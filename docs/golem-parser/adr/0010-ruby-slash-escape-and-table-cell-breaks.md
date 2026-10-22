# ADR 0010: エスケープした文字を AST に残すことと、表の行末の `\`

ステータス: 採択

## 文脈

v1 の実装の後、原稿の記法の仕様と実装が食い違う箇所が二つ見つかった。
どちらも、エスケープの情報が必要な段階まで届いていないことが原因である。

### ルビの中の `\/`

docs/markup.md の「エスケープ」は、エスケープの要る位置に「ルビの中の `/`」を挙げている。
`[ruby: a\/b|えー]` と書けば、親文字「a/b」の全体に「えー」を振るグループルビになるはずである。
実際には G02015（モノルビの対象と読みのセグメントの数が一致しません）になる。
マニュアルの付録A を書くときに見つかった。

経路を追うと、エスケープは評価に届く前に消えている。

1. 文法（`modules/golem-parser/grammar/Golem.hpeg`）の `Escape <- '\\' ![\n] .` は、`\/` を一つの `Escape` の字句にする。
2. `Golem.Parser.Lower.inline` は、`KEscape` の字句を、`\` を除いた `Text "/"` にする。`mergeText` が隣の `Text` とつなぐので、`a\/b` は AST では `Text "a/b"` になる。
3. golem-eval の `Golem.Eval.File.ruby` は、評価した親文字を `splitSegments` で、読みを `T.splitOn "/"` で、どちらも文字列の `/` で区切る。

評価の段階では、`/` が原稿で `\/` と書かれたのか `/` と書かれたのかを区別できない。
[golem-parser ADR 0004](0004-inline-grammar.md) は、ルビの `/` による区切りを文法で扱わないと決めている。

同じ問題は `index` にもある。
`Golem.Eval.File` の `index` は、評価した語を `T.splitOn "/"` で段に分ける。
`[index reading=えー: a\/b]` は、語「a/b」の一段の項目にならず、語が二段で読みが一段なので G02042 になる。
docs/markup.md の「エスケープ」は索引の `/` を挙げていないが、区切りの `/` を文字として書けないことは同じである。

### この ADR の草案での案と、所有者の指摘

この ADR の最初の草案は、`Lower` がコマンドの名前 `ruby` のときだけスロットを `/` で分け、AST に `RubySeparator` の構成子を置く案だった。
所有者は、`Lower` がコマンドの名前を知らずに解けないかを問うた。
`Lower` は構文の層であり、どのコマンドがどの文字を区切りに使うかは評価の規則である。
上のとおり `index` も `/` を使うので、名前の一覧はすでに二つになる。

最初の草案は、エスケープ一般を AST に残す案を、行頭と行末の空白の扱いが変わるとして退けていた。
コードを読み直すと、この理由は当たらない。
`Lower` の `trimEnds` と `trimStart` は、AST を作る前に CST の字句の上で働き、エスケープは別の字句（`KEscape`）なので、今も除かれない。
評価の側の `trimLine` と `splitParagraph` は、エスケープを `Text` に戻してから働かせれば、今と同じ結果になる。

### エスケープの情報を今使っている箇所

評価には、エスケープの情報を位置から推し量っている箇所が一つある。
G02064（`keep` の段落の行頭のエスケープした空白）は、行の最初の `Text` の文字列が、その位置の幅より 1 バイト短いことで、エスケープを見分けている（`Golem.Eval.File` の `escapedIndent`）。
`Text` の文字列がエスケープを含むとき、位置の幅と文字列の長さが食い違うことを利用した判定である。

### 表の行末の `\`

[docs/adr/0016](../../adr/0016-hard-line-breaks.md) は、見出し、定義リストの用語、表のセルの行末の `\` を G01024 にすると定めた。
見出しと用語では G01024 になるが、表では次のようになる（v1 の `golem check` で確かめた）。

| 原稿 | 結果 |
| --- | --- |
| 見出しの行が `\| a \| b \|\` で終わる表 | G01010（このブロックを解釈できません）が表の 1 行目に出る |
| 本文の行が `\| c \| d \|\` で終わる表 | G01010 が表の 1 行目に出る |
| 本文の行が `\| c \| d \` で終わる表（閉じる `\|` がない） | G01015（表のセルの数が見出しの行と一致しません） |
| `# 見出し\` | G01024 |

