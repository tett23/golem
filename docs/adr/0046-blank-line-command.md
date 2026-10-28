# ADR 0046: `@blank-line` で段落のあいだに行アキを入れる

ステータス: 採択→G07047 の重大度は [ADR 0104](0104-info-severity.md)

## 文脈

段落と段落のあいだに、一行や二行の空き（行アキ）を入れる記法がない。
小説の場面の区切りや、手紙の本文と署名のあいだのように、和文の本では行アキを原稿の任意の位置で指定する。
InDesign では、空の段落を入れるか、段落スタイルの「前のアキ」で入れる（記憶による）。

今の記法では、原稿の空行は空きを生まない。

- 空行の様式では、空行は段落の区切りであり、空行がいくつあっても段落の区切りが一つ生じるだけである（[markup.md](../markup.md) の「段落と改行」）。
- 改行の様式では、改行ひとつが段落の区切りであり、空行は無視される（[docs/adr/0013](0013-paragraph-separator.md)）。[docs/adr/0013](0013-paragraph-separator.md) は「実装しないこと」で、改行の様式で空行を空きとして残すことを見送り、行の空きは別の ADR で扱うとした。
- 行末の `\`（強制改行、[docs/adr/0016](0016-hard-line-breaks.md)）は段落の中で行を改める記法であり、中身のない行を作ると G02057 になる。[docs/adr/0016](0016-hard-line-breaks.md) は、空の行で空きを作る用途をアキの指定に回した。
- `[aki]`（[docs/adr/0019](0019-aki-settings.md)）は行の中の字間の空きであり、行と行のあいだの空きは作れない。
- 段落スタイルの `space-between` は、同じ段落スタイルの段落が続くときだけに空きの行を入れる（[docs/adr/0005](0005-character-and-paragraph-styles.md)）。原稿の一か所だけに空きを入れるには、その位置だけ別の段落スタイルを付けるしかない。

青空文庫の原稿では、空行が一行アキを表す。
改行の様式で青空文庫の形式の原稿を読むと、空行が無視されるので、原典の一行アキが出力から消える。
空行の様式で空行に空きの意味を持たせると、段落の区切りと空きの区別が空行の数に依存し、空行を一つ足すだけで出力が変わる。
空行の数を数える規則は、[golem-parser ADR 0003](../golem-parser/adr/0003-block-grammar.md) が空行を CST のトリビアとし、AST に残さないと決めたことにも反する。

メンテナーは、段落を区切るためのブロックコマンドを次のように指定した。

- 文書の最上位のどこにでも書ける。インラインのコマンドの中、リストの中などには書けない。
- 引数のない形は一行、`2` を付けた形は二行の空きを入れる。行の単位は、その位置の段落スタイルの行とする。
- PDF では、両端揃えなどの特別な処理をしない。
- HTML と EPUB でも表せる。
- プレーンテキストでは改行として出力する。
- 続けて書くと、お知らせを出す。
- 段の先頭に来た行アキは、`space-between` と同じく捨て、捨てたことをお知らせで知らせる。

### 今の処理

- 文法（`modules/golem-parser/grammar/Golem.hpeg`）では、行頭の `@` と英小文字はブロックの始まり（`BlockStart`）であり、段落の続きの行（`LineContinuation`）にならない。段落の直後の行に `@blank-line` と書くと、段落はその前で終わり、`@blank-line` は一般のブロックコマンド（`BlockGroup`）として読まれる。後に空行を挟まずに段落が続けば、その段落を対象にした属性のまとまりになる。
- 評価（`Golem.Eval.File` の `standalone`）は、知らない名前のブロックコマンドを G02009（`未知のブロックコマンドです`）とする。属性のまとまりの中では G02011 も出る。main の `golem` で、段落、知らない名前のブロックコマンド、段落の三行を `golem check` にかけ、G02011 と G02009 になることを確かめた。
- 意味論 IR には、段落のあいだの空きを表すブロックがない。`space-between` の空きは、PDF の経路だけが `Golem.Driver.Pdf` の `gapBefore` で `UGap` の単位にし、`Golem.Layout.Paginate` の `FSpace` にする。`FSpace` は段の先頭では空きを取らず、段の終わりで切り詰める。HTML は `space-between` を `p + p` の `margin-block-start` にする。
- 改ページ（[docs/adr/0017](0017-forced-page-breaks.md)）と改ページの手での制御（[docs/adr/0030](0030-manual-page-break-control.md)）は、最上位のブロック（`ForcedBreak`、`PageControl`）であり、属性のまとまりの中に書くと、まとまりの対象のブロックの直前に置かれる。

### 行の単位

段落スタイルは行送りの欄を持たない（[仕様書](../specifications.md) の「style.toml」の節）。
PDF の本文は、どの段落スタイルの段落も版面の行の格子に載る。
そのため、その位置の段落スタイルの一行は、PDF では行の格子の一行と同じになる。
HTML と EPUB では、段落スタイルの `size` を CSS に書かず（キャプションと傍注を除く）、行の高さを親から継ぐので、一行は本文の一行の高さになる。

### 名前

メンテナーは、起草の段階の名前 `@hardbreak` を `@blank-line` に改めると決めた。
`hardbreak` は、[docs/adr/0016](0016-hard-line-breaks.md) の強制改行（AST の `HardBreak`）と CommonMark の hard line break と同じ語であり、段落の中の改行と取り違えやすいためである。
`@blank-line` は、`@page-break` と `@column-break` と同じく、単位と動作をハイフンでつないだ形になる。
文書では機能の名前を「行アキ」とし、意味論 IR とコードの名前を `BlankLines` とする。

## 実装すること

### 記法

```
雪がやんだ。
@blank-line
翌朝、駅に着いた。

