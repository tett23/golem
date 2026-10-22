# ADR 0030: 改ページの手での制御

ステータス: 採択→ABI のバージョンを上げるかどうかは [ADR 0052](0052-plugin-abi-version-bump-rule.md)

## 文脈

原稿から改ページを改める手段は、`@page-break`（改ページ、改丁、次の偶数ページ）と `@column-break`（改段）だけである（[docs/adr/0017](0017-forced-page-breaks.md)、[docs/adr/0018](0018-multi-column-layout.md)）。
どれも「ここで改める」指定であり、改ページを止めたり、改ページの位置を少しずらしたりする指定はない。
[docs/roadmap.md](../roadmap.md) の「改ページの手での制御」が、これを v1 の課題にしている。
例として、TeX の `\nopagebreak`、needspace パッケージの `\needspace`、`\enlargethispage` を挙げている。

### 今の改ページの規則

PDF の改ページ（`Golem.Layout.Paginate.paginateIn`）は、ブロック（`Flow`）を段の格子に先頭から順に詰める。
コードで確かめた規則は次のとおりである。

- 段落（`FParagraph`）は、孤立行と泣き別れの規則で、段の末尾に 1 行だけ残すことも、次の段に 1 行だけ送ることもしない（`placeLines`）。
- 見出し（`FHeading`）と定義リストの用語（`FDefTerm`）は、続くブロックの最初の部分（`nextNeed`、段落なら最初の 2 行）と同じ段に置く（`keep`）。今の段に入らなければ次の段へ送る。空の段では送らない。
- 図版（`FFigure`）は、今の段に入らなければ後に送り（`sDeferred`）、後の本文を先に置く。
- 改ページの印（`FBreak`）は `sBreaks` にためておき、次のブロックを置く直前に書いた順に適用する。
- `paginate` は診断を返さない純粋な関数である。版面に入らない見出し（G0724）のように、改ページの前に分かる誤りは、golem-driver が `paginate` を呼ぶ前に検査する（[golem-driver ADR 0003](../golem-driver/adr/0003-pdf-heading-styles.md)）。

この規則で組めない組み方が三つある。

1. 二つの段落のあいだで改ページしたくない場合（段落とそれを受ける段落、引用とその出典の段落など）。今の `keep` は見出しと定義リストの用語にしか効かない。
2. 「この先に 5 行分の空きがなければ、次のページから始めたい」場合（短い節の区切り、表や図の前置きの段落など）。今は改ページを手で入れるしかなく、原稿を直すと位置がずれる。
3. ページに 1 行だけ足りずに、段落の最後の 2 行が次のページに送られる場合。和文の組版でも、版面の行数を 1 行だけ増減して追い込むことがある。

### ほかの処理系の対応

- **TeX**：`\nopagebreak` はその位置の改ページの罰則を最大にする。needspace パッケージの `\needspace{<長さ>}` は、ページの残りがその長さに足りなければ改ページする。`\enlargethispage{<長さ>}` は、今のページの本文の高さを一時的に変える（負の値も書ける）。
- **InDesign**：段落スタイルの「段落分離禁止オプション」に「次の段落と連動」（次の段落の最初の行数を同じ段に置く）がある。版面の行数を一つのページだけ増やすには、テキストフレームを手で伸ばす（記憶によるもので、資料では確かめていない）。
- **CSS**：`break-before: avoid` と `break-after: avoid` が改ページを避ける指定である（CSS Fragmentation Module Level 3）。空きの量や版面の行数を変える指定はない。

### 記法の方針

[docs/adr/0017](0017-forced-page-breaks.md) と同じく、本文の流れの中の一点を表す独立したブロックコマンドにする。
三つの指定は、どれもブロックとブロックのあいだの一点に効くので、`@page-break` と同じ規則（文書の最上位にだけ置ける、属性のまとまりの中に書ける、ファイルの末尾の印は次のファイルの最初のものに効く）を当てられる。

空きと行数は、版面の行の格子の行数（整数）で書く。
Golem の版面は行の格子で決まり（仕様書の「style.toml」の節）、本文の行は格子にしか置かれないので、長さで書いても行数に丸めることになるためである。

