# Emet の文法

この文書は、関数を書く言語 Emet（拡張子 `.emet`）の文法の参照である。
正本は peg-hs の文法 [modules/golem-emet/grammar/Emet.hpeg](../../modules/golem-emet/grammar/Emet.hpeg) であり、この文書はその規則を一つずつ、意味の動作（AST を作る Haskell の式）を除いた形で写し、読み方を説明する。
言語の設計の理由は [docs/adr/0160](../adr/0160-emet-function-language-core.md)、要求の列は [docs/adr/0161](../adr/0161-emet-requirements-and-driver-handlers.md)、`.gm` から使う関数の宣言は [ADR 0162](../adr/0162-calling-emet-functions-from-gm.md) が決めている。
型の規則、評価、組み込みの関数は、golem-emet の仕様書（[specifications.md](specifications.md)）にある。
使い手から見た書き方は、使い手のマニュアルの付録 J「関数を書く言語 Emet」にある。

CI の `changes` ジョブは、`scripts/ci/emet-grammar-doc.sh` で、この文書が `Emet.hpeg` のすべての規則を定義し、`Emet.hpeg` にない規則を定義していないことを確かめる。
規則を足すか、名前を変えるか、除いたときは、この文書の同じ規則も直す。
規則の中身の一致は検査しないので、規則の中身を変えたときも、この文書の写しを直す。

## 記法

文法は PEG（解析表現文法）で書いてある。
PEG の選択は順序付きであり、前の選択肢から試して、最初に一致したものを採る。
選択肢の一つが一致すると選択はそこで決まり、後ろの並びが失敗しても、同じ選択の残りの選択肢は試さない。
そのときは並びの全体が失敗し、それを囲む選択が次の選択肢を試す。
この文書では、PEG の規則を次の記法で書く。

| 記法 | 意味 |
| --- | --- |
| `A ::= e` | 規則 `A` の定義 |
| `e1 / e2` | 順序付きの選択 |
| `e1 e2` | 並び |
| `e*`、`e+`、`e?` | 0 回以上、1 回以上、0 回か 1 回の繰り返し。どれも読めるだけ読み、後戻りしない |
| `&e`、`!e` | 先読み。`e` が一致する（しない）ときに成功し、字を読まない |
| `"..."` | 字の列 |
| `[...]` | 字の集合 |
| `.` | 任意の一字（Unicode のスカラー値一つ） |
| `ε` | 空の列。つねに成功する |
| `A(nl)`、`A(nl, cons)` | 真偽値の引数を取る規則。呼ぶ側は `True` か `False` か、自分の引数を渡す |
| `A<p>` | 規則を引数に取る規則 |
| `&{nl}` | 引数 `nl` が真のときだけ成功する |
| `^label` | 直前の式が失敗したら、後戻りせずに解析を止め、`label` の誤り（E01101）にする |

`Emet.hpeg` の `$( )` は一致した字の列を値にする印で、読む字を変えないので、この文書では省く。
規則の写しの中で、引用符の外の `--` から行末は、この文書の説明のための注である（`Emet.hpeg` の規則にはない）。

## ファイル

一つの `.emet` が一つのモジュールである。
`module` の宣言は書かない。
文字コードは UTF-8 で、BOM と CR の扱いは `.gm` と同じである（BOM は G01002、正しくない UTF-8 は G01001、CR は G01003）。
読み込みの検査を通った文字列を、次の規則 `Module` で読む。

```text
Module ::= SpH Items<Decl> !.
```

ファイルの初めの空白とコメントを読み、宣言の並びを読み、ファイルの終わりで終わる。
`Emet.hpeg` の誤りからの回復はないので、一つのファイルの構文の誤り（E01100）は最初の一つだけである。

## 字句

### 空白、改行、コメント

```text
Ws ::= [ \t]+
Nl ::= "\n"
Comment ::= "--" (!"\n" .)*
SpH ::= (Ws / Comment)*
SpN ::= (Ws / Nl / Comment)*
Sp(nl) ::= &{nl} SpN
         / SpH
```

空白は空白とタブである。
コメントは `--` から行末までで、`{- -}` の形はない。
`--` は空白を置かずに字句の直後に書いてもコメントを始めるので、`1--x` は `1` とコメントである。
`SpH` は改行を読まない空白、`SpN` は改行を含めた空白である。
`Sp(nl)` は、引数 `nl` が真なら改行を空白として読み、偽なら読まない。
`nl` の働きは「改行と区切り」の節で説明する。

### 名前

```text
IdChar ::= [A-Za-z0-9_]
VarTok ::= [a-z_] IdChar*                    -- ただし "_" と予約語を除く
ConTok ::= [A-Z] IdChar* !"."
QualVar ::= [A-Z] IdChar* "." [a-z_] IdChar*   -- 後ろの名前は "_" と予約語を除く
QualCon ::= [A-Z] IdChar* "." [A-Z] IdChar*
VarNameLoc(nl) ::= VarTok Sp(nl)
VarName(nl) ::= VarNameLoc(nl)
ConNameLoc(nl) ::= ConTok Sp(nl)
ConRefLoc(nl) ::= QualCon Sp(nl)
                / ConNameLoc(nl)
QualVarLoc(nl) ::= QualVar Sp(nl)
```

