# ADR 0006: golem preflight

ステータス: 採択→G0905 の廃止と、図版の検査の PDF の図版への拡張は [golem-pdf ADR 0008](../../golem-pdf/adr/0008-pdf-figures.md)、雛形の `style.toml` の塗り足しは [golem-pdf ADR 0010](../../golem-pdf/adr/0010-golem-check-g0702-and-template-bleed.md)、（G0904 のまとめの単位と位置）は [ADR 0008](0008-g0904-by-size-source-and-colour.md)

## 文脈

`golem build` が PDF を書き終えても、その PDF をそのまま印刷所に渡してよいとは限らない。
解像度の足りない写真、出力インテントと違う色の画像、仕上がりの線の近くに置いた文字は、ビルドを止める誤りではないが、刷り上がりを損なう。
InDesign では、こうした検査をプリフライトが受け持つ。

Adobe のヘルプによると、InDesign のプリフライトは次のように働く。

- 検査の項目としきい値の組を**プリフライトプロファイル**と呼ぶ。新しい文書には [基本] プロファイルが掛かり、不明なリンクと変更されたリンク、オーバーセットテキスト、環境にないフォントを検出する。[基本] は編集できない。
- プロファイルの項目は、リンク、カラー（必要な透明ブレンドスペース、CMY の版、カラースペース、オーバープリント）、画像とオブジェクト（画像の解像度、透明、線の太さ）、テキスト（環境にないフォント、オーバーセットテキスト）、ドキュメント（ページのサイズと向き、ページ数、空白のページ、裁ち落としと印刷可能領域の設定）の五つの分類に分かれる。
- プロファイルは `.idpp` のファイルに書き出して他人に渡せる。文書に一つだけ埋め込める。印刷所は、埋め込まれたものとは別のプロファイルを選んで検査してよい。
- 誤りは、パネルに分類ごとの一覧として出る。ページの範囲で検査を絞れる。誤りの行数を、誤りの種類ごとに上限で切れる。結果をテキストか PDF の報告として保存できる。

docs/specifications.md の「今後の実装項目」の「CLI と LSP」は、`golem preflight` でこれに近いことをすると決め、検査の項目、しきい値、プロファイルにあたる設定の置き場所を ADR に委ねた。

所有者は、`golem new` が新しいプロジェクトに `preflight.toml` を作ることを求めている。
設定の置き場所を、プロジェクトを作った時点で見えるようにするためである。

### Golem が今すでに検査していること

プリフライトの項目のうち、いくつかは今のビルドがエラーとして止める。

| InDesign の項目 | Golem の今の扱い |
| --- | --- |
| 不明なリンク | 図版のファイルがなければ G0233、パスの誤りは G0260（評価の段階） |
| 環境にないフォント | フォントのファイルがなければ G0802、読めなければ G0803 |
| 埋め込めないフォント | `fsType` が埋め込みかサブセット化を禁じていれば G0804 |
| オーバーセットテキスト | 版面に入らない見出し（G0724）、回り込む図版（G0723）、傍注（G0733）、表（G0741、G0742）をエラーにする |
| 裁ち落としの設定 | 日本式のトンボで塗り足しが 0 なら G0702 |
| PDF/X-4 | ページのボックスの検査（`Golem.Pdf.X4.checkPdfX`）と、[golem-pdf ADR 0002](../../golem-pdf/adr/0002-pdf-x-4.md) の要件ごとの golem-pdf のテスト |

InDesign の「変更されたリンク」にあたるものは Golem にない。
Golem はビルドのたびにファイルを読み直すからである。

### 今は検査していないこと

コードを読むと、次のことはどこでも検査していない。

- **グリフのない文字**：フォントにグリフのない文字は、シェイピングの結果が .notdef（グリフ番号 0）になり、そのまま PDF に入る。診断は出ない。
- **PDF に置けない図版**：golem-driver の `Golem.Driver.Pdf.loadFigures` は、`Golem.Pdf.Image.readImage` が読めない画像を `Nothing` にする。`readImage` は JPEG と PNG しか読まないので、PDF の図版も、壊れた画像もここで `Nothing` になる。`figureOf` はその図版の配置を作らないので、コードを読む限り、その図版は PDF に描かれず、診断も出ない（実際の出力では確かめていない）。
- **画像の実効の解像度**：画像の画素数と、紙面に置いた大きさから決まる。どちらも `placeFigure` の中にあるが、比べていない。
- **画像の色空間**：golem-pdf は画像の色を変換しない（[golem-pdf ADR 0001](../../golem-pdf/adr/0001-deterministic-pdf-writer.md)）。RGB の画像は sRGB の ICC プロファイルを付けて ICCBased で埋め込む。PDF/X-4 は ICCBased の RGB を許すが、日本の印刷所の多くは CMYK の入稿を求める。CMYK の画像が出力インテントと違う ICC プロファイルを持つ場合も、そのまま埋め込む。
- **断裁の危険**：仕上がりの線の近くにある文字と画像。v1 は版面の外に図版を置かないが、柱とノンブルはマスターページで版面の外に置く。
- **組めなかった行**：Knuth-Plass の行分割（`Golem.Layout.KnuthPlass`）は、最後の段で行長を超える行を許し、`lineOverfull` を立てる。この印は診断にならない。

### PDF/X-4 の検査の限界

[golem-pdf ADR 0003](../../golem-pdf/adr/0003-pdf-x-4-validator.md) は、PDF/X-4 を判定できる自由な検証器がないことを確かめ、入稿の前の最終確認を商用のプリフライトに委ねた。
`golem preflight` を作っても、この判断は変わらない。
`golem preflight` が検査する PDF/X-4 の要件は、Golem が生成しうる要素に限った自前の検査である。

## 実装すること

### コマンド

```
golem preflight [--rules <ファイル>] [--marks japanese|western|none] [--format human|json]
```

- `golem preflight` は、`golem build --target pdf` と同じ手順で PDF を作り、ファイルに書かずに、組んだ結果と PDF を検査する。
- プロファイル（dev と prod）は常に prod とする。プリフライトは入稿の前の検査であり、dev で警告にとどめる検査（G0310、G0504）も、出荷する本としてエラーにするためである。`--profile` は受け付けず、付ければ使い方の誤りとする。
- `--marks` は `golem build` と同じ意味である。入稿する PDF と同じトンボで検査するためにある。
- `--rules` は、使うプリフライトの設定のファイルを指す（下の「プリフライトの設定」）。パスは作業ディレクトリからの相対パスか絶対パスとし、プロジェクトの外を指してもよい。印刷所から受け取ったファイルを、プロジェクトに入れずに使えるようにするためである。
- `manifest.toml` の `[targets.*]` の有無は見ず、`golem build --target pdf` と同じく常に PDF を組む（[golem-cli ADR 0002](0002-build-all-targets-by-default.md)）。
- 構文、評価、プロジェクト、文書の組み立て、レイアウト、出力の段階の誤りは、`golem build` と同じコードで出す。そのどれかがエラーで PDF を作れなければ、プリフライトの検査は行わない。
- PDF を作れたら、下の検査を行い、その診断を加える。

