//! A sample plugin (docs/adr/0105, docs/adr/0106): `[lookup: key]` gives
//! the value of the key in the TSV the project passes as the data `table`:
//!
//! ```toml
//! [plugins.lookup]
//! url = "https://github.com/tett23/golem/releases/download/v0.1.0-rc4/lookup.wasm"
//! data = { table = "data/words.tsv" }
//! ```
//!
//! Each line of the TSV is a key, a tab and a value; an empty line and a
//! line that starts with `#` are skipped. The first line of a key wins.

use golem_plugin_sdk::*;

fn describe() -> Description {
    Description { commands: vec!["lookup".into()], data: vec!["table".into()], ..Default::default() }
}

/// The value of a key in a TSV, if the TSV has the key.
pub fn find<'a>(tsv: &'a str, key: &str) -> Option<&'a str> {
    tsv.lines()
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
        .filter_map(|l| l.split_once('\t'))
        .find(|(k, _)| *k == key)
        .map(|(_, v)| v)
}

fn plain(xs: &[Inline]) -> String {
    xs.iter()
        .map(|x| match x {
            Inline::Text { text, .. } => text.as_str(),
            _ => "",
        })
        .collect()
}

fn error(span: Span, code: &str, message: String) -> Diagnostic {
    Diagnostic { code: code.into(), severity: Severity::Error, span, message }
}

pub fn invoke(req: Request) -> Response {
    match req {
        Request::Command(c) => {
            let key = c.slots.first().map(|s| plain(s)).unwrap_or_default();
            let tsv = match c.data.get("table").map(std::str::from_utf8) {
                Some(Ok(t)) => t,
                Some(Err(_)) => return Response::inlines(vec![]).with(error(c.span, "lookup-utf8", "table が UTF-8 ではありません".into())),
                None => return Response::inlines(vec![]).with(error(c.span, "lookup-no-table", "manifest.toml で data の table を渡してください".into())),
            };
            match find(tsv, &key) {
                Some(v) => Response::inlines(vec![Inline::Text { span: c.span, text: v.into() }]),
                None => Response::inlines(vec![]).with(error(c.span, "lookup-no-key", format!("table にないキーです: {key}"))),
            }
        }
        Request::Filter(f) => Response::document(f.document),
    }
}

export_plugin!(describe, invoke);

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_the_first_line_of_a_key() {
        let tsv = "# comment\n\nkey\tone\nkey\ttwo\nother\tthree";
        assert_eq!(find(tsv, "key"), Some("one"));
        assert_eq!(find(tsv, "other"), Some("three"));
        assert_eq!(find(tsv, "none"), None);
        assert_eq!(find(tsv, "# comment"), None);
    }

    #[test]
    fn answers_a_command() {
        let span = Span { file: 1, start: 0, end: 9 };
        let req = Request::Command(CommandRequest {
            name: "lookup".into(),
            args: vec![],
            slots: vec![vec![Inline::Text { span, text: "key".into() }]],
            span,
            data: Data(vec![("table".into(), b"key\tvalue\n".to_vec())]),
        });
        assert_eq!(invoke(req), Response::inlines(vec![Inline::Text { span, text: "value".into() }]));
    }
}
