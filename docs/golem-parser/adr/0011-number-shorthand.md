# ADR 0011: 数の糖衣構文 `##…##`

ステータス: 採択

## 文脈

v0.1.0-rc3 で、数の扱いの糖衣構文として `##1##` を導入する（メンテナーの指示）。

Golem は、表記を決めていない数を `[number-text ...]` で書く（docs/markup.md の「数の表記」）。
`[number-text 10]` は意味論 IR の `Number` になり、表記は書字方向が決まった段階で決まる（[golem-layout ADR 0002](../../golem-layout/adr/0002-japanese-composition.md)、[golem-eval ADR 0001](../../golem-eval/adr/0001-expression-language-and-numerics.md)）。
横組みでは算用数字の「10」、縦組みでは `style` 引数か `style.toml` の `[numbers]` の `vertical` に従い、「十」「一〇」「縦中横の 10」のどれかになる。
HTML、EPUB、プレーンテキストも同じ `Number` から書字方向に合わせて表記を選ぶ。

この仕組みは、縦組みと横組みの両方に出す原稿で数を一度だけ書くためにある。
しかし `[number-text 10]` は、本文の数一つに 16 字の記法を要する。
日付や数量の多い原稿では、書き手は記法を省いて算用数字をそのまま書くか、`[tcy: 10]` で縦中横を直に指定することになる。
前者は縦組みで漢数字にならず、後者は横組みとプレーンテキストでも縦中横の要素として残る。
G02063（「数の縦中横は [number-text 36 style=tcy] でも書けます」、[golem-syntax ADR 0002](../../golem-syntax/adr/0002-notice-severity.md)）は後者を見つけて案内するが、案内の先の記法が長いことは変わらない。

### 今の文法での `##`

`#` は、行頭でだけ記法の文字である（[ADR 0003](0003-block-grammar.md)）。
文法の `BlockStart` は行頭の `#` をブロックの始まりとし、`Paragraph` は `!BlockStart` で行頭の `#` を拒む。
見出しは `HashMark`（`#`、`##`、`###`）の直後に空白を要求するので、`##1##` で始まる行は見出しにならず、段落にもならず、G01010 になる。
`####` は G01012 になる。

行の途中の `#` は、地の文（`Text`、`SlotText`、`CellText`）の文字である。
今の版では `本文##1##本文` は「本文##1##本文」と組まれる。
つまり行の途中の `##` に意味を与えるのは、今の原稿の解釈を変える変更である。
リポジトリの 71 個の `.gm` ファイルを調べると、`##` の直後に数字が続く箇所はない。
見出しの印を除いて `##` が現れるのは `manual-dev/part2/10-docs.gm` の `[code: ##]` だけで、直後が `]` なので、この ADR の規則でも地の文のままである。

### 文法と `Lower` はコマンドの名前を知らない

文法と `Golem.Parser.Lower` は、コマンドの名前を見ない（[ADR 0004](0004-inline-grammar.md)、[ADR 0010](0010-ruby-slash-escape-and-table-cell-breaks.md)）。
`[code: ...]` の散文スロットも、`[strong: ...]` の散文スロットと同じ `ProseSlot` として読む。
名前で振る舞いを分けるのは評価であり、組み込みのコマンドは golem-eval の `Golem.Eval.Builtin` の型で表す（[docs/adr/0027](../../adr/0027-exhaustive-command-dispatch-by-types.md)）。
したがって、文法も `Lower` も、`##1##` がコードの中にあるかどうかを知らない。

### メンテナーが決めたこと

起草の後、メンテナーが次のように決めた。

- `##` と `##` のあいだに書けるのは ASCII の数字だけとする。全角の数字、符号、小数点、桁区切りは書けない。負の数は書けない。
- `[numbers]` の `vertical` に、「2 桁までは縦中横、それより長ければ漢数字」のような、数によって表記の変わる値（`auto` など）を加える。`##N##` の縦組みの表記は `[numbers]` に従うので、この値で糖衣構文だけで書ける数が増える。
- `##1##` はコードの中（`[code: ...]` など）では記法として認めない。
- `Lower` にコマンドの名前を一つも覚えさせない。起草のときの、`##N##` を `Command "number-text"` に下ろす設計はやめ、AST に専用の構築子を設ける。評価は、それを `[number-text N]` と同じく組む。コードの中で認めない仕組みも、`Lower` にコマンドの名前を知らせずに作る。
- 仕様（docs/markup.md、docs/specifications.md）は、実装のときに書く。

## 実装すること

### 記法

```
令和##6##年##10##月##16##日
```

`##` と `##` で、0 から 9 の ASCII の数字を挟む。
`##N##` は `[number-text N]` と同じ意味である。
`style` 引数を省いた `[number-text ...]` と同じく、横組みでは算用数字、縦組みでは `style.toml` の `[numbers]` の `vertical` の表記になる。
上の例は、横組みで「令和6年10月16日」、`vertical = "kanji"` の縦組みで「令和六年十月十六日」になる。

- 中に書けるのは、`0` か、`1` から `9` で始まる ASCII の数字の並びである。
- 先頭の `0`（`##007##`）は書けない。`[number-text 007]` と同じく 7 になり、書いた字が組まれないからである。
- 次のものも書けない。符号（`+`、`-`、`−`）、小数点、全角の数字（`１２`）、桁区切り（`1,000`）、空白、式。
- 表記を個別に選ぶ記法は持たない。縦組みで一つの数だけ表記を変えるときは、今と同じく `[number-text 10 style=kanji]` と書く。

### `##` が記法になる位置

**数の開き**を、`##` の直後に ASCII の数字（`0` から `9`）が続くものとする。

数の開きは、地の文の書ける位置では常に数の糖衣構文の始まりである。
地の文の規則は数の開きを読まない。
これは、本文の `[` が常にインラインの要素の始まりであるのと同じ扱いである（docs/markup.md の「エスケープ」）。

`##` の後が ASCII の数字でなければ、今と同じく地の文である。
`C##`、`##]`、`####`、`##見出し##`、`##１２##`、`##-3##` は地の文のままになる。
全角の数字や符号を開きに含め、書き誤りとして知らせる案もあったが、採らない（「トレードオフ」）。

糖衣構文を読める位置は、段落、見出し、リストの項目、定義リストの用語と説明、表のセル、命令文脈の散文スロット（ルビ、圏点、注、コードなど）である。
コマンドの引数、式文脈、文字列リテラル、コメント、コードブロックの中では読まない。
引数の `##1##` は今と同じく語（`Word`）であり、`[number-text ##1##]` は G02019 になる。
引数の数は `[number-text 1]` のように直に書けるので、引数に糖衣構文は要らない。

本文に `##` と数字を続けて書くときは、`\##1##` のように最初の `#` をエスケープする。
`\#` の次の `#` は、直後が `#` でなく数字なので開きにならない。

### 中身と閉じ

文法は、数の開きの後を、閉じの `##` か、糖衣構文の中に書けない文字の手前まで読む。
中身が正しいかどうかは、文法では検査しない。
中身を検査するのは評価であり、コードの中では検査しない（「コードの中」の節）。

- 中身は、`#`、改行、`[`、`]`、`|`、`\`、`%%` のどれでもない文字の並びである。
- 中身の後に `##` があれば、それを閉じとして読む。
- なければ、閉じのない糖衣構文として、中身の終わりで止まる。

たとえば `##1.5##` は中身 `1.5` と閉じを持つ糖衣構文、`##12年` で終わる行は中身 `12年` で閉じのない糖衣構文になる。
どちらも文法の誤りにはならない。
閉じがなくても文法は失敗しないので、ラベルも回復の規則も要らない。

### 行頭の `##`

行頭の数の開きは、ブロックの始まりにしない。
`##1##年` で始まる行は、`##1##` の数で始まる段落になる。
見出しの `##` は直後に空白を要るので、数の開きと見出しの印は一字目の後で必ず分かれる。

- `## 第##1##節`：二階層めの見出しで、題の中に数がある。
- `##1## 年`：段落。
- `###1##`：今と同じく G01010。行頭の `#` の直後が `#` で、その次も `#` なので、一字目は数の開きではない。
- `#1`：今と同じく G01010。

段落の続きの行（改行の様式と強制改行の後の行）でも、数の開きで始まる行は段落の続きになる。

### 文法

`modules/golem-parser/grammar/Golem.hpeg` を次のように直す（規則の形は目安であり、名前は実装で決める）。

```
%token NumberMark
%token NumberBody

NumberOpen :: ()
NumberOpen <- '##' [0-9] { () }

NumberShorthand :: ()
NumberShorthand <- &NumberOpen NumberMark NumberBody NumberMark? { () }

NumberMark :: ()
NumberMark <- '##' { () }

NumberBody :: ()
NumberBody <- (![#\n\[\]|\\] !'%%' .)+ { () }
```

- `Inline`、`HeadInline`、`SlotInline`、`CellInline` に、`Text` 類より前の選択肢として `NumberShorthand` を加える。
- `Text`、`SlotText`、`CellText` の繰り返しに `!NumberOpen` を加える。
- `BlockStart` の `'#'` を `!NumberOpen '#'` にする。

`NumberShorthand` は `&NumberOpen` の後で必ず成功するので、新しいラベルはない。
`%safe` の注釈も要らない。

### CST

`SyntaxKind` に、トークン `KNumberMark` と `KNumberBody`、ノード `NNumberShorthand` を加える。
`##1##` は `NNumberShorthand [KNumberMark "##", KNumberBody "1", KNumberMark "##"]` になり、原稿のバイト列をそのまま保つ。
閉じのない `##12年` は、`NNumberShorthand [KNumberMark "##", KNumberBody "12年"]` になる。

### AST

`Golem.Parser.AST` の `Inline` に構築子を一つ加える。

```haskell
data Inline
  = ...
  | -- | ##…## (golem-parser ADR 0011): the source text from the opening
    -- ## to the closing ## or to where it stopped without one
    NumberShorthand Text
```

- 値は、開きの `##` から、閉じの `##` まで（閉じがなければ中身の終わりまで）の原稿の文字列である。`##1##` は `NumberShorthand "##1##"`、`##12年` は `NumberShorthand "##12年"` になる。
- `Located` の位置は、同じ範囲である。
- `Lower` は `NNumberShorthand` の文字列をそのまま入れるだけで、中身を読まず、コマンドの名前も知らない。

`Golem.Parser.AST` に、散文の中の `NumberShorthand` を地の文に戻す純粋な関数を加える。

```haskell
-- | Every ##…## in the inlines, in the prose slots of the commands in
-- them and in their command arguments, as the text it was written with.
shorthandsAsText :: [Located Inline] -> [Located Inline]
```

戻した `Text` は `joinText` で隣の `Text` とつなぐ。
この関数もコマンドの名前を見ない。
どのコマンドに使うかを決めるのは評価である。

### 評価

golem-eval の `evalInline` に、`NumberShorthand` の枝を加える。

- 文字列が、`##` と、`0` か `1` から `9` で始まる ASCII の数字の並びと、`##` からなるとき、その数字の並びを `N` として、`Command "number-text" [Positional (Word N)] []` を同じ位置で評価した結果とする。組み込みの `number-text` を上書きしたプラグインがあれば、そのプラグインが受け取る（[docs/adr/0027](../../adr/0027-exhaustive-command-dispatch-by-types.md)）。糖衣構文が `[number-text N]` と同じ意味であることを、上書きの後も保つためである。
- そうでなければ、G02078 の誤り（「診断」の節）とし、何も組まない。

`Command "number-text"` を作るのは評価であり、`Lower` ではない。
評価はもともと組み込みのコマンドを名前で知っているので、名前を知る箇所は増えない。

### コードの中

コードの散文スロットの中の `NumberShorthand` は、評価の前に `shorthandsAsText` で地の文に戻す。
`[code: ##1##]` は「##1##」と組まれ、`[code: ##1.5##]` も誤りにならずに「##1.5##」と組まれる。

コードの散文スロットとは、次のコマンドの散文スロットである。

- `[code: ...]`
- `[style code: ...]`（`[code: ...]` は、この別名である。[golem-driver ADR 0017](../../golem-driver/adr/0017-pdf-code-blocks.md)）

戻すのは、組み込みのコマンドに渡す前でも、`code` か `style` を上書きしたプラグインに渡す前でも同じとする。
戻す判定は `evalInline` の `Command` の枝の入り口に置き、`code` という名前か、`style` という名前で最初の位置引数が語 `code` であるときに、スロットに `shorthandsAsText` を掛けてから、今の解決（上書き、組み込み、プラグイン）に進む。
スロットの中の入れ子のコマンド（`[code: [strong: ##1##]]`）の中も戻す。

コードブロック（```` ``` ````）と `@listing` の中身は、もともと散文として読まないので、糖衣構文にならない。

文法か `Lower` がコマンドの名前を知る案は採らない（「トレードオフ」）。

### `[numbers]` の `vertical` の値

`style.toml` の `[numbers]` の `vertical` に、二つの値を加える。

| 値 | 縦組みの表記 |
| --- | --- |
| `kanji` | 位取りをする漢数字（今と同じ。既定） |
| `kanji-digits` | 数字を一字ずつ漢数字にする（今と同じ） |
| `tcy` | 算用数字の縦中横（今と同じ） |
| `auto` | 0 以上 99 以下の数は縦中横、ほかは位取りをする漢数字 |
| `auto-digits` | 0 以上 99 以下の数は縦中横、ほかは数字を一字ずつ漢数字にする |

`auto` と `auto-digits` は、本の既定の表記にだけ使える。
`[number-text N style=...]` の `style` の値には加えない。
`style` は一つの数の表記を書き手が選ぶためのものであり、数によって変わる値を選ぶ理由がないからである。

境を「2 桁まで」としたのは、番号付きリストの `{n}` が縦組みで 2 字までの算用数字を縦中横にする規則（docs/specifications.md）とそろえるためである。
負の数は、`auto` で位取りをする漢数字、`auto-digits` で一字ずつの漢数字になる。

`style` 引数を省いた `[number-text ...]`、`##N##`、ページ番号、`{n}` のほかの数の表記など、本の既定の表記を使うすべての数に効く。

**データ構造**：golem-doc の `Golem.Doc.IR` に、本の既定の表記の型と、数から表記を決める関数を加える。

```haskell
-- | The vertical style of the numbers of a book ([numbers] vertical).
data VerticalNumbers
  = VerticalFixed !NumberStyle
  | -- | two digits or fewer in tate-chu-yoko, the others in the style
    VerticalAuto !NumberStyle

verticalStyleOf :: VerticalNumbers -> Integer -> NumberStyle
```

- `NumberStyle` と IR の `Number` は変えない。CBOR とプラグインの ABI も変わらない。
- golem-project の `Numbers` の `vertical` の値の検査に `auto` と `auto-digits` を加える。一覧にない値は今と同じく誤りとする。
- golem-driver の `ceVerticalNumbers`、golem-html、golem-text が `[numbers]` の値から表記を決めている箇所を、`VerticalNumbers` と `verticalStyleOf` に置き換える。

### 診断

評価の段階に G02078 を加える。

| コード | 重大度 | 条件 | メッセージ | 位置 |
| --- | --- | --- | --- | --- |
| G02078 | エラー | コードの外の `##…##` の中身が、先頭が 0 でない ASCII の数字の並び（または `0`）でないか、閉じの `##` がない | `## と ## のあいだには算用数字だけを書きます。本文の ## は \## と書きます` | 糖衣構文の全体（開きの `##` から、閉じか中身の終わりまで） |

G02078 は、02 の区分で草稿の ADR が使う番号（G02070 から G02076）と、草稿の [`**[式]` をキーワード引数と同じ位置に書けるようにする](0013-splat-after-keyword-arguments.md) の G02077 の次である。
並行する草稿が同じ番号を取っていれば、実装の順にずらす。

