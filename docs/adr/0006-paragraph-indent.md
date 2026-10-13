# ADR 0006: 段落スタイルで段落の字下げを指定する

ステータス: 採択

## 文脈

段落の字下げ（段落の先頭の字下げ、二行目以降の字下げ、ぶら下げ）を指定する方法がない（[仕様書の「v1 の実装で次の段階以降に回した項目」](../specifications.md)）。
和文の原稿は、段落の先頭に全角の空白を書いて一字下げを表している。
fixture の『蟹工船』（`modules/golem-driver/test/fixtures/kanikosen/kanikosen.gm`）では、449 の行が全角の空白で始まる。
全角の空白は本文の文字なので、PDF、HTML、EPUB、プレーンテキストのすべてにそのまま出る。

字下げの機構は、韻文にだけある。
`[verse]` の `indent`（すべての行の始まりの字下げ）と `hang`（行長を超えて折り返した部分を、さらに下げる量）である（[docs/adr/0003](0003-verse-line-breaks.md)）。
PDF は、行ごとの目標の行長 L*(i) を `measure - indent`（i = 0）と `measure - indent - hang`（i ≥ 1）にして Knuth と Plass の行分割で組み、`SetLine` の `slIndent` で行の始まりをずらす（`Golem.Driver.Pdf` の `widthOf` と `lineIndent`）。
HTML は、行を `display: block` の要素にして、`padding-inline-start` と負の `text-indent` でぶら下げる。

[docs/adr/0005](0005-character-and-paragraph-styles.md) は、段落スタイル（`[paragraph-styles.<名前>]` と `@style 名前`）を加え、韻文を組み込みの段落スタイル `verse` にした。
`[verse]` の `indent` と `hang` は、その ADR では `line-breaks = "keep"` の段落スタイルの段落に効く欄として残してある。
この ADR は、字下げを段落スタイルの欄にし、`[verse]` を廃止する。

InDesign の段落スタイルは、字下げを次の四つの欄で持つ。

- 左インデント：段落のすべての行の始まりの位置。
- 1 行目左インデント：段落の最初の行だけに加える量。左インデントからの相対の値で、負の値も書ける。
- 右インデント、最終行右インデント：行の終わりの側。

ぶら下げ（二行目以降を一行目より深く下げる組み方）は、左インデントを正、1 行目左インデントを同じ量の負にして表す。
InDesign の「左」は横組みの言い方であり、縦組みでは行の始まりの側（天の側）になる。

### 欄の候補

次の二つを比べた。

- InDesign の欄に合わせ、`indent`（すべての行）と `first-line-indent`（最初の行に加える量。負も書ける）の二つにする。ぶら下げは負の `first-line-indent` で表す。
- `[verse]` の欄に合わせ、`first-line-indent`、`indent`、`hang` の三つにする。

二つにする。
三つにすると、同じ字下げを二通りに書けるようになる（`indent = "2zw"` と `first-line-indent = "-2zw"` の組と、`hang = "2zw"` の組）。
InDesign から移る利用者は、左インデントと 1 行目左インデントの組で考える。
`[verse]` の `indent = I`、`hang = H` は、`indent = I + H`、`first-line-indent = -H` に置き換えられる。

### 既定の候補

`body` の段落スタイルの既定について、次の二つを比べた。

- 段落の先頭を一字下げる（`first-line-indent = "1zw"`）。和文の書籍の一般的な組み方を既定にする。
- 字下げをしない（0）。字下げは原稿の全角の空白に任せ、使いたい利用者が `style.toml` で指定する。

字下げをしない既定にする。
既定で一字下げると、全角の空白を書いた既存の原稿は二字下がる。
評価や lint が先頭の全角の空白を取り除くか警告すると、字下げを意図しない全角の空白（会話文の前の空白など）との区別がつかず、lint の「誤検知の余地のある規則は採用しない」（[golem-lint ADR 0001](../golem-lint/adr/0001-lint-rules.md)）に反する。
InDesign の「[基本段落]」も、字下げの既定は 0 である。
既定を 0 にすれば、既存の原稿の出力は変わらない。

