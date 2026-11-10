# ADR 0287: `release.yml` が `ci.yml` に渡す `actions: write` を、`caches` のジョブだけが受け取るように検査する

ステータス: 採択

## 文脈

[2026-11-09 の監査](../audits/2026-11-09-security-audit.md) の CI-01（情報）は、`release.yml` の `ci` の呼び出しが、再利用のワークフロー `ci.yml` に `actions: write` を与えることを挙げた（[`release.yml#L27-L37`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/.github/workflows/release.yml#L27-L37)）。

この権限は、`ci.yml` の `caches` のジョブのためにある（[`ci.yml#L1197-L1204`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/.github/workflows/ci.yml#L1197-L1204)）。
呼ばれるワークフローのジョブは、呼ぶジョブが与えた権限までしか持てない。
呼ぶ側が与えない権限をジョブが求めると、そのジョブが走るかどうかによらず、実行の全体が startup_failure で終わる。
`scripts/ci/test.sh` は、この失敗の実例（実行 42480681991）を挙げ、`release.yml` の `ci` が `ci.yml` のジョブの求める権限をすべて与えることを検査している（[`test.sh#L2477-L2490`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/scripts/ci/test.sh#L2477-L2490)）。

`caches` の `if` は `github.ref == 'refs/heads/main'` を含む。
タグの push から呼ばれた `ci.yml` では `github.ref` がタグなので、`caches` は走らない。
今、`release.yml` 経由で `actions: write` のトークンを受け取るジョブはない。

一方、[ADR 0228](0228-keep-the-ci-caches-under-the-10-gb-limit.md) は「`ci.yml` で `actions: write` を持つジョブは `caches` だけ」と書き、`release.yml` の呼び出しが同じ権限を与えることを書いていない。
監査は、この記述のずれと、将来 `ci.yml` のほかのジョブが `actions: write` を求めればタグの push でもそのジョブに渡ることを指摘した。
狭める案として、`caches` を `workflow_run` の別のワークフローにする案を挙げ、それには ADR が要るとした。

[ADR 0228](0228-keep-the-ci-caches-under-the-10-gb-limit.md) の不変条件（`actions: write` を持つジョブは `caches` だけで、`if` が `main` への push に限る）は、`ci.yml` の中のジョブを縛る。
`release.yml` の呼び出しの権限は縛らない。
今のずれは、`ci.yml` のジョブが求める権限の集合と、`release.yml` が与える権限の集合とが、別々の場所で決まっていることから来る。

## 実装すること

1. `scripts/ci/test.sh` に、次の検査を足す。
   - `ci.yml` で `actions: write` を求めるジョブは `caches` だけである。
   - `caches` の `if` は、`github.event_name == 'push'` と `github.ref == 'refs/heads/main'` の両方を含む。
   - `release.yml` の `ci` の呼び出しが与える権限は、`ci.yml` のジョブが求める権限の和集合にちょうど等しい。求められていない権限を与えない。
   今の `perms_of` と `ci_jobs` を使う。
2. `release.yml` の `ci` の注釈に、`actions: write` を受け取るのは `caches` だけで、タグの push では `caches` が走らないことと、この ADR へのリンクを書く。
3. 仕様書の CI の権限を書いた段落に、`release.yml` の `ci` が `actions: write` を与えること、それを受け取るのは `caches` だけで、この検査がそれを保つことを書く。
4. [ADR 0228](0228-keep-the-ci-caches-under-the-10-gb-limit.md) のステータスの行に、`release.yml` の呼び出しの権限はこの ADR で扱うことを書き足す。
5. [docs/roadmap.md](../roadmap.md) の「2026-11-09 の監査の情報の所見」の項目から、CI-01 を外す。

## 実装しないこと

- `caches` を `workflow_run` の別のワークフローに移すこと（「メンテナーが決めること」の 1）。
- `release.yml` の `ci` から `actions: write` を外すこと。外すと、タグの push のたびに実行が startup_failure で終わる（実行 42480681991）。
- `ci.yml` のほかのジョブの権限を変えること。

## 不変条件

`asked(j)` は `ci.yml` のジョブ j が `permissions` に書く権限の集合、`granted` は `release.yml` の `ci` の呼び出しが与える権限の集合とする。
権限は `スコープ: 段階` の組で、段階は `read` と `write` とする。

- **P1 書き込みは `caches` だけ**：`actions: write` を含む `asked(j)` を持つジョブ j は、`caches` だけである。
- **P2 `caches` は `main` への push に限る**：`caches` の `if` は、`github.event_name == 'push'` と `github.ref == 'refs/heads/main'` を含む。
- **P3 与えすぎない**：`granted` のどの組 `s: l` にも、`asked(j)` に `s: l` を持つジョブ j がある。
- **P4 与え足りない**：どのジョブ j のどの組 `s: l` にも、`granted` に `s: l` か `s: write` がある（今の検査）。

境界の入力：

| 入力 | 期待 |
| --- | --- |
| 今の二つのワークフロー | P1 から P4 が成り立つ |
| `ci.yml` のほかのジョブに `actions: write` を足したもの | P1 が落ちる |
| `caches` の `if` から `github.ref == 'refs/heads/main'` を除いたもの | P2 が落ちる |
| `release.yml` の `ci` に `contents: write` を足したもの | P3 が落ちる |
| `release.yml` の `ci` から `actions: write` を除いたもの | P4 が落ちる |
| `ci.yml` のジョブの `permissions` がない（ワークフローの既定の `contents: read`） | そのジョブは何も求めない |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
テストの名前（`test.sh` の `expect` の文）には、P1 から P4 の番号を入れる。

- P1 から P4 を、`scripts/ci/testdata/` に置く小さな二つのワークフローの組（境界の入力の表の各行）で確かめる。
- 今の二つのワークフローに対しても走らせる。今のワークフローで P1 から P4 は成り立つ見込みである。失敗を確かめられるのは、表の行の組で各述語が落ちることである。

## トレードオフ

`release.yml` のトークンの範囲は、今と変わらない。
将来 `ci.yml` のジョブが `actions: write` を求めたら、P1 で落ちる。
そのジョブに権限が要るなら、この ADR を改める ADR が要る。

`workflow_run` に移さないので、タグの push の実行の中に `actions: write` のトークンを受け取りうるジョブが一つ残る。
受け取る条件は、`caches` の `if` を誰かが書き換えたときで、P2 がそれを止める。

## メンテナーが決めること

1. **権限を狭める方法**：推奨は、今の権限のまま、P1 から P4 を検査で保つことである。`caches` の `if` が、タグの push の実行でトークンを使わせない。
   - 退けた案の一つは、`caches` を `workflow_run` で起動する別のワークフローにすることである。`ci.yml` から `actions: write` が消え、`release.yml` は `actions: read` だけを与えればよくなる。ただ、`workflow_run` は既定のブランチの文脈で書き込みの権限を持って走るので、監査が「ない」と確かめた種類のトリガーを一つ増やす。消す時点も `ci.yml` の実行の終わりの後にずれ、保存と削除の順を `needs` で保てなくなる。
   - もう一つは、記述のずれを記録するだけで、検査を足さないことである。将来ジョブが `actions: write` を求めたとき、レビューで見落とせば通る。
2. **P3 を足すか**：推奨は足すことである。`release.yml` が `ci.yml` の求めない権限を与えたときに気付ける。
   - 退けた案は、今の P4 だけを残すことである。与えすぎは startup_failure を起こさないので、誰も気付かない。

## 決めたことの記録

2026-11-10 に、tett23 が「メンテナーが決めること」のすべてを推奨のとおりに決めた。

1. 権限は今のまま狭めず、P1 から P4 を検査で保つ。`caches` の `if` が、タグの push の実行でトークンを使わせない。
2. P3 を足し、`release.yml` が `ci.yml` の求めない権限を与えたときに気付けるようにする。

採択にあたり、ソースコードへのリンクを `main` の `9acc137a`（[ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md) の実装のマージ）に合わせた。

## 参考文献

- [2026-11-09 の監査](../audits/2026-11-09-security-audit.md)（CI-01）
- [ADR 0035](0035-security-hardening.md)、[ADR 0228](0228-keep-the-ci-caches-under-the-10-gb-limit.md)、[ADR 0245](0245-keep-the-warnings-of-ci-at-zero.md)
- [`.github/workflows/release.yml`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/.github/workflows/release.yml#L27-L37)、[`.github/workflows/ci.yml` の `caches`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/.github/workflows/ci.yml#L1190-L1243)、[`scripts/ci/test.sh`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/scripts/ci/test.sh#L2477-L2490)
- GitHub Docs「Reusing workflows」の、呼ばれるワークフローの `GITHUB_TOKEN` の権限は呼ぶ側を超えないという記述
