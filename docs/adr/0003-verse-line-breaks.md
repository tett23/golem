# ADR 0003: 韻文の行分けを保つ @verse

ステータス: 採択→記法と `stanza-gap` は [docs/adr/0005](0005-character-and-paragraph-styles.md)

## 文脈

段落内の改行は文字を生まない（docs/markup.md、specifications.md の「段落内の改行」）。
日本語の原稿で行の折り返し位置に空白を入れないための規則であり、CST から AST への変換が改行のトークンを捨てて前後の地の文を連結している（[golem-parser ADR 0005](../golem-parser/adr/0005-cst-to-ast.md)）。

この規則の下では、詩や戯曲の韻文の行分けを書く方法がない。
fixture の『テンペスト』（`modules/golem-driver/test/fixtures/tempest/tempest.gm`）では、Ariel の歌が次の一段落になっている。

```
Full fathom five thy father lies; Of his bones are coral made; Those are pearls that were his eyes: ...
```

変換スクリプト（`scripts/fixtures/gutenberg_play_to_gm.py`）が、原典の行を空白でつないで一行にしているためである。
改行のまま残しても、段落内の改行は文字を生まないので、語が空白なしにつながる（lint の G0501 がこれを誤りとして報告する）。
specifications.md は、この問題を「今後の実装項目」に挙げている。

韻文の行は、組版の上でも段落と違う扱いを要する。
一行が版面の行長を超えたら折り返すが、折り返した部分は字下げして（ぶら下げ）、次の行の始まりと区別する。
連（スタンザ）の間には空きを置く。

v1 のリリースの前に、強調のような見た目の記法は文字スタイルへ、韻文のようなブロックの記法は段落スタイルへ統合する（[仕様書](../specifications.md)の「v1 の実装で次の段階以降に回した項目」）。
この ADR の `@verse` は、その統合までの記法として定める。
統合のときに記法が変わっても、意味論 IR の `VerseBlock` と各媒体の出力は段落スタイルの側から使えるように作る。

### 記法の候補

次の四つを比べた。

- ブロックコマンド `@verse` と、インデントした本体：本体の段落が連、段落の各行が韻文の行になる。`@figure` のキャプションと同じく、既存のブロックコマンドの本体の文法で書ける。
- 行頭の記号（Pandoc の line block の `| `）：Golem では行頭の `|` が表なので使えない。別の記号を選ぶと、行頭でエスケープの要る文字が一つ増え、その記号で始まる既存の段落の解釈が変わる。
- 行末の記号（Markdown の行末の `\` のような強制改行）：今は行末の `\` が構文エラーなので、文法の上では使える。しかし、一行ごとに記号が要り、韻文の連や折り返しの字下げのようなブロックとしての扱いを表せない。
- 段落に付ける属性 `@verse`（`@label` と同じく直後の段落に付ける）：インデントは要らないが、一つの属性が一つの段落にしか付かないので、複数の連からなる一篇の詩を一つのブロックとして表せない。

`@verse` と本体の形を採る。
文法を変えずに書け、構文解釈の安定（プラグインを足しても解析が変わらないこと）にも触れない。
一篇の詩、戯曲の一つの台詞のように、行の集まりを一つのブロックとして出力に渡せる。

```
@verse
  Full fathom five thy father lies;
  Of his bones are coral made;
  Those are pearls that were his eyes:

  Nothing of him that doth fade,
  But doth suffer a sea-change
