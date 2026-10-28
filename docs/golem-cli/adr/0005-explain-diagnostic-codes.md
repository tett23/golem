# ADR 0005: 診断のコードの説明を golem explain で表示する

ステータス: 採択→説明の文書の重大度の「お知らせ」は [golem-syntax ADR 0002](../../golem-syntax/adr/0002-notice-severity.md)、重大度の「プリフライトの設定による」と区分 09 は [ADR 0006](0006-preflight.md)、複数のコードと、コードを実行の段階で検査することは [ADR 0009](0009-explain-several-codes.md)

## 文脈

Golem の診断は、コード（`G07001` など）、重大度、位置、一行のメッセージを持つ（[golem-syntax ADR 0001](../../golem-syntax/adr/0001-source-spans-and-diagnostics.md)）。
人が読む形式では `a.gm:3:1: error[G01017]: 閉じ括弧 ] がありません` のように出る。
メッセージは一行なので、なぜその誤りになるのか、どう直せばよいのかまでは書けない。
とくにレイアウトと出力の診断（`G07xxx`、`G08xxx`）は、原因が `style.toml` と原稿の組み合わせにあり、一行からは直し方を読み取りにくい。

コードの一覧と説明は、どこにもない。
[golem-syntax ADR 0001](../../golem-syntax/adr/0001-source-spans-and-diagnostics.md) は「コードの一覧は golem-syntax の中に一箇所で定義する」と決めたが、実装されていない。
今のコードは、各モジュールのソースに文字列のリテラル（`diagnostic "G03006" Error …` など）として散らばっている。
`git grep` で `modules/*/src` を数えると、G01001 から G08006 までの 120 個ほどのコードが使われている。
golem-syntax にあるのは、プロファイルで重大度が変わるコードの一覧（`profileDependentCodes`）だけである。

使わなくなったコードもある。
G02044（`@verse` の引数）は [docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md) で使わなくなった。
コードは別の意味に再利用しないので、使わなくなったコードも、CI のログや過去の資料に残った値として意味を引ける必要がある。

ほかの処理系では、rustc が `rustc --explain E0308` でエラーのコードの説明を表示し、診断の末尾でこのコマンドを案内する。
説明はリポジトリの中の Markdown のファイルで、コンパイラーに埋め込まれている（記憶による）。

## 実装すること

### 説明の文書

説明は `docs/diagnostics.md` の一つの Markdown のファイルに書く。
人が GitHub で読む一覧と、`golem explain` が表示する本文を、同じファイルにする。

各コードは、次の形の節にする。

````markdown
## G07001

版面を計算できません

- 重大度: エラー
- 状態: 使用中

### 意味

PDF のページの幾何（判型、版面、傍注欄、マスターページの位置）を計算できませんでした。
…

### 主な原因

- `style.toml` に `[page]` か `[page.grid]` がない。
- 版面が判型からはみ出している。
…

### 直し方

版面がはみ出している場合は、字数か行数を減らすか、`position` の `top` と `gutter` を小さくします。

```toml
[page.grid]
characters = 38   # 42 から減らす
```
````

- 節の見出しは `## ` とコードだけとする。GitHub の見出しの id がコードの小文字（`#g07001`）になり、LSP から直接に節を指せる。
- 見出しの次の段落を、一行の題とする。`golem explain` の一覧に使う。
- 重大度は「エラー」「警告」「dev では警告、prod ではエラー」のいずれかとする。最後のものは `profileDependentCodes` のコードに使う。
- 状態は「使用中」か「廃止」とする。廃止したコードには、廃止した ADR へのリンクと、代わりの書き方を書く。廃止したコードの節には「主な原因」を書かなくてよい。
- 使用中のコードの節は、「意味」「主な原因」「直し方」の三つの小見出しをこの順に持ち、どれも空にしない。
- 節はコードの昇順に並べる。
- 文書の先頭に、コードの上 2 桁と発生源の対応（[golem-syntax ADR 0001](../../golem-syntax/adr/0001-source-spans-and-diagnostics.md) の表）と、プラグインが出す診断のコードはこの文書の対象外であることを書く。
- 言語は日本語だけとする。診断と CLI の文言を日本語だけにすると決めている（[golem-syntax ADR 0001](../../golem-syntax/adr/0001-source-spans-and-diagnostics.md)、[ADR 0004](0004-usage-error-exit-code.md)）。

### 実行ファイルへの埋め込み

`docs/diagnostics.md` を golem-driver に埋め込む。
`modules/golem-driver/VERSION` と同じく、`modules/golem-driver/diagnostics.md` を `../../docs/diagnostics.md` への記号リンクとして置き、`extra-source-files` に加える。

golem-driver に二つのモジュールを足す。

```haskell
-- Golem.Driver.Explain.Catalog（Template Haskell から呼ぶので別のモジュールにする）
data Status = InUse | Retired
data Explanation = Explanation
  { exCode   :: !Text      -- "G07001"
  , exTitle  :: !Text      -- 見出しの次の段落
  , exStatus :: !Status
  , exBody   :: !Text      -- "## G07001" の行から次の "## " の直前まで（末尾の空行を除く）
  }
parseCatalog :: Text -> Either Text [Explanation]

-- Golem.Driver.Explain
catalog :: Map Text Explanation
lookupExplanation :: Text -> Maybe Explanation   -- 大文字と小文字を区別しない
explainHint :: [Diagnostic] -> Text
codeDescriptionUrl :: DiagnosticCode -> Maybe Text
```

