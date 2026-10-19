# ADR 0006: CIDSystemInfo と異体字の選択

ステータス: 採択→ToUnicode で表せないクラスタに ActualText を使うことは [golem-driver ADR 0030](../../golem-driver/adr/0030-ligature-text-layer.md) で加えた、異体字セレクタを前の字に付ける処理を結合文字に広げたことは [golem-driver ADR 0036](../../golem-driver/adr/0036-combining-characters.md)

## 文脈

[仕様書](../../specifications.md)の「未決事項」は、PDF に埋め込むフォントの CID の扱いを挙げている。
Adobe-Japan1 の文字集合を持つ和文フォントで `CIDSystemInfo` を Adobe-Japan1 にするか、それがプリフライトや出力機（RIP）にどう影響するか、異体字の選択（IVS）をどう表すかが決まっていない。

### 今の実装

[golem-font ADR 0002](../../golem-font/adr/0002-subsetting-and-embedding.md) は、フォントを Type 0 のフォントと CIDFont で埋め込み、文字のコードを `Identity-H`（縦組みでは `Identity-V`）とすると決めた。
実装は次のとおりである。

- `Golem.Font.glyphCid`（C の `golem_font_cid`）は、FreeType が内部で CID-keyed と判定した CFF のフォントではグリフの CID を、それ以外のフォントではグリフ ID を返す。golem-driver の `Golem.Driver.Fonts` は、この値を内容のストリームの文字のコード、`W`、`W2`、ToUnicode に使う。
- `Golem.Pdf.Writer.fontObjects` は、どのフォントでも CIDFont の `CIDSystemInfo` を `<< /Registry (Adobe) /Ordering (Identity) /Supplement 0 >>` と書く。
- CFF のフォントは `CIDFontType0` と `FontFile3`（`/Subtype /OpenType`）、TrueType のフォントは `CIDFontType2` と `FontFile2` と `/CIDToGIDMap /Identity` で書く。

テストのフォントで実際の値を確かめた（golem-font を `cabal repl` で読み込んで調べた）。

- 『蟹工船』の fixture の Noto Serif JP（Noto Serif CJK 2.003 の Subset OTF）は CID-keyed の CFF で、CFF の ROS（Registry、Ordering、Supplement）は Adobe-Identity-0 である。CID はグリフ ID と一致しない。たとえばグリフ 466（`U+2014`）の CID は 722、グリフ 11183（`葛`）の CID は 34493 である。
- golem-font のテストの Source Han Sans のサブセットも ROS が Adobe-Identity-0 であり、Source Sans Pro は CID-keyed でない CFF である。
- hb-subset で `retain-gids` のサブセットを作っても、使ったグリフの CID は元のフォントと変わらない（グリフ 466、1100、11183、15282、16314、17596 で確かめた）。

したがって、今のテストのフォントについては、`CIDSystemInfo` の Adobe-Identity-0 はフォントの ROS と一致している。
一致しないのは、ROS が Adobe-Japan1-N の CID-keyed のフォントを使ったときである。
市販の和文の OpenType フォントの多くはこの形である（記憶による。リポジトリにはこの形のフォントがない）。

### PDF での CIDSystemInfo の役割

以下は PDF の仕様（ISO 32000）の記憶による整理であり、本文と照合していない。

- CIDFont の `CIDSystemInfo` は、その CIDFont の CID がどの文字集合の番号かを示す。
- 埋め込んだ CID-keyed の CFF では、CID は CFF の charset を通してグリフに写る。`CIDSystemInfo` の値は、グリフの選択には使われない。
- 符号化が `Identity-H` か `Identity-V` なら、どの `CIDSystemInfo` の CIDFont と組み合わせてもよい。

`CIDSystemInfo` が描画に効くのは、フォントの実体を使わない処理である。
フォントを埋め込まない PDF を開くときの代替のフォント、ToUnicode がない PDF からの文字の抽出（Adobe-Japan1 なら `Adobe-Japan1-UCS2` の対応で文字に戻せる）、搭載のフォントへの差し替えの機能を持つ RIP が、その例である。
Golem の PDF/X-4 はフォントを必ず埋め込み、ToUnicode を必ず付けるので、前の二つは起きない。
三つ目は、出力の側で埋め込みのフォントを搭載のフォントに差し替える設定にした場合に限られる（そうした機能を持つ RIP がある、という記憶による。確かめていない）。

### InDesign の挙動

