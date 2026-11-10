# ADR 0295: 表の列の幅を、小さな入力のすべてで確かめる

ステータス: 採択（未実装）

## 文脈

[ADR 0208](0208-widen-lightweight-formal-methods.md) の 1 は、規則を不変条件として書き、小さな入力のすべてで確かめる手法を、範囲ごとに一つの ADR で広げるとした。
順の 2 が表の列の幅で、前提は 1 の和文の行分割（[ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md)）の結果である。
0209 は実装され、その後の列挙の ADR の予算は [ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md) が決めた。
この ADR は、順の 2 の範囲の ADR である。

### 今の規則とテスト

列の幅は `Golem.Layout.Table` の `columnWidths` と `tableColumnWidths` が決める（[`Table.hs#L62-L127`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/modules/golem-layout/src/Golem/Layout/Table.hs#L62-L127)）。
各列は、最小の幅 lo と自然な幅 hi を持つ。

- 自然な幅の和が使える幅 W に収まれば、各列は自然な幅を受け取る。
- 最小の幅の和が W を超えれば、G07041（`ColumnsTooWide`）である。
- そのほかは [golem-driver ADR 0037](../golem-driver/adr/0037-table-column-widths.md) の配り方で、`S(C) = Σ clamp C lo_i hi_i ≤ W` を満たす最大の整数 C を求め、各列に `clamp C lo_i hi_i` を与え、残り `W − S(C)` を「幅が自然な幅に届いていない列」に左から 1sp ずつ配る。

`tableColumnWidths` は、利用者が幅を書いた列（[ADR 0262](0262-table-numbers-captions-column-widths-and-cell-styles.md)）にその幅を与え、残りの列で `columnWidths` を呼ぶ。
G07114（書いた幅の和が W を超える）、G07115（書いた幅が最小の幅より狭い）、G07041 の三つの誤りを返す。

今のテストは、決まった入力の例と、hedgehog の性質一つである（[`Main.hs#L1059-L1085`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/modules/golem-layout/test/Main.hs#L1060-L1086)）。
性質は、和が W に等しいこと、各列が lo 以上 hi 以下であること、自然な幅が C 以下の列は自然な幅を受け取ることを、列の数が 1 から 8、幅が 0 から 1000 の乱数の入力で確かめる。

### 小さな入力で見つかったこと

この ADR を書くために、`columnWidths` を `Integer` に写した関数を、幅を 0 から 4、列の数を 1 から 3、W を 0 から 13 のすべての組で走らせた（2026-11-10、手元の `runghc`）。
今の性質の三つは、すべての組で成り立った。
一方、W を 1 増やすと、ある列の幅が減る入力があった。

列が (lo, hi) = (1, 2)、(0, 1)、(0, 1) で、W が 2 と 3 のときである。

- W = 2 では、C = 0 で `S(0) = 1`、`S(1) = 3` なので C は 0 になる。幅は `[1, 0, 0]` で、残りの 1 を、自然な幅に届いていない最も左の列、つまり最初の列に配り、`[2, 0, 0]` になる。
- W = 3 では、C = 1 で `S(1) = 3` なので、幅は `[1, 1, 1]` になる。

最初の列は、W が増えると 2 から 1 に減る。
原因は、残りを受け取る列に、最小の幅のために C より広い列（lo > C）を含めることである。
その列は水位 C の上にあり、水を注ぐ配り方では、残りは水位にある列（lo ≤ C < hi）だけが受け取るはずである。
水位にある列の数は `S(C + 1) − S(C)` に等しく、C が最大なので、残りはその数より小さい。
残りを水位にある列だけに配っても、一巡で配り終わる。

この配り方に替えた関数を、幅を 0 から 5、列の数を 1 から 3 のすべての組と、幅を 0 から 3、列の数を 1 から 4 のすべての組で走らせ、W を増やして幅の減る入力がないこと、和と幅の範囲の性質が保たれることを確かめた。
違いは 1sp の単位で、見た目では区別できない。
それでも、使える幅が広がると列が狭くなる規則は、[golem-driver ADR 0037](../golem-driver/adr/0037-table-column-widths.md) が求めた「短い列を先に満たす」の一つの読み方として説明できない。

## 実装すること

### 1. 残りの配り方を改める

[golem-driver ADR 0037](../golem-driver/adr/0037-table-column-widths.md) の「列の幅の配り方」の 3 を、次に改める。

3. 残り `W − S(C)` を、水位にある列（`lo_i ≤ C < hi_i` の列）に、左（縦組みでは上）の列から 1sp ずつ配る。

1 と 2 は変えない。
[golem-driver ADR 0037](../golem-driver/adr/0037-table-column-widths.md) のステータスの行に、3 をこの ADR で改めたことを書き足す（「メンテナーが決めること」の 1）。

### 2. 列挙

golem-layout のテストに `ColumnWidthInvariantsSpec` を足し、[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) と同じ形（`Golem.TestSupport.Enum` の段、`checkAllPar`、反例の表示）で、次の入力を列挙する。

- **`columnWidths`**：列の数 n、各列の (lo, hi)（0 ≤ lo ≤ hi ≤ K）、W（0 から n·K + 1）。
- **`tableColumnWidths`**：上に加え、各列の指定（`ColumnAuto` か、`ColumnAbs w`、0 ≤ w ≤ K）。共有する幅は W とする。

上限は、範囲の環境の変数 `GOLEM_ENUM_TABLE_DEPTH` で決める。
プルリクエストの上限を、`columnWidths` は K = 4、n ≤ 3、`tableColumnWidths` は K = 3、n ≤ 3 とし、毎晩の上限を、それぞれ K = 5、n ≤ 4 と K = 4、n ≤ 3 とする。
値は、実装で [ADR 0286](0286-leave-the-start-of-cabal-out-of-the-time-of-an-enumeration-area.md) の量り方（テストの実行ファイルを直接走らせた時間）と判定（四つのジョブの中央値）で測り、範囲の予算 10 秒と和の予算 30 秒に収まるように決め直す。

### 3. 素朴な探索との比較

列挙の各入力で、C を 0 から最大の hi まで一つずつ試す素朴な探索で幅を求め、`columnWidths` の結果と比べる（不変条件の C5）。
二分探索の境目の誤りを見つけるためで、[ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md) の素朴な探索と同じ役目である。

### 4. 毎晩のジョブ

`enum.yml` に、範囲 `TABLE` の段を足す。
[ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md) の N4 のとおり `!cancelled()` を付け、N5 の時間を量る段に、この範囲の行を足す。

### 5. 文書

- 仕様書の表の節の列の幅の説明を、1 の配り方に改め、この ADR へのリンクを付ける。列挙の範囲の段落を、ほかの範囲と同じ形で足す。
- README の `enum.yml` の行に、範囲 `TABLE` を足す。
- [docs/roadmap.md](../roadmap.md) の「軽量な形式手法の残りの範囲」の子の「表の列の幅」を外す。

## 実装しないこと

- `ColumnZw` と `ColumnPercent` の指定の列挙。`specifiedWidth` の切り捨ては、長さの換算と丸めの範囲（[ADR 0208](0208-widen-lightweight-formal-methods.md) の順の 5）で扱う。
- `layoutTable` の列挙（セルを行に分けた結果）。セルの項目を作るには行分割の部品が要り、その規則は [ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md) の範囲で確かめている。
- `cellExtent` の列挙。最小の幅は改行の位置の規則で決まり、行分割の範囲に属する。
- Alloy のモデル。規則は三つの場合の分岐と一つの探索で、三つ以上の規則が端で重なる形ではない（[ADR 0208](0208-widen-lightweight-formal-methods.md) の 5）。

## 不変条件

列を `cols = [(lo_i, hi_i)]`、使える幅を W、`columnWidths W cols` の結果を w とする。
`Lo = Σ lo_i`、`Hi = Σ hi_i`、`S(C) = Σ clamp C lo_i hi_i` とし、C* は `S(C) ≤ W` を満たす 0 以上 `max hi_i` 以下の最大の整数とする。

- **C1 誤りの条件**：`Lo > W` のとき、そのときに限り、結果は `Left (ColumnsTooWide Lo W)` である。
- **C2 収まれば自然な幅**：`Hi ≤ W` なら、w は `map snd cols` である。
- **C3 和**：`Lo ≤ W < Hi` なら、`Σ w_i = W` である。
- **C4 範囲**：結果が `Right w` なら、どの i でも `lo_i ≤ w_i ≤ hi_i` である。
- **C5 水位**：`Lo ≤ W < Hi` なら、`w_i = clamp C* lo_i hi_i + e_i` で、e_i は、水位にある列（`lo_i ≤ C* < hi_i`）のうち左から `W − S(C*)` 個で 1、ほかで 0 である。C* は素朴な探索で求める。
- **C6 単調**：`columnWidths W cols` と `columnWidths (W + 1) cols` がどちらも `Right` なら、どの i でも前の幅は後の幅以下である。
- **C7 指定のある列**：`tableColumnWidths` の結果が `Right` なら、幅を書いた列はその幅で、書かない列の幅の並びは、`columnWidths (W − 書いた幅の和)` を書かない列に当てた結果に等しい。
- **C8 指定の誤り**：`tableColumnWidths` は、幅を書いた列があってその和が W を超えるときに限り `WidthsTooWide` を返し、書いた幅が lo より狭い列ごとに `ColumnTooNarrow` を返し、そのどちらもないときに限り、書かない列について C1 の誤りを返す。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 列の数 | 1、2、上限 |
| W | 0、`Lo − 1`、`Lo`、`Hi − 1`、`Hi`、`Hi + 1` |
| 列の幅 | lo = hi（伸びない列）、lo = 0、hi = 0、lo > C*（最小の幅で水位より広い列） |
| 残り | 0、水位にある列の数 − 1 |
| 指定 | すべて `ColumnAuto`、すべて指定、指定の和が W ちょうど、W + 1、指定が lo − 1 と lo |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
テストの名前には、C1 から C8 の番号を入れる。

- C1 から C8 を、2 の列挙で確かめる。今の実装では、C5 と C6 が文脈の入力（(1, 2)、(0, 1)、(0, 1) と W = 2）で落ちる。C5 は、今の実装が残りを最初の列に配るので落ちる。
- 文脈の入力を、例のテストとして `Main.hs` の列の幅のテストに足す。期待は `Right [1, 1, 0]` である。
- 今の hedgehog の性質は、C3、C4 と C5 の一部にあたるので、列挙の上限より大きな入力（列の数 8、幅 1000 まで）を見るために残す。
- 1 の変更で、golden の PDF のバイト列が変わる fixture があれば、変わった表を PDF の画像で見て、違いが 1sp の単位であることを確かめてから golden を更新する。
- 手元の測定で、`columnWidths` の列挙のプルリクエストの上限（入力は約 5 万）は、検査の関数が小さいので、範囲の予算に十分収まる見込みである。実装で、2 の値を [ADR 0286](0286-leave-the-start-of-cabal-out-of-the-time-of-an-enumeration-area.md) の量り方と判定で測る。

## トレードオフ

1 の変更で、最小の幅のために水位より広い列は、残りの 1sp を受け取らなくなる。
その 1sp は水位にある列が受け取る。
出力の違いは 1sp の単位で、行分割が変われば、セルの改行の位置が変わることはありうる。

C5 は、規則を素朴な探索の形で書き写したもので、規則そのものの正しさ（JLReq や tabularx に近いか）は確かめない。
それは [golem-driver ADR 0037](../golem-driver/adr/0037-table-column-widths.md) の決定のままである。

## メンテナーが決めること

1. **残りの配り方**：推奨は、水位にある列だけに配ることである。C6（使える幅が広がれば、どの列も狭くならない）が成り立ち、[golem-driver ADR 0037](../golem-driver/adr/0037-table-column-widths.md) の「短い列を先に満たし、残りを長い列で等分する」の説明にも合う。
   - 退けた案は、今の配り方を残し、C6 を不変条件にしないことである。列挙は今の振る舞いを確かめるだけになり、文脈の入力は既知の振る舞いとして残る。
2. **[golem-driver ADR 0037](../golem-driver/adr/0037-table-column-widths.md) の改め方**：推奨は、この ADR で 3 を改め、[golem-driver ADR 0037](../golem-driver/adr/0037-table-column-widths.md) のステータスの行に書き足すことである。[golem-driver ADR 0037](../golem-driver/adr/0037-table-column-widths.md) は採択済みで、本文を変えられない。
   - 退けた案は、golem-driver の ADR を新しく立てることである。改めるのは列挙が見つけた一点で、列挙の ADR から切り離すと、理由と確かめ方が別の文書に分かれる。
3. **プルリクエストの上限**：推奨は、`columnWidths` を K = 4、n ≤ 3、`tableColumnWidths` を K = 3、n ≤ 3 とし、実装で測って決め直すことである。文脈の反例は K = 2、n = 3 で現れ、この上限はそれを含む。
   - 退けた案は、毎晩だけで列挙することである。検査の関数が小さく、プルリクエストの予算に収まる見込みがあるのに、マージの前に見つける機会を捨てる。

## 決めたことの記録

2026-11-10 に、tett23 が「メンテナーが決めること」のすべてを推奨のとおりに決めた。

1. 残りの幅は、水位にある列だけに配る。
2. この ADR で [golem-driver ADR 0037](../golem-driver/adr/0037-table-column-widths.md) の 3 を改め、そのステータスの行に書き足す。
3. プルリクエストの上限は、`columnWidths` を K = 4、n ≤ 3、`tableColumnWidths` を K = 3、n ≤ 3 とし、実装で測って決め直す。

採択にあたり、同じプルリクエストで採択した [ADR 0286](0286-leave-the-start-of-cabal-out-of-the-time-of-an-enumeration-area.md) に合わせて、「実装すること」の 2 とテスト設計の上限の値の量り方を、[ADR 0286](0286-leave-the-start-of-cabal-out-of-the-time-of-an-enumeration-area.md) の量り方と判定（四つのジョブの中央値）に改めた。
採択にあたり、ソースコードへのリンクを `main` の `9acc137a`（[ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md) の実装のマージ）に合わせた。
`modules/golem-layout/test/Main.hs` は、[ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md) の実装で一行の import が増えたので、行の範囲を一つ送った。

## 参考文献

- [ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md)、[ADR 0208](0208-widen-lightweight-formal-methods.md)、[ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md)、[ADR 0262](0262-table-numbers-captions-column-widths-and-cell-styles.md)、[ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md)、[ADR 0286](0286-leave-the-start-of-cabal-out-of-the-time-of-an-enumeration-area.md)
- [golem-driver ADR 0008](../golem-driver/adr/0008-pdf-tables.md)、[golem-driver ADR 0037](../golem-driver/adr/0037-table-column-widths.md)
- [`modules/golem-layout/src/Golem/Layout/Table.hs`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/modules/golem-layout/src/Golem/Layout/Table.hs#L62-L127)、[`modules/golem-layout/test/Main.hs`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/modules/golem-layout/test/Main.hs#L1060-L1086)、[`.github/workflows/enum.yml`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/.github/workflows/enum.yml)
- CSS 2.1 の 17.5.2.2（表の自動の配置）、JLReq の 4.4.3
