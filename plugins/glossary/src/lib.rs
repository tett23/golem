//! A sample plugin (docs/adr/0126): `[term: 語]` sets the word in the text
//! and sends it to the channel `glossary`; `@channel glossary` lists the
//! words in the order of their readings, each with its definition and the
//! pages it is on. The project passes the words as the data `terms`:
//!
//! ```toml
//! [plugins.glossary]
//! url = "https://github.com/tett23/golem/releases/download/v0.1.0-rc4/glossary.wasm"
//! data = { terms = "data/terms.tsv" }
//! ```
//!
//! Each line of the TSV is a word, its reading, its definition and, if the
//! line has a fourth column, a label whose page the entry refers to. The
//! reading may be empty when the word has no kanji: the word is its own
//! reading. An empty line and a line that starts with `#` are skipped.
//!
//! The TSV is checked once, when the host reads it (`golem_check_data`,
//! docs/adr/0120): an error points at its line. The codes of the
//! diagnostics are the part after the name of the plugin, which the host
//! puts before them (`glossary/tsv-columns`, docs/adr/0108).

use golem_plugin_sdk::*;

/// The channel of the words: in the order of the readings, with the pages.
pub const CHANNEL: &str = "glossary";

/// The name of the data of the words.
pub const DATA: &str = "terms";

fn describe() -> Description {
    Description {
        commands: vec!["term".into()],
        channels: vec![ChannelDecl { name: CHANNEL.into(), order: ChannelOrder::Reading, locators: true }],
        data: vec![DATA.into()],
        ..Default::default()
    }
}

/// A line of the TSV.
#[derive(Clone, Debug, PartialEq)]
pub struct Term {
    pub word: String,
    /// the reading of the TSV, or the word when the TSV leaves it empty
    pub reading: String,
    pub definition: String,
    /// a label the entry refers to by its page
    pub see: Option<String>,
}

