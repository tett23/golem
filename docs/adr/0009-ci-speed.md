# ADR 0009: CI の高速化

ステータス: 採択→docs だけの変更を省く根拠は [docs/adr/0021](0021-docs-workflow-and-ci-gate.md)、プルリクエストでの `dist-newstyle` のキャッシュの保存は [docs/adr/0045](0045-split-x86-build-and-pull-request-cache.md)

## 文脈

[ADR 0001](0001-haskell-workspace-and-ci.md) で組んだ CI は、プルリクエストを一つ出すと、結果が出るまでに 8 分前後かかる。
ときどき 20 分を超える。
`.github/workflows/ci.yml` の `build` ジョブが x86-64 と aarch64 の両方で全体を毎回ビルドし、`determinism` ジョブがその二つを待つので、遅い方の `build` が全体の所要時間を決めている。

### 計測

2026-10-11 から 2026-10-12 までの `ci.yml` の 17 回の実行（`gh run view <id> --json jobs` で取得）から、ステップごとの所要時間（秒）をまとめた。
使った実行の ID は 38319536503、38318301629、38317046247、38315653147 から 38315677490 までの 8 回、38298507275、38296480961、38279316897、38237231913、38181469810 などである。

| ジョブ | ステップ | 最小 | 中央値 | 最大 |
|---|---|---|---|---|
| build (x86-64) | ジョブ全体 | 397 | 491 | 1603 |
| build (x86-64) | `haskell-actions/setup`（GHC の導入と `cabal update`） | 108 | 130 | 155 |
| build (x86-64) | `actions/cache`（cabal の store） | 1 | 3 | 4 |
| build (x86-64) | wasmtime の取得 | 1 | 1 | 3 |
| build (x86-64) | apt-get（qpdf と epubcheck） | 16 | 23 | 1144 |
| build (x86-64) | `cargo install cddl` | 45 | 62 | 78 |
| build (x86-64) | `cabal build all` | 168 | 220 | 1192 |
| build (x86-64) | `cabal test all` | 9 | 14 | 42 |
| build (x86-64) | パーサーの再生成の検査 | 0 | 16 | 36 |
| build (x86-64) | epubcheck | 0 | 4 | 5 |
| build (aarch64) | ジョブ全体 | 422 | 458 | 1086 |
| build (aarch64) | `haskell-actions/setup` | 117 | 125 | 135 |
| build (aarch64) | apt-get | 21 | 28 | 39 |
| build (aarch64) | `cargo install cddl` | 47 | 51 | 58 |
| build (aarch64) | `cabal build all` | 197 | 210 | 845 |
| build (aarch64) | `cabal test all` | 6 | 10 | 34 |
| format | ジョブ全体 | 143 | 168 | 802 |
| format | `haskell-actions/setup` | 117 | 130 | 139 |
| format | hlint のインストール（キャッシュあり） | 3 | 4 | 649 |
| format | hlint の実行 | 12 | 20 | 28 |
| adr | ジョブ全体 | 5 | 6 | 8 |
| release-scripts | ジョブ全体 | 4 | 7 | 7 |
| determinism | ジョブ全体 | 0 | 4 | 6 |

ログを読んでわかったことを、時間の大きい順に並べる。

