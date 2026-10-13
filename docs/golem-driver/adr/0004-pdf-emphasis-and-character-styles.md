# ADR 0004: PDF で強調、文字スタイル、色を区別して組む

ステータス: 採択

## 文脈

原稿は、意味の強調 `[strong: ...]`、見た目の指定 `[bold: ...]` と `[italic: ...]`、文字スタイル `[style 名前: ...]`、色 `[color スウォッチ: ...]` を持つ（[markup.md](../../markup.md)）。
意味論 IR では、それぞれ `Strong`、`Bold`、`Italic`、`CharStyle`、`Color` のインラインの要素になる。

HTML と EPUB は、これらを区別して出力している（`Golem.Html`）。

- `Strong` は `<strong>` とし、`[emphasis] strong` が `bold` なら太字、`italic` なら斜体にする CSS を出す。既定は `bold` である。
- `Bold` は `<b>`、`Italic` は `<i>` とする。どちらも書体のファイルを指定しないので、ブラウザーが本文の書体から太字と斜体を合成する。
- `CharStyle` は、文字スタイルの `font` の役割の書体を指定する。`size` は使っていない。
- `Color` は、スウォッチの CMYK を素朴な式で RGB に近似した色にする（[仕様書の「色」](../../specifications.md)）。

PDF は、これらを区別せずに組んでいる（[仕様書の「v1 の実装で次の段階以降に回した項目」](../../specifications.md)）。
`Golem.Layout.Japanese.piecesOf` が五つの要素を中身の並びに平らにし、何で囲まれていたかを捨てているためである。
golem-pdf には CMYK の色を設定する `SetColor` の描画の命令（`k` と `K` の演算子）があるが、PDF のパイプラインはこれを使っていない。

区別して組むには、四つのことを決める必要がある。

- 太字と斜体をどの書体で組むか。`style.toml` には太字と斜体の書体を指定する欄がない。
- 和文の斜体をどう扱うか。和文の書体は一般に斜体を持たない。
- 一つの段落の中に書体と大きさの異なる文字が混ざるとき、行分割の幅をどう測り、使ったグリフをどのフォントに集めるか。
- 色を、[golem-pdf ADR 0002](../../golem-pdf/adr/0002-pdf-x-4.md) の色の規則（出力インテントと同じ CMYK の色空間、プロセスカラーだけ）に収めて書くこと。

複数の役割のフォントの読み込み、フェイスの番号、サブセット化の単位は [ADR 0003](0003-pdf-heading-styles.md) で決めた。
この ADR はその上に、段落の中で書体と大きさを切り替える仕組みを加える。

## 実装すること

### style.toml の欄と検査（golem-project）

`[emphasis]` に二つのキーを加える。

```toml
[emphasis]
strong = "bold"
bold-font = "gothic"     # [bold: ...] を組むフォントの役割
italic-font = "italic"   # [italic: ...] を組むフォントの役割
```

- `Style` に `stBoldFont :: !(Maybe Text)` と `stItalicFont :: !(Maybe Text)` を加え、`Emphasis` の読み込みで読む。どちらも省略でき、既定は `Nothing` とする。
- `bold-font`、`italic-font`、`[character-styles.<名前>]` の `font` が `[fonts]` にない役割を指す場合は、[ADR 0003](0003-pdf-heading-styles.md) の G0308 とする。
- 検査は `parseStyle` の `checks` に加え、すべてのターゲットで同じ診断を出す。

### 文字の見た目（golem-layout）

段落の中の文字ごとの見た目を表す型を、golem-layout の新しいモジュール `Golem.Layout.Look` に置く。

```haskell
data Look = Look
  { lkFace :: !Text,         -- 和文の文字を組むフォントの役割
    lkLatinFace :: !Text,    -- 欧文の文字を組むフォントの役割
    lkSize :: !Sp,           -- 文字の大きさ
    lkEmbolden :: !Bool,     -- 合成の太字
    lkSlant :: !Bool,        -- 合成の斜体（italic-font の役割が持たない側の文字に効く）
    lkColor :: !(Maybe Text) -- スウォッチの名前。Nothing は既定の色
  }
  deriving stock (Eq, Ord, Show)
```

golem-layout は、役割の名前とスウォッチの名前を解釈しない。
幅を測る関数に渡し、箱に付けて後の段階に渡すだけである。

### 見た目の決め方（golem-driver）

