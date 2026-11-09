//! The semantic IR of modules/golem-doc/schema/golem-doc.cddl as Rust
//! types. The parts a plugin edits (inlines, paragraphs, headings, lists,
//! definition lists, tables) are typed; the rest is kept as the CBOR
//! value it came in as and written back unchanged (`BlockBody::Other`,
//! the heading attributes, deferred expressions).

use crate::cbor::{DecodeError, Value};

/// The ABI version this crate speaks (golem-plugin ADR 0001, docs/adr/0052).
pub const ABI_VERSION: u32 = 9;

/// A length in sp, the unit of lengths of Golem (golem-syntax's `Sp`):
/// the `sp` of an aki.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Sp(pub u64);

/// `span = [file, start, end]`: byte offsets of a source file.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct Span {
    pub file: u64,
    pub start: u64,
    pub end: u64,
}

#[derive(Clone, Debug, PartialEq)]
pub struct RubySegment {
    pub base: Vec<Inline>,
    pub reading: Option<String>,
}

/// `number-style = 0..2`
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NumberStyle {
    Kanji,
    KanjiDigits,
    Tcy,
}

/// `ref-kind = 0..2`
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RefKind {
    Number,
    Title,
    Page,
}

/// An inline of the IR, with its tag in the CDDL.
#[derive(Clone, Debug, PartialEq)]
pub enum Inline {
    /// 0
    Text { span: Span, text: String },
    /// 4; its bases hold no ruby
    Ruby { span: Span, segments: Vec<RubySegment> },
    /// 5
    Kenten { span: Span, shape: Option<String>, body: Vec<Inline> },
    /// 6
    Color { span: Span, swatch: String, body: Vec<Inline> },
    /// 7
    CharStyle { span: Span, style: String, body: Vec<Inline> },
    /// 8
    Tcy { span: Span, text: String },
    /// 9
    Number { span: Span, value: i64, style: Option<NumberStyle> },
    /// 10
    Ref { span: Span, kind: RefKind, label: String },
    /// 11: the expression as it came in; a plugin may only pass it on
    Deferred { span: Span, expr: Value },
    /// 23 (docs/adr/0263): the body is paragraphs without a paragraph style
    Note { span: Span, number: u64, body: Vec<Block> },
    /// 24 (docs/adr/0263): the body is one paragraph without a paragraph style
    Sidenote { span: Span, number: u64, body: Vec<Block> },
    /// 14
    IndexMark { span: Span, terms: Vec<String>, readings: Vec<String> },
    /// 25 (docs/adr/0266): one item or more, their keys distinct; 15 is retired
    Cite { span: Span, items: Vec<CiteItem> },
    /// 16
    ProofComment { span: Span, text: String },
    /// 17
    LineBreak { span: Span },
    /// 18: zw as numerator and denominator, or sp; exactly one
    Aki { span: Span, zw: Option<(u64, u64)>, sp: Option<Sp> },
    /// 19 (golem-doc ADR 0007)
    ChannelItem { span: Span, channel: String, key: Option<String>, reading: Option<String>, body: Vec<Inline> },
    /// 20: a link to an external URL, as written (docs/adr ADR 0182)
    Link { span: Span, uri: String, body: Vec<Inline> },
    /// 21: a language span, the tag as written (docs/adr ADR 0187)
    Lang { span: Span, lang: String, body: Vec<Inline> },
}

impl Inline {
    pub fn span(&self) -> Span {
        match self {
            Inline::Text { span, .. }
            | Inline::Ruby { span, .. }
            | Inline::Kenten { span, .. }
            | Inline::Color { span, .. }
            | Inline::CharStyle { span, .. }
            | Inline::Tcy { span, .. }
            | Inline::Number { span, .. }
            | Inline::Ref { span, .. }
            | Inline::Deferred { span, .. }
            | Inline::Note { span, .. }
            | Inline::Sidenote { span, .. }
            | Inline::IndexMark { span, .. }
            | Inline::Cite { span, .. }
            | Inline::ProofComment { span, .. }
            | Inline::LineBreak { span }
            | Inline::Aki { span, .. }
            | Inline::ChannelItem { span, .. }
            | Inline::Link { span, .. }
            | Inline::Lang { span, .. } => *span,
        }
    }
}