## 実装すること

### style.toml の欄（golem-project）

[docs/adr/0005](0005-character-and-paragraph-styles.md) の `[paragraph-styles.<名前>]` に二つのキーを加える。

| キー | 型 | 既定（`body`） | 意味 | InDesign |
|---|---|---|---|---|
| `indent` | 0 以上の寸法 | `"0zw"` | 段落のすべての行の始まりの字下げ | 左インデント |
| `first-line-indent` | 符号付きの寸法 | `"0zw"` | 段落の最初の行に `indent` へ加える量。負ならぶら下げになる | 1 行目左インデント |

- 書かなければ、ほかのキーと同じく `based-on` の値を引き継ぐ（[docs/adr/0005](0005-character-and-paragraph-styles.md) の「based-on の解決」）。
- `zw` は、その段落の文字の大きさ（段落スタイルの `size`、なければ版面の文字の大きさ）を一字とする。
- 解決した `indent` と `first-line-indent` を同じ文字の大きさで sp にした和が負なら、G0312 とする。最初の行の始まりが版面の外に出るためである。`zw` と絶対の単位が混ざる場合も、段落の文字の大きさで sp にしてから比べる。段落の文字の大きさは `[page.grid]` があるときだけ決まるので、ないときは両方が `zw` の場合と両方が絶対の単位の場合だけを検査する。

| 診断コード | 重大度 | メッセージ |
|---|---|---|
| G0312 | エラー | `段落の最初の行が版面の外に出ます。indent と first-line-indent の和を 0 以上にしてください: <名前>` |

G0312 は未使用である（[docs/adr/0005](0005-character-and-paragraph-styles.md) が G0311 と G0313 を、[golem-project ADR 0004](../golem-project/adr/0004-font-file-check-per-target.md) が G0310 を使う）。

負の寸法を読むため、`Golem.Project.Style` に `parseSignedDim :: Text -> Maybe Dim` を加える。
先頭の `-` を一つだけ許し、残りを `parseDim` で読んで符号を反転する。
`Dim` の型は変えない（`Abs` と `Zw` は負の値を持てる）。
`first-line-indent` だけがこの関数を使い、ほかの寸法の欄は今と同じく負の値を構文エラーとする。

`ParaStyleDef` に `psIndent :: !(Maybe Dim)` と `psFirstLineIndent :: !(Maybe Dim)` を加える。
`paraStyle` はこの二つも既定で埋める。

### 組み込みのスタイルの既定と [verse] の廃止

| 段落スタイル | `indent` | `first-line-indent` |
|---|---|---|
| `body` | `"0zw"` | `"0zw"` |
| `verse` | `"2zw"` | `"-2zw"` |

`verse` の既定は、`[verse]` の既定（`indent = "0zw"`、`hang = "2zw"`）と同じ組み方である。

`[verse]` の節を廃止し、`VerseStyle`、`defaultVerseStyle`、`stVerse` を削る。
`[verse]` を書いた `style.toml` は G0306 とし、メッセージで `[paragraph-styles.verse]` の `indent = I + H`、`first-line-indent = -H` への書き換えを示す。

### 字下げが効く段落

字下げは、意味論 IR の `Paragraph` のブロックにだけ効く。

