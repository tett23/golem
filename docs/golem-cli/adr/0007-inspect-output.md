# ADR 0007: golem inspect の診断、終了コード、表示の対象と形を直す

ステータス: 採択

## 文脈

仕様書の「既知の不具合」は、`golem inspect` について二つの食い違いを挙げている。

- 構文の誤り（G01017 など）があっても終了コード 0 で終わり、診断を Haskell の `show` の形で出す。
- 存在しないファイルを渡すと、英語の例外と GHC のバックトレースが出る。

ロードマップの v0.1.0-rc3 の「既知の不具合の修正」は、ほかのコマンドと同じ診断の出力を通して誤りがあれば終了コード 1 にし、ないファイルを日本語の誤りにし、`--as ir` は引数のファイルの IR を人が読める形で出す、という直し方を案として挙げ、二つの不具合を一つの ADR で直すとしている。

### 再現

main（0231d98）と golem-cli、golem-parser、golem-lsp が同じ `golem` で確かめた。

| 操作 | 標準出力 | 標準エラー出力 | 終了コード |
| --- | --- | --- | --- |
| `golem inspect bad.gm`（中身は `[strong: x`） | CST | `[Diagnostic {diagCode = DiagnosticCode "G01017", …, diagMessage = "\12371\12371…"}]` | 0 |
| `golem inspect nope.gm`（ないファイル） | なし | `golem: nope.gm: withBinaryFile: does not exist (No such file or directory)` と `HasCallStack backtrace:` から始まる 5 行 | 1 |
| `golem inspect d.gm`（`d.gm` はディレクトリ） | なし | `withBinaryFile: inappropriate type (is a directory)` とバックトレース | 1 |
| `golem inspect bin.gm`（UTF-8 でない） | なし | G01001 を `show` の形で | 1 |
| `golem inspect bad.gm --as ir`（プロジェクトの外） | なし | G03016 と G01017 を `show` の形で | 0 |
| `golem inspect two.gm --as ir`（`two.gm` は章でないファイル） | `chapters/01.gm` の `Document {docFile = FileId 1, …}` と `CBOR: 66 bytes` | なし | 0 |
| `golem inspect two.gm --as ast` | `File {fileId = FileId 0, fileBlocks = [Located {locSpan = …` の一行 | なし | 0 |
| `golem fmt nope.gm`（ないファイル） | なし | `withBinaryFile: does not exist` とバックトレース | 1 |

`show` の形の診断は、メッセージの日本語を `\12371` のような数の列で書くので読めない。
位置もバイトの位置のままで、行と列にならない。

### 原因

`modules/golem-cli/app/Main.hs` の `inspect` は、ほかのコマンドと違う経路で書いている。

- ファイルを `BS.readFile` で読み、例外を捕まえない。ないファイルは GHC の例外として最上位まで届き、英語の文言とバックトレースになる。
- 診断を `putHuman`（人が読む形と `golem explain` の案内）に渡さず、`T.pack (show ds)` で書く。
- 構文の診断があっても、最後に `pure ExitSuccess` を返す。
- `--as ir` は `evaluateProject Dev "."` でプロジェクトの全体を評価し、`evResults` のすべての文書を `print` する。引数のファイルは構文解析にだけ使い、どの文書を出すかには使っていない。
- `--as ast` も `print ast` で、`Located` と `SrcSpan` の入れ子を一行に並べる。人が読む形になっているのは `--as cst`（`Golem.Parser.CST` の `pretty`）だけである。

[golem-cli ADR 0001](0001-command-line-interface.md) は、`inspect` が「構文木、AST、意味論 IR（CBOR を人が読める形にしたもの）を表示する」とし、診断を人が読む形で標準エラー出力に書き、診断によるエラーがあれば終了コード 1 とすると定めている。
`inspect` は、この三つのどれにも従っていない。

### 決めること

- 診断の出力の経路と終了コード。
- ないファイルの診断のコード。`golem fmt` の引数のないファイルも同じ扱いにする。
- `--as ir` が出す文書と、その形。プロジェクトの原稿でないファイルの扱いも含む。
- CBOR のバイト列を出す手段が要るか。

