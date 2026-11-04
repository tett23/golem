//! CBOR (RFC 8949) as the host writes it: definite lengths, the shortest
//! heads (the deterministic encoding of section 4.2.1). The decoder reads
//! definite lengths only and refuses trailing bytes; the encoder writes the
//! shortest form, so the same value is always the same bytes.

use std::fmt;

/// A CBOR data item. Integers are kept in an `i128`, which holds every
/// CBOR integer (-2^64 .. 2^64-1).
#[derive(Clone, Debug, PartialEq)]
pub enum Value {
    Int(i128),
    Bytes(Vec<u8>),
    Text(String),
    Array(Vec<Value>),
    Map(Vec<(Value, Value)>),
    Tag(u64, Box<Value>),
    Bool(bool),
    Null,
    Float(f64),
}

/// Why bytes are not one CBOR item.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum DecodeError {
    /// the bytes end inside an item
    Eof,
    /// bytes after the item
    Trailing,
    /// an indefinite length, a reserved additional value, undefined or a simple value
    Unsupported(u8),
    /// a text string that is not UTF-8
    Utf8,
    /// a well-formed item of the wrong shape for the IR
    Shape(&'static str),
}

impl fmt::Display for DecodeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            DecodeError::Eof => write!(f, "unexpected end of CBOR"),
            DecodeError::Trailing => write!(f, "bytes after the CBOR item"),
            DecodeError::Unsupported(b) => write!(f, "unsupported CBOR initial byte {b:#04x}"),
            DecodeError::Utf8 => write!(f, "text string is not UTF-8"),
            DecodeError::Shape(s) => write!(f, "unexpected shape: {s}"),
        }
    }
}

/// Decodes exactly one item.
pub fn decode(bytes: &[u8]) -> Result<Value, DecodeError> {
    let mut d = Decoder { bytes, pos: 0 };
    let v = d.item()?;
    if d.pos != bytes.len() {
        return Err(DecodeError::Trailing);
    }
    Ok(v)
}

/// Encodes one item in the deterministic encoding.
pub fn encode(v: &Value) -> Vec<u8> {
    let mut out = Vec::new();
    encode_into(v, &mut out);
    out
}

pub fn encode_into(v: &Value, out: &mut Vec<u8>) {
    match v {
        Value::Int(i) if *i >= 0 => head(0, *i as u64, out),
        Value::Int(i) => head(1, (-1 - *i) as u64, out),
        Value::Bytes(b) => {
            head(2, b.len() as u64, out);
            out.extend_from_slice(b);
        }
        Value::Text(s) => {
            head(3, s.len() as u64, out);
            out.extend_from_slice(s.as_bytes());
        }
        Value::Array(xs) => {
            head(4, xs.len() as u64, out);
            for x in xs {
                encode_into(x, out);
            }
        }
        Value::Map(kvs) => {
            head(5, kvs.len() as u64, out);
            for (k, x) in kvs {
                encode_into(k, out);
                encode_into(x, out);
            }
        }
        Value::Tag(t, x) => {
            head(6, *t, out);
            encode_into(x, out);
        }
        Value::Bool(false) => out.push(0xf4),
        Value::Bool(true) => out.push(0xf5),
        Value::Null => out.push(0xf6),
        Value::Float(x) => {
            let single = *x as f32;
            if (single as f64).to_bits() == x.to_bits() || (x.is_nan() && single.is_nan()) {
                out.push(0xfa);
                out.extend_from_slice(&single.to_bits().to_be_bytes());
            } else {
                out.push(0xfb);
                out.extend_from_slice(&x.to_bits().to_be_bytes());
            }
        }
    }
}

fn head(major: u8, n: u64, out: &mut Vec<u8>) {
    let m = major << 5;
    if n < 24 {
        out.push(m | n as u8);
    } else if n <= 0xff {
        out.push(m | 24);
        out.push(n as u8);
    } else if n <= 0xffff {
        out.push(m | 25);
        out.extend_from_slice(&(n as u16).to_be_bytes());
    } else if n <= 0xffff_ffff {
        out.push(m | 26);
        out.extend_from_slice(&(n as u32).to_be_bytes());
    } else {
        out.push(m | 27);
        out.extend_from_slice(&n.to_be_bytes());
    }
}

struct Decoder<'a> {
    bytes: &'a [u8],
    pos: usize,
}