文法を追うと、原因は二つの段にある。

- **閉じる `|` の後の `\`**：`TableRow <- Ind(ind) cs:TableCellAndPipe+ Pipe Sp` は、最後の `|` と空白で終わる。その後の `\` を読む規則がないので、行の後に `Nl` が来ず、`Table` が通常の失敗をする。次の選択肢の `Paragraph` は、行頭の `|` を `!BlockStart` で拒むので、`Block` の `^block` が送出され、G01010 になる。
- **セルの中の `\`**：`CellInline` の `BadBreak` は `\` を読んで `hard_break` を送出し、`%recover hard_break SkipLine` で回復して構文エラーを一つ記録する。しかし、その後の `&(Pipe)` が行末で失敗し、`TableCellAndPipe` の試行は通常の失敗として捨てられる。peg-hs の回復するモードは、後戻りで捨てた試行の中で記録したエラーを、その試行とともに捨てる（[peg-hs ADR 0021](https://github.com/tett23/peg-hs/blob/main/docs/adr/0021-error-recovery.md)）。G01024 は残らない。

「今後の実装項目」は、直すには peg-hs の側の変更が要ると書いている。
ここで検討すると、peg-hs を変える必要はない。
捨てた試行の中のエラーを残すと、PEG の順序付き選択が試して捨てたすべての選択肢のエラーが報告に混ざる。
`Table` を試して失敗し `Paragraph` で受理される入力は多く、その都度、表として読んだときのエラーが出てしまう。
[peg-hs ADR 0021](https://github.com/tett23/peg-hs/blob/main/docs/adr/0021-error-recovery.md) がエラーを試行とともに捨てると決めたのは、この誤報を避けるためであり、正しい振る舞いである。
G01024 を出すには、エラーを記録した試行が捨てられないように、文法の側で `\` を受ける位置を作ればよい。

## 実装すること

### エスケープした文字を AST に残す

AST（`Golem.Parser.AST.Inline`）に構成子 `Escaped` を加える。
原稿で `\` を前に置いて書いた一文字を表す。

```haskell
data Inline
  = Text Text
  | -- | a character written after a backslash (golem-parser ADR 0010)
    Escaped Char
  | ...
```

- `Golem.Parser.Lower.inline` は、`KEscape` の字句（`\` と一文字）を `Escaped c` にする。位置は `\` から文字の終わりまでで、今の `Text` の位置と同じである。
- 文法の `Escape <- '\\' ![\n] .` は一つの符号位置を読むので、`Char` で足りる。
- `mergeText` は今と同じく `Text` どうしだけをつなぐ。`Escaped` はつながず、前後の `Text` も `Escaped` をまたいでつながない。
- この結果、`Lower` が作る `Text` はエスケープを含まない。今の G02064 のように、位置の幅と文字列の長さの差からエスケープを推し量る必要はなくなる。
- `Lower` はコマンドの名前を見ない。どの散文スロットでも、段落でも、見出しでも、表のセルでも、エスケープは同じく `Escaped` になる。
- 行頭のエスケープ（`\#` など）、`\\`、`\[`、`\%%` の `\%` も `Escaped` になる。`\%%` は `Escaped '%'` と `Text "%"` になる。

golem-parser は、エスケープを地の文に戻す関数を公開する。

```haskell
-- | Escaped characters as text, joined with the text around them
plainEscapes :: [Located Inline] -> [Located Inline]
```

- 一つの列の最上位の `Escaped c` を `Text (T.singleton c)` にし、隣り合う `Text` をつなぐ。つないだ `Text` の位置は、両方を覆う範囲とする（今の `mergeText` と同じ）。
- 入れ子のコマンドのスロットには入らない。各スロットは、そのコマンドを評価するときに戻す。
- 結果は、今の `Lower` が作る列と一致する。

### 評価：区切りを読んでからエスケープを戻す

評価は、インラインの列を評価する前に `plainEscapes` を掛ける。
戻す前に列を見るのは、エスケープで意味の変わる二つの箇所だけである。

**ルビと索引の区切り**。
golem-eval に、スロットを区切りの文字で分ける関数を置く。

```haskell
-- | A slot split at a character in its top-level text; escaped characters
-- and nested commands are not split (golem-parser ADR 0010)
splitSlot :: Char -> [A.Located A.Inline] -> [[A.Located A.Inline]]
```

