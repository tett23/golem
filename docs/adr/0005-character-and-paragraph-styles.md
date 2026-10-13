# ADR 0005: 強調を文字スタイルへ、韻文を段落スタイルへ統合する

ステータス: 採択→fmt の移行の段階と G0248 は [golem-fmt ADR 0002](../golem-fmt/adr/0002-remove-verse-migration.md)、文字の送りの欄は [docs/adr/0020](0020-indesign-character-features.md)

## 文脈

文字の見た目を変える指定は、今は四か所に分かれている（[markup.md](../markup.md)、[仕様書の「style.toml」](../specifications.md)）。

- 原稿の `[strong: ...]`、`[bold: ...]`、`[italic: ...]`。意味論 IR では `Strong`、`Bold`、`Italic` のインラインの要素になる。
- 原稿の `[style 名前: ...]` と、`style.toml` の `[character-styles.<名前>]`（`font` と `size`）。意味論 IR では `CharStyle` になる。
- `style.toml` の `[emphasis]` の `strong`（`bold` か `italic`）、`bold-font`、`italic-font`（[golem-driver ADR 0004](../golem-driver/adr/0004-pdf-emphasis-and-character-styles.md)）。
- 指定がないときの合成の太字と合成の斜体。PDF の `Golem.Driver.Pdf.restyle` が、`Strong`、`Bold`、`Italic` を `[emphasis]` の値で解釈して決める。

ブロックの側では、韻文だけが専用の記法 `@verse` と専用の節 `[verse]`（`indent`、`hang`、`stanza-gap`）を持つ（[docs/adr/0003](0003-verse-line-breaks.md)）。
段落に名前を付けて見た目をまとめる仕組み（段落スタイル）はない。
仕様書は、v1 のリリースの前に、強調を文字スタイルへ、韻文を段落スタイルへ統合すると決めている（[仕様書の「v1 の実装で次の段階以降に回した項目」](../specifications.md)）。
[docs/adr/0003](0003-verse-line-breaks.md) は、`@verse` をこの統合までの記法とし、意味論 IR の `VerseBlock` と各媒体の出力を段落スタイルの側から使えるように作った。

統合の目標は Adobe InDesign の概念に合わせることである。
InDesign では、文字の見た目は文字スタイル、段落の見た目は段落スタイルにまとめ、スタイルは「基準」（Based On）で別のスタイルを引き継ぐ。
すべての段落は段落スタイルを一つ持ち、指定のない段落は「[基本段落]」になる。
InDesign から移る利用者が、同じ考え方で `style.toml` を書けるようにしたい。

統合には、もう一つ解くべき問題がある。
属性のブロックコマンド（`@label` など）の直後にブロックコマンドを置くと、評価が G0210（「属性の後にブロックがありません」）とする。
文法（[golem-parser ADR 0003](../golem-parser/adr/0003-block-grammar.md)）が、連続したブロックコマンドを一つの `NAttributed` にまとめ、最後のブロックコマンドを対象のブロックとして扱わないためである。
`@label` を付けた `@figure` が markup.md の例にあるのに通らないのも、同じ原因である。
段落スタイルをブロックコマンドで書くなら、`@label` と並べられなければならない。

段落の字下げは、この ADR の段落スタイルの上に [docs/adr/0006](0006-paragraph-indent.md) で加える。
この ADR では、`[verse]` の `indent` と `hang` を今の意味のまま残す。

### 原稿の記法の候補

インラインの側では、次の二つを比べた。

- `[strong: ...]`、`[bold: ...]`、`[italic: ...]` を残し、組み込みの文字スタイルの別名にする。`[strong: 語]` は `[style strong: 語]` と同じ意味論 IR になる。
- 三つのコマンドをなくし、`[style strong: 語]` だけにする。

別名として残す。
強調は原稿の中で最も多く書くインラインの要素であり、毎回 `style` を書かせる利点が、統合の目的（見た目の定義を `style.toml` の一か所に集めること）に対して小さいためである。
統合が要るのは、見た目の定義と意味論 IR であり、原稿の綴りではない。
別名は意味論 IR に痕跡を残さないので、出力とプラグインから見れば記法は一つである。

ブロックの側では、次の三つを比べた。

- `@verse` を残し、組み込みの段落スタイル `verse` の別名にする。
- 段落スタイルを付けるブロックコマンド `@style 名前` を新設し、`@verse` をなくす。`@style` は二つの形で書ける。直後のブロックに付く属性の形と、インデントした本体を持つ形である。
- `@paragraph-style 名前` のように、インラインの `[style ...]` と別の名前にする。

`@style` を新設し、`@verse` をなくす。
`@verse` を別名として残すと、段落スタイルを増やすたびに別名を増やすかどうかを決める必要が生じる。
韻文は強調ほど頻繁には書かないので、`@style verse` の長さは問題にならない。
インラインの `[style ...]` と同じ名前にしても、インラインの要素には文字スタイルしか、ブロックには段落スタイルしか付かないので、書く位置で区別がつく。
InDesign でも、文字スタイルと段落スタイルは別のパネルで同じ「スタイル」という語を使う。

`@style` の二つの形は、どちらも今の文法で解析できる。
属性の形（インデントのない次の行にブロックが続く）は `NAttributed` になり、本体の形（2 つ深くインデントした行が続く）は本体を持つ `NBlockCommand` になる。
本体の形は、複数の段落に一度に同じスタイルを付けるためにある。
一篇の詩の連を並べる書き方は、`@verse` と変わらない。

```
@style quote
引用の段落。この段落だけが quote になる。

@style verse
  Full fathom five thy father lies;
  Of his bones are coral made;

  Nothing of him that doth fade,
  But doth suffer a sea-change
```

## 実装すること

### 原稿の記法

docs/markup.md を次のように改める。

