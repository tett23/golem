# ADR 0016: 行末の \ で段落の中の行を改める

ステータス: 採択→プレーンテキストの強制改行の後の行の字下げは [ADR 0049](0049-plain-text-indent-after-hard-break.md)

## 文脈

段落の中で、任意の位置で行を改める記法がない（[仕様書](../specifications.md)の「v1 の実装で次の段階以降に回した項目」の「強制改行」）。
空行の様式では、段落の中の改行は文字を生まず、前後の文字をそのままつなぐ（[markup.md](../markup.md) の「段落と改行」）。
改行の様式では、改行ひとつが段落の区切りになる（[docs/adr/0013](0013-paragraph-separator.md)）。
行を改めるのは、`line-breaks = "keep"` の段落スタイル（`@style verse` など）の段落の中だけである（[docs/adr/0005](0005-character-and-paragraph-styles.md)）。

住所、署名、手紙の結び、見出しのように組む段落の中の改行は、段落を分けずに行だけを改めたい。
InDesign では、Shift+Enter で入れる強制改行（英語版の Forced Line Break）がこれにあたる（記憶による）。
強制改行の後の行は同じ段落の行なので、段落スタイルの一行目の字下げは掛からず、段落前後のアキと孤立行の制御も一つの段落として扱われる（記憶による）。

### 今の処理

- 文法（`modules/golem-parser/grammar/Golem.peg`）の `Escape` は `'\\' ![\n] .` であり、`\` の直後が改行のときは合わない。`Text` は `\` を含まないので、行末の `\` は段落の規則に合わず、G01010（`このブロックを解釈できません`）になる。[docs/adr/0013](0013-paragraph-separator.md) は、この構文エラーを、段落一般の強制改行のために残すと決めた。
- 意味論 IR には、[docs/adr/0005](0005-character-and-paragraph-styles.md) が加えたインラインの `LineBreak`（タグ 17）がある。`Golem.Doc.Validate` は、`LineBreak` を `Paragraph` の最上位のインラインの列にだけ置け、列の先頭と末尾に置けず、二つ続けて置けないとする。今は `keep` の段落の行の区切りにだけ使われている。
- PDF（`Golem.Driver.Pdf.unitsOf`）は、段落を `LineBreak` で分け、部分ごとに `UPara` の単位にして、それぞれに段落の字下げを掛ける。`Golem.Layout.Japanese.piecesOf` は `LineBreak` を無視する（単位に分けた後に組むため）。
- HTML（`Golem.Html.block`）は、`keep` の段落か `LineBreak` を含む段落を、行ごとの `<span class="line">` と `<br/>` にする。
- プレーンテキスト（`Golem.Text`）は、`LineBreak` を改行と入れ子の字下げにする。

### 記法の候補

次の三つを比べた。

- 行末の `\`：CommonMark と Pandoc の hard line break と同じ書き方である。改行をエスケープして本文の改行にする、と読めば、`\` の後の文字を本文の文字にするエスケープの規則（[markup.md](../markup.md) の「エスケープ」）の延長になる。[docs/adr/0013](0013-paragraph-separator.md) も、この記法のために行末の `\` を構文エラーのまま残した。
- インラインのコマンド `[br]`：行の途中にも書け、改行を含まない見出しや表のセルにも書ける。ただし、意味論 IR の `LineBreak` は段落の最上位にしか置けないので、見出しとセルでは結局エラーになる。原稿の上で行が改まらないので、改めた位置が目で追いにくい。
- 行末の空白二つ（Markdown）：見えない文字に意味を持たせることになり、行末の空白を無視する今の規則（[golem-parser ADR 0006](../golem-parser/adr/0006-discard-insignificant-whitespace.md)）と衝突する。

行末の `\` を採る。

## 実装すること

### 記法

段落の行の末尾に `\` を書くと、その位置で行を改める。

```
〒100-0001\
東京都千代田区千代田1-1\
山田太郎様

