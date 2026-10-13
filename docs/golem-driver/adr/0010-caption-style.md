# ADR 0010: キャプションを段落スタイル caption の書体と大きさで組む

ステータス: 採択

## 文脈

書籍では、図版のキャプションを本文より小さい文字で組むことが多い。
`style.toml` には、キャプションの書体と大きさを指定する欄がない（[仕様書の「v1 の実装で次の段階以降に回した項目」](../../specifications.md)）。
[ADR 0005](0005-pdf-wrapped-figures.md) は、その欄がないので、PDF のキャプションを本文と同じ書体と大きさで組むと決め、設定は別の ADR に回した。

現状をコードで確かめると、次のとおりである。

- `Golem.Driver.Pdf` の `buildFlow` の `placeFigure` は、キャプション（図番号、全角の空白、`figCaption` の段落）を本文の環境 `bodyEnv` と本文の行分割の設定 `params` で、図版の `along` を行長として組む。
- キャプションの n 行は、画像が占める m 個の行の格子の直後から、一行を格子の一行として置く。`FFigure` の `ffLines` は m + n である。
- 回り込みの除外領域の深さは `(m + n − 1) × 行送り + 文字の大きさ` である。
- `writeDocument` は、キャプションの j 行目を `gridAt (slot + m + j)` に、版面の文字の大きさの `SetLine` で描く。
- `[figures]` は `number` と `wrap-gap` だけを持つ。
- HTML と EPUB の `figcaption` には、書体と大きさの CSS がない。

[docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md) は、段落の見た目を `[paragraph-styles.<名前>]` の段落スタイルにまとめ、組み込みの段落スタイルとして `body`、`verse`、`caption`、`sidenote` を置く。
段落スタイルの `font` はフォントの役割、`size` は文字の大きさで、`zw` は版面の文字の大きさを一字とする。
書かない欄は `based-on` をたどって引き継ぎ、最後は `body` の値になる。
`body` の `font` の既定は本文の役割、`size` の既定は版面の文字の大きさである。
`font` が `[fonts]` にない役割を指すと G0308、`size` が版面の文字の大きさを超えると G0311 になる。
`caption` は `based-on = "body"` だけを持ち、その ADR ではキャプションの組み方に使われない。
同じ ADR は、キャプションの本体の `@style` を G0213 とし、キャプションの見た目を `caption` が決めるとしている。

見出しの `[headings.<階層>]` の `font` と `size`（[ADR 0003](0003-pdf-heading-styles.md)）も、同じ意味の欄である。

キャプションの書体と大きさを指定する欄は、`caption` の段落スタイルにする。
`[figures]` の下に独自の表を設けると、書体と大きさの書き方が段落スタイルと二通りになる。
段落スタイルにすれば、`based-on`、G0308、G0311、`usedRoles` の扱いが [docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md) のまま使える。

この ADR は [docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md) と [docs/adr/0006](../../adr/0006-paragraph-indent.md) の後に実装する。
`caption` の段落スタイル、`usedRoles` の集め方、`restyle` の文字スタイルの扱いを、その二つの ADR に頼るためである。

本文より小さいキャプションを組むには、ほかに三つのことを決める必要がある。
一つ目は、小さい文字の行の送りと、それを行の格子にどう載せるかである。
本文の行送りでそのまま送ると、小さい文字の行のあいだが空きすぎる。
格子からずらすと、図版の後の本文が格子からずれる。
二つ目は、回り込みの除外領域の深さへの影響である。
三つ目は、HTML と EPUB の CSS に反映するかである。

## 実装すること

### style.toml の欄（golem-project）

キャプションの書体と大きさは、組み込みの段落スタイル `caption` の `font` と `size` で指定する。

```toml
[figures]
number = "図{chapter}-{n}"

[paragraph-styles.caption]
font = "caption"  # フォントの役割
size = "11Q"      # 文字の大きさ
```

- golem-project には新しい欄も型も加えない。`[paragraph-styles.caption]` の読み込み、`based-on` の解決、G0306、G0308、G0311 の検査は [docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md) のとおりとする。
- `[figures.caption]` の表は設けない。`[figures]` に `caption` を書けば、今と同じく未知のキーとして G0306 になる。
- キャプションに効くのは、解決した `caption` の `font` と `size` だけである。`line-breaks`、`space-between`、[docs/adr/0006](../../adr/0006-paragraph-indent.md) の `indent` と `first-line-indent` は、キャプションには効かない。意味論 IR のキャプション（`figCaption`）は段落スタイルのない段落（`Paragraph Nothing`）の列だが、図版の書式で図番号と一つのまとまりとして組み、[docs/adr/0006](../../adr/0006-paragraph-indent.md) も字下げを効かせない場所としているためである。これらの欄は、`@style caption` を付けた原稿の段落には効く。
- `caption` に `based-on` で別の段落スタイルを指定すれば、その `font` と `size` を引き継ぐ。

