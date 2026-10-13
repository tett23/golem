# ADR 0003: 行の長さを超える列を行末に丸め、位置の交渉をエディタで確かめる

ステータス: 採択

## 文脈

[ADR 0002](0002-utf8-position-encoding.md) は、位置の単位に UTF-8 を交渉で選べるようにした。
そのうえで、二つのことを残している。

一つは、行の長さを超える列の扱いである。
LSP 3.17 の `Position` の `character` は、「値が行の長さより大きい場合は、行の長さに戻す」と定めている（[LSP 3.17 の仕様](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/)の Position の節）。
今の実装は、要求の位置をバイト位置に変える `Golem.Lsp.Features.fromLineCol` が、golem-syntax の `utf8LineColToOffset` と `utf16LineColToOffset` をそのまま呼ぶ。
この二つは行の長さを超える列に `Nothing` を返し、`Golem.Lsp.Server` の `atPosition` は `Nothing` のとき結果を空にする（定義、参照、名前の変更、補完、ホバーのすべて）。
[ADR 0002](0002-utf8-position-encoding.md) は、この扱いを変えないと明記している。

もう一つは、UTF-8 の交渉を実際のエディタで確かめていないことである。
[ADR 0002](0002-utf8-position-encoding.md) のテスト設計は、Neovim 0.10 以降の組み込みのクライアントで確かめるとしたが、手順を決めておらず、まだ行っていない。

LSP 3.17 の仕様は、行の番号が文書の行の数を超える場合と、列が文字の途中（UTF-8 の後続バイト、UTF-16 のサロゲートペアの間）に当たる場合を定めていない。

手もとの Neovim 0.12.5 の組み込みのクライアントについて、次のことを確かめた（`$VIMRUNTIME/lua/vim/lsp/client.lua` を読み、`nvim --headless` で値を表示した）。

- `vim.lsp.protocol.make_client_capabilities().general.positionEncodings` は `{ "utf-8", "utf-16", "utf-32" }` である。
- 初期化の応答の `capabilities.positionEncoding` があれば、それを `client.offset_encoding` にする。
- 設定の `capabilities` は、既定の能力に `vim.tbl_deep_extend('force', …)` で重ねる。0.12.5 では、リストは要素ごとに重ねず、丸ごと置き換わる（`{ "utf-16" }` を重ねると `{ "utf-16" }` になる）。

## 実装すること

### 丸めの規則

要求の位置（行、列）からバイト位置への変換を、次の規則にする。

1. 行が 0 未満か、文書の行の数以上なら、変換できない（今と同じ）。
2. 列が、交渉した単位で数えたその行の長さより大きいなら、行末のバイト位置にする。行の長さは改行（LF）を含まない。
3. 列が文字の途中に当たるなら、変換できない（今と同じ）。
4. それ以外は、今と同じくその位置のバイト位置にする。

行の数を超える行と文字の途中の列は、仕様が定めていないので丸めない。
丸めると、クライアントの誤りを隠して、利用者が指していない位置の結果を返すことになるからである。

### golem-syntax

`Golem.Syntax.Position` に、行末のバイト位置を返す関数を足して公開する。

```haskell
-- | 行の末尾（改行の直前）のバイト位置。行がなければ Nothing。
lineEndOffset :: LineIndex -> Int -> Maybe Int
```

- 中身は、公開していない `lineStartAndEnd` の二つ目の値である。
- `utf8LineColToOffset`、`utf16LineColToOffset`、`lineColToOffset` の振る舞いは変えない。`lineColToOffset` はマニフェストの TOML の位置の変換にも使っており、そこでは丸める理由がない。[ADR 0002](0002-utf8-position-encoding.md) の golem-syntax のテスト（`(LineCol 0 7)` が `Nothing` になることなど）もそのまま保つ。

### golem-lsp

丸めは LSP の境界でだけ行う。

`Golem.Lsp.Features.fromLineCol` を次のように変える。型は変えない。

```haskell
fromLineCol :: Encoding -> LineIndex -> LineCol -> Maybe Int
fromLineCol enc li lc@(LineCol l c) = do
  end <- lineEndOffset li l
  let width = lcColumn (toLineCol enc li end)   -- 交渉した単位での行の長さ
  if c > width then Just end else exact enc li lc
```

