//! A sample plugin (docs/adr/0125): it overrides the built-in
//! `[number-text ...]` and sets the number in kanji.
//!
//! ```toml
//! [plugins.kansuji]
//! url = "https://github.com/tett23/golem/releases/download/v0.1.0-rc4/kansuji.wasm"
//! overrides = ["number-text"]
//! ```
//!
//! - an integer: `kanji` (百二十三), `kanji-digits` (一二三) or `tcy` (the
//!   number node of the IR, which the host sets in tate-chu-yoko);
//! - a rational whose decimal expansion ends: 三・一四 (the integer part in
//!   the style, the digits after the point one by one);
//! - another rational, or `form=fraction`: 三分の二;
//! - a negative number: マイナス before it.
//!
//! It asks the host for the writing mode and `[numbers] vertical` of the
//! book (docs/adr/0121): in horizontal writing an integer is the number
//! node (Arabic numerals) and a rational is 3.14 or 2/3; without `style=`
//! a number is in the notation of `[numbers] vertical`.

use golem_plugin_sdk::*;

/// How a number is written.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Style {
    /// positional: 百二十三
    Kanji,
    /// digit by digit: 一二三
    KanjiDigits,
    /// the number node of the IR in tate-chu-yoko
    Tcy,
    /// 0 to 99 in tate-chu-yoko, others positional (only a default)
    Auto,
    /// 0 to 99 in tate-chu-yoko, others digit by digit (only a default)
    AutoDigits,
}

/// How a rational that is not an integer is written.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Form {
    /// a decimal when the expansion ends, a fraction otherwise
    Decimal,
    /// always a fraction
    Fraction,
}

/// What `[number-text ...]` gives.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Rendered {
    Text(String),
    /// the number node with the style tcy
    Tcy(i64),
}

/// Why a number cannot be written.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RenderError {
    /// tcy for a number that is no integer
    TcyNotInteger,
}

const DIGITS: [char; 10] = ['〇', '一', '二', '三', '四', '五', '六', '七', '八', '九'];

fn digits(n: u128) -> String {
    n.to_string().chars().map(|c| DIGITS[c.to_digit(10).unwrap() as usize]).collect()
}

/// Positional kanji of a number of four digits or fewer, 1 or more.
fn small(r: u128) -> String {
    let parts = [(r / 1000, "千"), ((r / 100) % 10, "百"), ((r / 10) % 10, "十"), (r % 10, "")];
    parts
        .iter()
        .filter(|(d, _)| *d != 0)
        .map(|(d, p)| if *d == 1 && !p.is_empty() { p.to_string() } else { format!("{}{}", DIGITS[*d as usize], p) })
        .collect()
}

fn positional(n: u128) -> String {
    if n == 0 {
        return "〇".into();
    }
    // every int64 is below 10^20, so 京 is the largest unit needed
    let units = ["", "万", "億", "兆", "京"];
    let mut m = n;
    let mut groups = vec![];
    for u in units {
        if m == 0 {
            break;
        }
        let r = m % 10000;
        m /= 10000;
        if r != 0 {
            groups.push(format!("{}{}", small(r), u));
        }
    }
    groups.reverse();
    groups.concat()
}

fn signed(n: i128, f: fn(u128) -> String) -> String {
    if n < 0 {
        format!("マイナス{}", f(n.unsigned_abs()))
    } else {
        f(n as u128)
    }
}

/// Positional kanji: 10 → 十, 120 → 百二十, 10000 → 一万, -3 → マイナス三.
pub fn kanji(n: i128) -> String {
    signed(n, positional)
}

/// Digit-by-digit kanji: 10 → 一〇.
pub fn kanji_digits(n: i128) -> String {
    signed(n, digits)
}

/// The digits after the point of n/d (0 < n < d), if the expansion ends.
fn decimal_digits(n: u128, d: u128) -> Option<Vec<u8>> {
    let mut e = d;
    while e % 2 == 0 {
        e /= 2;
    }
    while e % 5 == 0 {
        e /= 5;
    }
    if e != 1 {
        return None;
    }
    let mut out = vec![];
    let mut r = n;
    while r != 0 {
        r *= 10;
        out.push((r / d) as u8);
        r %= d;
    }
    Some(out)
}

fn style_of(style: Style, n: i128) -> Style {
    match style {
        Style::Auto | Style::AutoDigits if (0..=99).contains(&n) => Style::Tcy,
        Style::Auto => Style::Kanji,
        Style::AutoDigits => Style::KanjiDigits,
        s => s,
    }
}

