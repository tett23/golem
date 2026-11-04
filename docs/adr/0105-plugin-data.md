# ADR 0105: プラグインにデータを渡す

ステータス: 採択（未実装）

## 文脈

プラグインが受け取るものは、原稿のコマンドの引数と散文スロット、フィルタならファイル一つ分の文書だけである。
ホストはプラグインに import を一切渡さないので（[golem-plugin ADR 0001](../golem-plugin/adr/0001-wasm-host-and-abi.md)）、プラグインはファイルを読めない。
辞書や設定は、wasm のモジュールに埋め込むしかない。

これでは、rc4 で作る見本のプラグインのいくつかが実用にならない（[docs/roadmap.md](../roadmap.md) の v0.1.0-rc4）。

- **総ルビ**と**初出ルビ**：ルビの対象と読みの辞書を、本ごとに差し替えたい。プラグインに辞書を埋め込むと、本ごとにプラグインを作り直すことになる。
- **TSV から表を組むコマンド**：表のデータは本の原稿の一部であり、プラグインに埋め込めない。
- **縦中横のフィルタ**：フィルタは引数を受け取らないので、当てる対象の決め方を本ごとに変える経路がない。

ルビの対象を `.gm` の中に書く方法もあるが、利用者は手元の TSV などをそのまま使いたがる。
そこで、プロジェクトのファイルをホストが読み、要求に入れてプラグインに渡す。
プラグインに IO を渡さない原則は保たれる。

### 決めること

ロードマップは、次の六つを ADR で決めるとしている。

1. データの置き場所と宣言の仕方（マニフェストか、プラグインの設定か）。
2. 渡すときの形（CBOR の値、バイト列、`@table` と同じ表の読み込み）。
3. プロジェクトの外を指すパスの拒否。
4. データの変更を LSP と再評価がどう扱うか。
5. 決定性とハッシュによる検証。
6. データの大きさの上限。

### 試しに実装して分かったこと

この ADR は、採択の前に実装を試した（ブランチ `plugins-foundation`）。
Rust で書いた見本のプラグイン `lookup`（[docs/adr/0106](0106-sample-plugins-in-rust.md)）に TSV を渡し、`golem build` で組むところまで動かした。
試してわかったことは次のとおりである。

- 要求の末尾に欄を足すと、wat で書いたテスト用のプラグインのうち、要求を手で読む二つ（`identity.wat` と `channels.wat`）が壊れた。どちらも「要求の残りのすべて」を文書や位置として写していたからである。CBOR の配列の要素を数えずに末尾まで読む作り方は、欄を足すたびに壊れる。直したあとは、どちらも欄を数えて読む。
- `golem_describe` の応答を四つの欄にすると、テスト用のプラグイン十三個の記述のバイト列と長さを書き換えることになった。ABI のバージョン 8 はまだリリースしていないので、バージョンは上げない（[docs/adr/0052](0052-plugin-abi-version-bump-rule.md)）。
- 1 回の呼び出しごとにデータを要求に入れて写すので、プラグインは呼び出しのたびにデータを読み直す。`lookup` の 74 KiB の wasm と数行の TSV では、呼び出しの時間は測れるほど延びなかった。数十 MiB の辞書を、本文の各所で呼ぶコマンドに渡すと遅くなるおそれがある。測ってはいない。
- プラグインが返す diagnostic のコード（`lookup-no-key` など）は、ホストが形を検査しない。`golem explain` で引けず、`manifest.toml` の `silence-notices` の検査にも合わない。この問題はデータとは別なので、別の草稿（[docs/adr/0108](0108-plugin-diagnostic-codes-and-spans.md)）で扱う。

## 実装すること

### 宣言

データは、`manifest.toml` のプラグインの宣言に書く。

```toml
[plugins.lookup]
url = "https://github.com/tett23/golem/releases/download/v0.1.0-rc4/lookup.wasm"
data = { table = "data/words.tsv" }
```