- `cabal build all` の 200 秒前後のうち、約 190 秒は golem-font のライブラリのビルドである。golem-font は HarfBuzz を一つの翻訳単位（`cbits/harfbuzz/src/harfbuzz-world.cc`）としてコンパイルする（[golem-font ADR 0001](../golem-font/adr/0001-shaping-and-metrics.md)）。golem-driver、golem-lsp、golem-cli はこれを待つので、golem-font がビルドの臨界経路になる。キャッシュするのは cabal の store だけで、`dist-newstyle` はキャッシュしていない。そのため、自前のパッケージは毎回すべて「first run」としてビルドされる。
- `haskell-actions/setup` の 130 秒のうち、約 118 秒は GHC 9.10.3 の導入である。ランナーのイメージには GHC 9.10.3 が入っていないので、ghcup が配布物を取得して展開し、インストールする。取得は 1 秒ほどで、残りは展開とインストールにかかる。残りの約 17 秒は `cabal update` である。format ジョブは hlint を動かすためだけに、この 130 秒を払っている。
- `cargo install cddl` は、golem-doc のテストの一件（「CBOR conforms to the CDDL」、実行は 0.01 秒）のために、毎回 Rust のクレートを約 80 個コンパイルしている。
- store のキャッシュの `restore-keys` が `cabal-ubuntu-24.04-` なので、x86-64 のジョブが aarch64 のキャッシュ（`cabal-ubuntu-24.04-arm-…`）を前方一致で復元することがある。実行 38279316897 の x86-64 では aarch64 の store を復元し、依存の約 200 個をビルドし直して `cabal build all` に 1104 秒かかった。20 分を超えた実行の多くは、このキャッシュの取り違えか、freeze ファイルの変更による store のキャッシュの不一致である。
- `cabal test all` は、テストスイートを並列に実行している。最も遅いのは golem-parser-test で、[golem-parser ADR 0007](../golem-parser/adr/0007-grammar-label-safety.md) の「the fixtures and their mutations」の一件が CI で約 27 秒（手元の macOS で 17 秒）かかる。テストの実行ファイルは `-threaded` を付けていないので、tasty は一つのスイートの中のテストを並列に走らせない。
- パーサーの再生成の検査は 16 秒から 36 秒かかるが、手元で `scripts/gen-parser.sh` を実行すると、ビルド済みの状態で 0.8 秒で終わる。生成そのものではなく、`cabal build -v0 peg-cli:exe:peg-hs` の計画とビルドに時間を使っていると推測する。`-v0` のせいでログからは内訳がわからない。
- apt-get は 44 個のパッケージ（82MB、ほとんどが epubcheck の Java）を入れ、約 7 秒が `apt-get update`、残りが展開と設定である。実行 38237231913 では apt のミラーが止まり、1144 秒かかった。
- 2026-10-12 22:16 に積み重ねたプルリクエストを 9 本同時に走らせたとき（ジョブは合わせて 45 個）、各ジョブの開始の待ちは 2 秒から 8 秒だった。公開リポジトリの同時実行の上限には届いておらず、待ちは遅さの原因ではない。
- キャッシュは 33 個、合わせて約 3.7GB ある。プルリクエストごとに store のキャッシュ（約 90MB と 120MB）が `refs/pull/N/merge` の範囲で保存されているが、ほかのプルリクエストからは使えない。
- リポジトリは公開で、`main` に保護の規則（required checks）は設定されていない。リポジトリの持ち主は個人のアカウントである。

## 実装すること

効果の大きい順に並べる。
見積もりは、上の計測の中央値からの推定であり、実装の後に計測で確かめる。

### 1. store のキャッシュの鍵を直す

`build` ジョブの store のキャッシュの鍵を、次の形にする。

```yaml
key: cabal-store-${{ runner.os }}-${{ runner.arch }}-ghc-${{ env.GHC_VERSION }}-${{ hashFiles('cabal.project', 'cabal.project.freeze') }}
restore-keys: cabal-store-${{ runner.os }}-${{ runner.arch }}-ghc-${{ env.GHC_VERSION }}-
```

`runner.arch` の値は `X64` と `ARM64` で、どちらも他方の前方一致にならないので、アーキテクチャの取り違えが起きない。
GHC の版は、ワークフローの先頭の `env.GHC_VERSION: "9.10.3"` に一度だけ書き、`haskell-actions/setup` の `ghc-version` と鍵の両方から参照する。
store のキャッシュは、今と同じく鍵が一致しなかったときに保存する。
store は freeze ファイルが変わったときにしか増えないので、プルリクエストで保存しても量は小さい。

効果：中央値は変わらない。依存の約 200 個をビルドし直す 15 分から 20 分の外れ値がなくなる。

