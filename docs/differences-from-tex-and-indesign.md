# TeX と InDesign との差異

この文書は、Golem の組版が TeX や InDesign と異なる振る舞いをまとめる。
TeX や InDesign から移ってくる書き手が、差異を一か所で引けるようにするためである。

差異ごとに一つの節を置く。
節には、TeX（と InDesign）の振る舞い、Golem の振る舞い、差異を決めた ADR、移ってくる書き手が気をつけることを書く。
この文書は仕様の一部であり、差異が変わればその都度書き換える。

## 明示したハイフンを含む語の分綴

### TeX の振る舞い

TeX は、原稿に書いたハイフンを含む語を、Liang のパターンで分綴しない。
`co-ordinate` は `co-` の後ろでだけ分けられる。
LuaTeX も、既定では同じである。

### Golem の振る舞い

Golem は、明示したハイフンを含む語を、ハイフンの直後で要素に分け、要素ごとにパターンで分綴する。
`co-ordinate` は、`co-` の後ろのほか、`ordinate` の中（`or-di-nate`）でも分けられる。
要素の中の候補は二回目の段階から使い、明示したハイフンの候補は一回目の段階から使う。
そのため、一回目の段階で収まる段落では、語は TeX と同じ位置で分かれる。
収まらない段落では、`co-ordi-nate` のように、一つの語に原稿のハイフンとパターンのハイフンが並ぶことがある。

### 決めた ADR

- [docs/adr/0179](adr/0179-lines-ending-in-explicit-hyphens.md)
- [golem-layout ADR 0008](golem-layout/adr/0008-explicit-hyphens.md)（明示したハイフンでの分割）

### 書き手が気をつけること

TeX で組んだときと、ハイフンで終わる行の位置が変わることがある。
ほとんどの語にハイフンを書いた段落の行は、要素の中で分けても詰まらないことがある。
そのような行は、`[composition]` の `expansion`（グリフの幅の伸縮）を書けば詰められる。

## 分綴の例外の語の前後に残す字の数

この節の TeX の振る舞いは、2026-11-10 に TeX Live 2026 で実際に組んで確かめたものである。
確かめた環境は、Docker のイメージ `texlive/texlive@sha256:07e8062637249c4f780ca59f42cc2ed592bc2dc1db4320769406aee3f98aa70e`（TeX Live 2026）の TeX 3.141592653（plain TeX）、pdfTeX 3.141592653-2.6-1.40.29、LuaHBTeX 1.24.0 である。
LaTeX は LaTeX2e <2026-11-01> の article クラスで、言語は既定の英語である。
パターンが分けない作り語（`abcdef`、`bcdfgh` など）に `\hyphenation` で例外を書き、`\showhyphens` が示す分割の位置を見た。
plain TeX では、`\hsize` を 1pt にして改行できる位置のすべてで改行させ、`\showbox` でも同じ位置を確かめた。

### TeX の振る舞い

plain TeX と LaTeX の既定は、`\lefthyphenmin` が 2、`\righthyphenmin` が 3 である。
TeX と pdfTeX は、`\hyphenation` に書いた語にもこの規則を当てる。
`a-bcdef` と書いても `abcdef` は分けず、`b-c-d-f-g-h` と書いた `bcdfgh` は `bc-d-fgh` の二か所でだけ分けた。
5 字に満たない語（`k-l-m`、`a-ble`）は、例外に書いても分けなかった。
`\lefthyphenmin` と `\righthyphenmin` を 1 にすると、同じ例外のすべての位置で分けたので、例外の一覧そのものは読まれている。

LuaTeX は TeX と異なる。
LuaLaTeX は、例外の語の前に 1 字、後に 1 字を残す位置でも分けた（`a-bcdef`、`stuvw-x`、`b-c-d-f-g-h`）。
一方で、`a-ble`（4 字）と `xy-z`（3 字）は分けなかった。
前後の字の数の規則は例外の位置に当てないが、短い語は例外に書いても分けない、という振る舞いである。
短い語を分けない境が 5 字（2 と 3 の和）かは、4 字以下と 5 字以上の語で確かめただけであり、境の値を変えては確かめていない。

原稿に書く任意の分割（`\-`）には、どのエンジンでも前後の字の数の規則を当てない。
plain TeX で `a\-bcdef` と `stuvw\-x` は、書いた位置で分けた。

### Golem の振る舞い

Golem は、分綴の例外の一覧（`[composition.hyphenation-exceptions]` と `@hyphenation-exceptions`）に書いた位置に、前に 2 字、後に 3 字を残す規則を当てない。
語の長さの下限もない。
`a-ble` と書けば、`a` の後で分ける。
当てると、書き手が `-` を書いた位置で分けられない理由が、一覧からは見えないからである。
ソフトハイフン（`[shy]`）にも、この規則を当てない。

TeX と比べると、次のようになる。

