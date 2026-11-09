# ADR 0267: PDF のしおりと文書の中のリンク

ステータス: 採択

## 文脈

[ロードマップ](../roadmap.md) の v1.0.0 の「LaTeX との差を埋める項目」に、「PDF のしおりとリンク」がある。
見出しから PDF のしおり（アウトライン）を作り、相互参照、目次、索引、脚注の印を PDF のリンクにする項目で、「リンクのほかの注釈も扱う」と添えてある。
[2026-10-17 の調査](../audits/2026-10-17-latex-gap-for-v1.md) の 5 が、この項目の調べである。
v2 にあった「PDF のしおりとリンク」（「アウトライン、文書の中のリンク、注釈」）は、コミット fd91d507 でこの項目に合わせてあり、ほかの項目に取り出し元の記述は残っていない。

この ADR は、同じ時期の ADR の [ADR 0260](0260-front-matter-folios-and-page-labels.md) から 0266 の後に実装する。
リンクの元になるもの（表の番号、複数段落の注、索引のページの範囲、複数の文献の引用）と、ページ番号の書式が、それらの ADR で変わるからである。

### 今の PDF

PDF が書く注釈は、外部の URL へのリンクの注釈だけである（[ADR 0182](0182-external-links.md)）。
ページは注釈の一覧 `pageAnnots` を持ち、注釈の型はリンクの注釈の一つで、動作は URI を開くことだけである（[`Writer.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L197-L223)）。
注釈の辞書は、`/A`、`/Border [0 0 0]`、`/F 4`、`/Rect`、`/Subtype /Link`、`/Type /Annot` に、構造の木のための `/Contents` と `/StructParent` を足したものである（[`annotationObject`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L847-L865)）。
注釈のオブジェクトは、出力インテントと XMP の後、構造の木の前に、ページの順、ページの中の描いた順で番号を振る（[`Writer.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L567-L572)、[`objects`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L643)）。
カタログは `/Outlines` も `/PageMode` も持たない（[`catalog`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L599-L609)）。

