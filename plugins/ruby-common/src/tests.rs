use super::*;

fn seg(b: &str, r: Option<&str>) -> (String, Option<String>) {
    (b.into(), r.map(Into::into))
}

fn err(line: usize, message: &str) -> TsvError {
    TsvError { line, message: message.into() }
}

const SP: Span = Span { file: 3, start: 10, end: 20 };

fn t(s: &str) -> Inline {
    Inline::Text { span: SP, text: s.into() }
}

#[test]
fn a_tsv_of_words_and_readings() {
    let d = parse_tsv("# comment\n\n東京\tとうきょう\r\n東/京/都\tとう/きょう/と\nお/父/さん\t/とう/\n東京駅\t\n").unwrap();
    assert_eq!(d.get("東京"), Some(&Entry::Ruby(vec![seg("東京", Some("とうきょう"))])));
    assert_eq!(d.get("東京都"), Some(&Entry::Ruby(vec![seg("東", Some("とう")), seg("京", Some("きょう")), seg("都", Some("と"))])));
    assert_eq!(d.get("お父さん"), Some(&Entry::Ruby(vec![seg("お", None), seg("父", Some("とう")), seg("さん", None)])));
    assert_eq!(d.get("東京駅"), Some(&Entry::Stop));
    assert_eq!(d.get("# comment"), None);
}

#[test]
fn every_wrong_line_of_a_tsv() {
    let tsv = "東京\tとうきょう\n語だけ\n語\t読み\t余り\n\tよみ\n東京\tひがしきょう\n東京\tとう/きょう\n東/京\tとうきょう\n東//京\tとう//きょう\n東/京\tとう/きょう\nお/父\t/\n";
    assert_eq!(
        parse_tsv(tsv),
        Err(vec![
            err(2, "語と読みをタブで区切った二つの欄がありません"),
            err(3, "欄が三つ以上あります"),
            err(4, "語が空です"),
            err(5, "語が重複しています（1 行め）: 東京"),
            err(6, "語と読みの / で区切った数が一致しません"),
            err(7, "語と読みの / で区切った数が一致しません"),
            err(8, "語の / のあいだが空です"),
            err(9, "語が重複しています（1 行め）: 東京"),
            err(10, "読みのない区切りだけの読みです。ルビを振らない語は読みを空にします"),
        ])
    );
}

#[test]
fn the_leftmost_longest_word() {
    let d = parse_tsv("東京\tとうきょう\n東京都\tとうきょうと\n京都\tきょうと\n都庁\t\n").unwrap();
    let w = |s: &str| Piece::Word(s.into(), d.get(s).unwrap());
    assert_eq!(d.scan("東京都庁へ"), vec![w("東京都"), Piece::Plain("庁へ".into())]);
    assert_eq!(d.scan("京都と東京"), vec![w("京都"), Piece::Plain("と".into()), w("東京")]);
    assert_eq!(d.scan("都庁"), vec![w("都庁")]);
    assert_eq!(d.scan("なし"), vec![Piece::Plain("なし".into())]);
    assert_eq!(d.scan(""), vec![]);
}

#[test]
fn kanji() {
    for c in ['漢', '々', '〆', '〇', 'ヶ', '\u{20B9F}', '\u{3400}', '\u{F900}'] {
        assert!(is_kanji(c), "{c}");
    }
    for c in ['ひ', 'カ', 'A', '1', '、', 'ー'] {
        assert!(!is_kanji(c), "{c}");
    }
}

#[test]
fn katakana_to_hiragana() {
    assert_eq!(hiragana("カタカナとひらがなとABCとヴとー"), "かたかなとひらがなとABCとゔとー");
}

#[test]
fn the_reading_of_each_run_of_kanji() {
    assert_eq!(align("東京", "とうきょう"), Some(vec![seg("東京", Some("とうきょう"))]));
    assert_eq!(align("引張り", "ひっぱり"), Some(vec![seg("引張", Some("ひっぱ")), seg("り", None)]));
    assert_eq!(
        align("取り扱い", "とりあつかい"),
        Some(vec![seg("取", Some("と")), seg("り", None), seg("扱", Some("あつか")), seg("い", None)])
    );
    assert_eq!(align("大きい", "おおきい"), Some(vec![seg("大", Some("おお")), seg("きい", None)]));
    assert_eq!(align("お茶", "おちゃ"), Some(vec![seg("お", None), seg("茶", Some("ちゃ"))]));
    assert_eq!(align("一ヶ月", "いっかげつ"), Some(vec![seg("一ヶ月", Some("いっかげつ"))]));
    assert_eq!(align("カタカナ", "かたかな"), Some(vec![seg("カタカナ", None)]));
    assert_eq!(align("書く", "よむ"), None);
    assert_eq!(align("書く", "く"), None);
    assert_eq!(align("漢字", ""), None);
}

#[test]
fn the_text_of_inlines() {
    let xs = vec![t("参"), Inline::CharStyle { span: SP, style: "bold".into(), body: vec![t("謀")] }, Inline::LineBreak { span: SP }];
    assert_eq!(plain_text(&xs), "参謀");
}

