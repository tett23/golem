# ADR 0115: 予約された記法に一つのコードを設け、`[!` と `@!` を拒む

ステータス: 採択

## 文脈

Golem は、マクロのために `[!` を予約している。
仕様書は「マクロ：構文 `[!` の予約のみ行い、実装しない」と書き（[docs/specifications.md の 113 行め](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/docs/specifications.md#L113)）、docs/markup.md の「予約された記法」の節は `[!` だけを挙げる（[docs/markup.md の 1348〜1352 行め](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/docs/markup.md#L1348-L1352)）。
引用は、断りのないかぎり origin/main の 668ed3ac のものである。

ところが、`[!` のための文法の規則も diagnostic もない。
origin/main の 668ed3ac で golem を作り、`golem new` で作ったプロジェクトの原稿に次のものを書いて `golem check` と `golem inspect --as ast` で確かめた。

| 原稿 | 今の結果 |
| --- | --- |
| `本文 [!foo bar] です。` | G01021（`[ の後にはコマンド名か = が必要です。本文の [ は \[ と書きます`） |
| `本文 [!] です。` | G01021 |
| `[! x]` | G01021 |
| 行頭の `@!foo` | 誤りにならず、`@!foo` という文字の段落になる |
| `@style x` の次の行の `@!foo` | 誤りにならず、段落スタイルを当てた段落になる |
| 段落の二行めの行頭の `@!foo` | 誤りにならず、前の行と同じ段落の文字になる |
| 段落の途中の `本文の@!です。` | 誤りにならず、文字になる |

`[!` は、`[` の後にコマンド名も `=` も続かないという、ほかの書き損じと同じ G01021 になる（文法の [`BadBracket`](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-parser/grammar/Golem.hpeg#L307-L308)）。
メッセージは `[` のエスケープを案内するだけで、予約された記法だとは伝えない。
`@!` は予約されておらず、行頭に書いても文字になる。
ブロックコマンドの始まりは `@` と英小文字（[`BlockStart` と `BlockCommandStart`](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-parser/grammar/Golem.hpeg#L204-L211)）であり、`@!` はどちらにも当たらないからである。

メンテナーは次のことを決めた。

- 予約された記法を書いたときの diagnostic を一つ設け、すべての予約された記法でそのコードを使う。原因は「予約された記法を書いた」であり、記法ごとにコードを分けない。これは「一つの原因に一つのコード」に従う。
- `[!` に加えて `@!` も予約する。
- [ADR 0113](0113-closed-range-literal.md) が予約する範囲の `..` も、このコードで拒む。

### 構文の diagnostic のコードと文法のラベル

構文の段階のコードは、文法のラベルごとに [`Golem.Parser.labelCode`](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-parser/src/Golem/Parser.hs#L39-L59) が一つずつ決める（[golem-parser ADR 0009](../golem-parser/adr/0009-syntax-diagnostic-codes.md)）。
ラベルには回復の規則（`%recover`）が一つずつ付く。
テスト「every grammar label has its own diagnostic code」（[ParserSpec.hs の 180〜186 行め](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-parser/test/ParserSpec.hs#L180-L186)）は、ラベルとコードが一対一であることを確かめる。
行頭で読んだ文字を見るだけでラベルを投げる規則には、`OrphanDef`（`=:`）と `BadBracket`（`[`）の前例がある（[Golem.hpeg の 169〜178 行め](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-parser/grammar/Golem.hpeg#L169-L178)）。

docs/diagnostics.md は、各区分の 000 から 099 を 4 桁のコードの写しに取っておき、新しいコードは 100 から 999 に割り当てると定める（[docs/diagnostics.md の「使っていない番号」](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/docs/diagnostics.md#L153-L163)）。
構文の区分（G01）の 100 以降は、どれも使っていない。

### 整形と LSP

`golem fmt` は、構文の誤りのあるファイルを書き換えない。
`本文   [!foo]   です。` を書いたファイルに `golem fmt` を実行すると、G01021 を出して終了コード 1 で終わり、ファイルのバイト列は変わらなかった。
LSP は、構文の段階の diagnostics を、ほかの段階と同じく公開する。

## 実装すること

### 予約された記法のコード

構文の区分の最初の新しい番号、G01100 を、予約された記法のコードにする。

| 項目 | 内容 |
| --- | --- |
| コード | G01100 |
| 重大度 | エラー |
| 原因 | 予約された記法を書いた |
| メッセージ | `予約された記法です。今のバージョンでは使えません` |
| 位置 | 予約された記法の最初の字から始まる。範囲の終わりは、ほかのラベルの構文の誤りと同じく回復の終わりである |
| 段階 | 構文（golem-parser）。語の中の `..` だけは評価（golem-eval、[ADR 0113](0113-closed-range-literal.md)） |

- メッセージは記法によらず一つにする。どの記法を書いたかは位置で分かる。記法ごとの書き換え方は、docs/diagnostics.md の G01100 の「直し方」に記法ごとに書く。
- 予約された記法は次の三つである。今後足すときも、このコードを使う。

| 記法 | 予約の目的 | 拒む位置 | 定める ADR |
| --- | --- | --- | --- |
| `[!` | インラインのマクロ | インラインのコマンドを書けるところ | この ADR |
| `@!` | ブロックのマクロ | ブロックコマンドを書けるところ | この ADR |
| `..` | 端を省いた範囲と、終わりを含まない範囲 | 式の中と、範囲を受け取る引数の語 | [ADR 0113](0113-closed-range-literal.md) |

### 文法

一つのラベル `reserved` を設け、予約された記法のすべてで使う。

```peg
%recover reserved SkipParagraph
# The same as bracket: the rule throws its label before the characters it
# only looks at, and no alternative can go on at the same place.
%safe reserved

ReservedBracket :: ()
ReservedBracket <- &'[!' (&{ False } '[!')^reserved { () }

ReservedBlock(ind :: Int) :: ()
ReservedBlock <- Ind(ind) &'@!' (&{ False } '@!')^reserved { () }
```

- `ReservedBracket` は、`InlineCommand` を書ける五つの規則（`HeadInline`、`Inline`、`SlotInline`、`CellInline`、`ArgValue`）で、`InlineCommand` の前に置く。`[!` は `InlineCommand` にも `BadBracket` にも届かず、G01021 にならない。
- `ReservedBlock` は、`Block` の選択肢の `OrphanDef` の次、`BlockGroup` の前に置く。
- `BlockStart` に `'@!'` を足す。段落の二行め以降の行頭の `@!` も、`@` と英小文字と同じく段落を終え、次のブロックとして `ReservedBlock` に読まれる。`@style x` の次の行の `@!` も、`AttributedBlock` の段落が `!BlockStart` で失敗するので、同じく G01100 になる。
- ラベルを一つにするので、回復の規則も一つ（`SkipParagraph`）になる。`[!` は `bracket` と同じ回復であり、`@!` と式の中の `..` は、ブロックの残りか段落の残りを読み飛ばす。予約された記法の後ろの誤りは報告されにくくなるが、予約された記法を直せば再び読まれる。
- `Golem.Parser.labelCode` に、ラベル `reserved` をコード G01100 と上の表のメッセージにする行を足す。ラベルとコードは一対一のままであり、テスト「every grammar label has its own diagnostic code」は変えない。
- `scripts/gen-parser.sh` で `Golem.Parser.Generated` と `StrippedGrammar` を作り直し、ラベルの安全性の検査（[golem-parser ADR 0007](../golem-parser/adr/0007-grammar-label-safety.md)）を通す。

### 予約しないところ

- 段落の途中の `@!`（`a@!b`）は文字のままとする。行の途中の `@` は、今も記法ではないからである。
- コードブロック、コメント、文字列リテラルの中の `[!` と `@!` は、今と同じく文字である。
- エスケープした `\[!` と `\@!` は文字である。書き手が `[!` や行頭の `@!` を本文に書くときは、この形にする。
- 式の中の `[!`（`[= [!x]]`）は、配列の始まりの `[` の後に式が来ないので、今の式の構文の誤り（G01020）のままとする。式の中にマクロを書く場所はない。

### `golem fmt` と LSP

- `golem fmt` は、G01100 のあるファイルを、ほかの構文の誤りと同じく書き換えず、diagnostic を出して終了コード 1 で終わる。予約された記法を書き換える規則は持たない。
- LSP は、G01100 をほかの構文の誤りと同じくエラーとして公開する。補完、ホバー、色分けに、予約された記法のための扱いは足さない。
- `golem explain G01100` は、docs/diagnostics.md の節を表示する。

### ドキュメント

- docs/markup.md の「予約された記法」の節に、`@!`（ブロックのマクロのための記法。ブロックコマンドを書ける行頭で使えない）と、予約された記法を書くと G01100 になることを書く。`..` は [ADR 0113](0113-closed-range-literal.md) が足す。
- docs/specifications.md の 113 行めの「マクロ」を、`[!` と `@!` を予約すると改め、G01100 へのリンクを足す。
- docs/diagnostics.md に G01100 の節を足す。「直し方」に、`[!` と行頭の `@!` を本文に書くときのエスケープ（`\[!`、`\@!`）を書く。G01021 の節の「意味」に、`[!` は G01100 になると書き足す。
- 使い手のマニュアルの付録 A の 476 行めに `@!` を足し、付録 E に G01100 を足す。

## 実装しないこと

- マクロそのもの。仕様書のとおり、予約だけを行う。
- 記法ごとにコードやメッセージを分けること。
- 行の途中の `@!` を予約すること。
- `golem fmt` で予約された記法をエスケープに書き換えること。
- `[!` と `@!` の後に何が続くか（マクロの名前と引数の形）を決めること。

## テスト設計

先に次のテストを書き、今のコードで失敗することを確かめてから実装する。

### golem-parser

- `a [!foo bar] b`、`a [!] b`、`[! x]` が G01100 になり、位置が `[` から始まること。今は G01021 である。
- 見出し（`# 題 [!x]`）、コマンドの本文の引数（`[strong: [!x]]`）、表のセル（`| [!x] |`）、コマンドの引数（`@caption [!x]`）の `[!` が G01100 になること。
- 行頭の `@!foo`、字下げしたブロックの中の `@!foo`、段落の二行めの行頭の `@!foo`、`@style x` の次の行の `@!foo` が G01100 になり、位置が `@` から始まること。今はどれも誤りにならない。
- `a@!b`、`\[!x]`、`\@!foo`、コードブロックの中の `[!` と `@!`、`%` のコメントの中の `[!` が誤りにならず、今と同じ AST になること。
- `a [x] b` は今と同じく G01021 であること。
- `labelCode (Just "reserved")` が G01100 であり、テスト「every grammar label has its own diagnostic code」が通ること。
- ラベルの安全性のテスト（`LabelSafetySpec`）が通ること。

### golem-driver

- `golem fmt` が `[!` を含むファイルを書き換えず、G01100 を出して終了コード 1 で終わること。
- `golem explain G01100` が節を表示すること（diagnostics.md の目録のテスト）。

### golem-lsp

- `[!` を含む文書を開くと、G01100 がエラーとして公開されること。

### 文書

- `scripts/manual/build.sh manual` と `manual-dev` が diagnostic を出さないこと。マニュアルの原稿の行頭に `@!` がないことは、`rg '^\s*@!' --glob '*.gm'` で確かめた。
- `adr-guard links` と textlint が通ること。

## トレードオフ

- 一つのラベルに一つの回復しか付けられないので、`@!` と式の中の `..` の後ろの誤りは、段落の終わりまで報告されない。記法ごとにラベルを分ければ回復を選べるが、ラベルとコードの一対一を崩すことになる。予約された記法は直せば消えるので、回復の粗さを受け入れる。
- メッセージを一つにしたので、`..` を書いた書き手に `...` を案内する文はメッセージに入らず、`golem explain` の「直し方」で読むことになる。記法ごとにメッセージを変えるには、`labelCode` が誤りの位置の文字を知る必要がある。
- 語の中の `..` は評価の段階で見つかるが、構文の区分のコード G01100 を使う。コードの上 2 桁は diagnostic を出す段階を表すが、「一つの原因に一つのコード」を優先する（[ADR 0102](0102-natural-number-type.md) と同じ判断）。
- 行頭の `@!` で始まる段落を書いていた原稿は、誤りになる。調べた範囲（リポジトリのマニュアル、fixture、テスト）にはなかった。

## 決めたことの記録

- **一つのコード**：メンテナーが、予約された記法を書いたときのコードを一つにし、`[!` と `..` で共有すると決めた。原因が「予約された記法を書いた」で同じだからである。
- **`@!` の予約**：メンテナーが決めた。どこで予約するか（ブロックコマンドを書ける行頭だけ）は、この版で決めた。
- **番号**：この版で、構文の区分の最初の新しい番号 G01100 を選んだ。[ADR 0113](0113-closed-range-literal.md) の G02105 から G02108 と G02110 とは区分が違う。

## 参考文献

- [docs/specifications.md](../specifications.md) の「意図的に採用しなかったもの」のマクロ
- [golem-parser ADR 0007](../golem-parser/adr/0007-grammar-label-safety.md)、[golem-parser ADR 0009](../golem-parser/adr/0009-syntax-diagnostic-codes.md)
- [ADR 0113](0113-closed-range-literal.md)、[ADR 0102](0102-natural-number-type.md)