- `catalog` は、Template Haskell でコンパイルのときにファイルを読み（`addDependentFile`）、`parseCatalog` にかける。`parseCatalog` が `Left` を返せばコンパイルを失敗させる。形の崩れた文書を持つ実行ファイルはできない。
- `parseCatalog` は、上の節の形の規則（見出し、題、重大度、状態、三つの小見出し、昇順、重複のなさ）をすべて検査し、最初に破られた規則と行の番号を `Left` で返す。
- golem-driver の `build-depends` には `template-haskell` がすでにある。Markdown の解析のライブラリは加えない。読むのは `## `、`### `、`- 重大度: `、`- 状態: ` で始まる行だけであり、行の単位の分割で足りる。

### golem explain

golem-cli に `golem explain [CODE]` を加える。

- `golem explain G07001` は、`exBody` を標準出力にそのまま書き、終了コード 0 で終わる。Markdown の記号は端末でも読めるので、整形し直さない。
- コードは大文字と小文字を区別しない（`g07001` も受け付ける）。
- 廃止したコードも表示する。終了コードは 0 とする。
- `golem explain` を引数なしで実行すると、すべてのコードを一行に一つずつ、コードの昇順に `G07001  版面を計算できません` の形で書く。廃止したコードには題の後に `（廃止）` を付ける。
- 引数の検査は、optparse-applicative の `ReadM` で引数の解釈の段階で行う。[ADR 0004](0004-usage-error-exit-code.md) と同じく、誤りは使い方の誤りとして終了コード 2 にする。
  - `G` と 4 桁の数字の形でない値：`診断のコードは G と 4 桁の数字です: <値>`
  - 形は正しいが文書にないコード：`未知の診断のコードです: <値>。プラグインが出す診断は、プラグインの文書を参照してください`
- ヘルプのコマンドの説明は `診断のコードの説明を表示する` とする。

### 診断の表示からの案内

人が読む形式で診断を出した後に、文書にあるコードが一つでもあれば、標準エラー出力に次の一行を加える。

```
コードの説明は golem explain <コード> で表示できます（例: golem explain G01017）
```

- 例のコードは、出した診断のうち文書にあるコードの最小のものとする。診断の並びは決定的なので、この行も決定的になる。
- 一行だけ加え、診断ごとには加えない。診断が多いビルドで出力が倍に増えないようにするためである。
- この行は `explainHint` が作り、文書にあるコードがなければ空を返す。プラグインのコードだけの場合は加えない。
- golem-cli で `renderHuman` を呼ぶすべての箇所（`report`、`golem fmt` の構文エラー、マニフェストと `plugins.lock` の読み込みの誤り）で、`renderHuman` の出力の後に `explainHint` を書く。
- `renderHuman`（golem-syntax）は変えない。golem-syntax は文書を知らず、ほかの呼び出し元に案内を混ぜないためである。
- `--format json` には加えない。JSON は一つの配列であり、末尾に文を足すと JSON として読めなくなる。

### LSP の codeDescription

golem-lsp の `toDiagnostic` で、文書にあるコードの診断に `codeDescription` を付ける。

- `href` は `https://github.com/tett23/golem/blob/main/docs/diagnostics.md#g07001` の形とし、`codeDescriptionUrl` が作る。
- 版のタグではなく `main` を指す。開発中の版は対応するタグを持たず、コードは別の意味に再利用しないので、`main` の説明は古い版の Golem が出したコードにも当てはまる。
- プラグインのコードには付けない。
- クライアントの能力の `codeDescriptionSupport` は見ない。LSP 3.17 では任意の欄であり、対応しないクライアントは無視する。

### ドキュメント

- `docs/diagnostics.md` を作り、`modules/*/src` と `modules/golem-cli/app` で使っているすべてのコードと、廃止した G02044 の説明を書く。
- 仕様書の「構文木と診断」の節に、コードの説明が `docs/diagnostics.md` にあり、`golem explain` で表示できること、新しいコードを足すときは同じ変更で説明を足すことを書く。
- 仕様書の「CLI」の表に `golem explain [CODE]` を加える。
- 仕様書の「v1 の実装で次の段階以降に回した項目」から「診断のコードの説明」を削る。
- README のコマンドの表に `golem explain` を加える。
- [golem-syntax ADR 0001](../../golem-syntax/adr/0001-source-spans-and-diagnostics.md) のステータスの行を「採択→コードの一覧は golem-cli ADR 0005」に変え、この ADR へのリンクを、書き込む先のファイルからの相対パスで付ける。

## 実装しないこと

