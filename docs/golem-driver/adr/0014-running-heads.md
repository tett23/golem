# ADR 0014: 柱の内容

ステータス: 採択

## 文脈

柱はマスターページで位置と内容を決める（[仕様書](../../specifications.md) の「style.toml」の節）。
`style.toml` には、柱に関わる欄が二つある。

```toml
[headings.1]
running-head = true

[masters.body]
running-head = { position = "top-outside", content = "heading.1.short" }
folio = { position = "bottom-outside", format = "{n}" }
```

マニフェストの章の項目は、そのファイルに使うマスターページを `master` で指定できる（[仕様書](../../specifications.md) の「プロジェクトの構成と import」の節）。

現状をコードで確かめると、次のとおりである。

- `Golem.Project.Style` は、見出しの `running-head` を `hsRunningHead` に、マスターページの `running-head` を `mdRunningHead :: Maybe (Text, Text)`（位置と内容）に読み込む。内容の文字列は検査していない。
- `Golem.LayoutSpec.masterGeometry` は、内容の文字列を `mgRunningHead` に入れて運ぶだけである。
- `Golem.Layout.Paginate.paginate` は、1 の階層の見出しの題を `fhShort` として受け取り、そのページで最初に置いた 1 の階層の見出し、なければそれまでに置いた最後の 1 の階層の見出しを `poRunningHead` にする。
- `Golem.Driver.Pdf.unitsOf` が `fhShort` に渡すのは、本文の見出しの題（`inlineText` でつないだもの）である。`@toc-title` の短い題は使っていない。
- `writeDocument` は、`pgMasters` の最初のマスターページ（名前の順で最初のもの）をすべてのページに使う。章ごとの `master` の指定は読んでいない。
- 白ページには柱もノンブルも描かない。白ページでないページには、`poRunningHead` があれば、マスターページの柱の位置に描く。章の始まりのページにも描く。
- `hsRunningHead` と、柱の内容の文字列は、どこからも使われていない。

[golem-driver ADR 0003](0003-pdf-heading-styles.md) は、見出しの `running-head` とマスターページの `content` の解釈を「実装しないこと」に挙げた。
[golem-layout ADR 0003](../../golem-layout/adr/0003-pagination-and-s2.md) は「マスターページの柱の内容（そのページで有効な章の短い題など）」を埋めるとしたが、内容の指定の形は決めていない。

InDesign は、柱を段落スタイルの柱の変数（Running Header）で作る。
変数ごとに、拾う段落スタイルと、ページの中のどれを使うか（「ページの最初」か「ページの最後」）を選ぶ。
ページにその段落スタイルの段落がない場合は、前のページまでの最後の段落を使う。
この最後の動きは Adobe の公式の資料では確かめられず（Adobe のヘルプは HTTP 403 で読めなかった）、Adobe のコミュニティの回答（https://community.adobe.com/t5/indesign/running-headers-won-t-pick-up-paragraph-from-previous-page/m-p/10115796 ）で確かめた。
辞書の柱のように、左右のページで「最初」と「最後」を使い分ける組み方も、同じ変数を二つ置いて作る（https://design.tutsplus.com/tutorials/quick-tip-mastering-running-titles-in-indesign--vector-2649 ）。
左右のページで柱の内容を変えるには、InDesign では見開きのマスターページの左右に別の変数を置く。
章の始まりのページの柱を消すには、そのページに柱のないマスターページを当てる（記憶による）。

## 実装すること

### style.toml の欄（golem-project）

マスターページの `running-head` を次の形にする。

```toml
[masters.body]
# 両方のページに同じ内容
running-head = { position = "top-outside", content = "heading.1.short" }

[masters.book]
# 偶数ページに書名、奇数ページに章の番号と短い題
running-head = { position = "top-outside", even = "title", odd = "heading.1.numbered" }

[masters.dictionary]
# 偶数ページにページの最初の項目、奇数ページに最後の項目
running-head = { position = "top-outside", even = "heading.2.short", odd = "heading.2.short.last" }
```

- `position` は必須で、値は今と同じである。
- 内容は `content` で両方のページに一つを書くか、`even` と `odd` の両方を書く。`content` と `even` または `odd` を一緒に書いた場合、`even` と `odd` の片方だけを書いた場合、どれも書かない場合は G0314 とする。
- 偶数と奇数は、ノンブルと同じくページの通し番号で決める。

内容の値は次のどれかとする。

