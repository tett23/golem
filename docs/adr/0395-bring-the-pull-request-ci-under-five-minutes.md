# ADR 0395: プルリクエストの CI を 5 分の予算に収める

Status: superseded [{"by":["docs/adr/0414-record-what-the-implementations-of-adr-0370-and-0395-decided.md"],"part":"I2 の残すキャッシュの単位","kind":"supplement"}]

## 文脈

[ADR 0392](0392-budget-the-pull-request-ci-at-five-minutes.md) は、プルリクエストの `ci.yml` の時間の中央値を 300 秒以下とする予算を決めた。
時間は、ジョブの依存をたどった最も長い道の秒で、ランナーの順番待ちを含めない。
今の CI はこの予算を超えており、[ADR 0392](0392-budget-the-pull-request-ci-at-five-minutes.md) は収める組み替えを別の ADR で決めるとした。
仕様書の設計原則も、CI を版によらず常に 5 分以内に保つと書いている。

tett23 は、2026-11-18 に次のとおり決めた。

- 検査を減らさない。
- 何も失わない改善と、プルリクエストごとの `dist-newstyle` のキャッシュで収める。
- 推定が予算の境目にあることを承知のうえで、実装して測る。
- 予算に収まらないとき、または収まっても安全な幅が無いときは、コードに手を入れてコンパイルの時間を縮める手も取る。

この ADR は、その組み替えと、選ばなかった案と理由を記録する。
選ばなかった案は、同じ問題が再び起きたときに、同じ調べを繰り返さないための記録である。

## 調査した事項