LSP と `golem check` と `golem build` は、プリフライトの検査を行わない。
`golem build` を速く保ち、ビルドを止めるかどうかの判断を、本ごとの印刷の条件から切り離すためである。

### 終了コード

ほかのコマンドと同じく、エラーの診断が一つもなければ 0、あれば 1、使い方の誤りは 2 とする。
警告だけなら 0 である。
警告でも止めたい人は、プリフライトの設定で重大度を `error` にする。

### 出力

診断は、人が読む形式と JSON の形式で、ほかのコマンドと同じく標準エラー出力に出す。

人が読む形式では、診断の後に、要約の一行を標準エラー出力に加える。

```
プリフライト（設定: preflight.toml、基にした設定: print）: エラー 1、警告 3。検査した PDF の SHA-256: 3f2a…（64 桁）
```

- PDF を作れなかったときは、要約の行を出さない。
- SHA-256 は、検査した PDF のバイト列のものである。Golem は同じ入力と同じオプションから同じバイト列を作るので、`golem build --target pdf --profile prod` に同じ `--marks` を付けて作った PDF と一致する。入稿するファイルが検査したものと同じであることを、この値で確かめられる。
- `--profile prod` を付けずに作った PDF とは一致しない。プロファイルは PDF のインスタンス ID の入力に入っているからである（docs/specifications.md の「識別子」、[golem-pdf ADR 0004](../../golem-pdf/adr/0004-crop-marks-and-bleed.md)）。`golem build` のプロファイルの既定は dev なので、入稿する PDF を `--profile prod` で作ることを、利用者のマニュアルの入稿の手順に書く。
- `--format json` では、要約の行を出さない。

プリフライトの診断は、ページ番号と測った値を持つ。
メッセージに書くだけでは機械が読みにくいので、診断に**事実**（`diagFacts`）の欄を加える（下の「データ構造の変更」）。
JSON では、事実を持つ診断にだけ `"facts"` のオブジェクトを加える。

```json
{"code":"G0906","severity":"warning","span":{...},"message":"図版の実効の解像度が足りません: images/photo.jpg（212ppi、300ppi 未満、PDF の 12 ページ目）","related":[],"fixes":[],"facts":{"pdf-pages":[12],"ppi":212,"limit":300}}
```

`"facts"` のない診断の JSON は、今と変わらない。

ページは、PDF の何ページ目か（1 から数える）で示す。
ノンブルは前付けと本文で数え方が変わり、ページによっては付かないので、位置の特定には使わない。

### 診断のまとめ方

同じ原因の診断がページの数だけ並ぶのを避けるため、検査ごとにまとめの単位を決める（下の各検査の「まとめ」）。
まとめた診断は、最初のページの位置に一つだけ出し、メッセージには最初の十ページまでを書き、それより多ければ `ほか <n> ページ` と添える。
事実の `pdf-pages` には、すべてのページを書く。
InDesign の「エラーごとの行数を制限」に近い働きを、設定なしで既定にする。

### プリフライトの設定

InDesign のプリフライトプロファイルにあたるものを、**プリフライトの設定**と呼ぶ。
「プロファイル」の語は、Golem では dev と prod を指すので使わない。

プリフライトの設定は TOML のファイルに書く。

- `--rules` を付けなければ、プロジェクトのルートの `preflight.toml` を読む。
- `preflight.toml` がなければ、組み込みの `print` を使う。
- 一つのファイルが一つの設定である。InDesign の `.idpp` のように、ファイルごと印刷所と受け渡す。
- 設定を `style.toml` にも `manifest.toml` にも置かない。印刷の条件は印刷所ごとに変わり、本の体裁（`style.toml`）や構成（`manifest.toml`）とは別に差し替えたいからである。

```toml
# 組み込みの設定を基にする。basic、print、none のどれか。省けば print
based-on = "print"
# 要約に出す名前。省けばファイル名
name = "○○印刷 オフセット 菊判"

[image-resolution]
color = { error-below = 150, warning-below = 300 }

[bleed-size]
severity = "error"
min = "3mm"

[page-count]
severity = "error"
multiple-of = 16
```

- 最上位のキーは `based-on` と `name` と、下の検査の名前の表だけである。知らないキーは G0901 とする。
- 各検査の表は、`severity` と、その検査のしきい値のキーを持つ。`severity` は `error`、`warning`、`off` のどれかである（`image-resolution` だけは `severity` を持たず、しきい値で重大度を決める）。
- 書かなかったキーは `based-on` の設定の値を引き継ぐ。表の中のキーごとに引き継ぐ。
- 長さは `style.toml` と同じ書き方（`3mm`、`0.25pt`、`8Q`）とする。`zw` は使えない（G0901）。
- 設定のファイルの誤り（TOML の誤り、知らないキー、値の型、範囲）は、すべて G0901 とし、位置はそのファイルの中の位置とする。

### 組み込みの設定

| 検査 | コード | `basic` | `print` |
| --- | --- | --- | --- |
| `glyph-missing` | G0902 | error | error |
| `font-formats` | G0903 | off | off |
| `type-size` | G0904 | off | warning（5pt 未満、二版以上の色だけ） |
| `image-unplaceable` | G0905 | error | error |
| `image-resolution` | G0906 | なし | 下の表の値 |
| `image-resolution-max` | G0907 | off | off |
| `image-color-space` | G0908 | off | warning（`cmyk` と `gray` を許す） |
| `image-icc` | G0909 | off | warning |
| `bleed-size` | G0910 | off | error（3mm 以上） |
| `bleed-trim-hazard` | G0911 | off | error（3mm） |
| `live-area` | G0912 | off | warning（3mm） |
| `overfull-lines` | G0913 | warning | warning |
| `pdf-x` | G0914 | error | error |
| `ink-coverage` | G0915 | off | warning（350%） |
| `page-count` | G0916 | off | off |
| `blank-pages` | G0917 | off | off |
| `stroke-weight` | G0918 | off | warning（0.1mm 未満） |

`basic` は InDesign の [基本] にあたる。
[基本] の三項目（不明なリンク、オーバーセットテキスト、環境にないフォント）のうち、Golem でビルドを止めないものだけを検査する。
`none` はすべての検査を `off` にした設定で、一から設定を書くときの基にする。

しきい値の既定は、日本の印刷所の入稿の案内でよく見る値（カラーとグレーの画像は 300〜350ppi、二値の画像は 600〜1200ppi、塗り足しは 3mm、文字は仕上がりから 3mm 以上内側、線は 0.1mm 以上）から選んだ。
特定の規格の値ではない。
GWG2015 のような業界の仕様は同じ種類の項目（小さな文字、線の太さ、総インキ量、画像の解像度、二値の画像の解像度）を持つが、その数値はこの ADR を書く時点で原文を確かめられなかった。

