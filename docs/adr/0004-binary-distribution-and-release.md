# ADR 0004: 実行ファイルの配布とリリースの自動化

ステータス: 採択→リリースノートを書くジョブ、Claude Code の入れ方、ノートのリンクの検査は [ADR 0044](0044-release-workflow-hardening.md)

## 文脈

[ADR 0001](0001-haskell-workspace-and-ci.md) は、バイナリの配布とリリースの自動化を「最初に配布できる機能が揃った段階で、別の ADR で扱う」とした。
[仕様書](../specifications.md)の「v2 以降に回した事項」にも同じ項目がある。
今の Golem は `golem new` から `golem build` までで四つのターゲットを出力できるので、この項目を前倒しする。

利用者が `golem` を手に入れる方法は、今はソースからのビルドだけである（[README](../../README.md) の Installation の節）。
ビルドには GHC 9.10.3、cabal-install 3.16.1.0、C と C++ のコンパイラ、wasmtime の C API の取得が要り、初回のビルドには長い時間がかかる。
CI で Golem を使いたい利用者も、毎回この手順を踏むことになる。

現状の実行ファイルについて、コードとビルドの結果から次のことがわかっている。

- HarfBuzz と FreeType はソースを同梱して静的にリンクする（[golem-font ADR 0001](../golem-font/adr/0001-shaping-and-metrics.md)）。zlib は `zlib-clib` の同梱版を使う。wasmtime は `scripts/fetch-wasmtime.sh` が取得した `libwasmtime.a` だけを置き、静的にリンクする（[golem-plugin ADR 0001](../golem-plugin/adr/0001-wasm-host-and-abi.md)）。
- `scripts/fetch-wasmtime.sh` が対応するのは、macOS の arm64、Linux の x86-64 と aarch64 の三つで、どれも glibc 向けの配布物である。
- macOS の arm64 でビルドした実行ファイルは約 176MB で、`otool -L` で見える依存は `libSystem`、`libiconv`、`libcharset`、`libffi`、`Security.framework` だけである。GMP は実行ファイルの中に静的にリンクされている（`nm` で `___gmpn_add` などが見える）。
- Linux では golem-font が `stdc++` を、golem-plugin が `pthread`、`dl`、`m` を動的にリンクする（各 cabal ファイルの `extra-libraries`）。GHC の glibc 向けの配布物は GMP と libffi をシステムの共有ライブラリとしてリンクする構成だが、CI でビルドした実行ファイルの `ldd` の結果はまだ確かめていない。
- HTTPS の取得（`Golem.Plugin.Lock.httpsFetcher`）は、`http-client-tls` の `newTlsManager` を使う。TLS は Haskell の `tls` で実装されていて、OpenSSL には依存しない。ルート証明書は `crypton-x509-system` 1.8.0 が読む。Linux では `/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem`、`/etc/ssl/certs/` などの決まったパスを、macOS では `security find-certificate` でシステムのキーチェーンを読む。どちらも環境変数 `SSL_CERT_FILE` と `SSL_CERT_DIR` が優先される。証明書が一つも見つからなくても、空のストアのまま処理が進む。
- golem-cli には `--version` がない。版の文字列は、`golem-driver` の `Golem.Driver.Pdf` に `"golem-0.1.0.0"` と直に書かれ、インスタンス ID の計算に使われている。全パッケージの cabal ファイルの `version` は `0.1.0.0` である。
- 仕様書は「PDF の Producer には Golem の版を書く」としているが、`Golem.Pdf.Writer` は Producer を書いていない。

## 実装すること

### 対象のプラットフォーム

次の三つの実行ファイルを配布する。

| 名前 | OS とアーキテクチャ | ビルドするランナー | リンク |
|---|---|---|---|
| `x86_64-linux` | Linux の x86-64 | `ubuntu-24.04` の上の Alpine のコンテナ | musl で完全に静的 |
| `aarch64-linux` | Linux の aarch64 | `ubuntu-24.04-arm` の上の Alpine のコンテナ | musl で完全に静的 |
| `aarch64-macos` | macOS の arm64 | `macos-15` | OS 標準のライブラリだけに動的 |

名前の付け方は、`scripts/fetch-wasmtime.sh` が使う wasmtime の配布物の名前（`aarch64-macos` など）に合わせる。
ランナーには `macos-latest` のような動く名前を使わず、版の付いた名前を書く。
`macos-latest` が指すランナーが変わると、リリースのビルドが黙って変わるためである。

Windows と x86-64 の macOS は対象にしない（「実装しないこと」）。

### Linux を musl で完全に静的にリンクする

Linux の実行ファイルは、Alpine Linux の上で musl に対して `cabal build --enable-executable-static` でビルドし、共有ライブラリへの依存を一つも持たせない。
glibc に動的にリンクする案と、glibc に静的にリンクする案は採らない。