| 例外の書き方 | TeX、pdfTeX | LuaTeX | Golem |
| --- | --- | --- | --- |
| `a-bcdef`（前に 1 字） | 分けない | 分ける | 分ける |
| `gh-ijkl`（前に 2 字、後に 4 字） | 分ける | 分ける | 分ける |
| `stuvw-x`（後に 1 字） | 分けない | 分ける | 分ける |
| `a-ble`（4 字の語） | 分けない | 分けない | 分ける |
| `xy-z`（3 字の語） | 分けない | 分けない | 分ける |

### 決めた ADR

- [docs/adr/0272](adr/0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md)

### 書き手が気をつけること

TeX の `\hyphenation` の一覧を移すと、TeX では使われなかった位置で語が分かれることがある。
行頭や行末に 1 字だけを残したくない位置は、一覧から `-` を消す。

### 確かめていないこと

- TeX と LuaTeX のソースで、例外の位置に前後の字の数の規則を当てる処理を読んでいない。表は組んだ結果だけによる。
- LuaTeX が短い語を分けない境の値。
- `\lefthyphenmin` と `\righthyphenmin` を言語ごとに変える babel の設定での振る舞い。

## 言語の区間の外の語の分綴

この節の TeX の振る舞いは、2026-11-10 に Docker のイメージ `texlive/texlive@sha256:07e8062637249c4f780ca59f42cc2ed592bc2dc1db4320769406aee3f98aa70e`（TeX Live 2026）の LuaHBTeX 1.24.0 で実際に組んで確かめたものである。
LaTeX の article クラスで、babel に `english`、`british`、`spanish`、`italian`、`portuguese`、`dutch`、`ngerman`、`french` を読み込み、最後の `french` を主の言語にした。

### TeX の振る舞い

babel は、主の言語（オプションの最後の言語）のパターンで、言語を切り替えていない文章を分綴する。
主の言語が `french` の文書で、言語を切り替えずに書いた `proverbe` は、`\showhyphens` で `pro-verbe` に分かれた。
`\selectlanguage` と `\foreignlanguage` で言語を切り替えると、その言語のパターンと、前と後に残す字の数（`\lefthyphenmin` と `\righthyphenmin`）を使う。

babel が言語ごとに決める前と後に残す字の数は、hyph-utf8 の注記の値と、一部の言語で違った。

| 言語 | babel | hyph-utf8 |
| --- | --- | --- |
| `english`、`british` | 2、3 | 2、3 |
| `french` | 2、3 | 2、2 |
| `ngerman` | 2、2 | 2、2 |
| `spanish` | 2、2 | 2、2 |
| `italian` | 2、2 | 2、2 |
| `portuguese` | 2、3 | 2、3 |
| `dutch` | 2、3 | 2、2 |

### Golem の振る舞い

Golem も、本の言語（`manifest.toml` の `[metadata] language`）のパターンで、言語の区間の外の語を分綴する。
本の言語に同梱のパターンがなければ（`ja` など）、英語（米国）のパターンを使う。
babel の主の言語に当たるものが本の言語であり、`[lang]` と `@lang` が babel の言語の切り替えに当たる。
前と後に残す字の数は hyph-utf8 の注記の値であり、フランス語とオランダ語では babel より後に残す字が 1 字少ない。
同梱のパターンは英語（米国と英国）、フランス語、ドイツ語、スペイン語、イタリア語、ポルトガル語、オランダ語であり、ほかの言語の区間の語はパターンで分綴しない。

両用の文字（引用符やダッシュ）を和文と欧文のどちらで組むかは、区間の外では本の言語を見ず、最も近い文字で決める。
区間の外の規則のうち、本の言語を見るのは分綴だけである。

### 決めた ADR

- [ADR 0276](adr/0276-hyphenate-words-by-the-patterns-of-their-language.md)
- [ADR 0187](adr/0187-inline-language-switch.md)（言語の区間と両用の文字）

### 書き手が気をつけること

フランス語とオランダ語の本では、TeX と babel で組んだときより、語の最後の 2 字を次の行に送る分け方が増える。
英語の本の中のフランス語の語は、今までどおり `[lang fr: …]` で包まなければ英語のパターンで分けられる。
`de-1901` と `de-CH` の区間も、新正書法のパターン（`hyph-de-1996`）で分ける。

## 引用の印の中の改行

この節の LaTeX と biblatex の振る舞いは、2026-11-10 にそれぞれのソースを読んで確かめたものである（[docs/adr/0277](adr/0277-keep-the-page-label-of-a-citation-mark-with-its-value.md) の参考文献）。
組んで確かめてはいない。

### TeX の振る舞い

LaTeX の標準の `\cite` は、番号を一つずつ `\hbox` に入れ、番号のあいだの区切りを `,\penalty\@m\ ` とする（`ltbibl.dtx`）。
番号の区切りの後では、罰点 1000 で分けうる。
後置きの文言の前の `, ` は、普通の空白である。

biblatex の `numeric-comp` は、番号の区切り（`\multicitedelim`）を `\addcomma\space` とし、範囲のダッシュ（`\bibrangedash`）を分けうるダッシュとする。
頁の文言と値のあいだは `\ppspace` であり、その既定は改行しない空白（`\addnbspace`）である。
後置きの前の区切り（`postnotedelim`）は `\addcomma\space` で、分けうる。