### golem new が作る preflight.toml

`golem new` は、プロジェクトのルートに `preflight.toml` を作る。
中身は `based-on = "print"` の一行と、`print` の主な値をコメントで書き写した例である。
和文の雛形（`--language ja`）は次のとおりとする。

```toml
# golem preflight の設定です（入稿の前の検査）。
# 書かなかった値は based-on の設定から引き継ぎます。
# 印刷所から設定のファイルを受け取ったら、このファイルをそれに置き換えます。
based-on = "print"
# name = "○○印刷 オフセット"

# 次の行は print の主な値を書き写したものです。
# 行頭の # を外して、印刷所の求める値に書き換えます。
#
# [image-resolution]
# color = { error-below = 150, warning-below = 300 }
# gray = { error-below = 150, warning-below = 300 }
# bitmap = { error-below = 600, warning-below = 1200 }
#
# [image-color-space]
# severity = "warning"
# allowed = ["cmyk", "gray"]
#
# [bleed-size]
# severity = "error"
# min = "3mm"
#
# [live-area]
# severity = "warning"
# distance = "3mm"
#
# [ink-coverage]
# severity = "warning"
# max = 350

# ページ数を折の単位にそろえる印刷所では、次の行の # を外します（print では off です）。
# [page-count]
# severity = "error"
# multiple-of = 16
```

欧文の雛形（`--language en`）は、同じキーと値を持ち、コメントだけを英語にする。
コメントの言語は、最初の章の原稿と同じく雛形の言語に合わせる。
設定のキーと値は印刷の条件であり、本の言語では変わらないので、言語ごとの組み込みの設定は作らない。

この形を選んだ理由は次のとおりである。

一行の `based-on` にとどめ、`print` の値をすべて書き出さない。
すべてを書き出すと、十七の表のうち v1 の本で意味を持たない検査（`font-formats`、`blank-pages` など）まで並び、利用者が変えた値と引き継いだ値の区別がつかなくなる。
書き出しても、Golem が後の版で加える検査は書いていないので `based-on` から引き継ぐ。
つまり、すべてを書いても値は凍結できず、読みにくさだけが残る。
`based-on` の一行なら、利用者が書き足した行がそのまま `print` との差分になる。

ファイルを作らずに組み込みの `print` に任せることもできる（`preflight.toml` がなければ `print` を使う）。
それでもファイルを置くのは、プリフライトの設定の置き場所と書き方を、マニュアルを開かずに知らせるためである。
要約の行にも `設定: preflight.toml` と出るので、どのファイルを直せばよいかがわかる。

コメントの例の値は、`print` の値と同じにする。
`page-count` を除くコメントを外しても、検査の結果が変わらないようにするためである。
利用者は、一つの値だけを外して書き換えられる。
`page-count` は `print` では `off` なので、例を別の段落に分け、外すと有効になることを書く。

雛形の作成は [golem-cli ADR 0003](0003-new-project-page-and-fonts.md) の仕組みに従う。

- `preflight.toml` は golem-driver の `Golem.Driver.New.templateFiles` の一つとする。取得するファイルではないので、`--no-fonts` を付けても作る。
- フォントの取得に失敗したときは、ほかの雛形のファイルと同じく `preflight.toml` も書かない。
- 実装のときに、[golem-cli ADR 0003](0003-new-project-page-and-fonts.md) のステータスの行の値を「採択→雛形の `preflight.toml` は [ADR 0006](0006-preflight.md)」に改める。

雛形のプロジェクトは、そのままでは `print` のプリフライトを通らない。
`style.toml` に `[page] bleed` と `[color] intent` がないので、G0910（塗り足しの幅の不足）と G0914（出力インテントがない）がエラーになる。
雛形の `style.toml` は変えない。
出力インテントの ICC プロファイルは Golem が持たず、印刷所ごとに違うので、雛形に書けない。
塗り足しだけを雛形に入れても、プリフライトは G0914 で止まる。
また、塗り足しを入れると、画面で読むための PDF にも塗り足しの分の余白が付く。
この二つのエラーは、マニュアルの入稿の手順の一つ目（`bleed` と `intent` を書く）とそのまま対応するので、プリフライトがその手順の残りを示す形になる。

### 検査

各検査について、条件、メッセージ、位置、まとめ、設定のキーを定める。
長さの比較は、PDF のユーザー空間の単位（1/72 インチ）を Golem の内部の単位（sp）に直した整数で行う。
メッセージの長さは mm で、小数点以下一桁に丸めて書く。

#### G0901 プリフライトの設定の誤り

- **条件**：`--rules` のファイル、または `preflight.toml` が読めない（ない、UTF-8 でない）、TOML として読めない、スキーマに合わない。`based-on` が `basic`、`print`、`none` のどれでもない。しきい値が負。`image-resolution` の `error-below` が `warning-below` より大きい。
- **重大度**：エラー（設定で変えられない）。
- **メッセージ**：TOML の誤りは [golem-project ADR 0007](../../golem-project/adr/0007-toml-messages-in-japanese.md) の日本語の文言。ほかは `<キー> の値が正しくありません: <値>（<理由>）`。`--rules` のファイルがなければ `プリフライトの設定のファイルがありません: <パス>`。
- **位置**：そのファイルの中の位置。ファイルがないときは、そのファイルの FileId の先頭。
- G0901 があれば、PDF を組まずに終える。

#### G0902 グリフのない文字（`glyph-missing`）

- **条件**：シェイピングの結果のグリフ番号が 0（.notdef）である。原稿の文字、番号の文字列、柱、ノンブル、目次と索引の文字列のすべてを対象とする。
- **メッセージ**：`フォントにグリフのない文字です: U+<16 進数>「<文字>」（<フォントのパス>、PDF の <ページ> ページ目）`。制御文字と結合文字は「」の中を省く。
- **位置**：その文字を含む原稿の `Text` の位置。原稿の外の文字（柱、ノンブル）は `style.toml` の先頭。
- **まとめ**：符号位置とフォントのファイルの組ごとに一つ。
- **事実**：`code-point`（文字列）、`font`（パス）、`pdf-pages`、`count`（出現の数）。

#### G0903 許さない形式のフォント（`font-formats`）

- **条件**：PDF に埋め込んだフォントの形式が、`allowed` にない。形式は、`CFF ` の表を持つ OpenType を `cff`、`glyf` の表を持つものを `truetype` とする。
- **キー**：`allowed`（文字列の配列。既定は `["cff", "truetype"]`）。
- **メッセージ**：`この設定では使えない形式のフォントです: <パス>（<形式>）`
- **位置**：`style.toml` の先頭。
- **まとめ**：フォントのファイルごとに一つ。

