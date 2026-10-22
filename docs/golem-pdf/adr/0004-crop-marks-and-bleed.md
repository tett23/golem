# ADR 0004: トンボと塗り足し

ステータス: 採択→トンボの色は [ADR 0007](0007-registration-crop-marks.md)、`golem check` が G0702 を出す条件は [ADR 0010](0010-golem-check-g0702-and-template-bleed.md)（`golem check` が四つのターゲットを検査することは [golem-project ADR 0004](../../golem-project/adr/0004-font-file-check-per-target.md)）

## 文脈

印刷所に入稿する PDF には、仕上がりの判型の外側に塗り足しの領域と、断裁の位置を示すトンボを付けることが多い。
日本の印刷所の多くは、塗り足しを 3mm とし、日本式の二重のトンボを付けた単ページの PDF を求める。
欧文の印刷所では一重のトンボが使われ、オンデマンド印刷のように、トンボを付けずに塗り足しだけを含めた判型を求める入稿先もある。

今の PDF は、どのページでも MediaBox、TrimBox、BleedBox を仕上がりの判型と同じ矩形（原点がページの左下）にしている。
`Golem.Driver.Pdf.writeDocument` が `P.Page pageRect pageRect pageRect marks` と書いており、`pageRect` は `pgPageSize` から作る `Rect 0 0 pw ph` である。
[golem-layout-spec ADR 0001](../../golem-layout-spec/adr/0001-page-geometry.md) は、裁ち落としの領域を golem-pdf の ADR で扱うとして残した。
[仕様書](../../specifications.md)の「v1 の実装で次の段階以降に回した項目」にも、トンボと塗り足しが挙がっている。

[ADR 0002](0002-pdf-x-4.md) は、各ページに TrimBox を置き、BleedBox を置く場合は MediaBox の内側に収めることを求める。
`Golem.Pdf.X4.checkPdfX` は、BleedBox が MediaBox の内側にあり、TrimBox が BleedBox の内側にあることを検査する。
同じ ADR は、スポットカラー（Separation と DeviceN の色空間）を v1 で扱わないと決めている。
トンボの色として印刷ソフトが使うレジストレーションの色は、Separation の `All` であり、この決定に当たる。

v1 のレイアウトは、版面と余白の中にだけ描く。
図版は版面の中に置き（[golem-driver ADR 0005](../../golem-driver/adr/0005-pdf-wrapped-figures.md)）、柱とノンブルは余白に置く。
ページの端まで図版を伸ばす置き方は、フレームのレベル 2 以上の機能であり、v1 にはない。
したがって、塗り足しの領域に描くものは v1 にはなく、塗り足しは入稿先が求める箱の大きさとして用意する。

インスタンス ID の計算に使う入力（`Golem.Driver.writeTargets` の `inputs`）は、マニフェストとソースファイルのテキストだけで、`style.toml` を含まない。
[docs/adr/0002](../../adr/0002-determinism.md) は `style.toml` を入力に数えている。
塗り足しを `style.toml` に書くと、塗り足しだけが違う二つの PDF が同じインスタンス ID を持つことになる。

[docs/adr/0002](../../adr/0002-determinism.md) の入力の一覧はファイルと Golem の版だけで、CLI のオプションを含まない。
今の `golem build` のオプションのうち、`--target` と `--format` は書くターゲットと診断の形式を選ぶだけで、出力のバイト列を変えない。
`--profile` は、prod で校正用のコメントを出力から落とす（`Golem.Eval.File` の G0205）ので、出力のバイト列を変える。
それでも `--profile` はインスタンス ID の入力に入っていない。

## 実装すること

### 設定の置き場所

塗り足しの量は `style.toml` の `[page]` に書き、トンボの有無と形は `golem build` の CLI のオプション `--marks` で選ぶ。

```toml
# style.toml
[page]
size = "A6"
bleed = "3mm"
```

```sh
golem build --target pdf --marks japanese   # 入稿用
golem build --target pdf                    # 閲覧用（トンボなし）
```

