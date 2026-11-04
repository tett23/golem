# rc4 のプラグインの監査の後の十三の ADR と六つの修正の照合（2026-11-04）

この記録は、2026-11-04 の main（4f86b945、PR #524 のマージの直後）の Golem を、同日の監査（[2026-11-04-rc4-plugin-adr-conformance.md](2026-11-04-rc4-plugin-adr-conformance.md)、以下「前回の監査」）の後に実装した ADR と修正のプルリクエストと照らし合わせた結果である。
対象は次のとおりである。

- [docs/adr/0133](../adr/0133-third-party-licenses-of-sample-plugins.md)（見本のプラグインのライセンスの文書、PR #503）。
- 前回の監査から起こした [docs/adr/0134](../adr/0134-numbers-range-code-is-g02113.md) から [0139](../adr/0139-plugin-diagnostic-code-starts-with-letter.md) と [0142](../adr/0142-import-arguments-are-not-spread.md) から [0145](../adr/0145-title-copies-drop-anchor-inlines.md)（PR #511、#513、#514、#515、#516、#517、#518、#520、#523、#524）。
- CI の [docs/adr/0140](../adr/0140-ci-split-test-runners-and-visual-pdfs-first.md) と [0141](../adr/0141-smaller-ghc-and-hackage-index-caches.md)（PR #509、#512）。
- ADR のない修正のプルリクエスト。前回の監査の F-38（#504）、F-14（#505）、F-44（#506）、文書の所見（#508）、F-16（#519）と、`scripts-macos` ジョブの並列化（#522）。

前回の監査の所見のうち、これらのプルリクエストが直したと申告したものは、実際に直っているかも見た。
コードは変えていない。

ソースコードへのリンクは、すべて調べたコミット 4f86b945 に固定した。

## 目的と範囲

十三の ADR の「実装すること」「実装しないこと」「テスト設計」の各項目について、コード、テスト、CI の設定、文書（docs/specifications.md、docs/markup.md、docs/diagnostics.md、README、manual/、manual-dev/）が ADR のとおりかを調べた。
ADR が指示した、ほかの ADR のステータスの行の書き換えも見た。
ADR のないプルリクエストは、申告した振る舞いがそのとおりか、前回の監査の所見を閉じているか、ADR なしに行ってよい変更かを判断した。
実装者がプルリクエストの本文で申告した逸脱は、妥当かどうかを判断した。

判断の基準、所見の分類（未実装、逸脱、範囲外の変更、テスト欠落、文書の不一致）と重大度（高、中、低）の定義は、前回の監査と同じである。
高は書き手の見る出力か diagnostic が ADR と違うもの、中はプロジェクトの原則か ADR の明示の規則に反するが影響の範囲が狭いもの、低は字面の違いか補助的なものとした。
CI の変更では、メンテナーが頼りにする検査が ADR と違って走らないものを高、ADR の明示の規則か運用の規則に反するものを中とした。

## 方法

1. 十三の ADR を全文読み、十九のプルリクエストの本文と変更したファイルの一覧を `gh pr view` で取った。
2. ADR ごとに、コードとテストと文書を読み、項目ごとに対応する箇所を file:line で特定した。読み取りは五つの組（0133 と 0138、評価器の 0134、0135、0142、0143 と #505、#506、#519、プラグインの 0136、0137、0139 と #504、CI の 0140、0141 と #522、0144、0145 と #508）に分けて分担し、中の所見と実機の確認は、この記録の執筆者がコードを読み直して行った。
3. 4f86b945 を `cabal build all`（GHC 9.10.3、wasmtime の C API は別の checkout の `third_party/wasmtime`）で組み、golem-project（342 件）、golem-doc（160 件）、golem-plugin（150 件）、golem-cli（174 件）、golem-eval（624 件）、golem-driver（974 件と並列の 6 件）のテストを `cabal test` で実行した。七つのスイートがすべて通った。`plugins/` では `cargo test --locked`（97 件、通過）、`sh build.sh --check`（通過、13.8 秒）、`sh rustc-wrapper-test.sh`（4 件、通過）を実行した。`sh scripts/plugin-licenses.sh --check`（終了コード 0）、`sh scripts/test.sh`（71 件、失敗 0）、`sh scripts/ci/test.sh`（348 件、失敗 0、飛ばし 4）、`sh scripts/ci/test-suites.sh driver`（2 行）、`rest`（24 行）、`all` も実行した。
4. `golem new` で作ったプロジェクトに、`plugins/wasm/` の見本を `path` で置き、`golem check`、`golem build`、`golem inspect`、`golem explain` で原稿を試した。試した原稿と結果は各節に書く。PDF のテキストを取り出す道具がないため、PDF のページ番号（0145）は目で見ず、golem-driver のテストに頼った。
5. 見た目の回帰テストは、`scripts/visual/build.sh` と `check.sh` を手元の `golem` と shem 0.1.0-rc3 で実行し、十七の入力のすべてのページが `scripts/visual/pages/` の参照と一致した（終了コード 0）。そのうえで、この日のプルリクエストで参照が変わった manual-dev の 53 から 63、71 から 83、124 から 136 ページと、manual の 179 から 180、321 から 324 ページを PNG に描き、七つのページを目で見た。
6. CI の時間と大きさの主張は、`docs/ci-timings/` が引く実行を `gh run view --json jobs` で取り直し、キャッシュは `gh api repos/tett23/golem/actions/caches`、ブランチの規則は `gh api repos/tett23/golem/rulesets/24998069` で確かめた。actions/cache のパスの扱いは、`ghq` で取った actions/cache（3edfce9、`@actions/cache` 6.2.0）の `dist/save/index.js` で読んだ。

## [ADR 0133](../adr/0133-third-party-licenses-of-sample-plugins.md): 見本のプラグインのライセンスの文書をリリースに添える

### 適合を確かめたもの

