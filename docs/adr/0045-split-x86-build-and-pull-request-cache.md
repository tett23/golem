# ADR 0045: x86-64 の build をテストと出力の二つのランナーに分け、プルリクエストの dist-newstyle を残す

ステータス: 採択

## 文脈

`CONTRIBUTING.md` は、CI の実行時間を 5 分以内に保つと定めている。
[ADR 0037](0037-ci-build-job-speedup.md) と [ADR 0038](0038-env-determinism-quick-on-pull-requests.md) の後も、`ci.yml` の一回の実行は 5 分前後かかる。
2026-10-19 には八つの実装の作業が並んでプルリクエストを出しており、CI の待ちがそのまま開発の待ちになっている。

### 計測

[ADR 0038](0038-env-determinism-quick-on-pull-requests.md) のマージ（2026-10-19T11:45Z ごろ）の後の、`build` ジョブまで走った `ci.yml` の実行を使った。
所要時間は `gh run view <id> --json jobs` を `scripts/ci/timings.sh` に渡して求めた。
単位は秒である。

プルリクエストは 9 回（39247407032、39251361598、39251538227、39252017770、39252760432、39254269013、39254577100、39254804855、39254909536）、`main` への push は 6 回（39247249910、39247839279、39252044974、39252812858、39255052610、39255221098）である。

| 実行 | 件数 | 実行全体（最小／中央値／最大） | x86-64 の `build` | aarch64 の `build` | x86-64 の `cabal build` | x86-64 の `cabal test` |
|---|---|---|---|---|---|---|
| プルリクエスト | 9 | 191／306／362 | 154／264／322 | 119／217／252 | 15／123／181 | 48／66／72 |
| `main` への push | 6 | 317／379／458 | 275／340／418 | 127／201／283 | 17／96.5／169 | 52／65／71 |

`cabal build` の中央値が大きいのは、並んだ作業がモジュールを変え、マージのたびに `main` のキャッシュとプルリクエストのマージコミットの差が広がるからである。

x86-64 の `build` ジョブが、どの実行でも臨界経路にある。
その中身は、上のプルリクエストの 9 回では次のとおりである。

| ステップ | 秒 |
|---|---|
| ランナーの準備とキャッシュの復元（GHC、Hackage の索引、cabal の store、`dist-newstyle`、wasmtime、cddl） | 約 45 |
| `cabal build all peg-cli:exe:peg-hs` | 15 から 181（中央値 123） |
| `cabal test all` | 48 から 72（中央値 66） |
| epubcheck | 3 から 5 |
| 決定性の検査の出力（二つのマニュアルを含む） | 16 から 23（中央値 21） |
| 環境を変える検査（`--quick`） | 6 から 8 |

`main` への push では、環境を変える検査がすべての入力を使うので、このステップが 88 秒から 117 秒（中央値 108.5 秒）になる。
aarch64 の `build` ジョブは、環境を変える検査と epubcheck を持たず、テストも x86-64 より 10 秒ほど短い。

### 試したこと

