# ADR 0005: 参考文献に誌名、巻と号、ページ、URL、閲覧日を組む

ステータス: 採択

## 文脈

参考文献の一件は、著者、題、発行者、発行の年の四つの欄だけを組む（[ADR 0004](0004-bibliography-formatting.md)）。
golem-driver の `Golem.Driver.cslEntry` は、CSL-JSON の項目から `id`、`language`、`author`、`title`、`publisher`、`issued` だけを読み、ほかの欄を捨てる。
[ADR 0004](0004-bibliography-formatting.md) は、`container-title`、`volume`、`page`、`URL` を一覧に出すことを「実装しないこと」に置いた。

その結果、論文は誌名なしで、Web の文献は URL なしで組まれる。
使い手のマニュアルの `manual/references.json` は、二十二件のうち二十件に `URL` を、Knuth と Plass の論文に `container-title` と `volume` を書いているが、どれも一覧に出ない。
マニュアルの `manual/chapters/04-manifest.gm` も、`URL` などの欄は「今は一覧に出しません」と書いている。

ロードマップの「参考文献の項目」は、誌名や書名（`container-title`）、巻と号（`volume`、`issue`）、ページ（`page`）、URL（`URL`）を組めるようにし、URL の文献には最終閲覧日（`accessed`）を書けるようにする、としている。

### CSL-JSON の欄

CSL-JSON のスキーマ（`csl-data.json`）では、欄は次の型を持つ。

| 欄 | 型 | 意味 |
| --- | --- | --- |
| `container-title` | 文字列 | 論文の載った誌、章の載った本などの題 |
| `volume` | 文字列か数 | 巻 |
| `issue` | 文字列か数 | 号 |
| `page` | 文字列か数 | ページ。範囲は `1119-1184` のように書くことが多い |
| `URL` | 文字列 | 文献の URL |
| `accessed` | 日付 | 閲覧した日。`issued` と同じ日付の形（`date-parts`、`literal` など） |

CSL の仕様は、ページの範囲の区切りを、既定では en dash（U+2013）で表すとしている。

### 書式を決めるうえでの前提

[ADR 0004](0004-bibliography-formatting.md) は、項目ごとに和文の項目か欧文の項目かを決め、欄のあいだと末尾の区切りを変える。

| | 欧文の項目 | 和文の項目 |
| --- | --- | --- |
| 欄のあいだ | `. ` | `、` |
| 末尾 | `.` | `。` |

新しい欄も、この区切りの中に置く。
書式の選択（誌ごとの書式や、TeX の書誌と互換の書式を目標とする参考文献のスタイル）は、v1.0.0 で扱う予定である。
したがって、この ADR が決めるのは、一種類の書式の中で、新しい欄をどの順に、どの印を付けて並べるかである。
スタイルを入れるときは、この ADR の書式を既定のスタイルとして引き継ぐ。

### URL の改行

URL は空白を含まない長い文字列なので、PDF の行分割で問題になる。
今の行組版は、欧文の語の中では、明示したハイフンの後と、ハイフネーションのパターンの許す位置でしか改行しない。
`https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/` のような URL は、パターンで分綴されてハイフンが入るか、一つの語として行からはみ出す。
どちらも URL を壊す。

コードの文字スタイル（`[code: ...]`）は、ハイフネーションをかけず、空白と `/` の後でだけ改行する（[golem-driver ADR 0017](../../golem-driver/adr/0017-pdf-code-blocks.md)）。
URL にも同じ規則が向く。
ただし、`code` の文字スタイルは書体を等幅の `code` の役割に変えるので、そのまま URL に当てると、参考文献の URL が等幅になる。

### メンテナーが決めたこと

起草の後、メンテナーが次のように決めた。

- 和文の項目では、題と誌名を括弧で括る。論文や章の題は「」で、本や誌の題は『』で括る。どの欄をどちらで括るかは、項目の種類（CSL-JSON の `type`）で決める。
- ページの範囲の区切りは、和文の項目でも en dash とする。
- 組み込みの文字スタイル `url` を加える。PDF のリンク（ロードマップの「PDF のリンク」）で、URL の文字を見分ける手段としても使える見込みである。
- 参考文献のスタイル（誌ごとの書式、TeX と互換の書式を目標とする）は v1.0.0 で予定している。この ADR は、それまでの一種類の書式を決める。

## 実装すること

### 欄の並びと書式

