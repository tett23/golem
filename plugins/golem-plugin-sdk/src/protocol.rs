//! Requests, responses and the description of golem-doc.cddl (golem-plugin
//! ADR 0001, golem-doc ADR 0007, docs/adr/0105).

use crate::cbor::{DecodeError, Value};
use crate::ir::{self, Document, Inline, Span};

type R<T> = Result<T, DecodeError>;

/// `value = int64 / rational / tstr / bool / null / range / [* value]`
#[derive(Clone, Debug, PartialEq)]
pub enum ArgValue {
    Int(i64),
    /// in lowest terms, the denominator 1 or more (tag 30, docs/adr/0101)
    Rational(i64, i64),
    Str(String),
    Bool(bool),
    Null,
    /// the closed range `first...last`, both ends in, `first <= last`:
    /// `{"first": int64, "last": int64}` (docs/adr/0113)
    Range(i64, i64),
    Array(Vec<ArgValue>),
}

/// `argument = [0, value] / [1, key, value]`
#[derive(Clone, Debug, PartialEq)]
pub enum Arg {
    Positional(ArgValue),
    Keyword(String, ArgValue),
}

/// The data the project passes to the plugin (docs/adr/0105): each name of
/// `[plugins.<name>.data]` the manifest gives, with the bytes of its file,
/// in the order of the names.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Data(pub Vec<(String, Vec<u8>)>);

