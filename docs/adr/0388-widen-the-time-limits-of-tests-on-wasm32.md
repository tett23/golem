# ADR 0388: wasm32 で走らせるテストの時間の上限を広げる

Status: superseded [{"by":["docs/adr/0415-fix-the-medium-findings-of-the-conformance-audit-of-2026-11-18.md"],"part":"I2 と I3 の wasm32 のテストを毎晩の wasm-tests.yml で走らせること","kind":"supplement"}]

## 文脈

毎晩の `wasm-tests.yml`（[ADR 0293](0293-run-the-test-suites-of-the-packages-of-golem-wasm-on-wasm32-every-night.md)）は、golem.wasm のパッケージのテストを wasm32 で走らせる。
wasm32 で落ちるテストは、既知の失敗の一覧 `scripts/wasm/test-failures.tsv` に載せる。
一覧に載ったテストが通ると、そのことでもジョブは落ちる（[ADR 0293](0293-run-the-test-suites-of-the-packages-of-golem-wasm-on-wasm32-every-night.md) A3）。

golem-svg のテスト「a path of 1,000,001 segments drawn by the drawing itself is not counted」は、この一覧に載っている（[test-failures.tsv の 298 行](https://github.com/tett23/golem/blob/2a37ddcbf078ff7aea28f137c430612573fd3443/scripts/wasm/test-failures.tsv#L298)）。
理由は、wasm32 で CPU 時間の上限 60 秒を超えることである。
上限は [ADR 0091](0091-cpu-time-limits-in-pdf-and-svg-tests.md) の `hangLimits` で、CPU 時間 60 秒と実時間 300 秒である（[TimeLimit.hs の 43 行](https://github.com/tett23/golem/blob/2a37ddcbf078ff7aea28f137c430612573fd3443/modules/golem-test-support/src/Golem/TestSupport/TimeLimit.hs#L43)）。

しかし、このテストは wasm32 で上限のすぐ近くの時間を使い、通るときと落ちるときがある。
一覧に載ったまま通った夜は、[ADR 0293](0293-run-the-test-suites-of-the-packages-of-golem-wasm-on-wasm32-every-night.md) A3 によってジョブが落ちる。
一覧から外すと、落ちた夜に [ADR 0293](0293-run-the-test-suites-of-the-packages-of-golem-wasm-on-wasm32-every-night.md) A2 によってジョブが落ちる。
どちらにしても、テストの結果がランナーの速さで決まり、毎晩のジョブが壊れやすくなる。

## 調査した事項

- wasm32 での結果（2026-11-17 の調べ。`gh run view` と成果物で確かめた）：
  - 8 回の実行のうち 7 回は 60.03〜60.11 秒で、`used more than 60 seconds of CPU time` で落ちた。42893833883、42929836841、43136115299、43339054577、43534402136、43652964510、43775222566 の 7 回である。
  - 実行 44004335314 では 58.58 秒で通った。
  - 一覧を直した後に走らせた実行 44041815945 では、60.08 秒で落ちた。
- 同じテストのネイティブでの時間は、実行 44004335314 の成果物 `wasm-tests-native/golem-svg-test.log` で 2.48 秒である。同じ実行の wasm32 の 58.58 秒は、その 23.6 倍にあたる。
- ネイティブでの 2.48 秒は、[ADR 0091](0091-cpu-time-limits-in-pdf-and-svg-tests.md) の「時間の上限を付けるテストは、単独の CPU 時間で 10 秒以内」に収まっている。テストそのものは [ADR 0091](0091-cpu-time-limits-in-pdf-and-svg-tests.md) に反していない。
- 一覧の理由のうち、時間の上限によるものはこの 1 行だけである（`awk -F'\t' 'NR>1{print $3}' scripts/wasm/test-failures.tsv | sort | uniq -c` の結果）。
- `wasm-tests.yml` は、スイートを一つずつ `timeout -k 10 1800` の下で走らせる（[wasm-tests.yml の 241 行](https://github.com/tett23/golem/blob/2a37ddcbf078ff7aea28f137c430612573fd3443/.github/workflows/wasm-tests.yml#L241)）。スイートの時間切れは 1800 秒である。
- wasm32 とネイティブの時間の比は、テストによって違う。同じ実行で、「a marker of 1,000 segments at the 1,000 vertices of a path is 1,000,000 segments, drawn」はネイティブ 0.09 秒、wasm32 4.38 秒で、比は約 49 倍である。この 2 件のほかの比は測っていない。

## 実装すること

1. golem-test-support の `hangLimits` を、wasm32 のときだけ広げる。
   - ネイティブでは今のまま、CPU 時間 60 秒、実時間 300 秒とする。
   - wasm32（`wasm32_HOST_ARCH`）では、CPU 時間 600 秒、実時間 1200 秒とする。CPU 時間は 10 倍、実時間は 4 倍である。実時間を 1800 秒より短くするのは、スイートごとの時間切れ（上の「調査した事項」）より先にテストごとの上限が働き、止まったテストの名前が出るようにするためである。
   - 分けるのはコンパイルのときの CPP で、実行のときの環境の変数は使わない。[ADR 0293](0293-run-the-test-suites-of-the-packages-of-golem-wasm-on-wasm32-every-night.md) は、run-tests.mjs が WASI に渡す環境の変数を二つに限っているからである。
   - `hangLimits` の注釈に、二つの値と、その理由としてこの ADR を書く。
2. `scripts/wasm/test-failures.tsv` から、上のテストの行を外す。
3. 仕様書の `Golem.TestSupport.TimeLimit` の項目（docs/specifications.md の 501 行）に、ネイティブと wasm32 の値と、この ADR へのリンクを足す。
4. [ADR 0091](0091-cpu-time-limits-in-pdf-and-svg-tests.md) のステータスの行を `superseded [{"part":"時間の上限の補助（wasm32 の値）","by":["docs/adr/0388-widen-the-time-limits-of-tests-on-wasm32.md"],"kind":"supplement"}]` にする。

## 実装しないこと

- ネイティブの上限は変えない。[ADR 0091](0091-cpu-time-limits-in-pdf-and-svg-tests.md) の値は、ネイティブで止まらないテストを見つけるためのもので、今も合っている。
- テストの入力（1,000,001 の線分）を小さくしない。このテストは、線分の数の上限 1,000,000 を一つ超える入力で、図そのものの線分を数えないことを確かめる。入力を小さくすると、境界を確かめられなくなる。
- 「通っても落ちてもよい」という種類を、既知の失敗の一覧に足さない。結果がランナーで揺れるテストを隠すことになるからである。
- 上限を、ネイティブの時間の何倍という形で、テストごとに決めない。比はテストによって違い（23.6 倍と約 49 倍）、測っていないテストの比はわからない。

## 不変条件

- I1: ネイティブ（wasm32 でない）では、`hangLimits` は CPU 時間 60 秒、実時間 300 秒である。
- I2: wasm32 では、`hangLimits` は CPU 時間 600 秒、実時間 1200 秒である。
- I3: どちらでも、`hangLimits` の実時間は CPU 時間より長い。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| ネイティブでビルドしたテスト | `TimeLimits {cpuSeconds = 60, wallSeconds = 300}` | I1, I3 |
| wasm32 でビルドしたテスト | `TimeLimits {cpuSeconds = 600, wallSeconds = 1200}` | I2, I3 |

## 受けいれ条件

- A1: `wasm-tests.yml` を、実装のブランチで `workflow_dispatch` によって 3 回走らせ、3 回とも四つのジョブが通る。
- A2: 実装の後に、上のテストが wasm32 で使う時間を、3 回の実行の成果物から記録する。
- A3: golem-pdf-test と golem-svg-test のネイティブのテストの結果と時間は、実装の前と変わらない。

## テスト設計

- golem-test-support のテストに、I1 と I3 を確かめるテストを足す。名前は `root ADR 0388 I1, I3: …` とする。このテストはネイティブの CI で走る。
- I2 と I3 の wasm32 の値を確かめるテストも、同じテストスイートに CPP で足す。名前は `root ADR 0388 I2, I3: …` とする。このテストは、毎晩の `wasm-tests.yml` で走る。
- A1 と A2 は手で確かめる。dispatch の実行の番号と、上のテストの wasm32 の時間を、プルリクエストの説明に書く。
- A3 は、プルリクエストの CI のネイティブのテストの結果で確かめる。

## トレードオフ

- wasm32 では、止まらないテストを見つけるまでの時間が、CPU 時間で 10 倍、実時間で 4 倍になる。CPU 時間を使い続けるテストは 600 秒で、待ち続けるテストは 1200 秒で止まる。どちらもスイートの時間切れの 1800 秒より短い。ただし、同じスイートで先に走ったテストの時間が 600 秒を超えていると、待ち続けるテストはスイートの時間切れで止まり、名前が出ない。
- 10 倍という値は、測った比（23.6 倍と約 49 倍）より小さい。比が 49 倍のテストでも、ネイティブで単独 10 秒以内（[ADR 0091](0091-cpu-time-limits-in-pdf-and-svg-tests.md)）であれば、wasm32 で 490 秒になり、600 秒に収まる。比が 60 倍を超えるテストがあれば、ネイティブで 10 秒近いテストは収まらない。そのときは、そのテストを一覧に載せるか、この値を変える ADR を書く。
- wasm32 だけ値を変えるので、ネイティブで止まらないテストを見つける力は変わらない。

## 決めたことの記録

- 2026-11-17 に tett23 が `0388の予算をbugetsに追加。未実装でマージ` と書き、この ADR を採択した。実装は後で行う。
- 同じ日に、`docs/budgets.md` の「テストと CI の中で強制する上限」の表に、wasm32 の上限の行を足した。

## 参考文献

- [ADR 0091](0091-cpu-time-limits-in-pdf-and-svg-tests.md)
- [ADR 0293](0293-run-the-test-suites-of-the-packages-of-golem-wasm-on-wasm32-every-night.md)
