# ADR 0006: semantic tokens で `.gm` の原稿を色付けする

ステータス: 採択

## 文脈

`.gm` の原稿には色付けがない。
Neovim は `.gm` のファイルタイプを `golem` にしているが、構文の定義も tree-sitter の文法もないので、原稿はすべて地の文の色で表示される。
本人から、色付けを実装する ADR を求められた。

[golem-lsp ADR 0005](0005-keystroke-latency-and-ordered-evaluation.md) は、処理できない semantic tokens を知らせていたせいでキー入力が遅れていたので、初期化の応答から `semanticTokensProvider` を除くと決めた。
その ADR は、色付けを実装するときに、知らせるかどうかを新しい ADR で決めるとしている。
この ADR がそれに当たる。
キー入力の目標（Neovim で 1 文字 16ms 未満）は、[ADR 0005](0005-keystroke-latency-and-ordered-evaluation.md) と同じく守る。

### 原稿の CST が持っているもの

golem-parser の CST（[CST.hs#L32-L115](https://github.com/tett23/golem/blob/8c9f2a6bab4a5e392670866af922d9946a4f7c34/modules/golem-parser/src/Golem/Parser/CST.hs#L32-L117)）は、原稿を失わずに保持し、トークンごとに種類（`SyntaxKind`）を持つ。
`withPositions`（[CST.hs#L167-L179](https://github.com/tett23/golem/blob/8c9f2a6bab4a5e392670866af922d9946a4f7c34/modules/golem-parser/src/Golem/Parser/CST.hs#L167-L179)）で、すべてのノードとトークンを、バイトの位置つきで前順にたどれる。
`golem inspect` で次の書き方の CST を確かめた。

| 書き方 | CST |
| --- | --- |
| `%%コメント%%`、`%%=校正%%` | `KComment`、`KProofComment` |
| `@label intro` | `NBlockCommand` の中の `KAt`、`KIdent`、`NArgument`（`KWord`） |
| `[ruby 漢字: かんじ]` | `NInlineCommand` の中の `KLBracket`、`KIdent`、`NArgument`、`KColon`、`NProseSlot`、`KRBracket` |
| `alt="図"` | `NKeywordArgument` の中の `KWord`、`KEquals`、`KString` |
| `[= 1 + x.y]`、`[= true]` | `NExpr` の中の `KExprOpen`、`KNumber`、`KOperator`、`NVarExpr`（`KIdent`、`KDot`）、`KKeyword` |
| `\[` | `KEscape` |
| `##12##` | `NNumberShorthand` の中の `KNumberMark`、`KNumberBody` |
| `# 見出し` | `NHeading` の中の `KHash`、`KText` |
| `- 箇条`、`+ 一` | `NListItem` の中の `KDash`、`KPlus` |
| `= 用語` | `NDefTerm` の中の `KEquals`、`KText` |
| 表 | `KPipe`、`NTableCell`、`NTableDelimiter` の中の `KDelim` |
| コードブロック | `KFence`、言語名の `KWord`、行ごとの `KCodeText` |
| 解釈できないブロック | `NErrorNode` の中の `KError` |

### lsp パッケージと Neovim の振る舞い

`lsp` 2.8.0.0 と `lsp-types` 2.4.0.0 は、cabal が取得済みの tarball で読んだ。

- `lsp` は、初期化の応答の `semanticTokensProvider` に、`lsp-types` の `defaultSemanticTokensLegend`（LSP の標準の型 23 種と修飾子 10 種）を必ず入れる。
  `textDocument/semanticTokens/full` のハンドラーがあれば `full` を、`range` のハンドラーがあれば `range` を足し、`full/delta` のハンドラーの有無で `delta` を決める（`Language.LSP.Server.Processing` の `inferServerCapabilities`）。
- `lsp-types` の `Language.LSP.Protocol.Types.SemanticTokens` は、絶対位置のトークン（`SemanticTokenAbsolute`：行、列、長さ、型、修飾子）の列を、凡例に従って LSP の整数の列に直す `makeSemanticTokens` を持つ。
- `lsp` は、届いたメッセージを一つずつ順に処理し、ハンドラーをその中で呼ぶ（`Language.LSP.Server.Control`）。時間のかかるハンドラーは、後のメッセージ（変更の通知や補完の要求）の処理を、その間だけ遅らせる。
- `lsp` は `$/cancelRequest` を処理しない。`$/` で始まる通知にハンドラーがなければ、重大度 Warning の記録になり、`window/logMessage` で送る（Error ではないので `window/showMessage` にはならない）。

Neovim 0.12.6 の `runtime/lua/vim/lsp/semantic_tokens.lua` は、次のように動く。

- `textDocument/didChange` か `didOpen` を送るたびに、その版の `textDocument/semanticTokens/full` を送る。`didChange` そのものは、既定で 150ms ごとにまとめて送る（`_changetracking.lua` の `debounce_text_changes`）。
- 古い版の要求が残っていれば、`$/cancelRequest` で取り消す。古い版への応答は捨てる。
- 応答のトークンを、コルーチンの中で 5ms ごとに処理を譲りながら、ハイライトの範囲に直す。表示は、見えている行だけを描く。
- 位置の単位は、交渉した `offset_encoding` で読む（[ADR 0002](0002-utf8-position-encoding.md)）。
- サーバーが `range` に対応していれば、最初の `full` の結果が届くまでのあいだと、スクロールのたびに、見えている範囲を `range` で求める。
- 既定のハイライトのグループ `@lsp.type.<型>` は、標準の型を tree-sitter のグループへつないでいる（`@lsp.type.function` は `@function`、`@lsp.type.comment` は `@comment` など）。

### 測ったこと

CST を作ってトークンを数える試作（コミットしない）を、`cabal repl` で `-fobject-code -O1` にして測った。
毎回 1 文字ずつ足した本文で 6 回ずつ測った。

| ファイル | 大きさ | 構文解析 | トークンへの変換 | トークンの数 |
| --- | --- | --- | --- | --- |
| `manual/chapters/09-editor.gm` | 6,426 バイト | 2.0ms から 6.2ms | 0.11ms | 80 |
| `manual/chapters/05-style.gm` | 58,198 バイト | 53ms から 103ms | 1.2ms から 38ms | 1,145 |

時間の大半は構文解析である。
大きなファイルでは、1 回の要求に数十 ms から 100ms かかりうる。
`lsp` はハンドラーを順に呼ぶので、そのあいだ補完の要求も待たされる。

## 実装すること

### 知らせる能力

- `textDocument/semanticTokens/full` のハンドラーを足す。`lsp` が、`full`（`delta` は偽）と `defaultSemanticTokensLegend` の凡例を知らせる。
- [ADR 0005](0005-keystroke-latency-and-ordered-evaluation.md) が `rewriteInitializeResponse` に足した、`semanticTokensProvider` を除く書き換えをやめる。`positionEncoding` の書き換えは残す。
- `range` と `full/delta` は知らせない。
- 凡例は `lsp` が知らせる `defaultSemanticTokensLegend` をそのまま使い、応答のトークンも同じ凡例で `makeSemanticTokens` に通す。独自の型は足さない。
- `$/cancelRequest` に、何もしないハンドラーを置く。Neovim が古い要求を取り消すたびに記録が出るのを防ぐ。

### トークンを作る元

- 要求の時点のエディタの内容（VFS）の CST から作る。[ADR 0005](0005-keystroke-latency-and-ordered-evaluation.md) のワークスペースは、変更の後に 100ms 待ってから評価するので、要求の時点ではエディタの内容より古いことがあり、位置がずれる。
- ワークスペースがそのファイルについて持つ本文が、VFS の本文と同じなら、ワークスペースの CST を使い、構文解析を省く。
- 違えば、VFS の本文を構文解析する（`parse`、ファイルの番号は 0）。
- 構文解析とトークンへの変換は、`forkIO` した別のスレッドで行い、そのスレッドから応答する。本文は、ハンドラーの中で VFS から取ってからスレッドに渡す。これで、大きなファイルでも、後のメッセージの処理を待たせない。
- `.gm` でないファイル（`style.toml`、`preflight.toml` など）には、空のトークンの列を返す。Neovim の semantic tokens のハイライトは tree-sitter より優先度が高いが、トークンがなければ TOML の tree-sitter の色付けがそのまま見える。

### 型の対応

トークンの種類と、その親のノードで型を決める。
親は `withPositions` の前順のたどりではなく、木をたどるときに持ち回す。

| 原稿の要素 | CST | LSP の型 | Neovim の既定のつなぎ先 |
| --- | --- | --- | --- |
| コメント | `KComment` | `comment` | `@comment` |
| 校正のコメント | `KProofComment` | `comment`、修飾子 `modification` | `@comment` |
| ブロックのコマンドの `@` と名前 | `NBlockCommand` の `KAt` と直後の `KIdent` | `decorator` | `@attribute` |
| インラインのコマンドの名前 | `NInlineCommand` の `KLBracket` の直後の `KIdent` | `function` | `@function` |
| キーワード引数の名前 | `NKeywordArgument` の最初の `KWord` | `parameter` | `@variable.parameter` |
| 引数の値 | `NArgument` と `NKeywordArgument` の値の `KWord`、`KString` | `string` | `@string` |
| 式の始まり | `KExprOpen`（`[=`） | `keyword` | `@keyword` |
| 式の数、文字列、キーワード | `KNumber`、`KString`、`KKeyword` | `number`、`string`、`keyword` | `@number`、`@string`、`@keyword` |
| 式の変数 | `NVarExpr` の `KIdent` | `variable` | `@variable` |
| 式の呼び出しの名前 | `NCallExpr` の最初の `KIdent` | `function` | `@function` |
| 式の演算子 | `KOperator` | `operator` | `@operator` |
| エスケープ | `KEscape` | `macro` | `@constant.macro` |
| 数の表記の `##` と中身 | `KNumberMark`、`KNumberBody` | `operator`、`number` | `@operator`、`@number` |
| 見出しの印 | `NHeading` の `KHash` | `keyword` | `@keyword` |
| 見出しの文字 | `NHeading` の `KText` | `namespace` | `@module` |
| リストと定義リストの印 | `KDash`、`KPlus`、`NDefTerm` の `KEquals` | `keyword` | `@keyword` |
| 表の区切り | `KPipe`、`KDelim` | `operator` | `@operator` |
| コードブロックの囲みと言語名 | `KFence`、`NCodeBlock` の `KWord` | `keyword`、`type` | `@keyword`、`@type` |

- 地の文（`KText`）、散文スロットの中身、コードブロックの中身（`KCodeText`）、空白、改行、角括弧、`:`、`KError` には、トークンを作らない。
  地の文を色付けしないのは、原稿の大半が地の文で、色を付けると見分けの役に立たないためである。
  構文エラーの箇所は diagnostics が示す。
- 修飾子は、校正のコメントの `modification` のほかは使わない。

### 位置

- トークンの行と列と長さは、交渉した位置の単位（[ADR 0002](0002-utf8-position-encoding.md)、`Golem.Lsp.Features` の [`toLineCol`](https://github.com/tett23/golem/blob/8c9f2a6bab4a5e392670866af922d9946a4f7c34/modules/golem-lsp/src/Golem/Lsp/Features.hs#L59-L61)）で数える。
- 改行をまたぐトークン（複数行のコメント、`KError` は除くので、主にコメント）は、行ごとに分けて、改行を含まないトークンにする。クライアントの `multilineTokenSupport` には頼らない。
- 長さが 0 になる行の部分（改行だけの行など）は捨てる。

### 文書

- 仕様書の LSP の節に、semantic tokens で色付けすること、型の対応、`.gm` のほかのファイルには空を返すことを書く。
- 使い手のマニュアルの第 9 章「エディタ」に、色付けが LSP から来ること、色はエディタのテーマの `@lsp.type.*` で変わることを書く。

## 実装しないこと

- `textDocument/semanticTokens/range` と `full/delta`。Neovim は応答を 5ms ごとに譲りながら処理し、見えている行だけを描くので、`full` だけでもエディタの入力を待たせない。`range` を足しても、サーバーはファイルの全体を構文解析するので、速くならない。
- 独自のトークンの型（`heading` など）と、Golem のための凡例。標準の型なら、エディタの設定なしに既定の色が付く。
- tree-sitter の文法と、Neovim の構文の定義。
- TOML（`style.toml`、`preflight.toml`）の色付け。エディタの TOML の色付けに任せる。
- コードブロックの中身を、その言語として色付けすること。
- 評価の結果に基づく色付け（未定義のラベルへの参照の色を変えるなど）。diagnostics が示す。
- 構文解析そのものの高速化。

## テスト設計

先に次のテストを書き、main（と [ADR 0005](0005-keystroke-latency-and-ordered-evaluation.md) の実装）で失敗することを確かめてから実装する。

- 純粋な関数のテスト（トークンを作る関数を `Golem.Lsp.Features` に置く）。
  - 上の表の各行の要素を一つずつ含む小さな原稿から、期待する型と、行、列、長さのトークンの列ができること。
  - 日本語の地の文の後のコマンドの名前の列が、UTF-8 と UTF-16 で、それぞれの単位で数えた値になること。
  - 2 行にまたがるコメントが、2 つのトークンに分かれること。
  - 地の文、散文スロットの中身、`KCodeText`、`KError` からトークンができないこと。
  - トークンが文書の順に並び、重ならないこと（hedgehog で、生成した原稿について確かめる）。
  - `makeSemanticTokens` に `defaultSemanticTokensLegend` で通して、`Left` にならないこと。
- `rewriteInitializeResponse` の今のテストを改め、`semanticTokensProvider` を残し、`positionEncoding` だけを書き換えることを確かめる。
- `runGolemLspWithHandles` で、初期化の応答に `semanticTokensProvider.full` と凡例があり、`range` と `delta` がないこと。
- 同じく、`modules/golem-lsp/test/fixtures/proj` の原稿を開き、`didChange` で本文を変えた直後（ワークスペースの評価を待たずに）`textDocument/semanticTokens/full` を送ると、変えた後の本文の位置でトークンが返ること。
- 同じく、`style.toml` への要求に、空のトークンの列が返ること。
- 同じく、`$/cancelRequest` を送っても、`window/logMessage` も `window/showMessage` も届かないこと。

自動のテストにしにくい次のことは、実装の後に手で確かめる。

- [ADR 0005](0005-keystroke-latency-and-ordered-evaluation.md) のキー入力の測り方（`nvim --headless --listen` に RPC で日本語を送り、`TextChangedI` と `TextChangedP` の時刻を見る）で、`manual/` の写しの `chapters/09-editor.gm` と `chapters/05-style.gm` に、日本語を 54 文字ずつ送る。取りこぼしがなく、最大が 16ms 未満であること。
- 同じ Neovim で、`golem` のクライアントの semantic tokens が有効で、`vim.lsp.semantic_tokens.get_at_pos()` がコマンドの名前の位置で `function` を返すこと。
- `chapters/05-style.gm` で `semanticTokens/full` の応答を待つあいだに送った `textDocument/completion` の応答が、トークンの応答より先に届くこと。
- 本人が確かめる：Ghostty の Neovim で `.gm` を開き、コマンド、コメント、見出し、式が色分けされること。日本語を打っても遅くないこと。

## トレードオフ

- 要求のたびに、エディタの内容を構文解析し直す。ワークスペースと同じ本文なら省けるが、打っている最中はほとんど省けない。大きなファイルでは CPU を使う。応答を別のスレッドで作るので、エディタの入力とほかの要求は待たせない。
- Neovim は古い要求を取り消すが、`lsp` は取り消しを処理しないので、取り消された要求の計算も最後まで走る。応答は Neovim が捨てる。
- 標準の型を借りるので、意味の合わない名前がある（見出しの文字を `namespace`、エスケープを `macro` とするなど）。独自の型にすれば名前は合うが、エディタの側に色の設定が要る。
- 地の文を色付けしないので、見出しやコマンドの外の誤り（閉じ忘れた括弧の後の地の文など）は、色では分からない。
- `lsp` が凡例を決めるので、`lsp` を上げて `defaultSemanticTokensLegend` の中身が変わると、型の番号も変わる。応答も同じ凡例で作るので、食い違いは起きない。
- [ADR 0005](0005-keystroke-latency-and-ordered-evaluation.md) の「semantic tokens を知らせない」は、この ADR を実装した時点で効力を失う。[ADR 0005](0005-keystroke-latency-and-ordered-evaluation.md) のステータスの行を、この ADR への参照つきで改める。

## 参考文献

- `lsp` 2.8.0.0 の `Language.LSP.Server.Processing`（`inferServerCapabilities`、ハンドラーのない通知の扱い）、`Language.LSP.Server.Control`、`Language.LSP.Logging`（`defaultClientLogger`）。cabal が取得済みの tarball で読んだ。
- `lsp-types` 2.4.0.0 の `Language.LSP.Protocol.Types.SemanticTokens`（`defaultSemanticTokensLegend`、`SemanticTokenAbsolute`、`makeSemanticTokens`）と `Language.LSP.Protocol.Message.Method`（`isOptionalMethod`）。
- Neovim 0.12.6 の `runtime/lua/vim/lsp/semantic_tokens.lua` と `runtime/lua/vim/lsp/_changetracking.lua`、`nvim --clean` の `:highlight` の `@lsp.type.*`。