### 守れない指定

改ページを止める指定は、ほかの規則と矛盾しうる。
改丁の見出しの前、二つのブロックを合わせると段に入らない位置、本の先頭や末尾などである。
矛盾の多くは改ページを計算するまで分からないので、`paginate` の結果に守れなかった指定を載せ、golem-driver が警告にする。
`paginate` は診断を返さない純粋な関数のままにする。

### 未決

- 記法の名前（`@no-page-break`、`@need-lines`、`@page-lines`）。とくに `@page-lines` は、段組みの版面では段の行数を変えるので、名前と意味が少しずれる。
- 守れない指定を警告にするか、エラーにするか。この ADR は警告にする。指定が守れなくても、出力そのものは組めるためである。
- `@page-lines` で増やした行が、ノンブルや柱と重なるかを検査するか。この ADR は、裁ち落としを除いたページの内側に収まるかだけを検査する（「トレードオフ」）。

## 実装すること

### 記法

```
@no-page-break
@need-lines 5
@page-lines +1
@page-lines -1
```

| 記法 | 意味 | TeX | InDesign | CSS |
|---|---|---|---|---|
| `@no-page-break` | 前のブロックと次のブロックのあいだで、改ページも改段もしない | `\nopagebreak` | 次の段落と連動 | `break-before: avoid` |
| `@need-lines N` | 今の段の残りが N 行に足りなければ、次の段から続ける | `\needspace` | なし | なし |
| `@page-lines +N`、`@page-lines -N` | 印の位置の段の行数を、その段に限り N 行増やす（減らす） | `\enlargethispage` | テキストフレームを伸ばす | なし |

- 文書の最上位にだけ置ける。リストの項目、定義リストの説明、ブロックコマンドの本体の中に置くと G0271 とする。本体の形の `@style` の中は、ほかのブロックと同じく G0245 になる。
- `@no-page-break` は引数を取らない。`@need-lines` は 1 以上の整数の位置引数を一つ取る。`@page-lines` は、`+` か `-` の符号を付けた 0 でない整数の位置引数を一つ取る。符号を必須にするのは、版面の行数そのものではなく増減であることを原稿で読めるようにするためである。どれもキーワード引数と本体を持たない。誤りは G0270 とする。
- 属性のまとまりの中に書いてよい。規則は `@page-break` と同じで、まとまりの中の位置によらず、まとまりの対象のブロックの直前に置かれる。`@label` などの属性は、印を飛ばして対象のブロックに付く。
- `@no-page-break` の直前か直後に、印のほかのブロックを挟まずに `@page-break` か `@column-break` を書くと、G0272 とする。改めることと改めないことを同じ位置に指定しているためである。間に `@need-lines` か `@page-lines` があっても、同じ位置とみなす。

### 意味

三つの印はどれも本文の流れの中の一点であり、[docs/adr/0017](0017-forced-page-breaks.md) と同じく、ファイルの末尾の印は次のファイルの最初のものに効く。

#### `@no-page-break`

印の前のブロック（前）の最後の部分と、印の後のブロック（後）の最初の部分を、同じ段に置く。
「後の最初の部分」は、今の `nextNeed` と同じ量（段落なら最初の 2 行、見出しなら占める格子の数）とする。

- 前が段落（`FParagraph`、`FContinued`）か定義リストの用語（`FDefTerm`）なら、改ページは、前の最後の行の後に後の最初の部分が入るように、前の行を次の段に送る。段落は、孤立行と泣き別れの規則を保ち、最後の 2 行（2 行の段落では全体）を送る。見出しの `keep` と同じく、空の段からは送らない。
- 前が見出しなら、今の `keep` がすでに後と離さないので、何も変わらない。
- 前がそのほかのブロック（図版、回り込ませた図版、表、コードブロック、空きの行、目次、索引など）なら、改ページの置き方は変えない。
- どの場合も、後の最初の部分を置いた段が、前の最後の部分を置いた段と異なれば、守れなかった指定（下の「守れない指定の警告」）とする。後が送られた図版である場合、後が改丁の見出しで段を改めた場合、前と後を合わせて段に入らない場合も、これに含まれる。
- 印の前か後に本文のブロックがない場合（本の先頭と末尾）も、守れなかった指定とする。