- glibc に動的にリンクすると、ビルドした環境の glibc より古い glibc では動かない。CI と同じ `ubuntu-24.04` でビルドすると glibc 2.39 が必要になり、Debian 12（glibc 2.36）や Ubuntu 22.04（glibc 2.35）では起動できない。加えて、GMP と libffi が共有ライブラリとしてリンクされていれば、それらが入っていない環境でも起動できない。
- glibc に静的にリンクすると、名前解決の `getaddrinfo` が実行時に NSS のモジュールを `dlopen` で読もうとし、ビルドした環境と同じ版の glibc がなければ失敗しうる。`golem new` と `golem plugin` はホスト名を解決するので、この失敗は機能の失敗になる。musl の名前解決は libc の中で完結するので、この問題がない。

GHC は 9.10.3 の Alpine 向けの公式の配布物（`ghc-9.10.3-x86_64-alpine3_18-linux` と `ghc-9.10.3-aarch64-alpine3_18-linux`、ghcup のメタデータに載っている）を ghcup で入れる。
Alpine のコンテナのイメージは、タグではなくダイジェストで固定する。
GitHub Actions の JavaScript のアクションは、aarch64 の Alpine のコンテナの中では動かないので、ジョブの `container:` は使わない。
リポジトリの取得はランナーの上で行い、ビルドは `docker run` で `scripts/release/build-linux.sh` をコンテナの中で実行する。

wasmtime の C API は、musl 向けのものが要る。
glibc 向けの `libwasmtime.a` は glibc のシンボルの版を参照するので、musl にはリンクできない。

- `scripts/fetch-wasmtime.sh` に、musl を検出する分岐（`/etc/alpine-release` の有無、または `ldd --version` の出力に `musl` が含まれるか）と、`x86_64-musl` と `aarch64-musl` の行を足す。
- 実装の最初に、wasmtime 49.0.2 のリリースに `wasmtime-v49.0.2-x86_64-musl-c-api.tar.xz` と `wasmtime-v49.0.2-aarch64-musl-c-api.tar.xz` があるかを確かめる。あれば、glibc 向けと同じく SHA-256 を固定して取得する。
- ないアーキテクチャについては、wasmtime の `v49.0.2` のタグをコミットのハッシュで確かめて取得し、`cargo build --release --locked -p wasmtime-c-api --target <アーキテクチャ>-unknown-linux-musl` で `libwasmtime.a` を作る。版は 49.0.2 のまま変えないので、[CONTRIBUTING.md](../../CONTRIBUTING.md) の「版を上げるときは ADR を書く」には当たらない。

静的ライブラリのパッケージ（GMP、libffi、libstdc++ の静的ライブラリを含むもの）は `apk add` で入れ、一覧を `scripts/release/build-linux.sh` に書く。
Alpine のパッケージの版は、イメージのダイジェストを固定しても `apk add` の時点で変わりうるので、入れたパッケージの版を `apk info -v` で `BUILDINFO`（後述）に書き残す。

### macOS の実行ファイル

- `macos-15` のランナーで、今の README の手順のとおり `cabal build exe:golem` でビルドする。
- 環境変数 `MACOSX_DEPLOYMENT_TARGET` を `14.0` にしてビルドし、macOS 14 以降で動く実行ファイルにする。
- 署名と公証（notarization）はしない（「実装しないこと」）。arm64 の macOS は署名のない実行ファイルを起動しないが、リンカーがアドホックの署名を付けるので、この条件は満たされる。
- `strip` の後に、`codesign --force --sign - golem` でアドホックの署名を付け直す。`strip` が署名の対象のバイト列を変えるので、付け直さないと起動を拒まれうるためである。

### デバッグ情報とシンボル

三つの実行ファイルとも `strip` でシンボルとデバッグ情報を除く。
GHC は既定では DWARF を出さないので、除かれるのは主にシンボルの表である。
`strip` の前と後の大きさを、ワークフローのログと `BUILDINFO` に記録する。
`-split-sections` のような、ビルドの設定を変えて大きさを減らす方法は採らない（「実装しないこと」）。

### 版番号