/// An item of a citation (docs/adr/0266): the key, where in the work, the
/// text before and after. The host sets only a page and no prefix nor suffix yet.
#[derive(Clone, Debug, PartialEq)]
pub struct CiteItem {
    pub key: String,
    pub locator: Option<Locator>,
    pub prefix: Vec<Inline>,
    pub suffix: Vec<Inline>,
}

impl CiteItem {
    /// An item of a key alone.
    pub fn key(key: impl Into<String>) -> CiteItem {
        CiteItem { key: key.into(), locator: None, prefix: vec![], suffix: vec![] }
    }
}

/// Where in the cited work: a CSL locator term ("page", "chapter", ...) and its value.
#[derive(Clone, Debug, PartialEq)]
pub struct Locator {
    pub label: String,
    pub value: LocatorValue,
}

#[derive(Clone, Debug, PartialEq)]
pub enum LocatorValue {
    Number(u64),
    Range(u64, u64),
    Text(String),
}

#[derive(Clone, Debug, PartialEq)]
pub struct ListItem {
    pub number: Option<u64>,
    pub blocks: Vec<Block>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct DefGroup {
    pub terms: Vec<Vec<Inline>>,
    pub defs: Vec<Vec<Block>>,
}

#[derive(Clone, Debug, PartialEq)]
pub enum BlockBody {
    /// 1: level 1..6 (docs/adr/0188), the attributes as they came in
    Heading { level: u8, attrs: Value, inlines: Vec<Inline> },
    /// 2
    BulletList(Vec<ListItem>),
    /// 3
    OrderedList(Vec<ListItem>),
    /// 4
    DefList(Vec<DefGroup>),
    /// 14 (docs/adr/0262): alignments 0..3, the widths of the columns as
    /// they came in (`[]` is every column auto), the caption, whether a
    /// table with a caption goes without a number, the paragraph style of
    /// the cells (none for table), the header row and the rows of cells
    Table {
        alignments: Vec<u8>,
        widths: Vec<Value>,
        caption: Option<Vec<Inline>>,
        nonumber: bool,
        style: Option<String>,
        header: Vec<Vec<Inline>>,
        rows: Vec<Vec<Vec<Inline>>>,
    },
    /// 10: the paragraph style, none for body
    Paragraph { style: Option<String>, inlines: Vec<Inline> },
    /// any other body (code, figure, channel output, break, page control,
    /// blank lines) as it came in: `[tag, ...]`
    Other(Value),
}

#[derive(Clone, Debug, PartialEq)]
pub struct Block {
    pub span: Span,
    pub label: Option<String>,
    /// the language of the block, as written with @lang (docs/adr ADR 0187)
    pub lang: Option<String>,
    pub body: BlockBody,
}

/// `document = [abi-version, file, blocks]`
#[derive(Clone, Debug, PartialEq)]
pub struct Document {
    pub file: u64,
    pub blocks: Vec<Block>,
}

impl Document {
    /// Rewrites every run of inlines of the typed blocks: paragraphs,
    /// headings, list items, terms and definitions, table cells. The runs
    /// inside `BlockBody::Other` (figure captions, code) and the heading
    /// attributes are not visited.
    pub fn map_inlines(&mut self, f: &mut impl FnMut(Vec<Inline>) -> Vec<Inline>) {
        for b in &mut self.blocks {
            map_block(b, f);
        }
    }
}

fn run(f: &mut impl FnMut(Vec<Inline>) -> Vec<Inline>, xs: &mut Vec<Inline>) {
    *xs = f(std::mem::take(xs));
}

fn map_block(b: &mut Block, f: &mut impl FnMut(Vec<Inline>) -> Vec<Inline>) {
    match &mut b.body {
        BlockBody::Heading { inlines, .. } | BlockBody::Paragraph { inlines, .. } => run(f, inlines),
        BlockBody::BulletList(items) | BlockBody::OrderedList(items) => {
            for it in items {
                for c in &mut it.blocks {
                    map_block(c, f);
                }
            }
        }
        BlockBody::DefList(groups) => {
            for g in groups {
                for t in &mut g.terms {
                    run(f, t);
                }
                for d in &mut g.defs {
                    for c in d {
                        map_block(c, f);
                    }
                }
            }
        }
        BlockBody::Table { caption, header, rows, .. } => {
            if let Some(c) = caption {
                run(f, c);
            }
            for c in header {
                run(f, c);
            }
            for r in rows {
                for c in r {
                    run(f, c);
                }
            }
        }
        BlockBody::Other(_) => {}
    }
}

// ---- to CBOR ----

fn int<T: Into<i128>>(n: T) -> Value {
    Value::Int(n.into())
}

fn text(s: &str) -> Value {
    Value::Text(s.to_owned())
}

fn opt_text(s: &Option<String>) -> Value {
    s.as_deref().map_or(Value::Null, text)
}

pub fn span_value(s: Span) -> Value {
    Value::Array(vec![int(s.file), int(s.start), int(s.end)])
}

pub fn inlines_value(xs: &[Inline]) -> Value {
    Value::Array(xs.iter().map(inline_value).collect())
}

pub fn inline_value(x: &Inline) -> Value {
    let t = |tag: u8, span: &Span, rest: Vec<Value>| {
        let mut v = vec![int(tag), span_value(*span)];
        v.extend(rest);
        Value::Array(v)
    };
    match x {
        Inline::Text { span, text: s } => t(0, span, vec![text(s)]),
        Inline::Ruby { span, segments } => t(
            4,
            span,
            vec![Value::Array(segments.iter().map(|g| Value::Array(vec![inlines_value(&g.base), opt_text(&g.reading)])).collect())],
        ),
        Inline::Kenten { span, shape, body } => t(5, span, vec![opt_text(shape), inlines_value(body)]),
        Inline::Color { span, swatch, body } => t(6, span, vec![text(swatch), inlines_value(body)]),
        Inline::CharStyle { span, style, body } => t(7, span, vec![text(style), inlines_value(body)]),
        Inline::Tcy { span, text: s } => t(8, span, vec![text(s)]),
        Inline::Number { span, value, style } => t(
            9,
            span,
            vec![
                int(*value),
                style.map_or(Value::Null, |s| int(match s {
                    NumberStyle::Kanji => 0u8,
                    NumberStyle::KanjiDigits => 1,
                    NumberStyle::Tcy => 2,
                })),
            ],
        ),
        Inline::Ref { span, kind, label } => t(
            10,
            span,
            vec![
                int(match kind {
                    RefKind::Number => 0u8,
                    RefKind::Title => 1,
                    RefKind::Page => 2,
                }),
                text(label),
            ],
        ),
        Inline::Deferred { span, expr } => t(11, span, vec![expr.clone()]),
        Inline::Note { span, number, body } => t(23, span, vec![int(*number), blocks_value(body)]),
        Inline::Sidenote { span, number, body } => t(24, span, vec![int(*number), blocks_value(body)]),
        Inline::IndexMark { span, terms, readings } => t(
            14,
            span,
            vec![
                Value::Array(terms.iter().map(|s| text(s)).collect()),
                Value::Array(readings.iter().map(|s| text(s)).collect()),
            ],
        ),
        Inline::Cite { span, items } => t(25, span, vec![Value::Array(items.iter().map(cite_item_value).collect())]),
        Inline::ProofComment { span, text: s } => t(16, span, vec![text(s)]),
        Inline::LineBreak { span } => t(17, span, vec![]),
        Inline::Aki { span, zw, sp } => t(
            18,
            span,
            vec![
                zw.map_or(Value::Null, |(n, d)| Value::Array(vec![int(n), int(d)])),
                sp.map_or(Value::Null, |Sp(s)| int(s)),
            ],
        ),
        Inline::ChannelItem { span, channel, key, reading, body } => {
            t(19, span, vec![text(channel), opt_text(key), opt_text(reading), inlines_value(body)])
        }
        Inline::Link { span, uri, body } => t(20, span, vec![text(uri), inlines_value(body)]),
        Inline::Lang { span, lang, body } => t(21, span, vec![text(lang), inlines_value(body)]),
    }
}

pub fn block_value(b: &Block) -> Value {
    let body = match &b.body {
        BlockBody::Heading { level, attrs, inlines } => Value::Array(vec![int(1u8), int(*level), attrs.clone(), inlines_value(inlines)]),
        BlockBody::BulletList(items) => Value::Array(vec![int(2u8), items_value(items)]),
        BlockBody::OrderedList(items) => Value::Array(vec![int(3u8), items_value(items)]),
        BlockBody::DefList(groups) => Value::Array(vec![
            int(4u8),
            Value::Array(
                groups
                    .iter()
                    .map(|g| {
                        Value::Array(vec![
                            Value::Array(g.terms.iter().map(|t| inlines_value(t)).collect()),
                            Value::Array(g.defs.iter().map(|d| blocks_value(d)).collect()),
                        ])
                    })
                    .collect(),
            ),
        ]),
        BlockBody::Table { alignments, widths, caption, nonumber, style, header, rows } => Value::Array(vec![
            int(14u8),
            Value::Array(vec![
                Value::Array(alignments.iter().map(|a| int(*a)).collect()),
                Value::Array(widths.clone()),
                caption.as_ref().map_or(Value::Null, |c| inlines_value(c)),
                Value::Bool(*nonumber),
                opt_text(style),
                Value::Array(header.iter().map(|c| inlines_value(c)).collect()),
                Value::Array(rows.iter().map(|r| Value::Array(r.iter().map(|c| inlines_value(c)).collect())).collect()),
            ]),
        ]),
        BlockBody::Paragraph { style, inlines } => Value::Array(vec![int(10u8), opt_text(style), inlines_value(inlines)]),
        BlockBody::Other(v) => v.clone(),
    };
    Value::Array(vec![span_value(b.span), opt_text(&b.label), opt_text(&b.lang), body])
}

fn items_value(items: &[ListItem]) -> Value {
    Value::Array(
        items
            .iter()
            .map(|i| Value::Array(vec![i.number.map_or(Value::Null, int), blocks_value(&i.blocks)]))
            .collect(),
    )
}

/// A figure (tag 7) of an image the response carries: its source
/// `plugin:<image>`, no web image, the alt text and the caption; not
/// wrapped, of no width, not turned (docs/adr/0123), numbered
/// (docs/adr/0200).
pub fn figure(span: Span, image: &str, alt: &str, caption: Vec<Block>) -> Block {
    let body = Value::Array(vec![
        int(7u8),
        Value::Array(vec![
            text(&format!("plugin:{image}")),
            Value::Null,
            text(alt),
            Value::Null,
            Value::Null,
            blocks_value(&caption),
            Value::Null,
            Value::Bool(false),
            Value::Bool(false),
        ]),
    ]);
    Block { span, label: None, lang: None, body: BlockBody::Other(body) }
}

/// The body of a note of one paragraph without a paragraph style (docs/adr/0263).
pub fn note_body(span: Span, inlines: Vec<Inline>) -> Vec<Block> {
    vec![Block { span, label: None, lang: None, body: BlockBody::Paragraph { style: None, inlines } }]
}

/// The runs of inlines of the paragraphs of the body of a note (docs/adr/0263).
pub fn note_paragraphs_mut(body: &mut [Block]) -> impl Iterator<Item = &mut Vec<Inline>> {
    body.iter_mut().filter_map(|b| match &mut b.body {
        BlockBody::Paragraph { inlines, .. } => Some(inlines),
        _ => None,
    })
}

fn cite_item_value(i: &CiteItem) -> Value {
    let locator = i.locator.as_ref().map_or(Value::Null, |l| {
        let value = match &l.value {
            LocatorValue::Number(n) => Value::Array(vec![int(0u8), int(*n)]),
            LocatorValue::Range(a, b) => Value::Array(vec![int(1u8), int(*a), int(*b)]),
            LocatorValue::Text(t) => Value::Array(vec![int(2u8), text(t)]),
        };
        Value::Array(vec![text(&l.label), value])
    });
    Value::Array(vec![text(&i.key), locator, inlines_value(&i.prefix), inlines_value(&i.suffix)])
}

pub fn blocks_value(bs: &[Block]) -> Value {
    Value::Array(bs.iter().map(block_value).collect())
}

pub fn document_value(d: &Document) -> Value {
    Value::Array(vec![int(ABI_VERSION), int(d.file), blocks_value(&d.blocks)])
}

// ---- from CBOR ----

type R<T> = Result<T, DecodeError>;

fn arr(v: &Value) -> R<&[Value]> {
    match v {
        Value::Array(xs) => Ok(xs),
        _ => Err(DecodeError::Shape("array")),
    }
}

pub(crate) fn u64_of(v: &Value) -> R<u64> {
    match v {
        Value::Int(i) if *i >= 0 && *i <= u64::MAX as i128 => Ok(*i as u64),
        _ => Err(DecodeError::Shape("unsigned integer")),
    }
}

fn i64_of(v: &Value) -> R<i64> {
    match v {
        Value::Int(i) if *i >= i64::MIN as i128 && *i <= i64::MAX as i128 => Ok(*i as i64),
        _ => Err(DecodeError::Shape("int64")),
    }
}

pub(crate) fn text_of(v: &Value) -> R<String> {
    match v {
        Value::Text(s) => Ok(s.clone()),
        _ => Err(DecodeError::Shape("text")),
    }
}

fn cite_item_of(v: &Value) -> R<CiteItem> {
    match arr(v)? {
        [k, l, p, q] => Ok(CiteItem {
            key: text_of(k)?,
            locator: opt(l, |l| match arr(l)? {
                [label, value] => Ok(Locator {
                    label: text_of(label)?,
                    value: match arr(value)? {
                        [i, n] if u64_of(i)? == 0 => LocatorValue::Number(u64_of(n)?),
                        [i, a, b] if u64_of(i)? == 1 => LocatorValue::Range(u64_of(a)?, u64_of(b)?),
                        [i, t] if u64_of(i)? == 2 => LocatorValue::Text(text_of(t)?),
                        _ => return Err(DecodeError::Shape("locator value")),
                    },
                }),
                _ => Err(DecodeError::Shape("locator")),
            })?,
            prefix: inlines_of(p)?,
            suffix: inlines_of(q)?,
        }),
        _ => Err(DecodeError::Shape("cite item")),
    }
}

fn opt<T>(v: &Value, f: impl Fn(&Value) -> R<T>) -> R<Option<T>> {
    match v {
        Value::Null => Ok(None),
        x => f(x).map(Some),
    }
}

pub fn span_of(v: &Value) -> R<Span> {
    match arr(v)? {
        [f, s, e] => Ok(Span { file: u64_of(f)?, start: u64_of(s)?, end: u64_of(e)? }),
        _ => Err(DecodeError::Shape("span")),
    }
}

pub fn inlines_of(v: &Value) -> R<Vec<Inline>> {
    arr(v)?.iter().map(inline_of).collect()
}

pub fn inline_of(v: &Value) -> R<Inline> {
    let xs = arr(v)?;
    let (tag, span) = match xs {
        [t, s, ..] => (u64_of(t)?, span_of(s)?),
        _ => return Err(DecodeError::Shape("inline")),
    };
    let rest = &xs[2..];
    let bad = || DecodeError::Shape("inline");
    Ok(match (tag, rest) {
        (0, [s]) => Inline::Text { span, text: text_of(s)? },
        (4, [segs]) => Inline::Ruby {
            span,
            segments: arr(segs)?
                .iter()
                .map(|g| match arr(g)? {
                    [b, r] => Ok(RubySegment { base: inlines_of(b)?, reading: opt(r, text_of)? }),
                    _ => Err(bad()),
                })
                .collect::<R<_>>()?,
        },
        (5, [shape, body]) => Inline::Kenten { span, shape: opt(shape, text_of)?, body: inlines_of(body)? },
        (6, [sw, body]) => Inline::Color { span, swatch: text_of(sw)?, body: inlines_of(body)? },
        (7, [st, body]) => Inline::CharStyle { span, style: text_of(st)?, body: inlines_of(body)? },
        (8, [s]) => Inline::Tcy { span, text: text_of(s)? },
        (9, [n, st]) => Inline::Number {
            span,
            value: i64_of(n)?,
            style: opt(st, |s| match u64_of(s)? {
                0 => Ok(NumberStyle::Kanji),
                1 => Ok(NumberStyle::KanjiDigits),
                2 => Ok(NumberStyle::Tcy),
                _ => Err(bad()),
            })?,
        },
        (10, [k, l]) => Inline::Ref {
            span,
            kind: match u64_of(k)? {
                0 => RefKind::Number,
                1 => RefKind::Title,
                2 => RefKind::Page,
                _ => return Err(bad()),
            },
            label: text_of(l)?,
        },
        (11, [e]) => Inline::Deferred { span, expr: e.clone() },
        (23, [n, body]) => Inline::Note { span, number: u64_of(n)?, body: blocks_of(body)? },
        (24, [n, body]) => Inline::Sidenote { span, number: u64_of(n)?, body: blocks_of(body)? },
        (14, [ts, rs]) => Inline::IndexMark {
            span,
            terms: arr(ts)?.iter().map(text_of).collect::<R<_>>()?,
            readings: arr(rs)?.iter().map(text_of).collect::<R<_>>()?,
        },
        (25, [items]) => Inline::Cite { span, items: arr(items)?.iter().map(cite_item_of).collect::<R<_>>()? },
        (16, [s]) => Inline::ProofComment { span, text: text_of(s)? },
        (17, []) => Inline::LineBreak { span },
        (18, [zw, sp]) => Inline::Aki {
            span,
            zw: opt(zw, |z| match arr(z)? {
                [n, d] => Ok((u64_of(n)?, u64_of(d)?)),
                _ => Err(bad()),
            })?,
            sp: opt(sp, |s| u64_of(s).map(Sp))?,
        },
        (19, [c, k, r, body]) => Inline::ChannelItem {
            span,
            channel: text_of(c)?,
            key: opt(k, text_of)?,
            reading: opt(r, text_of)?,
            body: inlines_of(body)?,
        },
        (20, [u, body]) => Inline::Link { span, uri: text_of(u)?, body: inlines_of(body)? },
        (21, [l, body]) => Inline::Lang { span, lang: text_of(l)?, body: inlines_of(body)? },
        _ => return Err(bad()),
    })
}

pub fn blocks_of(v: &Value) -> R<Vec<Block>> {
    arr(v)?.iter().map(block_of).collect()
}

fn items_of(v: &Value) -> R<Vec<ListItem>> {
    arr(v)?
        .iter()
        .map(|i| match arr(i)? {
            [n, bs] => Ok(ListItem { number: opt(n, u64_of)?, blocks: blocks_of(bs)? }),
            _ => Err(DecodeError::Shape("list item")),
        })
        .collect()
}

pub fn block_of(v: &Value) -> R<Block> {
    let (span, label, lang, body) = match arr(v)? {
        [s, l, g, b] => (span_of(s)?, opt(l, text_of)?, opt(g, text_of)?, b),
        _ => return Err(DecodeError::Shape("block")),
    };
    let xs = arr(body)?;
    let tag = xs.first().map(u64_of).transpose()?.ok_or(DecodeError::Shape("block body"))?;
    let body = match (tag, &xs[1..]) {
        (1, [level, attrs, inl]) => BlockBody::Heading { level: u64_of(level)? as u8, attrs: attrs.clone(), inlines: inlines_of(inl)? },
        (2, [items]) => BlockBody::BulletList(items_of(items)?),
        (3, [items]) => BlockBody::OrderedList(items_of(items)?),
        (4, [groups]) => BlockBody::DefList(
            arr(groups)?
                .iter()
                .map(|g| match arr(g)? {
                    [ts, ds] => Ok(DefGroup {
                        terms: arr(ts)?.iter().map(inlines_of).collect::<R<_>>()?,
                        defs: arr(ds)?.iter().map(blocks_of).collect::<R<_>>()?,
                    }),
                    _ => Err(DecodeError::Shape("definition group")),
                })
                .collect::<R<_>>()?,
        ),
        (14, [t]) => match arr(t)? {
            [al, ws, cap, nn, st, h, rows] => BlockBody::Table {
                alignments: arr(al)?.iter().map(|a| u64_of(a).map(|a| a as u8)).collect::<R<_>>()?,
                widths: arr(ws)?.to_vec(),
                caption: opt(cap, inlines_of)?,
                nonumber: match nn {
                    Value::Bool(b) => *b,
                    _ => return Err(DecodeError::Shape("table")),
                },
                style: opt(st, text_of)?,
                header: arr(h)?.iter().map(inlines_of).collect::<R<_>>()?,
                rows: arr(rows)?
                    .iter()
                    .map(|r| arr(r)?.iter().map(inlines_of).collect::<R<Vec<_>>>())
                    .collect::<R<_>>()?,
            },
            _ => return Err(DecodeError::Shape("table")),
        },
        (10, [st, inl]) => BlockBody::Paragraph { style: opt(st, text_of)?, inlines: inlines_of(inl)? },
        (1..=4 | 10 | 14, _) => return Err(DecodeError::Shape("block body")),
        _ => BlockBody::Other(body.clone()),
    };
    Ok(Block { span, label, lang, body })
}

pub fn document_of(v: &Value) -> R<Document> {
    match arr(v)? {
        [abi, file, blocks] => {
            if u64_of(abi)? != ABI_VERSION as u64 {
                return Err(DecodeError::Shape("ABI version of the document"));
            }
            Ok(Document { file: u64_of(file)?, blocks: blocks_of(blocks)? })
        }
        _ => Err(DecodeError::Shape("document")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cbor::{decode, encode};

    fn sp(a: u64, b: u64) -> Span {
        Span { file: 1, start: a, end: b }
    }

    #[test]
    fn inline_roundtrip() {
        let xs = vec![
            Inline::Text { span: sp(0, 3), text: "漢字".into() },
            Inline::Ruby {
                span: sp(0, 3),
                segments: vec![RubySegment { base: vec![Inline::Text { span: sp(0, 3), text: "漢".into() }], reading: Some("かん".into()) }],
            },
            Inline::Number { span: sp(1, 2), value: -5, style: Some(NumberStyle::Tcy) },
            Inline::Aki { span: sp(1, 2), zw: None, sp: Some(Sp(65536)) },
            Inline::Deferred { span: sp(1, 2), expr: Value::Array(vec![Value::Int(0), span_value(sp(1, 2)), Value::Int(3)]) },
            Inline::ChannelItem { span: sp(1, 2), channel: "glossary".into(), key: Some("k".into()), reading: None, body: vec![] },
            Inline::LineBreak { span: sp(4, 4) },
            Inline::Link { span: sp(1, 2), uri: "https://example.com/".into(), body: vec![Inline::Text { span: sp(1, 2), text: "例".into() }] },
        ];
        let bytes = encode(&inlines_value(&xs));
        assert_eq!(inlines_of(&decode(&bytes).unwrap()).unwrap(), xs);
    }

    /// the bytes of a language span are those of the host: [21, span, lang, inlines] (docs/adr ADR 0187)
    #[test]
    fn lang_bytes() {
        let x = Inline::Lang { span: sp(0, 1), lang: "en".into(), body: vec![] };
        let bytes = encode(&inline_value(&x));
        let expected: Vec<u8> = [&[0x84, 0x15, 0x83, 0x01, 0x00, 0x01, 0x62][..], b"en", &[0x80][..]].concat();
        assert_eq!(bytes, expected);
        assert_eq!(inline_of(&decode(&bytes).unwrap()).unwrap(), x);
    }

    /// the language of a block goes back and forth with the same bytes: [span, label, lang, body] (docs/adr ADR 0187)
    #[test]
    fn block_lang_bytes() {
        let b = Block { span: sp(0, 1), label: None, lang: Some("de-CH-1996".into()), body: BlockBody::Paragraph { style: None, inlines: vec![] } };
        let bytes = encode(&block_value(&b));
        let expected: Vec<u8> = [&[0x84, 0x83, 0x01, 0x00, 0x01, 0xf6, 0x6a][..], b"de-CH-1996", &[0x83, 0x0a, 0xf6, 0x80][..]].concat();
        assert_eq!(bytes, expected);
        assert_eq!(block_of(&decode(&bytes).unwrap()).unwrap(), b);
        let none = Block { lang: None, ..b };
        assert_eq!(block_of(&decode(&encode(&block_value(&none))).unwrap()).unwrap(), none);
    }

    /// the bytes of a table are those of the host: [14, [aligns, widths, caption, nonumber, style, header, rows]] (docs/adr/0262)
    #[test]
    fn table_bytes() {
        let b = Block {
            span: sp(0, 1),
            label: None,
            lang: None,
            body: BlockBody::Table {
                alignments: vec![1],
                widths: vec![Value::Array(vec![Value::Int(0)])],
                caption: Some(vec![]),
                nonumber: true,
                style: None,
                header: vec![vec![]],
                rows: vec![],
            },
        };
        let bytes = encode(&block_value(&b));
        let expected: Vec<u8> = vec![0x84, 0x83, 0x01, 0x00, 0x01, 0xf6, 0xf6, 0x82, 0x0e, 0x87, 0x81, 0x01, 0x81, 0x81, 0x00, 0x80, 0xf5, 0xf6, 0x81, 0x80, 0x80];
        assert_eq!(bytes, expected);
        assert_eq!(block_of(&decode(&bytes).unwrap()).unwrap(), b);
    }

    /// the bytes of a note are those of the host: [23, span, number, [+ block]] (docs/adr/0263)
    #[test]
    fn note_bytes() {
        let x = Inline::Note { span: sp(0, 1), number: 2, body: note_body(sp(0, 1), vec![]) };
        let bytes = encode(&inline_value(&x));
        let expected: Vec<u8> = vec![0x84, 0x17, 0x83, 0x01, 0x00, 0x01, 0x02, 0x81, 0x84, 0x83, 0x01, 0x00, 0x01, 0xf6, 0xf6, 0x83, 0x0a, 0xf6, 0x80];
        assert_eq!(bytes, expected);
        assert_eq!(inline_of(&decode(&bytes).unwrap()).unwrap(), x);
        let s = Inline::Sidenote { span: sp(0, 1), number: 1, body: note_body(sp(0, 1), vec![]) };
        assert_eq!(encode(&inline_value(&s))[1], 0x18);
        assert_eq!(inline_of(&decode(&encode(&inline_value(&s))).unwrap()).unwrap(), s);
    }

    /// the bytes of a citation are those of the host: [25, span, [+ item]] (docs/adr/0266)
    #[test]
    fn cite_bytes() {
        let x = Inline::Cite { span: sp(0, 1), items: vec![CiteItem::key("a")] };
        let bytes = encode(&inline_value(&x));
        let expected: Vec<u8> = vec![0x83, 0x18, 0x19, 0x83, 0x01, 0x00, 0x01, 0x81, 0x84, 0x61, b'a', 0xf6, 0x80, 0x80];
        assert_eq!(bytes, expected);
        assert_eq!(inline_of(&decode(&bytes).unwrap()).unwrap(), x);
        let p = Inline::Cite {
            span: sp(0, 1),
            items: vec![
                CiteItem { key: "a".into(), locator: Some(Locator { label: "page".into(), value: LocatorValue::Range(5, 7) }), prefix: vec![], suffix: vec![] },
                CiteItem { key: "b".into(), locator: Some(Locator { label: "page".into(), value: LocatorValue::Text("xii".into()) }), prefix: vec![], suffix: vec![] },
                CiteItem { key: "c".into(), locator: Some(Locator { label: "chapter".into(), value: LocatorValue::Number(2) }), prefix: vec![], suffix: vec![] },
            ],
        };
        assert_eq!(inline_of(&decode(&encode(&inline_value(&p))).unwrap()).unwrap(), p);
    }

    /// the bytes of a link are those of the host: [20, span, uri, inlines] (docs/adr ADR 0182)
    #[test]
    fn link_bytes() {
        let x = Inline::Link { span: sp(0, 1), uri: "https://e.jp/".into(), body: vec![] };
        let bytes = encode(&inline_value(&x));
        let expected: Vec<u8> = [&[0x84, 0x14, 0x83, 0x01, 0x00, 0x01, 0x6d][..], b"https://e.jp/", &[0x80][..]].concat();
        assert_eq!(bytes, expected);
        assert_eq!(inline_of(&decode(&bytes).unwrap()).unwrap(), x);
    }

    #[test]
    fn document_roundtrip_keeps_other_blocks() {
        let code = Value::Array(vec![Value::Int(11), Value::Int(0)]);
        let d = Document {
            file: 2,
            blocks: vec![
                Block { span: sp(0, 9), label: Some("a".into()), lang: None, body: BlockBody::Paragraph { style: None, inlines: vec![] } },
                Block { span: sp(9, 9), label: None, lang: None, body: BlockBody::Other(code) },
            ],
        };
        let bytes = encode(&document_value(&d));
        assert_eq!(document_of(&decode(&bytes).unwrap()).unwrap(), d);
    }

    #[test]
    fn map_inlines_visits_list_items() {
        let para = |s: &str| Block { span: sp(0, 1), label: None, lang: None, body: BlockBody::Paragraph { style: None, inlines: vec![Inline::Text { span: sp(0, 1), text: s.into() }] } };
        let mut d = Document { file: 1, blocks: vec![para("a"), Block { span: sp(0, 1), label: None, lang: None, body: BlockBody::BulletList(vec![ListItem { number: None, blocks: vec![para("b")] }]) }] };
        let mut seen = Vec::new();
        d.map_inlines(&mut |xs| {
            for x in &xs {
                if let Inline::Text { text, .. } = x {
                    seen.push(text.clone());
                }
            }
            xs
        });
        assert_eq!(seen, vec!["a", "b"]);
    }
}