### InDesign の振る舞い

InDesign は、引用と参考文献を組む組み込みの機能を持たない。
印は書き手が地の文として打つ文字列なので、印に固有の規則はない。

### Golem の振る舞い

Golem は、biblatex の `numeric-comp` に合わせる。
頁の文言（`p.`、`pp.`）と値のあいだでは改行しない。
番号の区切りの `, ` と `; ` の後、範囲の `–` の後、位置の前の `, ` の後は、地の文と同じ規則で分けうる。
LaTeX の標準の `\cite` の、番号の区切りの後の罰点 1000 は採らず、地の文の語間と同じにする。
範囲の `–` の後の罰点は、`explicit-hyphen-penalty` の既定の 50 であり、TeX の `\hyphenpenalty` の既定と同じである。
HTML と EPUB では、頁の文言と値のあいだを U+00A0 で書く。

### 決めた ADR

- [docs/adr/0277](adr/0277-keep-the-page-label-of-a-citation-mark-with-its-value.md)

### 書き手が気をつけること

LaTeX の標準の `\cite` で組んだときより、番号の区切りの後で行が分かれやすい。
印の全体を一行に置きたいときは、`[style no-break: [cite …]]` と書く。

## 段落の前後のアキの合わせ方

### InDesign の振る舞い

InDesign は、前の段落の段落後のアキと、次の段落の段落前のアキを足す。
後のアキが 1 行の段落の後に、前のアキが 1 行の段落が来ると、2 行空く。

### Golem の振る舞い

Golem は、違う段落スタイルの段落のあいだでは、前の段落の `space-after` と次の段落の `space-before` のうち大きいほうを取る。
上の例では 1 行空く。
同じ段落スタイルの段落のあいだでは、`space-between` だけを取り、前後のアキを使わない。
複数の段落からなる引用の段落のあいだに、前後のアキが入らないようにするためである。
HTML と EPUB では、CSS の余白の相殺と同じ結果になる。

### 決めた ADR

- [docs/adr/0189](adr/0189-paragraph-alignment-spacing-and-end-indent.md)

### 書き手が気をつけること

InDesign の版下を移すときは、前後のアキの値を読み替える。
二つのアキを足した空きが要るなら、どちらかの値を和にする。

## 段落の前後のアキの単位

### InDesign の振る舞い

InDesign は、段落前と段落後のアキを長さで書く。

### Golem の振る舞い

Golem は、`space-before` と `space-after` を行の格子の行の数で書く。
`space-between` と同じく、行の格子を崩さないためである。
長さ（`mm` や `zw`）では書けない。

### 決めた ADR

- [docs/adr/0189](adr/0189-paragraph-alignment-spacing-and-end-indent.md)

### 書き手が気をつけること

InDesign で長さで書いたアキは、行送りで割った行の数に直す。

## 縦組みのノド側と小口側の揃え

### InDesign の振る舞い

InDesign は、縦組みのフレームでは、ノド側に揃える指定と小口側に揃える指定を適用しない。

### Golem の振る舞い

Golem は、縦組みの本で `align = "towards-spine"` か `align = "away-from-spine"` を書くと、エラー（G03118）として止める。
書いた値を黙って適用しない出力を作らないためである。

### 決めた ADR

- [docs/adr/0189](adr/0189-paragraph-alignment-spacing-and-end-indent.md)

### 書き手が気をつけること

横組みと縦組みを切り替える本では、段落スタイルの `align` も書き換える。

## 最終行右インデント

### InDesign の振る舞い

InDesign は、段落の最後の行だけの終わりの側の字下げ（最終行右インデント）を持つ。

### Golem の振る舞い

Golem は、最後の行だけの終わりの側の字下げを持たない。
すべての行の終わりの側の字下げは、段落スタイルの `end-indent` で書く。

### 決めた ADR

- [docs/adr/0189](adr/0189-paragraph-alignment-spacing-and-end-indent.md)

### 書き手が気をつけること

最終行右インデントを使った段落は、`end-indent` か、ほかの揃えで組み直す。

## 行の調整の優先と伸びの上限

### TeX の振る舞い

TeX は、行を詰める行と空ける行を同じ式で量る。
不良度は、足りない幅か余る幅を行の伸びか縮みの合計で割った比 r から、約 100 |r|³ で求める。
和文の行は伸びの合計が大きく縮みの合計が小さいので、この式では、約物の空きを詰めて字を前の行に入れる（追い込む）より、字を次の行に送って字間を空ける（追い出す）ほうが選ばれやすい。

### InDesign の振る舞い

InDesign の段落の禁則調整方式（追い込み優先、追い出し優先、追い出しのみ、調整量を優先）が、この選択にあたると考えられる。
Golem の開発の環境で InDesign を動かせないので、振る舞いは確かめていない。

### Golem の振る舞い