一件の欄を次の順に並べ、空の欄を飛ばす。
著者、題、発行者、発行の年の書き方は [ADR 0004](0004-bibliography-formatting.md) のとおりとする。

| 順 | 欄 | 欧文の項目 | 和文の項目 |
| --- | --- | --- | --- |
| 1 | 著者 | 今と同じ | 今と同じ |
| 2 | 題 | 今と同じ | 項目の種類に応じて「」か『』で括る |
| 3 | 掲載先（誌名、巻、号、ページ） | 一つの欄にまとめ、`, ` でつなぐ | 誌名、巻と号、ページを別々の欄にする。誌名は項目の種類に応じて『』で括る |
| 4 | 発行者 | 今と同じ | 今と同じ |
| 5 | 発行の年 | 今と同じ | 今と同じ |
| 6 | URL と閲覧日 | `URL (accessed 日付)` | `URL（日付閲覧）` |

**和文の項目の括弧**：項目の種類（`type`）で、題と誌名の括り方を決める。
欧文の項目は括らない。

| 種類 | 題 | 誌名（`container-title`） |
| --- | --- | --- |
| 部分の文献：`article`、`article-journal`、`article-magazine`、`article-newspaper`、`chapter`、`entry`、`entry-dictionary`、`entry-encyclopedia`、`paper-conference`、`review`、`review-book` | 「」 | 『』 |
| Web の部分の文献：`webpage`、`post`、`post-weblog` | 「」 | 括らない |
| 一冊の文献：`book`、`thesis`、`report`、`manuscript`、`pamphlet` | 『』 | 括らない |
| ほかの種類と、`type` のない項目 | 括らない | 括らない |

部分の文献は、それを載せた誌や本の中の一つの文献なので、題を「」で、載せた誌や本の題を『』で括る。
Web のサイトの名前は誌や本の題ではないので括らない。
一冊の文献は、それ自体が本なので題を『』で括る。
`standard`、`dataset`、`software`、`document` などは、和文の書誌で括り方が定まっていないので、[ADR 0004](0004-bibliography-formatting.md) と同じく括らない。

題や誌名が、すでに同じ括弧の開きで始まり閉じで終わるときは、括弧を足さない。
書き手が CSL-JSON に括弧ごと書いた値を、二重に括らないためである。
括った欄は閉じ括弧で終わるので、[ADR 0004](0004-bibliography-formatting.md) の欄が `。`、`？`、`！` で終わるときの規則は当たらない。

**巻と号**：値が ASCII の数字だけなら印を付け、ほかの値はそのまま書く。

| | 欧文の項目 | 和文の項目 |
| --- | --- | --- |
| 巻 | `vol. 11` | `第11巻` |
| 号 | `no. 3` | `第3号` |
| 巻と号の両方 | `vol. 11, no. 3` | `第11巻第3号`（一つの欄） |

**ページ**：ASCII のハイフン（`-`）の連なりが数字と数字のあいだにあれば、en dash（`–`）一つに置き換える。
数字と数字のあいだに en dash かハイフンがあるとき、または `,` を含むとき、範囲とする。

| | 欧文の項目 | 和文の項目 |
| --- | --- | --- |
| 範囲 | `pp. 1119–1184` | `1119–1184頁` |
| 一ページ | `p. 5` | `5頁` |

**閲覧日**：`accessed` は URL があるときだけ組み、URL の後に括弧で添える。
URL のない項目の `accessed` は組まない。

| `accessed` | 欧文の項目 | 和文の項目 |
| --- | --- | --- |
| 年、月、日 | `October 16, 2026` | `2026年10月16日` |
| 年、月 | `October 2026` | `2026年10月` |
| 年 | `2026` | `2026年` |
| `literal` | その文字列 | その文字列 |

欧文の月の名前は、処理系が持つ表（`January` から `December`）で書き、ロケールに頼らない。
月が 1 から 12 の外なら年だけを、日が 1 から 31 の外なら年と月だけを書く。

**末尾**：

- 欧文の項目が、閲覧日のない URL で終わるときは、末尾の `.` を付けない。`.` が URL の一部に見えるからである。閲覧日があれば、`)` の後に `.` を付ける。
- 和文の項目は、URL で終わるときも `。` を付ける。全角の句点は URL の一部に見えない。
- [ADR 0004](0004-bibliography-formatting.md) の、欄が `.`、`?`、`!`（和文の項目では `。`、`？`、`！`）で終わるときの規則は、新しい欄にも同じく当てる。

