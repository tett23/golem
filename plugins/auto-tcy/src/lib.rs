//! A sample plugin (docs/adr/0128): the filter `auto-tcy` sets short runs
//! of ASCII digits and marks such as `!?` in tate-chu-yoko.
//!
//! ```toml
//! [plugins.auto-tcy]
//! url = "https://github.com/tett23/golem/releases/download/v0.1.0-rc4/auto-tcy.wasm"
//! data = { config = "auto-tcy.conf" }   # optional
//!
//! [[filters]]
//! plugin = "auto-tcy"
//! filter = "auto-tcy"
//! files = ["chapters/01.gm"]
//! ```
//!
//! A *chunk* is a maximal run of ASCII graphic characters (U+0021 to
//! U+007E) in the text as it is read, across the nodes of a run of inlines.
//! A chunk that lies in one text node is rewritten when it is
//!
//! - digits whose count is one of `digits` (2 by default): the number
//!   node with the style tcy, or a tcy node when it has a leading zero;
//! - one of `marks` (`!! !? ?! ??` by default): a tcy node.
//!
//! So `3.14`, `x86`, `A4` and `!!!` are left as they are. A chunk that
//! crosses nodes (`[strong: 1]2`), or touches a node whose text the filter
//! cannot see (`[= n]12`), is not rewritten; it is a warning when the
//! chunk, or a part of it in one text node, would be rewritten.
//!
//! The text of `[code: ...]`, ruby bases, kenten, and an existing tcy or
//! number is never rewritten. The filter asks for the writing mode of the
//! book (docs/adr/0121) and changes nothing in horizontal writing.

use golem_plugin_sdk::*;
use std::collections::BTreeMap;

/// The settings of the data `config`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Config {
    /// the counts of digits set in tate-chu-yoko
    pub digits: Vec<usize>,
    /// the runs of marks set in tate-chu-yoko
    pub marks: Vec<String>,
}

impl Default for Config {
    fn default() -> Self {
        Config { digits: vec![2], marks: ["!!", "!?", "?!", "??"].map(String::from).to_vec() }
    }
}

/// Why the data `config` is wrong; each is its own code.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ConfigError {
    Utf8,
    /// a line that is not `key = value` (the line number, from 1)
    Syntax(usize),
    Key(usize, String),
    /// a count of digits that is not 1 to 4
    Digits(usize, String),
    /// a mark that is not 1 to 4 ASCII graphic characters with no digit
    Mark(usize, String),
}

/// Reads the data `config`: lines of `key = value`, the value a list
/// separated by spaces; an empty line and a line that starts with `#` are
/// skipped. The keys are `digits` and `marks`; an empty list turns it off
/// (`digits =` is a syntax error, `digits = none` an empty list).
pub fn parse_config(bytes: &[u8]) -> Result<Config, ConfigError> {
    let text = std::str::from_utf8(bytes).map_err(|_| ConfigError::Utf8)?;
    let mut c = Config::default();
    for (i, line) in text.lines().enumerate().map(|(i, l)| (i + 1, l.trim())) {
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let (k, v) = line.split_once('=').ok_or(ConfigError::Syntax(i))?;
        let (k, v) = (k.trim(), v.trim());
        if k.is_empty() || v.is_empty() {
            return Err(ConfigError::Syntax(i));
        }
        let items: Vec<&str> = if v == "none" { vec![] } else { v.split_whitespace().collect() };
        match k {
            "digits" => {
                c.digits = items
                    .iter()
                    .map(|d| match d.parse::<usize>() {
                        Ok(n) if (1..=4).contains(&n) && !d.starts_with('0') => Ok(n),
                        _ => Err(ConfigError::Digits(i, d.to_string())),
                    })
                    .collect::<Result<_, _>>()?;
                c.digits.sort();
                c.digits.dedup();
            }
            "marks" => {
                c.marks = items
                    .iter()
                    .map(|m| {
                        let n = m.chars().count();
                        if (1..=4).contains(&n) && m.chars().all(|ch| ch.is_ascii_graphic() && !ch.is_ascii_digit()) {
                            Ok(m.to_string())
                        } else {
                            Err(ConfigError::Mark(i, m.to_string()))
                        }
                    })
                    .collect::<Result<_, _>>()?;
                c.marks.sort();
                c.marks.dedup();
            }
            _ => return Err(ConfigError::Key(i, k.into())),
        }
    }
    Ok(c)
}