既定（段落スタイルの `line-adjustment = "pull-in-first"`）では、グルーの縮みだけで収まる詰める行の不良度を 0 とし、JLReq の 3.8.2 のとおり追い込みを優先する。
優先は、一行ずつ前から決める方式ではなく、段落の全体の罰点の差として入れたので、詰めた行の後の行が大きく空く場合は追い出しを選ぶことがある。
`"balanced"` と書けば、TeX と同じ量り方に戻る。
段落スタイルの `stretch-limit` で、行のグルーを伸ばす比に上限を置ける。
上限を超える分は行末に残し、行末がそろわない。

### 決めた ADR

- [ADR 0274](adr/0274-prefer-pulling-in-and-limit-the-stretch-of-lines.md)

### 書き手が気をつけること

TeX や以前の Golem で組んだ本と、行の分かれ方が違いうる。
英語の本で語間が詰まった行が増えたと感じるなら、段落スタイルに `line-adjustment = "balanced"` を書く。

## 行の調整で詰める箇所と空ける箇所の順

### TeX の振る舞い

TeX は、決まった行の足りない幅か余る幅を、行のすべてのグルーに同じ比で配る。
語間の空白も約物の空きも、伸びか縮みに比例して同じ割合で動く。
グルーの伸びに無限の次数（fil、fill、filll）があるときは、高い次数のグルーだけが伸びる。

### InDesign の振る舞い

InDesign の文字組みアキ量設定には、行の調整の優先順位に当たる設定があると考えられる。
Golem の開発の環境で InDesign を動かせないので、振る舞いは確かめていない。

### Golem の振る舞い

Golem は、JLReq の 3.8.3 と 3.8.4 のとおり、行を詰める箇所と空ける箇所を段に分け、前の段から限度まで使う。
既定の詰める順は欧文間隔、中点類の前後、括弧類と読点類、和欧間であり、空ける順は欧文間隔、和欧間、字間である。
すべての段で空けても足りない行は、伸びるすべてのグルーを、文字の大きさに比例して同じ em の数だけ空ける。
順は段落スタイルの `shrink-order` と `stretch-order` で書き換えられ、どちらも行の分け方を変えない。

### 決めた ADR

- [ADR 0278](adr/0278-use-the-places-of-line-adjustment-in-the-order-of-jlreq.md)

### 書き手が気をつけること

行の分け方とページは変わらないが、行の中の字の位置は、TeX や以前の Golem で組んだ本と違う。
すべてのグルーを同じ割合で詰める前の組み方に戻すには、段落スタイルに `shrink-order = []` を書く。

## 数と単位の泣き別れ

### TeX と InDesign の振る舞い

JLReq は、数と和字の単位や助数詞のあいだ（`100｜円`）を分割禁止としない。
TeX の和文の組版がこの位置をどう扱うかは、組んで確かめていない。
InDesign がこの位置をどう扱うかは、Golem の開発の環境で InDesign を動かせないので確かめていない。

### Golem の振る舞い

既定（`[composition]` の `number-unit-penalty = 10000`）では、アラビア数字とその後の仮名か漢字のあいだで改行しない。
10000 より小さい値を書けば、その罰点で分けてよい候補になる。
人名と熟語は自動では分けないので、書き手が文字スタイル `no-break` で包む。

### 決めた ADR

- [ADR 0275](adr/0275-keep-numbers-with-the-units-after-them.md)

### 書き手が気をつけること

数の多い段落と狭い表のセルでは、ほかの組版より空いた行かはみ出す行が増えうる。
JLReq どおりに分けてよい本では、`number-unit-penalty` に 10000 より小さい値を書く。

## 禁則の文字の分類と分割禁止の字の組

### InDesign の振る舞い

InDesign は、禁則文字セットで、行頭禁則、行末禁則、ぶら下げ、分離禁止の字を決める。
既定の禁則文字セットの字の一覧は、Golem の開発の環境で InDesign を動かせないので確かめていない。

### Golem の振る舞い

Golem は、字の分類と分割禁止の字の組を、JLReq の付録の文字クラス一覧と 3.1.10 の記述に従って決める。
`⦅`、`⦆`、`〞`、`～`、`⸺`、`⸻` を JLReq の分類に足し、連数字（横組み）、前置省略記号と数、数と後置省略記号のあいだでは改行しない（仕様書の「行分割」の節）。
InDesign の既定の禁則文字セットとは、字ごとに比べていない。

### 決めた ADR

- [golem-layout ADR 0049](golem-layout/adr/0049-align-the-character-classes-and-unbreakable-pairs-with-jlreq.md)

### 書き手が気をつけること

InDesign で組んだ本と、行頭と行末に来る字や、数と記号の分かれ方が違いうる。
`100％` の `％` の前で分けたい本でも、Golem は分けない。

## 本文の中のコードの和文の改行

この節の TeX の振る舞いは、2026-11-08 に TeX Live 2026 で実際に組んで確かめたものである。
InDesign の振る舞いは、調べた環境で動かせなかったので、文書から調べたものにとどまる。
記述ごとに次のどれに当たるかを付ける。

- **観察**：実際に組み、`\showbox` の出力で行の分かれ方とノードを見た。
- **文書**：公式の文書やマニュアルに書いてある。
- **推測**：観察と文書から導いたが、組んで確かめてはいない。

### 確かめた環境