| 値 | 柱に出すもの |
|---|---|
| `heading.<l>.short` | 階層 l の見出しの短い題（`@toc-title`、なければ見出しの題） |
| `heading.<l>.numbered` | 階層 l の見出しの番号の表記、全角の空白、短い題。番号のない見出しは短い題だけ |
| `heading.<l>.short.last`、`heading.<l>.numbered.last` | 上と同じ。ページの中の見出しの選び方を「最後」にする |
| `title` | マニフェストの `metadata` の `title`（書名） |
| `none` | 何も出さない |

l は 1 以上の整数とする。
`.last` を付けない値は、選び方を「最初」にする。
これまでの書き方 `content = "heading.1.short"` は、そのまま同じ意味で読める。

```haskell
data HeadForm = HeadShort | HeadNumbered
data HeadPick = PickFirst | PickLast

data RunningContent
  = RunningHeading !Int !HeadForm !HeadPick
  | RunningTitle
  | RunningNone

data RunningHeadDef = RunningHeadDef
  { rhPosition :: !Text,
    rhOdd :: !RunningContent,
    rhEven :: !RunningContent
  }

data MasterDef = MasterDef
  { mdRunningHead :: !(Maybe RunningHeadDef),
    mdFolio :: !(Maybe (Text, Text)) -- 変えない
  }
```

`content` を書いた場合は、`rhOdd` と `rhEven` に同じ値を入れる。

| 診断コード | 重大度 | メッセージ |
|---|---|---|
| G0314 | エラー | `柱の内容が正しくありません: <値>。heading.<階層>.short か heading.<階層>.numbered（末尾に .last を付けられます）、title、none のどれかを、content に一つ、または even と odd の両方に書いてください` |

G0314 は未使用である（golem-project は G0301 から G0313 までを使っている）。
未知のキーをエラーにするのと同じく、綴りの誤りが柱の欠落としてしか現れないことを防ぐ。

### 見出しの `running-head` の廃止

`[headings.<l>]` の `running-head` を廃止し、`hsRunningHead` を削る。
柱に使う見出しの階層は、マスターページの内容の値の l が決めるので、見出しの側の欄は同じことを二か所に書かせるだけになるためである。
`running-head` を書いた `[headings.<l>]` は G0319（廃止した欄）とし、メッセージで「柱に使う見出しは [masters.<名前>] の running-head の content で指定してください」と示す。
廃止した `[verse]` などと同じく読み込みで止める（[docs/adr/0006](../../adr/0006-paragraph-indent.md)）。

| 診断コード | 重大度 | メッセージ |
|---|---|---|
| G0319 | エラー | `[headings.<l>] の running-head は廃止しました。柱に使う見出しは [masters.<名前>] の running-head の content で指定してください` |

G0319 は未使用である。`style.toml` の一般の誤りの G0306 から、廃止した欄の誤りを分けて、どの欄の誤りかをコードで引けるようにする（提案中の ADR のあいだで、G0317 から G0322 を分けて割り当てた）。


### ページのマスターページ

各ページに、そのページの内容が属する章のファイルのマスターページを使う。

- ページのファイルは、そのページの最初の行（`SLine` か `SHeading` の最初のスロット）を組んだ単位のファイルとする。段組みの版面（[docs/adr/0018](../../adr/0018-multi-column-layout.md)）では、段の順にたどって最初の行をとる。
- 行を一つも置かないページ（続きの脚注だけのページ、図版だけのページ）は、前のページのファイルを使う。最初のページに行がない場合は、マニフェストの最初の章のファイルとする。
- ファイルのマスターページは、マニフェストの章の項目の `master` とする。`master` のないファイルは、`body` という名前のマスターページがあればそれを、なければ名前の順で最初のマスターページを使う。マスターページが一つもなければ、柱もノンブルも描かない。
- 白ページは、今と同じく柱もノンブルも描かない。

章ごとのマスターページの対応は、golem-driver の `PdfInput` に `piMasters :: !(Map FileId Text)` として渡す。
`Golem.Driver` が `projectChapters` から作る。
行の id からファイルへの対応は、`Built` に `bLineFiles :: Map Int FileId`（各単位の最初の行の id から、その単位の `uSpan` のファイルへ）として持ち、`Map.lookupLE` で引く。

### ページの中の見出しの選び方

柱の値は、S2 の繰り返しが収束した後に、最終回のページから一度だけ決める。
柱の文字列は行の格子の外に描き、改ページに影響しないので、繰り返しの各回で決める必要はない。