`font` を省けば本文の役割、`size` を省けば版面の文字の大きさで組む（`body` の既定を引き継ぐため）。
既定の `style.toml` では `caption` が `body` と同じ書体と大きさになるので、今の出力は変わらない。

### 役割と大きさの決め方（golem-driver）

`Golem.Driver.Pdf` の `headingFace` を、書体と大きさの組から役割と大きさを決める関数に一般化する。

```haskell
faceFor :: Style -> PageGeometry -> Maybe Text -> Maybe Dim -> (Text, Sp)
faceFor style geom font size =
  (fromMaybe (bodyRole style) font, maybe (pgFontSize geom) (dimToSp (pgFontSize geom)) size)
```

`headingFace` は `faceFor` に `hsFont` と `hsSize` を渡す形に書き直す。
出力は変わらない。
[docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md) の `Unit` の `uFace` の段落スタイルからの計算も、同じ関数で書ける。

段落スタイルの名前から役割と大きさを決める関数を置く。

```haskell
paraFace :: Style -> PageGeometry -> Text -> (Text, Sp)
paraFace style geom name =
  let d = paraStyle style (Just name)
   in faceFor style geom (d >>= psFont) (d >>= psSize)
```

キャプションは `paraFace style geom "caption"` で役割と大きさ（以下 cs）を決める。
[ADR 0011](0011-sidenote-font.md) の傍注も同じ関数を `"sidenote"` で使う。

`usedRoles` は、[docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md) のとおり、すべての段落スタイルの `font` を集めるので、`caption` の役割はこの ADR で加えなくても読み込まれる。
読み込む役割の決め方、フェイスの番号、G0805 の検査は [ADR 0003](0003-pdf-heading-styles.md) のとおりとする。

### キャプションの組み方

`placeFigure` を次のように変える。

- 組版の環境は `envFor 役割 cs` とする。図番号と全角の空白も、キャプションの本文と同じ役割と大きさで組む。
- 行分割の設定は、`params` の `pEmergencyStretch` を cs を基準に `dimToSp cs (compEmergencyStretch comp)` で計算し直したものとする。傍注（[ADR 0006](0006-pdf-sidenotes.md)）と同じ扱いである。
- 行長は、今と同じく `along` とする。
- インラインの中の文字スタイル（`[strong: ...]` などの組み込みの文字スタイルを含む）と色は、[docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md) の `restyle` で、キャプションの見た目から切り替える。文字スタイルの `size` の `zw` は、外側の見た目、つまり cs を一字とする。

### キャプションの行の格子への載せ方

キャプションの行の送りと、キャプションが占める格子の数は、見出しの行取りの関数 `headingBlock`（[ADR 0003](0003-pdf-heading-styles.md)）で求める。
n 行のキャプションについて、`cb = headingBlock fs p cs n` とする（fs は版面の文字の大きさ、p は行送り）。

- キャプションの行の送り cp = `hbPitch cb` = round(p × cs ÷ fs)。本文の行送りと文字の大きさの比をキャプションにも保つ。傍注の行送りと同じ考え方である。
- 占める格子の数 N = `hbSpan cb`。キャプションの全体の長さ (n − 1) × cp + cs を収める最も少ない格子の数である。cs = fs なら N = n になる。
- n = 0（図番号もキャプションもない）なら、N = 0 とする。

見出しと違い、キャプションは領域の中央ではなく先頭にそろえて置く（`hbOffset` を使わない）。
キャプションの j 行目（0 から数える）の字面の始まりは、画像の先頭の格子の番号を k として、`(k + m) × p + j × cp` とする（横組みでは版面の上端から、縦組みでは右端から）。
横組みのベースラインはそれに round(cs × `baselineRatio`) を、縦組みの行の中心線は cs `div` 2 を足した位置とする。
cs = fs なら、各行の位置は今の `gridAt (k + m + j)` と一致する。

先頭にそろえるのは、画像とキャプションのあいだを、キャプションの大きさによらず一定に保つためである。
中央にそろえると、N 個の格子の余りの半分だけ、画像とキャプションのあいだが空く。
余りはキャプションの後ろ、つまり図版の後の本文とのあいだに回る。