```

## 実装すること

### 記法

docs/markup.md の「ブロック」に「韻文」の節を加え、v1 のブロックコマンドの一覧に `@verse` を加える。

- `@verse` は引数を取らない。
- `@verse` の行の直後に、2 つ深くインデントした段落を並べる。本体の段落が一つの連であり、段落の中の各行が韻文の一行である。連は空行で区切る。
- 本体の段落の中の改行は、段落の外と違い、行の区切りになる。
- 行の区切りになるのは、インラインのコマンドの外にある改行だけである。散文スロットの中の改行（`[note: ...]` の中など）は、段落と同じく文字を生まない。韻文の行をまたいで斜体などを続けたい場合は、行ごとにコマンドを閉じて開き直す。
- 各行の先頭と末尾の空白（空白とタブ）は無視する。エスケープした空白（`\ `）も行の先頭では無視する（AST への変換でエスケープを解除した後に取り除くため）。全角の空白（U+3000）は無視しない。和文の詩で行ごとに字下げしたい場合は全角の空白を使う。
- 行頭でエスケープの要る文字（`#`、`-`、`+`、`=`、`@`、`|`）は、段落と同じく `\` でエスケープする。
- `@verse` の本体に段落以外のブロック（リスト、見出し、コードブロック、ブロックコマンドなど）を置くとエラーとする。

docs/markup.md の「段落と改行」の節の末尾に、行分けを保つには `@verse` を使うことを一文で書く。
specifications.md の「段落内の改行」の節にも同じ一文を加え、「今後の実装項目」から韻文の行分けの項目を外す。
docs/glossary.md の「原稿の記法」に「韻文」の項目（`@verse` の本体。改行が行の区切りになり、段落が連になる）を加える。

### AST（golem-parser）

文法は変えない。
`@verse` の行と本体は、既存の `BlockCommand` の規則でそのまま解析できる（ブロックコマンドの本体は `Blocks(ind + 2)` であり、段落の改行は `LineContinuation` の `KNewline` のトークンとして CST に残っている）。

AST の `Inline`（`Golem.Parser.AST`）に、段落内の改行を表す構成子を加える。

```haskell
data Inline
  = Text Text
  | SoftBreak
  | Expr (Located Expr)
  | ...
```

`Golem.Parser.Lower` は、段落、リストの項目、定義リストの用語、散文スロットの中の `KNewline` のトークンを捨てずに、`SoftBreak` にする。
改行の直前の空白を捨てる規則（[golem-parser ADR 0006](../golem-parser/adr/0006-discard-insignificant-whitespace.md)）はそのまま適用する。
改行の前後の `Text` は連結しない。
この変更は [golem-parser ADR 0005](../golem-parser/adr/0005-cst-to-ast.md) の「改行のトークンを捨てて、前後の地の文をそのまま連結する」を改め、改行を捨てる段階を評価に移す。
[ADR 0005](../golem-parser/adr/0005-cst-to-ast.md) のステータスの行を「採択→段落内の改行の扱いは docs/adr [ADR 0003](0003-verse-line-breaks.md)」に変える。

AST を読むほかのモジュール（golem-lsp の出現位置の収集など）は、`SoftBreak` を何も持たない要素として読み飛ばす。

### 評価（golem-eval）

`Golem.Eval.File` に、AST の改行を落とす前処理を加える。

```haskell
-- | SoftBreak を取り除き、隣り合う Text を一つにまとめる。
-- まとめた Text の位置は、両者を覆う範囲とする。
joinSoftBreaks :: [A.Located A.Inline] -> [A.Located A.Inline]
```

ファイルの評価の入口で、すべてのインラインの列（段落、見出し、項目、用語、表のセル、散文スロット、コマンドの引数の中の命令文脈）に `joinSoftBreaks` を適用する。
例外は `@verse` の本体の段落の最上位の列であり、そこでは `SoftBreak` を残し、入れ子のインラインにだけ適用する。
結果の AST は、この ADR の前の `Lower` の出力と一致する。
評価のほかの部分（ルビの区切り、縦中横の中身の検査など）は変えない。

`standalone` に `"verse"` を加え、次の関数で評価する。

```haskell
verse :: EvalContext -> SrcSpan -> [A.Located A.Argument] -> [A.Located A.Block] -> M [Block]
```

