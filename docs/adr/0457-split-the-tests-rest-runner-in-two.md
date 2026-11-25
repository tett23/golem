# ADR 0457: プルリクエストの CI の tests-rest の脚を二つに分ける

Status: accepted-pending

## 文脈

[root ADR 0416](0416-shorten-the-build-of-the-pull-request-ci.md) は、golem-driver-test を分けて、プルリクエストの CI の時間を予算の 300 秒に収めようとした。
0416 の後の 20 回の中央値は 330 秒で、予算を 30 秒超えた（[記録](../ci-timings/2026-11-26-pull-request-ci-after-adr-0416.md)）。
0416 の「測る」の節は、中央値がまだ 300 秒を超えるときは、臨界経路の脚を測り直し、次の手を新しい ADR で決めると定めた。
メンテナーは、2026-11-26 に、この続きの ADR を作るよう求めた。

この ADR は、測り直した臨界経路をもとに、tests-rest の脚を二つに分けることを決める。
見込みでは、この手で予算の前後まで縮むが、収まるとは言えない。
収まらなければ、測った値を添えて次の手を別の ADR で決める。

## 調査した事項

0416 の記録と同じ 20 回の `ci.yml` の実行（45587653726 から 45712986764）を、`gh api` で取ったジョブと手順の時刻と、ジョブのログで調べた。
`scripts/ci/ci-critical-path.sh` で求めた中央値は 330 秒で、記録と一致した。

### 臨界経路

臨界経路は、次の三つだった。

| 臨界経路 | 回数 |
| --- | --- |
| changes、build、determinism、ci | 13 |
| changes、wasm、ci | 5 |
| changes、scripts-macos、ci | 2 |

ジョブの時間の中央値（秒）は、次のとおりだった。
build は、実行ごとに matrix の脚のうち最も長いものの時間を取り、その中央値とした。

| ジョブ | 中央値 |
| --- | --- |
| changes | 16.5 |
| build | 278.5 |
| determinism | 10.5 |
| wasm | 216 |
| scripts-macos | 215 |
| ci | 30 |

changes、determinism、ci の中央値の和は 57 秒である。
wasm の経路と scripts-macos の経路は、ジョブの中央値の和で 262.5 秒と 261.5 秒である。

### テストの脚

build で最も長い脚は、20 回のうち、ARM64 の tests-rest が 9 回、x86-64 の tests-rest が 8 回、tests-driver-b が 3 回だった。
テストの脚の全体の時間の中央値（秒）は、次のとおりだった。

| 脚 | x86-64 | ARM64 |
| --- | --- | --- |
| tests-driver-a | 157 | 146 |
| tests-driver-b | 187.5 | 214 |
| tests-rest | 251.5 | 244 |

tests-rest の脚の、3 秒を超えた手順の時間の中央値（秒）は、次のとおりだった。
括弧の中は、3 秒を超えた回数である。

| 手順 | x86-64 | ARM64 |
| --- | --- | --- |
| The test suites of the runner | 146.5（20） | 156（20） |
| cabal build | 21（18） | 66.5（10） |
| Restore dist-newstyle | 15.5（20） | 19（20） |
| Cache the cabal store | 11（20） | 10.5（20） |
| Run haskell-actions/setup | 5（10） | 8（20） |
| Run actions/checkout | 5（16） | 4（4） |

パーサーの照合、埋め込みの照合、キャッシュの保存の手順は、どの回も 3 秒以下だった。

### tests-rest のテストの手順

