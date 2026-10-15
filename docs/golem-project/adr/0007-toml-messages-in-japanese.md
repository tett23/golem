# ADR 0007: TOML の誤りの文言を日本語にする

ステータス: 採択

## 文脈

`style.toml` のキーを一つ綴り違えると、Golem は `unexpected key: bindng (.page)` と英語で答える。
ほかの診断の文言はすべて日本語なので、設定の誤りだけが英語で出る。
利用者のマニュアルは G0306 の説明で「今の版では、知らないキーのメッセージは英語です」と断っている（manual/ の付録D「診断の一覧」。[golem-cli ADR 0006](../../golem-cli/adr/0006-preflight.md) で付録E に繰り下がる）。

この英語は toml-parser 2.0.2.0 の文言である。
[golem-project ADR 0006](0006-project-diagnostic-codes.md) は、Golem のソースが書いた英語の文言（`column-gap is required when columns > 1` など）を日本語に改め、toml-parser 自身の文言は英語のまま残すと決めた。
理由は「翻訳すると toml-parser の版が上がるたびに文言の対応を保つ必要があり、その手間に見合わない」である。
docs/specifications.md の「構文木と診断」も同じことを書いている。
v1 の実装の後、この判断を見直す項目が「今後の実装項目」の「記法と設定」に残った。

### 今の経路

TOML の読み込みは、golem-project の `Golem.Project.Manifest.decodeStrictBy` に集まっている。

1. `Toml.parse` で構文を読む。失敗は `String` の一つの文言で返る。Golem はその前に `TOML の誤りです: ` を付け、位置をファイルの先頭にした診断を一つ作る。
2. `runMatcher (fromValue ...)` でスキーマと照合する。失敗と警告は `MatchMessage Position` の列で返る。`tomlDiagnosticsBy` が、文言に ` (<経路>)` を足して、値の位置の診断にする。未知のキーは toml-parser では警告だが、`decodeStrictBy` はエラーにする。

この関数を使うのは、`manifest.toml`（G0301）、`style.toml`（G0306、G0320、G0321）、golem-plugin の `plugins.lock`（G0611）である。
`Golem.Project.Style.readLocal` は、原稿の `@style-def` のキーと値を TOML の値に直して同じ照合にかけ、文言に ` (<キー>)` の形で経路を足す。

### toml-parser の文言の出どころ

toml-parser 2.0.2.0 のソースを読むと、文言は構成子ではなく文字列として作られている。
`MatchMessage` の `matchMessage` は `String` であり、種類を表す構成子はない。
文言の出どころは次の四つに限られる。

**スキーマの照合**：`Toml.Schema.ParseTable` の `unexpected key: <キー>` と `missing key: <キー>`、`Toml.Schema.FromValue` の `typeError` が作る `expected <型> but got <型>`。
ほかに `integer out of range for <型>`、`expected single character`、`finite float required`、`non-empty list required` がある。
型の名前は `Toml.Semantics.Types.valueType` の `integer`、`float`、`array`、`table`、`boolean`、`string`、`local time`、`local date-time`、`offset date-time` と、日付の `locate date`（綴りの誤りもそのまま）である。

**字句の誤り**：`Toml.Syntax.LexerUtils` と `Lexer.x` が作り、`lexical error: ` が前に付く。
`unterminated basic string` などの閉じていない文字列の四種、`unexpected end-of-input`、`unexpected end-of-line`、`control characters prohibited`、`unexpected <文字>`、`control characters must be escaped, use: \uXXXX`、`non-scalar unicode escape`、`unicode escape too large`、`malformed <日時の種類>`、`leading zero prohibited`、`unknown escape sequence`、`incomplete escape sequence` である。

**構文の誤り**：`Toml.Syntax.ParserUtils.errorP` の `parse error: unexpected <字句>`。
字句の名前は `Toml.Pretty.prettyToken` の `'='`、`end-of-line`、`bare key`、`string` などである。

**意味の誤り**：`Toml.Semantics.SemanticError` は構成子を持つ。
`AlreadyAssigned`、`ClosedTable`、`ImplicitlyTable` の三つと、キーと位置である。

`Toml.parse` はこれらを `行:桁: ` で始まる一つの文字列に畳んで返す。
一方、`Toml.parse'` は畳む前の `DecodeError`（`ErrSyntax (Located String)` と `ErrSemantics (SemanticError Position)`）を返す。
`parse'` を使えば、構文の誤りにも位置が取れる。
[golem-project ADR 0006](0006-project-diagnostic-codes.md) は、位置を文言の `行:桁` から取り出すことを、文言の形が版で変わりうるとして見送った。
`parse'` は型で位置を渡すので、この心配はない。