### 例

```
Knuth Donald, Plass Michael. Breaking Paragraphs into Lines. Software: Practice and Experience, vol. 11, no. 11, pp. 1119–1184. 1981.
山田太郎、「日本語の行分割」、『情報処理』、第45巻第1号、21–30頁、2004。
鈴木一郎、「縦組みの約物」、『組版論集』、45–60頁、組版出版、2015。
山田花子、『組版の基礎』、組版出版、2010。
「日本語組版処理の要件」、W3C、2020、https://www.w3.org/TR/jlreq/。
「日本語組版処理の要件」、W3C、2020、https://www.w3.org/TR/jlreq/（2026年10月16日閲覧）。
CSS Text Module Level 3. W3C. https://www.w3.org/TR/css-text-3/
CSS Text Module Level 3. W3C. https://www.w3.org/TR/css-text-3/ (accessed October 16, 2026).
```

### CSL-JSON の読み方（golem-driver）

`cslEntry` は、[ADR 0004](0004-bibliography-formatting.md) の欄に加えて、次を読む。

- `type`：文字列のとき読む。和文の項目の括弧の付け方にだけ使う。
- `container-title`、`URL`：文字列のとき読む。
- `volume`、`issue`、`page`：文字列か、整数の数のとき読む。整数の数は十進の数字の文字列にする。整数でない数は読まない。
- `accessed`：`issued` と同じく読む。
- 日付の `date-parts` は、最初の要素の一つめを年、二つめを月、三つめを日とする。それぞれ、整数の数か、ASCII の数字だけの文字列のとき読む。月がなければ日も読まない。

空の文字列と、空白だけの文字列は、ない欄として扱う。

`issued` は、今と同じく年だけを組む。
読む値は月と日まで広げるが、一覧に出すのは年である。

### 一件の表し方（golem-doc）

`formatEntry` の結果を、文字列から部分の列に変える。
URL を、ほかの文字と区別して出力に渡すためである。

```haskell
data EntryPart = EntryText !Text | EntryUrl !Text

formatEntry :: CslEntry -> [EntryPart]

-- | 部分をつないだ文字列（プレーンテキストとテストのため）。
entryText :: [EntryPart] -> Text
```

`EntryUrl` は URL の文字列だけを持ち、区切りと閲覧日は前後の `EntryText` に入る。
隣り合う `EntryText` はつなぐ。

### 出力

- **PDF**：`bibliographyLines` は、`EntryText` を `Text` に、`EntryUrl` を文字スタイル `url` の `CharStyle` に包んだ `Text` にする。
- **HTML と EPUB**：`EntryUrl` を `<a class="cs-url" href="URL">URL</a>` にする。URL の scheme が `http` か `https`（大文字と小文字を区別しない）でなければ、`<a>` にせず `<span class="cs-url">` にする。`javascript:` のような URL をリンクにしないためである。
- **プレーンテキスト**：`entryText` の文字列を使う。

### 組み込みの文字スタイル url

組み込みの文字スタイルに `url` を加える。
キーは何も持たず、書体、大きさ、色は周りの文字のまま組む。

文字スタイル `url` と、`based-on` をたどって `url` に行き着く文字スタイルの文字は、PDF で次のように組む。

- ハイフネーションをかけない。
- 改行してよい位置を、空白と `/` の後に限る。`/` の後で改行しても、ハイフンを描かない。`//` のような連なりは、その最後の `/` の後でだけ改行する。`https:/` と `/` のあいだで分かれると、URL の始まりが読み取りにくいからである。
- 中の文字のあいだにアキ量のセットの空きを入れない。

ここまでは、[golem-driver ADR 0017](../../golem-driver/adr/0017-pdf-code-blocks.md) の `code` の文字スタイルの規則と同じである。
`code` と違い、カーニングは止めず、`code` の役割の書体を読み込む理由にもしない。
`/` の連なりの扱いは `url` だけのものとし、`code` の規則は変えない。

利用者が `[character-styles.url]` を書くと、書いたキーだけが組み込みの定義を上書きする。
`font = "code"` と書けば参考文献の URL を等幅にでき、`color` を書けば色を付けられる。
HTML と EPUB の `.cs-url` の CSS も、ほかの文字スタイルと同じく書いたキーから作る。

原稿の `[style url: ...]` も、ほかの組み込みの文字スタイルと同じく使える。
`[url: ...]` のような別名は加えない。

### データ構造

golem-doc の `Golem.Doc.Bibliography`：

```haskell
data CslDate
  = DateParts !Integer !(Maybe Int) !(Maybe Int) -- 年、月、日
  | DateLiteral !Text

data CslEntry = CslEntry
  { ceId :: !Text,
    ceType :: !(Maybe Text),
    ceLanguage :: !(Maybe Text),
    ceAuthors :: ![CslName],
    ceTitle :: !(Maybe Text),
    ceContainerTitle :: !(Maybe Text),
    ceVolume :: !(Maybe Text),
    ceIssue :: !(Maybe Text),
    cePage :: !(Maybe Text),
    cePublisher :: !(Maybe Text),
    ceIssued :: !(Maybe CslDate),
    ceUrl :: !(Maybe Text),
    ceAccessed :: !(Maybe CslDate)
  }
```

`DateYear` は `DateParts` に置き換える。
日付の型を年、月、日まで広げ、`issued` の書式は年に絞る（仕様書の「設計原則」の「広い型、狭い実装」）。

- golem-driver の `loadBibliography` が返す書誌の表を `Map Text [EntryPart]` にする。
- golem-html の `hcBibliography` と、golem-text の設定の書誌の表も `Map Text [EntryPart]` にする。
- golem-driver の `bibliographyLines` の型を `Map Text [EntryPart] -> [(Text, Int)] -> [[Inline]]` にする。
- golem-project の `builtinCharStyles` に `("url", noCharDef)` を加える。PDF の改行の規則を当てる判定は、`isCodeCharStyle` とは別の関数にする。`isCodeCharStyle` は、`code` の役割の書体を読み込むかどうかの判定にも使われているからである。

意味論 IR とプラグインの ABI は変えない。
参考文献の文字列は IR に入らず、出力の段階で golem-driver が渡す。

### ドキュメント

- docs/specifications.md の「引用と参考文献」の、一件の欄の並びを述べた文を上の六つの欄に改め、和文の項目の題と誌名の括弧、巻と号、ページ、閲覧日の書き方、URL の末尾の扱いを書き、この ADR へリンクする。参考文献のスタイルを v1.0.0 で扱う予定であることを添える。
- docs/specifications.md の「style.toml」の「組み込みの文字スタイルは `bold`、`italic`、`strong`、`code` の四つである。」を、`url` を加えた五つに改め、`url` の改行の規則を書く。
- docs/roadmap.md の「記法と設定」から「参考文献の項目」の項を除く。
- 使い手のマニュアル（`manual/`）：
  - `manual/chapters/04-manifest.gm` の「Golem が使う欄」の箇条に `type`、`container-title`、`volume`、`issue`、`page`、`URL`、`accessed` を加え、`type` で和文の項目の括弧が決まることを書き、「一覧には、著者、題、発行者、発行の年を、この順に並べて組みます。」から始まる段落を、上の並びと書き方に改める。「ほかの欄（このマニュアルのデータにある `type` や `URL` など）は、書いてあってもかまいませんが、今は一覧に出しません。」の文は、`type` と `URL` がどちらも使う欄になるので、例を `DOI` などに改める。
  - 付録C（`manual/appendices/c-style.gm`）の組み込みの文字スタイルに `url` を加える。
  - 付録H（`manual/appendices/h-roadmap.gm`）の「参考文献の一覧に、誌名、巻と号、ページ、URL を組むこと」の項を除く。
- 開発者のマニュアル（`manual-dev/`）は、参考文献の書式を述べていないので変えない。`manual-dev/references.json` の文献の URL も一覧に出るようになるので、組んだ結果は「自動テストにしない確かめ方」で確かめる。
- [ADR 0004](0004-bibliography-formatting.md) のステータスの行を、「採択→一覧に出す欄と日付の型は」に続けてこの ADR へのリンクを置く形に改める。
- [golem-driver ADR 0017](../../golem-driver/adr/0017-pdf-code-blocks.md) のステータスの行を、「採択→コードの改行の規則を文字スタイル `url` にも当てることは」に続けてこの ADR へのリンクを置く形に改める。

## 実装しないこと

- 参考文献のスタイル（CSL のスタイルの解釈、誌ごとの書式、TeX と互換の書式）と書式の選択。v1.0.0 で扱う予定である。
- `DOI`、`ISBN`、`edition`、`number`（報告書の番号など）、`collection-title`、`editor`、`translator` などの欄。
- `issued` の月と日を一覧に出すこと。
- 欧文の項目の題を引用符で括ること。スタイルとともに扱う。
- 括弧で括る題の中の括弧を付け替えること（題の中の「」を『』にするなど）。書いたとおりに組む。
- 上の表にない種類の括り方を、`manifest.toml` などで変えられるようにすること。スタイルとともに扱う。
- 欧文の誌名や書名を斜体にすること。スタイルとともに扱う。
- PDF の URL にリンクの注釈を付けること。ロードマップの「PDF のリンク」で扱う。
- HTML と EPUB で、長い URL を折り返す CSS（`overflow-wrap` など）を足すこと。
- 原稿に URL を書く記法（`[url: ...]` の別名など）。
- URL の形を検査すること。書いた文字列をそのまま組む。
- URL のない項目の `accessed` を診断にすること。

## テスト設計

### 先に書いて失敗させるテスト

`modules/golem-doc/test/BibliographySpec.hs`（`entryText (formatEntry e)` と、部分の列そのものを確かめる）：

- 上の「例」の八件が、それぞれの行になること。
- 和文の項目で、表の種類ごとに題と誌名の括弧が表のとおりになること。`article-journal` で題が「」、誌名が『』に、`webpage` で題が「」、誌名が括られずに、`book` で題が『』に、`standard` と `type` のない項目で括弧が付かないこと。
- 題が `「既に括った題」` の `article-journal` の和文の項目で、括弧が二重にならないこと。題が `『書名』` の `book` も同じであること。
- 欧文の項目で、`type` によらず題と誌名に括弧も引用符も付かないこと。
- 題が `。` で終わる `book` の和文の項目で、`『…。』` の後に `、` が続き、末尾の `。` の規則が当たらないこと。
- 欧文の項目で、`container-title` だけの掲載先が `Title. Journal. 1981.` の形になり、巻だけが `Journal, vol. 11` に、号だけが `Journal, no. 3` になること。
- 和文の項目で、巻だけが `第11巻`、号だけが `第3号`、巻と号が `第11巻第3号` の一つの欄になること。
- 巻が `Suppl. 2` の欧文の項目で、`vol.` を付けずに `Suppl. 2` と書くこと。
- `page` が `1119-1184` と `1119--1184` のとき `pp. 1119–1184` に、`5` のとき `p. 5` に、`A-1` のとき `p. A-1` に（数字のあいだでないハイフンは置き換えず、範囲ともせずに）なること。`3, 7` が `pp. 3, 7` になること。和文の項目で `1119–1184頁` と `5頁` になること。
- 閲覧日の年月日、年月、年、`literal` の四つの形が、欧文と和文の表のとおりになること。月が 13 のとき年だけに、日が 32 のとき年と月だけになること。
- URL のない項目の `accessed` が出ないこと。
- 閲覧日のない URL で終わる欧文の項目に `.` が付かず、閲覧日があれば `).` で終わること。和文の項目は、どちらも `。` で終わること。
- URL が `EntryUrl` として一つの部分になり、前後の区切りと閲覧日が `EntryText` に入ること。
- 新しい欄のない項目の結果が、[ADR 0004](0004-bibliography-formatting.md) のテストの文字列と同じであること（今のテストを `entryText` で書き直したものが通ること）。

`modules/golem-driver/test/Main.hs`：

- `type` が文字列でない項目（数など）が、`type` のない項目と同じく組まれること。
- `volume` が `11`（数）と `"11"`（文字列）の項目が、同じ文字列になること。`volume` が `11.5` の項目は巻を出さないこと。
- `accessed` の `date-parts` が `[["2026", "10", "16"]]`（文字列）でも、`[[2026, 10, 16]]` と同じ閲覧日になること。
- 参考文献を引く原稿の HTML に、`<a class="cs-url" href="https://www.w3.org/TR/jlreq/">https://www.w3.org/TR/jlreq/</a>` が出ること。URL が `javascript:alert(1)` の項目では `<a>` が出ず `<span class="cs-url">` になること。
- PDF の `bibliographyLines` で、URL の部分が `CharStyle _ "url" [Text _ url]` になること。
- `style.toml` に `[character-styles.url]` を書かない本の HTML の `style.css` が、今と同じバイト列であること。

`modules/golem-layout/test/Main.hs`（`url` の文字スタイルの look を持つ文字の箱）：

