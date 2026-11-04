# ADR 0106: 見本のプラグインを Rust で書き、リポジトリに置く

ステータス: 採択→ホストに依らない `-C metadata`（`plugins/rustc-wrapper.sh`）は [ADR 0138](0138-host-independent-crate-metadata-for-plugins.md)

## 文脈

rc4 では、プラグインの仕組みを実際のプラグインで通すために、見本のプラグインを六つ作る（[docs/roadmap.md](../roadmap.md) の v0.1.0-rc4）。
数の表記、用語集、縦中横のフィルタ、TSV から表を組むコマンド、総ルビ、初出ルビである。
これまでのプラグインは、golem-plugin のテストのために wat（wasm のテキストの形式）で手書きしたものだけであり、CBOR のバイト列を手で組んでいる。
六つのプラグインは IR を読んで書き換えるので、wat では書けない。

そこで、次の四つを決める。

1. どの言語で書き、ゲストの側の共通の部分（CBOR、IR の型、公開する関数）をどう共有するか。
2. どこに置くか（このリポジトリの中か、別のリポジトリか）。
3. どう作り、Golem のテストがどう使うか（作った `.wasm` をコミットするか、CI で作るか）。
4. どう配布するか（[golem-plugin ADR 0002](../golem-plugin/adr/0002-distribution-and-lock.md)）。

[golem-plugin ADR 0001](../golem-plugin/adr/0001-wasm-host-and-abi.md) は、「最初の SDK（Rust）は別のリポジトリで扱う」として、SDK を対象外にしていた。
この ADR はその一文を改める。
理由は「置き場所」の節に書く。

### 試しに実装して分かったこと

この ADR は、採択の前に実装を試した（ブランチ `plugins-foundation`）。
補助のクレートと見本のプラグイン `lookup` を作り、`golem build` で動かした。

- **大きさ**：`lookup`（std を使い、`opt-level = "s"`、LTO、`panic = "abort"`、記号を削る）の wasm は 74031 バイトだった。大半は std の書式化と dlmalloc である。
- **import**：`wasm32-unknown-unknown` に std を使って作っても、モジュールは import を一つも持たなかった。ホストは import を持つモジュールを拒む（G06005）ので、これが前提になる。
- **再現性**：ソースのパスは panic の位置の文字列としてバイナリに入る（`/rustc/<hash>/library/...` と、ワークスペースのパス）。`--remap-path-prefix` でワークスペースと `CARGO_HOME` を固定の文字列に置き換えると、macOS arm64 の二つの異なるディレクトリと、Linux amd64 の `rust:1.99.1` のコンテナ（QEMU）で、同じバイト列になった。
- **ツールチェーン**：手元の既定のツールチェーンは nightly だった。`rust-toolchain.toml` で 1.99.1 に固定し、rustup が入れる。1.99.1 に wasm32 のターゲットを加えたのは、`rustup target add` である。
- **ABI の欠け**：コマンドはインラインの列しか返せない（`response` の `output` は `inlines / document`）。TSV から表を組むコマンドは、ブロックを返す必要があるので、今の ABI では作れない。[docs/adr/0122](0122-block-commands-in-plugins.md) で決める。
- ** diagnostic のコード**：プラグインが返す diagnostic のコードの形が決まっていない。`lookup` は `lookup-no-key` のようなコードにしたが、`golem explain` で引けない。別の草稿（[docs/adr/0108](0108-plugin-diagnostic-codes-and-spans.md)）で扱う。
- **手元で試す経路**：プラグインの `url` は HTTPS に限るので、作ったばかりのプラグインを手元のプロジェクトで試すには、キャッシュのディレクトリに `<SHA-256>.wasm` を置き、`plugins.lock` を手で書くしかなかった。別の草稿（[docs/adr/0109](0109-local-plugin-path.md)）で扱う。

## 実装すること

### 言語と補助のクレート

見本のプラグインは Rust で書く。
Rust は `wasm32-unknown-unknown` に、import のないモジュールを std ごと作れる。
総ルビに使う形態素解析器にも、Rust で書かれ wasm に作れるもの（Lindera など）がある。

ゲストの側の共通の部分は、補助のクレート `golem-plugin-sdk` にまとめる。
このクレートはほかのクレートに依存しない。
CBOR の読み書きは小さく、再実装したほうが、依存するクレートの版と再現性を管理せずに済む。

`golem-plugin-sdk` が公開するものは次のとおりである。

