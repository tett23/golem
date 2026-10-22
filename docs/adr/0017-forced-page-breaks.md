# ADR 0017: 原稿から改ページ、改丁、改段を指定する

ステータス: 採択→「実装しないこと」の改ページを禁じる指定は [docs/adr/0030](0030-manual-page-break-control.md)、本の最後の改ページの G0408 は [golem-syntax ADR 0002](../golem-syntax/adr/0002-notice-severity.md)

## 文脈

原稿の任意の位置で改ページする記法がない（[仕様書](../specifications.md)の「v1 の実装で次の段階以降に回した項目」の「強制改ページ」）。
今は、`style.toml` の見出しの `page-break = "recto"` で、その階層の見出しを奇数ページから始めることしかできない（[golem-layout ADR 0003](../golem-layout/adr/0003-pagination-and-s2.md)、[golem-driver ADR 0003](../golem-driver/adr/0003-pdf-heading-styles.md)）。
扉の後、前付けの各項目の間、図版や表をまとめたページの前など、見出しの設定では決まらない位置で改める必要がある。

InDesign では、書式メニューの「分割文字を挿入」から、改段、改フレーム、改ページ、奇数ページで改ページ、偶数ページで改ページを本文に入れる（記憶による）。
段落スタイルの「段落分離禁止オプション」の「開始位置」でも、段落を次の段、次のフレーム、次のページ、次の奇数ページ、次の偶数ページから始められる（記憶による）。
CSS では、`break-before` の `page`、`recto`、`verso`、`column` がこれにあたる（CSS Fragmentation Module Level 3）。

段組みは [docs/adr/0018](0018-multi-column-layout.md) で実装する。
[docs/adr/0018](0018-multi-column-layout.md) は、改段を次の段へ進むこととし、最後の段では次のページの最初の段へ、一段組みでは改ページと同じとし、段の先頭での改段は空の段を一つ作ると決める。
その印を `Flow` にどう表すかは、この ADR に合わせるとしている。

### 今の改ページの処理

- `Golem.Layout.Paginate.paginate` は、行を版面の格子に貪欲に置く。`newPage` が今のページを閉じ、送った図版（`sDeferred`）と続きの脚注（`sPendingNotes`）を新しいページに置く。
- `FHeading` の `fhRecto` が真なら `rectoStart` を通る。今のページが空でなければ閉じ、新しいページが偶数なら白ページ（`poBlank` が真の `PageOut`）を一つ入れる。今のページが空で奇数なら何もしない。
- 白ページには、マスターページの柱とノンブルを描かない（`Golem.Driver.Pdf` の `masterParts`）。
- ページ番号は 1 から数え、奇数ページを右綴じでも左綴じでも recto とする（[golem-layout-spec ADR 0002](../golem-layout-spec/adr/0002-gutter-side-of-odd-pages.md)）。
- HTML と EPUB は、ソースファイル一つを一つの XHTML の文書にする。改ページの指定は出力していない。EPUB の読書環境は、文書の境界で改ページする。

### 記法の候補

次の三つを比べた。

- 独立したブロックコマンド（`@page-break`）：今のブロックコマンドの文法で書ける。InDesign の分割文字と同じく、本文の流れの中の一点を表す。
- 次のブロックに付ける属性（`@page-break` を `@label` と同じ属性にする）：CSS の `break-before` と InDesign の「開始位置」に近い。ただし、属性の後にブロックがない位置（ファイルの末尾、空行の後に続くブロックコマンドの前など）に書くと G0210 になる。ファイルの末尾で「次のファイルの前で改める」と書けない。
- 見出しの設定を広げる（`[headings.*]` の `page-break` に `page` と `verso` を加える）：見出しの階層ごとの規則なので、任意の位置を指定できない。

独立したブロックコマンドを採る。
属性のまとまりの中にも書けるようにし、次のブロックの直前に置いた場合も同じ意味にする（「評価」の節）。

コマンドの名前は、改ページの種類を位置引数に持つ `@page-break` と、改段の `@column-break` の二つにする。
`@page-break` の引数の語 `recto` は、見出しの `page-break = "recto"` と同じ語である。
改段を `@page-break column` とすると、ページを改めない改段を「ページの改め」と書くことになるので、別の名前にした。
一つのコマンド `@break page`、`@break recto`、`@break column` も比べたが、`@page-break` と見出しの設定の名前がそろうことを取った。