図版がページの上で占める格子の数は m + N とする。
回り込ませない図版の `FFigure` の `ffLines` もこの値にする。
キャプションの後の本文は、m + N 個の格子の直後の格子から始まるので、格子からずれない。

### 除外領域の深さ

回り込ませる図版の除外領域の深さ `depth` を、キャプションの実際の終わりまでとする。

- キャプションがある場合：`depth = m × p + (n − 1) × cp + cs`。
- ない場合：今と同じく `across`。

cs = fs なら、今の式 `(m + n − 1) × p + fs` と一致する。
`exWidth`、`exLines`、G0722、G0723 の計算は [ADR 0005](0005-pdf-wrapped-figures.md) のまま変えない。
小さいキャプションでは `exLines` が減るので、本文の大きさでは G0723 になった図版が入る場合がある。

`paginate` の `FWrapped` は、`exLines` と脇の行の数の大きいほうを使う。
`exLines` は `depth` から求めるので、キャプションの占める格子の数 N を別に渡す必要はない。

### データ構造（golem-driver）

```haskell
data PlacedFigure = PlacedFigure
  { pfImage :: !P.ImageData,
    pfAlong :: !Sp,
    pfAcross :: !Sp,
    pfWrap :: !(Maybe Wrap),
    pfImageLines :: !Int,   -- m
    pfCaption :: ![Line],
    pfCaptionSize :: !Sp,   -- cs
    pfCaptionPitch :: !Sp,  -- cp
    pfCaptionSpan :: !Int,  -- N
    pfExclusion :: !(Maybe Exclusion)
  }
```

`writeDocument` の `drawPage` は、キャプションの j 行目を、上の式の位置で `SetLine l cs (captionIndent ta pf) [] []` として描く。
描く行のグリフは各箱の `bcLook` の役割と大きさで描かれるので（[ADR 0004](0004-pdf-emphasis-and-character-styles.md)、[docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md)）、キャプションの役割のグリフはその役割のフォントのサブセットに入る。

### HTML と EPUB（golem-html、golem-driver）

キャプションの書体と大きさを PDF だけに効かせると、媒体のあいだで見た目がずれるので、HTML と EPUB の CSS にも反映する。
[docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md) は、段落スタイルの `font` を CSS に反映し、`size` を反映しない。
キャプションでは `size` も反映する。
キャプションは本文より小さく組むことが目的の要素であり、大きさを落とすと HTML で本文と区別できなくなるためである。

- `Golem.Html` に、CSS に書く書体と大きさの組を表す型を加える。

```haskell
data Face = Face
  { faFont :: !(Maybe Text), -- フォントの役割
    faSize :: !(Maybe Text)  -- CSS の font-size の値
  }
```

- `HtmlConfig` に `hcCaptionFace :: !Face` を加える。
- `css` は、`faFont` か `faSize` のどちらかがある場合に、`figcaption { font-family: <役割の並び>; font-size: <値>; }` を、あるほうの宣言だけで出す。役割の並びは既存の `fontStack` で作る。どちらもない場合は何も出さず、今の CSS と同じになる。
- golem-driver の `Golem.Driver` に、`style.toml` の大きさを CSS の値にする関数を加える。

```haskell
cssFontSize :: Style -> Dim -> Text
```

`zw` は `em` にする。
絶対の大きさは、`[page.grid]` の `font-size` が絶対の大きさなら、その比を `em` で書く（11Q と 13Q なら `0.846em`）。
`[page.grid]` がない場合は、既存の `cssLength` と同じく `pt` で書く。
小数は `cssLength` と同じく 3 桁までの固定の表記にし、決定性を保つ。
HTML は版面を使わないが、本文に対する比を保てば、読者が文字の大きさを変えてもキャプションの相対の大きさが保たれるためである。

- `writeTargets` は、解決した `caption` の段落スタイルを `c` として、`hcCaptionFace = Face (c >>= psFont) (cssFontSize style <$> (c >>= psSize))` を渡す。EPUB は HTML と同じ `style.css` を使うので、同じ規則が入る。
- `figcaption` の規則は、[docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md) の `p.ps-caption` の規則とは別に書く。`p.ps-caption` は `@style caption` を付けた原稿の段落のためのもので、0005 の規則のとおり `font-family` だけを持つ。
- プレーンテキストは変えない。

[ADR 0011](0011-sidenote-font.md) は、同じ `Face` と `cssFontSize` を傍注に使う。

### 決定性

