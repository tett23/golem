# golem-emet 仕様書

golem-emet は、関数を書く言語 Emet（拡張子 `.emet`）を読み、検査し、評価し、整形するパッケージである（[docs/adr/0160](../adr/0160-emet-function-language-core.md)）。
依存する golem のパッケージは golem-syntax（位置と diagnostic）、golem-eval（値と数の演算、`.gm` が使う関数の表の型）、golem-doc（意味論 IR）であり、ほかに peg-runtime を使う。
golem-eval の数の演算を使うので、`.emet` の数の規則は `.gm` の式文脈と同じになる。
golem-driver が golem-emet に依存し、関数の要求のハンドラを渡し、`.gm` が使う関数の表を作る（[docs/adr/0161](../adr/0161-emet-requirements-and-driver-handlers.md)、[ADR 0162](../adr/0162-calling-emet-functions-from-gm.md)）。
`golem fmt` と `golem lint` は golem-driver を通して `.emet` を扱い、golem-lsp は golem-emet に依存する。

## モジュール

- `Golem.Emet`：ファイルの一覧から、それらが `import` する `.emet` までを読み込んで検査する `loadProgram`、関数を要求のハンドラ（`Handlers`）とともに呼ぶ `callFunction`、ハンドラを作る `fileHandlers`、シグネチャに書いた要求とその位置を返す `programRequirements`。読むファイルは呼び出し側の関数で渡すので、このパッケージはファイルシステムに触れない。
- `Golem.Emet.Path`：`import` と要求 `file` のパスの字面の正規化。
- `Golem.Emet.Parse`：読み込みの段階（G01001 から G01003）と、文法による解析（E01100 から E01102）。構文の誤りのある文字列から、誤りの前の部分を読む `parsedPrefix`（下の「エディタ」）。
- `Golem.Emet.Generated`：`grammar/Emet.hpeg` から peg-hs が生成したパーサー。生成物はコミットし、CI で `scripts/gen-parser.sh` で生成し直して一致を検査する。AST を返す入口と、fmt のためのロスレスな構文木を返す入口を持つ。
- `Golem.Emet.Syntax`：AST。各ノードはファイルの中のバイトの範囲を持つが、範囲は等しさの比較に加わらない。データ型のコンストラクタは宣言の順に持つ。
- `Golem.Emet.Literal`：数、文字列、文字のリテラルの値。数は `.gm` の式の文脈と同じ規則で読み（[docs/adr/0101](../adr/0101-rational-numbers-in-expressions.md)）、文字列と文字はエスケープを解く。
- `Golem.Emet.Check`：`where` の位置（E01103）、名前（E0210x）、型、ガードの規則（E03102）、網羅性（E03100、E03101）の検査。検査を通ったモジュールを、名前を解決した中間の形（`Golem.Emet.Core`）にする。
- `Golem.Emet.Core`：検査を通ったプログラムの形。名前はすべて解決し、レコードは位置で持ち、`True` と `False` は式の文脈の値とする。評価器はこの形を走らせる。
- `Golem.Emet.Solve`：型の制約を解く。
- `Golem.Emet.Exhaust`：パターンの行列に対するベクトルの有用性による網羅性の検査（Maranget, 2007）。
- `Golem.Emet.Types`：型、要求の列、三つの述語、述語を満たす型の表。
- `Golem.Emet.Eval`：評価器。
- `Golem.Emet.Builtins`、`Golem.Emet.Prim`：組み込みのモジュールの `.emet` の原文と、Haskell で書いたプリミティブ。
- `Golem.Emet.Fmt`：整形。
- `Golem.Emet.IR`：意味論 IR と、組み込みのモジュール `Inline` と `Block` のデータ型の値のあいだの変換（[ADR 0162](../adr/0162-calling-emet-functions-from-gm.md)）。
- `Golem.Emet.Lint`：`.emet` の lint（E07100 から E07102）。
- `Golem.Emet.Ide`：LSP の補完、ホバー、宣言への移動、参照の検索のための、`.emet` の文字列とプログラムの上の純粋な関数。書きかけの文字列が解析できなければ、カーソルの行の残りを仮の値に替えた文字列、その行を除いた文字列を順に解析し、初めに解析できたものを使う。局所の名前の型のホバー（`emetLocalHover`）も持つ。
- `Golem.Emet.Highlight`、`Golem.Emet.Outline`、`Golem.Emet.Rename`：LSP の色付け、アウトライン、名前の変更（[docs/adr/0170](../adr/0170-emet-editor-support.md)、下の「エディタ」）。
- `Golem.Emet.Gm`：`.gm` が使う関数の表（golem-eval の `FunctionNamespace`）と、`.emet` のフィルタ。`.gm` の値と `.emet` の値の写し方と、出力の検査（E06104）を持つ。