## 実装すること

### 記法

```
@page-break
@page-break recto
@page-break verso
@column-break
```

| 記法 | 意味 | InDesign | CSS |
|---|---|---|---|
| `@page-break` | 次のページから続ける（改ページ） | 改ページ | `break-before: page` |
| `@page-break recto` | 次の奇数ページから続ける（改丁） | 奇数ページで改ページ | `break-before: recto` |
| `@page-break verso` | 次の偶数ページから続ける | 偶数ページで改ページ | `break-before: verso` |
| `@column-break` | 次の段から続ける（改段） | 改段 | `break-before: column` |

- 文書の最上位にだけ置ける。リストの項目、定義リストの説明、ブロックコマンドの本体（`@figure` のキャプション、本体の形の `@style`）の中には置けない（G0259）。本体の形の `@style` の中は、今と同じく G0245 になる。
- 位置引数は `@page-break` に一つまで（`recto` か `verso`）、`@column-break` にはない。キーワード引数と本体は持たない。誤りは G0258 とする。
- 属性のまとまりの中に書いてよい。まとまりの中の位置によらず、まとまりの対象のブロックの直前に改ページを置く。`@label` などの属性は、`@page-break` を飛ばして対象のブロックに付く。

```
@page-break recto
@label appendix
# 付録
```

docs/markup.md のブロックコマンドの一覧に二つを加え、「改ページ」の節を設けて上の規則を書く。

### 改ページの意味

改ページの印は、本文の流れの中の一点である。
印の後にある最初のもの（行、見出し、図版、表など）を、次の規則で決まる位置から置く。

- `page`：今のページを閉じ、次のページから置く。今のページに何も置いていなくても閉じる。中身のないページは白ページになる。InDesign で、テキストフレームの先頭に改ページの文字を入れると、そのフレームが空のまま残るのと同じである（記憶による）。
- `recto`：今のページに何も置いておらず、奇数ページなら何もしない。そうでなければ今のページを閉じ、次の奇数ページから置く。途中の偶数ページは白ページになる。見出しの `page-break = "recto"` と同じ規則である。
- `verso`：`recto` の奇数と偶数を入れ替えた規則。
- `column`：[docs/adr/0018](0018-multi-column-layout.md) の規則で次の段へ進む。今の段に何も置いていなくても進む。一段組みでは `page` と同じである。

印の後に何もない場合（本の最後の改ページ）は、印を捨てる。
本の最後に白ページを作らないためである。
ファイルの末尾の印は、次のファイルの最初のものに効く。
印が続く場合は、書いた順にそれぞれを適用する。
`@page-break` を二つ続けると、白ページが一ページできる。
`@page-break` の後に `page-break = "recto"` の見出しが続くと、改ページの後のページが偶数なら、見出しの規則でさらに白ページが一ページ入る。

### 意味論 IR（golem-doc）と ABI

CDDL（`modules/golem-doc/schema/golem-doc.cddl`）に次のブロックを加え、ABI の版を一つ上げる。
今の版は 3 で、この ADR だけを実装すれば 4 になる。
この ADR の実装より前に別の ADR（[docs/adr/0019](0019-aki-settings.md) など）が版を上げていれば、その次の版にする。

```
block-body =
    ...
  / [11, break-kind]                               ; forced break (docs/adr ADR 0017)

break-kind = 0..3                                  ; page, recto, verso, column
```

Haskell の型（`Golem.Doc.IR`）。

```haskell
data BlockBody
  = ...
  | -- | a forced break before what follows (docs/adr ADR 0017)
    ForcedBreak !BreakKind

data BreakKind = BreakPage | BreakRecto | BreakVerso | BreakColumn
  deriving stock (Eq, Show, Enum, Bounded)
```

- `Golem.Doc.Cbor`：タグ 11 の符号化と復号。
- `Golem.Doc.Validate`：`ForcedBreak` は文書の最上位のブロックの列（`docBlocks`）にだけ置ける。ラベルを持てない（`blockLabel` が `Nothing`）。フィルタのプラグインが別の位置に置いた場合も、ここで誤りになる。
- `Golem.Doc.Assemble`、`Golem.Plugin`、`noRuby` などブロックを走査するすべての関数に、何も持たないブロックとして `ForcedBreak` の場合を加える。目次、索引、図番号、見出しの番号は数えない。
- `abiVersion` を上の次の版にする。golem-plugin の `abiVersion` も同じ版にし、テストのプラグイン（`modules/golem-plugin/test/plugins/*.wat`）の `golem_abi_version` の戻り値もそろえる。

