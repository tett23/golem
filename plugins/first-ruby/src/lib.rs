//! A sample plugin (docs/adr/0131): the filter `first-ruby` puts ruby on
//! the first occurrence in a file of each word of the TSV the project
//! passes as the data `words`:
//!
//! ```toml
//! [plugins.first-ruby]
//! url = "https://github.com/tett23/golem/releases/download/v0.1.0-rc4/first-ruby.wasm"
//! data = { words = "data/words.tsv" }
//!
//! [[filters]]
//! plugin = "first-ruby"
//! filter = "first-ruby"
//! files = ["chapters/01.gm", "chapters/02.gm"]
//! ```
//!
//! A filter sees one file, so the first occurrence is the first in the
//! file. The TSV is that of `ruby_common::parse_tsv`. Headings are left
//! alone and do not count; a ruby of the source counts for the words in
//! its base.

use golem_plugin_sdk::*;
use ruby_common::{read_words, ruby, walk, Dict, Entry, Piece, Visitor};
use std::collections::BTreeSet;

pub const NAME: &str = "first-ruby";

fn describe() -> Description {
    Description { filters: vec![NAME.into()], data: vec!["words".into()], ..Default::default() }
}

/// Puts ruby on the first occurrence of each word.
struct First<'a> {
    dict: &'a Dict,
    seen: BTreeSet<String>,
}

impl Visitor for First<'_> {
    fn text(&mut self, span: Span, text: String) -> Vec<Inline> {
        let mut out = vec![];
        let mut plain = String::new();
        for p in self.dict.scan(&text) {
            match p {
                Piece::Word(w, Entry::Ruby(segs)) if !self.seen.contains(&w) => {
                    if !plain.is_empty() {
                        out.push(Inline::Text { span, text: std::mem::take(&mut plain) });
                    }
                    out.push(ruby(span, segs));
                    self.seen.insert(w);
                }
                Piece::Word(w, _) | Piece::Plain(w) => plain.push_str(&w),
            }
        }
        if !plain.is_empty() {
            out.push(Inline::Text { span, text: plain });
        }
        out
    }

    fn ruby(&mut self, base: &str) {
        for p in self.dict.scan(base) {
            if let Piece::Word(w, Entry::Ruby(_)) = p {
                self.seen.insert(w);
            }
        }
    }
}

pub fn filter(mut doc: Document, data: &Data) -> Response {
    match read_words(data, "words", doc.file, NAME) {
        Ok(Some(dict)) => {
            walk(&mut doc, false, &mut First { dict: &dict, seen: BTreeSet::new() });
            Response::document(doc)
        }
        Ok(None) => {
            let top = Span { file: doc.file, start: 0, end: 0 };
            Response::document(doc).with(Diagnostic {
                code: format!("{NAME}-no-words"),
                severity: Severity::Error,
                span: top,
                message: "manifest.toml の data で words を渡してください".into(),
            })
        }
        Err(ds) => Response { output: Output::Document(doc), diagnostics: ds },
    }
}

pub fn invoke(req: Request) -> Response {
    match req {
        Request::Filter(f) => filter(f.document, &f.data),
        // the host calls only what describe declares: no command, no block command
        Request::Block(b) => Response::blocks(vec![]).with(Diagnostic {
            code: format!("{NAME}-no-command"),
            severity: Severity::Error,
            span: b.span,
            message: format!("{NAME} にコマンドはありません"),
        }),
        Request::Command(c) => Response::inlines(vec![]).with(Diagnostic {
            code: format!("{NAME}-no-command"),
            severity: Severity::Error,
            span: c.span,
            message: format!("{NAME} にコマンドはありません"),
        }),
    }
}

export_plugin!(describe, invoke);

#[cfg(test)]
mod tests;