#### G0904 小さすぎる文字（`type-size`）

- **条件**：文字の大きさが `min-size` 未満である。`multi-ink-only` が真なら、文字の色が二つ以上の版を使う（スウォッチの C、M、Y、K のうち 0 でない値が二つ以上ある）場合だけを対象とする。ルビと圏点も文字に含める。
- **キー**：`min-size`（長さ）、`multi-ink-only`（真偽値）。
- **メッセージ**：`文字が小さすぎます: <大きさ>（<min-size> 未満、色 <スウォッチの名前>、PDF の <ページ> ページ目）`
- **位置**：その文字を含む原稿の `Text` の位置。
- **まとめ**：段落スタイルか文字スタイルと色の組ごとに一つ。
- 二版以上の小さな文字を見るのは、版のずれで文字がにじむためである。InDesign の「最小文字サイズ」にも、複数のインキを使う文字だけに当てる指定がある。

#### G0905 PDF に置けない図版（`image-unplaceable`）

- **条件**：`@figure` の画像のファイルはあるが、`readImage` が読めない（JPEG と PNG でない、壊れている、対応しない形式の JPEG と PNG）。
- **メッセージ**：`図版を PDF に置けません: <パス>（<readImage の文言>）`
- **位置**：その `@figure` のブロック。
- **まとめ**：`@figure` ごとに一つ。
- PDF の図版を `golem build` で黙って落とすことは、別の ADR でビルドの誤りにするかどうかを決める（「実装しないこと」）。

#### G0906 実効の解像度の不足（`image-resolution`）

- **条件**：画像の実効の解像度が、その画像の種類の `warning-below` か `error-below` 未満である。
- **実効の解像度**：紙面に置いた画像の幅を w（インチ）、高さを h（インチ）、画素数を W × H として、`min(W / w, H / h)` の小数点以下を切り捨てた整数（ppi）。
- **画像の種類**：一ビットのグレーの画像を `bitmap`、ほかのグレーの画像を `gray`、RGB、CMYK、パレットの画像を `color` とする。
- **キー**：`color`、`gray`、`bitmap` の三つの表。それぞれ `error-below` と `warning-below`（ppi の整数）を持つ。0 はその段の検査をしない。
- **既定（`print`）**：`color` と `gray` は `error-below = 150`、`warning-below = 300`。`bitmap` は `error-below = 600`、`warning-below = 1200`。
- **重大度**：`error-below` 未満ならエラー、そうでなく `warning-below` 未満なら警告。
- **メッセージ**：`図版の実効の解像度が足りません: <パス>（<ppi>ppi、<しきい値>ppi 未満、PDF の <ページ> ページ目）`
- **位置**：その `@figure` のブロック。
- **まとめ**：`@figure` ごとに一つ。
- **事実**：`ppi`、`limit`、`pixels`（`[W, H]`）、`pdf-pages`。

#### G0907 実効の解像度の過剰（`image-resolution-max`）

- **条件**：実効の解像度が、その画像の種類の `max` を超える。
- **キー**：`color-max`、`gray-max`、`bitmap-max`（ppi の整数。0 は検査しない）。
- **メッセージ**：`図版の実効の解像度が高すぎます: <パス>（<ppi>ppi、<しきい値>ppi 超）`
- 位置、まとめ、事実は G0906 と同じ。
- PDF の大きさを抑えたい入稿先のためにある。Golem は画像を縮小しないので、直し方は画像のファイルを作り直すことである。

#### G0908 許さない色空間の図版（`image-color-space`）

- **条件**：画像の色空間が `allowed` にない。色空間は、`readImage` の `ColorSpace` から、`CsGray` を `gray`、`CsRgb` と `CsIndexed` を `rgb`、`CsCmyk` を `cmyk` とする。
- **キー**：`allowed`（既定は `["cmyk", "gray"]`）。
- **メッセージ**：`この設定では使えない色空間の図版です: <パス>（<色空間>）。Golem は画像の色を変換しないので、CMYK に変換した画像に替えます`
- **位置**、**まとめ**：G0906 と同じ。
- RGB の画像は PDF/X-4 では許されるので、`print` の既定を警告にする。

#### G0909 出力インテントと違うプロファイルの CMYK の図版（`image-icc`）

- **条件**：CMYK の画像が ICC プロファイルを埋め込んでおり、そのバイト列が `style.toml` の `[color] intent` のファイルのバイト列と一致しない。
- **メッセージ**：`出力インテントと違う ICC プロファイルを持つ CMYK の図版です: <パス>。印刷の工程で色が変換されることがあります`
- **位置**、**まとめ**：G0906 と同じ。
- バイト列で比べるので、同じ特性の別の版のプロファイルも違うとみなす。
- `[color] intent` がなければ、この検査は何も出さない。出力インテントがないことは G0914 が報告する。

#### G0910 塗り足しの幅の不足（`bleed-size`）

- **条件**：`style.toml` の `[page] bleed` が `min` 未満である。
- **キー**：`min`（長さ）。
- **メッセージ**：`塗り足しの幅が足りません: <bleed>（<min> 以上にします）`
- **位置**：`style.toml` の先頭（`style.toml` がなければ `manifest.toml` の先頭）。
- InDesign の「裁ち落としと印刷可能領域の設定」にあたる。

#### G0911 断裁の危険域の図版（`bleed-trim-hazard`）

- **定義**：ページの仕上がりの矩形を T、`[page] bleed` を B、設定の `distance` を d とする。画像の矩形 R の各辺について、R の辺が T の対応する辺の内側に d 未満まで近づいているか、T の辺を越えているが、T の辺から外へ B の位置（塗り足しの線）まで届いていないとき、その辺は**断裁の危険域にある**とする。辺の向きで測った R の辺から T の辺までの距離を e（内側を正）として、`-B < e < d` のときである。
- **条件**：画像のどれかの辺が断裁の危険域にある。
- **キー**：`distance`（長さ）。
- **メッセージ**：`図版が仕上がりの線の近くにあり、塗り足しまで届いていません: <パス>（<辺>、仕上がりの線から <e>、PDF の <ページ> ページ目）`。辺は「天」「地」「小口」「のど」で書く。
- **位置**、**まとめ**：G0906 と同じ。
- InDesign の「裁ち落としとトリミングの危険」にあたる。v1 の図版は版面の中に置くので、版面の余白が d 以上ある本ではこの検査は何も出さない。版面の外に図版を置く機能（v2 以降）が入ったときに、そのまま効く。

#### G0912 断裁の危険域の文字と線（`live-area`）

