# ADR 0231: LSP とエディタの文法を、ヘッドレスの Neovim と Helix で CI で確かめる

ステータス: 採択（未実装）

## 文脈

[docs/roadmap.md](../roadmap.md) の「手で確かめる項目」のうち、五つがエディタに関わる。

| 項目 | 確かめること | ADR |
| --- | --- | --- |
| エディタ向けの構文の定義の読み込み | README の手順で、Visual Studio Code、Sublime Text、TextMate、Helix、Zed が文法を読むこと | [ADR 0170](0170-emet-editor-support.md)、[ADR 0171](0171-neovim-setup-from-github-and-emet-lsp.md) |
| LSP の位置の扱い | UTF-8 の位置の交渉と、行の長さを超える列の丸めが、Neovim で働くこと | [golem-lsp ADR 0002](../golem-lsp/adr/0002-utf8-position-encoding.md)、[golem-lsp ADR 0003](../golem-lsp/adr/0003-position-handling.md) |
| LSP の notice | notice が Information として表示され、問題の一覧に載り、`silence-notices` に加えて保存すると消えること | [golem-syntax ADR 0002](../golem-syntax/adr/0002-notice-severity.md) |
| コマンドの中の空白の semantic tokens の見え方 | 空白（型は `operator`）に、本人のテーマで背景や下線が出ないこと | [golem-lsp ADR 0008](../golem-lsp/adr/0008-semantic-tokens-for-whitespace-and-remaining-punctuation.md) |
| style.toml と preflight.toml の補完 | ふつうに起動した Neovim で候補の一覧が出ること、引用符の中で選んだ候補が正しく入ること、`manifest.toml` とルートの外の TOML で何も出ないこと | [ADR 0169](0169-lsp-completion-in-style-and-preflight-toml.md) |

### 今の自動のテストが届く範囲

