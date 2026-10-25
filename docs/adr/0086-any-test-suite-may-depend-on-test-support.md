# ADR 0086: どのテストスイートも golem-test-support に依存してよいとする

ステータス: 採択（未実装）

## 文脈

テストの補助を共有するパッケージ golem-test-support は、[ADR 0028](0028-shared-test-support-package.md) が導入した。
今これに依存するテストスイートは、golem-doc-test、golem-driver-test、golem-driver-parallel-test、golem-pdf-test、golem-plugin-test の五つである（[golem-doc.cabal](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-doc/golem-doc.cabal#L56)、[golem-driver.cabal](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-driver/golem-driver.cabal#L118)、[同じく parallel-test](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-driver/golem-driver.cabal#L156)、[golem-pdf.cabal](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-pdf/golem-pdf.cabal#L60)、[golem-plugin.cabal](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-plugin/golem-plugin.cabal#L86)）。
ほかのテストスイートは依存していない。

[2026-10-25 のリファクタリングの調査](../audits/2026-10-25-refactoring-survey.md) の R18 は、テストの `inParallel`（4 箇所）、`raceFactor`（2 箇所）、`withEnv`（2 箇所）が同じ本体の写しであると挙げた。
このうち、すでに golem-test-support に依存しているテストスイートの写しは、R18 の (a) として片付いた（[#395](https://github.com/tett23/golem/pull/395)）。
`inParallel` と `raceFactor` は golem-test-support の [`Golem.TestSupport.Parallel`](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-test-support/src/Golem/TestSupport/Parallel.hs) に置かれ、golem-driver の ParallelSpec と ParallelMain、golem-plugin の ConcurrencySpec はそこから import する。
golem-test-support のテストは `inParallel` を確かめるが、`raceFactor` は確かめていない。

残った写しは、golem-test-support に依存していないテストスイートのものである。
本体が `Golem.TestSupport.Parallel` と一致することをコードで確かめた（注釈の文面だけが違う）。

- **`inParallel`**：二つある。[golem-font の ConcurrencySpec](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-font/test/ConcurrencySpec.hs#L47-L58) と [golem-font の race/Main.hs](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-font/test/race/Main.hs#L34-L45)。
- **`raceFactor`**：一つある。[golem-font の ConcurrencySpec](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-font/test/ConcurrencySpec.hs#L35-L40)。[ADR 0075](0075-race-search-repetitions.md) の `GOLEM_RACE_TESTS` を読む。
- **`withEnv`**：二つある。[golem-driver の Support.hs](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-driver/test/Support.hs#L650-L656) と [golem-lsp の Main.hs](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-lsp/test/Main.hs#L605-L611)。[ADR 0072](0072-tests-restore-process-environment.md) の、環境変数を書き換えて元に戻す補助である。golem-driver のテストは golem-test-support に依存しているが、`withEnv` は golem-lsp の写しと対になるため R18 の (a) では動かさなかった。

golem-font-test、golem-font-race-test（[golem-font.cabal](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-font/golem-font.cabal#L84-L94)、[同じく](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-font/golem-font.cabal#L106-L111)）と golem-lsp-test（[golem-lsp.cabal](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-lsp/golem-lsp.cabal#L53-L75)）は、golem-test-support に依存していない。
R18 の (a) がこれらの写しを残したのは、依存を足すのに ADR が要るからである。

これまでの方針は、golem-\* のパッケージのあいだの依存を足すくらいなら写しを許す、というものだった。
[ADR 0072](0072-tests-restore-process-environment.md) も「golem-lsp のテストは golem-test-support に依存していないので、依存を足さない」と決め、`withEnv` を写した（[ADR 0072 の実装すること](0072-tests-restore-process-environment.md)）。
この方針の理由は、パッケージのあいだに依存の道ができると、片方の変更がもう片方のビルドとテストに及ぶことにある。

しかし golem-test-support は、golem のどのパッケージにも依存しない。
依存は `base` と `tasty` だけである（[golem-test-support.cabal](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-test-support/golem-test-support.cabal#L28-L30)）。
テストスイートがこれに依存しても、製品のパッケージのあいだに新しい道はできない。
ライブラリと実行ファイルが依存しないことは `scripts/ci/test-only-deps.sh` が CI で確かめている（[test-only-deps.sh](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/scripts/ci/test-only-deps.sh#L44-L57)）。
写しを許す方針の理由は、golem-test-support への依存には当てはまらない。
それでも依存のたびに ADR を書くことになっていたので、写しが残った。

## 実装すること

### 方針

- どのテストスイートも、golem-test-support を build-depends に足してよい。足すのに ADR は要らない。
- ライブラリと実行ファイルは、今までどおり golem-test-support に依存しない（[ADR 0028](0028-shared-test-support-package.md)、`test-only-deps.sh`）。
- 二つ以上のパッケージのテストに本体の同じ補助があり、golem-test-support の依存の範囲で書けるものは、golem-test-support に置く。一つのパッケージの中だけで使う補助は、そのパッケージのテストに置く。
- golem-test-support 自身の依存は、この ADR では変えない（`base` と `tasty` のまま）。依存を広げるかどうかは [ADR 0087](0087-test-support-dependencies-and-shared-fixtures.md) で決める。

### golem-test-support を分ける時期

依存を足しやすくすると、golem-test-support には補助が集まり続ける。
いずれ、このパッケージが何の補助を持つのかがぼやけるだろう。
そうなったら、golem-test-support を小さなパッケージかモジュールに分ける。

分ける必要は、次のような兆候で見分ける。

- 互いに関係のない補助が、同じモジュールに積み重なっている。
- 一つのテストスイートしか使わない補助が golem-test-support にある。上の方針では、その補助はそのパッケージのテストに置くものである。
- golem-test-support の依存を足すたびに、その依存を使わないテストスイートまで作り直しを待つようになる。

golem-test-support に補助を足すプルリクエストでは、これらの兆候がないかを見る。
分けるときは、分け方（パッケージにするかモジュールにするか、どの補助をどこに置くか）を別の ADR で決める。
パッケージを分ければ golem のパッケージの一覧と依存の図が変わり、モジュールで分けても import の書き方が変わるからである。

### 補助の置き場

- golem-font の `inParallel` と `raceFactor` は、既存の `Golem.TestSupport.Parallel` から import する。新しいモジュールは作らない。
- `withEnv` を、既存の `Golem.TestSupport.Env`（[Env.hs](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-test-support/src/Golem/TestSupport/Env.hs)）に足す。`envFlag` と同じく環境変数の補助だからである。
- `withEnv` は `base` だけで書ける（`lookupEnv`、`setEnv`、`unsetEnv`、`finally`）ので、golem-test-support の依存は変わらない。
- 関数の名前、型、振る舞いは変えない。`raceFactor` の失敗の文言（`GOLEM_RACE_TESTS must be an integer of 1 or more, not ...`）も変えない。
- 環境変数を読まずに値の判定だけを確かめられるよう、`Golem.TestSupport.Parallel` の `raceFactor` の判定を純粋な関数 `raceFactorBy :: Maybe String -> Either String Int` に切り出し、export する。`raceFactor` はこれに `lookupEnv` の結果を渡し、`Left` なら `fail` するものとして定義し直す。`envFlag` と `envFlagBy` の分け方（[ADR 0074](0074-test-switches-by-environment-variables.md)）と同じである。

### build-depends の変更

| パッケージ | 部品 | 変更 |
| --- | --- | --- |
| golem-font | golem-font-test | `golem-test-support` を足す |
| golem-font | golem-font-race-test | `golem-test-support` を足す |
| golem-lsp | golem-lsp-test | `golem-test-support` を足す |
| golem-test-support | library | 変えない（`exposed-modules` も build-depends も今のまま） |

ライブラリと実行ファイルの build-depends は、どのパッケージでも変えない。

### 写しを消す箇所

- golem-font：`test/ConcurrencySpec.hs` の `inParallel` と `raceFactor`、`test/race/Main.hs` の `inParallel`。
- golem-lsp：`test/Main.hs` の `withEnv`。
- golem-driver：`test/Support.hs` の `withEnv`。依存は変わらない。

### 依存のグラフ

ライブラリと実行ファイルのあいだのグラフは変わらない。
変わるのはテストスイートからの辺だけで、golem-test-support は golem のパッケージに依存しないので、閉路はできない。

```
前：golem-font-test      → golem-font
    golem-font-race-test → golem-font
    golem-lsp-test       → golem-driver, golem-eval, golem-lsp, golem-plugin, golem-syntax
後：golem-font-test      → golem-font, golem-test-support
    golem-font-race-test → golem-font, golem-test-support
    golem-lsp-test       → golem-driver, golem-eval, golem-lsp, golem-plugin, golem-syntax, golem-test-support
    golem-test-support   → （golem のパッケージなし。base、tasty）
```

### 文書

- `CONTRIBUTING.md`（[106 行目](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/CONTRIBUTING.md#L106)）と `CONTRIBUTING.en.md`（[97 行目](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/CONTRIBUTING.en.md#L97)）に、どのテストスイートも golem-test-support に依存してよいこと、二つ以上のパッケージのテストが共有する補助はそこに置くこと、一つのテストスイートしか使わない補助は置かないことを足す。
- `manual-dev/part2/08-build-test.gm`（[108 行目から 111 行目](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/manual-dev/part2/08-build-test.gm#L108-L111)）に、同じことを一文で足す。
- `manual-dev/part2/07-modules.gm` の「golem-font は Golem のほかのパッケージに依存しない」（[58 行目](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/manual-dev/part2/07-modules.gm#L58)）を、「golem-font のライブラリは」に改める。テストが golem-test-support に依存するようになるので、パッケージ全体については成り立たなくなる。
- [ADR 0072](0072-tests-restore-process-environment.md) のステータスの行を「採択→golem-lsp のテストが golem-test-support に依存しないことは [ADR 0086](0086-any-test-suite-may-depend-on-test-support.md)」に改める。
- `docs/specifications.md` の golem-test-support の段落（[229 行目から 232 行目](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/docs/specifications.md#L229-L232)）は、モジュールの例を「など」で挙げ、どのテストスイートが依存するかを書いていないので変えない。`README.md` も変えない。

## 実装しないこと

- golem-test-support の依存を `base` と `tasty` の外に広げること。[ADR 0087](0087-test-support-dependencies-and-shared-fixtures.md) で決める。
- golem の型（`SrcSpan`、`Diagnostic` など）を使う補助の共有。
- golem-test-support を分けること。上の兆候が見えたときに、別の ADR で決める。
- `inParallel`、`raceFactor`、`withEnv` の振る舞いの変更。
- golem-driver-test を `-threaded` にすること（[ADR 0072](0072-tests-restore-process-environment.md) の実装しないことと同じ）。
- 使われていない依存を見つける検査（GHC の `-Wunused-packages`）を足すこと。

## テスト設計

### golem-test-support のテスト

テストを先に書き、golem-test-support に関数がない状態でコンパイルが失敗することを確かめてから実装する。
`inParallel` のテストは R18 の (a) が足したので、足さない。

- `raceFactorBy Nothing` は `Right 1`、`raceFactorBy (Just "40")` は `Right 40` である。
- `raceFactorBy` は、`Just ""`、`Just "0"`、`Just "07"`、`Just "x"`、`Just "1234567"` で `Left` を返し、文言は `GOLEM_RACE_TESTS must be an integer of 1 or more, not "<値>"` である。
- `withEnv` は、動作の中で値を設定し、動作の後に元の値に戻す。元の値がなかった変数は、動作の後に未設定に戻る。動作が例外を投げても戻す。テストは golem-test-support のテストだけが使う名前の変数（`GOLEM_TEST_SUPPORT_WITH_ENV`）で行う。golem-test-support-test は `-threaded` でないので、ほかのテストと競合しない。

### 移した後の確かめ

- `rg -n '^(inParallel|raceFactor|withEnv) ::' modules/*/test` が何も返さない。
- golem-font-test、golem-font-race-test、golem-lsp-test、golem-driver-test の `--list-tests` の出力が、変更の前と後で同じである。テストの数も名前も変わらない。
- 上の四つのテストスイートと、`raceFactor` を使う golem-driver-parallel-test が通る。golem-font-test の ConcurrencySpec と golem-driver-parallel-test を `GOLEM_RACE_TESTS=2` でも走らせ、回数の掛け算が働いていることを確かめる（`GOLEM_RACE_TESTS=0` で失敗することも見る）。
- CI の `build` ジョブの `test-only-deps.sh` が終了コード 0 で終わる。

### 出力が変わらないことの確かめ

ライブラリと実行ファイルのソースも build-depends も変えないので、出力は変わらない。
それを次で確かめる。

- cabal の計画（`dist-newstyle/cache/plan.json`）で、`golem-cli:exe:golem` から辿れる部品の集合が、変更の前と後で同じである（`scripts/release/licenses.sh` と同じ辿り方）。
- golem-driver の `OutputGoldenSpec`（`test/golden/` の `pdf-sample.txt`、`pdf-figures.txt`、`epub-sample.txt`、`epub-figures.txt`）が通る。
- ベースのコミットと変更後のコミットでそれぞれ golem をビルドし、`GOLEM=<その golem> sh scripts/determinism.sh` の出力の一覧を取って `diff` し、差がない。CI の決定性の検査は同じコミットの二つのアーキテクチャを比べるだけなので、コミットをまたぐ比較は手元で行う（[2026-10-20 のロードマップのレビュー](../audits/2026-10-20-roadmap-review.md)）。

## トレードオフ

- golem-test-support の補助を変えると、それに依存するテストスイートがすべて作り直される。依存するテストスイートは五つから八つになる。補助は小さく、変更もまれなので、写しを手で揃える手間より安い。
- golem-font のテストは、golem のどのパッケージにも依存せずにビルドできた。golem-test-support に依存すると、その独立がテストについては失われる。golem-test-support は golem のパッケージに依存しないので、golem-font のテストが golem-syntax などの変更で作り直されることはない。
- 写しのままにする案もある。写しは `inParallel` の三つの定義（golem-test-support と golem-font の二つ）を揃え続ける手間を残し、直し忘れを検出する仕組みもない（[ADR 0028](0028-shared-test-support-package.md) の文脈と同じ問題）。
- 依存を足すたびに ADR で決める案は、今までの運用である。golem-test-support が golem のパッケージに依存しない限り、ADR で比べる選択肢がなく、決定の中身がない。依存の範囲を変えるとき（[ADR 0087](0087-test-support-dependencies-and-shared-fixtures.md)）と、golem-test-support を分けるときだけ ADR を書く。
- 依存を足しやすくすると、golem-test-support の責務がぼやけるまで補助が集まる見込みが高い。この ADR は分ける時期を兆候で決め、分け方を後の ADR に回す。今の補助は四つのモジュールに収まっており、今分けると、まだ見えていない境界を推測で引くことになる。
- `raceFactor` の golem-font の写しは、R18 の (a) で意図して残していた。golem-font のテストが golem-test-support に依存すれば写しを残す理由がなくなるので、`inParallel` と同じく消す。

## 参考文献

- [2026-10-25 のリファクタリングの調査](../audits/2026-10-25-refactoring-survey.md) の R18
- [ADR 0028](0028-shared-test-support-package.md)、[ADR 0072](0072-tests-restore-process-environment.md)、[ADR 0074](0074-test-switches-by-environment-variables.md)、[ADR 0075](0075-race-search-repetitions.md)
- [2026-10-20 のロードマップのレビュー](../audits/2026-10-20-roadmap-review.md)
- [#395](https://github.com/tett23/golem/pull/395)（R18 の (a)：`inParallel` と `raceFactor` を `Golem.TestSupport.Parallel` に移した）
