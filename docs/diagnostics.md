# diagnostic のコード

この文書は、Golem が出す diagnostic のコード（`G0101` など）を一つずつ説明する。
diagnostic は、コードと一行のメッセージだけを出す。
コードが何を表し、どう直せばよいかを、ここで引けるようにする。
`golem explain <コード>` は、この文書の節をそのまま表示する（[golem-cli ADR 0005](golem-cli/adr/0005-explain-diagnostic-codes.md)）。
LSP の diagnostic の `codeDescription` は、GitHub の上のこの文書の節を指す。

プラグインが出す diagnostic のコードは、この文書の対象外である。
プラグインのコードはプラグインが決めるので、プラグインの文書を参照する。

## 節の形

各コードの節は、`## G0101` の見出しから始まる。
見出しにはコードだけを書くので、節の URL は `diagnostics.md#g0101` になる。
節は次のものを、この順に持つ。

- **題**：見出しの次の段落。一行で書き、`golem explain` の一覧に使う。
- **重大度**：`- 重大度:` の行。エラー、警告、dev では警告、prod ではエラー、お知らせ、プリフライトの設定による、のいずれかを書く。プリフライトの設定によるコードには、括弧で組み込みの設定 `print` の既定を添える（[golem-cli ADR 0006](golem-cli/adr/0006-preflight.md)）。エラーが一つでもあれば、ビルドは失敗し、終了コードは 1 になる。お知らせは終了コードに影響せず、`manifest.toml` の `[diagnostics]` の `silence-notices` と、コマンドの `--no-notices` で抑制できる（[golem-syntax ADR 0002](golem-syntax/adr/0002-notice-severity.md)）。
- **状態**：`- 状態:` の行。使用中か廃止を書く。
- **意味**：`### 意味` の小見出し。いつ出るかを書き、メッセージの文言、段階とモジュール、ADR を添える。メッセージの引数を埋める部分は `<名前>` のように書く。番号を書いた ADR が見つからないコードは「ADR なし」とし、番号に触れているだけの ADR があれば併記する。
- **主な原因**：`### 主な原因` の小見出し。よくある原因を書く。廃止したコードでは省ける。
- **直し方**：`### 直し方` の小見出し。廃止したコードでは、代わりの書き方を書く。

節はコードの昇順に並べる。
golem をビルドするときにこの文書を埋め込み、節の形を検査する。
形の崩れた文書では、golem をビルドできない。

ソースで使っているコードがすべて状態「使用中」で載っていること、状態「使用中」のコードがすべてソースで使われていること、重大度が `profileDependentCodes` と `noticeCodes` と `preflightCodes` に合うことは、golem-driver のテスト（`modules/golem-driver/test/Main.hs`）が確かめる。
新しいコードを足すときは、同じ変更でこの文書に節を足す。
使わなくなったコードは、節を消さずに状態を「廃止」にする。

## 番号の区分

コードは `G` と 4 桁の数字からなる。
上 2 桁が、diagnostic を出す段階を表す（[golem-syntax ADR 0001](golem-syntax/adr/0001-source-spans-and-diagnostics.md)）。
一度使った番号は、ほかの意味に使い回さない。

| 上 2 桁 | 段階 | 主なモジュール |
| --- | --- | --- |
| 01 | 構文（読み込みと解析） | golem-parser |
| 02 | 評価 | golem-eval（プラグインのコマンドは golem-driver） |
| 03 | プロジェクト（`manifest.toml`、`style.toml`、import） | golem-project、golem-driver、golem-eval |
| 04 | 文書の組み立て（ラベル、相互参照、目次） | golem-doc |
| 05 | lint | golem-lint |
| 06 | プラグイン | golem-plugin、golem-driver |
| 07 | レイアウト（版面、改ページ、傍注、表） | golem-layout-spec、golem-layout、golem-driver |
| 08 | 出力（フォント、出力インテント） | golem-driver |
| 09 | プリフライト | golem-preflight |