@blank-line 2
```

- `@blank-line` は一行、`@blank-line N` は N 行の行アキを、前後のブロックのあいだに入れる。
- N は 1 以上の整数の位置引数を一つだけとする。整数の範囲は [golem-doc ADR 0006](../golem-doc/adr/0006-integer-range-in-ir.md) と同じ（2 の 63 乗未満）である。`@need-lines` と同じく、整数の語だけを受け付ける。
- 0、負の数、小数、整数でない語、二つ以上の位置引数、キーワード引数、本体は G02092 とする。
- 文書の最上位にだけ置ける。リストの項目、定義リストの説明、ブロックコマンドの本体（`@figure` のキャプション）の中は G02093 とする。本体の形の `@style` の中は、ほかのブロックと同じく G02045 になる。
- 空行の様式と改行の様式のどちらでも、意味は同じである。段落の直後の行に空行を挟まずに書いてもよい。前後の空行は意味を持たない。
- 属性のまとまりの中に書いてよい。改ページと同じく、まとまりの中の位置によらず、行アキはまとまりの対象のブロックの直前に置かれ、`@label` などの属性は `@blank-line` を飛ばして対象のブロックに付く。

```
@blank-line
@label scene-2
# 二
```

- `@blank-line` には属性を付けられない。`@label x` の後に `@blank-line` だけが続いて対象のブロックがなければ、今と同じく G02010 になる。
- インラインの `[blank-line]` は設けない。今と同じく未知のインラインのコマンドの誤りになる。

### 続けて書いた場合

`@blank-line` を、ほかのブロックを挟まずに続けて書くと、二つ目以降の `@blank-line` の行にお知らせ G02094 を出す。
間に `@need-lines` か `@page-lines` か `@no-page-break` があっても、続けて書いたものとみなす（G02072 と同じ数え方）。
行アキの量は足し合わせる。
`@blank-line` と `@blank-line 2` が続けば、三行の行アキになる。
組んだ結果は変わらないので、エラーにはしない。
一つの `@blank-line N` にまとめて書けることを知らせる。

判定はファイルごとに行う。
ファイルの末尾の `@blank-line` と、次のファイルの先頭の `@blank-line` は、続けて書いたものとみなさない。

### 段の先頭の行アキ

PDF で段の先頭に来た行アキは、空きを取らずに捨て、お知らせ G07047 を出す。
`space-between` の空き（`FSpace`）と同じ規則である。
段の先頭の空きは、前の段の終わりの余白と見分けられず、行アキの役目（前後の段落の区切り）を果たさないためである。
書き手の入力と違う出力になるので、黙って捨てずに知らせる（[仕様書](../specifications.md) の「設計原則」の「緩い規則より厳しい規則」）。

段の先頭は、どのようにしてそこに来たかによらず同じに扱う。

- 前の段落が段の最後の行で終わった。
- 行アキと次のブロックの最初の部分が今の段に入らず、次の段へ送った（下の「PDF」）。
- 改ページ（`@page-break`、`@column-break`）、改丁する見出し、`@need-lines` で段を改めた直後である。
- 本の最初のブロックの前である。

改ページの直後の行アキも捨てる。
改ページの後の本文を数行下げて始める用途は、行アキでは扱わない（「実装しないこと」）。
改ページを書いた位置で段の先頭が決まる場合だけ例外にすると、同じ `@blank-line` が、前に `@page-break` があるかどうかで空きを取ったり取らなかったりし、規則が二つになる。

G07047 は、今の重大度の中ではお知らせとする。
ロードマップの「diagnostic の info」（[docs/roadmap.md](../roadmap.md)）で notice より下の info を設けたら、G07047 を info に移す予定である。
段の先頭の行アキを捨てることは組版の通常の結果であり、書き手が直す必要があるとは限らないためである。
移すかどうかは、info を設ける ADR で決める。

### 改ページとの組み合わせ

- `@blank-line` の直後に、ほかのブロックを挟まずに `@page-break` か `@column-break` が続くと警告 G04010 を出し、その行アキをすべての出力で捨てる。間に `@need-lines`、`@page-lines`、ほかの `@blank-line` があっても同じ位置とみなす。ファイルの境界をまたぐ組み合わせ（ファイルの末尾の `@blank-line` と、次のファイルの先頭の `@page-break`）も検出するため、本の全体を見る文書の組み立て（`Golem.Doc.Assemble`）で判定する。
- 改ページの直後（間に `@need-lines`、`@page-lines`、`@no-page-break`、ほかの `@blank-line` しかない位置）の `@blank-line` は、誤りにしない。PDF では段の先頭で捨て、G07047 を出す。
- 本の最後のブロックの後に `@blank-line` しかない場合は、行アキを捨て、お知らせ G04009 を出す。本の最後の改ページ（G04008）と同じ扱いである。ファイルの末尾の `@blank-line` は、次のファイルの最初のブロックの前に置かれる。

G04010 を残す理由は次のとおりである。
行アキは次のブロックの前に置くので、改ページの前に書いた行アキは、PDF では必ず改ページの後の段の先頭に移って捨てられる。
一方、HTML と EPUB とプレーンテキストは書いた順に出力するので、改ページの前に空きが出る。
改ページの前の行アキは PDF で効果がなく、そのままでは媒体のあいだで結果も食い違う。
そこで、書いた時点で警告で知らせ、HTML と EPUB とプレーンテキストでもその行アキを捨てて、媒体の結果をそろえる。
メンテナーは、これを誤りではなく警告にすると決めた。
改ページの後の行アキは、HTML と EPUB とプレーンテキストでも出力しない（下の各節）ので、媒体のあいだで食い違わず、お知らせで足りる。

### 意味論 IR（golem-doc）

CDDL（`modules/golem-doc/schema/golem-doc.cddl`）にブロックを加える。

```
block-body =
    ...
  / [13, lines: 1..9223372036854775807]            ; blank lines before what follows (docs/adr ADR 0046)