塗り足しは判型と同じくページの幾何であり、将来ページの端まで伸ばす図版を置くときにレイアウトが読む値なので、`style.toml` に置く。
トンボは、同じ原稿から閲覧用と入稿用の PDF を作り分けるときに切り替える出力の設定なので、ファイルを書き換えずに選べる CLI のオプションにする。
プロファイル（dev と prod）では選ばない。
プロファイルは検査の厳しさを表し、トンボの要否とは別の軸だからである。

塗り足しは `--marks none` でも効く。
`bleed` があれば、トンボのない PDF も塗り足しを含む MediaBox になる。
トンボを付けずに塗り足しだけを含めた判型を求める入稿先があるためである。

### style.toml の `bleed`

- `[page]` に `bleed` を加える。値は寸法の文字列で、`mm`、`pt`、`Q`、`H` を使える。既定は `0mm` とする。
- `golem-project` の `Golem.Project.Style.Page` に `pageBleed :: !Sp` を加える。`FromValue Page` で `dimKey "bleed"` を読み、`Zw` の値はエラー（G0306「塗り足しには zw を使えません」）とする。塗り足しは文字の大きさに依存しない長さだからである。
- 負の値は `parseDim` が受け付けないので、別の検査は要らない。
- EPUB と HTML は `bleed` を無視する。

### CLI の `--marks`（golem-cli と golem-driver）

- `golem build` と `golem check` に `--marks japanese|western|none` を加える。既定は `none` とする。
- golem-cli の `Main.hs` に `marksOpt :: Parser CropMarks` を置き、ほかの列挙のオプションと同じく `choice` で読む。

```haskell
marksOpt :: Parser CropMarks
marksOpt =
  option
    (choice "トンボの形" [("japanese", JapaneseMarks), ("western", WesternMarks), ("none", NoMarks)])
    (long "marks" <> value NoMarks <> metavar "japanese|western|none" <> help "PDF に付けるトンボ（既定は none）")
```

- 未知の値は引数の解釈の失敗とし、[golem-cli ADR 0004](../../golem-cli/adr/0004-usage-error-exit-code.md) のとおり、使い方の誤りとして終了コード 2 で終える。メッセージは `choice` の形式で `未知のトンボの形です: <値>（japanese、western、none のいずれか）` とし、`オプション --marks: ` の置き換えも同じ ADR の表に従う。
- `golem-driver` の `Golem.Driver` に次の型を置き、`BuildOptions` に `optMarks :: !CropMarks` を加える。`defaultOptions` の値は `NoMarks` とする。golem-cli は golem-pdf に依存しないので、golem-pdf の型ではなく golem-driver の型で受け渡す。

```haskell
data CropMarks = NoMarks | JapaneseMarks | WesternMarks
  deriving stock (Eq, Show)
```

- `golem build` は `--target` の指定にかかわらず `--marks` を受け付ける。PDF を書かないビルドでは、`--marks` は何も変えない。
- `golem check` は、`--marks` を受け付け、`golem build` と同じく G0702 を検査する。`golem check` は `golem build` と同じ検査を出力なしで行うコマンドなので、入稿用の設定を `golem check --marks japanese` で前もって確かめられるようにする。
- `golem lint`、`golem fmt`、LSP は `--marks` を持たない。LSP はターゲットを出力しないので、G0702 を出さない。
- [golem-cli ADR 0001](../../golem-cli/adr/0001-command-line-interface.md) のコマンドの表の `golem build` と `golem check` の行に `[--marks japanese|western|none]` を加える（ドキュメントの節を参照）。

### ページの箱

golem-pdf に `Golem.Pdf.Marks` を加え、`Golem.Pdf` から再び公開する。
golem-pdf は golem-driver に依存しないので、トンボの形は golem-pdf の側の型で表し、golem-driver が `CropMarks` から写す（`NoMarks` は `Nothing`）。

```haskell
data MarkStyle = Japanese | Western
  deriving stock (Eq, Show)

-- | 一ページの箱と、仕上がりの左下の点の MediaBox の中での位置
data Sheet = Sheet
  { shMedia :: !Rect,
    shTrim :: !Rect,
    shBleed :: !Rect,
    shOrigin :: !Sp
  }

sheet :: Maybe MarkStyle -> Sp -> (Sp, Sp) -> Sheet
sheet marks bleed (w, h) = ...
```