起草のときの構文の誤り G01025 は使わない。
中身の検査を評価に移したので、構文の段階の新しいコードはない。

### fmt

fmt は `##N##` と `[number-text N]` を互いに書き換えない。
どちらも正しい書き方であり、どちらで書くかは書き手が決める。
fmt の整形の対象（空白、インデント、空行、エスケープ）に記法の選び方は入っていない（[golem-fmt ADR 0001](../../golem-fmt/adr/0001-formatter.md)）。

外してよいエスケープの文字（`removableEscape`）は変えない。
`#` と ASCII の数字は、今も外さない文字に入っているので、`\##1##` のエスケープは外れない。
fmt の AST の比較は、新しい構築子 `NumberShorthand` も文字列ごと比べる。

### lint と LSP

lint の規則は足さない。
`[number-text N]` を `##N##` に書き換えるよう促す規則は好みの問題であり、誤検知の余地のある規則を採らない方針（[golem-lint ADR 0001](../../golem-lint/adr/0001-lint-rules.md)）に合わない。
正規表現スタイルは、コードの外の `##N##` を `[number-text N]` と同じく一字として扱い、コードの中の `##N##` を地の文として扱う。
どちらも評価の結果（`Number` か `Text`）に従うだけで、正規表現スタイルの側に変更は要らない。

G02063 のメッセージは変えない。
`[tcy: 10]` と同じ見た目になるのは `style=tcy` を付けた `[number-text 10 style=tcy]` であり、`##10##` は `[numbers]` の `vertical` が `tcy` か `auto` の本でしか同じにならないからである。

LSP の診断は G02078 を評価の診断として載せる。
補完、ホバー、アウトラインは変えない。
見出しのアウトラインは、今の `[number-text 1]` と同じく、地の文でない要素を原稿から切り出すので、`## 第##1##節` は「第##1##節」と表示される。

### ドキュメント

仕様は実装のときに書く（「メンテナーが決めたこと」）。

- docs/markup.md の「数の表記」に `##N##` の記法、書ける中身、書ける位置、行頭の扱い、コードの中の扱いを書く。「エスケープ」の一覧に「`##` の直後に ASCII の数字が続く位置の `#`」を加える。「縦中横」の「数を縦中横にする場合は」の文に、本の既定が `tcy` か `auto` なら `##10##` でもよいことを書く。この ADR へリンクする。
- docs/specifications.md の `[numbers]` の説明に `auto` と `auto-digits` を加え、この ADR へリンクする。
- docs/diagnostics.md に G02078 の節を足す。「主な原因」には、全角の数字、小数点、桁区切り、先頭の 0、閉じの `##` の書き忘れを挙げる。「直し方」には、算用数字に直す、`[number-text ...]` か地の文で書く、`\##` とエスケープする、の三つを書く。
- [ADR 0003](0003-block-grammar.md) のステータスの行の値に「行頭の数の開きは [ADR 0011](0011-number-shorthand.md)」を加える。
- [ADR 0004](0004-inline-grammar.md) のステータスの行の値に「数の糖衣構文は [ADR 0011](0011-number-shorthand.md)」を加える（今の値が「採択」だけなら「採択→」に続けて書く）。
- [golem-eval ADR 0003](../../golem-eval/adr/0003-evaluation-diagnostic-codes.md) のステータスの行の末尾に、「、G02078 は [golem-parser ADR 0011](0011-number-shorthand.md)」を加える。
- 利用者のマニュアル（`manual/`）を次のように直す（[docs/adr/0024](../../adr/0024-manual-audiences-and-policy.md)）。
  - `manual/chapters/03-markup.gm` の「数と式」の節で、`##10##` を数の書き方の第一の例にし、`[number-text 10 style=kanji]` を個別に表記を選ぶ書き方として続ける。コードの中では糖衣構文にならないことを書く。「コメントとエスケープ」の節の一覧に `\##` を加える。
  - `manual/chapters/05-style.gm` の `[numbers]` の説明に `auto` と `auto-digits` を加える。正規表現スタイルの注意（`[number-text ...]` の数は一字として扱う）に、`##…##` の数も同じであることを書く。
  - `manual/appendices/a-markup.gm` に `##数##` の項を `[number-text 数]` の項の前に足す。「コメントとエスケープ」の節の一覧に `\##` を加える。
  - 付録C（`manual/appendices/c-style.gm`）の `[numbers]` の `vertical` の値に `auto` と `auto-digits` を加える。
  - `manual/appendices/e-errors.gm` に G02078 の項を足す。

