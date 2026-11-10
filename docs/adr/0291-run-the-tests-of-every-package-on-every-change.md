# ADR 0291: 変更のないパッケージのテストも、すべての変更で走らせる

ステータス: 採択

## 文脈

[ADR 0244](0244-take-verapdf-off-the-critical-path-of-ci.md) の「メンテナーが決めること」の 3 は、CI の所要時間を縮めるため、変更のないパッケージのテストを省くことを、別の ADR で扱うとした。
[ADR 0259](0259-record-what-the-audit-of-the-ci-release-and-tooling-adrs-found-on-2026-11-09.md) の決定の 6 が、それを別の ADR として立てると決めた。
この ADR が、その別の ADR である。

省けば速くなる、とは思える。
ただ、省いて縮むのはテストのランナーの時間で、CI の実行の時間はいちばん遅いランナーで決まる。

### `build` のジョブの形

`ci.yml` の `build` は、x86-64 の四つのランナー（`tests-driver`、`tests-rest`、`outputs`、`env`）と、aarch64 の三つのランナー（`tests-driver`、`tests-rest`、`outputs`）で、同じコミットを組む（[`ci.yml#L120-L185`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/.github/workflows/ci.yml#L120-L185)）。
どのランナーも `cabal build all` を走らせ、その後で、テストのランナーはテストのスイートを、`outputs` は見た目の回帰テストの PDF、マニュアル、epubcheck などを、`env` は環境の検査を走らせる。
`determinism` は `build` のすべてを待つ（[`ci.yml#L827-L829`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/.github/workflows/ci.yml#L827-L829)）。
テストを省くことは、`cabal build all` も、`outputs` と `env` の仕事も縮めない。

### 測った時間

2026-11-10 に、`gh` で `ci.yml` の成功した実行を読んだ。
`main` への push の 15 回（`7e8fe7d3` から `8828fc5d`）と、プルリクエストの 14 回である。
秒は、実行の最初のジョブの開始から各ジョブの終わりまでで、`scripts/ci/timings.sh` と同じく `startedAt` と `completedAt` から求めた。

| 実行 | `build` のランナーのうち最後に終わったもの | 二番めとの差 |
| --- | --- | --- |
| `main` の push 15 回 | `outputs` 9 回、`env` 5 回、`tests-rest`（x86-64）1 回 | `tests-rest` が最後の 1 回で 57 秒 |
| プルリクエスト 14 回 | `outputs` 7 回、`tests-rest`（x86-64）7 回 | `tests-rest` が最後の 7 回で 2 秒から 73 秒、中央値 21 秒 |

プルリクエストの `env` は `--quick` で小さな入力だけを調べるので、`main` より早く終わり、`tests-rest` が最後になる実行が増える。
テストのスイートの手順の中央値は、`main` の push で x86-64 の `tests-rest` が 109 秒、`tests-driver` が 96 秒である。
`tests-rest` の中で長いスイートは、`golem-emet-test`（82 秒から 151 秒）、`golem-pdf-test`（56 秒から 114 秒）、`golem-parser-test`（52 秒から 74 秒）、`golem-layout-test`（33 秒から 81 秒）で、`main` への push の 9 回のログの `suite-timeout.sh` の行から読んだ。

省いて縮むのは、`tests-rest` がいちばん遅いときの、二番めのランナーとの差までである。
プルリクエストでは半分の実行で中央値 21 秒、`main` ではほぼ 0 秒になる。
変更が golem-emet や golem-pdf に届くと、長いスイートは省けないので、差も縮まない。

### 省くときに決めなければならないこと

省くなら、パッケージ P のテストを走らせる条件を決める必要がある。
`build-depends` の閉包だけでは足りない。
テストは、ほかのパッケージのファイルを相対のパスで読む。
たとえば、`../golem-font/test/fonts/SourceSansPro-Regular.otf` を 22 か所、`../golem-driver/test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf`、`../golem-plugin/test/plugins/*.wat`、`../../VERSION`、`../../plugins/wasm/glossary.wasm`、`../../manual`、`../../scripts/determinism/pdf-style.toml` を読む（2026-11-10 に `git grep '"\.\./'` で `modules/*/test/` を探した）。
これらは `build-depends` に現れないので、閉包の規則は、テストが読むファイルの一覧を別に持ち、その一覧が正しいことを検査する仕組みを要る。
一覧が漏れると、変更が壊したテストを省いたまま、CI が通る。

## 実装すること

1. 変更のないパッケージのテストを省かない。今のとおり、`build` のテストのランナーは、`scripts/ci/test-suites.sh` が挙げるすべてのスイートを走らせる。
2. [docs/roadmap.md](../roadmap.md) の「変更のないパッケージのテストを省く ADR」の項目を外す。
3. 仕様書の CI の節に、文書だけの変更（`needs-build.sh`）を除き、すべての変更ですべてのテストのスイートを走らせることと、その理由（文脈の測定）を、この ADR へのリンクで書く。
4. 文脈の表を `docs/ci-timings/` の記録にする。

## 実装しないこと

- パッケージの依存の閉包でテストを選ぶ仕組み。
- テストのスイートのランナーへの配り直し。[ADR 0244](0244-take-verapdf-off-the-critical-path-of-ci.md) の「メンテナーが決めること」の 2 のとおり、スイートごとの時間を集めてから別の ADR で決める。この ADR の測定はその材料になる。

## 不変条件

なし。
この ADR は、今の振る舞いを変えないことを決める。
すべてのスイートが走ることは、[ADR 0140](0140-ci-split-test-runners-and-visual-pdfs-first.md) の「どのスイートも `driver` か `rest` のどちらか一方にある」という `test-suites.sh` の検査が今も保つ。

## テスト設計

なし。
振る舞いを変えない。
文脈の測定は、`gh run view --json jobs` の出力を `scripts/ci/timings.sh` にかけ、実行ごとの最後のランナーを読んで得た。
記録には、読んだ実行の番号の一覧を添える。

## トレードオフ

プルリクエストのおよそ半分で、数十秒を縮める機会を捨てる。
その代わり、テストが読むファイルの一覧を保つ仕組みと、その一覧の漏れによってテストが省かれる危険を持たない。

`outputs` や `env` が速くなれば、テストのランナーが最後になる実行が増え、省く効果は大きくなる。
そのときは、測り直して ADR を書き直す。

## メンテナーが決めること

1. **省くか**：推奨は省かないことである。縮むのはプルリクエストの半分で中央値 21 秒、`main` ではほぼ 0 秒で、テストが読むファイルの一覧という、漏れたら気付かれない仕組みを足す代価に見合わない。正確さを時間より優先する方針にも合う。
   - 退けた案の一つは、`dist-newstyle/cache/plan.json` の依存の閉包と、テストが読むファイルの一覧（スイートごとに `test-inputs.txt` などで持つ）の和で、走らせるスイートを選ぶことである。一覧が正しいことは、テストの中で開いたファイルを記録して比べなければ確かめられず、その記録の仕組みのほうが省く仕組みより大きい。
   - もう一つは、`modules/` の外（`scripts/`、`cabal.project`、`manual/` など）が変わったらすべてを走らせ、`modules/` の中だけの変更で閉包を使うことである。一覧の漏れは減るが、上の相対のパスの読み込みはどれも `modules/` の中のパッケージの間なので、その漏れは残る。
   - もう一つは、プルリクエストでだけ省き、`main` への push ではすべてを走らせることである。省いたテストの失敗はマージの後に見つかり、`main` が壊れた状態でほかのプルリクエストが基づく。
2. **測り直す条件**：推奨は、`outputs` と `env` の手順を縮める ADR が入ったときに、この ADR の表を測り直すことである。
   - 退けた案は、期間を決めて測り直すことである。ランナーの役割が変わらなければ、表も変わらない。

## 決めたことの記録

2026-11-10 に、tett23 が「メンテナーが決めること」のすべてを推奨のとおりに決めた。

1. 変わったファイルでテストを省くことはせず、すべてのパッケージのテストを毎回走らせる。
2. `outputs` と `env` の手順を縮める ADR が入ったときに、この ADR の表を測り直す。

採択にあたり、ソースコードへのリンクを `main` の `9acc137a`（[ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md) の実装のマージ）に合わせた。

## 参考文献

- [ADR 0009](0009-ci-speed.md)、[ADR 0140](0140-ci-split-test-runners-and-visual-pdfs-first.md)、[ADR 0155](0155-split-aarch64-test-runner.md)、[ADR 0244](0244-take-verapdf-off-the-critical-path-of-ci.md)、[ADR 0259](0259-record-what-the-audit-of-the-ci-release-and-tooling-adrs-found-on-2026-11-09.md)
- [docs/ci-timings/2026-11-09-ci-times-after-verapdf-off-the-critical-path.md](../ci-timings/2026-11-09-ci-times-after-verapdf-off-the-critical-path.md)
- [`.github/workflows/ci.yml`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/.github/workflows/ci.yml#L120-L185)、[`scripts/ci/test-suites.sh`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/scripts/ci/test-suites.sh)、[`scripts/ci/suite-timeout.sh`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/scripts/ci/suite-timeout.sh)、[`scripts/ci/timings.sh`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/scripts/ci/timings.sh)
- CI の実行：`main` の push 42702830010、42711171269、42712675271、42714202388、42715298341、42717986659、42723132548、42729705298、42732052330、42735279926、42738715688、42740480282、42743811596、42747377433、42749412945 と、プルリクエストの 42728552528、42731014763、42731822427、42734534064、42738115261、42739674843、42743148058、42743256649、42744930735、42745588562、42745638372、42748404900、42749566843、42750973817（2026-11-10 に `gh run list -e pull_request -s success -L 15` で読んだ 15 回から、文書だけで `build` のない 42739089513 を除いた）
