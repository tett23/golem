# ADR 0232: 版、フォント、図版、リンク、EPUB の確かめを、プリフライトの検査と CI の構造の検査に移す

ステータス: 採択（未実装）

## 文脈

[docs/roadmap.md](../roadmap.md) の「手で確かめる項目」には、Acrobat やブラウザで開いて見ることを求める項目が多い。
読み直すと、その多くは見た目の判断ではなく、PDF や EPUB の構造についての問いである。

- **コードブロックの見え方**（[golem-driver ADR 0017](../golem-driver/adr/0017-pdf-code-blocks.md)）：背景の色が DeviceCMYK の版だけに出ること、コードの書体が埋め込まれていること。
- **技術書のコードブロックの見え方**（[golem-driver ADR 0023](../golem-driver/adr/0023-code-block-book-features.md)）：強調の網が墨の版だけに出ること。
- **組版の新しい機能の見え方**の線の種類と色（[golem-driver ADR 0028](../golem-driver/adr/0028-rule-colour-and-style.md)）：色が DeviceCMYK の版だけに出ること。
- **トンボのレジストレーションの色**（[golem-pdf ADR 0007](../golem-pdf/adr/0007-registration-crop-marks.md)）：トンボが全版に出ること、本文に特色が混ざらないこと。
- **二冊のマニュアルの HTML と PDF**（[ADR 0024](0024-manual-audiences-and-policy.md)）：Acrobat でフォントの一覧と埋め込みを見ること。
- **CIDSystemInfo と異体字**（[golem-pdf ADR 0006](../golem-pdf/adr/0006-cid-system-info.md)）：Adobe-Japan1 の ROS を持つフォントで、`CIDSystemInfo` がその ROS になること。
- **PNG の tRNS の見た目**（[golem-pdf ADR 0014](../golem-pdf/adr/0014-png-trns-transparency.md)）：Poppler の `pdftoppm` で画像にして、透明の画素が紙面の白になること。
- **PDF の図版の見た目と商用のプリフライト**（[golem-pdf ADR 0008](../golem-pdf/adr/0008-pdf-figures.md)）と **SVG の図版の見た目**（[golem-pdf ADR 0009](../golem-pdf/adr/0009-svg-figures.md)）：外のツールが書き出した図を置いて組めること、拒むときの理由が表のどれかであること、範囲の外の SVG が G08011 になること。
- **PDF のリンクの注釈**（[ADR 0182](0182-external-links.md)）：リンクの矩形を押して URL が開くこと。
- **EPUB の検査と読書環境での見え方**（[golem-html ADR 0003](../golem-html/adr/0003-cite-links-across-files.md)、[golem-epub ADR 0002](../golem-epub/adr/0002-nav-and-toc-depth.md)、[golem-doc ADR 0007](../golem-doc/adr/0007-plugin-channel-lists.md)）：三つの EPUB を epubcheck にかけ、RSC-012 などが出ないこと。

### 版に出るかは、内容のストリームで決まる

Acrobat の出力プレビューが版ごとに見せるものは、PDF の色の演算子と色空間から計算したものである。
DeviceCMYK の `k` と `K` は C、M、Y、K の四つの版にだけ出て、特色の版を持たない。
`0 0 0 t k` は墨の版にだけ出る。
`Separation` の色材の名前が `All` なら、ISO 32000-1 の 8.6.6.4 により、すべての版に出る。
したがって「背景の色が DeviceCMYK の版だけに出る」は、「背景を塗る演算子の前の色が `k` で設定され、ページに `Separation` も `DeviceN` も `All` 以外にない」と同じことである。
これは内容のストリームを読めば確かめられ、Acrobat を要らない。

