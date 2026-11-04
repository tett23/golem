# ADR 0163: 見た目の回帰テストの PDF を、入力ごとに並べて組む

ステータス: 採択（未実装）

## 文脈

[ADR 0155](0155-split-aarch64-test-runner.md) の後の `ci.yml` では、`build` の最後に終わるランナーが x86-64 の `outputs` と `tests-rest` のどちらかになった。
2026-11-04 の 18:24 から 18:42 UTC の 7 回の実行（41886607899 から 41889606653 まで）で、最後に終わったのは `outputs` が 4 回、`tests-rest` が 2 回、`env` が 1 回だった（41887719789 は `main` で、モジュールのビルドが長かった）。

### outputs の手順

同じ実行のうち 6 回で、x86-64 の `outputs` の手順の秒数は次のとおりだった。

| 手順 | 秒 |
|---|---|
| 見た目の回帰テストの PDF（`scripts/visual/build.sh`） | 42〜57 |
| 二つの EPUB の epubcheck | 7〜13（合わせて） |
| 決定性の検査の出力（`scripts/determinism.sh`） | 17〜25 |

見た目の回帰テストの PDF は、`outputs` で最も長い手順である。
`visual` ジョブはこの PDF が上がるのを待つので、この手順は `visual` の終わりも決める（[ADR 0099](0099-visual-job-waits-only-for-visual-pdfs.md)、[ADR 0140](0140-ci-split-test-runners-and-visual-pdfs-first.md)）。

### build.sh は入力を一つずつ組む

