# ADR 0015: 伸縮した行の水平の比率を後の描画に残さない

ステータス: 採択（未実装）

## 文脈

[golem-layout ADR 0005](../../golem-layout/adr/0005-microtypography.md) は、`[composition]` の `expansion` で欧文のグリフの幅を行ごとに伸び縮みさせ、PDF では水平の比率の演算子 `Tz` で描くと定めた。
golem-pdf の書き出しは、その行のグリフを `ScaledGlyphRun` のマークで受け取り、`Tz` を書く。
ところが `Tz` を戻さないので、同じページで後に描くグリフも同じ比率で描かれる。
golem-driver の [ADR 0045](../../golem-driver/adr/0045-draw-tate-chu-yoko-horizontally-in-pdf.md) を実装したときに、コードを読んで見つかった。
この ADR は、その振る舞いを PDF で確かめ、直し方を決める。

### 今の振る舞い

`Golem.Pdf.Writer.markBuilder` は、`ScaledGlyphRun` を `BT /F<n> <大きさ> Tf <比率> Tz`、各グリフの `Tm` と `Tj`、`ET` の順に書く（[Writer.hs の 366 行から 367 行](https://github.com/tett23/golem/blob/4b3ffcb406d8edee9be3e6a5cd78667b564e3f4e/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L366-L367)）。
`q` と `Q` で囲まず、後に `100 Tz` も書かない。

ほかのグリフのマークは、比率を自分で書かない。

- `GlyphRun` と `RotatedGlyphRun` は `Tz` を書かない（[365 行から 369 行](https://github.com/tett23/golem/blob/4b3ffcb406d8edee9be3e6a5cd78667b564e3f4e/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L365-L369)）。
- `StyledGlyphRun` は `q` と `Q` で囲むが、`rsScale` が 1000 のときは `Tz` を書かない（[389 行から 403 行](https://github.com/tett23/golem/blob/4b3ffcb406d8edee9be3e6a5cd78667b564e3f4e/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L389-L403)）。`q` は状態を保存するだけで、比率を 100 に戻さない。
- `TransformedGlyphRun` は `Tz` を書かず、線の幅が 0 なら `q` と `Q` でも囲まない（[404 行から 415 行](https://github.com/tett23/golem/blob/4b3ffcb406d8edee9be3e6a5cd78667b564e3f4e/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L404-L415)）。
- `Form`（PDF と SVG の図版）は `q` の中で `Do` を書く（[425 行から 426 行](https://github.com/tett23/golem/blob/4b3ffcb406d8edee9be3e6a5cd78667b564e3f4e/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L425-L426)）。
- `ActualText` の `BDC` と `EMC` は、状態を保存しない（[418 行](https://github.com/tett23/golem/blob/4b3ffcb406d8edee9be3e6a5cd78667b564e3f4e/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L418)）。

golem-typeset の `Draw` は、横組みで伸縮の率が 0 でない並びだけを `ScaledGlyphRun` にする（[Draw.hs の 560 行](https://github.com/tett23/golem/blob/4b3ffcb406d8edee9be3e6a5cd78667b564e3f4e/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L560)）。
伸縮の率を渡すのは、伸縮できる箱（`bcExpandable`）だけである（[935 行](https://github.com/tett23/golem/blob/4b3ffcb406d8edee9be3e6a5cd78667b564e3f4e/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L935)）。
行末に足すハイフン（[946 行](https://github.com/tett23/golem/blob/4b3ffcb406d8edee9be3e6a5cd78667b564e3f4e/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L946)）と和文の箱は、率 0 の `GlyphRun` になる。
`Draw` は比率 100 で描くつもりでこれらのマークを作るが、書き出しは比率を書かないので、直前の `Tz` の比率で描かれる。

縦中横（[golem-driver ADR 0045](../../golem-driver/adr/0045-draw-tate-chu-yoko-horizontally-in-pdf.md)）は、比率が 1000 でなければマークを `Saved` で包む（[587 行](https://github.com/tett23/golem/blob/4b3ffcb406d8edee9be3e6a5cd78667b564e3f4e/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L587)）。
縦中横の比率は後に残らない。
縦組みの本文は `ScaledGlyphRun` を作らない（560 行の前の分岐が縦組みを先に取る）。

### PDF の仕様が定める水平の比率

ISO 32000-1:2008 の 9.3.1 節は、テキストの状態の引数をグラフィックスの状態の一部とし、テキストオブジェクトの外でも設定でき、同じ内容のストリームのテキストオブジェクトをまたいで値が残ると定める。
9.3.4 節は、水平の比率 Th の初期値を 100 と定める。
8.4.2 節の `q` と `Q` は、テキストの状態を含むグラフィックスの状態を保存し、戻す。
9.4.4 節のテキストの描画の行列は Th を含むので、`Tm` で原点を置き直しても、字形の横の大きさには Th がかかる。
8.10.1 節の Form XObject は、`Do` を呼んだ時点のグラフィックスの状態から描き始める。
各ページの内容のストリームは、初期のグラフィックスの状態から始まる。
したがって、比率はページをまたがないが、同じページでは `ScaledGlyphRun` の後のすべての字と図版の中の字に残る。

### 確かめた振る舞い

origin/main の `4b3ffcb4` の golem で、`modules/golem-driver/test/fixtures/pd/elements-of-style` の写しに Source Serif を置き、`style.toml` に次を足して PDF を作った。

```toml
[composition]
expansion = { limit = 20, step = 5 }
```

qpdf 12.4.2 の `--qdf --object-streams=disable` で内容のストリームを展開した。
`q` と `Q` の積み上げと `Tz` を追い、`Tz` を書かないテキストオブジェクトの `Tj` のうち、比率が 100 でないものを数えた。

| 数えたもの | 値 |
| --- | --- |
| ページの数 | 53 |
| `Tz` を書かないテキストオブジェクトの `Tj` が 100 でない比率で描かれるページ | 53 |
| そのような `Tj` の数 | 24890 |
| そのうち、伸縮した並びと同じ基準線の上の、`Tz` を書かない並び（行末のハイフンなど） | 318 |
| `q BT /F1 10 Tf` で始まり `Tz` を書かない `StyledGlyphRun` | 292 |

1 ページめの目次では、`4. Place a comma ...` の行を `BT /F1 10 Tf 98.5 Tz` で描いた後、次の行の `clause 10` が `BT /F1 10 Tf` だけで始まり、98.5% で描かれる。
その後の伸縮しない行、見出しの `CONTENTS`、ノンブルの `1` も 98.5% で描かれる。

比べるために、`Tz` を書かない `BT /F<n> <大きさ> Tf` の行に `100 Tz` を足し、`fix-qdf` で長さを直した PDF を作った。
二つの PDF の 1 ページめを shem v0.1.0-rc4 で 150 dpi に描き、`shem diff` で比べると、28765 画素が違った。
違う画素は、伸縮しない行、見出し、ノンブルの字の輪郭に出る。
伸縮した行と、最初の伸縮した行より前の字には出ない。
字の原点は各グリフの `Tm` で決まるので、字の位置は変わらず、字形の幅だけが 1.5% 狭い。

### 今ある PDF

`expansion` は既定で無効である。
リポジトリの `style.toml`（マニュアル、`modules/golem-driver/test/fixtures` の入力、見た目の回帰の入力）に、`expansion` を書いたものはない。
`ScaledGlyphRun` を作る入力がないので、マニュアルと見た目の回帰の参照の PDF には、この誤りは出ない。
マニュアルの「既知の問題」は、ハイフンで終わる行の間延びの対処として `expansion` を勧めている（`manual/appendices/i-known-issues.gm` の 17 行）。
勧めに従った利用者の PDF には出る。

### 選択肢

1. `ScaledGlyphRun` を `q` と `Q` で囲む。`StyledGlyphRun` が `Tr` と `w` を囲む理由（[golem-driver ADR 0004](../../golem-driver/adr/0004-pdf-emphasis-and-character-styles.md)）と同じである。並びごとに 4 バイト増える。
2. `ScaledGlyphRun` の `ET` の後に `100 Tz` を書く。並びごとに 7 バイト増える。比率が 100 でない文脈の中に置くと、戻す先を誤る。
3. すべてのグリフのマークが、比率を毎回書く。伸縮を使わない PDF のバイト列もすべて変わる。
4. 書き出しがマークをまたいで比率を覚え、変わるときだけ `Tz` を書く。バイトは最も少ないが、マークの出力が前のマークに依存し、`Saved` や `ActualText` の入れ子で状態を正しく追う処理が要る。

## 実装すること

- `Golem.Pdf.Writer.markBuilder` は、`ScaledGlyphRun` を `q BT /F<n> <大きさ> Tf <比率> Tz`、改行、各グリフの `Tm` と `Tj`、`ET Q`、改行の順に書く（選択肢の 1）。
- 比率が 1000 の `ScaledGlyphRun` も同じ形で書く。`Draw` は比率が 1000 の `ScaledGlyphRun` を作らないので、`Tz` を省く分岐は足さない。
- golem-pdf の仕様書に「ページの内容のストリーム」の節を足し、グリフのマークがテキストの状態を `q` と `Q` の外に残さないことを書く。
- `modules/golem-pdf/test/Main.hs` の「content stream: glyph positions, colour, horizontal scaling」と `modules/golem-pdf/test/ImageSpec.hs` の「the page content of a scaled run sets Tz in percent」の期待するバイト列を、`q` と `Q` を含む形に直す。

## 実装しないこと

- 行末に足すハイフンを、行の伸縮の率で描くかどうか。今の `Draw` は率 0 で描くつもりでマークを作っており、この ADR はその意図どおりに描かれるようにするだけである。
- 和文のグリフの伸縮。[golem-layout ADR 0005](../../golem-layout/adr/0005-microtypography.md) のとおり伸縮しない。
- 内容のストリームの大きさを減らすための、比率の差分の書き出し（選択肢の 4）。
- 取り込んだ PDF の図版の中の `Tz` の扱い。取り込みの側の状態の検査（`Golem.Pdf.Import`）は変えない。

## 不変条件

マークの列の内容のストリームを、`q` と `Q` の積み上げ、`BT` と `ET`、`Tz`、`Tm` と `Tj` だけを見て解釈する。
初期の比率は 100 である。
マークの「比率」は、`ScaledGlyphRun` は `scale / 10`、`StyledGlyphRun` は `rsScale / 10`、ほかのグリフのマークは 100 とする。

| 番号 | 不変条件 |
| --- | --- |
| I1 | どのマークの列でも、各グリフの `Tj` の時点の比率は、そのグリフを持つマークの比率に等しい。 |
| I2 | どのマーク m でも、m の内容のストリームを解釈し終えた時点の比率と `q` の深さは、解釈を始める前と同じである。 |
| I3 | `ScaledGlyphRun` を持たないマークの列の内容のストリームのバイト列は、この ADR の前と同じである。 |

I2 が成り立てば、`Form` の `Do` を呼ぶ時点の比率は、ページの初期の 100 に等しい。

境界の入力は次のとおりである。
「今」の欄は origin/main の `4b3ffcb4` の振る舞いである。

| マークの列 | 期待 | 今 | 不変条件 |
| --- | --- | --- | --- |
| 空の列 | 何も書かない | 同じ | I2、I3 |
| `ScaledGlyphRun 985` だけ | グリフは 98.5 | 同じ | I1、I2 |
| グリフを持たない `ScaledGlyphRun 985` の後に `GlyphRun` | `GlyphRun` のグリフは 100 | 98.5 | I1、I2 |
| `ScaledGlyphRun 985` の後に `GlyphRun` | `GlyphRun` のグリフは 100 | 98.5 | I1 |
| `ScaledGlyphRun 985` の後に `rsScale` 1000 の `StyledGlyphRun` | 100 | 98.5 | I1 |
| `ScaledGlyphRun 985` の後に `rsScale` 1050 の `StyledGlyphRun` | 105 | 同じ | I1 |
| `ScaledGlyphRun 985` の後に `RotatedGlyphRun` と `TransformedGlyphRun` | どちらも 100 | 98.5 | I1 |
| `ScaledGlyphRun 985` の後に `ScaledGlyphRun 1015` | 98.5 と 101.5 | 同じ | I1 |
| `ActualText` に包んだ `ScaledGlyphRun 985` の後に `GlyphRun` | 100 | 98.5 | I1、I2 |
| `Saved` に包んだ `ScaledGlyphRun 985` の後に `GlyphRun` | 100 | 同じ | I1、I2 |
| `Translated` の中の `ScaledGlyphRun 985` の後の、同じ `Translated` の中の `GlyphRun` | 100 | 98.5 | I1 |
| `ScaledGlyphRun 985` の後に `Form` | `Do` の時点で 100 | 98.5 | I2 |
| 別の `Tagged` の片に分かれた `ScaledGlyphRun 985` と `GlyphRun` | 100 | 98.5 | I1 |
| `ScaledGlyphRun 1000` | 100 で、後も 100 | 同じ | I1、I2 |
| `GlyphRun` だけの列 | 前と同じバイト列 | 同じ | I3 |

## テスト設計

テストを先に書き、今のコードで I1 と I2 のテストが失敗することを確かめてから実装する。
I3 のテストは今も通る。

### golem-pdf の単体のテスト

- 内容のストリームを不変条件の節のとおりに解釈し、各グリフの比率と、終わりの比率と `q` の深さを返す関数をテストに置く。`modules/golem-driver/test/TateChuYokoSpec.hs` の `glyphsOf` と同じ形であり、golem-pdf のテストに写す（パッケージの依存は足さない）。
- I1 と I2：`Golem.TestSupport.Enum` で、`GlyphRun`、比率 985 と 1000 と 1015 の `ScaledGlyphRun`、比率 1000 と 1050 の `StyledGlyphRun`、`RotatedGlyphRun`、`TransformedGlyphRun`、`Form` と、それらを包む `Saved`、`Translated`、`ActualText` から、長さ 3 までのマークの列をすべて作り、`contentStream` の出力で I1 と I2 を確かめる。グリフは各マークに 0 個か 1 個とする。テストの名前に I1 と I2 を入れる。
- 境界の表の各行を、名前に不変条件の番号を入れた個別のテストにする。
- I3：`ScaledGlyphRun` を持たない境界の表の列で、`contentStream` のバイト列が今の期待（既存のテストの文字列）と同じであることを確かめる。
- `ScaledGlyphRun` のバイト列のテストは、`q BT /F1 10 Tf 98.5 Tz` で始まり `ET Q` で終わる形を期待する。

### golem-driver のテスト

- `expansion = { limit = 20, step = 5 }` を書いた小さな横組みの本を、テストの中で組む。段落は、伸縮する行の後に伸縮しない最後の行を持ち、行末のハイフンと和文の字を含める。
- 出力の PDF の各ページの内容のストリームを `glyphsOf` で読み、伸縮する行の後の最後の行、ハイフン、和文の字、ノンブルの字の比率が 1000（千分率）であることを確かめる（I1）。今のコードでは 1000 にならず、失敗する。

### 見た目の確かめ

- 見た目の回帰の入力は `expansion` を使わないので、参照の画像が変わらないことを `scripts/visual/check.sh` で確かめる（I3）。
- 文脈の節の再現の手順で PDF を作り、直した golem の 1 ページめを shem で描く。手で `100 Tz` を足した PDF の描画と画素が一致することを `shem diff` で確かめる。結果は実装のプルリクエストに書く。

## トレードオフ

`q` と `Q` で囲むと、伸縮した並びごとに 4 バイト増える。
再現の本では `ScaledGlyphRun` が 11198 個あり、展開した内容のストリームが約 44 KB 増える。
Flate で圧縮するので、ファイルの増え方はこれより小さい。
選択肢の 4 はこの増加を避けられるが、各マークの出力が前のマークに依存し、`Saved` と `ActualText` と `Tagged` の片をまたいで状態を追う処理が書き出しに入る。
マークごとに状態を閉じる今の設計（`StyledGlyphRun`、`Saved`、`Translated`、`Turned`、`Form`）から外れるので、採らない。

選択肢の 2 は、比率を 100 に決め打ちで戻す。
`ScaledGlyphRun` を比率が 100 でない文脈（たとえば `rsScale` の `Tz` の後）に置くと、戻した後の値が文脈と違う。
今の `Draw` はそのような列を作らないが、`q` と `Q` は文脈を問わずに戻すので、こちらを選ぶ。

`expansion` を使わない PDF は、バイト列が変わらない（I3）。
決定性の検査と見た目の参照に影響しない。

## メンテナーが決めること

1. **直し方**：推奨は、選択肢の 1（`q` と `Q` で囲む）である。
   - 退けた案の一つは、選択肢の 2（`100 Tz` を書く）である。バイトが多く、文脈の比率を戻せない。
   - 二つめは、選択肢の 3（すべてのグリフのマークが比率を書く）である。伸縮を使わない PDF のバイト列がすべて変わり、I3 を失う。
   - 三つめは、選択肢の 4（差分の書き出し）である。トレードオフの節のとおり、マークの出力が前のマークに依存する。
2. **ハイフンの比率**：推奨は、この ADR では行末のハイフンを今の `Draw` の意図どおり 100 で描き、伸縮の率で描くかは別の ADR で決めることである。直した後、ハイフンの字形は伸縮した行の字より最大 2% 広い、または狭い。
   - 退けた案は、この ADR でハイフンに行の率を渡すことである。行分割がハイフンの幅を伸縮できる箱として数えるかを確かめる必要があり、書き出しの誤りの修正と範囲が違う。
3. **既知の問題への記載**：推奨は、実装と同じプルリクエストで直し、マニュアルの「既知の問題」には書かないことである。`expansion` を勧めている既知の問題の項目は、そのまま残す。
   - 退けた案は、実装までのあいだ「既知の問題」に書くことである。実装は小さく、記載と削除の二度の変更になる。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-08、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- ISO 32000-1:2008, Document management, Portable document format, Part 1: PDF 1.7. 8.4.1 節（グラフィックスの状態）、8.4.2 節（グラフィックスの状態の積み上げ）、8.10.1 節（Form XObject）、9.3.1 節（テキストの状態の引数）、9.3.4 節（水平の比率）、9.4.4 節（テキストの空間の詳細）。
- [golem-layout ADR 0005](../../golem-layout/adr/0005-microtypography.md)
- [golem-driver ADR 0004](../../golem-driver/adr/0004-pdf-emphasis-and-character-styles.md)
- [golem-driver ADR 0045](../../golem-driver/adr/0045-draw-tate-chu-yoko-horizontally-in-pdf.md)
- [docs/adr/0051](../../adr/0051-reuse-repeated-pdf-content-streams.md)（内容のストリームの外に状態を漏らさない条件）
- [docs/adr/0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md)（不変条件と小さな入力の網羅）
