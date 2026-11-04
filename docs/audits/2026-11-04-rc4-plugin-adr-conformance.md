# rc4 のプラグインの二十四の ADR と実装の照合（2026-11-04）

この記録は、2026-11-04 の main（5db37cb9、PR #500 のマージの直後）の Golem を、同日に実装した二十四の ADR と照らし合わせた結果である。
対象は、[docs/adr/0105](../adr/0105-plugin-data.md) から [docs/adr/0112](../adr/0112-spread-arguments.md)、[docs/adr/0116](../adr/0116-narrow-reserved-syntax-recovery.md)、[docs/adr/0118](../adr/0118-ref-page-numerals-in-vertical-text.md) から [docs/adr/0132](../adr/0132-setting-command-codes-by-cause.md) と、それぞれを実装したプルリクエスト（#476 から #500）である。
[docs/adr/0113](../adr/0113-closed-range-literal.md)、[0114](../adr/0114-sp-in-a-length-package.md)、[0115](../adr/0115-reserved-syntax-code.md) は 2026-10-28 に #466 から #468 で実装済みなので、この記録ではほかの ADR が書き換えたステータスの行だけを見た。
docs/adr/0117 は存在しない（0116 の次は 0118）。
コードは変えていない。

ソースコードへのリンクは、すべて調べたコミット 5db37cb9 に固定した。

## 目的と範囲

二十四の ADR の「実装すること」「実装しないこと」「テスト設計」の各項目について、コード、テスト、文書（docs/specifications.md、docs/markup.md、docs/diagnostics.md、docs/roadmap.md、manual/、manual-dev/）が ADR のとおりかを調べた。
ADR が指示した、ほかの ADR（[golem-doc ADR 0007](../golem-doc/adr/0007-plugin-channel-lists.md)、[golem-plugin ADR 0001](../golem-plugin/adr/0001-wasm-host-and-abi.md) と [0002](../golem-plugin/adr/0002-distribution-and-lock.md)、[golem-parser ADR 0013](../golem-parser/adr/0013-splat-after-keyword-arguments.md)、[docs/adr/0014](../adr/0014-in-file-settings.md)、0113、0115）のステータスの行の書き換えも見た。
実装者がプルリクエストの本文で申告した逸脱は、妥当かどうかと、ほかの ADR の実装と整合するかを判断した。
判断の基準は、前回の監査（[2026-10-28](2026-10-28-rc4-adr-conformance.md)）と同じく、プロジェクトの原則である「一つの原因に一つのコード」「決定性の対象に diagnostic も含む」「出力を黙って変えない」「緩い規則より厳しい規則」「golem-\* のパッケージのあいだの build-depends は ADR なしに変えない」である。

所見の分類（未実装、逸脱、範囲外の変更、テスト欠落、文書の不一致）と重大度（高、中、低）の定義は前回の監査と同じである。
高は書き手の見る出力か diagnostic が ADR と違うもの、中はプロジェクトの原則か ADR の明示の規則に反するが影響の範囲が狭いもの、低は字面の違いか補助的なものとした。

## 方法

1. 二十四の ADR を全文読み、各プルリクエストの本文と変更したファイルの一覧を `gh pr view` で取った。
2. ADR ごとに、コードとテストと文書を読み、項目ごとに対応する箇所を file:line で特定した。読み取りは ADR を七つの組に分けて分担し、中以上の所見と実装者の申告の判断は、この記録の執筆者がコードを読み直して確かめた。
3. 5db37cb9 を `cabal build all`（GHC 9.10.3、wasmtime の C API は別の checkout の `third_party/wasmtime`）で組み、golem-plugin、golem-eval、golem-parser、golem-project、golem-driver、golem-cli、golem-doc のテストを `cabal test` で実行した。七つのスイートがすべて通った（golem-driver は 968 件、qpdf がないため 1 件を飛ばした）。`plugins/` では `cargo test --locked`（全クレート）と `sh build.sh --check` を実行し、どちらも通った。
4. `golem new` で作った縦組み A6 のプロジェクトに、`plugins/wasm/` の見本を `path` で置き、`golem check` と `golem build` で原稿を試した。試した原稿と結果は各 ADR の節に書く。PDF を目で見る確認（縦中横の箱、横倒しの数字）は、PDF のテキストを取り出す道具がないため行っていない。
5. 決定性の検査の一覧と見た目の回帰テストの不変は、再現していない。プルリクエストの本文の申告と、ゴールデンの一覧が Git の履歴で変わっていないことで判断した。

## [ADR 0105](../adr/0105-plugin-data.md): プロジェクトからプラグインにデータを渡す

### 適合を確かめたもの

