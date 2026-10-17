# ADR 0030: 合字のテキスト層

ステータス: 採択

## 文脈

十冊の fixture（[docs/adr/0026](../../adr/0026-ten-public-domain-fixtures.md)）の英語の本と The Tempest の PDF から文字を抜き出すと、合字で組んだ fi、fl、ff、ffi、ft が f の一字になる。
ロードマップの「合字のテキスト層」の項目である。

### 再現

Source Serif（fixture の The Tempest のフォント）を本文の欧文のフォントにした横組みの小さなプロジェクトで、一行の原稿 `office fluffy affix final left-hand` を組んだ。
PDFKit（macOS の PDF の読み込みの枠組み）で PDF の文字列を抜き出すと、`offce fufy affx fnal lef-hand` になった。
ToUnicode の CMap を展開すると、合字のグリフ 4 個（グリフ ID 0x019E から 0x01A1）がどれも `<0066>`（`f`）に対応していた。
原稿の i と t は、どれも合字の中にあったので、それだけで ToUnicode に現れるグリフはなかった。
同じ PDF を 8b449eb（fixture を加えたコミット）と e3e19da（今の `main`）で作り、どちらでも同じ結果になることを確かめた。

### 原因

ToUnicode の入力は、ページに描いたグリフごとの文字列（`Golem.Driver.Pdf` の `GlyphUse` の `guText`）であり、その文字列はシェイピングの結果の `Shaped` の `shText` から来る。
`shText` は、`Golem.Driver.Fonts` の `shapeText` の中の `clusterText` が作る。
`clusterText r c` は、ラン `r` の UTF-8 のバイト列のうち、クラスタの先頭のバイト位置 `c` から一字だけを取る。
合字のグリフはクラスタの全体（`ffi` なら三字）に当たるが、`clusterText` は先頭の `f` だけを返す。
`lfEmbed` は、この文字列をそのまま ToUnicode の対応に使うので、合字が f になる。

[golem-font ADR 0002](../../golem-font/adr/0002-subsetting-and-embedding.md) は、合字のグリフをクラスタの文字列の全体に対応させると定めている。
golem-font には、そのとおりに作った `Golem.Font.toUnicode` とそのテストがある。
しかし、PDF の経路（[ADR 0002](0002-pdf-pipeline.md)）は `Golem.Font.toUnicode` を使わず、`Golem.Driver.Fonts` で一字だけを取る形を別に書いた。
不具合は、採択した ADR と実装の食い違いである。
[golem-pdf ADR 0006](../../golem-pdf/adr/0006-cid-system-info.md) は、`clusterText` が一字だけを返すことを知ったうえで、異体字セレクタを除く処理をそこに置いた。
クラスタの全体を返すように直したときも、異体字セレクタが入らないようにするためである。

### 一つのクラスタに複数のグリフがある場合

今の `shapeText` は、クラスタの中のすべてのグリフに同じ文字列を渡す。
一つのクラスタに二つのグリフがあれば、二つとも同じ文字に対応し、抜き出すと字が重複する。
小さな原稿（`e` と結合文字の鋭アクセント U+0301 など）を組んで調べたかぎりでは、一つのクラスタに複数のグリフが出る例は見つからなかった。
fixture の全体は調べていない。
結合文字は別のクラスタとして組まれ、それぞれが自分の文字に対応していた。
それでも、合字だけを直すと、クラスタの文字列を何個のグリフに渡すかの規則が決まらないので、ここで合わせて決める。

### ToUnicode と ActualText

PDF から文字列を戻す仕組みには二つある。
ToUnicode の CMap はグリフ（文字のコード）ごとに一つの文字列を持ち、`bfchar` の行き先には複数の文字を書ける（PDF 1.7 の 9.10.3）。
ActualText は、内容のストリームのマーク付きの内容（`BDC` と `EMC`）で囲んだ範囲に、置き換える文字列を与える（PDF 1.7 の 14.9.4）。
ToUnicode はグリフに一つの対応しか持てないので、同じグリフが文脈によって別の文字列に当たる場合は表せない。
ActualText はそれを表せるが、golem-pdf には内容のストリームにマーク付きの内容を書く仕組みがまだない（[golem-pdf ADR 0006](../../golem-pdf/adr/0006-cid-system-info.md) も同じ理由で ActualText を使わないとした）。
合字のグリフは、Source Serif でも Noto Serif JP でも、ほかの文字列に当たることがない。
ToUnicode の行き先を複数の文字にすれば、合字はそれで足りる。
ToUnicode で表せないクラスタは、ActualText で表す。
そのために、golem-pdf に ActualText のためだけのマーク付きの内容を加える。