#### `@need-lines N`

印の後のブロックを置く直前に、今の段の残りの行の数（脚注の行を除いた `free`）が N に足りず、今の段が空でなければ、次の段から続ける。
段組みの版面では次の段、一段組みでは次のページになる。
`@column-break` と違い、残りが足りていれば何もしない。

- 印が続く場合は、最も大きい N を使う。
- 印の後に改ページの印（`@page-break` など）が続く場合は、改ページの印を先に適用し、その後の段で N を判定する。
- N が段の行の格子の数を超える場合は、守れなかった指定とし、N を段の格子の数として扱う（今の段が空でなければ、次の段から続ける）。
- 本の最後の印は捨てる。

#### `@page-lines ±N`

印の位置の段（印の前のものをすべて置いた時点の今の段）の行数を、その段に限り N 行増やす（減らす）。
印の前のもので段が満ちていても、その段に効く。
段の先頭の印は、その段に効く。

- 増やした行は、版面の行の格子を行の進む方向（横組みでは下、縦組みでは左）に延ばした位置に置く。行送りは格子と同じである。
- 脚注は、増やした（減らした）段の下部に置く。区切りの領域の規則（[golem-driver ADR 0024](../golem-driver/adr/0024-rule-spec-and-footnote-separator.md)）は変わらない。
- 一つの段に効く印が複数あれば、増減を足す。
- 段組みの版面では、印の位置の段にだけ効く。ほかの段の行数は変わらない。
- 足した結果の行数は、1 以上で、増やした行が裁ち落としを除いたページの内側に収まる数以下とする。超えた分は切り詰め、守れなかった指定とする。
- 減らした結果の行数が、印の前にその段にすでに置いた行（脚注の行を含む）の数より少なくなる場合は、置いた行の数までしか減らさず、守れなかった指定とする。
- 印の前に、まだ適用していない改ページの印（`@page-break` など）があれば、それを先に適用し、その後の段に効く。`@page-break` の直後に書いた `@page-lines` は、改ページの後のページの段を変える。白ページには効かない。

### 意味論 IR（golem-doc）と ABI

CDDL（`modules/golem-doc/schema/golem-doc.cddl`）に次のブロックを加え、ABI の版を一つ上げる。
今の版は 6 であり、この ADR より前に別の ADR が版を上げていれば、その次の版にする。

```
block-body =
    ...
  / [12, page-control]                             ; manual page break control (docs/adr ADR 0030)

page-control = [0]                                 ; no page break
             / [1, uint .ge 1]                     ; need lines
             / [2, int .ne 0]                      ; adjust the lines of the column
```

```haskell
data BlockBody
  = ...
  | -- | a manual control of page breaks (docs/adr ADR 0030)
    PageControl !PageControl

data PageControl = NoBreak | NeedLines !Int | AdjustLines !Int
  deriving stock (Eq, Show)
```

- `Golem.Doc.Cbor`：タグ 12 の符号化と復号。
- `Golem.Doc.Validate`：`PageControl` は文書の最上位にだけ置け、ラベルを持てない。`NeedLines` は 1 以上、`AdjustLines` は 0 でない。フィルタのプラグインが規則に反するブロックを置いた場合も、ここで誤りになる。
- `Golem.Doc.Assemble`、`Golem.Plugin` などブロックを走査するすべての関数に、何も持たないブロックとして `PageControl` の場合を加える。
- golem-doc と golem-plugin の `abiVersion` と、テストのプラグインの `golem_abi_version` を新しい版にそろえる。

`ForcedBreak` に種類を足さずに別のブロックにするのは、`ForcedBreak` が HTML と EPUB でも `break-before` として意味を持つ「文書の構造の指定」であるのに対し、`NeedLines` と `AdjustLines` は版面の行数に依存する PDF だけの指定だからである。
行数は版面の格子の行数という抽象的な数であり、ページの大きさや位置そのものではないので、意味論 IR の幾何の隔離（仕様書の「設計原則」）に反しない。

