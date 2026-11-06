# エディタ向けの構文の定義

Golem の原稿（`.gm`）と、関数を書く言語 Emet（`.emet`）の構文の定義を置く（[docs/adr/0170](../../docs/adr/0170-emet-editor-support.md)）。
色付けは LSP（`golem lsp`）の semantic tokens も行うが、LSP が動き出すまでのあいだと、LSP を使わないエディタでは色が付かない。
ここの定義は、その間のためのものである。
LSP の色付けに対応したエディタでは、LSP が動き出すと LSP の色が優先される。

リリースのアーカイブでは、同じものが `share/golem/editors/` に入る（テストは入らない）。
以下のパスは、このディレクトリ（またはアーカイブの `share/golem/editors/`）からの相対パスである。

## 置いてあるもの

| パス | 中身 |
| --- | --- |
| `textmate/golem.tmLanguage.json` | `.gm` の TextMate の文法（スコープ `source.golem`） |
| `textmate/emet.tmLanguage.json` | `.emet` の TextMate の文法（スコープ `source.emet`） |
| `tree-sitter-golem/`、`tree-sitter-emet/` | tree-sitter の文法。`grammar.js`、生成した `src/parser.c` と `src/grammar.json`、外部のスキャナー `src/scanner.c`、色付けの問い合わせ `queries/highlights.scm` |
| `test/sample.gm`、`test/sample.emet` | 二つの形式が共有する見本の原稿。行の下に TextMate のスコープを書いた vscode-tmgrammar-test の形式 |
| `test/classes.test.js` | 見本の同じ要素が、二つの形式で同じ分類になることのテスト |
| `test.sh` | すべてのテスト（CI の `editors` ジョブも同じものを実行する） |
| `package.json`、`package-lock.json` | テストの道具 tree-sitter-cli 0.27.1 と vscode-tmgrammar-test 0.1.3（どちらも MIT）を正確な版で固定する |
| `tree-sitter-cli.sha256` | tree-sitter-cli が GitHub のリリースから取る実行ファイルの SHA-256 |

構文の定義そのものは、Node も tree-sitter-cli も要らない。
Node と `package.json` はテストのためだけにある。

## 色の分類

分類は semantic tokens と同じにする（`.gm` は [golem-lsp ADR 0006](../../docs/golem-lsp/adr/0006-semantic-tokens-highlighting.md)、`.emet` は [docs/adr/0170](../../docs/adr/0170-emet-editor-support.md) の表）。
semantic tokens の型ごとに、次のスコープと捕捉の名前で書く。

| semantic tokens の型 | TextMate のスコープ | tree-sitter の捕捉の名前 |
| --- | --- | --- |
| `comment` | `comment.line` | `@comment` |
| `keyword` | `keyword.control` | `@keyword` |
| `function` | `entity.name.function` | `@function` |
| `decorator` | `entity.name.tag` | `@attribute` |
| `parameter` | `variable.parameter` | `@variable.parameter` |
| `variable` | `variable.other` | `@variable` |
| `type`、`typeParameter` | `entity.name.type` | `@type` |
| `enumMember` | `constant.other` | `@constructor` |
| `namespace` | `entity.name.namespace` | `@module` |
| `string` | `string.quoted`（`.gm` の引数の語は `string.unquoted`） | `@string` |
| `number` | `constant.numeric` | `@number` |
| `operator` | `keyword.operator` | `@operator` |
| `macro` | `constant.character.escape`（`.gm`）、`storage.modifier`（`.emet`） | `@string.escape`（`.gm`）、`@keyword.modifier`（`.emet`） |

捕捉の名前は nvim-treesitter の標準の名前である。
TextMate の文法は行ごとの正規表現なので、次の点で粗い。

- `.gm` の見出しは、行の全体が `markup.heading` になる。見出しの文字を `namespace` として区別するのは tree-sitter の文法だけである。
- `.emet` の関数の適用の先頭の名前（`f x` の `f`）は `variable.other` になる。`function` になるのは宣言の名前だけである。
- `.emet` のレコードのパターン（`Book { title = t }`）は、`=` から先を式として色付けする。

ほかに、二つの形式とも、次の点で semantic tokens と違う。

- `.gm` の `[= book.total(xs)]` の名前空間付きの呼び出しは、`book` と `total` の両方を `function` にする。semantic tokens は最初の `book` だけを `function` にする。

## tree-sitter の文法と Golem の構文解析の違い

