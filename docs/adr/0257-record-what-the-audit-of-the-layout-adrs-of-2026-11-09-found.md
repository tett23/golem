# ADR 0257: 2026-11-09 の組版の ADR の監査で見つかった、ADR の文と実装の食い違いを記録する

ステータス: 採択

## 文脈

2026-11-09 に、[golem-layout ADR 0033](../golem-layout/adr/0033-read-waiting-figures-from-the-placement.md) から [0045](../golem-layout/adr/0045-break-inline-code-after-hyphens-and-full-stops-to-avoid-loose-lines.md)、[golem-driver ADR 0045](../golem-driver/adr/0045-draw-tate-chu-yoko-horizontally-in-pdf.md)、[golem-pdf ADR 0015](../golem-pdf/adr/0015-scaled-glyph-run-restores-horizontal-scaling.md) の実装を、ADR の文と照らした（origin/main `81e1d187`）。
[ADR 0211](0211-record-what-implementations-decided-found-by-the-review-of-2026-11-08.md)、[ADR 0236](0236-record-what-implementations-decided-found-by-the-second-review-of-2026-11-08.md)、[ADR 0255](0255-record-what-implementations-decided-on-2026-11-09.md) と同じく、ADR の決めたことと実装が食い違い、直せるものはプルリクエストで直した。
Alloy のモデルの食い違いは [golem-layout ADR 0046](../golem-layout/adr/0046-the-alloy-model-judges-a-larger-need-lines-without-the-spaces-before-it.md) が扱い、[#785](https://github.com/tett23/golem/pull/785) が実装した。
[golem-layout ADR 0045](../golem-layout/adr/0045-break-inline-code-after-hyphens-and-full-stops-to-avoid-loose-lines.md) の表のセルの最小の幅、G09013 の文、J5 の確かめ方は、[ADR 0255](0255-record-what-implementations-decided-on-2026-11-09.md) がすでに記録している。

残ったのは、ADR のテスト設計の文が実装の前提を取り違えていたものと、テスト設計の一つを ADR の指定した場所と書体で行えなかったものである。
どれも実装の振る舞いは ADR のとおりであり、食い違うのは ADR の文か、テストの置き場所である。
この ADR は、それらを記録し、テストの置き場所は「メンテナーが決めること」で決める。

以下、元の ADR の番号の順に並べる。
各項目は、ADR の文、実装、そうした理由の順に書く。

### [golem-layout ADR 0034](../golem-layout/adr/0034-line-breaks-between-japanese-characters-in-inline-code.md)：golem-typeset のテスト

テスト設計は、golem-typeset のテストを二つ求めた。
一つは「付録 E の G03029 の全文を、利用者のマニュアルの書体と版面で組み、G07105 が出ないこと」である。
もう一つは「和文を含むコードの箱の幅の和が、この ADR の前の一つの箱の幅と同じであること（Noto Sans JP で、コードのカーニングを切った状態）」である。
実装（[#713](https://github.com/tett23/golem/pull/713)）は、このテストを書かなかった。
golem-driver の `PdfSpec` の C8 のテストが、テストの書体の提供者（`fakeProvider`）と G07046 の文で、G07105 が出ないことを確かめているだけである。
トレードオフの節の「箱の幅の和が変わらないことを、テスト設計の golem-typeset のテストで確かめる」も、確かめられていなかった。

マニュアルの書体（Noto Sans JP、Source Code Pro）は `scripts/manual/fetch-fonts.sh` で取得するもので、リポジトリにない。
golem-typeset のテストは実在の書体を読まず、実在の書体で組むテストの仕組みは golem-driver のテスト（`SpecimenGeometrySpec` の `jaLatin`、Noto Serif JP と Source Sans Pro）にある。
監査のプルリクエスト [#779](https://github.com/tett23/golem/pull/779) は、golem-driver のテスト `CodeFontSpec` に、G03029 の全文を 13Q、38 字詰めの横組みで Noto Serif JP で組んで diagnostic が出ないことと、和文の字ごとの箱の幅の和が、同じ並びを一つにシェイピングした送りと箱ごとの丸めの差（1 sp ずつ）の範囲で一致すること（C7）を足した。
ADR の指定（golem-typeset、Noto Sans JP、利用者のマニュアルの版面）とは、モジュール、書体、版面が違う。
これで足りるかを「メンテナーが決めること」の 1 で決める。

### [golem-layout ADR 0035](../golem-layout/adr/0035-a-larger-need-lines-after-a-judged-one-is-judged-again.md)：プルリクエストの段の列挙

テスト設計は、「`ENeedLinesMore` を足した列挙で、今の P1 と P2 の述語が、プルリクエストの段で違反を見つけること（直す前）と、見つけないこと（直した後）を確かめる」とした。
この ADR の形は、段落、`@need-lines`、空き、より大きい `@need-lines`、次のブロックの 5 個の要素が要る（段が空なら二つめは満たされ、ブロックがなければ `@need-lines` は段の終わりで捨てられる）。
プルリクエストの段は要素 3 個までを調べる（[ADR 0208](0208-widen-lightweight-formal-methods.md)）ので、直す前でも違反は見つからない。
実装（[#710](https://github.com/tett23/golem/pull/710)）は `ENeedLinesMore` を要素の一覧に足し、例のテストと境界のテストで直す前の失敗を確かめた。
ADR の文の「プルリクエストの段で」は、毎晩の段（要素 5 個まで）の誤りである。

### [golem-layout ADR 0045](../golem-layout/adr/0045-break-inline-code-after-hyphens-and-full-stops-to-avoid-loose-lines.md)：列挙の C5

テスト設計の「列挙：3 の部品で、L1 から L13、C1、C2、C5 から C8、J1 から J7 が……成り立つこと」は、C5（文字スタイル `url` の項目は 0034 の前と同じ）を列挙の述語に数えた。
C5 は、[golem-layout ADR 0034](../golem-layout/adr/0034-line-breaks-between-japanese-characters-in-inline-code.md) の実装のときから列挙の述語ではなく、例のテストで確かめている（仕様書の「行分割」の節の「C5（`url`）は例のテストで確かめる」）。
列挙の部品に `url` はない。
実装（[#767](https://github.com/tett23/golem/pull/767)）は C5 を述語に足さなかった。
ADR の文の「C5 から C8」は「C6 から C8」の誤りである。

### [golem-driver ADR 0045](../golem-driver/adr/0045-draw-tate-chu-yoko-horizontally-in-pdf.md)：I8 の `pdf-sample.txt` と、述語 8 のテスト

テスト設計の I8 は、「横組みの PDF のテスト、出力のゴールデン（`pdf-sample.txt`、`pdf-complex-horizontal.txt`、`pdf-figures.txt`）、決定性の検査の横組みの PDF のハッシュが、変わらずに通る」とした。
`sample` の PDF のゴールデンは、`scripts/determinism/pdf-style.toml`（B6、縦組み）で組む（[`OutputGoldenSpec.hs`](https://github.com/tett23/golem/blob/81e1d1870965141ed297c408790270dd3e006897/modules/golem-driver/test/OutputGoldenSpec.hs#L102-L111)）。
`sample` の原稿は注を持ち、注の番号の一字の縦中横を含む。
実装（[#722](https://github.com/tett23/golem/pull/722)）は、ADR の「一字の縦中横も同じ規則で描く」に従い、`pdf-sample.txt` を更新した（注の番号が縦組みのフォントの参照から横組みのフォントの参照に移った）。
`scripts/determinism/hashes.txt` の `pdf/` の項目と `scripts/visual/pages/sample.txt` も変わった。
ADR の I8 の「`pdf-sample.txt` は横組み」という前提が誤りで、実装は正しい。

ADR の不変条件の節は「テストの名前には、ここの番号を入れる」とした。
実装は述語 1 から 6 を「I1–I6」の三つのテストにまとめ、述語 8 の名前を持つテストを置かなかった（横組みのゴールデンと決定性の検査が担う）。
[#779](https://github.com/tett23/golem/pull/779) は、`TateChuYokoSpec` に「I8」の名前のテストを足した。
横組みの本の `[tcy: 12]` の字形が、横組みのフォントの参照で、回転せず、比率をかけず、一つの基準線に順に並び、ページに `Tz` がないことを確かめる。
ADR の前の出力との一致は、ゴールデンと決定性の検査のままである。

## 実装すること

ここに記録した点は、監査のプルリクエスト [#779](https://github.com/tett23/golem/pull/779) でテストを足したもののほかは、文書の記録だけである。
この ADR の実装は、次のことだけを行う。

- 次の ADR のステータスの行に、この ADR が記録した点を足す。すでに `→` を持つ行には `、` でつないで足す。
  - golem-layout 0034（golem-typeset のテストの置き場所と書体）、0035（プルリクエストの段の文）、0045（列挙の C5）
  - golem-driver 0045（I8 の `pdf-sample.txt`、述語 8 のテスト）
- `CodeFontSpec` の注釈に、この ADR へのリンクを足す。

## 実装しないこと

- **元の ADR の文を書き換えること**：コミット済みの ADR は、ステータスの行のほかは変えない。
- **マニュアルの書体をテストで取得すること**：ネットワークに依存するテストを足さない。「メンテナーが決めること」の 1 の退けた案。
- **振る舞いを変えること**：どの実装も ADR の決めた振る舞いのとおりである。

## 不変条件

なし。
この ADR は記録と、テストの置き場所の判断だけを扱い、新しい振る舞いを決めない。

## テスト設計

- ステータスの行の変更は、`adr-guard pre-commit` が検査する。
- `CodeFontSpec` の二つのテストは、[#779](https://github.com/tett23/golem/pull/779) で足し、今の実装で通る。箱の幅の和のテストは、`codeItems` の結合文字のトラッキングの修正の前にも通る（この並びに結合文字がない）。

## トレードオフ

ADR の文の誤りを、元の ADR を直さずに記録で残すので、0035 と 0045 と golem-driver 0045 を読む人は、ステータスの行からこの ADR へたどる必要がある。

golem-typeset のテストを golem-driver に置くと、golem-typeset だけを変えたときに、このテストが走るのは golem-driver のテストの段になる。
その代わり、テストの書体の提供者を golem-typeset に足さずに済む。

## メンテナーが決めること

1. **0034 の golem-typeset のテストの代わり**：推奨は、golem-driver の `CodeFontSpec`（Noto Serif JP、13Q、38 字詰め）で足りるとすることである。確かめたい性質（字ごとの箱の幅の和が一つの箱の幅と同じこと、長い和文のメッセージが禁則に従って分かれて収まること）は、書体が Noto Sans JP でも Noto Serif JP でも同じ仕組みで成り立つ。
   - 退けた案の一つは、マニュアルの書体を CI で取得して組むテストである。`scripts/manual/fetch-fonts.sh` のネットワークへの依存がテストに入る。
   - もう一つは、テストを足さず、記録だけにすることである。トレードオフの節の「確かめてはいない」が残る。

## 決めたことの記録

2026-11-09 に、tett23 が「メンテナーが決めること」のすべてを推奨のとおりとした。

1. **0034 の golem-typeset のテストの代わり**：golem-driver の `CodeFontSpec`（Noto Serif JP、13Q、38 字詰め）で足りるとする。マニュアルの書体を CI で取得して組むテストの案と、記録だけにする案は退けた。

## 参考文献

- [golem-layout ADR 0034](../golem-layout/adr/0034-line-breaks-between-japanese-characters-in-inline-code.md)、[golem-layout ADR 0035](../golem-layout/adr/0035-a-larger-need-lines-after-a-judged-one-is-judged-again.md)、[golem-layout ADR 0045](../golem-layout/adr/0045-break-inline-code-after-hyphens-and-full-stops-to-avoid-loose-lines.md)、[golem-layout ADR 0046](../golem-layout/adr/0046-the-alloy-model-judges-a-larger-need-lines-without-the-spaces-before-it.md)
- [golem-driver ADR 0045](../golem-driver/adr/0045-draw-tate-chu-yoko-horizontally-in-pdf.md)、[golem-pdf ADR 0015](../golem-pdf/adr/0015-scaled-glyph-run-restores-horizontal-scaling.md)
- [ADR 0208](0208-widen-lightweight-formal-methods.md)、[ADR 0211](0211-record-what-implementations-decided-found-by-the-review-of-2026-11-08.md)、[ADR 0236](0236-record-what-implementations-decided-found-by-the-second-review-of-2026-11-08.md)、[ADR 0255](0255-record-what-implementations-decided-on-2026-11-09.md)
- [#710](https://github.com/tett23/golem/pull/710)、[#713](https://github.com/tett23/golem/pull/713)、[#722](https://github.com/tett23/golem/pull/722)、[#767](https://github.com/tett23/golem/pull/767) の説明。監査のプルリクエスト：[#779](https://github.com/tett23/golem/pull/779)