- 最上位の `Text` の中の文字だけで分ける。`Escaped` は分けない。入れ子のコマンド（`[ruby: [bold: 漢/字]|かんじ]` の `bold` の中）も分けない。今の `splitSegments` も最上位の文字列だけを分けている。
- 分けた `Text` の位置は、今の `splitSegments` と同じく元の `Text` の位置とする。

`ruby` は、親文字と読みのスロットを、評価する前に `splitSlot '/'` で分ける。

- 親文字の各部分に `plainEscapes` を掛けて `evalInlines` で評価し、親文字のセグメントにする。
- 読みの各部分も同じく評価して `plainText` で文字列にする。地の文でない部分は、今と同じく G02043 とする。
- ルビの中のルビ（G02016）、セグメントの数の比較（G02015）、空の読みのセグメント（部分ルビ）、セグメントが一つのときのグループルビは、今と同じである。
- `splitSegments` と、読みの `T.splitOn "/"` は除く。

`index` は、語のスロットを、評価する前に `splitSlot '/'` で段に分ける。

- 各段に `plainEscapes` を掛けて評価し、`plainText` で文字列にする。地の文でない段があれば、今と同じく G02041 とする。
- `reading` は散文スロットではなく引数なので、今と同じく `T.splitOn "/"` で分ける。
- 段の数と空の段の検査（G02042）は、今と同じである。

この変更で、式の値の中の `/` は区切りにならなくなる。
`[ruby: [= "a/b"]|えー]` は、今は G02015 になるが、グループルビになる。
原稿に書いた区切りだけを区切りとするほうが、エスケープの規則（原稿に書いた文字だけが特別な意味を持つ）と一貫する。
リポジトリの原稿、テスト、文書を `ruby: [=` と `index reading=` で検索した範囲では、語や親文字に式を使う例はなかった。

読みの `\/` は、読みの文字の `/` になる。
`[ruby: 漢字|かん\/じ]` は、親文字「漢字」に読み「かん/じ」を振るグループルビになる。
[golem-eval ADR 0003](../../golem-eval/adr/0003-evaluation-diagnostic-codes.md) の変更 6 は「読みに `/` を含むグループルビを書けなくする」と書いたが、エスケープすれば書けるようになる。

**行頭のエスケープした空白（G02064）**。
`escapedIndent` は、位置の幅と文字列の長さを比べる代わりに、`keep` の段落の行の最初の要素が `Escaped ' '` か `Escaped '\t'` であることで判定する。
メッセージ、位置、重大度は変えない。
判定の後は、今と同じく `plainEscapes` を掛けてから `trimLine` で行頭の空白を除くので、エスケープした空白は今と同じく無視される。

**ほかの箇所**。

- 段落、見出し、定義リストの用語、表のセルの列と、各コマンドのスロットは、評価の前に `plainEscapes` を掛ける。
- `trimLine`、`splitParagraph` の行頭の空白の除去、`hardLines` は、`plainEscapes` を掛けた後の列に働かせる。どれも今と同じ結果になる。
- `evalInline` に `A.Escaped c` の分岐を置き、`Text` として扱う。上のとおり評価の前に戻すので、この分岐は防御のためだけにある。
- 評価の結果（意味論 IR）は、今と同じである。IR に `Escaped` にあたるものは加えない。

### エスケープを AST に残すことの、ほかのモジュールへの影響

