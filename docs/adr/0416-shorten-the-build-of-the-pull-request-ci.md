# ADR 0416: キャッシュを保存する組み立てを臨界経路から外し、golem-driver-test を分けて、プルリクエストの CI を縮める

Status: accepted

## 文脈

[ADR 0392](0392-budget-the-pull-request-ci-at-five-minutes.md) は、プルリクエストの CI の時間の予算を 300 秒とした。
[ADR 0395](0395-bring-the-pull-request-ci-under-five-minutes.md) は、失うもののない変更でこれに近づけ、実装の後に測ると決めた。
測った値が 300 秒を超えるか、300 秒との差が 30 秒に満たないときは、コードに手を入れてコンパイルの時間を縮める手を、別の ADR で測った値を添えて決めるとした（項目 8）。

0395 の後に測った中央値は 389 秒で、予算を超える（[ADR 0415](0415-fix-the-medium-findings-of-the-conformance-audit-of-2026-11-18.md) の 1）。
tett23 は 2026-11-23 に、監査の高の指摘として、これを直すことを決めた。

## 調査した事項

`origin/main`（`b540aa68a`）と、`gh` で取った実行の記録で確かめた。

- 0395 の後の、build を省かなかった 25 回の時間（秒）は、昇順に 276、292、305、311、312、314、325、327、329、330、345、367、389、430、466、468、495、510、511、529、556、681、704、887、896 である。
  中央値は 389 秒で、300 秒以下は 2 回だけである。
- 25 回の臨界経路で最も長い脚は、build と determinism が 14 回、wasm が 4 回、verapdf が 3 回、editors-lsp が 3 回、visual が 1 回であった。
  `changes` の 10〜22 秒と `ci` の 14〜42 秒が、毎回足される。
- build の脚は、アーキテクチャごとに六つある（`.github/workflows/ci.yml` の 150 行から 206 行）。
  `dist-newstyle` を保存する（`save: true`）のは、`cabal build all` を組む tests-driver の脚だけである。
  ほかの脚は、自分のスイートか `golem` だけを組む（[ADR 0395](0395-bring-the-pull-request-ci-under-five-minutes.md) の項目 1 と 2）。
- `ci` の job は、`build` の job（すべての脚）を `needs` に持つ（同 1309 行）。
  `needs` に入らない job は、`scripts/ci/ci-critical-path.sh` の数える臨界経路に入らない。
- 最も遅い build の脚は ARM64 の tests-driver で、ステップの秒は次のとおりであった。

  | 実行 | 脚 | dist の復元 | `cabal build` | テストの実行 | 脚の合計 |
  | --- | --- | --- | --- | --- | --- |
  | 45055120571 | tests-driver | 14 | 226 | 138 | 425 |
  | 45046398172 | tests-driver | 12 | 236 | 131 | 測っていない |
  | 45050959782 | outputs | 16 | 211 | 出力の段 25 | 293 |

- tests-driver の脚のテストの実行は、ほぼ golem-driver-test である（`All 1715 tests passed (131.68s)`）。
  同じ脚で、golem-driver-global-test（18 秒前後）と golem-driver-parallel-test（14 秒前後）も走る。
- ほぼ全部を組み直した二つのジョブのログで、`Compiling` と `Linking` の時刻をコンポーネントごとに数えた（並列に動くので近似の値である）。
  - golem-project の `Style.hs` を変えたジョブ：全体 219 秒のうち、golem-driver-test が 121 秒で、+98 秒に始まり +219 秒に終わる最後のコンポーネントであった。
  - golem-html を変えたジョブ：全体 226 秒のうち、golem-driver-test が 111 秒（+115 秒から +226 秒）であった。
- golem-driver-test は、`Main` と 76 の `other-modules` からなる一つのテストのスイートである。
- テストだけの依存の検査（`scripts/ci/test-only-deps.sh`、[ADR 0028](0028-shared-test-support-package.md)、[ADR 0191](0191-semantic-ir-generator-module.md)）は、ローカルのパッケージのライブラリから golem-test-support と golem-doc-gen に届かないことを確かめる。
  golem-driver-test はこの二つに依存するので、テストの補助をパッケージの内部のライブラリに置くと、この検査に掛かる見込みが高い。
  リポジトリに、内部のライブラリの前例はない。