### メンテナーが決めたこと

- ToUnicode で表せないクラスタは ActualText で表してよい。golem-pdf には、そのためのマーク付きの内容を最小限だけ加える。
- `Golem.Font.toUnicode` を消し、ToUnicode を作る処理を golem-driver に移してよい。v1 の前のプレリリースなので、golem-font の公開の関数を減らしてよい。

## 実装すること

### クラスタの文字列（`Golem.Driver.Fonts`）

- `clusterText` は、クラスタの先頭のバイト位置から、同じランの次のクラスタの先頭のバイト位置（なければランの末尾）までの文字列を返す。次のクラスタの先頭は、そのランのグリフのクラスタの値のうち、`c` より大きい最小の値とする。横組みの欧文も縦組みも、HarfBuzz の既定のクラスタの単位（文字の順に単調に増える）で組むので、この定め方で範囲が決まる。
- 異体字セレクタを除く処理（[golem-pdf ADR 0006](../../golem-pdf/adr/0006-cid-system-info.md)）は、クラスタの全体の文字列に対して行う。
- 縦組みで横組みの字形に回す判定（`turnsInVertical`、[ADR 0015](0015-vertical-dashes.md)）は、今のとおりクラスタの最初の文字で行う。

### グリフとクラスタの関係（データ構造）

`Shaped` に、グリフがクラスタのどの部分かを表す欄を加える。

```haskell
-- | どのグリフがクラスタの文字列を ToUnicode に出すか（golem-driver ADR 0030）
data ClusterPart
  = -- | クラスタのただ一つのグリフ（一字のグリフと合字）
    ClusterWhole
  | -- | 複数のグリフのクラスタの、グリフの順で最初のグリフ
    ClusterLead
  | -- | 複数のグリフのクラスタの、二番め以降のグリフ
    ClusterRest
  deriving stock (Eq, Ord, Show)

data Shaped = Shaped
  { ...,
    shText :: !Text, -- クラスタの全体の文字列（異体字セレクタを除く）
    shPart :: !ClusterPart
  }
```

- `shText` は、クラスタのすべてのグリフで、クラスタの全体の文字列とする。preflight の図（[golem-cli ADR 0006](../../golem-cli/adr/0006-preflight.md)）のように、グリフの文字を見せる処理は今のとおり `shText` を読む。
- `GlyphUse` にも `guPart :: ClusterPart` を加え、`runAt` が `Shaped` から写す。圏点の記号のグリフ（`kentenMark`）は一字のクラスタなので `ClusterWhole` とする。

### ToUnicode の対応（`Golem.Driver.Fonts`）

ToUnicode の対応を作る処理を、純粋な関数として `Golem.Driver.Fonts` に置く。

```haskell
-- | 描いた順のグリフと文字列とクラスタの部分から、グリフごとの ToUnicode の文字列
toUnicodeOf :: [(Int, Text, ClusterPart)] -> [(Int, Text)]
```

- `ClusterRest` のグリフは候補にしない。複数のグリフのクラスタの文字列は、最初のグリフ（`ClusterLead`）だけが持つ。抜き出した文字列で字が重複しないようにするためである。
- 一つのグリフに複数の候補があるときは、`ClusterWhole` の候補を `ClusterLead` の候補より先に採る。同じ部分の候補のあいだでは、今のとおり文書の中で先に描いたものを採る（[golem-font ADR 0002](../../golem-font/adr/0002-subsetting-and-embedding.md)）。`e` と結合文字のように、ふだんは一字に当たるグリフが、ある箇所だけ複数のグリフのクラスタの最初になったとき、その文字列が文書のすべての `e` に移らないようにするためである。
- グリフ ID 0 と空の文字列を除くのは、今の `lfEmbed` と同じである。
- `Golem.Driver.Pdf` は、フォントごとに描いた `GlyphUse` をこの関数に渡し、結果を `lfEmbed` に渡す。`lfEmbed` の引数の形（`[(Int, Text)]`）は変えない。
- golem-pdf の `toUnicodeCMap` は変えない。行き先の文字列を UTF-16BE で書いているので、複数の文字（サロゲートペアを含む）の行き先をそのまま書ける。

### ActualText（`Golem.Driver.Pdf`）

ToUnicode で表せないクラスタを、ActualText で囲む。

