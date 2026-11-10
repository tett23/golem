# ADR 0283: 両用の字の役割と語の頭のアポストロフィを、インラインの境目をまたいで決める

ステータス: 採択→引用の印で探すのをやめることは [ADR 0298](0298-read-the-text-of-a-citation-mark-for-characters-of-both-scripts.md)

## 文脈

### [ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md) の実装が狭めた W2

[ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md) の W2 は、テキストの部品の並びを境目で分けた段落と、一つのテキストにした段落とで、分割の候補が等しいことを求めた。
実装（[#827](https://github.com/tett23/golem/pull/827)）は、W2 を二つの点で狭めた。
一つは、両側の字が欧文の語の箱の字である位置の候補だけを比べることである。
もう一つは、境目で分けると欧文の語に入る字が変わる入力を調べないことである（[`w2Same`](https://github.com/tett23/golem/blob/5fe4b57f2e2a11f09eaff9497b1956c8477d53a1/modules/golem-layout/test/JoinedWordEnum.hs#L210-L236)）。
狭めた理由は、仕様書の「既知の不具合」に「区間の外で、両用の字の役割がインラインごとに決まる」として載っている。
[ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md) は欧文の語の箱のあいだだけを決め、欧文の語に入る字の決め方は決めていない。

### 区間の外の両用の字は、自分のテキストの字だけを見る

区間の外の引用符、アポストロフィ、ハイフン類、ダッシュ（両用の字）は、どちらかの側の最も近い字（両用の字を飛ばした先）が欧文の字なら、欧文の語に入る（[ADR 0187](0187-inline-language-switch.md)、[golem-layout ADR 0008](../golem-layout/adr/0008-explicit-hyphens.md)）。
[ADR 0187](0187-inline-language-switch.md) も仕様書も、「最も近い字」をどの範囲で探すかを書いていない。
実装は、一つのテキスト（IR の `Text`）の字の中だけを探す（[`isJoiner` と `side`](https://github.com/tett23/golem/blob/5fe4b57f2e2a11f09eaff9497b1956c8477d53a1/modules/golem-layout/src/Golem/Layout/Japanese.hs#L948-L960)）。
テキストの端まで探して欧文の字がなければ、その字は和文の文字クラスの一字として組む。
`—` は分離禁止文字、`“` は始め括弧類、`’` と `”` は終わり括弧類になる。

### 語の頭のアポストロフィは、自分の箱の字だけを見る

[golem-layout ADR 0030](../golem-layout/adr/0030-apostrophes-at-word-starts-are-not-closing-brackets.md) は、欧文の語の箱の最初の字が U+2019 で、箱の中の次の字が字か数字なら、その字を禁則の判定で欧文の字とした。
実装は、箱の中の次の字だけを見る（[`startClass`](https://github.com/tett23/golem/blob/5fe4b57f2e2a11f09eaff9497b1956c8477d53a1/modules/golem-layout/src/Golem/Layout/Japanese.hs#L1860-L1866)）。
`’` だけの箱の後に、境目を挟んで `tis` の箱が続いても、`’` は終わり括弧類のままである。

### 今の振る舞い

2026-11-10 に origin/main（`5fe4b57f`）の golem-layout のテストを `cabal repl` で読み込み、境目の列挙の環境（[`envOf`](https://github.com/tett23/golem/blob/5fe4b57f2e2a11f09eaff9497b1956c8477d53a1/modules/golem-layout/test/JoinedWordEnum.hs#L69-L74)、禁則は strict、分綴のパターンあり）で組んだ。
「境目」は、その位置から後の部品を `[strong: …]` に入れたことを表す。
`strong` は字の見た目を変えないので、二つの段落の違いはインラインの境目だけである。

| 部品 | 区間 | 境目で分けた段落の項目 | 一つのテキストの項目 |
| --- | --- | --- | --- |
| `a`、境目、`—`、境目、`b` | なし | `a`、和欧間の空き、和文の箱 `—`、和欧間の空き、`b` | 欧文の箱 `a—`、明示のハイフンの罰点 50、`b` |
| `aaaa`、境目、`—`、境目、`b`（行の幅 2 em） | なし | 一行目 `aaaa`、二行目 `—b` | 一行目 `aaaa—`、二行目 `b` |
| `a`、境目、`“`、境目、`b` | なし | `a`、二分の空き、和文の箱 `“`、`b` | 欧文の箱 `a“b` |
| `x “`、境目、`Ham`、境目、`” y` | なし | `x`、語間の空白、二分の空き、和文の箱 `“`、`Ham`、和文の箱 `”`、語間の空白、`y` | `x`、語間の空白、欧文の箱 `“Ham”`、語間の空白、`y` |
| `aaa ’`、境目、`tis`（行の幅 2 em） | なし | 和文の箱 `’` の後に二分の空き。一行目 `aaa’`、二行目 `tis` | 一行目 `aaa`、二行目 `’tis` |
| `aaa ’`、境目、`tis`（行の幅 2 em） | `[lang en]` | 空白の前に罰点 10000。`aaa’tis` の一行で、行の幅を超える | 一行目 `aaa`、二行目 `’tis` |
| `x ’`、境目、`90` | なし | 空白の前に罰点 10000、和文の箱 `’`、二分の空き | `x`、語間の空白、欧文の箱 `’90` |

区間の外では、境目の隣の両用の字が和文の字になり、空きが入る。
`x “[strong: Ham]” y` のように、文字スタイルを付けた語を引用符で囲むと、`“` の前に語間の空白と二分の空きが並ぶ。
`[lang en]` の中では両用の字は欧文の語に入るが、語の頭のアポストロフィが後の箱を見ないので、空白で分けられない。
どちらの段落も、[ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md) の L1 から L13 は破らない。
`—` と `’` が和文の字になると、L8 の「欧文の語」から外れるからである。

本の原稿にも、この形がある。
`pd-merry-wives`（本の言語は英語で、区間は書いていない）の原稿には `F4. ’[italic: Bless]` があり、`’` は空白の後で自分のテキストの終わりに来る。
今の実装では、この `’` は終わり括弧類の和文の箱になる。
PDF の見た目は、この ADR の調査では確かめていない。

### 拠るもの

- JLReq は、和文の中の欧文の語を一つのまとまりとして扱い、文字スタイルの境目には触れていない。
- InDesign の振る舞いは、Golem の開発の環境で動かせないので確かめていない。
- TeX には和文と欧文の両用の字の区別がない。[ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md) が `\showlists` で確かめたとおり、`aaa-{\bf bbb}` の `-` の後には、一つのテキストと同じく `\discretionary` が置かれ、フォントの境目で字の扱いは変わらない。
- 仕様書の「欧文の単語の箱は、両端の引用符やダッシュを含めて欧文（`western`）として扱う」と、[ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md) の「文字スタイルを付けたかどうかで行の分け方が変わらない」は、どちらも境目で字の扱いを変えないことを求めている。

## 実装すること

### 1. 区間の外の両用の字の最も近い字

区間の外の両用の字の「最も近い字」を、段落の**字の並び**で探す。
字の並びは、段落のインラインを順にたどり、テキスト（IR の `Text`）の字をつないだものとする。
文字スタイル、色、リンク、言語の区間、圏点、解決した参照（[ADR 0215](0215-ref-number-and-ref-title-as-reference.md)）の境目は、字の並びを切らない。
項目を作らないインライン（索引の印などのアンカーと、ソフトハイフン）は飛ばす。

ほかのインライン（ルビ、縦中横、番号、本文の中のコード、注の印、引用の印、強制改行、`[aki]`）に当たったら、そこで探すのをやめ、その側に欧文の字はないものとする。
空白で探すのをやめることと、段落の端で欧文の字がないものとすることは、今のとおりである。
見つけた字が欧文の字かは、その字のインラインの見た目（区間の言語を含む）で決める。
`a` と `[lang ja: —]` の `—` は区間の中の字なので、この規則に当たらない。

実装は、[`piecesOf`](https://github.com/tett23/golem/blob/5fe4b57f2e2a11f09eaff9497b1956c8477d53a1/modules/golem-layout/src/Golem/Layout/Japanese.hs#L683-L685) がテキストの部品を作るときに、テキストの前と後で最も近い両用でない字（探すのをやめたときは、そのこと）を渡し、`side` がテキストの端を越えたらそれを見る形を想定する。
語の箱の作り方、空き、禁則、分割の候補の規則は変えない。
欧文の語に入った両用の字は、今のテキストの中の語と同じく欧文の語の箱になり、[ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md) の隣り合う欧文の語の箱の規則に当たる。

### 2. 語の頭のアポストロフィの次の字

[golem-layout ADR 0030](../golem-layout/adr/0030-apostrophes-at-word-starts-are-not-closing-brackets.md) の「箱の中の次の字」を、「つないだ語の中の次の字」に改める。
つないだ語は、[ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md) の「実装すること」の 1 のとおり、あいだにほかの項目を挟まずに続く欧文の語の箱の字をつないだものとする。
箱が U+2019 と結合文字だけなら、次の字は、後に隣り合う欧文の語の箱の最初の字である。
後に隣り合う欧文の語の箱がなければ、今のとおり次の字はない。

この規則は、空白をまたぐ禁則の判定（`prohibitedAcross`）と、隣り合う二つの箱のあいだの判定（`between`）の両方に当たる。
`charClass`、`charClassIn`、`dualCharacters` の表は変えない。

### 3. 列挙

- [ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md) の境目の列挙（W3）で、W2 の二つの狭め方をやめる。境目で分けた段落と一つのテキストとで、欧文の語に入る字の列が等しいこと（E1）を確かめ、すべての位置の分割の候補を比べる（E2）。
- 部品は変えない。今の部品で、`’` の後に境目を挟んで字の続く並び（`’` と `a`、`’` と `lime-tree`）が部品 2 個で出て、空白の後のもの（空白、`’`、`a`）が部品 3 個で出る。E3 は、毎晩の段の部品 3 個までで列挙に入る。

### 4. 文書

- [docs/specifications.md](../specifications.md) の「両用の文字」の節の区間の外の項目と、「行分割」の節の U+2010 と U+2013 の段落に、最も近い字を段落の字の並びで探すことと、探すのをやめるインラインを書く。
- 同じく「行分割」の節の語の頭のアポストロフィの段落の「次の字」を、つないだ語の中の次の字に改める。
- 仕様書の「既知の不具合」から、「区間の外で、両用の字の役割がインラインごとに決まる」を消す。
- 「行分割」の節の境目の列挙の段落から、W2 の二つの狭め方の文を消す。
- [ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md) のステータスの行に「（W2 の比べる範囲）は ADR 0283」を足す。[golem-layout ADR 0030](../golem-layout/adr/0030-apostrophes-at-word-starts-are-not-closing-brackets.md) のステータスの行に「（次の字の範囲）は docs/adr/0283」を足す。

### 5. 出力の変化

区間の外で、両用の字だけのテキストか、テキストの端の両用の字が、境目の向こうの欧文の字と並ぶ段落の空きと行の分け方が変わる。
`“[italic: …]”` や `’[italic: …]` の形がこれに当たる。
両用の字の書体は変えない（「実装しないこと」）。
実装のプルリクエストで、決定性のハッシュと見た目の回帰テストの変わったものと、その理由を説明に書く。

## 実装しないこと

- **両用の字の書体**：区間の外の両用の字の書体は、golem-typeset が `charClass` で選ぶ（[golem-layout ADR 0030](../golem-layout/adr/0030-apostrophes-at-word-starts-are-not-closing-brackets.md) の「実装しないこと」）。語の最初の字が両用の字の語の書体は、[ADR 0222](0222-line-breaking-points-the-invariants-did-not-decide.md) の「メンテナーが決めること」の 6 で別の ADR にすると決めた点であり、ここでは変えない。
- **本の言語で区間の外を決めること**：[ADR 0187](0187-inline-language-switch.md) の決めたとおり、本の言語は見ない。
- **ほかのインラインの中の字**：ルビの親文字、縦中横、番号、コード、注と引用の印の字は、字の並びに入れない。ルビの親文字は和文の字が多く、コードと印の字は本文の語ではないので、境目の向こうの両用の字の役割を決める材料にしない。
- **空白とソフトハイフンの隣の境目**：[ADR 0284](0284-merge-spaces-on-both-sides-of-an-inline-boundary.md) と [ADR 0285](0285-read-soft-hyphens-at-inline-boundaries-in-the-joined-word.md) で決める。
- **HTML と EPUB**：閲覧環境が字を組むので、変えない。

## 不変条件

「字の並び」は「実装すること」の 1 のとおり、「つないだ語」は [ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md) のとおりとする。
「境目で分けた段落」は、テキストの部品の並びを、字の見た目を変えない文字スタイルの境目で分けた段落とする。
「一つのテキスト」は、同じ並びを一つのテキストにした段落とする。

- **E1 同じ字が欧文の語に入る**：どの区間の設定でも、境目で分けた段落と一つのテキストとで、段落のそれぞれの字が欧文の語の箱（`bcExpandable` の箱）に入るかの列が等しい。
- **E2 同じ分割の候補**：分綴のパターンを持たない設定では、境目の隣に空白とソフトハイフンがない入力で、境目で分けた段落と一つのテキストとで、段落のすべての位置の分割の候補（[ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md) の W2 の述語と同じもの）が、位置、罰点、種類とも等しい。
- **E3 語の頭のアポストロフィ**：欧文の語の箱の最初の字が U+2019 で、つないだ語の中の次の字（結合文字を除く）が字か数字なら、その箱の前の語間の空白の前に、行頭禁則による罰点 10000 はない。次の字がないか、字でも数字でもなければ、`’` は今のとおり終わり括弧類として判定する。
- **E4 字の並びを切るもの**：両用の字の役割は、字の並びの外のインライン（「実装すること」の 1 の一覧）と空白の向こうの字によって変わらない。あいだにそれらのインラインを挟む入力で、向こうの字を和文の字に変えても欧文の字に変えても、その両用の字が欧文の語に入るかは変わらない。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 両用の字の置き場所 | テキストの頭、テキストの終わり、両用の字だけのテキスト |
| 境目の向こうの最も近い字 | 欧文の字、和文の字、空白、段落の端、ルビ、コード、注の印、引用の印 |
| 飛ばす両用の字の数 | 0、1（`a`、`“`、`—`、`b` の四つの箱）、境目を二つまたぐもの |
| 向こうの字の区間 | なし、`[lang en]`、`[lang ja]` |
| 両用の字の区間 | なし、`[lang en]`（1 の規則に当たらない）、`[lang ja]` |
| アポストロフィの次の字 | 同じ箱の字、後の箱の字（`’` と `tis`）、後の箱の数字（`’` と `90`）、後の箱の約物（`’` と `.`）、後に箱がない |
| あいだのアンカー | なし、索引の印 |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
テストの名前には、E1 から E4 の番号を入れる。

- **E1**：「今の振る舞い」の表の組と、境界の入力の表の「両用の字の置き場所」と「境目の向こうの最も近い字」の組で、欧文の語に入る字の列が一つのテキストと等しいこと。今は `a`、`—`、`b` の三つの箱と、`x “`、`Ham`、`” y` で失敗する。
- **E2**：境目の列挙（W3）で、W2 の二つの狭め方をやめた述語が成り立つこと。今は `a`、`—`、`b` と、`’` と `tis` の組で失敗する。
- **E3**：`aaa ’` と `[strong: tis]` を、区間なしと `[lang en]` で行の幅 2 em に組み、`aaa` と `’tis` の二行になること。`aaa ’` と `[strong: 90]` も同じであること。`aaa ’` と `[strong: .]` は、今のとおり空白で分けないこと。今は区間なしでも `[lang en]` でも失敗する。
- **E4**：`a` と `[strong: —]` のあいだに、ルビ、コード、注の印、引用の印、空白を挟んだ入力で、それらの向こうの字を `b` と `あ` に替えても、`—` の箱の種類が変わらないこと。索引の印を挟んだ入力では、`b` のとき欧文の語に入ること。
- **述語のテスト**：E1 と E2 の述語が、今の実装の `a`、`—`、`b` の項目を違反として返すこと。
- **回帰**：`pd-merry-wives` の `F4. ’[italic: Bless]` の段落で、`’` が欧文の語の箱になること（golem-driver のテスト）。

## トレードオフ

- テキストの部品を作るのに、前と後のテキストの字が要る。テキストの部品は、自分のテキストだけでは決まらなくなる。[ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md) の箱の頭の連なりと同じ種類の依存である。
- 両用の字だけのテキストの役割が、隣のインラインの中身で変わる。`[strong: “]` の組み方は、前後に何を書いたかで欧文の引用符にも和文の括弧にもなる。一つのテキストの中では今もそうなので、境目の有無で違わなくなる代わりに、インラインの単位では決まらなくなる。
- ルビやコードの向こうの字を見ないので、`[code: x]—b` の `—` は `b` で欧文の語に入るが、`a—[code: x]` の `—` は `a` で決まる。字の並びの外のインラインの隣の両用の字は、片側の字だけで決まる。
- 書体は変えないので、欧文の語に入った区間の外の `“` も、今のテキストの中の `“` と同じく `charClass` で選んだ書体で描く。和文の書体の本では、引用符は和文の書体のままである。

## メンテナーが決めること

1. **最も近い字を探す範囲**：推奨は、段落の字の並び（文字スタイル、色、リンク、言語の区間、圏点、解決した参照の境目をまたぎ、ほかのインラインで止まる）とすることである。仕様書の「欧文の単語の箱は、両端の引用符やダッシュを含めて欧文として扱う」と、[ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md) の「文字スタイルを付けたかどうかで行の分け方が変わらない」に合う。
   - 退けた案の一つは、今のとおりテキストの中だけを探し、仕様書に「最も近い字は同じテキストの中で探す」と書くことである。`x “[strong: Ham]” y` の引用符の前に二分の空きが入る組み方を、仕様として残すことになる。
   - 二つめは、ルビ、コード、印も字の並びに入れることである。コードの字や印の `[` で、本文の両用の字の役割が決まるようになる。
2. **語の頭のアポストロフィの次の字**：推奨は、つないだ語の中の次の字とすることである。1 と同じく、`[lang en]` の中でも境目で禁則が変わらない。
   - 退けた案は、箱の中の次の字のままとすることである。`’[italic: Tis]` の形で、空白の前で分けられないままになる。

## 決めたことの記録

2026-11-10 に、tett23 が「メンテナーが決めること」のすべてを推奨のとおりに決めた。

1. 区間の外の両用の字の「最も近い字」は、段落の字の並び（文字スタイル、色、リンク、言語の区間、圏点、解決した参照の境目をまたぎ、ルビ、縦中横、番号、本文の中のコード、注の印、引用の印、強制改行、`[aki]` で止まる）で探す。
2. 語の頭のアポストロフィの次の字は、つないだ語の中の次の字とする。

採択にあたり、「今の振る舞い」と「文脈」のコードの記述が、`main` の `5fe4b57f`（[ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md) の実装のマージ）のコードと仕様書の「既知の不具合」に合うことを確かめた。

## 参考文献

- [ADR 0187](0187-inline-language-switch.md)、[ADR 0208](0208-widen-lightweight-formal-methods.md)、[ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md)、[ADR 0215](0215-ref-number-and-ref-title-as-reference.md)、[ADR 0222](0222-line-breaking-points-the-invariants-did-not-decide.md)、[ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md)、[ADR 0284](0284-merge-spaces-on-both-sides-of-an-inline-boundary.md)、[ADR 0285](0285-read-soft-hyphens-at-inline-boundaries-in-the-joined-word.md)
- [golem-layout ADR 0008](../golem-layout/adr/0008-explicit-hyphens.md)、[golem-layout ADR 0030](../golem-layout/adr/0030-apostrophes-at-word-starts-are-not-closing-brackets.md)
- [#827](https://github.com/tett23/golem/pull/827)（[ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md) の実装）の説明の「Points for the maintainer」の 1
- W3C. Requirements for Japanese Text Layout (JLReq). https://www.w3.org/TR/jlreq/（英語の題が「Handling of Western Text in Japanese Text using Proportional Western Fonts」の節）
- InDesign の振る舞いは、Golem の開発の環境で動かせないので確かめていない。
