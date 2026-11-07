//! A sample plugin (docs/adr/0129): the block command `@tsv-table name`
//! makes a table of the TSV the project passes as the data `name`:
//!
//! ```toml
//! [plugins.tsv-table]
//! url = "https://github.com/tett23/golem/releases/download/v0.1.0-rc4/tsv-table.wasm"
//! data = { sales = "data/sales.tsv", costs = "data/costs.tsv" }
//! ```
//!
//! ```text
//! @tsv-table sales align=left,right
//! ```
//!
//! The TSV is read as `@table` reads one (golem-eval ADR 0004, docs/adr/0043):
//! UTF-8, a BOM skipped, LF or CRLF ending a line, one line end at the end
//! dropped, tabs separating the cells and nothing else special; the first
//! line is the header, and every line has as many cells as the header. The
//! limits are those of `@table` (10,000 lines with the header, 256
//! cells in a line), and 8 MiB and 50,000 cells in all, which keep a call within its
//! fuel. The table is the one `@table` makes, its nodes at the call.

use golem_plugin_sdk::*;

/// The most bytes of a TSV: half of what `@table` reads (docs/adr/0043), so
/// that a TSV of Japanese text and MAX_TOTAL_CELLS stays within the fuel
/// of a call (docs/adr/0129).
pub const MAX_BYTES: usize = 8 * 1024 * 1024;
/// The most lines of a TSV, the header with them.
pub const MAX_ROWS: usize = 10_000;
/// The most cells in a line.
pub const MAX_CELLS: usize = 256;
/// The most cells of a table, the header with them: a table of this many
/// cells and MAX_BYTES stays within the fuel of a call (docs/adr/0129).
pub const MAX_TOTAL_CELLS: usize = 50_000;

fn describe() -> Description {
    Description { blocks: vec!["tsv-table".into()], data: vec!["*".into()], ..Default::default() }
}

/// Why a TSV gives no table; each is one code.
#[derive(Debug, PartialEq, Eq)]
pub enum TsvError {
    /// not UTF-8, on this line
    NotUtf8(usize),
    /// a CR not before an LF, on this line
    LoneCr(usize),
    /// nothing but a BOM and a line end
    Empty,
    /// a line with another number of cells than the header: the line, its cells, the header's
    Cells(usize, usize, usize),
    /// over MAX_BYTES, with the bytes
    TooLarge(usize),
    /// over MAX_ROWS, at this line
    TooManyRows(usize),
    /// over MAX_CELLS, at this line
    TooManyCells(usize),
    /// over MAX_TOTAL_CELLS, at this line
    TooManyCellsInAll(usize),
}

/// The lines of a TSV as cells, the header first.
pub fn parse(bytes: &[u8]) -> Result<Vec<Vec<&str>>, TsvError> {
    if bytes.len() > MAX_BYTES {
        return Err(TsvError::TooLarge(bytes.len()));
    }
    let text = std::str::from_utf8(bytes).map_err(|e| TsvError::NotUtf8(line_of(&bytes[..e.valid_up_to()])))?;
    if let Some(at) = lone_cr(text) {
        return Err(TsvError::LoneCr(line_of(&bytes[..at])));
    }
    let text = text.strip_prefix('\u{feff}').unwrap_or(text);
    let body = text.strip_suffix("\r\n").or_else(|| text.strip_suffix('\n')).unwrap_or(text);
    if body.is_empty() {
        return Err(TsvError::Empty);
    }
    let mut rows: Vec<Vec<&str>> = Vec::new();
    let mut total = 0;
    for (i, line) in body.split('\n').enumerate() {
        let n = i + 1;
        if n > MAX_ROWS {
            return Err(TsvError::TooManyRows(n));
        }
        let line = line.strip_suffix('\r').unwrap_or(line);
        let cells: Vec<&str> = line.split('\t').take(MAX_CELLS + 1).collect();
        if cells.len() > MAX_CELLS {
            return Err(TsvError::TooManyCells(n));
        }
        total += cells.len();
        if total > MAX_TOTAL_CELLS {
            return Err(TsvError::TooManyCellsInAll(n));
        }
        if let Some(h) = rows.first() {
            if cells.len() != h.len() {
                return Err(TsvError::Cells(n, cells.len(), h.len()));
            }
        }
        rows.push(cells);
    }
    Ok(rows)
}