impl<'a> Decoder<'a> {
    fn take(&mut self, n: usize) -> Result<&'a [u8], DecodeError> {
        let end = self.pos.checked_add(n).ok_or(DecodeError::Eof)?;
        if end > self.bytes.len() {
            return Err(DecodeError::Eof);
        }
        let s = &self.bytes[self.pos..end];
        self.pos = end;
        Ok(s)
    }

    fn argument(&mut self, initial: u8) -> Result<u64, DecodeError> {
        let info = initial & 0x1f;
        Ok(match info {
            0..=23 => info as u64,
            24 => self.take(1)?[0] as u64,
            25 => u16::from_be_bytes(self.take(2)?.try_into().unwrap()) as u64,
            26 => u32::from_be_bytes(self.take(4)?.try_into().unwrap()) as u64,
            27 => u64::from_be_bytes(self.take(8)?.try_into().unwrap()),
            _ => return Err(DecodeError::Unsupported(initial)),
        })
    }

    fn len(&mut self, initial: u8) -> Result<usize, DecodeError> {
        let n = self.argument(initial)?;
        // every item takes at least one byte, so a longer length cannot be right
        if n > (self.bytes.len() - self.pos) as u64 {
            return Err(DecodeError::Eof);
        }
        Ok(n as usize)
    }

    fn item(&mut self) -> Result<Value, DecodeError> {
        let initial = self.take(1)?[0];
        match initial >> 5 {
            0 => Ok(Value::Int(self.argument(initial)? as i128)),
            1 => Ok(Value::Int(-1 - self.argument(initial)? as i128)),
            2 => {
                let n = self.len(initial)?;
                Ok(Value::Bytes(self.take(n)?.to_vec()))
            }
            3 => {
                let n = self.len(initial)?;
                let s = std::str::from_utf8(self.take(n)?).map_err(|_| DecodeError::Utf8)?;
                Ok(Value::Text(s.to_owned()))
            }
            4 => {
                let n = self.len(initial)?;
                let mut xs = Vec::with_capacity(n);
                for _ in 0..n {
                    xs.push(self.item()?);
                }
                Ok(Value::Array(xs))
            }
            5 => {
                let n = self.len(initial)?;
                let mut kvs = Vec::with_capacity(n);
                for _ in 0..n {
                    let k = self.item()?;
                    let v = self.item()?;
                    kvs.push((k, v));
                }
                Ok(Value::Map(kvs))
            }
            6 => {
                let t = self.argument(initial)?;
                Ok(Value::Tag(t, Box::new(self.item()?)))
            }
            _ => match initial {
                0xf4 => Ok(Value::Bool(false)),
                0xf5 => Ok(Value::Bool(true)),
                0xf6 => Ok(Value::Null),
                0xf9 => {
                    let h = u16::from_be_bytes(self.take(2)?.try_into().unwrap());
                    Ok(Value::Float(half_to_f64(h)))
                }
                0xfa => Ok(Value::Float(f32::from_bits(u32::from_be_bytes(self.take(4)?.try_into().unwrap())) as f64)),
                0xfb => Ok(Value::Float(f64::from_bits(u64::from_be_bytes(self.take(8)?.try_into().unwrap())))),
                _ => Err(DecodeError::Unsupported(initial)),
            },
        }
    }
}

fn half_to_f64(h: u16) -> f64 {
    let sign = if h & 0x8000 != 0 { -1.0 } else { 1.0 };
    let exp = ((h >> 10) & 0x1f) as i32;
    let mant = (h & 0x3ff) as f64;
    sign * match exp {
        0 => mant * 2f64.powi(-24),
        31 if mant == 0.0 => f64::INFINITY,
        31 => f64::NAN,
        _ => (1.0 + mant / 1024.0) * 2f64.powi(exp - 15),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn roundtrip(v: Value, bytes: &[u8]) {
        assert_eq!(encode(&v), bytes, "encode {v:?}");
        assert_eq!(decode(bytes), Ok(v));
    }

    // the examples of RFC 8949, appendix A
    #[test]
    fn rfc_examples() {
        roundtrip(Value::Int(0), &[0x00]);
        roundtrip(Value::Int(23), &[0x17]);
        roundtrip(Value::Int(24), &[0x18, 0x18]);
        roundtrip(Value::Int(1000), &[0x19, 0x03, 0xe8]);
        roundtrip(Value::Int(1000000), &[0x1a, 0x00, 0x0f, 0x42, 0x40]);
        roundtrip(Value::Int(18446744073709551615), &[0x1b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]);
        roundtrip(Value::Int(-18446744073709551616), &[0x3b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]);
        roundtrip(Value::Int(-1), &[0x20]);
        roundtrip(Value::Int(-1000), &[0x39, 0x03, 0xe7]);
        roundtrip(Value::Float(1.1), &[0xfb, 0x3f, 0xf1, 0x99, 0x99, 0x99, 0x99, 0x99, 0x9a]);
        roundtrip(Value::Float(100000.0), &[0xfa, 0x47, 0xc3, 0x50, 0x00]);
        roundtrip(Value::Bool(false), &[0xf4]);
        roundtrip(Value::Null, &[0xf6]);
        roundtrip(Value::Bytes(vec![1, 2, 3, 4]), &[0x44, 1, 2, 3, 4]);
        roundtrip(Value::Text("\u{6c34}".into()), &[0x63, 0xe6, 0xb0, 0xb4]);
        roundtrip(
            Value::Array(vec![Value::Int(1), Value::Array(vec![Value::Int(2), Value::Int(3)])]),
            &[0x82, 0x01, 0x82, 0x02, 0x03],
        );
        roundtrip(Value::Tag(30, Box::new(Value::Array(vec![Value::Int(1), Value::Int(2)]))), &[0xd8, 0x1e, 0x82, 0x01, 0x02]);
        assert_eq!(decode(&[0xf9, 0x3c, 0x00]), Ok(Value::Float(1.0)));
        assert_eq!(decode(&[0xf9, 0xfc, 0x00]), Ok(Value::Float(f64::NEG_INFINITY)));
    }

    #[test]
    fn errors() {
        assert_eq!(decode(&[0x82, 0x01]), Err(DecodeError::Eof));
        assert_eq!(decode(&[0x01, 0x02]), Err(DecodeError::Trailing));
        assert_eq!(decode(&[0x9f, 0xff]), Err(DecodeError::Unsupported(0x9f)));
        assert_eq!(decode(&[0x62, 0xff, 0xfe]), Err(DecodeError::Utf8));
        assert_eq!(decode(&[0x9b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]), Err(DecodeError::Eof));
        assert_eq!(decode(&[0xf7]), Err(DecodeError::Unsupported(0xf7)));
    }
}