`--as` というオプションの名前と、`cst`、`ast`、`ir` の値は、草稿の [docs/adr/0031](../../adr/0031-adr-code-mismatches.md) の「3. golem inspect のオプション」が、今のコードのまま正とすると決めている。
この ADR は名前を決め直さず、値を一つ加える。

### メンテナーが決めたこと

起草の後、メンテナーが次のように決めた。

- **プロジェクトの原稿でないファイルの `--as ir`**：誤りにしない。下書き、一時的なファイル、メモをプロジェクトに置くのは、ふだんの作業の流れである。原稿かどうかを検査せず、そのファイルを評価して出す。LSP が開いたファイルを扱うのと同じく、原稿であることを求めずに評価する。
- **`--as ast` の形**：`--as ir` と同じ木の形にする。使いにくいと分かれば、新しい ADR で改める。
- **`golem fmt` のないファイル**：`inspect` と同じく、G03002 の誤りとし、終了コード 1 で終え、英語の例外を出さない。この ADR の範囲に含める。

## 実装すること

### 診断と終了コード

- `inspect` が出す診断は、すべて `putHuman` を通して標準エラー出力に書く。`build`、`check`、`lint` と同じく、人が読む形で、コードの説明があれば `golem explain` の案内の一行を添える。
- 表示（木か CBOR）は、診断があっても、作れる限り標準出力に書く。閉じていない `[` を含むファイルの CST を見ることは、`inspect` の主な使い道の一つだからである。
- 書いた診断にエラーが一つでもあれば、終了コード 1 とする。警告とお知らせだけなら 0 とする。
- 使い方の誤り（`--as` の値の誤りなど）は、[golem-cli ADR 0004](0004-usage-error-exit-code.md) のとおり終了コード 2 のままとする。
- `--format json` は加えない（「実装しないこと」）。

### ないファイル

この節の規則は、`golem inspect` の引数と、`golem fmt` の引数の両方に当てる（「golem fmt」の節）。

- 引数のパスが存在しないか、通常のファイルでない（ディレクトリなど）ときは、G03002 の誤りとし、終了コード 1 で終える。標準出力には何も書かない。
- メッセージは、章や `@import` の G03002 と同じ `ファイルがありません: <パス>` とする。パスは引数に書いたとおりに書く。
- 位置は引数のファイルの先頭とし、`nope.gm:1:1: error[G03002]: ファイルがありません: nope.gm` と表示する。
- G03002 は「章や `@import` が指すファイルがない」誤りであり、指す元がコマンドの引数に変わるだけで、利用者の直し方（パスの綴りと置き場所を確かめる）は同じである。新しいコードは設けない。
- 権限がないなど、ほかの理由で読めないときは扱わない。golem-project が章のファイルを読む経路と同じく、例外のままとする（「実装しないこと」）。

UTF-8 として読めないファイルは、今と同じく G01001 とし、上の経路で書く。

### `--as cst` と `--as ast`

- 引数のファイルだけを構文解析する。プロジェクトは読まない。
- 診断は、読みの段階と構文の段階のもの（G01xxx）である。
- `--as cst` の形は変えない。
- `--as ast` は、次の節の木の形で出す。

### `--as ir`

- 作業中のディレクトリをプロジェクトのルートとし、`golem check --profile dev` と同じく S1 まで評価する。
- 引数のパスを、作業中のディレクトリからの相対のパスに直して正規化し（`./` を除き、`..` を解決する）、プロジェクトの原稿（章と、章から `@import` で取り込んだファイル）のパスと比べる。
- 診断と終了コードは、上の「診断と終了コード」のとおりとする。標準出力に書くのは、次の節の木の形の文書である。CBOR のバイト数の行は出さない。

引数のファイルがどれかで、出す文書と診断が変わる。

| 引数のファイル | 出す文書 | 書く診断 |
| --- | --- | --- |
| プロジェクトの原稿 | 全体の評価の、そのファイルの S0 の結果の文書（`erDocument`） | 評価で出たものすべて（`golem check --profile dev` と同じもの） |
| 原稿でないファイル（プロジェクトは読める） | そのファイルを、プロジェクトの文脈で S0 まで評価した文書 | プロジェクトの段階の診断と、そのファイルの構文と S0 の診断 |
| `manifest.toml` のないディレクトリのファイル | そのファイルを、組み込みの体裁だけで S0 まで評価した文書 | そのファイルの構文と S0 の診断 |

