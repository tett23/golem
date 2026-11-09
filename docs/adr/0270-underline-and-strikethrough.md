# ADR 0270: 下線と打ち消し線

ステータス: 採択

## 文脈

ロードマップの v1.0.0 の「LaTeX との差を埋める項目」に、「下線と打ち消し線」がある（[ロードマップ](../roadmap.md)）。
文字スタイルに下線と打ち消し線の欄を加え、線の太さ、種類、位置、色を罫線の指定で書けるようにする項目である。
縦組みでの線の側（傍線）は、InDesign の振る舞いを確かめてから決める、とロードマップは書いている。
同じ v1.0.0 の「和文組版の拡張」から、傍線を取り出してこの項目に含めている。
出どころは [2026-10-17 の調査](../audits/2026-10-17-latex-gap-for-v1.md) の 13 であり、所有者はこの項目を v1.0.0 に置くと決めた（同じ記録の「所有者の決定」）。

この ADR は、同じ時期の ADR の [ADR 0268](0268-opentype-features-on-character-styles.md) と [ADR 0269](0269-superscript-and-subscript.md) と同じく文字スタイルに欄を加える。
どちらにも依存しないが、上付きの字を含む範囲に下線を引く規則は、[ADR 0269](0269-superscript-and-subscript.md) の上付きの大きさと位置に触れる。
番号の順のとおり、[ADR 0269](0269-superscript-and-subscript.md) の後に実装する。

### 今の Golem