- `exact` は今の `fromLineCol`（`utf8LineColToOffset` か `utf16LineColToOffset`）である。
- 行の長さは、行末のバイト位置を `toLineCol` で列に直して求める。UTF-8 では走査が要らず、UTF-16 では行を一度走査する。
- `Golem.Lsp.Server` は変えない。要求の位置はすべて `atPosition` から `fromLineCol` を通るので、定義、参照、名前の変更、補完、ホバーのすべてに丸めが効く。
- モジュールの先頭のコメントに、丸めの規則を一文で書く。

### エディタでの確かめ

実装の後に、Neovim の組み込みのクライアントで次の手順を行う。

1. `cabal-3.16.1.0 install golem-cli` などで `golem` を PATH に置く。
2. 次の内容の `golem-lsp.lua` を作る。

   ```lua
   vim.filetype.add({ extension = { gm = 'golem' } })
   vim.lsp.config('golem', {
     cmd = { 'golem', 'lsp' },
     filetypes = { 'golem' },
     root_markers = { 'manifest.toml' },
   })
   vim.lsp.enable('golem')
   ```

3. `nvim --clean -u golem-lsp.lua modules/golem-lsp/test/fixtures/proj/a.gm` で開く。
4. `:lua =vim.lsp.get_clients({ name = 'golem' })[1].offset_encoding` が `utf-8` を表示することを確かめる。
5. 次を確かめる。6 行目（1 始まり）は、確かめたい位置の前に日本語と絵文字を持つ。
   - 6 行目の `values.version` の上で `K`（ホバー）を押すと、評価の結果が出る。
   - 6 行目の `[ref-number second]` の `second` の上で `gd`（定義への移動）を押すと、`b.gm` の 1 行目の `second` に移る。
   - 3 行目の `@label intro` の `intro` の上で `:lua vim.lsp.buf.rename('opening')` を実行すると、`a.gm` と `b.gm` の `intro` だけが過不足なく書き換わる。確かめた後に `:wa` をせずに `:qa!` で閉じる。
   - 6 行目の末尾に `😀[ref-title nosuch]` を書き足すと、G0403 の下線が `[` から `]` までに引かれる。
6. 行の長さを超える列を、手で要求に載せて確かめる。

   ```lua
   :lua vim.lsp.buf_request(0, 'textDocument/hover', { textDocument = vim.lsp.util.make_text_document_params(), position = { line = 5, character = 1000 } }, function(err, res) print(vim.inspect(err), vim.inspect(res)) end)
   ```

   エラーにならず、6 行目の行末の位置でのホバーと同じ結果（行末が `]` の後なら `nil`）が返ることを確かめる。
7. 手順 2 の `vim.lsp.config` に `capabilities = { general = { positionEncodings = { 'utf-16' } } }` を加えて開き直し、手順 4 が `utf-16` を表示すること、手順 5 と 6 が同じ結果になることを確かめる。

確かめた結果（Neovim の版、Golem のコミット、各手順の結果）は、`docs/golem-lsp/verification/` に日付を名前にした Markdown のファイルとして残す。
このファイルは記録であり、コミットした後は変更しない。

### ドキュメント

- 仕様書の LSP の節に、行の長さを超える列は行末に丸め、行の数を超える行と文字の途中の列は結果を空にすることを書く。
- 仕様書の「v1 の実装で次の段階以降に回した項目」の「LSP の位置の扱い」から、丸めを実装した時点で丸めの記述を消し、エディタでの確かめを終えた時点で項目を削る。
- [ADR 0002](0002-utf8-position-encoding.md) のステータスの行を「採択→行の長さを超える列の扱いは ADR 0003」に変え、この ADR へのリンクを付ける。

## 実装しないこと

- 行の数を超える行の丸め（文書の末尾にする扱い）。仕様が定めておらず、クライアントの誤りを隠すことになる。
- 文字の途中の列を前後の文字の境界に寄せること。同じ理由で、[ADR 0002](0002-utf8-position-encoding.md) のとおり結果を空にする。
- 編集の直後に古い原稿で位置を解釈する問題。全文の同期の後、`Workspace` の更新は一定の時間を待ってから行う（[ADR 0001](0001-language-server.md)）ので、その間に届いた要求の位置は、新しい原稿の位置を古い原稿で解釈する。丸めはこの食い違いを直さず、行末より先の列が古い行の行末を指すようになるだけである。直すには要求の時点で編集中の全文から解析し直す必要があり、速度の問題とあわせて扱う（仕様書の「ビルドと LSP の速度」）。
- Neovim 以外のエディタ（VS Code、Helix など）での確かめ。UTF-8 を申し出る代表として Neovim で確かめ、UTF-16 の経路は手順 7 で同じエディタで確かめる。
- エディタでの確かめの自動化。`lsp-test` による自動テストが同じ経路を通るので、エディタでの確かめは一度の記録にとどめる。

