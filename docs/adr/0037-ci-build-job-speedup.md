# ADR 0037: CI の build ジョブの手戻りをなくす

ステータス: 採択

## 文脈

CONTRIBUTING.md は、CI の実行時間を 5 分以内に保つと定めている。
ところが 2026-10-17 の時点で、`ci.yml` の一回の実行は 7 分から 10 分かかる。
今は八つの実装の作業がそれぞれプルリクエストを出しており、CI の遅さがそのまま開発の遅さになっている。

### 計測

2026-10-17 02:41 から 03:56（UTC）までの、成功した `ci.yml` の 12 回の実行（`main` への push が 5 回、プルリクエストが 7 回）を使った。
ID は 39000100253、38999490823、38999311090、38998726613、38998612031、38998164338、38997971219、38997820014、38997697580、38997203604、38997156174、38996552496 である。
ジョブとステップの所要時間は `gh run view <id> --json jobs` を `scripts/ci/timings.sh --median` に渡して求めた。
単位は秒である。

| ジョブ | ステップ | 最小 | 中央値 | 最大 |
|---|---|---|---|---|
| 実行全体（作成から完了まで） | | 431 | 506 | 610 |
| `build (ubuntu-24.04)` | ジョブ全体 | 308 | 449 | 510 |
| `build (ubuntu-24.04)` | apt-get（qpdf と epubcheck） | 16 | 19 | 29 |
| `build (ubuntu-24.04)` | `cabal build all peg-cli:exe:peg-hs` | 128 | 217 | 271 |
| `build (ubuntu-24.04)` | `cabal test all` | 55 | 78 | 88 |
| `build (ubuntu-24.04)` | マニュアルを組む | 26 | 37 | 43 |
| `build (ubuntu-24.04)` | epubcheck | 3 | 4 | 5 |
| `build (ubuntu-24.04)` | 決定性の検査の出力 | 25 | 36 | 42 |
| `build (ubuntu-24.04-arm)` | ジョブ全体 | 384 | 417 | 487 |
| `build (ubuntu-24.04-arm)` | apt-get（qpdf） | 14 | 16 | 24 |
| `build (ubuntu-24.04-arm)` | `cabal build all peg-cli:exe:peg-hs` | 187 | 221 | 272 |
| `build (ubuntu-24.04-arm)` | `cabal test all` | 54 | 55 | 64 |
| `build (ubuntu-24.04-arm)` | マニュアルを組む | 37 | 40 | 41 |
| `build (ubuntu-24.04-arm)` | 決定性の検査の出力 | 36 | 40 | 41 |
| `format` | ジョブ全体 | 60 | 88 | 97 |
| `format` | hlint の実行 | 46 | 73 | 80 |
| `changes` | ジョブ全体 | 8 | 10 | 14 |
| `release-scripts` | ジョブ全体 | 8 | 9 | 10 |
| `determinism` | ジョブ全体 | 3 | 4 | 6 |
| `ci` | ジョブ全体 | 4 | 7 | 7 |

キャッシュは、12 回のすべてで GHC、Hackage の索引、cabal の store、`dist-newstyle`（`restore-keys` での一致）、cddl の CLI、マニュアルのフォントが当たった。
`cabal update` と `cargo install cddl` は一度も走っていない。
ジョブが作られてから始まるまでの待ちは、x86-64 で 1 秒から 2 秒、aarch64 で 4 秒から 6 秒だった。
今のところ、ランナーの待ちは遅さの原因ではない。
`docs.yml` は 29 秒から 42 秒で終わり、`ci.yml` より先に結果が出る。

### わかったこと

時間の大きい順に並べる。