- 文書の最上位の段落、`@style` の本体の段落、定義リストの説明の段落に効く。
- リストの項目の中の段落には効かない。項目の最初の行には `・` や番号の印が付くので、段落の字下げを加えると印の前が空くためである。リストの字下げは別に扱う。
- 図版のキャプションの段落には効かない。キャプションの段落は意味論 IR では `Paragraph` だが、図番号と一つのまとまりとして図版の書式で組むためである。
- 脚注と傍注の本文、表のセル、見出し、目次、索引、参考文献の行は段落ではないので、効かない。
- 組み込みの段落スタイル `caption` と `sidenote`（[docs/adr/0005](0005-character-and-paragraph-styles.md)）に書いた `indent` と `first-line-indent` も、図版のキャプションと傍注の本文には効かない。キャプションと傍注が使うのは `font` と `size` だけである（[golem-driver ADR 0010](../golem-driver/adr/0010-caption-style.md)、[golem-driver ADR 0011](../golem-driver/adr/0011-sidenote-font.md)）。`@style caption` を付けた原稿の段落には、ほかの段落スタイルと同じく効く。
- 段落が `LineBreak` を含む場合（[docs/adr/0005](0005-character-and-paragraph-styles.md) の `line-breaks = "keep"` の段落の各行）は、`LineBreak` で区切った各部分を段落の始まりと同じく扱う。各部分の最初の行が `first-line-indent` を受け、折り返した行が `indent` の位置から始まる。韻文の各行がぶら下がるのはこの規則による。

最後の規則は、InDesign の強制改行（Shift+Enter）と異なる。
InDesign では、強制改行の後の行は 1 行目左インデントを受けない。
Golem の原稿で `LineBreak` を生むのは `keep` の段落スタイルだけであり、そこでは原稿の一行が InDesign の一段落にあたるので、この扱いにする。

### PDF（golem-driver）

`Golem.Driver.Pdf` の単位の種類を次のように改める。

```haskell
-- | 段落の行の字下げ（sp）。inFirst は負になりうる。inStart + inFirst >= 0。
data Indent = Indent {inStart :: !Sp, inFirst :: !Sp}
  deriving stock (Eq, Show)

noIndent :: Indent
noIndent = Indent 0 0

data UnitKind
  = UPara !Indent
  | UHeading Int Text Bool
  | UTerm
  | UFigure Figure
  | UTable [Alignment] [[Inline]] [[[Inline]]]
  | UGap Int
  -- UVerseLine を削る
```

- `unitsOf` は、`Paragraph` の各部分（[docs/adr/0005](0005-character-and-paragraph-styles.md) で `LineBreak` で分けたもの）を `UPara ind` にする。`ind` は、解決した段落スタイルの `indent` と `first-line-indent` を段落の文字の大きさで sp にしたものである。`keep` かどうかで単位の種類を分けない。
- リストの項目の中の段落、目次、索引、参考文献の行、コードブロックの行は `UPara noIndent` にする。`unitsOf` の `block` に、リストの項目の中かどうかを表す引数を加える。
- `widthOf (UPara (Indent s f)) k` は、`k == 0` なら `measure - s - f`、ほかは `measure - s` とする。
- `lineIndent (UPara (Indent s f)) k` は、`k == 0` なら `s + f`、ほかは `s` とする。
- `SetLine` の `slIndent` と `drawLine` は変えない。`slIndent` は行の始まりの側からの距離なので、縦組みでは天からの距離になる。

回り込みの図版の脇の段落も、字下げを受ける。

- `wrapJob` の行長は、`wrappedLineWidth measure ex offset k` から、上の `widthOf` の字下げの分を引いた値とする。
- 行の始まりのずらしは、今の `indentOf off k`（`wrap=start` の図版の脇では除外領域の幅）に `lineIndent` を足した値とする。
- [docs/adr/0003](0003-verse-line-breaks.md) が `UVerseLine` を回り込みの脇で組まないとしたのは、単位の種類が違ったためである。韻文の行も `UPara` になるので、図版の直後の韻文も脇で組む。

字下げが大きすぎる段落スタイルは、PDF の組版の前に検査する。

- 解決した各段落スタイルについて、`measure - inStart - max 0 inFirst` が段落の文字の大きさの 8 字分に満たなければ、G0725 とする。基準を 8 字分にするのは、回り込みの図版の脇の行の下限（G0722、[golem-driver ADR 0005](../golem-driver/adr/0005-pdf-wrapped-figures.md)）に合わせるためである。
- 回り込みの図版の脇で、行長から字下げを引いた値が 0 以下になる行があれば、その段落の位置で G0725 とする。