改ページの種類は意味論 IR に置くが、ページの大きさや位置は置かない。
「次のページから始める」は文書の構造の指定であり、HTML と EPUB でも CSS の `break-before` として意味を持つので、幾何の隔離（[仕様書](../specifications.md)の「設計原則」）に反しない。

### 評価（golem-eval）

- `standalone` に `"page-break"` と `"column-break"` を加え、引数を検査して `ForcedBreak` のブロックを一つ返す。
- `attributed` は、まとまりの `cmds` から名前が `page-break` と `column-break` のブロックコマンドを先に取り除き、書いた順に `standalone` で評価する。残りの `cmds` と対象のブロックは今の規則で評価し、その結果を改ページのブロックの後に並べる。残りの `cmds` が空で対象のブロックがあれば、対象のブロックを `evalBlock` で評価する。残りの `cmds` が空で対象のブロックもなければ、改ページのブロックだけを返す。
- `@label x` の直後に空行を挟まず `@page-break` だけが続く場合、`@page-break` を取り除いた残りは対象のない属性になり、今と同じく G0210 になる。[docs/adr/0005](0005-character-and-paragraph-styles.md) の、まとまりの最後の属性でないブロックコマンドを対象にする規則は、改ページのコマンドには当てない。改ページにラベルを付ける意味がないためである。
- 文書の最上位でない位置の改ページは、評価の後に取り除いて G0259 とする。`evalFile` の最後（フィルタのプラグインの前）に、ブロックの木を走査して、最上位でない `ForcedBreak` の位置で G0259 を出し、そのブロックを捨てる関数 `nestedBreaks :: [Block] -> ([Block], [Diagnostic])` を通す。評価の各所に深さを持ち回らずに済むためである。

| 診断コード | 重大度 | 条件 | メッセージ |
|---|---|---|---|
| G0258 | エラー | 引数の誤り | `@page-break の引数は recto か verso です`、`@column-break は引数を取りません`、`@page-break と @column-break は本体を持てません` |
| G0259 | エラー | 文書の最上位でない位置の改ページ | `@page-break と @column-break は文書の最上位にだけ置けます` |

G0258 と G0259 は未使用である（G0256 と G0257 は [docs/adr/0016](0016-hard-line-breaks.md) が使う。origin/main のコードと docs の ADR、作業中の ADR に記載はない）。

### PDF（golem-driver と golem-layout）

- `Golem.Driver.Pdf` の `UnitKind` に `UBreak !BreakKind` を加え、`unitsOf` は `ForcedBreak k` を `Unit (UBreak k) Nothing [] sp bodyFace` にする。同じ段落スタイルの段落の間の空き（`gapBefore`）は、間に改ページを挟んだ二つの段落を続いた段落として扱わない。
- 組んだ単位を `Flow` に写すところで、`UBreak k` を `FBreak k` にする。
- `Golem.Layout.Paginate.Flow` に `FBreak !BreakKind` を加える。`BreakKind` は golem-doc の型を使う（golem-layout はすでに golem-doc に依存している）。
- `St` に `sBreaks :: ![BreakKind]`（まだ適用していない印）を加える。`place` は `FBreak k` を `sBreaks` に足すだけにし、ほかの `Flow` を置く前に `sBreaks` を書いた順に適用して空にする。`go` の最後（`flushDeferred` の前）では、残った `sBreaks` を捨てる。
- `nextNeed` の `FBreak` は 0 とする。見出しの直後の改ページで、見出しをページの末尾に残すことを防ぐ規則は設けない（「トレードオフ」）。
- 印の適用は次の関数で行う。

  ```haskell
  applyBreak :: St -> BreakKind -> St
  applyBreak st = \case
    BreakPage -> breakPage st
    BreakRecto -> parityStart odd st
    BreakVerso -> parityStart even st
    BreakColumn -> breakPage st -- docs/adr ADR 0018 replaces this with the next column
  ```

  - `breakPage`：今のページが空でも閉じる。空のまま閉じたページは白ページ（`poBlank` が真）とする。今の `closePage` は、中身のないページを `sDone` に加えない場合があるので、改ページで閉じる場合は、中身のないページも白ページとして必ず加える。
  - `parityStart p`：今の `rectoStart` を、奇数か偶数かを引数にして一般化したもの。`rectoStart` は `parityStart odd` に置き換える。
