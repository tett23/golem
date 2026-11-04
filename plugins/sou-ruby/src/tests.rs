use super::*;
use golem_plugin_sdk::{Block, BlockBody, RubySegment, Value};

const SP: Span = Span { file: 2, start: 5, end: 9 };

fn t(s: &str) -> Inline {
    Inline::Text { span: SP, text: s.into() }
}

fn r(segs: &[(&str, Option<&str>)]) -> Inline {
    Inline::Ruby {
        span: SP,
        segments: segs.iter().map(|(b, r)| RubySegment { base: vec![t(b)], reading: r.map(Into::into) }).collect(),
    }
}

fn g(b: &str, reading: &str) -> Inline {
    r(&[(b, Some(reading))])
}

fn para(xs: Vec<Inline>) -> Block {
    Block { span: SP, label: None, body: BlockBody::Paragraph { style: None, inlines: xs } }
}

fn words(tsv: &str) -> Data {
    Data(vec![("words".into(), tsv.as_bytes().to_vec())])
}

fn run(blocks: Vec<Block>, data: &Data, a: Option<&dyn Analyzer>) -> (Vec<Block>, Vec<Diagnostic>) {
    let res = filter_with(Document { file: 2, blocks }, data, a);
    match res.output {
        Output::Document(d) => (d.blocks, res.diagnostics),
        _ => panic!("not a document"),
    }
}

fn unread(s: &str) -> Diagnostic {
    Diagnostic { code: "sou-ruby-unread".into(), severity: Severity::Warning, span: SP, message: format!("読みの分からない漢字です: {s}") }
}

const TSV: &str = "東京\tとうきょう\n住/む\tす/\n今日\t\n";

#[test]
fn every_occurrence_of_each_word() {
    let (bs, ds) = run(vec![para(vec![t("東京に住む。東京")])], &words(TSV), None);
    assert_eq!(ds, vec![]);
    assert_eq!(bs, vec![para(vec![g("東京", "とうきょう"), t("に"), r(&[("住", Some("す")), ("む", None)]), t("。"), g("東京", "とうきょう")])]);
}

#[test]
fn kanji_no_word_covers_is_a_warning_once_a_file() {
    let (bs, ds) = run(vec![para(vec![t("東京の大阪と大阪と京都")])], &words(TSV), None);
    assert_eq!(bs, vec![para(vec![g("東京", "とうきょう"), t("の大阪と大阪と京都")])]);
    assert_eq!(ds, vec![unread("大阪"), unread("京都")]);
}

#[test]
fn a_word_with_no_reading_keeps_its_kanji_without_a_warning() {
    let (bs, ds) = run(vec![para(vec![t("今日")])], &words(TSV), None);
    assert_eq!((bs, ds), (vec![para(vec![t("今日")])], vec![]));
}

#[test]
fn headings_get_ruby_too() {
    let h = |xs| Block { span: SP, label: None, body: BlockBody::Heading { level: 1, attrs: Value::Null, inlines: xs } };
    let (bs, _) = run(vec![h(vec![t("東京")])], &words(TSV), None);
    assert_eq!(bs, vec![h(vec![g("東京", "とうきょう")])]);
}

#[test]
fn the_ruby_of_the_source_is_kept() {
    let src = g("東京", "とーきょー");
    let (bs, ds) = run(vec![para(vec![src.clone()])], &words(TSV), None);
    assert_eq!((bs, ds), (vec![para(vec![src])], vec![]));
}

#[test]
fn without_words_and_an_analyzer_an_error() {
    let (bs, ds) = run(vec![para(vec![t("東京")])], &Data::default(), None);
    assert_eq!(bs, vec![para(vec![t("東京")])]);
    assert_eq!(ds.iter().map(|d| d.code.as_str()).collect::<Vec<_>>(), ["sou-ruby-no-words"]);
}

/// Splits a text at 。 and reads 大阪 and 書き込む; nothing else.
struct Fake;

impl Analyzer for Fake {
    fn tokens(&self, text: &str) -> Vec<(String, Option<String>)> {
        let mut out = vec![];
        let mut rest = text;
        while !rest.is_empty() {
            let known = [("大阪", Some("オオサカ")), ("書き込む", Some("カキコム")), ("京都", None), ("変", Some("ヘン"))];
            let hit = known.iter().find(|(w, _)| rest.starts_with(w));
            match hit {
                Some((w, rd)) => {
                    out.push((w.to_string(), rd.map(Into::into)));
                    rest = &rest[w.len()..];
                }
                None => {
                    let c = rest.chars().next().unwrap();
                    out.push((c.to_string(), None));
                    rest = &rest[c.len_utf8()..];
                }
            }
        }
        out
    }
}

#[test]
fn an_analyzer_reads_what_no_word_covers() {
    let (bs, ds) = run(vec![para(vec![t("東京の大阪に書き込む。京都")])], &words(TSV), Some(&Fake));
    assert_eq!(
        bs,
        vec![para(vec![
            g("東京", "とうきょう"),
            t("の"),
            g("大阪", "おおさか"),
            t("に"),
            g("書", "か"),
            t("き"),
            g("込", "こ"),
            t("む。京都"),
        ])]
    );
    assert_eq!(ds, vec![unread("京都")]);
}

#[test]
fn an_analyzer_without_words() {
    let (bs, ds) = run(vec![para(vec![t("大阪")])], &Data::default(), Some(&Fake));
    assert_eq!((bs, ds), (vec![para(vec![g("大阪", "おおさか")])], vec![]));
}

fn dict_error(data: &Data) -> Vec<Diagnostic> {
    let res = filter(Document { file: 2, blocks: vec![para(vec![t("東京")])] }, data);
    assert_eq!(res.output, Output::Document(Document { file: 2, blocks: vec![para(vec![t("東京")])] }));
    res.diagnostics
}

#[test]
fn some_files_of_a_dictionary_but_not_all_is_an_error() {
    let mut d = words(TSV);
    d.0.push(("dict-matrix".into(), vec![0; 4]));
    let ds = dict_error(&d);
    assert_eq!(ds.len(), 1);
    assert_eq!(ds[0].code, "sou-ruby-dict");
    assert_eq!(
        ds[0].message,
        "辞書のファイルが足りません: dict-char-def、dict-metadata、dict-trie、dict-unk、dict-vals、dict-vals-idx、dict-words、dict-words-idx"
    );
}

#[test]
fn a_dictionary_lindera_cannot_read_is_an_error() {
    let d = Data(lindera_dict::NAMES.iter().map(|(n, _)| (n.to_string(), b"{}".to_vec())).collect());
    let ds = dict_error(&d);
    assert_eq!(ds.iter().map(|d| d.code.as_str()).collect::<Vec<_>>(), ["sou-ruby-dict"]);
    assert!(ds[0].message.starts_with("辞書のファイルを読めません: dict-metadata: "), "{}", ds[0].message);
}

#[test]
fn the_plugin_takes_the_files_of_a_dictionary_and_words() {
    let d = describe();
    assert_eq!(d.filters, ["sou-ruby"]);
    assert_eq!(
        d.data,
        ["dict-char-def", "dict-matrix", "dict-metadata", "dict-trie", "dict-unk", "dict-vals", "dict-vals-idx", "dict-words", "dict-words-idx", "words"]
    );
}