- **条件**：文字の行の矩形、または線の矩形が、仕上がりの矩形 T を各辺から `distance` だけ内側に縮めた矩形（**安全域**）からはみ出す。文字の行の矩形は、行の字面の範囲（行頭から行末、文字の大きさの高さ）とする。トンボは対象にしない。
- **キー**：`distance`（長さ）。
- **メッセージ**：`文字が仕上がりの線に近すぎます: <要素>（<辺>、仕上がりの線から <距離>、PDF の <ページ> ページ目）`。要素は「柱」「ノンブル」「本文の行」「表の罫線」などで書く。
- **位置**：本文の行は原稿の位置、柱とノンブルは `style.toml` の先頭。
- **まとめ**：要素の種類と辺の組ごとに一つ。柱とノンブルは全ページで同じ位置になるので、一つにまとまる。

#### G0913 行長からはみ出す行（`overfull-lines`）

- **条件**：行分割の結果の行に `lineOverfull` が立っている。
- **メッセージ**：`行が行長から <量> はみ出しています（PDF の <ページ> ページ目）`。量は mm で書く。
- **位置**：その行の最初の文字を含む原稿の `Text` の位置。
- **まとめ**：行ごとに一つ。
- InDesign の「オーバーセットテキスト」に最も近い。Golem の本文はフレームから溢れないので、組めなかった行をこの検査で拾う。

#### G0914 PDF/X-4 の要件（`pdf-x`）

- **条件**：検査した PDF が、[golem-pdf ADR 0002](../../golem-pdf/adr/0002-pdf-x-4.md) の要件のどれかを満たさない。
- 検査は、golem-pdf に加える `Golem.Pdf.X4.verify` が、書く前の PDF のオブジェクトに対して行う。項目は、PDF の版、出力インテントの辞書と `DestOutputProfile`、XMP の `GTS_PDFXVersion` と `Trapped`、各ページのボックス（今の `checkPdfX`）、フォントの埋め込み、ICC プロファイルのない RGB の色空間の不在、暗号化と JavaScript と外部への参照の不在である。今の golem-pdf のテストは、同じ関数を使うように改める。
- **メッセージ**：`PDF/X-4 の要件を満たしていません: <要件>（<詳細>）`
- **位置**：`style.toml` の先頭（`style.toml` がなければ `manifest.toml` の先頭）。
- **まとめ**：要件ごとに一つ。
- `style.toml` の `[color] intent` がないときは、Golem は出力インテントも PDF/X の XMP も書かない（[golem-pdf ADR 0002](../../golem-pdf/adr/0002-pdf-x-4.md)）。このとき、そこから続く要件の不足（出力インテントの辞書、`GTS_PDFXVersion` など）を並べず、`PDF/X-4 の要件を満たしていません: 出力インテントがありません（style.toml の [color] に intent を書きます）` の一つにまとめる。原因が一つの設定の欠けなので、直し方を一つだけ示すためである。
- この検査は PDF/X-4 の適合の判定ではない。要約の行と利用者のマニュアルに、入稿の前に商用のプリフライトで確かめることを書く（[golem-pdf ADR 0003](../../golem-pdf/adr/0003-pdf-x-4-validator.md)）。

#### G0915 総インキ量（`ink-coverage`）

- **条件**：紙面で使った色（文字、線、地の色）のスウォッチの C、M、Y、K の値の和が `max` を超える。
- **キー**：`max`（パーセントの整数）。
- **メッセージ**：`色の総インキ量が多すぎます: <スウォッチの名前>（<和>%、<max>% 超）`
- **位置**：`style.toml` の先頭。
- **まとめ**：スウォッチごとに一つ。
- 画像の画素の総インキ量は検査しない（「実装しないこと」）。
- 既定の 350% は、Japan Color 2001 Coated の条件の入稿の案内で見かける値として選んだ。規格の文書では確かめていない。

#### G0916 ページ数（`page-count`）

- **条件**：PDF のページ数が `multiple-of` の倍数でない。
- **キー**：`multiple-of`（正の整数。既定の `off` のときの値は 1）。
- **メッセージ**：`ページ数が <multiple-of> の倍数ではありません: <ページ数>（あと <差> ページ）`
- **位置**：`manifest.toml` の先頭。
- 折の単位（16 ページなど）で台割を組む印刷所のためにある。

#### G0917 空白のページ（`blank-pages`）

- **条件**：ページに、マスターページの要素（柱、ノンブル）のほかに描くものがない。
- **メッセージ**：`空白のページです（PDF の <ページ> ページ目）`
- **位置**：`manifest.toml` の先頭。
- **まとめ**：一つにまとめ、すべての空白のページを並べる。
- Golem は右起こしの改ページ（`page-break = "recto"`）で空白のページを意図して作るので、既定は `off` とする。

#### G0918 細すぎる線（`stroke-weight`）

- **条件**：Golem が描く線（表の罫線など）の太さが `min` 未満である。トンボの線は対象にしない。
- **キー**：`min`（長さ）。
- **メッセージ**：`線が細すぎます: <線の種類>（<太さ>、<min> 未満、PDF の <ページ> ページ目）`
- **位置**：`style.toml` の先頭。
- **まとめ**：線の種類ごとに一つ。
- v1 の表の罫線（0.6pt と 0.3pt、[golem-driver ADR 0008](../../golem-driver/adr/0008-pdf-tables.md)）は、既定の 0.1mm（約 0.28pt）以上なので、何も出さない。

### 重大度の扱い

G0902 から G0918 の重大度は、プリフライトの設定で決まる。
`Golem.Syntax.Diagnostic` に `preflightCodes :: [DiagnosticCode]` を置き、docs/diagnostics.md のこれらの節の重大度の欄は「プリフライトの設定による」と書き、`print` の既定を添える。
`profileDependentCodes` と `noticeCodes` には入れない。
お知らせ（[golem-syntax ADR 0002](../../golem-syntax/adr/0002-notice-severity.md)）は、設定の値として選べない。
お知らせは抑制できる重大度であり、印刷所が求める検査を手元で消せると、設定のファイルを受け渡す意味が薄れるからである。
docs/diagnostics.md と各一覧の一致を確かめる golem-driver のテストは、`preflightCodes` も照合する。

### 診断のコードの区分

上 2 桁の 09 をプリフライトの区分とする。
docs/diagnostics.md の「番号の区分」の表に、`09 | プリフライト | golem-preflight` を加える。
G0901 から G0918 をこの ADR が使う。

### モジュール

- **golem-preflight**（新しいパッケージ）：プリフライトの設定の型と読み込み（`Golem.Preflight.Rules`）、検査の入力（`Golem.Preflight.View`）、検査（`Golem.Preflight.check :: Rules -> View -> [Diagnostic]`）を持つ。I/O を持たない純粋な関数だけにする。golem-project（TOML の読み込みと長さ）、golem-syntax、golem-pdf（`ImageData`、`X4.verify`）に依存する。
- **golem-driver**：`Golem.Driver.preflight :: PreflightOptions -> IO PreflightResult` を加える。ビルドの手順を PDF まで進め、PDF のバイト列とともに `View` を作り、golem-preflight の検査を呼ぶ。
- **golem-cli**：`preflight` のコマンドと要約の行を加える。