/// The number num/den (in lowest terms, den 1 or more) in a style and a form.
pub fn render(num: i64, den: i64, style: Style, form: Form) -> Result<Rendered, RenderError> {
    let (n, d) = (num as i128, den as i128);
    if d == 1 {
        return Ok(match style_of(style, n) {
            Style::Tcy => Rendered::Tcy(num),
            Style::KanjiDigits => Rendered::Text(kanji_digits(n)),
            _ => Rendered::Text(kanji(n)),
        });
    }
    let whole = match style {
        Style::Tcy => return Err(RenderError::TcyNotInteger),
        Style::KanjiDigits | Style::AutoDigits => digits,
        _ => positional,
    };
    let sign = if n < 0 { "マイナス" } else { "" };
    let (a, b) = (n.unsigned_abs(), d as u128);
    let decimal = match form {
        Form::Decimal => decimal_digits(a % b, b).map(|ds| ds.iter().map(|x| DIGITS[*x as usize]).collect::<String>()),
        Form::Fraction => None,
    };
    Ok(Rendered::Text(match decimal {
        Some(after) => format!("{sign}{}・{after}", whole(a / b)),
        None => format!("{sign}{}分の{}", whole(b), whole(a)),
    }))
}

/// A number in horizontal writing: an integer as the number node, which
/// the host sets in Arabic numerals; a rational in Arabic numerals, as a
/// decimal (3.14) or a fraction (2/3) as the form says.
pub fn render_horizontal(num: i64, den: i64, form: Form) -> Inline2 {
    if den == 1 {
        return Inline2::Number(num);
    }
    let (n, d) = (num as i128, den as i128);
    let sign = if n < 0 { "-" } else { "" };
    let (a, b) = (n.unsigned_abs(), d as u128);
    let decimal = match form {
        Form::Decimal => decimal_digits(a % b, b).map(|ds| ds.iter().map(|x| char::from(b'0' + x)).collect::<String>()),
        Form::Fraction => None,
    };
    Inline2::Text(match decimal {
        Some(after) => format!("{sign}{}.{after}", a / b),
        None => format!("{sign}{a}/{b}"),
    })
}

/// What a number in horizontal writing becomes.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Inline2 {
    /// the number node without a style
    Number(i64),
    Text(String),
}

fn style_named(s: &str, default: bool) -> Option<Style> {
    match s {
        "kanji" => Some(Style::Kanji),
        "kanji-digits" => Some(Style::KanjiDigits),
        "tcy" => Some(Style::Tcy),
        "auto" if default => Some(Style::Auto),
        "auto-digits" if default => Some(Style::AutoDigits),
        _ => None,
    }
}

/// The plugin asks for the writing mode and `[numbers] vertical` of the
/// book (docs/adr/0121); it takes no data.
fn describe() -> Description {
    Description { commands: vec!["number-text".into()], context: vec!["vertical-numbers".into(), "writing-mode".into()], ..Default::default() }
}

/// An error of the call. The code is without the name of the plugin, which
/// the host puts before it: `arity` is `kansuji/arity` (docs/adr/0108).
fn error(span: Span, code: &str, message: String) -> Response {
    Response::inlines(vec![]).with(Diagnostic { code: code.into(), severity: Severity::Error, span, message })
}

