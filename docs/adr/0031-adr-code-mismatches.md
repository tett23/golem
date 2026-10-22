# ADR 0031: ADR とコードの四つの食い違いを、どちらに合わせるか

ステータス: 採択

## 文脈

ロードマップの「ADR とコードの食い違い」は、採択済みの ADR とコードが食い違う箇所を四つ挙げ、どちらに合わせるかを決めて直す、としている。

1. `overridableCommands` に `code` が入っている。
2. LSP の補完に、プラグインのコマンドの名前が出ない。
3. `golem inspect` のオプションの書き方が ADR と違う。
4. ホストが `golem_dealloc` を一度も呼ばない。

どれも main（e3e19da）のコードと文書で確かめた。
四つは別々のモジュールにまたがるが、どれも「ADR とコードのどちらを正とするか」という同じ種類の判断であり、それぞれの変更は小さいので、一つの ADR にまとめる。

### 1. 上書きできる組み込みのコマンド

[golem-eval ADR 0002](../golem-eval/adr/0002-file-evaluation.md) の「コマンドの解決」は、プラグインが上書きできるコマンドを `strong`、`bold`、`italic`、`ruby`、`kenten`、`color`、`style`、`tcy`、`number-text` の九つとし、上書きできないコマンドとして `ref-number`、`ref-title`、`note`、`sidenote`、`index`、`cite` を挙げている。

今のコードは、[docs/adr/0027](0027-exhaustive-command-dispatch-by-types.md) のとおり、上書きの可否を型で表す。
golem-eval の `Golem.Eval.Builtin` の `OverridableBuiltin` は十の構築子を持ち、`BCode`（`code`）を含む。
`FixedBuiltin` は、上の六つに `ref-page` と `aki` を加えた八つである。
`overridableCommands` は `OverridableBuiltin` から導くので、`code` を含む。
[docs/adr/0027](0027-exhaustive-command-dispatch-by-types.md) は、型に移す前の一覧（`code` を含む十）をそのまま保つと定めただけで、`code` を入れるかどうかは決めていない。

`code` が一覧に入ったのは、`[code: ...]` を加えたコミット（d10d454）である。
このコミットは `builtinInlineCommands` と `overridableCommands` の両方に `code` を足した。
`[code: ...]` を決めた [golem-driver ADR 0017](../golem-driver/adr/0017-pdf-code-blocks.md) は、上書きについて何も書いていない。
`ref-page` と `aki` も、[golem-eval ADR 0002](../golem-eval/adr/0002-file-evaluation.md) より後に加わったコマンドであり、どちらの一覧にも載っていない。

文書の側は次のとおりである。

- 使い手のマニュアルの付録B（`manual/appendices/b-manifest.gm`）は、`overrides` に書ける名前として `code` を含む十を挙げている。
- 開発者のマニュアル（`manual-dev/part1/05-plugins.gm`）は、ADR が九つを挙げ、今の実装が `code` も入れている、と食い違いのまま書いている。
- docs/specifications.md の「プラグイン」は、「表示に関わる組み込みのインラインのコマンド（ルビ、強調など）」とだけ書き、名前を挙げていない。

### 2. LSP の補完とプラグインのコマンド

[golem-lsp ADR 0001](../golem-lsp/adr/0001-language-server.md) は、補完の対象を「コマンドの名前（組み込みとプラグイン）」としている。

golem-lsp の `Golem.Lsp.Features` の `completions` は、コマンドの名前の候補を `builtinInlineCommands` だけから作る。
プラグインのコマンドの名前は、どこからも渡っていない。
golem-driver の `evaluateProject` はプラグインを読み込んで `PluginHook` を作るが、`Evaluated` にはそれを残さない。

さらに、`evaluateProject` は、プロジェクトのどれかのファイルに構文のエラーがあると、プラグインを読み込まずに `noPlugins` で評価する。
LSP は、編集したファイルに構文のエラーがあるとプロジェクトの全体を評価し直す（`Golem.Lsp.Workspace` の `updateFile`）。
`[` を打った直後のファイルは、角括弧が閉じていないので構文のエラーになることが多い。
`Evaluated` にコマンドの名前を足すだけでは、補完が最も求められる場面で、プラグインのコマンドの名前が空になる。

文書の側は次のとおりである。

- docs/specifications.md の「LSP」は「補完（コマンド名、ラベル、import のパス）」と書き、組み込みかどうかを区別していない。
- 使い手のマニュアルの `manual/chapters/09-editor.gm` は「コマンドの名前」と書く。
- 開発者のマニュアルの `manual-dev/part1/04-lsp.gm` は「組み込みのコマンドの名前」と、今の実装のとおりに書く。