- 送った図版（`sDeferred`）は、今の `newPage` と同じく、改ページの後の新しいページの先頭に置く。白ページには置かない。
- 続きの脚注（`sPendingNotes`）も、今の `newPage` と同じく次のページに続ける。改ページで閉じたページが脚注の続きだけを持つ場合は、白ページではなく、脚注を置いたページとして閉じる。
- 柱の値（`sHead`）は改ページで変えない。白ページには柱もノンブルも描かない（今の `masterParts` のまま）。

[docs/adr/0018](0018-multi-column-layout.md) を実装するときは、`BreakColumn` を「次の段へ進む」に、`BreakPage` を「今の段がどの段でも次のページの最初の段へ進む」に改める。
この ADR の実装では、段組みの PDF は一段目にしか本文を流さないので、`BreakColumn` を改ページとして扱う。

### HTML と EPUB（golem-html）

改ページの印の後の最初のブロックの要素に、`data-break-before` 属性を付ける。

```html
<h1 id="..." data-break-before="recto">...</h1>
```

```css
[data-break-before="page"] { page-break-before: always; break-before: page; }
[data-break-before="recto"] { page-break-before: always; break-before: recto; }
[data-break-before="verso"] { page-break-before: always; break-before: verso; }
```

- `Golem.Html.block` は、ブロックの列を描くときに、直前の改ページの種類を次のブロックに渡す。次のブロックの最も外側の要素（`<p>`、`<h1>`、`<ul>`、`<table>`、`<figure>`、`<nav>` など）に属性を付ける。印が続けば、最後の印の種類を付ける。
- class ではなく属性にするのは、[docs/adr/0014](0014-in-file-settings.md) の文書ごとの規則が `body` の段落を `p:not([class])` で選ぶためである。class を足すと、その段落が `body` の規則から外れる。
- `page-break-before: always` を先に書くのは、`break-before` を知らない読書環境でも改ページさせるためである。`break-before` を知る環境では、後に書いた `break-before` が同じ性質を上書きする（CSS Fragmentation Module Level 3 は `page-break-before` を `break-before` の別名とする）。
- 改段（`column`）は、Web の媒体に段組みがないので、属性も規則も書かない（[docs/adr/0018](0018-multi-column-layout.md) の「改段は Web の媒体では見た目に現れない」に合わせる）。
- 文書（XHTML）の最後のブロックの後の印は、何も出力しない。EPUB の読書環境は文書の境界で改ページし、改丁は表せないためである。
- `style.css` には、本で使った種類の規則だけを書く。改ページを使わない本の `style.css` を変えず、既存の golden を保つためである。`HtmlConfig` に `hcBreakKinds :: !(Set BreakKind)` を加え、golem-driver がすべての文書から集める。
- `blockNotes`、`sidenotes` などブロックを走査する関数は、`ForcedBreak` を何も持たないブロックとして扱う。

EPUB は golem-html の出力を包むので、golem-epub は変えない。

### プレーンテキスト（golem-text）

何も出力しない。
前後のブロックの間の空行も、改ページがない場合と同じ一つにする。
改ページの文字（U+000C）を書く案は、テキストの差分や表示で扱いにくく、プレーンテキストの読み手がページを持たないので採らない。

### lint（golem-lint）

規則は加えない。

### fmt（golem-fmt）

コードは変えない。
`@page-break` と `@column-break` はほかのブロックコマンドと同じく整形する。

### LSP（golem-lsp）

- 行頭の `@page-break ` の後で、`recto` と `verso` を補完する（`CkSettingValue`）。
- G0258 と G0259 は、評価の診断として既存の経路で表示される。

### ドキュメント

