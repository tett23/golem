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

## 本文の中のコードの和文の改行

この節の TeX と InDesign の振る舞いは、2026-11-08 に文書とソースコードで調べたものであり、どれも実際には組んでいない。
InDesign は調べた環境で動かせず、TeX の配布も入っていなかった。
そのため、記述ごとに次のどれに当たるかを付ける。

- **文書**：公式の文書やマニュアルに書いてある。
- **ソース**：ソースコードを読んで確かめた。動かしてはいない。
- **推測**：文書とソースから導いたが、どこにも直接は書いていない。

### TeX の振る舞い

pLaTeX と upLaTeX のエンジン（pTeX、upTeX）は、和文の行分割を TeX の罰点とグルーで行う。

- **文書**：pTeX では、禁則を除いて、和文のすべての文字間で改行できる。禁則は、禁則テーブルの `\prebreakpenalty` と `\postbreakpenalty` で表す（『pTeX 系列の解説』）。和文の字のあいだには `\kanjiskip` のグルーが入る。
- **ソース**：pLaTeX の `\ttfamily` は、和文のファミリを変えない（`plfonts.dtx`）。jsclasses は、`\ttfamily` で和文のファミリをゴシックにする（`jsclasses.dtx`）。どちらでも、`\texttt` の中の和文は、和文の書体と JFM で組まれる。
- **推測**：`\texttt` と `\verb` の中の和文の字のあいだも、本文と同じく、禁則に当たらなければ罰点 0 で改行できる。JFM のグルー（括弧の前後のアキなど）も、本文と同じく入る。
- **ソース**：LaTeX の `\verb` の中の空白は改行しない空白（`\nobreakspace`）になる（`ltspace.dtx`）。`\verb` は ASCII の特殊な字のカテゴリーコードだけを変えるので、**推測**として、`\verb` では空白で改行せず、和文の字のあいだで改行する。

和文と欧文の字の境は、欧文の字の種類で決まる。

- **文書**：和文の字と欧文の字のあいだに `\xkanjiskip` を入れてよいかは、欧文の字の `\xspcode` で決まる。pTeX の既定では、英字と数字が両側で許可、ほかの字は両側で禁止である（『pTeX 系列の解説』）。
- **ソース**：pLaTeX の `kinsoku.tex` は、`(` と `[` を前側だけ、`)`、`]`、`:`、`;`、`,`、`.` などを後側だけ許可にする。`"`、`=`、`/`、`_` などは禁止のままである。`"` には `\prebreakpenalty` 10000 も与える。`\xspcode` が許さないときは、`\xkanjiskip` のグルーを差し込まない（`ptex-base.ch`）。
- **推測**：`\texttt` の中で、`日本a` と `a日本`、`日本1` の境では改行し、`日本"`、`"日本`、`日本=` の境では改行しない。`日本(` と `)日本` の境では改行する。境には `\xkanjiskip`（jsclasses では四分）のアキが付く。
- **推測**：`\texttt` の欧文の並びの中は、空白とハイフネーションの位置でだけ分かれる。`cmtt` はハイフネーションしないと見込むが、フォントの定義は読んでいない。

LuaTeX-ja は、pTeX と境の扱いが違う。

- **ソース**：LuaTeX-ja でも、`\texttt` の中の和文は和文の書体で組まれる（`lltjdefs.sty`、`ltjsclasses.dtx`）。
- **文書**：`\xkanjiskip` の挿入を抑止する場合でも、行分割を許すために長さ 0 のグルーを入れる（LuaTeX-ja の文書）。**推測**として、欧文の字の種類によらず、禁則の罰点がない限り境で改行する。
- **ソース**：`ltj-kinsoku.tex` は `"` に `prebreakpenalty` 10000 を与えるので、`日本"` の境では改行しない。
- **文書**：listings を和文に対応させる `lltjp-listings` は、字を Letter、Other、Kanji、Open、Close に分け、和文の字の前後と和文と欧文の境で行分割を許す。pLaTeX の plistings パッケージは、`lltjp-listings` をもとにしている。

### InDesign の振る舞い

- **文書**：禁則処理セット、禁則調整方式、文字組みアキ量設定は、段落の属性であり、段落パネルで選ぶ（Adobe ヘルプ、『InDesign CS3 文字組み設定の手引き』）。
- **文書**：文字組みの文字クラスは、字の例で示した分類（起こし約物、受け約物、平仮名、欧文など）であり、JIS X 4051 に基づく。
- **文書**：文字の属性の「改行なし」（No Break）は、選んだ文字列を行をまたいで分けないようにする。文字スタイルに持たせ、先頭文字スタイルや正規表現スタイルで当てる方法が紹介されている（CreativePro）。文字スタイルで改行を許す方向に変える属性は、見つからなかった。
- **推測**：等幅の書体の文字スタイルを当てた和文の字のあいだも、段落の禁則処理セットに従って改行できる。和文と欧文の字の境は、和欧間のアキが入る位置として改行できる。欧文の字の並びの中は、ハイフネーションと欧文泣き別れを除いて改行しない。文字組みアキ量も段落の属性なので、コードの中の和文の約物にも本文と同じアキが付く。