段落の単位ごとの元の見た目は、本文では本文の役割と版面の文字の大きさ、見出しでは [ADR 0003](0003-pdf-heading-styles.md) の見出しの役割と大きさとする。
`lkFace` と `lkLatinFace` は同じ役割、`lkEmbolden` と `lkSlant` は `False`、`lkColor` は `Nothing` から始める。

インラインの要素に入るたびに、外側の見た目から内側の見た目を次の関数で作る。
`Golem.Driver.Pdf` に置く。

```haskell
restyle :: Style -> Look -> Inline -> Look
```

- `Strong`：`[emphasis] strong` が `bold` なら `Bold` と、`italic` なら `Italic` と同じに扱う。HTML の `strong` の CSS と同じ対応である。
- `Bold`：`bold-font` があれば `lkFace` と `lkLatinFace` をその役割にする。なければ `lkEmbolden` を `True` にする。
- `Italic`：`italic-font` があれば、その役割が持つ側（`ja` なら `lkFace`、`latin` なら `lkLatinFace`）をその役割にする。役割が持たない側の文字と、`italic-font` がない場合は、`lkSlant` を `True` にする。
- `CharStyle 名前`：文字スタイルの `font` があれば `lkFace` と `lkLatinFace` をその役割にする。`size` があれば `lkSize` を `dimToSp (lkSize 外側) size` にする。`zw` は外側の文字の大きさを一字とする。
- `Color スウォッチ`：`lkColor` を `Just スウォッチ` にする。
- ほかの要素では見た目を変えない。

入れ子では、外側から順に適用する。
内側の指定が同じ欄の外側の指定に勝ち、ほかの欄は外側から引き継ぐ。
たとえば `[color accent: [bold: 語]]` は、太字で accent の色になる。

### 和文の斜体

和文の文字も、斜体を指定すれば斜体で組む。
`italic-font` の役割が和文のフォント（`ja`）を持たない場合は、字形がゆがんでも、和文の文字に合成の斜体をかける。

- `italic-font` の役割が `ja` を持てば、和文の文字はそのフォントで組む。持たなければ、和文の文字は外側の和文の書体のまま、合成の斜体（`lkSlant`）をかける。
- 欧文の文字も同じく、役割が `latin` を持てばそのフォントで組み、持たなければ合成の斜体をかける。
- `italic-font` がないときは、和文と欧文の両方に合成の斜体をかける。
- 合成の斜体は、各字形をその字形の座標系で傾ける。縦組みで正立させる文字、縦中横、縦組みで回転させる欧文も同じ傾きにする。

和文の書体は一般に斜体を持たないので、合成の斜体は字形をゆがめる。
それでも傾けるのは、Adobe InDesign で和文に斜体を指定したときの挙動に合わせ、InDesign から移る利用者の原稿で強調が消えないようにするためである。
`[emphasis] strong = "italic"` の文書でも、和文の `[strong: ...]` は PDF で強調として見える。

### 行分割の寸法（golem-layout）

`Golem.Layout.Japanese` を次のように変える。

- `ComposeEnv` の `ceAdvance` を `Look -> Char -> Rational`、`ceWordAdvance` を `Look -> Text -> Rational` にする。単位は今と同じく em である。
- `ComposeEnv` に、段落の元の見た目 `ceLook :: !Look` と、見た目を切り替える関数 `ceRestyle :: Look -> Inline -> Look` を加える。`defaultComposeEnv` の `ceRestyle` は見た目を変えない関数とする。
- `ceFontSize` は段落の元の大きさとして残し、字間の調整の伸び（今は段落の大きさの 1/10）と和欧間の四分の基準に使う。
- `Piece` の各構成子（`PChar`、`PWord`、`PSpace`、`PBox`）に `Look` を持たせる。`piecesOf` は `Strong`、`Bold`、`Italic`、`CharStyle`、`Color` に入るときに `ceRestyle` で見た目を切り替える。
- 文字の箱の幅は、その文字の見た目の大きさ（`lkSize`）と `ceAdvance look c` から求める。欧文の語の幅は `ceWordAdvance look 語` と `lkSize` から求める。語間の空き、ハイフンの幅、縦中横の箱（一字分）、注の印の箱（半分）も、その位置の見た目の大きさで求める。
- 約物の前後の空き（`punctSpace`）は、その約物の見た目の大きさを一字として求める。`normalize` は、隣り合う箱の空きを合成するとき、各箱の `bcLook` の大きさを使う。
- ルビの親文字の幅は、ルビの要素の位置の見た目で測る。ルビの親文字の中の `Strong` などは、今と同じく文字の並びに平らにし、見た目を切り替えない。
- 見た目の境界は、行分割の可否を変えない。欧文の語の途中で見た目が変わる場合（`[bold: Gol]em`）は、今の規則（欧文の箱どうしの間では分割しない）のまま二つの箱が続く。ハイフネーションは見た目の同じ部分ごとに行う。