### 評価（golem-eval）

- `standalone` に `"no-page-break"`、`"need-lines"`、`"page-lines"` を加え、引数を検査して `PageControl` のブロックを一つ返す。`@need-lines` の引数は語 `5` を整数として、`@page-lines` の引数は語 `+1`、`-2` を符号付きの整数として読む。
- `attributed` が `@page-break` と `@column-break` を取り除く規則（[docs/adr/0017](0017-forced-page-breaks.md)）に、三つのコマンドを加える。書いた順は保つ。
- 最上位でない位置の印は、`nestedBreaks` と同じ走査で取り除き、G0271 とする。
- G0272 は、ファイルの最上位のブロックの列で、`NoBreak` と `ForcedBreak` が `PageControl` のほかのブロックを挟まずに隣り合う位置に出す。ファイルをまたぐ隣り合いは評価では分からないので、改ページで守れなかった指定として扱う。

| 診断コード | 重大度 | 条件 | メッセージ |
|---|---|---|---|
| G0270 | エラー | 引数の誤り | `@no-page-break は引数を取りません`、`@need-lines の引数は 1 以上の整数です`、`@page-lines の引数は +1 や -1 のように符号を付けた 0 でない整数です`、`<名前> は本体を持てません` |
| G0271 | エラー | 文書の最上位でない位置の印 | `@no-page-break、@need-lines、@page-lines は文書の最上位にだけ置けます` |
| G0272 | エラー | 改ページと改ページの禁止が同じ位置にある | `@no-page-break と <@page-break か @column-break> が同じ位置にあります` |

G0270 から G0272 は、02 の区分（評価）の最後に使った G0269 の次の番号である。

### PDF（golem-layout）

`Flow` に三つの値を加える。

```haskell
data Flow
  = ...
  | -- | no page or column break between the flows around (docs/adr ADR 0030)
    FNoBreak !SrcSpan
  | -- | go to the next column unless this many grid lines are free
    FNeedLines !SrcSpan !Int
  | -- | change the grid lines of the current column
    FAdjustLines !SrcSpan !Int
```

- `St` に、まだ適用していない `FNeedLines` の最大値と、今の段の行数の増減の和を加える。`capacity` を使う計算（`free`、`fitting`、`putLine`、`putBlock`、脚注の置き場所）は、今の段の行数（`capacity` に増減を足した値）で行う。
- `FNeedLines` は `FBreak` と同じくためておき、次のブロックを置く直前に、改ページの印の後で判定する。
- `FAdjustLines` は、ためた改ページの印を先に適用してから、今の段の増減に足す。段を進めると増減は 0 に戻る。
- `FNoBreak` は、前のブロックを置くときに `nextNeed` で後の量を見られるよう、`go` が前のブロックの次に `FNoBreak` があるかを見て、前の `place` に後の量を渡す。段落と定義リストの用語の `placeLines` は、この量を見て最後の行を送る。後のブロックを置いた後、前の最後の部分と後の最初の部分の段（ページと段の番号）を比べる。
- `PageOut` に、その段の行数 `poLines :: !Int` と、その段で守れなかった指定 `poUnmet :: ![Unmet]` を加える。

```haskell
data Unmet
  = UnmetNoBreak !SrcSpan
  | UnmetNeedLines !SrcSpan !Int   -- 求めた行数
  | UnmetAdjust !SrcSpan !Int      -- 実際に増減した行数
  deriving stock (Eq, Show)
```

- `nextNeed` は、`FNoBreak`、`FNeedLines`、`FAdjustLines` を飛ばしてその次を見る。見出しの直後に印を書いても、見出しを後のブロックと離さない規則は変わらない。
- 改ページの繰り返し（S2）の途中の結果は使わず、最後の回の `poUnmet` だけを警告にする。

### PDF（golem-driver）