1. 引数があれば G0244 とする。
2. 本体に `A.Paragraph` 以外のブロックがあれば、そのブロックの位置で G0245 とする（`A.ErrorBlock` は構文エラーとして報告済みなので数えない）。
3. 各段落の最上位のインラインの列を `SoftBreak` で分け、行の列にする。各行の先頭の `Text` の先頭の空白とタブを取り除き、`evalInlines` で評価する。
4. 評価した結果が空の行（コメントだけの行など）は捨てる。行が一つもなくなった連は捨てる。
5. 連が一つもなければ G0246 とする。そうでなければ `VerseBlock` のブロックを一つ返す。

注の番号は、行の順に、ほかのブロックと同じく文書の順で振る。

| 診断コード | 重大度 | メッセージ |
|---|---|---|
| G0244 | エラー | `@verse は引数を取りません` |
| G0245 | エラー | `@verse の本体には段落だけを置けます。連は空行で区切ります` |
| G0246 | エラー | `@verse の本体がありません。韻文の行を 2 つ深くインデントして書きます` |

G0244 から G0246 は未使用である（golem-eval は G0243 まで使っている）。

### 意味論 IR（golem-doc）

CDDL（`modules/golem-doc/schema/golem-doc.cddl`）に、ブロックの本体の選択肢と規則を加え、ABI の版を 2 に上げる。

```
document = [abi-version: 2, file: uint, blocks: [* block]]

block-body =
    ...
  / [9, verse]                                     ; verse

verse = [+ stanza]
stanza = [+ verse-line]
verse-line = [+ inline]
```

Haskell の型（`Golem.Doc.IR`）。

```haskell
data BlockBody
  = ...
  | VerseBlock [[[Inline]]] -- 連の列。連は行の列、行はインラインの列
```

- `abiVersion` を 2 にする。golem-plugin の `abiVersion` も 2 にし、テストのプラグイン（`modules/golem-plugin/test/plugins/*.wat`）の `golem_abi_version` の戻り値を 2 にする。
- `Golem.Doc.Cbor`：タグ 9 の符号化と復号。空の連の列、空の連、空の行は復号の誤りとする。
- `Golem.Doc.Validate`：行の中のインラインを、段落と同じ不変条件（ルビの入れ子、モノルビのセグメントの数、ソース位置）で検査する。
- `Golem.Doc.Assemble`：ブロックを走査するすべての関数（注、見出し、図版、遅延した式の解決）で、`VerseBlock` の行のインラインをたどる。
- `Golem.Plugin`：フィルタの出力の走査に `VerseBlock` を加える。

折り返しの字下げや連の間の空きは幾何なので、IR には持たせない（幾何の隔離）。

### スタイル（golem-project）

`style.toml` に `[verse]` の節を加える（[golem-project ADR 0002](../golem-project/adr/0002-style-toml.md) の節の一覧に追加する）。

| キー | 型 | 既定 | 意味 |
|---|---|---|---|
| `indent` | 寸法 | `"0zw"` | 韻文のすべての行の始まりの字下げ |
| `hang` | 寸法 | `"2zw"` | 行長を超えて折り返した部分の、`indent` からさらに下げる量 |
| `stanza-gap` | 0 以上の整数 | `1` | 連の間に空ける行の数 |

`Golem.Project.Style` の `Style` に `stVerse :: !VerseStyle` を加え、既定の値の表に上の値を足す。
未知のキーはほかの節と同じくエラーとする。
specifications.md の `style.toml` の例に `[verse]` を加える。

### HTML と EPUB（golem-html）

`Golem.Html.block` に `VerseBlock` を加える。

```html
<div class="verse" id="...">
<p><span>Full fathom five thy father lies;</span><br/>
<span>Of his bones are coral made;</span></p>
<p><span>Nothing of him that doth fade,</span></p>
</div>
```