## 文法と改行

文法は peg-hs の引数付き規則で書く。
式、パターン、型の規則は、括弧の中かどうかを表す引数 `nl` を取る。
字句の後ろの空白は、`nl` が真なら改行とコメントを含めて読み（`Sp(True)`）、偽なら空白とコメントだけを読む（`Sp(False)`）。
`nl` が偽の位置で読まれずに残った改行は、項目の区切り（`SepNl`）として読む。

- `(`、`[`、レコードの `{` の中の規則は `nl` を真にして呼ぶ。`case ... of { }` の中の選択肢は、括弧の中でも `nl` を偽に戻す。
- 二項演算子、`=`、`->`、`::`、`,`、`?`、`:` の字句は、後ろの改行をつねに読む。
- `|`、`-` を除く二項演算子、`?`、`:`、`where`、`->` の字句は、前の改行をつねに読む。前に改行を読んでから字句に一致しなければ、後戻りして、改行を区切りとして読み直す。
- 二項演算子の `-` は前の改行を読まない。行頭の `-` は新しい項目の始まりであり、選択肢の負の数のパターンとして読める。
- 三項演算子の真の枝は、`:` を読まない式の規則（`Or(nl, False)`）で読む。条件は `?` を含まない式（`Or(nl, True)`）、偽の枝は任意の式である。
- `;` は字句として持たないので、書けば E01100 になる。

ADR のテスト設計は、`c ? x : xs : ys` を E01100 とするが、この規則では偽の枝が `xs : ys` になり、`c ? x : (xs : ys)` と読む。
ADR の読み方の規則（偽の枝はどの式でもよい）に従った。
真の枝の最上位の `?`（`a ? b ? c : d : e`）は E01100 になる。

使えない予約語（E01102）は、文法の誤りの位置の語で判定する。
誤りの位置がその語の中か直後にあれば、E01100 ではなく E01102 とし、位置をその語にする。
`filter` は予約語なので、組み込みの関数の名前に使えない。
リストの要素を選ぶ関数は `List.select` とした。

実装で決めた細部を次に挙げる。

- `import` のパスは、プロジェクトのルートからの相対パスである。絶対パス、URL、ルートの外を指すパスは G03003、ないファイルは G03002 とする。
- 文字列と文字のリテラルの `\u{...}` の値が Unicode のスカラー値でなければ、E01100 とする。
- パターンには負の数のリテラル（`-1`）も書ける。
- レコードは、位置で作る（`Book "題" 2020`）ほか、欄の名前で作れる（`Book { title = "題", year = 2020 }`）。名前で作るときは、すべての欄を一度ずつ書く。欄はパターンで取り出す。
- 型の別名は `pub type` で公開できる。
- `where` の束縛と同じ名前のパターンの変数は、E02104 とする。どちらを指すかを読み手に推測させないためである。
- 組み込みの型（`Nat`、`String`、`Inlines`、`Blocks`、`Varargs` など）、組み込みのモジュール（`List`、`String`、`File`、`Inline`、`Block`）、組み込みのコンストラクタと同じ名前の型とコンストラクタ、組み込みの関数 `div` と同じ名前の関数は、E02104 とする。

## .gm から使う関数の宣言

`.gm` から使う関数（[ADR 0162](../adr/0162-calling-emet-functions-from-gm.md)）は、シグネチャの `pub` の後ろに種類の語（`inline`、`block`、`filter`、`fn`）を書き、その後ろに `.gm` に出す名前を文字列で書ける。

```haskell
pub inline "tax-included" taxIncluded :: Nat -> (tax :: Bool = True) -> Inlines
pub inline tags :: String -> Varargs String -> Inlines
pub block "word-table" wordTable :: String -> Blocks -> <file "data/words.tsv"> Blocks
pub filter "first-ruby" firstRuby :: Blocks -> Blocks
pub fn total :: List Nat -> Nat
```

