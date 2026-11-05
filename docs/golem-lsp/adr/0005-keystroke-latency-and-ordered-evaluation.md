# ADR 0005: キー入力を待たせない LSP（semantic tokens、diagnostics の送り方、評価の順序）

ステータス: 採択→semantic tokens を知らせないことは [ADR 0006](0006-semantic-tokens-highlighting.md)

## 文脈

Neovim で Golem の LSP（`golem lsp`）を有効にすると、`.gm` で日本語を打つのが遅くなる。
本人の目標は、1 文字の入力にかかる時間を 16ms（60Hz の 1 フレーム）に収めることである。

### 測ったこと

main（8c9f2a6b）を組んだ `golem` と、Neovim 0.12.6（本人の設定、`golem lsp` を有効にしたもの）で測った。
プロジェクトは `manual/` の写しで、開くファイルは `chapters/09-editor.gm` である。

- **キー入力**：Neovim を `--headless --listen` で起動し、別の Neovim から RPC の `nvim_input` で、挿入モードに日本語を 1 文字ずつ送った（間隔 200ms）。
  編集する側の Neovim が `TextChangedI` と `TextChangedP` で記録した時刻（`vim.uv.hrtime()`、両方のプロセスで同じ単調な時計）から、送った時刻を引いて 1 文字の時間とした。
  次の文字を送るまでに変更が記録されなかった文字は、取りこぼしと数えた。
  27 文字のうち 21 文字を取りこぼし、記録された 6 文字の平均は 73.6ms、最大は 186.9ms だった。
  Neovim の `:messages` には、`LSP: no handler for: "textDocument/semanticTokens/full"` が 7 回あった。
- **diagnostics の数**：LSP の通信を直接つないで、同じファイルの段落の末尾に 1 文字ずつ足す変更を 8 回送った。
  `textDocument/publishDiagnostics` が 208 回（1 回の変更につき、プロジェクトの 26 ファイルのすべて）届いた。
  変更を送ってから、そのファイルの diagnostics が届くまでは平均 282ms で、そのうち 250ms は評価の前に待つ時間（`debounceMicros`）である。
- **補完**：`[` を打った位置での `textDocument/completion` の応答は、8 回で 0.5ms から 3.0ms だった。

### 原因

キー入力が遅いのは、Golem が処理できない semantic tokens を、処理できると知らせているためである。

- `lsp` パッケージ 2.8.0.0 は、初期化の応答の `semanticTokensProvider` を、ハンドラーの有無にかかわらず必ず入れる（`Language.LSP.Server.Processing` の `inferServerCapabilities`）。
  ハンドラーがなければ `full` と `range` を省くが、`legend` を持つ `semanticTokensProvider` そのものは残る。
- Neovim はこれを見て、変更のたびに `textDocument/semanticTokens/full` を送る。
  Golem はこの要求を処理できず、`lsp` パッケージがエラーを返して、`window/showMessage` でエラーを知らせる。
- Neovim は知らせを表示する。上の取りこぼしは、確認を待つ表示が打った文字を受け取っているためである可能性が高い（取りこぼした文字の数と、エラーの数が近い）。
  Ghostty の Neovim で同じことが起きるかは、測っていない。

初期化の応答で、ほかに処理のない能力を知らせていないことも確かめた。
知らせているのは、補完、定義、整形、文書のシンボル、ホバー、参照、名前の変更、文書の同期、`workspace.fileOperations`（中身は空）、`positionEncoding` で、semantic tokens のほかはすべてハンドラーがある。

### diagnostics と評価の順序で見つかったこと

キー入力を待たせる直接の原因ではないが、同じ処理の中に次の三つがある。