- Golem の版は `X.Y.Z` か、それにプレリリースの識別子を付けた `X.Y.Z-<識別子>`（例：`0.1.0-rc1`、`0.1.0-rc.2`）で表す。識別子は `[0-9A-Za-z.-]+` とし、Semantic Versioning のプレリリースの書き方に合わせる。1.0.0 までは、原稿の記法、CLI、出力の互換性を壊す変更で `Y` を、それ以外の変更で `Z` を上げる。
- 版の正本は、リポジトリの根に置く `VERSION` ファイルの一行（例：`0.1.0-rc1`）とする。cabal の `version` は数の並びしか書けず、識別子を表せないためである。
- `modules/*/*.cabal` の `version` は、全パッケージで同じ値にし、`VERSION` の識別子を除いた `X.Y.Z` と一致させる。モジュールを別々に Hackage に出すことはないので、版を分ける理由がない。最初のリリースに合わせて、全パッケージの `version` を `0.1.0.0` から `0.1.0` に変える。
- golem-driver に `Golem.Driver.Version` を足し、`golemVersion :: Text` を公開する。値は `VERSION` の内容を Template Haskell でコンパイルの時点に埋め込んだものとし、`addDependentFile` で `VERSION` の変更に追随させる（英語のハイフネーションのパターンを埋め込む `Golem.Layout.Hyphenation.EnUs` と同じ方式）。版の文字列はソースだけで決まり、ビルドのときの Git の状態に左右されない。
- `Golem.Driver.Pdf` のインスタンス ID の計算の `"golem-0.1.0.0"` を、`"golem-" <> golemVersion` に置き換える。版の文字列が変わるので、PDF のインスタンス ID は変わる。[ADR 0002](0002-determinism.md) のとおり、Golem の版は入力の一部であり、版が変われば出力が変わってよい。
- golem-cli に `--version` を足す。`optparse-applicative` の `infoOption` で、`golem ` に `golemVersion` を続けた一行（例：`golem 0.1.0-rc1`）を標準出力に書き、終了コード 0 で終える。ヘルプの説明は「版を表示する」とする。`simpleVersioner` は英語の説明を出すので使わない（[golem-cli ADR 0004](../golem-cli/adr/0004-usage-error-exit-code.md)）。
- `-V` のような短い名前は付けない。
- プレリリースを出すときは、`VERSION` を `0.1.0-rc1` のように書き換えるプルリクエストをマージしてから、同じ名前のタグ（`v0.1.0-rc1`）を付ける。`v0.1.0-rc1` からビルドした `golem --version` は `golem 0.1.0-rc1` を出し、正式のリリースの `golem 0.1.0` と区別できる。

### タグとリリースの判定

`scripts/release/check-version.sh` を足す。

- 引数なしでは、`VERSION` の形（`^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$`）と、`modules/*/*.cabal` の `version` がすべて `VERSION` の `X.Y.Z` と同じであることを検査し、`version=<VERSION の内容>` を標準出力に書く。
- 引数にタグを渡すと、さらにタグの形を検査する。`^v[0-9]+\.[0-9]+\.[0-9]+$` はリリース、`^v[0-9]+\.[0-9]+\.[0-9]+-[0-9A-Za-z.-]+$` はプレリリースとし、`prerelease=false` か `prerelease=true` を書く。どちらにも当たらないタグ（`v0.1`、`0.1.0`、`v0.1.0+build` など）はエラーとする。
- タグから `v` を除いたものが `VERSION` の内容と一致しなければエラーとする。識別子も含めて比べる。
- 出力の形は `key=value` の行とし、ワークフローではそのまま `$GITHUB_OUTPUT` に追記する。
- エラーは標準エラー出力に一行で書き、終了コードを 1 にする。

### リリースのワークフロー

`.github/workflows/release.yml` を足す。

起動の条件は、`v*` のタグの push と `workflow_dispatch` の二つとする。
`workflow_dispatch` では配布物を作って検査するところまでを行い、GitHub Releases には何も作らない。

ワークフローの既定の `permissions` は `contents: read` とし、書き込みの権限は `release` ジョブだけに与える。
アクションの版は、[ADR 0001](0001-haskell-workspace-and-ci.md) と [CONTRIBUTING.md](../../CONTRIBUTING.md) の方針のとおり、Node 24 以降で動く最新のメジャー版を使い、今の `ci.yml` に合わせる（`actions/checkout@v7`、`actions/cache@v6`、`actions/upload-artifact@v7`、`actions/download-artifact@v8`、`haskell-actions/setup@v2`）。
GitHub Releases の作成にはアクションを使わず、ランナーに入っている `gh` を使う。
アクションを一つ減らせば、その版を追う手間と、第三者のコードに書き込みの権限を渡すことの両方がなくなるためである。

ジョブは次のとおりとする。

