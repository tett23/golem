//! What the two ruby plugins share (docs/adr/0130, docs/adr/0131).
//!
//! - [`parse_tsv`]: the TSV of words and readings a project passes as data.
//! - [`Dict::scan`]: the leftmost longest match of the words in a text.
//! - [`walk`]: the runs of inlines of a document in the order of the
//!   document, with the inlines a plugin must not put ruby in left alone.
//! - [`align`]: the reading of each run of kanji of a word, from the
//!   reading of the whole word.

use golem_plugin_sdk::*;
use std::collections::BTreeMap;

#[cfg(test)]
mod tests;

/// A word of the TSV: the segments of its base, each with its reading
/// (`None`: no ruby on that segment), or a word that stops a match and
/// gets no ruby (an empty reading).
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Entry {
    Ruby(Vec<(String, Option<String>)>),
    Stop,
}

/// The words of a TSV by their text.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Dict {
    words: BTreeMap<String, Entry>,
    /// the words by their first character, the longest first: the
    /// candidates of a match at a place are only those of its character
    by_first: BTreeMap<char, Vec<String>>,
}

/// A line of the TSV that is wrong: its number (from 1) and why.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TsvError {
    pub line: usize,
    pub message: String,
}

/// A piece of a text: text with no word, or a word with its entry.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Piece<'a> {
    Plain(String),
    Word(String, &'a Entry),
}

/// Reads a TSV of words and readings. Each line is a word, a tab and its
/// reading; an empty line and a line that starts with `#` are skipped. A
/// `/` splits the word and the reading into as many segments, each with
/// its own ruby (mono ruby), and an empty segment of the reading gives no
/// ruby to its segment of the word; with no `/` the whole word has one
/// reading (group ruby). An empty reading makes a word that gets no ruby
/// but stops a match there. Every wrong line is an error.
pub fn parse_tsv(tsv: &str) -> Result<Dict, Vec<TsvError>> {
    let mut words: BTreeMap<String, (usize, Entry)> = BTreeMap::new();
    let mut errors = vec![];
    for (i, raw) in tsv.split('\n').enumerate() {
        let n = i + 1;
        let line = raw.strip_suffix('\r').unwrap_or(raw);
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        match entry_of(line) {
            Err(m) => errors.push(TsvError { line: n, message: m }),
            Ok((word, entry)) => match words.get(&word) {
                Some((first, _)) => errors.push(TsvError { line: n, message: format!("語が重複しています（{first} 行め）: {word}") }),
                None => {
                    words.insert(word, (n, entry));
                }
            },
        }
    }
    if !errors.is_empty() {
        return Err(errors);
    }
    let mut by_first: BTreeMap<char, Vec<String>> = BTreeMap::new();
    for w in words.keys() {
        if let Some(c) = w.chars().next() {
            by_first.entry(c).or_default().push(w.clone());
        }
    }
    for ws in by_first.values_mut() {
        // the longest first; words of one length in the order of the map
        ws.sort_by_key(|w| std::cmp::Reverse(w.chars().count()));
    }
    Ok(Dict { words: words.into_iter().map(|(w, (_, e))| (w, e)).collect(), by_first })
}

fn entry_of(line: &str) -> Result<(String, Entry), String> {
    let cols: Vec<&str> = line.split('\t').collect();
    let (word, reading) = match cols.as_slice() {
        [w, r] => (*w, *r),
        [_] => return Err("語と読みをタブで区切った二つの欄がありません".into()),
        _ => return Err("欄が三つ以上あります".into()),
    };
    if word.is_empty() {
        return Err("語が空です".into());
    }
    let text: String = word.split('/').collect();
    if reading.is_empty() {
        return Ok((text, Entry::Stop));
    }
    let bases: Vec<&str> = word.split('/').collect();
    let readings: Vec<&str> = reading.split('/').collect();
    if bases.len() != readings.len() {
        return Err("語と読みの / で区切った数が一致しません".into());
    }
    if bases.iter().any(|b| b.is_empty()) {
        return Err("語の / のあいだが空です".into());
    }
    if readings.iter().all(|r| r.is_empty()) {
        return Err("読みのない区切りだけの読みです。ルビを振らない語は読みを空にします".into());
    }
    let segs = bases
        .iter()
        .zip(&readings)
        .map(|(b, r)| (b.to_string(), if r.is_empty() { None } else { Some(r.to_string()) }))
        .collect();
    Ok((text, Entry::Ruby(segs)))
}