- 「強調」の節：`[strong: ...]`、`[bold: ...]`、`[italic: ...]` は、組み込みの文字スタイル `strong`、`bold`、`italic` を付ける `[style 名前: ...]` の別名であると書く。見た目は `style.toml` の `[character-styles.strong]` などで変える。
- 「文字スタイル」の節：組み込みの文字スタイルの一覧と、利用者が同じ名前の表を書くと組み込みの定義を上書きすることを書く。
- 「段落スタイル」の節を新設する。`@style 名前` の二つの形、本体の形の本体には段落だけを置けること、組み込みの段落スタイル `body`、`verse`、`caption`、`sidenote`、指定のない段落が `body` になることを書く。
- 「韻文」の節：`@verse` を `@style verse` に書き換える。本体の行の扱い（各行の先頭と末尾の空白とタブを無視する、全角の空白は無視しない、散文スロットの中の改行は文字を生まない）は、`line-breaks = "keep"` の段落スタイルの段落の規則として書き直す。
- v1 のブロックコマンドの一覧の `@verse` を `@style` に替える。
- 「ブロックへの属性」の節：`@style` を属性として付けられるのは段落だけであると書く。属性のまとまりの最後に、本体を持つ `@style` や `@figure` のような属性でないブロックコマンドを置くと、それが対象のブロックになると書く。

スタイルの名前は、英小文字で始まり、英小文字、数字、`-` だけからなる（`[a-z][a-z0-9-]*`）。
HTML の class 名にそのまま使うためである。
今の `[character-styles.*]` の名前には制約がないので、この規則は既存の `style.toml` を拒みうる。

### style.toml の文字スタイル（golem-project）

`[character-styles.<名前>]` の欄を次のとおりとする。

| キー | 型 | 意味 |
|---|---|---|
| `based-on` | 文字スタイルの名前 | 基準にする文字スタイル（InDesign の「基準」）。書かなければ基準を持たない |
| `font` | フォントの役割 | 役割が持つ側（`ja`、`latin`）の文字を、その役割で組む。役割が持たない側の文字は、外側の書体のまま組む |
| `size` | 寸法 | 文字の大きさ。`zw` は外側の文字の大きさを一字とする |
| `color` | スウォッチの名前 | 文字の色 |
| `synthetic-bold` | 真偽値 | `true` なら、`font` の役割が持たない側の文字を合成の太字にし、持つ側の文字は太らせない。`font` がなければ両側を太らせる。`false` なら両側とも太らせない |
| `synthetic-italic` | 真偽値 | `synthetic-bold` と同じ規則で、合成の斜体をかける |

`font` の意味は今と変わる。
今は、役割が片側しか持たなくても、両側の文字をその役割で組む。
この ADR の後は、持たない側の文字は外側の書体のまま組む。
`italic-font` だけが持っていた「役割が持たない側を合成で補う」という扱いを、すべての文字スタイルの規則にするためである。

`color` は今の `[color スウォッチ: ...]` と同じ色を付ける。
InDesign の文字スタイルが文字の色を持つことに合わせて加える。

### style.toml の段落スタイル（golem-project）

`[paragraph-styles.<名前>]` の節を新設する。

| キー | 型 | 意味 |
|---|---|---|
| `based-on` | 段落スタイルの名前 | 基準にする段落スタイル。書かなければ `body` とする。`body` 自身には書けない |
| `font` | フォントの役割 | 段落を組む役割。`body` の既定は本文の役割（`Golem.Driver.Pdf.bodyRole`） |
| `size` | 寸法 | 段落の文字の大きさ。`zw` は版面の文字の大きさを一字とする。版面の文字の大きさを超える値は G0311 とする |
| `line-breaks` | `"join"` か `"keep"` | `keep` なら、原稿の段落の中の改行を行の区切りにする。`join` なら、ほかの段落と同じく改行は文字を生まない |
| `space-between` | 0 以上の整数 | 同じ段落スタイルの段落が続くとき、その間に空ける行の数（InDesign の「同じスタイルの段落間のスペース」） |

段落の字下げの欄は [docs/adr/0006](0006-paragraph-indent.md) で加える。
行送りの欄は設けない。
PDF の本文は行の格子に載せる（[仕様書の「style.toml」](../specifications.md)）ので、段落ごとに行送りを変えると、見開きの行の位置がそろわなくなるためである。
`size` に上限を設けるのも同じ理由である。
版面の文字の大きさより大きい文字の段落は、各行が隣の格子の行に重なる。
見出しのように行取りで組む仕組みは、段落スタイルでは扱わない。

### 組み込みのスタイルと利用者の定義

組み込みのスタイルを、`golem-project` の既定の値の表に置く。

| 種類 | 名前 | 定義 |
|---|---|---|
| 文字スタイル | `bold` | `synthetic-bold = true` |
| 文字スタイル | `italic` | `synthetic-italic = true` |
| 文字スタイル | `strong` | `based-on = "bold"` |
| 段落スタイル | `body` | `line-breaks = "join"`、`space-between = 0` |
| 段落スタイル | `verse` | `based-on = "body"`、`line-breaks = "keep"`、`space-between = 1` |
| 段落スタイル | `caption` | `based-on = "body"` |
| 段落スタイル | `sidenote` | `based-on = "body"` |

利用者が組み込みと同じ名前の表を書くと、書いたキーだけが組み込みの定義の同じキーを上書きする。
たとえば `[character-styles.bold] font = "gothic"` は、`synthetic-bold = true` を保ったまま `font` を加える。
`gothic` の役割が `ja` と `latin` の両方を持てば、どちらの文字も合成で太らせない。
利用者が新しい名前の表を書けば、新しいスタイルになる。
組み込みのスタイルを消す方法は設けない。

`caption` と `sidenote` は、図版のキャプションと傍注の本文の書体と大きさを決める段落スタイルである。
キャプションと傍注の本文は意味論 IR の段落ではないが、書体と大きさの指定を段落スタイルの仕組みにまとめるために、段落スタイルとして定義する。
この ADR では名前と定義を置くだけで、キャプションと傍注の組み方は変えない。
キャプションが `caption` の `font` と `size` を使うことは [golem-driver ADR 0010](../golem-driver/adr/0010-caption-style.md) で、傍注が `sidenote` の `font` と `size` を使うことは [golem-driver ADR 0011](../golem-driver/adr/0011-sidenote-font.md) で加える。
二つのスタイルも、ほかの段落スタイルと同じく `@style caption` のように原稿の段落に付けられる。

`body` は InDesign の「[基本段落]」にあたる。
段落スタイルを付けない段落は `body` で組む。
文字スタイルには InDesign の「[なし]」にあたる名前を設けない。
文字スタイルを付けない文字は、段落スタイルの書体と大きさで組む。

### based-on の解決

スタイルの定義は、`based-on` をたどった鎖の根から順に、子のキーが親のキーを上書きして決める。
解決した後も値のないキーは、文字スタイルでは外側の見た目を引き継ぎ、段落スタイルでは `body` の値になる。