仕上がりの幅と高さを `w` と `h`、塗り足しを `b`、仕上がりの外周から MediaBox の外周までの距離を `m` とする。

- `m` は、トンボがなければ `b`、あればトンボの始点の距離 `o`（次の節）に 13mm を足した値とする。
- MediaBox は `Rect 0 0 (w + 2m) (h + 2m)` とする。MediaBox の原点を左下の隅に保つ。
- TrimBox は `Rect m m w h`、BleedBox は `Rect (m - b) (m - b) (w + 2b) (h + 2b)` とする。
- `shOrigin` は `m` とする。
- トンボがなく `b` が 0 なら、三つの箱は今と同じ `Rect 0 0 w h` になり、`m` も 0 になる。

mm の値は `Golem.Project.Style.parseDim` と同じ規則（有理数で計算し、最近接偶数丸めで一度だけ丸める）で sp に変換した定数とする。
3mm は 557314sp、10mm は 1857713sp、13mm は 2415027sp である。

### トンボの形

トンボは仕上がりの左下を原点とする座標で作り、すべてのページに同じものを描く。
線は、太さ 0.25pt（16384sp）の線を、線の中心を通る細い矩形の塗り（`Rule`）で表す。
線の太さの半分（8192sp）は整数なので、矩形の座標は整数の sp になる。
線の長さの方向の矩形の端は、線の始点と終点に一致させ、太さの分を延ばさない。

`markRules :: MarkStyle -> Sp -> (Sp, Sp) -> [Rect]` を `Golem.Pdf.Marks` に置く。
線の長さを `l` = 10mm とし、トンボの始点の距離 `o` を、日本式では `b`、欧文では `max b 3mm` とする。

- 角のトンボ（日本式）：四隅のそれぞれに、仕上がりの線の延長の二本と、塗り足しの線の延長の二本を引く。左下の隅では、横線を `y = 0` と `y = -b` に `x = -o` から `x = -(o + l)` まで、縦線を `x = 0` と `x = -b` に `y = -o` から `y = -(o + l)` まで引く。外側の二本は点 `(-b, -b)` で交わり、L の字を作る。ほかの三隅は、この形を仕上がりの中心について対称に移したものとする。
- 角のトンボ（欧文）：日本式の四本のうち、仕上がりの線の延長の二本だけを引く。
- 中心のトンボ：四辺の中点のそれぞれに、辺に垂直な線を辺の中心線の上に `o` から `o + l` まで引き、辺に平行な長さ `l` の線を、距離 `o + l div 2` の位置に中心線と交わるように引く。辺の中心線の位置は `w div 2` と `h div 2` とする。`div` は整数の切り捨ての除算であり、座標を整数の sp に保つ。日本式と欧文で同じ形とする。
- 線の順序は、角のトンボを左下、右下、右上、左上の順に、中心のトンボを下、右、上、左の順に並べて固定する。

日本式の線の数は 4 隅 × 4 本 + 4 辺 × 2 本 = 24 本、欧文は 4 × 2 + 4 × 2 = 16 本になる。
どの線も BleedBox の内側に入らず、MediaBox の内側に収まる。

### トンボの色

トンボは、DeviceCMYK の C、M、Y、K の各 100% の塗りで描く。
レジストレーションの色（Separation の `All`）は使わない。
v1 はプロセスカラーだけを使い（[ADR 0002](0002-pdf-x-4.md)）、スポットカラーの版がないので、四つのプロセスの版のすべてに線が出る CMYK の各 100% は、`All` と同じ版に同じ線を出す。
スポットカラーを v2 で扱うときに、`All` へ切り替えるかを改めて決める。

### ページの内容の移動

MediaBox の原点を左下の隅に保つので、`m` が 0 でなければ、ページの内容を `(m, m)` だけ移す。