InDesign の文書には、本文の中のコードや、等幅の書体を当てた和文の改行についての記述はなかった。
日本語の技術書で、インラインのコードをどう組んでいるかを書いた DTP の実務の資料も、見つからなかった。

### Golem の振る舞い

Golem は、本文の中のコード（文字スタイル `code`）の文字列で、隣り合う二つの字の少なくとも一方が和文の字であれば、本文と同じ禁則に当たらない限り、罰点 0 で改行できるようにする。
和文の字どうしのあいだも、和文と欧文の字の境も、同じ規則である。
ASCII の字は、記号も含めてすべて JLReq の欧文用文字（cl-27）として扱う。
JLReq の表 2 は、cl-27 と平仮名、片仮名、漢字等のあいだを、どちらの順でも分割可とする。
欧文の字どうしのあいだは、今までどおり、空白、`/` の後、`_` の連なりの後だけで改行する。
コードの中には、和文の字のあいだにも境にも、アキ量のセットの空きを入れない。

この振る舞いは [golem-layout ADR 0034](golem-layout/adr/0034-line-breaks-between-japanese-characters-in-inline-code.md) で決めたものであり、まだ実装していない。
実装するまでは、本文の中のコードは、空白、`/` の後、`_` の連なりの後でしか改行せず、和文の並びは一つの改行できない並びになる。

三つと比べると、次のようになる。

| 位置 | pLaTeX、upLaTeX | LuaTeX-ja | InDesign | Golem |
| --- | --- | --- | --- | --- |
| 和文の字のあいだ | 禁則に従って改行する（推測） | 禁則に従って改行する（推測） | 段落の禁則に従って改行する（推測） | 禁則に従って改行する |
| 和文と英字、数字の境 | 改行する（推測） | 改行する（推測） | 改行する（推測） | 改行する |
| 和文と `"` の境 | 改行しない（推測） | `"` の前では改行しない（ソース） | 確かめていない | 改行する |
| 和文と `=` の境 | 改行しない（推測） | 改行する（推測） | 確かめていない | 改行する |
| コードの中のアキ | JFM のグルーと `\xkanjiskip` が入る（推測） | 確かめていない | 段落の文字組みアキ量が付く（推測） | 入れない |

Golem が `"` との境でも改行するのは、JLReq が ASCII の `"` を cl-27 にだけ挙げ、始め括弧類にも終わり括弧類にも入れていないためである。
同じ字が開きにも閉じにも使われるので、字だけでは括弧のどちらかを決められない。
本文も ASCII の字をすべて cl-27 として扱っており、コードだけ分け方を変えることはしない。

### 決めた ADR

- [golem-layout ADR 0034](golem-layout/adr/0034-line-breaks-between-japanese-characters-in-inline-code.md)（未実装）
- [golem-layout ADR 0031](golem-layout/adr/0031-line-breaks-after-low-lines-in-identifiers.md)（`_` の連なりの後の改行）

### 書き手が気をつけること

pLaTeX から移るときは、`x = "日本語"` のようなコードで、`"` が行末に残ったり、閉じる側の `"` が次の行頭に来たりすることがある。
引用符と中身を同じ行に保ちたいときは、行の前のほうで改行するよう文を組み直す。
コードの中の和文と欧文のあいだにはアキが付かないので、TeX や InDesign で組んだときより詰まって見える。
コードの中の改行の位置に、続きを示す印は描かない。
本文の中のコードに印を描くかどうかは、[golem-layout ADR 0034](golem-layout/adr/0034-line-breaks-between-japanese-characters-in-inline-code.md) で未決の事項である。

### 確かめていないこと

- InDesign で、等幅の書体の文字スタイル（合成フォントを含む）を当てた和文の改行と、和欧文の境の改行を、実際に組んで確かめていない。
- InDesign の字のクラスが、Unicode の値で決まるか、フォントの情報で決まるか。
- InDesign の文字スタイルの設定項目に、禁則と文字組みアキ量がないこと。
- pLaTeX、upLaTeX、LuaLaTeX のどれでも、`\texttt`、`\verb`、listings に和文を入れて組んでいない。確かめるには、TeX Live を入れ、狭い `\hsize` で `\texttt{あいうえおかきくけこ}`、`\texttt{あa}`、`\texttt{あ"か"}`、`\texttt{x = "日本語"}` を組み、`\showbox` で分割の位置とグルーを見る。
- pTeX で、ASCII の字の禁則テーブルの罰点が、和文の字に続かない欧文の並びの中でも罰点のノードを作るか。
- `cmtt` の `\hyphenchar`。
- url パッケージと fancyvrb の、和文を含む文字列の扱い。
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