`Golem.Project.Style` に、解決した定義を返す関数を置く。

```haskell
data CharStyleDef = CharStyleDef
  { csBasedOn :: !(Maybe Text),
    csFont :: !(Maybe Text),
    csSize :: !(Maybe Dim),
    csColor :: !(Maybe Text),
    csSyntheticBold :: !(Maybe Bool),
    csSyntheticItalic :: !(Maybe Bool)
  }

data LineBreaks = JoinLines | KeepLines

data ParaStyleDef = ParaStyleDef
  { psBasedOn :: !(Maybe Text),
    psFont :: !(Maybe Text),
    psSize :: !(Maybe Dim),
    psLineBreaks :: !(Maybe LineBreaks),
    psSpaceBetween :: !(Maybe Int)
  }

-- | 組み込みの定義に利用者の定義を重ね、based-on をたどって解決した文字スタイル。
-- 未知の名前は Nothing。
charStyle :: Style -> Text -> Maybe CharStyleDef

-- | 解決した段落スタイル。Nothing は body。based-on と既定を埋めるので、
-- psFont と psSize のほかの欄は Just になる。
paraStyle :: Style -> Maybe Text -> Maybe ParaStyleDef
```

`Style` の `stCharStyles` は、組み込みの定義に利用者の定義を重ねた表（`based-on` は解決しない）とし、`stParaStyles :: !(Map Text ParaStyleDef)` を加える。
`parseStyle` の `checks` に次の検査を加え、`charStyle` と `paraStyle` が循環で止まらないことを保証する。

- `based-on` が存在しないスタイルを指す、`based-on` が循環する、`body` に `based-on` がある：G0313。
- 文字スタイルの `color` が `[color.swatches]` にない：G0313。
- 段落スタイルの `font` が `[fonts]` にない：G0308（[golem-driver ADR 0003](../golem-driver/adr/0003-pdf-heading-styles.md) と同じ）。
- `[page.grid]` があり、段落スタイルの解決した `size` を版面の文字の大きさで sp にした値が、版面の文字の大きさを超える：G0311。
- スタイルの名前が `[a-z][a-z0-9-]*` に合わない：G0306。

| 診断コード | 重大度 | メッセージ |
|---|---|---|
| G0313 | エラー | `style.toml のスタイルの参照が不正です: <理由>` |
| G0311 | エラー | `段落スタイルの文字の大きさが版面の文字の大きさを超えます: <名前>` |

G0311 と G0313 は未使用である。
G0310 は [golem-project ADR 0004](../golem-project/adr/0004-font-file-check-per-target.md) が使う。

### 廃止する欄

`[emphasis]` の節と `[verse]` の `stanza-gap` を廃止する。
`Style` から `stStrongAs`、`stBoldFont`、`stItalicFont` と `VerseStyle` の `vsStanzaGap` を削る。
廃止した欄は未知のキーとして G0306 になるが、メッセージで書き換え方を示す。

| 旧 | 新 |
|---|---|
| `[emphasis] strong = "bold"` | 書かなくてよい（既定） |
| `[emphasis] strong = "italic"` | `[character-styles.strong] based-on = "italic"` |
| `[emphasis] bold-font = "r"` | `[character-styles.bold] font = "r"` |
| `[emphasis] italic-font = "r"` | `[character-styles.italic] font = "r"` |
| `[verse] stanza-gap = n` | `[paragraph-styles.verse] space-between = n` |

`[verse]` の `indent` と `hang` は、[docs/adr/0006](0006-paragraph-indent.md) で段落スタイルの欄に移すまで残す。
この ADR の間は、`line-breaks = "keep"` のすべての段落スタイルの段落に効く。

`style.toml` は手で書き換える。
コメントと書式を保ったまま TOML を書き換える仕組みを持たず、Golem はまだ配布していないので、書き換えの対象は golem のリポジトリの中のファイルと、`golem new` の雛形だけである。

### 評価（golem-eval）

`EvalContext` の `ctxCharStyles` を、`stCharStyles` の名前の集合（組み込みを含む）にする。
`ctxParaStyles :: !(Map Text LineBreaks)` を加え、golem-driver が解決した段落スタイルの `line-breaks` を渡す。

インラインの要素は次のとおりにする。

- `builtin` の `"strong"`、`"bold"`、`"italic"` は、それぞれ `CharStyle sp "strong"`、`CharStyle sp "bold"`、`CharStyle sp "italic"` を返す。
- `[style 名前: ...]` は今と同じ。名前の検査は組み込みを含む `ctxCharStyles` で行う。
- `builtinInlineCommands` と `overridableCommands` は変えない。プラグインが `strong` を上書きした場合、原稿の `[strong: ...]` はプラグインに渡り、`[style strong: ...]` は渡らない。

ブロックは次のとおりにする。

- `attributeCommands` に `"style"` を加える。本体のない `@style` は属性である。
- `standalone` の `"style"` は本体の形を評価する。本体がなければ G0210 とする。
- `standalone` の `"verse"` は G0248 とする。`verse` 関数は `styleBody` に改め、次の段落の評価の規則に従う。
- `normalizeBlock` は、本体を持つ `@style` の本体の段落と、`@style` を含む属性のまとまりの対象の段落では、最上位の `SoftBreak` を残す（今の `@verse` の本体と同じく、入れ子のインラインにだけ `joinSoftBreaks` を適用する）。

段落スタイルを付けた段落は、次の関数で評価する。

```haskell
styledParagraph :: EvalContext -> SrcSpan -> Text -> [A.Located A.Inline] -> M [Block]
```

1. 名前が `ctxParaStyles` になければ G0247 とし、段落を `body` として評価する。
2. `line-breaks` が `join` なら、`joinSoftBreaks` をかけて `evalInlines` で評価する。
3. `keep` なら、今の `verse` の手順 3 と 4 に従う。最上位のインラインの列を `SoftBreak` で行に分け、各行の先頭と末尾の空白とタブを取り除いて評価し、空の行を捨てる。残った行を `LineBreak` でつなぐ。
4. 行が一つも残らなければ、段落を捨てる。
5. 名前が `body` なら `Paragraph Nothing`、それ以外は `Paragraph (Just 名前)` のブロックを返す。