- 描いたクラスタの出現ごとに、そのクラスタのグリフ（`ClusterWhole` の一つ、または `ClusterLead` とそれに続く `ClusterRest`）を、フォントの ToUnicode の対応（`toUnicodeOf` の結果）で文字列に戻してつなぐ。対応のないグリフは空の文字列とする。
- つないだ文字列がクラスタの文字列（`shText`）と異なる出現だけを、ActualText で囲む。置き換える文字列はクラスタの文字列とする。異体字セレクタは `shText` から既に除いてあるので、ActualText にも入らない（[golem-pdf ADR 0006](../../golem-pdf/adr/0006-cid-system-info.md) と同じ）。
- 判定は純粋な関数として `Golem.Driver.Fonts` に置く。

```haskell
-- | 描いた順のグリフと文字列とクラスタの部分を、クラスタの出現ごとに分け、
-- ActualText が要る出現にその文字列を付ける（golem-driver ADR 0030）
actualTextOf :: Map Int Text -> [(Int, Text, ClusterPart)] -> [([Int], Maybe Text)]
```

- 第一引数は、そのフォントの ToUnicode の対応である。結果は、クラスタの出現ごとのグリフ ID の並びと、ActualText が要れば置き換える文字列である。
- `Golem.Driver.Pdf` は、すべてのページの `GlyphUse` から ToUnicode の対応を先に決め、その対応でページのマークを作る。`GlyphUse` はマークに依らずに決まるので、この順で循環はない。
- グリフの並びのマーク（`GlyphRun`、`ScaledGlyphRun`、`RotatedGlyphRun`、`StyledGlyphRun`）に ActualText が要るクラスタがあれば、マークをその前、そのクラスタ、その後の三つに分け、そのクラスタのマークを `ActualText` で囲む。要るクラスタがないマークは分けない。報告された合字の本では囲む範囲が生じないので、今の PDF と内容のストリームのバイト列が変わらない。
- 圏点の記号のグリフは一字のクラスタとして同じ規則に従う。

### マーク付きの内容（golem-pdf）

`Golem.Pdf.Writer` の `Mark` に、ActualText のためのマーク付きの内容を一つだけ加える。

```haskell
data Mark
  = ...
  | -- | marks wrapped in a marked-content sequence with the replacement
    -- text (golem-driver ADR 0030)
    ActualText !Text ![Mark]
```

- `contentStream` は、`ActualText t ms` を `/Span << /ActualText s >> BDC`、改行、`ms` の内容、`EMC`、改行の順に書く。`s` は `pdfTextString t` を `serialize` した文字列である（印字できる ASCII だけなら文字列のリテラル、それ以外は BOM 付きの UTF-16BE の十六進の文字列）。
- タグの名前は `/Span` に固定し、`/ActualText` のほかのキーは書かない。プロパティの辞書はページの `/Properties` の資源に置かず、内容のストリームに直接書く。
- `ActualText` は入れ子にしない。golem-driver は一つのクラスタのマークだけを囲み、その中に `ActualText` を置かない。
- マーク付きの内容は、`BT` と `ET` の外側で囲む。囲まれたマークがそれぞれ自分の `BT` と `ET` を書くので、テキストのオブジェクトの境界をまたがない（PDF 1.7 の 14.6）。
- タグ付き PDF の構造（`StructTreeRoot`、`MCID`）は作らない。
- `Golem.Pdf` は `ActualText` を公開する。

### golem-font

- 使われていない `Golem.Font.toUnicode` を消し、`Golem.Font` の公開の一覧からも除く。ToUnicode を作る処理を一か所にするためである。そのテスト（合字が文字列の全体に当たること、先に現れた対応を採ること）は、`toUnicodeOf` のテストとして golem-driver に移す。

### ドキュメント