### 版を上げる手間

[ADR 0006](0006-project-diagnostic-codes.md) の心配は、翻訳が文言の文字列に依存することである。
これは今も変わらない。
ただ、toml-parser の版は `golem-project.cabal` で `>=2.0 && <2.1` に、`cabal.project.freeze` で 2.0.2.0 に固定されている。
版を上げるのは、[CONTRIBUTING.md](../../../CONTRIBUTING.md) の手順でプルリクエストに理由を書くときだけである。
そのときに翻訳の表が古くなったことをテストが知らせれば、手間は版を上げる作業の中に収まる。
文言の数は上の四つの出どころで三十に満たない。

## 実装すること

### 翻訳の置き場所

golem-project に `Golem.Project.TomlMessage` を加え、toml-parser の誤りを日本語の文言にする関数をここに集める。

```haskell
-- スキーマの照合の文言（経路を除く）
schemaMessage :: String -> Text
-- 字句と構文の誤り（位置を除いた文言）
syntaxMessage :: String -> Text
-- 意味の誤り
semanticMessage :: SemanticErrorKind -> Text -> Text   -- 種類とキー
-- 経路の表記
pathText :: [Scope] -> Text
```

`decodeStrictBy` と `Style.readLocal` は、どちらもこの関数を通して文言を作る。
`plugins.lock`（G0611）も `decodeStrict` を通るので、同じく日本語になる。

### 読み込みの経路

- `decodeStrictBy` は `Toml.parse` の代わりに `Toml.parse'` を使う。
- `ErrSyntax (Located pos s)` は、`pos` の位置の診断にする。文言は `TOML の誤りです: ` に `syntaxMessage s` を続ける。
- `ErrSemantics (SemanticError pos key kind)` は、`pos` の位置の診断にする。文言は `TOML の誤りです: ` に `semanticMessage kind key` を続ける。
- スキーマの照合の文言は、`schemaMessage` で訳し、経路を下の形で添える。
- 位置が取れないとき（`MatchMessage` の位置が `Nothing`）は、今と同じくファイルの先頭とする。
- 診断のコードは変えない。`manifest.toml` は G0301、`style.toml` は G0306（アキの量は G0320、`features` の欄は G0321）、`plugins.lock` は G0611 のままである。

### 文言

スキーマの照合の文言は次のとおりとする。
`<キー>` には、toml-parser が `prettySimpleKey` で書いた形（裸のキーはそのまま、そうでないキーは引用符つき）をそのまま使う。

| toml-parser の文言 | 日本語の文言 |
| --- | --- |
| `unexpected key: <キー>` | `知らないキーです: <経路>.<キー>` |
| `missing key: <キー>` | `必須のキーがありません: <経路>.<キー>` |
| `expected <型1> but got <型2>` | `<経路> には<型1>を書きます（<型2>が書かれています）` |
| `integer out of range for Natural` | `<経路> には 0 以上の整数を書きます` |
| `integer out of range for <型>`（Natural 以外） | `<経路> の整数が大きすぎるか小さすぎます` |
| `expected single character` | `<経路> には一文字を書きます` |
| `finite float required` | `<経路> には有限の数を書きます（inf と nan は使えません）` |
| `non-empty list required` | `<経路> には空でない配列を書きます` |

未知のキーと必須のキーは、経路にキーを足した完全な名前で示す。
toml-parser の警告は表の経路の中で出るので、経路だけではどのキーかがわからないためである。
経路が空のとき（ファイルの最上位）は、`<経路>.` を付けずにキーだけを書く。

型の名前は次のように訳す。

| toml-parser | 日本語 |
| --- | --- |
| `integer` | 整数 |
| `float` | 小数 |
| `string` | 文字列 |
| `boolean` | 真偽値 |
| `array` | 配列 |
| `table` | 表 |
| `local date`、`locate date` | 日付 |
| `local time` | 時刻 |
| `local date-time` | 時差のない日時 |
| `offset date-time` | 時差つきの日時 |

`<型1>` には、Golem が `typeError` に渡した期待の説明も来る。
Golem のソースに残る二つの `typeError`（`Style` の判型の `page size name or { width = ..., height = ... }` と、柱の位置の `position such as top-outside`）は、[golem-project ADR 0006](0006-project-diagnostic-codes.md) がほかの `typeError` にしたのと同じく `fail` に改める。
文言は `判型の名前か { width = ..., height = ... } を書きます` と `top-outside のような位置を書きます` とする。
これで `<型1>` に来るのは上の表の型の名前だけになる。

