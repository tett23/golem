# ADR 0436: 改行しない範囲の S1 を、製品と同じ組版の環境の送りで確かめる

Status: accepted-pending

## 文脈

[root ADR 0305](0305-leave-soft-hyphens-in-or-next-to-a-no-break-range-out-of-i8.md) の S1 は、ソフトハイフンが改行しない範囲に接するとき、同じテキスト内で分かれた箱をつなぎ、つないだ箱の幅を語の送りで補正する。
[root ADR 0314](0314-check-no-break-widths-with-harfbuzz.md) は、S1 を三つの書体の HarfBuzz の送りで確かめると決め、実装した。
ところが 0314 は、次のことを決めずに残した。

- 書体の性質を、どこまで網羅するか。
- 一字ごとの送り（`ceAdvance`）を、実際の書体で確かめるか。
- 縦組みの送り（0314 は対象外とした）。

0314 のテストは、OpenType の機能を渡さずに HarfBuzz を呼んで語の送りを作るので、HarfBuzz の既定の機能（`kern`、`liga` など）を通した送りでは確かめているが、製品が役割ごとに足す機能（`palt`、`vpal` など）を通した送りでは確かめていない。
この ADR は、0314 が残したこれらを決める。

## 調査した事項

origin/main（[9efdc4f89](https://github.com/tett23/golem/commit/9efdc4f89b3fec75abcd37c11abb3e1d909c6725)）で、次のことを確かめた。

- 0314 のテスト（golem-layout の `NoBreakShapeSpec.hs` の `S1: real font advances preserve every small no-break range`）は、Source Sans Pro、Source Serif Variable、Source Han Sans のサブセットの三つの書体で、機能の一覧を空にして HarfBuzz を呼ぶ。
  列は各書体 1814 入力である。
  三つの書体の AV の送りの差は −14、−130、−15 で、Source Serif Variable の fi は一つのグリフになる（0314 の表）。
  0314 は、縦組みの送りを対象外とし、各文字の送りとルビの送りを実際の書体で調べることを未実施とした。
- 製品の組版の環境は、golem-typeset の `composeEnv`（[Flow.hs#L1837-L1850](https://github.com/tett23/golem/blob/9efdc4f89b3fec75abcd37c11abb3e1d909c6725/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L1837-L1850)）が作る。
  `ceAdvance` は `LoadedFonts` の `lfAdvance` から、`ceWordAdvance` は `lfWordAdvance` から、役割ごとの `Shaping` を渡して作る。
  `lfWordAdvance` は `LoadedFonts` のフィールドで（[Fonts.hs#L104](https://github.com/tett23/golem/blob/9efdc4f89b3fec75abcd37c11abb3e1d909c6725/modules/golem-typeset/src/Golem/Typeset/Fonts.hs#L104)）、語を組んだ送りの和である（[FontProvider.hs#L199](https://github.com/tett23/golem/blob/9efdc4f89b3fec75abcd37c11abb3e1d909c6725/modules/golem-typeset/src/Golem/Typeset/FontProvider.hs#L199)）。
  字間の追加（トラッキング）は、`lfWordAdvance` に入らない。
- 和文の `palt`（縦組みでは `vpal`）は、段落のスタイルか文字のスタイルの `proportional-metrics = true` で入り、約物に当てるには、役割（`[fonts.<役割>]`）の `punctuation-proportional = true` も要る（[root ADR 0378](0378-punctuation-proportional-features.md)、[Fonts.hs#L594-L631](https://github.com/tett23/golem/blob/9efdc4f89b3fec75abcd37c11abb3e1d909c6725/modules/golem-typeset/src/Golem/Typeset/Fonts.hs#L594-L631)）。
  既定の役割では入らない。
- `composeEnv` の型は `Text -> Style -> PageGeometry -> LoadedFonts -> Assumed -> Look -> ComposeEnv` で、`Golem.Typeset.Flow` は golem-typeset の other-modules にある（公開していない）。
  `LoadedFonts` は、`Golem.Typeset.FontProvider` の `provide` で、読んだ書体から作る。
- `ceAdvance` と `ceWordAdvance` は、どちらも同じ `Shaping` で `LoadedFonts` の同じ記憶（memo）を通る（[FontProvider.hs#L199-L214](https://github.com/tett23/golem/blob/9efdc4f89b3fec75abcd37c11abb3e1d909c6725/modules/golem-typeset/src/Golem/Typeset/FontProvider.hs#L199-L214)）。
  そのため、一字の `ceAdvance` と、その字だけの `ceWordAdvance` は、作り方から等しい。
  golem-font の `shapeUnits` は、機能の一覧を渡して HarfBuzz で組む、製品の記憶を通らない経路である。
- 0314 の列（golem-layout のテストの `NoBreakEnum.hs` の `realProbe`）は、13 の部品（`漢`、`あ`、`。`、`「`、`a`、`table`、`hyphenation`、`lime-tree`、空白、ソフトハイフン、二字の親字のルビ、コード、強制改行）を範囲の内と外で並べた長さ 0 から 2 の列（703 入力）と、`A`、`V`、`f`、`i`、ソフトハイフンを範囲の内と外で並べた長さ 0 から 3 の列（1111 入力）で、合わせて 1814 入力である。
  述語は `s1With` で、幅 3 em の段落で確かめる。
  この補助は、golem-layout のほかに golem-doc、golem-syntax、golem-unicode を使う。
- golem-font のテストの書体のうち、和文の Source Han Sans のサブセットは `palt` と `halt` を持たない。
  `palt` を持つ和文の書体は、golem-driver のテストの素材の NotoSerifJP（`modules/golem-driver/test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf`、OFL）である。
  golem-layout-test は、書体を `../golem-font/test/fonts/` のように相対パスで読む。
- golem-typeset のライブラリは golem-layout と golem-font に依存するが、golem-typeset-test の build-depends には golem-layout が無い。
  golem-* のあいだの依存を変えるには、テストの依存でも ADR が要る（メンテナーの決まり）。
- 列挙の時間の予算（範囲ごとに 10 秒、和 30 秒、[root ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md)）は、`enum.yml` の golem-layout-test の範囲だけを測る（`scripts/ci/enum-timings.sh`）。
  golem-typeset-test のテストは、この予算に入らない。

指示者は 2026-11-23 に、この項目の ADR を書くよう求めた。

## 実装すること

### 製品の環境で確かめる

0314 の S1 の検査を、製品と同じ組版の環境で行う検査を足す。
環境は、golem-typeset の `composeEnv` で作る。
引数は、次のように作る。

- `Style`: 検査のための `style.toml` を読んだもの（役割、段落のスタイル、判型）。
- `PageGeometry`: その `Style` の判型から、製品と同じ関数で作ったもの。
- `LoadedFonts`: 実際の書体を `provide` で読んだもの。
- `Assumed`: ページの参照を持たない列なので、空の仮定。
- `Look`: 本文の段落のスタイルから、製品と同じ関数で作ったもの。

こうすれば、`ceAdvance` と `ceWordAdvance` が、製品と同じ機能の一覧と同じ関数を通る。
製品が機能の選び方を変えても、検査が追う。
`composeEnv` と、引数を作る関数のうち公開していないものは、golem-typeset のテストのための公開のモジュール（`Golem.Typeset.Internal` などの名前）から export する。

検査は golem-typeset-test に置く。
golem-typeset-test の build-depends に、golem-layout、golem-doc、golem-syntax、golem-unicode、golem-font を足す。
写す S1 の補助が前の四つを使い、一字ごとの送りの検査が golem-font の `shapeUnits` を使うためである。
golem-typeset のライブラリがすでにこれらに依存するので、パッケージのあいだの依存の向きは変わらない。
S1 の述語（0305 の手順で得た項目列との一致と、つないだ箱の幅の補正）は、golem-layout のテストの補助から golem-typeset-test に写す。
golem-layout-test から golem-typeset に依存させると、検査の対象を組むパッケージにテストが依存する向きになるので、採らない。

### 網羅する書体の性質

次の四つの性質を、それぞれの書体と役割の設定で確かめる。

| 性質 | 書体 | 役割の設定 | 0314 との違い |
| --- | --- | --- | --- |
| 欧文のペアのカーニング | Source Sans Pro | 既定 | 製品の環境を通す |
| 欧文の合字 | Source Serif Variable | 既定 | 製品の環境を通す |
| 和文のプロポーショナルな送り（横組み） | NotoSerifJP | 本文の段落のスタイルの `proportional-metrics = true` と、役割の `punctuation-proportional = true` | `palt` を通す |
| 和文のプロポーショナルな送り（縦組み） | NotoSerifJP | 同上で、縦組みの判型 | `vpal` を通す |

NotoSerifJP の行では、役割の `ja` と `latin` の両方に NotoSerifJP を当て、列の欧文の部品も NotoSerifJP で組む。

NotoSerifJP は、golem-driver のテストの素材のファイルを、相対パス `../golem-driver/test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf` で読む。
サブセットを作らず、リポジトリに書体を足さない。

### 一字ごとの送り

検査の列のどの字についても、`ceAdvance` の一字の送りが、golem-font の `shapeUnits` に、その字と、その役割の `Shaping` の機能の一覧を渡した送りと等しいことを確かめる。
`ceWordAdvance` と比べないのは、二つが同じ記憶を通るので、作り方から等しいためである。
ルビの送りは含めない。
ルビは、親字の送りと別の規則で配るので、別の範囲として扱う。

### 列と時間

列は、四つの性質のどれでも、0314 と同じ 1814 入力とする。
0314 の部品には、すでに漢字、仮名、句点、かぎ括弧が入っているので、和文の書体でも部品を変えない。

縦組みでは、つないだ箱の幅を、行の向き（縦）の送りと読み、`s1With` をそのまま使う。
実装で `s1With` が縦組みの環境でそのまま成り立つ形でないと分かったときは、縦組みの行の実装を止め、扱いを別の ADR で決める。

この検査は 0281 の列挙の範囲ではなく、予算も持たない。
実装のプルリクエストで四つの性質の検査の壁時計の時間を計って書く。
golem-typeset-test が CI の時間の上限に近づいたときは、[root ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md) と同じく、毎晩の検査に移すかを別の ADR で決める。

### ロードマップとステータスの行

ロードマップの「改行しない範囲の S1 を実際の書体の送りで確かめる」の項目を消す。
採択したら、[root ADR 0314](0314-check-no-break-widths-with-harfbuzz.md) のステータスに、書体の性質と縦組みと一字ごとの送りを、この ADR が補ったと記録する。

```text
superseded [{"part":"実装しないこと","by":["docs/adr/0436-check-no-break-s1-through-the-product-shaping.md"],"kind":"supplement"},{"part":"テスト設計","by":["docs/adr/0436-check-no-break-s1-through-the-product-shaping.md"],"kind":"supplement"}]
```

## 実装しないこと

0314 の今の検査（機能を渡さない HarfBuzz の送り）は、消さずに残す。
ルビの送りを実際の書体で確かめない。
S1 の規則そのもの（0305）は変えない。
可変フォントの軸の値ごとの網羅はしない。
字間の追加（トラッキング）を通した送りは確かめない。

## 不変条件

- I1: 四つの性質の書体と役割の設定で、検査の列のどの入力についても、0314 の S1（範囲を無効にした結果から 0305 の手順で得た項目列と、範囲を有効にして組んだ項目列が一致し、つないだ箱の幅には `ceWordAdvance` による補正を含む）が、`composeEnv` で作った環境で成り立つ。
- I2: 各性質について、表の性質が、その書体と役割の設定の `ceWordAdvance` で現れる（AV の送りが A と V の送りの和より小さい、fi の送りが f と i の送りの和と違う、`「あ` の横と縦の送りが、`palt` と `vpal` を入れない役割の送りより小さい）。
- I3: 検査の列のどの字 `c` についても、`ceAdvance` の `c` の送りは、golem-font の `shapeUnits` に `c` と同じ機能の一覧を渡した送りを、文字の大きさで換算したものと等しい。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| Source Sans Pro の `AV` | S1 が成り立ち、送りが字の送りの和より小さい | I1, I2 |
| Source Serif Variable の `fi` | S1 が成り立ち、送りが字の送りの和と違う | I1, I2 |
| NotoSerifJP の `「あ」` 横組み | S1 が成り立ち、`palt` の無い役割より送りが小さい | I1, I2 |
| NotoSerifJP の `「あ」` 縦組み | S1 が成り立ち、`vpal` の無い役割より送りが小さい | I1, I2 |
| 一字 `A` | `ceAdvance` と `shapeUnits` の送りが等しい | I3 |
| 一字 `「` を `palt` の役割で | `ceAdvance` と `palt` を渡した `shapeUnits` の送りが等しい | I3 |
| 空の列 | S1 が成り立つ | I1 |
| ソフトハイフンが範囲のすぐ外にある列 | 0305 の境界の決まりで S1 が成り立つ | I1 |

## 受けいれ条件

なし。
不変条件のテストで足りるためである。

## テスト設計

root ADR 0436 I1 から I3 を名前の先頭に置いたテストを、golem-typeset-test に足す。
I1 は、四つの性質ごとに列を列挙し、S1 を確かめる。
I2 は、表の性質を一つの入力ずつ確かめ、性質を持たない役割（`palt` の無い役割など）で同じ検査が落ちることも確かめる。
I3 は、各性質の列の字をすべて確かめる。
実装のプルリクエストで、四つの性質の検査の壁時計の時間を書く。

## トレードオフ

製品の `composeEnv` で確かめるので、検査は製品の送りの誤りと S1 の誤りを区別できない。
0314 の機能を渡さない検査を残すことで、HarfBuzz そのものの送りとの比較も残す。

golem-typeset-test が golem-layout に依存するので、テストのパッケージの依存が一つ増える。
その代わりに、製品と同じ環境を、検査のために作り直さずに済む。

NotoSerifJP を golem-driver の素材から読むので、golem-typeset-test は golem-driver のフォルダのファイルに依る。
素材を動かすときは、この検査のパスも直す。

## 参考文献

- [root ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md)
- [root ADR 0305](0305-leave-soft-hyphens-in-or-next-to-a-no-break-range-out-of-i8.md)
- [root ADR 0314](0314-check-no-break-widths-with-harfbuzz.md)
- [root ADR 0378](0378-punctuation-proportional-features.md)
