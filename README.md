# golem

## Overview

Golem は、コマンドラインと CI で動く組版システムである。
原稿は `.gm` のテキストで書き、同じ入力から常に同じバイト列の PDF、EPUB、HTML、テキストを出力する。
仕様は [docs/specifications.md](./docs/specifications.md) と [docs/markup.md](./docs/markup.md) にある。
用語は [docs/glossary.md](./docs/glossary.md) にまとめている。

マニュアルは二つあり、どちらも Golem 自身で組んで、リリースの資産に添えている（[docs/adr/0022](./docs/adr/0022-manual-as-typesetting-sample.md)、[docs/adr/0024](./docs/adr/0024-manual-audiences-and-policy.md)）。

- 使い手のマニュアル：PDF（`golem-manual-<タグ>.pdf`）と HTML（`golem-manual-<タグ>-html.tar.gz`）。原稿は [`manual/`](./manual/)。
- 開発者のマニュアル：PDF（`golem-dev-manual-<タグ>.pdf`）と HTML（`golem-dev-manual-<タグ>-html.tar.gz`）。原稿は [`manual-dev/`](./manual-dev/)。

リリースの前のものは、CI の `build` ジョブの成果物（`manual` と `manual-dev`）で読める。
マニュアルの読み手と書き方の方針は [docs/manual-policy.md](./docs/manual-policy.md) にある。

## Installation

