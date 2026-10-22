# ADR 0002: ナビゲーション文書の深さと `@toc`

ステータス: 採択

## 文脈

[golem-epub ADR 0001](0001-epub-packaging.md) は、EPUB のナビゲーション文書を目次のチャネルから作り、`@toc` の有無にかかわらず必ず出力すると定めた。
`@toc` がない場合は、`@notoc` のない見出しをすべて載せる。
`@toc` がある場合に、その `depth` に従うかどうかは定めていない。

今の実装（golem-epub の `Golem.Epub.navDocument`）は、`Book` の `bookToc` をすべて載せ、`bookTocDepth` を見ない。
次の三つのファイルからなるプロジェクトで確かめた（main の a2b6106e）。

- `chapters/00.gm`：`# 目次` と `@toc depth=1`
- `chapters/01.gm`：`# 第一章`、`## 節一`、`### 項一`
- `chapters/99.gm`：`# 参考文献` と `@bibliography`

本文の `@toc` は階層 1 の見出しを三つだけ並べる。
一方、`nav.xhtml` は「2.1　節一」と「2.1.1　項一」も入れ子で載せる。

同じ食い違いは HTML のターゲットの目次のページ（`build/html/index.xhtml`）にもある。
このページを作る golem-driver の `Golem.Driver.indexPage` も `bookToc` をすべて並べ、`depth` を見ない。
仕様書は、目次の項目の区切りの規則を「PDF の目次、本文の `@toc`、HTML の目次のページ、EPUB のナビゲーション文書」に共通のものとしており、四つを同じ目次の出力として扱っている。
深さの規則だけが、PDF と本文の `@toc` では `depth` に従い、残りの二つでは従わない。

`depth` は `@toc` の引数で、1 から 3 の整数であり、書かなければ 2 である（`Golem.Eval.File`）。
見出しは 3 階層までなので、`@toc` がなければナビゲーション文書は 3 階層まで載る。

### 仕様が不明瞭な場合の調べ

JLReq は電子書籍のナビゲーションの深さを定めていない。
EPUB 3.3 も、`toc` の `nav` が持つべき深さを定めていない。

Adobe InDesign は、EPUB の書き出しの「ナビゲーション」で目次スタイルを選ばせ、そのスタイルが載せる段落スタイルと階層からナビゲーション文書を作る。
本文の目次と同じ目次スタイルを選べば、ナビゲーション文書の深さは本文の目次と同じになる。
Pandoc の EPUB の出力も、`--toc-depth` でナビゲーション文書の深さを決める。

どちらも、ナビゲーション文書の深さを、利用者が目次に指定した深さから決めている。

## 実装すること

- ナビゲーション文書は、`@toc` があるとき、その `depth` 以下の階層の見出しだけを載せる。`@notoc` の見出しは今と同じく載せない。
- `@toc` がないときは、[golem-epub ADR 0001](0001-epub-packaging.md) のとおり、`@notoc` のない見出しをすべて載せる。
- HTML のターゲットの目次のページ（`index.xhtml`）にも同じ規則を当てる。
- 深さは `Book` の `bookTocDepth`（文書の最初の `@toc` の `depth`）から取る。`@toc` が二つ以上あれば G04002 のエラーになるので、ビルドの出力では一つに決まる。
- 載せる見出しが一つもない場合（`@toc depth=1` で階層 1 の見出しがない本）は、今の `navDocument` と同じく、ナビゲーション文書そのものへのリンクを一つ置く。目次のページは空の一覧になる。

目次の項目の並びは `Book` にすでにあり、`bookTocDepth` も `Book` にある。
`Book` と意味論の IR は変えない。
IR と CBOR を変えないので、プラグインの ABI は 7 のままである。

### アルゴリズム

`navDocument` と `indexPage` は、項目を並べる前に `bookToc` を次の条件で絞る。

```haskell
tocWithinDepth :: Book -> [TocEntry]
tocWithinDepth book = [e | e <- bookToc book, maybe True (teLevel e <=) (bookTocDepth book)]
```

この関数は golem-doc の `Golem.Doc.Assemble` に置き、golem-epub の `navDocument` と golem-driver の `indexPage` が使う。
本文の `@toc`（golem-html、golem-text）と PDF の目次（golem-driver）は、今のとおり自分のブロックの `depth` で絞る。
G04002 で `@toc` は一つに限られるので、ブロックの `depth` と `bookTocDepth` は同じ値になる。

`navDocument` の入れ子は、絞った後の項目の階層で作る。
絞った後の並びでは、ある項目の子はその項目より深い階層の項目だけなので、今の入れ子の作り方をそのまま使える。

## 実装しないこと

- ナビゲーション文書の深さを `@toc` と別に指定する設定（`[targets.epub]` の `nav-depth` のようなキー）。
  InDesign では目次スタイルを分ければ本文とナビゲーションの深さを変えられるが、それを望む利用者の例はまだない。
