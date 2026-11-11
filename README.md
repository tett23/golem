# golem

## Overview

Golem は、コマンドラインと CI で動く組版システムである。
原稿は `.gm` のテキストで書き、同じ入力から常に同じバイト列の PDF、EPUB、HTML、テキストを出力する。

Golem の振る舞いと計画は、次の文書に分けて書いている。

- 仕様：[docs/specifications.md](./docs/specifications.md) と [docs/markup.md](./docs/markup.md)
- 用語：[docs/glossary.md](./docs/glossary.md)
- どのバージョンで何を扱うか：[docs/roadmap.md](./docs/roadmap.md)
- 互換の約束：[docs/compatibility.md](./docs/compatibility.md)

互換は 1.0.0 から守る。
Golem は 1.0.0 から、原稿の記法、設定、CLI、出力、プラグインの ABI、JSON の diagnostics、diagnostic のコードの互換を守る。
守る範囲と守らないもの、互換を壊してよい条件、廃止の手順は [docs/compatibility.md](./docs/compatibility.md) にある（[docs/adr/0174](./docs/adr/0174-compatibility-promises-for-1-0.md)）。
1.0.0 より前は、互換を壊すことがある。

マニュアルは二つあり、どちらも Golem 自身で組んで、リリースのアセットに添えている（[docs/adr/0022](./docs/adr/0022-manual-as-typesetting-sample.md)、[docs/adr/0024](./docs/adr/0024-manual-audiences-and-policy.md)）。

- 使い手のマニュアル：PDF（`golem-manual-<タグ>.pdf`）と HTML（`golem-manual-<タグ>-html.tar.gz`）。原稿は [`manual/`](./manual/)。
- 開発者のマニュアル：PDF（`golem-dev-manual-<タグ>.pdf`）と HTML（`golem-dev-manual-<タグ>-html.tar.gz`）。原稿は [`manual-dev/`](./manual-dev/)。

リリースの前のものは、CI の `build` ジョブの成果物（`manual` と `manual-dev`）で読める。
マニュアルの読み手と書き方の方針は [docs/manual-policy.md](./docs/manual-policy.md) にある。

関数とプラグインには、それぞれ見本がある。
本を作る人が自分の本のために書く関数（Emet の `.emet`）の見本は [`functions/`](./functions/) に、プログラムを書く技術者が作って配るプラグインの見本は [`plugins/`](./plugins/) にある。
関数の見本の使い方は [functions/README.md](./functions/README.md) にある。

## Installation