この節の値は、2026-11-18 に auditor（Fable 5.2）が、origin/main の [`0c3a675c`](https://github.com/tett23/golem/tree/0c3a675cdf1aa84ad6d939f95dd13890a8355a9b) と、成功したプルリクエストの `ci.yml` の直近 20 回（実行 44117694432 から 44176039261、`build` を省いた実行は除く）の、ジョブとステップの時刻とログから求めた。
ジョブは `gh api repos/tett23/golem/actions/runs/<id>/jobs` で取り、時間は [`ci-critical-path.sh`](https://github.com/tett23/golem/blob/0c3a675cdf1aa84ad6d939f95dd13890a8355a9b/scripts/ci/ci-critical-path.sh) と同じ計算で求めた。
案ごとの推定は、同じ 20 回の実測値を組み替えて計算し直した値であり、変えた CI を実際に動かしてはいない。

### 今の時間の内訳

- 中央値は 502.5 秒で、実行ごとに 260 秒から 691 秒だった。300 秒以下は 3 回だった。
- 最も長い道を終えるジョブは、20 回のうち 17 回が `build` の後の `determinism`、2 回が `wasm`、1 回が `verapdf` だった。
- 中央値は、`changes` 16 秒、`build` の最も長いレッグ 437 秒、`determinism` 10 秒、`ci` 25.5 秒である。`ci` の 25.5 秒のうち 18 秒は、ログの warning を探す手順（[ADR 0245](0245-keep-the-warnings-of-ci-at-zero.md)）である。
- `build` の各レッグは、`cabal build` の前に 43 秒から 49.5 秒（チェックアウト、GHC、索引、store、`dist-newstyle` の復元）、`cabal build` に 206 秒から 219.5 秒（中央値）を使う。
- x86-64 の `outputs` のレッグは、`cabal build` の後に 144 秒の手順（見た目の回帰の PDF、wasm と比べる一覧、適合の PDF、epubcheck、決定性の出力、マニュアルのプリフライト、成果物の上げ）を持つ。
- `golem-driver-test` の実行は中央値 124 秒で、`tests-driver` のレッグのテストの手順（132.5 秒）をほぼ決める。

### `cabal build` が長い理由

- 20 回は、x86-64 の `outputs` の `cabal build` が 100 秒を超える 13 回と、4 秒から 55 秒の 7 回に分かれる。最も長い道の中央値は、前者が 542 秒、後者が 308 秒である。
- 遅い 13 回は、依存の根に近いファイル（`golem-syntax` の `Diagnostic.hs` が 5 回、`golem-project` の `Style.hs` が 6 回など）を変えた実行である。
- 遅い 13 回のうち 7 回は、同じブランチの 2 回め以降の push である。プルリクエストは `dist-newstyle` を保存しないので（[`ci.yml`](https://github.com/tett23/golem/blob/0c3a675cdf1aa84ad6d939f95dd13890a8355a9b/.github/workflows/ci.yml#L621-L626)、[ADR 0228](0228-keep-the-ci-caches-under-the-10-gb-limit.md) の I1）、push のたびに同じコンパイルをやり直す。
- 全レッグが `cabal build all` でテストスイートまで組む（[`ci.yml`](https://github.com/tett23/golem/blob/0c3a675cdf1aa84ad6d939f95dd13890a8355a9b/.github/workflows/ci.yml#L355-L358)）。遅い 13 回の x86-64 の `outputs` では、`golem` のリンクから `cabal build` の終わりまでの差の、実行ごとの中央値は 78 秒で、これがテストスイートの分である。`outputs` と `env` の手順が使う実行ファイルは `golem` だけである（`cabal list-bin -v0 golem`）。
- コンパイルを 0 秒としても、今の形の中央値は 278.5 秒である。チェックアウトとキャッシュの復元と直列のジョブの固定費だけで、予算のほとんどを使う。

### プルリクエストのキャッシュで縮む時間

- [ADR 0228](0228-keep-the-ci-caches-under-the-10-gb-limit.md) の実測では、プルリクエストのキャッシュは、二度め以降の push の x86-64 の `cabal build` の中央値を 47 秒から 14 秒に縮めたが、第 3 四分位は 107 秒と 106 秒でほとんど変わらなかった。二度めの push までに `main` が進み、古いプルリクエストのキャッシュからは `main` の変更を組み直すことが多いためである（[ADR 0228](0228-keep-the-ci-caches-under-the-10-gb-limit.md) の「調査した事項」）。
- `restore-keys` の前方一致は、まずプルリクエストの範囲を探し、なければベースのブランチの範囲を探す（[ADR 0228](0228-keep-the-ci-caches-under-the-10-gb-limit.md)）。
- プルリクエストのキャッシュは、そのプルリクエストのマージの ref（`refs/pull/N/merge`）に作られ、ほかのプルリクエストからもベースのブランチからも戻せない（GitHub の Dependency caching reference の「Restrictions for accessing a cache」）。

### キャッシュの量

- 2026-11-18 の Actions のキャッシュの合計は 8.56 GB で（`gh api repos/tett23/golem/actions/cache/usage`）、予算は 10 GB である（[ADR 0228](0228-keep-the-ci-caches-under-the-10-gb-limit.md) の I5）。`refs/heads/main` のものは 3.73 GB である。
- プルリクエストの ref のキャッシュが残っている。たとえば、`refs/pull/962/merge`（開いている）、`refs/pull/953/merge` と `refs/pull/948/merge`（閉じている）の `ghc-wasm` がそれぞれ 1195.5 MB、閉じたプルリクエストの `cabal-store` が 256.7 MB から 345.2 MB ある（`gh api repos/tett23/golem/actions/caches`）。
- `main` の `dist-newstyle` は、x86-64 が 380.0 MB、arm が 589.8 MB である。
- 2026-11-18 に開いているプルリクエストは 12 件である（`gh pr list --state open`）。一つのプルリクエストが `dist-newstyle` を一組（約 970 MB）だけ持つとしても、`main` の分を除いた残りに入るのは約 6 件である。

## 実装すること

### 何も失わない改善

1. **`outputs` と `env` のレッグは `golem` の実行ファイルだけを組む。** テストスイートは、テストのレッグが組む。[`test-only-deps.sh`](https://github.com/tett23/golem/blob/0c3a675cdf1aa84ad6d939f95dd13890a8355a9b/scripts/ci/test-only-deps.sh) と [`doc-deps.sh`](https://github.com/tett23/golem/blob/0c3a675cdf1aa84ad6d939f95dd13890a8355a9b/scripts/ci/doc-deps.sh) が読む計画（`plan.json`）が、全体を組むときの計画と等しいことを、二つの計画の要素の一覧を比べる検査で確かめる。
2. **`tests-rest` のレッグは、自分が走らせるテストスイートだけを組む。** `dist-newstyle` を保存するレッグ（今 `matrix.save` が真のレッグ、[`ci.yml`](https://github.com/tett23/golem/blob/0c3a675cdf1aa84ad6d939f95dd13890a8355a9b/.github/workflows/ci.yml#L150-L178)）は、保存するキャッシュがすべてを含むように、今のとおり `cabal build all` で組む。
3. **x86-64 の `outputs` の `cabal build` の後の手順を、二つのレッグに分ける。** 成果物を待つジョブ（`visual`、`verapdf`、`wasm`、`editors-lsp`）が待つ成果物を作る手順を一つめのレッグに、そのほかの手順を二つめのレッグに置く。どの手順も、今と同じく必ず走らせる。[ADR 0244](0244-take-verapdf-off-the-critical-path-of-ci.md) は、ランナーを足すと用意に約 45 秒かかり、復元の量が増えるとして三つめのテストのランナーを退けたが、ここでは `outputs` の 144 秒の手順を分けるので、用意の費用を上回る短縮を見込む。

### プルリクエストごとの `dist-newstyle` のキャッシュ

4. **プルリクエストでも `dist-newstyle` を保存する。** 保存の条件は、`main` と同じく `cabal build` が何かをコンパイルしたときとする。キーは、今の族の前の部分にプルリクエストの番号とコミットのハッシュを足したものとする。同じプルリクエストの次の push は、`restore-keys` の前方一致で、自分の最新のものを戻す。それが無ければ、今のとおり `main` のものを戻す。
5. **キャッシュを消すワークフローを足す。** このワークフローは、プルリクエストの変更が書き換えられないよう、既定のブランチの定義で走る契機（`workflow_run` と `pull_request_target`）で動かし、プルリクエストのコードをチェックアウトしない。`actions: write` はこのワークフローのジョブにだけ与える。消すものは次のとおりである。
   - `ci.yml` の実行が終わったとき：同じプルリクエストの `dist-` のキャッシュのうち、最新のもの以外。
   - 同じとき：合計が 9 GB を超えていれば、開いているプルリクエストの `dist-` のキャッシュを、作った日時の古いものから、9 GB の下になるまで。
   - プルリクエストが閉じたとき（マージを含む）：そのプルリクエストの ref のキャッシュのすべて。
   - 今残っている、閉じたプルリクエストのキャッシュは、実装の PR で一度消す。
6. **[ADR 0228](0228-keep-the-ci-caches-under-the-10-gb-limit.md) の I1 と、その境界の表の「最初の push」と「二度めの push」の行を、この ADR で置き換える。** [ADR 0228](0228-keep-the-ci-caches-under-the-10-gb-limit.md) は、プルリクエストのキャッシュを閉じたときに消す案を、量が開いているプルリクエストの数で決まることと、`actions: write` をプルリクエストが書き換えられるワークフローに与えることの二つで退けた。量は項目 5 の上限で抑え、権限は既定のブランチの定義で走るワークフローに限る。[ADR 0228](0228-keep-the-ci-caches-under-the-10-gb-limit.md) のステータスの行に、置き換えた部分を記録する。`scripts/ci/test.sh` の [ADR 0228](0228-keep-the-ci-caches-under-the-10-gb-limit.md) の I1 の検査は、この ADR の不変条件の検査に置き換える。

### 測り直す

7. 実装のマージの後の、成功したプルリクエストの `ci.yml` の 20 回（`build` を省いた実行を除く）で、`scripts/ci/ci-critical-path.sh` の中央値を測り、`docs/ci-timings/` に記録する。
8. 中央値が 300 秒を超えるとき、または 300 秒との差が 30 秒に満たないときは、コンパイルの時間を縮める変更を加える。候補は、`golem-driver-test` の分割と `-j` による並列のコンパイル（「今は入れず、測ってから決める案」）と、依存の根に近いモジュール（`Golem.Syntax.Diagnostic`、`Golem.Project.Style` など）を変えても組み直す範囲が広がらないようにするコードの組み替えである。どれを入れるかは、測った値を添えて別の ADR で決める。

### 文書

9. 仕様書と開発者のマニュアルの CI のジョブとキャッシュの説明、`docs/budgets.md` の注記、CONTRIBUTING.md を、この ADR に合わせて直す。

## 実装しないこと

選ばなかった案と理由は次のとおりである。
推定の値は、同じ 20 回の実測値を組み替えた中央値である。

### 検査を毎晩に移す案

- **テストのレッグを毎晩に移す**（`tests-driver` だけで推定 476.5 秒、`tests-rest` だけで 475.5 秒、4 レッグすべてで 464.5 秒）。プルリクエストでテストを走らせなくなり、失敗がマージの後に出る。[ADR 0291](0291-run-the-tests-of-every-package-on-every-change.md) は、テストをプルリクエストでだけ省く案を、省いたテストの失敗がマージの後に見つかり、`main` が壊れた状態でほかのプルリクエストが基づくとして退けており、同じ理由が当てはまる。[ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md) も、列挙の範囲のすべての述語をプルリクエストに残すと決めている。4 レッグすべてを移し、`outputs` の分割とログの warning の手順の除去を合わせても推定 300.7 秒で、`outputs` を三つに分けて 280.9 秒である。tett23 は、検査を減らさない案を選んだ。
- **arm のレッグを毎晩に移す**（推定 486.5 秒）。アーキテクチャのあいだのバイトの一致を、プルリクエストで確かめなくなる。[ADR 0009](0009-ci-speed.md) は、aarch64 の `build` を省くことと `main` への push だけで走らせることを、同じ理由で退けている。
- **`wasm`、`visual`、`verapdf`、`editors-lsp`、`scripts-macos` を毎晩に移す**（推定 484.0 秒）。どれも最も長い道にほとんど居ないので、効果が小さい。`wasm` を毎晩だけ走らせることは [ADR 0219](0219-frequency-of-the-wasm-job-and-its-uncached-runs.md) と [ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md) が、`verapdf` を `main` への push だけで走らせることは [ADR 0244](0244-take-verapdf-off-the-critical-path-of-ci.md) が退けている。

### 変更の無いパッケージのテストを省く案

- 推定 475.5 秒から 502.5 秒。20 回のすべてで `golem-driver-test` が組み直しの計画に入っていたので、依存の閉包で選んでも `tests-driver` は一度も省けない。[ADR 0291](0291-run-the-tests-of-every-package-on-every-change.md) は、テストがほかのパッケージのファイルを相対のパスで読むので依存の閉包だけでは足りず、一覧が漏れると壊したテストを省いたまま CI が通るとして、この案を退けている。

### 検査をやめる案

- **`visual` をやめる**（推定 478.2 秒）、**`wasm` をやめる**（487.0 秒）、**`verapdf` をやめる**（494.0 秒）、**epubcheck とマニュアルのプリフライトをやめる**（478.0 秒）。それぞれ、ページの見た目の回帰、native と wasm の一致、PDF/A と PDF/UA、EPUB の妥当性とマニュアルのフォントとインクを確かめなくなる。
- **`visual`、`wasm`、`verapdf`、epubcheck とプリフライトを合わせてやめる**（推定 468.0 秒）。上の性質をすべて失い、しかも `tests-driver` が残るので 300 秒に届かない。
- **`determinism` と arm の `outputs` をやめる**（推定 471.0 秒）。アーキテクチャのあいだのバイトの一致と、記録したハッシュとの一致を確かめなくなる。
- **`scripts-macos` と `env` のレッグをやめる**（どちらも 502.5 秒）。最も長い道に居ないので、予算は動かない。`scripts-macos` の順番待ち（中央値 124 秒）は予算の外である。

### 直列のジョブを減らす案

- **`determinism` ジョブの比較を `ci` ジョブの中で行う**（約 10 秒の短縮）。[ADR 0037](0037-ci-build-job-speedup.md) は、判定のジョブの形（[ADR 0021](0021-docs-workflow-and-ci-gate.md)）を変えるとしてこの案を退けた。加えて、ログの warning の検査は `ci` 自身のログを読まないので（[ADR 0245](0245-keep-the-warnings-of-ci-at-zero.md)）、比較の手順のログが検査から外れる。何も失わない改善に当たらないので選ばなかった。
- **ログの warning の手順を `ci` の外の別のジョブに移す**（推定 483.5 秒）。`ci` の最も長い道からは外れるが、マージは別のジョブの終わりを待つので、書き手が待つ時間は縮まない。測る値だけを下げるので選ばなかった。

### ランナーとビルドの共有の案

- **大きいランナー**（コンパイルが 2 倍速いと仮定して推定 377.5 秒）。[ADR 0009](0009-ci-speed.md) は、個人のアカウントでは使えず、使えても分単位で課金されるとして退けている。2 倍でも 300 秒に届かない。
- **一度組んで成果物をほかのレッグに渡す**。道が「組む、上げる、下ろす、テスト」になり、組む時間は減らないので、今より長くなる見込みである（未確認）。[ADR 0037](0037-ci-build-job-speedup.md) と [ADR 0097](0097-ci-same-path-before-build-and-env-check-runner.md) が退けている。

### 今は入れず、測ってから決める案

- **`golem-driver-test` を二つのシャードに分けて走らせる**（項目 1 と 2 と合わせて推定 415.4 秒）。シャードごとに `golem-driver-test` のコンパイルが要り、スイートごとの時間の上限（[ADR 0292](0292-limit-the-time-of-each-test-suite-by-the-median-of-main.md)）もスイートの単位なので、仕組みを作り直す。
- **`golem-driver-test` のコンパイルを `-j` で並べる**。遅い回の最後の 64 秒はほかに何もコンパイルしていないが、`-j` で縮むかは確かめていない。

## 不変条件

- I1: キャッシュを消すスクリプトは、入力のキャッシュの一覧のうち、閉じたプルリクエストの ref（`refs/pull/N/merge`）のものをすべて消す対象にし、`refs/heads/main` のものを対象にしない。
- I2: キャッシュを消すスクリプトは、同じプルリクエストの `dist-` のキャッシュのうち、作った日時の最も新しいもの以外を消す対象にする。
- I3: キャッシュを消すスクリプトが合計を下げるとき、消す対象は開いているプルリクエストの `dist-` のキャッシュで、作った日時の古いものから、合計が 9 GB の下になる最小の個数である。
- I4: `ci.yml` の `pull_request` の実行が保存する `dist-` のキーは、プルリクエストの番号を含み、`main` の族のキーと前の部分で区別できる。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| 閉じたプルリクエストのキャッシュが三つ | 三つとも消す対象 | I1 |
| `main` のキャッシュ | 消す対象にしない | I1 |
| 同じプルリクエストの `dist-` が二つ | 古いほうだけ消す対象 | I2 |
| 同じプルリクエストの `dist-` が一つ | 消す対象にしない | I2 |
| 合計がちょうど 9 GB | 合計を下げる対象は無い | I3 |
| 合計が 9 GB を 1 バイト超える | 最も古い開いたプルリクエストの `dist-` を一つ | I3 |
| `pull_request` の保存のキー | `main` の族と区別できる | I4 |

## 受けいれ条件

- A1: 実装の後、プルリクエストの CI が走らせる検査は前と等しい。`cabal build` より後の手順の名前と `run` と `if` の組の集合、`cabal test` に渡すスイートの集合、`ci` が待つ検査の集合を、実装の前のコミットと比べて確かめる。手順を置くレッグが変わることだけが違う。
- A2: 項目 7 の中央値を `docs/ci-timings/` に記録する。300 秒以下なら予算を満たす。超えるか、300 秒との差が 30 秒に満たなければ、項目 8 の ADR を作る。

## テスト設計

テストの名前は `ADR 0395 I<n>: ` と `ADR 0395 A<n>: ` で始める。

- I1 から I3 は、キャッシュを消すスクリプトが `gh` の代わりに JSON の一覧を入力に取れるようにして、境界の表の行をそれぞれ一つのケースとして確かめる。テストは `scripts/ci` のテストと同じ置き場所と形で書く。
- I4 は、`ci.yml` から保存のキーの形を読む検査で確かめる。
- A1 は、`ci.yml` から上の三つの集合を作るスクリプトのテストで、実装の前のコミットで作った一覧と比べる。
- A2 は、実装の後に計測して記録する。

## トレードオフ

- 推定は、項目 1 から 4 と同じ形を、同じ 20 回の実測値に当てて組み替えた値で、中央値はおよそ 304 秒、300 秒以下は 20 回のうち 9 回である（ログの warning の手順を残し、`determinism` は今の 10 秒とし、保存の手順に 5 秒を足した値）。
- この推定は、同じプルリクエストの 2 回め以降の push の `cabal build` が 45 秒以下になるという仮定に依る。[ADR 0228](0228-keep-the-ci-caches-under-the-10-gb-limit.md) の実測では、第 3 四分位が 106 秒で、仮定が外れる実行は少なくない。仮定が外れると、推定はさらに上がる。A2 で測り、超えれば項目 8 で見直す。
- プルリクエストごとの `dist-newstyle` は、約 970 MB である。開いているプルリクエストが 6 件を超えるあたりから、古いもののキャッシュが消され、その push は速くならない。
- 依存の根に近いファイルを変える最初の push は、キャッシュがあっても組み直すので、速くならない。速い実行も 290 秒から 300 秒の近くにあるので、予算との余裕は数秒しかない。

## 参考文献

- [ADR 0392](0392-budget-the-pull-request-ci-at-five-minutes.md)
- [ADR 0228](0228-keep-the-ci-caches-under-the-10-gb-limit.md)
- [ADR 0291](0291-run-the-tests-of-every-package-on-every-change.md)
- [ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md)
- [ADR 0009](0009-ci-speed.md)
- [ADR 0021](0021-docs-workflow-and-ci-gate.md)
- [ADR 0037](0037-ci-build-job-speedup.md)
- [ADR 0097](0097-ci-same-path-before-build-and-env-check-runner.md)
- [ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md)
- [ADR 0219](0219-frequency-of-the-wasm-job-and-its-uncached-runs.md)
- [ADR 0244](0244-take-verapdf-off-the-critical-path-of-ci.md)
- [ADR 0245](0245-keep-the-warnings-of-ci-at-zero.md)
- [ADR 0292](0292-limit-the-time-of-each-test-suite-by-the-median-of-main.md)
- GitHub, "Dependency caching reference"（「Restrictions for accessing a cache」の節）. https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching
