# ADR 0007: PDF に索引と参考文献を出力する

ステータス: 採択→索引の段組みは [docs/adr/0018](../../adr/0018-multi-column-layout.md)

## 文脈

索引と参考文献は、目次と同じくチャネルとして文書の各所から項目を集め、`@index` と `@bibliography` の位置に一覧を出す（[specifications.md](../../specifications.md) の「チャネル」の節）。
項目の集約は文書構造（S1）で済んでいる（[golem-doc ADR 0002](../../golem-doc/adr/0002-document-assembly.md)）。
索引は `Book` の `bookIndex` に、読みで並べた `IndexGroup`（語、読み、出現位置の `(FileId, SrcSpan)` の列）として入る。
参考文献は `bookCitations` に、最初に引用された順のキーと番号の組として入る。
書誌の本文は golem-driver の `loadBibliography` が CSL-JSON から組み込みの書式で整え、キーから書誌の文字列への表として HTML に渡している。

HTML と EPUB は、索引に出現位置へのリンクを出し、参考文献を番号付きの一覧にしている。
プレーンテキストは索引を出さず、参考文献を番号の一覧にする（[golem-text ADR 0001](../../golem-text/adr/0001-plain-text-output.md)）。

PDF の経路（[ADR 0002](0002-pdf-pipeline.md)）は、チャネルのうち目次だけを出力している。
`Golem.Driver.Pdf` の `unitsOf` は `ChannelOutput IndexOutput` と `ChannelOutput BibliographyOutput` を空のリストに写すので、`@index` と `@bibliography` を書いても PDF には何も出ない。
加えて、引用の印 `[cite key]` は golem-layout の `piecesOf` で `[key]` という文字列に組まれており、[golem-doc ADR 0002](../../golem-doc/adr/0002-document-assembly.md) の「引用の印はその番号を表示する」に反している。
HTML は `[1]` のように番号を出しているので、PDF だけが書誌のキーを本文に出している。

索引の PDF での形は仕様で決まっている。
PDF ではページ番号を出し、階層は二段までとし、三段以上と「〜を見よ」は v2 以降に回している。
ページ番号は、ページ番号への参照（DeferredRef）と同じく、表記の決まっていない数（Number）として扱い、レイアウトを繰り返して収束させる（[golem-layout ADR 0003](../../golem-layout/adr/0003-pagination-and-s2.md)）。

ページ番号への参照は、ラベルからページを引く仕組みで解決している。
`Golem.Layout.Paginate` の `LineBox` がラベルを持ち、`labelPages` がラベルからページ番号への表を作り、ドライバーの `fixpoint` がその表が変わらなくなるまで組み直す。
索引の印はラベルを持たないので、この仕組みのままでは印のページを引けない。
golem-layout の `composeInlines` は印の位置を `AnchorIndex` として返すが、印の `SrcSpan` を落としているので、どの出現位置の印かも区別できない。

## 実装すること

### 索引の印のページを求める

印の位置を、ラベルと並ぶ第二の参照先として改ページまで運ぶ。

- golem-layout の `Golem.Layout.Japanese` の `Anchor` の `AnchorIndex` に印の `SrcSpan` を足し、`AnchorIndex !Int !SrcSpan IndexEntry` にする。`piecesOf` の `IndexMark sp e` から `sp` を渡す。
- `Golem.Layout.Paginate` の `LineBox` に `lbMarks :: ![SrcSpan]` を、`FFigure` に `ffMarks :: ![SrcSpan]` を、`PageOut` に `poMarks :: ![SrcSpan]` を足す。行や図版を置いたときに、ラベルと同じ経路で `poMarks` に積む。
- `Golem.Layout.Paginate` に `markPages :: [PageOut] -> Map SrcSpan Integer` を足す。`labelPages` と同じく、印からその印を置いたページの番号への表を作る。
- 印のキーは `SrcSpan` とし、ラベルの名前空間とは混ぜない。ラベルの名前には空白と一部の括弧を除くほとんどの文字を使えるので、印の位置を文字列にしてラベルの表に入れると、利用者のラベルと衝突しうるためである。

ドライバーでは、印をどの行に付けるかを次のように決める。

- 段落、見出し、定義リストの用語の中の印は、印を含む行の `LineBox` に付ける。行の求め方は、注の印と同じ `lineIndexOfItems` を使う。
- 注の本文の中の印は、その注の印を含む本文の行に付ける。注の本文はその行と同じページに置かれるので（[golem-layout ADR 0003](../../golem-layout/adr/0003-pagination-and-s2.md)）、ページは一致する。ページをまたいで続く注の後半にある印も、注の印のページを指す。
- 図版のキャプションの中の印は、その図版の `FFigure` の `ffMarks` に付ける。PDF の経路はキャプションを組んでいないが、図版の置かれるページは決まるので、そのページを指す。

### S2 の繰り返し

`Golem.Driver.Pdf` の `fixpoint` が比べる仮の値を、ラベルのページと印のページの組にする。