- 連を `<p>`、行を `<span>` とし、行の間に `<br/>` を置く。CSS が効かない読書環境でも行が分かれるようにするためである。
- `css` に次の規則を加える。`H` と `I` は `style.toml` の `hang` と `indent` であり、`zw` は `em` に、ほかの単位は sp から pt に変換して書く（小数は 3 桁までの固定の表記にし、決定性を保つ）。

  ```css
  .verse { margin-inline-start: I; }
  .verse p { margin: 0; text-indent: 0; }
  .verse p + p { margin-block-start: 1em; }
  .verse span { display: block; padding-inline-start: H; text-indent: -H; }
  .verse br { display: none; }
  ```

  `stanza-gap` が 0 のときは `.verse p + p` の規則を書かない。
  行の格子のない媒体なので、空ける量は行数によらず 1em とする。
- `padding-inline-start` と `margin-inline-start` は論理方向の指定なので、縦組みでもそのまま効く。
- 注を集める `blockNotes` に `VerseBlock` を加える。
- `HtmlConfig` に `[verse]` の値を渡す欄を加える。EPUB は golem-html の出力をそのまま包むので、golem-epub には変更がない。

### プレーンテキスト（golem-text）

`Golem.Text.block` に `VerseBlock` を加える。
行を改行で、連を空行で区切り、各行の前に入れ子の字下げ（`indentBy ind`）を置く。
折り返しの字下げは行長のない媒体なので出力しない。
`blockInlines` にも加える。

### PDF（golem-driver と golem-layout）

`Golem.Driver.Pdf` の `unitsOf` で、`VerseBlock` を次の単位に分ける。

- 各行を一つの単位 `Unit (UVerseLine indent hang) lbl line` にする。ラベルは最初の行にだけ付ける。
- 連の間に `Unit (UGap stanzaGap) Nothing []` を置く。

`buildFlow` は、単位ごとに行長の関数を選ぶ。
`UVerseLine` では、L*(i) を `measure - indent`（i = 0）と `measure - indent - hang`（i ≥ 1）とし、[golem-layout ADR 0001](../golem-layout/adr/0001-knuth-plass-line-breaking.md) の行分割で組む。
行の最後は段落の終わりと同じく `finish` で終えるので、一行に収まる韻文の行は伸ばされない。
折り返した行の始まりのずらしを表すため、`SetLine` に `slIndent :: !Sp` を加え、最初の行では `indent`、折り返した行では `indent + hang` とする。
`drawLine` は、行の中の位置に `slIndent` を足してから `origin` を計算する。
この欄は回り込みの図版の提案（[golem-driver ADR 0005](../golem-driver/adr/0005-pdf-wrapped-figures.md)）と同じものであり、先に実装した側が加え、後の側はそれを使う。

各 `UVerseLine` は `FParagraph` の流れになる。
改ページの孤立行と泣き別れの規則（[golem-layout ADR 0003](../golem-layout/adr/0003-pagination-and-s2.md)）が段落ごとに働くので、折り返しが二行か三行の韻文の行は、ページをまたいで分かれない。

`UGap n` は、`Golem.Layout.Paginate` の `Flow` に加える `FSpace !Int` になる。

- `FSpace n` は、ページに行が一つもないとき（ページの先頭）は何もしない。
- それ以外では、`min n (free st)` 行を空ける。
- `nextNeed` では 0 行とする。

回り込みの図版の脇で韻文を組むことはしない。
回り込みの仕事は `UPara` でない単位で終わる（[golem-driver ADR 0005](../golem-driver/adr/0005-pdf-wrapped-figures.md) の提案）ので、`UVerseLine` が来た時点で回り込みが終わる。

### lint（golem-lint）

G0501（段落内の改行の前後がともに欧文）は、韻文の行の区切りには当てない。
`latinJoinedByNewline` で、名前が `verse` の `NBlockCommand` の `NCommandBody` の中の `NParagraph` では、最上位の改行を調べず、入れ子の `NProseSlot` だけを調べる。
散文スロットの中の改行は韻文の中でも文字を生まないので、そこでは G0501 が引き続き意味を持つ。
[golem-lint ADR 0001](../golem-lint/adr/0001-lint-rules.md) のステータスの行を「採択→G0501 の韻文の扱いは docs/adr [ADR 0003](0003-verse-line-breaks.md)」に変える。