golem-driver のテストは、すでに内容のストリームを読んでいる。
`modules/golem-driver/test/Support.hs` の `drawnGlyphs` と `strokeRuns` は、ストリームを展開して演算子を拾い（[Support.hs の 272 行から 310 行](https://github.com/tett23/golem/blob/ed9aafba3e0ffd788f921de86b261339d8f642cd/modules/golem-driver/test/Support.hs#L272-L310)）、トンボのテストは `/Reg cs 1 scn` と `/Separation /All` を確かめている（[golem-pdf ADR 0007](../golem-pdf/adr/0007-registration-crop-marks.md) のテスト設計）。
足りないのは、塗りと線のすべてについて、色の演算子と色空間を一覧にする道具である。

### フォントの埋め込みも構造で決まる

Acrobat のフォントの一覧の「埋め込みサブセット」は、フォントの記述子が `FontFile`、`FontFile2`、`FontFile3` のどれかを持つかで決まる。
PDF/X-4 の文書では、`Golem.Pdf.X4.verify` がすでに埋め込まないフォントを `X4Problem` にする（[X4.hs の 229 行から 234 行](https://github.com/tett23/golem/blob/ed9aafba3e0ffd788f921de86b261339d8f642cd/modules/golem-pdf/src/Golem/Pdf/X4.hs#L229-L234)）。
ただし、`golem preflight` の `pdf-x` の検査は、出力インテントがなければ、欠けた要件を並べず G09014 を一つだけ出す（[Preflight.hs の 395 行から 404 行](https://github.com/tett23/golem/blob/ed9aafba3e0ffd788f921de86b261339d8f642cd/modules/golem-preflight/src/Golem/Preflight.hs#L395-L404)）。
二冊のマニュアルには出力インテントがないので、埋め込みは報告されない。
qpdf は `build` の `tests` の runner に apt で入っている（[`ci.yml` の 189 行から 191 行](https://github.com/tett23/golem/blob/ed9aafba3e0ffd788f921de86b261339d8f642cd/.github/workflows/ci.yml#L189-L191)）。

### プリフライトに入れられるもの

メンテナーは、この ADR の確かめのうち `golem preflight` の検査にできるものは、プリフライトの検査にすると決めた（下の「決めたことの記録」）。
CI のテストだけにすると、Golem の試料の PDF しか確かめられない。
プリフライトの検査にすれば、利用者が自分の本の PDF で同じことを確かめられる。

プリフライトの検査にできるかは、次の三つで決まる。

- **出力の PDF の性質であること**：プリフライトは、組んだ結果の写し（`Golem.Preflight.View`）を、golem-preflight の純粋な関数で検査する。写しは golem-typeset の `Golem.Typeset.Draw` が、書く前の PDF のオブジェクト（`PdfObjects`）から作る（[Draw.hs の 429 行](https://github.com/tett23/golem/blob/ed9aafba3e0ffd788f921de86b261339d8f642cd/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L429)）。オブジェクトから計算できる性質は、検査にできる。
- **外の実行ファイルを要らないこと**：`golem` は実行時に外の実行ファイルに頼らない。Poppler、qpdf、epubcheck を要る確かめは、プリフライトに入れられない。
- **Golem の試料に固有でないこと**：マニュアルの README が挙げる書体と照らすこと、fixture が三つの形を含むことは、Golem のリポジトリについての問いであり、利用者の本には意味がない。

この三つで分けると、次のようになる。

| 確かめ | 行き先 | 理由 |
| --- | --- | --- |
| 版（特色が混ざらないこと） | プリフライト（G09020） | オブジェクトの色空間から決まる |
| 版（C、M、Y の版に出ないこと） | プリフライト（G09021） | ページの内容のストリームの色の演算子から決まる。InDesign のプリフライトの「CMY の版」にあたる（[golem-cli ADR 0006](../golem-cli/adr/0006-preflight.md) の文脈） |
| 版（背景、網、線、トンボの色が Golem の決めた色空間であること） | CI | Golem の描き方の正しさであり、利用者の本では原稿のスウォッチで変わる |
| フォントの埋め込み | プリフライト（G09019） | フォントの記述子から決まる |
| CIDSystemInfo と CFF の `ROS` | CI | 写し方の正しさで、違えば Golem の誤りである。利用者が直せることがない |
| マニュアルの書体の一覧と README | CI | リポジトリに固有である |
| 外のツールの図版の試料 | CI | 取り込みと拒否は、すでに `golem build` の G08010 と G08011 が受け持つ。試料はその回帰のテストである |
| tRNS の画素、図版の画素の差 | CI | Poppler を要る |
| リンクの注釈を読むビューア | CI | Poppler を要る |
| EPUB の fixture | CI | PDF でなく、epubcheck を要る |

プリフライトに入れる三つの検査は、今の Golem の出力では、G09021 のほかは出ない。
Golem はプロセスカラーだけを書き、取り込む PDF の図版も、特色と埋め込まないフォントを `golem build` の G08010 で拒むからである（[golem-pdf ADR 0008](../golem-pdf/adr/0008-pdf-figures.md)）。
それでも検査にするのは、G09014 と同じく、入稿するバイト列のもとのオブジェクトで確かめるためである。
Golem の誤りでこの性質が崩れたら、印刷所に渡す前に利用者が気づける。

### CIDSystemInfo は、リポジトリにフォントがないだけである

[golem-pdf ADR 0006](../golem-pdf/adr/0006-cid-system-info.md) は、Adobe-Japan1 の ROS のフォントがリポジトリにないので、実際のフォントで確かめていない。
ただ、確かめたいのは、フォントの CFF の `ROS` の演算子の値が PDF の `CIDSystemInfo` に写ることである。
fixture の Source Han Sans のサブセットの CFF の `ROS` を、テストの中で `Adobe`、`Japan1`、`7` に書き換えれば、golem-font が読み、golem-pdf が書くまでを、フォントのファイルを足さずに通せる。
書き換えるのは CFF の Top DICT の三つの演算数であり、文字列の索引の二つを足す小さな処理で済む。
Acrobat のプリフライトがそのフォントに何も言わないこと、InDesign の書き出しと同じであることは、実際のフォントと商用のツールを要るので、この方法では確かめられない。

### Adobe の製品と ISO の規格の確かめは、v1.0.0 のリリースで行う

Acrobat、InDesign、Illustrator と、ISO の規格の本文は、どれも費用がかかる。
メンテナーは、これらを要る確かめを v1.0.0 のリリースのときにまとめて行うと決めた（下の「決めたことの記録」）。
この ADR が残す Adobe の製品の確かめと、Illustrator の図版の試料も、それに従う。
上の 8.6.6.4 の記述も、ISO 32000-1 の本文と照らすのは v1.0.0 のリリースのときである。

### Poppler は、ここで初めて要る

PNG の tRNS の項目は、Poppler の `pdftoppm` で画像にすることを名指ししている。
見た目の回帰のテストの shem は DeviceRGB と ICCBased をまだ読まないので（shem の仕様書）、RGB の画像を含む PDF を画素にするには使えない。
Poppler は Ubuntu の `poppler-utils` にあり、GPL のもとで配布される実行ファイルを CI で走らせるだけで、Golem にはリンクしない。
同じパッケージの `pdfinfo -url` は、ページのリンクの注釈の URL を一覧にする。
これは、PDF のビューアの実装の一つが、Golem の注釈をリンクとして読むことの確かめになる。

### EPUB は fixture が足りないだけである

CI の epubcheck は、`sample`、`bibliographies`、`languages` の三つの EPUB を検査している（[`ci.yml` の 438 行から 458 行](https://github.com/tett23/golem/blob/ed9aafba3e0ffd788f921de86b261339d8f642cd/.github/workflows/ci.yml#L438-L458)）。
[golem-html ADR 0003](../golem-html/adr/0003-cite-links-across-files.md) の文脈が書くとおり、どの fixture も、引用と `@bibliography` を別のファイルに置く形、ナビゲーション文書の深さを変えた形、プラグインの独自のチャネルを使った形を含まない。
fixture を足して同じ手順で検査すれば、この項目の epubcheck の部分は終わる。

### 外のツールが書き出した図版は、一度作れば足りる

図版の項目は、Illustrator、Inkscape、LibreOffice Draw、Chrome の印刷、matplotlib、TeX、draw.io で書き出した図を求めている。
これらのツールを CI に入れなくても、書き出した PDF と SVG をリポジトリに置けば、取り込みと拒否の検査はそのファイルに対して毎回走る。
ツールが要るのは、試料を作る一度だけである。
Illustrator の試料は、メンテナーが v1.0.0 のリリースのときに一度だけ書き出す。

## 実装すること

### 1. golem-pdf の色の一覧と、埋め込まないフォントの一覧

golem-pdf に `Golem.Pdf.Paint` を足し、`paintsOf :: PdfObjects -> [Paint]` を公開する。
`Paint` は、次を持つ。

- `paPage`：PDF の何ページ目か（1 から数える）。
- `paOperator`：塗るか描く演算子（`f`、`f*`、`B`、`B*`、`b`、`b*`、`S`、`s`、`Tj`、`TJ`、`'`、`"`、`sh`）。
- `paSource`：ページの内容のストリームか、そこから `Do` で呼んだ Form XObject の資源の名前の列か。
- `paSpace`：そのときの塗りか線の色空間。`DeviceGray`、`DeviceRGB`、`DeviceCMYK`、`ICCBased <成分の数>`、`Lab`、`Separation <色材>`、`DeviceN [<色材>…]`、`Pattern`、`Indexed` のどれか。
- `paComponents`：色の成分。ストリームに書かれた演算数の文字列のままとする。

読み方は次のとおりである。

- ページの内容のストリームを Flate で展開して、演算子を順に読む。トークンの読み方は `Golem.Pdf.Import` の内容のストリームの読み方を使う。
- `q` と `Q` で、塗りと線の色空間と色を保存し、戻す。
- `cs` と `CS` の後の色は、その色空間の初期の色とする。
- `g`、`G`、`rg`、`RG`、`k`、`K` は、それぞれの装置の色空間と色を設定する。
- 色空間の資源の名前は、ページか Form XObject の `Resources` の `ColorSpace` で引く。
- Form XObject の中は、呼んだ側の色を引き継いで読み、`Do` の後は呼んだ側の色に戻る。
- テキストの演算子は、テキストの描き方（`Tr`）が塗りなら塗りの色、線なら線の色、両方なら二つの `Paint` とする。描かない描き方（`3`、`7`）は `Paint` にしない。
- 画像の `Do` は `Paint` にしない。画像の色は G09006 から G09009 が受け持つ。

`Golem.Pdf.X4.verify` の `unembedded` を、`unembeddedFonts :: PdfObjects -> [Text]` として公開し、`verify` もそれを使う。
`verify` の結果は変えない。

色空間のオブジェクトのうち特色にあたるものの一覧を、`spotColorants :: PdfObjects -> [Text]` として公開する。
すべてのオブジェクトを走査し、`Separation` の色材の名前が `All` でも `None` でもないもの、`DeviceN` の色材の名前のうち `All` と `None` でないものを、見つけた順に一度ずつ並べる。
`usesDeviceRgb` と同じく、使われているかは問わない。

### 2. プリフライトの写しの欄

`Golem.Preflight.View` の `View` に、次の三つの欄を足す。

- `vwPaints :: [Paint]`：`paintsOf` の結果。
- `vwUnembeddedFonts :: [Text]`：`unembeddedFonts` の結果。
- `vwSpotColorants :: [Text]`：`spotColorants` の結果。

`Golem.Typeset.Draw` は、`vwX4` と同じく `documentObjects` から遅延して作る。
`golem build` は、G08100 のために字の一覧だけを評価するので、この三つを計算しない。

golem-pdf は、golem-preflight と golem-typeset がすでに依存している。
golem-driver のテストも golem-pdf、golem-preflight、golem-typeset に依存している。
この ADR は、golem-* のパッケージのあいだの `build-depends` を変えない。

### 3. プリフライトの三つの検査

`Golem.Preflight.check` に、次の三つの検査を足す。

| 検査 | コード | `basic` | `print` |
| --- | --- | --- | --- |
| `font-embedding`（埋め込んでいないフォント） | G09019 | error | error |
| `spot-colors`（特色の色空間） | G09020 | off | error |
| `cmy-plates`（C、M、Y の版に出る色） | G09021 | off | off |

どの表も、キーは `severity` だけである。
`basic` の `font-embedding` を `error` にするのは、InDesign の `[基本]` の「環境にないフォント」に近いからである。

#### G09019 埋め込んでいないフォント（`font-embedding`）

- **条件**：フォントの記述子が `FontFile`、`FontFile2`、`FontFile3` のどれも持たない。出力インテントの有無によらない。
- **まとめ**：`vwUnembeddedFonts` の名前ごとに一つ、その順に出す。
- **位置**：`style.toml` の先頭で、`style.toml` がなければ `manifest.toml` の先頭である。
- **事実**：`font`（記述子の `FontName`）。
- **メッセージ**：`フォントを埋め込んでいません: <FontName>`

同じ原因を二つのコードで出さないため、`pdf-x` の検査（G09014）は、要件「フォントの埋め込み」の `X4Problem` を出さない。
フォントの埋め込みの重大度は、`pdf-x` でなく `font-embedding` の `severity` で決まる。
`Golem.Pdf.X4.verify` の結果は変えず、golem-preflight の `pdfX` が、その要件を除いて diagnostics にする。

#### G09020 特色の色空間（`spot-colors`）

- **条件**：`vwSpotColorants` が空でない。
- **まとめ**：色材の名前ごとに一つ、その順に出す。
- **位置**：`style.toml` の先頭で、`style.toml` がなければ `manifest.toml` の先頭である。
- **事実**：`colorant`。
- **メッセージ**：`特色の色空間があります: <色材の名前>`

トンボのレジストレーションの色（`Separation All`）は数えない。

#### G09021 C、M、Y の版に出る色（`cmy-plates`）

墨一色で刷る本のための検査である。

- **条件**：`paSource` がページの内容のストリームである `Paint` のうち、次のどれかがある。
  - `DeviceCMYK` で、C、M、Y の成分のどれかが 0 でない。
  - `ICCBased` の 4 成分で、初めの三つの成分のどれかが 0 でない。
  - `DeviceRGB`、`ICCBased` の 3 成分、`Lab`、`Pattern`、`Indexed`、`DeviceN`、`Separation` のうち `All` 以外。値によらない。
- **数えないもの**：`DeviceGray`、`ICCBased` の 1 成分、`Separation All`。Form XObject の中の色（PDF と SVG の図版）と、画像。図版の色は G09008 が受け持つので、墨一色の本では `[image-color-space]` の `allowed` を `["gray"]` にする。
- **まとめ**：色空間と成分の組ごとに一つ、最初に現れた順に出し、ページを `pdf-pages` に並べる。
- **位置**：`style.toml` の先頭で、`style.toml` がなければ `manifest.toml` の先頭である。
- **事実**：`color`（メッセージの色の文字列）、`pdf-pages`。
- **メッセージ**：`C、M、Y の版に出る色があります: <色>（PDF の <ページ> ページ目）`。`<色>` は `DeviceCMYK 0.2 0 0 1` のように色空間と成分を空白でつなぐ。値の等しいスウォッチが `vwSwatchesUsed` にあれば、`<スウォッチの名前>、` を前に付ける。

#### 設定と雛形

- `preflight.toml` のスキーマ（[ADR 0169](0169-lsp-completion-in-style-and-preflight-toml.md)）に、三つの表と `severity` を足す。補完と G09001 の未知のキーは、スキーマから決まる。
- `golem new` の `preflight.toml` の雛形に、`page-count` と同じ形で、墨一色の本のための段落を足す。`[cmy-plates]` の `severity = "error"` と、`[image-color-space]` の `allowed = ["gray"]` を、コメントで書く。

### 4. 版のテスト（CI）

`modules/golem-driver/test/` に、次のテストを先に書いて失敗させる。
どれも `preflight` を走らせ、`prView` の `vwPaints` と diagnostics を読む。

- コードブロックの背景、技術書のコードブロックの強調の網、注釈の印、行番号を含む PDF で、背景の矩形の `Paint` の色空間が `DeviceCMYK` であり、強調の網の `Paint` が `DeviceCMYK` の `0 0 0 t` か `DeviceGray` であること（[golem-driver ADR 0017](../golem-driver/adr/0017-pdf-code-blocks.md)、[0023](../golem-driver/adr/0023-code-block-book-features.md)）。
- 12 の線の種類と色の脚注の区切り線の試料で、どの線の `Paint` も `DeviceCMYK` か `DeviceGray` であること（[golem-driver ADR 0028](../golem-driver/adr/0028-rule-colour-and-style.md)）。
- トンボを付けた PDF で、トンボの `Paint` がすべて `Separation All` であり、それ以外の `Paint` に `Separation` と `DeviceN` がないこと（[golem-pdf ADR 0007](../golem-pdf/adr/0007-registration-crop-marks.md)。今のテストの文字列の検索を、ページのすべての `Paint` に広げる）。
- 上の PDF のどれでも、G09019 と G09020 が出ないこと。
- 墨だけのスウォッチで組んだ試料で G09021 が出ず、C の成分を持つスウォッチの文字を一つ足すと、G09021 が一つ出ること。

### 5. ROS を書き換えたフォントのテスト（CI）

golem-font のテストに、CFF の Top DICT の `ROS` を書き換える関数をテストの中だけに置く。
次を確かめる。

- Source Han Sans のサブセットの `ROS` を `Adobe`、`Japan1`、`7` に書き換えたフォントの `fontCidSystemInfo` が `Just (CidSystemInfo "Adobe" "Japan1" 7)` であること。
- そのフォントを `subsetFont` でさらにサブセット化しても、`ROS` が残ること。

golem-driver のテストに、同じフォントで『蟹工船』の一段落を組み、PDF の CIDFont の `CIDSystemInfo` が `Adobe-Japan1-7` になることを足す。
書き換えの関数はフォントのファイルを作らず、テストのたびにメモリの上で作る。

### 6. 外のツールの図版の試料（CI）

`modules/golem-driver/test/fixtures/figures-external/` を足す。

- 図版の PDF：Inkscape、LibreOffice Draw、Chromium の印刷、matplotlib、pdfTeX、LuaTeX で書き出したもの。どれも同じ単純な図（線、塗り、文字、RGB と CMYK の色、透明のグループ）を描く。
- SVG：Inkscape と draw.io で、[golem-pdf ADR 0009](../golem-pdf/adr/0009-svg-figures.md) の範囲の中だけで描いたものと、範囲の外の機能（フィルター、`<foreignObject>` など）を一つずつ使ったもの。
- `README.md` に、それぞれのツールの名前、版、書き出しの設定、作った人と日付を書く。図はこのリポジトリのために描いたもので、マニュアルと同じく CC0 1.0 とする。

テストは次のとおりである。

- 範囲の中の図版の PDF と SVG は、diagnostic なしに組めること。
- 拒まれる図版の PDF は、それぞれ [golem-pdf ADR 0008](../golem-pdf/adr/0008-pdf-figures.md) の表の構成子のどれかの文言で拒まれ、どの構成子かを試料ごとに期待として書くこと。
- 範囲の外の機能を使った SVG は、G08011 になること。
- 組んだ PDF が `qpdf --check` を通ること。

Illustrator の図版の PDF と SVG は、この ADR の実装では作らない。
README の表の Illustrator の行は「v1.0.0 のリリースで書き出す」とし、テストはその行を飛ばす。
メンテナーが v1.0.0 のリリースで書き出してコミットしたら、テストはその行も検査する。

### 7. Poppler のテスト（CI）

`build` の `tests` の runner の apt に `poppler-utils` を加える（qpdf と同じ一回の `apt-install.sh` で入れる）。
golem-driver のテストの `Support.hs` に `optionalTool "pdftoppm"` と `optionalTool "pdfinfo"` を足し、`GOLEM_REQUIRE_EXTERNAL_TOOLS=1` のときは、ないことを失敗にする（`qpdfCheck` と同じ扱い）。

- **tRNS**：figures の fixture の PDF を `pdftoppm -r 72 -ppm` で画像にし、tRNS を持つ 4 枚の PNG のそれぞれについて、透明の画素に当たる位置の画素が白（RGB の三つの成分がどれも 255）であり、半透明の緑の画素が、緑と白を `alpha` で混ぜた値から 2 以内であること。位置は、置いた矩形と PNG の画素から計算する。
- **図版の PDF**：6 の範囲の中の図版の PDF のそれぞれについて、元の PDF のページと、それを等倍で置いて組んだ PDF の図の範囲を、同じ解像度で `pdftoppm` にかけ、画素の差が閾値以下であること。閾値は、実装のプルリクエストで、等倍で置いた場合の差を測って決める。
- **リンク**：リンクを含む横組みと縦組みの PDF で、`pdfinfo -url` の一覧が、原稿に書いた URL とページの組と一致すること。

`pdfinfo -url` が Ubuntu 24.04 の Poppler にあることは、実装の最初に確かめる。
なければ、リンクのテストは qpdf の JSON の `Annots` と `A` の `URI` を読む形にする。

この三つは Poppler を要るので、プリフライトの検査にしない。

### 8. マニュアルのフォント（プリフライトと CI）

埋め込みは、プリフライトで確かめる。
`scripts/ci/manual-preflight.toml` を足す。
`based-on = "none"` とし、`font-embedding` と `spot-colors` だけを `error` にする。
`build` の `outputs` の runner で、二冊のマニュアルのそれぞれに `golem preflight --rules ../scripts/ci/manual-preflight.toml` を走らせ、終了コードが 0 であることを確かめる。

書体の一覧は、CI のスクリプトで確かめる。
`scripts/ci/pdf-fonts.sh` を足す。
PDF を一つ受け取り、`qpdf --json` でフォントの辞書を読み、`BaseFont` の一覧を書く。
一覧は、`manual/fonts/` と `manual-dev/fonts/` の README の挙げる書体と照らし、挙げていない書体が出たら失敗にする。
outputs の runner の apt にも qpdf を加える。
これはリポジトリに固有の確かめなので、プリフライトの検査にしない。

### 9. EPUB の fixture（CI）

次の三つの形を持つ fixture を足し、今の epubcheck の三つのステップと同じ形で検査する。

- 引用と `@bibliography` を別の章のファイルに置いたもの（[golem-html ADR 0003](../golem-html/adr/0003-cite-links-across-files.md) の文脈の三つのファイルのプロジェクト）。
- `toc-depth` を 1 にし、階層 3 までの見出しを持つもの（[golem-epub ADR 0002](../golem-epub/adr/0002-nav-and-toc-depth.md)）。
- 見本のプラグイン（`plugins/wasm/` の一つ）の独自のチャネルを使ったもの（[golem-doc ADR 0007](../golem-doc/adr/0007-plugin-channel-lists.md)）。

三つは一つの fixture にまとめてよい。
まとめた場合でも、三つの形のどれを欠いても fixture のテストが失敗するように、golem-driver のテストで、組んだ EPUB にその三つの形（別のファイルへの引用のリンク、`hidden` の付いたナビゲーションの枝、チャネルの一覧）があることを確かめる。

### 10. ロードマップと文書

ロードマップの「手で確かめる項目」を次のように直す。
Adobe の製品か ISO の規格の本文を要る確かめは、項目に「（v1.0.0 のリリースで確かめる）」と添える。

- 「コードブロックの見え方」から、版と埋め込みを外す。HTML と EPUB の見え方だけが残る（[ADR 0234](0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md) が扱う）。
- 「技術書のコードブロックの見え方」から、強調の網の版を外す。
- 「組版の新しい機能の見え方」の線の種類と色の項目から、DeviceCMYK の版を外す。InDesign との比べ合わせと、破線の両端などの見た目は残る（[ADR 0233](0233-add-the-specimens-of-the-visual-checks-to-the-visual-regression-test.md)）。InDesign との比べ合わせは v1.0.0 のリリースで確かめる。
- 「トンボのレジストレーションの色」は、Acrobat のプリフライトとインキの総量の検査、InDesign の書き出しとの比べ合わせだけを残し、v1.0.0 のリリースで確かめる。
- 「二冊のマニュアルの HTML と PDF」から、PDF のフォントの一覧と埋め込みを外す。
- 「CIDSystemInfo と異体字」は、実際の Adobe-Japan1 のフォントで Acrobat のプリフライトにかけることと、InDesign との比べ合わせだけを残し、v1.0.0 のリリースで確かめる。
- 「PNG の tRNS の見た目」から、`pdftoppm` を外す。
- 「PDF の図版の見た目と商用のプリフライト」と「SVG の図版の見た目」から、外のツールの試料の取り込みと拒否、G08011 を外す。Acrobat の PDF/X-4 の検査が残り、v1.0.0 のリリースで確かめる。
- 「プリフライトと商用のプリフライトの差」と「マニュアルの中の InDesign の記述」にも、v1.0.0 のリリースで確かめることを添える。
- 「PDF のリンクの注釈」から、ビューアがリンクとして読むことのうち `pdfinfo -url` の分を外す。Acrobat Reader とプレビューで押すことと、ISO 15930-7 の本文の照合が残る。この二つは v1.0.0 のリリースで確かめる。
- 「EPUB の検査と読書環境での見え方」から、epubcheck を外す。

ロードマップの「v1.0.0」の節に、Illustrator で図版の PDF と SVG を書き出して `figures-external/` に加えることを足す。

仕様書と diagnostics の一覧を、次のように直す。

- 仕様書の「golem preflight」の節の表に、G09019 から G09021 の三行を足す。G09014 がフォントの埋め込みを出さず、G09019 が受け持つことを書く。
- 仕様書の CI の節に、Poppler、`pdf-fonts.sh`、マニュアルのプリフライトを足す。CONTRIBUTING.md のテストの節に、`poppler-utils` を手元に入れることを足す。
- `docs/diagnostics.md` に G09019、G09020、G09021 の節を足し、G09014 の節の項目から「フォントの埋め込み」を外して G09019 を指す。`Golem.Syntax.Diagnostic.preflightCodes` に三つのコードを足す。`golem explain` の埋め込みの説明も、diagnostics の一覧と同じく直す。
- 利用者のマニュアルの付録 D「preflight.toml のリファレンス」に、三つの表を足す。墨一色の本の設定の例を書く。
- [golem-cli ADR 0006](../golem-cli/adr/0006-preflight.md) のステータスの行に「G09019 から G09021 と、G09014 からフォントの埋め込みを外すことは docs/adr/0232」を、この ADR へのリンクを付けて足す。

## 実装しないこと

- 版ごとの画像を作ること（Ghostscript の `tiffsep` など）。版に出るかは色の演算子で決まるので、画像にしても新しいことはわからない。
- Acrobat、InDesign、Illustrator を CI で動かすこと。
- v1.0.0 のリリースの前に、Adobe の製品か ISO の規格の本文を要る確かめをすること。Illustrator の試料の書き出しもこれに含む。
- PDF/X-4 の検査を、商用のプリフライトの代わりに自前で広げること。`Golem.Pdf.X4.verify` に足す要件は、Acrobat との差がわかってから別の ADR で決める（[golem-cli ADR 0006](../golem-cli/adr/0006-preflight.md)）。
- 実際の Adobe-Japan1 のフォントをリポジトリに入れること。
- Poppler、qpdf、epubcheck を `golem` から呼ぶこと。外の実行ファイルを要る確かめは、CI のテストだけにする。
- CIDSystemInfo と CFF の `ROS` の一致をプリフライトの検査にすること。違えば Golem の誤りで、利用者が直せることがない。CI のテストで守る。
- G09021 で、画像の画素と Form XObject の中の色を数えること。画像と図版の色空間は G09008 が受け持つ。
- G09021 にしきい値（墨のほかの成分の許す量など）を持たせること。墨一色の本では、0 でない成分は版を一つ増やす。
- 特色の扱いを変えること。Golem は特色を書かず、取り込みでも拒む（[golem-pdf ADR 0008](../golem-pdf/adr/0008-pdf-figures.md)）。G09020 は、その性質を出力のオブジェクトで確かめるだけである。

## 不変条件

| 番号 | 不変条件 |
| --- | --- |
| I1 | Golem の PDF のページの内容のストリームの `Paint` の色空間は、`DeviceCMYK`、`DeviceGray`、`Separation All` のどれかであり、`Separation All` の `Paint` はトンボだけである。 |
| I2 | 技術書のコードブロックの強調の網の `Paint` は、`DeviceCMYK` の C、M、Y の成分が 0 であるか、`DeviceGray` である。 |
| I3 | G09019 は、`FontFile`、`FontFile2`、`FontFile3` のどれも持たない記述子があるときに限り出て、その数は記述子の `FontName` の異なる数に等しい。G09014 は要件「フォントの埋め込み」を出さない。 |
| I4 | G09020 は、`All` と `None` のほかの色材の `Separation` か `DeviceN` があるときに限り出て、その数は色材の名前の異なる数に等しい。 |
| I5 | G09021 は、ページの内容のストリームに、上の条件の `Paint` があるときに限り出て、その数は色空間と成分の組の異なる数に等しい。`pdf-pages` は、その組の `Paint` があるページを昇順に重なりなく並べる。 |
| I6 | Form XObject の中の `Paint` と画像は、G09021 の有無を変えない。 |
| I7 | `paintsOf` は、`q` の後の色の設定を、対応する `Q` の後に残さない。 |
| I8 | 同じ `PdfObjects` と同じ設定から、G09019 から G09021 は同じ順に同じ diagnostics を出す。 |
| I9 | Golem のすべての試料の PDF で、G09019 と G09020 は出ない。 |
| I10 | フォントの CFF の `ROS` は、そのまま PDF の `CIDSystemInfo` になる。 |
| I11 | tRNS の透明の画素は、Poppler で画像にしても紙面の白になる。 |
| I12 | CI が epubcheck にかける EPUB は、別のファイルへの引用、浅いナビゲーション、プラグインのチャネルを含む。 |

I1 の「ページの内容のストリーム」は、図版の Form XObject の中身を含まない。
取り込んだ図版の PDF の色は、[golem-pdf ADR 0008](../golem-pdf/adr/0008-pdf-figures.md) が sRGB に置き換えた DeviceRGB を含みうるからである。

境界の入力は次のとおりである。

| 入力 | 期待 |
| --- | --- |
| 内容のストリームが空のページだけ | `Paint` なし、G09021 なし |
| `0 0 0 1 k` の塗り一つ | G09021 なし |
| `0 0 0.01 1 k` の塗り一つ | G09021 が一つ |
| `/Reg cs 1 scn`（`Separation All`）の塗りだけ | G09020 なし、G09021 なし |
| `0 g` の塗りだけ | G09021 なし |
| `cs` の直後に色を設定せずに塗る（`ICCBased` の 4 成分） | 初期の色（すべての成分が 0）なので G09021 なし |
| `1 0 0 rg` の塗り一つ | G09021 が一つ |
| 同じ色の塗りが二つのページに一つずつ | G09021 が一つ、`pdf-pages` は二つ |
| 二つの色が交互に三回ずつ | G09021 が二つ、最初に現れた順 |
| `q 0 0 1 0 k Q` の後に色を設定せずに塗る | 初期の色（`DeviceGray` の 0）なので G09021 なし |
| Form XObject の中だけに `1 0 0 rg` | G09021 なし |
| テキストの描き方 `3` で `1 0 0 rg` の文字 | `Paint` なし、G09021 なし |
| フォントの記述子なし | G09019 なし |
| 記述子が一つで `FontFile3` だけを持つ | G09019 なし |
| 記述子が一つで埋め込みなし | G09019 が一つ |
| 埋め込みのない記述子が同じ `FontName` で二つ | G09019 が一つ |
| 出力インテントがあり、埋め込みのない記述子が一つ | G09019 が一つ、G09014 に「フォントの埋め込み」なし |
| `Separation` の色材が `All` だけ | G09020 なし |
| `Separation /PANTONE#20185#20C` が一つ | G09020 が一つ |
| `DeviceN [/Cyan /Spot1]` が一つ | G09020 が一つ（`Spot1`） |

## テスト設計

不変条件の番号を、テストの名前に入れる。

- **golem-pdf**：`paintsOf` に、手で書いた小さな `PdfObjects`（`q 0 0 0 1 k 0 0 1 1 re f Q /Reg cs 1 scn 0 0 1 1 re f` など）を与え、`Paint` の一覧が期待のとおりになるテストを足す（I7）。`q` と `Q` の後で色が戻ること、Form XObject の中の色が呼んだ側の色を引き継ぎ `Do` の後に戻ること、`cs` の後の初期の色、テキストの描き方を含める。`unembeddedFonts` と `spotColorants` にも、上の表の行の `PdfObjects` を与える。`verify` の結果が今と同じであることを、今のテストで確かめる。
- **golem-preflight**：手で作った `View` に、上の境界の入力の表の行を一つずつ与え、G09019 から G09021 のコード、数、順、メッセージ、事実を確かめる（I3 から I6、I8）。出力インテントのある `View` で、`vwX4` に「フォントの埋め込み」があっても G09014 にそれが出ないことを確かめる（I3）。小さな `View` を網羅して生成し、同じ `View` から二度 `check` を走らせて同じ結果になることを確かめる（I8、[docs/adr/0204](0204-pagination-invariants-by-exhaustive-small-inputs.md)）。`preflight.toml` のスキーマのテストに、三つの表を足す。
- **golem-driver**：4 の版のテスト（I1、I2、I9）、5 の ROS のテスト（I10）、6 の図版の試料のテスト、7 の Poppler のテスト（I11）、9 の EPUB の fixture のテスト（I12）を、先に書いて失敗させる。`golem new` の雛形の `preflight.toml` の中のコメントを外すと、`[cmy-plates]` と `[image-color-space]` がその値になることを確かめる。
- **scripts**：`pdf-fonts.sh` は `scripts/ci/test.sh` で、qpdf があるときだけ、README が挙げる書体だけの PDF と、挙げない書体を含む PDF を与えて確かめる。マニュアルのプリフライトは、CI の outputs の runner で走らせて確かめる。

## トレードオフ

プリフライトの検査が三つ増え、写しの欄が三つ増える。
`paintsOf` は、すべてのページの内容のストリームを展開して読むので、`golem preflight` の時間が延びる。
写しは遅延して作るので、`golem build` の時間は変わらない。
`golem preflight` の延びは、実装のプルリクエストで二冊のマニュアルで測って記録する。

G09019 と G09020 は、今の Golem の出力では出ない。
出ない検査を持つのは、Golem の誤りを入稿の前に見つけるためで、G09014 の要件の多くと同じ考え方である。
その分、`preflight.toml` のキーと diagnostics の一覧は長くなる。

G09014 から要件「フォントの埋め込み」を外すので、`pdf-x` を `error`、`font-embedding` を `off` にした設定では、埋め込んでいないフォントが PDF/X-4 の要件として報告されない。
一つの原因に一つのコードという方針を守るための代価であり、利用者のマニュアルの付録 D の `pdf-x` の項に書く。

マニュアルのプリフライトは prod で組む。
二冊のマニュアルを dev で組んで diagnostic が出なくても、prod の検査（G03010、G05004）でエラーになりうる。
そうなったら、実装のプルリクエストでマニュアルを直す。

`poppler-utils` は、apt から取るものを増やす。
[ADR 0062](0062-epubcheck-from-release-with-cache.md) は、apt の取得が止まった例を記録している。
qpdf と同じ一回の取得にまとめるので、止まったときの扱い（30 秒で切って 3 回まで）は変わらないが、取る量が増えた分、止まる機会は増える。
Ubuntu の Poppler は、ランナーの像の更新で版が変わりうる。
7 の検査は、画素の値の近さと URL の一覧だけを見て、画像のハッシュを固定しないので、版の違いに左右されにくい。

外のツールの試料は、そのツールの今の版の書き出しを固定する。
ツールの新しい版が別の PDF を書くようになっても、テストは気づかない。
試料を作り直す時期は決めず、利用者から取り込めない図版の報告が来たら、その図版を試料に加える。
Illustrator の試料は v1.0.0 のリリースまでないので、それまで、印刷の図版を作る人がいちばん使うツールの書き出しは確かめていない。

テストの時間は、`tests-driver` の runner に、試料の数だけの組版と `pdftoppm` が足される。
組むのは一ページの図版の試料で、合わせて十数秒の見込みである。
実装のプルリクエストで測り、`tests-driver` が臨界経路を延ばすなら、`scripts/ci/test-suites.sh` の分け方を直す。

## メンテナーが決めること

1. **版の確かめ方**：推奨は、内容のストリームの色の演算子で確かめることである。Acrobat の出力プレビューが見せるものは、この演算子から決まる。
   - 退けた案の一つは、Ghostscript（AGPL）の `tiffsep` で版ごとの画像を作り、背景の位置の画素を見ることである。演算子から決まることを画像を通して確かめ直すだけで、Ghostscript を CI に入れる分だけ重い。
   - 二つめは、手で確かめる項目に残すことである。I1 と I2 は、変更のたびに崩れうる性質で、一度の目視では守れない。
2. **CIDSystemInfo の試料**：推奨は、テストの中で `ROS` を書き換えることである。
   - 退けた案の一つは、AFDKO で Adobe-Japan1 の ROS の CID-keyed のフォントを作ってコミットすることである。CID と字形の対応が Adobe-Japan1 と合わないフォントになり、試料として誤解を招く。
   - 二つめは、小塚明朝などの商用のフォントを CI に入れることである。ライセンスがリポジトリへの同梱を許さない。
3. **Poppler の取り方**：推奨は、Ubuntu の apt から取ることである。qpdf と同じ取り方で、版を固定する手段（配布元のアーカイブ）は、Poppler がソースしか配らないので、ビルドを要る。
   - 退けた案は、Poppler をソースからビルドしてキャッシュすることである。ビルドの手順とキャッシュの量が増え、得るのは版の固定だけである。7 の検査は版に左右されにくい。
4. **Illustrator の試料**：推奨は、メンテナーが一度だけ書き出してコミットすることである。CI で作れず、一度作ればテストは毎回走る。
   - 退けた案は、Illustrator を範囲から外すことである。Illustrator は印刷の図版を作る人がいちばん使うツールで、外すと取り込めない図版の報告がいちばん多く来る見込みのところを確かめないことになる。
5. **プリフライトの版の検査が読むもの**：推奨は、書く前の `PdfObjects` の内容のストリームを `paintsOf` で読むことである。CI の版のテストと同じ一覧を読むので、テストで確かめた読み方がそのままプリフライトでも働く。`verify` と同じく、入稿するバイト列のもとのオブジェクトを見る。
   - 退けた案の一つは、写しの `vwSwatchesUsed` から C、M、Y の成分を見ることである。スウォッチを通らない色（既定の文字の色、Golem の描き方の誤りで入った色）を見落とし、CI の I1 と I2 にも使えない。
   - 二つめは、写しの `vwPdf` のバイト列を読み直すことである。相互参照表とオブジェクトのストリームを読む処理を、golem-pdf の取り込みの外に新しく要る。得るものは、`serializePdf` の誤りに気づけることだけで、それは今の `qpdf --check` のテストが受け持つ。
6. **フォントの埋め込みのコード**：推奨は、新しい G09019 に埋め込みを受け持たせ、G09014 からその要件を外すことである。出力インテントの有無によらず同じコードで出る。
   - 退けた案の一つは、出力インテントがないときにも G09014 が埋め込みを出すことである。PDF/X-4 でない PDF に「PDF/X-4 の要件を満たしていません」と出し、出力インテントがないときに一つにまとめる今の決まり（[golem-cli ADR 0006](../golem-cli/adr/0006-preflight.md)）とも合わない。
   - 二つめは、G09019 を足し、G09014 にも要件を残すことである。出力インテントのある PDF で、同じ原因が二つのコードで出る。
7. **C、M、Y の版の検査の範囲**：推奨は、ページの内容のストリームの色だけを数え、図版と画像は G09008 に任せることである。一つの原因に一つのコードを守れる。
   - 退けた案の一つは、Form XObject の中の色も数えることである。PDF と SVG の図版の色が、G09008 と G09021 の二つで出る。
   - 二つめは、画像の画素を読み、C、M、Y の成分が 0 でない画素があるかを見ることである。CMYK の画像を墨だけで描いたものを通せるが、画素を展開する時間がかかり、G09008 と原因が重なる。

## 決めたことの記録

- 「メンテナーが決めること」の 1 から 4 は、推奨のとおりに決めた（2026-11-08、メンテナー）。
- 4 の Illustrator の試料は、メンテナーが v1.0.0 のリリースのときに書き出す（2026-11-08、メンテナー）。Adobe の製品と ISO の規格は費用がかかるので、それらを要る確かめは v1.0.0 のリリースでまとめて行う、という決定による。この ADR の実装では Illustrator の試料を作らず、ロードマップの「v1.0.0」の節に移す。手で確かめる項目のうち Adobe の製品か ISO の規格の本文を要るものには、v1.0.0 のリリースで確かめることを添える。
- メンテナーは、この ADR の確かめのうちプリフライトに入れられるものは入れると決めた（2026-11-08、メンテナー）。入れられたのは、フォントの埋め込み（G09019）、特色の色空間（G09020）、C、M、Y の版に出る色（G09021）の三つである。CIDSystemInfo、マニュアルの書体の一覧、外のツールの図版の試料、Poppler を要る確かめ、EPUB の fixture は、CI のテストに残した。理由は「プリフライトに入れられるもの」の表に書いた。
- 5 から 7 は、この決定を形にするときに生じた選択で、推奨のとおりに決めた（2026-11-08、メンテナー）。
- 参考文献の ISO 32000-1 の節の番号と、境界の表の ICCBased の色空間の初期の色は、規格の本文で確かめていない。ISO の規格で確かめることは v1.0.0 のリリースで行うので、実装はこの二点に頼らず、v1.0.0 のリリースで規格の本文と照らし合わせる。

## 参考文献

- ISO 32000-1:2008, Document management, Portable document format, Part 1: PDF 1.7, 8.6.6.4 Separation Colour Spaces, 8.6.6.5 DeviceN Colour Spaces, 9.3.6 Text Rendering Mode, 9.8 Font Descriptors, 12.5.6.5 Link Annotations
- Poppler, pdftoppm(1), pdfinfo(1), https://poppler.freedesktop.org/
- qpdf, QPDF JSON, https://qpdf.readthedocs.io/en/stable/json.html
- Adobe, The Compact Font Format Specification, Technical Note #5176（Top DICT の `ROS`）
- Adobe, InDesign ユーザーガイド, プリフライト（[golem-cli ADR 0006](../golem-cli/adr/0006-preflight.md) の文脈が引くもの）
- W3C, EPUBCheck, https://github.com/w3c/epubcheck