### データ構造の変更

`Golem.Syntax.Diagnostic`：

```haskell
data Fact = FactInt Integer | FactText Text | FactInts [Integer] | FactTexts [Text]

data Diagnostic = Diagnostic
  { ...
  , diagFacts :: ![(Text, Fact)]   -- 機械が読む事実（golem-cli ADR 0006）。空なら JSON に出さない
  }
```

`diagnostic` と `notice` は `diagFacts` を空にして作る。
`renderJson` は、`diagFacts` が空でないときだけ `"facts"` を書く。
人が読む形式は事実を表示しない（メッセージに同じことを書く）。

`Golem.Preflight.View`（golem-driver が作る）：

```haskell
data View = View
  { vwPages :: [PageView],
    vwFonts :: [FontView],          -- 埋め込んだフォント：パス、形式
    vwSwatchesUsed :: Map Text Cmyk,
    vwBleed :: Sp,
    vwIntentProfile :: ByteString,
    vwX4 :: [X4Problem],
    vwPdf :: ByteString
  }

data PageView = PageView
  { pvIndex :: Int,                 -- PDF の何ページ目か（1 から）
    pvTrim :: Rect,
    pvImages :: [ImageView],        -- 置いた矩形、ImageData、@figure の位置、パス
    pvLines :: [LineView],          -- 行の矩形、要素の種類、原稿の位置、overfull の量
    pvGlyphs :: [GlyphView],        -- 符号位置、フォント、グリフ番号、大きさ、色、原稿の位置
    pvRules :: [RuleView],          -- 線の種類、太さ、矩形
    pvBlank :: Bool
  }
```

`Golem.Driver.Pdf` は、PDF を書く途中で持っている値（`placeFigure` の矩形、行分割の `Line`、シェイピングの結果、表の罫線）から `View` を作る。
`View` を作るのは `preflight` のときだけとし、`golem build` の速さと出力を変えない。

### ドキュメント

- docs/specifications.md の「CLI」の表に `golem preflight` を加え、プリフライトの設定、組み込みの設定、終了コード、要約の行、検査が PDF/X-4 の適合の判定ではないことを書く。この ADR へリンクする。
- 同じく「構文木と診断」に、診断の事実（`facts`）と JSON の形を書く。
- 同じく「今後の実装項目」の「CLI と LSP」から「プリフライト」の項を除く。「v1 の実装で次の段階以降に回した項目」に、PDF に置けない図版を `golem build` のエラーにするかどうかを決める項目を加える。
- docs/diagnostics.md の「番号の区分」に 09 を加え、G0901 から G0918 の節を加える。
- docs/glossary.md に「プリフライト」「プリフライトの設定」「実効の解像度」「断裁の危険域」「安全域」を加える。
- README の CLI の説明に `golem preflight` を加え、「入稿する前には商用のプリフライトで確認する」の文に、その前に `golem preflight` を通すことを加える。
- [golem-cli ADR 0001](0001-command-line-interface.md) のステータスの行に「`golem preflight` は [ADR 0006](0006-preflight.md)」を加える。
- docs/specifications.md の `golem new` の説明に、雛形に `preflight.toml` が入ることを加える。README の `golem new` の説明も同じく直す。
- 利用者のマニュアル（`manual/`）を次のように直す（[docs/adr/0024](../../adr/0024-manual-audiences-and-policy.md)）。
  - 第1章「インストールと最初の一冊」の「プロジェクトを作る」の節のファイルの一覧に、`preflight.toml`（入稿の前の検査の設定。第6章で使う）を加える。この章では `golem preflight` を実行しない。雛形のままではエラーになり、最初の一冊を組む流れを途切れさせるからである。
  - 第6章「出力」の「塗り足しとトンボ」の後に、「入稿の前の検査」の節を加える。雛形のプロジェクトに `golem preflight` を実行して G0910 と G0914 が出る様子を示し、`bleed` と `intent` を書いて `golem preflight --marks japanese` が通るまでを手順として書く。最初の実行に `--marks japanese` を付けないのは、塗り足しが 0 の雛形では G0702 で PDF を作れず、プリフライトの検査まで進まないからである。続けて、`preflight.toml` の `based-on` と書き換え方、印刷所から受け取ったファイルの使い方（置き換えるか `--rules` で指す）、組み込みの設定、要約の行の SHA-256 と `--profile prod` の関係、検査が PDF/X-4 の適合の判定ではないことを書く。同じ章の入稿の手順の箇条に、「`golem preflight --marks japanese` で検査する」を、商用のプリフライトの前の手順として加える。InDesign のプリフライトプロファイルとの対応もこの節に書く。
  - 第8章「版の管理と CI」の「CI で毎回組む」の節に、入稿の前の CI で `golem preflight` を走らせる例を加える。
  - `preflight.toml` のリファレンスを付録D「preflight.toml のリファレンス」（`manual/appendices/d-preflight.gm`、ラベル `app-preflight`）として、付録C の後ろに加える。設定のファイルのリファレンス（付録B、付録C）の並びに置くためである。`based-on` と `name`、検査ごとの表のキー、型、`print` の既定、組み込みの設定の表を、付録B と付録C と同じ形で書く。
  - 後ろの付録を一つずつ繰り下げる。今の付録D「診断の一覧」は付録E、付録E「InDesign との対応」は付録F、付録F「用語の一覧」は付録G になる。ファイルの名前も文字に合わせて `e-errors.gm`、`f-indesign.gm`、`g-glossary.gm` に改め、`manual/manifest.toml` の `chapters` を直す。
  - 本文と付録で手で書いた付録の文字を、すべて新しい文字に直す。origin/main の今の箇所は次のとおりである。各付録の見出し（`# 付録D 診断の一覧`、`# 付録E InDesign との対応`、`# 付録F 用語の一覧`）、`manual/preface.gm` の「付録D で引けます」と「付録E にまとめました」、`manual/chapters/10-plugins.gm` の「付録D」、`manual/appendices/f-glossary.gm` の「付録E」と「付録D」。付録A、付録B、付録C への参照は変わらない。実装のときに `付録[D-G]` で manual/ を検索し直し、ほかの ADR の実装で増えた箇所も直す。
  - 付録E「診断の一覧」（今の付録D）に、「プリフライト」の節を加え、G0901 から G0918 を載せる。
  - 付録F「InDesign との対応」（今の付録E）の表の `golem check` の行の「プリフライトの一部」を改め、`golem preflight` とプリフライトプロファイル（`preflight.toml`）の行を加える。docs/manual-policy.md の対応の表にも同じ行を加える。
  - 付録G「用語の一覧」（今の付録F）に、docs/glossary.md に加える語を加える。
