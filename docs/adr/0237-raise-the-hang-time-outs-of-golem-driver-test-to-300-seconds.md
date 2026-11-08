# ADR 0237: golem-driver-test の止まりの検出の時間切れを 300 秒にする

ステータス: 採択（未実装）

## 文脈

### 落ちて、再実行で通ったスイート

2026-11-08 に、手元の `cabal test golem-driver:test:golem-driver-test` が、1137 から 1152 のテストのうち 2 つか 3 つで落ちた。
落ちたのは、ほかの cabal のビルドとテストを同時に走らせていたときで、走らせ直すと通った。
出力は末尾しか残しておらず、落ちたテストの名前はわからなかった。
残った出力の末尾を集めると、この日に四回落ちている（13:26 に 1137 のうち 2、13:28 に 1139 のうち 2、21:23 に 1152 のうち 2、21:31 に 1150 のうち 3）。
CI では一度も落ちていない。

一度めの後、もう一度起きたら調べることにしていた。
候補の一つは、golem-emet-test を一つずつ走らせることにした aarch64 の GHC の runtime の不具合（[ADR 0207](0207-run-golem-emet-test-one-test-at-a-time-under-the-watchdog.md)、GHC #28001）だった。

### 再現

測った環境は、Apple silicon の 10 コア、64 GB のメモリの macOS で、GHC 9.10.3、origin/main の 143b57e5 である。
qpdf を入れていないので、1 つのテストが SKIP になる。
同じマシンでは、ほかの作業のセッションも動いていた。

スイートを一度だけビルドし、テストの実行ファイルを `modules/golem-driver` から直に走らせた。
単独で走らせると、1152 のテストは 118.32 秒で通った。
最大の常駐は 3.6 GB である。

次に、同じ実行ファイルを四つ同時に走らせた。
四つとも、1152 のうち 2 つで落ちた。
落ちたのは四つとも同じ二つのテストで、どちらも tasty の時間切れである。

```
T1, T2: a table of 10,000 rows of 256 cells is G07108 alone, without composing its cells: TIMEOUT (30.06s)
  Timed out after 30s
T4: a table of N + 1 cells from a CSV, a TSV, a | table of .gm and Block.table of Emet is the same G07108: TIMEOUT (30.02s)
  Timed out after 30s
```