#[test]
fn a_ruby_of_segments() {
    assert_eq!(
        ruby(SP, &[seg("お", None), seg("父", Some("とう"))]),
        Inline::Ruby {
            span: SP,
            segments: vec![
                RubySegment { base: vec![t("お")], reading: None },
                RubySegment { base: vec![t("父")], reading: Some("とう".into()) }
            ]
        }
    );
}

/// Records what it sees and puts every text in brackets.
#[derive(Default)]
struct Seen(Vec<String>);

impl Visitor for Seen {
    fn text(&mut self, span: Span, text: String) -> Vec<Inline> {
        self.0.push(text.clone());
        vec![Inline::Text { span, text: format!("<{text}>") }]
    }
    fn ruby(&mut self, base: &str) {
        self.0.push(format!("ruby:{base}"));
    }
}

fn block(body: BlockBody) -> Block {
    Block { span: SP, label: None, body }
}

fn para(xs: Vec<Inline>) -> Block {
    block(BlockBody::Paragraph { style: None, inlines: xs })
}

fn doc() -> Document {
    let kept = vec![
        Inline::CharStyle { span: SP, style: "code".into(), body: vec![t("code")] },
        Inline::Kenten { span: SP, shape: None, body: vec![t("kenten")] },
        Inline::Tcy { span: SP, text: "12".into() },
        Inline::IndexMark { span: SP, terms: vec!["語".into()], readings: vec!["ご".into()] },
        Inline::ChannelItem { span: SP, channel: "c".into(), key: None, reading: None, body: vec![t("item")] },
        Inline::ProofComment { span: SP, text: "comment".into() },
    ];
    Document {
        file: 3,
        blocks: vec![
            block(BlockBody::Heading { level: 1, attrs: Value::Null, inlines: vec![t("head")] }),
            para(
                [
                    vec![
                        t("a"),
                        Inline::Note { span: SP, number: 1, body: vec![t("note")] },
                        Inline::Color { span: SP, swatch: "red".into(), body: vec![t("red")] },
                        Inline::Ruby { span: SP, segments: vec![RubySegment { base: vec![t("参謀")], reading: Some("さんぼう".into()) }] },
                    ],
                    kept,
                    vec![t("b")],
                ]
                .concat(),
            ),
            block(BlockBody::BulletList(vec![ListItem { number: None, blocks: vec![para(vec![t("item")])] }])),
            block(BlockBody::Table { alignments: vec![0], header: vec![vec![t("h")]], rows: vec![vec![vec![t("c")]]] }),
            block(BlockBody::DefList(vec![DefGroup { terms: vec![vec![t("term")]], defs: vec![vec![para(vec![t("def")])]] }])),
            block(BlockBody::Other(Value::Array(vec![Value::Int(7)]))),
        ],
    }
}

#[test]
fn the_runs_in_the_order_of_the_document() {
    let mut d = doc();
    let mut v = Seen::default();
    walk(&mut d, false, &mut v);
    assert_eq!(v.0, ["a", "note", "red", "ruby:参謀", "b", "item", "h", "c", "term", "def"]);
    let mut v = Seen::default();
    walk(&mut doc(), true, &mut v);
    assert_eq!(v.0[0], "head");
    // the texts are what the visitor gives; the rest is as it was
    let BlockBody::Paragraph { inlines, .. } = &d.blocks[1].body else { panic!() };
    assert_eq!(inlines[0], t("<a>"));
    assert_eq!(inlines[4..10], doc_para()[4..10]);
    assert_eq!(d.blocks[0], doc().blocks[0]);
}

fn doc_para() -> Vec<Inline> {
    let BlockBody::Paragraph { inlines, .. } = doc().blocks[1].body.clone() else { panic!() };
    inlines
}

#[test]
fn the_words_a_project_passes() {
    let data = |b: &[u8]| Data(vec![("words".into(), b.to_vec())]);
    assert_eq!(read_words(&Data::default(), "words", 3), Ok(None));
    assert_eq!(read_words(&data("東京\tとうきょう\n".as_bytes()), "words", 3).unwrap().unwrap().get("東京").is_some(), true);
    let top = Span { file: 3, start: 0, end: 0 };
    assert_eq!(
        read_words(&data(b"\xff"), "words", 3),
        Err(vec![Diagnostic { code: "utf8".into(), severity: Severity::Error, span: top, message: "words が UTF-8 ではありません".into() }])
    );
    assert_eq!(
        read_words(&data("a\nb\n".as_bytes()), "words", 3),
        Err(vec![
            Diagnostic {
                code: "tsv".into(),
                severity: Severity::Error,
                span: top,
                message: "words の 1 行め: 語と読みをタブで区切った二つの欄がありません".into()
            },
            Diagnostic {
                code: "tsv".into(),
                severity: Severity::Error,
                span: top,
                message: "words の 2 行め: 語と読みをタブで区切った二つの欄がありません".into()
            },
        ])
    );
}