### 2. `dist-newstyle` をキャッシュする

`cabal build` の前に `actions/cache/restore@v6` で `dist-newstyle` を復元し、テストと検査の後に `actions/cache/save@v6` で保存する。

```yaml
key: dist-${{ runner.os }}-${{ runner.arch }}-ghc-${{ env.GHC_VERSION }}-${{ hashFiles('cabal.project', 'cabal.project.freeze') }}-${{ github.sha }}
restore-keys: dist-${{ runner.os }}-${{ runner.arch }}-ghc-${{ env.GHC_VERSION }}-${{ hashFiles('cabal.project', 'cabal.project.freeze') }}-
```

- 保存は `main` への push のときだけ行う（`if: success() && github.event_name == 'push' && github.ref == 'refs/heads/main'`）。プルリクエストの実行で保存したキャッシュはそのプルリクエストからしか使えず、コミットごとに鍵が変わるので、容量を食うだけである。
- `restore-keys` は依存のハッシュまでを含める。依存が変わると、自前のパッケージは設定のハッシュが変わってどのみちビルドし直しになり、古い `dist-newstyle` を復元しても容量と復元の時間を使うだけである。
- 復元した `dist-newstyle` の上で、cabal-install は変わっていないパッケージのビルドを省く。GHC 9.4 以降はモジュールの再コンパイルの要否をソースのハッシュで判断するので、チェックアウトで更新時刻が新しくなっても Haskell のモジュールはコンパイルし直さない。
- ただし Cabal は、C と C++ のソースの再コンパイルの要否を更新時刻で判断する。golem-font のソースが変わったときは、チェックアウトで更新時刻が新しくなった HarfBuzz と FreeType も、すべてコンパイルし直される。golem-font が変わる頻度は低いので、これは受け入れる。
- golem-font が変わっていないのに golem-font がビルドし直される場合（ログに `Building library for golem-font` が出る場合）は、cabal-install のパッケージの変更の検出も更新時刻に頼っていることになる。そのときは `scripts/ci/restore-mtime.sh` を加える。これは `git log --format=%ct --name-only` を一度だけ読み、`modules/` の下の各ファイルの更新時刻を、そのファイルを最後に変えたコミットの時刻に設定する。チェックアウトの直後、復元の前に実行する。どちらになったかは、計測の記録（下の「確かめ方」）に書く。

効果：golem-font が変わらない変更では、`cabal build all` が 220 秒から、変更したパッケージとそれに依存するパッケージのビルドだけ（30 秒から 60 秒と推定）になる。両方のアーキテクチャで約 160 秒短くなる。

### 3. GHC をキャッシュする

`haskell-actions/setup` の前に、ghcup が GHC を入れるディレクトリ `/usr/local/.ghcup/ghc/${GHC_VERSION}` を `actions/cache@v6` で復元する。

```yaml
key: ghc-${{ env.GHC_VERSION }}-${{ runner.os }}-${{ runner.arch }}-${{ env.ImageOS }}
```

- `ImageOS`（`ubuntu24` など）を鍵に含める。GHC の配布物はシステムの共有ライブラリ（libgmp など）にリンクするので、イメージの OS が変わったら入れ直す。
- `haskell-actions/setup` は、最初に `ghcup whereis ghc` で導入済みかを調べ、見つかれば `ghcup set ghc` だけを行う。ディレクトリが復元されていれば、ログに `Installing ghc` が出ずに `Found ghc 9.10.3 in cache` が出る。出ない場合（ghcup が導入済みと認めない場合）は、`haskell-actions/setup` の前に `ghcup set ghc ${GHC_VERSION}` を実行する手順を足して確かめ、結果を計測の記録に書く。
- `haskell-actions/setup` に `cabal-update: false` を渡し、Hackage の索引（`~/.cabal/packages/hackage.haskell.org`）を `actions/cache@v6` でキャッシュする。鍵は `hackage-index-${{ hashFiles('cabal.project.freeze') }}` とする。freeze ファイルの `index-state` が変わったら鍵が変わる。鍵が一致しなかったときだけ `cabal update` を実行するステップを置く。