- `UnitKind` に `UPageControl !PageControl` を加え、組んだ単位を `Flow` に写すところで上の三つにする。
- `AdjustLines` の上限は、`pageGeometry` から求めた、版面の行の格子を行の進む方向に延ばして、行の字面が裁ち落としを除いたページの内側に収まる行の数とする。golem-driver はこの値を `paginateIn` に渡す。
- 描画は、行の格子の位置を求める関数（`gridAt`）を、版面の行数を超える番号にも同じ式で延ばす。脚注は、その段の `poLines` から下部の位置を求める。
- `poUnmet` を、次の警告にする。

| 診断コード | 重大度 | 条件 | メッセージ |
|---|---|---|---|
| G0737 | 警告 | 改ページの手での制御を守れなかった | `ここで改ページを止められませんでした`、`@need-lines <N> は段の行数 <M> を超えます`、`@page-lines の増減を <K> 行に切り詰めました` |

警告の位置は印の位置とする。
G0737 は、07 の区分（レイアウト）の空きの番号である。

### HTML と EPUB（golem-html）

- `NoBreak` の後の最初のブロックの要素に、`data-break-before="avoid"` 属性を付ける。改ページの印（`page`、`recto`、`verso`）と同じ属性を使うのは、[docs/adr/0017](0017-forced-page-breaks.md) と同じく、`body` の段落の選び方（`p:not([class])`）を壊さないためである。G0272 があるので、同じ要素に二つの値が来ることはない。
- `style.css` には、本で `@no-page-break` を使った場合に限り、次の規則を書く。

  ```css
  [data-break-before="avoid"] { page-break-before: avoid; break-before: avoid; }
  ```

- `NeedLines` と `AdjustLines` は何も出力しない。Web の媒体は版面の行の格子を持たないためである。
- 文書の最後の `NoBreak` は何も出力しない。

### プレーンテキスト（golem-text）

何も出力しない。
前後のブロックの間の空行も、印がない場合と同じにする。

### fmt と LSP

- golem-fmt は、ほかのブロックコマンドと同じく整形する。
- golem-lsp は、`@page-lines ` の後で `+1` と `-1` を補完する。

### ドキュメント

- [docs/markup.md](../markup.md)：ブロックコマンドの一覧に三つを加え、「改ページ」の節に、記法、置ける位置、意味、守れない指定を書く。
- 仕様書の「改ページ」の節に、三つの印の規則と、HTML と EPUB の出力を書く。
- [docs/diagnostics.md](../diagnostics.md) に G0270、G0271、G0272、G0737 の節を加え、「使っていない番号」の空きから G0737 を除く。
- [docs/roadmap.md](../roadmap.md) の「改ページの手での制御」の項目を消す。
- 使い手のマニュアルの `manual/chapters/03-markup.gm` の改ページの節と `manual/appendices/a-markup.gm` のブロックコマンドの一覧に三つの記法を、`manual/appendices/e-errors.gm` に四つのコードを加える。`manual/appendices/f-indesign.gm` の対応の表に、「次の段落と連動」と `@no-page-break` の行を加える。`manual/appendices/h-roadmap.gm` から項目を消す。
- [docs/adr/0017](0017-forced-page-breaks.md) のステータスの行に、「実装しないこと」の「改ページを禁じる指定」をこの ADR で扱ったことを、この ADR へのリンクで書き足す。
- [golem-layout ADR 0003](../golem-layout/adr/0003-pagination-and-s2.md) のステータスの行に、この ADR へのリンクを書き足す。

## データ構造

- golem-doc：`BlockBody` に `PageControl` を、`PageControl` を新設する。ABI の版を上げる。
- golem-layout：`Flow` に `FNoBreak`、`FNeedLines`、`FAdjustLines` を、`PageOut` に `poLines` と `poUnmet` を、`Unmet` を新設する。`St` に、ためた `FNeedLines` と段の行数の増減を加える。
- golem-driver：`UnitKind` に `UPageControl` を加える。
- golem-html：`HtmlConfig` に、本で `@no-page-break` を使ったかを加える。

## 実装しないこと