重大度がプロファイルで変わるコードは `Golem.Syntax.Diagnostic.profileDependentCodes` にまとめてあり、dev では警告、prod ではエラーになる。
今は [G0310](#g0310) と [G0504](#g0504) の二つである。
[G0205](#g0205) は、prod でだけ出る警告である。

09 のコードは、`golem preflight` だけが出す（[golem-cli ADR 0006](golem-cli/adr/0006-preflight.md)）。
[G0902](#g0902) から [G0918](#g0918) の重大度は、プリフライトの設定（`preflight.toml`）で決まり、`Golem.Syntax.Diagnostic.preflightCodes` にまとめてある。
設定で選べるのはエラー、警告、off で、お知らせは選べない。
[G0901](#g0901) は設定のファイルの誤りで、常にエラーである。

## お知らせ

お知らせは、誤りではないが書き手が知っておいたほうがよいことを伝える重大度である（[golem-syntax ADR 0002](golem-syntax/adr/0002-notice-severity.md)）。
直すべきものは警告にし、直さなくてよいものをお知らせにする。
お知らせは終了コードに影響せず、プロファイルで重大度が変わらず、出力も変えない。
人が読む形式と JSON の形式では、エラーと警告の後に並ぶ。

お知らせのコードは `Golem.Syntax.Diagnostic.noticeCodes` にまとめてある。
今は次の十七である。

| コード | 種類 | 段階 |
| --- | --- | --- |
| [G0262](#g0262) | 上書き | 評価 |
| [G0263](#g0263) | 一般的でない書き方 | 評価 |
| [G0264](#g0264) | 効果のない書き方 | 評価 |
| [G0265](#g0265) | 廃止予定 | 評価 |
| [G0279](#g0279) | 効果のない書き方 | 評価 |
| [G0294](#g0294) | 一般的でない書き方 | 評価 |
| [G0323](#g0323) | 既定の使用 | プロジェクト |
| [G0407](#g0407) | 効果のない書き方 | 文書の組み立て |
| [G0408](#g0408) | 効果のない書き方 | 文書の組み立て |
| [G0409](#g0409) | 効果のない書き方 | 文書の組み立て |
| [G0411](#g0411) | 処理系による調整 | 文書の組み立て |
| [G0730](#g0730) | 処理系による調整 | レイアウト |
| [G0739](#g0739) | 処理系による調整 | レイアウト |
| [G0745](#g0745) | 処理系による調整 | 出力 |
| [G0746](#g0746) | 処理系による調整 | レイアウト |
| [G0747](#g0747) | 処理系による調整 | レイアウト |
| [G0808](#g0808) | 既定の使用 | 出力 |

抑制できるのはお知らせだけであり、エラーと警告を抑制する手段はない。
`manifest.toml` の `[diagnostics]` の `silence-notices` に並べたコードのお知らせは、`golem build`、`golem check`、`golem lint`、LSP のどれにも出ない。
`golem build`、`golem check`、`golem lint` に `--no-notices` を付けると、その実行に限り、すべてのお知らせを出さない。

```toml
[diagnostics]
silence-notices = ["G0262", "G0407"]
```

### 廃止予定の手順

記法と設定のキーを廃止するときは、次の順に進める。

1. 廃止を決める ADR で、廃止予定のお知らせのコードを決める。メッセージは「〜は廃止予定です」で始め、代わりの書き方を続ける。この文書の節の「直し方」に、書き換えの前と後の例を置く。
2. お知らせを出すバージョンを、少なくとも一つの minor のバージョンとしてリリースする。プレリリース（`-rc` など）だけでは数えない。リリースノートの「変更」の項に、廃止予定の書き方を挙げる。
3. 次の ADR で、その書き方をエラーにする。エラーには新しいコードを割り当て、お知らせのコードは状態を「廃止」にする。番号は使い回さない。

## 使っていない番号

次の番号は、ソースで使っていない。

- **廃止**：G0244。[docs/adr/0003](adr/0003-verse-line-breaks.md) が `@verse` の引数の誤りに定めたが、[docs/adr/0005](adr/0005-character-and-paragraph-styles.md) で使わなくなった。下に節を置く。
- **廃止**：G0235。[golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md) が `@table` のコマンドを指す CSV の誤りに定めたが、[golem-eval ADR 0004](golem-eval/adr/0004-tsv-tables.md) で表のファイルの中を指す G0285 に置き換えた。下に節を置く。
- **廃止**：G0248。[docs/adr/0005](adr/0005-character-and-paragraph-styles.md) が廃止した `@verse` に定めたが、[golem-fmt ADR 0002](golem-fmt/adr/0002-remove-verse-migration.md) で使わなくなった。下に節を置く。
- **廃止**：G0905。[golem-cli ADR 0006](golem-cli/adr/0006-preflight.md) がプリフライトの読めない図版に定めたが、[golem-pdf ADR 0008](golem-pdf/adr/0008-pdf-figures.md) で `golem build` の [G0810](#g0810) に置き換えた。下に節を置く。
- **空き**：G0104 から G0109、G0125 から G0128、G0601、G0703 から G0720、G0731、G0736、G0740、G0748、G0749、G0812。各区分の最後に使った番号より後も空いている。

## G0101

UTF-8 として不正なバイト列があります

- 重大度: エラー
- 状態: 使用中

### 意味

原稿のファイル（章と import したファイル）、`manifest.toml`、`style.toml`、`@table` の表のファイル（CSV と TSV）のどれかに、UTF-8 として読めないバイト列がある。
位置は最初の不正なバイトである。
表のファイルの誤りは、そのファイルの位置で表示し、そのファイルからは表を作らない。

- メッセージ: `UTF-8 として不正なバイト列があります`
- 段階とモジュール: 構文（golem-parser の `Golem.Parser.Read`）
- ADR: [golem-parser ADR 0009](golem-parser/adr/0009-syntax-diagnostic-codes.md)、[golem-eval ADR 0004](golem-eval/adr/0004-tsv-tables.md)（表のファイル）

### 主な原因

- Shift_JIS など、UTF-8 でない文字コードでファイルを保存した。

### 直し方

UTF-8 で保存し直す。

## G0102

ファイルの先頭に BOM があります

- 重大度: エラー
- 状態: 使用中

### 意味

原稿のファイル（章と import したファイル）、`manifest.toml`、`style.toml` のどれかが UTF-8 の BOM で始まる。
位置はバイト 0 から 3 である。
先頭以外の BOM（U+FEFF）は拒まない。
LSP では、エディタで開いているファイルにも出す。
`@table` の表のファイル（CSV と TSV）の先頭の BOM は読み飛ばすので、このコードにならない（[golem-eval ADR 0004](golem-eval/adr/0004-tsv-tables.md)）。

- メッセージ: `ファイルの先頭に BOM があります。BOM を取り除いてください`
- 段階とモジュール: 構文（golem-parser の `Golem.Parser.Read`）
- ADR: [golem-parser ADR 0009](golem-parser/adr/0009-syntax-diagnostic-codes.md)

### 主な原因

- エディタが BOM 付きの UTF-8 で保存している。

### 直し方

BOM なしの UTF-8 で保存し直す。
原稿のファイルなら、`golem fmt` でも取り除ける。

## G0103

改行に CR が含まれています

- 重大度: エラー
- 状態: 使用中

### 意味

原稿のファイル（章と import したファイル）、`manifest.toml`、`style.toml` のどれかに CR がある。
CRLF の改行の CR も、単独の CR も含む。
位置は最初の CR である。
原稿のファイルの診断には、修正案「golem fmt で LF に直す」が付く。
`golem fmt` は `style.toml` を整形しないので、`style.toml` の診断には付かない。
LSP では、エディタで開いているファイルにも出す。

- メッセージ: `改行に CR が含まれています。改行は LF に限ります`
- 段階とモジュール: 構文（golem-parser の `Golem.Parser.Read`）
- ADR: [golem-parser ADR 0009](golem-parser/adr/0009-syntax-diagnostic-codes.md)

### 主な原因

- Windows の改行（CRLF）で保存した。

### 直し方

原稿のファイルは `golem fmt` で LF に直す。
エディタの改行の設定を LF にする。

## G0110

このブロックを解釈できません

- 重大度: エラー
- 状態: 使用中

### 意味

ブロックの文法のどれにも当てはまらない行がある。

- メッセージ: `このブロックを解釈できません`
- 段階とモジュール: 構文（golem-parser）
- ADR: [golem-parser ADR 0009](golem-parser/adr/0009-syntax-diagnostic-codes.md)

### 主な原因

- ブロックの記法（見出し、箇条書き、表、ブロックコマンドなど）を書き誤った。

### 直し方

[記法](markup.md) と照らして直す。

## G0111

インデントが不正です

- 重大度: エラー
- 状態: 使用中

### 意味

行頭で、そのブロックの深さの空白の後に、さらに空白かタブがある。
たとえば、本文の段落の行頭に空白を置くとこのコードになる。
箇条書きの項目の続きの行は、深さより多い空白で始めてもよい。
位置は、余分な空白かタブから始まる。

- メッセージ: `インデントが不正です（タブ、またはブロックの深さより多い空白）`
- 段階とモジュール: 構文（golem-parser）
- ADR: [golem-parser ADR 0009](golem-parser/adr/0009-syntax-diagnostic-codes.md)

### 主な原因

- インデントにタブを使った。
- ブロックの深さより多い空白で行を始めた。

### 直し方

インデントは空白 2 個を単位とする。
タブを空白に替え、深さを 2 の倍数にそろえる。

## G0112

見出しの階層は 3 までです

- 重大度: エラー
- 状態: 使用中

### 意味

`####` 以上の見出しがある。
位置は 4 つ目の `#` から始まる。

- メッセージ: `見出しの階層は 3 までです`
- 段階とモジュール: 構文（golem-parser）
- ADR: [golem-parser ADR 0009](golem-parser/adr/0009-syntax-diagnostic-codes.md)

### 主な原因

- `####` 以上の見出しを書いた。

### 直し方

見出しは `#` から `###` までである。
構成を 3 階層に収める。

## G0113

用語のない =: があります

- 重大度: エラー
- 状態: 使用中

### 意味

定義リストの説明（`=:`）の前に、用語（`=`）の行がない。
位置は `=:` から始まる。

- メッセージ: `用語のない =: があります`
- 段階とモジュール: 構文（golem-parser）
- ADR: [golem-parser ADR 0009](golem-parser/adr/0009-syntax-diagnostic-codes.md)

### 主な原因

- 定義リストの用語の行を書き忘れた。

### 直し方

説明の前に `= 用語` の行を置く。

## G0114

表の 2 行目が区切りの行ではありません

- 重大度: エラー
- 状態: 使用中

### 意味

表の見出しの行の次の行が、`|---|` の形の区切りの行でない。

- メッセージ: `表の 2 行目は区切りの行でなければなりません`
- 段階とモジュール: 構文（golem-parser）
- ADR: [golem-parser ADR 0009](golem-parser/adr/0009-syntax-diagnostic-codes.md)

### 主な原因

- 表の見出しの行の直後に、区切りの行（`|---|`）を書き忘れた。

### 直し方

見出しの行の直後に区切りの行を書く。

## G0115

表のセルの数が見出しの行と一致しません

- 重大度: エラー
- 状態: 使用中

### 意味

表の行のセルの数が、見出しの行のセルの数と違う。
位置は、その行の終わりである。

- メッセージ: `表のセルの数が見出しの行と一致しません`
- 段階とモジュール: 構文（golem-parser）
- ADR: [golem-parser ADR 0009](golem-parser/adr/0009-syntax-diagnostic-codes.md)

### 主な原因

- 行の `|` の数が見出しの行と違う。
- 空のセルを省いた。

### 直し方

`|` の数を見出しの行にそろえる。
空のセルも `| |` と書く。

## G0116

コードブロックが閉じていません

- 重大度: エラー
- 状態: 使用中

### 意味

コードブロックの開始の行に対応する終わりの行がない。
位置はファイルの終わりである。

- メッセージ: `コードブロックが閉じていません`
- 段階とモジュール: 構文（golem-parser）
- ADR: [golem-parser ADR 0009](golem-parser/adr/0009-syntax-diagnostic-codes.md)

### 主な原因

- コードブロックの終わりの行を書き忘れた。

### 直し方

コードブロックの終わりの行を書く。

## G0117

ここに閉じ括弧 ] が必要です

- 重大度: エラー
- 状態: 使用中

### 意味

インラインのコマンド、式（`[= ...]`）、展開する引数（`*[...]`、`**[...]`）の後に、`]` が来ない。
`]` がない場合は、段落の終わりを指す。
式やコマンドの後に余計なものがある場合は、その余計なものの始まりを指す。
たとえば `[= 1 ? 2]` では、`?` の位置に出る。

- メッセージ: `ここに閉じ括弧 ] が必要です`
- 段階とモジュール: 構文（golem-parser）
- ADR: [golem-parser ADR 0009](golem-parser/adr/0009-syntax-diagnostic-codes.md)

### 主な原因

- `]` を書き忘れた。
- 式の中に、演算子でない記号を書いた。
- 本文の中の `]` が、意図より早く括弧を閉じている。

### 直し方

括弧の対応を直す。
本文に `]` を書きたいなら `\]` とエスケープする。

## G0118

コメントが段落の中で閉じていません

- 重大度: エラー
- 状態: 使用中

### 意味

`%%` で始めたコメントが、段落の終わりまでに `%%` で閉じていない。
位置は段落の終わりである。

- メッセージ: `コメントが段落の中で閉じていません`
- 段階とモジュール: 構文（golem-parser）
- ADR: [golem-parser ADR 0009](golem-parser/adr/0009-syntax-diagnostic-codes.md)

### 主な原因

- `%%` で始めたコメントを閉じ忘れた。
- コメントの途中に空行を入れた。コメントは空行を越えられない。

### 直し方

段落の中で `%%` を閉じる。

## G0119

位置引数と *[...] は、key=value と **[...] より前に書きます

- 重大度: エラー
- 状態: 使用中

### 意味

コマンドの引数で、キーワード引数の並びの後に、位置引数の並びの要素がある。
`*[式]` は位置引数として、`**[式]` はキーワード引数として数える。
位置引数の並びは位置引数と `*[式]` からなり、キーワード引数の並びは `key=value` と `**[式]` からなる。

- メッセージ: `位置引数と *[...] は、key=value と **[...] より前に書きます`
- 段階とモジュール: 構文（golem-parser）
- ADR: [golem-parser ADR 0009](golem-parser/adr/0009-syntax-diagnostic-codes.md)、[golem-parser ADR 0013](golem-parser/adr/0013-splat-after-keyword-arguments.md)

### 主な原因

- コマンドの引数で、`key=value` の後に位置引数を書いた。
- `**[式]` の後に、位置引数か `*[式]` を書いた。

### 直し方

位置引数と `*[式]` を、`key=value` と `**[式]` より前に並べる。

## G0120

式を解釈できません

- 重大度: エラー
- 状態: 使用中

### 意味

`[= ...]`、展開する引数（`*[...]`、`**[...]`）、`@set 名前 = 式` の `=` の後で、式が一つも読めない。
式を読んだ後に `]` 以外が来た場合は、[G0117](#g0117) になる。

- メッセージ: `式を解釈できません`
- 段階とモジュール: 構文（golem-parser）。式の評価（golem-eval の `Golem.Eval.Expr`）も、解析できなかった式に同じコードを出す。ただし構文エラーのあるファイルの評価の診断は表示しないので、golem-eval の G0120 は表示されない。
- ADR: [golem-parser ADR 0009](golem-parser/adr/0009-syntax-diagnostic-codes.md)

### 主な原因

- `[= ...]` の式か、展開する引数（`*[...]`、`**[...]`）の式で、演算子や括弧を書き誤った。

### 直し方

式の文法と照らして直す。

## G0121

[ の後にコマンド名も = もありません

- 重大度: エラー
- 状態: 使用中

### 意味

`[` の後に、コマンド名も `=` も続かない。
位置は `[` から始まる。

- メッセージ: `[ の後にはコマンド名か = が必要です。本文の [ は \[ と書きます`
- 段階とモジュール: 構文（golem-parser）
- ADR: [golem-parser ADR 0009](golem-parser/adr/0009-syntax-diagnostic-codes.md)

### 主な原因

- 本文に `[` を書こうとした。

### 直し方

本文の `[` は `\[` とエスケープする。

## G0122

解釈できない入力が残っています

- 重大度: エラー
- 状態: 使用中

### 意味

ラベルを持たない構文エラーである。
開始の規則の後に入力が残る場合と、開始の規則が失敗する場合に当たる。
今の文法では、どちらも起こらない。

- メッセージ: `解釈できない入力が残っています`
- 段階とモジュール: 構文（golem-parser）
- ADR: [golem-parser ADR 0009](golem-parser/adr/0009-syntax-diagnostic-codes.md)

### 主な原因

- 直前の構文の誤りに引きずられて、後ろの入力を解釈できなくなった。

### 直し方

先に出たほかの構文エラーを直す。

## G0123

表の行が | で始まらないか、| で終わりません

- 重大度: エラー
- 状態: 使用中

### 意味

表の中の行が `|` で始まらないか、`|` で終わらない。

- メッセージ: `表の行は | で始まり | で終わります`
- 段階とモジュール: 構文（golem-parser）
- ADR: [golem-parser ADR 0007](golem-parser/adr/0007-grammar-label-safety.md)

### 主な原因

- 表の中の行の端の `|` を書き忘れた。

### 直し方

行の両端に `|` を書く。

## G0124

行末の \ の次の行に段落の続きがありません

- 重大度: エラー
- 状態: 使用中

### 意味

行末の `\`（強制改行）の次の行が、同じ段落の続きの行ではない。
空行、ファイルの末尾、ブロックの始まりの文字（`#`、`- ` など）で始まる行が続いた。
見出しと定義リストの用語の行末の `\` も、このコードになる。
表の行の閉じる `|` の後に書いた `\` も、このコードになる（[golem-parser ADR 0010](golem-parser/adr/0010-ruby-slash-escape-and-table-cell-breaks.md)）。
これらは一行で書く記法なので、強制改行を書けない。

- メッセージ: `行末の \ は段落の中の強制改行です。次の行に段落の続きが要ります。本文の \ は \\ と書きます`
- 段階とモジュール: 構文（golem-parser）
- ADR: [docs/adr/0016](adr/0016-hard-line-breaks.md)、[golem-parser ADR 0010](golem-parser/adr/0010-ruby-slash-escape-and-table-cell-breaks.md)

### 主な原因

- 段落の最後の行の末尾に `\` を書いた。
- 本文の文字として、行末に `\` を置こうとした。
- 見出しや定義リストの用語の中で、行を改めようとした。
- 表の行の末尾に `\` を書いた。

### 直し方

段落の最後の行の `\` を消す。
本文の `\` を行末に置くときは、`\\` と書く。
見出し、用語、表の行は一行で書く。

## G0129

構文エラー

- 重大度: エラー
- 状態: 使用中

### 意味

コードを割り当てていない文法のラベルで解析が失敗した。
G0110 から G0123 に当たらない構文エラーの既定のコードである。

- メッセージ: `構文エラー（<ラベル>）`
- 段階とモジュール: 構文（golem-parser）
- ADR: [golem-parser ADR 0009](golem-parser/adr/0009-syntax-diagnostic-codes.md)

### 主な原因

- G0110 から G0123 に当たらない構文の誤り。メッセージのラベルが、失敗した文法の部分を示す。

### 直し方

ラベルの示す位置の記法を、[記法](markup.md) と照らして直す。

## G0201

型が合いません

- 重大度: エラー
- 状態: 使用中

### 意味

式の演算や関数に、使えない型の値を渡した。

- メッセージ: 型の誤りを述べる文言。たとえば `- は <型> に使えません`、`<型> と <型> にこの演算子は使えません`、`<型> は数ではありません`、`<型> の要素は参照できません`、`% は整数にだけ使えます`、`div は整数にだけ使えます`、`join の配列には文字列だけを並べます`、`join は文字列の配列と区切りの文字列に使えます`。
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.Expr`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)。[docs/adr/0033](adr/0033-colophon-contributors-and-printings.md) が `join` の誤りを加えた

### 主な原因

- 文字列と数の演算など、型の合わない値を演算子や関数に渡した。
- `join` に、文字列でない要素を持つ配列か、配列でない値を渡した。区切りに文字列でない値を渡した。

### 直し方

値の型をそろえる。

## G0202

未定義の名前です

- 重大度: エラー
- 状態: 使用中

### 意味

式が、定義されていない変数、名前空間、要素を参照した。

- メッセージ: `未定義の名前 <名前> です`、`未定義の名前空間 <名前空間> です`、`名前がありません`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.Expr`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)。[docs/adr/0033](adr/0033-colophon-contributors-and-printings.md) が `meta.roles` などの例を加えた

### 主な原因

- 名前の綴りを誤った。
- `@set` や `@import` を書き忘れた。
- マニフェストにない値を `meta` で引いた。その役割の項目がない `meta.roles.binder`、`printings` のない本の `meta.printing`、`publisher-person` のない本の `meta.publisher_person` などである。

### 直し方

定義を確かめ、綴りを直すか定義を書く。

## G0203

0 で割っています

- 重大度: エラー
- 状態: 使用中

### 意味

`/`、`%`、`div`、または 0 の負の冪で、0 で割った。

- メッセージ: `0 で割っています`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.Expr`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- 割る数が 0 になった。

### 直し方

割る数が 0 にならないように式を直す。

## G0204

結果が NaN か無限大になります

- 重大度: エラー
- 状態: 使用中

### 意味

浮動小数点の計算の結果が NaN か無限大になった。
または、浮動小数点数に変換する整数が大きすぎ、変換すると無限大になる（絶対値が 2^1024 - 2^970 以上）。
整数は、整数と浮動小数点数の `+`、`-`、`*`、`/` と、`sqrt`、`round`、`fixed` の引数で浮動小数点数に変換する。

- メッセージ: `結果が NaN か無限大になる演算です`、`負の数の平方根です`、`整数が大きすぎて浮動小数点数に変換できません`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.Expr`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)、[golem-eval ADR 0005](golem-eval/adr/0005-float-overflow.md)

### 主な原因

- 負の数の平方根など、浮動小数点の計算が NaN か無限大になる演算をした。
- `2.0 ** 1024` や `10 ** 400 / 3` のように、結果が倍精度の範囲を超えた。
- `10 ** 309 + 0.5` のように、大きな整数と浮動小数点数を混ぜて計算した。

### 直し方

値の範囲を確かめ、式を直す。

## G0205

校正用のコメントが残っています

- 重大度: 警告
- 状態: 使用中

### 意味

prod でビルドした原稿に、校正用のコメント（`%%=` で始まるコメント）がある。
prod では、このコメントを出力から落とす。
dev では出力に残し、診断は出さない。

- メッセージ: `校正用のコメントが残っています`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)（[golem-pdf ADR 0004](golem-pdf/adr/0004-crop-marks-and-bleed.md) が触れる）

### 主な原因

- prod でビルドする原稿に、校正用のコメント（`%%=`）を残した。

### 直し方

校正の済んだコメントを消す。

## G0206

** の指数は整数に限ります

- 重大度: エラー
- 状態: 使用中

### 意味

`**` の指数に浮動小数点数を書いた。

- メッセージ: `** の指数は整数に限ります`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.Expr`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- `**` の指数に浮動小数点数を書いた。

### 直し方

指数を整数にする。
平方根なら `sqrt` を使う。

## G0207

関数の引数が不正です

- 重大度: エラー
- 状態: 使用中

### 意味

組み込みの関数に、誤った数か型の引数を渡した。
引数のない `min()` と `max()` も、このコードになる。
存在しない関数の呼び出しは [G0261](#g0261) である。

- メッセージ: `<関数> の引数が不正です`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.Expr`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- 引数の数か型が違う。

### 直し方

関数の引数の数と型を確かめる。

## G0208

本文に埋め込めない値です

- 重大度: エラー
- 状態: 使用中

### 意味

`[= ...]` の式の値が、本文に埋め込めない型（配列、連想配列など）である。
位置は `[= ...]` のインラインである。
`doc` を参照する式は文書の組み立て（S1）で評価するが、その場合も位置は同じである。

- メッセージ: `<型> は本文に埋め込めません`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.Expr`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- 配列やハッシュなど、本文に埋め込めない型の値を `[= ...]` で埋め込もうとした。

### 直し方

埋め込めるのは整数、浮動小数点数、文字列である。
要素を取り出すか、文字列にする。

## G0209

未知のブロックコマンドです

- 重大度: エラー
- 状態: 使用中

### 意味

組み込みにないブロックコマンドを使った。

- メッセージ: `未知のブロックコマンドです: @<名前>`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- ブロックコマンドの名前の綴りを誤った。

### 直し方

コマンド名の綴りを確かめる。

## G0210

属性の後にブロックがありません

- 重大度: エラー
- 状態: 使用中

### 意味

属性のブロックコマンド（`@label`、`@number`、`@style` など）の後に、属性を付ける対象のブロックがない。

- メッセージ: `属性の後にブロックがありません`、`@<名前> の後にブロックがありません`、`@style の後にブロックがありません`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)（[docs/adr/0005](adr/0005-character-and-paragraph-styles.md) が `@style` の条件を加えた。[docs/adr/0003](adr/0003-verse-line-breaks.md) も触れる）

### 主な原因

- 属性の行（`@label`、`@number`、`@style` など）の後に、空行かファイルの終わりが来た。

### 直し方

属性の行の直後に、対象の段落かブロックを置く。

## G0211

属性のまとまりに属性でないコマンドがあります

- 重大度: エラー
- 状態: 使用中

### 意味

属性のまとまり（続けて書いた属性の行）に、属性でないブロックコマンドが混ざっている。
混ざった `@set` などのコマンドも、書いた順に評価する。

- メッセージ: `属性のまとまりに属性でないコマンドがあります`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)（[docs/adr/0005](adr/0005-character-and-paragraph-styles.md)、[docs/adr/0013](adr/0013-paragraph-separator.md)、[docs/adr/0014](adr/0014-in-file-settings.md) が触れる）

### 主な原因

- 続けて書いた属性の行のあいだに、属性でないブロックコマンドを書いた。

### 直し方

属性でないコマンドと属性のまとまりのあいだに空行を入れるか、属性の対象にしたいブロックを最後に置く。

## G0212

同じ属性を二度書いています

- 重大度: エラー
- 状態: 使用中

### 意味

一つのブロックに、同じ属性を二度付けた。
位置は、重複した属性の二つ目以降の行である。
重複した行のそれぞれに一つずつ出る。

- メッセージ: `同じ属性を二度書いています`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- 一つのブロックに、同じ属性の行を二度書いた。

### 直し方

重複した属性の行を消す。

## G0213

このブロックには付けられない属性です

- 重大度: エラー
- 状態: 使用中

### 意味

その種類のブロックに付けられない属性を付けた。
たとえば、見出しでないブロックへの `@notoc`、段落でないブロックへの `@style`、図版のキャプションの中の `@style`、コードブロックでないブロックへの `@caption` である。

- メッセージ: `@<名前> はこのブロックには付けられません`、`@style は図版のキャプションには付けられません`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)（[docs/adr/0005](adr/0005-character-and-paragraph-styles.md) が `@style` の条件を加えた。[golem-driver ADR 0010](golem-driver/adr/0010-caption-style.md) も触れる）

### 主な原因

- 見出しでないブロックに `@notoc` を付けた。
- 段落でないブロックか、図版のキャプションに `@style` を付けた。

### 直し方

属性を外すか、付けられるブロックに移す。
キャプションの見た目は `style.toml` の `[paragraph-styles.caption]` で決める。

## G0214

見出しの中では doc も相互参照も使えません

- 重大度: エラー
- 状態: 使用中

### 意味

見出しの中で、`doc` を使う式か、相互参照（`ref-number`、`ref-title`、`ref-page`）を使った。

- メッセージ: `見出しの中では doc を参照できません`、`見出しの中では相互参照を使えません`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- 見出しの中で、`doc` を使う式か、相互参照（`ref-number`、`ref-title`、`ref-page`）を使った。

### 直し方

参照を見出しの外の本文に移す。

## G0215

ルビの対象と読みの数が一致しません

- 重大度: エラー
- 状態: 使用中

### 意味

`/` で区切ったルビの対象と読みのセグメントの数が合わない。
対象を区切らず、読みだけを `/` で区切った場合も、このコードになる。
区切りになるのは原稿に書いた `/` だけであり、`\/` と書いた `/` と、式の値の中の `/` は区切りにならない（[golem-parser ADR 0010](golem-parser/adr/0010-ruby-slash-escape-and-table-cell-breaks.md)）。

- メッセージ: `モノルビの対象と読みのセグメントの数が一致しません`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)、[golem-parser ADR 0010](golem-parser/adr/0010-ruby-slash-escape-and-table-cell-breaks.md)

### 主な原因

- `/` で区切ったルビの対象と読みで、`/` の数が違う。
- 対象を区切らずに、読みに `/` を書いた。

### 直し方

対象と読みの `/` の数をそろえる。
区切りでない `/` を対象や読みに書くときは、`\/` と書く。

## G0216

ルビの中にルビは入れられません

- 重大度: エラー
- 状態: 使用中

### 意味

ルビの対象の中に、さらにルビがある。

- メッセージ: `ルビの中にルビは入れられません`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- ルビの対象の中に、さらにルビを書いた。

### 直し方

入れ子のルビを外す。

## G0217

style.toml にないスウォッチです

- 重大度: エラー
- 状態: 使用中

### 意味

`[color ...]` に、`style.toml` の `[color.swatches]` にない名前を書いたか、名前を一つ書かなかった。
名前の代わりに `[= ...]` やコマンドを書いた場合は、「一つ書きます」の側のメッセージになる。

- メッセージ: `style.toml にないスウォッチです: <名前>`、`color にはスウォッチの名前を一つ書きます`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- `[color ...]` の色の名前の綴りを誤った。
- `style.toml` の `[color.swatches]` に色を定義していない。
- 名前を書かなかったか、二つ以上書いた。

### 直し方

`[color.swatches]` に色を定義するか、名前の綴りを直す。

## G0218

定義されていない文字スタイルです

- 重大度: エラー
- 状態: 使用中

### 意味

`[style ...]` に、`style.toml` にもそのファイルの `@style-def` にもない文字スタイルの名前を書いたか、名前を一つ書かなかった。
名前の代わりに `[= ...]` やコマンドを書いた場合は、「一つ書きます」の側のメッセージになる。

- メッセージ: `定義されていない文字スタイルです: <名前>`、`style には文字スタイルの名前を一つ書きます`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)（メッセージは [docs/adr/0014](adr/0014-in-file-settings.md) が改めた）

### 主な原因

- `[style ...]` の名前の綴りを誤った。
- `style.toml` の `[character-styles]` にも、ファイルの先頭の `@style-def character` にも定義していない。
- 名前を書かなかったか、二つ以上書いた。

### 直し方

`style.toml` の `[character-styles]` か、ファイルの先頭の `@style-def character` に定義するか、名前の綴りを直す。

## G0219

number-text の引数が不正です

- 重大度: エラー
- 状態: 使用中

### 意味

`[number-text ...]` の引数が不正である。

- メッセージ: `style は kanji、kanji-digits、tcy のいずれかです: <値>`、`number-text に渡せるのは整数だけです`、`number-text には整数を一つ書きます`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- `[number-text ...]` に整数でない値を渡したか、整数を一つ書かなかった。
- `style` に定義されていない値を書いた。

### 直し方

整数を一つ渡し、`style` には `kanji`、`kanji-digits`、`tcy` のどれかを書く。

## G0220

索引には reading が必要です

- 重大度: エラー
- 状態: 使用中

### 意味

`[index ...]` に読み（`reading`）がない。

- メッセージ: `索引には reading が必要です`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- `[index ...]` に読みを書き忘れた。

### 直し方

`reading=` で語の読みを書く。

## G0221

書誌データにないキーです

- 重大度: エラー
- 状態: 使用中

### 意味

`[cite ...]` のキーが書誌データにないか、キーを一つ書かなかった。
キーの代わりに `[= ...]` やコマンドを書いた場合は、「一つ書きます」の側のメッセージになる。

- メッセージ: `書誌データにないキーです: <キー>`、`cite には書誌データのキーを一つ書きます`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- `[cite ...]` のキーの綴りを誤った。
- 書誌データに項目がない。
- キーを書かなかったか、二つ以上書いた。

### 直し方

書誌データのキーの綴りを確かめる。

## G0222

未知のコマンドです

- 重大度: エラー
- 状態: 使用中

### 意味

インラインのコマンドが、組み込みにもプラグインにもない。
位置はコマンドの名前である。

- メッセージ: `未知のコマンドです: <名前>`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)、[ADR 0027](adr/0027-exhaustive-command-dispatch-by-types.md)

### 主な原因

- インラインのコマンドの名前の綴りを誤った。
- プラグインのコマンドを使ったが、`manifest.toml` にプラグインを宣言していない。

### 直し方

コマンド名の綴りを確かめる。
プラグインのコマンドなら、`manifest.toml` にプラグインを宣言する。
プラグインの読み込みか検査が誤り（[G0602](#g0602) から [G0608](#g0608)、[G0610](#g0610)、[G0611](#g0611)）を出したときは、未知のコマンドを報告しない（[golem-plugin ADR 0003](golem-plugin/adr/0003-plugin-diagnostic-codes.md)）。
プラグインの誤りを直した後のビルドで報告する。

## G0223

予約語は名前に使えません

- 重大度: エラー
- 状態: 使用中

### 意味

`@set` の変数か `@import` の名前空間に、予約語を使った。
予約語は `doc`、`meta`、`true`、`false`、`nil` である。
位置は、変数の名前か名前空間の語である。

- メッセージ: `予約語は変数の名前に使えません: <名前>`、`予約語は名前空間に使えません: <名前>`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- `@set` の変数か `@import` の名前空間に、予約語を使った。

### 直し方

ほかの名前に替える。

## G0224

変数を二度定義しています

- 重大度: エラー
- 状態: 使用中

### 意味

同じファイルで、同じ変数を `@set` で二度定義した。

- メッセージ: `変数を二度定義しています: <名前>`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- 同じファイルで、同じ変数を `@set` で二度定義した。

### 直し方

変数は一度だけ定義する。
片方を消すか、名前を変える。

## G0225

@toc の depth は 1 から 3 の整数です

- 重大度: エラー
- 状態: 使用中

### 意味

`@toc` の `depth` が 1 から 3 の整数でない。

- メッセージ: `@toc の depth は 1 から 3 の整数です`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- `@toc` の `depth` に、1 から 3 の整数でない値を書いた。

### 直し方

`depth` を 1 から 3 にする。

## G0226

ラベルの名前を一つ書きます

- 重大度: エラー
- 状態: 使用中

### 意味

`@label` か相互参照のコマンドに、ラベルの名前として使える語を一つ書かなかった。

- メッセージ: `@label にはラベルの名前を一つ書きます。名前は英小文字、数字、-、_ で書きます`、`参照にはラベルの名前を一つ書きます。名前は英小文字、数字、-、_ で書きます`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- `@label` か相互参照のコマンドに、ラベルの名前を書かなかったか、名前として使えない値を書いた。
- 名前に英大文字など、英小文字、数字、`-`、`_` 以外の文字を使った。

### 直し方

ラベルの名前を一つ、英小文字、数字、`-`、`_` で書く。

## G0227

@number には整数を一つ書きます

- 重大度: エラー
- 状態: 使用中

### 意味

`@number` の引数が整数一つでない。

- メッセージ: `@number には整数を一つ書きます`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- `@number` の引数に、整数でない値を書いたか、引数の数が違う。

### 直し方

番号を整数で一つ書く。

## G0228

図版には alt の代替テキストが必要です

- 重大度: エラー
- 状態: 使用中

### 意味

`@figure` に `alt` がない。

- メッセージ: `図版には alt の代替テキストが必要です`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- `@figure` に `alt` を書き忘れた。

### 直し方

`alt=` で画像の代替テキストを書く。

## G0229

PDF の図版には web の代替画像が必要です

- 重大度: エラー
- 状態: 使用中

### 意味

PDF の画像を `@figure` に使い、HTML と EPUB のための `web` の代替画像を書かなかった。

- メッセージ: `PDF の図版には web の代替画像が必要です`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- PDF の画像を `@figure` に使い、HTML と EPUB のための代替画像を書かなかった。

### 直し方

`web=` で PNG などの代替画像を指す。

## G0230

wrap は start か end です

- 重大度: エラー
- 状態: 使用中

### 意味

`@figure` の `wrap` の値が `start` でも `end` でもない。

- メッセージ: `wrap は start か end です: <値>`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- `@figure` の `wrap` に、`start` でも `end` でもない値を書いた。

### 直し方

`wrap=start` か `wrap=end` にする。

## G0231

回り込む図版には width が必要です

- 重大度: エラー
- 状態: 使用中

### 意味

`wrap` を書いた図版に `width` がない。

- メッセージ: `回り込む図版には width が必要です`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- `wrap` を書いた図版に `width` を書き忘れた。

### 直し方

`width=` で図版の幅を書く。

## G0232

@figure には画像のパスを一つ書きます

- 重大度: エラー
- 状態: 使用中

### 意味

`@figure` の位置引数が画像のパス一つでない。

- メッセージ: `@figure には画像のパスを一つ書きます`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- `@figure` の位置引数を書かなかったか、二つ以上書いた。

### 直し方

画像のパスを一つ書く。

## G0233

ファイルがありません

- 重大度: エラー
- 状態: 使用中

### 意味

`@figure`、`@table`、`@listing` が指すファイルがない。
パスが絶対パス、URL、プロジェクトのルートの外を指す場合は、このコードでなく [G0260](#g0260) である。

- メッセージ: `ファイルがありません: <パス>`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- `@figure`、`@table`、`@listing` のパスの綴りを誤った。
- ファイルを置いていない。

### 直し方

パスはプロジェクトのルートからの相対パスである。
綴りとファイルの置き場所を確かめる。

## G0234

@table には src が必要です

- 重大度: エラー
- 状態: 使用中

### 意味

`@table` に `src` がない。

- メッセージ: `@table には src が必要です`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- `@table` に `src` を書き忘れた。

### 直し方

`src=` で CSV か TSV のファイルを指す。

## G0235

CSV が空か、行ごとのセルの数が一致しません

- 重大度: エラー
- 状態: 廃止

### 意味

廃止した。
`@table` の CSV が空か、行ごとのセルの数がそろっていないことを、`@table` のコマンドの位置で報告するコードだった。
今は同じ誤りを、表のファイルの中の位置で [G0285](#g0285) として報告する。

- メッセージ: `CSV が空です`、`CSV の行ごとのセルの数が一致しません`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)（定めた）、[golem-eval ADR 0004](golem-eval/adr/0004-tsv-tables.md)（廃止した）

### 直し方

[G0285](#g0285) の直し方に従う。

## G0236

@listing にはファイルのパスが必要です

- 重大度: エラー
- 状態: 使用中

### 意味

`@listing` にファイルのパスがない。

- メッセージ: `@listing にはファイルのパスが必要です`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- `@listing` にファイルのパスを書き忘れた。

### 直し方

位置引数か `src=` でファイルを指す。

## G0237

lines の範囲が不正です

- 重大度: エラー
- 状態: 使用中

### 意味

`@listing` の `lines` が `開始-終了` の形でないか、ファイルの行の範囲を外れる。

- メッセージ: `lines の範囲が不正です: <値>`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- `@listing` の `lines` が `開始-終了` の形でない。
- 範囲がファイルの行の範囲を外れる。

### 直し方

`lines=3-10` のように、1 以上でファイルの行数以下の範囲を書く。

## G0238

散文スロットの数が違います

- 重大度: エラー
- 状態: 使用中

### 意味

インラインのコマンドの散文スロット（`: ` の後の本文）の数が違う。
`number-text`、`ref-number`、`ref-title`、`ref-page`、`cite` は散文スロットを取らないので、書くとこのコードになり、コマンドは出力しない。

- メッセージ: `<名前> には散文スロットが一つ必要です`、`index には散文スロットが一つ必要です`、`ruby には散文スロットが二つ必要です`、`<名前> は散文スロットを取りません`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- インラインのコマンドの `: ` の後の本文（散文スロット）の数を誤った。

### 直し方

コマンドの書き方を確かめ、スロットの数をそろえる。
ルビは対象と読みの二つを書く。
散文スロットを取らないコマンドからは、`: ` の後の本文を消す。

## G0239

未知の圏点の形です

- 重大度: エラー
- 状態: 使用中

### 意味

`[kenten ...]` の `shape` が定義された形でない。

- メッセージ: `未知の圏点の形です: <形>`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- `[kenten ...]` の `shape` に、定義されていない形を書いた。

### 直し方

`sesame`、`open-sesame`、`dot`、`open-dot`、`circle`、`open-circle`、`double-circle`、`open-double-circle`、`triangle`、`open-triangle` のどれかにする。
形の一覧は [docs/markup.md](markup.md) の「圏点」にある（[golem-driver ADR 0019](golem-driver/adr/0019-pdf-kenten-shapes.md)）。

## G0240

縦中横の中身は地の文に限ります

- 重大度: エラー
- 状態: 使用中

### 意味

`[tcy ...]` の中に、地の文でないもの（コマンドなど）がある。

- メッセージ: `縦中横の中身は地の文に限ります`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)（[docs/adr/0003](adr/0003-verse-line-breaks.md) が触れる）

### 主な原因

- `[tcy ...]` の中にコマンドなどを書いた。

### 直し方

縦中横の中は文字だけにする。

## G0241

索引の語は地の文に限ります

- 重大度: エラー
- 状態: 使用中

### 意味

`[index ...]` の語に、地の文でないものがある。

- メッセージ: `索引の語は地の文に限ります`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- `[index ...]` の語の中にコマンドなどを書いた。

### 直し方

索引の語は文字だけにする。

## G0242

索引の語と読みの段の数が不正です

- 重大度: エラー
- 状態: 使用中

### 意味

`/` で区切った索引の語の段が 3 段以上あるか、語と読みの段の数が違うか、空の段がある。
語の中の `\/` と、式の値の中の `/` は段の区切りにならない（[golem-parser ADR 0010](golem-parser/adr/0010-ruby-slash-escape-and-table-cell-breaks.md)）。

- メッセージ: `索引の語と読みの段の数が不正です`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- `/` で区切った索引の語の段が 3 段以上ある。
- 語と読みで段の数が違う。
- 空の段がある。

### 直し方

段は 2 段までとし、語と読みの `/` の数をそろえる。
区切りでない `/` を語に書くときは、`\/` と書く。

## G0243

ルビの読みは地の文に限ります

- 重大度: エラー
- 状態: 使用中

### 意味

ルビの読みに、地の文でないものがある。

- メッセージ: `ルビの読みは地の文に限ります`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)（[docs/adr/0003](adr/0003-verse-line-breaks.md) が触れる）

### 主な原因

- ルビの読みの中にコマンドなどを書いた。

### 直し方

読みは文字だけにする。

## G0244

@verse は引数を取りません

- 重大度: エラー
- 状態: 廃止

### 意味

廃止した。
`@verse` の引数の誤りに定めたが、`@verse` は `@style verse` に変わり、このコードは出なくなった。

- メッセージ: `@verse は引数を取りません`
- 段階とモジュール: 評価（golem-eval）
- ADR: [docs/adr/0003](adr/0003-verse-line-breaks.md)（定めた）、[docs/adr/0005](adr/0005-character-and-paragraph-styles.md)（使わなくした）

### 直し方

`@verse` は `@style verse` に変わった（[docs/adr/0005](adr/0005-character-and-paragraph-styles.md)）。
行を保つ段落は `@style verse` と書く。
今 `@verse` を書くと、ほかの未知のブロックコマンドと同じ [G0209](#g0209) になる。

## G0245

@style の本体には段落だけを置けます

- 重大度: エラー
- 状態: 使用中

### 意味

本体の形の `@style` の本体に、段落でないブロック（箇条書きなど）がある。

- メッセージ: `@style の本体には段落だけを置けます。段落は空行で区切ります`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [docs/adr/0003](adr/0003-verse-line-breaks.md)（`@verse` に定めた）、[docs/adr/0005](adr/0005-character-and-paragraph-styles.md)（`@style` に一般化した）

### 主な原因

- 本体の形の `@style` の本体に、箇条書きなど段落でないブロックを書いた。

### 直し方

本体には段落だけを置く。
ほかのブロックは `@style` の外に出す。
段落は空行で区切る。

## G0246

@style の本体に段落がありません

- 重大度: エラー
- 状態: 使用中

### 意味

本体の形の `@style` の本体に、段落が一つもない。

- メッセージ: `@style の本体に段落がありません`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [docs/adr/0003](adr/0003-verse-line-breaks.md)（`@verse` に定めた）、[docs/adr/0005](adr/0005-character-and-paragraph-styles.md)（`@style` に一般化した）

### 主な原因

- 本体の形の `@style` の本体を書かなかったか、インデントが足りない。

### 直し方

本体の段落を、`@style` の行より 2 つ深くインデントして書く。

## G0247

定義されていない段落スタイルです

- 重大度: エラー
- 状態: 使用中

### 意味

`@style` の段落スタイルが、`style.toml` にもそのファイルの `@style-def` にもないか、名前を一つ書かなかった。
`@import` したファイルの `@style-def` は、取り込む側では使えない。
フィルタのプラグインが、定義されていない段落スタイルの段落を返した場合も出る。

- メッセージ: `定義されていない段落スタイルです: <名前>`、`@style には段落スタイルの名前を一つ書きます`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [docs/adr/0005](adr/0005-character-and-paragraph-styles.md)（メッセージは [docs/adr/0014](adr/0014-in-file-settings.md) が改めた）

### 主な原因

- `@style` の段落スタイルの名前の綴りを誤った。
- `style.toml` の `[paragraph-styles]` にも、ファイルの先頭の `@style-def paragraph` にも定義していない。
- 名前を書かなかったか、二つ以上書いた。
- フィルタのプラグインが、定義されていない段落スタイルの段落を返した。

### 直し方

`style.toml` の `[paragraph-styles]` か、ファイルの先頭の `@style-def paragraph` に定義するか、名前の綴りを直す。

## G0248

@verse は @style verse に変わりました

- 重大度: エラー
- 状態: 廃止

### 意味

廃止した。
廃止した `@verse` に定めたが、`@verse` はほかの未知のブロックコマンドと同じ [G0209](#g0209) になり、このコードは出なくなった。
`golem fmt` も `@verse` を書き換えなくなった。

- メッセージ: `@verse は @style verse に変わりました。golem fmt で書き換えられます`
- 段階とモジュール: 評価（golem-eval）
- ADR: [docs/adr/0005](adr/0005-character-and-paragraph-styles.md)（定めた）、[golem-fmt ADR 0002](golem-fmt/adr/0002-remove-verse-migration.md)（使わなくした）

### 直し方

`@verse` を `@style verse` に書き換える。

## G0249

@manifest と @style-def はファイルの最初に置きます

- 重大度: エラー
- 状態: 使用中

### 意味

ファイルの設定の並びの外に、`@manifest` か `@style-def` がある。
属性のまとまりの途中（`@label` の後など）に書いた場合も出る。
その行は、上書きと定義としては扱わない。

- メッセージ: `@manifest と @style-def はファイルの最初に置きます`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [docs/adr/0014](adr/0014-in-file-settings.md)

### 主な原因

- 本文の途中や末尾に `@manifest` か `@style-def` を書いた。
- `@label` などの属性の後に書いた。

### 直し方

`@manifest` と `@style-def` をファイルの先頭に集める。
前に置いてよいのは、コメントと空行だけである。

## G0250

ファイルの中で上書きできない設定です

- 重大度: エラー
- 状態: 使用中

### 意味

`@manifest` のキーが、ファイルの中で上書きできる `[source]` のキーでない。
マニフェストにはあるが上書きできないキー（`title` など）と、未知のキーの両方に出る。
そのキーは無視し、同じ `@manifest` のほかのキーの上書きは適用する。

- メッセージ: `ファイルの中で上書きできない設定です: <キー>。上書きできるのは paragraph-separator です`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.Settings`）
- ADR: [docs/adr/0014](adr/0014-in-file-settings.md)

### 主な原因

- 書名や出力ターゲットのように、本の全体で一つの値を `@manifest` で変えようとした。
- キーの綴りを誤った。

### 直し方

本の全体の設定は `manifest.toml` に書く。
ファイルの中で変えられるのは `[source]` のキー（`paragraph-separator`）だけである。

## G0251

@manifest の値が不正です

- 重大度: エラー
- 状態: 使用中

### 意味

`@manifest` の `[source]` のキーの値が、受け付ける値でない。
そのキーの上書きは適用されない。

- メッセージ: `paragraph-separator は "blank-line" か "line" です: <値>`（`[source]` のキーの表が返すメッセージ）
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.Settings`）
- ADR: [docs/adr/0014](adr/0014-in-file-settings.md)

### 主な原因

- 値の綴りを誤った（`lines` など）。

### 直し方

`paragraph-separator` には `blank-line` か `line` を書く。

## G0252

@manifest か @style-def の引数の形が誤っています

- 重大度: エラー
- 状態: 使用中

### 意味

`@manifest` か `@style-def` の引数の形が誤っている。
位置引数の数の誤り、未知の種類、展開する引数（`*[...]`、`**[...]`）、本体がある、`@manifest` に引数がない、同じキーを二度書いた、値が語と文字列のほか（`[= ...]` など）のいずれかである。
誤りのある `@manifest` の引数はその引数だけを無視し、誤りのある `@style-def` は定義の全体を捨てる。

- メッセージ: `@manifest には key=value だけを書きます`、`@style-def には種類（character、paragraph、regex）と名前を書きます`、`値は語か文字列で書きます`、`同じキーを二度書いています: <キー>`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.Settings`）
- ADR: [docs/adr/0014](adr/0014-in-file-settings.md)

### 主な原因

- `@style-def` の種類か名前を書き忘れた。
- 一つのスタイルの欄を、字下げした続きの行に書いた。
- 値を式で書いた。

### 直し方

メッセージの示す形に直す。
一つのスタイルは一行の `@style-def` で定義し、値は語か文字列で書く。

## G0253

同じ名前のスタイルを二度定義しています

- 重大度: エラー
- 状態: 使用中

### 意味

同じファイルの中で、同じ種類の同じ名前のスタイルを `@style-def` で二度定義した。
二つ目以降の定義は捨てる。
`style.toml` と組み込みのスタイルと同じ名前は、上書きとして受け付けるので、このコードにならない。

- メッセージ: `同じ名前のスタイルを二度定義しています: <名前>`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.Settings`）
- ADR: [docs/adr/0014](adr/0014-in-file-settings.md)

### 主な原因

- 一つのスタイルの欄を、二つの `@style-def` に分けて書いた。

### 直し方

定義を一つの `@style-def` にまとめる。

## G0254

正規表現スタイルはまだ実装していません

- 重大度: エラー
- 状態: 廃止

### 意味

廃止した。
正規表現スタイルを実装するまでの暫定のコードとして `@style-def regex` に定めたが、正規表現スタイルを実装し、このコードは出なくなった。
番号は再利用しない。

- メッセージ: `正規表現スタイルはまだ実装していません`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.Settings`）
- ADR: [docs/adr/0014](adr/0014-in-file-settings.md)（定めた）、[docs/adr/0015](adr/0015-regex-styles.md)（使わなくした）

### 直し方

`@style-def regex 段落スタイル pattern="..." style=文字スタイル` と書く（[docs/adr/0015](adr/0015-regex-styles.md)）。

## G0255

アキの量が正しくありません

- 重大度: エラー
- 状態: 使用中

### 意味

`[aki 量]` の書き方が正しくない。
`[aki]` は位置引数を一つだけ取り、散文スロットを取らない。
量は、アキの量の名前、`zw` の小数、百分率、絶対の寸法のどれかである。
誤った `[aki]` は何も置かない。

- メッセージ: `<理由>。量には、ベタ、全角、二分、三分、四分、五分、六分、八分、二分四分のどれか、0.2zw のような zw、25% のような百分率、1mm のような寸法のどれかを書きます`。理由は `aki には量を一つ書きます`、`アキの量を読めません: <値>`、`aki は散文スロットを取りません` のどれかである。
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [docs/adr/0019](adr/0019-aki-settings.md)

### 主な原因

- `[aki]` に量を書かなかったか、二つ以上書いたか、キーワード引数で書いた。
- 量の名前を誤った（`十分` など）か、負の量を書いた。
- `[aki 四分: 語]` のように散文スロットを書いた。

### 直し方

`[aki 四分]`、`[aki 0.2zw]`、`[aki 25%]`、`[aki 1mm]` のように、量を一つだけ書く。
空きを入れたい二つの文字の間に `[aki]` を置き、文字は `[aki]` の外に書く。

## G0256

コマンドの中に強制改行があります

- 重大度: エラー
- 状態: 使用中

### 意味

散文スロットの中（`[note: a\` の後に改行など）に、行末の `\` による強制改行がある。
強制改行は、段落の最上位にだけ書ける。
強制改行は無視され、前後の行はそのままつながる。

- メッセージ: `強制改行は段落の中にだけ書けます。コマンドの中では使えません`
- 段階とモジュール: 評価（golem-eval）
- ADR: [docs/adr/0016](adr/0016-hard-line-breaks.md)

### 主な原因

- 注や文字スタイルの本文の中で、行を改めようとした。
- 行をまたぐ斜体などのコマンドの中で、行末に `\` を書いた。

### 直し方

コマンドの中の行末の `\` を消す。
行をまたいで斜体などを続けたいときは、行ごとにコマンドを閉じて開き直し、`\` をコマンドの外に書く。

## G0257

強制改行で中身のない行ができます

- 重大度: エラー
- 状態: 使用中

### 意味

強制改行で、中身のない行ができる。
段落の最初の行が `\` だけの場合、`\` だけの行が続く場合、`\` の次の行がコメントだけの場合に出る。
中身のない行は捨てられる。

- メッセージ: `強制改行の前後に文字がありません`
- 段階とモジュール: 評価（golem-eval）
- ADR: [docs/adr/0016](adr/0016-hard-line-breaks.md)

### 主な原因

- 空の行で、行のあいだに空きを作ろうとした。
- `\` を二つの行に続けて書いた。

### 直し方

中身のない行と、その前の `\` を消す。
行のあいだの空きは、強制改行では作れない。

## G0258

@page-break の引数が誤っています

- 重大度: エラー
- 状態: 使用中

### 意味

`@page-break` の引数が、`recto` か `verso` の位置引数一つでない。
`@page-break` は位置引数を一つまで取り、それは `recto` か `verso` である。
引数を二つ以上書いた場合と、キーワード引数を書いた場合も、この誤りとする。
誤ったコマンドは捨て、改ページしない。
位置はコマンドの行である。
本体も書いていれば、G0297 も出る。

- メッセージ: `@page-break の引数は recto か verso です`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [docs/adr/0017](adr/0017-forced-page-breaks.md)、[docs/adr/0060](adr/0060-page-break-command-codes-by-cause.md)

### 主な原因

- `@page-break page` のように、`recto` と `verso` のほかの語を書いた。
- `@page-break recto verso` のように、引数を二つ以上書いた。
- `@page-break x=1` のように、キーワード引数を書いた。

### 直し方

ただの改ページは `@page-break` とだけ書き、奇数ページから始めるなら `@page-break recto`、偶数ページから始めるなら `@page-break verso` と書く。

## G0259

改ページのコマンドは文書の最上位にだけ置けます

- 重大度: エラー
- 状態: 使用中

### 意味

`@page-break` か `@column-break` を、リストの項目、定義リストの説明、ブロックコマンドの本体（`@figure` のキャプションなど）の中に置いた。
改ページは本文の流れの中の一点を表すので、文書の最上位のブロックの間にだけ置ける。
その位置のコマンドは捨て、改ページしない。
フィルタのプラグインが最上位でない位置に改ページを置いた場合は、このコードではなく、プラグインの出力の誤りになる。

- メッセージ: `@page-break と @column-break は文書の最上位にだけ置けます`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [docs/adr/0017](adr/0017-forced-page-breaks.md)

### 主な原因

- リストの項目や定義リストの説明の中に、字下げして `@page-break` を書いた。
- `@figure` の次の行を字下げして `@page-break` を書き、キャプションの中に入れた。

### 直し方

字下げをやめて、リストや図版の前か後ろに、文書の最上位のブロックとして書く。
本体の形の `@style` の中に書いた場合は、このコードではなく [G0245](#g0245) になる。

## G0260

使えないパスです

- 重大度: エラー
- 状態: 使用中

### 意味

`@figure`、`@table`、`@listing` のパスが、絶対パス、URL、またはプロジェクトのルートの外を指す。
ルートの外を指すのは、`..` で外に出るパスと、外を指すシンボリックリンクである。
その図版、表、ソースコードのリストは作らない。

- メッセージ: `絶対パスは使えません: <パス>`、`URL は使えません: <パス>`、`プロジェクトルートの外を指しています: <パス>`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`。パスは golem-driver が `resolveInRoot` で調べる）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- `/` から始まる絶対パスを書いた。
- `https://` などの URL を書いた。
- `../` でプロジェクトの外のファイルを指したか、外を指すシンボリックリンクを指した。

### 直し方

ファイルをプロジェクトの中に置き、プロジェクトのルートからの相対パスで書く。
章と `@import` のパスの同じ誤りは [G0303](#g0303) である。

## G0261

未定義の関数です

- 重大度: エラー
- 状態: 使用中

### 意味

式の中で、組み込みにない名前の関数を呼んだ。

- メッセージ: `未定義の関数 <関数> です`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.Expr`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- 関数名の綴りを誤った。
- 組み込みにない関数を使おうとした。

### 直し方

関数名の綴りを確かめる。
使える関数は `sqrt`、`floor`、`ceil`、`round`、`fixed`、`abs`、`min`、`max`、`len`、`div`、`join` である。
`@set` で関数は定義できない。

## G0262

ファイルの中の定義がスタイルを上書きしています

- 重大度: お知らせ
- 状態: 使用中

### 意味

ファイルの先頭の `@style-def character` か `@style-def paragraph` が、`style.toml` か組み込みのスタイルと同じ名前のスタイルを定義した。
ファイルの中の上書きは仕様どおりの使い方だが、`style.toml` を読んでも見えない体裁の差を作るので知らせる。
上書きでない新しい名前の定義には出ない。
一つの `@style-def` に一つ出し、位置は `@style-def` の行である。

- メッセージ: `ファイルの中の定義が<種類>の <名前> を上書きしています`（種類は文字スタイルか段落スタイル）
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.Settings`）
- ADR: [golem-syntax ADR 0002](golem-syntax/adr/0002-notice-severity.md)、[docs/adr/0014](adr/0014-in-file-settings.md)

### 主な原因

- その章だけ字下げや書体を変えるために、`body` などのスタイルを上書きした。
- 新しいスタイルを定義するつもりで、既存のスタイルと同じ名前を付けた。

### 直し方

意図した上書きなら、直す必要はない。
`manifest.toml` の `[diagnostics]` の `silence-notices` に `"G0262"` を加えると、このお知らせを出さなくなる。
新しいスタイルのつもりだったなら、ほかの名前を付け、`based-on` で元のスタイルを継ぐ。

```
@style-def paragraph letter based-on=body indent=1zw
```

## G0263

数の縦中横は number-text でも書けます

- 重大度: お知らせ
- 状態: 使用中

### 意味

`[tcy: ...]` の中身が ASCII の数字だけからなる。
縦組みの PDF では、`[tcy: 10]` と `[number-text 10 style=tcy]` は同じ見た目になる。
後者は数として扱われるので、書字方向に合わせて表記が決まり、プレーンテキストの縦書きと横書きでもそれぞれの表記で出る。
数字以外を含む中身（`!?` など）には出ない。
位置は `[tcy ...]` の全体である。

- メッセージ: `数の縦中横は [number-text <数> style=tcy] でも書けます`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-syntax ADR 0002](golem-syntax/adr/0002-notice-severity.md)

### 主な原因

- 日付や数量の数字を、縦中横の `[tcy: ...]` で書いた。

### 直し方

数なら `[number-text ...]` で書く。

```
[tcy: 10]月
```

は次のように書き換えられる。

```
[number-text 10 style=tcy]月
```

数でなく記号として扱いたい場合は、そのままでよい。
`silence-notices` に `"G0263"` を加えると、このお知らせを出さなくなる。

## G0264

行頭のエスケープした空白は無視されます

- 重大度: お知らせ
- 状態: 使用中

### 意味

`line-breaks = "keep"` の段落スタイル（`verse` など）の段落で、行頭にエスケープした空白（`\ `）を書いた。
`keep` の段落は、行頭の空白とタブを、エスケープしたものも含めて無視する。
書き手は字下げのつもりで書くことが多く、黙って無視されると意図が落ちるので知らせる。
位置はエスケープの `\` である。

- メッセージ: `行頭のエスケープした空白は無視されます。字下げには全角の空白を使います`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-syntax ADR 0002](golem-syntax/adr/0002-notice-severity.md)、[docs/adr/0005](adr/0005-character-and-paragraph-styles.md)

### 主な原因

- 詩の行を字下げするつもりで、行頭に `\ ` を書いた。

### 直し方

字下げには全角の空白（`　`）を使う。
全角の空白は文字として残る。
字下げが要らないなら、`\` と空白を消す。

## G0265

@listing の src= は廃止予定です

- 重大度: お知らせ
- 状態: 使用中

### 意味

`@listing` のファイルのパスを `src=` で書いた。
`@listing` だけが、パスを最初の引数と `src=` の両方で受け付けている。
最初の引数を正とし、`src=` は廃止する予定である。
今は `src=` でも同じ内容を取り込む。
位置は `src=` の引数である。

- メッセージ: `@listing の src= は廃止予定です。パスを最初の引数に書きます`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-syntax ADR 0002](golem-syntax/adr/0002-notice-severity.md)

### 主な原因

- 以前の文書の例に合わせて、`src=` でパスを書いた。

### 直し方

パスを最初の引数に書く。
ほかの引数はそのままでよい。

書き換える前：

```
@listing src=src/Main.hs lines=10-20
```

書き換えた後：

```
@listing src/Main.hs lines=10-20
```
## G0266

code はコードブロックの段落スタイルです

- 重大度: エラー
- 状態: 使用中

### 意味

原稿の `@style` に、組み込みの段落スタイル `code` を書いた。
`code` はコードブロックだけを組む段落スタイルであり、段落には付けられない。
段落は本文の段落スタイルで組む。

- メッセージ: `code はコードブロックの段落スタイルです。コードは ``` か @listing で書きます`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-driver ADR 0017](golem-driver/adr/0017-pdf-code-blocks.md)

### 主な原因

- コードを段落として書き、`@style code` で等幅の書体にしようとした。

### 直し方

コードは ```` ``` ```` で囲んだコードブロックか、`@listing` で書く。
本文の中のコードの名前は `[code: ...]` で書く。

## G0267

柱が参照する変数がファイルにありません

- 重大度: エラー
- 状態: 使用中

### 意味

`style.toml` のマスターページの柱の書式の `{set.<名前>}`（`?` なし）が参照する変数が、そのマスターページを使う章のファイルで定義されていない。
`{set.<名前空間>.<名前>}` では、名前空間の `@import` がないか、取り込んだファイルにその変数がない。
柱の `set` の変数は、そのページのファイルの変数であり、`@set` の変数がファイルの単位で定義されるという規則を変えない。
S0 の評価の後に、マニフェストの章のファイルごとに検査する。
PDF をターゲットに含むビルドと `golem check`（四つのターゲットを検査するので、つねに PDF を含む）で出し、HTML、EPUB、プレーンテキストだけのビルドでは出さない。
同じファイルと同じ変数の組には一つだけ出す。
位置はそのファイルの先頭であり、`style.toml` の先頭を関連する位置として添える。

- メッセージ: `柱が参照する変数 <名前> が、このファイルにありません（マスターページ <マスターページの名前>）`
- 段階とモジュール: 評価（golem-driver の `Golem.Driver`）
- ADR: [golem-driver ADR 0022](golem-driver/adr/0022-running-head-formats.md)

### 主な原因

- 柱で使う変数を、一部の章のファイルでだけ `@set` した。
- 変数を共通のファイルに置いたが、章のファイルで `@import` していないか、名前空間の名前が違う。
- 変数の名前の綴りを誤った。

### 直し方

その章のファイルで `@set` するか、変数を置いたファイルを `@import ... as <名前空間>` で取り込み、柱の書式で `{set.<名前空間>.<名前>}` と書く。
変数のない章では柱の行を描かなくてよい場合は、`{set.<名前>?}` と `?` を付ける。

## G0268

柱に出せるのは文字列と数です

- 重大度: エラー
- 状態: 使用中

### 意味

`style.toml` のマスターページの柱の書式が参照する変数の値が、文字列でも数でもない（真偽値、`nil`、配列、連想配列）。
文字列はそのまま、数は式文脈 `[= ...]` で本文に埋め込んだときと同じ文字列にして柱に出す。
S0 の評価の後に、マニフェストの章のファイルごとに検査する。
PDF をターゲットに含むビルドと `golem check`（四つのターゲットを検査するので、つねに PDF を含む）で出す。
位置はそのファイルの先頭であり、`style.toml` の先頭を関連する位置として添える。

- メッセージ: `柱に出せるのは文字列と数です: <名前> は <型>`
- 段階とモジュール: 評価（golem-driver の `Golem.Driver`）
- ADR: [golem-driver ADR 0022](golem-driver/adr/0022-running-head-formats.md)

### 主な原因

- `@set revision = true` のように、真偽値や配列の変数を柱に使った。

### 直し方

柱に出す値を、文字列か数の変数にする。
## G0269

コードブロックの引数か中身が正しくありません

- 重大度: エラー
- 状態: 使用中

### 意味

コードブロックの開始の行か `@listing` に書いた引数か、引数が決める中身の読み方に誤りがある。
コードブロックに書けるキーは `numbers`、`file`、`highlight`、`diff`、`callouts` であり、`@listing` ではこれに `lang` が加わる。
開始の行には、言語の名前のほかに位置引数を書けない。
`highlight` の行番号は、そのコードブロックの行番号の数え方（`numbers` の値か `@listing` の `lines` の最初の行から数え、`diff=true` の削除した行は数えない）で、コードブロックにある番号でなければならない。
`diff=true` のコードの各行は、`+`、`-`、空白のどれかで始まる。
`callouts=true` のコードの行末の注釈の印 `<N>` は、1 から 50 まで（丸数字が Unicode にある範囲）である。
本文のない `@caption` も、この誤りとする。
位置は、引数の誤りでは誤った引数、差分の印と注釈の印の誤りでは誤った行（`@listing` ではそのコマンド）、`@caption` の誤りではその行である。

- メッセージ: `コードブロックに書けないキーです: <キー>。numbers、file、highlight、diff、callouts（@listing では lang も）を書けます`、`コードブロックの開始の行には、言語の名前とキーワード引数だけを書けます`、`<キー> の値が正しくありません: <値>`、`highlight の行 <番号> はこのコードにありません`、`diff=true のコードの行は +、-、空白のどれかで始めます`、`注釈の印の番号は 1 から 50 までです: <番号>`、`@caption には本文を書きます`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-driver ADR 0023](golem-driver/adr/0023-code-block-book-features.md)

### 主な原因

- キーの綴りを誤った。`lang` を ```` ``` ```` の開始の行に書いた（開始の行では、言語の名前を ```` ``` ```` のすぐ後に書く）。
- 言語の名前の後に、キーワードでない語を書いた。
- `numbers` に負の数か数でない語を、`diff` と `callouts` に `true` と `false` のほかの値を書いた。
- `highlight` に、コードの行の外の番号か、削除した行（`-` の行）の番号を書いた。`@listing` の `lines=20-48` のコードの行番号は 20 から始まる。
- `diff=true` のコードに、差分の印のない行を書いた。
- 注釈の印に 0 か 51 以上の番号を書いた。
- `@caption` の後に本文を書かなかった。

### 直し方

メッセージの示すキーと値を直す。
差分のコードの変わらない行は、行頭に空白を一つ置く。
注釈の印が 50 を超えるときは、コードブロックを分ける。
`<数>` で終わるコードを `callouts=true` で書いていないかを確かめる。

## G0270

@need-lines の引数が誤っています

- 重大度: エラー
- 状態: 使用中

### 意味

`@need-lines` の引数が、1 以上の整数の位置引数一つでない。
引数がない場合、二つ以上書いた場合、キーワード引数を書いた場合も、この誤りとする。
誤ったコマンドは捨て、改ページを変えない。
位置はコマンドの行である。
本体も書いていれば、G0297 も出る。

- メッセージ: `@need-lines の引数は 1 以上の整数です`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [docs/adr/0030](adr/0030-manual-page-break-control.md)、[docs/adr/0060](adr/0060-page-break-command-codes-by-cause.md)

### 主な原因

- `@need-lines 0` や `@need-lines 2.5` のように、1 以上の整数でない値を書いた。
- `@need-lines` とだけ書き、行数を書かなかった。

### 直し方

`@need-lines 5` の形で、1 以上の整数を一つだけ書く。

## G0271

改ページの制御は文書の最上位にだけ置けます

- 重大度: エラー
- 状態: 使用中

### 意味

`@no-page-break`、`@need-lines`、`@page-lines` を、リストの項目、定義リストの説明、ブロックコマンドの本体の中に置いた。
三つのコマンドはブロックとブロックのあいだの一点を表すので、文書の最上位にだけ置ける。
その位置のコマンドは捨てる。
フィルタのプラグインが最上位でない位置に置いた場合は、このコードではなく、プラグインの出力の誤りになる。

- メッセージ: `@no-page-break、@need-lines、@page-lines は文書の最上位にだけ置けます`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [docs/adr/0030](adr/0030-manual-page-break-control.md)

### 主な原因

- リストの項目の中に、字下げしてコマンドを書いた。

### 直し方

字下げをやめて、リストの前か後ろに、文書の最上位のブロックとして書く。
本体の形の `@style` の中に書いた場合は、このコードではなく [G0245](#g0245) になる。

## G0272

改ページと改ページの禁止が同じ位置にあります

- 重大度: エラー
- 状態: 使用中

### 意味

`@no-page-break` の直前か直後に、ほかのブロックを挟まずに `@page-break` か `@column-break` を書いた。
間に `@need-lines` か `@page-lines` があっても、同じ位置とみなす。
改めることと改めないことを同じ位置に指定しているので、どちらの意図か分からない。

- メッセージ: `@no-page-break と @page-break が同じ位置にあります`、`@no-page-break と @column-break が同じ位置にあります`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [docs/adr/0030](adr/0030-manual-page-break-control.md)

### 主な原因

- 改ページを入れた位置に、改ページを止める指定も書いた。

### 直し方

どちらか一方を消す。

## G0273

web の代替画像の形式が使えません

- 重大度: エラー
- 状態: 使用中

### 意味

`@figure` の `web` に、PNG、JPEG、SVG のほかの形式のファイルを書いた。
形式は拡張子で決める（`.png`、`.jpg`、`.jpeg`、`.svg` を、大文字と小文字を区別せずに受け付ける）。
どの出力を組むときも同じ規則で調べるので、HTML だけを組むときにも出る。
位置は、その `@figure` のブロックである。

- メッセージ: `web の代替画像は PNG、JPEG、SVG です: <パス>`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-pdf ADR 0008](golem-pdf/adr/0008-pdf-figures.md)、[golem-pdf ADR 0009](golem-pdf/adr/0009-svg-figures.md)

### 主な原因

- `web` に PDF のファイルを書いた。

### 直し方

`web` の画像を PNG、JPEG、SVG のどれかに書き出し、そのファイルを指す。

## G0274

図版の形式が使えません

- 重大度: エラー
- 状態: 使用中

### 意味

`@figure` の画像に、PDF、PNG、JPEG、SVG のほかの形式のファイルを書いた。
形式は拡張子で決める（`.pdf`、`.png`、`.jpg`、`.jpeg`、`.svg` を、大文字と小文字を区別せずに受け付ける）。
中身は見ないので、拡張子と中身が食い違うファイルは、PDF を組むときに [G0810](#g0810) になる。
位置は、その `@figure` のブロックである。

- メッセージ: `図版の形式は PDF、PNG、JPEG、SVG です: <パス>`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-pdf ADR 0008](golem-pdf/adr/0008-pdf-figures.md)、[golem-pdf ADR 0009](golem-pdf/adr/0009-svg-figures.md)

### 主な原因

- GIF や TIFF などの画像を `@figure` に書いた。
- 拡張子のないファイルを書いた。

### 直し方

図を PDF、PNG、JPEG、SVG のどれかに書き出し、そのファイルを指す。

## G0275

page の値が正しくありません

- 重大度: エラー
- 状態: 使用中

### 意味

`@figure` の `page` に、1 以上の整数でない値を書いたか、PDF でない図版に `page` を書いた。
`page` は、PDF の図版の何ページ目を置くかを 1 から数えた整数で表す。
ページの数を超える値は、評価の段階ではファイルを読まないので、PDF を組むときに [G0810](#g0810) になる。
位置は、その `@figure` のブロックである。

- メッセージ: `page は PDF の図版のページを 1 から数えた整数で書きます: <値>`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-pdf ADR 0008](golem-pdf/adr/0008-pdf-figures.md)

### 主な原因

- `page=0` や `page=x` と書いた。
- PNG、JPEG、SVG の図版に `page` を書いた。

### 直し方

PDF の図版なら、`page` を 1 以上の整数にする。
PNG、JPEG、SVG の図版からは、`page` を消す。

## G0276

@printings は日本語の本でだけ使えます

- 重大度: エラー
- 状態: 使用中

### 意味

`@printings` を、日本語でない本（`[metadata] language` が `ja` でない本）に書いた。
`@printings` は何も組まない。
位置は `@printings` の行である。
`@printings` のほかの誤り（引数の G0296、本体の G0297、`[[metadata.printings]]` の欠けの G0298）も当たれば、それらと一緒に出る。

- メッセージ: `@printings は日本語の本（language = "ja"）でだけ使えます`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [docs/adr/0033](adr/0033-colophon-contributors-and-printings.md)、[docs/adr/0056](adr/0056-printings-diagnostic-codes-by-cause.md)

### 主な原因

- `[metadata] language` が `ja` でない本に `@printings` を書いた。発行の履歴の書式は、今は日本語の一つだけである。

### 直し方

日本語の本なら、`[metadata] language` を `ja` にする。
日本語でない本では、`@printings` を消し、`meta.printing` の値から発行の履歴を一行ずつ書く。

## G0277

同じキーを二度書いています

- 重大度: エラー
- 状態: 使用中

### 意味

コマンドのキーワード引数の並びで、同じキーが二度以上出た。
二度めから後の引数はどれも捨て、最初に書いたものだけを使う。
検査は、インラインのコマンド（組み込みとプラグイン）、ブロックコマンド、コードブロックの開始の行と `@listing` に当てる。
`@manifest` と `@style-def` は設定であり、同じキーを G0252 にする。
位置は、二度めから後のそれぞれの引数の全体である。
`**[式]` を展開したキーがほかのキーワード引数と重なるときもこの誤りとする予定だが、今の評価は `**[式]` を展開しないので、この場合はまだ出ない。

- メッセージ: `同じキーを二度書いています: <キー>`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-parser ADR 0013](golem-parser/adr/0013-splat-after-keyword-arguments.md)

### 主な原因

- `[number-text 10 style=kanji style=tcy]` のように、同じキーを二度書いた。

### 直し方

どちらか片方を消す。

## G0278

`##` と `##` のあいだには算用数字だけを書きます

- 重大度: エラー
- 状態: 使用中

### 意味

コードの外の数の糖衣構文 `##…##` の中身が、`0` か、`1` から `9` で始まる ASCII の数字の並びでないか、閉じの `##` がない。
糖衣構文の開きは `##` の直後に ASCII の数字が続くものなので、`##1.5##` や `##12年` は糖衣構文として読まれ、中身の誤りになる。
`[code: ...]` と `[style code: ...]` の散文スロットの中は書いたとおりの地の文になり、この誤りにならない。
位置は糖衣構文の全体（開きの `##` から、閉じの `##` か中身の終わりまで）である。

- メッセージ: `## と ## のあいだには算用数字だけを書きます。本文の ## は \## と書きます`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-parser ADR 0011](golem-parser/adr/0011-number-shorthand.md)

### 主な原因

- 算用数字の後に全角の数字を続けた（`##1２##`）。
- 小数点（`##1.5##`）か桁区切り（`##1,000##`）を書いた。
- 先頭に 0 を付けた（`##007##`）。
- 閉じの `##` を書き忘れた（`##12年`）。

### 直し方

中身を算用数字に直す。
小数や先頭の 0 を書きたいときは、`[number-text ...]` を使うか、地の文で書く。
本文に `##` と数字を続けて書きたいときは、`\##` とエスケープする。

## G0279

行末のエスケープした空白は無視されます

- 重大度: お知らせ
- 状態: 使用中

### 意味

`line-breaks = "keep"` の段落スタイル（`verse` など）の段落で、行末の空白とタブの並びに、エスケープした空白かタブ（`\ `）がある。
`keep` の段落は、行末の空白とタブを、エスケープしたものも含めて無視する。
書き手が残したつもりの空白が残らないので知らせる。
一行に一つだけ出し、位置はその並びの中の最初のエスケープの `\` である。
行の途中のエスケープした空白（`a\ b`）は空白として残り、このお知らせは出ない。

- メッセージ: `行末のエスケープした空白は無視されます`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-parser ADR 0012](golem-parser/adr/0012-keep-trailing-escaped-space.md)

### 主な原因

- `verse` の段落の行末に空白を残すつもりで、`\ ` を書いた。

### 直し方

`\ ` を消す。
見える空きが要るなら、全角の空白（`　`）を使う。

## G0280

@table の format の値が正しくありません

- 重大度: エラー
- 状態: 使用中

### 意味

`@table` の `format` の値が `csv` でも `tsv` でもない。
表は作らない。
位置は `format` の引数の全体である。

- メッセージ: `format は csv か tsv です: <値>`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0004](golem-eval/adr/0004-tsv-tables.md)

### 主な原因

- `format=xlsx` のように、ほかの形式の名前を書いた。
- `format=TSV` のように、大文字で書いた。

### 直し方

`format=csv` か `format=tsv` と書く。
拡張子が `.tsv` のファイルは TSV、それ以外は CSV として読むので、拡張子どおりの形式なら `format` を省ける。

## G0281

@table の align の値が正しくありません

- 重大度: エラー
- 状態: 使用中

### 意味

`@table` の `align` の値が、`left`、`center`、`right`、`default` のどれでもないか、値の数が表の列の数と違う。
表は作らない。
位置は `align` の引数の全体である。
値の数の検査は、表のファイルを読んで見出しの行を得た後に行う。

- メッセージ: `align の値は left、center、right、default のどれかです: <値>`、`align の値の数が表の列の数と違います（列は <m>、align は <n>）`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0004](golem-eval/adr/0004-tsv-tables.md)

### 主な原因

- `align=left,,right` のように、空の値を書いた。
- `align=Left` や `align=middle` のように、ほかの名前を書いた。
- 表に列を足したが、`align` に値を足していない。
- `align=[= ...]` のように、式で書いた。

### 直し方

列の揃えを `left`、`center`、`right`、`default` で、左の列から順にカンマで区切って書く。
すべての列を同じ揃えにするなら、値を一つだけ書く（`align=right`）。

## G0282

表のファイルに単独の CR があります

- 重大度: エラー
- 状態: 使用中

### 意味

`@table` の表のファイル（CSV と TSV）に、LF の前にない CR（単独の CR）がある。
CRLF は誤りにしない。
表は作らない。
位置は表のファイルの最初の単独の CR である。
同じファイルを複数の `@table` から参照しても、一度だけ出す。

- メッセージ: `単独の CR があります。表のファイルの改行は LF か CRLF に限ります`
- 段階とモジュール: 読み込み（golem-driver の `Golem.Driver`、golem-parser の `Golem.Parser.Read`）
- ADR: [golem-eval ADR 0004](golem-eval/adr/0004-tsv-tables.md)

### 主な原因

- 古い Mac の改行（CR だけ）でファイルを書き出した。
- セルの中に CR が紛れ込んだ。

### 直し方

表のファイルの改行を LF か CRLF にして保存し直す。

## G0283

CSV の引用符が閉じていません

- 重大度: エラー
- 状態: 使用中

### 意味

`@table` の CSV のファイルで、`"` で始めたセルの引用符を閉じずにファイルが終わる。
表は作らない。
位置は開いた引用符である。

- メッセージ: `CSV の引用符が閉じていません`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0004](golem-eval/adr/0004-tsv-tables.md)

### 主な原因

- セルの中の `"` を `""` と二つ重ねていない。
- 書き出しの途中でファイルが切れた。

### 直し方

引用符を閉じる。
セルの中の `"` は `""` と書く。

## G0284

@table の cells の値が正しくありません

- 重大度: エラー
- 状態: 使用中

### 意味

`@table` の `cells` が `text` でない。
`cells=markup` は将来セルをインラインの記法として読むために予約した値であり、まだ実装していない。
表は作らない。
位置は `cells` の引数の全体である。

- メッセージ: `cells=markup はまだ実装していません`、`cells は text です: <値>`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0004](golem-eval/adr/0004-tsv-tables.md)

### 主な原因

- セルの中の記法を解釈させようとして `cells=markup` を書いた。
- `cells` をほかの意味で書いた。

### 直し方

`cells` を消すか、`cells=text` と書く。
セルの中身は地の文として扱われる。

## G0285

表のファイルが表になりません

- 重大度: エラー
- 状態: 使用中

### 意味

`@table` の表のファイル（CSV と TSV）が空か、行のセルの数が見出しの行と違う。
表は作らない。
空のときの位置は表のファイルのバイト 0 から 0、セルの数の違うときの位置は最初のその行（行頭から行の終わりの前まで。CSV では引用符の中の改行をまたぐレコードの全体）である。
空とは、最後の行の終わりを捨てた後（CSV では空の行を除いた後）に行が一つもないことである。

- メッセージ: `CSV が空です`、`TSV が空です`、`CSV の行のセルの数が見出しの行と違います（見出しの行は <m>、この行は <n>）`、`TSV の行のセルの数が見出しの行と違います（見出しの行は <m>、この行は <n>）`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0004](golem-eval/adr/0004-tsv-tables.md)

### 主な原因

- 表のファイルが空である。
- 行によって列の数が違う。
- TSV の途中に空の行がある（TSV の空の行は、一つの空のセルを持つ行になる）。
- CSV のセルの中のカンマを `"` で囲んでいない。

### 直し方

各行のセルの数を見出しの行にそろえる。
TSV の途中の空の行は消す。

## G0286

整数が大きすぎます

- 重大度: エラー
- 状態: 使用中

### 意味

式の整数の演算の結果の絶対値が 2 の 4096 乗以上になった。
または、`round` か `fixed` の小数の桁数に 1000 を超える数を書いた。
上限を超える値を作る前に止めるので、大きな冪や桁数で評価が終わらなくなることはない。
浮動小数点数の底か負の指数の `**` の計算が大きすぎる場合は、このコードではなく G0295 になる。

- メッセージ: `整数が大きすぎます（絶対値は 2 の 4096 乗未満に限ります）`、`小数の桁数が多すぎます（1000 桁までです）`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.Expr`）
- ADR: [docs/adr/0035](adr/0035-security-hardening.md)、[golem-eval ADR 0005](golem-eval/adr/0005-float-overflow.md)、[golem-eval ADR 0006](golem-eval/adr/0006-exact-power-limit-before-range.md)

### 主な原因

- `10 ** 100000` のような、大きな冪を書いた。
- `round` か `fixed` の二つめの引数に、大きな桁数を書いた。

### 直し方

式を直し、値を上限の内に収める。

## G0287

@figure の rotate の誤りです

- 重大度: エラー
- 状態: 使用中

### 意味

`@figure` の `rotate` の値が `true` でも `false` でもない。
または、`rotate=true` と `wrap` を両方書いた。
回して置く図版は一ページを占め、脇に本文を置かないので、回り込ませられない。
位置は `@figure` のブロックである。

- メッセージ: `rotate は true か false です: <値>`、`回して置く図版は回り込ませられません`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-driver ADR 0034](golem-driver/adr/0034-fit-figures-to-column.md)

### 主な原因

- `rotate=yes` のように、`true` と `false` 以外の値を書いた。
- 回り込ませていた図版に `rotate=true` を足した。

### 直し方

`rotate` には `true` か `false` を書く。
回して置く図版からは `wrap` と `width` を消す。

## G0288

表のファイルが上限を超えます

- 重大度: エラー
- 状態: 使用中

### 意味

`@table` の表のファイル（CSV と TSV）が上限を超えた。
上限は三つあり、ファイルの大きさが 16 MiB（16,777,216 バイト）以下、行の数が見出しの行を含めて 10,000 以下、1 行のセルの数が 256 以下である。
大きさはファイルを読む前に調べ、超えていればファイルの中身を読まない。
行の数とセルの数は読みながら数え、超えた時点で読むのを止める。
行の数は表の行の数であり、CSV では捨てる空の行を数えない。
表は作らない。
dev でも prod でもエラーであり、LSP も同じく出す。
位置は `@table` のブロックである。

- メッセージ: `表のファイルが大きさの上限を超えます: <パス>（<n> バイト、上限は 16777216 バイト）`、`表のファイルが行の数の上限を超えます: <パス>（<r> 行目、上限は 10000 行）`、`表のファイルがセルの数の上限を超えます: <パス>（<r> 行目、上限は 1 行に 256 個）`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）。大きさは golem-driver の `Golem.Driver` がファイルを読む前に調べる
- ADR: [docs/adr/0043](adr/0043-table-file-size-limits.md)

### 主な原因

- データの一覧をそのまま表にしようとした。
- 区切りの文字を間違え、1 行のセルの数が増えた。
- 表のファイルではないファイルを `src` に書いた。

### 直し方

表を分け、一つのファイルを上限の内に収める。
上限は設定では変えられない。

## G0289

出力に書けない文字があります

- 重大度: エラー
- 状態: 使用中

### 意味

原稿の本文、見出し、表のファイルのセル、`@listing` のファイル、`@import` で取り込んだ値などの文字列に、出力に書けない文字がある。
出力に書けない文字とは、XML 1.0 の `Char` に当たらない文字であり、U+0000 から U+001F のうちタブ、改行、復帰以外と、U+FFFE、U+FFFF、サロゲートの符号位置である。
U+007F と C1 制御文字（U+0080 から U+009F）は含めない。
出力の側で別の文字に置き換えると入力と出力が黙って食い違うので、評価の段階で拒む。
ターゲットを問わず、プレーンテキストと PDF でも出す。
一つの文字列に複数あれば最初の一つを述べ、文字列ごとに一つ出す。
位置は、その文字を含む文字列である。
表のセルとコードブロックの文字列は、`@table` と `@listing` のブロックの位置を指し、コードブロックの行はまとめて一つの文字列として数える。
dev と prod の両方でエラーであり、LSP も同じく出す。

- メッセージ: `出力に書けない文字（U+0001）があります`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [docs/adr/0042](adr/0042-control-characters-and-glob-metacharacters.md)

### 主な原因

- ほかのアプリケーションから貼り付けた文章に、制御文字が混ざっている。
- 表のファイルや `@listing` のファイルに、制御文字が含まれている。

### 直し方

メッセージの符号位置の文字を消す。
エディタによっては制御文字が見えないので、符号位置で検索する。

## G0290

宣言されていないチャネルです

- 重大度: エラー
- 状態: 使用中

### 意味

`@channel` の名前を、読み込んだプラグインのどれも宣言していない。
または、`@channel` にチャネルの名前を一つだけ書いていない。
一覧は出さない。
位置は `@channel` のブロックコマンドである。
プラグインの読み込みか検査が誤りを出したときは報告しない。

- メッセージ: `宣言されていないチャネルです: <チャネル>`、`@channel にはチャネルの名前を一つ書きます`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-doc ADR 0007](golem-doc/adr/0007-plugin-channel-lists.md)

### 主な原因

- チャネルの名前を書き誤った。
- チャネルを宣言するプラグインを `manifest.toml` に書いていない。

### 直し方

プラグインが宣言するチャネルの名前を一つ書く。
プラグインを `manifest.toml` の `[plugins]` に書く。

## G0291

整数が意味論 IR に書ける範囲を超えています

- 重大度: エラー
- 状態: 使用中

### 意味

意味論 IR の整数の欄に、-2 の 63 乗以上、2 の 63 乗未満の範囲の外の整数を入れようとした。
IR の整数の欄は 64 ビットの符号付き整数に限るので、その要素を IR に入れない。
重大度はプロファイルによって変わらない。
位置と、出したあとの扱いは欄ごとに次のとおりである。

- `[number-text ...]` の数：位置はコマンドで、何も出さない。
- `@number N`：位置は `@number` の行で、`@number` がないものとして番号を振る。
- コードブロックの行番号（`numbers=N`）：位置はブロックで、`numbers` を書かなかったものとして番号を振る。最初の番号に行の数を足して範囲の外になる場合も含む。
- `[aki ...]` の量：位置はコマンドで、何も出さない。
- `doc` を使う `[= ...]`：位置は `[= ...]` で、何も出さない。変数を置き換えた後の式に、範囲の外の整数が一つでもあれば出る。
- プラグインのコマンドの引数：位置はコマンドで、プラグインを呼ばない。

`doc` を使わない `[= ...]` の値は本文の文字列になるので、この範囲とは関係しない。

- メッセージ: `整数が意味論 IR に書ける範囲を超えています（-2 の 63 乗以上、2 の 63 乗未満に限ります）`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-doc ADR 0006](golem-doc/adr/0006-integer-range-in-ir.md)

### 主な原因

- `[number-text [= 2 ** 70]]` のように、大きな値を数として渡した。
- `@number` に 2 の 63 乗以上の番号を書いた。
- `@set` で大きな値を作り、`doc` と組み合わせた式で使った。

### 直し方

値を範囲の内に収める。
数として扱う必要がなければ、`[= ...]` で本文の文字列として埋め込む。

## G0292

`@blank-line` の引数か本体が誤っています

- 重大度: エラー
- 状態: 使用中

### 意味

`@blank-line` の引数か本体が、決まった形でない。
`@blank-line` は、引数を取らないか、1 以上の整数の位置引数を一つだけ取る。
整数は数字だけの語で書き、符号、小数点、キーワード引数は使えない。
本体は持たない。
そのコマンドは捨て、行アキを入れない。
2 の 63 乗以上の整数は [G0291](#g0291) である。

- メッセージ: `@blank-line の引数は 1 以上の整数を一つだけ書きます`、`@blank-line は本体を持てません`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [docs/adr/0046](adr/0046-blank-line-command.md)

### 主な原因

- `@blank-line 0` や `@blank-line 1.5` のように、1 以上の整数でない値を書いた。
- `@blank-line lines=2` のように、キーワード引数で書いた。
- コマンドの次の行を字下げして、本体を書いた。

### 直し方

`@blank-line` か `@blank-line 2` の形で書く。

## G0293

`@blank-line` は文書の最上位にだけ置けます

- 重大度: エラー
- 状態: 使用中

### 意味

`@blank-line` を、リストの項目、定義リストの説明、ブロックコマンドの本体（`@figure` のキャプションなど）の中に置いた。
行アキは文書の最上位のブロックのあいだにだけ入れられる。
そのコマンドは捨てる。
本体の形の `@style` の中に置いた場合は、ほかのブロックと同じく [G0245](#g0245) である。

- メッセージ: `@blank-line は文書の最上位にだけ置けます`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [docs/adr/0046](adr/0046-blank-line-command.md)

### 主な原因

- リストの項目のあいだを空けるつもりで、項目の中に `@blank-line` を書いた。

### 直し方

`@blank-line` を、字下げせずに文書の最上位に書く。
リストの項目のあいだは、行アキでは空けられない。

## G0294

続けて書いた `@blank-line` はまとめて書けます

- 重大度: お知らせ
- 状態: 使用中

### 意味

`@blank-line` を、ほかのブロックを挟まずに続けて書いた。
間に `@need-lines`、`@page-lines`、`@no-page-break` しかない場合も、続けて書いたものとみなす。
行アキの量は足し合わせるので、組んだ結果は一つにまとめた場合と変わらない。
判定はファイルごとに行い、ファイルの境界をまたぐものは数えない。
位置は、二つ目以降の `@blank-line` の行である。
お知らせなので、エラーにも警告にもならず、ビルドの成否に影響しない（[golem-syntax ADR 0002](golem-syntax/adr/0002-notice-severity.md)）。

- メッセージ: `続けて書いた @blank-line は @blank-line <N> にまとめて書けます`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [docs/adr/0046](adr/0046-blank-line-command.md)

### 主な原因

- 二行の行アキのつもりで、`@blank-line` を二行書いた。

### 直し方

`@blank-line 2` のように、足し合わせた行数を一つの `@blank-line` に書く。
`manifest.toml` の `[diagnostics]` の `silence-notices` に `"G0294"` を加えると、このお知らせを出さなくなる。

## G0295

累乗の正確な計算に要るビットの数が上限を超えます

- 重大度: エラー
- 状態: 使用中

### 意味

浮動小数点数の底か、整数の底と負の指数の `**` の正確な計算に要るビットの数が、上限を超える。
底の絶対値を `m × 2^f`（`m` は正の奇数、`f` は整数）と分けたとき、`(m のビットの数 - 1) × |指数|` が 2^20（1048576）を超える場合である。
この判定は、結果が倍精度の範囲の内か外かより先に、整数の演算だけで行う。
このため、結果が範囲の外にある式（`1.5 ** 100000000`）も、範囲の内にある式も、上限を超えればこのエラーになる。
上限は計算の量の上限であり、結果の値の大きさによらない。
たとえば `1.0000000000000002 ** 30000` の底は 1 + 2^-52 で、`m` が 53 ビットなので `52 × 30000 = 1560000` が上限を超え、このエラーになる。
結果はおよそ 1 + 6.7 × 10^-12 であり、倍精度で普通に表せる値である。
どの式がこのエラーになるかは、底と指数だけで決まる。
位置は `**` の式の全体である。

- メッセージ: `累乗の正確な計算に要るビットの数 <n> が、上限の 1048576（2 の 20 乗）を超えます（結果の大きさによらない上限です）`。`<n>` は `(m のビットの数 - 1) × |指数|` の値である。
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.Expr`）
- ADR: [golem-eval ADR 0005](golem-eval/adr/0005-float-overflow.md)、[golem-eval ADR 0006](golem-eval/adr/0006-exact-power-limit-before-range.md)、[golem-eval ADR 0007](golem-eval/adr/0007-power-limit-message.md)

### 主な原因

- `1.0000001 ** 100000` のように、1 に近い数を何万回も掛ける累乗を書いた。
- `1.5 ** 100000000` のように、大きな指数を書いた。

### 直し方

指数を小さくするか、底を変える。
底が 2 の累乗（`2.0` や `0.5`）なら `m` が 1 なので、指数がいくつでもこのエラーにならない。
`m` が短いのは、`1.5` や `1.25` のように分母が 2 の累乗の小数だけである。
`1.1` や `1.0000001` のような十進の小数の底は、倍精度の値の `m` がおよそ 53 ビットになるので、指数の絶対値の上限はおよそ 20000 である。
十進の桁を減らしても `m` のビットの数は減らないので、底の桁を減らしてもこのエラーは消えない。

## G0296

引数を取らないコマンドに引数を書きました

- 重大度: エラー
- 状態: 使用中

### 意味

引数を取らないブロックコマンドに、引数を書いた。
位置引数、キーワード引数、展開した引数のどれでも、この誤りになる。
コマンドは何も組まない。
位置はコマンドの行である。
対象は `@column-break`、`@no-page-break`、`@printings` である。

- メッセージ: `<名前> は引数を取りません`。`<名前>` は `@` を付けたコマンドの名前である。
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [docs/adr/0056](adr/0056-printings-diagnostic-codes-by-cause.md)、[docs/adr/0060](adr/0060-page-break-command-codes-by-cause.md)

### 主な原因

- `@column-break recto` や `@printings 1` のように、引数を取らないコマンドの後に値を書いた。

### 直し方

コマンドの行から引数を消す。

## G0297

本体を持てないコマンドに本体を書きました

- 重大度: エラー
- 状態: 使用中

### 意味

本体を持てないブロックコマンドの次の行を字下げし、本体を書いた。
コマンドは何も組まない。
位置は本体の最初のブロックである。
対象は `@page-break`、`@column-break`、`@no-page-break`、`@need-lines`、`@page-lines`、`@printings` である。
引数も誤っていれば、引数の誤りのコードの後に出る。

- メッセージ: `<名前> は本体を持てません`。`<名前>` は `@` を付けたコマンドの名前である。
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [docs/adr/0056](adr/0056-printings-diagnostic-codes-by-cause.md)、[docs/adr/0060](adr/0060-page-break-command-codes-by-cause.md)

### 主な原因

- コマンドの次の行を、続きのつもりで字下げした。

### 直し方

コマンドの次の行の字下げをやめ、別の段落として書く。
本体のつもりで書いた行が要らなければ消す。

## G0298

マニフェストに [[metadata.printings]] がありません

- 重大度: エラー
- 状態: 使用中

### 意味

`@printings` を、`manifest.toml` に `[[metadata.printings]]` のない本に書いた。
`@printings` は何も組まない。
位置は `@printings` の行である。

- メッセージ: `マニフェストに [[metadata.printings]] がありません`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [docs/adr/0033](adr/0033-colophon-contributors-and-printings.md)、[docs/adr/0056](adr/0056-printings-diagnostic-codes-by-cause.md)

### 主な原因

- `manifest.toml` に `[[metadata.printings]]` を書いていない。

### 直し方

`manifest.toml` に `[[metadata.printings]]` を足し、版、刷、日付を書く。
発行の履歴を組まないなら、`@printings` を消す。

## G0299

@page-lines の引数が誤っています

- 重大度: エラー
- 状態: 使用中

### 意味

`@page-lines` の引数が、`+` か `-` の符号を付けた 0 でない整数の位置引数一つでない。
引数がない場合、二つ以上書いた場合、キーワード引数を書いた場合も、この誤りとする。
誤ったコマンドは捨て、ページの行数を変えない。
位置はコマンドの行である。
本体も書いていれば、G0297 も出る。

- メッセージ: `@page-lines の引数は +1 や -1 のように符号を付けた 0 でない整数です`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [docs/adr/0030](adr/0030-manual-page-break-control.md)、[docs/adr/0060](adr/0060-page-break-command-codes-by-cause.md)

### 主な原因

- `@page-lines 1` のように、符号を付けずに書いた。
- `@page-lines +0` のように、0 を書いた。

### 直し方

`@page-lines +1` か `@page-lines -1` の形で、符号を付けた 0 でない整数を一つだけ書く。

## G0301

manifest.toml の誤りです

- 重大度: エラー
- 状態: 使用中

### 意味

`manifest.toml` が TOML として読めないか、スキーマに合わないか、出力ターゲットが一つもない。
`[source]` と章の項目の `[source]` のキー（`paragraph-separator` など）の未知のキーと不正な値、同じファイルを章の配列に二度並べて適用される `[source]` の値が異なる場合も、この誤りとする。
`[metadata]` の `creators` と `contributors` の `role` が役割の表の語でない場合、`name` が空の文字列の場合、`publisher-person` が空の文字列か改行を含む場合、`printings` の版か刷が 1 より小さい場合、`printings` が版と刷の順に狭義に増えていない場合、`printings` の `date` が前の項目より前の場合も、この誤りとする。

- メッセージ: `TOML の誤りです: <詳細>`、`@style-def の値が不正です: <詳細>`、`出力ターゲットが一つもありません`、`同じファイルを [source] の設定を変えて章に二度並べています: <パス>`、`章は、ファイルのパス、表、配列のどれかで書きます`、`役割は語で書きます。"<符号>" は "<語>" です`、`役割は <語の一覧> のどれかです: <値>`、`発行所は [metadata] の publisher に、発行人は publisher-person に書きます`、`name に空の文字列は書けません`、`publisher-person に空の文字列は書けません`、`publisher-person に改行は書けません`、`版と刷の番号は 1 以上の整数です`、`printings は版と刷の順に、同じ版と刷を二度書かずに並べます`、`printings の date が前の項目の date より前です`、または TOML のスキーマの誤りの文言（`知らないキーです: <経路>.<キー>`、`必須のキーがありません: <経路>.<キー>`、`<経路> には<型>を書きます（<型>が書かれています）`、`[source]` の不正な値など）。TOML の誤りの詳細は、`文字列が閉じていません`、`閉じた表にキーを足しています: <キー>` などの日本語の文言である。経路は `metadata.title` や `chapters[0]` の形で書く。Golem の検査の文言には、`(chapters[0])` のように経路を後ろに添える。経路が空のとき（ファイルの最上位の誤り）は添えない。
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project.Manifest`）。位置は、スキーマの誤りと Golem が値の読み込みで調べる誤り（章の項目、`[source]` の値など）では誤った値の位置、TOML の構文の誤りではその誤りの位置、それ以外（出力ターゲットが一つもないなど）では `manifest.toml` の先頭である
- ADR: [golem-project ADR 0006](golem-project/adr/0006-project-diagnostic-codes.md)（定めた）。[golem-cli ADR 0002](golem-cli/adr/0002-build-all-targets-by-default.md) が触れ、[docs/adr/0013](adr/0013-paragraph-separator.md) が `[source]` の誤りの条件を加えた。[golem-project ADR 0007](golem-project/adr/0007-toml-messages-in-japanese.md) が TOML の誤りの文言を日本語にした。[docs/adr/0033](adr/0033-colophon-contributors-and-printings.md) が役割、名前、発行人、刷の検査を加えた。位置は [golem-project ADR 0008](golem-project/adr/0008-style-toml-value-positions.md) が定めた

### 主な原因

- TOML の文法を誤った。
- キーの綴りか値の型を誤った。未知のキーは無視せずエラーにする。
- 出力ターゲット（`[targets.*]`）を一つも書いていない。
- `[source]` の値を誤った。`paragraph-separator` は `"blank-line"` か `"line"` と書く。
- `role` に MARC relator の符号（`aut` など）を書いた。役割は `author` のような語で書く。
- `role = "publisher"` と書いた。発行所は `[metadata]` の `publisher` に、発行人は `publisher-person` に書く。
- `printings` の項目の順を誤ったか、同じ版と刷を二度書いた。

### 直し方

メッセージの示すキーと値を直す。
ターゲットを一つ以上書く。

## G0302

ファイルがありません

- 重大度: エラー
- 状態: 使用中

### 意味

章や `@import` が指すファイルがない。
`golem inspect` と `golem fmt` の引数のファイルがないか、通常のファイルでない（ディレクトリなど）ときも、この誤りとする（[golem-cli ADR 0007](golem-cli/adr/0007-inspect-output.md)）。
このときの位置は引数のファイルの先頭である。
プロジェクトのルートに `manifest.toml` がないときは、この誤りではなく [G0316](#g0316) とする。

- メッセージ: `ファイルがありません: <パス>`
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project`）。位置は、章なら `manifest.toml` の先頭、`@import` ならその `@import` のブロック全体である
- ADR: [golem-project ADR 0006](golem-project/adr/0006-project-diagnostic-codes.md)

### 主な原因

- 章や `@import` のパスの綴りを誤ったか、ファイルを置いていない。
- `golem inspect` か `golem fmt` に渡したパスの綴りを誤った。

### 直し方

パスの綴りとファイルの置き場所を確かめる。

## G0303

使えないパスです

- 重大度: エラー
- 状態: 使用中

### 意味

章や `@import` のパスが、絶対パス、URL、またはプロジェクトのルートの外を指すパスである。
シンボリックリンクを解決した実体がルートの外にあるときも、この誤りとする。

- メッセージ: `絶対パスは使えません: <パス>`、`URL は使えません: <パス>`、`プロジェクトルートの外を指しています: <パス>`
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project`）。位置は [G0302](#g0302) と同じである
- ADR: [golem-project ADR 0006](golem-project/adr/0006-project-diagnostic-codes.md)

### 主な原因

- 章や `@import` のパスに、絶対パスか URL を書いた。
- `..` でプロジェクトのルートの外を指した。

### 直し方

プロジェクトのルートからの相対パスで書き、ファイルをプロジェクトの中に置く。

## G0304

大文字と小文字だけが異なるパスです

- 重大度: エラー
- 状態: 使用中

### 意味

大文字と小文字だけが違う二つのパスを使った。
大文字と小文字を区別しないファイルシステムで、結果が変わるためである。
書いたパスで比べるので、どのファイルシステムでも同じ誤りになる。
シンボリックリンクを解決した後のパスも比べる。

- メッセージ: `大文字と小文字だけが異なるパスです: <後のパス> と <先のパス>`
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project`）。位置は、章なら `manifest.toml` の先頭、`@import` ならその `@import` のブロック全体である
- ADR: [golem-project ADR 0006](golem-project/adr/0006-project-diagnostic-codes.md)

### 主な原因

- 同じファイルを、大文字と小文字の違う二つの綴りで指した。

### 直し方

どちらかのパスに綴りをそろえる。

## G0305

import が循環しています

- 重大度: エラー
- 状態: 使用中

### 意味

`@import` が循環している。
自分自身の import も含む。

- メッセージ: `import が循環しています: <ファイル> → <ファイル> → ... → <最初のファイル>`
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project`）。位置は循環の最初のファイルの `@import` で、循環に含まれる各 `@import` を関連位置に載せる
- ADR: [golem-project ADR 0006](golem-project/adr/0006-project-diagnostic-codes.md)

### 主な原因

- `@import` が循環している。自分自身の import も含む。

### 直し方

共通の定義を別のファイルに切り出し、循環を断つ。

## G0306

style.toml の誤りです

- 重大度: エラー
- 状態: 使用中

### 意味

`style.toml` が TOML として読めないか、スキーマに合わないか、値が範囲の外にある。
フォントのファイルの欠落には使わない（[G0310](#g0310)、[G0802](#g0802)）。
判型（`[page]` の `size`）の誤りには使わない（[G0317](#g0317)）。
マスターページの柱の内容の誤りには使わない（[G0314](#g0314)）。
見出しの `running-head` には使わない（[G0319](#g0319)）。
文字スタイルと段落スタイルの `kerning`、`tracking`、`proportional-metrics`、`baseline-shift` の誤りには使わない（[G0321](#g0321)）。
隠しノンブルの `gutter` と `size` の関係の誤りには使わない（[G0329](#g0329)）。
`@style-def` の名前と欄の誤りにも出る。
誤りのある定義は捨てる。

- メッセージ: `TOML の誤りです: <詳細>`、TOML のスキーマの誤りの文言、または値の検査の文言（`スタイルの名前は英小文字で始まり、英小文字、数字、- だけからなります: <名前>`、`番号の書式が不正です: <書式>`、`塗り足しには zw を使えません`、`<キー> に使えない値です: <値>（<許す値> のどれか）`、`columns が 2 以上のときは column-gap が要ります`、`space-between は 0 以上です`、`長さの書き方が不正です: <値>（13Q や 20mm のように書きます）`、`長さは文字列で書きます`、`cmyk は 0 から 100 までの整数四つです`、`見出しの段は 1、2、3 のどれかです: <段>`、`罫線の <キー> を寸法として読めません: <値>`、`罫線の length は 0 より大きい寸法です`、`罫線の weight には zw を使えません`、`罫線の weight は 0 より大きい寸法です`、`罫線の <キー> は 0 以上の寸法です`、`罫線の style に使えない値です: <値>（<許す値> のどれか）`、`罫線の <キー> には zw を使えません`、`罫線の <キー> は 0 より大きい寸法です`、`罫線の <キー> は style が <線の種類> のときには書けません`、`[notes.rule] には length が要ります`、`[notes] の mark-size は 0 より大きい寸法で、zw では 1 以下です`、`[notes] の mark-format には {n} をちょうど一つ書きます: <書式>`、`lines は 1 以上の整数です: <値>`、`罫線の length と end-indent は一緒に書けません`、`罫線には表か false を書きます。true は書けません`、`[notes.rule] には <キー> を書けません。段落スタイルと見出しの罫線だけのキーです`、`段落スタイル <名前> には rule-before と rule-after を書けません`、`段落スタイル <名前> の罫線の長さが 0 以下です。start-indent と end-indent を狭めてください` など）。廃止した欄（`[emphasis]`、`[verse]`、`[sidenotes]` の `font` と `size`）は、書き換え先を示す文言になる。TOML のスキーマの誤りの文言は、`知らないキーです: page.bindng`、`必須のキーがありません: <経路>.<キー>`、`page.binding には文字列を書きます（整数が書かれています）` のように、文言の中に経路を書く。Golem の検査の文言には、`(page.grid.font-size)` のように経路を後ろに添え、経路が空のときは添えない。TOML の誤りの詳細も、`文字列が閉じていません`、`閉じた表にキーを足しています: page` などの日本語の文言である。
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project.Style`）。位置は、スキーマの誤りと Golem が値の読み込みで調べる誤りでは誤った値の位置、TOML の構文の誤りではその誤りの位置である。二つのキーの組み合わせの誤りは、文言が直すよう求めているキーの値の位置（`columns` と `column-gap` では `columns`）に出す。読み込んだ後の検査では、直すべき値の位置であり、その値が書かれていなければそのスタイルなどの表の見出しの位置、それもなければ `style.toml` の先頭である。ファイルの中の定義（`@style-def`）は評価（golem-eval の `Golem.Eval.Settings`）が同じ検査をし、位置はその `@style-def` の行になる
- ADR: [golem-project ADR 0006](golem-project/adr/0006-project-diagnostic-codes.md)（定めた）。条件を加えた ADR は [golem-project ADR 0004](golem-project/adr/0004-font-file-check-per-target.md)、[docs/adr/0005](adr/0005-character-and-paragraph-styles.md)、[docs/adr/0006](adr/0006-paragraph-indent.md)、[golem-pdf ADR 0004](golem-pdf/adr/0004-crop-marks-and-bleed.md)、[golem-layout ADR 0008](golem-layout/adr/0008-explicit-hyphens.md)、[golem-layout ADR 0009](golem-layout/adr/0009-ruby-placement.md)、[golem-driver ADR 0009](golem-driver/adr/0009-pdf-toc-page-numbers.md)、[golem-driver ADR 0010](golem-driver/adr/0010-caption-style.md)、[golem-driver ADR 0011](golem-driver/adr/0011-sidenote-font.md)、[docs/adr/0014](adr/0014-in-file-settings.md)、[golem-driver ADR 0021](golem-driver/adr/0021-hidden-folios.md)、[golem-driver ADR 0024](golem-driver/adr/0024-rule-spec-and-footnote-separator.md)、[golem-driver ADR 0028](golem-driver/adr/0028-rule-colour-and-style.md)、[golem-driver ADR 0025](golem-driver/adr/0025-note-mark-size-and-format.md)、[golem-driver ADR 0032](golem-driver/adr/0032-default-heading-styles.md) である。[golem-project ADR 0007](golem-project/adr/0007-toml-messages-in-japanese.md) が TOML の誤りの文言を日本語にした。位置は [golem-project ADR 0008](golem-project/adr/0008-style-toml-value-positions.md) が定めた

### 主な原因

- TOML の文法を誤った。
- キーの綴り、値の型、単位、列挙の値を誤った。
- 値が範囲の外にある。
- 廃止した欄（`[emphasis]`、`[verse]`、`[sidenotes]` の `font` と `size`）を書いた。
- 段落スタイル `code` に、`font`、`size`、`background`、`padding` のほかのキー（`based-on` を含む）を書いた（[golem-driver ADR 0017](golem-driver/adr/0017-pdf-code-blocks.md)）。
- `background` か `padding` を、`code` のほかの段落スタイルに書いた。`padding` が負であるか、寸法として読めない。
- `border` か `border-width` を、`code` のほかの段落スタイルに書いた。`border-width` を zw で書いた（[golem-driver ADR 0023](golem-driver/adr/0023-code-block-book-features.md)）。
- 文字スタイルの `background` か `padding` を、`code` と `based-on` で `code` に行き着く文字スタイルのほかに書いた。文字スタイルの `background` に `true` を書いた。文字スタイルの `padding` が負であるか、寸法として読めない（[golem-driver ADR 0029](golem-driver/adr/0029-inline-code-background.md)）。
- `[code]` か `[code.colors]` に未知のキーを書いた。`[code]` の `line-numbers` が真偽値でない。`[code]` の `number` が `{n}` などの差し込みを含まない。
- `[hidden-folio]` の `size` か `gutter` を `zw` で書いたか、0 以下にしたか、寸法として読めない値にした。`pages` に `unnumbered` と `all` のほかの値を書いた（[golem-driver ADR 0021](golem-driver/adr/0021-hidden-folios.md)）。`gutter` が `size` の半分より小さい誤りは [G0329](#g0329) である。
- 罫線の指定（`[notes.rule]`）で、`length` が寸法として読めないか 0 以下、`weight` が寸法として読めないか 0 以下か `zw`、`space-before` か `space-after` が寸法として読めないか負である。未知のキーを書いた。`[notes.rule]` に `length` を書いていない（[golem-driver ADR 0024](golem-driver/adr/0024-rule-spec-and-footnote-separator.md)）。
- 罫線の指定で、`style` に線の種類の表にない値を書いた。`dash` か `gap` が寸法として読めないか、0 以下か、`zw` である。`dash` を `"dashed"` のほかの線の種類に、`gap` を `"dashed"`、`"dotted"`、`"japanese-dots"` のほかの線の種類に書いた。`color` を文字列で書いていない（[golem-driver ADR 0028](golem-driver/adr/0028-rule-colour-and-style.md)）。
- 段落スタイルか `[headings.N]` の `rule-before`、`rule-after` に、表と `false` のほかの値（`true` を含む）を書いた。組み込みの段落スタイル `caption`、`sidenote`、`code` に書いた。`@style-def` に書いた。`length` と `end-indent` を一緒に書いた。`start-indent` と `end-indent` を引くと罫線の長さが 0 以下になる。`[notes.rule]` に `start-indent`、`end-indent`、`keep-in-column` を書いた（[golem-driver ADR 0027](golem-driver/adr/0027-paragraph-style-rules.md)）。

### 直し方

メッセージの示すキーと値を直す。
廃止した欄は、メッセージの示す節に移す。

## G0307

style.toml にないマスターページです

- 重大度: エラー
- 状態: 使用中

### 意味

`manifest.toml` の章の項目の `master` が、`style.toml` にないマスターページを指す。
`style.toml` がないときは、`master` を書いた項目がすべて該当する。
名前ごとに一つだけ出し、順序は章の順で名前が最初に現れた順である。
原稿に構文の誤りがあるときは調べない。

- メッセージ: `style.toml にないマスターページです: <名前>`
- 段階とモジュール: プロジェクト（golem-driver の `Golem.Driver`）。位置は `manifest.toml` の先頭である
- ADR: [golem-project ADR 0006](golem-project/adr/0006-project-diagnostic-codes.md)（定めた）。[golem-driver ADR 0003](golem-driver/adr/0003-pdf-heading-styles.md) が使用済みの番号として触れる

### 主な原因

- `manifest.toml` の章の `master` の綴りを誤った。
- `style.toml` にマスターページを定義していない。

### 直し方

`style.toml` にマスターページを定義するか、名前の綴りを直す。

## G0308

style.toml にないフォントの役割です

- 重大度: エラー
- 状態: 使用中

### 意味

見出し、文字スタイル、段落スタイルの `font` が、`[fonts]` にない役割を指す。
`@style-def` の `font` にも出る。
誤りのある定義は捨てる。
組み込みの段落スタイル `code` と文字スタイル `code` の `font` が既定の役割 `code` を指し、`[fonts.code]` がない場合は、この誤りとせず、本文の役割で組む（[G0808](#g0808)、[golem-driver ADR 0017](golem-driver/adr/0017-pdf-code-blocks.md)）。

- メッセージ: `style.toml にないフォントの役割です: <役割>`
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project.Style`）。`style.toml` の検査の位置は、直すべき値（`font`、`size`、`first-line-indent`、`based-on`、`color`、`kerning` など）の位置であり、その値が書かれていなければそのスタイルなどの表の見出しの位置である。ファイルの中の定義（`@style-def`）は評価（golem-eval の `Golem.Eval.Settings`）が同じ検査をし、位置はその `@style-def` の行になる
- ADR: [golem-driver ADR 0003](golem-driver/adr/0003-pdf-heading-styles.md)（定めた）、[docs/adr/0005](adr/0005-character-and-paragraph-styles.md)（段落スタイルに広げた）、[docs/adr/0014](adr/0014-in-file-settings.md)（ファイルの中の定義に広げた）。位置は [golem-project ADR 0008](golem-project/adr/0008-style-toml-value-positions.md) が定めた

### 主な原因

- 見出し、文字スタイル、段落スタイルの `font` に、`[fonts]` にない役割を書いた。

### 直し方

`[fonts.<役割>]` を定義するか、役割の名前を直す。

## G0309

@import の形が不正です

- 重大度: エラー
- 状態: 使用中

### 意味

`@import` の引数が `パス as 名前空間` の形でない。
引数は、ちょうど三つの位置引数「語か文字列」「語 `as`」「語」の並びでなければならない。
キーワード引数、式やコマンドの引数、引数の数の違いは、すべてこの誤りである。

- メッセージ: `@import は「@import パス as 名前空間」の形で書きます`
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project.Imports`）。プロジェクトの外のファイルを評価するときは、golem-eval の `Golem.Eval.File` が同じ関数で調べる。位置はその `@import` のブロック全体である
- ADR: [golem-project ADR 0006](golem-project/adr/0006-project-diagnostic-codes.md)（定めた）。[golem-driver ADR 0003](golem-driver/adr/0003-pdf-heading-styles.md) と [golem-project ADR 0004](golem-project/adr/0004-font-file-check-per-target.md) が使用済みの番号として触れる

### 主な原因

- `@import` の引数を `パス as 名前空間` の形で書かなかった。

### 直し方

`@import vars.gm as v` のように書く。

## G0310

フォントのファイルがないので、HTML と EPUB に同梱しません

- 重大度: dev では警告、prod ではエラー
- 状態: 使用中

### 意味

HTML か EPUB を作るときに、`[fonts]` が指すフォントのファイルがない。
そのフォントを同梱せず、`@font-face` も書かずに出力する。
prod では HTML と EPUB を書かない。
LSP は出さない。

- メッセージ: `フォントのファイルがないので、HTML と EPUB に同梱しません: <パス>`
- 段階とモジュール: プロジェクト（golem-driver の `Golem.Driver`）
- ADR: [golem-project ADR 0004](golem-project/adr/0004-font-file-check-per-target.md)

### 主な原因

- `style.toml` の `[fonts]` のパスの綴りを誤った。
- フォントのファイルを置いていない。`golem new --no-fonts` で作ったプロジェクトで起きる。

### 直し方

フォントのファイルを置くか、`[fonts]` のパスを直す。

## G0311

段落スタイルの文字の大きさが版面の文字の大きさを超えます

- 重大度: エラー
- 状態: 使用中

### 意味

段落スタイルの解決した `size` が、`[page.grid]` の文字の大きさを超える。

- メッセージ: `段落スタイルの文字の大きさが版面の文字の大きさを超えます: <名前>`
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project.Style`）。`style.toml` の検査の位置は、直すべき値（`font`、`size`、`first-line-indent`、`based-on`、`color`、`kerning` など）の位置であり、その値が書かれていなければそのスタイルなどの表の見出しの位置である。ファイルの中の定義（`@style-def`）は評価（golem-eval の `Golem.Eval.Settings`）が同じ検査をし、位置はその `@style-def` の行になる
- ADR: [docs/adr/0005](adr/0005-character-and-paragraph-styles.md)。位置は [golem-project ADR 0008](golem-project/adr/0008-style-toml-value-positions.md) が定めた

### 主な原因

- 段落スタイルの `size` を、`[page.grid]` の文字の大きさより大きくした。`based-on` で継いだ値も含む。

### 直し方

段落スタイルの `size` を版面の文字の大きさ以下にする。

## G0312

段落の最初の行が版面の外に出ます

- 重大度: エラー
- 状態: 使用中

### 意味

段落スタイルの `indent` と `first-line-indent` の和が負になる。

- メッセージ: `段落の最初の行が版面の外に出ます。indent と first-line-indent の和を 0 以上にしてください: <名前>`
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project.Style`）。`style.toml` の検査の位置は、直すべき値（`font`、`size`、`first-line-indent`、`based-on`、`color`、`kerning` など）の位置であり、その値が書かれていなければそのスタイルなどの表の見出しの位置である。ファイルの中の定義（`@style-def`）は評価（golem-eval の `Golem.Eval.Settings`）が同じ検査をし、位置はその `@style-def` の行になる
- ADR: [docs/adr/0006](adr/0006-paragraph-indent.md)。位置は [golem-project ADR 0008](golem-project/adr/0008-style-toml-value-positions.md) が定めた

### 主な原因

- ぶら下げのために負の `first-line-indent` を書いたが、`indent` が足りない。

### 直し方

ぶら下げの分だけ `indent` を大きくし、`indent` と `first-line-indent` の和を 0 以上にする。

## G0313

style.toml のスタイルの参照が不正です

- 重大度: エラー
- 状態: 使用中

### 意味

`based-on` が存在しないスタイルを指すか、循環するか、`body` に `based-on` があるか、文字スタイルの `color` が `[color.swatches]` にない。
罫線の指定の `color` が `[color.swatches]` にない場合も、この誤りとする。
正規表現スタイルの `style` が文字スタイルにないか、`@style-def regex` の段落スタイルがない場合も、この誤りとする。
段落スタイルの `aki-set` と、アキ量のセットの `based-on` が存在しないセットを指すか、セットの `based-on` が循環する場合も、この誤りとする。

- メッセージ: `style.toml のスタイルの参照が不正です: <理由>`（ファイルの中の定義では `@style-def のスタイルの参照が不正です: <理由>`）。正規表現スタイルの理由は `正規表現スタイルの文字スタイルがありません: <名前>` か `正規表現スタイルの段落スタイルがありません: <名前>`
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project.Style`）。`style.toml` の検査の位置は、直すべき値（`font`、`size`、`first-line-indent`、`based-on`、`color`、`kerning` など）の位置であり、その値が書かれていなければそのスタイルなどの表の見出しの位置である。ファイルの中の定義（`@style-def`）は評価（golem-eval の `Golem.Eval.Settings`）が同じ検査をし、位置はその `@style-def` の行になる
- ADR: [docs/adr/0005](adr/0005-character-and-paragraph-styles.md)（正規表現スタイルの参照は [docs/adr/0015](adr/0015-regex-styles.md)、アキ量のセットの参照は [docs/adr/0019](adr/0019-aki-settings.md)）。位置は [golem-project ADR 0008](golem-project/adr/0008-style-toml-value-positions.md) が定めた

### 主な原因

- `based-on` が存在しないスタイルを指す。
- `based-on` が循環する。
- `body` に `based-on` を書いた。
- 文字スタイルの `color` が `[color.swatches]` にない。
- 文字スタイルの `background` が `[color.swatches]` にない（[golem-driver ADR 0029](golem-driver/adr/0029-inline-code-background.md)）。
- 正規表現スタイルの `style` に、組み込みにも `style.toml` にも同じファイルの `@style-def character` にもない文字スタイルを書いた。
- `@style-def regex` の二つ目の引数に、ない段落スタイルを書いた。
- 段落スタイルの `aki-set` か、`[aki-sets.<名前>]` の `based-on` が、存在しないセットを指す。
- `[aki-sets.<名前>]` の `based-on` が循環する。
- 段落スタイルの `based-on` に `code` を書いた。`code` はほかの段落スタイルの元にならない（[golem-driver ADR 0017](golem-driver/adr/0017-pdf-code-blocks.md)）。
- 段落スタイル `code` の `background` が `[color.swatches]` にない。
- 段落スタイル `code` の `border`、`[code]` の `line-number-color`、`highlight`、`added`、`removed`、`[code.colors]` の値が `[color.swatches]` にない（[golem-driver ADR 0023](golem-driver/adr/0023-code-block-book-features.md)）。
- 罫線の指定（`[notes.rule]`）の `color` が `[color.swatches]` にない。メッセージの理由は `[notes.rule] の color のスウォッチがありません: <名前>` である（[golem-driver ADR 0028](golem-driver/adr/0028-rule-colour-and-style.md)）。
- 段落スタイルか見出しの罫線の `color` が `[color.swatches]` にない。理由は `段落スタイル <名前> の罫線の color のスウォッチがありません: <名前>` か `見出し <階層> の罫線の color のスウォッチがありません: <名前>` である（[golem-driver ADR 0027](golem-driver/adr/0027-paragraph-style-rules.md)、[golem-driver ADR 0028](golem-driver/adr/0028-rule-colour-and-style.md)）。

### 直し方

理由の示すスタイルの `based-on`、`color`、`aki-set`、正規表現スタイルの `style` か段落スタイルの名前、アキ量のセットの `based-on` を直す。
誤りのある正規表現スタイルの組だけを捨て、ほかの組は適用する。

## G0314

柱の内容が正しくありません

- 重大度: エラー
- 状態: 使用中

### 意味

`style.toml` のマスターページの `running-head` の内容が、決まった語彙のどれでもないか、書式が正しくないか、書き方の組み合わせが正しくない。
内容は `content` に一つ書くか、`even` と `odd` の両方に書く。
値は語彙の文字列か、書式の文字列の配列である。
位置は誤った値の位置である。

- メッセージ: 語彙と組み合わせの誤りは `柱の内容が正しくありません: <値>。heading.<階層>.short か heading.<階層>.numbered（末尾に .last を付けられます）、title、none のどれかを、content に一つ、または even と odd の両方に書いてください`。組み合わせの誤りでは、`<値>` に書いた欄と値を並べ、どれも書いていなければ `（なし）` とする。書式の誤りは `柱の書式が正しくありません: <理由>`。どちらも誤った箇所の経路を添える。
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project.Style`）
- ADR: [golem-driver ADR 0014](golem-driver/adr/0014-running-heads.md)、[golem-driver ADR 0022](golem-driver/adr/0022-running-head-formats.md)

### 主な原因

- 内容の値の綴りを誤った（`heading.1.long`、`chapter` など）。
- 見出しの階層に 0 や数でないものを書いた。
- 書式を配列でなく文字列で書いた（`"{meta.title}　{heading.1.short}"`）。
- 書式の `{` を閉じていないか、文字の `}` を `}}` と書いていないか、`{}` を書いた。
- 表にない差し込み（`{heading.1.long}`、`{meta.author}`、`{chapter}` など）か、配列の `{meta.creators}` を書いた。
- 空の配列、空の文字列の行、改行を含む行、文字列でない行を書いた。
- `content` と `even` または `odd` を一緒に書いた。
- `even` と `odd` の片方だけを書いた。
- 位置だけを書き、内容を書かなかった。

### 直し方

`content = "heading.1.short"` のように両方のページの内容を一つ書くか、`even = "title"` と `odd = "heading.1.short"` のように左右のページの内容を両方書く。
書式は `content = ["{meta.title}　{heading.1.short}"]` のように文字列の配列で書き、配列の要素ごとに一行とする。
柱を出さないページには `none` を書くか、`running-head` のないマスターページを使う。

## G0315

正規表現を解釈できません

- 重大度: エラー
- 状態: 使用中

### 意味

正規表現スタイルの `pattern` が、Golem の正規表現の方言（InDesign の方言の部分集合）にない構文を含むか、正規表現として誤っている。
部分集合の外の構文は、黙って別の意味に読まずにこの誤りとする。

- メッセージ: `正規表現を解釈できません: <理由>（<段落スタイル> の <n> 番目の正規表現の <位置> 字目）`
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project.Style`、照合器は golem-regex の `Golem.Regex`）。`style.toml` の検査の位置は、その正規表現スタイルの `pattern` の値の位置である。ファイルの中の `@style-def regex` は評価（golem-eval の `Golem.Eval.Settings`）が同じ検査をし、位置はその行になる
- ADR: [docs/adr/0015](adr/0015-regex-styles.md)。位置は [golem-project ADR 0008](golem-project/adr/0008-style-toml-value-positions.md) が定めた

### 主な原因

- 後方参照（`\1`、`\k<...>`）、名前付きの群、アトミックな群、所有的な量指定子（`*+` など）、条件、コメントの群を書いた。
- 先頭でない位置に `(?i)` を書いたか、ほかのフラグ（`(?s)`、`(?m)`、`(?x)`、`(?-i)`）を書いた。
- 方言の表にない英字のエスケープ（`\h`、`\Q`、`\A` など）か、文字体系の `\p{Han}` を書いた。
- 長さが一つに決まらない後読み（`(?<=a+)` など）を書いた。
- InDesign の `~` のメタ文字（`~m` など）を写した。
- 括弧が閉じていないか、範囲の両端が逆か、`{n,m}` の `n` が `m` より大きい。
- 量指定子の展開を含めて、照合のプログラムが 10000 命令を超えたか、繰り返しの回数に 65535 を超える数を書いた。

### 直し方

理由と位置の示す箇所を直す。
文字の `~` は `\~` と書く。
和文の文字体系は `[\x{4E00}-\x{9FFF}]` のように符号位置の範囲で書く。
長さの異なる候補を持つ後読みは、候補ごとの後読みに分けて並べる（`(?<=ab|c)x` は `(?:(?<=ab)|(?<=c))x` と書く）。
`@style-def regex` の文字列の中では、正規表現の `\` を `\\` と書く。

## G0316

manifest.toml がありません

- 重大度: エラー
- 状態: 使用中

### 意味

プロジェクトのルートに `manifest.toml` がない。
章や `@import` が指すファイルがないときは [G0302](#g0302) とする。

- メッセージ: `manifest.toml がありません`
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project`）。ファイルがないので、位置は表示されない
- ADR: [golem-project ADR 0006](golem-project/adr/0006-project-diagnostic-codes.md)

### 主な原因

- プロジェクトのルートでない場所で `golem` を実行した。
- `manifest.toml` を置いていないか、名前の綴りを誤った。

### 直し方

`golem` をプロジェクトのルートで実行しているかを確かめる。
新しいプロジェクトは `golem new` で作る。

## G0317

判型が不正です

- 重大度: エラー
- 状態: 使用中

### 意味

`style.toml` の `[page]` の `size` が、判型の表の名前でも、正しい `{ width, height }` でもない。
位置は `size` の値の位置である。

- メッセージ: `未知の判型です: <名前>。表にない判型は size = { width = "…", height = "…" } で書きます`、`判型の width と height はどちらも必須です`、`判型には zw を使えません`、`判型の幅と高さは 0 より大きい寸法です`、または未知のキーと寸法の誤りの TOML のスキーマの文言。どれも誤った箇所の経路を添える。
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project.Style`）
- ADR: [golem-project ADR 0005](golem-project/adr/0005-page-size-by-dimensions.md)。位置は [golem-project ADR 0008](golem-project/adr/0008-style-toml-value-positions.md) が定めた

### 主な原因

- 判型の表にない名前を書いたか、名前の綴りを誤った。
- `{ width, height }` の片方を書き忘れた。
- 寸法に `zw` を使ったか、0 以下の値を書いた。

### 直し方

表の名前（`"A4"`、`"A5"`、`"A6"`、`"B5"`、`"B6"`、`"四六判"`、`"菊判"`、`"新書判"`、`"mass-market"`）を書くか、`size = { width = "148mm", height = "210mm" }` のように寸法で書く。
単位は `mm`、`pt`、`Q`、`H`、`in` とし、`zw` は使わない。

## G0318

マスターページの位置が不正です

- 重大度: エラー
- 状態: 使用中

### 意味

`style.toml` の `[masters.<名前>]` の `running-head` か `folio` の `position` が、`top-outside`、`top-inside`、`top-center`、`bottom-outside`、`bottom-inside`、`bottom-center` のどれでもない。
`style.toml` を読むときに検査するので、ターゲットにかかわらず、`golem check` と LSP も報告する。
位置は `position` の値の位置である。

- メッセージ: `未知の位置です: <位置>`。誤った箇所の経路を添える。
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project.Style`）
- ADR: [golem-driver ADR 0016](golem-driver/adr/0016-output-and-layout-diagnostic-codes.md)。位置は [golem-project ADR 0008](golem-project/adr/0008-style-toml-value-positions.md) が定めた

### 主な原因

- `position` の綴りを誤った。
- `middle` や `top` のように、表にない位置を書いた。

### 直し方

`position` に上の 6 つのどれかを書く。

## G0319

見出しの running-head は廃止しました

- 重大度: エラー
- 状態: 使用中

### 意味

`style.toml` の `[headings.<階層>]` に `running-head` を書いた。
柱に使う見出しは、マスターページの `running-head` の内容で決める。

- メッセージ: `[headings.<l>] の running-head は廃止しました。柱に使う見出しは [masters.<名前>] の running-head の content で指定してください`。誤った箇所の経路を添える。
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project.Style`）
- ADR: [golem-driver ADR 0014](golem-driver/adr/0014-running-heads.md)

### 主な原因

- 以前の `style.toml` の `[headings.1]` の `running-head = true` が残っている。

### 直し方

`[headings.<階層>]` の `running-head` の行を消し、マスターページの `running-head` に `content = "heading.1.short"` のように柱に出す見出しの階層を書く。

## G0320

アキの量の指定が正しくありません

- 重大度: エラー
- 状態: 使用中

### 意味

`style.toml` の `[aki-sets.<名前>]` か、寸法の欄に書いたアキの量が正しくない。
`[aki-sets]` の中の誤りは、すべてこのコードになる。
ファイルの中の段落スタイルの定義（`@style-def`）の寸法の欄も同じである。

- メッセージ: `アキの量の指定が正しくありません: <理由>`。理由は `アキの量として読めません: <値>`、`未知のクラスの名前です: <名前>`、`line-end は after にだけ書けます`、`<名前> は before にだけ書けます`、`minimum、optimum、maximum の順に小さくない値を書きます`、`組み込みのアキ量のセットと同じ名前です。…`、`アキの量の名前と百分率は、アキの量を書く欄でだけ使えます。…` などである。誤った箇所の経路を添える。`[aki-sets]` の中の型の誤りは、TOML のスキーマの文言になる。
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project.Style`）。位置は誤った値の位置であり、組み込みのセットと同じ名前のセットではそのセットの表の見出しの位置である。`@style-def` の寸法の欄は評価（golem-eval の `Golem.Eval.Settings`）
- ADR: [docs/adr/0019](adr/0019-aki-settings.md)。位置は [golem-project ADR 0008](golem-project/adr/0008-style-toml-value-positions.md) が定めた

### 主な原因

- 規則の `optimum`、`minimum`、`maximum` に、読めない量や負の量を書いた。
- `minimum` が `optimum` より大きいか、`optimum` が `maximum` より大きい。
- `before` と `after` に未知のクラスの名前を書いた。
- `line-end` を `before` に、`line-start` か `paragraph-start` を `after` に書いた。
- 組み込みのセット（`gyomatsu-yakumono-hankaku`、`gyomatsu-yakumono-zenkaku`）と同じ名前の節を書いた。
- `indent = "二分"` のように、アキの量の名前や百分率を寸法の欄に書いた。

### 直し方

量は `"四分"`、`"0.25zw"`、`"25%"` のように書き、`minimum <= optimum <= maximum` にする。
クラスの名前は仕様書の表のとおりに書く。
組み込みのセットを変えたいときは、`based-on` で引き継いだ別の名前のセットを作る。
寸法の欄には `"0.5zw"` や `"2mm"` のように寸法を書く。

## G0321

文字の送りの欄の値が正しくありません

- 重大度: エラー
- 状態: 使用中

### 意味

文字スタイルか段落スタイルの `kerning`、`tracking`、`proportional-metrics`、`baseline-shift` の値が正しくない。
`style.toml` の `[character-styles.<名前>]` と `[paragraph-styles.<名前>]` にも、ファイルの中の定義（`@style-def`）にも出る。
`kerning = "optical"` もこのコードになる。
オプティカルカーニングは v2 以降に回した。

- メッセージ: `<欄> の値が正しくありません: <値>`。`tracking` の範囲の外では `（-1000 から 10000 までです）` を添える。`kerning = "optical"` は `v1 ではオプティカルカーニングを使えません（<文字スタイル|段落スタイル> <名前> の kerning）`。値の型の誤りは、`character-styles.<名前>.kerning には文字列を書きます（整数が書かれています）` のように文言の中に経路を書く（`@style-def` では経路は `kerning` だけになる）。そのほかの文言には誤った箇所の経路を添える。
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project.Style`）。`style.toml` の検査の位置は、直すべき値（`font`、`size`、`first-line-indent`、`based-on`、`color`、`kerning` など）の位置であり、その値が書かれていなければそのスタイルなどの表の見出しの位置である。ファイルの中の定義は評価（golem-eval の `Golem.Eval.Settings`）が同じ検査をし、位置はその `@style-def` の行になる
- ADR: [docs/adr/0020](adr/0020-indesign-character-features.md)。[golem-project ADR 0007](golem-project/adr/0007-toml-messages-in-japanese.md) が値の型の誤りの文言を日本語にした。位置は [golem-project ADR 0008](golem-project/adr/0008-style-toml-value-positions.md) が定めた

### 主な原因

- `kerning` に `metrics`、`japanese-equal-width`、`none` のほかの値を書いた。
- `kerning = "optical"` と書いた。
- `tracking` が -1000 から 10000 までの整数でない。
- `proportional-metrics` が真偽値でない。
- `baseline-shift` が `"1pt"` や `"-0.25zw"` のような寸法として読めない。

### 直し方

`kerning` は `metrics`、`japanese-equal-width`、`none` のどれかにする。
オプティカルカーニングの代わりには `metrics` を使う。
`tracking` は -1000 から 10000 までの整数（文字の大きさの 1/1000 が単位）で、`proportional-metrics` は `true` か `false` で、`baseline-shift` は符号付きの寸法で書く。

## G0322

リストの書式が正しくありません

- 重大度: エラー
- 状態: 使用中

### 意味

`style.toml` の `[lists]` の `bullets`、`numbers`、`gap` のどれかが正しくない。
メッセージがどの欄の誤りかを示す。

- メッセージ: `[lists] の <欄> が正しくありません: <理由>`。理由は `空の配列です`、`空の文字列があります`、`番号の差し込みがありません`、`番号の差し込みが二つ以上あります`、`表にない差し込みです: {x}`、`寸法として読めません`、`負の寸法です` など。誤った箇所の経路を添える。
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project.Style`）。位置は誤ったキーの値の位置である
- ADR: [golem-driver ADR 0013](golem-driver/adr/0013-list-indents.md)。位置は [golem-project ADR 0008](golem-project/adr/0008-style-toml-value-positions.md) が定めた

### 主な原因

- `bullets` か `numbers` を空の配列にしたか、空の文字列を書いた。
- `numbers` の書式に番号の差し込みを書かなかったか、二つ以上書いたか、表にない差し込みを書いた。
- 差し込みでない `{` と `}` を、`{{` と `}}` と書かなかった。
- `gap` が寸法として読めないか、負である。

### 直し方

`bullets` には印の文字列を、`numbers` には `"{n}."` や `"({a})"` のように差し込みをちょうど一つ含む書式を、一つ以上書く。
差し込みは `{n}`、`{1}`、`{一}`、`{①}`、`{a}`、`{A}`、`{i}`、`{I}`、`{ア}`、`{イ}` のどれかにする。
`gap` は `"0.5zw"` のように 0 以上の寸法で書く。

## G0323

style.toml がないので、既定の体裁で組みます

- 重大度: お知らせ
- 状態: 使用中

### 意味

プロジェクトルートに `style.toml` がない。
`style.toml` がなくても HTML、EPUB、プレーンテキストは組めるので、既定の体裁で組まれていることに気づきにくい。
PDF はフォントの設定がないので [G0807](#g0807) で止まるが、そのときもこのお知らせを出す。
位置は `manifest.toml` の先頭である。

- メッセージ: `style.toml がないので、既定の体裁で組みます`
- 段階とモジュール: プロジェクト（golem-driver の `Golem.Driver`）
- ADR: [golem-syntax ADR 0002](golem-syntax/adr/0002-notice-severity.md)

### 主な原因

- `style.toml` を置かずにプロジェクトを作った。
- `style.toml` を別の名前で保存した、または別のディレクトリに置いた。

### 直し方

既定の体裁でよいなら、直す必要はない。
`silence-notices` に `"G0323"` を加えると、このお知らせを出さなくなる。
体裁を決めるなら、プロジェクトルートに `style.toml` を置く。
`golem new` で作ったプロジェクトの `style.toml` が雛形になる。

## G0324

silence-notices に抑制できないコードがあります

- 重大度: エラー
- 状態: 使用中

### 意味

`manifest.toml` の `[diagnostics]` の `silence-notices` に、お知らせのコードでないものを書いた。
抑制できるのはお知らせだけであり、エラーと警告のコード、廃止したコード、存在しないコード、コードの形でない文字列（`"g262"`、`"all"` など）はこのエラーになる。
エラーと警告のコードを書いても抑制できないことを、黙って無視せずに伝える。
位置は `silence-notices` の値の中のそのコードである。

- メッセージ: `抑制できるのはお知らせのコードだけです: <コード>`、`診断のコードは G と 4 桁の数字で書きます: <文字列>`、`診断のコードは文字列で書きます`
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project.Manifest`）
- ADR: [golem-syntax ADR 0002](golem-syntax/adr/0002-notice-severity.md)

### 主な原因

- 警告やエラーを止めるつもりで、そのコードを書いた。
- Golem のバージョンを上げて、書いてあったお知らせのコードが廃止になった。
- コードを小文字で書いた。

### 直し方

そのコードを `silence-notices` から消す。
エラーと警告は抑制できないので、原因を直す。
コードは大文字の `G` と 4 桁の数字で書く。
`silence-notices` の値そのものが配列でない場合（`silence-notices = "all"` など）は [G0301](#g0301) になる。
すべてのお知らせを一度だけ止めたい場合は、コマンドに `--no-notices` を付ける。

## G0325

[index] の値が正しくありません

- 重大度: エラー
- 状態: 使用中

### 意味

`style.toml` の `[index]` の `columns` が 1 以上の整数でないか、`column-gap` が寸法として読めないか負である。
位置はその値である。
`[index]` の未知のキーは [G0306](#g0306) である。

- メッセージ: `[index] の columns は 1 以上の整数です` または `[index] の column-gap が正しくありません`。誤った箇所の経路を添える。
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project.Style`）
- ADR: [docs/adr/0025](adr/0025-index-columns.md)。位置は [golem-project ADR 0008](golem-project/adr/0008-style-toml-value-positions.md) が定めた

### 主な原因

- `columns` に 0 や負の数、小数、文字列（`"2"`）を書いた。
- `column-gap` に負の寸法か、単位のない値を書いた。

### 直し方

`columns` は `2` のように 1 以上の整数で、`column-gap` は `"2zw"` のように 0 以上の寸法で書く。

## G0326

参考文献のファイルを読めません

- 重大度: エラー
- 状態: 使用中

### 意味

`manifest.toml` の `bibliography` に並べたファイルがないか、JSON として読めないか、最上位が配列でない。
重大度はプロファイルで変わらない。
位置は `manifest.toml` の先頭である。
`Manifest` が値の位置を持たないためであり、[G0302](#g0302) と同じ扱いである。
パスの形の誤り（URL、絶対パス、ルートの外）は [G0303](#g0303) とする。
読めなかったファイルの項目はないものとして評価を続けるので、そのファイルの文献を引く `[cite ...]` には [G0221](#g0221) も出る。
G0326 はそれらより先に並ぶ。

- メッセージ: `参考文献のファイルがありません: <パス>`、`参考文献のファイルを JSON として読めません: <パス>（<aeson の文言>）`、`参考文献のファイルは CSL-JSON の配列で書きます: <パス>`。aeson の文言は英語のままである
- 段階とモジュール: プロジェクト（golem-driver の `Golem.Driver.loadBibliography`）。`golem check` とどのターゲットのビルドも出す
- ADR: [golem-doc ADR 0004](golem-doc/adr/0004-bibliography-formatting.md)

### 主な原因

- `bibliography` のパスの綴りを誤ったか、ファイルを置いていない。
- 文献管理ソフトから書き出したファイルが途中で切れているか、JSON でない形式（BibTeX など）で書き出した。
- 項目を一つだけ書くつもりで、`[` と `]` で囲まずにオブジェクトを書いた。

### 直し方

パスとファイルの置き場所を確かめ、ファイルを CSL-JSON の配列（`[{"id": ...}, ...]`）で書く。

## G0327

章末の注の番号が章の中で重なります

- 重大度: 警告
- 状態: 使用中

### 意味

注を章の末尾にまとめる出力で、章の注の一覧の中に同じ番号が二度現れる。
`[notes]` の `numbering` が `"file"` で、マニフェストの二つ以上のファイルからなる章の、二つ以上のファイルに注があるときに出る。
注を章の末尾にまとめる出力は、`placement = "chapter-end"` の PDF と、`placement` によらず HTML、EPUB、プレーンテキストである。
ターゲットが PDF だけで `placement` が `"page-foot"` なら出さない。
出力は止めず、重なった番号のまま組む。
HTML と EPUB では、注の id に章の中のファイルの順番を入れて（`note-2-1` など）、一つの文書の中で id が重ならないようにする。

- メッセージ: `章末の注の番号が章の中で重なります（<章の最初のファイル>）。[notes] の numbering を "chapter" にしてください`
- 段階とモジュール: プロジェクト（golem-driver の `Golem.Driver.chapterNoteDiagnostics`）。位置は、その章で注を持つ二つ目のファイルの最初の注である。`golem check` とビルドが出す
- ADR: [golem-driver ADR 0026](golem-driver/adr/0026-chapter-end-notes.md)

### 主な原因

- 一つの章を複数のファイルに分け、`[notes]` の `numbering` を `"file"` にした。

### 直し方

`[notes]` の `numbering` を `"chapter"`（既定）か `"book"` にする。

## G0328

manifest.toml に出力に書けない文字があります

- 重大度: エラー
- 状態: 使用中

### 意味

`manifest.toml` の文字列の値（`[metadata]` の `title`、`publisher`、`creators` の `name` など、どのテーブルの文字列も）に、出力に書けない文字がある。
出力に書けない文字は、U+0000 から U+001F のうちタブ、改行、復帰以外と、U+FFFE、U+FFFF、サロゲートの符号位置である（[G0289](#g0289) と同じ）。
TOML の文字列に生の制御文字は書けないので、これに当たるのは `\u0001` のようなエスケープである。
スキーマの検査の前に検査し、一つでもあればマニフェストを読まない。
一つの文字列に複数あれば最初の一つを述べ、文字列ごとに一つ出す。
位置は、その値の TOML の位置である。
dev と prod の両方でエラーであり、LSP も同じく出す。

- メッセージ: `<キーの経路> に出力に書けない文字（<符号位置>）があります`（例: `metadata.title に出力に書けない文字（U+0001）があります`）
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project.Manifest`）
- ADR: [docs/adr/0042](adr/0042-control-characters-and-glob-metacharacters.md)

### 主な原因

- 書名や著者名に、`\u0001` のような制御文字のエスケープを書いた。

### 直し方

メッセージの経路の値から、その文字のエスケープを消す。

## G0329

隠しノンブルが仕上がりの線を越えます

- 重大度: エラー
- 状態: 使用中

### 意味

`style.toml` の `[hidden-folio]` の `gutter` が `size` の半分より小さい（`2 × gutter < size`）。
隠しノンブルの数字の列は、ノドの仕上がりの線から `gutter` の距離にある中心線から、左右に `size` の半分ずつの幅を持つとして測るので、列がノドの仕上がりの線を越える。
フォントの字の送りは使わず、実際の数字の幅より広い `size` で測る（[G0750](#g0750) と同じ）。
`style.toml` をスキーマのとおりに読めた後の検査であり、ほかの検査の誤り（[G0311](#g0311) など）と一緒に出す。
TOML として読めないか、スキーマに合わない（[G0306](#g0306) などで読み込みが止まる）ときは検査しない。
`enabled`、`--marks`、ターゲットによらず検査する。
位置は `gutter` の値で、`gutter` を書かず `size` だけを書いた場合は `size` の値である。
値はどれも mm で、小数第 2 位まで書く。
`<下限>` は、検査を通る `gutter` のうち 0.01mm の倍数で最も小さい値、`<上限>` は、検査を通る `size` のうち 0.01mm の倍数で最も大きい値であり、どちらも `style.toml` の寸法と同じ丸めで sp に直して求める。
diagnostic の事実（JSON の `facts`）に、`gutter`、`size`、`min-gutter`、`max-size` を sp の整数で持つ。

- メッセージ: `[hidden-folio] の gutter（<gutter>）が size（<size>）の半分（<半分>）より小さいため、隠しノンブルの数字が仕上がりの線を越えます（gutter を <下限> 以上にするか、size を <上限> 以下にします）`（例: `size = "6pt"`、`gutter = "2pt"` では `[hidden-folio] の gutter（0.71mm）が size（2.12mm）の半分（1.06mm）より小さいため、隠しノンブルの数字が仕上がりの線を越えます（gutter を 1.06mm 以上にするか、size を 1.41mm 以下にします）`）
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project.Style`）
- ADR: [golem-driver ADR 0041](golem-driver/adr/0041-hidden-folio-overlap-check-by-size.md)

### 主な原因

- `[hidden-folio]` の `gutter` を小さくしすぎた。
- `[hidden-folio]` の `size` を大きくしすぎた。

### 直し方

`[hidden-folio]` の `gutter` を大きくするか、`size` を小さくする。
メッセージの下限か上限の値をそのまま `"1.06mm"` のように書けば、検査を通る。

## G0401

ラベルが重複しています

- 重大度: エラー
- 状態: 使用中

### 意味

同じラベルを二つ以上の要素に付けた。
マニフェストの章の順、ファイルの中の順で、二つ目以降のそれぞれに一つ出る。
位置はラベルを付けたブロックであり、関連情報に最初の定義の位置を示す。

- メッセージ: `ラベルが重複しています: <ラベル>`
- 段階とモジュール: 文書の組み立て（golem-doc の `Golem.Doc.Assemble`）
- ADR: [golem-doc ADR 0003](golem-doc/adr/0003-document-diagnostic-codes.md)

### 主な原因

- 同じラベルを二つの要素に付けた。関連情報に最初の定義の位置を示す。

### 直し方

どちらかのラベルを別の名前にする。

## G0402

@toc は文書に一つだけ置けます

- 重大度: エラー
- 状態: 使用中

### 意味

文書（すべての章のファイル）に `@toc` が二つ以上ある。
二つ目以降の `@toc` のそれぞれに一つ出る。
関連情報に、一つ目の `@toc` の位置を示す。

- メッセージ: `@toc は文書に一つだけ置けます`
- 段階とモジュール: 文書の組み立て（golem-doc の `Golem.Doc.Assemble`）
- ADR: [golem-doc ADR 0003](golem-doc/adr/0003-document-diagnostic-codes.md)

### 主な原因

- 文書に `@toc` を二つ以上書いた。

### 直し方

`@toc` を一つにする。
関連情報が示す一つ目の `@toc` を残すなら、この診断が出た `@toc` をすべて消す。

## G0403

存在しないラベルへの参照です

- 重大度: エラー
- 状態: 使用中

### 意味

相互参照（`ref-number`、`ref-title`、`ref-page`）が、どこにも付いていないラベルを指す。
参照の種類を問わない。
位置は参照であり、参照は何も出力しない。

- メッセージ: `存在しないラベルへの参照です: <ラベル>`
- 段階とモジュール: 文書の組み立て（golem-doc の `Golem.Doc.Assemble`）
- ADR: [golem-doc ADR 0003](golem-doc/adr/0003-document-diagnostic-codes.md)（[golem-lsp ADR 0002](golem-lsp/adr/0002-utf8-position-encoding.md) がテストの例として触れる）

### 主な原因

- 相互参照のラベルの綴りを誤った。
- 参照先に `@label` を付けていない。

### 直し方

ラベルの綴りを確かめ、参照先に `@label` を付ける。

## G0404

章の外にある図版とコードに、章番号を使う番号を振れません

- 重大度: エラー
- 状態: 使用中

### 意味

`style.toml` の図番号の書式（`figures.number`）が `{chapter}` を使うのに、章の番号を持たない図版がある。
リスト番号の書式（`[code]` の `number`、既定 `リスト{chapter}-{n}`）が `{chapter}` を使うのに、章の番号を持たない、キャプションのあるコードブロックがある場合も、この誤りとする。
章は、番号を持つ階層 1 の見出しから、次の階層 1 の見出しまでである。
最初の章の見出しより前の図版とコードブロックと、`@nonumber` の階層 1 の見出し（あとがきなど）の後のものが、章の外になる。
キャプションのないコードブロックは番号を持たないので、この誤りにならない。
位置は図版かコードブロックのブロックである。

- メッセージ: `章の外にある図版とコードには、章番号を使う番号を振れません。章は番号を持つ階層 1 の見出しから始まります`
- 段階とモジュール: 文書の組み立て（golem-doc の `Golem.Doc.Assemble`）
- ADR: [golem-doc ADR 0003](golem-doc/adr/0003-document-diagnostic-codes.md)（コードブロックの条件は [golem-driver ADR 0023](golem-driver/adr/0023-code-block-book-features.md) が加えた）

### 主な原因

- 図番号かリスト番号の書式が `{chapter}` を使うのに、最初の章の見出しより前に図版かキャプションのあるコードブロックを置いた。
- 図番号かリスト番号の書式が `{chapter}` を使うのに、`@nonumber` の階層 1 の見出し（あとがきなど）の後に図版かキャプションのあるコードブロックを置いた。

### 直し方

図版とコードブロックを章の中に移すか、番号の書式から `{chapter}` を外す。

## G0405

番号を持たない要素への参照です

- 重大度: エラー
- 状態: 使用中

### 意味

`ref-number` が、番号を持たない要素を指す。
番号を持つのは、`@nonumber` のない見出し、図版、キャプションを付けたコードブロックである。
位置は参照であり、参照は何も出力しない。

- メッセージ: `番号を持たない要素への参照です: <ラベル>`
- 段階とモジュール: 文書の組み立て（golem-doc の `Golem.Doc.Assemble`）
- ADR: [golem-doc ADR 0003](golem-doc/adr/0003-document-diagnostic-codes.md)、[golem-driver ADR 0023](golem-driver/adr/0023-code-block-book-features.md)（コードブロック）

### 主な原因

- `ref-number` で、番号のない見出しなど、番号を持たない要素を指した。

### 直し方

題を参照するなら `ref-title` を使う。
番号を参照するなら、番号の付く要素にラベルを移す。

## G0406

題を持たない要素への参照です

- 重大度: エラー
- 状態: 使用中

### 意味

`ref-title` が、題を持たない要素を指す。
題を持つのは、見出し（`@toc-title` があればそれ）、図版（代替テキスト）、キャプションを付けたコードブロック（キャプション）である。
段落、リスト、表、キャプションのないコードブロックなどに付けたラベルは、`ref-title` で参照できない。
位置は参照であり、参照は何も出力しない。

- メッセージ: `題を持たない要素への参照です: <ラベル>`
- 段階とモジュール: 文書の組み立て（golem-doc の `Golem.Doc.Assemble`）
- ADR: [golem-doc ADR 0003](golem-doc/adr/0003-document-diagnostic-codes.md)、[golem-driver ADR 0023](golem-driver/adr/0023-code-block-book-features.md)（コードブロック）

### 主な原因

- 段落、リスト、表などに付けたラベルを `ref-title` で指した。
- 題を参照するつもりで、見出しではなく、見出しの次の段落にラベルを付けた。

### 直し方

題を参照するなら、見出しか図版にラベルを移す。
その箇所のページを参照するなら `ref-page` を使う。

## G0407

@number が自動で振られる番号と同じです

- 重大度: お知らせ
- 状態: 使用中

### 意味

見出しか番号付きリストの項目の `@number N` が、`@number` がなくても振られる番号と同じである。
今は効果がないが、項目を入れ替えたときに番号を固定してしまう。
見出しの番号は文書の組み立てで求めた番号と比べ、`@nonumber` の見出しが番号を消費しないことも含めて判定する。
リストの項目の前に `@number` を置くと、その項目から別のリストになる。
その場合は、直前のリストの続きとして振られる番号と比べる。
位置は `@number` の行である。

- メッセージ: `@number <N> は自動で振られる番号と同じです`
- 段階とモジュール: 文書の組み立て（golem-doc の `Golem.Doc.Assemble`）
- ADR: [golem-syntax ADR 0002](golem-syntax/adr/0002-notice-severity.md)

### 主な原因

- 番号を確かめるつもりで、自動の番号と同じ `@number` を書いた。
- 前の項目を消して、`@number` の番号が自動の番号と一致した。

### 直し方

`@number` の行を消す。
番号は自動で振られる。

## G0408

本の最後の改ページは効果がありません

- 重大度: お知らせ
- 状態: 使用中

### 意味

本の最後のファイルで、最後のブロックの後に改ページ（`@page-break`、`@column-break`）しかない。
本の最後の改ページは捨てられるので、白ページは作られない。
ファイルの末尾の改ページは次のファイルに適用されるので、本の最後のファイルのものだけを対象にする。
改ページが続く場合は、一つずつ出す。
位置は改ページのコマンドの行である。

- メッセージ: `本の最後の改ページは効果がありません`
- 段階とモジュール: 文書の組み立て（golem-doc の `Golem.Doc.Assemble`）
- ADR: [golem-syntax ADR 0002](golem-syntax/adr/0002-notice-severity.md)、[docs/adr/0017](adr/0017-forced-page-breaks.md)

### 主な原因

- 白ページを作るつもりで、本の最後に `@page-break` を書いた。
- 章ごとに末尾へ改ページを書く習慣で、最後の章にも書いた。

### 直し方

本の最後の改ページを消す。

## G0409

本の最後の `@blank-line` は効果がありません

- 重大度: お知らせ
- 状態: 使用中

### 意味

本の最後のブロックの後に、`@blank-line` しかない。
間とその後に改ページ（`@page-break`、`@column-break`）、`@need-lines`、`@page-lines`、`@no-page-break` があっても同じである。
本の最後の行アキは、すべての出力で捨てる。
ファイルの末尾の `@blank-line` は次のファイルの最初のブロックの前に置かれるので、本の全体で後にブロックがないものだけを対象にする。
`@blank-line` が続く場合は、一つずつ出す。
位置は `@blank-line` の行である。

- メッセージ: `本の最後の @blank-line は効果がありません`
- 段階とモジュール: 文書の組み立て（golem-doc の `Golem.Doc.Assemble`）
- ADR: [docs/adr/0046](adr/0046-blank-line-command.md)

### 主な原因

- 最後の章の末尾に、空きを残すつもりで `@blank-line` を書いた。

### 直し方

本の最後の `@blank-line` を消す。
`manifest.toml` の `[diagnostics]` の `silence-notices` に `"G0409"` を加えると、このお知らせを出さなくなる。

## G0410

`@blank-line` の直後に改ページがあります

- 重大度: 警告
- 状態: 使用中

### 意味

`@blank-line` の直後に、ほかのブロックを挟まずに `@page-break` か `@column-break` がある。
間に `@need-lines`、`@page-lines`、ほかの `@blank-line` があっても同じ位置とみなす。
ファイルの末尾の `@blank-line` と、次のファイルの先頭の改ページの組み合わせも対象にする。
行アキは次のブロックの前に置くので、改ページの前の行アキは、PDF では必ず改ページの後の段の先頭に移って捨てられる。
HTML、EPUB、プレーンテキストで空きが出ると媒体のあいだで結果が食い違うので、その行アキをすべての出力で捨てる。
位置は `@blank-line` の行である。
本の最後では [G0409](#g0409) も出る。

- メッセージ: `@blank-line の直後に @page-break があります`、`@blank-line の直後に @column-break があります`
- 段階とモジュール: 文書の組み立て（golem-doc の `Golem.Doc.Assemble`）
- ADR: [docs/adr/0046](adr/0046-blank-line-command.md)

### 主な原因

- 章の終わりに空きを入れてから改ページした。
- 改ページの後の本文を下げるつもりで、改ページの前に `@blank-line` を書いた。

### 直し方

改ページの前の `@blank-line` を消す。
改ページの後の段の先頭の行アキも捨てられるので、改ページの後の本文を下げる用途には使えない。

## G0411

`@blank-line` の行数がページの行数以上なので捨てます

- 重大度: お知らせ
- 状態: 使用中

### 意味

`@blank-line` の行数が、`style.toml` の `[page.grid]` の `lines`（ページの行数）以上である。
続けて書いた `@blank-line`（間に `@need-lines`、`@page-lines`、`@no-page-break` しかないもの）は、行数の和で判定する。
ファイルの末尾の `@blank-line` と、次のファイルの先頭の `@blank-line` も続けて書いたものとみなす。
PDF では、ページの行数以上の行アキは次のブロックの最初の行とともに一つの段に入らないので、必ず段の先頭で捨てられる。
HTML、EPUB、プレーンテキストに残ると、媒体のあいだで結果が食い違い、出力が行数に比例して膨らむので、その行アキをすべての出力で捨てる。
`@blank-line` が続く場合は、一つずつ出す。
位置は `@blank-line` の行である。
`@page-lines` による段の行数の増減は、判定に含めない。
`[page.grid]` のない本では判定しない。
[G0409](#g0409) か [G0410](#g0410) で捨てる行アキには出さない。

- メッセージ: `@blank-line の行数 <n> がページの行数 <L> 以上なので捨てます`。`<n>` は続けて書いた `@blank-line` の行数の和、`<L>` はページの行数である。
- 段階とモジュール: 文書の組み立て（golem-doc の `Golem.Doc.Assemble`）
- ADR: [docs/adr/0047](adr/0047-blank-line-limit.md)

### 主な原因

- 段やページの全体を空けるつもりで、ページの行数以上の `@blank-line` を書いた。
- 判型を変えて、ページの行数が減った。

### 直し方

ページを改めたいなら、`@blank-line` を `@page-break` に書き換える。
空きを残したいなら、行数をページの行数より少なくする。
`manifest.toml` の `[diagnostics]` の `silence-notices` に `"G0411"` を加えると、このお知らせを出さなくなる。

## G0501

改行の前後が欧文なので、単語が空白なしにつながります

- 重大度: エラー
- 状態: 使用中

### 意味

段落の中の改行の前後が、ともに欧文の文字である。
段落の中の改行は文字を生まないので、単語が空白なしにつながる。
`line-breaks = "keep"` の段落スタイルの段落の行の区切りには当てない。
改行の様式（`[source]` の `paragraph-separator = "line"`）のファイルの段落とリストの項目の改行は段落の区切りなので当てず、散文スロットの中の改行にだけ当てる。

- メッセージ: `改行の前後が欧文なので、単語が空白なしにつながります。一行で書いてください`
- 段階とモジュール: lint（golem-lint の `Golem.Lint`）
- ADR: [golem-lint ADR 0001](golem-lint/adr/0001-lint-rules.md)（定めた）、[docs/adr/0003](adr/0003-verse-line-breaks.md) と [docs/adr/0005](adr/0005-character-and-paragraph-styles.md)（例外を定めた）、[docs/adr/0013](adr/0013-paragraph-separator.md)（改行の様式の扱いを定めた）

### 主な原因

- 欧文の文を、段落の中で改行して書いた。段落の中の改行は文字を生まない。

### 直し方

欧文の文は一行で書くか、改行の前に空白を置く。
行を保ちたい段落には、`line-breaks = "keep"` の段落スタイル（`verse` など）を付ける。

## G0502

使われていない変数です

- 重大度: エラー
- 状態: 使用中

### 意味

`@set` の変数が、そのファイルの中でも、そのファイルを import するどのファイルからも参照されていない。

- メッセージ: `使われていない変数です: <名前>`
- 段階とモジュール: lint（golem-lint の `Golem.Lint`）
- ADR: [golem-lint ADR 0001](golem-lint/adr/0001-lint-rules.md)

### 主な原因

- `@set` で定義した変数を、どこからも参照していない。

### 直し方

変数を消すか、使う。

## G0503

使われていない import です

- 重大度: エラー
- 状態: 使用中

### 意味

`@import` の名前空間が一度も参照されていない。

- メッセージ: `使われていない import です: <名前空間>`
- 段階とモジュール: lint（golem-lint の `Golem.Lint`）
- ADR: [golem-lint ADR 0001](golem-lint/adr/0001-lint-rules.md)

### 主な原因

- `@import` の名前空間を一度も参照していない。

### 直し方

`@import` を消すか、使う。

## G0504

参照されていないラベルです

- 重大度: dev では警告、prod ではエラー
- 状態: 使用中

### 意味

`@label` で付けたラベルを、どこからも参照していない。

- メッセージ: `参照されていないラベルです: <ラベル>`
- 段階とモジュール: lint（golem-lint の `Golem.Lint`）
- ADR: [golem-lint ADR 0001](golem-lint/adr/0001-lint-rules.md)

### 主な原因

- `@label` で付けたラベルを、どこからも参照していない。

### 直し方

参照を書くか、ラベルを消す。

## G0602

plugins.lock にないプラグインです

- 重大度: エラー
- 状態: 使用中

### 意味

`manifest.toml` で宣言したプラグインの名前が `plugins.lock` にないか、`plugins.lock` の項目の `url` が宣言の `url` と違う。
`plugins.lock` がなければ、空の `plugins.lock` として扱う。
位置は `manifest.toml` の先頭である。

- メッセージ: `plugins.lock にないプラグインです。golem plugin lock を実行してください: <名前>`、`plugins.lock の URL が manifest.toml と違います。golem plugin lock を実行してください: <名前>`
- 段階とモジュール: プラグイン（golem-driver の `Golem.Driver.Plugins`）
- ADR: [golem-plugin ADR 0003](golem-plugin/adr/0003-plugin-diagnostic-codes.md)

### 主な原因

- `manifest.toml` にプラグインを足したが、`golem plugin lock` を実行していない。
- `manifest.toml` のプラグインの `url` を変えたが、`golem plugin lock` を実行していない。

### 直し方

`golem plugin lock` を実行して `plugins.lock` を作り直す。

## G0603

キャッシュにないプラグインです

- 重大度: エラー
- 状態: 使用中

### 意味

`plugins.lock` の項目のハッシュを名前とする配布物が、キャッシュにない。
ビルドはネットワークに接続しないので、自分では取得しない。
位置は `manifest.toml` の先頭である。

- メッセージ: `キャッシュにないプラグインです。golem plugin fetch を実行してください: <名前>`
- 段階とモジュール: プラグイン（golem-driver の `Golem.Driver.Plugins`）
- ADR: [golem-plugin ADR 0003](golem-plugin/adr/0003-plugin-diagnostic-codes.md)

### 主な原因

- `golem plugin fetch` を実行していない。

### 直し方

`golem plugin fetch` を実行する。

## G0604

キャッシュの配布物のハッシュが plugins.lock と一致しません

- 重大度: エラー
- 状態: 使用中

### 意味

キャッシュにある配布物の SHA-256 が、`plugins.lock` の項目のハッシュと一致しない。
位置は `manifest.toml` の先頭である。

- メッセージ: `キャッシュの配布物のハッシュが plugins.lock と一致しません: <名前>`
- 段階とモジュール: プラグイン（golem-driver の `Golem.Driver.Plugins`）
- ADR: [golem-plugin ADR 0003](golem-plugin/adr/0003-plugin-diagnostic-codes.md)

### 主な原因

- キャッシュが壊れた。
- 配布物が差し替えられた。

### 直し方

キャッシュを消して `golem plugin fetch` をやり直し、配布物を確かめる。

## G0605

プラグインを読み込めません

- 重大度: エラー
- 状態: 使用中

### 意味

配布物を wasm のモジュールとして読み込めない。
コンパイルの失敗、import の要求、ABI のバージョンの違い、必要な関数の欠け、起動の失敗、`golem_describe` の不正な出力を含む。
位置は `manifest.toml` の先頭である。
理由の文言は次のいずれかで、[G0609](#g0609) と共有する。
`プラグインを読み込めません: <詳細>`、`プラグインが import を要求しています: <import の一覧>`、`プラグインの ABI のバージョンが異なります: <バージョン>`、`プラグインが関数を公開していません: <関数>`、`プラグインの実行が命令数の上限を超えました`、`プラグインの実行が失敗しました（メモリの上限を超えた場合を含む）: <詳細>`、`プラグインを起動できません: <詳細>`（テーブルの要素の数の上限 100 万を超えるモジュールを含む）、`プラグインの出力が不正です: <詳細>`（`<関数名> の戻り値の型が不正です` を含む。[docs/adr/0035](adr/0035-security-hardening.md)）
`golem_describe` の応答は、コマンド、フィルタ、チャネルの三つの欄を持つ（[golem-doc ADR 0007](golem-doc/adr/0007-plugin-channel-lists.md)）。
二つの欄の応答は `golem_describe の形が不正です`、チャネルの宣言の形の誤りは `チャネルの宣言の形が不正です` になる。

- メッセージ: `<名前>: <理由>`
- 段階とモジュール: プラグイン（golem-driver の `Golem.Driver.Plugins`）
- ADR: [golem-plugin ADR 0003](golem-plugin/adr/0003-plugin-diagnostic-codes.md)

### 主な原因

- プラグインの wasm のモジュールが壊れているか、Golem の求める形でない。

### 直し方

理由の示す誤りを、プラグインの作者に報告する。

## G0606

複数のプラグインが同じコマンドを提供しています

- 重大度: エラー
- 状態: 使用中

### 意味

二つ以上のプラグインが、同じ名前のコマンドを提供している。
コマンドの名前ごとに一つ出し、提供するプラグインを名前の順に並べる。
位置は `manifest.toml` の先頭である。

- メッセージ: `複数のプラグインが同じコマンドを提供しています: <コマンド>（<プラグイン>、<プラグイン>）`
- 段階とモジュール: プラグイン（golem-driver の `Golem.Driver.Plugins`）
- ADR: [golem-plugin ADR 0003](golem-plugin/adr/0003-plugin-diagnostic-codes.md)

### 主な原因

- 二つ以上のプラグインが、同じ名前のコマンドを提供している。

### 直し方

どちらかのプラグインを外す。

## G0607

組み込みのコマンドと衝突しています

- 重大度: エラー
- 状態: 使用中

### 意味

プラグインが組み込みのコマンドと同じ名前のコマンドを提供し、そのプラグインの `overrides` にその名前がない。
組み込みのコマンドが上書きできるものなら一つ目の文言、上書きできないもの（`note` など）なら二つ目の文言になる。
位置は `manifest.toml` の先頭である。

- メッセージ: `組み込みのコマンドと衝突しています（overrides で宣言してください）: <プラグイン>.<コマンド>`、`上書きできない組み込みのコマンドと衝突しています: <プラグイン>.<コマンド>`
- 段階とモジュール: プラグイン（golem-driver の `Golem.Driver.Plugins`）
- ADR: [golem-plugin ADR 0003](golem-plugin/adr/0003-plugin-diagnostic-codes.md)

### 主な原因

- プラグインのコマンドが組み込みのコマンドと同じ名前で、上書きを宣言していない。
- プラグインが、上書きできない組み込みのコマンドと同じ名前のコマンドを提供している。

### 直し方

上書きできるコマンドを上書きするなら、`manifest.toml` のプラグインの `overrides` にコマンドを書く。
上書きできないコマンドと衝突するなら、そのプラグインを外す。

## G0608

overrides に書けない名前です

- 重大度: エラー
- 状態: 使用中

### 意味

プラグインの `overrides` に、そのプラグインが提供していないコマンドか、上書きできる組み込みのコマンドでない名前がある。
`overrides` の一つの名前について、高々一つ出す。
提供していなければ一つ目の文言、提供していても上書きできる組み込みのコマンドでなければ（組み込みでない名前か、上書きできない組み込みのコマンド）二つ目の文言になる。
位置は `manifest.toml` の先頭である。

- メッセージ: `プラグインが提供していないコマンドを overrides に書いています: <プラグイン>.<コマンド>`、`上書きできる組み込みのコマンドではありません: <プラグイン>.<コマンド>`
- 段階とモジュール: プラグイン（golem-driver の `Golem.Driver.Plugins`）
- ADR: [golem-plugin ADR 0003](golem-plugin/adr/0003-plugin-diagnostic-codes.md)

### 主な原因

- `overrides` に、そのプラグインが提供していないコマンドを書いた。
- `overrides` に、組み込みでない名前か、上書きできない組み込みのコマンドを書いた。

### 直し方

`overrides` からその名前を外す。

## G0609

プラグインの実行が失敗しました

- 重大度: エラー
- 状態: 使用中

### 意味

プラグインのコマンドかフィルタの実行が失敗した。
命令数の上限、メモリの上限を含むトラップ、不正な出力を含む。
位置は、コマンドならコマンドを呼んだ箇所、フィルタならフィルタを適用したファイルの先頭である。
理由の文言は [G0605](#g0605) と同じである。
チャネルの項目（[golem-doc ADR 0007](golem-doc/adr/0007-plugin-channel-lists.md)）の不正な出力の詳細は、`宣言していないチャネルです: <チャネル>`、`読みの順のチャネルの項目には読みが要ります: <チャネル>`、`チャネルの項目の本文に置けない要素があります` である。

- メッセージ: `<プラグイン>.<コマンド>: <理由>`、`<プラグイン>.<フィルタ>: <理由>`
- 段階とモジュール: プラグイン（golem-driver の `Golem.Driver.Plugins`）
- ADR: [golem-plugin ADR 0003](golem-plugin/adr/0003-plugin-diagnostic-codes.md)

### 主な原因

- プラグインのコマンドかフィルタが、命令数の上限かメモリの上限に達した。
- プラグインの中で誤りが起きたか、プラグインが不正な出力を返した。

### 直し方

理由の示す誤りを確かめる。
プラグインの誤りなら作者に報告する。

## G0610

フィルタの設定が不正です

- 重大度: エラー
- 状態: 使用中

### 意味

`[[filters]]` の項目が、宣言されていないプラグインか、宣言したプラグインが提供していないフィルタを指す。
位置は `manifest.toml` の先頭である。

- メッセージ: `宣言されていないプラグインです: <プラグイン>（フィルタ <プラグイン>.<フィルタ>）`、`プラグインが提供していないフィルタです: <プラグイン>.<フィルタ>`
- 段階とモジュール: プラグイン（golem-driver の `Golem.Driver.Plugins`）
- ADR: [golem-plugin ADR 0003](golem-plugin/adr/0003-plugin-diagnostic-codes.md)

### 主な原因

- `[[filters]]` の項目が、宣言されていないプラグインを指す。
- `[[filters]]` の項目が、プラグインが提供していないフィルタを指す。

### 直し方

プラグインを宣言するか、`[[filters]]` の項目のプラグインとフィルタの名前を直す。

## G0611

plugins.lock を読めません

- 重大度: エラー
- 状態: 使用中

### 意味

`plugins.lock` が TOML として読めないか、項目の形（`url` と `sha256` の文字列）に合わない。
`sha256` は 64 文字の小文字の 16 進数でなければならない（キャッシュのファイルの名前になるので、パスを書けない）。
位置は、`plugins.lock` の中の誤りの位置である。

- メッセージ: `TOML の誤りです: <詳細>`、または TOML のスキーマの誤りの文言（`知らないキーです: plugins.<名前>.<キー>`、`必須のキーがありません: plugins.<名前>.sha256`、`plugins.<名前>.url には文字列を書きます（整数が書かれています）` など）、`plugins.<名前>.sha256 は 64 文字の小文字の 16 進数で書きます`（[docs/adr/0035](adr/0035-security-hardening.md)。位置は `plugins.lock` の先頭）
- 段階とモジュール: プラグイン（golem-plugin の `Golem.Plugin.Lock`、golem-driver の `Golem.Driver.Plugins`、`golem plugin fetch`）
- ADR: [golem-plugin ADR 0003](golem-plugin/adr/0003-plugin-diagnostic-codes.md)。[golem-project ADR 0007](golem-project/adr/0007-toml-messages-in-japanese.md) が TOML の誤りの文言を日本語にした

### 主な原因

- `plugins.lock` を手で編集した。
- `plugins.lock` のマージで衝突が残った。

### 直し方

`plugins.lock` は処理系が書くファイルなので、手で直さない。
`plugins.lock` を消して `golem plugin lock` を実行する。


## G0612

チャネルの宣言が誤っています

- 重大度: エラー
- 状態: 使用中

### 意味

二つのプラグインが同じ名前のチャネルを宣言したか、プラグインが予約した名前か形の誤った名前のチャネルを宣言した。
名前は英小文字で始まり、英小文字、数字、`-` だけからなる。
`toc`、`index`、`bibliography`、`note`、`notes`、`sidenote`、`cite` は予約した名前である。
位置は `manifest.toml` の先頭である。

- メッセージ: `複数のプラグインが同じチャネルを宣言しています: <チャネル>（<プラグイン>、<プラグイン>）`、`<プラグイン>: このチャネルの名前は使えません: <チャネル>`
- 段階とモジュール: プラグイン（golem-driver の `Golem.Driver.Plugins`）
- ADR: [golem-doc ADR 0007](golem-doc/adr/0007-plugin-channel-lists.md)

### 主な原因

- 同じチャネルを宣言する二つのプラグインを、同じ本で使っている。
- プラグインが、使えない名前のチャネルを宣言している。

### 直し方

どちらかのプラグインを外すか、プラグインの作者に報告する。
## G0701

版面を計算できません

- 重大度: エラー
- 状態: 使用中

### 意味

`style.toml` の版面の設定から、PDF の版面を計算できない。
次の順に検査し、最初に当てはまったものを一つだけ報告する。

1. `[page]` がない（`style.toml` がない場合を含む）。
2. `[page.grid]` がない。
3. `[page.grid]` の `font-size` が正の絶対的な寸法でない。
4. 字数か行数か段数が 0 以下か、行送りが文字の大きさより小さい。
5. 版面が判型からはみ出す。
6. 縦組みの版面に `[sidenotes]` がある。
7. 段組みの版面に `[sidenotes]` がある。
8. 傍注欄が判型からはみ出す。
9. `[notes.rule]` の `length` が行長（段組みでは段の行長）より長い。
10. 段落スタイル（名前の順）と見出し（階層の順）の罫線が、仕上がりの線を超えるか、段組みの版面で段間の半分を超える（[golem-driver ADR 0027](golem-driver/adr/0027-paragraph-style-rules.md)）。行の方向では、`start-indent`、`end-indent`、`length` で段の外に出る量を、左右（縦組みでは天地）の余白と比べる。行に直交する方向では、`keep-in-column = false` の罫線の内側の間隔と太さを、天地（縦組みでは左右）の余白と比べる。余白は奇数ページと偶数ページの狭いほうである。段間の半分と比べるのは行の方向だけで、行に直交する方向の罫線は段間と比べない（[golem-driver ADR 0040](golem-driver/adr/0040-rules-outside-column-only-at-type-area-edge.md)）。

PDF をターゲットに含むときは、ビルドと `golem check` の両方で、レイアウトの前に報告する。
PDF を書かない。
LSP は出さない。
位置は `style.toml` の先頭で、`style.toml` がなければ `manifest.toml` の先頭である。
未知の判型は [G0317](#g0317)、マスターページの未知の位置は [G0318](#g0318) である。

- メッセージ: `style.toml に [page] がないため、版面を計算できません`、`style.toml に [page.grid] がないため、版面を計算できません`、`文字の大きさは絶対的な寸法で書いてください`、`字数、行数、段数は 1 以上、行送りは文字の大きさ以上にしてください`、`版面がページからはみ出しています`、`縦組みの版面には傍注欄を設けられません`、`段組みの版面には傍注欄を設けられません`、`版面と傍注欄の合計がページからはみ出しています`、`脚注の区切り線の length が行長を超えます`、`段落スタイル <名前> の罫線が仕上がりの線を超えます`、`段落スタイル <名前> の罫線が段間の半分を超えます`、`見出し <階層> の罫線が仕上がりの線を超えます`、`見出し <階層> の罫線が段間の半分を超えます`
- 段階とモジュール: レイアウト（golem-layout-spec の `Golem.LayoutSpec`、golem-driver の `Golem.Driver`）
- ADR: [golem-driver ADR 0016](golem-driver/adr/0016-output-and-layout-diagnostic-codes.md)（[golem-cli ADR 0003](golem-cli/adr/0003-new-project-page-and-fonts.md)、[golem-driver ADR 0006](golem-driver/adr/0006-pdf-sidenotes.md)、[golem-driver ADR 0011](golem-driver/adr/0011-sidenote-font.md)、[golem-pdf ADR 0004](golem-pdf/adr/0004-crop-marks-and-bleed.md)、[docs/adr/0018](adr/0018-multi-column-layout.md)、[golem-driver ADR 0024](golem-driver/adr/0024-rule-spec-and-footnote-separator.md)、[golem-driver ADR 0027](golem-driver/adr/0027-paragraph-style-rules.md)、[golem-driver ADR 0040](golem-driver/adr/0040-rules-outside-column-only-at-type-area-edge.md) も触れる）

### 主な原因

- `style.toml` に `[page]` か `[page.grid]` がない。
- 文字の大きさを絶対的な寸法で書いていない。
- 字数、行数、段数が 0 以下か、行送りが文字の大きさより小さい。
- 版面か傍注欄が判型からはみ出している。
- 縦組みの版面に傍注欄を設けた。
- `[page.grid]` の `columns` が 2 以上の版面に傍注欄（`[sidenotes]`）を設けた。
- 脚注の区切り線（`[notes.rule]`）の `length` が、一行の長さ（段組みでは一段の行長）より長い。
- 段落スタイルか見出しの罫線を、`start-indent`、`end-indent`、`length` で、余白の幅か段間の半分を超えて段の外に出した。
- 段落スタイルか見出しの罫線を、`keep-in-column = false` で、天地（縦組みでは左右）の余白を超えて段の外に出した。この罫線は余白とだけ比べ、段間の半分とは比べない（[golem-driver ADR 0040](golem-driver/adr/0040-rules-outside-column-only-at-type-area-edge.md)）。

### 直し方

`[page]` と `[page.grid]` を書き、字数、行数、文字の大きさ、余白を判型に収まる値にする。
区切り線の `length` は行長以下にする。
段落と見出しの罫線は、段の外に出す量を余白の幅と段間の半分以下にする。

## G0702

日本式のトンボには塗り足しが要ります

- 重大度: エラー
- 状態: 使用中

### 意味

`--marks japanese` で PDF を作るか検査するときに、`[page]` の `bleed` が 0 である。
PDF をターゲットに含まないビルドと LSP では出さない。
`golem check` は四つのターゲットを検査するので、マニフェストのターゲットによらず出す。

- メッセージ: `日本式のトンボには塗り足しが要ります。style.toml の [page] に bleed を書いてください`
- 段階とモジュール: レイアウト（golem-driver の `Golem.Driver`）
- ADR: [golem-pdf ADR 0004](golem-pdf/adr/0004-crop-marks-and-bleed.md)、[golem-pdf ADR 0010](golem-pdf/adr/0010-golem-check-g0702-and-template-bleed.md)

### 主な原因

- `--marks japanese` で PDF を作ったが、`[page]` の `bleed` が 0 である。

### 直し方

`[page]` に `bleed = "3mm"` のように塗り足しを書く。

## G0721

ページ番号の参照が収束しません

- 重大度: エラー
- 状態: 使用中

### 意味

ページ番号の参照（`ref-page`、索引）を解決するためにレイアウトを繰り返したが、上限の 5 回までに収束しなかった。
メッセージは、最後の二回のレイアウトでページの変わったラベルを名前の順に並べ、続けて、ページの変わった索引の印の語を印の位置の順に並べる。
目次のページ番号は繰り返しの外で決めるので、見出しは並ばない。
繰り返しの途中のレイアウトがほかのエラーを出した場合は、そのエラーを報告し、このコードは出さない。
PDF を書かない。
位置は並びの最初のもの（ラベルならそのラベルを付けたブロック、索引の語ならその印）で、二つ目以降のものの位置を関連情報に `ページが定まりません` として載せる。

- メッセージ: `ページ番号の参照が収束しません: <ラベルと索引の語>`
- 段階とモジュール: レイアウト（golem-driver の `Golem.Driver.Pdf`）
- ADR: [golem-driver ADR 0016](golem-driver/adr/0016-output-and-layout-diagnostic-codes.md)（[golem-driver ADR 0007](golem-driver/adr/0007-pdf-index-and-bibliography.md) がメッセージに索引の語を加えた。[golem-driver ADR 0009](golem-driver/adr/0009-pdf-toc-page-numbers.md) も触れる）

### 主な原因

- 参照の解決でページ番号の文字列が変わると組版が変わり、それがまたページ番号を変える。

### 直し方

メッセージの示す参照の位置か、その付近の文言を変える。

## G0722

回り込む図版の幅が不正です

- 重大度: エラー
- 状態: 使用中

### 意味

回り込む図版の `width` が寸法として読めないか、図版の脇の行の長さが本文の文字の大きさの 8 字分に満たない。

- メッセージ: `回り込む図版の幅が不正です。寸法で書き、行の残りを本文の 8 字分以上にしてください: <幅>`
- 段階とモジュール: レイアウト（golem-driver の `Golem.Driver.Pdf`）
- ADR: [golem-driver ADR 0005](golem-driver/adr/0005-pdf-wrapped-figures.md)

### 主な原因

- 回り込む図版の `width` を寸法として書いていない。
- 図版が広く、脇の行の長さが本文の文字の大きさの 8 字分に満たない。

### 直し方

`width` を寸法で書き、版面の行長より 8 字分以上小さくする。

## G0723

回り込む図版が一ページに収まりません

- 重大度: エラー
- 状態: 使用中

### 意味

回り込む図版とキャプションの占める行数が、一ページの行数を超える。

- メッセージ: `回り込む図版の除外領域が一ページの行数を超えます（<行数> 行）`
- 段階とモジュール: レイアウト（golem-driver の `Golem.Driver.Pdf`）
- ADR: [golem-driver ADR 0005](golem-driver/adr/0005-pdf-wrapped-figures.md)

### 主な原因

- 回り込む図版とキャプションの占める行数が、一ページの行数を超える。

### 直し方

図版を小さくするか、キャプションを短くする。

## G0724

見出しが版面に入りません

- 重大度: エラー
- 状態: 使用中

### 意味

見出しの占める行数が、一ページの行数を超える。
見出しはページをまたいで分けない。

- メッセージ: `見出しが版面に入りません（<階層> の見出し: <題>）`
- 段階とモジュール: レイアウト（golem-driver の `Golem.Driver.Pdf`）
- ADR: [golem-driver ADR 0003](golem-driver/adr/0003-pdf-heading-styles.md)

### 主な原因

- 見出しが長いか、文字が大きく、占める行数が一ページの行数を超える。見出しはページをまたいで分けない。

### 直し方

見出しを短くするか、`[headings.<階層>]` の文字の大きさを小さくする。

## G0725

段落スタイルの字下げが大きすぎます

- 重大度: エラー
- 状態: 使用中

### 意味

`style.toml` か原稿のファイルが定める段落スタイルについて、版面の段の行長から `indent` と `first-line-indent`（負なら 0）を引いた値が、その段落スタイルの文字の大きさの 8 字分に満たない。
PDF をターゲットに含むときは、ビルドと `golem check` の両方で、レイアウトの前に報告する。
PDF を書かない。
LSP は出さない。
位置は `style.toml` の先頭で、`style.toml` がなければ `manifest.toml` の先頭である。
回り込む図版の脇で行が残らない場合は [G0728](#g0728) である。

- メッセージ: `段落スタイルの字下げが大きすぎます。行長を段落の文字の大きさの 8 字分以上残してください: <名前>`
- 段階とモジュール: レイアウト（golem-driver の `Golem.Driver`、`Golem.Driver.Pdf`）
- ADR: [docs/adr/0006](adr/0006-paragraph-indent.md)、[golem-driver ADR 0016](golem-driver/adr/0016-output-and-layout-diagnostic-codes.md)

### 主な原因

- 段落スタイルの `indent` と `first-line-indent` が大きく、行長が段落の文字の大きさの 8 字分に満たない。
- 版面の一行の字数が少ない。

### 直し方

段落スタイルの `indent` と `first-line-indent` を小さくするか、`[page.grid]` の `characters` を増やす。

## G0726

段組みの版面では図版を回り込ませられません

- 重大度: エラー
- 状態: 使用中

### 意味

`[page.grid]` の `columns` が 2 以上の版面で、図版に `wrap` を指定した。
段組みの版面での回り込みの形は決まっていないので、黙って一段組みの形で組まずに止める。

- メッセージ: `段組みの版面では図版を回り込ませられません。wrap を外すか、columns を 1 にしてください`
- 段階とモジュール: レイアウト（golem-driver の `Golem.Driver.Pdf`）
- ADR: [docs/adr/0018](adr/0018-multi-column-layout.md)

### 主な原因

- 2 段以上の版面の原稿に、`wrap=start` か `wrap=end` の図版がある。
- 一段組みで書いた原稿の版面を、後から段組みにした。

### 直し方

図版の `wrap` を外す。
回り込みが要るなら、`style.toml` の `columns` を 1 にする。

## G0727

リストの入れ子が深く、項目の本文の行長が足りません

- 重大度: エラー
- 状態: 使用中

### 意味

PDF で、入れ子のリストの字下げの後に残る項目の本文の行長が、版面の文字の大きさの 8 字分に満たない。
または、回り込む図版の脇で、リストの字下げを引いた行の長さが 0 以下になる。
位置はその項目の段落である。

- メッセージ: `リストの入れ子が深く、項目の本文の行長が足りません。行長を本文の文字の大きさの 8 字分以上残してください`
- 段階とモジュール: レイアウト（golem-driver の `Golem.Driver.Pdf`）
- ADR: [golem-driver ADR 0013](golem-driver/adr/0013-list-indents.md)

### 主な原因

- リストの入れ子が深く、各段の印の幅の和が行長の大部分を占める。
- 版面の一行の字数が少ない。
- 回り込む図版の脇にリストを置いた。

### 直し方

リストの入れ子を浅くする。
印の幅を狭くするために、`[lists]` の `bullets` と `numbers` に短い印を書くか、`gap` を小さくする。

## G0728

回り込む図版の脇で、字下げを引くと行が残りません

- 重大度: エラー
- 状態: 使用中

### 意味

PDF で、回り込む図版の脇の段落に、図版の脇の行の長さから字下げを引いた値が 0 以下になる行がある。
段落一つにつき一つ報告し、位置はその段落である。
リストの項目の段落では、代わりに [G0727](#g0727) を報告する。

- メッセージ: `回り込む図版の脇で、字下げを引くと行が残りません`
- 段階とモジュール: レイアウト（golem-driver の `Golem.Driver.Pdf`）
- ADR: [golem-driver ADR 0016](golem-driver/adr/0016-output-and-layout-diagnostic-codes.md)

### 主な原因

- 回り込む図版が広く、脇の行の長さが段落の字下げより短い。

### 直し方

図版の `width` を小さくするか、その段落の字下げを小さくする。

## G0729

リストの番号を書式で表せません

- 重大度: エラー
- 状態: 使用中

### 意味

番号付きリストの項目の番号を、その深さの `[lists]` の `numbers` の書式で表せない。
丸数字は 1 から 50 まで、ローマ数字は 1 から 3999 まで、ラテン文字は 1 から、片仮名はアイウエオ順で 46 まで、イロハ順で 47 までを表せる。
PDF、HTML、EPUB、プレーンテキストのどれを組んでも報告し、どれも書かない。
位置はその項目の最初のブロックであり、ブロックのない項目ではそのリストである。

- メッセージ: `リストの番号 <番号> は、書式 <書式> で表せません`
- 段階とモジュール: 出力（golem-driver の `Golem.Driver`、`Golem.Driver.Pdf`）
- ADR: [golem-driver ADR 0013](golem-driver/adr/0013-list-indents.md)

### 主な原因

- 丸数字や片仮名の書式のリストの項目が多すぎる。
- `@number` で 0 や大きすぎる番号を指定した。

### 直し方

項目を減らすか、`@number` を直すか、その深さの書式を算用数字（`{n}` や `{1}`）などの表せる書式に替える。

## G0730

コードの行を折り返しました

- 重大度: お知らせ
- 状態: 使用中

### 意味

PDF のコードブロックに、行長から左右の `padding` を引いた幅に収まらない行があり、シェイピングのクラスタの境界で折り返した。
折り返した続きの行は、元の行の行頭の空白とタブの幅に空白の送りの 2 倍を足した位置から始まる。
折り返した印は描かない。
コードブロックごとに一つ出し、位置はコードブロックの始まりである。
PDF は書く。
お知らせなので、エラーにも警告にもならず、ビルドの成否に影響しない（[golem-syntax ADR 0002](golem-syntax/adr/0002-notice-severity.md)）。

- メッセージ: `コードの行を折り返しました（<n> 行）`。`<n>` は折り返した元の行の数
- 段階とモジュール: レイアウト（golem-driver の `Golem.Driver.Pdf`、golem-layout の `Golem.Layout.Code`）
- ADR: [golem-driver ADR 0017](golem-driver/adr/0017-pdf-code-blocks.md)

### 主な原因

- コードの行が版面の行長より長い。
- `@listing` で取り込んだファイルの行が長い。

### 直し方

行を短く書き直すか、`[paragraph-styles.code]` の `size` か `padding` を小さくする。
`@listing` で取り込むファイルの行を直せない場合は、折り返しを受け入れてよい。
`manifest.toml` の `[diagnostics]` の `silence-notices` に `"G0730"` を加えると、このお知らせを出さなくなる。


## G0732

縦組みの版面では傍注を使えません

- 重大度: エラー
- 状態: 使用中

### 意味

縦組みの版面で傍注を使った。
縦組みでは傍注欄を設けない。
段落、見出し、リストの項目、定義リスト、表のセル、図版のキャプションの傍注と、圏点、色、文字スタイル、脚注の本文の中の傍注を、一つにつき一つ報告する。
縦組みのときは、[G0734](#g0734) と [G0735](#g0735) を出さない。
PDF を書かない。
位置は傍注の位置である。

- メッセージ: `縦組みの版面では傍注を使えません。脚注に替えてください`
- 段階とモジュール: レイアウト（golem-layout の `Golem.Layout.Japanese`、golem-driver の `Golem.Driver.Pdf`）
- ADR: [golem-driver ADR 0016](golem-driver/adr/0016-output-and-layout-diagnostic-codes.md)（[golem-layout ADR 0006](golem-layout/adr/0006-sidenotes.md) と [golem-driver ADR 0006](golem-driver/adr/0006-pdf-sidenotes.md) が条件を定めた）

### 主な原因

- 縦組みの版面で傍注を使った。縦組みでは傍注欄を設けない。

### 直し方

傍注を脚注（`[note: ...]`）に替える。

## G0733

傍注が傍注欄に収まりません

- 重大度: エラー
- 状態: 使用中

### 意味

一つの傍注が傍注欄より高いか、一ページの傍注を上に詰めても傍注欄に収まらない。
ページごとに最初の一つだけを報告する。

- メッセージ: `傍注が傍注欄より高く、収まりません`、`このページの傍注が傍注欄に収まりません`
- 段階とモジュール: レイアウト（golem-driver の `Golem.Driver.Pdf`）
- ADR: [golem-driver ADR 0006](golem-driver/adr/0006-pdf-sidenotes.md)

### 主な原因

- 一つの傍注が傍注欄より高い。
- 一ページの傍注が多く、上に詰めても傍注欄に収まらない。

### 直し方

傍注を短くするか、ページの傍注を減らす。

## G0734

傍注欄のない版面では傍注を使えません

- 重大度: エラー
- 状態: 使用中

### 意味

`[sidenotes]` のない横組みの版面で傍注を使った。

- メッセージ: `傍注欄（style.toml の [sidenotes]）のない版面では傍注を使えません`
- 段階とモジュール: レイアウト（golem-driver の `Golem.Driver.Pdf`）
- ADR: [golem-driver ADR 0006](golem-driver/adr/0006-pdf-sidenotes.md)

### 主な原因

- `[sidenotes]` のない横組みの版面で傍注を使った。

### 直し方

`style.toml` に `[sidenotes]` を書くか、傍注を脚注に替える。

## G0735

脚注の本文と図版のキャプションの中に傍注を置けません

- 重大度: エラー
- 状態: 使用中

### 意味

脚注の本文か図版のキャプションの中に傍注を置いた。
これらの行は本文の流れの外にあるので、傍注の高さを決められない。

- メッセージ: `PDF では、脚注の本文と図版のキャプションの中に傍注を置けません`
- 段階とモジュール: レイアウト（golem-driver の `Golem.Driver.Pdf`）
- ADR: [golem-driver ADR 0006](golem-driver/adr/0006-pdf-sidenotes.md)

### 主な原因

- 脚注の本文か図版のキャプションの中に傍注を書いた。これらの行は本文の流れの外にあるので、傍注の高さを決められない。

### 直し方

傍注を本文の段落に移す。

## G0737

改ページの手での制御を守れませんでした

- 重大度: 警告
- 状態: 使用中

### 意味

PDF の改ページで、`@no-page-break`、`@need-lines`、`@page-lines` の指定を守れなかった。
指定が守れなくても PDF は組める。
位置は、守れなかったコマンドである。

- `@no-page-break`：前のブロックの最後の部分と、後のブロックの最初の部分を、同じ段に置けなかった。本の先頭か末尾に書いた場合、前のブロックが次の段に送られた図版の場合、二つを合わせると段に入らない場合に起きる。
- `@need-lines`：求めた行数が、段の行の格子の数を超える。段の格子の数として扱い、今の段が空でなければ次の段から続けた。
- `@page-lines`：増減の結果の行数が、裁ち落としを除いたページの内側に収まる行数を超えるか、その段にすでに置いた行の数より少ない。収まる数に切り詰めた。

- メッセージ: `ここで改ページを止められませんでした`、`@need-lines <N> は段の行数 <M> を超えます`、`@page-lines の増減を <K> 行に切り詰めました`
- 段階とモジュール: レイアウト（golem-driver の `Golem.Driver.Pdf`、golem-layout の `Golem.Layout.Paginate`）
- ADR: [docs/adr/0030](adr/0030-manual-page-break-control.md)

### 主な原因

- 長い段落の後に `@no-page-break` を書き、後の段落と合わせて段に入らない。
- 版面の下の余白が狭いページで `@page-lines +1` を書いた。

### 直し方

組んだ PDF を見て、指定の位置か量を直すか、指定を消す。

## G0738

図版のキャプションが段に収まりません

- 重大度: エラー
- 状態: 使用中

### 意味

回り込ませない図版のキャプションが占める格子の行の数が、段の行の数に達し、画像を置く行が残らない。
`rotate=true` の図版では、回した図版を組む枠の行の数に達した場合である。
位置は `@figure` のブロックである。
dev と prod の両方でエラーになる。

- メッセージ: `図版のキャプションが段の行数を超えます（<s> 行。段は <L> 行）`、`図版のキャプションがページの行数を超えます（<s> 行。ページは <L> 行）`。`<s>` はキャプションが占める格子の行の数、`<L>` は段か枠の行の数
- 段階とモジュール: レイアウト（golem-driver の `Golem.Driver.Pdf`）
- ADR: [golem-driver ADR 0034](golem-driver/adr/0034-fit-figures-to-column.md)

### 主な原因

- キャプションが長い。
- `style.toml` の `[page.grid]` の `lines` が少ない。
- `rotate=true` の図版で、版面の幅（縦組みでは高さ）が狭い。

### 直し方

キャプションを短くするか、段の行の数を増やす。
回した図版では、回さずに置くことも考える。

## G0739

図版を段に収めるため縮めました

- 重大度: お知らせ
- 状態: 使用中

### 意味

回り込ませない図版を行長にそろえると、段の行の送りの方向の長さを超えるので、縦横の比を保って縮めた。
縮めた図版は、行の方向に余りができ、仕上がりの紙の端に近いほうの段の端に寄せた。
`rotate=true` の図版では、回した図版を組む枠に収めるために縮めた。
図版ごとに一つ出し、位置は `@figure` のブロックである。
PDF は書く。
お知らせなので、エラーにも警告にもならず、ビルドの成否に影響しない（[golem-syntax ADR 0002](golem-syntax/adr/0002-notice-severity.md)）。

- メッセージ: `図版を段に収めるため <r>% に縮めました`、回した図版では `図版をページに収めるため <r>% に縮めました`。`<r>` は縮めた後の行の方向の長さを行長で割った百分率の切り捨て。回さずに置いた図版が、回せばより大きく置ける場合は、`。rotate=true で回して一ページに置くと、より大きく置けます` が続く
- 段階とモジュール: レイアウト（golem-driver の `Golem.Driver.Pdf`）
- ADR: [golem-driver ADR 0034](golem-driver/adr/0034-fit-figures-to-column.md)

### 主な原因

- 縦組みの版面に、横長の図版を置いた。
- 横組みの版面に、縦長の図版を置いた。
- キャプションが長く、画像を置ける行が少ない。

### 直し方

縮めてよい図版なら、そのままでよい。
大きく置きたい図版は、図版の縦横の比を変えて作り直すか、`rotate=true` を書いて回して一ページに置く。
`manifest.toml` の `[diagnostics]` の `silence-notices` に `"G0739"` を加えると、このお知らせを出さなくなる。
抑制は本の全体の単位であり、図版ごとには抑制できない。

## G0741

表の列が版面の行長に収まりません

- 重大度: エラー
- 状態: 使用中

### 意味

表の各列の最小の幅（改行できる位置のあいだの最も広い部分）の合計が、版面の行長を超える。
セルの最後の二つの和文の字は、一つの区間として数える（[golem-driver ADR 0037](golem-driver/adr/0037-table-column-widths.md)）。

- メッセージ: `表の列の最小の幅の合計（<幅> mm）が使える幅（<幅> mm）に収まりません`
- 段階とモジュール: レイアウト（golem-driver の `Golem.Driver.Pdf`）
- ADR: [golem-driver ADR 0008](golem-driver/adr/0008-pdf-tables.md)、[golem-driver ADR 0037](golem-driver/adr/0037-table-column-widths.md)

### 主な原因

- 表の列が多い。
- 改行できる位置のない長い語が列の最小の幅を広げている。

### 直し方

列を減らすか、長い語に改行できる位置を作る。

## G0742

表の行が一ページに収まりません

- 重大度: エラー
- 状態: 使用中

### 意味

表の見出しの行とある本体の行の高さの和が、一ページの行数を超える。
表の行の途中では改ページしない。

- メッセージ: `表の <番号> 行目が見出しの行とともに一ページに収まりません`
- 段階とモジュール: レイアウト（golem-driver の `Golem.Driver.Pdf`）
- ADR: [golem-driver ADR 0008](golem-driver/adr/0008-pdf-tables.md)

### 主な原因

- 表の見出しの行とある本体の行の高さの和が、一ページの行数を超える。表の行の途中では改ページしない。

### 直し方

その行のセルの文を短くするか、列の幅が広がるように表を組み直す。

## G0743

コードブロックの行長が足りません

- 重大度: エラー
- 状態: 使用中

### 意味

PDF のコードブロックについて、行長から左右の `padding` を引いた幅が、コードの文字の大きさの 8 字分に満たないか、コードの一行と上下の `padding` が一ページの行数に収まらない。
行番号、差分の印、`[code]` の `wrap-mark` を付けたコードブロックでは、それらの列と空きと印の幅も行長から引く。
`[code]` の `continued` を書いた本では、コードの一行、続きの表示の行、上下の `padding` が一ページに収まらない場合も、この誤りとする（[golem-driver ADR 0023](golem-driver/adr/0023-code-block-book-features.md)）。
`style.toml` とファイルの中の定義だけで決まる最上位のコードブロックの行長の不足は、PDF をターゲットに含むときに、ビルドと `golem check` の両方でレイアウトの前に報告し、位置は `style.toml` の先頭（なければ `manifest.toml` の先頭）である。
リストの深い入れ子の中の行長の不足と、一ページに収まらない場合は、レイアウトで報告し、位置はコードブロックの始まりである。
PDF を書かない。

- メッセージ: `コードブロックの行長が足りません` または `コードブロックの一行が一ページに収まりません`
- 段階とモジュール: レイアウト（golem-driver の `Golem.Driver.Pdf`）
- ADR: [golem-driver ADR 0017](golem-driver/adr/0017-pdf-code-blocks.md)

### 主な原因

- `[paragraph-styles.code]` の `padding` が大きい。
- コードブロックをリストの深い入れ子の中に置いた。
- 行番号の桁が多いか、行番号と差分の印と `wrap-mark` を合わせた幅が大きい。
- 版面の行数が少なく、コードの文字の大きさと `padding` が大きい。

### 直し方

`padding` か `size` を小さくするか、コードブロックをリストの浅いところに移す。
## G0744

索引の段の行長が足りません

- 重大度: エラー
- 状態: 使用中

### 意味

`style.toml` の `[index]` の `columns` が版面の段数と異なり、索引の段の行長（版面の文字の領域の幅を `columns` の段と `column-gap` の段間に分けた値）が、版面の文字の大きさの 8 字分に満たない。
`style.toml` だけで決まるので、PDF をターゲットに含むときは、ビルドと `golem check` の両方で、レイアウトの前に報告する。
PDF を書かない。
位置は `[index]` の `columns` の値である。

- メッセージ: `索引の段の行長が足りません。columns を減らすか column-gap を狭めてください`
- 段階とモジュール: レイアウト（golem-driver の `Golem.Driver`、`Golem.Driver.Pdf`）
- ADR: [docs/adr/0025](adr/0025-index-columns.md)

### 主な原因

- 版面の一行の字数に対して、`[index]` の `columns` が多い。
- `column-gap` が広い。

### 直し方

`[index]` の `columns` を減らすか、`column-gap` を狭める。

## G0745

ルビの親文字の圏点を PDF で描きません

- 重大度: お知らせ
- 状態: 使用中

### 意味

ルビの親文字の中に圏点があるか、圏点の中にルビがある。
圏点とルビは親文字の同じ側に置くので、PDF は、ルビの親文字に圏点を描かない。
HTML と EPUB は圏点とルビの両方を出すので、PDF をターゲットに含むときだけ出す。
PDF は書く。
位置は、ルビの親文字の中の圏点ではその圏点の位置、圏点の中のルビではそのルビの位置である。
お知らせなので、エラーにも警告にもならず、ビルドの成否に影響しない（[golem-syntax ADR 0002](golem-syntax/adr/0002-notice-severity.md)）。

- メッセージ: `ルビの親文字の圏点は PDF では描きません`
- 段階とモジュール: 出力（golem-driver の `Golem.Driver`、`Golem.Driver.Pdf`）
- ADR: [golem-driver ADR 0019](golem-driver/adr/0019-pdf-kenten-shapes.md)

### 主な原因

- `[ruby: [kenten: 漢]|かん]` のように、ルビの親文字に圏点を付けた。
- `[kenten: [ruby: 漢|かん]]` のように、圏点の中にルビを書いた。

### 直し方

PDF で圏点を描くには、圏点を付ける語からルビを外す。
PDF で圏点がなくてよければ、そのままでよい。
`manifest.toml` の `[diagnostics]` の `silence-notices` に `"G0745"` を加えると、このお知らせを出さなくなる。

## G0746

罫線を持つ段落か見出しが版面に入りません

- 重大度: お知らせ
- 状態: 使用中

### 意味

罫線を持つ段落か見出し（段落スタイルか `[headings.N]` の `rule-before`、`rule-after`）が、前の罫線の領域、行、後の罫線の領域を合わせて、空の段にも入らない。
罫線を持つ段落は、罫線を持たない段落と同じく、孤立行と泣き別れの規則で行を段に分けて組む。
分けて組んだ段落には、前の罫線も後の罫線も引かず、罫線の領域の行も取らない（[golem-driver ADR 0035](golem-driver/adr/0035-paragraph-rules-split-and-space-units.md)）。
後の罫線の領域が最後の部分の後に入る場合も引かない。
罫線を持つ見出しは、行を分けず、後の罫線を省き、それでも入らなければ前の罫線も省く。
PDF は書く。
見出しの行だけで空の段に入らない場合は、[G0724](#g0724) である。
位置は、段落か見出しの位置である。
お知らせなので、エラーにも警告にもならず、ビルドの成否に影響しない（[golem-syntax ADR 0002](golem-syntax/adr/0002-notice-severity.md)）。

- メッセージ: `罫線を持つ段落が版面に入らないため、罫線を省いて分けて組みました（段落スタイル <名前>）`、`罫線を持つ見出しが版面に入らないため、罫線を省きました（見出し <階層>）`
- 段階とモジュール: レイアウト（golem-driver の `Golem.Driver.Pdf`）
- ADR: [golem-driver ADR 0027](golem-driver/adr/0027-paragraph-style-rules.md)、[golem-driver ADR 0035](golem-driver/adr/0035-paragraph-rules-split-and-space-units.md)（分けて組んだ段落の罫線）

### 主な原因

- 罫線を持つ段落スタイルを、一ページ（段）より長い段落に当てた。
- 見出しの罫線の間隔が大きく、見出しの行と罫線の領域が一ページ（段）に入らない。

### 直し方

罫線を持つ段落を短くするか、罫線を持たない段落スタイルにする。
見出しの罫線の間隔を狭める。
分けて組んでよければ、そのままでよい。
`manifest.toml` の `[diagnostics]` の `silence-notices` に `"G0746"` を加えると、このお知らせを出さなくなる。

## G0747

段の先頭に来た `@blank-line` の空きを捨てました

- 重大度: お知らせ
- 状態: 使用中

### 意味

PDF で、行アキが段の先頭に来たので、空きを取らずに捨てた。
段の先頭の空きは前の段の終わりの余白と見分けられず、前後のブロックの区切りにならないためである。
どのようにして段の先頭に来たかによらず捨てる。
前のブロックが段の最後の行で終わった場合、行アキと次のブロックの最初の部分が今の段に入らずに次の段へ送った場合、改ページか改丁する見出しか `@need-lines` で段を改めた直後、本の最初のブロックの前のどれでも同じである。
行アキを途中で切り詰めることはしない。
続けて書いた `@blank-line` を捨てた場合は、それぞれの行に出す。
位置は、捨てた `@blank-line` の行である。
お知らせなので、エラーにも警告にもならず、ビルドの成否に影響しない（[golem-syntax ADR 0002](golem-syntax/adr/0002-notice-severity.md)）。
diagnostic の重大度に notice より下の info を設けたら、このコードを info に移す予定である（[docs/roadmap.md](roadmap.md) の「diagnostic の info」）。

- メッセージ: `段の先頭に来た @blank-line の空きを捨てました`
- 段階とモジュール: レイアウト（golem-driver の `Golem.Driver.Pdf`、golem-layout の `Golem.Layout.Paginate`）
- ADR: [docs/adr/0046](adr/0046-blank-line-command.md)

### 主な原因

- 場面の区切りの `@blank-line` が、組んだ結果でページか段の境目に来た。
- 改ページの直後に `@blank-line` を書いた。

### 直し方

捨ててよければ、そのままでよい。
区切りを必ず見せたい場合は、＊などの印を原稿に書くか、`@page-lines` などで改ページの位置を変える。
`manifest.toml` の `[diagnostics]` の `silence-notices` に `"G0747"` を加えると、このお知らせを出さなくなる。

## G0750

隠しノンブルが版面に重なります

- 重大度: エラー
- 状態: 使用中

### 意味

トンボを付けた PDF に入れる隠しノンブルの数字の列の左右の範囲（ノドの仕上がりの線から `[hidden-folio]` の `gutter` の距離にある中心線から、`size` の半分ずつ）が、そのページの版面か傍注欄に、左右の方向で重なる。
`style.toml` と `--marks` だけで決まるので、PDF をターゲットに含み、`--marks` が `japanese` か `western` のときは、ビルドと `golem check` の両方で、レイアウトの前に報告する。
`[hidden-folio]` の `enabled` が `false` のときと、`--marks none` のときは検査しない。
PDF を書かない。
位置は `style.toml` の先頭である。

- メッセージ: `隠しノンブルが版面に重なります。[hidden-folio] の gutter を小さくするか、ノドの余白を広げてください`
- 段階とモジュール: レイアウト（golem-layout-spec の `Golem.LayoutSpec`、golem-driver の `Golem.Driver`、`Golem.Driver.Pdf`）
- ADR: [golem-driver ADR 0021](golem-driver/adr/0021-hidden-folios.md)、[golem-driver ADR 0041](golem-driver/adr/0041-hidden-folio-overlap-check-by-size.md)（数字の列の幅を `size` で測ること）

### 主な原因

- `[page.grid]` の `position` の `gutter`（ノドの余白）が数ミリしかない。
- `[hidden-folio]` の `gutter` か `size` が大きい。

### 直し方

`[hidden-folio]` の `gutter` を小さくするか、`[page.grid]` の `position` の `gutter` を広げる。
中綴じの本のように隠しノンブルが要らない場合は、`[hidden-folio]` に `enabled = false` を書く。

## G0751

柱の行が版面の幅を超えています

- 重大度: 警告
- 状態: 使用中

### 意味

PDF に描く柱の行の幅が、そのページの版面の幅を超える。
柱は版面の幅で折り返さないので、行は小口かノドの余白へ伸びるが、PDF は組める。
同じ行の文字列には一つだけ出し、ページの番号は最初に現れたページとする。
位置は `style.toml` の先頭である。

- メッセージ: `柱の行が版面の幅を超えています（<ページ> ページ）: <行の文字列>`
- 段階とモジュール: レイアウト（golem-driver の `Golem.Driver.Pdf`）
- ADR: [golem-driver ADR 0022](golem-driver/adr/0022-running-head-formats.md)

### 主な原因

- 柱の書式の一行に、書名と章の題など長い値を並べた。
- 固定の文言が長い。

### 直し方

柱の書式の行を二行に分けるか、`@toc-title` で短い題を付ける。
固定の文言を短くする。

## G0752

柱の行がページからはみ出しています

- 重大度: エラー
- 状態: 使用中

### 意味

`style.toml` のマスターページの柱の書式の行が多く、最も外側の行の字の外枠が、仕上がりの判型の外に出る。
柱の行は、版面に最も近い行を一行の柱の位置に置き、ほかの行を行送りずつ天（または地）の側へ重ねるので、行を増やすと柱はページの端へ伸びる。
字の外枠は、ベースラインから天の側へ文字の大きさの 0.88 倍、地の側へ残りとする。
行の数は `style.toml` だけで決まるので、PDF をターゲットに含むときは、ビルドと `golem check` の両方で、レイアウトの前に報告する。
PDF を書かない。
位置は `style.toml` の先頭である。

- メッセージ: `柱の行がページからはみ出しています。行の数を減らすか、天（または地）の余白を広げてください`
- 段階とモジュール: レイアウト（golem-layout-spec の `Golem.LayoutSpec`）
- ADR: [golem-driver ADR 0022](golem-driver/adr/0022-running-head-formats.md)

### 主な原因

- 柱の書式の配列の行が、天（または地）の余白に対して多い。
- 天（または地）の余白が狭い。

### 直し方

柱の書式の行の数を減らすか、`[page.grid]` の `position` で天（または地）の余白を広げる。

## G0801

フォントを読まずに PDF を作ろうとしました

- 重大度: エラー
- 状態: 使用中

### 意味

フォントを読まない `noFontProvider` で PDF を作ろうとした。
`golem` のコマンドは本物のフォントの読み込みを使うので、利用者がこのコードを見ることはない。
テストが、フォントなしで PDF の経路の手前までを確かめるために使う。
位置は `style.toml` の先頭で、`style.toml` がなければ `manifest.toml` の先頭である。

- メッセージ: `フォントを読まない設定（noFontProvider）では PDF を出力できません`
- 段階とモジュール: 出力（golem-driver の `Golem.Driver.Pdf`）
- ADR: [golem-driver ADR 0016](golem-driver/adr/0016-output-and-layout-diagnostic-codes.md)

### 主な原因

- テストがフォントを読まない `noFontProvider` で PDF を作ろうとした。`golem` のコマンドは本物のフォントの読み込みを使うので、利用者がこのコードを見ることはない。

### 直し方

利用者が直すことはない。
`golem` のコマンドでこのコードが出たら、Golem の誤りとして報告する。

## G0802

PDF のフォントのファイルがありません

- 重大度: エラー
- 状態: 使用中

### 意味

PDF が使う役割のフォントのファイルがないか、パスが不正である。
PDF を書かない。
`golem check` も報告する。
LSP は出さない。
位置は `style.toml` の先頭である。
本文のフォントの設定がない場合は [G0807](#g0807) である。

- メッセージ: `フォントのファイルがありません: <パス>`、またはパスの誤りの文言（`絶対パスは使えません: <パス>` など）
- 段階とモジュール: 出力（golem-driver の `Golem.Driver`、`Golem.Driver.Fonts`）
- ADR: [golem-project ADR 0004](golem-project/adr/0004-font-file-check-per-target.md)（ターゲットごとの検査を定めた）、[golem-driver ADR 0016](golem-driver/adr/0016-output-and-layout-diagnostic-codes.md)（本文のフォントの設定の欠けを G0807 に分けた。[golem-cli ADR 0003](golem-cli/adr/0003-new-project-page-and-fonts.md) も触れる）

### 主な原因

- `style.toml` の `[fonts]` のパスの綴りを誤ったか、ファイルを置いていない。
- `golem new --no-fonts` で作ったプロジェクトに、まだフォントを置いていない。

### 直し方

`style.toml` の `[fonts]` のパスを直すか、指すファイルを置く。

## G0803

フォントを読み込めません

- 重大度: エラー
- 状態: 使用中

### 意味

PDF が使う役割のフォントのファイルを、OpenType（TrueType の輪郭か CFF の輪郭）のフォントとして開けない。
読み込めないファイルをすべて、パスごとに一つずつ報告する。
PDF を書かない。
位置は `style.toml` の先頭である。

- メッセージ: `フォントを読み込めません: <パス>`。パスは `style.toml` に書いたとおりである。
- 段階とモジュール: 出力（golem-driver の `Golem.Driver.Fonts`）
- ADR: [golem-driver ADR 0016](golem-driver/adr/0016-output-and-layout-diagnostic-codes.md)

### 主な原因

- フォントのファイルが壊れている。
- OpenType として読めない、対応しない形式である。

### 直し方

別のファイルを指す。

## G0804

ライセンスが埋め込みを禁じているフォントです

- 重大度: エラー
- 状態: 使用中

### 意味

フォントの OS/2 の `fsType` が、PDF への埋め込みを禁じている。
OpenType の仕様に従い、次のどれかに当てはまれば埋め込まない。
ビット 1（`0x0002`、制限付きのライセンス）が立ち、ビット 2（`0x0004`）とビット 3（`0x0008`）が立っていない。
ビット 8（`0x0100`、サブセット化の禁止）が立っている。
Golem はサブセットしか埋め込まないためである。
ビット 9（`0x0200`、ビットマップの埋め込みだけを許す）が立っている。
読み込めないファイルをすべて、パスごとに一つずつ報告する。
PDF を書かない。
位置は `style.toml` の先頭である。

- メッセージ: `ライセンスが埋め込みを禁じているフォントです（fsType <値>）: <パス>`。値は `0x0102` のように `0x` と 4 桁の大文字の 16 進数で書く。
- 段階とモジュール: 出力（golem-driver の `Golem.Driver.Fonts`、golem-font の `Golem.Font`）
- ADR: [golem-driver ADR 0016](golem-driver/adr/0016-output-and-layout-diagnostic-codes.md)（[golem-font ADR 0001](golem-font/adr/0001-shaping-and-metrics.md) がエラーにすると定めた）

### 主な原因

- フォントの OS/2 の `fsType` が、PDF への埋め込みかサブセット化を禁じている。

### 直し方

埋め込みとサブセット化を許すフォントに替える。

## G0805

PostScript 名が同じ異なるフォントがあります

- 重大度: エラー
- 状態: 使用中

### 意味

バイト列の異なる二つのフォントのファイルが、同じ PostScript 名を持つ。
[G0803](#g0803) と [G0804](#g0804) がないときだけ検査する。
位置は `style.toml` の先頭である。

- メッセージ: `PostScript 名が同じ異なるフォントがあります: <名前>（<パス>、<パス>）`
- 段階とモジュール: 出力（golem-driver の `Golem.Driver.Fonts`）
- ADR: [golem-driver ADR 0003](golem-driver/adr/0003-pdf-heading-styles.md)（位置は [golem-driver ADR 0016](golem-driver/adr/0016-output-and-layout-diagnostic-codes.md)）

### 主な原因

- 同じフォントの別のバージョンを混ぜている。

### 直し方

どちらか一方のファイルにそろえる。

## G0806

出力インテントの ICC プロファイルがありません

- 重大度: エラー
- 状態: 使用中

### 意味

PDF を作るときに、`[color]` の `intent` が指す ICC プロファイルのファイルがないか、パスが不正である。
PDF を書かない。
LSP は出さない。

- メッセージ: `出力インテントの ICC プロファイルがありません: <パス>`、またはパスの誤りの文言（`絶対パスは使えません: <パス>` など）
- 段階とモジュール: 出力（golem-driver の `Golem.Driver`、`Golem.Driver.Pdf`）
- ADR: [golem-project ADR 0004](golem-project/adr/0004-font-file-check-per-target.md)

### 主な原因

- `[color]` の `intent` のパスの綴りを誤ったか、ファイルを置いていない。
- パスが絶対パスなど、使えない形である。

### 直し方

ICC プロファイルのファイルを置くか、パスを直す。

## G0807

PDF の本文のフォントの設定がありません

- 重大度: エラー
- 状態: 使用中

### 意味

PDF をターゲットに含むのに、`style.toml` の `[fonts]` に役割が一つもないか、本文の役割に `ja` も `latin` もない。
本文の役割は `body` で、`[fonts]` に `body` がなければ名前の順で最初の役割である。
`golem check` も報告し、PDF のレイアウトに進まない。
LSP は出さない。
位置は `style.toml` の先頭で、`style.toml` がなければ `manifest.toml` の先頭である。

- メッセージ: `style.toml に本文のフォントがありません。[fonts.body] を書いてください`、`[fonts.<役割>] にフォントのファイルがありません`
- 段階とモジュール: 出力（golem-driver の `Golem.Driver`）
- ADR: [golem-driver ADR 0016](golem-driver/adr/0016-output-and-layout-diagnostic-codes.md)

### 主な原因

- `style.toml` に `[fonts.body]` を書いていない。
- 本文の役割に `features` だけを書き、`ja` と `latin` を書いていない。

### 直し方

`style.toml` に `[fonts.body]` を書き、`ja` か `latin` にフォントのファイルのパスを書く。

## G0808

コードの書体の役割がありません

- 重大度: お知らせ
- 状態: 使用中

### 意味

本にコードブロックかコードの文字スタイル（`code` と、`based-on` で `code` に行き着く文字スタイル）の文字があるのに、`style.toml` に `[fonts.code]` がない。
PDF はコードを本文の役割で組む。
一回のビルドで一つだけ出し、PDF は書く。
位置は `style.toml` の先頭で、`style.toml` がなければ `manifest.toml` の先頭である。
`code` の段落スタイルか文字スタイルの `font` を別の役割に変え、その役割が `[fonts]` にない場合は [G0308](#g0308) である。
お知らせなので、エラーにも警告にもならず、ビルドの成否に影響しない（[golem-syntax ADR 0002](golem-syntax/adr/0002-notice-severity.md)）。

- メッセージ: `コードの書体の役割 code がないので、本文の書体で組みます`
- 段階とモジュール: 出力（golem-driver の `Golem.Driver`、`Golem.Driver.Pdf`）
- ADR: [golem-driver ADR 0017](golem-driver/adr/0017-pdf-code-blocks.md)

### 主な原因

- `style.toml` に、コード用の書体の役割 `[fonts.code]` を書いていない。`golem new` の雛形は書かない。

### 直し方

`style.toml` に `[fonts.code]` を書き、等幅の書体のファイルを `latin`（和文も載せるなら `ja`）に書く。
本文の書体で組んでよければ、そのままでよい。
`manifest.toml` の `[diagnostics]` の `silence-notices` に `"G0808"` を加えると、このお知らせを出さなくなる。

## G0809

圏点の字が書体にありません

- 重大度: エラー
- 状態: 使用中

### 意味

圏点を付けた字の役割の和文の書体に、圏点の形の字（`sesame` なら U+FE45 の `﹅`）がない。
書体にない字は `.notdef` の箱で描かれるので、PDF を書く前に止める。
役割と形の組ごとに一つだけ出す。
PDF を書かない。
位置は `style.toml` の先頭で、`style.toml` がなければ `manifest.toml` の先頭である。

- メッセージ: `役割 <役割> の和文の書体に圏点の形 <形> の字（U+<符号位置>）がありません`
- 段階とモジュール: 出力（golem-driver の `Golem.Driver.Pdf`）
- ADR: [golem-driver ADR 0019](golem-driver/adr/0019-pdf-kenten-shapes.md)

### 主な原因

- 和文の役割に、圏点の字を持たない書体（欧文の書体など）を指定した。
- `[kenten ...]` の `shape` か `style.toml` の `[composition]` の `kenten` に、書体にない形を書いた。

### 直し方

`shape`（または `[composition]` の `kenten`）を、書体にある形に替える。
あるいは、圏点の字を持つ書体を、その役割の `ja` に指定する。
## G0810

図版を PDF に置けません

- 重大度: エラー
- 状態: 使用中

### 意味

`@figure` の画像のファイルはあるが、PDF に置ける形で読めない。
PNG と JPEG の図版は画像として読めないとき、PDF の図版は Golem が取り込めないときに出す。
SVG の図版は、XML として読めないとき、UTF-8 でないとき、内部サブセットを持つ `DOCTYPE` があるとき、大きさ（ルートの `width` と `height` か `viewBox`）がないときに出す（[golem-pdf ADR 0009](golem-pdf/adr/0009-svg-figures.md)）。
大きさの数の絶対値が 10^9 を超えるときも、大きさがないときと同じく、理由を `大きさの数が大きすぎます` として出す（[docs/adr/0041](adr/0041-svg-marker-and-number-limits.md)）。
SVG の範囲の外のものは [G0811](#g0811) である。
PDF の図版を取り込めないのは、次のどれかの場合である。

- 相互参照などが壊れている。
- 暗号化されている。
- `page` のページがない。
- 扱わない圧縮（`LZWDecode`、`JBIG2Decode`、`JPXDecode` など）を使っている。
- 埋め込んでいないフォントがある。
- 特色（Separation か DeviceN）がある。
- RGB のインライン画像がある。
- レイヤー（オプショナルコンテンツ）がある。
- `UserUnit` が 1 でない。
- 展開した大きさの合計が 256 MiB を超える。理由は `PDF として読めません（展開した大きさが上限を超えました）` である。
- ページの木で、一つのノードを二度指している（同じ `Page` を二つの `Kids` から指すなど）。理由は `PDF として読めません（ページの木）` である。
- 相互参照の項目の数が、すべての改訂を合わせて 8,388,607 を超える。理由は `PDF として読めません（相互参照）` である。
- Flate の予測子の `Colors`、`BitsPerComponent`、`Columns` が範囲の外にある。理由は `PDF として読めません（予測子）` である。

最後の四つは、取り込みの資源の上限である（[docs/adr/0040](adr/0040-pdf-import-resource-limits.md)）。
壊れている PDF の理由は `PDF として読めません（<箇所>）` の形であり、`ページの木` と `相互参照` の箇所は、上限を超えた場合とそのほかの壊れ方で同じ文言になる。
上限の値と数え方は [golem-pdf の仕様書](golem-pdf/specifications.md) にある。

`@figure` ごとに一つ出し、PDF を書かない。
dev と prod の両方でエラーである。
PDF を組むとき（`golem build` の PDF と `golem preflight`）にだけ出す。
HTML、EPUB、プレーンテキストでは出さない。
位置は、その `@figure` のブロックである。

- メッセージ: `図版を PDF に置けません: <パス>（<理由>）`
- 段階とモジュール: 出力（golem-driver の `Golem.Driver.Pdf`、golem-pdf の `Golem.Pdf.Image` と `Golem.Pdf.Import`、golem-svg の `Golem.Svg`）
- ADR: [golem-pdf ADR 0008](golem-pdf/adr/0008-pdf-figures.md)、[docs/adr/0040](adr/0040-pdf-import-resource-limits.md)、[docs/adr/0041](adr/0041-svg-marker-and-number-limits.md)（SVG の大きさの数）

### 主な原因

- 画像のファイルが壊れている。
- SVG の図版の大きさに、10^9 を超える数を書いた。
- インターレースの PNG を使った。
- 拡張子と中身の形式が食い違っている（中身が PDF の `.png` など）。
- PDF の図版の書き出しの設定で、フォントを埋め込んでいないか、特色やレイヤーを残している。
- PDF の図版が仕様に反している（ページの木の重なりなど）か、展開すると大きすぎる。

### 直し方

理由に合わせて図版を書き出し直す。
PDF の図版なら、フォントを埋め込み、特色をプロセスカラーに直し、レイヤーを統合して書き出す。
PNG はインターレースを外して書き出す。
ページの木や相互参照が理由なら、PDF を作り直す道具で書き出し直す。
展開した大きさが理由なら、図版を必要なページだけの PDF に分けて書き出す。

## G0811

SVG の図版に扱えないものがあります

- 重大度: エラー
- 状態: 使用中

### 意味

SVG の図版に、Golem が PDF に描ける範囲の外の要素、属性、プロパティの値がある。
範囲は [golem-pdf ADR 0009](golem-pdf/adr/0009-svg-figures.md) の表のとおりで、パス、基本の図形、変換、塗りと線、マーカーなどである。
輪郭にしていない文字（`text`、`tspan`、`textPath` の要素と `@font-face`）も範囲の外である。
絶対値が 10^9 を超える数も範囲の外であり、その属性かプロパティの名前に `（読めない数）` を添える（[docs/adr/0041](adr/0041-svg-marker-and-number-limits.md)）。
`marker` の循環は [G0816](#g0816)、深すぎる `marker` の入れ子は [G0817](#g0817) であり、このコードには入れない。
範囲の外のものを黙って無視せず、文書の順にすべて集め、最初のものの名前と位置（SVG のファイルの中の行と桁）を書き、残りの件数を添える。
最初のものが文字なら、輪郭にして書き出すよう案内する。
`@figure` ごとに一つ出し、PDF を書かない。
同じ `@figure` に G0816 か G0817 も当たれば、このコードの後に続けて出す。
dev と prod の両方でエラーである。
PDF を組むとき（`golem build` の PDF と `golem preflight`）にだけ出し、HTML、EPUB、プレーンテキストでは出さない。
HTML と EPUB は SVG を PDF の部分集合では検査せず、動的なコンテンツだけを [G0814](#g0814) で検査する。
位置は、その `@figure` のブロックである。

- メッセージ: `SVG の図版に扱えないものがあります: <パス>:<行>:<桁>（<名前>）ほか <n> 件`。文字なら `（<名前>: 文字は輪郭にして書き出してください）`。ほかになければ `ほか <n> 件` を書かない。
- 段階とモジュール: 出力（golem-driver の `Golem.Driver.Pdf` と `Golem.Driver.Svg`、golem-svg の `Golem.Svg`）
- ADR: [golem-pdf ADR 0009](golem-pdf/adr/0009-svg-figures.md)、[docs/adr/0041](adr/0041-svg-marker-and-number-limits.md)（読めない数）、[docs/adr/0054](adr/0054-svg-marker-cycle-and-depth-codes.md)（`marker` の循環と入れ子を G0816 と G0817 に分けた）

### 主な原因

- 文字を輪郭にせずに書き出した。
- グラデーション、`use`、クリップ、フィルター、1 でない不透明度などを使った。
- 子孫の結合子などの、扱わない CSS のセレクターを使った。
- 地図のタイルなどの、大きな座標を使う図を書き出した。

### 直し方

図の作成ツールで、文字を輪郭（アウトライン）にして書き出す。
範囲の外の機能は、ツールの側で範囲の中に収めて書き出し直す。
読めない数は、座標を縮めて書き出し直す。
SVG で収まらない図は、PDF で書き出して PDF の図版として置く。

## G0813

出力先がシンボリックリンクです

- 重大度: エラー
- 状態: 使用中

### 意味

`build`、または出力するターゲットのディレクトリ（`build/html`、`build/epub`、`build/text`、`build/pdf`）が、シンボリックリンクか、ディレクトリではないファイルである。
`golem build` は出力の前にこれらのディレクトリを消すので、リンクの先のファイルを消さないように、どのターゲットも消さず、書かずに止める。
該当するパスごとに一つ出す。
位置は `style.toml` の先頭で、`style.toml` がなければ `manifest.toml` の先頭である。

- メッセージ: `出力先がシンボリックリンクかディレクトリではないので、消すことも書くこともしません: <パス>`
- 段階とモジュール: 出力（golem-driver の `Golem.Driver`）
- ADR: [docs/adr/0035](adr/0035-security-hardening.md)

### 主な原因

- 原稿のリポジトリに、`build` という名前のシンボリックリンクが置かれている。
- `build` を別のディスクに向けるために、シンボリックリンクにした。

### 直し方

リンクの先を確かめてから、`build` のリンク（またはファイル）を消す。
出力を別の場所に置きたいときは、リンクにせず、ディレクトリをマウントする。

## G0814

SVG の図版に、HTML と EPUB に写せない動的なコンテンツがあります

- 重大度: エラー
- 状態: 使用中

### 意味

HTML と EPUB に写す SVG のファイルに、ブラウザーが SVG を文書として開いたときに動かすか読むもの（動的なコンテンツ）がある。
写す SVG は、`@figure` の図版か `web` のうち、拡張子が `.svg` のものである。
HTML と EPUB は SVG をそのまま写すので、読者が SVG を直接開けば、そのスクリプトが動く。
拒むのは、`script` の要素、`foreignObject`、`iframe`、`embed`、`object`、`handler`、`listener` の要素、名前が `on` で始まる属性、`#` で始まらない `href` と `xlink:href`、`href` かイベントの属性を書き換える `set` と `animate`、CSS の `@import` と `#` で始まらない `url()` である。
XML として読めない SVG、UTF-8 でない SVG、内部サブセットを持つ `DOCTYPE` を持つ SVG も、中身を確かめられないのでこのコードにする。
見つかったものを文書の順に集め、最初のものの名前と位置（SVG のファイルの中の行と桁）を書き、残りの件数を添える。
`@figure` ごとに一つ出し、HTML と EPUB を書かない。
PDF とプレーンテキストは書く。
dev と prod の両方でエラーである。
HTML か EPUB を組むとき（`golem build`）にだけ出す。
位置は、その `@figure` のブロックである。

- メッセージ: `SVG の図版に、HTML と EPUB に写せない動的なコンテンツがあります: <パス>:<行>:<桁>（<名前>）ほか <n> 件`。`<名前>` は要素の名前、属性の名前、`url()`、`@import` のどれかである。ほかになければ `ほか <n> 件` を書かない。読めない SVG なら `SVG の図版に、HTML と EPUB に写せない動的なコンテンツがあります: <パス>（<G0810 と同じ理由>）`
- 段階とモジュール: 出力（golem-driver の `Golem.Driver` と `Golem.Driver.Svg`、golem-svg の `Golem.Svg.Active`）
- ADR: [docs/adr/0039](adr/0039-svg-active-content-in-html-and-epub.md)、[docs/adr/0057](adr/0057-g0814-says-dynamic-content.md)（文言）

### 主な原因

- Web 用に作ったインタラクティブな SVG を、図版にした。
- 図の作成ツールが、外部の画像やフォントへの参照を書き出した。
- 他人から受け取った原稿のリポジトリに、スクリプトを持つ SVG が置かれている。

### 直し方

図の作成ツールで、スクリプト、イベント、外部への参照を使わずに書き出し直す。
外部の画像を参照する図は、画像を埋め込むか、`web` に PNG を置く。
他人から受け取った SVG でこのコードが出たら、中身を確かめてから使う。

## G0816

SVG の図版の marker が循環しています

- 重大度: エラー
- 状態: 使用中

### 意味

SVG の図版の `marker` が、自分自身を、ほかの `marker` を経てでも置く。
循環する `marker` は描き終わらない図なので、Golem の範囲によらず描かない。
判定は `marker` の参照のグラフで行い、図の本体から届く `marker` のあいだの参照のうち、両端が同じ強連結成分にあるもの（自分自身への参照を含む）を循環の参照とする（[docs/adr/0054](adr/0054-svg-marker-cycle-and-depth-codes.md)）。
循環の中の参照をすべて数える。
図の本体が置かない `marker` は数えない。
循環の参照を文書の順に集め、最初のものの位置（参照を持つ図形の、SVG のファイルの中の行と桁）と置く `marker` の id を書き、残りの件数を添える。
`@figure` ごとに一つ出し、PDF を書かない。
同じ `@figure` に [G0811](#g0811) も当たれば、その後に、[G0817](#g0817) も当たれば、その前に出す。
dev と prod の両方でエラーである。
PDF を組むとき（`golem build` の PDF と `golem preflight`）にだけ出す。
位置は、その `@figure` のブロックである。

- メッセージ: `SVG の図版の marker が循環しています: <パス>:<行>:<桁>（<id>）ほか <n> 件`。ほかになければ `ほか <n> 件` を書かない。
- 段階とモジュール: 出力（golem-driver の `Golem.Driver.Pdf` と `Golem.Driver.Svg`、golem-svg の `Golem.Svg`）
- ADR: [docs/adr/0054](adr/0054-svg-marker-cycle-and-depth-codes.md)

### 主な原因

- `marker` が自分自身を参照する SVG を生成した。
- 二つ以上の `marker` が互いを置く SVG を生成した。

### 直し方

循環の中の参照を一つ切る。

## G0817

SVG の図版の marker の入れ子が 9 段を超えます

- 重大度: エラー
- 状態: 使用中

### 意味

SVG の図版の `marker` の中の `marker` が、9 段を超えて入れ子になる。
図が置く `marker` を 1 段目とし、描く手間を限るために 9 段まで描く。
`marker` の深さは、循環の参照を除いた、図の本体からの最も長い参照の列の長さとする（[docs/adr/0054](adr/0054-svg-marker-cycle-and-depth-codes.md)）。
深さ 9 以上の `marker` の中の参照を、すべて数える。
循環の参照でもある参照は、[G0816](#g0816) として数える。
参照を文書の順に集め、最初のものの位置（参照を持つ図形の、SVG のファイルの中の行と桁）と置く `marker` の id を書き、残りの件数を添える。
`@figure` ごとに一つ出し、PDF を書かない。
同じ `@figure` に [G0811](#g0811) か G0816 も当たれば、その後に出す。
dev と prod の両方でエラーである。
PDF を組むとき（`golem build` の PDF と `golem preflight`）にだけ出す。
位置は、その `@figure` のブロックである。

- メッセージ: `SVG の図版の marker の入れ子が 9 段を超えます: <パス>:<行>:<桁>（<id>）ほか <n> 件`。ほかになければ `ほか <n> 件` を書かない。
- 段階とモジュール: 出力（golem-driver の `Golem.Driver.Pdf` と `Golem.Driver.Svg`、golem-svg の `Golem.Svg`）
- ADR: [docs/adr/0054](adr/0054-svg-marker-cycle-and-depth-codes.md)

### 主な原因

- `marker` を深く入れ子にした SVG を生成した。

### 直し方

`marker` の入れ子を 9 段までにする。

## G0819

CFF2 の輪郭のフォントは PDF に埋め込めません

- 重大度: エラー
- 状態: 使用中

### 意味

PDF が使う役割のフォントが、CFF2 の輪郭（`CFF2` の表）を持つ。
CFF2 の輪郭は、可変の OpenType/CFF2 のフォントが使う。
PDF の埋め込みフォントの入れ物は CFF2 の輪郭を受けず、TrueType の入れ物に入れた PDF はビューアーで字が描かれない。
フォントのファイルごとに一つ出す。
PDF を書かない。
`golem build` の PDF、`golem check`、`golem preflight` が報告する。
HTML と EPUB はフォントのファイルをそのまま同梱し、ブラウザーと読書環境が CFF2 を描くので、出さない。
位置は `style.toml` の先頭（`style.toml` がなければマニフェストの先頭）である。

- メッセージ: `CFF2 の輪郭のフォントは PDF に埋め込めません: <パス>。CFF か TrueType の輪郭のフォントを使ってください`。パスは `style.toml` に書いたとおりである。
- 段階とモジュール: 出力（golem-driver の `Golem.Driver`、`Golem.Driver.Fonts`、golem-font の `Golem.Font`）
- ADR: [golem-font ADR 0003](golem-font/adr/0003-reject-cff2-fonts-in-pdf.md)

### 主な原因

- 可変フォントの `.otf`（たとえば `SourceSerif4Variable-Roman.otf`）を、本の役割に指定した。

### 直し方

同じ書体の、CFF の輪郭の版（静的な `.otf`）か TrueType の輪郭の版（`.ttf`）を使う。
Source Serif 4 なら、`SourceSerif4-Regular.otf` か `SourceSerif4Variable-Roman.ttf` である。

## G0901

プリフライトの設定に誤りがあります

- 重大度: エラー
- 状態: 使用中

### 意味

`golem preflight` が読むプリフライトの設定のファイルに誤りがある。
ファイルは `--rules` で指したもの、指さなければプロジェクトのルートの `preflight.toml` である。
ファイルが読めない（`--rules` の指すファイルがない、UTF-8 でない）、TOML として読めない、知らないキーがある、値の型や範囲が違う、のどれもがこのコードになる。
`based-on` が `basic`、`print`、`none` のどれでもないとき、しきい値が負のとき、`image-resolution` の `error-below` が `warning-below` より大きいときも、このコードである。
位置は、そのファイルの中の誤りの位置である。
このコードが出ると、PDF を組まずに終える。
重大度は、プリフライトの設定で変えられない。

- メッセージ: TOML の誤りは TOML の読み込みの文言、ほかは `<キー> の値が正しくありません: <値>（<理由>）`。ファイルがなければ `プリフライトの設定のファイルがありません: <パス>`
- 段階とモジュール: プリフライト（golem-preflight の `Golem.Preflight.Rules`、golem-driver の `Golem.Driver`）
- ADR: [golem-cli ADR 0006](golem-cli/adr/0006-preflight.md)

### 主な原因

- キーの名前を書き違えた。
- `severity` に `error`、`warning`、`off` のほかの値（`notice` など）を書いた。
- 長さに `zw` を使った。
- `--rules` のパスを書き違えた。

### 直し方

メッセージが示すキーを直す。
書けるキーと値は、利用者のマニュアルの付録 D「preflight.toml のリファレンス」にある。

## G0902

フォントにグリフのない文字があります

- 重大度: プリフライトの設定による（print の既定はエラー）
- 状態: 使用中

### 意味

シェイピングの結果のグリフ番号が 0（.notdef）になった文字がある。
その文字は、PDF では空の箱などで表示される。
原稿の文字、番号の文字列、柱、ノンブル、目次と索引の文字列のすべてを対象とする。
符号位置とフォントのファイルの組ごとに一つにまとめ、JSON の `facts` に `code-point`、`font`、`pdf-pages`、`count` を書く。
位置は、その文字を含む原稿のブロックの位置である。

- メッセージ: `フォントにグリフのない文字です: U+<16 進数>「<文字>」（<フォントのパス>、PDF の <ページ> ページ目）`
- 段階とモジュール: プリフライト（golem-preflight の `Golem.Preflight`）
- ADR: [golem-cli ADR 0006](golem-cli/adr/0006-preflight.md)

### 主な原因

- 本文のフォントが、その文字（外字、絵文字、私用領域の文字など）を持っていない。
- 和文の文字を、欧文だけのフォントの役割で組んでいる。

### 直し方

その文字を持つフォントを `style.toml` の `[fonts]` の役割に書くか、原稿の文字を替える。
検査を外すときは、プリフライトの設定の `[glyph-missing]` の `severity` を `off` にする。

## G0903

この設定では使えない形式のフォントです

- 重大度: プリフライトの設定による（print の既定は off）
- 状態: 使用中

### 意味

PDF に埋め込んだフォントの形式が、プリフライトの設定の `[font-formats]` の `allowed` にない。
形式は、`CFF ` の表を持つ OpenType を `cff`、`CFF2` の表を持つ OpenType を `cff2`、そのどちらでもないものを `truetype` とする（[golem-font ADR 0003](golem-font/adr/0003-reject-cff2-fonts-in-pdf.md)）。
`cff2` のフォントは [G0819](#g0819) で PDF を組めないので、`allowed` に書けるが、この検査には現れない。
フォントのファイルごとに一つ出す。
位置は `style.toml` の先頭である。

- メッセージ: `この設定では使えない形式のフォントです: <パス>（<形式>）`
- 段階とモジュール: プリフライト（golem-preflight の `Golem.Preflight`）
- ADR: [golem-cli ADR 0006](golem-cli/adr/0006-preflight.md)

### 主な原因

- 印刷所が、TrueType のフォントの入稿を受けない。

### 直し方

印刷所が受ける形式のフォントに替える。

## G0904

文字が小さすぎます

- 重大度: プリフライトの設定による（print の既定は警告）
- 状態: 使用中

### 意味

文字の大きさが、プリフライトの設定の `[type-size]` の `min-size` より小さい。
`multi-ink-only` が真なら、色が二つ以上の版を使う文字だけを対象とする。
版のずれで、小さな文字がにじむからである。
ルビと圏点も文字に含める。
文字の役割と大きさと色の組ごとに一つにまとめる。
位置は、その文字を含む原稿のブロックの位置である。

- メッセージ: `文字が小さすぎます: <大きさ>（<min-size> 未満、色 <スウォッチの名前>、PDF の <ページ> ページ目）`
- 段階とモジュール: プリフライト（golem-preflight の `Golem.Preflight`）
- ADR: [golem-cli ADR 0006](golem-cli/adr/0006-preflight.md)

### 主な原因

- 小さなルビや注を、複数の版を使う色（リッチブラックなど）で組んでいる。

### 直し方

文字を大きくするか、色を一つの版（K だけなど）にする。

## G0905

図版を PDF に置けません

- 重大度: プリフライトの設定による（print の既定はエラー）
- 状態: 廃止

### 意味

廃止した。
`@figure` の画像のファイルはあるが、JPEG か PNG として読めない図版を `golem preflight` が報告するコードだった。
置けない図版は `golem build` と `golem preflight` のどちらでも [G0810](#g0810) のエラーになり、PDF を作れなければプリフライトは何も検査しないので、このコードは出なくなった。
`preflight.toml` の `image-unplaceable` は、知らないキー（[G0901](#g0901)）になった。

- メッセージ: `図版を PDF に置けません: <パス>（<理由>）`
- 段階とモジュール: プリフライト（golem-preflight）
- ADR: [golem-cli ADR 0006](golem-cli/adr/0006-preflight.md)（定めた）、[golem-pdf ADR 0008](golem-pdf/adr/0008-pdf-figures.md)（使わなくした）

### 直し方

[G0810](#g0810) を見る。
`preflight.toml` に `image-unplaceable` を書いていれば消す。

## G0906

図版の実効の解像度が足りません

- 重大度: プリフライトの設定による（print では 150ppi 未満がエラー、300ppi 未満が警告）
- 状態: 使用中

### 意味

画像の実効の解像度が、その画像の種類の `warning-below` か `error-below` を下回る。
実効の解像度は、画素数を紙面に置いた大きさ（インチ）で割った値で、縦と横の小さいほうを、小数点以下を切り捨てて使う。
画像の種類は、一ビットのグレーを `bitmap`、ほかのグレーを `gray`、RGB と CMYK とパレットを `color` とする。
`error-below` を下回ればエラー、そうでなく `warning-below` を下回れば警告である。
`@figure` ごとに一つ出し、JSON の `facts` に `ppi`、`limit`、`pixels`、`pdf-pages` を書く。

- メッセージ: `図版の実効の解像度が足りません: <パス>（<ppi>ppi、<しきい値>ppi 未満、PDF の <ページ> ページ目）`
- 段階とモジュール: プリフライト（golem-preflight の `Golem.Preflight`）
- ADR: [golem-cli ADR 0006](golem-cli/adr/0006-preflight.md)

### 主な原因

- 画面用の小さな画像を、紙面に大きく置いた。

### 直し方

画素数の多い画像に替えるか、紙面に置く大きさを小さくする。

## G0907

図版の実効の解像度が高すぎます

- 重大度: プリフライトの設定による（print の既定は off）
- 状態: 使用中

### 意味

画像の実効の解像度が、その画像の種類の上限（`[image-resolution-max]` の `color-max`、`gray-max`、`bitmap-max`）を超える。
PDF の大きさを抑えたい入稿先のための検査である。
`@figure` ごとに一つ出す。

- メッセージ: `図版の実効の解像度が高すぎます: <パス>（<ppi>ppi、<しきい値>ppi 超）`
- 段階とモジュール: プリフライト（golem-preflight の `Golem.Preflight`）
- ADR: [golem-cli ADR 0006](golem-cli/adr/0006-preflight.md)

### 主な原因

- 撮影したままの大きな画像を、紙面に小さく置いた。

### 直し方

Golem は画像を縮小しないので、画像のファイルを小さく作り直す。

## G0908

この設定では使えない色空間の図版です

- 重大度: プリフライトの設定による（print の既定は警告）
- 状態: 使用中

### 意味

画像の色空間が、プリフライトの設定の `[image-color-space]` の `allowed` にない。
色空間は、グレーを `gray`、RGB とパレットを `rgb`、CMYK を `cmyk` とする。
PDF の図版では、ICC プロファイルの色空間を成分の数で `gray`（1）、`rgb`（3）、`cmyk`（4）とし、それ以外の成分の数のものを `icc`、Lab を `lab` とする。
SVG の図版は `rgb` である。
`@figure` ごとに一つ出す。
PDF の図版で許さない色空間が二つ以上あれば、一つの diagnostic に `、` で並べる。

- メッセージ: `この設定では使えない色空間の図版です: <パス>（<色空間>）。Golem は画像の色を変換しないので、CMYK に変換した画像に替えます`
- 段階とモジュール: プリフライト（golem-preflight の `Golem.Preflight`）
- ADR: [golem-cli ADR 0006](golem-cli/adr/0006-preflight.md)

### 主な原因

- RGB の画像を使った。PDF/X-4 は RGB の画像を許すが、日本の印刷所の多くは CMYK の入稿を求める。

### 直し方

画像を、印刷所の求める条件で CMYK に変換して置き換える。

## G0909

出力インテントと違う ICC プロファイルを持つ CMYK の図版です

- 重大度: プリフライトの設定による（print の既定は警告）
- 状態: 使用中

### 意味

CMYK の画像が ICC プロファイルを埋め込んでおり、そのバイト列が `style.toml` の `[color] intent` のファイルのバイト列と違う。
同じ特性の別のバージョンのプロファイルも、違うとみなす。
`[color] intent` がなければ、何も出さない。
`@figure` ごとに一つ出す。

- メッセージ: `出力インテントと違う ICC プロファイルを持つ CMYK の図版です: <パス>。印刷の工程で色が変換されることがあります`
- 段階とモジュール: プリフライト（golem-preflight の `Golem.Preflight`）
- ADR: [golem-cli ADR 0006](golem-cli/adr/0006-preflight.md)

### 主な原因

- 出力インテントと違う条件で、画像を CMYK に変換した。

### 直し方

出力インテントと同じプロファイルで画像を変換し直す。

## G0910

塗り足しの幅が足りません

- 重大度: プリフライトの設定による（print の既定はエラー、3mm 未満）
- 状態: 使用中

### 意味

`style.toml` の `[page] bleed` が、プリフライトの設定の `[bleed-size]` の `min` より小さい。
位置は `style.toml` の先頭で、`style.toml` がなければ `manifest.toml` の先頭である。

- メッセージ: `塗り足しの幅が足りません: <bleed>（<min> 以上にします）`
- 段階とモジュール: プリフライト（golem-preflight の `Golem.Preflight`）
- ADR: [golem-cli ADR 0006](golem-cli/adr/0006-preflight.md)

### 主な原因

- `style.toml` の `[page]` に `bleed` を書いていない。`golem new` の雛形は書かない。

### 直し方

`style.toml` の `[page]` に `bleed = "3mm"` のように書く。

## G0911

図版が仕上がりの線の近くにあり、塗り足しまで届いていません

- 重大度: プリフライトの設定による（print の既定はエラー、3mm）
- 状態: 使用中

### 意味

画像のどれかの辺が、仕上がりの線の内側に `[bleed-trim-hazard]` の `distance` 未満まで近づいているか、仕上がりの線を越えているが塗り足しの線まで届いていない。
辺から仕上がりの線までの距離を、内側を正として e とすると、`-<bleed> < e < <distance>` のときである。
仕上がりの線ちょうど（e = 0）の辺は、塗り足しが 0 でも対象とする。
`@figure` ごとに一つ出す。
v1 の図版は版面の中に置くので、版面の余白が `distance` 以上ある本では何も出さない。

- メッセージ: `図版が仕上がりの線の近くにあり、塗り足しまで届いていません: <パス>（<辺>、仕上がりの線から <e>、PDF の <ページ> ページ目）`
- 段階とモジュール: プリフライト（golem-preflight の `Golem.Preflight`）
- ADR: [golem-cli ADR 0006](golem-cli/adr/0006-preflight.md)

### 主な原因

- 版面の余白が狭い。

### 直し方

版面の余白を広げるか、図版を小さくする。

## G0912

文字が仕上がりの線に近すぎます

- 重大度: プリフライトの設定による（print の既定は警告、3mm）
- 状態: 使用中

### 意味

文字の行の範囲か線の範囲が、仕上がりの線から `[live-area]` の `distance` だけ内側の矩形（安全域）からはみ出す。
文字の行の範囲は、行頭から行末まで、文字の大きさの高さである。
トンボは対象にしない。
要素の種類と辺の組ごとに一つにまとめるので、柱とノンブルは一つになる。
位置は、本文の行では原稿のブロック、柱とノンブルでは `style.toml` の先頭である。

- メッセージ: `文字が仕上がりの線に近すぎます: <要素>（<辺>、仕上がりの線から <距離>、PDF の <ページ> ページ目）`
- 段階とモジュール: プリフライト（golem-preflight の `Golem.Preflight`）
- ADR: [golem-cli ADR 0006](golem-cli/adr/0006-preflight.md)

### 主な原因

- `[masters]` の柱かノンブルの位置が、仕上がりの線に近い。
- 版面の余白が狭い。
- 段落スタイルか見出しの罫線を、`start-indent`、`end-indent`、`keep-in-column = false` で仕上がりの線の近くまで出した（[golem-driver ADR 0027](golem-driver/adr/0027-paragraph-style-rules.md)）。

### 直し方

版面の位置か、柱とノンブルの位置を仕上がりの線から離す。

## G0913

行が行長からはみ出しています

- 重大度: プリフライトの設定による（print の既定は警告）
- 状態: 使用中

### 意味

行分割が、行長に収められなかった行を残した。
Knuth-Plass の行分割は、最後の段で行長を超える行を許す。
行ごとに一つ出す。
位置は、その行を含む原稿のブロックである。

- メッセージ: `行が行長から <量> はみ出しています（PDF の <ページ> ページ目）`
- 段階とモジュール: プリフライト（golem-driver の `Golem.Driver.Pdf`、golem-preflight の `Golem.Preflight`）
- ADR: [golem-cli ADR 0006](golem-cli/adr/0006-preflight.md)

### 主な原因

- 分割できない長い語や URL がある。
- 行長が短い。

### 直し方

語を分けられるようにするか、文を書き換える。

## G0914

PDF/X-4 の要件を満たしていません

- 重大度: プリフライトの設定による（print の既定はエラー）
- 状態: 使用中

### 意味

組んだ PDF が、[golem-pdf ADR 0002](golem-pdf/adr/0002-pdf-x-4.md) の PDF/X-4 の要件のどれかを満たさない。
`Golem.Pdf.X4.verify` が、書く前の PDF のオブジェクトを検査する。
項目は、PDF のバージョン、出力インテントとその ICC プロファイル、XMP の `GTS_PDFXVersion` と `Trapped`、各ページのボックス、フォントの埋め込み、ICC プロファイルのない RGB、暗号化と JavaScript と外部への参照である。
要件ごとに一つ出す。
`style.toml` に `[color] intent` がないときは、続く要件の不足を並べず、一つにまとめる。
位置は `style.toml` の先頭で、`style.toml` がなければ `manifest.toml` の先頭である。
この検査は PDF/X-4 の適合の判定ではない（[golem-pdf ADR 0003](golem-pdf/adr/0003-pdf-x-4-validator.md)）。

- メッセージ: `PDF/X-4 の要件を満たしていません: <要件>（<詳細>）`。出力インテントがなければ `PDF/X-4 の要件を満たしていません: 出力インテントがありません（style.toml の [color] に intent を書きます）`
- 段階とモジュール: プリフライト（golem-pdf の `Golem.Pdf.X4`、golem-preflight の `Golem.Preflight`）
- ADR: [golem-cli ADR 0006](golem-cli/adr/0006-preflight.md)

### 主な原因

- `style.toml` の `[color]` に `intent` を書いていない。`golem new` の雛形は書かない。

### 直し方

印刷所が指定する ICC プロファイルを置き、`style.toml` の `[color]` に `intent` を書く。
入稿の前には、商用のプリフライトでも確かめる。

## G0915

色の総インキ量が多すぎます

- 重大度: プリフライトの設定による（print の既定は警告、350%）
- 状態: 使用中

### 意味

紙面で使った色（文字と地の色）のスウォッチの C、M、Y、K の値の和が、`[ink-coverage]` の `max` を超える。
スウォッチごとに一つ出す。
画像の画素は検査しない。
位置は `style.toml` の先頭である。

- メッセージ: `色の総インキ量が多すぎます: <スウォッチの名前>（<和>%、<max>% 超）`
- 段階とモジュール: プリフライト（golem-preflight の `Golem.Preflight`）
- ADR: [golem-cli ADR 0006](golem-cli/adr/0006-preflight.md)

### 主な原因

- リッチブラック（C、M、Y、K をすべて重ねた黒）のスウォッチを使った。

### 直し方

スウォッチの値を下げる。

## G0916

ページ数が指定の倍数ではありません

- 重大度: プリフライトの設定による（print の既定は off）
- 状態: 使用中

### 意味

PDF のページ数が、`[page-count]` の `multiple-of` の倍数でない。
折の単位（16 ページなど）で台割を組む印刷所のための検査である。
位置は `manifest.toml` の先頭である。

- メッセージ: `ページ数が <multiple-of> の倍数ではありません: <ページ数>（あと <差> ページ）`
- 段階とモジュール: プリフライト（golem-preflight の `Golem.Preflight`）
- ADR: [golem-cli ADR 0006](golem-cli/adr/0006-preflight.md)

### 主な原因

- 原稿の量が、折の単位にそろっていない。

### 直し方

白ページや奥付の位置を調整して、ページ数をそろえる。

## G0917

空白のページがあります

- 重大度: プリフライトの設定による（print の既定は off）
- 状態: 使用中

### 意味

マスターページの要素（柱、ノンブル）のほかに、何も描かないページがある。
すべての空白のページを一つにまとめる。
Golem は右起こしの改ページで空白のページを意図して作るので、既定では検査しない。
位置は `manifest.toml` の先頭である。

- メッセージ: `空白のページです（PDF の <ページ> ページ目）`
- 段階とモジュール: プリフライト（golem-driver の `Golem.Driver.Pdf`、golem-preflight の `Golem.Preflight`）
- ADR: [golem-cli ADR 0006](golem-cli/adr/0006-preflight.md)

### 主な原因

- `page-break = "recto"` の見出しの前のページが空いた。
- 改ページを重ねた。

### 直し方

意図した空白なら、そのままでよい。
そうでなければ、改ページを見直す。

## G0918

線が細すぎます

- 重大度: プリフライトの設定による（print の既定は警告、0.1mm 未満）
- 状態: 使用中

### 意味

Golem が描く線（表の罫線と、脚注の前の罫線）の太さが、`[stroke-weight]` の `min` より細い。
トンボの線は対象にしない。
線の種類ごとに一つ出す。
v1 の表の罫線（0.6pt と 0.3pt）は、既定の 0.1mm より太い。
脚注の前の罫線の太さは `[notes.rule]` の `weight` で決まり、既定の 0.3pt は 0.1mm より太い（[golem-driver ADR 0024](golem-driver/adr/0024-rule-spec-and-footnote-separator.md)）。
位置は `style.toml` の先頭である。

- メッセージ: `線が細すぎます: <線の種類>（<太さ>、<min> 未満、PDF の <ページ> ページ目）`
- 段階とモジュール: プリフライト（golem-preflight の `Golem.Preflight`）
- ADR: [golem-cli ADR 0006](golem-cli/adr/0006-preflight.md)

### 主な原因

- プリフライトの設定の `min` を、Golem の罫線より太くした。
- `[notes.rule]` の `weight` を、`min` より細くした。

### 直し方

印刷所の求める太さを確かめる。