効果：`haskell-actions/setup` の 130 秒が、GHC と索引の復元（合わせて 20 秒前後と推定）になる。build の二つのジョブで約 110 秒短くなる。GHC のキャッシュの大きさは未計測であり、計測の記録に書く。

### 4. format ジョブから GHC をなくす

format ジョブは `haskell-actions/setup`、store のキャッシュ、`cabal install hlint-3.10` をやめ、hlint の配布物を取得する。

- `scripts/ci/fetch-hlint.sh` を加える。ndmitchell/hlint の v3.10 のリリースにある `hlint-3.10-x86_64-linux.tar.gz` を取得し、SHA-256 を検査して展開し、`hlint` を `$HOME/.local/bin` に置く。SHA-256 は実装者が配布物を一度取得して調べ、スクリプトに書く。書き方は `scripts/fetch-wasmtime.sh` に合わせる。
- 配布物に同梱のデータ（`data/hlint.yaml` など）が実行ファイルから見つからない場合は、`--datadir` で展開先の `data` を渡す。
- hlint の版は 3.10 のまま変えない。配布物は x86-64 の Linux だけにあり、format ジョブは `ubuntu-24.04`（x86-64）で動くので足りる。
- `haskell-actions/hlint-setup` は使わない。最新の v2.4.10 は `runs.using` が `node20` であり、Node 24 以降で動くアクションを使う方針（CONTRIBUTING.md）に合わない。

効果：format ジョブが 168 秒から 30 秒前後（fourmolu、hlint の取得と実行）になる。format は臨界経路にはないが、ランナーの時間が減る。hlint の取得は 1 回あたり数 MB の通信である。

### 5. cddl の CLI をキャッシュする

`~/.cargo/bin/cddl` を `actions/cache@v6` でキャッシュし、鍵が一致しなかったときだけ `cargo install cddl --version ${CDDL_VERSION} --locked` を実行する。

```yaml
key: cddl-${{ env.CDDL_VERSION }}-${{ runner.os }}-${{ runner.arch }}-${{ env.ImageOS }}
```

anweiss/cddl の v0.10.7 のリリースには `cddl-linux-amd64.tar.gz` しかなく、aarch64 の Linux の配布物がない。
二つのアーキテクチャで同じ手順にするため、配布物の取得ではなくキャッシュにする。
README の「CI では必ず実行する」は変わらない。

効果：両方の build で約 55 秒短くなる。

### 6. パーサーの再生成の検査を本体のビルドに含める

`cabal build all` を `cabal build all peg-cli:exe:peg-hs` に変える。
peg-cli の実行ファイルが本体と同じビルドの計画に入り、HarfBuzz のコンパイルと並行してビルドされる。
`scripts/gen-parser.sh` の中の `cabal build -v0 peg-cli:exe:peg-hs` は、ビルド済みなら計画を確かめるだけで終わる。
スクリプト自体は手元での手順でもあるので変えない。

効果：検査のステップが 16 秒から 36 秒から、数秒になると推定する。推定の根拠は手元での 0.8 秒という計測だけなので、実装の後の計測で確かめる。

### 7. ラベルの比較のテストを分けて並列に走らせる

golem-parser-test の「the fixtures and their mutations」を、入力の並びを 4 つに分けた 4 つの `testCase` にする（`modules/golem-parser/test/LabelSafetySpec.hs`）。

- 入力の並び（fixture の原文と、`mutations` で作った変異）は今と同じに作る。
- i 番目の `testCase`（i は 0 から 3）は、並びの添字を 4 で割った余りが i の入力だけを `allAgree` で確かめる。名前は「the fixtures and their mutations (part 1 of 4)」のようにする。
- `modules/golem-parser/golem-parser.cabal` の `test-suite golem-parser-test` に `ghc-options: -threaded -rtsopts "-with-rtsopts=-N"` を加え、tasty が 4 つのテストを並列に走らせるようにする。
- 分けても、確かめる入力の集合は [golem-parser ADR 0007](../golem-parser/adr/0007-grammar-label-safety.md) のテスト設計のとおりで、変わらない。

