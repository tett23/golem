# ADR 0008: コマンドと式の空白と残りの記号にも semantic tokens を付ける

ステータス: 採択

## 文脈

[golem-lsp ADR 0007](0007-semantic-tokens-for-command-punctuation.md) は、インラインのコマンドの `[`、`:`、`]` と式の記号に `operator` を付け、「コマンドと式の中では、散文スロットの中身を除くすべての文字がどれかのトークンに入る」とした。
Golem のエディタの Aleph（https://github.com/tett23/aleph）が、コマンドと式を等幅にする範囲を semantic tokens の型だけで決められるようにするためである（[tett23/aleph ADR 0009](https://github.com/tett23/aleph/blob/54fa4e136989fda6fe122ef4ae866ebb1c85247d/docs/adr/0009-lsp-and-formatting.md)）。

ところが、実装した #618 の後も、この文は成り立っていない。
#618 の説明は、空白、キーワード引数の `=`、`*[` と `**[`、ハッシュのキーの名前が残ると書き、仕様書もそれらにトークンを付けないと明記した。
本人から、空白や `=` にもトークンを付ける ADR を求められた（2026-11-07）。

### 残っている箇所

origin/main（89bbc555）の `Golem.Lsp.Features` の `semanticTokens` に、`cabal repl` で原稿を一行ずつ渡し、CST のトークンごとに、重なる semantic tokens があるかを調べた（2026-11-07）。
トークンのない CST のトークンのうち、親のノードがコマンドか式のもの（散文スロットの中身、改行、`KError` を除く）は、次のとおりだった。
列は UTF-8 のバイトで数える。

| 原稿 | トークンのない箇所 | CST |
| --- | --- | --- |
| `[figure a.png alt="図" width=10]` | 列 7、13、23 の空白、列 17 と 29 の `=` | `NInlineCommand` の `KWhitespace`、`NKeywordArgument` の `KEquals` |
| `[ruby 漢字: かんじ]` | 名前の後の空白（列 5）と、`:` の後の空白（列 13） | `NInlineCommand` の `KWhitespace` |
| `[strong: 強 \| 弱 ]` | `:` の後（列 8）と `\|` の後（列 14）の空白 | `NInlineCommand` の `KWhitespace` |
| `[= [1, 2] + (3 * 4)]` | `[=` の後と、`,`、`+`、`*` の前後の空白 | `NExpr`、`NArrayExpr`、`NBinaryExpr` の `KWhitespace` |
| `[x *[a.b] **[f(1)]]` | `*[`、`**[`、`.`、`(`、`)`、二つの閉じの `]`、引数の前の空白 | `NSplatArgument` の `KStar` と `KRBracket`、`NVarExpr` の `KDot`、`NCallExpr` の `KLParen` と `KRParen` |
| `[= {a: 1, "b": 2}]` | キーの `a`、空白 | `NHashEntry` の `KIdent`、`NExpr` と `NHashEntry` と `NHashExpr` の `KWhitespace` |
| `@figure a.png alt="図"` | 列 7、13 の空白、`=` | `NBlockCommand` の `KWhitespace`、`NKeywordArgument` の `KEquals` |
| `@set f = g(1, [2])` | 名前の `f`、`=`、`(`、`,`、`[`、`]`、`)`、空白 | `NBlockCommand` の `KIdent` と `KEquals`、`NCallExpr` と `NArrayExpr` の記号 |
| `@label intro␣␣`（行末に空白が二つ） | 列 7 の前の空白と、行末の空白 | `NBlockCommand` の `KWhitespace` |