名前は ASCII の英字、数字、`_` からなる。
値と関数と型の変数の名前（`VarTok`）は英小文字か `_` で始まり、型とコンストラクタの名前（`ConTok`）は英大文字で始まる。
`_` 一字は名前ではなく、パターンのワイルドカードである（`WildS`）。
`_x` のように `_` で始まる名前は、普通の名前である。
名前に `-` は使えない。
`.gm` に `-` を含む名前で出すときは、宣言に名前を文字列で書く（「シグネチャ」の節）。

`List.map`、`Inline.Text` のように、組み込みのモジュールの名前と `.` を前に付けた名前（`QualVar`、`QualCon`）を書ける。
`.` の前後に空白は置けず、モジュールの名前は一つだけである（`A.B.c` は E01100）。
`ConTok` の後ろの `!"."` は、`Inline.` のような名前を一つの名前として読まないためである。

次の語は名前に使えない。

| 語 | 扱い |
| --- | --- |
| `pub`、`inline`、`block`、`filter`、`fn`、`data`、`type`、`import`、`where`、`case`、`of`、`otherwise` | 文法の語 |
| `as` | 予約した語。使えば E01100 |
| `if`、`then`、`else`、`for`、`while`、`let`、`in`、`lazy`、`class`、`instance`、`deriving`、`default` | 使えない予約語。使えば E01102 |

E01102 は、文法の誤りの位置がその語の中か直後にあるときに出す（[specifications.md](specifications.md) の「文法と改行」）。
`as` は `Parse.hs` の E01102 の語の一覧にないので、E01100 になる。
`True` と `False` は予約語ではなく、組み込みのコンストラクタである。
`otherwise` はガードの条件にだけ書ける語で、`Bool` の値ではない。

### 数のリテラル

```text
NumTok ::= [0-9]+ ("." [0-9]+)? ("e" [+-]? [0-9]+)? !IdChar
NumLitLoc(nl) ::= NumTok Sp(nl)
```

数のリテラルは、`.gm` の式文脈と同じ規則で値にする（[docs/adr/0101](../adr/0101-rational-numbers-in-expressions.md)）。
数字だけなら `Nat`、小数点か指数があれば正確な `Rat` である（`1.5e-3` は 3/2000）。
指数の印は小文字の `e` だけで、`1E3` は E01100 である。
`1.` と `.5` は書けない。
数の直後に英字、数字、`_` を続けることはできない。
負の数のリテラルはなく、式では単項の `-`、パターンでは `-` と数の並び（`APat`）で書く。

### 文字列と文字のリテラル

```text
StrTok ::= "\"" StrChar* StrClose
StrChar ::= Escape
          / !["\\\n] .
Escape ::= "\\" ["'\\nt]
         / "\\u{" [0-9A-Fa-f]+ "}"
StrClose ::= "\""
           / &("\n" / !.) Never ^unclosed_string
StrLitLoc(nl) ::= StrTok Sp(nl)
CharTok ::= "'" (Escape / !['\\\n] .) CharClose
CharClose ::= "'"
            / &("\n" / !.) Never ^unclosed_char
CharLitLoc(nl) ::= CharTok Sp(nl)
Never ::= !. .
```

文字列は `"` で囲み、改行を含められない。
文字は `'` で囲んだ一字かエスケープ一つである。
エスケープは `\"`、`\'`、`\\`、`\n`、`\t`、`\u{16 進数}` に限る。
`\u{...}` の値が Unicode のスカラー値でなければ（サロゲートか U+10FFFF を超える値）、文法の後の検査で E01100 とする。
閉じる `"` か `'` がないまま行かファイルが終われば、E01101 とする。

`Never` は決して成功しない規則で、`^label` と組んで、その位置で解析を止める（「誤りのラベル」の節）。

### 記号

```text
K<w> ::= w !IdChar
KS<w>(nl) ::= K<w> Sp(nl)
S<s> ::= s
```

語（`K<w>`）は、後ろに名前の字が続かないときだけ一致する（`types` は語 `type` ではない）。
記号の字句と、その前後で読む空白は次のとおりである。
字句の前に `SpN` を持つ規則は前の改行を読み、後ろに `SpN` を持つ規則は後ろの改行を読む。
`SpH` は改行を読まず、`Sp(nl)` は引数による。