/// `[number-text ...]`. The host sends the context the plugin asked for;
/// a request without it is a bug of the host, and traps.
pub fn number_text(c: &CommandRequest) -> Response {
    let vertical = c.context.vertical().expect("the host sends writing-mode");
    let default = c.context.get("vertical-numbers").and_then(|s| style_named(s, true)).expect("the host sends vertical-numbers");
    if !c.slots.is_empty() {
        return error(c.span, "slot", "number-text は散文スロットを取りません".into());
    }
    let mut value = None;
    let mut positionals = 0;
    let (mut style, mut form) = (default, Form::Decimal);
    for a in &c.args {
        match a {
            Arg::Positional(v) => {
                positionals += 1;
                value = Some(v);
            }
            Arg::Keyword(k, v) => match (k.as_str(), v) {
                ("style", ArgValue::Str(s)) => match style_named(s, false) {
                    Some(st) => style = st,
                    None => return error(c.span, "style", format!("style は kanji、kanji-digits、tcy のいずれかです: {s}")),
                },
                ("form", ArgValue::Str(s)) if s == "decimal" => form = Form::Decimal,
                ("form", ArgValue::Str(s)) if s == "fraction" => form = Form::Fraction,
                ("style", _) => return error(c.span, "style", "style は kanji、kanji-digits、tcy のいずれかです".into()),
                ("form", _) => return error(c.span, "form", "form は decimal か fraction です".into()),
                _ => return error(c.span, "key", format!("number-text の知らないキーワード引数です: {k}")),
            },
        }
    }
    let (num, den) = match (positionals, value) {
        (1, Some(ArgValue::Int(n))) => (*n, 1),
        (1, Some(ArgValue::Rational(n, d))) => (*n, *d),
        (1, Some(ArgValue::Str(s))) => {
            return error(c.span, "not-number", format!("number-text には数を渡します: {s}"))
        }
        (1, _) => return error(c.span, "not-number", "number-text には数を渡します".into()),
        (0, _) => return error(c.span, "arity", "number-text には数を一つ渡します".into()),
        _ => return error(c.span, "arity", format!("number-text に渡せる数は一つです（{positionals} 個）")),
    };
    // the same errors in either writing mode
    let rendered = match render(num, den, style, form) {
        Ok(r) => r,
        Err(RenderError::TcyNotInteger) => return error(c.span, "tcy-not-integer", "縦中横にできるのは整数だけです".into()),
    };
    let out = if !vertical {
        match render_horizontal(num, den, form) {
            Inline2::Number(n) => Inline::Number { span: c.span, value: n, style: None },
            Inline2::Text(t) => Inline::Text { span: c.span, text: t },
        }
    } else {
        match rendered {
            Rendered::Text(t) => Inline::Text { span: c.span, text: t },
            Rendered::Tcy(n) => Inline::Number { span: c.span, value: n, style: Some(NumberStyle::Tcy) },
        }
    };
    Response::inlines(vec![out])
}

pub fn invoke(req: Request) -> Response {
    match req {
        Request::Command(c) => number_text(&c),
        Request::Filter(f) => Response::document(f.document),
        // kansuji declares no block command, so the host sends none (docs/adr/0122)
        Request::Block(_) => Response::blocks(vec![]),
    }
}

export_plugin!(describe, invoke);

#[cfg(test)]
mod tests {
    use super::*;

    fn text(s: &str) -> Result<Rendered, RenderError> {
        Ok(Rendered::Text(s.into()))
    }

    #[test]
    fn positional_kanji() {
        let cases: &[(i128, &str)] = &[
            (0, "〇"),
            (1, "一"),
            (10, "十"),
            (11, "十一"),
            (20, "二十"),
            (100, "百"),
            (123, "百二十三"),
            (1000, "千"),
            (1001, "千一"),
            (2026, "二千二十六"),
            (10000, "一万"),
            (11000, "一万千"),
            (100000000, "一億"),
            (100010001, "一億一万一"),
            (-3, "マイナス三"),
        ];
        for (n, k) in cases {
            assert_eq!(kanji(*n), *k, "{n}");
        }
    }

    #[test]
    fn the_extremes_of_int64() {
        assert_eq!(kanji(i64::MAX as i128), "九百二十二京三千三百七十二兆三百六十八億五千四百七十七万五千八百七");
        assert_eq!(kanji(i64::MIN as i128), "マイナス九百二十二京三千三百七十二兆三百六十八億五千四百七十七万五千八百八");
        assert_eq!(render(i64::MIN, 1, Style::KanjiDigits, Form::Decimal), text("マイナス九二二三三七二〇三六八五四七七五八〇八"));
    }

    #[test]
    fn digit_by_digit() {
        assert_eq!(kanji_digits(123), "一二三");
        assert_eq!(kanji_digits(2026), "二〇二六");
        assert_eq!(kanji_digits(0), "〇");
        assert_eq!(kanji_digits(-10), "マイナス一〇");
    }

    #[test]
    fn integers_in_each_style() {
        assert_eq!(render(123, 1, Style::Kanji, Form::Decimal), text("百二十三"));
        assert_eq!(render(123, 1, Style::KanjiDigits, Form::Decimal), text("一二三"));
        assert_eq!(render(12, 1, Style::Tcy, Form::Decimal), Ok(Rendered::Tcy(12)));
        assert_eq!(render(99, 1, Style::Auto, Form::Decimal), Ok(Rendered::Tcy(99)));
        assert_eq!(render(100, 1, Style::Auto, Form::Decimal), text("百"));
        assert_eq!(render(-1, 1, Style::Auto, Form::Decimal), text("マイナス一"));
        assert_eq!(render(100, 1, Style::AutoDigits, Form::Decimal), text("一〇〇"));
    }