二つのテストは、[ADR 0224](0224-limit-the-cells-of-a-table-set-in-pdf.md) が足した表のセルの上限のテスト（[`cellLimitTests`](https://github.com/tett23/golem/blob/143b57e508fd29e37d3e33330974f6d92ba0e0ed/modules/golem-driver/test/TableFilesSpec.hs#L159-L217)）にある。
このテストの群は、6 つのテストのすべてに 30 秒の時間切れを付けている。
落ちた時刻も合う。
[ADR 0224](0224-limit-the-cells-of-a-table-set-in-pdf.md) の実装は 2026-11-08 の 11:33 にマージされ、手元で落ちた四回はどれもその後である。

### テストの所要時間

この群の 6 つのテストの所要時間を、走らせ方ごとに比べる。
「群だけ」は `-p '/the cells of a table set in PDF/' -j1` で、この群のテストを一つずつ走らせたものである。

| テスト | 群だけ | スイート、単独 | スイート、四つ同時 | スイート、六つ同時（時間切れ 300 秒） |
| --- | --- | --- | --- | --- |
| T1、T2（10,000 行 256 セル） | 3.00 秒 | 14.80 秒 | 時間切れ（4 回とも） | 51.22〜54.93 秒 |
| T1、T3 | 1.43 秒 | 12.56 秒 | 19.14〜20.74 秒 | 29.21〜34.17 秒 |
| T1（空のセルの見出し行） | 0.77 秒 | 2.67 秒 | 10.14〜11.66 秒 | 13.93〜15.87 秒 |
| T4（四つの源の N + 1） | 3.21 秒 | 15.75 秒 | 時間切れ（4 回とも） | 48.76〜52.34 秒 |
| T5 | 0.24 秒 | 0.87 秒 | 2.43〜3.69 秒 | 3.34〜4.97 秒 |
| T6 | 0.21 秒 | 0.78 秒 | 2.74〜3.45 秒 | 3.42〜4.26 秒 |

群だけでは、どのテストも 30 秒の 1/9 に収まる。
スイートの中では、ほかのテストと同時に走るので、単独のスイートでも約 5 倍に延びる。
golem-driver-test は `-threaded` と `-N` でリンクされ、tasty がテストを同時に走らせる（[ADR 0146](0146-threaded-golem-driver-test.md)）。
ほかのプロセスが CPU を取ると、さらに延び、四つ同時で 30 秒を超えた。
六つ同時の列は、時間切れを試しに 300 秒に変えた実行ファイルで測った（この変更は確かめのためだけで、コミットしていない）。
六つとも、1152 のテストがすべて通った。
同じ実行ファイルを四つ同時に二回ずつ走らせた 8 回も、すべて通った。

群だけで走らせたときの割り当ては 14.7 GB、最大の常駐は 530 MB で、時間の 4 割ほどが GC だった。
スイートの中で 5 倍に延びる分に、`-N` の capability がそろって止まる GC の同期がどれだけ寄与しているかは確かめていない。
`-qg` などの RTS のオプションを試そうとしたが、この実行ファイルは `-rtsopts` なしでリンクされており、受け付けなかった。

### GHC の runtime の不具合ではない

落ちたプロセスは止まっていない。
時間切れは 30.00〜30.08 秒で働き、その後もほかのテストが走り続け、プロセスは失敗の数を書いて終わった。
[ADR 0207](0207-run-golem-emet-test-one-test-at-a-time-under-the-watchdog.md) の止まりでは、Haskell のスレッドがすべて動かなくなり、tasty の時間切れも働かない。
今回は、tasty の時間切れが働いたこと自体が、runtime が動いていたことを示す。
一時ディレクトリの共有も原因ではない。
この群のテストは、どれも `withSystemTempDirectory` が作る別々のディレクトリに書く。

### 30 秒の時間切れが見ているもの

[ADR 0073](0073-time-bounds-in-tests.md) は、テストの時間切れを止まらないことの検出に限り、値を 30 秒にそろえた。
しかし、この群のコメントは、時間切れが「表のセルを組んでから拒んだこと」を見つけるとしている（[TableFilesSpec.hs](https://github.com/tett23/golem/blob/143b57e508fd29e37d3e33330974f6d92ba0e0ed/modules/golem-driver/test/TableFilesSpec.hs#L167-L168)）。
[ADR 0224](0224-limit-the-cells-of-a-table-set-in-pdf.md) のテスト設計も、T2 と T3 に「30 秒の時間切れの中で終わること」を書いている。

その働きは、30 秒の時間切れには任せられない。
T3 の前半は、ちょうど N（100,000）のセルを組んで G07041 になる表であり、群だけで走らせた T3 は全体で 1.43 秒で終わる。
N + 1 のセルを拒まずに組む誤りがあっても、組むセルの数はほぼ同じなので、かかる時間もこれと同じ程度と見込まれ、30 秒には届かない（この誤りを入れて測ってはいない）。
T3 と T4 で組んでいないことを示しているのは、G07108 だけが出るという diagnostic の断言である。
組むと 57 秒かかる T2 の表（監査の T-01）も、組んだことは割り当ての上限（8 GiB、組んだときは 96 GB、[ADR 0236](0236-record-what-implementations-decided-found-by-the-second-review-of-2026-11-08.md)）と G07041 が出ないことの断言で見つかる。
どちらも、マシンの混み具合によらず同じ結果になる。

時間切れに残る働きは、[ADR 0073](0073-time-bounds-in-tests.md) のとおり、止まらない実装をテストごとに止めることだけである。
そのための値が、正しいテストを混んだマシンで落とすほど短い。

### ほかの時間切れ

golem-driver-test の時間切れは、ほかに二つある。
TableFilesSpec の「a large table is G02088, and the text build ends」（[L139-L144](https://github.com/tett23/golem/blob/143b57e508fd29e37d3e33330974f6d92ba0e0ed/modules/golem-driver/test/TableFilesSpec.hs#L139-L144)）と、SecuritySpec の「a year of 1e1000000000 in CSL-JSON does not stop the build」（[L130](https://github.com/tett23/golem/blob/143b57e508fd29e37d3e33330974f6d92ba0e0ed/modules/golem-driver/test/SecuritySpec.hs#L130)）である。
四つ同時の下でも、それぞれ 0.63 秒と 0.04 秒で終わり、落ちていない。
同じスイートの中で、時間切れの値が二つあると、どちらの規則で書くかをテストを足すたびに決めることになる。

### CPU 時間で測れない理由

golem-pdf と golem-svg では、時間の上限をプロセスの CPU 時間と実時間の二つで測る（[ADR 0091](0091-cpu-time-limits-in-pdf-and-svg-tests.md)）。
その補助 `withinTimeLimits` は、threaded の RTS では動作を始めずに失敗する。
threaded の RTS では、プロセスの CPU 時間がほかのテストの分も含むからである。
[ADR 0091](0091-cpu-time-limits-in-pdf-and-svg-tests.md) は、golem-driver の TableFilesSpec をこの理由で外し、「時間切れの失敗を観測していない」と書いた。
今回、その失敗を観測した。

## 実装すること

### 時間切れの値

- golem-driver-test の `Support.hs` に、止まりの検出の時間切れ `hangTimeout :: Timeout` を置く。値は実時間の 300 秒である。値はここ一か所に置き、テストには書かない。
- golem-driver-test の `mkTimeout` の 8 箇所（TableFilesSpec の 7、SecuritySpec の 1）を、すべて `localOption hangTimeout` に置き換える。
- `cellLimitTests` の時間切れのコメントを、止まらない実装の検出だけを書く文に改める。組んでから拒んだことは、diagnostics と割り当ての断言が見つけると書く。
- 断言は変えない。T2 の割り当ての上限（8 GiB）も変えない。

300 秒は、次のように決めた。

- 文脈の測定で最も重い負荷（六つ同時）の下で、最も長くかかったテストは 54.93 秒だった。300 秒はその 5.5 倍で、群だけで走らせたときの 3.21 秒の 93 倍である。
- [ADR 0091](0091-cpu-time-limits-in-pdf-and-svg-tests.md) の実時間の上限と、[ADR 0207](0207-run-golem-emet-test-one-test-at-a-time-under-the-watchdog.md) の見張りの上限も 300 秒である。リポジトリの中の、止まりを見る実時間の上限が一つの値にそろう。
- CI のスイートの時間切れ（[suite-timeout.sh](https://github.com/tett23/golem/blob/143b57e508fd29e37d3e33330974f6d92ba0e0ed/scripts/ci/suite-timeout.sh#L11)、600 秒）より短い。

### 検査

- `scripts/ci/test.sh` の golem-driver のスイートの節（[ADR 0146](0146-threaded-golem-driver-test.md) の検査の隣）に、golem-driver-test のモジュールのうち `Support.hs` の外に `mkTimeout` がないことの検査を足す。値を一か所に置くことを、テストを足す人の注意に任せない。

### 文書

- `CONTRIBUTING.md` のテストの節に、次を書く。golem-driver-test のテストでは、時間の上限に `Support.hs` の `hangTimeout`（実時間の 300 秒）を使う。テストは threaded の RTS で同時に走るので、CPU 時間では測らない（この ADR へのリンク）。[ADR 0073](0073-time-bounds-in-tests.md) の 30 秒の一文は、golem-pdf、golem-svg、golem-driver の外のテストの規則として残す。
- [ADR 0073](0073-time-bounds-in-tests.md) のステータスの行の末尾に「、golem-driver-test の時間切れは [ADR 0237](0237-raise-the-hang-time-outs-of-golem-driver-test-to-300-seconds.md)」を足す。
- [ADR 0224](0224-limit-the-cells-of-a-table-set-in-pdf.md) のステータスの行を「採択→テストの時間切れの値は [ADR 0237](0237-raise-the-hang-time-outs-of-golem-driver-test-to-300-seconds.md)」に改める。
- 振る舞いは変わらないので、`docs/specifications.md` と README は変えない。

## 実装しないこと

- 製品のコードの変更。表のセルの上限とその diagnostic は、[ADR 0224](0224-limit-the-cells-of-a-table-set-in-pdf.md) のとおりである。
- 重いテストを一つずつ走らせること（tasty の `sequentialTestGroup` や `-j`）。スイートの中で延びる分は減る見込みがあるが、四つ同時の測定が示すとおり、時間はスイートの外のプロセスからも延びる。[ADR 0091](0091-cpu-time-limits-in-pdf-and-svg-tests.md) が cabal の並列の度合いを下げなかったのと同じ理由である。
- 表を小さくすること。T2 の表は監査の `proj-max` と同じ大きさであり、T4 の表は N + 1 のセルである。大きさはテストが確かめることそのものから決まる。
- T3 から T6 に割り当ての上限を足すこと。組んでいないことは、G07108 だけが出る断言で足りる。
- golem-driver-test の RTS のオプション（`-rtsopts`、`-qg`、`-N` の数）を変えること。GC の同期が延びをどれだけ左右するかは確かめておらず、確かめずに変える理由がない。
- golem-driver-global-test と golem-driver-parallel-test。今は時間切れを持たない。
- スイート全体の所要時間の上限（[ADR 0073](0073-time-bounds-in-tests.md) の実装しないこと、roadmap の v1.0.0 の項目）。

## 不変条件

なし。
この ADR は、テストの時間切れの値とその置き場所を決めるだけで、どの入力にも成り立つ性質を新しく決めない。
値を一か所に置くことは、テスト設計の静的な検査で確かめる。

## テスト設計

- `scripts/ci/test.sh` の検査を先に足し、今の golem-driver-test（TableFilesSpec と SecuritySpec に `mkTimeout 30000000` が 8 つある）で失敗することを確かめてから、時間切れを置き換える。
- 置き換えた後、文脈と同じ手順で確かめる。golem-driver-test を一度ビルドし、実行ファイルを `modules/golem-driver` から四つ同時に 2 回ずつ、六つ同時に 1 回走らせる。14 回とも、すべてのテストが通ること。結果はプルリクエストの説明に書く。
- 時間切れが止まらない実装を今も止めることを、一度だけ手で確かめる。`cellLimitTests` の一つのテストの本体を `forever (threadDelay 1000000)` に変え、そのテストが 300 秒で `TIMEOUT` になり、スイートが失敗で終わること。この変更はコミットしない。

## トレードオフ

- 止まらない実装が見つかるまでの時間が、テストごとに 30 秒から 300 秒に延びる。止まったテストの名前が出るのは、スイートの始まりから最長で約 300 秒後になる。CI のスイートの時間切れ（600 秒）より先に働くので、名前は今も出る。
- 30 秒は、遅くなったことを見つける目安としても読めた。この ADR は、その読み方を捨てる。性能は `docs/benchmarks/` で測るもので、時間切れで見るものではない（[ADR 0073](0073-time-bounds-in-tests.md)）。T2 については、組んだかどうかを割り当ての上限が見る。
- 300 秒でも、マシンがさらに混めば届きうる。文脈の測定では、最も重い負荷でも 300 秒の 1/5 に収まった。ただし、[ADR 0091](0091-cpu-time-limits-in-pdf-and-svg-tests.md) のレーンでは、スイートが単独のときの約 19 倍に延びた。T4 がスイートの単独の 15.75 秒から同じだけ延びると、約 300 秒になる。届いたときは、[ADR 0091](0091-cpu-time-limits-in-pdf-and-svg-tests.md) のように CPU 時間で測れないかを、threaded の RTS のスレッドごとの CPU 時間の取り方から調べ直す。
- 時間切れの値が golem-driver-test とほかのスイートで違う。ほかのスイートは 30 秒、golem-pdf と golem-svg は CPU 時間の 60 秒と実時間の 300 秒である。規則が三つになるが、それぞれの値の理由はスイートの RTS とテストの重さから来ている。

## メンテナーが決めること

### 1. 置き換える範囲（推奨：golem-driver-test の 8 箇所すべて）

落ちたのは `cellLimitTests` の 2 つだけで、ほかの時間切れは 1 秒にも届かない。
`cellLimitTests` の 6 つだけを 300 秒にする案もある。
推奨は 8 箇所すべてである。
同じスイートに二つの値があると、テストを足すたびにどちらで書くかを決めることになり、`scripts/ci/test.sh` の検査も一つの値を前提にできない。

### 2. 値（推奨：300 秒）

文脈の測定は、最も重い負荷でも 54.93 秒だった。
120 秒でも今の測定には収まる。
しかし、[ADR 0091](0091-cpu-time-limits-in-pdf-and-svg-tests.md) のレーンが観測した、スイートの単独の約 19 倍の延びには、120 秒では届く（T4 の 15.75 秒の 19 倍は約 300 秒）。
300 秒は、その延びの境にあたり、リポジトリの中の止まりを見るほかの上限とも同じ値である。
これより長くすると、CI のスイートの時間切れ（600 秒）より先に働く余地が減る。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-08、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [tasty 1.5.4 の Run.hs](https://hackage.haskell.org/package/tasty-1.5.4/src/Test/Tasty/Run.hs)（`mkTimeout` が `System.Timeout.timeout` で実時間を測ること）
- [ADR 0073](0073-time-bounds-in-tests.md)、[ADR 0091](0091-cpu-time-limits-in-pdf-and-svg-tests.md)、[ADR 0146](0146-threaded-golem-driver-test.md)、[ADR 0207](0207-run-golem-emet-test-one-test-at-a-time-under-the-watchdog.md)、[ADR 0224](0224-limit-the-cells-of-a-table-set-in-pdf.md)、[ADR 0236](0236-record-what-implementations-decided-found-by-the-second-review-of-2026-11-08.md)