字句と構文の誤りは次のとおりとする。
`lexical error: ` と `parse error: ` の前置きは、どれも訳した文言では落とす。

| toml-parser の文言 | 日本語の文言 |
| --- | --- |
| `unterminated basic string` | `文字列が閉じていません` |
| `unterminated literal string` | `リテラル文字列が閉じていません` |
| `unterminated multi-line basic string` | `複数行の文字列が閉じていません` |
| `unterminated multi-line literal string` | `複数行のリテラル文字列が閉じていません` |
| `unexpected end-of-input` | `ファイルが途中で終わっています` |
| `unexpected end-of-line` | `行が途中で終わっています` |
| `control characters prohibited` | `制御文字は書けません` |
| `control characters must be escaped, use: \uXXXX` | `制御文字はエスケープします（\uXXXX と書きます）` |
| `unexpected <文字>` | `ここに <文字> は書けません` |
| `non-scalar unicode escape` | `サロゲートの符号位置は \u で書けません` |
| `unicode escape too large` | `\U の値が Unicode の範囲を超えています` |
| `malformed <日時の種類>` | `<日時の種類の訳>の書き方が不正です` |
| `leading zero prohibited` | `整数の先頭に 0 は書けません` |
| `unknown escape sequence` | `知らないエスケープです` |
| `incomplete escape sequence` | `エスケープが途中で終わっています` |
| `parse error: unexpected <字句>` | `ここに<字句の訳>は書けません` |

字句の名前は、`'='` のような記号はそのまま、`end-of-line` は「行末」、`end-of-input` は「ファイルの終わり」、`bare key` は「キー」、`string` は「文字列」、`multi-line string` は「複数行の文字列」、`integer` は「整数」、`float` は「小数」、`true literal` と `false literal` は「真偽値」とし、日時の四種は型の名前の表に従う。

意味の誤りは次のとおりとする。

| 構成子 | 日本語の文言 |
| --- | --- |
| `AlreadyAssigned` | `同じキーに二度値を書いています: <キー>` |
| `ClosedTable` | `閉じた表にキーを足しています: <キー>` |
| `ImplicitlyTable` | `表として定まったキーを表の配列にはできません: <キー>` |

### 経路の表記

経路は、TOML のキーを `.` でつなぎ、配列の添字を `[0]` の形で書く（例：`page.bleed`、`targets.html`、`chapters[0]`、`paragraph-styles.body.font`）。
今の ` (.page)` の形をやめ、文言の中に経路を置く。
先頭の `.` は付けない。
`@style-def` のキーは、`readLocal` が `<キー>` だけを経路に持つので、`font` のように一語になる。

### 訳のない文言

`schemaMessage` と `syntaxMessage` は、表にない文言を受けたとき、文言を変えずに返す。
Golem が `fail` で書いた日本語の文言はここを通る。
表にない英語の文言が出るのは、toml-parser の版を変えたときだけであり、それは下のテストが止める。

## 実装しないこと

- toml-parser に手を入れること、toml-parser をやめて TOML の読み込みを再実装すること。
  文言の構成子を持つ版を上流に提案することも、この ADR の範囲に入れない。
- 原稿のエスケープや Golem の式のような、TOML 以外の誤りの文言。
- 未知のキーに綴りの近いキーを示すこと（「bindng ではなく binding ですか」）。
  キーの一覧を `FromValue` の外から取る手段がない。
- 英語の文言を残す選択肢（`--lang` のような切り替え）。
  v1 の診断は日本語だけと決めている（[golem-syntax ADR 0001](../../golem-syntax/adr/0001-source-spans-and-diagnostics.md)）。

## テスト設計

### 先に書いて失敗させるテスト

`modules/golem-project/test/Main.hs`：