- markup.md：ブロックコマンドの一覧に `@page-break` と `@column-break` を加え、「改ページ」の節を設けて記法、置ける位置、属性のまとまりとの関係、四つの種類の意味を書く。
- 仕様書：「v1 の実装で次の段階以降に回した項目」から「強制改ページ」を削る。改ページの規則を書いている箇所に、原稿の改ページと白ページの規則を加える。
- docs/glossary.md の「組版」に「改ページ」「改丁」（次の奇数ページから始めること）「白ページ」の項目を加える。「改段」は [docs/adr/0018](0018-multi-column-layout.md) が加える。
- [golem-layout ADR 0003](../golem-layout/adr/0003-pagination-and-s2.md) のステータスの行を「採択→原稿の改ページは docs/adr/0017」に変え、この ADR へのリンクを、書き込む先のファイルからの相対パスで付ける。

## データ構造の変更

- golem-doc：`BlockBody` に `ForcedBreak` を、`BreakKind` を新設する。ABI の版を上げる。
- golem-layout：`Flow` に `FBreak` を、`St` に `sBreaks` を加える。`rectoStart` を `parityStart` に一般化する。
- golem-driver：`UnitKind` に `UBreak` を加える。
- golem-html：`HtmlConfig` に `hcBreakKinds` を加える。

## 実装しないこと

- 段落の途中（文の途中）での改ページ。印はブロックの間に置く。
- 改フレーム。フレームはレベル 2 以降である（[仕様書](../specifications.md)の「フレーム」）。
- 段落スタイルの「開始位置」と、見出しの `page-break` に `page` と `verso` と `column` を加えること。
- 見出しの `page-break = "recto"` を HTML と EPUB の CSS に出すこと。見出しの改ページは今と同じく PDF でだけ効く。
- 改ページの直前に見出しや定義リストの用語がある場合に、それらを次のページへ送ること。
- 白ページに柱やノンブルを描く設定。
- 改ページを禁じる指定（`break-inside: avoid` にあたるもの）。
- プレーンテキストでの改ページの表現。

## テスト設計

先に書き、失敗させてから実装する。

### golem-doc

- `ForcedBreak` の各種類が CBOR の往復で変わらないこと。生成器（`test/Gen.hs`）の文書の最上位に `ForcedBreak` を加え、往復のプロパティテストに含める。
- リストの項目の中の `ForcedBreak` と、ラベルを持つ `ForcedBreak` を `Golem.Doc.Validate` が誤りとすること。

### golem-eval（`test/FileSpec.hs`）

- `"@page-break\n\na\n"` が `[ForcedBreak BreakPage, Paragraph Nothing [Text "a"]]` になること。`"@page-break recto\n"`、`"@page-break verso\n"`、`"@column-break\n"` がそれぞれの種類になること。
- `"@page-break recto\n# h\n"`（空行なし）が `[ForcedBreak BreakRecto, Heading ...]` になり、G0211 が出ないこと。
- `"@page-break\n@label x\n# h\n"` と `"@label x\n@page-break\n# h\n"` のどちらでも、ラベル `x` が見出しに付き、改ページのブロックが見出しの前にあること。
- `"@label x\n@page-break\n\na\n"` が G0210 になること。
- `"@page-break page\n"`、`"@page-break recto verso\n"`、`"@page-break x=1\n"`、`"@column-break recto\n"`、本体を持つ `"@page-break\n  a\n"` が G0258 になること。
- `"- a\n\n  @page-break\n"` と `"= t\n  @page-break\n"` と `"@figure x.png alt=a\n  @page-break\n"` が G0259 になり、結果に `ForcedBreak` がないこと。`"@style quote\n  @page-break\n"` が G0245 になること。

### golem-layout（`test/Main.hs`）

段落を一行の `FParagraph` で表し、`paginate` の結果のページの数と `poBlank` で確かめる。

