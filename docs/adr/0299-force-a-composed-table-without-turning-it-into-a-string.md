# ADR 0299: 組んだ表を、文字列にせずに評価しきる

ステータス: 採択（未実装）

## 文脈

[ADR 0290](0290-keep-the-cost-of-a-table-within-the-cell-limit-and-measure-where-it-goes.md) の実装で、セルの上限の内側の表の費用を測った（[docs/benchmarks/2026-11-10-cost-of-tables-within-the-cell-limit.md](../benchmarks/2026-11-10-cost-of-tables-within-the-cell-limit.md)、以下「記録」）。
割り当てはセルの数に比例し、1 セルあたり 229 KB から 233 KB だった。
100,000 セルの表は 22.9 GB を割り当てる。

その割り当ての 54% と CPU 時間の 25% は、組版の結果に使われない。
表の単位を並列に組む `flowLines` は、組んだ表を次の一行で評価しきる（[`Flow.hs#L3144`](https://github.com/tett23/golem/blob/2ca838ce01ba2423df175cf6548a89bb9f4482c4/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L3144)）。

```haskell
evaluate (length (show (fmap fst r)))
```

`r` は `Either TableRefusal (SetTable, ...)` である。
`show` は、`SetTable` のすべてのセル（`SetCell`）のすべての行（`Line`）のすべての項目を、導出された `Show` で文字列にする。
項目の `Look`（書体、言語、色、下線など）とソースの位置まで文字列になり、長さを数えた後に捨てられる。
記録の表 3 では、`SetCell` の `Show` の下で `Look` の `showsPrec` が単独で 17.6%、`Golem.Layout.KnuthPlass` の型の `showsPrec` が合わせて 28.5% を割り当てる。
10,000 セルの表でも 52.9% で、この費用もセルの数に比例する。

評価しきる目的は、組版の仕事を `mapConcurrently` のスレッドの中で済ませることである（[golem-driver ADR 0002](../golem-driver/adr/0002-pdf-pipeline.md)）。
段落の単位は `forceComposed`（[`Flow.hs#L2522-L2524`](https://github.com/tett23/golem/blob/2ca838ce01ba2423df175cf6548a89bb9f4482c4/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L2522-L2524)）で、各行の `lineRatio` だけを `show` する。
`Line` のフィールドはすべて正格である（[`KnuthPlass.hs#L276-L298`](https://github.com/tett23/golem/blob/2ca838ce01ba2423df175cf6548a89bb9f4482c4/modules/golem-layout/src/Golem/Layout/KnuthPlass.hs#L276-L298)）。
行を WHNF まで評価すれば、行分割（`breakParagraph`）は済み、`lineItems` のリストの最初の構成子と `lineRatio` も評価される。
`SetCell` の `scLines` も正格のフィールドである（[`Table.hs#L126-L133`](https://github.com/tett23/golem/blob/2ca838ce01ba2423df175cf6548a89bb9f4482c4/modules/golem-layout/src/Golem/Layout/Table.hs#L126-L133)）。

改ページは費用の行き先ではなかった（記録の表 3、`paginateWithin` は 0.1%）。
常駐の山はページの描画と PDF の書き出しにあり、`show` の文字列は作るそばから捨てられるので、常駐にはほとんど現れない（記録の表 4）。

## 実装すること

1. `Flow.hs` の表の評価を、文字列を作らない関数（仮に `forceTable`）に置き換える。
   - `Left (TooManyCells n)` は `n` を、`Left (LayoutRefused es)` は `es` の各要素を WHNF まで評価する。`TableError` のフィールドは正格なので、これで要素は評価しきられる。
   - `Right (set, _)` は、`stWidths` の各要素、`stHeaderLines`、`stRowLines` の各要素と、`stHeader` と `stRows` のすべての `SetCell` の `scLines` の各行と `scShifts` の各要素を WHNF まで評価する。`forceComposed` が段落の各行の `lineRatio` を評価するのと同じ深さである。
   - `show` を使わない。`deepseq` のような新しい依存も足さない。
2. 振る舞いを変えない。出力の PDF、diagnostics、終了コード、組版の結果は、置き換えの前とバイト列で一致する。
3. 実装のプルリクエストで、記録と同じ入力と方法（[`make-tables.sh`](../benchmarks/2026-11-10-cost-of-tables-within-the-cell-limit/make-tables.sh)、[`measure.sh`](../benchmarks/2026-11-10-cost-of-tables-within-the-cell-limit/measure.sh)）で、置き換えの前と後を測り、`docs/benchmarks/` に新しい記録を置く。

## 実装しないこと

- 段落の `forceComposed` と図の見出しの評価の `show (map lineRatio ...)` を変えること。`Rational` の文字列は行ごとに数十バイトで、記録の内訳の 3% に届かない。
- `exceptionPatterns` をセルごとに作り直すこと（記録の表 3 で 3.4%）を、表ごとに一度にすること。費用は別の関数にあり、ハイフネーションの例外の扱い（[ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md)）に触れるので、要れば別の ADR で決める。
- セルの上限（[ADR 0224](0224-limit-the-cells-of-a-table-set-in-pdf.md)、100,000）を変えること。
- 常駐を下げること。常駐の山は描画と PDF の書き出しにあり、この変更では下がらないと見込む。
- `NFData` のインスタンスを足すこと（「メンテナーが決めること」の 1）。

## 不変条件

- **I1 出力は変わらない**：どの入力でも、置き換えの後の `golem build --target pdf` の `build/` の下のすべてのファイルのバイト列、終了コード、標準出力、標準エラー出力（`--format json` の diagnostics を含む）は、置き換えの前と一致する。
- **I2 拒む表は拒む**：セルの数が上限を超える表と、列の幅を決められない表に対して、`forceTable` は例外を投げずに終わり、結果は `composeTable` の `Left` のままである（G07108、G07041、G07114、G07115 の判定は変わらない）。
- **I3 評価は組んだ行に届く**：`forceTable` を通した `SetTable` のすべてのセルの `scLines` は、長さが `breakParagraph` の行の数に等しい。テストでは、`forceTable` の後に `ghc-heap` などで評価の状態を調べず、`forceTable` が返した値と、`show` で評価しきった値が `==` で等しいことを述語にする。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| セルの数 | 見出しの行だけ（本体の行が 0）、1 セル、空のセルだけの見出しの行、100,000（上限ちょうど）、100,001（G07108） |
| セルの中身 | 空、一字、行分割で二行以上になる文、注やルビを含むセル |
| 列の幅 | 収まる、指定の幅の合計が行長を超える（G07114）、指定の幅が列の最小の幅より狭い（G07115）、列が多すぎて収まらない（G07041） |

## テスト設計

先に書いて失敗させてから実装するもの。

- I2 と I3：golem-typeset のテストに、上の境界の入力の表を `composeTable` で組み、`forceTable` の結果が例外を投げず、`fmap fst` が元の値と等しいことを確かめるテストを足す。テストの名前に I2、I3 を入れる。`forceTable` がまだないので、最初はコンパイルできずに失敗する。

既存のテストで確かめること。

- I1：golem-driver の表の fixture の PDF のゴールデンと、`scripts/determinism.sh` の二回のビルドの一致。置き換えの前後で通ることを確かめる。

測って確かめること（実装のプルリクエストの説明と記録に書く）。

- 記録の表 1 と同じ入力で、割り当てが 40% 以上減ること。記録の内訳から見込む減りは 54% である。
- CPU 時間の中央値が減ること。負荷で揺れるので、置き換えの前と後を交互に走らせ、同じ周の比の中央値で読む（[docs/benchmarks/2026-11-09-link-golem-with-a-64-mb-allocation-area.md](../benchmarks/2026-11-09-link-golem-with-a-64-mb-allocation-area.md) と同じ方法）。
- 最大常駐が増えないこと。
- 利用者向けマニュアルと十冊の fixture（[docs/benchmarks/2026-11-09-typesetting-speed-survey.md](../benchmarks/2026-11-09-typesetting-speed-survey.md) の入力）の割り当てと壁時計が、悪くならないこと。

## トレードオフ

- 評価の深さが変わる。今の `show` は項目の `Look` の中まで評価するので、表の項目のうち `composeInlines` が遅延させた部分も並列のスレッドで評価される。行を WHNF まで評価するだけにすると、行の項目の中身のうち、描画で初めて要る部分は描画の側で評価される。描画はページごとに並列なので（[ADR 0252](0252-draw-and-serialise-the-pages-of-the-pdf-in-parallel.md)）、仕事は並列のまま移ると見込むが、確かめていない。測って、壁時計が悪くなれば「メンテナーが決めること」の 1 の案を取り直す。
- 段落と表で評価の深さがそろう。表を深く評価する一行は、表を行の格子に載せたコミット（[`a32d76cf`](https://github.com/tett23/golem/commit/a32d76cff0b470881706492e288b0bd7f29b18cd)）で入った。そのコミットの説明は、段落と違う深さにした理由を書いていない。
- 表の型にフィールドを足すと、`forceTable` も直す必要がある。`show` はフィールドを足しても自動で追いついていた。

## メンテナーが決めること

1. **評価の仕方**：推奨は、`forceComposed` と同じく行までを WHNF で評価する専用の関数である。依存を足さず、段落と同じ深さになる。
   - 退けた案の一つは、`deepseq` に依存し、`SetTable`、`SetCell`、`Line`、項目、`Look` などに `NFData` のインスタンスを足すことである。今の `show` と同じ深さまで評価でき、文字列も作らない。ただし golem-layout と golem-typeset に依存が増え、インスタンスは十数の型にわたる。
   - もう一つは、評価しないことである。仕事はすべて描画の側に移り、表の組版が並列でなくなる。
2. **測定の基準**：推奨は、割り当てが 40% 以上減ることを実装の条件にすることである。割り当ては負荷に依らず、記録の 10 回の幅は 0.1% 以内だった。
   - 退けた案は、CPU 時間で条件を置くことである。記録では、同じ入力の CPU 時間が負荷で 2 倍揺れた。

## 決めたことの記録

2026-11-10 に、tett23 が「メンテナーが決めること」のすべてを推奨のとおりに決めた。

1. 表は、`forceComposed` と同じく行までを WHNF で評価する専用の関数で評価しきる。`deepseq` と `NFData` のインスタンスは足さない。
2. 実装の条件は、記録の表 1 と同じ入力で割り当てが 40% 以上減ることとする。CPU 時間は条件にしない。

採択にあたり、ソースコードへのリンクを `main` の `2ca838ce`（[ADR 0293](0293-run-the-test-suites-of-the-packages-of-golem-wasm-on-wasm32-every-night.md) の実装のマージ）に合わせた。
境界の入力の表の列の幅の行に、G07115 を足し、G07114 の説明を直した。

## 参考文献

- [docs/benchmarks/2026-11-10-cost-of-tables-within-the-cell-limit.md](../benchmarks/2026-11-10-cost-of-tables-within-the-cell-limit.md)
- [ADR 0224](0224-limit-the-cells-of-a-table-set-in-pdf.md)、[ADR 0252](0252-draw-and-serialise-the-pages-of-the-pdf-in-parallel.md)、[ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md)、[ADR 0290](0290-keep-the-cost-of-a-table-within-the-cell-limit-and-measure-where-it-goes.md)、[golem-driver ADR 0002](../golem-driver/adr/0002-pdf-pipeline.md)
- [`modules/golem-typeset/src/Golem/Typeset/Flow.hs`](https://github.com/tett23/golem/blob/2ca838ce01ba2423df175cf6548a89bb9f4482c4/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L3144)、[`modules/golem-layout/src/Golem/Layout/Table.hs`](https://github.com/tett23/golem/blob/2ca838ce01ba2423df175cf6548a89bb9f4482c4/modules/golem-layout/src/Golem/Layout/Table.hs#L126-L133)、[`modules/golem-layout/src/Golem/Layout/KnuthPlass.hs`](https://github.com/tett23/golem/blob/2ca838ce01ba2423df175cf6548a89bb9f4482c4/modules/golem-layout/src/Golem/Layout/KnuthPlass.hs#L276-L298)
- GHC User's Guide 9.10, "Profiling"（`-fprof-late`、`+RTS -p`、`+RTS -hc`）。https://downloads.haskell.org/ghc/9.10.3/docs/users_guide/profiling.html
