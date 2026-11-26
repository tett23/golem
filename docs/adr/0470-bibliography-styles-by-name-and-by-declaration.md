# ADR 0470: 参考文献のスタイルを、決まった名前と宣言の二つで選ぶ

Status: accepted-pending

## 文脈

[Golem ADR 0385](0385-bibliography-and-citation-styles.md) は、書き手が投稿先の規定に合わせて文献スタイルを作り、本ごとに指定できるようにすると決めた。
文献の種類ごとの欄の順、欠けた欄の省略、区切り、ソート、ぶら下げ字下げを宣言し、引用は番号式と著者年式を選べる。
しかし、スタイルを書く形（キーと値）と、投稿規定のどの書誌例で確かめるかは決めていない（ロードマップの「投稿用の文献スタイルを照合する雑誌」）。

メンテナーは、2026-11-26 に、次のことを決めた。

- 参考文献のスタイルは、自由に宣言する形と、Chicago のような決まった名前（列挙の値）の両方を用意する。
- 広く使われる書式を調べて、`docs/research/` に置く。
- 論文を投稿できる品質で組めるかを確かめるために、見本の論文を三つ組む。
  和文の縦組みの 2 段組みで室町期の朝廷について、和文の横組みの 2 段組みで宇佐美のディスコース・ポライトネス理論のおさらいと展望について、欧文の 2 段組みで待遇表現について書く。
  参考文献は、その論文を投稿するならこの雑誌だろうというものの書式で組む。
  本文はある程度適当でよいが、参考文献は実在し、書誌を確かめたものだけにする。

この ADR は、スタイルの書き方、決まった名前の一覧、見本の論文を決める。

## 調査した事項

### 今の書式