```haskell
data Assumed = Assumed
  { asLabels :: !(Map Text Integer),
    asMarks :: !(Map SrcSpan Integer)
  }
```

- `buildFlow` と `composeEnv` は `Map Text Integer` の代わりに `Assumed` を受け取る。
- 一回組むごとに `labelPages` と `markPages` を求め、両方が仮の値と一致したら終える。
- 上限の回数（`maxIterations`、5 回）までに収束しなければ、今の G0721 のエラーとする。メッセージには、収束しなかったラベルに加えて、ページの変わり続けた印の語（`igTerms` を ` / ` でつないだもの）を並べる。
- 仮の値がまだない印のページは 1 として組む。ページ番号への参照と同じく、1 桁の仮の値から始める（[golem-layout ADR 0003](../../golem-layout/adr/0003-pagination-and-s2.md)）。

### 索引の組版

`unitsOf` は `ChannelOutput IndexOutput` を、索引の行の段落の列に写す。
行を作る処理は純粋な関数として `Golem.Driver.Pdf` から公開し、単体でテストできるようにする。

```haskell
indexLines :: Bool -> (SrcSpan -> Maybe Integer) -> [IndexGroup] -> [[Inline]]
```

第一引数は縦組みかどうか、第二引数は印のページを引く関数である。
各要素が一つの段落になり、段落としてシェイピングと行分割をする。

- 一段の項目（`igTerms` が一つ）は、語、全角の空白、ページ番号の列を一行にする。
- 二段の項目は、主項目の行の直後に、全角の空白一つで字下げした副項目の行として出す。副項目の行は、副項目の語、全角の空白、ページ番号の列から成る。
- 同じ主項目を持つ副項目が続く場合は、主項目の行を一度だけ出す。主項目の同一性は、語と読みの両方の一致で判定する。
- 副項目だけがあり、主項目そのものの印がない場合は、ページ番号のない主項目の行を出す。
- `bookIndex` の並びは S1 で決まっている（[golem-doc ADR 0002](../../golem-doc/adr/0002-document-assembly.md) の並べ替えの規則）。読みの列で並べているので、主項目の直後にその副項目が来る。`indexLines` は並べ替えをしない。
- ページ番号は昇順に並べ、同じページの印が複数あっても一度だけ出す。
- ページ番号は `Number` の inline として出す。縦組みでは `[numbers]` の `vertical` の既定の表記になり、横組みでは算用数字になる。ページ番号も数なので、ほかの数と同じ経路で表記を決める（specifications.md の「目次と文書構造の参照」の節）。
- ページ番号の区切りは、横組みでは `, `、縦組みでは `、` とする。
- ページを引けない出現位置は出さない。正しく組めていれば起こらないので、テストで起こらないことを確かめる。
- 索引の項目が一つもない場合は、何も出さない。

### 参考文献の組版

`PdfInput` に `piBibliography :: !(Map Text Text)` を足し、`writeTargets` が HTML のために読んでいる `loadBibliography` の結果をそのまま渡す。

```haskell
bibliographyLines :: Map Text Text -> [(Text, Int)] -> [[Inline]]
```

- `bookCitations` の順に、`[n] ` と書誌の文字列を続けた段落を一つずつ作る。プレーンテキストの `[n] ` の形と合わせる。
- 書誌の表にキーがない場合は、HTML と同じくキーを出す。存在しないキーの引用は評価の段階でエラーになる（[golem-eval ADR 0002](../../golem-eval/adr/0002-file-evaluation.md)）ので、通常は起こらない。
- 引用された文献が一つもない場合は、何も出さない。

### 引用の印

- golem-layout の `ComposeEnv` に `ceCiteNumber :: Text -> Maybe Int` を足す。`defaultComposeEnv` では `const Nothing` とする。
- `piecesOf` の `Cite _ k` は、番号が引ける場合は `[n]` を、引けない場合は今と同じ `[k]` を組む。
- ドライバーの `composeEnv` は `bookCitations` から作った表を `ceCiteNumber` に渡す。

### ドキュメント

- specifications.md の「v1 の実装で次の段階以降に回した項目」から「索引と参考文献」を除く。
- specifications.md の「索引」の節に、PDF での索引の形（副項目の字下げ、ページ番号の区切りと重複の除去、印のページの決め方）を書き加える。

## 実装しないこと

- 索引の三段以上の階層と「〜を見よ」。仕様のとおり v2 以降とする。
- 索引の見出し（「あ」「か」のような行の区切り）と、索引の段組み。段組みはフレームのレベル 2 に当たり、v1 では扱わない。
- ページ番号の範囲の圧縮（「12, 13, 14」を「12-14」にすること）。
- 縦組みの本の索引を横組みにして巻末から始めること。一冊の中で組み方向を切り替える仕組みがまだないので、索引も本文と同じ方向に組む。
- 副項目の行が二行以上に折り返したときの、二行目以降の字下げ。行頭の字下げは段落の先頭の全角の空白で表すので、折り返した行は字下げされない。
- 参考文献の書式の選択と、書誌の一覧のぶら下げ字下げ。
- 目次へのページ番号の追加。今の PDF の目次は番号と題だけを出しているが、目次の形は別の ADR で扱う。
- HTML、EPUB、プレーンテキストの索引と参考文献の変更。