サーバーの側は、すでにプロトコルの水準で確かめている。
golem-lsp のテストは `lsp-test` でサーバーと JSON-RPC をやりとりし（[`modules/golem-lsp/test/Main.hs` の 572 行](https://github.com/tett23/golem/blob/683744442737c02e86e700e26b6f1b9b95277aef/modules/golem-lsp/test/Main.hs#L572)）、位置の符号化の選び方（同じファイルの 483 行から 490 行）と、行の末尾を超える列の丸め（431 行）を調べている。
notice の抑制は golem-syntax のテストが調べている。
文法の側は、`tools/editors/test.sh` が tree-sitter と `vscode-tmgrammar-test` で調べている（[`ci.yml` の `editors`](https://github.com/tett23/golem/blob/683744442737c02e86e700e26b6f1b9b95277aef/.github/workflows/ci.yml#L926-L950)）。

残っているのは、クライアントの側である。
サーバーが UTF-8 を選んでも、Neovim の組み込みのクライアントがそれを受けて `offset_encoding` を `utf-8` にするか、範囲の外の列を Neovim がどう描くかは、サーバーのテストからはわからない。
notice の severity が 3（Information）で送られることはテストで確かめられるが、`vim.diagnostic` がそれを INFO として扱い、quickfix に載せるかは Neovim の振る舞いである。

### Neovim はヘッドレスで確かめられる

ここが、これらの項目を手で確かめる項目に置いた前提と食い違う。
[ADR 0171](0171-neovim-setup-from-github-and-emet-lsp.md) は README の手順を `nvim --headless` で確かめ、[golem-lsp ADR 0005](../golem-lsp/adr/0005-keystroke-latency-and-ordered-evaluation.md) は `nvim --headless --listen` に RPC の `nvim_input` で日本語を送ってキー入力の遅れを測った。
どちらも手元で一度走らせただけで、CI には入っていない。

ヘッドレスの Neovim でも、LSP のクライアントは動き、`vim.diagnostic.get`、`vim.lsp.get_clients`、`vim.lsp.semantic_tokens.get_at_pos`、`nvim_get_hl` は値を返す。
補完の候補の一覧は描く画面がないが、`vim.ui_attach` で `ext_popupmenu` を受け取れば、一覧に出た項目を Lua の値として読める。
ふつうに起動した Neovim との違いは、端末に描くかどうかだけになる。

Neovim は、GitHub の neovim/neovim のリリースに Linux の x86-64 の tar.gz を置いている。
ライセンスは Apache License 2.0 と Vim のライセンスで、CI のランナーで使うことに妨げはない。

### Helix もヘッドレスで文法を読む

Helix は `hx --grammar build` で `languages.toml` の文法をコンパイルし、`hx --health <言語>` で、その言語の文法と問い合わせのファイルが見つかるかを書く。
GitHub の helix-editor/helix のリリースに Linux の x86-64 のアーカイブがあり、ライセンスは MPL 2.0 である。

### 残りのエディタ

Visual Studio Code は、TextMate の文法を `vscode-textmate` で読む。
`vscode-tmgrammar-test` も同じ `vscode-textmate` で文法を読むので、文法そのものは今の `editors` ジョブが確かめている。
README の `package.json` の形で拡張機能として読むことは、VS Code（か VSCodium）を Xvfb の上で `@vscode/test-electron` から起動すれば確かめられるが、エディタ本体を毎回取ることになる。

Sublime Text と TextMate は、GUI のアプリケーションの中でしか文法を読まない。
Sublime Text はプロプライエタリであり、TextMate は macOS のアプリケーションである。
Zed は拡張機能を GUI から入れ、ヘッドレスで文法を読ませる手段を持たない。
この三つは CI で確かめられない。

## 実装すること

### 1. ヘッドレスの Neovim のテスト

`tools/editors/nvim/` に、Lua のテストと、それを走らせる `test.sh` を置く。

`test.sh` は、`GOLEM`（golem の実行ファイル）と `NVIM`（Neovim の実行ファイル）を受け取り、`nvim --headless --clean -u <テストの init.lua>` でテストを一つずつ走らせる。
`--clean` で、走らせる人の設定を読まない。
テストは失敗を `vim.cmd.cquit(1)` で返す。
各テストは、`modules/golem-lsp/test/fixtures/` の写しを一時ディレクトリに作って開く。

テストは次のとおりである。

- **位置の符号化**：`golem lsp` に付いたクライアントの `offset_encoding` が `utf-8` であること。`general.positionEncodings` に `utf-16` だけを渡した `vim.lsp.start` では `utf-16` であること。
- **列の丸め**：日本語と 4 バイトの文字を含む行に diagnostic が出る原稿を開き、`vim.diagnostic.get` の `col` と `end_col` が、その行のバイト数を超えないこと。
- **notice**：notice を出す原稿で、その diagnostic の `severity` が `vim.diagnostic.severity.INFO` であり、`vim.diagnostic.setqflist()` の後の `getqflist()` に載ること。`style.toml` の `silence-notices` にそのコードを加えて `:write` した後、diagnostic が消えること。
- **空白の semantic tokens**：コマンドと式の中の空白の位置で、`vim.lsp.semantic_tokens.get_at_pos` の型が `operator` であること。その位置に当たる強調のグループを `nvim_get_hl(0, { name = ..., link = false })` で解決し、既定の色の組で `bg`、`underline`、`undercurl` を持たないこと。
- **TOML の補完**：`vim.lsp.completion.enable` で補完を有効にし、`vim.ui_attach` で `ext_popupmenu` を受ける。`style.toml` と `preflight.toml` で補完を起こすと一覧に候補が出ること。引用符を付けた候補を選ぶ場合と、開いた引用符の中で選ぶ場合のそれぞれで、`nvim_buf_get_lines` の行が期待の文字列になること。`manifest.toml` とルートの外の TOML で、一覧が出ないこと。
- **README の手順**：[ADR 0171](0171-neovim-setup-from-github-and-emet-lsp.md) の確かめ（手元の写しから `cc` でパーサーを作り、`text.gm` と `fn/lib.emet` のファイルタイプが `golem` と `emet` になり、tree-sitter の色付けが始まること）を、README の `path` の手順で走らせる。nvim-treesitter を GitHub から取る手順は、外のリポジトリを取ることになるので入れない。

本人のテーマと端末（Ghostty）は、走らせる人が `NVIM_APPNAME` と自分の設定で同じ `test.sh` の空白のテストだけを走らせられるようにする（`--theme` の引数で `--clean` を外す）。
CI は既定の色の組だけを確かめる。

### 2. Neovim の取得

`tools/editors/fetch-nvim.sh` を足す。
版（[ADR 0171](0171-neovim-setup-from-github-and-emet-lsp.md) が確かめた 0.12.6）と、Linux の x86-64 と macOS の arm64 のアーカイブの SHA-256 をスクリプトに書き、取ったアーカイブをその SHA-256 で検査してから展開する。
リリースの `shasum.txt` は読まない（同じリリースの一覧は、差し替えられたアーカイブについて何も言わないので。`fetch-shem.sh` と同じ扱い）。

### 3. Helix のテスト

`tools/editors/helix/test.sh` を足す。
`fetch-nvim.sh` と同じ形で Helix のアーカイブを版と SHA-256 で取り、README の `languages.toml` の例を、`<editors>` を置き換えて一時ディレクトリの設定に書く。
`HELIX_RUNTIME` をアーカイブの `runtime/` にし、`hx --grammar build` が成功すること、`hx --health golem` と `hx --health emet` が文法と強調の問い合わせを見つけたと書くことを確かめる。

### 4. CI

`ci.yml` にジョブ `editors-lsp` を足す。

- `build (ubuntu-24.04, outputs)` が `golem` の実行ファイルを成果物 `golem-linux-x86_64` として上げる。`visual` と同じく `scripts/visual/wait-pdfs.sh` でそれを待ち、`build` の全体を待たない（[ADR 0099](0099-visual-job-waits-only-for-visual-pdfs.md)）。
- Neovim と Helix のアーカイブは、版と SHA-256 をキーにキャッシュする。
- 1 と 3 のテストを走らせる。
- `ci` の `needs` に加える。

Helix のテストは golem を要らないので、今の `editors` ジョブに置く。

### 5. ロードマップと文書

- 「LSP の位置の扱い」「LSP の notice」「style.toml と preflight.toml の補完」を外す。
- 「コマンドの中の空白の semantic tokens の見え方」は、本人のテーマと Ghostty で見ることだけを残す。手元で `tools/editors/nvim/test.sh --theme` を走らせる手順を書く。
- 「エディタ向けの構文の定義の読み込み」から Helix、Sublime Text、TextMate、Zed を外し、Visual Studio Code だけを残す。`tools/editors/README.md` の Sublime Text、TextMate、Zed の手順は消さず、確かめていない手順であることを書く（「決めたことの記録」）。
- `tools/editors/README.md` の「テスト」の節に、1 と 3 を足す。

## 実装しないこと

- Visual Studio Code を CI で起動すること（「メンテナーが決めること」の 3）。
- Sublime Text、TextMate、Zed を確かめること。CI でも手でも確かめない。メンテナーが使うエディタ（Aleph、Neovim、Visual Studio Code）に検証を絞る（「決めたことの記録」）。
- nvim-treesitter を GitHub から取る手順を CI で走らせること。外のリポジトリの main の先頭に結果が左右される。
- 端末の描画（Ghostty の上で、色がどう見えるか）を確かめること。強調のグループの属性までで止める。

## 不変条件

| 番号 | 不変条件 |
| --- | --- |
| I1 | `utf-8` を申し出る Neovim のクライアントに付いた golem lsp は、そのクライアントの `offset_encoding` を `utf-8` にする。 |
| I2 | Neovim が受け取った golem lsp の diagnostic の列は、その行のバイト数を超えない。 |
| I3 | golem lsp の notice は、Neovim で INFO の diagnostic になり、`silence-notices` にそのコードを書いて保存した後は出ない。 |
| I4 | コマンドと式の中の空白には、既定の色の組で、背景も下線も付かない。 |
| I5 | `style.toml` と `preflight.toml` の補完は、引用符の内でも外でも、選んだ後の行が期待の文字列になる。`manifest.toml` とルートの外の TOML には候補を出さない。 |
| I6 | README の Helix の `languages.toml` の例で、`hx --grammar build` が成功する。 |

## テスト設計

1 と 3 のテストは、先に書いて失敗させる。
失敗させる方法は、テストごとに、期待を一つ反転したもの（`utf-8` の代わりに `utf-16` を期待する、など）で走らせ、`test.sh` が終了コード 1 と、そのテストの名前を書くことを確かめる。
この反転は、`tools/editors/nvim/test.sh --self-test` として残し、`editors-lsp` ジョブで走らせる。
反転しても通るテストは、何も確かめていないので、`--self-test` が失敗にする。

README の例とテストがずれないように、Helix の `languages.toml` と Neovim の `init.lua` の例は、README のコードブロックから `test.sh` が切り出して使う。
README の例を変えると、テストも同じものを走らせる。

## トレードオフ

`editors-lsp` は、`build (ubuntu-24.04, outputs)` の成果物を待つ。
2026-11-08 の `main` の run 42444096822 では、この runner は始まりから 4 分 45 秒で終わり、実行の全体は `build (ubuntu-24.04, env)` と `verapdf` を待って 8 分 34 秒かかった。
Neovim のテストが数十秒で終われば、`editors-lsp` は臨界経路に入らない。
ただし、この実行の全体は CONTRIBUTING の 5 分をすでに超えている。
この ADR が延ばすものではないが、実装のプルリクエストで `scripts/ci/timings.sh` の値を取り、`editors-lsp` が最後に終わるジョブにならないことを確かめる。

golem の実行ファイルを成果物にすると、その保存と取得に数秒かかる。
`visual` の PDF と同じ扱いであり、量は一つの実行ファイルである。

Neovim の版を固定すると、利用者の手元の版とずれていく。
README の例を確かめた版は README に書いてあるので、版を上げるときは README とスクリプトを同じプルリクエストで直す。

Neovim の文書は、`vim.ui_attach` を実験的な API と書いている。
版を上げて振る舞いが変わったら、補完のテストが失敗するので、そのとき直す。

## メンテナーが決めること

1. **Neovim のテストを走らせる場所**：推奨は、`outputs` の runner の golem を待つ別のジョブにすることである。待つ形は `visual` と同じで、`outputs` の runner の時間を延ばさない。
   - 退けた案の一つは、`build (ubuntu-24.04, outputs)` のステップに足すことである。その runner が終わるのが遅れ、`visual` と `wasm` の待ちも延びる。
   - 二つめは、`schedule` の夜間のジョブにすることである。LSP を変えたプルリクエストが、マージの後まで失敗を知らない。
2. **本人のテーマの扱い**：推奨は、CI は既定の色の組だけを確かめ、本人のテーマは手元で同じスクリプトを走らせることである。テーマは dotfiles にあり、リポジトリに入れるものではない。
   - 退けた案は、本人のテーマをリポジトリに写して CI で確かめることである。テーマの変更がリポジトリの変更を要するようになる。
3. **Visual Studio Code**：推奨は、CI で起動せず、手で確かめる項目に残すことである。文法は `vscode-textmate` で確かめており、残るのは README の `package.json` を VS Code が読むことだけである。そのために、エディタ本体と Xvfb を CI に入れるのは見合わない。
   - 退けた案の一つは、VSCodium（MIT）を `@vscode/test-electron` で起動することである。エディタ本体のアーカイブの取得と Xvfb が要り、得るのは `contributes.grammars` の三行が読まれることだけである。
   - 二つめは、README の `package.json` が JSON として読めて `path` の先があることだけを `tools/editors/test.sh` で調べることである。安いが、VS Code が読むことは確かめない。推奨の案と並べて足してもよい。
4. **残りの GUI のエディタ**：推奨は、Sublime Text、TextMate、Zed を手で確かめる項目に残し、確かめた人と版を README に書いたら外すことである。CI で動かす手段がない。

## 決めたことの記録

- **「メンテナーが決めること」の 1 から 3**（2026-11-08、メンテナー）：推奨のとおりとした。
- **「メンテナーが決めること」の 4**（2026-11-08、メンテナー）：推奨を採らず、Sublime Text、TextMate、Zed を検証の対象から外した。手で確かめる項目にも残さない。メンテナーが使うエディタは Aleph、Neovim、Visual Studio Code であり、検証はそれに絞る。対応するエディタは後に増やす（時期は決めていない）。増やすときに、そのエディタの確かめ方を決める。Aleph は LSP を使うので、この ADR の LSP のテスト（1）が Golem の側を確かめ、Aleph の側は Aleph のリポジトリが確かめる。
## 参考文献

- Neovim, Lua API（`vim.ui_attach`、`vim.lsp.completion`、`vim.lsp.semantic_tokens`）, https://neovim.io/doc/user/lua.html
- Neovim, LSP, https://neovim.io/doc/user/lsp.html
- Helix, Adding languages, https://docs.helix-editor.com/guides/adding_languages.html
- Visual Studio Code, Testing Extensions, https://code.visualstudio.com/api/working-with-extensions/testing-extension