origin/main（[c034510](https://github.com/tett23/golem/commit/c034510e33476f4af68ba22636f5ab6ef8463f0a)）の仕様書で、次のことを確かめた。

- 書誌データは CSL-JSON のファイルに置き、本文では `[cite キー]` で引用する（docs/specifications.md の 8905 行から 8934 行）。
- 引用の印は番号の書式の一種類だけで、golem-doc の `Golem.Doc.Citation.citationPieces` が決める（同 8936 行から 8959 行）。
- 参考文献の一件は、著者、題、掲載先、発行者、発行の年、URL と閲覧日の順に空でない欄を並べ、golem-bibliography の `Golem.Bibliography` が決める（同 8984 行から 8990 行、[golem-doc ADR 0005](../golem-doc/adr/0005-bibliography-fields.md)）。
  スタイルは選べない。
- 数の表記の名前（`kanji`、`kanji-digits` など）は、書式の差し込みに `{n:kanji}` の形で書ける（同 1697 行、2280 行）。
- 注のチャネルは、脚注、傍注、章末の注の三つである（同 8292 行）。
  PDF の脚注の置き場所は `[notes]` の `placement` で、ページ下か章末を選ぶ（同 2640 行）。

### 広く使われる書式と投稿先

調べた結果は [docs/research/bibliography-styles.md](../research/bibliography-styles.md) にまとめた。
この ADR が使う事実は次のとおりである。

- 書式は、欄の順、区切り、括弧と斜体、著者名の順と略し方、編者の書き方、ページの範囲の略し方、日付の形、一覧の並べ方で違う。
  斜体にする欄は、文献の種類で変わる（書籍は題、論文は誌名）。
- 一次資料の書誌例を読めたのは、IEEE（IEEE Reference Guide）、Vancouver（NLM の見本のページ）、SIST 02、Unified Style Sheet for Linguistics（De Gruyter Mouton の書式）である。
  Chicago は大学の図書館の案内から、APA はエージェントが覚えていた形を Crossref の書誌で確かめたものから採った。
  MLA、Harvard、ISO 690 は、一次資料を読めないか、書式を決める団体が無い。
- 室町期の朝廷の論文の投稿先の候補（史学雑誌、日本歴史、古文書研究）は、どれも参考文献の書式を定めない。
  日本歴史は、注を全体の通し番号にして論文の末尾にまとめると定める。
  題を「」と『』で囲み、巻号と年を漢数字で書く形は、規定でなく、三重県の文書にあった例による慣行である。
- ディスコース・ポライトネス理論の論文の投稿先の『社会言語科学』は、著者と年の引用（本文では `安田・海野`、複数の文献は古い順）と、第一著者の名前の順に日本語と欧文を混ぜた一つの一覧を定め、日本語の項目に『』と「」を使わない。
  雛形は 1 段組みである。
- 待遇表現の論文の投稿先の Journal of Politeness Research は、Unified Style Sheet for Linguistics に基づく書式を定め、本文で `&` を使わず、一覧では `&` を使う。
- 研究の文書の文献のうち、Haugh 2007 のページ、今谷 1990 の叢書の番号、Usami 2002 の総ページ数は確かめられていない。

## 実装すること

### スタイルの選び方

`style.toml` の `[bibliography]` の `style` に、スタイルの名前を書く。
名前は、処理系が持つ決まった名前か、書き手が `[bibliography.styles.<名前>]` に宣言したスタイルの名前である。
`style` を書かなければ、`golem`（今の書式）を使う。

決まった名前は次のとおりである。

| 名前 | 書式 | 引用 | 書誌例の出典 |
| --- | --- | --- | --- |
| `golem` | 今の書式（[golem-doc ADR 0005](../golem-doc/adr/0005-bibliography-fields.md)） | 番号 | 今の仕様（docs/specifications.md の「参考文献の書式」） |
| `ieee` | IEEE Reference Guide（V 3.28.2025） | 番号 | 一次資料：IEEE Reference Guide（https://journals.ieeeauthorcenter.ieee.org/wp-content/uploads/sites/7/IEEE_Reference_Guide.pdf） |
| `vancouver` | NLM の見本のページの書式 | 番号 | 一次資料：NLM の Samples of Formatted References（https://www.nlm.nih.gov/bsd/uniform_requirements.html） |
| `sist02` | SIST 02（2007） | 番号 | 一次資料：SIST 02「参照文献の書き方」（https://warp.ndl.go.jp/20220119/20220113214833/jipsti.jst.go.jp/sist/handbook/sist02_2007/main.htm） |
| `unified-linguistics` | Unified Style Sheet for Linguistics | 著者と年 | 一次資料：De Gruyter Mouton Journal Style Sheet v1.3（https://www.degruyterbrill.com/publication/journal_key/JPLR/downloadAsset/JPLR_Mouton_journal_stylesheet.pdf）と Unified Style Sheet for Linguistics（https://www.linguisticsociety.org/sites/default/files/style-sheet_0.pdf） |
| `chicago-notes-bibliography` | Chicago 18 版の注と書誌 | 注 | 二次資料：Widener University の案内（https://widener.libguides.com/Chicago18/examples）、University of Queensland の案内（https://guides.library.uq.edu.au/referencing/chicago-18th-edition-notes-and-bibliography） |
| `chicago-author-date` | Chicago 18 版の著者と年 | 著者と年 | 二次資料：Widener University の案内（同上） |
| `apa` | APA 7 版 | 著者と年 | 二次資料：APA の公式の例の書誌を Crossref で確かめたもの、University of Melbourne の案内（https://library.unimelb.edu.au/recite/referencing-styles/apa7/referencing-non-english-sources） |

Chicago の二つは、メンテナーが決まった名前の例に挙げたので同梱する。
APA は、広く使われるので足す。
二次資料による三つは、一次資料で確かめるまで、仕様書とマニュアルに、この表の出典と、二次資料によることを書く。
同梱のスタイルの宣言のファイルの頭にも、同じ出典を書く。
`golem` のほかの決まった名前は、下の宣言の形で書いたスタイルとして、処理系に同梱する。
書き手は、同梱のスタイルを写して直せる。

### 宣言の形

`[bibliography.styles.<名前>]` に、次のキーを書く。

| キー | 値 |
| --- | --- |
| `citation-mode` | `numeric`、`author-year`、`note` のどれか |
| `citation` | 本文の引用の印の書式（`note` では注の本文の書式）。片の配列 |
| `citation-year` | `author-year` で、著者名を地の文に書き、年だけを括弧に入れる引用（`[cite キー form=year]`）の書式。片の配列 |
| `citation-delimiter` | 一つの印の中の文献の区切り |
| `citation-sort` | 一つの印の中の文献の並べ方。`written`（書いた順）か `year`（古い順） |
| `subsequent` | `note` で、同じ文献を二度目から引用するときの書式。書かなければ `citation` と同じ |
| `note-channel` | `note` の注のチャネル。`footnote`（既定）か `endnote` |
| `sort` | 一覧の並べ方のキーの配列。`citation`（最初に引用した順）、`author`、`year`、`title`、`language` |
| `language-order` | `sort` の `language` の順。言語の主の副タグの配列で、`"*"` はほかの言語 |
| `label` | 一覧の項目の頭の書式（`"[{number}]"`、`"({number})"` など）。書かなければ頭を付けない |
| `hanging-indent` | ぶら下げ字下げの寸法 |
| `year-suffix` | 同じ著者の同じ年の文献に `a`、`b` を付けるか（真偽値） |
| `page-range` | `full`（略さない）か `minimal`（284-7 のように終わりの上の桁を略す） |
| `range-delimiter` | ページの範囲の区切りの文字列 |
| `months` | 月の名前の 12 の文字列の配列（`{month}` の値） |
| `locator-labels` | 位置の種類（CSL の 26 の種類）ごとの、単数と複数のラベルの二つの文字列の表（`page = ["p.", "pp."]`、`page = ["頁", "頁"]`）。`{locator}` は、このラベルと値で組む |
| `types.<種類>` | 文献の種類（CSL の `type`）ごとの、一件の書式の表（下） |
| `types.default` | `types` に無い種類の書式の表 |
| `names.author`、`names.editor` | 著者名と編者名の組み方の表（下） |
| `names.short` | 引用の印の著者名の組み方の表（下） |
| `languages.<言語>` | その言語の文献に当てる、上のキーの上書き |

一件の書式の表は、次のキーを持つ。

| キー | 値 |
| --- | --- |
| `pieces` | 片の配列 |
| `char-styles` | 欄の名前から文字スタイルの名前への表。その種類の文献でだけ当たる |

片は、柱の書式と同じ「差し込みのある書式」である。
差し込みは、CSL の変数の名前（`{title}`、`{container-title}`、`{volume}`、`{issue}`、`{page}`、`{publisher}`、`{publisher-place}`、`{collection-title}`、`{collection-number}`、`{edition}`、`{DOI}`、`{URL}`、`{ISBN}` など）と、次のものである。

| 差し込み | 値 |
| --- | --- |
| `{author}`、`{editor}` | `names.author`、`names.editor` で組んだ名前。ただし、`numeric` と `author-year` の `citation`、`citation-year`、`subsequent` の `{author}` は `names.short` で組む |
| `{editor-label}` | 編者が一人なら `names.editor` の `label` の一つ目、複数なら二つ目 |
| `{year}`、`{month}`、`{day}` | `issued` の年、月（`months` の名前か、数の表記）、日 |
| `{locator}` | 引用の位置（`p. 5` など） |
| `{number}` | 番号の方式の番号 |
| `{first-note}` | `note` の `subsequent` で、その文献を最初に引用した注の番号 |

数の値の差し込みには、数の表記を `{volume:kanji}` のように書ける。
値が数として読めないとき（`8(2–3)` の号など）は、表記を当てずにそのまま書く。
`?` の無い差し込みのどれかに値が無い片は、片ごと組まない。
これで、欠けた欄と、その前後の区切りや括弧を一緒に省ける。

名前の組み方の表は、次のキーを持つ。

| キー | 値 |
| --- | --- |
| `order` | `family-given`、`given-family`、`first-family-given`（最初の名前だけ姓を先にする） |
| `part-delimiter` | 姓を先に書く名前の、姓と名のあいだの文字列（`", "`、`" "`、`""`）。名を先に書く名前は、名と姓を U+0020 でつなぐ |
| `initials` | 名を頭文字にするか（真偽値） |
| `initial-format` | 頭文字の書式。`{i}` が頭文字（`"{i}."`、`"{i}"`） |
| `initial-delimiter` | 頭文字のあいだの文字列（`" "`、`""`） |
| `delimiter` | 名前のあいだの区切り |
| `last-delimiter` | 最後の名前の前の区切り |
| `max` | 書く名前の数の上限 |
| `use-first` | 上限を超えたときに書く名前の数 |
| `et-al` | 書かない名前を表す文字列 |
| `label` | `names.editor` だけ。一人と複数のときの語の二つの文字列（`["ed.", "eds."]`、`["編", "編"]`） |

`names.short` は、`names.author` と同じキーのうち、`delimiter`、`last-delimiter`、`max`、`use-first`、`et-al` を持ち、名前は姓だけを書く。

文献の言語は、CSL-JSON の `language` で決め、無ければ本の言語とする。

### 著者の名前の順

`sort` の `author` は、第一著者の名前の並べ替えのキーで比べる。
並べ替えのキーは、CSL-JSON の名前の表の、Golem が読む欄 `golem-sort-key` の文字列で、無ければ姓と名を `part-delimiter` でつないだ文字列である。
比べ方は、キーを小文字にし、ラテン文字の発音区別符号を外した文字列の、Unicode の符号位置の順である（`Kádár` は `kadar` として比べる）。
選んだスタイルの `sort` が `author` を含み、一覧を組むときは、一覧に載る文献の第一著者のうち、漢字かかなを含む姓で `golem-sort-key` の無い名前ごとに、警告の G03306 `著者名 <名前> に並べ替えのキー（golem-sort-key）がありません。符号位置の順で並べます` を出す。
`sort` が `author` を含まないスタイルと、一覧を組まない本では、G03306 を出さない。
書き手は、読みを `golem-sort-key` に書いて、五十音順やアルファベット順に並べる。

### 年だけの引用

`[cite]` に、名前付き引数 `form` を足す。
`form=year` の引用は、`author-year` のスタイルでは `citation-year` の書式で組み、ほかのスタイルでは `form` が無いときと同じに組む。
`form` のほかの値は、エラーの G02289 `cite の form は year だけを書けます: <値>` とし、`form` が無いときと同じに組む。

### 注の引用

`citation-mode = "note"` の引用は、引用の位置に注の印を置き、注の本文に `citation` の書式で文献を組む。
注は `note-channel` のチャネルに入り、書き手の書いた注と番号を通す。
同じ文献の二度目からの引用は、`subsequent` の書式で組み、`{first-note}` で最初の注の番号を引ける（「前掲注（3）」など）。
書き手の書いた注の本文の中の `[cite]` は、新しい注を作らず、その場に `citation` の書式で文献を組む。
一つの注の中に、複数の文献と地の文を並べられる。
`note` のスタイルでも、`@bibliography` を書けば一覧を組む。

### diagnostic

| 箇所 | コード | 重大度 | メッセージ |
| --- | --- | --- | --- |
| `style` の名前の決まった名前も宣言も無い | G03303 | エラー | `参考文献のスタイル <名前> がありません` |
| 宣言の書式として読めない（未知の差し込み、閉じない `{`、未知の表記） | G03304 | エラー | `参考文献のスタイル <名前> の <キー> を書式として読めません: <理由>` |
| 宣言の名前が決まった名前と同じ | G03305 | エラー | `<名前> は決まったスタイルの名前なので、宣言できません` |
| 漢字かかなの姓の並べ替えのキーが無い | G03306 | 警告 | 上のとおり |
| キーの値の型か範囲の誤り | G03006 | エラー | 今と同じ |

G03303 の後は、`golem` で組む。
G03304 は、書いた値ごとに一つ出す。

### 0385 との関係

0385 の `[cites: …]` の記法、位置の種類と前置きと後置き、G06009 の検査の改めは、0385 のとおり実装する。
0385 のスタイルの要求は、この ADR の次のキーで満たす。

| 0385 の要求 | この ADR |
| --- | --- |
| 文献の種類ごとの欄の順 | `types.<種類>` の `pieces` |
| 欠けた欄の省略、欄の有無による条件分岐、各欄の前後の句読点 | 値の無い差し込みを含む片を組まない決まり |
| 区切り（`separator`） | 片の文字 |
| 著者名順のソート（`sort`） | `sort` の `author` と並べ替えのキー |
| ぶら下げ字下げ | `hanging-indent` |
| 番号式と著者年式（`citation-mode`） | `citation-mode` の `numeric` と `author-year`。`note` と、年だけの引用の `citation-year` を足す |
| page や chapter のラベルの言語別の展開 | `locator-labels` と `languages.<言語>` の上書き |
| 著者名の順序とイニシャル、複数著者の列挙と省略 | `names.*` |
| 題や誌名の文字スタイル | `types.<種類>` の `char-styles` |

### 見本の論文

`samples/papers/` に、三つの見本のプロジェクトを置く。
本文は見本のために書いたもので、参考文献は [docs/research/bibliography-styles.md](../research/bibliography-styles.md) で書誌を確かめたものだけを使う。
確かめられなかった欄（Haugh 2007 のページ、今谷 1990 の叢書の番号、Usami 2002 の総ページ数）は、書誌データに書かない。

| プロジェクト | 組み方 | 参考文献のスタイル |
| --- | --- | --- |
| `muromachi-court` | 和文、縦組み、2 段組み。室町期の朝廷 | 宣言。規定の無い日本史の誌の慣行の形の、章末の注（`note`、`endnote`）。題を「」と『』で囲み、巻号と年を漢数字にし、二度目から「前掲注（n）」で引く |
| `discourse-politeness` | 和文、横組み、2 段組み。宇佐美のディスコース・ポライトネス理論のおさらいと展望 | 宣言。『社会言語科学』の著者と年の引用と、並べ替えのキーで日本語と欧文を混ぜた一覧 |
| `honorifics` | 欧文、2 段組み。待遇表現 | `unified-linguistics`（Journal of Politeness Research） |

見本を組む CI のジョブは、プルリクエストの CI のワークフローに足し、ほかのジョブと並べて動かす。
フォントは、今のプルリクエストの CI が PDF を組むのに使うものを使う。
ジョブの時間を実装のプルリクエストで測り、プルリクエストの CI の時間の予算を超えるなら、別の ADR で動かすイベントを決め直す。

### 文書

仕様書の「引用と参考文献」の節に、スタイルの選び方、決まった名前と書誌例の出どころ、宣言の形、注の引用を書く。
`docs/diagnostics.md` に G02289 と G03303 から G03306 を足す。
ロードマップの「参考文献のスタイル」の項目のうち、この ADR で決めたことを消し、「投稿用の文献スタイルを照合する雑誌」を消す。
マニュアルに、スタイルの選び方と、同梱のスタイルを写して直す手順を書く。

採択したら、0385 のステータスに `{"part":"実装すること","by":["docs/adr/0470-bibliography-styles-by-name-and-by-declaration.md"],"kind":"replace"}` を足す。

## 実装しないこと

CSL の XML のスタイルと BibTeX のスタイルを読むことはしない。
MLA、Harvard、ISO 690 は、決まった名前にしない。
書き手が宣言で書ける。
文献の言語を題の文字から推し量ることと、漢字の読みを推し量ることはしない。

## 不変条件

- I1: `[bibliography]` の `style` を書かない本は、どの出力も、この ADR の前と同じである。
- I2: 決まった名前のスタイルで組んだ一件は、同梱の宣言を書き手が `[bibliography.styles.<別の名前>]` に写して選んだときと同じ文字列になる。
- I3: 一件の書式の片のうち、`?` の無い差し込みに値の無い片は、組んだ文字列に現れない。
- I4: 文献キーに対応する位置、前置き、後置きは、`sort` を変えても同じキーに属する（0385 の不変条件 1）。
- I5: `note` のスタイルで、書き手の注の外の引用の数を k とすると、引用からできる注はちょうど k 個で、書き手の注の中の引用は注を作らない。
- I6: 一次資料による決まった名前のスタイルで、[docs/research/bibliography-styles.md](../research/bibliography-styles.md) に原文のとおり写した書誌例と同じ書誌データを組むと、例と同じ文字列になる。
- I7: `sort` が `author` を含むスタイルで一覧を組むとき、一覧に載る文献の、漢字かかなの姓で並べ替えのキーの無い第一著者の名前ごとに G03306 が、無いスタイルの名前ごとに G03303 が、読めない書式の値ごとに G03304 が、決まった名前の宣言ごとに G03305 が、ちょうど一つ出る。ほかの場合に G03306 は出ない。
- I8: 数として読めない値には、数の表記を当てずにそのまま書く。
- I9: `sort` の `author` の一覧は、第一著者の並べ替えのキーを小文字にして発音区別符号を外した文字列の、符号位置の順に並ぶ。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| `style` の無い本 | 今と同じ | I1 |
| `style = "ieee"` と、写した宣言 | 同じ文字列 | I2 |
| `["{title}", "、{volume:kanji}号"]` と `volume` の無い論文 | 「、号」が出ない | I3 |
| `{issue:kanji}` と号 `2–3` | `2–3` のまま | I8 |
| `sort = ["author"]` と `["citation"]` で、二つの文献に別の頁 | 各頁が対応する文献に付く | I4 |
| `note` で同じ文献を二度引用 | 注が二つ。二つ目は `subsequent` で、`{first-note}` は 1 | I5 |
| 書き手の注の中の `[cite a][cite b]` | 注は一つ。中に二つの文献 | I5 |
| `ieee` で Chiampi と Zilberti の論文 | 研究の文書の例と同じ（`M. M. Chiampi`、`Oct. 2011`） | I6 |
| `vancouver` で Halpern らの論文 | 研究の文書の例と同じ（`Halpern SD`、`2002 Jul 25`、`284-7`） | I6 |
| `sist02` で西と石原の論文 | 研究の文書の例と同じ | I6 |
| `unified-linguistics` で Heller の章（編者三人） | 研究の文書の例と同じ（`(eds.)`） | I6 |
| `author-year` で同じ著者の同じ年の二件 | 文献キー順に a、b | I4 |
| 漢字の著者に `golem-sort-key` があり、欧文の著者と混ぜた一覧 | キーの順に混ざる | I9 |
| `Kádár` と `Kz` の一覧 | `Kádár` が先 | I9 |
| `sort = ["author"]` で、漢字の第一著者に `golem-sort-key` が無い | G03306 | I7 |
| `style` の無い本の、漢字の著者に `golem-sort-key` が無い | G03306 なし | I7 |
| `author-year` の `[cite shibata1978 form=year]` | `(1978)` の形 | I2 |
| `locator-labels` の `page = ["頁", "頁"]` と `page=5` | `5頁` の形 | I2 |
| `style = "nature"` | G03303。`golem` で組む | I1, I7 |

## 受けいれ条件

- A1: 三つの見本の論文を PDF で組み、メンテナーが、投稿できる品質で組めているかを目で確かめる。
  `muromachi-court` の注の形は、メンテナーが日本歴史か史学雑誌の実際の誌面と比べる。
- A2: 三つの見本の論文を CI で組み、diagnostic が一つも出ない。

## テスト設計

root ADR 0470 I1 から I9 を名前の先頭に置いたテストを、golem-project（宣言の読み込みと diagnostic）、golem-bibliography（一件の書式と並べ方）、golem-doc（引用の印と注）に足す。
I6 は、研究の文書に原文のとおり写した一次資料の書誌例だけを使う。
二次資料から採った Chicago と APA の例も、同じ形のテストにするが、名前に「二次資料」と書く。
A2 は、見本を組む CI のジョブで確かめる。
A1 の見本は `samples/papers/` に置く。
テストは、実装の前に書いて落ちることを確かめる。

## トレードオフ

決まった名前のスタイルを宣言の形で同梱するので、処理系の中に書式ごとの特別な場合を持たない。
書式の細部が規定と違うと分かったときは、宣言を直すだけで済む。

CSL の XML のスタイルを読まないので、CSL の数千のスタイルはそのまま使えない。
CSL のスタイルの言語は大きく、実装は独立した大きな仕事になるためである。

漢字の読みを推し量らないので、日本語の文献を五十音順に並べるには、書き手が読みを書誌データに書く。
読みを推し量ると、同じ漢字の読みの違いで、黙って誤った順になるためである。

『社会言語科学』の雛形は 1 段組みなので、2 段組みの見本は、その誌の規定のとおりの見た目ではない。
見本は、2 段組みで組めることと、その誌の参考文献の書式で組めることを、別々に確かめる。

## 参考文献

- [Golem ADR 0385](0385-bibliography-and-citation-styles.md)
- [golem-doc ADR 0005](../golem-doc/adr/0005-bibliography-fields.md)
- [docs/research/bibliography-styles.md](../research/bibliography-styles.md)