| 診断コード | 重大度 | メッセージ |
|---|---|---|
| G0725 | エラー | `段落の字下げが大きすぎます。行長を本文の文字の大きさの 8 字分以上残してください: <名前>` |

G0725 は未使用である（golem-driver は G0721 から G0724 までを使っている）。

### HTML と EPUB（golem-html）

[docs/adr/0005](0005-character-and-paragraph-styles.md) の `HtmlParaStyle` に二つの欄を加え、`HtmlConfig` の `hcVerseIndent` と `hcVerseHang` を削る。

```haskell
data HtmlParaStyle = HtmlParaStyle
  { hpsFont :: !(Maybe Text),
    hpsKeepLines :: !Bool,
    hpsSpaceBetween :: !Int,
    hpsIndent :: !Text,         -- CSS の長さ
    hpsFirstLineIndent :: !Text -- CSS の長さ。負になりうる
  }
```

golem-driver は今の `cssLength` で寸法を変換する（`zw` は `em`、ほかは `pt`、小数は 3 桁まで、負の符号を保つ）。

CSS を次の規則で書く。

- `body` の字下げが 0 でなければ `p { padding-inline-start: I; text-indent: F; }` を書く。
- `body` 以外の段落スタイルで、解決した字下げが `body` と異なれば `p.ps-名前 { padding-inline-start: I; text-indent: F; }` を書く。同じなら書かない。`p` の規則がそのまま効くためである。
- どれかの規則を書いた場合は、`li p, li p[class] { padding-inline-start: 0; text-indent: 0; }` を続けて書く。リストの項目の中の段落に字下げを効かせないためである。`li p[class]` は `p.ps-名前` より強い詳細度を持つ。
- [docs/adr/0005](0005-character-and-paragraph-styles.md) の `keep` の段落スタイルの規則（`margin-inline-start` と `.line` の `padding-inline-start` と負の `text-indent`）を削る。`text-indent` は子の要素に継承され、`display: block` の `.line` の最初の行ごとに効くので、上の規則だけで各行がぶら下がる。`p.ps-名前 { margin-block: 0; }` は残す。

`padding-inline-start` と `text-indent` は論理方向の指定なので、縦組み（`writing-mode: vertical-rl`）でも行の始まりの側に効く。
既定の `style.toml` では規則を一つも書かないので、今の golden（`test/golden/html-style.css`）は変わらない。

### プレーンテキスト（golem-text）

プレーンテキストには行長がないので、段落の最初の行の字下げだけを全角の空白で表す。

- 解決した `indent` と `first-line-indent` がどちらも `zw` で書かれていれば、和の整数部の数（0 以上）の全角の空白を、段落の先頭に置く。`LineBreak` で区切った各部分の先頭にも置く。
- どちらかが絶対の単位なら、字下げを出力しない。文字の大きさが決まらない媒体で、長さを字数に変換できないためである。
- リストの項目の中の段落には置かない。入れ子の字下げ（`indentBy ind`）はこれまでどおり前に置く。

`renderText` に、段落スタイルの名前（`Nothing` は `body`）から全角の空白の数を返す関数を引数として加え、golem-driver が解決した段落スタイルから作る。
`verse` の既定では和が 0 なので、韻文のテキストの出力は変わらない。

### 縦組み

字下げは、横組みでも縦組みでも行の始まりの側から測る。
縦組みの `indent = "1zw"` は、すべての行を天から一字下げる。
欄の名前に「左」を入れないのは、縦組みで左が行の始まりを指さないためである。

### ドキュメント