tree-sitter の文法は、Golem の構文解析（`modules/golem-parser/grammar/Golem.hpeg` と `modules/golem-emet/grammar/Emet.hpeg`）とは別に書いたものである。
Golem が受け付ける原稿は受け付けるように書き、テストの原稿と二つのマニュアルのすべての `.gm` と `.emet` を読めることを CI で確かめている。
逆に、Golem が誤りとする原稿の一部も受け付ける。

- `.gm` の字下げは、外部のスキャナーが深さの列として持つ。Golem はブロックの本体を 2 つ深い字下げに限るが、ここではどの深さでも本体とし、本体の前の空行も許す。
- `.gm` の段落の続きの行、リストの項目の続きの行、散文スロットの中の改行は、スキャナーが決める（空行を挟まず、そのブロックの文字の位置か、それより深い位置から始まり、ブロックの始まりの文字で始まらない行）。改行の様式と空行の様式は、同じ木になる。
- `.gm` のブロックへの属性（`@style` の直後の段落）は、木の上ではただの兄弟のブロックである。定義リストの用語に本体がなくてもよい。
- `.gm` の `#` の後に空白がない行、`@set` の後に `=` がない行、予約した記法（`[!`、`@!`、`..`）は、Golem の診断のとおりには扱わない。
- `.emet` の改行は、外部のスキャナーが、パーサーが区切りを受け取れる位置で、次の行が `|`、`-` を除く二項演算子、`?`、`:`、`where`、`->` で始まらないときだけ区切りにする。括弧の中や演算子の後の改行は空白である。Golem の規則（`Sp(True)` と `SpN`）に合わせている。
- `.emet` の三項演算子の真の枝は、Golem と同じく最上位に `:` を持たない（`c ? x : xs : ys` は `c ? x : (xs : ys)`）。
- `.emet` の使えない予約語（`if`、`let` など）は、名前として読む。

## エディタでの使い方

`<editors>` は、このディレクトリかアーカイブの `share/golem/editors/` のパスとする。
Neovim の手順は Neovim 0.12.6 で確かめた。
nvim-treesitter を使う手順は、nvim-treesitter の main ブランチの `e289100` で確かめた。
ほかのエディタの手順は、まだ実際のエディタで確かめていない（[docs/roadmap.md](../../docs/roadmap.md) の「手で確かめる項目」）。

### Neovim

tree-sitter の文法を使う。
nvim-treesitter（main ブランチ）を使っている場合は、`init.lua` に次のように書き、`:TSInstall golem emet` で GitHub から文法を入れる。

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

- 手元に Golem を clone しなくてよい。nvim-treesitter が GitHub からリポジトリを落とし、`location` のディレクトリでパーサーをコンパイルする。nvim-treesitter の main ブランチの要件のとおり、コンパイルには tree-sitter の CLI（`tree-sitter build`）と C コンパイラーが要る。
- nvim-treesitter は色付けを自動では始めないので、`FileType` で `vim.treesitter.start()` を呼ぶ。
- `queries` は `location` からではなく、リポジトリのルートからのパスで書く。nvim-treesitter は、落として展開したリポジトリのルートに `queries` を連結して、問い合わせを写すからである。
- `revision` を書かなければ、`main` の先頭を入れる。そのときは、`:TSUpdate` のたびに入れ直す。版を固定したいときは、`install_info` の `revision` にタグかコミットを書く。
- この例は、Neovim 0.12.6 と、nvim-treesitter の main ブランチの `e289100`（`e289100ff98969e118c702199d88b764ce9e7fdf`）で確かめた。nvim-treesitter が `install_info` の書き方を変えたら、この例も直す。

手元の写し（リポジトリかリリースのアーカイブ）から入れる場合は、`url` の代わりに `path` をその写しの文法のディレクトリ（`<editors>/tree-sitter-golem` と `<editors>/tree-sitter-emet`）にし、`location` を除く。
`path` のときも、`queries` は `location` ではなく `path` からのパスで書くので、ここでは `queries = 'queries'` になる。
`path` から入れるときは、問い合わせを写さずにリンクを張り、パーサーはそのディレクトリに `parser.so` としてコンパイルしてから写す。

nvim-treesitter を使わない場合は、パーサーを C コンパイラーで共有ライブラリにして、問い合わせと一緒に `runtimepath` の下に置く。

```sh
SITE=~/.local/share/nvim/site
mkdir -p "$SITE/parser" "$SITE/queries/golem" "$SITE/queries/emet"
for g in golem emet; do
  cc -shared -fPIC -O2 -I "<editors>/tree-sitter-$g/src" \
    "<editors>/tree-sitter-$g/src/parser.c" \
    "<editors>/tree-sitter-$g/src/scanner.c" \
    -o "$SITE/parser/$g.so"
  cp "<editors>/tree-sitter-$g/queries/highlights.scm" "$SITE/queries/$g/"
done
```