- **`cbor`**：CBOR の値 `Value`、`decode`（長さの決まった項目だけを読み、後ろに余分なバイトがあれば誤り）、`encode`（RFC 8949 の決定的な符号化。整数は最短の頭で書き、浮動小数点数は単精度で表せれば単精度で書く）。
- **`ir`**：意味論 IR（`modules/golem-doc/schema/golem-doc.cddl`）の Rust の型。
  - `Inline` はインラインの十七の種類のすべてを型で持つ。遅延した式は、受け取った CBOR の値のまま持つ（プラグインは作れず、渡すだけなので）。アキの `sp` は `Sp(u64)` とする（[docs/adr/0114](0114-sp-in-a-length-package.md)（長さの型を golem-length に移し、長さを `Sp` で持つ）に合わせ、長さを素の整数で持たない）。
  - `BlockBody` は見出し、箇条書き、番号付きの箇条書き、定義リスト、表、段落を型で持ち、ほかの種類（コード、図版、チャネルの出力、強制改行、改ページの制御、空行）は受け取った CBOR の値のまま `Other` に持つ。見出しの属性も CBOR の値のまま持つ。
  - `Document::map_inlines` は、型で持つブロックのインラインの列を一つずつ書き換える。`Other` の中（図版のキャプションなど）は辿らない。
- **`protocol`**：要求（`Request::Command` と `Request::Filter`）、引数の値 `ArgValue`（整数、有理数、文字列、真偽値、null、配列）、データ `Data`（[docs/adr/0105](0105-plugin-data.md)）、応答 `Response`、diagnostic `Diagnostic`、`golem_describe` の記述 `Description`。
- **`export_plugin!(describe, invoke)`**：`golem_abi_version`、`golem_alloc`、`golem_describe`、`golem_invoke` を公開するマクロ。`describe` は `fn() -> Description`、`invoke` は `fn(Request) -> Response` である。
  - `golem_alloc` と応答の領域は解放しない。ホストは呼び出しごとにインスタンスを捨てるからである（[docs/adr/0031](0031-adr-code-mismatches.md)）。
  - `golem_dealloc` は公開しない。
  - 読めない要求は panic とし、ホストはトラップ（G06009）として報告する。

範囲を表す値は、[docs/adr/0113](0113-closed-range-literal.md)（閉じた範囲を `a...b` と書く）を前提にし、二つの要素の配列の形には依存しない。
範囲の値は、[docs/adr/0113](0113-closed-range-literal.md) のとおり `first` と `last` の二つのキーを持つ CBOR の map で渡る。
今の `ArgValue` は範囲の種類を持たないので、この map を読む範囲の種類を `ArgValue` に足す。

### 置き場所

このリポジトリの `plugins/` に、Cargo のワークスペースとして置く。

```
plugins/
  Cargo.toml            ワークスペースと release のプロファイル
  Cargo.lock
  rust-toolchain.toml   1.99.1、wasm32-unknown-unknown
  build.sh              wasm/ に作る。--check で比べる
  golem-plugin-sdk/     補助のクレート
  lookup/               見本のプラグイン（ディレクトリの名前がパッケージの名前）
  wasm/lookup.wasm      作ったプラグイン（コミットする）
```

別のリポジトリに置かないのは、IR と ABI を変える変更と、それに合わせた補助のクレートとプラグインの変更を、一つのプルリクエストで確かめるためである。
rc4 のあいだは ABI が動く（[docs/adr/0105](0105-plugin-data.md) もその一つ）。
リポジトリが分かれていると、ABI を変えるプルリクエストは、別のリポジトリの変更がマージされるまで、見本のプラグインでテストできない。

### 作り方とテストでの使い方

作った `.wasm` を `plugins/wasm/` にコミットし、Golem のテストはそれを読む。
CI の `plugins` ジョブが、ソースから作り直したバイト列とコミットしたバイト列が一致することを確かめる。

- `plugins/build.sh` は、`--remap-path-prefix` でワークスペースのパスを `/golem/plugins` に、`CARGO_HOME` を `/cargo` に置き換え、`cargo build --release --locked --target wasm32-unknown-unknown` で作り、`wasm/<名前>.wasm` に写す。
- `plugins/build.sh --check` は、写さずに比べ、違えば失敗する。
- `release` のプロファイルは、`opt-level = "s"`、`lto = true`、`codegen-units = 1`、`panic = "abort"`、`debug = false`、`strip = true`、`incremental = false` とする。
- CI の `plugins` ジョブは、`ubuntu-24.04` で `cargo test --locked`（補助のクレートとプラグインの単体テスト）と `sh build.sh --check` を行う。ほかのジョブと同じく、文書だけの変更では省く。
- golem-driver のテストは、`plugins/wasm/<名前>.wasm` を読み、テストの中の HTTPS の取得の偽物で `plugins.lock` とキャッシュを作る（`lockIn` に `.wasm` のファイル名を渡す）。

