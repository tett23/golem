# 診断のコード

この文書は、Golem が出す診断のコード（`G0101` など）を一つずつ説明する。
診断は、コードと一行のメッセージだけを出す。
コードが何を表し、どう直せばよいかを、ここで引けるようにする。
`golem explain <コード>` は、この文書の節をそのまま表示する（[golem-cli ADR 0005](golem-cli/adr/0005-explain-diagnostic-codes.md)）。
LSP の診断の `codeDescription` は、GitHub の上のこの文書の節を指す。

プラグインが出す診断のコードは、この文書の対象外である。
プラグインのコードはプラグインが決めるので、プラグインの文書を参照する。

## 節の形

各コードの節は、`## G0101` の見出しから始まる。
見出しにはコードだけを書くので、節の URL は `diagnostics.md#g0101` になる。
節は次のものを、この順に持つ。

- **題**：見出しの次の段落。一行で書き、`golem explain` の一覧に使う。
- **重大度**：`- 重大度:` の行。エラー、警告、dev では警告、prod ではエラー、お知らせ、のいずれかを書く。エラーが一つでもあれば、ビルドは失敗し、終了コードは 1 になる。お知らせは終了コードに影響せず、`manifest.toml` の `[diagnostics]` の `silence-notices` と、コマンドの `--no-notices` で抑制できる（[golem-syntax ADR 0002](golem-syntax/adr/0002-notice-severity.md)）。
- **状態**：`- 状態:` の行。使用中か廃止を書く。
- **意味**：`### 意味` の小見出し。いつ出るかを書き、メッセージの文言、段階とモジュール、ADR を添える。メッセージの引数を埋める部分は `<名前>` のように書く。番号を書いた ADR が見つからないコードは「ADR なし」とし、番号に触れているだけの ADR があれば併記する。
- **主な原因**：`### 主な原因` の小見出し。よくある原因を書く。廃止したコードでは省ける。
- **直し方**：`### 直し方` の小見出し。廃止したコードでは、代わりの書き方を書く。

節はコードの昇順に並べる。
golem をビルドするときにこの文書を埋め込み、節の形を検査する。
形の崩れた文書では、golem をビルドできない。

ソースで使っているコードがすべて状態「使用中」で載っていること、状態「使用中」のコードがすべてソースで使われていること、重大度が `profileDependentCodes` と `noticeCodes` に合うことは、golem-driver のテスト（`modules/golem-driver/test/Main.hs`）が確かめる。
新しいコードを足すときは、同じ変更でこの文書に節を足す。
使わなくなったコードは、節を消さずに状態を「廃止」にする。

## 番号の区分

コードは `G` と 4 桁の数字からなる。
上 2 桁が、診断を出す段階を表す（[golem-syntax ADR 0001](golem-syntax/adr/0001-source-spans-and-diagnostics.md)）。
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

