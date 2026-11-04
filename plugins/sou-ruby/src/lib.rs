//! A sample plugin (docs/adr/0130): the filter `sou-ruby` puts ruby on
//! every kanji of a file, by the TSV of words the project passes as the
//! data `words`:
//!
//! ```toml
//! [plugins.sou-ruby]
//! url = "https://github.com/tett23/golem/releases/download/v0.1.0-rc4/sou-ruby.wasm"
//! data = { words = "data/readings.tsv" }
//!
//! [[filters]]
//! plugin = "sou-ruby"
//! filter = "sou-ruby"
//! files = ["chapters/01.gm"]
//! ```
//!
//! The TSV is that of `ruby_common::parse_tsv`; each word gets its ruby
//! at every occurrence, the longest word first. The text no word covers
//! goes to a morphological analyzer, Lindera, when the project passes the
//! files of a dictionary of Lindera as the data `dict-*`
//! ([`lindera_dict::NAMES`]); the plugin embeds no dictionary. A run of
//! kanji with no reading keeps no ruby, and the warning `unread`
//! names it once per file. The ruby of the source is kept as it is.

use golem_plugin_sdk::*;
use ruby_common::{align, has_kanji, is_kanji, read_words, ruby, walk, Dict, Entry, Piece, Visitor};

pub const NAME: &str = "sou-ruby";

fn describe() -> Description {
    let mut data: Vec<String> = lindera_dict::NAMES.iter().map(|(n, _)| n.to_string()).collect();
    data.push("words".into());
    Description { filters: vec![NAME.into()], data, ..Default::default() }
}

/// A morphological analyzer: the words of a text, each with its reading
/// (katakana or hiragana) if it knows one. The words together are the text.
pub trait Analyzer {
    fn tokens(&self, text: &str) -> Vec<(String, Option<String>)>;
}

struct Sou<'a> {
    dict: &'a Dict,
    analyzer: Option<&'a dyn Analyzer>,
    /// the runs of kanji with no reading, each once, with where it is first
    unread: Vec<(String, Span)>,
}

impl Sou<'_> {
    fn unread(&mut self, s: &str, span: Span) {
        if !self.unread.iter().any(|(u, _)| u == s) {
            self.unread.push((s.to_string(), span));
        }
    }

    /// A text no word of the TSV covers.
    fn plain(&mut self, span: Span, text: String, out: &mut Out) {
        if !has_kanji(&text) {
            return out.text(span, &text);
        }
        let Some(a) = self.analyzer else {
            for run in kanji_runs(&text) {
                self.unread(&run, span);
            }
            return out.text(span, &text);
        };
        for (surface, reading) in a.tokens(&text) {
            if !has_kanji(&surface) {
                out.text(span, &surface);
                continue;
            }
            match reading.as_deref().and_then(|r| align(&surface, r)) {
                Some(segs) => {
                    for (b, r) in segs {
                        match r {
                            Some(r) => out.push(ruby(span, &[(b, Some(r))])),
                            None => out.text(span, &b),
                        }
                    }
                }
                None => {
                    self.unread(&surface, span);
                    out.text(span, &surface);
                }
            }
        }
    }
}

/// Inlines with the texts next to each other joined.
#[derive(Default)]
struct Out(Vec<Inline>);

impl Out {
    fn text(&mut self, span: Span, s: &str) {
        if s.is_empty() {
            return;
        }
        if let Some(Inline::Text { text, .. }) = self.0.last_mut() {
            text.push_str(s);
        } else {
            self.0.push(Inline::Text { span, text: s.to_string() });
        }
    }
    fn push(&mut self, x: Inline) {
        self.0.push(x);
    }
}

fn kanji_runs(s: &str) -> Vec<String> {
    let mut runs: Vec<String> = vec![];
    let mut cur = String::new();
    for c in s.chars() {
        if is_kanji(c) {
            cur.push(c);
        } else if !cur.is_empty() {
            runs.push(std::mem::take(&mut cur));
        }
    }
    if !cur.is_empty() {
        runs.push(cur);
    }
    runs
}

impl Visitor for Sou<'_> {
    fn text(&mut self, span: Span, text: String) -> Vec<Inline> {
        let mut out = Out::default();
        for p in self.dict.scan(&text) {
            match p {
                Piece::Word(_, Entry::Ruby(segs)) => out.push(ruby(span, segs)),
                Piece::Word(w, Entry::Stop) => out.text(span, &w),
                Piece::Plain(p) => self.plain(span, p, &mut out),
            }
        }
        out.0
    }

    fn ruby(&mut self, _base: &str) {}
}

/// The filter with an analyzer or none.
pub fn filter_with(mut doc: Document, data: &Data, analyzer: Option<&dyn Analyzer>) -> Response {
    let dict = match read_words(data, "words", doc.file) {
        Ok(Some(d)) => d,
        Ok(None) if analyzer.is_some() => Dict::default(),
        Ok(None) => {
            let top = Span { file: doc.file, start: 0, end: 0 };
            return Response::document(doc).with(Diagnostic {
                code: "no-words".into(),
                severity: Severity::Error,
                span: top,
                message: "manifest.toml の data で words を渡してください".into(),
            });
        }
        Err(ds) => return Response { output: Output::Document(doc), diagnostics: ds },
    };
    let mut v = Sou { dict: &dict, analyzer, unread: vec![] };
    walk(&mut doc, true, &mut v);
    let ds = v
        .unread
        .into_iter()
        .map(|(u, span)| Diagnostic {
            code: "unread".into(),
            severity: Severity::Warning,
            span,
            message: format!("読みの分からない漢字です: {u}"),
        })
        .collect();
    Response { output: Output::Document(doc), diagnostics: ds }
}

