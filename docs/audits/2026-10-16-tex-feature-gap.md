# TeX と比べて Golem に足りない組版の機能（2026-10-16）

この記録は、2026-10-16 の main（eaf8c74）の Golem を、TeX と LaTeX の系統（pLaTeX、upLaTeX、LuaLaTeX と、よく使われるパッケージ）と比べ、Golem に足りない組版の機能を並べたものである。
数式の組版は比較の対象から外した。
判定は仕様書の約束ではなく、今の実装でできることで行った。
仕様書（[docs/specifications.md](../specifications.md)）、言語仕様（[docs/markup.md](../markup.md)）、ADR、コードを読んで判定し、パブリックドメインの十冊を試しに組んで見つかった問題（[PR #123](https://github.com/tett23/golem/pull/123)、未マージ）を実際の振る舞いの証拠として使った。
十冊の問題は、以下では「十冊の試し組み」の番号（#123-1 など）で指す。

## 表の読み方

各項目には、次の三つを添える。

- **計画**：Golem の仕様書のどこに載っているか。「v1 残」は[v1 の実装で次の段階以降に回した項目](../specifications.md#v1-の実装で次の段階以降に回した項目)、「v2」と「v3」は[v2 以降に回した事項](../specifications.md#v2-以降に回した事項)と[v3 以降に回した事項](../specifications.md#v3-以降に回した事項)、「未決」は[未決事項](../specifications.md#未決事項)、「不採用」は[意図的に採用しなかったもの](../specifications.md#意図的に採用しなかったもの)か[課題にしなかった事項](../specifications.md#課題にしなかった事項)、「なし」はどこにも載っていないことを表す。
- **重要度**：和文の書籍と CI で組む本（InDesign の置き換え）にとっての重要度を、高、中、低の三段階で表す。
- **設計との相性**：Golem の設計（決定性、媒体契約、幾何の隔離、広い型と狭い実装、プラグインの S0 への限定）に合うか。「合う」はそのまま足せること、「条件付き」は形を変えれば足せること、「合わない」は設計が意図して外したことを表す。

## 要約

重要度の高いものを先に並べる。

| 順 | 機能 | TeX の手段 | Golem の今 | 計画 | 重要度 | 相性 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 段落の行揃え（中央、右、地付き） | `\centering`、`\raggedleft`、`flushright` | なし。扉、献辞、署名、奥付を組めない | v2 | 高 | 合う |
| 2 | 縦の空きの指定（段落の前後、見出しの前後、任意の空き） | `\vspace`、`\parskip`、titlesec | 同じ段落スタイルが続くときの `space-between` だけ | v2（一部）、なし（原稿の空き） | 高 | 条件付き |
| 3 | 改ページの手での制御（分けない範囲、ここで分けない、版面を一行延ばす） | `\nopagebreak`、`\samepage`、needspace、`\enlargethispage` | `@page-break` と `@column-break` だけ | なし（韻文の連だけ v2） | 高 | 合う |
| 4 | PDF のしおり、リンク、外部の URL | hyperref、`\url`、`\href` | PDF にアウトラインも注釈もない。原稿に URL のリンクを書く記法もない | v2（しおりと内部リンク）、なし（URL の記法） | 高 | 合う |
| 5 | PDF と SVG の図版 | graphicx | JPEG と PNG だけ。PDF の図版は仕様にあるが未実装 | v1 残 | 高 | 合う |
| 6 | テキスト層の正しさとグリフの欠けの検出 | fontspec、luaotfload のフォールバックと警告 | 合字の ToUnicode が一字目だけになる。グリフの欠けを `golem build` が黙って通す | なし | 高 | 合う |
| 7 | 章末注と複数段落の注 | endnotes、enotez、`\footnote` の中の段落 | 注は一段落だけ。`placement = "chapter-end"` は読むが効かない | v1 残、v2 | 高 | 合う |
| 8 | 表の拡張（結合、列幅、縦罫、番号とキャプション） | tabularx、multirow、booktabs、longtable、caption | 横の罫三本、列幅の自動、見出しの繰り返しだけ | v2 | 高 | 合う |
| 9 | 和文の拡張（割注、傍線、添え字、訓点） | pxrubrica、okumacro、luatexja の割注、kanbun | どれもない | v2 | 中〜高 | 合う |
| 10 | 前付けのローマ数字のノンブルと番号の振り直し | `\frontmatter`、`\pagenumbering` | ノンブルは通し番号だけ | v2 | 中〜高 | 合う |

このほかに、どこにも計画のない中程度の不足として、タグ付き PDF と PDF/UA、PDF/A、原稿の中の言語の切り替え、見出しの四階層め以降、注の印の書式、引用の頁の指定、複数の索引、用語集がある。
いずれも下の各節に書く。

## 段落の組み方

Golem の行分割は Knuth と Plass の方式で、TeX と同じ式を使い、TeX が組んだ段落を期待値にした参照のテストを持つ（[golem-layout ADR 0001](../golem-layout/adr/0001-knuth-plass-line-breaking.md)、[golem-layout ADR 0007](../golem-layout/adr/0007-knuth-plass-reference-test.md)）。
行分割の核は TeX と同等であり、不足は周辺の調整の手段にある。

| 機能 | TeX | Golem の今 | 計画 | 重要度 | 相性 |
| --- | --- | --- | --- | --- | --- |
| 段落の行揃え | `\centering`、`\raggedright`、`\raggedleft` | 両端揃えだけ。表のセルの揃えはある | v2（段落スタイルの拡張） | 高 | 合う |
| 行の終わりの側の字下げ | `\rightskip`、quote 環境 | 行の始まりの側の `indent` だけ（[docs/adr/0006](../adr/0006-paragraph-indent.md)） | v2 | 中 | 合う |
| 段落の形の指定 | `\parshape`、`\hangindent`、`\hangafter` | 内部の L*(i) はあるが、原稿や設定からは字下げと回り込みでしか使えない | なし | 低 | 条件付き |
| 段落ごとの行数の増減 | `\looseness` | なし | なし | 中 | 合う |
| 非常時の伸び | `\emergencystretch` | 許容度の段階の切り替えはある。三段めの段階はない | なし | 低 | 合う |
| 欧文の語間のスペースファクター | `\frenchspacing`、`\nonfrenchspacing` | スペースファクターを持たない（[行分割の節](../specifications.md#行分割)） | なし | 低 | 合う |
| 明示のハイフンの後の行の扱い | `\exhyphenpenalty` と行の評価 | 罰則の設定はある。明示のハイフンの前の行が極端に間延びする（#123-6） | なし（不具合） | 中 | 合う |
| 言語ごとのハイフネーション | babel、polyglossia のパターン | 英語（米）のパターンだけで、本の言語によらず当てる。仏語も英語のパターンで分ける（#123-7、`Golem.Driver.Pdf` が `englishUS` を固定で使う） | v2（英語以外のパターン） | 中 | 合う |
| ソフトハイフンと分割の位置の指定 | `\-`、`\hyphenation` | なし | v2 | 中 | 合う |
| 突き出し | microtype の protrusion | 欧文の約物の固定の表だけで、フォントごとの調整がない（[golem-layout ADR 0005](../golem-layout/adr/0005-microtypography.md)）。量が文字の幅でなく語の箱の幅に対する割合になっている（PR #122 の報告の 3） | なし（調整）、不具合 | 中 | 合う |
| 字幅の伸縮 | microtype の expansion | 欧文だけ、`Tz` による（[golem-layout ADR 0005](../golem-layout/adr/0005-microtypography.md)） | 和文の伸縮は ADR が外した | 低 | 合う |
| 字間とトラッキング | microtype の tracking、`\textls` | `tracking` がある（[docs/adr/0020](../adr/0020-indesign-character-features.md)） | ある | なし | なし |
| 手動のカーニング、文字の変形 | `\kern`、`\scalebox` | なし | v2（文字の変形と詰め） | 低 | 合う |
| オプティカルカーニング | なし（TeX にもない） | `optical` は G0321 | v2 | 低 | 合う |
| 合字のテキスト層 | pdfTeX と LuaTeX の ToUnicode、`\pdfglyphtounicode` | 合字のグリフの ToUnicode が先頭の一字になり、`fi` が `f` としてコピーされる（#123-1、`Golem.Driver.Fonts` の `clusterText` が一字だけ取る） | なし（不具合） | 高 | 合う |

和文の行の組み方（禁則、ぶら下げ、アキ量のセット、和欧間）は、JLReq と InDesign のアキ量設定にそろえた形で実装されている（[golem-layout ADR 0002](../golem-layout/adr/0002-japanese-composition.md)、[docs/adr/0019](../adr/0019-aki-settings.md)）。
未決事項として、和字の直後の欧文の句読点の前に四分を入れる扱いが残っている（[未決事項](../specifications.md#未決事項)）。

## ページの組み方

Golem の改ページは貪欲法で、行を版面の格子に先頭から詰める（[golem-layout ADR 0003](../golem-layout/adr/0003-pagination-and-s2.md)）。
TeX も貪欲法なので方式の差は小さい。
差は、TeX が罰則と手での指示で改ページを調整できるのに対し、Golem は固定の規則しか持たない点にある。
InDesign の置き換えを狙う以上、編集者がページの切れ目を手で直す手段の欠けは重い。

| 機能 | TeX | Golem の今 | 計画 | 重要度 | 相性 |
| --- | --- | --- | --- | --- | --- |
| 孤立行の調整 | `\widowpenalty`、`\clubpenalty`、`\brokenpenalty` | 段落の最初と最後の一行を残さない固定の規則だけ。行数も罰則も変えられない | なし | 中 | 合う |
| 分けない範囲、ここで分けない | `\nopagebreak`、`\samepage`、needspace、minipage | なし。韻文の連が二行ずつに分かれる（#123-9） | v2（韻文の連だけ） | 高 | 合う |
| 版面を一行延ばす、縮める | `\enlargethispage` | なし | なし | 中 | 条件付き |
| 見出しを次の内容と離さない | 見出しの後の `\nobreak` と `\@afterheading` | 直後の一ブロックしか見ない。見出しが続くと最初の見出しがページ末に残る（PR #122 の報告の 1） | なし（不具合） | 高 | 合う |
| ページ末の空き | なし（TeX は `\flushbottom` で行間を伸ばす） | 格子組みでは空きが残る。高野聖でページ末に 3〜5 行の空き（#123-4、原因は未調査） | なし | 中 | 合う |
| 段の高さをそろえる | multicol の balancing | なし | v2 | 低 | 合う |
| 一冊の中で段数を切り替える | multicol | 索引だけ（[docs/adr/0025](../adr/0025-index-columns.md)） | v2 | 中 | 合う |
| 段抜きの見出し | multicol の前置き、`\twocolumn[...]` | なし | v2 | 中 | 合う |
| 改ページの大域の最適化 | なし（TeX も貪欲法。LuaTeX のコールバックで実験はある） | なし | v2 | 低 | 合う |
| 柱（マーク） | `\markboth`、`\leftmark`、`\rightmark`、fancyhdr | 見出しの階層、最初と最後の選び方、書式、複数行の柱がある（[golem-driver ADR 0014](../golem-driver/adr/0014-running-heads.md)、[golem-driver ADR 0022](../golem-driver/adr/0022-running-head-formats.md)） | ある | なし | なし |
| ページスタイルの細部 | fancyhdr の左中右の複数の項目、柱の罫 | 柱一つとノンブル一つを六つの位置から選ぶだけ。柱の罫も色もない | v2（柱とノンブルの色） | 低 | 合う |
| 章の始まりのページの体裁 | `\thispagestyle{plain}` | recto の見出しのページで柱を消すだけ | なし | 低 | 合う |

## 浮動体、図版、キャプション

| 機能 | TeX | Golem の今 | 計画 | 重要度 | 相性 |
| --- | --- | --- | --- | --- | --- |
| PDF の図版 | graphicx | 仕様にあるが、`readImage` は JPEG と PNG だけを読む | v1 残 | 高 | 合う |
| SVG の図版 | svg パッケージ（Inkscape で変換） | なし | v1 残 | 中 | 合う |
| 置けない図版の扱い | 読めない画像はエラー | `golem build` が黙って落とす。preflight だけが G0905 で報告する | v1 残 | 高 | 合う |
| 置き方の指定 | float の `[htbp]`、`[H]` | 出た位置か次のページの先頭だけ。上、下、別ページの指定がない | なし | 中 | 合う |
| 図版の順序 | 浮動体は順序を保つ | 収まった図が先に送られた図より先に置かれ、順序が入れ替わる（PR #122 の報告の 4） | なし（不具合） | 高 | 合う |
| 大きさの指定と縮小 | `\includegraphics[width=...]` | 回り込ませない図版は行長の幅に固定 | v2（図版とキャプションの拡張） | 高 | 合う |
| 回転、横置きのページ | rotating、pdflscape | なし | なし | 低 | 合う |
| 塗り足しまでの図版 | eso-pic、tikz の overlay | なし | v2 | 中 | 合う |
| 回り込み | wrapfig | 矩形の回り込みがある（[golem-layout ADR 0004](../golem-layout/adr/0004-wrapped-figures.md)）。段組みでは使えない | v2（段組み、矩形以外） | 低 | 合う |
| 小図（subfigure） | subcaption | なし | なし | 低 | 合う |
| キャプションの書式 | caption | 位置は下（縦組みでは左）に固定。番号と本文で書体を分けられない | v2 | 中 | 合う |
| 表と図の別の番号、表のキャプション | `\caption` を table に | 表に番号もキャプションもない | v2（表の拡張） | 中 | 合う |
| 図目次と表目次 | `\listoffigures`、`\listoftables` | なし | v2（目次の拡張） | 低 | 合う |

## 表

表は行の格子に載せて組み、改ページで見出しの行を繰り返す（[golem-driver ADR 0008](../golem-driver/adr/0008-pdf-tables.md)）。
罫は booktabs に近い三本の横罫であり、longtable に当たる分割はできている。

| 機能 | TeX | Golem の今 | 計画 | 重要度 | 相性 |
| --- | --- | --- | --- | --- | --- |
| セルの結合 | multirow、`\multicolumn` | なし | v2 | 高 | 合う |
| 列の幅の指定 | tabularx、`p{...}` | 自動だけ | v2 | 中 | 合う |
| 縦罫、罫の種類と色 | 列の指定の縦罫、hhline、colortbl | 横罫三本だけ | v2 | 中 | 合う |
| 表の文字の大きさ | `\small` を表の中に | 本文と同じ大きさだけ | v2 | 中 | 合う |
| セルの中のブロック | `p{}` の中の段落、リスト | インラインだけ | v2 | 低 | 合う |
| 行の途中での改ページ | なし（longtable も行の単位） | 行の単位 | v2 | 低 | 合う |
| 表の前後のアキと罫の位置 | booktabs の `\aboverulesep` | 罫が本文に接し、表の前後に空きがない。空の見出し行で罫が二重になる（#123-5） | なし（不具合） | 高 | 合う |
| 縦組みの本の中の横組みの表 | `\yoko` の中の表 | なし | v2 | 中 | 合う |

## 注と傍注

| 機能 | TeX | Golem の今 | 計画 | 重要度 | 相性 |
| --- | --- | --- | --- | --- | --- |
| 章末注 | endnotes、enotez | `placement` を読むが効かない | v1 残 | 高 | 合う |
| 複数段落の注 | `\footnote` の中の `\par` | 一段落だけ | v2 | 中 | 合う |
| 注の印の書式 | footmisc、`\thefootnote`、記号の印 | `*1` の形に固定（[golem-driver ADR 0018](../golem-driver/adr/0018-footnote-marks-and-numbers.md) が設定を作らないと決めた） | なし | 中 | 合う |
| ページごとの番号 | footmisc の `perpage` | なし。ページが決まるまで番号が決まらないので v1 では採らない | なし | 低 | 条件付き |
| 段落形式の脚注、複数の系列 | footmisc の `para`、manyfoot、bigfoot | なし | なし | 低 | 合う |
| 脚注の区切り線 | `\footnoterule` | 長さ、太さ、間隔がある（[golem-driver ADR 0024](../golem-driver/adr/0024-rule-spec-and-footnote-separator.md)）。色と線の種類はない | v1 残（色と種類） | 低 | 合う |
| 傍注 | `\marginpar`、marginnote、sidenotes | 横組みの一段組みだけ。収まらない傍注はエラー（[golem-driver ADR 0006](../golem-driver/adr/0006-pdf-sidenotes.md)） | v2（縦組み、段組み、脚注への振り替え） | 中 | 合う |
| 脚注の多い本の速度 | 問題にならない | 脚注 14 件の本だけが 17〜20 秒かかる（#123-10） | なし（速度の不具合） | 中 | 合う |

## 見出し、番号、目次

| 機能 | TeX | Golem の今 | 計画 | 重要度 | 相性 |
| --- | --- | --- | --- | --- | --- |
| 見出しの階層の数 | `\part` から `\subparagraph` まで七階層 | 三階層（意味論 IR の見出しの階層が `1..3`） | なし | 中 | 合う |
| 見出しの前後の空きと行取り | titlesec の `\titlespacing` | 大きさから行数を自動で決め、領域の中央に置くだけ。既定の見出しが本文と同じ大きさで空きもない（#123-11） | v2（行取り） | 高 | 合う |
| 追い込みの見出し、左右に置く見出し | titlesec の `runin`、`leftmargin` | なし | なし | 低 | 合う |
| 番号の書式 | `\thesection` の再定義 | 書式の差し込みで書ける | ある | なし | なし |
| 目次の書体、字下げ、リーダー | tocloft、titletoc | 階層ごとの一字下げ、リーダーの有無だけ | v2（目次の拡張） | 中 | 合う |
| 章ごとの小目次 | minitoc、etoc | なし | v2 | 低 | 合う |

## 相互参照、リンク、PDF の機能

Golem の相互参照は番号、題、ページの三つで、ページ番号は一回の `golem build` の中で収束するまで組み直す（[golem-layout ADR 0003](../golem-layout/adr/0003-pagination-and-s2.md)）。
PDF の側の機能は、文書情報と XMP のほかに何もない。
コードを確かめると、golem-pdf は `/Outlines`、`/Annots`、`/StructTreeRoot`、`/PageLabels` のどれも書かない。

| 機能 | TeX | Golem の今 | 計画 | 重要度 | 相性 |
| --- | --- | --- | --- | --- | --- |
| PDF のしおり | hyperref、bookmark | なし | v2（PDF のしおりとリンク） | 高 | 合う |
| 文書の中のリンク | hyperref | PDF にはない。HTML と EPUB にはある | v2 | 高 | 合う |
| 外部の URL | `\url`、`\href` | 原稿に URL のリンクを書くインラインのコマンドがない。PDF、HTML、EPUB のどれにも出せない | なし | 高 | 合う |
| 参照の文言の自動付加 | cleveref、varioref | なし（`図[ref-number x]` のように手で書く） | なし | 低 | 合う |
| ページラベル | hyperref の `pdfpagelabels` | なし | なし（ローマ数字のノンブルとあわせて要る） | 低 | 合う |
| PDF の文書情報と XMP | hyperref の `pdfinfo`、pdfx | マニフェストから決定的に書く | ある | なし | なし |
| タグ付き PDF、PDF/UA | tagpdf、LaTeX の `\DocumentMetadata{tagging=on}` | なし。`/Lang` もない | なし | 中 | 合う |
| PDF/A | pdfx、`\DocumentMetadata{pdfstandard=a-2b}` | なし | なし | 低 | 合う |
| PDF/X | pdfx（X-1a、X-4） | PDF/X-4 だけ。規格の本文との照合が済んでいない | 未決 | なし | なし |

タグ付き PDF と PDF/A は、仕様書のどこにも扱いが書かれていない。
アクセシビリティの要件は EPUB の代替テキストとして持ち込まれているが（「図版」の節）、PDF の側は決まっていない。

## 参考文献、索引、用語集

| 機能 | TeX | Golem の今 | 計画 | 重要度 | 相性 |
| --- | --- | --- | --- | --- | --- |
| 書誌の項目 | biblatex のデータモデル | 著者、題、発行者、年だけ。誌名、巻号、ページ、URL を組まない | v1 残 | 中 | 合う |
| 引用の書式の選択 | biblatex のスタイル、natbib、CSL | 番号の一種類、最初に引用した順だけ（[golem-doc ADR 0004](../golem-doc/adr/0004-bibliography-formatting.md)） | v2 | 中 | 合う |
| 引用の頁の指定と複数の文献 | `\cite[p.~5]{a,b}` | `[cite]` はキーを一つだけ取り、頁を書けない | なし | 中 | 合う |
| 書誌のぶら下げ | biblatex の `\bibhang` | なし | v2 | 低 | 合う |
| 索引の階層と参照 | makeindex、xindy の三段、`see` | 二段まで、参照なし | v2 | 中 | 合う |
| 索引の見出しとページの範囲 | `\indexsetup`、範囲の印の `(` と `)` | なし | v2 | 中 | 合う |
| 複数の索引 | imakeidx、splitidx | 一つだけ（チャネルの種類が固定） | なし | 低 | 合う |
| 用語集、略語集 | glossaries | なし。仕様は「プラグインで作れる」と書くが、意味論 IR のチャネルは目次、索引、参考文献の三種に固定で、プラグインが新しい一覧を作る経路がない | なし | 低 | 条件付き |

## リスト

リストの印と番号の書式は深さごとに設定できる（[golem-driver ADR 0013](../golem-driver/adr/0013-list-indents.md)）。
enumitem の主な用途は覆っている。

| 機能 | TeX | Golem の今 | 計画 | 重要度 | 相性 |
| --- | --- | --- | --- | --- | --- |
| リストごとの書式 | enumitem の環境ごとの指定 | 本に一つの `[lists]` だけ | なし | 低 | 条件付き |
| 項目の間と前後の空き | enumitem の `itemsep`、`topsep` | なし | なし | 低 | 合う |
| 定義リストの体裁 | description の `style=nextline` など | 固定 | なし | 低 | 合う |
| 文中のリスト | enumitem の `inline` | なし | なし | 低 | 合う |

## 多言語と和文の機能

Golem の言語は本に一つで、マニフェストの `[metadata] language` だけが持つ。
原稿の一部の言語を変えるコマンドはない。

| 機能 | TeX | Golem の今 | 計画 | 重要度 | 相性 |
| --- | --- | --- | --- | --- | --- |
| 原稿の中の言語の切り替え | babel の `\foreignlanguage`、polyglossia の `\textlang` | なし。HTML の `lang` 属性も本に一つ | なし | 中 | 合う |
| 双方向のテキスト | bidi、LuaTeX の `\textdir` | なし | 不採用（複雑な文字体系の検証） | 低 | 合わない |
| ルビ | pxrubrica、luatexja-ruby | モノルビ、グループルビ、かけ、行頭と行末の処理がある（[golem-layout ADR 0009](../golem-layout/adr/0009-ruby-placement.md)） | v2（熟語ルビ、両側ルビ、大きさ） | 中 | 合う |
| 圏点 | pxrubrica の `\kenten`、okumacro | 十の形がある（[golem-driver ADR 0019](../golem-driver/adr/0019-pdf-kenten-shapes.md)） | ある | なし | なし |
| 縦中横 | `\tatechuyoko`、`\rensuji` | ある | ある | なし | なし |
| 割注 | luatexja の `\warichu`、`\warigaki` | なし | v2（和文組版の拡張） | 中 | 合う |
| 傍線、下線 | okumacro の `\bou`、ulem、soul | なし | v2（傍線） | 中 | 合う |
| 添え字（上付き、下付き） | `\textsuperscript`、`\textsubscript` | なし。`baseline-shift` と `size` の文字スタイルで近似はできる | v2 | 中 | 合う |
| 組数字、組文字 | jlreq の `\kumimoji` 系、otf の `\UTF` と合字 | なし | なし | 低 | 合う |
| 字取り、均等割り | `\kintou`、jlreq の `\jidori` | なし | v2（段落スタイルの拡張の字取り） | 中 | 合う |
| 漢文の訓点 | kanbun パッケージ | なし | v2 | 中 | 合う |
| 縦組みの中の欧文を一字ずつ正立 | `\rensuji` の連続、luatexja の `\yoko` 指定 | なし（欧文は回転） | v2 | 低 | 合う |
| 縦組みの本の中の横組みの部分 | 一冊の中での組方向の切り替え | なし | v2 | 中 | 合う |
| 縦組みの字下げ | 字下げは行の始まりから測る | 縦組みで `indent=5zw`、`first-line-indent=0` の段落の一行目が約 1.5 字下がり、行長が約 2 字短い（#123-3） | なし（不具合） | 高 | 合う |
| 段落の先頭の始め括弧の字下げ | jlreq の設定 | なし | v2 | 低 | 合う |

## 色、箱、背景、描画

| 機能 | TeX | Golem の今 | 計画 | 重要度 | 相性 |
| --- | --- | --- | --- | --- | --- |
| 文字の色 | xcolor | スウォッチの CMYK だけ（[golem-driver ADR 0004](../golem-driver/adr/0004-pdf-emphasis-and-character-styles.md)） | ある | なし | なし |
| 特色 | xcolor の spot、colorspace パッケージ | なし | v2 | 低 | 合う |
| 枠と背景の箱 | tcolorbox、`\fbox`、`\colorbox`、mdframed | コードブロックの背景と枠だけ | なし（一般の箱） | 中 | 条件付き |
| 段落の罫線 | mdframed、titlesec の罫 | なし | v1 残 | 中 | 合う |
| 本文の中のコードの背景 | `\colorbox` | なし | v1 残 | 低 | 合う |
| ページの背景、透かし | eso-pic、background、draftwatermark | なし | なし | 低 | 合う |
| 描画 | TikZ、PSTricks、picture 環境 | なし | なし | 低 | 合わない |
| 透明 | transparent パッケージ | なし | なし | 低 | 条件付き |

描画を Golem に持たせることは、図を外部の道具で作って図版として置く分担（「小さな道具で組み立てる」の方針）と合わない。
ただし、その分担は PDF と SVG の図版を置けることが前提であり、今はその前提が欠けている。

## コードの掲載

行番号、強調、差分、注釈の印、キャプション、ファイル名、構文の色分けがある（[golem-driver ADR 0017](../golem-driver/adr/0017-pdf-code-blocks.md)、[golem-driver ADR 0023](../golem-driver/adr/0023-code-block-book-features.md)）。
listings と minted の主な機能は覆っている。
残る差は、コードの中に原稿の記法を混ぜる手段（listings の `escapeinside`）がないことと、本文の中のコードの背景（v1 残）だけである。
重要度はどちらも低い。

## プログラム可能性と拡張

| 機能 | TeX | Golem の今 | 計画 | 重要度 | 相性 |
| --- | --- | --- | --- | --- | --- |
| マクロ | `\newcommand`、expl3 | `[!` を予約しただけ | 不採用（hygienic な変換に限り将来） | 中 | 条件付き |
| 式の言語 | expl3、LuaTeX の Lua | 算術と比較だけ。関数、条件、繰り返しなし（[golem-eval ADR 0001](../golem-eval/adr/0001-expression-language-and-numerics.md)） | 不採用 | 低 | 合わない |
| 拡張の機構 | パッケージ、LuaTeX のコールバック | wasm のプラグイン（コマンドとフィルタ）。S0 だけで動き、レイアウトに触れない | ある | なし | なし |
| 改ページとレイアウトへの介入 | 出力ルーチン、`pre_linebreak_filter` など | なし | なし | 低 | 合わない |
| パッケージの配布 | CTAN、TeX Live | URL とロックファイルだけ | v2（配布機構） | 中 | 合う |
| 設定の分割 | `\input` によるクラスとスタイルの分割 | `style.toml` は一つのファイル | v2 | 中 | 合う |

出力ルーチンへの介入とチューリング完全なマクロは、決定性と媒体契約を守るために外した機能であり、足りないことそのものが設計の結果である。

## フォント

| 機能 | TeX | Golem の今 | 計画 | 重要度 | 相性 |
| --- | --- | --- | --- | --- | --- |
| OpenType の機能 | fontspec の `Features` と `\addfontfeatures` | 役割ごとの `features` だけ。文字スタイルからは機能を足せず、スモールキャップなどは役割を一つ増やして書く | なし | 中 | 合う |
| 可変フォント | fontspec の軸の指定 | 既定のインスタンスだけ | v2 | 低 | 合う |
| フォールバック | luaotfload の `fallback` | 役割ごとに和文と欧文の二つだけ。ほかの字の代わりの書体を指定できない | なし | 中 | 合う |
| グリフの欠けの報告 | `Missing character` の警告 | `golem build` は黙って通し、`.notdef` の箱か何も描かない。preflight だけが検出する（#123-2） | なし | 高 | 合う |
| 光学サイズ | fontspec の `SizeFeatures` | なし | なし | 低 | 合う |
| 異体字 | `\UTF`、IVS | 異体字セレクタを通し、ToUnicode に基底の字を書く（[golem-pdf ADR 0006](../golem-pdf/adr/0006-cid-system-info.md)） | ある | なし | なし |
| システムのフォント | fontspec が名前で引く | 引かない | 不採用（決定性） | なし | 合わない |

## 出力、ページ、PDF の規格

| 機能 | TeX | Golem の今 | 計画 | 重要度 | 相性 |
| --- | --- | --- | --- | --- | --- |
| 判型と版面 | geometry | 字数、行数、行送りで版面を決め、余白を従属させる | ある | なし | なし |
| トンボと塗り足し | crop、gentombow | 日本式と欧文式のトンボ、塗り足し、隠しノンブルがある（[golem-pdf ADR 0004](../golem-pdf/adr/0004-crop-marks-and-bleed.md)、[golem-driver ADR 0021](../golem-driver/adr/0021-hidden-folios.md)） | ある | なし | なし |
| 前付けのノンブル | `\frontmatter`、`\pagenumbering{roman}` | なし | v2 | 中〜高 | 合う |
| 面付け | pdfpages、bookletimpose | なし | v2 | 低 | 合う |
| 既存の PDF のページの取り込み | pdfpages | なし | なし | 低 | 合う |
| フレームと絶対配置 | textpos、tikz の overlay | レベル 2 と 3 のフレームは型だけ | v2 | 中 | 合う |

## ビルドの速さと誤りの報告

| 機能 | TeX | Golem の今 | 計画 | 重要度 | 相性 |
| --- | --- | --- | --- | --- | --- |
| 差分のビルド | latexmk の再実行の判定、`\includeonly` | 毎回すべてを組む | v2（ビルドと LSP の速度） | 中 | 合う |
| 一部の章だけ組む | `\includeonly` | なし | なし | 低 | 条件付き |

誤りの報告では Golem が TeX を上回る（末尾の一覧を参照）。

## Golem が TeX より優れている点

- 同じ入力から同じバイト列の PDF を得る決定性を、処理系が保証する（[docs/adr/0002](../adr/0002-determinism.md)）。
- 一つの意味論 IR から PDF、EPUB、HTML、プレーンテキストを出す。
- 診断に安定したコード、`golem explain`、JSON の形式、LSP、fmt、lint がある。
- ページ番号の参照と索引を一回のビルドの中で収束させ、再実行を求めない。
- PDF/X-4、トンボ、隠しノンブル、プリフライトを最初から持つ。
- InDesign に合わせたアキ量のセットと正規表現スタイルを、行の格子に載せた和文の版面で使える。
- コードの色分けに外部のプログラム（minted の Pygments）を呼ばず、プラグインは wasm の隔離の中で動く。

## 人の判断が要る点

この調査で、仕様書の一覧に載っていない不足と、十冊の試し組みで見つかった不具合のうち、扱いが決まっていないものを挙げる。

- 原稿の中の URL のリンク、改ページを手で制御する記法、タグ付き PDF と PDF/A、原稿の中の言語の切り替え、見出しの四階層め以降は、どの一覧にもない。今後の実装項目に加えるかを決める必要がある。
- 合字のテキスト層（#123-1）、グリフの欠けを `golem build` が通すこと（#123-2）、縦組みの字下げ（#123-3）、表の前後の空き（#123-5）、明示のハイフンの前の行の間延び（#123-6）、図版の順序と見出しの送り（PR #122 の報告）は不具合であり、ADR で直すか v1 残に加えるかが決まっていない。
- 注の印の書式は [golem-driver ADR 0018](../golem-driver/adr/0018-footnote-marks-and-numbers.md) が設定を作らないと決めたが、今後の実装項目にも課題にしなかった事項にも載っていない。

## 参考文献

- Donald E. Knuth, *The TeXbook*, Addison-Wesley, 1984.
- LaTeX Project, *LaTeX2e for authors*（ltnews と tagging project の文書を含む）, https://www.latex-project.org/help/documentation/
- 各パッケージの CTAN の文書: microtype、geometry、fancyhdr、hyperref、biblatex、babel、polyglossia、luatexja、pxrubrica、okumacro、longtable、booktabs、float、caption、multicol、footmisc、imakeidx、listings、minted、tcolorbox、xcolor、graphicx、pdfx、tikz（https://ctan.org/）
- W3C, *Requirements for Japanese Text Layout*（JLReq）, https://www.w3.org/TR/jlreq/
