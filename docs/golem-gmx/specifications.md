# golem-gmx 仕様書

golem-gmx は、関数を書く言語 `.gmx` を読み、検査し、評価し、整形するパッケージである（[docs/adr/0148](../adr/0148-gmx-function-language-core.md)）。
依存する golem のパッケージは golem-syntax（位置と diagnostic）、golem-doc、golem-eval（値と数の演算）だけであり、ほかに peg-runtime を使う。
golem-eval の数の演算を使うので、`.gmx` の数の規則は `.gm` の式文脈と同じになる。

## モジュール

- `Golem.Gmx`：ファイルの一覧から、それらが `import` する `.gmx` までを読み込んで検査する `loadProgram` と、関数を呼ぶ `callFunction`。読むファイルは呼び出し側の関数で渡すので、このパッケージはファイルシステムに触れない。
- `Golem.Gmx.Parse`：読み込みの段階（G01001 から G01003）と、文法による解析（G10100 から G10102）。
- `Golem.Gmx.Generated`：`grammar/Gmx.hpeg` から peg-hs が生成したパーサー。生成物はコミットし、CI で `scripts/gen-parser.sh` で生成し直して一致を検査する。AST を返す入口と、fmt のためのロスレスな構文木を返す入口を持つ。
- `Golem.Gmx.Syntax`：AST。各ノードはファイルの中のバイトの範囲を持つが、範囲は等しさの比較に加わらない。
- `Golem.Gmx.Check`：`where` の位置（G10103）、名前（G102xx）、型、ガードの規則（G10302）、網羅性（G10300、G10301）の検査。検査を通ったモジュールを、名前を解決した中間の形（`Golem.Gmx.Core`）にする。
- `Golem.Gmx.Exhaust`：パターンの行列に対するベクトルの有用性による網羅性の検査（Maranget, 2007）。
- `Golem.Gmx.Types`：型と、数の型の広がり。
- `Golem.Gmx.Eval`：評価器。
- `Golem.Gmx.Builtins`、`Golem.Gmx.Prim`：組み込みのモジュールの `.gmx` の原文と、Haskell で書いたプリミティブ。
- `Golem.Gmx.Fmt`：整形。

## 字句と宣言

字句と宣言の規則は [docs/adr/0148](../adr/0148-gmx-function-language-core.md) のとおりである。
実装で決めた細部を次に挙げる。

- `import` のパスは、プロジェクトのルートからの相対パスである。絶対パス、URL、ルートの外を指すパスは G03003、ないファイルは G03002 とする（`.gm` の `@import` と同じ原因なので、同じコードにする）。
- 文字列の `\u{...}` の値が Unicode のスカラー値でなければ、G10100 とする。
- パターンには負の数のリテラル（`-1`）も書ける。
- レコードは、位置で作る（`Book "題" 2020`）ほか、欄の名前で作れる（`Book { title = "題", year = 2020 }`）。名前で作るときは、すべての欄を一度ずつ書く。欄を取り出す関数は作らず、欄はパターンで取り出す。
- `where` の中の束縛には、シグネチャ（`name :: 型;`）を書ける。
- 一つのファイルの文法の誤りは、最初の一つだけを報告する。文法に回復の規則がないためである。

## 型

最上位の関数の型はシグネチャで決まり、`where` の中の束縛と式の型は Hindley-Milner の型推論で決める。
`where` の束縛は一つの再帰の組として推論し、シグネチャのない束縛の型を汎化する。

数は、`Nat` から `Int` へ、`Int` から `Rat` へ暗に広がる。
広がりは、値を求める型の位置に渡すとき（関数の引数、等式の右辺など）に認め、`List` と `Maybe` の中にも及ぶ。
`case` の選択肢、三項演算子の枝、リストの要素の型は、広いほうにそろえる。
評価のあいだ、値は狭い型のまま渡ることがある（`Rat` の引数に `Nat` の値が渡る）が、演算の規則は値によらず同じ結果を返す。