ランナーは 4 コアであり、ほかのテストスイートは 15 秒ほどで終わるので、その後は golem-parser-test がコアを使える。

効果：golem-parser-test が 32 秒から 12 秒前後、`cabal test all` が 34 秒から 42 秒から 20 秒前後になると推定する。

### 8. epubcheck を x86-64 だけで走らせ、apt-get を軽くする

- 「The EPUB passes epubcheck」のステップと epubcheck の導入を、x86-64 のジョブだけで行う（`if: matrix.runner == 'ubuntu-24.04'`）。aarch64 の EPUB は、`determinism` ジョブが `scripts/determinism.sh` の出力（同じ `sample` の EPUB を含む）のハッシュで x86-64 と一致することを確かめるので、epubcheck の結果も同じになる。
- aarch64 では qpdf だけを入れる。golem-driver のテストの `qpdfCheck` が qpdf を使うので、両方に要る。
- `apt-get install` に `--no-install-recommends` を付け、その前に `echo 'man-db man-db/auto-update boolean false' | sudo debconf-set-selections` で man-db の索引の更新を止める。
- apt-get のステップに `timeout-minutes: 5` を付ける。ミラーが止まったときに 19 分待たずに失敗させ、再実行で回復させる。

効果：aarch64 で 20 秒前後、x86-64 で数秒短くなると推定する。

### 9. 変更のないジョブを省く

ジョブ `changes` を加え、ほかのジョブより先に走らせる。

- `scripts/ci/needs-build.sh` を加える。標準入力から改行で区切ったパスの並びを読み、ビルドが要れば `true`、要らなければ `false` を標準出力に書く。
- ビルドが要らないのは、すべてのパスが `docs/` の下か、リポジトリの根にある `.md` のファイル（`README.md`、`CONTRIBUTING.md`、`CONTRIBUTING.en.md` など）である場合だけとする。`modules/` の下の `.md` は、テストのデータ（`modules/golem-layout/test/data/knuth-plass/README.md` など）なので、ビルドが要る側に数える。
- 入力が空のときは `true` を書く。差分が取れないときに検査を省かないためである。
- `changes` ジョブは、イベントに応じて差分の範囲を決め、`git -c core.quotePath=false diff --name-only BASE HEAD` の結果をスクリプトに渡し、結果を出力 `build` にする。プルリクエストでは `pull_request.base.sha` と `pull_request.head.sha`、`main` への push では `github.event.before` と `github.sha` を使う。`github.event.before` がすべて 0 の場合と、`workflow_call`（release.yml からの呼び出し）と、それ以外のイベントでは、差分を取らずに `true` とする。チェックアウトは `fetch-depth: 0` で行う。
- `changes` ジョブは、出力を計算する前に `scripts/ci/test.sh`（下のテスト設計）を実行する。
- `build`、`format`、`release-scripts` に `needs: changes` と `if: needs.changes.outputs.build == 'true'` を付ける。`determinism` は `build` を `needs` に持つので、`build` を省くと一緒に省かれる。
- `adr` ジョブは、変更のパスにかかわらず常に走らせる。ADR の変更を検査するジョブであり、docs だけの変更こそが対象だからである。

docs だけの変更を省いてよい根拠は、どのテストも `docs/` の下のファイルを読まないことである（`modules/*/test` で `docs/` を参照しているのはテストの名前の文字列だけであることを grep で確かめた）。
`scripts/determinism.sh` の入力も `scripts/determinism`、`modules/golem-driver/test/fixtures`、`modules/golem-font/test/fonts` だけである。