- `[plugins.<名前>]` の `data` は `Map Text FilePath` で読み、省略は空、文字列でない値は G03001 である（[Manifest.hs#L182-L187](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-project/src/Golem/Project/Manifest.hs#L182-L187)、[同#L422-L430](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-project/src/Golem/Project/Manifest.hs#L422-L430)）。
- `golem_describe` のデータの名前は英小文字で始まり、英小文字、数字、`-` だけで、違えば `データの名前が不正です`、重複は `データの名前が重複しています`（G06005）である（[Plugin.hs#L204-L207](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-plugin/src/Golem/Plugin.hs#L204-L207)、[同#L421-L426](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-plugin/src/Golem/Plugin.hs#L421-L426)）。
- データは読み込みのときに一度だけ名前の順に `[名前, bstr]` で符号化し、要求の最後の欄に置く（[Plugin.hs#L213-L216](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-plugin/src/Golem/Plugin.hs#L213-L216)、[同#L515](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-plugin/src/Golem/Plugin.hs#L515)）。合計の上限は 64 MiB である。
- パスは `resolveInRoot` で確かめ、ルートの外は G03003、ないファイルは G06101、受け取らない名前は G06102、合計の超過は G06103 で、位置は `manifest.toml` の先頭である（[Driver/Plugins.hs#L228-L255](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-driver/src/Golem/Driver/Plugins.hs#L228-L255)）。`data = { tabel = "w.tsv" }` が G06102 で `プラグインが受け取らないデータの名前です: lookup.tabel（受け取る名前: table）`、`../w.tsv` が G03003 になることを実機で確かめた。
- 読み込みに失敗したとき G02022 と G02090 を抑える（[Driver.hs#L237-L239](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-driver/src/Golem/Driver.hs#L237-L239)）。LSP はデータのファイルを `evTableFiles` で監視し、エディタの内容を優先する。
- CDDL の `data = [* [name: tstr, bytes: bstr]]`、仕様書の「データ」の節、diagnostics.md の G06101 から G06103、両マニュアル、ロードマップの項目の削除は ADR のとおりである。
- [golem-doc ADR 0007](../golem-doc/adr/0007-plugin-channel-lists.md) と [golem-plugin ADR 0001](../golem-plugin/adr/0001-wasm-host-and-abi.md) のステータスの行は、ADR の指示の句を含む。0007 は素の `採択` だったので `採択→` で始めた（申告あり、妥当）。
- テスト設計の項目は golem-plugin の `DataSpec` と golem-driver の `PluginsSpec` にすべてある。
- 申告された二つの逸脱（G06102 の文言に受け取る名前を並べる、driver のテストを `lookup.wasm` でなく `datum.wat` で書く）は妥当である。前者は ADR が文言を決めていない箇所で直し方を示し、後者は 0106 の実装が `lookup.wasm` のテストを足している。

### 所見

**F-01（文書の不一致、低）：テストの名前と冒頭のコメントが「fourth list」のまま。**
[DataSpec.hs#L77](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-plugin/test/DataSpec.hs#L77) は `the fourth list of the description` と書くが、0107 の後は欄に名前があり、位置の数え方は意味を失った。
振る舞いには関係しない。

## [ADR 0106](../adr/0106-sample-plugins-in-rust.md): 見本のプラグインを Rust で書き、リポジトリに置く

### 適合を確かめたもの

- `plugins/` の workspace、`rust-toolchain.toml`（1.99.1、wasm32-unknown-unknown）、`Cargo.lock`、release プロファイルの七つの設定、`build.sh` の `--remap-path-prefix` と `--locked` と `--check`、SDK が他のクレートに依存しないこと、`export_plugin!` が四つの関数を公開し `golem_dealloc` を持たないこと（[plugins/Cargo.toml#L15-L22](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/plugins/Cargo.toml#L15-L22)、[build.sh#L22-L43](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/plugins/build.sh#L22-L43)、[sdk/lib.rs#L94-L121](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/plugins/golem-plugin-sdk/src/lib.rs#L94-L121)）。
- `cbor`、`ir`、`protocol` の各モジュールの規則（余分なバイト、不定長、最短の頭、`Sp(u64)`、`Other(Value)`、`Range`）と単体テスト（RFC 8949 付録 A を含む）。
- CI の `plugins` ジョブ（`cargo test --locked`、`build.sh --check`）、リリースの `plugins/wasm/*.wasm` と `SHA256SUMS`。
- golem-driver の `lookup.wasm` のテスト、仕様書の見本の節、README、manual-dev、[golem-plugin ADR 0001](../golem-plugin/adr/0001-wasm-host-and-abi.md) のステータスの行の追記（申告あり、妥当）。
- 「実装しないこと」（no_std、crates.io、Component Model、大きさの上限）は実装していない。

### 所見

**F-02（範囲外の変更、申告あり、低）：ADR にない `plugins/rustc-wrapper.sh` が `build.sh` に組み込まれ、仕様書は 0106 の説明として書く。**
PR #496（0130）の CI で、`sou-ruby.wasm` が macOS と Linux で違うことが分かり、cargo が `rustc -vV`（ホストの名前を含む）から作る `-C metadata` を、パッケージ名、版、feature、host/target の文字列に置き換える wrapper が入った（[build.sh#L24-L26](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/plugins/build.sh#L24-L26)、[rustc-wrapper.sh](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/plugins/rustc-wrapper.sh)）。
0106 の再現性の検査は同じホストの別のディレクトリと Linux amd64 のコンテナだけで、ホストのあいだの差は見えていなかった。
置き換える値はホストに依らず、CI の `plugins` ジョブ（ubuntu）が macOS で作ってコミットした wasm と一致することを毎回確かめるので、目的（同じソースからは同じバイト列）には沿う。
ただし、[docs/specifications.md#L3017](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/docs/specifications.md#L3017) はこの仕組みを 0106 の説明の中に書くが、0106 にも 0130 にもない。
0106 の補足の ADR で記録するのがよい。

**F-03（逸脱、申告あり、低）：`rust:1.99.1` のコンテナでの `build.sh --check` を PR #482 は行わず、CI に委ねた。**
ADR のテスト設計は手で確かめることを求める。
`lookup.wasm` は一致したので 0106 の範囲では結果に影響はないが、同じ検査を手で行わなかったことが、F-02 の不一致を 0130 まで隠した。

**F-04（文書の不一致、低）：`plugins/wasm/lookup.wasm` だけがモード 100644 で、ほかの七つは 100755 である。**
`git ls-files -s plugins/wasm` で確かめた。
`cmp` には影響しない。

## [ADR 0107](../adr/0107-named-describe-fields.md): `golem_describe` の欄に名前を付ける

### 適合を確かめたもの

- `decodeDescription` はマップ以外と不定長を `golem_describe の形が不正です`、未知の欄、重複の欄、配列でない値をそれぞれの文言で拒み、書かない欄は空とし、欄の順を問わない（[Plugin.hs#L379-L434](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-plugin/src/Golem/Plugin.hs#L379-L434)）。古い配列の形は `TList` の枝で拒む。
- CDDL のマップ、ABI は 8 のまま、SDK は空でない欄だけを 4.2.1 の順に書く（[protocol.rs#L226-L251](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/plugins/golem-plugin-sdk/src/protocol.rs#L226-L251)）。wat のテスト用プラグイン 15 本と manual-dev の wat の例（`\a1\67filters\81\64same`、15 バイト）は書き換わっている。
- テスト設計の八つは `DataSpec.hs#L130-L165` にある。申告された二つの逸脱（`blocks` を CDDL に先に書いたこと、テストの置き場）は、0122 の実装の後は不一致がなく、妥当である。
- ABI のバージョンは、コード（golem-plugin、golem-doc の CDDL）、SDK、仕様書、manual-dev の 05-plugins.gm で 8 に一致する。

### 所見

**F-05（文書の不一致、中）：開発者のマニュアルの IR の章が、`golem_describe` の「三つ目のフィールド」と「ABI のバージョンは 7 のまま」を書く。**
[manual-dev/part1/06-ir.gm#L440](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/manual-dev/part1/06-ir.gm#L440) は「宣言は `golem_describe` の応答の三つ目のフィールドで」、[同#L450](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/manual-dev/part1/06-ir.gm#L450) は「ABI のバージョンは 7 のままである」と書く。
前者は 0107 の後では誤りで、欄は `channels` という名前である。
後者は前回の監査の F-03（05-plugins.gm の「ABI 7」）と同じ誤りの別の箇所で、PR #488 が 05-plugins.gm の行を 8 に直したとき、この行は残った。
0107 の「開発者のマニュアルの wat の例の記述を書き換える」は 05-plugins.gm を指すので ADR への違反ではないが、main の文書は常に最新であるという規則に反する。

**F-06（範囲外の変更、低）：PR #483 が 0105 と [golem-doc ADR 0007](../golem-doc/adr/0007-plugin-channel-lists.md) のステータスの行を書き換えたが、0107 にその指示がない。**
[0105#L3](../adr/0105-plugin-data.md) と [0007#L3](../golem-doc/adr/0007-plugin-channel-lists.md) に「`description` の形は docs/adr/0107」が足されている。
ステータスの行は書き換えてよい唯一の行で、読み手には有益であり、慣行にも合う。
ADR に書かずに行ったことだけを記録する。

## [ADR 0108](../adr/0108-plugin-diagnostic-codes-and-spans.md): プラグインが返す diagnostic のコードと位置を検査する

### 適合を確かめたもの

- `pluginCode` は空でなく ASCII 小文字、数字、`-` だけを許し、違えば `診断のコードの形が不正です: <コード>`（[Plugin.hs#L814-L819](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-plugin/src/Golem/Plugin.hs#L814-L819)）。ホストは `ofPlugin` で `<宣言名>/<コード>` にする（[Driver/Plugins.hs#L195-L196](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-driver/src/Golem/Driver/Plugins.hs#L195-L196)）。`golem_check_data` の diagnostic にも同じ検査が効く。
- `checkDiagnosticSpans` は位置を呼び出しか要求のノードに限り、フィルタにはファイルの先頭も許す（[Plugin.hs#L698-L701](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-plugin/src/Golem/Plugin.hs#L698-L701)、[同#L672](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-plugin/src/Golem/Plugin.hs#L672)）。
- `golem explain lk/no-key` が標準出力に一行を書いて終了コード 0、`golem explain lk/No-key` が終了コード 2 になることを実機で確かめた。
- `datum.wat` と `lookup` の修正、テスト設計の項目（golem-plugin の `ResponseSpec`、golem-driver、golem-cli）、文書、新設コードなし。

### 所見

**F-07（文書の不一致、中）：docs/diagnostics.md の G06009 と G06005 の節が、この日の五つの ADR が足した理由の文言を載せていない。**
G06009 の節（[diagnostics.md#L5328-L5345](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/docs/diagnostics.md#L5328-L5345)）は、データの検査とチャネルの項目の文言までを列挙するが、0108 の `診断のコードの形が不正です: <コード>` と `診断が要求にないソース位置を指しています`、0122 の `ブロックコマンドの出力は [ブロックの列, 画像の列] です`、`ブロックコマンドが返せないブロックです: <種類>`、`ブロックコマンドの出力はラベルを持てません`、0123 の画像の八つの文言（`画像の名前が不正です` ほか）がなく、ADR の行に 0108、0122、0123 がない。
`rg '診断のコードの形|要求にないソース位置' docs manual manual-dev` は 0 件である。
G06005 の節（[同#L5232-L5234](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/docs/diagnostics.md#L5232-L5234)）は欄の名前を `commands`、`filters`、`channels`、`data` の四つと書き、コードの `fields` の六つ（[Plugin.hs#L404](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-plugin/src/Golem/Plugin.hs#L404)）に `context`（0121）と `blocks`（0122）が足りず、0121 の `文脈の名前が重複しています`、0122 のブロックコマンドの名前の三つの文言もない。
仕様書には書いてあるので、利用者が `golem explain G06009` で見る説明だけが遅れている。
五つのプルリクエストのどれも申告していない。

**F-08（逸脱、申告あり、低）：コードの先頭の数字と `-` を許す。**
[Plugin.hs#L817](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-plugin/src/Golem/Plugin.hs#L817) は先頭の文字を区別しないので、`-`、`0` も通る。
ADR の文言「英小文字、数字、- の列」には忠実である。
一方、データの名前、ブロックコマンドの名前、スタイルの名前は「英小文字で始まる」を課しており、「緩い規則より厳しい規則」からは不ぞろいである。
厳しくするなら修正用の ADR が要る。

**F-09（範囲外の変更、低）：PR #499 が bar-chart のコードを ADR なしに変えた。**
[bar-chart/lib.rs#L123-L133](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/plugins/bar-chart/src/lib.rs#L123-L133) は `key`、`name`、`alt`、`no-data`、`tsv`、`values` を返し、仕様書とテストも直っている。
0123 はコードの名前を決めていないので ADR への違反ではなく、0108 の「後ろの部分だけを返す」趣旨に合う。
ただし、仕様書に書かれていた利用者の見るコードを ADR なしに変えたこと、そして同じ日の sou-ruby と first-ruby は逆の形のままであること（F-38）を記録する。

**F-10（低、ADR の要求外）：`golem explain` は `/` の前の部分を空白以外なら何でも受ける。**
[cli/Main.hs#L160-L163](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-cli/app/Main.hs#L160-L163)。
`golem explain G01017/x` がプラグインのコードとして終了コード 0 になることを実機で確かめた。
manifest の宣言名に形の規則がないので誤りとは言えない。

## [ADR 0109](../adr/0109-local-plugin-path.md): プロジェクトの中のプラグインを `path` で宣言する

### 適合を確かめたもの

- `PluginSource` の `PluginUrl` と `PluginPath`、`url` と `path` はちょうど一つ（[Manifest.hs#L183-L198](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-project/src/Golem/Project/Manifest.hs#L183-L198)、[同#L420-L429](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-project/src/Golem/Project/Manifest.hs#L420-L429)）。
- ないファイルは G06104、ルートの外は G03003、lock もキャッシュも見ない（[Driver/Plugins.hs#L81-L89](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-driver/src/Golem/Driver/Plugins.hs#L81-L89)）。`plugins/none.wasm` が G06104、`../x.wasm` が G03003、`url` と `path` の両方が G03001 `プラグインには url と path のどちらか一方だけを書きます (plugins.lk)` になることを実機で確かめた。
- `golem plugin lock` は `PluginUrl` だけを渡し、`fetch` は plugins.lock だけを読む。LSP は `path` を `evTableFiles` に入れる。
- テスト設計の項目、文書、新設コード G06104、[golem-plugin ADR 0002](../golem-plugin/adr/0002-distribution-and-lock.md) のステータスの行（申告あり、妥当）。

### 所見

**F-11（文書の不一致、低）：G03003 の節が章と `@import` のパスしか挙げない。**
[diagnostics.md#L3906-L3930](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/docs/diagnostics.md#L3906-L3930) の意味、主な原因、直し方は「章や `@import` のパス」だけで、プラグインの `path` とデータのパス（0105）が G03003 になることを書いていない。
G06104 の節と仕様書は G03003 に送っている。

**F-12（テスト欠落、低）：プラグインの `path` のシンボリックリンクのルート外は未テストである。**
データには [PluginsSpec.hs#L981-L987](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-driver/test/PluginsSpec.hs#L981-L987) があるが、`path` にはない。
`resolveInRoot` を共有するので動くはずだが、未確認である。

## [ADR 0110](../adr/0110-keyword-arguments-to-plugins.md): キーワード引数をプラグインに名前ごと渡す

### 適合を確かめたもの

- `PluginArg = PluginPositional | PluginKeyword`、`pcCall :: [PluginArg] -> ...`、`argumentTerm` が `[0, value]` と `[1, key, value]` を書く（[Value.hs#L39-L51](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-eval/src/Golem/Eval/Value.hs#L39-L51)、[Plugin.hs#L498-L502](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-plugin/src/Golem/Plugin.hs#L498-L502)）。CDDL の `argument` は変わらず、ABI は 8 のまま、SDK は変更なし。
- 評価器の `pluginArgs` は原稿の順を保ち、同じキーは展開と同じ `uniqueKeys` で G02077 にして最初を残す（[File.hs#L586-L590](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-eval/src/Golem/Eval/File.hs#L586-L590)、[同#L2008-L2013](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-eval/src/Golem/Eval/File.hs#L2008-L2013)）。組み込みのコマンドは AST から読む方式のままである。
- テスト（golem-plugin の `NumbersSpec`、golem-eval の `FileSpec`）、仕様書、manual-dev、ロードマップの項目の削除。
- 申告（driver の wat のテストを書かず、golem-plugin で要求のバイト列を試す）は妥当である。ADR は見本を使うテストを後回しにすると明記し、結合は 0125 と 0129 のテストが `PluginsSpec` で通している。

所見はない。

## [ADR 0111](../adr/0111-argument-words-as-number-literals.md): 数のリテラルの形をした引数の語を数として読む

### 適合を確かめたもの

- `wordNumber` は先頭の `-` を一つだけ許し、数字だけは `VNat`、`-` と数字は `VInt`、小数と指数は `VRat` にする。`+3`、`.5`、`5.`、`1-2` などは文法の `literal` で弾かれて文字列である（[File.hs#L2095-L2107](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-eval/src/Golem/Eval/File.hs#L2095-L2107)、[Lower.hs#L364-L386](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-parser/src/Golem/Parser/Lower.hs#L364-L386)）。
- 対象は `A.Word` を `argValue` で読む箇所（`[number-text ...]` の数とプラグインの引数）で、`shape=`、`style=`、コードブロックのキーは字のままである。int64 超えは G02091、指数 1300 超は G02086。
- `<数>...<数>` の語は、範囲を受け取らない箇所では G02113（メッセージは ADR と一字一句同じ、[File.hs#L2158](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-eval/src/Golem/Eval/File.hs#L2158)）、プラグインには範囲の値である。`[number-text 1...3]`、`@blank-line 1...3`、`numbers=5...5` が G02113 になることを実機で確かめた。
- テスト設計の項目は `FileSpec.argWordTests` と `NaturalSpec` にある。docs/markup.md、diagnostics.md（G02113 の新設と G02019、G02069、G02086、G02092 の改訂）、両マニュアルは ADR のとおりである。

### 所見

**F-13（逸脱、申告あり、中）：`numbers=5...5` と `numbers=[= 1...3]` を G02069 から G02113 に変え、0113 の明示の決定を 0111 の一般規則で上書きした。**
[0113#L260-L263](../adr/0113-closed-range-literal.md) は「`numbers=5-5`、`numbers=5...5`、`numbers=[= 1...3]` は、今の…G02069 にする」と決め、テスト設計にも書いた。
0111 は `numbers` を一度も挙げず、文脈で「[ADR 0113](../adr/0113-closed-range-literal.md) は、範囲を受け取らない引数に範囲の値を渡したときのコードを決めていない」と書くが、`numbers` については決めていたので、この前提は事実と違う。
一方、0111 の規則の本文（自然数を求める箇所の `<数>...<数>` の語と、範囲を受け取らない組み込みの引数に届いた範囲の値は G02113）は `numbers` に当たる。
実装（[File.hs#L2331-L2354](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-eval/src/Golem/Eval/File.hs#L2331-L2354)）は `@blank-line 1...3` と `numbers=1...3` を同じコードにするので「一つの原因に一つのコード」に沿い、判断としては妥当である。
しかし、二つの ADR が同じ入力に別のコードを与えており、実装者がどちらかを選ばざるを得なかった。
0113 のステータスの行の追記は内容としては正確だが、0111 に指示はない。
0111 の文脈の誤りを実装で補ったことを、記録に残す。
`numbers=5-5` は G02069 のままで、0113 と矛盾しない。

**F-14（逸脱、申告なし、中）：コードブロックの `file`、`diff`、`callouts`、`lang` に式の範囲を書くと、G02113 と G02069 の二つが出る。**
申告は「`file` などの式の値が範囲のとき G02069 から G02113 に変えた」であるが、実機では ```` ```haskell file=[= 1...3] ```` が `error[G02069]: file の値が正しくありません: `（値が空）と `error[G02113]: 範囲を受け取らない引数に範囲を書いています: 1...3` の二つになる。
`scalar` は `plainArgValue` の `Left d` を報告して `Nothing` を返し、呼び手は `Nothing` を「読めない値」として G02069 を空の値で出す（[File.hs#L1600-L1614](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-eval/src/Golem/Eval/File.hs#L1600-L1614)）。
一つの原因（範囲を受け取らないキーに範囲を書いた）に二つのコードが出ており、G02069 のメッセージの値が空であることも、書き手に誤りの場所を示さない。
`FileSpec` にこの組み合わせのテストはなく、PR #479 の本文は G02113 だけを書く。
同じキーに語で `file=1...3` と書くと字のままで誤りにならないことは、ADR が「字として読む箇所は規則の外」としたとおりで、逸脱ではない。
ただし、diagnostics.md の G02113 の節（[同#L3720](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/docs/diagnostics.md#L3720)）がこれらのキーを対象に挙げるとき、式に限ることを書いていない。

**F-15（逸脱、申告あり、低）：`[number-text [= -1...1.5]]` は G02104、語の `[number-text -1...1.5]` は G02113 で、語と式のコードが違う。**
実機で確かめた。
式では範囲の値を作る時点で端が整数でないので G02104 になり、語は形で先に判定して G02113 になる（[File.hs#L2141](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-eval/src/Golem/Eval/File.hs#L2141)）。
ADR の「語と式で同じ原因には同じコード」と、テスト設計の例（語の `-1...1.5` を G02113）が、`-1...1.5` が範囲として成立しない値であるために両立しない。
ADR 自身の例の不備であり、実装はテスト設計に従った。
整理する ADR が要る。

**F-16（文書の不一致、低）：G02113 の位置が「引数」と書かれているが、`[number-text ...]` と自然数を求めるブロックコマンドではコマンドの位置になる。**
`[number-text 1...3]` の G02113 が 3:4（`[` の位置）に出ることを実機で確かめた。
ADR と [diagnostics.md#L3724](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/docs/diagnostics.md#L3724) 付近は位置を引数とする。
`builtinWith` が引数の span を捨ててコマンドの span を渡す既存の慣行（G02019、G02103、G02104 も同じ）によるもので、0111 だけの問題ではない。
コードブロックのキーだけが引数の位置になる。

## [ADR 0112](../adr/0112-spread-arguments.md): `*[式]` と `**[式]` をすべてのコマンドの引数に展開する

### 適合を確かめたもの

- 展開は `prepareArgs` の一か所で、配列を位置引数、連想配列をキーの順にキーワード引数にし、空は何も出さず、位置は展開の引数の span である（[File.hs#L2022-L2043](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-eval/src/Golem/Eval/File.hs#L2022-L2043)）。インラインのコマンド、ブロックコマンド、コードブロックの開始の行、属性、プラグインに当たる。
- G02111、G02112、G02114 のメッセージは ADR と一致し、誤りのときコマンドを実行しない。G02077 は添字で見分け、後のキーを除いて実行を続ける。
- 語だけの位置（`@page-break`、`@page-lines`、`@label`、`@style`、`[style ...]`）は `nameArg` で語と文字列を同一視する。`@manifest` と `@style-def` は展開の引数ごとに G02114、`@style` は本体と属性の形で G02114。
- テスト設計の全項目が `FileSpec.spreadTests` にある。docs/markup.md の「引数」、diagnostics.md の三つの新設と G02077、G02052 の改訂、両マニュアル、ロードマップの項目の削除は ADR のとおりである。
- [golem-parser ADR 0013](../golem-parser/adr/0013-splat-after-keyword-arguments.md) のステータスの行の書き換えは 0112 に指示がなく、変更は不要である。

### 所見

**F-17（逸脱、申告なし、低）：`@import` の引数にも `prepareArgs` が走る。**
ADR は「`@import` は変えない。……展開を書いた `@import` は、今のとおり形の誤り（G03009）である」と書く。
評価器は `@import` を `standalone` で読むが、その前に [File.hs#L485](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-eval/src/Golem/Eval/File.hs#L485) の枝で `prepareArgs` が走り、`@import *[1]` なら G02111 を報告して進まない。
プロジェクトでは `importsOf` が G03009 を見つけると評価に進まないので、出力は変わらない。
影響はプロジェクトの外の単一ファイルの評価に限られ、そこでは G03009 の代わりに G02111 や式の誤りが出る可能性がある（実機では未確認）。
diagnostics.md と markup.md の「`@import` の展開は G03009」は、この経路では成り立たない。

**F-18（逸脱、申告なし、低）：`@style` に展開を二つ書いても G02114 は最初の一つしか出ない。**
`@style *[["a"]] **[{b: 1}]` で G02114 が一つだけ出ることを実機で確かめた（`(ssp : _) <- spreadsOf args`、[File.hs#L484](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-eval/src/Golem/Eval/File.hs#L484)）。
`@manifest` と `@style-def` は展開の引数ごとに出す。
ADR の「位置は、どれも展開の引数」は引数ごとを含意し、三つのコマンドで振る舞いが揃っていない。
決定性は保たれる。

## [ADR 0116](../adr/0116-narrow-reserved-syntax-recovery.md): 予約された記法の回復を記法の分だけに狭める

### 適合を確かめたもの

- `%recover reserved SkipReserved`、`SkippedReserved`、`ReservedBracketBody`、`ReservedRange` は ADR の PEG と一字一句同じである（[Golem.hpeg#L62](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-parser/grammar/Golem.hpeg#L62)、[同#L437-L449](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-parser/grammar/Golem.hpeg#L437-L449)、[同#L729-L747](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-parser/grammar/Golem.hpeg#L729-L747)）。
- テスト設計の二つの表の全行が `narrowReservedTests`（[ParserSpec.hs#L288-L365](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-parser/test/ParserSpec.hs#L288-L365)）にある。
- `本文 [!x] です。` の次の行の `[` が G01100 と G01021 の二つ、`@!foo` の字下げした本体が G01100 と G01011、`[= f(1..3)]` が G01100 だけになることを実機で確かめた。
- diagnostics.md の G01100 の追記、0113 と 0115 のステータスの行、「実装しないこと」の違反なし。

### 所見

**F-19（テスト欠落、低）：ロスレス性のテストが入力の一部だけを対象にしている。**
ADR は「上の入力のそれぞれで、`parse` の木のテキストが入力と一致すること」とするが、[ParserSpec.hs#L342-L355](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-parser/test/ParserSpec.hs#L342-L355) は 10 個の入力だけである。
回復の分岐は網羅しているので、実質の抜けは小さい。

## [ADR 0118](../adr/0118-ref-page-numerals-in-vertical-text.md): 縦組みの `[ref-page]` のページ番号の表記

### 適合を確かめたもの

- `stNumbersRefPage`、`[numbers] ref-page` の六つの値、G03006（[Style.hs#L1684-L1690](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-project/src/Golem/Project/Style.hs#L1684-L1690)）。`ceRefPageNumbers`、`piecesOf` の `Ref sp RefPage` が縦組みで `numberPieces` を使う（[Japanese.hs#L287-L293](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-layout/src/Golem/Layout/Japanese.hs#L287-L293)）。横組み、索引、目次、HTML、テキストの経路は変わっていない。
- テスト設計の五つは `ReferencesSpec.refPageNumeralTests`、golem-project の三点はそのテストにある。仕様書、diagnostics.md、両マニュアル。
- 出力の変化（縦組みの `[ref-page]` の既定が漢数字になる）は ADR が予告したものである。

### 所見

**F-20（テスト欠落、低）：既定の出力が変わる縦組みの `[ref-page]` を、ゴールデンも見た目の回帰も捉えていない。**
PR #476 が変えた `scripts/visual/pages/manual.txt` はマニュアル（横組み）の本文の追記によるもので、縦組みの `[ref-page]` を含む固定資料はリポジトリにない。
`refPageNumeralTests` は行の文字列だけを見るので、`tcy` が縦中横の箱になることは未検証である（ADR 自身が既存の経路に任せると書く）。
この監査でも PDF を目で見る確認はしていない。

## [ADR 0119](../adr/0119-plugin-data-of-any-name.md): どんな名前のデータも受け取るプラグイン

### 適合を確かめたもの

- `takesData` は `["*"]` のときだけ名前の形で判定し、`["*", "table"]` は `データの名前が不正です: *` である（[Plugin.hs#L196-L199](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-plugin/src/Golem/Plugin.hs#L196-L199)、[同#L421-L423](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-plugin/src/Golem/Plugin.hs#L421-L423)）。G06102 の文言は「受け取る名前: 英小文字で始まる任意の名前」。
- データは `Map` の名前の順に読み、符号化するので、`*` でも決定的である。
- テスト（golem-plugin、golem-driver）、文書。申告（`tsv-table` のテストを `datum.wat` で置き換えた）は、0129 の実装が二つの表のテストを足したので、今は ADR のテスト設計を満たす。

所見はない。

## [ADR 0120](../adr/0120-plugin-data-check-at-load.md): プラグインのデータを読み込みで一度だけ検査する

### 適合を確かめたもの

- 任意の export `golem_check_data` を `golem_plugin_has_export` で見て、読み込みの直後に一度だけ呼ぶ（[Driver/Plugins.hs#L108-L109](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-driver/src/Golem/Driver/Plugins.hs#L108-L109)）。要求 `[data]`、応答の復号、コードは `pluginCode` と共用、エラーなら読み込みの誤りとして G02022 と G02090 を抑え、警告だけなら読み込む。
- 位置はデータのファイルの行の先頭で、FileId は lock の次から振る（[同#L203-L216](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-driver/src/Golem/Driver/Plugins.hs#L203-L216)）。
- 用語集の見本で、`terms.tsv` の 2 行めの欄を一つ減らすと `terms.tsv:2:1: error[glossary/tsv-columns]: terms の 2 行めの欄の数が 3 か 4 ではありません` が一度だけ出て終了コード 1 になることを実機で確かめた。
- CDDL、仕様書、diagnostics.md の G06009、両マニュアル、テスト（`CheckDataSpec`、`PluginsSpec`）。PR #488 が manual-dev の「ABI 7」を 8 に直したのは範囲外だが正しい（F-05 の同種の行は残った）。
- 申告された「ファイルにない行を指す応答は G06009」は、ADR が決めていない箇所を黙って丸めずに拒むもので、妥当である。

### 所見

**F-21（逸脱、申告あり、中）：「`name` が宣言にない名前なら G06009」を「渡していない名前なら G06009」と読んだ。**
[0120#L24](../adr/0120-plugin-data-check-at-load.md) は「宣言にない名前」、実装は `渡していないデータの名前です`（[Driver/Plugins.hs#L204-L205](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-driver/src/Golem/Driver/Plugins.hs#L204-L205)）である。
`*` を宣言するプラグイン（0119）では「宣言にある名前」が定義できず、ファイルがなければ行の位置も作れないので、実装の選択は妥当で、厳しい側に寄せる原則にも合う。
ただし代価がある。
0120 の文脈は、原稿にコマンドを書いたかどうかで誤りが見えるかどうかが変わることを問題にしたが、この規則では「必須のデータが渡されていない」ことを `golem_check_data` で報告できない（名前を返せば G06009 になる）。
用語集の見本に `data` を書かずに `[term: 組版]` を書くと、読み込み時には何も出ず、呼び出しの位置に `glossary/no-data` が出ることを実機で確かめた。
`[term]` のない本では見えない。
ADR の文面からは外れないが、ADR が意図した穴の一部が残る。
`name` を null にして `manifest.toml` の先頭を指す形などを足すかは、別の ADR かロードマップの未決事項にするのがよい（今のロードマップにはない）。

**F-22（テスト欠落、低）：`CheckDataSpec` が ABI を `"8"` と直書きしている。**
[CheckDataSpec.hs#L33](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-plugin/test/CheckDataSpec.hs#L33)。
`DataSpec` は `abiVersion` を使う。
ABI を上げたときにこのテストだけが壊れる。

## [ADR 0121](../adr/0121-host-context-in-plugin-requests.md): プラグインが本の文脈を宣言して受け取る

### 適合を確かめたもの

- `contextNames = ["vertical-numbers", "writing-mode"]`、知らない名前は `UnknownContext` で G06105（`manifest.toml` の先頭、`<プラグイン>: ` を前置）、重複は G06005（[Plugin.hs#L174-L175](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-plugin/src/Golem/Plugin.hs#L174-L175)、[同#L246](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-plugin/src/Golem/Plugin.hs#L246)、[Driver/Plugins.hs#L101-L102](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-driver/src/Golem/Driver/Plugins.hs#L101-L102)）。
- `withPluginContext` は宣言した名前だけをコードポイント順に、データの前に置く。宣言なしは空配列で、縦横で同じバイト列になる。値は `style.toml` の字と同じで、既定は `horizontal` と `kanji`。
- 文脈を宣言したプラグインがあるときだけ `style.toml` を監視する（[Driver.hs#L235-L236](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-driver/src/Golem/Driver.hs#L235-L236)）。
- CDDL、ABI 8 のまま、SDK、テスト設計の項目（`ContextSpec`、`PluginsSpec`）、仕様書、diagnostics.md の G06105、manual-dev、付録 E。
- 申告された二つの逸脱（`loadPlugins` の型に 0120 の `FileId` と `LoadedPlugins` が入る、四つの欄の記述のテストを書かない）は妥当である。

### 所見

**F-23（文書の不一致、低）：使い手のマニュアルのコードの範囲が古い。**
[manual/chapters/10-plugins.gm#L53](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/manual/chapters/10-plugins.gm#L53) は「G06101 から G06104」と書き、仕様書と manual-dev の G06105 と食い違う。
0121 の文書の節は使い手のマニュアルを挙げていないが、main のマニュアルは常に最新であるべきである。

G06005 の節に `context` がないことは F-07 にまとめた。

## [ADR 0122](../adr/0122-block-commands-in-plugins.md): プラグインのブロックコマンド

### 適合を確かめたもの

- `standalone` は組み込み、ファイルの設定、属性の順に調べ、どれでもなければ `phBlocks` を引き、なければ G02009（[File.hs#L504-L543](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-eval/src/Golem/Eval/File.hs#L504-L543)）。引数はインラインと同じ経路、本体は評価して渡す、int64 超えは G02091。
- 宣言の検査（形、重複、組み込みの名前）、G06006、要求 `[2, name, args, body, span, context, data]`、返せるブロックの種類とラベルの拒否（`blockKind`、[Plugin.hs#L629-L647](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-plugin/src/Golem/Plugin.hs#L629-L647)）、本体から来たブロックは検査を免れる、位置は呼び出しか本体。
- 申告された「要求に文脈が入る」は、0121 の「文脈はデータの前」がすべての要求に及ぶので妥当である。「`set` を `builtinBlockCommands` に入れ、`=` のない `@set` は G02009」は、パーサーが `=` のない `set` を一般のブロックコマンドにする既存の振る舞い（[Lower.hs#L158-L163](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-parser/src/Golem/Parser/Lower.hs#L158-L163)）の上で、`@set` の書き違いをプラグインが拾う事態を防ぐもので、妥当である。`@set foo` が `G02009 未知のブロックコマンドです: @set` になることを実機で確かめた。
- `@tsv-table sales x=1` と `@tsv-table` が `tt/key` と `tt/name` を呼び出しの行に出すことを実機で確かめた（0129 の見本、宣言名 `tt`）。
- テスト（`BlockSpec`、`FileSpec`、`PluginsSpec`）、docs/markup.md、仕様書、diagnostics.md の G02009 と G06006、両マニュアル。

### 所見

**F-24（文書の不一致、低）：docs/markup.md がブロックコマンドの返せるものに図版を挙げない。**
[markup.md#L292](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/docs/markup.md#L292) は「段落、リスト、定義リスト、表、コードブロックを返し」と書く。
0123 の後は図版も返せる（仕様書は直っている）。
PR #491 は markup.md を触っていない。

G06009 の節にブロックコマンドの文言がないことは F-07 にまとめた。

## [ADR 0123](../adr/0123-figures-from-plugins.md): プラグインが作った画像の図版

### 適合を確かめたもの

- 応答 `[blocks, images]`、画像 `[name, format, bytes]`、名前の形と重複、形式 svg/png/jpeg、合計 64 MiB、`plugin:` の `src`、応答にない名前、使われない画像、`web`、箇条書きと定義リストの中の図版をそれぞれの文言で拒む（[Plugin.hs#L582-L624](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-plugin/src/Golem/Plugin.hs#L582-L624)）。名前は SHA-256 と拡張子、`golem-plugin-image://` の前置、HTML と EPUB の `images/golem-plugin/`。
- `checkFigure` は `@figure` と同じ順に同じ関数で検査し、通らなければブロックなし。画像は `erImages` から `bookImages` へ運ばれ、PDF は読み、HTML は書き出し、EPUB は本から読む。
- 見本 bar-chart を `path` で宣言した本を四つのターゲットで組むと、`build/html/images/golem-plugin/<sha>.svg` が書かれ、テキストに `［図1-1　売り上げ］` と `図1-1。` が出て、PDF を二度組んだバイト列が同じであることを実機で確かめた。
- テスト（`FileSpec` の十二の図版、`BlockSpec` の画像、`PluginsSpec` の bar-chart）、文書。golem-eval に `bytestring`、golem-epub に `containers` が足されたが、どちらも golem-\* ではなく、ADR の文脈に記載がある。
- 申告された「検査に通らない図版の画像を残さない」は、ブロックのない画像を誰も参照しないので一貫し、妥当である。

### 所見

**F-25（逸脱、申告あり、中）：「実装しないこと」に書いた G08102 を実装した。**
[0123#L111](../adr/0123-figures-from-plugins.md) は「原稿の図版の出力のパスが `images/golem-plugin/` と重なるときのエラー。試しの実装には入れていない。採択の前に、コード G08102…と一緒に足す」を「実装しないこと」の中に置いたまま採択された。
実装は [Driver.hs#L684-L692](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-driver/src/Golem/Driver.hs#L684-L692) で前方一致を見、HTML と EPUB を止めて PDF とテキストは書く。
`@figure images/golem-plugin/a.svg alt=x` を HTML を含む本で組むと G08102 が出て `build/` に pdf と text だけが書かれ、`--target pdf` では出ないことを実機で確かめた。
プラグインを使わない本にも出る新しいエラーで、文言、重大度、出す条件を ADR の本文なしに実装側が決めている。
原則（厳しい規則、黙って取り違えない）には沿い、diagnostics.md、仕様書、両マニュアル、テストもそろっている。
ADR の「実装しないこと」との矛盾は残るので、短い修正の ADR で記録に残すべきである。

**F-26（逸脱、申告なし、中、実機未確認）：図版のキャプションの中の図版が「最上位でない図版」として拒まれない。**
ADR は「出力の最上位でない図版（箇条書きの中など）」を G06009 とする。
`placeImages` の `nested` と `inner` は箇条書きと定義リストの中だけを見て `FigureBlock` のキャプションに降りず（[Plugin.hs#L616-L624](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-plugin/src/Golem/Plugin.hs#L616-L624)）、`place` も最上位だけを置き換え、`blockKind` はキャプションの中の `FigureBlock` を種類として許す（[同#L641](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-plugin/src/Golem/Plugin.hs#L641)）。
IR の `validateBlocks` もキャプションの中の図版を拒まない。
したがって、最上位の図版のキャプションに `src = "plugin:x"` の図版を入れた応答は検査を通り、`plugin:x` が置き換えられないまま IR に残り、`checkFigure` も通らない。
原稿の `@figure` のキャプションに `@figure` を書けるので、IR の形としては起こりうる。
ADR の条件「原稿の図版の検査を一つも迂回しない」の穴になる。
コードの読みによる指摘で、範囲は狭い。
`BlockSpec` に、キャプションに `plugin:` の図版を持つ応答を足して確かめるのがよい。

**F-27（文書の不一致、低）：`FileSpec` のコメントが `docs/adr/NNNN-figures-from-plugins` のまま。**
[FileSpec.hs#L405](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-eval/test/FileSpec.hs#L405)。
一段めのブランチの番号の仮置きである。

**F-28（テスト欠落、申告あり、低）：一段め（`checkFigure` への分解）の「出力を変えないこと」を本実装では比べていない。**
ADR は試しの実装で決定性の一覧と見た目の回帰テストの一致を確かめたと書くが、PR #491 は本実装で前後を比べず、`OutputGoldenSpec` と視覚リファレンスの不変で代えている。
ゴールデンが通れば実質は担保される。

## [ADR 0124](../adr/0124-filter-fuel-by-document-size.md): フィルタの命令の数の上限を文書の大きさに比例させる

### 適合を確かめたもの

- `filterFuel base bytes = base + 10000 × bytes`、文書のバイト数は要求に入れる文書の CBOR で、データは数えない（[Plugin.hs#L119-L127](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-plugin/src/Golem/Plugin.hs#L119-L127)、[同#L656-L661](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-plugin/src/Golem/Plugin.hs#L656-L661)）。コマンド、ブロックコマンド、`golem_describe`、`golem_check_data` は 10 億のままである。
- C の `golem_plugin_call` が使った数を返し、上限超過なら上限の全部とする。燃料切れのコードと文言は不変。
- `GOLEM_DEBUG_PLUGIN_FUEL=1` で sou-ruby のフィルタを当てた本を組むと、標準エラーに `golem-debug-fuel: mode=2 request=121 fuel=1000630000 used=163626 status=0` のような三行（mode 0、1、2）が出て、環境変数なしの `build/` と diagnostic と同一であることを実機で確かめた。`fuel − 10^9 = 630000` は 10000 の倍数で、`request` の 121 バイト（文脈とデータを含む）より小さい文書のバイト数に対応する。
- `unsafePerformIO` は `invokeRawFuel` の一つで、`scripts/ci/unsafe-io-allowed.txt` と manual-dev の 12-purity.gm が同名である。テスト（`FuelSpec`）、仕様書、manual-dev。

### 所見

**F-29（逸脱、申告あり、低）：allow-list の名前を `invokeRaw` から `invokeRawFuel` に変え、純粋性の章はデバッグ行に触れない。**
[docs/adr/0034](../adr/0034-adr-code-mismatches.md) は残す一つを `invokeRaw` と名指しするが、実装は上限を引数に取る `invokeRawFuel` を唯一の `unsafePerformIO` にし、`invokeRaw` はその純粋な包みである（[Plugin.hs#L346-L347](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-plugin/src/Golem/Plugin.hs#L346-L347)、[同#L358-L359](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-plugin/src/Golem/Plugin.hs#L358-L359)）。
「残すものは一つ」という規則は守られ、最初のコミットにあった二つめの `unsafePerformIO` はマージ前に一つに戻された。
一方、`callModeWith` は `unsafePerformIO` の内側で `lookupEnv` と `hPutStrLn stderr` を行う（[同#L322-L324](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-plugin/src/Golem/Plugin.hs#L322-L324)）。
結果は環境に依らず、出力も diagnostic も変わらないので決定性と「黙って変えない」には反せず、0124 自身がこの経路を決めている。
ただし [12-purity.gm#L200](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/manual-dev/part2/12-purity.gm#L200) の「作用が外から観察できない」と allow-list の理由は、標準エラーへの書き込みに触れておらず、`invokeRawFuel` を純粋と呼ぶ根拠の説明が欠ける。
純粋性の章に一文を足すのがよい。

## [ADR 0125](../adr/0125-kansuji-plugin-overrides-number-text.md): kansuji が `number-text` を上書きする

### 適合を確かめたもの

- `number-text` は 0031 の `OverridableBuiltin` にあり、`phOverrides` にあればプラグインへ回す（[File.hs#L1817](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-eval/src/Golem/Eval/File.hs#L1817)）。`overrides` に書かないと G06007 `組み込みのコマンドと衝突しています（overrides で宣言してください）: kansuji.number-text` になることを実機で確かめた。
- 位取り、〇、マイナス、小数の「・」、分数、`tcy`、横組みの算用数字、桁の上限、既定の `vertical-numbers` と `style=` の優先、七つのコード（[kansuji/lib.rs](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/plugins/kansuji/src/lib.rs)）。
- 縦組みの本で `[number-text 123456789]、[number-text [= 3.14]]、[number-text [= 2 / 3]]、[number-text 2026 style=kanji-digits]、[number-text -3]、[number-text 12 style=tcy]、##10##` が `一億二千三百四十五万六千七百八十九、三・一四、三分の二、二〇二六、マイナス三、12、十` になることを実機で確かめた。
- Rust と golem-driver のテスト設計の全項目、仕様書、使い手のマニュアル、ロードマップの項目の削除、CI とリリース。「実装しないこと」の違反なし。
- 申告された三つの逸脱は妥当である。`[number-text -3]` が「マイナス三」になるのは 0111 の後の帰結で、0125 自身が予告した。`style=kanji **[{style: "tcy"}]` が G02077 で kanji を使うのは G02077 の定義（最初に書いたものだけを使う）どおりで、実機でも G02077 が出た。コードを `arity` のように後ろだけ返すのは 0108 と 0125 の本文どおりである。マニュアルの URL をプレースホルダーにしたのは、仕様書に形があるので読み手は辿れる。

### 所見

**F-30（文書の不一致、低）：`style` の値が文字列でないときのメッセージに値が付かない。**
ADR の表は `style は kanji、kanji-digits、tcy のいずれかです: <値>` とするが、`[number-text 12 style=[= 3]]` では `kansuji/style` が値なしの文言になることを実機で確かめた（[kansuji/lib.rs#L252](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/plugins/kansuji/src/lib.rs#L252)）。
コードは同じで、ADR の表に「値が文字列でないとき」の行がないので字面の差にとどまる。

## [ADR 0126](../adr/0126-glossary-plugin.md): 用語集のプラグイン

### 適合を確かめたもの

- コマンド `term`、チャネル `glossary`（読みの順、`locators`）、データ `terms`。TSV の 3 欄か 4 欄、読みの文字の制限、重複、空、読みのない漢字の語、メッセージは ADR の表と一字一句一致（[glossary/lib.rs#L58-L95](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/plugins/glossary/src/lib.rs#L58-L95)）。
- `[term: 語]` の本文はスロットのまま、項目のキーは語、読みは TSV、本文は語と定義と `（→ Ref Page ）`。独自チャネルを実プラグインで通し、PDF、HTML、EPUB、テキストの一覧をテストが確かめる。
- 横組みの本で `[term: 組版]と[term: 組版]と[term 組む: 組んだ]。` と `@channel glossary` を組むと、テキストに `組版　版を組むこと` と `組む　版を作ること` の二行が読みの順に出ることを実機で確かめた。
- `golem_check_data` で TSV の誤りを TSV の行に出す（0120 のとおり、実機で確認済み、上の 0120 の節）。
- HTML の目次は `isAnchored` で `IndexMark` と `ChannelItem` を見出しから除く（[Html.hs#L516-L526](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-html/src/Golem/Html.hs#L516-L526)）。
- Rust と golem-driver のテスト設計の全項目、仕様書、manual-dev、ロードマップの項目の削除。「実装しないこと」の違反なし。
- 申告された暫定の `args` のコードは、二つのマージの間だけの状態で、0127 の文言に置き換わっている。妥当である。

### 所見

**F-31（文書の不一致、中、実機未確認）：ADR の「PDF の目次と同じ扱い」は、チャネルの項目については成り立っていない疑いがある。**
ADR と [docs/specifications.md#L717-L718](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/docs/specifications.md#L717-L718) は、HTML の目次の修正を「PDF の目次と同じ扱い」と書く。
しかし PDF の目次が除くのは索引の印だけで（[Flow.hs#L1301](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L1301) の `filter (not . isMark)`、`isMark` は `IndexMark` のみ）、`ChannelItem` は残る。
レイアウトは `ChannelItem` をアンカーにする（[Japanese.hs#L305](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-layout/src/Golem/Layout/Japanese.hs#L305)）ので、見出しに `[term]` を書き `@toc` を置いた PDF では、目次の行にもアンカーが立ち、出現のページの列に目次のページが混じるおそれがある。
ADR の「実装すること」は HTML の修正だけで、PDF 側は ADR の前提（既に除いている）が誤っている疑いである。
driver のテストの `@toc` の検査は HTML だけで、PDF のテキストを取り出す道具がないため、この監査では再現していない。
確かめ方は、横組みの本で `@toc` と `# [term: 組版]の章` を別のページに置いて PDF を組み、一覧の出現のページが見出しのページ一つだけかを見ることである。

**F-32（文書の不一致、低）：使い手のマニュアルは glossary が見本のプラグインであることを書いていない。**
[manual/chapters/10-plugins.gm#L150-L166](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/manual/chapters/10-plugins.gm#L150-L166) は `@channel glossary` を例に使うが、kansuji や tsv-table のように宣言と TSV の形を載せない。
0126 はマニュアルの更新を求めていないので逸脱ではない。
同じ章で見本の三つを紹介しながら glossary、sou-ruby、first-ruby を載せないことは F-43 と合わせて記録する。

**F-33（低）：glossary だけが TSV の先頭の BOM を飛ばさない。**
lookup と bar-chart の節は「先頭の BOM を飛ばし」と書くが、glossary の `parse`（[glossary/lib.rs#L72-L77](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/plugins/glossary/src/lib.rs#L72-L77)）は飛ばさず、BOM 付きの TSV では 1 行めの語が `\u{FEFF}組版` になる。
ADR は BOM を決めていないので逸脱ではなく、見本のあいだで TSV の扱いが揃っていないことの記録である。

## [ADR 0127](../adr/0127-glossary-headword-argument.md): 用語集の見出し語の引数

### 適合を確かめたもの

- 位置引数一つを見出し語にし、散文スロットは本文の字だけ。`args`、`headword-type`、`headword-empty` のメッセージは ADR の表と一字一句一致（[glossary/lib.rs#L156-L164](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/plugins/glossary/src/lib.rs#L156-L164)）。語も文字列も `ArgValue::Str` で届くので `[term 組む: …]` と `[term "組む": …]` は同じである。
- `[term 組む: 組んだ]` がテキストで `組む　版を作ること` の一行になることを実機で確かめた。Rust と golem-driver のテスト、仕様書。「実装しないこと」の `headword=` は `args` になる。

所見はない。実装者の「逸脱なし」の申告は妥当である。

## [ADR 0128](../adr/0128-auto-tcy-filter.md): 縦中横を自動で当てるフィルタ

### 適合を確かめたもの

- 塊の定義、`digits` と `marks` の判定、ノードの種類ごとの扱い（`code` の中、圏点とルビの親文字、既存の縦中横、数と参照、脚注と傍注、索引の印）、またぐ塊の警告、`config` の文法と誤りの位置、横組みでは文書を変えない（[auto-tcy/lib.rs](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/plugins/auto-tcy/src/lib.rs)）。
- 縦組みの本で `第12回、本当か!?、3.14、[strong: 1]2。` を組むと `warning[auto-tcy/split]: ノードの境をまたぐので縦中横にしませんでした: 12。…` が一つ出て終了コード 0 になることを実機で確かめた。
- Rust と golem-driver のテスト設計の全項目、仕様書、使い手のマニュアル、ロードマップの項目の削除。

### 所見

**F-34（逸脱、申告あり、低）：`auto-tcy/split` の位置は塊の最初のノードであり、ADR の「ノードの位置を合わせた範囲」ではない。**
[auto-tcy/lib.rs#L267-L270](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/plugins/auto-tcy/src/lib.rs#L267-L270)。
0108 は diagnostic の位置を要求のノードの位置に限り、合わせた範囲はどのノードの位置でもないので、0128 の文言のままでは実装できない。
文書順で最初のノードなので決定的であり、妥当である。
仕様書はこの振る舞いを書いている。

**F-35（範囲外の変更、低）：`config` の `digits` で `02` のような先頭 0 を拒む。**
[auto-tcy/lib.rs#L85](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/plugins/auto-tcy/src/lib.rs#L85)。
ADR は「1 から 4 の数の並び」とだけ書く。
厳しい側なので許容範囲だが、ADR にない規則である。

## [ADR 0129](../adr/0129-tsv-table-plugin.md): TSV から表を組むブロックコマンド

### 適合を確かめたもの

- 位置引数一つ、`align` 以外のキーは `key`、本体は `body`、名前のデータなしは `no-data`、TSV の読み方（8 MiB、UTF-8、CR、BOM、行と列と合計の上限、セル数の不一致）、`align` の形、空セル、全ノードの位置は呼び出し、誤りのときブロックなし、十のコード（[tsv-table/lib.rs](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/plugins/tsv-table/src/lib.rs)）。
- 縦組みの本で、同じ TSV（引用符、バックスラッシュ、空セルを含む）を `@tsv-table sales` と `@table src=data/sales.tsv` で組んだ PDF は、どちらも 140436 バイトで、違いは末尾の 31 バイト（`/ID` の二つめ）だけであることを実機で確かめた。メンテナーの縦横の確認と一致する。
- Rust と golem-driver のテスト設計の全項目、仕様書、使い手のマニュアル、ロードマップの項目の削除と未決事項（上限の違い）の追加。
- 申告（コードは後ろの部分だけ）は 0108 と 0129 の本文どおりで、妥当である。

### 所見

**F-36（文書の不一致、低）：大きさの上限の `limit` のメッセージには行の番号がない。**
[tsv-table/lib.rs#L182](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/plugins/tsv-table/src/lib.rs#L182) はバイト数と上限だけを書く。
ADR の「メッセージに超えた上限と行の番号を書く」と仕様書の「`limit` のメッセージには、TSV の行の番号を書く」は、ファイル全体の大きさには当てはまらない。
実装が合理的で、文書の表現が広すぎる。

**F-37（テスト欠落、低）：`@tsv-table` と `@table` の PDF の同一性はテストで固定されていない。**
[PluginsSpec.hs#L523-L531](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-driver/test/PluginsSpec.hs#L523-L531) は S0 の表の形だけを比べる。
ADR のテスト設計がそう求めているので不足ではないが、ADR の「`/ID` を除いて同じバイト列」は手で確かめたままで、回帰の検査がない。

## [ADR 0130](../adr/0130-sou-ruby-plugin.md): 総ルビのプラグイン

### 適合を確かめたもの

- 読みの二段（TSV を最長一致で先に、残りを Lindera で）、辞書はデータで渡し埋め込まない（`lindera` は `default-features = false`）、九つのファイルの名前、辞書の誤りの三つの文言、TSV も辞書もなければ `no-words`、グループルビと仮名の位置での分割、読みのない語の警告はファイルごとに語ごとに一度、見出しにも振る、原稿のルビは残す（[sou-ruby/lib.rs](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/plugins/sou-ruby/src/lib.rs)、[ruby-common/lib.rs](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/plugins/ruby-common/src/lib.rs)）。
- `東京に住む。大阪。` が `東京（とうきょう）に住（す）む。大阪。` になり、`大阪` に警告が一つ出ることを実機で確かめた。
- Rust と golem-driver のテスト、仕様書、ロードマップの項目の削除。「実装しないこと」の違反なし。IPADIC での結合は ADR のとおりテストに入れず、PR も実行していない（申告あり）。

### 所見

**F-38（逸脱、申告なし、中）：sou-ruby と first-ruby は diagnostic のコードに宣言の名前を自分で含み、ホストの前置と重なる。**
[sou-ruby/lib.rs#L149](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/plugins/sou-ruby/src/lib.rs#L149)、[同#L163](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/plugins/sou-ruby/src/lib.rs#L163)、[first-ruby/lib.rs#L77](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/plugins/first-ruby/src/lib.rs#L77)、[ruby-common/lib.rs#L343](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/plugins/ruby-common/src/lib.rs#L343) は `sou-ruby-unread`、`first-ruby-no-words`、`<名前>-tsv` を返し、ホストが前置して `sou-ruby/sou-ruby-unread` と表示される。
driver のテスト（[PluginsSpec.hs#L889-L890](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-driver/test/PluginsSpec.hs#L889-L890)、[同#L912](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-driver/test/PluginsSpec.hs#L912)）はこの二重の形を固定している。
`[plugins.ruby]` の名前で宣言すると `warning[ruby/sou-ruby-unread]` と `error[ruby/first-ruby-no-words]` になることを実機で確かめた。
0108 は「プラグインは後ろの部分だけを返し」と決め、同じ日に実装した auto-tcy（`split`）、tsv-table（`name`）、kansuji、bar-chart、glossary はそれに従う。
0130 と 0131 の表記 `sou-ruby-unread`、`first-ruby-tsv` は、0128 と 0129 の `auto-tcy-split`、`tsv-table-name` と同じ書き方で、0131 は「コードの形は 0108 に従う」と明記するので、同じ読み替えをすべきだった。
PR #496 と #500 の本文に申告はない（#500 は「Deviations: none」）。
書き手の見る diagnostic のコードが見本のあいだで一貫せず、宣言の名前を変えると二重の名前が見えるので、中とする。
仕様書の [L3110-L3111](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/docs/specifications.md#L3110-L3111) も、ほかの見本の節が「宣言の名前を前に付けて…と表示する」と書く形と揃っていない。
直すなら `read_words` の `code` 引数と二つの `NAME` の使い方、driver のテスト 5 件、仕様書を変える。

**F-39（文書の不一致、中）：開発者のマニュアルが「総ルビの辞書のようなアセットは、wasm のモジュールに埋め込む」と書いたまま。**
[manual-dev/part1/05-plugins.gm#L117](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/manual-dev/part1/05-plugins.gm#L117)。
0130 は埋め込みを「実装しないこと」に置き、データで渡すと決めた。
0105 のデータの仕組みがある今、この一文はプラグインを書く読者を逆に案内する。
PR #496 は「Manual: unchanged」で、ADR もこの文書の修正を指示していないが、古い記述の残存にあたる。

**F-40（文書の不一致、申告あり、中）：Lindera を含む wasm の配布にライセンスの文書を添えない件が、ADR にもロードマップにも決定として残っていない。**
PR #496 の本文は「`sou-ruby.wasm` contains Lindera (MIT) and its dependencies; the release attaches the wasm without their license texts. The ADR does not address this」と申告する。
0130 の「ライセンス」の節は Lindera と依存クレートのライセンスの種類を列挙するが、wasm に入るクレートのライセンス表示を配布物にどう添えるかは決めていない。
ほかの見本は `golem-plugin-sdk`（リポジトリ内）だけに依存するので、外のクレートを含む wasm の配布は sou-ruby が初めてである。
`rg 'Lindera|ライセンス' docs/roadmap.md` は 0 件である。
外部の法的な判断はしないが、ADR が決めていないことを PR が指摘し、文書のどこにも引き取られていない状態なので、未決事項に足すか別の ADR で決めるべきである。

**F-41（範囲外の変更、低）：`sou-ruby-no-command` と `first-ruby-no-command` は ADR にない。**
[sou-ruby/lib.rs#L267-L278](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/plugins/sou-ruby/src/lib.rs#L267-L278)、[first-ruby/lib.rs#L87-L104](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/plugins/first-ruby/src/lib.rs#L87-L104)。
`golem_describe` がコマンドを宣言しないのでホストからは起きない。
0131 は「プラグインが返す diagnostic は、次の三つ」と限定している。

F-02 の `rustc-wrapper.sh` は 0130 の PR で入ったが、0106 の節に書いた。

## [ADR 0131](../adr/0131-first-occurrence-ruby-plugin.md): 初出の語にルビを振るプラグイン

### 適合を確かめたもの

- TSV の形式（`/` のモノルビと部分ルビ、読みの空の止めの語、七つの誤りのメッセージ、行の番号、一つでも誤りがあれば文書を変えない）、最長一致、初出の単位はファイル、辿る順、見出しと `code` と圏点などは数えない、原稿のルビは残して出現に数える、出力の形（[first-ruby/lib.rs](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/plugins/first-ruby/src/lib.rs)、ruby-common）。
- ホストはフィルタの diagnostic にファイルの先頭を許す（0108 のとおり）。
- Rust と golem-driver のテスト設計の全項目、仕様書、ロードマップの項目の削除、CI とリリース。

### 所見

F-38（二重の名前）は 0131 にも当たる。

**F-42（逸脱、申告なし、低）：止めの語の行では「語の `/` のあいだが空です」を検査しない。**
[ruby-common/lib.rs#L100-L111](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/plugins/ruby-common/src/lib.rs#L100-L111) は読みが空なら区切りの検査の前に止めの語を返すので、`東//京<TAB>` は誤りにならず止めの語「東京」になる。
ADR の表は行の種類で区別していない。
出力には影響しないが、ADR の誤りの一覧より緩い。

**F-43（文書の不一致、低）：使い手のマニュアルの付録のロードマップが、二つのルビのプラグインを rc4 の予定として残し、「章ごとの最初の出現」と書く。**
[manual/appendices/h-roadmap.gm#L37-L38](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/manual/appendices/h-roadmap.gm#L37-L38)。
0131 は単位をファイルと決めた。
また、使い手のマニュアルのプラグインの章は sou-ruby と first-ruby を見本として載せていない（F-32 と同じ形）。

## [ADR 0132](../adr/0132-setting-command-codes-by-cause.md): `@manifest` と `@style-def` の引数の誤りを原因ごとのコードに分ける

### 適合を確かめたもの

- G02052 は位置引数の数だけ、G02117 は未知の種類、G02116 は語と文字列以外、G02115 は `@manifest` に引数なし、G02097 は本体、G02077 は同じキー、G02114 は展開（[Settings.hs#L71-L122](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-eval/src/Golem/Eval/Settings.hs#L71-L122)、[同#L234-L256](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-eval/src/Golem/Eval/Settings.hs#L234-L256)）。メッセージは ADR と一字一句同じである。
- `@style-def table a b` が G02117（1:12）と G02052（1:20）、`@manifest [= 1]` が G02052 だけになることを実機で確かめた。申告された順（書いた順、`inOrder`）は ADR が決めておらず、決定的で、妥当である。
- テスト設計の表 17 行が `FileSpec.hs#L980-L1001` にあり、旧 G02052 の期待は改めてある。diagnostics.md の G02052 の改訂と三つの新設、G02077 と G02097 の対象、docs/markup.md、仕様書、付録 E。`golem explain G02115 G02116 G02117` が三節を出すことを実機で確かめた。
- 0014 と [golem-parser ADR 0013](../golem-parser/adr/0013-splat-after-keyword-arguments.md) のステータスの行は ADR の指示どおりである。新設コードはほかの ADR と衝突しない。

### 所見

**F-44（逸脱、申告なし、中）：本体のある `@manifest` では、引数の誤りが G02097 の陰に隠れる。**
ADR は「一つの `@manifest` か `@style-def` に原因が複数あれば、原因ごとに一つずつ出す」とする。
`fileSettings` の `step` は `not (null body) || null args` を先に判定し、そこで G02115 と G02097 だけを出して引数を読まない（[Settings.hs#L110-L111](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-eval/src/Golem/Eval/Settings.hs#L110-L111)）。
`@manifest title=x title=x` に本体を付けると、ADR の規則では G02077 と G02097 だが、実機では G02097 だけになることを確かめた。
一方 `@style-def` は引数の誤りと本体をすべて集めるので、二つのコマンドで規則が食い違う。
「誤りの後の扱い」（本体のある `@manifest` を無視すること）は保ちつつ、引数の diagnostic だけ出すことはできたはずで、ADR の明示の規則に反する。
`FileSpec` に本体と引数の誤りを同時に持つ `@manifest` の例はない。

**F-45（逸脱、申告なし、低）：位置引数が足りないときの G02052 と G02115 の位置が、コマンドの行ではなくブロックの全体である。**
ADR は位置を「足りないときはコマンドの行」「G02115…コマンドの行」とする。
実装はブロックの `sp` を使い（[Settings.hs#L107](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-eval/src/Golem/Eval/Settings.hs#L107)、[同#L242](https://github.com/tett23/golem/blob/5db37cb96acb88a84fb63057323c066991fc995c/modules/golem-eval/src/Golem/Eval/Settings.hs#L242)）、この `sp` は本体まで含む。
本体がなければ行と一致するので、違いが見えるのは `@style-def paragraph` に本体も付けたときだけで、実機では G02052 が 1:1 に出た（終わりの位置は表示されない）。
テストは始まりのオフセットしか確かめていない。

**F-46（文書の不一致、低）：`@manifest` の位置引数が式のときのコードが ADR で二義的である。**
ADR の表は「`@manifest` に位置引数がある」を G02052、「値か位置引数が語と文字列のほか」を G02116 とし、`@manifest [= 1]` はどちらにも読める。
実装は G02052 だけを出す（実機で確認）。
数の誤りが先に立つ判断は「一つの原因に一つのコード」に沿うが、diagnostics.md の G02116 の節はこの境界を書いていない。

## ほかの ADR のステータスの行

- [golem-doc ADR 0007](../golem-doc/adr/0007-plugin-channel-lists.md)：0105 の指示の句と、0107 の句（F-06）。
- [golem-plugin ADR 0001](../golem-plugin/adr/0001-wasm-host-and-abi.md)：0105 の「要求の `data` の欄」と 0106 の「最初の SDK（Rust）の置き場所」の句（0106 は文言を与えておらず、申告どおり）。
- [golem-plugin ADR 0002](../golem-plugin/adr/0002-distribution-and-lock.md)：0109 の句（0109 は求めていないが申告あり、妥当）。
- [docs/adr/0113](../adr/0113-closed-range-literal.md)：0116 の句（指示どおり）と 0111 の句（F-13）。
- [docs/adr/0115](../adr/0115-reserved-syntax-code.md)：0116 の句（指示どおり）。
- [docs/adr/0014](../adr/0014-in-file-settings.md) と [golem-parser ADR 0013](../golem-parser/adr/0013-splat-after-keyword-arguments.md)：0132 の句（指示どおり）。
- 二十四の ADR のステータスは、どれも「採択（未実装）」から「採択」に変わり、ほかの行は変わっていない（0105 は 0107 への参照を含む）。

## 横断的な所見

**プラグインのコードの前置き**：0108 は「プラグインは後ろの部分だけを返す」と決め、同じ日の七つの見本のうち五つはそれに従い、bar-chart は PR #499 で後から合わせた（F-09）。
sou-ruby と first-ruby は ADR の字面（`sou-ruby-unread`）をそのまま返し、`sou-ruby/sou-ruby-unread` になった（F-38）。
0125、0128、0129 の ADR も同じ字面で書いていたが、実装者は 0108 に読み替えた。
見本の命名が二通りに割れたことは、ADR の字面と 0108 の規則のどちらを優先するかを ADR で決めて揃えるのがよい。

**一つの原因に一つのコード**：原則に反する箇所は F-14（コードブロックのキーの式の範囲で G02113 と G02069）である。
F-13（`numbers` の G02113）と F-15（`-1...1.5` の語と式）は、二つの ADR か ADR の例の不備が原因で、実装者が原則に沿う側を選んだ。
F-44（本体のある `@manifest`）は原則の逆で、原因が複数あるのに一つしか出ない。

**ADR の「実装しないこと」と実装**：F-25（G08102）は、採択の前に足すと書いた項目が「実装しないこと」の中に残ったまま採択され、実装側が入れた。
ADR の節の置き場所と採択の手順の問題で、短い修正の ADR で記録に残すべきである。

**ADR の外で決めたこと**：`rustc-wrapper.sh`（F-02）、Lindera のライセンスの文書（F-40）、bar-chart のコードの名前（F-09）は、どれもプルリクエストで申告されたが、ADR にもロードマップにも引き取られていない。

**文書の遅れ**：diagnostics.md の G06009 と G06005（F-07）、manual-dev の IR の章（F-05）と埋め込みの一文（F-39）、使い手のマニュアルの付録のロードマップ（F-43）とコードの範囲（F-23）は、プルリクエストが触らなかった文書の古い記述である。
前回の監査の F-03（ABI 7）と同じ型で、ADR が指示する文書の外にある記述は申告の対象に入っていない。
実装のレーンの手順に「`rg` で古い記述を探す」を足すのがよい。

**決定性と出力**：二十四の ADR のどれも、出力を黙って変えていない。
0118 の縦組みの `[ref-page]` の変化は ADR が予告したもので、0124 のデバッグの行は出力と diagnostic を変えないことを実機で確かめた。
`@tsv-table` と `@table` の PDF の一致（`/ID` を除く）と、bar-chart の PDF の二度のビルドの一致も実機で確かめた。

**build-depends**：二十五のプルリクエストで変わった cabal ファイルは、テストの `other-modules` の追加と、golem-\* 以外の `bytestring` と `containers`（0123、ADR に記載）だけで、golem-\* のあいだの build-depends は変わっていない。

**申告の質**：申告された逸脱はどれも妥当か、妥当な範囲の判断だった。
申告のない中の所見は F-05、F-07、F-14、F-26、F-31、F-38、F-39、F-44 の八つで、うち F-14、F-26、F-44 はコードの振る舞い、ほかは文書である。

## 要約表

| 番号 | 所見 | 分類 | 重大度 | 根拠 |
| --- | --- | --- | --- | --- |
| F-05 | manual-dev の IR の章が「三つ目のフィールド」と「ABI 7」を書く | 文書の不一致 | 中 | 06-ir.gm#L440、#L450 |
| F-07 | diagnostics.md の G06009 と G06005 に 0108、0121、0122、0123 の文言と欄がない | 文書の不一致 | 中 | diagnostics.md#L5232-L5234、#L5328-L5345 |
| F-13 | `numbers` の `...` を G02069 から G02113 にし、0113 の決定を 0111 の一般規則で上書きした | 逸脱（申告あり） | 中 | 0113#L260-L263、File.hs#L2331-L2354 |
| F-14 | コードブロックのキーの式の範囲で G02113 と G02069（値が空）の二つが出る | 逸脱（申告なし） | 中 | File.hs#L1600-L1614、実機 |
| F-21 | 「宣言にない名前」を「渡していない名前」と読み、必須のデータの欠けを読み込み時に報告できない | 逸脱（申告あり） | 中 | Driver/Plugins.hs#L204-L205、実機 |
| F-25 | 「実装しないこと」に書いた G08102 を実装した | 逸脱（申告あり） | 中 | Driver.hs#L684-L692、実機 |
| F-26 | 図版のキャプションの中の `plugin:` の図版が検査を迂回する | 逸脱（申告なし、実機未確認） | 中 | Plugin.hs#L616-L624、#L641 |
| F-31 | PDF の目次がチャネルの項目のアンカーを残し、ADR の前提と合わない疑い | 文書の不一致（実機未確認） | 中 | Flow.hs#L1301、Japanese.hs#L305 |
| F-38 | sou-ruby と first-ruby のコードが `sou-ruby/sou-ruby-unread` と二重になる | 逸脱（申告なし） | 中 | sou-ruby/lib.rs#L149、実機 |
| F-39 | manual-dev が辞書を wasm に埋め込むと書いたまま | 文書の不一致 | 中 | 05-plugins.gm#L117 |
| F-40 | Lindera を含む wasm のライセンスの文書を添えない件が未決のまま | 文書の不一致（申告あり） | 中 | PR #496、roadmap.md |
| F-44 | 本体のある `@manifest` で引数の誤りが G02097 の陰に隠れる | 逸脱（申告なし） | 中 | Settings.hs#L110-L111、実機 |
| F-01 | `DataSpec` の「fourth list」 | 文書の不一致 | 低 | DataSpec.hs#L77 |
| F-02 | `rustc-wrapper.sh` が ADR になく、仕様書は 0106 の説明として書く | 範囲外の変更（申告あり） | 低 | build.sh#L24-L26、specifications.md#L3017 |
| F-03 | コンテナでの `build.sh --check` を手で行わなかった | 逸脱（申告あり） | 低 | PR #482 |
| F-04 | `lookup.wasm` だけモード 100644 | 文書の不一致 | 低 | `git ls-files -s` |
| F-06 | PR #483 が 0105 と 0007 のステータスの行を指示なく書き換えた | 範囲外の変更 | 低 | 0105#L3、0007#L3 |
| F-08 | コードの先頭の数字と `-` を許す | 逸脱（申告あり） | 低 | Plugin.hs#L817 |
| F-09 | PR #499 が bar-chart のコードを ADR なしに変えた | 範囲外の変更 | 低 | bar-chart/lib.rs#L123-L133 |
| F-10 | `golem explain` が `/` の前を何でも受ける | 範囲外の変更 | 低 | cli/Main.hs#L160-L163、実機 |
| F-11 | G03003 の節がプラグインの `path` とデータを挙げない | 文書の不一致 | 低 | diagnostics.md#L3906-L3930 |
| F-12 | `path` のシンボリックリンクのルート外が未テスト | テスト欠落 | 低 | PluginsSpec.hs#L981-L987 |
| F-15 | `-1...1.5` の語は G02113、式は G02104 | 逸脱（申告あり） | 低 | File.hs#L2141、実機 |
| F-16 | G02113 の位置がコマンドで、文書の「引数」と違う | 文書の不一致 | 低 | 実機 |
| F-17 | `@import` にも `prepareArgs` が走る | 逸脱（申告なし） | 低 | File.hs#L485 |
| F-18 | `@style` の二つの展開に G02114 が一つ | 逸脱（申告なし） | 低 | File.hs#L484、実機 |
| F-19 | ロスレス性のテストが入力の一部 | テスト欠落 | 低 | ParserSpec.hs#L342-L355 |
| F-20 | 縦組みの `[ref-page]` の出力の変化を固定する資料がない | テスト欠落 | 低 | ReferencesSpec.hs#L779 |
| F-22 | `CheckDataSpec` が ABI を直書き | テスト欠落 | 低 | CheckDataSpec.hs#L33 |
| F-23 | 使い手のマニュアルのコードの範囲が G06104 まで | 文書の不一致 | 低 | 10-plugins.gm#L53 |
| F-24 | markup.md が返せるブロックに図版を挙げない | 文書の不一致 | 低 | markup.md#L292 |
| F-27 | `FileSpec` のコメントが `NNNN` | 文書の不一致 | 低 | FileSpec.hs#L405 |
| F-28 | 一段めの前後の比較を本実装でしていない | テスト欠落（申告あり） | 低 | PR #491 |
| F-29 | `invokeRawFuel` への改名と、純粋性の章がデバッグ行に触れない | 逸脱（申告あり） | 低 | Plugin.hs#L322-L324、12-purity.gm#L200 |
| F-30 | `style` が文字列でないときの文言に値がない | 文書の不一致 | 低 | kansuji/lib.rs#L252、実機 |
| F-32 | 使い手のマニュアルが glossary を見本として載せない | 文書の不一致 | 低 | 10-plugins.gm#L150-L166 |
| F-33 | glossary だけ TSV の BOM を飛ばさない | 文書の不一致 | 低 | glossary/lib.rs#L72-L77 |
| F-34 | `split` の位置が最初のノード | 逸脱（申告あり） | 低 | auto-tcy/lib.rs#L267-L270 |
| F-35 | `digits` の先頭 0 を拒む | 範囲外の変更 | 低 | auto-tcy/lib.rs#L85 |
| F-36 | `limit` の文言に行の番号がないのに文書は書くとする | 文書の不一致 | 低 | tsv-table/lib.rs#L182 |
| F-37 | `@tsv-table` と `@table` の PDF の一致がテストにない | テスト欠落 | 低 | PluginsSpec.hs#L523-L531 |
| F-41 | `no-command` のコードが ADR にない | 範囲外の変更 | 低 | sou-ruby/lib.rs#L267-L278 |
| F-42 | 止めの語の行で `/` の空を検査しない | 逸脱（申告なし） | 低 | ruby-common/lib.rs#L100-L111 |
| F-43 | マニュアルの付録のロードマップが古い | 文書の不一致 | 低 | h-roadmap.gm#L37-L38 |
| F-45 | 足りないときの G02052 と G02115 の位置がブロックの全体 | 逸脱（申告なし） | 低 | Settings.hs#L107、#L242 |
| F-46 | `@manifest [= 1]` の G02052 と G02116 の境界が文書にない | 文書の不一致 | 低 | 実機 |

高の所見はない。
中の十二のうち、コードの振る舞いに関わるのは F-13、F-14、F-21、F-25、F-26、F-38、F-44 の七つ、文書と決定の記録に関わるのは F-05、F-07、F-31、F-39、F-40 の五つである。