- 仕様書の「style.toml」の例から `[verse]` を削り、`[paragraph-styles.verse]` に `indent` と `first-line-indent` を書いた例と、`body` の `first-line-indent = "1zw"` の例を加える。字下げの既定が 0 であり、原稿の全角の空白と併用すると二重に下がることを書く。
- 仕様書の「v1 の実装で次の段階以降に回した項目」から「字下げ」を削る。
- docs/markup.md の「韻文」の節の、`[verse]` の `indent`、`hang`、`stanza-gap` の文を、`[paragraph-styles.verse]` の `indent`、`first-line-indent`、`space-between` に改める。
- docs/glossary.md に「字下げ」の項目（`indent` と `first-line-indent`、行の始まりの側から測ること）を加える。
- README の `style.toml` の説明を改める。
- [docs/adr/0003](0003-verse-line-breaks.md) のステータスの行を「採択→記法と `stanza-gap` は [docs/adr/0005](0005-character-and-paragraph-styles.md)、`indent` と `hang` は [docs/adr/0006](0006-paragraph-indent.md)」に変える。

## データ構造の変更

- golem-project：`ParaStyleDef` に `psIndent` と `psFirstLineIndent` を加える。`parseSignedDim` を新設する。`VerseStyle`、`defaultVerseStyle`、`stVerse` を削る。
- golem-driver：`Indent` を新設する。`UnitKind` の `UPara` が `Indent` を持ち、`UVerseLine` を削る。
- golem-html：`HtmlParaStyle` に `hpsIndent` と `hpsFirstLineIndent` を加え、`HtmlConfig` の `hcVerseIndent` と `hcVerseHang` を削る。
- golem-text：`renderText` に段落スタイルの字下げの引数を加える。

意味論 IR は変えない。
字下げは幾何なので、段落スタイルの名前だけを IR に置き、値は `style.toml` から各媒体の出力が引く（[docs/adr/0005](0005-character-and-paragraph-styles.md)）。

## 実装しないこと

- 行の終わりの側の字下げ（InDesign の右インデント、最終行右インデント）。
- `hang` のキー。負の `first-line-indent` で表す。
- 段落の先頭の始め括弧類の位置の調整（JLReq の、段落の先頭が「「」で始まる場合に字下げを半角にする組み方など）。
- 原稿の先頭の全角の空白を取り除くこと、警告すること。
- リストの項目と、入れ子のリストの字下げ。
- `@style` の引数で段落ごとに字下げを上書きすること。
- ドロップキャップ、字取り。
- 字下げを `zw` 以外の単位で書いた段落の、プレーンテキストでの字下げ。

## テスト設計

先に書き、失敗させてから実装する。

### golem-project（`modules/golem-project/test/Main.hs`）

- 空の `style.toml` で、`paraStyle s Nothing` の字下げが `Zw 0` と `Zw 0`、`paraStyle s (Just "verse")` が `Zw 2` と `Zw (-2)` であること。
- `[paragraph-styles.quote] indent = "2zw"` で、`quote` の `first-line-indent` が `body` の値を引き継ぐこと。
- `parseSignedDim` が `"-1.5zw"` を `Zw (-3/2)`、`"-3mm"` を負の `Abs` に、`"--1zw"` と `"-zw"` を `Nothing` にすること。
- `indent = "-1zw"` が G0306、`indent = "1zw"` と `first-line-indent = "-2zw"` の組が G0312、`indent = "2zw"` と `first-line-indent = "-2zw"` の組が通ること。
- `[page.grid] font-size = "13Q"` で、`indent = "1mm"` と `first-line-indent = "-1zw"` の組が G0312 になること（1zw は 3.25mm）。
- `[verse] indent = "0zw"` が G0306 になり、メッセージに `[paragraph-styles.verse]` が含まれること。

### golem-driver（`modules/golem-driver/test/Main.hs`）

PDF は `flowLines` の `(lineTarget, slIndent)` の組で確かめる。

