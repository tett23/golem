# セルの上限の内側の表の費用（2026-11-10）

[docs/adr/0290](../adr/0290-keep-the-cost-of-a-table-within-the-cell-limit-and-measure-where-it-goes.md) の実装のプルリクエストで、一字のセルを 10 列に並べた表を 10,000 から 100,000 セルまで組み、常駐、割り当て、時間を測った記録である。
100,000 セルの表では、プロファイルを取るビルドで割り当てと時間の内訳と、ヒープの内訳も取った。
コミットした後は変更しない。

## 結論

- 割り当てはセルの数に比例する。1 セルあたり 229 KB から 233 KB で、二倍ごとの増え方の指数は 0.985 から 0.999 である。
- [2026-11-09 の監査](../audits/2026-11-09-security-audit.md) の表の「80,000 セルで割り当て 8 GB」は、転記の誤りである。同じ監査の [実行記録](../audits/2026-11-09-evidence/table-recheck.txt) には `19,235,065,616 bytes allocated` とある。80,000 セルから 100,000 セルへの割り当ての増え方（19.2 GB から 23.9 GB）は、セルの数の増え方（25%）と同じである。[ADR 0290](../adr/0290-keep-the-cost-of-a-table-within-the-cell-limit-and-measure-where-it-goes.md) の文脈の「約 3 倍」は、この誤りから来ている。
- 割り当ての 54% と CPU 時間の 25% は、組んだ表を評価しきるために表を `show` で文字列にし、その長さを数える一行（[`Flow.hs#L3143`](https://github.com/tett23/golem/blob/aa95669d5ab497fea5c2e48a4db78f8abd88c08d/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L3143)）に使われる。文字列は捨てるだけで、出力には使われない。
- 改ページの探索（`paginateWithin`）は割り当ての 0.1% で、改ページの固定点は一周で終わる。セルの数より速く増える費用は見つからなかった。

[ADR 0290](../adr/0290-keep-the-cost-of-a-table-within-the-cell-limit-and-measure-where-it-goes.md) の「実装すること」の 4 は、割り当てがセルの数の 1 乗より速く増えるときに roadmap に項目を足すとしている。
速く増えてはいないので、項目は足さない。

## 環境

- 計算機：Apple M1 Max（10 コア、性能コア 8 と効率コア 2）、メモリ 64GB、macOS 27.0。
- コミット：`origin/main` の `aa95669d`（[ADR 0290](../adr/0290-keep-the-cost-of-a-table-within-the-cell-limit-and-measure-where-it-goes.md) を採択したプルリクエストのマージ）。
- GHC 9.10.3、cabal 3.18.1.0、最適化は cabal の既定（`-O1`）。
- 実行ファイル：`modules/golem-cli/app/Main.hs` を、作業ツリーの `cabal.project.local` に `package golem-cli` の `ghc-options: -rtsopts` を足してリンクし直したもの（以下 `golem-rtsopts`）。`-with-rtsopts` は製品と同じ `-N -A64m` である。製品のビルド設定には `-rtsopts` を入れていない。
- 監査の `golem-rtsopts` は、[docs/adr/0249](../adr/0249-link-golem-with-a-64-mb-allocation-area.md) より前の `-with-rtsopts=-N` でリンクされていた。監査と比べるために、各回で `+RTS -A4m -RTS`（GHC の既定の nursery）を付けたビルドも測った。下の表では、前者を「製品の設定」、後者を「監査の設定」と呼ぶ。
- プロファイルを取るビルド：別の build ディレクトリで `cabal build exe:golem --disable-tests --enable-profiling --profiling-detail=late --builddir=dist-prof` とした。`late` は最適化の後にトップレベルの関数ごとにコストセンターを置くので、最適化の結果をほとんど変えない。製品のビルド設定は変えていない。

## 方法

入力は監査の [`make-fixtures.sh`](../audits/2026-11-09-evidence/make-fixtures.sh) と同じ形で作った（[`make-tables.sh`](2026-11-10-cost-of-tables-within-the-cell-limit/make-tables.sh)）。
`golem-driver` の fixture の `kanikosen` を写し、本文を `@table data/t.csv` の一つの表と「本文。」にした。
CSV のセルはすべて `x` の一字である。
CSV の一行めは見出しの行で、セルの数は見出しの行のセルを含む（[ADR 0224](../adr/0224-limit-the-cells-of-a-table-set-in-pdf.md) の数え方）。

| 入力 | 列 | CSV の行 | セル |
| --- | --- | --- | --- |
| c10-r1000 | 10 | 1,000 | 10,000 |
| c10-r2000 | 10 | 2,000 | 20,000 |
| c10-r4000 | 10 | 4,000 | 40,000 |
| c10-r8000 | 10 | 8,000 | 80,000 |
| c10-r10000 | 10 | 10,000 | 100,000 |
| c8-r10000 | 8 | 10,000 | 80,000 |

c8-r10000 は、監査の 80,000 セルと同じ形（10,000 行 8 列）である。
[ADR 0290](../adr/0290-keep-the-cost-of-a-table-within-the-cell-limit-and-measure-where-it-goes.md) の大きさの列（10 列）の 80,000 セルは c10-r8000 である。

一回ごとに `build/` を消し、`golem-rtsopts build --target pdf +RTS -s<ファイル> -RTS` を実行した（[`measure.sh`](2026-11-10-cost-of-tables-within-the-cell-limit/measure.sh)）。
一周で六つの入力を順に、それぞれ製品の設定と監査の設定で一回ずつ走らせ、これを 10 周した。
各回の始めに `uptime` の load average（1 分）を記録した。
同じ計算機で別のエージェントのビルドと計測が動いていて、120 回の load average は 39.3 から 202.6、中央値は 122.7 だった。
割り当ての量は負荷に依らない（10 回の幅は 0.1% 以内）が、時間は負荷で 2 倍から 4 倍揺れる。
下の表の値は 10 回の中央値（[`medians.sh`](2026-11-10-cost-of-tables-within-the-cell-limit/medians.sh)）で、各回の値は [`results-1.txt`](2026-11-10-cost-of-tables-within-the-cell-limit/results-1.txt)（1 周めから 5 周め）と [`results-2.txt`](2026-11-10-cost-of-tables-within-the-cell-limit/results-2.txt)（6 周めから 10 周め、周の番号は 1 から振り直した）にある。
中央値と幅は [`medians.txt`](2026-11-10-cost-of-tables-within-the-cell-limit/medians.txt) にある。

すべての回が終了コード 0 で終わった。
出力は、`build/` の下のすべてのファイルの SHA-256 と標準出力と標準エラー出力をまとめたハッシュで比べた。
どの入力でも、20 回（二つの設定の 10 回ずつ）のハッシュは一つだった。

## 表 1：製品の設定（`-N -A64m`）

割り当てと最大常駐は `+RTS -s` の「bytes allocated in the heap」と「maximum residency」、メモリは「total memory in use」、CPU は「Total time」、壁時計はコマンドの前後の時刻の差である。

| 入力 | セル | 割り当て（GB） | 1 セルあたり（KB） | 最大常駐（MB） | メモリ（MiB） | CPU（秒） | 壁時計（秒） | load average |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| c10-r1000 | 10,000 | 2.33 | 233.2 | 23 | 814 | 0.79 | 0.83 | 122.9 |
| c10-r2000 | 20,000 | 4.62 | 230.9 | 37 | 913 | 1.56 | 1.35 | 117.2 |
| c10-r4000 | 40,000 | 9.19 | 229.8 | 135 | 974 | 3.12 | 3.04 | 120.3 |
| c10-r8000 | 80,000 | 18.35 | 229.3 | 264 | 1465 | 6.25 | 7.85 | 123.1 |
| c10-r10000 | 100,000 | 22.92 | 229.2 | 347 | 1580 | 8.38 | 8.00 | 108.4 |
| c8-r10000 | 80,000 | 18.43 | 230.3 | 259 | 1450 | 6.53 | 8.21 | 102.3 |

c10 の隣り合う大きさのあいだの増え方を、セルの数の何乗かで書くと次のとおりである。

| 区間 | 割り当て | 最大常駐 | CPU |
| --- | --- | --- | --- |
| 10,000 から 20,000 | 0.985 | 0.67 | 0.99 |
| 20,000 から 40,000 | 0.993 | 1.87 | 1.00 |
| 40,000 から 80,000 | 0.997 | 0.96 | 1.00 |
| 80,000 から 100,000 | 0.999 | 1.23 | 1.43 |

割り当ては 1 乗である。
1 セルあたりの割り当ては、大きくなるほどわずかに減る（固定の費用が割られるため）。
同じ 80,000 セルの c10-r8000 と c8-r10000 の割り当ては 0.4% しか違わず、費用は行の数ではなくセルの数で決まる。

最大常駐の指数が揺れるのは、`+RTS -s` の最大常駐が主要な GC のときにしか測られないからである。
`-A64m` の 10 個の capability では nursery が 640MB あり、主要な GC が少ない（10,000 セルでは 2 回）。
常駐の増え方は、下の表 3 のヒープのプロファイルで見る。
最後の区間の CPU の指数は負荷の揺れで、10 回の幅（80,000 セルで 5.6 秒から 11.6 秒、100,000 セルで 7.6 秒から 12.4 秒）の中にある。

## 表 2：監査の設定（`-N -A4m`）と監査の値

| 入力 | セル | 割り当て（GB） | 最大常駐（MB） | メモリ（MiB） | CPU（秒） | 壁時計（秒） | 監査の値 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| c10-r1000 | 10,000 | 2.33 | 43 | 166 | 1.18 | 1.30 | 測っていない |
| c10-r2000 | 20,000 | 4.62 | 84 | 272 | 2.26 | 2.36 | 測っていない |
| c10-r4000 | 40,000 | 9.20 | 167 | 485 | 4.66 | 6.45 | 測っていない |
| c10-r8000 | 80,000 | 18.36 | 318 | 901 | 9.41 | 11.38 | 測っていない |
| c10-r10000 | 100,000 | 22.94 | 441 | 1161 | 11.46 | 17.38 | 23.9 GB、402 MB、CPU 9.7 秒 |
| c8-r10000 | 80,000 | 18.44 | 349 | 966 | 9.82 | 13.21 | 19.2 GB、330 MB、CPU 8.0 秒 |

監査の値は [実行記録](../audits/2026-11-09-evidence/table-recheck.txt) の `+RTS -s` の値である。
二点とも同じ桁で再現した。
割り当ては監査より 4% 少なく、最大常駐は 6% から 10% 多い。
割り当ての差は、監査のコミット（`94b976e1`）から `aa95669d` までのコードの変化と見るが、確かめていない。
最大常駐の差は、上に書いた主要な GC の時刻の違いの範囲である。
CPU 時間は負荷の重いこの計測のほうが長い。

## 表 3：100,000 セルの割り当てと時間の内訳

プロファイルを取るビルドで、c10-r10000 を `+RTS -p -hc -i0.5 -RTS` で一回組んだ（[`profile-100000-cells.txt`](2026-11-10-cost-of-tables-within-the-cell-limit/profile-100000-cells.txt)、[`profile-100000-cells-rts.txt`](2026-11-10-cost-of-tables-within-the-cell-limit/profile-100000-cells-rts.txt)）。
開始のときの load average は 286.7 だった。
プロファイルの割り当ての合計は 22.6 GB（プロファイルの費用を除く）で、表 1 の 22.9 GB とほぼ同じである。
`%time` は 1 ミリ秒ごとの標本の割合で、負荷の影響を受ける。

呼び出しの木で、割り当ての 3% 以上を持つものを、子の費用を含む割合で挙げる。

| コストセンター | 呼ばれた回数 | 時間 | 割り当て | 何をしているか |
| --- | --- | --- | --- | --- |
| `$fShowSetCell1`（`Golem.Layout.Table`） | 99,990 | 24.7% | 54.0% | 組んだ表の各セルの導出された `Show`。`length (show (fmap fst r))` から呼ばれる |
| `$wcomposeInlinesTree`（`Golem.Layout.Japanese`） | 100,000 | 15.0% | 10.3% | 各セルの項目を作る |
| うち `exceptionPatterns`（`Golem.Layout.Hyphenation.Languages`） | 100,000 | 3.6% | 3.4% | ハイフネーションの例外の表を、セルごとに作る |
| `$wentryAt` と `$wdrawLineAt`（`Golem.Typeset.Draw`） | 104,756、100,000 | 14.7% | 12.7% | ページに行を描く |
| `$wserializePdf`（`Golem.Pdf.Writer`） | 1 | 6.7% | 5.3% | PDF のオブジェクトを書く |
| `$wdocumentObjectsWith`（`Golem.Pdf.Writer`） | 2 | 15.4% | 4.9% | PDF の文書のオブジェクトを作る |
| `softHyphenSites`（`Golem.Layout.Japanese`） | 100,002 | 2.9% | 3.1% | ソフトハイフンの診断のために、セルの構造をもう一度たどる |

`$fShowSetCell1` の下では、`Golem.Layout.Look` の `Look` の `showsPrec`（[`Look.hs#L187`](https://github.com/tett23/golem/blob/aa95669d5ab497fea5c2e48a4db78f8abd88c08d/modules/golem-layout/src/Golem/Layout/Look.hs#L187)）が単独で 17.6% を割り当てる。
`Golem.Layout.KnuthPlass` の型（`Line`、項目、`BoxContent` など）の `showsPrec` が合わせて 28.5%、`Golem.Syntax.Span` の `SrcSpan` が 1.9% である。
各セルの一行の各項目が、書体の名前、言語、ソースの位置まで文字列にされる。
1 セルあたりおよそ 122 KB が文字列のために割り当てられ、すぐに捨てられる。

10,000 セル（c10-r1000）でも同じプロファイルを取った（[`profile-10000-cells.txt`](2026-11-10-cost-of-tables-within-the-cell-limit/profile-10000-cells.txt)）。
`$fShowSetCell1` は時間の 25.2%、割り当ての 52.9% で、100,000 セルとほぼ同じ割合だった。
この費用もセルの数に比例する。

改ページは費用の行き先ではなかった。
`fixpoint1` と `flowLines4` は一回ずつしか呼ばれず、改ページの固定点は一周で終わった。
`paginateWithin` は割り当ての 0.1% である。

### 評価しきるための `show`

[`Flow.hs#L3143`](https://github.com/tett23/golem/blob/aa95669d5ab497fea5c2e48a4db78f8abd88c08d/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L3143) は、表の単位を `mapper`（並列の `mapConcurrently`）の中で組み、`evaluate (length (show (fmap fst r)))` で結果を評価しきる。
組版の仕事を並列のスレッドで済ませるための評価である（[golem-driver ADR 0002](../golem-driver/adr/0002-pdf-pipeline.md)）。
段落の単位は `forceComposed`（[`Flow.hs#L2522-L2523`](https://github.com/tett23/golem/blob/aa95669d5ab497fea5c2e48a4db78f8abd88c08d/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L2522-L2523)）で、各行の `lineRatio` だけを `show` する。
表は、セルの行の項目まで含めた `SetTable` 全体を `show` する。
この違いが、割り当ての半分を占める。

文字列を作らずに同じ部分を評価する方法（たとえば `forceComposed` と同じく各セルの各行の `lineRatio` を評価する）にすれば、割り当てはおよそ半分、CPU 時間はおよそ 4 分の 3 になると見込む。
評価する範囲が変わると、仕事の一部が並列のスレッドから描画の側に移りうるので、その確かめを含めて別の ADR で決める。
[ADR 0290](../adr/0290-keep-the-cost-of-a-table-within-the-cell-limit-and-measure-where-it-goes.md) の「実装しないこと」のとおり、この記録のプルリクエストでは変えていない。

`exceptionPatterns` がセルごとに呼ばれること（3.4%）も、表ごとに一度にできる可能性がある。
これも測っただけで、変えていない。

## 表 4：100,000 セルのヒープの内訳

同じ実行の `-hc` の標本である（[`heap-100000-cells.txt`](2026-11-10-cost-of-tables-within-the-cell-limit/heap-100000-cells.txt)）。
プロファイルの見出しの分を除いた、生きているデータの合計である。

| 時刻（秒） | 合計（MB） | 大きいもの |
| --- | --- | --- |
| 0.3 から 5.5 | 45 から 158 | セルの項目（`composeInlinesTree` 42MB、`wordItems` 29MB）、`breakParagraph` 22MB |
| 8.0 から 9.6 | 312 から 453 | 描画（`runAtSqueezed` 104MB、`drawLineAt` 80MB）、`renderPdf2` 40MB |
| 11.4 から 12.6 | 242 から 325 | PDF のオブジェクト（`documentObjectsWith` 41MB）、`drawLineAt` 34MB |

常駐の山は、セルを組む段ではなく、ページを描いて PDF に書く段にある。
`show` の文字列は作るそばから捨てられるので、常駐には現れない。
評価の `show` を変えても、最大常駐はほとんど下がらないと見込む。

## 使ったコマンド

```sh
# 測る golem（cabal.project.local に package golem-cli / ghc-options: -rtsopts）
cabal build exe:golem --disable-tests
# プロファイルを取る golem（別の build ディレクトリ）
cabal build exe:golem --disable-tests --enable-profiling --profiling-detail=late --builddir=dist-prof
# 入力
sh make-tables.sh <リポジトリ> <作業のディレクトリ>/fx
# 10 周（5 周を二回）
sh measure.sh 5 results-1.txt; sh measure.sh 5 results-2.txt
# 100,000 セルのプロファイル
cd fx/c10-r10000 && rm -rf build && golem-prof build --target pdf +RTS -p -hc -i0.5 -s<ファイル> -RTS
```

`measure.sh` は、実行ファイル `golem-rtsopts` と入力の `fx/` を、自分と同じディレクトリに置いて使う。
時刻は `perl` の `Time::HiRes` で取った。

## 限界

- 負荷を制御できなかった。load average の中央値は 122.7 で、時間の絶対値は静かな計算機より長い。割り当ての量は負荷に依らない。
- `-rtsopts` を付けた実行ファイルで測った。`-rtsopts` は RTS のオプションの受け付けだけを変え、GC の動きは変えない。
- プロファイルは一回ずつである。割り当ての割合は 10,000 セルと 100,000 セルで 1 ポイントしか違わないが、時間の割合は負荷の影響を受ける。
- 入力は一字のセルだけである。長い文のセルや、注、ルビ、索引の印を持つセルの費用は測っていない。
