# ADR 0170: Emet のエディタ対応と、.gm と .emet の構文の定義

ステータス: 採択

## 文脈

Golem の LSP は、`.gm` に対して diagnostics、定義への移動と参照の検索、ラベルの名前の変更、補完、ホバー、整形、見出しによるアウトライン、semantic tokens による色付けを持つ（[仕様書の「LSP」](../specifications.md#lsp)）。
`.gm` の lint と fmt は、`golem lint` と `golem fmt` が持つ。

関数を書く言語 Emet（`.emet`）は、[ADR 0162](0162-calling-emet-functions-from-gm.md) で LSP と lint と fmt を得た。
`.emet` の lint（E07100 から E07102）、`golem fmt`、LSP の diagnostics、補完、定義への移動、参照の検索、ホバー、整形がある（[PR #570](https://github.com/tett23/golem/pull/570)）。

`.gm` と比べると、`.emet` には次の四つがない。

- **色付け**：semantic tokens の要求に、`.gm` でないファイルは空の列を返す（[`Server.hs`](https://github.com/tett23/golem/blob/91c2e32c5c66af01286a5a24a55916930995b156/modules/golem-lsp/src/Golem/Lsp/Server.hs#L204)）。[ADR 0162](0162-calling-emet-functions-from-gm.md) は `.emet` の色付けを「実装しないこと」に挙げた。
- **アウトライン**：`textDocument/documentSymbol` は `.gm` の見出しだけを返し、`.emet` には空の列を返す（[`Server.hs`](https://github.com/tett23/golem/blob/91c2e32c5c66af01286a5a24a55916930995b156/modules/golem-lsp/src/Golem/Lsp/Server.hs#L264-L273)）。
- **名前の変更**：`textDocument/rename` は `.gm` のラベルだけを扱う（[`renameLabel`](https://github.com/tett23/golem/blob/91c2e32c5c66af01286a5a24a55916930995b156/modules/golem-lsp/src/Golem/Lsp/Features.hs#L336-L337)）。`.emet` の関数や変数の名前を変えるには、宣言と呼び出しを手で書き換える。
- **局所の名前の型**：`.emet` のホバーは、最上位の関数、取り込んだ関数、組み込みの関数のシグネチャだけを表示する（[`emetHover`](https://github.com/tett23/golem/blob/91c2e32c5c66af01286a5a24a55916930995b156/modules/golem-emet/src/Golem/Emet/Ide.hs#L175-L194)）。引数のパターンの変数と `where` の束縛の型は、型の検査が推論しているが、表示されない。

また、Golem はエディタ向けの構文の定義（TextMate の文法や tree-sitter の文法）を配っていない。
色付けは LSP の semantic tokens だけが行うので、LSP が動く前、LSP を使わないエディタ、semantic tokens に対応しないエディタでは、`.gm` も `.emet` も色の付かない文字列として表示される。

色付けは、[golem-lsp ADR 0006](../golem-lsp/adr/0006-semantic-tokens-highlighting.md) が `.gm` のために決めた形（構文木のトークンの種類と親のノードで型を決め、別のスレッドで返す）を、`.emet` に当てはめられる。
`.emet` の文法は、fmt のためにロスレスな構文木を持つ（[`Fmt.hs`](https://github.com/tett23/golem/blob/91c2e32c5c66af01286a5a24a55916930995b156/modules/golem-emet/src/Golem/Emet/Fmt.hs#L48-L52)）。
アウトラインと名前の変更は、`.emet` の LSP がすでに持つ、名前の出どころを引く仕組み（[`Ide.hs`](https://github.com/tett23/golem/blob/91c2e32c5c66af01286a5a24a55916930995b156/modules/golem-emet/src/Golem/Emet/Ide.hs#L199)）と、`.gm` からの参照の検索の上に作れる。

この ADR は、LSP（golem-lsp）、言語（golem-emet）、エディタ向けのファイル（`tools/`）にまたがるので、`docs/adr/` に置く。

## 実装すること

### 色付け

`.emet` にも `textDocument/semanticTokens/full` でトークンを返す。
凡例、`range` と `full/delta` を知らせないこと、別のスレッドで作ること、要求の時点のエディタの内容から作ること、改行をまたぐトークンを行ごとに分けることは、[golem-lsp ADR 0006](../golem-lsp/adr/0006-semantic-tokens-highlighting.md) と同じとする。

型は、ロスレスな構文木のトークンの種類と親のノードだけで決める（「メンテナーが決めること」の 1）。
型の検査の結果は使わない。
入力の途中で型の検査が通らない間も、色が変わらないようにするためである。

| `.emet` の要素 | 型 |
| --- | --- |
| コメント | `comment` |
| 予約語（`pub`、`inline`、`block`、`filter`、`fn`、`data`、`type`、`import`、`where`、`case`、`of`、`otherwise`） | `keyword` |
| シグネチャと等式の先頭の関数の名前、`where` の束縛の名前 | `function`（修飾子 `declaration`） |
| 関数の適用の先頭の名前（`f x` の `f`、`List.map xs` の `map`） | `function` |
| ほかの小文字の名前 | `variable` |
| 等式の引数のパターンの変数、キーワード引数の名前 | `parameter` |
| 型の名前（シグネチャ、`data`、`type` の中の大文字の名前） | `type` |
| 型の変数、要求の変数 | `typeParameter` |
| コンストラクタ（式とパターンの中の大文字の名前） | `enumMember` |
| 名前の前の組み込みのモジュールの名前（`List.`、`Inline.`） | `namespace` |
| 文字列、文字 | `string` |
| 数 | `number` |
| 演算子、`=`、`->`、`::`、ガードの `\|`、三項演算子の `?` と `:` | `operator` |
| 要求の列の `<`、`>`、`\|` と種類の `file` | `macro` |
| `import` のパス、`pub inline` などの文字列の名前、要求のパス | `string` |

- 括弧、角括弧、波括弧、カンマには、トークンを作らない。
- 構文の誤りの箇所には、トークンを作らない。誤りの前のトークンには型を付ける。
- `.gm` の [golem-lsp ADR 0006](../golem-lsp/adr/0006-semantic-tokens-highlighting.md) の表と同じ考え方で、名前の宣言を `declaration` の修飾子で区別する。

### アウトライン

`.emet` にも `textDocument/documentSymbol` で、ファイルの最上位の宣言の木を返す（「メンテナーが決めること」の 2）。

| 宣言 | 記号の種類 | 子 |
| --- | --- | --- |
| 関数（シグネチャと等式） | `Function` | `where` の束縛（関数は `Function`、値は `Variable`） |
| データ型 | `Enum`（コンストラクタが二つ以上）、`Struct`（レコード一つ） | コンストラクタ（`EnumMember`）、レコードの欄（`Field`） |
| 型の別名 | `TypeParameter` | なし |
| `import` | `Module` | なし |

- 記号の名前は宣言の名前、詳細（`detail`）はシグネチャの型の文字列とする。`pub inline` などは、詳細の前に種類の語と文字列の名前を付ける（`pub inline "tax-included" :: Nat -> Inlines`）。
- 範囲は、関数ならシグネチャから最後の等式と `where` の終わりまで、選択の範囲は名前とする。
- 構文の誤りのあるファイルでは、誤りの前までに読めた宣言を返す。

### 名前の変更

`.emet` の名前を `textDocument/rename` で変えられるようにする（「メンテナーが決めること」の 3）。

- **局所の名前**：引数のパターンの変数と `where` の束縛は、その関数の中の出現を書き換える。
- **最上位の名前**：関数、データ型、コンストラクタ、型の別名は、宣言したファイルの中の出現と、それを `import` するほかの `.emet` の出現を書き換える。
- **`.gm` の呼び出し**：`pub fn` の関数の名前は、それを `@import` する `.gm` の式文脈の呼び出し（`[= book.total(xs)]` の `total`）も書き換える。`pub inline`、`pub block`、`pub filter` の文字列の名前は `.gm` に出す名前なので、関数の名前を変えても変えない。文字列の名前を省いた関数は、関数の名前が `.gm` のコマンドの名前なので、`.gm` の呼び出しと `[[filters]]` の `filter` も書き換える。
- **新しい名前の検査**：新しい名前が `.emet` の識別子の規則に合わないか、予約語か、同じ有効範囲の名前と重なれば、書き換えずに誤りを返す。`.gm` のコマンドの名前にもなる関数では、`.gm` の名前の規則にも合わなければならない。重なりの判定は、[ADR 0160](0160-emet-function-language-core.md) の E02104 と E02108 の規則に従う。
- **組み込みの名前**：組み込みのモジュールの名前（`List.map` など）と組み込みの型は変えられず、誤りを返す。
- 書き換えは、`.gm` のラベルの名前の変更と同じく、一つの `WorkspaceEdit` で返す。型の検査が通っていないファイルでは、最後に型の検査が通った結果で出現を引く。

### ホバーで局所の名前の型を表示すること

`.emet` のホバーは、局所の名前の型も表示する（「決めたことの記録」）。

- 型の検査は、制約を解いた後、局所の名前の束縛の位置と出現の位置ごとに、その名前の型を残す。局所の名前は、等式と `case` の選択肢のパターンの変数、`where` の束縛、キーワード引数の名前（等式の引数の位置のもの）である。
- 型は、解いた結果の型に要求の列を含めて表示する（`words :: List String`、`lookup :: String -> <file "data/words.tsv"> Maybe String`）。`where` の関数のように一般化した型は、型の変数を `a`、`b` の順に名付けて表示する。最後まで決まらなかった型の変数も、同じ名付けで表示する。
- ホバーの位置の名前が局所の名前なら局所の型を、そうでなければ今のとおり最上位、取り込み、組み込みの関数のシグネチャを表示する。
- 型を表示するのは、エディタの今の内容が、最後に型の検査をした内容と同じときに限る（「メンテナーが決めること」の 7）。違えば局所の型を表示しない。編集の途中の内容では位置がずれ、別の名前の型を表示しうるからである。
- 型の検査が残す位置と型は、LSP のためだけに使い、diagnostics と出力には影響しない。`golem build` と `golem check` では残さない。

### エディタ向けの構文の定義

`.gm` と `.emet` の構文の定義を、二つの形式で用意する（「決めたことの記録」）。

- **TextMate の文法**：`tools/editors/textmate/golem.tmLanguage.json`（`.gm`、スコープ `source.golem`）と `tools/editors/textmate/emet.tmLanguage.json`（`.emet`、スコープ `source.emet`）。VS Code、Sublime Text、TextMate などが読む。
- **tree-sitter の文法**：`tools/editors/tree-sitter-golem/`（`.gm`）と `tools/editors/tree-sitter-emet/`（`.emet`）。それぞれ `grammar.js`、生成した `src/parser.c` と `src/grammar.json`、色付けの問い合わせ `queries/highlights.scm` を持つ。Neovim（nvim-treesitter）、Helix、Zed などが読む。

TextMate の文法は正規表現で書くので、LSP の semantic tokens より粗い。
tree-sitter の文法は構文木を作るので、TextMate の文法より正確だが、Golem の文法（peg-hs）とは別に書く文法であり、細部は Golem の構文解析と一致しない場合がある。
`.emet` の改行による区切りと、`.gm` の改行の様式のように、文脈で決まる区切りは、tree-sitter の外部のスキャナー（`src/scanner.c`）で扱う。

色の分類は、semantic tokens の表（`.gm` は [golem-lsp ADR 0006](../golem-lsp/adr/0006-semantic-tokens-highlighting.md)、`.emet` は上の表）と同じ分類にし、次の対応で書く。

| semantic tokens の型 | TextMate のスコープ | tree-sitter の捕捉の名前 |
| --- | --- | --- |
| `comment` | `comment.line` | `@comment` |
| `keyword` | `keyword.control` | `@keyword` |
| `function` | `entity.name.function` | `@function` |
| `decorator` | `entity.name.tag` | `@attribute` |
| `parameter` | `variable.parameter` | `@variable.parameter` |
| `variable` | `variable.other` | `@variable` |
| `type` | `entity.name.type` | `@type` |
| `typeParameter` | `entity.name.type` | `@type` |
| `enumMember` | `constant.other` | `@constructor` |
| `namespace` | `entity.name.namespace` | `@module` |
| `string` | `string.quoted` | `@string` |
| `number` | `constant.numeric` | `@number` |
| `operator` | `keyword.operator` | `@operator` |
| `macro` | `constant.character.escape`（`.gm` のエスケープ）、`storage.modifier`（`.emet` の要求の列） | `@string.escape`（`.gm`）、`@keyword.modifier`（`.emet`） |

- tree-sitter の捕捉の名前は、nvim-treesitter の標準の名前に揃える。Helix と Zed は、その多くを同じ名前で読む。
- TextMate の文法で区別できない分類は、近い分類にまとめる。`.emet` の関数の適用の先頭の名前と変数は、どちらも `variable` にし、宣言の名前だけを `function` にする。`.gm` の見出しの文字は、見出しの行の全体を `markup.heading` にする。tree-sitter の文法では、表のとおりに分ける。
- LSP の semantic tokens に対応するエディタでは、LSP の色が構文の定義の色より優先される。構文の定義は、LSP が動く前と、LSP を使わないエディタのためのものである。
- 構文の定義の使い方（各エディタでの読み込ませ方）を `tools/editors/README.md` に書く。
- 構文の定義を、`golem` のリリースのアーカイブに入れる（「決めたことの記録」）。アーカイブの中の `share/golem/editors/` に、TextMate の文法の二つのファイルと、tree-sitter の二つの文法のディレクトリ（`grammar.js`、`src/`、`queries/`）を置く。リリースの手順（[docs/adr/0004](0004-binary-distribution-and-release.md) の流れ）に、このディレクトリを写す手順を足す。アーカイブのほかの中身と、配布物の SHA-256 の扱いは変えない。
- 使い手のマニュアルのエディタの章と、開発者のマニュアルの LSP の章に、構文の定義の場所を書き足す。

## 実装しないこと

- `textDocument/semanticTokens/range` と `full/delta`（[golem-lsp ADR 0006](../golem-lsp/adr/0006-semantic-tokens-highlighting.md) と同じ）。
- 型の検査の結果による色付け（関数の値の変数を `function` にするなど）。
- `pub inline` などの文字列の名前の変更。`.gm` の原稿の呼び出しをすべて変えることになり、関数の名前の変更とは別の操作である。
- ホバーで式の部分の型を表示すること（`f x` の全体の型など）。名前の型だけを表示する。
- Vim の syntax（`syntax/*.vim`）。Neovim は tree-sitter の文法で色付けし、Vim は TextMate の文法も tree-sitter の文法も読まないので、Vim だけが LSP の前の色付けを持たない（「決めたことの記録」）。
- 構文の定義を、エディタの拡張機能やプラグインとして配布の場所（VS Code Marketplace、nvim-treesitter の文法の一覧など）に出すこと。
- GitHub の言語の判定（linguist）への登録。

## テスト設計

テストを先に書き、`.emet` の色付け、アウトライン、名前の変更、局所の型のホバー、構文の定義がないために失敗することを確かめてから実装する。

golem-emet か golem-lsp のテストでは、次のことを確かめる。

- **色付け**：上の表の要素を一つずつ含む `.emet` の断片について、トークンの位置、長さ、型、修飾子が表のとおりであること。UTF-8 と UTF-16 の列で数えた位置がどちらも正しいこと。コメントが行ごとに一つのトークンになること。構文の誤りのある断片で、誤りの前までのトークンが返ること。任意の `.emet` の原稿について、トークンが文書の順に並び、重ならず、既定の凡例で符号化できること（プロパティテスト）。
- **アウトライン**：関数、`where` の束縛、データ型とコンストラクタ、レコードの欄、型の別名、`import` が表の種類と親子で返ること。`pub inline "tax-included"` の詳細に種類の語と文字列の名前が出ること。構文の誤りの前の宣言が返ること。
- **名前の変更**：局所の変数、`where` の束縛、最上位の関数、コンストラクタ、型の名前の変更が、宣言とすべての出現を書き換えること。`import` するほかの `.emet` の出現も書き換えること。`pub fn` の名前の変更が `.gm` の式文脈の呼び出しを書き換えること。文字列の名前を持つ `pub inline` の名前の変更が `.gm` を書き換えず、文字列の名前を省いた `pub inline` の名前の変更が `.gm` の呼び出しを書き換えること。予約語、規則に合わない名前、重なる名前、組み込みの名前への変更が誤りになり、何も書き換えないこと。
- **局所の型**：引数のパターンの変数、`case` の選択肢の変数、`where` の値の束縛と関数の束縛、キーワード引数の名前の、束縛の位置と出現の位置のホバーが、それぞれの型を表示すること。一般化した `where` の関数が `a -> a` の形で表示されること。要求を持つ `where` の関数の型に要求の列が出ること。エディタの内容が型の検査をした内容と違えば、局所の型を表示しないこと。

golem-lsp の LSP のセッションのテストでは、`.emet` を開いて `semanticTokens/full`、`documentSymbol`、`rename`、`hover` の要求に答えることを確かめる。

構文の定義のテストは、次のとおりとする。

- **TextMate の文法**：`vscode-tmgrammar-test` の形式のテストのファイル（行の下にスコープを書いたもの）で、`.gm` と `.emet` の主な要素のスコープを確かめる。ツールは textlint と同じく `tools/editors/` の `package.json` で版を固定し、`package-lock.json` をコミットする（[docs/adr/0036](0036-textlint-for-documents.md) と同じ扱い）。
- **tree-sitter の文法**：`tree-sitter test` で、構文木のテスト（`test/corpus/`）と色付けのテスト（`test/highlight/`、行の下に捕捉の名前を書いたもの）を確かめる。tree-sitter の CLI も `tools/editors/` の `package.json` で版を固定する。生成した `src/parser.c` と `src/grammar.json` はコミットし、CI で生成し直して一致を検査する（Golem の文法の `Generated.hs` と同じ扱い）。
- **Golem の構文解析との突き合わせ**：tree-sitter の文法が、Golem の構文解析が受け付ける原稿を受け付けることを確かめる。`modules/golem-driver/test/fixtures/` と `manual/`、`manual-dev/` のすべての `.gm` と `.emet` を tree-sitter で読み、構文の誤り（`ERROR` のノード）がないことを CI で確かめる。
- **分類の一致**：二つの形式のテストは、同じテストの原稿（`tools/editors/test/sample.gm` と `sample.emet`）を使い、同じ要素が上の対応表の同じ分類になることを確かめる。
- **リリース**：リリースの手順の検査（[docs/adr/0004](0004-binary-distribution-and-release.md) の流れのテスト）で、アーカイブに `share/golem/editors/` の各ファイルが入ることを確かめる。
- CI に、二つの形式のテストを走らせる手順を足す。

## トレードオフ

色付けを構文木だけで決めるので、関数を値として持つ変数（引数に渡した関数など）は、適用の先頭にあれば `function`、それ以外では `variable` になる。
型の検査の結果を使えばより正確に分けられるが、入力の途中で型の検査が通らない間は色が決まらなくなる。

名前の変更が `.gm` の呼び出しまで書き換えるので、一回の名前の変更で多くのファイルが変わることがある。
`.gm` のラベルの名前の変更も章をまたいで書き換えており、同じ性質である。

文字列の名前を省いた関数の名前の変更は、`.gm` のコマンドの名前も変える。
関数の名前とコマンドの名前が同じ字面なので、片方だけを変えると呼び出しが壊れるからである。
`.gm` に出す名前を固定したいときは、文字列の名前を書けばよい。

局所の型を残すので、LSP の型の検査が使うメモリが、局所の名前の出現の数だけ増える。
`golem build` では残さないので、組版の時間とメモリには影響しない。

構文の定義を二つの形式で持つので、`.gm` と `.emet` の構文を変えるたびに、文法（peg-hs）、semantic tokens、TextMate の文法、tree-sitter の文法の四か所を変えることになる。
テストで同じ原稿の分類を比べ、tree-sitter で既存の原稿をすべて読むので、変え忘れは CI で見つかる。
特に tree-sitter の文法は、peg-hs の文法と同じ言語をもう一度書くもので、外部のスキャナーの C のコードも持つ。
保守の手間は大きいが、tree-sitter はこれから多くのエディタが使うと見込み、正確な色付けを LSP の前から得るために持つ。
TextMate の文法は正規表現で書くので、`.gm` の入れ子の括弧や、`.emet` の改行をまたぐ式のような、文脈で決まる要素は正確に色付けできない。

Vim の syntax を持たないので、Vim では LSP の semantic tokens に対応する設定をしない限り、色が付かない。

構文の定義をリリースのアーカイブに入れるので、アーカイブが少し大きくなり、リリースの手順に写す手順が一つ増える。

## 決めたことの記録

- **`.gm` と揃えること**（2026-11-06、メンテナー）：`.gm` の色付け、lint、fmt、LSP が `.emet` に揃っているかを尋ね、なければ ADR を作るよう求めた。`.emet` に足りない色付け、アウトライン、名前の変更を足す。
- **局所の型のホバーと構文の定義**（2026-11-06、メンテナー）：草稿が「実装しないこと」に挙げた、ホバーで局所の変数の型を表示することと、エディタ向けの構文の定義の配布を、やるよう求めた。
- **色付けの根拠、アウトライン、名前の変更、`.gm` の構文の定義、局所の型の条件**（2026-11-06、メンテナー）：「メンテナーが決めること」の 1、2、3、6、7 を推奨のとおりとした。
- **構文の定義の形式**（2026-11-06、メンテナー）：「tree-sitter が今後普及するはずなので」、TextMate の文法と tree-sitter の文法の二つとし、Vim の syntax は作らない。
- **リリースに含めること**（2026-11-06、メンテナー）：リリースに含めるとした。構文の定義を `golem` のリリースのアーカイブに入れる。

## メンテナーが決めること

すべて決めた（「決めたことの記録」）。

1. **色付けの根拠**：ロスレスな構文木だけで型を決める。
2. **アウトラインの中身**：最上位の宣言と `where` の束縛、コンストラクタ、レコードの欄を返す。
3. **名前の変更の範囲**：局所の名前、最上位の名前（`import` する `.emet` を含む）、`pub fn` と文字列の名前を省いたコマンドの `.gm` の呼び出しまでを書き換える。
4. **構文の定義の形式**：TextMate の文法と tree-sitter の文法の二つとし、Vim の syntax は作らない。
5. **構文の定義の置き場所**：リポジトリの `tools/editors/` に置き、`golem` のリリースのアーカイブの `share/golem/editors/` にも入れる。
6. **`.gm` も含めるか**：`.gm` と `.emet` の両方の構文の定義を作る。
7. **局所の型を表示する条件**：エディタの今の内容が、最後に型の検査をした内容と同じときだけ表示する。

## 参考文献

- Language Server Protocol Specification 3.17, "Semantic Tokens", "Document Symbols Request", "Rename Request", "Hover Request". https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/
- TextMate Manual, "Language Grammars". https://macromates.com/manual/en/language_grammars
- Tree-sitter, "Creating parsers", "Syntax Highlighting". https://tree-sitter.github.io/tree-sitter/
- nvim-treesitter, "Highlight captures". https://github.com/nvim-treesitter/nvim-treesitter/blob/main/CONTRIBUTING.md
- vscode-tmgrammar-test. https://github.com/PanAeon/vscode-tmgrammar-test
- [golem-lsp ADR 0006](../golem-lsp/adr/0006-semantic-tokens-highlighting.md)
- [ADR 0160](0160-emet-function-language-core.md)、[ADR 0162](0162-calling-emet-functions-from-gm.md)