- `@toc` の `depth` の範囲（1 から 3）と既定（2）の変更。
- EPUB の `landmarks` と `page-list` の `nav`。
- `hidden` 属性で深い階層を隠しながらナビゲーション文書に残すこと。
  リーダーが `hidden` の枝をどう扱うかはまちまちで、利用者が目で確かめられない。

## テスト設計

### 先に書いて失敗させるテスト

`modules/golem-epub/test/PackageSpec.hs`：

- `bookToc` が階層 1、2、3 の項目を持ち、`bookTocDepth = Just 1` の `Book` のナビゲーション文書が、階層 1 の項目だけを持ち、入れ子の `ol` を持たないこと。
- 同じ `bookToc` で `bookTocDepth = Just 2` のとき、階層 3 の項目を持たず、階層 2 の項目が階層 1 の項目の下に入れ子になること。
- `bookTocDepth = Nothing` のとき、三つの階層の項目がすべて入れ子で載ること（今のテストがこれに当たり、変えずに通ること）。
- 階層 2 の項目だけを持ち、`bookTocDepth = Just 1` の `Book` のナビゲーション文書が、`#toc` へのリンクを一つ持つこと。

`modules/golem-driver/test/Main.hs`：

- 文脈の三つのファイルのプロジェクトを EPUB に組み、`nav.xhtml` に「節一」と「項一」がないこと。
- 同じプロジェクトを HTML に組み、`index.xhtml` に `toc-2` と `toc-3` の項目がないこと。
- `@toc` を除いた同じプロジェクトでは、`nav.xhtml` と `index.xhtml` に三つの階層の項目がすべてあること。

`modules/golem-doc/test`：

- `tocWithinDepth` が、`bookTocDepth` が `Nothing` なら `bookToc` をそのまま返し、`Just d` なら階層が `d` 以下の項目だけを順を保って返すこと。

### 自動テストにしない確かめ方

文脈のプロジェクトを EPUB に組み、epubcheck にかけてエラーと警告が出ないことを確かめる。
Apple Books か Thorium Reader で開き、リーダーの目次に階層 1 の見出しだけが並ぶことを目で確かめる。

## トレードオフ

`@toc` を置いた本では、ナビゲーション文書から深い見出しへ移れなくなる。
リーダーの目次は本文の目次と違って紙面を取らないので、深い見出しを載せても困らないという考え方もある。
しかし、本文の目次と同じ深さにしておけば、利用者は一つの `depth` で両方を決められ、`@toc` を書いた意図とリーダーの目次が食い違わない。
深さを分けたい要望が出たら、そのときに別のキーを足す。

`@toc` を書いて `depth` を省くと深さは 2 になるので、今まで 3 階層を載せていた本のナビゲーション文書が浅くなる。
v1 のリリースの前なので、この変化を受け入れる。

`@toc` のブロックを持たない二つの出力は `bookTocDepth` を、ブロックを持つ三つの出力はブロックの `depth` を見るので、深さの出どころは二つある。
G04002 があるので二つは同じ値になり、本文の `@toc` と PDF の目次の実装を書き換えずに済む。

## ドキュメント

- docs/specifications.md の「目次と文書構造の参照」の節に、EPUB のナビゲーション文書と HTML の目次のページは、`@toc` があればその `depth` に従い、なければ `@notoc` のない見出しをすべて載せることを書き、この ADR へリンクする。
- docs/specifications.md の「既知の不具合」から「EPUB のナビゲーション文書と `@toc` の深さ」の項を除く。
- [golem-epub ADR 0001](0001-epub-packaging.md) のステータスの行を「採択→`@toc` がある場合のナビゲーション文書の深さは [ADR 0002](0002-nav-and-toc-depth.md)」の形で改める（今のステータスの行の [docs/adr ADR 0033](../../adr/0033-colophon-contributors-and-printings.md) の記述は残す）。
- ユーザーのマニュアルの「EPUB」の節（`manual/chapters/06-output.gm`）の、ナビゲーション文書を必ず作るという説明に、`@toc` の `depth` に従うことを足す。
- ユーザーのマニュアルの付録の「既知の不具合」（`manual/appendices/i-known-issues.gm`）から「EPUB の目次が `@toc` の深さに従わない」の項を除く。

## 参考文献

- W3C, EPUB 3.3, 7.4 EPUB navigation document, https://www.w3.org/TR/epub-33/#sec-nav
- Adobe, InDesign ユーザーガイド「EPUB へのコンテンツの書き出し」, https://helpx.adobe.com/jp/indesign/using/export-content-epub-cc.html
- Pandoc User's Guide（`--toc-depth`）, https://pandoc.org/MANUAL.html
- W3C, Requirements for Japanese Text Layout（JLReq）, https://www.w3.org/TR/jlreq/