- `Golem.Pdf.Writer.Mark` に `Translated !Sp !Sp ![Mark]` を加える。`contentStream` は `q 1 0 0 1 <x> <y> cm`、改行、内側の内容、`Q`、改行を書く。
- `writePdf` のフォントと画像の収集（`fontsOf` と `imageOrder`）を、`Saved` と `Translated` の内側まで辿るように直す。今の `imageOrder` はページの内容の最上位の `Image` しか見ていない。
- `Golem.Pdf.Marks` に `framePage :: Maybe MarkStyle -> Sp -> (Sp, Sp) -> [Mark] -> Page` を置く。`m` が 0 なら内容をそのまま、そうでなければ `[Translated m m (content <> marks)]` を内容とし、`sheet` の箱を付けた `Page` を返す。`marks` は、トンボがあれば `[Saved (SetColor (Swatch 100 100 100 100) : map Rule (markRules ...))]` とする。トンボはページの内容の後に描き、内容の上に重ねる。
- golem-driver の `writeDocument` は、`P.Page pageRect pageRect pageRect marks` の代わりに `P.framePage` を呼ぶ。

`--marks none` で `bleed` がない PDF は、この変更の前とバイト列が変わらない（インスタンス ID を除く。後の節を参照）。

### 診断

- G0702：`--marks japanese` で PDF を書くか検査するときに、`style.toml` の `[page]` の `bleed` が 0 なら、PDF の出力の前にエラーとする。メッセージは「日本式のトンボには塗り足しが要ります。style.toml の [page] に bleed を書いてください」とする。日本式の二重のトンボは、仕上がりの線と塗り足しの線の間隔で塗り足しを示すので、塗り足しが 0 だと二本の線が重なり、意味をなさないためである。
- G0702 の位置は `style.toml` とする。`Style` はキーの位置を持たないので、ほかの `style.toml` の診断（G0306 など）と同じく先頭（`mkSpan <style.toml の FileId> 0 0`）に置く。`style.toml` がないプロジェクトでは、`manifest.toml` の先頭に置く。
- G0702 は PDF のターゲットの診断であり、`--target` に `pdf` を含まないビルドでは出さない。`golem check` は、マニフェストのターゲット（`targetsOf`）に PDF があれば出す。
- G0702 は今の G07 の番号（G0701、G0721 から G0724、G0732 から G0735、G0741、G0742）の空きである。[docs/adr/0006](../../adr/0006-paragraph-indent.md) の G0725 とも重ならない。
- 欧文のトンボは、塗り足しが 0 でもエラーにしない。始点の距離 `o` が 3mm より小さくならないので、断裁の後にトンボが残らない。

### インスタンス ID の入力

`Golem.Driver.writeTargets` の PDF の `inputs` に、`style.toml` のバイト列と、出力を変える CLI のオプションを加える。

- `style.toml` のバイト列は、マニフェストの直後に置く。`style.toml` がないプロジェクトでは空のバイト列を置く。入力の各要素には長さが前置される（`Golem.Pdf.Writer.instanceId`）ので、空のバイト列も入力の区切りとして区別される。
- `style.toml` のテキストを `Evaluated` に `evStyleText :: !Text` として持たせ、`evaluateProjectWith` が読んだものを渡す。
- CLI のオプションは、ソースファイルの後に一つの要素として置く。要素は `options marks=<値> profile=<値>` の UTF-8 のバイト列とし、値は CLI の綴り（`japanese`、`western`、`none`、`dev`、`prod`）とする。既定の値のときも省かない。
- `--target` と `--format` は要素に入れない。PDF のバイト列を変えないためである。

`--profile` を加えるのは、文脈に書いたとおり、prod では校正用のコメントが落ちて出力が変わるためである。
`--marks` だけを加えると、出力を変える CLI のオプションのうち一つだけが入力に入り、規則が説明できなくなる。

### 決定性

