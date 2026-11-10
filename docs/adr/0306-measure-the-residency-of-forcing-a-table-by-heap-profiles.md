# ADR 0306: 表を評価しきる変更の最大常駐を、ヒープのプロファイルで測り直す

ステータス: 採択（未実装）

## 文脈

[ADR 0299](0299-force-a-composed-table-without-turning-it-into-a-string.md) は、組んだ表を `show` で文字列にせずに評価しきる変更を決めた。
その実装（プルリクエスト #897）は、表の割り当てを 52.3% から 53.2% 減らした（[docs/benchmarks/2026-11-10-force-a-composed-table-without-show.md](../benchmarks/2026-11-10-force-a-composed-table-without-show.md)、以下「記録」）。
しかし、[ADR 0299](0299-force-a-composed-table-without-turning-it-into-a-string.md) のテスト設計の「最大常駐が増えないこと」は、20,000 から 80,000 セルの四つの入力で満たさなかった。
記録の表 1 では、20,000 セルの表（c10-r2000）の最大常駐が 37.0 MB から 80.6 MB に増えている。
記録は、標本の取り方による見かけの増えだと見込んだが、ヒープのプロファイルを取っていない。
tett23 は、実装がうまくいっていなかったとして、新しい ADR を作ると決めた。

この ADR の起草のために、#897 の前と後のヒープのプロファイルを取った（「調査の記録」）。
生きているデータの山（実行のあいだに、GC の後に生きているデータの量の最大）は、前と後で揺れの幅の中にあった。
増えたのは、`+RTS -s` の「maximum residency」という標本の値である。
測定済みの入力では、前後の山は近かった。
表を組む途中の保持と、まだ測っていない入力については、増加がないとは判断していない。