**原稿のファイル**：ほかのファイルのエラーでも終了コードは 1 になる。
そのファイルのエラーが原因で S1 が行われないこともあるからである。

**原稿でないファイル**：プロジェクトの全体を評価した後、その `evReevaluate` で引数のファイルを評価する。
`evReevaluate` は、前回の評価の文脈（`style.toml` の体裁、プラグイン、マニフェストの設定）でファイル一つを S0 まで評価する関数であり、LSP が編集したファイルを評価し直すのに使っている（[golem-lsp ADR 0001](../../golem-lsp/adr/0001-language-server.md)）。
ファイルの番号（`FileId`）は、プロジェクトの評価が使った番号の最大の次とする。
S1 は行わないので、相互参照と `doc` を参照する式は解決されないまま文書に残る。
ほかの原稿のファイルの S0 と S1 の診断は書かない。
引数のファイルと関係がなく、そのファイルを原稿に加えたときにどうなるかは `golem check` で分かるからである。
プロジェクトの段階の診断（G03007、プラグインと参考文献の誤り）は書く。
引数のファイルの評価の文脈に効くからである。

**プロジェクトの外のファイル**：作業中のディレクトリに `manifest.toml` がないときは、G03016 を書かず、LSP がマニフェストから到達しないファイルを評価するのと同じく、組み込みの体裁だけで、プラグインなしに S0 まで評価する。
ファイルの番号は 0 とする。
この評価の関数は、今は golem-lsp の `Golem.Lsp.Workspace` の `loose` にある。
golem-driver に `evaluateLoose :: FilePath -> Text -> EvalResult` としてくくり出し、golem-lsp と golem-cli の両方から使う。

`manifest.toml` はあるが、`style.toml` などの誤りでプロジェクトを読めないとき（`loadProject` が失敗したとき）は、その診断を書き、終了コード 1 で終える。
標準出力には何も書かない。
体裁の誤りを黙って組み込みの体裁に置き換えると、出した IR がプロジェクトの IR と違うことに気付けないからである。

引数のファイルに構文の誤りがあると、S0 を行わないので、文書はない。
このときは診断だけを書き、標準出力には何も書かない。

### `--as cbor`

- `--as` の値に `cbor` を加える。
- `--as ir` と同じ文書を選び、`Golem.Doc.Cbor` の `encodeDocument` のバイト列を、そのまま標準出力に書く。改行も足さない。
- 診断と終了コードは `--as ir` と同じとする。

プラグインの変換（`[1, 名前, 文書]` の要求）が受け取る文書は、この CBOR である（[golem-plugin ADR 0001](../../golem-plugin/adr/0001-wasm-host-and-abi.md)）。
プラグインの作者は、これをファイルに書き出して、自分のプラグインの単体テストの入力にできる。
CBOR を読む形（RFC 8949 の診断の記法）で見たいときは、ほかの道具に渡せばよい。

### 木の形

`--as ast` と `--as ir` は、型の `Show` のインスタンス（導出したもの）が出す文字列を読み、字下げした木に組み直して出す。
組み直しは golem-syntax の新しいモジュール `Golem.Syntax.ShowTree` の純粋な関数とする。

```haskell
showTree :: FileId -> String -> Text
```

`FileId` は、表示するファイルの番号である。

読み取る形は、導出した `Show` が出す形に限る。

- 構築子の適用（`Heading 1 [...]`）、レコード（`Block {blockSpan = ..., ...}`）、リスト、タプル、括弧で囲んだ負の数。
- 文字列と文字のリテラル。
- 数と、`1 % 2` のような中置の演算子を含む値は、一続きの葉として扱う。

組み直しの規則は次のとおりとする。

