# ADR 0003: 別のファイルの参考文献への引用の印のリンク

ステータス: 採択→本文の 62、77、88、103 行の golem-doc の ADR へのリンクは誤って docs/adr/0008 を指している。正しい先は [golem-doc ADR 0008](../../golem-doc/adr/0008-multiple-index-and-bibliography.md)

## 文脈

HTML と EPUB の本文の引用の印（`[cite キー]`）は、`<a class="cite" href="#cite-<キー>">[n]</a>` と書かれる。
リンクの先は、いつも同じページの `#cite-<キー>` である。
参考文献の一覧の項目は `<li id="cite-<キー>">` であり、`@bibliography` を置いたファイルのページにだけある。
そのため、`@bibliography` を引用と別のファイルに置くと、リンクの先がない。

次の三つのファイルからなるプロジェクトで確かめた（main の a2b6106e）。

- `chapters/00.gm`：`@toc depth=1`
- `chapters/01.gm`：`本文[cite knuth1981]。`
- `chapters/99.gm`：`@bibliography`

`golem build` の HTML の `chapters/01.xhtml` は `<a class="cite" href="#cite-knuth1981">[1]</a>` を含み、`id="cite-knuth1981"` は `chapters/99.xhtml` にだけある。
EPUB の `OEBPS/chapters/01.xhtml` も同じである。

原因は golem-html の `Golem.Html` の `inline` の `Cite` の分岐である。
この分岐は `"#cite-" <> キー` を直に書き、ファイルの部分を付けない。
ラベルへの参照（`Ref`）、注の印（`Note`）、目次（`toc`）、索引（`index`）は、どれも `linkTo` で参照先のファイルへの相対リンクを作っている。
引用の印だけが、この関数を通っていない。

[golem-html ADR 0001](0001-xhtml-serializer.md) の要素の対応の表は、注の印と参照をリンクにすると定めているが、引用の印の行を持たない。
引用の印のリンクの先は、どの ADR も定めていない。
ユーザーのマニュアルは、引用を本文の各章に書き、`@bibliography` を `manual/back.gm` に置いているので、マニュアルの HTML の引用のリンクはすべて切れている。
マニュアルの付録の「既知の不具合」もこの不具合を載せている。

EPUB では、リンク切れは見た目の不具合にとどまらない。
epubcheck は、ファイルの中にない断片識別子を指すリンクをエラー（RSC-012）にする。
ただし、この ADR を書いたマシンには epubcheck がなく、上の EPUB で RSC-012 が出ることは確かめていない。
[golem-epub ADR 0001](../../golem-epub/adr/0001-epub-packaging.md) は、出力した EPUB を epubcheck にかけ、エラーと警告が出ないことを求めている。
CI の epubcheck にかける fixture（`modules/golem-driver/test/fixtures/sample`）は、引用と `@bibliography` を別のファイルに置いていないので、この不具合を検出していない。

## 実装すること

### リンクの先

- 引用の印のリンクの先のファイルは、その印が載る参考文献の一覧（IR のチャネルの出力 `BibliographyOutput`）のある文書とする。どの一覧に載るかは [golem-doc ADR 0008](../../golem-doc/adr/0008-multiple-index-and-bibliography.md) が定める（印の後にある最初の一覧、なければ最後の一覧）。一覧が一つなら、その一覧のある文書である。
- 印は、そのファイルへの `linkTo` のリンクにする。断片識別子は今と同じく `cite-<キー>` とする。
  同じファイルなら今と同じ `#cite-<キー>` になり、別のファイルなら `../chapters/99.xhtml#cite-knuth1981` のような相対リンクになる。
- 本に `@bibliography` がないときは、印をリンクにせず、`<span class="cite">[n]</span>` と書く。
  今はこの場合も同じページの `#cite-<キー>` を指しており、リンクの先がない。
- 書誌データにないキー（G02021）の印は、今と同じく何も書かない。

`@bibliography` を二つ以上置いた本の扱い（一覧ごとの番号と、`id` の重複の避け方）は、[golem-doc ADR 0008](../../golem-doc/adr/0008-multiple-index-and-bibliography.md) に従う。
この ADR は、印から一覧のある文書へのリンクの作り方だけを定める。

### 置き場所

先のファイルは golem-html の中で `Book` から求める。
`Golem.Html` に次の関数を加え、`page` が作る `Ctx` に結果を持たせる。

```haskell
-- | The file of the bibliography list a cite mark belongs to (golem-html ADR 0003,
-- golem-doc ADR 0008).
bibliographyHome :: Book -> CiteMark -> Maybe FileId
```