- 横組み、字数 30 の版面で、`[paragraph-styles.body] first-line-indent = "1zw"` の 45 字の段落が二行に組まれ、一行目の `slIndent` が一字分、`lineTarget` が行長から一字分を引いた値、二行目の `slIndent` が 0、`lineTarget` が行長であること。
- `indent = "2zw"`、`first-line-indent = "-2zw"` の段落で、一行目の `slIndent` が 0、二行目が二字分であること。
- [docs/adr/0003](0003-verse-line-breaks.md) と [docs/adr/0005](0005-character-and-paragraph-styles.md) の韻文の PDF のテストが、`[verse]` を使わない既定のままで同じ `slIndent` と `lineTarget` になること。
- 縦組みのスタイル（既存の `pdfStyle`）で、`first-line-indent = "1zw"` の一行目の `slIndent` が一字分であり、描いた最初のグリフの位置が天の側に一字分ずれること。
- リストの項目の段落と、目次の行では、`body` に `first-line-indent = "1zw"` があっても `slIndent` が 0 であること。
- 定義リストの説明の段落では `slIndent` が一字分であること。
- `wrap=start` の図版の直後の段落で、脇の一行目の `slIndent` が除外領域の幅と一字分の和であること。
- 字数 10 の版面で `indent = "3zw"` が G0725 になること。
- HTML：`body` に `first-line-indent = "1zw"` を指定すると、`style.css` に `p { padding-inline-start: 0em; text-indent: 1em; }` と `li p, li p[class]` の規則があること。`verse` の CSS が `p.ps-verse { padding-inline-start: 2em; text-indent: -2em; }` を含み、`.line` の規則を含むこと。既定の `style.toml` の CSS が golden と一致すること。
- プレーンテキスト：`first-line-indent = "1zw"` の段落が全角の空白一つで始まること。`first-line-indent = "3mm"` では空白が付かないこと。リストの項目には付かないこと。
- `scripts/determinism.sh` が出力する sample の各ファイルのハッシュと、`kanikosen` と `tempest` の各ターゲットの出力が、この ADR の前と変わらないこと。既定の字下げが 0 であり、韻文の既定が `[verse]` の既定と同じ組み方であることの確認である。

### 自動テストにしない確かめ方

実装の後に、`first-line-indent = "1zw"` と、ぶら下げ（`indent = "1zw"`、`first-line-indent = "-1zw"`）の段落を含む原稿を、縦組みと横組みで PDF と EPUB にし、ビューアーと EPUB の読書環境（Apple Books と Thorium）で字下げの位置を目で確かめる。

## トレードオフ

既定の字下げを 0 にするので、段落スタイルで字下げを指定する利用者は、原稿の先頭の全角の空白を自分で消す必要がある。
消し忘れた段落は二字下がり、処理系はそれを指摘しない。
既定で一字下げる方式は、既存の原稿の出力を変え、全角の空白を書く慣習の原稿を一律に二字下げにするので採らない。

`hang` のキーをなくすので、`[verse]` の `hang = "3zw"` のような指定は、`indent` と負の `first-line-indent` の二つのキーに書き換える必要がある。
InDesign の欄と一対一に対応し、同じ字下げの書き方を一つにする利点を取る。

`LineBreak` で区切った各部分が最初の行の字下げを受けるので、InDesign の強制改行と意味が違う。
Golem では強制改行を書く記法が `keep` の段落スタイルしかないので、この差が問題になるのは、プラグインが `join` の段落に `LineBreak` を入れた場合だけである。

プレーンテキストで字下げを表すのは `zw` で書いた場合の整数部だけなので、`1.5zw` は一字、`5mm` は字下げなしになる。
行長も文字の大きさもない媒体で、最初の行の字下げを字数に近似するのは、全角の空白を書いた原稿の出力と見た目を近づけるためである。

リストの項目の段落に字下げを効かせないので、項目の中に置いた `@style quote` の段落も字下げされない。
リストの字下げを決めるまでは、項目の印の前が空く組み方を避けることを優先する。