- `[plugins.<名前>]` の `data` は、データの名前から、プロジェクトのルートを基準にしたパスへの表である。
- プラグインは、受け取るデータの名前を `golem_describe` の応答の四つめの欄で宣言する。
  - 名前は英小文字で始まり、英小文字、数字、`-` だけからなる。チャネルの名前と同じ形である（[golem-doc ADR 0007](../golem-doc/adr/0007-plugin-channel-lists.md)）。
  - 形の誤った名前と、二度書いた名前は、不正な `golem_describe`（G06005）とする。メッセージは `データの名前が不正です: <名前>` と `データの名前が重複しています: <名前>` である。
  - 四つの欄のない応答は、今と同じく `golem_describe の形が不正です`（G06005）とする。
- プラグインが宣言していない名前を `data` に書くと、新しいエラー G06102 とする。綴りの誤りを黙って捨てないためである。
- 宣言した名前を `data` に書かなくてもよい。データがないときの振る舞いは、プラグインが決める。

置き場所をマニフェストにしたのは、プラグインの設定が別のファイルになると、プロジェクトの入力の一覧が増えるからである。
`manifest.toml` はすでにプラグインの URL と `overrides` を持ち、LSP も CLI も読む。

### 渡す形

ホストはファイルのバイト列を解釈せずに渡す。

- 要求の最後の欄を `data` とする。`[名前, バイト列]` の組を、名前のコードポイントの順に並べた配列である。
- `data` に書いた名前だけを入れる。書かなかった名前の組はない。
- コマンドの要求とフィルタの要求の両方に入れる。フィルタは引数を持たないので、データがフィルタの唯一の設定の経路になる。
- データの CBOR は、プラグインを読み込んだときに一度だけ符号化し、呼び出しのたびには符号化しない。

TSV や JSON を読むのはプラグインである。
ホストが `@table` と同じく表に読む案は採らない。
表に読めないデータ（形態素解析の辞書のバイナリなど）を渡せなくなり、表の形の誤りを報告する責任がホストに移るからである。

### パス

