# ADR 0004: 使い方の誤りの終了コードを 2 にし、使い方の文言を日本語にする

ステータス: 採択

## 文脈

[ADR 0001](0001-command-line-interface.md) は、終了コードを、成功が 0、診断によるエラーが 1、コマンドの使い方の誤り（未知のオプションなど）が 2 と定めている。
仕様書と README も同じことを書いている。

実際の `golem` は、使い方の誤りで 1 を返す。
`golem new --language fr` や未知のオプションを渡すと、使い方を表示して終了コード 1 で終わる。
引数の解釈に使う optparse-applicative は、解釈に失敗したときの終了コードを最上位の `ParserInfo` の `infoFailureCode` から取り、その既定が 1 だからである。

[ADR 0001](0001-command-line-interface.md) のテスト設計には「未知のオプションで終了コードが 2 になることを確かめる」とあるが、golem-cli にはテストがなく、この食い違いに気づけなかった。

ほかにも、使い方の誤りなのに 2 を返さない箇所がある。
`golem inspect` の `--as` に `cst`、`ast`、`ir` 以外を渡すと、誤りを表示したうえで終了コード 0 を返す。

CI で Golem を使う利用者は、終了コードで「原稿の誤り」と「呼び出し方の誤り」を見分ける。
1 と 2 が混ざると、呼び出し方の誤りを原稿の誤りとして扱ってしまう。

文言も揃っていない。
診断は日本語だが、使い方の表示とヘルプは英語である。
英語の文言には、Golem が書いたもの（コマンドとオプションの説明、`unknown profile` などの値の誤り、`unknown target`）と、optparse-applicative が組み込みで持つもの（`Usage:`、`Available options:`、`Invalid option`、`Missing:` など）がある。

## 実装すること

### 終了コード

- 最上位の `ParserInfo` に `failureCode 2` を付け、引数の解釈の失敗をすべて終了コード 2 にする。サブコマンドの解釈の失敗も、最上位の値が使われる。
- `golem inspect` の `--as` と `golem build` の `--target` を、値の列挙として引数の解釈の段階で読む。ほかの値は解釈の失敗にする。
- `--help` は、これまでどおり終了コード 0 とする。
- 引数なしの `golem` は、使い方を表示して終了コード 2 にする。今は 1 を返しているが、コマンドを指定していないのは使い方の誤りである。

### 文言の日本語化

- Golem が書く文言（コマンドの説明、オプションの説明、値の誤り）をすべて日本語にする。
- ヘルプのオプション（`-h`、`--help`）は `helperWith` で作り、説明を日本語にする。
- コマンドの一覧の見出しは `commandGroup` で日本語にする。
- optparse-applicative が組み込みで持ち、差し替える口のない文言は、`execParserPure` の失敗を `renderFailure` で文字列にした後、決まった語句の表で置き換える。表は optparse-applicative 0.19.0.0 の文言に合わせる。対象は次のとおりとする。

| 英語 | 日本語 |
|---|---|
| `Usage:` | `使い方:` |
| `Available options:` | `オプション:` |
| `` Invalid option `X' `` | `未知のオプションです: X` |
| `` Invalid argument `X' `` | `未知の引数です: X` |
| `Missing: X` | `足りない引数があります: X` |
| `Did you mean this?`、`Did you mean one of these?` | `次のことですか？` |
| `` The option `X` expects an argument. `` | `オプション X には値が必要です` |
| `option X: ` で始まる値の誤り | `オプション X: ` |

- `--help` の出力にも同じ置き換えを適用する。
- 置き換えの結果は golden テストで固定する。optparse-applicative の版を上げて文言が変わると、テストが失敗して表の更新が必要だとわかる。

### テスト

- golem-cli にテストスイートを加える。`build-tool-depends` で `golem` の実行ファイルをビルドし、テストから実行して終了コードと出力を確かめる。

## 実装しないこと

- 英語など、ほかの言語での表示の切り替え。
- 終了コードの値そのものの変更。[ADR 0001](0001-command-line-interface.md) の表のとおりにする。
- 引数の解釈を optparse-applicative から自前の実装に置き換えること。組み込みの文言を置き換える表で足りる。
- [ADR 0001](0001-command-line-interface.md) のテスト設計のうち、この ADR に関わらない項目（各コマンドの成功と失敗、`--format json`）のテスト。

## テスト設計

golem-cli のテストスイートで、`golem` の実行ファイルを一時ディレクトリで実行して確かめる。

終了コード：

- 未知のオプション（`golem build --nope`）で 2 になること。
- 未知のサブコマンド（`golem nope`）で 2 になること。
- 値の誤り（`golem new --language fr DIR`、`golem build --profile nope`、`golem build --target nope`、`golem inspect FILE --as nope`）で 2 になること。
- 引数なしの `golem` で 2 になること。
- `golem --help` で 0 になること。
- `golem new` の値の誤りでは、ディレクトリが作られないこと。

文言：

- `golem --help`、`golem build --help`、`golem build --nope`、`golem nope`、`golem buld`（綴りの誤り）、`golem build --profile nope`、`golem build --profile`（値の欠け）の出力を golden テストで固定する。
- これらの出力に、表の英語の語句と、Golem が書いた英語の説明が残っていないこと。

## トレードオフ

テストのために golem-cli がテストスイートを持つと、`cabal test all` で `golem` の実行ファイルのビルドが必要になる。
実行ファイルはすでに CI でビルドしているので、増える時間は小さい。

組み込みの文言を文字列の置き換えで日本語にするので、optparse-applicative の版を上げると表の手入れが要る。
`cabal.project.freeze` で版を固定し、golden テストで変化を検出するので、気づかずに英語が混ざることはない。
引数の解釈を自前で実装すれば置き換えは要らないが、サブコマンド、ヘルプ、綴りの誤りの候補まで作り直すことになり、得るものに見合わない。

`--as` と `--target` を列挙として読むと、今の個別の文言（「--as は cst、ast、ir のいずれかです」、`unknown target`）は、ほかの値の誤りと同じ形式の日本語にそろう。