impl Dict {
    pub fn is_empty(&self) -> bool {
        self.words.is_empty()
    }

    pub fn get(&self, word: &str) -> Option<&Entry> {
        self.words.get(word)
    }

    /// The longest word that starts at each place, from the left; the text
    /// between the words is plain.
    pub fn scan<'a>(&'a self, text: &str) -> Vec<Piece<'a>> {
        let mut out = vec![];
        let mut plain = String::new();
        let mut rest = text;
        while let Some(c) = rest.chars().next() {
            let hit = self.by_first.get(&c).and_then(|ws| ws.iter().find(|w| rest.starts_with(w.as_str())));
            match hit.and_then(|w| self.words.get(w).map(|e| (w, e))) {
                Some((w, e)) => {
                    if !plain.is_empty() {
                        out.push(Piece::Plain(std::mem::take(&mut plain)));
                    }
                    out.push(Piece::Word(w.clone(), e));
                    rest = &rest[w.len()..];
                }
                None => {
                    plain.push(c);
                    rest = &rest[c.len_utf8()..];
                }
            }
        }
        if !plain.is_empty() {
            out.push(Piece::Plain(plain));
        }
        out
    }
}

/// A character that takes ruby: a CJK ideograph (the unified ideographs,
/// extension A and the planes 2 and 3, the compatibility ideographs), the
/// iteration mark 々, 〆, 〇 and the small ヶ (一ヶ月).
pub fn is_kanji(c: char) -> bool {
    matches!(c,
        '\u{3400}'..='\u{4DBF}' | '\u{4E00}'..='\u{9FFF}' | '\u{F900}'..='\u{FAFF}' | '\u{20000}'..='\u{3FFFF}'
        | '々' | '〆' | '〇' | 'ヶ')
}

pub fn has_kanji(s: &str) -> bool {
    s.chars().any(is_kanji)
}

/// The katakana of a text as hiragana (ァ to ヵ); the rest as it is.
pub fn hiragana(s: &str) -> String {
    s.chars()
        .map(|c| match c {
            'ァ'..='ヵ' => char::from_u32(c as u32 - 0x60).unwrap_or(c),
            _ => c,
        })
        .collect()
}

/// The runs of a word, each with its reading: a run of kanji gets the part
/// of the reading it stands for, the other runs (kana, the rest) none. The
/// other runs must be in the reading as they are (katakana as hiragana); a
/// run of kanji takes one character of the reading or more, the fewest
/// first. `None` when the reading does not fit the word.
pub fn align(surface: &str, reading: &str) -> Option<Vec<(String, Option<String>)>> {
    let mut runs: Vec<(bool, String)> = vec![];
    for c in surface.chars() {
        let k = is_kanji(c);
        match runs.last_mut() {
            Some((lk, s)) if *lk == k => s.push(c),
            _ => runs.push((k, c.to_string())),
        }
    }
    let r: Vec<char> = hiragana(reading).chars().collect();
    let mut out = vec![];
    if !r.is_empty() && fit(&runs, &r, &mut out) {
        out.reverse();
        Some(out)
    } else {
        None
    }
}

fn fit(runs: &[(bool, String)], r: &[char], out: &mut Vec<(String, Option<String>)>) -> bool {
    let Some(((kanji, text), rest)) = runs.split_first() else {
        return r.is_empty();
    };
    if !kanji {
        let lit: Vec<char> = hiragana(text).chars().collect();
        if r.starts_with(&lit) && fit(rest, &r[lit.len()..], out) {
            out.push((text.clone(), None));
            return true;
        }
        return false;
    }
    for n in 1..=r.len() {
        if fit(rest, &r[n..], out) {
            out.push((text.clone(), Some(r[..n].iter().collect())));
            return true;
        }
    }
    false
}

/// A ruby whose segments are texts at a span.
pub fn ruby(span: Span, segments: &[(String, Option<String>)]) -> Inline {
    Inline::Ruby {
        span,
        segments: segments
            .iter()
            .map(|(b, r)| RubySegment { base: vec![Inline::Text { span, text: b.clone() }], reading: r.clone() })
            .collect(),
    }
}