- 種類の語は予約語なので、二つ書く（`pub inline fn f`）と E01100 になる。種類の語は `pub` の後ろにだけ書け、データ型と型の別名には書けない。
- キーワード引数は、型の位置に `(名前 :: 型 = 既定の値)` と書く。名前は識別子か文字列（`("font-size" :: Rat = 10)`）で、既定の値は式の文法で読んでから、リテラルかどうかを検査する（E06103）。型の検査では、括弧の中の型の引数と同じである。既定の値を省いた形（`(tax :: Bool)`）も文法としては読み、E06103 とする。
- `Varargs a`、`Inlines`、`Blocks` は型の別名で、それぞれ `List a`、`List Inline.Inline`、`List Block.Block` である。`.gm` から呼ぶ関数の引数の種類（位置引数、可変長引数、キーワード引数、散文スロット、本体）は、書いた型（`Varargs` とキーワード引数）と、別名を解いた型（`Inlines` と `Blocks`）から決める。型の別名で矢印を隠したシグネチャは、書いた型の引数がないものとして扱う。
- 宣言の誤り（E06100 から E06106）は、シグネチャごとに最初の一つだけを出す。誤りのない宣言は `Program` の `programExports` に、関数の名前、引数の種類、戻り値の型、シグネチャの原文とともに入る。
- 式文脈から呼べない関数（`pub fn` でない関数）は、その理由とともに `programOthers` に入る。golem-eval が G02002 のメッセージに使う。

## 型

最上位の関数の型はシグネチャで決まり、`where` の中の束縛と式の型は推論する。
型の検査は二段に分かれる。
構文をたどる段（`Golem.Emet.Check`）は制約を集めるだけで、単一化をしない。
解く段（`Golem.Emet.Solve`）が制約を解く。
制約は次の五つである。

- **等しさ**：二つの型が同じである。単一化で解く。
- **広がり**：一つめの型の値を、二つめの型を求める位置に渡せる。数どうしは順位で比べ、`List`、`Maybe`、組の中に及ぶ。ほかの型は単一化する。
- **述語**：型が「数」「比べられる型」「つなげる型」のどれかを満たす。満たす型は `Golem.Emet.Types` の `holds` の表で引く。
- **算術**：算術の演算子の左右の型と結果の型。左右が数に決まってから結果を決める。
- **符号の反転**：単項の `-` の型と結果の型。

解く段は、決められる制約を決められなくなるまで繰り返す。
`where` の束縛は一つの再帰の組として制約を集めて解き、残った制約に現れない型変数を汎化する。
関数の終わりには、型変数のまま残った制約を、次の既定で一つずつ、制約の順に決める。

1. 数が広がって入る型変数は、そのうちの最も広い数の型にする。
2. 数へ広がって入る型変数は、そのうちの最も狭い数の型にする。
3. 型変数から型変数への広がりは、二つを同じにする。
4. 算術の左右がどちらも型変数なら、どちらも `Rat` にする。片方だけなら、もう片方の型にする。
5. 数でなければならない型変数は `Rat` にする。

比べられる型とつなげる型の述語だけが残った型変数は、そのままにする。
評価器は値から型を引くので、残っても評価は変わらない。

演算子の結果の型は、式文脈の規則に合わせる。

| 演算子 | 結果の型 |
| --- | --- |
| `+`、`*` | 二つの広いほう |
| `-`（二項と単項） | `Int` 以上の広いほう |
| `/` | `Rat` |
| `%` | 右が `Nat` なら `Nat`、ほかは `Int`。左右とも `Nat` か `Int` に限る |
| `div a b` | 左右が `Nat` なら `Nat`、ほかは `Int`。左右とも `Nat` か `Int` に限る |
| `**` | 指数が `Nat` なら底の型、`Int` なら `Rat`。指数は `Nat` か `Int` に限る |
| `==`、`/=`、`<`、`<=`、`>`、`>=` | `Bool`。左右は、広げて同じになる数、`Bool`、`Char`、`String` に限る |
| `&&`、`\|\|` | `Bool` |
| `++` | `String` どうしか、`List` どうし |
| `:` | `List a`。左は `a`、右は `List a` |

`case` の選択肢、三項演算子の枝、リストの要素の型は、広げて同じになる最も狭い型にそろえる。
評価のあいだ、値は狭い型のまま渡ることがある（`Rat` の引数に `Nat` の値が渡る）が、演算の規則は値によらず同じ結果を返す。

## 組み込みのモジュール

組み込みのモジュール `List` と `String` は、`import` なしで `List.map` のように使う。
二つのモジュールは `.emet` で書いてあり、Haskell で書いたプリミティブの上に高階の関数を載せる。
高階の関数の再帰は末尾呼び出しで書いてあるので、長いリストでも E04101 にならない。
このほかに、モジュールの名前なしで使える関数 `div` と、コンストラクタ `True`、`False`、`Nothing`、`Just` がある。