パスの検査は、`@table` と参考文献のファイルと同じ `resolveInRoot`（[Golem.Project.Paths](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-project/src/Golem/Project/Paths.hs#L47-L48)）で行う。

- URL、絶対パス、ルートの外を指すパス、ルートの外を指すシンボリックリンクは G03003 とする。メッセージは `<理由>: <プラグイン>.<データの名前>: <パス>` である。
- ファイルがなければ、新しいエラー G06101 とする。メッセージは `プラグインのデータのファイルがありません: <プラグイン>.<データの名前>: <パス>` である。

### 大きさの上限

一つのプラグインのデータの大きさの合計を、64 MiB（67108864 バイト）までとする。
超えると新しいエラー G06103 とし、メッセージは `プラグインのデータが上限（67108864 バイト）を超えています: <プラグイン>（<合計> バイト）` である。
大きさは、ファイルを読む前にファイルの大きさで確かめる。

64 MiB は、インスタンスのメモリの上限 256 MiB（[`defaultMemoryLimit`](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-plugin/src/Golem/Plugin.hs#L81-L82)）の四分の一である。
要求はプラグインのメモリに書かれ、プラグインはそれを読んで自分の構造を作るので、データの数倍のメモリを使う。
上限をメモリの上限より十分に小さく置けば、データの大きさだけでトラップすることはない。

### diagnostic の順と位置

データの検査は、プラグインを読み込む段（[golem-plugin ADR 0003](../golem-plugin/adr/0003-plugin-diagnostic-codes.md) の二段め）で、読み込めたプラグインごとに行う。

- G06102、G03003、G06101 は、そのプラグインの誤りをすべて報告する。
- G06103 は、そのプラグインにほかの誤りがないときだけ確かめる。
- 位置は、G06002 などと同じく `manifest.toml` の先頭とする。
- データの誤りもプラグインの読み込みの誤りなので、評価で G02022 と G02090 を報告しない。

### 決定性

データは原稿や画像と同じく、プロジェクトの入力である。
同じ原稿と同じデータからは、同じ出力と同じ diagnostic になる。
データのハッシュは `plugins.lock` に書かない。
`plugins.lock` は、プロジェクトの外から取ってくる配布物を固定するためのものであり（[golem-plugin ADR 0002](../golem-plugin/adr/0002-distribution-and-lock.md)）、データはリポジトリの版管理で固定される。

### LSP と再評価

データは、プラグインを読み込むたびに読む。
ビルド、`golem check`、LSP の評価は、どれもプラグインを読み込むので、データの変更は次の評価で反映される。

- LSP は、データのファイルを `@table` のファイルと同じく監視する（[`tablesToWatch`](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-lsp/src/Golem/Lsp/Workspace.hs#L158-L159)、[`tableFilesChanged`](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-lsp/src/Golem/Lsp/Workspace.hs#L178-L179)）。`Evaluated` の `evTableFiles` に、データのパスを正規化して加える。ファイルが変われば、プロジェクトを評価し直す。
- エディタで開いているデータのファイルは、エディタの内容（UTF-8 に符号化したもの）を使う。`@table` と同じ扱いである（[golem-eval ADR 0004](../golem-eval/adr/0004-tsv-tables.md)）。

### モジュールの変更

golem-* のパッケージのあいだの build-depends は変えない。

- **golem-project**：`PluginDecl` に `pdData :: Map Text FilePath` を足す。
- **golem-plugin**：`Plugin` に、宣言されたデータの名前 `pluginDataNames` と、符号化したデータを足す。`withPluginData :: Map Text ByteString -> Plugin -> Plugin` と、上限 `maxDataBytes` を公開する。`commandRequest` は `Plugin` を受け取り、`filterRequest` を新たに公開する。
- **golem-driver**：`loadPlugins` が、プロジェクトのルートとエディタの内容を受け取り、データを読む。
- **golem-doc**：CDDL を下のとおりに変える。

## データ構造

```cddl
command-request = [0, name: tstr, args: [* argument], slots: [* inlines], span, data]
filter-request = [1, name: tstr, document, data]
data = [* [name: tstr, bytes: bstr]]
description = [commands: [* tstr], filters: [* tstr], channels: [* channel-decl], data: [* tstr]]
```

```haskell
-- Golem.Project.Manifest
data PluginDecl = PluginDecl
  { pdUrl :: !Text, pdOverrides :: ![Text], pdData :: !(Map Text FilePath) }

-- Golem.Plugin
pluginDataNames :: Plugin -> [Text]
withPluginData :: Map Text ByteString -> Plugin -> Plugin
maxDataBytes :: Int64
commandRequest :: Plugin -> Text -> [Value] -> [[Inline]] -> SrcSpan -> Either PluginError ByteString
filterRequest :: Plugin -> Text -> Document -> ByteString
```

## ドキュメント

- 仕様書の「プラグイン」に「データ」の節を足し、`[plugins.<名前>]` のキーの説明に `data` を加え、diagnostic の範囲を G06002 から G06012 と G06101 から G06103 にする。
- `docs/diagnostics.md` に G06101、G06102、G06103 を足す。
- 開発者のマニュアルのプラグインの章の CDDL、`golem_describe` の説明、wat の例、diagnostic の表を直す。
- 使い手のマニュアルのプラグインの章に「プラグインにデータを渡す」の節を足し、付録 E に三つのコードを足す。
- 採択の後、`docs/roadmap.md` の v0.1.0-rc4 から「プラグインにデータを渡す仕組み」を除く。
- 次の ADR のステータスの行の末尾に、この ADR を指す一句を加える。
  - [golem-doc ADR 0007](../golem-doc/adr/0007-plugin-channel-lists.md)：三つの欄の `description` を定めているので、「、`description` の四つめの欄は」に続けてこの ADR へのリンクを置く。
  - [golem-plugin ADR 0001](../golem-plugin/adr/0001-wasm-host-and-abi.md)：要求の形を定めているので、「、要求の `data` の欄は」に続けてこの ADR へのリンクを置く。

## 実装しないこと

- データを、プラグインが求めたときだけ渡すこと。ホストの関数を import として渡すことになり、import を渡さない原則（[golem-plugin ADR 0001](../golem-plugin/adr/0001-wasm-host-and-abi.md)）に反する。
- コマンドや宣言ごとに、渡すデータを選ぶこと。どのコマンドにも、そのプラグインのデータのすべてを渡す。
- `manifest.toml` の TOML の値（文字列や数）を、ファイルを介さずに設定として渡すこと。CBOR の `value` にマップがなく、TOML の表を写す形を決める必要がある。小さな設定も、ファイルにして渡せば足りる。
- ディレクトリを渡すこと。ファイルの並べ方と、ファイルの増減の監視を決める必要がある。
- データのハッシュを `plugins.lock` に記録すること。
- 呼び出しのあいだで、プラグインが読んだデータの構造を持ち越すこと（初期化済みのメモリの複製）。速度が問題になってから、ADR で検討する（[docs/roadmap.md](../roadmap.md) の「ビルドと LSP の速度」）。

## テスト設計

テストを先に書き、今の実装でコンパイルできないか失敗することを確かめてから実装した。

golem-plugin のテスト（`modules/golem-plugin/test/DataSpec.hs`）では、次のことを確かめる。

- 四つめの欄の名前が `pluginDataNames` になる。
- 三つの欄の `golem_describe` が `golem_describe の形が不正です` になる。
- `Dict`、空、`1a`、`a_b` の名前が `データの名前が不正です` に、二度書いた名前が `データの名前が重複しています` になる。
- `echo.wat`（要求をそのまま返す）で、コマンドの要求の最後の欄が名前の順のデータであること、データがなければ空の配列であり要求が六つの欄であること。
- フィルタの要求が `[1, 名前, 文書, データ]` のバイト列になること。

golem-project のテスト（`modules/golem-project/test/Main.hs`）では、次のことを確かめる。

- `data` の表が `pdData` になり、`data` がなければ空になる。文字列でないパスが G03001 になる。

golem-driver のテスト（`modules/golem-driver/test/PluginsSpec.hs`）では、プラグインに `plugins/wasm/lookup.wasm` を使い、次のことを確かめる。

- `data` で渡した TSV の値が、S0 の文書のテキストになる。
- `data` がなければ、プラグインの diagnostic `lookup-no-table` になる。
- ファイルを書き換えて評価し直すと、新しい値になる。
- エディタの内容が、ファイルより先に使われる。
- `./data/../words.tsv` と書いたデータが、`evTableFiles` に `words.tsv` として入る。
- G06101、G06102、G03003（ルートの外、絶対パス、URL、ルートの外を指すシンボリックリンク）、G06103 のコードとメッセージと位置。
- データの誤りのあとに G02022 が出ない。

手で確かめたこと：`golem new` で作ったプロジェクトに `lookup` を宣言し、キャッシュと `plugins.lock` を手で置いて、`golem build --target text` で TSV の値が本文に入ること、TSV を書き換えると次のビルドで値が変わること、TSV にないキーでプラグインの diagnostic が出て終了コードが 1 になることを確かめた。

## トレードオフ

呼び出しのたびにデータを写すので、大きな辞書を多数の呼び出しに渡すと遅くなる。
プラグインの側で「必要なときだけ読む」ことができないのは、import を渡さないことの代価である。
速度より、呼び出しが入力だけの関数であることを優先する。
大きな辞書をどうしても速く使いたいプラグインは、辞書を wasm のモジュールに埋め込める。

ホストがデータを解釈しないので、TSV の形の誤りはプラグインが自分の diagnostic で報告する。
`@table` と同じ表に読んで渡せば、誤りの報告をホストに揃えられたが、表でないデータを渡せなくなる。

64 MiB の上限は、メモリの上限から逆算した値であり、実際の辞書で確かめた値ではない。
IPADIC の CSV（約 50 MB）を渡す総ルビのプラグインは収まるが、プラグインがその数倍のメモリで辞書を組めば、メモリの上限を超えうる。
総ルビのプラグインを作ったときに測り、足りなければ ADR で改める。

データの名前を `golem_describe` で宣言させたので、プラグインの作者は名前を二か所（宣言と読む箇所）に書く。
その代わり、利用者の綴りの誤りが黙って捨てられることはない。

## 参考文献

- RFC 8949, Concise Binary Object Representation (CBOR). https://www.rfc-editor.org/rfc/rfc8949
- RFC 8610, Concise Data Definition Language (CDDL). https://www.rfc-editor.org/rfc/rfc8610