- `style.toml` に `[page]` の `bindng = "left"` を書くと、G0306 の文言が `知らないキーです: page.bindng` で、位置がその行であること。
- `manifest.toml` から `[metadata]` を除くと、G0301 の文言が `必須のキーがありません: metadata` であること。
- `[metadata]` から `title` を除くと、文言が `必須のキーがありません: metadata.title` であること。
- `[page] bleed = 3` が `page.bleed には文字列を書きます（整数が書かれています）` であること。
- `[page] size = 3` が、判型の新しい文言で始まること。
- `chapters = [3]` の文言が、経路 `chapters[0]` を含むこと。
- `style.toml` の `[page]` を二度書くと、`TOML の誤りです: ` で始まり、`閉じた表にキーを足しています` か `同じキーに二度値を書いています` を含み、位置が二つ目の `[page]` の行であること（どちらになるかは toml-parser の判定に従い、テストで一方に固定する）。
- 閉じていない文字列 `title = "abc` が `TOML の誤りです: 文字列が閉じていません` で、位置がその行であること。
- `title = ` で行が終わると `TOML の誤りです: ` で始まり、`行末` を含むこと。
- `n = 012` が `整数の先頭に 0 は書けません` を含むこと。
- `@style-def` の値の型の誤りの文言が、`font には文字列を書きます（整数が書かれています）` の形であること（`modules/golem-eval/test` の `@style-def` のテストに加える）。
- `plugins.lock` の未知のキーが G0611 で `知らないキーです: ` で始まること（`modules/golem-plugin/test`）。

`modules/golem-project/test/TomlMessageSpec.hs`（新設）：

- toml-parser 2.0.2.0 が作りうる文言を、上の四つの表の左の列からすべて並べ、`schemaMessage` か `syntaxMessage` が元の文言と異なる文字列を返すこと。
  型の名前の組み合わせは、`valueType` の十種と期待の型の名前の全組を確かめる。
- 実際の TOML の断片から作った誤りが、表の左の列の文言のどれかに一致すること。
  字句の誤りの各種、構文の誤り、意味の誤りの三種、照合の誤りの各種を、一つずつ断片で起こす。
  toml-parser の版を変えて文言が変われば、ここが落ちる。
- 表にない文言（`foo`）を `schemaMessage` が変えずに返すこと。

`modules/golem-cli/test/Main.hs`：

- `golem check` の人が読む出力に、`unexpected key`、`missing key`、`expected `、`lexical error`、`parse error` のどれも現れないこと（G0301 と G0306 を起こすプロジェクトで確かめる）。

### 自動テストにしない確かめ方

なし。

## トレードオフ

文字列に合わせて訳すので、toml-parser が文言を変えると訳が外れる。
外れた文言は英語のまま出るだけで、診断そのものは失われない。
テストが版の更新のプルリクエストで外れを知らせるので、版を上げる人が表を直す。
[golem-project ADR 0006](0006-project-diagnostic-codes.md) が見積もった手間は、この形で版の更新の作業に含めて払う。

`parse'` に替えると、構文の誤りがファイルの先頭ではなく誤りの行に出る。
エディタと CLI のどちらにとっても得であり、失うものは見当たらない。

経路の表記を ` (.page)` から文言の中の `page.bindng` に変えるので、今の文言に合わせたテストとスクリプトは直す必要がある。
v1 のリリースの前なので、この変更を受け入れる。

## ドキュメント

- docs/specifications.md の「構文木と診断」の「toml-parser 自身の文言（`missing key` など）は英語のまま出す」を、TOML の誤りの文言はすべて日本語にし、構文の誤りもその行の位置で出すと改め、この ADR へリンクする。
- 同じく「今後の実装項目」の「記法と設定」から「style.toml の未知のキーの診断」の項を除く。
- docs/diagnostics.md の G0301、G0306、G0321、G0611 の節のメッセージの欄から「toml-parser 自身の文言は英語のままである」の旨を除き、代表の文言（`知らないキーです: <経路>.<キー>` など）を書く。ADR の欄にこの ADR を加える。
- [golem-project ADR 0006](0006-project-diagnostic-codes.md) のステータスの行を「採択→toml-parser の文言の扱いは [ADR 0007](0007-toml-messages-in-japanese.md)」とする。
- 利用者のマニュアル（manual/ の付録E「診断の一覧」。[golem-cli ADR 0006](../../golem-cli/adr/0006-preflight.md) より前に実装するときは付録D）の G0306 の説明から「今の版では、知らないキーのメッセージは英語です」を除き、知らないキーの例の文言を日本語にする（[docs/adr/0024](../../adr/0024-manual-audiences-and-policy.md)）。

## 参考文献

- TOML v1.0.0, https://toml.io/en/v1.0.0
- toml-parser 2.0.2.0（Hackage）のソース：`Toml.Schema.ParseTable`、`Toml.Schema.FromValue`、`Toml.Semantics`、`Toml.Semantics.Types`、`Toml.Syntax.Lexer`、`Toml.Syntax.LexerUtils`、`Toml.Syntax.ParserUtils`、`Toml.Pretty`、`Toml`