| 関数 | 型 | 中身 |
| --- | --- | --- |
| `List.length` | `List a -> Nat` | 要素の数 |
| `List.reverse` | `List a -> List a` | 逆順 |
| `List.take`、`List.drop` | `Nat -> List a -> List a` | 先頭から n 個、n 個の後ろ |
| `List.range` | `Int -> Int -> List Int` | 両端を含む整数の列 |
| `List.concat` | `List (List a) -> List a` | 連結 |
| `List.at` | `Nat -> List a -> Maybe a` | 0 から数えた n 番目 |
| `List.isEmpty` | `List a -> Bool` | 空か |
| `List.map` | `(a -> e b) -> List a -> e (List b)` | 各要素に当てる |
| `List.select` | `(a -> e Bool) -> List a -> e (List a)` | 条件に合う要素 |
| `List.foldl` | `(b -> a -> e b) -> b -> List a -> e b` | 左からたたむ |
| `List.foldr` | `(a -> b -> e b) -> b -> List a -> e b` | 右からたたむ |
| `List.any`、`List.all` | `(a -> e Bool) -> List a -> e Bool` | どれかが、すべてが条件に合うか |
| `List.concatMap` | `(a -> e (List b)) -> List a -> e (List b)` | 当てて連結 |
| `List.zip` | `List a -> List b -> List (a, b)` | 二つの列の組の列。短いほうの長さ |
| `String.length` | `String -> Nat` | Unicode のスカラー値の数 |
| `String.chars` | `String -> List Char` | 字のリスト |
| `String.fromChars` | `List Char -> String` | `chars` の逆 |
| `String.fromChar` | `Char -> String` | 一字の文字列 |
| `String.join` | `String -> List String -> String` | 区切りを挟んでつなぐ |
| `String.split` | `String -> String -> List String` | 区切りで分ける。区切りが空なら一字ずつ |
| `String.lines` | `String -> List String` | 改行で分ける。最後の改行の後ろの空の行は含めない |
| `String.trim` | `String -> String` | 前後の空白を除く |
| `String.startsWith`、`String.endsWith`、`String.contains` | `String -> String -> Bool` | 一つめの文字列で始まるか、終わるか、含むか |
| `String.replace` | `String -> String -> String -> String` | 一つめを二つめに置き換える。一つめが空なら何もしない |
| `String.take`、`String.drop` | `Nat -> String -> String` | 先頭から n 字、n 字の後ろ |
| `String.fromNat`、`String.fromInt`、`String.fromRat` | 数 `-> String` | 本文に埋め込むときと同じ書き方の文字列。小数点以下が 1000 桁を超えれば G02102 |
| `String.toNat`、`String.toInt` | `String -> Maybe Nat`、`String -> Maybe Int` | ASCII の十進の数字（`toInt` は前の `-` も）だけからなれば、その数 |
| `String.all`、`String.any` | `(Char -> e Bool) -> String -> e Bool` | 各字について |
| `String.map` | `(Char -> e Char) -> String -> e String` | 各字に当てる |

型クラスを足せば多相になる関数（並べ替え、要素の有無）は、まだ持たない。

組み込みのモジュール `Inline` と `Block` は、意味論 IR のデータ型を持つ（[ADR 0162](../adr/0162-calling-emet-functions-from-gm.md)）。
コンストラクタは、プラグインとの ABI のシリアライズ形式と同じ範囲である。