`*[...]` の中と `@set` の `=` の後の式は、記号にトークンがない。
[golem-lsp ADR 0007](0007-semantic-tokens-for-command-punctuation.md) の実装は、式の記号を `NExpr` の下でだけ `operator` にする（[Features.hs#L943](https://github.com/tett23/golem/blob/89bbc5556e7f1a1368ffe4b27e492b38002e3496/modules/golem-lsp/src/Golem/Lsp/Features.hs#L943)、[Features.hs#L991-L995](https://github.com/tett23/golem/blob/89bbc5556e7f1a1368ffe4b27e492b38002e3496/modules/golem-lsp/src/Golem/Lsp/Features.hs#L991-L995)）。
CST の `NExpr` は `[= ...]`（文法の `ExprCtx`）だけから作られ（[Convert.hs#L26](https://github.com/tett23/golem/blob/89bbc5556e7f1a1368ffe4b27e492b38002e3496/modules/golem-parser/src/Golem/Parser/Convert.hs#L26)）、`SplatArgument` と `@set` は式の本体（`ExprBody`）を `NExpr` で包まずに持つ（[Golem.hpeg#L364-L367](https://github.com/tett23/golem/blob/89bbc5556e7f1a1368ffe4b27e492b38002e3496/modules/golem-parser/grammar/Golem.hpeg#L364-L367)、[Golem.hpeg#L577](https://github.com/tett23/golem/blob/89bbc5556e7f1a1368ffe4b27e492b38002e3496/modules/golem-parser/grammar/Golem.hpeg#L577)）。
`@set` の名前（文法の `SetName`）は `KIdent` だが、`tokenType` はブロックのコマンドの二つ目の `KIdent` に型を返さない（[Features.hs#L962-L964](https://github.com/tett23/golem/blob/89bbc5556e7f1a1368ffe4b27e492b38002e3496/modules/golem-lsp/src/Golem/Lsp/Features.hs#L962-L964)）。
キーワード引数の名前は、`NKeywordArgument` の最初の `KWord` として `parameter` になっている（[Features.hs#L969](https://github.com/tett23/golem/blob/89bbc5556e7f1a1368ffe4b27e492b38002e3496/modules/golem-lsp/src/Golem/Lsp/Features.hs#L969)）。

コマンドの外にも、型のないものが一つあった。
定義リストの `=:`（`NDefNew` の `KNewDefMark`）である。
[golem-lsp ADR 0006](0006-semantic-tokens-highlighting.md) は「リストと定義リストの印」を `keyword` としたが、表に挙げたのは `NDefTerm` の `=` だけで、`=:` はどの型にも当たらない。

### 空白の CST

空白は、文法の `Ws` と `Ind` から作る `KWhitespace` である（[Convert.hs#L72-L73](https://github.com/tett23/golem/blob/89bbc5556e7f1a1368ffe4b27e492b38002e3496/modules/golem-parser/src/Golem/Parser/Convert.hs#L72-L73)）。
親のノードで、コマンドの空白と散文の空白を分けられる。

- インラインのコマンドの `:` と `|` の後の空白は、文法の `Sp`（[Golem.hpeg#L386](https://github.com/tett23/golem/blob/89bbc5556e7f1a1368ffe4b27e492b38002e3496/modules/golem-parser/grammar/Golem.hpeg#L386)）なので、親は `NInlineCommand` である。
- 散文スロットの中の空白と、`|` と `]` の前の空白は、散文スロットの文字（`SlotText`、`KText`）に含まれる。上の `[strong: 強 | 弱 ]` の `強 ` と `弱 ` がそうである。
- コマンドとコマンドのあいだの空白（`[a] [b]` の列 3）は、地の文の `KText` である。
- ブロックのコマンドの行頭の字下げ（`@box` の本体の中の `  @label x`）は、内側の `NBlockCommand` の最初の子の `KWhitespace` である。段落の行頭の字下げは、`NParagraph` の `KWhitespace` である。
- 見出しの `#`、リストの `-` と `+`、定義リストの `=` の後の空白は、`NHeading`、`NListItem`、`NDefTerm` の `KWhitespace` である。
- 字下げが 0 の行の `Ind` は幅 0 の `KWhitespace` になる。`placeTokens` は長さ 0 の部分を捨てる（[Features.hs#L915-L930](https://github.com/tett23/golem/blob/89bbc5556e7f1a1368ffe4b27e492b38002e3496/modules/golem-lsp/src/Golem/Lsp/Features.hs#L915-L930)）。

コマンドと式の中の空白は、改行を含まない。
引数と式の空白は `Ws`（`[ \t]+`）だけで、改行の入る `[x\n  y: 散文]` と `[= a +\n  b]` は、改行から後が `KError` になった。
改行がコマンドの中に入るのは、散文スロットの続きの行だけである。

### LSP 3.17 と、クライアントの振る舞い

LSP 3.17 の semantic tokens（https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_semanticTokens）は、トークンを、行、列、長さ、型、修飾子で表す範囲とする。
範囲の中身が空白かどうかの決まりはない。
型は標準の 23 種のほかに、クライアントが拡張して能力で知らせてよいとする。
行をまたぐトークンはクライアントの `multilineTokenSupport` に、重なるトークンは `overlappingTokenSupport` に従う。
Golem は、改行をまたぐトークンを行ごとに分け、重なるトークンを作らない（[golem-lsp ADR 0006](0006-semantic-tokens-highlighting.md)）ので、どちらの能力にも頼らない。
空白のトークンは改行を含まず、別の CST のトークンとも重ならないので、この扱いは変わらない。

型の凡例は `lsp` 2.8.0.0 が決める。
`inferServerCapabilities` は、`semanticTokensProvider` の凡例に `defaultSemanticTokensLegend` を必ず入れ、ソースに「利用者が凡例を与えられるようにする」という TODO がある（cabal が取得済みの tarball の `Language.LSP.Server.Processing`）。
独自の型を使うには、[`rewriteInitializeResponse`](https://github.com/tett23/golem/blob/89bbc5556e7f1a1368ffe4b27e492b38002e3496/modules/golem-lsp/src/Golem/Lsp/Server.hs#L120-L121) で凡例を書き換え、応答を作る `makeSemanticTokens` にも同じ凡例を渡す必要がある（[Server.hs#L200](https://github.com/tett23/golem/blob/89bbc5556e7f1a1368ffe4b27e492b38002e3496/modules/golem-lsp/src/Golem/Lsp/Server.hs#L200)）。

Neovim 0.12.6 の `runtime/lua/vim/lsp/semantic_tokens.lua` は、トークンの範囲に `@lsp.type.<型>.<ファイルタイプ>` のハイライトの extmark を置く。
範囲の中身が空白かどうかは見ない。
クライアントの能力では、標準の 23 種の型と、`overlappingTokenSupport` と `multilineTokenSupport` を知らせる（`runtime/lua/vim/lsp/protocol.lua`）。
空白に前景の色を付けても見えないが、テーマがその型に背景や下線を付けていれば、空白にも出る。
VS Code の振る舞いは確かめていない。

Aleph は、凡例で型の名前を引き、`classOf` で型を描き分けの分類に直す（[app/lsp/protocol.ts#L60-L69](https://github.com/tett23/aleph/blob/54fa4e136989fda6fe122ef4ae866ebb1c85247d/app/lsp/protocol.ts#L60-L69)）。
`keyword`、`function`、`decorator`、`operator` はコマンドの分類、`string`、`number`、`variable`、`parameter`、`property` などは式の分類になり、どちらも等幅で描く。
知らない型は分類が `null` になり、描き分けに使われない。

## 実装すること

`Golem.Lsp.Features` の `classifyIn` と `tokenType` を、次のように改める。

### 空白

- 親のノードがコマンドか式のノードである `KWhitespace` に、`operator` を付ける。
  コマンドのノードは `NInlineCommand`、`NBlockCommand`、`NArgument`、`NKeywordArgument`、`NSplatArgument`、式のノードは `NExpr`、`NBinaryExpr`、`NUnaryExpr`、`NCallExpr`、`NLiteral`、`NVarExpr`、`NArrayExpr`、`NHashExpr`、`NHashEntry`、`NParenExpr`、`NRangeExpr` である。
- 行頭の字下げ（`NBlockCommand` の最初の子の `KWhitespace`）には付けない。段落の字下げと同じく、行の構造の一部として扱う。
- ブロックのコマンドの行末の空白（`@label intro␣␣` の末尾）には付ける。
- 散文スロットの中、地の文、見出し、リスト、定義リスト、表の空白には、今と同じく付けない。
- 修飾子は付けない。

### 記号と名前

- キーワード引数の `=`（`NKeywordArgument` の `KEquals`）と、`@set` の `=`（`NBlockCommand` の `KEquals`）に `operator` を付ける。
- `*[` と `**[`（`NSplatArgument` の `KStar`）と、その閉じの `]`（`NSplatArgument` の `KRBracket`）に `operator` を付ける。
- 式の記号を `operator` にする範囲を、`NExpr` の下から、`NExpr` と `NSplatArgument` と上の式のノードの下に広げる。これで、`*[...]` の中と `@set` の式の `.`、括弧、`,`、`:`、`[`、`]`、`{`、`}` にも付く。散文スロットとその中のコマンドを除く決まりは変えない。
- ハッシュのキーの名前（`NHashEntry` の `KIdent`）に `property` を付ける。文字列のキー（`{"b": 2}` の `"b"`）は、今と同じ `string` とする。
- `@set` の名前（`NBlockCommand` の、`set` の後の `KIdent`）に、`variable` と修飾子 `declaration` を付ける。
- 定義リストの `=:`（`KNewDefMark`）に `keyword` を付ける。

これで、コマンドと式の中では、散文スロットの中身、行頭の字下げ、改行、構文エラーの箇所（`KError`）を除くすべての文字が、どれかのトークンに入る。
凡例は `defaultSemanticTokensLegend` のままとし、独自の型は足さない。

### 文書

- 仕様書の LSP の節の型の表に、空白（`operator`）、キーワード引数と `@set` の `=`、`*[` と `**[` とその閉じの `]`（`operator`）、ハッシュのキーの名前（`property`）、`@set` の名前（`variable` と `declaration`）、`=:`（`keyword`）を足し、「キーワード引数の `=`、……、空白には、トークンを付けない」の文を、付けない箇所（散文スロットの中身、行頭の字下げ、改行、構文エラー）の文に改める。
- `tools/editors/README.md` の型の表に `property` の行を足し、semantic tokens との違いの一覧に、この ADR で付けたトークンを足す。TextMate と tree-sitter の文法は改めない。

## 実装しないこと

- 散文スロットの中身、地の文、見出しやリストの印の後の空白へのトークン。散文スロットの中の空白は散文の一部であり、Aleph では本文のフォントで描く。
- 改行と行頭の字下げへのトークン。
- 構文エラーの箇所（`KError`）へのトークン。`[x\n  y: 散文]` のように、コマンドの途中から後が `KError` になる原稿では、等幅の範囲はそこで切れる。
- 段落の強制改行の `\`（`NHardBreak` の `KBackslash`）へのトークン。地の文の中の記号で、コマンドでも式でもない。
- 独自の型と修飾子、凡例の書き換え。
- 隣り合う同じ型のトークンを一つにまとめること。トークンは CST のトークンに一つずつ対応させる。
- TextMate と tree-sitter の文法の変更。
- Aleph の変更。等幅の範囲を、今の「トークンの範囲と Aleph 自身の字句の読み方の和」から、トークンだけに改めるかは、Aleph が決める。

## テスト設計

先に次のテストを `modules/golem-lsp/test/SemanticTokensSpec.hs` に書き、main で失敗することを確かめてから実装する。

- 純粋な関数のテスト（`semanticTokens`、UTF-8）。
  - `[figure a.png alt="図" width=10]`：列 7、13、23 の空白（長さ 1）と、列 17、29 の `=` が `operator` であること。
  - `[ruby 漢字: かんじ]`：列 5 と列 13 の空白が `operator` で、`かんじ` にトークンがないこと。
  - `[strong: 強 | 弱 ]`：列 8 と列 14 の空白が `operator` で、`強 ` と `弱 `（後ろの空白を含む散文スロットの文字）にトークンがないこと。
  - `[x *[a.b] **[f(1)]]`：`*[`（長さ 2）、`**[`（長さ 3）、`.`、`(`、`)`、二つの閉じの `]`、列 2 と 9 の空白が `operator` であること。
  - `[= {a: 1, "b": 2}]`：`a` が `property`、`"b"` が `string` で、列 2、6、9、14 の空白が `operator` であること。
  - `@set x = 1 + y.z`：`x` が `variable` と `declaration`、`=` と `.` と列 4、6、8、10、12 の空白が `operator` であること。
  - `@box\n  @label x\n  本文\n`：2 行目の字下げ（列 0 から 2）と 3 行目の字下げにトークンがなく、2 行目の列 8 の空白が `operator` であること。
  - `@label intro  \n`：列 6 の空白と、列 12 からの長さ 2 の空白が `operator` であること。
  - `[a] [b]` の列 3 の空白、`# 見出し`、`- a`、`= 用語` の印の後の空白にトークンがないこと。
  - `= 用語\n  定義\n=:\n  別\n` の `=:` が `keyword` であること。
- hedgehog の性質のテスト（`genText` で生成した原稿）。
  - 今の性質（文書の順に並び、重ならず、長さが正で、`defaultSemanticTokensLegend` で `makeSemanticTokens` が `Left` にならない）がそのまま成り立つこと。
  - 親のノードがコマンドか式のノードである CST のトークンのうち、散文スロットの中、行頭の字下げ、改行、`KError` を除くすべてのバイトが、どれかの semantic tokens に入ること。[golem-lsp ADR 0007](0007-semantic-tokens-for-command-punctuation.md) の「すべての文字がどれかのトークンに入る」を、例ではなく性質として確かめる。
- 今のテストの期待値（[golem-lsp ADR 0007](0007-semantic-tokens-for-command-punctuation.md) の行と、`runGolemLspWithHandles` の応答の数の列）を、増えたトークンに合わせて改める。

自動のテストにしにくい次のことは、実装の後に手で確かめる。

- [golem-lsp ADR 0005](0005-keystroke-latency-and-ordered-evaluation.md) のキー入力の測り方（`nvim --headless --listen` に RPC の `nvim_input` で日本語を 200ms の間隔で送り、`TextChangedI` と `TextChangedP` の時刻から送った時刻を引く）で、`manual/` の写しの `chapters/09-editor.gm` と `chapters/05-style.gm` に、日本語を 54 文字ずつ送る。取りこぼしがなく、最大が 16ms 未満であること。`:messages` が空であること。
- 同じ Neovim で、`vim.lsp.semantic_tokens.get_at_pos()` が、`chapters/03-markup.gm` の `[ruby ...]` の名前の後の空白で `operator` を、キーワード引数の `=` で `operator` を返すこと。
- 本人が確かめる：Ghostty の Neovim の本人のテーマで、コマンドの中の空白に背景や下線が出ないこと。

## トレードオフ

- トークンが増える。上の調べ方で、増えるトークンの数を数えた（行頭の字下げを除く）。`chapters/09-editor.gm`（9,875 バイト）は 286 から 353 に、`chapters/05-style.gm`（61,017 バイト）は 2,929 から 3,643 に、どちらも 2 割強増える。増える分のほとんどは空白で、`05-style.gm` では 714 のうち 675 だった。応答が大きくなり、Neovim がハイライトに直す仕事も増える。[golem-lsp ADR 0005](0005-keystroke-latency-and-ordered-evaluation.md) のキー入力の目標を守るかは、テスト設計の手順で測って確かめる。
- 空白を `operator` と呼ぶのは、型の名前と合わない。Neovim の `:Inspect` のようにトークンの型を示す道具は、空白を演算子と示すことになる。[golem-lsp ADR 0006](0006-semantic-tokens-highlighting.md) が見出しの文字を `namespace` と呼んだのと同じく、標準の型を借りる代わりに、エディタの設定なしに動くことを選ぶ。
- `@lsp.type.operator` に背景や下線を付けるテーマでは、コマンドの中の空白にも背景や下線が出る。
- 独自の型にしないので、クライアントは型だけでは空白と演算子を区別できない。区別したいクライアントは、トークンの範囲の文字を見る必要がある。
- `@set` の名前に `declaration` を付けるので、`.gm` で `modification` のほかの修飾子を使うのはこれが初めてになる。`.emet` の宣言の名前（[docs/adr/0170](../../adr/0170-emet-editor-support.md)）と同じ修飾子である。
- TextMate と tree-sitter の文法との違いが広がる。LSP が動き出すまでのあいだ、空白と `=` などは色の分類が違う。空白は色が見えないので、違いが目に見えるのは `=`、`*[`、ハッシュのキー、`@set` の名前である。

## メンテナーが決めること

1. **空白の型**：推奨は `operator`。Aleph の `classOf` はすでに `operator` をコマンドの分類にするので、Aleph を変えずに等幅の範囲に入る。却下した案と理由は次のとおり。
   - 独自の型（`whitespace` など）：`lsp` 2.8.0.0 は凡例を固定するので、初期化の応答の凡例と `makeSemanticTokens` の凡例の両方を書き換える必要がある。Aleph の `classOf` は知らない型を捨てるので、Aleph も変える必要がある。[golem-lsp ADR 0006](0006-semantic-tokens-highlighting.md) と [golem-lsp ADR 0007](0007-semantic-tokens-for-command-punctuation.md) の、標準の型だけを使う決まりも破る。得られるのは型の名前が合うことと、テーマの `@operator` の背景が空白に出ないことだけである。
   - 修飾子で空白を示す：修飾子は型に付くものなので、型を選ぶ問題は残る。標準の修飾子に空白に当たるものはなく、独自の修飾子には独自の型と同じ凡例の問題がある。
   - トークンを付けず、Aleph がトークンのあいだの空白を埋める：`[a] [b]` の列 3 の空白は地の文だが、両隣がコマンドのトークンなので、埋めると等幅になる。どの空白がコマンドに属するかは CST が知っているので、Aleph に文法の知識を持たせることになる。
   - 隣のトークンを空白の分だけ広げる：`[ruby 漢字` の `ruby` の `function` が空白を含むようになり、トークンの範囲と名前の範囲がずれる。どちらの隣に含めるかの規則も要る。
   - ほかの標準の型（`keyword`、`string` など）：`keyword` は `[=` や見出しの `#` と、`string` は引数の値と同じ分類になり、Aleph の描き分けや色が変わる。`operator` はすでにコマンドの括弧と `:` に使っており、空白はそれらと同じ「コマンドの組み立ての部分」として扱える。
2. **空白の範囲**：推奨は、親のノードがコマンドか式のノードの空白で、行頭の字下げを除き、行末の空白を含めること。行頭の字下げも含めると、Aleph では本体の中のブロックのコマンドの字下げが等幅になり、同じ深さの段落の字下げ（トークンなし）と幅がそろわない。行末の空白を除くと、「行末かどうか」の規則が一つ増える一方で、見た目は変わらない。
3. **ハッシュのキーの型**：推奨は `property`。ハッシュは `@set` の値などで記録として使い、キーはその項目の名前である。却下した案は `parameter`（キーワード引数の名前と同じ型にする）。`**[h]` で渡すとハッシュのキーがキーワード引数の名前になるが、ハッシュはそのほかの場所でも使い、そこでは引数ではない。Aleph の `classOf` は `property` も式の分類にするので、どちらでも等幅になる。
4. **`@set` の名前の型**：推奨は `variable` と修飾子 `declaration`。式の中で同じ名前を参照するところが `variable` なので、宣言の箇所を修飾子で区別する。`.emet` の宣言の名前と同じ扱いである。代案は修飾子のない `variable` で、[golem-lsp ADR 0006](0006-semantic-tokens-highlighting.md) の「修飾子は `modification` のほかは使わない」を保てる。
5. **`=` と `*[` の型**：推奨は、キーワード引数と `@set` の `=`、`*[` と `**[` とその閉じの `]` をすべて `operator` にすること。`keyword` にする案は、定義リストの `=`（ブロックの印）と `[=`（式の始まり）が `keyword` なので一見そろうが、キーワード引数の `=` は名前と値をつなぐ記号で、インラインのコマンドの `:` と `|`（`operator`）に近い。
6. **`=:` を含めるか**：推奨は、この ADR で `keyword` を付けること。コマンドでも空白でもないが、[golem-lsp ADR 0006](0006-semantic-tokens-highlighting.md) の「リストと定義リストの印」の表から漏れたもので、型を一つ足すだけで済む。代案はこの ADR から外し、別の ADR にすること。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-07、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [golem-lsp ADR 0005](0005-keystroke-latency-and-ordered-evaluation.md)
- [golem-lsp ADR 0006](0006-semantic-tokens-highlighting.md)
- [golem-lsp ADR 0007](0007-semantic-tokens-for-command-punctuation.md)
- tett23/golem のプルリクエスト #618（コマンドの括弧と式の記号へのトークン）：https://github.com/tett23/golem/pull/618
- Language Server Protocol Specification 3.17、Semantic Tokens：https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_semanticTokens
- `lsp` 2.8.0.0 の `Language.LSP.Server.Processing`（`inferServerCapabilities`）と、`lsp-types` 2.4.0.0 の `SemanticTokenTypes`（`SemanticTokenTypes_Custom`）。cabal が取得済みの tarball で読んだ。
- Neovim 0.12.6 の `runtime/lua/vim/lsp/semantic_tokens.lua` と `runtime/lua/vim/lsp/protocol.lua`
- tett23/aleph の [ADR 0006](https://github.com/tett23/aleph/blob/54fa4e136989fda6fe122ef4ae866ebb1c85247d/docs/adr/0006-horizontal-editor.md)、[ADR 0009](https://github.com/tett23/aleph/blob/54fa4e136989fda6fe122ef4ae866ebb1c85247d/docs/adr/0009-lsp-and-formatting.md)、[app/lsp/protocol.ts](https://github.com/tett23/aleph/blob/54fa4e136989fda6fe122ef4ae866ebb1c85247d/app/lsp/protocol.ts)