`Golem.Layout.KnuthPlass.BoxContent` に `bcLook :: !Look` を加える。
行分割のアルゴリズムはこの欄を読まない。
`bcTag` は今と同じく `BoxKind` を表す。

合成の太字と斜体は字形の塗り方だけを変え、送りを変えない。
したがって、`bold-font` と `italic-font` を指定しない文書では、強調の有無で行分割の結果は変わらない。
`bold-font`、`italic-font`、文字スタイルの `font` と `size` を指定した場合は、その役割のフォントのメトリクスで幅を測るので、行分割の結果が変わる。

### フォントの読み込みと幅の関数（golem-driver）

- [ADR 0003](0003-pdf-heading-styles.md) で読み込む役割に、`bold-font`、`italic-font`、`[character-styles.*]` の `font` が指す役割を加える。フェイスの番号の振り方、同じバイト列のファイルの統合、G0805 の検査は [ADR 0003](0003-pdf-heading-styles.md) のとおりとする。
- `composeEnv` は、`ceAdvance look c` を、`c` が欧文の文字（`charClass` が `Western`）なら `lfAdvance (lkLatinFace look) c`、ほかは `lfAdvance (lkFace look) c` とする。`ceWordAdvance look w` は `lfWordAdvance (lkLatinFace look) w` とする。
- `ceRestyle` には `restyle (piStyle inp)` を渡す。
- `LoadedFonts` の型は [ADR 0003](0003-pdf-heading-styles.md) のまま変えない。

### 描画（golem-driver）

`writeDocument` の `drawLine` は、行の役割と大きさの代わりに、各箱の `bcLook` で描く。
[ADR 0003](0003-pdf-heading-styles.md) で `SetLine` に加えた `slFace` は使わなくなるので削る。

- 箱の文字列を、欧文の文字の連続とそれ以外の連続に分け、欧文は `lkLatinFace`、それ以外は `lkFace` の役割で `lfShape` に渡す。大きさは `lkSize` とする。
- ルビの読みと圏点の点は、親文字の箱の見た目の大きさの半分で、同じ役割、同じ色で描く。
- 行末のハイフンは、直前の箱の見た目で描く。
- 合成の太字（`lkEmbolden`）か、合成の斜体（`lkSlant`）が効くグリフの並びは、下の `StyledGlyphRun` で描く。どちらも効かない並びは、今と同じ `GlyphRun`、`ScaledGlyphRun`、`RotatedGlyphRun` で描く。
- 合成の斜体の傾きは 1/5（約 11.3 度）とする。合成の太字の輪郭の線の幅は、文字の大きさの 1/40 を `div` で整数の sp にしたものとする。どちらも `Golem.Driver.Pdf` に名前を付けた定数として置く。
- 一つの行の中で `lkColor` が同じ `Just s` の箱が続く部分を一つにまとめ、`P.Saved (P.SetColor sw : その部分の描画の命令)` で描く。`sw` は `stSwatches` の `s` の CMYK の値とする。`lkColor` が `Nothing` の部分は、今と同じく色を設定せずに描く。
- `Color` のスウォッチの名前は評価の段階で存在を検査している（`ctxSwatches`）。`stSwatches` にない名前が描画に届いた場合は、色を設定せずに描く。

### 描画の命令（golem-pdf）

`Golem.Pdf.Writer.Mark` に二つの構成子を加える。
既存の構成子と、その直列化のバイト列は変えない。

```haskell
data RunStyle = RunStyle
  { rsScale :: !Int,        -- 水平の拡大率（千分率、1000 で拡大しない）
    rsRotated :: !Bool,     -- 縦組みの中で 90 度回した欧文
    rsSlant :: !Rational,   -- 傾き（0 で傾けない）
    rsEmbolden :: !Sp       -- 輪郭の線の幅（0 で太らせない）
  }

data Mark
  = ...
  | StyledGlyphRun !RunStyle !FontRef !Sp ![(GlyphId, Sp, Sp)]
  | Saved ![Mark]
```

