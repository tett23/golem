# ADR 0303: テストが調べるプロセスを、テスト自身が起動したものに限る

ステータス: 採択（未実装）

## 文脈

### compare.sh の打ち切りのテスト

[ADR 0247](0247-keep-the-values-of-golem-wasm-independent-of-the-width-of-int.md) の 7 は、`scripts/wasm/compare.sh` が終わらない入力を `COMPARE_TIMEOUT` 秒で打ち切り、ホストとその子を止めると決めた。
compare.sh は、ホストを背景で起動し、見張りのサブシェルが一秒ごとに `kill -0` で生きているかを見る。
時間を過ぎると、`stop` が `pgrep -P` でホストの直接の子を探して止め、続けてホストを止める（[compare.sh の 134 行から 162 行](https://github.com/tett23/golem/blob/75c3f807096ed695a53b7d58f0ad97be9ee0bd00/scripts/wasm/compare.sh#L134-L162)）。

`scripts/ci/test.sh` は、この振る舞いを偽のホスト `deno-hangs` で確かめる（[test.sh の 3727 行から 3747 行](https://github.com/tett23/golem/blob/75c3f807096ed695a53b7d58f0ad97be9ee0bd00/scripts/ci/test.sh#L3727-L3747)）。
偽のホストは、入力 `int-width-png-chunk` のときだけ `sleep 300` を動かす。
`COMPARE_TIMEOUT=2` で compare.sh を動かしたあと、テストは子が止まったことを次の一行で確かめる（[3747 行](https://github.com/tett23/golem/blob/75c3f807096ed695a53b7d58f0ad97be9ee0bd00/scripts/ci/test.sh#L3747)）。

```sh
if pgrep -f "sleep 300" >/dev/null 2>&1; then ng "compare.sh: the children of the host stopped are stopped too (I1)"; else ok; fi
```

`pgrep -f` は、マシンのすべてのプロセスのコマンド行から、部分一致で探す。
テストが起動した `sleep` だけを見ているわけではない。

### 二つの向きの誤り

この断言は、二つの向きに誤る。

一つめは、偽の失敗である。
同じマシンで、コマンド行に `sleep 300` を含むプロセスが一つでも動いていれば、テストは失敗する。
`sleep 3000` や、`sleep 300` を引数に持つシェルも一致する。
同じリポジトリの別の worktree で `scripts/ci/test.sh` が同時に走れば、片方の偽のホストの `sleep 300` が、もう片方の断言に一致する。
エージェントが手元で test.sh を動かしたときに失敗したのは、この形である。

二つめは、偽の合格である。
`pgrep` がプロセスの一覧を読めない環境では、`pgrep` は失敗の終了コードで終わる。
断言は終了コードが 0 でなければ `ok` とするので、何も調べずに合格する。
Claude Code のサンドボックスの中では、`pgrep` は `Cannot get process list` を出して終わる。
同じ環境では compare.sh の `stop` も `pgrep -P` で子を見つけられず、`sleep` は止まらずに残る。
compare.sh が [ADR 0247](0247-keep-the-values-of-golem-wasm-independent-of-the-width-of-int.md) の I1 を満たしていないのに、テストは合格する。
[ADR 0077](0077-shell-test-assertions-that-pass-vacuously.md) が直した、検査の対象が壊れても通る断言と同じ種類である。

### 確かめたこと

2026-11-10 に、macOS の手元で次を確かめた。

- サンドボックスの外で、背景に `sleep 300` を一つ動かしてから同じ `pgrep -f "sleep 300"` を評価すると、一致した（テストなら `ng`）。
- サンドボックスの中で、`stop` と同じ関数でホストを止めると、ホストの子の `sleep 300` は残った（子が自分の PID をファイルに書き、`kill -0` で確かめた）。同じ状態で `pgrep -f "sleep 300"` の断言は `ok` だった。
- `kill -0` は、サンドボックスの中でも、自分が起動したプロセスの生死を正しく返した。

### ほかのテストの調べ

`origin/main`（75c3f807096ed695a53b7d58f0ad97be9ee0bd00）のテストのスクリプトを、マシン全体の状態に依る検査を探して調べた。
探したのは、`pgrep`、`pkill`、`killall`、`ps` によるプロセスの検索、決まったポート、決まった `/tmp` の道、テストが設定しない環境変数やホームの設定の読み込み、時刻である。
対象は、`scripts/**/test*.sh`、`scripts/ci/test-suites.sh`、`tools/editors/**/test.sh`、`scripts/browser/test/*.mjs` と、各パッケージの Haskell のテストである。

| テスト | 見つけたもの | 扱い |
| --- | --- | --- |
| [scripts/ci/test.sh の 3747 行](https://github.com/tett23/golem/blob/75c3f807096ed695a53b7d58f0ad97be9ee0bd00/scripts/ci/test.sh#L3747) | `pgrep -f "sleep 300"` | この ADR で直す |
| [scripts/ci/test.sh の 3746 行](https://github.com/tett23/golem/blob/75c3f807096ed695a53b7d58f0ad97be9ee0bd00/scripts/ci/test.sh#L3746) | 打ち切りまでの経過を `date +%s` で測り、60 秒未満を求める | 対象外。ほかのプロセスが何かではなく、マシンの負荷に依る。打ち切りは 2 秒と 10 秒の猶予で、60 秒との差は大きい |
| [scripts/ci/test.sh の 6 行と 7 行](https://github.com/tett23/golem/blob/75c3f807096ed695a53b7d58f0ad97be9ee0bd00/scripts/ci/test.sh#L6-L7) ほか、すべての `test.sh` | 作業の場所は `mktemp -d` | 問題なし。同時に動かしても重ならない |
| [scripts/ci/test.sh の 1033 行](https://github.com/tett23/golem/blob/75c3f807096ed695a53b7d58f0ad97be9ee0bd00/scripts/ci/test.sh#L1033) | `bg.sh` の既定の置き場所 `/tmp/bg` | 問題なし。テストは `BG_DIR` を作業の場所に向ける |
| [scripts/ci/test.sh の 67 行から 75 行](https://github.com/tett23/golem/blob/75c3f807096ed695a53b7d58f0ad97be9ee0bd00/scripts/ci/test.sh#L67-L75)、scripts/visual/test.sh、scripts/manual/test.sh | テストのリポジトリは利用者の git の設定を読む | 署名は [ADR 0077](0077-shell-test-assertions-that-pass-vacuously.md) が直した。ほかの設定はこの ADR の対象外 |
| [tools/editors/nvim/test.sh の 31 行から 33 行](https://github.com/tett23/golem/blob/75c3f807096ed695a53b7d58f0ad97be9ee0bd00/tools/editors/nvim/test.sh#L31-L33) | `--theme` は利用者の Neovim の設定を読む | 対象外。手で動かす見た目の確認で、設定を読むことが目的である。既定の動かし方は `--clean` |
| tools/editors/helix/test.sh | `HOME` を作業の場所に向ける | 問題なし |
| scripts/browser/test/unit.test.mjs | サーバーは `listen(0, '127.0.0.1')` で空いたポートを取る。`41234` と `127.0.0.1:1` は、読み取りの入力と偽のサーバーへ送る値である | 問題なし |
| Haskell のテスト | `/tmp/` は入力の文字列としてだけ現れる | 問題なし |

プロセスを名前で探すテストは、この一か所だけだった。
一方で、テストではないスクリプトには、自分で起動した PID だけを `kill -0` で見る形がすでにある（[scripts/models/check.sh の 153 行から 166 行](https://github.com/tett23/golem/blob/75c3f807096ed695a53b7d58f0ad97be9ee0bd00/scripts/models/check.sh#L153-L166)、compare.sh の見張り）。

### プロセスグループで止める案

子と孫をまとめて止めるには、ホストを別のプロセスグループで起動し、グループに送る方法がある。
POSIX の sh では、`set -m` でジョブ制御を有効にすると、背景のジョブが別のグループになる。
2026-11-10 に確かめると、macOS の `/bin/sh` では `kill -TERM -- -<PID>` で子まで止まった。
Debian 系の `/bin/sh` である dash は、端末のないところで `set: can't access tty; job control turned off` を出し、グループを分けなかった。
グループへの `kill` は失敗し、ホストは止まらずに残った。
CI の Ubuntu の runner には端末がないので、この案は使えない。

## 実装すること

### 1. 規則

テストがプロセスの状態を調べるときは、そのテストが起動したプロセスか、そのテストが起動したプロセスが PID を書いたプロセスだけを、PID で調べる。
名前やコマンド行で、マシンのプロセスを探さない。
PID を書く先は、そのテストの作業の場所（`mktemp -d` で作ったディレクトリ）の中とする。

### 2. compare.sh の打ち切りのテスト

`scripts/ci/test.sh` の偽のホスト `deno-hangs` を、`sleep 300` を背景で起動してその PID を作業の場所のファイルに書き、`sleep` を待つ形に変える。

```sh
case "$7" in
  */int-width-png-chunk) sleep 300 & echo "$!" >"$HANG_PID"; wait "$!" ;;
esac
```

`HANG_PID` は `$CB/hang.pid` で、compare.sh を動かす `env` で渡す。
`sleep` はホストの直接の子のままなので、compare.sh の `stop` が探す子の範囲は今と変わらない。

compare.sh が終わったあとの断言は、次のとおりとする。

- `$CB/hang.pid` がないか空なら、`ng` とする。偽のホストが入力にたどり着かなかったか、PID を書けなかったので、何も調べていない（[ADR 0077](0077-shell-test-assertions-that-pass-vacuously.md)）。
- 書かれた PID に `kill -0` が成功すれば、子が残っているので `ng` とする。
- 断言のあと、PID が生きていれば `kill` で止める。テストの `trap` も、`hang.pid` があれば同じことをする。失敗したテストが `sleep` を残さないためである。

### 3. 子を一覧できない環境

compare.sh の `stop` は `pgrep -P` に依る。
`pgrep` がプロセスの一覧を読めない環境では、2 の断言は正しく失敗する（compare.sh が子を止めていないため）。
この失敗はテストの不安定さではなく、その環境での compare.sh の限界である。
テストは、compare.sh を動かす前に、自分で起動した子を `pgrep -P $$` で見つけられるかを試す。
見つけられなければ、打ち切りの子についての断言を `skip` とし、`SKIP compare.sh: the children of the host (pgrep cannot list processes)` を出す。
打ち切りの終了コードと一覧の行の断言は、今のまま動かす。

### 4. 静的な検査

`scripts/ci/test.sh` に、テストのスクリプトがプロセスを名前で探していないことの検査を足す。
対象は、`git ls-files` が返す `scripts/**/test*.sh`、`scripts/ci/test-suites.sh`、`tools/editors/**/test.sh` である。
`-P` を伴わない `pgrep`、`pkill`、`killall` の語と、`ps` の `-e`、`-A`、`ax`、`aux` を含む行を探し、一つでもあれば `ファイル:行` を出して `ng` とする。
`pgrep -P` は、親の PID で範囲を絞り、テストが起動したプロセスの子だけを返すので許す（3 の試しに使う）。
調べたファイルの数が 0 なら `ng` とする（[ADR 0077](0077-shell-test-assertions-that-pass-vacuously.md)）。
テストではない compare.sh の `pgrep -P` は、対象に入らない。

検査の自身のテストとして、`scripts/ci/testdata/process-checks/` に `pgrep -f` を含む偽のテストと含まない偽のテストを置き、前者で失敗し、後者で通ることを確かめる。
検査は POSIX の sh と、macOS の BSD の `grep` で動く形で書く。

## 実装しないこと

- compare.sh の `stop` を変えない。孫を止めないことと、`pgrep` に依ることは、テストの隔離とは別の問題である。プロセスグループの案は、文脈のとおり dash で動かない。
- 経過時間の断言（3746 行）は変えない。
- テストのリポジトリが利用者の git の設定を読むことは、この ADR では扱わない。
- `tools/editors/nvim/test.sh --theme` は変えない。
- Haskell のテストに静的な検査を足さない。名前でプロセスを探すものはない。

## 不変条件

- **I1 起動したものだけを調べる**：テストが状態を調べるプロセスは、そのテストが起動したプロセスか、そのテストが起動したプロセスがテストの作業の場所に PID を書いたプロセスに限る。
- **I2 ほかのプロセスに依らない**：同じマシンで動くほかのプロセス（同じコマンド行のものを含む）があってもなくても、テストの結果は同じである。
- **I3 同時に動かせる**：同じテストのスクリプトを同時に二つ動かしたとき、それぞれの合格と失敗の数は、一つだけ動かしたときと同じである。
- **I4 空振りしない**：調べる PID が得られなかったとき、断言は `ok` にならない。
- **I5 壊れた止め方を見逃さない**：compare.sh の `stop` が子を止めないように変えると、打ち切りの子の断言は `ng` になる（子を一覧できる環境で）。
- **I6 一覧できない環境では SKIP**：`pgrep -P` が自分の子を見つけられない環境では、打ち切りの子の断言は `ok` にも `ng` にもならず、`SKIP` の行を出す。
- **I7 残さない**：テストが終わったとき、合格でも失敗でも、テストが起動した `sleep` は残っていない。
- **I8 名前で探さない**：4 の対象のファイルに、`-P` を伴わない `pgrep`、`pkill`、`killall` と、全プロセスを並べる `ps` が現れない。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| ほかのプロセス | なし、`sleep 300` が一つ、`sleep 3000` が一つ、同じ `test.sh` がもう一つ同時に |
| `pgrep` | プロセスを一覧できる、一覧できない（Claude Code のサンドボックス） |
| compare.sh の `stop` | 子を止める（今のまま）、子を止めない（`pgrep -P` の行を消した変異） |
| `hang.pid` | 書かれる、書かれない（偽のホストが入力にたどり着かない変異） |
| 静的な検査の対象 | 0 ファイル、`pgrep -f` を含むファイルが一つ、含まないファイルだけ |

## テスト設計

- **偽の失敗の再現（I2）**：実装の前に、背景で `sleep 300` を動かしてから `sh scripts/ci/test.sh` を動かし、3747 行の断言が `FAIL` になることを確かめる。実装の後に同じことをして、`FAIL` が出ないことを確かめる。`sleep 3000` でも同じ。これは手で動かし、プルリクエストに結果を書く。
- **同時の実行（I3、I7）**：実装の後に、`scripts/ci/test.sh` を背景で二つ同時に動かし、二つの終了コードと合格の数が、一つだけ動かしたときと同じであることを確かめる。終わったあとに、二つの `hang.pid` の PID がどちらも `kill -0` で失敗することも確かめる。手で動かし、プルリクエストに結果を書く。
- **変異（I4、I5）**：`stop` から `pgrep -P` の行を消した compare.sh で、打ち切りの子の断言が `FAIL` になることを確かめる。偽のホストが PID を書かないように変えて、同じ断言が `FAIL` になることも確かめる。手で動かし、プルリクエストに結果を書く。
- **一覧できない環境（I6）**：Claude Code のサンドボックスの中で `scripts/ci/test.sh` を動かし、`SKIP compare.sh: the children of the host` の行が出て、`FAIL` が出ないことを確かめる。
- **静的な検査（I8）**：`scripts/ci/test.sh` に、`scripts/ci/testdata/process-checks/` の二つの偽のテストに対する検査の結果と、対象が 0 ファイルのときの失敗の断言を書く。名前に `I8` を入れる。CI の `scripts-linux` と `scripts-macos` のジョブで動く。

## トレードオフ

- PID で調べると、子が止まってから `kill -0` までのあいだに、同じ PID が別のプロセスに使われれば偽の失敗になる。macOS と Linux は既定で PID を増やしながら割り当て、このあいだは数ミリ秒なので、起きる見込みは小さい。`ps -p` でコマンド行も確かめれば防げるが、サンドボックスでは `ps` がプロセスを読めない場合があり（未確認）、断言が環境に依るものに戻る。
- コマンド行に作業の場所の道（一意の印）を入れて `pgrep -f` で探す案は、I2 と I3 を満たす。しかし `pgrep` が一覧を読めない環境では今と同じく空振りし、I4 を満たさない。
- 3 の SKIP によって、サンドボックスの中では打ち切りの子の断言が働かない。CI はサンドボックスの外で動くので、CI では働く。
- 静的な検査は、名前で探す書き方を禁じるだけで、ほかのマシン全体の状態（ポート、時刻）は見ない。今のテストにそれらの問題はなく、検査の語を増やすと誤検出が増える。

## メンテナーが決めること

1. **PID の確かめ方**：`kill -0` だけで確かめる案と、`ps -p` でコマンド行も確かめる案がある。推奨は `kill -0` だけである。PID が再利用されるあいだは短く、`ps` を足すと断言がまた環境に依る。
2. **一覧できない環境の扱い**：`SKIP` とする案（3）と、`FAIL` のままにする案がある。推奨は `SKIP` である。`FAIL` は事実だが、compare.sh の限界をテストの失敗として毎回出すと、ほかの失敗が埋もれる。`timeout` のない macOS の `suite-timeout` のテストと同じ扱いになる。
3. **静的な検査を足すか**：推奨は足すことである。名前で探す書き方は短く書けて、レビューで見落としやすい。
4. **compare.sh の `stop` を直す ADR を別に書くか**：孫を止めないことと、`pgrep` に依ることは残る。偽のホストと node、deno のホストでは、止めるプロセスはホスト自身か直接の子である。`--browser` のホスト（`run-browser.mjs`）はブラウザーを起動するので、孫ができる可能性がある。この ADR では確かめていない。推奨は、`--browser` で打ち切ったあとに残るプロセスを確かめ、残るなら別の ADR を書くことである。

## 決めたことの記録

2026-11-10 に、tett23 がこの ADR の判断のすべてを推奨のとおりに決めた。

1. **PID の確かめ方**：`kill -0` だけで確かめる。
   - `ps -p` でコマンド行も確かめる案は、退けた。PID が再利用されるあいだは短く、`ps` を足すと断言がまた環境に依る。
2. **一覧できない環境の扱い**：`SKIP` とする（実装すること 3）。
   - `FAIL` のままにする案は、退けた。compare.sh の限界をテストの失敗として毎回出すと、ほかの失敗が埋もれる。
3. **静的な検査**：足す（実装すること 4）。
4. **compare.sh の `stop` を直す ADR**：この ADR を実装したあとに、打ち切りのあとに残るプロセスを wasmtime のホストと `--browser` のホストで確かめる。孫が残るなら、別の ADR を書く。

## 参考文献

- [ADR 0077](0077-shell-test-assertions-that-pass-vacuously.md)、[ADR 0247](0247-keep-the-values-of-golem-wasm-independent-of-the-width-of-int.md)
- IEEE Std 1003.1-2017（POSIX）、Shell Command Language の `set -m` と `kill`。https://pubs.opengroup.org/onlinepubs/9699919799/
- macOS の `pgrep(1)`、`kill(1)` のマニュアル
