# ADR 0228: CI のキャッシュの量を 10 GB の上限の下に保つ

ステータス: 採択→記録の時期は [ADR 0236](0236-record-what-implementations-decided-found-by-the-second-review-of-2026-11-08.md)、`release.yml` の `ci` の呼び出しの権限は [ADR 0287](0287-keep-actions-write-of-the-ci-call-in-release-yml-for-the-caches-job-alone.md)

## 文脈

ロードマップの v0.1.0-rc4 の「CI」は、リポジトリの Actions のキャッシュが 10 GB の上限を超えていると書く。
[ADR 0219](0219-frequency-of-the-wasm-job-and-its-uncached-runs.md) は `wasm` ジョブの `dist-wasm` の保存を `main` への push だけにしたが、`build` ジョブの `dist-newstyle` の保存は別の ADR に回した。
この ADR が、その保存の扱いを決める。

### 今のキャッシュ

2026-11-08T03:17Z ごろに、`gh api repos/tett23/golem/actions/cache/usage` と `gh api repos/tett23/golem/actions/caches --paginate` で数えた。
キャッシュは 36 個で、合わせて 10,889,469,901 バイトある。

| キャッシュ | 範囲 | 個数 | バイト |
| --- | --- | --- | --- |
| `dist-Linux-ARM64-…`（aarch64 の `dist-newstyle`） | プルリクエスト | 7 | 3,825,689,944 |
| `dist-Linux-X64-…`（x86-64 の `dist-newstyle`） | プルリクエスト | 6 | 2,057,953,563 |
| `dist-Linux-ARM64-…` | `main` | 3 | 1,639,189,670 |
| `dist-Linux-X64-…` | `main` | 3 | 1,028,474,583 |
| `dist-wasm-…` | `main` | 3 | 351,302,472 |
| そのほか（GHC、wasm のツールチェーン、cabal の store、Hackage の索引、cddl、フォント、epubcheck など） | `main` | 14 | 1,986,859,669 |

範囲ごとの合計は、`main` が 5.01 GB、プルリクエストが 5.89 GB（#679 が 3.22 GB、#682 が 1.78 GB、#680 が 0.89 GB）である。
一つの `dist-newstyle` は、x86-64 で約 343 MB、aarch64 で約 546 MB あり、`dist-wasm` は約 117 MB ある。
そのほかの 14 個のうち最大は、wasm のツールチェーンと store（`ghc-wasm-…`、1,186 MB）である。

`dist-` で始まるキャッシュでいちばん古いものは 02:35:15Z に作られていた。
数えた時点から 42 分ほど前である。
それより前に保存した `dist-` は、どれも GitHub が上限を超えた分として消していた。

### 保存の頻度

`gh run list -w ci.yml -L 200` の実行（2026-11-07T07:11Z から 2026-11-08T03:16Z までの約 20 時間）について、`gh api .../runs/<id>/jobs` で `tests-driver` の二つのジョブの `Save dist-newstyle` のステップが成功した回数を数えた。

| イベント | 実行 | 保存した実行 | 保存の回数 | 量の見積もり |
| --- | --- | --- | --- | --- |
| `main` への push | 60 | 44 | 88 | 約 39 GB（ほかに `dist-wasm` が最大で約 5 GB） |
| プルリクエスト | 139 | 76 | 150 | 約 67 GB |