```text
WhereS ::= SpN K<"where"> SpH
OpenBlock ::= "{"
OpenBlockS ::= OpenBlock SpH
CloseBlock ::= "}"
             / !. Never ^unclosed_brace
CloseBlockS(nl) ::= CloseBlock Sp(nl)
OpenRecS ::= S<"{"> SpN
CloseRecS(nl) ::= S<"}"> Sp(nl)
                / !. Never ^unclosed_brace
GuardBar ::= "|" !"|"
GuardBarS ::= SpN GuardBar SpH
DataBarS ::= SpN "|" !"|" SpH
OpenParenS ::= S<"("> SpN
CloseParenS(nl) ::= S<")"> Sp(nl)
                  / &("}" / !.) Never ^unclosed_paren
OpenBracketS ::= S<"["> SpN
CloseBracketS(nl) ::= S<"]"> Sp(nl)
                    / &("}" / !.) Never ^unclosed_bracket
CommaS ::= "," SpN
EqS ::= "=" !("=" / ">") SpN
DColonS ::= "::" SpN
ColonS ::= SpN ":" !":" SpN
QuestionS ::= SpN "?" SpN
ArrowS ::= SpN "->" SpN
MinusS(nl) ::= S<"-"> !("-" / ">") Sp(nl)
WildS(nl) ::= S<"_"> !IdChar Sp(nl)
OrOpS ::= SpN "||" SpN
AndOpS ::= SpN "&&" SpN
AppendOpS ::= SpN "++" SpN
PowOpS ::= SpN "**" SpN
```

`case` と `where` の `{ }`（`OpenBlock`）と、レコードの `{ }`（`OpenRecS`）は、同じ字だが別の字句である。
前者の中は改行が区切りになり、後者の中は改行が空白になる。
`;` は字句として持たないので、書けば E01100 である。

## 改行と区切り

Emet はオフサイドルールを採らず、字下げは空白と同じである。
最上位の宣言、`where { }` の束縛、`case ... of { }` の選択肢は、改行で区切る。

```text
Items<p> ::= Sep? p (Sep p)* Sep?
           / Sep?
Sep ::= (SepNl SpH)+
SepNl ::= "\n"
```

`Items<p>` は、改行で区切った `p` の並びである。
空行と、コメントだけの行は、区切りが続くだけである。
初めの項目の前と最後の項目の後ろの改行も、区切りとして読む。
`SepNl` と `Nl` はどちらも改行一字だが、ロスレスな構文木では別の種類の字句になる。
`golem fmt` は、`SepNl` の後ろの行を項目の始まり、`Nl` の後ろの行を続きの行として字下げする（[specifications.md](specifications.md) の「fmt」）。

改行を区切りとして残すか、空白として読むかは、改行の前後の字句と括弧の入れ子だけで決まる。

- 式、パターン、型の規則は引数 `nl` を取る。`nl` が偽の位置では、字句の後ろの `Sp(False)` が改行を読まずに残し、残った改行が `Sep` になる。
- `(`、`[`、レコードの `{` の中では、規則を `nl` を真にして呼ぶので、改行は空白である。要求の列の `< >` の中も、要求を `nl` を真にして読む。
- `case ... of { }` と `where { }` の中は、括弧の中でも項目を `nl` を偽にして読む。
- 後ろの改行をつねに読む字句（行の最後に置けば次の行に続く字句）は、二項演算子、`=`、`->`、`::`、`,`、`?`、`:` と、開く括弧の `(`、`[`、レコードの `{`、`<` である。
- 前の改行をつねに読む字句（次の行の最初に置けば前の行に続く字句）は、ガードと `data` の `|`、`-` を除く二項演算子、`?`、`:`、`where`、`->` である。改行を読んでから字句に一致しなければ、PEG の後戻りで改行を読む前に戻り、改行を区切りとして読む。
- 二項演算子の `-` は前の改行を読まない。行頭の `-` は新しい項目の始まりであり、`case` の選択肢の負の数のパターンとして読める。引き算を次の行に続けるときは、行の最後に `-` を置く。
- 括弧の外で、ほかの字句（名前、リテラル、`case`、`of`、`{`、`pub` などの語）の前にある改行は区切りである。関数の適用を次の行に続けることはできない。括弧で囲むか、行の最後に演算子を置く。

次の関数は、どの改行も続きの行を示す字句の前後にあるので、一つの等式である。

```haskell
total :: Nat -> Nat -> Nat
total price rate =
  price
    + div (price * rate) 100
```

次の行を `-` で始めると、引き算ではなく新しい宣言の始まりになり、E01100 になる。
`x\n  - 1`（`\n` は改行）は `x -\n  1` と書く。

`case` の `of` と `{`、`where` と `{`、ガードの `|` と条件は、同じ行に書く。
括弧の外では、`case` の調べる式の終わりと `of` も同じ行に書く。
どれも、あいだの改行が区切りとして残り、E01100 になる。

## 宣言

```text
Decl ::= Import
       / Data
       / TypeAlias
       / Signature
       / Equation
```

最上位の宣言は、取り込み、データ型、型の別名、シグネチャ、等式の五つである。
Emet に文（statement）はなく、関数の本体は一つの式である。