## 実装しないこと

- 表記を選ぶ引数を糖衣構文に持たせること（`##36:tcy##` のような形）。一つの数の表記を選ぶときは `[number-text ...]` を使う。
- 段落や文字スタイルごとに、数の既定の表記を変える設定。今の既定は本の `[numbers]` の `vertical` だけである。
- `[number-text ...]` の `style` に `auto` と `auto-digits` を加えること。
- 負の数、小数、桁区切り、全角の数字、先頭の 0 を糖衣構文で書けるようにすること。
- 全角の数字や符号で始まる `##…##` を、書き誤りとして知らせること。
- 式を糖衣構文の中に書くこと。計算した数は `[number-text [= x]]` と書く。
- 文法か `Lower` に、コードの散文スロットを見分けさせること。
- `code` の文字スタイルを付けるほかの手段（正規表現スタイル、段落スタイル）の中で、糖衣構文を地の文に戻すこと。散文スロットを持つコマンドの名前だけで決める。
- 全角の `＃＃` を記法にすること。
- 既存の `[number-text N]` を `##N##` に書き換える移行の道具。
- アウトラインで数を表記に直して表示すること。
- G02063 のメッセージを、本の `[numbers]` に応じて `##10##` を案内する形に変えること。メッセージが `style.toml` に依存するようになるからである。

## テスト設計

### 先に書いて失敗させるテスト

`modules/golem-parser/test/ParserSpec.hs`：

- `本文##12##本文` が、`Text`、`NNumberShorthand`、`Text` の三つになり、CST を文字列に戻すと入力に一致すること。
- `##1##年` の一行が段落になり、G01010 を出さないこと。段落の先頭が `NNumberShorthand` であること。
- `## 第##1##節` が二階層めの見出しで、題に `NNumberShorthand` があること。
- `###1##` と `#1` が今と同じく G01010 になること。`#### x` が今と同じく G01012 になること。
- `##0##`、`##007##`、`##1.5##`、`##1,000##`、`##1 2##`、`##12年`（閉じなし）が、どれも構文の診断を出さずに `NNumberShorthand` になること。`##12年` は閉じの `KNumberMark` を持たないこと。
- `##12|x` を含む表のセルで、中身が `|` の手前で止まり、セルの区切りが今と同じく読まれること。`[ruby: ##12|じゅうに]` も同じであること。
- `C##`、`##]`、`####`、`##見出し##`、`##１２##`、`##-3##`、`\##1##` が地の文（とエスケープ）だけになること。
- `- ##1##つ目`、`= ##1##`、`| ##1## | a |` の表、`[ruby: ##12##|じゅうに]`、`[note: ##1##]`、`[code: ##1##]` で、それぞれ `NNumberShorthand` ができること。
- `[number-text ##1##]` の引数が語 `##1##` であること。`[= "##1##"]`、`%% ##1## %%`、コードブロックの中の `##1##` に `NNumberShorthand` ができないこと。

`modules/golem-parser/test/LowerSpec.hs`：

- `##36##` の AST が `NumberShorthand "##36##"` であり、位置が 6 バイトであること。
- `##12年` の AST が `NumberShorthand "##12年"` であること。
- `shorthandsAsText` が、`a`、`NumberShorthand "##1##"`、`b` を一つの `Text "a##1##b"` に戻し、入れ子のコマンドのスロットの中も戻すこと。

`modules/golem-eval/test`：