本体の形は、本体の各段落に `styledParagraph` を適用する。
本体に段落以外のブロックがあれば、そのブロックの位置で G0245 とする（`A.ErrorBlock` は数えない）。
本体から段落が一つも残らなければ G0246 とする。
本体の形の `@style` の引数が名前一つでなければ、G0247 とする。

属性の形は `attributed` で扱う。
属性に `@style` があり、対象が `A.Paragraph` なら、対象を `evalBlock` でなく `styledParagraph` で評価する。
対象が段落でなければ、今の `applyAttr` と同じく G0213 とし、対象の `SoftBreak` を `joinSoftBreaks` で落としてから `evalBlock` で評価する。

図版のキャプションの本体に `@style` があれば、G0213 とする。
キャプションの段落の見た目は組み込みの段落スタイル `caption` が決め（[golem-driver ADR 0010](../golem-driver/adr/0010-caption-style.md)）、原稿で一つのキャプションごとに別のスタイルを選ぶ仕組みは設けないためである。
キャプションの見た目を変えるには、`style.toml` の `[paragraph-styles.caption]` を書く。

フィルタのプラグインが返した文書の段落スタイルの名前も検査する。
`evalFile` で `phApplyFilters` の後に、`ctxParaStyles` にない名前を持つ `Paragraph` の位置で G0247 とする。

| 診断コード | 重大度 | メッセージ |
|---|---|---|
| G0245 | エラー | `@style の本体には段落だけを置けます。段落は空行で区切ります`（`@verse` から一般化） |
| G0246 | エラー | `@style の本体に段落がありません`（`@verse` から一般化） |
| G0247 | エラー | `style.toml にない段落スタイルです: <名前>`、または `@style には段落スタイルの名前を一つ書きます` |
| G0248 | エラー | `@verse は @style verse に変わりました。golem fmt で書き換えられます` |

G0247 と G0248 は未使用である（golem-eval は G0246 まで使っている）。
G0244（`@verse` の引数）は使わなくなる。
番号は再利用しない。

### 属性の後のブロックコマンド（G0210）

`attributed` で、対象のブロックがなく（`target` が `Nothing`）、まとまりの最後のブロックコマンドが属性でない場合は、それを対象にする。
本体を持つ `@style` は属性でないものとして扱う。

1. 最後のブロックコマンドより前のコマンドがすべて属性なら、最後のブロックコマンドを `standalone` で評価する。
2. 評価の結果の最初のブロックに、前のコマンドの属性を `applyAttr` で付ける。`@label` は最初のブロックに付く。本体の形の `@style` なら最初の段落である。
3. 前のコマンドに属性でないものがあれば、今と同じく G0211 とする。

```
@label song
@style verse
  Full fathom five thy father lies;

@label fig-arch
@figure images/arch.pdf web=images/arch.png alt="Golem の構成図"
  構成図のキャプション。
```

文法（`Golem.peg`）と `Golem.Parser.Lower` は変えない。
[golem-parser ADR 0003](../golem-parser/adr/0003-block-grammar.md) は、後ろにブロックがない場合の扱いを評価に任せている。

### 意味論 IR（golem-doc）と ABI

CDDL（`modules/golem-doc/schema/golem-doc.cddl`）を次のように変え、ABI の版を 3 に上げる。
タグは再利用しないので、形の変わる段落と、なくなる韻文、強調の三つのタグは欠番にする。

```
document = [abi-version: 3, file: uint, blocks: [* block]]

block-body =
    [1, level: 1..3, heading-attrs, inlines]        ; heading
  / ...
  / [8, channel]                                   ; channel output
  / [10, para-style: tstr / null, inlines]         ; paragraph; null is body
; 0 (paragraph without a style) and 9 (verse) are retired (docs/adr ADR 0005)

inline-no-ruby =
    [0, span, tstr]                                ; text
  / [5, span, shape: tstr / null, inlines]         ; kenten
  / ...
  / [16, span, tstr]                               ; proofreading comment
  / [17, span]                                     ; line break
; 1 (strong), 2 (bold) and 3 (italic) are retired: they are character styles (docs/adr ADR 0005)
```

Haskell の型（`Golem.Doc.IR`）。

```haskell
data BlockBody
  = Paragraph !(Maybe Text) [Inline] -- 段落スタイル（Nothing は body）
  | ...                              -- VerseBlock を削る

data InlineF r
  = Text !SrcSpan Text
  | ...                              -- Strong、Bold、Italic を削る
  | LineBreak !SrcSpan               -- 段落の中の強制改行
```

- `abiVersion` を 3 にする。golem-plugin の `abiVersion` も 3 にし、テストのプラグイン（`modules/golem-plugin/test/plugins/*.wat`）の `golem_abi_version` の戻り値を 3 にする。
- `Golem.Doc.Cbor`：タグ 10 とインラインのタグ 17 の符号化と復号。欠番のタグは復号の誤りとする。
- `Golem.Doc.Validate`：`LineBreak` は `Paragraph` の最上位のインラインの列にだけ置け、列の先頭と末尾に置けず、二つ続けて置けない。`Paragraph (Just "body")` は誤りとする（`body` は `Nothing` で表し、一つの段落の表し方を一つにする）。段落スタイルの名前の存在は検査しない（golem-doc は `style.toml` を知らない）。
- `Golem.Doc.Assemble`、`Golem.Plugin`：ブロックとインラインを走査するすべての関数で、`VerseBlock`、`Strong`、`Bold`、`Italic` の場合を削り、`Paragraph` の形を改め、`LineBreak` を何も持たない要素として扱う。
- `noRuby` と `inlineText` も同様に改める。`inlineText` は `LineBreak` を空の文字列にする。

段落スタイルの名前は意味論 IR に置くが、スタイルの中身（書体、行数、字下げ）は置かない。
幾何の隔離（[仕様書の「設計原則」](../specifications.md)）のためである。

### PDF（golem-driver と golem-layout）

文字の見た目は次のとおりにする。

- `Golem.Layout.Look.Look` の `lkEmbolden` と `lkSlant` を、文字の側ごとの組に替える。

  ```haskell
  data Synthetic = Synthetic {synBold :: !Bool, synSlant :: !Bool}

  data Look = Look
    { lkFace :: !Text,
      lkLatinFace :: !Text,
      lkSize :: !Integer,
      lkSynthetic :: !Synthetic,      -- 和文の側
      lkLatinSynthetic :: !Synthetic, -- 欧文の側
      lkColor :: !(Maybe Text)
    }
  ```

