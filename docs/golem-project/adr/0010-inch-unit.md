# ADR 0010: 寸法にインチの単位 `in` を加える

ステータス: 採択

## 文脈

寸法は、`mm`、`pt`、`Q`、`H`、`zw` の単位を付けた文字列で書く（仕様書の「style.toml」の節）。
[ADR 0003](0003-mass-market-paperback-size.md) と [ADR 0005](0005-page-size-by-dimensions.md) は、インチの単位を加えないと決めた。
インチの判型は、`mm`（1in = 25.4mm）か `pt`（1in = 72pt）で厳密に書けるからである。

[golem-pdf ADR 0010](../../golem-pdf/adr/0010-golem-check-g0702-and-template-bleed.md) の草案で、`golem new` の英語の雛形の塗り足しを 0.125in にすると決めた。
英語圏の印刷所が塗り足しや判型をインチで示すことが多いので、メンテナーは、`in` の単位を加えると決めた。
`in` がないと、書き手は 0.125in を `9pt` や `3.175mm` に換算して書く必要があり、`style.toml` を読む人には元の値が分からない。

寸法の文字列は、すべて `Golem.Project.Style.parseDim` で読む。
`style.toml` の寸法、判型の寸法（[ADR 0005](0005-page-size-by-dimensions.md)）、プリフライトの設定の寸法、`@figure` の `width`、原稿の `[aki]` の寸法である。
`parseDim` に単位を一つ足せば、すべての寸法で `in` を使える。

## 実装すること

- `parseDim` に `in` を加える。1in は 72pt であり、`r` in を `round (r × 72 × 65536)` sp に一度だけ丸める（ほかの単位と同じく、正確な有理数から一度だけ、等距離なら偶数の側へ丸める）。
- `parseSignedDim` も `parseDim` を使うので、負の寸法（`-0.5in`）も書ける。
- `in` は絶対的な寸法（`Abs`）であり、`zw` を拒む欄（判型など）でも使える。
- [golem-pdf ADR 0010](../../golem-pdf/adr/0010-golem-check-g0702-and-template-bleed.md) の草案の英語の雛形の塗り足しを、`bleed = "9pt"` から `bleed = "0.125in"` に改める。この ADR と golem-pdf ADR 0010 を一緒に採択するときは、golem-pdf ADR 0010 の本文をこの値で書いてから採択する。
- 寸法として読めない値の diagnostic（G0306、G0317 など）のメッセージで、使える単位を並べている箇所に `in` を足す。

### ドキュメント

- 仕様書の「style.toml」の節の単位の一覧に `in`（インチ。1in = 72pt = 25.4mm）を足す。判型の節の「インチの単位はなく」の文を、`in` で書けると改める。
- `docs/diagnostics.md` で、使える単位を並べている節に `in` を足す。
- 使い手のマニュアルの第 5 章と付録 C の単位の説明に `in` を足し、英語の本の判型を `in` で書く例（`{ width = "5.5in", height = "8.5in" }`）を載せる。
- [ADR 0003](0003-mass-market-paperback-size.md) と [ADR 0005](0005-page-size-by-dimensions.md) のステータスの行に「採択→インチの単位は [ADR 0010](0010-inch-unit.md)」を足す。

## 実装しないこと

- `cm`、`pc`（パイカ）、`px` などのほかの単位。必要になったら、別の ADR で加える。
- 寸法を表に出すときの単位。diagnostic のメッセージやプリフライトの要約は、今のとおり `mm` で書く。
- 判型の表に、インチで決まる判型の名前（`letter` など）を加えること。

## テスト設計

テストを先に書き、今の実装で失敗することを確かめる。

- golem-project：`parseDim "1in"` が `Abs (72 × 65536)`、`"0.125in"` が `Abs (9 × 65536)`、`"8.5in"` が `parseDim "612pt"` と同じ値になること。`"0.1in"`（7.2pt）が `round (7.2 × 65536)` になること。
- golem-project：`parseSignedDim "-0.5in"` が負の値になること。`"1 in"`（空白を挟む）と `"1In"`（大文字）は読めないこと（ほかの単位と同じ）。
- golem-project：判型の `{ width = "5.5in", height = "8.5in" }` が、`{ width = "396pt", height = "612pt" }` と同じ判型になること。
- golem-driver：英語の雛形で組んだ PDF の `BleedBox` が、0.125in（9pt）の塗り足しになること（golem-pdf ADR 0010 のテストを `0.125in` で書く）。

## トレードオフ

- 単位が一つ増えるので、書き手が覚えることが増える。ただ、英語圏の印刷所の仕様をそのまま写せるほうが、換算の誤りが減る。
- 小数のインチ（`0.1in` など）は sp で正確に表せないことがあるが、ほかの単位と同じく一度だけ丸めるので、結果は決定的である。

## 参考文献

- [ADR 0003](0003-mass-market-paperback-size.md)
- [ADR 0005](0005-page-size-by-dimensions.md)