- 箱とトンボの座標は、整数の sp と、有理数から一度だけ丸めた mm の定数から計算し、浮動小数点数を使わない。
- トンボの線の順序は前の節のとおり固定し、ページの順序や並列の処理に依存しない。
- 出力を変える CLI のオプション（`--marks` と `--profile`）は、ビルドの入力として扱う。[docs/adr/0002](../../adr/0002-determinism.md) の「出力は入力だけで決まる」を、「出力はファイルの入力、Golem の版、出力を変える CLI のオプションだけで決まる」と読み替え、入力の一覧に出力を変える CLI のオプションを加える。
- CLI のオプションは環境変数や時計と違い、呼び出しに明示され、同じ呼び出しなら同じ値になるので、決定性を損なわない。CI と手元で同じ出力を得るには、同じオプションで呼べばよい。
- トンボと塗り足しの設定は `style.toml` と `--marks` から決まり、どちらもインスタンス ID の入力に入る。閲覧用と入稿用の PDF は、同じドキュメント ID と異なるインスタンス ID を持つ。
- 今後 CLI に出力を変えるオプションを加えるときは、インスタンス ID の入力の要素に加える。

### ドキュメント

- 仕様書の `style.toml` の例と説明に `bleed` を加え、「v1 の実装で次の段階以降に回した項目」からトンボと塗り足しを除く。
- 仕様書の CLI の節の `golem build` と `golem check` に `--marks` を加え、値と既定、PDF にだけ効くこと、未知の値が終了コード 2 になることを書く。
- 仕様書の「識別子」の節の入力全体の一覧に、`style.toml` と、出力を変える CLI のオプション（`--marks` と `--profile`）を加える。
- 用語集に、トンボと塗り足しを加える。
- README の入稿の説明に、日本の印刷所向けの手順（`style.toml` の `[page]` に `bleed = "3mm"` を書き、`golem build --target pdf --marks japanese` で作る）と、閲覧用の PDF は `--marks` を付けずに作ることを書く。
- [docs/adr/0002](../../adr/0002-determinism.md) のステータスの行を「採択→入力に出力を変える CLI のオプションを加える点は golem-pdf ADR 0004」に変え、この ADR へのリンクを付ける。
- [golem-cli ADR 0001](../../golem-cli/adr/0001-command-line-interface.md) のステータスの行を「採択→`golem build` と `golem check` の `--marks` は golem-pdf ADR 0004」に変え、この ADR へのリンクを付ける。
- ステータスの行のリンクは、書き込む先のファイルからの相対パスにする。

### CLI の変更をこの ADR で扱う理由

`--marks` のために golem-cli の ADR を別に立てない。
`--marks` は塗り足しと G0702 とインスタンス ID の入力と一体の変更であり、別の ADR に分けると、片方だけを実装した状態で意味をなさない。
引数の解釈の規則（終了コードと日本語の文言）は [golem-cli ADR 0004](../../golem-cli/adr/0004-usage-error-exit-code.md) がすでに決めており、`--marks` はその規則にオプションを一つ足すだけで、golem-cli の設計を変えない。
golem-cli の変更（`marksOpt`、テスト、golden）は、この ADR の実装に含める。

## 実装しないこと

- ページの端まで、または塗り足しの領域まで図版を伸ばす指定。版面の外に図版を置く仕組み（フレームのレベル 2 以上）がないので、v1 では塗り足しの領域に描くものがない。フレームを実装するときに、塗り足しまでの伸ばし方を別の ADR で決める。
- 版面や柱が仕上がりの外に出ていないかの検査。v1 で版面の外に描く柱とノンブルは、[golem-layout-spec ADR 0001](../../golem-layout-spec/adr/0001-page-geometry.md) の計算で余白の中に置かれる。
- 見開き（二ページを一枚に並べたもの）の PDF と面付け。入稿は単ページで行い、面付けは印刷所に任せる。
- レジストレーションの色（Separation の `All`）、カラーバー、レジスターマーク（円と十字の見当合わせの印）、ページの情報（ファイル名や日時）の印字。
- トンボの太さ、長さ、色を変える設定。
- トンボの有無だけが違う二つの PDF（閲覧用と入稿用）を一度のビルドで出力すること。`--marks` を変えて二度ビルドする。二度目のビルドは一度目の出力を上書きするので、両方を残すには、一度目の出力を別の場所に写す。
- マニフェストや `style.toml` にトンボの既定を書くこと。設定ファイルによる既定のオプションの変更は [golem-cli ADR 0001](../../golem-cli/adr/0001-command-line-interface.md) が実装しないとしている。
- `--marks` の値ごとに出力のファイル名を変えること。
- `golem new` の雛形に `bleed` を入れること。今の雛形の出力を変えないためである。