1. `ci`：`.github/workflows/ci.yml` を再利用可能なワークフローとして呼ぶ。`ci.yml` の `on:` に `workflow_call:` を足す。リリースの前に、CI と同じビルド、テスト、決定性の検査を通すためである。
2. `version`：`scripts/release/check-version.sh` を実行する。タグの push では、タグを引数に渡し、さらに `git merge-base --is-ancestor "$GITHUB_SHA" origin/main` でタグのコミットが `main` に含まれることを確かめる。ブランチの上のコミットにタグを付けた誤りを、リリースの前に止めるためである。
3. `build`：上の表の三つのプラットフォームで実行ファイルを作り、`strip` し、アーカイブにしてワークフローの成果物として上げる。
4. `smoke`：アーカイブを、ビルドしたものとは別のランナーとコンテナで展開して動かす（「テスト設計」）。
5. `determinism`：`ci` ジョブの `determinism-ubuntu-24.04.txt` と、`smoke` ジョブが三つの配布物で作った `scripts/determinism.sh` の出力を比べ、すべてが一致することを確かめる。
6. `release`：タグの push のときだけ、ほかのジョブがすべて通った後に実行する。

`release` ジョブは次のことを行う。

- `permissions` は `contents: write`、`id-token: write`、`attestations: write` とする。
- 三つのアーカイブの SHA-256 を `sha256sum` の形式で `SHA256SUMS` に書く。
- `actions/attest-build-provenance` の、Node 24 以降で動く最新のメジャー版で、三つのアーカイブにビルドの来歴の証明を付ける。
- `scripts/release/notes.sh` で変更の一覧を作り、AI にリリースノートを書かせる（後述）。
- `gh release create "$TAG" --draft --verify-tag --title "$TAG" --notes-file notes.md` で、下書きのリリースを作り、三つのアーカイブと `SHA256SUMS` を添える。プレリリースのタグでは `--prerelease` を付ける。

リリースは下書きで作り、人がリリースノートを読んで、必要なら手で直してから公開する。
公開の操作はワークフローでは行わない。

### 配布物の形

アーカイブの名前は `golem-<タグ>-<プラットフォーム>.tar.gz`（例：`golem-v0.1.0-aarch64-linux.tar.gz`）とする。
展開すると `golem-<タグ>-<プラットフォーム>/` の一つのディレクトリができ、次のものが入る。

| パス | 内容 |
|---|---|
| `golem` | 実行ファイル |
| `LICENSE` | Golem の MIT ライセンス |
| `THIRD_PARTY_LICENSES/` | 実行ファイルに静的にリンクしたものと同梱したデータのライセンスの文書 |
| `BUILDINFO` | ビルドの情報 |

圧縮は gzip とする。
xz のほうが小さくなるが、最小構成のコンテナのイメージには xz の展開の道具がないことがあり、`tar` と gzip ならどの環境にもあるためである。

`THIRD_PARTY_LICENSES/` は `scripts/release/licenses.sh` で作る。
BSD のライセンスのように、バイナリの配布にも著作権の表示を求めるライセンスがあるためである。

- Hackage の依存は、`dist-newstyle/cache/plan.json` から `golem-` で始まらないパッケージの名前と版を `jq` で列挙し、cabal のパッケージのキャッシュ（`~/.cabal/packages/hackage.haskell.org/<名前>/<版>/<名前>-<版>.tar.gz`）からライセンスのファイルを取り出す。`source-repository-package` の peg-hs は、cabal が取得したソースのディレクトリから取り出す。
- GHC に付属するパッケージ（plan.json で `pre-existing` のもの）は、GHC の `share/doc/<アーキテクチャ>-ghc-9.10.3/<名前>-<版>/` から取り出す。GHC と RTS のライセンスも加える。
- C のライブラリと同梱のデータは、`modules/golem-font/cbits/harfbuzz/COPYING`、`modules/golem-font/cbits/freetype/LICENSE.TXT` と `docs/FTL.TXT`、`third_party/wasmtime/LICENSE`、zlib のライセンス、`modules/golem-layout/data/hyphenation/LICENSE-hyph-en-us.txt` を加える。FreeType は FTL を選び、FTL が求める謝辞を `THIRD_PARTY_LICENSES/README` に書く。
- GMP は LGPL-3.0 であり、三つの実行ファイルのどれにも静的にリンクされる。LGPL-3.0 と GPL-3.0 の文書を加え、リンクした GMP の版と、Golem のソースがタグの版で公開されていることを `THIRD_PARTY_LICENSES/README` に書く。リンクした GMP の版のソースのアーカイブを、リリースにも添える（gmplib.org の配布物を SHA-256 で検証して添える）。
- ライセンスのファイルが見つからない依存が一つでもあれば、スクリプトはエラーで終える。

`BUILDINFO` には、コミットのハッシュ、タグ、GHC と cabal-install の版、ランナーのイメージの名前と版（環境変数 `ImageOS` と `ImageVersion`）、Alpine のイメージのダイジェストと `apk info -v` の結果、wasmtime の配布物の名前、`strip` の前後の大きさを書く。

### リリースノート

リリースノートは AI が書き、人は公開の前に読んで、おかしなところがあれば手で直す。
変更を追加、変更、削除、修正に分ける判断は、コミットの題名からは機械的にできないが、プルリクエストの本文と ADR を読めば AI にも判断できるためである。