- 仕様書の「フォント」の節の、異体字セレクタと ToUnicode の段落の前に、次の内容を加える。ToUnicode は、グリフをそのグリフが組んだクラスタの文字列の全体に対応させ、合字（fi、ffi など）は複数の文字に戻る。一つのクラスタを複数のグリフで組んだ場合は、最初のグリフにクラスタの文字列を対応させる。同じグリフが複数の文字列に当たる場合は、一つのグリフだけのクラスタの対応を先に採り、そのうえで文書の中で先に現れた対応を採る。この ADR と [golem-font ADR 0002](../../golem-font/adr/0002-subsetting-and-embedding.md) へのリンクを付ける。
- 仕様書の同じ段落に、ToUnicode で表せないクラスタを ActualText で囲むことを加える。
- golem-pdf の仕様書の内容のストリームの節に、`ActualText` のマーク付きの内容を加える。
- [golem-pdf ADR 0006](../../golem-pdf/adr/0006-cid-system-info.md) のステータスの行に、ToUnicode で表せないクラスタに ActualText を使うことをこの ADR で加えたことを、この ADR へのリンクで書き足す。
- [golem-font ADR 0002](../../golem-font/adr/0002-subsetting-and-embedding.md) のステータスの行に、ToUnicode を作る処理を golem-driver に移したことを、この ADR へのリンクで書き足す。
- ロードマップから「合字のテキスト層」の項目を消す。
- 利用者のマニュアルの付録I（`manual/appendices/i-known-issues.gm`）から「PDF からコピーした文字の合字」の項目を消す。付録H（`manual/appendices/h-roadmap.gm`）に同じ項目があれば消す。
- 開発者のマニュアルの「決定性を守る」の章（`manual-dev/part2/12-determinism.gm`）は、画像に現れない誤りの例として、合字を一字めだけに対応させる ToUnicode の誤りを挙げている。直したあとも例として成り立つように、過去の誤りとして書き直す（「一字めだけに対応させていた」）。

## 実装しないこと

- タグ付き PDF。マーク付きの内容は ActualText のためだけに書き、構造の木と `MCID` は作らない。ロードマップの「タグ付き PDF と PDF/A」で扱う。
- ActualText で、ToUnicode で表せるクラスタまで囲むこと。内容のストリームが大きくなり、今の PDF のバイト列が変わるためである。
- 結合文字を基底の文字と一緒に一つのクラスタとして組むこと。今の組版は結合文字を別の箱に分けている。見た目と抜き出しの両方に関わるので、別の項目として扱う。
- 行末のハイフンの扱いの変更。分綴で入れたハイフンは、今のとおりハイフンの文字に戻る。
- HTML、EPUB、プレーンテキスト。これらは原稿の文字列を書くので、合字の問題は起きない。

## テスト設計

実装の前に書き、失敗することを確かめる。

### `toUnicodeOf`（`modules/golem-driver/test/PdfSpec.hs`）

- 一つのグリフのクラスタ `(7, "ffi", ClusterWhole)` から、`(7, "ffi")` が出る。
- `(3, "é", ClusterLead)` と `(4, "é", ClusterRest)` から、`(3, "é")` だけが出て、グリフ 4 の対応はない。
- 同じグリフ 3 について、先に `(3, "é", ClusterLead)`、後に `(3, "e", ClusterWhole)` が来ると、`(3, "e")` が出る。
- 同じ部分の候補が二つあると、先の候補が出る（`(5, "a", ClusterWhole)`、`(5, "b", ClusterWhole)` から `(5, "a")`）。
- グリフ ID 0 と空の文字列は出ない。

### `actualTextOf`（`modules/golem-driver/test/PdfSpec.hs`）

- 対応 `{3 ↦ "e"}` のもとで、`(3, "é", ClusterLead)`、`(4, "é", ClusterRest)` から `([3, 4], Just "é")` が出る。
- 対応 `{3 ↦ "é"}` のもとで、同じ入力から `([3, 4], Nothing)` が出る。
- 対応 `{7 ↦ "ffi"}` のもとで、`(7, "ffi", ClusterWhole)` から `([7], Nothing)` が出る。
- 対応 `{5 ↦ "a"}` のもとで、`(5, "b", ClusterWhole)` から `([5], Just "b")` が出る。
- 一字のクラスタと複数のグリフのクラスタが続く入力が、出現ごとに正しく分かれる。

### マーク付きの内容（`modules/golem-pdf/test/Main.hs`）

- `contentStream` が、`ActualText "ffi" [GlyphRun ...]` を `/Span << /ActualText (ffi) >> BDC` で始まり `EMC` で終わる形に書き、その間に `GlyphRun` の `BT` から `ET` までがある。
- `ActualText "é" [...]` の置き換える文字列が `<FEFF00E9>` になる。
- `ActualText` を含むページの PDF が、golem-pdf の PDF/X-4 の検査（[golem-pdf ADR 0003](../../golem-pdf/adr/0003-pdf-x-4-validator.md)）を通る。

### 実際のフォントの PDF（`modules/golem-driver/test/PdfSpec.hs`）

