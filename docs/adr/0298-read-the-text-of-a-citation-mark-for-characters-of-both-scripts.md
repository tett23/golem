# ADR 0298: 両用の字の最も近い字を、引用の印の文字列で決める

ステータス: 採択（未実装）

## 文脈

### [ADR 0277](0277-keep-the-page-label-of-a-citation-mark-with-its-value.md) の C2 が成り立たない入力

[ADR 0277](0277-keep-the-page-label-of-a-citation-mark-with-its-value.md) の C2 は、引用の印を含む段落の項目を、印を同じ文字列のテキストに替えた段落の項目と比べる。
違ってよいのは、頁の文言と値のあいだのグルーの前の罰点 10000 だけである。

[ADR 0283](0283-decide-the-roles-of-characters-of-both-scripts-across-inline-boundaries.md) は、区間の外の両用の字（引用符、アポストロフィ、ハイフン類、ダッシュ）の「最も近い字」を段落の字の並びで探すとし、引用の印に当たったら探すのをやめて、その側に欧文の字はないものとした。
印を替えたテキストの `[` と `]` では、探すのをやめない。
そのため、区間の外で両用の字が印のすぐ隣にあり、反対の側に欧文の字がない段落では、両用の字の役割が二つの段落で違う。
C2 はそこで成り立たない。