```

```haskell
data BlockBody
  = ...
  | -- | blank lines before what follows (docs/adr ADR 0046)
    BlankLines !Int64
```

- `Golem.Doc.Cbor`：タグ 13 の符号化と復号。
- `Golem.Doc.Validate`：`BlankLines` は文書の最上位のブロックの列にだけ置け、行数は 1 以上である。ラベルを持てない。フィルタのプラグインが別の位置に置いた場合も、ここで誤りになる。
- `Golem.Doc.Assemble`、`Golem.Plugin`、`noRuby` などブロックを走査するすべての関数に、何も持たないブロックとして `BlankLines` の場合を加える。目次、索引、図番号、見出しの番号は数えない。
- `Golem.Doc.Assemble` で G04009 と G04010 を判定する。
- ABI のバージョンは 7 のままとする。7 はまだリリースしていないためである。この ADR を実装する前に ABI 7 を含むバージョンをリリースした場合は、ABI のバージョンを一つ上げる。

`ForcedBreak` と `PageControl` を使わず、別のブロックにする。
行アキは HTML、EPUB、プレーンテキストにも出力するので、PDF だけの指定である `PageControl` には入れない。
改ページの種類（`BreakKind`）とも、量を持つ点で異なる。
行数は行の格子の行数という抽象的な数であり、ページの大きさや位置ではないので、幾何の隔離（[仕様書](../specifications.md) の「設計原則」）に反しない。

### 評価（golem-eval）

- `standalone` に `"blank-line"` を加え、引数を検査して `BlankLines` のブロックを一つ返す。誤りは G02092 とし、何も返さない。
- `isBreakCommand` に `"blank-line"` を加える。属性のまとまりの中の `@blank-line` は、改ページと同じく対象のブロックの直前に置かれる。
- 文書の最上位でない `BlankLines` は、改ページの G02059 と同じく、評価の後にブロックの木を走査して取り除き、G02093 とする。
- 最上位のブロックの列で、`BlankLines` のあいだに `PageControl` だけがある組を探し、後の `BlankLines` の位置に G02094 を出す。
- G02094 を golem-syntax の `noticeCodes` に加える。

### PDF（golem-driver と golem-layout）

行アキは、次に置くもの（行、見出し、図版、表など）の前の、行の格子の空きの行である。
次に置くものの最初の部分と同じ段に置く。

- `Golem.Driver.Pdf` の `UnitKind` に `UBlank !Int64` を加え、`unitsOf` は `BlankLines n` を `UBlank n` にする。単位を `Flow` に写すところで `FBlank sp n` にする（`sp` は G07047 の位置）。
- `gapBefore` は、間に行アキを挟んだ二つの段落を、続いた段落として扱わない。`before` は `BlankLines` を飛ばさない。`space-between` の空きと行アキは足さず、行アキだけが入る。改ページを挟んだ段落と同じ扱いである。
- `Golem.Layout.Paginate.Flow` に `FBlank !SrcSpan !Int` を加える。`St` に、まだ置いていない行アキ `sBlank :: ![(SrcSpan, Int)]` を加え、`FBlank` は `sBlank` に足すだけにする。
- 改ページと改ページの手での制御以外のものを置く直前に、次の順で処理する。
  1. 今の `ready`（改ページの印、`@need-lines` の順に適用）。`@need-lines` の判定に行アキの行数は数えない。
  2. 置くものが `page-break = "recto"` の見出しなら、見出しの改ページの規則（`rectoStart`）。
  3. 今の段が空でなく、行アキの行数の和と、置くものの最初の部分（`nextNeed`）の和が今の段の残りに入らなければ、次の段へ進む。
  4. 今の段が空（段の先頭）なら、行アキを捨て、ためた `@blank-line` ごとに G07047 に当たる記録を残す。空でなければ、行アキの行数だけ行の格子の行を空ける。
  5. 置くものを今の規則で置く。
- 3 で次の段へ進めば、4 で行アキは必ず捨てられる。行アキが段に入りきらない場合も同じ規則で捨てるので、行アキを途中で切り詰めることはない。
- `nextNeed` は、`FBlank` の後のものの量に、その行数を足す。見出しの後に行アキと段落が続けば、見出しは行アキと段落の最初の 2 行と同じ段に置かれる（[golem-driver ADR 0032](../golem-driver/adr/0032-default-heading-styles.md)）。足した量は段の行の格子の数を上限とする。
- `@no-page-break` の後の部分の量（`keptNeed`）も、行アキを飛ばさずに数える。前のブロックの最後の部分、行アキ、後のブロックの最初の部分が同じ段に入らなければ、今の規則のとおり G07037 になる。行アキを置いたことは、`@no-page-break` が待つものを置いたことにならない（今の `FSpace` と同じ）。
- 本の最後に残った `sBlank` は捨てる（G04009 は文書の組み立てで出している）。
- 表の前の一行の空き（`ftSpaceBefore`）は、行アキの後でも今のとおり取る。行アキは書き手が指定した空きであり、表の空きの代わりにしない。今の `FSpace` の後の表の空きを 0 にする規則は、`FBlank` には当てない。
- コードブロックの直後の行のルビと圏点のための空きの行（[golem-driver ADR 0033](../golem-driver/adr/0033-ruby-after-code-block.md)）は、コードブロックの直後に行アキがあれば足さない。行アキが空きの行になるからである。
- 段組み、縦組みでも同じ規則とする。縦組みの一行は縦の行であり、行アキは行の進む方向（左）に空く。
- 前の段落の最後の行の組み方（両端揃え、行末の約物）は変えない。行アキは段落の外にあるので、行分割、禁則、ルビの規則に関わらない。
- `Golem.Driver.Pdf` は、G07047 に当たる記録を、`@blank-line` の行を位置とするお知らせにする。G07037 の未達の記録と同じ経路である。

### HTML と EPUB（golem-html）

行アキを、行数と同じ数の `<br/>` を持つ空の `div` で書く。

```html
<p>雪がやんだ。</p>
<div class="blank-line"><br/><br/></div>
<p>翌朝、駅に着いた。</p>
```

- `<br/>` 一つが、継いだ行の高さの一行の行ボックスを作る。CSS の単位（`lh` など）と `style.css` の規則が要らず、読書環境の文字の大きさと行の高さに従う。電書協の EPUB 3 制作ガイドの空行（`<p><br/></p>`）と同じ考え方である（記憶による）。
- `p` ではなく `div` にするのは、段落スタイルの CSS（`p:not([class])` の字下げなど）を受けないためである。`p + p` の `space-between` の規則も、間に `div` があれば当たらないので、PDF と同じく行アキだけが入る。
- 文書（XHTML）の最初のブロックの前、改ページ（`ForcedBreak`）の直後（間に `PageControl` と `BlankLines` しかない位置）、文書の最後のブロックの後の行アキは、何も出力しない。前の二つは、EPUB の読書環境でページの先頭に来ることが決まっている位置であり、PDF の段の先頭の規則に合わせる。最後の一つは、EPUB の読書環境が文書の境界で改ページし、文書の末尾の空きが見えないためである。改ページの `data-break-before` は、今のとおり次のブロックの要素に付く。
- それ以外の位置で、読書環境がページの先頭に置いた行アキは、そのまま空く。リフローの媒体ではページの先頭が組むときに決まらないためである。
- EPUB は golem-html の出力を包むので、golem-epub は変えない。

### プレーンテキスト（golem-text）

行アキの行数だけ空行を足す。
ブロックのあいだの空行は今は一つなので、`@blank-line N` を挟んだ二つのブロックのあいだは、1 + N 行の空行になる。
文書の最初のブロックの前、改ページの直後、文書の最後のブロックの後の行アキは、HTML と同じく何も出力しない。

### lint（golem-lint）

規則は加えない。
続けて書いた `@blank-line` は、評価のお知らせ G02094 が扱う。

### fmt（golem-fmt）

コードは変えない。
`@blank-line` はほかのブロックコマンドと同じく、行と引数の空白だけを整える。
続けて書いた `@blank-line` を一つにまとめる書き換えはしない。
整形は改行の位置と行の数を変えないためである（[golem-fmt ADR 0001](../golem-fmt/adr/0001-formatter.md)）。

### LSP（golem-lsp）

コードは変えない。
G02092、G02093、G02094、G04009、G04010 は、評価と文書の組み立ての diagnostic として既存の経路で表示される。
G07047 はレイアウトの diagnostic なので、LSP での扱いは G07037 などほかのレイアウトの diagnostic と同じにする。
`@blank-line` の引数の補完は加えない。
整数を書くだけであり、`@page-lines` の `+1` と `-1` のような決まった候補がないためである。

### diagnostic

| コード | 重大度 | 条件 | メッセージ | 段階 |
|---|---|---|---|---|
| G02092 | エラー | `@blank-line` の引数か本体の誤り | `@blank-line の引数は 1 以上の整数を一つだけ書きます`、`@blank-line は本体を持てません` | 評価 |
| G02093 | エラー | 文書の最上位でない位置の `@blank-line` | `@blank-line は文書の最上位にだけ置けます` | 評価 |
| G02094 | お知らせ | `@blank-line` を続けて書いた | `続けて書いた @blank-line は @blank-line <N> にまとめて書けます` | 評価 |
| G04009 | お知らせ | 本の最後の行アキ | `本の最後の @blank-line は効果がありません` | 文書の組み立て |
| G04010 | 警告 | `@blank-line` の直後の改ページ | `@blank-line の直後に @page-break があります`、`@blank-line の直後に @column-break があります` | 文書の組み立て |
| G07047 | お知らせ | PDF で段の先頭に来た行アキを捨てた | `段の先頭に来た @blank-line の空きを捨てました` | レイアウト |

位置は、どれも `@blank-line` の行とする。
G04009 は本の最後の `@blank-line`、G07047 は捨てた行アキの `@blank-line` の行である。
続けて書いた `@blank-line` が段の先頭で捨てられれば、G07047 はそれぞれの行に出す。
G02094、G04009、G07047 を `noticeCodes` に加え、`manifest.toml` の `silence-notices` で抑えられるようにする。

番号は次のとおり未使用である。

- G02092 から G02094：評価の区分（02）は G02091 まで、使用中のコードか作業中の草稿が使う。origin の各ブランチと作業中の worktree の docs とコードに G02092 から G02094 の記載はない。
- G04009 と G04010：文書の組み立ての区分（04）は G04008 まで使っている。
- G07047：レイアウトの区分（07）は G07046 まで使い、G07050 から G07052 は別の用途に使っている。G07038 と G07039 は作業中の草稿が使う。

並行する草稿が同じ番号を取っていれば、実装の順にずらす。

## 実装しないこと

- 段落の中の行アキ（行末の `\` を続けて書いて空の行を作ること）。今と同じく G02057 とする。
- 文書の最上位でない位置（リストの項目、定義リストの説明、図版のキャプション、注の本文）の行アキ。項目のあいだを空ける用途は、リストのスタイルの設定として別に扱う。
- インラインの `[blank-line]`。
- 行の格子の一行より細かい量（`@blank-line 0.5`）の空き。PDF の本文は行の格子に載るので、半行の空きは後の行を格子からずらす。
- 空行の数で行アキを表す記法。空行は今と同じく段落の区切りであり、空きを生まない。
- 改ページの後の本文を数行下げて始めること（扉の後の本文の位置など）。段の先頭の行アキは捨てるので、`@blank-line` では書けない。見出しの `lines` か、別の ADR の指定で扱う。
- 段の先頭で捨てた行アキを、印（＊など）に置き換えること。場面の区切りを印で示すかは編集の判断であり、原稿に印を書けば足りる。
- 青空文庫の形式から変換するスクリプト（`scripts/fixtures/aozora_to_gm.py`）が、原典の空行を `@blank-line` に変えること。fixture の出力が変わるので、別の作業で扱う。
- 続けて書いた `@blank-line` を `golem fmt` で一つにまとめること。
- PDF で、行アキの前の段落の最後の行を特別に組むこと。
- G07047 の重大度を info にすること。info の重大度はまだない。

## テスト設計

先に書き、失敗させてから実装する。

### golem-parser（`test/ParserSpec.hs`）

文法は変えない。
今の振る舞いを固定するテストを加える。

- `"あ\n@blank-line\nい\n"` が diagnostic なしに解析でき、AST が `Paragraph`、`@blank-line` と段落 `い` の属性のまとまり、の順になること。
- 段落の続きの行の途中の `@blank-line` が、段落の文字にならないこと。

### golem-eval（`test/FileSpec.hs`）

空行の様式と改行の様式の両方で確かめる。

- `"あ\n@blank-line\nい\n"` が `[Paragraph あ, BlankLines 1, Paragraph い]` になること。
- `"あ\n\n@blank-line 2\n\nい\n"` が `[Paragraph あ, BlankLines 2, Paragraph い]` になること。
- `@blank-line 0`、`@blank-line -1`、`@blank-line 1.5`、`@blank-line x`、`@blank-line 1 2`、`@blank-line lines=2`、本体を持つ `@blank-line` が G02092 になり、ブロックを返さないこと。
- `"- あ\n\n  @blank-line\n  い\n"` と `"@figure x.png alt=a\n  c\n\n  @blank-line\n"` が G02093 になり、IR に `BlankLines` が残らないこと。
- `"@style verse\n  あ\n\n  @blank-line\n"` が G02045 になること。
- `"@blank-line\n@label x\n# 見出し\n"` が `[BlankLines 1, Heading（ラベル x）]` になること。`"@label x\n@blank-line\n# 見出し\n"` も同じになること。
- `"@blank-line\n@blank-line 2\nあ\n"` が二つ目の `@blank-line` の位置に G02094 を出し、IR が `[BlankLines 1, BlankLines 2, Paragraph あ]` になること。
- `"@blank-line\n@need-lines 3\n@blank-line\nあ\n"` が G02094 を出すこと。`"@blank-line\nあ\n@blank-line\nい\n"` が G02094 を出さないこと。
- G02094 の重大度がお知らせであること。

### golem-doc（`test/`）

- `BlankLines 1` と `BlankLines 9223372036854775807` が CBOR で往復すること。タグが 13 であること。
- `Golem.Doc.Validate` が、行数 0 の `BlankLines`、リストの項目の中の `BlankLines`、ラベルを持つ `BlankLines` を誤りとすること。
- 本の最後のファイルの末尾の `BlankLines` に G04009 が出ること。後に改ページだけがある場合も同じであること。
- `[BlankLines 1, ForcedBreak BreakPage]` と `[BlankLines 1, PageControl (NeedLines 3), ForcedBreak BreakColumn]` が G04010 になること。一つ目のファイルが `BlankLines` で終わり、二つ目のファイルが `ForcedBreak` で始まる場合も G04010 になること。`[ForcedBreak BreakPage, BlankLines 1, 段落]` が誤りにならないこと。

### golem-layout（`test/Main.hs`）

行の格子が 10 行の一段の版面で確かめる。

- 三行の段落、`FBlank 2`、二行の段落を流すと、二つ目の段落が 6 行目から始まり、未達の記録がないこと。
- 九行の段落、`FBlank 1`、三行の段落を流すと、10 行目に行アキと次の段落の最初の 2 行が入らないので、次のページの 1 行目から段落が始まり、G07047 に当たる記録が一つできること。
- 十行の段落、`FBlank 1`、段落を流すと、次のページの 1 行目から段落が始まり、G07047 に当たる記録が一つできること。
- `FBreak BreakPage`、`FBlank 3`、段落を流すと、新しいページの 1 行目から段落が始まり、G07047 に当たる記録が一つできること。
- 本の先頭の `FBlank 2` と段落で、段落が 1 行目から始まり、G07047 に当たる記録が一つできること。
- `FBlank 1`、`FBlank 2`、段落を段の先頭で流すと、G07047 に当たる記録が二つできること。
- 三行の段落、`FBlank 20`、段落を流すと、次のページの 1 行目から段落が始まり、行アキが切り詰められずに捨てられること。
- `page-break = "recto"` の見出しの前の `FBlank 2` が、改めた後の奇数ページの先頭で捨てられ、偶数ページに行アキだけが残らないこと。
- 見出し、`FBlank 2`、段落の並びで、見出しが行アキと段落の最初の 2 行と同じ段に置かれること。
- `FNoBreak`、`FBlank 1`、段落の並びで、前の段落の最後の部分、行アキ、後の段落の最初の 2 行が同じ段に置かれること。
- `FBlank 1` の後の表が、今のとおり一行の空きを取ること。

### golem-driver（`test/Main.hs`）

- `"あ\n@blank-line 2\nい\n"` の PDF で、`い` の行が `あ` の行から 3 行分後の格子の行にあること。横組みと縦組みの両方で確かめる。
- 段の先頭に来る `@blank-line` を含む原稿の `golem build` が、G07047 のお知らせを `@blank-line` の行の位置で出すこと。`silence-notices = ["G07047"]` で出なくなること。
- `"@style verse\n  あ\n\n@blank-line\n\n@style verse\n  い\n"`（`space-between = 1`）の PDF で、二つの連のあいだが 1 行であり、2 行にならないこと。
- コードブロック（背景あり）、`@blank-line`、ルビを持つ段落の並びで、コードブロックの後に足す空きの行が加わらないこと。
- HTML で、`"あ\n@blank-line 2\nい\n"` が `<p>あ</p>`、`<div class="blank-line"><br/><br/></div>`、`<p>い</p>` の順になること。
- HTML で、ファイルの先頭の `@blank-line`、`"@page-break\n@blank-line\nあ\n"` の `@blank-line`、ファイルの末尾の `@blank-line` が何も出力しないこと。`"@page-break\n@blank-line\nあ\n"` の `<p>` に `data-break-before="page"` が付くこと。
- プレーンテキストで、`"あ\n@blank-line 2\nい\n"` が `あ`、空行三つ、`い` になること。ファイルの先頭と末尾の `@blank-line` が何も出力しないこと。
- 既存の golden と、`scripts/determinism.sh` の sample の各ファイルのハッシュが、この ADR の前と変わらないこと。`@blank-line` を使う原稿がないためである。

### golem-syntax と docs の一致

- `noticeCodes` が G02094、G04009、G07047 を含み、docs/diagnostics.md の重大度と一致すること（既存の golem-driver のテスト）。

### golem-fmt（`test/Main.hs`）

- golden に `"あ\n@blank-line\nい\n"` と `"@blank-line  2\n"` を加え、前者は変わらず、後者は引数の前の空白が一つになること。

## トレードオフ

段の先頭の行アキを捨てるので、小説の場面の区切りがページの境目に来ると、区切りが PDF から消える。
次のページの一行目を空ける案もあったが、段の先頭の空きは前の段の終わりの余白と見分けられず、読者には区切りとして伝わらない。
`space-between` と規則をそろえ、捨てたことを G07047 で知らせる。
区切りを必ず見せたい場合は、書き手が＊などの印を原稿に書くか、`@page-lines` などで改ページの位置を変える。

改ページの直後の行アキも捨てるので、改ページの後の本文を数行下げて始める用途は `@blank-line` で書けない。
例外を設けると、同じ `@blank-line` の振る舞いが、前のブロックの種類によって変わる。
一つの規則にすることを取り、その用途は別の指定に回した。

行アキを、前のブロックの後ではなく、次のブロックの前に付けた。
前に付けると、段の終わりで行アキの一部だけが残り、残りが次の段の先頭で捨てられて、行アキの量が位置によって変わる。
次に付ければ、行アキは全体が置かれるか全体が捨てられるかのどちらかになる。
代わりに、改ページの前に書いた行アキは必ず捨てられるので、警告（G04010）を出してすべての出力で捨てることにした。

HTML と EPUB は、ページの先頭が組むときに決まらないので、PDF と同じ規則を当てられない。
文書の先頭と改ページの直後の行アキだけを出力せず、PDF で必ず捨てられる位置と合わせた。
それ以外の位置で、読書環境のページの先頭に来た行アキは空いたまま残る。

`space-between` と行アキを足さず、行アキだけを入れる。
同じ段落スタイルの連のあいだに `@blank-line` を書くと、`space-between = 1` の `verse` では空きが変わらない。
連のあいだを広げるには `@blank-line 2` と書く必要がある。
足し合わせる規則にすると、`@blank-line` の量が前後の段落スタイルに依存し、原稿だけを見て空きの行数が分からなくなる。

G07047 は、段の先頭で行アキを捨てるたびに出る。
場面の区切りの多い小説では、お知らせが本の中で何度も出うる。
`silence-notices` で抑えられ、info の重大度ができれば info に移す予定なので、ふだんの出力を埋めることは一時的である。

## ドキュメント

- markup.md の「ブロックコマンド」の一覧に `@blank-line` を加え、「改ページ」の節の前に「行アキ」の節を設けて、記法、置ける位置、続けて書いた場合、段の先頭での扱い、改ページとの組み合わせを書く。「段落と改行」の節に、空行は空きを生まず、行アキは `@blank-line` で書くことを一文で加える。
- 仕様書の「段落内の改行」の節の後に「行アキ」の節を設け、意味論 IR の `BlankLines`、PDF の置き方と段の先頭の規則、HTML と EPUB とプレーンテキストの出力を書く。意味論 IR のブロックの一覧に `BlankLines` を加える。
- docs/diagnostics.md に G02092、G02093、G02094、G04009、G04010、G07047 の節を加え、「使っていない番号」を改める。G07047 の節に、info の重大度ができたら移す予定であることを書く。
- docs/glossary.md の「原稿の記法」に「行アキ」の項目（段落のあいだに行の格子の行を単位とする空きを入れること。`@blank-line` で書く）を加える。
- docs/roadmap.md の「diagnostic の info」の項目に、info に移す候補として G07047 を加える。
- [docs/adr/0013](0013-paragraph-separator.md) のステータスの行は変えない。[docs/adr/0013](0013-paragraph-separator.md) が見送ったのは空行を空きとして残すことであり、この ADR も空行に意味を持たせないためである。

## 未決事項

なし。
名前（`@blank-line`）と段の先頭の扱い（捨ててお知らせを出す）は、起草の後にメンテナーが決めた。

## 参考文献

- [docs/adr/0005](0005-character-and-paragraph-styles.md)（段落スタイルの `space-between`）
- [docs/adr/0013](0013-paragraph-separator.md)（段落の区切り方）
- [docs/adr/0016](0016-hard-line-breaks.md)（行末の `\` の強制改行）
- [docs/adr/0017](0017-forced-page-breaks.md)（改ページ、改段）
- [docs/adr/0019](0019-aki-settings.md)（アキの指定）
- [docs/adr/0030](0030-manual-page-break-control.md)（改ページの手での制御）
- [golem-parser ADR 0003](../golem-parser/adr/0003-block-grammar.md)（ブロックの文法）
- [golem-doc ADR 0006](../golem-doc/adr/0006-integer-range-in-ir.md)（IR の整数の範囲）
- [golem-driver ADR 0032](../golem-driver/adr/0032-default-heading-styles.md)（見出しを後と離さない規則）
- [golem-driver ADR 0033](../golem-driver/adr/0033-ruby-after-code-block.md)（コードブロックの後の空きの行）
- [golem-fmt ADR 0001](../golem-fmt/adr/0001-formatter.md)（整形の規則）
- [golem-syntax ADR 0002](../golem-syntax/adr/0002-notice-severity.md)（お知らせの重大度）
- [docs/roadmap.md](../roadmap.md)（diagnostic の info）
- 日本語組版処理の要件（JLReq）、W3C Working Group Note。行の格子と行送りの考え方。
- CommonMark Spec、Hard line breaks の節。
- 『電書協 EPUB 3 制作ガイド』。空行の書き方（記憶による）。