### 3. golem inspect のオプション

[golem-cli ADR 0001](../golem-cli/adr/0001-command-line-interface.md) は、`golem inspect <file> [--cst|--ast|--ir]` と、三つの旗のオプションで書いている。

今の golem-cli は、`--as cst|ast|ir` の一つのオプションで受け取り、既定を `cst` とする（`app/Main.hs` の `inspectAsOpt`）。
後から採択した [golem-cli ADR 0004](../golem-cli/adr/0004-usage-error-exit-code.md) は、`--as` を前提に、`--as` の値の誤りを終了コード 2 にすると決めた。
README.md と開発者のマニュアル（`manual-dev/part1/01-cli.gm`、`manual-dev/part1/05-plugins.gm`）も `--as` で書いている。
docs/specifications.md の CLI の表は `golem inspect <file>` とだけ書き、オプションを挙げていない。

調べる途中で、オプションの書き方とは別の食い違いも見つかった。
[golem-cli ADR 0001](../golem-cli/adr/0001-command-line-interface.md) は、`ir` の表示を「意味論 IR（CBOR を人が読める形にしたもの）」とする。
今の `--as ir` は、引数のファイルではなく、作業ディレクトリのプロジェクトのすべてのファイルを評価し、それぞれの `Document` を Haskell の `show` の形で出し、CBOR のバイト数を添える。
この食い違いは、オプションの書き方とは別に、草稿の [golem inspect の診断、終了コード、表示の対象と形を直す](../golem-cli/adr/0007-inspect-output.md) で直す。

### 4. golem_dealloc

[golem-plugin ADR 0001](../golem-plugin/adr/0001-wasm-host-and-abi.md) の「呼び出し規約」は、プラグインが公開する関数に `golem_alloc(len: u32) -> u32` と `golem_dealloc(ptr: u32, len: u32)` を挙げ、「ホストがプラグインのメモリに入力を書くための領域を管理する」としている。

今のホスト（`modules/golem-plugin/cbits/golem_plugin.c` の `golem_plugin_call`）は、一回の呼び出しごとに次の順で動く。

1. ストアとインスタンスを新しく作る。
2. `golem_alloc` に要求の長さを渡し、返った位置に要求の CBOR を書く。
3. `golem_invoke` を呼び、応答の位置と長さを受け取って、応答を読む。
4. ストアを捨てる。

`golem_dealloc` は呼ばず、公開されているかも調べない。
同じ ADR が「呼び出しごとに新しいインスタンスを作り、呼び出しの間で状態を持ち越させない」と決めているので、インスタンスを捨てればメモリもすべて捨てられる。
応答の領域を解放する手段は、ABI にもともとない。
golem-plugin のテストのプラグイン（`modules/golem-plugin/test/plugins/*.wat`）は、何もしない `golem_dealloc` を公開している。
開発者のマニュアル（`manual-dev/part1/05-plugins.gm`）は、ADR が `golem_dealloc` を挙げているが、ホストは呼ばない、と書いている。

### メンテナーが決めたこと

起草の後、メンテナーが次の二つを決めた。

- `aki` と `ref-page` は、今のコードのとおり上書きできないままとする。不都合が見つかれば、rc4 以降で上書きできる側に移してよい。
- `golem inspect --as ir` の表示の食い違いは、docs/specifications.md の「既知の不具合」に加えない。直し方は草稿の [golem inspect の診断、終了コード、表示の対象と形を直す](../golem-cli/adr/0007-inspect-output.md) が決める。

## 実装すること

四つのどれも、ADR とコードの一方を正とし、もう一方をそれに合わせる。

| 食い違い | 正とする側 | 直す側 |
| --- | --- | --- |
| 1. `overridableCommands` の `code` | コード | [golem-eval ADR 0002](../golem-eval/adr/0002-file-evaluation.md) の一覧、文書 |
| 2. LSP の補完 | [golem-lsp ADR 0001](../golem-lsp/adr/0001-language-server.md) | golem-driver、golem-lsp |
| 3. `golem inspect` のオプション | コード | [golem-cli ADR 0001](../golem-cli/adr/0001-command-line-interface.md) の書き方、文書 |
| 4. `golem_dealloc` | コード | [golem-plugin ADR 0001](../golem-plugin/adr/0001-wasm-host-and-abi.md) の呼び出し規約、文書 |