- The Tempest の fixture の Source Serif を本文の欧文のフォントにした横組みの本で `office fluffy affix final left-hand` を組む。内容のストリームの文字のコードを描いた順に ToUnicode で文字列に戻してつなぐと、原稿から空白を除いた `officefluffyaffixfinalleft-hand` に等しい。合字の有無と、どのグリフが合字になるかはフォントで決まるので、テストはグリフ ID に依らない形にする。
- 同じ PDF の ToUnicode の CMap に、行き先が 2 字以上の `bfchar` の行が少なくとも一つある。この本文で Source Serif が合字を作ることを確かめ、上のテストが合字のない組版で通ってしまわないようにする。
- 異体字セレクタの既存のテスト（`葛` と `U+E0100`、[golem-pdf ADR 0006](../../golem-pdf/adr/0006-cid-system-info.md)）がそのまま通る。
- 同じ PDF の内容のストリームに `BDC` がない。報告された合字は ToUnicode だけで戻ることを確かめる。
- 偽のフォントで、同じグリフが二つの文字列に当たる本（テストの `Shaped` を直接組む）を組むと、後に採らなかったほうの箇所だけが ActualText で囲まれ、ActualText を考慮して抜き出した文字列が原稿に等しい。
- 縦組みの二倍ダーシ（U+2014 の二字）の既存のテスト（`<02D2>` が `U+2014` に当たる、[ADR 0015](0015-vertical-dashes.md)）がそのまま通る。

### 自動テストにしない確かめ方

- fixture の英語の五冊と The Tempest を組み、PDFKit（Swift の使い捨てのスクリプト）か `pdftotext` で抜き出した文字列に、`frst`、`fnd`、`lef`、`afer` のような字の欠けがないことを確かめる。
- 同じ PDF を Acrobat Reader と macOS のプレビューで開き、合字を含む語を検索して見つかること、複写した文字列に字の欠けがないことを確かめる。
- ActualText を含む PDF を作れた場合は、Acrobat Reader で囲んだ範囲を複写し、置き換える文字列が出ることを確かめる。

## トレードオフ

ToUnicode を主にし、ActualText は ToUnicode で表せない出現だけに使った。
報告された合字はどれも ToUnicode の行き先を複数の文字にするだけで直り、内容のストリームは変わらない。
すべてのクラスタを ActualText で囲めば規則は一つで済むが、内容のストリームが大きくなり、ActualText を読まない抜き出しの道具では ToUnicode が頼りになることに変わりはない。

golem-pdf のマーク付きの内容を、ActualText のためだけの一つの形にした。
タグ付き PDF にはタグの名前、`MCID`、構造の木が要り、その設計をこの ADR で先に決めると、タグ付き PDF の ADR の選択肢を狭める。
タグ付き PDF を作るときに、この形を広げるか置き換えることになる。

ActualText の判定に、文書の全体の ToUnicode の対応が要る。
ページのマークを作る前に、すべてのページの描いたグリフを集めて対応を決める必要がある。
ページごとに独立してマークを作る今の形より、ページのあいだの依存が一つ増える。

複数のグリフのクラスタでは、文字列の全体を最初のグリフに渡し、残りのグリフには何も対応させない。
文字列をグリフに分けて配ると、どの文字をどのグリフに配るかを、フォントの字形の作りから推し量る必要がある。
最初のグリフにまとめれば、抜き出した文字列の順と中身はクラスタの単位で正しくなる。
代わりに、残りのグリフだけを選んで複写すると、文字が取れない。

候補の順を、一つのグリフのクラスタを先にする形にした。
文書の中で先に現れたものだけで決めると、本の最初のほうにある一つの特殊なクラスタが、同じグリフのすべての箇所の文字を変えてしまう。
一つのグリフのクラスタの対応は、フォントの文字の対応表（cmap）の逆に当たることが多く、どの箇所でも正しい可能性が高い。

`Golem.Font.toUnicode` を消して golem-driver に新しい関数を置いた。
golem-font の関数を直して使う形もあるが、golem-font の `ShapedGlyph` は描く位置も回転も持たず、PDF の経路が実際に描いたグリフの並び（縦組みで回した字形、圏点の記号を含む）とは一致しない。
ToUnicode の入力は描いたグリフから作るほうが、描いたものと抜き出すものが食い違わない。

## 参考文献

- ISO 32000-1:2008（PDF 1.7）, 9.10.3 ToUnicode CMaps.
- ISO 32000-1:2008（PDF 1.7）, 14.9.4 Replacement Text（ActualText）.
- HarfBuzz manual, Clusters. https://harfbuzz.github.io/clusters.html