1. **すべてのファイルの diagnostics を送り直す**：`publishAll`（[Server.hs#L310-L316](https://github.com/tett23/golem/blob/8c9f2a6bab4a5e392670866af922d9946a4f7c34/modules/golem-lsp/src/Golem/Lsp/Server.hs#L310-L316)）は、評価のたびに、プロジェクトのすべての原稿、`@table` が読む表のファイル、プロジェクトの外の開いている `.gm` のファイルへ `publishDiagnostics` を送る。
   エディタは、届いたファイルごとに diagnostics を置き換えて表示し直す。
   プロジェクトが大きいほど、1 回の変更でエディタがする仕事が増える。
2. **別のファイルの変更が評価されない**：`changed`（[Server.hs#L243-L255](https://github.com/tett23/golem/blob/8c9f2a6bab4a5e392670866af922d9946a4f7c34/modules/golem-lsp/src/Golem/Lsp/Server.hs#L243-L255)）は、変更ごとに通し番号（`gen`）を一つ増やし、待ち時間の後に番号が変わっていなければ、そのファイルだけを評価する。
   番号はファイルによらず一つなので、ファイル A を変えて待ち時間のうちにファイル B を変えると、A の評価は飛ばされ、B だけが評価される。
   A の新しい内容は、A をもう一度変えるまで評価されない。
   `chapters/09-editor.gm` に存在しないラベルへの参照を足し、50ms と 80ms の後に `chapters/08-git-ci.gm` を変えると、どちらも `09-editor.gm` に G04003 が出なかった。
3. **古い評価が新しい評価を上書きする**：評価は変更ごとに別のスレッドで走り、互いを待たない。
   プロジェクトの全体を評価し直す変更（見出しを足すなど、`manual/` の写しで約 700ms）の後に、待ち時間を過ぎてから次の変更が来ると、次の変更は全体の評価が終わる前の状態から評価を始め、先に終わる。
   その後に全体の評価が終わって、古い内容の結果で上書きする。
   `09-editor.gm` に見出しを足し、300ms と 400ms の後に、見出しを消して存在しないラベルへの参照を足すと、どちらも最後の diagnostics に G04003 がなかった（1500ms の後なら出た）。

2 と 3 は、エディタに見えている diagnostics が、エディタの内容と食い違う不具合である。

### 試したこと

下の「実装すること」を仮に組んで（コミットはしない）、同じように測った。

| 測ったもの | main（8c9f2a6b） | 仮の実装 |
| --- | --- | --- |
| キー入力（`09-editor.gm`） | 27 文字のうち 21 文字を取りこぼし、記録された 6 文字の平均 73.6ms、最大 186.9ms | 54 文字を 3 回送って、取りこぼしなし、平均 2.8ms から 2.9ms、最大 6.0ms から 8.5ms |
| Neovim の `:messages` のエラー | 7 回 | 0 回 |
| 1 回の変更の `publishDiagnostics` | 26 回 | 1 回 |
| 変更から diagnostics まで | 平均 282ms | 平均 135ms |
| 2 の再現 | G04003 が出ない | 出る |
| 3 の再現 | G04003 が出ない | 出る |

golem-lsp の今のテスト（124 件）は、仮の実装でもすべて通った。

## 実装すること

### semantic tokens を知らせない

- `rewriteInitializeResponse` が初期化の応答を書き換えるとき、`positionEncoding` を入れるのに加えて、`capabilities` から `semanticTokensProvider` を除く（[ADR 0002](0002-utf8-position-encoding.md) と同じ書き換えの場所）。
- Golem が semantic tokens を処理するようになるまでは、知らせない。

### diagnostics は変わったファイルにだけ送る

- サーバーは、ファイルごとに最後に送った diagnostics（LSP の `Diagnostic` に直したもの）を覚える。
- 評価の後、次のファイルにだけ `publishDiagnostics` を送る。
  - 今回の評価で内容を変えたファイル（diagnostics が前と同じでも送る）。
  - diagnostics が、最後に送ったものと違うファイル。diagnostics がなくなったファイルには、空の列を送る。
- 一度も diagnostics を持たなかったファイルには送らない。
  エディタはそのファイルの diagnostics を受け取っていないので、表示は変わらない。

### 評価を一つずつ、変わったファイルをすべて評価する

- サーバーは、まだ評価していない変更のあるファイルの集合を持つ。
  変更が届くと、そのファイルを集合に加え、通し番号を増やす。
- 評価は、一つのロック（`MVar`）を取ってから行い、二つの評価が同時に走らないようにする。
  ロックを取ったら、集合を空にして取り出し、各ファイルの今のエディタの内容（VFS）で、順に `updateFile` する。
  最後に一度だけ、ワークスペースを置き換えて diagnostics を送る。
- 初期化の後の最初の評価、ファイルを閉じたときの評価、表のファイルの変更による評価も、同じロックを取る。
- これで、後に始まった評価は、先に始まった評価の結果の上で動き、古い結果が新しい結果を上書きしない。

### 評価の前に待つ時間を 100ms にする

- `debounceMicros` を 250ms から 100ms にする。
  評価が一つずつになり、待ち時間より評価が長くても結果の順序が崩れないので、待ち時間は、続けて打っている途中かどうかを見分けるのに足りればよい。
- 待ち時間は、エディタの入力そのものは待たせない（変更の通知は応答を待たない）。短くするのは、diagnostics が出るまでの時間を縮めるためである。

### 文書

- 仕様書の LSP の節に、diagnostics を変わったファイルにだけ送ること、評価を一つずつ行うこと、semantic tokens を知らせないことを書く。

## 実装しないこと

- semantic tokens の処理（`.gm` の色付け）。
- 1 回の評価そのものを速くすること（S1 の組み直し、lint）。今は変更 1 回につき数十 ms で、エディタの入力を待たせない。
- RTS のオプションの変更（GC の設定など）。`golem` は一つの実行ファイルで、`golem lsp` だけに別のオプションを与えるには手間がかかる。`GHCRTS=-N1` と既定の `-N` で、変更から diagnostics までの時間はほぼ同じだった（平均 289ms と 282ms）。キー入力の時間は、エディタの側で決まる。
- `textDocument/didChange` の差分の同期。全文の同期のまま（[ADR 0001](0001-language-server.md)）。
- Neovim の設定（dotfiles の側で semantic tokens を止める回避策）。Golem が知らせなくなれば要らない。

## テスト設計

先に次のテストを書き、main で失敗することを確かめてから実装する。

- `rewriteInitializeResponse` が、`semanticTokensProvider` を含む初期化の応答から、それを除くこと。ほかの能力と `positionEncoding` の書き換えは今のテストのとおり。
- `runGolemLspWithHandles` に初期化と `didOpen` を送った後、`modules/golem-lsp/test/fixtures/proj` の一つのファイルを、diagnostics がほかのファイルに及ばない形で変えると、`publishDiagnostics` がそのファイルにだけ届くこと。
- 同じく、ファイル A に存在しないラベルへの参照を足し、待ち時間のうちにファイル B を変えると、待ち時間の後に A に G04003 が届くこと（main では届かない。通し番号がファイルによらず一つのため、決まって失敗する）。
- 同じく、diagnostics を持つファイルの誤りを直すと、そのファイルに空の diagnostics が届くこと。

3（古い評価が新しい評価を上書きする）は、評価の時間に左右されるので、自動のテストにしない。
実装の後に、次を手で確かめる。

- `manual/` の写しで、`09-editor.gm` に見出しを足し、300ms と 400ms の後に、見出しを消して存在しないラベルへの参照を足す。最後の diagnostics に G04003 があること。
- 「測ったこと」のキー入力の測り方で、`manual/` の写しの `chapters/09-editor.gm` に、日本語を 54 文字送る。取りこぼしがなく、最大が 16ms 未満であること。
- Neovim の `:messages` に、`no handler` のエラーがないこと。
- 本人が確かめる：Ghostty の Neovim で `.gm` を開いて日本語を打ち、遅くないこと。diagnostics と補完が今までどおり出ること。

## トレードオフ

- 評価が一つずつになるので、プロジェクトの全体を評価し直している間（`manual/` の写しで約 700ms）の変更は、その評価が終わるまで評価されない。
  今は全体の評価が並んで走るが、結果の順序が保証されないので、待つほうを選ぶ。
- 最後に送った diagnostics をサーバーが覚えるので、プロジェクトの diagnostics の数だけメモリを使う。
- 待ち時間を 100ms にすると、100ms より間を空けて打つたびに評価が走る。評価はエディタの入力を待たせないが、CPU は今より使う。
- semantic tokens を知らせないので、エディタは Golem の色付けを求めない。色付けを実装するときは、知らせるかどうかを新しい ADR で決める。

## 参考文献

- `lsp` 2.8.0.0 の `Language.LSP.Server.Processing`（`inferServerCapabilities` の `semanticTokensProvider`）。cabal が取得済みの tarball（`~/.cabal/packages/hackage.haskell.org/lsp/2.8.0.0/`）で読んだ。
