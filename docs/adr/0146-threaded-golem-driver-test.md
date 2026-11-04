# ADR 0146: golem-driver-test を threaded の RTS で並べて走らせ、プロセスの状態を変えるテストを別のスイートに分ける

ステータス: 採択（未実装）

## 文脈

[ADR 0140](0140-ci-split-test-runners-and-visual-pdfs-first.md) の後、`ci.yml` の `build` の x86-64 の `tests-driver` は golem-driver の二つのスイートだけを実行する。
その `cabal test` の手順は、2026-11-04 の 10 回の実行で 55 秒から 88 秒かかった。
aarch64 の `tests` の手順（すべてのスイート）は 85 秒から 92 秒で、その終わりも golem-driver-test が決めている。

### golem-driver-test は一つのコアで走る

golem-driver-test の `ghc-options` には `-threaded` がない（[golem-driver.cabal](https://github.com/tett23/golem/blob/3011e026b7b52e5100f52b81eddde068a89e04cb/modules/golem-driver/golem-driver.cabal#L73-L129)）。
threaded でない RTS では、tasty の `NumThreads` の既定値は 1 で、テストは一つずつ走る（[ADR 0091](0091-cpu-time-limits-in-pdf-and-svg-tests.md) の文脈が golem-pdf と golem-svg について書いたことと同じである）。
CI のログでも、`tests-driver` で golem-driver-test がほかのスイートと重ならずに走るのに、80 秒前後かかっている（実行 [41815303999](https://github.com/tett23/golem/actions/runs/41815303999) の 10:37:48 から 10:39:09、[41817232702](https://github.com/tett23/golem/actions/runs/41817232702) の 10:55:16 から 10:56:36）。

`-threaded` を付けない理由は、golem-driver.cabal の golem-driver-parallel-test の前の注釈にある（[golem-driver.cabal](https://github.com/tett23/golem/blob/3011e026b7b52e5100f52b81eddde068a89e04cb/modules/golem-driver/golem-driver.cabal#L130-L133)）。
threaded でビルドすると、tasty が同じスイートのテストを同時に走らせる。
golem-driver-test のテストには、プロセスの全体の状態を変えるものがある。

- PluginsSpec は、`withEnv` で環境変数 `XDG_CACHE_HOME` を変えてから組む（[PluginsSpec.hs](https://github.com/tett23/golem/blob/3011e026b7b52e5100f52b81eddde068a89e04cb/modules/golem-driver/test/PluginsSpec.hs#L70)）。プラグインのキャッシュの場所は、この変数から決まる。
- LocaleSpec は、`setLocaleEncoding` でプロセスのロケールの符号化を変えてから組む（[LocaleSpec.hs](https://github.com/tett23/golem/blob/3011e026b7b52e5100f52b81eddde068a89e04cb/modules/golem-driver/test/LocaleSpec.hs#L60)）。
- Main.hs の `cacheHomeRestored` は、すべてのテストの後で `XDG_CACHE_HOME` が元に戻っていることを確かめる（[Main.hs](https://github.com/tett23/golem/blob/3011e026b7b52e5100f52b81eddde068a89e04cb/modules/golem-driver/test/Main.hs#L83-L84)、[ADR 0072](0072-tests-restore-process-environment.md)）。

### 手元での計測

10 コアの macOS（cabal-install 3.18.1.0、GHC 9.10.3）で、`GOLEM_PD_BOOKS=1 TASTY_NO_CREATE=true` を付けて golem-driver のディレクトリで実行した。
CI のランナーの 4 コアに合わせ、threaded のものは `+RTS -N4` で走らせた。

| ビルドと実行 | 実時間（秒） | user（秒） | 結果 |
|---|---|---|---|
| 今のまま（threaded でない）、tasty `-j 4` | 48.67 | 43.69 | 通る |
| 今のまま（threaded でない）、tasty `-j 1` | 50.42 | 46.69 | 通る |
| `-threaded`、`-N4`、全体（3 回） | 31.55、21.73、21.08 | 約 54 | 968 のうち 76〜77 が失敗 |
| 同じ、PluginsSpec の群だけ `sequentialTestGroup`（3 回） | 34.81、29.09、25.94 | 約 60 | 11〜20 が失敗 |
| 同じ、プラグインの群を除く（3 回） | 19.54、18.97、18.84 | 約 51 | 856 のうち 2〜3 が失敗 |
| 同じ、プラグインの群だけを `-j 1`（1 回） | 7.60 | 7.09 | 112 がすべて通る |

threaded でない今のビルドでは、`-j 4` でも CPU の使用率は 100% のままだった（`ps` で 6 秒おきに 6 回見た）。
threaded で全体を走らせたときの失敗は、すべてが PluginsSpec のテストだった。
プラグインの群を除いたときの失敗は、すべてが HTML を読む三つのテストの `hGetContents: invalid argument (cannot decode byte sequence …)` で、LocaleSpec が同時にロケールの符号化を変えたことによる。
PluginsSpec の群を `sequentialTestGroup` にしても、入れ子の群のテストは同時に走るので、失敗は残った。

この計測から、二つの群をスイートから出せば、残りは 4 コアで約 2.5 倍速く走ると見込める。
CI の `tests-driver` の golem-driver-test の 80 秒前後は、30 秒台になる見込みである。

## 実装すること

テストを先に書き、今の実装で失敗することを確かめる。

- golem-driver に、threaded でないテストのスイート `golem-driver-global-test` を足す。PluginsSpec、LocaleSpec と、`XDG_CACHE_HOME` が元に戻ることの検査（`cacheHomeRestored`）を、golem-driver-test からここに移す。テストの中身は変えない。
- golem-driver-test の `ghc-options` を `-threaded "-with-rtsopts=-N"` にする（[ADR 0050](0050-run-golem-on-every-processor.md) の決まりのとおり、`setNumCapabilities` は呼ばない）。golem-driver.cabal の注釈を、二つのスイートの分け方に合わせて直す。
- golem-driver-test の Main に、プロセスの状態を変える補助（`withEnv`、`setLocaleEncoding`、`setEnv`、`setCurrentDirectory`）を使うテストがないことを、`scripts/ci/test.sh` で検査する。threaded のスイートにこれらを入れると、ほかのテストが途中の状態を読む。
- `scripts/ci/test-suites.sh` の `driver` は golem-driver のすべてのスイートなので、新しいスイートは `tests-driver` で走る（[ADR 0140](0140-ci-split-test-runners-and-visual-pdfs-first.md)）。`ci.yml` は変えない。
- 開発者のマニュアルのテストの章と CONTRIBUTING.md に、プロセスの状態を変えるテストは golem-driver-global-test に書くことを足す。

## 実装しないこと

- **プラグインのキャッシュの場所を、環境変数でなく引数で渡すこと。** PluginsSpec を threaded のスイートに残せるが、golem-plugin と golem-driver の公開の関数を変える。テストの速さのために製品の API を変えない。
- **golem-pdf-test と golem-svg-test を threaded にすること。** 二つは CPU 時間の上限をプロセスの CPU 時間で測り、threaded の RTS では動作を始めずに失敗する（[ADR 0091](0091-cpu-time-limits-in-pdf-and-svg-tests.md)）。
- **RTS の GC の設定を変えること。** 手元で golem-parser-test（`-N4`）を `-qg`、`-A64m`、`-qn2` で走らせると、12.35 秒が 10.29〜10.97 秒になった。CI の golem-parser-test は `tests-rest` で 45〜62 秒かかるが、そのランナーの終わりは golem-pdf-test が決めており、この差は実行全体を縮めない。
- **golem-driver-test のテストを中身で複数のスイートに分けること。** threaded にすれば一つのスイートのまま 4 コアを使える。

## テスト設計

### 先に書いて失敗させるテスト

- `scripts/ci/test.sh` に、golem-driver.cabal の golem-driver-test の `ghc-options` が `-threaded` と `-with-rtsopts=-N` を持ち、golem-driver-global-test が `-threaded` を持たないことを確かめる項目を足す。
- 同じく、golem-driver-test の `other-modules` に PluginsSpec と LocaleSpec がなく、golem-driver-global-test にあることを確かめる項目を足す。
- 同じく、golem-driver-test の `other-modules` のソースが `withEnv`、`setEnv`、`unsetEnv`、`setLocaleEncoding`、`setCurrentDirectory`、`withCurrentDirectory` を使わないことを確かめる項目を足す。

### 自動テストにできないものの確かめ方

- 手元で、`-N4` の golem-driver-test を 20 回続けて走らせ、一度も失敗しないことを確かめる。
- 下書きのプルリクエストで、`tests-driver` と aarch64 の `tests` の `cabal test` の手順の時間と、各スイートの始まりと終わりを、変更の前後で 2 回ずつ取る。golem-driver-test、golem-driver-global-test、golem-driver-parallel-test のすべてのテストが走っていることを、ログの数で確かめる。
- 夜間の `race.yml` の対象に golem-driver-test を足すかどうかを、そのとき決めて記録する（[ADR 0075](0075-race-search-repetitions.md)）。

## トレードオフ

- golem-driver-test のテストは、同じプロセスの中で同時に走るようになる。プロセスの状態に頼るテストを足すと、たまにだけ落ちるテストになる。上の検査は、名前のわかる補助しか捕まえない。
- テストのスイートが一つ増え、そのリンクの時間（手元で数秒）がビルドに足される。
- `tests-driver` は短くなるが、`build` のほかのランナー（`tests-rest`、`outputs`、aarch64 の `tests`）が同じくらいの時間で残る。実行全体を縮めるには、[ADR 0147](0147-start-long-test-suites-first.md) が要る。aarch64 の `tests` では、golem-driver-test が終わっても、遅れて始まる golem-pdf-test と golem-parser-test が残る。

## 決めたことの記録

- **採択**：メンテナーが採択した（2026-11-04）。この ADR が決めてほしい点として挙げた項目は、どれも ADR の推奨のとおりとする。

## 参考文献

- [golem-driver.cabal](https://github.com/tett23/golem/blob/3011e026b7b52e5100f52b81eddde068a89e04cb/modules/golem-driver/golem-driver.cabal)
- [golem-driver の test/Main.hs](https://github.com/tett23/golem/blob/3011e026b7b52e5100f52b81eddde068a89e04cb/modules/golem-driver/test/Main.hs)
- tasty 1.5.4, `Test.Tasty.Options.Core`（`NumThreads` の既定値）. https://hackage.haskell.org/package/tasty-1.5.4/src/Test/Tasty/Options/Core.hs
- tasty 1.5.4, `sequentialTestGroup`. https://hackage.haskell.org/package/tasty-1.5.4/docs/Test-Tasty.html
- [ADR 0050](0050-run-golem-on-every-processor.md)、[ADR 0072](0072-tests-restore-process-environment.md)、[ADR 0075](0075-race-search-repetitions.md)、[ADR 0091](0091-cpu-time-limits-in-pdf-and-svg-tests.md)、[ADR 0140](0140-ci-split-test-runners-and-visual-pdfs-first.md)