- 任意の 0 以上の整数 N と、横組みと縦組み、`[numbers]` の `vertical` の五つの値の組で、`##N##` と `[number-text N]` の評価の結果の IR が、位置を除いて一致すること（プロパティテスト）。
- `##007##`、`##1.5##`、`##1,000##`、`##1 2##`、`##12年` が、それぞれ G02078 を一つだけ出し、位置が糖衣構文の全体であること。
- `[code: ##1##]` が `CharStyle "code" [Text "##1##"]` になること。`[code: ##1.5##]` と `[code: [strong: ##12年]]` が G02078 を出さないこと。`[style code: ##1##]` も地の文になること。`[style note: ##1##]` は `Number` になること。
- `code` を上書きするプラグインが、スロットの `##1##` を地の文として受け取ること。`number-text` を上書きするプラグインが、`##1##` の呼び出しを受け取ること。
- `[ruby: 第##1##|だいいち]` の親文字に `Number` が入ること。`[ruby: 一|##1##]` が今の `[ruby: 一|[number-text 1]]` と同じく G02043 になること。
- `[tcy: ##10##]` が `[tcy: [number-text 10]]` と同じく G02040 になること。

`modules/golem-doc/test`：

- `verticalStyleOf` が、`VerticalAuto StyleKanji` で 0、9、10、99 を `StyleTcy` に、100、-1 を `StyleKanji` にすること。`VerticalAuto StyleKanjiDigits` で 100 を `StyleKanjiDigits` にすること。`VerticalFixed s` がどの数でも `s` を返すこと。

`modules/golem-project/test/Main.hs`：

- `[numbers] vertical = "auto"` と `"auto-digits"` を読めること。`"automatic"` が今と同じく誤りになること。

`modules/golem-layout/test/Main.hs`、`modules/golem-html/test`、`modules/golem-text/test/Main.hs`：

- `vertical = "auto"` の縦組みの本で、`##9##` と `##99##` が縦中横、`##100##` が「百」に組まれること。`auto-digits` で `##100##` が「一〇〇」になること。
- 横組みの本では、`auto` でも算用数字になること。

`modules/golem-fmt/test`：

- `##36##` と `[number-text 36]` が整形で変わらないこと。
- `\##1##` のエスケープが外れないこと。
- 整形の前後の AST の比較と冪等性のプロパティテストの生成器に、`##N##` と `\##N##` を加えること。

`modules/golem-driver/test/Main.hs`：

- G02078 が docs/diagnostics.md に状態「使用中」で載っていることを、今のテストが確かめること（節を足す前に失敗する）。

`modules/golem-cli/test/Main.hs`：

- `##1.5##` を含む原稿で、`golem check` が `error[G02078]` を出し、終了コードが 1 であること。

### 自動テストにしない確かめ方

マニュアルの「数と式」の節の `##10##` の例を、横組みの PDF と HTML、縦組みのプレーンテキストに組み、横組みで「10」、縦組みで `[numbers]` の表記になっていることを目で確かめる。
`vertical = "auto"` にした縦組みの fixture を組み、2 桁までの数が縦中横に、3 桁の数が漢数字になっていることを目で確かめる。
マニュアルの全体を組んだ PDF と HTML のバイト列が、この変更の前後で、例を加えた箇所を除いて変わらないことを確かめる。

## トレードオフ

糖衣構文は、数を一度だけ書いて書字方向ごとに表記を決める、という `Number` の使い方を短くする。
`[number-text 10]` の 16 字が `##10##` の 6 字になり、算用数字をそのまま書く書き方との差が小さくなる。
代わりに、記法の文字が一つ増え、行の途中の `##` が条件つきで特別な意味を持つ。

数の開きを「`##` の直後が ASCII の数字」に限ったのは、今の原稿の地の文の `##` を記法にしないためである。
起草のときは、全角の数字、符号、小数点までを開きに含め、`##１２##` や `##-3##` を書き誤りとして知らせる案だった。
中身を ASCII の数字に限ったので、開きも同じ範囲にそろえ、記法になる文字の組を最小にした。
その代わりに、`##１２##` や `##-3##` は黙って地の文として組まれる。