- Docker のイメージ `texlive/texlive@sha256:07e8062637249c4f780ca59f42cc2ed592bc2dc1db4320769406aee3f98aa70e`（TeX Live 2026）。
- pLaTeX：e-upTeX 3.141592653-p4.1.2-u2.02-251130-2.6（utf8.euc）、pLaTeX2e <2023-02-14>+1、LaTeX2e <2026-11-01>、pldefs.ltx 2021/01/10 v1.7k、jsarticle.cls 2025/04/27、jarticle.cls 2020/09/30 v1.8f。
- upLaTeX：同じ e-upTeX（utf8.uptex）、pLaTeX2e <2023-02-14u04>+1、upldefs.ltx 2020/02/01 v1.6v-u02、ujarticle.cls 2020/09/30 v1.8f-u00、jsarticle.cls 2025/04/27（`uplatex` のオプション）。
- LuaLaTeX：LuaHBTeX 1.24.0、LaTeX2e <2026-11-01>、luatexja.sty 2026-10-29、ltjsarticle.cls 2026-10-25、lltjcore.sty 2026-10-26、lltjp-listings.sty 2025-09-21、lltjp-fancyvrb.sty 2026-04-18。
- 共通のパッケージ：listings 1.11b（2025/11/14）、fancyvrb 4.8（2026/10/20）、fvextra v1.14.0（2026/02/25）、url 3.4（2013/09/16）。
- plistings と jlisting は、このイメージに入っていない。pLaTeX と upLaTeX の listings は、素の listings で組んだ。

組み方は三通りである。
8 字の幅の段落で組んだもの、`\hsize=0pt` にして改行できる位置のすべてで改行させたもの、`\hbox` に入れて字のあいだのペナルティとグルーを見たものである。
クラスは、pLaTeX では jsarticle と jarticle、upLaTeX では ujarticle と jsarticle、LuaLaTeX では ltjsarticle の五つの組で組んだ。

### TeX の振る舞い

`\texttt` の中の和文は、本文の和文と同じ位置で改行する。

- **観察**：五つの組のすべてで、`\texttt` の中の和文の行の分かれ方は、同じ文字列を本文で組んだものと同じだった。和文の字のあいだはどこでも改行でき、`。`、`、`、`」` の前と `「` の後では改行しなかった。小書きの仮名の前には罰点 150 が入った。
- **観察**：`\ttfamily` は、jsarticle と ltjsarticle では和文をゴシックに変え、jarticle と ujarticle では変えなかった。どちらでも、改行できる位置は変わらなかった。
- **観察**：`\texttt` の中でも、和文の字のあいだの `\kanjiskip` と、和文と英字のあいだの `\xkanjiskip` が入った。jsarticle の `\xkanjiskip` は 2.5pt（伸び 1.49994pt、縮み 0.59998pt）である。
- **観察**：`\texttt` の中の空白では改行した。英字だけの並び（`foo`、`"config.toml"`）の中では改行しなかった。

和文と ASCII の記号の境は、記号の禁則の罰点で決まる。

- **観察**：五つの組のすべてで、`"` の後の和文（`"日`）の前では改行し、和文の後の `"`（`ジ"`）の前では改行しなかった。`"` の前には `\penalty 10000` が入った。pLaTeX の `kinsoku.tex` は `"` に `\prebreakpenalty` 10000 を与えている。
- **観察**：`(設定)` は `(` の後と `)` の前で改行しなかった。どちらにも `\penalty 10000` が入った。
- **観察**：pTeX と upTeX は、`"` と和文のあいだに `\xkanjiskip` を入れないが、改行はできた。LuaTeX-ja は、そこに幅 0 のグルーを入れた。
- **推測**：`=` は禁則の罰点を持たないので、和文と `=` の境でも改行すると見込む。`日本=` の並びは組んでいない。

`\verb` は、空白でだけ改行を止める。

- **観察**：五つの組のすべてで、`\verb` の中の空白の前には `\penalty 10000` が入り、空白では改行しなかった。和文の字のあいだは `\texttt` と同じく改行でき、禁則も同じく働いた。
- **観察**：`\verb` の中の和文と英字の境は、pTeX と upTeX では `\xkanjiskip` で改行でき、LuaTeX-ja では幅 0 のグルーで改行できた。

コードを組むパッケージは、エンジンによって振る舞いが分かれる。

- **観察**：LuaLaTeX の listings（`breaklines=true`、lltjp-listings が自動で読まれる）は、和文の字ごとに改行の位置を作り、和文の中でも改行した。行頭の `。`、`、`、`」` と行末の `「` は、3 字から 9 字のどの幅でも起きなかった。`prebreak` と `postbreak` を書くと、和文の中で改行した行の行末と次の行頭にも、その印が付いた。既定では印は付かない。
- **観察**：pLaTeX と upLaTeX の素の listings は、和文を含む行の字の順序を崩した（`"` が和文の後ろに回るなど）。`prebreak` と `postbreak` を書いても、印は出なかった。和文だけの行では、禁則に当たる改行は起きなかった。
- **観察**：fancyvrb の `Verbatim` は、和文の中でも改行しなかった。fvextra の `breaklines` は、和文の字のあいだで改行し、続きの行の左に `↪`（`\hookrightarrow`）を付けた。`breakanywhere` を足すと、どのエンジンでも行頭に `。` や `」` が来て、禁則が破れた。
- **観察**：url パッケージの `\url` は、pTeX と upTeX では和文の字のあいだで改行し、禁則が破れた（行頭の `。`、行末の `「`）。禁則のペナルティのノードが一つもなかった。LuaTeX-ja では、和文の中で改行しなかった。