- `Saved ms` は `q`、`ms` の直列化、`Q` の順に書く。色を設定した後に元の色へ戻すためである。
- `StyledGlyphRun` は、`q BT /F<n> <大きさ> Tf` を書き、`rsScale` が 1000 でなければ `<rsScale/10> Tz`、`rsEmbolden` が 0 より大きければ `2 Tr <線の幅> w` を続け、各グリフを `<a> <b> <c> <d> <x> <y> Tm <gid> Tj` で書いて、`ET Q` で閉じる。`Tr` と `w` は後の描画に残るので、`q` と `Q` で囲む。
- 文字の行列は、回さない場合は `1 0 s 1`、回す場合は `0 -1 1 -s` とする（s は `rsSlant`）。後者は、字形を傾けてから今の `RotatedGlyphRun` と同じく 90 度回した行列である。
- 数値は、今の `ratio`（有理数を小数 4 桁で書く関数）と `num`（sp を pt で書く関数）で書く。
- ページのリソースの辞書にフォントを集める関数（`fontsOf`）は、`StyledGlyphRun` のフォントと、`Saved` の中の命令のフォントも集める。

### 色の規則

- 文字の色は、`SetColor` で DeviceCMYK の `k`（塗り）と `K`（線）に同じ値を書く。合成の太字の輪郭の線も文字と同じ色になる。
- 色はスウォッチの CMYK の値をそのまま書き、RGB への変換も、Separation と DeviceN の色空間も使わない。出力インテントと同じ CMYK の色空間で、プロセスカラーだけを使うという [golem-pdf ADR 0002](../../golem-pdf/adr/0002-pdf-x-4.md) の規則に従う。
- 既定の色（`lkColor` が `Nothing`）の文字は、今と同じく色を設定せずに描く。

### HTML と EPUB（golem-html）

`bold-font` と `italic-font` を PDF だけに効かせると、媒体のあいだで強調の書体がずれるので、HTML と EPUB の CSS にも反映する。

- `HtmlConfig` に `hcBoldFont :: !(Maybe Text)` と `hcItalicFont :: !(Maybe Text)` を加え、golem-driver が `stBoldFont` と `stItalicFont` を渡す。
- `bold-font` があれば、`b` に `font-family: <その役割の並び>; font-weight: normal;` を出す。`strong = "bold"` なら `strong` にも同じものを出す。役割のフォントがすでに太字なので、ブラウザーにさらに太らせないためである。
- `italic-font` があれば、その役割の `@font-face` を `font-style: italic` で宣言し、`i` に `font-family: <その役割の並び>, <本文の役割の並び>; font-style: italic;` を出す。`strong = "italic"` なら `strong` にも同じものを出す。役割が持つ側の文字はその書体で組まれ、持たない側の文字はブラウザーが本文の書体から斜体を合成するので、PDF の規則と同じになる。
- どちらもない場合の CSS は今と変えない。

### 決定性

[docs/adr/0002](../../adr/0002-determinism.md) の規則を次のように守る。

- `Look` の計算は `Style` とインラインの要素だけから決まる純粋な関数で行う。
- 傾きと線の幅は有理数と整数の sp で表し、浮動小数点数を使わない。PDF への書き出しは今の `ratio` と `num` で行う。
- 色の部分のまとめ方は、行の中の箱の順だけで決まる。
- フェイスの番号と、フォントごとのグリフの集め方は [ADR 0003](0003-pdf-heading-styles.md) のとおりであり、`Data.Map` で集める。

### ドキュメント

- 仕様書の「v1 の実装で次の段階以降に回した項目」から「強調、文字スタイル、色」を削る。
- 仕様書の `style.toml` の例と説明に `bold-font` と `italic-font` を加え、指定しない場合は合成の太字と斜体で組むことを書く。
- 仕様書の「色」の節に、PDF の文字の色を DeviceCMYK のプロセスカラーで書くことを書く。
- markup.md の強調の節に、和文も合成の斜体で傾くことを書く。
- README の `style.toml` の説明に同じことを書く。

## データ構造の変更