- 段落の中（文の途中）に置く印。印はブロックのあいだに置く。
- 段落の中で改ページしない指定（InDesign の「段落内のすべての行を連動」）と、段落スタイルの「次の段落と連動」。スタイルで繰り返し指定する形は、段落スタイルの拡張で扱う。
- 長さ（`mm`、`zw` など）で空きを書く `@need-lines`。行の格子の行数だけを書ける。
- `@page-lines` で、見開きの両方のページの行数をそろえて変えること。
- 増やした行と、ノンブル、柱、傍注欄との重なりの検査。
- 改ページの大域の最適化（[docs/roadmap.md](../roadmap.md) の「改ページの大域の最適化」）。三つの印は、今の貪欲な改ページの上で効く。
- HTML と EPUB の `break-after: avoid` と `break-inside: avoid`。

## テスト設計

先に書き、失敗させてから実装する。

### golem-doc

- `PageControl` の三つの値が CBOR の往復で変わらない。生成器の文書の最上位に `PageControl` を加え、往復のプロパティテストに含める。
- リストの項目の中の `PageControl`、ラベルを持つ `PageControl`、`NeedLines 0`、`AdjustLines 0` を `Golem.Doc.Validate` が誤りとする。

### golem-eval（`test/FileSpec.hs`）

- `"a\n\n@no-page-break\n\nb\n"` が `[Paragraph a, PageControl NoBreak, Paragraph b]` になる。`"@need-lines 5\n"` が `NeedLines 5`、`"@page-lines +1\n"` が `AdjustLines 1`、`"@page-lines -2\n"` が `AdjustLines (-2)` になる。
- `"@need-lines 3\n@label x\n# h\n"` で、ラベルが見出しに付き、印が見出しの前にある。
- `"@no-page-break x\n"`、`"@need-lines\n"`、`"@need-lines 0\n"`、`"@need-lines 2.5\n"`、`"@page-lines 1\n"`（符号なし）、`"@page-lines +0\n"`、`"@page-lines +1 +2\n"`、本体を持つ `"@need-lines 3\n  a\n"` が G0270 になる。
- `"- a\n\n  @no-page-break\n"` が G0271 になり、結果に `PageControl` がない。
- `"@no-page-break\n@page-break\n"`、`"@column-break\n\n@no-page-break\n"`、`"@no-page-break\n@need-lines 2\n@page-break\n"` が G0272 になる。`"@no-page-break\n\na\n\n@page-break\n"` は G0272 にならない。

### golem-layout（`test/Main.hs`）

段落を行の数を決めた `FParagraph` で表し、`paginate` の結果の各段の行の番号で確かめる。

- 格子 10 行の段に 7 行の段落、`FNoBreak`、5 行の段落を置くと、一つ目の段落の最後の 2 行が次の段に送られ、二つ目の段落の最初の行と同じ段にある。`FNoBreak` がない場合は、一つ目の段落が最初の段に収まる（今の結果）。
- 同じ流れで一つ目の段落が 2 行なら、段落の全体が次の段に送られる。
- 格子 10 行の段に 9 行の段落、`FNoBreak`、9 行の段落を置いた空の段では、送らずに置き、`poUnmet` に `UnmetNoBreak` が入る。
- 図版の後の `FNoBreak` で、図版が送られた場合に `UnmetNoBreak` が入る。
- `FHeading` の後の `FNeedLines` と `FNoBreak` が、見出しを後のブロックと離さない規則を変えない（`nextNeed` が印を飛ばす）。
- 残り 4 行の段で `FNeedLines 5` の後の段落が次の段の先頭から置かれ、`FNeedLines 4` では今の段に置かれる。空の段では `FNeedLines 5` が何もしない。
- 二段組みで、`FNeedLines` が次のページではなく次の段に進む。
- `FNeedLines 20`（格子 10 行）が `UnmetNeedLines` を入れ、今の段が空でなければ次の段に進む。
- 本の最後の `FNeedLines` と `FNoBreak` が、ページを増やさない。最後の `FNoBreak` は `UnmetNoBreak` を入れる。
- 格子 10 行の段で、`FAdjustLines 1` の後の 11 行の段落が、一つの段に 11 行とも置かれ、`poLines` が 11 になる。次の段の `poLines` は 10 に戻る。
- `FAdjustLines (-1)` の後の段落が、その段に 9 行までしか置かれない。
- 上限を 1 にして `FAdjustLines 1` を二つ置くと、増減が 1 に切り詰められ、`UnmetAdjust` が入る。
- 8 行を置いた段で `FAdjustLines (-5)` を置くと、段の行数が 8 になり、`UnmetAdjust` が入る。
- `FAdjustLines 1` の段に脚注を持つ行を置くと、脚注が 11 行目から上に置かれる（脚注の行の番号で確かめる）。

