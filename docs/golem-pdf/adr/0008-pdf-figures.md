# ADR 0008: PDF の図版と置けない図版の診断

ステータス: 採択→図版の形式の SVG は [ADR 0009](0009-svg-figures.md)

## 文脈

仕様書の[「図版」の節](../../specifications.md#図版)は、図版の形式を PDF（ベクター）、PNG、JPEG と定め、PDF の図版には Web 用の代替画像（`web=`）を必須とする。
利用者のマニュアル（`manual/chapters/03-markup.gm`）も、PDF の図版を使えると書いている。
ところが、PDF の出力は PNG と JPEG しか置けない。
ロードマップの v1.0.0 には、この食い違いが三つの項目に分かれて載っている（「PDF」の節の「図版の欠落の扱い」と「PDF の図版」、「CLI と LSP」の節の「PDF に置けない図版」）。
三つは同じ処理（`@figure` の画像を PDF に置く処理）の別の面なので、この ADR でまとめて決める。

### 今の振る舞い

コードを読むと、図版は次の順に扱われる。

- 評価（golem-eval の `Golem.Eval.File` の `figure`）は、画像と `web` のファイルがあるかだけを確かめる。ないファイルは G0233、使えないパスは G0260 になる。拡張子が `.pdf` で `web` がなければ G0229 になる。形式は拡張子の `.pdf` だけで見分け、ほかの拡張子（`.svg`、`.gif` など）はそのまま通る。
- PDF の書き手（golem-driver の `Golem.Driver.Pdf` の `loadFigures`）は、golem-pdf の `Golem.Pdf.Image.readImage` で画像を読む。`readImage` は先頭のバイト列で JPEG と PNG を見分け、それ以外を `Left` にする。`loadFigures` は `Left` を `Nothing` にし、`figureOf` はその図版の配置を作らない。
- `golem preflight` だけが、同じ図版を G0905 で報告する（[golem-cli ADR 0006](../../golem-cli/adr/0006-preflight.md)）。同じ ADR は、`golem build` で黙って落とすことを直すかどうかを別の ADR に回した。

### 実験で確かめた振る舞い

`golem new` の雛形に四つの図版（正しい PNG、`web=` 付きの PDF、200 バイトで切った PNG、SVG）を置き、`main` の `e3e19da` と同じモジュールのバイナリで組んだ。

- `golem build --target pdf` は、診断を一つも出さずに終了コード 0 で終わった。PDF に入った画像の XObject は二つ（正しい PNG と、そのアルファの SMask）だけで、残りの三つの図版は、キャプションと図番号ごと PDF から消えた。
- `golem preflight` は、三つの図版をそれぞれ G0905 で報告した（「JPEG と PNG 以外の画像は使えません」が二つ、「PNG のチャンクが途中で切れています」が一つ）。
- `golem build --target html` と `--target epub` は四つとも `<img>` で置き、ファイルをそのまま写した。EPUB は SVG の `media-type` を `application/octet-stream` にした（golem-epub の `mediaType` が `.svg` を知らないため）。

ロードマップの「図版の欠落の扱い」が「可能性がある」と書いていた振る舞いは、実際に起きている。
図版が消えても図番号は振り直されないので、「図 1-2」への参照が、PDF のどこにもない図を指したまま組まれる。

### PDF の図版の置き方

InDesign は、PDF を置くときにページと切り抜きの枠（バウンディングボックス、アート、トリミング、裁ち落とし、仕上がり、メディア）を選ばせる。
pdfTeX の `\includegraphics` は、PDF のページを Form XObject として取り込み、既定では CropBox で切り抜く。
Golem でも、PDF のページを Form XObject として取り込み、その内容をそのまま描くのが素直である。
ラスタに変換すると、ベクターで置くという図版の目的が失われる。

取り込みには、PDF を読む処理が要る。
golem-pdf は PDF を書くが、読む処理を持たない。
Hackage には PDF を読むライブラリ（pdf-toolbox など）があるが、必要なのは相互参照、オブジェクト、ストリームの復号の一部である。
CLAUDE.md の方針（ライセンスに問題がなく再実装が容易なら依存に入れず再実装する）とメンテナーの決定に従い、必要な範囲だけを Haskell で golem-pdf の中に書く。
Flate の復号には、すでに依存に入っている zlib を使う。
相互参照のストリームが使う PNG の予測子は、`Golem.Pdf.Image.unfilterPng` がすでに実装している。

取り込んだページは、PDF/X-4 の出力（[ADR 0002](0002-pdf-x-4.md)）の中に入る。
外から来た内容は、Golem が自分で書く内容と違い、色空間、フォント、フィルターを Golem が選べない。

- **色**：仕様書の[「色」の節](../../specifications.md#色)は、写真などの画像を例外とし、色を変換せずに ICC プロファイルを付けて埋め込み、プロファイルのない RGB の画像には sRGB のプロファイルを付けると定める。PDF の図版の DeviceRGB も、同じ考え方で sRGB の ICCBased に置き換えられる。DeviceRGB のまま入れると、`Golem.Pdf.X4.verify` の「ICC プロファイルのない RGB」に当たり、PDF/X-4 の出力インテントが CMYK の本では要件を満たさない。
- **特色**：[ADR 0002](0002-pdf-x-4.md) は特色（Separation と DeviceN）を扱わないと決め、PDF の色はトンボのレジストレーションの色を除いてプロセスカラーだけである（[ADR 0007](0007-registration-crop-marks.md)）。
- **フォント**：PDF/X-4 はすべてのフォントの埋め込みを求める。埋め込んでいないフォント（標準の 14 書体を含む）を使う図版は、そのまま入れられない。
- **透明**：PDF/X-4 は透明を許す。PNG のアルファを SMask で入れているので、今の PDF もすでに透明を含みうる。
- **版**：PDF/X-4 の PDF の版は 1.6 である。取り込む PDF の版が 1.7 や 2.0 でも、取り込む要素が 1.6 の範囲にあればよい。

### メンテナーが決めたこと

案の段階で残していた問いに、メンテナーが次のとおり答えた。

- `page=` は v1 に入れ、この ADR で扱う。意味論の IR の `Figure` に欄が一つ増える（下の「データ構造」）。
- G0905 を廃止した後、`preflight.toml` の `image-unplaceable` のキーは知らないキー（G0901）とする。v1 の前なので、読んで無視する移行の期間は設けない。雛形の `preflight.toml` はこのキーをコメントの中にも書いていないが、利用者のマニュアルの付録（`manual/appendices/d-preflight.gm`）はキーとして載せているので、そこから消す。
- DeviceRGB を sRGB の ICCBased に置き換える方法は、内容のストリームの書き換えとする（理由は「トレードオフ」）。
- PDF を読む処理は Haskell で golem-pdf の中に再実装する。Rust のライブラリも、新しい組み込みの依存（C のライブラリや Hackage の PDF のライブラリ）も入れない。組み込みの依存を足すことは、ビルドと決定性の管理の負担が大きいためである。
- 新しい診断のコード（G0273、G0274、G0275、G0810）が、並行して書かれているほかの ADR のコードと重なった場合は、実装する者がそれを報告し、重ならない順に実装する。この ADR を書いた時点では、G0270 から G0272 を [docs/adr/0030](../../adr/0030-manual-page-break-control.md) の案が、G0276 を [docs/adr/0033](../../adr/0033-colophon-contributors-and-printings.md) の案が使い、08 の区分のコードを使うほかの案はない。

## 実装すること

### 図版の形式（golem-eval）

評価の段階で、図版と `web` の形式を拡張子で決める。
形式は、どの出力でも同じ規則で決まるようにし、PDF だけを組むときにしか見つからない誤りを減らす。

| 引数 | 受け付ける拡張子（大文字と小文字を区別しない） | 誤りのコード |
| --- | --- | --- |
| 画像（最初の位置引数） | `.pdf`、`.png`、`.jpg`、`.jpeg` | G0274 |
| `web` | `.png`、`.jpg`、`.jpeg` | G0273 |

- G0274 のメッセージは `図版の形式は PDF、PNG、JPEG です: <パス>`、G0273 のメッセージは `web の代替画像は PNG か JPEG です: <パス>` とする。
- `web` は、PNG と JPEG の図版にも書ける。今と同じく、HTML と EPUB は `web` があればそれを、なければ図版のファイルを使う。PDF は常に図版のファイルを使う。
- PDF の図版に `web` がなければ、今と同じく G0229 とする。
- 拡張子と中身が食い違うファイル（中身が PDF の `.png` など）は、PDF の書き手が拡張子の形式として読んで失敗し、G0810 になる。中身で形式を決め直さない。

### ページの指定（golem-eval、golem-doc）

`@figure` に `page=` を加える。

```
@figure images/figures.pdf page=3 web=images/fig3.png alt="三つめの図"
```

- `page` は 1 以上の整数で、PDF の何ページ目を置くかを表す。省けば 1 である。
- 整数として読めない値、0 以下の値、PDF でない図版に書いた `page` は G0275（`page は PDF の図版のページを 1 から数えた整数で書きます: <値>`）とする。
- ページの数を超える値は、評価の段階ではファイルを読まないので、PDF の書き手が G0810 にする。

### PDF の読み込み（golem-pdf の `Golem.Pdf.Import`）

PDF のバイト列とページの番号から、そのページを Form XObject として書ける形に読む純粋な関数を作る。

```haskell
importPage :: Int -> ByteString -> Either ImportError ImportedPage
```

読む範囲は次のとおりとする。

- **ヘッダー**：`%PDF-1.0` から `%PDF-1.7` と `%PDF-2.0` を受け付ける。版の数字そのものでは拒まず、取り込む要素で判断する。
- **相互参照**：ファイルの末尾の `startxref` から、相互参照の表と相互参照のストリームを読み、`/Prev` と、両方を持つファイルの `/XRefStm` をたどる。後の改訂の項目が前の改訂に勝つ。オブジェクトのストリーム（`/Type /ObjStm`）の中のオブジェクトも読む。相互参照が壊れたファイルを、オブジェクトを走査して直すことはしない。
- **暗号化**：トレーラーに `/Encrypt` があれば、拒む。
- **ページ**：ページの木をたどり、`page` 番目のページを取る。`Resources`、`MediaBox`、`CropBox`、`Rotate` は、ページの木の親から引き継ぐ。
- **切り抜き**：CropBox（なければ MediaBox）を、MediaBox との共通部分にしたものを切り抜きの枠とする。pdfTeX の既定と同じで、PDF のビューアーが表示する範囲でもあるので、`web` の画像を作るときの範囲とそろいやすい。
- **回転**：`Rotate`（0、90、180、270）を Form XObject の `Matrix` で表す。図版の縦横の比は回転した後の枠で決める。
- **UserUnit**：1 でない `UserUnit` を持つページは拒む。

取り込む Form XObject と、そこから参照されるオブジェクトは次のように作る。

- Form XObject の `BBox` を切り抜きの枠、`Resources` をページの資源とし、ページの内容のストリーム（配列なら、復号して改行でつないだもの）を内容とする。ページの `Group`（透明のグループ）があれば写す。
- ページの注釈、`Metadata`、`PieceInfo`、`StructParents`、しおり、カタログの `OutputIntents` は写さない。
- 資源から参照をたどって届くオブジェクトだけを写し、番号を振り直す。たどる順は、辞書のキーと配列の要素の、ファイルの中の順とする。同じファイルの同じオブジェクトは、何度届いても一度だけ写す。
- 画像のように復号しないストリームは、バイト列をそのまま写す。内容のストリーム（ページ、Form XObject、Type 3 のフォントの字形、タイリングのパターン）は復号し、下の色の書き換えをしてから、Flate で圧縮し直す。

フィルターは次のように扱う。

| フィルター | 扱い |
| --- | --- |
| `FlateDecode`（予測子を含む）、`ASCIIHexDecode`、`ASCII85Decode` | 復号できる。内容のストリームにも使える |
| `DCTDecode`、`CCITTFaxDecode`、`RunLengthDecode` | 画像のストリームでだけ、そのまま写す |
| `LZWDecode`、`JBIG2Decode`、`JPXDecode`、`Crypt`、そのほか | 拒む |

色は次のように扱う。

- DeviceRGB は、sRGB のプロファイル（`Golem.Pdf.Srgb`）の ICCBased に置き換える。置き換えるのは、資源の `ColorSpace` の値、画像とシェーディングの辞書の `ColorSpace`、Indexed の基底の色空間、内容のストリームの `rg`、`RG`、`cs`、`CS` である。`r g b rg` は `/GolemSRGB cs r g b sc` に、`RG` は `CS` と `SC` の組に書き換え、`GolemSRGB` をその内容のストリームの資源に足す。
- DeviceGray、DeviceCMYK、ICCBased、CalGray、CalRGB、Lab、Pattern は、そのまま写す。DeviceCMYK の値は、本の出力インテントの値として印刷される。
- Separation と DeviceN（特色）、RGB のインライン画像（`BI` の `/CS /RGB` か `/CS /DeviceRGB`）は拒む。インライン画像の色空間を ICCBased に置き換える書き方が、インライン画像の規則では保証されないためである。
- 取り込んだ図版が使う色空間の一覧（`gray`、`rgb`、`cmyk`、`icc` のプロファイル、`lab`）を `ImportedPage` に持たせ、プリフライトに渡す。

フォントは次のように扱う。

- 届いたフォントの辞書のうち、Type 1、MMType1、TrueType と、Type 0 の子孫の CIDFont は、`FontDescriptor` に `FontFile`、`FontFile2`、`FontFile3` のどれかを持たなければ拒む。標準の 14 書体も、埋め込んでいなければ拒む。
- Type 3 のフォントは、字形の内容のストリームと資源を、ページの内容と同じ規則でたどる。
- 取り込んだフォントは、Golem が本文に使うフォントとまとめない。同じ書体が二度埋め込まれることがある。

オプショナルコンテンツ（レイヤー）は、`/OC` を持つオブジェクトか、資源の `Properties` に `/Type /OCG` か `/Type /OCMD` があれば拒む。
レイヤーを残すには、カタログの `OCProperties` を本の PDF に作る必要があり、PDF/X-4 にもその規則があるためである。

拒む理由は `ImportError` の構成子で表し、利用者に見せる文言を一つずつ持たせる。

| 構成子 | 文言 |
| --- | --- |
| `Malformed` | `PDF として読めません（<どこで>）` |
| `Encrypted` | `暗号化された PDF は使えません` |
| `NoSuchPage` | `<n> ページ目がありません（全 <m> ページ）` |
| `UnsupportedFilter` | `<名前> で圧縮された PDF は使えません` |
| `FontNotEmbedded` | `埋め込んでいないフォントがあります: <BaseFont>` |
| `SpotColor` | `特色（Separation か DeviceN）があります` |
| `RgbInlineImage` | `RGB のインライン画像があります` |
| `OptionalContent` | `レイヤー（オプショナルコンテンツ）があります` |
| `UnsupportedUserUnit` | `UserUnit が 1 でないページは使えません` |

### PDF の書き手（golem-pdf の `Golem.Pdf.Writer`）

- `Mark` に `Form !FormRef !Rect` を加える。矩形に、Form XObject の切り抜きの枠を縦横の比を保たずに合わせる `cm` と `Do` を書く。縦横の比は、配置を決める golem-driver が保つ。
- `Document` に `docForms :: Map FormRef ImportedPage` を加える。Form XObject と取り込んだオブジェクトは、画像の XObject の後に、ページで初めて使った順に番号を振る。
- 同じファイルの同じページを置く図版が複数あれば、Form XObject を一つだけ書く。同じファイルの別のページどうしは、共通のオブジェクト（フォントなど）を一度だけ写す。
- `Golem.Pdf.X4.verify` は今のままでよい。置き換えた後の取り込んだオブジェクトにも、今の検査（ICC プロファイルのない RGB、フォントの埋め込み、暗号化、JavaScript と外部への参照）がそのまま効く。

### 置けない図版の診断（golem-driver）

`loadFigures` は、図版ごとに `Either Text FigureContent` を返す。

```haskell
data FigureContent
  = RasterFigure !P.ImageData
  | VectorFigure !P.ImportedPage
```

- 拡張子が `.pdf` なら `importPage`、`.png`、`.jpg`、`.jpeg` なら `readImage` で読む。
- `Left` になった図版は、エラー G0810（`図版を PDF に置けません: <パス>（<理由>）`）とし、PDF を書かない。理由は `readImage` の文言か、`ImportError` の文言である。位置はその `@figure` のブロックとし、`@figure` ごとに一つ出す。
- G0810 は dev と prod の両方でエラーである。ないファイル（G0233）が両方でエラーなのと合わせる。
- 図版の大きさは、PNG と JPEG では画素の縦横の比、PDF では切り抜きの枠（回転の後）の縦横の比から決める。回り込み（`wrap`、`width`）、キャプション、行の格子の扱いは、[golem-driver ADR 0005](../../golem-driver/adr/0005-pdf-wrapped-figures.md) のまま変えない。
- G0810 は PDF を組むとき（`golem build` の PDF、`golem preflight`）にだけ出す。HTML、EPUB、プレーンテキストは画像を読まない。

### プリフライト（golem-preflight）

- G0905 を廃止する。G0810 で PDF を作れなければプリフライトの検査は行わないので、G0905 が出る場面はなくなる。`View` から `vwUnplaceable` を消し、`preflight.toml` の `image-unplaceable` を知らないキー（G0901）にする。
- 取り込んだ PDF の図版も、ページの図版の一覧に載せる。`ImageView` の `ivImage :: ImageData` を、`ivContent :: FigureContent` に替える。
- G0906（実効の解像度の不足）と G0907（過剰）は、PNG と JPEG の図版だけを検査する。PDF の図版の中の画像の解像度は検査しない。
- G0908（許さない色空間）は、PDF の図版では、`ImportedPage` の色空間の一覧のうち、許さないものをすべて並べて一つの診断にする。sRGB に置き換えた DeviceRGB は `rgb` とする。
- G0909（出力インテントと違うプロファイル）は、PDF の図版の CMYK の ICCBased のプロファイルが出力インテントと違えば出す。
- G0911（断裁の危険域の図版）は、PDF の図版も矩形で検査する。

### データ構造

- golem-doc の `Figure` に `figPage :: Maybe Int` を加える。CBOR では、今の六つの要素の後に七つめの要素（`null` か整数）として書く。CDDL の `figure` も同じに改める（[golem-doc ADR 0001](../../golem-doc/adr/0001-semantic-ir-in-cddl.md)）。
- golem-pdf に `Golem.Pdf.Import`（`importPage`、`ImportedPage`、`ImportError`、`ColorUse`）を加え、`Golem.Pdf` から再輸出する。
- golem-pdf の `Mark` に `Form`、`Document` に `docForms` を加える。
- golem-driver の `loadFigures` の結果を `Map Text (Either Text FigureContent)` にし、`PlacedFigure` の画像を `FigureContent` にする。
- golem-preflight の `View` から `vwUnplaceable` と `Unplaceable` を消し、`ImageView` の `ivImage` を `ivContent` に替える。

### ドキュメント

- 仕様書の[「図版」の節](../../specifications.md#図版)に、PDF の図版の取り込み方（ページ、切り抜きの枠、色とフォントの扱い、拒む場合）、`web` の形式、G0810 を書く。[「色」の節](../../specifications.md#色)の画像の例外に、PDF の図版の DeviceRGB を sRGB に置き換えることを足す。[「golem preflight」の節](../../specifications.md#golem-preflight)の表から G0905 の行を消し、G0906 から G0911 の説明に PDF の図版の扱いを足す。
- `docs/markup.md` の「図版」の節に、`page=`、`web` の形式、形式の誤り（G0273、G0274、G0275）を書く。
- `docs/diagnostics.md` に G0273、G0274、G0275、G0810 の節を足し、G0905 を状態「廃止」にして、代わりに G0810 を案内する。
- `docs/roadmap.md` から「図版の欠落の扱い」「PDF の図版」「PDF に置けない図版」を消す。
- 利用者のマニュアルの `manual/chapters/03-markup.gm`（図版の節）と `manual/appendices/a-markup.gm` に `page=` と形式の規則を、`manual/appendices/d-preflight.gm` から `image-unplaceable` の行を消し、`manual/appendices/e-errors.gm` に G0273、G0274、G0275、G0810 を足して G0905 を廃止と書き、`manual/appendices/i-known-issues.gm` の置けない図版の項を消す。
- 開発者のマニュアルのモジュールの章（`manual-dev/part2/07-modules.gm`）の golem-pdf の説明に、PDF を読む処理を足す。
- [golem-cli ADR 0006](../../golem-cli/adr/0006-preflight.md) のステータスの行を「採択→G0905 の廃止と、図版の検査の PDF の図版への拡張は [golem-pdf ADR 0008](../../golem-pdf/adr/0008-pdf-figures.md)」に改める。
- [ADR 0002](0002-pdf-x-4.md) のステータスの行に「取り込んだ PDF の図版の色、フォント、透明の扱いは [ADR 0008](0008-pdf-figures.md)」を足す。

## 実装しないこと

- 切り抜きの枠の選択（InDesign のアート、トリミング、裁ち落とし、内容の外接矩形）。v1 は CropBox だけを使う。要る場合は `box=` のようなキーを別の ADR で加える。
- 壊れた相互参照の修復、暗号化された PDF の復号、`LZWDecode`、`JBIG2Decode`、`JPXDecode` のストリーム。
- 特色とレイヤーを持つ PDF の取り込み。特色を本の PDF に通すには、[ADR 0002](0002-pdf-x-4.md) の色の方針から決め直す必要がある。
- 取り込んだフォントと本文のフォントをまとめて一度だけ埋め込むこと。
- PDF の図版の DeviceCMYK を、図版を作ったときの出力インテントから本の出力インテントに変換すること。Golem は色を変換しない。
- PDF の図版の中の画像の解像度、総インキ量、細すぎる線の検査。
- 取り込んだページの注釈、リンク、しおり、タグの構造を残すこと。
- HTML と EPUB の出力で、図版のファイルや `web` の画像が画像として読めるかを確かめること。HTML と EPUB は今と同じくファイルを写すだけにする。
- 拡張子ではなく中身で図版の形式を決めること。
- PDF を読む処理に、Rust のライブラリや新しい組み込みの依存（pdf-toolbox、qpdf や MuPDF のライブラリなど）を使うこと。
- `preflight.toml` の `image-unplaceable` を読んで無視する移行の期間。
- SVG の図版。[ADR 0009](0009-svg-figures.md) で扱う。

## テスト設計

実装の前に書き、失敗することを確かめる。
テストに使う PDF は、Golem 自身が書いた PDF と、テストの中でバイト列として組み立てた小さな PDF とする（外部のツールで作った PDF をコミットしない）。

### 評価（`modules/golem-eval/test/Main.hs`）

- `@figure a.gif alt="x"` が G0274 になり、`@figure a.PDF web=a.png alt="x"` は通る。
- `@figure a.pdf web=b.pdf alt="x"` と `web=b.svg` が G0273 になる。
- `@figure a.png web=b.jpg alt="x"` が通り、`Figure` の `figWeb` が `b.jpg` である。
- `page=2` の PDF の図版の `figPage` が `Just 2` になる。`page=0`、`page=x`、PNG の図版の `page=1` が G0275 になる。

### 意味論の IR（`modules/golem-doc/test/Main.hs`）

- `figPage` を持つ `Figure` が CBOR の往復で変わらない。CDDL の検査を通る。

### PDF の読み込み（`modules/golem-pdf/test/Main.hs`）

- 相互参照の表の PDF、相互参照のストリームとオブジェクトのストリームの PDF、`/Prev` で二つの改訂を持つ PDF のそれぞれで、`importPage 1` が成功し、後の改訂のオブジェクトを使う。
- 三ページの PDF の `importPage 3` が三ページ目の内容を持ち、`importPage 4` が `NoSuchPage 4 3` になる。
- 親の `Pages` にだけ `MediaBox` と `Resources` を持つ PDF で、ページが両方を引き継ぐ。CropBox が MediaBox からはみ出す PDF で、切り抜きの枠が共通部分になる。`Rotate 90` のページの縦横が入れ替わる。
- `/Encrypt`、`LZWDecode` の内容のストリーム、埋め込んでいない Helvetica、Separation の色空間、`/OC` を持つ内容、RGB のインライン画像、`UserUnit 2` の PDF が、それぞれ対応する `ImportError` になる。ヘッダーのない入力と、`startxref` が範囲外を指す入力が `Malformed` になる。
- `1 0 0 rg` と `/DeviceRGB cs` を含む内容のストリームが、`GolemSRGB` の `cs` と `sc` に書き換わり、資源に sRGB の ICCBased が足される。`0 0 0 1 k` は変わらない。DeviceRGB の画像の辞書の `ColorSpace` が ICCBased になる。
- 同じ入力から二度作った `ImportedPage` が同じであり、それを含む PDF のバイト列も同じである（[docs/adr/0002](../../adr/0002-determinism.md)）。
- 取り込んだ図版を含む文書で、`Golem.Pdf.X4.verify` が問題を返さない。書いた PDF が `qpdf --check` を通る（[ADR 0003](0003-pdf-x-4-validator.md) の CI の検査と同じ）。

### PDF の書き手と CLI（`modules/golem-driver/test/Main.hs`、`modules/golem-driver/test/CliSpec.hs`）

- `web=` 付きの PDF の図版（Golem で組んだ PDF）を置いた本の PDF に、Form XObject が一つあり、図版の矩形の幅が行長で、高さが切り抜きの枠の比に合う。
- 同じ PDF を二度置いた本で、Form XObject が一つだけである。
- 壊れた PNG と、`readImage` が拒む PNG（インターレース）の図版で、`golem build --target pdf` が G0810 を出し、終了コード 1 で、PDF を書かない。dev と prod の両方で同じである。
- 今の `CliSpec` の「a PDF as a figure is G0905」を、PDF の図版が置かれ、G0905 も G0810 も出ないテストに替える。暗号化した PDF の図版が `golem build` で G0810 になるテストを足す。
- `golem build --target html` は、壊れた PNG の図版でも G0810 を出さない。
- `golem preflight` は G0810 で終わり、プリフライトの検査を行わない。`image-unplaceable` を書いた `preflight.toml` が G0901 になる。
- `docs/diagnostics.md` の節と、ソースで使うコードが一致する（既存のテストがそのまま確かめる）。

### プリフライト（`modules/golem-preflight/test/Main.hs`）

- G0905 のテストを消す。
- DeviceRGB と DeviceCMYK を使う PDF の図版が、`print` の設定で G0908 を一つ出し、メッセージに `rgb` を含む。
- 出力インテントと違う CMYK の ICCBased を持つ PDF の図版が G0909 を出す。
- PDF の図版が G0906 を出さない。

### 自動テストにしない確かめ方

- Illustrator、Inkscape、LibreOffice Draw、Chrome の印刷、matplotlib、TeX（pdfTeX と LuaTeX）で書き出した図の PDF を、利用者のマニュアルの見本のプロジェクトに置いて組み、画面と印刷で元の PDF と同じに見えることを目で確かめる。拒まれた場合は、その理由が上の表のどれかであることを確かめる。
- 取り込んだ図版を含む PDF を、商用のプリフライト（Acrobat の PDF/X-4 の検査）に通す。sRGB に置き換えた DeviceRGB と、透明のグループを含む図版で誤りが出ないことを確かめ、結果を `docs/audits/` に記録する。

## トレードオフ

置けない図版を、警告ではなくエラーにした。
警告にすると、dev で組みながら図を後から差し替える使い方はしやすくなる。
しかし、図版が消えた PDF は図番号の参照が宙に浮いたまま組まれ、警告を見落とせば入稿まで気付かない。
ないファイル（G0233）が両方のプロファイルでエラーなのとも合わない。

DeviceRGB の置き換えを、内容のストリームの書き換えで行うことにした。
資源の `DefaultRGB` に sRGB を置けば、内容のストリームを触らずに済み、書き換えの誤りで図の見た目が変わる危険もない。
しかし、`DefaultRGB` は資源の辞書ごとに置く必要があり、DeviceRGB の演算子は残るので、`DeviceRGB` の名前を探すだけの検査（Golem の `verify` を含む）からは DeviceRGB があるように見える。
PDF/X-4 の検査がこれを認めるかも確かめられていない。
書き換えなら、出力から DeviceRGB が消え、PNG の画像に sRGB を付ける今の規則と同じ結果になる。
書き換えに要る字句の解析は、PDF のオブジェクトを読む処理と同じものを使えるので、増える仕事は演算子の置き換えだけである。

特色とレイヤーを拒むことにした。
図の PDF にはこれらを含むものがあり、その図は書き出しの設定を変えるまで使えない。
特色を通すと、本の PDF はプロセスカラーだけという仕様書の前提が崩れ、プリフライトの検査（G0915 の総インキ量など）も特色を数える形に改める必要がある。
v1 では理由を示して拒み、書き出しの側で直してもらう。

PDF を読む処理を Haskell で自前で書くことにした。
依存に入れれば実装は短くなるが、組み込みの依存を足すことはメンテナーが避けると決めている。
また、必要なのは一つのページとその資源を写すことだけであり、出力の決定性（オブジェクトをたどる順、番号の振り方）を自分で決める必要もある。
自前で書く範囲は、相互参照、オブジェクトの字句と構文、三つの復号、ページの木に限られる。
相互参照の修復をしないので、壊れた PDF は読めない。
多くの作成ツールは正しい相互参照を書くので、v1 ではこれで足りると見込む。

## 参考文献

- ISO 32000-1:2008, Document management: Portable document format, Part 1: PDF 1.7（7.3 オブジェクト、7.4 フィルター、7.5 ファイルの構造、8.6 色空間、8.10 Form XObject、14.11.2 ページの境界）
- ISO 15930-7:2010, Graphic technology: Prepress digital data exchange using PDF, Part 7: Complete exchange of printing data (PDF/X-4) and partial exchange of printing data with external profile reference (PDF/X-4p) using PDF 1.6（本文は参照していない。[ADR 0002](0002-pdf-x-4.md) と同じ）
- The graphicx package（`\includegraphics` の `pagebox` の既定の `cropbox`）と、pdfTeX の `\pdfximage`（記憶によるもので、資料では確かめていない）
- Adobe InDesign ユーザーガイド、「読み込みオプション（PDF）」（ページの選択とトリミングの枠。記憶によるもので、資料では確かめていない）