### InDesign の振る舞い

- **文書**：禁則処理セット、禁則調整方式、文字組みアキ量設定は、段落の属性であり、段落パネルで選ぶ（Adobe ヘルプ、『InDesign CS3 文字組み設定の手引き』）。
- **文書**：文字組みの文字クラスは、字の例で示した分類（起こし約物、受け約物、平仮名、欧文など）であり、JIS X 4051 に基づく。
- **文書**：文字の属性の「改行なし」（No Break）は、選んだ文字列を行をまたいで分けないようにする。文字スタイルに持たせ、先頭文字スタイルや正規表現スタイルで当てる方法が紹介されている（CreativePro）。文字スタイルで改行を許す方向に変える属性は、見つからなかった。
- **推測**：等幅の書体の文字スタイルを当てた和文の字のあいだも、段落の禁則処理セットに従って改行できる。和文と欧文の字の境は、和欧間のアキが入る位置として改行できる。欧文の字の並びの中は、ハイフネーションと欧文泣き別れを除いて改行しない。文字組みアキ量も段落の属性なので、コードの中の和文の約物にも本文と同じアキが付く。

InDesign の文書には、本文の中のコードや、等幅の書体を当てた和文の改行についての記述はなかった。
日本語の技術書で、インラインのコードをどう組んでいるかを書いた DTP の実務の資料も、見つからなかった。

### Golem の振る舞い

Golem は、本文の中のコード（文字スタイル `code`）の文字列で、隣り合う二つの字の少なくとも一方が和文の字であれば、本文と同じ禁則に当たらない限り、罰点 0 で改行できる。
和文の字どうしのあいだも、和文と欧文の字の境も、同じ規則である。
ASCII の字は、記号も含めてすべて JLReq の欧文用文字（cl-27）として扱う。
JLReq の表 2 は、cl-27 と平仮名、片仮名、漢字等のあいだを、どちらの順でも分割可とする。
欧文の字どうしのあいだは、空白、`/` の後、`_` の連なりの後、`-` と `.` の連なりの後だけで改行する。
`-` と `.` の連なりの後は、前と後の字がどちらも欧文の字で、`/` でも `_` でもなく、ともに数字ではないときだけ、罰点 100 で改行する（[golem-layout ADR 0045](golem-layout/adr/0045-break-inline-code-after-hyphens-and-full-stops-to-avoid-loose-lines.md)）。
コードの中には、和文の字のあいだにも境にも、アキ量のセットの空きを入れない。
空白でない位置で改行した行の行末には、文字スタイル `code` の `wrap-mark`（既定は `⏎`）を描く。
空白で改行した行には描かない。
印は、コードの字の 3/5 の大きさで、コードの色の半分の色で描く。
既定の `⏎` は、書体の字形でなく、細い線の小さな矢印の図形で描く。

この振る舞いは [golem-layout ADR 0034](golem-layout/adr/0034-line-breaks-between-japanese-characters-in-inline-code.md) で決め、印の描き方は [golem-layout ADR 0042](golem-layout/adr/0042-draw-the-wrap-mark-of-inline-code-small-and-light.md) で決めた。

TeX と InDesign と比べると、次のようになる。
TeX の列は `\texttt` の振る舞いであり、五つの組で同じだった。

| 位置 | pLaTeX、upLaTeX | LuaTeX-ja | InDesign | Golem |
| --- | --- | --- | --- | --- |
| 和文の字のあいだ | 禁則に従って改行する（観察） | 禁則に従って改行する（観察） | 段落の禁則に従って改行する（推測） | 禁則に従って改行する |
| 和文と英字、数字の境 | 改行する（観察） | 改行する（観察） | 改行する（推測） | 改行する |
| 和文の後の `"` の前 | 改行しない（観察） | 改行しない（観察） | 確かめていない | 改行する |
| `"` の後の和文の前 | 改行する（観察） | 改行する（観察） | 確かめていない | 改行する |
| `(` の後と `)` の前 | 改行しない（観察） | 改行しない（観察） | 確かめていない | 改行する |
| 和文と `=` の境 | 改行する（推測） | 改行する（推測） | 確かめていない | 改行する |
| コードの中のアキ | `\kanjiskip` と `\xkanjiskip` が入る（観察） | `\texttt` では入り、`\verb` の和欧の境は幅 0（観察） | 段落の文字組みアキ量が付く（推測） | 入れない |
| 改行した位置の印 | `\texttt` には付かない（観察） | `\texttt` には付かない。listings は `prebreak` を書けば付く（観察） | 確かめていない | 行末に `wrap-mark` を描く |