### 1. 上書きできる組み込みのコマンド

上書きできる組み込みのインラインのコマンドを、今の `OverridableBuiltin` の十とする。

- 上書きできる：`strong`、`bold`、`italic`、`code`、`ruby`、`kenten`、`color`、`style`、`tcy`、`number-text`
- 上書きできない：`ref-number`、`ref-title`、`ref-page`、`note`、`sidenote`、`index`、`cite`、`aki`

`code` を上書きできる側に置く理由は次のとおりである。

- `[code: ...]` は `[style code: ...]` の別名である（[golem-driver ADR 0017](../golem-driver/adr/0017-pdf-code-blocks.md)）。同じく `[style 名前: ...]` の別名である `strong`、`bold`、`italic` と、`style` そのものは上書きできる。`code` だけを上書きできないとする理由がない。
- `code` は文字スタイルを付けるだけで、S1 の集約が前提にする番号、ラベル、チャネルを作らない。[golem-eval ADR 0002](../golem-eval/adr/0002-file-evaluation.md) が上書きを禁じた理由は当てはまらない。

`ref-page` を上書きできない側に置くのは、`ref-number`、`ref-title` と同じく、S2 で解決する参照の値を作るからである。
`aki` を上書きできない側に置くのは、今のコードのとおりにするためである。
`aki` は表示だけに関わるコマンドとも言えるが、上書きを許す理由はまだ見つかっていない。
`aki` と `ref-page` の扱いに不都合が見つかれば、rc4 以降の ADR で上書きできる側に移す。
上書きできるコマンドを後から増やしても、今の原稿とプラグインの意味は変わらない。
逆に、上書きできるとしたコマンドを後から上書きできないとすると、それを上書きしていたプラグインが読み込めなくなる。
決めかねるものは、狭い側に置いておく。

コードは変えない。

### 2. LSP の補完にプラグインのコマンドの名前を出す

[golem-lsp ADR 0001](../golem-lsp/adr/0001-language-server.md) のとおり、補完の候補にプラグインのコマンドの名前を出す。

**golem-driver**：

- `Evaluated` に、プラグインのコマンドの名前の欄 `evPluginCommands :: [Text]` を加える。`PluginHook` の `phCommands` のキーを名前に戻し、昇順に並べたものである。上書きのコマンド（`phOverrides`）の名前は組み込みの名前なので、含めない。
- `evaluateProject` は、構文のエラーがあるときも、ないときと同じくプラグインを読み込む。プラグインの読み込みは、`manifest.toml`、`plugins.lock`、キャッシュだけを読み、原稿を読まないからである。
  - 構文のエラーがあるときの `evReevaluate` も、読み込んだフックで評価する。今は `noPlugins` で評価している。
  - 構文のエラーがあるときの `evDiagnostics` に、プラグインの読み込みの診断（G06xxx）も加える。今は、構文のエラーを直すまで、プラグインの誤りが見えない。
  - プラグインの読み込みに失敗したときの `evPluginCommands` は空とする。G02022 を出さない扱い（[golem-plugin ADR 0003](../golem-plugin/adr/0003-plugin-diagnostic-codes.md)）は変えない。

**golem-lsp**：

- `completions` のコマンドの名前の候補を、`builtinInlineCommands` の後に `evPluginCommands` を続けたものにする。`wsEvaluated` がなければ、今と同じく組み込みの名前だけとする。
- 候補の種類は、組み込みと同じ `CkCommand` とする。LSP の `CompletionItemKind` も同じものに写す。

二つのプラグインが同じ名前を提供する場合と、組み込みの名前を宣言なしに提供する場合は、読み込みの時点でエラー（G06006、G06007）になり、フックが作られない。
そのため、候補に同じ名前が二度並ぶことはない。

### 3. golem inspect のオプション

今のコードの `--as cst|ast|ir`（既定は `cst`）を正とする。
`--cst`、`--ast`、`--ir` の旗は設けない。

- 三つは同時に指定できない選択なので、値を一つ取るオプションのほうが、旗を二つ指定した場合の扱いを決めずに済む。
- [golem-cli ADR 0004](../golem-cli/adr/0004-usage-error-exit-code.md) は `--as` を前提に、値の誤りを使い方の誤り（終了コード 2）にすると決めている。
- README.md と開発者のマニュアルは `--as` で書いている。旗に変えると、それらと、`--as` を使うスクリプトがすべて変わる。

コードは変えない。

