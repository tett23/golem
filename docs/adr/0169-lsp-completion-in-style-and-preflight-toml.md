# ADR 0169: LSP で style.toml と preflight.toml のキーと値を補完する

ステータス: 採択

## 文脈

LSP の補完は、`.gm` の原稿の中でだけ働く（[specifications.md](../specifications.md) の LSP の節）。
`style.toml` と `preflight.toml` を編集しているあいだは、キーも値も補えない。
キーの数は多く（`style.toml` の段落スタイルだけで 20 近い）、列挙の値（`line-breaks` の `join` と `keep`、`kerning` の四つの値、プリフライトの設定の `severity` など）や、同じファイルで定義した名前（スタイル、スウォッチ、書体の役割、アキ量のセット）を参照する値もある。
利用者は仕様書かマニュアルを横に開いて書くことになる。

### 今の実装

補完の入口は `Golem.Lsp.Features.completions` である（[Features.hs#L277-L333](https://github.com/tett23/golem/blob/0d390581fa868f6eff0feff41d41d0c0988697fd/modules/golem-lsp/src/Golem/Lsp/Features.hs#L277-L333)）。
`sourceOf` が `Nothing` を返すパス、つまり Golem の原稿として扱っていないファイルでは空のリストを返す。
その手前で、サーバーの要求の受け口 `atPosition` も、`sourceOf` のないパスでは結果を空にする（[Server.hs#L273-L283](https://github.com/tett23/golem/blob/0d390581fa868f6eff0feff41d41d0c0988697fd/modules/golem-lsp/src/Golem/Lsp/Server.hs#L273-L283)）。

`style.toml` のキーを補う仕組みは、原稿の `@style-def` の行にだけある（`styleDefCompletions`、[Features.hs#L354-L388](https://github.com/tett23/golem/blob/0d390581fa868f6eff0feff41d41d0c0988697fd/modules/golem-lsp/src/Golem/Lsp/Features.hs#L354-L388)、[docs/adr/0014](0014-in-file-settings.md)）。
キーの一覧 `charStyleKeys`、`paraStyleKeys`、`regexStyleKeys` は golem-project に手で書いたリストである（[Style.hs#L2233-L2237](https://github.com/tett23/golem/blob/0d390581fa868f6eff0feff41d41d0c0988697fd/modules/golem-project/src/Golem/Project/Style.hs#L2233-L2237)）。
`line-breaks` の値 `join` と `keep` は、golem-lsp の中にもう一度書いてある（[Features.hs#L386](https://github.com/tett23/golem/blob/0d390581fa868f6eff0feff41d41d0c0988697fd/modules/golem-lsp/src/Golem/Lsp/Features.hs#L386)）。
リストとデコーダーの食い違いは、golem-project のテスト「every key of charStyleKeys and paraStyleKeys is known」が片方向だけ確かめている（[test/Main.hs#L1678-L1698](https://github.com/tett23/golem/blob/0d390581fa868f6eff0feff41d41d0c0988697fd/modules/golem-project/test/Main.hs#L1678-L1698)）。
リストのキーをデコーダーが知っていることは確かめるが、デコーダーが読むキーがリストにあることは確かめない。
`@manifest` の補完も同じ形で、`[source]` のキーは golem-parser の `sourceKeys` から取り、`paragraph-separator` の値は golem-lsp に書いてある（[Features.hs#L338-L352](https://github.com/tett23/golem/blob/0d390581fa868f6eff0feff41d41d0c0988697fd/modules/golem-lsp/src/Golem/Lsp/Features.hs#L338-L352)）。

### デコーダーの形

`style.toml` のデコーダーは、toml-parser の `ParseTable` のモナドの中で `optKey`、`reqKey`、`enumKey` を順に呼ぶ形で書いてある（[Style.hs#L1472-L1496](https://github.com/tett23/golem/blob/0d390581fa868f6eff0feff41d41d0c0988697fd/modules/golem-project/src/Golem/Project/Style.hs#L1472-L1496)、[Style.hs#L1842-L1918](https://github.com/tett23/golem/blob/0d390581fa868f6eff0feff41d41d0c0988697fd/modules/golem-project/src/Golem/Project/Style.hs#L1842-L1920)）。
プリフライトの設定も同じ形である（[Rules.hs#L170-L233](https://github.com/tett23/golem/blob/0d390581fa868f6eff0feff41d41d0c0988697fd/modules/golem-preflight/src/Golem/Preflight/Rules.hs#L170-L233)）。
キーの一覧はどこにもデータとして置かれておらず、読むキーは値によって分かれることもあるので、デコーダーを走らせてキーの一覧を取り出すことはできない。
知らないキーは、toml-parser が表の読み終わりに残ったキーを `unexpected key` の警告にし、`decodeStrictBy` がそれを G03006 や G09001 のエラーにする（[Manifest.hs#L448-L455](https://github.com/tett23/golem/blob/0d390581fa868f6eff0feff41d41d0c0988697fd/modules/golem-project/src/Golem/Project/Manifest.hs#L448-L455)、文言は [golem-project ADR 0007](../golem-project/adr/0007-toml-messages-in-japanese.md)）。
toml-parser の `Matcher` は、値の誤りで失敗すると警告を捨てる（toml-parser 2.0.2.0 の `Toml.Schema.Matcher` の `Result`）。
そのため今は、値の誤りがあるファイルでは知らないキーが報告されない。
列挙の値の多くは `enumKey` の引数に書いたリストで（[Style.hs#L1381-L1386](https://github.com/tett23/golem/blob/0d390581fa868f6eff0feff41d41d0c0988697fd/modules/golem-project/src/Golem/Project/Style.hs#L1381-L1386)）、`kerning` やプリフライトの `severity` は `case` の分岐で書いてある。

### LSP が TOML のファイルをどう扱っているか

`style.toml` の読み込みは、LSP の編集中の内容ではなくディスクのファイルから行う（[Driver.hs#L210](https://github.com/tett23/golem/blob/0d390581fa868f6eff0feff41d41d0c0988697fd/modules/golem-driver/src/Golem/Driver.hs#L210)）。
LSP が `style.toml` を監視するのは、プラグインが文脈を求めたときだけである（[Driver.hs#L236](https://github.com/tett23/golem/blob/0d390581fa868f6eff0feff41d41d0c0988697fd/modules/golem-driver/src/Golem/Driver.hs#L236)、[docs/adr/0121](0121-host-context-in-plugin-requests.md)）。
`style.toml` の誤りは、プロジェクトを評価したときに `style.toml` の上に載る（[golem-project ADR 0006](../golem-project/adr/0006-project-diagnostic-codes.md)、golem-lsp のテスト「a style.toml error is reported on style.toml」）。
`preflight.toml` は LSP がまったく読まない。
仕様書は、LSP がプリフライトの検査をしないと定めている。

エディタの設定は、マニュアルの例では `.gm` のファイルにだけ LSP を付ける（`filetypes = { "golem" }`）。
TOML のファイルを補うには、エディタが `style.toml` を LSP に開いて送る必要がある。
ところが、今のサーバーは、開いたファイルの拡張子も `languageId` も見ない（[Server.hs#L168-L169](https://github.com/tett23/golem/blob/0d390581fa868f6eff0feff41d41d0c0988697fd/modules/golem-lsp/src/Golem/Lsp/Server.hs#L168-L169)）。
`updateFile` は、プロジェクトの原稿でも `@table` のファイルでもないファイルを `refreshLoose` に回し（[Workspace.hs#L229-L230](https://github.com/tett23/golem/blob/0d390581fa868f6eff0feff41d41d0c0988697fd/modules/golem-lsp/src/Golem/Lsp/Workspace.hs#L229-L230)）、`refreshLoose` は編集中のファイルをすべて Golem の原稿として構文解析して S0 で評価する（[Workspace.hs#L191-L194](https://github.com/tett23/golem/blob/0d390581fa868f6eff0feff41d41d0c0988697fd/modules/golem-lsp/src/Golem/Lsp/Workspace.hs#L191-L194)）。
コードを読むかぎり、エディタが `style.toml` を送ると、TOML の本文を Golem の原稿として解析した diagnostics が `style.toml` に載る。
この振る舞いは手もとで動かして確かめておらず、下のテスト設計で先に失敗させて確かめる。

## 実装すること

`tett23` に決めてもらう点を「決定」として番号を振る。
各決定に推奨と、採らなかった案を書く。

### 決定 1：対象のファイル

推奨：プロジェクトのルートの `style.toml` と `preflight.toml` の二つだけを対象にする。
パスはルートからの相対パスで、ちょうど `style.toml` と `preflight.toml` に一致するものとする。

- `manifest.toml` は対象にしない。依頼は `style.toml` と `preflight.toml` だけを名指ししており、`manifest.toml` はデコーダーが別（golem-project の `Manifest`）で、章の項目のように表、配列、文字列を取り混ぜる値を持つ。決定 4 のスキーマと決定 5 の読み取りは `manifest.toml` にもそのまま使えるので、必要になったら別の ADR で加える。
- 採らない案：ファイル名だけで判断し、ルートより下の `style.toml` も対象にする。Golem が読むのはルートの `style.toml` だけ（[Driver.hs#L210](https://github.com/tett23/golem/blob/0d390581fa868f6eff0feff41d41d0c0988697fd/modules/golem-driver/src/Golem/Driver.hs#L210)）なので、読まれないファイルで補完が働くと、そのファイルが組版に使われていると誤解させる。
- 採らない案：`golem preflight --rules` で指す別の名前の設定のファイルも対象にする。LSP はコマンドの引数を知らないので、どのファイルがプリフライトの設定かを決められない。

### 決定 2：ADR の置き場所

この ADR は `docs/adr/` に置く。
決定 4 で golem-project と golem-preflight のデコーダーを変え、決定 9 で golem-lsp の `build-depends` を変えるので、golem-lsp の一つのモジュールに収まらない。
原稿の中の `@style-def` の補完も、golem-project と golem-lsp にまたがる変更として [docs/adr/0014](0014-in-file-settings.md) に置いた。
決定 4 で採らない案（手で書いた一覧）を選ぶなら、変更の大半は golem-lsp に収まるが、一覧を置くのは golem-project と golem-preflight なので、置き場所は変えない。

### 決定 3：何を補うか

推奨：次の五つの位置で補う。

| 位置 | 例（`▮` がカーソル） | 候補 |
|---|---|---|
| 表の見出し | `[▮`、`[paragraph-styles.▮` | 次の段のキー。利用者が名前を決める段（`character-styles.<名前>` など）では、組み込みの名前と、同じファイルで定義した名前 |
| 表の中のキー | `[page]` の下の行頭、インラインテーブルの `{` か `,` の後 | その表のキーのうち、同じ表にまだ書いていないもの |
| 列挙の値 | `binding = ▮`、`severity = "▮` | 列挙の値 |
| 真偽の値 | `synthetic-bold = ▮` | `true`、`false` |
| 名前の参照 | `based-on = ▮`、`font = ▮`、`color = ▮`、`aki-set = ▮`、`regex-styles` の `style = ▮` | 参照する種類の名前（決定 6） |

- 同じ表にすでに書いたキーは候補に出さない。TOML はキーの重複をエラーにするので、出すと誤りを勧めることになる。
- 段落スタイルの `based-on` の候補から、`code` とそのスタイル自身を除く。どちらも G03013 になる（[golem-project ADR 0008](../golem-project/adr/0008-style-toml-value-positions.md) の表）。原稿の `@style-def` の補完も `code` を除いている（[Features.hs#L291-L292](https://github.com/tett23/golem/blob/0d390581fa868f6eff0feff41d41d0c0988697fd/modules/golem-lsp/src/Golem/Lsp/Features.hs#L291-L292)）。
- 文字列の値の候補は、カーソルが文字列の外にあれば引用符を付けたラベル（`"keep"`）、開いた引用符の中にあれば引用符のないラベル（`keep`）にする。真偽の値は引用符を付けない。
- キーの候補のラベルはキーの名前だけとし、`=` を付けない。`@manifest` の補完が `paragraph-separator=` を返すのは、原稿の記法に空白のない `key=value` の形があるためで、TOML では `key = value` と空白を入れるのがふつうだからである。
- 補わないもの：寸法（`13Q`、`1zw`）、数、自由な文字列（`name`、見出しの `number` の書式）、ファイルのパス（`[fonts.<役割>]` の `ja` と `latin`）。寸法と数は候補を列挙できず、パスの補完はファイルシステムを読む別の仕組みになる。
- 補完の項目の種類は、今の `CompletionKind` の `CkSettingKey`（キー）、`CkSettingValue`（列挙と真偽）、`CkSwatch`、`CkCharStyle`、`CkParaStyle` を使う。表の見出しの段のために `CkTable` を一つ加え、LSP の `CompletionItemKind_Module` に対応させる。

### 決定 4：キーと値の一覧をどこから取るか

推奨：キーと列挙の値をデータとして書いた**スキーマ**を、デコーダーと同じモジュールに置き、知らないキーの判定をスキーマで行う。
スキーマは、パーサーの受け付けるキーそのものになり、補完と食い違わない。

golem-project に `Golem.Project.TomlSchema` を加え、型と判定の関数を置く。

```haskell
-- | 一つの値の形
data Node
  = NTable [(Text, Node)]            -- キーの決まった表。並びはデコーダーの読む順
  | NNamed (Maybe Namespace) Node    -- 利用者が名前を決める表（[fonts]、[character-styles] など）。
                                     -- Namespace は、そのキーが定義する名前の種類
  | NArray Node                      -- 配列。要素の形
  | NEither [Node]                   -- いくつかの形のどれか（罫線の表か false など）
  | NValue Leaf

data Leaf
  = LString | LDimension | LInteger | LBoolean
  | LEnum [Text]                     -- 列挙の値
  | LRef Namespace                   -- ほかで定義した名前

data Namespace = FontRoles | Swatches | CharStyles | ParaStyles | AkiSets | Masters

-- | スキーマにないキーの誤り。文言、コード、位置は今の toml-parser の unexpected key と同じにする
unknownKeys :: Node -> Table' Position -> [MatchMessage Position]
```

- golem-project の `Golem.Project.Style` に `styleSchema :: Node` を、golem-preflight の `Golem.Preflight.Rules` に `rulesSchema :: Node` を置く。
- `decodeStrictBy` にスキーマを渡す形を加え、`parseStyle` と `parseRules` はそれを使う。TOML の木をスキーマでたどって知らないキーの誤りを作り、デコーダーの結果からは toml-parser の `unexpected key` の警告を取り除く。知らないキーを判定するのはスキーマだけになる。
- 知らないキーの誤りの文言、コード（`codeAt` による G03006、G03017 などの振り分けを含む）、位置は今と変えない。[golem-project ADR 0007](../golem-project/adr/0007-toml-messages-in-japanese.md) の `translateSchema` に、今と同じ `unexpected key: <キー>` の形と経路で渡す。
- 列挙の値は、値ごとに一度だけ定数として書き、デコーダーとスキーマの両方がその定数を使う。`enumKey "line-breaks" ["join", "keep"]` は `enumKey "line-breaks" lineBreaksValues` に、`kerning` の `case` は `kerningValues :: [(Text, Kerning)]` を引く形に、プリフライトの `levelOf` は `levelValues :: [(Text, Level)]` を引く形に、`based-on` は `builtinRules` の名前を引く形にする。誤りの文言は変えない。
- `charStyleKeys`、`paraStyleKeys`、`regexStyleKeys` は、`styleSchema` の `character-styles`、`paragraph-styles`、`regex-styles` の要素の表から、値が `NValue` のキーを並びのまま取り出して作る。今のリストと同じ値になる（`rule-before`、`rule-after`、`regex-styles` は `NValue` でないので除かれる）。`@style-def` の `line-breaks` の値も `lineBreaksValues` から取る。

これで、二つの向きの食い違いは次のように防ぐ。

- デコーダーが読むのにスキーマにないキー：利用者が書くと、スキーマが知らないキーにする。そのキーを読むデコーダーのテストが失敗する。
- スキーマにあるのにデコーダーが読まないキー：利用者が書くと黙って捨てられる。これは厳しさを緩めることになるので、テストで防ぐ（テスト設計の「スキーマの網羅」）。

振る舞いが一つ変わる。
今は値の誤りがあるファイルでは知らないキーが出ないが、この後は両方が出る。
報告が増えるだけで、どの誤りもコードと文言は今と同じであり、同じ入力に同じ diagnostics を返すことも変わらない。

採らない案：

- **手で書いた一覧と片方向のテスト**：今の `charStyleKeys` の形を `style.toml` の全体に広げる。変更は golem-lsp と一覧に閉じて小さい。しかし、デコーダーにキーを足して一覧に足し忘れても、どのテストも落ちない。補完から候補が黙って消えるだけなので、気付く機会がない。
- **キーを列挙型にする**：`data ParaKey = ParaBasedOn ▮ …` を `Bounded` と `Enum` にし、デコーダーは列挙型を通してしかキーを読めないようにする。食い違いはコンパイルで防げるが、2000 行を超える `Golem.Project.Style` のデコーダーをすべて書き換えることになり、表ごとに型が増える。
- **デコーダーからキーを取り出す**：`ParseTable` を記録する形で走らせてキーを集める。読むキーが値によって分かれる（`rule-before` の `false` と表、`[page]` の `size` の文字列と表）ので、すべてのキーを取り出せない。

### 決定 5：書きかけの TOML の読み方

推奨：カーソルより前のテキストを先頭から読む、小さな読み取りを golem-lsp に書く。
完全な構文解析はしない。

```haskell
-- Golem.Lsp.Toml
data Context
  = AtHeader [Text] Text              -- 見出しの中。確定した段と、書きかけの段
  | AtKey [Text] Text                 -- キーの位置。表の経路と、書きかけのキー
  | AtValue [Text] Quote Text         -- 値の位置。キーの経路、引用符の中か、書きかけの値
  | Nowhere                           -- コメント、複数行の文字列の中など

contextAt :: Text -> Int -> Context   -- テキストと UTF-8 のバイト位置

-- | ファイル全体で定義した表とキーの経路（重複の除外と、名前の参照に使う）
definedPaths :: Text -> [[Text]]
```

読み取りは次のものだけを追う。

- 行頭の `[` と `[[` で始まる見出し。見出しの経路は、引用符の付いたキー（`"a.b"`）を一つの段として読む。
- 基本の文字列（`"…"` と `\` のエスケープ）、リテラルの文字列（`'…'`）、複数行の文字列（`"""`、`'''`）、`#` から行末までのコメント。
- 値の中の `[` と `]`、`{` と `}` の入れ子と、インラインテーブルの中のキー。
- `=` の前のドットでつないだキー。

行をまたぐ配列は入れ子として追うので、仕様書の例にある複数行の `regex-styles = [ … ]` の中でも、`style = ` の後で文字スタイルの名前を補える。
読み取りはどの入力でも失敗せず、解釈できない位置は `Nowhere` にして候補を返さない。
カーソルより後ろのテキストは読まない。

採らない案：

- **toml-parser で全体を構文解析する**：書きかけの行（`font = ` で止まった行）は構文エラーになり、ファイル全体の木が得られない。
- **カーソルの位置に仮の値を入れてから構文解析する**：入れる値は位置ごとに違い（キー、値、配列の要素、閉じていない文字列）、ほかの行の書きかけの誤りでも全体が失敗する。
- **toml-parser の字句解析器（`Toml.Syntax.Lexer`）を使う**：公開されているが、キーと値の文脈の切り替えは toml-parser の構文解析器が行っており、それを golem-lsp の側でまねることになる。
- **今の行と直前の見出しだけを見る**：複数行の配列の中で、どのキーの値かがわからない。

### 決定 6：参照する名前をどこから取るか

推奨：編集中のファイルのテキストから `definedPaths` で集めた名前に、組み込みの名前を加える。
プロジェクトの評価の結果（`wsEvaluated` の `evStyle`）は使わない。

- `style.toml` の評価はディスクのファイルから読むので、編集中の名前を含まない。
- 書きかけの `style.toml` はたいてい読み込みに失敗し、そのあいだは評価の結果そのものがない。
- 名前の種類は、スキーマの `NNamed (Just ns)` の表のキーとする（`[fonts.<役割>]`、`[color.swatches.<名前>]`、`[character-styles.<名前>]`、`[paragraph-styles.<名前>]`、`[aki-sets.<名前>]`、`[masters.<名前>]`）。見出しで書いても、上の段の表の中のキーやインラインテーブルで書いても集める。
- 組み込みの名前は golem-project の `builtinCharStyles`、`builtinParaStyles`、`builtinAkiSetNames` のキーとする。
- 候補の並びは、組み込みの名前、ファイルに書いた順の名前の順とし、重複を除く。同じテキストからは同じ並びになる。

採らない案：評価の結果の名前を使う。
上の二つの理由で、編集中は古いか、ないことが多い。

### 決定 7：TOML のファイルを原稿として扱わない

推奨：拡張子が `.gm` でない編集中のファイルは、`refreshLoose` で原稿として解析しない。
編集中のテキスト（`wsOverlay`）と行の索引（`wsLines`）は今のとおり持つ。
補完と位置の変換に使うためである。

- `@table` のファイルは今もプロジェクトの評価が読んでおり（[golem-eval ADR 0004](../golem-eval/adr/0004-tsv-tables.md)）、この変更の影響を受けない。
- この規則は `manifest.toml` や `plugins.lock` を開いたときにも適用される。今そこに載りうる、原稿として解析した diagnostics も出なくなる。
- 採らない案：`style.toml` と `preflight.toml` の二つだけを除く。`manifest.toml` を開いたときに同じ問題が残り、除くファイルの一覧を別に保つことになる。

### 決定 8：位置の単位と要求の受け口

推奨：TOML のファイルの補完の要求も、`.gm` と同じく交渉した単位（[golem-lsp ADR 0002](../golem-lsp/adr/0002-utf8-position-encoding.md)）で受け、`F.fromLineCol` で UTF-8 のバイト位置に変える。
行の長さを超える列は行末に丸める（[golem-lsp ADR 0003](../golem-lsp/adr/0003-position-handling.md)）。

- `Golem.Lsp.Server` の補完の受け口で、パスが決定 1 の二つのどちらかであれば、`atPosition` のかわりに、`wsOverlay` のテキストと `lineIndexOf` の索引で位置を変える。編集中のテキストがなければ（エディタが開いていなければ）空の結果を返す。
- `Golem.Lsp.Features.completions` は、パスが決定 1 の二つのどちらかなら `tomlCompletions` に回す。`tomlCompletions :: Schema -> Text -> Int -> [Completion]` は、スキーマ、テキスト、バイト位置だけの純粋な関数とする。
- 補完を始める文字（`optCompletionTriggerCharacters`）は今の `[` と空白のままとする。`.` と `"` を加えると、`.gm` の原稿の中でも引用符を打つたびに要求が飛ぶ。見出しの段の補完は、エディタが識別子の文字を打つあいだに候補を絞り込む動きで足りる。

### 決定 9：パッケージの依存

推奨：golem-lsp の `build-depends` に golem-preflight を加える。
`rulesSchema` を読むためである。
ほかの golem-* の間の依存は変えない。

- golem-lsp はすでに golem-driver を通して golem-preflight に依存しており、ビルドするパッケージの集合は変わらない。golem-preflight は golem-lsp に依存しないので、循環はできない。
- golem-preflight はすでに golem-project に依存している（`decodeStrictBy` を使う）ので、`Golem.Project.TomlSchema` を使うための依存の追加は要らない。
- golem-lsp のテストスイートの依存も変えない。テストは期待する候補を文字列で書く。
- 採らない案：golem-driver から `rulesSchema` を再公開する。依存は隠れるが、golem-driver の公開する面に、golem-driver の使わない値が加わる。
- 採らない案：プリフライトの設定のスキーマを golem-project に置く。スキーマとデコーダーが別のパッケージに分かれ、決定 4 の同じ定数を共有する形がとれない。

### ドキュメント

- 仕様書の LSP の節の補完の項に、`style.toml` と `preflight.toml` のキーと値を加え、決定 1 の対象、決定 3 の位置、決定 6 の名前の出どころを書いてこの ADR へリンクする。拡張子が `.gm` でない編集中のファイルを原稿として解析しないことも書く。
- 仕様書の `style.toml` の節とプリフライトの設定の節に、知らないキーがスキーマで決まること、値の誤りと知らないキーが同じファイルにあれば両方を報告することを書く。
- マニュアルの「エディタと LSP」の章（`manual/chapters/09-editor.gm`）と開発者向けのマニュアル（`manual-dev/part1/04-lsp.gm`）の補完の項目とエディタの設定の例に、TOML のファイルも LSP に送る設定を加える。設定の例は、手で確かめた後に書く。

## 実装しないこと

- `manifest.toml` の補完（決定 1）。
- `style.toml` と `preflight.toml` の編集中の内容による diagnostics。`style.toml` の diagnostics は今のとおりディスクの内容による。編集中の内容でプロジェクトを評価し直すには、golem-driver が `style.toml` を `overlay` から読む変更が要り、評価の回数も増える。`preflight.toml` の G09001 は LSP に載せない（仕様書のとおり、LSP はプリフライトを扱わない）。
- ホバー（キーの説明の表示）と定義への移動（`based-on` から定義の表へ）。
- 補完の項目の `textEdit` とスニペット。今の `.gm` の補完と同じく、ラベルだけを返す。
- 寸法、数、自由な文字列、ファイルのパスの補完（決定 3）。
- `golem preflight --rules` で指す、ルートの `preflight.toml` 以外の設定のファイル（決定 1）。
- 補完を始める文字の追加（決定 8）。

## テスト設計

先に書いて、失敗することを確かめてから実装する。

### golem-project（`modules/golem-project/test/Main.hs`）

- スキーマの網羅：`styleSchema` のすべてのキーの経路について、そのキーだけを書いた `style.toml`（必須のキーは見本の値で補う）を toml-parser の `Matcher` で直接読み、`unexpected key` の警告が出ないこと。見本の値は値の種類（寸法は `"1zw"`、列挙はスキーマの最初の値など）で決め、それで読めないキーだけをテストの表で上書きする。デコーダーが読まないキーをスキーマに書くと、このテストが落ちる。
- 知らないキー：`[page]\nunknown = 1\n` の G03006 の文言と位置が、今と同じであること（今の出力をテストに書いておく）。`[paragraph-styles.body]\ncolour = "x"\n` と、`[page.size]` の下の知らないキー（G03017）も同じく確かめる。
- 値の誤りと知らないキー：`[page]\nbleed = "1zw"\nunknown = 1\n` で、塗り足しの誤りと知らないキーの二つが、位置の順に出ること。今は前者だけが出るので、このテストは先に落ちる。
- 列挙：スキーマの列挙の値のそれぞれを書いた `style.toml` が、そのキーで誤りを出さないこと。作った値（`line-breaks = "x"`）の誤りの文言が今と同じであること。
- `charStyleKeys`、`paraStyleKeys`、`regexStyleKeys` が、今のリストと同じ値（並びも含む）であること。
- 既存の「every key of charStyleKeys and paraStyleKeys is known」はそのまま通ること。

### golem-preflight（`modules/golem-preflight/test/Main.hs`）

- スキーマの網羅、知らないキー（廃止した `image-unplaceable` の G09001 を含む）、値の誤りと知らないキー、列挙（`severity`、`based-on`、`allowed`）について、golem-project と同じ形のテストを置く。

### golem-lsp（`modules/golem-lsp/test/Main.hs`）

`contextAt` と `tomlCompletions` を、テキストとカーソルの位置と期待の表で確かめる。
候補は文字列で書き、スキーマから組み立てない。
少なくとも次の行を置く。

| テキスト（`▮` がカーソル） | 期待 |
|---|---|
| `[▮`（空の `style.toml` の行頭） | `page`、`fonts`、`character-styles`、`paragraph-styles`、`color` を含む |
| `[paragraph-styles.quote]\n[paragraph-styles.▮` | 組み込みの段落スタイルの名前と `quote` |
| `[page]\nbinding = "right"\n▮` | `[page]` のキーを含み、`binding` を含まない |
| `[page]\nbinding = ▮` | `"right"`、`"left"` |
| `[page]\nbinding = "▮` | `right`、`left` |
| `[character-styles.em]\nsynthetic-bold = ▮` | `true`、`false` |
| `[paragraph-styles.quote]\nbased-on = ▮` | 組み込みの段落スタイルの名前のうち `code` を除いたもの。`quote` を含まない |
| `[fonts.heading]\nja = "a.otf"\n[character-styles.em]\nfont = ▮` | `"heading"` |
| `[color.swatches]\naccent = { cmyk = [0, 80, 100, 0] }\n[character-styles.em]\ncolor = ▮` | `"accent"` |
| `[paragraph-styles.body]\nregex-styles = [\n  { pattern = 'x', style = ▮` | 文字スタイルの名前 |
| `[page]\n# binding = ▮` | 候補なし |
| `[page]\nbinding = """\n▮` | 候補なし |
| `[page]\nsize = \n[page.grid]\n▮`（前の行が書きかけ） | `[page.grid]` のキー |
| 日本語のコメントを含む行の後での `binding = ▮` | `"right"`、`"left"`（バイト位置の計算） |

プリフライトの設定について、次の行を置く。

| テキスト | 期待 |
|---|---|
| `based-on = ▮` | `"basic"`、`"print"`、`"none"` |
| `[type-size]\nseverity = ▮` | `"error"`、`"warning"`、`"off"` |
| `[font-formats]\nallowed = [▮` | `"cff"`、`"cff2"`、`"truetype"` |
| `[▮` | 検査の名前の表（`glyph-missing` など）を含み、`image-unplaceable` を含まない |

ワークスペースについて、次を確かめる。

- `updateFile ws "style.toml" "[page]\nsize = \"B6\"\n"` の後で、`sourceOf ws "style.toml"` が `Nothing` であり、`diagnosticsFor ws` の `style.toml` に原稿の構文解析と評価のコード（G01xxx、G04xxx）がないこと。今の実装ではこのテストが落ちることを、実装の前に確かめる。
- `manifest.toml` を開いたときも同じであること。
- `completions` が、`sub/style.toml` と `manifest.toml` では空を返すこと。

プロトコルについて、`test/golden/protocol.txt` と `test/golden/protocol-utf8.txt` に、`style.toml` を開いて日本語のコメントの次の行で補完を求めるやりとりを加え、UTF-16 と UTF-8 のどちらでも同じ候補が返ることを固定する。

### 自動テストにしない確かめ方

実装の後に、Neovim の組み込みのクライアントで、`filetypes` に `toml` を加えた設定で `style.toml` と `preflight.toml` を開き、決定 3 の五つの位置で候補が出ることを確かめる。
あわせて、ルートの外の TOML のファイルと `manifest.toml` を開いたときに、diagnostics も候補も出ないことを確かめる。
確かめた設定を、マニュアルの設定の例に書く。

## トレードオフ

スキーマは、デコーダーとは別に書くデータである。
キーを足すときは、デコーダーとスキーマの二か所を変える。
二か所のどちらかを忘れれば、知らないキーの誤りかスキーマの網羅のテストで落ちるので、食い違ったまま出荷されることはない。
キーを列挙型にする案なら一か所で済むが、デコーダーの書き換えの量に見合わない。

知らないキーの判定をスキーマに移すので、toml-parser の残ったキーの検出を使わなくなる。
toml-parser の振る舞いに頼る点が一つ減る一方で、誤りの文言と位置を今と同じに保つ責任が Golem の側に移る。
テストで今の文言と位置を固定して受け止める。

読み取りを自前で書くので、TOML の文法の一部（文字列、コメント、入れ子）を golem-lsp がもう一度実装する。
読み取りは補完の文脈を決めるだけで、diagnostics を作らず値も解釈しないので、誤っても候補が出ないか、ずれた候補が出るだけである。
TOML の全体を tolerant に解析するパーサーを書くより小さい。

エディタの設定で TOML のファイルを LSP に送る必要があり、利用者の設定の手間が一つ増える。
サーバーの側から、エディタに送らせることはできない。

## 決めたことの記録

- **採択**：メンテナーが採択した（2026-11-05）。`style.toml` は分割する予定だが、今は今の形のまま扱う。細部よりも動くことを優先し、この ADR が決めてほしい点として挙げた項目は、どれも ADR の推奨のとおりとする。

## 参考文献

- toml-parser 2.0.2.0（Hackage）のソース：`Toml.Schema.ParseTable`（`parseTableFromValue` の残ったキーの警告）、`Toml.Schema.Matcher`（`Result` と、失敗のときに警告を捨てる振る舞い）、`Toml.Syntax.Lexer`
- TOML v1.0.0 の仕様：https://toml.io/en/v1.0.0
- LSP 3.17 の仕様（`textDocument/completion`、`CompletionItemKind`）：https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/