この手順は `cabal test $(sh scripts/ci/test-suites.sh "$SUITES")` で、スイートは並行に走る（[ci.yml#L480-L483](https://github.com/tett23/golem/blob/7ef91831d4894e9012f15b2aa5f6c2c555c5de68/.github/workflows/ci.yml#L480-L483)）。
ログでは、五つ以上のスイートが同時に走っていた。
並行に走る仕組み（cabal の既定の動き）と、スイートの始まる順の決まり方は、確かめていない。

スイートの時間の中央値（秒、ログの `finished in` から読んだ）は、次のとおりだった。
10 秒以上のものだけを挙げる。

| スイート | x86-64 | ARM64 |
| --- | --- | --- |
| golem-emet-test | 104.5 | 116 |
| golem-pdf-test | 86.5 | 96.5 |
| golem-layout-test | 86.5 | 77 |
| golem-parser-test | 55 | 53.5 |
| golem-lsp-test | 17.5 | 20 |
| golem-svg-test | 15 | 12 |
| golem-test-support-test | 14 | 14 |
| golem-cli-test | 12 | 14.5 |

一回の実行のスイートの時間の和は、x86-64 で 399 から 737 秒、ARM64 で 336 から 461 秒あり、手順の時間より長い。
40 の脚のすべてで、最後に終わったスイートは golem-pdf-test で、その終わりは手順の始まりから中央値で 146.5 秒（ARM64 は 156 秒）だった。
golem-pdf-test の時間は 86.5 秒（ARM64 は 96.5 秒）なので、golem-pdf-test は手順の始まりから 60 秒ほど後に始まっている。
golem-emet-test は、手順の始まりから中央値で 9 秒（ARM64 は 8 秒）で始まっていた。

### 分け方の仕組み

`scripts/ci/test-suites.sh` は、golem-driver のスイートを `DRIVER_A` の一覧とそのほかに分け、新しいスイートが一覧に書かなくても driver-b で走るようにしている（[test-suites.sh#L31-L37](https://github.com/tett23/golem/blob/7ef91831d4894e9012f15b2aa5f6c2c555c5de68/scripts/ci/test-suites.sh#L31-L37)）。
`scripts/ci/build-targets.sh` の `rest` は、rest のスイートと peg-hs と、golem のほかの実行ファイル（どのスイートも組まないもの）を組む対象にする。
tests-rest の脚は、`matrix.suites == 'rest'` のときに、生成したパーサーと文法の照合（peg-hs を使う `scripts/gen-parser.sh`）と、埋め込んだモジュールの照合（`scripts/gen-embedded.sh`、cabal を使わない）を走らせる（[ci.yml#L484-L496](https://github.com/tett23/golem/blob/7ef91831d4894e9012f15b2aa5f6c2c555c5de68/.github/workflows/ci.yml#L484-L496)）。
`scripts/ci/test.sh` は、matrix の脚の行と、二つの照合の手順の条件を確かめている。

## 実装すること

### 脚を分ける

x86-64 と ARM64 のそれぞれで、tests-rest の脚を tests-rest-a と tests-rest-b の二つに分ける。
matrix の脚は、10 から 12 に増える。

| 脚 | スイート | 組む実行ファイル | 照合の手順 |
| --- | --- | --- | --- |
| tests-rest-a | golem-emet-test、golem-parser-test | peg-hs | パーサーと文法の照合、埋め込んだモジュールの照合 |
| tests-rest-b | rest のほかのすべてのスイート | golem のほかの実行ファイル | なし |

- 最も長い golem-emet-test と、最後に終わる golem-pdf-test を別の脚に置き、golem-pdf-test が始まるまでの待ちを減らす。
- `scripts/ci/test-suites.sh` に、`rest-a`（`REST_A` の一覧のスイート）と `rest-b`（rest のほかのスイート）を足す。
  新しいスイートは、一覧に書かなくても rest-b に入る。
  `rest` は、今と同じく rest-a と rest-b の和を出す。
- `scripts/ci/build-targets.sh` に、`rest-a`（rest-a のスイートと peg-hs）と `rest-b`（rest-b のスイートと golem のほかの実行ファイル）を足す。
  一覧に無い新しい実行ファイルは、rest-b で組む。
  `rest` は、今と同じく二つの和を出す。
- 二つの照合の手順の条件を `matrix.suites == 'rest-a'` にし、`scripts/ci/test.sh` の matrix の脚の行と、照合の手順の条件の期待を変える。
- `scripts/ci/suite-limits.sh` と、`rest` を使うほかの呼び出しは変えない。
- 割り当ては、実装のプルリクエストで測った時間を見て入れ替えてよい。
  入れ替えたら、表を実装のプルリクエストに書く。

### 見込み

tests-rest の脚のうち、テストの手順のほかの部分は、x86-64 で 105 秒、ARM64 で 88 秒である（脚の全体からテストの手順を引いた値）。
分けた後のテストの手順を、tests-rest-a は golem-emet-test と同じほど（110 から 125 秒）、tests-rest-b は golem-pdf-test が早く始まって 100 から 130 秒と見込む。
すると、二つの脚は 190 から 235 秒になる。
tests-driver-b（187.5 秒と 214 秒）が、最も長い脚になりうる。

build の中央値は実行ごとの最も長い脚で決まるので、脚の中央値より長くなる。
今は、脚の中央値の最大 251.5 秒に対し、build の中央値は 278.5 秒で、27 秒長い。
同じ差が残ると、build は 240 から 260 秒、臨界経路は 57 秒を足して 297 から 317 秒になる。
予算の前後であり、収まるとは言えない。
二つの脚のテストの手順の時間と、build と脚の中央値の差が残るかは、推測である。

### 測る

- 実装のマージの後の、成功したプルリクエストの `ci.yml` 20 回の中央値を、`scripts/ci/ci-critical-path.sh` で測り、`docs/ci-timings/` に記録する。
- 中央値がまだ 300 秒を超えるときは、臨界経路を測り直し、次の手を新しい ADR で決める。
  候補は、時間のかかるスイートを先に始めること、golem-emet-test と golem-pdf-test の中の時間のかかるテストの短縮、テストの脚の始めの手順（キャッシュの復元とストアのキャッシュ）の短縮である。

## 実装しないこと

テストの中身と名前は変えない。
tests-driver-a と tests-driver-b の割り当ては変えない。
`ci` のジョブが待つジョブは変えない。
予算の 300 秒は変えない。

## 不変条件

- I1: rest のどのスイートも、`test-suites.sh` の rest-a と rest-b のちょうど一方に入る。
- I2: `test-suites.sh` の rest-a と rest-b の和は、rest と同じスイートの集合である。
- I3: `REST_A` に書いていない新しいスイートは、rest-b に入る。
- I4: `build-targets.sh` の rest-a と rest-b の和は、rest と同じ対象の集合である。
- I5: `build-targets.sh` の各脚の対象は、`test-suites.sh` の同じ脚のスイートをすべて含み、rest-a は peg-hs を含む。
- I6: `ci.yml` の二つの照合の手順は、tests-rest-a の脚でだけ走る。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| 今のスイートの一覧 | rest-a と rest-b に分かれ、和は rest | I1, I2 |
| 新しいスイートを足したモジュール | rest-b に入る | I3 |
| `REST_A` に、どのモジュールにも無い名前を書いた | rest-a と rest-b の和は変わらない | I2 |
| `REST_A` に golem-driver のスイートを書いた | rest-a にも rest-b にも出ない | I1 |
| 実行ファイルを一つ足したモジュール | rest-b の組む対象に入る | I4 |
| `buildable: False` の実行ファイル | どちらの組む対象にも入らない（今と同じ） | I4 |
| 今の `ci.yml` | 照合の手順の条件は rest-a | I6 |

## 受けいれ条件

A1: 実装のマージの後の、成功したプルリクエストの `ci.yml` 20 回の中央値を `scripts/ci/ci-critical-path.sh` で測り、`docs/ci-timings/` に記録する。
300 秒以下なら予算を満たす。
超えたら、測る節のとおり次の ADR を作る。

A2: 実装のプルリクエストの CI のログで、二つのアーキテクチャのそれぞれで、tests-rest-a と tests-rest-b の脚が走らせたテストの名前と数の和を、分ける前の tests-rest の脚と比べ、等しいことをプルリクエストに書く。

## テスト設計

root ADR 0457 I1 から I6 を名前の先頭に置いたテストを、`scripts/ci/test.sh`（今の matrix の脚と `test-suites.sh` を確かめるテストのある場所）に足す。
一時のモジュールの木を作り、`test-suites.sh` と `build-targets.sh` の rest、rest-a、rest-b の出力を比べて I1 から I5 を、`ci.yml` の照合の手順の条件を読んで I6 を確かめる。
A1 はマージの後の 20 回で、A2 は実装のプルリクエストの CI のログで確かめる。
テストは、実装の前に書いて落ちることを確かめる。

## トレードオフ

アーキテクチャごとに一つ、合わせて二つの脚が増えるので、ランナーの時間の和は増える。
増えるのは、脚の始めの手順（チェックアウト、GHC の用意、キャッシュの復元）と `cabal build` の手順の、二回分である。

見込みでは、この手だけでは 300 秒に収まらない場合がある。
それでも、tests-rest は 20 回のうち 17 回で最も長い脚で、ほかの手を足すときも、先に分けておくほうが、どの手がどれだけ縮めたかを測りやすい。

## 参考文献

- [root ADR 0416](0416-shorten-the-build-of-the-pull-request-ci.md)
- [root ADR 0395](0395-bring-the-pull-request-ci-under-five-minutes.md)
- [root ADR 0392](0392-budget-the-pull-request-ci-at-five-minutes.md)
- [root ADR 0292](0292-limit-the-time-of-each-test-suite-by-the-median-of-main.md)