リンクの範囲は、行分割の箱の見た目の `lkLink :: Maybe LinkTarget` が持つ。
`LinkTarget` は今は `LinkUri Text` だけで、型の注釈は「文書の中の行先は後で足す構成子」と書いている（[`Look.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-layout/src/Golem/Layout/Look.hs#L146-L150)）。
`lkLink` を決めるのは、golem-typeset の `restyle` が `Link` のインラインを読むところだけである（[`Fonts.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-typeset/src/Golem/Typeset/Fonts.hs#L462-L463)）。
矩形は、行ごとに同じ `lkLink` の箱の連なりを一つにまとめ、行の面にする（[`linkRects`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L765-L778)）。
行をまたぐリンクは行ごとの注釈になり、`/QuadPoints` は使わない（[ADR 0182](0182-external-links.md)）。
注釈を作るのは golem-typeset の `pdfPages` で、`LinkUri` の矩形だけを `UriAction` の注釈にする（[`Draw.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L367-L371)）。

構造の木では、リンクの注釈は `Link` の要素の `OBJR` になり、注釈は `/StructParent` を持ち、注釈のあるページは `/Tabs /S` を持つ（[ADR 0183](0183-tagged-pdf-and-pdf-a.md)、[`structureObjects`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L713-L737)）。
相互参照、引用の印、本文の注の印は、すでに `Reference` の要素である（[仕様書の構造の要素の表](../specifications.md)、[ADR 0215](0215-ref-number-and-ref-title-as-reference.md)）。
[ADR 0183](0183-tagged-pdf-and-pdf-a.md) は、PDF に文書の中のリンクがないので、`Note` を印の直後に置き、支援技術が印と注を対応づけられるようにした（「メンテナーが決めること」の 9）。

### 行先を求める材料

ページの番号は、組版の繰り返し（S2）が収束した後のページから引ける。
ラベルのページは `labelPages`、索引の印のページは `markPages`（[`Paginate.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-layout/src/Golem/Layout/Paginate.hs#L604-L609)）、見出しのページは見出しの最初の行を置いた段から引く `headingPages` である（[`Flow.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L599-L604)）。
どれもページの番号だけを返し、ページの中の位置は持たない。
位置は、描いた行の面（`LineRec` の `lrRect`）と、図版の矩形から求められる。

`[ref-number]` と `[ref-title]` は、組み立てで `Resolved` の要素になり、指すラベルを持ったまま組版に届く（[ADR 0215](0215-ref-number-and-ref-title-as-reference.md)）。
`[ref-page]` は `Ref` のまま届き、ページが決まってから数字になる。

### HTML と EPUB の今

HTML と EPUB（golem-epub は golem-html の書き手を使う）は、すでに次のものをリンクにしている（[`Html.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-html/src/Golem/Html.hs#L686-L716)）。

- 目次の項目（`@toc`、ナビゲーション文書、HTML の目次のページ）
- `[ref-page]`（ページを持たないので、参照先の題へのリンク）
- 脚注と章末の注の印から注へ、注の印から本文の印へ（[`notesSection`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-html/src/Golem/Html.hs#L735-L751)）
- 索引の項目の位置
- `[cite]` から参考文献の項目へ（参考文献が別のファイルにあっても。[golem-html ADR 0003](../golem-html/adr/0003-cite-links-across-files.md)）

リンクにしていないのは、傍注の印と、`[ref-number]` と `[ref-title]` の `Resolved` である。
`Resolved` は「まだリンクにしない」と書いて中の文字だけを書く。
[ADR 0215](0215-ref-number-and-ref-title-as-reference.md) は、HTML と EPUB のリンクを別の ADR で決めるとした。
プレーンテキスト（golem-text）はリンクを持たない。

### InDesign と LaTeX

InDesign は、しおりのパネルでしおりを作り、目次を作るときの「PDF のしおりを作成」の設定で目次の項目をしおりにする。
PDF の書き出しでハイパーリンクを選ぶと、相互参照、目次の項目、索引の項目が PDF のリンクになる。
これらは調査が Adobe のヘルプの検索の抜粋で確かめたことで、ヘルプの本文は読めていない（[調査](../audits/2026-10-17-latex-gap-for-v1.md) の「調べ方」）。
しおりの開閉の既定と、リンクの行先の形（ページの全体か位置か）は確かめていない。

LaTeX の hyperref は、相互参照、目次、脚注、引用をリンクにし、見出しからしおりを作る。
しおりの深さは目次の深さに従い、既定では子の項目を閉じる（`bookmarksopen=false`）。
JLReq は PDF のしおりとリンクを定めていない。

## 実装すること

### しおり

- 目次の項目の並び `tocWithinDepth`（[`Assemble.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-assemble/src/Golem/Assemble.hs#L172-L177)）を、そのまましおりにする（「メンテナーが決めること」の 1）。`@toc` があればその `depth` までの階層、なければ `@notoc` のない見出しのすべてである。EPUB のナビゲーション文書と HTML の目次のページと同じ規則になる（[golem-epub ADR 0002](../golem-epub/adr/0002-nav-and-toc-depth.md)）。本の中に `@toc` があるかどうかは、しおりを作るかどうかを変えない。
- しおりの題は、目次の項目と同じく、番号、番号と題の区切り、短い題（`@toc-title`、なければ見出しの題）を並べた文字である。題の文字は `inlineText`（ルビは親文字だけ。[`Assemble.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-assemble/src/Golem/Assemble.hs#L247-L260)）で作り、PDF の文字列（`pdfTextString`）で書く。
- 入れ子は、ある項目の親を、それより前で階層が小さい最も近い項目とする。階層 1 の次に階層 3 が来れば、階層 3 の項目は階層 1 の項目の子になる。
- 子を持つ項目は閉じて書く（「メンテナーが決めること」の 2）。`/Count` は、ルートでは最上位の項目の数、子を持つ項目では子の数を負にした値で、子を持たない項目には書かない（ISO 32000-1 の 12.3.3）。
- しおりの項目の行先は、見出しの行先（下の「行先」）である。
- しおりが一つ以上あれば、カタログに `/Outlines` と `/PageMode /UseOutlines` を書く（「メンテナーが決めること」の 3）。しおりがなければどちらも書かない。

### リンクにするもの

次のものを、文書の中の行先へのリンクにする（「メンテナーが決めること」の 5、6）。

| リンクの元 | 矩形 | 行先 |
| --- | --- | --- |
| `[ref-number]`、`[ref-title]`（`Resolved`） | 置き換わった文字 | ラベルを付けたブロック |
| `[ref-page]` | ページ番号の文字 | ラベルを付けたブロック |
| 本文の脚注と章末の注の印 | 印 | 注の本文の最初の行 |
| 注の側の印（脚注と章末の注） | 注の側の印 | 本文の注の印の行 |
| PDF の目次と本文の `@toc` の項目 | 項目の行ごとに、最初の箱からページ番号の終わりまで（リーダーを含む） | 見出し |
| 索引のページ番号 | ページ番号の文字ごと | そのページで、その項目の最初の印の行 |
| `[cite]` の番号（`@bibliography` があるとき） | 文献ごとの番号の文字 | 参考文献の項目の最初の行 |

- 傍注の印はリンクにしない。印と傍注は同じ見開きの同じ行の高さにあり、HTML もリンクにしていない。
- `@bibliography` のない本の引用はリンクにしない。HTML が `<span>` にするのと同じである。
- [ADR 0262](0262-table-numbers-captions-column-widths-and-cell-styles.md) の表の番号はラベルを付けたブロックとして、[ADR 0263](0263-notes-with-more-than-one-paragraph.md) の複数段落の注は注として、上の表のとおりに扱う。注の本文の最初の行は、最初の段落の最初の行である。
- [ADR 0265](0265-index-cross-references-page-ranges-and-section-headings.md) のページの範囲は、範囲の始まりの数字を始まりの印へ、終わりの数字を終わりの印へのリンクにする。あいだの記号はリンクにしない。「を見よ」「をも見よ」の参照はリンクにしない（「実装しないこと」）。
- [ADR 0266](0266-citation-locators-and-multiple-keys.md) の複数の文献の引用は、文献ごとに、[ADR 0266](0266-citation-locators-and-multiple-keys.md) がその文献に割り当てた番号の文字をリンクにする。頁の指定の文字は、[ADR 0266](0266-citation-locators-and-multiple-keys.md) がその文献の番号と一続きに組むならその番号のリンクに含め、そうでなければリンクにしない。
- リンクの元が別のリンクの元の中にあれば、外側のリンクだけを作る（「メンテナーが決めること」の 9）。見出しの題の中の `[ref-number]` や注の印を目次の項目に写した場合が当たる。`restyle` は、`lkLink` がすでに `Just` なら変えない。`[link]` の中の相互参照、注、引用は今のとおり G02128 で拒むので、外部のリンクと重なることはない。

### 行先

- 行先は、明示した行先の配列 `[p 0 R /XYZ null t null]` を注釈の `/Dest` に書く（「メンテナーが決めること」の 4）。名前の付いた行先（`/Dests`、`/Names` の `/Dests`）と `/GoTo` のアクションは使わない。
- `p` は行先のページのオブジェクト、`t` は行先の最初に描いたものの上端の y 座標である。行の面なら面の上端、図版なら図版の矩形の上端、表なら最初の格子の行の面の上端である。縦組みでも同じく上端を使う。縦組みの行の面の上端は版面の行頭の側の端なので、行の始まりがウィンドウの上端にそろう。
- `left` と `zoom` は `null` とし、閲覧ソフトの今の横の位置と倍率を保つ。
- 座標は、ページのトンボと塗り足しの分を足した、ページの上の座標である（図版の `BBox` と同じく `frameOrigin` を足す）。数の書き方は `/Rect` と同じである。
- ラベルを付けたブロックの行先は、そのブロックの最初に描いたものである。[ADR 0262](0262-table-numbers-captions-column-widths-and-cell-styles.md) がキャプションを表の前に置き、ラベルのブロックに含めるなら、キャプションの最初の行になる。
- ページラベル（[ADR 0260](0260-front-matter-folios-and-page-labels.md)）は行先を変えない。行先はページのオブジェクトを指し、ページの番号の文字を使わないからである。

### 型（golem-layout、golem-pdf、golem-typeset）

golem-layout の `LinkTarget` に、文書の中の行先の構成子を足す。

```haskell
data LinkTarget = LinkUri Text | LinkTo LinkDest

-- | Where a link inside the document goes (docs/adr/0267).
data LinkDest
  = DestLabel Text            -- the block of a label
  | DestHeading SrcSpan       -- a heading, by the span of its block
  | DestNote NoteId           -- the first line of the body of a note
  | DestNoteMark NoteId       -- the line of the mark of a note in the text
  | DestIndexMark SrcSpan     -- the line of an index mark
  | DestBibEntry SrcSpan Text -- an entry of the @bibliography at a span, by its key
```

golem-pdf の `LinkAction` と `Document` を広げる。

```haskell
data LinkAction = UriAction Text | GoTo Dest

-- | A destination (docs/adr/0267): the page by its index and the top of the window.
data Dest = DestXyz !Int !Sp

data OutlineItem = OutlineItem
  { oiTitle :: !Text,
    oiDest :: !Dest,
    oiKids :: ![OutlineItem]
  }
```

`Document` に `docOutline :: [OutlineItem]` を足す。
`Dest` は `/XYZ` の一つの形だけを持つ。
ほかの形（`/Fit`、`/FitH`）は、使う場面ができたときに構成子を足す。

golem-typeset は、すべてのページを描いた後に、行先ごとのページと上端の表を作り、`LinkTo` の矩形を `GoTo` の注釈にする。
行先が表にないリンクの元かしおりの項目があれば、G07120 のエラーとし、PDF を書かない（下の「diagnostic」）。

パッケージの依存は変えない。
golem-typeset はすでに golem-assemble、golem-layout、golem-pdf に依存し、golem-layout の新しい型は golem-syntax の `SrcSpan` と、すでにある `NoteId` しか使わない。
意味論の IR、CDDL、プラグインの ABI は変わらない。

### PDF の書き方

注釈の辞書は、`/A` の代わりに `/Dest` を持つほかは、外部のリンクと同じ形である。

```
<< /Border [0 0 0] /Dest [12 0 R /XYZ null 700.5 null] /F 4 /Rect [x1 y1 x2 y2] /Subtype /Link /Type /Annot /Contents (...) /StructParent n >>
```

- `/Contents` は、リンクの元の描いた文字である（「メンテナーが決めること」の 8）。目次の項目は、番号、区切り、題、ページ番号の文字を並べたもので、リーダーは含めない。
- 一つのページの注釈は、外部のリンクと文書の中のリンクを分けずに描いた順に並べる。
- しおりのオブジェクトは、注釈のオブジェクトの後、構造の木の前に置く。`/Outlines` の辞書、その後に項目を先行順（文書の順）に並べる。項目は `/Title`、`/Parent`、`/Prev`、`/Next`、`/First`、`/Last`、`/Count`、`/Dest` のうち要るものを持ち、キーは名前の順に書く。
- 文書の中のリンクもしおりもない PDF のバイト列は変わらない。

### 構造の木

- 文書の中のリンクも、[ADR 0183](0183-tagged-pdf-and-pdf-a.md) のとおり `Link` の要素にし、リンクの文字の葉と行ごとの注釈の `OBJR` を行の順に持たせる（PDF/UA-1 の 7.18.5）。
- `Link` は、リンクの元の要素の子にする。相互参照、引用、本文の注の印は今の `Reference` の子、注の側の印は `Note` の `Lbl` の子、索引のページ番号は項目の行の `P` の中の `Reference` の子、目次の項目は `TOCI` の中の `Reference` の子である（ISO 32000-1 の 14.8.4.3 の表 333 で、`TOCI` の子に `Reference` が許される）。
- しおりは構造の木の外にあり、構造の木を変えない。

### HTML と EPUB

`Resolved` を、`Ref` と同じくラベルの行先への `<a href>` にする（「メンテナーが決めること」の 7）。
ほかの要素の中に写したもの（目次の項目、ナビゲーション文書、柱）では、今のとおり文字だけを書く。
プレーンテキストは変えない。

### diagnostic

| コード | 重大度 | 原因 |
| --- | --- | --- |
| G07120 | エラー | リンクの元かしおりの項目の行先が、描いたページにない |

G07120 は、行先を集める処理とリンクの元を作る処理が食い違ったときにだけ起き、原稿では起こせない。
[G07107](../diagnostics.md) と同じく、Golem の誤りとして報告を求めるメッセージにし、PDF を書かず、HTML、EPUB、プレーンテキストは書く。
行先のないリンクを黙って落とすと、出力を黙って変えることになるので、エラーにする。
位置は最初のリンクの元の原稿の位置で、しおりの項目なら見出しのブロックである。
コードの番号は、採択のときに、使われていない番号であり同じ時期の ADR と重ならないことを確かめて振り直した（「決めたことの記録」）。

### 文書

実装は次の文書を同じプルリクエストで改める。

- [ロードマップ](../roadmap.md)：「LaTeX との差を埋める項目」の「PDF のしおりとリンク」を消す。ほかの項目から取り出した部分はない（「文脈」）。「リンクのほかの注釈」は「課題にしなかった事項」に移す（「メンテナーが決めること」の 10）。「手で確かめる項目」の「PDF のリンクの注釈」に、文書の中のリンクとしおりを Acrobat Reader と macOS のプレビューで開いて確かめることを足す。ISO 15930-7 の照合の項目の問いに、`/Dest` を持つリンクの注釈と `/Outlines` を足す。
- [仕様書](../specifications.md)：「リンク」の節に文書の中のリンクと行先、しおりの節、構造の要素の表の `Link` の置き場所、HTML の `Resolved` のリンク。
- [diagnostics](../diagnostics.md)：G07120。
- 記法は変えないので、[docs/markup.md](../markup.md) は変えない。
- マニュアルが PDF のリンクを説明していれば、その節に文書の中のリンクとしおりを足す。

## 実装しないこと

- **リンクのほかの注釈**：テキストの注釈（付箋）、ハイライト、フォームのフィールド、添付ファイルの注釈は作らない。ロードマップの「リンクのほかの注釈も扱う」は、元の v2 の項目の「注釈」を合わせたときに残った語で、使う場面が書かれていない。LaTeX の差の調査にも InDesign の調べにも、リンクのほかの注釈の不足は挙がっていない。PDF/X-4 と PDF/A-2 の注釈の制約を照合する手間も増える。
- **名前の付いた行先**：外の PDF やウェブのページから `#ラベル` で本の中を指すことはできない。必要になれば、名前の木を書く ADR を作る。
- **索引の「を見よ」「をも見よ」のリンク**：索引の中の別の項目への行先を集める仕組みが要る。hyperref も既定ではリンクにしない。
- **傍注の印のリンク**。
- **しおりの開閉、深さ、色、書体の設定**：`style.toml` の欄を足さない。
- **しおりの題の文字の言語**：しおりの項目は `/Lang` を持てないので、言語の区間は題の文字に反映しない。
- **ページラベル**：[ADR 0260](0260-front-matter-folios-and-page-labels.md) が扱う。
- **リンクの見た目**：今のとおり色、下線、枠を付けない。
- **`/QuadPoints`**：[ADR 0182](0182-external-links.md) のとおり使わない。

## 不変条件

PDF の文書の中のリンクの注釈を「内部の注釈」、しおりの項目を「項目」と呼ぶ。

- **I1 内部の注釈は行先を一つ持つ**：どのリンクの注釈も、`/A`（URI）と `/Dest` のちょうど一方を持つ。`/Dest` は `[p 0 R /XYZ null t null]` の形で、`p` は `/Pages` の木のページであり、`t` はそのページの `/MediaBox` の下端と上端のあいだにある。
- **I2 行先は描いた位置にある**：内部の注釈の `/Dest` のページと `t` は、その行先の最初に描いたもののページと上端に一致する。
- **I3 リンクの元はすべてリンクになる**：「リンクにするもの」の表の各行のリンクの元が、外側のリンクの元の中にない限り、少なくとも一つの内部の注釈を持ち、その矩形が元の文字の行の面に一致する。行をまたぐ元は、行ごとに一つの注釈を持つ。
- **I4 リンクは重ならない**：一つの行の中で、異なる注釈の矩形の内部は重ならない。外側のリンクの元の中のリンクの元は、注釈を持たない。
- **I5 しおりは目次の項目と一対一**：項目の先行順の並びは `tocWithinDepth` の並びと同じ長さで、i 番めの項目の題は i 番めの目次の項目の番号、区切り、題を並べた文字であり、行先はその見出しである。
- **I6 入れ子は階層に従う**：項目の親は、それより前で階層が小さい最も近い項目であり、そのような項目がなければルートである。
- **I7 開閉の数**：ルートの `/Count` は最上位の項目の数である。子を持つ項目の `/Count` は子の数を負にした値で、子を持たない項目は `/Count` を持たない。
- **I8 しおりがなければ何も足さない**：`tocWithinDepth` が空なら、カタログは `/Outlines` と `/PageMode` を持たない。内部の注釈もしおりもない本の PDF のバイト列は、この ADR の前と同じである。
- **I9 構造の木の中の置き場所**：内部の注釈は、ちょうど一つの `Link` の要素の `OBJR` であり、その `Link` の親は `Reference` か、`Note` の `Lbl` である。
- **I10 決定性**：同じ入力からは、同じバイト列の PDF と、同じ並びの diagnostic になる。
- **I11 HTML の参照**：外側のリンクの中にない `Resolved` は、その指すラベルの行先への `<a href>` になる。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 見出しの数 | 0、1、2 |
| `@toc` | なし、`depth=1` で階層 2 の見出しだけ（しおりが空）、`depth=6` |
| 見出しの階層の並び | 1→2、1→3（飛ぶ）、3→1（戻る）、同じ階層が続く |
| リンクの元の行 | 一行に収まる、行の終わりでちょうど終わる、一字だけ次の行にあふれる、段とページをまたぐ |
| 組み方向 | 横組み、縦組み |
| 注 | ページの最後の行の印と次のページに続く脚注、章末の注、一つの段落の注、二つの段落の注 |
| 索引の項目 | 印が一つ、同じページに印が二つ、ページの範囲 |
| 引用 | `@bibliography` なし、一つの文献、二つの文献 |
| 入れ子 | 見出しの題の中の `[ref-number]` と注の印を目次に写したもの |
| 行先の位置 | ページの最初の行、ページの最後の行、図版、表 |

## テスト設計

先に書いて失敗させるテストは次のとおりである。
テストの名前には不変条件の番号を入れる。

### golem-pdf のテスト

- `I1`：`GoTo` の注釈の辞書が `/Dest [p 0 R /XYZ null t null]` を持ち、`/A` を持たないこと。`UriAction` の注釈が今と同じバイト列であること。
- `I6`、`I7`：階層の並び（境界の表の四つ）から作ったしおりが、`/Parent`、`/First`、`/Last`、`/Prev`、`/Next`、`/Count` を不変条件のとおりに持つこと。
- `I8`：`docOutline` が空で `GoTo` の注釈のない `Document` のバイト列が、この ADR の前のゴールデンと同じであること。
- `I10`：しおりと内部の注釈を持つ `Document` を二度書き、同じバイト列になること。オブジェクトの番号が、注釈、`/Outlines`、項目、構造の木の順であること。

### golem-typeset のテスト

- `I2`：ページの最初の行、最後の行、図版、表に付けたラベルへの参照の `/Dest` の `t` が、描いたものの上端に `frameOrigin` を足した値であること。横組みと縦組みの両方で確かめる。
- `I3`：境界の表のリンクの元の行の四つで、注釈の数と矩形が行の面に一致すること。
- `I4`：見出しの題の中の `[ref-number]` と注の印が、目次の項目では注釈を持たず、目次の項目の注釈だけがあること。
- 行先を表から抜いた入力で、G07120 が一つ出て PDF を書かないこと。

### golem-driver のテスト

- `I5`、`I8`：`@toc` の三つの場合のプロジェクトを組み、しおりの題と並びが `tocWithinDepth` と一致すること。しおりが空なら `/Outlines` がないこと。
- `I3`：注、索引、引用、目次、相互参照をすべて含む fixture（[ADR 0183](0183-tagged-pdf-and-pdf-a.md) の `conformance`）の PDF で、表の各行のリンクの元に注釈があること。
- `I9`：同じ fixture の構造の木のゴールデンで、内部の注釈の `Link` の親が `Reference` か `Lbl` であること。
- `I10`：同じ fixture の PDF を二度組み、バイト列が同じであること。
- CI の veraPDF の検査（PDF/A-2b、PDF/A-2u、PDF/UA-1）が、`conformance` の fixture の PDF で誤りを出さないこと。

### golem-html のテスト

- `I11`：`Resolved` が `<a href>` になり、目次の項目とナビゲーション文書の中の `Resolved` は文字だけになること。

### 自動テストにしない確かめ方

横組みと縦組みの `conformance` の PDF を Acrobat Reader と macOS のプレビューで開き、しおりのパネルが開いて最上位の項目だけが並ぶこと、しおりと各種のリンクをクリックして行先の行がウィンドウの上端に来ることを目で確かめる。
結果は実装のプルリクエストに書く。

## トレードオフ

明示した行先は、ページのオブジェクトを直接指すので、名前の木も名前の文字列も要らない。
注釈の数だけ配列を書くが、名前の付いた行先でも注釈ごとに名前の文字列を書くので、バイト数はほぼ変わらず、名前の木の分だけ明示した行先が小さい。
失うのは、外から `#ラベル` で指す手段である。

`/XYZ null t null` はウィンドウの上端を行先に合わせ、横の位置は今のままにする。
縦組みで拡大して読んでいると、行先の行がウィンドウの横の外にあることがありうる。
`/FitV` で行の位置を左端に合わせる案は、倍率を変えてしまう。
多くの閲覧ソフトがページの幅に合わせて表示するので、上端だけを合わせれば足りると判断した。

しおりを目次の深さに合わせると、`@toc depth=1` の本では節がしおりに出ない。
目次とナビゲーション文書としおりの三つが同じ深さになることを優先した。
深さを別に決めたい本の例が出たら、設定を足す ADR を作る。

外側のリンクだけを作る規則は、目次の項目の中の注の印から注へは飛べなくする。
目次から注に飛ぶ読み方はまずないので、項目の全体を一つのリンクにするほうを採った。

## メンテナーが決めること

1. **しおりに載せる見出し**：推奨は `tocWithinDepth`（`@toc` の `depth` まで、なければ `@notoc` のないすべて）である。EPUB のナビゲーション文書、HTML の目次のページと同じ規則になり、InDesign も目次スタイルからしおりを作る。
   - 退けた案の一つは、`@notoc` のない見出しをすべて、`@toc` の深さによらず載せることである。目次としおりの深さが食い違い、[golem-epub ADR 0002](../golem-epub/adr/0002-nav-and-toc-depth.md) が直した食い違いを PDF で作り直すことになる。
   - もう一つは、`@notoc` の見出しも載せることである。`@notoc` は目次の機能に載せないための指定で、しおりも目次の機能である。
2. **しおりの開閉の既定**：推奨は、子を持つ項目をすべて閉じることである。開いたときに最上位の項目が一画面に並び、章の数が多い本でも目次として読める。hyperref の既定と同じである。
   - 退けた案は、すべて開くことである。節の多い本では、しおりのパネルが長い一覧になる。開く階層を `style.toml` で指定させる案は、欄を一つ増やすので、求める例が出てから考える。
3. **しおりのパネルを開いて表示するか**：推奨は、しおりがあれば `/PageMode /UseOutlines` を書くことである。しおりがあることに読み手が気付く。hyperref も、しおりがあれば既定でこう書く。
   - 退けた案は書かないことである。多くの閲覧ソフトはパネルを閉じて開き、しおりがあることに気付かれない。
4. **行先の形**：推奨は、注釈の `/Dest` に明示した `[p 0 R /XYZ null t null]` を書くことである。オブジェクトが増えず、行先の値はページと座標だけで決まる。
   - 退けた案の一つは、名前の付いた行先（カタログの `/Names` の `/Dests` の名前の木）である。名前の順に並べれば決定的にできるが、名前の木の分だけ大きくなり、ラベルのない行先（注、索引の印）に名前を作る規則が別に要る。
   - もう一つは、`/A << /S /GoTo /D [...] >>` のアクションである。同じ行先を辞書一つ分だけ大きく書く。
   - もう一つは、`/Fit`（ページの全体）である。座標が要らないが、行先の行がページのどこにあるかを読み手が探すことになる。
5. **リンクにするもの**：推奨は「リンクにするもの」の表のとおりで、ロードマップの四つ（相互参照、目次、索引、脚注の印）に、章末の注の印と `[cite]` から参考文献へのリンクを足す。どちらも HTML と EPUB がすでにリンクにしており、PDF だけがリンクを持たない理由がない。hyperref も引用をリンクにする。
   - 退けた案は、ロードマップの四つに限ることである。媒体ごとにリンクの有無が食い違う。
6. **注から本文の印へ戻るリンク**：推奨は作ることである。章末の注は印と別のページにあり、戻る手段がないと読み手はページをめくって印を探す。HTML も戻るリンクを持つ。
   - 退けた案は、印から注への片道だけにすることである。脚注では困らないが、章末の注で困る。
7. **HTML と EPUB の `[ref-number]` と `[ref-title]`**：推奨は、この ADR で `<a href>` にすることである。行先はすでに `[ref-page]` が使うラベルの行先で、`Resolved` がラベルを持つので IR を変えずに済む。PDF だけがリンクになると、媒体の食い違いが逆向きに残る。
   - 退けた案は、[ADR 0215](0215-ref-number-and-ref-title-as-reference.md) のとおり別の ADR に残すことである。小さな変更のために ADR を一つ増やす。
8. **内部の注釈の `/Contents`**：推奨は、リンクの元の描いた文字とすることである。外部のリンクの `/Contents` が、プレーンテキストで書く文字であるのと同じ考え方で、追加の文言を作らない。
   - 退けた案は、行先を説明する文（「第 2 章へ」「12 ページの注 3 へ」）を作ることである。文言の言語と書式を新しく決めることになる。
9. **リンクの元の入れ子**：推奨は、外側のリンクだけを作ることである。矩形が重ならないので、閲覧ソフトがどちらのリンクを選ぶかで振る舞いが変わらない。
   - 退けた案は、内側のリンクを優先し、外側の矩形から内側の部分を除くことである。目次の項目のリンクが一行の中で途切れ、クリックできない隙間ができる。
10. **ロードマップの「リンクのほかの注釈」**：推奨は、項目を消し、リンクのほかの注釈を作らないことを「課題にしなかった事項」に理由とともに書くことである（「実装しないこと」の最初の項目）。
    - 退けた案は、v2 に項目を残すことである。使う場面が書かれていない項目を残すと、いつ着手するかを決められない。

## 決めたことの記録

2026-11-09 に、tett23 がすべて推奨のとおりに決めた。

1. しおりに載せる見出しは、推奨のとおり `tocWithinDepth` とする。
2. しおりは、推奨のとおり子を持つ項目をすべて閉じて書く。
3. 推奨のとおり、しおりがあれば `/PageMode /UseOutlines` を書く。
4. 行先は、推奨のとおり注釈の `/Dest` に明示した `[p 0 R /XYZ null t null]` を書く。
5. リンクにするものは、推奨のとおり「リンクにするもの」の表のとおりとする。
6. 注から本文の印へ戻るリンクは、推奨のとおり作る。
7. HTML と EPUB の `[ref-number]` と `[ref-title]` は、推奨のとおりこの ADR で `<a href>` にする。
8. 内部の注釈の `/Contents` は、推奨のとおりリンクの元の描いた文字とする。
9. リンクの元が入れ子になれば、推奨のとおり外側のリンクだけを作る。
10. ロードマップの「リンクのほかの注釈」は、推奨のとおり項目を消し、作らない理由を「課題にしなかった事項」に書く。

diagnostic のコードは、採択のときに、docs/diagnostics.md と origin/main のコードで使われていない番号であり、同じ時期の ADR と重ならないことを確かめて、G07120 とした。
草案の仮の番号から振り直した。

## 参考文献

- [2026-10-17 の調査](../audits/2026-10-17-latex-gap-for-v1.md) の 5 と「所有者の決定」
- [ADR 0182](0182-external-links.md)、[ADR 0183](0183-tagged-pdf-and-pdf-a.md)、[ADR 0215](0215-ref-number-and-ref-title-as-reference.md)、[ADR 0216](0216-drawn-content-missing-from-the-structure-tree-is-an-error.md)、[ADR 0221](0221-check-iso-15930-7-for-link-annotations-before-rc4.md)、[ADR 0226](0226-move-the-iso-15930-7-check-to-before-v1.md)
- [golem-pdf ADR 0001](../golem-pdf/adr/0001-deterministic-pdf-writer.md)、[golem-epub ADR 0002](../golem-epub/adr/0002-nav-and-toc-depth.md)、[golem-html ADR 0003](../golem-html/adr/0003-cite-links-across-files.md)、[golem-driver ADR 0007](../golem-driver/adr/0007-pdf-index-and-bibliography.md)、[golem-driver ADR 0009](../golem-driver/adr/0009-pdf-toc-page-numbers.md)、[golem-driver ADR 0026](../golem-driver/adr/0026-chapter-end-notes.md)
- ISO 32000-1:2008 の 12.3.2（行先）、12.3.3（文書のアウトライン）、12.5.6.5（リンクの注釈）、14.8.4.3 の表 333（`TOCI` と `Reference`）
- ISO 14289-1:2014（PDF/UA-1）の 7.18.1、7.18.5。[ADR 0183](0183-tagged-pdf-and-pdf-a.md) と同じく veraPDF の検証プロファイルの記述で読んだ
- Adobe, InDesign User Guide。本文は読めず、調査が検索の抜粋で確かめたことだけに拠る。しおりの開閉の既定と行先の形は確かめていない
  - しおり: https://helpx.adobe.com/indesign/desktop/indexes-and-references/references-and-bookmarks/create-bookmarks.html
  - 目次からのしおり: https://helpx.adobe.com/indesign/desktop/indexes-and-references/add-a-table-of-contents/add-interactivity-to-tocs.html
  - 相互参照: https://helpx.adobe.com/indesign/using/cross-references.html
  - PDF の書き出しの設定: https://helpx.adobe.com/in/indesign/using/pdf-options.html
- CTAN の hyperref と bookmark。`bookmarksopen` と `pdfpagemode` の既定は、パッケージの説明書の記述として書き、この ADR で読み直してはいない
  - hyperref: https://ctan.org/pkg/hyperref
  - bookmark: https://ctan.org/pkg/bookmark
- W3C, Requirements for Japanese Text Layout（JLReq）, https://www.w3.org/TR/jlreq/ 。PDF のしおりとリンクの定めはない