GitHub の required checks は、今は設定されていない。
将来設定しても、ジョブの `if` で省かれたジョブは「skipped」となり、必須の検査を満たしたものとして扱われる。
ワークフロー全体の `paths` の絞り込みを使わないのは、ワークフローが走らないと必須の検査が「待ち」のまま残り、マージできなくなるからである。

効果：docs だけの変更では、CI が 8 分前後から 10 秒前後（`adr` と `changes`）になる。

### 10. 同じプルリクエストの古い実行を取り消す

ワークフローの先頭に次の `concurrency` を置く。

```yaml
concurrency:
  group: ${{ github.event_name == 'pull_request' && format('ci-pr-{0}', github.event.pull_request.number) || format('ci-run-{0}', github.run_id) }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
```

- プルリクエストに新しいコミットを push すると、同じプルリクエストの走っている実行を取り消す。2026-10-12 には `pr/label-safety-test` に 6 分の間隔で 2 回 push し、2 回とも最後まで走った。
- `main` への push と `workflow_call` では、実行ごとに別の組（`github.run_id`）にして、取り消しも待ちも起こさない。同じ組に入れると、待っている実行が新しい実行に置き換えられ、`main` の一部のコミットが検査されなくなるからである。
- `push` は `main` だけを対象にしているので、プルリクエストのブランチで push と pull_request が重なって二度走ることは、今もない。

計測では同時実行の待ちが 8 秒以内だったので、この変更が短くするのは結果が出るまでの時間ではなく、ランナーの使用時間である。

### 11. ジョブの上限の時間

`build` に `timeout-minutes: 30`、`format` に `timeout-minutes: 10` を付ける。
キャッシュがすべて外れた最悪の場合の実績（`build` で 27 分）を上限の目安にした。

### 新しいアクション

使うアクションは、`actions/cache@v6`（v6.1.0）と、その `restore` と `save`（`actions/cache/restore@v6`、`actions/cache/save@v6`）だけを新たに加える。
どれも `runs.using` が `node24` であることを確かめた。
`haskell-actions/setup@v2`（v2.12.1、`node24`）、`actions/checkout@v7`、`actions/upload-artifact@v7`、`actions/download-artifact@v8` は今のままとする。
変更のパスの判定に dorny/paths-filter などのアクションを使わないのは、必要な機能が `git diff` と十数行のシェルで足り、再実装を優先する方針に合うからである。

### 計測の記録のためのスクリプト

`scripts/ci/timings.sh` を加える。
`gh run view <id> --json jobs` の JSON を標準入力から読み、ジョブとステップごとの所要時間（秒）を Markdown の表として書く。
所要時間は `startedAt` と `completedAt` の差である。
`--median` を付けると、一行に一つの実行の JSON を並べた入力を読み、ジョブとステップごとの最小、中央値、最大を書く。

### ドキュメント

- README の CI の節の表に `changes` ジョブを加え、docs だけの変更では `build`、`determinism`、`format`、`release-scripts` を省くこと、`adr` は常に走ることを書く。
- README の hlint の説明に、CI では hlint の配布物を使うことを書く。

## 実装しないこと

- 大きいランナー（larger runners）。リポジトリの持ち主が個人のアカウントであり、大きいランナーは Team か Enterprise Cloud の組織でしか使えない。使えたとしても、公開リポジトリで無料の標準のランナーと違い、分単位で課金される。さらに、今の臨界経路は HarfBuzz の一つの翻訳単位のコンパイルで、コアを増やしても短くならない。
- aarch64 の `build` を省くこと、または `main` への push だけで走らせること。決定性の検査には両方の出力が要り、プルリクエストの段階で不一致を見つけられなくなる（[ADR 0001](0001-haskell-workspace-and-ci.md)、[ADR 0002](0002-determinism.md)）。
- HarfBuzz と FreeType を別のパッケージに切り出すこと。golem-font の Haskell のコードを変えたときにも HarfBuzz をコンパイルし直さずに済むが、golem-font のパッケージの構成を変える変更であり、golem-font の ADR で扱う。
- HarfBuzz の翻訳単位を分けて並列にコンパイルすること。[golem-font ADR 0001](../golem-font/adr/0001-shaping-and-metrics.md) で決めた同梱の方法を変えることになる。
- GHC を含むコンテナの中でジョブを動かすこと。イメージの取得に GHC のキャッシュの復元と同じ程度の時間がかかると見込まれ、apt-get で入れているものもイメージに合わせ直す必要がある。
- `cabal test` の `--test-show-details` の変更。出力の形を変えるだけで、時間には効かない。
- プルリクエストを積み重ねたときに、同じ変更を何度もビルドしないようにすること。積み重ねた各プルリクエストのマージ先のコミットはそれぞれ違うので、同じコミットを二度ビルドしてはいない。マージの後の `main` への push は、`dist-newstyle` のキャッシュを保存するために要る。
- 古い `dist-newstyle` のキャッシュを消すジョブ。GitHub は容量（リポジトリあたり 10GB）を超えると、最後に使われたのが古いものから消す。GHC と store のキャッシュは毎回使われるので残る。