    #[test]
    fn decimals_and_fractions() {
        assert_eq!(render(157, 50, Style::Kanji, Form::Decimal), text("三・一四"));
        assert_eq!(render(24691, 200, Style::Kanji, Form::Decimal), text("百二十三・四五五"));
        assert_eq!(render(24691, 200, Style::KanjiDigits, Form::Decimal), text("一二三・四五五"));
        assert_eq!(render(1, 2, Style::Kanji, Form::Decimal), text("〇・五"));
        assert_eq!(render(-1, 8, Style::Kanji, Form::Decimal), text("マイナス〇・一二五"));
        assert_eq!(render(2, 3, Style::Kanji, Form::Decimal), text("三分の二"));
        assert_eq!(render(-7, 3, Style::Kanji, Form::Decimal), text("マイナス三分の七"));
        assert_eq!(render(1, 2, Style::Kanji, Form::Fraction), text("二分の一"));
        assert_eq!(render(13, 10, Style::Kanji, Form::Fraction), text("十分の十三"));
        assert_eq!(render(13, 10, Style::KanjiDigits, Form::Fraction), text("一〇分の一三"));
        assert_eq!(render(13, 10, Style::Auto, Form::Decimal), text("一・三"));
        assert_eq!(render(1, 3, Style::Tcy, Form::Decimal), Err(RenderError::TcyNotInteger));
    }

    #[test]
    fn a_long_decimal_expansion() {
        // 1 / 2^62 = 2.168... * 10^-19: 62 digits after the point, 18 zeros first
        let r = render(1, 1 << 62, Style::Kanji, Form::Decimal).unwrap();
        match r {
            Rendered::Text(t) => {
                assert!(t.starts_with("〇・〇〇〇〇〇〇〇〇〇〇〇〇〇〇〇〇〇〇二一六"), "{t}");
                assert_eq!(t.chars().count(), 2 + 62);
            }
            _ => panic!(),
        }
    }

    fn call_in(vertical: bool, numbers: &str, args: Vec<Arg>, slots: Vec<Vec<Inline>>) -> Response {
        let span = Span { file: 1, start: 0, end: 5 };
        let mode = if vertical { "vertical" } else { "horizontal" };
        invoke(Request::Command(CommandRequest {
            name: "number-text".into(),
            args,
            slots,
            span,
            context: Context(vec![("vertical-numbers".into(), numbers.into()), ("writing-mode".into(), mode.into())]),
            data: Data::default(),
        }))
    }

    fn call(args: Vec<Arg>, slots: Vec<Vec<Inline>>) -> Response {
        call_in(true, "kanji", args, slots)
    }

    fn texts(r: &Response) -> Vec<String> {
        match &r.output {
            Output::Inlines(xs) => xs
                .iter()
                .map(|x| match x {
                    Inline::Text { text, .. } => text.clone(),
                    Inline::Number { value, style: Some(NumberStyle::Tcy), .. } => format!("#{value}"),
                    Inline::Number { value, .. } => format!("number {value}"),
                    _ => "?".into(),
                })
                .collect(),
            _ => panic!(),
        }
    }

    fn codes(r: &Response) -> Vec<String> {
        r.diagnostics.iter().map(|d| d.code.clone()).collect()
    }

    fn pos(v: ArgValue) -> Arg {
        Arg::Positional(v)
    }

    fn kw(k: &str, v: &str) -> Arg {
        Arg::Keyword(k.into(), ArgValue::Str(v.into()))
    }

    #[test]
    fn the_description_asks_for_the_context() {
        let d = describe();
        assert_eq!(d.context, ["vertical-numbers", "writing-mode"]);
        assert!(d.data.is_empty());
    }