/// The line the end of these bytes is on, from 1.
fn line_of(before: &[u8]) -> usize {
    before.iter().filter(|&&c| c == b'\n').count() + 1
}

/// The offset of the first CR that is not before an LF.
fn lone_cr(text: &str) -> Option<usize> {
    // match_indices searches a word at a time, a byte loop would cost a few instructions a byte
    text.match_indices('\r').map(|(i, _)| i).find(|&i| text.as_bytes().get(i + 1) != Some(&b'\n'))
}

/// The alignments of `align=`, by column, as the CDDL writes them
/// (0 default, 1 left, 2 center, 3 right); one value is for every column.
pub fn alignments(value: &str, columns: usize) -> Result<Vec<u8>, String> {
    let one = |v: &str| match v.trim() {
        "default" => Ok(0),
        "left" => Ok(1),
        "center" => Ok(2),
        "right" => Ok(3),
        other => Err(format!("align の値は left、center、right、default のどれかです: {other}")),
    };
    let values = value.split(',').map(one).collect::<Result<Vec<u8>, String>>()?;
    match values.as_slice() {
        [a] => Ok(vec![*a; columns]),
        _ if values.len() == columns => Ok(values),
        _ => Err(format!("align の値の数が表の列の数と違います（列は {columns}、align は {}）", values.len())),
    }
}

fn error(span: Span, code: &str, message: String) -> Diagnostic {
    Diagnostic { code: code.into(), severity: Severity::Error, span, message }
}

/// A cell at the call: no inlines when it is empty, as `@table`'s TSV.
fn cell(span: Span, t: &str) -> Vec<Inline> {
    if t.is_empty() {
        vec![]
    } else {
        vec![Inline::Text { span, text: t.into() }]
    }
}

/// The table of a block command request, or the diagnostic of why there is none.
pub fn table(req: &BlockCommandRequest) -> Result<Block, Diagnostic> {
    let span = req.span;
    let mut name = None;
    let mut align = None;
    let mut positional = 0;
    for a in &req.args {
        match a {
            Arg::Positional(v) => {
                positional += 1;
                if let ArgValue::Str(s) = v {
                    name = Some(s.as_str());
                }
            }
            Arg::Keyword(k, v) if k == "align" => match v {
                ArgValue::Str(s) => align = Some(s.as_str()),
                _ => return Err(error(span, "align", "align の値は left、center、right、default のどれかです".into())),
            },
            Arg::Keyword(k, _) => return Err(error(span, "key", format!("@tsv-table のキーワード引数は align だけです: {k}"))),
        }
    }
    let name = match (positional, name) {
        (1, Some(n)) => n,
        _ => return Err(error(span, "name", "@tsv-table にはデータの名前を一つ書きます".into())),
    };
    if !req.body.is_empty() {
        return Err(error(span, "body", "@tsv-table は字下げした行を取りません".into()));
    }
    let bytes = req.data.get(name).ok_or_else(|| {
        error(span, "no-data", format!("manifest.toml の data にない名前です: {name}"))
    })?;
    let rows = parse(bytes).map_err(|e| {
        let (code, message) = match e {
            TsvError::NotUtf8(l) => ("utf8", format!("{name} の {l} 行目が UTF-8 ではありません")),
            TsvError::LoneCr(l) => ("cr", format!("{name} の {l} 行目に LF の前にない CR があります")),
            TsvError::Empty => ("empty", format!("{name} が空です")),
            TsvError::Cells(l, n, h) => {
                ("cells", format!("{name} の {l} 行目のセルの数が見出しの行と違います（見出しの行は {h}、この行は {n}）"))
            }
            TsvError::TooLarge(n) => ("limit", format!("{name} が大きさの上限を超えます（{n} バイト、上限は {MAX_BYTES} バイト）")),
            TsvError::TooManyRows(l) => ("limit", format!("{name} が行の数の上限を超えます（{l} 行目、上限は {MAX_ROWS} 行）")),
            TsvError::TooManyCells(l) => {
                ("limit", format!("{name} がセルの数の上限を超えます（{l} 行目、上限は 1 行に {MAX_CELLS} 個）"))
            }
            TsvError::TooManyCellsInAll(l) => {
                ("limit", format!("{name} がセルの数の合計の上限を超えます（{l} 行目、上限は {MAX_TOTAL_CELLS} 個）"))
            }
        };
        error(span, code, message)
    })?;
    let (header, body) = rows.split_first().expect("parse gives a header");
    let alignments = match align {
        None => vec![0; header.len()],
        Some(v) => alignments(v, header.len()).map_err(|m| error(span, "align", m))?,
    };
    Ok(Block {
        span,
        label: None,
        lang: None,
        body: BlockBody::Table {
            alignments,
            header: header.iter().map(|t| cell(span, t)).collect(),
            rows: body.iter().map(|r| r.iter().map(|t| cell(span, t)).collect()).collect(),
        },
    })
}