- 1 ページ目の途中の `FBreak BreakPage` の後の段落が 2 ページ目の先頭に置かれること。
- `FBreak BreakPage` が二つ続くと、2 ページ目が白ページになり、段落が 3 ページ目に置かれること。
- 本の先頭の `FBreak BreakPage` が、1 ページ目を白ページにすること。
- 1 ページ目の途中の `FBreak BreakRecto` の後の段落が 3 ページ目に置かれ、2 ページ目が白ページであること。2 ページ目の途中なら、白ページなしで 3 ページ目に置かれること。
- 3 ページ目の先頭（空のページ）の `FBreak BreakRecto` が何もしないこと。
- `FBreak BreakVerso` が、1 ページ目の途中から 2 ページ目に、2 ページ目の途中から 4 ページ目に送ること（3 ページ目は白ページ）。
- 本の最後の `FBreak BreakPage` と `FBreak BreakRecto` が、ページを増やさないこと。
- `FBreak BreakPage` の直後の `FHeading` で `fhRecto` が真の場合、改ページの後のページが偶数なら白ページが一つ入り、奇数なら入らないこと。
- 送った図版がある状態の `FBreak BreakPage` で、図版が次のページの先頭に置かれ、白ページに置かれないこと。
- 一段組みの `FBreak BreakColumn` が `FBreak BreakPage` と同じ結果になること。

### golem-driver（`test/Main.hs`）

- `@page-break` を挟んだ二つの段落の PDF が 2 ページになり、二つ目の段落が 2 ページ目の一行目にあること。
- `@page-break` を二つ続けたプロジェクトの PDF で、白ページに柱とノンブルが描かれないこと。
- HTML で、`"@page-break recto\n# h\n"` の見出しが `data-break-before="recto"` を持ち、`style.css` に `[data-break-before="recto"]` の規則があり、`page` と `verso` の規則がないこと。
- HTML で、`@page-break` の後の `body` の段落が `<p data-break-before="page">` になり、class を持たないこと。
- HTML で、ファイルの末尾の `@page-break` が何も出力しないこと。`@column-break` の後の段落が属性を持たないこと。
- プレーンテキストで、`"a\n\n@page-break\n\nb\n"` が `"a\n\nb\n"` と同じ出力になること。
- 既存の golden と、`scripts/determinism.sh` の sample の各ファイルのハッシュが、この ADR の前と変わらないこと。

### golem-plugin（`test/Main.hs`）

- `ForcedBreak` を含む文書が、フィルタのプラグインとの往復で変わらないこと。ABI の版の検査が新しい版で通ること。

### golem-lsp（`test/Main.hs`）

- `"@page-break "` の行末での補完が `recto` と `verso` を返すこと。

## トレードオフ

改ページを独立したブロックにしたので、InDesign の段落スタイルの「開始位置」のように、スタイルで繰り返し指定することはできない。
同じ位置で何度も改めるなら、見出しの `page-break` のように設定で表すほうがよい。
段落スタイルの開始位置は、段落スタイルの拡張（[仕様書](../specifications.md)の「段落スタイルの拡張」）で検討する。

`page` の改ページは、空のページでも閉じる。
`@page-break` を二つ続けると白ページになり、InDesign で改ページの文字を二つ続けたときと同じ結果になる（記憶による）。
今の `recto` の見出しは空のページでは改めないので、`recto` と `verso` は空のページで改めず、`page` だけが空のページでも改める、という二つの規則が並ぶ。
`recto` と `verso` は「どのページから始めるか」の指定であり、空の奇数ページはすでにその条件を満たしている。
`page` は「ここでページを改める」の指定であり、空のページでも改めることで、白ページを原稿から作れる。
一方で、ファイルの先頭に `@page-break` を書く習慣があると、直前のファイルが `recto` の見出しで終わった場合などに意図しない白ページができる。

本の最後の印を捨てるので、本の末尾に白ページを足す手段はない。
印刷所の求める総ページ数の調整（16 ページの倍数にするなど）は、改ページではなく別の設定で扱うべきことである。

見出しの直後に改ページを書くと、見出しがページの末尾に一人で残りうる。
今の規則は、見出しの直後で改ページしない（見出しを次のページに送る）ことを、ページが満ちた場合にだけ適用している。
原稿の改ページは書いた人の指定なので、見出しを送ることはせず、指定のとおりに組む。

HTML と EPUB の改丁（`break-before: recto`）は、多くの読書環境とブラウザーで、ただの改ページとして扱われると考えられる（未確認）。
`page-break-before: always` を併記しているので、少なくとも改ページはされる。
EPUB の見開きの左右は読書環境が決めるので、Golem の側で白ページを足して奇数ページに合わせることはしない。

ABI の版を上げるので、配布済みのフィルタのプラグインは作り直しが要る。
v1 はまだ配布していないので、影響はテストのプラグインに限られる。
