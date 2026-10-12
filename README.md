# golem

## Overview

Golem は、コマンドラインと CI で動く組版システムである。
原稿は `.gm` のテキストで書き、同じ入力から常に同じバイト列の PDF、EPUB、HTML、テキストを出力する。
仕様は [docs/specifications.md](./docs/specifications.md) と [docs/markup.md](./docs/markup.md) にある。
用語は [docs/glossary.md](./docs/glossary.md) にまとめている。

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
| `golem new DIR [--language ja\|en] [--no-fonts]` | プロジェクトを作る。版面の設定と、配布元から取得したフォントを含む |
| `golem plugin lock` | マニフェストのプラグインを取得し、ハッシュを `plugins.lock` に書く |
| `golem plugin fetch` | `plugins.lock` のとおりにプラグインを取得してキャッシュに置く |
| `golem build [--target html\|epub\|text\|pdf] [--profile dev\|prod]` | 出力を `build/` に書く。`--target` を省くと四つのターゲットをすべて作る |
| `golem check` | 出力を書かずに検査する |
| `golem lint` | lint の規則を適用する |
| `golem fmt [--check] [FILE...]` | 原稿を整形する |
| `golem lsp` | 標準入出力で LSP を話す。位置の単位は、クライアントが対応していれば UTF-8、そうでなければ UTF-16 を使う |
| `golem inspect FILE --as cst\|ast\|ir` | 構文木と IR を表示する |
| `golem --version` | 版を表示する（例：`golem 0.1.0`） |

PDF を出力するには、`style.toml` の `[fonts.body]` に和文と欧文のフォントのファイルを書く。
PDF/X-4 の適合は Golem 自身の検査で確かめているが、入稿する前には商用のプリフライト（Acrobat や pdfToolbox など）で確認する。
フォントの OS/2 の `fsType` が埋め込みを禁じている場合はエラーになる。
ビルドはプラグインをキャッシュからだけ読み、ネットワークに接続しない。
診断は `--format json` で JSON にできる。
終了コードは、成功が 0、エラーの診断があれば 1、使い方の誤りが 2 である。

## Development

変更の進め方と約束ごとは [CONTRIBUTING.md](./CONTRIBUTING.md) にある。

### Git フックの有効化

クローン直後に、リポジトリ同梱の Git フックを有効にする。

```bash
git config core.hooksPath .githooks
```

フックは [adr-guard](https://github.com/tett23/adr-guard) を呼び出すので、あらかじめインストールしておく。
`.githooks/pre-commit` は、コミット済みの ADR（`docs/adr/` と `docs/<モジュール>/adr/` の配下）への変更、削除、リネームを含むコミットを拒否する。
例外は `ステータス:` で始まる行で、この行だけは変更できる。
ADR はコミット後に変更しない規約であり、変更が必要な場合は新しい連番の ADR を作成する（詳細は [CLAUDE.md](./CLAUDE.md)）。
`core.hooksPath` はクローンごとのローカル設定であり、リポジトリには保存されないため、クローンのたびに実行が必要になる。
同じ検査は CI の `adr` ジョブでも行う。

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

パーサーは `modules/golem-parser/grammar/Golem.peg` から生成し、生成物をコミットする。
文法を変えたら生成し直す。

```bash
scripts/gen-parser.sh
```

テストのうち CDDL のスキーマへの適合の検査は、Rust の `cddl` クレートの CLI（0.10.7）を使う。
`PATH` にあるか `GOLEM_CDDL` で指定した場合だけ実行され、CI では必ず実行する。

```bash
cargo install cddl --version 0.10.7 --locked
```

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

### 整形と検査

Haskell のコードは fourmolu 0.21.0.0 で整形し（設定は `fourmolu.yaml`）、hlint 3.10 で検査する。
どちらも CI の `format` ジョブで検査する。

### CI

`.github/workflows/ci.yml` に次のジョブがある。

| ジョブ | 内容 |
|---|---|
| `adr` | コミット済みの ADR が変更されていないことを検査する |
| `build` | x86-64 と aarch64 の Linux でビルドとテストを行い、生成したパーサーが文法と一致すること、EPUB が epubcheck を通ることを確かめる |
| `determinism` | 決まった入力（`scripts/determinism.sh`）の出力のハッシュを、二つのアーキテクチャで比べる |
| `release-scripts` | `VERSION` と全パッケージの版の一致を検査し、`scripts/release/` のスクリプトのテスト（`scripts/release/test.sh`）を実行する |
| `format` | fourmolu と hlint で検査する |

`.github/workflows/release.yml` は、`v` で始まるタグの push と `workflow_dispatch` で動く（[docs/adr/0004](./docs/adr/0004-binary-distribution-and-release.md)）。
`workflow_dispatch` では、配布物を作って検査するところまでを行い、リリースは作らない。

| ジョブ | 内容 |
|---|---|
| `ci` | `ci.yml` を再利用可能なワークフローとして呼ぶ |
| `version` | `scripts/release/check-version.sh` で `VERSION` とタグを検査し、タグのコミットが `main` に含まれることを確かめる |
| `build` | Linux の二つのアーキテクチャでは Alpine のコンテナの中で musl に静的にリンクして、macOS では `macos-15` でビルドし、アーカイブを作る |
| `smoke` | アーカイブを別のランナーと、`alpine` と `debian:stable-slim` のコンテナの中で展開して動かす |
| `determinism` | 三つの配布物と CI のビルドの、`scripts/determinism.sh` の出力を比べる |
| `release` | タグの push のときだけ、`SHA256SUMS`、来歴の証明、GMP のソース、AI が書いたリリースノートと共に下書きのリリースを作る |

リリースノートを書く AI の API キーは、リポジトリの秘密情報 `ANTHROPIC_API_KEY` に置く。

## License

[MIT](./LICENSE) © tett23
