# セキュリティ監査の後の十二の ADR の照合（2026-11-05）

この記録は、2026-11-05 の main（645a739f、PR #557 のマージの直後）の Golem を、同日の [セキュリティ監査](2026-11-05-security-audit.md)と [三度めの照合の監査](2026-11-05-gmx-and-ci-conformance.md)（以下「前回の監査」）の後に採択して実装した ADR のプルリクエストと照らし合わせた結果である。
対象は次のとおりである。

- セキュリティ監査の所見から起こした [docs/adr/0156](../adr/0156-wasmtime-49-0-5.md)（wasmtime を 49.0.5 に上げる、PR #545）、[0157](../adr/0157-check-wasmtime-pin-against-advisories.md) と [0166](../adr/0166-read-wasmtime-advisory-ranges-as-written.md)（固定した版をアドバイザリと毎日照合する、PR #553）、[0158](../adr/0158-svg-external-references-beyond-href.md)（G08014 の検査を広げる、PR #546）、[0159](../adr/0159-unwritable-characters-in-csl-json.md)（CSL-JSON の出力に書けない文字を G03108 で拒む、PR #549）。
- テストと CI の [docs/adr/0117](../adr/0117-watchdog-outside-the-runtime-for-threaded-tests.md)（ランタイムの外の見張り、PR #548）、[0155](../adr/0155-split-aarch64-test-runner.md)（aarch64 のテストを二つのランナーに分ける、PR #539）、[0163](../adr/0163-build-visual-pdfs-in-parallel.md)（見た目の回帰テストの PDF を並べて組む、PR #543）、[0165](../adr/0165-wait-pdfs-finds-the-job-under-a-caller-prefix.md)（`wait-pdfs.sh` が呼び出し元の接頭辞のついた名前でも待つ、PR #551）、[0167](../adr/0167-leave-cache-restore-failures-as-misses.md)（キャッシュの復元の失敗は外れのまま、PR #555）、[0168](../adr/0168-render-visual-pdfs-side-by-side-with-shem-jobs-1.md)（PDF を並べて描き shem に `--jobs 1` を渡す、PR #557）。
- 前回の監査の所見から起こした [docs/adr/0164](../adr/0164-explain-dedup-and-plugin-code-messages.md)（`golem explain` の重複の除き方と形の誤りの文、PR #544）。
- ADR のないプルリクエスト二つ。`release.yml` の `ci` ジョブに `actions: read` を与えた PR #547 と、[docs/adr/0100](../adr/0100-raise-shem-to-v0-1-0-rc3-and-pre-release-bumps.md) の手順で shem を v0.1.0-rc4 に上げた PR #552。

セキュリティ監査の V-01、V-02、V-03 と、前回の監査の F-05、F-06 が実際に直っているかも見た。
コードは変えていない。

破棄した [docs/adr/0148](../adr/0148-gmx-function-language-core.md) から [0150](../adr/0150-calling-gmx-functions-from-gm.md) と、コミットしていない下書き（0098、0160 から 0162）は範囲の外である。

ソースコードへのリンクは、すべて調べたコミット 645a739f に固定した。

## 目的と範囲

十二の ADR の「実装すること」「実装しないこと」「テスト設計」「決めたことの記録」の各項目について、コード、テスト、CI とリリースの設定、文書（docs/specifications.md、docs/diagnostics.md、README、CONTRIBUTING、二つのマニュアル、docs/roadmap.md、docs/ci-timings/）が ADR のとおりかを調べた。
ADR が指示した、ほかの ADR のステータスの行の書き換えも見た。
実装者がプルリクエストの本文で申告した逸脱は、妥当かどうかを判断した。

判断の基準、所見の分類（未実装、逸脱、範囲外の変更、テスト欠落、文書の不一致）と重大度（高、中、低）の定義は、前回の監査と同じである。
高は書き手の見る出力か diagnostic が ADR と違うもの、中はプロジェクトの原則か ADR の明示の規則に反するが影響の範囲が狭いもの、低は字面の違いか補助的なものとした。

## 方法

1. 十二の ADR を全文読み、十三のプルリクエスト（#539、#543 から #549、#551 から #553、#555、#557）の本文、コミットの一覧、変更したファイルの一覧を `gh pr view` と `git diff --stat` で取った。
2. ADR ごとに、コードとテストと文書を読み、項目ごとに対応する箇所を file:line で特定した。
3. 645a739f を新しい worktree に取り出し、`scripts/fetch-wasmtime.sh` で wasmtime を取得して（aarch64-macos の配布物の SHA-256 がスクリプトの値と一致した）、`cabal build all`（GHC 9.10.3、cabal 3.16.1.0）で組んだ。組んだ `golem` に `scripts/check-wasmtime-linked.sh` を当て、`libwasmtime.a` と `golem` を `strings -a` で見た。`cabal test` で golem-plugin、golem-test-support、golem-svg、golem-doc、golem-cli、golem-driver-parallel-test の六つのスイートを実行し、すべて通った。
4. スクリプトのテストを実行した。`sh scripts/test.sh`（145 件、失敗 0、10.6 秒）、`sh scripts/visual/test.sh`（150 件、失敗 0）、`sh scripts/release/test.sh`（242 件、失敗 0）、`sh scripts/ci/test.sh`（GNU の道具の `PATH`、366 件、失敗 0、飛ばし 4）。`scripts/ci/test.sh` を BSD の道具で実行することと、`plugins/` の `cargo test`、見た目の回帰テストそのもの（`scripts/visual/check.sh`）は実行していない。
5. `scripts/wasmtime-advisories.sh` を、コミットした fixture に対して 49.0.5 と 49.0.2（`MANIFEST.tsv` の 49.0.5 を 49.0.2 に、0.136.5 を 0.136.2 に置き換えたもの）で、また引数なしで GitHub の API（2026-11-05）に対して実行した。同じ API の応答を取り、fixture と ID と `vulnerabilities` の要素の数を比べた。
6. wasmtime の五つの配布物の SHA-256 を GitHub の release の API の `digest` と、タグ `v49.0.5` のコミットを `git/ref/tags` の API と比べた。shem の三つの配布物の SHA-256 を release の API の `digest` と `SHA256SUMS` と比べた。
7. セキュリティ監査の二つの probe（[svg-probe.hs](2026-11-05-evidence/svg-probe.hs) を `runghc` で、[cli-probe.sh](2026-11-05-evidence/cli-probe.sh) を組んだ `golem` で）を、監査の記録の手順どおりに実行した。probe の三つめの試験（出力先のガード）は後述の理由で働かないので、同じ fixture に SVG を足さずにシンボリックリンクの `build` だけを置いて、別に実行した。
8. 組んだ `golem` で `golem explain` に、[ADR 0164](../adr/0164-explain-dedup-and-plugin-code-messages.md) の二つの表とテスト設計の引数（`X/A x/a`、`x/a X/A`、`lk/x LK/x`、`nope NOPE`、`a/b/c`、`x/a/`、`/a/b`、`x /a`、`/a`、`x y/A`、`/A`、`x/A`、`x/404`、`G01017/`、`x/a x/a`、`G01017/x`）を渡し、標準出力、標準エラー出力、終了コードを見た。
9. CI とリリースの主張は、`gh run view --json jobs`、`gh run view --job <id> --log`、`gh api repos/tett23/golem/commits/<sha>/check-runs` で取り直した。release の実行 41934030359、advisories の実行 41935839410、`ci.yml` の実行 41887380664 と 41889606653 を見た。公開済みの三つのリリースのノートは `gh release view` で読んだ。
10. 645a739f で `sh scripts/ci/textlint.sh origin/main`、`adr-guard links`、`adr-guard check-status`、`adr-guard unimplemented` を実行し、どれも終了コード 0 で、未実装の ADR はなかった。

