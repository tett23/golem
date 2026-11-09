# ADR 0249: `golem` を `-with-rtsopts=-N -A64m` でリンクし、GC の回数を減らす

ステータス: 採択→速さの比べ方と CI の時間は [ADR 0255](0255-record-what-implementations-decided-on-2026-11-09.md)

## 文脈

### 組版の時間の三割が GC である

[docs/benchmarks/2026-11-09-typesetting-speed-survey.md](../benchmarks/2026-11-09-typesetting-speed-survey.md)（以下「記録」）で、`main` のコミット `08d09332` の `golem build --target pdf` を `+RTS -s` で測った。
利用者向けマニュアル（217 ページ）は壁時計で 9.7 秒から 11.5 秒、CPU 時間で 22 秒から 26 秒かかり、ヒープに 50.1 GB を割り当てる。
その CPU 時間のうち 6.8 秒から 7.5 秒が GC で、全体の 29% である。
十冊のパブリックドメインの本でも GC は CPU 時間の 28% から 35% を占める（記録の表 1）。

GC が多い理由は、割り当て領域（nursery）の大きさである。
`golem` は `-with-rtsopts=-N` でリンクされ（[`golem-cli.cabal`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-cli/golem-cli.cabal#L13-L16)）、GHC の既定の `-A4m` で動く。
capability ごとの 4 MB の nursery が埋まるたびに世代 0 の GC が起き、そのたびにすべての capability が同期する。
マニュアルの一回のビルドで世代 0 の GC は 5,300 回から 5,800 回起きる（記録の表 2）。
段落の組版は `mapConcurrently` で並列に進むが、10 個の capability のうち動いているのは平均 2 個から 3 個で（CPU 時間と壁時計の比 2.0 から 2.8）、残りは GC の同期を待つ。

### 測った RTS のオプション

`-rtsopts` でリンクし直した同じ `golem` で、GC のオプションを変えて測った（記録の表 2、各 3 回の範囲）。

| オプション | マニュアル（秒） | 開発者向けマニュアル（秒） | 『蟹工船』（秒） | 『Nightmare Abbey』（秒） |
| --- | --- | --- | --- | --- |
| なし（`-A4m`） | 9.67 から 9.88 | 8.42 から 13.89 | 2.06 から 2.13 | 2.49 から 2.55 |
| `-A16m` | 9.26 から 9.83 | 測っていない | 測っていない | 測っていない |
| `-A32m` | 測っていない | 6.28 から 6.45 | 1.53 から 1.56 | 1.83 から 1.87 |
| `-A64m` | 7.12 から 7.84 | 6.10 から 6.22 | 1.53 から 1.59 | 1.77 から 1.81 |
| `-A128m -n4m` | 6.90 から 6.97 | 測っていない | 測っていない | 測っていない |
| `-A64m -qn4` | 7.18 から 8.70 | 6.36 から 6.97 | 1.58 から 1.61 | 1.81 から 1.87 |
| `-A64m -qg` | 8.78 から 9.51 | 7.87 から 7.91 | 1.90 から 1.95 | 2.26 から 2.27 |
| `-qg` | 10.55 から 10.70 | 9.12 から 9.35 | 測っていない | 測っていない |

`-A64m` で、マニュアルは 25% から 28%、開発者向けマニュアルは 27% 以上、『蟹工船』は 25%、『Nightmare Abbey』は 28% 速くなる。
世代 0 の GC は 5,300 回から 73 回に減り、CPU 時間は 22.5 秒から 18.8 秒から 19.1 秒になる。
`-A32m` は `-A64m` とほぼ同じ速さである。
`-A128m` は `-A64m` よりさらに 3% ほど速いが、メモリが 3.1 GB になる。
並列 GC を止める `-qg` は CPU 時間を減らすが、GC が一つのスレッドで走るので壁時計は延びる。
GC のスレッドを 4 つに限る `-qn4` は `-A64m` 単独と差がない。

メモリ（`+RTS -s` の「total memory in use」）は、nursery が capability の数だけ増える分だけ増える。
10 個の capability で `-A64m` は 640 MB、`-A32m` は 320 MB である。

| 入力 | なし | `-A32m` | `-A64m` |
| --- | --- | --- | --- |
| マニュアル | 1.80 GB から 1.87 GB | 2.36 GB から 2.37 GB（`-qn4` と） | 2.34 GB |
| 開発者向けマニュアル | 1.29 GB から 1.31 GB | 1.52 GB から 1.58 GB | 1.78 GB から 1.86 GB |
| 『蟹工船』 | 0.44 GB から 0.46 GB | 0.69 GB | 0.97 GB から 1.01 GB |
| 『Nightmare Abbey』 | 0.48 GB から 0.49 GB | 0.66 GB から 0.69 GB | 0.93 GB から 0.94 GB |

### 出力は変わらない

GC のオプションはプログラムの意味を変えない。
[ADR 0050](0050-run-golem-on-every-processor.md) は「`-A` や `-M` のような GC の設定は出力に影響しないはずだが、利用者に開く理由がない」として `-rtsopts` を付けなかった。
この ADR は `-rtsopts` を付けず、リンクのときに決める既定値（`-with-rtsopts`）だけを変える。
`GHCRTS=-N<n>` と `+RTS -N<n> -RTS` で capability の数を変えられることは、GHC の既定の `-rtsopts=some` のまま変わらない。

## 実装すること

- `modules/golem-cli/golem-cli.cabal` の `executable golem` の `ghc-options` を `-threaded "-with-rtsopts=-N -A64m"` にする。
- `test-suite golem-cli-test` の `RtsSpec` が `("Flag -with-rtsopts", "-N")` を確かめている箇所（[`RtsSpec.hs`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-cli/test/RtsSpec.hs#L31-L32)）を、`-N` と `-A64m` の両方を含むことを確かめる形にする。
- `scripts/ci/rts-capabilities.sh` が `-with-rtsopts=-N` の有無を見ている箇所を、`-with-rtsopts` の値が `-N` で始まることを見る形にする。
- 仕様書の「CLI」の節の `-with-rtsopts=-N` の文（[`docs/specifications.md`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/docs/specifications.md#L4818-L4822)）に、割り当て領域を `-A64m` にしていること、`-rtsopts` は付けないことを書き、この ADR へのリンクを付ける。
- 開発者向けマニュアルの「並列の組版」の節に同じことを一文で足す。
- [ADR 0050](0050-run-golem-on-every-processor.md) のステータスの行を「採択→`-with-rtsopts` の GC の設定は [ADR 0249](0249-link-golem-with-a-64-mb-allocation-area.md)」に改める。
- 実装のプルリクエストで、記録と同じ方法でマニュアルと十冊を測り直し、`docs/benchmarks/` に記録を足す。

## 実装しないこと

- `-rtsopts` を付けること。利用者が GC の設定を変える理由はなく、[ADR 0050](0050-run-golem-on-every-processor.md) の判断を保つ。
- `-qg`、`-qn`、`-n`、`--nonmoving-gc` を付けること。測った範囲で `-A64m` 単独より速くならない。`-A` が 16 MB 以上のとき GHC は `-n4m` を既定で有効にするので、`-n` を書く必要もない。
- `-A128m` にすること。3% の差にメモリが 0.8 GB 増える。
- テストのスイート（`golem-driver-test`、`golem-cli-test` など）の `-with-rtsopts` を変えること。テストの時間は GC より tasty の並列度とランナーのコア数で決まり（[ADR 0146](0146-threaded-golem-driver-test.md)）、別に測ってから決める。
- `golem-lsp`、`golem-emet`、`golem-wasm` の RTS の設定を変えること。LSP の応答の時間は [golem-lsp ADR 0005](../golem-lsp/adr/0005-keystroke-latency-and-ordered-evaluation.md) が扱い、wasm は RTS の GC を持たない。
- 割り当ての量そのものを減らすこと。50 GB の割り当ては組版のコードの問題で、[ADR 0250](0250-character-class-tables-instead-of-list-membership.md) 以降が扱う。

## 不変条件

- **I1 出力は変わらない**：どの入力でも、`-A64m` でリンクした `golem` の `build/` の下のすべてのファイルのバイト列、終了コード、標準出力、標準エラー出力（`--format json` の diagnostics）は、`-A4m` のものと一致する。
- **I2 リンクの設定**：`golem +RTS --info -RTS` の `Flag -with-rtsopts` の値は `-N` を含み、`-A64m` を含む。`RTS way` は `rts_thr` である。
- **I3 capability の数は外から変えられる**：`GHCRTS=-N1` と `+RTS -N2 -RTS` で起動した `golem` は起動し、出力は変わらない（[ADR 0050](0050-run-golem-on-every-processor.md) の `caps-one`、`caps-two`）。
- **I4 GC の設定は外から変えられない**：`+RTS -A4m -RTS` で起動した `golem` は「Most RTS options are disabled」を出して終了コード 1 で止まる。`-rtsopts` が付いていないことの検査である。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| capability の数 | 1、2、計算機のすべて |
| 入力の大きさ | `sample`（数ページ）、`snark`（36 KB、0.5 秒）、利用者向けマニュアル（217 ページ、最大） |
| RTS のオプション | なし、`-N1`、`-N2`、`-A4m`（I4） |

## テスト設計

先に書いて失敗させてから実装するもの。

- I2：`modules/golem-cli/test/RtsSpec.hs` の `--info` の検査を、`Flag -with-rtsopts` の値を読んで `-N` と `-A64m` を単語として含むことを確かめる形にする。今の `golem` では `-A64m` がなく失敗する。
- I4：同じ `RtsSpec` に、`golem +RTS -A4m -RTS --version` が終了コード 1 で止まり、標準エラー出力に `Most RTS options are disabled` を含むことを確かめるテストを足す。`-rtsopts` を付けないことの回帰テストである。今の `golem` でも通るので、実装の前後で通ることを確かめる。
- `scripts/ci/test.sh` の `rts-capabilities.sh` の検査に、`-with-rtsopts` の値が `-N` で始まる `.cabal` を通し、`-N` を含まないものを拒む fixture を足す。

既存のテストで確かめること。

- I1 と I3：`scripts/env-determinism/check.sh` の `caps-one`、`caps-two`、`combined` は変えずに走らせ、通ることを確かめる。基準の環境が `-A64m` で、`caps-one` が `-N1 -A64m` になる。
- I1：`scripts/determinism.sh` の二回のビルドの一致。

測って確かめること（実装のプルリクエストの説明に書く）。

- 記録と同じ方法（`build/` を消して 3 回、壁時計と `+RTS -s`）でマニュアル、開発者向けマニュアル、十冊を測り、壁時計の中央値が記録の「なし」より 20% 以上短いこと、世代 0 の GC の回数が 100 回未満であることを確かめ、`docs/benchmarks/` に書く。
- CI の `cabal test` の時間は変わらないことを、実装のプルリクエストの実行で確かめる。`golem` の実行ファイルの設定なので、テストのスイートの RTS には影響しない。

CI に組版の時間の検査は足さない。
GitHub のランナーの時間は実行ごとに 2 倍ほど揺れ（[docs/ci-timings/2026-11-09-ci-critical-path-and-download-failures.md](../ci-timings/2026-11-09-ci-critical-path-and-download-failures.md)）、5 分の予算の中で 20% の差を見分けられない。

## トレードオフ

- 速さとメモリの交換である。10 個の capability の計算機で、一回のビルドのメモリが 0.5 GB ほど増える。4 コアの CI のランナーでは 240 MB である。`golem` は一つの本を組んで終わるコマンドなので、常駐のメモリより一回の時間を取る。
- capability の数が多いほど nursery の合計は大きい。64 コアの計算機では 4 GB になる。そのような計算機で問題になれば、`GHCRTS` ではなく（`-rtsopts` がないので変えられない）、`-N` の既定を見直す ADR で扱う。
- `-A32m` は速さがほぼ同じでメモリが半分である。差が小さいので、「メンテナーが決めること」の 1 に残す。
- GC の回数を減らしても、割り当ての量（50 GB）は変わらない。この ADR は症状を抑えるだけで、[ADR 0250](0250-character-class-tables-instead-of-list-membership.md) 以降の割り当てを減らす変更と組み合わせて働く。

## メンテナーが決めること

1. **nursery の大きさ**：推奨は `-A64m` である。測った四つの入力のすべてで最速か同率で、GHC の `-n4m` も既定で有効になる。
   - 退けた案は `-A32m` である。速さは 0% から 3% 劣るだけでメモリの増加は半分なので、メモリの小さい計算機を重く見るならこちらにする。
   - もう一つは `-A128m` である。3% 速いが、メモリが 0.8 GB 増える。
2. **テストのスイートにも同じ設定を広げるか**：推奨は、この ADR では広げず、実装のプルリクエストの CI の時間を見てから別の ADR で決めることである。[ADR 0146](0146-threaded-golem-driver-test.md) は golem-parser-test で `-A64m` が 12.35 秒を 10.29 秒から 10.97 秒にしたと記録しているが、ランナーの終わりは別のスイートが決めていた。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-09、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [ADR 0002](0002-determinism.md)、[ADR 0029](0029-environment-variation-determinism-test.md)、[ADR 0050](0050-run-golem-on-every-processor.md)、[ADR 0146](0146-threaded-golem-driver-test.md)、[golem-driver ADR 0002](../golem-driver/adr/0002-pdf-pipeline.md)
- [docs/benchmarks/2026-11-09-typesetting-speed-survey.md](../benchmarks/2026-11-09-typesetting-speed-survey.md)
- [`modules/golem-cli/golem-cli.cabal`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-cli/golem-cli.cabal#L13-L16)、[`modules/golem-cli/test/RtsSpec.hs`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-cli/test/RtsSpec.hs#L31-L32)、[`scripts/ci/rts-capabilities.sh`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/scripts/ci/rts-capabilities.sh)、[`docs/specifications.md` の CLI の節](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/docs/specifications.md#L4818-L4822)
- GHC User's Guide 9.10, "Running a compiled program", RTS options to control the garbage collector（`-A`、`-n`、`-qg`、`-qn`）。https://downloads.haskell.org/ghc/9.10.3/docs/users_guide/runtime_control.html#rts-options-to-control-the-garbage-collector
