# ADR 0431: PDF/X-4 を宣言しない、画面で読むための PDF 1.7 のターゲットを足す

Status: superseded-pending [{"part":"実装することの書き方の色の項のうち図版の色の明示的な置換、不変条件の I4（スウォッチで塗る文字、罫線、背景に狭める）、境界の表の [figures] の color の行、受けいれ条件の A1 の色の比べ方","by":["docs/adr/0445-keep-the-cmyk-recoloring-of-pdf-figures-in-pdf-screen.md"],"kind":"replace"}]

## 文脈

Golem の PDF は、入稿のための PDF である。
`[color]` の `intent` があれば PDF/X-4 の出力インテントを書き、無くても版 1.6 で書き、仕上がりの寸法（TrimBox）と塗り足し（BleedBox）を持つ。
色はスウォッチを DeviceCMYK で書く。

一方、同じ本を画面で読むための PDF（電子配布、校正の回覧、ウェブでの公開）も要る。
画面で読む PDF には、塗り足しもトンボも要らず、色は画面の色（sRGB）がよく、ページの中のリンクが押せるほうがよい。
今の Golem では、入稿の PDF と画面の PDF を一度のビルドで両方作れない。
`intent` を外せばリンクの注釈は付くが、塗り足しと CMYK の色は残り、入稿の PDF が作れなくなる。

この ADR は、入稿の PDF とは別に、PDF/X-4 の制約を持たない PDF 1.7 のターゲットを足す。

## 調査した事項

