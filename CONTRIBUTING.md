# Golem への貢献

[English](./CONTRIBUTING.en.md)

この文書は日本語版を正とする。
英語版は翻訳であり、内容が食い違うときは日本語版に従う。

Golem への変更は、どれも ADR（Architecture Decision Record）から始まる。
仕様を決めてからテストを書き、テストを失敗させてから実装する、という順番を守ってもらう必要がある。
この文書は、その順番と、リポジトリの約束ごとをまとめたものである。

## 開発環境

ビルドとテストの手順は [README.md](./README.md) の Development の節にある。
クローンしたら、まず Git フックを有効にする。

```bash
git config core.hooksPath .githooks
```

フックは [adr-guard](https://github.com/tett23/adr-guard) の v0.8.3 以降を呼び出すので、あらかじめインストールしておく（`cargo install --git https://github.com/tett23/adr-guard --tag v0.8.3`）。
`.githooks/pre-push` は、仕様を変えたのにマニュアルを直していないブランチの push を止める（「ドキュメント」の節）。
この設定はリポジトリに保存されないため、クローンのたびに実行する。

## 変更の流れ

1. ADR を書いて、レビューを受ける。
2. ADR のテスト設計にあるテストを書き、失敗することを確かめる。
3. 実装して、テストを通す。
4. 仕様書と README を更新する。
5. ブランチを push して、プルリクエストを作る。
6. CI が通ったら、`main` に no-ff でマージする。

誤字の修正や、仕様に影響しないドキュメントの修正には ADR は要らない。
二つのマニュアルと [docs/manual-policy.md](./docs/manual-policy.md) の変更も、メンテナーが求めない限り ADR を書かず、プルリクエストで決める。
迷ったら ADR を書く。

## ADR

### 置き場所と名前

特定のモジュールに属する ADR は `docs/<モジュール>/adr/` に置く。
モジュールをまたぐ ADR は `docs/adr/` に置く。

ファイル名には、`0001-feature-details.md` のように 4 桁の連番を付ける。
連番のあとは、内容がわかる kebab-case の名前にする。

### 構成

ADR は次の形で書く。
データ構造やアルゴリズムを変える場合は、その節も立てる。
検討の経緯として残しておきたいことがあれば、ほかの節を足してよい。
ADR は日本語で書く。

```markdown
# ADR 0001: タイトル

ステータス: 提案

## 文脈

## 実装すること

## 実装しないこと

## テスト設計

## トレードオフ
```

ステータスには、提案、採択、採択（未実装）、却下、破棄のいずれかを書く。
採択（未実装）は、採択したがまだ実装していない ADR に使い、実装を終えたら採択に変える。
採択（未実装）の ADR は `adr-guard unimplemented` で一覧にできる（[docs/adr/0048](./docs/adr/0048-update-adr-guard-to-v0.8.3.md)）。
あとの ADR が一部を置き換えた場合は、「採択→○○（変更部分）は [ADR NNNN](...)」のように、置き換えた ADR をリンクで示す。

### 変更してはいけない

コミットした ADR は、ステータスの行を除いて変更できない。
`.githooks/pre-commit` と CI の `adr` ジョブが、変更、削除、リネームを拒否する。
ステータスの行の変更（`--allow-status`）と、リンクを付ける、外す、リンク先を変えるだけの変更（`--allow-links`）は許す（[docs/adr/0010](./docs/adr/0010-update-adr-guard-to-v0.5.0.md)、[docs/adr/0032](./docs/adr/0032-update-adr-guard-to-v0.8.2.md)）。
リンクのテキストの変更は許さない。
ADR は、行頭が `ステータス:` のステータスの行をちょうど一つ持つ。
無い ADR と二つ以上ある ADR は、フックと CI の `adr` ジョブが拒否する。
`adr-guard check-status` で一覧にできる（[docs/adr/0011](./docs/adr/0011-update-adr-guard-to-v0.8.0.md)）。
文書の中の ADR の参照にはリンクを付ける。
リンクのない参照は CI の `adr` ジョブが拒否する。
`adr-guard links --fix` で直せる。

仕様を変えたくなったら、元の ADR を書き換えずに、新しい連番の ADR を書く。
ADR をやめる場合は、ステータスを破棄にして、理由を [docs/specifications.md](./docs/specifications.md) に書く。

ADR はレビューを受けるまでコミットしない。
提案の段階で内容を直せるのは、コミットするまでのあいだだけだからだ。

## テストと実装

ADR のテスト設計に書いたテストを先に書き、失敗することを確かめてから実装する。
設定の値のように自動テストを書けない変更は、テスト設計に確かめ方を書いておき、実装したあとに実際に動かして確かめる。
採択済みの ADR のテスト設計が「10 秒以内」「5 秒以内」のように時間で書いた検査は、計算が止まらないことを検出する意図として読み、テストの時間切れを 30 秒にして、上限で拒んだことを断言する（[docs/adr/0073](./docs/adr/0073-time-bounds-in-tests.md)）。
これは golem-pdf と golem-svg の外のテストの規則である。
golem-pdf と golem-svg のテストでは、時間の上限に `modules/golem-test-support` の `Golem.TestSupport.TimeLimit` にある `withinTimeLimits hangLimits` を使い、プロセスの CPU 時間の 60 秒と実時間の 300 秒の二つで止める。
時間の上限を付けるテストの CPU 時間は、単独で走らせて 10 秒以内に収める（[docs/adr/0091](./docs/adr/0091-cpu-time-limits-in-pdf-and-svg-tests.md)）。

外部ツール（`cddl`、`qpdf`、`openssl` など）を使うテストは、`modules/golem-test-support` の `Golem.TestSupport.ExternalTool` にある `needsTool` か `optionalTool` で書く（[docs/adr/0028](./docs/adr/0028-shared-test-support-package.md)）。
ツールがなければ `SKIP` と表示され、`GOLEM_REQUIRE_EXTERNAL_TOOLS=1` のもとでは失敗になる。
この変数の値は `1` だけが有効である。
飛ばしたテストの数は、テストのスイートの最後に標準エラー出力へ一行で出る（[docs/adr/0074](./docs/adr/0074-test-switches-by-environment-variables.md)）。
テストを切り替える環境変数を新しく読むときは、golem-test-support の `envFlag` で読み、値が `1` のときだけ有効にする。
golem-test-support に依存してよいのはテストスイートだけであり、ライブラリと実行ファイルが依存すると CI の `build` ジョブの `scripts/ci/test-only-deps.sh` が失敗する。
どのテストスイートも、ADR なしで golem-test-support を build-depends に足してよい（[docs/adr/0086](./docs/adr/0086-any-test-suite-may-depend-on-test-support.md)）。
二つ以上のパッケージのテストが同じ補助を使うなら、写さずに golem-test-support に置く。
一つのテストスイートしか使わない補助は、golem-test-support に置かず、そのパッケージのテストに置く。
golem-test-support は golem のパッケージに依存してはいけない。
依存すると、同じ `scripts/ci/test-only-deps.sh` が失敗する（[docs/adr/0087](./docs/adr/0087-test-support-dependencies-and-shared-fixtures.md)）。

ゴールデンのファイルは手で作らず、`--accept` で書き出す（手順は [README.md](./README.md) の Development の節）。
書き出したファイルの差分を読み、意図した出力であることを確かめてからコミットする。
CI はテストに `TASTY_NO_CREATE=true` を付けるので、ゴールデンのファイルを消したり名前を変え間違えたりすると失敗する。

Golem は、同じ入力から常に同じバイト列を出力する。
出力を変える変更は、x86-64 と aarch64 で同じ結果になることを CI の `determinism` ジョブで確かめる。
時刻、乱数、ハッシュ表の走査順、ロケールのように、環境で変わるものを出力に混ぜないよう注意する。

`scripts/` の下のスクリプトは、POSIX の `sh` で書き、macOS の BSD 版の `awk`、`sed`、`find`、`grep` でも動くようにする。
`sed -i` の引数のように GNU 版と BSD 版で違う書き方は避ける。
CI の `scripts-macos` ジョブが、`PATH` をシステムの道具だけにして、`scripts/` の下の五本のテストを macOS で走らせる（[docs/adr/0079](./docs/adr/0079-shell-tests-on-macos.md)）。

ライセンスに問題がなく、再実装がやさしいものは、依存に加えずに再実装する。
その場合は、本家のテストを参考にして、テストを十分に厚く書く。
必要な機能が限られているなら、その機能だけを実装してよい。

[README.md](./README.md) にある固定したネイティブライブラリ（HarfBuzz、FreeType、wasmtime、zlib、hyph-utf8）のバージョンを上げるときは、ADR を書く。
wasmtime のバージョンを上げるときは、`scripts/wasmtime-licenses.sh` で `licenses/wasmtime-v<バージョン>/`（`libwasmtime.a` に入った Rust のクレートなどのライセンスの文書）を作り直し、生成物もコミットする（[docs/adr/0007](./docs/adr/0007-third-party-licenses.md)）。
このスクリプトはネットワークに接続し、`cargo` と `rustup` を要する。
`c-objects.tsv` の構成要素の列は、スクリプトが埋めないので手で埋める。
`cabal.project.freeze` で固定した依存のバージョンを変えるときも、変更の理由をプルリクエストに書く。
リリースノートを書く Claude Code のバージョンは、`mise.toml` の `"npm:@anthropic-ai/claude-code"` に正確な値で固定してある（[docs/adr/0044](./docs/adr/0044-release-workflow-hardening.md)）。
上げるときは `mise.toml` を変えるプルリクエストを出し、新しいバージョンの `claude --help` に `--tools` と `--strict-mcp-config` があることを確かめる（`scripts/release/test.sh` は、そのバージョンの `claude` があれば確かめる。CI の `release-scripts` ジョブは、mise でそのバージョンを入れて必ず確かめる。[docs/adr/0058](./docs/adr/0058-run-skipped-checks-in-ci.md)）。
Claude Code を入れる mise の版と、その版の Linux の x86-64 の実行ファイルの SHA-256 は、`.github/workflows/ci.yml` と `.github/workflows/release.yml` の `MISE_VERSION` と `MISE_SHA256` に同じ値で固定してある（[docs/adr/0085](./docs/adr/0085-pin-mise-version-in-workflows.md)）。
上げるときは二つのファイルを変えるプルリクエストを出し、SHA-256 を求めた手順を本文に書く。
SHA-256 は次の手順で求める。
jdx/mise の GitHub の release から、`mise-v<版>-linux-x64.tar.zst`、`SHASUMS256.txt`、`SHASUMS256.txt.minisig` を取る。
`SHASUMS256.txt` の署名を mise の minisign の公開鍵で確かめ、圧縮ファイルをその値で確かめる。
展開した `mise/bin/mise` の SHA-256 を求め、同じ版の `mise-v<版>-linux-x64` の `SHASUMS256.txt` の値と一致することも確かめる。
CI の `release-scripts` が通れば、action が新しい SHA-256 で実行ファイルを確かめたことになる。
リリースノートから兄弟のリポジトリへリンクするときは、`scripts/release/allowed-links.txt` に `https://github.com/tett23/<リポジトリ>/` の 1 行を足すプルリクエストを出す。
ghcup を上げるときは、`scripts/release/build-linux.sh` の ghcup のバージョン、ブートストラップのスクリプトのコミット、その SHA-256 を一緒に変える。

## 整形と検査

Haskell のコードは fourmolu 0.21.0.0 で整形し、hlint 3.10 の指摘をなくす。
どちらも CI の `format` ジョブで検査する。
生成したパーサー（`modules/golem-parser/src/Golem/Parser/Generated.hs`）と、ラベルを外した文法（`modules/golem-parser/test/StrippedGrammar.hs`）は対象外である。

文法（`modules/golem-parser/grammar/Golem.hpeg`）を変えたら、`scripts/gen-parser.sh` で生成し直して、生成物もコミットする。
このスクリプトは、ラベルを外した文法も生成する。
golem-parser のテストは、二つの文法が同じ入力を受理することを確かめる。
文法にラベルを足すときは、ラベルを外しても受理する言語が変わらないことを確かめ、理由のコメントを添えて `%safe` を書く。
`scripts/gen-parser.sh` は peg-hs の警告を誤りとして扱うので、`%safe` のないラベルがあると生成が失敗する（[golem-parser ADR 0007](./docs/golem-parser/adr/0007-grammar-label-safety.md)）。

## ドキュメント

ADR で仕様が変わったら、同じプルリクエストで [docs/specifications.md](./docs/specifications.md) と [README.md](./README.md) も更新する。
この二つは、`main` で常に最新でなければならない。
モジュールの実装の詳細は `docs/<モジュール>/specifications.md` に書く。
どのバージョンで何を扱うか、まだ実装していない項目、手で確かめる項目、未決事項、課題にしなかった事項は [docs/roadmap.md](./docs/roadmap.md) に書き、仕様書には書かない。
実装を終えたら、その項目を roadmap.md から消し、振る舞いを仕様書に書く。

仕様書から ADR を参照するときは、ADR のファイルへのリンクを付ける。
新しい用語を導入したら、[docs/glossary.md](./docs/glossary.md) にも加える。

マニュアルは、使い手のマニュアル `manual/` と開発者のマニュアル `manual-dev/` の二つで、どちらも Golem のプロジェクトとして書き、Golem で組む（[docs/adr/0024](./docs/adr/0024-manual-audiences-and-policy.md)）。
読み手、文体、説明の厚さ、根拠と脚注の書き方、章立て、コードの表示は、方針の文書 [docs/manual-policy.md](./docs/manual-policy.md) に従う。
ADR を実装して使い手から見える振る舞いが変わるときは同じプルリクエストで `manual/` を、開発の手順や仕組みが変わるときは `manual-dev/` を直す。
マニュアルには、採択して実装を終えた仕様だけを書く。
マニュアルを編集する前に、一度 `sh scripts/manual/build-info.sh manual`（と `manual-dev`）を実行して、奥付が読む `common/build-info.gm` を作っておく。
二つのマニュアルは `scripts/manual/build.sh` で、エラー、警告、notice を一つも出さずに組めなければならない（CI の `build` ジョブで走る）。
`silence-notices` と `--no-notices` で、notice を消してはいけない。
`.githooks/pre-push` と CI の `manual` ジョブ（`docs.yml`）は、次のブランチを止める。

- docs/markup.md か docs/specifications.md を変えて、`manual/` も `manual-dev/` も変えていないブランチ
- CONTRIBUTING.md か CONTRIBUTING.en.md を変えて、`manual-dev/` を変えていないブランチ

既知の不具合を足すときのように、変更がマニュアルに書いた事柄を変えない場合は、ブランチのコミットのどれかのメッセージの末尾に `Manual: unchanged` というトレーラーの行を書く。
フックは手元の `origin/main` との分岐点から検査するので、`main` に入った変更で止まったときは `git fetch` をしてから push し直す。

ビルドやテストが `docs/` の下の文書を読むようにしたときは、その文書を `scripts/ci/needs-build.sh` の一覧に加える。
一覧にない文書は docs だけの変更として扱われ、変えてもビルドが走らない。
コードの中では、文書のパスを一つの文字列（`"../../docs/diagnostics.md"` のような形）で書く。
CI の `changes` ジョブは、そうした文字列を拾って一覧と照らし合わせる（[docs/adr/0021](./docs/adr/0021-docs-workflow-and-ci-gate.md)）。
パスを `"docs" </> "diagnostics.md"` のように組み立てるときは、その行に `-- docs-refs: docs/diagnostics.md` の注釈で読む文書を書く。
`"docs"` という文字列を含む行に注釈がないと、同じジョブ（`scripts/ci/docs-refs.sh`）が失敗する（[docs/adr/0069](./docs/adr/0069-lint-scripts-bypassed-by-plain-rewrites.md)）。

すべてのパッケージは、網羅していない `case` と関数の定義を `-Werror=incomplete-patterns` でエラーにする（[docs/adr/0027](./docs/adr/0027-exhaustive-command-dispatch-by-types.md)）。
`modules/` にパッケージを足したときは、cabal ファイルの `common warnings` の `ghc-options` にこのフラグを書き、各コンポーネントで `import: warnings` とする。
付け忘れると、CI の `changes` ジョブ（`scripts/ci/incomplete-patterns.sh`）が失敗する。

`unsafePerformIO` とその仲間（`unsafeDupablePerformIO`、`unsafeInterleaveIO` など）は、`scripts/ci/unsafe-io-allowed.txt` に書いた定義でだけ使う（[docs/adr/0034](./docs/adr/0034-fewer-unsafe-perform-io.md)）。
IO で書ける処理は IO のエッジに置き、どうしても純粋な関数の内側から C のライブラリを呼ぶときだけ、一覧に定義と残す理由を足す。
一覧とソースが食い違うと、CI の `changes` ジョブ（`scripts/ci/unsafe-io.sh`）が失敗する。

`-threaded` でビルドする実行ファイルとテストのスイートは、`-with-rtsopts=-N` でもリンクし、起動のときから capability をプロセッサの数だけ持たせる。
コードの中では `setNumCapabilities` を呼ばない。
二つの呼び出しが同時に capability を増やすと、GHC 9.10.3 のランタイムが止まる。
tasty 1.5.4 も、capability がプロセッサより少ないと起動の時点でこれを呼ぶので、`-N` で呼ばせないようにする。
どちらかを破ると、CI の `changes` ジョブ（`scripts/ci/rts-capabilities.sh`）が失敗する。

監査の記録や性能計測のスナップショットは、`docs/` の下に用途ごとのディレクトリを作って置く。
これらもコミットしたあとは変更しない。
`docs/audit/`、`docs/audits/`、`docs/benchmarks/`、`docs/benchmark/` に置いた記録は、フックと CI の `adr` ジョブがコミット後の変更、削除、移動を拒否する（[docs/adr/0011](./docs/adr/0011-update-adr-guard-to-v0.8.0.md)、[docs/adr/0012](./docs/adr/0012-update-adr-guard-to-v0.8.1.md)）。
`docs/ci-timings/` のようにほかの名前のディレクトリに置いた記録は検査されないので、約束とレビューで守る。

### 日本語の文章

日本語の文章は、一文ごとに改行する。
箇条書きの項目と表のセルは、一つの項目やセルに複数の文を書いてよい。
地の文では、ダッシュ（——）を使わない。
中黒（・）は、並列を表すことにだけ使わない。
並べるときは、読点か「と」でつなぐ。
外来語の区切りのような、並列でない中黒は使ってよい。

用語は [docs/manual-policy.md](./docs/manual-policy.md) の規則に従う。
開発者のマニュアルの規則（「診断」ではなく diagnostic、「資産」ではなくアセット、「機械」ではなくマシンか計算機、「お知らせ」ではなく notice と info）と、二つのマニュアルに共通する規則（「書体」と「フォント」の使い分け、version は「版」ではなくバージョン、public domain は「公有」ではなくパブリックドメイン）は、`docs/` の仕様書、README、CONTRIBUTING、新しい ADR にも当てはめる。
コミット済みの ADR は変えられないので、古い用語のまま残す。

文字と行で判定できる規則は、textlint で検査する（[docs/adr/0036](./docs/adr/0036-textlint-for-documents.md)）。
規則、用語の辞書、バージョンを固定した npm のパッケージは `tools/textlint/` にある（[tools/textlint/README.md](./tools/textlint/README.md)）。
Node を入れてから `sh scripts/ci/textlint.sh` を実行する。
初めての実行でパッケージを入れる。
`TEXTLINT_ARGS=--fix` を付けると、直せる違反を直す。
対象は、`docs/` の Markdown（ADR、`docs/audits/` のような記録を除く）、README.md、CONTRIBUTING.md、ブランチで加えた ADR、二つのマニュアルの原稿である。
CI の `textlint` ジョブ（`docs.yml`）も同じスクリプトを走らせる。
意味で選ぶ語（「版」と「バージョン」、「書体」と「フォント」）と、文の長さは検査しないので、レビューで確かめる。

## Git

### コミット

コミットメッセージは英語で書く。
一つのコミットには、一つのまとまった変更だけを入れる。

### ブランチとマージ

`main` に直接 push せず、ブランチを切ってプルリクエストを作る。
マージは常に no-ff で行う。
`main` には保護の規則があり、プルリクエストを経ない push と、マージコミット以外のマージ（squash と rebase）を拒否する。
マージには、CI の `ci`（`ci.yml`）と、`adr`、`manual`、`textlint`（`docs.yml`）の四つの検査が通っている必要がある（[docs/adr/0021](./docs/adr/0021-docs-workflow-and-ci-gate.md)、[docs/adr/0022](./docs/adr/0022-manual-as-typesetting-sample.md)、[docs/adr/0036](./docs/adr/0036-textlint-for-documents.md)）。

`main` の rebase と force push は禁止する。
例外は、API キーのような秘密情報を誤ってコミットした場合だけである。
自分のブランチは、マージするまでなら rebase してよい。

### タグとリリース

`v` で始まるタグをリリースとして扱う。
`v0.0.1-rc` のようにバージョンのあとに識別子が付くタグは、プレリリースとする。
リリースノートは GitHub の Releases に英語で書く。
変更点は、追加、変更、削除、修正のように項目を分けて書き、できれば各変更のコミットまたはプルリクエストと ADR を絶対リンクで添える。

リリースの手順は次のとおりである（[docs/adr/0004](./docs/adr/0004-binary-distribution-and-release.md)）。

1. セキュリティ監査をする（[docs/adr/0035](./docs/adr/0035-security-hardening.md)）。プレリリース（`rc` などの識別子が付くタグ）を含め、`v` で始まるタグのリリースのたびに行う。前の監査からの変更を中心に、信頼できない入力（原稿、TOML、画像、フォント、CSL-JSON、プラグイン、シンボリックリンク）と CI のワークフローを調べる。結果は `docs/audits/<日付>-security-audit.md` に日本語で記録し、プルリクエストで `main` に入れる。記録はコミットしたあとは変更しない。見つかった問題は、失敗するテストを先に書いてから直す。仕様を変える修正には ADR を書く。監査の記録と修正が `main` に入るまで、タグを付けない。
2. バージョンを上げるプルリクエストを作る。リポジトリの根の `VERSION` を新しいバージョン（例：`0.1.0-rc1`）に書き換え、識別子を除いた `X.Y.Z` を全パッケージの cabal ファイルの `version` に書く。CI の `release-scripts` ジョブが、二つの一致を検査する。
3. プルリクエストを `main` にマージする。
4. マージしたコミットに、`v` に `VERSION` の内容を続けたタグ（例：`v0.1.0-rc1`）を付けて push する。タグと `VERSION` が一致しないとき、タグのコミットが `main` に含まれないときは、ワークフローの `version` ジョブが失敗し、リリースは作られない。
5. `.github/workflows/release.yml` が、配布物を作って検査し、下書きのリリースを作る。プレリリースのタグでは、プレリリースの印が付く。
6. 下書きのリリースノートを読む。AI が書いたノートの分類やまとめ方がおかしければ、手で直す。AI の実行か検査に失敗したときは、`## Unsorted` に変更の一覧が残ったノートになるので、分類して書き直す。ワークフローの要約に、失敗の理由が書かれる。
7. GitHub の Releases の画面で、下書きを公開する。公開の操作はワークフローでは行わない。

配布物を作って検査するところまでを試すときは、`gh workflow run release.yml --ref <ブランチ>` で `workflow_dispatch` から起動する。
このときはリリースを作らない。

タグは次のとおり扱う（[docs/adr/0008](./docs/adr/0008-first-release-verification.md)）。

- push したタグを別のコミットに付け直さない。
- 公開していないリリースのタグは、ワークフローが失敗したとき、または配布物の確かめが通らなかったときに限り削除してよい。削除したタグの名前は再び使わず、プレリリースの識別子を進める（`rc1` の次は `rc2`）。
- 公開したリリースのタグは削除しない。
- コードを変えずに直る失敗（ランナーの不調、ネットワークの一時的な失敗、API の制限）は、タグを変えずにワークフローをやり直す（`gh run rerun <実行の ID> --failed`）。

配布物を確かめた結果は、`docs/audits/releases/<タグ>.md` に日本語で記録し、プルリクエストで `main` に入れる。
タグを削除してやり直した場合も、削除したタグの記録に失敗を書いて残し、次のタグの記録を別に作る。
記録はコミットしたあとは変更しない。

## テスト用の素材

フィクスチャに外部の文章やフォントを加えるときは、ライセンスを確かめて、ライセンスの文書を一緒に置く。
出典は、そのフィクスチャの README に書く。
取得するスクリプトでは、取得したファイルの SHA-256 を固定して検証する。
取得した原文を Golem の原稿に変換する処理は、Python で書かない。
`modules/golem-fixtures` の実行ファイル `golem-fixtures` に Haskell で書き、`scripts/fixtures/fetch-public-domain.sh` から `cabal run` で動かす（[docs/adr/0023](docs/adr/0023-fixture-converters-without-python.md)）。
このパッケージはリリースの配布物に入れない。

## GitHub Actions

Node は最新の LTS を使う。
アクションは、Node 24 以降で動く最新のメジャーバージョンを使う。

CI の実行時間は 5 分以内を保つ。
CI を待つ時間は、変更を一つ入れるたびにかかるので、CI が遅いと開発そのものが遅くなる。
このプロジェクトは開発の速さをいちばん大事にしているので、CI の遅さを後回しにしない。
プルリクエストの CI が 5 分を超えたら、ほかの作業を止めて、まず CI を改善する（ジョブの分割、キャッシュ、変更のないモジュールの検査を省くことなど）。
最適化の前後の時間は `docs/ci-timings/` に記録する。

CI の `build` ジョブは、EPUB を検査する epubcheck を apt から入れない。
配布元（GitHub の w3c/epubcheck）の release の zip を取り、`ci.yml` に書いた SHA-256 で検査してから、ランナーにもとからある Java 17（`JAVA_HOME_17_X64`）で動かす。
zip は版と SHA-256 をキーにキャッシュするので、取りに行くのは版を上げたときとキャッシュが消えたときだけである。
今の版は 5.4.0 である。
版を上げるときは、`ci.yml` の `EPUBCHECK_VERSION` と `EPUBCHECK_SHA256` を変えるプルリクエストを出す（[docs/adr/0062](./docs/adr/0062-epubcheck-from-release-with-cache.md)）。

## ライセンス

二つのマニュアル（`manual/` と `manual-dev/`。`fonts/` を除く）への貢献は、[CC0 1.0](./manual/LICENSE) のもとで配布される（[docs/adr/0082](./docs/adr/0082-manuals-under-cc0.md)）。
そのほかに貢献したコードとドキュメントは、[MIT ライセンス](./LICENSE) のもとで配布される。