### 取り込み

```text
Import ::= KS<"import">(False) StrLitLoc(False)
```

`import "パス"` は、ほかの `.emet` の公開された名前を、名前空間を付けずに取り込む。
パスはプロジェクトのルートからの相対パスである。
文法は `import` を最上位のどこに置いても読む。
`as` を付けた取り込みはない。

```haskell
import "functions/numbers.emet"
```

### データ型と型の別名

```text
Data ::= PubOpt KS<"data">(False) ConNameLoc(False) VarName(False)* EqS ConDecl (DataBarS ConDecl)*
PubOpt ::= KS<"pub">(False)
         / ε
ConDecl ::= ConNameLoc(False) OpenRecS FieldDecl (CommaS FieldDecl)* CloseRecS(False)
          / ConNameLoc(False) AType(False)*
FieldDecl ::= VarName(True) DColonS Type(True)
TypeAlias ::= PubOpt KS<"type">(False) ConNameLoc(False) VarName(False)* EqS Type(False)
```

データ型は、コンストラクタを `|` で区切って並べる。
コンストラクタは、位置で並べた欄の型を持つか、`{ }` の中に名前と型の欄を一つ以上持つ（レコード）。
欄のないレコードの宣言（`C {}`）は書けない。
型の引数は、型の名前と同じ行に書く。
`|` は前の改行を読むので、二つ目からのコンストラクタは行頭の `|` で始められる。
`=` は前の改行を読まないので、`data` の行に書く。

```haskell
pub data Shape = Circle Rat | Rect Rat Rat

data Pair a b = Pair a b

pub data Book = Book { title :: String, year :: Nat }

data Mark =
  Done
  | Todo String

pub type Name = String
```

`pub` を付けたデータ型は、コンストラクタとともに公開する。
データ型と型の別名には、種類の語（`inline` など）を書けない。

### シグネチャ

```text
Signature ::= SigPub VarNameLoc(False) DColonS LeadRow Type(False)
SigPub ::= KS<"pub">(False) KindWord StrLitLoc(False)?
         / KS<"pub">(False)
         / ε
KindWord ::= KS<"inline">(False)
           / KS<"block">(False)
           / KS<"filter">(False)
           / KS<"fn">(False)
LocalSignature ::= VarNameLoc(False) DColonS LeadRow Type(False)
```

シグネチャは、関数の名前、`::`、型である。
最上位の関数は、シグネチャを必ず持つ（E02102）。
`pub` を付けた関数は、ほかの `.emet` から使える。
`pub` の後ろの種類の語（`inline`、`block`、`filter`、`fn`）は、`.gm` からの使い方を決める（「.gm からの呼び出し」の節）。
種類の語の後ろには、`.gm` に出す名前を文字列で書ける。
種類の語は一つだけで、二つ書く（`pub inline fn f`）と E01100 である。
文字列の名前は種類の語の後ろにだけ書け、`pub "x" f` は E01100 である。
`::` の直後には要求の列（`LeadRow`）を書ける（「要求の列」の節）。
`where` の中のシグネチャ（`LocalSignature`）は、`pub` を持たない。

```haskell
pub inline "tax-included" taxIncluded :: Nat -> (tax :: Bool = True) -> Inlines
taxIncluded n tax = Inline.text (String.fromNat n ++ (tax ? "（税込）" : ""))

pub fn total :: List Nat -> Nat
total xs = List.foldl add 0 xs
  where {
    add a b = a + b
  }
```

### 等式

```text
Equation ::= VarNameLoc(False) APat(False)* Rhs Where*
Rhs ::= EqS Expr(False)
      / GuardEq+
GuardEq ::= GuardBarS GuardCond EqS Expr(False) Where*
GuardCond ::= KS<"otherwise">(False)
            / Expr(False)
```

等式は、関数の名前、引数のパターン、右辺である。
引数のパターンは関数の名前と同じ行に書く。
右辺は、`=` と式か、一つ以上のガードである。
ガードは `|`、条件、`=`、式であり、条件は式か `otherwise` である。
ガードの `|` は前の改行を読むので、ガードは次の行から書ける。

```haskell
sign :: Int -> String
sign 0 = "零"
sign n
  | n < 0 = "負"
  | otherwise = "正"
```

文法は等式とガードの後ろに `where` をいくつでも読むが、検査が位置を限る（E01103、次の節）。
同じ関数の等式は続けて書く（E02107）。
等式の引数の数はどれも同じで、シグネチャの矢印の数を超えない（E02106）。
ガードの並びの最後は `otherwise` でなければならない（E03102）。

### where

```text
Where ::= WhereS OpenBlockS Items<Binding> CloseBlockS(False)
Binding ::= LocalSignature
          / Equation
```

`where { }` の中には、シグネチャと等式を改行で区切って並べる。
`where` は前の改行を読むので、等式の次の行に書ける。
`where` と `{` は同じ行に書く。