「maximum residency」は、主の GC（世代 1 の GC）を終えたときに生きているデータの量の最大である。
製品の `golem` は `-with-rtsopts=-N -A64m` でリンクされる（[`golem-cli.cabal#L18`](https://github.com/tett23/golem/blob/2e074342c2a5473016bec162c79b0c9c6224a560/modules/golem-cli/golem-cli.cabal#L18)）。
割り当て領域が大きいので GC そのものが少なく、c10-r2000 の GC は前で 8 回、後で 5 回、そのうち主の GC は前で 2 回、後で 3 回だった（終了時の GC を含む、「調査の記録」）。
c10-r2000 では、前は主の GC が開始から約 0.36 秒に一回だけ起き、そのときの生きているデータは 37.4 MB だった（終了時の GC を除く）。
この量は、表 A の測定で表を組む段階の生きているデータ（37 から 39.5 MB）と合う。
後は割り当てが半分になって GC の起きる時点がずれ、約 0.48 秒の主の GC が 82.5 MB を見た。
この量は表を組む段階より多く、描画の段階に入った後の量と見る（GC の時点がどの段階かは、生きているデータの量から推したもので、未確認）。
記録の `measure.sh` は、この値を最大常駐として読んでいる（[`measure.sh`](../benchmarks/2026-11-10-force-a-composed-table-without-show/measure.sh) の `res=` の行）。

ヒープのプロファイル（`+RTS -hT -i0.01`）を取ると、主の GC が標本の間隔ごとに起きる。
起草の調査では、`-hT` を付けた実行の `-s` の最大常駐と `.hp` の標本の合計の最大とが、c10-r2000 の前で 107,171,104 バイトと 107.2 MB、c10-r4000 の前で 201,100,608 バイトと 201.1 MB のように一致した。
この一致から、標本が主の GC で取られていると読む（GHC のソースと文書では確かめていない）。
`-A1m` と合わせて 0.01 秒ごとに標本を取ると、生きているデータの山の前と後の差は、同じ実行ファイルの回ごとの揺れより小さかった（表 A）。
c10-r2000 では、三回の山の中央値が前 106.8 MB、後 104.5 MB である。
どちらの山も、記録の `-A64m` の値（前 37.0 MB、後 80.6 MB）より大きい。
つまり、`-A64m` の `-s` の値は前も後も山を測りそこねており、前の値のほうが大きく外れていた。

山の中身も前と後でほとんど同じだった。
c10-r2000 の山の標本では、描画の型（`Golem.Typeset.Draw` の `GlyphUse` と `LineRec`、[`Draw.hs#L389`](https://github.com/tett23/golem/blob/2e074342c2a5473016bec162c79b0c9c6224a560/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L389)、[`Draw.hs#L412`](https://github.com/tett23/golem/blob/2e074342c2a5473016bec162c79b0c9c6224a560/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L412)）と PDF の構造の木（`StructElem`、[`Structure.hs#L112`](https://github.com/tett23/golem/blob/2e074342c2a5473016bec162c79b0c9c6224a560/modules/golem-pdf/src/Golem/Pdf/Structure.hs#L112)）が、前と後で 0.05 MB 以内の差で並ぶ（表 B）。
山は描画と PDF の書き出しにあり、[ADR 0299](0299-force-a-composed-table-without-turning-it-into-a-string.md) の文脈の見立てと合う。
`forceTable`（[`Flow.hs#L2561-L2571`](https://github.com/tett23/golem/blob/2e074342c2a5473016bec162c79b0c9c6224a560/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L2561-L2571)）を変えて山を下げる余地は、この測定からは見つからない。

そこで、まず [ADR 0299](0299-force-a-composed-table-without-turning-it-into-a-string.md) の測り方と許容する比をこの ADR で定め直し、六つの入力を検証する。
`-s` の最大常駐は、割り当てを変える変更の前後で比べると、GC の時点のずれをそのまま差として出す。
割り当てを減らすことは [ADR 0299](0299-force-a-composed-table-without-turning-it-into-a-string.md) の目的そのものなので、この測り方では目的を果たすほど条件を外れやすい。

## 実装すること

1. `modules/` のコードを変えない。`forceTable` とその呼び出し（[`Flow.hs#L3174`](https://github.com/tett23/golem/blob/2e074342c2a5473016bec162c79b0c9c6224a560/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L3174)）をそのまま残し、割り当ての減りを保つ。
2. [ADR 0299](0299-force-a-composed-table-without-turning-it-into-a-string.md) のテスト設計の「最大常駐が増えないこと」を、次の「生きているデータの山」で確かめる。
   - 生きているデータの山とは、`golem build --target pdf +RTS -hT -i0.01 -A1m -s -RTS` で取ったヒープのプロファイルの、標本ごとの合計の最大である。`-N` は製品と同じく有効のままにする。
   - 前は `ff5d9b11`（#897 のマージの第一の親）、後は `2e074342`（#897 のマージ）とし、どちらも `cabal.project.local` に `package golem-cli` の `ghc-options: -rtsopts` を足してビルドする。
   - 入力は記録と同じ六つ（[`make-tables.sh`](../benchmarks/2026-11-10-cost-of-tables-within-the-cell-limit/make-tables.sh) の c10-r1000 から c10-r10000 と c8-r10000）とする。
   - 入力ごとに前と後を交互に 3 回ずつ走らせ、山の中央値の比（後/前）を取る。
   - 実行ごとに別のファイルを用意し、各回の `.hp` と、標準エラーに出る `-s` の統計を保存する。
   - 条件は、どの入力でも比が 1.05 以下であることとする。「増えない」という条件の測定方法だけでなく、許容する比も変更する。
3. 測る脚本と結果を、`docs/benchmarks/` の新しい記録に置く。脚本は、プロファイルを取る `measure-heap.sh` と、`.hp` から標本ごとの合計とその最大を出す `peak.sh` の二つとする。記録には、山の標本の上位の型（`-hT` の内訳）も入力ごとに書く。
4. 実装のプルリクエストで、[ADR 0299](0299-force-a-composed-table-without-turning-it-into-a-string.md) のステータスの行を「採択→最大常駐の確かめ方は [ADR 0306](0306-measure-the-residency-of-forcing-a-table-by-heap-profiles.md)」に変える。[ADR 0299](0299-force-a-composed-table-without-turning-it-into-a-string.md) のほかの行は変えない。
5. 条件を満たさない入力があれば、その入力の `-hT` の内訳と前の内訳との差を記録に書き、この ADR の実装を止めて新しい ADR を起こす。

## 実装しないこと

- `forceTable` の評価を深くすること、または浅くすること。山の内訳は前と後でほとんど同じで（表 B）、表の評価の深さを変えた差が山に現れなかった。
- 製品の RTS の設定（`-N -A64m`）を変えること。測るときだけ `-A1m` にする。
- 記録とそれより前の記録を直すこと。`docs/benchmarks/` の記録はコミットした後に変えない。記録の最大常駐の値は、`-A64m` の `-s` の値として読む。
- ほかの ADR の、最大常駐を条件や見積もりに使った箇所（[ADR 0251](0251-reuse-the-compositions-of-unchanged-units-between-fixpoint-rounds.md)、[0252](0252-draw-and-serialise-the-pages-of-the-pdf-in-parallel.md)、[0253](0253-memoise-run-shaping-and-shorten-the-memo-key.md)、[0255](0255-record-what-implementations-decided-on-2026-11-09.md)）を測り直すこと。
- 「total memory in use」（RTS が OS から取ったメモリ）を条件にすること。記録では 40,000 セルで 973 MiB から 1,060 MiB に、80,000 セルで 1,463 MiB から 1,616 MiB に増え、100,000 セルでは 1,687 MiB から 1,545 MiB に減った（10 回の中央値）。主の GC の時点に依ると見込むが、確かめていない（未確認）。
- 描画と PDF の書き出しの山を下げること。要れば別の ADR で決める。

## 不変条件

なし。
この ADR は `modules/` の振る舞いを変えず、[ADR 0299](0299-force-a-composed-table-without-turning-it-into-a-string.md) の測定方法と許容する比を決める。
[ADR 0299](0299-force-a-composed-table-without-turning-it-into-a-string.md) の I1 から I3 は、#897 のテストのまま成り立つ。

## テスト設計

自動のテストは足さない。
測り方の確かめは、実装の後に次のとおり実際に動かして行う。

- `peak.sh` の確かめ：同じ実行の `+RTS -s` の「maximum residency」と、`peak.sh` の出す最大とが 1% 以内で一致することを、c10-r2000 の一回で確かめる。起草の調査では、前の c10-r2000 で `-s` が 107,171,104 バイト（主の GC 164 回）、`.hp` の最大が 107.2 MB（標本 154 個）だった。
- 条件の確かめ：「実装すること」の 2 の 36 回（六つの入力、前と後、3 回）を走らせ、すべての回が終了コード 0 で終わり、前と後の `build/` のハッシュが一致し、入力ごとの比が 1.05 以下であることを記録に書く。
- 割り当ての確かめ：同じ 36 回の `-s` の割り当てが、記録の表 1 の値から 1% 以内であることを確かめる。`-hT` と `-A1m` は割り当ての量を変えないはずで、変われば測り方を見直す。

## トレードオフ

- `-A1m` は製品の設定ではない。生きているデータの量はプログラムが決めるので、割り当て領域の大きさには依らないと見込む。ただし `-N` の並列の進み方が変わり、同時に生きているデータが変わる余地はある。起草の調査では、後の実行ファイルの c10-r2000 の山は、`-A64m` のまま `-hT` を取ると 103.9 MB（標本 12 個）で、`-A1m` の 3 回の 100.0 から 106.6 MB の幅に入った。
- ヒープのプロファイルを取る実行は遅い。起草の調査では、前の c10-r8000 の一回に約 3 分かかった（ほかのエージェントの作業が動いている計算機で）。100,000 セルを含む 36 回は、数時間かかると見込む。
- 山の測り方は 0.01 秒ごとの標本なので、標本のあいだの短い山は見落とす。`-s` の値よりは細かいが、真の最大ではない。
- 比の 1.05 は、起草の調査の揺れから決めた。同じ実行ファイルの 3 回の山は、c10-r4000 の前で 191.6 MB から 205.5 MB まで 7% 揺れた。中央値を比べるので、揺れより小さい増えは見逃す。

## メンテナーが決めること

1. **[ADR 0299](0299-force-a-composed-table-without-turning-it-into-a-string.md) の条件の扱い**：推奨は、最大常駐を確かめる条件を残し、測定方法と許容する比をこの ADR のものに変えることである。
   - 退けた案の一つは、[ADR 0299](0299-force-a-composed-table-without-turning-it-into-a-string.md) から最大常駐の条件を外すことである。割り当てを減らす変更が保持を増やす場合を見逃す。
   - もう一つは、`-s` の値を製品の `-A64m` のまま回数を増やして読むことである。主の GC の時点は実行ごとにほとんど揺れないので（起草の調査の 2 回で、前は 0.355 秒と 0.400 秒、後は 0.475 秒と 0.509 秒）、回数を増やしても同じ外れ方をする。
2. **比の上限**：推奨は 1.05 である。揺れが 7% あるので、1.02 では揺れだけで外れうる。
3. **以後の ADR**：推奨は、以後の ADR が最大常駐を条件にするときも、この ADR の測り方を使うことである。`docs/benchmarks/` の記録の書き方を決めた文書はまだないので、これを決めるなら、置き場所を別のプルリクエストで決める。

## 調査の記録

起草の調査は、`2e074342` を取り出した作業ツリーで行った。
後の実行ファイルはそのままビルドし、前の実行ファイルは `Flow.hs` の表の呼び出しの一行だけを `evaluate (length (show (fmap fst r)))` に戻してビルドした。
どちらも `-rtsopts` を足し、`-hi` を取るために golem-layout、golem-typeset、golem-pdf、golem-driver、golem-doc に `-finfo-table-map -fdistinct-constructor-tables` を足した。
後の c10-r2000 の割り当ては 2,178,142,600 バイトで、記録の表 1 の 2.179 GB と同じである。
計算機は記録と同じ（Apple M1 Max、メモリ 64 GB）で、ほかのエージェントの作業が動いていた。
脚本と `.hp` はスクラッチパッドに置き、コミットしていない。

### 製品の設定での主の GC

`+RTS -S`（`-N -A64m`）で c10-r2000 を 2 回ずつ走らせた。
「時点」は開始からの経過で、終了時の GC（生きているデータ 0.2 MB）は除く。

| 実行ファイル | GC の回数 | 主の GC の時点と生きているデータ | maximum residency |
| --- | --- | --- | --- |
| 前 1 回目 | 8 | 0.355 秒 37.4 MB | 37,424,968 |
| 前 2 回目 | 8 | 0.400 秒 37.4 MB | 37,421,616 |
| 後 1 回目 | 5 | 0.475 秒 82.5 MB、0.806 秒 50.1 MB | 82,528,920 |
| 後 2 回目 | 5 | 0.509 秒 82.3 MB、0.808 秒 84.1 MB | 84,091,720 |

### 表 A：生きているデータの山（`-hT -i0.01 -A1m`、MB）

| 入力 | 前 | 後 | 中央値の比 |
| --- | --- | --- | --- |
| c10-r2000 | 107.2、106.8、104.2 | 106.6、100.0、104.5 | 0.978 |
| c10-r4000 | 201.1、205.5、191.6 | 201.2、199.5、197.9 | 0.992 |
| c10-r8000 | 402.9 | 405.3 | 1.006（1 回） |

c10-r1000、c10-r10000、c8-r10000 は測っていない。

### 表 B：c10-r2000 の山の標本の内訳（`-hT`、1 回目、MB）

山は、前は開始から 2.24 秒（実行は 2.73 秒）、後は 1.12 秒（実行は 1.55 秒）の標本である。

| 型 | 前 | 後 |
| --- | --- | --- |
| `:`（リストの構成子） | 19.66 | 19.62 |
| THUNK | 17.90 | 17.83 |
| THUNK_2_0 | 13.20 | 13.08 |
| ARR_WORDS | 6.98 | 6.98 |
| `StructElem` | 2.46 | 2.46 |
| `GlyphUse` | 2.28 | 2.29 |
| `LineRec` | 1.87 | 1.84 |
| `Line` | 1.60 | 1.60 |

`-hi` のプロファイルも取ったが、`.hp` には info table の番地しか出ず、ソースの位置に引けなかった（eventlog を読む道具が手元にない）。

### `-A1m` の `-s` の値

`-A1m` で `-hT` を付けずに 3 回ずつ走らせた `-s` の最大常駐（MB）である。
主の GC の回数は、c10-r2000 で前 31 から 32、後 12、c10-r4000 で前 36 から 37、後 14 だった。

| 入力 | 前 | 後 |
| --- | --- | --- |
| c10-r1000 | 55.0、53.2、54.3 | 56.2、56.0、56.2 |
| c10-r2000 | 82.0、81.3、82.3 | 85.9、85.9、87.3 |
| c10-r4000 | 192.0、158.3、188.6 | 154.5、161.7、156.2 |

c10-r2000 の値は前も後も表 A の山（100 MB 以上）に届かない。
`-A1m` にしても、`-hT` なしの `-s` の値は山を測れない。

### 表を組む途中の小さな山

後の c10-r2000 の 1 回目では、表を組む途中（約 0.53 秒）に 62.3 MB の小さな山があり、前の同じ段階の 37 から 39.5 MB より高い。
描画の山（104 MB 以上）より低いので、この測定の最大値は変わらない。
並列に組む表の行が同時に生きる量が変わったためと見込むが、確かめていない（未確認）。

## 決めたことの記録

2026-11-11 に、tett23 が提案中の Golem ADR 0306 から 0309 について、次のとおり指示した。

> 提案のADRをマージしてサブエージェントで実装

この指示により、この ADR の推奨案を採択し、実装を別のプルリクエストで進める。
最大常駐の条件はヒープのプロファイルで確かめ、中央値の比の上限を 1.05 とする。
以後の ADR で最大常駐を条件にするときも、この測り方を使う。
共通の測定手順を置く場所は、別のプルリクエストで整える。

## 参考文献

- [docs/benchmarks/2026-11-10-force-a-composed-table-without-show.md](../benchmarks/2026-11-10-force-a-composed-table-without-show.md)
- [docs/benchmarks/2026-11-10-cost-of-tables-within-the-cell-limit.md](../benchmarks/2026-11-10-cost-of-tables-within-the-cell-limit.md)
- [docs/benchmarks/2026-11-09-link-golem-with-a-64-mb-allocation-area.md](../benchmarks/2026-11-09-link-golem-with-a-64-mb-allocation-area.md)
- [ADR 0251](0251-reuse-the-compositions-of-unchanged-units-between-fixpoint-rounds.md)、[ADR 0252](0252-draw-and-serialise-the-pages-of-the-pdf-in-parallel.md)、[ADR 0253](0253-memoise-run-shaping-and-shorten-the-memo-key.md)、[ADR 0255](0255-record-what-implementations-decided-on-2026-11-09.md)、[ADR 0299](0299-force-a-composed-table-without-turning-it-into-a-string.md)
- [`modules/golem-typeset/src/Golem/Typeset/Flow.hs`](https://github.com/tett23/golem/blob/2e074342c2a5473016bec162c79b0c9c6224a560/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L2561-L2571)、[`modules/golem-cli/golem-cli.cabal`](https://github.com/tett23/golem/blob/2e074342c2a5473016bec162c79b0c9c6224a560/modules/golem-cli/golem-cli.cabal#L18)
- GHC User's Guide 9.10, "Running a compiled program"（`+RTS -s`、`-S`、`-A`）。https://downloads.haskell.org/ghc/9.10.3/docs/users_guide/runtime_control.html
- GHC User's Guide 9.10, "Profiling"（`-hT`、`-hi`、`-i`）。https://downloads.haskell.org/ghc/9.10.3/docs/users_guide/profiling.html
