# 二度めの監査の後の六つの ADR の照合（2026-11-05）

この記録は、2026-11-04 の main（fbea58c4、PR #535 のマージの直後）の Golem を、同日の二度めの監査（[2026-11-04-rc4-followup-conformance.md](2026-11-04-rc4-followup-conformance.md)、以下「前回の監査」）の後に採択して実装した ADR のプルリクエストと照らし合わせた結果である。
対象は次のとおりである。

- CI の [docs/adr/0146](../adr/0146-threaded-golem-driver-test.md)（golem-driver-test を threaded にする、PR #528）、[0147](../adr/0147-touch-setup-config-after-restoring-dist.md)（戻した dist-newstyle の setup-config の時刻、PR #530）、[0152](../adr/0152-remove-hackage-index-tar-gz-before-cache.md)（`01-index.tar.gz` を `rm` で除く、PR #532）、[0154](../adr/0154-scripts-macos-tests-at-once-with-deadline.md)（`scripts-macos` の六本を同時に走らせ、期限で止める、PR #535）。
- 前回の監査の所見から起こした [docs/adr/0151](../adr/0151-explain-uses-plugin-code-rule.md)（`golem explain` のプラグインのコードの形、PR #527）と [0153](../adr/0153-sample-plugin-codes-are-tails.md)（見本のプラグインの ADR の表のコードの読み方、PR #529）。

前回の監査の所見のうち、これらの ADR が引き取った F-12、F-16、F-22、F-26 が実際に直っているかも見た。
コードは変えていない。

同じ日に採択した [docs/adr/0148](../adr/0148-gmx-function-language-core.md)、[0149](../adr/0149-gmx-requirements-and-driver-handlers.md)、[0150](../adr/0150-calling-gmx-functions-from-gm.md)（関数を書く言語 `.gmx`、PR #531、#533、#534、#536）は、この監査の途中でメンテナーが草案として撤回し、実装のプルリクエストを戻してステータスを破棄にすると決めたので、範囲から外した。
fbea58c4 には `.gmx` の実装（`modules/golem-gmx`、golem-driver-test の `FunctionsSpec` など）が含まれているが、この記録はそれらを見ていない。

ソースコードへのリンクは、すべて調べたコミット fbea58c4 に固定した。

## 目的と範囲

六つの ADR の「実装すること」「実装しないこと」「テスト設計」「決めたことの記録」の各項目について、コード、テスト、CI の設定、文書（docs/specifications.md、README、CONTRIBUTING.md、manual-dev/、docs/ci-timings/）が ADR のとおりかを調べた。
ADR が指示した、ほかの ADR のステータスの行の書き換えも見た。
実装者がプルリクエストの本文で申告した逸脱は、妥当かどうかを判断した。

判断の基準、所見の分類（未実装、逸脱、範囲外の変更、テスト欠落、文書の不一致）と重大度（高、中、低）の定義は、前回の監査と同じである。
高は書き手の見る出力か diagnostic が ADR と違うもの、中はプロジェクトの原則か ADR の明示の規則に反するが影響の範囲が狭いもの、低は字面の違いか補助的なものとした。
CI の変更では、メンテナーが頼りにする検査が ADR と違って走らないものを高、ADR の明示の規則か運用の規則に反するものを中とした。

## 方法

1. 六つの ADR を全文読み、六つのプルリクエスト（#527、#528、#529、#530、#532、#535）の本文、コミットの一覧、変更したファイルの一覧を `gh pr view` と `git diff --stat` で取った。
2. ADR ごとに、コードとテストと文書を読み、項目ごとに対応する箇所を file:line で特定した。
3. fbea58c4 を `cabal build all`（GHC 9.10.3、wasmtime の C API は別の checkout の `third_party/wasmtime`）で組んだ。golem-cli のテストのうち `golem explain` のもの（`-p explain`、35 件）、golem-driver-global-test（120 件、10.8 秒）を `cabal test` で実行し、どちらも通った。golem-driver-test は、`modules/golem-driver` を作業ディレクトリにして `+RTS -N4` で 6 回続けて走らせ、どの回も 872 件が通り（qpdf がないため 1 件を飛ばす）、実時間は 20.1 秒から 24.2 秒だった。
4. `sh scripts/ci/test.sh` を、GNU の道具の `PATH` と、`scripts-macos` と同じ `/usr/bin:/bin:/usr/sbin:/sbin` の `PATH`（macOS 26 の BSD 版の道具）の二つで実行し、どちらも 361 件、失敗 0、飛ばし 4 だった。`scripts/test.sh`、`plugins/` の `cargo test`、見た目の回帰テストは実行していない。
5. `scripts/ci/run-all.sh` を `/bin/sh` で、`-t 2` と、`sleep 30` を含む偽のスクリプト、すぐ終わるスクリプト、終了コード 3 のスクリプトに対して実行し、出力、標準エラー出力、終了コード、残るプロセスを見た。`-t 0`、`-t x`、`-t 5x`、`-t 05`、`-t` を後ろに置いた形も試した。
6. 組んだ `golem` で `golem explain` に、[ADR 0151](../adr/0151-explain-uses-plugin-code-rule.md) のテスト設計の引数とそのほかの形（`G01017/`、`a/b/c`、`G01017/x`、`x /a`、`X/A x/a`）を渡し、標準出力、標準エラー出力、終了コードを見た。
7. CI の主張は、`docs/ci-timings/` が引く実行とその後の main の実行を `gh run view --json jobs` と `gh run view --job <id> --log` で取り直し、キャッシュは `gh api repos/tett23/golem/actions/caches`、マージの時刻は `gh pr view` と issue の timeline で確かめた。