| データ型 | コンストラクタ |
| --- | --- |
| `Inline.Inline` | `Text String`、`Ruby (List RubySegment)`、`Kenten (Maybe String) Inlines`、`Color String Inlines`、`CharStyle String Inlines`、`Tcy String`、`Number Int (Maybe NumberStyle)`、`Ref RefKind String`、`Deferred Deferred`、`Note Inlines`、`Sidenote Inlines`、`IndexMark (List String) (List String)`、`Cite String`、`ProofComment String`、`LineBreak`、`Aki AkiAmount`、`ChannelItem String (Maybe String) (Maybe String) Inlines`、`Link String Inlines`（[docs/adr/0182](../adr/0182-external-links.md)）、`Lang String Inlines`（[docs/adr/0187](../adr/0187-inline-language-switch.md)。組み込みの `plain` は中の文字を返す） |
| `Inline.RubySegment` | `RubySegment Inlines (Maybe String)`（親文字と読み） |
| `Inline.NumberStyle` | `Kanji`、`KanjiDigits`、`TateChuYoko` |
| `Inline.RefKind` | `RefNumber`、`RefTitle`、`RefPage` |
| `Inline.AkiAmount` | `Zw Rat`、`Sp Nat` |
| `Inline.Deferred` | なし（中身の読めない値） |
| `Block.Block` | `Paragraph (Maybe String) Inlines`、`Heading Nat HeadingAttrs Inlines`、`BulletList (List ListItem)`、`OrderedList (List ListItem)`、`DefList (List DefGroup)`、`Table (List Alignment) (List Inlines) (List (List Inlines))`、`CodeBlock Code`、`FigureBlock Figure`、`ChannelOutput Channel`、`ForcedBreak BreakKind`、`PageControl PageControl`、`BlankLines Nat` |
| `Block.HeadingAttrs` | `HeadingAttrs { tocTitle :: Maybe Inlines, number :: Maybe Nat, nonumber :: Bool, notoc :: Bool }` |
| `Block.ListItem` | `ListItem (Maybe Nat) (List Block)`（番号と中身） |
| `Block.DefGroup` | `DefGroup (List Inlines) (List Blocks)`（語と定義） |
| `Block.Alignment` | `AlignDefault`、`AlignLeft`、`AlignCenter`、`AlignRight` |
| `Block.Code` | `Code { lang :: Maybe String, numbers :: Maybe Bool, file :: Maybe String, caption :: Maybe Inlines, diff :: Bool, lines :: List CodeLine, nonumber :: Bool }` |
| `Block.CodeLine` | `CodeLine { text :: String, number :: Maybe Nat, mark :: Maybe DiffMark, highlight :: Bool, callouts :: List Nat }` |
| `Block.DiffMark` | `Added`、`Removed`、`Unchanged` |
| `Block.Figure` | `Figure { source :: String, web :: Maybe String, alt :: String, wrap :: Maybe Wrap, width :: Maybe String, caption :: Blocks, page :: Maybe Nat, rotate :: Bool, nonumber :: Bool }` |
| `Block.Wrap` | `WrapStart`、`WrapEnd` |
| `Block.Channel` | `TocOutput Nat`、`IndexOutput`、`BibliographyOutput`、`CustomOutput String (Maybe String)` |
| `Block.BreakKind` | `BreakPage`、`BreakRecto`、`BreakVerso`、`BreakColumn` |
| `Block.PageControl` | `NoBreak`、`NeedLines Nat`、`AdjustLines Int` |

ADR は注と傍注の本文を `Blocks` と書くが、ABI と意味論 IR の注の本文はインラインの列なので、`Inlines` にした。

よく使うノードを作る関数は次のとおりである。

| 関数 | 型 | 中身 |
| --- | --- | --- |
| `Inline.text` | `String -> Inlines` | テキスト |
| `Inline.ruby` | `String -> String -> Inlines` | 親文字と読みのルビ |
| `Inline.style` | `String -> Inlines -> Inlines` | 文字スタイル |
| `Inline.color` | `String -> Inlines -> Inlines` | 色 |
| `Inline.kenten` | `Inlines -> Inlines` | 既定の形の圏点 |
| `Inline.tcy` | `String -> Inlines` | 縦中横 |
| `Inline.note` | `Inlines -> Inlines` | 脚注 |
| `Inline.plain` | `Inlines -> String` | テキスト、ルビの親文字、圏点と色と文字スタイルの中身、縦中横、数をつないだ文字列 |
| `Block.paragraph` | `Inlines -> Blocks` | 段落 |
| `Block.styled` | `String -> Inlines -> Blocks` | 段落スタイルを付けた段落 |
| `Block.bullets`、`Block.numbered` | `List Blocks -> Blocks` | 箇条書き、番号付きリスト |
| `Block.table` | `List Inlines -> List (List Inlines) -> Blocks` | 見出しの行と本体の行の表 |
| `Block.definitions` | `List (Inlines, Blocks) -> Blocks` | 定義リスト |

値の中のソースの位置、ブロックのラベルと言語（[docs/adr/0187](../adr/0187-inline-language-switch.md)）、注の番号、遅延した式は、データ型の欄に出さない（`Golem.Emet.IR`）。
外から来たノードは、宣言の欄の後ろに、それらを引く添字を一つ多く持つ。
パターンは宣言の欄だけを照合するので、関数からは見えない。
関数が作ったノードは添字を持たず、呼び出しの位置（フィルタではファイルの先頭）を持つ。
関数が作ったブロックは言語を持たず、外のブロックの言語を受け継ぐ。
`Inline.Deferred` のコンストラクタ `Opaque` は利用者に見せず、値は遅延した式の添字である。