- 毎晩の wasm のテストも golem-driver のスイートを走らせる。
  `scripts/wasm/test-failures.tsv` には golem-driver-test の行が 56 あり、`suite-limits.tsv` に 2 行、予算の一覧に止まりの検出（`hangTimeout`、[ADR 0237](0237-raise-the-hang-time-outs-of-golem-driver-test-to-300-seconds.md)）の行がある。

## 実装すること

### キャッシュを保存する組み立てを、臨界経路から外す

- `cabal build all` を組んで `dist-newstyle` を保存する仕事を、新しい job `cache-dist` に移す。
  `cache-dist` は、アーキテクチャごとに一つ動き、`ci` の job の `needs` に入れない。
- `cache-dist` は、今の保存の脚と同じキー、同じ条件（[ADR 0395](0395-bring-the-pull-request-ci-under-five-minutes.md) の項目 4）で保存する。
- tests-driver の脚は、`save: false` にし、自分のスイートだけを組む。

### golem-driver-test を分ける

golem-driver-test を、領域ごとに四つのテストのスイートに分ける。

| スイート | 主なファイル |
| --- | --- |
| golem-driver-pdf-test | `PdfSpec` と、PDF の構造、タグ、フォント、図版の検査 |
| golem-driver-page-test | `PageElementsSpec`、`ParagraphSpec`、注、図版の配置、改ページ |
| golem-driver-output-test | HTML、EPUB、プレーンテキスト、参考文献、索引、相互参照 |
| golem-driver-cli-test | diagnostic、プラグイン、プロジェクト、CLI に近い検査 |

- ファイルの分け方は、実装のプルリクエストで、四つのスイートの実行の時間がなるべくそろうように決め、表をプルリクエストに書く。
- 共通の補助のモジュールは、内部のライブラリにせず、四つのスイートの `other-modules` にそれぞれ書く（`hs-source-dirs` を共有する）。
  補助のモジュールは四回組まれるが、テストだけの依存の検査を変えずに済む。
- テストの名前と数は変えない。

### 脚に配る

tests-driver の脚を二つに分ける。
x86-64 と ARM64 のそれぞれで同じにする。

| 脚 | スイート |
| --- | --- |
| tests-driver-a | golem-driver-pdf-test、golem-driver-cli-test、golem-driver-global-test |
| tests-driver-b | golem-driver-page-test、golem-driver-output-test、golem-driver-parallel-test |

- 割り当ては、実装のプルリクエストで測った実行の時間を見て入れ替えてよい。
  入れ替えたら、表を ADR の実装のプルリクエストに書く。

### wasm と上限の一覧

- `scripts/wasm/test-failures.tsv` の golem-driver-test の行を、分けた後のスイートの名前に付け直す。
- `suite-limits.tsv` と予算の一覧の golem-driver-test の行を、四つのスイートの行に分ける。
  止まりの検出（[ADR 0237](0237-raise-the-hang-time-outs-of-golem-driver-test-to-300-seconds.md)）の値は、四つのスイートのどれにも同じ値を当てる。

### 見込み

上の表の 45055120571 の値から見積もる。
tests-driver の脚は、今は dist の復元 14 秒、`cabal build` 226 秒、テスト 138 秒である。
`cabal build` のうち、golem-driver-test の 121 秒は最後の一つのコンポーネントとして走る。
四つに分けると、四つのスイートが並列に組まれ、各脚は自分の二つ（と小さな一つ）だけを組む。
脚あたりのテストの実行は、138 秒の半分ほどになる。
各スイートの組み立てが 121 秒の 3 分の 1 で済むと仮定すると、脚は 14 + (226 − 121 + 40) + 70 ≒ 230 秒、臨界経路は `changes` と `ci` を足して 270 秒ほどになる。
3 分の 1 という仮定と、テストの時間が半分になることは確かめていない（推測）。

### 測る