手順は次のとおりとする。

1. `scripts/release/notes.sh <前のタグ> <タグ>` が、AI に渡す材料として、英語の Markdown の変更の一覧を標準出力に書く（下の規則）。
2. `release` ジョブが Claude Code（`@anthropic-ai/claude-code` を npm で入れ、`claude -p` を非対話で実行する）に、変更の一覧、各プルリクエストの題名と本文（`gh pr view`）、範囲で追加された ADR の本文を渡し、[CONTRIBUTING.md](../../CONTRIBUTING.md) の「タグとリリース」の約束（英語、追加、変更、削除、修正などの見出し、各変更にプルリクエストと ADR の絶対リンク）に従ったリリースノートを書かせる。モデルは、そのときの最新で最も能力の高い Claude のモデルを、ワークフローに名前で固定して指定する。API キーはリポジトリの秘密情報 `ANTHROPIC_API_KEY` に置く。Node は `actions/setup-node` で最新の LTS を使う。
3. AI の出力を `scripts/release/check-notes.sh` で検査する。英語の見出しが一つ以上あること、`## Unsorted` が残っていないこと、リンクがすべて `https://github.com/tett23/golem/` で始まる絶対リンクであること、`notes.sh` が挙げたプルリクエストの番号がすべて現れることを確かめる。
4. 検査を通れば AI の出力を、AI の実行か検査に失敗すれば `notes.sh` の出力をそのまま、下書きのリリースのノートにする。後者の場合は、ジョブの要約に失敗の理由を書く。リリースそのものは止めない。

`notes.sh` の出力は次の規則に従う。

- 見出しは `## Added`、`## Changed`、`## Removed`、`## Fixed` と、まだ分類していない項目を置く `## Unsorted` とする。分類の済んでいない下書きを誤って公開しても、そのことがわかるようにするためである。
- `## Unsorted` には、`git log --first-parent --merges <前のタグ>..<タグ>` のうち `Merge pull request #N: 題名` の形のものを、`https://github.com/tett23/golem/pull/N` への絶対リンク付きで並べる。
- その範囲で追加された ADR（`docs/adr/*.md` と `docs/*/adr/*.md`）を、`https://github.com/tett23/golem/blob/<タグ>/<パス>` への絶対リンク付きで `## ADRs` に並べる。
- 前のタグは、`v` で始まるタグのうちコミットの順で直前のものを `git describe --tags --abbrev=0 --match 'v*' <タグ>^` で求める。最初のリリースでは前のタグがないので、リポジトリの最初のコミットからとする。
- 末尾に、`SHA256SUMS` での検証の方法と、`gh attestation verify` での来歴の検証の方法を書く。

### TLS のルート証明書が見つからない場合

配布した実行ファイルは、ルート証明書を同梱せず、OS の証明書のストアを読む。
最小構成のコンテナ（`debian:stable-slim` など）には ca-certificates が入っておらず、ストアが空になる。
今の実装では、そのとき TLS の検証の失敗として、原因のわかりにくいエラーになる。

- golem-plugin の `httpsFetcher` で、`System.X509.getSystemCertificateStore` を呼び、`listCertificates` が空なら、接続する前に `Left` を返す。メッセージは「TLS のルート証明書が見つかりません。ca-certificates を入れるか、SSL_CERT_FILE で証明書のファイルを指定してください」とする。
- `crypton-x509-system` と `crypton-x509-store` を golem-plugin の `build-depends` に加える。どちらも `http-client-tls` の推移的な依存としてすでに `cabal.project.freeze` で 1.8.0 に固定されているので、新しい依存は増えない。
- 新しい診断のコードは足さない。`httpsFetcher` の失敗は今も `Left` の文字列で返り、診断のコードを持たないためである。

### ドキュメント

- README の Installation の節を、GitHub Releases からの入手の手順に書き換える。アーカイブの取得、`SHA256SUMS` での検証、展開、`PATH` への配置を書く。macOS でブラウザから取得した場合は、`xattr -d com.apple.quarantine golem` が要ることを書く。ブラウザは取得したファイルに `com.apple.quarantine` の属性を付け、Gatekeeper は公証のない実行ファイルの初回の起動をこの属性によって拒むためである。`curl` で取得した場合は属性が付かない。
- README の Usage の表に `golem --version` を加える。
- README の CI の節に `release.yml` のジョブを加える。
- [仕様書](../specifications.md)の「v2 以降に回した事項」から「バイナリの配布とリリースの自動化」を除き、配布の節を設けてこの ADR へリンクする。
- [CONTRIBUTING.md](../../CONTRIBUTING.md) と `CONTRIBUTING.en.md` の「タグとリリース」に、版を上げるプルリクエスト、タグの付け方、下書きのリリースの編集と公開の手順を書く。

