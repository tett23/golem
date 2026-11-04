//! A sample plugin (docs/adr/0123): the block command
//! `@bar-chart name column=N alt="..."` draws the numbers of a column of the
//! TSV the project passes as the data `name` as a bar chart, an SVG image of
//! a figure. The indented lines after the command are the caption.
//!
//! ```text
//! @label sales-chart
//! @bar-chart sales column=2 alt="月ごとの売上の棒グラフ"
//!   月ごとの売上
//! ```
//!
//! The TSV is read as `tsv-table` reads one, its first line the header;
//! the column is counted from 1 and holds integers from 0. The chart has no
//! text: text that is not outlined is outside the SVG that Golem draws in a
//! PDF (G08011), and the figure goes through the same checks as an `@figure`.
//! The bars are as many as the lines but the header, at most 1,000.

use golem_plugin_sdk::*;

/// The most bars of a chart.
pub const MAX_BARS: usize = 1000;
/// The size of the chart, in the units of its viewBox.
const WIDTH: u64 = 400;
const HEIGHT: u64 = 200;

fn describe() -> Description {
    Description { blocks: vec!["bar-chart".into()], data: vec!["*".into()], ..Default::default() }
}

/// The lines of a TSV as cells: UTF-8, a BOM skipped, LF or CRLF, one line
/// end at the end dropped; every line as wide as the first. Err is a message.
pub fn rows(bytes: &[u8]) -> Result<Vec<Vec<&str>>, String> {
    let text = std::str::from_utf8(bytes).map_err(|_| "UTF-8 ではありません".to_string())?;
    let text = text.strip_prefix('\u{feff}').unwrap_or(text);
    let body = text.strip_suffix("\r\n").or_else(|| text.strip_suffix('\n')).unwrap_or(text);
    if body.is_empty() {
        return Err("空です".into());
    }
    let rows: Vec<Vec<&str>> = body.split('\n').map(|l| l.strip_suffix('\r').unwrap_or(l).split('\t').collect()).collect();
    match rows.iter().position(|r| r.len() != rows[0].len()) {
        Some(i) => Err(format!("{} 行目のセルの数が見出しの行と違います", i + 1)),
        None => Ok(rows),
    }
}

/// The values of a column (from 1) of the lines below the header.
pub fn values(rows: &[Vec<&str>], column: usize) -> Result<Vec<u64>, String> {
    if column == 0 || column > rows[0].len() {
        return Err(format!("列 {column} がありません（列は {}）", rows[0].len()));
    }
    if rows.len() - 1 > MAX_BARS {
        return Err(format!("棒の数が上限（{MAX_BARS}）を超えます"));
    }
    rows.iter()
        .enumerate()
        .skip(1)
        .map(|(i, r)| {
            let c = r[column - 1];
            if !c.is_empty() && c.bytes().all(|b| b.is_ascii_digit()) && c.len() <= 15 {
                Ok(c.parse::<u64>().expect("digits"))
            } else {
                Err(format!("{} 行目の値が 0 以上の整数ではありません: {c}", i + 1))
            }
        })
        .collect()
}

/// The SVG of a bar chart: a bar for each value, the highest the height of
/// the chart, on a baseline. Integers only, so the same values give the same bytes.
pub fn svg(vs: &[u64]) -> String {
    let max = vs.iter().copied().max().unwrap_or(0).max(1);
    let n = vs.len().max(1) as u64;
    let slot = WIDTH * 1000 / n; // thousandths of a unit
    let mut out = format!("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 {WIDTH} {HEIGHT}\" width=\"{WIDTH}\" height=\"{HEIGHT}\">");
    for (i, v) in vs.iter().enumerate() {
        let h = HEIGHT * 1000 * v / max;
        let x = slot * i as u64 + slot / 10;
        let w = slot * 8 / 10;
        out.push_str(&format!(
            "<rect x=\"{}\" y=\"{}\" width=\"{}\" height=\"{}\" fill=\"#404040\"/>",
            milli(x),
            milli(HEIGHT * 1000 - h),
            milli(w),
            milli(h)
        ));
    }
    out.push_str(&format!("<rect x=\"0\" y=\"{}\" width=\"{WIDTH}\" height=\"1\" fill=\"#000000\"/>", HEIGHT - 1));
    out.push_str("</svg>");
    out
}

/// Thousandths as a decimal number without trailing zeros.
fn milli(n: u64) -> String {
    let (i, f) = (n / 1000, n % 1000);
    if f == 0 {
        format!("{i}")
    } else {
        format!("{i}.{}", format!("{f:03}").trim_end_matches('0'))
    }
}

fn error(span: Span, code: &str, message: String) -> Diagnostic {
    Diagnostic { code: code.into(), severity: Severity::Error, span, message }
}