Golem が `"`、`(`、`)` との境でも改行するのは、JLReq が ASCII の `"` を cl-27 にだけ挙げ、始め括弧類にも終わり括弧類にも入れていないためである。
同じ字が開きにも閉じにも使われるので、字だけでは括弧のどちらかを決められない。
`(` と `)` も、JLReq の約物のクラスの表に挙がるのは全角の字形である。
本文も ASCII の字をすべて cl-27 として扱っており、コードだけ分け方を変えることはしない。
pTeX と LuaTeX-ja は、`kinsoku.tex` と `ltj-kinsoku.tex` で ASCII の記号に禁則の罰点を与えるので、この三つの位置で Golem と分かれる。

長いコードの前後では、TeX と Golem の出力が分かれる。
許容度の範囲に分割がないとき、TeX は最後の段階で行長からはみ出す行を作り、Overfull \hbox を報告する。
Golem は、行長に収まる分割の候補がある限りはみ出す行を作らず、収まらない箱を次の行へ送り出すので、同じ入力で字間の空いた行を作る（[docs/adr/0210](adr/0210-warn-overfull-lines-in-build.md)）。
TeX Live 2026 の pLaTeX と jsarticle で、`actions/attest-build-provenance` を含む文を 40 字の行に組むと、`\texttt` と url パッケージの `\url` は一行めをはみ出させた（観察）。
url パッケージは、`hyphens` のオプションを付けたときだけ `-` の後で改行し、そのときは一行めを `actions/attest-build-` で終えた（観察）。
Golem は、`hyphens` のオプションに当たる改行を文字スタイル `code` に既定で当て、`-` に加えて `.` の後でも改行する。
`-` は字のまま行末に残るので、書いたハイフンと改行のためのハイフンの区別は、行末の `wrap-mark` が受け持つ。
文字スタイル `url` は、url パッケージの既定と同じく `-` の後で改行しない。

### 決めた ADR

- [golem-layout ADR 0034](golem-layout/adr/0034-line-breaks-between-japanese-characters-in-inline-code.md)
- [golem-layout ADR 0031](golem-layout/adr/0031-line-breaks-after-low-lines-in-identifiers.md)（`_` の連なりの後の改行）
- [golem-layout ADR 0042](golem-layout/adr/0042-draw-the-wrap-mark-of-inline-code-small-and-light.md)（改行の印の描き方）
- [golem-layout ADR 0045](golem-layout/adr/0045-break-inline-code-after-hyphens-and-full-stops-to-avoid-loose-lines.md)（`-` と `.` の連なりの後の改行）

### 書き手が気をつけること

pLaTeX から移るときは、`x = "日本語"` のようなコードで、`"` が行末に残ったり、閉じる側の `"` が次の行頭に来たりすることがある。
`(` が行末に残ることも、`)` が次の行頭に来ることもある。
引用符と中身を同じ行に保ちたいときは、行の前のほうで改行するよう文を組み直す。
コードの中の和文と欧文のあいだにはアキが付かないので、TeX で組んだときより詰まって見える。
空白でない位置で改行したコードの行末には、`⏎` が付く。
fvextra の `breaklines` は続きの行の行頭に印を付けるが、Golem は改行した行の行末に付ける。
印の大きさと線の細さは fvextra と同じ考え方である。
fvextra の既定の印（`breakanywheresymbolpre`）は、10pt の文書で 6pt の、細い線の `⌋` である。
Golem の既定の印も、コードの字の 3/5 の大きさの、細い線の矢印であり、本文の字より明らかに小さく細く描く。
fvextra の印の色は本文と同じだが、Golem は印をコードの色の半分の色で淡く描く。
印を描きたくなければ、`[character-styles.code]` に `wrap-mark = ""` と書く。
`\verb` と違い、Golem の本文の中のコードは空白でも改行する。

### 確かめていないこと

- InDesign で、等幅の書体の文字スタイル（合成フォントを含む）を当てた和文の改行と、和欧文の境の改行を、実際に組んで確かめていない。
- InDesign の字のクラスが、Unicode の値で決まるか、フォントの情報で決まるか。
- InDesign の文字スタイルの設定項目に、禁則と文字組みアキ量がないこと。
- TeX で、和文と `=` が隣り合う並びを組んでいない。
- plistings を使った pLaTeX と upLaTeX の listings。確かめたイメージに入っていなかった。
- `\texttt` の英字の並びの中で改行しない理由。tt の書体の `\hyphenchar` は読んでいない。
- LuaTeX-ja で、`\verb` の中の和欧の境に `\xkanjiskip` が入らない理由。
- 日本語の技術書の出版社が、InDesign でインラインのコードをどう組んでいるか。

### 参考文献

参照日はすべて 2026-11-08。