高階の関数は、渡された関数の要求をそのまま自分の要求にする型を持つ（[docs/adr/0161](../adr/0161-emet-requirements-and-driver-handlers.md)）。
組み込みのモジュール `File` は `File.read` だけを持つ。
`File.read` の型は引数の文字列のリテラルで決まるので、検査器が特別に扱う（「要求」の節）。
`File` は組み込みのモジュールの名前なので、利用者の型とコンストラクタの名前に使えない（E02104）。

## 要求

関数の要求（[docs/adr/0161](../adr/0161-emet-requirements-and-driver-handlers.md)）は、型 `TF` の矢印ごとの列（`Row`）として持つ。
列は要求の集合と、開いた列の変数からなる。
列の変数は型の変数と同じ番号の空間を使い、一つの番号は型か列のどちらか一方の変数である。
シグネチャで同じ名前を型の変数と列の変数の両方に使えば E02101 とする。
型の別名とデータ型の定義には、列の変数を書けない（E02101）。
型の別名とデータ型の引数は型であり、列を当てる手段がないためである。
`::` の直後の列は、スキームの「参照したときの列」として持つ。

要求の記法の誤りは、シグネチャごとにまとめて出す。

- 一覧にない種類（E05100）は、シグネチャの中のすべてを一つの diagnostic に並べる。位置は最初のものである。
- `file` にパスが一つでない（`<file>`、`<file "a" "b">`）ものは E02101 とする。ADR はこの場合のコードを決めていないので、型の構築子の引数の数の誤りと同じコードにした。
- パスは `Golem.Emet.Path` で字面のまま正規化し、絶対パス、URL、ルートの外は G03003 とする。シンボリックリンクの解決は、ファイルを読む golem-driver が行う。
- 一つの列の同じ要求は E05102、大文字と小文字だけが違う二つのパスは G03004 とする。

検査は次のとおりである。

- 本体の列（等式の引数の数を n として、n 個目の矢印の列。n が 0 なら `::` の直後の列）を、本体を検査するあいだの「囲む列」とする。
- 矢印を一つ適用するたびに、その矢印の列が囲む列に含まれるという制約（`KRow`）を出す。引数のない関数と、値の `where` の束縛を名前で参照したときは、その参照の列について同じ制約を出す。部分適用は、本体の矢印まで適用しないので、要求を持たない。
- `File.read` の引数が文字列のリテラルなら、そのパスの `file` を要求する呼び出しとし、型を `String` とする。リテラルでない引数と、`File.read` を値として使うことは E05107 とする。核の形では、パスを正規化した文字列にする。
- 関数を、関数の型を求める位置に渡すときは、渡す関数の列が求める型の列に含まれればよい（要求の少ない関数を渡せる）。含まれなければ E02101 とする。引数と結果の型は単一化する。
- 本体の前の矢印と、n が 1 以上のときの `::` の直後に書いた列は E05106 とする。型の別名から来た列も同じで、そのときの位置はシグネチャの型である。
- `where` の束縛は、シグネチャがあればその本体の列を囲む列とする。なければ新しい列の変数を囲む列とし、推論した列の変数は型の変数と同じく汎化する。

解く段は、列の単一化と包含を次のように扱う。

- 二つの列を等しくするときは、片方にない要求を、もう片方の変数に入れる。変数のない列とシグネチャの変数（固い変数）は、何も受け取らない。
- 包含の制約では、囲む列にない要求を、囲む列の変数に入れる。変数がなければ、呼び出しなら E05101、関数の型の比較なら E02101 とする。呼び出しの列の変数がまだ決まらなければ、制約を待たせる。
- ほかに決められる制約がなくなったら、待っている包含の制約の一つに既定を当てる。囲む列の変数は呼び出しの列の変数を受け取り、変数のない列に入る呼び出しの列の変数は空の列になる。この既定は `where` を汎化する前にも当てる。

E05108（情報）は、最上位の関数の本体の列が閉じているときに、等式の中のどの呼び出しの列にも現れない要求について出す。
位置は書いた要求で、別名から来た要求ならシグネチャである。
`where` の束縛のシグネチャには出さない。
束縛の制約は汎化の時点で解き終わっておらず、本体が使うかどうかを決められないためである。

`Program` は、すべての `.emet` の最上位と `where` のシグネチャに書いた `file` の要求を、書いた位置とともに持つ（`programRequirements`）。
golem-driver は、これを `manifest.toml` の `[functions.requires]` と突き合わせて E05104 を出す。

## 評価