- `restyle` は `CharStyle` と `Color` だけを解釈する。`CharStyle` は `charStyle style 名前` の定義を、「style.toml の文字スタイル」の表の規則で外側の見た目に重ねる。`size` は今と同じく `dimToSp (lkSize 外側) size` とする。
- `Golem.Layout.Japanese.piecesOf` と、平らにする関数から `Strong`、`Bold`、`Italic` の場合を削る。
- `drawLine` は、欧文の文字の並びには `lkLatinSynthetic`、それ以外には `lkSynthetic` を使う。今の `slantedIn`（`italic-font` の役割かどうかで傾けるかを決める判定）は削る。側ごとの組が同じことを表すためである。
- `writeDocument` の `runsOf` は、`lkFace` と `lkLatinFace` が異なる場合に加え、`lkSynthetic` と `lkLatinSynthetic` が異なる場合にも、文字の並びを欧文の連続とそれ以外の連続に分ける。片側だけを持つ役割が外側の役割と同じ場合に、同じフォントの中で片側だけを太らせるためである。`runsOf` の各要素は、役割と文字の並びに加え、欧文の連続かどうかを持つ。合成の太字の線の幅を側ごとに変えることは [golem-driver ADR 0012](../golem-driver/adr/0012-synthetic-bold-weight.md) で扱い、この ADR では今の線の幅（文字の大きさの 1/40）を両側に使う。

段落スタイルは次のとおりにする。

- `Unit` に `uFace :: !(Text, Sp)`（段落を組む役割と大きさ）を加え、`faceOf` を `uFace` に替える。見出しは今の `headingFace`、段落は解決した段落スタイルの `font`（なければ `bodyRole`）と `size`（版面の文字の大きさで sp にする。なければ版面の文字の大きさ）、ほかの単位は本文の役割と版面の文字の大きさとする。
- `unitsOf` は、`Paragraph` の最上位のインラインの列を `LineBreak` で分け、一つの部分を一つの単位にする。ラベルは最初の単位にだけ付ける。
- 段落スタイルが `keep` なら、各部分を `UVerseLine` の単位にし、`[verse]` の `indent` と `hang` を使う。今の韻文の行と同じ組み方である。`join` なら `UPara` の単位にする。
- ブロックの列の中で、同じ段落スタイルの段落が続き、その `space-between` が 1 以上なら、その間に `Unit (UGap n)` を置く。続く段落とは、同じブロックの列（文書の最上位、定義リストの説明、リストの項目）の中で隣り合う `Paragraph` である。

- `usedRoles` は、`stBoldFont` と `stItalicFont` の代わりに、すべての段落スタイル（組み込みを含む `stParaStyles`）の `font` を、見出しと文字スタイルの `font` と並べて集める。読み込む役割の決め方、フェイスの番号、G0805 の検査は [golem-driver ADR 0003](../golem-driver/adr/0003-pdf-heading-styles.md) のとおりとする。

組んだ行の幅と位置の計算（`widthOf`、`lineIndent`）、`FSpace` による空き、回り込みの図版の脇で `UVerseLine` を組まないことは、[docs/adr/0003](0003-verse-line-breaks.md) のまま変えない。

### HTML と EPUB（golem-html）

class との対応を次のとおりにする。

| 意味論 IR | HTML |
|---|---|
| `CharStyle "strong"` | `<strong>` |
| `CharStyle "bold"` | `<b>` |
| `CharStyle "italic"` | `<i>` |
| ほかの `CharStyle 名前` | `<span class="cs-名前">` |
| `Paragraph Nothing` | `<p>` |
| `Paragraph (Just 名前)` | `<p class="ps-名前">` |
| `LineBreak` を含む段落の各行 | `<span class="line">` と、行の間の `<br/>` |

組み込みの文字スタイルは、利用者が定義を変えても同じ要素にする。
意味の強調を `<strong>` で表すと、支援技術と EPUB の読書環境が強調として扱えるためである。
韻文の `<div class="verse">` はなくなり、連は `<p class="ps-verse">` になる。

`HtmlConfig` の `hcStrongAs`、`hcCharStyles`、`hcBoldFont`、`hcItalicFont`、`hcStanzaGap` を削り、次の欄を加える。
golem-driver が解決したスタイルから作る。

```haskell
data HtmlCharStyle = HtmlCharStyle
  { hcsFont :: !(Maybe Text),
    hcsBold :: !Bool,   -- 解決した synthetic-bold
    hcsItalic :: !Bool, -- 解決した synthetic-italic
    hcsColor :: !(Maybe Text)
  }

data HtmlParaStyle = HtmlParaStyle
  { hpsFont :: !(Maybe Text),
    hpsKeepLines :: !Bool,
    hpsSpaceBetween :: !Int
  }

-- HtmlConfig に加える欄
hcCharStyles :: !(Map Text HtmlCharStyle) -- 組み込みを含む
hcParaStyles :: !(Map Text HtmlParaStyle) -- body を含む
```

CSS は次の規則で書く。

- 文字スタイルの規則の選択子は、上の表の要素か `.cs-名前` とする。`font` があれば `font-family` に、その役割の書体、本文の役割の書体、`serif` の順の並びを書く。役割が持たない側の文字を本文の書体で組むためである。
- `hcsBold` が真なら `font-weight: bold`、`hcsItalic` が真なら `font-style: italic` を書く。`color` があれば、スウォッチを今の `cmykToRgb` で変換した `color` を書く。
- `font-weight: bold` の文字スタイルの `font` の役割は、その `@font-face` を `font-weight: bold` で宣言する。`font-style: italic` の場合は `font-style: italic` で宣言する（[golem-driver ADR 0004](../golem-driver/adr/0004-pdf-emphasis-and-character-styles.md) の `italic-font` の扱いを太字にも広げたもの）。役割が持つ側の文字は宣言した書体で組まれ、持たない側の文字はブラウザーが本文の書体から合成する。
- 要素の既定の見た目と同じ指定（`b` の太字、`i` の斜体）は書かない。`strong` の規則だけは今と同じく常に書く。既定の `style.toml` の CSS を今の golden（`modules/golem-driver/test/golden/html-style.css`）と一致させるためである。
- 段落スタイルの `font` があれば `p.ps-名前 { font-family: ...; }` を書く。
- `keep` の段落スタイルには `p.ps-名前 { margin-block: 0; margin-inline-start: I; }` と `p.ps-名前 .line { padding-inline-start: H; text-indent: -H; }` を書く。I と H は `[verse]` の `indent` と `hang` を今の `cssLength` で変換した値である。
- `space-between` が 1 以上なら `p.ps-名前 + p.ps-名前 { margin-block-start: <n>em; }` を書く。
- `.line { display: block; }` と `.line + br { display: none; }` を書く。`<br/>` は CSS の効かない読書環境で行を分けるためにある。