/// The filter: an analyzer when the project passes a dictionary of
/// Lindera, none when it passes no file of one.
pub fn filter(doc: Document, data: &Data) -> Response {
    let top = Span { file: doc.file, start: 0, end: 0 };
    match lindera_dict::from_data(data) {
        Ok(None) => filter_with(doc, data, None),
        Ok(Some(a)) => filter_with(doc, data, Some(&a)),
        Err(m) => Response::document(doc).with(Diagnostic { code: "dict".into(), severity: Severity::Error, span: top, message: m }),
    }
}

/// A morphological analyzer of Lindera over a dictionary the project
/// passes as data, the files `lindera build` writes (docs/adr/0130).
pub mod lindera_dict {
    use golem_plugin_sdk::Data;
    use lindera::dictionary::Dictionary;
    use lindera::mode::Mode;
    use lindera::segmenter::Segmenter;
    use lindera_dictionary::dictionary::{
        character_definition::CharacterDefinition, connection_cost_matrix::ConnectionCostMatrix, metadata::Metadata,
        prefix_dictionary::PrefixDictionary, unknown_dictionary::UnknownDictionary,
    };
    use std::borrow::Cow;
    use std::sync::Arc;

    /// The names of the data, each a file of the dictionary.
    pub const NAMES: [(&str, &str); 9] = [
        ("dict-char-def", "char_def.bin"),
        ("dict-matrix", "matrix.mtx"),
        ("dict-metadata", "metadata.json"),
        ("dict-trie", "dict.trie"),
        ("dict-unk", "unk.bin"),
        ("dict-vals", "dict.vals"),
        ("dict-vals-idx", "dict.valsidx"),
        ("dict-words", "dict.words"),
        ("dict-words-idx", "dict.wordsidx"),
    ];

    pub struct Lindera(Segmenter);

    /// The analyzer of the dictionary of the data; none when the data has
    /// no file of it. Some files but not all, a file Lindera cannot read
    /// and a dictionary with no field `reading` are errors.
    pub fn from_data(data: &Data) -> Result<Option<Lindera>, String> {
        let missing: Vec<&str> = NAMES.iter().map(|(n, _)| *n).filter(|n| data.get(n).is_none()).collect();
        if missing.len() == NAMES.len() {
            return Ok(None);
        }
        if !missing.is_empty() {
            return Err(format!("辞書のファイルが足りません: {}", missing.join("、")));
        }
        let get = |n: &str| data.get(n).map(<[u8]>::to_vec).unwrap_or_default();
        fn bad(n: &'static str) -> impl Fn(lindera::error::LinderaError) -> String {
            move |e| format!("辞書のファイルを読めません: {n}: {e}")
        }
        let metadata = Metadata::load(&get("dict-metadata")).map_err(bad("dict-metadata"))?;
        metadata.validate_format_version().map_err(bad("dict-metadata"))?;
        if metadata.dictionary_schema.get_field_index("reading").is_none() {
            return Err("辞書に読み（reading）の欄がありません".into());
        }
        let dict = Dictionary {
            prefix_dictionary: Arc::new(
                PrefixDictionary::load(get("dict-trie"), get("dict-vals-idx"), get("dict-vals"), get("dict-words-idx"), get("dict-words"))
                    .map_err(bad("dict-trie"))?,
            ),
            connection_cost_matrix: Arc::new(ConnectionCostMatrix::load(get("dict-matrix")).map_err(bad("dict-matrix"))?),
            character_definition: Arc::new(CharacterDefinition::load(&get("dict-char-def")).map_err(bad("dict-char-def"))?),
            unknown_dictionary: Arc::new(UnknownDictionary::load(&get("dict-unk")).map_err(bad("dict-unk"))?),
            metadata: Arc::new(metadata),
        };
        Ok(Some(Lindera(Segmenter::new(Mode::Normal, dict, None))))
    }

    impl super::Analyzer for Lindera {
        fn tokens(&self, text: &str) -> Vec<(String, Option<String>)> {
            // segmenting fails only on a dictionary that is not consistent:
            // the text then has no reading
            let Ok(mut ts) = self.0.segment(Cow::Borrowed(text)) else {
                return vec![(text.to_string(), None)];
            };
            ts.iter_mut()
                .map(|t| {
                    let s = t.surface.to_string();
                    let r = t.get("reading").filter(|r| *r != "*" && !r.is_empty()).map(String::from);
                    (s, r)
                })
                .collect()
        }
    }
}

pub fn invoke(req: Request) -> Response {
    match req {
        Request::Filter(f) => filter(f.document, &f.data),
        // the host calls only what describe declares: no command, no block command
        Request::Block(b) => Response::blocks(vec![]).with(Diagnostic {
            code: "no-command".into(),
            severity: Severity::Error,
            span: b.span,
            message: format!("{NAME} にコマンドはありません"),
        }),
        Request::Command(c) => Response::inlines(vec![]).with(Diagnostic {
            code: "no-command".into(),
            severity: Severity::Error,
            span: c.span,
            message: format!("{NAME} にコマンドはありません"),
        }),
    }
}

export_plugin!(describe, invoke);

#[cfg(test)]
mod tests;