## テスト設計

### golem-pdf（`modules/golem-pdf/test/Main.hs`）

- `sheet Nothing 0 (w, h)` の三つの箱が `Rect 0 0 w h` で、`shOrigin` が 0 であること。
- `sheet Nothing b (w, h)` の MediaBox と BleedBox が `Rect 0 0 (w + 2b) (h + 2b)`、TrimBox が `Rect b b w h` であること。
- `sheet (Just Japanese) 557314 (w, h)` の `shOrigin` が 557314 + 2415027 で、MediaBox、TrimBox、BleedBox が前の節の式と一致すること。
- `sheet (Just Western) 0 (w, h)` の `shOrigin` が 557314 + 2415027 であること（始点の距離が 3mm になる）。
- 上の各場合で、`checkPdfX` が空のリストを返すこと。
- `markRules Japanese` が 24 本、`markRules Western` が 16 本の矩形を返し、どの矩形も BleedBox の内部と重ならず、MediaBox（仕上がりの原点の座標に移したもの）の内側にあること。
- `markRules Japanese` の左下の隅の四本が、前の節の座標（太さの半分の 8192sp を含む）と一致すること。
- `contentStream` が `Translated 65536 131072 [Rule (Rect 0 0 65536 65536)]` を `q 1 0 0 1 1 2 cm\n0 0 1 1 re f\nQ\n` と書くこと。
- `Translated` の内側にだけ `Image` と `GlyphRun` があるページを書いた PDF が、`/XObject` と `/Font` のリソースにその画像とフォントを含むこと。
- 既存のプロパティテスト（任意のページの内容を決定的に書き、相互参照が正しいこと）の生成器に `Translated` を加える。
- `framePage (Just Japanese)` で作ったページの PDF が `qpdf --check` を通ること（qpdf がある環境で）。

### golem-project（`modules/golem-project/test/Main.hs`）

- `[page]` の `bleed = "3mm"` が `pageBleed = 557314` になり、`bleed` を省くと 0 になること。
- `bleed = "1zw"` が G0306 になること。
- マニフェストの `[targets.pdf]` に `marks = "japanese"` を書くと、今と同じく未知のキーとして G0301 になること（マニフェストに `marks` を加えないことの確認）。

### golem-driver（`modules/golem-driver/test/Main.hs`）

`buildMini` の既存の小さなプロジェクトを使う。

- `bleed` がなく `optMarks = NoMarks` のとき、出力の PDF の各ページの `/MediaBox`、`/TrimBox`、`/BleedBox` が同じ値で、内容のストリームに `cm` の移動がないこと。
- `bleed = "3mm"` と `optMarks = JapaneseMarks` のとき、`/MediaBox`、`/TrimBox`、`/BleedBox` の値が `sheet` の計算と一致し、内容のストリームが `q 1 0 0 1` で始まり、`1 1 1 1 k` を含むこと。出力が `qpdf --check` を通ること。
- `bleed = "3mm"` と `optMarks = NoMarks` のとき、MediaBox と BleedBox が一致し、TrimBox がその内側にあること。
- `optMarks = JapaneseMarks` で `bleed` がないとき、`style.toml` の先頭の位置の G0702 になり、PDF が書かれないこと。`optMarks = WesternMarks` で `bleed` がないときは、エラーにならないこと。
- `optMarks = JapaneseMarks` で `bleed` がなく、`optTargets = Just [TargetHtml]` のとき、G0702 が出ず、HTML が書かれること。
- マニフェストに `[targets.pdf]` があるプロジェクトで、`optMarks = JapaneseMarks`、`optCheckOnly = True` で `bleed` がないとき、G0702 が出て、`build/` に何も書かれないこと。
- `style.toml` の `bleed` だけが違う二つのプロジェクトの PDF で、インスタンス ID（トレーラーの `/ID` の第二要素）が異なること。
- 同じプロジェクトを `optMarks` だけ変えて二回ビルドした PDF で、ドキュメント ID（`/ID` の第一要素）が同じで、インスタンス ID が異なること。`optProfile` だけを変えた場合も、インスタンス ID が異なること。
- 同じ設定で二回ビルドした PDF のバイト列が一致すること（既存の決定性のテストに、トンボと塗り足しのある設定を加える）。