中身の検査を文法から評価に移した。
文法で検査すると、`[code: ##1.5##]` のようなコードの中の誤りも構文の誤りになるが、文法はコードの中かどうかを知らない。
評価なら、コードの中では検査せずに地の文に戻せる。
代わりに、`##1.5##` の誤りは構文の段階ではなく評価の段階で出る。
構文の誤りのあるファイルは評価されないので、構文の誤りと G02078 は同時には出ない。

AST に専用の構築子 `NumberShorthand` を足したので、`Lower` も文法もコマンドの名前を知らずに済む。
起草のときは `##N##` を `Command "number-text"` に下ろし、評価、正規表現スタイル、プラグインの上書き、LSP、`golem inspect` が糖衣構文を知らずに済む形にしていた。
その形では、[ADR 0004](0004-inline-grammar.md) と [ADR 0010](0010-ruby-slash-escape-and-table-cell-breaks.md) の「文法と `Lower` はコマンドの名前を知らない」という分け方に例外ができる。
専用の構築子にすると、評価、fmt の AST の比較、`golem inspect` の AST の表示が構築子を一つ多く扱う。
評価は `NumberShorthand` を `[number-text N]` の評価に回すだけなので、意味の一致は一か所で保たれる。

コードの中で糖衣構文を認めない仕組みとして、文法の散文スロットに種類を設ける案もある。
`[code: ...]` のスロットを、糖衣構文を読まない別のスロットとして読む形である。
これは文法がコマンドの名前 `code` を知ることになり、`Lower` に名前を覚えさせない、という決定と同じ理由で採らない。
評価はもともとコマンドの名前で振る舞いを分けているので、コードの散文スロットを地の文に戻すのも評価に置く。
文法が `[code: ...]` の中でも `NumberShorthand` を作るのは、その結果である。
`NumberShorthand` は原稿の文字列を持つので、地の文に戻しても字は一つも変わらない。

コードの中で地の文に戻すのを、`[code: ...]` と `[style code: ...]` に限った。
`code` の文字スタイルを正規表現スタイルや段落スタイルで付けた文字は、評価の時点ではまだ文字スタイルが決まっていないので、見分けられない。
コードを書く場所は `[code: ...]` かコードブロックである、という書き方の約束で足りると考える。

`[numbers]` の `vertical` に `auto` を足すと、`##N##` で書ける数が増える。
年号のように「二〇二四」と書きたい数と、日付のように縦中横で書きたい 2 桁の数が混ざる本では、`auto-digits` を既定にすれば、どちらも糖衣構文で書ける。
「十月」のように位取りで書きたい数と「二〇二四」が混ざる本では、今と同じく一方を `[number-text ...]` で書く。

行の途中の `##1##` の意味が変わるのは、今の原稿に対する非互換の変更である。
リポジトリの原稿には該当箇所がなく、v0.1.0 はまだプレリリースなので、廃止予定の段階（docs/diagnostics.md の手順）を踏まずに変える。
リリースノートの「変更」に、`##` の直後に数字の続く地の文は `\##` と書く必要があることを書く。

## 参考文献

- docs/markup.md の「エスケープ」「見出し」「縦中横」「数の表記」
- [golem-eval ADR 0001](../../golem-eval/adr/0001-expression-language-and-numerics.md)「式の言語と数の規則」
- [golem-layout ADR 0002](../../golem-layout/adr/0002-japanese-composition.md)「日本語組版の規則」の「縦中横」「Number の解決」
- [golem-syntax ADR 0002](../../golem-syntax/adr/0002-notice-severity.md)「重大度のお知らせ（notice）」の G02063
- [docs/adr/0027](../../adr/0027-exhaustive-command-dispatch-by-types.md)「到達しない診断の分岐を型で除く」
- W3C, "Requirements for Japanese Text Layout"（JLReq）, W3C Group Note の縦中横の節（縦組みの中の数字の扱い）