## テスト設計

先に次のテストを書いて失敗させる。

### golem-syntax（`modules/golem-syntax/test/Main.hs`）

- `mkLineIndex "漢字\nab"` で、`lineEndOffset li 0` が `Just 6`、`lineEndOffset li 1` が `Just 9`、`lineEndOffset li 2` が `Nothing` になる。
- `mkLineIndex "a\n"` で、`lineEndOffset li 1` が `Just 2`（末尾の空の行）になる。
- [ADR 0002](0002-utf8-position-encoding.md) の `utf8LineColToOffset` の単体テストが変わらずに通る。

### golem-lsp（`modules/golem-lsp/test/Main.hs`）

単体（`mkLineIndex "漢字\nab"`）：

- `fromLineCol Utf8 li (LineCol 0 7)` と `fromLineCol Utf8 li (LineCol 0 1000)` が `Just 6` になる。今は `Nothing` である。
- `fromLineCol Utf16 li (LineCol 0 3)` と `fromLineCol Utf16 li (LineCol 0 1000)` が `Just 6` になる。
- `fromLineCol Utf16 li (LineCol 0 2)` が `Just 6`（行末そのもの）になる。
- `fromLineCol Utf8 li (LineCol 1 5)` が `Just 9` になる。
- `fromLineCol Utf8 li (LineCol 2 0)` と `fromLineCol Utf16 li (LineCol 2 0)` が `Nothing` になる（行の数を超える）。
- `fromLineCol Utf8 li (LineCol 0 1)` が `Nothing` になる（文字の途中）。
- 絵文字の行 `mkLineIndex "😀a"` で、`fromLineCol Utf16 li (LineCol 0 1)` が `Nothing`（サロゲートペアの間）、`fromLineCol Utf16 li (LineCol 0 9)` が `Just 5` になる。

プロパティ：

- 既存の `genText` と任意の行と列で、`fromLineCol` が `Just o` を返すなら、`o` はその行の先頭以上、`lineEndOffset` 以下である。
- 列が行の長さ以下の位置では、`fromLineCol` の結果が今の `utf8LineColToOffset` と `utf16LineColToOffset` の結果と一致する。

プロトコル（`lsp-test` のセッション、UTF-16 と UTF-8 の両方）：

- `b.gm` の内容を `"[color \n"` に変え、診断の通知を待ってから、`(0, 7)` と `(0, 1000)` で補完を要求する。どちらも `["accent"]` になる。今の実装では `(0, 1000)` が空になる。
- `a.gm` の 0 始まりで 5 の行で、列 1000 のホバーが、行末の列（UTF-16 と UTF-8 のそれぞれで数えた値）のホバーと同じ結果になり、エラーの応答にならない。

自動テストにしないもの：「エディタでの確かめ」の手順。結果は `docs/golem-lsp/verification/` に記録する。

## トレードオフ

行末に丸めると、行の長さを超える位置を送るクライアントの誤りが、行末での結果として表に出る。
空の結果のほうが誤りに気付きやすいが、LSP 3.17 は丸めると定めているので、仕様に従うクライアントが補完やホバーの結果を得られないほうを問題とする。
とくに補完は行末で求められることが多く、クライアントが行末の改行の扱いを誤って一つ先の列を送った場合にも結果が出る。

丸めを LSP の境界（`fromLineCol`）に置くので、golem-syntax の変換の関数は厳密なまま残る。
マニフェストの位置の変換のように丸める理由のない呼び出しに、丸めが漏れることはない。
その代わり、行の長さを数えるために UTF-16 では行を一度余分に走査する。
一つの要求につき一行の走査であり、行の索引は [ADR 0002](0002-utf8-position-encoding.md) で配列にしてあるので、費用は行の長さに比例するだけである。

エディタでの確かめは一度きりの記録であり、Neovim や Golem の版が変わった後の振る舞いは保証しない。
交渉と変換は `lsp-test` の自動テストで UTF-8 と UTF-16 の両方を確かめており、エディタでの確かめは、自動テストのクライアントと実際のクライアントの能力の違いを見つけるためのものである。