### golem-cli（`modules/golem-cli/test/Main.hs`）

- `golem build --marks nope` と `golem check --marks nope` が終了コード 2 で終わり、標準エラー出力に `未知のトンボの形です: nope` を含むこと。
- `golem build --marks`（値の欠け）が終了コード 2 で終わること。
- `golem build --help` の golden に `--marks japanese|western|none` の行と日本語の説明が入ること。golden を更新する。
- `bleed` のないプロジェクトで `golem build --target pdf --marks japanese` が終了コード 1 で終わり、標準エラー出力に G0702 があること。同じプロジェクトで `golem build --target html --marks japanese` が終了コード 0 で終わること。

### 手作業の確認

自動テストにできないものは、実装の後に次のように確かめる。

- 日本式のトンボを付けた A6 の PDF を Acrobat で開き、トンボの位置と形を、InDesign で同じ判型と塗り足しに日本式のトンボを付けて書き出した PDF と見比べる。
- 同じ PDF を Acrobat のプリフライトの PDF/X-4 の検査にかけ、ページの箱について指摘がないことを確かめる。インキの総量の指摘が出るかも記録する（トレードオフを参照）。
- 印刷所の入稿の案内（日本式のトンボと 3mm の塗り足しを求めるもの）と、線の位置を照らし合わせる。

## トレードオフ

トンボを CMYK の各 100% で描くので、インキの総量は 400% になり、Japan Color 2001 Coated の総量の上限を超える。
トンボは断裁で落ちるので印刷の結果には影響しないが、プリフライトの設定によっては総量の警告が出ると考えられる（確かめていない）。
レジストレーションの色を使えば警告は出ないが、v1 の範囲（プロセスカラーだけ）を広げる別の ADR が要る。

トンボを CLI のオプションで選ぶので、閲覧用の PDF と入稿用の PDF を、ファイルを書き換えずに同じプロジェクトから作り分けられる。
その代わり、入稿用の PDF はリポジトリのファイルだけからは決まらず、呼び出しのオプションも要る。
入稿用の PDF を再現するには、CI の設定やスクリプトに `--marks japanese` を書いて残す必要がある。
マニフェストに置けば再現はファイルだけで済むが、閲覧用と入稿用を切り替えるたびにファイルを書き換えることになり、その手間を避けるほうを選ぶ。
オプションの値はインスタンス ID の入力に入るので、どの設定で作った PDF かは区別できる。

出力を変える CLI のオプションを入力に数えるので、`--profile` もインスタンス ID の入力に入る。
dev と prod で同じ原稿から作った PDF は、校正用のコメントがなくてもインスタンス ID が異なる。
同じ PDF のバイト列でもインスタンス ID が違いうるが、インスタンス ID は呼び出しの条件ごとに変わる値として扱う。

MediaBox の原点を左下の隅に保つため、トンボや塗り足しがあるときは内容を `cm` で移す。
原点を負の座標にすれば内容を移さずに済むが、ほかの PDF の制作ソフトの多くは MediaBox を原点から始める形で書くので、それに合わせる。
移す処理は内容のストリームの先頭と末尾に数バイトを足すだけで、トンボも塗り足しもない PDF には何も足さない。

塗り足しの領域に描くものが v1 にはないので、v1 の塗り足しは、入稿先が求める箱の大きさを満たすためだけにある。
ページの端まで伸ばす図版は、フレームの実装を待つことになる。

インスタンス ID の入力に `style.toml` と CLI のオプションを加えるので、すべてのプロジェクトで、この変更の後のインスタンス ID が変わる。
`style.toml` は [docs/adr/0002](../../adr/0002-determinism.md) が入力に数えていたものを入れ直すだけであり、同じ版の Golem の中での決定性は保たれる。
