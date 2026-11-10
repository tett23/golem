# 表を評価しきる変更のヒーププロファイル

この記録は、[Golem ADR 0306](../adr/0306-measure-the-residency-of-forcing-a-table-by-heap-profiles.md) に従い、[Golem ADR 0299](../adr/0299-force-a-composed-table-without-turning-it-into-a-string.md) の最大常駐の条件を測り直した結果を残す。
前は `ff5d9b118f3aa1910bfa763a27f52e30ce736a85`、後は `2e074342c2a5473016bec162c79b0c9c6224a560` の実行ファイルである。
両方とも GHC 9.10.3 を使い、製品の `-N -A64m` に `-rtsopts` を足してビルドした。
Wasmtime は、両コミットが固定する 49.0.5 の C API を使った。

## 測り方

表の六つの入力は、[make-tables.sh](2026-11-10-cost-of-tables-within-the-cell-limit/make-tables.sh) で作る。
各入力で前と後を交互に三回ずつ、[`measure-heap.sh`](2026-11-11-force-table-heap-profiles/measure-heap.sh) で走らせる。
コマンドには `+RTS -hT -i0.01 -A1m -s -RTS` を与え、ヒープのプロファイルと RTS の統計を回ごとに保存する。
[`peak.sh`](2026-11-11-force-table-heap-profiles/peak.sh) は、`.hp` の標本ごとのバイト数を合計し、その最大と最大の標本の型別内訳を出す。
入力ごとに三回の山の中央値を取り、後と前の比が 1.05 以下かを確かめる。
各回の割り当てが[前の記録](2026-11-10-force-a-composed-table-without-show.md)の表 1 の値から 1% 以内であり、前後の `build/` のハッシュが一致することも確かめる。
`build/` にある各ファイルの SHA-256 と標準出力をまとめ、入力ごとのハッシュを計算する。

二つのコミットを別々にチェックアウトし、それぞれ `cabal.project.local` の `package golem-cli` に `ghc-options: -rtsopts` を指定した。
実行ファイルは `cabal build golem-cli:exe:golem --offline -j4` で作った。
入力の作成と全回の測定には次を使う。

```sh
sh docs/benchmarks/2026-11-10-cost-of-tables-within-the-cell-limit/make-tables.sh AFTER-CHECKOUT FIXTURES
sh docs/benchmarks/2026-11-11-force-table-heap-profiles/measure-heap.sh BEFORE-GOLEM AFTER-GOLEM FIXTURES EMPTY-OUT
```

今回の実行は、最初の 6 回を終えたところで実行環境のセッションが閉じた。
完了した 6 回の `results.tsv` と `.hp`・RTS 統計を照合して残し、途中だった c10-r8000 の前の回だけを消した。
作業用の再開スクリプトは、結果に終了値 0 の行と保存済みの `.hp`・RTS 統計がある回を飛ばし、同じ測定ループで残りの 30 回を実行した。
新しい空の出力先で実行するときは、上の `measure-heap.sh` 一つで 36 回を通して測れる。

## 結果

36 回とも終了値は 0 だった。
各入力の 6 回で出力ハッシュは同じだった。
割り当ての、前の記録の表 1 の値からの差は、最大で 0.103%（c10-r1000、後の 2 回目）だった。
したがって、割り当てと出力の検査に通った。

山の値は十進 MB で、各欄の順序は 1 回目、2 回目、3 回目である。
比はバイト単位の中央値から計算した。

| 入力 | 前の山（MB） | 後の山（MB） | 中央値の比（後/前） |
| --- | --- | --- | ---: |
| c10-r1000 | 50.844、53.036、55.468 | 50.905、42.241、55.106 | 0.960 |
| c10-r2000 | 83.459、101.983、102.321 | 104.180、102.610、103.820 | 1.018 |
| c10-r4000 | 197.994、196.877、201.667 | 196.544、200.685、196.598 | 0.993 |
| c10-r8000 | 395.474、393.016、391.707 | 383.289、385.692、395.233 | 0.981 |
| c10-r10000 | 482.899、493.200、479.446 | 485.699、476.545、490.425 | 1.006 |
| c8-r10000 | 387.806、397.808、386.641 | 391.256、392.972、396.305 | 1.013 |

すべての入力で、[Golem ADR 0306](../adr/0306-measure-the-residency-of-forcing-a-table-by-heap-profiles.md) の上限 1.05 以下だった。
次の表は、各入力の中央値に当たる回の、山の標本に多かった型である。
値は十進 MB で、同じ型の前と後を示す。型の全内訳は各回の `types.tsv` に残した。

| 入力 | 型 | 前 | 後 |
| --- | --- | ---: | ---: |
| c10-r1000 | `ghc-prim:GHC.Types.:` | 10.017 | 9.807 |
| c10-r1000 | `THUNK` | 8.464 | 8.148 |
| c10-r1000 | `ARR_WORDS` | 6.691 | 6.691 |
| c10-r2000 | `ghc-prim:GHC.Types.:` | 19.236 | 19.586 |
| c10-r2000 | `THUNK` | 17.565 | 17.781 |
| c10-r2000 | `THUNK_2_0` | 13.067 | 12.995 |
| c10-r4000 | `ghc-prim:GHC.Types.:` | 37.968 | 37.193 |
| c10-r4000 | `THUNK` | 35.249 | 35.881 |
| c10-r4000 | `THUNK_2_0` | 25.582 | 26.660 |
| c10-r8000 | `ghc-prim:GHC.Types.:` | 75.388 | 73.948 |
| c10-r8000 | `THUNK` | 71.185 | 71.579 |
| c10-r8000 | `THUNK_2_0` | 52.443 | 53.250 |
| c10-r10000 | `ghc-prim:GHC.Types.:` | 93.339 | 93.665 |
| c10-r10000 | `THUNK` | 87.996 | 88.490 |
| c10-r10000 | `THUNK_2_0` | 63.923 | 64.761 |
| c8-r10000 | `ghc-prim:GHC.Types.:` | 73.651 | 75.585 |
| c8-r10000 | `THUNK` | 71.977 | 71.032 |
| c8-r10000 | `THUNK_2_0` | 53.477 | 51.837 |

[Golem ADR 0306](../adr/0306-measure-the-residency-of-forcing-a-table-by-heap-profiles.md) の `peak.sh` の検査では、c10-r2000 の 6 回のうち、同じ実行の `-s` との差の最大は 0.020% だった。
ほかの入力では、c10-r1000 の後の 2 回目に、`.hp` の山 42,241,296 バイトと `-s` の最大常駐 43,287,304 バイトの差（2.416%）があった。
独立に `.hp` の 19 標本の各値を足しても最大は 42,241,296 バイトだったため、`peak.sh` の集計誤りではない。
同じ実行の `-s` は世代 1 の GC を 23 回と記録している。
この差を、`.hp` の標本が GC の後の最大値を捉えなかったためと見るのは推測である。

各回のバイト単位の値とハッシュは [`results.tsv`](2026-11-11-force-table-heap-profiles/results.tsv) に、36 回分の `.hp`、`-s`、型の内訳、標準出力は [`profiles.tar.gz`](2026-11-11-force-table-heap-profiles/profiles.tar.gz) に保存した。
アーカイブの SHA-256 は `930e6057cd0fde376f12befac63b2970a5c20f680c490bf24dccd729205917d4` である。