- **プラグイン**：プラグインが受け取るのは評価の後の IR であり、エスケープは評価で地の文に戻るので、IR にもプラグインの ABI にも現れない（[golem-plugin ADR 0001](../../golem-plugin/adr/0001-wasm-host-and-abi.md)）。
- **正規表現スタイル**：評価の後の IR の文字列に掛かるので、今と同じく `a\/b` と書いた原稿にも「a/b」として一致する。
- **lint**：golem-lint は CST と評価の `Usage` を読み、AST を読まないので、変わらない。
- **LSP**：golem-lsp の `Golem.Lsp.Features` の見出しの一覧（`outline`）は、`Text` でない要素の文字を原稿から切り出している。`Escaped c` は `c` として書く。切り出すと `\` が見出しの一覧に出るからである。参照の位置の収集（`occurrences`）は、`Escaped` を読み飛ばす。
- **`golem inspect`**：AST の表示に `Escaped` が現れる。
- **fmt**：下の「fmt の不変条件」。

### fmt の不変条件

golem-fmt は CST を書き換えるので、整形の規則そのものは変わらない。
変わるのは、規則が出力を変えないことの確かめ方である。

今の golem-fmt は、規則を掛けた後の AST が、掛ける前の AST と一致する場合だけ、その規則の結果を採る（`astFingerprint`）。
エスケープが AST に残ると、`\あ` を `あ` に直すと `Escaped 'あ'` が `Text "あ"` に変わるので、不要なエスケープを除く規則（`escapes`）が一度も採られなくなる。

そこで、比べる AST を次のように改める。

- `escapes` の規則は、fmt が外してよい文字（今の `special` に当たらない文字。空白、ASCII の句読点と記号、数字のどれでもない文字）の `Escaped` を地の文に戻した AST どうしを比べる。golem-parser に、AST の全体の、条件に合う文字の `Escaped` だけを戻す関数を置き、golem-fmt はそれを使う。
- ほかの規則は、今と同じく AST をそのまま比べる。
- `/`、空白、タブは `special` に入っているので、`\/` と `\ ` は戻さずに比べる。そのため、仮に規則が `\/` を `/` に直しても、AST が一致せずに採られない。

この確かめ方が出力の不変を保証するのは、評価がエスケープで意味を変える文字（`/`、空白、タブ）がすべて `special` に入っている場合に限る。
docs/specifications.md の「fmt」に、この条件を書く。
評価が新しい文字をエスケープで区別するようになったら、その文字を `special` に加える。

### 表の行末の `\` を受ける

`TableRow` の最後に、行末の `\` を受ける省略可能な部分を加える。

```
TableRow(ind :: Int) :: Int
TableRow <- Ind(ind) cs:TableCellAndPipe+ Pipe Sp RowBreak? { length cs }