## 実装しないこと

- Windows の実行ファイル。今の CI は Windows でビルドもテストもしておらず、配布するなら先に CI の `build` と `determinism` に Windows を加える必要がある。加えて、Git の `core.autocrlf` が有効な Windows の環境では、取得した原稿の改行が CRLF になり、[markup.md](../markup.md) の規則でエラーになる。`scripts/` の検査も POSIX のシェルで書かれている。GHC 9.10.3 には Windows 向けの配布物（`x86_64-unknown-mingw32`）があり、`crypton-x509-system` も Windows の証明書のストアを読めるが、wasmtime の C API を GHC の mingw の道具でリンクできるかは確かめていない。Windows の利用者は、WSL2 の上で Linux の静的な実行ファイルを使える。
- x86-64 の macOS の実行ファイル。Apple は Mac を Apple Silicon に移し終えており、x86-64 の Mac のためにビルドと検査の系統を一つ増やす手間に見合わないと判断する。
- macOS の実行ファイルの署名（Developer ID）と公証。Apple Developer Program への登録と、証明書を CI の秘密情報として扱う運用が要る。さらに、公証には Hardened Runtime が要り、Hardened Runtime の下で wasmtime が実行時に機械語を生成するには `com.apple.security.cs.allow-jit` の entitlement が要る。この組み合わせで wasmtime が動くかを確かめる作業が別に要るので、別の ADR で扱う。
- Homebrew の tap と、`curl | sh` の形のインストール用のスクリプト。tap は別のリポジトリとリリースごとの formula の更新を要し、スクリプトはその内容を信用して実行してもらう経路を一つ増やす。GitHub Releases のアーカイブと `SHA256SUMS` があれば、どちらも後から足せる。
- 再現可能なビルド（同じタグから同じバイト列の実行ファイルが得られること）の保証。後の「再現可能なビルドと出力の決定性」の節を参照。
- `-split-sections` とリンカーの未使用のセクションの除去による大きさの削減。CI のビルドと設定が離れるので、効果を測ったうえで別に扱う。
- リリースの自動公開。AI が書いたリリースノートは、人が読んでから公開する。
- PDF の Producer への Golem の版の書き込み。仕様書にあるが未実装であり、`golemVersion` を使えば足せる。ただし PDF の出力を変える変更なので、この ADR には含めない。
- 古い版の実行ファイルの自動の削除や、自動の更新の確認。

## 再現可能なビルドと出力の決定性

二つは別の性質である。

出力の決定性（[ADR 0002](0002-determinism.md)）は、同じ版の Golem に同じ入力を与えれば、同じバイト列の出力が得られることをいう。
利用者が頼るのはこの性質であり、配布物でも保つ必要がある。
配布物は CI と異なる libc（musl）と異なる OS（macOS）でビルドするので、浮動小数点数の計算を libc の数学関数に頼る箇所があれば、出力が変わりうる。
そこで、リリースのワークフローの `determinism` ジョブで、三つの配布物と CI のビルドが同じ出力を出すことを確かめ、一致しなければリリースを止める。

再現可能なビルドは、同じソースから同じバイト列の実行ファイルが得られることをいう。
v1 ではこれを求めない。
`scripts/fetch-wasmtime.sh` が `cabal.project.local` に絶対パスを書くように、ビルドの環境のパスが実行ファイルに入りうること、Alpine のパッケージの版がビルドのたびに変わりうること、wasmtime の C API を配布物のまま使うことが理由である。
代わりに、`BUILDINFO` にビルドの環境を記録し、来歴の証明で「どのワークフローがどのコミットから作ったか」を検証できるようにする。

## テスト設計

### 版の表示（golem-cli のテスト）

`modules/golem-cli/test/Main.hs` に加える。
テストのスイートは golem-driver に依存させ、`golemVersion` を参照する。

- `golem --version` の終了コードが 0 で、標準出力が `"golem " <> golemVersion <> "\n"` と一致し、標準エラー出力が空であること。
- `golem --version` の出力に英語の定型句（既存の `english` の一覧）が含まれないこと。
- `golem --help` の golden（`test/golden/help.txt`）に `--version` の行と「版を表示する」が現れること。golden を先に書き換えて、失敗させてから実装する。
- `golem build --version` が、サブコマンドのオプションとしては受け付けられず、終了コード 2 になること。

### 版の一元化（golem-driver のテスト）