## テスト設計

### 先に書いて失敗させるテスト

`scripts/ci/test.sh` を加える。
書き方は `scripts/release/test.sh` に合わせ、`changes` ジョブで実行する。

`scripts/ci/needs-build.sh` について、標準入力と期待する出力を並べる。

| 標準入力 | 期待する出力 |
|---|---|
| 空 | `true` |
| `docs/adr/0009-ci-speed.md` | `false` |
| `README.md` と `CONTRIBUTING.en.md` | `false` |
| `docs/specifications.md` と `docs/golem-pdf/adr/0005-producer.md` | `false` |
| `docs/specifications.md` と `modules/golem-font/src/Golem/Font.hs` | `true` |
| `.github/workflows/ci.yml` | `true` |
| `scripts/determinism.sh` | `true` |
| `modules/golem-layout/test/data/knuth-plass/README.md` | `true` |
| `VERSION` | `true` |
| `docsx/a.md` | `true` |
| `docs`（ディレクトリと同じ名前のファイル） | `true` |
| 空白を含むパス `docs/a b.md` | `false` |
| 末尾に改行のない `docs/a.md` | `false` |

`scripts/ci/timings.sh` について、`scripts/ci/testdata/run.json`（実行 38319536503 の `gh run view --json jobs` の出力を縮めたもの）を入力にして、表の行が期待どおりであることを確かめる。
`completedAt` が `0001-01-01T00:00:00Z`（取り消されたステップ）の行は、所要時間を `-` と書くことを確かめる。

golem-parser-test は、分けた 4 つのテストの入力を合わせたものが、分ける前の入力の並びと同じ集合になることを確かめるテストを `LabelSafetySpec` に加える。
分ける関数（`shard :: Int -> Int -> [a] -> [a]` のような純粋な関数）に対する性質のテストとして書く。

### 自動テストにできないものの確かめ方

ワークフローの挙動は、実装のプルリクエストとその後の実行で確かめ、結果を計測の記録に書く。

- golem-driver だけを変えたプルリクエストで、ログに `Building library for golem-font` が出ないこと（`dist-newstyle` の復元が効いていること）。
- golem-font の `src/Golem/Font.hs` だけを変えたプルリクエストで、golem-font とそれに依存するパッケージだけがビルドされること。
- `haskell-actions/setup` のログに `Installing ghc` が出ず、`Found ghc 9.10.3 in cache` が出ること。
- x86-64 のジョブが `cabal-store-Linux-X64-` で始まる鍵だけを復元し、aarch64 のジョブが `cabal-store-Linux-ARM64-` で始まる鍵だけを復元すること。
- docs だけを変えたプルリクエストで、`adr` と `changes` が走り、`build`、`determinism`、`format`、`release-scripts` が skipped になること。
- 同じプルリクエストに続けて二度 push すると、先の実行が取り消されること。
- `main` に二つのマージを続けたとき、どちらの実行も取り消されないこと。
- release.yml を `workflow_dispatch` で走らせ、`ci` の中の `build` と `determinism` が省かれずに走ること。
- format ジョブで、hlint の警告を一つ含む変更が失敗すること（hlint の配布物に替えても検査が働くこと）。
- aarch64 のジョブに epubcheck の導入とステップがなく、x86-64 のジョブにはあること。
- `actions/cache` の一覧（`gh api repos/tett23/golem/actions/caches`）で、`dist-` で始まるキャッシュが `refs/heads/main` にだけあること。