/// The texts of inlines, the bodies of styles, colors and kenten included.
pub fn plain_text(xs: &[Inline]) -> String {
    xs.iter()
        .map(|x| match x {
            Inline::Text { text, .. } => text.clone(),
            Inline::Kenten { body, .. } | Inline::Color { body, .. } | Inline::CharStyle { body, .. } => plain_text(body),
            Inline::Ruby { segments, .. } => segments.iter().map(|s| plain_text(&s.base)).collect(),
            _ => String::new(),
        })
        .collect()
}

/// What a plugin does with the texts it may put ruby in.
pub trait Visitor {
    /// A text node; the inlines that stand for it.
    fn text(&mut self, span: Span, text: String) -> Vec<Inline>;
    /// A ruby of the source, with the text of its bases.
    fn ruby(&mut self, base: &str);
}

/// Visits the texts of a document in its order: paragraphs, list items,
/// tables (the header, then the rows), terms and definitions, and the
/// headings when `headings`. In a run of inlines it goes into colors,
/// character styles, notes and sidenotes (a note at its mark), and leaves
/// alone code, kenten (ruby there is G07045), the ruby of the source (the
/// visitor sees its text), tate-chu-yoko, numbers, references, index
/// marks, channel items and comments. The blocks the SDK keeps as CBOR
/// (figures and their captions, code) are not visited.
pub fn walk(doc: &mut Document, headings: bool, v: &mut impl Visitor) {
    for b in &mut doc.blocks {
        walk_block(b, headings, v);
    }
}

fn walk_block(b: &mut Block, headings: bool, v: &mut impl Visitor) {
    match &mut b.body {
        BlockBody::Heading { inlines, .. } => {
            if headings {
                walk_run(inlines, v)
            }
        }
        BlockBody::Paragraph { inlines, .. } => walk_run(inlines, v),
        BlockBody::BulletList(items) | BlockBody::OrderedList(items) => {
            for c in items.iter_mut().flat_map(|it| it.blocks.iter_mut()) {
                walk_block(c, headings, v);
            }
        }
        BlockBody::DefList(groups) => {
            for g in groups {
                for t in &mut g.terms {
                    walk_run(t, v);
                }
                for c in g.defs.iter_mut().flatten() {
                    walk_block(c, headings, v);
                }
            }
        }
        BlockBody::Table { header, rows, .. } => {
            for c in header.iter_mut().chain(rows.iter_mut().flatten()) {
                walk_run(c, v);
            }
        }
        BlockBody::Other(_) => {}
    }
}

fn walk_run(xs: &mut Vec<Inline>, v: &mut impl Visitor) {
    let old = std::mem::take(xs);
    for x in old {
        match x {
            Inline::Text { span, text } => xs.extend(v.text(span, text)),
            Inline::Ruby { span, segments } => {
                v.ruby(&segments.iter().map(|s| plain_text(&s.base)).collect::<String>());
                xs.push(Inline::Ruby { span, segments });
            }
            Inline::CharStyle { span, style, mut body } => {
                if style != "code" {
                    walk_run(&mut body, v);
                }
                xs.push(Inline::CharStyle { span, style, body });
            }
            Inline::Color { span, swatch, mut body } => {
                walk_run(&mut body, v);
                xs.push(Inline::Color { span, swatch, body });
            }
            Inline::Note { span, number, mut body } => {
                walk_run(&mut body, v);
                xs.push(Inline::Note { span, number, body });
            }
            Inline::Sidenote { span, number, mut body } => {
                walk_run(&mut body, v);
                xs.push(Inline::Sidenote { span, number, body });
            }
            other => xs.push(other),
        }
    }
}

/// The TSV of words a project passes as the data `name`, if it passes it.
/// A TSV that is not UTF-8 is the error `utf8`, and each wrong line
/// the error `tsv`, at the top of the file. The host puts the name of the
/// plugin before a code (docs/adr/0108).
pub fn read_words(data: &Data, name: &str, file: u64) -> Result<Option<Dict>, Vec<Diagnostic>> {
    let top = Span { file, start: 0, end: 0 };
    let error = |code: &str, message: String| Diagnostic { code: code.into(), severity: Severity::Error, span: top, message };
    let Some(bytes) = data.get(name) else { return Ok(None) };
    let tsv = std::str::from_utf8(bytes).map_err(|_| vec![error("utf8", format!("{name} が UTF-8 ではありません"))])?;
    parse_tsv(tsv)
        .map(Some)
        .map_err(|es| es.into_iter().map(|e| error("tsv", format!("{name} の {} 行め: {}", e.line, e.message))).collect())
}