- Adobe. 禁則処理設定の使用（InDesign ヘルプ）. https://helpx.adobe.com/jp/indesign/desktop/language-and-proofing/chinese-japanese-and-korean/use-kinsoku-settings.html
- Adobe. CJK テキストの書式設定（InDesign ヘルプ）. https://helpx.adobe.com/jp/indesign/desktop/language-and-proofing/chinese-japanese-and-korean/format-cjk-text.html
- Adobe. 間隔クラスと約物タイプ（InDesign ヘルプ）. https://helpx.adobe.com/jp/indesign/desktop/language-and-proofing/chinese-japanese-and-korean/spacing-classes-and-yakumono-types.html
- Adobe. ハイフネーションと単語分割の制御（InDesign ヘルプ）. https://helpx.adobe.com/jp/indesign/desktop/format-and-style-text/composition-and-text-wrapping/control-hyphenation-and-word-breaks.html
- Adobe. Adobe InDesign CS3 文字組み設定の手引き（3 節、5.6 節、6 節）. https://www.adobe.com/jp/print/pdfs/mojikumiWPCS3_web.pdf
- CreativePro. Controlling Line Breaks with Nested Styles. https://creativepro.com/controlling-line-breaks-with-nested-styles/
- CreativePro. Turning Off Hyphenation for URLs. https://creativepro.com/turning-off-hyphenation-for-urls/
- W3C. Requirements for Japanese Text Layout（JLReq）（3.2.6 節、付録 A、付録 C）. https://www.w3.org/TR/jlreq/
- W3C. JLReq Table 2 Possibility of separation between characters. https://www.w3.org/TR/jlreq/tables/table_en3.pdf
- 日本語 TeX 開発コミュニティ. pTeX 系列の解説（ptex-manual）の禁則. https://github.com/texjporg/ptex-manual/blob/cdb9dcf825062041f02104c7e6e8ea7e1d66ef09/ptex-manual.tex#L1847-L1866
- 日本語 TeX 開発コミュニティ. pTeX 系列の解説（ptex-manual）の `\kanjiskip`、`\xkanjiskip`、`\xspcode`、`\noautoxspacing`. https://github.com/texjporg/ptex-manual/blob/cdb9dcf825062041f02104c7e6e8ea7e1d66ef09/ptex-manual.tex#L2031-L2155
- pTeX の変更のファイル. https://github.com/texjporg/tex-jp-build/blob/efdafcea93fa9ee4f958aae272030cc1f7671b31/source/texk/web2c/uptexdir/ptex-base.ch#L7681-L7812
- pLaTeX `kinsoku.tex`. https://github.com/texjporg/platex/blob/627d847e1275067521c3a5032f4563cc0dbd55cb/kinsoku.tex
- pLaTeX `plfonts.dtx`（`\fontfamily`）. https://github.com/texjporg/platex/blob/627d847e1275067521c3a5032f4563cc0dbd55cb/plfonts.dtx#L2456-L2589
- pLaTeX `plcore.dtx`（`\verb`、`\do@noligs`）. https://github.com/texjporg/platex/blob/627d847e1275067521c3a5032f4563cc0dbd55cb/plcore.dtx
- jsclasses `jsclasses.dtx`（`ttfamily` のフック）. https://github.com/texjporg/jsclasses/blob/5b85f2cd76e6255837f31823d0f15ff464da8b0e/jsclasses.dtx#L1257-L1301
- LaTeX `ltspace.dtx`（`\@xobeysp`）. https://github.com/latex3/latex2e/blob/910abf03262d81961d0a1ce582b3202331218065/base/ltspace.dtx#L1291-L1350
- LuaTeX-ja の文書 `luatexja.dtx` の `\xkanjiskip` の抑止と長さ 0 のグルー. https://github.com/luatexja/luatexja/blob/4f10414927f439cb1197593b0d310b2e90802ae9/doc/luatexja.dtx#L11006-L11019
- LuaTeX-ja の文書 `luatexja.dtx` の `lltjp-listings` の文字種. https://github.com/luatexja/luatexja/blob/4f10414927f439cb1197593b0d310b2e90802ae9/doc/luatexja.dtx#L11444-L11560
- LuaTeX-ja `ltj-kinsoku.tex`. https://github.com/luatexja/luatexja/blob/4f10414927f439cb1197593b0d310b2e90802ae9/src/ltj-kinsoku.tex
- LuaTeX-ja `lltjdefs.sty`. https://github.com/luatexja/luatexja/blob/4f10414927f439cb1197593b0d310b2e90802ae9/src/patches/lltjdefs.sty#L88-L110
- LuaTeX-ja `ltjsclasses.dtx`. https://github.com/luatexja/luatexja/blob/4f10414927f439cb1197593b0d310b2e90802ae9/src/ltjsclasses.dtx#L1009-L1057
- plistings. https://github.com/h-kitagawa/plistings/blob/ca9bd3bf6a13bd501544c58e34c7c612b7dd567a/README.md
- fvextra（`breaklines`、`breaksymbolleft`、`breakanywhere`）. https://github.com/gpoore/fvextra/blob/b22ac9e0806479bfe69bf6f2fd2c052b50a3b5cf/fvextra/fvextra.dtx#L1071-L1216
- TeX Live の Docker のイメージ `texlive/texlive@sha256:07e8062637249c4f780ca59f42cc2ed592bc2dc1db4320769406aee3f98aa70e`. https://hub.docker.com/r/texlive/texlive