### fmt（golem-fmt）

コードは変えない。
fmt は本文を折り返し直さず、改行の位置を変えない（[golem-fmt ADR 0001](../golem-fmt/adr/0001-formatter.md)）。
本体のインデントは、ほかのブロックコマンドの本体と同じく 2 つの空白にそろえる。
AST に `SoftBreak` が加わっても、整形の前後で改行の位置が変わらないので、「整形の前後で AST が一致する」という不変条件はそのまま成り立つ。

### LSP（golem-lsp）

機能は加えない。

- 新しい診断（G0244 から G0246）は、評価の診断として既存の経路で表示される。
- AST を走査する関数に `SoftBreak` の場合を加える（何も返さない）。
- ブロックコマンドの名前の補完は今もないので、`@verse` も補完しない。
- 整形は golem-fmt を呼ぶので、韻文の行分けは保たれる。

### 変換スクリプト

`scripts/fixtures/gutenberg_play_to_gm.py` で、韻文のブロックを `@verse` として出力する。
原典（Project Gutenberg #23042）では、散文は版面の幅で折り返されており、韻文は一行ごとに改行されている。
行分けの情報が改行にしかなく、散文の折り返しの改行と区別する印がないので、次の規則で判定する。

- 原典の空行で区切ったブロックのうち、台詞（`_名前._` で始まる行）と、台詞の続き（ト書きでない、インデントのない行の並び）で、二行以上あるものを対象にする。
- 二行目以降のすべての行が、次のどれかに当たれば韻文とする。
  - 4 つ以上の空白で始まる（行の途中から始まる半行）。
  - ト書きの括弧（`[_..._]`）だけの行。
  - 先頭のト書きの括弧、引用符、アポストロフィ（`’`）を除いた最初の文字が大文字。
- 歌と仮面劇の台詞（すべての行が 4 つ以上の空白で始まるブロック、2 つの空白と `_名前._` で始まり続きの行が 4 つ以上の空白で始まるブロック）も韻文とする。
- 一行だけの台詞は段落のままにする。一行なら段落でも韻文でも見た目は変わらない（版面の行長を超えたときの折り返しの字下げを除く）。

韻文と判定したブロックは次の形で出力する。

```
@verse
  [strong: Fer.] Where should this music be? i’ th’ air or th’ earth?
  It sounds no more: and, sure, it waits upon
```