/// The figure and its image, or the diagnostic of why there is none.
pub fn chart(req: &BlockCommandRequest) -> Result<(Block, Image), Diagnostic> {
    let span = req.span;
    let mut name = None;
    let mut positional = 0;
    let mut column = 2usize;
    let mut alt = None;
    for a in &req.args {
        match a {
            Arg::Positional(v) => {
                positional += 1;
                if let ArgValue::Str(s) = v {
                    name = Some(s.as_str());
                }
            }
            Arg::Keyword(k, ArgValue::Int(n)) if k == "column" && *n >= 1 => column = *n as usize,
            Arg::Keyword(k, ArgValue::Str(s)) if k == "alt" => alt = Some(s.as_str()),
            Arg::Keyword(k, _) => return Err(error(span, "bar-chart-key", format!("@bar-chart のキーワード引数は column（1 以上の整数）と alt（文字列）です: {k}"))),
        }
    }
    let name = match (positional, name) {
        (1, Some(n)) => n,
        _ => return Err(error(span, "bar-chart-name", "@bar-chart にはデータの名前を一つ書きます".into())),
    };
    let alt = alt.ok_or_else(|| error(span, "bar-chart-alt", "@bar-chart には alt の代替テキストが必要です".into()))?;
    let bytes = req.data.get(name).ok_or_else(|| error(span, "bar-chart-no-data", format!("manifest.toml の data にない名前です: {name}")))?;
    let rows = rows(bytes).map_err(|m| error(span, "bar-chart-tsv", format!("{name} が {m}")))?;
    let vs = values(&rows, column).map_err(|m| error(span, "bar-chart-values", format!("{name}: {m}")))?;
    let image = Image { name: "chart".into(), format: ImageFormat::Svg, bytes: svg(&vs).into_bytes() };
    Ok((ir::figure(span, "chart", alt, req.body.clone()), image))
}

pub fn invoke(req: Request) -> Response {
    match req {
        Request::Block(b) => match chart(&b) {
            Ok((f, i)) => Response::blocks_with_images(vec![f], vec![i]),
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

    const SPAN: Span = Span { file: 1, start: 0, end: 20 };

    fn request(args: Vec<Arg>, tsv: &[u8]) -> BlockCommandRequest {
        BlockCommandRequest { name: "bar-chart".into(), args, body: vec![], span: SPAN, context: Default::default(), data: Data(vec![("sales".into(), tsv.to_vec())]) }
    }

    fn named(n: &str) -> Arg {
        Arg::Positional(ArgValue::Str(n.into()))
    }

    fn alt() -> Arg {
        Arg::Keyword("alt".into(), ArgValue::Str("売上".into()))
    }

    #[test]
    fn draws_a_bar_for_each_line_below_the_header() {
        assert_eq!(
            svg(&[1, 2]),
            "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 400 200\" width=\"400\" height=\"200\">\
             <rect x=\"20\" y=\"100\" width=\"160\" height=\"100\" fill=\"#404040\"/>\
             <rect x=\"220\" y=\"0\" width=\"160\" height=\"200\" fill=\"#404040\"/>\
             <rect x=\"0\" y=\"199\" width=\"400\" height=\"1\" fill=\"#000000\"/></svg>"
        );
        assert_eq!(milli(66_667), "66.667");
        assert_eq!(milli(66_500), "66.5");
    }

    #[test]
    fn reads_a_column() {
        let r = rows("月\t売上\r\n1月\t12\r\n2月\t30\r\n".as_bytes()).unwrap();
        assert_eq!(values(&r, 2), Ok(vec![12, 30]));
        assert!(values(&r, 1).is_err());
        assert!(values(&r, 3).is_err());
        assert!(rows(b"a\tb\n1\n").is_err());
        assert!(rows(b"").is_err());
    }

    #[test]
    fn a_figure_of_the_image_chart() {
        let (f, i) = chart(&request(vec![named("sales"), alt()], b"m\tv\na\t3\n")).unwrap();
        assert_eq!(f, ir::figure(SPAN, "chart", "売上", vec![]));
        assert_eq!(i.name, "chart");
        assert_eq!(i.format, ImageFormat::Svg);
    }

    #[test]
    fn the_errors_of_a_call() {
        let code = |args: Vec<Arg>, tsv: &[u8]| chart(&request(args, tsv)).expect_err("a chart").code;
        assert_eq!(code(vec![alt()], b"m\tv\n"), "bar-chart-name");
        assert_eq!(code(vec![named("sales")], b"m\tv\n"), "bar-chart-alt");
        assert_eq!(code(vec![named("costs"), alt()], b"m\tv\n"), "bar-chart-no-data");
        assert_eq!(code(vec![named("sales"), alt()], b"m\tv\na\tx\n"), "bar-chart-values");
        assert_eq!(code(vec![named("sales"), alt(), Arg::Keyword("color".into(), ArgValue::Str("red".into()))], b"m\tv\n"), "bar-chart-key");
        assert_eq!(code(vec![named("sales"), alt()], b"\xff"), "bar-chart-tsv");
    }
}