文法は `where` を等式、ガード、`case` の選択肢、選択肢のガードの後ろに、いくつでも読む。
型の検査の前の検査（`Golem.Emet.Check`）が、次の位置の `where` を E01103 とする。

- 関数の最後でない等式の後ろの `where`。
- ガードのある等式で、最後でないガードの後ろの `where`。
- 一つの関数の二つ目の `where`。
- `where` の中の束縛の `where`。
- `case` の選択肢と、選択肢のガードの後ろの `where`。

`where { }` の中が空でも、文法としては読む。

```haskell
label :: Maybe Nat -> String
label Nothing = bracket "なし"
label (Just n) = bracket (String.fromNat n)
  where {
    bracket :: String -> String
    bracket s = "［" ++ s ++ "］"
  }
```

## 型と要求の列

### 型

```text
Type(nl) ::= BType(nl) ArrowS ArrowRow(nl) Type(nl)
           / BType(nl)
BType(nl) ::= TyConLoc(nl) AType(nl)+
            / AType(nl)
AType(nl) ::= OpenParenS ArgNameE DColonS Type(True) DefaultOpt CloseParenS(nl)
            / TyConLoc(nl)
            / VarNameLoc(nl)
            / OpenParenS Type(True) (CommaS Type(True))* CloseParenS(nl)
TyConLoc(nl) ::= QualCon Sp(nl)
               / ConNameLoc(nl)
ArgNameE ::= VarNameLoc(True)
           / StrLitLoc(True)
DefaultOpt ::= EqS Expr(True)
             / ε
```

`->` は右に結合する（`Nat -> Nat -> Nat` は `Nat -> (Nat -> Nat)`）。
型の適用は、型の名前に型を並べる（`List (Maybe Nat)`、`Block.Block`）。
型の変数を型に当てることはできない（`f a` は型ではない）。
`.emet` は高い種の型を持たないためである。
括弧の中に型を二つ以上並べると組の型になる。
空の組の型（`()`）はない。

`(名前 :: 型 = 既定の値)` は、`.gm` から呼ぶ関数のキーワード引数である（[ADR 0162](../adr/0162-calling-emet-functions-from-gm.md)）。
名前は識別子か文字列（`("font-size" :: Rat = 10)`）である。
既定の値は式の文法で読み、リテラルかどうかは後で検査する（E06103）。
既定の値を省いた形（`(tax :: Bool)`）も文法としては読み、E06103 とする。
型の上では、括弧で囲んだ型と同じ一つの引数である。

### 要求の列

```text
LeadRow ::= Row(False)
          / ε
ArrowRow(nl) ::= Row(nl)
               / VarNameLoc(nl) &AType(nl)
               / ε
Row(nl) ::= RowOpen SpN CommaList<Req> RowTail RowClose Sp(nl)
RowOpen ::= "<"
RowClose ::= ">"
RowTail ::= "|" SpN VarNameLoc(True)
          / ε
Req ::= VarNameLoc(True) StrLitLoc(True)*
```

関数が処理系に求めるもの（要求）は、`->` の後ろ、結果の型の前に `< >` で囲んで書く（[docs/adr/0161](../adr/0161-emet-requirements-and-driver-handlers.md)）。
引数のない関数の要求は、`::` の直後に書く。
要求は、種類の名前と文字列の並びである（`file "data/units.tsv"`）。
要求を `,` で区切って並べ、最後に `|` と変数を書くと開いた列になる。
`->` の後ろの変数の後ろに型が続けば、その変数だけの列である（`a -> e String` の `e`）。
型の変数を型に当てることはないので、この読み方は型の適用と重ならない。

```haskell
pub block "unit-table" unitTable ::
  <file "data/units.tsv"> Blocks
unitTable = Block.paragraph (Inline.text (File.read "data/units.tsv"))

apply :: (String -> e String) -> String -> e String
apply f s = f s
```

文法は、種類の名前と文字列の数を限らない。
v1 の種類は `file` だけで、ほかの種類は E05100、文字列が一つでない `file` は E02101 である。
種類のない列（`<>`）も文法としては読む。

## パターン

```text
Pat(nl) ::= PApp(nl) ColonS Pat(nl)
          / PApp(nl)
PApp(nl) ::= ConRefLoc(nl) APat(nl)+
           / APat(nl)
APat(nl) ::= WildS(nl)
           / VarNameLoc(nl)
           / NumLitLoc(nl)
           / MinusS(False) NumLitLoc(nl)
           / StrLitLoc(nl)
           / CharLitLoc(nl)
           / OpenBracketS CommaList<Pat(True)> CloseBracketS(nl)
           / ConRefLoc(False) OpenRecS CommaList<FieldPat> CloseRecS(nl)
           / ConRefLoc(nl)
           / OpenParenS Pat(True) (CommaS Pat(True))* CloseParenS(nl)
FieldPat ::= VarName(True) EqS Pat(True)
CommaList<p> ::= p (CommaS p)*
               / ε
```