## テスト設計

### golem-layout

- `composeInlines` に `[Text "前", IndexMark sp e, Text "後"]` を渡すと、`AnchorIndex 1 sp e` が返り、`sp` が印の位置と一致すること。
- 3 行の段落を 3 ページに分ける `paginate` で、2 行目の `LineBox` に印 `m` を付けたとき、`markPages` が `m` を 2 ページ目に写すこと。
- 送られた図版（`FFigure`）の `ffMarks` の印が、図版を実際に置いたページを指すこと。[golem-layout ADR 0003](../../golem-layout/adr/0003-pagination-and-s2.md) の「図版が次のページに送られる」テストの構成に印を足して確かめる。
- `ceCiteNumber` が `knuth1981` を 1 に写すとき、`Cite _ "knuth1981"` が `[1]` の箱として組まれ、`knuth1981` の文字が箱に現れないこと。`const Nothing` のときは `[knuth1981]` のままであること。

### golem-driver の単体のテスト

`indexLines` に次の入力を与え、出力の inline を `inlineText` と `Number` の値で比べる。

- `組版`（くみはん、位置 a と b）、`組版 / 和文組版`（くみはん / わぶんくみはん、位置 c）、`和文`（わぶん、位置 d）。ページは a と b が 3、c が 10、d が 12。
  横組みでは `組版　3`、`　和文組版　10`、`和文　12` の三行になる。同じページの a と b が一度だけ出ることも、この例で確かめる。
- 副項目 `組版 / 和文組版` だけがある場合に、ページ番号のない `組版` の行が先に出ること。
- 同じ主項目の副項目が二つ続く場合に、主項目の行が一度だけ出ること。
- ページ 3 と 12 を持つ項目が、縦組みでは `、` で区切られ、ページ番号が `Text` ではなく `Number` の inline であること。

`bibliographyLines` に `[("knuth1981", 1), ("missing", 2)]` と `knuth1981` だけを持つ書誌の表を与え、`[1] ` に書誌の表の `knuth1981` の文字列を続けた行と、`[2] missing` の行の二行になることを確かめる。

### golem-driver の PDF のテスト

PDF の行の文字列を確かめるため、`Golem.Driver.Pdf` から、組み終えたページごとの行の文字列（箱の `bcText` をつないだもの）を返す `layoutPages :: FontProvider -> PdfInput -> IO (Either [Diagnostic] [[Text]])` を公開する。
`renderPdf` と同じ段階を、PDF を書く手前まで実行する関数である。
テストには既存の `fakeFonts` を使う。

- 行数の少ない版面（`lines = 5`）で、第 1 章の 1 ページ目、第 2 章の 3 ページ目に索引の印を置き、末尾の `@index` の行が、それぞれの語と正しいページ番号を含むこと。
- 索引の印の前に段落を足して印のページが 9 から 10 に繰り上がる原稿で、繰り返しが収束し、索引に `10` が出ること。
- `[cite knuth1981]` を含む原稿の行に `[1]` が現れ、`knuth1981` が現れないこと。`@bibliography` の行が `[1] ` で始まり、書誌の文字列を含むこと。
- `bookIndex` のすべての出現位置が `markPages` の表に現れること（ページを引けない出現位置がないこと）。
- 索引と参考文献を含む原稿で、並列と逐次で PDF のバイト列が一致し、二回のビルドでも一致すること（[docs/adr/0002](../../adr/0002-determinism.md)）。qpdf の検査も通ること。

既存の HTML とプレーンテキストの golden テストが変わらないことも確かめる。

## トレードオフ

印のページの表を S2 の繰り返しに加えるので、索引の印が多い本では繰り返しの一回ごとの比較が重くなる。
表は `Data.Map` であり、比較は印の数に比例するので、組版の本体に比べれば小さい。

索引をページ番号の繰り返しに含めると、索引のページ番号の桁が変わって索引の行の折り返しが変わり、索引より後のページが動くことがある。
索引は普通は巻末にあり、その後ろに印はないので、繰り返しは増えないと見込む。
これは推測であり、収束しない構成は G0721 で止まる。

注の本文の中の印を、注の印のページに結び付ける。
ページをまたいで続く注の後半にある印は、実際にはその次のページに組まれるので、一ページずれる。
注の本文の行ごとの位置を印まで運ぶより単純であり、複数段落の注を持たない v1 では長い注は少ないので、このずれを受け入れる。

索引のページ番号を `Number` で出すので、縦組みの索引のページ番号は本文の数と同じ表記（既定では漢数字）になる。
縦組みの本でも索引のページ番号を算用数字で出す慣習はあるが、表記の使い分けを数の経路に一本化する仕様を優先する。