演算子の結果の型は、式文脈の規則に合わせる。

| 演算子 | 結果の型 |
| --- | --- |
| `+`、`*` | 二つの広いほう |
| `-`（二項と単項） | `Int` 以上の広いほう |
| `/` | `Rat` |
| `%` | 右が `Nat` なら `Nat`、ほかは `Int`。左右とも `Nat` か `Int` に限る |
| `div a b` | 左右が `Nat` なら `Nat`、ほかは `Int`。左右とも `Nat` か `Int` に限る |
| `**` | 指数が `Nat` なら底の型、`Int` なら `Rat`。指数は `Nat` か `Int` に限る |
| `==`、`/=`、`<`、`<=`、`>`、`>=` | `Bool`。左右は数どうし、`Bool` どうし、`String` どうしに限る。`Bool` は `False < True` で比べる |
| `&&`、`||` | `Bool` |
| `++` | `String` どうしか、`List` どうし |

型クラスを持たないので、演算子の左右の型が型変数のままのときは、その型変数に「数」「比べられる型」「つなげる型」の制約を付ける。
制約の付いた型変数は汎化しない。
算術の演算子の左右がどちらも型変数なら、その型を `Rat` に決める。

## 組み込みのモジュール

組み込みのモジュール `List` と `String` は、`import` なしで `List.map` のように使う。
二つのモジュールは `.gmx` で書いてあり、Haskell で書いたプリミティブの上に高階の関数を載せる。
高階の関数の再帰は末尾呼び出しで書いてあるので、長いリストでも G10401 にならない。
このほかに、名前空間なしで使える関数 `div` と、コンストラクタ `True`、`False`、`Nothing`、`Just` がある。

| 関数 | 型 | 中身 |
| --- | --- | --- |
| `List.length` | `List a -> Nat` | 要素の数 |
| `List.reverse` | `List a -> List a` | 逆順 |
| `List.cons` | `a -> List a -> List a` | 先頭に足す |
| `List.uncons` | `List a -> Maybe (List.Cons a)` | 先頭と残り。空なら `Nothing` |
| `List.take`、`List.drop` | `Nat -> List a -> List a` | 先頭から n 個、n 個の後ろ |
| `List.range` | `Int -> Int -> List Int` | 両端を含む整数の列 |
| `List.concat` | `List (List a) -> List a` | 連結 |
| `List.at` | `Nat -> List a -> Maybe a` | 0 から数えた n 番目 |
| `List.isEmpty` | `List a -> Bool` | 空か |
| `List.map` | `(a -> b) -> List a -> List b` | 各要素に当てる |
| `List.filter` | `(a -> Bool) -> List a -> List a` | 条件に合う要素 |
| `List.foldl` | `(b -> a -> b) -> b -> List a -> b` | 左からたたむ |
| `List.foldr` | `(a -> b -> b) -> b -> List a -> b` | 右からたたむ |
| `List.any`、`List.all` | `(a -> Bool) -> List a -> Bool` | どれかが、すべてが条件に合うか |
| `List.concatMap` | `(a -> List b) -> List a -> List b` | 当てて連結 |
| `String.length` | `String -> Nat` | Unicode のスカラー値の数 |
| `String.chars` | `String -> List String` | 一字ずつの文字列 |
| `String.fromChars` | `List String -> String` | `chars` の逆 |
| `String.join` | `String -> List String -> String` | 区切りを挟んでつなぐ |
| `String.split` | `String -> String -> List String` | 区切りで分ける。区切りが空なら一字ずつ |
| `String.lines` | `String -> List String` | 改行で分ける。最後の改行の後ろの空の行は含めない |
| `String.trim` | `String -> String` | 前後の空白を除く |
| `String.startsWith`、`String.endsWith`、`String.contains` | `String -> String -> Bool` | 一つめの文字列で始まるか、終わるか、含むか |
| `String.replace` | `String -> String -> String -> String` | 一つめを二つめに置き換える。一つめが空なら何もしない |
| `String.take`、`String.drop` | `Nat -> String -> String` | 先頭から n 字、n 字の後ろ |
| `String.fromNat`、`String.fromInt`、`String.fromRat` | 数 `-> String` | 本文に埋め込むときと同じ書き方の文字列。小数点以下が 1000 桁を超えれば G02102 |
| `String.toNat`、`String.toInt` | `String -> Maybe Nat`、`String -> Maybe Int` | ASCII の十進の数字（`toInt` は前の `-` も）だけからなれば、その数 |
| `String.all`、`String.any` | `(String -> Bool) -> String -> Bool` | 各字（一字の文字列）について |
| `String.map` | `(String -> String) -> String -> String` | 各字に当てる |

