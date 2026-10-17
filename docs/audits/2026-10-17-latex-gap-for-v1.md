# v1.0.0 までに埋める LaTeX との差（2026-10-17）

この記録は、v0.1.0-rc4 と v1.0.0 で、数式の組版を除いて LaTeX に比べて Golem に足りない機能を埋めるという方針のための調査である。
2026-10-17 の main（dcc1e54）の Golem を対象にした。
前の調査（[2026-10-16 の TeX との比較](2026-10-16-tex-feature-gap.md)）の後に、多くの不足が v0.1.0-rc3 と v0.1.0-rc4 の項目になった。
この記録は、その後に残る不足だけを扱う。

各項目について、Golem の今、InDesign の振る舞い、LaTeX の振る舞い、Golem の目的にとっての重要度、提案する版を書く。
InDesign を先に、LaTeX を後に書くのは、仕様を決める順を「まず InDesign の振る舞いを調べ、確かめられない場合に限り TeX の仕様に従う」とした所有者の規則による（[仕様書の「仕様が不明瞭な場合」](../specifications.md#仕様が不明瞭な場合)）。

## 調べ方

Golem の今は、仕様書（[docs/specifications.md](../specifications.md)）と言語仕様（[docs/markup.md](../markup.md)）を読み、コードで確かめた。
確かめたコードの場所は各項目に書く。

計画済みのものは、[docs/roadmap.md](../roadmap.md) の v0.1.0-rc3、v0.1.0-rc4、v1.0.0 の項目と、まだコミットしていない v0.1.0-rc3 の ADR の草稿（docs/adr/0029 から 0033、`golem-driver/adr/0025` から 0032、`golem-layout/adr/0013` から 0017、`golem-pdf/adr/0008` と 0009 ほか）とした。
草稿は採択されていないが、この記録では実装される予定のものとして扱い、不足に数えない。

InDesign の振る舞いは、Adobe のヘルプ（helpx.adobe.com）で確かめた。
helpx.adobe.com は自動の取得を拒んだ（HTTP 403）ので、ページの本文は読めず、検索の結果に出たページの抜粋で確かめた。
各項目の URL は、その抜粋が出たページである。
抜粋で確かめられなかったことは、確かめられなかったと書く。

LaTeX の振る舞いは、CTAN のパッケージのページと、LaTeX のカーネルの命令の参照（LaTeX2e unofficial reference manual）で示す。
LaTeX の側は既知の事実として書き、この調査で本文を読み直してはいない。

重要度は、前の調査と同じく、和文の書籍、CI で組む本、InDesign の置き換えという Golem の目的にとっての重要度を、高、中、低で表す。

## 前の調査から計画に入ったもの

前の調査が挙げた不足のうち、次のものは計画に入ったので、この記録では扱わない。

| 前の調査の不足 | 今の計画 |
| --- | --- |
| 改ページの手での制御 | rc3 の草稿 docs/adr/0030（`@no-page-break`、`@need-lines`、`@page-lines`） |
| PDF と SVG の図版、置けない図版 | rc3 の草稿 `golem-pdf/adr/0008`、`golem-pdf/adr/0009` |
| 合字のテキスト層 | rc3 の草稿 `golem-driver/adr/0030` |
| 書体にない字の報告 | rc4 の「書体にない字」 |
| 章末の注、注の印の書式 | rc3 の草稿 `golem-driver/adr/0025`、`golem-driver/adr/0026`、rc4 の「注の印の文字スタイル」 |
| 段落の罫線、罫線の色と種類 | rc3 の草稿 `golem-driver/adr/0027`、`golem-driver/adr/0028` |
| 本文の中のコードの背景 | rc3 の草稿 `golem-driver/adr/0029` |
| 表の前後の空き | rc3 の草稿 `golem-driver/adr/0031` |
| 既定の見出し、見出しの行取りの行数 | rc3 の草稿 `golem-driver/adr/0032` |
| 図版の順序、見出しの脚注 | rc3 の草稿 `golem-layout/adr/0015`、`golem-layout/adr/0017` |
| 書誌の項目 | rc3 の草稿 `golem-doc/adr/0005` |
| 参考文献のスタイル | v1.0.0 の「参考文献のスタイル」 |
| 外部の URL のリンク | rc4 の「PDF のリンク」 |
| タグ付き PDF、PDF/A | rc4 の「タグ付き PDF と PDF/A」 |
| 原稿の中の言語の切り替えと分綴 | rc4 の「原稿の中の言語の切り替え」、v1.0.0 の「本の中の別の言語の分綴」 |
| 見出しの 4 階層め以降 | rc4 の「見出しの 4 階層め以降」 |

草稿は main にないので、この記録では草稿へのリンクを張らず、パスだけを書く。

## 要約

v0.1.0-rc4 に 4 項目、v1.0.0 に 13 項目を提案する。
ほかの不足は、v2 以降のままにするか、新しく後の版に置くことを提案する。

| 番号 | 不足 | Golem の今 | InDesign | LaTeX | 重要度 | 提案 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 段落の行揃え | 両端揃えだけ | 段落パネルの行揃え | `\centering`、`flushright`、ragged2e | 高 | rc4 |
| 2 | 段落の前後のアキ | `space-between` だけ | 段落前のアキ、段落後のアキ | `\vspace`、`\addvspace`、titlesec | 高 | rc4 |
| 3 | 行の終わりの側の字下げ | 行の始まりの側だけ | 右インデント | `quote`、`\rightskip` | 中 | rc4 |
| 4 | 回り込ませない図版の幅 | 行長に固定し、`width` を黙って無視する | フレームの大きさと内容の合わせ方 | `\includegraphics[width=...]` | 高 | rc4 |
| 5 | PDF のしおりと文書の中のリンク | どちらもない | しおりのパネル、目次からのしおり、相互参照のリンク | hyperref、bookmark | 高 | v1.0.0 |
| 6 | 前付けのノンブルとページラベル | 通し番号だけ | セクションの開始、ノンブルの様式 | `\frontmatter`、`\pagenumbering` | 中〜高 | v1.0.0 |
| 7 | 段落スタイルの分割禁止と連動 | 固定の規則と原稿の印だけ | 段落の分割禁止オプション | `\nopagebreak`、needspace | 中〜高 | v1.0.0 |
| 8 | 表の番号とキャプション、列の幅、文字の大きさ | どれもない | 表のキャプション、列の幅、表スタイル | caption、tabularx | 中〜高 | v1.0.0 |
| 9 | 複数段落の注 | 一段落だけ | 複数の段落を持つ脚注 | `\footnote` の中の `\par` | 中 | v1.0.0 |
| 10 | 目次の項目の書式 | 字下げとリーダーの有無だけ | 目次スタイルの項目のスタイル | tocloft、titletoc | 中 | v1.0.0 |
| 11 | 索引の参照、範囲、見出し | 二段の項目とページだけ | 「を見よ」「をも見よ」、範囲、見出し | makeindex、upmendex | 中 | v1.0.0 |
| 12 | 引用の頁の指定と複数の文献 | キー一つだけ | 組み込みの機能なし | `\cite[p.~5]{a,b}`、biblatex | 中 | v1.0.0 |
| 13 | 下線と打ち消し線 | なし | 下線、打ち消し線とそのオプション | ulem、soul、lua-ul | 中 | v1.0.0 |
| 14 | 上付きと下付き | 文字スタイルで近似だけ | 上付き文字、下付き文字 | `\textsuperscript`、realscripts | 中 | v1.0.0 |
| 15 | 文字スタイルの OpenType の機能 | 書体の役割の `features` だけ | 文字パネルの OpenType の機能 | fontspec の `\addfontfeatures` | 中 | v1.0.0 |
| 16 | 段落の背景と囲み罫 | コードブロックだけ | 段落の囲み罫と背景色 | tcolorbox、mdframed | 中 | v1.0.0 |
| 17 | 任意ハイフン、分綴の例外、分離禁止 | どれもない | 任意ハイフン、ユーザー辞書、分離禁止 | `\-`、`\hyphenation`、`\mbox` | 中 | v1.0.0 |

## v0.1.0-rc4 に提案するもの

rc4 には、扉、献辞、引用、奥付、図版の大きさといった、ふつうの本の数ページで必ず出会う不足を置く。
どれも段落スタイルか図版の既存の欄を広げる変更で、意味論 IR を大きく変えない。

### 1. 段落の行揃え

Golem の今は、段落を両端揃えでしか組めない。
段落スタイルの欄（`modules/golem-project/src/Golem/Project/Style.hs` の `ParaStyleDef`）に行揃えの欄がない。
揃えは表のセルにだけある（`Golem.Doc.IR` の `Table [Alignment] ...`）。
扉、献辞、エピグラフ、署名、奥付を、中央揃えや地付きで組めない。

InDesign は、段落パネルで左揃え、中央揃え、右揃え、均等配置（最終行を左、中央、右に揃える）、両端揃え（全行を揃える）を選べる。
ノド側に揃える、小口側に揃えるという指定もあり、縦組みのフレームではこの二つは効かない。
出典は https://helpx.adobe.com/indesign/using/aligning-text.html である。

LaTeX は、`\centering`、`\raggedright`、`\raggedleft` の宣言と、`center`、`flushleft`、`flushright` の環境で揃えを変える（https://latexref.xyz/ の「center」「flushright」）。
ragged2e パッケージ（https://ctan.org/pkg/ragged2e）は、行末を揃えない組みでもハイフネーションを許す版を加える。

重要度は高い。
扉と奥付は本のほぼすべてにあり、今は組めないからである。

提案は rc4 である。
v2 の「段落スタイルの拡張」の行揃えを先に取り出す。
値の名前は InDesign の行揃えに合わせ、縦組みでは天付き、中央、地付きと読む。
ノド側と小口側の揃えは、見開きの左右を知る必要があるので、rc4 では作らず ADR で決める。

### 2. 段落の前後のアキ

Golem の今は、同じ段落スタイルの段落が続くときの `space-between` しかない（`ParaStyleDef` の `psSpaceBetween`）。
`space-before` の欄は脚注の区切り線の罫線の指定（`Golem.Project.Style`）にだけある。
rc3 の草稿の `golem-driver/adr/0027` は、段落の前後の空きを罫線なしで書くことを「実装しないこと」に挙げている。
韻文の後に空きがない不具合（rc4 の「韻文の後の空き」）も、この欄があれば設定で表せる。

InDesign は、段落パネルと段落スタイルに段落前のアキと段落後のアキを持つ。
同じスタイルの段落のあいだのアキ（Golem の `space-between` にあたるもの）は、二つの段落が同じスタイルのときだけ効き、ほかのときは段落前と段落後のアキを使う。
段落前のアキは、段やフレームの先頭では効かない。
出典は https://helpx.adobe.com/in/indesign/using/formatting-paragraphs.html である。
ベースライングリッドに揃える段落では、行は格子に載る（https://helpx.adobe.com/indesign/desktop/layout-and-grid-tools/grids/use-a-baseline-grid.html）。

LaTeX は、`\vspace` と `\addvspace` で任意の縦の空きを置き、見出しの前後の空きは titlesec の `\titlespacing`（https://ctan.org/pkg/titlesec）で決める。
段落のあいだの空きは `\parskip` である。

重要度は高い。
引用、韻文、見出しのまわりの空きは本の読みやすさを決め、今は空の段落でしか作れないからである。

提案は rc4 である。
v2 の「段落スタイルの拡張」の段落の前後の空きを先に取り出す。
単位は `space-between` と同じく行の数にし、行の格子を崩さない。
段の先頭で段落前のアキを捨てるかは、InDesign に合わせて捨てる案を ADR で検討する。
原稿に任意の空きを置く記法（`\vspace` にあたるもの）は InDesign にないので、この項目では作らない。

### 3. 行の終わりの側の字下げ

Golem の今は、行の始まりの側の `indent` と `first-line-indent` しかない（`ParaStyleDef` の `psIndent`、`psFirstLineIndent`）。
引用を両側から字下げして組めない。

InDesign は、左インデント、右インデント、一行目左インデントのほかに、最終行右インデントを持つ。
出典は https://helpx.adobe.com/indesign/desktop/format-and-style-text/tabs-indents-and-spacing/set-indents.html と https://helpx.adobe.com/in/indesign/using/formatting-paragraphs.html である。

LaTeX は、`quote` と `quotation` の環境が両側を字下げし、`\leftskip` と `\rightskip` で任意の量を指定する（https://latexref.xyz/ の「quotation and quote」）。

重要度は中である。

提案は rc4 である。
1 と 2 と同じく段落スタイルの欄であり、同じ ADR で決められるからである。
最終行右インデントは作らない。

### 4. 回り込ませない図版の幅

Golem の今は、回り込ませない図版を版面の行長の幅に固定する（仕様書の「図版」の節）。
`@figure` の `width` は評価で読み、`Figure` の `figWidth` に入るが（`modules/golem-eval/src/Golem/Eval/File.hs`）、PDF の `placeFigure`（`modules/golem-driver/src/Golem/Driver/Pdf.hs`）は回り込ませない図版では `width` を見ない。
回り込ませない図版に `width` を書いても、診断なしに無視される。
小さな図や縦長の図も行長まで引き伸ばされる。

InDesign は、図版をフレームに置き、フレームの大きさと、内容をフレームに合わせる方法（内容を縦横比を保って合わせる、フレームを埋めるなど）を選ぶ。
出典は https://helpx.adobe.com/indesign/desktop/add-graphics-and-media/manage-frames-and-objects/fit-object-to-frame.html である。
本文に固定した図版（アンカー付きオブジェクト）も、大きさを変えると位置の設定が保たれる（https://helpx.adobe.com/indesign/desktop/add-graphics-and-media/transform-and-arrange-objects/create-position-anchored-objects.html）。

LaTeX は、graphicx の `\includegraphics` の `width`、`height`、`scale`、`keepaspectratio` で大きさを決める（https://ctan.org/pkg/graphicx）。

重要度は高い。
技術書と画集のどちらでも、図をすべて行長で置く本はないからである。

提案は rc4 である。
v2 の「図版とキャプションの拡張」の「回り込ませない図版の幅の指定」を先に取り出す。
すでに `width` を読んで黙って捨てているので、仕様と実装の食い違いを直す意味もある。
図版を行のどちらに寄せるかと、行長より大きい図版の縮小は、この項目で合わせて決める。

## v1.0.0 に提案するもの

v1.0.0 には、InDesign で本を作る人が当然に使う機能と、原稿の記法、意味論 IR、プラグインの ABI を変える機能を置く。
仕様書の「版」の節のとおり、1.0.0 までは互換を壊す変更で `Y` を上げればよいが、1.0.0 の後は互換を壊す変更の費用が上がる。
記法と IR を変える機能は、1.0.0 より前に入れたほうが安い。

### 5. PDF のしおりと文書の中のリンク

Golem の今は、PDF にアウトライン（`/Outlines`）も注釈（`/Annots`）も書かない。
`modules` の Haskell のコードに、どちらの名前も出てこない。
rc4 の「PDF のリンク」は外部の URL の記法とリンクの注釈を扱い、相互参照のリンクとしおりは v2 の「PDF のしおりとリンク」に残っている。

InDesign は、しおりのパネルでしおりを作り、目次を作るときの「PDF のしおりを作成」の設定で、目次の項目をしおりにする。
出典は https://helpx.adobe.com/indesign/desktop/indexes-and-references/references-and-bookmarks/create-bookmarks.html と https://helpx.adobe.com/indesign/desktop/indexes-and-references/add-a-table-of-contents/add-interactivity-to-tocs.html である。
相互参照は、PDF の書き出しでハイパーリンクを選ぶと PDF のリンクになる（https://helpx.adobe.com/indesign/using/cross-references.html）。
書き出しのハイパーリンクの設定は、ハイパーリンク、目次の項目、索引の項目を PDF のリンクの注釈にする（https://helpx.adobe.com/in/indesign/using/pdf-options.html）。

LaTeX は、hyperref（https://ctan.org/pkg/hyperref）が相互参照、目次、脚注、引用をリンクにし、見出しからしおりを作る。
bookmark（https://ctan.org/pkg/bookmark）はしおりの書き方を改める。

重要度は高い。
CI で組んだ PDF をそのまま電子版として配る使い方では、しおりとリンクのない PDF は見劣りするからである。

提案は v1.0.0 である。
v2 の「PDF のしおりとリンク」のうち、見出しからのしおりと、相互参照、目次、索引、脚注の印のリンクを先に取り出す。
rc4 の「PDF のリンク」でリンクの注釈を書く仕組みができるので、その後に続けるのが安い。
注釈と決定性の関係（注釈の辞書の順序）は ADR で決める。

### 6. 前付けのノンブルとページラベル

Golem の今は、ノンブルが本の通し番号だけである。
`/PageLabels` を書くコードはない。
v2 の「ページ番号と柱の拡張」に、前付けのローマ数字のノンブルと振り直しがある。

InDesign は、ページを選んでセクションを開始し、セクションごとにノンブルの開始の番号と様式（ローマ数字など）と接頭辞を決める。
前付けをローマ数字、本文をアラビア数字にする例を、Adobe 自身が挙げている。
出典は https://helpx.adobe.com/indesign/desktop/create-and-organize-pages/page-numbers-chapters-and-sections/document-numbering-options.html である。
PDF に書き出したときにセクションのノンブルがページラベルになるかは、抜粋では確かめられなかった。

LaTeX は、book クラスの `\frontmatter`、`\mainmatter`、`\backmatter` と、`\pagenumbering{roman}` でノンブルの様式を変え、番号を振り直す（https://latexref.xyz/ の「\pagenumbering」）。
hyperref の `pdfpagelabels` は、ノンブルをページラベルとして PDF に書く（https://ctan.org/pkg/hyperref）。

重要度は中〜高である。
欧文の本と学術書では前付けのローマ数字は当然であり、和文の本でも前付けを別のノンブルにすることがあるからである。

提案は v1.0.0 である。
v2 の「ページ番号と柱の拡張」のうち、ノンブルの様式と振り直しとページラベルだけを先に取り出す。
目次、索引、相互参照のページ番号にも同じ書式を使うので、ページ番号の値の表し方（数の抽象値との関係）を変える。
これは意味論 IR の参照の値に関わるので、1.0.0 の前に決める。

### 7. 段落スタイルの分割禁止と連動

Golem の今は、段落の最初と最後の行を一行だけ残さない固定の規則と、見出しを後の内容と離さない規則しかない（[golem-layout ADR 0003](../golem-layout/adr/0003-pagination-and-s2.md)）。
rc3 の草稿 docs/adr/0030 は、原稿の一か所に置く印（`@no-page-break` など）を加えるが、段落スタイルに書く欄は加えない。
v2 の「韻文の拡張」の「連をページで分けない指定」と、v2 の「孤立行の規則の見直し」が関係する。

InDesign は、段落の分割禁止オプションとして、次の段落と連動（後の段落の最大 5 行まで）、前の段落と連動、段落を分割しない（すべての行、または段落の始めと終わりの行数）、段落の開始位置（次の段、次のページ、次の奇数ページなど）を持ち、段落スタイルに書ける。
出典は https://helpx.adobe.com/indesign/desktop/format-and-style-text/composition-and-text-wrapping/paragraph-break-options-in-indesign.html である。

LaTeX は、段落ごとの指定を持たず、`\nopagebreak`、`\samepage`、needspace（https://ctan.org/pkg/needspace）を原稿に書くか、`\widowpenalty` と `\clubpenalty` で本の全体の罰則を変える。

重要度は中〜高である。
連、見出しに準ずる段落、表の前の説明の段落を、一か所ずつ印を置かずにスタイルで守れるからである。

提案は v1.0.0 である。
InDesign の方式（段落スタイルの欄）を採り、rc3 の草稿 docs/adr/0030 の印と同じ改ページの仕組みで実装する。
孤立行の行数を変える欄（段落の始めと終わりの行数）は、v2 の「孤立行の規則の見直し」と重なるので、この項目に入れるかを ADR で決める。
段落の開始位置は、見出しの `page-break` と同じ意味を段落に広げる形にする。

### 8. 表の番号とキャプション、列の幅、文字の大きさ

Golem の今は、表に番号もキャプションもなく、列の幅は自動だけで、セルを本文と同じ書体と大きさで組む。
意味論 IR の表は `Table [Alignment] [[Inline]] [[[Inline]]]` で、揃えと見出しの行と本体の行しか持たない（`Golem.Doc.IR`）。
v2 の「表の拡張」にこれらがある。

InDesign は、表の設定のキャプションで、表の上か下にキャプションを置く（https://helpx.adobe.com/indesign/desktop/add-tables-and-data/create-tables/add-content-to-a-table.html）。
図と表の番号は、リストを定義してキャプションの段落スタイルに含める「通し番号のキャプション」で振る（https://helpx.adobe.com/indesign/desktop/format-and-style-text/lists-and-numbering/create-running-captions.html）。
列の幅はセルの設定か列の境のドラッグで決める（https://helpx.adobe.com/indesign/desktop/add-tables-and-data/format-tables/resize-columns-rows-and-tables.html）。
表スタイルとセルスタイルが、罫、塗り、セルの中の段落スタイルをまとめる（https://helpx.adobe.com/indesign/using/table-cell-styles.html）。

LaTeX は、`table` の浮動体の `\caption` で番号とキャプションを付け、caption（https://ctan.org/pkg/caption）で書式を変える。
列の幅は `p{...}` の列と tabularx（https://ctan.org/pkg/tabularx）で決め、文字の大きさは表の中の `\small` などで変える。

重要度は中〜高である。
技術書と学術書は表を番号で参照し、本文より小さい文字の表が多いからである。

提案は v1.0.0 である。
v2 の「表の拡張」のうち、表の番号とキャプション、列の幅の指定、表の文字の大きさ（段落スタイルの適用）を先に取り出す。
表に番号を持たせることは意味論 IR と相互参照（`[ref-number]`）に関わるので、1.0.0 の前に決める。
セルの結合は、後の「後の版に置くもの」で扱う。

### 9. 複数段落の注

Golem の今は、注の本文がインラインの要素に限られる（`Golem.Doc.IR` の `Note !SrcSpan !Int [InlineF r]`）。
v2 に「複数段落の注」がある。

InDesign の脚注は複数の段落を持て、脚注の段落の段落前と段落後のアキは、複数の段落を持つ脚注でだけ効く。
出典は https://helpx.adobe.com/uk/indesign/using/footnotes.html と https://helpx.adobe.com/indesign/desktop/indexes-and-references/footnotes-and-endnotes/change-footnote-numbering-and-layout-options.html である。

LaTeX は、`\footnote` の引数の中で `\par` か空行を書けば段落を分けられる（https://latexref.xyz/ の「\footnote」）。

重要度は中である。
学術書と翻訳書の訳注は複数の段落になることがあるからである。

提案は v1.0.0 である。
注の本文の型をインラインからブロックに変えるので、意味論 IR、CDDL、プラグインの ABI が変わる。
互換を壊す変更なので、1.0.0 の前に入れる。
この項目を採るなら、v2 の「複数段落の注」はこの項目に置き換わる。

### 10. 目次の項目の書式

Golem の今は、`@toc depth=N` で載せる深さを選び、`[toc]` の `leader` でリーダーの有無を選ぶだけである（仕様書の「目次と文書構造の参照」の節）。
階層ごとの書体、大きさ、字下げ、空きは選べない。
v2 の「目次の拡張」にこれらがある。

InDesign は、目次スタイルで、目次に載せる段落スタイルごとに項目のスタイル（段落スタイル）、レベル、ページ番号の位置と文字スタイル、項目とページ番号のあいだの文字を決める。
リーダーは、項目のスタイルのタブのリーダーで描く。
出典は https://helpx.adobe.com/indesign/desktop/indexes-and-references/add-a-table-of-contents/customize-toc-style.html である。
図目次は、別の目次スタイルで別の目次を作って組む（https://helpx.adobe.com/be_en/indesign/desktop/indexes-and-references/add-a-table-of-contents/create-multiple-tocs.html）。

LaTeX は、tocloft（https://ctan.org/pkg/tocloft）と titletoc（https://ctan.org/pkg/titletoc）で、階層ごとの書体、字下げ、リーダーを決める。
図目次と表目次は `\listoffigures` と `\listoftables` である。

重要度は中である。
目次は本の顔の一つで、今は本文と同じ書体と大きさでしか組めないからである。

提案は v1.0.0 である。
v2 の「目次の拡張」のうち、階層ごとに段落スタイルを当てることだけを先に取り出す。
InDesign の方式（目次の項目に段落スタイルを当てる）にすれば、新しい欄は階層と段落スタイルの対応だけで済む。
図目次、表目次、章ごとの小目次は v2 に残す。

### 11. 索引の参照、ページの範囲、見出し

Golem の今は、索引の項目が二段までで、項目のあいだの参照も、ページの範囲も、行の見出し（「あ」「か」）もない（`Golem.Doc.IR` の `IndexEntry` は語と読みの列だけを持つ）。
v2 の「索引と参考文献の拡張」にこれらがある。

InDesign は、索引の項目の種類に「を見よ」「をも見よ」の参照と、次のスタイルの変更まで、文書の終わりまでといったページの範囲を持つ。
ページを持つ項目には「をも見よ」、持たない項目には「を見よ」を自動で選ぶ。
索引を作るときに、アルファベットなどの見出しを入れるかを選び、レベルごとにスタイルを決める。
出典は https://helpx.adobe.com/indesign/using/creating-index.html と https://helpx.adobe.com/indesign/desktop/indexes-and-references/create-an-index/index-formatting-options.html である。

LaTeX は、makeindex と、和文を扱う upmendex（https://ctan.org/pkg/upmendex）で、`!` による三段の階層、`|see{...}` と `|seealso{...}` の参照、`|(` と `|)` の範囲を書き、索引のスタイルファイルで見出しを入れる。

重要度は中である。
学術書の索引では、参照と行の見出しのない索引は不完全とされるからである。

提案は v1.0.0 である。
v2 の「索引と参考文献の拡張」のうち、「を見よ」「をも見よ」、ページの範囲、行の見出しを先に取り出す。
参照と範囲は `[index]` の記法と `IndexEntry` の型を変えるので、1.0.0 の前に決める。
三段以上の階層と、縦組みの本の索引を横組みにすることは v2 に残す。

### 12. 引用の頁の指定と複数の文献

Golem の今は、`[cite]` がキーを一つだけ取り、頁を書けない（`Golem.Doc.IR` の `Cite !SrcSpan !Text`）。
どの一覧にも載っていない。

InDesign のヘルプに、引用と参考文献を組む組み込みの機能の記載は見つからなかった。
InDesign の振る舞いを確かめられないので、所有者の規則により TeX に従う。

LaTeX は、`\cite[p.~5]{knuth1981}` のように任意の引数で頁を書き、`\cite{a,b}` で複数の文献を一度に引く（https://latexref.xyz/ の「\cite」）。
biblatex（https://ctan.org/pkg/biblatex）は、前置きと後置きの文言と、`\cites` による文献ごとの頁を加える。

重要度は中である。
学術書では頁のない引用はほとんど使えないからである。

提案は v1.0.0 である。
v1.0.0 の「参考文献のスタイル」は引用の書式（番号か著者と年か）を変えるので、引用が持つ値（頁、複数の文献）を先に決めておく必要がある。
記法を変えるので、1.0.0 の前に入れる。

### 13. 下線と打ち消し線

Golem の今は、下線も打ち消し線もない。
文字スタイルの欄は `based-on`、`font`、`size`、`color`、`synthetic-bold`、`synthetic-italic` と文字の送りの四つだけである（仕様書の「style.toml」の節）。
v2 の「和文組版の拡張」に傍線がある。

InDesign は、文字パネルと文字スタイルで下線と打ち消し線を付け、それぞれのオプションで線の太さ、種類、位置（オフセット）、色を決める。
出典は https://helpx.adobe.com/ca/indesign/using/formatting-characters.html である。
縦組みで下線が字の右に出るか（傍線になるか）は、この調査では確かめられなかった。

LaTeX は、ulem（https://ctan.org/pkg/ulem）の `\uline` と `\sout`、soul（https://ctan.org/pkg/soul）の `\ul` と `\st`、LuaLaTeX の lua-ul（https://ctan.org/pkg/lua-ul）で下線と打ち消し線を引く。

重要度は中である。
法令の新旧対照、教科書、校正の版で使い、和文では傍線として要るからである。

提案は v1.0.0 である。
文字スタイルの欄を加える変更で、罫線の指定（[golem-driver ADR 0024](../golem-driver/adr/0024-rule-spec-and-footnote-separator.md) と rc3 の草稿の色と種類）を線の書き方に使える。
縦組みでの線の側は、InDesign の振る舞いを実際に確かめてから ADR で決める。
v2 の「和文組版の拡張」の傍線はこの項目に含まれることになる。

### 14. 上付きと下付き

Golem の今は、上付きと下付きの組み込みの文字スタイルがない。
文字スタイルの `size` と `baseline-shift` で近似はできるが、HTML と EPUB は `<sup>` と `<sub>` にならず、書体の上付きの字形も使わない。
v2 の「和文組版の拡張」に添え字がある。

InDesign は、文字パネルの上付き文字と下付き文字を持ち、OpenType の機能のない書体では、環境設定の詳細設定の大きさと位置の比で文字を縮めてずらす。
OpenType の書体では、上付き序数表記と下付き序数表記の機能も選べる。
出典は https://helpx.adobe.com/ca/indesign/using/formatting-characters.html と https://helpx.adobe.com/indesign/desktop/fonts/opentype-font-attributes.html である。

LaTeX は、カーネルの `\textsuperscript` と `\textsubscript` で文字を縮めて上げ下げし、realscripts（https://ctan.org/pkg/realscripts）は fontspec の書体の上付きと下付きの字形を使う。

重要度は中である。
単位（m²）、化学式、序数、注の番号のような字に要るからである。

提案は v1.0.0 である。
組み込みの文字スタイル `superscript` と `subscript` を加え、InDesign と同じく、書体の機能があればそれを使い、なければ大きさと位置で近似する。
既定の比は InDesign の既定の値を確かめて決める。
15 の OpenType の機能と同じ ADR で扱うのがよい。

### 15. 文字スタイルの OpenType の機能

Golem の今は、OpenType の機能を書体の役割ごとの `features` でしか指定できない（仕様書の「フォント」の節）。
文字スタイルから機能を足せないので、スモールキャップや分数のために役割を一つ増やして書く必要がある。

InDesign は、文字パネルのメニューで、分数、上付き序数表記、スワッシュ字形、スモールキャップ、数字の形式（オールドスタイル、ライニング、等幅）、スタイルセットなどを選び、文字スタイルに保存できる。
書体にない機能は角括弧付きで表示される。
出典は https://helpx.adobe.com/indesign/desktop/fonts/opentype-font-attributes.html である。
スモールキャップは、書体にスモールキャップの字形がなければ大文字を縮めて合成する（https://helpx.adobe.com/ca/indesign/using/formatting-characters.html）。

LaTeX は、fontspec（https://ctan.org/pkg/fontspec）の `\addfontfeatures` と書体の定義の `Numbers`、`Letters`、`StyleSet` などで機能を足す。
スモールキャップは `\textsc` である。

重要度は中である。
欧文の本の略語のスモールキャップ、表の等幅の数字、和文の字形の切り替え（`jp90`、`expt` など）に要るからである。

提案は v1.0.0 である。
文字スタイルに `features` の欄を加え、外側の機能に足す形にする。
書体にない機能を指定したときの扱い（InDesign は表示するだけで組む）と、合成のスモールキャップを作るかは ADR で決める。
HTML と EPUB では `font-feature-settings` に写せる。

### 16. 段落の背景と囲み罫

Golem の今は、背景と枠をコードブロックの段落スタイル `code` にだけ書ける（`ParaStyleDef` の `psBackground`、`psPadding`、`psBorder`、`psBorderWidth`）。
型は段落スタイルの全体にあり、実装を `code` に絞っている（仕様書の「広い型、狭い実装」）。

InDesign は、段落の囲み罫と背景色の設定で、段落の上下左右の罫（太さ、種類、色、角の形）と背景の色と濃度を決め、段落スタイルに書ける。
幅を段の幅にするか文字の幅にするかを選び、同じ設定の段落が続けば一つの囲みにまとめられる。
出典は https://helpx.adobe.com/indesign/desktop/format-and-style-text/composition-and-text-wrapping/apply-paragraph-borders-and-backgrounds.html である。

LaTeX は、tcolorbox（https://ctan.org/pkg/tcolorbox）と mdframed（https://ctan.org/pkg/mdframed）で、ページをまたげる枠と背景の箱を作る。

重要度は中である。
技術書のコラム、注意書き、練習問題の囲みに使うからである。

提案は v1.0.0 である。
すでにある `code` の欄をほかの段落スタイルに開き、rc3 の草稿の段落の罫線（`golem-driver/adr/0027`）と罫線の色と種類（`golem-driver/adr/0028`）を枠に使う。
新しい型をほとんど要らないので費用が小さい。
続く段落を一つの囲みにまとめることと、囲みのページをまたぐ分割は ADR で決める。

### 17. 任意ハイフン、分綴の例外、分離禁止

Golem の今は、欧文の語の分割の位置を原稿で指定できず、本ごとの分綴の例外も書けず、改行しない範囲も指定できない。
v2 の「行分割の拡張」に、ソフトハイフンと分割の位置を指定する記法がある。
`[aki]` の前後では改行しないが、文字の範囲を分離禁止にする手段はない。

InDesign は、任意ハイフンで語を分けてよい位置を指定し、語の先頭に置けばその語を分けない。
文字パネルの分離禁止と、分割禁止ハイフンも持つ。
分綴の例外は、ユーザー辞書か文書の中の辞書に書く。
出典は https://helpx.adobe.com/indesign/desktop/format-and-style-text/composition-and-text-wrapping/control-hyphenation-and-word-breaks.html と https://helpx.adobe.com/indesign/desktop/language-and-proofing/manage-language-dictionaries/add-or-remove-words-from-dictionaries.html である。

LaTeX は、`\-` で分けてよい位置を指定し、`\hyphenation{...}` で例外を書き、`\mbox` と `~` で改行を禁じる（https://latexref.xyz/ の「\- (hyphenation)」「\hyphenation」「\mbox」）。

重要度は中である。
欧文の本では分綴の誤りを手で直す手段が要り、和文の本でも欧文の名前や型番を分けたくない場面があるからである。

提案は v1.0.0 である。
v2 の「行分割の拡張」のうち、ソフトハイフン（U+00AD）、本ごとの分綴の例外の一覧、分離禁止の文字スタイルを先に取り出す。
例外の一覧は、InDesign の文書の中の辞書にあたるものとして `style.toml` に書く案を ADR で検討する。
v1.0.0 の「本の中の別の言語の分綴」と同じ時期に扱うと、言語ごとの例外の一覧も合わせて決められる。

## 後の版に置くもの

次の不足は、v2 以降のままにするか、新しく後の版に置くことを提案する。
理由は、InDesign にない機能であること、重要度が低いこと、設計の決定が先に要ることのどれかである。

| 不足 | Golem の今 | InDesign | LaTeX | 重要度 | 提案と理由 |
| --- | --- | --- | --- | --- | --- |
| 表のセルの結合 | なし | 表のセルの結合（https://helpx.adobe.com/au/indesign/using/formatting-tables.html） | multirow、`\multicolumn` | 中〜高 | v2 のまま。CSV の表（`@table`）では結合を書けず、表の記法から作り直す必要がある。所有者の判断を求める |
| 図版の置き方（上、下、別ページ） | 出た位置か次のページの先頭 | 自動で流す浮動体はなく、アンカー付きオブジェクトの位置を指定する（https://helpx.adobe.com/indesign/desktop/add-graphics-and-media/transform-and-arrange-objects/create-position-anchored-objects.html） | float の `[htbp]`、`[H]` | 中 | v2 以降。InDesign に自動の置き方がないので、InDesign の置き換えには要らない |
| 割注 | なし | 確かめられなかった | luatexja の割注 | 中 | v2 のまま。InDesign の振る舞いを日本語版のヘルプで確かめてから決める |
| 字取り、均等割り | なし | 確かめられなかった | jlreq の `\jidori`、`\kintou` | 中 | v2 のまま。1 の行揃えの均等配置で一部は代えられる。奥付の項目名の字取りの要否は、rc3 の草稿 docs/adr/0033 の奥付と合わせて検討する |
| 脚注のページごとの番号 | 章、ファイル、本の単位 | ページ、見開き、セクションごとに振り直せる（https://helpx.adobe.com/indesign/desktop/indexes-and-references/footnotes-and-endnotes/change-footnote-numbering-and-layout-options.html） | footmisc の `perpage` | 低〜中 | 後の版。番号がページで決まるので、ページ番号の参照と同じ収束の仕組みが要る |
| 条件テキスト（版や媒体ごとの本文の出し分け） | なし | 条件テキストと条件セット（https://helpx.adobe.com/indesign/desktop/add-and-manage-text/conditional-and-variable-text/create-edit-conditional-text.html） | comment、etoolbox のトグル | 中 | 未決。媒体ごとの出し分けは媒体契約と関わるので、作るかどうかを先に決める必要がある |
| ドロップキャップ | なし | ドロップキャップ（https://helpx.adobe.com/ph_en/indesign/desktop/format-and-style-text/character-formatting/apply-drop-caps-text-positioning.html） | lettrine | 低 | v2 の「段落スタイルの拡張」のまま |
| タブとリーダー | コードブロックの中だけ | タブパネルの揃えとリーダー（https://helpx.adobe.com/uk/indesign/using/tabs-indents.html） | `tabbing`、`\dotfill` | 低 | 後の版。目次のリーダーは別にあり、1 の行揃えで扉と奥付は組める |
| リストごとの書式と前後の空き | 本に一つの `[lists]` | 段落スタイルごとの箇条書きと番号（https://helpx.adobe.com/indesign/desktop/format-and-style-text/lists-and-numbering/create-lists.html） | enumitem | 低 | 後の版。2 の段落の前後のアキをリストに当てるかは 2 の ADR で決める |
| 段抜きの見出しと段の高さの調整 | なし | 段抜きと段分割の段落の属性（※） | multicol | 中 | v2 の「段組みの拡張」と「改ページの大域の最適化」のまま |
| 同行見出し | なし | 段落スタイルの機能としては確かめられなかった | titlesec の `runin` | 低 | 後の版。rc3 の草稿 `golem-driver/adr/0032` も外している |
| 参照の文言の自動付加 | 手で書く | 相互参照の書式（https://helpx.adobe.com/indesign/using/cross-references.html） | cleveref | 低 | 後の版。`[ref-number]` の前後に文言を書けば足りる |
| 行番号 | なし | 確かめられなかった | lineno | 低 | 後の版 |
| 透かしとページの背景 | なし | マスターページに置く（※） | draftwatermark、eso-pic | 低 | v2 の「フレーム」のまま |
| 柱とノンブルのほかの欄、柱の罫 | 柱一つとノンブル一つ | マスターページに自由に置く（※） | fancyhdr | 低 | v2 の「フレーム」と「ページ番号と柱の拡張」のまま |
| 欧文の語間と字間の範囲の設定 | 許容度と字幅の伸縮だけ | ジャスティフィケーションの語間、字間、字形の比率（※） | `\spaceskip`、microtype | 低 | 後の版 |
| 複数の索引と用語集 | 一つの索引 | 複数の索引の機能は確かめていない（※） | imakeidx、glossaries | 低 | 後の版 |
| 回転と横置きのページ | なし | オブジェクトの回転（※） | rotating、pdflscape | 低 | 後の版 |
| 既存の PDF のページの取り込み | なし | PDF のページを図版として置く（※） | pdfpages | 低 | 後の版。rc3 の草稿の PDF の図版で一ページずつは置ける |
| 漢文の訓点、組数字、縦組みの中の欧文の正立、縦組みの本の中の横組み | なし | 一部は確かめられなかった | kanbun、luatexja | 中 | v2 のまま |

（※）の付いた InDesign の記述は、この調査でヘルプの URL を確かめておらず、一般に知られた機能として書いた。
どれも後の版に置く提案なので、着手するときに確かめる。

## 版の振り分けの考え方

rc4 には、段落スタイルと図版の既存の欄を広げるだけで済み、ふつうの本の数ページで必ず出会う不足を置いた（1 から 4）。
1 から 3 は同じ段落スタイルの欄なので、一つの ADR で決められる。

v1.0.0 には、二つの種類のものを置いた。
一つは、記法、意味論 IR、プラグインの ABI を変えるもので、1.0.0 の後に変えると互換を壊す（6、8、9、11、12）。
もう一つは、InDesign で本を作る人が当然に使い、型がすでにあるか、計画済みの仕組みの上に安く作れるもの（5、7、10、13 から 17）である。

v1.0.0 の 13 項目は、すでに v1.0.0 にある 3 項目と合わせて多い。
v1.0.0 を rc4 の直後に出す今の計画とは釣り合わないので、計画の時期を延ばすか、項目を v1.x に回すかの判断が要る。
回すなら、記法と IR を変えない 10、13、15、16 を先に回すのがよい。

## 人の判断が要る点

調査の時点で、次の点の判断を所有者に求めた。

- v1.0.0 の項目の数と、rc4 の直後に v1.0.0 を出す計画との釣り合い。
- 「仕様が不明瞭な場合」の規則の順序。JLReq と InDesign の振る舞いが食い違う場合にどちらを採るか。
- 表のセルの結合を v1.0.0 に入れるか。前の調査は重要度を高とした。入れるなら、表の記法を作り直す ADR が要る。
- 条件テキストを作るか。媒体ごとの出し分けを媒体契約の中で認めるかを先に決める必要がある。
- 割注、字取り、縦組みの下線について、InDesign の日本語版の振る舞いを実機かヘルプの本文で確かめる人がいるか。この調査では helpx.adobe.com の本文を読めず、確かめられなかった。
- 「段落スタイルの分割禁止と連動」の孤立行の行数を、v2 の「孤立行の規則の見直し」から前倒しするか。

## 所有者の決定

この記録を含むプルリクエストのレビューで、所有者は次のとおり決めた。

- v1.0.0 に提案した 13 項目は、すべて v1.0.0 に置く。目次の項目の書式、下線と打ち消し線、OpenType の機能、段落の背景と囲み罫も含む。これらがなければ v1 とは呼べないためである。「版の振り分けの考え方」の、回すなら 10、13、15、16 を先に回すという案は採らない。
- JLReq と InDesign の振る舞いが食い違う場合は JLReq を採る。規則の順は JLReq、InDesign、TeX と LaTeX とし、仕様書の「仕様が不明瞭な場合」に書いた。
- 表のセルの結合は v2 のままとする。
- 条件テキストは v2 に置く。あわせて、外部のデータの値を組版に差し込む機能（InDesign のデータ結合にあたる差し込み）も v2 に置く。
- 孤立行の行数の欄（InDesign の段落の始めと終わりの行数にあたるもの）は、v1.0.0 の「段落スタイルの分割禁止と連動」に入れる。v2 の「孤立行の規則の見直し」には、既定の規則を和文の本で緩めるかどうかだけが残る。

割注、字取り、縦組みの下線の InDesign の振る舞いは、確かめられないまま残っている。

## 参考文献

- [前の調査（2026-10-16 の TeX との比較）](2026-10-16-tex-feature-gap.md)
- Adobe, InDesign User Guide, https://helpx.adobe.com/indesign/desktop.html （各項目の URL を参照）
- LaTeX2e unofficial reference manual, https://latexref.xyz/
- CTAN のパッケージのページ: ragged2e、titlesec、graphicx、hyperref、bookmark、needspace、caption、tabularx、multirow、tocloft、titletoc、upmendex、biblatex、ulem、soul、lua-ul、realscripts、fontspec、tcolorbox、mdframed、footmisc、float、lettrine、enumitem、cleveref、lineno、draftwatermark、imakeidx、glossaries、rotating、pdflscape、pdfpages、comment、etoolbox、luatexja、jlreq（https://ctan.org/pkg/ の後にパッケージの名前）
- W3C, Requirements for Japanese Text Layout（JLReq）, https://www.w3.org/TR/jlreq/