/// An error of a line of the TSV: the number of the line (from 1), its
/// code and its message.
pub type LineError = (u64, &'static str, String);

/// A character a reading may have: kana, the long vowel mark, an ASCII
/// letter or digit. The host sorts the readings by these (golem-doc ADR
/// 0002); a kanji would sort by its code point, after every kana.
fn reading_char(c: char) -> bool {
    matches!(c, 'ぁ'..='ゖ' | 'ァ'..='ヶ' | 'ー') || c.is_ascii_alphanumeric()
}

/// A kanji: the CJK unified ideographs and their extensions, the
/// compatibility ideographs and the iteration mark 々.
pub fn is_kanji(c: char) -> bool {
    matches!(c, '\u{3400}'..='\u{4DBF}' | '\u{4E00}'..='\u{9FFF}' | '\u{F900}'..='\u{FAFF}' | '\u{20000}'..='\u{3FFFF}' | '々')
}

/// The terms of a TSV, or the errors of its lines.
pub fn parse(tsv: &str) -> Result<Vec<Term>, Vec<LineError>> {
    let mut terms: Vec<Term> = vec![];
    let mut errors = vec![];
    for (i, line) in tsv.lines().enumerate() {
        let n = i as u64 + 1;
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let cols: Vec<&str> = line.split('\t').collect();
        let (word, reading, definition, see) = match cols.as_slice() {
            [w, r, d] => (*w, *r, *d, None),
            [w, r, d, s] => (*w, *r, *d, Some(*s)),
            _ => {
                errors.push((n, "tsv-columns", format!("terms の {n} 行めの欄の数が 3 か 4 ではありません")));
                continue;
            }
        };
        if word.is_empty() || definition.is_empty() || see == Some("") {
            errors.push((n, "tsv-empty", format!("terms の {n} 行めの語、定義、ラベルのどれかが空です")));
        } else if reading.is_empty() && word.chars().any(is_kanji) {
            errors.push((n, "tsv-no-reading", format!("terms の {n} 行めの語は漢字を含むので、読みが要ります: {word}")));
        } else if !reading.chars().all(reading_char) {
            errors.push((n, "tsv-reading", format!("terms の {n} 行めの読みには、かなと英数字だけを書きます: {reading}")));
        } else if terms.iter().any(|t| t.word == word) {
            errors.push((n, "tsv-duplicate", format!("terms の {n} 行めの語は、前の行にもあります: {word}")));
        } else {
            let reading = if reading.is_empty() { word } else { reading };
            terms.push(Term { word: word.into(), reading: reading.into(), definition: definition.into(), see: see.map(Into::into) });
        }
    }
    if errors.is_empty() {
        Ok(terms)
    } else {
        Err(errors)
    }
}

/// The TSV of the data as text: an error of the code `utf8` when it is not UTF-8.
fn tsv_of(bytes: &[u8]) -> Result<&str, (&'static str, String)> {
    std::str::from_utf8(bytes).map_err(|_| ("utf8", "terms が UTF-8 ではありません".into()))
}

/// `golem_check_data`: the errors of `terms`, each at its line; the
/// file as a whole when it is not UTF-8. Data without `terms` is the error
/// of each call (`no-data`), as the host has no file to point at.
pub fn check_data(data: &Data) -> Vec<DataDiagnostic> {
    let at = |line: Option<u64>, code: &str, message: String| DataDiagnostic { code: code.into(), severity: Severity::Error, name: DATA.into(), line, message };
    match data.get(DATA).map(tsv_of) {
        None => vec![],
        Some(Err((code, m))) => vec![at(None, code, m)],
        Some(Ok(tsv)) => match parse(tsv) {
            Ok(_) => vec![],
            Err(es) => es.into_iter().map(|(n, code, m)| at(Some(n), code, m)).collect(),
        },
    }
}

/// The text of a slot: its text, the bases of its ruby, the text inside its
/// styles. A note and the other marks have none.
pub fn plain(xs: &[Inline]) -> String {
    xs.iter()
        .map(|x| match x {
            Inline::Text { text, .. } | Inline::Tcy { text, .. } => text.clone(),
            Inline::Ruby { segments, .. } => segments.iter().map(|s| plain(&s.base)).collect(),
            Inline::Kenten { body, .. } | Inline::Color { body, .. } | Inline::CharStyle { body, .. } => plain(body),
            _ => String::new(),
        })
        .collect()
}

/// The body of the entry of a term: the word, a full-width space and the
/// definition, and the page of the label after an arrow.
pub fn entry_body(span: Span, t: &Term) -> Vec<Inline> {
    let text = |s: &str| Inline::Text { span, text: s.into() };
    let mut body = vec![text(&t.word), text("\u{3000}"), text(&t.definition)];
    if let Some(l) = &t.see {
        body.extend([text("（→"), Inline::Ref { span, kind: RefKind::Page, label: l.clone() }, text("）")]);
    }
    body
}

fn error(span: Span, code: &str, message: String) -> Diagnostic {
    Diagnostic { code: code.into(), severity: Severity::Error, span, message }
}

pub fn invoke(req: Request) -> Response {
    let c = match req {
        Request::Command(c) => c,
        Request::Filter(f) => return Response::document(f.document),
        // glossary declares no block command, so the host sends none (docs/adr/0122)
        Request::Block(_) => return Response::blocks(vec![]),
    };
    let slot = match c.slots.as_slice() {
        [s] => s.clone(),
        _ => return Response::inlines(vec![]).with(error(c.span, "slot", "term には語を一つ書きます".into())),
    };
    let shown = Response::inlines(slot.clone());
    let word = plain(&slot);
    if word.is_empty() {
        return shown.with(error(c.span, "slot", "term には語を一つ書きます".into()));
    }
    if !c.args.is_empty() {
        return shown.with(error(c.span, "args", "term は引数を取りません".into()));
    }
    let tsv = match c.data.get(DATA).map(tsv_of) {
        Some(Ok(t)) => t,
        Some(Err((code, m))) => return shown.with(error(c.span, code, m)),
        None => return shown.with(error(c.span, "no-data", "manifest.toml で data の terms を渡してください".into())),
    };
    // the host calls no command after an error of check_data; this is for a host that does not check
    let terms = match parse(tsv) {
        Ok(ts) => ts,
        Err(es) => return es.into_iter().fold(shown, |r, (_, code, m)| r.with(error(c.span, code, m))),
    };
    match terms.iter().find(|t| t.word == word) {
        None => shown.with(error(c.span, "unknown", format!("terms にない語です: {word}"))),
        Some(t) => {
            let item = Inline::ChannelItem {
                span: c.span,
                channel: CHANNEL.into(),
                key: Some(t.word.clone()),
                reading: Some(t.reading.clone()),
                body: entry_body(c.span, t),
            };
            Response::inlines(slot.into_iter().chain([item]).collect())
        }
    }
}

export_plugin!(describe, invoke, check_data);

#[cfg(test)]
mod tests {
    use super::*;

    const SPAN: Span = Span { file: 1, start: 0, end: 12 };

    fn text(s: &str) -> Inline {
        Inline::Text { span: SPAN, text: s.into() }
    }

    fn terms(tsv: Option<&[u8]>) -> Data {
        Data(tsv.map(|b| vec![("terms".into(), b.to_vec())]).unwrap_or_default())
    }

    fn command(args: Vec<Arg>, slots: Vec<Vec<Inline>>, tsv: Option<&[u8]>) -> Request {
        Request::Command(CommandRequest { name: "term".into(), args, slots, span: SPAN, context: Default::default(), data: terms(tsv) })
    }

    fn codes(r: &Response) -> Vec<&str> {
        r.diagnostics.iter().map(|d| d.code.as_str()).collect()
    }

    fn item(key: &str, reading: &str, body: Vec<Inline>) -> Inline {
        Inline::ChannelItem { span: SPAN, channel: "glossary".into(), key: Some(key.into()), reading: Some(reading.into()), body }
    }

    #[test]
    fn declares_the_command_the_channel_and_the_data() {
        let d = describe();
        assert_eq!(d.commands, vec!["term"]);
        assert_eq!(d.channels, vec![ChannelDecl { name: "glossary".into(), order: ChannelOrder::Reading, locators: true }]);
        assert_eq!(d.data, vec!["terms"]);
    }

    #[test]
    fn parses_three_and_four_columns() {
        let tsv = "# word\treading\n\n組版\tくみはん\t版を組むこと\nカーニング\tかーにんぐ\t字間の調整\tkern\n";
        assert_eq!(
            parse(tsv),
            Ok(vec![
                Term { word: "組版".into(), reading: "くみはん".into(), definition: "版を組むこと".into(), see: None },
                Term { word: "カーニング".into(), reading: "かーにんぐ".into(), definition: "字間の調整".into(), see: Some("kern".into()) },
            ])
        );
    }

    #[test]
    fn a_word_without_kanji_is_its_own_reading() {
        let tsv = "カーニング\t\t字間の調整\nGolem\t\t組版システム\nルビ・ふりがな\t\t記号も読みになる\n";
        let readings: Vec<String> = parse(tsv).unwrap().into_iter().map(|t| t.reading).collect();
        assert_eq!(readings, vec!["カーニング", "Golem", "ルビ・ふりがな"]);
    }

    #[test]
    fn a_word_with_kanji_needs_its_reading() {
        assert_eq!(
            parse("組版\t\t版を組むこと\n々\t\tx\n"),
            Err(vec![
                (1, "tsv-no-reading", "terms の 1 行めの語は漢字を含むので、読みが要ります: 組版".into()),
                (2, "tsv-no-reading", "terms の 2 行めの語は漢字を含むので、読みが要ります: 々".into()),
            ])
        );
    }

    #[test]
    fn reports_every_bad_line_with_the_code_of_its_cause() {
        let tsv = "a\tb\n組版\t組版\tx\n語\tご\t\nx\tx\tx\nx\tx\ty\nz\tz\tz\t\n";
        assert_eq!(
            parse(tsv),
            Err(vec![
                (1, "tsv-columns", "terms の 1 行めの欄の数が 3 か 4 ではありません".into()),
                (2, "tsv-reading", "terms の 2 行めの読みには、かなと英数字だけを書きます: 組版".into()),
                (3, "tsv-empty", "terms の 3 行めの語、定義、ラベルのどれかが空です".into()),
                (5, "tsv-duplicate", "terms の 5 行めの語は、前の行にもあります: x".into()),
                (6, "tsv-empty", "terms の 6 行めの語、定義、ラベルのどれかが空です".into()),
            ])
        );
    }

    #[test]
    fn the_check_of_the_data_points_at_the_lines() {
        let at = |line, code: &str, message: &str| DataDiagnostic { code: code.into(), severity: Severity::Error, name: "terms".into(), line, message: message.into() };
        assert_eq!(check_data(&terms(Some(b"a\ta\td\n"))), vec![]);
        assert_eq!(check_data(&terms(None)), vec![]);
        assert_eq!(check_data(&terms(Some(&[0xff]))), vec![at(None, "utf8", "terms が UTF-8 ではありません")]);
        assert_eq!(
            check_data(&terms(Some("# c\nx\n組版\t\td\n".as_bytes()))),
            vec![
                at(Some(2), "tsv-columns", "terms の 2 行めの欄の数が 3 か 4 ではありません"),
                at(Some(3), "tsv-no-reading", "terms の 3 行めの語は漢字を含むので、読みが要ります: 組版"),
            ]
        );
    }

    #[test]
    fn a_term_is_the_word_and_an_item() {
        let r = invoke(command(vec![], vec![vec![text("組版")]], Some("組版\tくみはん\t版を組むこと\n".as_bytes())));
        assert_eq!(r, Response::inlines(vec![text("組版"), item("組版", "くみはん", vec![text("組版"), text("\u{3000}"), text("版を組むこと")])]));
    }

    #[test]
    fn an_empty_reading_sends_the_word_as_the_reading() {
        let r = invoke(command(vec![], vec![vec![text("カーニング")]], Some("カーニング\t\t字間の調整\n".as_bytes())));
        assert_eq!(r, Response::inlines(vec![text("カーニング"), item("カーニング", "カーニング", vec![text("カーニング"), text("\u{3000}"), text("字間の調整")])]));
    }

    #[test]
    fn the_fourth_column_is_a_reference_to_a_page() {
        let t = Term { word: "w".into(), reading: "w".into(), definition: "d".into(), see: Some("sec".into()) };
        assert_eq!(
            entry_body(SPAN, &t),
            vec![text("w"), text("\u{3000}"), text("d"), text("（→"), Inline::Ref { span: SPAN, kind: RefKind::Page, label: "sec".into() }, text("）")]
        );
    }

    #[test]
    fn the_key_is_the_text_of_the_slot_and_its_ruby() {
        let slot = vec![Inline::Ruby {
            span: SPAN,
            segments: vec![RubySegment { base: vec![text("組")], reading: Some("くみ".into()) }, RubySegment { base: vec![text("版")], reading: None }],
        }];
        assert_eq!(plain(&slot), "組版");
        let styled = vec![Inline::CharStyle { span: SPAN, style: "em".into(), body: vec![text("組"), text("版")] }];
        assert_eq!(plain(&styled), "組版");
        let r = invoke(command(vec![], vec![slot.clone()], Some("組版\tくみはん\td\n".as_bytes())));
        assert_eq!(codes(&r), Vec::<&str>::new());
        match &r.output {
            Output::Inlines(xs) => assert_eq!(xs[0], slot[0]),
            o => panic!("{o:?}"),
        }
    }

    #[test]
    fn errors_keep_the_word_in_the_text() {
        let tsv = Some("組版\tくみはん\td\n".as_bytes());
        let one = || vec![vec![text("組版")]];
        let cases: Vec<(Request, &str)> = vec![
            (command(vec![], vec![vec![text("版面")]], tsv), "unknown"),
            (command(vec![], one(), None), "no-data"),
            (command(vec![], one(), Some(&[0xff])), "utf8"),
            (command(vec![], one(), Some("x\n".as_bytes())), "tsv-columns"),
            (command(vec![Arg::Positional(ArgValue::Str("a".into()))], one(), tsv), "args"),
        ];
        for (req, code) in cases {
            let r = invoke(req);
            assert_eq!(codes(&r), vec![code]);
            assert_eq!(r.output, Output::Inlines(vec![text(if code == "unknown" { "版面" } else { "組版" })]));
        }
    }

    #[test]
    fn a_slot_that_is_not_one_word_is_an_error() {
        let tsv = Some(&b"a\ta\td\n"[..]);
        assert_eq!(codes(&invoke(command(vec![], vec![vec![text("a")], vec![text("b")]], tsv))), vec!["slot"]);
        assert_eq!(codes(&invoke(command(vec![], vec![vec![]], tsv))), vec!["slot"]);
        assert_eq!(codes(&invoke(command(vec![], vec![], tsv))), vec!["slot"]);
    }
}