### golem-driver（`test/Main.hs` または `PdfSpec.hs`）

- `@page-lines +1` で 1 行増やしたページの最後の行の基準線が、版面の最後の格子の基準線から行送り一つ分だけ先にある。横組みと縦組みの両方で確かめる。
- 版面の下の余白が行送りより狭い版面で `@page-lines +1` を書くと、G0737 の警告が出て、行数が増えない。
- `@no-page-break` を守れない入力（空の段に入らない二つの段落）が G0737 の警告になり、PDF は出力される。
- `@need-lines` に格子の行数を超える値を書くと G0737 の警告になる。
- 印を書かない本の PDF が、この ADR の前とバイト列で一致する（既存の golden と、決定性の検査の sample のハッシュで確かめる）。
- HTML で、`@no-page-break` の後の段落が `<p data-break-before="avoid">` になり、`style.css` に `[data-break-before="avoid"]` の規則がある。`@no-page-break` を使わない本の `style.css` が変わらない。`@need-lines` と `@page-lines` が何も出力しない。
- プレーンテキストで、`"a\n\n@no-page-break\n\nb\n"` が `"a\n\nb\n"` と同じ出力になる。
- 二回のビルドと、並列と逐次の行分割で、PDF のバイト列が一致する。

### golem-plugin と golem-lsp

- `PageControl` を含む文書が、フィルタのプラグインとの往復で変わらない。ABI の版の検査が新しい版で通る。
- `"@page-lines "` の行末での補完が `+1` と `-1` を返す。

### 自動テストにしない確かめ方

- 蟹工船の縦組みの fixture で、段落の最後の 2 行が次のページに送られている箇所の前に `@page-lines +1` を書き、その段落がページに収まり、増やした行が版面の左に行送りの間隔で置かれることを目で確かめる。

## トレードオフ

`@page-lines` は、版面の行の格子の外に行を置く。
行の格子を守ることは Golem の版面の前提であり、この指定はその例外を原稿から作る。
TeX の `\enlargethispage` と同じく、最後の調整の手段として用意し、使った箇所は原稿に残る。
増やした行がノンブルや柱と重なるかは検査しないので、余白の狭い版面では、書き手が目で確かめる必要がある。

守れない指定を警告にしたので、`@no-page-break` を書いても、そこで改ページされることがある。
エラーにすると、原稿を少し直しただけで改ページの位置が動き、ビルドが通らなくなる。
指定の意図が守られなかったことは警告で分かるので、直すかどうかは書き手が決める。

`@no-page-break` で、前の段落の行を送るのは最後の 2 行だけである。
TeX は罰則の和で改ページの位置を選ぶので、より多くの行を送ることもあるが、Golem の改ページは貪欲に詰めるので、孤立行と泣き別れの規則に合わせた最小の量だけを送る。

三つの印は、今の段と次の段だけを見る局所的な指定である。
改ページの大域の最適化を実装すると、同じ印の意味を最適化の制約として定め直す必要がある。

## 参考文献

- Donald E. Knuth, *The TeXbook*, Addison-Wesley, 1984. `\nobreak` と改ページの罰則。章と頁は確かめていない。
- Leslie Lamport, *LaTeX: A Document Preparation System*, 2nd ed., Addison-Wesley, 1994. `\nopagebreak` と `\enlargethispage`。章と頁は確かめていない。
- needspace パッケージ（CTAN, https://ctan.org/pkg/needspace ）。`\needspace` の意味。本文は確かめていない。
- W3C, CSS Fragmentation Module Level 3, https://www.w3.org/TR/css-break-3/ 。`break-before: avoid`。
- InDesign の段落分離禁止オプション。記憶によるものであり、Adobe のヘルプの本文では確かめていない。