origin/main（[9efdc4f89](https://github.com/tett23/golem/commit/9efdc4f89b3fec75abcd37c11abb3e1d909c6725)）で、次のことを確かめた。

- PDF の版は `PdfObjects "1.6"` に固定している（[Writer.hs#L766](https://github.com/tett23/golem/blob/9efdc4f89b3fec75abcd37c11abb3e1d909c6725/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L766)）。
  TrimBox と BleedBox は、`intent` の有無によらずいつも書く（[Writer.hs#L738-L739](https://github.com/tett23/golem/blob/9efdc4f89b3fec75abcd37c11abb3e1d909c6725/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L738-L739)）。
- `intent` があるときだけ、OutputIntents、XMP の `pdfxid:GTS_PDFXVersion`、文書情報の `GTS_PDFXVersion` と `Trapped` を書く（仕様書の「PDF/X-4 と出力インテント」の節）。
- PDF/X-4 を宣言する PDF は、ページのリンクの注釈を書かず、構造の Link を Span にする（[root ADR 0350](0350-omit-page-link-annotations-from-pdf-x-4.md)、[Writer.hs#L614-L625](https://github.com/tett23/golem/blob/9efdc4f89b3fec75abcd37c11abb3e1d909c6725/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L614-L625)）。
  使い手のマニュアルは、電子配布でリンクを押せるようにするには `intent` を省いて組むと書いている（[03-markup.gm#L912-L914](https://github.com/tett23/golem/blob/9efdc4f89b3fec75abcd37c11abb3e1d909c6725/manual/chapters/03-markup.gm#L912-L914)）。
- `Golem.Pdf.X4.verify` は、版が 1.6 以下であることを確かめる（[X4.hs#L259](https://github.com/tett23/golem/blob/9efdc4f89b3fec75abcd37c11abb3e1d909c6725/modules/golem-pdf/src/Golem/Pdf/X4.hs#L259)）。
- すべての PDF はタグ付きで、`/Lang` と `DisplayDocTitle` を持ち、しおりを持つ（[root ADR 0183](0183-tagged-pdf-and-pdf-a.md)）。
  `[targets.pdf]` の `pdfa = "2a"` は `intent` を要し、`pdfua = "1"` は `intent` を要らない。
  0183 は、PDF 2.0 を基礎とする PDF/A-4 と PDF/UA-2 を採らず、`intent` の無い PDF/A も作らないと決めている。
  PDF/UA-1（ISO 14289-1）は、ISO 32000-1（PDF 1.7）を基礎とする。
- 文書 ID は、マニフェストの `id` から名前ベースの UUID（v5）で作り、同じ文書の版をまたいで変わらない値とする（仕様書の「識別子」の節）。
  インスタンス ID は、入力全体（ソース、マニフェスト、`style.toml`、フォント、出力を変える CLI のオプション、Golem のバージョンなど）のハッシュから作る。
  仕様書の「PDF/A と PDF/UA の宣言」の節は、文書 ID とインスタンス ID を入力全体のハッシュから作ると書いており、「識別子」の節と食い違っている。
- PDF に固有の検査（レイアウトの diagnostic、フォントの欠けの G08002、出力インテントの ICC プロファイルの欠けの G08006、トンボの diagnostic など）は、選んだターゲットに `TargetPdf` があるかで動かすかを決める（[Driver.hs#L965-L1002](https://github.com/tett23/golem/blob/9efdc4f89b3fec75abcd37c11abb3e1d909c6725/modules/golem-driver/src/Golem/Driver.hs#L965-L1002)、[Driver.hs#L1188-L1191](https://github.com/tett23/golem/blob/9efdc4f89b3fec75abcd37c11abb3e1d909c6725/modules/golem-driver/src/Golem/Driver.hs#L1188-L1191)）。
- MediaBox、TrimBox、BleedBox は別の値で、TrimBox は塗り足しとトンボの分だけ原点からずれる（[Writer.hs#L737-L739](https://github.com/tett23/golem/blob/9efdc4f89b3fec75abcd37c11abb3e1d909c6725/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L737-L739)）。
  リンクの注釈の `/Rect` と文書内の行き先（`/Dest`）は、ページの座標で書く。
  行をまたぐリンクは、行ごとの矩形に分かれ、矩形ごとに一つの注釈になる（仕様書のリンクの注釈の節）。
- マニフェストに `[targets.*]` が一つも無いと G03001 になる（[Manifest.hs#L1010-L1012](https://github.com/tett23/golem/blob/9efdc4f89b3fec75abcd37c11abb3e1d909c6725/modules/golem-project/src/Golem/Project/Manifest.hs#L1010-L1012)）。
- 色は名前で指定し、出力インテント（Japan Color 2001 Coated）に束縛する。
  スウォッチの文字と罫線と背景は DeviceCMYK で書き、色を指定しない文字は色を設定せずに描く（仕様書の文字の色の節）。
  換算は CMYK から RGB の向きだけで、HTML と EPUB は、golem-html の `cmykToRgb` でスウォッチを 0 から 255 の整数の sRGB にする（[Html.hs#L330](https://github.com/tett23/golem/blob/9efdc4f89b3fec75abcd37c11abb3e1d909c6725/modules/golem-html/src/Golem/Html.hs#L330)）。
  golem-pdf は golem-html に依存しない。
- RGB の画像は CMYK にせず、プロファイルの無い RGB には sRGB を付ける。
  図版の色の明示的な置換（`[figures]` の `color`）は、スウォッチの CMYK で塗る（[root ADR 0408](0408-preserve-rgb-and-distinguish-explicit-figure-recoloring.md)）。
- 特色の色空間は、トンボのレジストレーションの色（Separation の `All`）だけに使う（[golem-pdf ADR 0007](../golem-pdf/adr/0007-registration-crop-marks.md)）。
- ターゲットは `data Target = TargetHtml | TargetEpub | TargetText | TargetPdf` の四つで（[Driver.hs#L132-L137](https://github.com/tett23/golem/blob/9efdc4f89b3fec75abcd37c11abb3e1d909c6725/modules/golem-driver/src/Golem/Driver.hs#L132-L137)）、`--target` を省くと `allTargets` の四つをすべて作り、マニフェストの `[targets.*]` を見ない（[golem-cli ADR 0002](../golem-cli/adr/0002-build-all-targets-by-default.md)）。
  `--target` は何度でも書け、値は `html|epub|text|pdf` である（[Main.hs#L137-L141](https://github.com/tett23/golem/blob/9efdc4f89b3fec75abcd37c11abb3e1d909c6725/modules/golem-cli/app/Main.hs#L137-L141)）。
- 出力は、ターゲットごとのフォルダ（`build/pdf` など）に、前の出力を消してから書く（[root ADR 0429](0429-clear-the-target-output-before-writing.md)）。
  prod のビルドでエラーのために PDF を書けなければ、前の `build/pdf` を片付ける（[root ADR 0326](0326-discard-stale-pdf-after-build-errors.md)）。
  `build/pdf` には PDF のほかに `pages.json` を書き、エディタが改ページの位置の印に使う（[root ADR 0195](0195-page-start-positions-of-pdf.md)）。
- `[targets.pdf]` の未知のキーは、`manifest.toml` の誤りの G03001 である。
- [root ADR 0327](0327-screen-preflight-and-template.md) の `screen` は、プリフライトの検査の選び方と `golem new` の雛形を変えるが、PDF の書き方は変えない。

確かめていないことは次のとおりである。

- PDF/X-4（ISO 15930-7）が、ヘッダーの版を 1.6 以下と厳密に求めるか。
- Golem が書く PDF に、PDF 1.7 の機能が要るものがあるか。

指示者は 2026-11-23 に、この項目の ADR を書くよう求めた。

## 実装すること

### ターゲット

五つめのターゲット `pdf-screen` を足す。
出力のフォルダは `build/pdf-screen` とし、`pdf` と同じ名前の PDF を一つ書く。
`pages.json` は書かない。
ページの割り付けは `pdf` と同じなので、エディタは今までどおり `build/pdf/pages.json` を読めば足りる。

`pdf-screen` は、`--target pdf-screen` で選んだときだけ作る。
`--target` は今までどおり何度でも書け、`--target pdf --target pdf-screen` で両方を作る。
`--target` の値の一覧（メタ変数と補完）に `pdf-screen` を足す。

`--target` を省いたときは、今までどおり `allTargets` の四つを作り、`pdf-screen` を作らない。
入稿の PDF だけが要る本で、ビルドの時間を増やさないためである。
マニフェストの `[targets.pdf-screen]` は設定の表で、書いても既定のターゲットを変えない。
[golem-cli ADR 0002](../golem-cli/adr/0002-build-all-targets-by-default.md) の「マニフェストの `[targets.*]` の有無は見ない」をそのまま保つためである。

`build/pdf-screen` は、ほかのターゲットと同じく、書く前に消す（0429）。
prod のビルドでエラーのために `pdf-screen` の PDF を書けなければ、前の `build/pdf-screen` を片付ける（0326 と同じ）。

### 書き方

`pdf-screen` は、組版の結果（ページの割り付け、行、図版の位置）を `pdf` と同じにし、書き出し方だけを次のように変える。

- 版: ヘッダーを `%PDF-1.7` にする。
  1.7 にするのは、PDF/UA-1 が基礎とする版だからである。
  1.7 の機能を新たに使うことはしない。
- 出力インテント: `intent` があっても、OutputIntents、`GTS_PDFXVersion`、`Trapped` を書かない。
  PDF/X-4 を宣言しない。
- ページの寸法: MediaBox を、`pdf` の TrimBox と同じ大きさで、原点 (0, 0) を左下に置いた箱にする。
  BleedBox と TrimBox は書かず、塗り足しの領域とトンボは描かない。
  塗り足しの領域に伸びた図版や背景は、仕上がりの寸法で切れる。
  トンボを描かないので、Separation の `All` の色空間も書かない。
- リンク: ページのリンクの注釈と文書内の行き先を書き、構造の Link を Link のまま書く。
  `intent` の無い今の PDF と同じ振る舞いである（0350）。
- 色: スウォッチで塗る文字、罫線、背景、図版の色の明示的な置換を、HTML と EPUB と同じ `cmykToRgb` の sRGB にし、sRGB の ICCBased の色空間で書く。
  各成分は、`cmykToRgb` の 0 から 255 の整数を 255 で割った値を、`pdf` が数を書くときと同じ桁で書く。
  色を指定しない文字は、今と同じく色を設定せずに描く。
  画像の元の色は `pdf` と同じに扱う（RGB は sRGB の ICCBased、CMYK の画像はそのまま）。
- 透明: 透明の扱い（不透明度と描画モード）は `pdf` と変えない。
- タグ、言語、しおり: `pdf` と同じく、タグ付きにし、`/Lang` と `DisplayDocTitle` としおりを書く。
- 文書 ID: `pdf` と同じく、マニフェストの `id` から作る。
  同じ本の別の表し方なので、文書 ID は変えない。
- インスタンス ID: 入力全体に、ターゲットの名前 `pdf-screen` を足したもののハッシュから作る。
  同じ本の `pdf` と `pdf-screen` は別のファイルなので、別のインスタンス ID を持たせる。
- 座標: 内容のストリーム、リンクの注釈の `/Rect`、文書内の行き先の座標を、`pdf` の TrimBox の左下を原点とする座標に移す。
- XMP: `pdfua` を宣言したときだけ書き、内容は `intent` の無い今の PDF と同じとする。

`cmykToRgb` は、golem-pdf に写す。
golem-pdf に golem-html の依存を足さないためである。
写した関数と元の関数が同じ値を返すことは、I4 のテストで確かめる。

### 組版と検査

`pdf-screen` は、組版を `pdf` と共有する。
`pdf` と `pdf-screen` の両方を選んだときも、組版は一度だけ行い、その diagnostic は一度だけ出す。
PDF に固有の検査は、次のように扱う。

| 検査 | `pdf-screen` だけを選んだとき |
| --- | --- |
| レイアウトの diagnostic（傍注、柱の変数、注の番号など） | `pdf` と同じに出す |
| 本文のフォントの欠け（G08002） | `pdf` と同じに出し、PDF を書かない |
| 出力インテントの ICC プロファイルの欠け（G08006） | 出さない（出力インテントを使わない） |
| トンボの diagnostic（`--marks`） | 出さない（トンボを描かない） |

`pdf` と `pdf-screen` の両方を選んだときは、`pdf` の検査をそのまま行い、G08006 とトンボの diagnostic は `pdf` だけを止める。

### `[targets.pdf-screen]`

`[targets.pdf-screen]` は、ターゲットの表として、`[targets.*]` が一つも無いときの G03001 の検査で数える。
`[targets.pdf-screen]` に書けるキーは `pdfua` だけとし、値は `[targets.pdf]` と同じく `"1"` だけを受け付ける。
`pdfua = "1"` を書けば、PDF/UA-1 を宣言する。
`pdfa` を含むほかのキーは、未知のキーとして G03001 にする。
`intent` の無い PDF/A を作らないという 0183 の決定に合わせるためで、新しいコードは足さない。

### プリフライトと検証

`golem preflight` は、今までどおり `pdf` の PDF を検査し、`pdf-screen` を検査しない。
CI の `verapdf` ジョブに、`pdf-screen` で `pdfua = "1"` を書いた PDF を PDF/UA-1 の検証にかける手順を足す。
決定性の検査に、`pdf-screen` の PDF のハッシュを足す。

### 文書

仕様書に `pdf-screen` の節を足し、`pdf` との違いを表にする。
仕様書の「PDF の版（1.6）」と書く二箇所（「PDF/X-4 と出力インテント」の節と「PDF/A と PDF/UA の宣言」の節）を、`pdf` のターゲットの版と読めるように直す。
「PDF/A と PDF/UA の宣言」の節の、文書 ID を入力全体のハッシュから作るという記述を、「識別子」の節に合わせて直し、「識別子」の節に `pdf-screen` のインスタンス ID を書く。
README のターゲットの一覧に `pdf-screen` を足す。
使い手のマニュアルの、電子配布でリンクを押せるようにするには `intent` を省くという段落（03-markup.gm の 912 行目から）を、`pdf-screen` を使う書き方に直す。
マニュアルの出力の章に、入稿の PDF と画面の PDF の使い分けを書く。
ロードマップの「プレーンな PDF 1.7 のターゲット」の項目を消す。

### ステータスの行

採択したら、[golem-cli ADR 0002](../golem-cli/adr/0002-build-all-targets-by-default.md) のステータスに、`pdf-screen` は既定のターゲットに入らないことを、この ADR が補ったと記録する。

```text
superseded [{"part":"既定のターゲット","by":["docs/adr/0431-plain-pdf-1-7-target.md"],"kind":"supplement"}]
```

## 実装しないこと

`pdf` の書き方は変えない。
PDF 2.0、PDF/A-4、PDF/UA-2 を書かない。
`pdf-screen` で PDF/A を宣言しない。
ページの表示の設定（見開き、開いたときの倍率）は、この ADR では足さない。
画面に合わせた組み直し（リフローや画面の大きさの判型）はしない。
`--target` を省いたときのターゲットに `pdf-screen` を入れない。
`--target all` のような値は足さない。

## 不変条件

- I1: `pdf-screen` の PDF のヘッダーは `%PDF-1.7` で、OutputIntents と `GTS_PDFXVersion` を持たない。
- I2: `pdf-screen` の各ページの MediaBox は、原点が (0, 0) で、幅と高さが、同じビルドの `pdf` のそのページの TrimBox の幅と高さに等しく、ページは BleedBox と TrimBox を持たない。
- I3: `pdf-screen` の PDF のリンクの注釈の列は、同じ入力を `intent` なしで組んだ `pdf` の注釈の列と、数と行き先が等しく、各注釈の `/Rect` は、その `pdf` の対応する `/Rect` から TrimBox の左下を引いたものに等しい。
- I4: `pdf-screen` の PDF に書いたスウォッチの色の各成分は、golem-html の `cmykToRgb` が同じスウォッチに返す整数を 255 で割った値を、`pdf` の数の桁で書いたものと等しい。
- I5: `pdf-screen` のページの数と、各ページから抜き出した文字の並びは、同じビルドの `pdf` と等しい。
- I6: `--target` を省いたビルドは、`[targets.pdf-screen]` の有無によらず、`build/pdf-screen` を作らない。
- I7: 同じ入力からの `pdf-screen` の PDF は、バイト列まで等しい。
- I8: `[targets.pdf-screen]` の `pdfua` でないキーと、`"1"` でない `pdfua` の値は G03001 になり、`pdf-screen` の PDF を書かない。
- I9: 同じビルドの `pdf` と `pdf-screen` の文書 ID は等しく、インスタンス ID は異なる。
- I10: `pdf-screen` の PDF は、Separation の色空間を持たない。
- I11: `pdfua = "1"` の `pdf-screen` の PDF は、XMP に `pdfuaid:part` を 1 として持つ。
- I12: `pdf-screen` だけを選んだビルドは、`intent` の ICC プロファイルが無くても、G08006 を出さずに PDF を書く。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| `intent` のある本を `--target pdf --target pdf-screen` で組む | `pdf` は PDF/X-4、`pdf-screen` は 1.7 で出力インテントなし、ページと文字が同じ | I1, I5 |
| `intent` の無い本を `--target pdf-screen` で組む | 1.7、出力インテントなし | I1 |
| 1 ページだけの本 | MediaBox が TrimBox と同じ大きさ | I2 |
| 塗り足しまで伸びた背景のある本 | `pdf-screen` では仕上がりの寸法で切れる | I2 |
| トンボを付けた本 | `pdf-screen` にトンボと Separation が無い | I2, I10 |
| リンクの無い本 | リンクの注釈が無い | I3 |
| 文書内リンクと URI のリンクを持つ本 | `pdf-screen` にそれぞれの注釈がある | I3 |
| 行をまたぐリンク | 行ごとの注釈が `intent` なしの `pdf` と同じ数ある | I3 |
| スウォッチ `accent` を文字、罫線、背景に使う本 | 色が `cmykToRgb` の値と等しい | I4 |
| `[figures]` の `color` で図版の色を置き換えた本 | 置き換えた色が `cmykToRgb` の値と等しい | I4 |
| CMYK が (0, 0, 0, 0) と (100, 100, 100, 100) のスウォッチ | 両端の値が `cmykToRgb` と等しい | I4 |
| `--target` を省き、`[targets.pdf-screen]` が無い | `build/pdf-screen` が無い | I6 |
| `--target` を省き、`[targets.pdf-screen]` がある | `build/pdf-screen` が無い | I6 |
| 同じ入力で二回組む | 同じバイト列 | I7 |
| `[targets.pdf-screen] pdfua = "1"` | PDF/UA-1 の宣言があり、veraPDF の ua1 を通る | I11 |
| `[targets.pdf-screen]` だけのマニフェスト | G03001 にならない | I8 |
| `intent` のファイルが無い本を `--target pdf-screen` で組む | G08006 が無く、PDF がある | I12 |
| フォントの無い本を `--target pdf-screen` で組む | G08002 で、PDF が無い | I12 |
| `[targets.pdf-screen] pdfa = "2a"` | G03001 で、PDF を書かない | I8 |
| `[targets.pdf-screen] pdfua = "2"` | G03001 で、PDF を書かない | I8 |
| 同じビルドの `pdf` と `pdf-screen` | 文書 ID が等しく、インスタンス ID が異なる | I9 |

## 受けいれ条件

A1: マニュアルを `pdf-screen` で組み、Acrobat Reader と macOS のプレビューで、リンクが押せること、色が HTML の出力と同じに見えること、塗り足しとトンボが無いことを、手で確かめる。

## テスト設計

root ADR 0431 I1 から I12 を名前の先頭に置いたテストを、golem-driver と golem-pdf に足す。
I1、I2、I3、I9、I10、I11 は、組んだ PDF を `Golem.Pdf` の読み取りで開き、ヘッダー、MediaBox、BleedBox、TrimBox、OutputIntents、注釈、`/ID`、色空間、XMP を調べる。
I12 は、境界の表のプロジェクトを `--target pdf-screen` だけで組み、diagnostic と出力を調べる。
I4 は、golem-driver のテストで、golem-pdf に写した関数と golem-html の `cmykToRgb` を、境界の表のスウォッチを含む CMYK の値の列挙で比べ、組んだ PDF の内容のストリームの色の値も比べる。
I5 は、`pdf` と `pdf-screen` のページの数と、ページごとの抜き出した文字を比べる。
I6 は、`--target` を省いたビルドの出力のフォルダの一覧を調べる。
I7 は、決定性の検査のハッシュで確かめる。
I8 は、golem-project のマニフェストの読み取りのテストで確かめる。
各テストは、実装の前に落ちることを確かめる。
root ADR 0431 A1 は、手で確かめ、結果を実装のプルリクエストに書く。

## トレードオフ

組版の結果を `pdf` と同じにするので、`pdf-screen` は入稿の PDF と同じページ割りになる。
画面に合わせて組み直すことはできないが、校正で見るページと配布するページが一致する。

ターゲットを一つ増やすので、ターゲットを並べるところ（CLI、マニフェストの補完、決定性の検査、マニュアル）がすべて変わる。
その代わりに、一度のビルドで入稿と画面の両方の PDF を作れる。

既定のビルドに入れないので、画面の PDF が要る本は、`--target pdf-screen` を明示する必要がある。
マニフェストで既定を変えられるようにすると、[golem-cli ADR 0002](../golem-cli/adr/0002-build-all-targets-by-default.md) の「出力をマニフェストを読まずに言い当てられる」が崩れるので、採らない。

`cmykToRgb` を golem-pdf に写すので、二つの写しがずれうる。
I4 のテストで、ずれを検出する。

## 参考文献

- [root ADR 0183](0183-tagged-pdf-and-pdf-a.md)
- [root ADR 0195](0195-page-start-positions-of-pdf.md)
- [root ADR 0326](0326-discard-stale-pdf-after-build-errors.md)
- [root ADR 0327](0327-screen-preflight-and-template.md)
- [root ADR 0350](0350-omit-page-link-annotations-from-pdf-x-4.md)
- [root ADR 0408](0408-preserve-rgb-and-distinguish-explicit-figure-recoloring.md)
- [root ADR 0429](0429-clear-the-target-output-before-writing.md)
- [golem-cli ADR 0002](../golem-cli/adr/0002-build-all-targets-by-default.md)
- [golem-pdf ADR 0002](../golem-pdf/adr/0002-pdf-x-4.md)
- [golem-pdf ADR 0007](../golem-pdf/adr/0007-registration-crop-marks.md)
- ISO 32000-1:2008（PDF 1.7）、ISO 14289-1（PDF/UA-1）