pub fn invoke(req: Request) -> Response {
    match req {
        Request::Block(b) => match table(&b) {
            Ok(t) => Response::blocks(vec![t]),
            Err(d) => Response::blocks(vec![]).with(d),
        },
        Request::Command(_) => Response::inlines(vec![]),
        Request::Filter(f) => Response::document(f.document),
    }
}

export_plugin!(describe, invoke);

#[cfg(test)]
mod tests {
    use super::*;

    const SPAN: Span = Span { file: 1, start: 0, end: 16 };

    fn request(args: Vec<Arg>, data: &[(&str, &[u8])]) -> BlockCommandRequest {
        BlockCommandRequest {
            name: "tsv-table".into(),
            args,
            body: vec![],
            span: SPAN,
            context: Context::default(),
            data: Data(data.iter().map(|(n, b)| (n.to_string(), b.to_vec())).collect()),
        }
    }

    fn named(n: &str) -> Arg {
        Arg::Positional(ArgValue::Str(n.into()))
    }

    fn code(r: Result<Block, Diagnostic>) -> String {
        r.expect_err("a table").code
    }

    #[test]
    fn reads_a_tsv_as_table_does() {
        assert_eq!(parse(b"a\tb\n1\t2\n").unwrap(), vec![vec!["a", "b"], vec!["1", "2"]]);
        // CRLF, a BOM, no line end at the end
        assert_eq!(parse("\u{feff}a\tb\r\n1\t2".as_bytes()).unwrap(), vec![vec!["a", "b"], vec!["1", "2"]]);
        // quotes and backslashes are text
        assert_eq!(parse(b"\"a\"\t\\b\n").unwrap(), vec![vec!["\"a\"", "\\b"]]);
        // an empty line in the middle is a line of one empty cell
        assert_eq!(parse(b"a\n\nb\n").unwrap(), vec![vec!["a"], vec![""], vec!["b"]]);
        // only one line end at the end is dropped
        assert_eq!(parse(b"a\n\n").unwrap(), vec![vec!["a"], vec![""]]);
        // empty cells
        assert_eq!(parse(b"a\t\tc\n\t\t\n").unwrap(), vec![vec!["a", "", "c"], vec!["", "", ""]]);
    }

    #[test]
    fn rejects_what_table_rejects() {
        assert_eq!(parse(b""), Err(TsvError::Empty));
        assert_eq!(parse(b"\n"), Err(TsvError::Empty));
        assert_eq!(parse("\u{feff}".as_bytes()), Err(TsvError::Empty));
        assert_eq!(parse(b"a\tb\n1\n"), Err(TsvError::Cells(2, 1, 2)));
        assert_eq!(parse(b"a\nb\rc\n"), Err(TsvError::LoneCr(2)));
        assert_eq!(parse(b"a\n\xff\n"), Err(TsvError::NotUtf8(2)));
    }