- 開発者のマニュアル（`manual-dev/`）を次のように直す。
  - `manual-dev/part1/01-cli.gm`：「コマンドの一覧」の表に `golem preflight` を、「終了コード」に `golem preflight` の終了コードを、「プロジェクトの雛形」に `preflight.toml` を加える。
  - `manual-dev/part1/02-diagnostics.gm`：「JSON の形式」に `"facts"` の欄と、それを持つ診断を書く。「診断のコード」の区分の表に 09 を加える。
  - `manual-dev/part1/03-ci.gm`：「組んで、結果を読む」の後に、入稿の前の CI で `golem preflight --format json` を走らせ、`facts` と要約の SHA-256 を読む例を加える。
  - `manual-dev/part2/07-modules.gm`：「モジュールの一覧」に golem-preflight を加える。
- `scripts/release/check-version.sh` が全パッケージの版を照合するので、golem-preflight の cabal ファイルの `version` もそろえる。`cabal.project` に golem-preflight を加える。

## 実装しないこと

- 透明、オーバープリント、白のオーバープリント、特色、CMY の版の検査。v1 の Golem は透明もオーバープリントも特色も出さない（トンボのレジストレーションの色を除く）。
- 画像の画素の総インキ量と、画像の中の特色。画素を走査する費用が大きく、v1 の画像は変換しないので、画像を作った側で確かめるほうがよい。
- ページのサイズと向きの検査。判型は `style.toml` で決まり、PDF のボックスとの不一致は G0914 が拾う。
- ページの範囲を絞った検査、層や印刷しない要素の扱い。Golem にはどちらもない。
- 報告を PDF に保存すること。JSON を変換すれば足りる。
- InDesign の `.idpp` の読み込み。形式が公開されていない。
- プリフライトの設定を PDF に埋め込むこと。
- 検査した PDF を書き出すこと。`golem build` で書き、要約の SHA-256 で一致を確かめる。
- LSP、`golem check`、`golem build` でプリフライトの検査を行うこと。`preflight.toml` の誤り（G0901）も `golem preflight` だけが報告する。
- 雛形の `style.toml` に `bleed` と `intent` を入れること（上の「golem new が作る preflight.toml」）。
- 言語ごとの組み込みの設定と、既存のプロジェクトに `preflight.toml` を後から作るコマンド。ファイルがなければ `print` を使うので、後から作る必要はない。
- PDF の図版を `golem build` で黙って落とすことを直すこと。ビルドの振る舞いの変更なので、別の ADR で決める。
- 自由に使える PDF/X-4 の検証器を組み込むこと（[golem-pdf ADR 0003](../../golem-pdf/adr/0003-pdf-x-4-validator.md) のまま）。

## テスト設計

### 先に書いて失敗させるテスト

`modules/golem-preflight/test`（`View` を手で作って検査する。I/O なし）：

- **設定**：組み込みの `basic`、`print`、`none` の各検査の値が上の表のとおりであること。`based-on = "print"` に `[image-resolution] color = { warning-below = 350 }` だけを書くと、`color` の `error-below` は 150 のまま、`warning-below` が 350 になること。知らない最上位のキー、知らない検査のキー、`severity = "notice"`、`min = "1zw"`、`error-below` が `warning-below` より大きい設定が、それぞれ G0901 で、位置がそのキーの行であること。
- **G0902**：グリフ番号 0 の `GlyphView` が三ページにある `View` で、G0902 が一つだけ出て、`pdf-pages` が三つのページであり、`count` が出現の数であること。グリフ番号が 0 でなければ出ないこと。
- **G0903**：`allowed = ["cff"]` で `truetype` のフォントが G0903 になること。
- **G0904**：K100 の 4pt の文字は `multi-ink-only = true` で出ず、C100 K100 の 4pt の文字は出ること。`multi-ink-only = false` では両方出ること。5pt の文字は出ないこと。
- **G0905**：読めない画像の `@figure` が G0905 になること（golem-driver の `View` の作成の側のテストでも確かめる）。
- **G0906**：画素数 1200 × 900 の color の画像を 4in × 3in に置くと 300ppi で何も出ず、6in × 4.5in に置くと 200ppi で警告、10in × 7.5in に置くと 120ppi でエラーになること。縦と横で解像度が違うとき、小さいほうを使うこと（1200 × 600 を 4in × 3in に置くと 200ppi）。一ビットのグレーの画像に `bitmap` のしきい値が使われること。`error-below = 0` で、その段の検査をしないこと。
- **G0907**：`color-max = 600` で 700ppi の画像が出ること。
- **G0908**：RGB の画像が `print` で警告になり、CMYK とグレーの画像は出ないこと。パレットの画像が `rgb` とみなされること。
- **G0909**：出力インテントと同じバイト列の ICC を持つ CMYK の画像は出ず、違うバイト列なら出ること。ICC のない CMYK の画像は出ないこと。
- **G0910**：`bleed = 2mm` が `print` でエラーになり、`3mm` で出ないこと。
- **G0911**：B = 3mm、d = 3mm で、R の小口の辺が仕上がりの線の 2mm 内側にある画像が出ること、5mm 内側にある画像は出ないこと、仕上がりの線ちょうど（e = 0）の画像が出ること、塗り足しの線まで伸びた画像（e = -3mm）は出ないこと、仕上がりの線の 1mm 外まで伸びた画像（e = -1mm）は出ること。B = 0 のとき、仕上がりの線ちょうどの画像が出ること。
- **G0912**：仕上がりの線から 2mm の位置のノンブルが、全ページで一つの G0912 にまとまること。トンボの線が対象にならないこと。
- **G0913**：`lineOverfull` の行が G0913 になり、量が mm の小数点以下一桁で書かれること。
- **G0914**：`X4Problem` を一つ持つ `View` が G0914 になること。`pdf-x` を `off` にすると出ないこと。出力インテントのない `View` では、続く要件の不足があっても G0914 が一つだけ出ること。
- **G0909**：出力インテントのない `View` では、ICC を持つ CMYK の画像があっても出ないこと。
- **G0915**：C100 M100 Y100 K100（400%）のスウォッチを文字に使うと出て、使わなければ出ないこと。
- **G0916**：`multiple-of = 16` で 130 ページの PDF が G0916 で `あと 14 ページ` を含むこと。
- **G0917**：柱とノンブルだけのページが G0917 になること。既定（`off`）では出ないこと。
- **G0918**：0.2pt の線が `print` で出て、0.3pt の線は出ないこと。
- **まとめ**：十二ページにまたがる診断のメッセージが、十ページを並べて `ほか 2 ページ` で終わること。

`modules/golem-syntax/test`：

- `diagFacts` が空の診断の `renderJson` が今と同じバイト列であること。事実を持つ診断に `"facts":{...}` が加わり、キーが書いた順に並ぶこと。

`modules/golem-pdf/test`：