`blockNotes` と `sidenotes` から `VerseBlock` の場合を削る。
EPUB は golem-html の出力をそのまま包むので、golem-epub には変更がない。

### プレーンテキスト（golem-text）

`VerseBlock` の場合を削る。
`LineBreak` は、改行と入れ子の字下げ（`indentBy ind`）にする。
段落の間は今と同じく空行なので、韻文の連の間の空行は変わらない。
段落スタイルの書体と `space-between` は出力しない。

### lint（golem-lint）

G0501 の例外を、`@verse` の本体から、`line-breaks = "keep"` の段落スタイルを付けた段落に替える。

- `LintInput` に `liKeepStyles :: !(Set Text)` を加え、`latinJoinedByNewline` の引数にも同じ集合を加える。
- 本体を持つ `@style 名前` の本体の段落と、`@style 名前` を含む `NAttributed` の対象の段落で、名前が集合にあれば、最上位の改行を調べず、散文スロットだけを調べる。
- `Golem.Driver.Lint` は、評価ができた場合は解決した段落スタイルから集合を作る。評価が止まった場合は組み込みの `keep` のスタイル（`verse`）だけを集合にする。

[golem-lint ADR 0001](../golem-lint/adr/0001-lint-rules.md) のステータスの行を「採択→G0501 の韻文の扱いは docs/adr/0003、段落スタイルの扱いは docs/adr/0005」に変え、[docs/adr/0003](0003-verse-line-breaks.md) とこの ADR へのリンクを、書き込む先のファイルからの相対パスで付ける。

### fmt（golem-fmt）と原稿の移行

`golem fmt` に移行の段階を加え、`@verse` を `@style verse` に書き換える。

- `Golem.Fmt` に `migrate :: Node -> Node` を置く。`NBlockCommand` で、名前が `verse` で引数のないものの `KIdent` のトークンを、`style verse` を解析した場合と同じトークンの並び（名前、空白、位置引数）に替える。コードブロックの中の `@verse` は `NBlockCommand` でないので書き換わらない。
- `format` は、`preprocess` の後に解析し、`migrate` をかけて描画した文字列を新しい原稿とする。AST の一致を検査する基準（`astFingerprint`）は、この移行の後の原稿から取る。
- 整形の不変条件は「移行の後の原稿と、整形の結果とで AST が一致する」となる。移行は、評価がエラー（G0248）とする記法を、同じ出力になる記法に替えるだけであり、`preprocess` が BOM と CRLF を直すのと同じ位置づけである。
- `golem fmt --check` は、`@verse` を含むファイルを整形されていないファイルとして報告する。

移行の段階は v1 の間は残し、外すときは別の ADR で決める。
[golem-fmt ADR 0001](../golem-fmt/adr/0001-formatter.md) のステータスの行を「採択→移行の段階は docs/adr/0005」に変え、この ADR へのリンクを、書き込む先のファイルからの相対パスで付ける。

インラインの記法は別名として残すので、移行は要らない。

### LSP（golem-lsp）

- `[style ` の後の補完は、`stCharStyles` の名前（組み込みを含む）を出す。
- 行頭の `@style ` の後で、`stParaStyles` の名前（組み込みを含む）を補完する。`@import ` のパスの補完と同じく、`completions` の最初の分岐に加える。`CompletionKind` に `CkParaStyle` を加え、`Golem.Lsp.Server` で `CkCharStyle` と同じ LSP の種類に写す。
- 新しい診断（G0247、G0248、G0313、G0311）は既存の経路で表示される。

### 変換スクリプトと fixture

- `scripts/fixtures/gutenberg_play_to_gm.py` は `@verse` の代わりに `@style verse` を出力する。
- `modules/golem-driver/test/fixtures/tempest/tempest.gm` は `golem fmt` で書き換えてコミットする。移行の段階を実際の原稿で通す確認を兼ねる。
- `modules/golem-driver/test/fixtures/sample/style.toml` の `[emphasis]` を削る。
- `Golem.Driver.New` の雛形の `[emphasis]` を削り、golden（`new-ja-style.toml`、`new-en-style.toml`）を改める。

### ドキュメント

- 仕様書の「style.toml」の例から `[emphasis]` と `[verse]` の `stanza-gap` を削り、`[character-styles.term]` に `color` を、`[paragraph-styles.quote]` の例を加える。説明の `[emphasis]` の段落を、組み込みの文字スタイルの説明に書き換える。
- 仕様書の「v1 の実装で次の段階以降に回した項目」から「文字スタイルと段落スタイルへの記法の統合」を削る。
- 仕様書の「段落内の改行」の `@verse` を `@style verse` に替える。
- docs/glossary.md に「文字スタイル」「段落スタイル」の項目を加え、「韻文」の項目を `@style verse` に改める。
- README の `style.toml` の説明を改める。
- [docs/adr/0003](0003-verse-line-breaks.md) のステータスの行を「採択→記法と `stanza-gap` は [docs/adr/0005](0005-character-and-paragraph-styles.md)」に変える。
- [golem-driver ADR 0004](../golem-driver/adr/0004-pdf-emphasis-and-character-styles.md) のステータスの行を「採択→`[emphasis]` の欄と文字スタイルの `font` の意味は docs/adr/0005」に変え、この ADR へのリンクを、書き込む先のファイルからの相対パスで付ける。
- [golem-project ADR 0002](../golem-project/adr/0002-style-toml.md) のステータスの行を「採択→`[emphasis]` の廃止と `[paragraph-styles]` は docs/adr/0005」に変え、この ADR へのリンクを、書き込む先のファイルからの相対パスで付ける。

## データ構造の変更

