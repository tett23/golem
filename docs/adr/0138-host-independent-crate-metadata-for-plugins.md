# ADR 0138: 見本のプラグインのクレートの `-C metadata` をホストに依らない値にする

ステータス: 採択

## 文脈

[docs/adr/0106](0106-sample-plugins-in-rust.md) は、見本のプラグインの `.wasm` をリポジトリにコミットし、同じソースからは同じバイト列ができることを CI の `plugins` ジョブで確かめると決めた。
再現性のために決めた手立ては、`rust-toolchain.toml` でのツールチェーンの固定と、`--remap-path-prefix` でのソースのパスの置き換えである。
試しの実装は、macOS arm64 の二つのディレクトリと、Linux amd64 の `rust:1.99.1` のコンテナで、同じバイト列になることを確かめた。

[docs/adr/0130](0130-sou-ruby-plugin.md) の `sou-ruby` を足した PR #496 で、CI の `plugins` ジョブ（ubuntu-24.04）が失敗した。
macOS で作ってコミットした `sou-ruby.wasm` と、Linux で作ったものが違った。
Linux arm64 で作ったものは、そのどちらとも違った。
どのホストでも、同じホストで作り直せば同じバイト列だった。

実装者の調べでは、原因は次のとおりである（[e85ad2af](https://github.com/tett23/golem/commit/e85ad2afcef84adeb06b3f44c38855dd9320251d) のコミットのメッセージ）。

- cargo は、各クレートに `-C metadata=<ハッシュ>` を渡す。このハッシュには `rustc -vV` の出力が入り、その出力はホストの名前（`host: aarch64-apple-darwin` など）を含む。
- `sou-ruby` が依存する Lindera のクレートは derive のマクロを使う。derive が書く項目の順が、このハッシュから作られる識別子で決まり、ホストごとに変わった。
- ほかの見本は `golem-plugin-sdk` だけに依存し、derive を使わないので、バイト列は変わらなかった。

[docs/adr/0106](0106-sample-plugins-in-rust.md) の再現性の検査は一つのホストの別のディレクトリと Linux amd64 のコンテナだけで、Linux amd64 と macOS arm64 の組み合わせは、derive を使うクレートで試していなかった。

PR #496 は、rustc のラッパー [`plugins/rustc-wrapper.sh`](https://github.com/tett23/golem/blob/97be81e8de344a22a15079b2e56bf0e5ce20ea62/plugins/rustc-wrapper.sh) を足し、[`plugins/build.sh`](https://github.com/tett23/golem/blob/97be81e8de344a22a15079b2e56bf0e5ce20ea62/plugins/build.sh#L24-L26) が `RUSTC_WRAPPER` で使うようにした。
これで `sou-ruby.wasm` は、macOS arm64、Linux arm64、Linux x86-64（`rust:1.99.1`）で同じバイト列になった。
ほかの見本のバイト列は変わらなかった。
仕様書は、この仕組みを [docs/adr/0106](0106-sample-plugins-in-rust.md) の説明の中に書いている（[docs/specifications.md の 3017 行め](https://github.com/tett23/golem/blob/97be81e8de344a22a15079b2e56bf0e5ce20ea62/docs/specifications.md#L3017)）。

このラッパーは、どの ADR にも書かれていない。
2026-11-04 の監査（[docs/audits/2026-11-04-rc4-plugin-adr-conformance.md](../audits/2026-11-04-rc4-plugin-adr-conformance.md) の F-02）は、[docs/adr/0106](0106-sample-plugins-in-rust.md) を補う ADR で記録するよう求めた。

## 実装すること

### ラッパーの規則

`plugins/build.sh` は、cargo に `RUSTC_WRAPPER=plugins/rustc-wrapper.sh` を渡す。
cargo はラッパーを `rustc-wrapper.sh <rustc> <引数>` の形で呼ぶ。
ラッパーは、引数の `metadata=<値>` を次の値に置き換えて、rustc を呼ぶ。

```text
metadata=<パッケージの名前>-<版>-<host か target><,feature="..." の並び>
```

- パッケージの名前と版は、cargo が渡す環境変数 `CARGO_PKG_NAME` と `CARGO_PKG_VERSION` から取る。
- 引数に `--target` があれば `target`、なければ `host` とする。build script と proc macro のクレートはホスト向けに作られ、同じパッケージがターゲット向けにも作られることがあるので、二つを分ける。
- 引数の `feature=...`（`--cfg 'feature="x"'` の値）を、引数の順に `,` でつなぐ。同じパッケージを違う feature で作るときに分けるためである。
- ほかの引数は変えない。`-C extra-filename` も変えないので、`target/` の中のファイルの名前は cargo が作るとおりである。ファイルの名前は `.wasm` に入らない。

置き換えた値は、どれもホストに依らない。
ラッパーは `build.sh` だけが使う。
`cargo test` と、開発者が手で呼ぶ `cargo build` では使われない。
コミットする `.wasm` は `build.sh` で作るので、それで足りる。

### 文書

- docs/specifications.md の「見本のプラグイン」の節の再現性の段落に、この ADR へのリンクを足す。
- `plugins/rustc-wrapper.sh` と `plugins/build.sh` の冒頭のコメントの `docs/adr/0106` に、この ADR を並べる。
- [docs/adr/0106](0106-sample-plugins-in-rust.md) のステータスの行に、「ホストに依らない `-C metadata`（`plugins/rustc-wrapper.sh`）は [ADR 0138](0138-host-independent-crate-metadata-for-plugins.md)」を足す。

## 実装しないこと

- `RUSTFLAGS` で `-C metadata` を渡すこと。`RUSTFLAGS` の値は cargo が付ける引数に足されるだけで、cargo の `-C metadata` を取り除けない。この案は試していない。
- コミットする `.wasm` を、決まった Linux のコンテナの中でだけ作ること。macOS の開発者は、手元で `build.sh --check` を通せなくなる。コンテナの実行環境も要る。
- CI の `plugins` ジョブを macOS でも走らせること。メンテナーは macOS で `.wasm` を作ってコミットするので、ubuntu のジョブが毎回ホストのあいだの一致を確かめている。Linux で作ってコミットしたときは、macOS との一致を CI では確かめない。macOS の開発者が次に `build.sh --check` を走らせたときに見える。
- Lindera の derive の順を、上流で直すこと。ホストに依らないハッシュを使う作りは、上流のクレートが変わっても働く。

## テスト設計

ラッパーは既にあり、ホストのあいだの一致はホストを跨がないと確かめられない。
次の三つで確かめる。

- **CI**：`plugins` ジョブ（ubuntu-24.04）の `sh build.sh --check` が、macOS で作ってコミットした `.wasm` と、Linux で作ったバイト列の一致を毎回確かめる。PR #496 では、ラッパーを足す前に失敗し、足した後に通った。
- **手で確かめたこと**：PR #496 で、`sou-ruby.wasm` を一から作り、macOS arm64、Linux arm64、Linux x86-64（`rust:1.99.1`）で同じバイト列になることと、ほかの見本のバイト列が変わらないことを確かめた。ツールチェーンの版を上げるときは、同じ確認を手で繰り返す。
- **ラッパーの単体テスト**：`plugins/rustc-wrapper-test.sh` を足し、CI の `plugins` ジョブで走らせる。引数をそのまま書き出す偽の rustc を渡し、次のことを確かめる。
  - `-C metadata=abc` が、`CARGO_PKG_NAME` と `CARGO_PKG_VERSION` と `host` からなる値になる。
  - `--target wasm32-unknown-unknown` があれば `target` になる。
  - `--cfg 'feature="a"'` と `--cfg 'feature="b"'` が、書いた順に値に入る。
  - ほかの引数（空白を含む引数を含む）が、順も字も変わらずに rustc に渡る。

単体テストは今のラッパーの振る舞いを固定するもので、書いた時点で通る。
ツールチェーンの版を上げて cargo の引数の形（`-C` と `metadata=` を別の引数で渡す形）が変わったとき、置き換えが黙って働かなくなるのを、CI の `build.sh --check` とあわせて見つけるためである。

## トレードオフ

ラッパーは、cargo が rustc に渡す引数の形に依る。
cargo が `-C metadata` の渡し方を変えると、置き換えが働かなくなり、ホストのあいだの差が戻る。
ツールチェーンは `rust-toolchain.toml` で固定しているので、変わるのは版を上げたときだけである。
そのときは `.wasm` をすべて作り直すので、CI の `build.sh --check` が差を見つける。

置き換えた値は cargo のハッシュより粗い。
同じ名前と版のパッケージを、別の取得元（crates.io と Git）から同じ feature で同時に使うと、二つのクレートの `-C metadata` が同じになる。
そのときに rustc がどう振る舞うかは試していない。
今の `Cargo.lock` に、そうしたパッケージはない（Git から取るパッケージがない）。
依存を足して `Cargo.lock` にそうした組が現れたら、この ADR を見直す。

`cargo build` を手で呼んだときの `.wasm` は、`build.sh` の `.wasm` と違うバイト列になる。
コミットするのは `build.sh` の出力だけなので、害はない。

## 決めたことの記録

- **採択**：メンテナーが、この ADR の案のとおり採択した（2026-11-04）。

## 参考文献

- [docs/audits/2026-11-04-rc4-plugin-adr-conformance.md](../audits/2026-11-04-rc4-plugin-adr-conformance.md)（F-02）
- The Cargo Book, Environment Variables, `RUSTC_WRAPPER` と `CARGO_PKG_NAME`. https://doc.rust-lang.org/cargo/reference/environment-variables.html
- The rustc book, Codegen Options, `metadata`. https://doc.rust-lang.org/rustc/codegen-options/index.html#metadata