## [ADR 0146](../adr/0146-threaded-golem-driver-test.md): golem-driver-test を threaded の RTS で並べて走らせ、プロセスの状態を変えるテストを別のスイートに分ける

### 適合を確かめたもの

- golem-driver-test の `ghc-options` は `-threaded "-with-rtsopts=-N"` で、`other-modules` に PluginsSpec と LocaleSpec がない（[golem-driver.cabal#L75-L105](https://github.com/tett23/golem/blob/fbea58c49120afaf77d9ea05bf395c6ffec037f5/modules/golem-driver/golem-driver.cabal#L75-L105)）。新しいスイート golem-driver-global-test は `-threaded` を持たず、`GlobalMain.hs` が PluginsSpec、`cacheHomeRestored`、LocaleSpec をこの順に並べる（[同#L136-L177](https://github.com/tett23/golem/blob/fbea58c49120afaf77d9ea05bf395c6ffec037f5/modules/golem-driver/golem-driver.cabal#L136-L177)、[GlobalMain.hs#L15-L26](https://github.com/tett23/golem/blob/fbea58c49120afaf77d9ea05bf395c6ffec037f5/modules/golem-driver/test/GlobalMain.hs#L15-L26)）。PR #528 は PluginsSpec と LocaleSpec を変えておらず、`Main.hs` からは三つの項目を取り除いただけで、残りの順も変わっていない。`setNumCapabilities` は呼ばない。golem-driver.cabal の二つのスイートの注釈は分け方のとおりである。
- `scripts/ci/test.sh` に、テスト設計の三つの検査がある。`-threaded` と `"-with-rtsopts=-N"`、global-test が `-threaded` を持たないこと、二つのモジュールの所在、golem-driver-test のモジュールと `Main` が `withEnv`、`setEnv`、`unsetEnv`、`setLocaleEncoding`、`setCurrentDirectory`、`withCurrentDirectory` を使わないこと（[test.sh#L1489-L1513](https://github.com/tett23/golem/blob/fbea58c49120afaf77d9ea05bf395c6ffec037f5/scripts/ci/test.sh#L1489-L1513)）。
- `sh scripts/ci/test-suites.sh driver` は golem-driver-test、golem-driver-global-test、golem-driver-parallel-test の三行を出し、`ci.yml` は PR #528 で変わっていない。
- CONTRIBUTING.md と CONTRIBUTING.en.md に、プロセスの状態を変えるテストは golem-driver-global-test に書くことと、`scripts-linux` が検査することの段落がある（[CONTRIBUTING.md#L225-L228](https://github.com/tett23/golem/blob/fbea58c49120afaf77d9ea05bf395c6ffec037f5/CONTRIBUTING.md#L225-L228)）。[ADR 0146](../adr/0146-threaded-golem-driver-test.md) のステータスの行は `採択` である。
- 手で確かめることのうち、`-N4` の 20 回は PR #528 が申告し（854 件、18.8 秒から 34.1 秒）、この監査でも上の 6 回がすべて通った（872 件。差は後の PR #534 が足した `FunctionsSpec` で、範囲外である）。前後の時間は [docs/ci-timings/2026-11-04-threaded-golem-driver-test.md](../ci-timings/2026-11-04-threaded-golem-driver-test.md) にあり、x86-64 の golem-driver-test は約 80 秒から 33〜50 秒、`tests-driver` の手順は 36〜54 秒になった。三つのスイートの件数（854、120、6）はログの tasty の行と一致する。`race.yml` に足さないことの決定と理由も、同じ記録にある。
- PR #528 のマージ（14:47:31Z）は、最終コミット a0d8cc99 の実行 41850302302 の成功（14:45:57Z）の後である。前回の監査の F-13 は繰り返されていない。

### 所見

**F-01（文書の不一致、低）：開発者のマニュアルへの追記が、ADR の「テストの章」でなく純粋性の章にある。**
ADR は「開発者のマニュアルのテストの章と CONTRIBUTING.md に」足すとした。
PR #528 は [manual-dev/part2/12-purity.gm#L252-L255](https://github.com/tett23/golem/blob/fbea58c49120afaf77d9ea05bf395c6ffec037f5/manual-dev/part2/12-purity.gm#L252-L255) の、golem-driver のテストが一つの capability で動くという古い記述を直すついでに書き、テストの章（`manual-dev/part2/08-build-test.gm`）には golem-driver-global-test の名前も、プロセスの状態を変えるテストの置き場も出てこない。
古い記述を直したことは必要で正しい。
テストを書く人が読む章に書き場所の規則がないのは、ADR の意図と違う。

**F-02（範囲外の変更、低）：golem-driver-global-test の build-depends が golem-driver-test の写しで、使わないパッケージを含む。**
[golem-driver.cabal#L149-L176](https://github.com/tett23/golem/blob/fbea58c49120afaf77d9ea05bf395c6ffec037f5/modules/golem-driver/golem-driver.cabal#L149-L176) は golem-driver-test の一覧をそのまま持つ。
このスイートの四つのモジュール（GlobalMain、PluginsSpec、LocaleSpec、Support）の import には、golem-epub、golem-length、golem-parser、golem-preflight のモジュールがない。
パッケージの単位の依存の図は変わらない（golem-driver のテストはすでにこれらに依存する）ので、ADR のない build-depends の変更とは見ないが、使わない四つは外せる。

**F-03（運用、低）：[ADR 0146](../adr/0146-threaded-golem-driver-test.md) の計測の記録が、[ADR 0147](../adr/0147-touch-setup-config-after-restoring-dist.md) のプルリクエスト（#530）で入った。**
PR #528 の本文は「この PR の実行から記録する」と書いたが、#528 は最終コミットの CI が通った直後にマージされ、記録のコミット 291bf81c は 26 秒後に #530 の枝に置かれた。
#530 の本文はこれを申告している。
記録の中身は ADR のテスト設計を満たす（前後 2 回以上、スイートの件数、`race.yml` の決定）。
記録がどの ADR の実装に属するかは、ファイル名と本文から辿れるので、実害はない。

## [ADR 0147](../adr/0147-touch-setup-config-after-restoring-dist.md): 戻した dist-newstyle の setup-config の更新時刻を新しくする

### 適合を確かめたもの

- 「Restore dist-newstyle」の直後に `if [ -d dist-newstyle ]; then find dist-newstyle -name setup-config -exec touch {} +; fi` の手順があり、`cabal build` の前にある（[ci.yml#L263-L277](https://github.com/tett23/golem/blob/fbea58c49120afaf77d9ea05bf395c6ffec037f5/.github/workflows/ci.yml#L263-L277)）。`dist-newstyle` がなければ何もしない。`PATH` と設定に触れないので、[docs/adr/0097](../adr/0097-ci-same-path-before-build-and-env-check-runner.md) の検査は通る（`scripts/ci/test.sh` が通ることで確かめた）。
- `scripts/ci/test.sh` に、手順の存在と、「Restore dist-newstyle」の後、`- id: build` の前にあることの二つの検査がある（[test.sh#L1026-L1041](https://github.com/tett23/golem/blob/fbea58c49120afaf77d9ea05bf395c6ffec037f5/scripts/ci/test.sh#L1026-L1041)）。
- 計測の記録 [docs/ci-timings/2026-11-04-touch-setup-config.md](../ci-timings/2026-11-04-touch-setup-config.md) がある。前の四つの実行の数値は ADR の文脈の表と一致し、後の二つの実行で設定し直しは三つのランナーのすべてで 0 である。`.cabal` に `other-modules` を一つ足す確かめのコミット（33f3f515）を置いて戻したことと、cabal-install が `configuration changed` でその枝を組み直したことが書かれている。
- この監査で、PR #532 のマージの後の main の実行 41882199399 の `tests-rest` のログを取り、`has been changed. Re-configuring` が 0 行であることを確かめた（`Linking` は 17 行）。[ADR 0147](../adr/0147-touch-setup-config-after-restoring-dist.md) のステータスの行は `採択` である。

### 所見

**F-04（記録、低）：main への push の実行の確認が、記録にない。**
ADR のテスト設計は「実装のプルリクエストの実行と、その後の `main` への push の実行で」設定し直しが出ないことを記録するとした。
記録は #530 の二つの実行だけを書く。
上のとおり main の実行でも 0 行であることをこの監査で確かめたので、結論は変わらない。

## [ADR 0151](../adr/0151-explain-uses-plugin-code-rule.md): `golem explain` が受けるプラグインのコードの形を、golem-plugin の規則で判定する

### 適合を確かめたもの

- golem-plugin は `pluginCodeForm = dataName` を公開し（[Plugin.hs#L49](https://github.com/tett23/golem/blob/fbea58c49120afaf77d9ea05bf395c6ffec037f5/modules/golem-plugin/src/Golem/Plugin.hs#L49)、[同#L823-L824](https://github.com/tett23/golem/blob/fbea58c49120afaf77d9ea05bf395c6ffec037f5/modules/golem-plugin/src/Golem/Plugin.hs#L823-L824)）、中の `pluginCode` はこれで判定する（[同#L829-L831](https://github.com/tett23/golem/blob/fbea58c49120afaf77d9ea05bf395c6ffec037f5/modules/golem-plugin/src/Golem/Plugin.hs#L829-L831)）。golem-cli の `pluginCode` は、`/` を含まなければ `Nothing`、`/` でちょうど二つに分かれ、前が空でなく空白を含まず、後が `pluginCodeForm` なら今までの一行、それ以外は ADR の文の誤りを返す（[cli/Main.hs#L158-L172](https://github.com/tett23/golem/blob/fbea58c49120afaf77d9ea05bf395c6ffec037f5/modules/golem-cli/app/Main.hs#L158-L172)）。`explain` は誤りを正しいコードの節の後に標準エラー出力へ書き、使い方を書かず、終了コード 2 とする（[同#L249-L262](https://github.com/tett23/golem/blob/fbea58c49120afaf77d9ea05bf395c6ffec037f5/modules/golem-cli/app/Main.hs#L249-L262)）。PR #527 は golem-cli.cabal を変えておらず、golem-\* のあいだの build-depends は変わっていない。
- 実機で、`x/404`、`x/-`、`x/0`、`x/_`、`x/2x`、`x/-a`、`lookup/No-key`、`G01017/`、`a/b/c`、`x /a` のすべてが、標準出力なし、標準エラー出力に ADR の一行、終了コード 2 になり、`x/a`、`x/a-`、`x/no-key-2`、`lookup/no-key`、`G01017/x` が今までの一行と終了コード 0、`nope` と `G99999` の文が変わらないことを確かめた。`x/404 G01017` は G01017 の節を単独のときと同じバイト列で書いた後、`x/404` の一行を標準エラー出力に書き、終了コード 2 だった。
- golem-cli の `explainTests` に、ADR のテスト設計の三つの新しいテストと、通り続けることを確かめる `x/a`、`x/a-`、`x/no-key-2` のテストがあり、旧の `exitsWith (ExitFailure 2) ["explain", "lookup/No-key"]` は置き換えられている（[test/Main.hs#L358-L375](https://github.com/tett23/golem/blob/fbea58c49120afaf77d9ea05bf395c6ffec037f5/modules/golem-cli/test/Main.hs#L358-L375)）。`-p explain` の 35 件が通った。golden の `explain-bad-code` と `explain-unknown-code` は変わっていない。
- 仕様書の「プラグイン」の節（[specifications.md#L3292-L3294](https://github.com/tett23/golem/blob/fbea58c49120afaf77d9ea05bf395c6ffec037f5/docs/specifications.md#L3292-L3294)）と CLI の表の行、開発者のマニュアルの CLI の章（[01-cli.gm#L133](https://github.com/tett23/golem/blob/fbea58c49120afaf77d9ea05bf395c6ffec037f5/manual-dev/part1/01-cli.gm#L133)）、[docs/adr/0139](../adr/0139-plugin-diagnostic-code-starts-with-letter.md) と [golem-cli ADR 0009](../golem-cli/adr/0009-explain-several-codes.md) のステータスの行の句。[ADR 0151](../adr/0151-explain-uses-plugin-code-rule.md) のステータスの行は `採択` である。
- 前回の監査の F-12 は閉じている。

### 所見

**F-05（範囲外の観察、低）：大文字に直して同じになる引数の重複の除き方が、プラグインのコードでは引数の順で結果を変える。**
実機で `golem explain X/A x/a` は `X/A` の形の誤りだけを書いて終了コード 2 になり、`x/a` の一行は出ない。
`golem explain x/a X/A` は `x/a` の一行を書いて終了コード 0 になり、形の誤りの `X/A` は黙って落ちる。
`nubOrdOn T.toUpper`（[cli/Main.hs#L257](https://github.com/tett23/golem/blob/fbea58c49120afaf77d9ea05bf395c6ffec037f5/modules/golem-cli/app/Main.hs#L257)）は大文字と小文字を区別しない Golem のコードのためのもので、ADR は「今の重複の除き方も変えない」とした。
逸脱ではないが、0151 が `/` の後の形を大文字で区別するようにした結果、同じ除き方がプラグインのコードには合わなくなった。
重複の除き方を Golem のコードに限るか、プラグインのコードは字面で比べるかを、短い ADR で決めるのがよい。

**F-06（文書の不一致、低）：`/` の前の誤りと二つ以上の `/` にも、「`/` の後は…」の文が出る。**
`x /a`（前に空白）と `a/b/c` は、ADR の 2 のとおり形の誤りになるが、文は `/ の後は英小文字で始まり…` で、直す場所を示していない。
ADR のトレードオフは、Golem のコードに `/` を混ぜた場合の文の不一致だけを挙げた。
ごく稀な入力であり、記録に残す。

## [ADR 0152](../adr/0152-remove-hackage-index-tar-gz-before-cache.md): Hackage の索引のキャッシュから `01-index.tar.gz` を `rm` で除く

### 適合を確かめたもの

- 索引のキャッシュの `path` は `~/.cabal/packages/hackage.haskell.org` の一行で、キーは `hackage-index-no-gz-${{ hashFiles('cabal.project.freeze') }}`、`cache-hit != 'true'` の手順は `cabal update`、`ls -l`、`rm`（`-f` なし）、`du -sh` の順である（[ci.yml#L239-L256](https://github.com/tett23/golem/blob/fbea58c49120afaf77d9ea05bf395c6ffec037f5/.github/workflows/ci.yml#L239-L256)）。手順の上の注は `rm` で消す理由に改まっている。`race.yml` は 4f86b945 から変わっていない。`ci.yml` の actions/cache の `path` に `!` の行はない。
- `scripts/ci/test.sh` の 0141 の検査は、ADR の四つの検査に置き換わっている（[test.sh#L984-L1004](https://github.com/tett23/golem/blob/fbea58c49120afaf77d9ea05bf395c6ffec037f5/scripts/ci/test.sh#L984-L1004)）。
- 計測の記録 [docs/ci-timings/2026-11-05-hackage-index-without-tar-gz.md](../ci-timings/2026-11-05-hackage-index-without-tar-gz.md) は、一回目の実行で `01-index.tar.gz` が 140298351 バイトだったこと、消した後の `cabal build` と `cabal test` が両方のアーキテクチャで通ったこと、二回目のキャッシュが 113937076 バイトだったこと、2026-11-04 の記録の推測が誤りで原因は actions/cache の `path` の扱いだったことを書く。この監査で、一回目の実行 41856732951 の六つの `build` のランナーがすべて成功で失敗は `visual` だけであること、main の最初の実行 41879977643 の `ls -l` が同じ 140298351 バイトで `du -sh` が 1015M であること、次の main の実行 41882199399 では六つのランナーのすべてで索引のキャッシュが当たって `cabal update` の手順が飛ばされ、`tests-rest` のログに `cabal update` を求める行がないことを確かめた。`gh api` の main の `hackage-index-no-gz-…` は 113973425 バイトである。
- 開発者のマニュアルの CI の章（[11-ci-jobs.gm#L115](https://github.com/tett23/golem/blob/fbea58c49120afaf77d9ea05bf395c6ffec037f5/manual-dev/part2/11-ci-jobs.gm#L115)）に `cabal update` の後に消して保存することと 0152 の注がある。[docs/adr/0141](../adr/0141-smaller-ghc-and-hackage-index-caches.md) のステータスの行の句。[ADR 0152](../adr/0152-remove-hackage-index-tar-gz-before-cache.md) のステータスの行は `採択` である。
- 前回の監査の F-16 は閉じている。索引のキャッシュは 242 MB から約 109 MB になった。

### 所見

**F-07（文書の不一致、低）：開発者のマニュアルの 0141 の一文が残り、0152 の一文が後ろに足されている。**
ADR は「Hackage の索引のキャッシュには、…（`01-index.tar.gz`）を入れない」を「`cabal update` の後に消してから保存する」に改めるとした。
[11-ci-jobs.gm#L115](https://github.com/tett23/golem/blob/fbea58c49120afaf77d9ea05bf395c6ffec037f5/manual-dev/part2/11-ci-jobs.gm#L115) は元の一文と 0141 の注を残し、その後ろに新しい一文と 0152 の注を足した。
二つの文はどちらも今の振る舞いとして正しいので、読者に誤りは伝わらない。

**F-08（記録、低）：古いキー `hackage-index-tar-…` の main のキャッシュは 254 MB で、記録の 242 MB より大きい。**
`gh api` の 2026-11-05 の値は 254106712 バイト（main、最後のアクセスは 2026-11-04T17:37Z）である。
ADR と二つの記録の 242 MB は、プルリクエストのマージの ref のキャッシュの値である。
索引は `cabal update` のたびに大きくなるので、同じキーでも保存した日で大きさが違う。
比較の基準としては、同じ日の同じ ref の値を並べるのがよい。
0152 の結論（約 134 MiB の差がなくなった）は変わらない。

## [ADR 0153](../adr/0153-sample-plugin-codes-are-tails.md): 見本のプラグインの ADR の表のコードを、プラグインが返す後ろの部分として読む

### 適合を確かめたもの

- [docs/adr/0130](../adr/0130-sou-ruby-plugin.md) と [0131](../adr/0131-first-occurrence-ruby-plugin.md) のステータスの行は、ADR の句と一字一句同じである。[0125](../adr/0125-kansuji-plugin-overrides-number-text.md)、[0128](../adr/0128-auto-tcy-filter.md)、[0129](../adr/0129-tsv-table-plugin.md) も同じく ADR の句である。[docs/adr/0136](../adr/0136-missing-plugin-data-at-load.md) のステータスの行は `採択` のままである。PR #529 はステータスの行と [ADR 0153](../adr/0153-sample-plugin-codes-are-tails.md) のステータスの行以外を変えていない。
- `rg '(kansuji|auto-tcy|tsv-table|sou-ruby|first-ruby)-(no-words|unread|utf8|tsv|dict|arity|not-number|split|config|name|cells)'` は、`docs/adr/` と `docs/audits/` の外に何も出さない。
- 表示の形を固定する golem-driver の `PluginsSpec` は、golem-driver-global-test の 120 件の中で通った。`plugins/` の `cargo test` はこの監査では実行していない（PR #529 はコードを変えていない）。
- 前回の監査の F-22 は閉じている。

所見はない。

## [ADR 0154](../adr/0154-scripts-macos-tests-at-once-with-deadline.md): `scripts-macos` の六本のテストを同時に走らせ、期限を過ぎたテストを止めて出力を残す

### 適合を確かめたもの

- `run-all.sh [-t SECONDS] SCRIPT...` は、`-t` の値を正の整数（先頭が 1 から 9）に限り、ほかは使い方の誤り（終了コード 2）とする（[run-all.sh#L19-L31](https://github.com/tett23/golem/blob/fbea58c49120afaf77d9ea05bf395c6ffec037f5/scripts/ci/run-all.sh#L19-L31)）。見張りのプロセスは `sleep SECONDS` の後に、終わっていないスクリプトの `sh SCRIPT` を `kill` し、`</dev/null >/dev/null 2>&1` で run-all.sh の出力を持たない（[同#L50-L66](https://github.com/tett23/golem/blob/fbea58c49120afaf77d9ea05bf395c6ffec037f5/scripts/ci/run-all.sh#L50-L66)）。止めたスクリプトは `==> SCRIPT: timed out after SECONDS s` の見出しとそこまでの出力、標準エラー出力の `run-all: SCRIPT timed out (SECONDS s)`、終了コード 1 である（[同#L72-L89](https://github.com/tett23/golem/blob/fbea58c49120afaf77d9ea05bf395c6ffec037f5/scripts/ci/run-all.sh#L72-L89)）。冒頭のコメントに `-t` がある。
- 実機（`/bin/sh`、BSD の道具の `PATH`）で、`sleep 30` を含むスクリプト、すぐ終わるスクリプト、終了コード 3 のスクリプトを `-t 2` に渡し、`| cat` のパイプが 2 秒で閉じ、三つの見出しが引数の順に並び、止めたスクリプトの出力が `before` だけで、標準エラー出力が `timed out (2 s)` と `failed (exit 3)` の二行、終了コードが 1 であることを確かめた。`sleep 30` のプロセスは ADR のとおり残った。`-t 0`、`-t x`、`-t 5x`、`-t 05` は使い方の誤りで終了コード 2 だった。
- `scripts-macos` は `sh scripts/ci/run-all.sh -t 600 …` の一つの手順で、ジョブの `timeout-minutes` は 15 である（[ci.yml#L583-L598](https://github.com/tett23/golem/blob/fbea58c49120afaf77d9ea05bf395c6ffec037f5/.github/workflows/ci.yml#L583-L598)）。`scripts-linux` は変わっていない。
- `scripts/ci/test.sh` に、`-t 2` の振る舞い、標準エラー出力の一行、`-t 0` と `-t x`、手順の字面と `600 < timeout-minutes × 60` の検査がある（[test.sh#L905-L913](https://github.com/tett23/golem/blob/fbea58c49120afaf77d9ea05bf395c6ffec037f5/scripts/ci/test.sh#L905-L913)、[同#L1471-L1487](https://github.com/tett23/golem/blob/fbea58c49120afaf77d9ea05bf395c6ffec037f5/scripts/ci/test.sh#L1471-L1487)）。`-t` のない七つの検査は変わっていない。GNU と BSD の両方の道具で通った。
- 手で確かめることのうち、`sleep 900` の下書きのコミット（b74d8a8a）の実行 41880168814 の `scripts-macos` のログに、五本の `exit 0` の見出しと `==> scripts/test.sh: timed out after 600 s`、`run-all: scripts/test.sh timed out (600 s)` があり、ジョブは 10 分 10 秒で失敗した。コミットは 1a213585 で戻された。実装の後の `scripts-macos` は、#535 の最終の実行で 60 秒、マージの後の main の実行 41884712244 で 69 秒であり、PR #522 の 78 秒から延びていない。
- README の CI の表（[README.md#L381](https://github.com/tett23/golem/blob/fbea58c49120afaf77d9ea05bf395c6ffec037f5/README.md#L381)）と開発者のマニュアルの CI の章（[11-ci-jobs.gm#L316-L318](https://github.com/tett23/golem/blob/fbea58c49120afaf77d9ea05bf395c6ffec037f5/manual-dev/part2/11-ci-jobs.gm#L316-L318)）。[ADR 0154](../adr/0154-scripts-macos-tests-at-once-with-deadline.md) のステータスの行は `採択` である。
- 前回の監査の F-26 は閉じている。PR #522 の作りとトレードオフは [ADR 0154](../adr/0154-scripts-macos-tests-at-once-with-deadline.md) に記録された。

### 所見

**F-09（逸脱、申告あり、低）：`-t 2` のテストの時間の上限が、ADR の 10 秒でなく 20 秒である。**
[test.sh#L1475-L1479](https://github.com/tett23/golem/blob/fbea58c49120afaf77d9ea05bf395c6ffec037f5/scripts/ci/test.sh#L1475-L1479) は run-all.sh を二度（パイプの出力と終了コードのために）走らせ、二度の合計を 20 秒未満とする。
PR #535 はこれを申告した。
背景のプロセスが出力を持ったままなら 30 秒かかるので、20 秒でも検査の目的は果たす。

**F-10（範囲外の観察、低）：見張りの判定と `kill` のあいだに、終わったスクリプトを止めたと報告する窓がある。**
見張りは `.end` のファイルがないことで走っていると判定し、`.timedout` を作ってから `kill` する（[run-all.sh#L59-L62](https://github.com/tett23/golem/blob/fbea58c49120afaf77d9ea05bf395c6ffec037f5/scripts/ci/run-all.sh#L59-L62)）。
`.end` はスクリプトの `wait` が返った後に書かれるので、期限のちょうどそのときに終わったスクリプトは、`exit 0` でも `timed out` と報告されうる。
窓はミリ秒の単位で、600 秒の期限と 78 秒のテストでは起こらない。
記録に残す。

## 前回の監査の所見の現状

| 前回の番号 | 現状 |
| --- | --- |
| F-12 | [ADR 0151](../adr/0151-explain-uses-plugin-code-rule.md)（#527）が直した。`x/404`、`x/-`、`x/0` は終了コード 2 になる（この記録の 0151 の節） |
| F-16 | [ADR 0152](../adr/0152-remove-hackage-index-tar-gz-before-cache.md)（#532）が直した。索引のキャッシュは 242 MB から約 109 MB になり、`01-index.tar.gz` なしで cabal-install 3.16.1.0 が計画を立てることも CI で確かめられた |
| F-22 | [ADR 0153](../adr/0153-sample-plugin-codes-are-tails.md)（#529）が記録した。五つの ADR のステータスの行に句がある |
| F-26 | [ADR 0154](../adr/0154-scripts-macos-tests-at-once-with-deadline.md)（#535）が記録し、期限を足した |
| F-13 | この監査の六つのプルリクエストでは繰り返されていない。どれも最終コミットの CI の成功（3 秒から 100 秒前）の後にマージされた |
| F-15 | 残る。`scripts/ci/test.sh` は GNU の awk で `escape sequence '\('` の警告を二行出す |
| ほかの低の所見 | 変わらない |

## 横断的な所見

**範囲の変更**：0148 から 0150 と PR #531、#533、#534、#536 は、撤回のため見ていない。
fbea58c4 のコードには `.gmx` の実装が残っており、golem-driver-test の `FunctionsSpec`（18 件）もその一部である。
この監査の golem-driver-test の 872 件はそれを含むが、0146 の判断には関わらない。

**ADR の外で決めたことの記録**：六つの実装で、新たに ADR の外で決まったことは、golem-driver-global-test の build-depends の一覧（F-02）だけである。
F-03 の記録の置き場は申告されている。

**手で確かめることの実行**：四つの CI の ADR（0146、0147、0152、0154）は、どれも手で確かめることを実際に行い、`docs/ci-timings/` か PR のコミットの履歴に残した。
0147 の `.cabal` の変更の確かめ、0152 の一回目の `cabal build`、0154 の `sleep 900` の下書きは、ADR の手順どおりに下書きのコミットを置いて戻している。
前回の監査が指摘した「見積もりと合わない結果を別の説明で閉じる」ことは、0152 の記録が訂正した。

**運用**：六つのプルリクエストは、どれも最終コミットの CI が成功した後にマージされた。
F-13 の原因（管理者の bypass）は残っているが、使われていない。

**build-depends**：六つのプルリクエストで、golem-\* のパッケージのあいだの依存は変わっていない。
新しいテストのスイートの一覧（F-02）は、既存のスイートの写しである。

**申告の質**：申告された逸脱（F-03、F-09）はどちらも妥当である。
申告のない所見は、すべて低である。

## 要約表

| 番号 | 所見 | 分類 | 重大度 | 根拠 |
| --- | --- | --- | --- | --- |
| F-01 | 開発者のマニュアルの追記がテストの章でなく純粋性の章にある | 文書の不一致 | 低 | 12-purity.gm#L252-L255、08-build-test.gm |
| F-02 | golem-driver-global-test の build-depends が写しで、使わない四つを含む | 範囲外の変更 | 低 | golem-driver.cabal#L149-L176 |
| F-03 | 0146 の計測の記録が #530 で入った | 運用（申告あり） | 低 | PR #528、#530 |
| F-04 | 0147 の main の実行の確認が記録にない | 記録 | 低 | 2026-11-04-touch-setup-config.md、実行 41882199399 |
| F-05 | 大文字小文字を区別しない重複の除き方が、プラグインのコードでは引数の順で結果を変える | 範囲外の観察 | 低 | cli/Main.hs#L257、実機 |
| F-06 | `/` の前の誤りと二つ以上の `/` にも「`/` の後は…」の文 | 文書の不一致 | 低 | cli/Main.hs#L172、実機 |
| F-07 | 開発者のマニュアルの 0141 の一文が残る | 文書の不一致 | 低 | 11-ci-jobs.gm#L115 |
| F-08 | 古いキーの main のキャッシュは 254 MB で、記録の 242 MB と違う | 記録 | 低 | `gh api actions/caches` |
| F-09 | `-t 2` のテストの時間の上限が 10 秒でなく 20 秒 | 逸脱（申告あり） | 低 | test.sh#L1475-L1479 |
| F-10 | 見張りの判定と `kill` のあいだの窓 | 範囲外の観察 | 低 | run-all.sh#L59-L62 |

高と中の所見はない。
前回の監査の中の所見 F-12、F-16、F-22、F-26 は、四つの ADR で閉じた。