### 4. golem_dealloc を ABI から外す

`golem_dealloc` を、プラグインが公開する関数の一覧から外す。

- ホストは `golem_dealloc` を呼ばず、公開されているかも調べない。プラグインが公開していても、読み込みと呼び出しには影響しない。
- 入力の領域と応答の領域は、呼び出しの後にインスタンスごと捨てる。
- ABI の版（今は 6）は変えない。ホストの振る舞いも、ホストが調べる関数の一覧も変わらず、今のプラグインはどれもそのまま動くからである。

呼ばない理由は次のとおりである。

- 呼び出しごとにインスタンスを捨てる決まり（[golem-plugin ADR 0001](../golem-plugin/adr/0001-wasm-host-and-abi.md) の「決定性と隔離のための設定」）のもとでは、解放しても、その後にメモリを使う呼び出しがない。
- 呼べば命令の数（fuel）を消費し、プラグインの `golem_dealloc` の誤りで呼び出しが失敗する経路が一つ増える。応答を読み終えた後の失敗を、どう扱うかも決める必要がある。
- 応答の領域を解放する関数は、もともと ABI にない。入力の領域だけを解放しても、対称にならない。

コードは変えない。

### ドキュメント

- docs/specifications.md の「プラグイン」の、上書きできるコマンドを述べた二文に、上の二つの一覧を書き、この ADR へリンクする。
- docs/specifications.md の「LSP」の「補完（コマンド名、ラベル、import のパス）」を、「補完（組み込みとプラグインのコマンドの名前、ラベル、import のパス）」と改める。
- docs/specifications.md の CLI の表の `golem inspect <file>` を `golem inspect <file> [--as cst\|ast\|ir]` とする。
- docs/roadmap.md の「記法と設定」から「ADR とコードの食い違い」の項を除く。
- 開発者のマニュアル：
  - `manual-dev/part1/05-plugins.gm` の上書きできるコマンドの段落を、上の二つの一覧に改め、ADR とコードが食い違うという文を除く。`golem_dealloc` を述べた二文を、「ホストは呼び出しごとにインスタンスを捨てるので、領域を解放する関数を求めない」という趣旨に改める。テストのプラグインの例に残る `golem_dealloc` の行は、公開しても害がないことを添えて残すか、例から除く。
  - `manual-dev/part1/04-lsp.gm` の補完の行を「組み込みとプラグインのコマンドの名前」とする。
- 使い手のマニュアル：付録B の `overrides` の一覧は、すでに十の名前を挙げているので変えない。`manual/chapters/09-editor.gm` の補完の行に、プラグインのコマンドの名前も補うことを加える。
- 次の ADR のステータスの行の末尾に、この ADR を指す一句を加える。
  - [golem-eval ADR 0002](../golem-eval/adr/0002-file-evaluation.md)：「、上書きできるコマンドの一覧は」に続けて、この ADR へのリンクを置く。
  - [golem-cli ADR 0001](../golem-cli/adr/0001-command-line-interface.md)：「、`golem inspect` のオプションは」に続けて、この ADR へのリンクを置く。
  - [golem-plugin ADR 0001](../golem-plugin/adr/0001-wasm-host-and-abi.md)：今は「採択」だけなので、「採択→`golem_dealloc` は」に続けて、この ADR へのリンクを置く。
- [golem-lsp ADR 0001](../golem-lsp/adr/0001-language-server.md) のステータスの行は変えない。コードを ADR に合わせるだけだからである。

## 実装しないこと

- `golem inspect --as ir` の表示を、引数のファイルの IR にすることと、CBOR を人が読める形にすること。草稿の [golem inspect の診断、終了コード、表示の対象と形を直す](../golem-cli/adr/0007-inspect-output.md) が直す。「既知の不具合」にも加えない。
- `golem inspect` の終了コードと文言。同じ草稿が直す。
- プラグインのコマンドの補完に、引数や散文スロットの数を添えること。`golem_describe` が返すのは名前の一覧だけである。
- プラグインが提供するブロックコマンドの補完。今の ABI で、プラグインが提供するのはインラインのコマンドとフィルタだけである。
- `golem_dealloc` を公開するプラグインを、誤りやお知らせにすること。
- 上書きできるコマンドの一覧を、`manifest.toml` や `style.toml` で変えられるようにすること。

## テスト設計

### 先に書いて失敗させるテスト

食い違い 2 だけが振る舞いを変えるので、失敗させるテストはその分だけである。