- `golemVersion` が `VERSION` の内容と一致すること。
- `VERSION` を `0.1.0-rc1` にした状態でビルドした `golem --version` が `golem 0.1.0-rc1` を出すこと（golem-cli のテストで、`VERSION` を読んで期待値を作る）。
- 同じ入力で PDF のインスタンス ID が `"golem-" <> golemVersion` を含む入力から計算されること。`Golem.Driver.Pdf` の入力の一覧を返す関数を公開し、その末尾が `TE.encodeUtf8 ("golem-" <> golemVersion)` であることを検査する。

### TLS のルート証明書（golem-plugin のテスト）

- 環境変数 `SSL_CERT_FILE` を空のファイルに向けて `httpsFetcher` で `https://` の URL を取得すると、ネットワークに接続する前に `Left` が返り、メッセージに `SSL_CERT_FILE` と `ca-certificates` が含まれること。ローカルの HTTPS のテスト用サーバー（[golem-plugin ADR 0002](../golem-plugin/adr/0002-distribution-and-lock.md) のテストで使っているもの）を立て、サーバーが接続を一度も受けないことも確かめる。
- テストの後に `SSL_CERT_FILE` を元に戻す。

### リリースのスクリプト（`scripts/release/test.sh`）

POSIX のシェルで書き、CI に `release-scripts` ジョブを足して実行する。
一時ディレクトリに cabal ファイルと Git のリポジトリを作って入力にする。

`check-version.sh`：

| 入力 | 期待 |
|---|---|
| `VERSION` が `0.1.0`、全パッケージが `0.1.0`、引数なし | 終了コード 0、`version=0.1.0` |
| `VERSION` が `0.1.0-rc1`、全パッケージが `0.1.0`、引数なし | 終了コード 0、`version=0.1.0-rc1` |
| 一つのパッケージだけ `0.1.1` | 終了コード 1 |
| `VERSION` が `0.1`、`v0.1.0`、`0.1.0-` | 終了コード 1 |
| `VERSION` が `0.1.0`、タグ `v0.1.0` | `prerelease=false` |
| `VERSION` が `0.1.0-rc1`、タグ `v0.1.0-rc1` | `prerelease=true` |
| `VERSION` が `0.1.0-rc.1`、タグ `v0.1.0-rc.1` | `prerelease=true` |
| `VERSION` が `0.1.0`、タグ `v0.1.0-rc1` | 終了コード 1 |
| `VERSION` が `0.1.0`、タグ `v0.1.1` | 終了コード 1 |
| タグ `v0.1`、`0.1.0`、`v0.1.0+build`、`v0.1.0-` | 終了コード 1 |

`notes.sh`：

- 二つのマージコミット（`Merge pull request #3: a`、`Merge pull request #4: b`）と、マージでないコミット、追加した ADR 一つを含む範囲で、`## Unsorted` に `#3` と `#4` だけが `https://github.com/tett23/golem/pull/3` などの絶対リンク付きで並び、`## ADRs` に ADR がタグの版の絶対リンクで並ぶこと。期待する出力を golden のファイルとして置く。
- 前のタグがない場合に、最初のコミットからの範囲になること。
- `## Added`、`## Changed`、`## Removed`、`## Fixed`、`## Unsorted` の見出しがこの順に現れること。

`check-notes.sh`：

- 見出しとプルリクエストの絶対リンクがそろったノートが通ること。
- `## Unsorted` が残ったノート、相対リンク（`#3`、`../docs/adr/...`）を含むノート、`notes.sh` が挙げたプルリクエストの番号が抜けたノートが、それぞれ終了コード 1 になること。

AI の出力そのものは自動テストにしない。
最初の `v0.1.0-rc1` の下書きで、ノートを人が読んで確かめる。

`licenses.sh`：

- `plan.json` の依存のうち一つのライセンスのファイルを取り除いた入力で、終了コード 1 になり、そのパッケージの名前が標準エラー出力に出ること。

### 配布物の検査（リリースのワークフローの `smoke` ジョブ）

三つの配布物それぞれについて、ビルドしたものとは別のランナーで次を行う。
Linux の配布物は、ランナーの上（Ubuntu、glibc）に加えて、`docker run` で `alpine` と `debian:stable-slim` のコンテナの中でも動かす（イメージはダイジェストで固定する）。
`debian:stable-slim` では、ca-certificates を入れる場合と入れない場合の両方を試す。