    #[test]
    fn the_command() {
        assert_eq!(texts(&call(vec![pos(ArgValue::Int(123))], vec![])), ["百二十三"]);
        assert_eq!(texts(&call(vec![pos(ArgValue::Int(123)), kw("style", "kanji-digits")], vec![])), ["一二三"]);
        assert_eq!(texts(&call(vec![pos(ArgValue::Int(12)), kw("style", "tcy")], vec![])), ["#12"]);
        assert_eq!(texts(&call(vec![pos(ArgValue::Rational(2, 3))], vec![])), ["三分の二"]);
        assert_eq!(texts(&call(vec![pos(ArgValue::Rational(1, 2)), kw("form", "fraction")], vec![])), ["二分の一"]);
    }

    #[test]
    fn the_default_style_is_the_vertical_numbers_of_the_book() {
        assert_eq!(texts(&call_in(true, "auto", vec![pos(ArgValue::Int(12))], vec![])), ["#12"]);
        assert_eq!(texts(&call_in(true, "auto", vec![pos(ArgValue::Int(120))], vec![])), ["百二十"]);
        assert_eq!(texts(&call_in(true, "auto-digits", vec![pos(ArgValue::Int(120))], vec![])), ["一二〇"]);
        assert_eq!(texts(&call_in(true, "auto", vec![pos(ArgValue::Int(12)), kw("style", "kanji")], vec![])), ["十二"]);
    }

    #[test]
    fn horizontal_writing_has_no_kanji() {
        let h = |args| texts(&call_in(false, "kanji", args, vec![]));
        assert_eq!(h(vec![pos(ArgValue::Int(123))]), ["number 123"]);
        assert_eq!(h(vec![pos(ArgValue::Int(12)), kw("style", "tcy")]), ["number 12"]);
        assert_eq!(h(vec![pos(ArgValue::Int(-3)), kw("style", "kanji-digits")]), ["number -3"]);
        assert_eq!(h(vec![pos(ArgValue::Rational(157, 50))]), ["3.14"]);
        assert_eq!(h(vec![pos(ArgValue::Rational(-1, 8))]), ["-0.125"]);
        assert_eq!(h(vec![pos(ArgValue::Rational(2, 3))]), ["2/3"]);
        assert_eq!(h(vec![pos(ArgValue::Rational(-7, 3))]), ["-7/3"]);
        assert_eq!(h(vec![pos(ArgValue::Rational(1, 2)), kw("form", "fraction")]), ["1/2"]);
        // the same error in either writing mode
        let r = call_in(false, "kanji", vec![pos(ArgValue::Rational(1, 3)), kw("style", "tcy")], vec![]);
        assert_eq!(codes(&r), ["tcy-not-integer"]);
    }

    #[test]
    fn the_messages_of_a_value_that_is_no_number() {
        let messages = |r: Response| r.diagnostics.into_iter().map(|d| d.message).collect::<Vec<_>>();
        assert_eq!(messages(call(vec![pos(ArgValue::Str("abc".into()))], vec![])), ["number-text には数を渡します: abc"]);
        assert_eq!(messages(call(vec![pos(ArgValue::Bool(true))], vec![])), ["number-text には数を渡します"]);
        assert_eq!(messages(call(vec![pos(ArgValue::Int(1)), pos(ArgValue::Int(2))], vec![])), ["number-text に渡せる数は一つです（2 個）"]);
    }

    #[test]
    fn the_errors_of_the_command() {
        let none: Vec<String> = vec![];
        let cases: Vec<(Vec<Arg>, Vec<Vec<Inline>>, &str)> = vec![
            (vec![], vec![], "arity"),
            (vec![pos(ArgValue::Int(1)), pos(ArgValue::Int(2))], vec![], "arity"),
            (vec![pos(ArgValue::Str("abc".into()))], vec![], "not-number"),
            (vec![pos(ArgValue::Range(1, 3))], vec![], "not-number"),
            (vec![pos(ArgValue::Bool(true))], vec![], "not-number"),
            (vec![pos(ArgValue::Int(1)), kw("style", "auto")], vec![], "style"),
            (vec![pos(ArgValue::Int(1)), kw("form", "mixed")], vec![], "form"),
            (vec![pos(ArgValue::Int(1)), kw("sytle", "kanji")], vec![], "key"),
            (vec![pos(ArgValue::Rational(1, 3)), kw("style", "tcy")], vec![], "tcy-not-integer"),
            (vec![pos(ArgValue::Int(1))], vec![vec![]], "slot"),
        ];
        for (args, slots, code) in cases {
            let r = call(args, slots);
            assert_eq!((texts(&r), codes(&r)), (none.clone(), vec![code.to_string()]), "{code}");
        }
    }
}