どの一覧に載るかの情報は、golem-doc [ADR 0008](../../adr/0008-first-release-verification.md) が `Book` に加えるものを使う。
意味論の IR は変えない。
IR と CBOR を変えないので、プラグインの ABI は 7 のままである。

EPUB の本文は golem-html の出力なので、同じ変更で EPUB の引用の印も直る。
EPUB では、`OEBPS/` の下のページのパスが HTML の `build/html/` の下と同じなので、相対リンクはそのまま使える。

## 実装しないこと

- 引用の印に `epub:type="biblioref"` や `role="doc-biblioref"` を付けること。
  注の印の `noteref` はリーダーのポップアップのために付けたが、参考文献の参照をポップアップにするリーダーの扱いは確かめていない。
- 参考文献の項目から本文の引用の印へ戻るリンク。
  一つの文献は本文の何か所からも引用されるので、戻り先が一つに決まらない。
- `@bibliography` がない本で `[cite ...]` を使ったときの diagnostic。
  PDF もこの場合に番号だけを組んでおり、出力の間で振る舞いをそろえる。
- `@bibliography` を複数置いたときの番号と `id` の扱い（golem-doc [ADR 0008](../../adr/0008-first-release-verification.md) で定める）。

## テスト設計

### 先に書いて失敗させるテスト

`modules/golem-html/test/XhtmlSpec.hs`：

- 二つの文書からなる `Book` で、一つ目の文書に `Cite` があり、二つ目の文書に `BibliographyOutput` があるとき、一つ目のページの印が、二つ目のページへの相対パスに `#cite-<キー>` を付けたリンクであること。
- 同じ文書に `Cite` と `BibliographyOutput` があるとき、印のリンクが今と同じ `#cite-<キー>` であること（今の二つのテストがこれに当たり、変えずに通ること）。
- `BibliographyOutput` がどの文書にもないとき、印が `<span class="cite">[1]</span>` であり、`href` を含まないこと。
- `BibliographyOutput` を二つの文書に置いたとき、それぞれの印が golem-doc [ADR 0008](../../adr/0008-first-release-verification.md) の規則で決まる一覧の文書へリンクすること。
- `BibliographyOutput` が箇条書きの項目の中にあるときも、その文書へリンクすること。

`modules/golem-driver/test/Main.hs`：

- 文脈の三つのファイルのプロジェクトを HTML と EPUB に組み、`chapters/01.xhtml` の印の `href` が `../chapters/99.xhtml#cite-knuth1981` であり、その先のページに `id="cite-knuth1981"` があること。

### 自動テストにしない確かめ方

文脈の三つのファイルのプロジェクトを EPUB に組み、epubcheck にかけて、RSC-012 を含むエラーと警告が出ないことを確かめる。
修正の前の出力では RSC-012 が出ることも確かめ、テストの前提が正しいことを確かめる。
ユーザーのマニュアルを HTML に組み、ブラウザで本文の引用の番号を押して、参考文献のページの該当する項目に移ることを確かめる。

## トレードオフ

リンクの先を決める規則を golem-doc [ADR 0008](../../adr/0008-first-release-verification.md) に任せるので、二つの ADR は同じ時期に採択し、実装する必要がある。

先のファイルを golem-html で求めるので、ほかの出力が同じ情報を要るようになれば、`Book` に移すことになる。
今それを要るのは HTML と EPUB だけであり、`Book` を広げるより局所的に済ませる。

`@bibliography` がない本の印をリンクにしないので、HTML の要素が `a` と `span` の二通りになる。
CSS のクラスは同じ `cite` なので、見た目を変えたい人は一つの規則で両方に当てられる。

## ドキュメント

- docs/specifications.md の「引用と参考文献」の節に、HTML と EPUB の引用の印は、その印が載る参考文献の一覧の項目へのリンクであり、`@bibliography` がなければリンクにしないことを書き、この ADR へリンクする。
- docs/specifications.md の「既知の不具合」から「HTML の引用の印のリンク」の項を除く。
- ユーザーのマニュアルの付録の「既知の不具合」（`manual/appendices/i-known-issues.gm`）から「HTML で引用の番号のリンクが切れる」の項を除く。

## 参考文献

- W3C, EPUB 3.3, https://www.w3.org/TR/epub-33/
- W3C, EPUBCheck のメッセージの一覧（RSC-012）, https://github.com/w3c/epubcheck/blob/main/src/main/resources/com/adobe/epubcheck/messages/MessageBundle.properties