`paginate` は柱を決めない。
`PageOut` の `poRunningHead` と、`FHeading` の `fhShort` を削り、`St` の `sHead` と `sPageHead` も削る。
見出しの位置は、今の `poSlots` の `SHeading` から分かる。

golem-driver に次の純粋な関数を置く。

```haskell
-- | ページの中で始まった見出しを、置いた順に。段組みでは段の順につなぐ
headingsOnPages :: (Int -> Maybe HeadingInfo) -> [PageOut] -> Map Int [HeadingInfo]

runningHeadText
  :: Text                      -- 書名
  -> RunningContent
  -> Map Int (Maybe HeadingInfo) -- ページの始まりの時点の、階層ごとの有効な見出し
  -> [HeadingInfo]               -- そのページで始まった見出し
  -> Maybe Text
```

`Int -> Maybe HeadingInfo` は、見出しのブロックの最初の行の id から、`bHeadingSpans` と `bookHeadings` を通して `HeadingInfo` を引く関数である。

階層 l の有効な見出しを、見出しを文書の順にたどって次のように更新する。

- 階層 l の見出しが現れたら、それが階層 l の有効な見出しになる。
- l より上の階層（番号の小さい階層）の見出しが現れたら、階層 l の有効な見出しはなくなる。章が変わった後に、前の章の最後の節の題を柱に出さないためである。

`RunningHeading l form pick` の値は次のとおりとする。

- `PickFirst`：そのページで始まった階層 l の見出しがあれば、その最初のもの。なければ、ページの始まりの時点の階層 l の有効な見出し。
- `PickLast`：そのページで始まった階層 l の見出しがあれば、その最後のもの。なければ、ページの終わりの時点の階層 l の有効な見出し。ページの途中で上の階層の見出しが始まれば、なくなる。
- 有効な見出しがなければ、柱を描かない（前付けの、最初の章より前のページなど）。

`form` が `HeadShort` なら `hiTitle` を、`HeadNumbered` なら `hiNumberText` と全角の空白と `hiTitle` をつないだ文字列を出す。
`hiTitle` は `@toc-title` があればその題、なければ見出しの題であり（[golem-doc ADR 0002](../../golem-doc/adr/0002-document-assembly.md)）、`Golem.Doc.Assemble.inlineText` で文字列にする。
`RunningTitle` は書名を、`RunningNone` は何も出さない。

上の階層の見出しで有効な見出しをなくす規則は、InDesign の柱の変数にはない（記憶による）。
InDesign では、拾う段落スタイルの段落が前の章の中にしかなければ、その段落を次の章の柱にも出す。

### 柱を描かないページ

次のページには柱を描かない。
ノンブルは、白ページを除いて今と同じく描く。

- 白ページ。
- `page-break = "recto"` の見出しを置いたページ。章の始まりのページ（章扉を含む）に柱を出さない、和文と欧文の書籍の慣習に合わせる。`recto` の見出しは常にページの先頭に置かれるので、このページはその章の最初のページである。
- 内容の値が `none` のページと、上の規則で値がないページ。
- マスターページが `running-head` を持たないページ。

前付けの目次のページなどで柱を消したい場合は、`running-head` のないマスターページを章の項目の `master` に指定する。

### 描き方

- 柱は、今と同じく本文の役割と版面の文字の大きさで、マスターページの位置に横書きで描く（`textAt`）。縦組みの本でも横書きのままである。
- 奇数ページは `rhOdd`、偶数ページは `rhEven` の値を描く。位置は今の `mgRunningHead` の奇数ページと偶数ページのアンカーを使う。
- `MasterGeometry` の `mgRunningHead` は、内容の文字列の代わりに `RunningHeadDef` の内容を運ぶ `Maybe (RunningContent, RunningContent, Anchor, Anchor)` にする。

テストのために、ページの番号から描く柱の文字列への表を返す関数を `Golem.Driver.Pdf` から公開する。

```haskell
runningHeads :: PdfInput -> PageGeometry -> PdfLayout -> Map Int (Maybe Text)
```

### 決定性

柱の値は、収束した最終回の `PageOut` の列と、S1 の `bookHeadings` と、`style.toml` だけから決まる純粋な関数で求める。
見出しをたどる順は `poSlots` の順と段の順で決まる。

### ドキュメント