# a backslash at the end of a table row: tables have no hard breaks
# (docs/adr ADR 0016); it throws hard_break so that the row stays a row
RowBreak :: ()
RowBreak <- &('\\' ('\n' / !.)) BadBreak { () }
```

- `RowBreak` は、`\` の直後が改行か入力の終わりのときだけ `BadBreak` を試す。`\x` のような行の途中のエスケープには効かない。
- `BadBreak` が `hard_break` を送出し、`SkipLine` で回復する。回復は改行を読まないので、`TableRow` は成功し、`Table` は次の行へ進む。記録した G01024 は、`Table` が成功するので捨てられない。
- ラベルは増えない。`hard_break` は `%safe` を宣言済みであり、ラベルを外した文法では `BadBreak` が必ず失敗するので `RowBreak?` は空に一致し、受理する言語は変わらない（[golem-parser ADR 0007](0007-grammar-label-safety.md)）。
- `Golem.Parser.Lower.table` は、行の中の `NTableCell` だけを読むので、`RowBreak` の字句と回復の `ERROR` のノードは AST に入らない。
- `scripts/gen-parser.sh` で `Generated.hs` と `StrippedGrammar.hs` を作り直す。

これで、閉じる `|` の後の `\` は、見出しの行でも本文の行でも G01024 になる。
位置は `\` の位置であり、メッセージは見出しと同じ `行末の \ は段落の中の強制改行です。…` である。

閉じる `|` のない行（`| c | d \`）は、今と同じく G01015 のままとする。
閉じる `|` がない行は、行末の `\` がなくても表の行として不完全であり、G01015 が先に直すべき誤りを指している。

### データ構造の変更

- `Golem.Parser.AST.Inline` に `Escaped Char` を加える。AST を網羅的に照合する関数（golem-eval の `evalInline`、golem-lsp の `Golem.Lsp.Features`）に分岐を足す。
- golem-parser に `plainEscapes` と、条件に合う文字の `Escaped` だけを AST の全体で戻す関数を加える。
- golem-eval に `splitSlot` を加え、`splitSegments` を除く。
- 意味論 IR とプラグインの ABI は変わらない。

### 検討した案

| 案 | 採らなかった理由 |
| --- | --- |
| `Lower` がコマンドの名前 `ruby` のときだけ `/` で分け、`RubySeparator` を置く（最初の草案） | 構文の層がコマンドの意味（どの文字を区切りに使うか）を知ることになる。`index` も `/` を使うので名前の一覧が要り、区切りを使うコマンドを足すたびに `Lower` を直す。 |
| 評価が、`Text` の位置の幅と文字列の長さを比べてエスケープを見分ける（今の G02064 のやり方） | `mergeText` がエスケープを前後の文字とつなぐので、幅の差からはエスケープの数しかわからず、文字列のどこにあったかがわからない。改行をまたいでつないだ `Text` では、幅に改行が入るので数もわからなくなる。原稿を読み直せば位置はわかるが、評価が原稿のバイト列を持つことになる。 |
| `Text` にエスケープした文字の位置の集合を持たせる（`Text Text IntSet`） | 構成子は増えないが、`Text` をつなぐ、切る、空白を除くすべての箇所（`mergeText`、`mergeLocated`、`trimLine`、`splitParagraph`、`trimEnds`）で位置をずらす必要がある。ずらし忘れても型では見つからず、誤った位置が黙って残る。 |
| `Text` に「原稿のまま」か「エスケープ」かの印を付ける（`Text Kind Text`） | `Escaped Char` と同じ情報を持つが、`Text` を照合するすべての箇所が変わる。`Escaped` を足せば、変わるのは網羅的な照合の分岐だけで、コンパイラがその箇所を示す。 |
| 評価に CST を渡し、ルビのスロットを CST から読む | AST を評価の唯一の入力にした [golem-parser ADR 0005](0005-cst-to-ast.md) の分け方に反する。評価がトリビアとエスケープの扱いを再び持つ。 |
| 文法でルビの `/` を読む | [golem-parser ADR 0004](0004-inline-grammar.md) は文法がコマンドの名前を知らないと決めている。 |
| `\/` をやめ、区切りでない `/` を別の書き方（`[slash]` のようなコマンド、全角の `／`）にする | docs/markup.md は `\/` を約束しており、別の書き方は利用者に新しい規則を覚えさせる。全角の `／` は別の文字である。 |

### ドキュメント

- docs/markup.md の「エスケープ」の「ルビの中の `/`」を「ルビの親文字と読み、索引の語の中の `/`」に改める。「ルビ」に、親文字と読みを区切るのは原稿に書いた `/` だけであり、`\/` は `/` そのもの、式の値の中の `/` は区切りにならないことを書く。読みに `\/` を書けば読みの文字の `/` になることも書く。「索引」に、語の `\/` が段の区切りにならないことを書く。
- docs/specifications.md の「処理の流れ」の「CST から空白、コメント、エスケープを取り除き」を、エスケープは `\` を除いた文字として印を付けて残すことに改める。「fmt」に、上の「fmt の不変条件」を書く。この ADR へリンクする。
- docs/specifications.md の「今後の実装項目」の「記法と設定」から「ルビの中の `/` のエスケープ」と「表のセルの行末の `\`」の二項を除く。
- [golem-parser ADR 0005](0005-cst-to-ast.md) のステータスの行の値を「採択→段落内の改行の扱いは [docs/adr/0003](../../adr/0003-verse-line-breaks.md)、エスケープの表し方は [ADR 0010](0010-ruby-slash-escape-and-table-cell-breaks.md)」に改める。
- [golem-parser ADR 0003](0003-block-grammar.md) のステータスの行の値に「表の行末の `\` は [ADR 0010](0010-ruby-slash-escape-and-table-cell-breaks.md)」を加える。
- [golem-eval ADR 0002](../../golem-eval/adr/0002-file-evaluation.md) のステータスの行の値を「採択→`ruby` と `index` の `/` の区切りは [golem-parser ADR 0010](0010-ruby-slash-escape-and-table-cell-breaks.md)」に改める。
- [golem-fmt ADR 0001](../../golem-fmt/adr/0001-formatter.md) のステータスの行の値に「エスケープの規則の出力の不変の確かめ方は [golem-parser ADR 0010](0010-ruby-slash-escape-and-table-cell-breaks.md)」を加える。
- docs/diagnostics.md の G01024 の節に、表の行の閉じる `|` の後の `\` も G01024 になることを書く。G02015 の節に、`\/` は区切りにならないことを書く。G02042 の節に、語の `\/` は段の区切りにならないことを書く。
- 利用者のマニュアル（`manual/`）を次のように直す（[docs/adr/0024](../../adr/0024-manual-audiences-and-policy.md)）。
  - `manual/appendices/a-markup.gm` の `[ruby: 親文字|読み]` の項：「今の版では、親文字と読みに `/` という文字そのものは書けません。」を消し、`\/` の例を加える。`[index ...]` の項にも、語の `\/` が段の区切りにならないことを書く。「コメントとエスケープ」の節のバックスラッシュの要る文字の一覧に、ルビと索引の語の中の `/` を加える。
  - `manual/chapters/03-markup.gm` の「ルビ」の節（ラベル `ruby`）に `\/` の例を加え、「目次と索引と参考文献」の節の索引の説明に語の `\/` を書く。「コメントとエスケープ」の節の一覧にも、ルビと索引の語の中の `/` を加える。
  - `manual/appendices/e-errors.gm`（付録E「診断の一覧」。[golem-cli ADR 0006](../../golem-cli/adr/0006-preflight.md) より前に実装するときは `d-errors.gm` の付録D）の G02015 と G02042 の項に、`\/` が区切りにならないことを書く。表の行末の `\` が G01024 になることを G01024 の項に書く。
- 開発者のマニュアル（`manual-dev/`）を次のように直す。
  - `manual-dev/part1/06-ir.gm` の「処理の流れの中の位置」の「CST から空白、コメント、エスケープを取り除き、AST（抽象構文木）を作る。」を、エスケープは印を付けて残し、評価で地の文に戻ることに改める。
  - `manual-dev/part1/01-cli.gm` の「構文木と IR を見る」に、`--as ast` の表示に `Escaped` が現れることを書く。

## 実装しないこと

- peg-hs の回復の意味論を変えること。上の検討のとおり、変える必要がない。
- 表のセルに強制改行を書けるようにすること（[docs/adr/0016](../../adr/0016-hard-line-breaks.md) が書けないと決めている）。
- 閉じる `|` のない行の `\` を G01024 にすること。
- 文法でルビを特別に扱うこと（[golem-parser ADR 0004](0004-inline-grammar.md) のまま、文法は `ruby` を知らない）。
- エスケープした文字を意味論 IR とプラグインに渡すこと。
- `index` の `reading` の中の `/` をエスケープできるようにすること。`reading` は引数であり、引数の書き方は散文スロットと別である。
- 行頭と行末の空白の除き方を変えること。どの箇所も、今と同じくエスケープを戻してから除く。コードを読む限り、`keep` の段落では行末のエスケープした空白も `trimLine` で除かれており、docs/markup.md の「エスケープした空白も行の先頭では無視する」（行末は残ると読める）と食い違っている可能性がある。`Escaped` が AST に残れば `trimLine` が行末の `Escaped ' '` を残すように直せるが、振る舞いの変更なので別の ADR で決める。

## テスト設計

### 先に書いて失敗させるテスト

`modules/golem-parser/test/LowerSpec.hs`：

- `[ruby: a\/b|えー]` の親文字のスロットが `[Text "a", Escaped '/', Text "b"]` であり、`Escaped` の位置が `\/` の 2 バイトであること。
- `\# 見出しではない \[ x \\` の段落が `[Escaped '#', Text " 見出しではない ", Escaped '[', Text " x ", Escaped '\\']` であること。今の「escapes are resolved」のテストを、この形に改める。
- `[bold: a\/b]` のスロットも `[Text "a", Escaped '/', Text "b"]` であり、コマンドの名前によらないこと。
- `Lower` の結果に `plainEscapes` を掛けると、今の `Lower` の結果と一致すること。今の LowerSpec のエスケープを含む入力（「escaped and ideographic spaces stay」など）で確かめる。

