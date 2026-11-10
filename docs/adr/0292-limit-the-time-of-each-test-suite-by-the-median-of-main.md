# ADR 0292: テストのスイートごとの時間に、`main` の中央値から決めた上限を置く

ステータス: 採択

## 文脈

[ADR 0073](0073-time-bounds-in-tests.md) は、テストの時間の上限を「止まらないことの検出」に限り、その時間切れを 30 秒にそろえた。
性能の後退を見つけることは、テストの時間切れの役目から外した。
スイート全体の所要時間の上限は、その「実装しないこと」で別に扱うとし、値は直近の実行の中央値から決める予定とした。

例外が一つ残っている。
golem-syntax のテストの「10 万行の位置の往復」は、2 秒の時間切れを持つ（[`Main.hs#L101-L106`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/modules/golem-syntax/test/Main.hs#L101-L106)）。
[golem-lsp ADR 0002](../golem-lsp/adr/0002-utf8-position-encoding.md) が、行の数に比例する探索に戻ったことに気付けるように決めた値である。
テストは約 0.06 秒で終わるが、行を先頭から探す実装に戻れば、10 万回の往復は 10^10 の桁の手数になる。
時間切れを 30 秒にそろえると、速いマシンでは、この後退が 30 秒に収まって通る可能性がある。
[docs/roadmap.md](../roadmap.md) は、スイートの時間の上限ができたら、この 2 秒も 30 秒にそろえ、性能の後退はその上限で見つけるとしている。

### 今の時間切れ

CI のテストのスイートは、`scripts/ci/suite-timeout.sh` を test wrapper にして走る（[`suite-timeout.sh`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/scripts/ci/suite-timeout.sh)）。
600 秒で終わらないスイートを止め、終わったスイートは「`<スイート>: finished in <秒> seconds`」を標準エラーに書く（[ADR 0244](0244-take-verapdf-off-the-critical-path-of-ci.md) の 2）。
600 秒は止まらないことの検出で、どのスイートの所要時間よりも一桁以上大きい。

### スイートの時間の揺れ

2026-11-10 に、`main` への push の 9 回（`79c91475` から `8828fc5d`）の `build` のテストのランナーのログから、この行を読んだ。

| スイート | x86-64 の秒 | aarch64 の秒 |
| --- | --- | --- |
| `golem-emet-test` | 82 から 151 | 87 から 98 |
| `golem-pdf-test` | 56 から 114 | 59 から 67 |
| `golem-driver-test` | 72 から 104 | 81 から 88 |
| `golem-parser-test` | 52 から 74 | 40 から 50 |
| `golem-layout-test` | 33 から 81 | 25 から 45 |
| `golem-svg-test` | 12 から 23 | 12 から 13 |
| `golem-test-support-test` | 14 から 15 | 13 から 16 |
| `golem-syntax-test` | 1 から 2 | 1 |

x86-64 のランナーは、同じコミットの同じスイートでも最大で約 1.8 倍揺れる。
aarch64 は 1.1 倍ほどに収まる。
`golem-layout-test` の幅は揺れだけでなく、この期間に列挙のテストが足されたことも含む（[ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md)）。
上限は、この揺れで落ちない大きさでなければならない。
落ちたり通ったりする検査は、原因を調べることになり（flaky なテストは調べて直す方針）、揺れのたびに調べる費用は上限の価値を上回る。

## 実装すること

### 1. 上限の表

`scripts/ci/suite-limits.tsv` に、アーキテクチャ（`uname -m` の値、`x86_64` と `aarch64`）、スイートの名前、上限の秒を、タブで区切って一行ずつ書く。
上限は、直近の `main` への push の 20 回の、そのアーキテクチャとスイートの秒の中央値 m から、`max(10, ceil(2 × m))` とする。

### 2. 上限を超えたスイートを失敗にする

`suite-timeout.sh` は、スイートが終わった後、表の上限と秒を比べる。

- 秒が上限以下なら、今のとおり、スイートの終了コードで終わる。
- 秒が上限を超えたら、`<スイート>: finished in <秒> seconds, over its limit of <上限> seconds (scripts/ci/suite-limits.tsv)` を標準エラーに書き、スイートが通っていても終了コード 1 で終わる。スイートが落ちていれば、スイートの終了コードで終わる。
- 表にそのアーキテクチャとスイートの行がなければ、スイートを走らせる前に `<スイート>: no limit in scripts/ci/suite-limits.tsv` を書いて終了コード 1 で終わる。
- 600 秒の時間切れ（`SUITE_TIMEOUT`）は、今のとおり残す。止まらないスイートを止める役目は変わらない。
- 表を読む場所は、環境の変数 `SUITE_LIMITS`（既定はリポジトリの `scripts/ci/suite-limits.tsv`）で変えられる。`SUITE_LIMITS` が空なら、上限を当てない（手元で test wrapper を使うときのため）。

### 3. 表を作る

`scripts/ci/suite-limits.sh` は、`suite-timeout.sh` の「finished in」の行に、アーキテクチャを前に付けた行（`<arch>\t<行>`）を標準入力から読み、1 の式で表を書く。
CI のログからこの入力を集める手順は、`scripts/ci/suite-limits.sh --fetch N` とし、`gh run list` で `main` への push の成功した直近 N 回を選び、`build` のテストのランナーのログを、[ADR 0245](0245-keep-the-warnings-of-ci-at-zero.md) の 6 と同じく API から `curl` で取る。
Python は使わず、`jq` と `awk` で書く。

### 4. 表を改める規則

- スイートが上限を超えたら、まず後退かどうかを調べる。後退なら直す。
- テストを足したことによる正当な増加なら、そのプルリクエストで `suite-limits.sh --fetch 20` で表を作り直し、増えたスイートの行は、プルリクエストの CI の秒を中央値に加えた値で上限を求める。プルリクエストの説明に、前と後の上限を書く。
- 新しいスイートを足すプルリクエストは、そのスイートの行を、プルリクエストの CI の秒から 1 の式で求めて足す。

### 5. golem-syntax の 2 秒

`modules/golem-syntax/test/Main.hs` の `mkTimeout 2000000` を、[ADR 0073](0073-time-bounds-in-tests.md) の 30 秒にそろえる。
注釈に、行の数に比例する探索への後退は、このスイートの上限（1 の式で 10 秒）で見つけることを書く。
[golem-lsp ADR 0002](../golem-lsp/adr/0002-utf8-position-encoding.md) のステータスの行に、テストの時間切れはこの ADR で改めたことを書き足す。

### 6. 文書

- 仕様書の CI の節に、スイートの上限の表、式、超えたときの扱い、表を改める規則を書く。
- `CONTRIBUTING.md` のテストの節に、4 の手順を書く。
- [ADR 0073](0073-time-bounds-in-tests.md) のステータスの行に、スイート全体の上限はこの ADR で決めたことを書き足す。
- [docs/roadmap.md](../roadmap.md) の「テストのスイートの時間の上限」の項目を外す。

## 実装しないこと

- テストごとの時間の上限。テストごとの時間切れは、止まらないことの検出のままとする（[ADR 0073](0073-time-bounds-in-tests.md)、[ADR 0091](0091-cpu-time-limits-in-pdf-and-svg-tests.md)、[ADR 0237](0237-raise-the-hang-time-outs-of-golem-driver-test-to-300-seconds.md)）。
- 列挙のテストの予算。範囲ごとの予算は [ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md) が決め、この ADR の上限は列挙のテストを含むスイートの全体に当てる。
- CPU 時間で量ること（「メンテナーが決めること」の 2）。
- `enum.yml` と `race.yml` など、`build` のジョブの外のスイートの実行。
- 手元の `cabal test` に上限を当てること。

## 不変条件

アーキテクチャ a のスイート s の上限を L(a, s)、走った秒を t、スイートの終了コードを c とする。

- **L1 上限の内側は今のとおり**：t ≤ L(a, s) なら、wrapper の終了コードは c である。
- **L2 上限を超えたら落ちる**：t > L(a, s) なら、wrapper の終了コードは 0 でなく、標準エラーに上限の行がある。c が 0 でなければ、終了コードは c である。
- **L3 表にないスイートは走らせない**：(a, s) の行がなければ、スイートを起動せずに終了コード 1 で終わる。
- **L4 表はすべてのスイートを持つ**：`test-suites.sh all` の展開するすべてのスイートと、`x86_64`、`aarch64` のそれぞれについて、表にちょうど一つの行がある。表にあってスイートのない行もない。
- **L5 式**：`suite-limits.sh` が書く上限は、入力の中央値 m に対して `max(10, ceil(2 × m))` である。偶数個の中央値は、中央の二つの平均とする（`timings.sh` と同じ）。
- **L6 止まらないものは止める**：`SUITE_TIMEOUT` の時間切れは、上限の表によらず、今のとおり働く。

境界の入力：

| 入力 | 期待 |
| --- | --- |
| t = L | 終了コード c（L1） |
| t = L + 1 で c = 0 | 終了コード 1 と上限の行（L2） |
| t = L + 1 で c = 1 | 終了コード 1 と上限の行（L2） |
| 表に行がない | 起動しない（L3） |
| 表に同じ (a, s) が二行 | L4 で落ちる |
| m = 0、m = 4.9、m = 5、m = 5.1 | 10、10、10、11（L5） |
| 入力が一つ、二つ | その値、二つの平均（L5） |
| `SUITE_LIMITS` が空 | 上限を当てない |
| `SUITE_TIMEOUT` を超える | 今のとおり 124 か 137 で止める（L6） |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
テストの名前（`test.sh` の `expect` の文）には、L1 から L6 の番号を入れる。

- **L1、L2、L3、L6**：`scripts/ci/test.sh` に、偽のスイート（指定の秒だけ眠り、指定の終了コードで終わるシェルのスクリプト）と、`scripts/ci/testdata/` の小さな表で、境界の入力の表の行を確かめるテストを足す。秒の境目は、偽の `date`（`PATH` の先に置く）で決めた時刻で作り、眠らない。今の `suite-timeout.sh` では、L2 と L3 が落ちる。
- **L4**：`scripts/ci/test.sh` で、リポジトリの表と `test-suites.sh all` の展開を比べる。`changes` のジョブでも走らせ、スイートを足して表を足し忘れたプルリクエストを、テストのランナーより先に落とす。
- **L5**：`suite-limits.sh` に、境界の入力の表の中央値になる入力を与えて確かめる。
- **5 の後退の検出**：自動のテストにしない。実装のプルリクエストで、`Golem.Syntax` の行の探索を一時的に先頭からの探索に替えたコミットを積み、x86-64 と aarch64 の両方で `golem-syntax-test` が上限で落ちることを確かめて、ログをプルリクエストの説明に貼る。そのコミットは外してからマージする。落ちなければ、golem-syntax の上限の行だけ式によらず小さくするかを、プルリクエストで判断を仰ぐ。
- **揺れ**：実装の後、`main` への push の 10 回で、上限で落ちたスイートがないことを確かめる。

## トレードオフ

上限は中央値の 2 倍なので、スイートの時間が 2 倍に届かない後退は見つからない。
目的は、行の数に比例する探索のような、桁の変わる後退を見つけることである。
小さな後退の積み重ねは、4 の規則で表を作り直すたびに上限に取り込まれる。

テストを足すプルリクエストが表を改めることになり、プルリクエストの手順が一つ増える。

## メンテナーが決めること

1. **上限の式**：推奨は `max(10, ceil(2 × m))` で、m は直近 20 回の中央値である。x86-64 の揺れ（最大で約 1.8 倍）を、中央値から見て収める。
   - 退けた案の一つは、`ceil(1.5 × m)` にすることである。x86-64 の `golem-emet-test` の最大（151 秒）は中央値の約 1.14 倍で収まるが、`golem-pdf-test` の最小と最大の比は 2 倍あり、中央値が低い側に寄った期間に作った表では落ちうる。
   - もう一つは、直近の最大の 1.2 倍にすることである。最大は外れ値で決まり、上限が揺れに引きずられて大きくなる。
   - もう一つは、下限を置かないことである。1 秒のスイートの上限が 2 秒になり、ランナーの起動の揺れで落ちる。
2. **何で量るか**：推奨は、今の `suite-timeout.sh` と同じ壁時計の秒である。ランナーの時間を縮める目的と同じ量を見る。
   - 退けた案は、POSIX の `times` で子の CPU 時間を量ることである。混んだランナーの揺れは減るが、スイートは `-N` で並列に走るので、CPU 時間は GC の並列の度合いで揺れる。
3. **アーキテクチャごとに表を持つか**：推奨は持つことである。x86-64 と aarch64 で同じスイートの時間が違い、揺れの大きさも違う。
   - 退けた案は、二つの大きいほうで一つの表にすることである。aarch64 の後退が、x86-64 の大きな上限に隠れる。
4. **上限を超えたときに落とすか**：推奨は落とすことである。警告にすると、[ADR 0245](0245-keep-the-warnings-of-ci-at-zero.md) の warning を 0 に保つ方針と同じ扱いになり、結局は落とすのと変わらない。
   - 退けた案は、ジョブの要約に書くだけにすることである。[ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md) の列挙の予算はそうしているが、そこでは列挙を足すプルリクエストが表を貼る手順で補っている。スイートの後退は、どのプルリクエストからも起こりうる。

## 決めたことの記録

2026-11-10 に、tett23 が「メンテナーが決めること」のすべてを推奨のとおりに決めた。

1. 上限の式は `max(10, ceil(2 × m))` とし、m は直近 20 回の `main` への push の中央値とする。
2. 時間は、今の `suite-timeout.sh` と同じ壁時計の秒で量る。
3. 表はアーキテクチャごとに持つ。
4. 上限を超えたスイートは落とす。

採択にあたり、ソースコードへのリンクを `main` の `9acc137a`（[ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md) の実装のマージ）に合わせた。

## 参考文献

- [ADR 0073](0073-time-bounds-in-tests.md)、[ADR 0091](0091-cpu-time-limits-in-pdf-and-svg-tests.md)、[ADR 0140](0140-ci-split-test-runners-and-visual-pdfs-first.md)、[ADR 0237](0237-raise-the-hang-time-outs-of-golem-driver-test-to-300-seconds.md)、[ADR 0244](0244-take-verapdf-off-the-critical-path-of-ci.md)、[ADR 0245](0245-keep-the-warnings-of-ci-at-zero.md)、[ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md)
- [golem-lsp ADR 0002](../golem-lsp/adr/0002-utf8-position-encoding.md)
- [`scripts/ci/suite-timeout.sh`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/scripts/ci/suite-timeout.sh)、[`scripts/ci/test-suites.sh`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/scripts/ci/test-suites.sh)、[`scripts/ci/timings.sh`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/scripts/ci/timings.sh)、[`modules/golem-syntax/test/Main.hs`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/modules/golem-syntax/test/Main.hs#L101-L123)
- CI の実行：`main` の push 42723132548、42729705298、42732052330、42735279926、42738715688、42740480282、42743811596、42747377433、42749412945 の `build (…, tests-driver)` と `build (…, tests-rest)` のログ（2026-11-10 に API から `curl` で取った）