保存はどちらも、キーの終わりにコミットのハッシュを持つ（[`ci.yml` の `main` の保存](https://github.com/tett23/golem/blob/d6fd7b349d3cbb638ccc57e67cb6de052dcb5e03/.github/workflows/ci.yml#L517-L526)、[プルリクエストの保存](https://github.com/tett23/golem/blob/d6fd7b349d3cbb638ccc57e67cb6de052dcb5e03/.github/workflows/ci.yml#L527-L537)）。
同じキーを二度保存することがないので、保存のたびに 0.89 GB が増える。

プルリクエストの保存をやめても、上限の下には収まらない。
`main` だけで、20 時間に上限の 4 倍近くを保存しているからである。
`main` の保存のうち 11 回は、`cabal build` が何もコンパイルしなかった実行のもので、戻したキャッシュと同じ中身を新しいキーで保存していた。
プルリクエストの保存は、GHC がコンパイルしたときに限る（[`compiled` の出力](https://github.com/tett23/golem/blob/d6fd7b349d3cbb638ccc57e67cb6de052dcb5e03/.github/workflows/ci.yml#L315-L324)）が、`main` の保存にはこの条件がない。

### 上限を超えると何が起きるか

GitHub は上限を超えた分を、最後に使われた日時の古いものから消す（Dependency caching reference の「Usage limits and eviction policy」）。
`main` の最新の `dist-newstyle` とツールチェーンは、ビルドのたびに読まれるので、今のところ消されずに残っている。
消されているのは、主に古い `dist-` である。

それでも、上限に張りついたままでは困ることがある。
一つめに、プルリクエストの自分のキャッシュが、次の push までに消されうる。
上の 20 時間では、二度め以降の push の 71 回のうち 11 回で、プルリクエストのキャッシュがなく `main` のものを戻していた。
二つめに、ビルドのたびには読まれないキャッシュは、ほかの保存が続くと消されうる。
今は保存するのがビルドを走らせた実行だけで、その実行がツールチェーンも読むので、ツールチェーンが消された記録はない。
ただ、それは保存と読み出しの順に頼った結果で、`ghc-wasm-…`（1.19 GB）が消されれば、`wasm` は [ADR 0219](0219-frequency-of-the-wasm-job-and-its-uncached-runs.md) が記録した 973 秒かかる。
三つめに、キャッシュの量が上限で決まるので、どのキャッシュが残るかを CI の設定から読めない。

### プルリクエストのキャッシュが役に立つ範囲

プルリクエストのキャッシュは、そのプルリクエストのマージの ref（`refs/pull/N/merge`）に作られ、ほかのプルリクエストからも、ベースのブランチからも戻せない。
プルリクエストの実行は、ベースのブランチのキャッシュも戻せる（Dependency caching reference の「Restrictions for accessing a cache」）。
`restore-keys` の前方一致は、まずプルリクエストの範囲を探す（[ADR 0045](0045-split-x86-build-and-pull-request-cache.md)）。

同じ 20 時間の `tests-driver` のジョブのログから、戻したキャッシュの範囲（ログの `Cache restored from key:`）と、`cabal build all peg-cli:exe:peg-hs` のステップの秒を取った。

| 実行 | 戻した範囲 | x86-64 の `cabal build`（件数、中央値、第 3 四分位、最大） | aarch64 の `cabal build`（同） |
| --- | --- | --- | --- |
| プルリクエストの最初の push | `main` | 39 件、47、107、208 | 40 件、39、113、198 |
| 二度め以降の push | プルリクエスト | 60 件、14、106、248 | 60 件、15、104、203 |
| 二度め以降の push | `main` | 11 件、3、24、203 | 11 件、3、28、183 |

プルリクエストのキャッシュは中央値を 47 秒から 14 秒に縮めるが、第 3 四分位はほとんど変わらない。
並んだ作業がおよそ 27 分に一度マージされる（20 時間に 44 回）ので、二度めの push までに `main` が進み、プルリクエストの古いキャッシュからは `main` の変更をビルドし直すことが多いためである。
[ADR 0045](0045-split-x86-build-and-pull-request-cache.md) も同じことを書いている。
保存のステップは、プルリクエストで x86-64 が中央値 5 秒、aarch64 が 6 秒だった。

同じ 20 時間で、`build` まで走って成功したプルリクエストの実行は、全体で中央値 266 秒、第 3 四分位 344 秒だった（57 件）。
CONTRIBUTING は、CI の実行時間を 5 分以内に保つと定める（[`CONTRIBUTING.md`](https://github.com/tett23/golem/blob/d6fd7b349d3cbb638ccc57e67cb6de052dcb5e03/CONTRIBUTING.md#L378-L385)）。

### 古いキャッシュを消す権限

キャッシュを消すには、トークンに `actions: write` が要る（Managing caches の「Force deleting cache entries」の例は、ジョブに `actions: write` を与えている）。
`ci.yml` は、[ADR 0035](0035-security-hardening.md) に従ってワークフローの全体を `contents: read` にしている（[`ci.yml`](https://github.com/tett23/golem/blob/d6fd7b349d3cbb638ccc57e67cb6de052dcb5e03/.github/workflows/ci.yml#L11-L14)）。
それより広い権限を持つのは、`actions: read` を持つ `visual` だけである（[`ci.yml`](https://github.com/tett23/golem/blob/d6fd7b349d3cbb638ccc57e67cb6de052dcb5e03/.github/workflows/ci.yml#L760-L764)）。
[ADR 0009](0009-ci-speed.md) と [ADR 0045](0045-split-x86-build-and-pull-request-cache.md) は、古い `dist-newstyle` を消すことを、この権限を理由に扱わなかった。
ただし、その二つが決めたころの保存の頻度は、今よりずっと低かった（[ADR 0009](0009-ci-speed.md) の時点でキャッシュは 33 個、約 3.7 GB）。

上限は、リポジトリの管理者が 10 GB より上げられ、超えた分は課金される（Dependency caching reference の「Increasing cache size」）。

## 実装すること

### プルリクエストの `dist-newstyle`

- `build` の「Save dist-newstyle of the pull request (docs/adr/0045)」のステップを除く。プルリクエストは `dist-newstyle` を保存しない（「メンテナーが決めること」の 1）。
- `Restore dist-newstyle` のステップは変えない（[`ci.yml`](https://github.com/tett23/golem/blob/d6fd7b349d3cbb638ccc57e67cb6de052dcb5e03/.github/workflows/ci.yml#L288-L293)）。プルリクエストは `restore-keys` の前方一致で `main` の最新の `dist-newstyle` を戻す。
- `race.yml` と `enum.yml` は `main` の `dist-newstyle` を戻すだけなので、変えない（[`race.yml`](https://github.com/tett23/golem/blob/d6fd7b349d3cbb638ccc57e67cb6de052dcb5e03/.github/workflows/race.yml#L100-L106)）。

### `main` の `dist-newstyle` の保存

- `main` への push の `Save dist-newstyle` の条件に、`steps.build.outputs.compiled == 'true'` を足す（「メンテナーが決めること」の 3）。何もコンパイルしなかった実行は、戻したものと同じ中身を保存しない。`dist-wasm` の保存はすでにこの条件を持つ（[`ci.yml`](https://github.com/tett23/golem/blob/d6fd7b349d3cbb638ccc57e67cb6de052dcb5e03/.github/workflows/ci.yml#L675-L683)）。

### `main` の古い `dist-` を消すジョブ

`ci.yml` に、ジョブ `caches` を足す（「メンテナーが決めること」の 2）。

- `needs: [changes, build, wasm]`、`if: always() && github.event_name == 'push' && github.ref == 'refs/heads/main' && needs.changes.outputs.build == 'true'` とする。`build` と `wasm` の保存がどちらも終わった後に走り、どちらかが失敗しても走る。
- このジョブだけが `permissions` に `contents: read` と `actions: write` を持つ。ジョブは、`actions/checkout`（`persist-credentials: false`）のほかにアクションを使わず、リポジトリのビルドもテストも走らせない。
- `gh cache list --ref refs/heads/main --key dist- --limit 100 --json id,key,createdAt` で `main` の `dist-` の一覧を取り、新しいスクリプト `scripts/ci/stale-dist-caches.sh` に渡す。
- `stale-dist-caches.sh` は、一覧（一行に ID、作った日時、キーをタブで区切ったもの）を標準入力から、今のキーの三つの族の前の部分（x86-64 と aarch64 の `dist-newstyle`、`dist-wasm`。キーからコミットのハッシュを除いた部分）を引数から受け取る。消すキャッシュの ID を一行に一つ書く。
  - 三つの族のそれぞれで、作った日時がいちばん新しいもの一つを残し、ほかを消す。日時が同じものは、ID の大きいほうを残す。
  - どの族の前の部分にも一致しない `dist-` のキャッシュ（GHC の版や freeze を替える前の族）は、すべて消す。
  - `dist-` で始まらないキーは、入力にあっても書かない。
- ジョブは、書かれた ID を `gh cache delete` で消し、消したキーと、消す前と後の `gh api repos/{owner}/{repo}/actions/cache/usage` の量をジョブの要約に書く。
- ジョブの失敗は、ジョブを失敗にする。`caches` は、`main` の保護が求めるジョブ `ci` の `needs` に入れない（[`ci.yml`](https://github.com/tett23/golem/blob/d6fd7b349d3cbb638ccc57e67cb6de052dcb5e03/.github/workflows/ci.yml#L975-L979)）。消し損ねたキャッシュは、次の `main` への push で消える（「メンテナーが決めること」の 4）。

### 文書

- README の CI のジョブの表で、`build` の行の「プルリクエストでは、GHC がモジュールをコンパイルしたときに `dist-newstyle` をそのプルリクエストのキャッシュに保存し…」を、プルリクエストは `main` の `dist-newstyle` を戻すだけで保存しない、に書き換える。`caches` の行を足す。
- [ADR 0045](0045-split-x86-build-and-pull-request-cache.md) のステータスの行に、プルリクエストの `dist-newstyle` の保存はこの ADR がやめたと書く。[ADR 0009](0009-ci-speed.md) のステータスの行に、`main` の保存の条件と古い `dist-` を消すことはこの ADR が決めたと書く。
- ロードマップの「CI のキャッシュの量を 10 GB の上限の下に保つこと」を除く。
- 実装のプルリクエストは、前と後の所要時間を `docs/ci-timings/` に記録する。

## 実装しないこと

- **今あるプルリクエストのキャッシュを消すこと**：実装の後は、プルリクエストのキャッシュは増えない。今ある 5.89 GB を足しても、`main` の分（下の見積もりで約 3.0 GB）と合わせて上限の下にあり、使われないまま 7 日で GitHub が消す。手で消すなら、メンテナーの了承を得て `gh cache delete` で消す。
- **`dist-newstyle` の中身を減らすこと**：キャッシュに入れるディレクトリを選ぶことは扱わない。中身の内訳を測っておらず、半分にしても `main` の 20 時間の保存は上限の 2 倍近くある。
- **ツールチェーンのキャッシュ**：GHC、wasm のツールチェーン、cabal の store、Hackage の索引は、キーが外れたときだけ保存する今のままとする。キーを替えた後に残る古いものは、使われないまま 7 日で消える。
- **上限を上げること**：「メンテナーが決めること」の 2 の退けた案に理由を書く。

## 不変条件

| 番号 | 不変条件 |
| --- | --- |
| I1 | プルリクエストの実行は、`dist-` で始まるキャッシュを保存しない。 |
| I2 | `main` への push の実行は、`cabal build` が何もコンパイルしなかったとき、`dist-newstyle` を保存しない。 |
| I3 | `caches` のジョブが成功した直後、`refs/heads/main` の `dist-` のキャッシュは、今のキーの三つの族のそれぞれに多くとも一つである。 |
| I4 | `caches` のジョブは、`dist-` で始まらないキャッシュも、`refs/heads/main` の外のキャッシュも消さない。 |
| I5 | ツールチェーンのキーを替えない定常の状態で、リポジトリのキャッシュの合計は 10 GB の下にある。 |

I5 の見積もりは次のとおりである。
定常の状態で残るのは、三つの族の最新の一つずつ（343 MB、546 MB、117 MB）と、そのほかの 14 個（1,987 MB）で、合わせて約 3.0 GB である。
GHC か wasm のツールチェーンのキーを替えると、古い族が 7 日まで残り、多くとも同じ量（約 2.0 GB）が足される。
二つの `main` への push が重なると、三つの族に二つずつ、一時的に約 1.0 GB が足される。
どれが重なっても約 6 GB で、10 GB の下にある。

境界の場合は次のとおりである。

| 場合 | 保存 | `caches` のジョブ | 戻すキャッシュ |
| --- | --- | --- | --- |
| モジュールを変えたプルリクエストの最初の push | しない（I1） | 走らない | `main` の最新 |
| 同じプルリクエストの二度めの push、再実行 | しない（I1） | 走らない | `main` の最新 |
| 文書だけのプルリクエスト | `build` が走らない | 走らない | なし |
| モジュールを変えた `main` への push | する | 同じ族の古いものを消す（I3） | `main` の一つ前 |
| 何もコンパイルしなかった `main` への push | しない（I2） | 消すものがない | `main` の最新 |
| `build` が失敗した `main` への push | しない | 走り、最新を残す | `main` の最新 |
| 重なった二つの `main` への push | 二つとも保存しうる | 後に終わった方が、作った日時の新しい一つを残す | `main` の最新 |
| freeze か GHC の版を替えた `main` への push | 新しい族に保存する | 古い族をすべて消す | 新しい族は前方一致しないので、なし |
| GitHub の API が失敗した | 変わらない | ジョブが失敗し、`ci` は通る | 変わらない |
| `refs/pull/N/merge` のキャッシュ | 増えない | 消さない（I4） | 7 日で GitHub が消す |

## テスト設計

### スクリプトの自動のテスト

`scripts/ci/test.sh` に、`stale-dist-caches.sh` のテストを先に書いて失敗させる。

- 空の一覧からは何も書かない。
- 三つの族に一つずつあるときは何も書かない。
- 一つの族に三つあるときは、古い二つの ID を書く。
- 作った日時が同じ二つは、ID の小さいほうを書く。
- どの族の前の部分にも一致しない `dist-` のキーの ID を書く。
- `dist-` で始まらないキー（`ghc-…`、`cabal-store-…`）の ID は、入力にあっても書かない（I4）。
- x86-64 の族の前の部分が、aarch64 の族のキーを前方一致で拾わない（`dist-Linux-X64-` と `dist-Linux-ARM64-` を区別する）。

### ワークフローの構造の検査

`scripts/ci/test.sh` の `ci.yml` の検査を、次のように改める（今の検査は [`scripts/ci/test.sh`](https://github.com/tett23/golem/blob/d6fd7b349d3cbb638ccc57e67cb6de052dcb5e03/scripts/ci/test.sh#L1276-L1278)）。

- `github.event_name == 'pull_request'` を条件に持つ `actions/cache/save` のステップがない（I1）。今の「a pull request saves dist-newstyle when GHC compiled」の検査は除く。
- `main` への push の `Save dist-newstyle` の条件が、`steps.build.outputs.compiled == 'true'` を含む（I2）。
- `ci.yml` で `actions: write` を持つジョブは `caches` だけで、その `if` が `github.event_name == 'push' && github.ref == 'refs/heads/main'` を含み、`needs` が `build` と `wasm` を含む。
- `ci` の `needs` が `caches` を含まない。
- `caches` が `actions/checkout` のほかの `uses:` を持たない。

### CI を走らせて確かめること

実装のプルリクエストとそのマージで、次を確かめ、結果をプルリクエストの説明に書く。

- 実装のプルリクエストの実行のログに、`Cache saved with key: dist-` がない（I1）。
- マージの後の `main` への push で、`caches` が走り、`gh api repos/tett23/golem/actions/caches?ref=refs/heads/main` の `dist-` が三つの族に一つずつになる（I3）。`dist-` でないキャッシュの数が変わらない（I4）。
- マージから 24 時間後と 7 日後に、`gh api repos/tett23/golem/actions/cache/usage` の量が 10 GB の下にある（I5）。7 日後には、プルリクエストのキャッシュがなくなっている。
- プルリクエストの所要時間を、`scripts/ci/timings.sh` で 5 回以上集めて `--median` で中央値を取り、上の 20 時間の値（全体で中央値 266 秒、第 3 四分位 344 秒）と比べて `docs/ci-timings/` に記録する。

## トレードオフ

プルリクエストは、二度めの push や再実行でも、`main` の最新から自分の変更をビルドし直す。
上の 20 時間の値から見積もると、二度めの push の `cabal build` は、中央値で 14 秒から最初の push と同じ 40 秒台へ、x86-64 で 30 秒ほど延びる。
第 3 四分位（100 秒台）はほとんど変わらない見込みである。
保存のステップの 5 秒から 6 秒はなくなる。
`tests-driver` がプルリクエストの CI の臨界経路にあるかは測っていないので、実行全体への効果は実装のプルリクエストで測る。
中央値の 266 秒は 5 分に近く、延びた分で超えるなら、CONTRIBUTING のとおりほかの作業を止めて CI を直す。

失敗した実行の再実行は、[ADR 0045](0045-split-x86-build-and-pull-request-cache.md) が測った 17 秒ではなく、最初の実行と同じだけビルドする。
その代わり、`main` の最新のキャッシュは消されず、プルリクエストは古い自分のキャッシュではなく `main` の最新から始める。

`actions: write` のトークンは、ジョブ `caches` のあいだ、リポジトリの Actions の実行、キャッシュ、成果物を操作できる。
このジョブは `main` への push でしか走らず、マージ済みのワークフローとスクリプトだけを動かし、ビルドもテストも走らせない。
プルリクエストの変更がこのジョブのコードとして走ることはない。
[ADR 0035](0035-security-hardening.md) の「読み取りだけ」から外れる箇所を、この一つのジョブに限る。

## メンテナーが決めること

1. **プルリクエストの `dist-newstyle`**：推奨は、保存しないことである。`main` の古いものを消しても、プルリクエストが保存を続ける限り、量は並んだ作業の数で決まる。上限の残り（10 GB から定常の 3.0 GB を引いた 7 GB）に収まるのは、`dist-newstyle` を持つプルリクエストが七つまでで、2026-11-08T01Z の一時間には十二のブランチが CI を走らせていた。
   - 退けた案の一つは、今のまま保存し、プルリクエストを閉じたときに `pull_request` の `closed` で消すことである（Managing caches の「Force deleting cache entries」）。開いているあいだの量は減らず、上の七つの上限を超える。`actions: write` を、プルリクエストの変更が書き換えられるワークフローに与えることにもなる。
   - 二つめは、保存のたびに同じプルリクエストの前のものを消すことである。一つめと同じく、量は開いているプルリクエストの数で決まり、権限の問題も同じである。
   - 三つめは、どちらか一つのアーキテクチャだけ保存することである。aarch64 を除いても一つ 343 MB で、十二のブランチで 4.1 GB になる。もう一方のアーキテクチャは今の効果を失う。
2. **`main` の古い `dist-`**：推奨は、`actions: write` を持つ一つのジョブで、`main` への push のたびに消すことである。`main` の保存だけで 20 時間に約 39 GB あり、消さない限り上限に張りつく。
   - 退けた案の一つは、消さずに GitHub の追い出しに任せることである。今の状態がそれで、プルリクエストのキャッシュが次の push までに消され、ビルドのたびには読まれないキャッシュも消されうる。
   - 二つめは、`main` の保存を一日に一度などに減らすことである。消さずに 10 GB の下に保つには、`main` の保存を 7 日に十回ほどにする必要があり、プルリクエストは最大で一日分のマージをビルドし直す。上の表の最大（200 秒前後）に近づき、5 分の方針と合わない。
   - 三つめは、上限を上げることである。量の増え方は変わらず、超えた分は課金される。
   - 四つめは、`schedule` の別のワークフローで消すことである。同じ `actions: write` が要り、走る間隔のあいだに保存が積み上がる（一時間に約 2 GB）。`ci.yml` のジョブなら、保存の直後に走る。
3. **`main` の保存の条件**：推奨は、コンパイルしたときだけ保存することである。20 時間の 44 回のうち 11 回は、同じ中身を保存していた。消すジョブがあれば量は変わらないが、保存の時間と書き込みが要らなくなり、プルリクエストの保存と同じ条件になる。
   - 退けた案は、今のまま成功したら保存することである。キーにハッシュがあるので保存は失敗しないが、得るものがない。
4. **消すジョブの失敗**：推奨は、ジョブを失敗にし、`ci` の `needs` に入れないことである。消し損ねても次の push で消え、`main` の保護が求める検査を、プルリクエストの変更と関係のない GitHub の API の失敗で止めない。
   - 退けた案の一つは、`ci` の `needs` に入れることである。`ci` は `main` への push でも走るので、API の失敗で `main` が赤くなり、変更の失敗と見分けにくい。
   - 二つめは、失敗を注釈にとどめてジョブを通すことである。消し損ねが続いても気づきにくい。
5. **`dist-newstyle` に入れるものを減らすこと**：推奨は、扱わないことである。cabal の store だけをキャッシュする案は、[ADR 0009](0009-ci-speed.md) の前の状態に戻り、自前のパッケージを毎回すべてビルドする（上の表の最大で 200 秒前後）。パッケージごとに分ける案は、合計の量を減らさない。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-08、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [ADR 0009](0009-ci-speed.md)、[ADR 0035](0035-security-hardening.md)、[ADR 0045](0045-split-x86-build-and-pull-request-cache.md)、[ADR 0140](0140-ci-split-test-runners-and-visual-pdfs-first.md)、[ADR 0155](0155-split-aarch64-test-runner.md)、[ADR 0219](0219-frequency-of-the-wasm-job-and-its-uncached-runs.md)
- GitHub Docs, "Dependency caching reference"（「Restrictions for accessing a cache」「Usage limits and eviction policy」「Increasing cache size」）, https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching
- GitHub Docs, "Managing caches"（「Force deleting cache entries」）, https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manage-caches
- GitHub Docs, "REST API endpoints for GitHub Actions cache"（使用量の値は約 5 分ごとに更新される）, https://docs.github.com/en/rest/actions/cache