- `https://example.com/a/b` が、`https://`、`example.com/`、`a/`、`b` の後でだけ改行できる箱の列になり、ハイフネーションの候補を持たないこと。
- 行長を狭くした段落で、URL が `/` の後で改行され、ハイフンが描かれないこと。

`modules/golem-project/test/Main.hs`：

- 組み込みの文字スタイルに `url` があり、キーを持たないこと。`[character-styles.url] font = "code"` が `font` だけを上書きすること。

`modules/golem-text/test/Main.hs`：

- `@bibliography` の行が、URL と閲覧日を含む `entryText` の文字列になること。

### 自動テストにしない確かめ方

二つのマニュアルを PDF に組み、巻末の参考文献で次を目で確かめる。

- Knuth と Plass の論文の行に、誌名と巻が出ていること。
- 和文の項目があれば、題と誌名の括弧が種類のとおりであること。
- URL の行が版面からはみ出さず、長い URL（LSP の仕様の URL など）が `/` の後で改行され、ハイフンが入っていないこと。
- 和文の項目の「、」の後の URL の前に、余分な空きがないこと。

## トレードオフ

和文の項目の括弧を、項目の種類で決めた。
括弧があれば、題と誌名が「、」だけで並んでも、どこまでが題かを読み取れる。
代わりに、CSL-JSON に `type` を書かない項目は括られず、種類を書いた項目と同じ一覧に並ぶと括り方がそろわない。
`container-title` の有無から部分の文献かどうかを推す案もあるが、推し量りの規則を一つ増やすことになるので、書き手が書いた `type` に従うほうを選んだ。
CSL-JSON を書誌の管理の道具から書き出せば、`type` はふつう入っている。

欧文の項目では掲載先を一つの欄にまとめ、和文の項目では欄を分けた。
欧文では `. ` で欄を分けるので、`Journal. vol. 11. pp. 1–10.` のように巻とページを別の欄にすると、ピリオドが多く、どこまでが誌名の情報かが読みにくい。
和文では欄のあいだが「、」なので、分けても掲載先の情報はつながって読める。
同じ欄の順で、区切りの扱いだけが文字の種類で変わる、という [ADR 0004](0004-bibliography-formatting.md) の方針の延長である。

巻と号に「第」「巻」や `vol.` を付けるのは、値が数字だけのときに限った。
`Suppl. 2` や「増刊」のような値に印を付けると、`vol. Suppl. 2` や「第増刊巻」になる。
数字でない値には書き手が自分で書いた形を尊重する。
代わりに、`vol. 11` と `Suppl. 2` が同じ一覧に並ぶと、印の有無がそろわない。

閲覧日は URL の後に括弧で添えた。
Chicago のように閲覧日を URL の前に置く流儀もあるが、URL を最後に置くと、欧文の項目で URL の後に `.` を付けずに済む。
APA は URL の後に `.` を付けない。
URL の直後に句読点を置かないことは、URL を写し取る読み手を誤らせないための選択である。

URL の改行のために、組み込みの文字スタイル `url` を加えた。
PDF のリンクを入れるときも、URL の文字をこの文字スタイルで見分けられる見込みである。
golem-layout に URL を見分ける規則を加える案、ゼロ幅空白（U+200B）を改行の位置として扱う案もある。
前者は、参考文献のほかの文字と URL を区別する手段がやはり要る。
後者は、本文に書いたゼロ幅空白の扱いも変え、ハイフネーションを止める手段にはならない。
文字スタイルにすると、既にある `code` の改行の規則を使い回せ、利用者が `style.toml` で書体と色を変えられる。
その代わりに、組み込みの名前が一つ増え、`url` という名前の文字スタイルを定義していた本では、その文字スタイルの文字の改行の規則が変わる。

部分の列（`[EntryPart]`）にしたので、書誌の表を受け取るすべての出力の型が変わる。
文字列のまま URL に印の文字を埋め込む案は、印の文字が原稿の文字と衝突しうるので採らない。

## 参考文献

- Citation Style Language 1.0.2 Specification, "Appendix IV - Variables", "Page Ranges", https://docs.citationstyles.org/en/stable/specification.html
- CSL-JSON schema (`csl-data.json`), https://github.com/citation-style-language/schema/blob/master/schemas/input/csl-data.json
- 科学技術振興機構, SIST 02 参照文献の書き方
- W3C, Requirements for Japanese Text Layout（JLReq）, https://www.w3.org/TR/jlreq/
