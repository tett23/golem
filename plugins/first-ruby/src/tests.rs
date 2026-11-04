use super::*;
use golem_plugin_sdk::{Block, BlockBody, RubySegment, Value};

const SP: Span = Span { file: 2, start: 5, end: 9 };
const TOP: Span = Span { file: 2, start: 0, end: 0 };

fn t(s: &str) -> Inline {
    Inline::Text { span: SP, text: s.into() }
}

fn r(segs: &[(&str, Option<&str>)]) -> Inline {
    Inline::Ruby {
        span: SP,
        segments: segs.iter().map(|(b, r)| RubySegment { base: vec![t(b)], reading: r.map(Into::into) }).collect(),
    }
}

fn para(xs: Vec<Inline>) -> Block {
    Block { span: SP, label: None, body: BlockBody::Paragraph { style: None, inlines: xs } }
}

fn heading(xs: Vec<Inline>) -> Block {
    Block { span: SP, label: None, body: BlockBody::Heading { level: 1, attrs: Value::Null, inlines: xs } }
}

fn words(tsv: &str) -> Data {
    Data(vec![("words".into(), tsv.as_bytes().to_vec())])
}

fn run(blocks: Vec<Block>, tsv: &str) -> (Vec<Block>, Vec<Diagnostic>) {
    let res = filter(Document { file: 2, blocks }, &words(tsv));
    match res.output {
        Output::Document(d) => (d.blocks, res.diagnostics),
        _ => panic!("not a document"),
    }
}

const TSV: &str = "東京\tとうきょう\n東京都庁\t\nお/父/さん\t/とう/\n";

#[test]
fn only_the_first_occurrence_in_the_file() {
    let (bs, ds) = run(vec![para(vec![t("東京と東京")]), para(vec![t("また東京")])], TSV);
    assert_eq!(ds, vec![]);
    assert_eq!(bs, vec![para(vec![r(&[("東京", Some("とうきょう"))]), t("と東京")]), para(vec![t("また東京")])]);
}

#[test]
fn mono_ruby_and_partial_ruby_as_the_tsv_writes() {
    let (bs, _) = run(vec![para(vec![t("お父さんが")])], TSV);
    assert_eq!(bs, vec![para(vec![r(&[("お", None), ("父", Some("とう")), ("さん", None)]), t("が")])]);
}

#[test]
fn a_word_with_no_reading_stops_a_match_and_gets_no_ruby() {
    let (bs, _) = run(vec![para(vec![t("東京都庁と東京")])], TSV);
    assert_eq!(bs, vec![para(vec![t("東京都庁と"), r(&[("東京", Some("とうきょう"))])])]);
}

#[test]
fn headings_are_left_alone_and_do_not_count() {
    let (bs, _) = run(vec![heading(vec![t("東京")]), para(vec![t("東京")])], TSV);
    assert_eq!(bs, vec![heading(vec![t("東京")]), para(vec![r(&[("東京", Some("とうきょう"))])])]);
}

#[test]
fn a_ruby_of_the_source_counts() {
    let src = r(&[("東京", Some("とーきょー"))]);
    let (bs, _) = run(vec![para(vec![src.clone(), t("東京")])], TSV);
    assert_eq!(bs, vec![para(vec![src, t("東京")])]);
}

#[test]
fn a_note_counts_where_its_mark_is() {
    let note = |xs| Inline::Note { span: SP, number: 1, body: xs };
    let (bs, _) = run(vec![para(vec![t("あ"), note(vec![t("東京")]), t("東京")])], TSV);
    assert_eq!(bs, vec![para(vec![t("あ"), note(vec![r(&[("東京", Some("とうきょう"))])]), t("東京")])]);
}

#[test]
fn code_and_kenten_are_left_alone_and_do_not_count() {
    let code = Inline::CharStyle { span: SP, style: "code".into(), body: vec![t("東京")] };
    let kenten = Inline::Kenten { span: SP, shape: None, body: vec![t("東京")] };
    let (bs, _) = run(vec![para(vec![code.clone(), kenten.clone(), t("東京")])], TSV);
    assert_eq!(bs, vec![para(vec![code, kenten, r(&[("東京", Some("とうきょう"))])])]);
}

#[test]
fn without_words_the_document_is_kept_and_an_error_says_so() {
    let res = filter(Document { file: 2, blocks: vec![para(vec![t("東京")])] }, &Data::default());
    assert_eq!(res.output, Output::Document(Document { file: 2, blocks: vec![para(vec![t("東京")])] }));
    assert_eq!(
        res.diagnostics,
        vec![Diagnostic {
            code: "no-words".into(),
            severity: Severity::Error,
            span: TOP,
            message: "manifest.toml の data で words を渡してください".into()
        }]
    );
}

#[test]
fn a_wrong_tsv_keeps_the_document() {
    let (bs, ds) = run(vec![para(vec![t("東京")])], "東京\n");
    assert_eq!(bs, vec![para(vec![t("東京")])]);
    assert_eq!(ds.iter().map(|d| d.code.as_str()).collect::<Vec<_>>(), ["tsv"]);
}

#[test]
fn the_same_bytes_for_the_same_input() {
    let blocks = vec![para(vec![t("東京とお父さん、東京")])];
    let a = cbor_of(run(blocks.clone(), TSV).0);
    let b = cbor_of(run(blocks, TSV).0);
    assert_eq!(a, b);
}

fn cbor_of(bs: Vec<Block>) -> Vec<u8> {
    golem_plugin_sdk::cbor::encode(&golem_plugin_sdk::ir::document_value(&Document { file: 2, blocks: bs }))
}
