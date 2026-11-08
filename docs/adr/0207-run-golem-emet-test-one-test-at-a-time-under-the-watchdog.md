# ADR 0207: aarch64 の GHC の不具合が直るまで、golem-emet-test を一つずつ走らせ、見張りを付ける

ステータス: 採択（未実装）

## 文脈

### 2 時間止まったスイート

2026-11-07 の 14:02（UTC）に、[ADR 0180](0180-verse-spacing-and-stanza-breaks.md) を実装した worktree（コミット 520d8270）で、Claude Code のサンドボックスの中から `cabal test all` を走らせた。
出力は通常のファイルに向けていた。
このコマンドは 2 時間、何も出力しなかったので、16:02 に止めた。

最後まで終わらなかったのは golem-emet-test だけである。
golem-emet-test が出力したのは、群の見出しと最初のテスト（[LanguageSpec.hs](https://github.com/tett23/golem/blob/7a6b50607d15f10b8124a8f01a2957bb9cd5522a/modules/golem-emet/test/LanguageSpec.hs#L82-L87) の「cidSystemInfo of the ADR is read and evaluated」）の結果の `OK (0.37s)` までで、二つめのテストの名前は出ていない。
単独で走らせると、同じスイートは 207 のテストを 24〜34 秒で通す。

同じ実行では、golem-text-test、golem-typeset-test、golem-test-support-test も始まらなかった。
これは止まりとは別の事情である。
サンドボックスがソケットの bind を禁じるので golem-plugin-test が落ち、その後、cabal は残りのスイートを始めなかった。
2026-11-08 に同じ worktree で `cabal test all` を三回走らせ直すと、三回とも golem-plugin-test が落ち、同じ三つのスイートが始まらずに、コマンドは 72〜121 秒で終わった。
三回とも golem-emet-test は通った。

### 出力から言えること

スイートごとのログ（`dist-newstyle/.../golem-emet-0.1.0-golem-emet-test.log`）には cabal の 3 行しかなく、テストの出力は共通のログに、ほかのスイートの出力と行の途中で混ざって入っている。
テストは、cabal から受け継いだ標準出力（ここではファイル）に直に書いていたと見られる。
ファイルへの書き込みは読み手を待たないので、出力が詰まって止まった、という説明は成り立たない。

tasty 1.5.4 のコンソールの報告は、テストの結果を待つ前に、テストの名前を書いて `hFlush` する（`Test/Tasty/Ingredients/ConsoleReporter.hs` の `printTestName`）。
二つめのテストの名前が出ていないので、報告のスレッドは、一つめの結果を書いた後、2 時間のあいだ動かなかったことになる。
一つのテストが遅いだけなら、二つめの名前は出ているはずである。
プロセスの中の Haskell のスレッドが、すべて止まっていた可能性が高い。

### macOS での再現

最初のテストの群（「newlines as separators」の 17 のテスト、単独で約 0.1 秒）だけを、別々のプロセスで何千回も走らせると、止まりが再現した。
8 つのプロセスを並べ、1 回ずつ 20 秒で打ち切る。

```sh
cd modules/golem-emet
B=$(cabal list-bin golem-emet:test:golem-emet-test)
for w in 1 2 3 4 5 6 7 8; do
  (for i in $(seq 1 500); do
     "$B" -p '/newlines as separators/' >"$TMPDIR/w$w.out" 2>&1 & pid=$!
     t=0; while kill -0 $pid 2>/dev/null; do
       sleep 0.1; t=$((t+1))
       if [ $t -gt 200 ]; then echo "w$w run$i stuck"; kill -9 $pid; break; fi
     done
     wait $pid; rc=$?; [ $rc -ne 0 ] && [ $rc -ne 137 ] && echo "w$w run$i rc=$rc"
   done) &
done; wait
```

止まったプロセスは、どれもその実行の最初のテストの名前を出したところで止まっていた。
`ps` で調べた四つは CPU を使っておらず、累計の CPU 時間は 0.08〜0.09 秒だった。
止まるのとは別に、まれにプロセスが SIGSEGV で落ちる。

tasty を使わない小さなプログラムでも落ちる。
16 の Haskell のスレッドを `forkIO` で立て、それぞれに短い .emet のソースを `formatEmet` させて、結果を `MVar` で待つだけのプログラムである（以下「同時整形のプログラム」）。
こちらは落ちるだけで、止まらなかった。

10 コアの macOS（Apple Silicon、GHC 9.10.3、tasty 1.5.4）で、2026-11-08 に次の結果を得た。
試したのはすべてサンドボックスの中である。
「止まった」は 20 秒で終わらなかった回、「落ちた」は SIGSEGV で終わった回である。

| 走らせたもの | 回数 | 止まった | 落ちた |
|---|---|---|---|
| golem-emet-test、「newlines as separators」（そのまま） | 6,000 | 9 | 1 |
| 同じ、最初のテストを除く 16 | 4,000 | 3 | 1 |
| 同じ、最初のテストだけ | 4,000 | 0 | 0 |
| 同じ、fmt の 7 つのテスト（構文解析と整形だけ） | 4,000 | 0 | 5 |
| 同じ群、tasty の `-j1` | 10,000 | 0 | 0 |
| 同じ群、`-j1`、`+RTS -N1` | 2,000 | 0 | 0 |
| テストのソースの写し（そのまま） | 8,000 | 26 | 1 |
| 同じ写しに `localOption (NumThreads 1)` を足したもの | 8,000 | 0 | 0 |
| 同じ写しを `-threaded` を付けずにリンクしたもの | 8,000 | 0 | 0 |
| 同じ写しを debug の RTS でリンクしたもの | 2,400 | 8 | 0 |
| 同じ、`+RTS -Ds`（スケジューラーのトレース） | 2,400 | 0 | 0 |
| 同時整形のプログラム | 16,000 | 0 | 16 |
| 同じ、`+RTS -qg`（並列の GC を使わない） | 8,000 | 0 | 5 |
| golem-parser-test の群 `parser (ADR 0002-0004)`（golem-parser の ADR）の 93 のテスト | 4,000 | 0 | 0 |

「テストのソースの写し」は、golem-emet-test のテストのソースを写し、別の cabal のプロジェクトで、同じ golem のソースに対してリンクし直したものである。
golem-emet-test では、同じプロセスの中でテストが同時に走らないと、止まりも落ちも起きなかった。

### 止まったプロセスと落ちたプロセス

止まったプロセスのうち三つで、macOS の `sample` を取った。
三つとも、23 の OS スレッドが次の場所にいた。

| スレッド | 数 | いた場所 |
|---|---|---|
| メインスレッド | 1 | `waitCondition`（`__psynch_cvwait`） |
| ghc_ticker | 1 | `waitCondition` |
| ghc_worker | 10 | Haskell のコードから呼んだ `kevent`（capability ごとの IO マネージャー） |
| ghc_worker | 1 | Haskell のコードから呼んだ `poll`（タイマーマネージャー） |
| ghc_worker | 10 | `waitCondition` |

走っているスレッドはない。
これは、[ADR 0117](0117-watchdog-outside-the-runtime-for-threaded-tests.md) が golem-driver-parallel-test について記録した止まり方と同じ形である。
`lldb` はプロセスに付けられず（「could not pause execution」）、GHC のフレームはたどれなかった。

落ちたプロセスのクラッシュレポートは、どれも同じだった。
落ちたスレッドは `schedule` から `stg_ap_ppv_info` に入ったところで、アドレス 0 を読んでいる。
GHC の aarch64 のレジスターの割り当てでは x22 が R1 で、その値が 0 だった。
二つのポインターと状態の引数に適用しようとした関数のクロージャーが、ヌルだったことになる。
golem-emet が使うパーサーの型は `Ctx r s -> Int -> ST s (Res a)` で（[peg-runtime の Internal.hs](https://github.com/tett23/peg-hs/blob/8441ad7f9d77acb6c95e6dce214ad219f03425d2/packages/peg-runtime/src/Peg/Runtime/Internal.hs#L347)）、この形の適用になる。

golem-emet、golem-syntax、golem-eval、golem-doc、peg-runtime のソースには、`unsafePerformIO` も FFI の宣言もない。
範囲を確かめない操作は Text のバイトの読み出しと切り出しだけで、どちらもヒープにポインターを書かない。
安全な Haskell のコードがヒープにヌルのポインターを作ることはないので、golem のコードの誤りではなく、GHC のランタイムかコード生成の不具合である可能性が高い。

### Linux では aarch64 だけで落ちる

macOS に固有の不具合か、aarch64 に固有の不具合かを分けるために、GitHub Actions の ubuntu-24.04（x86-64、4 CPU）と ubuntu-24.04-arm（aarch64、4 CPU）で同じことを走らせた。
GHC 9.10.3、cabal.project.freeze、cabal-install 3.16.1.0 は CI と同じである。
ワークフローは、使い捨てのブランチに置いた一時的なもので、実行の後にブランチを消した（実行 [42400776836](https://github.com/tett23/golem/actions/runs/42400776836)）。

| 走らせたもの | x86-64 | aarch64 |
|---|---|---|
| golem-emet-test、「newlines as separators」 | 6,000 回で 0 | 6,000 回で 0 |
| 同じ、`+RTS -N10` | 4,000 回で 0 | 4,000 回で 0 |
| 同じ、`-j1` | 4,000 回で 0 | 4,000 回で 0 |
| 同時整形のプログラム | 8,000 回で 0 | 8,000 回のうち 13 回落ちた |
| 同じ、`+RTS -N10` | 4,000 回で 0 | 4,000 回のうち 13 回落ちた |

落ちたのは aarch64 だけで、x86-64 では 12,000 回のうち 0 回だった。
一方、Linux の aarch64 では、golem-emet-test は 10,000 回とも止まらなかった。
止まりが macOS だけで起きるのか、Linux では率が低いだけなのかは、わからない。

### 新しい GHC と、ほかの対処の候補

同時整形のプログラムを、新しい GHC と、`-feager-blackholing` を付けたビルドで試した。
GHC は ghcup の公式のビルドで、プロジェクトの GHC は変えていない。
9.12.4 と 9.14.1 は、cabal.project.freeze を外し、`allow-newer: all` でビルドした。

| ビルド | 場所 | 回数 | 落ちた |
|---|---|---|---|
| 9.10.3 | Linux aarch64（[42403505173](https://github.com/tett23/golem/actions/runs/42403505173)） | 16,000 | 12 |
| 9.10.3、golem と peg-runtime に `-feager-blackholing` | 同じ | 16,000 | 32 |
| 9.10.3、すべてのパッケージに `-feager-blackholing` | 同じ | 16,000 | 12 |
| 9.12.4 | Linux aarch64（[42402553462](https://github.com/tett23/golem/actions/runs/42402553462)） | 8,000 | 10 |
| 9.14.1 | 同じ | 8,000 | 13 |
| 9.14.1 | macOS | 8,000 | 6 |
| 9.10.3、golem と peg-runtime に `-feager-blackholing` | macOS | 8,000 | 0 |

9.14.1 で落ちたプロセスのクラッシュレポートも、`schedule` から入った `stg_ap_ppv_info` でアドレス 0 を読む、同じ形だった。
9.14.1 でリンクしたテストのソースの写しも、macOS で 8,000 回のうち 1 回止まった。
試したどの版でも落ちた。

`-feager-blackholing` は、macOS では同時整形のプログラムもテストのソースの写しも 8,000 回のうち 0 回にした。
しかし、Linux の aarch64 では落ちを消さなかった。
オブジェクトファイルが大きくなったことで、フラグが適用されていることは確かめた。
macOS で消えた理由は説明できない。

構文解析の下準備（並べる前に一度だけ構文解析しておく）は、macOS の同時整形のプログラムの落ちを 20,000 回のうち 0 回にしたが、テストのソースの写しの止まりは消さなかった（8,000 回のうち 24 回）。

### GHC の issue

GHC の issue の [#28001](https://gitlab.haskell.org/ghc/ghc/-/issues/28001)（2026-10-20 に開かれ、2026-11-08 の時点で未解決、マイルストーンは 10.2.1）は、同じ症状を aarch64 の macOS について報告している。
tasty で小さなパーサーのテストを並列に走らせると、数百回から千回に一回ほど、`schedule` から入った `stg_ap_*` でヌルのクロージャーを適用して落ちるか、ワーカーのスレッドが `stg_BLACKHOLE_info` で回り続けて止まる。
tasty の `--num-threads=1` では落ちず、`+RTS -qg` では落ち、debug の RTS では再現しない。
報告は 9.12.4 と 9.14.1 で、トップレベルのパーサー（CAF）の更新か blackhole の処理に、aarch64 での順序の保証が欠けていると疑っている。

この ADR の観測は、ほとんどがこの報告と一致する。
違うのは二点である。
この ADR の止まったプロセスは CPU を使っていなかった（報告では回り続ける）。
また、9.10.3 と Linux の aarch64 でも落ちることを確かめた（報告は macOS の 9.12.4 と 9.14.1 だけ）。
issue に付いたコメントは、gitlab.haskell.org が自動のアクセスを拒むため読めていない。
issue の再現のプログラムは、この ADR の作業では走らせていない。

9.14.2 の候補版（9.14.2-rc1）の告知は、blackhole の処理の不具合の修正（#26922、[#26936](https://gitlab.haskell.org/ghc/ghc/-/issues/26936)）と、aarch64 のコード生成の修正（#26978、#26979、#26980、#27046、#27047）を挙げている。
#26922 と #26936 は 9.14.1 で入った退行と報告されており、9.10.3 から続くこの不具合とは別のものと見られる。
aarch64 のコード生成の修正が、この不具合に関わるかどうかはわからない。
ghcup の一覧（2026-11-08）には 9.14.2 がなく、試していない。

### golem のコードを使わない再現

上流に報告できる、golem のコードを使わない再現は作れていない。
次のプログラムを作り、macOS で 4,000〜6,000 回ずつ走らせたが、どれも 0 回だった。

- tasty で 17 の小さなテストを並列に走らせるもの。
- 遅延評価の値を持つトップレベルの `Map` を、17 のテストで同時に評価するもの。
- 互いに呼び合う 400 のトップレベルの `ST` のパーサーを、16 のスレッドで同時に初めて使うもの。
- peg-runtime と同じ形のパックラットパーサー（可変の配列のメモ表、子の木のリスト、トップレベルの規則）を、16 のスレッドで同時に初めて使うもの。規則の中の値を共有の thunk にした版も試した。

今ある最小の再現は、同時整形のプログラム（40 行ほど）だが、golem-emet と、その依存の golem のパッケージ、peg-runtime を要する。

### 本番のコードへの影響

本番の `golem`（`-threaded`、`-with-rtsopts=-N`）では、再現しなかった。
どれも macOS のサンドボックスの中で走らせた。
サンドボックスの外では試していない。

| 走らせたもの | 回数 | 止まった | 落ちた |
|---|---|---|---|
| `golem build`、.emet の関数とフィルターを使う fixture（emet-samples、HTML、EPUB、テキスト）、8 プロセスを並べて | 1,200 | 0 | 0 |
| `golem build`、complex-vertical（.emet の関数、縦組みの PDF、並列の組版）、6 プロセスを並べて | 150 | 0 | 0 |
| `golem lsp`、六つの .emet を開き、semantic tokens の要求を 18 個続けて送る、8 プロセスを並べて | 1,200 | 0 | 0 |

`golem fmt` は、ファイルを一つずつ順に整形するので、同時に評価することがない。
組版の並列（[Flow.hs](https://github.com/tett23/golem/blob/7a6b50607d15f10b8124a8f01a2957bb9cd5522a/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L2345)）が .emet の評価を同時に起こすかどうかは調べていない。
言語サーバーは、semantic tokens の要求ごとにスレッドを立て、.emet の構文木を作る（[Server.hs](https://github.com/tett23/golem/blob/7a6b50607d15f10b8124a8f01a2957bb9cd5522a/modules/golem-lsp/src/Golem/Lsp/Server.hs#L207-L215)）。
同時整形のプログラムと同じく、構文解析が複数のスレッドで同時に走る経路である。
1,200 回で 0 回だったが、同時整形のプログラムの率（0.1% ほど）から見れば、起きないとは言えない。

### 手元の `cabal test` に上限がない

golem-emet-test には時間の上限がない。
CI は `scripts/ci/suite-timeout.sh` でスイートを 600 秒で止めるが、手元の `cabal test` にはこの歯止めがなく、2 時間のあいだ止まりに気づけなかった。
[ADR 0117](0117-watchdog-outside-the-runtime-for-threaded-tests.md) は、ほかの `-threaded` のスイートで止まりを観測したら同じ見張りを当てる、と決めている。

## 実装すること

### テストを一つずつ走らせる

- [golem-emet-test の Main.hs](https://github.com/tett23/golem/blob/7a6b50607d15f10b8124a8f01a2957bb9cd5522a/modules/golem-emet/test/Main.hs#L11-L12) で、木の全体を `localOption (NumThreads 1)` で包む。注釈に、この ADR と GHC の #28001 を書く。
- tasty 1.5.4 は、木のいちばん外側の `localOption` をコマンドラインのオプションに重ねてから、テストを走らせるスレッドの数を決める（`Test/Tasty/Run.hs` の `applyTopLevelPlusTestOptions`）。そのため、テストは一つずつ走る。コマンドラインの `-j` は働かなくなる。
- `-threaded` と `-with-rtsopts=-N` は残す（[golem-emet.cabal](https://github.com/tett23/golem/blob/7a6b50607d15f10b8124a8f01a2957bb9cd5522a/modules/golem-emet/golem-emet.cabal#L54-L73)）。「evaluating in parallel gives what evaluating in sequence gives」（[LanguageSpec.hs](https://github.com/tett23/golem/blob/7a6b50607d15f10b8124a8f01a2957bb9cd5522a/modules/golem-emet/test/LanguageSpec.hs#L520-L533)）は、テストの中で `forkIO` のスレッドを同時に走らせる。この評価が複数のコアで同時に走ることを確かめ続けるためである。
- capability の数はテストのスレッドの数（1）より多いので、tasty は `setNumCapabilities` を呼ばない（`scripts/ci/rts-capabilities.sh` の検査はそのまま通る）。

### 見張りを付ける

- 木の全体を `watchTests 300` で包む（`Golem.TestSupport.Watchdog`、[ADR 0117](0117-watchdog-outside-the-runtime-for-threaded-tests.md)）。`watchTests` は `localOption` を外さずに保つので、包む順はどちらでもよい。
- 300 秒は [ADR 0117](0117-watchdog-outside-the-runtime-for-threaded-tests.md) と同じ値である。スイートで最も遅いテスト（「a tail recursion that never stops is E04100, the same twice」）は単独で 25〜34 秒、ほかのスイートと並べた `cabal test all` でもスイート全体が 91 秒で終わった。
- golem-emet-test の `build-depends` に `golem-test-support` を足す。golem-* のパッケージの依存を変えるので、この ADR で決める。golem-test-support のライブラリーは golem-* のパッケージに依存しないので、循環はできない。

### 上流の修正を追う

- `docs/roadmap.md` の未決事項に、次の項目を足す。
  - GHC の 9.14.2 が ghcup に出たら、または #28001 が直った版が出たら、文脈の再現の手順（変更の前のテストのソースと、同時整形のプログラム）を aarch64 の macOS と Linux で走らせ、落ちも止まりも消えたら、`localOption (NumThreads 1)` を外す ADR を書く。
  - 言語サーバーの semantic tokens のように、本番で .emet の構文解析が同時に走る経路が、この不具合に当たるかどうか。
  - golem のコードを使わない再現。

### 文書

- `docs/specifications.md` の golem-test-support の段落で、`watchTests` を使うスイートに golem-emet-test を足し、この ADR へのリンクを添える。
- `CONTRIBUTING.md` と `CONTRIBUTING.en.md` のテストの節に、golem-emet-test も `watchTests` で包むこと、テストを一つずつ走らせることと、その理由（aarch64 の GHC の不具合）を書く。
- 開発者のマニュアル（`manual-dev/part2/09-adr.gm` の時間の上限の段落）に同じことを足す。

## 実装しないこと

- **GHC の版を上げること**：9.12.4 と 9.14.1 でも落ちた。今ある版に上げても直らない。9.14.2 は roadmap の項目で試す。
- **RTS のオプション**：`+RTS -qg` では落ちた。`+RTS -N1` は本番ですべてのプロセッサーを使う決まり（[ADR 0050](0050-run-golem-on-every-processor.md)）に反し、テストだけなら `localOption (NumThreads 1)` で足りる。
- **`-feager-blackholing`**：macOS では消えたが、Linux の aarch64 では消えなかった。有効な理由を説明できない対処は入れない。
- **構文解析の下準備**：同時整形のプログラムの落ちは消えたが、テストの止まりは消えなかった。
- **`-threaded` を外すこと**：8,000 回のうち 0 回で、一つずつ走らせるのと同じく有効である。しかし、並列の評価のテストが、一つのコアの上で順に切り替わるだけのテストになる。
- **本番のコードの変更**：本番で再現していない。言語サーバーの経路は roadmap の未決事項に残す。
- **ほかの `-threaded` のスイートへの適用**：golem-parser-test の群は 4,000 回のうち 0 回だった。golem-driver-parallel-test、golem-lsp、golem-font、golem-plugin、golem-cli では、この手順で試していない。止まりか落ちを観測したら、同じ手順で調べる。
- **GHC の issue への書き込み**：この ADR の作業では、何も投稿しない。書き込むかどうかはメンテナーが決める（メンテナーが決めることの 3）。
- **再現の手順や同時整形のプログラムをコミットすること**：文脈の手順で足りる。上流の修正を確かめるときに要るなら、そのときの ADR で決める。

## 不変条件

- golem-emet-test のテストは、同じプロセスの中で同時に走らない。
- golem-emet-test のすべてのテストは、`watchTests` の見張りの下で走る。テストが 300 秒を超えるか、テストが終わってからプロセスが 300 秒を超えて終わらなければ、走っていたテストの名前と心拍の行を標準エラー出力に書き、`abort()` で止まる。
- golem-emet-test は `-threaded` と `-N` でリンクされ、並列の評価のテストは複数のコアで走る。
- テストを一つずつ走らせる理由は GHC の不具合であり、golem の仕様ではない。#28001 が直った GHC を使うようになったら、この制限を外すかどうかを ADR で決め直す。

## テスト設計

この変更は、まれにしか起きない止まりを消すものなので、決まった時間で終わる自動のテストでは確かめられない。
次の三つを手で確かめ、結果を実装のプルリクエストに書く。

1. 文脈の再現の手順を、変更の前と後の golem-emet-test で、それぞれ 8 プロセス × 1,000 回、aarch64 の macOS で走らせる。前は 1 回以上止まるか落ち、後は 0 回であること。この ADR を書くときに、同じ変更（`localOption (NumThreads 1)` だけを足したテストのソースの写し）で、前が 8,000 回のうち止まり 26 回と落ち 1 回、後が 8,000 回のうち 0 回であることを確かめた。
2. 見張りの上限を一時的に 2 秒にして、群の一つのテストに `threadDelay` で 10 秒待つ行を一時的に足して走らせる。走っていたテストの名前と心拍の行を出し、終了コード 134 で終わること。
3. `cabal test golem-emet` が、変更の前と同じ数のテストを通すこと。全体の時間が延びないこと。この ADR を書くときに、`-j1` で 32〜38 秒、並列で 30〜63 秒だった。

## トレードオフ

- 原因を直さずに、症状の出る条件をテストで避ける。同じ不具合が、本番で構文解析や評価が同時に走る経路に残っている可能性がある。roadmap の項目で追う。
- 並列の評価のテストは、テストの中で複数のスレッドを同時に走らせるので、このテストだけは同じ不具合に当たりうる。当たれば、見張りが名前を出して止めるか、SIGSEGV で落ちる。黙って長く止まることはない。
- テストを一つずつ走らせても、全体の時間はほとんど変わらない。最も遅いテストが全体の時間の大半を占めるからである。
- 見張りのために golem-emet-test が golem-test-support に依存する。テストのスイートだけの依存で、golem-emet のライブラリーは変わらない。
- 上流の修正を待つあいだ、ほかのスイートが同じ不具合に当たっても、見張りのないスイートは手元で黙って止まりうる。

## メンテナーが決めること

### 1. golem-emet-test への対処（推奨：一つずつ走らせ、見張りを付ける）

- **`localOption (NumThreads 1)` と見張り（推奨）**：macOS の再現の手順で 0 回になり、並列の評価のテストは複数のコアで走り続ける。見張りは、残った止まりも名前つきの失敗にする。
- **`-threaded` を外し、見張りを付ける**：同じく 0 回になる。並列の評価のテストが、並列でなくなる。
- **見張りだけ**：止まりは残るが、300 秒で名前つきの失敗になる。ときどき落ちるテストを再実行で済ませないという方針に反する。

### 2. 本番の言語サーバー（推奨：今は変えず、roadmap で追う）

- **今は変えない（推奨）**：1,200 回の試しで再現していない。変える根拠がない。
- **.emet の構文木を作る処理を一つずつにする**：言語サーバーには一つずつ評価する仕組み（`serially`）があり、semantic tokens もその下に置ける。不具合が本番で起きるかどうかわからないまま、応答を遅くする。

### 3. GHC の #28001 への情報の提供（推奨：tett23 がコメントを書くかどうかを決める）

この ADR の作業で、報告にない次のことを実機で確かめた。

- 9.10.3 でも起きる。
- Linux の aarch64（GitHub Actions の ubuntu-24.04-arm）でも落ちる。x86-64 では 12,000 回のうち 0 回だった。
- 止まったプロセスが CPU を使わない形もある。

これらは上流の切り分けに役立つ可能性がある。
ただし、golem のコードを使わない再現はまだない。
書き込むなら、tett23 が内容を確かめてからにする。

## 決めたことの記録

- **1 と 2**（2026-11-08、メンテナー）：推奨のとおりとした。
- **3**（2026-11-08、メンテナー）：この ADR からは書き込まない。さらなる条件がわかったら、メンテナーが自分で GHC に報告する。

## 参考文献

- [ADR 0050](0050-run-golem-on-every-processor.md)
- [ADR 0117](0117-watchdog-outside-the-runtime-for-threaded-tests.md)
- GHC の issue #28001「Rare segfaults and BLACKHOLE livelock with the threaded RTS on aarch64 macOS (9.12.4, 9.14.1)」：https://gitlab.haskell.org/ghc/ghc/-/issues/28001
- GHC の issue #20129「Data race in CAF blackholing」：https://gitlab.haskell.org/ghc/ghc/-/issues/20129
- GHC の issue #23374「Segfault on RTS schedule function (GHC 9.6.1)」：https://gitlab.haskell.org/ghc/ghc/-/issues/23374
- GHC の issue #26936「Parallel job hangs」（9.14.1 の退行、9.14.2 で修正）：https://gitlab.haskell.org/ghc/ghc/-/issues/26936
- GHC 9.14.2-rc1 の告知：https://www.haskell.org/ghc/blog/20260730-ghc-9.14.2-rc1-released.html
- tasty 1.5.4：`Test/Tasty/Run.hs`（`applyTopLevelPlusTestOptions`、`launchTestTree`）、`Test/Tasty/Ingredients/ConsoleReporter.hs`（`printTestName`）、`Test/Tasty/Options/Core.hs`（`NumThreads`）、`Test/Tasty/Parallel.hs`（`runInParallel`）https://hackage.haskell.org/package/tasty-1.5.4
- peg-runtime（peg-hs 8441ad7f）の `P`：https://github.com/tett23/peg-hs/blob/8441ad7f9d77acb6c95e6dce214ad219f03425d2/packages/peg-runtime/src/Peg/Runtime/Internal.hs#L347
- GHC 9.10.3 の aarch64 の STG のレジスターの割り当て（`rts/include/stg/MachRegs/arm64.h`）：https://gitlab.haskell.org/ghc/ghc/-/blob/ghc-9.10.3-release/rts/include/stg/MachRegs/arm64.h
- GitHub Actions の一時的な実行：[42400776836](https://github.com/tett23/golem/actions/runs/42400776836)、[42402553462](https://github.com/tett23/golem/actions/runs/42402553462)、[42403505173](https://github.com/tett23/golem/actions/runs/42403505173)