- 行の送り cp と格子の数 N は `headingBlock` と同じく整数の sp と有理数で計算し、丸めは一度だけにする。
- 並列と逐次の行分割は、今と同じく図版の結果を文書の順に並べ直す（[docs/adr/0002](../../adr/0002-determinism.md)）。
- CSS の小数の表記は `cssLength` と同じ固定の桁で書く。

### ドキュメント

- [仕様書](../../specifications.md) の「v1 の実装で次の段階以降に回した項目」から「キャプションの書体」を削る。
- [仕様書](../../specifications.md) の「図版」の節の「本文と同じ書体と大きさで組む」を、段落スタイル `caption` の `font` と `size` で組み、小さい文字の行は本文の行送りと文字の大きさの比で送り、行の格子の先頭にそろえて置くと書き直し、この ADR へのリンクを付ける。除外領域の深さがキャプションの実際の終わりまでになることも書く。
- [仕様書](../../specifications.md) の `style.toml` の段落スタイルの説明に、`caption` がキャプションに使われ、`font` と `size` だけが効くことを書き、`[paragraph-styles.caption]` の例を加える。
- README の `style.toml` の説明に同じことを書く。

## 実装しないこと

- キャプションの位置（画像の上、横）と揃え（中央揃え）の設定。今と同じく画像の下（縦組みでは左）に、画像の行の始まりにそろえて組む。
- 画像とキャプションのあいだの空きの設定。
- 図番号とキャプションの本文で書体や大きさを変えること。
- キャプションを中央にそろえる行取り。
- 表のキャプション（[仕様書](../../specifications.md) の「v2 以降に回した事項」の表の拡張）。
- HTML と EPUB で、見出しの `font` と `size`、文字スタイルの `size`、`caption` と `sidenote` 以外の段落スタイルの `size` を使うこと（[ADR 0003](0003-pdf-heading-styles.md)、[docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md) の決定のまま）。
- キャプションに `caption` の `line-breaks`、`space-between`、字下げを効かせること。
- 原稿で一つのキャプションごとに段落スタイルを選ぶこと（[docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md) の G0213 のまま）。
- `[figures.caption]` のような、段落スタイルと別のキャプションの欄。
- キャプションの中の傍注の配置（[ADR 0006](0006-pdf-sidenotes.md) の G0735 のまま）。

## テスト設計

先に書いて失敗させるテストを並べる。

### golem-project（modules/golem-project/test/Main.hs）

検査そのものは [docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md) のテストが確かめるので、ここではキャプションの書き方で通ることだけを確かめる。

- `[fonts.caption]` と `[paragraph-styles.caption]\nfont = "caption"\nsize = "8pt"\n` を含む `style.toml` が診断なしで読め、`paraStyle s (Just "caption")` の `psFont` が `Just "caption"`、`psSize` が `Just (Abs (8 × 65536))` になること。
- `[figures]\ncaption = "x"\n` と、`[figures.caption]\nfont = "body"\n` が G0306 になること。

### golem-driver（modules/golem-driver/test/Main.hs）

フォントは `fakeFonts` を使う。
`horizontal24`（10pt、行送り 15pt、30 行、行長 240pt）に `[paragraph-styles.caption]` を足したスタイルで、画像は既存の `tinyImage` とする。