[GitHub Releases](https://github.com/tett23/golem/releases) から、プラットフォームに合うアーカイブを取得する。

| アーカイブ | 対象 |
|---|---|
| `golem-<タグ>-x86_64-linux.tar.gz` | Linux の x86-64（musl で完全に静的にリンクしており、ディストリビューションを問わない） |
| `golem-<タグ>-aarch64-linux.tar.gz` | Linux の aarch64（同上） |
| `golem-<タグ>-aarch64-macos.tar.gz` | macOS 14 以降の Apple Silicon |

Windows では、WSL2 の上で Linux のアーカイブを使う。
x86-64 の macOS 向けの配布物はないので、[CLI のビルド](#cli-のビルド)の手順でソースからビルドする。

アーカイブと `SHA256SUMS` を取得し、検証してから展開する。
次の例は x86-64 の Linux の場合である。

```bash
TAG=v0.1.0
curl -LO "https://github.com/tett23/golem/releases/download/$TAG/golem-$TAG-x86_64-linux.tar.gz"
curl -LO "https://github.com/tett23/golem/releases/download/$TAG/SHA256SUMS"
sha256sum --ignore-missing -c SHA256SUMS
tar -xzf "golem-$TAG-x86_64-linux.tar.gz"
```

macOS では、`sha256sum` の代わりに `shasum -a 256 --ignore-missing -c SHA256SUMS` を使う。
展開したディレクトリの `golem` を、`PATH` にあるディレクトリに置く。

```bash
install -m 755 "golem-$TAG-x86_64-linux/golem" "$HOME/.local/bin/golem"
golem --version
```

ビルドの来歴は、GitHub CLI の `gh attestation verify golem-$TAG-x86_64-linux.tar.gz --repo tett23/golem` で検証できる。

macOS の実行ファイルは公証を受けていない。
ブラウザで取得したアーカイブから展開した `golem` には `com.apple.quarantine` の属性が付き、Gatekeeper が初回の起動を拒む。
その場合は、属性を外してから起動する。

```bash
xattr -d com.apple.quarantine golem
```

`curl` で取得した場合は、この属性は付かない。

`golem new` はフォントを HTTPS で取得し、ルート証明書を OS の証明書のストアから読む。
ca-certificates の入っていない最小構成のコンテナでは、ca-certificates を入れるか、環境変数 `SSL_CERT_FILE` で証明書のファイルを指定する。

アーカイブの中の `THIRD_PARTY_LICENSES/` に、実行ファイルに静的にリンクしたライブラリと同梱したデータのライセンスがある。
`BUILDINFO` には、ビルドしたコミットと環境を記録している。

## Usage

```bash
golem new mybook
```

| コマンド | 内容 |
|---|---|
| `golem new DIR [--language ja\|en] [--no-fonts]` | プロジェクトを作る。版面の設定と、配布元から取得したフォントと、プリフライトの設定 `preflight.toml` を含む。`--no-fonts` で作ったプロジェクトも、フォントを置く前から HTML、EPUB、プレーンテキストを作れる（PDF はフォントを置くまで作れない） |
| `golem plugin lock` | マニフェストのプラグインを取得し、ハッシュを `plugins.lock` に書く |
| `golem plugin fetch` | `plugins.lock` のとおりにプラグインを取得してキャッシュに置く |
| `golem build [--target html\|epub\|text\|pdf] [--profile dev\|prod] [--marks japanese\|western\|none] [--no-notices]` | 出力を `build/` に書く。`--target` を省くと四つのターゲットをすべて作る。`--marks` は PDF に付けるトンボ（既定は none）。`--no-notices` はその実行に限りお知らせを出さない |
| `golem check [--profile dev\|prod] [--marks japanese\|western\|none] [--no-notices]` | 出力を書かずに検査する |
| `golem preflight [--rules FILE] [--marks japanese\|western\|none] [--format human\|json]` | PDF を prod で組み、書かずに入稿の前の検査（プリフライト）を行う。設定は `--rules` のファイル、なければ `preflight.toml`、それもなければ組み込みの `print`。最後に検査した PDF の SHA-256 を出す |
| `golem lint [--profile dev\|prod] [--no-notices]` | lint の規則を適用する |
| `golem fmt [--check] [FILE...]` | 原稿を整形する |
| `golem lsp` | 標準入出力で LSP を話す。位置の単位は、クライアントが対応していれば UTF-8、そうでなければ UTF-16 を使う |
| `golem inspect FILE --as cst\|ast\|ir` | 構文木と IR を表示する |
| `golem explain [CODE]` | 診断のコードの説明を表示する。コードを省くと一覧を表示する |
| `golem --version` | 版を表示する（例：`golem 0.1.0`） |

原稿の段落は、既定では空行で区切る。
一行を一つの段落として書く和文の原稿は、`manifest.toml` の `[source]` に `paragraph-separator = "line"` と書くと、改行ひとつで段落を区切って読む。
章の配列の項目（`{ file = "...", paragraph-separator = "blank-line" }`）で、章ごとに変えられる。
段落を分けずに行を改めるには、行の末尾に `\` を書く（強制改行、[docs/adr/0016](docs/adr/0016-hard-line-breaks.md)）。

PDF を出力するには、`style.toml` の `[fonts.body]` に和文と欧文のフォントのファイルを書く。
見出しは `[headings.<階層>]` の `font` の役割の書体と `size` の大きさで組み、行の格子にそろえて置く。
`font` が `[fonts]` にない役割を指す場合はエラーになる。
文字の見た目は `[character-styles.<名前>]` の文字スタイル、段落の見た目は `[paragraph-styles.<名前>]` の段落スタイルにまとめる。
`[strong: ...]`、`[bold: ...]`、`[italic: ...]`、`[code: ...]` は組み込みの文字スタイル `strong`、`bold`、`italic`、`code` の別名であり、`[character-styles.bold]` などの `font` の役割の書体で組む。
指定がなければ合成の太字と斜体で組み、役割が和文か欧文の片方しか持たない場合は、持たない側の文字を合成で組む。
和文も合成の斜体で傾く。
段落スタイルは原稿の `@style 名前` で付け、韻文は組み込みの段落スタイル `verse` で書く（`@style verse`）。
段落の字下げは段落スタイルの `indent` と `first-line-indent`（負ならぶら下げ）で指定し、既定は 0 である。
文字スタイルと段落スタイルの `kerning`（`metrics`、`japanese-equal-width`、`none`）、`tracking`、`proportional-metrics`、`baseline-shift` で、カーニングの方式、トラッキング、プロポーショナルメトリクス、ベースラインシフトを指定する。
既定はフォントのペアカーニングを和文にも欧文にもかける `metrics` である（[docs/adr/0020](docs/adr/0020-indesign-character-features.md)）。
PDF のリストは項目の印をぶら下げ、入れ子のリストを外の項目の本文の始まりから下げる。
箇条書きの印と番号付きリストの番号の書式は、`[lists]` の `bullets` と `numbers` で入れ子の深さごとに変えられる。
和欧間や括弧類の前後などの字間の空き（アキ）の量は、`[aki-sets.<名前>]` で文字のクラスの組ごとに定義したアキ量のセットを、段落スタイルの `aki-set` で選んで変えられる（既定は行末約物半角の `gyomatsu-yakumono-hankaku`）。
原稿の任意の位置には、`3[aki 四分]kg` のように固定の空きを置ける。
一つの章でだけ使う文字スタイルと段落スタイルは、その章のファイルの先頭に `@style-def paragraph letter indent=2zw` のように書けば、そのファイルにだけ効く（`style.toml` と同じ名前なら、そのファイルの中でだけ上書きになる）。
段落スタイルの `regex-styles = [{ pattern = '[0-9]+', style = "bold" }]` のような正規表現スタイルは、段落の中で正規表現に一致した文字に文字スタイルを当てる（InDesign の正規表現スタイル、[docs/adr/0015](./docs/adr/0015-regex-styles.md)）。
図版のキャプションは組み込みの段落スタイル `caption` の `font` と `size` で組み、本文より小さいキャプションも行の格子を崩さずに置く。
傍注は組み込みの段落スタイル `sidenote` の `font` と `size` で組み、`[sidenotes]` には傍注欄の幅、版面との間隔、本文側の印だけを書く。
コードブロックは組み込みの段落スタイル `code` で組み、書体は `[fonts.code]` の役割、背景の色と内側の余白は `[paragraph-styles.code]` の `background` と `padding` で指定する（[golem-driver ADR 0017](./docs/golem-driver/adr/0017-pdf-code-blocks.md)）。
PDF では空白とタブ（幅は空白 2 字分）を残し、長い行は折り返す。
技術書のためには、```` ```haskell numbers=10 file="src/Main.hs" highlight=12 diff=true callouts=true ```` のように開始の行（と `@listing`）に書くキーワード引数で、行番号、ファイル名、強調、差分、注釈の印（①）を付けられ、`@caption` で付けたキャプションにはリスト番号が振られる。色分け、強調と差分の背景、折り返した印、改ページの続きの表示は `style.toml` の `[code]` と `[code.colors]` で、枠は `[paragraph-styles.code]` の `border` で指定する（[golem-driver ADR 0023](./docs/golem-driver/adr/0023-code-block-book-features.md)）。
PDF の索引は、`[index]` の `columns` と `column-gap` で、一段組みの本でも二段のように版面と異なる段数で組める（[docs/adr/0025](docs/adr/0025-index-columns.md)）。
PDF のページ下の脚注の前には、`[notes.rule]` に `length`、`weight`、`space-before`、`space-after` を書けば区切り線を引ける（[golem-driver ADR 0024](./docs/golem-driver/adr/0024-rule-spec-and-footnote-separator.md)）。
文字の色はスウォッチの CMYK のプロセスカラーで書く。
PDF/X-4 の適合は Golem 自身の検査で確かめているが、入稿する前には `golem preflight --marks japanese` を通し、その後に商用のプリフライト（Acrobat や pdfToolbox など）で確認する（[docs/golem-cli/adr/0006](docs/golem-cli/adr/0006-preflight.md)）。
入稿する PDF は `golem build --target pdf --profile prod` で作る。`golem preflight` の要約の SHA-256 は、この PDF と一致する。

日本の印刷所に入稿する PDF は、`style.toml` の `[page]` に `bleed = "3mm"` を書き、`golem build --target pdf --marks japanese` で作る。
塗り足しのない日本式のトンボはエラー（G0702）になる。
欧文の一重のトンボは `--marks western` で付ける。
閲覧用の PDF は `--marks` を付けずに作る。
トンボを付けた PDF には、ノンブルのないページのノドの側に隠しノンブルが入る。
中綴じの本では `style.toml` の `[hidden-folio]` に `enabled = false` を書く（[golem-driver ADR 0021](docs/golem-driver/adr/0021-hidden-folios.md)）。
トンボの有無は PDF のインスタンス ID に入るので、閲覧用と入稿用の PDF は区別できる。
フォントの OS/2 の `fsType` が埋め込みかサブセット化を禁じている場合はエラーになる（[golem-driver ADR 0016](docs/golem-driver/adr/0016-output-and-layout-diagnostic-codes.md)）。
原稿の異体字セレクタ（IVS）は PDF では字形の選択に使い、ToUnicode には基底の文字だけを書く（[golem-pdf ADR 0006](docs/golem-pdf/adr/0006-cid-system-info.md)）。
ビルドはプラグインをキャッシュからだけ読み、ネットワークに接続しない。
診断は `--format json` で JSON にできる。
診断のコード（`G0101` など）の意味と直し方は [docs/diagnostics.md](docs/diagnostics.md) にまとめてある。
終了コードは、成功が 0、エラーの診断があれば 1、使い方の誤りが 2 である。

## Development

変更の進め方と約束ごとは [CONTRIBUTING.md](./CONTRIBUTING.md) にある。

### Git フックの有効化

クローン直後に、リポジトリ同梱の Git フックを有効にする。

```bash
git config core.hooksPath .githooks
```

フックは [adr-guard](https://github.com/tett23/adr-guard) の v0.8.1 以降を呼び出すので、あらかじめインストールしておく（[docs/adr/0012](./docs/adr/0012-update-adr-guard-to-v0.8.1.md)）。
ソースからは `cargo install --git https://github.com/tett23/adr-guard --tag v0.8.1` で入る。
`.githooks/pre-commit` は、コミット済みの ADR（`docs/adr/` と `docs/<モジュール>/adr/` の配下）への変更、削除、リネームを含むコミットを拒否する。
例外は `ステータス:` で始まる行で、この行だけは変更できる（`--allow-status`）。
ADR の参照にリンクを付ける、外す、リンク先を変えるだけの変更も許す（`--allow-links`）。
ADR は、行頭が `ステータス:` のステータスの行をちょうど一つ持たねばならない。無い ADR と二つ以上ある ADR はフックが拒否し、`adr-guard check-status` で一覧にできる。
監査の記録（`docs/audit/`、`docs/audits/`）と性能計測の記録（`docs/benchmarks/`、`docs/benchmark/`）も、コミット済みのものは変更、削除、移動を拒否する。記録には `--allow-status` と `--allow-links` の例外も効かない。
文書の中の ADR の参照（`ADR 0001` の形）には、ADR のファイルへのリンクを付ける。リンクのない参照は `adr-guard links` で一覧にでき、`adr-guard links --fix` で直せる。
ADR はコミット後に変更しない規約であり、変更が必要な場合は新しい連番の ADR を作成する（詳細は [CLAUDE.md](./CLAUDE.md)）。
`.githooks/pre-push` は、`docs/markup.md` か `docs/specifications.md` を変えたのに `manual/` と `manual-dev/` のどちらも変えていないブランチと、`CONTRIBUTING.md` か `CONTRIBUTING.en.md` を変えたのに `manual-dev/` を変えていないブランチの push を止める（`scripts/manual/check-updated.sh`、[docs/adr/0024](./docs/adr/0024-manual-audiences-and-policy.md)）。
マニュアルの変わらない変更では、コミットのメッセージの末尾に `Manual: unchanged` のトレーラーを書く。
`main` への push とブランチの削除は検査しない。
`core.hooksPath` はクローンごとのローカル設定であり、リポジトリには保存されないため、クローンのたびに実行が必要になる。
同じ検査は CI の `adr` ジョブでも、adr-guard の v0.8.1 の action に `allow-status: true` と `allow-links: true` を付けて行う。

### 固定しているネイティブライブラリ

出力の決定性を保つため、次のライブラリは版を固定して使う。
版を上げるときは ADR を作成する。

| ライブラリ | 版 |
|---|---|
| HarfBuzz | 14.6.0 |
| FreeType | 2.14.3 |
| wasmtime | 49.0.2 |
| zlib | 1.3.2 |
| hyph-utf8（英語（米国）のハイフネーションのパターン） | コミット 5684c0f |

HarfBuzz と FreeType は、ソースを `modules/golem-font/cbits/` に同梱して静的にリンクする。
zlib は Hackage の `zlib-clib` 1.3.2 を同梱版として使う（`cabal.project` で固定）。
wasmtime はプラットフォームごとの C API の配布物を `scripts/fetch-wasmtime.sh` で取得する（SHA-256 を検証し、`third_party/wasmtime` に置く）。
`licenses/` には、配布物の `THIRD_PARTY_LICENSES/` に写すライセンスの文書のうち、ビルドの環境から取れないもの（`libwasmtime.a` に入った Rust のクレートなどの文書と、Alpine のパッケージが入れない文書）を置く（[docs/adr/0007](./docs/adr/0007-third-party-licenses.md)）。

### ビルドとテスト

GHC 9.10.3 と cabal-install 3.16.1.0 を ghcup で入れる。
`mise.toml` は ghcup の `bin` を `PATH` に加える。
C と C++ のコンパイラも必要である。

最初に wasmtime を取得する。
このスクリプトは、ライブラリの絶対パスを `cabal.project.local` に書き込む。

```bash
scripts/fetch-wasmtime.sh
```

```bash
cabal build all
```

```bash
cabal test all
```

依存の版は `cabal.project.freeze` で固定している。
このファイルを消してビルドすると、依存の版が変わりうる。

パーサーは `modules/golem-parser/grammar/Golem.hpeg` から生成し、生成物をコミットする。
文法を変えたら生成し直す。
同じスクリプトが、ラベルを外した文法（`modules/golem-parser/test/StrippedGrammar.hs`）も生成する。テストは、二つの文法が同じ入力を受理することを確かめる（[golem-parser ADR 0007](./docs/golem-parser/adr/0007-grammar-label-safety.md)）。

```bash
scripts/gen-parser.sh
```

テストの fixture の『テンペスト』と『蟹工船』、`modules/golem-driver/test/fixtures/pd/` の十冊は、`scripts/fixtures/fetch-public-domain.sh` が原文を取得して作る。
原文の変換は `modules/golem-fixtures` の実行ファイル `golem-fixtures` が行う。
このパッケージはリリースの配布物に入らない（[docs/adr/0023](./docs/adr/0023-fixture-converters-without-python.md)）。

```bash
GOLEM=$(cabal list-bin golem) scripts/fixtures/fetch-public-domain.sh
```

十冊はフォントをコミットしない。
そのディレクトリで `golem build` を実行する前に、`scripts/fixtures/copy-fonts.sh` で『蟹工船』と『テンペスト』のフォントを写す（[docs/adr/0026](./docs/adr/0026-ten-public-domain-fixtures.md)）。
golem-driver のテストは十冊をエラーなしに検査し、環境変数 `GOLEM_PD_BOOKS` があればすべてのターゲットに組む。

```bash
scripts/fixtures/copy-fonts.sh
GOLEM_PD_BOOKS=1 cabal test golem-driver --test-options='-p 0026'
```

テストのうち CDDL のスキーマへの適合の検査は、Rust の `cddl` クレートの CLI（0.10.7）を使う。
`PATH` にあるか `GOLEM_CDDL` で指定した場合だけ実行され、CI では必ず実行する。

```bash
cargo install cddl --version 0.10.7 --locked
```

ほかに、PDF の構造の検査は qpdf を、プラグインの配布のテストは openssl を使う。
これらの外部ツールがないと、それを使うテストは `SKIP` と表示されて飛ばされる。
`GOLEM_REQUIRE_EXTERNAL_TOOLS=1` を付けると、ツールがないことがテストの失敗になる。
CI はこれを付けて実行する。
この振る舞いを持つテストの補助は、テストスイートだけが使うパッケージ `modules/golem-test-support` にある（[docs/adr/0028](docs/adr/0028-shared-test-support-package.md)）。

### CLI のビルド

`golem` コマンドの実行ファイルは、`golem-cli` パッケージの `exe:golem` である。
wasmtime を取得したあとで、次のコマンドを実行すると、実行ファイルを `~/.local/bin` に置く。

```bash
cabal install exe:golem --installdir="$HOME/.local/bin" --install-method=copy --overwrite-policy=always
```

`--installdir` を変えれば、ほかのディレクトリにも置ける。
そのディレクトリを `PATH` に加えておけば、`golem` で呼び出せる。

インストールせずに使う場合は、`cabal build exe:golem` でビルドし、`cabal list-bin golem` で実行ファイルのパスを調べる。
`cabal run golem -- --help` のように、`cabal run` から呼び出してもよい。

HarfBuzz、FreeType、wasmtime、zlib は静的にリンクする。
macOS でビルドした実行ファイルは OS 標準のライブラリだけに依存するので、同じアーキテクチャの macOS であれば、実行ファイルだけをコピーして使える。

Golem の版の正本はリポジトリの根の `VERSION` である。
版を変えるときは、`VERSION` と全パッケージの cabal ファイルの `version` を一緒に書き換える（手順は [CONTRIBUTING.md](./CONTRIBUTING.md) の「タグとリリース」）。

### マニュアル

マニュアルの原稿は、使い手のマニュアルの `manual/` と、開発者のマニュアルの `manual-dev/` の二つの Golem のプロジェクトである（[docs/adr/0024](./docs/adr/0024-manual-audiences-and-policy.md)）。
書き方の方針は [docs/manual-policy.md](./docs/manual-policy.md) にある。
次のスクリプトで組める。

```bash
GOLEM="$(cabal list-bin golem)" sh scripts/manual/build.sh             # 二冊とも
GOLEM="$(cabal list-bin golem)" sh scripts/manual/build.sh manual-dev  # 一冊だけ
```

このスクリプトは、プロジェクトごとに、奥付の版とコミットのハッシュを `common/build-info.gm` に書き（`scripts/manual/build-info.sh`）、マニュアルの書体（Noto Serif JP、Noto Sans JP、Source Serif 4、Source Sans 3、Source Code Pro。どれも SIL Open Font License 1.1）を、版を固定した配布元から取得して SHA-256 を検査し、`fonts/` に置く（`scripts/manual/fetch-fonts.sh`。二回目からは検査だけを行う）。
そのあと `golem build --target pdf --target html` で組み、出力を `build/` に書く。
エラー、警告、お知らせのどれか一つでも出れば失敗し、マニフェストに `silence-notices` があれば組む前に失敗する。
`GOLEM` を省くと、`PATH` にある `golem` を使う。

`build-info.gm` は生成物で、Git では管理しない。
マニュアルを `golem check` や LSP で開く前に、一度 `sh scripts/manual/build-info.sh manual`（開発者のマニュアルは `manual-dev`）を実行する。
実行しないと、奥付の `@import` の先がないエラー（G0302）になる。
Git のリポジトリの外で組むときは、環境変数 `GOLEM_MANUAL_COMMIT` と `GOLEM_MANUAL_TAG` で値を渡す。
スクリプトのテストは `scripts/manual/test.sh` にある。

開発者のマニュアルの図は、`manual-dev/images/src/` の SVG が原稿である。
SVG を直したら、`sh scripts/manual/render-figures.sh` で `manual-dev/images/` の PNG を作り直し、両方をコミットする。
このスクリプトはヘッドレスの Chrome を使う（`CHROME` で実行ファイルを選べる）。
組むときには実行しないので、マニュアルを組むだけなら Chrome は要らない。

### 整形と検査

Haskell のコードは fourmolu 0.21.0.0 で整形し（設定は `fourmolu.yaml`）、hlint 3.10 で検査する。
どちらも CI の `format` ジョブで検査する。
CI の hlint は、GHC でビルドせず、hlint のリリースの x86-64 Linux 向けの配布物を `scripts/ci/fetch-hlint.sh` で取得して使う（[docs/adr/0009](./docs/adr/0009-ci-speed.md)）。

### CI

CI は二つのワークフローからなる。
`.github/workflows/docs.yml` は ADR とドキュメントを、`.github/workflows/ci.yml` はコードを検査する（[docs/adr/0021](./docs/adr/0021-docs-workflow-and-ci-gate.md)）。

| ワークフロー | ジョブ | 内容 |
|---|---|---|
| `docs.yml` | `adr` | コミット済みの ADR と記録（`docs/audit/`、`docs/audits/`、`docs/benchmarks/`、`docs/benchmark/`）が変更されていないこと、文書の中の ADR の参照にリンクがあること、各 ADR がステータスの行をちょうど一つ持つことを検査する |
| `docs.yml` | `manual` | プルリクエストで、`docs/markup.md` か `docs/specifications.md` を変えたのに `manual/` も `manual-dev/` も変えていないこと、`CONTRIBUTING.md` か `CONTRIBUTING.en.md` を変えたのに `manual-dev/` を変えていないことを検査する（`scripts/manual/check-updated.sh`）。`main` への push では省く |
| `ci.yml` | `changes` | `scripts/ci/` と `scripts/manual/` のスクリプトのテスト（`scripts/ci/test.sh`、`scripts/manual/test.sh`）を実行し、ビルドが読む `docs/` の下の文書が一覧にあることを確かめ、変更のパスからビルドが要るかを決める |
| `ci.yml` | `build` | x86-64 と aarch64 の Linux でビルドとテストを行い、生成したパーサーが文法と一致することを確かめる。`manual/` と `manual-dev/` をお知らせも含めて診断なしで組む。x86-64 では EPUB が epubcheck を通ることを確かめ、組んだ二つのマニュアルの PDF と HTML を成果物 `manual` と `manual-dev` として上げる |
| `ci.yml` | `determinism` | 決まった入力（`scripts/determinism.sh`。二つのマニュアルを含む）の出力のハッシュを、二つのアーキテクチャで比べる |
| `ci.yml` | `release-scripts` | `VERSION` と全パッケージの版の一致を検査し、`scripts/release/` のスクリプトのテスト（`scripts/release/test.sh`）を実行する |
| `ci.yml` | `format` | fourmolu と hlint で検査する |
| `ci.yml` | `ci` | `ci.yml` のほかのジョブがすべて成功したか、省かれたことを確かめる（`scripts/ci/gate.sh`） |

変更が `docs/` の下のファイルとリポジトリの根の Markdown のファイルだけの場合、`build`、`determinism`、`format`、`release-scripts` は省かれる（[docs/adr/0009](./docs/adr/0009-ci-speed.md)）。
判定は `scripts/ci/needs-build.sh` が行い、プルリクエストの変更のパスは分岐点からの差分で取る（`scripts/ci/changed-paths.sh`）。
ただし、ビルドやテストが読む文書（今は `docs/diagnostics.md`）を変えた場合はビルドする（[docs/adr/0021](./docs/adr/0021-docs-workflow-and-ci-gate.md)）。
`adr` は、変更のパスにかかわらず常に走る。
`main` の保護の規則が必須とする検査は、`ci` と `adr` の二つである。
同じプルリクエストに新しいコミットを push すると、走っている前の実行は取り消される。
CI の所要時間の記録は `docs/ci-timings/` に置き、`scripts/ci/timings.sh` で作る。

`.github/workflows/release.yml` は、`v` で始まるタグの push と `workflow_dispatch` で動く（[docs/adr/0004](./docs/adr/0004-binary-distribution-and-release.md)）。
`workflow_dispatch` では、配布物を作って検査するところまでを行い、リリースは作らない。

| ジョブ | 内容 |
|---|---|
| `ci` | `ci.yml` を再利用可能なワークフローとして呼ぶ |
| `version` | `scripts/release/check-version.sh` で `VERSION` とタグを検査し、タグのコミットが `main` に含まれることを確かめる |
| `build` | Linux の二つのアーキテクチャでは Alpine のコンテナの中で musl に静的にリンクして、macOS では `macos-15` でビルドし、アーカイブを作る。`THIRD_PARTY_LICENSES/` を決めたリンクマップも成果物として上げる |
| `smoke` | アーカイブを別のランナーと、`alpine` と `debian:stable-slim` のコンテナの中で展開して動かす |
| `determinism` | 三つの配布物と CI のビルドの、`scripts/determinism.sh` の出力を比べる |
| `release` | タグの push のときだけ、`SHA256SUMS`、来歴の証明、GMP のソース、x86-64 の Linux の配布物で組んだ二つのマニュアルの PDF と HTML（`golem-manual-<タグ>` と `golem-dev-manual-<タグ>`）、AI が書いたリリースノートと共に下書きのリリースを作る |

リリースノートを書く AI の API キーは、リポジトリの秘密情報 `ANTHROPIC_API_KEY` に置く。

## License

[MIT](./LICENSE) © tett23