パターンは、ワイルドカード `_`、変数、数（負の数を含む）、文字列、文字、リスト、レコード、コンストラクタ、組、括弧である。
`:` は右に結合し、`x : y : rest` は `x : (y : rest)` である。
引数を取るコンストラクタ（`Just x`）と `:` のパターンは、等式の引数では括弧で囲む（`f (Just x) = ...`、`f (x : xs) = ...`）。
等式の引数は `APat` で読むからである。
`case` の選択肢は `Pat` で読むので、括弧なしで書ける。
レコードのパターン（`Book { year = y }`）は、コンストラクタと `{` を同じ行に書き、欄の一部だけを書ける。
等式の引数でも、括弧なしで書ける。
`-` と数のあいだには空白を置ける（`- 1`）が、改行は置けない。

```haskell
pub data Book = Book { title :: String, year :: Nat }

yearOf :: Book -> Nat
yearOf Book { year = y } = y

firstTwo :: List Nat -> Maybe (Nat, Nat)
firstTwo (a : b : _) = Just (a, b)
firstTwo _ = Nothing

kind :: Int -> String
kind n = case n of {
  -1 -> "負の一"
  0 -> "零"
  _ -> "ほか"
}
```

## 式

```text
Expr(nl) ::= Case(nl)
           / Ternary(nl)
```

式は、`case` 式か、三項演算子を含む演算子の式である。
`if`、`let`、ラムダ式（`\x -> e`）、演算子の切片（`(+ 1)`）、演算子を関数として書く形（`(+)`）、逆引用符の中置（`` `div` ``）はない。
局所の関数は `where` に書いて、名前で渡す。

### case

```text
Case(nl) ::= KS<"case">(nl) Expr(nl) KS<"of">(False) OpenBlockS Items<Alt> CloseBlockS(nl)
Alt ::= Pat(False) AltRhs Where*
AltRhs ::= ArrowS Expr(False)
         / GuardAlt+
GuardAlt ::= GuardBarS GuardCond ArrowS Expr(False) Where*
```

`case 式 of { }` の中には、選択肢を改行で区切って並べる。
選択肢は、パターンと、`->` と式か、一つ以上のガード（`| 条件 -> 式`）である。
`case` は、式を書く位置（等式の右辺、ガードの条件、括弧とリストの中、三項演算子の偽の枝など）の全体か、三項演算子の真の枝に書ける。
演算子の項（`1 + case ...`）、関数の引数、三項演算子の条件に書くときは、括弧で囲む。
`case` の後ろに演算子を続けることもできない。
選択肢の後ろの `where` は E01103 である。
選択肢のない `case x of { }` も文法としては読み、網羅性の検査が E03100 とする。

```haskell
label :: Maybe Nat -> String
label n = case n of {
  Just k
    | k > 1 -> "第" ++ String.fromNat k ++ "版"
    | otherwise -> "初版"
  Nothing -> "版なし"
}
```

### 演算子

```text
Ternary(nl) ::= Or(nl, True) QuestionS TrueBranch(nl) ColonS Expr(nl)
              / Or(nl, True)
TrueBranch(nl) ::= Case(nl)
                 / Or(nl, False)
Or(nl, cons) ::= And(nl, cons) OrOpS Or(nl, cons)
               / And(nl, cons)
And(nl, cons) ::= Cmp(nl, cons) AndOpS And(nl, cons)
                / Cmp(nl, cons)
Cmp(nl, cons) ::= Append(nl, cons) CmpOp Append(nl, cons)
                / Append(nl, cons)
CmpOp ::= SpN "==" SpN
        / SpN "/=" SpN
        / SpN "<=" SpN
        / SpN ">=" SpN
        / SpN "<" SpN
        / SpN ">" SpN
Append(nl, cons) ::= AddE(nl) AppendOp(cons) Append(nl, cons)
                   / AddE(nl)
AppendOp(cons) ::= AppendOpS
                 / &{cons} ColonS
AddE(nl) ::= MulE(nl) AddTail(nl)*
AddTail(nl) ::= AddOp MulE(nl)
AddOp ::= SpN "+" !"+" SpN
        / "-" !("-" / ">") SpN
MulE(nl) ::= Unary(nl) MulTail(nl)*
MulTail(nl) ::= MulOp Unary(nl)
MulOp ::= SpN "*" !"*" SpN
        / SpN "/" !"=" SpN
        / SpN "%" SpN
Unary(nl) ::= MinusS(nl) Unary(nl)
            / PowE(nl)
PowE(nl) ::= App(nl) PowOpS Unary(nl)
           / App(nl)
```

演算子の優先順位と結合は次のとおりである。
上ほど強く結び付く。

