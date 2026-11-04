# ADR 0121: プラグインが本の文脈を宣言して受け取る

ステータス: 採択

## 文脈

Golem は、数の表記を書字方向で決める。
`[number-text ...]` と `##N##` は、横組みでは算用数字、縦組みでは `[numbers]` の `vertical` の表記になる（[docs/markup.md](../markup.md) の「数の表記」）。
組み込みのコマンドは IR の数のノードを作り、表記はレイアウトが書字方向を見て決める（[`numberPieces`](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-layout/src/Golem/Layout/Japanese.hs#L378-L385)）。

プラグインの要求は、本のこうした設定を持たない。
コマンドの要求は名前、引数、散文スロット、位置、データを、フィルタの要求は名前、文書、データを持つだけである（[golem-plugin ADR 0001](../golem-plugin/adr/0001-wasm-host-and-abi.md)、[docs/adr/0105](0105-plugin-data.md)）。
rc4 の見本のプラグインを二つ作ったところ、この欠けは次の問題を起こした。

- **`kansuji`**（[docs/adr/0125](0125-kansuji-plugin-overrides-number-text.md)）：漢数字の文字列を返すので、横組みの本でも「百二十三」になった。組み込みの「横組みでは算用数字」を守れない。`style` のない数の表記も `[numbers]` の `vertical` を読めないので、同じ値をプラグインのデータに書き写させるしかなかった。
- **`auto-tcy`**（[docs/adr/0128](0128-auto-tcy-filter.md)）：数字は数のノードで返せば横組みで算用数字に戻るが、`!?` には縦中横のノードしかない。横組みで組むと、`!?` が全角一字分の箱に入り、前後に空きができた。

用語集のプラグイン（[docs/adr/0126](0126-glossary-plugin.md)）も、プラグインが出力の媒体（PDF か HTML か）を知る手段がないことを報告している。
メンテナーは、書字方向だけを足すのではなく、プラグインが受け取れる本の情報を一般に決めるよう求めた。

### 本の文脈を渡す形の候補

本の情報をすべての要求に入れると、プラグインが使わない値でも要求のバイト列が変わる。
`style.toml` の数の表記を変えただけで、それを読まない `lookup` の要求まで変わるのは、決定性の説明を複雑にする。
そこで、プラグインが要る情報を宣言し、ホストは宣言されたものだけを送る形にする。
宣言できる名前は閉じた一覧とし、ABI と一緒に版を管理する。

### 候補の名前

| 名前 | 中身 | 今入れるか |
| --- | --- | --- |
| `writing-mode` | `style.toml` の `[page]` の `writing-mode` | 入れる |
| `vertical-numbers` | `style.toml` の `[numbers]` の `vertical` | 入れる |
| `language` | `manifest.toml` の `language` | 入れない |
| 出力の媒体 | PDF、HTML、EPUB、プレーンテキスト | 入れない |

`language` を今入れないのは、使う見本のプラグインがなく、`manifest.toml` の変更を LSP が評価し直すかを確かめていないからである。
入れるときは、この ADR の修正の ADR で一覧に足す。

出力の媒体を入れないのは、S0 の評価が媒体ごとに分かれていないからである。
Golem は一つのファイルを一度だけ評価して意味論 IR を作り、すべての出力はその IR から分かれる（[docs/specifications.md](../specifications.md) の処理の段階の 3）。
媒体を要求に入れるには、プラグインを使うファイルを媒体ごとに評価し直す必要があり、評価の階層とキャッシュの設計を変えることになる。
プレーンテキストの `variants`（`horizontal` と `vertical`）も同じ理由で渡せない。
`writing-mode` は `style.toml` の `[page]` の値であり、プレーンテキストの縦組みの出力を作るかどうかとは別である。

### 試しに実装して分かったこと

この ADR は、採択の前に実装を試した（ブランチ `plugins-number-tcy` のコミット `b1721043`）。

- `golem_describe` の記述に欄を足すと、wat で書いたテスト用のプラグイン十三個の記述のバイト列と長さを書き換えることになった（[docs/adr/0105](0105-plugin-data.md) の試しと同じ）。要求を手で読む `identity.wat` は、要求の末尾の空の配列が一つから二つになり、文書の長さの計算を直した。
- 記述の欄を位置で並べる形は、欄を足すたびにすべてのプラグインを壊す。メンテナーは、`golem_describe` の欄を名前のある map にすると決めた（[docs/adr/0107](0107-named-describe-fields.md)）。試しの実装は位置の五つめの欄で行い、この ADR は名前のある map のキー `context` として書く。
- 補助のクレートの `Context::vertical()` を足すと、`kansuji` と `auto-tcy` の分岐はそれぞれ数行で済んだ。`kansuji` はデータの `config` が要らなくなった。
- `lookup` の wasm は、要求の形が変わったので作り直した（74031 バイトから 76116 バイト）。`lookup` は文脈を宣言しないので、要求の文脈の欄は空の配列である。
- LSP は、エディタで開いた `style.toml` の変更でも、ディスクの `style.toml` の変更でも、プロジェクトを評価し直していなかった（[`updateFile`](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-lsp/src/Golem/Lsp/Workspace.hs#L205-L231) は `.gm` と `@table` のファイル以外で評価し直さない）。これはプラグインに限らない今の振る舞いである。この ADR は、プラグインが文脈を宣言したときに限って `style.toml` を監視する。

## 実装すること

### 宣言

プラグインは、`golem_describe` の記述の `context` に、受け取る文脈の名前を並べる。

```cddl
description = {
  ? "commands": [* tstr],
  ? "filters": [* tstr],
  ? "channels": [* channel-decl],
  ? "data": [* tstr],
  ? "context": [* context-name],
}
context-name = "vertical-numbers" / "writing-mode"
```

記述を名前のある map にする部分は、[docs/adr/0107](0107-named-describe-fields.md) が決める。
この ADR が決めるのは `context` のキーとその値である。

- 名前は上の一覧のいずれかである。一覧にない名前は新しいエラー G06105 とし、プラグインを読み込まない。宣言にある知らない名前をすべて、一つの diagnostic に並べる。
- 同じ名前を二度書いた宣言は、今の不正な `golem_describe`（G06005）とし、メッセージは `文脈の名前が重複しています: <名前>` とする。
- 名前が文字列でない宣言は、今の G06005（`名前が文字列ではありません`）のままである。
- 宣言しなかった名前の値は、要求に入らない。プラグインが宣言していない文脈を読む経路はないので、宣言していない名前についての diagnostic はない。

G06105 を G06005 と分けるのは、原因が違うからである。
G06005 はプラグインの記述が壊れていることを、G06105 はプラグインがこの Golem より新しい Golem のために作られていることを表す。
直し方も、前者はプラグインの作者に報告すること、後者は Golem を上げることであり、違う。

| コード | 重大度 | 原因 | メッセージ |
| --- | --- | --- | --- |
| G06105 | エラー | プラグインが、この Golem の渡せない文脈を宣言した | `<プラグイン>: Golem が渡せない文脈を求めています: <名前>、…（渡せる文脈: vertical-numbers、writing-mode）` |

位置は、ほかの読み込みの誤りと同じく `manifest.toml` の先頭である。

### 要求

```cddl
command-request = [0, name: tstr, args: [* argument], slots: [* inlines], span, context, data]
filter-request = [1, name: tstr, document, context, data]
context = [* context-entry]
context-entry = ["vertical-numbers", "kanji" / "kanji-digits" / "tcy" / "auto" / "auto-digits"]
              / ["writing-mode", "horizontal" / "vertical"]
```

- 文脈は、データ（[docs/adr/0105](0105-plugin-data.md)）の前に置く。データが要求の最後の欄であることは変わらない。
- 文脈は、宣言した名前だけを、名前のコードポイントの順に並べる。値は `style.toml` に書く字と同じ文字列である。
- `style.toml` に `[page]` がない本の `writing-mode` は `horizontal`、`[numbers]` の `vertical` を書かない本の `vertical-numbers` は既定の `kanji` である。どちらもレイアウトが使う値と同じである。
- 文脈の CBOR は、データと同じくプラグインを読み込んだときに一度だけ符号化する。
- 宣言のないプラグインの文脈は空の配列であり、要求のバイト列は `style.toml` によらない。

### 決定性と再評価

要求のバイト列は、原稿、データ、宣言した文脈だけで決まる。
同じ原稿、同じデータ、同じ `style.toml` からは、同じ要求と同じ出力と同じ diagnostic になる。
プラグインが宣言していない `style.toml` の値を変えても、そのプラグインの要求は変わらない。

文脈を宣言したプラグインがあるとき、S0 の結果は `style.toml` に依る。

- ビルドと `golem check` は、毎回 `style.toml` を読んでプラグインを読み込むので、変更は次の実行で反映される。
- LSP は、読み込んだプラグインのどれかが文脈を宣言しているとき、`style.toml` を `@table` のファイルと同じく監視する（`Evaluated` の `evTableFiles` に `style.toml` を加える）。ファイルが変われば、プロジェクトを評価し直す。
- エディタで開いた `style.toml` の未保存の内容は、今の評価が `style.toml` をディスクから読むので、使わない。プラグインに限らない今の振る舞いであり、この ADR では変えない。

### モジュールの変更

golem-* のパッケージのあいだの build-depends は変えない。

```haskell
-- Golem.Plugin
data HostContext = HostContext { hcWritingMode :: !Text, hcVerticalNumbers :: !Text }
contextNames :: [Text]                       -- ["vertical-numbers", "writing-mode"]
pluginContextNames :: Plugin -> [Text]
withPluginContext :: HostContext -> Plugin -> Plugin
data PluginError = ... | UnknownContext [Text]   -- G06105

-- Golem.Eval.File
data PluginHook = PluginHook { ..., phContextNames :: ![Text] }

-- Golem.Driver.Plugins
loadPlugins :: FilePath -> Map FilePath Text -> FilePath -> FileId -> FileId -> Text -> HostContext -> Manifest -> IO (Either [Diagnostic] PluginHook)
```

補助のクレート（[docs/adr/0106](0106-sample-plugins-in-rust.md)）は、`Description::context` と、要求の `Context`（`get` と `vertical`）を持つ。

### ドキュメント

- docs/specifications.md の「プラグイン」に「本の文脈」の節を足し、diagnostic の範囲を G06105 までにする。
- docs/diagnostics.md に G06105 を足す（試しの実装で足した）。
- 開発者のマニュアルのプラグインの章の CDDL と `golem_describe` の説明を直す。
- `modules/golem-doc/schema/golem-doc.cddl` を上の形にする（試しの実装では、記述は位置の五つめの欄）。

## 実装しないこと

- `language` と出力の媒体を一覧に入れること。上の「候補の名前」に理由を書いた。
- `style.toml` の全体や任意のキーをプラグインに渡すこと。一覧を閉じるのは、要求が依る入力を ABI の版ごとに数えられるようにするためである。
- ファイルや節ごとの書字方向。Golem は本ごとに一つの書字方向しか持たない。
- エディタの未保存の `style.toml` を評価に使うこと。

## テスト設計

下のテストのうち、見本のプラグイン kansuji（[docs/adr/0125](0125-kansuji-plugin-overrides-number-text.md)）と auto-tcy（[docs/adr/0128](0128-auto-tcy-filter.md)）を使うものは、この ADR の実装では書かない。
この ADR の実装では、同じことを wat のテスト用のプラグイン（`modules/golem-plugin/test/` と golem-driver のテストの wat）で確かめるテストを先に書く。
見本のプラグインを使うテストは、結合のテストとして、その見本のプラグインの ADR を実装するときに足す。
見本のプラグインの ADR が、この ADR より後に実装されるからである。

試しの実装で、次のテストを先に書き、失敗すること（コンパイルできないことを含む）を確かめてから実装した。

golem-plugin の `ContextSpec` では、次のことを確かめる。

- 記述の文脈の名前が `pluginContextNames` になる。四つの欄の記述は G06005 の形の誤りである。
- 知らない名前（`language`、`medium`）が `UnknownContext` になり、すべての名前を並べる。同じ名前を二度書くと `文脈の名前が重複しています` になる。
- コマンドの要求の文脈がデータの前にあり、宣言した名前だけを名前の順に持つ。
- 宣言のないプラグインの要求は、縦組みと横組みの本で同じバイト列になる。
- フィルタの要求が `[1, 名前, 文書, 文脈, データ]` になる。

golem-driver の `PluginsSpec` では、次のことを確かめる。

- `language` を宣言する wat のプラグインが、`manifest.toml` の先頭の G06105 になる。
- `kansuji` の `style` のない数が `[numbers]` の `vertical` の表記になり、横組みの本では整数が数のノード、有理数が `3.14` と `2/3` になる。
- `auto-tcy` が横組みの本で文書を変えず、警告も出さない。`config` の誤りは横組みでも報告する。
- `kansuji` を読み込むと `evTableFiles` に `style.toml` が入り、文脈を宣言しない `lookup` では入らない。

補助のクレートの単体テストでは、要求の文脈の読み方、文脈の欄のない要求が読めないこと、記述の五つの欄を確かめる。

手で確かめたこと：縦組みと横組みの小さなプロジェクトを `golem build` で組み、横組みの PDF とプレーンテキストに漢数字と縦中横が出ないことを確かめた。

## トレードオフ

文脈を宣言したプラグインがあると、`style.toml` の変更でプロジェクトの全体を評価し直す。
文脈を宣言したプラグインを使うファイルだけを評価し直すほうが速いが、今の LSP は `@table` のファイルの変更でも全体を評価し直しており、それに揃えた。

一覧を閉じたので、新しい文脈を使いたいプラグインは、Golem の新しい版を待つ必要がある。
その代わり、要求が依る入力は版ごとに決まり、プラグインが本の任意の設定に依ることはない。

プラグインが書字方向で出力を変えられるので、同じ原稿でも `style.toml` によって S0 の文書が変わる。
組み込みの数のノードは表記をレイアウトまで遅らせるので S0 は変わらなかったが、プラグインには表記を遅らせる IR がない。
IR に「書字方向で変わる文字列」のノードを足す案もあったが、プラグインが二通りの中身を書く必要があり、ルビや圏点の中での規則も決める必要があるので採らなかった。

## 決めたことの記録

- **書字方向を要求に入れるか**：メンテナーが、入れると決めた（2026-10-29）。あわせて、プラグインが要るものを宣言し、ホストは宣言されたものだけを送る一般の仕組みにし、名前の一覧は閉じて ABI と一緒に版を管理すると決めた。
- **記述の形**：メンテナーが、`golem_describe` の欄を名前のある map にすると決めた。この ADR の宣言は、その map のキー `context` とする。
- **今入れる名前**：この草稿は、`writing-mode` と `vertical-numbers` を入れ、`language` と出力の媒体を入れない案にした。メンテナーが、`language` と出力の媒体は今は入れないことでよいと決めた（2026-10-29）。理由は、メンテナーが S1 と S2 を、ビルドの結果を変えない形で段階的にプラグインに開く予定であり、媒体ごとの情報はその段階で扱えるので、今の S0 の要求に入れる必要がないからである。
- **エディタで開いたまま保存していない style.toml**：メンテナーが、今のとおりディスクから読むことでよいと決めた（2026-10-29）。
- **知らない名前のコード**：この草稿は、G06005 から分けて G06105 にする案にした。同じ名前の二度書きは、記述の形の誤りとして G06005 に残した。
- **テストのプラグイン**：メンテナーが、土台の ADR は wat のテスト用のプラグインで試し、見本のプラグインを使う結合のテストは見本のプラグインの実装のときに足す運用にすると決めた（2026-11-04）。

## 参考文献

- RFC 8949, Concise Binary Object Representation (CBOR). https://www.rfc-editor.org/rfc/rfc8949
- RFC 8610, Concise Data Definition Language (CDDL). https://www.rfc-editor.org/rfc/rfc8610
