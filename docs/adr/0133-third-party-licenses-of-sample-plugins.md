# ADR 0133: 見本のプラグインのライセンスの文書をリリースに添える

ステータス: 採択

## 文脈

リリースには、見本のプラグインの `<名前>.wasm` を添えている（[docs/adr/0106](0106-sample-plugins-in-rust.md)、[`release.yml` の L253-L266](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/.github/workflows/release.yml#L253-L266)、[同 L281](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/.github/workflows/release.yml#L281)）。
添えるのは `.wasm` だけで、その中に入ったものの著作権の表示とライセンスの文書は添えていない。
`golem` の実行ファイルには、リンクしたもののライセンスの文書を `THIRD_PARTY_LICENSES/` として添えている（[docs/adr/0007](0007-third-party-licenses.md)）が、見本のプラグインはその対象の外にある。

[docs/adr/0130](0130-sou-ruby-plugin.md) の `sou-ruby` は、形態素解析の Lindera 6.2.0（MIT）と、それが依存するクレートを wasm に入れる。
MIT は、ソフトウェアの複製に著作権の表示と許諾の文を含めることを求める。
Apache-2.0、BSD-3-Clause、Unicode-3.0 も、バイナリの形で配布するときに文書を添えることを求める。
[docs/adr/0106](0106-sample-plugins-in-rust.md) は「辞書などを埋め込むプラグインは、埋め込むもののライセンスを、そのプラグインの ADR に書く」としたが、書いたライセンスの文書を配布物に添えることは決めていない。
Lindera のライセンスの文書をリリースに添えるよう、メンテナから求められた。

### 調べて分かったこと

この ADR を書く前に、`origin/main`（[5db37cb9](https://github.com/tett23/golem/tree/5db37cb96acb88a84fb63057323c066991fc995c)）の `plugins/` で次を調べた。
クレートの集合は、`cargo tree --offline --locked -e normal,build --target wasm32-unknown-unknown` と、`cargo build --release --target wasm32-unknown-unknown` で実際に作られた `.rlib` から求めた。

#### どのプラグインにも Rust の標準ライブラリが入る

見本のプラグインはどれも `#![no_std]` ではない（[docs/adr/0106](0106-sample-plugins-in-rust.md) の「実装しないこと」）。
コミットした八つの wasm から `strings -a` で取り出したパスには、どれにも `/rustc/58cf8f9c35b355199727627d07ae34a4e2846d67/library/std` と `library/alloc` と、標準ライブラリが crates.io から取り込む `/rust/deps/dlmalloc-0.2.14` がある。
`sou-ruby` には、さらに `/rust/deps/hashbrown-0.17.1` と `/rust/deps/rustc-demangle-0.1.28` がある。
問題は `sou-ruby` だけではなく、八つのプラグインのすべてにある。

#### crates.io のクレートに依存するのは `sou-ruby` だけである

| プラグイン | crates.io のクレート | リポジトリのクレート |
|---|---|---|
| `lookup`、`bar-chart`、`glossary`、`kansuji`、`auto-tcy`、`tsv-table` | 0 | 自身、`golem-plugin-sdk` |
| `first-ruby` | 0 | 自身、`golem-plugin-sdk`、`ruby-common` |
| `sou-ruby` | 77 | 自身、`golem-plugin-sdk`、`ruby-common` |

`sou-ruby` の 77 個のうち、57 個は wasm 向けの `.rlib` として作られ、wasm にリンクされうる。
残りの 20 個はホストでだけ動くもので、通常の依存の手続きマクロ（`serde_derive`、`zerovec-derive` など 12 個）と、その依存（`syn` の 2.0.119 と 3.0.9、`quote`、`proc-macro2` など 7 個）と、`rustversion` である。
`rustversion` は手続きマクロで、`encoding_rs` のビルドの依存としてだけ現れる。
ライセンスの式は、`MIT OR Apache-2.0`（または `Apache-2.0 OR MIT`）が 36 個、`Unicode-3.0` が 18 個、`MIT` が 16 個、`Unlicense OR MIT` が 4 個、`Apache-2.0 OR BSL-1.0` が 1 個、`(MIT OR Apache-2.0) AND Unicode-3.0` が 1 個、`(Apache-2.0 OR MIT) AND BSD-3-Clause` が 1 個である。

[docs/adr/0130](0130-sou-ruby-plugin.md) は依存のクレートを 88 個としている。
`cargo metadata` の `resolve` を `sou-ruby` から通常の依存の辺で辿ると、リポジトリのクレート 3 個と crates.io のクレート 86 個になる。
この 86 個は、フィーチャーが有効でないためにビルドされない 10 個（`uuid`、`wasm-bindgen` とその三つの補助、`bumpalo`、`bytes`、`indexmap`、`equivalent`、`tinyvec`）を含む。
`cargo metadata` はフィーチャーの解決の前の依存を返すためである。

#### パッケージにライセンスのファイルがないクレートがある

77 個のうち 75 個は、パッケージの最上位に `LICENSE`、`LICENSE-MIT`、`COPYING`、`UNLICENSE` などのファイルを持つ。
持たないのは `lindera-6.2.0` と `lindera-dictionary-6.2.0` の二つで、メンテナが名指しした当のクレートである。
どちらも `Cargo.toml` に `license = "MIT"` と書くだけで、著作権者の表示がない。
両者の `.cargo_vcs_info.json` は、どちらも lindera のリポジトリのコミット `0482efcc46b5ec518b7238efae55e9fed9bba0c0` を指す。
これはタグ `v6.2.0` のコミットであり、その最上位の `LICENSE`（MIT、`Copyright (c) 2019 by the project authors`）の SHA-256 は `d37249886de3136db31717f15f6ade215a36fbed1c782381e38b2bf6047e8ec4` である。

#### 標準ライブラリのライセンスの文書は、ツールチェーンが持っている

rustup の `minimal` のプロファイルでも入る `rustc` のコンポーネントは、`share/doc/rust/COPYRIGHT-library.html`（約 1.5 MB）と `share/doc/rust/licenses/`（Apache-2.0、MIT、Unicode-3.0 など 12 個の本文）を持つ。
`COPYRIGHT-library.html` は、標準ライブラリの木の中のファイルのライセンスと、標準ライブラリが使う crates.io のクレート 141 個の文書を載せる。
1.99.1 のものには `dlmalloc-0.2.14`、`hashbrown-0.17.1`、`rustc-demangle-0.1.28` があり、wasm から取り出した版と一致する。
`aarch64-apple-darwin` と `x86_64-unknown-linux-gnu` の rustc 1.99.1 で、`COPYRIGHT-library.html` の SHA-256（`5647be07…`）と `licenses/` の中身は一致した。

#### 大きさ

77 個のクレートの文書は 129 ファイル、約 0.8 MB で、`COPYRIGHT-library.html` と `licenses/` を合わせると約 2.4 MB になる。
`tar.gz` にすると約 135 KB である。

### wasmtime のクレートの先例

[docs/adr/0007](0007-third-party-licenses.md) は、`libwasmtime.a` に入った Rust のクレートの文書を、人が `scripts/wasmtime-licenses.sh` で生成してコミットし、リリースのたびに照合すると決めた。
パッケージにライセンスのファイルがないクレートは、同じプロジェクトのほかのクレートの文書を写す対応表で扱っている（[`NOFILE_TABLE`](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/scripts/wasmtime-licenses.sh#L89-L95)）。
見本のプラグインでは、事情が二つ異なる。

- wasm はコミットしてあり、CI の `plugins` ジョブが、ソースから作ったバイト列と一致することを毎回確かめている（[`ci.yml` の L564-L583](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/.github/workflows/ci.yml#L564-L583)）。このジョブは依存のクレートのソースを手元に持つので、クレートの集合と文書をそこで作り直せる。
- 依存は `plugins/Cargo.lock` の更新で変わり、wasmtime の版を上げるときほど稀ではない。人が生成を忘れたときに止める検査が要る。

## 実装すること

### 方針

見本のプラグインに入るものの著作権の表示とライセンスの文書を、リポジトリの `licenses/plugins/` に生成してコミットする。
CI の `plugins` ジョブで同じものを作り直し、コミットしたものと一字でも違えば失敗させる。
リリースでは、`licenses/plugins/` と Golem の `LICENSE` を一つのアーカイブ `golem-plugins-licenses-<タグ>.tar.gz` にまとめて添える。
リリースのワークフローは、ネットワークにも Rust のツールチェーンにも依らない。

### 生成の道具

`scripts/plugin-licenses.sh` を足す。
POSIX のシェルと awk、`diff`、`strings`、`cargo`、`rustc`、`curl` で書き、`cargo about` のような道具は使わない（[docs/adr/0007](0007-third-party-licenses.md) と同じ理由）。
`jq` も使わない。

```
scripts/plugin-licenses.sh           licenses/plugins/ を作り直す
scripts/plugin-licenses.sh --check   作り直したものが licenses/plugins/ と同じでなければ失敗する
```

手順は次のとおりである。

1. `plugins/` で `cargo tree --offline --locked --workspace -e normal,build --target wasm32-unknown-unknown --prefix depth --format '{p}|{l}'` を実行する。`--workspace` にするのは、`plugins/build.sh` がワークスペースの全体を一度に作り、フィーチャーをワークスペースで統一するためである。深さ 0 の行でプラグインを区切り、プラグインごとに、それが依存するクレートの名前、版、ライセンスの式を得る。`(<パス>)` の付いたクレートはリポジトリのものなので除く。`crate-type` に `cdylib` を持たない `golem-plugin-sdk` と `ruby-common` は、プラグインとしては数えない（`build.sh` の判定と同じ）。
2. クレートごとに、`$CARGO_HOME/registry/src/index.crates.io-*/<名前>-<版>/` の最上位から、[docs/adr/0007](0007-third-party-licenses.md) の `licenses.sh` と同じ正規表現（`LICEN[CS]E`、`COPYING`、`COPYRIGHT`、`NOTICE`）と `UNLICENSE` に当たるファイルと、REUSE の `LICENSES/` を `crates/<名前>-<版>/` に写す。
3. ファイルが一つもないクレートは、スクリプトに固定した対応表 `UPSTREAM` を引く。表の行は、クレートの名前と版、上流のリポジトリ、コミットのハッシュ、リポジトリの中のパス、SHA-256 である。クレートの `.cargo_vcs_info.json` の `sha1` が表のコミットと一致しなければ、エラーとする。文書は `https://raw.githubusercontent.com/<リポジトリ>/<コミット>/<パス>` から取得し、SHA-256 を検証して写す。`crates/<名前>-<版>/` に同じ SHA-256 のファイルがすでにあれば、取得しない。写したディレクトリには、取得元の URL と SHA-256 を書いた `NOTE` を置く。最初の表は次の二行である。

   | クレート | リポジトリ | コミット | パス | SHA-256 |
   |---|---|---|---|---|
   | `lindera-6.2.0` | `lindera/lindera` | `0482efcc46b5ec518b7238efae55e9fed9bba0c0` | `LICENSE` | `d37249886de3136db31717f15f6ade215a36fbed1c782381e38b2bf6047e8ec4` |
   | `lindera-dictionary-6.2.0` | `lindera/lindera` | `0482efcc46b5ec518b7238efae55e9fed9bba0c0` | `LICENSE` | `d37249886de3136db31717f15f6ade215a36fbed1c782381e38b2bf6047e8ec4` |

   表にもないクレートは、名前を標準エラー出力に書いてエラーとする。
4. `plugins/rust-toolchain.toml` のツールチェーンの `$(rustc --print sysroot)/share/doc/rust/` から、`COPYRIGHT-library.html` と `licenses/` を `rust/` に写す。`rustc -vV` の `release` と `commit-hash` を `rust/VERSION` に書く。`COPYRIGHT.html`（約 14 MB）はコンパイラの文書であり、wasm に入らないので写さない。
5. コミットした `plugins/wasm/<名前>.wasm` を `strings -a` で読み、次を確かめる。どれか一つでも外れれば、エラーとする。
   - `/rustc/<ハッシュ>/` のハッシュが、`rust/VERSION` の `commit-hash` と一致すること。
   - `/rust/deps/<名前>-<版>` の各々が、`COPYRIGHT-library.html` に `📦 <名前>-<版>` として載っていること。
   - `index.crates.io-<ハッシュ>/<名前>-<版>` の各々が、1 でそのプラグインの依存として得たクレートにあること。
6. 次のものを書く。
   - `MANIFEST.tsv`：プラグイン、パッケージの名前、版、ライセンスの式、写したファイルの一覧。プラグインとクレートの組ごとに一行とし、名前の順に並べる。
   - `README`：何の文書か、生成のコマンド、ツールチェーンの版、プラグインごとの依存のクレートの一覧（crates.io の依存がないプラグインは、標準ライブラリだけであることを書く）。日付は書かない。`--check` で作り直したものと比べるためである。

`--check` は、一時ディレクトリに作り直して `diff -r` で `licenses/plugins/` と比べ、違いがあれば違ったパスを標準エラー出力に書いて終了コード 1 で終える。
新しいクレートの文書がない、使わなくなったクレートの文書が残っている、クレートの版が変わった、ツールチェーンを変えたのに `rust/` が古い、のどれもこれで止まる。
`--check` は、`UPSTREAM` の文書をネットワークから取らず、コミットしたファイルの SHA-256 を検証する。

`CARGO_HOME`、`cargo tree` の出力、`share/doc/rust/` の場所、`rustc -vV` の出力、wasm の置き場所、`curl` の代わりは、環境変数で差し替えられるようにする。
テストで小さな入力を渡すためである。

### 出力

`licenses/plugins/` に置き、コミットする。

| パス | 内容 |
|---|---|
| `README` | 何の文書か、生成のコマンド、ツールチェーンの版、プラグインごとの依存の一覧 |
| `MANIFEST.tsv` | プラグイン、パッケージの名前、版、ライセンスの式、写したファイルの一覧 |
| `crates/<名前>-<版>/` | クレートのライセンスの文書。`UPSTREAM` から取ったものには `NOTE` も置く |
| `rust/COPYRIGHT-library.html`、`rust/licenses/` | Rust の標準ライブラリと、それが取り込む crates.io のクレートの文書 |
| `rust/VERSION` | rustc の版とコミットのハッシュ |

二つのプラグインが同じクレートに依存しても、`crates/` には一つだけ置く。
`MANIFEST.tsv` には、プラグインごとに行を置く。

### CI

`ci.yml` の `plugins` ジョブの `sh build.sh --check` の後に、`sh ../scripts/plugin-licenses.sh --check` の段を足す。
`build.sh` のビルドで依存のクレートのソースが手元にあるので、この段はネットワークを使わない。
`licenses/plugins/` と `scripts/plugin-licenses.sh` は `docs/` の外にあるので、変えると `plugins` ジョブが走る（`scripts/ci/needs-build.sh`）。
リリースのワークフローは `ci.yml` を呼ぶので、タグの push でもこの検査が走る。

### リリース

`release.yml` の「SHA256SUMS, the sample plugins and the source of GMP」の段で、`golem-plugins-licenses-<タグ>.tar.gz` を作る。
展開すると `golem-plugins-licenses-<タグ>/` の一つのディレクトリができ、中には Golem の `LICENSE` と、`licenses/plugins/` を写した `THIRD_PARTY_LICENSES/` が入る。
見本のプラグインの Golem のコードは MIT（[`plugins/Cargo.toml` の L11](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/plugins/Cargo.toml#L11)）なので、Golem 自身の表示も要る。
`tar` には、マニュアルの HTML のアーカイブと同じく `--sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner` を付け、`gzip -n` で圧縮する。
SHA-256 を `SHA256SUMS` に載せ、`gh release create` の引数に加える。

利用者は、プラグインと同じ URL の並びで文書を取得できる。

```
https://github.com/tett23/golem/releases/download/<タグ>/<名前>.wasm
https://github.com/tett23/golem/releases/download/<タグ>/golem-plugins-licenses-<タグ>.tar.gz
```

### ドキュメント

- [仕様書](../specifications.md) の「見本のプラグイン」の節に、`licenses/plugins/` を生成してコミットすること、CI の `plugins` ジョブが作り直して比べること、この ADR へのリンクを書く。「配布物」の節の、リリースに添えるものの一覧に `golem-plugins-licenses-<タグ>.tar.gz` を加える。
- README の、アーカイブの `THIRD_PARTY_LICENSES/` を説明する段落の後に、見本のプラグインの文書は `golem-plugins-licenses-<タグ>.tar.gz` にあることを書く。Development の節の `licenses/` の説明に `licenses/plugins/` を加え、CI の表の `plugins` ジョブと、リリースのワークフローの表の `release` ジョブの説明を改める。
- 開発者のマニュアル（`manual-dev/part1/05-plugins.gm`）の見本のプラグインの段落に、依存を変えたら `sh scripts/plugin-licenses.sh` で `licenses/plugins/` を作り直し、`Cargo.lock` と一緒にコミットすることを書く。
- 利用者のマニュアル（`manual/chapters/10-plugins.gm`）の、見本のプラグインの URL を説明する段落に、ライセンスの文書を添えたアーカイブの URL を書く。プラグインを再配布するときに同梱することも書く。

## 実装しないこと

- IPADIC などの辞書をリリースに添えること。[docs/adr/0130](0130-sou-ruby-plugin.md) のとおり、辞書は利用者がデータとして渡し、Golem は配布しない。辞書のライセンスの文書も、配布しないので添えない。
- プラグインごとのライセンスのファイル（`<名前>.wasm` ごとの文書）。理由は「トレードオフ」に書いた。
- ライセンスの文書を wasm のカスタムセクションに埋め込むこと。wasm のバイト列が大きくなり、`sou-ruby` 以外の七つの小さなプラグインにも標準ライブラリの文書（約 1.5 MB）が入る。読む道具もない。
- リリースのワークフローの中で文書を集めること。Rust のツールチェーンとクレートのソースが要り、リリースが crates.io に依存する。生成したものをコミットすれば、プルリクエストで文書の差分を読める。
- クレートのライセンスの式を解釈して、許すライセンスかどうかを自動で判定すること。[docs/adr/0007](0007-third-party-licenses.md) と同じく、判定は人が行う。`MANIFEST.tsv` の差分がプルリクエストに出るので、式の変化は読める。
- 文書の重複の除去。MIT の著作権者の表示はクレートごとに違うので、クレートごとに置く。
- `golem` の実行ファイルの `THIRD_PARTY_LICENSES/` への同梱。見本のプラグインは実行ファイルとは別に URL で取得され、実行ファイルのアーカイブを取らない利用者もいる。
- `golem plugin lock` などで、プラグインの取得のときに文書も取ること。Haskell のコードは変えない。
- `golem-plugin-sdk` を `#![no_std]` にして、標準ライブラリを入れないこと。[docs/adr/0106](0106-sample-plugins-in-rust.md) のとおり、困っていない。

## テスト設計

### スクリプトのテスト（`scripts/test.sh`）

`scripts/test.sh` は、人が実行するスクリプトのテストであり、`scripts-linux` ジョブが実行する（[docs/adr/0078](0078-tests-for-release-and-hand-run-scripts.md)）。
`plugin-licenses.sh` のテストを足し、一時ディレクトリに偽の `CARGO_HOME`、`cargo tree` の出力、`share/doc/rust/`、`rustc -vV` の出力、wasm を置いて実行する。
ネットワークは使わない。
これらのテストは、`plugin-licenses.sh` を書く前に書いて失敗させる。

偽の入力は、プラグイン `plain`（リポジトリのクレートだけに依存する）と `rich`（`foo v1.0.0` に通常の依存、手続きマクロ `bar v2.0.0` に通常の依存、`baz v0.1.0` にビルドの依存）の二つとする。

- 終了コード 0 で、`MANIFEST.tsv` に `rich` と `foo`、`bar`、`baz` の三行が、名前の順に出ること。`plain` の行は出ないこと。
- `crates/foo-1.0.0/LICENSE-MIT`、`crates/bar-2.0.0/LICENSE-APACHE`、`crates/bar-2.0.0/LICENSE-MIT` が、偽の registry のものと同じ内容で書かれること。
- REUSE の `LICENSES/` だけを持つクレートで、`LICENSES/` が写ること。
- リポジトリのクレート（`(<パス>)` の付いた行）が、`crates/` にも `MANIFEST.tsv` にも出ないこと。
- `plain` も `rich` も `foo` に依存させると、`crates/foo-1.0.0/` は一つで、`MANIFEST.tsv` には二行出ること。
- `README` に `plain` があり、標準ライブラリだけであることが書かれること。
- `rust/COPYRIGHT-library.html` と `rust/licenses/` が写り、`rust/VERSION` に `rustc -vV` の `release` と `commit-hash` が書かれること。
- 二度実行すると、出力のディレクトリがバイト単位で同じであること。
- ライセンスのファイルを持たず `UPSTREAM` にもないクレートを足すと、終了コード 1 になり、その名前が標準エラー出力に出ること。
- `UPSTREAM` にあるクレートで、`curl` の代わりが表の SHA-256 の文書を書くと、`crates/<名前>-<版>/LICENSE` と `NOTE` が書かれること。違う内容を書くと、終了コード 1 になること。
- `.cargo_vcs_info.json` の `sha1` が `UPSTREAM` のコミットと異なると、終了コード 1 になること。
- `crates/<名前>-<版>/LICENSE` がすでに表の SHA-256 で置かれていると、`curl` の代わりを呼ばないこと（呼ぶと失敗する代わりを置いて確かめる）。
- wasm の `/rustc/<ハッシュ>/` が `rustc -vV` の `commit-hash` と異なると、終了コード 1 になること。
- wasm の `/rust/deps/dlmalloc-0.2.15` が `COPYRIGHT-library.html` にないと、終了コード 1 になり、その名前が標準エラー出力に出ること。
- `rich` の wasm に、`rich` の依存にない `index.crates.io-0123456789abcdef/qux-1.0.0` があると、終了コード 1 になること。`foo` に依存しない `plain` の wasm に `foo-1.0.0` があっても、同じく終了コード 1 になること。
- `--check`：作ったばかりの出力に対して、終了コード 0 になること。次のどれでも終了コード 1 になり、違ったパスが標準エラー出力に出ること。
  - `cargo tree` の出力にクレートを足す。
  - `cargo tree` の出力からクレートを取り除く。
  - `cargo tree` の出力でクレートの版を変える。
  - `crates/` のファイルを一字変える。
  - `rust/VERSION` を変える。
- `--check` は `curl` の代わりを呼ばないこと。

### 自動テストにしないもの

- 実装の最後に、手元の macOS で `sh scripts/plugin-licenses.sh` を実行し、`licenses/plugins/MANIFEST.tsv` の `sou-ruby` の行が 77 行で、ほかの七つのプラグインの行がないことを確かめる。`crates/lindera-6.2.0/LICENSE` が上の SHA-256 であることも確かめる。
- BSD の道具で動くことは、生成を macOS で実行することで確かめる。GNU の道具で動くことは、CI の `plugins` ジョブ（Ubuntu）の `--check` が通ることで確かめる。macOS で生成したものと Linux で作り直したものが一致すれば、両方で同じ出力になる。
- リリースのワークフローは、次のプレリリースで確かめる。リリースに `golem-plugins-licenses-<タグ>.tar.gz` があり、`SHA256SUMS` にその行があり、展開したものに `LICENSE` と `THIRD_PARTY_LICENSES/crates/lindera-6.2.0/LICENSE` があることを見る。

## トレードオフ

### 一つのアーカイブか、プラグインごとか

一つのアーカイブにすると、標準ライブラリの文書（約 1.5 MB）と共通のクレートの文書を一度だけ置ける。
プラグインごとにすると、同じ文書が八つ並び、リリースの添付も八つ増える。
代わりに、`sou-ruby` だけを再配布する利用者は、アーカイブの `README` か `MANIFEST.tsv` を見て、どの文書が要るかを選ぶ手間がある。
`lindera` だけでなく `sou-ruby` の 77 個の文書を同梱すればよく、`MANIFEST.tsv` の `sou-ruby` の行がその一覧になる。

### 生成してコミットするか、CI で作るだけにするか

コミットすると、リポジトリが約 2.4 MB 大きくなる。
代わりに、リリースのワークフローがツールチェーンとネットワークに依らず、`Cargo.lock` を変えたプルリクエストにライセンスの文書と式の差分が出る。
[docs/adr/0130](0130-sou-ruby-plugin.md) が「クレートの更新のたびに確かめる必要がある」とした確認を、この差分で行える。

### クレートの集合を `cargo tree` から求めるか、`cargo metadata` から求めるか

`cargo metadata` は JSON を返すので読みやすいが、フィーチャーの解決の前の依存を返すので、ビルドされない 10 個のクレートを含む。
`cargo tree` は、`build.sh` と同じフィーチャーの解決をした後の依存を返す。
出力は人向けの形だが、`--prefix depth --format '{p}|{l}'` で行ごとに区切れる。
形が変わって読めなくなれば、`sou-ruby` の依存が 0 個に見えて、5 の wasm との照合（wasm に残る 8 個のクレートの位置）でエラーになり、黙って漏れることはない。

### 手続きマクロとビルドの依存も入れるか

手続きマクロとビルドスクリプトのコードは wasm に入らないが、それが書いたコードは入る。
書いたコードに著作権が及ぶかを自動で判定できないので、入れる側に倒す。
多く入れる分には害がない（[docs/adr/0007](0007-third-party-licenses.md)）。
入れすぎるのは 20 個で、文書の量はわずかである。
開発の依存は、テストでしか使わないので入れない。

### 標準ライブラリの文書を、ツールチェーンの `COPYRIGHT-library.html` から取るか

このファイルは Rust のプロジェクトが標準ライブラリの配布のために作ったもので、wasm に入る `dlmalloc` などの版を載せている。
wasm から見えない多くのクレートの文書も含むが、標準ライブラリがどのクレートを wasm に入れるかは、ターゲットと使った機能で変わり、こちらで選ぶと漏れうる。
[docs/adr/0007](0007-third-party-licenses.md) の wasmtime の文書のように、`rust-src` の `library/Cargo.lock` から辿って写す方法もあるが、wasm32 の `dlmalloc` が依存の一覧に入るかを確かめる手間が増え、得るものがない。
`rustc` のコンポーネントは SHA-256 を検証して rustup が入れるので、出どころは公式の配布物である。

### wasm の文字列による照合は、補助である

パニックの位置の文字列を持たないクレートは、wasm から見えない。
`sou-ruby` の 57 個のうち、wasm に位置が残るのは 8 個だけだった。
漏れを防ぐのは 1 の `cargo tree` の集合であり、5 は、`cargo tree` の集合と実際の wasm がずれたときと、ツールチェーンを変えたのに `rust/` を作り直さなかったときに止めるためのものである。

### `UPSTREAM` の表は人が書く

パッケージにライセンスのファイルがないクレートが加わるたびに、上流のリポジトリの文書を探し、コミットと SHA-256 を表に書く手間がある。
同じプロジェクトのほかのクレートから写す wasmtime の `NOFILE_TABLE` の方式は、Lindera では使えない。
Lindera の二つのクレートはどちらもパッケージに `LICENSE` を持たず、MIT の著作権者の表示はプロジェクトごとに違うためである。

## 参考文献

- [docs/adr/0004](0004-binary-distribution-and-release.md)「実行ファイルの配布とリリースの自動化」
- [docs/adr/0007](0007-third-party-licenses.md)「配布物の THIRD_PARTY_LICENSES にリンクしたものをすべて入れる」
- [docs/adr/0078](0078-tests-for-release-and-hand-run-scripts.md)「リリースと手で実行するスクリプトのテスト」
- [docs/adr/0106](0106-sample-plugins-in-rust.md)「見本のプラグインを Rust で書き、リポジトリに置く」
- [docs/adr/0130](0130-sou-ruby-plugin.md)「形態素解析で読みを振るプラグイン」
- [golem-plugin ADR 0002](../golem-plugin/adr/0002-distribution-and-lock.md)
- The Cargo Book, cargo-tree. https://doc.rust-lang.org/cargo/commands/cargo-tree.html
- The Cargo Book, cargo-metadata. https://doc.rust-lang.org/cargo/commands/cargo-metadata.html
- Lindera v6.2.0 の LICENSE. https://github.com/lindera/lindera/blob/0482efcc46b5ec518b7238efae55e9fed9bba0c0/LICENSE
- The MIT License. https://opensource.org/license/mit
- Apache License, Version 2.0（第 4 節 Redistribution）. https://www.apache.org/licenses/LICENSE-2.0
- Unicode License v3. https://www.unicode.org/license.txt
- REUSE Specification. https://reuse.software/spec/