- `Golem.Pdf.X4.verify` が、今の PDF/X-4 の要件のテストの各項目（出力インテントがない、`GTS_PDFXVersion` がない、`TrimBox` がない、埋め込まないフォント、ICC のない RGB）を、それぞれ一つの `X4Problem` として返すこと。Golem が今書く PDF には何も返さないこと。

`modules/golem-driver/test/Main.hs`：

- テストのフォントで組めるプロジェクトの `preflight` で、PDF のバイト列が同じプロジェクトを prod で `build` した PDF と一致し、dev で `build` した PDF とは一致しないこと。
- `View` の作成：仕上がりの矩形、画像の置いた矩形、ノンブルの行の矩形、表の罫線の太さが、組んだ結果と一致すること。テストのフォントにない文字（私用領域の U+E000）を書いた原稿で、グリフ番号 0 の `GlyphView` が作られること。
- JPEG と PNG 以外の画像（PDF のファイル）を `@figure` に書いた原稿で、G0905 が出ること。
- dev でだけ警告になる診断（G0504）が、`preflight` ではエラーになること。
- docs/diagnostics.md の重大度の欄と `preflightCodes` が一致すること。
- 雛形（`Golem.Driver.New`）：言語ごとに、`templateFiles` の `preflight.toml` を golden テストで固定する。和文と欧文の `preflight.toml` から、`#` で始まる行を除いた部分が同じであること。`--no-fonts` に当たる指定でも `preflight.toml` が作られること。偽の取得の関数が失敗を返すとき、`preflight.toml` も書かれないこと。
- 雛形の `preflight.toml` を読んだ設定が、診断なしで読め、組み込みの `print` と等しいこと。`[page-count]` の段落を除くコメントの例の行の先頭の `# ` を外した設定も、`print` と等しいこと。`[page-count]` の段落の `# ` も外すと、`page-count` だけが `print` と違うこと。
- 偽のフォントを置いた雛形のプロジェクトを言語ごとに `preflight` にかけると、エラーが G0910 と G0914 の二つだけであり、G0914 が出力インテントの欠けの一つにまとまっていること。`style.toml` に `bleed = "3mm"` と、テストの ICC プロファイルを指す `[color] intent` を足すと、エラーがなくなること。

`modules/golem-cli/test/Main.hs`：

- `golem preflight` がエラーのないプロジェクトで終了コード 0 を返し、警告だけのプロジェクトで 0、G0902 のあるプロジェクトで 1 を返すこと。
- `golem preflight --profile dev` と `golem preflight --rules` （値なし）が終了コード 2 になること。
- 人が読む形式の最後の行が `プリフライト（` で始まり、`SHA-256: ` に続く 64 桁の 16 進数が、同じプロジェクトを `golem build --target pdf --profile prod` した PDF の SHA-256 と一致すること。
- `--format json` の出力が JSON として正しく、要約の行を含まず、G0906 の診断が `facts` の `ppi` を持つこと。
- `--rules` で指したプロジェクトの外のファイルが読まれること。`--rules` の指すファイルがなければ G0901 になること。

### 自動テストにしない確かめ方

- マニュアル（`manual/`）を `golem preflight` にかけ、出た診断を一つずつ PDF の該当するページと照らす。誤検出がないことを確かめる。
- 同じマニュアルの PDF を Acrobat のプリフライト（PDF/X-4 の適合の検査）にかけ、Golem の G0914 が出なかった PDF で Acrobat が PDF/X-4 の誤りを報告するかを記録する。差があれば、`X4.verify` に足すべき要件を ADR にする。結果は `docs/audits/` に残す。
- 72ppi の RGB の画像と、仕上がりの線の近くに柱を置いた `style.toml` の本を作り、InDesign で同じ条件の文書を作ってプリフライトにかけ、同じ種類の問題が両方で出ることを確かめる（InDesign が手元にある場合）。

## トレードオフ

プリフライトのために PDF を一度組むので、`golem preflight` は `golem build --target pdf` と同じくらい時間が掛かる。
PDF を書かないのでディスクには触れないが、CI で両方を走らせると組版を二度行う。
`golem build` に検査を混ぜれば一度で済むが、ビルドの合否が印刷所の設定で変わることになる。
ビルドは原稿と設定の誤りで、プリフライトは印刷の条件で止まる、という分け方を優先した。

プリフライトの設定を独立したファイルにしたので、プロジェクトの設定のファイルが一つ増える。
本の体裁と印刷の条件を分けておけば、同じ本を別の印刷所に出すときに `--rules` だけを替えられる。
`golem new` がこのファイルを作るので、雛形のファイルも一つ増える。
その代わり、設定の置き場所を探す手間がなくなる。

雛形の `preflight.toml` は `print` を名前で参照するので、Golem の版が上がって `print` の値が変われば、同じ `preflight.toml` でも検査の結果が変わる。
値をすべて書き出せば書いた値は固定できるが、上に書いたとおり、新しい検査は引き継がれるので固定しきれない。
`print` の値を変えるときは ADR を書き、リリースノートの「変更」に挙げる。

雛形のプロジェクトはそのままではプリフライトを通らない。
「雛形から始めればすぐ入稿できる」とは言えないが、出力インテントのない PDF を入稿できる PDF として通すよりはよい。

既定のしきい値は、どの規格の数値でもない。
印刷所ごとに求める値が違う以上、既定は代表的な値にとどめ、正しい値は印刷所の設定のファイルで与えてもらうしかない。
InDesign のヘルプも、プロファイルは印刷会社に問い合わせて入手するよう勧めている。

InDesign のプリフライトの項目はすべて「エラー」として一覧に出るが、Golem はエラーと警告を分ける。
CI の終了コードで入稿の可否を決めるには、刷れないものと確かめてほしいものを区別する必要があるためである。

`View` を作る費用は `golem preflight` のときだけ払う。
その代わり、`View` に何を入れるかを PDF の書き手（`Golem.Driver.Pdf`）と検査の両方で保つ必要がある。
検査を PDF のバイト列の解析で行えば `View` は要らないが、PDF を読む部品を作ることになり、原稿の位置も失う。

## 参考文献

- Adobe, InDesign User Guide, "Preflighting files before handoff", https://helpx.adobe.com/indesign/using/preflighting-files-handoff.html （日本語版「ファイルのプリフライトチェック」, https://helpx.adobe.com/jp/indesign/using/preflighting-files-handoff.html ）
- ISO 15930-7:2010 Graphic technology — Prepress digital data exchange using PDF — Part 7: Complete exchange of printing data (PDF/X-4) and partial exchange of printing data with external profile reference (PDF/X-4p) using PDF 1.6
- Ghent Workgroup, GWG2015 PDF/X workflow, https://www.gwg.org/gwg-2015-pdf-x-workflow/
- Microsoft, OpenType specification, OS/2 table `fsType`, https://learn.microsoft.com/en-us/typography/opentype/spec/os2
- 日本印刷産業機械工業会, Japan Color 2001 Coated