InDesign が書き出す PDF は、Adobe-Japan1 の OpenType フォントを `CIDFontType0` で埋め込み、`CIDSystemInfo` にフォントの ROS（たとえば Adobe-Japan1-6）を書くと記憶している。
Adobe の公式の資料では確かめられなかった。
TrueType のフォントについては Adobe-Identity-0 になると記憶しているが、これも確かめていない。

### 異体字の選択（IVS）

[markup.md](../../markup.md) は Unicode の正規化を行わないと定めており、原稿に書いた異体字セレクタ（`U+E0100` から `U+E01EF`、`U+FE00` から `U+FE0F`）は IR まで残る。
しかし PDF では IVS が効いていない。
`Golem.Layout.Japanese.textPieces` は、和文の文字を一字ずつ `PChar` にするので、異体字セレクタも前の文字と別の箱になる。
golem-driver は箱ごとに `lfShape` でシェイピングするので、基底の文字と異体字セレクタが別々にシェイピングされ、フォントの cmap の format 14 が引かれない。

二つを一緒にシェイピングすれば効くことは確かめた。
Noto Serif JP で `葛` だけをシェイピングするとグリフ 11183、`葛` と `U+E0100` を一緒にシェイピングするとグリフ 16314 になる。
`葛` と `U+E0101` ではグリフ 11183 の一つになる（フォントの既定の字形を指す IVS か、フォントにない IVS で、HarfBuzz が異体字セレクタを消したと考えられる。どちらかは確かめていない）。

ToUnicode は、`Golem.Driver.Fonts` の `clusterText` が、クラスタの先頭の一字だけをグリフの文字とする。
基底の文字と異体字セレクタを一緒にシェイピングすれば、異体字のグリフの ToUnicode は基底の文字だけになる。

## 実装すること

### CIDSystemInfo をフォントの ROS にする

CID-keyed の CFF のフォントでは、CIDFont の `CIDSystemInfo` を、埋め込むフォントの CFF の ROS と同じ値にする。
それ以外のフォント（TrueType と、CID-keyed でない CFF）は、今のとおり Adobe-Identity-0 とする。

- golem-font の C の層に `int golem_font_ros(golem_font *f, const char **registry, const char **ordering, int *supplement)` を加える。`FT_Get_CID_Is_Internally_CID_Keyed` が真で、`FT_Get_CID_Registry_Ordering_Supplement` が成功したときに 0 を返し、それ以外は -1 を返す。
- `Golem.Font` に次の型と関数を加え、公開する。値は `loadFont` のときに一度だけ読み、`Font` のフィールドに持つ。

```haskell
data CidSystemInfo = CidSystemInfo
  { csiRegistry :: !Text,
    csiOrdering :: !Text,
    csiSupplement :: !Int
  }
  deriving stock (Eq, Show)

-- | The ROS of a CID-keyed CFF font; Nothing for any other font.
fontCidSystemInfo :: Font -> Maybe CidSystemInfo
```

- Registry と Ordering が印字可能な ASCII（`' '` から `'~'`）でないか、Supplement が負なら `Nothing` とする。PDF の文字列にそのまま書ける値に限るためである。
- `Golem.Pdf.Writer.Font` に `fontCidSystemInfo :: !(Text, Text, Int)` を加え、`fontObjects` は CIDFont の `CIDSystemInfo` をこの値から書く。golem-pdf は golem-font に依存しないので、型は組で受け取る。
- `Golem.Driver.Fonts.embed` は、`fontCidSystemInfo f` が `Just` ならその値を、`Nothing` なら `("Adobe", "Identity", 0)` を渡す。
- 符号化（`Identity-H`、`Identity-V`）、文字のコード（`glyphCid`）、`CIDToGIDMap` は変えない。
- ToUnicode の CMap の中の `CIDSystemInfo`（Adobe-UCS-0）は変えない。

この変更で、Noto Serif JP と Source Han Sans の PDF のバイト列は変わらない。
変わるのは、ROS が Adobe-Identity-0 でない CID-keyed のフォント（Adobe-Japan1 のフォントなど）を使った PDF だけである。

### 異体字セレクタを前の文字と一つの箱にする

