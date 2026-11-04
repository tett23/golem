# ADR 0117: golem-driver-parallel-test に、Haskell のランタイムの外で実時間を測る見張りを付ける

ステータス: 採択（未実装）

## 文脈

### 止まったスイート

2026-10-29 の 01:51 に、origin/main から作ったブランチ（縦組みの参照のページ番号を変えたもの。並列の処理には触れていない）で、`cabal test golem-layout golem-driver golem-project golem-html golem-text` を走らせた。
同じマシンでは、ほかのセッションも `cabal test` を走らせていた。
golem-driver-parallel-test は、CPU を使わないまま 14 分を超えて終わらなかった。
SIGTERM を送っても終わらず、SIGKILL で止めた。
同じスイートは、それまで 6 つのテストを 6.69 秒で通していた。
出力はパイプに流れて溜まっており、止める前には読めなかったので、どのテストで止まったかはわからない。

止まっているあいだに macOS の `sample` を 1 ミリ秒ごとに 842 回取った。
バイナリの UUID（2992F218-D40D-3A93-9A5F-329EDB26CB2D）は、そのブランチの worktree に残った golem-driver-parallel-test の UUID と一致する。
842 回とも、すべての OS スレッドが同じ場所にいた。

| スレッド | 数 | いた場所 |
| --- | --- | --- |
| メインスレッド | 1 | `waitCondition`（`__psynch_cvwait`） |
| ghc_ticker | 1 | `waitCondition` |
| ghc_worker | 22 | `waitCondition` |
| ghc_worker | 10 | Haskell のコードから呼んだ `kevent`（capability ごとの IO マネージャー） |
| ghc_worker | 1 | Haskell のコードから呼んだ `poll`（タイマーマネージャー） |

C のコードを走っているスレッドはない。
golem-font の関数のロック（`pthread_mutex_lock`）で待つスレッドもない（待てば `__psynch_mutexwait` が出る）。
つまり、走っている Haskell のスレッドも、終わらない外部の呼び出しもなく、すべてが何かを待っていた。

### この観測から言えること、言えないこと

止まった原因は、次の三つのどれかである。
`sample` は GHC のコードのフレームをたどれず（`thread_start` からいきなり `waitCondition` に飛ぶ）、三つを見分けられない。