/// What a chunk becomes.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Kind {
    /// the number node with the style tcy
    Number(i64),
    /// a tcy node of the chunk
    Tcy,
}

/// What a chunk in one text node becomes, if anything.
pub fn classify(cfg: &Config, chunk: &str) -> Option<Kind> {
    let n = chunk.chars().count();
    if chunk.chars().all(|c| c.is_ascii_digit()) {
        if !cfg.digits.contains(&n) {
            None
        } else if n > 1 && chunk.starts_with('0') {
            // the number node would lose the zero
            Some(Kind::Tcy)
        } else {
            chunk.parse().ok().map(Kind::Number)
        }
    } else if cfg.marks.iter().any(|m| m == chunk) {
        Some(Kind::Tcy)
    } else {
        None
    }
}

/// What the filter knows of a node of a run of inlines.
struct Leaf {
    span: Span,
    /// the number of the text node in the order of the run, if it is one
    /// the filter may rewrite
    text: Option<usize>,
}

enum Item {
    /// a character, the leaf it is in, and its byte offset in a text node
    Ch(char, usize, usize),
    /// what ends a chunk: a line break, an aki, a note mark
    Wall,
    /// a node whose text is not known: a reference, a deferred expression,
    /// a citation, a number whose notation the book decides
    Unknown(usize),
}

struct Flat {
    leaves: Vec<Leaf>,
    items: Vec<Item>,
    texts: usize,
}

impl Flat {
    fn leaf(&mut self, span: Span, text: Option<usize>) -> usize {
        self.leaves.push(Leaf { span, text });
        self.leaves.len() - 1
    }

    fn chars(&mut self, s: &str, leaf: usize) {
        self.items.extend(s.char_indices().map(|(o, c)| Item::Ch(c, leaf, o)));
    }

    fn run(&mut self, xs: &[Inline], editable: bool) {
        for x in xs {
            match x {
                Inline::Text { span, text } => {
                    let t = self.texts;
                    self.texts += 1;
                    let l = self.leaf(*span, editable.then_some(t));
                    self.chars(text, l);
                }
                Inline::CharStyle { style, body, .. } => self.run(body, editable && style != "code"),
                Inline::Color { body, .. } => self.run(body, editable),
                // the text of a link is set as that of a character style (docs/adr ADR 0182)
                Inline::Link { body, .. } => self.run(body, editable),
                // the text of a language span likewise (docs/adr ADR 0187)
                Inline::Lang { body, .. } => self.run(body, editable),
                Inline::Kenten { body, .. } => self.run(body, false),
                Inline::Ruby { segments, .. } => {
                    for s in segments {
                        self.run(&s.base, false);
                    }
                }
                Inline::Tcy { span, text } => {
                    let l = self.leaf(*span, None);
                    self.chars(text, l);
                }
                Inline::Number { span, .. } | Inline::Ref { span, .. } | Inline::Deferred { span, .. } | Inline::Cite { span, .. } => {
                    let l = self.leaf(*span, None);
                    self.items.push(Item::Unknown(l));
                }
                Inline::Note { .. } | Inline::Sidenote { .. } | Inline::LineBreak { .. } | Inline::Aki { .. } => self.items.push(Item::Wall),
                // nothing is set where they are
                Inline::IndexMark { .. } | Inline::ProofComment { .. } | Inline::ChannelItem { .. } => {}
            }
        }
    }
}

/// A rewrite of a text node: the byte range and what it becomes.
type Edits = BTreeMap<usize, Vec<(usize, usize, Kind)>>;

fn warning(span: Span, chunk: &str) -> Diagnostic {
    Diagnostic {
        code: "split".into(),
        severity: Severity::Warning,
        span,
        message: format!("ノードの境をまたぐので縦中横にしませんでした: {chunk}。[tcy: ...] か [number-text ... style=tcy] で書いてください"),
    }
}