`List.uncons` の値の型 `List.Cons a` は、先頭と残りを持つ組み込みのデータ型（`Cons a (List a)`）である。
`.gmx` は組の型を持たず、Haskell の `:` は三項演算子と重なるので、先頭と残りはこの型のパターンで取り出す（`Just (List.Cons x rest)`）。

## 関数のコマンド

`pub inline` と `pub block` は `pub` の後ろに一つだけ書く（`pub inline block f` は G10100）（[docs/adr/0150](../adr/0150-calling-gmx-functions-from-gm.md)）。
`Golem.Gmx.Check` の `commandDiags` が名前（G10600）、戻り値（G10601）、引数（G10602）を検査し、`programCommands` が `loadProgram` に渡したファイルの関数をコマンドの一覧にする。
`callCommand` は、位置引数の値と、散文スロットの `Inlines` か本体の `Blocks` を渡して関数を呼ぶ。
`pub block` の関数の最後の引数が `Blocks` でなければ、本体は渡さない。
golem-driver が一覧から golem-eval の `FunctionCommand` と `FunctionBlockCommand` を作る。

組み込みのモジュール `Inline` と `Block` は次の関数を持つ。
作るノードの位置は、すべて `.gm` の呼び出しの位置である。

| 関数 | 型 | 作るもの |
| --- | --- | --- |
| `Inline.text` | `String -> Inlines` | 文字 |
| `Inline.ruby` | `String -> String -> Inlines` | 親文字と読みのルビ。親文字が文字列なので、ルビの中にルビは作れない |
| `Inline.kenten` | `Inlines -> Inlines` | 圏点（形は `style.toml` の既定） |
| `Inline.charStyle` | `String -> Inlines -> Inlines` | 文字スタイル |
| `Inline.color` | `String -> Inlines -> Inlines` | 色（スウォッチの名前） |
| `Inline.tcy` | `String -> Inlines` | 縦中横 |
| `Inline.number` | `Int -> Inlines` | 数（`[number-text ...]` と同じく書字方向で表記が決まる） |
| `Inline.concat` | `List Inlines -> Inlines` | 連結 |
| `Block.paragraph` | `Inlines -> Blocks` | 段落（`body`） |
| `Block.styledParagraph` | `String -> Inlines -> Blocks` | 段落スタイルを付けた段落 |
| `Block.bulletList`、`Block.orderedList` | `List Blocks -> Blocks` | 項目ごとのブロックの箇条書き |
| `Block.defList` | `List Block.Def -> Blocks` | 定義の並び。`Block.Def` は用語の `Inlines` と定義の `Blocks` を持つ |
| `Block.table` | `List Inlines -> List (List Inlines) -> Blocks` | 見出しの行と本体の行の表 |
| `Block.code` | `String -> Blocks` | コードのブロック（行ごと） |
| `Block.concat` | `List Blocks -> Blocks` | 連結 |

`++` は `Inlines` どうしと `Blocks` どうしもつなぐ。

## 要求