- `Golem.Layout.Japanese` に `isVariationSelector :: Char -> Bool` を置き、`U+FE00` から `U+FE0F` と `U+E0100` から `U+E01EF` を真とする。
- `textPieces` は、異体字セレクタ（続けて複数あればそのすべて）を、直前の `PChar` か `PWord` に付ける。直前が空白か段落の先頭なら、今のとおり一字の `PChar` とする。
- `PChar` の文字を `!Char` から基底の文字と異体字セレクタの組 `!Char !Text`（異体字セレクタがなければ空）に変える。箱の `bcText` は基底の文字に異体字セレクタをつないだ文字列とする。
- 異体字セレクタの付いた `PChar` の幅は、`ceWordAdvance lk (基底の文字 <> 異体字セレクタ)` で、二つを一緒にシェイピングした送りとする。付いていなければ今のとおり `ceAdvance` とする。
- 文字の分類（`charClass`）は基底の文字で決める。`normalize` の `textClass`、`firstClass`、`lastClass` は、`bcText` の末尾の異体字セレクタを除いてから文字を取り出す。`textClass` の「一字の箱」の判定も、異体字セレクタを除いた長さで行う。禁則と約物の空きが、異体字セレクタの有無で変わらないようにするためである。
- `Golem.Driver.Fonts` の `runs` と、`Golem.Driver.Pdf` の `runsOf` の和欧の分割は、異体字セレクタを直前の文字と同じ側に入れる。異体字セレクタは `charClass` では和文に分類されるので、欧文の文字に付いたときに別のフォントへ分かれないようにする。

### ToUnicode

- 異体字のグリフの ToUnicode は、基底の文字だけとする。グリフの文字列から異体字セレクタを除く処理を `Golem.Driver.Fonts` の `clusterText` に置く。今の `clusterText` はクラスタの先頭の一字だけを返すので結果は変わらないが、[golem-font ADR 0002](../../golem-font/adr/0002-subsetting-and-embedding.md) のとおりクラスタの全体を返すように直したときにも、異体字セレクタが入らないようにするためである。
- `ActualText` は使わない。

基底の文字だけにするのは、PDF の中の検索で、異体字を基底の文字で見つけられるようにするためである。
異体字セレクタを含めると、既定の字形を指す IVS（`葛` と `U+E0101` の組）のように、同じグリフに異体字セレクタのある文字列とない文字列の両方が対応する場合がある。
ToUnicode は一つのグリフに一つの文字列しか持てないので、文書の中で先に現れたほうが勝ち、同じ字形でも抽出の結果が文書によって変わる。

### 媒体ごとの扱い

HTML、EPUB、プレーンテキストは、今のとおり異体字セレクタを原稿のまま出力する。
字形の選択は閲覧の環境のフォントに任せる。

### 決定性

- `CIDSystemInfo` の値は、フォントのバイト列だけから決まる。
- 異体字セレクタの扱いは原稿の文字列だけから決まり、HarfBuzz の版を固定しているので、選ばれるグリフも決まる。

### ドキュメント

- 仕様書の「未決事項」から「CID の扱い」の項目を除く。
- 仕様書の「フォント」の節に、次の内容を加える。CID-keyed の CFF のフォントは CID を文字のコードとし、`CIDSystemInfo` をフォントの ROS とする。それ以外のフォントはグリフ ID を文字のコードとし、`CIDSystemInfo` を Adobe-Identity-0 とする。原稿の異体字セレクタは PDF では字形の選択に使い、ToUnicode には基底の文字だけを書く。この ADR へのリンクを付ける。
- 用語集に、異体字セレクタと IVS を加える。
- [golem-font ADR 0002](../../golem-font/adr/0002-subsetting-and-embedding.md) のステータスの行を「採択→`CIDSystemInfo` と異体字セレクタの ToUnicode は [golem-pdf ADR 0006](../../golem-pdf/adr/0006-cid-system-info.md)」に変える。リンクは書き込む先のファイルからの相対パスである。
- [golem-layout ADR 0002](../../golem-layout/adr/0002-japanese-composition.md) のステータスの行に「、異体字セレクタの箱は [golem-pdf ADR 0006](../../golem-pdf/adr/0006-cid-system-info.md)」を加える。

### 診断

新しい診断は加えない。

## 実装しないこと

- フォントにない IVS の警告。HarfBuzz は、フォントにない IVS では基底の文字の既定の字形を選ぶ。フォントにない字の検出（InDesign の字形の欠落の表示に当たるもの）は、IVS に限らない機能として別の ADR で扱う。
- `ActualText` による原稿の文字列の保存。
- Adobe-Japan1 の CID を原稿で直接指定する記法（InDesign の字形パネルによる字形の選択に当たるもの）。
- Adobe-Identity-0 のフォントの CID を Adobe-Japan1 の CID に写し直すこと。フォントの ROS と異なる値を書くと、`CIDSystemInfo` が CID の意味を偽ることになる。
- TrueType のフォントで `CIDSystemInfo` を Adobe-Identity-0 以外にすること。
- Ideographic Description Sequence や、CJK 互換漢字を異体字セレクタの組に置き換える処理。