- 一つの節を一行で書いたとき、字下げを含めて 100 桁に収まるなら一行で書く。
- 収まらないときは、構築子の名前を一行に置き、引数を次の行から二つ深く字下げして一つずつ書く。レコードの欄は `欄の名前 = 値`、リストの要素は `- 値` の形にする。
- 文字列は Haskell のリテラルの形のまま書くが、印字できる ASCII の外の字（日本語など）を `\12371` のように数にせず、そのまま書く。制御文字と `"` と `\` は今と同じくエスケープする。
- `SrcSpan {spanFile = FileId f, spanStart = s, spanEnd = e}` は、`f` が表示するファイルの番号なら `@s..e`、そうでなければ `@f:s..e` と書く。CST の表示（`NFile@0..10`）と同じ書き方である。
- `Located {locSpan = 位置, locValue = 値}` は、値を書き、その最初の行の末尾に ` @s..e` を添える。

`本文。` だけのファイルの `--as ast` は、次の形になる。

```
File
  fileId = FileId 0
  fileBlocks =
    - Paragraph [Text "本文。" @0..9] @0..10
```

読み取れない文字列が来たとき（導出していない `Show` のインスタンスを持つ型が加わったときなど）は、元の文字列をそのまま書く。
出力は入力の文字列だけで決まり、決定的である（[docs/adr/0002](../../adr/0002-determinism.md)）。

### golem fmt

`golem fmt` の引数のファイルにも、「ないファイル」の節の規則を当てる。

- 引数のパスが存在しないか、通常のファイルでないときは、そのファイルについて G03002 を `putHuman` で書き、そのファイルを飛ばす。
- 残りのファイルの整形は続ける。一つでも G03002 があれば、終了コードは 1 とする。今の「整形できないファイルがあれば 1」と同じ扱いである。
- 引数を省いてプロジェクトの原稿を整形するときは、`loadProject` が章のファイルを読んでいるので、今と同じとする。

### オプションの表示

`--as` の `metavar` を `cst|ast|ir|cbor` とし、説明を `表示するもの（既定は cst）` のままとする。
`--as` の値の誤りは、今と同じく使い方の誤り（終了コード 2）である。

## 実装しないこと

- `inspect` の `--format json`。表示そのものが人の読む木であり、機械で読むなら `--as cbor` がある。
- `--profile`。`--as ir` は今と同じく dev で評価する。
- CBOR の診断の記法（RFC 8949 の 8 節）での表示。
- 権限がないなど、存在しないこと以外の理由で読めないファイルの診断。
- `golem fmt` の、UTF-8 として読めないファイルの文言（`UTF-8 として読めないため整形しません`）を G01001 にそろえること。
- `golem fmt` と `golem inspect` のほかに、ファイルを引数に取るコマンドの扱い。今はこの二つだけである。
- 原稿でないファイルの `--as ir` で、S1 を行うこと。そのファイルは本に入らないので、S1 の結果に意味がない。
- 型ごとに手で書いた木の表示（「トレードオフ」）。
- レイアウト IR（S2 の結果）の表示。
- `--as` の名前の変更。草稿の [docs/adr/0031](../../adr/0031-adr-code-mismatches.md) が扱う。

## テスト設計

`modules/golem-cli/test/CommandsSpec.hs` の `inspectTests` に次を加え、今の `golem` で失敗することを確かめてから実装する。

| 場合 | 期待 |
| --- | --- |
| `[strong: x` のファイルの `inspect`（`--as cst`） | 終了コード 1。標準出力に CST。標準エラー出力が `a.gm:2:1: error[G01017]: ` で始まり、`golem explain` の案内の行を含み、`Diagnostic {` を含まない |
| 同じファイルの `--as ast` | 終了コード 1。標準出力に木 |
| ないファイル `nope.gm` | 終了コード 1。標準出力が空。標準エラー出力の最初の行が `nope.gm:1:1: error[G03002]: ファイルがありません: nope.gm`。`withBinaryFile` と `backtrace` を含まない |
| ディレクトリ `d.gm` | 終了コード 1、G03002 |
| UTF-8 でないファイル | 終了コード 1、標準エラー出力が人の読む形の G01001 |
| 正しいファイルの `--as cst` | 終了コード 0、標準エラー出力が空（今の「the CST is the default, on stdout」のまま通る） |
| 章が `a.gm` と `b.gm` のプロジェクトで `inspect b.gm --as ir` | 終了コード 0。標準出力の木が `b.gm` の文書であり、`a.gm` の本文を含まない。`CBOR:` の行がない |
| 同じプロジェクトで `inspect ./b.gm --as ir` | `b.gm` と同じ出力 |
| 同じプロジェクトで章でない `c.gm` の `--as ir` | 終了コード 0。標準出力の木が `c.gm` の文書であり、`FileId` が `a.gm` と `b.gm` の番号と重ならない。標準エラー出力が空 |
| `style.toml` で文字スタイル `note` を定義したプロジェクトで、章でない `c.gm`（`[style note: x]` を含む）の `--as ir` | 終了コード 0。文書に `note` の文字スタイルが入る（プロジェクトの体裁で評価している） |
| `a.gm` に未知のコマンドがあるプロジェクトで、章でない `c.gm` の `--as ir` | 終了コード 0。標準エラー出力に `a.gm` の G02022 がない |
| 章でない `c.gm` に未知のコマンドがあるとき | 終了コード 1、`c.gm` の G02022、標準出力に木 |
| `manifest.toml` のないディレクトリで `x.gm --as ir` | 終了コード 0。標準出力に `x.gm` の木。G03016 を書かない |
| `manifest.toml` はあるが `style.toml` に誤りのあるディレクトリで `--as ir` | 終了コード 1、その誤りの診断、標準出力が空 |
| `a.gm` に存在しないラベルへの参照があるプロジェクトで `inspect b.gm --as ir` | 終了コード 1、G04003、標準出力に `b.gm` の木 |
| `inspect b.gm --as cbor` | 終了コード 0。標準出力のバイト列が、同じプロジェクトを `evaluateProject` で評価した `b.gm` の文書の `encodeDocument` と一致する |
| `inspect a.gm --as nope` | 終了コード 2（今のまま） |
| `fmt nope.gm` | 終了コード 1。標準エラー出力の最初の行が `nope.gm:1:1: error[G03002]: ファイルがありません: nope.gm`。`withBinaryFile` と `backtrace` を含まない |
| `fmt nope.gm ok.gm`（`ok.gm` は整形の要るファイル） | 終了コード 1、G03002。`ok.gm` は整形されている |
| `fmt --check d.gm`（ディレクトリ） | 終了コード 1、G03002 |

今の「--as ast shows the AST of the file」と「--as ir shows the IR of the project and the size of its CBOR」は、上の期待に合わせて書き直す。
`modules/golem-cli/test/LocaleSpec.hs` の「golem inspect writes the same tree」は、`--as cst` なので変わらずに通ること。

golem-lsp の今のテストのうち、マニフェストから到達しないファイルの診断を確かめるものは、`evaluateLoose` にくくり出した後もそのまま通ること。

golem-syntax のテストに `Golem.Syntax.ShowTree` の単体テストを加える。

- 一行に収まる節は一行で、収まらない節は字下げした木で書くこと（100 桁ちょうどと 101 桁の境）。
- レコード、リスト、タプル、負の数、`%` を含む有理数、空のリストを読めること。
- 文字列の日本語がそのまま出て、`"`、`\`、改行がエスケープされること。
- `SrcSpan` が `@s..e` に、ほかのファイルの `SrcSpan` が `@f:s..e` に、`Located` が値と ` @s..e` になること。
- 読み取れない文字列が、そのまま返ること。
- golem-parser の AST と golem-doc の IR の `show` を、fixture のいくつかで組み直し、例外にならず、元の文字列に戻せない情報を落としていないこと（各葉の文字列が出力に現れること）。

## トレードオフ

木の形を、型ごとに手で書いた表示の関数で作る案もある。
欄の名前を CDDL の名前に揃えるなど、表示を自由に決められ、構築子を足すと網羅性の検査で書き忘れに気付ける。
採らなかったのは、IR と AST の型が ADR のたびに増え、表示の関数の手入れが型の変更のたびに要るからである。
導出した `Show` から組み直せば、型の変更はそのまま表示に出る。
代わりに、表示の欄の名前は Haskell の欄の名前（`docBlocks` など）になり、開発者のマニュアルが説明する CDDL の名前とは一致しない。
`inspect` は開発者の道具なので、この差は受け入れる。
`Generic` を導出して木を作る案は、IR と AST のすべての型に `deriving Generic` を足すことになり、今のところどの型も導出していないので見送った。

プロジェクトの原稿でないファイルも、原稿かどうかを検査せずに評価して出す。
下書きやメモを見たいときに、章に加える手間も、誤りの終了コードもない。
代わりに、原稿でないファイルの IR は S0 までであり、そのファイルを章に加えたときの IR とは、相互参照、`doc` を参照する式、`@import` された側から見た変数の解決が違いうる。
この違いを利用者に知らせる診断は出さない。
原稿でないファイルの評価にプロジェクトの体裁とプラグインを使うのは、組み込みの体裁だけで評価すると、プロジェクトで定義した文字スタイルが G02018 になり、下書きの IR が使い物にならないからである。
`manifest.toml` のない場所では文脈がないので、LSP と同じく組み込みの体裁で評価する。

原稿の `--as ir` の診断をプロジェクトの全体のものにすると、引数のファイルに関係のない誤りでも終了コードが 1 になる。
引数のファイルの診断だけに絞ると、S1 が行われなかった理由が見えなくなる。
原稿については `golem check` と同じものを出すほうを選んだ。
原稿でないファイルは S1 に関わらないので、ほかの原稿の診断を書く理由がない。

`--as ast` を `--as ir` と同じ木の形にしたので、今の一行の形を読むスクリプトがあれば壊れる。
`inspect` は開発者の道具であり、一行の形は人にも機械にも読みにくいので、変える。
木の形が使いにくいと分かれば、新しい ADR で改める。

`golem fmt` のないファイルを、ほかのファイルの整形を止めずに飛ばすのは、`golem fmt a.gm b.gm` の一つの綴りの誤りで、ほかのファイルの整形まで止めないためである。

## データ構造

golem-cli の `InspectAs` に `AsCbor` を加える。
golem-driver に `evaluateLoose :: FilePath -> Text -> EvalResult` を加え、golem-lsp の `loose` はそれを使う形に改める。
ほかの型は変えない。

## ドキュメント

- docs/specifications.md：「既知の不具合」の「`golem inspect` の終了コードと文言」の項を消す。CLI の表の `golem fmt` の行に、ないファイルを G03002 とすることを加える。CLI の表の `golem inspect` の行を `golem inspect <file> [--as cst|ast|ir|cbor]` とし、説明を「CST、AST、意味論 IR を人が読む木の形で、または意味論 IR の CBOR を表示する」とする。
- README.md：コマンドの表の `golem inspect FILE --as cst|ast|ir` を `golem inspect FILE --as cst|ast|ir|cbor` とする。
- docs/diagnostics.md：G03002 の「意味」に、`golem inspect` と `golem fmt` の引数のファイルがない場合を加える。
- docs/roadmap.md：v0.1.0-rc3 の「既知の不具合の修正」から「`golem inspect` の終了コード、文言、対象」を消す。
- 開発者のマニュアル：`manual-dev/part1/01-cli.gm` の「構文木と IR を見る」で、`--as ir` が引数のファイルの IR を出すこと、原稿でないファイルとプロジェクトの外のファイルの扱い、木の形、`--as cbor`、終了コードを書き直す。オプションの表の `--as` の値に `cbor` を加える。`manual-dev/part1/05-plugins.gm` の「受け取る IR の中身」の文に、`--as cbor` でバイト列を取り出せることを加える。
- 使い手のマニュアル：付録E（`manual/appendices/e-errors.gm`）の G03002 の項の直し方に、`golem fmt` に渡したファイルのパスも確かめることを加える。`golem inspect` については変えない。付録I は `golem inspect` の不具合を載せない方針である（docs/manual-policy.md）。
- [golem-cli ADR 0001](0001-command-line-interface.md) のステータスの行：今の行の末尾に「、`golem inspect` の診断、対象、表示の形は [ADR 0007](0007-inspect-output.md)」を加える。

## 参考文献

- [golem-cli ADR 0001](0001-command-line-interface.md)
- [golem-cli ADR 0004](0004-usage-error-exit-code.md)
- [golem-cli ADR 0005](0005-explain-diagnostic-codes.md)
- [golem-plugin ADR 0001](../../golem-plugin/adr/0001-wasm-host-and-abi.md)
- [golem-project ADR 0006](../../golem-project/adr/0006-project-diagnostic-codes.md)
- RFC 8949 Concise Binary Object Representation (CBOR)、8 節 Diagnostic Notation。https://www.rfc-editor.org/rfc/rfc8949