関数のシグネチャは、型の後ろの `=>` に要求を並べる（[docs/adr/0149](../adr/0149-gmx-requirements-and-driver-handlers.md)）。
要求の一覧は `file` だけで、操作は組み込みのモジュール `File` の `File.read :: String -> String => file` である。
要求の集合は、関数の型（`Golem.Gmx.Types` の `Scheme`）の項として持つ。
要求の変数と利用者のハンドラは持たない。

- 要求を持つ関数を呼ぶ関数は、シグネチャにその要求を持たなければならない（G10501）。引数の数が足りた呼び出しと、引数のない関数の参照を、呼び出しとして扱う。
- `where` の中の局所の関数は、外の関数の要求を受け継ぐ。局所の関数が要求を使うかは、その本体で決まる。
- 要求を持つ関数（要求を使う局所の関数を含む）を値として使えば G10501 とする。
- 一覧にない名前は G10500（一つのシグネチャで一つ）、同じ名前の二度めは G10502 とする。
- fmt は要求の名前を名前の順に並べ替える。

評価器は、`File.read` に出会うと、呼び出し側から渡されたハンドラ（`Handlers`）を呼ぶ。
ハンドラを渡さない呼び出しでは、どの名前も G10503 になる。
`fileHandler` は、名前からファイルのバイト列への表からハンドラを作る。

## 評価

評価器は、継続を明示したスタックを持つ抽象的な計算機である。
末尾の位置の呼び出しは、呼び出し元の枠を置き換えるので、深さを増やさない。
末尾でない呼び出しの枠の数が 10000 を超えると G10401 とする。

手数は、関数の呼び出し、プリミティブの呼び出し、コンストラクタの適用、演算子、等式と選択肢の選択、`lazy` の束縛の評価を一つずつ数える。
`++` と、文字列とリストを作るプリミティブは、作った値の長さも足す。
手数が上限の 100,000,000 を超えると G10400 とする。

上限は、[docs/adr/0148](../adr/0148-gmx-function-language-core.md) の決め方に従い、正常に終わる仕事の手数を測って、その最大の数倍とした。
測った仕事と手数は次のとおりである（golem-gmx のテスト「the measured work is a third of the limit or less」）。

| 仕事 | 手数 |
| --- | --- |
| 見本のプラグイン `kansuji` と同じ仕事（19 桁の自然数を漢数字にする） | 423 |
| 見本のプラグイン `first-ruby` と同じ仕事を文字列で行うもの（1000 語の列の、50 語の初出に印を付ける） | 30,290 |
| ADR のテストの 1000 万回の末尾再帰 | 30,000,002 |

ADR のテストは 1000 万回の末尾再帰が終わることを求めるので、これも正常に終わる仕事に数え、その約 3 倍を上限とした。

`where` の束縛は、関数が呼ばれるたびに作る。
`lazy` のない値の束縛は、等式を選ぶ前に上から順に評価する。
評価の途中で束縛が自分自身の値を求めたときは、決して終わらないので、そこで G10400 とする。

## fmt

`formatGmx` は、ロスレスな構文木の字句の上で整形するので、コメントは元の位置に残る。
字下げは次の規則で決める。

- ブロックの項目（最上位の宣言、`case` の選択肢、`where` の束縛）の最初の行は、ブロックの段に置く。項目の二行目からは一段下げる。
- `case` と `where` の `{` の後ろと `}` の前で改行する。`{` の中は `{` の行より一段下げ、`}` は `{` の行の段に置く。
- ガードの `|` の前で改行する。ガードは項目の二行目からなので、一段下がる。
- 一段は空白二つである。

書き手の改行は残し、行の長さで折り返さない。
行の中の空白も書き手のまま残し、行末の空白だけを除く。
続く空行は一つにまとめ、ファイルの初めと終わりの空行は除く。
BOM を除き、CR を LF に直す。
レコードの `{ }` では改行しない。
