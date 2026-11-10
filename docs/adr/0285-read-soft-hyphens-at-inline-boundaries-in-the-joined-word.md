# ADR 0285: インラインの境目の隣のソフトハイフンを、つないだ語で読む

ステータス: 採択

## 文脈

### 述語と組版が別の語を見ている

[ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md) は、ソフトハイフン（U+00AD）を取り除いた位置の前の字と後の字が、同じ欧文の語の要素の中でどちらも字なら、そこを分割の候補とした。
ソフトハイフンを一つでも含む要素は、パターンでも分綴しない。
I3 と I4 は、この二つを不変条件にしたものである。

I3 と I4 の述語は、段落の字の並びでソフトハイフンを読む（[`softHyphenBreaks`](https://github.com/tett23/golem/blob/5fe4b57f2e2a11f09eaff9497b1956c8477d53a1/modules/golem-layout/test/LineBreakInvariants.hs#L501-L515)、[`i4NoHyphensWithShy`](https://github.com/tett23/golem/blob/5fe4b57f2e2a11f09eaff9497b1956c8477d53a1/modules/golem-layout/test/LineBreakInvariants.hs#L669-L700)）。
組版は、インラインごとのテキストの語で読む（[`softHyphenNotes` と `shyRole`](https://github.com/tett23/golem/blob/5fe4b57f2e2a11f09eaff9497b1956c8477d53a1/modules/golem-layout/src/Golem/Layout/Japanese.hs#L866-L913)、[`wordItems`](https://github.com/tett23/golem/blob/5fe4b57f2e2a11f09eaff9497b1956c8477d53a1/modules/golem-layout/src/Golem/Layout/Japanese.hs#L1527-L1540)）。
境目の前のテキストの終わりのソフトハイフンは、述語では語の中にあり、組版では語の終わりにある。

[ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md) は、境目にちょうど来るソフトハイフンを「実装しないこと」に置き、境目の列挙で L8 と I3 が成り立つことだけを確かめるとした。
実装（[#827](https://github.com/tett23/golem/pull/827)）は、I3 と I4 が成り立たないことを見つけた。
ソフトハイフンの隣に境目のある入力では L8 と W1 だけを調べ（[`shyAtBoundary`](https://github.com/tett23/golem/blob/5fe4b57f2e2a11f09eaff9497b1956c8477d53a1/modules/golem-layout/test/JoinedWordEnum.hs#L288-L298)）、ソフトハイフンの部品を含む入力では W2 を調べない。
仕様書の「既知の不具合」に「インラインの境目の隣のソフトハイフンを、述語と組版が別の語で読む」として載り、どちらに合わせるかは決めていない。

### 今の振る舞い

2026-11-10 に origin/main（`5fe4b57f`）の golem-layout のテストを `cabal repl` で読み込み、境目の列挙の環境（[`envOf`](https://github.com/tett23/golem/blob/5fe4b57f2e2a11f09eaff9497b1956c8477d53a1/modules/golem-layout/test/JoinedWordEnum.hs#L69-L74)、区間なし、分綴のパターンあり、行の幅 4 em）で組んだ。
「境目」は、その位置から後の部品を `[strong: …]` に入れたことを表し、`­` は U+00AD を表す。

| 部品 | 境目で分けた段落 | 一つのテキスト | 破る不変条件 |
| --- | --- | --- | --- |
| `a­`、境目、`a` | 箱 `a` と `a` のあいだに候補なし。G07123 の notice | ソフトハイフンの罰点（幅は `-` の送り、50） | I3 |
| `a`、境目、`­`、境目、`a` | 同じ。G07123 の notice | 同じ | I3 |
| `ab`、境目、`­hyphenation` | 候補なし。後の語は語の頭のソフトハイフンで分綴しない。notice なし | `ab` の後にソフトハイフンの罰点 | I3 |
| `hyphenation`、境目、`­`、境目、`x` | `hy-phen-ation` とパターンで分綴し、`x` との境目に候補なし。行は `hyphen` と `ationx` | `hyphenation` の後にソフトハイフンの罰点、パターンの分綴なし | I3、I4 |

組版は、境目の前の語の終わりのソフトハイフンを「前後が字でない」として notice にし、後の語の頭のソフトハイフンを「その要素を分けない」指定として読む。
一つのテキストでは、どちらも語の中の分割の候補である。
四つめの組では、書き手が分ける位置をソフトハイフンで指定したのに、パターンの分綴で分けている。

`[italic: hyphen]­ation` のように、語の一部に文字スタイルを付けた語の境目に分ける位置を指定すると、この形になる。

### 拠るもの

- JLReq は、欧文の語のハイフネーションの位置を欧文の組版の規則に委ね、ソフトハイフンを定めていない。
- InDesign の振る舞いは、Golem の開発の環境で動かせないので確かめていない。
- TeX の `\-` は `\discretionary{-}{}{}` であり、語の中のどこに置いても、前後のフォントの境目にかかわらず任意の分割になる。[ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md) は、フォントの境目で語が途切れても `\discretionary` の位置が変わらないことを `\showlists` で確かめた。
- [ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md) は、明示のハイフンとダッシュの後の候補を、つないだ語で決めた。理由は、文字スタイルを付けたかどうかで行の分け方が変わらないようにするためである。

## 実装すること

### 1. つないだ語のソフトハイフン

ソフトハイフンの規則（[ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md) の「実装すること」の 1）を、インラインごとの語ではなく、**つないだ語**に当てる。
つないだ語は、段落の部品の並びで、あいだに項目を作る部品を挟まずに続く欧文の語の部品（上付きと下付きの範囲のものを除く）の並びとする。
あいだのソフトハイフンだけの部品（ソフトハイフンだけのテキスト）と、アンカーの部品は、項目を作らないので並びを切らない。
これは、[ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md) の隣り合う欧文の語の箱を、部品の段階で見たものである。

つないだ語の字と、その中のソフトハイフンの位置から、[ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md) の規則で次の三つを決める。

- **候補**：取り除いた位置の前の字と後の字が、つないだ語の同じ要素の中でどちらも字である位置。要素は、つないだ語を明示のハイフンで分けたものとする。
- **分綴しない要素**：ソフトハイフンを一つでも含むつないだ語の要素。その要素の字を持つどの箱も、パターンと例外で分綴しない。
- **notice**：候補でないソフトハイフンの G07123 と G07124 を、つないだ語の中の役割で決める。語の頭のソフトハイフン（つないだ語の要素の最初の字より前のもの）は、今のとおり notice を出さない。

### 2. 境目の候補

候補が二つの箱の境目にあるときは、二つの箱のあいだにソフトハイフンの罰点（幅は `-` の送り、罰則 50、`SoftHyphen`）を一つ置く。
語の中の候補と同じく、一回目の段階から使い、突き出しの量と連続するハイフンの規則もパターンの分綴と同じに当てる。
[ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md) の明示のハイフンの罰点と同じ境目に来ることはない。
明示のハイフンの直後のソフトハイフンは、前の字が字でないので候補にならないからである。

候補の前の字か後の字が改行しない字（リンクの語、コード、改行しない範囲）なら、今のとおり候補にしない。
ソフトハイフンが改行しない字の中にあれば G07124、ないときは G07123 とする。

### 3. 実装の形

[`composeInlinesTree`](https://github.com/tett23/golem/blob/5fe4b57f2e2a11f09eaff9497b1956c8477d53a1/modules/golem-layout/src/Golem/Layout/Japanese.hs#L320-L368) が [ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md) の `leads` と同じく部品の並びをたどり、それぞれの語の部品に、つないだ語の中の位置と、つないだ語のソフトハイフンの位置を渡す形を想定する。
`wordItems` は、その位置で要素とソフトハイフンの役割を決める。
境目の罰点は、前の語の部品の項目の後に置く。
つないだ語の中にソフトハイフンがなければ、今の語の箱の作り方と変わらない。

### 4. 列挙

- [ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md) の境目の列挙（W3）で、ソフトハイフンの隣に境目のある入力で L8 と W1 だけを調べる除外をやめ、L1 から L13（L8 と L9 は [ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md) の I2 と I3 のとおり）と I4 と W1（H4 のとおりに広げたもの）を調べる。
- ソフトハイフンの部品を含む入力でも W2 を調べる。
- 部品と上限は変えない。

### 5. 文書

- [docs/specifications.md](../specifications.md) の「行分割」の節のソフトハイフンの段落に、語がインラインの境目で分かれても、候補、分綴しない要素、notice をつないだ語で決めることを書く。
- 仕様書の「既知の不具合」から、「インラインの境目の隣のソフトハイフンを、述語と組版が別の語で読む」を消す。
- 「行分割」の節の境目の列挙の段落から、「ソフトハイフンの隣に境目のある入力では L8 と W1 だけを調べる」を消す。
- [ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md) のステータスの行に「（W1 の境目の項目と、境目のソフトハイフン）は ADR 0285」を足す。[ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md) のステータスの行に「（インラインの境目のソフトハイフン）は ADR 0285」を足す。

### 6. 出力の変化

語の途中にインラインの境目があり、その隣にソフトハイフンを書いた段落の行の分け方と、G07123 の notice が変わる。
notice が出なくなる入力は、組版がソフトハイフンを候補として使うようになる入力である。
実装のプルリクエストで、決定性のハッシュと見た目の回帰テストの変わったもの、notice の数の変わったものと、その理由を説明に書く。

## 実装しないこと

- **つないだ語のパターンの分綴**：[ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md) のとおり、パターンは箱ごとに当てる。この ADR が変えるのは、ソフトハイフンを含む要素を分綴しないことの範囲だけである。
- **リンクの語を切ること**：リンクの語は一つの箱のままとする（[ADR 0182](0182-external-links.md)）。
- **HTML と EPUB**：U+00AD をそのまま書き、閲覧環境が分ける（[ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md) のとおり）。
- **境目の両側の空白と両用の字**：[ADR 0284](0284-merge-spaces-on-both-sides-of-an-inline-boundary.md) と [ADR 0283](0283-decide-the-roles-of-characters-of-both-scripts-across-inline-boundaries.md) で決める。

## 不変条件

「境目で分けた段落」と「一つのテキスト」は、[ADR 0283](0283-decide-the-roles-of-characters-of-both-scripts-across-inline-boundaries.md) の不変条件の節のとおりとする。
「つないだ語」は「実装すること」の 1 のとおりとする。

- **H1 I3 と I4 は境目でも成り立つ**：ソフトハイフンの部品を含む境目の列挙のすべての入力で、[ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md) の I3（L9 を広げたもの）と I4 が成り立つ。
- **H2 一つのテキストと同じ候補**：分綴のパターンを持つ設定でも持たない設定でも、境目で分けた段落と一つのテキストとで、ソフトハイフンの罰点の列（段落の字の数えでの位置、幅、罰則）が等しい。
- **H3 一つのテキストと同じ notice**：境目で分けた段落と一つのテキストとで、ソフトハイフンの notice の種類（G07123、G07124）の列が等しい。
- **H4 境目の項目**（[ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md) の W1 を広げたもの）：隣り合う欧文の語の箱のあいだの項目は、空か、W1 の条件の明示のハイフンの罰点一つか、ソフトハイフンの罰点一つである。ソフトハイフンの罰点は、境目がつないだ語のソフトハイフンの候補であるとき、そのときに限る。
- **H5 列挙**：境目の列挙のすべての入力で、L1 から L13、I4、H4、W2 が成り立つ。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| ソフトハイフンの置き場所 | 前のテキストの終わり、後のテキストの頭、ソフトハイフンだけのテキスト、境目の両側（`a­` と `­b`） |
| 前後の字 | 字と字、字と約物（`a.­` と `b`）、明示のハイフンの直後（`a-­` と `b`）、字と数字 |
| 要素とパターン | パターンで分ける語（`hyphenation` と `­` と `x`）、要素の頭（`[strong: ­]hyphenation`） |
| 境目の数 | 一つ、二つ |
| 区間 | なし、`[lang en]`、`[lang ja]` |
| `explicit-hyphen-penalty` | 50、10000 |
| 改行しない字 | リンクの語の隣、改行しない範囲の中 |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
テストの名前には、H1 から H5 の番号を入れる。

- **H1**：「今の振る舞い」の表の四つの組で、I3 と I4 が成り立つこと。今は四つとも I3 で、四つめは I4 でも失敗する。
- **H2**：境界の入力の表の「ソフトハイフンの置き場所」と「前後の字」と「要素とパターン」の組で、ソフトハイフンの罰点の列が一つのテキストと等しいこと。今は `a­` と `a` で失敗する。
- **H3**：同じ組で、notice の種類の列が一つのテキストと等しいこと。今は `a­` と `a` で、境目で分けた段落だけに G07123 が出るので失敗する。リンクの語の隣のソフトハイフンで G07124 が出ること。
- **H4**：述語のテストとして、`a­` と `a` の項目からソフトハイフンの罰点を除いた出力を、H4 が違反として返すこと。ソフトハイフンの罰点の代わりに罰点 0 の `NoHyphen` を置いた出力も、違反として返すこと。
- **H5**：境目の列挙をプルリクエストの上限まで走らせる。除外の一覧（`shyAtBoundary` と W2 の除外）を消した状態で、今は I3 で失敗する。
- **golem-driver**：`[italic: hyphen]­ation` を狭い行に組み、`hyphen` の後で行末にハイフンを描いて分けうること、`hyphenation` をパターンの位置で分けないこと、notice が出ないこと。

## トレードオフ

- 語の部品の項目が、前後の語の部品のソフトハイフンで変わる。`[strong: hyphenation]` の分綴の位置は、後に `­x` が続くかどうかで変わる。[ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md) の箱の頭の連なりと同じ種類の依存であり、つないだ語を持ち回る範囲が広がる。
- パターンは箱ごとに当てるのに、ソフトハイフンで分綴を止める範囲はつないだ語の要素になる。分綴の規則の中で、箱を単位にするものとつないだ語を単位にするものが混ざる。
- notice の数が変わる。決定性は、同じ入力に同じ notice を出すことを求めるので、変わった notice は実装のプルリクエストで説明する。

## メンテナーが決めること

1. **どちらに合わせるか**：推奨は、組版を述語に合わせ、ソフトハイフンをつないだ語で読むことである。ソフトハイフンは書き手が分ける位置を指定する字であり、文字スタイルを付けたかどうかで指定が働いたり働かなかったりするのは、[ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md) が避けた振る舞いと同じである。TeX の `\-` も、フォントの境目にかかわらず任意の分割になる。
   - 退けた案は、述語を組版に合わせ、インラインの境目でソフトハイフンの語が切れると仕様に書くことである。変えるのはテストだけで済むが、`a­[strong: b]` で書き手の指定した位置で分けず、G07123 を出し続ける。
2. **分綴しない範囲**：推奨は、ソフトハイフンを含むつないだ語の要素の、すべての箱で分綴しないことである。[ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md) の「要素にソフトハイフンを一つでも書けば、その要素の分け方は書き手が決める」をそのまま保てる。
   - 退けた案は、候補だけをつないだ語で決め、分綴を止める範囲はソフトハイフンのある箱だけとすることである。`hyphenation` と `[strong: ­]` と `x` では、書き手の指定した位置とパターンの位置の両方で分けることになり、I4 が成り立たない。
3. **改行しない字の隣**：推奨は、候補の前か後の字が改行しない字なら候補にしないことである。リンクの語を分けない規則（[ADR 0182](0182-external-links.md)）と、改行しない範囲（[ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md)）を、境目でも保つ。
   - 退けた案は、ソフトハイフンが改行しない字の外にあれば候補にすることである。リンクの語の直後で分けて、リンクの語の後に行末のハイフンを描くことになる。

## 決めたことの記録

2026-11-10 に、tett23 が「メンテナーが決めること」のすべてを推奨のとおりに決めた。

1. 組版を述語に合わせ、ソフトハイフンをつないだ語で読む。
2. ソフトハイフンを含むつないだ語の要素は、すべての箱で分綴しない。
3. 候補の前か後の字が改行しない字なら、候補にしない。

採択にあたり、「今の振る舞い」と「文脈」のコードの記述が、`main` の `5fe4b57f`（[ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md) の実装のマージ）のコードと仕様書の「既知の不具合」に合うことを確かめた。

## 参考文献

- [ADR 0182](0182-external-links.md)、[ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md)、[ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md)、[ADR 0283](0283-decide-the-roles-of-characters-of-both-scripts-across-inline-boundaries.md)、[ADR 0284](0284-merge-spaces-on-both-sides-of-an-inline-boundary.md)
- [#827](https://github.com/tett23/golem/pull/827)（[ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md) の実装）の説明の「Points for the maintainer」の 3
- D. E. Knuth. The TeXbook（第 14 章、`\-` と `\discretionary`）
- InDesign の振る舞いは、Golem の開発の環境で動かせないので確かめていない。