`init.lua` には、上の例の `vim.filetype.add` と `FileType` の部分だけを書き、ファイルタイプを決めて tree-sitter の色付けを始める。

```lua
vim.filetype.add({ extension = { gm = 'golem', emet = 'emet' } })
vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'golem', 'emet' },
  callback = function() vim.treesitter.start() end,
})
```

### Visual Studio Code

TextMate の文法を、手元の拡張機能として読み込ませる。
`~/.vscode/extensions/golem-syntax/` に `package.json` を置き、同じディレクトリに `textmate/` を写す。

```json
{
  "name": "golem-syntax",
  "version": "0.0.1",
  "engines": { "vscode": "^1.80.0" },
  "contributes": {
    "languages": [
      { "id": "golem", "extensions": [".gm"] },
      { "id": "emet", "extensions": [".emet"] }
    ],
    "grammars": [
      { "language": "golem", "scopeName": "source.golem", "path": "./textmate/golem.tmLanguage.json" },
      { "language": "emet", "scopeName": "source.emet", "path": "./textmate/emet.tmLanguage.json" }
    ]
  }
}
```

### Sublime Text と TextMate

どちらも TextMate の文法を読むが、JSON の形式ではなく plist の形式（`.tmLanguage`）を読む。
JSON から plist に変換して（Sublime Text なら PackageDev のパッケージで変換できる）、Sublime Text は `Packages/User/` に、TextMate はバンドルの `Syntaxes/` に置く。

### Helix

tree-sitter の文法を使う。
`~/.config/helix/languages.toml` に言語と文法を足し、`hx --grammar build` でパーサーを作る。
問い合わせは `~/.config/helix/runtime/queries/golem/highlights.scm`（`.emet` は `emet`）に写す。

```toml
[[language]]
name = "golem"
scope = "source.golem"
file-types = ["gm"]
roots = ["manifest.toml"]

[[grammar]]
name = "golem"
source = { path = "<editors>/tree-sitter-golem" }
```

`.emet` も同じく、`name = "emet"`、`file-types = ["emet"]`、`tree-sitter-emet` で足す。
捕捉の名前は nvim-treesitter の名前なので、Helix のテーマが知らない名前（`@module`、`@number`、`@string.escape`、`@keyword.modifier`）には色が付かないことがある。

### Zed

Zed は、tree-sitter の文法を拡張機能として読む。
手元の拡張機能（dev extension）の `extension.toml` の `[grammars.golem]` に、このディレクトリを含む Git のリポジトリとコミットを書き、`languages/golem/` に `config.toml`（`name = "Golem"`、`grammar = "golem"`、`path_suffixes = ["gm"]`）と `highlights.scm` を置く。
`.emet` も同じく足す。

## テスト

リポジトリのどこからでも、次を実行する。

```sh
sh tools/editors/test.sh
```

初めての実行で `npm ci` がパッケージを `node_modules/` に入れる。
tree-sitter-cli の npm のパッケージは、インストールのときに GitHub の tree-sitter/tree-sitter のリリースから実行ファイルを取るが、そのハッシュを検査しない。
`test.sh` は、実行ファイルを動かす前に、その SHA-256 を `tree-sitter-cli.sha256` と照合する。
固定しているのは Linux の x86-64 と macOS の arm64 の二つで、ほかの環境では `test.sh` が止まる。
C コンパイラー（`cc`）も要る。

`test.sh` は次を確かめる。

1. コミットした `src/` が、`grammar.js` から生成したものと一致する（Golem の文法の `Generated.hs` と同じ扱い）。
2. `tree-sitter test` で、構文木のテスト（`test/corpus/`）と、行の下に捕捉の名前を書いた色付けのテスト（`test/highlight/`）が通る。
3. `vscode-tmgrammar-test` で、見本の `test/sample.gm` と `test/sample.emet` の行の下に書いたスコープが付く。
4. 同じ見本の同じ要素について、TextMate の文法の最も内側のスコープと、tree-sitter の問い合わせの最も内側の捕捉が、上の表で同じ分類になる。
5. `modules/golem-driver/test/fixtures/`、`manual/`、`manual-dev/` のすべての `.gm` と `.emet` を、tree-sitter が `ERROR` と `MISSING` のノードなしに読める。

文法を変えたら、そのディレクトリで `../node_modules/.bin/tree-sitter generate` を実行し、生成した `src/` もコミットする。
`.gm` か `.emet` の構文を変えるときは、Golem の文法、semantic tokens、ここの二つの形式を合わせて変える。