- 各行について、行番号を取り除き、行頭の空白を取り除き、連続した空白を一つにまとめ、`--` を `—` に置き換える。
- `_` による斜体の切り替えは、行をまたいで状態を引き継ぎ、行の終わりで `[italic: ...]` を閉じて次の行の始まりで開き直す。
- 各行の先頭が `#-+=@|` のどれかなら `\` でエスケープする。
- 台詞の名前は、これまでどおり最初の行の先頭に `[strong: 名前.]` として置く。

この規則は、すべての行が大文字で始まる二、三行の散文の台詞を韻文と誤る。
第 1 幕第 1 場の `_Alon._ Good boatswain, have care. Where’s the master? / Play the men.` がその例である。
fixture の目的は韻文の組版を通すことであり、版の正確さではないので、この誤りは受け入れる。
README（`modules/golem-driver/test/fixtures/README.md`）の Sources に、韻文の判定が近似であることを一文で書く。

fixture は `scripts/fixtures/fetch-public-domain.sh` で作り直し、`golem fmt` で整形した結果をコミットする。

## 実装しないこと

- 韻文の行ごとの字下げを記法で指定すること（歌の行を交互に下げる、半行を前の行の終わりにそろえる、など）。和文では全角の空白で書ける。変換スクリプトは原典の行頭の空白を捨てる。
- `@verse` の引数（詩ごとの `indent` や `hang` の上書き）。v1 では `style.toml` の値だけを使う。
- 行番号（5 行ごとの番号など）。
- 連をページで分けない指定。連の途中で改ページしうる。
- `@label` などの属性を `@verse` に付けること。属性のまとまりの最後がブロックコマンドの場合、評価は今「属性の後にブロックがありません」（G0210）とする。`@figure` にも同じ問題があり、属性の規則の ADR で扱う。
- 段落一般の強制改行（行末の `\` など）。必要になったら別の ADR で決める。行末の `\` は今は構文エラーなので、後から意味を与えられる。
- 蟹工船の変換スクリプト（`aozora_to_gm.py`）の変更。
- 段落スタイルとしての韻文の定義。文字スタイルと段落スタイルへの記法の統合は、v1 のリリースの前に別の ADR で行う。

## テスト設計

先に書き、失敗させてから実装する。

### golem-parser（`test/LowerSpec.hs`）

- `"a\nb\n"` の段落が `[Text "a", SoftBreak, Text "b"]` になること。
- `"a  \nb\n"` も同じになること（改行の前の空白は捨てる）。
- `"[note: a\nb]\n"` の散文スロットが `[Text "a", SoftBreak, Text "b"]` を持つこと。
- `"@verse\n  A\n  B\n\n  C\n"` が、本体に二つの段落を持つ `BlockCommand "verse"` になること。

### golem-eval（`test/FileSpec.hs`）

- `"吾輩は猫である。\n名前はまだ無い。\n"` の段落の IR が、一つの `Text "吾輩は猫である。名前はまだ無い。"` であること（この ADR の前と同じ）。
- `"[tcy: 1\n2]\n"` が G0240 にならないこと（`joinSoftBreaks` が縦中横の中身の検査より先に働くこと）。
- `"@verse\n  A\n  B\n\n  C\n"` が `VerseBlock [[[Text "A"], [Text "B"]], [[Text "C"]]]` になること。
- `"@verse\n  A\n    B\n"` の二行目が `Text "B"` になること。`"@verse\n  A\n  　B\n"`（全角の空白で始まる行）の二行目が `Text "　B"` になること。
- `"@verse\n  [italic: a\n  b] c\n"` が一行 `[Italic [Text "ab"], Text " c"]` になること。
- `"@verse\n  A %% x %%\n  %% y %%\n  B\n"` が二行 `[Text "A"]` と `[Text "B"]` になること。
- `"@verse x\n  A\n"` が G0244、`"@verse\n  - a\n"` が G0245、`"@verse\n"` が G0246 であること。
- `@verse` の行の中の `[note: ...]` に、前後の段落の注と続く番号が振られること。

### golem-doc

- `Gen.hs` の生成器に `VerseBlock` を加え、既存の往復、決定性、CDDL の検証器（`cddl` の CLI）による適合のテストが `VerseBlock` を含む文書で通ること。
- ABI の版が 1 の文書の復号が誤りになること。
- 空の連、空の行を含む CBOR の復号が誤りになること。
- 行の中のルビの入れ子が `validate` の診断になること。

### golem-project

- `[verse]` の三つのキーを読み、省略すると既定の値になること。
- 未知のキー、負の `stanza-gap` がエラーになること。

### golem-layout（`test/Main.hs`）

- `paginate 5 [FParagraph (lines' 0 4), FSpace 1, FParagraph (lines' 10 1)]` で、空きが 1 ページ目の 5 行目に入り、次の段落が 2 ページ目の 1 行目に来ること。
- `FSpace` がページの先頭に来たとき、行を消費しないこと。

### golem-driver（`test/Main.hs`）

作業用のディレクトリに韻文を含む小さなプロジェクトを作って確かめる。

- HTML の出力に `<div class="verse">`、連ごとの `<p>`、行ごとの `<span>` と `<br/>` があり、`style.css` に `.verse span` の規則があること。`hang = "3zw"` で `padding-inline-start: 3em; text-indent: -3em;` になること。
- プレーンテキストの出力で、行が改行で、連が空行で区切られること。
- PDF で、版面の行長を超える韻文の行（横組み、字数 30 の版面に 45 字の行）が二行に組まれ、二行目の `slIndent` が `hang` の sp の値であり、一行目の `lineTarget` が版面の行長、二行目が版面の行長から `hang` を引いた値であること。
- 縦組みのスタイル（既存の `pdfStyle`）でも、二行目の `slIndent` が `hang` の値であること。
- 連の間に `stanza-gap` の行数の空きが入ること。
- 既存の golden（`html-01.xhtml` など）と、`scripts/determinism.sh` が出力する sample の各ファイルのハッシュが、この ADR の前と変わらないこと。段落の改行を落とす段階を移しても、IR が変わらないことの確認である。

### golem-lint と golem-fmt

- `"@verse\n  Full fathom five\n  Of his bones\n"` に G0501 が出ないこと。同じ二行を普通の段落に書くと G0501 が出ること。
- `"@verse\n  [note: a\n  b] x\n"` の散文スロットの中の改行に G0501 が出ること。
- golem-fmt の golden に韻文のファイル（本体のインデントが 4 つの空白のもの、行末に空白のあるもの）を加え、本体が 2 つの空白にそろい、行分けが変わらないこと。既存の整形の前後の AST の一致のプロパティテストの生成器に `@verse` を加えること。

### 変換スクリプトと fixture

自動テストにはしない。
実装の後で、次を確かめる。

- `scripts/fixtures/fetch-public-domain.sh` で `tempest.gm` を作り直し、`golem fmt --check` が通ること。
- golem-driver のテスト「The Tempest builds horizontally to every target」が通ること。このテストに、プレーンテキストの出力に `"Full fathom five thy father lies;\nOf his bones are coral made;"` が含まれることの検査を加える。
- 作り直した `tempest.gm` の `@verse` の数を数え、散文の場面（第 1 幕第 1 場、第 2 幕第 2 場の Trinculo と Stephano の場面）に誤って韻文になった台詞がいくつあるかを目で確かめ、README に書いた近似の説明と合っていること。

## トレードオフ

AST に `SoftBreak` を加えると、改行を落とす処理が変換から評価に移る。
AST を読むすべての場所が新しい構成子を扱う必要があり、評価の入口に正規化の一段が増える。
代わりに、変換（golem-parser）がコマンドの名前を知らずに済み、構文の側はコマンドの定義に依存しないままでいられる。
変換が `verse` の名前を見て改行を残す方式なら AST の型は変わらないが、構文の段階が特定のコマンドの意味を持つことになる。

本体をインデントして書くので、長い戯曲では韻文の台詞のたびに `@verse` の行と 2 つの空白が要る。
台詞ごとに属性を付ける方式と比べて手間は同程度であり、複数の連を一つのブロックにまとめられる利点を取る。

折り返しの字下げを `style.toml` で一つの値にすると、詩ごとに変えることはできない。
一冊の本の中で韻文の組み方をそろえることを優先し、詩ごとの指定が要る原稿が出てきたら引数を加える。

変換スクリプトの韻文の判定は近似であり、短い散文の台詞を韻文と誤る。
原典に散文と韻文を区別する印がない以上、規則を足しても誤りは残る。
fixture の役割は韻文の組版の経路を通すことなので、近似のまま使う。

`@verse` は段落スタイルへの統合までの記法なので、統合のときに原稿の書き換えが要る。
統合の ADR で、`golem fmt` か移行のスクリプトで書き換えられるようにする。
統合を待って韻文を後回しにするより、`VerseBlock` と各媒体の組版を先に作っておくほうが、統合の作業を記法の置き換えだけにできる。

ABI の版を 2 に上げるので、版 1 のプラグインは読み込めなくなる。
Golem はまだ配布しておらず、版 1 のプラグインはリポジトリのテストのものしかない。