1. ランタイムそのものが止まった。GC の同期が終わらない場合などである。2026-10-17 の `setNumCapabilities` の件（[scripts/ci/rts-capabilities.sh](https://github.com/tett23/golem/blob/95599786d1885df85520fb498d175c26904f94ab/scripts/ci/rts-capabilities.sh#L6-L16)）と同じ形の止まり方で、このときも SIGTERM では終わらない。ランタイムの中のシグナルの処理は Haskell のスレッドが行うからである。
2. Haskell のスレッドどうしが待ち合った。tasty は SIGTERM を受けると、走っているテストを `cancel` し、その終わりを待つ（tasty 1.5.4 の `Test.Tasty.Run` の `executeTest` は `withAsync` で、片付けは `uninterruptibleCancel`）。async の `concurrently'` も、子のスレッドの終わりを `uninterruptibleMask_` の中で待つ。止まったスレッドが終わらなければ、SIGTERM の片付けも終わらない。
3. テストはすべて終わり、プロセスが終わる途中で止まった。

次のものは、原因から外せる。

- `setNumCapabilities`：`modules/` のコードは呼ばない（rts-capabilities.sh が検査する）。tasty 1.5.4 は capability がスレッドの数より少ないときだけ呼び、`-N` のこのスイートでは呼ばない。hedgehog の `updateNumCapabilities` は `checkParallel` の経路だけで、tasty-hedgehog（`checkReport`）は通らない。
- golem-plugin の `unsafe` の呼び出し（[docs/roadmap.md](https://github.com/tett23/golem/blob/95599786d1885df85520fb498d175c26904f94ab/docs/roadmap.md#L83)）：このスイートの原稿と二つの本はプラグインを使わない。また、`unsafe` の呼び出しが capability を持ったままなら、そのスレッドは C の中にいるはずだが、いなかった。
- golem-font の `unsafe` の呼び出しとロック：上のとおり、C の中にもロックの待ちにもスレッドはない。

### 再現の試み

止まったバイナリと同じ origin/main（95599786）のバイナリを、`modules/golem-driver` で繰り返し走らせた。
1 回を 180〜600 秒で打ち切り、打ち切ったら `sample` を取って SIGTERM、5 秒後に SIGKILL を送るスクリプトを使った。
マシンには、ほかのセッションの負荷（load average 15〜60）が常にあった。

| 条件 | 同時に走らせた数 | 回数 | 止まった回数 | 1 回の時間 |
| --- | --- | --- | --- | --- |
| そのまま（`-N`、10 capability） | 4 | 100 | 0 | 10〜38 秒 |
| `+RTS -N20`、`GOLEM_RACE_TESTS=3` | 8 | 80 | 0 | 最長 105 秒 |
| `yes` を 16 個走らせた下で、そのまま | 4 | 60 | 0 | 24〜36 秒 |
| 同じ負荷の下で `+RTS -N2` | 4 | 60 | 0 | 28〜50 秒 |
| 同じ負荷の下で `+RTS -N32`、`GOLEM_RACE_TESTS=5` | 2 | 20 | 0 | 43〜73 秒 |
| 止まったバイナリそのもの（UUID が一致するもの） | 4 | 40 | 0 | 15〜18 秒 |

合わせて 360 回で、止まったのは 0 回である。
`-N` を 10 より大きくするために、2 行めから 5 行めは同じコードを `-rtsopts` でリンクし直したバイナリを使った。

止まりは再現しなかった。
原因を決められないので、原因を直す変更はできない。
次に止まったときに原因がわかり、しかも有限の時間で失敗として終わるようにする。

### 上限が働かなかった理由

- golem-driver-parallel-test には、時間の上限が一つもない。
- [ADR 0091](0091-cpu-time-limits-in-pdf-and-svg-tests.md) の `withinTimeLimits` は golem-pdf と golem-svg のテストのためのもので、threaded の RTS では動作を始めずに失敗する（プロセスの CPU 時間がほかのテストの分を含むから）。このスイートは `-threaded` である。
- tasty の `mkTimeout` は `System.Timeout.timeout` で、Haskell のスレッド（タイマーマネージャーと、例外を投げるスレッド）が動くことを前提にする。上の 1 では働かない。2 では、時間切れの後の `uninterruptibleCancel` が止まったスレッドを待ち続ける。3 では、テストがもう走っていない。
- CI は `scripts/ci/suite-timeout.sh` でスイートを 600 秒で止め、10 秒後に SIGKILL を送る（[ADR 0073](0073-time-bounds-in-tests.md) の文脈のとおり、どのテストが止まったかはわからない）。手元の `cabal test` には、このラッパーがない。

## 実装すること

### 見張りの補助

- golem-test-support に `Golem.TestSupport.Watchdog` を足し、`watchTests :: Integer -> TestTree -> TestTree` と `watchedName :: [TestName] -> TestName -> String` を置く。
- `watchTests limit` は、木のすべてのテストを包む。木の形、名前、オプション、資源、依存は変えない。包んだテストは、始まるときに名前（グループの名前と自分の名前を `/` でつないだもの）と時刻を C の表に書き、終わるとき（値でも例外でも）に消す。
- 見張りは C の POSIX スレッドで、最初のテストが始まるときに一度だけ作る。1 秒ごとに表を読み、次のどちらかで止める。
  - あるテストが `limit` 秒を超えて走っている。
  - 走っているテストがなく、最後のテストが終わってから `limit` 秒を超えた（プロセスが終わらない。文脈の 3）。
- 止めるときは、標準エラー出力に `write(2)` で直に次の行を書き、`abort()` する。出力はバッファーを通らない。
  - `watchdog: "<名前>" has run for more than <limit> seconds of wall-clock time`（上限を超えたテストごと）
  - `watchdog: "<名前>" is also running, for <秒> seconds`（ほかに走っているテストごと）
  - `watchdog: no test is running, and the last one ended <秒> seconds ago (more than <limit>): the process has not exited`（走っているテストがないとき）
  - `watchdog: the Haskell runtime last ran a thread <秒> seconds ago`。2 秒を超えていれば ` (it is stuck, not only the tests)` を足す。
  - `watchdog: aborting the process`
- 最初のテストは、0.1 秒ごとに C の時刻を書き換える Haskell のスレッド（心拍）も立てる。心拍が止まっていればランタイムが止まっており（文脈の 1）、動いていればテストどうしの待ち合い（文脈の 2）である。この一行が、次に止まったときに原因を分ける。
- 見張りのスレッドは Haskell を呼ばず、capability も取らない。Haskell の側は C の関数を `unsafe` で呼び、関数は表のロックを短く取るだけである。そのため、ランタイムが止まっていても見張りは働く。
- `abort()` を使うのは、終わらせ方を決めておくためと、macOS ではクラッシュレポートにすべてのスレッドのスタックが残るためである。
- 上限の値は、プロセスで最初に `watchTests` を通ったテストの値に固定する。
- C のソース（`cbits/golem_watchdog.c` と `.h`）は libc と pthread だけを使う。golem-test-support のライブラリにパッケージの依存を足さない。テストのスイート golem-test-support-test には `process` を足す（golem-* の依存ではないので、ADR の決まりの外である）。

### golem-driver-parallel-test

- `ParallelMain` で、木全体を `watchTests (300 * GOLEM_RACE_TESTS の値)` で包む。
- 300 秒は、[ADR 0091](0091-cpu-time-limits-in-pdf-and-svg-tests.md) の実時間の上限と同じ値である。単独で最も遅いテスト（kanikosen）は約 9 秒、文脈の再現の最も重い条件でもスイート全体が 105 秒で終わった。`GOLEM_RACE_TESTS` は fixture books の組版の回数を n 倍にするので、上限も n 倍にする。CI の suite-timeout.sh の 600 秒より短いので、CI でも見張りが先に働き、名前が出る。

### 文書

- `docs/specifications.md` の golem-test-support の段落に、`Golem.TestSupport.Watchdog` とこの ADR へのリンクを足す。
- `CONTRIBUTING.md` と `CONTRIBUTING.en.md` のテストの節に、`-threaded` の golem-driver-parallel-test は `watchTests` で止まることを書く。
- 開発者のマニュアル（`manual-dev/part2/09-adr.gm` の時間の上限の段落）に同じことを足す。

## 実装しないこと

- 止まりの原因の修正。原因を決められていない。次に止まったときの見張りの出力で決め、その修正は別の ADR か不具合の修正として扱う。
- ほかの `-threaded` のテストのスイート（golem-lsp、golem-font、golem-plugin、golem-parser）への適用。止まりを観測していない。観測したら、同じ補助を当てる。
- golem-pdf と golem-svg の `withinTimeLimits` の置き換え。あちらは CPU 時間で、止まらない計算を負荷に左右されずに止める。見張りは実時間だけを測り、別の失敗を拾う。
- tasty の `mkTimeout` をこのスイートに付けること。文脈のとおり、止まり方の三つのどれでも、名前つきの失敗にならないか、片付けで止まる。
- golem-plugin の `unsafe` の呼び出しを `safe` にすること。このスイートは通らない（docs/roadmap.md の項目のまま残す）。
- `suite-timeout.sh` の変更。スイートの外の最後の歯止めとして残す。

## テスト設計

golem-test-support-test は、自分の実行ファイルを、環境変数 `GOLEM_WATCHDOG_CHILD` を付けて子のプロセスとして走らせる。
子は、上限 3 秒の `watchTests` で次のスイートを走らせる。

- `waits`：`threadDelay` で 60 秒待つテスト。10 秒以内に正常でない終了コードで終わり、`watchdog: "g/waits" has run for more than 3 seconds of wall-clock time` と、心拍の行と、`watchdog: aborting the process` を出し、`stuck` を出さない。
- `holds`：C の `sleep(60)` を `unsafe` で呼ぶテスト。threaded でない RTS の唯一の OS スレッドを握るので、Haskell のスレッドは一つも動かない（文脈の 1 の代わり）。同じく名前の行を出し、心拍の行に `(it is stuck, not only the tests)` を出す。
- `stays`：テストは通り、`defaultMain` の終わりの `ExitCode` を捕まえて 60 秒待つ。`watchdog: no test is running, and the last one ended` の行を出し、`has run for` を出さない。
- `ends`：上限より早く終わるテスト。終了コード 0 で、標準エラー出力に `watchdog` を含まない。
- `watchedName ["a", "b"] "c"` が `a/b/c` であること。

見張りを外した（`watchTests` が木をそのまま返す）実装では、`waits`、`holds`、`stays` の三つが 60 秒で正常に終わり、落ちることを確かめた。

golem-driver-parallel-test の上限を一時的に 2 秒にして走らせ、`-threaded` と `-N` の下でも、走っていた四つのテストの名前と心拍の行（0.0 秒）を出して終了コード 134 で終わることを手で確かめた。

## トレードオフ

- テストの補助に C のコードが入る。代わりに、ランタイムが止まっても働く上限はほかに作れない。外のプロセス（`timeout` のような）で見張ると、どのテストが走っていたかを知るために、テストからファイルなどに書き出す仕組みが要り、要素が増える。
- 止まったスイートの失敗まで、最大で 300 秒（と見張りの 1 秒）かかる。正しいテストを負荷で落とさないための値である。
- `abort()` は、その時点までに Haskell の側のバッファーに溜まった出力を捨てる。tasty は標準出力を行のバッファーにするので、捨てるのは最後の行の途中だけである。見張りの行はバッファーを通らない。
- 見張りはプロセスに一つで、上限もプロセスに一つである。スイートの中でテストごとに上限を変えることはできない。

## 決めたことの記録

- **採択**：メンテナーが採択した（2026-11-05）。この ADR が決めてほしい点として挙げた項目は、どれも ADR の推奨のとおりとする。

## 参考文献

- [ADR 0073](0073-time-bounds-in-tests.md)
- [ADR 0075](0075-race-search-repetitions.md)
- [ADR 0091](0091-cpu-time-limits-in-pdf-and-svg-tests.md)
- tasty 1.5.4：`Test/Tasty/Run.hs`（`executeTest`、`launchTestTree`）、`Test/Tasty/Parallel.hs`（`runInParallel`）、`Test/Tasty/Runners/Utils.hs`（`installSignalHandlers`）https://hackage.haskell.org/package/tasty-1.5.4
- async 2.2.6：`Control/Concurrent/Async/Internal.hs`（`concurrently'`、`uninterruptibleCancel`）https://hackage.haskell.org/package/async-2.2.6
- hedgehog 1.5：`Hedgehog/Internal/Runner.hs`（`checkGroup` の `updateNumCapabilities`）https://hackage.haskell.org/package/hedgehog-1.5