- golem-layout：`Golem.Layout.Look.Look` を新設する。`BoxContent` に `bcLook` を加える。`ComposeEnv` の `ceAdvance` と `ceWordAdvance` の型を変え、`ceLook` と `ceRestyle` を加える。`Piece` の各構成子が `Look` を持つ。
- golem-project：`Style` に `stBoldFont` と `stItalicFont` を加える。
- golem-pdf：`Mark` に `StyledGlyphRun` と `Saved` を加え、`RunStyle` を新設する。
- golem-html：`HtmlConfig` に `hcBoldFont` と `hcItalicFont` を加える。
- golem-driver：`SetLine` から `slFace` を削る。

`BoxContent` を使うすべての箇所（golem-layout のテストの箱の組み立てを含む）に `bcLook` を足す必要がある。
テストでは、`defaultComposeEnv` の元の見た目を使う。

## 実装しないこと

- 合成の太字の線の幅と、合成の斜体の傾きを `style.toml` で変える設定。
- フォントの OS/2 テーブルの太さと斜体の情報から、太字と斜体の書体を自動で選ぶこと。書体は役割の名前で明示する。
- 可変フォントの太さの軸を使った太字。
- 合成の太字で太った分だけ送りを広げること。
- 段落の中に大きい文字があるときに、行送りを広げること。行は今と同じく行の格子に置き、大きい文字は隣の行に重なりうる。
- 圏点の点とルビの読みに、親文字と別の色を付けること。
- 罫線、図版、柱、ノンブルに色を付けること。
- 既定の色の文字を DeviceCMYK で書き直すこと。今の既定の色（色を設定しない黒）は変えない。
- スポットカラー（[golem-pdf ADR 0002](../../golem-pdf/adr/0002-pdf-x-4.md) の「実装しないこと」のとおり）。
- HTML と EPUB で、文字スタイルの `size` を使うこと。
- 傍注の中の強調と色。傍注はまだ PDF に出力していない。

## テスト設計

先に書いて失敗させるテストを並べる。

### golem-project（modules/golem-project/test/Main.hs）

- `[emphasis] bold-font = "gothic"` を含み `[fonts.gothic]` がない `style.toml` が G0308 になること。
- `[character-styles.term] font = "nope"` が G0308 になること。
- `bold-font` と `italic-font` を含む正しい `style.toml` で、`stBoldFont` と `stItalicFont` が読めること。省略した場合は `Nothing` になること。

### golem-layout（modules/golem-layout/test/Main.hs）

`ceAdvance` を役割で変える環境（役割 `wide` の欧文の文字は 1 em、`body` は 1/2 em）と、`Bold` で役割を `wide` に替える `ceRestyle` を使う。

- `[bold: AB]C` を組むと、A と B の箱の幅が C の 2 倍になり、各箱の `bcLook` の `lkFace` がそれぞれ `wide` と `body` であること。
- 合成の太字だけを立てる `ceRestyle` では、`[bold: AB]C` の箱の幅の並びが `ABC` と一致すること。
- `CharStyle` で大きさを 2 倍にした閉じ括弧（`」`）の後の空きが、本文の大きさの半分ではなく、2 倍の大きさの半分であること。
- 欧文の語の途中で見た目が変わる `[bold: Gol]em` で、二つの箱の間に分割の位置（罰点 0 の `Penalty` と `Glue`）がないこと。
- 入れ子の `[color accent: [italic: [bold: x]]]` の箱の `Look` が、`lkColor = Just "accent"`、`lkSlant = True`、`lkEmbolden = True` になること。

### golem-pdf（modules/golem-pdf/test/Main.hs）

- `contentStream` で、回さない `StyledGlyphRun`（傾き 1/5、線の幅 0.25pt）が `q BT /F1 10 Tf 2 Tr 0.25 w`、`1 0 0.2 1 <x> <y> Tm`、`ET Q` を含むこと。
- 回す `StyledGlyphRun` の行列が `0 -1 1 -0.2 <x> <y> Tm` になること。
- `rsScale` が 1000 でない場合に `Tz` が書かれ、1000 の場合に書かれないこと。
- `Saved [SetColor (Swatch 0 80 100 0), GlyphRun ...]` が `q` で始まり `Q` で終わり、その中に `0 0.8 1 0 k` と `0 0.8 1 0 K` があること。
- `Saved` の中の `GlyphRun` と、`StyledGlyphRun` のフォントが、ページのリソースの辞書に載ること。
- 既存の golden テストの出力が変わらないこと。

