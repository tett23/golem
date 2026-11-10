# ADR 0308: 日本語の本かどうかを、どこでも `language` の主の副タグで決める

ステータス: 採択

## 文脈

### 日本語かどうかの判定が六か所にあり、三通りに分かれている

言語のタグが日本語を表すかどうかを決めるコードは、`main`（`db145a81`）に六か所ある。
`modules` の下のテストでない `.hs` を、`"ja"` との比べ、`isPrefixOf`、`takeWhile (/= '-')` で `rg` で検索して数えた。

| 場所 | 判定するもの | 判定の形 |
| --- | --- | --- |
| golem-eval [`File.hs#L1009`](https://github.com/tett23/golem/blob/db145a81a219741ca75d9774637398816694e693/modules/golem-eval/src/Golem/Eval/File.hs#L1009)（`@printings` の G02076） | 本の `language` | ちょうど `"ja"` に等しい |
| golem-assemble [`Assemble.hs#L239`](https://github.com/tett23/golem/blob/db145a81a219741ca75d9774637398816694e693/modules/golem-assemble/src/Golem/Assemble.hs#L239)（章末の注の見出しの文言） | 本の `language` | 英小文字にして `ja` で始まる |
| golem-typeset [`Fonts.hs#L675`](https://github.com/tett23/golem/blob/db145a81a219741ca75d9774637398816694e693/modules/golem-typeset/src/Golem/Typeset/Fonts.hs#L675)（見出しの `lines` の既定） | 本の `language` | 英小文字にして `ja` で始まる |
| golem-assemble [`Numbering.hs#L18`](https://github.com/tett23/golem/blob/db145a81a219741ca75d9774637398816694e693/modules/golem-assemble/src/Golem/Assemble/Numbering.hs#L18)（番号と題のあいだの空白） | 本の `language` | 最初の `-` の前を英小文字にして `ja` に等しい |
| golem-layout [`CharClass.hs#L194`](https://github.com/tett23/golem/blob/db145a81a219741ca75d9774637398816694e693/modules/golem-layout/src/Golem/Layout/CharClass.hs#L194)（`spanIsJapanese`） | 言語の区間の言語 | 最初の `-` の前を英小文字にして `ja` に等しい |
| golem-bibliography [`Bibliography.hs#L232`](https://github.com/tett23/golem/blob/db145a81a219741ca75d9774637398816694e693/modules/golem-bibliography/src/Golem/Bibliography.hs#L232)（`isJapaneseEntry`） | 文献の項目の `language` | 最初の `-` の前を英小文字にして `ja` に等しい |

この ADR では、最初の `-` の前を英小文字にしたものを、仕様書と同じく「主の副タグ」と呼ぶ。
主の副タグで決める形は、六か所のうち三か所が使い、仕様書もその三か所をこの形で書いている（`docs/specifications.md` の番号の後の空白、言語の区間、文献の項目）。

### 三通りの判定は、同じ本で食い違う

本の `language` が同じでも、`@printings`、章末の注と見出しの既定、番号の後の空白で、日本語の本かどうかの答えが違う。

| `language` | `@printings`（いま） | 注と見出し（いま） | 番号の後の空白（いま） |
| --- | --- | --- | --- |
| `ja` | 日本語 | 日本語 | 日本語 |
| `ja-JP` | G02076 | 日本語 | 日本語 |
| `JA` | G02076 | 日本語 | 日本語 |
| `jam`（`ja` で始まる三文字の言語の符号） | G02076 | 日本語 | 日本語でない |
| `ja_JP`（BCP 47 の形でない） | G02076 | 日本語 | 日本語でない |

`ja-JP` の本では、注の見出しは「注」になり、番号の後は全角の空白になるのに、`@printings` は G02076 になる。
`jam` の本では、注の見出しが「注」になり、番号の後は半角の空白になる。
`ja` で始まるかで決める形は、`ja` で始まる三文字の言語の符号を日本語と取り違える。

### tett23 の決定

2026-11-10 に tett23 は、次のとおり指示した。

> 5 揃える。ADR作成。ただし、printingsはそんなに使われないというか、出版社によってフォーマットがかなり異なるのでそこまで重要な機能ではない。

この ADR は、その決定に従って判定を揃えるだけの、小さな変更とする。

## 実装すること

### 1. 判定の規則

言語のタグ `l` が日本語を表すのは、`l` の主の副タグが `ja` のときだけとする。
Haskell では `T.toLower (T.takeWhile (/= '-') l) == "ja"` である。
本の `language`、言語の区間の言語、文献の項目の `language` のどれにも、この規則を使う。

### 2. 違う形の三か所を、1 の規則に変える

- golem-eval の `printingsBlock`：`ctxMeta` の `language` が文字列で、1 の規則で日本語のときだけ、G02076 を出さない。`language` がないか文字列でないときは、今のとおり G02076 とする。
- golem-assemble の `notesTitle`：1 の規則で日本語なら「注」、そうでなければ「Notes」とする。
- golem-typeset の `headingDefaults`：1 の規則で日本語なら日本語の表を使う。`Fonts.hs` はすでに golem-layout の `spanIsJapanese` を読み込んでいるので、それを使う。

### 3. 共通の関数は作らない

golem-syntax は `Golem.Syntax.LanguageTag` で言語のタグの形を検査する。
この ADR では、日本語かどうかを決める共通の関数をそこへ足さず、今の依存のまま一行の式を各所に残す。
golem-eval は golem-layout にも golem-assemble にも依らず、依存を足すには ADR が要る。
そこで、一行の式をそれぞれの場所に書き、golem のパッケージのあいだの `build-depends` は変えない。
すでに依っているパッケージに同じ式の関数があれば、それを使ってよい（golem-typeset は golem-layout の `spanIsJapanese` をすでに読み込んでいる）。

### 4. G02076 のメッセージ

G02076 のメッセージを「`@printings は日本語の本（language の主の副タグが ja）でだけ使えます`」とする。
いまの「`（language = "ja"）`」は、`ja-JP` の本も使えるようになると正しくない。

### 5. 文書

- 仕様書の `@printings` の節の「日本語でない本（`language` が `ja` でない本）」を、主の副タグの形に直す。
- 仕様書の見出しの既定の節の「`ja` で始まる本」と「`JA` で始まる本も `ja` の本として扱う」を、主の副タグの形に直す。
- 仕様書の章末の注の節の「英小文字にしたものが `ja` で始まれば」を、主の副タグの形に直す。
- `docs/diagnostics.md` の G02076 の意味、メッセージ、主な原因を直し、`scripts/gen-embedded.sh` で `Golem.Driver.Explain.Embedded` を作り直す。

## 実装しないこと

- 言語のタグの形を検査すること。`ja_JP` のような BCP 47 でない形は、主の副タグが `ja_jp` になり、日本語の本にならない。本の `metadata.language` の形の検査は、今のとおり PDF/A と PDF/UA の G03119 だけとする。
  原稿の `[lang]` と `@lang` の G02132 は変えない。
- `@printings` の書式を、日本語のほかの言語に広げること。
- 六か所を一つの関数にまとめること（3 のとおり）。

## 不変条件

言語のタグ `l` の主の副タグを `p(l)` とする。
本の `language` が `l` のとき、`@printings` が G02076 を出さないことを `printingsOk(l)`、章末の注の見出しが「注」であることを `notesJa(l)`、見出しの既定が日本語の表であることを `headingJa(l)`、番号 `"1"` の後の空白が全角であること（`numberSeparator l "1" == "\x3000"`）を `sepJa(l)` とする。
言語の区間（`spanIsJapanese`）と文献の項目（`isJapaneseEntry`）は、すでに 1 の規則のとおりで、この ADR では変えないので、J1 に含めない。

- **J1 一つの規則**：どの `l` でも、`printingsOk(l)`、`notesJa(l)`、`headingJa(l)`、`sepJa(l)` は、どれも `p(l) == "ja"` に等しい。
- **J2 大文字と小文字を区別しない**：どの `l` でも、`l` を英小文字にしても英大文字にしても、J1 の四つの値は変わらない。

境界の入力：

| `l` | `p(l)` | 四つの値 |
| --- | --- | --- |
| （空） | （空） | 偽 |
| `j` | `j` | 偽 |
| `ja` | `ja` | 真 |
| `JA` | `ja` | 真 |
| `ja-JP` | `ja` | 真 |
| `ja-` | `ja` | 真 |
| `jam` | `jam` | 偽 |
| `ja_JP` | `ja_jp` | 偽 |
| `en` | `en` | 偽 |
| `en-ja` | `en` | 偽 |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
テストの名前には、J1、J2 の番号を入れる。

- **J1、J2**：境界の入力の表の `l` を、それぞれの関数の持ち主のテストのスイートで確かめる。`printingsOk` は golem-eval-test（`FileSpec` の `printingsCtx` で `language` を変える）、`notesJa` は golem-assemble-test（`notesTitle`）、`headingJa` は golem-driver-test の今の `headingDefaults` のテストの隣、`sepJa` は golem-assemble-test（`numberSeparator`）で確かめる。J2 は、表の `l` を英大文字にしたものでも同じ値になることを確かめる。今の実装では、`printingsOk` が `ja-JP` と `JA` で、`notesJa` と `headingJa` が `jam` と `ja_JP` で落ちる。
- G02076 のメッセージの今のテスト（`FileSpec` の「a book not in Japanese is G02076 alone and sets nothing」）を、4 のメッセージに直す。

## トレードオフ

`jam` や `ja_JP` を `language` に書いた本は、注の見出しが「Notes」に、見出しの `lines` の既定がほかの言語の表に変わる。
`jam` の本を日本語として組むのは誤りなので、直す変更である。
`ja_JP` は BCP 47 の形でないので、`ja-JP` に書き直せば今の組みに戻る。
リポジトリの `manifest.toml` の `language` は `ja`（26 個）と `en`（6 個）だけで、この二つを書いたものはない（`rg -g 'manifest.toml' -o --no-filename '^language *= *"[^"]*"' . | sort | uniq -c`）。

同じ一行の式が六か所に残る。
式がまた食い違わないことは、J1 のテストが確かめる。
式が育ったら（地域の副タグを見るなど）、共通の関数の置き場所を、依存の ADR と一緒に決める。

## 決めたことの記録

2026-11-11 に、tett23 が提案中の Golem [ADR 0306](0306-measure-the-residency-of-forcing-a-table-by-heap-profiles.md) から 0309 について、次のとおり指示した。

> 提案のADRをマージしてサブエージェントで実装

この指示により、この ADR を採択し、実装を別のプルリクエストで進める。

## 参考文献

- [ADR 0033](0033-colophon-contributors-and-printings.md)、[ADR 0056](0056-printings-diagnostic-codes-by-cause.md)、[ADR 0187](0187-inline-language-switch.md)
- [golem-driver ADR 0026](../golem-driver/adr/0026-chapter-end-notes.md)、[golem-driver ADR 0032](../golem-driver/adr/0032-default-heading-styles.md)
- [`modules/golem-eval/src/Golem/Eval/File.hs`](https://github.com/tett23/golem/blob/db145a81a219741ca75d9774637398816694e693/modules/golem-eval/src/Golem/Eval/File.hs)、[`modules/golem-assemble/src/Golem/Assemble.hs`](https://github.com/tett23/golem/blob/db145a81a219741ca75d9774637398816694e693/modules/golem-assemble/src/Golem/Assemble.hs)、[`modules/golem-assemble/src/Golem/Assemble/Numbering.hs`](https://github.com/tett23/golem/blob/db145a81a219741ca75d9774637398816694e693/modules/golem-assemble/src/Golem/Assemble/Numbering.hs)、[`modules/golem-typeset/src/Golem/Typeset/Fonts.hs`](https://github.com/tett23/golem/blob/db145a81a219741ca75d9774637398816694e693/modules/golem-typeset/src/Golem/Typeset/Fonts.hs)、[`modules/golem-layout/src/Golem/Layout/CharClass.hs`](https://github.com/tett23/golem/blob/db145a81a219741ca75d9774637398816694e693/modules/golem-layout/src/Golem/Layout/CharClass.hs)、[`modules/golem-bibliography/src/Golem/Bibliography.hs`](https://github.com/tett23/golem/blob/db145a81a219741ca75d9774637398816694e693/modules/golem-bibliography/src/Golem/Bibliography.hs)
- BCP 47（RFC 5646）の主の言語の副タグと、大文字と小文字を区別しないこと