下書きのプルリクエスト [#249](https://github.com/tett23/golem/pull/249) で、次の三つを試した。

#### テストと出力を同じランナーで同時に走らせる

[ADR 0037](0037-ci-build-job-speedup.md) は、テストと決定性の検査の出力を並行に走らせると約 35 秒縮むと見積もり、別の ADR に回していた。
コミットの写し（`git worktree`）の上で出力を作り、`scripts/ci/bg.sh` で `cabal test all` と同時に走らせた。
テストは `modules/golem-driver/test/fixtures/sample` をディレクトリごと写すので、元の木で出力を作ると途中の `build/` を拾うからである。

結果は、縮まなかった。

| 実行 | x86-64 の `cabal test all` | 出力を待つ時間 | 合計 | 同じ仕事を順に走らせた場合 |
|---|---|---|---|---|
| 39250273135（プルリクエスト） | 89 | 0 | 89 | 約 86 |
| 39250950057（同、出力を `nice -n 19` で） | 86 | 4 | 90 | 約 86 |
| 39253109275（同、環境を変える検査をすべての入力で） | 97 | 96 | 193 | 約 189 |

テストのスイートは `-threaded` と `-with-rtsopts=-N` でビルドされ、tasty はケースをコアの数だけ並べて走らせる。
golem の出力の作成も同じく `-N` で走る。
どちらもランナーの四つのコアを使い切るので、同じランナーで重ねても、二つの仕事が互いに遅くなるだけである。
`nice` で出力の優先度を下げても、出力が後ろにずれるだけで合計は変わらなかった。

#### x86-64 の build を二つのランナーに分ける

コアが足りないなら、ランナーを足せばよい。
x86-64 の `build` を、行列の二つの組み合わせに分けた。
どちらも同じコミットをビルドし、一方（`tests`）がテストと生成したパーサーの検査を、もう一方（`outputs`）が epubcheck、決定性の検査の出力、二つのマニュアル、環境を変える検査を受け持つ。
aarch64 は一つのランナー（`all`）のままにした。

| 実行 | 条件 | 実行全体 | `build (ubuntu-24.04, tests)` | `build (ubuntu-24.04, outputs)` | `build (ubuntu-24.04-arm, all)` |
|---|---|---|---|---|---|
| 39254966773 | golem-layout の一時的な変更を戻した（ビルドし直し 46 から 63 秒） | 238 | 191 | 130 | 165 |
| 39255843132 | `main` に golem-doc などの変更が入った後（ビルドし直し 129 から 182 秒） | 337 | 294 | 253 | 254 |
| 39256667333 | モジュールの変更なし（プルリクエストのキャッシュから） | 175 | 119 | 111 | 131 |
| 39257150661 | モジュールの変更なし（同） | 170 | 124 | 108 | 128 |
| 39257618402 | モジュールの変更なし（同） | 195 | 124 | 110 | 149 |

モジュールの変更がない場合で比べると、基準の実行（39247407032 の 191 秒、39251538227 の 216 秒）に対して、分けた後は 170 秒、175 秒、195 秒だった。
x86-64 のテストのランナーは 119 秒から 124 秒で、基準の x86-64 の `build`（154 秒と 174 秒）より 30 秒から 50 秒短い。
3 回のうち 1 回（39257618402）は、aarch64 が最も長いジョブになった。
件数が少なく、ランナーの性能の揺れ（同じ手順の `cabal test all` が 48 秒から 72 秒）より小さな差は言えない。

x86-64 の `tests` の時間は、ビルドとテストの和になる。
同じ条件の基準の実行と比べると、`outputs` に移した epubcheck、決定性の検査の出力、環境を変える検査（プルリクエストで合わせて約 31 秒）がそのまま縮む。
`main` への push では、環境を変える検査（約 108 秒）を含む `outputs` が x86-64 の長い方になり、テスト（約 65 秒）の分が縮む見込みである。
`main` への push の実行は、まだ計測していない（下書きのプルリクエストでは `main` への push が起きない）。

#### プルリクエストの dist-newstyle を残す

[ADR 0009](0009-ci-speed.md) は、`dist-newstyle` のキャッシュを `main` への push のときだけ保存すると決めた。
プルリクエストは、`main` の最新のキャッシュを戻してからビルドする。
そのため、モジュールを変えるプルリクエストは、push のたびに自分の変更をビルドし直す。
同じプルリクエストの二度目の push や、失敗したジョブの再実行でも同じである。

プルリクエストでも、GHC がモジュールをコンパイルしたときに限って `dist-newstyle` を保存するようにした。
`actions/cache` は、キャッシュを探すときに、まずそのプルリクエストの範囲を探し、次に `main` を探す。
`restore-keys` の前方一致は今のままで、プルリクエストのキャッシュがあればそれが選ばれる。

| 実行 | 戻したキャッシュ | x86-64 の `cabal build` | aarch64 の `cabal build` |
|---|---|---|---|
| 39253109275 の 1 回目 | プルリクエストの前の push のもの（その後 `main` に golem-doc の変更が入った） | 135 | 92 |
| 39253109275 の 2 回目（再実行） | 1 回目が保存したもの | 17 | 13 |
| 39252220232 | プルリクエストの前の push のもの（その後 `main` に golem-layout の変更が入った） | 82 | 70 |

同じマージコミットをビルドし直す再実行では、ビルドが 135 秒から 17 秒になった。
一方、二度目の push のあいだに `main` が進んでいると、`main` の変更をビルドし直すことになり、効果は消える。
並んだ実装の作業が次々にマージされる今は、二度目の push の多くがこの場合に当たる。
保存には x86-64 で 5 秒から 11 秒、aarch64 で 4 秒から 23 秒かかった。
何もコンパイルしなかった実行（ドキュメントやスクリプトだけの変更）は保存しないので、この時間はかからない。

## 実装すること

### x86-64 の build を二つのランナーに分ける

`.github/workflows/ci.yml` の `build` ジョブの行列を、`runner` と `part` の三つの組み合わせにする。

| `runner` | `part` | 受け持つ手順 |
|---|---|---|
| `ubuntu-24.04` | `tests` | `cabal test all`、生成したパーサーの検査、`dist-newstyle` の保存 |
| `ubuntu-24.04` | `outputs` | epubcheck、決定性の検査の出力（二つのマニュアルを含む）、環境を変える検査、マニュアルの成果物 |
| `ubuntu-24.04-arm` | `all` | 上の両方（epubcheck、環境を変える検査、マニュアルの成果物を除く） |

- 三つとも、同じ設定（`cabal.project.local` のテストのラッパーを含む）で `cabal build all peg-cli:exe:peg-hs` を実行する。ビルドの計画は同じになる。
- `scripts/ci/test-only-deps.sh` は三つとも実行する。
- apt で入れるのは、テストを受け持つランナーでは qpdf、x86-64 の `outputs` では epubcheck だけである。
- cddl の CLI は、テストを受け持つランナーだけが用意する。
- ジョブの名前は `build (<runner>, <part>)` とする。`ci` ジョブの判定（`scripts/ci/gate.sh`）は、行列をまとめた `needs.build.result` を見るので変わらない。
- `determinism` ジョブは今と同じく、`determinism-ubuntu-24.04` と `determinism-ubuntu-24.04-arm` の二つの成果物を比べる。前者は `outputs` が上げる。

### プルリクエストの dist-newstyle を残す

- `cabal build` のステップの出力を `tee` で残し、`[n of m] Compiling` の行があれば `compiled=true` をステップの出力にする。シェルは `bash`（`pipefail` 付き）にして、ビルドの失敗を `tee` が隠さないようにする。
- プルリクエストで、ビルドが成功し、`compiled` が `true` のとき、テストを受け持つランナーが `dist-newstyle` を保存する。後のステップが失敗しても保存する（`always()`）。修正の push が、失敗した実行のビルドを使えるようにするためである。
- 鍵は、`main` の鍵の形に `pr-<番号>-<コミット>-<試行の番号>` を付けたものとする。`restore-keys` は変えない。

### ドキュメント

- README の CI の節の表の `build` の行に、x86-64 の二つのランナーとプルリクエストのキャッシュを書く。
- 開発者向けのマニュアルの「CI のジョブ」の章の `build` の節を、同じ内容に直す。

## 実装しないこと

- **テストと出力を同じランナーで同時に走らせること。** 計測のとおり、コアが足りず縮まない。
- **aarch64 の build を二つに分けること。** aarch64 は x86-64 より短く終わり、臨界経路にない。ランナーを増やすと、同時実行の枠を多く使う。
- **変更したパッケージと、それに依存するパッケージのテストだけを走らせること。** `modules/` の 23 のパッケージのうち 21 は、依存をたどると golem-driver、golem-cli、golem-lsp に行き着く。時間の大きい golem-driver-test はほぼすべての変更で走る。さらに、golem-parser-test は golem-driver の `test/fixtures` を読むので、パッケージの依存だけでは影響の範囲を決められない。省けるのは golem-parser-test などの一部で、そのかわり必須の検査が弱くなる。
- **CI のテストのビルドの最適化を下げること（`-O0`）。** cabal の `optimization` はパッケージ単位で、テストのスイートだけを下げられない。ライブラリまで下げると、決定性の検査には別に `-O1` のビルドが要り、ビルドが二度になる。テストの実行も遅くなる。
- **ビルドの成果物を別のジョブに渡すこと。** `dist-newstyle` は x86-64 で 244 MB、aarch64 で 384 MB あり、上げ下ろしの時間が、二つ目のランナーでビルドし直す時間（モジュールを変えない場合で 15 秒前後）を上回る。
- **golem-parser-test を分けること、テストの順を変えること。** golem-parser-test は 39 秒から 54 秒かかり、`cabal test all` の最後に走ることが多い。分けるにはモジュールのテストを変える必要があり、golem-parser の ADR で扱う。
- **古い `dist-newstyle` のキャッシュを消すこと。** リポジトリのキャッシュは 10 GB の上限を超えており、古いものから消されている。消すには `actions: write` の権限が要り、[ADR 0035](0035-security-hardening.md) の読み取りだけの権限に反する。

## テスト設計

### 先に書いて失敗させるテスト（`scripts/ci/test.sh`）

`ci.yml` について、次を確かめる。

- `build` ジョブの行列が、`ubuntu-24.04` の `tests` と `outputs`、`ubuntu-24.04-arm` の `all` を持つこと。
- `cabal test all` のステップと、`scripts/determinism.sh` のステップが、それぞれ `matrix.tests` と `matrix.outputs` を条件に持つこと。
- プルリクエストの `dist-newstyle` を保存するステップが、`steps.build.outputs.compiled == 'true'` と `matrix.tests` を条件に持つこと。
- 既存の検査（`cabal` のコマンドが設定を変える引数を持たないこと、`--quick` の扱い）が通ること。

### 自動テストにできないものの確かめ方

実装のプルリクエストで、次を確かめて結果をプルリクエストに書く。

- 三つのジョブがそれぞれ受け持つステップだけを実行し、ほかを飛ばすこと。
- `determinism` ジョブが、`outputs` と `all` の成果物を比べて成功すること。
- マニュアルの成果物 `manual` と `manual-dev` が上がること。
- モジュールを変えたプルリクエストの実行で、プルリクエストのキャッシュが保存され、その再実行で `cabal build` がほとんど何もしないこと。ドキュメントやスクリプトだけを変えた実行で、保存のステップが飛ばされること。
- 所要時間。マージの後、プルリクエストと `main` への push の実行を 5 回以上集めて `scripts/ci/timings.sh --median` で中央値を取り、`docs/ci-timings/` に記録する。

## トレードオフ

- x86-64 では、同じコミットを二度ビルドする。モジュールを変えたプルリクエストでは、二つのランナーが同じコンパイルを同時にする。時間は増えないが、ランナーの使用時間は増える。
- 一回の実行で同時に使うランナーが一つ増える。無料のプランの同時実行の上限は 20 である。八つのプルリクエストが同時に CI を走らせると、重いジョブ（`build` と `format`）だけで 32 になり、今の 24 より待ちが増えうる。
- プルリクエストのキャッシュは、一回の保存で x86-64 の 244 MB と aarch64 の 384 MB を使う。キャッシュの上限（10 GB）を超えた分は古いものから消されるので、`main` の古い `dist-newstyle` から先に消える。`main` の最新のキャッシュは、プルリクエストが戻すたびに使われるので残る。
- プルリクエストのキャッシュは、`main` が進んだ後の push では役に立たない。古いプルリクエストのキャッシュを戻すと、`main` の最新のキャッシュより多くをビルドし直すこともある。
- 環境を変える検査がすべての入力を使う `main` への push では、x86-64 の `outputs` が臨界経路になる。

## 参考文献

- GitHub Docs, "Caching dependencies to speed up workflows"（キャッシュの探す範囲と `restore-keys`、上限と追い出し）. https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/caching-dependencies-to-speed-up-workflows
- GitHub Docs, "Running variations of jobs in a workflow"（行列の `include`）. https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/running-variations-of-jobs-in-a-workflow
- GitHub Docs, "Usage limits, billing, and administration"（同時実行の上限）. https://docs.github.com/en/actions/administering-github-actions/usage-limits-billing-and-administration
- tasty README（`--num-threads` と、`-N` のときの並列の実行）. https://github.com/UnkindPartition/tasty
- [ADR 0009](0009-ci-speed.md)、[ADR 0029](0029-environment-variation-determinism-test.md)、[ADR 0035](0035-security-hardening.md)、[ADR 0037](0037-ci-build-job-speedup.md)、[ADR 0038](0038-env-determinism-quick-on-pull-requests.md)
- 計測のデータ：下書きのプルリクエスト [#249](https://github.com/tett23/golem/pull/249) の実行