impl Data {
    /// The bytes of a name, if the project passes it.
    pub fn get(&self, name: &str) -> Option<&[u8]> {
        self.0.iter().find(|(n, _)| n == name).map(|(_, b)| b.as_slice())
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct CommandRequest {
    pub name: String,
    pub args: Vec<Arg>,
    /// the prose slots, evaluated
    pub slots: Vec<Vec<Inline>>,
    /// where the command is called; the span of what the plugin makes
    pub span: Span,
    pub data: Data,
}

#[derive(Clone, Debug, PartialEq)]
pub struct FilterRequest {
    pub name: String,
    pub document: Document,
    pub data: Data,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Request {
    Command(CommandRequest),
    Filter(FilterRequest),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Severity {
    Error,
    Warning,
}

/// `plugin-diagnostic = [code, severity, span, message]`
#[derive(Clone, Debug, PartialEq)]
pub struct Diagnostic {
    pub code: String,
    pub severity: Severity,
    pub span: Span,
    pub message: String,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Output {
    Inlines(Vec<Inline>),
    Document(Document),
}

/// `response = [output, diagnostics]`
#[derive(Clone, Debug, PartialEq)]
pub struct Response {
    pub output: Output,
    pub diagnostics: Vec<Diagnostic>,
}

impl Response {
    pub fn inlines(xs: Vec<Inline>) -> Self {
        Response { output: Output::Inlines(xs), diagnostics: vec![] }
    }

    pub fn document(d: Document) -> Self {
        Response { output: Output::Document(d), diagnostics: vec![] }
    }

    pub fn with(mut self, d: Diagnostic) -> Self {
        self.diagnostics.push(d);
        self
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ChannelOrder {
    Document,
    Reading,
}

/// `channel-decl = [name, order, locators]`
#[derive(Clone, Debug, PartialEq)]
pub struct ChannelDecl {
    pub name: String,
    pub order: ChannelOrder,
    pub locators: bool,
}

/// `description = [commands, filters, channels, data]`
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Description {
    pub commands: Vec<String>,
    pub filters: Vec<String>,
    pub channels: Vec<ChannelDecl>,
    /// the names of the data the plugin takes (docs/adr/0105)
    pub data: Vec<String>,
}

fn texts(xs: &[String]) -> Value {
    Value::Array(xs.iter().map(|s| Value::Text(s.clone())).collect())
}

pub fn description_value(d: &Description) -> Value {
    Value::Array(vec![
        texts(&d.commands),
        texts(&d.filters),
        Value::Array(
            d.channels
                .iter()
                .map(|c| {
                    Value::Array(vec![
                        Value::Text(c.name.clone()),
                        Value::Int(match c.order {
                            ChannelOrder::Document => 0,
                            ChannelOrder::Reading => 1,
                        }),
                        Value::Bool(c.locators),
                    ])
                })
                .collect(),
        ),
        texts(&d.data),
    ])
}

pub fn response_value(r: &Response) -> Value {
    let out = match &r.output {
        Output::Inlines(xs) => ir::inlines_value(xs),
        Output::Document(d) => ir::document_value(d),
    };
    Value::Array(vec![
        out,
        Value::Array(
            r.diagnostics
                .iter()
                .map(|d| {
                    Value::Array(vec![
                        Value::Text(d.code.clone()),
                        Value::Int(match d.severity {
                            Severity::Error => 0,
                            Severity::Warning => 1,
                        }),
                        ir::span_value(d.span),
                        Value::Text(d.message.clone()),
                    ])
                })
                .collect(),
        ),
    ])
}

fn int64(i: i128) -> bool {
    i >= i64::MIN as i128 && i <= i64::MAX as i128
}

fn arg_value_of(v: &Value) -> R<ArgValue> {
    Ok(match v {
        Value::Int(i) if *i >= i64::MIN as i128 && *i <= i64::MAX as i128 => ArgValue::Int(*i as i64),
        Value::Tag(30, x) => match &**x {
            Value::Array(nd) => match nd.as_slice() {
                [Value::Int(n), Value::Int(d)] if *d >= 1 => ArgValue::Rational(*n as i64, *d as i64),
                _ => return Err(DecodeError::Shape("rational")),
            },
            _ => return Err(DecodeError::Shape("rational")),
        },
        Value::Text(s) => ArgValue::Str(s.clone()),
        Value::Bool(b) => ArgValue::Bool(*b),
        Value::Null => ArgValue::Null,
        Value::Array(xs) => ArgValue::Array(xs.iter().map(arg_value_of).collect::<R<_>>()?),
        Value::Map(kvs) => match kvs.as_slice() {
            [(Value::Text(f), Value::Int(a)), (Value::Text(l), Value::Int(b))]
                if f == "first" && l == "last" && int64(*a) && int64(*b) && a <= b =>
            {
                ArgValue::Range(*a as i64, *b as i64)
            }
            _ => return Err(DecodeError::Shape("range")),
        },
        _ => return Err(DecodeError::Shape("value")),
    })
}

fn data_of(v: &Value) -> R<Data> {
    match v {
        Value::Array(xs) => Ok(Data(
            xs.iter()
                .map(|e| match e {
                    Value::Array(p) => match p.as_slice() {
                        [Value::Text(n), Value::Bytes(b)] => Ok((n.clone(), b.clone())),
                        _ => Err(DecodeError::Shape("data entry")),
                    },
                    _ => Err(DecodeError::Shape("data entry")),
                })
                .collect::<R<_>>()?,
        )),
        _ => Err(DecodeError::Shape("data")),
    }
}

pub fn request_of(v: &Value) -> R<Request> {
    let xs = match v {
        Value::Array(xs) => xs.as_slice(),
        _ => return Err(DecodeError::Shape("request")),
    };
    match xs {
        [Value::Int(0), name, Value::Array(args), Value::Array(slots), span, data] => Ok(Request::Command(CommandRequest {
            name: ir::text_of(name)?,
            args: args
                .iter()
                .map(|a| match a {
                    Value::Array(p) => match p.as_slice() {
                        [Value::Int(0), x] => Ok(Arg::Positional(arg_value_of(x)?)),
                        [Value::Int(1), k, x] => Ok(Arg::Keyword(ir::text_of(k)?, arg_value_of(x)?)),
                        _ => Err(DecodeError::Shape("argument")),
                    },
                    _ => Err(DecodeError::Shape("argument")),
                })
                .collect::<R<_>>()?,
            slots: slots.iter().map(ir::inlines_of).collect::<R<_>>()?,
            span: ir::span_of(span)?,
            data: data_of(data)?,
        })),
        [Value::Int(1), name, doc, data] => Ok(Request::Filter(FilterRequest {
            name: ir::text_of(name)?,
            document: ir::document_of(doc)?,
            data: data_of(data)?,
        })),
        _ => Err(DecodeError::Shape("request")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cbor::decode;

    fn range(first: Value, last: Value) -> Value {
        Value::Map(vec![(Value::Text("first".into()), first), (Value::Text("last".into()), last)])
    }

    #[test]
    fn reads_a_range_as_a_map_of_first_and_last() {
        assert_eq!(arg_value_of(&range(Value::Int(1), Value::Int(3))), Ok(ArgValue::Range(1, 3)));
        assert_eq!(arg_value_of(&range(Value::Int(2), Value::Int(2))), Ok(ArgValue::Range(2, 2)));
        // {"first": 1, "last": 10}
        let bytes = [0xa2, 0x65, b'f', b'i', b'r', b's', b't', 0x01, 0x64, b'l', b'a', b's', b't', 0x0a];
        assert_eq!(arg_value_of(&decode(&bytes).unwrap()), Ok(ArgValue::Range(1, 10)));
    }

    #[test]
    fn rejects_other_maps() {
        assert!(arg_value_of(&range(Value::Int(3), Value::Int(1))).is_err());
        assert!(arg_value_of(&Value::Map(vec![(Value::Text("last".into()), Value::Int(3)), (Value::Text("first".into()), Value::Int(1))])).is_err());
        assert!(arg_value_of(&Value::Map(vec![(Value::Text("first".into()), Value::Int(1))])).is_err());
        assert!(arg_value_of(&range(Value::Int(1), Value::Int(i64::MAX as i128 + 1))).is_err());
    }

    #[test]
    fn reads_the_data_of_a_command_request() {
        let span = ir::span_value(Span { file: 1, start: 0, end: 4 });
        let data = Value::Array(vec![Value::Array(vec![Value::Text("table".into()), Value::Bytes(b"k\tv".to_vec())])]);
        let req = Value::Array(vec![Value::Int(0), Value::Text("c".into()), Value::Array(vec![]), Value::Array(vec![]), span, data]);
        match request_of(&req) {
            Ok(Request::Command(c)) => assert_eq!(c.data.get("table"), Some(&b"k\tv"[..])),
            other => panic!("{other:?}"),
        }
    }
}