- `size = "8pt"` の `wrap=end width=4zw` の図版で、`pfCaptionSize` が 8pt、`pfCaptionPitch` が 12pt であり、`exLines` が `⌈(4 × 15 + (n − 1) × 12 + 8 + 10) ÷ 15⌉`（n は `pfCaption` の行数）に一致すること。
- `size = "6pt"` で、回り込ませない図版に全角 100 字のキャプションを付けると、キャプションが 3 行（6pt で一行 40 字）になり、`pfCaptionPitch` が 9pt、`pfCaptionSpan` が 2 になること。後の段落の最初の行が、図版の先頭の格子から 24 + 2 個後の格子に置かれること。同じ原稿を `[paragraph-styles.caption]` なしで組むと、キャプションが 5 行で、後の段落が 24 + 5 個後の格子に置かれること。
- 同じ 6pt の原稿の PDF で、キャプションの文字のグリフが大きさ 6 の `Tf` で描かれ、1 行目のベースラインの y 座標が、版面の上端から `(k + 24) × 15pt + round(6pt × 0.88)` 下にあること（k は図版の先頭の格子の番号）。2 行目がその 9pt 下にあること。
- `[fonts.heading]` と `[paragraph-styles.caption] font = "heading"` で、キャプションの文字のグリフが `heading` の役割のフェイス（`fakeFonts` の 4）のフォントのリソースで描かれ、本文のグリフは本文のフォントのリソースで描かれること。
- 本文の大きさでは G0723 になる回り込みの図版（行数を減らした版面で、キャプションの行で除外領域が一ページを超えるもの）が、小さいキャプションでは G0723 にならないこと。
- 縦組みの `pdfStyle` に `size = "10Q"` を足し、回り込ませない図版のキャプションの行が版面の中にあり、1 行目の中心線が画像の左の格子の字面の始まりから 5Q の位置にあること。
- `[paragraph-styles.caption]` に `font = "body"` と版面と同じ `size` を書いた PDF が、書かない PDF とバイト列で一致すること。
- `[paragraph-styles.note] size = "8pt"` と `[paragraph-styles.caption] based-on = "note"` で、キャプションが 8pt で組まれること。
- `[paragraph-styles.caption] first-line-indent = "1zw"` を書いても、キャプションの 1 行目の位置が書かない場合と同じであること。
- 小さいキャプションの回り込みの図版を含む原稿を並列と逐次でビルドし、PDF のバイト列が一致すること。二回のビルドでも一致し、qpdf の検査を通ること。
- 実際のフォントで、本文の欧文を `SourceSansPro-Regular.otf`、`[fonts.caption]` の欧文を `SourceSerifVariable-Roman.ttf` とし、`[paragraph-styles.caption] font = "caption"` で組むと、二つのフォントが埋め込まれ、キャプションのフォントのサブセットにキャプションの文字のグリフだけが入ること。
- HTML：`[paragraph-styles.caption]` に `font = "caption"` と `size = "8pt"` を書き、`[page.grid]` の `font-size` が 10pt の `style.toml` の CSS に、`figcaption { font-family: "golem-caption-latin", serif; font-size: 0.8em; }` が出ること。`size = "0.85zw"` なら `font-size: 0.85em` になること。`[paragraph-styles.caption]` がない場合の CSS が今の golden（`test/golden/html-style.css`）と一致すること。
- `cssFontSize`：`[page.grid]` が 13Q のスタイルで 11Q が `0.846em`、`[page]` のないスタイルで 9pt が `9pt` になること。

自動テストにしない確かめ方として、実装の後に `golem new` の和文の雛形に図版と `[paragraph-styles.caption] size = "10.5Q"` を足してビルドし、縦組みでキャプションが画像の左に詰めて置かれ、キャプションの後の本文が行の格子にそろうことを目で確かめる。
HTML でも、キャプションが本文より小さく表示されることを確かめる。

## トレードオフ

キャプションの行送りを本文の行送りと文字の大きさの比から決めるので、キャプションの行は本文の行の格子に載らない。
格子に載るのは、キャプションの領域の始まりと、図版の後の本文である。
見開きの左右のページでキャプションの行どうしはそろわないが、キャプションは本文と別の大きさで組む要素であり、本文の行がそろうことを優先する。

キャプションが占める格子の数を、キャプションの全体を収める最小の数に切り上げるので、キャプションの後に一行に満たない空きができる。
この空きは図版の後の本文とのあいだに入り、キャプションと本文を分ける空きとして働く。

行の送りの比を、傍注は切り捨て（`div`）、キャプションは見出しと同じ最近接偶数丸め（`round`）で計算する。
傍注の計算を変えると、既存の傍注のある PDF の出力が変わるので、[ADR 0011](0011-sidenote-font.md) でも傍注の計算は変えない。
差は 1sp であり、見た目には現れない。

キャプションの書体と大きさを段落スタイルに置くので、`caption` の欄のうち `font` と `size` だけがキャプションに効き、ほかの欄は `@style caption` の段落にだけ効く。
同じ名前のスタイルで効く欄が場所によって違うのは分かりにくいが、キャプションのために別の表を設けて書き方を二通りにするより、InDesign の段落スタイルにまとめる [docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md) の方針を優先する。
`size` が版面の文字の大きさを超えると G0311 になるので、本文より大きいキャプションは組めない。
キャプションの行は本文の格子に載らないので、この制約はキャプションには本来要らないが、段落スタイルの検査を場所によって変えないことを選ぶ。

HTML の大きさを本文に対する比で書くので、`[page.grid]` のない `style.toml` では絶対の大きさ（pt）になる。
PDF を出力しないプロジェクトでも `size` を書けば効くようにするためであり、比にできない場合だけ絶対の大きさに落とす。