- `scripts/plugin-licenses.sh` は POSIX のシェルと awk、`diff`、`strings`、`cargo`、`rustc`、`curl` だけを使い、`jq` と `cargo about` を使わない。引数なしと `--check` の二つの形、それ以外は終了コード 2 である（[plugin-licenses.sh#L33-L38](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/scripts/plugin-licenses.sh#L33-L38)）。
- 手順 1 から 6 は ADR のとおりである。深さ 0 の行で区切り、`cdylib` を持たないクレートをプラグインと数えず、`(<パス>)` の付いた行を除く（[同#L68-L95](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/scripts/plugin-licenses.sh#L68-L95)）。`LICEN[CS]E`、`COPYING`、`COPYRIGHT`、`NOTICE`、`UNLICENSE` と REUSE の `LICENSES/` を写す。`UPSTREAM` の二行、`.cargo_vcs_info.json` の照合、SHA-256 の検証、`NOTE`、同じ SHA-256 のファイルがあれば取得しないこと、表にないクレートのエラー（[同#L137-L155](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/scripts/plugin-licenses.sh#L137-L155)）。`rust/` と `VERSION`、wasm の文字列の三つの照合、`MANIFEST.tsv` と `README`。
- `--check` は一時ディレクトリに作り直して `diff -r` で比べ、違ったパスを標準エラー出力に書く。`cargo tree --offline` で、`UPSTREAM` の文書はコミットしたファイルの SHA-256 を検証し、`curl` に至る分岐は `--check` でないときだけである。
- `licenses/plugins/MANIFEST.tsv` は見出しと `sou-ruby` の 77 行で、ほかのプラグインの行はなく、`LC_ALL=C sort -c` が通る。`crates/lindera-6.2.0/LICENSE` と `crates/lindera-dictionary-6.2.0/LICENSE` の SHA-256 はどちらも ADR の `d37249886de3136db31717f15f6ade215a36fbed1c782381e38b2bf6047e8ec4` で、`NOTE` がある。`rust/VERSION` は `release: 1.99.1`、`commit-hash: 58cf8f9c…` である。全体は 149 ファイル、約 2.4 MB で、ADR の見積もりと一致する。
- CI の `plugins` ジョブは `sh build.sh --check` の直後に `sh ../scripts/plugin-licenses.sh --check` を実行する（[ci.yml#L629-L635](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/.github/workflows/ci.yml#L629-L635)）。`release.yml` は `golem-plugins-licenses-<タグ>/` に `LICENSE` と `THIRD_PARTY_LICENSES/` を置き、ADR の `tar` と `gzip -n` の引数で固め、`SHA256SUMS` に載せる（[release.yml#L255-L272](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/.github/workflows/release.yml#L255-L272)）。
- 仕様書の「見本のプラグイン」と「配布物」、README の三か所、manual-dev の見本のプラグインの段落、使い手のマニュアルのアーカイブの URL と再配布の一文。ADR のステータスの行は `採択` である。
- `scripts/test.sh` には、テスト設計の十八の項目のすべてに対応する検査がある（[test.sh#L194-L393](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/scripts/test.sh#L194-L393)）。PR #503 の「先に書いて 41 件が失敗した」は、スクリプトのない状態の申告として筋が通る。
- 手で確かめることのうち、macOS での生成と Linux の CI での `--check` は、PR #503 の `plugins` ジョブが通ったことで満たされている。リリースのワークフローは「次のプレリリースで確かめる」とされ、PR #503 の後にタグがないので、この監査でも確かめていない。

### 所見

**F-01（範囲外の変更、申告あり、低）：`cargo tree` に `--no-dedupe` を足した。**
[plugin-licenses.sh#L66-L69](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/scripts/plugin-licenses.sh#L66-L69)。
申告の理由は実在する。
`--no-dedupe` なしの出力は 192 行で、そのうち 74 行が ` (*)` 付きであり、一度出したクレートの子は後のルートの下に出ない。
ADR の手順 1（深さ 0 で区切る）は、この省略を前提に入れていなかった。
今は crates.io に依存するのが `sou-ruby` だけなので、どちらの出力からも `sou-ruby` の集合は 77 個で、結果は変わらない。
`(*)` を落とす分岐（[同#L89-L90](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/scripts/plugin-licenses.sh#L89-L90)）は、`--no-dedupe` 付きの実出力に `(*)` の行がなく、`scripts/test.sh` の偽の入力にもないので、動かしていない保険である。
妥当な逸脱だが、ADR の手順と実装の違いは記録に残すのがよい。

**F-02（逸脱、申告なし、低）：`curl` の差し替えが環境変数でなく `PATH` による。**
ADR は「`curl` の代わりは、環境変数で差し替えられるようにする」とするが、[plugin-licenses.sh#L23](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/scripts/plugin-licenses.sh#L23) は `PATH` で引くと書き、[同#L146](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/scripts/plugin-licenses.sh#L146) は素の `curl` を呼ぶ。
テストは `PATH` の先頭に偽の `curl` を置いて通している（[test.sh#L266](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/scripts/test.sh#L266)）。
機能は足りている。

**F-03（逸脱、申告あり、低）：`gh release create` の引数を足さず、既存のグロブに頼る。**
[release.yml#L286-L290](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/.github/workflows/release.yml#L286-L290) は `dist/golem-*.tar.gz` でアーカイブを拾い、コメントで意図を書く。
名前は確実に一致する。
副作用として、`attest-build-provenance` の `subject-path`（同じグロブ）にもこのアーカイブが入るが、マニュアルの HTML のアーカイブと同じ扱いで、害はない。

**F-04（文書の不一致、低）：README と使い手のマニュアルの挿入位置が ADR の指定と違う。**
ADR は README を「`THIRD_PARTY_LICENSES/` を説明する段落の後」、使い手のマニュアルを「見本のプラグインの URL を説明する段落に」とする。
[README.md#L66-L68](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/README.md#L66-L68) は同じ段落の二文めに入れ、[manual/chapters/10-plugins.gm#L118-L122](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/manual/chapters/10-plugins.gm#L118-L122) は URL の段落（L96-L101）から kansuji の例を挟んだ後の独立した段落である。
内容は ADR のとおりで、読みとしても自然である。

**F-05（テスト設計、低）：`UPSTREAM` のテストの入力が、検査対象の生成物に依っている。**
[test.sh#L262](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/scripts/test.sh#L262) は偽の `curl` が返す文書に `licenses/plugins/crates/lindera-6.2.0/LICENSE` を使う。
SHA-256 の定数で独立に検証するので循環はしないが、生成前の木では同じ節の三つの検査が失敗する。

## [ADR 0134](../adr/0134-numbers-range-code-is-g02113.md): コードブロックの `numbers` に書いた範囲は G02113 とする

### 適合を確かめたもの

- コードは変わっていない。`RangeSpec` が `numbers=5-5` を G02069、`numbers=5...5` と `numbers=[= 1...3]` を G02113、`5`、`[= 5]`、`true` を誤りなしと固定する（[RangeSpec.hs#L184-L188](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-eval/test/RangeSpec.hs#L184-L188)）。
- [docs/adr/0113](../adr/0113-closed-range-literal.md) のステータスの行は 0111 と 0134 を引き、[docs/adr/0111](../adr/0111-argument-words-as-number-literals.md) のステータスの行に 0134 の句がある。diagnostics.md の G02069 の主な原因は「`-` で区切った範囲か数でない語」で、G02069 と G02113 の ADR の欄に 0134 がある。docs/markup.md の表（L465）と `numbers` の段落は同じ規則で書かれ、`numbers` の範囲をすべて G02069 とする古い記述は docs、manual、manual-dev にない。

所見はない。

## [ADR 0135](../adr/0135-range-words-read-as-range-expressions.md): 範囲を受け取らない引数の範囲の語を、同じ字の式と同じに読む

### 適合を確かめたもの

- `plainArgValue` は `argValue` で値を作り、`VRange` なら G02113 を語の字で返し、それ以外は式の diagnostic をそのまま返す（[File.hs#L2169-L2177](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-eval/src/Golem/Eval/File.hs#L2169-L2177)）。`naturalArg` は範囲の語と式を `plainArgValue` に回す（[同#L2210-L2223](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-eval/src/Golem/Eval/File.hs#L2210-L2223)）。語の `1.5` は `wordNumber` で有理数になり、式と同じ `rangeEnd` を通るので、G02104 のメッセージの値は式と同じ `1.5` である。
- ADR の表の七行は `FileSpec` の `argWordTests` にあり、六つの語は同じ行の式とコードもメッセージも一致し、`[number-text 1...3]`、`@blank-line 1...3`、`numbers=5...5` は語の字で G02113、`1...`、`a...3`、`1...2...3` は据え置きである（[FileSpec.hs#L756-L790](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-eval/test/FileSpec.hs#L756-L790)）。旧の `[number-text -1...1.5]` を G02113 とする期待は G02104 に改まっている。
- 実機で、`[number-text 7...3]` が G02106、`[number-text -1...1.5]` と `@blank-line 1...1.5` が G02104、`[number-text 1e1301...2]` が語でも式でも同じ文言の G02086、`numbers=7...3` が G02106、`[number-text 1...3]` と `@blank-line 1...3` と `@toc depth=1...3` が G02113 になることを確かめた。
- diagnostics.md の G02113 の「意味」は成り立つ語に限り、`-1...1.5` を例から除き、成り立たない語は G02104、G02106、G02086 とする。G02104 と G02106 の節に語の記述がある。docs/markup.md の段落、0111 のステータスの行の句。

### 所見

**F-06（文書の不一致、低）：範囲の語が G02104、G02106、G02086 になるときの位置が箇所で揺れ、diagnostics.md の記述と合わない。**
実機で、`[number-text 7...3]` の G02106 は 3:1（コマンド）、`[number-text [= 7...3]]` は 3:34（範囲の式）、`@blank-line 7...3` は 5:1（コマンド）、コードブロックの `numbers=7...3` は 15:12（引数）に出た。
`argValue` が語の範囲を組むとき、呼び手から受けた `sp` を使い（[File.hs#L2154](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-eval/src/Golem/Eval/File.hs#L2154)）、`[number-text ...]` と自然数を求めるブロックコマンドはコマンドの span を渡し、`numbersArg` だけが引数の span を渡す（[同#L1611](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-eval/src/Golem/Eval/File.hs#L1611)）ためである。
[diagnostics.md#L3542](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/docs/diagnostics.md#L3542) の G02106 の「語と文字列なら引数である」は、`[number-text 7...3]` と `@blank-line 7...3` に当てはまらない。
G02104 の節（[同#L3482](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/docs/diagnostics.md#L3482)）は語の位置を書いていない。
[ADR 0135](../adr/0135-range-words-read-as-range-expressions.md) は位置を扱わないと明記しているので逸脱ではないが、#519 が G02113 を引数に移した後、同じ箇所の兄弟の原因（`1...3` は引数、`7...3` はコマンド、`[= 7...3]` は範囲の式）が三つの位置に分かれた。
位置は ADR で決めて揃えるのがよい（F-26 も参照）。

**F-07（範囲外の観察、低）：コードブロックの `numbers` の文字列が範囲の語として読まれる。**
`numbersArg` は `StringLit t` を `Word t` に変える（[File.hs#L2370](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-eval/src/Golem/Eval/File.hs#L2370)）ので、実機で `numbers="5...5"` が G02113、`numbers="7...3"` が G02106 になった。
`file="1...3"` は字のままで誤りにならない。
0111 と 0135 は語だけを対象にし、文字列は決めていない。
0135 の前からある振る舞いで、逸脱ではないが、diagnostics.md と markup.md は文字列を挙げていない。

## [ADR 0136](../adr/0136-missing-plugin-data-at-load.md): 渡されていないデータを `golem_check_data` で読み込みのときに報告する

### 適合を確かめたもの

- CDDL の `name: tstr / null`（[golem-doc.cddl#L131](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-doc/schema/golem-doc.cddl#L131)）、`ddName :: Maybe Text`、`TNull` の復号（[Plugin.hs#L869-L884](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-plugin/src/Golem/Plugin.hs#L869-L884)）。golem-driver の `located` は `Nothing` を `manifest.toml` の先頭（G06101 から G06103 と同じ span）に置き、渡していない名前は今までどおり G06009 である（[Driver/Plugins.hs#L205-L214](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-driver/src/Golem/Driver/Plugins.hs#L205-L214)）。エラーなら読み込みの誤り、警告なら読み込む（[同#L113-L115](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-driver/src/Golem/Driver/Plugins.hs#L113-L115)）。ABI は golem-plugin、CDDL、SDK、仕様書、manual-dev で 8 である。
- 見本の三つは `name` を null にして `golem_check_data` で報告し、呼び出しのときのコードは残る。`sou-ruby` と `first-ruby` は `export_plugin!` に三つめの関数を渡す。SDK の `DataDiagnostic.name` は `Option<String>` である。コードは #504 の後の `no-data` と `no-words` で、ADR の「F-38 を別の変更が直すときは、その形に従う」のとおりである。
- 実機で、`[plugins.g]` に `data` を書かない用語集の本が、`[term]` が零個でも三個でも `manifest.toml:1:1: error[g/no-data]: manifest.toml で data の terms を渡してください` を一つだけ出し、G02022 を出さず、終了コード 1 になること、`words` を渡さずに `first-ruby` を二つのファイルに当てた本が `first-ruby/no-words` を一つだけ出すことを確かめた。
- テスト設計の項目は `CheckDataSpec`（[#L71-L76](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-plugin/test/CheckDataSpec.hs#L71-L76)）、`PluginsSpec`（[#L709-L722](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-driver/test/PluginsSpec.hs#L709-L722)、[#L833-L842](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-driver/test/PluginsSpec.hs#L833-L842)、[#L956-L959](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-driver/test/PluginsSpec.hs#L956-L959)）、三つの見本の Rust のテストにある。
- 仕様書の `golem_check_data` の節と三つの見本の節、diagnostics.md の G06009 の理由、manual-dev の CDDL と段落（manual-dev の 55 ページを目で見た）、[docs/adr/0120](../adr/0120-plugin-data-check-at-load.md) のステータスの行の句。

### 所見

**F-08（逸脱、申告あり、低）：`name` が null で `line` がある応答の検査を、golem-driver の `located` でなく golem-plugin の復号器に置いた。**
[Plugin.hs#L882](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-plugin/src/Golem/Plugin.hs#L882)。
形だけで決まる規則（コードの形、重大度、`line` が 1 以上）は golem-plugin、ファイルが要る規則（渡していない名前、ファイルにない行）は golem-driver という既存の分担に沿い、書き手の見る出力は ADR のとおりである。
妥当である。

**F-09（テスト欠落、低）：`name` が null の警告でプラグインが読み込まれることのテストがない。**
`PluginsSpec` は名前のある警告だけを試す。
コードの経路は名前を見ないので動くはずだが、未確認である。

## [ADR 0137](../adr/0137-plugin-image-folder-collision-g08102.md): 原稿の図版の出力のパスがプラグインの画像のフォルダーと重なるときの G08102

### 適合を確かめたもの

- `pluginImagePathDiagnostics` は、`web` があれば `web`、なければ図版のパスを `normalizeRelative` で正規化し、`images/golem-plugin/` で始まれば `@figure` ごとにエラーを出す（[Driver.hs#L684-L692](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-driver/src/Golem/Driver.hs#L684-L692)）。`golem check` でなく、HTML か EPUB を書くときだけ呼び、HTML と EPUB を書かない（[同#L657-L664](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-driver/src/Golem/Driver.hs#L657-L664)）。メッセージは ADR の表と一字一句同じである。
- プラグインのない本で、`a/../images/golem-plugin/x.svg`、`images/./golem-plugin/x.svg`、`img/x.svg web=images/golem-plugin/x.svg` の三つが `golem build` で G08102 になり、`images/golem-plugin/x.svg web=img/x.svg` はならず、`build/` に pdf と text だけが書かれ、`golem check` と `--target text` では出ないことを実機で確かめた。
- diagnostics.md の G08102 の ADR の欄と仕様書の段落に 0137 がある。[docs/adr/0123](../adr/0123-figures-from-plugins.md) のステータスの行の句。

### 所見

**F-10（文書の不一致とテスト欠落、低）：ADR が「プラグインのない本で」と書くテストは、bar-chart を宣言した本である。**
[PluginsSpec.hs#L352-L359](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-driver/test/PluginsSpec.hs#L352-L359) は `withBarChart` を使い、その `manifest.toml` は `bc` を宣言する（[同#L299-L305](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-driver/test/PluginsSpec.hs#L299-L305)）。
0137 の理由の要である「プラグインの有無を問わない」は、テストでは宣言のある側だけを固定し、宣言のない側は実機（前回の監査とこの監査）でだけ確かめている。
EPUB が書かれないこと、テキストが書かれること、`golem check` で出ないことも、テストにない。

## [ADR 0138](../adr/0138-host-independent-crate-metadata-for-plugins.md): 見本のプラグインのクレートの `-C metadata` をホストに依らない値にする

### 適合を確かめたもの

- `rustc-wrapper.sh` は `metadata=<CARGO_PKG_NAME>-<CARGO_PKG_VERSION>-<host か target><,feature="..." の並び>` に置き換え、ほかの引数を変えない（[rustc-wrapper.sh#L17-L31](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/plugins/rustc-wrapper.sh#L17-L31)）。`build.sh` が `RUSTC_WRAPPER` に渡し、`plugins/.cargo/config.toml` はないので `cargo test` と手の `cargo build` には及ばない。
- `rustc-wrapper-test.sh` の四つの場合はテスト設計の四つの項目に一対一で当たり、CI の `plugins` ジョブが `build.sh --check` の前に走らせる（[ci.yml#L626-L628](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/.github/workflows/ci.yml#L626-L628)）。
- 仕様書の再現性の段落、二つのスクリプトの冒頭のコメント、[docs/adr/0106](../adr/0106-sample-plugins-in-rust.md) のステータスの行は ADR の文言どおりである。
- cargo 1.99.1（5f94df478）のソースで、`-C` と `metadata=<ハッシュ>`、`--target` と triple、`--cfg` と `feature="x"` がそれぞれ別の引数で渡されることを確かめた。ラッパーの前提は正しい。

### 所見

**F-11（テスト欠落、低）：`-Cmetadata=` と `--target=<triple>` の一引数の形に対する検査がない。**
一引数の形はラッパーに当たらず素通りし、`--target=` は `host` と判定される。
ADR はこの限界を書き、`build.sh --check` を保険にしているので、逸脱ではない。
ツールチェーンを上げるときの手順に、`cargo build -v` の引数の形を見ることを足すとよい。

## [ADR 0139](../adr/0139-plugin-diagnostic-code-starts-with-letter.md): プラグインの diagnostic のコードを英小文字で始める

### 適合を確かめたもの

- `pluginCode` は `dataName` で判定し、文言は `診断のコードの形が不正です: <コード>` のままである（[Plugin.hs#L821-L824](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-plugin/src/Golem/Plugin.hs#L821-L824)）。呼び手は `response` と `checkData` の二つで、コマンド、ブロックコマンド、フィルタ、`golem_check_data` のすべてに及ぶ。
- `ResponseSpec` の不正なコードに `-`、`-x`、`0`、`404`、`2x` があり、`no-key-2`、`a`、`a-` は通る。`CheckDataSpec` に `404` と `-x` がある。仕様書の二か所、diagnostics.md の冒頭と G06009、manual-dev の文言、[docs/adr/0108](../adr/0108-plugin-diagnostic-codes-and-spans.md) のステータスの行の句。
- `cargo test --locked` と golem-driver の `PluginsSpec` は変えずに通る。

### 所見

**F-12（逸脱、申告あり、中）：`golem explain` が、コードの形の規則の写しを持ち、0139 の後は食い違っている。**
[cli/Main.hs#L156-L166](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-cli/app/Main.hs#L156-L166) は `/` の後を「英小文字、数字、`-` の列」で判定し、先頭を見ない。
`golem explain x/404`、`x/-`、`x/0` が「プラグインの診断のコードです」を標準出力に書いて終了コード 0 になり、`x/_` だけが終了コード 2 になることを実機で確かめた。
0139 の後、どのプラグインも `404` や `-` を出せないので、CLI は存在しない形をプラグインのコードとして説明している。
0139 は「名前の形の規則を一つにし、二つの関数が食い違わないようにする」と書き、「実装しないこと」で除いたのは `/` の前の部分（前回の監査の F-10）だけである。
PR #517 はこれを申告し、後の変更で揃えられると書いた。
golem-cli は golem-plugin に依存済みなので、規則を公開して使えば build-depends は変わらない。
仕様書とマニュアルは `golem explain <プラグイン>/<コード>` が受ける形を書いていないので、文書の不一致はない。
短い修正の ADR で揃えるのがよい。

## [ADR 0140](../adr/0140-ci-split-test-runners-and-visual-pdfs-first.md): build のテストを四つのランナーに分け、visual-pdfs を決定性の検査の出力より先に組む

### 適合を確かめたもの

- `scripts/ci/test-suites.sh` は `modules/*/*.cabal` の `test-suite` を読み、`driver` は golem-driver のスイート、`rest` はそれ以外を書き、引数なしと未知の `PART` は終了コード 2 である。実際の `modules/` で `driver` が 2 行、`rest` が 24 行、合わせて 26 の `test-suite` のすべてで、重なりはない。
- 行列は x86-64 の `tests-driver`、`tests-rest`、`outputs`、`env` と aarch64 の `tests`、`outputs` で、`tests`、`outputs`、`env`、`suites`、`save` を持つ（[ci.yml#L120-L162](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/.github/workflows/ci.yml#L120-L162)）。`cabal test $(sh scripts/ci/test-suites.sh "$SUITES")`（[同#L330](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/.github/workflows/ci.yml#L330)）で、環境変数と `timeout-minutes` は変わっていない。`cabal build all peg-cli:exe:peg-hs` は全ランナー、qpdf と cddl は `matrix.tests`、生成したパーサーの検査は `matrix.tests && matrix.suites != 'driver'`、二つの `Save dist-newstyle` は `matrix.save`、成果物の名前、`ci` の `needs`、`gate.sh`、`wait-pdfs.sh` のジョブの名前は変わっていない。`visual-pdfs` の二つの手順は「Cache the fonts of the manuals」の直後、epubcheck の前にある。
- テスト設計の七項目は `scripts/ci/test.sh` にある。README、manual-dev の CI の章（128 ページを目で見た）、仕様書、[docs/adr/0045](../adr/0045-split-x86-build-and-pull-request-cache.md)、[0095](../adr/0095-visual-job-in-ci.md)、[0097](../adr/0097-ci-same-path-before-build-and-env-check-runner.md) のステータスの行。
- 手で確かめることのうち、スイートの和は、実行 41815303999 と 41814517417 のログで `tests-driver` が 2、`tests-rest` が 24、aarch64 の `tests` が 26 で、和が一致する。`docs/ci-timings/2026-11-04-split-test-runners.md` の前後 2 回ずつの数値は、`gh run view --json jobs` から取り直した値とすべて一致した。ADR の「3 回ずつ」に対して記録は 2 回ずつだが、#509 の後の main のプルリクエストの実行（41831996929、41836138897、41833786147、41831485473）で `build` の最後のランナーが 160 から 174 秒に終わり、見積もりの「170 秒前後」は成り立つ。

### 所見

**F-13（運用の逸脱、中）：PR #509 は、最終コミットの CI が終わる前にマージされた。**
`gh pr view 509` のマージは 2026-11-04T10:43:12Z、最終コミット eca3cef7 の `ci.yml` の実行 41816022322 は 10:43:11Z に始まり 10:46:12Z に成功した。
直前のコミット 7c621739 の実行 41815303999 は 10:39:48Z に成功しており、最終コミットは `docs/ci-timings/` の追加だけである。
main のルールセット（24998069）は `ci`、`adr`、`manual`、`textlint` の状態の検査を求めるが、管理者の `bypass_mode: always` があるので、管理者のマージは検査を待たない。
結果は通ったので実害はないが、実装のレーンの「CI が通ればマージしてよい」に反する。
ルールセットの bypass を外すか、`gh pr merge --auto` を使うかは、メンテナーの判断である。

**F-14（範囲外の変更、低）：`test-suites.sh` の引数が ADR より広く、行列に `suites: none` がある。**
ADR は `PART` を `driver` と `rest` の二つとし、`all` は `ci.yml` の側で `cabal test all` と書くとしたが、スクリプトは `all` と二つめの引数 `MODULES` を受ける（[test-suites.sh#L5-L7](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/scripts/ci/test-suites.sh#L5-L7)）。
`outputs` と `env` の行には ADR にない `suites: none` がある（[ci.yml#L140](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/.github/workflows/ci.yml#L140)、[#L147](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/.github/workflows/ci.yml#L147)、[#L161](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/.github/workflows/ci.yml#L161)）。
CI の振る舞いは同じで、`test.sh` がこれらを固定している。

**F-15（低）：`scripts/ci/test.sh` が GNU awk で警告を出す。**
[test.sh#L999](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/scripts/ci/test.sh#L999) の `-v c="…\\(…\\)"` に対し、gawk が `escape sequence '\(' treated as plain '('` を二行出す。
`c` は使われず、結果に影響しない。
BSD の awk では出ない。

## [ADR 0141](../adr/0141-smaller-ghc-and-hackage-index-caches.md): GHC と Hackage の索引のキャッシュから、CI が読まないファイルを除く

### 適合を確かめたもの

- 索引のキャッシュの `path` に `!~/.cabal/packages/hackage.haskell.org/01-index.tar.gz`、キーに `hackage-index-tar-${{ hashFiles('cabal.project.freeze') }}`（[ci.yml#L243-L249](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/.github/workflows/ci.yml#L243-L249)）。GHC のキーは `…-${{ env.ImageOS }}-slim`、消す手順は `cache-hit != 'true'` のときだけ、`haskell-actions/setup` の後、`cabal build` の前にある（[同#L216-L228](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/.github/workflows/ci.yml#L216-L228)）。
- `test.sh` に三つの検査がある。manual-dev の CI の章、[docs/adr/0009](../adr/0009-ci-speed.md) のステータスの行の句。
- 手で確かめることのうち、一回目（41816372306、41818590437）は全ランナーでキャッシュが外れ、`cabal build` と `cabal test` が通った。二回目（41817232702）は `cabal update` を飛ばし、golem-driver、golem-lsp、golem-cli とそのテストだけを再コンパイルした。GHC のキャッシュは x86-64 で 146 MB、aarch64 で 150 MB（`gh api` の `actions/caches` でも同じ）で、手順は 2 から 4 秒である。`docs/ci-timings/2026-11-04-smaller-ghc-and-index-caches.md` の数値は実行と一致する。

### 所見

**F-16（逸脱、申告なし、中）：`01-index.tar.gz` の除外は効いておらず、索引のキャッシュは ADR の意図のとおりには縮んでいない。**
`actions/cache` の `resolvePaths` は、`path` の各行を `@actions/glob` に `implicitDescendants: false` で渡す（actions/cache 3edfce9 の `dist/save/index.js` の 43325 行め）。
`~/.cabal/packages/hackage.haskell.org` のようなディレクトリの行は、そのディレクトリ自身が一件として当たり、tar にはディレクトリが丸ごと渡る。
`!` の行は glob が当てたパスからしか除けないので、ディレクトリの中の一つのファイルは除けない。
除外が効くのは、`…/hackage.haskell.org/**` のようにファイルを列挙する行と組み合わせたときだけである。
実測もこれと合う。
索引のキャッシュは 259 MB から 242 MB に 17 MB しか縮まず（`gh api` の `hackage-index-tar-…` も 242 MB）、`01-index.tar.gz` だけで 139 MB（圧縮済みで縮まない）あるので、除外が効いていれば 120 MB ほどになるはずである。
[docs/ci-timings/2026-11-04-smaller-ghc-and-index-caches.md#L37-L38](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/docs/ci-timings/2026-11-04-smaller-ghc-and-index-caches.md#L37-L38) は「ランナーの上の `01-index.tar.gz` はずっと小さいと見られる」と推測するが、原因の取り違えである（記録は変更不可なので、ここに記す）。
帰結は三つある。
ADR の「実装すること」の一つめは字面どおりに入っているが目的を果たしていない。
テスト設計の「二回目の実行で、二つのキャッシュの大きさと手順の秒数が、上の表より小さい」は、索引については満たされていない（259 MB から 242 MB、手順の秒数は同じ）。
二回目の実行は `01-index.tar.gz` がそろったまま動くので、ADR が「CI の cabal-install 3.16.1.0 では確かめていない」とした「`.tar.gz` なしで cabal が計画を立てられる」ことは、CI で未検証のままである。
直すには ADR が要る。
`path` を `…/hackage.haskell.org/**` と `!…/01-index.tar.gz` の組にするか、`cabal update` の後に `rm` するかである。
`scripts/ci/test.sh` の検査は `path` の字面しか見ないので、この誤りを捉えられない。

## [ADR 0142](../adr/0142-import-arguments-are-not-spread.md): `@import` の引数を評価器で展開しない

### 適合を確かめたもの

- ブロックコマンドの枝は `@import` を `prepareArgs` の前に `standalone` へ渡す（[File.hs#L483-L484](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-eval/src/Golem/Eval/File.hs#L483-L484)）。`importSite` は三つの位置引数の形以外を G03009 にし、式を評価しない。属性の形でも同じ枝に入る。
- 実機で `golem inspect s.gm --as ir` により、`@import *[["x.gm"]] as n`、`@import *[1]`、`@import *[y]`、`@import **[{a: 1}]` のどれも `s.gm:1:1: error[G03009]` だけになる（G02002 も G02111 も出ない）ことを確かめた。属性の形の `@import *[y]` は G02011 と G03009 である。
- `FileSpec` の `spreadTests` に五つのテストがあり、四つの原稿の diagnostic（コード、メッセージ、始まり、終わり）を golem-project の `importsOf` の結果と比べる（[FileSpec.hs#L888-L900](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-eval/test/FileSpec.hs#L888-L900)）。golem-eval のテストの golem-project への依存は 2026-10-13 からあり、変わっていない。
- diagnostics.md の G03009 の追記、G02114 と G03009 の ADR の欄、[docs/adr/0112](../adr/0112-spread-arguments.md) のステータスの行の句。

所見はない。

## [ADR 0143](../adr/0143-style-spread-diagnostic-per-argument.md): `@style` の展開の G02114 を展開の引数ごとに出す

### 適合を確かめたもの

- 本体の形（[File.hs#L486](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-eval/src/Golem/Eval/File.hs#L486)）と属性の形（[同#L2086](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-eval/src/Golem/Eval/File.hs#L2086)）が `spreadsOf` のすべてに G02114 を出す。メッセージは据え置きである。
- 実機で、本体の形と属性の形の `@style *[["a"]] **[{b: 1}]` がそれぞれ 9:8 と 9:17、12:8 と 12:17 の二つの G02114 になることを確かめた。
- `FileSpec` の四つのテスト、diagnostics.md の G02114 の追記、0112 のステータスの行の句。`@manifest` と `@style-def` は元から引数ごとで、変わっていない。

所見はない。

## [ADR 0144](../adr/0144-figure-captions-hold-paragraphs-only.md): 図版のキャプションには段落だけを置く

### 適合を確かめたもの

- golem-eval の `captionParagraphs` は、評価した本体の各ブロックに `notInCaption` を当て、段落以外に `G02118` をそのブロックの位置に出して除き、図版は残す（[File.hs#L1227-L1241](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-eval/src/Golem/Eval/File.hs#L1227-L1241)）。`ForcedBreak`、`PageControl`、`BlankLines` は対象から外し、既存の `nestedBreaks` の G02059、G02071、G02093 に任せるので、重ならない。
- golem-doc の `Validate` に `captionErrors`（`図版のキャプションには段落だけを置けます`）があり、`validateBlocks` と `validateDocument` の両方に効く（[Validate.hs#L81-L91](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-doc/src/Golem/Doc/Validate.hs#L81-L91)）。golem-plugin はブロックコマンドの出力で、画像の検査より先に最上位の図版のキャプションを検査し（[Plugin.hs#L558](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-plugin/src/Golem/Plugin.hs#L558)）、`blockKind` はキャプションに降りない。CDDL は変わらず、ABI は 8 である。
- 実機で、ADR の文脈の原稿に `@page-break`、`@blank-line 1`、画像のない内側の `@figure` を足したものが、G02118 を図版、箇条書き、コードブロックの三つのブロックの位置に出し、`@page-break` は G02059、`@blank-line` は G02093、画像のない内側の図版は G02033 だけになることを確かめた。段落だけのキャプションの本は、テキストで `［図1-1　外］`、`［図1-2　二つめ］`、`[ref-number z]` が `1-2` になる。
- テスト（`FileSpec`、golem-doc の `Main.hs`、`BlockSpec` の `plugin:` の図版と箇条書き）、docs/markup.md、diagnostics.md の G02118 の節と G06009 の理由、仕様書の三か所、両マニュアル（manual の 180 ページ、manual-dev の 61 と 72 ページを目で見た）、[docs/adr/0123](../adr/0123-figures-from-plugins.md) のステータスの行の句。
- 申告された二つの逸脱は妥当である。golem-doc の既存のテストで、キャプションの中の強制改ページがキャプションの理由だけになるのは、`Validate` が段落でないブロックの中に降りない作りの帰結で、一つの原因に一つの理由である。図番号を IR で確かめるのは、S1 の `allBlocks` がキャプションに降りて図版を数える（[Assemble.hs#L542-L551](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-doc/src/Golem/Doc/Assemble.hs#L542-L551)）以上、IR にないものは数えないので、推論は正しい。

### 所見

**F-17（文書の不一致、低）：`<種類>` の列挙が、ADR の十一と実装・diagnostics.md の八で違う。**
ADR は改ページ、改ページの制御、行アキを `<種類>` に含めるが、実装はこれらを既存のコードに任せ（上のとおり）、[diagnostics.md#L3875](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/docs/diagnostics.md#L3875) は八つを書く。
文書の側が正しく、ADR の列挙が広かった。
golem-eval の `notInCaption` と golem-plugin の `blockKind` は別の関数の重複だが、依存の向きから共有できず、方針（新しい依存より複製）に沿う。

**F-18（テスト欠落、申告あり、低）：図番号の端から端までの検査がない。**
[FileSpec.hs#L423-L426](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-eval/test/FileSpec.hs#L423-L426) は IR に二つの図版が残ることだけを見る。
G02118 はエラーなので、誤りのある本の出力はなく、図番号が書き手に見えるのは `[ref-number]` の diagnostic だけである。
実害は小さい。

**F-19（テスト欠落、低）：ADR の「見た目の回帰テストの参照が変わらない」は PR では満たされず、参照は変わった。**
PR #523 は manual の 170 ページ余りと manual-dev の 18 ページの参照を書き換えた。
原因は ADR 自身が求めたマニュアルの追記（a-markup に一行、e-errors に四行、06-ir に四行）による組み直しで、コードの変更によるものではないと推定できるが、参照は SHA-256 だけなので区別はできない。
この監査では、現在の参照が手元のビルドと一致すること、書き換わったページの一部が正しく組まれていることを確かめた（「方法」の 5）。
manual の奥付が、二ページ増えた結果、最後の 324 ページに四行だけあふれていることを見た。
誤りではないが、体裁としては気になる。

## [ADR 0145](../adr/0145-title-copies-drop-anchor-inlines.md): 目次と `[ref-title]` に写す題から、索引の印とチャネルの項目を除く

### 適合を確かめたもの

- `withoutAnchors` は `IndexMark` と `ChannelItem` を除き、`Ruby` の親文字、`Kenten`、`Color`、`CharStyle` に降りる（[IR.hs#L345-L353](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-doc/src/Golem/Doc/IR.hs#L345-L353)）。子を持つ構成子のうち `Note` と `Sidenote` に降りないのは、ADR の「実装しないこと」のとおりである。
- S1 は `hiTitle` を `withoutAnchors` で作り（[Assemble.hs#L305](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-doc/src/Golem/Doc/Assemble.hs#L305)）、`TocEntry` と見出しの `ltTitle` はこれを使い、コードブロックのキャプションのラベルの題も除く（[同#L567-L573](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-doc/src/Golem/Doc/Assemble.hs#L567-L573)）。本文の見出しは変えない。PDF と HTML の目次のフィルタは取り除かれている。柱、しおり、`<title>`、EPUB のナビ、プレーンテキストは `inlineText` か S1 の題を使い、未フィルタの題を写す場所はない。
- 実機で、横組みの本に `@label c`、`# [term: 組版]と[strong: [index reading=はんめん: 版面]と]の章`、`[ref-title c]`、`@toc`、`@channel glossary`、`@index` を置いて HTML を組むと、`id="c-glossary-…"` と `id="i-…"` がそれぞれ一つ、リンクもそれぞれ一つになることを確かめた。PDF のページは、golem-driver の `ReferencesSpec`（[#L93-L108](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-driver/test/ReferencesSpec.hs#L93-L108)）と `PluginsSpec`（[#L844-L862](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-driver/test/PluginsSpec.hs#L844-L862)）が通ることで判断した。
- golem-doc の `AssembleSpec`、仕様書の「目次と文書構造の参照」、docs/markup.md の「索引」と「相互参照」、manual-dev の IR の章（82 ページを目で見た）、[docs/adr/0126](../adr/0126-glossary-plugin.md) のステータスの行の句。[golem-doc ADR 0007](../golem-doc/adr/0007-plugin-channel-lists.md) は変わっていない。
- 申告（HTML の検査を golem-html でなく `PluginsSpec` に置いた）は妥当である。golem-html のテストは `Book` を手で組み、S1 を通さないので、S1 が除くことは golem-html の単体では確かめようがない。

### 所見

**F-20（逸脱、申告なし、低）：題が索引の印だけの見出しへの `[ref-title]` が G04006 になる。**
実機で `@label c`、`# [index reading=くみ: 組]`、`[ref-title c]` が `error[G04006]: 題を持たない要素への参照です: c` になることを確かめた。
0145 の前は `ltTitle` に印が残って空でなかったので、この diagnostic は出なかった（コードの読みによる）。
出力に文字のない題を参照しているので、エラーにするのは原則に沿うが、ADR は diagnostic が変わらないと書いた。
記録に残す。

**F-21（テスト欠落、低）：チャネルの項目の入れ子（圏点の中など）の PDF の端から端までの検査がない。**
`ReferencesSpec` の入れ子は索引の印だけ、`PluginsSpec` の `[term]` は最上位だけである。
同じ `withoutAnchors` を通るので、危険は小さい。

## ADR のない修正のプルリクエスト

### PR #504（前回の F-38）：sou-ruby と first-ruby のコードを後ろの部分だけにする

- コードは `no-words`、`unread`、`utf8`、`tsv`、`dict`、`no-command` で、`ruby_common::read_words` は前置きの引数を持たない（[sou-ruby/lib.rs#L152-L189](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/plugins/sou-ruby/src/lib.rs#L152-L189)、[first-ruby/lib.rs#L78-L107](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/plugins/first-ruby/src/lib.rs#L78-L107)）。wasm は作り直され、`PluginsSpec` と仕様書（[L3121](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/docs/specifications.md#L3121)、[L3143](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/docs/specifications.md#L3143)）はほかの見本の節と同じ形になった。実機で `first-ruby/no-words` と表示されることを確かめた。
- 前回の F-38 は閉じている。

**F-22（文書の不一致、中）：[docs/adr/0130](../adr/0130-sou-ruby-plugin.md) と [0131](../adr/0131-first-occurrence-ruby-plugin.md) の字面と違う形に変えたことが、どの ADR にも記録されていない。**
[0130#L127-L130](../adr/0130-sou-ruby-plugin.md) と [0131#L136-L138](../adr/0131-first-occurrence-ruby-plugin.md) は `sou-ruby-no-words`、`first-ruby-tsv` などを表で定め、ステータスの行は素の `採択` のままである。
PR #504 は「0108 の読み替えで、ADR は変えない」とした。
前回の監査もその読み替えを求めたので、変更そのものは妥当である。
しかし、プロジェクトの規則では、コミット済みの ADR の決定と違う形にするときは、ステータスの行の句か修正の ADR で記録する。
今は [docs/adr/0136](../adr/0136-missing-plugin-data-at-load.md) の「F-38 を別の変更が直すときは、その形に従う」という条件の一文だけが、この読み替えに触れている。
0130 と 0131 を読む人は、実機が出さないコードを見る。
0130、0131（と同じ字面の 0128、0129）のステータスの行に、「コードは後ろの部分だけ（[ADR 0108](../adr/0108-plugin-diagnostic-codes-and-spans.md)）」の句を足すのが最小の直し方である。

### PR #505（前回の F-14）：コードブロックのキーの式の範囲に一つのコード

- `codeArgs` の `scalar` は、式の diagnostic を報告して `Nothing` を返し、呼び手は `Nothing` に G02069 を重ねない（[File.hs#L1616-L1636](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-eval/src/Golem/Eval/File.hs#L1616-L1636)）。`numbersArg`、`lines` と `highlight` の `lineRanges` も一つのコードである。実機で `file=[= 1...3]` が G02113 だけ、`numbers=[= nope]` が G02002 だけになることを確かめた。`FileSpec` の二つのテスト、diagnostics.md の G02069 と G02113、docs/markup.md。
- 前回の F-14 は閉じている。

**F-23（文書の不一致とテスト欠落、低）：文字に読めない式の値の G02069 は、値が空のままである。**
実機で `file=[= [1]]` が `error[G02069]: file の値が正しくありません: `（値なし）になることを確かめた（[File.hs#L1621](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-eval/src/Golem/Eval/File.hs#L1621) の `fromMaybe ""`）。
diagnostics.md のメッセージの形 `<キー> の値が正しくありません: <値>` と合わない。
前回の F-14 が触れた「値が空」の G02069 は、この経路に残った。
`file=[= [1]]`、`diff=[= 1]`、`numbers=[= nope]` のテストもない。

### PR #506（前回の F-44）：本体のある `@manifest` の引数の誤りを出す

- `fileSettings` の `step` は、引数なしなら G02115 と G02097、本体があれば `argDiags`（G02114、G02052、G02077、G02116 を書いた順）の後に G02097 を出し、どちらも `[source]` には当てない（[Settings.hs#L113-L128](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-eval/src/Golem/Eval/Settings.hs#L113-L128)）。
- 実機で `@manifest *[[1]] title=x` に本体を付けたものが G02114 と G02097 で G02050 を出さず、`@manifest` だけに本体を付けたものが G02115 と G02097 の両方になることを確かめた。`FileSpec` の五行の表と、無視した `@manifest` のキーに G02050 と G02051 を出さないという判断は、[ADR 0132](../adr/0132-setting-command-codes-by-cause.md) の表（`@manifest title=x` に本体で G02097 だけ）と整合する。diagnostics.md の G02097 はこれを書く。
- 前回の F-44 は閉じている。

**F-24（テスト欠落、低）：G02115 と G02097 が同時に出ることのテストがない。**
`FileSpec` の G02115 は本体のない `@manifest` だけである。
実機では両方出る。

### PR #508：前回の監査の文書の所見の修正

- 申告された F-01、F-04、F-05、F-07、F-11、F-23、F-24、F-27、F-32、F-36、F-39、F-43、F-46 のすべてが、4f86b945 で直っていることを確かめた。F-07 は G06005 の `context` と `blocks`、G06009 の 0108、0122、0123 の文言を `Golem.Plugin` の文字列と照合した（五つを抜き取り、一字一句一致）。F-04 は `git ls-files -s plugins/wasm` で八本とも 100755 である。
- 「直さない」とした F-16 は #519 が、F-02 と F-40 は 0138 と 0133 が引き取った。

所見はない。

### PR #519（前回の F-16）：G02113 を引数の位置に出す

- `plainArgValue` と `naturalArg` は `A.Located A.ArgValue` を受け、G02113 をその span に出す。`[number-text ...]`、`@blank-line`、`@need-lines`、`@number`、`@toc depth=`、`@figure page=` が引数の span を渡し、キーワード引数は `キー=値` の全体である。`FileSpec` は十一か所の span を固定する（[FileSpec.hs#L792-L806](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-eval/test/FileSpec.hs#L792-L806)）。diagnostics.md の G02113 は位置を明記する。
- 実機で `@toc depth=1...3` の G02113 が 11:6（`depth=` の先頭）、`@toc depth=-1` の G02103 が 13:1（コマンド）に出ることを確かめた。
- 前回の F-16 は閉じている。

**F-25（文書の不一致、低）：キーワード引数の位置の慣行が二層になっており、G02019 と G02104 の位置は文書にない。**
`キー=値` の全体を指すのは、G02077、G02116（0132）、コードブロックの G02069、`lines=` の G02105 から G02110（0113）、G02113（#519）で、新しい ADR の慣行として一貫している。
一方、同じ箇所の G02025（`@toc depth`）と G02075（`@figure page`）、G02019、G02103、G02104 はコマンドの位置である。
diagnostics.md は G02103 の「コマンドの引数ならコマンド」を明記するが、G02019（[L1163-L1167](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/docs/diagnostics.md#L1163-L1167)）と G02104（語の場合）は位置を書かない。
#519 のスコープの注のとおり、文書化された既存の振る舞いだが、F-06 と合わせて、位置の規則を一つの ADR で決めるのがよい。

### PR #522：`scripts-macos` の六つのテストを同時に走らせる

- `scripts/ci/run-all.sh` は各スクリプトを `sh SCRIPT </dev/null` で背景に走らせ、`wait` の後に引数の順で `==> SCRIPT: exit CODE, SECONDS s` と出力を印字し、失敗ごとに標準エラー出力に一行、終了コード 1、引数なしは 2 である。時間は `date +%s` の差で、`$SECONDS` に依らない。`scripts-macos` は同じ六本を一つの手順で走らせ（[ci.yml#L584](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/.github/workflows/ci.yml#L584)）、`PATH` はジョブの `env` のままで、`scripts-linux` は変わっていない。六本のテストはどれも `mktemp -d` の中で動き、共有する状態がない。`test.sh` に七つの検査がある。
- 時間は PR のコメントに投稿され、41831996929 で `scripts-macos` が 78 秒（以前は 109 から 167 秒）であることを確かめた。

**F-26（運用の逸脱、中）：ADR なしの CI の変更である。**
PR #522 は「同じランナー、同じ `PATH`、同じテストで、検査が変わらないので ADR はない」とする。
検査の中身と失敗の検出（`|| code=$?`、シグナルでの死も 128+n で捕まる）に穴はなく、[docs/adr/0079](../adr/0079-ci-scripts-with-bsd-tools.md) にも反しない。
しかし、同じ日の 0140（ランナーの分割）と 0141（キャッシュの中身）は、検査を変えない CI だけの変更に ADR を書いており、#522 だけが例外である。
新しいスクリプト（`run-all.sh`、40 行）の仕様と、トレードオフ（一本がハングするとジョブの時間切れで殺され、`trap` が作業ディレクトリを消すので、六本のどの出力も残らない。以前は逐次に流れていた）は、どこにも記録されていない。
グローバルの規則「実装に入るまえに必ず ADR を作成する」に照らして、短い ADR で事後に記録するのがよい。

## 前回の監査の所見の現状

| 前回の番号 | 現状 |
| --- | --- |
| F-02、F-08、F-13、F-15、F-17、F-18、F-21、F-25、F-26、F-31、F-40 | [ADR 0138](../adr/0138-host-independent-crate-metadata-for-plugins.md)、[0139](../adr/0139-plugin-diagnostic-code-starts-with-letter.md)、[0134](../adr/0134-numbers-range-code-is-g02113.md)、[0135](../adr/0135-range-words-read-as-range-expressions.md)、[0142](../adr/0142-import-arguments-are-not-spread.md)、[0143](../adr/0143-style-spread-diagnostic-per-argument.md)、[0136](../adr/0136-missing-plugin-data-at-load.md)、[0137](../adr/0137-plugin-image-folder-collision-g08102.md)、[0144](../adr/0144-figure-captions-hold-paragraphs-only.md)、[0145](../adr/0145-title-copies-drop-anchor-inlines.md)、[0133](../adr/0133-third-party-licenses-of-sample-plugins.md) が引き取り、実装済み（この記録の各節） |
| F-14、F-38、F-44、F-16 | #505、#504、#506、#519 が直した（この記録の各節）。F-14 の空の値は F-23 に残る |
| F-01、F-04、F-05、F-07、F-11、F-23、F-24、F-27、F-32、F-36、F-39、F-43、F-46 | #508 が直した |
| F-03、F-06、F-09 | 手順と履歴の記録で、直す対象がない |
| F-10 | 未対応。`golem explain` の `/` の前の検査はない（0139 が「実装しないこと」に置いた）。F-12 と合わせて扱うのがよい |
| F-12、F-19、F-20、F-22、F-28、F-37 | 未対応（テスト欠落、低） |
| F-29、F-30、F-33、F-34、F-35、F-41、F-42、F-45 | 未対応（低）。F-41 の `no-command` は #504 の後も残り、ADR にも仕様書にもない |

## 横断的な所見

**ADR の外で決めたことの記録**：前回の監査が「ADR の外で決めたこと」として挙げた三つは、0133 と 0138 で引き取られ、bar-chart のコードの名前だけが記録なしのままである。
この日の実装では、新たに三つが ADR の外で決まった。
sou-ruby と first-ruby のコードの読み替え（F-22）、`scripts-macos` の並列化（F-26）、`cargo tree` の `--no-dedupe`（F-01）である。
前の二つは中で、どちらも短い ADR かステータスの行の句で閉じられる。

**ADR の意図と実装の字面**：F-16（索引のキャッシュ）は、ADR の「実装すること」を字面どおりに入れ、`scripts/ci/test.sh` も字面を検査するが、`actions/cache` の仕組みのために目的を果たしていない。
ADR の自動テストにできない確かめ方（二回目に小さいこと）が満たされていないのに、`docs/ci-timings/` は別の説明を書いて閉じた。
手で確かめることの結果が見積もりと合わないときは、原因を特定してから記録に書くのがよい。

**運用**：F-13（CI の完了前のマージ）は、ルールセットの管理者の bypass によって起きた。
実害はなかったが、`gh pr merge --auto --merge` を使う実装のレーンの手順と、ルールセットの設定のどちらを規範とするかを決めておくのがよい。

**位置の規則**：G02113 を引数に移した結果（#519）、同じ箇所で原因ごとに位置が違う状態になった（F-06、F-25）。
0135 と #519 はどちらも位置を既存の慣行として範囲外に置いた。
キーワード引数の位置（全体かコマンドか）と、語の範囲の値の誤りの位置を、一つの ADR で決めるのがよい。

**決定性と出力**：十三の ADR と六つの修正のどれも、出力を黙って変えていない。
0144 と 0145 の出力の変化は ADR が予告したもので、見た目の回帰テストの参照は手元のビルドと一致し、ゴールデンと決定性のテストは通った。
F-20（G04006）だけが、ADR の予告にない diagnostic の変化である。

**build-depends**：十九のプルリクエストで、golem-\* のあいだの build-depends は変わっていない。

**申告の質**：申告された逸脱（F-01、F-03、F-08、F-18、0144 と 0145 の二つずつ、F-12 の注）はどれも妥当である。
申告のない中の所見は F-16 と F-22 の二つで、F-13 と F-26 は運用の判断である。

## 要約表

| 番号 | 所見 | 分類 | 重大度 | 根拠 |
| --- | --- | --- | --- | --- |
| F-12 | `golem explain` がコードの形の規則の写しを持ち、`x/404` を通す | 逸脱（申告あり） | 中 | cli/Main.hs#L156-L166、実機 |
| F-13 | PR #509 が最終コミットの CI の完了前にマージされた | 運用の逸脱 | 中 | 実行 41816022322、ルールセット 24998069 |
| F-16 | `!01-index.tar.gz` の除外が効かず、索引のキャッシュは 17 MB しか縮まない | 逸脱（申告なし） | 中 | actions/cache の `resolvePaths`、キャッシュ 242 MB |
| F-22 | 0130 と 0131 の字面と違うコードの形が、どの ADR にも記録されていない | 文書の不一致 | 中 | 0130#L127-L130、0131#L136-L138 |
| F-26 | `scripts-macos` の並列化が ADR なし、トレードオフが未記録 | 運用の逸脱 | 中 | PR #522、run-all.sh |
| F-01 | `cargo tree` に `--no-dedupe` | 範囲外の変更（申告あり） | 低 | plugin-licenses.sh#L66-L69 |
| F-02 | `curl` の差し替えが `PATH` による | 逸脱（申告なし） | 低 | plugin-licenses.sh#L23、#L146 |
| F-03 | `gh release create` の引数を足さずグロブに頼る | 逸脱（申告あり） | 低 | release.yml#L286-L290 |
| F-04 | README と使い手のマニュアルの挿入位置が指定と違う | 文書の不一致 | 低 | README.md#L66-L68、10-plugins.gm#L118-L122 |
| F-05 | `UPSTREAM` のテストの入力が生成物に依る | テスト設計 | 低 | test.sh#L262 |
| F-06 | 範囲の語の G02104、G02106 の位置が箇所で揺れ、文書と合わない | 文書の不一致 | 低 | File.hs#L2154、diagnostics.md#L3542、実機 |
| F-07 | `numbers="5...5"` の文字列が範囲の語として読まれる | 範囲外の観察 | 低 | File.hs#L2370、実機 |
| F-08 | null と行の検査が golem-plugin にある | 逸脱（申告あり） | 低 | Plugin.hs#L882 |
| F-09 | null の警告で読み込まれることのテストがない | テスト欠落 | 低 | PluginsSpec.hs |
| F-10 | G08102 のテストがプラグインのある本で、EPUB と `golem check` の検査がない | 文書の不一致、テスト欠落 | 低 | PluginsSpec.hs#L352-L359 |
| F-11 | 一引数の形の検査がない | テスト欠落 | 低 | rustc-wrapper-test.sh |
| F-14 | `test-suites.sh` の引数が広く、`suites: none` がある | 範囲外の変更 | 低 | test-suites.sh#L5-L7、ci.yml#L140 |
| F-15 | `scripts/ci/test.sh` の gawk の警告 | 低 | 低 | test.sh#L999 |
| F-17 | `<種類>` の列挙が ADR と実装で違う | 文書の不一致 | 低 | File.hs#L1230-L1241、diagnostics.md#L3875 |
| F-18 | 図番号の端から端までの検査がない | テスト欠落（申告あり） | 低 | FileSpec.hs#L423-L426 |
| F-19 | 見た目の回帰の参照が変わり、奥付が最後のページにあふれる | テスト欠落 | 低 | PR #523、manual の 324 ページ |
| F-20 | 印だけの題への `[ref-title]` が G04006 になる | 逸脱（申告なし） | 低 | Assemble.hs#L620、実機 |
| F-21 | チャネルの項目の入れ子の PDF の検査がない | テスト欠落 | 低 | ReferencesSpec.hs、PluginsSpec.hs |
| F-23 | 読めない式の値の G02069 が空の値 | 文書の不一致、テスト欠落 | 低 | File.hs#L1621、実機 |
| F-24 | G02115 と G02097 の同時のテストがない | テスト欠落 | 低 | FileSpec.hs |
| F-25 | キーワード引数の位置の慣行が二層で、G02019 と G02104 の位置が文書にない | 文書の不一致 | 低 | diagnostics.md#L1163-L1167 |

高の所見はない。
中の五つのうち、コードの振る舞いに関わるのは F-12 と F-16、決定の記録に関わるのは F-22、運用に関わるのは F-13 と F-26 である。