    #[test]
    fn limits() {
        let rows = |n: usize| "a\n".repeat(n);
        assert!(parse(rows(MAX_ROWS).as_bytes()).is_ok());
        assert_eq!(parse(rows(MAX_ROWS + 1).as_bytes()), Err(TsvError::TooManyRows(MAX_ROWS + 1)));
        let cells = |n: usize| vec!["x"; n].join("\t");
        assert!(parse(cells(MAX_CELLS).as_bytes()).is_ok());
        assert_eq!(parse(format!("a\n{}", cells(MAX_CELLS + 1)).as_bytes()), Err(TsvError::TooManyCells(2)));
        // 50,000 cells in all: 10,000 lines of 5 cells, but not of 6
        let wide = |n: usize| format!("{}\n", vec!["x"; n].join("\t")).repeat(MAX_ROWS);
        assert!(parse(wide(5).as_bytes()).is_ok());
        assert_eq!(parse(wide(6).as_bytes()), Err(TsvError::TooManyCellsInAll(8334)));
        let big = vec![b'a'; MAX_BYTES + 1];
        assert_eq!(parse(&big), Err(TsvError::TooLarge(MAX_BYTES + 1)));
    }

    #[test]
    fn alignments_as_table() {
        assert_eq!(alignments("right", 3), Ok(vec![3, 3, 3]));
        assert_eq!(alignments("left, center ,default", 3), Ok(vec![1, 2, 0]));
        assert!(alignments("left,right", 3).is_err());
        assert!(alignments("middle", 1).is_err());
        assert!(alignments("", 1).is_err());
    }

    #[test]
    fn makes_the_table_at_the_call() {
        let b = table(&request(vec![named("sales"), Arg::Keyword("align".into(), ArgValue::Str("left,right".into()))], &[("sales", b"a\tb\n1\t\n")])).unwrap();
        assert_eq!(b.span, SPAN);
        assert_eq!(b.label, None);
        let t = |s: &str| vec![Inline::Text { span: SPAN, text: s.into() }];
        assert_eq!(b.body, BlockBody::Table { alignments: vec![1, 3], header: vec![t("a"), t("b")], rows: vec![vec![t("1"), vec![]]] });
    }

    #[test]
    fn the_errors_of_a_call() {
        let tsv: &[(&str, &[u8])] = &[("sales", b"a\n")];
        assert_eq!(code(table(&request(vec![], tsv))), "name");
        assert_eq!(code(table(&request(vec![named("sales"), named("x")], tsv))), "name");
        assert_eq!(code(table(&request(vec![Arg::Positional(ArgValue::Int(1))], tsv))), "name");
        assert_eq!(code(table(&request(vec![named("costs")], tsv))), "no-data");
        assert_eq!(code(table(&request(vec![named("sales"), Arg::Keyword("src".into(), ArgValue::Str("x".into()))], tsv))), "key");
        assert_eq!(code(table(&request(vec![named("sales"), Arg::Keyword("align".into(), ArgValue::Str("left,left".into()))], tsv))), "align");
        assert_eq!(code(table(&request(vec![named("sales")], &[("sales", b"")]))), "empty");
        assert_eq!(code(table(&request(vec![named("sales")], &[("sales", b"a\tb\nc\n")]))), "cells");
        let mut with_body = request(vec![named("sales")], tsv);
        with_body.body = vec![Block { span: SPAN, label: None, lang: None, body: BlockBody::Paragraph { style: None, inlines: vec![] } }];
        assert_eq!(code(table(&with_body)), "body");
    }

    #[test]
    fn an_error_gives_no_blocks() {
        let r = invoke(Request::Block(request(vec![], &[])));
        assert_eq!(r.output, Output::Blocks(vec![], vec![]));
        assert_eq!(r.diagnostics.len(), 1);
    }
}