| 順位 | 演算子 | 結合 | 規則 |
| --- | --- | --- | --- |
| 1 | 関数の適用（`f x y`） | 左 | `App` |
| 2 | `**` | 右 | `PowE` |
| 3 | 単項の `-` | 前置 | `Unary` |
| 4 | `*`、`/`、`%` | 左 | `MulE` |
| 5 | `+`、`-` | 左 | `AddE` |
| 6 | `++`、`:` | 右 | `Append` |
| 7 | `==`、`/=`、`<`、`<=`、`>`、`>=` | 結合しない | `Cmp` |
| 8 | `&&` | 右 | `And` |
| 9 | `\|\|` | 右 | `Or` |
| 10 | `? :`（三項演算子） | 偽の枝で右 | `Ternary` |

- `**` の右の項は単項の `-` を含められる（`2 ** -1`）。`-x ** 2` は `-(x ** 2)` である。`2 ** 3 ** 2` は `2 ** (3 ** 2)` である。
- 単項の `-` は乗除の項にも書ける（`a * -b`、`a - -1`）。
- 比較の演算子は結合しないので、`1 < x < 3` は E01100 である。`1 < x && x < 3` と書く。
- `++` と `:` は同じ順位で右に結合する。`x : xs ++ ys` は `x : (xs ++ ys)` である。
- 比較より `:` が強いので、`x : xs == ys` は `(x : xs) == ys` である。
- `div` は演算子ではなく、組み込みの関数である（`div a b`）。
- 等しくないことは `/=` と書き、`!=` はない。

三項演算子は `条件 ? 真の枝 : 偽の枝` である。
条件は `Or` で読むので、三項演算子と `case` を含まない（含めるときは括弧で囲む）。
真の枝は、最上位に `?` も `:` も持たない式か、`case` 式である。
`AppendOp` の `&{cons}` は、引数 `cons` が偽のとき（真の枝の中）、`:` を演算子として読まない。
そのため、真の枝の後ろの最初の `:` が、三項演算子の `:` になる。
偽の枝は任意の式で、三項演算子を続けられる（`a ? x : b ? y : z` は `a ? x : (b ? y : z)`）。
`c ? x : xs : ys` は `c ? x : (xs : ys)` と読む。
真の枝に三項演算子か `:` を書くときは、括弧で囲む（`a ? (b ? c : d) : e`、`c ? (x : xs) : ys`）。
囲まない `a ? b ? c : d : e` は E01100 である。

```haskell
commas :: Nat -> String
commas n = n < 1000 ?
  String.fromNat n :
  commas (div n 1000) ++ "," ++ String.fromNat (n % 1000)

grade :: Nat -> String
grade n = n >= 80 ? "優" : n >= 60 ? "可" : "不可"
```

### 関数の適用と項

```text
App(nl) ::= Atom(nl) Atom(nl)*
Atom(nl) ::= OpenParenS Expr(True) (CommaS Expr(True))* CloseParenS(nl)
           / OpenBracketS CommaList<Expr(True)> CloseBracketS(nl)
           / NumLitLoc(nl)
           / StrLitLoc(nl)
           / CharLitLoc(nl)
           / QualVarLoc(nl)
           / VarNameLoc(nl)
           / ConRefLoc(False) OpenRecS CommaList<FieldExpr> CloseRecS(nl)
           / ConRefLoc(nl)
FieldExpr ::= VarNameLoc(True) EqS Expr(True)
```

関数の適用は、項を空白で区切って並べる。
項は、括弧の式、組、リスト、リテラル、名前、レコード、コンストラクタである。
括弧の中に式を二つ以上並べると組になる。
空の組（`()`）はない。
リストは `[]` と `[a, b, c]` である。
レコードは、コンストラクタと `{` を同じ行に書き、`{ 欄 = 式, ... }` で作る。
欄はすべて一度ずつ書く（検査が確かめる）。
レコードは一つの項なので、括弧なしで関数の引数にできる（`f Book { title = "題", year = 2020 }`）。
式の中に `_` は書けない。

関数の引数は項なので、`f -1` は `f` から 1 を引く式である。
負の数を渡すときは括弧で囲む（`f (-1)`）。

```haskell
pub data Book = Book { title :: String, year :: Nat }

first :: Book
first = Book { title = "題", year = 2020 }

pairs :: List (Nat, String)
pairs = List.zip [1, 2, 3] ["一", "二", "三"]

shift :: Int -> Int
shift n = n - 1

before :: Int
before = shift (-1)
```

## 誤りのラベル

`^label` の付いた選択肢は、閉じる括弧か引用符が来るべき位置でファイルが終わったときにだけ、その位置で解析を止める。
`(` と `[` は `}` が来たときも、引用符は行が終わったときも止める。
ほかの選択肢がどれも続けられない位置なので、後戻りをやめても読み方は変わらない（`Emet.hpeg` の `%safe`）。