## [ADR 0156](../adr/0156-wasmtime-49-0-5.md): wasmtime を 49.0.5 に上げる

### 適合を確かめたもの

- `scripts/fetch-wasmtime.sh` は `VERSION=49.0.5` で、五つの SHA-256 は ADR の表と一字一句同じである（[fetch-wasmtime.sh#L20-L31](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/scripts/fetch-wasmtime.sh#L20-L31)）。この監査で、GitHub の release の API が返す五つの `-c-api.tar.xz` の `digest` がこの五つと一致し、タグ `v49.0.5` が `805a0f15320e8836cf2b9f001b53d884bf866c89` を指すことを確かめた。手元で取得した aarch64-macos の `libwasmtime.a` は `version: 49.0.5` の行をちょうど一つ持ち、`rustc version 1.98.0` である。
- 49.0.2 は、`scripts/release/test.sh` の `licenses.sh` のための偽の入力、`scripts/test.sh` と `scripts/testdata/` のアドバイザリの照合のテスト、コミット済みの ADR（[golem-plugin ADR 0001](../golem-plugin/adr/0001-wasm-host-and-abi.md)）のほかに残っていない。`Plugin.hs`、`golem-plugin.cabal`、README の表、`manual-dev` の三つの章は 49.0.5 である（[Plugin.hs#L3](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/modules/golem-plugin/src/Golem/Plugin.hs#L3)、[golem-plugin.cabal#L42](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/modules/golem-plugin/golem-plugin.cabal#L42)、[README.md#L182](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/README.md#L182)）。
- `scripts/wasmtime-licenses.sh` は `VERSION=49.0.5`、`COMMIT=805a0f15…`、`RUSTC_VERSION=1.98.0` で、`COMPILER_RT_LICENSE_SHA256` は変わっていない（[wasmtime-licenses.sh#L37-L45](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/scripts/wasmtime-licenses.sh#L37-L45)）。`licenses/wasmtime-v49.0.5/` があり（`MANIFEST.tsv` は 256 行で、`wasmtime` 49.0.5、`cranelift-codegen` 0.136.5、`http` 1.5.0、`rustls` 0.23.46、`rustls-webpki` 0.103.15）、`licenses/wasmtime-v49.0.2/` は消えている。`c-objects.tsv` は 49.0.2 のものとバイト列で同じで、構成要素の列は引き継がれている。
- `ci.yml` の `dist-newstyle` のキーと `restore-keys`（復元と二つの保存）と `race.yml` のキーに `hashFiles('scripts/fetch-wasmtime.sh')` がある（[ci.yml#L275-L276](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/.github/workflows/ci.yml#L275-L276)、[同#L467](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/.github/workflows/ci.yml#L467)、[同#L478](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/.github/workflows/ci.yml#L478)、[race.yml#L93-L94](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/.github/workflows/race.yml#L93-L94)）。`release.yml` の musl の wasmtime のキャッシュのキーは変わっていない。
- `scripts/check-wasmtime-linked.sh` は、`fetch-wasmtime.sh --expected` の名前から版を取り、`strings -a` の `^version: [0-9]+\.[0-9]+\.[0-9]+$` の行がちょうど一つで値が一致すれば 0、そうでなければ見つけた行と期待した版を標準エラー出力に書いて 1 で終える（[check-wasmtime-linked.sh](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/scripts/check-wasmtime-linked.sh)）。`ci.yml` の `build` のジョブで `cabal build` の後に `cabal list-bin -v0 golem` に対して走り（[ci.yml#L314-L315](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/.github/workflows/ci.yml#L314-L315)）、`release.yml` の `smoke` のジョブで展開した配布物の `golem` に対して走る（[release.yml#L158-L162](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/.github/workflows/release.yml#L158-L162)）。レーンの報告にあった「別の手順として走らせた」は、ADR の「`smoke` のジョブで…実行する」のとおりであり、逸脱ではない。
- この監査で組んだ `golem` に対して `check-wasmtime-linked.sh` は終了コード 0 で、`strings -a` の `version:` の行は `version: 49.0.5` の一つだった。
- golem-plugin のテストに、分岐先が 65521 の `br_table` が `CompileFailed` で `exceeds the implementation limit of 65520` を含むこと、65520 が `MissingExport` になることの二つがある（[test/Main.hs#L234-L243](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/modules/golem-plugin/test/Main.hs#L234-L243)）。PR #545 は、49.0.2 では前者が `MissingExport "golem_abi_version"` で失敗したことを申告している。`scripts/release/test.sh` に `check-wasmtime-linked.sh` の四つの場合（一行、行なし、別の版、二行）のテストがある（[release/test.sh#L463-L485](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/scripts/release/test.sh#L463-L485)）。golem-plugin-test（ABI、import の拒否、fuel、メモリとテーブルの上限、並行性を含む）と `scripts/release/test.sh` は、この監査で通った。
- `release.yml` を `workflow_dispatch` で動かした実行 41934030359（main の 15d98089、2026-11-04）は、三つの `build`（`licenses.sh` を含む）、三つの `smoke`（`check-wasmtime-linked.sh` の手順が三つとも成功）、`determinism`、`notes`、`ci / ci` のすべてが成功し、`release` だけがタグの push でないため省かれた。
- 仕様書と roadmap は変わっていない。[ADR 0156](../adr/0156-wasmtime-49-0-5.md) のステータスの行は `採択` である。

### 所見

**F-01（未実装、中）：公開済みの v0.1.0-rc1、rc2、rc3 のリリースのノートに、aarch64 の配布物が GHSA-mghf-wjfp-p5xm の対象であるという注意がない。**
ADR の「配布物と過去のリリース」は、三つのリリースのノートの先頭に、aarch64 の配布物が GHSA-mghf-wjfp-p5xm（CVE-2026-115893）の対象であること、信頼できないプラグインを読み込まないこと、修正した版のリリースへのリンク（出したときに足す）の注意を英語で足すとした。
2026-11-05 に `gh release view` で読んだ三つのノートは、どれも `GHSA` も `CVE-2026-115893` も含まず、rc1 のノートは「a sandboxed wasm plugin host on wasmtime 49.0.2」と書くだけである。
PR #545 は「公開済みのリリースのノートは、ADR のとおりメンテナーに任せる」と申告したが、ADR はノートの変更をメンテナーに任せるとは書いていない。
リンクは修正した版のリリースの後に足すとしても、注意の本文は今すぐ書ける。
[ADR 0156](../adr/0156-wasmtime-49-0-5.md) のステータスは `採択`（実装済み）であり、この項目だけが残っている。
配布物は差し替えないと決めたので、脆弱な配布物を使い続ける利用者に届く唯一の手段がこの注意であり、公開から日が経つほど意味が薄れる。
中としたのは、Golem の出力や diagnostic ではなく、GitHub の Releases の文章だからである。

**F-02（逸脱、申告あり、低）：`scripts/wasmtime-licenses.sh` の `archive_sha` の三つの SHA-256 を、ADR の指示の外で変えた。**
ADR は `VERSION` と `COMMIT` だけを挙げたが、スクリプトは配布物の SHA-256 を `archive_sha` に持ち、一致しなければ止まる（[wasmtime-licenses.sh#L68-L74](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/scripts/wasmtime-licenses.sh#L68-L74)）。
三つの値は `fetch-wasmtime.sh` と ADR の表の値と同じで、PR #545 が申告している。
ADR の書き漏れを正しく補ったものである。

## [ADR 0157](../adr/0157-check-wasmtime-pin-against-advisories.md) と [ADR 0166](../adr/0166-read-wasmtime-advisory-ranges-as-written.md): 固定した wasmtime の版を、上流のアドバイザリと毎日照合する

### 適合を確かめたもの

- `scripts/wasmtime-advisories.sh [ADVISORIES_JSON]` は POSIX のシェルと `jq` と `awk` で書かれ、固定した版を `fetch-wasmtime.sh --expected`（テストでは `WASMTIME_VERSION`）から、パッケージの版を `licenses/wasmtime-v<版>/MANIFEST.tsv`（テストでは `WASMTIME_MANIFEST`）から取る（[wasmtime-advisories.sh#L45-L53](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/scripts/wasmtime-advisories.sh#L45-L53)）。引数がなければ `gh api --paginate` でリポジトリのアドバイザリを取る（[同#L62-L65](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/scripts/wasmtime-advisories.sh#L62-L65)）。
- 範囲の読み方は 0166 のとおりである。末尾の `(excluding …)` を切り離し、カンマ、`&&`、単語の `and` で分け、版の順に並べ（同じ版が二度なら誤り）、下限で開き上限で閉じ、一つの版はその版だけの区間とする（[同#L97-L140](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/scripts/wasmtime-advisories.sh#L97-L140)）。修正版は上限のない区間に入ったときだけ読み、系列か最大の規則で直った版とし、`note:` を標準エラーに書く（[同#L167-L181](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/scripts/wasmtime-advisories.sh#L167-L181)）。エコシステムは `rust` か `crates.io`、一覧にないパッケージは誤りである（[同#L156-L157](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/scripts/wasmtime-advisories.sh#L156-L157)）。出力の行と終了コード（当たれば 1、誤りなら 2）は 0157 のとおりである。
- 実機で、fixture に対して 49.0.5 は当たり 0、誤り 0、終了コード 0 で、標準エラーは GHSA-vc8c-j3xm-xj73 の `note:` の一行だった。49.0.2 は 25 件、終了コード 1 で、ID の一覧は 0166 の 25 件と一字一句同じだった。引数なしで GitHub の API に対して実行すると、終了コード 0、同じ `note:` の一行だった。API は 86 件のアドバイザリ、133 の `vulnerabilities` の要素を返し、fixture の ID の集合と各アドバイザリの要素の数と一致した。
- `.github/workflows/advisories.yml` は `schedule`（`41 21 * * *`）と `workflow_dispatch` で動き、`permissions` は `contents: read` だけで、ジョブは checkout と `sh scripts/wasmtime-advisories.sh`（`GH_TOKEN` は `github.token`）だけである（[advisories.yml](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/.github/workflows/advisories.yml)）。`workflow_dispatch` の実行 41935839410（main の f96ffb79）は成功した。
- `scripts/test.sh` に 0157 と 0166 のテスト設計の項目があり（`wasmtime-advisories` の名前を持つ検査が 24 箇所、fixture は 86 件を `ghsa_id`、`severity`、`summary`、`vulnerabilities` の三つのキーに絞ったもの）、145 件が通った。PR #553 は、テストだけのコミット（73 件が失敗）、0157 の規則の実装（0166 の 39 件が失敗）、0166 の規則の実装の三段で進めたことを申告している。
- 文書は、仕様書の固定したライブラリの節（[specifications.md#L517-L525](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/docs/specifications.md#L517-L525)）、README のワークフローの表（[README.md#L385](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/README.md#L385)）、CONTRIBUTING.md と CONTRIBUTING.en.md の wasmtime の版を上げる段落（[CONTRIBUTING.md#L139-L140](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/CONTRIBUTING.md#L139-L140)、[CONTRIBUTING.en.md#L126](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/CONTRIBUTING.en.md#L126)）、開発者のマニュアルの wasmtime の節（[08-build-test.gm#L57-L63](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/manual-dev/part2/08-build-test.gm#L57-L63)）にある。PR #545 の本文には、[ADR 0157](../adr/0157-check-wasmtime-pin-against-advisories.md) の手順のとおり照合の出力と終了コードが貼られている。
- [ADR 0157](../adr/0157-check-wasmtime-pin-against-advisories.md) のステータスの行は `採択→範囲、修正版、パッケージの読み方は ADR 0166`、[ADR 0166](../adr/0166-read-wasmtime-advisory-ranges-as-written.md) は `採択` である。

### 所見

**F-03（範囲外の変更、低）：`scripts/ci/test.sh` に、`advisories.yml` の静的な検査が四つ足された。**
ADR はワークフローの自動テストを定めず、`workflow_dispatch` で一度動かして確かめるとした。
PR #553 は、`advisories.yml` の存在、`schedule` と `workflow_dispatch` だけで動くこと、`write` の権限がないこと、`GH_TOKEN` とスクリプトの行を検査する四つを足した（[ci/test.sh#L1403-L1413](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/scripts/ci/test.sh#L1403-L1413)）。
ほかのワークフローの ADR（[docs/adr/0097](../adr/0097-ci-same-path-before-build-and-env-check-runner.md)、[0154](../adr/0154-scripts-macos-tests-at-once-with-deadline.md) など）と同じ形の検査で、ADR の決定を固定する側に働く。
PR の本文に書かれており、害はない。

**F-04（記録、低）：[ADR 0166](../adr/0166-read-wasmtime-advisory-ranges-as-written.md) の文脈は `vulnerabilities` の要素を 137 と書くが、fixture と API はどちらも 133 である。**
2026-11-05 の API の応答と、コミットした fixture の 86 件の ID と各アドバイザリの要素の数は一致し、要素の和は 133 だった。
0166 の 25 件の一覧と 49.0.5 の結果はこの監査で再現したので、数の違いは ADR の文の誤りであり、実装には影響しない。
コミット済みの ADR は書き換えないので、ここに記録する。

## [ADR 0158](../adr/0158-svg-external-references-beyond-href.md): G08014 の検査を、属性の値の CSS、処理命令、XHTML の要素、接頭辞つきの `attributeName` に広げる

### 適合を確かめたもの

- `Golem.Svg.Active` は、対象が `xml-stylesheet`（大文字と小文字を問わない）の処理命令を文書のどこにあっても拾い（[Active.hs#L56-L57](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/modules/golem-svg/src/Golem/Svg/Active.hs#L56-L57)）、名前空間が XHTML の要素を拒み、`set` と `animate` の `attributeName` の局所名（最後の `:` の後）が `href` か `on` で始まるものを拒む（[同#L66-L73](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/modules/golem-svg/src/Golem/Svg/Active.hs#L66-L73)）。すべての属性の値に `cssRefs` を当て、`@import`、`#` で始まらない `url(`、`image-set(` を、エスケープを解き注釈を除いて探す（[同#L88-L89](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/modules/golem-svg/src/Golem/Svg/Active.hs#L88-L89)、[同#L124-L129](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/modules/golem-svg/src/Golem/Svg/Active.hs#L124-L129)）。
- `Golem.Svg.Xml` に `NInstruction !Text !Pos`、`Document { docRoot, docInstructions }`、`parseXmlDocument` があり、`parseXml = docRoot <$> parseXmlDocument` で型は変わっていない（[Xml.hs#L60-L72](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/modules/golem-svg/src/Golem/Svg/Xml.hs#L60-L72)、[同#L85-L86](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/modules/golem-svg/src/Golem/Svg/Xml.hs#L85-L86)）。XML の宣言は処理命令に含めない。
- golem-svg の `ActiveSpec` に ADR のテスト設計の十二の場合（表現の六つの属性、`url(#g)` と `URL( '#g' )`、エスケープ、`image-set(` と `-webkit-image-set(`、先頭と要素の中と大文字の `xml-stylesheet`、`xpacket` と XML の宣言、`set` の `to`、`q:href` と `Q:HREF`、`h:img`、Inkscape と RDF、文書の順）、XML の読み手のテストに処理命令を含む SVG と含まない SVG の比較と描画の一致、golem-driver の `FigureSpec` に監査の CLI の再現と同じ SVG で HTML と EPUB が G08014 になり書かれないこと、処理命令で PDF が変わらないことのテストがある。golem-svg-test はこの監査で通った。PR #546 は、新しい `ActiveSpec` の 12 件のうち 9 件と driver の 1 件が main で失敗し、XML の読み手のテストは `NInstruction` がないためコンパイルできなかったことを申告している。
- 仕様書の図版の節の表は ADR の表と同じ八行で、四つの注も ADR のとおりである（[specifications.md#L1959-L1972](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/docs/specifications.md#L1959-L1972)）。docs/diagnostics.md の G08014 の節（[diagnostics.md#L6967-L6968](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/docs/diagnostics.md#L6967-L6968)）、利用者のマニュアルの図版の章と付録、開発者のマニュアルの表（[07-modules.gm#L89-L93](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/manual-dev/part2/07-modules.gm#L89-L93)）、golem-svg の仕様書（[golem-svg/specifications.md#L11-L12](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/docs/golem-svg/specifications.md#L11-L12)）に `NInstruction` と `parseXmlDocument` がある。roadmap の「G08014 の表にない外部の参照」の項目は消えている（「セキュリティ監査の残り」の見出しは PR #549 が消した）。
- セキュリティ監査の [svg-probe.hs](2026-11-05-evidence/svg-probe.hs) をこの監査で再実行すると、`presentation-url` と `animated-style` が `url()`、`stylesheet-pi` が `xml-stylesheet`（1 行 1 桁）を返し、対照の二つは変わらなかった。[cli-probe.sh](2026-11-05-evidence/cli-probe.sh) の二つめの試験は、終了コード 1、`G08014`（`test.svg:1:1（xml-stylesheet）ほか 1 件`）、`SVG preserved: False` になった。
- [ADR 0158](../adr/0158-svg-external-references-beyond-href.md) のステータスの行は `採択` である。

### 所見

**F-05（逸脱、申告あり、低）：逆斜線も `/` も、`@import`、`url(`、`image-set(` のどれも含まない属性の値は、CSS の字句として読まずに通す。**
ADR は「値は、今の `style` の属性と同じく CSS の字句として読む」とした。
実装は `mayRefer` で、値に `\` か `/` があるか、小文字に直した値が三つの語のどれかを含むときだけ `cssRefs` を当てる（[Active.hs#L102-L105](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/modules/golem-svg/src/Golem/Svg/Active.hs#L102-L105)）。
CSS の字句解析が文字列を変えるのはエスケープ（`\` で始まる）と注釈（`/*`）だけで、文字列の中の `\` と改行を落とすのも `\` を要するので、`\` も `/` もない値の字句は値そのものであり、結果は読んだときと同じである。
`path` の `d` のような長い値を読まないための近道で、PR #546 と golem-svg の仕様書に書かれている。
妥当である。
ただし、この等価性を直に確かめるテストはなく、エスケープの `u\72l(` のテストが間接に確かめるだけである。

**F-06（範囲外の観察、低）：セキュリティ監査の [cli-probe.sh](2026-11-05-evidence/cli-probe.sh) の三つめの試験（出力先のガード）は、G08014 で止まるようになり、ガードを確かめなくなった。**
probe は二つめの試験で `chapters/01.gm` に SVG の図版を足し、三つめの試験でそのまま `build` をシンボリックリンクにして走らせる。
0158 の後は二つめの SVG が G08014 で止まるので、三つめの出力は `output guard: False sentinel: unchanged` になる。
G08014 は出力先に触れる前に出るので、sentinel が `unchanged` であることは G08013 の働きを示さない。
この監査で、同じ fixture に SVG を足さずに `build` をシンボリックリンクにして `golem build --target html` を走らせると、`G08013`、終了コード 1、sentinel は `unchanged` で、ガードは働いている。
監査の記録と probe はコミット後に変えないので、次に probe を使うときは、三つめの試験の前に SVG の図版を取り除くか、三つめを別の fixture で行う必要がある。

## [ADR 0159](../adr/0159-unwritable-characters-in-csl-json.md): CSL-JSON の出力に書けない文字を、参考文献のファイルを読むときに G03108 で拒む

### 適合を確かめたもの

- `Golem.Doc.Bibliography.Csl` の `CslJsonError` に `CslUnwritable Char Text Int` があり、`decodeCslJson` は JSON として読めた配列に `unwritables` を当て、最初の文字、JSON Pointer、ほかの件数を返す（[Csl.hs#L30-L48](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/modules/golem-doc/src/Golem/Doc/Bibliography/Csl.hs#L30-L48)）。たどる順は配列の添字の順、オブジェクトは `sortOn` でキーの符号位置の順、キーをその値より先に見る。`~` と `/` は `~0` と `~1` である（[同#L55-L69](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/modules/golem-doc/src/Golem/Doc/Bibliography/Csl.hs#L55-L69)）。`firstUnwritable` は golem-syntax のもので、golem-doc の build-depends は変わっていない。
- `Golem.Driver.loadBibliography` は `CslUnwritable` を、`manifest.toml` の先頭の G03108 のエラーにし、メッセージは `参考文献のファイルに出力に書けない文字（<符号位置>）があります: <パス>（<JSON Pointer>）[、ほか <n> 件]` である（[Driver.hs#L598-L609](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/modules/golem-driver/src/Golem/Driver.hs#L598-L609)）。G03026 と同じく、そのファイルの項目は一つも使わない。
- golem-doc の `CslSpec` にテスト設計の七つの場合（`/0/title`、ESC・NUL・U+FFFE・U+FFFF、`note` と `abstract`、キー、`~1` と `~0`、二つの項目と `author` の順、通るもの）、golem-driver の `ReferencesSpec` に監査の再現と同じ入力で HTML と EPUB が dev と prod で G03108 になり書かれないこと、`--target pdf` と `--target text`、引用されない項目の `ほか 1 件`、golem-lsp に `manifest.toml` の G03108 がある。golem-doc-test はこの監査で通った。PR #549 は、`CslSpec` がコンパイルできず、driver の三つと lsp の一つが main で失敗したことを申告している。
- docs/diagnostics.md に G03108 の節があり、G02089 と G03028 の節から相互に示されている（[diagnostics.md#L4780-L4816](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/docs/diagnostics.md#L4780-L4816)、[同#L3067](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/docs/diagnostics.md#L3067)、[同#L4702](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/docs/diagnostics.md#L4702)）。仕様書の出力に書けない文字の節と参考文献の節（[specifications.md#L388](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/docs/specifications.md#L388)、[同#L2809-L2820](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/docs/specifications.md#L2809-L2820)）、glossary、利用者のマニュアルの manifest の章と付録 E、roadmap の「CSL-JSON の制御文字」の項目の削除。
- G03108 の番号は、docs/diagnostics.md に G03101 から G03107 がなく、その番号を使うのは破棄した 0149 と 0150 だけであることを確かめた。ADR の説明のとおりである。
- セキュリティ監査の [cli-probe.sh](2026-11-05-evidence/cli-probe.sh) の一つめの試験は、終了コード 1、`manifest.toml:1:1: error[G03108]: … refs.json（/0/title）` と六つの G02021 になり、HTML と EPUB は書かれなかった。
- [ADR 0159](../adr/0159-unwritable-characters-in-csl-json.md) のステータスの行は `採択` である。

### 所見

**F-07（逸脱、申告あり、低）：golem-doc の仕様書がないので、CSL-JSON の読み方の検査は docs/specifications.md の参考文献の節に書かれた。**
ADR は「golem-doc の仕様書の CSL-JSON の読み方に、検査を書く」としたが、`docs/golem-doc/` には `adr/` しかない。
PR #549 はこれを申告し、仕様書の参考文献の節に、たどる順、キーを先に見ること、`CslUnwritable` と `loadBibliography` の役割まで書いた（[specifications.md#L2809-L2820](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/docs/specifications.md#L2809-L2820)）。
妥当である。
同じ PR は、利用者のマニュアルの参考文献の節の追記を一文に縮めている（コミット 02c7bf49）。ADR は「G03108 を書く」とだけ定めており、一文で足りる。

## [ADR 0117](../adr/0117-watchdog-outside-the-runtime-for-threaded-tests.md): golem-driver-parallel-test に、Haskell のランタイムの外で実時間を測る見張りを付ける

### 適合を確かめたもの

- `Golem.TestSupport.Watchdog` は `watchTests :: Integer -> TestTree -> TestTree` と `watchedName :: [TestName] -> TestName -> String` を公開し、`watchTests` は tasty の六つの構成子（`SingleTest`、`TestGroup`、`PlusTestOptions`、`WithResource`、`AskOptions`、`After`）をすべて辿って `SingleTest` だけを包み、木の形、名前、オプション、資源、依存を変えない（[Watchdog.hs#L81-L90](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/modules/golem-test-support/src/Golem/TestSupport/Watchdog.hs#L81-L90)）。包んだテストは `bracket` で始まりに名前を登録し、値でも例外でも終わりに消す。最初のテストが見張りを起こし、0.1 秒ごとの心拍の Haskell のスレッドを立てる（[同#L59-L67](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/modules/golem-test-support/src/Golem/TestSupport/Watchdog.hs#L59-L67)）。四つの C の関数は `capi unsafe` で呼ぶ。
- `cbits/golem_watchdog.c` の include は `pthread.h`、`stdio.h`、`stdlib.h`、`string.h`、`time.h`、`unistd.h` だけである（[golem_watchdog.c#L15-L20](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/modules/golem-test-support/cbits/golem_watchdog.c#L15-L20)）。見張りのスレッドは 1 秒ごとに表を読み、上限を超えたテストがあるか、走っているテストがなく最後の変化から上限を超えたときに、`write(2)` で ADR の五種の行（上限を超えたテスト、ほかに走っているテスト、テストなし、心拍と `(it is stuck, not only the tests)`、`aborting the process`）を書いて `abort()` する（[同#L56-L104](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/modules/golem-test-support/cbits/golem_watchdog.c#L56-L104)）。上限はプロセスで最初の値に固定される（[同#L109-L126](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/modules/golem-test-support/cbits/golem_watchdog.c#L109-L126)）。
- golem-test-support のライブラリの build-depends は変わらず、`c-sources` と `include-dirs` が足され、テストのスイートに `process` が足された（[golem-test-support.cabal#L36-L38](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/modules/golem-test-support/golem-test-support.cabal#L36-L38)、[同#L57](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/modules/golem-test-support/golem-test-support.cabal#L57)）。golem-\* のあいだの依存は変わっていない。
- `ParallelMain` は木全体を `watchTests (300 * toInteger race)` で包む（[ParallelMain.hs#L14](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/modules/golem-driver/test/ParallelMain.hs#L14)）。
- golem-test-support-test は、`GOLEM_WATCHDOG_CHILD` で自分を子として走らせ、`waits`、`holds`（`sleep(60)` を `unsafe` で呼ぶ）、`stays`、`ends`、`watchedName` の五つを確かめる（[test/Main.hs#L43](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/modules/golem-test-support/test/Main.hs#L43)、[同#L382-L392](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/modules/golem-test-support/test/Main.hs#L382-L392)）。この監査で golem-test-support-test と golem-driver-parallel-test（`-threaded`、`-N`）が通った。PR #548 は、見張りを外した実装で三つが 60 秒で正常に終わって落ちたこと、上限を 2 秒にした手の確かめ（終了コード 134、走っていた二つの名前、心拍 0.1 秒）を申告している。
- 仕様書の golem-test-support の段落（[specifications.md#L239-L240](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/docs/specifications.md#L239-L240)）、CONTRIBUTING.md と CONTRIBUTING.en.md のテストの節（[CONTRIBUTING.md#L232-L233](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/CONTRIBUTING.md#L232-L233)、[CONTRIBUTING.en.md#L215](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/CONTRIBUTING.en.md#L215)）、開発者のマニュアルの時間の上限の段落（[09-adr.gm#L36-L38](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/manual-dev/part2/09-adr.gm#L36-L38)）。[ADR 0117](../adr/0117-watchdog-outside-the-runtime-for-threaded-tests.md) のステータスの行は `採択` である。

所見はない。

## [ADR 0155](../adr/0155-split-aarch64-test-runner.md): aarch64 の build のテストを、x86-64 と同じく二つのランナーに分ける

### 適合を確かめたもの

- `build` の行列は、`ubuntu-24.04` の `tests-driver`、`tests-rest`、`outputs`、`env` と、`ubuntu-24.04-arm` の `tests-driver`（`suites: driver`、`save: true`）、`tests-rest`（`suites: rest`、`save: false`）、`outputs` の七行で、各行の `tests`、`outputs`、`env` は ADR のとおりである（[ci.yml#L150-L170](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/.github/workflows/ci.yml#L150-L170)）。`scripts/ci/test-suites.sh` は変わっていない。生成したパーサーの検査の条件は `matrix.tests && matrix.suites != 'driver'` のままである。
- `scripts/ci/test.sh` に、七行の行列の検査と、`save: true` がアーキテクチャごとにちょうど一つであることの検査がある（[ci/test.sh#L819-L830](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/scripts/ci/test.sh#L819-L830)）。PR #539 は、検査だけのコミットで行列の検査が main に対して失敗したことを申告している。
- README の `build` の行（[README.md#L377](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/README.md#L377)）と開発者のマニュアルの CI の章（[11-ci-jobs.gm#L110](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/manual-dev/part2/11-ci-jobs.gm#L110)、[同#L118-L130](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/manual-dev/part2/11-ci-jobs.gm#L118-L130)）。
- 計測の記録 [docs/ci-timings/2026-11-05-split-aarch64-tests.md](../ci-timings/2026-11-05-split-aarch64-tests.md) がある。この監査で、二回目の実行 41887380664 のログから `Test suite …: PASS` の行を数えると、aarch64 の `tests-driver` が 3、`tests-rest` が 25、x86-64 も 3 と 25 で、両方のアーキテクチャの和が同じ 28 だった（ADR を書いた時点の 26 から、その後のスイートの追加で 28 になっている）。
- [ADR 0155](../adr/0155-split-aarch64-test-runner.md) のステータスの行は `採択` である。

### 所見

**F-08（記録、低）：計測の記録は実装のプルリクエストの 2 回の実行だけで、ADR の「3 回の実行と、その後の `main` への push の実行」に足りない。**
記録は 41886607899 と 41887380664 の二行である。
この監査で、マージの後の main の実行 41889606653（19d0ec3e）を取ると、aarch64 の `tests-driver` の手順は 38 秒、`tests-rest` は 59 秒で、記録の 39 秒と 63〜65 秒と同じ範囲だった。
結論（80〜103 秒の一つが 39 秒と 63〜65 秒の二つになり、aarch64 が `build` の最後でなくなった）は変わらない。
前回の監査の F-04 と同じ形である。

## [ADR 0163](../adr/0163-build-visual-pdfs-in-parallel.md): 見た目の回帰テストの PDF を、入力ごとに並べて組む

### 適合を確かめたもの

- `scripts/visual/build.sh` は、プロジェクトの写しを先に作り、`job` で背景のプロセスとして組む。同時に動く数の上限は `getconf _NPROCESSORS_ONLN`（取れないか数でなければ 1）で、二つのマニュアルを一つのジョブとして最初に始め、15 の入力を続ける（[build.sh#L68-L106](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/scripts/visual/build.sh#L68-L106)、[同#L171-L181](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/scripts/visual/build.sh#L171-L181)）。失敗のときの出力（`job-<名前>.log`）と見つけた PDF の一覧（`pdfs-<名前>`）は入力ごとのファイルで、`finish` はすべてのジョブを待ってから、失敗したジョブの出力を始めた順に標準エラー出力に書き、終了コード 1 で終える。`--list`、出力のファイルの名前、マニュアルの固定のコミットとタグは変わっていない。`ci.yml` は変わっていない。
- `scripts/visual/test.sh` に、遅い偽の golem と偽の `getconf`（3）で、17 の PDF がそれぞれ自分の入力のものであること、同時に動く数が 2 以上 3 以下であること、一つの入力の失敗がほかの 16 の終わりの後に終了コード 1 になることの検査がある（[visual/test.sh#L738-L774](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/scripts/visual/test.sh#L738-L774)）。PR #543 は、main に対して同時性と失敗の順の 2 件が失敗したことを申告している。150 件がこの監査で通った。
- 計測の記録 [docs/ci-timings/2026-11-05-visual-pdfs-in-parallel.md](../ci-timings/2026-11-05-visual-pdfs-in-parallel.md) は、前の 6 回と後の 2 回を書き、PDF を組む手順が 42〜57 秒から 27 秒と 32 秒になったこと、`visual` が二回とも参照のまま通ったこと、手元で 17 の PDF がバイト単位で一致したことを書く。
- [ADR 0163](../adr/0163-build-visual-pdfs-in-parallel.md) のステータスの行は `採択` である。

所見はない。

## [ADR 0164](../adr/0164-explain-dedup-and-plugin-code-messages.md): `golem explain` の重複の除き方と、プラグインのコードの形の誤りの文を、誤りの場所ごとに決める

### 適合を確かめたもの

- `dedupKey` は `/` を含む引数をそのまま、含まない引数を大文字に直した値とし、`explain` は `nubOrdOn dedupKey` で重複を除く（[cli/Main.hs#L182-L185](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/modules/golem-cli/app/Main.hs#L182-L185)、[同#L270](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/modules/golem-cli/app/Main.hs#L270)）。`pluginCode` は ADR のデータ構造の節のコードと同じ順（`/` の数、`/` の前、`/` の後）で三つの文を選ぶ（[同#L165-L175](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/modules/golem-cli/app/Main.hs#L165-L175)）。golem-cli.cabal は変わっていない。
- 実機で、ADR の表の四行（`X/A x/a` と `x/a X/A` がどちらも `x/a` の一行と `X/A` の 3 の文で終了コード 2、`lk/x LK/x` が二行と空行で 0、`nope NOPE` が `nope` の文で 2）と、テスト設計のすべての引数（`a/b/c`、`x/a/`、`/a/b` が 1 の文、`x /a`、`/a`、`x y/A`、`/A` が 2 の文、`x/A`、`x/404`、`G01017/` が 3 の文、`x/a x/a` が一行で 0、`G01017/x` が一行で 0）が ADR のとおりだった。
- golem-cli の `explainTests` に `pluginCodeOrderTests` があり、`badPluginCode` は文の後半を引数に取る形に改まっている（[test/Main.hs#L376](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/modules/golem-cli/test/Main.hs#L376)、[同#L397-L409](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/modules/golem-cli/test/Main.hs#L397-L409)）。golem-cli-test はこの監査で通った。PR #544 は新しい場合の 4 件が main で失敗したことを申告している。
- 仕様書のプラグインの節の三つの文と順（[specifications.md#L3233-L3236](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/docs/specifications.md#L3233-L3236)）、CLI の表の行（[同#L3262](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/docs/specifications.md#L3262)）、README の表の行（[README.md#L88](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/README.md#L88)）、開発者のマニュアルの箇条（[01-cli.gm#L133](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/manual-dev/part1/01-cli.gm#L133)）。[ADR 0151](../adr/0151-explain-uses-plugin-code-rule.md) と [golem-cli ADR 0009](../golem-cli/adr/0009-explain-several-codes.md) のステータスの行の句は ADR のとおりで、[ADR 0164](../adr/0164-explain-dedup-and-plugin-code-messages.md) のステータスの行は `採択` である。
- 前回の監査の F-05 と F-06 は閉じている。

所見はない。

## [ADR 0165](../adr/0165-wait-pdfs-finds-the-job-under-a-caller-prefix.md): wait-pdfs.sh は、呼び出し元の接頭辞のついたジョブの名前でも待つジョブを見つける

### 適合を確かめたもの

- `wait-pdfs.sh` は、ジョブの一覧を `--jq '.jobs[] | [.name, .status] | @tsv'` の行で受け取り、`awk` で、名前が `JOB` と一致するか ` / JOB` で終わるものを選ぶ。0 件なら今までの一行、2 件以上なら当たった名前をすべて標準エラーに書いて終了コード 1、1 件ならその状態で今までの判定をする（[wait-pdfs.sh#L32-L58](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/scripts/visual/wait-pdfs.sh#L32-L58)）。冒頭の注釈に照合の規則がある。`ci.yml` の `visual` の引数と `release.yml` は PR #551 で変わっていない。
- `scripts/visual/test.sh` の偽の `gh` は `FAKE_JOBS` の行からジョブを作り、呼び出しの `--jq` を実際に `jq` で当てる。実行 41918079466 の名前の一覧（`completed` で成果物なし、`in_progress` で二回目に成果物）、`a / b / JOB`、`xbuild …` と `… / x` だけ、二つが当たる一覧、`-arm` だけの一覧の検査がある（[visual/test.sh#L446-L470](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/scripts/visual/test.sh#L446-L470)）。
- 開発者のマニュアルの `visual` の節に `ci / ` の一文がある（[11-ci-jobs.gm#L248](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/manual-dev/part2/11-ci-jobs.gm#L248)）。
- 手で確かめることのうち、#547 と #551 がともに main に入った後の `release.yml` の `workflow_dispatch` の実行 41934030359 で、`ci / visual` は `ci / build (ubuntu-24.04, outputs)` を待って 1 分 40 秒で成功し、`ci / ci`、`determinism`、三つの `smoke`、`notes` が成功した。実行の番号は PR #551 の本文にある。`pull_request` の `visual` は、その後の十三のプルリクエストでも通っている。
- [ADR 0165](../adr/0165-wait-pdfs-finds-the-job-under-a-caller-prefix.md) のステータスの行は `採択` である。

### 所見

**F-09（記録、申告あり、低）：ADR が「今の実装でも通る」とした二つの項目は、古い実装で失敗した。**
ADR のテスト設計は、`a / b / JOB` が見つかることと、二つが当たる一覧で失敗することを「今の実装でも通るが、規則を固定する項目」に置いた。
古い実装は `jq` で `.name == JOB` の完全一致だけを選ぶので、`a / b / JOB` は「ジョブがない」になり、二つが当たる一覧では最初のものを選んで待ち続ける（偽の `gh` の 21 回目の問い合わせの失敗で止まる）。
ADR の文脈は、偽の `gh` が `--jq` を当てていなかったため名前の照合そのものがテストされていなかったと正しく指摘しながら、古い実装の振る舞いの見積もりを誤った。
PR #551 がこれを申告しており、テストを先に失敗させる手順としてはむしろ強い。

## [ADR 0167](../adr/0167-leave-cache-restore-failures-as-misses.md): キャッシュの復元が egress の上限で失敗しても、再試行もタイムアウトの変更もしない

### 適合を確かめたもの

- PR #555 はワークフローを変えず、`docs/roadmap.md` の「課題にしなかった事項」に一行を足した。警告の文、実行の番号、手を加えない理由、見直す条件（7 日のうちに二つ以上の実行）、ADR へのリンクがある（[roadmap.md#L261](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/docs/roadmap.md#L261)）。
- textlint と `adr-guard links` はこの監査でも通った。[ADR 0167](../adr/0167-leave-cache-restore-failures-as-misses.md) のステータスの行は `採択` である。

所見はない。

## [ADR 0168](../adr/0168-render-visual-pdfs-side-by-side-with-shem-jobs-1.md): 見た目の回帰テストで、PDF を並べて描き、shem に `--jobs 1` を渡す

### 適合を確かめたもの

- `scripts/visual/check.sh` は、PDF のある入力をバイト数の大きい順（同じなら名前の順）に並べ、`getconf _NPROCESSORS_ONLN`（取れなければ 1。`build.sh` と同じ決め方）を上限に背景で描く。各 shem は `--jobs 1` で、入力ごとのディレクトリに描き、ページの SHA-256 の一覧、標準エラー出力、終了コードを入力ごとのファイルに書く（[check.sh#L74-L89](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/scripts/visual/check.sh#L74-L89)、[同#L97-L118](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/scripts/visual/check.sh#L97-L118)）。`check: rendering <入力>` は描き始めるときに標準エラー出力に書く。すべて描き終えてから入力の一覧の順に結果を読み、`missing`、`unreadable`、`unlisted`、`changed`、`added`、`removed`、`stale` の行と `--accept`、`--lists` の処理は今までの順である（[同#L122-L156](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/scripts/visual/check.sh#L122-L156)）。上限を変える環境変数はない。`ci.yml`、600 秒の上限、`report.sh` は変わっていない。
- `scripts/visual/test.sh` に、すべての `render` が `--jobs 1` を持つこと（引数は 9）、遅い偽の shem と偽の `getconf`（3）で同時に動く数が 2 以上 3 以下であること、描き終える順が逆でも標準出力が main の `check.sh` の出力（テストに固定）と一致すること、`--accept` と `--lists`、17 の入力の名前が一度ずつ出ることの検査がある（[visual/test.sh#L233](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/scripts/visual/test.sh#L233)、[同#L328-L358](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/scripts/visual/test.sh#L328-L358)）。PR #557 は main に対して 4 件が失敗したことを申告している。
- 仕様書の見た目の回帰テストの節（[specifications.md#L579-L580](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/docs/specifications.md#L579-L580)）、開発者のマニュアルの決定性の章（`--jobs 1` の描き方、止まったときの読み方、CI の比べる手順の時間を 216 秒から測った値に直したこと。[12-determinism.gm#L227-L231](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/manual-dev/part2/12-determinism.gm#L227-L231)）と CI の章。`scripts/visual/pages/manual-dev.txt` の変わった行は、PR #557 が `visual-diff` の画像を見て受け入れたと申告している。
- 計測の記録 [docs/ci-timings/2026-11-05-visual-pdfs-side-by-side.md](../ci-timings/2026-11-05-visual-pdfs-side-by-side.md) は、CI の 2 回（比べる手順が 3 秒と 4 秒）、手元の交互の 3 回ずつ（2.34〜2.53 秒が 1.46〜1.53 秒）、二つの `check.sh` の標準出力が一致したこと、描き始めた順が大きさの順だったことを書く。
- [ADR 0094](../adr/0094-visual-regression-page-hashes-at-72-dpi.md)、[0095](../adr/0095-visual-job-in-ci.md)、[0100](../adr/0100-raise-shem-to-v0-1-0-rc3-and-pre-release-bumps.md) のステータスの行の句は ADR の指示と一字一句同じで、[ADR 0168](../adr/0168-render-visual-pdfs-side-by-side-with-shem-jobs-1.md) のステータスの行は `採択` である。

所見はない。
描いたページの決定性は、shem の約束（出力は `--jobs` によらない）と、入力ごとのディレクトリに描くこと、結果を入力の順に読むことで保たれる。この監査は `check.sh` そのものを手元の PDF に対しては実行しておらず、記録の二回の CI と手元の一致、テストの固定した出力で確かめた。

## ADR のないプルリクエスト

### PR #547: `release.yml` の `ci` ジョブに `actions: read` を与える

- `release.yml` の `ci` ジョブは `permissions: contents: read, actions: read` を持ち、ほかのジョブは変わっていない（[release.yml#L27-L34](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/.github/workflows/release.yml#L27-L34)）。`ci.yml` の `visual` が求める権限と同じである。
- PR の本文は、[docs/adr/0096](../adr/0096-before-and-after-images-of-changed-pages.md) が `visual` の `actions: read` を決めたが呼び出し元の付与を決めていないこと、ADR がないことを申告し、同時に見つけた二つめの失敗（ジョブの名前）を [ADR 0165](../adr/0165-wait-pdfs-finds-the-job-under-a-caller-prefix.md) に委ねた。0165 の文脈はこれを引き取っている。
- 実行 41917899773（main の 708263da、`startup_failure`）、41918079466（#547 の枝、`visual` の名前で失敗）、41934030359（main の 15d98089、成功）の三つの実行が、本文の記述と一致する。

**F-10（運用、低）：ADR のない `release.yml` の変更が、申告つきでマージされた。**
0096 の実装（51ca9d55、2026-10-27）から #547 まで、`release.yml` のすべての実行は `startup_failure` で、v0.1.0-rc3 の後にタグを押しても下書きのリリースは作られなかった。
ADR なしの変更は方針に反するが、権限の一行の修正で、PR の本文が範囲と理由を書き、[ADR 0165](../adr/0165-wait-pdfs-finds-the-job-under-a-caller-prefix.md) の文脈が記録している。
セキュリティ監査の H-02（外部の action をタグで参照すること）は、この PR も [ADR 0156](../adr/0156-wasmtime-49-0-5.md) も扱っておらず、残る。

### PR #552: shem を v0.1.0-rc4 に上げる（[ADR 0100](../adr/0100-raise-shem-to-v0-1-0-rc3-and-pre-release-bumps.md) の手順）

- `scripts/visual/fetch-shem.sh` は `VERSION=0.1.0-rc4` で、三つの SHA-256 は、この監査で取った release の API の `digest` と `SHA256SUMS` の三行と一致する（[fetch-shem.sh#L31-L36](https://github.com/tett23/golem/blob/645a739f1bbea5d344061d2a00d29fe4f87e9834/scripts/visual/fetch-shem.sh#L31-L36)）。
- 0100 の「pre-release の識別子を変える版上げ」のとおり、仕様書と開発者のマニュアルの固定した版の名前が `v0.1.0-rc4` になり、rc3 と rc4 で描いたページの SHA-256 の違いがないこと、変わった参照が版の名前を含む `manual-dev` の一ページだけであることが本文にある。計測の記録 [docs/ci-timings/2026-11-05-shem-rc4.md](../ci-timings/2026-11-05-shem-rc4.md) がある。`check.sh` の描き方は PR #552 では変えておらず、変えたのは後の [ADR 0168](../adr/0168-render-visual-pdfs-side-by-side-with-shem-jobs-1.md) である。
- 所見はない。

## セキュリティ監査と前回の監査の所見の現状

| 番号 | 現状 |
| --- | --- |
| V-01（wasmtime 49.0.2 の aarch64 のサンドボックス逸脱） | [ADR 0156](../adr/0156-wasmtime-49-0-5.md)（#545）が 49.0.5 に上げ、組んだ `golem` と三つの配布物が 49.0.5 とリンクしていることを `check-wasmtime-linked.sh` が確かめる。[ADR 0157](../adr/0157-check-wasmtime-pin-against-advisories.md) と [0166](../adr/0166-read-wasmtime-advisory-ranges-as-written.md)（#553）が毎日の照合を足し、2026-11-05 の API に対して 49.0.5 は当たらない。公開済みの rc1 から rc3 の配布物は脆弱なまま残り、ノートの注意はまだない（F-01） |
| V-02（SVG の外部参照が G08014 を通る） | [ADR 0158](../adr/0158-svg-external-references-beyond-href.md)（#546）が直した。svg-probe.hs の三つの形はすべて検出され、cli-probe.sh の SVG は G08014 で写されない |
| V-03（CSL-JSON の制御文字が XHTML に残る） | [ADR 0159](../adr/0159-unwritable-characters-in-csl-json.md)（#549）が直した。cli-probe.sh は G03108 と終了コード 1 になり、HTML と EPUB は書かれない |
| H-01（取得と Wasm コンパイルの資源上限） | 残る。対象の ADR はない |
| H-02（CI の外部 action の可変タグ参照） | 残る。対象の ADR はない |
| 前回の F-05、F-06 | [ADR 0164](../adr/0164-explain-dedup-and-plugin-code-messages.md)（#544）が直した。重複の除き方と形の誤りの文は実機で ADR のとおり |
| 前回の F-15 | 残る。`scripts/ci/test.sh` は GNU の awk で `escape sequence '\('` の警告を二行出す |

## 横断的な所見

**運用**：十三のプルリクエストは、どれも最終コミットの `ci` の check-run が成功した後にマージされた（3 秒から 80 分前）。前回の監査の F-13 は繰り返されていない。

**手で確かめることの実行**：CI とリリースの ADR（0155、0156、0157、0163、0165、0168）は、どれも手で確かめること（`workflow_dispatch` の実行、計測の記録）を実際に行い、`docs/ci-timings/` か PR の本文に残した。0156 の過去のリリースのノートだけが行われていない（F-01）。0155 の記録は ADR の求めた回数に足りない（F-08）。

**build-depends**：十三のプルリクエストで、golem-\* のパッケージのあいだの依存は変わっていない。golem-test-support のテストのスイートに足した `process` は、[ADR 0117](../adr/0117-watchdog-outside-the-runtime-for-threaded-tests.md) が明示したものである。

**申告の質**：申告された逸脱（F-02、F-05、F-07、F-09）はどれも妥当である。申告のない所見は F-01（中）、F-03、F-04、F-06、F-08、F-10（低）で、F-01 は PR の本文が「メンテナーに任せる」と書いたが、ADR にその委任はない。

**セキュリティ監査の probe**：二つの probe は監査の記録のままで、変える対象ではない。svg-probe.hs は変更の前後で結果が変わることを目的のとおり示した。cli-probe.sh の三つめの試験は、二つめの試験の入力が残るため、0158 の後は出力先のガードを確かめられない（F-06）。

## 要約表

| 番号 | 所見 | 分類 | 重大度 | 根拠 |
| --- | --- | --- | --- | --- |
| F-01 | v0.1.0-rc1、rc2、rc3 のリリースのノートに GHSA-mghf-wjfp-p5xm の注意がない | 未実装 | 中 | [ADR 0156](../adr/0156-wasmtime-49-0-5.md)「配布物と過去のリリース」、`gh release view` |
| F-02 | `wasmtime-licenses.sh` の `archive_sha` を ADR の指示の外で変えた | 逸脱（申告あり） | 低 | wasmtime-licenses.sh#L68-L74 |
| F-03 | `scripts/ci/test.sh` に `advisories.yml` の静的な検査を足した | 範囲外の変更 | 低 | ci/test.sh#L1403-L1413 |
| F-04 | [ADR 0166](../adr/0166-read-wasmtime-advisory-ranges-as-written.md) の `vulnerabilities` の要素の数 137 は、fixture と API の 133 と違う | 記録 | 低 | scripts/testdata/wasmtime-advisories.json、API |
| F-05 | `\` も `/` も三つの語も含まない属性の値は CSS として読まない | 逸脱（申告あり） | 低 | Active.hs#L102-L105 |
| F-06 | cli-probe.sh の三つめの試験は G08014 で止まり、出力先のガードを確かめない | 範囲外の観察 | 低 | cli-probe.sh、実機 |
| F-07 | golem-doc の仕様書がなく、検査の記述は docs/specifications.md にある | 逸脱（申告あり） | 低 | specifications.md#L2809-L2820 |
| F-08 | 0155 の記録が 2 回の実行で、main の実行がない | 記録 | 低 | 2026-11-05-split-aarch64-tests.md、実行 41889606653 |
| F-09 | 0165 が「今の実装でも通る」とした二つの項目は古い実装で失敗した | 記録（申告あり） | 低 | PR #551 |
| F-10 | ADR のない `release.yml` の権限の変更 | 運用（申告あり） | 低 | release.yml#L27-L34、PR #547 |

高の所見はない。
中の所見は F-01 の一つで、[ADR 0156](../adr/0156-wasmtime-49-0-5.md) の実装のうち公開済みのリリースのノートへの注意だけが残っている。
セキュリティ監査の V-01、V-02、V-03 と前回の監査の F-05、F-06 は、五つの ADR で閉じた。
H-01 と H-02 は残る。