Gold is for the mistress,\
silver for the maid.
```

- `\` は行の最後の文字でなければならない。`\` の後に空白を書くと、エスケープした空白（`\ `）と行末の空白になり、強制改行にならない。
- `\` の前の空白とタブは無視する（行末の空白と同じ扱い）。次の行の先頭の空白とタブも無視する。全角の空白（U+3000）は無視しない。
- `\` の次の行は、同じ段落の続きの行でなければならない。空行、ファイルの末尾、ブロックの始まりの文字（`#`、`- ` など）で始まる行が続くと、G01024 とする。
- 行末に本文の `\` を置きたいときは `\\` と書く。`\\` の後の改行は、ほかの改行と同じく段落の様式に従う。
- 二つの段落の様式のどちらでも、強制改行の意味は同じである。改行の様式では、`\` で終わる行と次の行が一つの段落になる。改行の様式で一つの段落を複数の行に分けて書く唯一の方法になる。
- `line-breaks = "keep"` の段落スタイルの段落では、改行がもともと行の区切りなので、行末の `\` は改行と同じ意味になる。行の区切りは一つだけ生じる。
- 散文スロットの中（`[note: a\` の後に改行など）では強制改行を書けない（G02056）。注の本文は一つの段落に限り（[仕様書](../specifications.md)の「複数段落の注」）、意味論 IR の `LineBreak` は段落の最上位にしか置けないためである。行をまたいで斜体などを続けたい場合は、韻文と同じく、行ごとにコマンドを閉じて開き直す。
- 強制改行で中身のない行ができる場合（段落の最初の行が `\` だけ、`\` だけの行が続く、`\` の次の行がコメントだけ）は G02057 とする。空の行で空きを作る用途は、アキの指定（[仕様書](../specifications.md)の「v1 の実装で次の段階以降に回した項目」）で扱う。
- 見出し、定義リストの用語、表のセルは一行で書く記法なので、強制改行を書けない。行末の `\` は G01024 になる。

### 文法（golem-parser）

`Golem.peg` に次の規則を加える。

```
%token Backslash

HardBreak(ind :: Int) :: ()
HardBreak <- Backslash LineContinuation(ind) { () }

Backslash :: ()
Backslash <- '\\' &'\n' { () }

# a backslash that escapes nothing: before a newline that does not continue
# the paragraph, or at the end of input
BadBreak :: ()
BadBreak <- '\\' (&{ False })^hard_break { () }
```

- `Inline` と `SlotInline` の選択肢の `Escape` の直後に `HardBreak(ind)` を、`BadBracket` の直後に `BadBreak` を加える。`Escape` は `\` の後に改行でない文字を求めるので、`HardBreak` と `BadBreak` に届くのは、`\` の直後が改行かファイルの末尾の場合だけである。
- `HeadInline` と `CellInline` の `BadBracket` の直後にも `BadBreak` を加える。見出し、用語、セルの行末の `\` を、G01010 ではなく G01024 にするためである。
- `HardBreak` は CST の節（`NHardBreak`）にする。`Golem.Parser.Convert` の節の名前の表に `"HardBreak" -> NHardBreak` を、トークンの表に `"Backslash" -> KBackslash` を加える。節は `\` のトークン、改行のトークン、次の行のインデント（トリビア）を持つので、CST から元のテキストを一字一句復元できるという不変条件（[golem-parser ADR 0001](../golem-parser/adr/0001-cst-types-and-invariants.md)）は保たれる。
- `Golem.Parser.labelCode` に `Just "hard_break" -> ("G01024", "行末の \\ は段落の中の強制改行です。次の行に段落の続きが要ります。本文の \\ は \\\\ と書きます")` を加える。G01024 は未使用である（構文の診断は G01023 と G01029 まで使い、G01024 から G01028 は空いている）。
- ラベル `hard_break` が安全であること（[golem-parser ADR 0007](../golem-parser/adr/0007-grammar-label-safety.md)）を `LabelSafetySpec` で確かめる。検査器が証明できなければ、`bracket` と同じ理由（`BadBreak` は失敗した後に同じ位置で続けられる選択肢を持たない）を書いて `%safe hard_break` を加える。

### AST（golem-parser）

- `Golem.Parser.AST.Inline` に `HardBreak` を加える。
- `Golem.Parser.Lower.inline` は、`NHardBreak` の節を `[Located sp HardBreak]` にする。位置は `\` から改行の終わりまでとする。節の中の改行は `SoftBreak` にしない。
- `trimEnds` は、`NHardBreak` の節の前を行末として扱い、その前の `Text` の末尾の空白とタブを取り除く。
- `NHardBreak` の直後の `Text` の先頭の空白とタブを取り除く（全角の空白は残す）。取り除いて空になった `Text` は捨てる。
- `inlines` の `dropEdgeBreaks` は `HardBreak` を取り除かない。段落の先頭の `HardBreak` は評価が G02057 とする。

AST の形が変わるので、golem-fmt の整形の前後で AST が一致するというプロパティテストの生成器にも、行末の `\` を加える。

### 評価（golem-eval）

- `joinSoftBreaks` と `nestedInline` は `HardBreak` を残す。取り除くのは `SoftBreak` だけである。
- [docs/adr/0013](0013-paragraph-separator.md) の `splitLines`（改行の様式で段落を分ける関数）は `SoftBreak` だけで分け、`HardBreak` では分けない。
- `evalBlock` の `A.Paragraph` は、今の `evalInlines` の代わりに `styledParagraph ctx sp Nothing is` を呼ぶ。リストの項目、定義リストの説明、図版のキャプション、本体の形の `@style` の段落が、同じ規則で強制改行を扱うためである。
- `styledParagraph` は次のようにする。
  - `join` の段落：最上位のインラインの列を `HardBreak` で行に分け、各行を `evalInlines` で評価して、行の間に `LineBreak`（位置は `HardBreak` の位置）を置く。評価した結果が空の行があれば、その行の位置で G02057 とし、その行と前の `LineBreak` を捨てる。すべての行が空なら、今と同じく空の段落を返す。
  - `keep` の段落：今の `splitLines`（`SoftBreak` で行に分ける関数）が、`HardBreak` でも行に分ける。空の行は今と同じく捨て、診断を出さない。`keep` の段落では、改行と行末の `\` が同じ意味だからである。
- `evalInline` の `A.HardBreak` は、段落の最上位の列ではない位置（散文スロットの中）でだけ評価される。G02056 とし、何も返さない。

| 診断コード | 重大度 | 条件 | メッセージ |
|---|---|---|---|
| G02056 | エラー | 散文スロットの中の強制改行 | `強制改行は段落の中にだけ書けます。コマンドの中では使えません` |
| G02057 | エラー | 強制改行で中身のない行ができる | `強制改行の前後に文字がありません` |

G02056 と G02057 は未使用である（golem-eval は [docs/adr/0014](0014-in-file-settings.md) の G02054 まで使い、G02055 は作業中の [docs/adr/0019](0019-aki-settings.md) が使う。origin/main のコードと docs の ADR、作業中の ADR に記載はない）。

### 意味論 IR（golem-doc）

変えない。
強制改行は、[docs/adr/0005](0005-character-and-paragraph-styles.md) の `LineBreak` で表す。
`Golem.Doc.Validate` の制約（段落の最上位にだけ置ける、先頭と末尾に置けない、二つ続けて置けない）は、評価の規則がそのまま満たす。
ABI の版も変えない。

同じ `LineBreak` が、`keep` の段落では韻文の行の区切りを、`join` の段落では強制改行を表す。
どちらの意味かは、段落スタイルの `line-breaks` で決まる。
`keep` の段落の行は、InDesign で韻文の一行を一つの段落として組むのと同じく、行ごとに一行目の字下げを掛ける。
`join` の段落の強制改行の後の行には、一行目の字下げを掛けない。

### PDF（golem-driver と golem-layout）

- `Golem.Driver.Pdf.unitsOf` は、解決した段落スタイルの `line-breaks` が `keep` の段落だけを、今と同じく `LineBreak` で単位に分ける。`join` の段落は、`LineBreak` を含んだまま一つの `UPara` の単位にする。行分割の L*(i)（`widthOf` と `lineIndent`）は、一行目にだけ `first-line-indent` を加えるので、強制改行の後の行は `indent` の位置から始まる。
- `Golem.Layout.Japanese` に部品 `PForcedBreak` を加え、`piecesOf` の `LineBreak` を `[PForcedBreak]` にする。`PForcedBreak` は、段落の末尾と同じ並び `[Penalty 0 infPenalty NoHyphen, Glue 0 filStretch 0, Penalty 0 (negate infPenalty) NoHyphen]` の項目になる。Knuth-Plass の行分割（`Golem.Layout.KnuthPlass`）は、罰点 -10000 以下の位置で必ず改行し、それより前の候補を捨てる（今の `forced` の扱い）。強制改行の前の行は、段落の最後の行と同じく、フィルのグルーで行末を空けて組まれる。
- 字間の調整（`normalize` の和欧間の空き、約物の詰め）は、`PForcedBreak` の前後を行の端として扱い、前後の文字の組で空きを入れない。段落の端と同じ扱いである。
- 孤立行の規則（[golem-layout ADR 0003](../golem-layout/adr/0003-pagination-and-s2.md)）は、強制改行を含む段落を一つの段落として扱う。一つの単位なので、追加の変更は要らない。
- `modules/golem-layout/test/Main.hs` の、`LineBreak` を無視することを確かめるテストは、強制の罰点の並びになることを確かめるテストに改める。

### HTML と EPUB（golem-html）

- `Golem.Html.block` は、`keep` の段落だけを行ごとの `<span class="line">` にする。`join` の段落の `LineBreak` は、インラインの `<br/>` として書く（今の `inlines` の `LineBreak` の出力）。
- `<span class="line">` にしないのは、`.line` が `display: block` であり、段落の `text-indent` が各行のブロックに継がれて、強制改行の後の行にも一行目の字下げが掛かるためである。`<br/>` なら、`text-indent` は段落の最初の行にだけ掛かる。
- リストの項目（`item`）が一つの段落だけを持つ場合に段落の `<p>` を省く条件 `not (any isLineBreak is)` は、`keep` の段落でないこと、に改める。
- EPUB は golem-html の出力を包むので、golem-epub は変えない。

### プレーンテキスト（golem-text）

変えない。
`LineBreak` は、今と同じく改行と入れ子の字下げになる。
段落の一行目の字下げ（`textFirstLine`）は最初の行にだけ掛かる。

### lint（golem-lint）

G05001（段落の中の改行の前後がともに欧文）は、強制改行の改行には当てない。
強制改行では単語はつながらないためである。
`latinJoinedByNewline` の `scan` は、`NHardBreak` の節の中に降りない。
改行のトークンは `NHardBreak` の子にあり、`scan` は段落の直下の改行のトークンだけを調べるので、今の走査のままで当たらないはずである。
テストで確かめる。

### fmt（golem-fmt）

コードは変えない。
`golem fmt` は改行の位置と行末の文字を変えない（[golem-fmt ADR 0001](../golem-fmt/adr/0001-formatter.md)）。
`\` の前の空白は AST に影響しないので、整形の前後で AST が一致するという不変条件は保たれる。

### LSP（golem-lsp）

コードは変えない。
G01024、G02056、G02057 は、構文と評価の診断として既存の経路で表示される。

### ドキュメント

- markup.md の「段落と改行」に「強制改行」の項を設け、上の記法の規則を書く。「エスケープ」の節に、行末の `\` は強制改行であり、本文の `\` を行末に置くには `\\` と書くことを加える。「韻文」の節に、`keep` の段落では行末の `\` が改行と同じ意味であることを一文で加える。
- 仕様書の「段落内の改行」に強制改行を書き、「v1 の実装で次の段階以降に回した項目」から「強制改行」を削る。
- docs/glossary.md の「原稿の記法」に「強制改行」の項目（段落を分けずに行を改めること。行末の `\` で書く）を加える。
- [docs/adr/0013](0013-paragraph-separator.md) のステータスの行を「採択→行末の `\` は docs/adr/0016」に変え、この ADR へのリンクを付ける。

## 実装しないこと

- 見出し、定義リストの用語、表のセルの中の強制改行。見出しの中の改行（「第一章」と題を二行に組むなど）は、見出しの番号の書式と行取りの設計に関わるので、見出しの拡張として扱う。
- 散文スロットの中（注、傍注、ルビ、文字スタイルなど）の強制改行。
- 強制改行で空の行を作ること。
- 行の途中に書ける強制改行のコマンド（`[br]`）。
- 段落の中の任意の位置で改段、改ページ、改フレームすること。改ページと改段はブロックの単位で [docs/adr/0017](0017-forced-page-breaks.md) が扱う。
- `keep` の段落の中の冗長な行末の `\` を lint で報告すること。
- 強制改行の後の行に、段落の一行目と別の字下げを指定する設定。

## テスト設計

先に書き、失敗させてから実装する。

### golem-parser（`test/ParserSpec.hs`、`test/LowerSpec.hs`、`test/Main.hs`）

- `"a\\\nb\n"` が診断なしに解析でき、AST が `Paragraph [Text "a", HardBreak, Text "b"]` になること。CST から元のテキストを復元できること。
- `"a  \\\n  b\n"` の AST が `Paragraph [Text "a", HardBreak, Text "b"]` になること。`"a\\\n　b\n"` の二つ目の `Text` が `"　b"` であること。
- `"a\\ \nb\n"` の AST が `Paragraph [Text "a ", SoftBreak, Text "b"]` になること（エスケープした空白）。
- `"a\\\\\nb\n"` の AST が `Paragraph [Text "a\\", SoftBreak, Text "b"]` になること。
- `"a\\\n\nb\n"`、`"a\\\n"`、`"a\\"`、`"a\\\n# h\n"` が G01024 になること。
- `"# h\\\n"` と `"| a\\\n|---|\n"` と `"= t\\\n  d\n"` が G01024 になること。
- `"[note: a\\\nb]\n"` が構文エラーなしに解析でき、散文スロットに `HardBreak` を持つこと。
- `labelCode` の表とラベルの一覧の双方向の検査（既存のテスト）が `hard_break` を含めて通ること。`LabelSafetySpec` が通ること。

### golem-eval（`test/FileSpec.hs`）

空行の様式と改行の様式の両方の文脈で確かめる。

- `"a\\\nb\n"` が `Paragraph Nothing [Text "a", LineBreak, Text "b"]` になること。
- 改行の様式で、`"a\\\nb\nc\n"` が二つの段落（`a` と `b` を `LineBreak` でつないだ段落と `c`）になること。
- 空行の様式で、`"a\\\nb\nc\n"` が `[Text "a", LineBreak, Text "bc"]` の一つの段落になること。
- `"@style verse\n  a\\\n  b\n"` が `[Text "a", LineBreak, Text "b"]` の一つの段落になり、`LineBreak` が一つだけであること。
- `"@style quote\na\\\nb\n"`（`quote` は `join`）が `Paragraph (Just "quote") [Text "a", LineBreak, Text "b"]` になること。
- `"- a\\\n  b\n"` の項目の段落が `LineBreak` を含むこと。
- `"@figure x.png alt=a\n  c1\\\n  c2\n"` のキャプションの段落が `LineBreak` を含むこと。
- `"[note: a\\\nb] c\n"` が G02056 になり、注の本文が `ab` になること。
- `"\\\na\n"`、`"a\\\n\\\nb\n"`、`"a\\\n%% c %%\nb\n"` が G02057 になり、結果の段落が `Golem.Doc.Validate` を通ること。
- 改行の様式で `"a\\\nb\n"` の `erSource` が改行の様式のままであること（[docs/adr/0013](0013-paragraph-separator.md) のテストとの共存）。

### golem-layout（`test/Main.hs`）

- `composeInlines env [sp0 "ab", LineBreak sp, sp0 "cd"]` の項目が、`ab` の箱、罰点 10000、フィルのグルー、罰点 -10000、`cd` の箱の順を含むこと。
- 行長に十分な余裕のある `[ab, LineBreak, cd]` を `breakParagraph` で分けると、二行になり、一行目が `ab` だけであること。
- `[ab, LineBreak, cd]` で、`a` と `b` を和文、`c` を欧文にしたとき、`b` と `c` のあいだに和欧間の空きが入らないこと。

### golem-driver（`test/Main.hs`）

- `[paragraph-styles.body] first-line-indent = "1zw"` のプロジェクトで、`"東京都\\\n千代田区\n"` の PDF の二行目の始まりが字下げされず、一行目だけが 1 字下がること。
- `[paragraph-styles.verse]` の既定の字下げで、`"@style verse\n  a\\\n  b\n"` の PDF の二行の始まりが今の韻文と同じ位置であること。
- ページの境界をまたぐ三行の段落（強制改行で三行にしたもの）で、最初の一行だけがページの末尾に残らないこと（孤立行の規則が一つの段落として働くこと）。
- HTML で、`"a\\\nb\n"` が `<p>a<br/>b</p>` になり、`<span class="line">` を含まないこと。`@style verse` の段落は今と同じく `<span class="line">` になること。
- 一つの段落だけの項目 `"- a\\\n  b\n"` の HTML が `<li>a<br/>b</li>` になること。
- プレーンテキストで、`"a\\\nb\n"` が `a` と `b` の二行になること。
- 既存の golden と、`scripts/determinism.sh` の sample の各ファイルのハッシュが、この ADR の前と変わらないこと。行末の `\` を使う原稿がないためである。

### golem-lint（`test/Main.hs`）

- `"Full fathom\\\nfive\n"` に G05001 が出ないこと。`"Full fathom\nfive\n"` には出ること。

### golem-fmt（`test/Main.hs`）

- golden に `"a\\\nb\n"` と `"- a\\\n  b\n"` を加え、整形で変わらないこと。

## トレードオフ

`LineBreak` の意味が段落スタイルの `line-breaks` で変わる。
`keep` の段落では行ごとに一行目の字下げが掛かり、`join` の段落では掛からない。
意味論 IR に強制改行と韻文の行の区切りを別のインラインとして持てば、媒体の側で段落スタイルを引かずに済むが、ABI の版を上げ、フィルタのプラグインに二つの改行を区別させることになる。
媒体の側は、すでに段落スタイルを引いて字下げと書体を決めているので、`line-breaks` を一緒に引くことは負担にならない。
代わりに、`keep` の段落の中で、強制改行（一行目の字下げを掛けない改行）を書く手段はない。
韻文の一行を折り返して組む場面では、行末の `\` も改行と同じく新しい韻文の行を始める。

行末の `\` は目立たない。
行末の空白を消すエディタの設定と組み合わせても壊れないが、`\` の後に空白を残すと強制改行にならず、エスケープした空白になる。
この場合は G01024 にも G05001 にもならず、行が改まらないだけなので、気づきにくい。
`\` の直後の空白を lint で警告することは、`\ ` をわざと行末に書く原稿（行末に空白を残したい場合）と区別できないので行わない。

改行の様式では、`\` が一つの段落を複数の行に分けて書く唯一の手段になる。
[docs/adr/0013](0013-paragraph-separator.md) は、行末の記号による継続（行を折り返して書くが、出力の行は改めない）を設けないと決めた。
行末の `\` は出力の行も改めるので、改行の様式で長い段落を見やすく折り返して書く用途には使えない。

散文スロットの中で強制改行を書けないので、注の本文の中で行を改めることはできない。
複数段落の注（v2 以降）と合わせて、注の本文を段落の列にするときに改めて検討する。
