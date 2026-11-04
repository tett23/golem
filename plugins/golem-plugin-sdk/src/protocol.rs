//! Requests, responses and the description of golem-doc.cddl (golem-plugin
//! ADR 0001, golem-doc ADR 0007, docs/adr/0105).

use crate::cbor::{DecodeError, Value};
use crate::ir::{self, Block, Document, Inline, Span};

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

/// The context of the book the plugin asked for in its description
/// (docs/adr/0121): each name with its value, in the order of the names.
/// `writing-mode` is `horizontal` or `vertical`; `vertical-numbers` is
/// `kanji`, `kanji-digits`, `tcy`, `auto` or `auto-digits`.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Context(pub Vec<(String, String)>);

impl Context {
    /// The value of a name, if the plugin asked for it.
    pub fn get(&self, name: &str) -> Option<&str> {
        self.0.iter().find(|(n, _)| n == name).map(|(_, v)| v.as_str())
    }

    /// Whether the book is set in vertical writing; None when the plugin
    /// did not ask for `writing-mode`.
    pub fn vertical(&self) -> Option<bool> {
        self.get("writing-mode").map(|m| m == "vertical")
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
    pub context: Context,
    pub data: Data,
}

#[derive(Clone, Debug, PartialEq)]
pub struct FilterRequest {
    pub name: String,
    pub document: Document,
    pub context: Context,
    pub data: Data,
}

/// The request of a block command, `@name` at the start of a line
/// (docs/adr/0122): its arguments and its body, evaluated.
#[derive(Clone, Debug, PartialEq)]
pub struct BlockCommandRequest {
    pub name: String,
    pub args: Vec<Arg>,
    /// the indented lines after `@name`, evaluated as blocks
    pub body: Vec<Block>,
    /// where the command is called; the span of what the plugin makes
    pub span: Span,
    pub context: Context,
    pub data: Data,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Request {
    Command(CommandRequest),
    Filter(FilterRequest),
    Block(BlockCommandRequest),
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

/// `data-diagnostic = [code, severity, name, line, message]`: an error or a
/// warning of the data, at a line of the file of the data `name` (counted
/// from 1), or at its top when `line` is None (docs/adr/0120).
#[derive(Clone, Debug, PartialEq)]
pub struct DataDiagnostic {
    pub code: String,
    pub severity: Severity,
    pub name: String,
    pub line: Option<u64>,
    pub message: String,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Output {
    Inlines(Vec<Inline>),
    Document(Document),
    /// the output of a block command (docs/adr/0122): its blocks and the
    /// images of its figures (docs/adr/0123)
    Blocks(Vec<Block>, Vec<Image>),
}

/// The format of an image a plugin makes for a figure (docs/adr/0123).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ImageFormat {
    Svg,
    Png,
    Jpeg,
}

/// `plugin-image = [name, format, bytes]`: a figure of the output points at
/// it with the source `plugin:<name>` ([`ir::figure`], docs/adr/0123).
#[derive(Clone, Debug, PartialEq)]
pub struct Image {
    pub name: String,
    pub format: ImageFormat,
    pub bytes: Vec<u8>,
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

    /// The answer of a block command (docs/adr/0122).
    pub fn blocks(bs: Vec<Block>) -> Self {
        Response { output: Output::Blocks(bs, vec![]), diagnostics: vec![] }
    }

    /// Blocks with the images their figures point at (docs/adr/0123).
    pub fn blocks_with_images(bs: Vec<Block>, images: Vec<Image>) -> Self {
        Response { output: Output::Blocks(bs, images), diagnostics: vec![] }
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

/// `description = {? "commands", ? "filters", ? "channels", ? "data", ? "context", ? "blocks"}`
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Description {
    pub commands: Vec<String>,
    pub filters: Vec<String>,
    pub channels: Vec<ChannelDecl>,
    /// the names of the data the plugin takes (docs/adr/0105)
    pub data: Vec<String>,
    /// the names of the context of the book it asks for (docs/adr/0121):
    /// `writing-mode`, `vertical-numbers`
    pub context: Vec<String>,
    /// the block commands it provides, `@name` (docs/adr/0122)
    pub blocks: Vec<String>,
}

fn texts(xs: &[String]) -> Value {
    Value::Array(xs.iter().map(|s| Value::Text(s.clone())).collect())
}

/// The description as a map of its fields that are not empty, in the order
/// of RFC 8949 4.2.1: shorter keys first, then by their bytes
/// (docs/adr/0107). A field left out is empty for the host.
pub fn description_value(d: &Description) -> Value {
    let channels = d
        .channels
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
        .collect::<Vec<_>>();
    // already in the order of 4.2.1
    let mut fields = vec![
        ("data", texts(&d.data)),
        ("blocks", texts(&d.blocks)),
        ("context", texts(&d.context)),
        ("filters", texts(&d.filters)),
        ("channels", Value::Array(channels)),
        ("commands", texts(&d.commands)),
    ];
    fields.retain(|(_, v)| !matches!(v, Value::Array(xs) if xs.is_empty()));
    Value::Map(fields.into_iter().map(|(k, v)| (Value::Text(k.into()), v)).collect())
}

pub fn response_value(r: &Response) -> Value {
    let out = match &r.output {
        Output::Inlines(xs) => ir::inlines_value(xs),
        Output::Document(d) => ir::document_value(d),
        Output::Blocks(bs, images) => Value::Array(vec![
            ir::blocks_value(bs),
            Value::Array(
                images
                    .iter()
                    .map(|i| {
                        Value::Array(vec![
                            Value::Text(i.name.clone()),
                            Value::Text(
                                match i.format {
                                    ImageFormat::Svg => "svg",
                                    ImageFormat::Png => "png",
                                    ImageFormat::Jpeg => "jpeg",
                                }
                                .into(),
                            ),
                            Value::Bytes(i.bytes.clone()),
                        ])
                    })
                    .collect(),
            ),
        ]),
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

/// The response of `golem_check_data`: `[* data-diagnostic]` (docs/adr/0120).
pub fn data_diagnostics_value(ds: &[DataDiagnostic]) -> Value {
    Value::Array(
        ds.iter()
            .map(|d| {
                Value::Array(vec![
                    Value::Text(d.code.clone()),
                    Value::Int(match d.severity {
                        Severity::Error => 0,
                        Severity::Warning => 1,
                    }),
                    Value::Text(d.name.clone()),
                    d.line.map_or(Value::Null, |l| Value::Int(l as i128)),
                    Value::Text(d.message.clone()),
                ])
            })
            .collect(),
    )
}

/// The request of `golem_check_data`: `[data]` (docs/adr/0120).
pub fn check_data_request_of(v: &Value) -> R<Data> {
    match v {
        Value::Array(xs) => match xs.as_slice() {
            [data] => data_of(data),
            _ => Err(DecodeError::Shape("check-data request")),
        },
        _ => Err(DecodeError::Shape("check-data request")),
    }
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

fn context_of(v: &Value) -> R<Context> {
    match v {
        Value::Array(xs) => Ok(Context(
            xs.iter()
                .map(|e| match e {
                    Value::Array(p) => match p.as_slice() {
                        [Value::Text(n), Value::Text(x)] => Ok((n.clone(), x.clone())),
                        _ => Err(DecodeError::Shape("context entry")),
                    },
                    _ => Err(DecodeError::Shape("context entry")),
                })
                .collect::<R<_>>()?,
        )),
        _ => Err(DecodeError::Shape("context")),
    }
}

pub fn request_of(v: &Value) -> R<Request> {
    let xs = match v {
        Value::Array(xs) => xs.as_slice(),
        _ => return Err(DecodeError::Shape("request")),
    };
    match xs {
        [Value::Int(0), name, Value::Array(args), Value::Array(slots), span, context, data] => Ok(Request::Command(CommandRequest {
            name: ir::text_of(name)?,
            args: args_of(args)?,
            slots: slots.iter().map(ir::inlines_of).collect::<R<_>>()?,
            span: ir::span_of(span)?,
            context: context_of(context)?,
            data: data_of(data)?,
        })),
        [Value::Int(1), name, doc, context, data] => Ok(Request::Filter(FilterRequest {
            name: ir::text_of(name)?,
            document: ir::document_of(doc)?,
            context: context_of(context)?,
            data: data_of(data)?,
        })),
        [Value::Int(2), name, Value::Array(args), body, span, context, data] => Ok(Request::Block(BlockCommandRequest {
            name: ir::text_of(name)?,
            args: args_of(args)?,
            body: ir::blocks_of(body)?,
            span: ir::span_of(span)?,
            context: context_of(context)?,
            data: data_of(data)?,
        })),
        _ => Err(DecodeError::Shape("request")),
    }
}

fn args_of(args: &[Value]) -> R<Vec<Arg>> {
    args.iter()
        .map(|a| match a {
            Value::Array(p) => match p.as_slice() {
                [Value::Int(0), x] => Ok(Arg::Positional(arg_value_of(x)?)),
                [Value::Int(1), k, x] => Ok(Arg::Keyword(ir::text_of(k)?, arg_value_of(x)?)),
                _ => Err(DecodeError::Shape("argument")),
            },
            _ => Err(DecodeError::Shape("argument")),
        })
        .collect()
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
        let req = Value::Array(vec![Value::Int(0), Value::Text("c".into()), Value::Array(vec![]), Value::Array(vec![]), span, Value::Array(vec![]), data]);
        match request_of(&req) {
            Ok(Request::Command(c)) => assert_eq!(c.data.get("table"), Some(&b"k\tv"[..])),
            other => panic!("{other:?}"),
        }
    }

    #[test]
    fn describes_the_fields_that_are_not_empty_in_the_order_of_4_2_1() {
        let d = Description {
            commands: vec!["c".into()],
            filters: vec![],
            channels: vec![ChannelDecl { name: "glossary".into(), order: ChannelOrder::Reading, locators: false }],
            data: vec!["table".into()],
            context: vec!["writing-mode".into()],
            blocks: vec!["grid".into()],
        };
        let key = |k: &str| Value::Text(k.into());
        let channel = Value::Array(vec![Value::Text("glossary".into()), Value::Int(1), Value::Bool(false)]);
        assert_eq!(
            description_value(&d),
            Value::Map(vec![
                (key("data"), Value::Array(vec![Value::Text("table".into())])),
                (key("blocks"), Value::Array(vec![Value::Text("grid".into())])),
                (key("context"), Value::Array(vec![Value::Text("writing-mode".into())])),
                (key("channels"), Value::Array(vec![channel])),
                (key("commands"), Value::Array(vec![Value::Text("c".into())])),
            ])
        );
        assert_eq!(description_value(&Description::default()), Value::Map(vec![]));
        assert_eq!(crate::cbor::encode(&description_value(&Description::default())), vec![0xa0]);
    }

    fn t(s: &str) -> Value {
        Value::Text(s.into())
    }

    #[test]
    fn a_command_request_has_the_context_before_the_data() {
        let v = Value::Array(vec![
            Value::Int(0),
            t("x"),
            Value::Array(vec![]),
            Value::Array(vec![]),
            Value::Array(vec![Value::Int(1), Value::Int(0), Value::Int(3)]),
            Value::Array(vec![Value::Array(vec![t("writing-mode"), t("vertical")])]),
            Value::Array(vec![Value::Array(vec![t("d"), Value::Bytes(b"1".to_vec())])]),
        ]);
        match request_of(&v).unwrap() {
            Request::Command(c) => {
                assert_eq!(c.context.get("writing-mode"), Some("vertical"));
                assert_eq!(c.context.vertical(), Some(true));
                assert_eq!(c.context.get("vertical-numbers"), None);
                assert_eq!(c.data.get("d"), Some(&b"1"[..]));
            }
            _ => panic!(),
        }
    }

    #[test]
    fn a_request_without_the_context_is_no_request() {
        let v = Value::Array(vec![Value::Int(1), t("f"), Value::Array(vec![Value::Int(8), Value::Int(0), Value::Array(vec![])]), Value::Array(vec![])]);
        assert!(request_of(&v).is_err());
    }

    #[test]
    fn reads_the_request_of_a_check_of_the_data_and_writes_its_answer() {
        let req = Value::Array(vec![Value::Array(vec![Value::Array(vec![t("terms"), Value::Bytes(b"a".to_vec())])])]);
        assert_eq!(check_data_request_of(&req), Ok(Data(vec![("terms".into(), b"a".to_vec())])));
        assert!(check_data_request_of(&Value::Array(vec![])).is_err());
        let ds = vec![
            DataDiagnostic { code: "tsv-columns".into(), severity: Severity::Error, name: "terms".into(), line: Some(7), message: "m".into() },
            DataDiagnostic { code: "utf8".into(), severity: Severity::Warning, name: "terms".into(), line: None, message: "n".into() },
        ];
        assert_eq!(
            data_diagnostics_value(&ds),
            Value::Array(vec![
                Value::Array(vec![t("tsv-columns"), Value::Int(0), t("terms"), Value::Int(7), t("m")]),
                Value::Array(vec![t("utf8"), Value::Int(1), t("terms"), Value::Null, t("n")]),
            ])
        );
    }

    #[test]
    fn reads_the_request_of_a_block_command() {
        let span = Value::Array(vec![Value::Int(1), Value::Int(0), Value::Int(6)]);
        let v = Value::Array(vec![
            Value::Int(2),
            t("grid"),
            Value::Array(vec![Value::Array(vec![Value::Int(1), t("align"), t("left")])]),
            Value::Array(vec![]),
            span,
            Value::Array(vec![]),
            Value::Array(vec![]),
        ]);
        match request_of(&v).unwrap() {
            Request::Block(b) => {
                assert_eq!(b.name, "grid");
                assert_eq!(b.args, vec![Arg::Keyword("align".into(), ArgValue::Str("left".into()))]);
                assert!(b.body.is_empty());
                assert_eq!(b.span, Span { file: 1, start: 0, end: 6 });
            }
            other => panic!("{other:?}"),
        }
    }

    #[test]
    fn a_block_command_answers_with_blocks_and_images() {
        let r = Response::blocks(vec![]);
        assert_eq!(response_value(&r), Value::Array(vec![Value::Array(vec![Value::Array(vec![]), Value::Array(vec![])]), Value::Array(vec![])]));
        let img = Image { name: "chart".into(), format: ImageFormat::Svg, bytes: b"<svg/>".to_vec() };
        match response_value(&Response::blocks_with_images(vec![], vec![img])) {
            Value::Array(xs) => assert_eq!(
                xs[0],
                Value::Array(vec![
                    Value::Array(vec![]),
                    Value::Array(vec![Value::Array(vec![t("chart"), t("svg"), Value::Bytes(b"<svg/>".to_vec())])])
                ])
            ),
            other => panic!("{other:?}"),
        }
    }
}
