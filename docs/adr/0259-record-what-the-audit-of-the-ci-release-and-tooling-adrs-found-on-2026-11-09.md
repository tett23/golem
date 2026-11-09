# ADR 0259: 2026-11-09 の CI、リリース、ツールの ADR の監査で見つかった、判断の要る点を記録する

ステータス: 採択

## 文脈

2026-11-09 に、[ADR 0230](0230-check-the-release-workflow-and-ci-history-by-scripts.md) から [ADR 0248](0248-move-the-css-cascade-of-the-tests-into-golem-test-support.md) の実装を、ADR の文と照らし合わせた（origin/main `a8ad416c`）。
対象は CI、リリース、ツール、wasm、ブラウザ、文書の手順の ADR である。
[ADR 0236](0236-record-what-implementations-decided-found-by-the-second-review-of-2026-11-08.md) と同じく、ADR の決めたことからの逸脱で判断の要らないもの（不変条件の番号のないテスト、テスト設計にあって書かれていないテスト、ADR が指示した文書の直し漏れ、小さな誤り）は、監査のプルリクエスト（[#780](https://github.com/tett23/golem/pull/780)）で直した。
残ったのは、実装が ADR の書いていない点を決めたもの、ADR の文が互いに食い違っていて実装がその一方を採ったもの、ADR の文のとおりには実現できなかったもの、ADR の不変条件が成り立たない入力があるものである。
この ADR は、それらを記録し、判断の要るものを「メンテナーが決めること」に並べる。

以下、元の ADR の番号の順に並べる。
各項目は、ADR の文、実装、そうした理由または問題の順に書く。

### [ADR 0230](0230-check-the-release-workflow-and-ci-history-by-scripts.md)：`SHA256SUMS` に GMP のソースがない

ADR の 3 は、`release` ジョブの最後に `gh release download` した `SHA256SUMS` を `sha256sum -c` にかけ、上げたものと `dist/` のものが同じであることを確かめるとした。
[`release.yml`](https://github.com/tett23/golem/blob/a8ad416c380dbeacb788a46b51106815674c4fc8/.github/workflows/release.yml#L496-L500) の `SHA256SUMS` は `gmp-*.tar.xz` を含まないので、この照合は GMP のソースに及ばない。
[`docs/audits/releases/v0.1.0-rc4.md`](../audits/releases/v0.1.0-rc4.md) もそう記録している。
ADR の文は `SHA256SUMS` の中身を決めていないので違反ではないが、GMP のソースを `SHA256SUMS` に入れるかは判断が要る（「メンテナーが決めること」の 1）。

### [ADR 0231](0231-run-the-lsp-and-the-editor-grammars-in-headless-neovim-and-helix.md)：notice のテストの二点と、Helix の `use-grammars`

ADR の実装すること 1 は、notice のテストで「`style.toml` の `silence-notices`」にコードを加えるとした。
`silence-notices` は `manifest.toml` の `[diagnostics]` のキーであり（[docs/specifications.md](../specifications.md) の diagnostics の節）、テストは `manifest.toml` に書く（[`notice.lua`](https://github.com/tett23/golem/blob/a8ad416c380dbeacb788a46b51106815674c4fc8/tools/editors/nvim/tests/notice.lua#L38-L40)）。
ADR の文の誤りで、実装が正しい。

同じテストは、クライアントの能力 `workspace.didChangeWatchedFiles.dynamicRegistration` を明示して起動する（[`notice.lua`](https://github.com/tett23/golem/blob/a8ad416c380dbeacb788a46b51106815674c4fc8/tools/editors/nvim/tests/notice.lua#L13-L15)）。
Neovim 0.12.6 は Linux ではこの能力を申し出ないので、既定の Linux の Neovim では、不変条件 I3 の「`silence-notices` にそのコードを書いて保存した後は出ない」が成り立たない。
`tools/editors/README.md` と [docs/roadmap.md](../roadmap.md) の「未決事項」に記録があるが、I3 の範囲を「この能力を申し出るクライアント」に狭めるか、`manifest.toml` の `didSave` でサーバーが評価し直すかは判断が要る（「メンテナーが決めること」の 2）。

不変条件 I6 は「README の Helix の `languages.toml` の例で、`hx --grammar build` が成功する」とした。
テストは README の例の先頭に `use-grammars = { only = ["golem", "emet"] }` を足して走らせる（[`helix/test.sh`](https://github.com/tett23/golem/blob/a8ad416c380dbeacb788a46b51106815674c4fc8/tools/editors/helix/test.sh#L110-L113)）。
README の例だけでは、Helix が持つほかの文法を作ろうとして終了コード 1 になるからで、README にそう書いてある。
I6 は字義どおりには成り立たないので、README の例に `use-grammars` の行を入れるか、I6 の文を改めるかを決める（「メンテナーが決めること」の 3）。

### [ADR 0232](0232-check-inks-fonts-figures-links-and-epubs-structurally-in-ci.md)：`spotColorants` の除く色材、I12 の `hidden`、`pdf-fonts.sh` の照らし先

ADR の 1 と不変条件 I4 は、`Separation` と `DeviceN` の色材のうち「`All` と `None` のほか」をすべて特色として数えるとした。
境界の表は `DeviceN [/Cyan /Spot1]` で G09020 が一つ（`Spot1`）としており、本文と合わない。
実装は表に従い、`All`、`None` に加えてプロセスの色材の名前 `Cyan`、`Magenta`、`Yellow`、`Black` を除く（[`Paint.hs`](https://github.com/tett23/golem/blob/a8ad416c380dbeacb788a46b51106815674c4fc8/modules/golem-pdf/src/Golem/Pdf/Paint.hs#L286-L288)）。
`Separation /Black` だけの PDF は G09020 を出さず、G09021 は `Separation Black` を数える。
仕様書と `docs/diagnostics.md` はコードのとおりに書いてある。
この記録で、I4 と 1 の「`All` と `None` のほか」を「`All`、`None` とプロセスの色材（`Cyan`、`Magenta`、`Yellow`、`Black`）のほか」と読む。

不変条件 I12 は、CI が epubcheck にかける EPUB に「`hidden` の付いたナビゲーションの枝」があるとした。
[golem-epub ADR 0002](../golem-epub/adr/0002-nav-and-toc-depth.md) は、深い見出しをナビゲーションから落とし、`hidden` を使わない。
テストは、深さ 1 のナビゲーションに「節一」「項一」がないことで代えた（[`PluginsSpec.hs`](https://github.com/tett23/golem/blob/a8ad416c380dbeacb788a46b51106815674c4fc8/modules/golem-driver/test/PluginsSpec.hs#L1096-L1098)）。
この記録で、I12 の「`hidden` の付いたナビゲーションの枝」を「深い見出しを含まない深さ 1 のナビゲーション」と読む。

ADR の 8 は、`pdf-fonts.sh` の一覧を「`manual/fonts/` と `manual-dev/fonts/` の README の挙げる書体」と照らすとした。
そのような README はない。
`ci.yml` は `<project>/fonts/*.otf` の名前を許す書体として渡し、`fonts/` の中身は `scripts/manual/fetch-fonts.sh` の固定の一覧（SHA-256 つき）から入る（[`ci.yml`](https://github.com/tett23/golem/blob/a8ad416c380dbeacb788a46b51106815674c4fc8/.github/workflows/ci.yml#L534-L544)）。
PostScript の名前がファイルの名前と一致することに暗黙に頼るが、今はすべて一致する。
この記録で、照らし先は `fetch-fonts.sh` の一覧とする。

### [ADR 0239](0239-decide-the-conditions-of-the-outlined-figure-check-and-the-punctuation-of-figure-sources.md)：Safari の横書きの上限

不変条件 I2 と境界の表は、Safari でも I1 と同じ中心 1 画素、大きさ 2 画素の上限を当てるとした。
実装は Safari の横書きの上限を 8 画素にした（[`svg-text.mjs`](https://github.com/tett23/golem/blob/a8ad416c380dbeacb788a46b51106815674c4fc8/scripts/browser/svg-text.mjs#L34-L35)）。
Safari の横書きの 34 の文字列が 1.5 から 5.5 画素で失敗したためで、「決めたことの記録」の 2 が、理由をプルリクエストに書くことを条件に緩めることを認めており、[#727](https://github.com/tett23/golem/pull/727) に測定と理由がある。
仕様書と README は 8 画素を書いている。
決定は済んでいるので、この記録で I2 の Safari の上限を 8 画素と読む。
[ADR 0234](0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md) の I6（二つのブラウザで同じ基準）の二つめの例外でもある。

### [ADR 0243](0243-retry-every-download-and-cache-the-archives-checked-by-sha-256.md)：三点

`fetch-url.sh` の既定（3 回、待ち 10 秒と 30 秒、`curl` は 120 秒まで）では、一つのアーカイブの取得は最長で約 7 分かかる。
ADR の 3 は `ci.yml` の手順の `timeout -k 10 300` を `timeout-minutes` に替えるとしたが、ほかに `timeout -k 10 300` で包む手順が残っている：[`browser.yml`](https://github.com/tett23/golem/blob/a8ad416c380dbeacb788a46b51106815674c4fc8/.github/workflows/browser.yml#L132-L135) の Chromium、Deno、wasmtime の取得、[`release.yml`](https://github.com/tett23/golem/blob/a8ad416c380dbeacb788a46b51106815674c4fc8/.github/workflows/release.yml#L294) の `fetch-wasm-packages.sh`、`ci.yml` の epubcheck（`bg.sh` 経由）。
300 秒では 3 回めの試行に届かないので、再試行の設計が働かない。
包みを 600 秒以上にするか、`timeout-minutes` に替えるかを決める（「メンテナーが決めること」の 4）。

ADR の 3 は「`release.yml` の GMP と wasmtime も同じ形にする」とした。
`third_party/downloads` のキャッシュがあるのは `build` ジョブだけで、`wasm` と `release` のジョブは `fetch-gmp.sh` をキャッシュなしで走らせる（[`release.yml`](https://github.com/tett23/golem/blob/a8ad416c380dbeacb788a46b51106815674c4fc8/.github/workflows/release.yml#L346)、[同](https://github.com/tett23/golem/blob/a8ad416c380dbeacb788a46b51106815674c4fc8/.github/workflows/release.yml#L503)）。
再試行は働くので実害は小さい。
ジョブごとにキャッシュを置くかを決める（「メンテナーが決めること」の 5）。

`epubcheck-install.sh` は、以前はキャッシュの zip の SHA-256 が合わないと失敗したが、`fetch-url.sh` を使うようになって取り直す。
ADR の 2 は `curl` を `fetch-url.sh` に替えるとしか書いておらず、`fetch-url.sh` の意味論から導かれる。
[ADR 0062](0062-epubcheck-from-release-with-cache.md) の「zip を戻すたびに照合する」の失敗時の扱いが変わった点を、ここに記録する。

### [ADR 0244](0244-take-verapdf-off-the-critical-path-of-ci.md)：中央値が見積もりと離れる

ADR の 3 は、マージの後の 10 回以上のプルリクエストの実行で、中央値が 234 秒前後になることを確かめるとした。
[2026-11-09 の記録](../ci-timings/2026-11-09-ci-times-after-verapdf-off-the-critical-path.md) の 18 回では、中央値は 358.5 秒で、300 秒超が 14 回ある。
`verapdf` は 18 回すべてで最後の `build` のランナーより先に終わっており、臨界経路から外れたことは確かめられた。
中央値の差は、標本が rc4 の ADR の実装のプルリクエストが集中した 5 時間のもので、`cabal build` が長い実行と wasm のキャッシュが外れた実行を含むためと見る。
[ADR 0244](0244-take-verapdf-off-the-critical-path-of-ci.md) の「メンテナーが決めること」の 3（変更のないパッケージのテストを省くこと）を別の ADR にするかを決める（「メンテナーが決めること」の 6）。

### [ADR 0245](0245-keep-the-warnings-of-ci-at-zero.md)：`-w` と、生成したファイルの例外

ADR の 2 は、`-Wwarn`、`-Wno-error`、`-Wno-` を検査するとした。
`werror.sh` はそのとおりで、すべての warning を消す `-w` は見ない（[`werror.sh`](https://github.com/tett23/golem/blob/a8ad416c380dbeacb788a46b51106815674c4fc8/scripts/ci/werror.sh#L45)）。
`ghc-options: -Werror -w` や `{-# OPTIONS_GHC -w #-}` は warning を出さずに通るので、不変条件 W1 の目的に穴がある。
`-w` を検査に足すかを決める（「メンテナーが決めること」の 7）。

ADR の 2 は、`modules/` の Haskell のファイルの `OPTIONS_GHC` の `-Wno-` をすべてエラーにするとし、例外を書いていない。
`werror.sh` は peg-hs が生成する三つのファイル（`modules/golem-parser/src/Golem/Parser/Generated.hs`、`modules/golem-parser/test/StrippedGrammar.hs`、`modules/golem-emet/src/Golem/Emet/Generated.hs`）の `-Wno-unused-imports -Wno-unused-top-binds` を除く（[`werror.sh`](https://github.com/tett23/golem/blob/a8ad416c380dbeacb788a46b51106815674c4fc8/scripts/ci/werror.sh#L131-L133)）。
`build` ジョブが生成器の出力との一致を検査するので、Golem の側では外せない。
仕様書に理由がある。
この記録で、この三つのファイルを [ADR 0245](0245-keep-the-warnings-of-ci-at-zero.md) の 2 の例外とする。

### [ADR 0246](0246-bound-the-prompt-of-the-release-notes.md)：二点

`notes.sh` の「Verifying the downloads」の文は、`golem-*.tar.gz` だけに来歴の証明があり、マニュアル、見本のプラグイン、GMP は `SHA256SUMS` だけである、と書き換わった（[`notes.sh`](https://github.com/tett23/golem/blob/a8ad416c380dbeacb788a46b51106815674c4fc8/scripts/release/notes.sh#L114-L115)）。
[`docs/audits/releases/v0.1.0-rc4.md`](../audits/releases/v0.1.0-rc4.md) の「見つけた問題」に対応する事実の訂正で、[#758](https://github.com/tett23/golem/pull/758) が明記しているが、[ADR 0246](0246-bound-the-prompt-of-the-release-notes.md) の本文にはない。
この記録で認める。

ADR の 1 は、ステータスを「`ステータス:` の後の文字列で、前後の空白を除く」とした。
ステータスの行の相対リンク（例：[ADR 0004](0004-release-notes.md) の `[ADR 0044](0044-release-workflow-hardening.md)`）は、そのまま `## ADRs whose status changed` の一覧とプロンプトに入り、一覧がそのままノートになる経路では、リリースのページで解決しないリンクになる。
相対リンクを絶対にするか、リンクを外すかを決める（「メンテナーが決めること」の 8）。

### [ADR 0247](0247-keep-the-values-of-golem-wasm-independent-of-the-width-of-int.md)：`int-width-icc` と `innerKey`

ADR の 7 の表は、入力 `int-width-icc` で見るものを diagnostics とした。
`compare.sh` は `golem build` だけを走らせ、`golem preflight` は走らせない（[`compare.sh`](https://github.com/tett23/golem/blob/a8ad416c380dbeacb788a46b51106815674c4fc8/scripts/wasm/compare.sh#L165)）。
ICC プロファイルの `/N` の値は `golem preflight` の diagnostics にしか現れず、PDF のバイト列も変わらないので、この入力は golem.wasm で不変条件 I6 を確かめない。
実装は入力と `preflight.toml` を ADR のとおり置いたうえで、仕様書に「確かめない」と明記し、I6 はネイティブの `ImportSpec` で確かめる。
入力を残すか、`compare.sh` に `golem preflight` を足すかを決める（「メンテナーが決めること」の 9）。

ADR の 2 は object の番号の 18 桁を保つと決め、不変条件 I3 は object のストリームの中のキーが「どの二つも異なり、object の番号とも異なる」とした。
キーは `innerKey k = negate (k * 4294967296 + fromIntegral n)` で `k :: Int64` である（[`Import.hs`](https://github.com/tett23/golem/blob/a8ad416c380dbeacb788a46b51106815674c4fc8/modules/golem-pdf/src/Golem/Pdf/Import.hs#L1143)）。
`k` が 2^31 以上なら `k * 2^32` は 2^63 以上で折り返し、キーが正になって object の番号やほかのキーと衝突しうる。
ネイティブと wasm で同じ値になるので I1 は保たれ、ADR の前の 64 ビットの `Int` の式にも同じ折り返しがあった。
I3 のテストは object 4 と 5 だけで、`k` が 2^31 以上の行はない。
`k` の上限を決めるか、キーの型を `Integer` か別の構成にするかを決める（「メンテナーが決めること」の 10）。

### 記録だけの点

- [ADR 0237](0237-raise-the-hang-time-outs-of-golem-driver-test-to-300-seconds.md)：[ADR 0224](0224-limit-the-cells-of-a-table-set-in-pdf.md) のステータスの行を「採択→テストの時間切れの値は [ADR 0237](0237-raise-the-hang-time-outs-of-golem-driver-test-to-300-seconds.md)」に改めるとしたが、[ADR 0236](0236-record-what-implementations-decided-found-by-the-second-review-of-2026-11-08.md) が先に書いた参照を残して 0237 を追記した。0236 の実装を壊さないための逸脱で、[#717](https://github.com/tett23/golem/pull/717) に書いてある。
- [ADR 0239](0239-decide-the-conditions-of-the-outlined-figure-check-and-the-punctuation-of-figure-sources.md)：I6 の末尾の「golem-driver のテスト（輪郭の SVG に Unsupported がない）」に当たるテストは golem-svg のテスト（[`Main.hs`](https://github.com/tett23/golem/blob/a8ad416c380dbeacb788a46b51106815674c4fc8/modules/golem-svg/test/Main.hs#L25-L26)）にある。置き場所の記述の誤りで、テストはある。
- [ADR 0241](0241-derive-the-punctuation-of-figure-sources-from-the-default-aki-set.md)：`golem-layout-test` の `build-depends` に、ADR が挙げた `tasty-golden` のほかに `bytestring` を足した。Hackage のパッケージで golem-* ではなく、[#742](https://github.com/tett23/golem/pull/742) に書いてある。
- [ADR 0245](0245-keep-the-warnings-of-ci-at-zero.md)：ログの取得は `gh api` でなく `curl` で行う（`gh` がエスケープシーケンスを含む応答を書かないため。仕様書に記載）。`release.yml` が `ci.yml` を呼ぶとき、完了済みの `release.yml` 自身のジョブのログも読む。ADR は `release.yml` 自身のジョブを検査しないとしたが、許可の一覧が Alpine の HarfBuzz の行を持つので今は落ちない。[#762](https://github.com/tett23/golem/pull/762) に書いてある。
- [ADR 0232](0232-check-inks-fonts-figures-links-and-epubs-structurally-in-ci.md)：ROS の書き換えの関数は「golem-font のテストの中だけ」でなく `golem-test-support` に置き、golem-font と golem-driver の両方のテストが使う（[#714](https://github.com/tett23/golem/pull/714)）。拒まれる図版の試料は、ふつうの書き出しでは得られず、pdfTeX のプリミティブで書いた `pdftex-spot-color.pdf` の一つである。

## 実装すること

- この ADR を採択したら、「メンテナーが決めること」の決定に従って、それぞれを変更する。記録だけの点と、「この記録で〜と読む」とした点は、変更を要らない。
- 決定が元の ADR の不変条件の文を変えるものは、元の ADR のステータスの行に、この ADR への参照を足す。

## 実装しないこと

- 元の ADR の本文を書き換えること。コミット済みの ADR は変更不可である。
- 「メンテナーが決めること」の各点を、決定の前に実装すること。

## 不変条件

なし。
この ADR は記録と判断の整理であり、新しい振る舞いを決めない。
決定の後の変更は、それぞれの元の ADR の不変条件か、決定が改めた文で確かめる。

## テスト設計

なし。
決定の後の変更のテストは、決定ごとに元の ADR のテスト設計に従う。

## トレードオフ

記録の ADR が増えるぶん、元の ADR の文と振る舞いの対応を読む人は、この ADR も参照することになる。
元の ADR を書き換えないという決まりの代価である。

## メンテナーが決めること

1. **`SHA256SUMS` に GMP のソースを入れるか**（[ADR 0230](0230-check-the-release-workflow-and-ci-history-by-scripts.md)）：推奨は入れることである。`gh attestation verify` の対象でないものも、`SHA256SUMS` には載せて、`release` ジョブの照合に含める。
2. **notice の I3 の範囲**（[ADR 0231](0231-run-the-lsp-and-the-editor-grammars-in-headless-neovim-and-helix.md)）：推奨は、I3 を「`workspace/didChangeWatchedFiles` の動的な登録を申し出るクライアント」に狭め、Linux の Neovim の扱いは [docs/roadmap.md](../roadmap.md) の未決事項のままにすることである。サーバーが `manifest.toml` の `didSave` で評価し直す案は、golem-lsp の ADR を要る。
3. **Helix の I6**（[ADR 0231](0231-run-the-lsp-and-the-editor-grammars-in-headless-neovim-and-helix.md)）：推奨は、I6 の文を「README の Helix の例に `use-grammars = { only = ["golem", "emet"] }` を添えたもので、`hx --grammar build` が成功する」と読むことである。README の例に `use-grammars` の行を入れると、ほかの文法を使う人の設定を壊す。
4. **300 秒の包み**（[ADR 0243](0243-retry-every-download-and-cache-the-archives-checked-by-sha-256.md)）：推奨は、`browser.yml`、`release.yml`、`ci.yml` の `timeout -k 10 300` を 600 秒以上にするか、手順の `timeout-minutes` に替えることである。
5. **`release.yml` の `wasm` と `release` のジョブのキャッシュ**（[ADR 0243](0243-retry-every-download-and-cache-the-archives-checked-by-sha-256.md)）：推奨は、今のままにすることである。タグのたびの一度の取得で、再試行が働く。
6. **CI の所要時間の次の ADR**（[ADR 0244](0244-take-verapdf-off-the-critical-path-of-ci.md)）：推奨は、[ADR 0244](0244-take-verapdf-off-the-critical-path-of-ci.md) の「メンテナーが決めること」の 3（変更のないパッケージのテストを省くこと）を別の ADR として立てることである。
7. **`-w` の検査**（[ADR 0245](0245-keep-the-warnings-of-ci-at-zero.md)）：推奨は、`werror.sh` に `-w` の検査を足すことである。
8. **ステータスの行の相対リンク**（[ADR 0246](0246-bound-the-prompt-of-the-release-notes.md)）：推奨は、`notes.sh` と `write-notes.sh` で、ステータスの行の相対リンクを GitHub の絶対リンクにすることである。
9. **`int-width-icc`**（[ADR 0247](0247-keep-the-values-of-golem-wasm-independent-of-the-width-of-int.md)）：推奨は、入力を残し、`compare.sh` にプリフライトを足さないことである。I6 はネイティブのテストで確かめており、wasm との差はネイティブと wasm で同じ `Integer` を使うことから出ない。
10. **`innerKey` の折り返し**（[ADR 0247](0247-keep-the-values-of-golem-wasm-independent-of-the-width-of-int.md)）：推奨は、キーの型を `Integer` にせず、object のストリームの番号 `k` が 2^31 以上の PDF の図版を取り込みで拒むことである（コードは実装で決める）。ISO 32000-1 の付録 C が挙げる object の番号の実装の上限は 8,388,607 で、2^31 に遠く届かない。

## 決めたことの記録

2026-11-09 に、tett23 が「メンテナーが決めること」のすべてを推奨のとおりとした。

1. **`SHA256SUMS` に GMP のソースを入れる**：`release` ジョブの照合に GMP のソースを含める。
2. **notice の I3 の範囲**：I3 を「`workspace/didChangeWatchedFiles` の動的な登録を申し出るクライアント」に狭める。Linux の Neovim の扱いは [docs/roadmap.md](../roadmap.md) の未決事項のままにする。
3. **Helix の I6**：I6 を「README の Helix の例に `use-grammars = { only = ["golem", "emet"] }` を添えたもので、`hx --grammar build` が成功する」と読む。README の例は変えない。
4. **300 秒の包み**：`browser.yml`、`release.yml`、`ci.yml` の `timeout -k 10 300` を 600 秒以上にするか、手順の `timeout-minutes` に替える。どちらにするかは実装で決める。
5. **`release.yml` の `wasm` と `release` のジョブのキャッシュ**：今のままにする。
6. **CI の所要時間の次の ADR**：[ADR 0244](0244-take-verapdf-off-the-critical-path-of-ci.md) の「メンテナーが決めること」の 3（変更のないパッケージのテストを省くこと）を別の ADR として立てる。
7. **`-w` の検査**：`werror.sh` に `-w` の検査を足す。
8. **ステータスの行の相対リンク**：`notes.sh` と `write-notes.sh` で、ステータスの行の相対リンクを GitHub の絶対リンクにする。
9. **`int-width-icc`**：入力を残し、`compare.sh` にプリフライトを足さない。
10. **`innerKey` の折り返し**：キーの型を `Integer` にせず、object のストリームの番号 `k` が 2^31 以上の PDF の図版を取り込みで拒む。diagnostic のコードは実装で決める。

## 参考文献

- [ADR 0236](0236-record-what-implementations-decided-found-by-the-second-review-of-2026-11-08.md)（記録の ADR の形）
- 監査のプルリクエスト：[#780](https://github.com/tett23/golem/pull/780)（判断の要らない逸脱の修正）、[#781](https://github.com/tett23/golem/pull/781)（[ADR 0244](0244-take-verapdf-off-the-critical-path-of-ci.md) の 3 の記録）