/// The edits of the chunks of a flattened run, and the warnings.
fn plan(cfg: &Config, f: &Flat, diags: &mut Vec<Diagnostic>) -> Edits {
    let mut edits = Edits::new();
    let member = |it: &Item| matches!(it, Item::Ch(c, _, _) if c.is_ascii_graphic()) || matches!(it, Item::Unknown(_));
    let mut i = 0;
    while i < f.items.len() {
        if !member(&f.items[i]) {
            i += 1;
            continue;
        }
        let start = i;
        while i < f.items.len() && member(&f.items[i]) {
            i += 1;
        }
        let chunk = &f.items[start..i];
        let mut leaves: Vec<usize> = chunk.iter().map(|it| match it {
            Item::Ch(_, l, _) | Item::Unknown(l) => *l,
            Item::Wall => unreachable!(),
        }).collect();
        leaves.dedup();
        let unknown = chunk.iter().any(|it| matches!(it, Item::Unknown(_)));
        let text: String = chunk.iter().filter_map(|it| if let Item::Ch(c, _, _) = it { Some(*c) } else { None }).collect();
        if leaves.len() == 1 && !unknown {
            if let (Some(t), Some(k)) = (f.leaves[leaves[0]].text, classify(cfg, &text)) {
                let (s, e) = match (&chunk[0], &chunk[chunk.len() - 1]) {
                    (Item::Ch(_, _, s), Item::Ch(c, _, e)) => (*s, *e + c.len_utf8()),
                    _ => unreachable!(),
                };
                edits.entry(t).or_default().push((s, e, k));
            }
            continue;
        }
        // the parts of the chunk in one leaf each
        let mut parts: Vec<String> = vec![];
        let mut last = None;
        for it in chunk {
            match it {
                Item::Ch(c, l, _) if last == Some(*l) => parts.last_mut().unwrap().push(*c),
                Item::Ch(c, l, _) => {
                    parts.push(c.to_string());
                    last = Some(*l);
                }
                _ => last = None,
            }
        }
        let would = if unknown { parts.iter().any(|p| classify(cfg, p).is_some()) } else { classify(cfg, &text).is_some() };
        if would {
            // at the first node of the chunk: a diagnostic points at a node of
            // the request, not at a range the plugin makes up (docs/adr/0108)
            let shown: String = chunk.iter().map(|it| if let Item::Ch(c, _, _) = it { c.to_string() } else { "…".into() }).collect();
            diags.push(warning(f.leaves[leaves[0]].span, &shown));
        }
    }
    edits
}

fn split(span: Span, text: String, edits: &[(usize, usize, Kind)]) -> Vec<Inline> {
    let mut out = vec![];
    let mut at = 0;
    for (s, e, k) in edits {
        if *s > at {
            out.push(Inline::Text { span, text: text[at..*s].into() });
        }
        out.push(match k {
            Kind::Number(n) => Inline::Number { span, value: *n, style: Some(NumberStyle::Tcy) },
            Kind::Tcy => Inline::Tcy { span, text: text[*s..*e].into() },
        });
        at = *e;
    }
    if at < text.len() {
        out.push(Inline::Text { span, text: text[at..].into() });
    }
    out
}

/// Rebuilds a run in the order `Flat::run` numbered its text nodes.
fn rebuild(xs: Vec<Inline>, edits: &Edits, count: &mut usize) -> Vec<Inline> {
    let mut out = vec![];
    for x in xs {
        match x {
            Inline::Text { span, text } => {
                let t = *count;
                *count += 1;
                match edits.get(&t) {
                    Some(es) => out.extend(split(span, text, es)),
                    None => out.push(Inline::Text { span, text }),
                }
            }
            Inline::CharStyle { span, style, body } => out.push(Inline::CharStyle { span, style, body: rebuild(body, edits, count) }),
            Inline::Color { span, swatch, body } => out.push(Inline::Color { span, swatch, body: rebuild(body, edits, count) }),
            Inline::Link { span, uri, body } => out.push(Inline::Link { span, uri, body: rebuild(body, edits, count) }),
            Inline::Lang { span, lang, body } => out.push(Inline::Lang { span, lang, body: rebuild(body, edits, count) }),
            Inline::Kenten { span, shape, body } => out.push(Inline::Kenten { span, shape, body: rebuild(body, edits, count) }),
            Inline::Ruby { span, segments } => out.push(Inline::Ruby {
                span,
                segments: segments.into_iter().map(|s| RubySegment { base: rebuild(s.base, edits, count), reading: s.reading }).collect(),
            }),
            other => out.push(other),
        }
    }
    out
}