- golem-project：`CharStyleDef` に `csBasedOn`、`csColor`、`csSyntheticBold`、`csSyntheticItalic` を加える。`ParaStyleDef` と `LineBreaks` を新設する。`Style` に `stParaStyles` を加え、`stStrongAs`、`stBoldFont`、`stItalicFont`、`vsStanzaGap` を削る。`charStyle` と `paraStyle` を新設する。
- golem-doc：`BlockBody` の `Paragraph` に段落スタイルを加え、`VerseBlock` を削る。`InlineF` から `Strong`、`Bold`、`Italic` を削り、`LineBreak` を加える。ABI の版を 3 にする。
- golem-eval：`EvalContext` に `ctxParaStyles` を加える。
- golem-layout：`Look` の合成の太字と斜体を側ごとの `Synthetic` に替える。
- golem-driver：`Unit` に `uFace` を加える。
- golem-html：`HtmlConfig` の文字スタイルと強調の欄を `HtmlCharStyle` と `HtmlParaStyle` の表に替える。
- golem-lint：`LintInput` に `liKeepStyles` を加える。
- golem-lsp：`CompletionKind` に `CkParaStyle` を加える。

## 実装しないこと

- 段落の字下げ。[docs/adr/0006](0006-paragraph-indent.md) で扱う。
- 見出しを段落スタイルにすること。`[headings.<階層>]` は番号、目次、柱、行取りを持ち、段落スタイルの欄では表せない。
- 圏点、縦中横、ルビを文字スタイルの欄にすること。圏点の形は今の `[kenten shape=...: ...]` で指定する。縦中横とルビは見た目ではなく文字の並びの構造である。
- `[color スウォッチ: ...]` をなくすこと。文字スタイルの `color` と併存させる。
- 段落スタイルの行送り、段落の前後の空き（InDesign の「段落前のアキ」「段落後のアキ」）、行揃え、次のスタイル、ドロップキャップ。
- 段落スタイルの中で文字スタイルを指定すること（InDesign の「先頭文字スタイル」「正規表現スタイル」）。
- `@style` の引数で、段落ごとにスタイルの欄を上書きすること（InDesign の「オーバーライド」）。
- 見出し、リスト、定義リスト、表、コードブロック、図版に段落スタイルを付けること。
- 組み込みのスタイルを消すこと、名前を変えること。
- `style.toml` の自動の書き換え。
- HTML と EPUB で、文字スタイルと段落スタイルの `size` を使うこと。
- `emphasis` という組み込みの文字スタイルと、HTML の `<em>` への対応。

## テスト設計

先に書き、失敗させてから実装する。

### golem-project（`modules/golem-project/test/Main.hs`）

- 空の `style.toml` で、`charStyle s "strong"` の `csSyntheticBold` が `Just True`、`charStyle s "italic"` の `csSyntheticItalic` が `Just True` になること。`paraStyle s (Just "verse")` の `psLineBreaks` が `Just KeepLines`、`psSpaceBetween` が `Just 1` になること。`paraStyle s (Just "caption")` と `paraStyle s (Just "sidenote")` が `paraStyle s Nothing` と同じ定義になること。
- `[paragraph-styles.caption] size = "0.8zw"` で、`caption` の `psSize` が `Just (Zw (4/5))` になり、`based-on` を書かなくても `body` の `psLineBreaks` を引き継ぐこと。
- `[character-styles.strong] based-on = "italic"` で、`strong` の `csSyntheticItalic` が `Just True`、`csSyntheticBold` が `Nothing` になること。
- `[fonts.gothic]` と `[character-styles.bold] font = "gothic"` で、`bold` の `csFont` が `Just "gothic"`、`csSyntheticBold` が `Just True` になること。
- 存在しない `based-on`、`a` と `b` の循環、`[paragraph-styles.body] based-on = "verse"`、`[color.swatches]` にない `color` が、それぞれ G0313 になること。
- `[page.grid] font-size = "13Q"` で、段落スタイルの `size = "2zw"` が G0311、`size = "0.9zw"` が通ること。
- 段落スタイルの `font` が `[fonts]` にない役割を指すと G0308 になること。
- `[character-styles.Term]`、`line-breaks = "x"`、負の `space-between` が G0306 になること。
- `[emphasis] strong = "bold"` と `[verse] stanza-gap = 1` が G0306 になり、メッセージに書き換え先の節の名前が含まれること。

### golem-eval（`modules/golem-eval/test/FileSpec.hs`）

- `"[strong: a]\n"` と `"[style strong: a]\n"` が、ともに `Paragraph Nothing [CharStyle _ "strong" [Text _ "a"]]` になること。`[bold: a]`、`[italic: a]` も同様であること。
- `"@style verse\n  A\n  B\n\n  C\n"` が、`Paragraph (Just "verse") [Text "A", LineBreak, Text "B"]` と `Paragraph (Just "verse") [Text "C"]` の二つのブロックになること。
- 属性の形 `"@style verse\nA\nB\n"` が `Paragraph (Just "verse") [Text "A", LineBreak, Text "B"]` になること。
- `join` の段落スタイル `quote` で、`"@style quote\nab\ncd\n"` が `Paragraph (Just "quote") [Text "abcd"]` になること。
- `"@style body\nx\n"` が `Paragraph Nothing [Text "x"]` になること。
- `"@style nope\nx\n"` と `"@style\n  x\n"` が G0247、`"@verse\n  A\n"` が G0248、`"@style verse\n  - a\n"` が G0245、`"@style verse\n  %% c %%\n"` が G0246 になること。
- `"@style quote\n# 見出し\n"` が G0213 になり、見出しは評価されること。
- `"@label song\n@style verse\n  A\n"` が G0210 にならず、ラベル `song` を持つ段落になること。`@label` を付けた `@figure` が、ラベルを持つ `FigureBlock` になること。
- [docs/adr/0003](0003-verse-line-breaks.md) の韻文のテスト（行頭の空白、全角の空白、行をまたぐ散文スロット、コメントだけの行、注の番号）を `@style verse` に書き換えて、行が `LineBreak` で区切られた同じ内容になること。
- フィルタのプラグインが `Paragraph (Just "nope")` を返すと G0247 になること。

### golem-doc

- `Gen.hs` の生成器を新しい `Paragraph` と `LineBreak` に改め、往復、決定性、CDDL の検証器（`cddl` の CLI）による適合のテストが通ること。
- ABI の版が 2 の文書、欠番のタグ（ブロックの 0 と 9、インラインの 1、2、3）を含む CBOR の復号が誤りになること。
- `validate` が、`CharStyle` の中の `LineBreak`、段落の先頭と末尾の `LineBreak`、続けて置いた `LineBreak`、`Paragraph (Just "body")` をそれぞれ診断にすること。