## テスト設計

### golem-font（`modules/golem-font/test/Main.hs`）

- Source Han Sans のサブセットの `fontCidSystemInfo` が `Just (CidSystemInfo "Adobe" "Identity" 0)` であること。
- Source Sans Pro（CID-keyed でない CFF）と Source Serif の可変フォント（TrueType）の `fontCidSystemInfo` が `Nothing` であること。
- Source Han Sans のサブセットを `subsetFont` でさらにサブセット化したフォントの `fontCidSystemInfo` が、元と同じであること。
- 同じサブセットで、使ったグリフの `glyphCid` が元のフォントと一致すること。

### golem-pdf（`modules/golem-pdf/test/Main.hs`）

- `fontCidSystemInfo = ("Adobe", "Japan1", 7)` の `Font` を書いた PDF の CIDFont に `/CIDSystemInfo << /Ordering (Japan1) /Registry (Adobe) /Supplement 7 >>` があること（辞書のキーは整列して書かれる）。
- `("Adobe", "Identity", 0)` のときに、この変更の前と同じバイト列になること。既存の golden を変えずに通ることで確かめる。

### golem-layout（`modules/golem-layout/test/Main.hs`）

- `葛` と `U+E0100` を含む段落を `composeInlines` で組むと、二つが一つの箱になり、箱の `bcText` が二字の文字列になること（`textPieces` は公開されていないので、`composeInlines` の結果で確かめる）。
- 異体字セレクタの付いた `葛` の後の `、` に、付いていない場合と同じ約物の空きが入ること。
- 異体字セレクタの付いた始め括弧類の後で、行頭禁則が付いていない場合と同じに働くこと（`「` と `U+FE00` の後で改行しない）。
- 段落の先頭の異体字セレクタが、一字の箱のまま残ること。

### golem-driver（`modules/golem-driver/test/Main.hs`）

『蟹工船』の fixture の Noto Serif JP を使う。

- `lfShape body False "葛\xE0100"` がグリフ 16314 の一つを返し、その文字が `葛` であること。
- `葛` と `U+E0100` を含む一段落の縦組みと横組みの PDF で、内容のストリームに CID 61923（グリフ 16314）の文字のコードがあり、そのフォントの ToUnicode が CID 61923 を `葛`（`U+845B`）に対応させること。
- 同じ PDF で、異体字セレクタだけのグリフ（グリフ ID 0 か、異体字セレクタの文字に対応する ToUnicode の項目）がないこと。
- 『蟹工船』の PDF の CIDFont の `CIDSystemInfo` が、Adobe-Identity-0 のままであること。

### 手作業の確認

- Adobe-Japan1 の CID-keyed の OpenType フォント（たとえば Adobe Fonts の小塚明朝 Pr6N）で同じ原稿を組み、PDF の CIDFont の `CIDSystemInfo` がフォントの ROS になっていることを確かめる。InDesign で同じフォントを使って書き出した PDF の `CIDSystemInfo` と見比べ、文脈の InDesign の挙動の記憶を確かめる。
- その PDF を Acrobat のプリフライトの PDF/X-4 の検査にかけ、フォントについて指摘がないことを確かめる。
- 異体字を含む PDF を Acrobat で開き、異体字が表示されること、検索で基底の文字から見つかること、複写した文字列が基底の文字になることを確かめる。

## トレードオフ

`CIDSystemInfo` をフォントの ROS にすると、出力の側で搭載のフォントに差し替える RIP では、Adobe-Japan1 の和文フォントが同じ CID の搭載のフォントに差し替わる余地が生まれる。
Adobe-Identity-0 のままなら、CID の意味が分からないので差し替えは起きない。
差し替えが起きると、埋め込んだフォントと異なる字形で印刷される。
それでも ROS に合わせるのは、`CIDSystemInfo` がフォントの CID の意味を正しく表すことを優先するからである。
差し替えは出力の側の設定であり、Golem の PDF の誤りではない。

ToUnicode を基底の文字だけにすると、PDF から複写した文字列では異体字の区別が失われる。
印刷用の PDF の文字の抽出は検索と校正の確認に使われることが多く、そこでは基底の文字で見つかるほうが役に立つ。
区別を残すには `ActualText` が要るが、内容のストリームにマーク付きの内容を書く仕組みが golem-pdf にまだない。