文字スタイルに、下線と打ち消し線の欄はない（[`Style.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-project/src/Golem/Project/Style.hs#L220-L247)）。

罫線の書き方は、`style.toml` の罫線の指定として一つに決めてある（[golem-driver ADR 0024](../golem-driver/adr/0024-rule-spec-and-footnote-separator.md)、[golem-driver ADR 0028](../golem-driver/adr/0028-rule-colour-and-style.md)）。
`RuleSpec` は長さ、太さ、前後の間隔、色、線の種類、段落の罫線の字下げを持ち、太さに `zw` を受け付けない（[`Style.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-project/src/Golem/Project/Style.hs#L1158-L1194)、[`Style.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-project/src/Golem/Project/Style.hs#L1219-L1280)）。
線の種類の形は、golem-typeset の `ruleShapes` が帯の中の矩形、円、曲線に分け、すべて塗りで描く（[`RuleShape.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-typeset/src/Golem/Typeset/RuleShape.hs#L44-L56)）。

行の中の文字の範囲に重ねて描くものには、本文の中のコードの背景（[golem-driver ADR 0029](../golem-driver/adr/0029-inline-code-background.md)）と、リンクの注釈の矩形（[ADR 0182](0182-external-links.md)）がある。
どちらも、行に置いた箱のうち同じ値の箱の連なりを、最初の箱の始まりから最後の箱の終わりまで、あいだのグルーを含めて一つの矩形にする（[`Draw.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L734-L777)）。
コードの背景は、行の字より前に、アーティファクトとして描く（[`Draw.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L1007-L1009)）。

### JLReq の傍線と下線

JLReq は、傍線と下線を行間に配置する要素に挙げる。

- 2.4.2：行間にルビ、圏点、傍線、下線などを配置しても、行間は一定にし、変えない。
- 3.3.9：文中の強調の方法の一つに、傍線（又は下線）を付ける方法がある。
- 4.5.1：版面の先頭の行の「縦組における親文字の右側に付けるルビ，圏点及び傍線」と、末尾の行の「縦組における親文字の左側に付けるルビ及び傍線」「横組における親文字の下側に付ける下線」は、版面の外側に接して配置する。

JLReq は、縦組みの傍線を親文字の右にも左にも付けうるとし、横組みの下線を字の下に付ける。
同じ側にルビや圏点がある場合の順は、JLReq に書かれていない。

### InDesign と LaTeX

InDesign は、文字パネルと文字スタイルで下線と打ち消し線を付け、それぞれのオプションで線の太さ、種類、位置（オフセット）、色を決める（調査の 13）。
縦組みで下線が字の右に出るか左に出るかは、調査で確かめられず、所有者の決定の後も確かめられないまま残っている。
InDesign の振る舞いを確かめられない場合は JLReq の本文に従う、という規則（[仕様書の「仕様が不明瞭な場合」](../specifications.md#仕様が不明瞭な場合)）により、縦組みの側は JLReq で決める。

LaTeX は、ulem の `\uline` と `\sout`、soul の `\ul` と `\st`、LuaLaTeX の lua-ul で下線と打ち消し線を引く。

## 実装すること

### style.toml の欄

文字スタイルに、欄 `underline` と `strikethrough` を加える。
値は、次のどれかである。

| 値 | 意味 |
| --- | --- |
| `true` | 既定の線を引く。`{}` と同じ |
| 表 | 書いたキーの線を引く |
| `false` | 外側の線を引かない |

書かなければ、外側の値を引き継ぐ。
`based-on` の鎖では、ほかの欄と同じく、子が書いた値が親の値を置き換える。
表のキーを親とつなぎ合わせることはしない。

表のキーは、罫線の指定のキーのうち線の形を決めるものと、位置を決める `offset` である。

| キー | 型 | 既定 | 意味 |
| --- | --- | --- | --- |
| `weight` | 寸法 | `"0.05zw"` | 線の太さ。0 より大きい |
| `offset` | 符号付きの寸法 | `"0pt"` | 線の位置（次の節） |
| `style` | 文字列 | `"solid"` | 線の種類。罫線の指定の 12 種（[golem-driver ADR 0028](../golem-driver/adr/0028-rule-colour-and-style.md)） |
| `dash` | 寸法 | `weight` の 3 倍 | 破線の線分の長さ |
| `gap` | 寸法 | 線の種類による | 破線と点線の間隔 |
| `color` | スウォッチの名前 | 線を引く字の色 | 線の色 |

```toml
[character-styles.bousen]
underline = true

[character-styles.deleted]
strikethrough = { weight = "0.5pt", color = "red" }

[character-styles.wavy]
underline = { style = "wavy", weight = "0.08zw", offset = "0.05zw" }
```

キーの検査は、罫線の指定と同じ関数で行い、同じ文言とコードを使う。
違いは次のとおりである。

- `weight`、`dash`、`gap` に `zw` を書ける。`zw` は、線を引く字の大きさ（次の節の「線の基準」の大きさ）で数える。罫線の指定が太さに `zw` を受け付けないのは、太さを字の大きさに比例させる理由がないためだった。下線は字に属する線であり、字の大きさを変えれば線も比例して太くなるのが自然である。
- `length`、`space-before`、`space-after`、`start-indent`、`end-indent`、`keep-in-column` は、線の長さと位置を字の範囲が決めるので書けない。未知のキーと同じく G03006 とする。
- `offset` は、罫線の指定にないキーである。寸法として読めない値は G03006 とする。
- `true` と表のほかの値（文字列、数など）は G03006 とする。段落の罫線の `rule-before` は `true` を受け付けないが（[golem-driver ADR 0027](../golem-driver/adr/0027-paragraph-style-rules.md)）、下線はすべてのキーに既定があるので `true` を受け付ける（「メンテナーが決めること」の 3）。
- `color` が `[color.swatches]` にない場合は、罫線と同じく G03013 とする。

原稿の `@style-def` では、表を書けないので、`underline=true` と `underline=false` だけを書ける。
表の線は `style.toml` で定義し、`@style-def` で `based-on` する。

段落スタイルには置かない（「メンテナーが決めること」の 4）。

### 線の基準

入れ子の文字スタイルで下線を引くとき、線の位置と太さをどの字で決めるかを定める。
CSS の文字の飾り（text decoration）と同じく、線を書いた文字スタイルの側で決め、内側で大きさや位置を変えても線は動かないことにする。

文字スタイルの入れ子で、`underline`（`strikethrough`）の値を書いた定義に `based-on` の鎖で行き着くスタイルの適用のうち、ある字を含む最も内側のものを、その字の**線の基準**と呼ぶ。
線の基準の大きさ `s`、色、`baseline-shift` が、線の太さと位置と既定の色を決める。
線の基準より内側の文字スタイルの `size`、`baseline-shift`、[ADR 0269](0269-superscript-and-subscript.md) の `position` は、線を動かさない。
上付きの字を含む範囲に下線を引いても、線はまっすぐに続く。
内側で `underline = false` を書けば、その範囲では線が切れ、内側で別の表を書けば、その範囲は内側の線の基準で引く。

### 線の位置

線の基準の大きさを `s`、行の基準線（縦組みでは行の中心線）を線の基準の `baseline-shift` だけずらしたものを基にする。
字面の枠は、今のコードの背景と同じく、横組みでは高さ `s` で基準線を上から 0.88 の位置に置いた枠、縦組みでは幅 `s` で行の中心線に中心を置いた枠とする。

| 線 | 横組み | 縦組み |
| --- | --- | --- |
| 下線 | 字面の枠の下端から `offset` だけ下に、線の上の縁を置く | 字面の枠の右端から `offset` だけ右に、線の左の縁を置く（傍線） |
| 打ち消し線 | 字面の枠の中心から `offset` だけ上に、線の中心を置く | 字面の枠の中心から `offset` だけ右に、線の中心を置く |

`offset` が正なら、下線は字から離れ、打ち消し線は横組みで上、縦組みで右へ動く。
打ち消し線の向きは、`baseline-shift` と同じである。

縦組みの下線を字の右に引くのは、JLReq の 4.5.1 が傍線を親文字の右に付けるものとして最初に挙げ、圏点とルビの側（右）と同じとしているためである。
InDesign の縦組みの下線の側は確かめていない。
左の傍線は、v1 では引かない（「実装しないこと」）。

縦組みでは、傍線と同じ右の側にルビの読みと圏点が来る。
行の一つの区画（次の節）の中に、右に読みか圏点を持つ箱があるときは、区画の全体の傍線を、その区画の読みと圏点の右端のうち最も右のものから `offset` だけ右に置く（「メンテナーが決めること」の 2）。
線を区画の中で曲げないために、区画の全体を動かす。
横組みの下線はルビと圏点の反対の側にあり、打ち消し線は字の中にあるので、動かさない。

線は行送りを変えず、行分割と改ページにも影響しない（JLReq の 2.4.2）。
版面の先頭と末尾の行の線が版面の外にはみ出しても、行の位置は変えない（JLReq の 4.5.1）。

### 線を引く範囲

行ごとに、行に置いた箱のうち、下線（打ち消し線）の値が等しい箱の連なりを一つの**区画**とする。
値が等しいとは、解決した線の太さ、位置、種類、破線の長さ、色、線の基準の基準線のずらしがすべて等しいことである。
区画は、最初の箱の始まりから最後の箱の終わりまでとし、あいだのグルー（語間の空白、アキ量のセットの空き）を含む。
コードの背景とリンクの矩形と同じ取り方である。

- 別々に当てた同じ文字スタイルが隣り合えば、値が等しいので一つの区画になり、線に切れ目はできない。
- 値の違う線が隣り合えば、別の区画になり、境で接する。
- 区画は行をまたがない。行末で分かれた範囲は、行ごとの区画になる。
- 行末で捨てる空白（行分割で消えるグルー）は、行に置かれないので線を引かない。
- 下線のある箱と下線のない箱のあいだの空白は、区画に入らない。下線のある範囲の最後に書いた空白も、次の字に下線がなければ線を引かない。
- 行末のハイフンと、ぶら下げた約物は、箱に含まれるので線を引く。
- ルビの親文字には線を引き、ルビの読みと圏点の字には引かない。縦中横の箱にも引く。
- 中身のない範囲（`[style bousen:]`）は箱を作らないので、線を引かない。

### 線の形と描く順

区画の長さを `L`、太さを `w` とする帯に、[golem-driver ADR 0028](../golem-driver/adr/0028-rule-colour-and-style.md) の線の種類の形を `ruleShapes` で描く。
破線と点線の割り付けは、区画ごとに行う。
帯の「前」の縁は、横組みでは上、縦組みでは右であり、多重線の比もこの向きで数える。

PDF では、行の内容を次の順に描く。

1. 本文の中のコードの背景（今と同じ）
2. 下線
3. 行の字
4. 打ち消し線

下線を字の前に描くのは、欧文の字のディセンダーと線が重なる場合に、字を線で隠さないためである。
打ち消し線を字の後に描くのは、色の付いた線が字に隠れないためである。

線の色は、`color` があればそのスウォッチの CMYK を DeviceCMYK で塗る。
なければ線の基準の字の色（文字スタイルの `color`）で塗り、字に色がなければ色を設定せずに塗る（今の罫線と同じ）。

線の図形は、アーティファクト（`/Artifact << /Type /Layout >>`）として描く。
タグ付き PDF の構造の木には、線を引いた範囲（線の基準の適用の範囲）ごとに、属性 `/A << /O /Layout /TextDecorationType /Underline >>`（打ち消し線では `/LineThrough`）を持つ `Span` を加える（ISO 32000-1 の 14.8.5.4.3、「メンテナーが決めること」の 5）。
下線と打ち消し線の両方がある範囲は、下線の `Span` の中に打ち消し線の `Span` を置く。
縦組みの傍線も `/Underline` とする。
ISO 32000-1 の `TextDecorationType` は、行の方向に対する側を区別しないためである。
`Span` は、言語の区間の `Span`（[docs/adr/0187](0187-inline-language-switch.md)）と同じ仕組みで作る。

golem preflight は、線の最も細い部分の太さを罫線の太さ（`RuleView` の `rvWeight`）に加え、細すぎる線を G09018 で報告する。
線の色のスウォッチを、使ったスウォッチに加え、総インキ量の検査（G09015）の対象にする。

### HTML と EPUB

`cs-名前` の CSS に、`text-decoration` の性質を書く。

| Golem | CSS |
| --- | --- |
| `underline` | `text-decoration-line: underline` |
| `strikethrough` | `text-decoration-line: line-through` |
| 両方 | `text-decoration-line: underline line-through` |
| `weight` | `text-decoration-thickness`（`zw` は `em`、絶対の寸法は `pt`） |
| `style` | `text-decoration-style`。`"solid"` は `solid`、`"dashed"` は `dashed`、`"dotted"` と `"japanese-dots"` は `dotted`、多重線の 7 種は `double`、`"wavy"` は `wavy` |
| `color` | `text-decoration-color`（スウォッチの RGB の近似）。書かなければ書かない（CSS の既定は字の色） |
| `offset`（下線） | `text-underline-offset`。0 なら書かない |
| 縦組みの本の下線 | `text-underline-position: right` |

`dash` と `gap` と、打ち消し線の `offset` は、CSS で表せないので書かない。

CSS と PDF は、次の点で違う。
仕様書に書いて受け入れる。

- `text-underline-offset` は書体が決める位置からの距離であり、Golem の字面の枠からの距離と一致しない。
- 一つの要素の `text-decoration-style`、`-color`、`-thickness` は下線と打ち消し線で共通なので、両方を書いたスタイルでは下線の値を書く。
- CSS の文字の飾りは子孫の要素で消せないので、`underline = false` は HTML と EPUB では外側の線を消さない。`false` を写した CSS は書かない。
- 範囲の最後の空白にも、CSS は線を引く。

読書環境が `text-underline-position: right` を読むかは確かめていない。
HTML と EPUB の見た目の確かめは、致命的な崩れだけを見る方針なので、ブラウザーでの位置は確かめない。

プレーンテキストは、線を出さず、字を原稿のまま出す。

### 互換

意味論 IR とプラグインの ABI は変わらない。
文字スタイルは名前で IR に入り、二つの欄は `style.toml` の中だけの値である。
`abiVersion` と CDDL は変えない。
二つの欄を書かない本の出力は変わらない。

### パッケージの依存

golem-* のパッケージのあいだの依存は変えない。
欄の読み込みは golem-project に、線の基準と区画は golem-layout と golem-typeset に、CSS は golem-html に置き、線の形は golem-typeset の `ruleShapes` を使う。

### データ構造

- golem-project に、線の指定 `DecorationSpec`（太さ、`offset`、`RuleStyle`、色）を加える。太さと破線の長さは `zw` を含む寸法で持ち、線の基準の大きさで解決する。罫線の指定と共通のキーの読み込みは、`RuleSpec` の読み込みと一つの関数にまとめる。
- `CharStyleDef` に `csUnderline` と `csStrikethrough`（どちらも `Maybe (Maybe DecorationSpec)`、外の `Nothing` は書かない、内の `Nothing` は `false`）を加える。`overChar` は、ほかの欄と同じく書いた値が勝つ。
- golem-layout の `Look` に、解決した下線と打ち消し線（`Maybe Decoration`、sp に解決した太さ、位置、種類、色、線の基準の大きさと基準線のずらし）を加える。値が等しい箱の連なりが区画になる。
- golem-typeset の `Draw.hs` に、行ごとの区画を求める純粋な関数を、`codeBackgrounds` と同じ形で置く。縦組みでは、区画の中の読みと圏点の右端を受け取る。

### 文書

- docs/specifications.md：「style.toml」の節の文字スタイルのキーに `underline` と `strikethrough` を加え、線の基準、位置、範囲、描く順、色、HTML と EPUB の CSS とその差を書く。「タグ付き PDF」の節の表に、線を引いた範囲の `Span` を加える。
- docs/diagnostics.md：G03006 と G03013 の主な原因に、二つの欄を加える。新しいコードは使わない。
- docs/roadmap.md：v1.0.0 の「LaTeX との差を埋める項目」から「下線と打ち消し線」を消し、v1.0.0 の「和文組版の拡張」から「傍線」を消す。左の傍線を残す場合は、「和文組版の拡張」に「左の傍線」と書き直す。
- 使い手のマニュアル：`manual/chapters/05-style.gm` と `manual/appendices/c-style.gm` に二つの欄を書き、`manual/appendices/f-indesign.gm` に InDesign の下線と打ち消し線のオプションとの対応と、縦組みの側を JLReq で決めたことを書き、`manual/appendices/h-roadmap.gm` から項目を消す。
- docs/markup.md は記法を変えないので変えない。

## 実装しないこと

- 縦組みの左の傍線（JLReq の 4.5.1 の「左側に付ける傍線」）。側を選ぶ欄は、使う本が現れたら加える。加えても互換を壊さない。
- 上線（InDesign にない）と、二本の傍線を両側に引くこと。
- 下線の組み込みの文字スタイル（「メンテナーが決めること」の 1）。
- 字のディセンダーをよけて下線を切ること（CSS の `text-decoration-skip-ink`）。
- 書体の `post` の表の下線の位置と太さ、`OS/2` の表の打ち消し線の位置を使うこと（「メンテナーが決めること」の 6）。
- InDesign の線の間隔の色と濃淡、オーバープリント（[golem-driver ADR 0028](../golem-driver/adr/0028-rule-colour-and-style.md) の「実装しないこと」と同じ）。
- 段落スタイルの `underline` と `strikethrough`（「メンテナーが決めること」の 4）。
- HTML と EPUB で、PDF と同じ位置と破線の長さに合わせること。
- 原稿の `@style-def` で線の表を書くこと。

## 不変条件

- **I1 線は組版を変えない**：どの原稿でも、`underline` と `strikethrough` の値だけを変えた二つの本の、行分割（各行の箱とその位置）、行送り、改ページは等しい。
- **I2 区画は行の中にある**：どの区画も、一つの行の最初の箱の始まりから最後の箱の終わりまでの中にあり、二つの行にまたがらない。
- **I3 等しい区画は接しない**：同じ行の、同じ値の二つの区画のあいだには、その値でない箱が少なくとも一つある。隣り合う同じ値の箱は、必ず一つの区画に入る。
- **I4 区画は線を引く箱をすべて覆う**：行の箱のうち下線の値を持つ箱は、ちょうど一つの区画に入り、値を持たない箱はどの区画にも入らない。
- **I5 線はまっすぐ**：一つの区画の帯は、行の方向に直交する位置と太さが区画の全体で一つである。
- **I6 線の基準の内側は線を動かさない**：線の基準の内側の文字スタイルの `size`、`baseline-shift`、`position` だけを変えた二つの本の帯は等しい。
- **I7 傍線は字とルビと圏点の外**：縦組みの下線の帯の左の縁は、区画の中のすべての箱の字面の枠の右端と、読みと圏点の右端より、`offset` 以上右にある（`offset` が 0 以上のとき）。横組みの下線の帯の上の縁は、字面の枠の下端より `offset` だけ下にある。
- **I8 描く順**：どの行でも、内容のストリームの中で、下線の図形はその行の字より前に、打ち消し線の図形はその行の字より後に現れる。
- **I9 書かない本は変わらない**：二つの欄を書かない本の PDF、HTML、EPUB、プレーンテキストのバイト列と diagnostics は、この変更の前と一致する。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 範囲の字の数 | 0、1、2、行にちょうど収まる、一字あふれて次の行に続く |
| 範囲の端 | 行の始まり、行末、範囲の最後の空白、範囲の前と後ろの空白 |
| 隣り合う範囲 | 同じ値、太さだけ違う、色だけ違う、`false` を挟む |
| 入れ子 | 内側の `size`、`baseline-shift`、`position = "superscript"`、内側の `underline = false`、内側の別の表 |
| ルビと圏点 | なし、区画の途中に一つ、区画の全体、区画の外の隣 |
| 線の種類 | 実線、多重線、破線（区画が線分一つより短い）、点線、波線 |
| 書字方向 | 横組み、縦組み（立てた和文、回転する欧文、縦中横） |
| 位置 | 版面の先頭の行、末尾の行 |

## テスト設計

実装の前に書き、失敗することを確かめる。
テストの名前には、不変条件の番号を入れる。

### golem-project（`modules/golem-project/test/Main.hs`）

- `underline = true` が既定の線（0.05zw、`offset` 0、実線、色なし）になり、`{}` と等しい。`underline = false` が内の `Nothing` になる。
- `weight = "0.08zw"`、`style = "dashed"` を読むと、破線の既定の長さが `weight` から求まる。
- `length = "1zw"`、`space-before = "1pt"`、`keep-in-column = true`、`underline = "yes"`、`offset = "abc"` が、それぞれ G03006 になる。`color` がスウォッチにないと G03013 になる。
- `@style-def character x underline=true` を読め、`underline="{}"` は G03006 になる。

### golem-layout と golem-typeset（`modules/golem-layout/test/`、`modules/golem-typeset/test/`）

- I1：短い和文と欧文の字の列と、その中の一つか二つの範囲を、行長と範囲の位置を変えて小さな入力のすべてで列挙し、`underline` を書いた本と書かない本の行分割が等しいことを確かめる（[docs/adr/0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の列挙の部品を使う）。
- I2、I3、I4：同じ列挙で、区画を求める関数の結果について確かめる。
- I5、I6：線の基準の内側に `size = "2zw"`、`baseline-shift = "0.3zw"`、`position = "superscript"` を入れた区画の帯が、入れない区画の帯と等しい。
- I7：縦組みで、区画の途中にルビを持つ範囲の傍線の帯が、読みの右端より右にあり、ルビのない区画では字面の枠の右端から `offset` だけ右にある。横組みでは、ルビがあっても下線の位置が変わらない。
- I8：下線と打ち消し線を持つ行の内容のストリームで、下線の矩形が字の前、打ち消し線の矩形が字の後にある。どちらも `/Artifact` の中にある。
- 色：`color` を書かない下線が、線の基準の字の `color` のスウォッチで塗られ、字に色がなければ色を設定しない。
- タグ付き PDF：線を引いた範囲が `/TextDecorationType /Underline` の `Span` になり、両方の範囲では入れ子の `Span` になる。
- preflight：太さ 0.05zw の下線を 2pt の字に当てた本で、G09018 が線の太さ 0.1pt を報告する。

### golem-html（`modules/golem-html/test/`）

- `underline = { style = "wavy", weight = "0.08zw" }` の CSS が `text-decoration-line: underline; text-decoration-style: wavy; text-decoration-thickness: 0.08em` を持つ。縦組みの本では `text-underline-position: right` も持つ。
- `strikethrough = true` の CSS が `text-decoration-line: line-through` を持つ。

### golem-driver（`modules/golem-driver/test/`）

- I9：二つの欄を書かない fixture の PDF、HTML、EPUB、プレーンテキストのバイト列と diagnostics が、変更の前に記録したものと一致する。
- プレーンテキストで、下線の範囲の字が原稿のまま出る。

### 自動テストにできないものの確かめ方

- 縦組みと横組みの見本の原稿（傍線、ルビと傍線、打ち消し線、波線の下線）を組み、ページを画像にして、線が字に重ならず、区画の境に切れ目がないことを目で確かめる。見本を見た目の回帰テストに加えるかは、実装のプルリクエストで決める。

## トレードオフ

線の位置を、書体の表（`post` と `OS/2`）でなく、字面の枠から決めた。
書体の表を使えば欧文の下線は書体の設計どおりの位置になるが、和文と欧文で書体が違う範囲では線が段違いになる。
字面の枠からの位置は書体によらず一つに決まり、JLReq の字面の枠の考え方とも合う。
試験に使う書体の `post` の下線の上の縁は基準線から 0.05 から 0.075 字の下、`OS/2` の打ち消し線の位置は基準線から 0.285 から 0.308 字の上にある。
字面の枠から決めると、下線は基準線から 0.12 字の下、打ち消し線の中心は 0.38 字の上になり、どちらも書体の設計より 0.05 から 0.1 字ほど外れる。
欧文の本でこの差が気になれば、`offset` で直す。

線の基準を CSS と同じく外側に置いた。
字ごとの大きさと位置で線を引けば、上付きの字の下で線が細くなって上がり、線が途切れて見える。
その代わり、内側の大きな字の下端が線にかかることがある。

縦組みの傍線を右に固定し、同じ側の読みと圏点の外に区画の全体を動かすことにした。
区画の中で線を曲げずに済むが、ルビの一字を含む区画では、ルビのない字の傍線も字から離れる。
区画は行ごとなので、離れるのはその行の範囲だけである。

太さに `zw` を受け付け、罫線の指定と規則を変えた。
同じキーの名前で受け付ける単位が違うことになるが、罫線は版面に属し、下線は字に属するという違いに対応する。

## メンテナーが決めること

1. **組み込みの文字スタイルを加えるか**：推奨は加えないことである。下線と打ち消し線は、強調、削除、挿入、試験の問いの印など、本によって意味が違い、意味の名前を付けるのは書き手である。HTML の `<u>`、`<s>`、`<del>` のどれに写すかも意味によって変わる。
   - 退けた案は、`underline` と `strikethrough` の組み込みの文字スタイルを加え、HTML で `<u>` と `<s>` にすることである。名前が欄の名前と同じになり、`[character-styles.underline] underline = true` のような紛らわしい定義が生まれる。
2. **縦組みの傍線とルビと圏点が同じ側に来たときの位置**：推奨は、区画の全体の傍線を、区画の読みと圏点の外に置くことである。読みと圏点の位置は変えない。
   - 退けた案の一つは、傍線を字面の枠の右に置いたまま読みと圏点と重ねることである。線が読みを横切る。
   - もう一つは、傍線を字と読みのあいだに置き、読みと圏点を線の太さと `offset` の分だけ外へ動かすことである。ルビの配置（[golem-layout ADR 0009](../golem-layout/adr/0009-ruby-placement.md)）を変え、線のない本と読みの位置が変わる。
   - さらに、重なりを diagnostic で報告する案もある。重ならない配置を決められるので、報告で済ませる理由がない。
3. **`true` を受け付けるか**：推奨は受け付け、`{}` と同じにすることである。InDesign の下線はチェックボックスで付け、すべてのキーに既定がある。
   - 退けた案は、段落の罫線（[golem-driver ADR 0027](../golem-driver/adr/0027-paragraph-style-rules.md)）と同じく `true` を誤りにし、`{}` と書かせることである。`@style-def` で下線を書けなくなる。
4. **段落スタイルにも置くか**：推奨は、v1 では文字スタイルだけに置くことである。段落の全体に下線を引く使い方は少なく、段落の罫線とも紛らわしい。後から段落スタイルに加えても互換を壊さない。
   - 退けた案は、[docs/adr/0020](0020-indesign-character-features.md) の考え方のとおり、InDesign と同じく段落スタイルにも置くことである。[ADR 0268](0268-opentype-features-on-character-styles.md) の `features` は段落の単位の使い方（表の数字）があるので両方に置くが、下線にはそれにあたる使い方が見つからない。
5. **タグ付き PDF に線の意味を残すか**：推奨は、線を引いた範囲を `TextDecorationType` を持つ `Span` にすることである。法令の新旧対照の打ち消し線や、試験の問いの傍線は、線そのものが意味を持つ。アーティファクトの図形だけでは、読み上げの環境に線のあることが伝わらない。
   - 退けた案は、線をアーティファクトとして描くだけにすることである。構造の木は変わらないが、線の意味が失われる。
6. **線の位置を書体の表から取るか**：推奨は、字面の枠から決めることである（「トレードオフ」）。
   - 退けた案は、欧文の書体の `post` の `underlinePosition` と `underlineThickness`、`OS/2` の `yStrikeoutPosition` を使うことである。和欧の混じった範囲で線が段違いになり、和文の書体の値は和文の字面の枠と合わないことがある。
7. **既定の太さ**：推奨は 0.05zw（10pt の字で 0.5pt）である。試験に使う書体（Source Sans Pro、Source Serif、Noto Serif JP）の `post` の下線の太さは、どれも字の大きさの 5% である。
   - 退けた案は、罫線の既定の 0.3pt にそろえることである。字の大きさによらない太さは、見出しの大きな字の下で細すぎ、注の小さな字の下で太すぎる。

## 決めたことの記録

2026-11-09 に、tett23 がすべて推奨のとおりに決めた。

1. 推奨のとおり、組み込みの文字スタイルは加えない。
2. 縦組みで傍線とルビと圏点が同じ側に来たときは、推奨のとおり区画の全体の傍線を区画の読みと圏点の外に置く。
3. 推奨のとおり、`true` を受け付け、`{}` と同じにする。
4. 推奨のとおり、v1 では文字スタイルだけに置く。
5. 推奨のとおり、線を引いた範囲をタグ付き PDF の `TextDecorationType` を持つ `Span` にする。
6. 線の位置は、推奨のとおり字面の枠から決める。
7. 既定の太さは、推奨のとおり 0.05zw とする。

この ADR は新しい diagnostic のコードを足さない。

## 参考文献

- [2026-10-17 の調査](../audits/2026-10-17-latex-gap-for-v1.md) の 13 と「所有者の決定」
- [ロードマップ](../roadmap.md) の「LaTeX との差を埋める項目」と「和文組版の拡張」
- [仕様書の「style.toml」](../specifications.md#styletoml)、[仕様書の「タグ付き PDF」](../specifications.md#タグ付き-pdf)、[仕様書の「仕様が不明瞭な場合」](../specifications.md#仕様が不明瞭な場合)
- [golem-driver ADR 0024](../golem-driver/adr/0024-rule-spec-and-footnote-separator.md)、[golem-driver ADR 0027](../golem-driver/adr/0027-paragraph-style-rules.md)、[golem-driver ADR 0028](../golem-driver/adr/0028-rule-colour-and-style.md)、[golem-driver ADR 0029](../golem-driver/adr/0029-inline-code-background.md)、[golem-driver ADR 0019](../golem-driver/adr/0019-pdf-kenten-shapes.md)
- [golem-layout ADR 0009](../golem-layout/adr/0009-ruby-placement.md)
- [docs/adr/0020](0020-indesign-character-features.md)、[docs/adr/0183](0183-tagged-pdf-and-pdf-a.md)、[docs/adr/0187](0187-inline-language-switch.md)、[ADR 0182](0182-external-links.md)、[docs/adr/0204](0204-pagination-invariants-by-exhaustive-small-inputs.md)
- [ADR 0268](0268-opentype-features-on-character-styles.md)、[ADR 0269](0269-superscript-and-subscript.md)
- W3C, Requirements for Japanese Text Layout（JLReq）, https://www.w3.org/TR/jlreq/ の 2.4.2、3.3.9、4.5.1
- Adobe, InDesign User Guide, "Format characters", https://helpx.adobe.com/ca/indesign/using/formatting-characters.html（本文は読めず、調査の抜粋による。縦組みの下線の側は確かめていない）
- ISO 32000-1:2008, 14.8.5.4.3 Inline-Level Structure Element Attributes（`TextDecorationType`）
- W3C, CSS Text Decoration Module Level 3, https://www.w3.org/TR/css-text-decor-3/ と Level 4, https://www.w3.org/TR/css-text-decor-4/（`text-decoration-thickness`、`text-underline-offset`）
- CTAN, ulem, https://ctan.org/pkg/ulem 、soul, https://ctan.org/pkg/soul 、lua-ul, https://ctan.org/pkg/lua-ul