[ADR 0283](0283-decide-the-roles-of-characters-of-both-scripts-across-inline-boundaries.md) の実装（[#835](https://github.com/tett23/golem/pull/835)）は、振る舞いではなくテストを狭めた。
引用の印の列挙は、区間の外で両用の字が印のすぐ隣にある入力で C2 を調べない（[`dualAtMark`](https://github.com/tett23/golem/blob/39d97a1af61ea5b0dfef153d1e365273377c9800/modules/golem-layout/test/CiteBreakEnum.hs#L242-L262)、[`violations`](https://github.com/tett23/golem/blob/39d97a1af61ea5b0dfef153d1e365273377c9800/modules/golem-layout/test/CiteBreakEnum.hs#L214-L240)）。
仕様書の「行分割」の節にもその文がある。
どちらの ADR も、この除外を決めていない。

### 今の振る舞い

2026-11-10 に origin/main（`39d97a1a`）の golem-layout のテストを `cabal repl` で読み込み、引用の印の列挙と同じ組み方の環境（[`composeEnv`](https://github.com/tett23/golem/blob/39d97a1af61ea5b0dfef153d1e365273377c9800/modules/golem-layout/test/LineBreakEnum.hs#L261-L272)、禁則は strict、区間なし、文献 a の番号は 1）で組んだ。
「印」の行は `[cite a]` を、「テキスト」の行は印を同じ文字列のテキスト `[1]` に替えた段落を表す。
`W` は欧文の語の箱、`J` は和文の字の箱、空きの値は字の大きさを 1 とした幅である。

| 原稿 | 印 | テキスト |
| --- | --- | --- |
| `あ—[cite a]い` | `あ`、字間 0、`—`(J)、和欧間 0.25、`[1]`(W)、和欧間 0.25、`い` | `あ`、和欧間 0.25、`—`(W)、`[1]`(W)、和欧間 0.25、`い` |
| `あ[cite a]—い` | `あ`、和欧間 0.25、`[1]`(W)、和欧間 0.25、`—`(J)、字間 0、`い` | `あ`、和欧間 0.25、`[1]`(W)、`—`(W)、和欧間 0.25、`い` |
| `あ“[cite a]”い` | `あ`、括弧の空き 0.5、`“`(J)、`[1]`(W)、`”`(J)、括弧の空き 0.5、`い` | `あ`、和欧間 0.25、`“`(W)、`[1]`(W)、`”`(W)、和欧間 0.25、`い` |
| `あ[cite a]’い` | `あ`、和欧間 0.25、`[1]`(W)、`’`(J)、括弧の空き 0.5、`い` | `あ`、和欧間 0.25、`[1]`(W)、`’`(W)、和欧間 0.25、`い` |
| `あ[cite a]–[cite b]い` | `[1]`(W)、罰点 10000、和欧間 0.25、`–`(J)、和欧間 0.25、`[2]`(W) | `[1]`(W)、`–`(W)、明示のハイフンの罰点 50、`[2]`(W) |
| `see “[cite a]” and` | `see`、語間 0.25、空き 0.5、`“`(J)、`[1]`(W)、`”`(J)、語間 0.25、`and` | `see`、語間 0.25、`“`(W)、`[1]`(W)、`”`(W)、語間 0.25、`and` |
| `as in [cite a]— and` | `[1]`(W)、和欧間 0.25、`—`(J)、語間 0.25、`and` | `[1]`(W)、`—`(W)、語間 0.25、`and` |
| `power—[cite a]` | `power—`(W)、明示のハイフンの罰点 50、`[1]`(W) | 同じ |
| `[cite a]’s` | `[1]`(W)、`’s`(W) | 同じ |

印の行では、両用の字が和文の字になり、印とのあいだに和欧間の空きが入る。
`—` と `[1]` のあいだには分割の候補（和欧間のグルー）ができ、テキストの行の `—[1]` は一つの欧文の語として続く。
`–` で二つの印をつないだ範囲は、印の行では前後に空きのある和文のハイフン類になり、`–` の後で分けられない。
反対の側に欧文の字がある `power—[cite a]` と `[cite a]’s` は、どちらの段落でも同じである。

同じ日に、`golem new` の雛形（日本語の本は行長を 20 字の横組みにしたもの、英語の本はそのまま）に参考文献を足した本を組み、PDF を shem で画像にして見た。
日本語の本では、`あいう—[cite a]えお` が `あいう— [1] えお` と `—` の後ろに空いて組まれ、`あいう—\[1]えお` は `あいう —[1] えお` と `—` の前に空いて組まれた。
英語の本（区間なし）では、`as shown “[cite a]” here` の `”` が後ろの語間の空白に重なり、`here` の `h` に接して描かれた。
`he said ” here` のように、テキストだけで `”` が和文の字になる段落も同じ形に描かれるので、重なりそのものは和文の字になった `”` を欧文だけの本で描くときの問題であり、この ADR の範囲の外である。
ただし、印の隣の引用符を和文の字にする今の規則は、英語の本の `“[cite a]”` という普通の書き方でこの描画に当たる。
`[lang en: as shown “[cite a]” here]` では、二つの引用符は欧文の語に入り、重ならなかった。

### 印の文字の扱いの食い違い

[ADR 0283](0283-decide-the-roles-of-characters-of-both-scripts-across-inline-boundaries.md) は、印で探すのをやめる理由を「コードと印の字は本文の語ではない」とした（「実装しないこと」の「ほかのインラインの中の字」）。
しかし、引用の印の字は、ほかの規則では本文の欧文の字として扱われている。

- 印の文字列は、地の文と同じ大きさと書体で、ベースラインの上に組む（[`citeTextPieces`](https://github.com/tett23/golem/blob/39d97a1af61ea5b0dfef153d1e365273377c9800/modules/golem-layout/src/Golem/Layout/Japanese.hs#L915-L925)）。注の印は上付きにもなるが、引用の印はならない。
- [ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md) は、語が引用の印の境目で箱に分かれても、明示のハイフンの候補をつないだ語で決める。`power—[cite a]` の `—` の後の候補は、`[1]` を語の続きとして決まる。
- [ADR 0285](0285-read-soft-hyphens-at-inline-boundaries-in-the-joined-word.md) も、引用の印の境目で分かれた語のソフトハイフンをつないだ語で読む。
- 解決した相互参照（`[ref-number]` など）は、[ADR 0283](0283-decide-the-roles-of-characters-of-both-scripts-across-inline-boundaries.md) で字の並びを切らない。タグ付き PDF では、相互参照も引用の印も同じ `Reference` の要素である。

つまり、印の `[1]` は語の箱としては隣の欧文の語につながるのに、両用の字の役割を決めるときだけは字がないものとして扱われる。

### 拠るもの

- JLReq は、和文の中の欧文を一つのまとまりとして扱い、欧文と和文のあいだに空きを入れる。引用の印については定めていない。
- TeX には和文と欧文の両用の字の区別がない。`power---\cite{a}` の `---` は、`\cite` の出力の `[1]` が何であっても欧文の字である（[ADR 0283](0283-decide-the-roles-of-characters-of-both-scripts-across-inline-boundaries.md) の「拠るもの」と同じ）。
- InDesign の振る舞いは、Golem の開発の環境で動かせないので確かめていない。InDesign には引用の印の機能がないので（[ADR 0277](0277-keep-the-page-label-of-a-citation-mark-with-its-value.md) の「拠るもの」）、印は書き手が地の文として打つ文字列であり、組版はテキストの `[1]` と同じになると考えられる。

## 実装すること

### 1. 引用の印の文字列を字の並びに入れる

区間の外の両用の字の最も近い字を探すとき（[ADR 0283](0283-decide-the-roles-of-characters-of-both-scripts-across-inline-boundaries.md) の「実装すること」の 1）、引用の印に当たったら、印の文字列（`citationText` の文字列。既定の書式では `[1]`、`[1, p. 5]` など）の字を、字の並びの字として読む。
印の外から探すときは、印の文字列の、探す向きの端から字を読む。
両用の字を飛ばすことと、見つけた字が欧文の字かをその字の見た目（区間の言語を含む）で決めることは、テキストの字と同じである。

既定の書式の印は `[` で始まり `]` で終わるので、印のすぐ隣の両用の字は、いつも欧文の語に入る。
印の文字列の書き方が変われば（「参考文献のスタイル」）、その字で決まる。

注の印、ルビ、縦中横、番号、本文の中のコード、強制改行、`[aki]` では、今のとおり探すのをやめる。

実装は、[`edgeOf`](https://github.com/tett23/golem/blob/39d97a1af61ea5b0dfef153d1e365273377c9800/modules/golem-layout/src/Golem/Layout/Japanese.hs#L505-L538) の `Cite` の場合に、`citationPieces` と `ceCiteNumber` で印の文字列を作り、テキストと同じ規則で端の字を返す形を想定する。
印の中の字の組み方（`citeTextPieces`）と、印の項目は変えない。

### 2. 列挙と単体テスト

- 引用の印の列挙で、`dualAtMark` の除外をやめ、すべての入力で C2 を調べる。
- [ADR 0283](0283-decide-the-roles-of-characters-of-both-scripts-across-inline-boundaries.md) の E4 のテストの、探すのをやめるインラインの一覧（[`stoppers`](https://github.com/tett23/golem/blob/39d97a1af61ea5b0dfef153d1e365273377c9800/modules/golem-layout/test/JoinedWordEnum.hs#L511-L517)）から引用の印を外し、4 の不変条件のテストに移す。

### 3. 文書

- [docs/specifications.md](../specifications.md) の「両用の文字」の節で、探すのをやめるインラインの一覧から引用の印を外し、印の文字列の字を字の並びに入れることを書く。
- 同じく「行分割」の節の、引用の印の列挙で C2 を調べない入力の二文を消す。
- [ADR 0283](0283-decide-the-roles-of-characters-of-both-scripts-across-inline-boundaries.md) のステータスの行に「（引用の印で探すのをやめること）は ADR 0298」を足す。
- [ADR 0277](0277-keep-the-page-label-of-a-citation-mark-with-its-value.md) は変えない。C2 は、書かれたとおりにすべての入力で成り立つようになる。

### 4. 出力の変化

区間の外で、両用の字が引用の印のすぐ隣にあり、反対の側に欧文の字がない段落の空きと行の分け方が変わる。
その両用の字は欧文の語に入り、印との空きがなくなり、印とのあいだで分けられなくなる。
2026-11-10 に、リポジトリの `.gm` に両用の字と印が隣り合う書き方がないことを `rg` で確かめた。
実装のプルリクエストで、決定性のハッシュと見た目の回帰テストの変わったものと、その理由を説明に書く。

## 実装しないこと

- **注の印**：注の印は上付きにもなり、本文の語の字と同じ大きさで並ぶとは限らないので、今のとおり探すのをやめる。
- **ルビ、コード、縦中横、番号**：[ADR 0283](0283-decide-the-roles-of-characters-of-both-scripts-across-inline-boundaries.md) のとおりである。
- **和文の字になった両用の字を欧文だけの本で描くときの重なり**：「今の振る舞い」で見た `he said ” here` の描き方は、印に関係なく起こる。別に扱う。
- **両用の字の書体**：[ADR 0283](0283-decide-the-roles-of-characters-of-both-scripts-across-inline-boundaries.md) の「実装しないこと」のとおり変えない。
- **HTML と EPUB**：閲覧環境が字を組むので、変えない。

## 不変条件

「印」は、PDF の本文の、番号を引ける引用の印とする。
「テキストの段落」は、それぞれの印を、その印の文字列（`citationText`）のテキストに替えた段落とする。
「両用の字」は、区間の外の両用の字とする。

- **M1 C2 はどの入力でも成り立つ**：引用の印の列挙のすべての入力（区間なし、`[lang en]`、`[lang ja]`）で、[ADR 0277](0277-keep-the-page-label-of-a-citation-mark-with-its-value.md) の C2 が成り立つ。除外する入力はない。
- **M2 印とテキストで同じ役割**：印を含む段落とテキストの段落とで、段落のそれぞれの字が欧文の語の箱（`bcExpandable` の箱）に入るかの列が等しい。
- **M3 印の向こうの字を見ない**：両用の字と、和文の字か欧文の字 X とのあいだに印を挟んだ入力で、X を `b` に替えても `あ` に替えても、その両用の字が欧文の語に入るかは変わらない。既定の書式では、いつも欧文の語に入る。
- **M4 ほかのインラインは今のとおり**：注の印、ルビ、コードを挟んだ入力では、[ADR 0283](0283-decide-the-roles-of-characters-of-both-scripts-across-inline-boundaries.md) の E4 のとおり、両用の字の役割はこの ADR の前と同じである。

[ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md) の L1 から L13 と、[ADR 0277](0277-keep-the-page-label-of-a-citation-mark-with-its-value.md) の C1 は、そのまま成り立つ。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 両用の字 | `—`、`–`、`’`、`”`、`“`、`‘` |
| 印との位置 | 印の直前、印の直後、二つの印のあいだ（`[cite a]–[cite b]`） |
| 反対の側 | 和文の字（`あ`）、欧文の字（`power`、`s`）、空白、段落の端、別の印 |
| 印の種類 | 位置なし、`page=5`、`page=5...7`、二つの文献（`[1, 3]`）、`@bibliography` のある本の番号のリンク |
| 区間 | なし、`[lang en]`、`[lang ja]` |
| あいだのもの | なし、ソフトハイフン、索引の印 |
| 挟むインライン（M3、M4） | 引用の印、注の印、ルビ、コード |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
テストの名前には、M1 から M4 の番号を入れる。

- **M1**：引用の印の列挙から `dualAtMark` の除外を消す。プルリクエストの段（部品 2 個）と、毎晩の段（`GOLEM_ENUM_CITE_DEPTH=3`）で C2 が成り立つこと。今は区間の外の `—` と印の組で失敗する。
- **M2**：「今の振る舞い」の表の九つの原稿と、境界の入力の表の「両用の字」「印との位置」「反対の側」「区間」の組で、欧文の語に入る字の列が印とテキストで等しいこと。今は表の上から七つで失敗する。
- **M3**：`b` と `あ` のそれぞれと `[strong: —]` のあいだに印を挟み、`—` が欧文の語に入ること。今は欧文の語に入らないので失敗する。
- **M4**：E4 のテストのうち、注の印、ルビ、コードの組が今のとおり成り立つこと。
- **golem-driver**：区間のない英語の本で `as shown “[cite a]” here` を組み、二つの引用符が欧文の語の箱に入り、`“` の前に語間の空白のほかの空きがないこと。

## トレードオフ

- 印の隣の両用の字の役割が、印の文字列で決まる。印の書式（「参考文献のスタイル」）を変えると、隣の両用の字の役割も変わりうる。テキストで同じ文字列を書いたときと同じ振る舞いなので、書き手が見た目から予想できる。
- 和文の本で `あ“[cite a]”い` と書くと、引用符は欧文の語に入り、和文の括弧の空きではなく和欧間の空きで組む。印の `[1]` が欧文の字で組まれる以上、隣の引用符も欧文の引用符として読むほうが、テキストの `“[1]”` と一致する。
- 字の並びを探す範囲の規則に、「印の文字列の字を読む」という種類が一つ増える。印は IR の中に字を持たないので、探すときに印の文字列を作る。

## 決めたことの記録

2026-11-10 に、tett23 がこの ADR の判断のすべてを推奨のとおりに決めた。

1. **印の隣の両用の字の扱い**：印の文字列の字を字の並びに入れる（案 B）。印の `[1]` は、ほかの規則（[ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md)、[ADR 0285](0285-read-soft-hyphens-at-inline-boundaries-in-the-joined-word.md)）では隣の欧文の語につながる本文の字として扱われており、両用の字の役割だけを別にする理由がない。C2 も書かれたとおりに成り立ち、テストの除外を消せる。
   - 今のとおり印で探すのをやめ、C2 から `dualAtMark` の入力を除くことを決める案（案 A）は、退けた。印とテキストとで組み方の違う入力が仕様として残り、英語の本の `see “[cite a]” and` の空きと、`[cite a]–[cite b]` の前後の空きも残る。
   - C2 の比べる段落を「印をテキストに替え、その両端で両用の字を探すのをやめた段落」と定め直す案（案 C）は、退けた。比べる段落がこの ADR の前の組版でなくなり、C2 が確かめていたこと（印にしても組み方が変わらないこと）が弱まる。案 A と同じ空きも残る。

## 参考文献

- [ADR 0187](0187-inline-language-switch.md)、[ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md)、[ADR 0215](0215-ref-number-and-ref-title-as-reference.md)、[ADR 0266](0266-citation-locators-and-multiple-keys.md)、[ADR 0277](0277-keep-the-page-label-of-a-citation-mark-with-its-value.md)、[ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md)、[ADR 0283](0283-decide-the-roles-of-characters-of-both-scripts-across-inline-boundaries.md)、[ADR 0285](0285-read-soft-hyphens-at-inline-boundaries-in-the-joined-word.md)
- [#835](https://github.com/tett23/golem/pull/835)（[ADR 0283](0283-decide-the-roles-of-characters-of-both-scripts-across-inline-boundaries.md) の実装）の説明の「Point for the maintainer: C2 of [ADR 0277](0277-keep-the-page-label-of-a-citation-mark-with-its-value.md)」
- W3C. Requirements for Japanese Text Layout (JLReq). https://www.w3.org/TR/jlreq/（英語の題が「Handling of Western Text in Japanese Text using Proportional Western Fonts」の節）
- InDesign の振る舞いは、Golem の開発の環境で動かせないので確かめていない。
