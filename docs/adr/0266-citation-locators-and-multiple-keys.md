# ADR 0266: 引用の頁の指定と複数の文献

ステータス: 採択（未実装）

## 文脈

Golem の `[cite]` は、書誌データのキーを一つだけ取る。
評価は位置引数がちょうど一つの名前のときだけ引用を作り、それ以外を G02021 とする（[`Fixed BCite`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-eval/src/Golem/Eval/File.hs#L2280-L2283)）。
IR の引用は `Cite !SrcSpan !Text` で、キーのほかに値を持たない（[`InlineF`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-doc/src/Golem/Doc/IR.hs#L276-L277)）。
このため、「Knuth の 5 ページ」のように引用した文献の中の位置（頁）を書けず、三つの文献を一度に引くには `[cite a][cite b][cite c]` と書いて「[1][2][3]」になる。

学術書では、頁のない引用はほとんど使えない。
[2026-10-17 の調査](../audits/2026-10-17-latex-gap-for-v1.md) の「12. 引用の頁の指定と複数の文献」は、これを v1.0.0 に提案し、所有者は v1.0.0 に置くと決めた（同じ記録の「所有者の決定」）。
v1.0.0 の「参考文献のスタイル」は、引用の書式（番号か、著者と年か）を変える（[ロードマップ](../roadmap.md)）。
書式を変える前に、引用が持つ値を決めておかなければ、スタイルの ADR が IR を変えることになる。
IR とプラグインの ABI を変えるので、1.0.0 の前に入れる（[ADR 0174](0174-compatibility-promises-for-1-0.md)）。

### 今の引用の組み方

文書の組み立て（S1）は、`@bibliography` の一覧ごとに、その範囲で最初に引用された順にキーへ 1 から番号を振る（[`numberCitations`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-assemble/src/Golem/Assemble.hs#L727-L745)、[golem-doc ADR 0008](../golem-doc/adr/0008-multiple-index-and-bibliography.md)）。
印の番号は、印の位置から一覧を決め、その一覧の中でキーの番号を引く（[`citeNumber`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-assemble/src/Golem/Assemble.hs#L163-L170)）。

本文の印は、三つの出力がそれぞれ `[n]` の文字列を作る。

- PDF は、golem-layout が `[n]` を組む。番号を引けないときはキーを組む（[`Cite sp k`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-layout/src/Golem/Layout/Japanese.hs#L563)）。
- HTML と EPUB は、一覧の項目へのリンク `<a class="cite" href="…">[n]</a>` を出す。本に `@bibliography` がなければ `<span class="cite">[n]</span>` とする（[`Cite sp k`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-html/src/Golem/Html.hs#L700-L706)、[golem-html ADR 0003](../golem-html/adr/0003-cite-links-across-files.md)）。
- プレーンテキストは `[n]` を出す（[`Cite sp k`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-text/src/Golem/Text.hs#L231-L233)）。

一覧の書誌の一件は golem-bibliography が組み、媒体はその文字列を共有する（[golem-doc ADR 0005](../golem-doc/adr/0005-bibliography-fields.md)）。
この ADR は一覧の書誌を変えない。

G02021 は二つの原因（キーが書誌データにないことと、キーを一つ書かなかったこと）を一つのコードにまとめている（[docs/diagnostics.md の G02021](../diagnostics.md#g02021)）。
複数のキーを許すと「一つ書かなかった」は原因でなくなるので、この機会に原因ごとのコードに分ける。

### ほかの処理系

InDesign のヘルプに、引用と参考文献を組む組み込みの機能の記載は見つからなかった（調査による）。
InDesign の振る舞いを確かめられないので、仕様書の規則（[仕様書の「仕様が不明瞭な場合」](../specifications.md#仕様が不明瞭な場合)）により TeX と LaTeX に従う。
JLReq は引用の書式を決めていない。

LaTeX は、`\cite[p.~5]{knuth1981}` の任意の引数で後置きの文言（postnote）を書き、`\cite{a,b}` で複数の文献を一度に引く。
biblatex は、前置きの文言（prenote）と、`\cites[p.~5]{a}[ch.~2]{b}` による文献ごとの前置きと後置きを加える。
後置きは自由な文字列で、biblatex は数字だけなら `p.` を、範囲なら `pp.` を付ける。

CSL（Citation Style Language）は、引用の一件ごとに、位置（locator）とその種類（label）、前置き（prefix）、後置き（suffix）を持つ。
位置の種類は、`appendix`、`article-locator`、`book`、`canon`、`chapter`、`column`、`elocation`、`equation`、`figure`、`folio`、`issue`、`line`、`note`、`opus`、`page`、`paragraph`、`part`、`rule`、`section`、`sub-verbo`、`supplement`、`table`、`timestamp`、`title`、`verse`、`volume` の 26 である（CSL 1.0.2 の仕様の「Locators」の term の一覧）。
Golem の書誌データは CSL-JSON なので、引用の値も CSL の形に合わせると、「参考文献のスタイル」で CSL の書式を読むときに値を写し直さずに済む。

### ほかの ADR との関係

引用の番号を PDF のリンクにすることは、[ADR 0267](0267-pdf-bookmarks-and-links-inside-the-document.md) が扱う。
この ADR は、どの番号がどのキーを指すかを、リンクを作れる形で出力まで運ぶ。
ほかの ADR に依存しない。

## 実装すること

### 記法

```
[cite knuth1981]
[cite knuth1981 lamport1994 goossens1993]
[cite knuth1981 page=5]
[cite knuth1981 page=5...7]
[cite knuth1981 page=xii]
```

- 位置引数のすべてを書誌データのキーとして読む。順は書いた順である。`*[式]` で配列を展開してもよい（[ADR 0112](0112-spread-arguments.md)）。
- `page` は、引用した文献の頁である。値は、自然数（`page=5`）、自然数の範囲（`page=5...7`。範囲の形の語は範囲として読む、[ADR 0135](0135-range-words-read-as-range-expressions.md)）、文字列（`page=xii`、`page="5f."`）のいずれかである。
- `page` は、キーが一つの引用にだけ書ける。キーが二つ以上の引用に書くと G02149 とする。どのキーの頁かを記法から決められないからである。文献ごとに頁が要るときは `[cite a page=5][cite b page=7]` と書く。
- 散文スロットは、今と同じく取らない（G02038）。

diagnostic は次のとおりとする。
一つの `[cite]` に複数の原因があれば、それぞれを書いた順に報告し、引用を作らない。

| コード | 原因 |
| --- | --- |
| G02021 | キーが書誌データにない。一つの引用の中の知らないキーを、書いた順に一度ずつ報告する |
| G02147 | 一つの引用に同じキーを二度書いた |
| G02148 | `page` の値が頁として読めない（空の文字列、負の数、整数でない数、負の端を持つ範囲、真偽値、`nil`、配列、連想配列） |
| G02149 | キーが二つ以上の引用に `page` を書いた |
| G02150 | 位置引数がキーとして読めない（名前でも文字列でもない値） |
| G02151 | キーを一つも書かなかった |

G02021 の意味は「キーが書誌データにない」だけになり、メッセージ `cite には書誌データのキーを一つ書きます` は使わなくなる。
コードの番号は、採択のときに、使われていない番号であり同じ時期の ADR と重ならないことを確かめて振り直した（「決めたことの記録」）。

### データ構造

IR の引用を、引用の一件の列にする。

```haskell
  | Cite !SrcSpan ![CiteItem r] -- one or more, the keys distinct

data CiteItem r = CiteItem
  { citKey :: !Text,
    citLocator :: !(Maybe Locator),
    citPrefix :: ![InlineF r],
    citSuffix :: ![InlineF r]
  }

data Locator = Locator
  { locLabel :: !LocatorLabel, -- the 26 locator terms of CSL 1.0.2
    locValue :: !LocatorValue
  }

data LocatorValue
  = LocNumber !Integer -- 0 or more
  | LocRange !Integer !Integer -- 0 <= from <= to
  | LocText !Text -- not empty
```

`LocatorLabel` は CSL の 26 の種類を一つずつ構成子に持つ列挙型である。
欄の名前を `cit` で始めるのは、チャネルの項目の `ciKey` と衝突させないためである。

型は CSL と biblatex の値をすべて持てる広さにし、実装は狭くする。

- 記法が作るのは、前置きと後置きの空な一件と、種類が `page` の位置だけである。
- プラグインと Emet の関数が、種類が `page` でない位置か、空でない前置きか後置きを持つ引用を出すと、プラグインの出力の検査（`Golem.Doc.Validate`）が「まだ組めない引用の値」として不正な出力（G06009）とする。黙って捨てずに止める。
- 「参考文献のスタイル」が、ほかの種類の位置の文言と、前置きと後置きを組む規則を決め、検査を緩める。そのとき IR は変わらない。

検査は、このほかに、一件もない引用、同じキーの二件、空の `LocText`、負の数と逆向きの範囲を不正とする。

CDDL の引用は、新しいタグ 25 の次の形になり、タグ 15 は廃止する（[golem-doc ADR 0006](../golem-doc/adr/0006-integer-range-in-ir.md) の CDDL の規則に従う）。
欄の型が変わるので、段落のタグ 0 を 10 に替えたときと同じく、タグを使い回さずに新しくする。
新しいタグの番号は、[ADR 0263](0263-notes-with-more-than-one-paragraph.md) の注のタグ 23 と 24 の後に置いた。

```
/ [25, span, items: [1* cite-item]]  ; citation (15 is retired)
cite-item = [key: tstr, locator: locator / null, prefix: inlines, suffix: inlines]
locator = [label: locator-label, value: locator-value]
locator-label = "appendix" / "article-locator" / "book" / "canon" / "chapter" / "column" / "elocation" / "equation" / "figure" / "folio" / "issue" / "line" / "note" / "opus" / "page" / "paragraph" / "part" / "rule" / "section" / "sub-verbo" / "supplement" / "table" / "timestamp" / "title" / "verse" / "volume"
locator-value = [0, uint64] / [1, from: uint64, to: uint64] / [2, tstr .size (1..)]
```

IR とプラグインの ABI が変わるので、`abiVersion` を上げる（[ADR 0052](0052-plugin-abi-version-bump-rule.md)）。
CBOR の読み書き（`Golem.Doc.Cbor`）、Emet の組み込みの型（`Golem.Emet.Builtins` の `Cite`）、IR の生成器（`Golem.DocGen`）、引用を辿る関数（`nameErrors`、`bodyInlines`、正規表現スタイルの一字の置き換え）を合わせて変える。
前置きと後置きの inline は、注と同じく本文の外の inline として辿る。

### 番号

`numberCitations` は、一つの引用の印のキーを書いた順に並べて数える。
番号の振り方（一覧ごとに、最初に引用された順に 1 から）は変えない。
`[cite c a]` が最初の引用なら、c が 1、a が 2 になる。
一つの引用のキーはすべて同じ一覧に載る。
一覧はキーではなく印の位置で決まるからである。

### 本文の印の書式

今の既定の書式（番号）の印を、次の規則で組む。
「参考文献のスタイル」はこの書式を変えてよい。
この ADR が固定するのは、引用が持つ値である。

1. 位置を持つ件が一つもなければ、番号を昇順に並べ、三つ以上連続する番号を `a–b`（U+2013 EN DASH）にまとめ、残りを `, ` で区切る。`[1, 2]`、`[1–3]`、`[1, 3–5, 7]` になる。
2. 位置を持つ件があれば、件を書いた順に並べ、`; ` で区切る。位置は番号の後に `, ` をはさんで置く。記法から作れるのは `[1, p. 5]` のような一件の引用だけである。
3. `page` の位置は、`LocNumber` と `LocText` を `p. 5`、`p. xii`、`LocRange` を `pp. 5–7` と組む。両端の等しい `LocRange` は `p. 5` と組む。
4. 番号を引けない件は、今と同じく、PDF ではキーを組み、HTML とプレーンテキストでは何も出さない。

縦組みでも同じ文字列を組む。
今の `[n]` と同じく、番号と `p.` は算用数字とラテン文字のまま組む。

書式の規則は、golem-doc に純粋な関数として一つだけ置く。

```haskell
data CitePiece = CiteNumber !Text !Int | CiteText !Text -- a number and the key it stands for, or text

citationPieces :: [(CiteItem r, Maybe Int)] -> [CitePiece]
```

golem-layout、golem-html、golem-text は、どれもすでに golem-doc に依存しているので、golem-* のあいだの依存は増えない。
PDF とプレーンテキストは片の文字列をつなぎ、HTML は `CiteNumber` をリンクにする。

### HTML と EPUB

引用の印は、`<span class="cite">` の中に、括弧、区切り、位置の文字列と、番号ごとのリンクを置く。

```html
<span class="cite">[<a href="#cite-knuth1981">1</a>, p. 5]</span>
<span class="cite">[<a href="#cite-a">1</a>–<a href="#cite-c">3</a>]</span>
```

- リンクの行き先は、今と同じく、その印が載る一覧の、そのキーの項目の `id` である（[golem-html ADR 0003](../golem-html/adr/0003-cite-links-across-files.md)）。
- まとめた範囲の途中の番号（`[1–3]` の 2）は、文字に出ないのでリンクを持たない。
- 本に `@bibliography` がなければ、リンクを付けず、同じ `<span class="cite">` に文字列だけを置く。

キーが一つの引用の印も、この形に変わる。
今は `<a class="cite">` が括弧ごとリンクにしている（メンテナーが決めること 3）。

### PDF とプレーンテキスト

PDF は、`citationPieces` の文字列を、今の `[n]` と同じ経路で組む。
番号をリンクにするのは [ADR 0267](0267-pdf-bookmarks-and-links-inside-the-document.md) である。
プレーンテキストは同じ文字列を出す。

### 文書とロードマップ

実装は次の文書を更新する。

- [docs/specifications.md](../specifications.md) の「引用と参考文献」の節と、「索引」の節の末尾の PDF の引用の印の段落。
- [docs/markup.md](../markup.md) の「引用」の節に、複数のキーと `page` を書く。
- [docs/diagnostics.md](../diagnostics.md) に新しいコードを足し、G02021 の意味とメッセージから、キーを一つ書くことを求める側を除く。
- マニュアルの参考文献の章に、頁と複数の文献の書き方を足す。

実装を終えたら、[docs/roadmap.md](../roadmap.md) から次の記述を消す。

- v1.0.0 の「LaTeX との差を埋める項目」の「引用の頁の指定と複数の文献」の項目。同じ節の冒頭の「記法、意味論の IR、プラグインの ABI を変える項目（…）」の括弧の中の「引用の頁」。

この項目はほかの項目から取り出したものではないので、ほかの項目の記述は消さない。
「参考文献のスタイル」の項目は残る。

## 実装しないこと

- **文献ごとの頁を一つの印に書く記法**：biblatex の `\cites[p.~5]{a}[p.~7]{b}` にあたるもの。IR は持てるが、記法は「参考文献のスタイル」で、著者と年の書式とあわせて決める。
- **前置きと後置きの記法**：「〜を参照」「ほか」のような文言。IR は持てるが、組む規則がスタイルに依存する。
- **`page` のほかの位置の種類**：`chapter`、`section` など。種類ごとの文言（`ch.`、「章」など）がスタイルに依存する。
- **引用の書式の選択**：著者と年の書式、脚注の書式。v1.0.0 の「参考文献のスタイル」が扱う。
- **連続する引用の印の結合**：`[cite a][cite b]` を `[1, 2]` に組むこと。書いたとおりに組む。
- **一覧の書誌の変更**：書誌の一件は golem-bibliography が組むまま変えない。

## 不変条件

番号の引ける引用について述べる。
引用の番号の集まりを N とする。

- **I1 番号は一度ずつ表れる**：位置を持たない引用の印の文字列に表れる番号と、まとめた範囲が覆う番号を合わせた集まりは、N と等しく、どの番号も一度だけ覆われる。
- **I2 書いた順によらない**：位置を持たない引用の印の文字列は、キーの並べ替えで変わらない。
- **I3 まとめは三つから**：位置を持たない印の片は、番号の真に増える列である。範囲にまとめた片は三つ以上の連続する番号を覆い、範囲でない隣り合う二つの片の番号の差は 1 より大きいか、二つだけの連続である。
- **I4 位置のある印は書いた順**：位置を持つ件のある引用の印は、件を書いた順に番号を並べる。
- **I5 番号の振り方**：一覧の番号の順は、その一覧の範囲の引用の印のキーを、印の文書の順と印の中の書いた順で平らにした列から、二度めの出現を除いた順と等しい。
- **I6 diagnostic は原因ごと**：評価は、上の表の原因の一つだけを含む `[cite]` に、そのコードだけを出す。原因を含まない `[cite]` は、書いたキーと同じ数の件を持つ `Cite` を一つ作る。
- **I7 IR の往復**：どの `Cite` も、CBOR に書いて読むと元に戻り、CDDL に合う。
- **I8 キーが一つの印は変わらない**：位置のない一つのキーの引用の印の文字列は、PDF とプレーンテキストで今と同じ `[n]` である。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| キーの数 | 0、1、2、3、4 |
| 番号の並び | 連続が 1、2、3、4 の長さ、飛びのある並び、逆順に書いた並び |
| キーの重なり | なし、二つが同じ、三つが同じ |
| 知らないキー | なし、一つ、二つ（書いた順に報告） |
| `page` の値 | `0`、`5`、`5...5`、`5...7`、`xii`、`""`、`-1`、`1/2`、`true`、配列 |
| `page` とキー | キーが一つ、キーが二つ |
| 一覧 | `@bibliography` なし、一つ、二つ（印の前後で一覧が変わる） |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
テストの名前には不変条件の番号を入れる。

- **golem-doc のテスト**：I1 から I4 と I8 を `citationPieces` で確かめる。番号の集まりを 1 から 6 の部分集合（64 通り）とその並べ替えで列挙し、I1、I2、I3 の述語を確かめる。I7 は、位置の三つの値と前置きと後置きを持つ引用の CBOR の往復と CDDL の検査である。検査が、空の件の列、同じキー、`page` でない種類、空でない前置きを不正とすること。
- **golem-eval のテスト**：I6。表の原因ごとの原稿と、複数の原因を含む原稿の報告の順。`*[式]` で展開したキーと、`page=5...7` が `LocRange` になること。
- **golem-assemble のテスト**：I5。一覧が一つと二つの文書で、複数のキーの印の番号の順を確かめる。
- **golem-html のテスト**：番号ごとのリンク、まとめた範囲の両端だけのリンク、`@bibliography` のない本のリンクのない印、別のファイルの一覧への相対リンク。
- **golem-layout と golem-text のテスト**：I8 と、`[1, p. 5]`、`[1–3]` の文字列。
- **golem-driver のテスト**：頁と複数の文献を持つ原稿の PDF、HTML、EPUB、プレーンテキストのゴールデンのテスト。

## トレードオフ

- 文献ごとの頁を一つの印に書けない。`[cite a page=5][cite b page=7]` は `[1, p. 5][2, p. 7]` になり、biblatex の `[1, p. 5; 2, p. 7]` にならない。記法を後で足しても、IR は変わらない。
- 頁の文言を `p.` と `pp.` に固定する。和文の本で「5 頁」と組みたい場合に合わない。書誌の一件と違い、引用の印は和文と欧文の文献が一つの括弧に混ざりうるので、文献の言語で文言を選ぶ規則をこの ADR では決めない。
- 昇順に並べてまとめるので、著者が意味を込めた順（重要な順など）は印に残らない。位置を持つ引用だけは書いた順を残す。
- キーが一つの引用の HTML が変わるので、HTML と EPUB のゴールデンのテストの期待値が変わる。
- 前置きと後置きと位置の種類を IR に持つが、出力は組まずに検査で止める。型と実装の差は、スタイルの ADR が埋めるまで残る。

## メンテナーが決めること

1. **複数の文献の印の並び**
   - 推奨：番号の昇順に並べ、三つ以上の連続をまとめる（`[1–3]`）。biblatex の `numeric-comp` の振る舞いで、番号の書式では読み手が番号から一覧を引くので、昇順のほうが引きやすい。既定だけで整った印になる。
   - 退けた案：書いた順のまま並べ、まとめない（`[3, 1, 2]`）。biblatex の `numeric` の既定だが、番号を引きにくい。
   - 退けた案：昇順に並べるがまとめない（`[1, 2, 3]`）。まとめの規則を決めずに済むが、多くの文献を引く印が長くなる。
2. **頁の書き方**
   - 推奨：キーワード引数 `page`。値は数、範囲、文字列とし、CSL の位置の種類 `page` に写す。値を構造で持つので、スタイルが `p.` と `pp.` と「頁」を選べる。
   - 退けた案：散文スロットに自由な文字列で書く（`[cite knuth1981: p. 5]`、biblatex の後置き）。キーごとにスロットを `|` で分ければ複数の文献の頁も書けるが、文言が原稿に入るので、スタイルを変えても `p.` が残る。
   - 退けた案：位置引数とキーワード引数を交互に書く（`[cite a page=5 b page=7]`）。キーワード引数を位置引数の後に書く規則（G01019）と、同じキーの二度めの禁止（G02077）に反する。
3. **キーが一つの引用の HTML**
   - 推奨：すべての引用を `<span class="cite">` と番号ごとのリンクの一つの形にする。形が一つなので、CSS と検査が一通りで済む。
   - 退けた案：キーが一つのときだけ今の `<a class="cite">[n]</a>` を残す。今の出力を変えないが、同じ印に二つの形ができる。
4. **前置きと後置きと位置の種類を今 IR に入れるか**
   - 推奨：入れて、出力は検査で止める。「参考文献のスタイル」が IR と ABI を変えずに済み、1.0.0 の後の互換の約束（[ADR 0174](0174-compatibility-promises-for-1-0.md)）を破らない。
   - 退けた案：キーと `page` の位置だけを入れる。型は小さいが、スタイルの ADR が IR を変えることになり、1.0.0 の後なら互換を壊す。

## 決めたことの記録

2026-11-09 に、tett23 がすべて推奨のとおりに決めた。

1. 複数の文献の印は、推奨のとおり番号の昇順に並べ、三つ以上の連続をまとめる（`[1–3]`）。
2. 頁は、推奨のとおりキーワード引数 `page` で書く。
3. 引用の HTML は、推奨のとおりキーが一つの引用も含めて `<span class="cite">` と番号ごとのリンクの一つの形にする。
4. 前置きと後置きと位置の種類は、推奨のとおり今 IR に入れ、出力は検査で止める。

diagnostic のコードは、採択のときに、docs/diagnostics.md と origin/main のコードで使われていない番号であり、同じ時期の ADR と重ならないことを確かめて、G02147 から G02151 とした。
草案の仮の番号から振り直した。

## 参考文献

- [2026-10-17 の調査](../audits/2026-10-17-latex-gap-for-v1.md) の「12. 引用の頁の指定と複数の文献」と「所有者の決定」
- [ADR 0052](0052-plugin-abi-version-bump-rule.md)、[ADR 0112](0112-spread-arguments.md)、[ADR 0135](0135-range-words-read-as-range-expressions.md)、[ADR 0174](0174-compatibility-promises-for-1-0.md)、[ADR 0267](0267-pdf-bookmarks-and-links-inside-the-document.md)
- [golem-doc ADR 0005](../golem-doc/adr/0005-bibliography-fields.md)、[golem-doc ADR 0006](../golem-doc/adr/0006-integer-range-in-ir.md)、[golem-doc ADR 0008](../golem-doc/adr/0008-multiple-index-and-bibliography.md)
- [golem-html ADR 0003](../golem-html/adr/0003-cite-links-across-files.md)、[golem-eval ADR 0003](../golem-eval/adr/0003-evaluation-diagnostic-codes.md)、[golem-parser ADR 0013](../golem-parser/adr/0013-splat-after-keyword-arguments.md)
- LaTeX2e unofficial reference manual の「\cite」, https://latexref.xyz/
- biblatex, https://ctan.org/pkg/biblatex（`\cites`、prenote と postnote、`numeric-comp`。この調査で本文は読み直していない）
- Citation Style Language 1.0.2 の仕様, https://docs.citationstyles.org/en/stable/specification.html の「Locators」（位置の種類の一覧は 2026-11-09 に取得して確かめた）
- Adobe, InDesign User Guide, https://helpx.adobe.com/indesign/desktop.html（引用の組み込みの機能の記載は見つからなかった。本文は読めていない）