- 仕様書の「v1 の実装で次の段階以降に回した項目」から「柱の内容」を削る。
- 仕様書の「style.toml」の例の `[headings.1]` から `running-head = true` を削り、`[masters.body]` の例はそのまま残す。`even` と `odd` の例、内容の値の表、柱を描かないページ、章ごとのマスターページの選び方を書き、この ADR へリンクする。
- 仕様書の「目次と文書構造の参照」の節の「短い題」の項目に、柱には `heading.<l>.short` と `heading.<l>.numbered` で短い題が出ることを書く。
- docs/glossary.md の「柱」と「マスターページ」の項目に、柱の内容を `running-head` の `content`（または `even` と `odd`）で決めることを書く。
- [golem-project ADR 0002](../../golem-project/adr/0002-style-toml.md) のステータスの行の末尾に「、見出しの `running-head` の廃止とマスターページの柱の内容は [golem-driver ADR 0014](../../golem-driver/adr/0014-running-heads.md)」を足す。
- [golem-layout ADR 0003](../../golem-layout/adr/0003-pagination-and-s2.md) のステータスの行を変える。[docs/adr/0018](../../adr/0018-multi-column-layout.md) が先に変えていなければ `ステータス: 採択→柱の内容の決め方は [golem-driver ADR 0014](../../golem-driver/adr/0014-running-heads.md)` とし、変えていれば、その行の末尾に「、柱の内容の決め方は [golem-driver ADR 0014](../../golem-driver/adr/0014-running-heads.md)」を足す。

## データ構造の変更

- golem-project：`MasterDef` の `mdRunningHead` を `Maybe RunningHeadDef` にする。`RunningHeadDef`、`RunningContent`、`HeadForm`、`HeadPick` を加える。`HeadingStyle` の `hsRunningHead` を削る。
- golem-layout-spec：`MasterGeometry` の `mgRunningHead` の型を変える。
- golem-layout：`FHeading` の `fhShort`、`PageOut` の `poRunningHead`、`St` の `sHead` と `sPageHead` を削る。
- golem-driver：`PdfInput` に `piMasters` を、`Built` に `bLineFiles` を加える。`headingsOnPages`、`runningHeadText`、`runningHeads` を加える。

意味論 IR は変えない。

## 実装しないこと

- 柱の文字列を見出しの書体で組むこと、柱の色、縦組みの本で柱を縦書きにすること。仕様書の「ページ番号と柱の拡張」に含める。
- 段落スタイルや文字スタイルの付いた本文の文字列を柱に拾うこと（InDesign の文字スタイルの柱の変数）。柱に出せるのは見出しと書名だけとする。
- 柱の値の前後に文字を足すこと、末尾の句読点を消すこと、大文字と小文字の変換（InDesign の柱の変数の設定）。
- 内容に任意の文字列や、複数の値の組み合わせ（「書名　章題」など）を書く書式。
- 章の始まりのページで柱を出すかどうかの設定。常に出さない。
- ページごとにマスターページを指定すること。マスターページは章のファイルの単位で決める。
- ノンブルの書式と、ノンブルを描かないページの設定。ノンブルは今と同じく白ページだけで描かない。
- HTML、EPUB、プレーンテキストでの柱。ページを持たない媒体なので出さない。

## テスト設計

先に書き、失敗させてから実装する。

### golem-project（`modules/golem-project/test/Main.hs`）

- `content = "heading.1.short"` が、`rhOdd` と `rhEven` がともに `RunningHeading 1 HeadShort PickFirst` の `RunningHeadDef` として読めること。
- `even = "title"`、`odd = "heading.2.numbered.last"` が、`RunningTitle` と `RunningHeading 2 HeadNumbered PickLast` として読めること。`none` が `RunningNone` として読めること。
- `content = "heading.0.short"`、`content = "heading.1.long"`、`content = "chapter"` が G0314 になること。
- `content` と `odd` を両方書いた場合、`even` だけを書いた場合、どれも書かない場合が G0314 になること。
- `[headings.1] running-head = true` が G0319 になり、メッセージに `[masters.` が含まれること。今の `running-head = true` を含むテストの入力から、その行を削る。

### golem-layout（`modules/golem-layout/test/Main.hs`）

- `paginate` の結果に `poRunningHead` がなくなるので、今の「recto の見出しが白ページの後の奇数ページから始まる」テストの柱の検査を削り、golem-driver の `runningHeads` のテストに移す。