`modules/golem-eval/test`：

- `[ruby: a\/b|えー]` が、親文字 `a/b` に読み `えー` のグループルビになり、G02015 が出ないこと。
- `[ruby: 漢字|かん\/じ]` が、読み「かん/じ」のグループルビになること。
- `[ruby: 漢/字|かん\/じ]` が G02015 になること（読みのセグメントは一つ）。
- `[ruby: 東京|とう/きょう]` が今と同じく G02015 になること。
- `[ruby: 漢/字|かん/]` が今と同じく、二つ目のセグメントに読みのない部分ルビになること。
- `[ruby: [bold: 漢/字]|かんじ]` が今と同じく、一つのセグメントのグループルビになること。
- `[ruby: [= "a/b"]|えー]` がグループルビになること（今は G02015）。
- `[index reading=えー: a\/b]` が、語「a/b」と読み「えー」の一段の索引の項目になること（今は G02042）。`[index reading=くみはん/わぶん: 組版/和文]` が今と同じく二段になること。
- G02064 の今のテスト（`@style verse` の行頭の `\ `）が、同じメッセージと位置で通ること。その行の行頭の空白が、今と同じく出力に残らないこと。
- エスケープを含む今の評価のテストの IR が変わらないこと。

`modules/golem-fmt/test`：