### 確かめ方（計測の記録）

計測のスナップショットを `docs/ci-timings/` に置く。
コミットした後は変更しない。

- 実装の前に、`docs/ci-timings/2026-10-13-before.md` を作る。上の「計測」の節の 17 回の実行の ID と、`scripts/ci/timings.sh --median` の出力（ジョブとステップごとの最小、中央値、最大）を書く。
- 実装をマージした後に、次の 4 種類の実行をそれぞれ 3 回以上集め、`docs/ci-timings/<日付>-after.md` に同じ形で書く。golem-font 以外のパッケージを変えるプルリクエスト、golem-font を変えるプルリクエスト、docs だけのプルリクエスト、`main` への push である。
- after の記録には、キャッシュの大きさ（GHC、store、`dist-newstyle`、索引、cddl）と、`scripts/ci/restore-mtime.sh` と `ghcup set` の手順が要ったかどうかも書く。
- 目標は、golem-font 以外を変えるプルリクエストで、ワークフローの開始から `determinism` の終わりまでが中央値で 4 分以内になることとする。届かなかった場合は、どのステップが見積もりから外れたかを after の記録に書き、別の ADR で扱う。

## トレードオフ

見積もりをまとめる。
いずれも計測の中央値からの推定で、golem-font 以外を変えるプルリクエストの x86-64 の `build` についての値である。

| ステップ | 今の中央値（秒） | 見積もり（秒） |
|---|---|---|
| GHC の導入と `cabal update` | 130 | 20 |
| apt-get | 23 | 15 |
| cddl | 62 | 2 |
| `cabal build all` | 220 | 30 から 60 |
| `cabal test all`（最近の 3 回） | 34 から 42 | 20 |
| パーサーの再生成の検査（最近の 3 回） | 30 から 36 | 5 |
| ジョブ全体 | 491 | 110 から 140 |

キャッシュを増やすと、ビルドの結果がキャッシュの中身に依存する。
`dist-newstyle` の中の古い成果物を cabal が誤って使えば、壊れたコードがテストを通りうる。
cabal-install と GHC の変更の検出を信頼し、依存が変わったら `dist-newstyle` を復元しない鍵の作りで危険を減らす。
リリースの配布物は release.yml で Alpine のコンテナの中で一からビルドするので、キャッシュの誤りが配布物に入ることはない。

GHC のキャッシュは、ghcup の導入先の内部の構成（`/usr/local/.ghcup/ghc/<版>`）に依存する。
ランナーのイメージや `haskell-actions/setup` の更新で構成が変わると、キャッシュが効かなくなり、今と同じ 130 秒に戻る。
失敗するのではなく遅くなるだけなので、受け入れる。

docs だけの変更でビルドを省くと、`docs/` を読むテストを将来足したときに、そのテストが docs の変更で走らなくなる。
`scripts/ci/needs-build.sh` の判定をパスの許可の一覧（docs と根の `.md`）にして、それ以外はすべてビルドする側に倒すことで、取りこぼしを最小にする。

hlint をリリースの配布物から取得すると、hlint の実行ファイルは Golem の freeze ファイルとは無関係に、hlint の作者のビルドしたものになる。
今も hlint は freeze ファイルの外で `cabal install` しているので、版を 3.10 に固定している点は変わらない。

`dist-newstyle` の保存を `main` への push に限るので、依存を変えるプルリクエストでは、push のたびに自前のパッケージをすべてビルドし直す。
依存を変えるプルリクエストは少ないので、受け入れる。