- 実装のマージの後の、成功したプルリクエストの `ci.yml` 20 回の中央値を、`scripts/ci/ci-critical-path.sh` で測り、`docs/ci-timings/` に記録する。
- 中央値がまだ 300 秒を超えるときは、臨界経路の脚を測り直し、次の手を新しい ADR で決める。
  候補は、根に近いモジュールの組み替え（`Golem.Syntax.Diagnostic` と `Golem.Project.Style` を変えても組み直す範囲が広がらない形）と、`Golem.Typeset.Flow` と golem-project-test の `Main` の分割である。

## 実装しないこと

- テストを消したり、毎晩のジョブに移したりしない。
- 検査を減らさない。
- 大きなランナー（[ADR 0009](0009-ci-speed.md)）は使わない。
- この ADR では、ライブラリのモジュールの構成は変えない。

## 不変条件

- I1：分けた後の四つのスイートのテストの名前の集合の和は、分ける前の golem-driver-test のテストの名前の集合に等しく、四つの集合は互いに交わらない。
- I2：プルリクエストの CI のどのアーキテクチャでも、golem-driver の各スイートは、build の脚のちょうど一つで走る。
- I3：`cache-dist` は、`ci` の job の `needs` に入らず、保存するキーと条件は、この ADR の前の保存の脚と同じである。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| 分ける前と後の `--list-tests` | 名前の集合が等しく、交わらない | I1 |
| ある脚の一覧からスイートを一つ落とした変更 | 検査が失敗 | I2 |
| 同じスイートを二つの脚に置いた変更 | 検査が失敗 | I2 |
| `cache-dist` を `ci` の `needs` に足した変更 | 検査が失敗 | I3 |

## 受けいれ条件

- A1：実装のマージの後の 20 回の中央値を `docs/ci-timings/` に記録する。
  予算を満たすかどうかは、この ADR の受けいれ条件としない。
  満たさなければ、上の「測る」の手順で次の ADR を書く。

## テスト設計

- 名前は `root ADR 0416 I<番号>: ...` とする。
- I1 は、実装のプルリクエストで一度だけ確かめる。
  分ける前の `golem-driver-test --list-tests` の出力と、分けた後の四つのスイートの出力の和を比べ、結果をプルリクエストに書く。
  ずっと続ける検査にはしない（テストを足すたびに golden を直すことになるため）。
- I2 と I3 は、ワークフローの形を読む検査として `scripts/ci/test.sh` に置き、変更の前に失敗することを確かめる。
  [ADR 0395](0395-bring-the-pull-request-ci-under-five-minutes.md) の A1 の検査（プルリクエストが走らせるチェックの一覧）も、新しい脚と `cache-dist` に合わせて直す。
- テストの時間の上限（[ADR 0292](0292-limit-the-time-of-each-test-suite-by-the-median-of-main.md)）の一覧に、四つのスイートの行を足す。

## トレードオフ

スイートを分けると、テストのファイルの置き場所と、テストを足すときに選ぶスイートが増える。
補助のモジュールは四回組まれ、リンクも四回になるので、全体の CPU の時間は増える。
`cache-dist` は臨界経路の外で `cabal build all` を組むので、ランナーの時間も増える。
代わりに、臨界経路の脚は自分のスイートだけを組み、テストの実行も二つの脚に分かれる。
縮む量は見込みであり、実装の後に測る。

## 参考文献

- [ADR 0392](0392-budget-the-pull-request-ci-at-five-minutes.md)
- [ADR 0395](0395-bring-the-pull-request-ci-under-five-minutes.md)
- [ADR 0415](0415-fix-the-medium-findings-of-the-conformance-audit-of-2026-11-18.md)
- [ADR 0292](0292-limit-the-time-of-each-test-suite-by-the-median-of-main.md)
- [ADR 0028](0028-shared-test-support-package.md)
- [ADR 0191](0191-semantic-ir-generator-module.md)
- [ADR 0237](0237-raise-the-hang-time-outs-of-golem-driver-test-to-300-seconds.md)
- [ADR 0009](0009-ci-speed.md)
