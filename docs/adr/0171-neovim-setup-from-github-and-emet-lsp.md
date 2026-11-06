# ADR 0171: Neovim の設定例で、tree-sitter の文法を GitHub から入れ、.emet でも LSP を起動する

ステータス: 採択

## 文脈

[ADR 0170](0170-emet-editor-support.md) で、`.gm` と `.emet` の tree-sitter の文法を `tools/editors/` に置き、使い方を `tools/editors/README.md` に書いた（[PR #574](https://github.com/tett23/golem/pull/574)）。
Neovim の節は、次の二つの入れ方を書いている（[`README.md`](https://github.com/tett23/golem/blob/d4a259b331990a71b804d062466b8cfeee2ff64e/tools/editors/README.md#L79-L105)）。

- パーサーを C コンパイラーで共有ライブラリにし、問い合わせと一緒に `runtimepath` の下に写す。リポジトリかリリースのアーカイブが手元にあることを前提にする。
- nvim-treesitter を使っている場合は、`require('nvim-treesitter.parsers')` に、`install_info` の `path` をこのディレクトリにした項目を足し、`:TSInstall` で入れる。これも手元の写しを前提にし、項目の書き方の例はない。

使い手のマニュアルの「エディタ」の章（`manual/chapters/09-editor.gm`）の Neovim の設定の例は、LSP の設定だけを書いている（[`09-editor.gm`](https://github.com/tett23/golem/blob/d4a259b331990a71b804d062466b8cfeee2ff64e/manual/chapters/09-editor.gm#L39-L49)）。
例の `vim.filetype.add` は `.gm` だけを `golem` にし、`filetypes` は `{ "golem", "toml" }` である。
[ADR 0162](0162-calling-emet-functions-from-gm.md) と [ADR 0170](0170-emet-editor-support.md) で、Golem の LSP は `.emet` の diagnostics、補完、色付け、アウトラインなどを持つようになったが、この例のとおりに設定すると、`.emet` にはファイルタイプが付かず、LSP も起動しない。

### 確かめたこと

メンテナーの dotfiles を設定するセッションが、2026-11-06 に次のことを確かめた（Neovim 0.12.6、nvim-treesitter の main ブランチの `e289100`、Golem の `origin/main` の `387312d3`）。

- 下の「実装すること」の `install_info`（`url`、`location`、`queries`）で、`golem` と `emet` の文法が GitHub から入り、`queries/golem/highlights.scm` と `queries/emet/highlights.scm` が写された。
- `modules/golem-driver/test/fixtures/emet-samples` の `text.gm` で `vim.treesitter.start` が通り、構文の誤りはなく、29 個の捕捉が付いた。見出しの `#` に `@keyword`、見出しの文字に `@module`、`[t.mono …]` に `@function` が付いた。
- 同じ fixture の `fn/lib.emet` で、`@keyword`、`@function`、`@type`、`@constructor` などの捕捉が付いた。
- `filetypes` に `emet` を足すと、`.emet` で Golem の LSP のクライアントが付いた。

この ADR の草稿を書くセッションは、2026-11-06 に次のことを確かめた。

- nvim-treesitter の `e289100` の `install.lua` で、`url` の項目は GitHub の tarball を展開したディレクトリに `location` を連結してコンパイルし、`queries` は `location` ではなく、展開したディレクトリ（リポジトリのルート）に連結して写す（[`install.lua`](https://github.com/nvim-treesitter/nvim-treesitter/blob/e289100ff98969e118c702199d88b764ce9e7fdf/lua/nvim-treesitter/install.lua#L381-L443)）。
- `revision` がなければ、`branch` か `main` を落とす（同じ箇所）。`revision` のない項目は、問い合わせの写しがランタイムの問い合わせと同じ場所を指さないので、`:TSUpdate` のたびに入れ直す（[`needs_update`](https://github.com/nvim-treesitter/nvim-treesitter/blob/e289100ff98969e118c702199d88b764ce9e7fdf/lua/nvim-treesitter/install.lua#L170-L184)）。
- `generate` を指定しなければ、文法を生成し直さず、コミットした `src/parser.c` と `src/scanner.c` をコンパイルする（同じ箇所）。
- nvim-treesitter を使わない Neovim でも、`.gm` のファイルタイプ `golem` の色付けは、パーサーと `queries/golem/highlights.scm` が `runtimepath` にあり、`vim.treesitter.start()` を呼べば始まる。
  パーサーをコンパイルして `vim.treesitter.language.add` で読ませ、`nvim --headless` で確かめた。
  `@import` には `@attribute` が、見出しの `#` には `@keyword` が捕捉として付いた。
- `d4a259b3`（[ADR 0170](0170-emet-editor-support.md) の実装の後）の `golem` で、`vim.filetype.add` に `emet = "emet"`、`filetypes` に `emet` を足して `fn/lib.emet` を開くと、クライアントが付き、`textDocument/documentSymbol` が 25 個の記号を、`textDocument/semanticTokens/full` がトークンを返した。dotfiles のセッションが [ADR 0170](0170-emet-editor-support.md) より前の `golem` で確かめたときは、どちらも空だった。

次のことは、まだ確かめていない。

- Ghostty などで実際に開いた画面での見え方。
- Helix、Zed、Visual Studio Code の手順（[ADR 0170](0170-emet-editor-support.md) のときから [docs/roadmap.md](../roadmap.md) の「手で確かめる項目」にある）。

## 実装すること

使い手のマニュアル、開発者のマニュアル、`tools/editors/README.md` の変更であり、Golem のプログラムは変えない。

### `tools/editors/README.md` の「Neovim」の節

今の二つの入れ方（手でコンパイルして写すこと、`path` の項目）の前に、nvim-treesitter（main ブランチ）で GitHub から入れる例を、推奨の方法として置く。

```lua
vim.api.nvim_create_autocmd('User', { pattern = 'TSUpdate', callback = function()
  local parsers = require('nvim-treesitter.parsers')
  parsers.golem = { install_info = {
    url = 'https://github.com/tett23/golem',
    location = 'tools/editors/tree-sitter-golem',
    queries = 'tools/editors/tree-sitter-golem/queries',
  } }
  parsers.emet = { install_info = {
    url = 'https://github.com/tett23/golem',
    location = 'tools/editors/tree-sitter-emet',
    queries = 'tools/editors/tree-sitter-emet/queries',
  } }
end })
vim.filetype.add({ extension = { gm = 'golem', emet = 'emet' } })
vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'golem', 'emet' },
  callback = function() vim.treesitter.start() end,
})
```

例の後に、次のことを書く。

- 入れるコマンドは `:TSInstall golem emet` である。手元に Golem を clone しなくてよい。C コンパイラーは要る（nvim-treesitter がパーサーをコンパイルする）。
- nvim-treesitter は色付けを自動では始めないので、`FileType` で `vim.treesitter.start()` を呼ぶ。
- `queries` は `location` からではなく、リポジトリのルートからのパスで書く。nvim-treesitter は、展開したリポジトリのルートに `queries` を連結するからである。
- `revision` を書かなければ、`main` の先頭を入れる。そのときは、`:TSUpdate` のたびに入れ直す。版を固定したいときは、`revision` にタグかコミットを書く。
- 確かめた環境（Neovim 0.12.6、nvim-treesitter の main ブランチの `e289100`）を書く。

今の `path` の項目の一行は、「手元の写し（リポジトリかリリースのアーカイブ）から入れる場合は、`url` の代わりに `path` をその写しのディレクトリにし、`location` を除く」と書き直し、`path` のときの `queries` も同じ写しのルートからのパスであることを添える。
手でコンパイルして写す方法は、nvim-treesitter を使わない場合の方法として残す。

`tools/editors/README.md` の「確かめた」の記述（`Neovim の手順は Neovim 0.12.6 で確かめた`）は、上の確かめた環境に合わせて書き直す。

### `manual/chapters/09-editor.gm` の Neovim の設定の例

LSP の設定の例を、`.emet` でも起動するように直し、同じ例に tree-sitter の色付けの設定を並べる（「決めたことの記録」）。
LSP と構文の色付けは、今のエディタで原稿を書くのに欠かせないので、Neovim を使う読み手が一か所で設定を写せるようにする。

```lua
-- ファイルの種類
vim.filetype.add({ extension = { gm = "golem", emet = "emet" } })

-- LSP
vim.lsp.config("golem", {
  cmd = { "golem", "lsp" },
  filetypes = { "golem", "emet", "toml" },
  root_markers = { "manifest.toml" },
})
vim.lsp.enable("golem")

-- LSP が動く前の色付け（nvim-treesitter の main ブランチ）
vim.api.nvim_create_autocmd("User", { pattern = "TSUpdate", callback = function()
  local parsers = require("nvim-treesitter.parsers")
  parsers.golem = { install_info = {
    url = "https://github.com/tett23/golem",
    location = "tools/editors/tree-sitter-golem",
    queries = "tools/editors/tree-sitter-golem/queries",
  } }
  parsers.emet = { install_info = {
    url = "https://github.com/tett23/golem",
    location = "tools/editors/tree-sitter-emet",
    queries = "tools/editors/tree-sitter-emet/queries",
  } }
end })
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "golem", "emet" },
  callback = function() vim.treesitter.start() end,
})
```

- 例の後の説明に、`emet` は関数を書くファイル（`.emet`）のための指定であることを書き足す。今の「要らなければ `{ "golem" }` だけにします」は、「関数を書かなければ `"emet"` を、補完が要らなければ `"toml"` を除けます」の形に直す。
- 色付けの部分の説明として、`:TSInstall golem emet` で入れること、nvim-treesitter（main ブランチ）と C コンパイラーが要ること、`revision` を書かなければ Golem の最新の文法を入れ、`:TSUpdate` のたびに入れ直すことを、使い手に向けた言葉で書く。`queries` がリポジトリのルートからのパスであることのような仕組みの説明は、使い手のマニュアルには書かず、`tools/editors/README.md` に任せる。
- 「LSP が動く前の色付け」の節は、Neovim の例を指すように直す。nvim-treesitter を使わずに入れる方法は、開発者のマニュアルにあることを一文で書く。

### 開発者のマニュアルの「エディタ向けの構文の定義」

開発者のマニュアルの LSP の章（`manual-dev/part1/04-lsp.gm`）の「エディタ向けの構文の定義」の節に、nvim-treesitter を使わずに、パーサーを C コンパイラーで共有ライブラリにして、問い合わせと一緒に `runtimepath` の下に写す手順を載せる（「決めたことの記録」）。
内容は `tools/editors/README.md` の同じ手順と同じにする。
開発者のマニュアルの読み手（社内の技術者）が、nvim-treesitter のない環境や、手元の写しの文法を試すときに使う。

マニュアルを変えるので、同じプルリクエストで `scripts/visual/pages/manual.txt` と `scripts/visual/pages/manual-dev.txt` を、CI の成果物 `visual-diff` の `pages/` から写して直す。

## 実装しないこと

- Helix、Zed、Visual Studio Code の手順を変えること。確かめていないので、今の記述と「手で確かめる項目」のままにする。
- Golem の文法を nvim-treesitter の文法の一覧に登録すること（[ADR 0170](0170-emet-editor-support.md) の「実装しないこと」のまま）。
- `revision` を例に書くこと。版の固定は、説明の文で示すだけにする。
- メンテナーの dotfiles の設定を変えること。dotfiles のリポジトリの ADR で扱う。

## テスト設計

文書の変更なので、自動のテストは足さない。
実装の後、次のことを実際に動かして確かめ、確かめた結果をプルリクエストに書く。

- 新しい Neovim の設定のディレクトリ（`NVIM_APPNAME` を使い、メンテナーの設定を使わない）に、nvim-treesitter の main ブランチと、`tools/editors/README.md` の例をそのまま写した設定を置き、`:TSInstall golem emet` で文法が入ること。`queries/golem/highlights.scm` と `queries/emet/highlights.scm` が写されること。
- その設定で、`emet-samples` の `text.gm` と `fn/lib.emet` を `nvim --headless` で開き、ファイルタイプが `golem` と `emet` になり、`vim.treesitter.highlighter.active` にそのバッファがあり、見出しの `#` などの位置に表の捕捉が付くこと。
- `:TSUpdate` の後に、二つの文法が入れ直されること（`revision` を書かない場合の記述を確かめる）。
- `manual/chapters/09-editor.gm` の LSP の設定の例をそのまま写した設定で、`emet-samples` の `fn/lib.emet` を開き、Golem の LSP のクライアントが付き、`textDocument/documentSymbol` が空でない結果を返すこと。
- 使い手のマニュアルの Neovim の設定の例をそのまま写した設定で、上の二つ（文法が入って色付けが始まること、LSP のクライアントが付くこと）が同時に成り立つこと。
- 開発者のマニュアルの手でコンパイルして写す手順をそのまま実行し、`nvim-treesitter` のない設定（`NVIM_APPNAME` の新しいディレクトリ）で `.gm` と `.emet` に捕捉が付くこと。
- `golem check manual`、`golem check manual-dev` と、CI の `manual`、`visual`、`textlint` のジョブが通ること。

## トレードオフ

GitHub から入れる例を推奨にするので、使い手はリポジトリを clone せずに色付けを得られる。
その代わり、`revision` を書かない例は Golem の `main` の先頭を入れるので、使い手の手元の `golem` の版と、文法の版がずれることがある。
文法は、構文を変える ADR と同じプルリクエストで変えるので、`golem` より新しい文法を入れると、まだ手元の `golem` が受け付けない構文にも色が付く。
害は色付けにとどまり、diagnostics は手元の `golem` の LSP が出す。

例は nvim-treesitter の main ブランチの書き方に依存する。
nvim-treesitter が `install_info` の書き方を変えれば、README と使い手のマニュアルの例を直し、マニュアルの見た目の参照も直すことになる。
確かめた nvim-treesitter のコミットを README に書いておき、変わったときに気付けるようにする。

使い手のマニュアルに Neovim の長い例を載せるので、Neovim を使わない読み手にとっては読み飛ばす部分が増える。
LSP と構文の色付けは、エディタで原稿を書くための前提であり、設定を一か所で写せることを優先した。

手でコンパイルして写す手順を README と開発者のマニュアルの二か所に書くので、変えるときは二か所を直す。

## 決めたことの記録

- **README とマニュアルの更新**（2026-11-06、メンテナー）：`tools/editors/README.md` の Neovim の節に GitHub から文法を入れる nvim-treesitter の例を、`manual/chapters/09-editor.gm` の LSP の設定の例に `emet` を足すよう求め、実装の前に ADR を作ってレビューを受けるとした。
- **使い手のマニュアルに tree-sitter の例を載せること**（2026-11-06、メンテナー）：載せるとした。LSP も構文の色付けもない開発は、今の開発ではないからである。
- **手でコンパイルして写す方法**（2026-11-06、メンテナー）：README に残し、開発者のマニュアルにも入れるとした。
- **`FileType` で色付けを始める例**（2026-11-06、メンテナー）：README の例に含めるとした。

## メンテナーが決めること

すべて決めた（「決めたことの記録」）。

1. **使い手のマニュアルに tree-sitter の例を載せるか**：載せる。LSP の設定の例と同じ例に並べる。
2. **README の例の置き方**：GitHub から入れる例を最初に置き、手でコンパイルして写す方法を nvim-treesitter を使わない場合として後に残す。同じ手順を開発者のマニュアルにも載せる。
3. **`FileType` で色付けを始める例を README の例に含めるか**：含める。使い手のマニュアルの例にも含める。

## 参考文献

- nvim-treesitter（main ブランチの `e289100`）、`README.md` の「Adding custom languages」と [`lua/nvim-treesitter/install.lua`](https://github.com/nvim-treesitter/nvim-treesitter/blob/e289100ff98969e118c702199d88b764ce9e7fdf/lua/nvim-treesitter/install.lua)
- [ADR 0170](0170-emet-editor-support.md)、[ADR 0162](0162-calling-emet-functions-from-gm.md)
- Neovim の help、`:help vim.treesitter.start()`、`:help vim.filetype.add()`、`:help vim.lsp.config()`
