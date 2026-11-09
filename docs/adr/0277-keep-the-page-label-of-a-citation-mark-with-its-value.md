# ADR 0277: 引用の印の頁の文言と値を、行末と次の行頭に分けない

ステータス: 採択（未実装）

## 文脈

### 引用の印の中で行が分かれる

[ADR 0266](0266-citation-locators-and-multiple-keys.md) は、PDF の本文の引用の印を `[1, 3–5, 7]`、`[1–3]`、`[1, p. 5]`、`[1, pp. 5–7]` の形で組むことにした。
印は、`citationPieces` の片をつないだ一つの文字列として組む（[`Japanese.hs` の 646 行](https://github.com/tett23/golem/blob/574a21f56c0d438412547e41a54664fb941de0b7/modules/golem-layout/src/Golem/Layout/Japanese.hs#L646)）。
位置は、区切りの `, ` と合わせて一つの `CiteText` の片になる（[`Citation.hs` の 46 行から 48 行](https://github.com/tett23/golem/blob/574a21f56c0d438412547e41a54664fb941de0b7/modules/golem-doc/src/Golem/Doc/Citation.hs#L46-L48)、[`locatorText`](https://github.com/tett23/golem/blob/574a21f56c0d438412547e41a54664fb941de0b7/modules/golem-doc/src/Golem/Doc/Citation.hs#L66-L79)）。
そのため、印の中の空白は地の文の欧文の語間と同じグルーになり、分割の候補になる。
`–` の後も、欧文の語の明示のダッシュとして候補になる（[golem-layout ADR 0008](../golem-layout/adr/0008-explicit-hyphens.md)）。

[ADR 0266](0266-citation-locators-and-multiple-keys.md) は、印の中で行を分けるかを決めていない。
不変条件（I1 から I8）は印の文字列だけを述べ、境界の入力の表にも行の幅はない。
仕様書の「引用と参考文献」の節と「行分割」の節も、印の中の分割に触れていない。
[ADR 0267](0267-pdf-bookmarks-and-links-inside-the-document.md) は印の番号を PDF のリンクにするが、頁の指定の文字をリンクに含めるかを [ADR 0266](0266-citation-locators-and-multiple-keys.md) の組み方に委ねており、分割も決めていない。
[ADR 0267](0267-pdf-bookmarks-and-links-inside-the-document.md) のステータスは採択（未実装）である。

### 今の振る舞い

この節の観察は、2026-11-10 に origin/main（`574a21f5`）の `golem` を組み立て、`golem new` の雛形（A6、Noto Serif JP）の行長を 12 字にした本で組んだ結果である。
段落は `あ` を n 字並べた後に `[cite …]` と仮名を続けたもので、n を変えて印が行末に来る位置をずらした。
PDF を shem で画像にして、横組みと縦組みの両方を見た。

| 原稿 | 前の行の終わり | 次の行の始め |
| --- | --- | --- |
| `あ`×8 `[cite a page=5...7]` | `[1, pp.` | `5–7]` |
| `あ`×7 `[cite a page=5...7]` | `[1, pp. 5–` | `7]` |
| `あ`×10 `[cite a c e]`（`[1–3]`） | `[1–` | `3]` |
| `あ`×11 `[cite a b]`（`[1, 4]`） | `[1,` | `4]` |

縦組みでも同じ位置で分かれた。
頁の文言 `pp.` だけが行末に残り、値が次の行頭に送られる組み方は、読み手が `pp.` から値を探して行を移ることになる。

### 拠るもの

仕様書は、組版の振る舞いを JLReq、InDesign、TeX と LaTeX の順に拠って決めるとする（[仕様書の「仕様が不明瞭な場合」](../specifications.md#仕様が不明瞭な場合)）。

- JLReq は、引用の印の中の分割を定めていない。欧文の扱いでは、欧文の単語をハイフネーションの位置のほかで分けないことと、追込みと追出しで欧文間隔（cl-26）を優先して使うことを定める（JLReq の節 `#handling_of_western_text_in_japanese_text_using_proportional_western_fonts`）。語間の空白で分けることは禁じていない。分割禁止（3.1.10）は、アラビア数字と後置の省略記号（`%` など）のあいだを分けないとするが、前置きの略語と数のあいだ（`p. 5`）には触れていない。
- InDesign は、引用と参考文献を組む組み込みの機能を持たない（[ADR 0266](0266-citation-locators-and-multiple-keys.md) の調査による）。印は書き手が地の文として打つ文字列なので、印に固有の規則はない。
- LaTeX の標準の `\cite` は、番号を一つずつ `\hbox` に入れて番号の中で分けず、番号のあいだの区切りを `,\penalty\@m\ ` とする（`ltbibl.dtx`）。区切りの後では、罰点 1000 で分けうる。後置きの文言の前の `, ` は普通の空白である。
- biblatex は、[ADR 0266](0266-citation-locators-and-multiple-keys.md) が既定の書式の手本にした `numeric-comp` で、番号の区切り（`\multicitedelim`）を `\addcomma\space`、範囲のダッシュ（`\bibrangedash`）を罰点 `\hyphenpenalty` で分けうるダッシュ（「breakable dash」）とする。頁の文言と値のあいだは `\ppspace` で、その既定は改行しない空白（`\addnbspace`、`\nobreak\space`）である（`biblatex.sty` の `\blx@mkpageprefix`）。後置きの前の区切り（`postnotedelim`）は `\addcomma\space` で、分けうる。

JLReq と InDesign が決めないので、仕様書の順により LaTeX に拠る。
[ADR 0266](0266-citation-locators-and-multiple-keys.md) が手本にした biblatex の規則では、印の中で分けないのは頁の文言と値のあいだだけであり、番号のあいだの区切りの後と、範囲のダッシュの後では分けうる。
今の Golem は、頁の文言と値のあいだでも分ける点だけが biblatex と違う。
`–` の後の罰点は、Golem の `explicit-hyphen-penalty` の既定（50）も TeX の `\hyphenpenalty` の既定（50）も同じである。

### 印の全体を分けないこと

印の全体を一つの改行しない範囲（[ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md)）にすれば、印はいつも一行に収まる。
ただし、拠るものの順で手本になる LaTeX と biblatex はそうしていない。
印は複数の文献で長くなりうる（`[1, 3, 5, 7, 9, 11]` は 19 字の文字列である）。
行長の短い縦組みの本や表のセルで、印の全体を次の行へ送れば、前の行の字のあいだが大きく空く。
範囲が行長を超えれば、はみ出す行ができる。
「メンテナーが決めること」の 1 で、退けた案として比べる。

## 実装すること

### 1. 頁の文言と値を分けない

PDF の行分割で、引用の印の位置の文言（`p.`、`pp.`）と、その後の値（`5`、`5–7`、`xii`）のあいだでは行を分けない。

- 文言と値のあいだの語間のグルーの前に、罰点 10000 の項目を置く。グルーの幅と伸び縮みは変えない。[ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md) の改行しない範囲がグルーの前に置く項目と同じ形である。
- 印のほかの位置（`[` の後、番号の区切りの `, ` と `; ` の後、範囲の `–` の後、位置の前の `, ` の後、`]` の前）は、今のとおりの規則で決める。`[` の後と `]` の前は、今のとおり禁則で分けない。
- 値の中の位置（`5–7` の `–` の後、`LocText` の中の空白）も、今のとおりの規則で決める（「メンテナーが決めること」の 2）。
- 横組みと縦組みで同じ規則を当てる。
- 印が書き手の改行しない範囲の中にあれば、範囲の規則がそのまま当たる。

文言と値を合わせた幅が行長より長ければ、はみ出す行を作る。
その行は、範囲を書き手が付けたものではないので、G07122 ではなく G07105 の警告で報告する（「メンテナーが決めること」の 4）。
分けられない欧文の語のはみ出しと同じ扱いである。

### 2. 片のデータ構造

`Golem.Doc.Citation` の `CitePiece` に、位置の片を足す。

```haskell
data CitePiece
  = CiteNumber !Text !Int -- a number and the key it stands for
  | CiteText !Text -- text: brackets, separators, an unnumbered key
  | CiteLocator !Text !Text -- the label of a locator and its value: "pp." "5–7"
```

- `citationPieces` は、位置を持つ件の番号の後に `CiteText ", "` と `CiteLocator` を置く。種類が `page` でない位置は、今のとおり文言を持たないので、`CiteText` で値だけを置く（Validate がその前に止める）。
- `citationText` は、`CiteLocator l v` を `l <> " " <> v` とつなぐ。PDF の抜き出した文字列とプレーンテキストの出力は、この ADR の前と同じ `[1, p. 5]` である。
- golem-layout は、`CiteLocator` の文言と値のあいだの空白から作るグルーの前に、1 の罰点を置く。
- golem-html は、`CiteLocator` の文言と値のあいだに U+00A0 NO-BREAK SPACE を書く（3）。

`CitePiece` は意味論 IR の型ではないので、IR、CBOR、CDDL、プラグインの ABI は変わらない。
golem-* のあいだの依存も変わらない。

### 3. HTML と EPUB

引用の印の頁の文言と値のあいだを、U+0020 の代わりに U+00A0 で書く（`<span class="cite">[<a href="#cite-knuth1981">1</a>, p.&#xA0;5]</span>` の形。実体参照で書くか文字で書くかは今の `escapeXml` に従う）。
閲覧環境は U+00A0 で行を分けないので、PDF と同じく文言と値が一行に残る。
位置のない印の HTML は変わらない。

### 4. プレーンテキスト

変えない。
プレーンテキストは行を折り返さないので、文言と値のあいだは今のとおり U+0020 で書く。

### 5. 文書

- [docs/specifications.md](../specifications.md) の「引用と参考文献」の節の印の書式の規則の後に、頁の文言と値のあいだで行を分けないこと、ほかの位置は地の文の規則で分けうること、HTML と EPUB では U+00A0 で書くことを足す。「行分割」の節の、行を分けない位置を並べた箇所にも一文を足す。
- [docs/diagnostics.md](../diagnostics.md) の G07105 の節に、引用の印の頁の文言と値が行に収まらない場合を足す。
- [TeX と InDesign との差異](../differences-from-tex-and-indesign.md) に、印の中の分割を biblatex の `\ppspace` と番号の区切りに合わせたこと、LaTeX の標準の `\cite` の番号のあいだの罰点 1000 は採らないことを書く。

### 6. 出力の変化

頁を指定した引用の印が行末に来る段落の行の分け方が変わりうる。
complex fixture の `[cite build-systems page=12...14]` を含む段落と、マニュアルの参考文献の章の例で、PDF と決定性のハッシュが変わりうる。
実装のプルリクエストで、ハッシュが変わったものと、文言と値のあいだで分けていた行の数を説明に書く。

## 実装しないこと

- **印の全体を分けないこと**：LaTeX と biblatex に合わず、長い印で行が大きく空く（「メンテナーが決めること」の 1）。
- **番号の範囲と頁の範囲の `–` の後で分けないこと**：biblatex は分けうるダッシュとする（「メンテナーが決めること」の 2）。
- **番号のあいだの区切りの後の罰点**：LaTeX の標準の `\cite` の罰点 1000 は採らず、biblatex と同じく地の文の語間と同じにする。
- **連続する印のあいだ（`[1][2]`）の分割**：二つの印は別の印であり、あいだは地の文の規則で決める。
- **注の印と相互参照の文字列**：注の印と相互参照（`[ref-number]`）の文字列の中の分割は、この ADR では扱わない。
- **プレーンテキストの U+00A0**：4 のとおり変えない。

## 不変条件

「印」は、PDF の本文の、番号を引ける引用の印とする。
「文言と値の組」は、印の位置の文言の最後の字（`p.` か `pp.` の `.`）と、その値の最初の字の組とする。

- **C1 分けない**：PDF の行分割で、どの行も、文言と値の組のあいだで終わらない。文言と値のあいだのグルーの前の項目は罰点 10000 であり、そのあいだにほかの分割の候補はない。
- **C2 幅は変わらない**：印を含む段落の箱とグルーの幅と伸び縮みは、この ADR の前と同じである。項目の違いは、文言と値のあいだのグルーの前の罰点 10000 の一つだけである。
- **C3 ほかの位置**：位置を持たない印を含む段落の項目は、この ADR の前と同じである（[ADR 0266](0266-citation-locators-and-multiple-keys.md) の I8 はそのまま成り立つ）。位置を持つ印でも、文言と値のあいだのほかの位置の候補と罰点は、この ADR の前と同じである。
- **C4 文字列は変わらない**：どの引用についても、`citationText` の文字列と、PDF の抜き出した文字列と、プレーンテキストの出力は、この ADR の前と同じである。
- **C5 HTML**：位置を持つ印の HTML は、この ADR の前の HTML の、文言と値のあいだの U+0020 を U+00A0 に替えたものと等しい。位置を持たない印の HTML は、この ADR の前とバイト列で等しい。
- **C6 はみ出しの報告**：文言と値の組が行に収まらずにはみ出した行には、G07105 だけを出し、G07122 を出さない。印が書き手の改行しない範囲の中なら、[ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md) の I9 のとおり G07122 だけを出す。

[ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md) の L1 から L13 は、候補が一つ減るだけなので、そのまま成り立つ。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 位置 | なし、`page=0`、`page=5`、`page=5...5`、`page=5...7`、`page=xii`、`page="5 f."`（値の中の空白） |
| 印の中の行末の位置 | `[` の後、番号の区切りの後、`–` の後、位置の前の `, ` の後、文言の後、値の中、`]` の後 |
| 行の残りの幅 | 文言の後でちょうど終わる、値の最初の字まで入る、値の全体が入る、印の全体が入る |
| 文言と値の幅 | 行長より短い、ちょうど行長、行長より一字長い |
| 組方向 | 横組み、縦組み |
| 範囲 | 書き手の改行しない範囲の外、中 |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
テストの名前には、C1 から C6 の番号を入れる。

- **golem-doc のテスト**：C4。[ADR 0266](0266-citation-locators-and-multiple-keys.md) のテストの引用の列挙（番号の集まり 64 通りとその並べ替え、位置の三つの値）のすべてで、`citationText` がこの ADR の前の期待値と等しいこと。位置を持つ件が `CiteLocator` を一つ持ち、文言が `p.` か `pp.` であること。
- **golem-layout のテスト**：C1、C2、C3。`あ` を n 字（0 から行長まで）並べた後に `[1, pp. 5–7]` と `[1, p. xii]` の印を置き、行長 8 字から 14 字、横組みと縦組みで組んで、どの行も文言の後で終わらないこと。今は行長 12 字、n が 8 の入力で `pp.` の後で分けるので失敗する。同じ入力で、項目の違いが罰点 10000 の一つだけであること（C2）。位置のない印（`[1–3]`、`[1, 4]`）の項目がこの ADR の前と同じであること（C3）。
- **列挙**：[ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md) の部品の列挙に、文言と値の組の部品を足し、L1 から L13 と C1 がすべての入力で成り立つことを確かめる。プルリクエストの段の時間が範囲ごとの予算 10 秒（[ADR 0208](0208-widen-lightweight-formal-methods.md) の 4）を超えるなら、毎晩のジョブの段だけで足す。
- **golem-html のテスト**：C5。`[1, p. 5]`、`[1, pp. 5–7]`、`[1, p. xii]` の印の HTML と、位置のない印の HTML。
- **golem-text のテスト**：C4。プレーンテキストの印が U+0020 のままであること。
- **golem-driver のテスト**：C6。行長 2 字の本で `[cite a page=xii]` を組み、はみ出した行に G07105 だけが出ること。`[style no-break: …]` の中の印では G07122 だけが出ること。

## トレードオフ

- 印の中の分割の候補は残るので、`[1,` `4]` や `[1–` `3]` のように、印が二行に分かれることは今のとおり起こる。読み手が印を一目で読めない場合がある。分けないことを求める本は、書き手が `[style no-break: [cite …]]` で印を囲める（2026-11-10 に同じ本で、囲んだ印が一行に残ることを確かめた）。
- 頁の文言と値を分けないので、行長の短い組版で前の行が空くことがある。分けない文字列は `pp. 5–7` でも 7 字であり、欧文の長い語と同じ程度である。
- HTML とプレーンテキストで、文言と値のあいだの文字が違う（U+00A0 と U+0020）。プレーンテキストを HTML と同じにすると、印の文字列を検索する利用者が U+00A0 を考えることになる。
- `CitePiece` の構成子が増え、`citationPieces` を使う三つの出力がそれぞれ `CiteLocator` を扱うことになる。
- 「参考文献のスタイル」が文言を変えても（「頁」など）、文言と値の組を一つの片にしておけば、この規則はそのまま当たる。

## メンテナーが決めること

1. **分けない範囲**：推奨は、頁の文言と値のあいだだけを分けないことである。仕様書の拠るものの順で手本になる biblatex（[ADR 0266](0266-citation-locators-and-multiple-keys.md) が手本にした `numeric-comp`）と同じ規則であり、`pp.` だけが行末に残る組み方を除ける。
   - 退けた案の一つは、印の全体を分けないことである。印はいつも一行に収まるが、LaTeX の標準の `\cite` も biblatex も番号の区切りの後で分けており、拠るものの順に合わない。複数の文献の長い印を送れば、行長の短い縦組みの本や表のセルで前の行が大きく空き、印が行長を超えればはみ出す。
   - もう一つは、今のまま変えないことである。`pp.` だけが行末に残る。
2. **範囲の `–` の後**：推奨は、今のとおり分けうることである（`[1–` `3]`、`pp. 5–` `7]`）。biblatex は範囲のダッシュを分けうるダッシュとし、罰点の既定も Golem の `explicit-hyphen-penalty` と同じ 50 である。
   - 退けた案は、印の中の `–` の後でも分けないことである。範囲が一行に残るが、拠るものの順に合わず、行の調整の余地が減る。
3. **HTML と EPUB の書き方**：推奨は、文言と値のあいだを U+00A0 で書くことである。CSS を足さずに、閲覧環境の行分割を PDF に合わせられる。
   - 退けた案の一つは、文言と値を `<span class="cite-locator">` で囲み、組み込みの CSS に `white-space: nowrap` を書くことである。クラスと CSS の規則が一つずつ増える。
   - もう一つは、HTML を変えないことである。閲覧環境では `pp.` だけが行末に残りうる。
4. **はみ出した行のコード**：推奨は、G07105 を使い、新しいコードを足さないことである。範囲は書き手が付けたものではなく、分けられない欧文の語と同じく組版の規則が候補を消した行である。G07122 のメッセージ（改行しない範囲が行に収まらない）は、書き手が `no-break` を書いていない原稿では原因を取り違えさせる。
   - 退けた案は、[ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md) の改行しない範囲の仕組み（`lkNoBreak`）をそのまま使い、G07122 を出すことである。実装は小さいが、原因と違うコードになる。

## 決めたことの記録

2026-11-10 に、tett23 がすべて推奨のとおりに決めた。

1. 分けない範囲は、推奨のとおり頁の文言と値のあいだだけとする。
2. 範囲の `–` の後は、推奨のとおり今のとおり分けうる。
3. HTML と EPUB では、推奨のとおり文言と値のあいだを U+00A0 で書く。
4. はみ出した行は、推奨のとおり G07105 で報告し、新しいコードを足さない。

## 参考文献

- [ADR 0208](0208-widen-lightweight-formal-methods.md)、[ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md)、[ADR 0266](0266-citation-locators-and-multiple-keys.md)、[ADR 0267](0267-pdf-bookmarks-and-links-inside-the-document.md)、[ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md)
- [golem-layout ADR 0008](../golem-layout/adr/0008-explicit-hyphens.md)
- W3C. Requirements for Japanese Text Layout (JLReq). https://www.w3.org/TR/jlreq/（3.1.10 分割禁止と、英語の題が「Handling of Western Text in Japanese Text using Proportional Western Fonts」の節）。w3c/jlreq の `index.html`（`43942474`）を 2026-11-10 に読んだ。
- LaTeX2e の `base/ltbibl.dtx` の `\@citex`（latex3/latex2e `910abf03`）。2026-11-10 に読んだ。
- biblatex の `tex/latex/biblatex/biblatex.sty`（`\ppspace`、`\addnbspace`、`\blx@mkpageprefix`）、`biblatex.def`（`\multicitedelim`、`postnotedelim`）、`lbx/english.lbx`（`\bibrangedash`）、`cbx/numeric-comp.cbx`（plk/biblatex `c89dfc81`、v3.22 の後）。2026-11-10 に読んだ。
- InDesign の振る舞いは、Golem の開発の環境で動かせないので確かめていない。