| ラベル | 規則 | diagnostic |
| --- | --- | --- |
| `unclosed_paren` | `CloseParenS` | E01101（閉じていない `(`） |
| `unclosed_bracket` | `CloseBracketS` | E01101（閉じていない `[`） |
| `unclosed_brace` | `CloseBlock`、`CloseRecS` | E01101（閉じていない `{`） |
| `unclosed_string` | `StrClose` | E01101（閉じていない文字列） |
| `unclosed_char` | `CharClose` | E01101（閉じていない文字） |

ほかの構文の誤りは、解析が止まった位置の E01100 で、メッセージにその位置に書ける字句を並べる。

## 文法の後の検査

文法が読んでも、次の検査が誤りにするものがある。
コードの意味と直し方は [docs/diagnostics.md](../diagnostics.md) にある。

| 検査 | diagnostic |
| --- | --- |
| `\u{...}` がスカラー値でない | E01100 |
| `where` の位置（「where」の節） | E01103 |
| シグネチャのない最上位の関数 | E02102 |
| 等式の引数の数がそろわないか、矢印の数を超える | E02106 |
| 同じ関数の等式のあいだに、ほかの宣言がある | E02107 |
| ガードの並びの最後が `otherwise` でない | E03102 |
| 一覧にない要求の種類 | E05100 |
| `.gm` から使う関数の宣言（名前、引数の並び、キーワード引数、可変長引数） | E06100 から E06106 |

## .gm からの呼び出し

`.gm` は、`@import パス as 名前空間` で `.emet` を取り込み、`pub` の後ろの種類の語で決まる形で呼ぶ（[ADR 0162](../adr/0162-calling-emet-functions-from-gm.md)、仕様書の「[.gm から関数を使う](../specifications.md#gm-から関数を使う)」）。
呼び出しの文法は `.gm` の文法（[docs/markup.md](../markup.md)）であり、Emet の文法ではない。

| `.emet` の宣言 | `.gm` からの呼び出し |
| --- | --- |
| `pub inline "tax-included" taxIncluded :: Nat -> Inlines` | `[book.tax-included 1000]` |
| `pub inline boxed :: Inlines -> Inlines` | 散文スロットに書く `[book.boxed: 校了]` |
| `pub block memo :: Blocks -> Blocks` | 行頭の `@book.memo` と、その下に字下げした本体 |
| `pub fn total :: List Nat -> Nat` | 式文脈の `[= book.total([1200, 800])]` |
| `pub filter lead :: Blocks -> Blocks` | `manifest.toml` の `[[filters]]` の `function` と `filter` |
| `pub f :: ...` | `.gm` からは呼べない。ほかの `.emet` から使う |

コマンドの位置引数、可変長引数（`Varargs a`）、キーワード引数（`(名前 :: 型 = 既定の値)`）、散文スロット（最後の `Inlines`）、本体（最後の `Blocks`）は、シグネチャの型から決まる。
写し方の規則は、仕様書の「[引数の写し方](../specifications.md#引数の写し方)」にある。

## エディタの文法との違い

エディタのための文法（tree-sitter の `tools/editors/tree-sitter-emet/grammar.js` と、TextMate の `tools/editors/textmate/emet.tmLanguage.json`）は、`Emet.hpeg` とは別に書いてある（[docs/adr/0170](../adr/0170-emet-editor-support.md)、[tools/editors/README.md](../../tools/editors/README.md)）。
tree-sitter の文法は、Golem が読む `.emet` を読めるように書き、Golem が誤りとする文字列の一部も読む。
CI の `editors` ジョブが、テストの `.emet` と二つのマニュアルの `.emet` を tree-sitter で読めることを確かめている。
この文書の例も tree-sitter で読める。

tree-sitter の文法は、次の文字列も読む。
どれも Golem では誤りである。

| 文字列 | tree-sitter | Golem |
| --- | --- | --- |
| `1 < x < 3` | 比較を左に結合する | E01100（比較は結合しない） |
| `1 + case x of { ... }`、`case x of { ... } ? a : b` | 演算子の項と三項演算子の条件に `case` を書ける | E01100 |
| `data T = C {}` | 欄のないレコードの宣言 | E01100 |
| `f\n  x = x`、`data T\n  = A`、`case x\n  of {`、`case x of\n{`、`where\n{`、`\|\n  otherwise = x` | パーサーが区切りを受け取れない位置の改行を空白として読む | E01100（改行は区切り） |
| `1E3` | 数 `1` にコンストラクタ `E3` を当てる | E01100（数の直後に英字は続けられない） |
| CR を含む行 | CR を空白として読む | G01003 |
| `if`、`let` などの使えない予約語 | 名前として読む | E01102 |

TextMate の文法は行ごとの正規表現であり、文法の全体を表さない。
色付けの粗さは [tools/editors/README.md](../../tools/editors/README.md) にある。

## 参考文献

- Bryan Ford, "Parsing Expression Grammars: A Recognition-Based Syntactic Foundation", POPL 2004.
