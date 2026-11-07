# ADR 0206: 改ページの不変条件の述語が判定しなかった仕様の点を決める

ステータス: 採択（未実装）

## 文脈

[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) は、仕様書の「改ページ」の節の規則を不変条件 I1 から I8 として述語に書き、小さな入力のすべてで確かめると決めた。
仕様書の文から一つの述語に決まらないところは、述語を書かずに、実装のプルリクエストに挙げることにした（[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の「実装すること」の 3）。
実装（[#641](https://github.com/tett23/golem/pull/641)）は、次の五つを挙げ、述語はどれも判定しない（[`PaginateInvariants.hs`](https://github.com/tett23/golem/blob/499f6d95fd32c1188555a81c8f4b60c0cc612d83/modules/golem-layout/test/PaginateInvariants.hs#L1-L22)）。

1. **段より高い図版（I2）**：[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) は C + 1 行の図版を列挙すると決めた（「実装すること」の 2 と、境界の入力の表）。仕様書の「図版」の節は、図版を縮めて空の段に必ず収める（[golem-driver ADR 0034](../golem-driver/adr/0034-fit-figures-to-column.md)）。[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の中で食い違っている。
2. **見出しだけを置いた段の後の孤立行と寡婦行（I4、I5）**：仕様書は、段の先頭から見出しだけを置いた段では、見出しの後の行を「空の段と同じく一行は置き」と定める（[golem-layout ADR 0019](../golem-layout/adr/0019-keep-with-next-counts-footnotes.md)）。[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の I4 と I5 の例外は、空の段だけを挙げる。見出しだけの段で、孤立行と寡婦行の規則を空の段と同じく緩めるかが、決まっていない。
3. **改丁の見出しの前の送った図版（I8）**：仕様書は「送った図版と続きの脚注は、改ページの後の新しいページに置き」と定め、[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の I8 は、改丁の見出しを「奇数ページの最初の段の最初」に置くと定める。改ページの後の新しいページが奇数ページなら、送った図版と改丁の見出しのどちらがページの最初かが、決まっていない。
4. **改丁の見出しが続く見出し（I6 と I8）**：I6 は、見出しを続く見出しのすべてと同じ段に置くと定め、I8 は、改丁の見出しをページの最初に置くと定める。見出しの直後が改丁の見出しなら、二つを同時に満たすのは、前の見出しが段の最初の要素であるときだけである。
5. **見出しが段落のいくつの行と同じ段にあるか（I6）**：[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の I6 は「最初の 2 行」と書く。その後に入った [golem-layout ADR 0021](../golem-layout/adr/0021-keep-with-next-counts-widow-and-orphan.md) で、仕様書は「3 行の段落では全体」に改まった。述語は [ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) のとおり 2 行を調べる。

改ページの不変条件のテストは、仕様書の「既知の不具合」の三つの違反も見つけた。
その原因と直し方は、[golem-layout ADR 0023](../golem-layout/adr/0023-keep-with-next-after-figures-sent-on.md)（I6 と I7）と [golem-layout ADR 0024](../golem-layout/adr/0024-recto-start-places-figures-sent-on-first.md)（I8）で決める。
3 の決め方は、[golem-layout ADR 0024](../golem-layout/adr/0024-recto-start-places-figures-sent-on-first.md) の直し方を決める。

この ADR は、五つの点をそれぞれ決め、[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の述語と既知の不具合の一覧がどう変わるかを決める。
[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) はコミット済みなので、書き換えない。
[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の I2、I4、I5、I6、I8 の読み方は、この ADR が改める。

### Alloy のモデルで確かめたこと

`docs/golem-layout/models/pagination.als` に、2 から 5 の決め方の候補を述語として足した写しを作り、[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の README と同じ手順（スコープ 2 から 5、整数 5 ビット、`-n`）で走らせた（2026-11-08、Alloy 6.2.0）。
写しはコミットしていない。
足した述語は、改丁の見出し（`Recto`、`Heading` の一種）、見出しだけを置いた段の後の行（`lineAfterHeadings`、仕様書の「一行は置き」）、見出しだけの段を空の段と同じに扱う孤立行と寡婦行（`orphanH`、`widowH`）、[golem-layout ADR 0021](../golem-layout/adr/0021-keep-with-next-counts-widow-and-orphan.md) の量の I6（`keepHeading21`）、改丁の見出しで見出しの並びを切る I6（`keepHeadingR`）、段の境目での I8（`recto`）である。

| コマンド | 調べること | 最も小さい例のスコープ |
| --- | --- | --- |
| `strictAfterHeadings` | 見出しの後の行を一行は置き、孤立行と寡婦行の規則を緩めないと、すべてを満たす配置がない入力があるか | 4 |
| `relaxedAfterHeadings` | 見出しだけの段を空の段と同じに扱うと、どの入力にも配置があるか（ないものを探す） | なし |
| `rectoKept` | 改丁の見出しを見出しの並びに含めた I6 と、段の境目での I8 を合わせて、配置がない入力があるか | なし |
| `rectoEnds` | 改丁の見出しで並びを切った I6 と、I8 を合わせて、配置がない入力があるか | なし |
| `keep21` | [golem-layout ADR 0021](../golem-layout/adr/0021-keep-with-next-counts-widow-and-orphan.md) の量の I6 で、貪欲法のほかのすべての規則を満たす配置がない入力があるか | なし |
| `decidedSome` | 決めた規則のすべてを満たす配置が、改丁の見出しのある入力にあるか（モデルが全否定でないこと） | 2 |

- `strictAfterHeadings` の最も小さい例は、段の行の数が 3 の空の段に、見出しと 3 行の段落が来るものである。見出しは送れず、見出しの後に 1 行を置けば孤立行、2 行を置けば寡婦行になる。2 の推奨の根拠である。
- `rectoKept` は、配置のない入力を出さなかった。モデルは一つの段と次の段の境目だけを扱い、前の見出しを改丁の見出しとともに次の段に送れば、境目の規則はすべて満たせるからである。前の見出しを送った先の段では、その見出しが段の最初になり、I6 の例外に当たる。4 の二つは、論理の上では両立し、両立させると見出しだけの段ができる。4 は矛盾の解き方ではなく、どちらの出力が望ましいかの選択である。
- 3 は、ページの奇数と偶数と送った図版の置き場所に関わるので、このモデルでは書けない。改ページの不変条件のテストと、[golem-layout ADR 0024](../golem-layout/adr/0024-recto-start-places-figures-sent-on-first.md) の試した直し方で確かめた。

### 決めた後の述語で確かめたこと

[golem-layout ADR 0023](../golem-layout/adr/0023-keep-with-next-after-figures-sent-on.md) と 0024 の直し方と、この ADR の推奨のとおりに述語と列挙を変えたもの（作業用の変更で、コミットしていない）で、改ページの不変条件のテストを要素 5 個まで走らせ、違反は一つもなかった（2026-11-08）。
既知の不具合の一覧は空にした。
golem-layout のテストのうち、手で選んだ `PaginateSpec` の例は、どれも変わらなかった。
4 の `nextNeed` の変更は、この確かめの後に足し、要素 4 個まで走らせて、違反は一つもなかった。

この ADR だけを入れた形（コミット 499f6d95 の実装に 4 の `nextNeed` の変更を足し、1、3、4、5 のとおりに述語と列挙を変えたもの）でも、要素 3 個と 4 個で、既知の不具合の一覧で除くほかの違反はなかった。
除く入力の数は、次のとおりに変わった。

| 項目 | 要素 3 個（今 → 後） | 要素 4 個（今 → 後） |
| --- | --- | --- |
| 送った図版の後の改丁の見出しが、偶数ページに置かれる | 420 → 582 | 24,364 → 29,752 |
| 送った図版の後の見出しの注が、次のページに送られる | 0 → 0 | 757 → 344 |
| 図版を追い越した見出しが、本文から離れる | 0 → 0 | 3,654 → 3,156 |

要素 5 個の数は、実装のときに数える。

## 実装すること

### 1. 段より高い図版を列挙しない

- `paginateWithin` に渡す図版は、格子の行の数が段の行の数（C）以下であることを、改ページの入力の前提とする。図版を縮める golem-driver が、この前提を作る（仕様書の「図版」の節）。
- `PaginateEnum` の `elementsFor` は、図版を 1 行から C 行まで列挙する（[`PaginateEnum.hs`](https://github.com/tett23/golem/blob/499f6d95fd32c1188555a81c8f4b60c0cc612d83/modules/golem-layout/test/PaginateEnum.hs#L54-L61)）。
- I2 の述語から、段より高い図版を除く例外（`tooTall`）を消す（[`PaginateInvariants.hs`](https://github.com/tett23/golem/blob/499f6d95fd32c1188555a81c8f4b60c0cc612d83/modules/golem-layout/test/PaginateInvariants.hs#L185-L196)）。
- `Golem.Layout.Paginate` の `paginateWithin` の Haddock に、この前提を書く。前提を破る入力の振る舞い（空の段に置く）は変えず、定めない。

### 2. 見出しだけを置いた段は、孤立行と寡婦行の規則で空の段と同じに扱う

段の先頭から見出しだけを置いた段では、孤立行と寡婦行の規則で一行も置けなくなる場合は、空の段と同じく、入るだけの行を置く。
今の実装は、すでにこのとおりである（[`Paginate.hs` の `placeLines`](https://github.com/tett23/golem/blob/499f6d95fd32c1188555a81c8f4b60c0cc612d83/modules/golem-layout/src/Golem/Layout/Paginate.hs#L339)）。

- I4 と I5 の例外に、段の先頭から見出しだけを置いた段を足す。述語の式は今のとおりで（[`PaginateInvariants.hs`](https://github.com/tett23/golem/blob/499f6d95fd32c1188555a81c8f4b60c0cc612d83/modules/golem-layout/test/PaginateInvariants.hs#L248-L285)）、「判定しない」のコメントを、規則として許す旨に改める。
- 仕様書の「段の先頭から見出しだけを置いた段では、見出しの後の行を空の段と同じく一行は置き」を、「段の先頭から見出しだけを置いた段では、空の段と同じく、孤立行と寡婦行の規則で一行も置けなくなる場合は、入るだけの行を置き」に改める。

### 3. 改丁の見出しは、送った図版の後に置かない

改丁の見出しと `@page-break recto`、`@page-break verso` では、送った図版と続きの脚注をすべて置いてから、奇数（偶数）ページを始める。
改丁の見出しは、奇数ページの最初の段の、最初の要素である。

- I8 の述語を、改丁の見出しの前に、その段のどの要素（送った図版を含む）もないことを求める形に強める（[`PaginateInvariants.hs`](https://github.com/tett23/golem/blob/499f6d95fd32c1188555a81c8f4b60c0cc612d83/modules/golem-layout/test/PaginateInvariants.hs#L342-L350)）。
- 実装と仕様書の文は、[golem-layout ADR 0024](../golem-layout/adr/0024-recto-start-places-figures-sent-on-first.md) で変える。仕様書は今の振る舞いを書くので、振る舞いが変わるときに文を足す。

### 4. 見出しの並びは、改丁の見出しの前で切れる

見出しの直後が改丁の見出しなら、前の見出しは、改丁の見出しもその後の段落も、後に続くものとして数えない。
`@page-break` の前の見出しが、後に続くものを数えないのと同じである（[`Decide.hs` の `nextNeed`](https://github.com/tett23/golem/blob/499f6d95fd32c1188555a81c8f4b60c0cc612d83/modules/golem-layout/src/Golem/Layout/Paginate/Decide.hs#L69-L75)）。

- `nextNeed` に、改丁の見出し（`FHeading` の `fhRecto` と、罫線を持つ改丁の見出し。`startsRecto` が真のもの）で何も数えない枝を、見出しの枝の前に足す。`nextNeed` を使うほかの先読み（定義リストの用語と、`@no-page-break` の前の段落の `keptNeed`）も、改丁の見出しを数えなくなる。改丁の見出しは次の奇数ページから始まるので、どれも同じ段に置けないからである。
- I6 の述語で、見出しの並びを改丁の見出しの前で切る。改丁の見出しの前の見出しは、その前までの見出しと同じ段にあればよい（[`PaginateInvariants.hs`](https://github.com/tett23/golem/blob/499f6d95fd32c1188555a81c8f4b60c0cc612d83/modules/golem-layout/test/PaginateInvariants.hs#L291-L319)）。今の「判定しない」（`Nothing` を返す枝）を消す。
- 仕様書の「見出しは、続く見出しのすべてと」の文の後に、「改丁の見出しは、前の見出しの続く見出しに数えない。改丁の見出しの前の見出しは、`@page-break` の前の見出しと同じく、後に続くものを数えない」を足す。

### 5. I6 は、[golem-layout ADR 0021](../golem-layout/adr/0021-keep-with-next-counts-widow-and-orphan.md) の量を調べる

I6 の述語が調べる段落の行を、[golem-layout ADR 0021](../golem-layout/adr/0021-keep-with-next-counts-widow-and-orphan.md) の量（3 行以下の段落は全体、4 行以上は最初の 2 行）にする。
述語は実装の `Decide` を読まないので、表の値を述語の中に書く。

### 6. [ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の不変条件の読み方

この ADR の後の I2、I4、I5、I6、I8 は、次のとおりに読む。
ほかの不変条件と、[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の残りは変えない。

| 不変条件 | [ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の文 | この ADR の後 |
| --- | --- | --- |
| I2 | 段より高い図版は列挙の中にあり、述語は判定しない | 図版は C 行以下だけを列挙し、どの段も判定する |
| I4 | 空の段の先頭では除く | 空の段と、段の先頭から見出しだけを置いた段の、見出しの後では除く |
| I5 | 前の段が空の段から始まり、その段落の行だけを持つときは除く | 前の段が空の段から始まるか、段の先頭から見出しだけを置き、その後にその段落の行だけを持つときは除く |
| I6 | 続く見出しのすべてと、その後の段落の最初の 2 行 | 続く見出しのうち改丁の見出しの前までと、その後の段落の [golem-layout ADR 0021](../golem-layout/adr/0021-keep-with-next-counts-widow-and-orphan.md) の量。改丁の見出しが続くなら、段落は数えない |
| I8 | 奇数ページの最初の段の最初（述語は、前に送った図版があっても判定しない） | 奇数ページの最初の段の、最初の要素。送った図版も前に置かない |

この ADR を採択したら、[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) のステータスの行を「採択→（不変条件の I2、I4、I5、I6、I8 の読み方）は ADR 0206」に改める。

### 7. 既知の不具合の一覧と、固定した数

テストの中の既知の不具合の一覧（[`PaginateInvariantsSpec.hs`](https://github.com/tett23/golem/blob/499f6d95fd32c1188555a81c8f4b60c0cc612d83/modules/golem-layout/test/PaginateInvariantsSpec.hs#L235-L257)）は、次のとおりに変わる。

- 1 で列挙が変わる（C = 3 の要素が 17 から 16 になる）ので、各項目の固定した数（`kbCounts`）を、要素 0 から 5 個まで数え直す。列挙の数を確かめるテスト（「in columns of 3 grid lines there are 17 elements」など）も改める。
- 3 で I8 が強まり、4 と 5 で I6 が変わるので、「送った図版の後の改丁の見出しが、偶数ページに置かれる」と「図版を追い越した見出しが、本文から離れる」の項目が除く入力の数も変わる。除く条件（入力の形）は変えない。
- 述語のテストのうち、「I2: a figure taller than the column is not judged」「I8: after the figures sent on is not judged」「I6: a heading before a heading at a recto is not judged」を、決めた規則のテストに改める（「テスト設計」）。
- 一覧の三つの項目は、[golem-layout ADR 0023](../golem-layout/adr/0023-keep-with-next-after-figures-sent-on.md) と 0024 が消す。この ADR は項目を消さない。

### 8. 実装の順

この ADR を先に実装し、[golem-layout ADR 0023](../golem-layout/adr/0023-keep-with-next-after-figures-sent-on.md) と 0024 はその後に実装する。
[golem-layout ADR 0024](../golem-layout/adr/0024-recto-start-places-figures-sent-on-first.md) のテスト設計は、3 で強めた I8 を前提にする。
[golem-layout ADR 0023](../golem-layout/adr/0023-keep-with-next-after-figures-sent-on.md) と 0024 を先に入れると、7 で数え直す数が二度変わる。

### 9. 文書

- 仕様書の「改ページ」の節の、述語が判定しない場合を挙げた文（「段より高い図版を置いた段のあふれ、……がそれにあたる」）を消し、「判定しない場合はない」とする。
- `docs/golem-layout/models/pagination.als` に、「Alloy のモデルで確かめたこと」の述語とコマンドを足し、[docs/golem-layout/models/README.md](../golem-layout/models/README.md) の結果の表と例を書き直す（docs/roadmap.md の「手で確かめる項目」）。

### 10. 出力の変化

4 は、改丁の見出しの直前に見出しを置いた本で、改ページの位置を変えうる。
前の見出しが、改丁の見出しの行と後の段落の行を数えなくなり、今の段に残ることが増える。
1、2、3、5 は、この ADR では実装の振る舞いを変えない（3 の振る舞いは [golem-layout ADR 0024](../golem-layout/adr/0024-recto-start-places-figures-sent-on-first.md) で変わる）。

この ADR を書く段で、コミット 499f6d95 に [golem-layout ADR 0023](../golem-layout/adr/0023-keep-with-next-after-figures-sent-on.md) と 0024 と 4 の変更を入れた `golem` で、golem-driver の fixture の `sample`、`figures`、`complex-vertical`、`complex-horizontal`、`kanikosen`、`tempest` と、使い手のマニュアルの PDF を組み、コミット 499f6d95 の `golem` の PDF とバイト列が一致した（2026-11-08）。
golem-driver のテストも、すべて通った。
ほかの本は比べていないので、golden、見た目の回帰テストの参照、`scripts/determinism/hashes.txt` が実装のときに変われば、変わったページを目で確かめてから改める。

## 実装しないこと

- **`@page-lines` で減らした段と図版**：段の行の数を減らした段では、C 行の図版が段より高くなりうる。改ページの不変条件のテストは `FAdjustLines` を列挙しないので、この ADR では決めない。
- **改丁の見出しが続く見出しを、notice で知らせること**：見出しの直後に改丁の見出しを書いた原稿は、前の見出しが本文を持たない。notice にするかは、原稿の lint の範囲として別に決める。
- **改丁でない見出しの前の送った図版**：今のとおり、送った図版を次の段の先頭に置き、見出しはその後に置く（[golem-layout ADR 0023](../golem-layout/adr/0023-keep-with-next-after-figures-sent-on.md)）。
- **列挙の範囲を広げること**：`BreakRecto`、`BreakVerso`、定義リストの用語などの列挙は、[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の「実装しないこと」のとおり、範囲を広げる ADR で決める。

## 不変条件

[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の I1 から I8 を、6 の表のとおりに読む。
この ADR が足す不変条件は、次の二つである。

- **D1**：改丁の見出しの直前の見出しが段の最初の要素でないとき、その見出しの段とページは、改丁の見出しがないときと同じである（4。`nextNeed` が改丁の見出しの後を数えない）。
- **D2**：段の先頭から見出しだけを置いた段の後の段落は、その段に少なくとも 1 行を置く。ただし、その 1 行と、その行の注の本文の 1 行と、その段で最初の注なら区切りの領域が入らないときは除く（2。[golem-layout ADR 0019](../golem-layout/adr/0019-keep-with-next-counts-footnotes.md) の `roomForLine`）。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 図版の行の数 | 1、C − 1、C |
| 見出しだけの段の見出しの数 | 1、2 |
| 見出しだけの段の後の段落の行の数 | 1、2、3、C、C + 1 |
| 改丁の見出しの前の見出し | 0、1、2 |
| 改丁の見出しの前の送った図版 | 0、1、2 |
| 段落の行の数（I6） | 1、2、3、4 |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
テストの名前には、I2 から I8 と D1、D2 の番号を入れる。

- **I2**：述語のテスト「a figure taller than the column is not judged」を、「a figure taller than the column is broken」（C + 1 行の図版を置いた段で I2 の違反を返す）に改める。列挙のテストで、C = 3 の要素が 16 であること。
- **I4、I5**：「the first line after nothing but a heading is not judged」と「the lines after nothing but a heading are not judged」を、許す規則のテスト（違反を返さない）として名前を改める。式は変えない。
- **I6（5）**：見出しの後の 3 行の段落の 3 行めだけが次の段にある出力を手で作り、I6 の違反を返すこと。4 行の段落の 3 行めが次の段にある出力では、違反を返さないこと。
- **I6（4）**：「a heading before a heading at a recto is not judged」を、改丁の見出しの前の見出しが段の末尾に残る出力で違反を返さないことと、その前の見出しの並びが分かれた出力で違反を返すことに分ける。
- **I8（3）**：「after the figures sent on is not judged」を、送った図版の後に改丁の見出しを置いた出力で I8 の違反を返すことに改める。
- **D1**：`nextNeed` に、見出し、改丁の見出し、段落の流れを渡し、見出しの量だけを返すこと。`PaginateSpec` に、一段、C = 3 で `[EPara 2, EHeading, ERecto, EPara 1]` を置き、見出しが 1 ページの最後の行に残り、2 ページが白ページ、3 ページに改丁の見出しと段落が置かれること。今は見出しが 2 ページに一つだけ置かれるので失敗する。
- **D2**：一段、C = 3 で `[EHeading, EPara 3]` を置くと、1 ページに見出しと段落の 2 行、2 ページに段落の 1 行が置かれること（今の出力を固定する回帰のテスト）。
- **全体**：要素 3 個まで（プルリクエスト）と 5 個まで（毎晩の `enum.yml`）で、既知の不具合の一覧で除くほかの違反がないこと。固定した数を、7 のとおり数え直した値にすること。

## トレードオフ

1 は、段より高い図版を改ページで扱う道を閉じる。
golem-driver が図版を縮める規則を変え、段より高い図版を改ページに渡すようになれば、そのときに I2 と列挙を見直す ADR が要る。
今は、仕様書が起きないと定める入力の振る舞いを、テストで固定しないほうを選ぶ。

2 は、見出しだけの段の後に、孤立行か寡婦行を許す。
見出しだけを段に残すよりはよく、空の段と同じ規則なので、規則の数が増えない。

3 は、改丁の前に送った図版のページと白ページを足すことがある（[golem-layout ADR 0024](../golem-layout/adr/0024-recto-start-places-figures-sent-on-first.md) の「トレードオフ」）。

4 は、改丁の見出しの直前の見出しを、本文を持たないまま段の末尾に残す。
今の実装は、その見出しを次の段に送って一つだけ置くことがあり、その後の改丁で白ページがさらに増えることもある。
どちらにしても見出しは後と離れるので、ページの少ないほうを選ぶ。

5 は、述語に [golem-layout ADR 0021](../golem-layout/adr/0021-keep-with-next-counts-widow-and-orphan.md) の表を写すので、表を変える ADR では述語も変える。
孤立行と寡婦行の規則があるので、3 行の段落では、2 行を調べる今の I6 と I5 を合わせたものと、ほとんど同じ入力を違反とする。
それでも仕様書の文と述語を一対一に対応させるほうを選ぶ。

## メンテナーが決めること

1. **段より高い図版（I2）**：推奨は、改ページの入力の前提として C 行以下に限り、列挙から C + 1 行の図版を除き、I2 をどの段でも判定することである。仕様書が図版を縮めると定めているので、起きない入力を列挙すると、要素の候補が増えて時間が延び、判定しない例外も増える。
   - 退けた案の一つは、C + 1 行の図版を列挙に残し、空の段に置いて段からあふれるという今の振る舞いを規則として定めることである。仕様書が起きないと定める入力の振る舞いを、テストで固定することになる。
   - もう一つは、改ページの側で図版を段に収まるように縮めることである。図版の大きさは golem-driver が決めており、改ページは格子の行の数しか持たない。
2. **見出しだけを置いた段の後（I4、I5）**：推奨は、空の段と同じく、孤立行と寡婦行の規則で一行も置けなくなる場合は入るだけの行を置くことである。今の実装と述語の式のとおりで、Alloy のモデルは、規則を緩めなければすべてを満たす配置のない入力があること（`strictAfterHeadings`）と、緩めればないこと（`relaxedAfterHeadings`）を示した。
   - 退けた案の一つは、「一行は置き」を文字どおりに読み、ちょうど 1 行を置くことである（孤立行は許し、寡婦行は許さない）。空の段の規則と別の規則になり、出力も変わる。
   - もう一つは、見出しを後の段に送ることである。空の段からは送らない規則に反し、見出しが段に入りきらない場合には止まらない。
3. **改丁の見出しの前の送った図版（I8）**：推奨は、送った図版と続きの脚注をすべて置いてから奇数ページを始め、改丁の見出しをページの最初の要素にすることである。前の章の図版が次の章の扉に出ない。LaTeX の `\cleardoublepage` も、待っている図版をすべて出力してから奇数ページを始める。
   - 退けた案の一つは、仕様書の文のとおり、改ページの後の新しいページの先頭に送った図版を置き、改丁の見出しをその後に置くことである。ページは増えないが、章の扉に前の章の図版が載り、見出しがページの最初でなくなる。
   - もう一つは、改丁の見出しの後に送った図版を置くことである。図版が次の章の本文の中に入り、図番号の順と章の順が食い違う。
4. **改丁の見出しが続く見出し（I6 と I8）**：推奨は、見出しの並びを改丁の見出しの前で切り、前の見出しは後に続くものを数えないことである（`@page-break` の前の見出しと同じ）。前の見出しは今の段に残り、改丁は次の奇数ページから始まる。
   - 退けた案は、今のとおり改丁の見出しを並びに数えることである。前の見出しを次の段に送って一つだけ置くことがあり、I6 は前の見出しが段の最初になって成り立つが、ページが増える。見出しが後と離れることは変わらない。
5. **I6 の段落の行の数**：推奨は、[golem-layout ADR 0021](../golem-layout/adr/0021-keep-with-next-counts-widow-and-orphan.md) の量（3 行以下の段落は全体、4 行以上は 2 行）にすることである。仕様書の文と述語が一致する。
   - 退けた案は、[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の文のとおり 2 行のままにすることである。仕様書と述語が食い違ったまま残り、表を変える ADR で述語の変え忘れに気付けない。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-08、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) と、その実装のプルリクエスト（[#641](https://github.com/tett23/golem/pull/641)）の報告
- [docs/adr/0017](0017-forced-page-breaks.md)
- [golem-layout ADR 0003](../golem-layout/adr/0003-pagination-and-s2.md)、[golem-layout ADR 0019](../golem-layout/adr/0019-keep-with-next-counts-footnotes.md)、[golem-layout ADR 0021](../golem-layout/adr/0021-keep-with-next-counts-widow-and-orphan.md)、[golem-layout ADR 0023](../golem-layout/adr/0023-keep-with-next-after-figures-sent-on.md)、[golem-layout ADR 0024](../golem-layout/adr/0024-recto-start-places-figures-sent-on-first.md)
- [golem-driver ADR 0032](../golem-driver/adr/0032-default-heading-styles.md)、[golem-driver ADR 0034](../golem-driver/adr/0034-fit-figures-to-column.md)
- [docs/golem-layout/models/README.md](../golem-layout/models/README.md)
- "LaTeX2e: An unofficial reference manual", `\clearpage & \cleardoublepage`. https://latexref.xyz/_005cclearpage-_0026-_005ccleardoublepage.html（今のページを終え、待っている図版と表をすべて出力する。2026-11-08 に確かめた）
- Daniel Jackson. Software Abstractions: Logic, Language, and Analysis. Revised edition, MIT Press, 2012.
