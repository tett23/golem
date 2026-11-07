# ADR 0189: 段落スタイルに行揃え、段落の前後のアキ、行の終わりの側の字下げを加える

ステータス: 採択→見出しの先読みが空きの行を後の量に数えることは [ADR 0205](0205-rules-added-by-the-implementation-of-adr-0180.md)

## 文脈

扉、献辞、エピグラフ、署名、奥付は、ふつうの本のほぼすべてにある。
どれも中央揃えか地付き（横組みでは右揃え）で組むが、今の Golem はそれを組めない。
段落スタイルの欄（[`ParaStyleDef`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-project/src/Golem/Project/Style.hs#L243-L273)）に、行揃えの欄がないからである。

段落のまわりの空きも同じ事情にある。
今あるのは、同じ段落スタイルの段落が続くときの `space-between` だけで（[`gapBefore`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L1265-L1274)）、引用の前と後に一行ずつ空けるといった指定は書けない。
行の終わりの側の字下げもないので、引用を両側から字下げして組めない。
字下げは行の始まりの側の `indent` と `first-line-indent` だけである（[docs/adr/0006](0006-paragraph-indent.md)）。

ロードマップの v0.1.0-rc4 の「LaTeX との差を埋める項目」は、この三つを「段落の行揃え」「段落の前後のアキ」「行の終わりの側の字下げ」として挙げ、同じ ADR で決めてよいとする（[docs/roadmap.md](../roadmap.md)）。
三つとも v2 の「段落スタイルの拡張」から先に取り出すもので、根拠は [2026-10-17 の調査](../audits/2026-10-17-latex-gap-for-v1.md) の 1 から 3 である。

### 今の振る舞いの確かめ

`~/.local/bin/golem`（`golem --version` は `0.1.0-rc3`、2026-11-06 にビルドしたもの）で、横組みの小さなプロジェクトの `style.toml` に次の段落スタイルを書き、`golem check` を走らせた。

```toml
[paragraph-styles.title]
align = "center"
space-before = 1
end-indent = "2zw"
```

三つのキーとも、`知らないキーです` の G03006 になった。

### 行の組み方

PDF の段落は、Knuth-Plass の行分割（[golem-layout ADR 0001](../golem-layout/adr/0001-knuth-plass-line-breaking.md)）で行に分け、最後の行のほかを行長いっぱいに伸ばす（両端揃え）。
段落の終わりには、伸びが無限に近いグルー（`filStretch`）を置くので（[`lineEnd`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-layout/src/Golem/Layout/Japanese.hs#L255-L256)、[`filStretch`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-layout/src/Golem/Layout/KnuthPlass.hs#L105-L110)）、最後の行は自然な幅のまま行の始まりに寄る。
InDesign の名前でいえば、今の Golem は「均等配置（最終行左揃え）」だけを持つ。
行の中の箱の位置は、グルーの伸び縮みの比（[`glueRatio`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-layout/src/Golem/Layout/KnuthPlass.hs#L430-L466)）で決まる。

揃えを持つのは、今は表のセルだけである。
セルは、行に分けた後、行の内容の幅と列の幅の差だけ行をずらして右揃えと中央揃えを作り、両端揃えにした行はずらさない（[`layoutTable`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-layout/src/Golem/Layout/Table.hs#L114-L125)）。
セルの行分割は両端揃えのままなので、最後の行だけが揃う。

字下げは、行ごとの行長を短くする形で働く。
`indent` と `first-line-indent` は、行分割に渡す行ごとの行長から引かれる（[`widthOf` と `lineIndent`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L1440-L1448)）。

### 空きの扱い

`space-between` の空きは、二つの段落のあいだに置く `UGap` の単位であり、段の先頭では捨てる。
行アキ（`@blank-line`）も同じ規則で、行アキを挟んだ二つの段落には `space-between` を足さない（[仕様書](../specifications.md) の「行アキ」の節、[docs/adr/0046](0046-blank-line-command.md)）。

HTML と EPUB では、`space-between` を `p.ps-<名前> + p.ps-<名前>` の `margin-block-start` に、行の数を `em` にして書く（[`paraRules`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-html/src/Golem/Html.hs#L1069-L1078)）。
それ以外の段落のあいだは、ブラウザーの既定の `p` の余白（上下に 1em）である。
HTML の段落には今 `text-align` を書かないので、本文はブラウザーの既定（行の始まりに寄せ、行の終わりを揃えない）で表示される。

### InDesign と LaTeX

[2026-10-17 の調査](../audits/2026-10-17-latex-gap-for-v1.md) の要約によれば、InDesign の段落の行揃えは五種類ある。
左揃え、中央揃え、右揃え、均等配置（最終行を左か中央か右に揃える）、両端揃え（最終行も揃える）である。
ほかに、ノド側に揃える指定と小口側に揃える指定を持つ。
ノド側と小口側の二つは、縦組みのフレームでは使えない。
段落前のアキと段落後のアキを持ち、同じスタイルの段落のあいだのアキは、二つの段落が同じスタイルのときだけ適用される。
段落前のアキは、段とフレームの先頭では適用されない。
右インデントを持つ。

LaTeX は、`\centering`、`\raggedright`、`\raggedleft` で揃えを変える。
`\raggedright` と `\centering` は、行の端に伸びが無限のグルー（`\rightskip` と `\leftskip` の `0pt plus 1fil`）を置き、段落の中のグルーの伸びを使わない（latexref の「\raggedright」）。
縦の空きは `\vspace` と `\addvspace` で置き、`\addvspace` は続けて置いた空きのうち大きいほうだけを残す。
`quote` と `quotation` は両側を字下げする。

## 実装すること

段落スタイルに四つのキーを加える。

| キー | 値 | 既定 |
| --- | --- | --- |
| `align` | `"left"`、`"center"`、`"right"`、`"left-justified"`、`"center-justified"`、`"right-justified"`、`"fully-justified"`、`"towards-spine"`、`"away-from-spine"` | `"left-justified"` |
| `space-before` | 0 以上の整数（行の数） | 0 |
| `space-after` | 0 以上の整数（行の数） | 0 |
| `end-indent` | 0 以上の長さ（`indent` と同じ書き方） | 0 |

`body` の組み込みの定義（[`bodyDefaults`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-project/src/Golem/Project/Style.hs#L348-L359)）に既定の値を加え、ほかの段落スタイルは `based-on` で引き継ぐ。
既定の値は今の組み方と同じなので、キーを書かない本の出力は、PDF、HTML、EPUB、プレーンテキストのどれも変わらない。
`@style-def` でも同じキーを書ける。
LSP の `style.toml` の補完（[ADR 0169](0169-lsp-completion-in-style-and-preflight-toml.md)）の表（[`paraStyleNode`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-project/src/Golem/Project/Style.hs#L2542-L2563)）にも加える。

### 行揃え（`align`）

値の名前は、InDesign の行揃えの名前を kebab-case にしたものとする（「メンテナーが決めること」の 1）。

| 値 | 最後のほかの行 | 最後の行 | InDesign |
| --- | --- | --- | --- |
| `left` | 行の始まりに寄せる | 行の始まりに寄せる | 左揃え |
| `center` | 中央に置く | 中央に置く | 中央揃え |
| `right` | 行の終わりに寄せる | 行の終わりに寄せる | 右揃え |
| `left-justified` | 両端を揃える | 行の始まりに寄せる | 均等配置（最終行左揃え） |
| `center-justified` | 両端を揃える | 中央に置く | 均等配置（最終行中央揃え） |
| `right-justified` | 両端を揃える | 行の終わりに寄せる | 均等配置（最終行右揃え） |
| `fully-justified` | 両端を揃える | 両端を揃える | 両端揃え |
| `towards-spine` | ノドの側に寄せる | ノドの側に寄せる | ノド側に揃える |
| `away-from-spine` | 小口の側に寄せる | 小口の側に寄せる | 小口側に揃える |

縦組みでは、`left` を天付き、`right` を地付きと読む。
行の始まりは天、行の終わりは地である。
値はほかに受け付けず、ほかの値は G03006 とする。
`towards-spine` と `away-from-spine` は横組みの本でだけ使える（下の「ノド側と小口側の揃え」）。

揃えの基準は、字下げを引いた後の行の領域である。
行の領域は、行の始まりの側を `indent`（最初の行は `indent + first-line-indent`）、行の終わりの側を `end-indent` だけ縮めた範囲とする。
`center` は、この領域の中央に置く。
`verse` のようにぶら下げた段落では、最初の行と折り返した行とで領域が違うので、中央の位置も行ごとに違う。

#### ノド側と小口側の揃え

`towards-spine` と `away-from-spine` は、横組みの本で、行をページのノドの側か小口の側に寄せる（「メンテナーが決めること」の 2 と 8）。

- 行の分け方は `left` と `right` と同じで、両端を揃えない行の組み方（下の節）で分ける。行に分けた後、行が置かれたページのノドの側を求め、ノドの側が左なら `towards-spine` を `left`、`away-from-spine` を `right` と同じにずらす。右なら逆にする。
- ノドの側は、柱と傍注と同じく `gutterSide` で、`[page]` の `binding` とページの番号の偶奇から決める（[`LayoutSpec.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-layout-spec/src/Golem/LayoutSpec.hs#L97-L104)）。
- 行の分け方はページによらないので、ページが決まった後に行をずらしても、改ページは変わらない。一つの段落が二つのページにまたがれば、ページごとに寄せる側が変わる。
- 段組みの版面でも、段によらずページのノドの側に寄せる。

縦組みの本で `towards-spine` か `away-from-spine` を書くと、エラー（G03118）とする（「メンテナーが決めること」の 10）。

- 縦組みの行は天から地へ進むので、ノドと小口は行の方向に交わらず、行をノドの側に寄せることが意味を持たない。InDesign は縦組みのフレームではこの二つを適用しない。Golem は、書いた値を黙って適用しない出力を作らずに止める。
- 書字方向は `style.toml` の `[page]` の `writing-mode` で本の全体に一つなので、`style.toml` を読むときに判定できる。`@style-def` は `style.toml` を読んだ後に評価するので（[`fileStyles`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-eval/src/Golem/Eval/Settings.hs#L157)）、同じコードで止める。
- メッセージは `縦組みの本では、段落スタイル <名前> の align に <値> を書けません。ノドと小口は横組みの本でだけ使えます` とする。位置は `align` の値（`@style-def` ではそのキーの引数）とする。
- G03006 にまとめない。値そのものは正しく、書字方向との組み合わせが原因なので、直し方（`writing-mode` か `align` を変える）が違う。

HTML と EPUB にはページの左右がない。
二つの値は、本の最初のページ（1 ページ、奇数のページ）のノドの側で読み替えて書く（「メンテナーが決めること」の 9）。
左綴じ（`binding = "left"`）の横組みの本では、`towards-spine` は `text-align: left`、`away-from-spine` は `text-align: right` になる。
右綴じの横組みの本では逆になる。

#### 両端を揃えない行の組み方

`left`、`center`、`right` の段落と、均等配置の段落の最後の行は、両端を揃えない。
両端を揃えない段落は、LaTeX の `\raggedright` と `\centering` と同じく、次のように行に分ける（「メンテナーが決めること」の 3）。

- 段落の中のグルーの伸びを 0 にする。縮みは今のまま残す。アキ量のセットの空き（[ADR 0019](0019-aki-settings.md)）も同じで、自然な量より空けることはなく、詰めることはある。
- 行分割の `Params` に、各行の端に足す伸びを持たせ、その伸びを `filStretch` とする。どの行も伸びの比が 0 に近くなり、不良度（badness）は 0 になるので、行分割は、行の数とペナルティの和が最も小さい分け方を選ぶ。
- 行に分けた後、各行の箱を自然な幅で並べ（グルーの比 0）、行の領域と内容の幅の差を、`left` なら行の終わりの側に、`right` なら行の始まりの側に、`center` なら両側に半分ずつ置く。差が奇数の sp なら、余りの 1sp を行の終わりの側に置く。
- 縮めた行は行の領域いっぱいになるので、差は 0 になる。

字幅の伸縮（[golem-layout ADR 0005](../golem-layout/adr/0005-microtypography.md)）は、両端を揃えない行では使わない。
グルーの伸びを使わないのと同じ理由で、行を領域に合わせる必要がないからである。
禁則、ぶら下げ組、突き出し、ハイフネーションは、今のまま使う。
ハイフネーションのペナルティは今のままなので、伸びを使わない行では、分綴よりも次の行に送る分け方が選ばれやすい。
LaTeX の `\raggedright` が分綴をほとんどしないのと同じ性質である。

均等配置の三つの値は、最後のほかの行を今のとおり両端揃えで組む。
最後の行は、段落の終わりのグルーの伸び（`filStretch`）が受け持つので、今も自然な幅で組まれている。
`center-justified` と `right-justified` は、その行を、`center` と `right` と同じ規則でずらす。
`fully-justified` は、段落の終わりの `filStretch` のグルーを置かず、最後の行もほかの行と同じく行の領域いっぱいに伸ばす。
伸びるグルーを持たない最後の行（欧文の一語だけの行など）は伸ばせないので、行の始まりに寄せる。

コードだけでできた行のように伸びるグルーのない行は、今は両端揃えにせず、自然な幅のまま行の始まりに寄せる（[仕様書](../specifications.md) の「style.toml」の節）。
この規則は、両端を揃える行に限った規則として残す。
両端を揃えない行は、上の規則でずらす。

#### 揃えを当てる段落

`align` は、今の字下げ（`indent` と `first-line-indent`）を当てる段落と同じ段落に当てる（「メンテナーが決めること」の 6）。
文書の最上位の段落、`@style` の本体の段落、定義リストの説明の段落である。
リストの項目の中の段落、図版のキャプション、脚注と傍注の本文、表、見出し、目次、索引、参考文献には当てない。

`@style caption` と `@style sidenote` を付けた原稿の段落には当てる。
`caption` と `sidenote` の `align` は、図版のキャプションと傍注の本文には当てない（[golem-driver ADR 0010](../golem-driver/adr/0010-caption-style.md)）。
キャプションの揃えは、v2 の「図版とキャプションの拡張」の項目のままとする。
`code` に `align` を書くと G03006 とする。
コードブロックは段落ではなく、行を揃えないからである（[golem-driver ADR 0017](../golem-driver/adr/0017-pdf-code-blocks.md)）。

`line-breaks = "keep"` の段落は、改行で区切った一行ずつを一つの単位として組む（[`block` の `Paragraph`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L1284-L1295)）。
揃えは、その単位ごとに、上の規則で当てる。
`fully-justified` は、各単位の最後の行も伸ばす。

### 段落の前後のアキ（`space-before` と `space-after`）

単位は `space-between` と同じく行の格子の行の数とし、行の格子を崩さない。
空きは、今の `space-between` と同じ `UGap` の単位として、ブロックのあいだに置く。

二つの続いたブロック A と B のあいだの空きの行の数を、次のように決める（「メンテナーが決めること」の 4）。

1. A と B のあいだに行アキ（`@blank-line`）があれば、行アキの行だけを空け、段落の前後のアキと `space-between` は足さない。今の `space-between` の規則を広げたものである。
2. A と B が同じ段落スタイルの段落なら、今のとおり `space-between` の行を空け、A の `space-after` と B の `space-before` は使わない。複数の段落からなる引用の段落のあいだに、前後のアキが入らないようにするためである。
3. それ以外は、A が段落なら A の `space-after`、B が段落なら B の `space-before` を取り、大きいほうの行を空ける。段落でないブロック（見出し、図版、表、コードブロック、リストなど）は 0 とする。

段の先頭に来た空きは、今の `space-between` と行アキと同じく捨てる（「メンテナーが決めること」の 5）。
段の先頭の空きは、前の段の終わりの余白と見分けられないからである。
段落の後のアキで段が終わる場合も、空きは次の段の先頭に来て捨てられる。
`space-between` と同じく、捨てても diagnostic は出さない。
空きを捨てたことを知らせる G07047 は、原稿に書いた `@blank-line` だけを対象とする。
段落スタイルの空きは、段の先頭で捨てることを含めて書き手が指定したものだからである。

見出しを後と離さない規則と `@no-page-break` の先読みは、今の `space-between` の空きと同じく、空きの行を後のものの量に足す。

`line-breaks = "keep"` の段落では、`space-before` を最初の行の単位の前に、`space-after` を最後の行の単位の後に置く。
行のあいだには置かない。

段落の罫線（[golem-driver ADR 0027](../golem-driver/adr/0027-paragraph-style-rules.md)）を持つ段落では、前後のアキの行を罫線の領域の外に置き、罫線の領域とは別に数える。
今の `space-between` の空きの行と罫線の領域の関係と同じである。

段落の前後のアキを当てる段落は、段落の罫線を引く段落と同じとする（「メンテナーが決めること」の 6）。
文書の最上位の段落と、`@style` の本体の段落である。
リストの項目、表のセル、注の本文、定義リストの中の段落には当てない。
`@style caption` と `@style sidenote` を付けた原稿の段落には当てる。
`code` に書くと G03006 とする。

`space-before` と `space-after` に負の数を書くと、`space-between` と同じく G03006 とする。
罫線の指定の表にも `space-before` と `space-after` があるが、表の中のキーであり、段落スタイルの直下のキーとは別のものである。

### 行の終わりの側の字下げ（`end-indent`）

`end-indent` は、段落のすべての行の終わりの側の字下げであり、InDesign の右インデントにあたる。
行の終わりの側から測るので、縦組みでは地からの距離になる。
`zw` は、`indent` と同じく段落の文字の大きさを一字とする。
`indent` と同じく負の値は書けず、負の値は読めない長さとして G03006 とする。

PDF では、行分割に渡す行ごとの行長から `end-indent` を引く。
最初の行の行長は「段の行長 − `indent` − `first-line-indent` − `end-indent`」、ほかの行は「段の行長 − `indent` − `end-indent`」になる。
回り込ませる図版の脇の行では、脇の行の長さから同じく引く。

`end-indent` を当てる段落は、`indent` を当てる段落と同じである。
`caption` と `sidenote` に 0 でない `end-indent` を書くと、今の `indent` と同じく G03006 とし、0 なら notice（G03100）とする（[golem-driver ADR 0043](../golem-driver/adr/0043-caption-sidenote-do-not-inherit-indent.md)）。
`code` に書くと G03006 とする。

字下げが大きすぎる段落スタイルのエラー（G07025）は、`end-indent` を含めて判定する。
判定は「段の行長 − `indent` − max(0, `first-line-indent`) − `end-indent` が段落の文字の大きさの 8 字分に満たない」とする（[`indentDiagnostics`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L343-L357)）。
原因は今と同じ「字下げで行長が足りなくなる」ことなので、別のコードにはしない。
回り込ませる図版の脇の行のエラー（G07028）も、`end-indent` を引いた長さで判定する。

段落の罫線の長さは、今のとおり段の行長から罫線の `start-indent` と `end-indent` を引いた長さで、段落の字下げには合わせない。

### HTML と EPUB

段落スタイルの CSS に、次の宣言を加える。
書く条件は、今の字下げと同じく、`body` では既定の値でないとき、ほかのスタイルでは `body` と値が違うときとする（「メンテナーが決めること」の 7）。
既定の値の本の CSS は変わらない。

| キー | CSS |
| --- | --- |
| `align = "left"` | `text-align: start` |
| `align = "center"` | `text-align: center` |
| `align = "right"` | `text-align: end` |
| `align = "left-justified"` | `text-align: justify; text-align-last: start` |
| `align = "center-justified"` | `text-align: justify; text-align-last: center` |
| `align = "right-justified"` | `text-align: justify; text-align-last: end` |
| `align = "fully-justified"` | `text-align: justify; text-align-last: justify` |
| `align = "towards-spine"` | 1 ページのノドの側が左なら `text-align: left`、右なら `text-align: right` |
| `align = "away-from-spine"` | 1 ページのノドの側が左なら `text-align: right`、右なら `text-align: left` |
| `end-indent` | `padding-inline-end`（`zw` は `em`。`indent` と同じ書き方） |

`start` と `end` は書字の方向に沿う値なので、縦組みの EPUB でも天付きと地付きになる。
ノドと小口の二つの値は横組みの本にしかないので、物理の向きの `left` と `right` で書く。
`text-align-last` を読書環境が読むかは確かめていない。

段落の前後のアキは、ブロックの境目の規則を、隣り合う兄弟の要素のセレクターで書く。
行の数は、`space-between` と同じく `em` にする。

- B の `space-before`：`p.ps-B { margin-block-start: <n>em; }`
- A の `space-after`：`p.ps-A + :not(.ps-A):not(.blank-line) { margin-block-start: <n>em; }`。`:not()` の中を単純なセレクターにして、Selectors Level 3 の範囲に収める。行アキには当てない。
- A と B の両方が空きを持つ組：`p.ps-A + p.ps-B { margin-block-start: <max>em; }`。組ごとの値は `style.toml` だけで決まるので、組み立てるときに計算して書く。この規則を、前の二つの後に書く。
- 同じスタイルの段落のあいだ：今のとおり `p.ps-A + p.ps-A` に `space-between` を書く。A が前か後のアキを持てば、`space-between` が 0 でも `margin-block-start: 0` を書き、前のアキの規則に勝たせる。
- 行アキの後の段落：前のアキを持つスタイル B ごとに、`div.blank-line + p.ps-B { margin-block-start: 0; }` を書く。PDF の「行アキがあれば行アキだけ」に合わせるためである。前のアキを持つスタイルがなければ書かないので、今の HTML は変わらない。

`body` の規則は、今の字下げの規則と同じセレクター（`style.toml` では `p`、ファイルの定義では `p:not([class])`）で書く。
`body` は class を持たないので、上の `.ps-A` の否定は、class の有無（`[class]`）で書き分ける。
空きが 0 の宣言は、上の二つの場合のほかは書かない。

`@style-def` で定義を重ねたファイルでは、今の段落スタイルの規則（`body.file-<n>` で始まる規則）と同じく、上の宣言をすべて書き直す。

### プレーンテキスト

プレーンテキストは行長を持たず、行を折り返さないので、四つのキーを使わない。
`space-between` を使わないのと同じである。

### 仕様書とマニュアル

[docs/specifications.md](../specifications.md) の「style.toml」の節の段落スタイルのキーの一覧、字下げの記述、「行アキ」の節（`space-between` と並べて前後のアキを書く）、HTML の CSS の節を更新する。
使い手のマニュアルの段落スタイルの章に、扉、献辞、引用の例を加える。
[docs/roadmap.md](../roadmap.md) の三つの項目を外し、v2 の「段落スタイルの拡張」から、段落の前後の空き、行揃え、行の終わりの側の字下げを外す。
[docs/diagnostics.md](../diagnostics.md) に G03118 の節を足す。

### InDesign との差異の文書

InDesign との差異を、[docs/adr/0179](0179-lines-ending-in-explicit-hyphens.md) が作る TeX との差異の文書と同じ docs/differences-from-tex-and-indesign.md に書く（「メンテナーが決めること」の 11）。
文書の節の形は、[docs/adr/0179](0179-lines-ending-in-explicit-hyphens.md) の決めたとおりとする。
この ADR を [docs/adr/0179](0179-lines-ending-in-explicit-hyphens.md) より先に実装する場合は、この ADR の実装で文書を作る。
この ADR の実装で、次の差異の節を加える。

- **段落の前後のアキの合わせ方**：InDesign は前の段落の段落後のアキと次の段落の段落前のアキを足すが、Golem は大きいほうを取る。同じスタイルの段落のあいだでは `space-between` だけを取る。
- **アキの単位**：InDesign は段落前後のアキを長さで書くが、Golem は行の格子の行の数で書く。
- **縦組みのノド側と小口側の揃え**：InDesign は縦組みのフレームでこの二つを適用しないが、Golem はエラー（G03118）とする。
- **最終行右インデント**：InDesign にはあるが、Golem にはない。

## 実装しないこと

- 最終行右インデント（InDesign の、最後の行だけの終わりの側の字下げ）。
- 段落の前後のアキを、行の数でない長さ（`mm` や `zw`）で書くこと。行の格子を崩すからである。
- 原稿に任意の縦の空きを置く記法（`\vspace` にあたるもの）。行アキ（`@blank-line`）がある。
- 段やページの先頭から、段落を決まった位置に置くこと（扉の題をページの中ほどに置くなど）。段の先頭の空きは、前後のアキも行アキも捨てるので、この ADR の範囲では書けない。
- 見出しの揃え、見出しの前後のアキ。見出しは段落スタイルでなく `[headings.<階層>]` で組み、行取りを持つ。
- リストの項目、表のセル、図版のキャプション、注、傍注の揃え。
- 組み込みの `verse` に段落の前後のアキの既定を持たせること。韻文の後に空きがない不具合は、ロードマップの「韻文の後の空き」の項目で扱う。この ADR の後は、`[paragraph-styles.verse] space-after = 1` で表せる。
- 両端を揃えない行の、行の端の伸びの量を利用者が選べるようにすること（ragged2e の `\RaggedRight` にあたるもの）。
- `@style` の引数による段落ごとの上書き（v2 の「段落スタイルの拡張」のまま）。

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。

golem-project のテストでは、次のことを確かめる。

- 四つのキーを読み、`based-on` で引き継ぐこと。`body` の既定の値が表のとおりであること。
- `align` の九つのほかの値、負の `space-before` と `space-after`、負の `end-indent` が G03006 になること。`@style-def` でも同じであること。
- 縦組みの本で `towards-spine` と `away-from-spine` が G03118 になり、横組みの本では誤りにならないこと。`@style-def` でも同じであること。
- `code` に四つのキーのどれかを書くと G03006 になること。`caption` と `sidenote` に 0 でない `end-indent` を書くと G03006、0 なら G03100 になること。
- LSP の補完の候補に四つのキーと `align` の値が出ること。

golem-layout のテストでは、行分割と行の置き方を確かめる。

- 両端を揃えない段落で、グルーの伸びが使われず（行の比が 0 以上で、伸びたグルーがない）、字幅を伸縮しないこと。縮みは使われうること。
- `left`、`center`、`right` の各行の箱の位置が、行の領域と内容の幅の差から求めた位置と一致すること。奇数の sp の差で、余りが行の終わりの側に来ること。
- 均等配置の三つの値で、最後のほかの行が今と同じ位置に組まれ、最後の行だけがずれること。`fully-justified` で最後の行が行の領域いっぱいになり、伸びるグルーのない最後の行は行の始まりに寄ること。
- 縦組みで、`left` が天、`right` が地に寄ること。
- `left-justified` の段落の行が、今の実装と同じ行の分け方と位置になること。

golem-driver のテストでは、次のことを確かめる。

- 「段落の前後のアキ」の規則の 1 から 3 の各場合の空きの行の数。同じスタイルが続く場合、違うスタイルで大きいほうを取る場合、段落でないブロックとの境、行アキを挟む場合。
- 段の先頭で前のアキを捨て、diagnostic を出さないこと。段落の後のアキが段の終わりに来ると、次の段の先頭で捨てること。
- `line-breaks = "keep"` の段落で、前のアキが最初の行の前に、後のアキが最後の行の後にだけ入ること。
- 罫線を持つ段落で、前後のアキの行が罫線の領域とは別に数えられること。
- `end-indent` を持つ段落の各行の行長が、表の式のとおりであること。`center` の行が字下げを引いた領域の中央に来ること。
- G07025 が `end-indent` を含めて判定されること。
- 左綴じと右綴じの横組みの本で、`towards-spine` と `away-from-spine` の段落の行が、奇数と偶数のページでそれぞれ左と右のどちらに寄るか。二つのページにまたがる段落で、ページごとに寄せる側が変わり、行の分け方は `left` と同じであること。
- リストの項目、キャプション、脚注の本文に四つのキーが当たらないこと。

golem-html のテストでは、表の CSS が書かれること、左綴じと右綴じの本で `towards-spine` と `away-from-spine` の `text-align` が表のとおりであること、既定の値の本の CSS とページが今と同じバイト列であること、隣り合う兄弟のセレクターの規則と `div.blank-line + p` の規則が書かれることを確かめる。

決定性の検査が通ること、既存の fixture の PDF、HTML、EPUB、プレーンテキストのバイト列が変わらないことを確かめる。
見た目の回帰テスト（[ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md)）の参照は変わらない。
複雑な組版の fixture（ロードマップの「複雑な組版の fixture」）に、中央揃えの扉、地付きの署名、前後にアキを取り両側を字下げした引用を加える。

## トレードオフ

両端を揃えない行で伸びを `filStretch` にすると、行分割は行の長さのばらつきを気にしない。
LaTeX の `\raggedright` と同じく、長い行と短い行が交互に並ぶことがある。
有限の伸びにすれば行の長さはそろいやすいが、その量を決める欄が要る。
扉や署名のように行の少ない段落が主な使い道なので、欄を増やさないほうを選んだ（「メンテナーが決めること」の 3）。

前後のアキを大きいほうに合わせると、InDesign の足し合わせとは結果が違う。
後のアキが 1 行の段落の後に前のアキが 1 行の段落が来ると、InDesign では 2 行、Golem では 1 行になる。
InDesign の版下を移す利用者は、値を読み替える必要がある。
その代わり、HTML と EPUB では CSS の余白の相殺と同じ結果になる（「メンテナーが決めること」の 4）。

HTML と EPUB の空きは、今の `space-between` と同じく、行の数を `em` にした近似である。
行の高さは `em` ではないので、PDF の行の格子の空きとは一致しない。
ブラウザーの既定の `p` の余白（1em）があるので、`space-before = 1` の段落の前の空きは、HTML では既定と見分けがつかない。

既定の本の HTML の本文には `text-align` を書かないので、`left-justified` の本文は、HTML では今のとおり行の終わりを揃えずに表示される。
`body` に別の値を書き、ほかのスタイルで `left-justified` に戻したときだけ、HTML でも両端を揃える。

段落の前後のアキを罫線と同じ範囲の段落に限るので、リストの前後に空きを取りたい本は、今のとおり行アキを使う。

ノド側と小口側の揃えは、ページが決まるまで行の位置が決まらない。
行の分け方はページによらないので改ページには影響しないが、同じ段落の行が、ページをまたぐと反対の側に寄る。
HTML と EPUB では 1 ページの側に固定するので、偶数ページの見た目は PDF と違う。
縦組みで止めるので、横組みと縦組みを切り替える本は、段落スタイルの `align` も書き換える必要がある。

InDesign との差異を TeX との差異と同じ文書に書くので、文書の名前は二つの処理系を挙げる長いものになる。
差異の文書は一つで、移ってくる書き手は、どちらの処理系から来ても同じ文書を引く。

## 決めたことの記録

- **三つの項目を一つの ADR にすること**（ロードマップ、v0.1.0-rc4 の「LaTeX との差を埋める項目」）：行揃え、段落の前後のアキ、行の終わりの側の字下げは、同じ ADR で決めてよい。行揃えの値は InDesign の行揃えに合わせ、縦組みでは天付き、中央、地付きと読む。前後のアキの単位は `space-between` と同じく行の数とし、行の格子を崩さない。ノド側と小口側の揃えを作るかと、段の先頭で段落の前の空きを捨てるかは ADR で決める。
- **最終行右インデントを作らないこと**（[2026-10-17 の調査](../audits/2026-10-17-latex-gap-for-v1.md)、3 の提案）。
- **任意の縦の空きの記法を作らないこと**（[2026-10-17 の調査](../audits/2026-10-17-latex-gap-for-v1.md)、2 の提案）。
- **ノド側と小口側の揃え**（2026-11-07、メンテナー）：草稿の推奨（作らない）を退けた。横組みでは入れ、縦組みではエラーとする。組版の自由を縛ってはいけない。
- **InDesign との差異の文書**（2026-11-07、メンテナー）：TeX との差異と同じく、InDesign との差異も文書に書く。文書は TeX との差異と同じでよい。
- **ほかの決めること**（2026-11-07、メンテナー）：「メンテナーが決めること」の 1、3、4、5、6、7 を推奨のとおりとした。
- **ノド側と小口側の値と差異の文書**（2026-11-07、メンテナー）：問題ないとした。「メンテナーが決めること」の 8 から 11 を推奨のとおりとした。

## メンテナーが決めること

すべて決めた（「決めたことの記録」）。

1. **`align` の値の名前**：決めた。InDesign の行揃えの名前を kebab-case にした `left`、`center`、`right`、`left-justified`、`center-justified`、`right-justified`、`fully-justified` とし、縦組みでは `left` を天付き、`right` を地付きと読む。
2. **ノド側と小口側の揃え**：決めた。横組みの本で作り、縦組みの本ではエラーとする。
3. **両端を揃えない行の組み方**：決めた。段落の中のグルーの伸びを 0 にし、行の端に `filStretch` の伸びを足して行に分ける。
4. **前後のアキの合わせ方**：決めた。違うスタイルの段落のあいだでは大きいほうを取り、同じスタイルの段落のあいだでは `space-between` だけを取る。
5. **段の先頭で前のアキを捨てるか**：決めた。捨てる。
6. **キーを当てる段落の範囲**：決めた。`align` と `end-indent` を今の字下げと同じ範囲に、`space-before` と `space-after` を段落の罫線と同じ範囲に当てる。
7. **HTML と EPUB の既定の揃え**：決めた。既定の値の `body` には `text-align` を書かず、今の HTML を変えない。
8. **ノド側と小口側の値の名前**：決めた。InDesign の「ノド側に揃える」と「小口側に揃える」の英語版の名前（Align Towards Spine、Align Away From Spine）を、1 の決定と同じく kebab-case にした `towards-spine` と `away-from-spine` とする。InDesign のほかの値と名前の付け方がそろう。退けた案は、`[sidenotes]` の `side` と柱の位置が使う `inside` と `outside` である。Golem の中の語とはそろうが、`align` の値のなかで一つだけ付け方が変わる。英語版の名前は記憶による。InDesign のヘルプは 403 で読めず（参考文献）、確かめていない。
9. **HTML と EPUB の読み替え**：決めた。本の最初のページ（奇数のページ）のノドの側で読み替える。どの本でも一つに決まり、左綴じの横組みの本では `towards-spine` が左揃えになる。退けた案の一つは、二つの値をどちらも `text-align: start` にする案で、書き手が区別した二つの値が同じになる。もう一つは、HTML と EPUB では揃えを書かない案で、書き手の指定が黙って消える。
10. **縦組みのエラーのコード**：決めた。新しい G03118 とする。値の書き間違い（G03006）と違い、書字方向との組み合わせが原因であり、直し方が違う。退けた案は G03006 にまとめる案である。一つのコードに一つの原因の原則に反する。
11. **差異の文書の名前**：決めた。docs/differences-from-tex-and-indesign.md とする。[docs/adr/0179](0179-lines-ending-in-explicit-hyphens.md) と同じ名前にする。退けた案は、TeX と InDesign で文書を分ける案である。メンテナーは同じ文書でよいとした。

## 参考文献

- [2026-10-17 の LaTeX との差の調査](../audits/2026-10-17-latex-gap-for-v1.md) の 1 から 3（InDesign の行揃え、段落前後のアキ、インデントの出典 URL を含む）。
- Adobe, InDesign User Guide, "Align text". https://helpx.adobe.com/indesign/using/aligning-text.html（2026-11-06 に取りに行ったが 403 で読めなかった。内容は上の調査の要約による）
- Adobe, InDesign User Guide, "Formatting paragraphs". https://helpx.adobe.com/in/indesign/using/formatting-paragraphs.html
- LaTeX2e unofficial reference manual, "\raggedright"、"center"、"flushright"、"quotation and quote"、"\addvspace". https://latexref.xyz/
- ragged2e package. https://ctan.org/pkg/ragged2e
- W3C, CSS Text Module Level 3, `text-align`、`text-align-last`. https://www.w3.org/TR/css-text-3/
- [docs/adr/0005](0005-character-and-paragraph-styles.md)、[docs/adr/0006](0006-paragraph-indent.md)、[docs/adr/0046](0046-blank-line-command.md)、[golem-driver ADR 0027](../golem-driver/adr/0027-paragraph-style-rules.md)、[golem-driver ADR 0043](../golem-driver/adr/0043-caption-sidenote-do-not-inherit-indent.md)、[golem-layout ADR 0001](../golem-layout/adr/0001-knuth-plass-line-breaking.md)