/// Sets the chunks of a run of inlines in tate-chu-yoko. The bodies of
/// notes, sidenotes and channel items are runs of their own.
pub fn run(cfg: &Config, xs: Vec<Inline>, diags: &mut Vec<Diagnostic>) -> Vec<Inline> {
    let xs: Vec<Inline> = xs
        .into_iter()
        .map(|x| match x {
            Inline::Note { span, number, mut body } => {
                for p in note_paragraphs_mut(&mut body) {
                    *p = run(cfg, std::mem::take(p), diags);
                }
                Inline::Note { span, number, body }
            }
            Inline::Sidenote { span, number, mut body } => {
                for p in note_paragraphs_mut(&mut body) {
                    *p = run(cfg, std::mem::take(p), diags);
                }
                Inline::Sidenote { span, number, body }
            }
            Inline::ChannelItem { span, channel, key, reading, body } => Inline::ChannelItem { span, channel, key, reading, body: run(cfg, body, diags) },
            other => other,
        })
        .collect();
    let mut f = Flat { leaves: vec![], items: vec![], texts: 0 };
    f.run(&xs, true);
    let edits = plan(cfg, &f, diags);
    if edits.is_empty() {
        return xs;
    }
    rebuild(xs, &edits, &mut 0)
}

fn describe() -> Description {
    Description { filters: vec!["auto-tcy".into()], data: vec!["config".into()], context: vec!["writing-mode".into()], ..Default::default() }
}

fn config_diagnostic(file: u64, e: &ConfigError) -> Diagnostic {
    let (code, message) = match e {
        ConfigError::Utf8 => ("config-utf8", "config が UTF-8 ではありません".to_string()),
        ConfigError::Syntax(l) => ("config-syntax", format!("config の {l} 行め: キー = 値 の形ではありません")),
        ConfigError::Key(l, k) => ("config-key", format!("config の {l} 行め: 知らないキーです: {k}")),
        ConfigError::Digits(l, d) => ("config-digits", format!("config の {l} 行め: digits は 1 から 4 の数です: {d}")),
        ConfigError::Mark(l, m) => ("config-mark", format!("config の {l} 行め: marks は数字を含まない 1 から 4 字の ASCII の記号です: {m}")),
    };
    // the data has no position; the top of the file the filter is applied to
    Diagnostic { code: code.into(), severity: Severity::Error, span: Span { file, start: 0, end: 0 }, message }
}

pub fn invoke(req: Request) -> Response {
    match req {
        Request::Command(c) => Response::inlines(vec![]).with(Diagnostic {
            code: "no-command".into(),
            severity: Severity::Error,
            span: c.span,
            message: "auto-tcy はフィルタです".into(),
        }),
        // auto-tcy declares no block command, so the host sends none (docs/adr/0122)
        Request::Block(_) => Response::blocks(vec![]),
        Request::Filter(f) => {
            let mut doc = f.document;
            let cfg = match f.data.get("config").map(parse_config) {
                None => Config::default(),
                Some(Ok(c)) => c,
                Some(Err(e)) => {
                    let d = config_diagnostic(doc.file, &e);
                    return Response::document(doc).with(d);
                }
            };
            // nothing in horizontal writing; the host sends the writing mode it asked for
            if !f.context.vertical().expect("the host sends writing-mode") {
                return Response::document(doc);
            }
            let mut diags = vec![];
            doc.map_inlines(&mut |xs| run(&cfg, xs, &mut diags));
            let mut r = Response::document(doc);
            r.diagnostics = diags;
            r
        }
    }
}

export_plugin!(describe, invoke);

#[cfg(test)]
mod tests {
    use super::*;

    const S: Span = Span { file: 1, start: 0, end: 10 };

    fn t(s: &str) -> Inline {
        Inline::Text { span: S, text: s.into() }
    }

    fn tcy(s: &str) -> Inline {
        Inline::Tcy { span: S, text: s.into() }
    }

    fn num(n: i64) -> Inline {
        Inline::Number { span: S, value: n, style: Some(NumberStyle::Tcy) }
    }

    fn style(name: &str, body: Vec<Inline>) -> Inline {
        Inline::CharStyle { span: S, style: name.into(), body }
    }

    fn go(xs: Vec<Inline>) -> (Vec<Inline>, Vec<String>) {
        go_with(&Config::default(), xs)
    }