1. **`cabal build all` と `cabal test all` が、毎回すべてのパッケージを設定し直している。** 両方のステップのログで、`modules/` のすべてのパッケージに `(configuration changed)` が付いている。原因は、テストのスイートの時間の上限を入れた変更（[#174](https://github.com/tett23/golem/pull/174)）で `cabal test all` だけに付けた `--test-wrapper` である。テストの実行の設定はローカルのパッケージの設定の一部なので、`cabal build all`（付けない）と `cabal test all`（付ける）のあいだで設定が行き来する。`main` で保存する `dist-newstyle` は `cabal test all` の後の状態なので、次の実行の `cabal build all` がまた設定し直す。設定し直したパッケージは Cabal の `build` をやり直し、C と C++ のソースの再コンパイルの要否を更新時刻で決める（[ADR 0009](0009-ci-speed.md) の 2）。チェックアウトでソースの更新時刻が新しくなるので、golem-font は HarfBuzz と FreeType をすべてコンパイルし直す。三つの実行のログで、golem-font のライブラリのビルドは 175 秒から 196 秒かかっていた。`--test-wrapper` を付ける前の実行（38985663557）では、`cabal build all` は 14 秒、`cabal test all` は 45 秒だった。手元でも、C のソースとテストのスイートを持つ小さなパッケージで同じ行き来を再現し、`--test-wrapper` を `cabal.project.local` に書けば設定し直さないことを確かめた。
2. **マニュアルを二度組んでいる。**「The manuals build without diagnostics」のステップが `scripts/manual/build.sh` で二つのマニュアルを組み、そのあと `scripts/determinism.sh` が同じ `build.sh` でもう一度組んでハッシュを書く。`build.sh` は diagnostic が一つでも出れば失敗し、`determinism.sh` は `set -eu` なのでその失敗で止まる。前のステップの検査は、後のステップがすべて行っている。二つのアーキテクチャで、それぞれ約 37 秒を余分に使っている。
3. **apt-get を待っている。** qpdf と epubcheck の導入に 16 秒から 19 秒かかり、その間ほかのステップは進まない。qpdf と epubcheck を使うのはテストと epubcheck のステップだけで、ビルドは使わない。
4. **hlint が一つのコアで動いている。** format ジョブの hlint の実行が 73 秒かかる。format は臨界経路にはないが、そのぶんランナーを占める。八つの作業が同時にプルリクエストを出すと、ジョブの数は無料のプランの同時実行の上限（20）に近づく。
5. **テストのスイートで最も遅いのは golem-parser-test で、約 52 秒かかる。** cabal はスイートを並列に走らせているので、テストのステップの所要時間はこのスイートでほぼ決まる。スイートを分けるのはモジュールのコードの変更であり、この ADR では扱わない。

1 から 3 を除けば、x86-64 の build ジョブは 449 秒から 190 秒前後になると見積もる（golem-font を変えない変更のとき）。
golem-font を変える変更では、HarfBuzz のコンパイルの約 190 秒が加わる。

## 実装すること

### 1. テストのラッパーを `cabal.project.local` に書く

build ジョブの最初の方に、次の一行を `cabal.project.local` に書き足すステップを置く。

```
test-wrapper: <リポジトリの絶対パス>/scripts/ci/suite-timeout.sh
```

- 書き足すのは、wasmtime の取得（`scripts/fetch-wasmtime.sh`、同じファイルに `package golem-plugin` の節を書き足す）より前とする。トップレベルの欄が `package` の節の後ろに来ないようにするためである。
- `cabal test all` からは `--test-wrapper` を外す。これで `cabal build all`、`cabal test all`、`scripts/gen-parser.sh` の中の `cabal build`、`cabal list-bin` が、すべて同じ設定を読む。
- `scripts/ci/suite-timeout.sh` の働き（10 分で終わらないスイートを止めて失敗にする）と、テストのステップの `timeout-minutes: 20` は変えない。
- `cabal.project.local` は Git で管理しないファイルであり、キャッシュの鍵（`cabal.project` と `cabal.project.freeze` のハッシュ）には入らない。絶対パスはランナーの上で毎回同じ（`/home/runner/work/golem/golem`）である。

### 2. マニュアルを決定性の検査の出力のステップで一度だけ組む

- 「The manuals build without diagnostics」のステップを消す。
- 「Outputs for the determinism check」のステップの名前を「Outputs for the determinism check; the manuals build without diagnostics」にし、`scripts/determinism.sh` が `scripts/manual/build.sh` で二つのマニュアルを組むことをコメントに書く。
- マニュアルのフォントのキャッシュは、このステップより前に置いたままにする。
- 成果物 `manual` と `manual-dev` は、今と同じく、このステップが `manual/build` と `manual-dev/build` に残した出力を上げる。
- 二つのマニュアルが diagnostic を一つも出さずに組めることは、今と同じく二つのアーキテクチャで確かめる（[ADR 0022](0022-manual-as-typesetting-sample.md)、[ADR 0024](0024-manual-audiences-and-policy.md)）。

### 3. apt-get を裏で走らせる

`scripts/ci/bg.sh` を加える。

```
bg.sh start NAME COMMAND [ARGUMENTS...]
bg.sh wait NAME
```

- `start` は、コマンドを裏で走らせてすぐに終わる。コマンドの標準入力は `/dev/null`、標準出力と標準エラー出力は `BG_DIR/NAME.log` に書き、終わったら終了コードを `BG_DIR/NAME.code` に書く。`BG_DIR` の既定は `$RUNNER_TEMP/bg` とする。
- `wait` は、`NAME.code` ができるまで待ち、ログを書き出して、コマンドの終了コードで終わる。始めていない名前なら終了コード 2 で終わる。待つ時間の上限は持たず、呼ぶステップの `timeout-minutes` に任せる。
- 名前が空のもの、`/` を含むもの、`.` で始まるものは、終了コード 2 で拒む。

`scripts/ci/apt-install.sh PACKAGE...` を加え、今のステップの中身（man-db の索引の更新を止め、`apt-get update` と `apt-get install -y --no-install-recommends` を行う）を移す。

build ジョブは、チェックアウトの直後に `bg.sh start apt timeout -k 10 300 sh scripts/ci/apt-install.sh $PACKAGES` を実行し、`cabal build all` と `cabal test all` のあいだで `bg.sh wait apt` を実行する。
待つステップには `timeout-minutes: 5` を付ける。
ミラーが止まったときに 5 分で失敗させる今の上限（[ADR 0009](0009-ci-speed.md) の 8）は、`timeout 300` と待つステップの上限の両方で保つ。

### 4. hlint をすべてのコアで走らせる

format ジョブの hlint に `-j` を付ける。
検査する範囲と規則は変えない。

### 5. 計測の記録

実装の前の計測（上の表）を `docs/ci-timings/2026-10-17-before.md` に、実装の後の計測を `docs/ci-timings/` の新しいファイルに、`scripts/ci/timings.sh` で作って置く。
どちらもコミットした後は変更しない。

### ドキュメント

- README の CI の節の表の `build` の行を、マニュアルを決定性の検査の出力と一緒に組むことに合わせる。
- 開発者のマニュアルの CI のジョブの章（`manual-dev/part2/11-ci-jobs.gm`）の build の手順を、上の 1 から 3 に合わせ、設定し直しの行き来を避けるためにテストのラッパーを `cabal.project.local` に書くことを説明する。

## 実装しないこと

- **テストと決定性の検査の出力を並行に走らせること。** golem-driver のテストは `test/fixtures/sample` をディレクトリごと写し、golem-parser のテストは同じディレクトリを歩く。`scripts/determinism.sh` は同じディレクトリに `build/` を作っては消すので、並行に走らせるとテストが途中の `build/` を拾う。並行にするには木の写しの上で出力を作る必要があり、決定性の検査の手順を変えることになる。約 35 秒の短縮が見込めるので、必要になったら別の ADR で扱う。
- **ビルドの成果物を別のジョブに渡し、テスト、マニュアル、決定性の検査を別のジョブで並べること。** ジョブを足すたびに、ランナーの起動、キャッシュの復元、成果物の上げ下ろしが加わり、同時実行の枠も多く使う。今の重複はマニュアルの二度のビルドだけで、2 で消える。
- **アーキテクチャに依らない重い手順を x86-64 だけで走らせること。** 残る重い手順はビルド、テスト、決定性の検査の出力で、どれも両方のアーキテクチャで要る（[ADR 0001](0001-haskell-workspace-and-ci.md)、[ADR 0002](0002-determinism.md)、[ADR 0009](0009-ci-speed.md)）。epubcheck はすでに x86-64 だけで走る。
- **変更のパスでマニュアルや決定性の検査を省くこと。** `modules/` のどの変更も出力を変えうるので、省けるのは docs だけの変更であり、それは [ADR 0009](0009-ci-speed.md) と [ADR 0021](0021-docs-workflow-and-ci-gate.md) で省いている。
- **golem-parser-test を分けること。** モジュールのテストの変更であり、golem-parser の ADR で扱う。
- **`determinism` ジョブを `ci` ジョブにまとめること。** ジョブを一つ減らせば実行全体が 8 秒ほど短くなるが、[ADR 0021](0021-docs-workflow-and-ci-gate.md) の判定のジョブの形を変えることになる。
- **ソースの更新時刻をコミットの時刻にそろえること（[ADR 0009](0009-ci-speed.md) の `restore-mtime.sh`）。** 設定が変わらなければ、cabal-install は内容のハッシュで変更を判断し、更新時刻だけが新しいパッケージをビルドし直さない。手元で、ソースに `touch` をしてもビルドし直さないことを確かめた。
- **`cabal test` の並列の度合いを変えること。** cabal はすでにスイートをコアの数だけ並列に走らせている。

## テスト設計

### 先に書いて失敗させるテスト（`scripts/ci/test.sh`）

`bg.sh` について、一時ディレクトリを `BG_DIR` にして確かめる。

- 標準出力と標準エラー出力に一行ずつ書くコマンドを `start` し、`wait` が終了コード 0 で、その二行を書き出すこと。
- `exit 3` のコマンドの `wait` が、終了コード 3 で終わること。
- 2 秒眠ってから書くコマンドの `start` が、コマンドの終わる前（`NAME.code` がまだない状態）に終了コード 0 で戻り、`wait` がコマンドの終わりを待ってその出力を書くこと。
- 標準入力を読むコマンド（`cat`）が、入力を待たずに終わること。
- 始めていない名前の `wait`、コマンドのない `start`、`/` を含む名前、知らないサブコマンドが、終了コード 2 で終わること。

`apt-install.sh` について、引数がないときに終了コード 2 で終わること。

`ci.yml` について、次の二つを確かめる。

- `cabal build`、`cabal test`、`cabal run`、`cabal install`、`cabal list-bin` を呼ぶ行が、ローカルのパッケージの設定を変える引数（`--test-` や `--enable-` で始まるものなど）を持たないこと。今の `ci.yml` は `cabal test all --test-wrapper=...` を持つので失敗する。
- `scripts/ci/suite-timeout.sh` を `test-wrapper:` として `cabal.project.local` に書くこと。

### 自動テストにできないものの確かめ方

実装のプルリクエストで、次を確かめて結果をプルリクエストに書く。

- `cabal build all` のログで、そのプルリクエストが変えていないパッケージに `(configuration changed)` が付かず、golem-font のライブラリがビルドされないこと。`cabal test all` のログに `Configuring` が出ないこと。
- テストのラッパーが効いていること。`SUITE_TIMEOUT=1` をテストのステップに付けた一時的なコミットを push し、スイートが `did not finish in 1 seconds` で失敗することを見る。確かめたら、そのコミットを取り消す。
- マニュアルの diagnostic で build ジョブが失敗すること。`manual/manifest.toml` に `silence-notices` を書いた一時的なコミットを push し、決定性の検査の出力のステップが `scripts/manual/build.sh` のエラーで失敗することを見る。確かめたら、そのコミットを取り消す。
- 所要時間。キャッシュの冷えた実行（`dist-newstyle` のキャッシュが今の設定と食い違う最初の実行）と、温まった実行を、それぞれ `scripts/ci/timings.sh` で記録する。マージの後、`main` への push とプルリクエストの実行を 5 回以上集めて `--median` で中央値を取り、`docs/ci-timings/` に記録する。目標は、golem-font を変えないプルリクエストで実行全体が 5 分以内であることとする。

## トレードオフ

- CI の `cabal` は `cabal.project.local` のテストのラッパーを読み、手元の `cabal` は読まない。手元でラッパーを使いたいときは、同じ一行を自分の `cabal.project.local` に書けばよい。代わりに、CI の中のすべての `cabal` のコマンドが一つの設定を共有し、ラッパーを付け忘れたコマンドが設定を行き来させる危険がなくなる。
- マニュアルのビルドの失敗は、「Outputs for the determinism check; the manuals build without diagnostics」のステップの失敗として現れる。ステップの名前で二つの役割を示し、`build.sh` のエラーの文で原因がわかるようにする。
- apt-get のログは、始めたステップではなく、待つステップに出る。ミラーが止まった場合の失敗も待つステップに出る。時間の上限は今と同じ 5 分である。
- 裏で走るコマンドは、ステップの区切りを越えて動く。GitHub Actions は、ジョブの終わりに残ったプロセスを片付けるので、ビルドが失敗しても apt-get が残り続けることはない。
- hlint の `-j` は、指摘を書く順を変えうる。指摘の有無と内容は変わらない。

## 参考文献

- Cabal User Guide, "cabal.project Reference"（`cabal.project.local` と、テストの実行の欄 `test-wrapper`）. https://cabal.readthedocs.io/en/stable/cabal-project-description-file.html
- Cabal User Guide, "cabal test"（`--test-wrapper`）. https://cabal.readthedocs.io/en/stable/cabal-commands.html#cabal-test
- GitHub Docs, "Usage limits, billing, and administration"（無料のプランの同時実行の上限）. https://docs.github.com/en/actions/administering-github-actions/usage-limits-billing-and-administration
- hlint README（`-j` による並列の検査）. https://github.com/ndmitchell/hlint
- [#174](https://github.com/tett23/golem/pull/174)（テストのスイートの時間の上限と `--test-wrapper`）
- [ADR 0009](0009-ci-speed.md)、[ADR 0021](0021-docs-workflow-and-ci-gate.md)、[ADR 0022](0022-manual-as-typesetting-sample.md)、[ADR 0024](0024-manual-audiences-and-policy.md)