コミットする案を採るのは、Haskell のテストを走らせるすべての場所（開発者の手元、CI の `build` の二つのアーキテクチャ）に、Rust のツールチェーンを求めずに済むからである。
バイナリとソースの食い違いは、`plugins` ジョブが防ぐ。
このジョブは、ビルドの再現性そのものの検査も兼ねる。

### 配布

見本のプラグインは、Golem のリリースの配布物として、GitHub のリリースに `.wasm` を添える。
利用者は [golem-plugin ADR 0002](../golem-plugin/adr/0002-distribution-and-lock.md) のとおり、URL（`https://github.com/tett23/golem/releases/download/<タグ>/<名前>.wasm`）を `manifest.toml` に書き、`golem plugin lock` でハッシュを固定する。
`release.yml` の変更（`plugins/wasm/*.wasm` を添え、`SHA256SUMS` に加える）は、この ADR の実装に含めるが、試しの実装ではまだ行っていない。

### 見本のプラグインを足す手順

見本のプラグインを足すときは、次のとおりにする。

1. `plugins/<名前>/` に `crate-type = ["cdylib", "rlib"]` のクレートを作り、`golem-plugin-sdk` に path で依存する。パッケージの名前はディレクトリの名前と同じにする。
2. `plugins/Cargo.toml` の `members` に加える。
3. `sh plugins/build.sh` で `plugins/wasm/<名前>.wasm` を作り、`Cargo.lock` と一緒にコミットする。
4. golem-driver のテストでは、`lockIn [("宣言の名前", "<名前>.wasm")] tmp` で読み込む。

辞書などを埋め込むプラグインは、埋め込むもののライセンスをこの ADR とは別の、そのプラグインの ADR に書く。

## 実装しないこと

- Rust 以外の言語の補助のライブラリ。
- 補助のクレートを crates.io に公開すること。ABI が 1.0 で固まるまでは、リポジトリの中だけで使う。
- Component Model と WIT。[golem-plugin ADR 0001](../golem-plugin/adr/0001-wasm-host-and-abi.md) のとおり対象外である。
- `#![no_std]` にして wasm を小さくすること。74 KiB で困っていない。
- 見本のプラグインの wasm の大きさの上限を CI で検査すること。

## テスト設計

- `golem-plugin-sdk` の単体テスト（`cargo test`）：RFC 8949 の付録 A の例の往復、長さの足りない入力、後ろに余分なバイトのある入力、長さの決まっていない配列、UTF-8 でない文字列が誤りになること。インラインの列（ルビ、アキの `Sp`、遅延した式、チャネルの項目を含む）と、`Other` のブロックを含む文書の往復。`map_inlines` が箇条書きの中の段落も辿ること。
- `lookup` の単体テスト：TSV の最初の行が勝つこと、注釈の行と空行を飛ばすこと、コマンドの要求に値を返すこと。
- 再現性：`plugins/` を別のディレクトリに写して `build.sh --check` が通ること、`rust:1.99.1` の Linux amd64 のコンテナで `build.sh --check` が通ることを手で確かめた。CI では `plugins` ジョブが毎回確かめる。
- 結合：golem-driver の `PluginsSpec` が `plugins/wasm/lookup.wasm` を読み込み、データの値が文書に入ることを確かめる（[docs/adr/0105](0105-plugin-data.md) のテスト）。
- 手で確かめたこと：`golem new` で作ったプロジェクトで、`lookup` を `golem build --target text` で動かした。

## トレードオフ

`.wasm` をコミットするので、プラグインを変えるたびにバイナリの差分がリポジトリに残る。
見本のプラグインは数十 KiB なので、受け入れる。
辞書を埋め込んで数十 MiB になるプラグイン（総ルビなど）は、コミットせずに別に置く方法を、そのプラグインの ADR で決める必要がある。

ツールチェーンの版を固定したので、版を上げるとすべての `.wasm` のバイト列が変わる。
版を上げる変更では、`build.sh` で作り直してコミットする。

CI に Rust のジョブが一つ増える。
`cargo test` と release のビルドは、手元では数秒で終わった。
rustup がツールチェーンを入れる時間が加わるが、`build` のジョブと並んで走るので、CI の全体の時間は延びない見込みである。
CI での実際の時間は測っていない。

同じリポジトリに置くので、Golem の CI は、Rust のプラグインが壊れても失敗する。
ABI を変える人がプラグインも直す必要があるが、それがこの置き場所を選んだ理由そのものである。

## 参考文献

- RFC 8949, Concise Binary Object Representation (CBOR), Appendix A. https://www.rfc-editor.org/rfc/rfc8949
- The rustc book, Command-line Arguments, `--remap-path-prefix`. https://doc.rust-lang.org/rustc/command-line-arguments.html
- The rustup book, Overrides, The toolchain file. https://rust-lang.github.io/rustup/overrides.html
- Lindera. https://github.com/lindera/lindera
