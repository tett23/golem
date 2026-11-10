# Golem への貢献

[English](./CONTRIBUTING.en.md)

この文書は日本語版を正とする。
英語版は翻訳であり、内容が食い違うときは日本語版に従う。

Golem への変更は、どれも ADR（Architecture Decision Record）から始まる。
仕様を決めてからテストを書き、テストを失敗させてから実装する、という順番を守ってもらう必要がある。
この文書は、その順番と、リポジトリの約束ごとをまとめたものである。

## 開発環境

ビルドとテストの手順は [README.md](./README.md) の Development の節にある。
クローンしたら、まず Git フックを有効にする。

```bash
git config core.hooksPath .githooks
```

フックは [adr-guard](https://github.com/tett23/adr-guard) の v0.10.0 以降を呼び出すので、あらかじめインストールしておく（`cargo install --git https://github.com/tett23/adr-guard --tag v0.10.0`）。
`.githooks/pre-push` は、仕様を変えたのにマニュアルを直していないブランチの push を止める（「ドキュメント」の節）。
この設定はリポジトリに保存されないため、クローンのたびに実行する。

## 変更の流れ

1. ADR を書いて、レビューを受ける。
2. ADR のテスト設計にあるテストを書き、失敗することを確かめる。
3. 実装して、テストを通す。
4. 仕様書と README を更新する。
5. ブランチを push して、プルリクエストを作る。
6. CI が通ったら、`main` に no-ff でマージする。

誤字の修正や、仕様に影響しないドキュメントの修正には ADR は要らない。
二つのマニュアルと [docs/manual-policy.md](./docs/manual-policy.md) の変更も、メンテナーが求めない限り ADR を書かず、プルリクエストで決める。
迷ったら ADR を書く。

## ADR

### 置き場所と名前

特定のモジュールに属する ADR は `docs/<モジュール>/adr/` に置く。
モジュールをまたぐ ADR は `docs/adr/` に置く。

ファイル名には、`0001-feature-details.md` のように 4 桁の連番を付ける。
連番のあとは、内容がわかる kebab-case の名前にする。

### 構成

ADR は次の形で書く。
データ構造やアルゴリズムを変える場合は、その節も立てる。
検討の経緯として残しておきたいことがあれば、ほかの節を足してよい。
ADR は日本語で書く。

```markdown
# ADR 0001: タイトル

ステータス: 提案

## 文脈

## 実装すること

## 実装しないこと

## テスト設計

## トレードオフ
```

ステータスには、提案、採択、採択（未実装）、却下、破棄のいずれかを書く。
採択（未実装）は、採択したがまだ実装していない ADR に使い、実装を終えたら採択に変える。
採択（未実装）の ADR は `adr-guard unimplemented` で一覧にできる（[docs/adr/0048](./docs/adr/0048-update-adr-guard-to-v0.8.3.md)）。
あとの ADR が一部を置き換えた場合は、「採択→○○（変更部分）は [ADR NNNN](...)」のように、置き換えた ADR をリンクで示す。

### 変更してはいけない

コミットした ADR は、ステータスの行を除いて変更できない。
`.githooks/pre-commit` と CI の `adr` ジョブが、変更、削除、リネームを拒否する。
ステータスの行の変更（`--allow-status`）と、リンクを付ける、外す、リンク先を変えるだけの変更（`--allow-links`）は許す（[docs/adr/0010](./docs/adr/0010-update-adr-guard-to-v0.5.0.md)、[docs/adr/0032](./docs/adr/0032-update-adr-guard-to-v0.8.2.md)）。
リンクのテキストの変更は許さない。
ADR は、行頭が `ステータス:` のステータスの行をちょうど一つ持つ。
無い ADR と二つ以上ある ADR は、フックと CI の `adr` ジョブが拒否する。
`adr-guard check-status` で一覧にできる（[docs/adr/0011](./docs/adr/0011-update-adr-guard-to-v0.8.0.md)）。
文書の中の ADR の参照にはリンクを付ける。
リンクのない参照は CI の `adr` ジョブが拒否する。
`adr-guard links --fix` で直せる。
モジュールの ADR は、`golem-driver ADR 0015` のようにモジュールの名前を直前に置いて参照し、モジュールの名前もリンクのテキストに含める（`[golem-driver ADR 0015](...)`）。
`docs/adr ADR 0003` のようにディレクトリで修飾するときも同じである。
修飾子がリンクの外にある参照、リンク先が修飾子の ADR と異なるリンク、対象の無い修飾子付きの参照も、CI の `adr` ジョブが拒否する。
ほかのリポジトリの ADR は、`[peg-hs ADR 0039](https://github.com/...)` のように、リンクのテキストごと絶対リンクにする。
同じディレクトリの ADR に同じ番号を付けてはならない。
番号の重複は CI の `adr` ジョブが拒否し、`adr-guard check-numbers` で一覧にでき、`adr-guard renumber` で直せる（[docs/adr/0194](./docs/adr/0194-update-adr-guard-to-v0.10.0.md)）。
振りなおしのコミットには、一時的にフックと action に `--allow-renumber` を付ける。

仕様を変えたくなったら、元の ADR を書き換えずに、新しい連番の ADR を書く。
ADR をやめる場合は、ステータスを破棄にして、理由を [docs/specifications.md](./docs/specifications.md) に書く。

ADR はレビューを受けるまでコミットしない。
提案の段階で内容を直せるのは、コミットするまでのあいだだけだからだ。

### 規則の Alloy のモデル

規則を足すか変える ADR のうち、その範囲に Alloy のモデル（`docs/<モジュール>/models/`）があるものは、モデルを直して走らせ直し、両立しない規則の組と最も小さい例をモデルの README と ADR の「テスト設計」に書く。
モデルのコマンドの解の有無を変えたときは、同じディレクトリの `expected.txt` か `nightly.txt`（コマンドのある方）も直す。
コマンドを足すときは、ランナーで 30 分の `models.yml` に収まるものを `expected.txt` に、収まらないものを `nightly.txt` に挙げる。
どのコマンドも、二つの一覧のちょうど一方にある（`scripts/ci/test.sh` が確かめる）。
今モデルがあるのは改ページ（`docs/golem-layout/models/pagination.als`、結果は `docs/golem-layout/models/README.md`）だけである。
モデルのない範囲では、規則が三つ以上のほかの規則と端で重なる ADR だけが、新しくモデルを書く（[docs/adr/0204](./docs/adr/0204-pagination-invariants-by-exhaustive-small-inputs.md)、[docs/adr/0208](./docs/adr/0208-widen-lightweight-formal-methods.md) の 5）。
`.github/workflows/models.yml` が、`scripts/models/check.sh` でモデルのコマンドを走らせ、解の有無を `expected.txt` と比べる（[docs/adr/0235](./docs/adr/0235-check-the-manual-wat-example-the-diagnostic-anchors-and-the-alloy-models-in-ci.md)）。
`nightly.txt` のコマンドは、`.github/workflows/models-nightly.yml` が毎晩走らせる（[docs/adr/0242](./docs/adr/0242-run-the-heavy-commands-of-the-alloy-models-every-night.md)）。
結果を変えるモデルの変更は、マージした次の夜にわかるので、手元で走らせてから一覧を書き直す。

## テストと実装

ADR のテスト設計に書いたテストを先に書き、失敗することを確かめてから実装する。
設定の値のように自動テストを書けない変更は、テスト設計に確かめ方を書いておき、実装したあとに実際に動かして確かめる。
採択済みの ADR のテスト設計が「10 秒以内」「5 秒以内」のように時間で書いた検査は、計算が止まらないことを検出する意図として読み、テストの時間切れを 30 秒にして、上限で拒んだことを断言する（[docs/adr/0073](./docs/adr/0073-time-bounds-in-tests.md)）。
これは golem-pdf、golem-svg、golem-driver の外のテストの規則である。
golem-pdf と golem-svg のテストでは、時間の上限に `modules/golem-test-support` の `Golem.TestSupport.TimeLimit` にある `withinTimeLimits hangLimits` を使い、プロセスの CPU 時間の 60 秒と実時間の 300 秒の二つで止める。
時間の上限を付けるテストの CPU 時間は、単独で走らせて 10 秒以内に収める（[docs/adr/0091](./docs/adr/0091-cpu-time-limits-in-pdf-and-svg-tests.md)）。
golem-driver-test のテストでは、時間の上限に `modules/golem-driver/test/Support.hs` の `hangTimeout`（実時間の 300 秒）を使い、値をテストに書かない。
テストは threaded の RTS で同時に走るので、CPU 時間では測らない（[docs/adr/0237](./docs/adr/0237-raise-the-hang-time-outs-of-golem-driver-test-to-300-seconds.md)）。
`Support.hs` の外に `mkTimeout` があると、`scripts/ci/test.sh` が失敗する。

CI の `build` ジョブは、テストのスイートの全体の時間を、`scripts/ci/suite-limits.tsv` のアーキテクチャごとの上限と比べ、超えたスイートを失敗にする（[ADR 0292](./docs/adr/0292-limit-the-time-of-each-test-suite-by-the-median-of-main.md)）。
上限は、直近の `main` への push の 20 回の秒の中央値 m から `max(10, ceil(2 × m))` で決める。
スイートが上限を超えたら、次の順で扱う。

1. まず性能の後退かどうかを調べる。後退なら直す。
2. テストを足したことによる正当な増加なら、そのプルリクエストで `sh scripts/ci/suite-limits.sh --fetch 20 | sh scripts/ci/suite-limits.sh > scripts/ci/suite-limits.tsv` で表を作り直す。増えたスイートの行は、プルリクエストの CI の秒を中央値に加えた値で上限を求める。プルリクエストの説明に、前と後の上限を書く。
3. 新しいスイートを足すプルリクエストは、そのスイートの行を、プルリクエストの CI の秒から同じ式で求めて、`x86_64` と `aarch64` の二行を足す。行を足し忘れると、`changes` ジョブの `scripts/ci/suite-limits.sh --check` が落ち、テストのラッパーもそのスイートを走らせずに落とす。

手元でラッパーを使うときは `SUITE_LIMITS=` を付けると、上限を当てない。

外部ツール（`cddl`、`qpdf`、`openssl` など）を使うテストは、`modules/golem-test-support` の `Golem.TestSupport.ExternalTool` にある `needsTool` か `optionalTool` で書く（[docs/adr/0028](./docs/adr/0028-shared-test-support-package.md)）。
golem-driver のテストは、qpdf のほかに Poppler の `pdftoppm` と `pdfinfo` を使うので、手元にも `poppler-utils` を入れる（[docs/adr/0232](./docs/adr/0232-check-inks-fonts-figures-links-and-epubs-structurally-in-ci.md)）。
ツールがなければ `SKIP` と表示され、`GOLEM_REQUIRE_EXTERNAL_TOOLS=1` のもとでは失敗になる。
この変数の値は `1` だけが有効である。
飛ばしたテストの数は、テストのスイートの最後に標準エラー出力へ一行で出る（[docs/adr/0074](./docs/adr/0074-test-switches-by-environment-variables.md)）。
テストを切り替える環境変数を新しく読むときは、golem-test-support の `envFlag` で読み、値が `1` のときだけ有効にする。
golem-test-support に依存してよいのはテストスイートだけであり、ライブラリと実行ファイルが依存すると CI の `build` ジョブの `scripts/ci/test-only-deps.sh` が失敗する。
どのテストスイートも、ADR なしで golem-test-support を build-depends に足してよい（[docs/adr/0086](./docs/adr/0086-any-test-suite-may-depend-on-test-support.md)）。
二つ以上のパッケージのテストが同じ補助を使うなら、写さずに golem-test-support に置く。
一つのテストスイートしか使わない補助は、golem-test-support に置かず、そのパッケージのテストに置く。
golem-test-support は golem のパッケージに依存してはいけない。
依存すると、同じ `scripts/ci/test-only-deps.sh` が失敗する（[docs/adr/0087](./docs/adr/0087-test-support-dependencies-and-shared-fixtures.md)）。

golem のパッケージの、名前が `.Internal` で終わるモジュールは、そのパッケージのテストのためにあり、ほかのパッケージから import しない。
今あるのは `Golem.TestSupport.ExternalTool.Internal` だけである（[docs/adr/0092](./docs/adr/0092-remove-tools-required-exports.md)）。

ゴールデンのファイルは手で作らず、`--accept` で書き出す（手順は [README.md](./README.md) の Development の節）。
書き出したファイルの差分を読み、意図した出力であることを確かめてからコミットする。
CI はテストに `TASTY_NO_CREATE=true` を付けるので、ゴールデンのファイルを消したり名前を変え間違えたりすると失敗する。
PDF の見た目を意図して変えたときは、`scripts/visual/run.sh --accept` で見た目の回帰テストの参照（`scripts/visual/pages/`）を書き直し、同じプルリクエストに入れる（[docs/adr/0094](./docs/adr/0094-visual-regression-page-hashes-at-72-dpi.md)）。
参照の差分が、どのページの見た目が変わったかの記録になる。
機能を組み合わせた二冊の fixture（`modules/golem-driver/test/fixtures/complex-vertical` と `complex-horizontal`）は、一つの変更で多くのページが変わりやすい（[docs/adr/0175](./docs/adr/0175-complex-typesetting-fixture.md)）。
二冊の参照（`scripts/visual/pages/complex-vertical.txt` と `complex-horizontal.txt`）か出力のゴールデン（`pdf-complex-*.txt` と `epub-complex-*.txt`）を書き直すプルリクエストは、説明に、変わったページと、変わった理由（どの機能の変更か）を書く。
レビューでは、CI の要約と成果物 `visual-diff` にある、変わったページの前後の画像と差分の画像を見る（[docs/adr/0096](./docs/adr/0096-before-and-after-images-of-changed-pages.md)）。

改ページの規則は、小さな入力のすべてで不変条件として確かめる（[docs/adr/0204](./docs/adr/0204-pagination-invariants-by-exhaustive-small-inputs.md)）。
golem-layout のテストの「every input」が落ちたら、表示された最も小さい入力を、直すプルリクエストで次の手順で `modules/golem-layout/test/PaginateSpec.hs` の例にする。

1. 失敗の表示の「As a case of PaginateSpec:」の後の `testCase` を、`PaginateSpec.hs` のその規則の `testGroup` に貼る。表示は、その入力を組む式（`paginateWithin` と `enumFlows` の要素の並び）と、今の出力の各段の中身である。
2. `PaginateSpec.hs` に `import PaginateEnum (Element (..), enumFlows)` を足す。
3. 期待する出力を、違反した不変条件（表示の `I1` から `I8`）が求める配置に書き直す。今の出力のままにすると、不具合を固定するテストになる。

すぐに直さない違反は、例を貼らずに、仕様書の「既知の不具合」と docs/roadmap.md に項目を足し、`PaginateInvariantsSpec.hs` の `knownBugs` に、入力の形の条件と除く入力の数を足す。

行分割の規則も、小さな入力のすべてで不変条件として確かめる（[docs/adr/0209](./docs/adr/0209-line-breaking-invariants-by-exhaustive-small-inputs.md)）。
「line breaking invariants on every small input」の「every input」が落ちたら、「As a case of LineBreakingSpec:」の後の `testCase` を、`modules/golem-layout/test/LineBreakingSpec.hs` か `InseparableSpec.hs` に貼る。
表示は、その入力（`LineBreakEnum` の `Input`）を `breakInput` で組む式と、今の各行の字である。
貼る側に `import LineBreakEnum` を足し、期待する行を、違反した不変条件（表示の `L1` から `L13`）が求める分け方に書き直す。
すぐに直さない違反は、改ページと同じく、`LineBreakInvariantsSpec.hs` の `lineBugs` に、入力の形の条件と除く入力の数を足す。
数は、テストが表示する数をそのまま固定する。
直す ADR が入ったら、その項目を `knownBugs` から消す。

毎晩の `enum.yml` は、すべての入力を調べる上限の一つ上の段から、入力を抜き取って調べる（[docs/adr/0208](./docs/adr/0208-widen-lightweight-formal-methods.md)）。
抜き取りで見つけた違反は、最も小さいとは限らないので、テストが違反の残るかぎり要素を一つずつ取り除き、残った入力を同じ形で表示する。
その入力も、上の手順で例にする。
取り除いた後の入力は局所的に最も小さいだけなので、すべての入力を調べる上限を上げて、より小さい入力が見つかればそれを例にする。

範囲ごとの列挙のテストは、手元では範囲ごとの環境の変数で上限と抜き取りの数を変えて走らせる。

| 範囲 | テスト | 上限 | 抜き取りの数 |
|---|---|---|---|
| 改ページ | `cabal test golem-layout-test --test-option=-p --test-option='/pagination invariants/&&/every input/'` | `GOLEM_ENUM_DEPTH`（プルリクエストは 3、毎晩は 5） | `GOLEM_ENUM_PAGINATION_SAMPLES`（プルリクエストは 0、毎晩は 500 万） |
| 行分割 | `cabal test golem-layout-test --test-option=-p --test-option='/line breaking invariants on/'` | `GOLEM_ENUM_LINES_DEPTH`（プルリクエストは 2、毎晩は 3。2 までは 4 字までの行、3 からは 5 字までの行） | `GOLEM_ENUM_LINES_SAMPLES`（プルリクエストは 0、毎晩は 500 万） |

たとえば `GOLEM_ENUM_DEPTH=5 GOLEM_ENUM_PAGINATION_SAMPLES=100000 cabal test golem-layout-test --test-option=-p --test-option='/pagination invariants/&&/every input/'` のように、調べる要素の数を上げて走らせる。
golem-layout のテストは `-threaded` で作り、入力をプロセッサの数に分けて調べる。

列挙のテストの予算は、範囲ごとに 10 秒、すべての範囲の和で 30 秒である（[ADR 0281](./docs/adr/0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md)）。
時間は、x86-64 のランナーで、範囲のテストだけを `-p` で走らせた壁時計の時間で量る。
`tests-rest` のログの tasty の時間は、ほかのテストスイートと同時に走った時間なので使わない。
`enum.yml` の範囲の段の前の段「The time of each area on the settings of pull requests」が、上限の変数を渡さずに範囲ごとに走らせ、時間と和の表をジョブの要約に書く（`scripts/ci/enum-timings.sh`）。
予算を超えても、この段は落ちない。

列挙を足すか変えるプルリクエストでは、次の手順で時間を量る。

1. ブランチを push し、`gh workflow run enum.yml --repo tett23/golem --ref <ブランチ>` で `enum.yml` を起動する。
2. 終わった実行の要約から、「The time of each area on the settings of pull requests」の表をプルリクエストの説明に貼る。
3. 範囲が 10 秒を超えたか、和が 30 秒を超えたら、[ADR 0281](./docs/adr/0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md) の「予算を超えたときの順」で手を打つ。まず範囲のテストを速くし、次に既定の組版でない値を毎晩の段に移す。移したことは、移す境を決めるコード（`groupsAt`、`adjustsAt` など）の注釈と、仕様書のその範囲の段落に書く。

`enum.yml` の範囲の段は、どれも `!cancelled()` を持ち、前の段が落ちても走る。

Golem は、同じ入力から常に同じバイト列を出力する。
出力を変える変更は、x86-64 と aarch64 で同じ結果になることを CI の `determinism` ジョブで確かめる。
時刻、乱数、ハッシュ表の走査順、ロケールのように、環境で変わるものを出力に混ぜないよう注意する。

`scripts/` の下のスクリプトは、POSIX の `sh` で書き、macOS の BSD 版の `awk`、`sed`、`find`、`grep` でも動くようにする。
`sed -i` の引数のように GNU 版と BSD 版で違う書き方は避ける。
CI の `scripts-macos` ジョブが、`PATH` をシステムの道具だけにして、`scripts/` の下の六本のテストを macOS で走らせる（[docs/adr/0079](./docs/adr/0079-shell-tests-on-macos.md)）。

ライセンスに問題がなく、再実装がやさしいものは、依存に加えずに再実装する。
その場合は、本家のテストを参考にして、テストを十分に厚く書く。
必要な機能が限られているなら、その機能だけを実装してよい。

[README.md](./README.md) にある固定したネイティブライブラリ（HarfBuzz、FreeType、wasmtime、zlib、hyph-utf8）のバージョンを上げるときは、ADR を書く。
wasmtime のバージョンを上げるときは、`scripts/wasmtime-licenses.sh` で `licenses/wasmtime-v<バージョン>/`（`libwasmtime.a` に入った Rust のクレートなどのライセンスの文書）を作り直し、生成物もコミットする（[docs/adr/0007](./docs/adr/0007-third-party-licenses.md)）。
`scripts/fetch-wasmtime.sh` を変えたプルリクエストでは、手元で `sh scripts/wasmtime-advisories.sh` を実行し、出力と終了コードをプルリクエストの説明に貼る。
新しい版が既知のアドバイザリの範囲に入っていないことを確かめるためである（[docs/adr/0157](./docs/adr/0157-check-wasmtime-pin-against-advisories.md)）。
このスクリプトはネットワークに接続し、`cargo` と `rustup` を要する。
`c-objects.tsv` の構成要素の列は、スクリプトが埋めないので手で埋める。
見た目の回帰テストのラスタライザ shem の版を上げるときは、`scripts/visual/fetch-shem.sh` の版と三つのアーカイブの SHA-256 を変える。
SHA-256 は取ったアーカイブから自分で計算し、shem の release の `SHA256SUMS` と一致することを確かめてから書く。
マイナーバージョンを上げるときは画素が変わりうるので、同じプルリクエストで見た目の回帰テストの参照を作り直し、shem のリリースノートの「変更」を説明に引く。
パッチバージョンを上げるときは、shem の画素のために変わる参照を変えない（[docs/adr/0093](./docs/adr/0093-fetch-shem-pinned-by-version-and-sha256.md)）。
古い版と新しい版のどちらかが pre-release の識別子（`-rc3` など）を持つ版上げは、マイナーバージョンを上げるときと同じに扱い、参照を作り直してよい（[docs/adr/0100](./docs/adr/0100-raise-shem-to-v0-1-0-rc3-and-pre-release-bumps.md)）。
その代わりに、プルリクエストの PDF を古い版と新しい版の両方で描き、ページの SHA-256 が違うページを入力ごとに説明に挙げる（なければ「なし」と書く）。
古い版の shem は、版上げの前のコミットの `fetch-shem.sh` で取り、そのパスを `SHEM` に入れて描く。
違うページがあれば、shem のリリースノートの「変更」を引き、そのページの前後の画像（成果物 `visual-diff`）を見てから参照を受け入れる。
版上げが Golem の入力（固定した版の名前を書いた開発者のマニュアルの本文など）を変えたために変わったページの参照は、版上げの種類によらず直してよい。
直してよいのは、古い版と新しい版で同じ SHA-256 になるページに限る。
Golem の PDF の Writer が新しい演算子や資源を書く変更は、先に shem を直してリリースし、固定した版を上げてから入れる。
shem は読めない PDF に出会うと、画像を書かずに失敗するからである。
`cabal.project.freeze` で固定した依存のバージョンを変えるときも、変更の理由をプルリクエストに書く。
リリースノートを書く Claude Code のバージョンは、`mise.toml` の `"npm:@anthropic-ai/claude-code"` に正確な値で固定してある（[docs/adr/0044](./docs/adr/0044-release-workflow-hardening.md)）。
上げるときは `mise.toml` を変えるプルリクエストを出し、新しいバージョンの `claude --help` に `--tools` と `--strict-mcp-config` があることを確かめる（`scripts/release/test.sh` は、そのバージョンの `claude` があれば確かめる。CI の `release-scripts` ジョブは、mise でそのバージョンを入れて必ず確かめる。[docs/adr/0058](./docs/adr/0058-run-skipped-checks-in-ci.md)）。
Claude Code を入れる mise の版と、その版の Linux の x86-64 の実行ファイルの SHA-256 は、`.github/workflows/ci.yml` と `.github/workflows/release.yml` の `MISE_VERSION` と `MISE_SHA256` に同じ値で固定してある（[docs/adr/0085](./docs/adr/0085-pin-mise-version-in-workflows.md)）。
上げるときは二つのファイルを変えるプルリクエストを出し、SHA-256 を求めた手順を本文に書く。
SHA-256 は次の手順で求める。
jdx/mise の GitHub の release から、`mise-v<版>-linux-x64.tar.zst`、`SHASUMS256.txt`、`SHASUMS256.txt.minisig` を取る。
`SHASUMS256.txt` の署名を mise の minisign の公開鍵で確かめ、圧縮ファイルをその値で確かめる。
展開した `mise/bin/mise` の SHA-256 を求め、同じ版の `mise-v<版>-linux-x64` の `SHASUMS256.txt` の値と一致することも確かめる。
CI の `release-scripts` が通れば、action が新しい SHA-256 で実行ファイルを確かめたことになる。
リリースノートから兄弟のリポジトリへリンクするときは、`scripts/release/allowed-links.txt` に `https://github.com/tett23/<リポジトリ>/` の 1 行を足すプルリクエストを出す。
ghcup を上げるときは、`scripts/release/build-linux.sh` の ghcup のバージョン、ブートストラップのスクリプトのコミット、その SHA-256 を一緒に変える。

## 整形と検査

Haskell のコードは fourmolu 0.21.0.0 で整形し、hlint 3.10 の指摘をなくす。
どちらも CI の `format` ジョブで検査する。
生成したパーサー（`modules/golem-parser/src/Golem/Parser/Generated.hs`）と、ラベルを外した文法（`modules/golem-parser/test/StrippedGrammar.hs`）は対象外である。
`scripts/gen-embedded.sh` が生成する golem-driver の二つのモジュール（`modules/golem-driver/src/Golem/Driver/Version/Embedded.hs` と `modules/golem-driver/src/Golem/Driver/Explain/Embedded.hs`）も対象外である。

文法（`modules/golem-parser/grammar/Golem.hpeg`）を変えたら、`scripts/gen-parser.sh` で生成し直して、生成物もコミットする。
このスクリプトは、ラベルを外した文法も生成する。
golem-parser のテストは、二つの文法が同じ入力を受理することを確かめる。
文法にラベルを足すときは、ラベルを外しても受理する言語が変わらないことを確かめ、理由のコメントを添えて `%safe` を書く。
`scripts/gen-parser.sh` は peg-hs の警告を誤りとして扱うので、`%safe` のないラベルがあると生成が失敗する（[golem-parser ADR 0007](./docs/golem-parser/adr/0007-grammar-label-safety.md)）。

## ドキュメント

ADR で仕様が変わったら、同じプルリクエストで [docs/specifications.md](./docs/specifications.md) と [README.md](./README.md) も更新する。
この二つは、`main` で常に最新でなければならない。
モジュールの実装の詳細は `docs/<モジュール>/specifications.md` に書く。
どのバージョンで何を扱うか、まだ実装していない項目、手で確かめる項目、未決事項、課題にしなかった事項は [docs/roadmap.md](./docs/roadmap.md) に書き、仕様書には書かない。
実装を終えたら、その項目を roadmap.md から消し、振る舞いを仕様書に書く。

仕様書から ADR を参照するときは、ADR のファイルへのリンクを付ける。
新しい用語を導入したら、[docs/glossary.md](./docs/glossary.md) にも加える。

[docs/diagnostics.md](./docs/diagnostics.md) を変えたら、同じ変更で `sh scripts/gen-embedded.sh` を走らせ、生成し直した `modules/golem-driver/src/Golem/Driver/Explain/Embedded.hs` もコミットする。
golem-driver は、この生成したモジュールで文書を埋め込む（[docs/adr/0203](./docs/adr/0203-generated-modules-instead-of-template-haskell-in-golem-driver.md)）。
生成し直すのを忘れると、golem-driver のテストと CI の `build` ジョブが失敗する。

マニュアルは、使い手のマニュアル `manual/` と開発者のマニュアル `manual-dev/` の二つで、どちらも Golem のプロジェクトとして書き、Golem で組む（[docs/adr/0024](./docs/adr/0024-manual-audiences-and-policy.md)）。
読み手、文体、説明の厚さ、根拠と脚注の書き方、章立て、コードの表示は、方針の文書 [docs/manual-policy.md](./docs/manual-policy.md) に従う。
ADR を実装して使い手から見える振る舞いが変わるときは同じプルリクエストで `manual/` を、開発の手順や仕組みが変わるときは `manual-dev/` を直す。
マニュアルには、採択して実装を終えた仕様だけを書く。
マニュアルを編集する前に、一度 `sh scripts/manual/build-info.sh manual`（と `manual-dev`）を実行して、奥付が読む `common/build-info.gm` を作っておく。
二つのマニュアルは `scripts/manual/build.sh` で、エラー、警告、notice を一つも出さずに組めなければならない（CI の `build` ジョブで走る）。
`silence-notices` と `--no-notices` で、notice を消してはいけない。
`.githooks/pre-push` と CI の `manual` ジョブ（`docs.yml`）は、次のブランチを止める。

- docs/markup.md か docs/specifications.md を変えて、`manual/` も `manual-dev/` も変えていないブランチ
- CONTRIBUTING.md か CONTRIBUTING.en.md を変えて、`manual-dev/` を変えていないブランチ

既知の不具合を足すときのように、変更がマニュアルに書いた事柄を変えない場合は、ブランチのコミットのどれかのメッセージの末尾に `Manual: unchanged` というトレーラーの行を書く。
フックは手元の `origin/main` との分岐点から検査するので、`main` に入った変更で止まったときは `git fetch` をしてから push し直す。

ビルドやテストが `docs/` の下の文書を読むようにしたときは、その文書を `scripts/ci/needs-build.sh` の一覧に加える。
一覧にない文書は docs だけの変更として扱われ、変えてもビルドが走らない。
コードの中では、文書のパスを一つの文字列（`"../../docs/diagnostics.md"` のような形）で書く。
CI の `changes` ジョブは、そうした文字列を拾って一覧と照らし合わせる（[docs/adr/0021](./docs/adr/0021-docs-workflow-and-ci-gate.md)）。
パスを `"docs" </> "diagnostics.md"` のように組み立てるときは、その行に `-- docs-refs: docs/diagnostics.md` の注釈で読む文書を書く。
`"docs"` という文字列を含む行に注釈がないと、同じジョブ（`scripts/ci/docs-refs.sh`）が失敗する（[docs/adr/0069](./docs/adr/0069-lint-scripts-bypassed-by-plain-rewrites.md)）。

すべてのパッケージは、網羅していない `case` と関数の定義を `-Werror=incomplete-patterns` でエラーにする（[docs/adr/0027](./docs/adr/0027-exhaustive-command-dispatch-by-types.md)）。
`modules/` にパッケージを足したときは、cabal ファイルの `common warnings` の `ghc-options` にこのフラグを書き、各コンポーネントで `import: warnings` とする。
付け忘れると、CI の `changes` ジョブ（`scripts/ci/incomplete-patterns.sh`）が失敗する。

`unsafePerformIO` とその仲間（`unsafeDupablePerformIO`、`unsafeInterleaveIO` など）は、`scripts/ci/unsafe-io-allowed.txt` に書いた定義でだけ使う（[docs/adr/0034](./docs/adr/0034-fewer-unsafe-perform-io.md)）。
IO で書ける処理は IO のエッジに置き、どうしても純粋な関数の内側から C のライブラリを呼ぶときだけ、一覧に定義と残す理由を足す。
一覧とソースが食い違うと、CI の `changes` ジョブ（`scripts/ci/unsafe-io.sh`）が失敗する。

`-threaded` でビルドする実行ファイルとテストのスイートは、`-with-rtsopts=-N` でもリンクし、起動のときから capability をプロセッサの数だけ持たせる。
コードの中では `setNumCapabilities` を呼ばない。
二つの呼び出しが同時に capability を増やすと、GHC 9.10.3 のランタイムが止まる。
tasty 1.5.4 も、capability がプロセッサより少ないと起動の時点でこれを呼ぶので、`-N` で呼ばせないようにする。
どちらかを破ると、CI の `changes` ジョブ（`scripts/ci/rts-capabilities.sh`）が失敗する。

`-threaded` のテストのスイートでは、tasty がテストを同時に走らせる。
環境変数、ロケールの符号化、カレントディレクトリのようなプロセスの状態を変えるテストは、ほかのテストが途中の状態を読むので、`-threaded` のスイートに置かない。
golem-driver では、そうしたテストを `-threaded` でない `golem-driver-global-test` に書く（[docs/adr/0146](./docs/adr/0146-threaded-golem-driver-test.md)）。
`golem-driver-test` のモジュールが `withEnv`、`setEnv`、`setLocaleEncoding`、`setCurrentDirectory` などを使うと、CI の `scripts-linux` ジョブ（`scripts/ci/test.sh`）が失敗する。

`-threaded` の `golem-driver-parallel-test` は、`modules/golem-test-support` の `Golem.TestSupport.Watchdog` にある `watchTests` で包む。
Haskell のランタイムの外の POSIX のスレッドが実時間を測り、一つのテストが `GOLEM_RACE_TESTS` の値の 300 倍の秒数を超えるか、テストが終わってもプロセスが同じ秒数を超えて終わらないと、走っていたテストの名前とランタイムの心拍を標準エラー出力に書いて、プロセスを `abort()` で止める（[docs/adr/0117](./docs/adr/0117-watchdog-outside-the-runtime-for-threaded-tests.md)）。

`golem-emet-test` も、木の全体を `watchTests 300` で包む。
同じスイートは、木の全体を `localOption (NumThreads 1)` でも包み、テストを一つずつ走らせる。
コマンドラインの `-j` は働かない。
aarch64 の GHC の threaded のランタイムには、.emet を構文解析するテストが同じプロセスの中で同時に走ると、まれにすべての Haskell のスレッドが止まるか、SIGSEGV で落ちる不具合があるからである（GHC の issue #28001）。
`-threaded` と `-N` は残すので、テストの中でスレッドを同時に走らせる並列の評価のテストは、複数のコアで走る（[docs/adr/0207](./docs/adr/0207-run-golem-emet-test-one-test-at-a-time-under-the-watchdog.md)）。

監査の記録や性能計測のスナップショットは、`docs/` の下に用途ごとのディレクトリを作って置く。
これらもコミットしたあとは変更しない。
`docs/audit/`、`docs/audits/`、`docs/benchmarks/`、`docs/benchmark/` に置いた記録は、フックと CI の `adr` ジョブがコミット後の変更、削除、移動を拒否する（[docs/adr/0011](./docs/adr/0011-update-adr-guard-to-v0.8.0.md)、[docs/adr/0012](./docs/adr/0012-update-adr-guard-to-v0.8.1.md)）。
`docs/ci-timings/` のようにほかの名前のディレクトリに置いた記録は検査されないので、約束とレビューで守る。

### 日本語の文章

日本語の文章は、一文ごとに改行する。
箇条書きの項目と表のセルは、一つの項目やセルに複数の文を書いてよい。
地の文では、ダッシュ（——）を使わない。
中黒（・）は、並列を表すことにだけ使わない。
並べるときは、読点か「と」でつなぐ。
外来語の区切りのような、並列でない中黒は使ってよい。

用語は [docs/manual-policy.md](./docs/manual-policy.md) の規則に従う。
開発者のマニュアルの規則（「診断」ではなく diagnostic、「資産」ではなくアセット、「機械」ではなくマシンか計算機、「お知らせ」ではなく notice と info）と、二つのマニュアルに共通する規則（「書体」と「フォント」の使い分け、version は「版」ではなくバージョン、public domain は「公有」ではなくパブリックドメイン）は、`docs/` の仕様書、README、CONTRIBUTING、新しい ADR にも当てはめる。
コミット済みの ADR は変えられないので、古い用語のまま残す。

文字と行で判定できる規則は、textlint で検査する（[docs/adr/0036](./docs/adr/0036-textlint-for-documents.md)）。
規則、用語の辞書、バージョンを固定した npm のパッケージは `tools/textlint/` にある（[tools/textlint/README.md](./tools/textlint/README.md)）。
Node を入れてから `sh scripts/ci/textlint.sh` を実行する。
初めての実行でパッケージを入れる。
`TEXTLINT_ARGS=--fix` を付けると、直せる違反を直す。
対象は、`docs/` の Markdown（ADR、`docs/audits/` のような記録を除く）、README.md、CONTRIBUTING.md、ブランチで加えた ADR、二つのマニュアルの原稿である。
CI の `textlint` ジョブ（`docs.yml`）も同じスクリプトを走らせる。
意味で選ぶ語（「版」と「バージョン」、「書体」と「フォント」）と、文の長さは検査しないので、レビューで確かめる。

## Git

### コミット

コミットメッセージは英語で書く。
一つのコミットには、一つのまとまった変更だけを入れる。

### ブランチとマージ

`main` に直接 push せず、ブランチを切ってプルリクエストを作る。
マージは常に no-ff で行う。
`main` には保護の規則があり、プルリクエストを経ない push と、マージコミット以外のマージ（squash と rebase）を拒否する。
マージには、CI の `ci`（`ci.yml`）と、`adr`、`manual`、`textlint`（`docs.yml`）の四つの検査が通っている必要がある（[docs/adr/0021](./docs/adr/0021-docs-workflow-and-ci-gate.md)、[docs/adr/0022](./docs/adr/0022-manual-as-typesetting-sample.md)、[docs/adr/0036](./docs/adr/0036-textlint-for-documents.md)）。

`main` の rebase と force push は禁止する。
例外は、API キーのような秘密情報を誤ってコミットした場合だけである。
自分のブランチは、マージするまでなら rebase してよい。

### タグとリリース

`v` で始まるタグをリリースとして扱う。
`v0.0.1-rc` のようにバージョンのあとに識別子が付くタグは、プレリリースとする。
リリースノートは GitHub の Releases に英語で書く。
変更点は、追加、変更、削除、修正のように項目を分けて書き、できれば各変更のコミットまたはプルリクエストと ADR を絶対リンクで添える。

リリースの手順は次のとおりである（[docs/adr/0004](./docs/adr/0004-binary-distribution-and-release.md)）。

1. セキュリティ監査をする（[docs/adr/0035](./docs/adr/0035-security-hardening.md)）。プレリリース（`rc` などの識別子が付くタグ）を含め、`v` で始まるタグのリリースのたびに行う。前の監査からの変更を中心に、信頼できない入力（原稿、TOML、画像、フォント、CSL-JSON、プラグイン、シンボリックリンク）と CI のワークフローを調べる。結果は `docs/audits/<日付>-security-audit.md` に日本語で記録し、プルリクエストで `main` に入れる。記録はコミットしたあとは変更しない。見つかった問題は、失敗するテストを先に書いてから直す。仕様を変える修正には ADR を書く。監査の記録と修正が `main` に入るまで、タグを付けない。
2. バージョンを上げるプルリクエストを作る。リポジトリの根の `VERSION` を新しいバージョン（例：`0.1.0-rc1`）に書き換え、識別子を除いた `X.Y.Z` を全パッケージの cabal ファイルの `version` に書く。CI の `release-scripts` ジョブが、二つの一致を検査する。`VERSION` を書き換えた後に `sh scripts/gen-embedded.sh` を走らせ、生成し直した `modules/golem-driver/src/Golem/Driver/Version/Embedded.hs` も同じプルリクエストに入れる（[docs/adr/0203](./docs/adr/0203-generated-modules-instead-of-template-haskell-in-golem-driver.md)）。
3. プルリクエストを `main` にマージする。
4. マージしたコミットに、`v` に `VERSION` の内容を続けたタグ（例：`v0.1.0-rc1`）を付けて push する。タグと `VERSION` が一致しないとき、タグのコミットが `main` に含まれないときは、ワークフローの `version` ジョブが失敗し、リリースは作られない。
5. `.github/workflows/release.yml` が、配布物を作って検査し、下書きのリリースを作る。プレリリースのタグでは、プレリリースの印が付く。
   ジョブ `wasm` は、`golem.wasm` のアーカイブを作った直後に `scripts/release/check-wasm-archive.sh` でライセンスの文書と `.sha256` を確かめる。`workflow_dispatch` でも走る（[docs/adr/0230](./docs/adr/0230-check-the-release-workflow-and-ci-history-by-scripts.md)）。
   `release` ジョブは、下書きのリリースを作った後に、上げたアーカイブのそれぞれに `gh attestation verify` を走らせ、下書きの `SHA256SUMS` で `dist/` のファイルと照らす（[docs/adr/0230](./docs/adr/0230-check-the-release-workflow-and-ci-history-by-scripts.md)）。
6. 下書きのリリースノートを読む。AI が書いたノートの分類やまとめ方がおかしければ、手で直す。AI の実行か検査に失敗したときは、`## Unsorted` に変更の一覧が残ったノートになるので、分類して書き直す。ワークフローの要約に、失敗の理由が書かれる。
   v1.0.0 より前のリリースでは、リンクの注釈を含む PDF/X-4 の PDF を ISO 15930-7 と照合していないことを、ノートの既知の問題に書く（[docs/adr/0226](./docs/adr/0226-move-the-iso-15930-7-check-to-before-v1.md)）。
7. GitHub の Releases の画面で、下書きを公開する。公開の操作はワークフローでは行わない。

配布物を作って検査するところまでを試すときは、`gh workflow run release.yml --ref <ブランチ>` で `workflow_dispatch` から起動する。
このときはリリースを作らない。

タグは次のとおり扱う（[docs/adr/0008](./docs/adr/0008-first-release-verification.md)）。

- push したタグを別のコミットに付け直さない。
- 公開していないリリースのタグは、ワークフローが失敗したとき、または配布物の確かめが通らなかったときに限り削除してよい。削除したタグの名前は再び使わず、プレリリースの識別子を進める（`rc1` の次は `rc2`）。
- 公開したリリースのタグは削除しない。
- コードを変えずに直る失敗（ランナーの不調、ネットワークの一時的な失敗、API の制限）は、タグを変えずにワークフローをやり直す（`gh run rerun <実行の ID> --failed`）。

配布物を確かめた結果は、`docs/audits/releases/<タグ>.md` に日本語で記録し、プルリクエストで `main` に入れる。
タグを削除してやり直した場合も、削除したタグの記録に失敗を書いて残し、次のタグの記録を別に作る。
記録はコミットしたあとは変更しない。

## テスト用の素材

フィクスチャに外部の文章やフォントを加えるときは、ライセンスを確かめて、ライセンスの文書を一緒に置く。
出典は、そのフィクスチャの README に書く。
取得するスクリプトでは、取得したファイルの SHA-256 を固定して検証する。
取得した原文を Golem の原稿に変換する処理は、Python で書かない。
`modules/golem-fixtures` の実行ファイル `golem-fixtures` に Haskell で書き、`scripts/fixtures/fetch-public-domain.sh` から `cabal run` で動かす（[docs/adr/0023](docs/adr/0023-fixture-converters-without-python.md)）。
このパッケージはリリースの配布物に入れない。

## GitHub Actions

Node は最新の LTS を使う。
アクションは、Node 24 以降で動く最新のメジャーバージョンを使う。
アクションは、コミットの SHA と版のタグの注釈で指定する（`- uses: actions/checkout@<40 桁の SHA> # v7.0.1` の形）。
注釈のタグは、そのコミットを指すタグのうち、いちばん細かいものとする。
プルリクエストの CI（`scripts-linux` ジョブ）は、`sh scripts/ci/actions-pins.sh check` でこの形を確かめる。
ワークフローを足すときも、同じ形で書く。
`.github/workflows/advisories.yml` は毎日一回、`verify` と `latest` で、注釈のタグが固定したコミットを指すことと、固定した版が上流の最新であることを照合する。
照合が失敗したら、手元で `sh scripts/ci/actions-pins.sh update` を実行し、書き換えたワークフローのプルリクエストを出す。
プルリクエストの説明には、`update` の出力（どの action をどの版からどの版へ上げたか）を書く。
メジャーバージョンが上がるときは、上流のリリースノートを読み、入力の変わったアクションの `with:` を同じプルリクエストで直す（[docs/adr/0296](./docs/adr/0296-pin-every-github-action-by-commit-sha.md)）。

CI の実行時間は 5 分以内を保つ。
CI を待つ時間は、変更を一つ入れるたびにかかるので、CI が遅いと開発そのものが遅くなる。
このプロジェクトは開発の速さをいちばん大事にしているので、CI の遅さを後回しにしない。
プルリクエストの CI が 5 分を超えたら、ほかの作業を止めて、まず CI を改善する（ジョブの分割、キャッシュ、変更のないモジュールの検査を省くことなど）。
最適化の前後の時間は `docs/ci-timings/` に記録する。
例外は、wasm のツールチェーン（`scripts/fetch-ghc-wasm.sh`）か wasm の freeze（`cabal.project.wasm.freeze`）を替えるプルリクエストで、`wasm` ジョブの最初の実行はキャッシュがないので 5 分を超えてよい。
そのプルリクエストは、キャッシュのない実行とキャッシュのある実行の時間を `docs/ci-timings/` に記録する。
キャッシュが消されて 5 分を超えた実行は、この例外に当たらないので、CI を直す（キャッシュの量を減らす）作業を先にする（[docs/adr/0219](./docs/adr/0219-frequency-of-the-wasm-job-and-its-uncached-runs.md)）。
`.github/workflows/models.yml` も、この方針の例外である。
Alloy のモデルを走らせるには 5 分を大きく超える時間がかかるので、モデル（`docs/*/models/`）を変えたプルリクエストと `main` への push と週に一度だけ走り、上限を 30 分とする。
モデルを変えるプルリクエストは、その時間を待つ（[docs/adr/0235](./docs/adr/0235-check-the-manual-wat-example-the-diagnostic-anchors-and-the-alloy-models-in-ci.md)）。
`.github/workflows/models-nightly.yml` は、夜間に `main` でだけ走り、プルリクエストを待たせないので、この方針に関わらない。
一つのコマンドの上限は 5.5 時間である（[docs/adr/0242](./docs/adr/0242-run-the-heavy-commands-of-the-alloy-models-every-night.md)）。

CI が配布元から取るファイル（wasmtime の C API、hlint、shem、Neovim、Helix、Chromium、Deno、Alloy の jar、GMP のソースなど）は、`scripts/ci/fetch-url.sh` で取る。
`fetch-url.sh` は、`curl` のどの誤りも再試行する。
試行は 3 回、試行のあいだの待ちは 10 秒と 30 秒、一回の `curl` の上限は 120 秒で、それぞれ `FETCH_ATTEMPTS`、`FETCH_WAITS`、`FETCH_MAX_TIME` で変えられる。
取ったファイルの SHA-256 が取得のスクリプトに書いた値と違えば、再試行せずに失敗する。
一つのアーカイブの取得は、再試行を含めて最長で約 7 分かかる。
ワークフローの取得の手順は、一つの手順で一つのスクリプトだけを走らせ、`timeout-minutes: 10` で止める。
バックグラウンドで走る epubcheck の取得は `timeout -k 10 600` で包む（[docs/adr/0259](./docs/adr/0259-record-what-the-audit-of-the-ci-release-and-tooling-adrs-found-on-2026-11-09.md)）。
アーカイブは `third_party/downloads`（`GOLEM_DOWNLOADS` で変えられる）に置き、ワークフローはこのディレクトリをキャッシュする。
展開した木はキャッシュしない。
キャッシュから戻したアーカイブは、使う前に必ず SHA-256 を照合し、合わなければ取り直す。
キャッシュを保存するのは `main` の実行だけで、プルリクエストは `main` のキャッシュを戻す（[docs/adr/0243](./docs/adr/0243-retry-every-download-and-cache-the-archives-checked-by-sha-256.md)）。

CI の `build` ジョブは、EPUB を検査する epubcheck を apt から入れない。
配布元（GitHub の w3c/epubcheck）の release の zip を取り、`ci.yml` に書いた SHA-256 で検査してから、ランナーにもとからある Java 17（`JAVA_HOME_17_X64`）で動かす。
zip は版と SHA-256 をキーにキャッシュするので、取りに行くのは版を上げたときとキャッシュが消えたときだけである。
今の版は 5.4.0 である。
版を上げるときは、`ci.yml` の `EPUBCHECK_VERSION` と `EPUBCHECK_SHA256` を変えるプルリクエストを出す（[docs/adr/0062](./docs/adr/0062-epubcheck-from-release-with-cache.md)）。

夜ごとの `browser.yml` は、golem の HTML と `golem.wasm` を、Chromium、Safari、Deno で確かめる（[docs/adr/0234](./docs/adr/0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md)）。
プルリクエストでは走らず、前の成功した実行から `main` が進んだ日と、`workflow_dispatch` で走る。
Chromium は Chrome for Testing の `chrome-headless-shell` を、Deno は GitHub のリリースの zip を、版と SHA-256 で固定する（`scripts/browser/fetch-chromium.sh`、`scripts/wasm/fetch-deno.sh`）。
版を上げるときは、版と SHA-256 を同じプルリクエストで変え、`workflow_dispatch` で `browser.yml` が通ることを確かめる。
Safari の版は固定せず、macOS のランナーの像に従う。
`safari` のジョブの要約には、macOS、像、Safari、WebDriver の `browserVersion` の版の表が残る。
`safari` のジョブが失敗したら、まずこの表を前の成功した実行の表と比べ、Safari か像の版が変わっていれば Safari の更新を疑う。
検査を緩めるか外すときは、その変更のプルリクエストに理由を書く。

## ライセンス

二つのマニュアル（`manual/` と `manual-dev/`。`fonts/` を除く）への貢献は、[CC0 1.0](./manual/LICENSE) のもとで配布される（[docs/adr/0082](./docs/adr/0082-manuals-under-cc0.md)）。
そのほかに貢献したコードとドキュメントは、[MIT ライセンス](./LICENSE) のもとで配布される。