[GitHub Releases](https://github.com/tett23/golem/releases) から、プラットフォームに合うアーカイブを取得する。

| アーカイブ | 対象 |
|---|---|
| `golem-<タグ>-x86_64-linux.tar.gz` | Linux の x86-64（musl で完全に静的にリンクしており、ディストリビューションを問わない） |
| `golem-<タグ>-aarch64-linux.tar.gz` | Linux の aarch64（同上） |
| `golem-<タグ>-aarch64-macos.tar.gz` | macOS 14 以降の Apple Silicon |
| `golem-<タグ>-wasm32-wasi.tar.gz` | PDF の組版だけを行う WebAssembly の reactor モジュール `golem.wasm`（下の「wasm の版」） |

表にないプラットフォームでは、別の手段を使う。
Windows では、WSL2 の上で Linux のアーカイブを使う。
x86-64 の macOS 向けの配布物はないので、[CLI のビルド](#cli-のビルド) の手順でソースからビルドする。

アーカイブは、`SHA256SUMS` で検証してから展開する。
次の例は x86-64 の Linux の場合である。

```bash
TAG=v0.1.0
curl -LO "https://github.com/tett23/golem/releases/download/$TAG/golem-$TAG-x86_64-linux.tar.gz"
curl -LO "https://github.com/tett23/golem/releases/download/$TAG/SHA256SUMS"
sha256sum --ignore-missing -c SHA256SUMS
tar -xzf "golem-$TAG-x86_64-linux.tar.gz"
```

macOS では、`sha256sum` の代わりに `shasum -a 256 --ignore-missing -c SHA256SUMS` を使う。
ビルドの来歴も、GitHub CLI の `gh attestation verify golem-$TAG-x86_64-linux.tar.gz --repo tett23/golem` で検証できる。

展開したら、ディレクトリの `golem` を、`PATH` にあるディレクトリに置く。

```bash
install -m 755 "golem-$TAG-x86_64-linux/golem" "$HOME/.local/bin/golem"
golem --version
```

macOS の実行ファイルは公証を受けていない。
ブラウザで取得したアーカイブから展開した `golem` には `com.apple.quarantine` の属性が付き、Gatekeeper が初回の起動を拒む。
その場合は、属性を外してから起動する。

```bash
xattr -d com.apple.quarantine golem
```

`curl` で取得した場合は、この属性は付かない。

`golem new` はフォントを HTTPS で取得し、ルート証明書を OS の証明書のストアから読む。
ca-certificates の入っていない最小構成のコンテナでは、ca-certificates を入れるか、環境変数 `SSL_CERT_FILE` で証明書のファイルを指定する。

アーカイブには、実行ファイルのほかに次のものが入っている。

- `THIRD_PARTY_LICENSES/`：実行ファイルに静的にリンクしたライブラリと同梱したデータのライセンス。
- `BUILDINFO`：ビルドしたコミットと環境の記録。
- `share/golem/editors/`：エディタが `.gm` と `.emet` を色付けするための TextMate と tree-sitter の構文の定義。
  使い方は、同じディレクトリの `README.md`（[tools/editors/README.md](./tools/editors/README.md)）にある。

見本のプラグイン（`<名前>.wasm`）に入るクレートと Rust の標準ライブラリのライセンスは、リリースに添えた `golem-plugins-licenses-<タグ>.tar.gz` にある（[docs/adr/0133](./docs/adr/0133-third-party-licenses-of-sample-plugins.md)）。

### wasm の版

`golem-<タグ>-wasm32-wasi.tar.gz` の `golem.wasm` は、同じ版の `golem build --target pdf` と同じ手順で PDF を組む WebAssembly の reactor モジュールである（[docs/adr/0199](./docs/adr/0199-pdf-typesetting-as-wasm-reactor.md)）。
ファイルを読まず、プロジェクトのファイルをバイト列で受け取って、PDF と diagnostics の JSON を返す。
インポートは WASI（preview 1）の `wasi_snapshot_preview1` だけで、前もって開くディレクトリ（preopen）を要らない。

ネイティブの `golem` と比べると、できることが二つ少ない。
プラグインの機能はなく、`[plugins]` かプラグインのフィルタの `[[filters]]` を書いたプロジェクトは G06106 になる。
ビルドのオプション（プロファイル、トンボ、`--no-notices`、`--verbose`）は受け取らず、`golem build --target pdf` の既定で組む。

動かす実行環境は、wasm の標準化された例外処理に対応した版でなければならない。
`golem.wasm` は、wasm の例外処理の標準化された形（exnref の形）を使い、古い形（legacy exceptions）を使わないからである。
対応した最初の版は、Chrome 137、Firefox 131、Safari 18.4、Node 24.15、Deno 2.3.2、wasmtime 47 である。

Node の `node:wasi` で動くことは、CI で確かめている。
夜ごとの `.github/workflows/browser.yml` が、Deno 2.9.8 の `node:wasi` と、wasmtime 50.0.1 の C API のホスト（`scripts/wasm/run-wasmtime.c`）と、`browser_wasi_shim` を使う Chromium（Chrome for Testing 157.0.8103.50）と Safari（macOS のランナーのもの）でも、ネイティブの `golem` と同じ PDF と diagnostics を返すことを確かめている（[docs/adr/0234](./docs/adr/0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md)、[docs/adr/0238](./docs/adr/0238-build-golem-wasm-with-the-standard-exception-handling-and-run-it-under-wasmtime.md)）。
Chromium と Safari では、ページの Worker の中で `golem.wasm` を動かす（[docs/adr/0309](./docs/adr/0309-run-golem-wasm-in-a-worker-of-the-browser-page.md)）。

エクスポートは C の ABI の次の五つと `hs_init` で、ホストは `_initialize` を一度、`hs_init(0, 0)` を一度呼んでから使う。

| 名前 | 型（C） | 働き |
|---|---|---|
| `golem_alloc` | `uint8_t *golem_alloc(uint32_t len)` | 入力のバッファを確保する |
| `golem_free` | `void golem_free(uint8_t *p)` | `golem_alloc` と結果のバッファを解放する |
| `golem_build_pdf` | `uint8_t *golem_build_pdf(const uint8_t *in, uint32_t len)` | 入力の枠を読んで組み、結果の枠を返す |
| `golem_result_len` | `uint32_t golem_result_len(const uint8_t *r)` | 結果の枠（と `golem_version` の値）の長さ |
| `golem_version` | `uint8_t *golem_version(void)` | `VERSION` の値（UTF-8） |

`golem_build_pdf` に渡す入力の枠は、プロジェクトのファイルを並べたものである。
入力の枠は、ファイルごとに、パスの長さ（`uint32` のリトルエンディアン）、パス（UTF-8）、中身の長さ（同じ）、中身を続けたものである。
パスはプロジェクトのルートからの相対パスで、`.` と `..` と空の区間を含まない正規化した形（`manifest.toml`、`fonts/NotoSerifJP-Regular.otf` など）とし、同じパスを二度書かない。

返る結果の枠は、状態の 1 バイト、PDF の長さと PDF、diagnostics の JSON の長さと JSON である（長さはどれも `uint32` のリトルエンディアン）。

- 状態 0 は組んだことを表し、エラーで PDF がなければ PDF の長さが 0 になる。
- 状態 1 は入力の枠を読めないことを表し、二つの長さはどちらも 0 である。

JSON は `golem build --target pdf --format json` が標準エラーに書くものと同じバイト列である。
ホストの例は [scripts/wasm/run.mjs](./scripts/wasm/run.mjs) にあり、アーカイブの `README` にも同じことを書いている。

アーカイブの `THIRD_PARTY_LICENSES/` には、`golem.wasm` にリンクしたもの（wasm の GHC の RTS と boot のパッケージ、HarfBuzz、FreeType、hyph-utf8、zlib、wasi-sdk の wasi-libc と libc++、GMP など）のライセンスがある。
GMP のソースは、ネイティブのアーカイブと同じくリリースに添えている。

## Usage

最初に、`golem new` でプロジェクトを作る。

```bash
golem new mybook
```

コマンドは次のとおりである。

| コマンド | 内容 |
|---|---|
| `golem new DIR [--language ja\|en] [--no-fonts] [--screen]` | プロジェクトを作る（下に詳しく書く） |
| `golem plugin lock` | マニフェストのプラグインを取得し、ハッシュを `plugins.lock` に書く |
| `golem plugin fetch` | `plugins.lock` のとおりにプラグインを取得してキャッシュに置く |
| `golem build [--target html\|epub\|text\|pdf] [--profile dev\|prod] [--marks japanese\|western\|none] [--no-notices] [-v\|--verbose]` | 出力を `build/` に書く。`--target` を省くと四つのターゲットをすべて作る。`--marks` は PDF に付けるトンボ（既定は none）。`--no-notices` はその実行に限り notice を出さない。`--verbose`（`-v`）は info も出す |
| `golem check [--profile dev\|prod] [--marks japanese\|western\|none] [--no-notices] [-v\|--verbose]` | 出力を書かずに検査する |
| `golem preflight [--rules FILE] [--marks japanese\|western\|none] [--format human\|json]` | PDF を prod で組み、書かずに入稿の前の検査（プリフライト）を行う。設定は `--rules` のファイル、なければ `preflight.toml`、それもなければ組み込みの `print`。最後に検査した PDF の SHA-256 を出す |
| `golem lint [--profile dev\|prod] [--no-notices] [-v\|--verbose]` | lint の規則を適用する |
| `golem fmt [--check] [FILE...]` | 原稿を整形し、表のファイルの BOM と改行を直す |
| `golem lsp` | 標準入出力で LSP を話す。位置の単位は、クライアントが対応していれば UTF-8、そうでなければ UTF-16 を使う |
| `golem inspect FILE --as cst\|ast\|ir\|cbor` | 構文木と IR を表示する |
| `golem explain [CODE...]` | diagnostic のコードの説明を表示する（下に詳しく書く） |
| `golem --version` | バージョンを表示する（例：`golem 0.1.0`） |

`golem new` が作るプロジェクトは、版面の設定と、配布元から取得したフォントと、プリフライトの設定 `preflight.toml` を含む。
`--no-fonts` で作ったプロジェクトも、フォントを置く前から HTML、EPUB、プレーンテキストを作れる（PDF はフォントを置くまで作れない）。
`--screen` は塗り足しを省き、プリフライトに `based-on = "screen"` を設定する（[ADR 0327](./docs/adr/0327-screen-preflight-and-template.md)）。
`DIR` は空でなくてよく、`manifest.toml` と `style.toml` のないディレクトリ（Markdown の原稿のリポジトリなど）なら、ほかのファイルを残したまま作る。
雛形のファイルと同じパスに何かあれば何も書かず、既存の `.gitignore` は書き換えない（[docs/adr/0273](./docs/adr/0273-golem-new-in-a-directory-without-a-project.md)）。

`golem explain` は、コードを省くと一覧を表示する。
複数のコードを渡すと、渡した順に空行一つで区切って標準出力に書く。
Golem のコードは大文字に直して同じになるものを、プラグインのコードは綴りが同じものを、最初のものだけ扱う。
未知のコードと形の誤ったコードは、正しいコードの説明の後に一つずつ一行で標準エラー出力に書き、終了コードを 2 にする。

プラグインは、`golem plugin lock` と `golem plugin fetch` で前もってキャッシュに置く。
ビルドはプラグインをキャッシュからだけ読み、ネットワークに接続しない。

### 原稿の段落

原稿の段落は、既定では改行ひとつで区切り、一行を一つの段落として読む（[docs/adr/0193](docs/adr/0193-line-paragraph-separator-by-default.md)）。
空行で段落を区切って書いた原稿は、`manifest.toml` の `[source]` に `paragraph-separator = "blank-line"` と書く。
章の配列の項目（`{ file = "...", paragraph-separator = "blank-line" }`）で、章ごとに変えられる。
`[source]` に `paragraph-separator` を書かなければ、notice の G03120 が出る。
`golem new` の雛形は `paragraph-separator = "line"` を書く。

段落を分けずに行を改めるには、行の末尾に `\` を書く（強制改行、[docs/adr/0016](docs/adr/0016-hard-line-breaks.md)）。

### 書体とスタイル

PDF を出力するには、`style.toml` の `[fonts.body]` に和文と欧文のフォントのファイルを書く。
見出しは `[headings.<階層>]` の `font` の役割の書体と `size` の大きさで組み、行の格子にそろえて置く。
`font` が `[fonts]` にない役割を指す場合はエラーになる。

文字と段落の見た目は、スタイルにまとめる。
文字の見た目は `[character-styles.<名前>]` の文字スタイル、段落の見た目は `[paragraph-styles.<名前>]` の段落スタイルにまとめる。
段落スタイルは原稿の `@style 名前` で付け、韻文は組み込みの段落スタイル `verse` で書く（`@style verse`）。
一つの章でだけ使う文字スタイルと段落スタイルは、その章のファイルの先頭に `@style-def paragraph letter indent=2zw` のように書けば、そのファイルにだけ適用される（`style.toml` と同じ名前なら、そのファイルの中でだけ上書きになる）。

強調と書体の切り替えも、文字スタイルで組む。
`[strong: ...]`、`[bold: ...]`、`[italic: ...]`、`[code: ...]` は組み込みの文字スタイル `strong`、`bold`、`italic`、`code` の別名であり、`[character-styles.bold]` などの `font` の役割の書体で組む。
指定がなければ合成の太字と斜体で組み、役割が和文か欧文の片方しか持たない場合は、持たない側の文字を合成で組む。
和文も合成の斜体で傾く。

段落スタイルは、字下げ、行揃え、段落の前後の空きを決める。
段落の字下げは段落スタイルの `indent` と `first-line-indent`（負ならぶら下げ）で指定し、既定は 0 である。
行の終わりの側の字下げは `end-indent`、行揃えは `align`（`left`、`center`、`right`、均等配置の三つ、`fully-justified`、ノド側と小口側）、段落の前後に空ける行の数は `space-before` と `space-after` で指定する（[docs/adr/0189](./docs/adr/0189-paragraph-alignment-spacing-and-end-indent.md)）。

文字の詰めと送りも、スタイルで指定する。
文字スタイルと段落スタイルの `kerning`（`metrics`、`japanese-equal-width`、`none`）、`tracking`、`proportional-metrics`、`baseline-shift` で、カーニングの方式、トラッキング、プロポーショナルメトリクス、ベースラインシフトを指定する。
既定はフォントのペアカーニングを和文にも欧文にもかける `metrics` である（[docs/adr/0020](docs/adr/0020-indesign-character-features.md)）。
括弧類、句読点、中点類は、PDF で既定でフォントの全角の字形（`fwid`）で組み、全角の字形がなければ全角の字幅の箱の中に字形を置く。
文字スタイルと段落スタイルの `punctuation-width = "font"` で、フォントの字形のまま組む（[ADR 0302](docs/adr/0302-full-width-glyphs-for-punctuation-and-boxes-for-narrower-ones.md)）。

段落スタイルの `regex-styles = [{ pattern = '[0-9]+', style = "bold" }]` のような正規表現スタイルは、段落の中で正規表現に一致した文字に文字スタイルを当てる（InDesign の正規表現スタイル、[docs/adr/0015](./docs/adr/0015-regex-styles.md)）。

文字の色はスウォッチの CMYK のプロセスカラーで書く。

### 字間と言語

和欧間や括弧類の前後などの字間の空き（アキ）の量は、`[aki-sets.<名前>]` で文字のクラスの組ごとに定義したアキ量のセットを、段落スタイルの `aki-set` で選んで変えられる（既定は行末約物半角の `gyomatsu-yakumono-hankaku`）。
原稿の任意の位置には、`3[aki 四分]kg` のように固定の空きを置ける。

原稿の一部の言語は `[lang en: “Tokyo”]` と、ブロックの言語は `@lang en` と書く。
PDF では引用符、ダッシュ、三点リーダーをその言語で欧文か和文として組み、英語のほかの言語では分綴しない。
HTML と EPUB には `lang` と `xml:lang` を、PDF には `/Lang` を書く（[docs/adr/0187](./docs/adr/0187-inline-language-switch.md)）。

PDF の欧文の語の分け方は、三つの方法で変えられる（[ADR 0272](./docs/adr/0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md)）。

- 語を分けてよい位置は、`in[shy]com[shy]pre` のようにソフトハイフン（`[shy]` か U+00AD）で指定できる。
- 行を分けない範囲は、組み込みの文字スタイル `no-break` で `[style no-break: 100 円]` と書く。
- 語の分け方の例外は、`style.toml` の `[composition.hyphenation-exceptions]` と原稿のファイルの `@hyphenation-exceptions` に言語ごとに書く。

### リスト、図版、コード、表

PDF のリストは項目の印をぶら下げ、入れ子のリストを外の項目の本文の始まりから下げる。
箇条書きの印と番号付きリストの番号の書式は、`[lists]` の `bullets` と `numbers` で入れ子の深さごとに変えられる。

図版のキャプションは組み込みの段落スタイル `caption` の `font` と `size` で組み、本文より小さいキャプションも行の格子を崩さずに置く。

コードブロックは組み込みの段落スタイル `code` で組み、書体は `[fonts.code]` の役割、背景の色と内側の余白は `[paragraph-styles.code]` の `background` と `padding` で指定する（[golem-driver ADR 0017](./docs/golem-driver/adr/0017-pdf-code-blocks.md)）。
PDF では空白とタブ（幅は空白 2 字分）を残し、長い行は折り返す。

技術書のためには、コードブロックに行番号などを付けられる。
```` ```haskell numbers=10 file="src/Main.hs" highlight=12 diff=true callouts=true ```` のように開始の行（と `@listing`）に書くキーワード引数で、行番号、ファイル名、強調、差分、注釈の印（①）を付けられ、`@caption` で付けたキャプションにはリスト番号が振られる。
色分け、強調と差分の背景、折り返した印、改ページの続きの表示は `style.toml` の `[code]` と `[code.colors]` で、枠は `[paragraph-styles.code]` の `border` で指定する（[golem-driver ADR 0023](./docs/golem-driver/adr/0023-code-block-book-features.md)）。

表には `@caption` でキャプションを付けて表番号（既定 `表{chapter}-{n}`）を振り、`@column-widths 8zw auto` で列の幅を、`@style` でセルの段落スタイル（既定は組み込みの `table`）を指定できる。
キャプションを表の上と下のどちらに置くかは `[tables]` の `caption-position` で決める（[docs/adr/0262](./docs/adr/0262-table-numbers-captions-column-widths-and-cell-styles.md)）。

### 注、索引、リンク

傍注は組み込みの段落スタイル `sidenote` の `font` と `size` で組み、`[sidenotes]` には傍注の領域の幅、版面との間隔、本文側の印だけを書く。
PDF のページ下の脚注の前には、`[notes.rule]` に `length`、`weight`、`space-before`、`space-after` を書けば区切り線を引ける（[golem-driver ADR 0024](./docs/golem-driver/adr/0024-rule-spec-and-footnote-separator.md)）。

PDF の索引は、`[index]` の `columns` と `column-gap` で、一段組みの本でも二段のように版面と異なる段数で組める（[docs/adr/0025](docs/adr/0025-index-columns.md)）。
索引の項目には、`[index reading=くみはん range=begin: 組版]` と `range=end` でページの範囲を、`see=組版` で「（組版を見よ）」「（組版をも見よ）」の参照を書ける。
続くページは「5–6」のように範囲にまとめ、項目は「あ」「か」のような行の見出しの下に並べる（見出しは `[index]` の `section-headings = false` で外せる。[docs/adr/0265](./docs/adr/0265-index-cross-references-page-ranges-and-section-headings.md)）。

外部の URL へのリンクは `[link "https://www.w3.org/TR/jlreq/": 日本語組版処理の要件]` と書き、PDF ではリンクの注釈に、HTML と EPUB では `a` 要素になる。
リンクは見た目を変えない（[docs/adr/0182](./docs/adr/0182-external-links.md)）。

文書の中の参照も、行先へのリンクになる。
PDF は、目次の項目の並びから閉じたしおりを作り、相互参照、注の印と注の側の印、目次の項目、索引のページ番号、参考文献を指す引用の番号を、文書の中の行先へのリンクにする。
HTML と EPUB では、`[ref-number]` と `[ref-title]` もラベルの行先へのリンクになる（[ADR 0267](./docs/adr/0267-pdf-bookmarks-and-links-inside-the-document.md)）。

### PDF の出力と入稿

どの PDF もタグ付き PDF で、`manifest.toml` の `[targets.pdf]` に `pdfa = "2a"` と `pdfua = "1"` を書けば PDF/A-2a と PDF/UA-1 に準拠させる。
CI がその PDF を veraPDF で検証する（[docs/adr/0183](docs/adr/0183-tagged-pdf-and-pdf-a.md)）。

入稿する PDF は `golem build --target pdf --profile prod` で作る。
`golem preflight` の要約の SHA-256 は、この PDF と一致する。
PDF/X-4 の適合は Golem 自身の検査で確かめているが、入稿する前には `golem preflight --marks japanese` を通し、その後に商用のプリフライト（Acrobat や pdfToolbox など）で確認する（[docs/golem-cli/adr/0006](docs/golem-cli/adr/0006-preflight.md)）。

トンボは、PDF の用途に合わせて選ぶ。

- 日本の印刷所に入稿する PDF は、`style.toml` の `[page]` に `bleed = "3mm"` を書き、`golem build --target pdf --marks japanese` で作る。
  塗り足しのない日本式のトンボはエラー（G07002）になる。
- 欧文の一重のトンボは `--marks western` で付ける。
- 閲覧用の PDF は `--marks` を付けずに作る。

トンボを付けた PDF には、ノンブルのないページのノドの側に隠しノンブルが入る。
中綴じの本では `style.toml` の `[hidden-folio]` に `enabled = false` を書く（[golem-driver ADR 0021](docs/golem-driver/adr/0021-hidden-folios.md)）。
トンボの有無は PDF のインスタンス ID に入るので、閲覧用と入稿用の PDF は区別できる。

フォントの埋め込みと異体字には、次の決まりがある。
フォントの OS/2 の `fsType` が埋め込みかサブセット化を禁じている場合はエラーになる（[golem-driver ADR 0016](docs/golem-driver/adr/0016-output-and-layout-diagnostic-codes.md)）。
原稿の異体字セレクタ（IVS）は PDF では字形の選択に使い、ToUnicode には基底の文字だけを書く（[golem-pdf ADR 0006](docs/golem-pdf/adr/0006-cid-system-info.md)）。

PDF と同じ `build/pdf/` には、各ページの最初の行が原稿のどのファイルの何行何列から始まるかを LSP の位置で表す `pages.json` も書く。
エディタが改ページの位置の印を出すためのものである（[docs/adr/0195](./docs/adr/0195-page-start-positions-of-pdf.md)）。

### diagnostics と終了コード

diagnostics は `--format json` で JSON にできる。
diagnostic のコード（`G01001` など）の意味と直し方は [docs/diagnostics.md](docs/diagnostics.md) にまとめてある。
コードは `G` と、段階の 2 桁と番号の 3 桁からなる 5 桁の数字である（[docs/adr/0061](./docs/adr/0061-five-digit-diagnostic-codes.md)）。
関数を書く言語 Emet のコードは `E` で始まる（[docs/adr/0160](./docs/adr/0160-emet-function-language-core.md)）。

終了コードは、成功が 0、エラーの diagnostic があれば 1、使い方の誤りが 2 である。

## Development

変更の進め方と約束ごとは [CONTRIBUTING.md](./CONTRIBUTING.md) にある。
最大常駐を条件にする変更は、[ヒープの測定手順](./docs/heap-measurement.md) に従って確かめる。

### Git フックの有効化

クローン直後に、リポジトリ同梱の Git フックを有効にする。

```bash
git config core.hooksPath .githooks
```

`core.hooksPath` はクローンごとのローカル設定であり、リポジトリには保存されないため、クローンのたびに実行が必要になる。
フックは [adr-guard](https://github.com/tett23/adr-guard) の v0.10.0 以降を呼び出すので、あらかじめインストールしておく（[docs/adr/0194](./docs/adr/0194-update-adr-guard-to-v0.10.0.md)）。
ソースからは `cargo install --git https://github.com/tett23/adr-guard --tag v0.10.0` で入る。

ADR はコミット後に変更しない規約であり、変更が必要な場合は新しい連番の ADR を作成する（詳細は [CLAUDE.md](./CLAUDE.md)）。
`.githooks/pre-commit` は、次のものを含むコミットを拒否する。

- コミット済みの ADR（`docs/adr/` と `docs/<モジュール>/adr/` の配下）への変更、削除、リネーム。
  例外は `ステータス:` で始まる行で、この行だけは変更できる（`--allow-status`）。
  リンクを付ける、外す、リンク先を変えるだけの変更も許す（`--allow-links`）。
  ADR の参照に限らず、画像のリンク先とリンクの参照定義の行（`[1]: URL`）も含む。
  リンクのテキスト、画像の追加と削除、自動リンク（`<URL>`）と本文の URL の変更は拒否する。
- ステータスの行の数が一つでない ADR。
  ADR は、行頭が `ステータス:` のステータスの行をちょうど一つ持たねばならない。
  無い ADR と二つ以上ある ADR はフックが拒否し、`adr-guard check-status` で一覧にできる。
- 監査の記録（`docs/audit/`、`docs/audits/`）と性能計測の記録（`docs/benchmarks/`、`docs/benchmark/`）のうち、コミット済みのものの変更、削除、移動。
  記録には `--allow-status` と `--allow-links` の例外も適用されない。

ADR の参照の書き方にも、決まりがある。
文書の中の ADR の参照（`ADR 0001` の形）には、ADR のファイルへのリンクを付ける。
リンクのない参照は `adr-guard links` で一覧にでき、`adr-guard links --fix` で直せる。
モジュールの ADR は `golem-driver ADR 0015` のようにモジュールの名前（`docs/adr ADR 0003` のようにディレクトリでもよい）で修飾して参照し、修飾子もリンクのテキストに含める。
修飾子がリンクの外にある参照、リンク先が修飾子の ADR と異なるリンク、対象の無い修飾子付きの参照も `adr-guard links` が報告する。
同じディレクトリの ADR の番号の重複は `adr-guard check-numbers` で一覧にでき、`adr-guard renumber` で直せる。

`.githooks/pre-push` は、仕様を変えたのにマニュアルを変えていないブランチの push を止める（`scripts/manual/check-updated.sh`、[docs/adr/0024](./docs/adr/0024-manual-audiences-and-policy.md)）。
止めるのは、`docs/markup.md` か `docs/specifications.md` を変えたのに `manual/` と `manual-dev/` のどちらも変えていないブランチと、`CONTRIBUTING.md` か `CONTRIBUTING.en.md` を変えたのに `manual-dev/` を変えていないブランチである。
マニュアルの変わらない変更では、コミットのメッセージの末尾に `Manual: unchanged` のトレーラーを書く。
`main` への push とブランチの削除は検査しない。

フックと同じ検査は、CI の `adr` ジョブでも、adr-guard の v0.10.0 の action に `allow-status: true` と `allow-links: true` を付けて行う。
この action は、ADR の参照のリンクと番号の重複も検査する。

### 固定しているネイティブライブラリ

出力の決定性を保つため、次のライブラリはバージョンを固定して使う。
バージョンを上げるときは ADR を作成する。

| ライブラリ | バージョン |
|---|---|
| HarfBuzz | 15.1.0 |
| FreeType | 2.15.0 |
| wasmtime | 50.0.1 |
| zlib | 1.3.2 |
| hyph-utf8（欧文の八つの言語のハイフネーションのパターン） | コミット 5684c0f |
| wasm のツールチェーン（ghc-wasm-meta の 9.10 の flavour） | ghc-wasm-meta のコミット 8079eb96、GHC 9.10.3.20260731、wasi-sdk（clang 21.1.8）、cabal 3.14.2.0 |
| cborg（wasm の版だけ） | 上流のコミット 6ef2791c |
| skylighting、skylighting-core（wasm の版だけ） | Hackage の 0.15.0.1 に `scripts/wasm/patches/` の差分を当てたもの |

固定の仕方は、ライブラリごとに違う。

- HarfBuzz と FreeType は、ソースを `modules/golem-font/cbits/` に同梱して静的にリンクする。
- zlib は Hackage の `zlib-clib` 1.3.2 を同梱するバージョンとして使う（`cabal.project` で固定）。
- wasmtime はプラットフォームごとの C API の配布物を `scripts/fetch-wasmtime.sh` で取得する（SHA-256 を検証し、`third_party/wasmtime` に置く。`third_party/wasmtime/VERSION` の名前と SHA-256 がスクリプトのものと一致しなければ取り直す）。
- wasm の版（`golem.wasm`）のツールチェーンは、ghc-wasm-meta の配布物を `scripts/fetch-ghc-wasm.sh` で x86-64 の Linux の向けだけ取得する（各アーカイブの SHA-256 と、`autogen.json` の SRI の値を 16 進に直したものを検証し、`third_party/ghc-wasm` に置く、[docs/adr/0199](./docs/adr/0199-pdf-typesetting-as-wasm-reactor.md)）。

wasm の版だけは、ネイティブの版と違うパッケージを使う（[docs/adr/0202](./docs/adr/0202-packages-that-do-not-build-for-wasm.md)）。
32 ビットで組めない cborg 0.2.10.0 の代わりに、上流のコミット 6ef2791c を `cabal.project.wasm` の `source-repository-package` で使う。
`network` に依存する `xml-conduit` を外すために、Hackage の `skylighting` 0.15.0.1 と `skylighting-core` 0.15.0.1 に `Skylighting.Parser` と `Skylighting.Loader` を除く差分（`scripts/wasm/patches/`）を当てたものを、`scripts/fetch-wasm-packages.sh` で `third_party/wasm-packages/` に置いて使う。

ライセンスの文書のうち、ビルドの環境から取れないものはリポジトリに置く。
`licenses/` には、配布物の `THIRD_PARTY_LICENSES/` に写すライセンスの文書のうち、ビルドの環境から取れないもの（`libwasmtime.a` に入った Rust のクレートなどの文書と、Alpine のパッケージが入れない文書と、wasi-sdk の配布物が持たない文書の `licenses/wasi-sdk/`）を置く（[docs/adr/0007](./docs/adr/0007-third-party-licenses.md)）。
`licenses/plugins/` には、見本のプラグインに入るものの著作権の表示とライセンスの文書を `scripts/plugin-licenses.sh` で生成して置く（[docs/adr/0133](./docs/adr/0133-third-party-licenses-of-sample-plugins.md)）。

### ビルドとテスト

GHC 9.10.3 と cabal-install 3.18.2.0 を ghcup で入れる。
`mise.toml` は ghcup の `bin` を `PATH` に加える。
`mise.toml` は、リリースノートを書く Claude Code のバージョンも固定する（`mise install` で入る）。
C と C++ のコンパイラも必要である。

最初に wasmtime を取得する。
このスクリプトは、ライブラリの絶対パスを `cabal.project.local` に書き込む。

```bash
scripts/fetch-wasmtime.sh
```

その後にビルドし、テストする。

```bash
cabal build all
```

```bash
cabal test all
```

依存のバージョンは `cabal.project.freeze` で固定している。
このファイルを消してビルドすると、依存のバージョンが変わりうる。

golem のパッケージは `-Werror` でビルドするので、warning が一つでもあるとビルドが止まる（[docs/adr/0245](./docs/adr/0245-keep-the-warnings-of-ci-at-zero.md)）。
手元で warning を見ながら作業するときは、自分の `cabal.project.local` に次を書けば止まらない。

```
package *
  ghc-options: -Wwarn
```

この `cabal.project.local` は CI に持ちこめない。
`scripts/ci/werror.sh` が、`cabal.project.local` の `-Wwarn` を見つけて失敗する。

#### ゴールデン

ゴールデン（出力を固定したファイル）は tasty-golden で比べる。
tasty-golden は、ゴールデンのファイルがなければ作ってテストを通す。
CI は環境変数 `TASTY_NO_CREATE=true` を付けてテストを走らせるので、ゴールデンが欠けていると失敗する。
手元でも同じ条件で確かめるには、この変数を付ける。

```bash
TASTY_NO_CREATE=true cabal test all
```

出力を意図して変えたときは、パッケージを指定して `--accept` を付け、ゴールデンを書き直す。
`--accept` は tasty-golden を使うテストのスイートだけが受け付ける（`golem-cli-test`、`golem-driver-test`、`golem-fmt-test`、`golem-font-test`、`golem-layout-test`、`golem-lsp-test`、`golem-pdf-test`、`golem-svg-test`）。
golem-driver と golem-font はほかのスイートも持ち、そちらは `--accept` を拒むので、スイートの名前まで指定する。
書き直したファイルの差分を読み、意図した変更だけであることを確かめてからコミットする。

```bash
cabal test golem-driver:golem-driver-test --test-options=--accept
```

#### 見た目の回帰テスト

見た目の回帰テストは、23 の入力の PDF を shem で 72 dpi の画像に描き、ページごとの SHA-256 を `scripts/visual/pages/` の参照と比べる（[docs/adr/0094](./docs/adr/0094-visual-regression-page-hashes-at-72-dpi.md)）。
入力には、機能を組み合わせた二冊の fixture（`modules/golem-driver/test/fixtures/complex-vertical` と `complex-horizontal`）を含む（[docs/adr/0175](./docs/adr/0175-complex-typesetting-fixture.md)）。
二冊は、出力のゴールデンと決定性の検査（`scripts/determinism.sh` と `scripts/env-determinism/check.sh`）の入力でもある。
二冊の参照やゴールデンを書き直すプルリクエストは、説明に、変わったページと変わった理由を書く（`CONTRIBUTING.md`）。

手元で動かすには、PDF のページを画像にするラスタライザ [shem](https://github.com/tett23/shem) が要る。
`scripts/visual/fetch-shem.sh` が、固定した版の shem を shem の release から取り、SHA-256 を確かめて `third_party/shem/` に入れる（[docs/adr/0093](./docs/adr/0093-fetch-shem-pinned-by-version-and-sha256.md)）。
取ったアーカイブは `third_party/downloads/` に残り、次からはその SHA-256 を照合して使う（[docs/adr/0243](./docs/adr/0243-retry-every-download-and-cache-the-archives-checked-by-sha-256.md)）。

```bash
scripts/visual/fetch-shem.sh
```

shem の配布物があるのは macOS の aarch64 と、Linux の x86-64 と aarch64 だけである。
ほかの環境（x86-64 の macOS など）では、shem の固定した版のタグを `cargo build --release` でビルドし、実行ファイルのパスを環境変数 `SHEM` に入れる。
`SHEM` の shem も、`shem --version` が固定した版でなければ使われない。

`scripts/visual/run.sh` が、入力を組み、shem を取り、比べるまでを続けて行う。
PDF の見た目を意図して変えたときは、ゴールデンと同じく `--accept` を付けて参照を書き直し、どのページが変わったかを参照の差分で確かめてから、同じプルリクエストに入れる。

```bash
GOLEM="$(cabal list-bin -v0 golem)" scripts/visual/run.sh
GOLEM="$(cabal list-bin -v0 golem)" scripts/visual/run.sh --accept
```

#### 生成したモジュール

生成したモジュールは、生成のもとと一緒にコミットする。
パーサーは `modules/golem-parser/grammar/Golem.hpeg` から生成し、生成物をコミットする。
文法を変えたら生成し直す。
同じスクリプトが、ラベルを外した文法（`modules/golem-parser/test/StrippedGrammar.hs`）も生成する。
テストは、二つの文法が同じ入力を受理することを確かめる（[golem-parser ADR 0007](./docs/golem-parser/adr/0007-grammar-label-safety.md)）。

```bash
scripts/gen-parser.sh
```

golem-driver が埋め込む `VERSION` と `docs/diagnostics.md` も、`scripts/gen-embedded.sh` で生成したモジュール（`modules/golem-driver/src/Golem/Driver/Version/Embedded.hs` と `modules/golem-driver/src/Golem/Driver/Explain/Embedded.hs`）をコミットする。
どちらかのファイルを変えたら、同じ変更で生成し直す。
golem-font に依存するパッケージは、wasm で組むために Template Haskell を使わない（[docs/adr/0203](./docs/adr/0203-generated-modules-instead-of-template-haskell-in-golem-driver.md)）。

```bash
sh scripts/gen-embedded.sh
```

#### パブリックドメインの fixture

テストの fixture の『テンペスト』と『蟹工船』、`modules/golem-driver/test/fixtures/pd/` の十冊は、`scripts/fixtures/fetch-public-domain.sh` が原文を取得して作る。
原文の変換は `modules/golem-fixtures` の実行ファイル `golem-fixtures` が行う。
このパッケージはリリースの配布物に入らない（[docs/adr/0023](./docs/adr/0023-fixture-converters-without-python.md)）。

```bash
GOLEM=$(cabal list-bin golem) scripts/fixtures/fetch-public-domain.sh
```

十冊はフォントをコミットしない。
そのディレクトリで `golem build` を実行する前に、`scripts/fixtures/copy-fonts.sh` で『蟹工船』と『テンペスト』のフォントを写す（[docs/adr/0026](./docs/adr/0026-ten-public-domain-fixtures.md)）。

十冊をどこまで組むかは、環境変数で決まる。
golem-driver のテストは十冊をエラーなしに検査し、環境変数 `GOLEM_PD_BOOKS` が `1` ならすべてのターゲットに組む。
`0` や `yes` などほかの値は、付けていないのと同じに扱う（[docs/adr/0074](./docs/adr/0074-test-switches-by-environment-variables.md)）。
CI の `build` ジョブは `GOLEM_PD_BOOKS=1` を付けてテストを走らせ、十冊をすべてのターゲットに組む（[docs/adr/0058](./docs/adr/0058-run-skipped-checks-in-ci.md)）。
手元では、変数を付けたときだけ組む。
組まずに検査だけで済ませた冊数は、テストの結果の後に標準エラー出力へ一行で出る。

```bash
scripts/fixtures/copy-fonts.sh
GOLEM_PD_BOOKS=1 cabal test golem-driver --test-options='-p 0026'
```

#### 外部ツールを使うテスト

いくつかのテストは、外部ツールを使う。
CDDL のスキーマへの適合の検査は、Rust の `cddl` クレートの CLI（0.10.7）を使う。
`PATH` にあるか `GOLEM_CDDL` で指定した場合だけ実行され、CI では必ず実行する。

```bash
cargo install cddl --version 0.10.7 --locked
```

ほかに、PDF の構造の検査は qpdf を、プラグインの配布のテストは openssl を使う。
これらの外部ツールがないと、それを使うテストは `SKIP` と表示されて飛ばされる。
tasty は `SKIP` を通ったテストとして数えるので、飛ばした数はテストのスイートの最後に、ツールごとに標準エラー出力へ一行で出る（`3 tests skipped: qpdf is not installed (GOLEM_REQUIRE_EXTERNAL_TOOLS=1 makes them failures)` の形）。

`GOLEM_REQUIRE_EXTERNAL_TOOLS=1` を付けると、ツールがないことがテストの失敗になる。
値は `1` だけが有効であり、`0` や `yes` などは付けていないのと同じに扱う（[docs/adr/0074](./docs/adr/0074-test-switches-by-environment-variables.md)）。
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

Golem のバージョンの正本はリポジトリの根の `VERSION` である。
バージョンを変えるときは、`VERSION` と全パッケージの cabal ファイルの `version` を一緒に書き換える（手順は [CONTRIBUTING.md](./CONTRIBUTING.md) の「タグとリリース」）。

### マニュアル

マニュアルの原稿は、使い手のマニュアルの `manual/` と、開発者のマニュアルの `manual-dev/` の二つの Golem のプロジェクトである（[docs/adr/0024](./docs/adr/0024-manual-audiences-and-policy.md)）。
書き方の方針は [docs/manual-policy.md](./docs/manual-policy.md) にある。
次のスクリプトで組める。

```bash
GOLEM="$(cabal list-bin golem)" sh scripts/manual/build.sh             # 二冊とも
GOLEM="$(cabal list-bin golem)" sh scripts/manual/build.sh manual-dev  # 一冊だけ
```

このスクリプトは、プロジェクトごとに、組む前の準備、組版、ライセンスの写しを順に行う。
`GOLEM` を省くと、`PATH` にある `golem` を使う。

1. 奥付の版とコミットのハッシュを `common/build-info.gm` に書く（`scripts/manual/build-info.sh`）。
2. マニュアルの書体（Noto Serif JP、Noto Sans JP、Source Serif 4、Source Sans 3、Source Code Pro。どれも SIL Open Font License 1.1）を、バージョンを固定した配布元から取得して SHA-256 を検査し、`fonts/` に置く（`scripts/manual/fetch-fonts.sh`。二回目からは検査だけを行う）。
3. `golem build --target pdf --target html` で組み、出力を `build/` に書く。
   エラー、警告、notice のどれか一つでも出れば失敗し、マニフェストに `silence-notices` があれば組む前に失敗する。
4. 組めたら、プロジェクトの `LICENSE`（CC0 1.0）を `build/html/LICENSE` に、`fonts/LICENSE-*`（SIL Open Font License 1.1 の全文）を `build/html/fonts/` に写す。
   組んだ HTML はフォントのファイルをそのまま含むので、その隣にライセンスの文書を置くためである（[docs/adr/0082](./docs/adr/0082-manuals-under-cc0.md)）。

プロジェクトに `LICENSE` がなければ、組む前に失敗する。

`build-info.gm` は生成物で、Git では管理しない。
マニュアルを `golem check` や LSP で開く前に、一度 `sh scripts/manual/build-info.sh manual`（開発者のマニュアルは `manual-dev`）を実行する。
実行しないと、奥付の `@import` の先がないエラー（G03002）になる。
Git のリポジトリの外で組むときは、環境変数 `GOLEM_MANUAL_COMMIT` と `GOLEM_MANUAL_TAG` で値を渡す。
スクリプトのテストは `scripts/manual/test.sh` にある。

#### 図の原稿と輪郭

二つのマニュアルの SVG の図は、`manual/images/src/` と `manual-dev/images/src/` の SVG が原稿である。
SVG を直したら、`sh scripts/manual/outline-figures.sh` で、文字を輪郭にした一つ上の `images/` の SVG を作り直し、両方をコミットする（`sh scripts/manual/outline-figures.sh manual workflow` のように、マニュアルと図を選べる）。
このスクリプトは Inkscape 1.x を使うので、図を直すときだけ Inkscape を入れておく（`INKSCAPE` で実行ファイルを選べる）。
組むときには実行しないので、マニュアルを組むだけなら Inkscape は要らない。
輪郭の SVG が原稿から作られたことは、`sh scripts/manual/check-figures.sh` で確かめられる（CI も確かめる）。

原稿の SVG の書き方には、輪郭を作る手順から来る制約がある。
Inkscape に渡す前に、`scripts/manual/outline-prepare.sh` が原稿の写しを直し、輪郭の文字を Chromium が原稿を描く位置に置く。
このため、原稿の `text` の要素は一行に書いて中に `halt` の `tspan` のほかに要素を置かず、`dominant-baseline` と `writing-mode` を決める CSS の規則も一行に書く。
縦書きの文字列に、隣り合う全角の約物を置かない（置くとスクリプトが止まる）。
原稿を開いて確かめるブラウザーは Chromium の系統のものにする（Safari では縦書きが輪郭と違って描かれる）。

図の隣り合う約物は、本文と同じ空きで組む（[docs/adr/0239](./docs/adr/0239-decide-the-conditions-of-the-outlined-figure-check-and-the-punctuation-of-figure-sources.md)）。
原稿の `<style>` に `text { text-spacing-trim: space-all; }` と `tspan.halt { font-feature-settings: "halt"; }` を一行ずつ置き、半角に詰める約物を `<tspan class="halt">（</tspan>` のように一字ずつ包む。

包む字は、本文の既定のアキ量のセットから決まる（[docs/adr/0241](./docs/adr/0241-derive-the-punctuation-of-figure-sources-from-the-default-aki-set.md)）。
隣り合う二つの約物では、前の字の後ろと後ろの字の前の墨の外の空きの和から、本文の最適の空きを引いた量を詰める。

- 詰める量が 0 なら包まない。
- 詰める量が後ろの字の前の空きと等しければ後ろの字を、前の字の後ろの空きと等しければ前の字を包む。
- 中点類は包まない。

どの字を包むかは `scripts/manual/check-figures.sh` が確かめ、どちらの字を包んでも本文と同じ空きにならない組と、縦書きの中の隣り合う約物はエラーにする。
既定のアキ量のセットの値は、golem-layout のテストが書く `modules/golem-layout/test/golden/default-aki-set.tsv` から読む。
既定のアキ量のセットを変えたら、`cabal test golem-layout:golem-layout-test --test-options=--accept` でこのファイルを書き直し、`check-figures.sh` が失敗すれば図の原稿を直して輪郭を作り直す。

### 整形と検査

Haskell のコードは fourmolu 0.21.0.0 で整形し（設定は `fourmolu.yaml`）、hlint 3.10 で検査する。
どちらも CI の `format` ジョブで検査する。
CI の hlint は、GHC でビルドせず、hlint のリリースの x86-64 Linux 向けの配布物を `scripts/ci/fetch-hlint.sh` で取得して使う（[docs/adr/0009](./docs/adr/0009-ci-speed.md)）。

文書とマニュアルの原稿の表記（一文ごとの改行、ダッシュと中黒、用語）は、textlint で検査する（[docs/adr/0036](./docs/adr/0036-textlint-for-documents.md)）。
Node を入れてから `sh scripts/ci/textlint.sh` を実行する。
初めての実行で、`tools/textlint/package-lock.json` が固定したパッケージを `tools/textlint/node_modules/` に入れる。
`TEXTLINT_ARGS=--fix` を付けると、直せる違反を直す。
文書はファイルごとに並べて検査し、何も報告しなかったファイルを `tools/textlint/.cache/` に覚えて、文書も規則も変わらなければ次から検査を省く（[docs/adr/0258](./docs/adr/0258-textlint-per-file-jobs-and-a-cache-of-clean-results.md)）。
規則と、止めた規則の理由は [tools/textlint/README.md](./tools/textlint/README.md) にある。

Golem のビルドとテストは Node を使わない。
エディタ向けの構文の定義のテスト（`tools/editors/test.sh`）は、textlint と同じく Node を使う。

### CI

プルリクエストと `main` への push で走る CI は、二つのワークフローからなる。
`.github/workflows/docs.yml` は ADR とドキュメントを、`.github/workflows/ci.yml` はコードを検査する（[docs/adr/0021](./docs/adr/0021-docs-workflow-and-ci-gate.md)）。

ほかに、決まった時刻か決まった変更で走るワークフローがある。

- 夜間に `main` で走る `.github/workflows/race.yml` と `.github/workflows/enum.yml` と `.github/workflows/browser.yml` と `.github/workflows/wasm-tests.yml`。
- 毎日一回 wasmtime のアドバイザリと action の固定を照合する `.github/workflows/advisories.yml`。
- Alloy のモデルを変えたときと週に一度走る `.github/workflows/models.yml` と、そのモデルの重いコマンドを夜間に走らせる `.github/workflows/models-nightly.yml`。

#### どのジョブを走らせるか

変更が `docs/` の下のファイル、`tools/textlint/` の下のファイル、リポジトリの根の Markdown のファイルだけの場合、`build`、`determinism`、`visual`、`format`、`release-scripts`、`scripts-macos`、`plugins`、`editors-lsp`、`verapdf` は省かれる（[docs/adr/0009](./docs/adr/0009-ci-speed.md)、[docs/adr/0036](./docs/adr/0036-textlint-for-documents.md)）。
ただし、ビルドやテストが読む文書（今は `docs/diagnostics.md`）を変えた場合はビルドする（[docs/adr/0021](./docs/adr/0021-docs-workflow-and-ci-gate.md)）。
判定は `scripts/ci/needs-build.sh` が行い、プルリクエストの変更のパスは分岐点からの差分で取る（`scripts/ci/changed-paths.sh`）。
ファイルの移動は、移動元と移動先の両方を変更のパスとして数える（[docs/adr/0070](./docs/adr/0070-changed-paths-without-rename-detection.md)）。
`adr` と `textlint` は、変更のパスにかかわらず常に走る。

`main` の保護の規則が必須とする検査は、`ci`、`adr`、`manual`、`textlint` の四つである。
同じプルリクエストに新しいコミットを push すると、走っている前の実行は取り消される。

CI の所要時間の記録は `docs/ci-timings/` に置き、`scripts/ci/timings.sh` で作る。
`ci.yml` のステップ「qpdf is installed」と「epubcheck is installed」の結果（`conclusion`）を、実行ごとに数えるには、`scripts/ci/step-timeouts.sh <日時> <回数>` を使う（[docs/adr/0230](./docs/adr/0230-check-the-release-workflow-and-ci-history-by-scripts.md)）。

#### 文書のワークフロー（docs.yml）

- `adr`：コミット済みの ADR と記録（`docs/audit/`、`docs/audits/`、`docs/benchmarks/`、`docs/benchmark/`）が変更されていないこと、文書の中の ADR の参照にリンクがあること、各 ADR がステータスの行をちょうど一つ持つことを検査する。
- `manual`：プルリクエストで、`docs/markup.md` か `docs/specifications.md` を変えたのに `manual/` も `manual-dev/` も変えていないこと、`CONTRIBUTING.md` か `CONTRIBUTING.en.md` を変えたのに `manual-dev/` を変えていないことを検査する（`scripts/manual/check-updated.sh`）。
  `main` への push では省く。
- `textlint`：`tools/textlint/` の規則のテストを実行し、`docs/` の文書（ADR と記録を除く）、README.md、CONTRIBUTING.md、変更で加わった ADR、二つのマニュアルの原稿の表記を textlint で検査する（`scripts/ci/textlint.sh`、[docs/adr/0036](./docs/adr/0036-textlint-for-documents.md)）。
  何も報告しなかったファイルのキーをキャッシュに保つ（[docs/adr/0258](./docs/adr/0258-textlint-per-file-jobs-and-a-cache-of-clean-results.md)）。
- `anchors`：`docs/diagnostics.md` か `modules/golem-driver/src/Golem/Driver/Explain.hs` を変えたプルリクエストと `main` への push で、GitHub の API が描いた `docs/diagnostics.md` の HTML に、すべての diagnostic のコードの見出しの `id`（`user-content-g01017` の形）があることを確かめる（`scripts/ci/github-anchors.sh`）。
  API から引けないフォークのコミットは飛ばし、`main` への push で確かめる（[docs/adr/0235](./docs/adr/0235-check-the-manual-wat-example-the-diagnostic-anchors-and-the-alloy-models-in-ci.md)）。

#### コードのワークフロー（ci.yml）

`ci.yml` のジョブは次のとおりである。

##### `changes`

`changes` は、次のことを確かめ、変更のパスからビルドが要るかを決める。

- ビルドが読む `docs/` の下の文書が一覧にあること。
- 全パッケージが `-Werror=incomplete-patterns` でビルドされること（`scripts/ci/incomplete-patterns.sh`、[docs/adr/0027](./docs/adr/0027-exhaustive-command-dispatch-by-types.md)）。
- 全パッケージのすべてのコンポーネントが `-Werror` でビルドされること（`scripts/ci/werror.sh`、[docs/adr/0245](./docs/adr/0245-keep-the-warnings-of-ci-at-zero.md)）。
- `unsafePerformIO` の使用が一覧のとおりであること（`scripts/ci/unsafe-io.sh`、[docs/adr/0034](./docs/adr/0034-fewer-unsafe-perform-io.md)）。
- `modules/` のプログラムが実行中に capability の数を変えないこと（`scripts/ci/rts-capabilities.sh`）。
- すべてのテストのスイートが `x86_64` と `aarch64` のそれぞれに時間の上限を一つずつ持つこと（`scripts/ci/suite-limits.sh --check`、[ADR 0292](./docs/adr/0292-limit-the-time-of-each-test-suite-by-the-median-of-main.md)）。
- プラグインの ABI のバージョンが直前のリリースからの ABI の変更に合っていること（`scripts/ci/abi-version.sh`、[docs/adr/0052](./docs/adr/0052-plugin-abi-version-bump-rule.md)。直前のリリースが `v1.0.0` 以降なら、ABI の変更の予告と patch の規則も）。
- 直前のリリースが `v1.0.0` 以降なら、diagnostic のコードが 1.x の約束を守っていること（`scripts/ci/diagnostic-codes.sh`、[docs/adr/0174](./docs/adr/0174-compatibility-promises-for-1-0.md)）。

スクリプトのテストは `scripts-linux` に分け、ビルドがその終わりを待たないようにしている（[docs/adr/0097](./docs/adr/0097-ci-same-path-before-build-and-env-check-runner.md)）。

##### `scripts-linux`

`scripts-linux` は、スクリプトのテストを `ubuntu-24.04` で実行する。
対象は、`scripts/ci/`、`scripts/manual/`、`scripts/env-determinism/`、`scripts/visual/` のスクリプトと、手でだけ動くスクリプト（`scripts/gen-vertical-orientation.sh`、`scripts/fixtures/` の二本、`scripts/plugin-licenses.sh`、`scripts/wasmtime-advisories.sh`）と、`scripts/gen-embedded.sh` のテスト（`scripts/ci/test.sh`、`scripts/manual/test.sh`、`scripts/env-determinism/test.sh`、`scripts/visual/test.sh`、`scripts/test.sh`、[docs/adr/0078](./docs/adr/0078-tests-for-release-and-hand-run-scripts.md)、[docs/adr/0093](./docs/adr/0093-fetch-shem-pinned-by-version-and-sha256.md)）である。
ワークフローのすべての action がコミットの SHA と版の注釈で指定されていることも、`scripts/ci/actions-pins.sh check` で確かめる（[docs/adr/0296](./docs/adr/0296-pin-every-github-action-by-commit-sha.md)）。
`needs` も条件も持たず、文書だけの変更でも走る（[docs/adr/0097](./docs/adr/0097-ci-same-path-before-build-and-env-check-runner.md)）。

##### `build`

`build` は、x86-64 と aarch64 の Linux でビルドとテストを行う。
10 分で終わらないテストのスイートは `scripts/ci/suite-timeout.sh` が止めて失敗にする。
終わったスイートは、かかった秒を標準エラーに一行で書き、その秒が `scripts/ci/suite-limits.tsv` のアーキテクチャごとの上限を超えれば失敗にする。
上限は、直近の `main` への push の 20 回の中央値 m から `max(10, ceil(2 × m))` で決める（[ADR 0292](./docs/adr/0292-limit-the-time-of-each-test-suite-by-the-median-of-main.md)）。

ビルドの後に、生成物と出力を確かめる。
生成したパーサーが文法と一致すること、`scripts/gen-embedded.sh` で生成した golem-driver のモジュールが `VERSION` と `docs/diagnostics.md` と一致すること（[docs/adr/0203](./docs/adr/0203-generated-modules-instead-of-template-haskell-in-golem-driver.md)）を確かめる。
`scripts/determinism.sh` の出力を作り、その中で `manual/` と `manual-dev/` を notice も含めて diagnostic を一つも出さずに組む。

x86-64 では、さらに次のことを行う。

- EPUB が epubcheck を通ることを確かめる。
- 組んだ二つのマニュアルの PDF と HTML を成果物 `manual` と `manual-dev` として上げる。
- 見た目の回帰テストの 23 の PDF を `scripts/visual/build.sh` で組んで成果物 `visual-pdfs` として上げる（[docs/adr/0095](./docs/adr/0095-visual-job-in-ci.md)）。
- 実行の環境を変えても出力が変わらないことを `scripts/env-determinism/check.sh` で確かめる。
  プルリクエストでは `--quick` で小さな入力だけを検査し、`main` への push とリリースではすべての入力を検査する（[docs/adr/0029](./docs/adr/0029-environment-variation-determinism-test.md)、[docs/adr/0038](./docs/adr/0038-env-determinism-quick-on-pull-requests.md)）。

ジョブは、アーキテクチャごとに複数のランナーに分かれる（[docs/adr/0140](./docs/adr/0140-ci-split-test-runners-and-visual-pdfs-first.md)、[docs/adr/0155](./docs/adr/0155-split-aarch64-test-runner.md)）。
x86-64 では同じコミットを四つのランナーでビルドする。
`tests-driver` が golem-driver のテストのスイートを、`tests-rest` がそのほかのスイートを（振り分けは `scripts/ci/test-suites.sh` が `.cabal` から決める）、`outputs` が見た目の回帰テストの PDF（`visual` を待たせないよう最初に組む）、`wasm` と比べるネイティブの一覧、epubcheck、決定性の検査の出力、マニュアルを、`env` が環境を変える検査を受け持つ。
aarch64 では三つのランナーでビルドし、x86-64 と同じく `tests-driver` と `tests-rest` がテストのスイートを、`outputs` が決定性の検査の出力を受け持つ。

テストの道具は、ビルドと並べて入れる。
テストのラッパーは、すべての `cabal` のコマンドが同じ設定を読むように `cabal.project.local` に書き、qpdf と epubcheck はビルドの裏で入れる（[docs/adr/0037](./docs/adr/0037-ci-build-job-speedup.md)）。
qpdf は apt で入れ、止まったダウンロードを 30 秒で切って 3 回まで取り直す。
epubcheck は apt を使わず、配布元（w3c/epubcheck）の release の zip（5.4.0）を `ci.yml` に書いた SHA-256 で検査して `scripts/ci/epubcheck-install.sh` で入れ、ランナーにもとからある Java 17 で動かす。
zip は版と SHA-256 をキーにキャッシュする（[docs/adr/0062](./docs/adr/0062-epubcheck-from-release-with-cache.md)）。

`env` は日本語のロケールを作り、マニュアルのフォントをキャッシュか `scripts/manual/fetch-fonts.sh` で取る。
cabal は `PATH` をすべてのパッケージの設定に含めるので、`cabal build` より前に `PATH` を変えるのは、どのランナーでも同じディレクトリを足す GHC の手順だけとし、epubcheck は `cabal build` の後で `PATH` に足す（[docs/adr/0097](./docs/adr/0097-ci-same-path-before-build-and-env-check-runner.md)）。

`dist-newstyle` は、`main` への push で GHC がモジュールをコンパイルしたときに、アーキテクチャごとに一つのランナー（どちらのアーキテクチャでも `tests-driver`）が保存する。
プルリクエストは `main` の最新の `dist-newstyle` を戻すだけで、保存しない（[docs/adr/0045](./docs/adr/0045-split-x86-build-and-pull-request-cache.md)、[docs/adr/0228](./docs/adr/0228-keep-the-ci-caches-under-the-10-gb-limit.md)）。

##### `determinism`

`determinism` は、出力のハッシュを二つのアーキテクチャで比べる（[docs/adr/0071](./docs/adr/0071-determinism-check-compares-diagnostics.md)）。
比べるのは、決まった入力（`scripts/determinism.sh`。二つのマニュアル、機能を組み合わせた二冊の fixture（[docs/adr/0175](./docs/adr/0175-complex-typesetting-fixture.md)）と、diagnostics を出す `scripts/env-determinism/diagnostics/` を含む）の出力のハッシュと、マニュアルのほかの入力の diagnostics（標準出力と標準エラー出力のハッシュ）と終了コードである。

コミットをまたいだ出力の変化も見つける。
x86-64 の一覧からマニュアルの行を除いたものを、コミットした `scripts/determinism/hashes.txt` と `scripts/ci/determinism-hashes.sh` で比べる。
意図して出力を変えるプルリクエストとリリースのプルリクエストは、`scripts/determinism.sh --no-manuals` の出力で `hashes.txt` を書き直す（[docs/adr/0173](./docs/adr/0173-rc4-refactoring.md)）。

##### `visual`

`visual` は見た目の回帰テストである。
`changes` だけを待って `build` と同時に始まり、`build` の x86-64 の `outputs` が成果物 `visual-pdfs` を上げるのを `scripts/visual/wait-pdfs.sh` で待つ（上限は 60 分、ジョブは 75 分。`outputs` が上げずに終わると失敗する、[docs/adr/0099](./docs/adr/0099-visual-job-waits-only-for-visual-pdfs.md)）。
成果物は既定で 30 秒ごとに問い合わせる。
見つからなければ初回と以降 4 間隔ごとに生成元のジョブを確認する。
GitHub API が利用上限を返したときは、応答に従って待ってから再試行する（[ADR 0333](./docs/adr/0333-wait-for-ci-artifacts-with-fewer-api-requests.md)）。

上がった `visual-pdfs` を取り寄せ、固定した版の shem で 72 dpi の PPM に描き、ページごとの SHA-256 が `scripts/visual/pages/` の参照と一致することを `scripts/visual/check.sh` で確かめる。
shem は、shem のアーカイブを `third_party/downloads` に `scripts/visual/fetch-shem.sh` のハッシュをキーにキャッシュし、`fetch-shem.sh` を 10 分の上限で実行して取る。
戻したアーカイブは SHA-256 を照合してから展開する（[docs/adr/0243](./docs/adr/0243-retry-every-download-and-cache-the-archives-checked-by-sha-256.md)）。
比べる手順の上限は実時間の 600 秒である。

失敗したときは、`scripts/visual/report.sh` がジョブの要約に、shem が読めなかった PDF と、変わったページ（違う画素の数と矩形）を書く。
変わったページの前と後の画像と差分の画像、このコミットの参照の一覧は、成果物 `visual-diff` として上げる。
前の画像は、ベースのコミットか、その 20 個までの first-parent の祖先の `ci.yml` の push の実行の成果物 `visual-pdfs` から描くので、このジョブだけがトークンに `actions: read` を持つ（[docs/adr/0093](./docs/adr/0093-fetch-shem-pinned-by-version-and-sha256.md)、[docs/adr/0094](./docs/adr/0094-visual-regression-page-hashes-at-72-dpi.md)、[docs/adr/0095](./docs/adr/0095-visual-job-in-ci.md)、[docs/adr/0096](./docs/adr/0096-before-and-after-images-of-changed-pages.md)）。

##### `release-scripts`

`release-scripts` は、`VERSION` と全パッケージのバージョンの一致を検査する。
さらに、`mise.toml` に固定した版の Claude Code を、`notes` と同じ版と SHA-256 で固定した mise で入れて、`scripts/release/` のスクリプトのテスト（`scripts/release/test.sh`）を `GOLEM_REQUIRE_CLAUDE=1` で実行する（[docs/adr/0058](./docs/adr/0058-run-skipped-checks-in-ci.md)）。
テストは、リリースのときだけ動くスクリプト（アーカイブの作成と検査、GMP の版と取得、macOS のビルド）も、偽のコマンドでネットワークを使わずに動かす（[docs/adr/0078](./docs/adr/0078-tests-for-release-and-hand-run-scripts.md)）。

##### `scripts-macos`

`scripts-macos` は、macOS 15 のランナーで、`PATH` をシステムの道具（BSD 版の `awk`、`sed`、`find`、`grep`）だけにして、`scripts/` の下の六本のテスト（`scripts/ci/test.sh`、`scripts/manual/test.sh`、`scripts/env-determinism/test.sh`、`scripts/release/test.sh`、`scripts/test.sh`、`scripts/visual/test.sh`）を、`scripts/ci/run-all.sh` で同時に、600 秒の期限を付けて実行する（[docs/adr/0079](./docs/adr/0079-shell-tests-on-macos.md)、[docs/adr/0154](./docs/adr/0154-scripts-macos-tests-at-once-with-deadline.md)）。

##### `format`

`format` は、fourmolu と hlint で検査する。

##### `plugins`

`plugins` は、`plugins/` の Rust のクレート（見本のプラグインと、それを書く補助のクレート `golem-plugin-sdk`）のテストを実行する。
コミットした `plugins/wasm/*.wasm` が、`plugins/rust-toolchain.toml` の版のツールチェーンでソースから作ったバイト列と一致することを `plugins/build.sh --check` で確かめる（[docs/adr/0106](./docs/adr/0106-sample-plugins-in-rust.md)）。
`licenses/plugins/` が、依存のクレートとツールチェーンから作り直したものと一致することを `scripts/plugin-licenses.sh --check` で確かめる（[docs/adr/0133](./docs/adr/0133-third-party-licenses-of-sample-plugins.md)）。

##### `editors`

`editors` は、`tools/editors/` のエディタ向けの構文の定義を `tools/editors/test.sh` で検査する（[docs/adr/0170](./docs/adr/0170-emet-editor-support.md)、[docs/adr/0231](./docs/adr/0231-run-the-lsp-and-the-editor-grammars-in-headless-neovim-and-helix.md)）。
確かめるのは次のことである。

- 生成した tree-sitter のパーサーが `grammar.js` と一致すること。
- tree-sitter と TextMate の文法のテスト。
- 二つの形式が同じ見本で同じ分類になること。
- テストの原稿と二つのマニュアルのすべての `.gm` と `.emet` を tree-sitter が誤りなく読むこと。

テストの道具は `tools/editors/package-lock.json` で固定し、tree-sitter の実行ファイルの SHA-256 を照合する。
あわせて、`tools/editors/helix/test.sh` で、`tools/editors/README.md` の Helix の手順のとおりに Helix 25.07.1 が二つの文法を作り、パーサーと強調の問い合わせを見つけることを確かめる。
Helix は版とアーカイブの SHA-256 で固定する。
`needs` も条件も持たず、文書だけの変更でも走る。

##### `editors-lsp`

`editors-lsp` は、ヘッドレスの Neovim 0.12.6 で、golem lsp とエディタの文法を `tools/editors/nvim/test.sh` で確かめる（[docs/adr/0231](./docs/adr/0231-run-the-lsp-and-the-editor-grammars-in-headless-neovim-and-helix.md)）。
確かめるのは、位置の符号化、diagnostic の列の丸め、notice の severity と quickfix と `silence-notices`、空白の semantic tokens とその強調のグループ、`style.toml` と `preflight.toml` の補完の一覧と選んだ後の行、`tools/editors/README.md` の nvim-treesitter を使わない手順である。
各テストの期待を反転すると失敗することも `--self-test` で確かめる。
`changes` だけを待ち、`build` の x86-64 の `outputs` が上げる成果物 `golem-linux-x86_64` を `scripts/visual/wait-pdfs.sh` で待つ。
Neovim は `tools/editors/fetch-nvim.sh` が版とアーカイブの SHA-256 で固定する。

##### `wasm`

`wasm` は、PDF の組版を wasm の reactor モジュールにした `golem.wasm` を組み、ネイティブの `golem` と同じ PDF と diagnostics を返すことを確かめる（[docs/adr/0199](./docs/adr/0199-pdf-typesetting-as-wasm-reactor.md)、[docs/adr/0202](./docs/adr/0202-packages-that-do-not-build-for-wasm.md)）。
`build` と同じく `changes` の `build` が真のときに、`build` と同時に走る。

組む手順は次のとおりである。
ghc-wasm-meta の 9.10 の flavour のツールチェーンを `scripts/fetch-ghc-wasm.sh` で取り、`skylighting` の差分を `scripts/fetch-wasm-packages.sh` で当てる。
`cabal.project.wasm.freeze` の版が `cabal.project.freeze` と一致することを `scripts/ci/wasm-freeze.sh` で確かめてから、`cabal.project.wasm` で `golem-wasm` を組む。
組んだ直後の `golem.wasm` に例外処理の古い形の命令がないことを `scripts/wasm/legacy-eh.sh` で確かめる（Node で `--no-experimental-wasm-legacy-eh` を付けて検証する、[docs/adr/0238](./docs/adr/0238-build-golem-wasm-with-the-standard-exception-handling-and-run-it-under-wasmtime.md)）。

組んだ `golem.wasm` は、二つの方法で確かめる。
`setup-node` の Node LTS の `node:wasi` で `scripts/wasm/run.mjs` から動かし、エクスポートとインポート、読めない入力の枠、`[plugins]` を書いたマニフェスト（G06106）、同じインスタンスと新しいインスタンスでの繰り返しを確かめる。
`scripts/wasm/compare.sh` で入力ごとの PDF と diagnostics の JSON と終了コードの SHA-256 の一覧を作り、`build` の x86-64 の `outputs` がネイティブの `golem` で作って上げる一覧 `wasm-native-list` を `scripts/visual/wait-pdfs.sh` で待って、`diff` で比べる。
`golem.wasm` と一覧は成果物 `golem-wasm` として上げる。

キャッシュは三つに分ける。
ツールチェーンと wasm の cabal の store と索引は一つのキャッシュ、ネイティブの GHC で組んだ `alex` と `happy` は別のキャッシュ、`dist-wasm` はコミットごとのキャッシュに置く。
`dist-wasm` を保存するのは `main` への push だけで、プルリクエストは `main` の `dist-wasm` を戻して変わったパッケージだけを組み、保存しない。
ビルドに関わる変更のあるプルリクエストごとに走らせる頻度は変えない（[docs/adr/0219](./docs/adr/0219-frequency-of-the-wasm-job-and-its-uncached-runs.md)）。
最後の `Times` のステップは、ツールチェーンのキャッシュが外れた理由（ツールチェーンを替えた、プロジェクトか freeze が `main` と違う、どれも同じなのに外れた）を `scripts/ci/wasm-cache.sh` で一行に書き、三つめ（キャッシュが消された）では `::warning::` の注釈を出してジョブは通す。
ツールチェーンか freeze を替えるプルリクエストの最初の実行は 5 分を超えてよい（CONTRIBUTING の「GitHub Actions」）。

##### `verapdf`

`verapdf` は、`build` の x86-64 の `outputs` が上げる成果物 `conformance-pdfs` の PDF を、veraPDF で PDF/A-2a と PDF/UA-1 として検証する（`scripts/ci/verapdf.sh`、[docs/adr/0183](./docs/adr/0183-tagged-pdf-and-pdf-a.md)）。
`visual` と同じく `changes` だけを待って `build` と同時に始まり、Nix の導入と veraPDF の取得を終えてから、`conformance-pdfs` が上がるのを `scripts/visual/wait-pdfs.sh` で待つ（上限は 60 分、ジョブは 75 分。`outputs` が上げずに終わると失敗する）。
`build` の全体を待たないので、CI の臨界経路にない（[docs/adr/0244](./docs/adr/0244-take-verapdf-off-the-critical-path-of-ci.md)）。

##### `caches`

`caches` は、`main` への push で、`build` と `wasm` が終わった後に（どちらかが失敗しても）走り、`main` の古い `dist-` のキャッシュを消す（[docs/adr/0228](./docs/adr/0228-keep-the-ci-caches-under-the-10-gb-limit.md)）。
`gh cache list` で `main` の `dist-` のキャッシュの一覧を取り、三つの族（x86-64 と aarch64 の `dist-newstyle`、`dist-wasm`）のそれぞれで作った日時のいちばん新しいもの一つを残し、ほかの `dist-` のキャッシュを `scripts/ci/stale-dist-caches.sh` が選んで `gh cache delete` で消す。
消したキーと、消す前と後のキャッシュの量をジョブの要約に書く。
`ci.yml` でトークンに書き込みの権限（`actions: write`）を持つのはこのジョブだけで、`actions/checkout` のほかにアクションを使わず、ビルドもテストも走らせない。
失敗するとジョブは失敗になるが、`ci` はこのジョブを待たない。

##### `ci`

`ci` は、`ci.yml` のほかのジョブ（`caches` を除く）がすべて成功したか、省かれたことを確かめる（`scripts/ci/gate.sh`）。
別の step で、同じ実行の終わったジョブのログを読み、`scripts/ci/warnings-allowed.tsv` にない warning がないことを確かめる（`scripts/ci/log-warnings.sh`、[docs/adr/0245](./docs/adr/0245-keep-the-warnings-of-ci-at-zero.md)）。

#### 定期に走るワークフロー

`docs.yml` と `ci.yml` のほかのワークフローは、次のとおりである。
夜間の `race.yml`、`enum.yml`、`browser.yml`、`wasm-tests.yml`、`models-nightly.yml` は、毎日一回 `main` で起動し、前回の成功した実行から `main` が変わっていれば走る（判定は `scripts/ci/race-needed.sh`）。
`workflow_dispatch` で手で起動すると、判定せずに走らせる。
権限は `contents: read` と `actions: read` だけである。

##### `models.yml` と `models-nightly.yml`

- `models.yml` の `models`：`docs/*/models/` を変えたプルリクエストと `main` への push と週に一度、版と SHA-256 で固定した Alloy 6.2.0 の jar で、モデルのコマンドを一つずつ並べて走らせ、解の有無が同じディレクトリの `expected.txt` のとおりであることを確かめる（`scripts/models/check.sh`、上限は 30 分、[docs/adr/0235](./docs/adr/0235-check-the-manual-wat-example-the-diagnostic-anchors-and-the-alloy-models-in-ci.md)）。
- `models-nightly.yml` の `prepare`、`nightly`：`scripts/ci/race-needed.sh` に `models-nightly.yml` を渡して判定し、`expected.txt` には重すぎるコマンドを挙げた同じディレクトリの `nightly.txt` のコマンドを、一つのジョブに一つずつ同時に走らせ、解の有無が `nightly.txt` のとおりであることを確かめる（`scripts/models/check.sh -f nightly.txt`）。
  一つのコマンドの上限は 5.5 時間（`TIMEOUT=19800`）で、時間切れは失敗にせず、注釈とジョブの要約に書く。
  結果の違いと Alloy の失敗だけを失敗にする（[docs/adr/0242](./docs/adr/0242-run-the-heavy-commands-of-the-alloy-models-every-night.md)）。

##### `advisories.yml`

`advisories.yml` は、毎日一回と `workflow_dispatch` で走り、固定したものを上流と照合する。
プルリクエストでは走らない。
権限は `contents: read` だけである。

- `wasmtime`：固定した wasmtime の版を bytecodealliance/wasmtime のリポジトリのアドバイザリと `scripts/wasmtime-advisories.sh` で照合する。
  当たるアドバイザリがあるか、読めないアドバイザリがあれば失敗し、スケジュールの実行の失敗の通知がメンテナーに届く（[docs/adr/0157](./docs/adr/0157-check-wasmtime-pin-against-advisories.md)、[docs/adr/0166](./docs/adr/0166-read-wasmtime-advisory-ranges-as-written.md)）。
- `actions`：ワークフローで固定した action を上流と照合する。
  `scripts/ci/actions-pins.sh verify` で注釈のタグが固定したコミットを指すことを、`latest` で固定した版が上流のいちばん新しい版で、Node 24 以降か composite で動くことを確かめる。
  外れれば失敗し、メンテナーが `update` で書き換えたプルリクエストを出す（[docs/adr/0296](./docs/adr/0296-pin-every-github-action-by-commit-sha.md)）。

##### `race.yml`

`race.yml` の `race` は、並行の競合を探すテスト（`golem-driver-parallel-test`、`golem-font-race-test`、`golem-font-test` の並行のテスト）を `GOLEM_RACE_TESTS=40` で走らせる（[docs/adr/0075](./docs/adr/0075-race-search-repetitions.md)）。

`GOLEM_RACE_TESTS` は、競合を探すテストの回数に掛ける数である（1 以上の整数。未設定なら 1）。
プルリクエストの CI は設定せず、今の回数で走らせる。

`race.yml` が落ちたら、落ちたテストの名前と、ログに出たシードとサイズ（tasty-hedgehog が `--hedgehog-replay` に渡す形で書く）と、実行の URL と head のコミットを添えて issue を立てる。
手元では、`GOLEM_RACE_TESTS=40 cabal test golem-driver-parallel-test` のように同じ回数で試し、`--hedgehog-replay` で落ちた例を再現する。

##### `enum.yml`

`enum.yml` の `enum` は、`scripts/ci/race-needed.sh` に `enum.yml` を渡して判定し、不変条件を小さな入力のすべてで確かめるテストを、範囲ごとの段（step）で走らせる（[docs/adr/0204](./docs/adr/0204-pagination-invariants-by-exhaustive-small-inputs.md)、[docs/adr/0208](./docs/adr/0208-widen-lightweight-formal-methods.md)）。
段ごとに、すべてを調べる上限と、その一つ上の段から抜き取る入力の数を環境の変数で渡し、すべての段の和を 60 分以内に収める（ジョブの上限は 90 分）。
範囲の段はどれも `!cancelled()` を持ち、前の段が落ちても走る。

範囲の段の前の段（`scripts/ci/enum-timings.sh`）は、時間を量る。
範囲ごとのテストを上限の変数を渡さずにプルリクエストと同じ設定で走らせ、範囲ごとの壁時計の時間と和を予算（範囲ごとに 10 秒、和で 30 秒）と並べた表にして、ジョブの要約とログに書く（[ADR 0281](./docs/adr/0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md)）。
範囲の時間は、`cabal list-bin` で求めたテストの実行ファイルを直接走らせた時間で、`cabal test` の起動の時間を含まない。
時間が予算を超えても、この段は落ちない。
`workflow_dispatch` の入力 `timings` を付けて起動すると、この段だけを四つのジョブで走らせ（範囲の段は走らせない）、後の `medians` のジョブが四つの表の範囲ごとと和の中央値を予算と並べて要約に書く（`enum-timings.sh --median`）。
予算と比べるのは、この中央値である（[ADR 0286](./docs/adr/0286-leave-the-start-of-cabal-out-of-the-time-of-an-enumeration-area.md)）。

範囲の段と、プルリクエストの CI が同じテストを調べる範囲は、次のとおりである。

- 改ページの段：golem-layout のテスト（「pagination invariants」の「every input」のうち「keep options」でないもの）を `GOLEM_ENUM_DEPTH=5` と `GOLEM_ENUM_PAGINATION_SAMPLES=5000000` で走らせる。
  プルリクエストの CI は、同じテストを要素 3 個まで調べ、抜き取らない。
- 段落の分け方の段：golem-layout のテスト（「pagination invariants」の「keep options」の「every input」）を `GOLEM_ENUM_KEEP_DEPTH=4` と `GOLEM_ENUM_KEEP_SAMPLES=5000000` で走らせ、要素 4 個までのすべての入力と、要素 5 個の入力の抜き取りを調べる。
  プルリクエストの CI は、同じテストを要素 3 個まで調べ、抜き取らない（[ADR 0304](./docs/adr/0304-check-the-keep-options-up-to-4-elements-and-draw-5-every-night.md)）。
- 行分割の段：golem-layout のテスト（「line breaking invariants on every small input」）を `GOLEM_ENUM_LINES_DEPTH=3` と `GOLEM_ENUM_LINES_SAMPLES=5000000` で走らせる。
  本文の中のコードの 18 の部品の並びも、同じ部品の数と行の幅まで調べる（抜き取らない）。
  プルリクエストの CI は、同じテストを部品 2 個まで 4 字までの行で調べ（正規形と縦組みと R7 は部品 1 個まで。行の調整の `"balanced"` と伸びの上限は毎晩だけ）、抜き取らない（[docs/adr/0209](./docs/adr/0209-line-breaking-invariants-by-exhaustive-small-inputs.md)、コードの並びは [golem-layout ADR 0034](./docs/golem-layout/adr/0034-line-breaks-between-japanese-characters-in-inline-code.md) と [golem-layout ADR 0045](./docs/golem-layout/adr/0045-break-inline-code-after-hyphens-and-full-stops-to-avoid-loose-lines.md)）。
  `[lang fr]` の区間と R1 は、[ADR 0276](./docs/adr/0276-hyphenate-words-by-the-patterns-of-their-language.md) と [ADR 0282](./docs/adr/0282-record-what-the-implementations-of-adr-0274-and-0275-decided.md) が毎晩に移したものを、[ADR 0286](./docs/adr/0286-leave-the-start-of-cabal-out-of-the-time-of-an-enumeration-area.md) の量り方でプルリクエストに戻した。
- 引用の印の段と語の途中の境目の段：引用の印の段は、golem-layout のテスト（「GOLEM_ENUM_CITE_DEPTH」）を `GOLEM_ENUM_CITE_DEPTH=3` で走らせ、語の途中の境目の段は、golem-layout のテスト（「GOLEM_ENUM_JOINED_DEPTH」）を `GOLEM_ENUM_JOINED_DEPTH=3` で走らせる。
  プルリクエストの CI は、どちらも部品 2 個まで調べる（[docs/adr/0277](./docs/adr/0277-keep-the-page-label-of-a-citation-mark-with-its-value.md)、[ADR 0280](./docs/adr/0280-breaks-between-latin-word-boxes-follow-the-joined-word.md)）。
- 行の調整の順の段：golem-layout のテスト（「order of JLReq」の「every small input」）を `GOLEM_ENUM_LINES_DEPTH=3` で走らせ、三つの順を 5 字までの行で調べる。
  プルリクエストの CI も、三つの順を 4 字までの行で調べる。[ADR 0286](./docs/adr/0286-leave-the-start-of-cabal-out-of-the-time-of-an-enumeration-area.md) の量り方でプルリクエストに戻した（[docs/adr/0278](./docs/adr/0278-use-the-places-of-line-adjustment-in-the-order-of-jlreq.md)）。
- 表の列の幅の段：golem-layout のテスト（「GOLEM_ENUM_TABLE_DEPTH」）を `GOLEM_ENUM_TABLE_DEPTH=5` で走らせ、`columnWidths` を幅 5 まで列 4 個まで、`tableColumnWidths` を幅 4 まで列 3 個まで調べる。
  プルリクエストの CI は、それぞれ幅 4 まで列 3 個までと、幅 3 まで列 3 個まで調べる（[ADR 0295](./docs/adr/0295-column-widths-of-tables-by-exhaustive-small-inputs.md)）。

2026-11-10 にブランチで起動した四回の実行（[ADR 0281](./docs/adr/0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md) の 8）では、段の時間は次のとおりだった。

| 段 | 一回目 | 二回目 | 三回目 | 四回目 |
|---|---|---|---|---|
| 改ページ | 17 分 21 秒 | 12 分 18 秒 | 12 分 16 秒 | 12 分 19 秒 |
| 行分割 | 30 分 4 秒 | 20 分 45 秒 | 20 分 56 秒 | 25 分 49 秒 |
| 改行しない範囲 | 28 秒 | 20 秒 | 19 秒 | 20 秒 |
| 引用の印 | 5 分 11 秒 | 3 分 44 秒 | 3 分 45 秒 | 3 分 53 秒 |
| 境目 | 2 分 8 秒 | 1 分 30 秒 | 1 分 30 秒 | 1 分 54 秒 |
| 行の調整の順 | なし | なし | なし | 10 秒 |
| 時間を量る段を含めた和 | 55 分 42 秒 | 38 分 59 秒 | 39 分 8 秒 | 44 分 54 秒 |

四回とも、改ページの段では保持の設定の列挙が I6 の違反で落ちた。
行分割の段では、初めの三回は抜き取りが I4 の違反で 1 分ほどで止まった。
四回目は、その違反を直した後で、すべて通った。
段の和は、どの回も 60 分に収まった。
時間を量る段の和（プルリクエストの設定）は、ランナーによって 22.48 秒から 28.91 秒であった。

保持の設定の段を分けた後（[ADR 0304](./docs/adr/0304-check-the-keep-options-up-to-4-elements-and-draw-5-every-night.md)）に、ブランチで毎晩の設定のまま起動した四回の実行（42837473529、42848615465、42859556574、42869707002）では、段の時間は次のとおりだった。

| 段 | 一回目 | 二回目 | 三回目 | 四回目 |
|---|---|---|---|---|
| 時間を量る段 | 34 秒 | 35 秒 | 31 秒 | 24 秒 |
| 改ページ | 9 分 43 秒 | 9 分 46 秒 | 8 分 25 秒 | 6 分 46 秒 |
| 保持の設定 | 2 分 18 秒 | 2 分 20 秒 | 2 分 1 秒 | 1 分 38 秒 |
| 行分割 | 36 分 59 秒 | 37 分 22 秒 | 32 分 55 秒 | 26 分 12 秒 |
| 行の調整の順 | 15 秒 | 15 秒 | 14 秒 | 11 秒 |
| 改行しない範囲 | 14 秒 | 14 秒 | 12 秒 | 25 秒 |
| 引用の印 | 6 分 9 秒 | 6 分 12 秒 | 5 分 46 秒 | 4 分 30 秒 |
| 境目 | 4 分 10 秒 | 4 分 14 秒 | 3 分 43 秒 | 2 分 57 秒 |
| 表の列の幅 | 13 秒 | 12 秒 | 11 秒 | 9 秒 |
| 和 | 60 分 35 秒 | 61 分 10 秒 | 53 分 58 秒 | 43 分 12 秒 |

初めの三回は、[ADR 0305](./docs/adr/0305-leave-soft-hyphens-in-or-next-to-a-no-break-range-out-of-i8.md) を入れる前のコミットで、改行しない範囲の段が I8 の違反で落ちた。
四回目は、ADR 0305 を入れた後のコミットで、すべて通った。
保持の設定の段の中央値は 2 分 10 秒、段の和の中央値は 57 分 17 秒で、60 分に収まった。
一回目と二回目は、行分割の段が 37 分ほどかかり、和が 60 分を超えた。

`enum.yml` が落ちたら、表示された最も小さい入力と、実行の URL と head のコミットを添えて issue を立てる。
手元では `GOLEM_ENUM_DEPTH=5 GOLEM_ENUM_PAGINATION_SAMPLES=5000000 cabal test golem-layout-test --test-option=-p --test-option='/pagination invariants/&&/every input/&&!/keep options/'`、`GOLEM_ENUM_KEEP_DEPTH=4 GOLEM_ENUM_KEEP_SAMPLES=5000000 cabal test golem-layout-test --test-option=-p --test-option='/pagination invariants/&&/keep options/&&/every input/'`、`GOLEM_ENUM_LINES_DEPTH=3 GOLEM_ENUM_LINES_SAMPLES=5000000 cabal test golem-layout-test --test-option=-p --test-option='/line breaking invariants on/'` で同じ入力を調べる。

##### `browser.yml`

`browser.yml` の `prepare`、`chromium`、`safari` は、`scripts/ci/race-needed.sh` に `browser.yml` を渡して判定して走る（[docs/adr/0234](./docs/adr/0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md)、[docs/adr/0239](./docs/adr/0239-decide-the-conditions-of-the-outlined-figure-check-and-the-punctuation-of-figure-sources.md)）。
ビルドはしない。

- `prepare`：成果物 `golem-wasm`、`wasm-native-list`、`manual`、`manual-dev`、`golem-linux-x86_64` のそろった最新の成功した `main` の `ci.yml` の実行からそれらを取り、`scripts/browser/fixtures/` と figures の fixture の HTML を組んで、成果物 `browser-inputs` として上げる。
  偽の WebDriver のサーバーに対する `scripts/browser/test/unit.test.mjs` もここで走る。
- `chromium`（`ubuntu-24.04`）：版と SHA-256 で固定した `chrome-headless-shell` と Deno と wasmtime の C API で、次の検査を走らせる（[docs/adr/0238](./docs/adr/0238-build-golem-wasm-with-the-standard-exception-handling-and-run-it-under-wasmtime.md)）。
  HTML の検査、輪郭の SVG の文字の検査（この検査だけ `--font-render-hinting=none` で起動し、起動の引数を版の表に書く）、`scripts/browser/test/` の手で書いたページの検査、Deno、wasmtime の C API（`scripts/wasm/run-wasmtime.sh`）、Chromium の `golem.wasm` の一覧の比べ合わせと、`run-wasmtime.c` と `run.mjs` の `call` が同じ結果の枠を返すことの確かめと、入力の枠の上限を 64 バイトにしてビルドした `run-wasmtime.c` が 65 バイトの入力の枠を `golem_alloc` の前に終了コード 3 で止めることの確かめである（[docs/adr/0289](./docs/adr/0289-bound-the-input-and-the-memory-of-the-wasmtime-host.md)）。
- `safari`（`macos-15`）：`sudo safaridriver --enable` の後に、同じ検査を Safari で走らせ、macOS、像、Safari、`browserVersion` の版の表をジョブの要約に書く。
  輪郭の SVG の文字の検査では縦書きの文字列を判定に含めず、その数と差の最大を要約に書き、横書きの文字列は中心と大きさの差の上限を CSS の 8 画素にする。
  Safari の版は固定しない。

どの検査も前の検査の失敗で止まらず、`safari` の失敗も再実行も無視もしない。

##### `wasm-tests.yml`

`wasm-tests.yml` の `prepare`、`native`、`wasm`、`skips` は、`scripts/ci/race-needed.sh` に `wasm-tests.yml` を渡して判定して走り、`golem.wasm` のパッケージのテストのスイート（`scripts/ci/test-suites.sh wasm`）を wasm32 とネイティブの両方で走らせる（[docs/adr/0293](./docs/adr/0293-run-the-test-suites-of-the-packages-of-golem-wasm-on-wasm32-every-night.md)）。
`ci.yml` のキャッシュを戻すだけで、保存しない。

- `wasm`：スイートを `cabal.project.wasm-tests` で wasm32 に向けて組み、`scripts/wasm/run-suite.sh` で一つずつ Node の `node:wasi` で走らせる（`scripts/wasm/run-tests.mjs`）。
  スイートごとに空の `/tmp` を用意して後に消し、除外するテストの式が 65,536 バイトを超えれば、スイートを起動せずに失敗する（[docs/adr/0307](./docs/adr/0307-preopen-a-temporary-directory-at-tmp-for-the-wasm-tests.md)）。
  `scripts/wasm/test-failures.tsv` のテストを除いたテストが通るか SKIP になること、一覧のテストがそれだけで走らせると落ちることを確かめ、スイートごとの時間と OK、FAIL、SKIP の数をジョブの要約に書く。
  組めなかったスイートも要約に書き、ジョブを失敗にする。
- `native`：同じスイートをネイティブの GHC で、外部の道具（qpdf、cddl、pdfinfo、pdftoppm）を `PATH` に置かずに走らせる。
- `skips`：wasm32 の SKIP がネイティブの SKIP に含まれること、一覧のテストがネイティブで通ることを `scripts/wasm/check-skips.sh` で確かめる。

#### リリースのワークフロー（release.yml）

`.github/workflows/release.yml` は、`v` で始まるタグの push と `workflow_dispatch` で動く（[docs/adr/0004](./docs/adr/0004-binary-distribution-and-release.md)）。
`workflow_dispatch` では、配布物を作って検査し、そのコミットのリリースノートを書くところまでを行い、リリースは作らない。
リリースノートを書く AI の API キーは、リポジトリの秘密情報 `ANTHROPIC_API_KEY` に置く。

- `ci`：`ci.yml` を再利用可能なワークフローとして呼ぶ。
  呼び出したワークフローは呼ぶジョブの権限までしか持てないので、`ci.yml` のジョブが求める権限（`visual` の `actions: read` と、`main` への push でだけ走る `caches` の `actions: write`）を与える。
  `actions: write` を受け取るのは `caches` だけで、タグの push では `caches` は走らない。
  ほかのジョブが `actions: write` を求めないことと、ジョブが求めない権限を与えないことは、`scripts/ci/test.sh` が確かめる（[ADR 0287](./docs/adr/0287-keep-actions-write-of-the-ci-call-in-release-yml-for-the-caches-job-alone.md)）。
- `version`：`scripts/release/check-version.sh` で `VERSION` とタグを検査し、タグのコミットが `main` に含まれることを確かめる。
  タグの push では、`scripts/release/check-patch.sh` で、タグが patch（`X` と `Z` が 1 以上）かを決め、patch なら基準のリリース（同じ `X.Y` のプレリリースでない最新のタグ）を `patch` ジョブに渡す。
  patch なのに基準のリリースがなければ失敗する（[docs/adr/0174](./docs/adr/0174-compatibility-promises-for-1-0.md)、[docs/adr/0212](./docs/adr/0212-patch-release-check-on-the-inputs-of-the-previous-release.md)）。
- `build`：Linux の二つのアーキテクチャでは Alpine のコンテナの中で musl に静的にリンクして、macOS では `macos-15` でビルドし、アーカイブを作る。
  `THIRD_PARTY_LICENSES/` を決めたリンクマップも成果物として上げる。
- `smoke`：アーカイブを別のランナーと、`alpine` と `debian:stable-slim` のコンテナの中で展開して動かす。
  `golem new` の雛形と sample のビルドが diagnostics を一つも出さない（notice も含む）こと、`golem new --no-fonts` が置くべきフォントの一覧のほかに何も書かないことを確かめる（[docs/adr/0080](./docs/adr/0080-release-smoke-checks-diagnostics.md)）。
- `wasm`：`ci.yml` の `wasm` と同じ手順で `golem.wasm` を組み、`scripts/wasm/run.mjs` の検査を通し、x86-64 の Linux のアーカイブの `golem` と PDF と diagnostics が一致することを `scripts/wasm/compare.sh` で確かめてから、`scripts/release/package-wasm.sh` で `golem-<タグ>-wasm32-wasi.tar.gz`（`golem.wasm`、`LICENSE`、`THIRD_PARTY_LICENSES/`、`README`）を作る。
  `THIRD_PARTY_LICENSES/` は `scripts/release/licenses.sh --wasm` が作り、wasm の GHC の GMP の版は `scripts/release/gmp-version.sh` を `GMP_GHC=wasm32-wasi-ghc` で動かして調べる（[docs/adr/0199](./docs/adr/0199-pdf-typesetting-as-wasm-reactor.md)）。
  作ったアーカイブは、`scripts/release/check-wasm-archive.sh` で、`golem.wasm`、`LICENSE`、`README`、[ADR 0199](docs/adr/0199-pdf-typesetting-as-wasm-reactor.md) の 8 の挙げる文書と `.sha256` を持つことを確かめる（[docs/adr/0230](./docs/adr/0230-check-the-release-workflow-and-ci-history-by-scripts.md)）。
- `patch`：タグが patch のときだけ、x86-64 の Linux のアーカイブの `golem` で、基準のリリースの木の見た目の回帰テストの入力を組み、その木の参照と比べ、基準のリリースに `scripts/determinism/hashes.txt` があれば PDF の行を除いて比べる（`scripts/release/check-patch-output.sh`）。
  入力は基準のリリースのものなので、patch の前にマニュアルや fixture の原稿を直しても結果は変わらない。
  `release` ジョブはこのジョブを待つ（[docs/adr/0212](./docs/adr/0212-patch-release-check-on-the-inputs-of-the-previous-release.md)）。
- `determinism`：三つの配布物と CI のビルドの、`scripts/determinism.sh` の出力を比べる。
- `notes`：`mise.toml` で固定した Claude Code を、版と SHA-256 で固定した mise（[docs/adr/0085](./docs/adr/0085-pin-mise-version-in-workflows.md)）で `jdx/mise-action` を使って入れ、`scripts/release/write-notes.sh` でリリースノートを書き、`notes.md` を成果物として上げる。
  権限は `contents: read` だけである（[docs/adr/0044](./docs/adr/0044-release-workflow-hardening.md)）。
- `release`：タグの push のときだけ、下書きのリリースを作る。
  添えるのは、`SHA256SUMS`、来歴の証明、GMP のソース、x86-64 の Linux の配布物で組んだ二つのマニュアルの PDF と HTML（`golem-manual-<タグ>` と `golem-dev-manual-<タグ>`）、コミットした見本のプラグイン（`plugins/wasm/*.wasm`、[docs/adr/0106](./docs/adr/0106-sample-plugins-in-rust.md)）、そのライセンスの文書のアーカイブ（`golem-plugins-licenses-<タグ>.tar.gz`、[docs/adr/0133](./docs/adr/0133-third-party-licenses-of-sample-plugins.md)）、`notes` が書いたリリースノートである。
  その後に、下書きの `SHA256SUMS` を下ろして `dist/` のファイルと照らし、上げたアーカイブのそれぞれに `gh attestation verify` を走らせる（[docs/adr/0230](./docs/adr/0230-check-the-release-workflow-and-ci-history-by-scripts.md)）。
  Node と Claude Code は入れない。

## License

[MIT](./LICENSE) © tett23

ただし、二つのマニュアルの `manual/` と `manual-dev/`（`fonts/` を除く）と、そこから組んだ PDF と HTML は、[CC0 1.0](./manual/LICENSE) で公開している（[docs/adr/0082](./docs/adr/0082-manuals-under-cc0.md)）。
マニュアルの PDF に埋め込んだフォントと、HTML と一緒に配るフォントは、SIL Open Font License 1.1 のままである。