- `\あ` が `あ` に直ること（今と同じ）。
- `[ruby: a\/b|えー]`、`a\ ` の行、`\#` で始まる段落が、整形で変わらないこと。
- 整形の前後の AST の比較のプロパティテストを、上の「fmt の不変条件」の比べ方に改める。

`modules/golem-lsp/test`：

- 見出し `# a\[b` の `outline` の名前が `a[b` であること。

`modules/golem-parser/test/ParserSpec.hs`：

- 見出しの行が `| a | b |\` で終わる表で、構文エラーが G01024 の一つだけで、位置が `\` であること。
- 本文の行が `| c | d |\` で終わる表で、同じく G01024 だけであること。AST に表があり、行の数が今の書き方の表と同じであること。
- `| a | b |\` が入力の最後の行で、改行で終わらない場合も G01024 であること。
- `| c | d \` の行が今と同じく G01015 であること。
- ラベルを外した文法（`StrippedGrammar`）が、上の入力をどれも受理しないこと（すでにある「二つの文法が同じ入力を受理する」テストに入力を加える）。

`modules/golem-cli/test/Main.hs`：

- 上の表の入力で、`golem check` が `error[G01024]` を出し、`error[G01010]` を出さないこと。

### 自動テストにしない確かめ方

マニュアルの付録A に `\/` の例を加えて PDF と HTML に組み、ルビが親文字の全体に掛かっていることを目で確かめる。
マニュアルの全体を組んだ PDF と HTML のバイト列が、この変更の前後で、付録A の例を加えた箇所を除いて変わらないことを確かめる。

## トレードオフ

AST の構成子が一つ増え、AST を照合する箇所はすべて `Escaped` を扱う必要がある。
多くの箇所は `plainEscapes` を掛けてから働くので、扱いは一行で済む。
一方で、`plainEscapes` を掛け忘れた箇所では、エスケープの前後で `Text` が分かれたままになり、行頭の空白の除去や文字列の照合が黙って効かなくなる。
評価の結果の IR が今と変わらないことをテストで確かめて、掛け忘れを見つける。

その代わり、`Lower` はコマンドの名前を一つも知らずに済む。
区切りの文字の意味は評価だけが持ち、ルビと索引は同じ `splitSlot` を使う。
G02064 の位置から推し量る判定もなくなる。

fmt の出力の不変の確かめ方は、エスケープについては AST の比較だけでは閉じなくなる。
`Escaped` のどの文字が評価で意味を持つかは評価の規則であり、AST には表れないからである。
fmt は外してよい文字を `special` で限り、評価で意味を持つ文字を `special` に入れておくことで不変を保つ。
この対応は二つのモジュールにまたがる約束であり、評価が新しい文字を区別するときに `special` を直し忘れると、整形で原稿の意味が変わりうる。

式の値の `/` が区切りにならなくなるのは、振る舞いの変更である。
式で親文字や索引の語を作る原稿は確かめた範囲になく、エスケープの規則（原稿に書いた文字だけが特別な意味を持つ）に合うほうを選ぶ。

`RowBreak` は、表の行の終わりにだけ効く規則を一つ文法に足す。
peg-hs を変える案は、上のとおり誤報を生むので採らない。

## 参考文献

- [peg-hs ADR 0021](https://github.com/tett23/peg-hs/blob/main/docs/adr/0021-error-recovery.md)「エラー回復」
- Sérgio Medeiros, Fabio Mascarenhas, "Syntax Error Recovery in Parsing Expression Grammars", SAC 2018
- Andre Murbach Maidl, Fabio Mascarenhas, Sérgio Medeiros, Roberto Ierusalimschy, "Error Reporting in Parsing Expression Grammars", Science of Computer Programming 132, 2016