1. `SHA256SUMS` に当たる値でアーカイブを検証し、展開する。
2. `golem --version` の出力が `golem X.Y.Z` で、`X.Y.Z` が `check-version.sh` の結果と一致すること。
3. 依存を検査する。Linux では `file golem` が `statically linked` を含み、`ldd golem` が動的な実行ファイルでないと報告すること。macOS では `otool -L golem` の依存がすべて `/usr/lib/` と `/System/Library/` の下にあること、`otool -l golem` の `minos` が `14.0` 以下であること、`codesign --verify golem` が通ること。
4. `golem new --no-fonts book-ja` と `golem new --no-fonts --language en book-en` が終了コード 0 で終わり、それぞれの中で `golem build --target html --target epub --target text` が終了コード 0 で終わること。この手順はネットワークに接続しない。
5. `golem new book` と `golem new --language en book-en-fonts` が、フォントを配布元から HTTPS で取得して終了コード 0 で終わり、それぞれの中で `golem build` が終了コード 0 で四つのターゲットを作ること。この手順が、配布物の中の TLS と名前解決が OS の証明書のストアと共に動くことの確かめになる（[golem-cli ADR 0003](../golem-cli/adr/0003-new-project-page-and-fonts.md)）。
6. ca-certificates のない `debian:stable-slim` では、`golem new book` が終了コード 1 で終わり、標準エラー出力に `SSL_CERT_FILE` が含まれ、`book` のディレクトリが作られないこと。続けて `SSL_CERT_FILE` にランナーの証明書のファイルを渡すと、5 と同じく成功すること。
7. `GOLEM=<展開した golem> scripts/determinism.sh` の出力を `determinism-<プラットフォーム>.txt` として上げる。

プラグインの取得（`golem plugin lock` と `golem plugin fetch`）は、TLS と名前解決の経路が `golem new` と同じ `httpsFetcher` なので、5 の確かめで代える。

### 出力の決定性（リリースのワークフローの `determinism` ジョブ）

- `ci` ジョブの `determinism-ubuntu-24.04.txt` と、`smoke` ジョブの三つの `determinism-<プラットフォーム>.txt` を `diff` で比べ、すべて一致すること。

### ワークフローをタグなしで試す

- `release.yml` を含むブランチで `gh workflow run release.yml --ref <ブランチ>` を実行し、`release` ジョブ以外のすべてのジョブが通り、三つのアーカイブがワークフローの成果物として残ること、GitHub Releases に何も作られないことを確かめる。
- `main` にマージした後、`VERSION` を `0.1.0-rc1` にして最初に `v0.1.0-rc1` のタグを push し、プレリリースの印の付いた下書きのリリースが、三つのアーカイブ、`SHA256SUMS`、GMP のソースのアーカイブ、AI が書いた英語のリリースノートと共に作られることを確かめる。配布物の `golem --version` が `golem 0.1.0-rc1` を出すことも確かめる。`gh attestation verify golem-v0.1.0-rc1-x86_64-linux.tar.gz --repo tett23/golem` が通ることも確かめる。確かめた後は、下書きを削除してよい。
- `main` に含まれないコミットに `v0.0.0-test1` のタグを付けて push すると、`version` ジョブが失敗し、リリースが作られないことを確かめる。

## トレードオフ

Linux を musl で静的にリンクすると、CI（glibc）とリリース（musl）でビルドの環境が分かれる。
CI で通ったものが musl でも同じ出力を出すことは、リリースの `determinism` ジョブで初めて確かめられるので、不一致はリリースの時点まで見つからない。
不一致が続くようなら、CI の `build` に musl のビルドを加える。

musl の `malloc` は glibc のものより遅いことが知られている。
GHC のヒープは RTS が自前で管理するので影響は限られるが、HarfBuzz、FreeType、wasmtime の割り当ては musl の `malloc` を使う。
速度の差は測っておらず、問題になれば別に扱う。

musl 向けの wasmtime の C API が公式の配布物にない場合は、Rust の道具でソースからビルドすることになり、リリースのビルドが長くなる。
ビルドした `libwasmtime.a` はコミットのハッシュと版で鍵を付けてキャッシュする。

GMP を静的にリンクするので、LGPL-3.0 の条件に従ってライセンスの文書と GMP のソースを添える手間が、リリースごとにかかる。
GMP を使わない GHC（整数の実装を native にしたもの）にすれば手間はなくなるが、GHC 9.10.3 の公式の配布物にはその構成がない。

macOS の実行ファイルに公証がないので、ブラウザから取得した利用者は、属性を外す一手間をかける。
CI や `curl` で取得する利用者には影響しない。

リリースノートを AI が書くので、分類やまとめ方がおかしいことがある。
公開の前に人が読み、多少おかしい点は手で直す運用にして、書く手間を減らすほうを選ぶ。
AI の実行に API キーと費用が要り、AI が使えないときは `notes.sh` の一覧だけのノートになる。

版の正本を cabal の `version` ではなく `VERSION` に置くので、版を上げるときは `VERSION` と全パッケージの cabal ファイルの両方を書き換える。
`check-version.sh` が二つの食い違いを CI で止めるので、片方だけを書き換えたまま出ることはない。
プレリリースの識別子が実行ファイルと PDF のインスタンス ID に入るので、rc と正式のリリースで同じ入力の PDF のバイト列は変わる。
