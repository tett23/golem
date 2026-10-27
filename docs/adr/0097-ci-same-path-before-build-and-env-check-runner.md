# ADR 0097: build のランナーの PATH をそろえ、環境を変える検査とスクリプトのテストを臨界経路から外す

ステータス: 採択（未実装）

## 文脈

`ci.yml` の一回の実行は、`main` への push で 11 分半ほどかかる（実行 [40368421139](https://github.com/tett23/golem/actions/runs/40368421139)）。
プルリクエストでも 10 分ほどかかる（実行 [40368830926](https://github.com/tett23/golem/actions/runs/40368830926)）。
`CONTRIBUTING.md` は、CI の実行時間を 5 分以内に保ち、超えたらまず CI を改善すると約束している。

### 臨界経路

二つの実行のジョブの時間を、`gh run view <id> --json jobs | scripts/ci/timings.sh` で取った。
単位は秒である。

| ジョブ | `main` への push（40368421139） | プルリクエスト（40368830926） |
|---|---|---|
| `changes` | 24 | 31 |
| `build (ubuntu-24.04, tests)` | 170 | 145 |
| `build (ubuntu-24.04, outputs)` | 449 | 353 |
| `build (ubuntu-24.04-arm, all)` | 168 | 156 |
| `visual` | 211 | 213 |
| `scripts-macos` | 197 | 220 |
| `format` | 58 | 72 |

臨界経路は `changes`、`build (ubuntu-24.04, outputs)`、`visual`、`ci` である。
`visual` は `build` の行列のすべてを待つ（`needs: [changes, build]`）。

### outputs だけがすべてのパッケージをビルドし直す

`outputs` の `cabal build all peg-cli:exe:peg-hs` は、`main` への push で 201 秒、プルリクエストで 211 秒かかった。
同じ実行の `tests` は 18 秒と 15 秒、aarch64 の `all` は 14 秒と 14 秒だった。
三つのランナーは、同じキーの `dist-newstyle` のキャッシュを戻している（40368421139 では、三つとも `dist-…-66d308f5…` から戻した）。

`outputs` のログでは、cabal がすべてのパッケージの、すべての部品に `(configuration changed)` を付けて、設定からやり直している。
`golem-font` のライブラリのビルドが、そのうちの約 140 秒を占める（`Building library for golem-font` の 17:26:09 から、次の `Configuring library for golem-driver` の 17:29:12 まで）。
golem-font は HarfBuzz の C のソースを含み、設定が変わるとそれもコンパイルし直す（[ADR 0037](0037-ci-build-job-speedup.md)）。
`tests` のログには `configuration changed` がなく、テストのスイートに `(additional components to build)` が付くだけである。

違いは `PATH` にある。
`outputs` の「epubcheck in the background」のステップは、`cabal build` より前に `"$RUNNER_TEMP/epubcheck/bin"` を `GITHUB_PATH` に書く（[ADR 0062](0062-epubcheck-from-release-with-cache.md)、[ci.yml](https://github.com/tett23/golem/blob/22f6975623903baf42236964a8d29ae244b06a83/.github/workflows/ci.yml#L143-L147)）。
`tests` と aarch64 の `all` は epubcheck を入れないので、`PATH` に足さない。
キャッシュを保存するのは `tests` と `all` だけなので、`outputs` の `PATH` だけが、キャッシュを作ったときと違う。

cabal-install 3.16.1.0 は、プロジェクトの計画を作るときにシステムの検索パス（`PATH`）を読み（[ProjectPlanning.hs](https://github.com/haskell/cabal/blob/8d1f5a33662be0db0654061fb53fb00e3f4417e0/cabal-install/src/Distribution/Client/ProjectPlanning.hs#L525)）、それを `ProgramDb` に入れる。
`ProgramDb` を保存するときは、検索パスもいっしょに書く（[Db.hs](https://github.com/haskell/cabal/blob/8d1f5a33662be0db0654061fb53fb00e3f4417e0/Cabal/src/Distribution/Simple/Program/Db.hs#L151-L154)）。
この `ProgramDb` は、すべてのパッケージが共有する設定（`pkgConfigCompilerProgs`）に入る。
そのため、`PATH` が変わると、すべてのパッケージの設定が変わったことになる。

手元（cabal-install 3.18.1.0、macOS）で、一つのライブラリだけのプロジェクトを使って確かめた。
ビルドの後、同じ `PATH` の `cabal build --dry-run` は `Up to date` を出した。
`PATH` の先頭か末尾に空のディレクトリを一つ足すと、`pt-0.1 (lib) (configuration changed)` を出した。

[ADR 0045](0045-split-x86-build-and-pull-request-cache.md) は、三つのランナーが同じ設定でビルドし、ビルドの計画が同じになることを前提に、二つ目の x86-64 のランナーでのビルドを 15 秒前後と見積もった。
[ADR 0062](0062-epubcheck-from-release-with-cache.md) の実装（[9a5eb349](https://github.com/tett23/golem/commit/9a5eb34957fdf188f5ecadd064821aa975a1c192)）が、この前提を気づかれないまま崩していた。

### 環境を変える検査

`outputs` の中で、環境を変える検査（`scripts/env-determinism/check.sh`）は、`main` への push で 125 秒、プルリクエスト（`--quick`）で 14 秒かかった（[ADR 0029](0029-environment-variation-determinism-test.md)、[ADR 0038](0038-env-determinism-quick-on-pull-requests.md)）。
この検査は `outputs` のほかの手順の結果を使わない。
要るのは、ビルドした golem、日本語のロケール、マニュアルのフォントだけである。

### changes のスクリプトのテスト

`changes` は、ビルドの要否を決める前に、`scripts/` の下の五本のテストを実行する。
40368421139 では、ジョブの 24 秒のうち 16 秒がこのテストだった。
`build` も `scripts-macos` も、このテストが終わるまで始まらない。
ビルドの要否の判定は、テストの結果を使わない。

### scripts-macos の環境を変える検査のテスト

`scripts-macos` の `scripts/env-determinism/test.sh` は、`main` への push で 130 秒かかった。
同じテストは、Linux の `changes` では 6 秒である。
`check.sh` は、日本語のロケールを探すとき、インストールされたロケールの一つずつに三つほどのプロセスを起こす。
macOS には約 500 のロケールがあり、`check.sh` の一回の実行がそれだけで約 4 秒かかる。
テストは `check.sh` を約 30 回実行する。
手元の Mac では、テストが 113 秒かかった。

### 下書きでの計測

この ADR の内容を、下書きのプルリクエスト [#435](https://github.com/tett23/golem/pull/435) で試した。
`main` への push と同じ時間を見るため、[#436](https://github.com/tett23/golem/pull/436) は #435 に、環境を変える検査から `--quick` を外す一行だけを足した（計測のためだけで、マージしない）。
どちらも 2 回ずつ実行した。
実行全体は、最初のジョブの始まりから最後のジョブの終わりまでの秒数である。

| 実行 | 実行全体 | `visual` の始まり | `outputs` | `outputs` の `cabal build` | `env` | `env` の検査 | `visual` |
|---|---|---|---|---|---|---|---|
| 前、プルリクエスト（40368830926） | 607 | 388 | 353 | 211 | - | 14（`outputs` の中） | 213 |
| 前、プルリクエスト（40366727002） | 606 | 378 | 340 | 184 | - | 12（`outputs` の中） | 215 |
| 前、`main` への push（40368421139） | 696 | 478 | 449 | 201 | - | 125（`outputs` の中） | 211 |
| 前、`main` への push（40372815478） | 663 | 434 | 396 | 181 | - | 99（`outputs` の中） | 222 |
| 後、#435（40375352220） | 486 | 191 | 151 | 18 | 66 | 9 | 288 |
| 後、#435（40376691227） | 435 | 191 | 148 | 16 | 72 | 13 | 238 |
| 後、#436 のすべての入力（40375774694） | 361 | 199 | 151 | 19 | 181 | 127 | 155 |
| 後、#436 のすべての入力（40377816967） | 423 | 180 | 146 | 19 | 140 | 80 | 236 |

`visual` の始まりは、プルリクエストで約 380 秒から約 190 秒に、すべての入力で約 450 秒から約 190 秒になった。
後の `visual` の始まりを決めているのは、`build (ubuntu-24.04-arm, all)`（160 秒から 183 秒）と `build (ubuntu-24.04, tests)`（157 秒から 175 秒）である。
`visual` 自身は 155 秒から 288 秒と揺れ、実行全体の揺れの大半はここから来る。
`scripts-macos` は 177 秒から 226 秒が 99 秒から 126 秒になり、その中の `scripts/env-determinism/test.sh` は 130 秒が 27 秒から 36 秒になった。

## 実装すること

### build のランナーの PATH をそろえる

- `outputs` の epubcheck を `PATH` に足すのを、`cabal build` の後の「epubcheck is installed」のステップに移す。epubcheck を使うのは、その後のステップだけである。
- `build` ジョブで、`cabal build` より前に `PATH` を変えてよいのは、どのランナーでも同じディレクトリを足す「GHC on the PATH」のステップだけとする。
- `scripts/ci/test.sh` に、この二つを確かめる項目を足す。

### 環境を変える検査を、x86-64 の新しいランナーに移す

`build` の行列に、四つ目の組み合わせを足す。

| `runner` | `part` | 受け持つ手順 |
|---|---|---|
| `ubuntu-24.04` | `tests` | 今と同じ |
| `ubuntu-24.04` | `outputs` | 今の手順から、環境を変える検査を除いたもの |
| `ubuntu-24.04` | `env` | 日本語のロケールの生成、マニュアルのフォントの取得、環境を変える検査 |
| `ubuntu-24.04-arm` | `all` | 今と同じ |

- 行列の各行に `env`（真偽値）を足し、ロケールと検査のステップの条件を `matrix.env` にする。
- `env` のランナーは、マニュアルのフォントのキャッシュを戻し、`scripts/manual/fetch-fonts.sh` で `manual/fonts` と `manual-dev/fonts` を取る（キャッシュにあれば取らない）。`outputs` では `scripts/manual/build.sh` がフォントを取るが、`env` はマニュアルを組まないからである。
- 検査の引数（プルリクエストの `--quick`）と環境変数（`GOLEM_REQUIRE_LOCALES=1`、`GOLEM_REQUIRE_FONTS=1`）は変えない。
- `env` のランナーは、ほかと同じ手順で、同じ `PATH` のまま `cabal build all peg-cli:exe:peg-hs` を実行する。

### スクリプトのテストを、新しいジョブ scripts-linux に移す

- `changes` から、`scripts/ci/test.sh`、`scripts/manual/test.sh`、`scripts/env-determinism/test.sh`、`scripts/test.sh`、`scripts/visual/test.sh` のステップを、新しいジョブ `scripts-linux` に移す。
- `scripts-linux` は `needs` も `if` も持たず、ドキュメントだけの変更でも走る。今の `changes` と同じく、スクリプトのテストはいつも走る。
- `changes` には、ビルドが読む文書の一覧、不完全なパターン、`unsafePerformIO`、capability の数、プラグインの ABI のバージョンの検査と、ビルドの要否の判定を残す。どれも 1 秒に満たない。
- `ci` ジョブの `needs` と `scripts/ci/gate.sh` の `NAMES` に `scripts-linux` を足す（[ADR 0021](0021-docs-workflow-and-ci-gate.md)）。

### check.sh のロケールの探し方

- `scripts/env-determinism/check.sh` の `find_locale` は、`locale -a` の一覧を一つの `awk` で調べる。比べ方（大文字と小文字を区別せず、`-` を除いて比べ、一覧の名前のまま返す）は変えない。

### ドキュメント

- README の CI の節の表に `scripts-linux` の行を足し、`changes` と `build` の行を直す。
- 開発者向けのマニュアルの「CI のジョブ」の章を、同じ内容に直す。
- 計測の結果を `docs/ci-timings/` に記録する。

## 実装しないこと

- **ビルドした golem を成果物として別のジョブに渡すこと。** 環境を変える検査を `needs: build` の別のジョブにすると、`build` の行列が終わるまで始まらない。`main` への push では `build` の後に約 140 秒が足され、`visual` が今より短くなると臨界経路に出る。行列の一つにすれば、ほかのランナーと同時に始まる。`PATH` をそろえた後のビルドは 15 秒前後で済む。
- **環境を変える検査のための手順を、別のジョブに書き写すこと。** `build` の十数のステップ（キャッシュ、GHC、wasmtime、テストのラッパー）を二か所で保つことになる。
- **プルリクエストでだけ、環境を変える検査を `outputs` に残すこと。** プルリクエストの検査は 14 秒で、ランナーを一つ節約できる。しかし、イベントによって行列の形が変わり、ステップの条件が複雑になる。
- **テストのスイートを複数のランナーに分けること。** `tests` と `all` は、`PATH` をそろえた後の `outputs` と同じくらいの長さで、`visual` の始まりを決める。分けても `visual`（約 210 秒）が残る。`visual` の中身はこの ADR の範囲の外である。
- **`format` と `scripts-macos` の短縮。** どちらも臨界経路にない。`scripts-macos` は、上の `check.sh` の変更で約 90 秒縮む見込みである。
- **`visual` が `build` の行列のすべてを待つこと。** `visual` が要るのは `outputs` の成果物だけだが、行列の一つだけを待つことはできない。変えるなら、`outputs` を行列から出すか、PDF を組む場所を動かす。見た目の回帰テストの ADR で扱う。

## テスト設計

### 先に書いて失敗させるテスト（`scripts/ci/test.sh`）

- `build` の行列が、`ubuntu-24.04` の `tests`、`outputs`、`env` と、`ubuntu-24.04-arm` の `all` を持ち、各行の `tests`、`outputs`、`env` が上の表のとおりであること。
- 「Japanese locales for the environment check」と「The outputs do not change with the environment」の条件が `matrix.env` であること。
- `env` のランナーが、`fetch-fonts.sh` で `manual/fonts` と `manual-dev/fonts` を取ること。
- `build` ジョブの、`cabal build` のステップより前の `GITHUB_PATH` への書き込みが、GHC のディレクトリの一つだけであること。
- 「epubcheck is installed」のステップが、epubcheck のディレクトリを `GITHUB_PATH` に書くこと。
- `scripts-linux` が `ubuntu-24.04` で動き、`needs` と `if` を持たず、五本のテストを実行すること。`changes` がその五本を実行しないこと。
- `ci` が `scripts-linux` を待つこと。`gate.sh` の名前が `ci.yml` のジョブと一致すること（今の項目）。

### 自動テストにできないものの確かめ方

下書きのプルリクエストで、次を確かめて記録する。

- `outputs` と `env` の `cabal build` のログに `configuration changed` がなく、時間が `tests` と同じくらいであること。
- `env` のランナーで、プルリクエストでは `--quick` の検査が、`main` への push（`workflow_call` を含む）ではすべての入力の検査が通ること。`main` への push は下書きでは起きないので、マージの後の最初の push で確かめる。
- `determinism` が `outputs` と `all` の成果物を比べて通ること。`visual` が `visual-pdfs` を取り寄せて通ること。
- `scripts-macos` の `scripts/env-determinism/test.sh` の時間。
- 実行全体と各ジョブの時間を、変更の前後で 2 回ずつ取る。

## トレードオフ

- x86-64 のランナーが一つ増え、一回の実行で同時に使うランナーは、`build` の四つと `scripts-linux` を合わせて二つ増える。プルリクエストでは、`env` のランナーはセットアップとビルドに約 75 秒を使い、検査は 14 秒しかしない。
- `main` への push では、`env` のランナー（セットアップとビルドに約 75 秒、検査に約 125 秒）が `build` の行列で最も長くなりうる。`visual` は行列のすべてを待つので、その分だけ `visual` の始まりが遅れる。それでも、今の `outputs`（449 秒）よりは短い。
- `changes` が失敗しても、`scripts-linux` は走る。逆に、スクリプトのテストが失敗しても `build` は止まらない。どちらの失敗も `ci` が拾うので、必須の検査の結果は変わらない。ランナーの時間は、失敗のときに少し増える。
- `PATH` の検査は、`GITHUB_PATH` への書き込みしか見ない。`GITHUB_ENV` で `PATH` を変えるステップや、アクションが中で `PATH` を変える場合は捕まえない。

## 参考文献

- cabal-install 3.16.1.0, `Distribution.Client.ProjectPlanning`（計画を作るときにシステムの検索パスを読む）. https://github.com/haskell/cabal/blob/8d1f5a33662be0db0654061fb53fb00e3f4417e0/cabal-install/src/Distribution/Client/ProjectPlanning.hs#L525
- Cabal 3.16, `Distribution.Simple.Program.Db`（`ProgramDb` の保存に検索パスを含める）. https://github.com/haskell/cabal/blob/8d1f5a33662be0db0654061fb53fb00e3f4417e0/Cabal/src/Distribution/Simple/Program/Db.hs#L151-L154
- `ci.yml`（変更の前）. https://github.com/tett23/golem/blob/22f6975623903baf42236964a8d29ae244b06a83/.github/workflows/ci.yml
- `scripts/env-determinism/check.sh`（変更の前の `find_locale`）. https://github.com/tett23/golem/blob/22f6975623903baf42236964a8d29ae244b06a83/scripts/env-determinism/check.sh#L75-L88
- GitHub Docs, "Workflow commands for GitHub Actions"（`GITHUB_PATH` は後のステップの `PATH` の先頭に足される）. https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands
- [ADR 0009](0009-ci-speed.md)、[ADR 0021](0021-docs-workflow-and-ci-gate.md)、[ADR 0029](0029-environment-variation-determinism-test.md)、[ADR 0037](0037-ci-build-job-speedup.md)、[ADR 0038](0038-env-determinism-quick-on-pull-requests.md)、[ADR 0045](0045-split-x86-build-and-pull-request-cache.md)、[ADR 0062](0062-epubcheck-from-release-with-cache.md)、[ADR 0079](0079-shell-tests-on-macos.md)、[ADR 0095](0095-visual-job-in-ci.md)
- 計測のデータ：下書きのプルリクエスト [#435](https://github.com/tett23/golem/pull/435) の実行