### golem-driver の単体のテスト（`modules/golem-driver/test/Main.hs`）

`runningHeadText` に、見出しの列を与えて確かめる。
見出しは、1 の階層の「第一章 海」（短い題「海」）、2 の階層の「一 朝」と「二 昼」、1 の階層の「第二章 山」とする。

- 「海」と「一 朝」が始まったページで、`heading.1.short` が「海」、`heading.2.short` が「朝」、`heading.2.short.last` が「朝」になること。
- 「二 昼」だけが始まったページで、`heading.2.short` が「昼」、`heading.1.short` が前のページから続く「海」になること。
- 見出しの始まらないページで、`heading.2.short` と `heading.2.short.last` が前のページの最後の「昼」になること。
- 「第二章 山」だけが始まったページで、`heading.2.short` が「昼」（ページの始まりの時点の値）、`heading.2.short.last` が値なしになること。次のページで `heading.2.short` も値なしになること。
- `heading.1.numbered` が「第一章　海」になり、`@nonumber` の見出しでは短い題だけになること。
- `@toc-title` を付けた見出しで、柱が短い題になり、本文の見出しの題にならないこと。
- 最初の 1 の階層の見出しより前のページで、`heading.1.short` が値なしになること。

### golem-driver の PDF のテスト

`runningHeads` の表で確かめる。
スタイルは既存の `horizontalStyle` に `[headings.1] page-break = "recto"` と、行数の少ない版面を使う。
フォントは `fakeFonts` を使う。

- `even = "title"`、`odd = "heading.1.short"` で、偶数ページが書名、奇数ページが章の短い題になること。
- `page-break = "recto"` の見出しを置いたページが `Nothing` になり、そのページのノンブルは描かれること（内容のストリームにノンブルの文字のグリフがあること）。
- 白ページが `Nothing` になり、ノンブルも描かれないこと。
- マニフェストの章の項目で、前付けのファイルに `running-head` のない `master = "front"` を、本文のファイルに `master = "body"` を指定すると、前付けのページが `Nothing`、本文のページに柱があること。`master` のない章が `body` を使うこと。
- 二段組みの版面（[docs/adr/0018](../../adr/0018-multi-column-layout.md) が実装されている場合）で、二段目でだけ 2 の階層の見出しが始まるページの `heading.2.short` が、その見出しの短い題になること。
- 柱の内容だけが違う二つの `style.toml` で、`plPages` が一致すること。柱が改ページに影響しないことの確認である。
- 柱を含む原稿を並列と逐次で組み、PDF のバイト列が一致すること。二回のビルドでも一致すること。
- `scripts/determinism.sh` の sample と、`kanikosen` と `tempest` の各ターゲットの出力が変わらないこと。どれも柱を持たないマスターページなので、変わらないことが期待値である。

### 自動テストにしない確かめ方

実装の後に、`golem new` の和文の雛形に `[headings.1] page-break = "recto"`、前付けの目次のファイル、`even = "title"`、`odd = "heading.1.numbered"` のマスターページを加えて PDF にし、ビューアーで、章の始まりのページと白ページと目次のページに柱がなく、ほかのページで左右の柱が入れ替わることを目で確かめる。

## トレードオフ

見出しの `running-head` を廃止するので、それを書いた `style.toml` はエラーになる。
今は読まれるだけで効いていない欄であり、残すと、柱に出る見出しを決める欄が二つになり、食い違ったときの意味を決める必要が生じる。

上の階層の見出しで下の階層の有効な見出しをなくす規則は、InDesign の動きと異なる。
InDesign の動きに合わせると、章の最初の節より前のページに、前の章の最後の節の題が出る。
これは InDesign でも利用者がマスターページを当て分けて避けている形であり、Golem にはページごとにマスターページを当てる手段がないので、規則で防ぐ。

章の始まりのページの柱を常に消すので、章の始まりのページに柱を出したい本は作れない。
和文と欧文の書籍の多くは章の始まりのページに柱を出さないので、設定を増やさずにこの形に固定する。
要望が出たら、マスターページの `running-head` にキーを足す ADR を作る。

内容の値を固定の語彙にするので、書名と章題を一つの柱に並べるような書式は書けない。
書式の文字列にすると、ノンブルの書式と別の差し込みの言語が増える。
v1 は、InDesign の柱の変数の基本の使い方（見出しを拾う、最初か最後を選ぶ、左右で変える）に絞る。