    fn go_with(cfg: &Config, xs: Vec<Inline>) -> (Vec<Inline>, Vec<String>) {
        let mut ds = vec![];
        let out = run(cfg, xs, &mut ds);
        (out, ds.into_iter().map(|d| d.code).collect())
    }

    fn none() -> Vec<String> {
        vec![]
    }

    #[test]
    fn two_digits_and_marks() {
        assert_eq!(go(vec![t("第12回")]), (vec![t("第"), num(12), t("回")], none()));
        assert_eq!(go(vec![t("本当か!?")]), (vec![t("本当か"), tcy("!?")], none()));
        assert_eq!(go(vec![t("12")]), (vec![num(12)], none()));
        assert_eq!(go(vec![t("1月12日と10月")]), (vec![t("1月"), num(12), t("日と"), num(10), t("月")], none()));
        assert_eq!(go(vec![t("05年")]), (vec![tcy("05"), t("年")], none()));
    }

    #[test]
    fn what_is_left_alone() {
        for s in ["1年", "123年", "3.14", "x86", "A4", "!!!", "!", "１２", "！？", "12a", "a 1 b", "10%"] {
            assert_eq!(go(vec![t(s)]), (vec![t(s)], none()), "{s}");
        }
        // a space ends a chunk
        assert_eq!(go(vec![t("a 12 b")]), (vec![t("a "), num(12), t(" b")], none()));
    }

    #[test]
    fn code_ruby_kenten_and_tcy_are_not_rewritten() {
        let code = vec![style("code", vec![t("12")])];
        assert_eq!(go(code.clone()), (code, none()));
        let ruby = vec![Inline::Ruby { span: S, segments: vec![RubySegment { base: vec![t("12")], reading: Some("x".into()) }] }];
        assert_eq!(go(ruby.clone()), (ruby, none()));
        let kenten = vec![Inline::Kenten { span: S, shape: None, body: vec![t("!?")] }];
        assert_eq!(go(kenten.clone()), (kenten, none()));
        let done = vec![t("第"), tcy("12"), t("回")];
        assert_eq!(go(done.clone()), (done, none()));
    }

    #[test]
    fn inside_a_style_with_its_neighbours() {
        assert_eq!(go(vec![t("第"), style("strong", vec![t("12")]), t("回")]), (vec![t("第"), style("strong", vec![num(12)]), t("回")], none()));
        let color = Inline::Color { span: S, swatch: "red".into(), body: vec![t("!?")] };
        assert_eq!(go(vec![color]).0, vec![Inline::Color { span: S, swatch: "red".into(), body: vec![tcy("!?")] }]);
    }

    #[test]
    fn a_chunk_across_nodes_is_a_warning() {
        let xs = vec![style("strong", vec![t("1")]), t("2")];
        assert_eq!(go(xs.clone()), (xs, vec!["split".to_string()]));
        let xs = vec![t("!"), style("bold", vec![t("?")])];
        assert_eq!(go(xs.clone()), (xs, vec!["split".to_string()]));
        // across nodes, but not two digits: no warning
        let xs = vec![style("strong", vec![t("1")]), t("23")];
        assert_eq!(go(xs.clone()), (xs, none()));
        let xs = vec![t("x"), style("strong", vec![t("86")])];
        assert_eq!(go(xs.clone()), (xs, none()));
        // a tcy next to a digit
        let xs = vec![tcy("1"), t("2")];
        assert_eq!(go(xs.clone()), (xs, vec!["split".to_string()]));
    }

    #[test]
    fn the_warning_is_at_the_first_node_of_the_chunk() {
        let a = Span { file: 1, start: 9, end: 20 };
        let b = Span { file: 1, start: 20, end: 21 };
        let mut ds = vec![];
        run(&Config::default(), vec![style("strong", vec![Inline::Text { span: a, text: "1".into() }]), Inline::Text { span: b, text: "2".into() }], &mut ds);
        assert_eq!(ds.iter().map(|d| d.span).collect::<Vec<_>>(), vec![a]);
    }