評価器は、継続を明示したスタックを持つ抽象的な計算機である。
末尾の位置（等式の右辺、`case` の選択肢とガードの右辺、三項演算子の枝、`&&` と `||` の右辺）の呼び出しは、呼び出し元の枠を置き換えるので、深さを増やさない。
末尾でない呼び出しの枠の数が 10000 を超えると E04101 とする。

比較、算術、`++` の演算子は、左の値の型から実装の表（`instancesOf`）を引いて呼ぶ。
型クラスの辞書渡しと同じ形であり、型クラスを足すときは、利用者のデータ型の行を表に足す。
そのときは、コンストラクタの値に型を持たせる。

手数は、関数の呼び出し、プリミティブの呼び出し、コンストラクタの適用、演算子、等式と選択肢の選択、`where` の束縛の評価を一つずつ数える。
`++` と、文字列とリストを作るプリミティブは、作った値の長さも足す。
手数が上限の 100,000,000 を超えると E04100 とする。

上限は、[docs/adr/0160](../adr/0160-emet-function-language-core.md) の決め方に従い、正常に終わる仕事の手数を測って、その最大の約 3 倍とした。
測った仕事と手数は次のとおりである（golem-emet のテスト「the measured work is a third of the limit or less」）。

| 仕事 | 手数 |
| --- | --- |
| 見本のプラグイン `kansuji` と同じ仕事（19 桁の自然数を漢数字にする） | 408 |
| 見本のプラグイン `first-ruby` と同じ仕事を文字列で行うもの（1000 語の列の、50 語の初出に印を付ける） | 20,312 |
| ADR のテストの 1000 万回の末尾再帰 | 30,000,002 |

`where` の束縛は、関数が呼ばれるたびに作る。
値の束縛（引数のない束縛）は、最初に使ったときに一度だけ評価し、結果を残す。
局所の関数は、同じ `where` の束縛を見る閉包になる。
束縛を評価している途中で同じ束縛の値を求めたら、E04102 とする。
メッセージの束縛の並びは、評価を始めた順である。

`File.read` は、driver が渡したハンドラ（`Handlers`）の `handleFile` に正規化したパスを渡し、返った文字列を値とする。
ハンドラはプロジェクトを読み込んだ時点で読んだ文字列を返すので、評価はファイルシステムに触れず、同じパスは一回のビルドの中でいつも同じ値になる。
新しい文字列を作らないので、手数は 1 とする。
ハンドラがパスを持たなければ E05104 とし、位置は `.gm` の呼び出しである。

呼び出しの誤りの位置は次のとおりである。

- E04100、E04101、E04102 は、`callFunction` に渡した `.gm` の呼び出しの位置。
- 数の演算の誤り（G02003 など）は、その演算の `.emet` の中の位置。

## fmt

`formatEmet` は、ロスレスな構文木の字句の上で整形するので、コメントは元の位置に残る。
構文木は、区切りの改行（`SepNl`）と空白の改行（`Nl`）を別の種類の字句として持つ。
字下げは次の規則で決める。

- 区切りの改行の後ろの行は、項目の始まりであり、ブロックの段に置く。空白の改行の後ろの行は、続きの行であり、ブロックの段より一段下げる。
- `case` と `where` の `{` の後ろと `}` の前で改行する。`{` の中は `{` の行より一段下げ、`}` は `{` の行の段に置く。
- ガードの `|` の前で改行する。ガードは続きの行なので、一段下がる。
- 一段は空白二つである。

足す改行は、`{` の後ろ、`}` の前、`|` の前だけであり、文法はどれも足す前と同じに読む。
書き手の改行は残し、行の長さで折り返さない。
行の中の空白も書き手のまま残し、行末の空白だけを除く。
続く空行は一つにまとめ、ファイルの初めと終わりの空行は除く。
BOM を除き、CR を LF に直す。
レコードの `{ }` では改行しない。

要求の列の要求は、種類とパスの順に並べ替える（`<file "a.tsv", file "b.tsv"|e>`）。
並べ替えたときは、要求のあいだを `, ` にそろえる。
並びがすでに整っている列と、中にコメントか改行がある列は、書き手のまま残す。
コメントを動かさないためである。

## エディタ

