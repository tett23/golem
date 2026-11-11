# ADR 0307: wasm32 のテストのスイートに、走らせるごとの一時のディレクトリを `/tmp` として preopen する

ステータス: 採択

## 文脈

### 毎晩の `wasm-tests.yml` で、golem-driver-test が終了コード 126 で落ちる

[ADR 0300](0300-build-the-suites-of-golem-driver-and-golem-pdf-on-wasm32.md) の実装（プルリクエスト [#898](https://github.com/tett23/golem/pull/898)）の後、毎晩の `wasm-tests.yml` が落ちている。
2026-11-10 の実行 42797749874（コミット `022accd5`）では、ジョブの出力に次の二行があった。

```
A2 golem-driver-test: the tests not in test-failures.tsv exited 126
golem-driver-test	0	126	0	0	0
```

この実行の成果物 `wasm-tests-wasm` の `wasm/golem-driver-test.log` は、次の一行だけであった。

```
scripts/wasm/run-suite.sh: 46: timeout: Argument list too long
```

46 行は、`RUN` のコマンドを起動する行である（[`run-suite.sh#L43-L50`](https://github.com/tett23/golem/blob/db145a81a219741ca75d9774637398816694e693/scripts/wasm/run-suite.sh#L43-L50)）。
ジョブは `RUN` を `timeout -k 10 1800 node --no-warnings scripts/wasm/run-tests.mjs` とする（[`wasm-tests.yml#L238-L262`](https://github.com/tett23/golem/blob/db145a81a219741ca75d9774637398816694e693/.github/workflows/wasm-tests.yml#L238-L262)）。
スイートは一度も起動していない。

### 一覧のテストを除く `-p` の式が、引数一つの上限を超えた

`run-suite.sh` は、wasm32 で落ちることがわかっているテストの一覧 `scripts/wasm/test-failures.tsv`（以下、一覧）にあるそのスイートのテストの名前をすべて `||` でつなぎ、`-p "!(…)"` の一つの引数にして渡す（[`run-suite.sh#L54-L66`](https://github.com/tett23/golem/blob/db145a81a219741ca75d9774637398816694e693/scripts/wasm/run-suite.sh#L54-L66)）。
コミット `022accd5` の一覧には、golem-driver-test の行が 1,154 あった（`git show 022accd5:scripts/wasm/test-failures.tsv | awk -F'\t' 'NR>1 && $1=="golem-driver-test"' | wc -l`）。
`main`（`db145a81`）では 1,156 行で、`run-suite.sh` と同じ組み立てで作った引数は 183,062 バイトである。
Linux は、`execve` の引数の一つの文字列を `MAX_ARG_STRLEN`（4 KiB のページで 131,072 バイト）までに限る。
この上限の値は Linux のソースによるもので、手元（macOS）では確かめていない。

ほかのスイートの式は、どれも上限より短い。
最も長いのは golem-emet-test の 218 行で、26,906 バイトである。

### 一覧の 1,184 行は、`/tmp` がないことだけが理由である

`test-failures.tsv` の 1,428 行を、理由の列で数えると次のとおりである（`awk -F'\t' 'NR>1{print $3}' scripts/wasm/test-failures.tsv | sort | uniq -c`）。

| 理由 | 行 |
| --- | --- |
| `withSystemTempDirectory` が `/tmp` の下にディレクトリを作り、そこが preopen にない | 1,184 |
| watchdog のスレッドを起動できない（wasm32-wasi にスレッドがない） | 224 |
| `PATH` がなく、`findExecutable` が例外を投げる（qpdf、pdftoppm、pdfinfo） | 10 |
| `PATH` がなく、`needsTool` の `findExecutable` が例外を投げる（cddl） | 7 |
| `sh scripts/visual/build.sh --list` のプロセスを起動できず、`/tmp` もない | 2 |
| node:wasi で CPU の時間の上限 60 秒を超える | 1 |

`/tmp` だけが理由の 1,184 行のうち、1,150 行が golem-driver-test、30 行が golem-project-test、2 行が golem-driver-global-test、2 行が golem-epub-test である。
golem-driver-test のほかの 6 行は、`PATH` の 4 行と、プロセスと `/tmp` の 2 行である。

テストは、`temporary` 1.3 の `withSystemTempDirectory` で一時のディレクトリを作る。
`withSystemTempDirectory` は、`getTemporaryDirectory` を `canonicalizePath` した下にディレクトリを作る。
`getTemporaryDirectory` は、`TMPDIR` がなければ `/tmp` を返す（手元の GHC 9.14.1 の directory 1.3.10.0 で、`env -u TMPDIR ghc -e 'System.Directory.getTemporaryDirectory >>= print'` が `"/tmp"` を返した）。
`run-tests.mjs` は `TMPDIR` を渡さず、リポジトリの根だけを `/` に preopen する（[`run-tests.mjs#L25-L35`](https://github.com/tett23/golem/blob/db145a81a219741ca75d9774637398816694e693/scripts/wasm/run-tests.mjs#L25-L35)）。
そのため `/tmp` はリポジトリの根の `tmp` を指し、そのディレクトリはない。

### tett23 の決定

2026-11-10 に tett23 は、選択肢のうち (b) を選び、次のとおり指示した。

> 4 (b)でADR作成

(b) は、一時のディレクトリを `/tmp` として preopen し、テストそのものを通す案である。
`/tmp` だけが理由の 1,184 行が一覧から外れ、golem-driver-test の式は上限の下に戻る。

### テストを走らせるホストは node:wasi だけである

wasm32 のテストのスイートを走らせるのは、`run-tests.mjs`（Node の `node:wasi`）だけである。
`wasm-tests.yml` の `RUN` も、`run-suite.sh` の既定も、`run-tests.mjs` である。
wasmtime の C API のホスト `run-wasmtime.c` は、`golem.wasm` の `golem_build_pdf` を呼ぶもので、テストのスイートを走らせない（[`run-wasmtime.c#L1-L27`](https://github.com/tett23/golem/blob/db145a81a219741ca75d9774637398816694e693/scripts/wasm/run-wasmtime.c#L1-L27)）。
`run-wasmtime.c` は preopen を一つも持たず、`golem.wasm` も preopen を要らない。
[ADR 0293](0293-run-the-test-suites-of-the-packages-of-golem-wasm-on-wasm32-every-night.md) の「実装しないこと」も、wasmtime でテストを走らせることを外している。
したがって、この ADR が変えるホストは `run-tests.mjs` だけである。

### node:wasi は、`/` と `/tmp` の二つの preopen で、`/tmp` の下を後者に解決する

手元の Node v26.11.1 で、Rust の `wasm32-wasip1`（wasi-libc を使う）で組んだ小さなプログラムを走らせて確かめた。
プログラムは `/tmp/golem-probe` を作り、その下にファイルを書く。

- preopen が `{ '/': root }` だけのとき、`/tmp/golem-probe` の作成は `NotFound`（errno 44）で落ちた。
- preopen を `{ '/': root, '/tmp': t }`（`t` は `mkdtempSync` で作ったディレクトリ）にすると、作成と書き込みが通り、`t` の下に `golem-probe/f` ができた。根の下に `tmp` はできなかった。
- preopen の順を `{ '/tmp': t, '/': root }` に入れ替えても、結果は同じであった。

wasi-libc は、パスに最も長く一致する preopen を選ぶとされる。
wasi-libc のソースは読んでいないが、順を入れ替えても結果が同じであったことは、これと合う。
GHC の wasm32 のバックエンドも wasi-libc を使うので、テストのスイートでも同じに解決される見込みである。
GHC で組んだスイートでの確かめは、手元に wasm のツールチェーンがないので、していない。

## 実装すること

### 1. `run-tests.mjs` が、走らせるごとの一時のディレクトリを `/tmp` に preopen する

`run-tests.mjs` は、スイートを走らせる前に、ホストの一時のディレクトリ（Node の `os.tmpdir()`）の下に `mkdtempSync` で新しいディレクトリを作る。
そのディレクトリを、リポジトリの根の `/` に加えて、`/tmp` に preopen する。
環境の変数は変えず、`TMPDIR` も渡さない。
スイートの中の `getTemporaryDirectory` は、今のまま `/tmp` を返す。

### 2. 走らせた後に、一時のディレクトリを消す

`run-tests.mjs` は、`wasi.start` が返ったときも、例外を投げたとき（trap など）も、作ったディレクトリを中身ごと消す。
終了コードは、今のとおりスイートの終了コードとする。
trap のときは、今のとおり Node が例外を出して 0 でない終了コードで終わる。

### 3. `test-failures.tsv` から、`/tmp` だけが理由の行を外す

理由が「`withSystemTempDirectory` が `/tmp` の下にディレクトリを作り、そこが preopen にない」の 1,184 行を外す。
`build.sh --list` のプロセスと `/tmp` の 2 行は、プロセスを起動できないことが残るので、理由から `/tmp` の部分を除いて残す。
外したテストのうち、ほかの理由で落ちるものは、[ADR 0293](0293-run-the-test-suites-of-the-packages-of-golem-wasm-on-wasm32-every-night.md) の 4 のとおり、本当の理由と扱いを書いて一覧に戻す。
実装のプルリクエストでは、`workflow_dispatch` で `wasm-tests.yml` を走らせ、その結果で一覧を決める。

### 4. `run-suite.sh` が、式の長さの上限を自分で確かめる

`run-suite.sh` は、`-p` に渡す引数（`!(…)` の全体）のバイト数が 65,536 を超えたら、そのスイートを一度も起動しない。
一覧のテストを一つずつ走らせる確かめ（[ADR 0293](0293-run-the-test-suites-of-the-packages-of-golem-wasm-on-wasm32-every-night.md) の A3）も行わない。
そのときは、`A2 <スイート>: the pattern of <バイト数> bytes is over 65536` を標準エラーに出し、そのスイートを落とす（終了コード 1）。
65,536 は、Linux の 131,072 の半分である。
半分にするのは、ページの大きさの違う環境や、終わりの NUL を数えるかどうかに依らずに、上限の下に収めるためである。
上限を超えたときに、今の `Argument list too long` と終了コード 126 ではなく、スイートの名前と長さで知らせるための検査である。

### 5. 文書

- 仕様書の wasm の節の「リポジトリの根を `/` に preopen し」の段落に、`/tmp` の preopen と、走らせるごとに作って消すことと、4 の上限を書く。
- `run-tests.mjs` の先頭の説明と、`Golem.TestSupport.PackageDirectory` の説明の preopen の記述を、二つの preopen に直す。
- この ADR の実装がマージされ、毎晩の `wasm-tests.yml` が通ったら、[ADR 0293](0293-run-the-test-suites-of-the-packages-of-golem-wasm-on-wasm32-every-night.md) のステータスを「採択→3 の preopen は ADR 0307」とし、この ADR のステータスを「採択」とする。それまで、[ADR 0293](0293-run-the-test-suites-of-the-packages-of-golem-wasm-on-wasm32-every-night.md) は「採択（未実装）」のままとする。

## 実装しないこと

- `PATH` を渡すこと。`PATH` が理由の 17 行（`findExecutable` の 10 行、cddl の `needsTool` の 7 行）は、tett23 の決定の範囲の外であり、別に決める。
- wasm32 でプロセスやスレッドを使えるようにすること。watchdog のスレッドの 224 行と、プロセスの 2 行は残る。
- `run-wasmtime.c` とブラウザーのホストに preopen を足すこと。どちらもテストのスイートを走らせない。
- `-p` の式を、環境の変数やファイルで渡すこと。環境の変数の一つの文字列も `MAX_ARG_STRLEN` に限られる。ファイルで渡す案は `run-tests.mjs` の引数の取り決めを変えるので、4 の上限に当たったときに別の ADR で決める（「トレードオフ」）。
- 外部から止められたとき（`timeout` の `SIGTERM` や `SIGKILL`）に一時のディレクトリを消すこと。`wasi.start` は同期に走るので、そのあいだ Node の JavaScript のシグナルの処理は動かない。

## 不変条件

`run-tests.mjs` の一回の実行を r、r が作るホストの一時のディレクトリを D(r) とする。
`run-suite.sh` があるスイートに `-p` で渡す引数のバイト数を L とする。

- **P1 `/tmp` は D(r)**：r のスイートから見える `/tmp` は D(r) であり、スイートが始まるとき空である。
- **P2 実行ごとに別**：r ≠ r′ なら D(r) ≠ D(r′) である。
- **P3 後に残らない**：r が `wasi.start` から返るか、`wasi.start` が例外を投げて終わったら、D(r) はない。
- **P4 終了コードは変わらない**：r の終了コードは、スイートが `proc_exit` に渡した値である。
- **P5 長すぎる式はスイートを起動しない**：L > 65,536 なら、`run-suite.sh` はそのスイートを起動せず、スイートの名前と L を標準エラーに出して 1 で終わる。L ≤ 65,536 なら、今のとおりスイートを起動する。
- **P6 一覧に `/tmp` だけの理由はない**：`test-failures.tsv` の理由の列に、`/tmp` の preopen がないことだけを理由とする行はない。

境界の入力：

| 入力 | 期待 |
| --- | --- |
| スイートが `proc_exit(0)` で終わる | 終了コード 0、D(r) はない（P3、P4） |
| スイートが `proc_exit(7)` で終わる | 終了コード 7、D(r) はない（P3、P4） |
| スイートが trap で終わる | 0 でない終了コード、D(r) はない（P3） |
| `run-tests.mjs` を二回続けて走らせる | 二つの D(r) は別で、どちらも残らない（P2、P3） |
| 一覧にそのスイートの行がない | `-p` を渡さずに起動する（P5） |
| L がちょうど 65,536 | 起動する（P5） |
| L が 65,537 | 起動せず、1 で終わる（P5） |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
テストの名前には、P1 から P6 の番号を入れる。

- **P2、P3、P4**：`scripts/ci/test.sh` に足す。`wasi_snapshot_preview1` の `proc_exit` だけを読み込み、`_start` で決まった値を渡す最小のモジュール（96 バイト）と、`_start` が `unreachable` のモジュールを、テストの中で書き出す。`TMPDIR` を空のディレクトリにして `run-tests.mjs` を走らせ、終了コードと、走らせた後に `TMPDIR` の下が空であることを確かめる。P2 は、テストの中で `mkdtempSync` が返した道を記録し、二回の実行で道が異なることも確かめる。手書きの 96 バイトのモジュールが Node v26.11.1 の `node:wasi` で `proc_exit(7)` の 7 を返すことは、この ADR を書くときに確かめた。
- **P5**：`scripts/ci/test.sh` の `run-suite.sh` のテスト（偽の `RUN` と `FAILURES` で走らせるもの）に、式が 65,536 バイトと 65,537 バイトになる偽の一覧を足す。前者で偽の `RUN` が呼ばれ、後者で呼ばれずに 1 で終わり、標準エラーにスイートの名前があることを確かめる。
- **P6**：`scripts/ci/test.sh` で、`test-failures.tsv` の理由の列に「which is not in the preopened root of the repository」で終わる理由がないことを確かめる。
- **P1**：毎晩の `wasm-tests.yml` が確かめる。一覧を見直した後、一覧にないテストが [ADR 0293](0293-run-the-test-suites-of-the-packages-of-golem-wasm-on-wasm32-every-night.md) の A2 を満たし、`/tmp` の preopen がないことだけを理由に落ちるテストがないことを確かめる。実装のプルリクエストでは `workflow_dispatch` の実行で確かめ、その実行の番号をプルリクエストの説明に書く。

## トレードオフ

`/tmp` の中身は、実行ごとに空から始まる。
ホストの `/tmp` をそのまま preopen する案は、ほかのプロセスのファイルが見え、前の実行が残したものも見えるので、退けた。
リポジトリの根の下のディレクトリを `TMPDIR` で渡す案は、[ADR 0293](0293-run-the-test-suites-of-the-packages-of-golem-wasm-on-wasm32-every-night.md) の「ほかの環境の変数は渡さない」を変え、チェックアウトの中に一時のファイルを残すので、退けた。

ホストの一時のディレクトリの名前は、実行ごとに変わる。
スイートから見えるパスは常に `/tmp` なので、テストの結果は名前に依らない。
`withSystemTempDirectory` は、ネイティブでもランダムな名前のディレクトリを作るので、テストはもともと名前に依らない。

`timeout` に止められた実行は、D(r) を残す。
CI のランナーはジョブごとに捨てられ、止められた実行はジョブを落とすので、残ったディレクトリは次の実行に影響しない。
手元で止めたときは、`os.tmpdir()` の下に `run-tests.mjs` が作ったディレクトリが残る。

4 の上限は、`MAX_ARG_STRLEN` の半分で、今の最も長い式（golem-emet-test の 26,906 バイト）の二倍余りである。
一つのスイートの一覧の行が、四百から五百を超えれば上限に当たる（今の一行あたりの平均は、golem-driver-test で約 158 バイト、golem-emet-test で約 123 バイトである）。
そのときはジョブが名前と長さで落ちるので、一覧を減らすか、式を分けて渡す方法を別の ADR で決める。

## 確かめていないこと

- GHC の wasm32 のバックエンドで組んだスイートで、`canonicalizePath "/tmp"` と `withSystemTempDirectory` が、`/tmp` の preopen の下で通るか。Rust の `wasm32-wasip1` では `/tmp` の下の作成と書き込みが通ったが、`canonicalizePath`（`realpath`）は試していない。実装のプルリクエストの `workflow_dispatch` の実行で確かめる。
- 外した 1,184 のテストが、`/tmp` のほかの理由で落ちないか。落ちたものは 3 のとおり一覧に戻す。
- Linux の `MAX_ARG_STRLEN` の値。手元は macOS で、値は Linux のソースによる。

## 決めたことの記録

2026-11-11 に、tett23 が提案中の Golem [ADR 0306](0306-measure-the-residency-of-forcing-a-table-by-heap-profiles.md) から 0309 について、次のとおり指示した。

> 提案のADRをマージしてサブエージェントで実装

この指示により、この ADR を採択し、実装を別のプルリクエストで進める。

## 参考文献

- [ADR 0293](0293-run-the-test-suites-of-the-packages-of-golem-wasm-on-wasm32-every-night.md)、[ADR 0300](0300-build-the-suites-of-golem-driver-and-golem-pdf-on-wasm32.md)
- [`scripts/wasm/run-tests.mjs`](https://github.com/tett23/golem/blob/db145a81a219741ca75d9774637398816694e693/scripts/wasm/run-tests.mjs)、[`scripts/wasm/run-suite.sh`](https://github.com/tett23/golem/blob/db145a81a219741ca75d9774637398816694e693/scripts/wasm/run-suite.sh)、[`scripts/wasm/test-failures.tsv`](https://github.com/tett23/golem/blob/db145a81a219741ca75d9774637398816694e693/scripts/wasm/test-failures.tsv)、[`scripts/wasm/run-wasmtime.c`](https://github.com/tett23/golem/blob/db145a81a219741ca75d9774637398816694e693/scripts/wasm/run-wasmtime.c)、[`.github/workflows/wasm-tests.yml`](https://github.com/tett23/golem/blob/db145a81a219741ca75d9774637398816694e693/.github/workflows/wasm-tests.yml)
- `wasm-tests.yml` の実行 42797749874 と、その成果物 `wasm-tests-wasm`
- Linux の `include/uapi/linux/binfmts.h` の `MAX_ARG_STRLEN`（`PAGE_SIZE * 32`）
- Node の `node:wasi` の `preopens`、wasi-libc の preopen の選び方（最も長く一致する前置き）
- Hackage の `temporary` 1.3 の `System.IO.Temp`（`withSystemTempDirectory`、`getCanonicalTemporaryDirectory`）