`scripts/visual/build.sh` は、15 の入力（見本、図、蟹工船の二つ、テンペスト、十冊）を一つずつ `golem build` で組み、その後で二つのマニュアルを `scripts/manual/build.sh` で組む（[build.sh](https://github.com/tett23/golem/blob/19d0ec3e0ac22110392a6a64160f59e0890786f6/scripts/visual/build.sh#L44-L131)）。
golem は `-N` で動くが、一つの入力の組版はプロセッサを使い切らない。

手元（10 コアの macOS、GHC 9.10.3）で、origin/main の 19d0ec3e の golem を使って計測した。

| 組み方 | 実時間（秒） | user（秒） |
|---|---|---|
| 今の `build.sh`（一つずつ） | 42.78 | 57.46 |
| 15 の入力を同時に組み、終わってから二つのマニュアルを組む（2 回） | 20.29、20.20 | 61.27 |

今の `build.sh` の中の内訳は、15 の入力が合わせて約 19 秒（一つあたり 0.1〜2.2 秒）、二つのマニュアルが約 14 秒だった。
並べて組んだ 17 の PDF は、二回とも、今の `build.sh` が組んだものとバイト単位で一致した。

並べるときに直す点がある。
`build.sh` の `pdf` と `one` は、失敗のときの出力（`$WORK/log`）と見つけた PDF の一覧（`$WORK/pdfs`）に、入力によらない同じファイルを使っている。
そのまま並べた最初の試しでは、`one` が別の入力の PDF を拾い、三つの PDF が違うものになった。
入力ごとのファイルにすると一致した。

### 見込み

CI の x86-64 のランナーは 4 コアなので、手元の 10 コアほどは縮まない。
今の 42〜57 秒のうち、15 の入力の部分（手元の比で約 45%）が数分の一になり、20〜30 秒前後になると見込む。
`outputs` と `visual` が 15〜25 秒早く終わる。
実行全体を縮めるのは、`outputs` が最後に終わる実行で、上の 7 回では 4 回だった。
二番めのランナーとの差は 1〜32 秒だったので、縮む秒数はその差を超えない。

## 実装すること

テストを先に書き、今の実装で失敗することを確かめる。

- `scripts/visual/build.sh` で、15 の入力の `golem build` を、ランナーのプロセッサの数（`getconf _NPROCESSORS_ONLN`、取れなければ 1）を上限に同時に走らせる。二つのマニュアルは、入力と同時に組み始める。
- 失敗のときの出力と、見つけた PDF の一覧は、入力ごとのファイルにする。
- どれかの入力が組めなければ、今と同じく、その入力の golem の出力を標準エラー出力に書いて、終了コード 1 で終わる。ほかの入力が終わるのを待ってから終わる。
- 入力の一覧（`--list`）、出力のファイルの名前と中身、マニュアルを組む条件（固定のコミットとタグ）は変えない。
- `ci.yml` は変えない。
- 計測の結果を `docs/ci-timings/` に記録する。

## 実装しないこと

- **`scripts/determinism.sh` を並べること。** 決定性の検査の出力は 17〜25 秒で、その中の二つのマニュアルが大半を占める。マニュアルは一つずつ大きく、並べても縮みは小さい。出力の一覧の順を保つ手間も増える。
- **見た目の回帰テストの PDF を、別のランナーで組むこと。** golem のビルドがもう一度要る（[ADR 0099](0099-visual-job-waits-only-for-visual-pdfs.md) の「実装しないこと」と同じ理由）。
- **golem-pdf-test を複数のスイートに分けて、同時に走らせること。** 下の「検討して退けたこと」を見よ。

## 検討して退けたこと

### golem-pdf-test を並べること

x86-64 の `tests-rest` の終わりを決めるのは golem-pdf-test で、CI で 40〜75 秒かかる。
golem-pdf-test は threaded でない RTS で、テストを一つずつ走らせる。
CPU 時間の上限を、プロセスの CPU 時間で測るテストがあるためである（[ADR 0091](0091-cpu-time-limits-in-pdf-and-svg-tests.md)）。

手元で測ると、golem-pdf-test の 251 のテストの 32.49 秒のうち、`security` の群の 29 のテストが 31.70 秒を占め、残りの 222 のテストは 0.85 秒だった。
`security` の群の時間は、8 MiB のストリームを 40 回参照する、合わせて 256 MiB を展開する、といった大きな入力の処理で、GC は 1% に満たなかった（`+RTS -s` で GC が 0.27 秒、`-A16m`、`-A64m` でも縮まない）。
これらの多くが CPU 時間の上限の補助（`withinTimeLimits`）を使うので、threaded にはできない。
縮めるには、`security` の群を複数の threaded でないスイートに分け、別のプロセスとして同時に走らせることになる。

一方、同じ 7 回の実行の `tests-rest` では、golem-pdf-test が終わるのは golem-parser-test の終わりから −3〜19 秒後で、中央値は 12 秒だった。
golem-pdf-test を縮めても、`tests-rest` は golem-parser-test（threaded、45〜60 秒）で決まる。
`tests-rest` が最後に終わったのは 7 回のうち 2 回で、縮む秒数は一回あたり数秒になる。
テストのモジュールを分ける手間に見合わないので、この ADR では扱わない。

## テスト設計

### 先に書いて失敗させるテスト（`scripts/visual/test.sh`）

- 偽の golem（入力の名前ごとに決まった時間だけ待ってから一つの PDF を書くもの）で `build.sh` を走らせ、17 の PDF が今と同じ名前で書かれ、それぞれが自分の入力の PDF であること。待つ時間を、先に始めた入力ほど長くして、`one` が別の入力の PDF を拾わないことを確かめる。
- 偽の golem が二つの入力を同時に組んだことを、偽の golem が書く印のファイルで確かめる（今の `build.sh` では、同時に動く数が 1 を超えないので失敗する）。同時に動く数が、`getconf _NPROCESSORS_ONLN` の値を超えないこと。
- 偽の golem が一つの入力で失敗すると、`build.sh` がその入力の出力を標準エラー出力に書き、終了コード 1 で終わること。ほかの入力の golem が終わってから終わること。

### 自動テストにできないものの確かめ方

- 実装のプルリクエストで、`visual` ジョブが参照と一致して通ること。
- 同じプルリクエストの 2 回の実行で、`outputs` の「The PDFs of the visual regression test」の秒数と、`outputs` と `visual` の終わりを記録する。

## トレードオフ

- 見込める短縮は、`outputs` と `visual` で 15〜25 秒、実行全体では `outputs` が最後に終わる実行だけで、二番めのランナーとの差（1〜32 秒）までである。
- `build.sh` に、背景のプロセスを数え、待つ処理が加わる。POSIX の `sh` で書き、macOS の `scripts-macos` でもテストする（[ADR 0079](0079-shell-tests-on-macos.md)）。
- 同時に組む入力の数だけ、メモリーを多く使う。x86-64 のランナー（16 GB）で、4 つの golem と二つのマニュアルの組版が同時に動く。
- 失敗した入力の出力は、ほかの入力の出力と交ざらないが、標準エラー出力に書く順は入力の順と変わりうる。

## 決めたことの記録

- **採択**：メンテナーが採択した（2026-11-05）。この ADR が決めてほしい点として挙げた項目は、どれも ADR の推奨のとおりとする。

## 参考文献

- [scripts/visual/build.sh](https://github.com/tett23/golem/blob/19d0ec3e0ac22110392a6a64160f59e0890786f6/scripts/visual/build.sh)
- [ADR 0079](0079-shell-tests-on-macos.md)、[ADR 0091](0091-cpu-time-limits-in-pdf-and-svg-tests.md)、[ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md)、[ADR 0095](0095-visual-job-in-ci.md)、[ADR 0099](0099-visual-job-waits-only-for-visual-pdfs.md)、[ADR 0140](0140-ci-split-test-runners-and-visual-pdfs-first.md)、[ADR 0155](0155-split-aarch64-test-runner.md)
- 計測のデータ：上の 7 回の実行（2026-11-04）と、手元の計測（2026-11-05）