- 英語など、日本語以外の説明。
- コードの一覧を Haskell の型（コードの列挙）として golem-syntax に置き、ソースの文字列のリテラルを置き換えること。120 個ほどの呼び出し箇所を書き換えることになり、説明の漏れを検出する目的には、次のテスト設計のソースの走査で足りる。
- 説明の Markdown を端末向けに整形すること（色、太字、ページャー）。
- プラグインが出す診断の説明。プラグインのコードはプラグインが決めるので、Golem の文書には載せない。プラグインが `G` で始まるコードを出すことを禁じるかは、この ADR では決めない。
- LSP のホバーやコードアクションで説明を表示すること。`codeDescription` のリンクで足りる。
- 診断ごとの案内の行と、JSON の出力の案内の欄。

## テスト設計

先に次のテストを書いて失敗させる。

### 説明の漏れの検出（`modules/golem-driver/test/Main.hs`）

テストは golem-driver のディレクトリで動くので、`../../VERSION` を読む既存のテストと同じく、`../` からほかのモジュールのソースを読む。

- `../*/src` と `../golem-cli/app` の下のすべての `.hs` のファイルから、`"G` に 4 桁の数字と `"` が続く文字列のリテラルを集め、使っているコードの集合を作る。テストのディレクトリ（`test/`）は読まない。テストは誤りを起こすためにコードを書くので、使っているコードの根拠にならない。
- 使っているコードのそれぞれが、`catalog` に状態「使用中」で載っていること。漏れたコードの一覧を失敗のメッセージに出す。
- `catalog` の状態「使用中」のコードのそれぞれが、使っているコードの集合にあること。使わなくなったコードは「廃止」にしなければならない。
- `catalog` の状態「廃止」のコードが、使っているコードの集合にないこと。
- `profileDependentCodes` のコードの重大度が「dev では警告、prod ではエラー」であり、それ以外のコードの重大度がそうでないこと。

### 文書の形（`modules/golem-driver/test/Main.hs`）

`parseCatalog` に小さな文書を与えて確かめる。

- 正しい二つの節から、題、状態、本文が取り出せる。
- 「直し方」がない節、題がない節、状態がない節、重大度の値が不正な節、昇順でない節、同じコードが二度ある節が、それぞれ `Left` になり、メッセージに行の番号が含まれる。
- 廃止の節は「主な原因」がなくても `Right` になる。

### golem explain（`modules/golem-cli/test/Main.hs`）

- `golem explain G01017` の出力が `## G01017` で始まり、終了コードが 0 になる。
- `golem explain g01017` の出力が `golem explain G01017` と同じになる。
- `golem explain G02044` が廃止の節を表示し、終了コードが 0 になる。
- `golem explain` の出力の行の数が `catalog` の要素の数と等しく、`G02044` の行に `（廃止）` がある。
- `golem explain G9999` と `golem explain nope` の終了コードが 2 になる。両者の出力を golden テストで固定する。
- `golem explain --help` の出力を golden テストで固定する。
- 構文エラーのある原稿で `golem check` を実行すると、標準エラー出力の最後の行が `コードの説明は golem explain <コード> で表示できます（例: golem explain G01017）` になる。`--format json` では、標準エラー出力が JSON として読める。

### LSP（`modules/golem-lsp/test/Main.hs`）

- `protocol` のセッションの golden（`test/golden/protocol.txt`、`protocol-utf8.txt`）に、診断の `codeDescription` の行を加える。G01017 の診断で `https://github.com/tett23/golem/blob/main/docs/diagnostics.md#g01017` になる。
- 単体：`codeDescriptionUrl (DiagnosticCode "X001")` が `Nothing` になる。

### 実装の後の確かめ

- GitHub で `docs/diagnostics.md` を開き、`#g01017` の URL で G01017 の節に移ることを確かめる。見出しの id がコードの小文字になるという前提は記憶によるので、ここで確かめる。

## トレードオフ

説明をソースではなく `docs/diagnostics.md` に置くので、新しいコードを足す人は、ソースと文書の二か所を変える必要がある。
漏れはテストが検出するので、説明のないコードが main に入ることはない。
その代わり、説明が実行ファイルと GitHub の両方で読め、文書を直すのにソースを読む必要がない。

ソースの文字列のリテラルを走査して使っているコードを集めるので、コードを文字列の連結や変数で組み立てると検出できない。
今のソースにはそのような箇所がない（すべて `"G` と 4 桁の数字のリテラルである）。
コードの列挙の型を作れば型で保証できるが、[golem-syntax ADR 0001](../../golem-syntax/adr/0001-source-spans-and-diagnostics.md) の一覧を一箇所に置く決定を、型ではなく文書と検査で実現することを選ぶ。

診断の後の案内の行は、CI のログに毎回一行を足す。
一行に限り、JSON の出力には足さないので、機械が読む出力には影響しない。

LSP の `codeDescription` は `main` を指すので、説明の文面は利用者の手もとの版と食い違うことがある。
コードの意味は変わらないので、食い違うのは説明の書きぶりと、新しい版で足した直し方に限られる。
手もとの版と一致する説明は `golem explain` で読める。

120 個ほどのコードの説明を一度に書く必要がある。
説明の質はレビューで保ち、テストが保証するのは節があることと形だけである。