### golem-plugin（`modules/golem-plugin/test/Main.hs`）

- テストのプラグインの ABI の版を 3 にして、既存のテストが通ること。
- 版 2 を返すプラグインの読み込みが誤りになること。

### golem-driver（`modules/golem-driver/test/Main.hs`）

- [golem-driver ADR 0004](../golem-driver/adr/0004-pdf-emphasis-and-character-styles.md) の PDF のテストを、`style.toml` を「廃止する欄」の表で書き換えて実行し、PDF のバイト列がこの ADR の前の出力と一致すること。ただし、`italic-font` か `bold-font` が片側しか持たない役割を指すテストでは、持たない側の文字が外側の書体のまま合成で組まれることを確かめる。
- `[character-styles.term] color = "accent"` の `[style term: 語]` で、内容のストリームに `accent` の CMYK の `k` があること。
- `[paragraph-styles.quote] font = "heading"` の `@style quote` の段落が、`heading` の役割のフォントのリソースで描かれること。
- [docs/adr/0003](0003-verse-line-breaks.md) の PDF のテスト（折り返しの `slIndent` と `lineTarget`、縦組み、連の間の空き）を `@style verse` に書き換えて、同じ値になること。`[paragraph-styles.verse] space-between = 2` で、連の間に 2 行の空きが入ること。
- HTML の出力に `<p class="ps-verse">`、`<span class="line">`、`<br/>` があり、`style.css` に `.line { display: block; }` と `p.ps-verse + p.ps-verse` の規則があること。
- `[character-styles.bold] font = "gothic"` の CSS で、`gothic` の `@font-face` が `font-weight: bold` で宣言され、`b` に `font-family` と `font-weight: bold` があること。
- 既定の `style.toml` の CSS が golden（`test/golden/html-style.css`）と一致すること。
- プレーンテキストの出力で、韻文の行が改行で、連が空行で区切られること。
- `scripts/determinism.sh` が出力する sample の各ファイル（PDF、EPUB、HTML、テキスト）のハッシュが、`sample/style.toml` から `[emphasis]` を削った後も、この ADR の前と変わらないこと。

### golem-lint（`modules/golem-lint/test/Main.hs`）

- `"@style verse\n  Full fathom five\n  Of his bones\n"` と、属性の形の `"@style verse\nFull fathom five\nOf his bones\n"` に G0501 が出ないこと。
- `liKeepStyles` に `quote` がないとき、`"@style quote\n  Full fathom five\n  Of his bones\n"` に G0501 が出ること。

### golem-fmt（`modules/golem-fmt/test/Main.hs`）

- golden の `verse.gm` の入力を `@verse` のままにし、期待する出力を `@style verse` にすること。本体のインデントと行分けは今の golden と同じであること。
- `"```\n@verse\n```\n"`（コードブロックの中の `@verse`）が書き換わらないこと。
- `@verse` を含むファイルで `--check` が非ゼロで終わること。
- 二度整形しても結果が変わらないこと。整形の前後の AST の一致のプロパティテストの生成器の `@verse` を `@style verse` に替えること。

### golem-lsp（`modules/golem-lsp/test/Main.hs`）

- 行頭の `@style ` の後の補完に `body`、`verse`、`caption`、`sidenote` と利用者の段落スタイルが出ること。
- `[style ` の後の補完に `strong`、`bold`、`italic` が出ること。

### 変換スクリプトと fixture

自動テストにはしない。
実装の後で、次を確かめる。

- `golem fmt` で `tempest.gm` を書き換えた後、`@verse` が残っておらず、`@style verse` の数が書き換えの前の `@verse` の数と一致すること。
- `scripts/fixtures/fetch-public-domain.sh` で作り直した `tempest.gm` が、`golem fmt` で書き換えたものと一致すること。
- golem-driver のテスト「The Tempest builds horizontally to every target」が通ること。

## トレードオフ

`[strong: ...]` と `[style strong: ...]` の二つの綴りが同じ意味になる。
一つの意味に二つの書き方があるのは、記法を一つにしたい統合の動機に反する。
それでも、意味論 IR と出力から見れば記法は一つであり、頻度の高い強調を短く書ける利点を取る。
プラグインの上書きは原稿の綴りに対して働くので、`[strong: ...]` だけを上書きして `[style strong: ...]` を上書きしないという差が残る。

`@verse` をなくすので、既存の原稿の書き換えが要る。
`golem fmt` の移行の段階で書き換えられるようにし、その代わりに fmt の不変条件に例外を一つ加える。
移行の段階が増えるたびに不変条件の例外が増えるので、移行は v1 の間に限る。

段落スタイルの `line-breaks` は、見た目ではなく原稿の改行の意味を変える。
`style.toml` の一行で、ある段落の改行が文字を生むかどうかが変わり、全媒体の内容が変わる。
韻文の行分けを段落スタイルに統合する以上、この性質は避けられない。
評価が段落スタイルの定義を読むことになり、評価の結果が `style.toml` に依存する範囲が、スウォッチと文字スタイルの名前の検査から一段広がる。

意味論 IR の段落の形を変え、韻文と強調のタグを欠番にするので、ABI の版を上げ、版 2 のプラグインは読み込めなくなる。
Golem はまだ配布しておらず、版 2 のプラグインはリポジトリのテストのものしかない。

文字スタイルの `font` の意味を「役割が持つ側だけ」に変えるので、片側しか持たない役割を文字スタイルや `bold-font` に指定していた文書は、PDF の出力が変わる。
今の挙動では、持たない側の文字がその役割のフォントで引かれ、字形がないか別のフォントに落ちる。
変更の後の挙動のほうが、`italic-font` で決めた規則と一貫する。
v1 のリリースの前なので、この出力の変化は受け入れる。

InDesign の文字スタイルは入れ子にならないが、Golem の文字スタイルは入れ子にでき、内側の欄が外側に勝つ。
`[strong: [style term: 語]]` のような原稿は今も書けるので、入れ子を禁じると既存の原稿が通らなくなる。

`space-between` は InDesign では長さで指定するが、Golem では行の数で指定する。
PDF の本文を行の格子に載せるので、行の数でなければ格子の位置がずれる。
