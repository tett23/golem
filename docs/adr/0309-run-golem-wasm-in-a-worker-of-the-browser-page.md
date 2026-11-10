# ADR 0309: ブラウザのページで golem.wasm を Worker の中で動かす

ステータス: 採択

## 文脈

### ブラウザでの比べと、打ち切り

[ADR 0234](0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md) の 5 は、golem.wasm を Chromium と Safari で動かし、組んだ PDF をネイティブの golem と比べると決めた。
ホストは `scripts/wasm/run-browser.mjs` で、入力ごとにブラウザを起こし、`scripts/wasm/browser/run.html` を開く。
ページの `golemBuild()` は、golem.wasm を読み込み、`golem_build_pdf` を呼び、PDF の SHA-256 と diagnostics を返す（[run.html の 35 行から 72 行](https://github.com/tett23/golem/blob/db145a81a219741ca75d9774637398816694e693/scripts/wasm/browser/run.html#L35-L72)）。
ホストは、この関数を WebDriver の Execute Async Script か、CDP の `Runtime.evaluate` で一度だけ呼ぶ（[run-browser.mjs の 46 行から 53 行](https://github.com/tett23/golem/blob/db145a81a219741ca75d9774637398816694e693/scripts/wasm/run-browser.mjs#L46-L53)）。

[ADR 0247](0247-keep-the-values-of-golem-wasm-independent-of-the-width-of-int.md) の 7 は、終わらない入力を `scripts/wasm/compare.sh` が `COMPARE_TIMEOUT` 秒で打ち切ると決めた。
打ち切りでは、`stop` が `pgrep -P` でホストの直接の子を探して TERM を送り、続けてホストに TERM を送る（[compare.sh の 139 行から 163 行](https://github.com/tett23/golem/blob/db145a81a219741ca75d9774637398816694e693/scripts/wasm/compare.sh#L139-L163)）。
Chromium では、ブラウザがホストの子なので、この TERM でブラウザも止まる。
Safari では、ホストの子は `safaridriver` だけである。
Safari と、ページを動かす WebContent のプロセスは、launchd の子として動く。

### Safari に残る WebContent のプロセス

今の `run.html` は、golem.wasm をページのメインスレッドで動かす。
`golem_build_pdf` が返らない間、ページのメインスレッドは止まったままになる。
打ち切りで `safaridriver` とホストが止まっても、そのページの WebContent のプロセスは残る。
「確かめたこと」の実験では、14 入力をすべて打ち切ると 15 個が残り、そのうち一つは 35 秒後も CPU を使い続けていた。
[ADR 0303](0303-check-only-the-processes-a-test-started.md) の作業では、WebDriver のセッションを消しても残ったと報告された（この ADR では確かめていない）。

### 確かめたこと

2026-11-10 から 2026-11-11 に、GitHub Actions の `macos-15` のランナーで次を確かめた。
使ったのは、`main` の `db145a81` から切った実験のブランチ `exp-wasm-worker`（main にはマージしない）である。

- 入力は二つの偽の golem.wasm である。`hang.wasm` は `_initialize` が無限のループで、返らない（60 バイト）。`ok.wasm` は `_initialize` がすぐ返り、`hs_init` を持たないので、ページはすぐ失敗する（55 バイト）。
- 手順は `exp/run.sh` である。`COMPARE_TIMEOUT=20` で `compare.sh --browser safari` を動かし、終わった 5 秒後と 35 秒後に、動かす前にはなかった WebContent のプロセスを `ps -A -ww -o pid= -o ppid= -o pcpu= -o etime= -o comm=` で数える。
- ジョブはそれぞれ別のランナーで動く。前のジョブの残りは数に入らない。

表の「Worker のページ」は、「実装すること」の 1 と 2 の形（golem.wasm を Worker で動かし、ホストは `golemBuild()` を Execute Async Script で一度だけ呼ぶ）である。
結果は次のとおりである（35 秒後の数。5 秒後も同じ数だった）。

| ページ | wasm | 打ち切り | 残った WebContent | 実行 |
| --- | --- | --- | --- | --- |
| 今のページ | `hang.wasm` | 14 入力のすべて | 15。うち一つは CPU 99.1 % | 42843247830 |
| 今のページ | `ok.wasm` | なし | 2。CPU 0 % | 42843247830 |
| Worker のページ | `hang.wasm` | 14 入力のすべて | 2。CPU 0 %（一つは 1.2 %） | 42846595080 |
| Worker のページ | `ok.wasm` | なし | 2。CPU 0 % | 42846595080 |

打ち切らない実行でも、Safari は WebContent のプロセスを二つ残す。
これは Safari が次のページのために残すものと見られ、打ち切りの数に依らない（推測）。
Worker のページでは、14 入力をすべて打ち切っても、残る数は打ち切らない実行と同じ 2 になった。

同じ実験で、Worker に加えて次の三つの止め方も試した。
どれも残る数は 2 で、Worker だけの形と変わらなかった。

- ホストが TERM を受けたら `worker.terminate()` をページで呼び、セッションを消してから終わる。
- ページが、ホストからの問い合わせが 5 秒途絶えたら `worker.terminate()` を呼ぶ。
- `safaridriver` に TERM を無視させ（`trap '' TERM` のあとの `exec`）、ホストが先にセッションを消せるようにする。

Worker だけの形で足りるので、この ADR はこれらを採らない。

本物の golem.wasm でも、一覧が変わらないことを確かめた。
最新の成功した `main` の `ci.yml` の成果物 `golem-wasm` と `wasm-native-list` を取り、Worker のページの `compare.sh --browser` の一覧を `compare.sh --check` でネイティブの一覧と比べた。

| ブラウザ | 実行 | ci.yml の実行 | 結果 | compare.sh の時間 |
| --- | --- | --- | --- | --- |
| Safari | 42846595080（2 回） | 42838162275 | 一致 | 155 秒、163 秒 |
| Chromium（chrome-headless-shell） | 42846595080 | 42838162275 | 一致 | 44 秒 |
| Safari（今のページ） | 42841649123 | 42829205880 | 一致 | 156 秒 |

手元の macOS の Google Chrome でも、今のページと Worker のページの `compare.sh --browser chromium` の一覧が一致した（`CHROMIUM` にヘッドレスで起こすラッパーを渡した）。
Firefox は、`compare.sh` が扱わないので確かめていない。

### 確かめきれなかったこと

Worker のページで、すぐ終わるはずの入力が打ち切られたことが、二度あった。
一度は、本物の golem.wasm の `kanikosen` が `COMPARE_TIMEOUT=120` を超えた（実行 42838744788）。
もう一度は、`ok.wasm` の `determinism` が `COMPARE_TIMEOUT=20` を超えた（実行 42843247830）。
どちらも、ホストが 200 ミリ秒ごとにページへ結果を問い合わせる形（この ADR では採らない形）での実行だった。
今のページの実行（`ok.wasm` を 2 回、本物の golem.wasm を 1 回）では起きなかった。
原因は分かっていない（未確認）。
Worker のページでは、Safari での実行 4 回（`ok.wasm` の 14 入力を 1 回、本物の golem.wasm を 2 回、`hang.wasm` を 1 回）で起きなかった。

## 実装すること

### 1. Worker で組む

`scripts/wasm/browser/worker.js` を足す。
今の `run.html` の `build()` の中身（ファイルを取る、golem.wasm を読み込む、`golem_build_pdf` を呼ぶ、SHA-256 を求める）を、この module Worker に移す。
Worker は、結果を `postMessage({ ok: true, v })` で送る。
`v` は、今の `golemBuild()` の値と同じ `{ status, sha, pdfLen, json }` である。
失敗したときは、`postMessage({ ok: false, e })` を送る。
`e` は、今と同じく、失敗した段階の名前とエラーを `段階: エラー` の形で持つ。

`run.html` の `golemBuild()` は、`new Worker('worker.js', { type: 'module' })` で Worker を作り、その結果で解決する Promise を返す。
結果を受け取ったら、`worker.terminate()` を呼ぶ。
Worker の読み込みの失敗（`error` の事象）は、`worker: メッセージ` で拒否する。
`run.html` のメインスレッドは、golem.wasm を読み込まず、呼ばない。

### 2. ホストが配る

`run-browser.mjs` は、`/__golem/worker.js` に `scripts/wasm/browser/worker.js` を配る。
`golemBuild()` の呼び方（Execute Async Script か `Runtime.evaluate` を一度）は変えない。
`compare.sh`、`webdriver.mjs`、`cdp.mjs` は変えない。

### 3. 打ち切りが WebContent を残さないことの検査

`scripts/wasm/test/browser-leftovers.sh` を足し、夜ごとの `browser.yml` の `safari` のジョブで動かす。
この検査は、ほかのブラウザの作業を並行して動かさない、GitHub Actions の専用の Safari ランナーでだけ動かす。
その実行環境であることを確かめられなければ、Safari を起こす前に失敗する。
[ADR 0303](0303-check-only-the-processes-a-test-started.md) の「テストが起こしたプロセスだけを見る」規則の例外として、この検査に限り、実行前後の WebContent の PID を読み取りで比べることを認める。
この調査は、見つけたプロセスにシグナルを送らず、停止しない。

1. 動かす前の WebContent のプロセスの PID を記録する。
2. `printf` で `hang.wasm` を作業の場所に書く。
3. `compare.sh --browser safari` を、`COMPARE_TIMEOUT=20` で `hang.wasm` に対して動かす。14 入力がすべて `exit timeout` になることを確かめる。
4. 35 秒待ち、動かす前になかった WebContent のプロセスを数える。
5. その数が 14（打ち切った入力の数）より小さいことを確かめる。

数の上限を 2 としないのは、Safari が残す数が Safari の版で変わりうるからである。
上限を打ち切った数より小さくすれば、今のページ（15）は失敗し、Worker のページ（2）は通る。

この検査は 14 × 20 秒ほどかかるので、`safari` のジョブの `timeout-minutes` を、実装のプルリクエストで測った時間の倍ほどに上げる。

### 4. 文書

`scripts/wasm/README` の「The browsers run scripts/wasm/browser/run.html」を、`run.html` が golem.wasm を `worker.js` の Worker で動かすことが分かる文に直す。
`docs/specifications.md` の golem-wasm の節（`scripts/wasm/browser/run.html` を挙げる段落）に、Worker で動かすことと、この ADR へのリンクを足す。

実装のプルリクエストで、[ADR 0303](0303-check-only-the-processes-a-test-started.md) のステータスに、この専用ランナーでの読み取りの例外へのリンクを加える。

## 実装しないこと

- ホストの TERM の処理、ページの見張り、`safaridriver` に TERM を無視させること。「確かめたこと」のとおり、Worker だけの形と残る数が変わらなかった。
- Safari のプロセスを名前で止めること（`pkill Safari` など）。手元の Safari を巻き込み、[ADR 0303](0303-check-only-the-processes-a-test-started.md) の I8 にも反する。
- Firefox で動かすこと。`compare.sh --browser` は `chromium` と `safari` だけを扱う。
- `cdp.mjs` の `close` の 5 秒の `setTimeout` を `unref` すること。手元の Google Chrome では `Browser.close` が答えず、この時計がホストの終わりを 5 秒遅らせた。ただし、CI の chrome-headless-shell で遅れるかは確かめておらず、この ADR の目的とも別である。

## 不変条件

- **I1 打ち切った入力より少ない数に抑える**：`compare.sh --browser safari` で 14 入力をすべて打ち切ったとき、終わった 35 秒後に残る、実行前にはなかった WebContent のプロセスの数は 14 より小さい。
- **I2 一覧が変わらない**：本物の golem.wasm の `compare.sh --browser chromium` と `compare.sh --browser safari` の一覧は、同じコミットのネイティブの一覧と `compare.sh --check` で一致する（[ADR 0234](0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md) の I5 を保つ）。
- **I3 メインスレッドで wasm を動かさない**：`scripts/wasm/browser/run.html` に、`WebAssembly.` と `golem_build_pdf` の文字列が現れない。
- **I4 ページの値の形が変わらない**：`golemBuild()` は、成功すれば `{ status, sha, pdfLen, json }` で解決し、失敗すれば、失敗した段階の名前を頭に持つメッセージで拒否する。
- **I5 失敗が打ち切りにならない**：golem.wasm がすぐ失敗する入力（`ok.wasm`）では、どの入力も `exit timeout` にならず、`exit 3` になる。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 打ち切る入力の数 | 0（`ok.wasm`、I5）、14（`hang.wasm` で全部、I1） |
| golem.wasm | すぐ失敗する（`ok.wasm`）、返らない（`hang.wasm`）、本物 |
| ブラウザ | Chromium（ブラウザがホストの子）、Safari（launchd の子） |
| Worker の読み込み | 読める、読めない（`worker.js` を配らない変異） |

## テスト設計

- **残る数（I1、I5）**：実装の 3 の `browser-leftovers.sh` が `I1` を名前に持つ断言で確かめる。実装の前に、今のページで動かして失敗する（15 ≥ 14）ことを、実装ブランチを指定した `browser.yml` の `workflow_dispatch` で確かめる。打ち切らない側は、`ok.wasm` で `compare.sh` を動かし、14 入力のすべてが `exit 3` になることを、同じスクリプトの `I5` の断言で確かめる。
- **一覧（I2）**：今の `browser.yml` の `compare.sh --check` がそのまま確かめる。実装のプルリクエストでは、`workflow_dispatch` で `browser.yml` を 3 回動かし、Safari のジョブが 3 回とも通ることを確かめる。「確かめきれなかったこと」の打ち切りが起きないかを見るためである。
- **専用ランナーの制限**：専用の GitHub Actions ランナーでない環境では、Safari を起動する前に検査が失敗することを確かめる。
- **メインスレッド（I3）**：`scripts/ci/test.sh` に、`run.html` を `grep` して二つの文字列がないことの断言を足す。名前に `I3` を入れる。
- **値の形（I4）**：`scripts/browser/test/browser.test.mjs` に、`ok.wasm` を配ったページの `golemBuild()` が `initialize: ` で始まるメッセージで拒否することの検査を足す。`worker.js` を配らないページでは、`worker: ` で始まるメッセージで拒否することも足す。Chromium と Safari の両方のジョブで動く。

## トレードオフ

- Worker からページへ `postMessage` で複製するのは `{ status, sha, pdfLen, json }` の値で、PDF 本体は送らない。本物の golem.wasm の Safari の一覧の時間は 155 秒と 163 秒で、今のページの 156 秒と同じほどだった。
- module Worker を読めるブラウザが要る。golem.wasm はすでに Safari 18.4 と Chrome 137 以降を要するので、範囲は狭まらない。
- 検査の 3 は、夜ごとの `safari` のジョブを 5 分ほど延ばす。
- 打ち切りでページを止める仕組みを、Safari が自動化のセッションの終わりにページを閉じる振る舞いに頼る。Safari がこの振る舞いを変えれば、検査の 3 が知らせる。

## 決めたことの記録

2026-11-11 に、tett23 が提案中の Golem [ADR 0306](0306-measure-the-residency-of-forcing-a-table-by-heap-profiles.md) から 0309 について、次のとおり指示した。

> 提案のADRをマージしてサブエージェントで実装

この指示により、この ADR を採択し、実装を別のプルリクエストで進める。

## 参考文献

- [ADR 0234](0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md)、[ADR 0247](0247-keep-the-values-of-golem-wasm-independent-of-the-width-of-int.md)、[ADR 0303](0303-check-only-the-processes-a-test-started.md)
- WHATWG HTML Living Standard、Web workers（`Worker`、`terminate()`、module Worker）。https://html.spec.whatwg.org/multipage/workers.html
- W3C WebDriver、Execute Async Script と Delete Session。https://www.w3.org/TR/webdriver2/
- 実験の実行：https://github.com/tett23/golem/actions/runs/42843247830 、https://github.com/tett23/golem/actions/runs/42845167759 、https://github.com/tett23/golem/actions/runs/42846595080 、https://github.com/tett23/golem/actions/runs/42841649123 、https://github.com/tett23/golem/actions/runs/42838744788