LSP の色付け、アウトライン、名前の変更、局所の名前の型は、golem-emet の純粋な関数が作り、golem-lsp が LSP の形にする（[docs/adr/0170](../adr/0170-emet-editor-support.md)）。
LSP から見た振る舞いは、仕様書の「[評価の段階](../specifications.md#評価の段階)」に書く。

### 誤りの前の部分

文法は回復を持たないので、構文の誤りのある文字列は行の初めで切って読む（`parsedPrefix`）。
最初の桁が空白でも `}`、`)`、`]`、`|` でもない行は、宣言の初めとみなす。
文字列をそうした行の初めで区切り、初めから順に区切りごとに解析する。
一つの区切りが読めなければ、後ろの区切りを七つまで足して読み直す。
最初の桁で続く行を持つ宣言のためである。
それでも読めない区切りでは、その中の行の初めのうち最も後ろの、そこまでなら読める位置で切る（後ろから三十二行まで試す）。
読めた部分の全体をもう一度解析した結果を使う。
各区切りの解析は区切りの長さに比例するので、誤りが文字列の初めにあっても、全体の長さの二乗にはならない。

### 色付け

`emetHighlights` は、ロスレスな構文木のトークンを、トークンの種類と上のノードの種類で分類する。
構文木は名前を一字ずつの節に分けるので、名前の節（`VarTok`、`ConTok`、`QualVar`、`QualCon`）と数の節（`NumTok`）は、その範囲を一つのトークンにする。

- 小文字の名前は、名前を包む節（`VarNameLoc`、`VarName`）の上の最初のノードで決める。`Signature`、`LocalSignature`、`Equation` なら宣言の関数、`ArrowRow`、`RowTail`、`AType`、`Data`、`TypeAlias` なら型の変数、`Req` なら要求の種類、`ArgNameE` ならキーワード引数の名前、`APat` なら、上の `Equation` と `Alt` のうち近いほうが `Equation` のとき引数、そうでなければ変数、`Atom` なら、それが `App` の先頭（ラベル `f`）で引数（ラベル `as`）があるとき関数、なければ変数とする。ほか（レコードの欄の名前など）は変数とする。
- 大文字の名前は、`Data` と `TypeAlias` の名前なら宣言の型、`ConDecl` の名前なら宣言のコンストラクタ、`TyConLoc` の中なら型、ほかはコンストラクタとする。
- `List.map` のような名前は、モジュールの名前と `.` を `namespace` にし、残りを上の規則で分ける。
- ノード `Import`、`Data`、`PubOpt`、`TypeAlias`、`SigPub`、`KindWord`、`WhereS`、`Case`、`GuardCond` が直に持つ文字は予約語、`EqS`、`DColonS`、`ArrowS`、`ColonS`、`QuestionS`、`AddOp`、`MulOp`、`CmpOp`、`OrOpS`、`AndOpS`、`AppendOpS`、`PowOpS`、`MinusS`、`DataBarS` が直に持つ文字は演算子、`RowTail` の `|` は要求の列の印とする。

### アウトライン

`emetOutline` は、AST の最上位の宣言から記号の木を作る。
シグネチャのない等式も関数とする。
データ型と型の別名の名前の位置は AST にないので、宣言の範囲の中で名前に一致する最初の語とする。
レコードの欄の名前の位置は、前の欄の型の終わりから欄の型の初めまでで名前に一致する最後の語とする。

### 名前の変更

`emetRename` は、プログラムの各ファイルについて、最後に型の検査をしたモジュールと、エディタの今の文字列を受け取る。
名前を変えるファイルと、書き換えるファイルを今の文字列から解析し、名前ごとに何を指すかを解く。

- 最上位の名前は、ファイルの宣言、`import` した `.emet` の公開された名前の順に引く。どちらにもない名前と、モジュールの名前の付いた名前は、組み込みの名前とする。
- 局所の名前は、その束縛の位置のバイトの位置で区別する。等式の引数の変数の有効範囲はその等式、`case` の選択肢の変数はその選択肢、`where` の束縛はその関数のすべての等式である。`where` の束縛の本体は、等式の引数の変数を見ない（型の検査と同じ）。

重なりと捕まりの判定には、各出現の位置で見える局所の名前の集合を使う。

### 局所の名前の型

型の検査の文脈は、局所の名前の型を残すかどうかを持つ（`cxRecord`）。
残すときは、パターンの変数を検査するたびに求める型を、局所の名前を解くたびにその型を残す。
関数の制約を最後に解いた後、残した型の変数を解いた結果で置き換え、`where` の束縛の名前には、汎化した後の型（シグネチャがあればシグネチャの型）を当てる。
`checkModule` は残さず、`checkModuleLocals` だけが残す。
`Golem.Emet` の `localTypes` は、プログラムの一つのファイルを、プログラムの持つ取り込みのモジュールに対して `checkModuleLocals` で検査し直す。