    #[test]
    fn a_node_whose_text_is_unknown() {
        let deferred = Inline::Deferred { span: S, expr: Value::Null };
        let xs = vec![deferred.clone(), t("12")];
        assert_eq!(go(xs.clone()), (xs, vec!["split".to_string()]));
        let xs = vec![deferred, t("年")];
        assert_eq!(go(xs.clone()), (xs, none()));
        let number = Inline::Number { span: S, value: 3, style: None };
        let xs = vec![number, t("回")];
        assert_eq!(go(xs.clone()), (xs, none()));
    }

    #[test]
    fn walls_and_invisible_nodes() {
        let br = Inline::LineBreak { span: S };
        assert_eq!(go(vec![t("1"), br.clone(), t("12")]), (vec![t("1"), br, num(12)], none()));
        // an index mark sets nothing, so the chunk goes on across it
        let ix = Inline::IndexMark { span: S, terms: vec!["a".into()], readings: vec!["a".into()] };
        let xs = vec![t("1"), ix, t("2")];
        assert_eq!(go(xs.clone()), (xs, vec!["split".to_string()]));
    }

    #[test]
    fn the_body_of_a_note_is_a_run_of_its_own() {
        let note = |b| Inline::Note { span: S, number: 1, body: note_body(S, b) };
        assert_eq!(go(vec![t("1"), note(vec![t("12")]), t("2")]), (vec![t("1"), note(vec![num(12)]), t("2")], none()));
    }

    #[test]
    fn the_config() {
        assert_eq!(parse_config(b"# c\n"), Ok(Config::default()));
        let c = parse_config(b"digits = 3 2 2\nmarks = !!! !?\n").unwrap();
        assert_eq!(c, Config { digits: vec![2, 3], marks: vec!["!!!".into(), "!?".into()] });
        assert_eq!(go_with(&c, vec![t("123と!!!")]).0, vec![num(123), t("と"), tcy("!!!")]);
        let off = parse_config(b"digits = none\nmarks = none").unwrap();
        assert_eq!(go_with(&off, vec![t("12!?")]).0, vec![t("12!?")]);
        assert_eq!(parse_config(b"digits"), Err(ConfigError::Syntax(1)));
        assert_eq!(parse_config(b"digits ="), Err(ConfigError::Syntax(1)));
        assert_eq!(parse_config(b"digit = 2"), Err(ConfigError::Key(1, "digit".into())));
        for d in ["0", "5", "02", "x"] {
            assert_eq!(parse_config(format!("digits = {d}").as_bytes()), Err(ConfigError::Digits(1, d.into())));
        }
        for m in ["!!!!!", "1!", "！？"] {
            assert_eq!(parse_config(format!("marks = {m}").as_bytes()), Err(ConfigError::Mark(1, m.into())));
        }
        assert_eq!(parse_config(b"\xff"), Err(ConfigError::Utf8));
    }

    #[test]
    fn the_filter_rewrites_paragraphs_and_reports_the_config() {
        let doc = Document { file: 3, blocks: vec![Block { span: S, label: None, lang: None, body: BlockBody::Paragraph { style: None, inlines: vec![t("第12回")] } }] };
        let req_in = |mode: &str, data: Vec<(String, Vec<u8>)>| {
            Request::Filter(FilterRequest {
                name: "auto-tcy".into(),
                document: doc.clone(),
                context: Context(vec![("writing-mode".into(), mode.into())]),
                data: Data(data),
            })
        };
        match invoke(req_in("vertical", vec![])).output {
            Output::Document(d) => match &d.blocks[0].body {
                BlockBody::Paragraph { inlines, .. } => assert_eq!(inlines, &vec![t("第"), num(12), t("回")]),
                _ => panic!(),
            },
            _ => panic!(),
        }
        // in horizontal writing nothing changes, but the config is checked
        assert_eq!(invoke(req_in("horizontal", vec![])), Response::document(doc.clone()));
        for mode in ["vertical", "horizontal"] {
            let r = invoke(req_in(mode, vec![("config".into(), b"digits = 9".to_vec())]));
            assert_eq!(r.output, Output::Document(doc.clone()));
            assert_eq!(r.diagnostics.iter().map(|d| (d.code.as_str(), d.span)).collect::<Vec<_>>(), vec![("config-digits", Span { file: 3, start: 0, end: 0 })]);
        }
    }

    #[test]
    fn the_description_asks_for_the_writing_mode() {
        assert_eq!(describe().context, ["writing-mode"]);
    }
}
