# ADR 0269: 上付きと下付き

ステータス: 採択（未実装）

## 文脈

ロードマップの v1.0.0 の「LaTeX との差を埋める項目」に、「上付きと下付き」がある（[ロードマップ](../roadmap.md)）。
組み込みの文字スタイル `superscript` と `subscript` を加え、書体の上付きと下付きの機能があればそれを使い、なければ大きさと位置で近似する項目である。
HTML と EPUB では `sup` と `sub` にする。
同じ v1.0.0 の「和文組版の拡張」から、添え字を取り出してこの項目に含めている。
出どころは [2026-10-17 の調査](../audits/2026-10-17-latex-gap-for-v1.md) の 14 であり、所有者はこの項目を v1.0.0 に置くと決めた（同じ記録の「所有者の決定」）。

この ADR は [ADR 0268](0268-opentype-features-on-character-styles.md)（文字スタイルの OpenType の機能）の後に実装する。
書体の上付きの字形は、[ADR 0268](0268-opentype-features-on-character-styles.md) が決める範囲ごとの機能の並びに `sups` を足して選ぶ。

### 今の Golem

組み込みの文字スタイルは `bold`、`italic`、`strong`、`code`、`url`、`note-mark` の六つであり、上付きと下付きはない（[仕様書の「style.toml」](../specifications.md#styletoml)、[`Style.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-project/src/Golem/Project/Style.hs#L474-L486)）。
文字スタイルの `size` と `baseline-shift` を書けば、小さくずらした字は組める（[docs/adr/0020](0020-indesign-character-features.md)）。
しかし、HTML と EPUB では `<span class="cs-名前">` になり、`<sup>` と `<sub>` にならない（[`Html.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-html/src/Golem/Html.hs#L672-L678)）。
書体の上付きの字形も使わない。
行分割も、ずらした字の前で行を分け、前の字とのあいだにアキ量のセットの空きを入れうる。

注の印は、上付きと似た字を別の仕組みで組んでいる。
組み込みの `note-mark`（`size = "0.5zw"`）で組み、横組みでは印の字面の枠の上端を本文の字面の枠の上端にそろえ、縦組みでは印の字の列の右端を本文の字面の枠の右端にそろえる（[仕様書の「脚注」](../specifications.md#脚注)、[ADR 0177](0177-note-mark-style-and-numerals.md)）。
印の前では行を分けず、空きも入れない。

### JLReq の添え字

JLReq の 3.7.1「添え字処理」は、添え字（上付きと下付きの字）を次のように扱う。

- 親文字と添え字の字間はベタ組とする。
- 添え字の大きさと位置は、JIS X 4051 では処理系定義である。大きさは、親文字の 60% くらいがよい。
- 添え字の付いた親文字の文字列（cl-21）の字間で、二行に分けない。行の調整でその字間を空けない（3.1.10 の分割禁止にもある）。
- 縦組みでは、添え字の付いた文字列を時計回りに 90 度回転して配置する。短ければ縦中横にしてもよい。

JLReq の 4.5.1 は、添え字を行間にはみ出して配置しうる要素に挙げ、行送りは変えない（2.4.2）。
JLReq の 4.2.3「合印の処理」は、合印の字を添え字の上付きの字と同じとしている。

### InDesign と LaTeX

InDesign は、文字パネルの上付き文字と下付き文字を持ち、書体の機能を使わずに、環境設定の「詳細設定」の大きさと位置の比で字を縮めてずらす（調査の 14）。
OpenType の書体では、上付き序数表記（`sups`）と下付き序数表記（`subs`）の機能も別に選べる。
既定の比は、上付きと下付きのどちらも大きさ 58.3%、位置 33.3% と知られている。
この調査では helpx.adobe.com の本文を読めず、この値を Adobe の資料で確かめていない。

LaTeX は、`\textsuperscript` と `\textsubscript` で字を縮めて上げ下げし、realscripts は fontspec の書体の上付きと下付きの字形を使う。

## 実装すること

### 文字スタイルの欄 `position`

文字スタイルに、欄 `position` を加える。
値は `"normal"`、`"superscript"`、`"subscript"` のどれかで、書かなければ外側の値を引き継ぐ。
本文の根の値は `"normal"` である。
欄の名前と値は、InDesign の文字パネルの「位置」（Position）にそろえる。
これ以外の値は G03006 とする。

組み込みの文字スタイルを二つ加える。

| 名前 | 定義 |
| --- | --- |
| `superscript` | `position = "superscript"` |
| `subscript` | `position = "subscript"` |

原稿では `[style superscript: 2]` と書く。
`[strong: ...]` のような別名は作らない（「メンテナーが決めること」の 4）。

`position` は段落スタイルには置かない。
段落の全体を上付きにする使い方はないからである。

### 大きさと位置を決める規則

`position` が `"normal"` でない字の連なりを、**添え字の範囲**と呼ぶ。
添え字の範囲は、同じ `position` の字が続く最大の連なりであり、文字スタイルの入れ子で途中の見た目が変わっても切れない。
行分割の前に、原稿の範囲だけで決める。

字の**名目の大きさ**を、`position` を無視して `size` の規則（`zw` は外側の名目の大きさで数える）で決めた大きさとする。
添え字の範囲の字は、次の二つの方法のどちらかで組む。
方法は範囲ごとに一つに決め、範囲の途中で変えない。

**書体の字形**：範囲のすべての字が、その字を組む書体（和文の字は和文の書体、欧文の字は欧文の書体）の `sups`（下付きでは `subs`）で別の字形に置き換わるなら、範囲の字を名目の大きさで、機能の並びの最後の段（[ADR 0268](0268-opentype-features-on-character-styles.md) の 4）に `sups` か `subs` を足してシェイピングし、ずらさない。
置き換わるかは、字を一字ずつ、その機能のあるときとないときでシェイピングし、グリフ番号が違うかで決める。

**合成**：そうでなければ、範囲の字を名目の大きさ `s` の 7/12 の大きさで組み、横組みでは上付きを `s` の 1/3 だけ上へ、下付きを `s` の 1/3 だけ下へずらす。
大きさは `⌊7s/12⌋`、ずらす量は `⌊s/3⌋` を sp で求める。
縦組みでは、上付きを右へ、下付きを左へずらす。
`baseline-shift` と同じ向きである。
文字スタイルの `baseline-shift` は、この位置からさらにずらす。

比の 7/12（58.3%）と 1/3（33.3%）は、InDesign の既定として知られる値であり、JLReq の「60% くらい」にも合う（「メンテナーが決めること」の 1）。
比は v1 では `style.toml` に書けない（「メンテナーが決めること」の 2）。

`position` は属性であり、重ねても効果は重ならない。
`superscript` の中に `superscript` を入れても、名目の大きさは外側と同じなので、同じ大きさと位置になる。
`subscript` の中に `superscript` を入れると、内側は名目の大きさからの上付きになる。
`zw` の大きさも名目の大きさで数えるので、上付きの中の `size = "1zw"` は、上付きの外の字と同じ名目の大きさを指す。

書体の字形の方法では、`sups` と `subs` を書き手の `features` より後ろに足すので、書き手が `-sups` を書いても `position` が勝つ。
`position` を書かずに `features = ["sups"]` だけを書けば、字形だけを選び、大きさと位置は変えない。
[ADR 0268](0268-opentype-features-on-character-styles.md) の書体にない機能の報告（G08103）は、Golem が足す `sups` と `subs` には出ない。
書体に機能がなければ合成で組むので、書き手の意図どおりの結果になるからである。

### 行分割と空き

JLReq の 3.7.1 と 3.1.10 に従い、添え字の範囲を注の印と同じく扱う。

- 添え字の範囲の前では行を分けず、空きも入れない（親文字とベタ組）。
- 添え字の範囲の中では行を分けず、アキ量のセットの空きを入れず、行の調整で字間を空けない。
- 添え字の範囲の後ろには、範囲がないときに前の字と次の字のあいだに入る空きが入り、改行の規則もそのときと同じとする。

範囲の後ろの扱いは、注の印の「印の後ろには、印がないときに前の字と次の字のあいだに入る空きが入る」と同じである。
注の印の箱を作る golem-layout の関数を、添え字の範囲にも使う。
範囲の前に字がない（段落の始まり）ときは、範囲を一つの箱として段落の始まりに置く。

ずらした字は、行送りを変えない（JLReq の 2.4.2 と 4.5.1）。
今の `baseline-shift` と同じである。

### 縦組み

JLReq は、縦組みの添え字の付いた文字列を 90 度回転するか、縦中横にするとしている。
Golem は、この回転を作らない（「実装しないこと」）。
縦組みでは、和文の字は縦組みの字形で立て、欧文の字は今のとおり横に倒し、どちらも上の規則で縮めて右か左へずらす。
横に倒した欧文では、右へのずらしは字の上の向きであり、横組みの上付きと同じ見た目になる。
立てた和文の上付きは、注の印と同じく行の右の側に寄る。
短い添え字を縦中横にしたい書き手は、今の縦中横の記法で書ける。

### ルビ、圏点、注の印との関係

ルビの読みは、今の規則のとおり外側の書体と色と大きさの半分で組み、`position` を引き継がない。
ルビの親文字の中の添え字の範囲は、親文字の各字の送りを測る今の規則で測る（[golem-layout ADR 0011](../golem-layout/adr/0011-ruby-base-character-styles.md)）。
圏点は、添え字の範囲の字にも今のとおり付け、字と同じ量だけずらす。

本文の注の印の文字スタイル（`[notes]` の `mark-style`、書かなければ `note-mark`）の `based-on` の鎖で、`position` が `"normal"` でない値に解決するときは、エラー（G03125）とする。
印の位置は [ADR 0177](0177-note-mark-style-and-numerals.md) の規則で決まり、`position` の上げ下げを重ねると、どちらの位置で組むかが決まらないからである。
メッセージは `注の印の文字スタイル <名前> の position は "normal" だけを書けます（印の位置は [notes] で決まります）` とし、位置は `position` を書いた定義の値とする。
コードの番号（G03125）は、採択のときに、使われていない番号であり同じ時期の ADR と重ならないことを確かめて振り直した（「決めたことの記録」）。
注の印に書体の上付きの字形を使いたい本は、[ADR 0268](0268-opentype-features-on-character-styles.md) の `features = ["sups"]` を印の文字スタイルに書く。
注の本文の先頭の印（`body-mark-style`）は、注の本文の行の中で組むので、`position` を書ける。

組み込みの `note-mark` は、`superscript` を `based-on` にしない（「メンテナーが決めること」の 3）。

### HTML と EPUB

文字スタイルの `position` が `"superscript"` に解決する範囲は `<sup>`、`"subscript"` に解決する範囲は `<sub>` で出す。
組み込みの `superscript` と `subscript` は class を持たない `<sup>` と `<sub>` にし、ほかの名前の文字スタイルは `<sup class="cs-名前">` のように class を付ける。
今の組み込みの `strong` と `<strong>` の対応を、`position` を持つスタイルに広げたものである。
大きさとずらしの CSS は書かず、ブラウザーと読書環境の既定に任せる。
正規表現スタイルで当てた文字スタイルも同じ要素にする。

`<sup>` の既定の `vertical-align: super` は、そのスタイルの `baseline-shift` を写した `vertical-align` で置き換わる。
CSS の `vertical-align` は一つの値しか持てないためであり、`position` と `baseline-shift` を一緒に書いたスタイルは、HTML と EPUB で PDF と違う位置になる。
この差は仕様書に書いて受け入れる。

プレーンテキストは、添え字の範囲の字を原稿のまま出す。
`2` を `²` のような Unicode の上付きの字に置き換えると、原稿にない字を出すことになり、置き換えられない字（仮名など）と混じると一貫しない。

### 互換

意味論 IR とプラグインの ABI は変わらない。
文字スタイルは名前で IR に入り、`position` は `style.toml` の中だけの値である。
`abiVersion` と CDDL は変えない。

利用者が `[character-styles.superscript]` か `[character-styles.subscript]` をすでに書いている本は、組み込みの定義の上に書いたキーを重ねる今の規則で、`position` が加わる。
PDF の大きさと位置、HTML の要素が変わる。
実装のプルリクエストの説明とリリースノートに、この変わり方を書く。

### パッケージの依存

golem-* のパッケージのあいだの依存は変えない。
`position` は golem-project に、添え字の範囲と行分割は golem-layout に、方法の選び方と描画は golem-typeset に、要素の対応は golem-html に置き、どれも今の依存の中で済む。

### データ構造

- golem-project の `CharStyleDef` に `csPosition :: !(Maybe Position)` を加える。`Position` は `PositionNormal`、`PositionSuperscript`、`PositionSubscript` である。`overChar` は、ほかの欄と同じく書いた値が勝つ。
- `builtinCharStyles` に `superscript` と `subscript` を加える。
- golem-layout の `Look` に `lkPosition :: !Position` と、名目の大きさ `lkNominalSize :: !Sp` を加える。`lkSize` は、合成の方法では名目の大きさの 7/12 になる。
- 添え字の範囲ごとの方法（書体の字形か合成か）を、行分割の前に golem-typeset が決め、`Look` に入れて golem-layout に渡す。

### 文書

- docs/specifications.md：「style.toml」の節の文字スタイルのキーに `position` を、組み込みの文字スタイルの一覧に `superscript` と `subscript` を加え、大きさと位置の規則、行分割、縦組み、HTML と EPUB の要素、プレーンテキストを書く。「脚注」の節に、印の文字スタイルの `position` の制限を書く。
- docs/diagnostics.md：G03125 を加え、G03006 の主な原因に `position` の値を加える。
- docs/roadmap.md：v1.0.0 の「LaTeX との差を埋める項目」から「上付きと下付き」を消し、v1.0.0 の「和文組版の拡張」から「添え字」を消す。
- 使い手のマニュアル：`manual/chapters/05-style.gm` と `manual/appendices/c-style.gm` に `position` と二つの組み込みのスタイルを書き、`manual/appendices/f-indesign.gm` に InDesign の文字パネルの「位置」と環境設定の比との対応を書き、`manual/appendices/h-roadmap.gm` から項目を消す。
- docs/markup.md は記法を変えないので変えない。

## 実装しないこと

- 縦組みで添え字の付いた文字列を 90 度回転すること（JLReq の 3.7.1）。添え字だけでなく親文字も回すので、親文字の範囲を書く記法が要る。縦中横は今の記法で書ける。
- 親文字の前に付く添え字（化学式の前置の添え字）の空きの規則。親文字の前の字との空きは、範囲の前の字との空きとして今の規則で決める。
- 下付きと上付きを同じ位置に縦に重ねること（JLReq の 3.7.1 の化学式の例）。
- 分子と分母（`numr`、`dnom`）、科学の下付き（`sinf`）、序数（`ordn`）の位置。[ADR 0268](0268-opentype-features-on-character-styles.md) の `features` で字形を選べる。
- 比を `style.toml` に書くこと（「メンテナーが決めること」の 2）。
- プレーンテキストで Unicode の上付きと下付きの字に置き換えること。
- 原稿の別名 `[sup: ...]` と `[sub: ...]`（「メンテナーが決めること」の 4）。

## 不変条件

- **I1 方法は範囲ごとに一つ**：どの添え字の範囲でも、範囲のすべての字が書体の字形の方法で組まれるか、すべてが合成で組まれる。
- **I2 書体の字形の条件**：範囲が書体の字形の方法で組まれるのは、範囲のすべての字について、その字の書体で `sups`（`subs`）の有無によりグリフ番号が変わるときに限る。
- **I3 合成の大きさと位置**：合成で組んだ字の大きさは名目の大きさ `s` の `⌊7s/12⌋` であり、`baseline-shift` を書かない範囲のずらしは、上付きで `⌊s/3⌋` 上（縦組みで右）、下付きで `⌊s/3⌋` 下（縦組みで左）である。書体の字形の方法では、大きさは `s` で、ずらしは `baseline-shift` だけである。
- **I4 重ねても変わらない**：`position` の同じ値を入れ子にした範囲の字の大きさと位置は、入れ子にしない範囲と等しい。
- **I5 範囲の前と中で行を分けない**：どの行の始まりも、添え字の範囲の最初の字の直前と、範囲の中の字のあいだにはない。範囲が段落の始まりにあるときは除く。
- **I6 範囲の後ろは範囲がないときと同じ**：範囲の最後の字と次の字のあいだの空きと改行の罰点は、範囲を消した原稿の、範囲の前の字と次の字のあいだのものに等しい。
- **I7 行送りは変わらない**：`position` を書いた本の各行の基準線の位置は、同じ原稿の添え字の範囲を同じ字数の `position = "normal"` の字に替えた本と、同じ行の数のときに等しい。
- **I8 計測と描画が一致する**：行分割が添え字の範囲の字の送りを測った大きさと機能の並びは、描画のものと等しい。
- **I9 書かない本は変わらない**：`position` を書かず、`superscript` と `subscript` の名前の文字スタイルを使わない本の PDF、HTML、EPUB、プレーンテキストのバイト列と diagnostics は、この変更の前と一致する。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 範囲の字の数 | 0（空の `[style superscript:]`）、1、2、行にちょうど収まる、一字あふれる |
| 範囲の位置 | 段落の始まり、行の途中、行末の直前の字の後ろ |
| 書体の機能 | すべての字が置き換わる、一字だけ置き換わらない、書体が機能を持たない |
| 字の種類 | 欧文の数字だけ、欧文の字と数字、和文だけ、和欧の混じり |
| 入れ子 | なし、同じ値の入れ子、上付きの中の下付き、`size = "1zw"` の入れ子 |
| 書字方向 | 横組み、縦組み（立てた和文と横に倒した欧文） |
| 注の印 | `mark-style` に `position` を書かない、`"normal"` を書く、`"superscript"` に解決する |

## テスト設計

実装の前に書き、失敗することを確かめる。
テストの名前には、不変条件の番号を入れる。

### golem-project（`modules/golem-project/test/Main.hs`）

- `position = "superscript"` を読む。`position = "super"` が G03006 になる。組み込みの `superscript` と `subscript` があり、利用者の同じ名前の表に `size` を書くと、`position` が残る。
- `mark-style` の鎖が `superscript` に行き着く `style.toml` が G03125 になり、`body-mark-style` では出ない。`mark-style` を書かずに `[character-styles.note-mark] position = "subscript"` と書いても G03125 になる。

### golem-layout（`modules/golem-layout/test/`）

- I5、I6：短い和文と欧文の字の列と、その中の一つの添え字の範囲を、行長と範囲の位置を変えて小さな入力のすべてで列挙し、行の始まりが範囲の前と中にないことと、範囲の後ろの空きと罰点が範囲を消した原稿と等しいことを確かめる（[docs/adr/0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の列挙の部品を使う）。
- I4：入れ子の範囲の箱の `Look` の大きさと `lkPosition` が、入れ子にしない範囲と等しい。

### golem-typeset（`modules/golem-typeset/test/`）

- I1、I2：Source Sans Pro の欧文の役割で、`[style superscript: 2]` が書体の字形の方法になり、大きさが名目の大きさのまま `sups` が並びの最後の段に入る。`sups` で置き換わらない字を一字混ぜた範囲は、すべての字が合成になる。Noto Serif JP（`sups` を持たない）の和文の範囲は合成になる。
- I3：合成の範囲の字の大きさとずらしが、10pt の本文で `⌊7 × 10pt/12⌋` と `⌊10pt/3⌋` になる。縦組みで右へ、下付きで左へずれる。
- I8：添え字の範囲を含む段落の、行の箱の幅と描画のグリフの送りの和が一致する。
- I7：添え字の範囲を含む段落の各行の基準線の位置が、範囲を替えた段落と一致する。
- G08103 は、Golem が足した `sups` と `subs` には出ない。

### golem-html（`modules/golem-html/test/`）

- 組み込みの `superscript` が `<sup>`、`subscript` が `<sub>` になる。`based-on = "superscript"` の `x` が `<sup class="cs-x">` になる。正規表現スタイルで当てた `superscript` も `<sup>` になる。

### golem-driver（`modules/golem-driver/test/`）

- I9：`position` を書かない fixture の PDF、HTML、EPUB、プレーンテキストのバイト列と diagnostics が、変更の前に記録したものと一致する。
- プレーンテキストで、`[style superscript: 2]` が `2` のまま出る。

## トレードオフ

書体の字形を使う条件を、範囲のすべての字が置き換わることにした。
一部の字だけを書体の字形にすると、同じ範囲の中で字の太さと高さが変わる。
`m²` の `2` のような数字だけの範囲は、上付きの数字を持つ欧文の書体ならほぼ書体の字形になり、仮名の混じる範囲は合成になる。

置き換わるかを、機能のあるときとないときのグリフ番号の違いで決めた。
書体の GSUB の表の中を読むより、シェイピングの結果で決めるほうが、Golem が描く字形と判定が食い違わない。
字ごとに二度シェイピングする費用は、範囲の字の数に比例し、ランのメモ（[ADR 0253](0253-memoise-run-shaping-and-shorten-the-memo-key.md)）が同じ字の二度めを省く。

合成の比を InDesign の既定として知られる値にした。
JLReq は大きさを「60% くらい」とし、位置を決めていない。
JLReq の言う範囲に入り、InDesign から移した本の添え字が同じ大きさになる値を選んだ。
Adobe の資料で確かめていないので、確かめられたら比を直す ADR を書く。

添え字の範囲の前で行を分けないことにした。
JLReq のとおりであり、`m` と `²` が別の行に分かれることを防ぐ。
その代わり、長い文字列を上付きにすると、範囲の全体が一つの箱になり、行の調整が崩れうる。
上付きにする文字列は短いのがふつうなので、受け入れる。

注の印を `superscript` に寄せなかった。
寄せると、注のあるすべての本の印の大きさ（0.5 から 7/12）と位置が変わり、[ADR 0177](0177-note-mark-style-and-numerals.md) が JLReq の 4.2.3 に合わせて決めた、字面の枠の上端と右端にそろえる配置とも重なる。

## メンテナーが決めること

1. **合成の比**：推奨は、大きさ 7/12（58.3%）、位置 1/3（33.3%）である。InDesign の既定として知られる値で、JLReq の「60% くらい」にも入る。
   - 退けた案の一つは、JLReq の 60%（3/5）にすることである。JLReq は「くらい」と書いており、厳密な値を求めていない。InDesign から移した本と大きさが変わる。
   - もう一つは、LaTeX の `\textsuperscript` の大きさ（10pt の本文で 7pt、70%）にすることである。仕様を決める順で LaTeX は最後であり、JLReq の 60% から離れる。
2. **比を `style.toml` に書けるようにするか**：推奨は、v1 では書けないことである。比を変えたい本は、`position` を書かずに `size` と `baseline-shift` を書いた文字スタイルで組める。比の欄は、後から足しても互換を壊さない。
   - 退けた案は、InDesign の環境設定にあたる `[composition]` の欄を加えることである。使う本がわからないうちに欄を増やすと、欄の検査と文書が増える。
3. **`note-mark` を `superscript` に寄せるか**：推奨は寄せないことである。今の印の大きさと位置が変わり、印の配置の規則と `position` が重なる。印の文字スタイルの鎖の `position` は G03125 で止める。
   - 退けた案は、`note-mark` の `based-on` を `superscript` にし、印の配置を `position` の合成で置き換えることである。注のあるすべての本の PDF が変わり、縦組みの印を行の右端にそろえる JLReq の 4.2.3 の配置を失う。
4. **原稿の別名を作るか**：推奨は作らず、`[style superscript: 2]` と書くことである。別名はコマンドの名前を予約し、同じ名前のプラグインのコマンドと衝突する。組み込みの `url` も別名を持たない。
   - 退けた案は、`[sup: ...]` と `[sub: ...]` を `[strong: ...]` と同じく別名にすることである。短く書けるが、記法の変更なので 1.0.0 の前に決める必要があり、後から足すとプラグインのコマンドの名前と衝突しうる。

## 決めたことの記録

2026-11-09 に、tett23 がすべて推奨のとおりに決めた。

1. 合成の比は、推奨のとおり大きさ 7/12、位置 1/3 とする。
2. 推奨のとおり、v1 では比を `style.toml` に書けない。
3. 推奨のとおり、`note-mark` を `superscript` に寄せない。
4. 推奨のとおり、原稿の別名は作らず、`[style superscript: 2]` と書く。

diagnostic のコードは、採択のときに、docs/diagnostics.md と origin/main のコードで使われていない番号であり、同じ時期の ADR と重ならないことを確かめて、G03125 とした。
草案の仮の番号から振り直した。

## 参考文献

- [2026-10-17 の調査](../audits/2026-10-17-latex-gap-for-v1.md) の 14 と「所有者の決定」
- [ロードマップ](../roadmap.md) の「LaTeX との差を埋める項目」と「和文組版の拡張」
- [仕様書の「style.toml」](../specifications.md#styletoml)、[仕様書の「脚注」](../specifications.md#脚注)
- [ADR 0268](0268-opentype-features-on-character-styles.md)、[ADR 0177](0177-note-mark-style-and-numerals.md)、[docs/adr/0020](0020-indesign-character-features.md)、[docs/adr/0005](0005-character-and-paragraph-styles.md)、[ADR 0253](0253-memoise-run-shaping-and-shorten-the-memo-key.md)、[docs/adr/0204](0204-pagination-invariants-by-exhaustive-small-inputs.md)
- [golem-layout ADR 0011](../golem-layout/adr/0011-ruby-base-character-styles.md)
- W3C, Requirements for Japanese Text Layout（JLReq）, https://www.w3.org/TR/jlreq/ の 2.4.2、3.1.10、3.7.1「添え字処理」、4.2.3、4.5.1、附属書の cl-21
- JIS X 4051:2004 日本語文書の組版方法 4.13 添え字処理（JLReq の引用による。本文は読んでいない）
- Adobe, InDesign User Guide, "Format characters", https://helpx.adobe.com/ca/indesign/using/formatting-characters.html（本文は読めず、調査の抜粋による。上付きと下付きの既定の比は確かめていない）
- Adobe, InDesign User Guide, "Apply OpenType font attributes", https://helpx.adobe.com/indesign/desktop/fonts/opentype-font-attributes.html（同上）
- LaTeX2e unofficial reference manual, `\textsuperscript`, https://latexref.xyz/
- CTAN, realscripts, https://ctan.org/pkg/realscripts
- W3C, HTML Living Standard, the `sub` and `sup` elements, https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-sub-and-sup-elements