`modules/golem-driver/test/PluginsSpec.hs`（`withPlugins` で `identity.wat` を `broken` のコマンドを持つプラグインとして読み込む）：

- `evaluateProject` の結果の `evPluginCommands` が `["broken"]` になること。今は欄がないのでコンパイルできない。
- 章のファイルに構文のエラー（閉じていない `[`）を置いたプロジェクトでも、`evPluginCommands` が `["broken"]` になること。
- 同じプロジェクトで、構文のエラーのないファイルを `evReevaluate` で評価し直すと、`[broken]` が G02022 にならず、プラグインの呼び出しの結果（`identity.wat` の `broken` は空の応答を返すので、その検証の誤り）になること。今は `noPlugins` で評価するので G02022 になり、失敗する。
- 構文のエラーと、`plugins.lock` にないプラグインの宣言の両方があるプロジェクトで、`evDiagnostics` に構文の誤りとプラグインの読み込みの誤りの両方が入ること。

`modules/golem-lsp/test/Main.hs`（`withPlugins` と同じ手順でキャッシュとロックファイルを用意したワークスペース）：

- `[` の直後の補完の候補に、組み込みの名前に続いて `broken` が出ること。
- `[b` まで打った位置（構文のエラーがある状態）でも `broken` が出ること。
- プラグインのないプロジェクトの候補が、今と同じく組み込みの十八の名前であること。

### 今のコードのまま通るテスト

食い違い 1、3、4 は、コードを変えずに ADR と文書を合わせるので、テストは今の振る舞いを仕様として固定するものになる。

- 食い違い 1：`modules/golem-eval/test/BuiltinSpec.hs` の `overridableCommands` のテストは、すでに十の名前を確かめている。上書きできないコマンドの名前の一覧（`[builtinName (Fixed f) | f <- [minBound .. maxBound]]`）が `ref-number`、`ref-title`、`ref-page`、`note`、`sidenote`、`index`、`cite`、`aki` であることを加える。`modules/golem-driver/test/PluginsSpec.hs` に、`overrides = ["code"]` のプラグインが読み込めることと、`overrides = ["aki"]` が G06008 になることを加える。
- 食い違い 3：`modules/golem-cli/test/CommandsSpec.hs` に、`golem inspect FILE --cst` が使い方の誤り（終了コード 2）になること、`--as` を省くと CST を表示することを加える。
- 食い違い 4：`modules/golem-plugin/test/plugins/` に、`golem_dealloc` を公開しない `no-dealloc.wat` を加え、そのコマンドを呼べることを確かめる。

### 自動テストにしない確かめ方

プラグインを宣言したプロジェクトを VS Code の拡張で開き、`[` を打った位置の補完の一覧にプラグインのコマンドが出ることを目で確かめる。

## トレードオフ

四つのうち三つでコードを正としたので、ADR の文言が後から覆った形になる。
どれも、後の ADR（[docs/adr/0027](0027-exhaustive-command-dispatch-by-types.md)、[golem-cli ADR 0004](../golem-cli/adr/0004-usage-error-exit-code.md)）や文書がすでにコードの側を前提にしており、ADR の側に戻すと変更が広がる。

`code` を上書きできるとすると、プラグインが `[code: ...]` を、たとえば構文の色分けを付けるコマンドに置き換えられる。
置き換えた結果は、[golem-driver ADR 0017](../golem-driver/adr/0017-pdf-code-blocks.md) の PDF の改行の規則（`/` の後で改行する）を受けなくなりうる。
これは `strong` や `style` を置き換えた場合と同じであり、上書きを宣言した利用者の選択として受け入れる。

構文のエラーがあるときもプラグインを読み込むと、`golem check` と `golem build` が、構文の誤りと一緒にプラグインの誤りも出すようになる。
構文の誤りを直した後で初めてプラグインの誤りに気付くより、一度に見えるほうがよい。
プラグインの読み込みは wasm のコンパイルを伴うが、構文のエラーがないときにはすでに毎回行っているので、LSP の評価の時間は、エラーのないプロジェクトを評価するときより延びない。

`golem_dealloc` を ABI から外しても、プラグインの作者には何も求めない。
将来、インスタンスを呼び出しの間で使い回す設計に変えるなら、解放の関数がまた要る。
そのときは ABI の版を上げて加える。
呼ばない関数を ABI に残しておく案は、ホストの実装を読む人と ADR を読む人の理解を食い違わせ続けるので採らない。

## 参考文献

- Language Server Protocol Specification 3.17, "Completion Request", https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/