重大度がプロファイルで変わるコードは `Golem.Syntax.Diagnostic.profileDependentCodes` にまとめてあり、dev では警告、prod ではエラーになる。
今は [G0310](#g0310) と [G0504](#g0504) の二つである。
[G0205](#g0205) は、prod でだけ出る警告である。

## お知らせ

お知らせは、誤りではないが書き手が知っておいたほうがよいことを伝える重大度である（[golem-syntax ADR 0002](golem-syntax/adr/0002-notice-severity.md)）。
直すべきものは警告にし、直さなくてよいものをお知らせにする。
お知らせは終了コードに影響せず、プロファイルで重大度が変わらず、出力も変えない。
人が読む形式と JSON の形式では、エラーと警告の後に並ぶ。

お知らせのコードは `Golem.Syntax.Diagnostic.noticeCodes` にまとめてある。
今は次の九つである。

| コード | 種類 | 段階 |
| --- | --- | --- |
| [G0262](#g0262) | 上書き | 評価 |
| [G0263](#g0263) | 一般的でない書き方 | 評価 |
| [G0264](#g0264) | 効果のない書き方 | 評価 |
| [G0265](#g0265) | 廃止予定 | 評価 |
| [G0323](#g0323) | 既定の使用 | プロジェクト |
| [G0407](#g0407) | 効果のない書き方 | 文書の組み立て |
| [G0408](#g0408) | 効果のない書き方 | 文書の組み立て |
| [G0730](#g0730) | 処理系による調整 | レイアウト |
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
2. お知らせを出す版を、少なくとも一つの minor の版としてリリースする。プレリリース（`-rc` など）だけでは数えない。リリースノートの「変更」の項に、廃止予定の書き方を挙げる。
3. 次の ADR で、その書き方をエラーにする。エラーには新しいコードを割り当て、お知らせのコードは状態を「廃止」にする。番号は使い回さない。

## 使っていない番号

次の番号は、ソースで使っていない。

- **廃止**：G0244。[docs/adr/0003](adr/0003-verse-line-breaks.md) が `@verse` の引数の誤りに定めたが、[docs/adr/0005](adr/0005-character-and-paragraph-styles.md) で使わなくなった。下に節を置く。
- **廃止**：G0248。[docs/adr/0005](adr/0005-character-and-paragraph-styles.md) が廃止した `@verse` に定めたが、[golem-fmt ADR 0002](golem-fmt/adr/0002-remove-verse-migration.md) で使わなくなった。下に節を置く。
- **空き**：G0104 から G0109、G0125 から G0128、G0601、G0703 から G0720、G0731、G0736 から G0740。各区分の最後に使った番号より後も空いている。

## G0101

UTF-8 として不正なバイト列があります

- 重大度: エラー
- 状態: 使用中

### 意味

原稿のファイル（章と import したファイル）、`manifest.toml`、`style.toml` のどれかに、UTF-8 として読めないバイト列がある。
位置は最初の不正なバイトである。

- メッセージ: `UTF-8 として不正なバイト列があります`
- 段階とモジュール: 構文（golem-parser の `Golem.Parser.Read`）
- ADR: [golem-parser ADR 0009](golem-parser/adr/0009-syntax-diagnostic-codes.md)

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

[記法](markup.md)と照らして直す。

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

キーワード引数の後に位置引数があります

- 重大度: エラー
- 状態: 使用中

### 意味

コマンドの引数で、`key=value` の後に位置引数がある。

- メッセージ: `キーワード引数の後に位置引数があります`
- 段階とモジュール: 構文（golem-parser）
- ADR: [golem-parser ADR 0009](golem-parser/adr/0009-syntax-diagnostic-codes.md)

### 主な原因

- コマンドの引数で、`key=value` の後に位置引数を書いた。

### 直し方

位置引数をキーワード引数より前に並べる。

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

ラベルの示す位置の記法を、[記法](markup.md)と照らして直す。

## G0201

型が合いません

- 重大度: エラー
- 状態: 使用中

### 意味

式の演算や関数に、使えない型の値を渡した。

- メッセージ: 型の誤りを述べる文言。たとえば `- は <型> に使えません`、`<型> と <型> にこの演算子は使えません`、`<型> は数ではありません`、`<型> の要素は参照できません`、`% は整数にだけ使えます`、`div は整数にだけ使えます`。
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.Expr`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- 文字列と数の演算など、型の合わない値を演算子や関数に渡した。

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
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- 名前の綴りを誤った。
- `@set` や `@import` を書き忘れた。

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

- メッセージ: `結果が NaN か無限大になる演算です`、`負の数の平方根です`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.Expr`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- 負の数の平方根など、浮動小数点の計算が NaN か無限大になる演算をした。

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
たとえば、見出しでないブロックへの `@notoc`、段落でないブロックへの `@style`、図版のキャプションの中の `@style` である。

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
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`。プラグインのコマンドの呼び出しでは golem-driver の `Golem.Driver.Plugins`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

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

`src=` で CSV のファイルを指す。

## G0235

CSV が空か、行ごとのセルの数が一致しません

- 重大度: エラー
- 状態: 使用中

### 意味

`@table` の CSV が空か、行ごとのセルの数がそろっていない。

- メッセージ: `CSV が空です`、`CSV の行ごとのセルの数が一致しません`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [golem-eval ADR 0003](golem-eval/adr/0003-evaluation-diagnostic-codes.md)

### 主な原因

- `@table` の CSV のファイルが空である。
- CSV の行によって列の数が違う。

### 直し方

CSV の各行の列の数を見出しの行にそろえる。

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

`sesame`、`open-sesame`、`dot`、`open-dot`、`circle`、`open-circle` のどれかにする。

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
そのキーは無視し、同じ `@manifest` のほかのキーの上書きは効かせる。

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
そのキーの上書きは効かない。

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

改ページのコマンドの引数が誤っています

- 重大度: エラー
- 状態: 使用中

### 意味

`@page-break` か `@column-break` の引数か本体が誤っている。
`@page-break` は位置引数を一つまで取り、それは `recto` か `verso` である。
`@column-break` は引数を取らない。
どちらもキーワード引数と本体を持たない。
誤ったコマンドは捨て、改ページしない。

- メッセージ: `@page-break の引数は recto か verso です`、`@column-break は引数を取りません`、`@page-break と @column-break は本体を持てません`
- 段階とモジュール: 評価（golem-eval の `Golem.Eval.File`）
- ADR: [docs/adr/0017](adr/0017-forced-page-breaks.md)

### 主な原因

- `@page-break page` のように、`recto` と `verso` のほかの語を書いた。
- `@page-break recto verso` のように、引数を二つ以上書いた。
- `@page-break x=1` のように、キーワード引数を書いた。
- `@column-break recto` のように、`@column-break` に引数を書いた。
- `@page-break` の次の行を字下げして、本体にした。

### 直し方

ただの改ページは `@page-break` とだけ書き、奇数ページから始めるなら `@page-break recto`、偶数ページから始めるなら `@page-break verso` と書く。
`@page-break` の次の行を字下げしているなら、字下げをやめる。

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
使える関数は `sqrt`、`floor`、`ceil`、`round`、`fixed`、`abs`、`min`、`max`、`len`、`div` である。
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

## G0301

manifest.toml の誤りです

- 重大度: エラー
- 状態: 使用中

### 意味

`manifest.toml` が TOML として読めないか、スキーマに合わないか、出力ターゲットが一つもない。
`[source]` と章の項目の `[source]` のキー（`paragraph-separator` など）の未知のキーと不正な値、同じファイルを章の配列に二度並べて効く `[source]` の値が異なる場合も、この誤りとする。

- メッセージ: `TOML の誤りです: <詳細>`、`@style-def の値が不正です: <詳細>`、`出力ターゲットが一つもありません`、`同じファイルを [source] の設定を変えて章に二度並べています: <パス>`、`章は、ファイルのパス、表、配列のどれかで書きます`、または TOML のスキーマの誤りの文言（未知のキー、値の型の誤り、`[source]` の不正な値など）。スキーマの誤りには、`(.targets.html)` のように誤った箇所の経路を添える。経路が空のとき（ファイルの最上位の誤り）は添えない。
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project.Manifest`）。位置は、スキーマの誤りでは誤った値の位置、それ以外では `manifest.toml` の先頭である
- ADR: [golem-project ADR 0006](golem-project/adr/0006-project-diagnostic-codes.md)（定めた）。[golem-cli ADR 0002](golem-cli/adr/0002-build-all-targets-by-default.md) が触れ、[docs/adr/0013](adr/0013-paragraph-separator.md) が `[source]` の誤りの条件を加えた

### 主な原因

- TOML の文法を誤った。
- キーの綴りか値の型を誤った。未知のキーは無視せずエラーにする。
- 出力ターゲット（`[targets.*]`）を一つも書いていない。
- `[source]` の値を誤った。`paragraph-separator` は `"blank-line"` か `"line"` と書く。

### 直し方

メッセージの示すキーと値を直す。
ターゲットを一つ以上書く。

## G0302

ファイルがありません

- 重大度: エラー
- 状態: 使用中

### 意味

章や `@import` が指すファイルがない。
プロジェクトのルートに `manifest.toml` がないときは、この誤りではなく [G0316](#g0316) とする。

- メッセージ: `ファイルがありません: <パス>`
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project`）。位置は、章なら `manifest.toml` の先頭、`@import` ならその `@import` のブロック全体である
- ADR: [golem-project ADR 0006](golem-project/adr/0006-project-diagnostic-codes.md)

### 主な原因

- 章や `@import` のパスの綴りを誤ったか、ファイルを置いていない。

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
`@style-def` の名前と欄の誤りにも出る。誤りのある定義は捨てる。

- メッセージ: `TOML の誤りです: <詳細>`、TOML のスキーマの誤りの文言、または値の検査の文言（`スタイルの名前は英小文字で始まり、英小文字、数字、- だけからなります: <名前>`、`番号の書式が不正です: <書式>`、`塗り足しには zw を使えません`、`<キー> に使えない値です: <値>（<許す値> のどれか）`、`columns が 2 以上のときは column-gap が要ります`、`space-between は 0 以上です`、`長さの書き方が不正です: <値>（13Q や 20mm のように書きます）`、`長さは文字列で書きます`、`cmyk は 0 から 100 までの整数四つです`、`見出しの段は 1、2、3 のどれかです: <段>` など）。廃止した欄（`[emphasis]`、`[verse]`、`[sidenotes]` の `font` と `size`）は、書き換え先を示す文言になる。スキーマの誤りには誤った箇所の経路を添え、経路が空のときは添えない。toml-parser 自身の文言（`missing key`、`unexpected key` など）は英語のままである。
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project.Style`）。位置は、スキーマの誤りでは誤った値の位置、TOML の構文の誤りと読み込んだ後の検査では `style.toml` の先頭である。ファイルの中の定義（`@style-def`）は評価（golem-eval の `Golem.Eval.Settings`）が同じ検査をし、位置はその `@style-def` の行になる
- ADR: [golem-project ADR 0006](golem-project/adr/0006-project-diagnostic-codes.md)（定めた）。条件を加えた ADR は [golem-project ADR 0004](golem-project/adr/0004-font-file-check-per-target.md)、[docs/adr/0005](adr/0005-character-and-paragraph-styles.md)、[docs/adr/0006](adr/0006-paragraph-indent.md)、[golem-pdf ADR 0004](golem-pdf/adr/0004-crop-marks-and-bleed.md)、[golem-layout ADR 0008](golem-layout/adr/0008-explicit-hyphens.md)、[golem-layout ADR 0009](golem-layout/adr/0009-ruby-placement.md)、[golem-driver ADR 0009](golem-driver/adr/0009-pdf-toc-page-numbers.md)、[golem-driver ADR 0010](golem-driver/adr/0010-caption-style.md)、[golem-driver ADR 0011](golem-driver/adr/0011-sidenote-font.md)、[docs/adr/0014](adr/0014-in-file-settings.md) である

### 主な原因

- TOML の文法を誤った。
- キーの綴り、値の型、単位、列挙の値を誤った。
- 値が範囲の外にある。
- 廃止した欄（`[emphasis]`、`[verse]`、`[sidenotes]` の `font` と `size`）を書いた。
- 段落スタイル `code` に、`font`、`size`、`background`、`padding` のほかのキー（`based-on` を含む）を書いた（[golem-driver ADR 0017](golem-driver/adr/0017-pdf-code-blocks.md)）。
- `background` か `padding` を、`code` のほかの段落スタイルに書いた。`padding` が負であるか、寸法として読めない。

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
`@style-def` の `font` にも出る。誤りのある定義は捨てる。
組み込みの段落スタイル `code` と文字スタイル `code` の `font` が既定の役割 `code` を指し、`[fonts.code]` がない場合は、この誤りとせず、本文の役割で組む（[G0808](#g0808)、[golem-driver ADR 0017](golem-driver/adr/0017-pdf-code-blocks.md)）。

- メッセージ: `style.toml にないフォントの役割です: <役割>`
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project.Style`）。ファイルの中の定義（`@style-def`）は評価（golem-eval の `Golem.Eval.Settings`）が同じ検査をし、位置はその `@style-def` の行になる
- ADR: [golem-driver ADR 0003](golem-driver/adr/0003-pdf-heading-styles.md)（定めた）、[docs/adr/0005](adr/0005-character-and-paragraph-styles.md)（段落スタイルに広げた）、[docs/adr/0014](adr/0014-in-file-settings.md)（ファイルの中の定義に広げた）

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
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project.Style`）。ファイルの中の定義（`@style-def`）は評価（golem-eval の `Golem.Eval.Settings`）が同じ検査をし、位置はその `@style-def` の行になる
- ADR: [docs/adr/0005](adr/0005-character-and-paragraph-styles.md)

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
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project.Style`）。ファイルの中の定義（`@style-def`）は評価（golem-eval の `Golem.Eval.Settings`）が同じ検査をし、位置はその `@style-def` の行になる
- ADR: [docs/adr/0006](adr/0006-paragraph-indent.md)

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
正規表現スタイルの `style` が文字スタイルにないか、`@style-def regex` の段落スタイルがない場合も、この誤りとする。
段落スタイルの `aki-set` と、アキ量のセットの `based-on` が存在しないセットを指すか、セットの `based-on` が循環する場合も、この誤りとする。

- メッセージ: `style.toml のスタイルの参照が不正です: <理由>`（ファイルの中の定義では `@style-def のスタイルの参照が不正です: <理由>`）。正規表現スタイルの理由は `正規表現スタイルの文字スタイルがありません: <名前>` か `正規表現スタイルの段落スタイルがありません: <名前>`
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project.Style`）。ファイルの中の定義（`@style-def`）は評価（golem-eval の `Golem.Eval.Settings`）が同じ検査をし、位置はその `@style-def` の行になる
- ADR: [docs/adr/0005](adr/0005-character-and-paragraph-styles.md)（正規表現スタイルの参照は [docs/adr/0015](adr/0015-regex-styles.md)、アキ量のセットの参照は [docs/adr/0019](adr/0019-aki-settings.md)）

### 主な原因

- `based-on` が存在しないスタイルを指す。
- `based-on` が循環する。
- `body` に `based-on` を書いた。
- 文字スタイルの `color` が `[color.swatches]` にない。
- 正規表現スタイルの `style` に、組み込みにも `style.toml` にも同じファイルの `@style-def character` にもない文字スタイルを書いた。
- `@style-def regex` の二つ目の引数に、ない段落スタイルを書いた。
- 段落スタイルの `aki-set` か、`[aki-sets.<名前>]` の `based-on` が、存在しないセットを指す。
- `[aki-sets.<名前>]` の `based-on` が循環する。
- 段落スタイルの `based-on` に `code` を書いた。`code` はほかの段落スタイルの元にならない（[golem-driver ADR 0017](golem-driver/adr/0017-pdf-code-blocks.md)）。
- 段落スタイル `code` の `background` が `[color.swatches]` にない。

### 直し方

理由の示すスタイルの `based-on`、`color`、`aki-set`、正規表現スタイルの `style` か段落スタイルの名前、アキ量のセットの `based-on` を直す。
誤りのある正規表現スタイルの組だけが効かず、ほかの組は効く。

## G0314

柱の内容が正しくありません

- 重大度: エラー
- 状態: 使用中

### 意味

`style.toml` のマスターページの `running-head` の内容が、決まった語彙のどれでもないか、書き方の組み合わせが正しくない。
内容は `content` に一つ書くか、`even` と `odd` の両方に書く。
位置は誤った値の位置である。

- メッセージ: `柱の内容が正しくありません: <値>。heading.<階層>.short か heading.<階層>.numbered（末尾に .last を付けられます）、title、none のどれかを、content に一つ、または even と odd の両方に書いてください`。誤った箇所の経路を添える。組み合わせの誤りでは、`<値>` に書いた欄と値を並べ、どれも書いていなければ `（なし）` とする。
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project.Style`）
- ADR: [golem-driver ADR 0014](golem-driver/adr/0014-running-heads.md)

### 主な原因

- 内容の値の綴りを誤った（`heading.1.long`、`chapter` など）。
- 見出しの階層に 0 や数でないものを書いた。
- `content` と `even` または `odd` を一緒に書いた。
- `even` と `odd` の片方だけを書いた。
- 位置だけを書き、内容を書かなかった。

### 直し方

`content = "heading.1.short"` のように両方のページの内容を一つ書くか、`even = "title"` と `odd = "heading.1.short"` のように左右のページの内容を両方書く。
柱を出さないページには `none` を書くか、`running-head` のないマスターページを使う。

## G0315

正規表現を解釈できません

- 重大度: エラー
- 状態: 使用中

### 意味

正規表現スタイルの `pattern` が、Golem の正規表現の方言（InDesign の方言の部分集合）にない構文を含むか、正規表現として誤っている。
部分集合の外の構文は、黙って別の意味に読まずにこの誤りとする。

- メッセージ: `正規表現を解釈できません: <理由>（<段落スタイル> の <n> 番目の正規表現の <位置> 字目）`
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project.Style`、照合器は golem-regex の `Golem.Regex`）。ファイルの中の `@style-def regex` は評価（golem-eval の `Golem.Eval.Settings`）が同じ検査をし、位置はその行になる
- ADR: [docs/adr/0015](adr/0015-regex-styles.md)

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
- ADR: [golem-project ADR 0005](golem-project/adr/0005-page-size-by-dimensions.md)

### 主な原因

- 判型の表にない名前を書いたか、名前の綴りを誤った。
- `{ width, height }` の片方を書き忘れた。
- 寸法に `zw` を使ったか、0 以下の値を書いた。

### 直し方

表の名前（`"A4"`、`"A5"`、`"A6"`、`"B5"`、`"B6"`、`"四六判"`、`"菊判"`、`"新書判"`、`"mass-market"`）を書くか、`size = { width = "148mm", height = "210mm" }` のように寸法で書く。
単位は `mm`、`pt`、`Q`、`H` とし、`zw` は使わない。

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
- ADR: [golem-driver ADR 0016](golem-driver/adr/0016-output-and-layout-diagnostic-codes.md)

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
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project.Style`）。`@style-def` の寸法の欄は評価（golem-eval の `Golem.Eval.Settings`）
- ADR: [docs/adr/0019](adr/0019-aki-settings.md)

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

- メッセージ: `<欄> の値が正しくありません: <値>`。`tracking` の範囲の外では `（-1000 から 10000 までです）` を添える。`kerning = "optical"` は `v1 ではオプティカルカーニングを使えません（<文字スタイル|段落スタイル> <名前> の kerning）`。値の型の誤りは toml-parser の文言になる。誤った箇所の経路を添える。
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project.Style`）。ファイルの中の定義は評価（golem-eval の `Golem.Eval.Settings`）が同じ検査をし、位置はその `@style-def` の行になる
- ADR: [docs/adr/0020](adr/0020-indesign-character-features.md)

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
- 段階とモジュール: プロジェクト（golem-project の `Golem.Project.Style`）
- ADR: [golem-driver ADR 0013](golem-driver/adr/0013-list-indents.md)

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
- 版を上げて、書いてあったお知らせのコードが廃止になった。
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
- ADR: [docs/adr/0025](adr/0025-index-columns.md)

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

章の外にある図版に章番号を使う図番号を振れません

- 重大度: エラー
- 状態: 使用中

### 意味

`style.toml` の図番号の書式（`figures.number`）が `{chapter}` を使うのに、章の番号を持たない図版がある。
章は、番号を持つ階層 1 の見出しから、次の階層 1 の見出しまでである。
最初の章の見出しより前の図版と、`@nonumber` の階層 1 の見出し（あとがきなど）の後の図版が、章の外になる。
位置は図版のブロックである。

- メッセージ: `章の外にある図版には、章番号を使う図番号を振れません。章は番号を持つ階層 1 の見出しから始まります`
- 段階とモジュール: 文書の組み立て（golem-doc の `Golem.Doc.Assemble`）
- ADR: [golem-doc ADR 0003](golem-doc/adr/0003-document-diagnostic-codes.md)

### 主な原因

- 図番号の書式が `{chapter}` を使うのに、最初の章の見出しより前に図版を置いた。
- 図番号の書式が `{chapter}` を使うのに、`@nonumber` の階層 1 の見出し（あとがきなど）の後に図版を置いた。

### 直し方

図版を章の中に移すか、図番号の書式から `{chapter}` を外す。

## G0405

番号を持たない要素への参照です

- 重大度: エラー
- 状態: 使用中

### 意味

`ref-number` が、番号を持たない要素を指す。
番号を持つのは、`@nonumber` のない見出しと図版である。
位置は参照であり、参照は何も出力しない。

- メッセージ: `番号を持たない要素への参照です: <ラベル>`
- 段階とモジュール: 文書の組み立て（golem-doc の `Golem.Doc.Assemble`）
- ADR: [golem-doc ADR 0003](golem-doc/adr/0003-document-diagnostic-codes.md)

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
題を持つのは、見出し（`@toc-title` があればそれ）と図版（代替テキスト）である。
段落、リスト、表などに付けたラベルは、`ref-title` で参照できない。
位置は参照であり、参照は何も出力しない。

- メッセージ: `題を持たない要素への参照です: <ラベル>`
- 段階とモジュール: 文書の組み立て（golem-doc の `Golem.Doc.Assemble`）
- ADR: [golem-doc ADR 0003](golem-doc/adr/0003-document-diagnostic-codes.md)

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
ファイルの末尾の改ページは次のファイルに効くので、本の最後のファイルのものだけを対象にする。
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
コンパイルの失敗、import の要求、ABI の版の違い、必要な関数の欠け、起動の失敗、`golem_describe` の不正な出力を含む。
位置は `manifest.toml` の先頭である。
理由の文言は次のいずれかで、[G0609](#g0609) と共有する。
`プラグインを読み込めません: <詳細>`、`プラグインが import を要求しています: <import の一覧>`、`プラグインの ABI の版が異なります: <版>`、`プラグインが関数を公開していません: <関数>`、`プラグインの実行が命令数の上限を超えました`、`プラグインの実行が失敗しました（メモリの上限を超えた場合を含む）: <詳細>`、`プラグインを起動できません: <詳細>`、`プラグインの出力が不正です: <詳細>`

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
位置は、`plugins.lock` の中の誤りの位置である。

- メッセージ: `plugins.lock` の TOML の誤りの文言
- 段階とモジュール: プラグイン（golem-plugin の `Golem.Plugin.Lock`、golem-driver の `Golem.Driver.Plugins`、`golem plugin fetch`）
- ADR: [golem-plugin ADR 0003](golem-plugin/adr/0003-plugin-diagnostic-codes.md)

### 主な原因

- `plugins.lock` を手で編集した。
- `plugins.lock` のマージで衝突が残った。

### 直し方

`plugins.lock` は処理系が書くファイルなので、手で直さない。
`plugins.lock` を消して `golem plugin lock` を実行する。

## G0701

版面を計算できません

- 重大度: エラー
- 状態: 使用中

### 意味

`style.toml` の版面の設定から、PDF の版面を計算できない。
次の順に検査し、最初に当てはまったものを一つだけ報告する。
`[page]` がない（`style.toml` がない場合を含む）、`[page.grid]` がない、`[page.grid]` の `font-size` が正の絶対的な寸法でない、字数か行数か段数が 0 以下か行送りが文字の大きさより小さい、版面が判型からはみ出す、縦組みの版面に `[sidenotes]` がある、段組みの版面に `[sidenotes]` がある、傍注欄が判型からはみ出す、の順である。
PDF をターゲットに含むときは、ビルドと `golem check` の両方で、レイアウトの前に報告する。
PDF を書かない。
LSP は出さない。
位置は `style.toml` の先頭で、`style.toml` がなければ `manifest.toml` の先頭である。
未知の判型は [G0317](#g0317)、マスターページの未知の位置は [G0318](#g0318) である。

- メッセージ: `style.toml に [page] がないため、版面を計算できません`、`style.toml に [page.grid] がないため、版面を計算できません`、`文字の大きさは絶対的な寸法で書いてください`、`字数、行数、段数は 1 以上、行送りは文字の大きさ以上にしてください`、`版面がページからはみ出しています`、`縦組みの版面には傍注欄を設けられません`、`段組みの版面には傍注欄を設けられません`、`版面と傍注欄の合計がページからはみ出しています`
- 段階とモジュール: レイアウト（golem-layout-spec の `Golem.LayoutSpec`、golem-driver の `Golem.Driver`）
- ADR: [golem-driver ADR 0016](golem-driver/adr/0016-output-and-layout-diagnostic-codes.md)（[golem-cli ADR 0003](golem-cli/adr/0003-new-project-page-and-fonts.md)、[golem-driver ADR 0006](golem-driver/adr/0006-pdf-sidenotes.md)、[golem-driver ADR 0011](golem-driver/adr/0011-sidenote-font.md)、[golem-pdf ADR 0004](golem-pdf/adr/0004-crop-marks-and-bleed.md)、[docs/adr/0018](adr/0018-multi-column-layout.md) も触れる）

### 主な原因

- `style.toml` に `[page]` か `[page.grid]` がない。
- 文字の大きさを絶対的な寸法で書いていない。
- 字数、行数、段数が 0 以下か、行送りが文字の大きさより小さい。
- 版面か傍注欄が判型からはみ出している。
- 縦組みの版面に傍注欄を設けた。
- `[page.grid]` の `columns` が 2 以上の版面に傍注欄（`[sidenotes]`）を設けた。

### 直し方

`[page]` と `[page.grid]` を書き、字数、行数、文字の大きさ、余白を判型に収まる値にする。

## G0702

日本式のトンボには塗り足しが要ります

- 重大度: エラー
- 状態: 使用中

### 意味

`--marks japanese` で PDF を作るか検査するときに、`[page]` の `bleed` が 0 である。
PDF をターゲットに含まないビルドと LSP では出さない。

- メッセージ: `日本式のトンボには塗り足しが要ります。style.toml の [page] に bleed を書いてください`
- 段階とモジュール: レイアウト（golem-driver の `Golem.Driver`）
- ADR: [golem-pdf ADR 0004](golem-pdf/adr/0004-crop-marks-and-bleed.md)

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
位置はその項目の最初のブロックである。

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

## G0741

表の列が版面の行長に収まりません

- 重大度: エラー
- 状態: 使用中

### 意味

表の各列の最小の幅（改行できる位置のあいだの最も広い部分）の合計が、版面の行長を超える。

- メッセージ: `表の列の最小の幅の合計（<幅> mm）が使える幅（<幅> mm）に収まりません`
- 段階とモジュール: レイアウト（golem-driver の `Golem.Driver.Pdf`）
- ADR: [golem-driver ADR 0008](golem-driver/adr/0008-pdf-tables.md)

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
`style.toml` とファイルの中の定義だけで決まる最上位のコードブロックの行長の不足は、PDF をターゲットに含むときに、ビルドと `golem check` の両方でレイアウトの前に報告し、位置は `style.toml` の先頭（なければ `manifest.toml` の先頭）である。
リストの深い入れ子の中の行長の不足と、一ページに収まらない場合は、レイアウトで報告し、位置はコードブロックの始まりである。
PDF を書かない。

- メッセージ: `コードブロックの行長が足りません` または `コードブロックの一行が一ページに収まりません`
- 段階とモジュール: レイアウト（golem-driver の `Golem.Driver.Pdf`）
- ADR: [golem-driver ADR 0017](golem-driver/adr/0017-pdf-code-blocks.md)

### 主な原因

- `[paragraph-styles.code]` の `padding` が大きい。
- コードブロックをリストの深い入れ子の中に置いた。
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

- 同じフォントの別の版を混ぜている。

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