### golem-driver（modules/golem-driver/test/Main.hs）

- `[bold: 本文]` を含む原稿を `bold-font` なしで組むと、内容のストリームに `2 Tr` があり、各グリフの `Tm` の位置の並びが、`[bold: ...]` を外した原稿の PDF と一致すること。
- `strong = "italic"`、`italic-font` なしで `[strong: Golem と組版]` を組むと、`Golem` のグリフにも「と組版」のグリフにも傾きの行列（`1 0 0.2 1`）が使われること。縦組みでも、正立させる和文のグリフに傾きの行列が使われること。
- `italic-font` が `latin` だけを持つ役割を指すとき、`[italic: Golem と組版]` の `Golem` はその役割のフォントのリソースで傾きなしに描かれ、「と組版」は本文の和文のフォントで傾きの行列つきで描かれること。
- 役割で幅の変わる偽のフォントで、`bold-font = "wide"` のときに、`[bold: ...]` を含む段落の行数が、`bold-font` なしのときより多くなること。
- 実際のフォントで `bold-font` に本文と別の欧文のフォントを指定すると、そのフォントが埋め込まれ、そのサブセットに `[bold: ...]` の中の文字のグリフだけが入ること。
- `[color accent: 赤い語]` と `accent = { cmyk = [0, 80, 100, 0] }` で、内容のストリームに `0 0.8 1 0 k` があり、`q` と `Q` に囲まれ、PDF に `DeviceRGB` と `Separation` と `DeviceN` が現れないこと。
- 同じ行で同じスウォッチの箱が続く場合に、`q` と `Q` の組が一つにまとまること。
- `[style term: 語]` と `[character-styles.term] font = "heading"`、`size = "2zw"` で、その語が `heading` の役割のフォントのリソースと、版面の文字の大きさの 2 倍の `Tf` で描かれること。
- 強調、文字スタイル、色を含む入力で、並列と逐次の行分割の PDF のバイト列が一致し、二回のビルドの PDF も一致すること。
- 出力の PDF を qpdf で検査し、今の PDF/X-4 の検査を通ること。
- HTML：`bold-font` を指定した `style.toml` の CSS に `b { font-family: ...; font-weight: normal; }` が出ること。指定しない場合の CSS が今の golden（`test/golden/html-style.css`）と一致すること。

自動テストにしない確かめ方として、実装の後に、和文と欧文の強調、文字スタイル、色を含む原稿を縦組みと横組みでビルドし、PDF のビューアーで、合成の太字の太さ、欧文の斜体の傾き、和文が合成の斜体で傾くこと、色の付いた語の後で文字が黒に戻ることを目で確かめる。

## トレードオフ

`bold-font` と `italic-font` を指定しない場合は、合成の太字と斜体で組む。
合成の太字は輪郭を線で太らせるだけで、字面の内側のつぶれや送りの不足を補正しないので、太字の書体のファイルで組むより品質が劣る。
それでも、指定がない場合に強調が PDF で見えなくなるより、HTML と EPUB でブラウザーが合成するのと同じく、見える形で区別するほうを選ぶ。
品質が要る本では、`bold-font` で太字の書体を指定する。

合成の太字は送りを変えないので、太った字形が隣の字形に近づき、和文のべた組みでは字面が接することがある。
送りを広げると行分割の結果が強調の有無で変わり、本文の字送りの格子からもずれるので、送りは変えない。

和文に合成の斜体をかけるので、和文の字形はゆがむ。
組版の品質だけを見れば和文は正体のまま組むほうがよいが、InDesign と挙動をそろえ、斜体の指定が黙って消えることを避けるほうを選ぶ。
和文を傾けたくない利用者は、和文の強調に `strong = "bold"`（既定）を使うか、`ja` を持つ `italic-font` の役割を指定する。

見た目の境界で欧文の語を箱に分けるので、境界をまたぐカーニングと合字は効かない。
境界は利用者が意図して置いたものであり、境界の両側を一度にシェイピングするには、異なる書体と大きさのあいだのシェイピングの規則を決める必要があるため、v1 では扱わない。

色の部分ごとに `q` と `Q` で囲むので、色の多い文書では内容のストリームが少し大きくなる。
色を戻す値を明示する方式（黒の CMYK を設定し直す）では、既定の色を設定しない今の出力と色空間が混ざるので、元の状態に戻す `Q` を使う。
