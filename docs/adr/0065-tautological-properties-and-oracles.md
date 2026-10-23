# ADR 0065: 実装を写したオラクルと、同じ式を二度評価するだけの断言をなくす

ステータス: 採択（未実装）

## 文脈

プロパティテストが検査になるのは、期待値を実装と独立に求めたときだけである。
期待値を実装と同じ式で求めると、式の誤りは両方に同じく入り、テストは常に通る。
純粋な関数を同じ引数で二度呼んで比べる断言も、Haskell では型が一致を保証するので、何も確かめていない。

2026-10-23 のテストの品質の点検は 8 件を挙げた。
コードと照らし合わせ、次の 7 件がこれに当たることを確かめた。

1. [modules/golem-lsp/test/Main.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-lsp/test/Main.hs#L353-L361) の「within the line, fromLineCol agrees with the exact conversions」は、列を `0..width` の範囲で生成する。[`fromLineCol`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-lsp/src/Golem/Lsp/Features.hs#L62-L69) は、列が `width` 以下なら `utf8LineColToOffset` と `utf16LineColToOffset` をそのまま呼ぶ。テストはその二つと比べているので、同じ関数を比べている。
2. [modules/golem-parser/test/CSTSpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-parser/test/CSTSpec.hs#L38-L40) の「width equals the sum of children」は、生成器が [`node`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-parser/src/Golem/Parser/CST.hs#L144-L145) で木を作る。`node` は幅を子の幅の和として定義するので、テストは定義を確かめているだけである。パーサが作った木は対象にしていない。
3. [modules/golem-pdf/test/Main.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-pdf/test/Main.hs#L1250-L1251) の `writePdf sample @?= writePdf sample` と、[同じファイル](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-pdf/test/Main.hs#L1333) の `pdf === writePdf (documentWith [page marks])`。[その次の行](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-pdf/test/Main.hs#L1334) の `xrefConsistent` の断言は有効である。
4. [modules/golem-doc/test/Main.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-doc/test/Main.hs#L134) の `bs === encodeDocument d`。[その次の行](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-doc/test/Main.hs#L135) の正準性の断言は有効である。
5. [modules/golem-eval/test/FileSpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-eval/test/FileSpec.hs#L1511) の `diags x === diags x`。[その直前](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-eval/test/FileSpec.hs#L1509-L1510) の、別の文脈との比較は有効である。
6. [modules/golem-svg/test/Main.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-svg/test/Main.hs#L257-L259) の `readSvg doc @?= readSvg doc`。
7. [modules/golem-layout/test/Main.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-layout/test/Main.hs#L124-L176) の `bruteBest` は、分け方の探索を総当たりで独立に行うが、採点に実装の `badness`、`lineDemerits`、`fitnessOf`（[`bruteScore` の採点](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-layout/test/Main.hs#L165-L175)）を使う。`badness` は TeX の値と比べる [単体テスト](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-layout/test/Main.hs#L320-L322) があるが、`lineDemerits` と `fitnessOf` の式の誤りは、このオラクルでは見つからない。

点検の 8 件めに挙がった [modules/golem-layout/test/Main.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-layout/test/Main.hs#L829-L837) の headingBlock のプロパティは、これに当たらない。
オラクルの式は [golem-driver ADR 0003](../golem-driver/adr/0003-pdf-heading-styles.md) の 99-105 行に書かれた計算の手順そのものであり、実装もこの手順を写している。
プロパティの名前のとおり、最小の行数が 1 のときに [golem-driver ADR 0003](../golem-driver/adr/0003-pdf-heading-styles.md) の式に戻ることを確かめるテストであり、仕様を独立のオラクルにしている。
最小の行数が 1 より大きい場合は、[その後の単体テスト](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-layout/test/Main.hs#L838-L846) が具体的な値で確かめている。

## 実装すること

- 1：プロパティの列の範囲を `0..width + 5` に広げ、`width` を超えた列で行の末尾のオフセットになることを同じプロパティで断言する。`width` 以下の列では、オフセットから `toLineCol` で戻した列が元の列に一致すること（往復）を断言する。往復は `fromLineCol` の実装と独立である。
- 2：プロパティの対象を、`parse` で作った木に変える。入力は [ParserSpec の断片の生成器](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-parser/test/ParserSpec.hs#L54-L89) を使う。`node` の定義そのものの確認は削る。
- 3 から 6：同じ式を二度評価する断言を削る。決定性は、プロセスと環境をまたいだ検査（[ADR 0002](0002-determinism.md) の `determinism` ジョブと、[scripts/env-determinism/check.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/env-determinism/check.sh)）に任せる。プロパティの名前から「deterministic」を除く。
- 7：`lineDemerits` と `fitnessOf` を、テストの中で [golem-layout ADR 0001](../golem-layout/adr/0001-knuth-plass-line-breaking.md) と TeX の定義から書き直した関数に置き換える。`badness` は TeX の値との単体テストがあるので、実装のものを使い続ける。

## 実装しないこと

- headingBlock のプロパティを変えること（上の理由による）。
- TeX のトレースとの比較（[modules/golem-layout/test/Main.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-layout/test/Main.hs#L498-L507)）を変えること。これは独立のオラクルであり、有効である。

## テスト設計

- 1：`fromLineCol` の `c > width` の分岐を `exact enc li lc` に置き換えた変異で、新しいプロパティが落ちる。今のプロパティはこの変異で落ちない。
- 2：`node` の幅の計算を壊さず、パーサの `Lower` で子を落とす変異（例えば最後の子を捨てる）で、新しいプロパティが落ちる。
- 7：[`lineDemerits`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-layout/src/Golem/Layout/KnuthPlass.hs#L183-L187) の上限の条件を `abs l >= 10000` から `abs l > 10000` に変えた変異と、`fitnessOf` の境界の不良度を一つずらした変異で、総当たりとの比較が落ちる。今は実装の関数を採点に使うので落ちない。変異が落ちる入力を生成器が出さないときは、その入力を単体テストとして足す。
- 3 から 6 は削除なので、テストの数が減ることをプルリクエストの説明に書く。

## トレードオフ

- 7 の書き直しは、テストの中に TeX の式をもう一つ持つことになる。式を二か所に書くので、仕様を変えるときは両方を変える必要がある。その二か所が独立に書かれていることが、このオラクルの価値である。
- 3 から 6 を削ると、決定性をそのテストの場で確かめることはなくなる。もともと確かめていなかったので、失うものはない。
- 削った同語反復の断言は、のちに別の言語で検査を書いて補える。

## 参考文献

- [ADR 0002](0002-determinism.md)
- [golem-driver ADR 0003](../golem-driver/adr/0003-pdf-heading-styles.md)
- [golem-layout ADR 0001](../golem-layout/adr/0001-knuth-plass-line-breaking.md)
- Knuth, D. E. and Plass, M. F. Breaking Paragraphs into Lines. Software: Practice and Experience 11 (1981).
