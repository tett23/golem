# ADR 0271: 段落の背景と囲み罫

ステータス: 採択（未実装）

## 文脈

[ロードマップ](../roadmap.md) の v1.0.0 の「LaTeX との差を埋める項目」に「段落の背景と囲み罫」がある。
今は段落スタイル `code` にだけ書ける背景と枠を、ほかの段落スタイルにも書けるようにし、コラムや注意書きの囲みに使う項目である（[2026-10-17 の調査](../audits/2026-10-17-latex-gap-for-v1.md) の 16）。
続く段落を一つの囲みにまとめることと、ページをまたぐ分割は ADR で決めるとされた。
調査の「所有者の決定」は、この項目を v1.x に回さず v1.0.0 に置くとした。

### 今のコードブロックの背景と枠

`ParaStyleDef` は、`psBackground`、`psPadding`、`psBorder`、`psBorderWidth` を段落スタイルの全体に持つ（[`Style.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-project/src/Golem/Project/Style.hs#L269-L306)）。
実装は `code` に絞られ、ほかの段落スタイルに書くと G03006 になる（[`Style.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-project/src/Golem/Project/Style.hs#L2251-L2280)、[golem-driver ADR 0017](../golem-driver/adr/0017-pdf-code-blocks.md)、[golem-driver ADR 0023](../golem-driver/adr/0023-code-block-book-features.md)）。

コードブロックの組み方は次のとおりである（[仕様書の「style.toml」](../specifications.md#styletoml) の段落スタイル `code` の節）。

- コードの行は本文と別の行送りを持ち、コードの行の全体と上下の `padding` を収める最も少ない数の格子の行を占め、その中央に置かれる（`codeSpan`、`codeRowsTop`、[`Code.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-layout/src/Golem/Layout/Code.hs#L139-L159)）。後の本文は格子からずれない。
- 背景は、占めた格子の行の領域を塗る。上の辺は最初の格子の行の上の空きの中央、下の辺は最後の格子の行の下の空きの中央であり、行の方向は行の始まり（リストの中では項目の本文の始まり）から行長の終わりまでである（`codeRect`、[`Draw.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L1351-L1360)）。
- 文字は `padding` だけ内側から置く。
- `border` があれば、背景と同じ矩形の四辺を、線の中心を矩形の辺に置いた四つの塗りの矩形で描く（`borderRects`、[`Draw.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L1346-L1349)）。
- 改ページでは、コードの行のあいだで分け、分けた部分ごとに格子の行を占め、背景を塗り、閉じた矩形の枠を描く（`placeCode`、[`Paginate.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-layout/src/Golem/Layout/Paginate.hs#L444-L466)、[`Draw.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L1099-L1113)）。
- HTML と EPUB では `pre` に `background-color`、`padding`、`border` を書く。

### 罫線の仕組み

段落スタイルの `rule-before` と `rule-after` は、罫線の指定（重さ、色、線の種類）を持つ（[golem-driver ADR 0024](../golem-driver/adr/0024-rule-spec-and-footnote-separator.md)、[golem-driver ADR 0027](../golem-driver/adr/0027-paragraph-style-rules.md)、[golem-driver ADR 0028](../golem-driver/adr/0028-rule-colour-and-style.md)）。
線の種類は、長さと重さを持つ帯の中の塗りの図形（矩形、円、閉じた曲線）として描く（`ruleShapes`、[`RuleShape.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-typeset/src/Golem/Typeset/RuleShape.hs#L40-L56)）。
罫線を持つ段落は、罫線の領域を格子の行の単位で取り、段で分けないまとまりとして置かれる（`FRuled`、[`Types.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-layout/src/Golem/Layout/Paginate/Types.hs#L100-L115)）。
罫線は、リストの項目、表のセル、注の本文、定義リストの中の段落には引かない。

### InDesign と LaTeX

InDesign は、段落の囲み罫と段落の背景色を段落スタイルに書ける。
囲み罫は上下左右の罫（太さ、種類、色）と角の形を持ち、背景色は色と濃度を持つ。
幅を段の幅にするか文字の幅にするかを選び、同じ設定の段落が続けば一つの囲みにまとめられる。
出典は調査の 16 に挙げたヘルプの頁で、調査は本文を読めず、検索の抜粋で確かめた。
次の点は確かめていない。

- 辺ごとに太さを変えられるか。
- 「文字の幅」が、段落の字下げを引いた幅か、行の文字の幅か。
- 段やフレームで分かれた囲みの、分かれ目の辺を描くかどうかと、その既定。
- 続く段落をまとめる設定の既定。

LaTeX は、tcolorbox と mdframed で、ページをまたげる枠と背景の箱を作る。
どちらも、分かれた箱の分かれ目の辺を描くかを選べる。
JLReq の該当する記述は、この ADR を書くときに確かめていない。

### 依存

この ADR は [ADR 0261](0261-keep-options-of-paragraph-styles.md) の後に実装する。
囲みの中の段落を段で分けるときに、[ADR 0261](0261-keep-options-of-paragraph-styles.md) の `keep-first-lines`、`keep-last-lines`、`keep-all-lines` を使うからである。
欄の名前は [ADR 0261](0261-keep-options-of-paragraph-styles.md) と同じく、kebab-case の平らなキーにする。

## 実装すること

### style.toml の欄

段落スタイルの囲みは、次のキーで決める。
`background`、`padding`、`border`、`border-width` は今あるキーであり、`code` のほかの段落スタイルにも開く。
`border-style`、`border-sides`、`border-radius` を新しく加える。

| キー | 型 | 既定 | 意味 |
| --- | --- | --- | --- |
| `background` | スウォッチの名前か `false` | なし | 囲みの背景の色。`false` は引き継いだ背景を塗らない |
| `padding` | 寸法 | `"0.5zw"` | 囲みの内側の余白。`zw` は段落スタイルの文字の大きさを一字とする |
| `border` | スウォッチの名前か `false` | なし | 枠の色。`false` は引き継いだ枠を描かない |
| `border-width` | `mm`、`pt`、`Q`、`H`、`in` の寸法 | `"0.25pt"` | 枠の線の太さ |
| `border-style` | `"solid"`、`"dashed"`、`"dotted"` | `"solid"` | 枠の線の種類（[golem-driver ADR 0028](../golem-driver/adr/0028-rule-colour-and-style.md) の値） |
| `border-sides` | `"before"`、`"after"`、`"start"`、`"end"` の配列 | 四つすべて | 枠を描く辺。前（横組みの上、縦組みの右）、後、行の始まりの側、行の終わりの側 |
| `border-radius` | 寸法 | `"0pt"` | 囲みの角の丸みの半径。0 は直角 |

- `background` か `border` を持つ段落スタイルを、**囲みを持つ**段落スタイルと呼ぶ。`padding`、`border-width`、`border-style`、`border-sides` は、囲みを持たない段落スタイルでは効果がない。
- `border-style` の線の長さ（破線の長さと間、点の間）は、罫線の指定で `dash` と `gap` を書かない場合と同じく、太さから求める。
- `border-style` に表のほかの値（[golem-driver ADR 0028](../golem-driver/adr/0028-rule-colour-and-style.md) の多重線、`"japanese-dots"`、`"wavy"` を含む）を書くと G03006 とする。型（`RuleStyle`）は罫線と同じものを使い、実装を三つに絞る。
- `border-sides` の空の配列、重複、表にない値は G03006 とする。
- `border-radius` は、`padding` と同じく `mm`、`pt`、`Q`、`H`、`in`、`zw` の寸法で書き、`zw` は段落スタイルの文字の大きさを一字とする。負の値と寸法でない値は G03006 とする。四つの角は一つの半径を持つ（下の「角の丸み」）。
- 値の誤りは今のとおり G03006、スウォッチがない場合は G03013 とする。`border-width` の `zw` は G03006 のままとする。
- 組み込みの `caption` と `sidenote` には、今のとおり六つのキーを書けない（G03006）。
  先に実装する [ADR 0262](0262-table-numbers-captions-column-widths-and-cell-styles.md) の `table` は、`caption` と同じく四つの今のキー（`background`、`padding`、`border`、`border-width`）を書けない。
  [ADR 0264](0264-paragraph-styles-for-toc-entries.md) の `toc-1` から `toc-6` は、今の規則（四つのキーは `code` にだけ書ける）のもとで同じく書けない。
  この ADR はこの二つも `caption` と同じに扱い、六つのキーを書けないものとする。
  セルと目次の項目は文書の最上位の段落ではなく、下の「囲む段落」のとおり囲みを付けない段落だからである。
- 囲みを持つ段落スタイルに `rule-before` か `rule-after` を書くと（`based-on` で引き継いだ場合を含む）、G03006 とする。メッセージは `段落スタイル <名前> には囲みと罫線を一緒に書けません` とする（「メンテナーが決めること」の 5）。
- `code` は、`border-style`、`border-sides`、`border-radius` も書けるようにする（`codeParaKeys`）。どれも書かなければ、`code` の出力は変わらない。
- `@style-def` にも同じキーを同じ検査で書ける。
- `ParaStyleDef` の `psBackground` と `psBorder` を `Maybe (Maybe Text)`（`Nothing` は書いていない、`Just Nothing` は `false`）にし、`psBorderStyle :: Maybe RuleStyle`、`psBorderSides :: Maybe [BoxSide]`、`psBorderRadius :: Maybe Dimension`（寸法の型は `padding` と同じもの）を加える。`BoxSide` は `SideBefore`、`SideAfter`、`SideStart`、`SideEnd` とする。LSP の補完が読む `paraStyleNode` にも加える。

### 囲む段落

囲みは、文書の最上位の段落にだけ付ける。
リストの項目、表のセル、注の本文、定義リストの中の段落には付けない。
罫線と同じ範囲である。
回り込む図版の脇には、囲みを持つ段落を組まない。
罫線を持つ段落と同じく、図版の後から置き、図版の脇の残りの行は空ける。

`line-breaks = "keep"` の段落（連）も囲める。

### 続く段落を一つの囲みにまとめる

文書の最上位で続く二つの段落は、次のすべてが成り立つとき、一つの囲みにまとめる（「メンテナーが決めること」の 2）。

- どちらも囲みを持つ。
- 解決した `background`、`padding`、`border`、`border-width`、`border-style`、`border-sides`、`border-radius` が等しい。`padding` と `border-radius` は sp に直した値で比べる。
- 囲みの行の方向の範囲（下の「行の方向」）が sp で等しい。
- あいだに、段落の前後のアキ（`space-before`、`space-after`、`space-between`）と行アキのほかのブロックがない。
- 後の段落の `page-break`（[ADR 0261](0261-keep-options-of-paragraph-styles.md)）が `"any"` である。

段落スタイルの名前が違っても、設定が等しければまとめる。
まとめた囲みの中では、段落のあいだの空き（`space-between`、前の段落の `space-after`、後の段落の `space-before`）を、今の規則のまま囲みの中に置く。
最初の段落の `space-before` と最後の段落の `space-after` は、囲みの外に置く。

### 行の方向

囲みの行の方向の範囲は、段の行の始まりから段落スタイルの `indent` だけ進んだ位置から、行長の終わりから `end-indent` だけ戻った位置までとする（「メンテナーが決めること」の 4）。
`indent` と `end-indent` が 0 なら、段の行長の全体である。

段落の行は、囲みの範囲の両端から `padding` だけ内側を行の領域として組む。
`first-line-indent` は、今のとおりその領域の始まりに加える。
G07025（行長の不足）は、`indent`、`first-line-indent`、`end-indent` に加えて、囲みを持つ段落スタイルでは左右の `padding` も引いた幅で検査する。

### 行と直交する方向と行の格子

段落の行は、今のとおり行の格子に載せる。
囲みは格子の行の単位で領域を取り、本文の行を格子からずらさない。

行送りを p、格子の字面の高さを h（`[page.grid]` の `font-size`）、`padding` を d とする。
囲みは、最初の行の前に k 行、最後の行の後に k 行の格子の行を足して占める。
k は、`(p − h)/2 + k × p ≥ d` を満たす最も小さい 0 以上の整数である。
整数の割り算で、`k = max 0 (ceiling ((d − (p − h)/2) / p))` として一度だけ求める。
囲みの前の辺は、占めた最初の格子の行の上の空きの中央に、後の辺は、占めた最後の格子の行の下の空きの中央に置く。
コードブロックの `codeRect` と同じ位置である。
行と直交する方向の内側の余白は、d 以上 d + p 未満になる。

`border-width` は、コードブロックと同じく領域の計算に数えず、線の中心を辺に置く。

### 段落の前後のアキとの関係

前のアキ（`space-before`、[docs/adr/0189](0189-paragraph-alignment-spacing-and-end-indent.md)）は囲みの外、囲みの前の k 行の前に置く。
後のアキも、囲みの後の k 行の後に置く。
段の先頭では、今のとおり前のアキの空きを取らないが、囲みの前の k 行は取る。
k 行は囲みの一部であり、空きではないからである。

### 段と段をまたぐ囲み

囲みは、中の段落の行のあいだで、段とページをまたいで分ける（「メンテナーが決めること」の 3）。

- 分け方は、中の段落の規則（[ADR 0261](0261-keep-options-of-paragraph-styles.md) の `keep-first-lines`、`keep-last-lines`、`keep-all-lines`）に従う。
- 分けた部分（**囲みの部分**）のそれぞれが、前の k 行と後の k 行を取り、背景を塗り、`border-sides` のすべての辺を描く。コードブロックの部分と同じく、閉じた囲みになる。
- 囲みの部分は、少なくとも一行を持つ。段の残りに、前の k 行、中の段落の規則で置ける最初の部分、後の k 行が入らなければ、次の段から置く。
- 空の段にも、前の k 行、一行、後の k 行が入らなければ、エラー（G07121）とする。コードブロックの G07043 と同じく、版面と `padding` だけで決まるので、golem-typeset が組む前に検査する。
- 囲みの中の行の注の本文は、今のとおり段の下に置き、囲みの外にある。

### 改ページの型（golem-layout）

`Flow` に囲みを加える（[`Types.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-layout/src/Golem/Layout/Paginate/Types.hs#L52-L130)）。

```haskell
  | {- | paragraphs in one box (docs/adr/0271): each part of the box in a
    column takes 'fbBefore' grid lines before its first line and
    'fbAfter' after its last; the body holds paragraphs, stanzas and the
    spaces between them, broken as they are outside a box
    -}
    FBoxed {fbId :: !Int, fbBefore :: !Int, fbAfter :: !Int, fbBody :: ![Flow]}
```

`PageOut` に `poBoxes :: ![BoxSegment]` を加える。
`BoxSegment` は、囲みの `fbId` と、その段の部分が占める最初と最後の格子の行（前と後の k 行を含む）を持つ。
`TableSegment` と同じ形である。

- `place` は、中の流れを、段の最後の `fbAfter` 行を除いた残りに置く。段を進むたびに、新しい部分の前に `fbBefore` 行を取る。
- `nextNeed` は、`fbBefore` と、中の最初の流れの最初の部分を数え、最初の部分が中のすべてなら `fbAfter` も数える。
- [ADR 0261](0261-keep-options-of-paragraph-styles.md) の `FStart` は囲みの前に、`FKeepNext`（最後の段落のもの）は囲みの後に置く。中の段落のあいだの `FKeepNext` は囲みの中に置く。
- 段の先頭で空きを取らない規則（`FSpace` と `FBlank`）は、`fbBefore` には当てない。

golem-typeset の `numberText` が囲みを持つ段落を `FBoxed` にまとめ、`fbBefore` と `fbAfter` を上の k から求める（[`Flow.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L2366-L2380)）。
意味論 IR、CDDL、プラグインの ABI は変えない。
golem のパッケージのあいだの `build-depends` も変えない。

### PDF の描画（golem-typeset）

- 背景は、囲みの部分ごとに、行の方向の範囲と占めた格子の行の領域の矩形を、スウォッチの CMYK で DeviceCMYK の矩形として塗り、その上に文字を描く。コードブロックの背景と同じく、ほかのものより先に描く。
- 枠は、`border-sides` の辺ごとに、辺に沿った帯（太さは `border-width`、中心は辺）を `ruleShapes` で描く。前と後の辺の帯は、行の方向に矩形の幅に太さを足した長さ（両端に太さの半分ずつ）を持ち、始まりと終わりの辺の帯は、直交する方向に矩形の高さに太さを足した長さを持つ。
- `"solid"` で四辺のときの帯は、`borderRects` の四つの矩形と同じ値と順になる。コードブロックの枠も同じ関数で描くように改めるが、PDF のバイト列は変わらない。
- 背景と枠はタグ付き PDF のアーティファクト（`Layout`）にする。コードブロックの背景と枠と同じである（[仕様書の「タグ付き PDF」](../specifications.md#タグ付き-pdf)）。
- 背景と枠のスウォッチは、golem preflight の使ったスウォッチに入り、総インキ量の検査（G09015）の対象になる。

縦組みでは、前の辺が右、後の辺が左、始まりの辺が上、終わりの辺が下になる。
`codeRect` と同じく、縦組みの座標に写す。

### 角の丸み

角丸の囲みは、コラムや注意書きでほぼかならず早く要るので、最初から入れる（2026-11-09 の tett23 の決定、「メンテナーが決めること」の 1）。

`border-radius` を sp に直した値を r とする。
囲みの部分の矩形の行の方向の長さを w、直交する方向の長さを h とする。
角の半径は、どの角も r′ = min(r, w/2, h/2) とする。
r が短い辺の半分より大きいときは、短い辺の半分の半円になる（CSS の `border-radius` が一つの値のときと同じ縮め方である）。
縮めるのは、書いた値の意味として決めた形であり、誤りとして扱わない。
囲みの高さは中身の行の数で変わり、書き手が前もって辺の長さを知れないからである。

丸める角は、次の二つが両方成り立つ角である。

- **分かれ目の角でない**：段とページで分けた囲みの部分では、分かれ目の辺（最初の部分の後の辺、最後の部分の前の辺、途中の部分の前と後の辺）の両端の角を直角にする。囲みの本当の始まりと終わりの角だけを丸める。分けない囲みは四つの角を丸める（「メンテナーが決めること」の 3 の分け方は変えない。分けた部分は閉じた囲みのままである）。
- **枠の辺がそろう角である**：`border` を持つ囲みでは、角をはさむ二つの辺がどちらも `border-sides` にある角だけを丸める。片方の辺だけを描く角は直角にする。`border` を持たない囲み（背景だけ）は、辺の選び方によらず、分かれ目でない角を丸める。

背景と枠は、同じ閉じたパスで描く。
パスは、矩形の辺を直線で、丸める角を半径 r′ の四分円で結んだものである。
四分円は、一つの三次ベジエ曲線で近似し、制御点を角の両端から接線の方向に κ × r′（κ = 4(√2 − 1)/3）だけ離して置く。
座標は有理数で求め、PDF の内容のストリームに書く精度に丸める。
丸め方は今の矩形の座標と同じであり、同じ入力から同じバイト列を得る。

- 背景は、そのパスを塗る（`f`）。
- 枠は、r′ が 0 より大きい角を一つでも持つ囲みの部分では、描く辺と、その両端の丸めた角の四分円をつないだパスを線として描く（`S`）。線の太さは `border-width`、線の中心はパスの上である。`"dashed"` と `"dotted"` は、`ruleShapes` が求めるのと同じ長さと間を、`d` 演算子のダッシュの配列で与える。`"dotted"` は丸い線端（`1 J`）と長さ 0 のダッシュで点を描く。描く辺が続かない場合（`border-sides` が前と後だけのときなど）は、続く辺ごとに一つのパスにする。
- r′ がすべての角で 0 の囲みの部分（`border-radius` が 0 の囲みを含む）は、今の帯の描き方（上の「PDF の描画」）のままである。`border-radius` を書かない本の PDF は、角丸を入れる前と同じバイト列になる。

縦組みでは、角の位置を `codeRect` と同じく縦組みの座標に写し、丸める角の判定は前、後、始まり、終わりの辺で行う。

HTML と EPUB では、`div.box-<名前>` の規則に、丸める角ごとに `border-start-start-radius`、`border-start-end-radius`、`border-end-start-radius`、`border-end-end-radius` を書く。
HTML には段とページの分かれ目がないので、分かれ目の角の規則は当てない。
r′ の縮め方は、閲覧環境の CSS の規則に任せる。
`border-radius` が 0 の囲みには何も書かない。

### diagnostics

| コード | 重大度 | 条件 | メッセージ |
| --- | --- | --- | --- |
| G07121 | エラー | 空の段に、囲みの前の k 行、一行、後の k 行が入らない | `段落スタイル <名前> の囲みの一行と上下の padding が段に収まりません` |

位置は、その段落スタイルの最初の段落である。
同じ段落スタイルには一度だけ出す。
コードの番号は、採択のときに、使われていない番号であり同じ時期の ADR と重ならないことを確かめて振り直した（「決めたことの記録」）。

ほかの誤り（`border-radius` の値の誤りを含む）は、既存の G03006、G03013、G07025 で報告する。
どれも既存のコードの原因（style.toml の値、スウォッチの参照、行長の不足）と同じだからである。

### HTML と EPUB

- 一つの囲みにまとめた段落を `<div class="box box-<最初の段落の段落スタイルの名前>">` で包む。囲みは HTML の構造に現れ、PDF と同じ段落がまとまる。
- `style.css` に、囲みを持つ段落スタイルごとに `div.box-<名前>` の規則を書く。背景はスウォッチの RGB の近似の `background-color`、余白は `padding`（`zw` は `em`）、枠は辺ごとに `border-block-start`、`border-block-end`、`border-inline-start`、`border-inline-end`（太さ、`solid`、`dashed`、`dotted`、色）、行の方向の範囲は `margin-inline-start` と `margin-inline-end`（`indent` と `end-indent`）である。
- 囲みの中の段落は、`indent` と `end-indent` を囲みが受け持つので、段落の `padding-inline-start` と `padding-inline-end` を 0 にする。`first-line-indent`（`text-indent`）は残す。
- 最初の段落の前のアキと最後の段落の後のアキは、囲みの `margin-block-start` と `margin-block-end` に書き、囲みの中の最初と最後の段落の外側の `margin-block` は 0 にする。前後のアキの兄弟の要素のセレクター（[docs/adr/0189](0189-paragraph-alignment-spacing-and-end-indent.md)、[docs/adr/0217](0217-html-spaces-of-paragraph-styles-redefined-in-files.md)）は、`div.box` を前後の要素として数えるように広げる。
- `pre` の規則は変えない。

EPUB は HTML と同じ XHTML と `style.css` を使う。
EPUB の読書環境が `border-block-start` などの論理的な指定を読むかは確かめていない。
プレーンテキスト（golem-text）には、罫線と同じく囲みを出力しない。

### 文書

- [docs/specifications.md](../specifications.md) の「style.toml」の段落スタイルの節に、囲みの欄と規則を書く。段落スタイル `code` の節の「`background` と `padding` は、v1 では `code` にだけ書ける」と、`border` の同じ文を消し、`code` の組み方のうち囲みと同じ部分は、囲みの節を指す文にする。「改ページ」の節に囲みの分け方を書き、不変条件の段落に B1 から B6 と B8、B9 を足す。「HTML」の節に囲みの CSS を書く。
- [docs/diagnostics.md](../diagnostics.md) に G07121 を足し、G03006 の主な原因の「`background` か `padding` を、`code` のほかの段落スタイルに書いた」と、`border` の同じ項目を、新しい条件（`border-style`、`border-sides`、罫線との組み合わせ）に書き換える。
- マニュアルの style.toml の章（`manual/chapters/05-style.gm`）、style.toml の付録（`manual/appendices/c-style.gm`）、InDesign との対応の付録（`manual/appendices/f-indesign.gm`）に囲みを足す。
- docs/markup.md は変えない（記法を変えないため）。
- [ロードマップ](../roadmap.md) の「LaTeX との差を埋める項目」の「段落の背景と囲み罫」の項目を消す。ほかの項目から取り出した部分はない。

## 実装しないこと

- **角丸のほかの角の形**：InDesign の角の形のうち、角丸のほかのもの（面取り、内丸、装飾など）と、角ごとに違う半径、楕円の角は作らない。角丸は「角の丸み」のとおり作る。
- **辺ごとの太さ、色、線の種類**：四辺は一つの太さ、色、種類を持つ。辺を選ぶだけである（「メンテナーが決めること」の 1）。
- **辺ごとの余白**：`padding` は一つの値で、上下と左右に同じ量を取る。コードブロックと同じである。
- **背景の濃度**：InDesign の濃度は、スウォッチの CMYK で表す。囲みに濃度の欄は設けない。
- **多重線、和文の点線、波線の枠**：型は持つが、`border-style` には書けない。角での線のつなぎ方を決める必要があるからである。
- **破線の長さの指定**：`border-style` の破線と点線の長さは太さから求め、`dash` と `gap` にあたるキーは設けない。
- **見出し、リストの項目、表、定義リストの囲み**：段落スタイルを持たないか、罫線と同じく囲みを付けない範囲である。
- **囲みと罫線の併用**：G03006 とする（「メンテナーが決めること」の 5）。
- **分かれ目の辺を描かない設定**：囲みの部分は、つねに閉じる（「メンテナーが決めること」の 3）。
- **コードブロックの組み方を変えること**：コードの行の行送り、領域の取り方、`continued` は変えない。コードブロックは段落の囲みとまとめない。

## 不変条件

段の行の数を C、行送りを p、格子の字面の高さを h、囲み B の前と後の格子の行の数を k とする。
囲みの部分は、出力の `poBoxes` の一つの `BoxSegment` である。

- **B1 部分の形**：囲みの部分の最初の格子の行は、その段に置かれた B の最初の行の格子の行より k 小さく、最後の格子の行は、その段に置かれた B の最後の行の格子の行より k 大きい。
- **B2 段からあふれない**：どの段でも、置いた格子の行（囲みの前と後の k 行を含む）と注の本文の行と区切りの行の和が C を超えない。[docs/adr/0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の I2 の和に、囲みの k 行を加えたものである。
- **B3 空の部分がない**：どの囲みの部分も、B の行を少なくとも一つ持つ。B のすべての行は、ちょうど一つの囲みの部分に入る。
- **B4 まとめ方**：文書の最上位で続く二つの段落が同じ囲みに入ることと、「続く段落を一つの囲みにまとめる」の条件のすべてが成り立つことは、同値である。
- **B5 格子からずれない**：囲みの中の行の位置は、同じ段落を囲みなしで同じ格子の行に置いた位置と、行と直交する方向で等しい。描いた囲みの前の辺の位置は、最初の格子の行の上の空きの中央である。
- **B6 余白は求めた以上**：囲みの矩形の辺から最も近い行の字面までの、行と直交する方向の距離は、d 以上 d + p 未満である。行の方向の距離は d に等しい。
- **B7 コードは変わらない**：`border-style`、`border-sides`、`border-radius` を書かない本のコードブロックの PDF のバイト列は、この ADR の前の実装と等しい。
- **B8 角の半径**：囲みのどの部分のどの角でも、描いた角の半径は、丸める角なら min(r, w/2, h/2) に等しく、そうでなければ 0 である。丸める角は、分かれ目の辺の端になく、`border` を持つ囲みでは角をはさむ二つの辺がどちらも `border-sides` にある角に限る。
- **B9 角丸は矩形の中にある**：背景のパスと枠の線の中心のパスは、囲みの部分の矩形の内側（辺の上を含む）にあり、r′ が 0 の角では矩形の角を通る。r = 0 の囲みのパスは、矩形そのものである。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| d | 0、(p − h)/2、(p − h)/2 + 1sp、(p − h)/2 + p、(p − h)/2 + p + 1sp |
| k と段 | 2k + 1 = C − 1、C、C + 1（G07121） |
| 囲みの段落の行の数 | 1、2、C − 2k、C − 2k + 1 |
| 続く囲み | 一つ、設定の等しい二つ、`padding` だけ違う二つ、あいだに前後のアキのある二つ、後が `page-break = "page"` の二つ |
| 囲みの位置 | 段の先頭、段の途中、段の最後の一行 |
| `border-sides` | 四つ、一つ（`"start"`）、前と後、三つ（`"end"` のほか） |
| r | 0、1sp、min(w, h)/2 − 1sp、min(w, h)/2、min(w, h)/2 + 1sp、max(w, h)/2 より大きい値 |
| 分けた囲みの部分 | 分けない囲み、最初の部分、途中の部分、最後の部分 |
| 角丸と枠 | 背景だけ、枠だけ、背景と枠 |
| 書字方向 | 横組み、縦組み |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。

### 改ページ（golem-layout のテスト）

- [docs/adr/0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の `PaginateEnum` に、要素 `EBoxed !Int !Int`（k と、中の段落の行の数）と `EBoxedPair !Int`（中に段落を二つ持つ囲み）を足す。k は 0 と 1、行の数は 1 から 4 とする。[ADR 0261](0261-keep-options-of-paragraph-styles.md) の `keepInputs` と同じく別の列挙 `boxInputs` にし、`EPara` の 1 から 4、`EHeading`、`EFigure` の C、`ESpace`、`EBreak`、`ENotedPara` の 2 と合わせる。段の行の数は 3 から 5、段の数は 1 と 2、プルリクエストでは要素 3 個まで、毎晩は 5 個までとする。
- `PaginateInvariants` に B1、B2、B3 の述語を足し、`boxInputs` のすべての入力で、I1 から I8 と B1 から B3 が違反を返さないことを確かめる。テストの名前に番号を入れる。
- 述語のテスト：B1 から B3 のそれぞれについて、規則を破った出力を手で作り、その述語だけが違反を返すこと。
- 例：段の先頭の囲みが、前のアキを取らずに前の k 行を取ること。段の最後の一行に入らない囲みが、次の段から始まること。段で分かれた囲みの各部分が k 行ずつを取ること。

### 組版と描画（golem-typeset のテスト）

- B4：段落の並びから `FBoxed` を作る関数に、境界の入力の表の「続く囲み」のすべてを渡し、まとめ方が条件と一致すること。
- B5、B6：k の式に、境界の入力の表の d のすべてを渡し、領域と辺の位置を有理数で求めた値と比べること。横組みと縦組みの両方で、矩形と行の位置を確かめる。
- 枠：`"solid"` で四辺の帯が `borderRects` と同じ矩形を同じ順で返すこと。`border-sides = ["start"]` で一つの帯だけを返すこと。
- B8、B9：角の半径を求める関数に、境界の入力の表の r、分けた囲みの部分、`border-sides`、角丸と枠のすべての組を渡し、角ごとの半径と、パスが矩形の内側にあることを有理数で確かめる。横組みと縦組みの両方で確かめる。r = 0 で今の帯の描き方の値と同じになること。
- G07121：2k + 1 = C で出さず、C + 1 で出すこと。

### プロジェクトと出力（golem-project、golem-driver のテスト）

- キーの読み込み、`based-on` の引き継ぎ、`false`、`border-style`、`border-sides`、`border-radius`（負の値、寸法でない値）の誤り、罫線との併用（G03006）、スウォッチの欠落（G03013）、`caption` と `sidenote` に書いた場合。
- G07025 が `padding` を引いた幅で検査すること。
- B7：コードブロックを含む今の fixture（golem-driver の golden）の PDF のバイト列が変わらないこと。
- HTML：囲みの `div` とその CSS（丸める角だけの `border-*-radius`）、囲みの中の段落の字下げとアキの規則、`pre` の規則が変わらないこと。`browser.yml` の検査に、囲みの背景と枠があり、囲みの外の段落と重ならないことを足す（緩い検査とする）。
- fixture：`specimens` の横組みと縦組みに、二つの段落の角丸のコラムの囲みと、行の始まりの辺だけの注意書きを足し、golden と見た目の回帰テストの参照を更新する。

## トレードオフ

囲みの上下の余白を格子の行の単位に切り上げるので、`padding` を少し増やしただけで囲みが一行ずつ高くなる。
本文の行を格子に載せ、見開きの行の位置をそろえることを優先した。
コードブロックは自らの行送りを持つので、余白を正確に取れる。
同じ `padding` でも、コードブロックと段落の囲みでは上下の余白が違って見えることがある。

囲みの部分ごとに前と後の k 行を取るので、分かれた囲みは、分かれない囲みより 2k 行多く占める。
段の末尾に囲みの部分が来るたびに、その分だけ本文が減る。
代わりに、どの部分も閉じた囲みになり、コードブロックと見た目がそろう。

分けた囲みの部分の分かれ目の角を直角にするので、角丸の囲みは、部分ごとに丸い角の数が変わる。
続きであることが角の形で読み取れる代わりに、どの部分も四つの角が丸いコードブロックのような見た目にはならない。

続く段落を設定でまとめるので、段落スタイルの名前が違っても一つの囲みになる。
コラムの題と本文を別のスタイルにしても一つに囲めるが、偶然に設定が等しい二つの段落スタイルもまとまる。
まとめたくなければ、`padding` などを少し変える必要がある。

## メンテナーが決めること

1. **枠の欄の形**：推奨は、今の `border` と `border-width` を残し、`border-style`、`border-sides`、`border-radius` を平らなキーとして足すことである。コードブロックの欄がそのまま使え、コラムの全周の枠と、注意書きの行の始まりの側の一本の線の両方を書ける。`border-radius` は、2026-11-09 の tett23 の決定で足した。
   - 角の丸みの退けた案の一つは、草案の推奨のとおり角を直角だけにし、角丸を要るとわかってから足すことである。角丸はほぼかならず早く要る。
   - もう一つは、分けた囲みの部分のすべての角を丸めることである（CSS の `box-decoration-break: clone` に近い）。どの部分も同じ形になるが、続きであることが角で読み取れない。
   - 退けた案の一つは、`border` を罫線の指定の表にすることである。`length`、`space-before`、`start-indent`、`keep-in-column` など、囲みの辺に意味のないキーが混ざり、今の `border = "<スウォッチ>"` の書き方を壊す。
   - もう一つは、辺ごとの表（`border-before = { ... }` など）である。InDesign の辺ごとの太さに近いが、四つの表の引き継ぎと、太さの違う辺の角のつなぎ方を決める必要がある。
2. **続く段落をまとめるか**：推奨は、設定が等しく、あいだに段落の前後のアキのほかのブロックがなければ、つねにまとめることである。複数の段落のコラムは、一つの囲みであることが多い。
   - 退けた案の一つは、InDesign と同じくまとめるかどうかの欄を設けることである。InDesign の既定を確かめておらず、欄が一つ増える。
   - もう一つは、段落スタイルの名前が同じときだけまとめることである。HTML のクラスは簡単になるが、コラムの題と本文のスタイルを分けた本で囲みが二つに割れる。
3. **段とページをまたぐ囲み**：推奨は、行のあいだで分け、各部分を閉じた囲みにすることである。コードブロックと同じ見た目で、規則が一つで済む。
   - 退けた案の一つは、分かれ目の辺を描かず、余白の k 行も取らないことである（tcolorbox の既定に近い）。続きであることは読み取りやすいが、コードブロックと見た目が違い、部分ごとに辺の有無が変わる。
   - もう一つは、囲みを分けず、段に入らなければ次の段に送ることである。長いコラムで段の下に大きな空きができる。分けたくなければ、[ADR 0261](0261-keep-options-of-paragraph-styles.md) の `keep-all-lines` で書ける。
4. **囲みの行の方向の範囲**：推奨は、段落の `indent` と `end-indent` で決めることである。新しい欄がいらず、字下げした注意書きの囲みも書ける。
   - 退けた案の一つは、InDesign の「段の幅」と「文字の幅」を選ぶ欄を設けることである。「文字の幅」の意味を確かめていない。
   - もう一つは、つねに段の行長の全体にすることである。字下げした段落の囲みを書けない。
5. **囲みと罫線の併用**：推奨は、G03006 で禁じることである。罫線の領域と囲みの k 行の順と、続く段落の罫線の領域の共有（`frJoined`）と囲みのまとめ方の関係を決めずに済む。
   - 退けた案は、罫線を囲みの外に引くことである。InDesign では併用できると思われるが確かめておらず、使い道も見えていない。
6. **上下の余白の取り方**：推奨は、格子の行の単位に切り上げることである。囲みの後の本文が格子からずれない。
   - 退けた案は、`padding` を正確に取り、囲みの後の本文を格子から外すことである。見開きの行の位置がそろわなくなり、格子に載せる今の組版の前提を崩す。

## 決めたことの記録

2026-11-09 に、tett23 が次のとおり決めた。

1. 枠の欄の形は、推奨の平らなキーとし、角丸を最初から入れる。tett23 は、角丸はほぼかならず早期に必要になると述べた。`border-radius` のキー、「角の丸み」の節、B8 と B9、境界の入力、テストを足し、「実装しないこと」の角の形の項目を改めた。採択のときに次を決めた。
   - 四つの角は一つの半径を持ち、辺の半分より大きい半径は短い辺の半分に縮める（CSS と同じ）。縮めることは誤りとしない。
   - 段とページで分けた囲みの部分は、分かれ目の辺の両端の角を直角にし、囲みの本当の始まりと終わりの角だけを丸める。
   - 枠を持つ囲みでは、二つの辺がどちらも描かれる角だけを丸める。
   - 丸めた角を持つ部分の枠は、パスの線として描き、破線と点線はダッシュの配列で描く。直角だけの部分は今の帯の描き方のままとし、`border-radius` を書かない本の PDF を変えない。
2. 続く段落は、推奨のとおり設定が等しければつねにまとめる。比べる設定に `border-radius` を加えた。
3. 段とページをまたぐ囲みは、推奨のとおり行のあいだで分け、各部分を閉じた囲みにする。
4. 囲みの行の方向の範囲は、推奨のとおり段落の `indent` と `end-indent` で決める。
5. 囲みと罫線の併用は、推奨のとおり G03006 で禁じる。
6. 上下の余白は、推奨のとおり格子の行の単位に切り上げる。
7. diagnostic のコードは、採択のときに、docs/diagnostics.md と origin/main のコードで使われていない番号であり、同じ時期の ADR と重ならないことを確かめて、G07121 とした。
草案の仮の番号から振り直した。

## 参考文献

- [2026-10-17 の調査](../audits/2026-10-17-latex-gap-for-v1.md) の 16 と「所有者の決定」
- [golem-driver ADR 0017](../golem-driver/adr/0017-pdf-code-blocks.md)、[golem-driver ADR 0023](../golem-driver/adr/0023-code-block-book-features.md)、[golem-driver ADR 0024](../golem-driver/adr/0024-rule-spec-and-footnote-separator.md)、[golem-driver ADR 0027](../golem-driver/adr/0027-paragraph-style-rules.md)、[golem-driver ADR 0028](../golem-driver/adr/0028-rule-colour-and-style.md)、[golem-driver ADR 0029](../golem-driver/adr/0029-inline-code-background.md)、[golem-driver ADR 0035](../golem-driver/adr/0035-paragraph-rules-split-and-space-units.md)
- [docs/adr/0189](0189-paragraph-alignment-spacing-and-end-indent.md)、[docs/adr/0204](0204-pagination-invariants-by-exhaustive-small-inputs.md)、[docs/adr/0217](0217-html-spaces-of-paragraph-styles-redefined-in-files.md)、[ADR 0261](0261-keep-options-of-paragraph-styles.md)
- Adobe, InDesign User Guide, Apply paragraph borders and backgrounds, https://helpx.adobe.com/indesign/desktop/format-and-style-text/composition-and-text-wrapping/apply-paragraph-borders-and-backgrounds.html（本文は読めず、検索の抜粋で確かめた）
- CTAN, tcolorbox, https://ctan.org/pkg/tcolorbox
- CTAN, mdframed, https://ctan.org/pkg/mdframed
- W3C, CSS Backgrounds and Borders Module Level 3, https://www.w3.org/TR/css-backgrounds-3/
- W3C, CSS Logical Properties and Values Level 1, https://www.w3.org/TR/css-logical-1/
- W3C, Requirements for Japanese Text Layout, https://www.w3.org/TR/jlreq/（該当する節は確かめていない）
