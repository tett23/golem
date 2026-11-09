# ADR 0268: 文字スタイルの OpenType の機能

ステータス: 採択

## 文脈

ロードマップの v1.0.0 の「LaTeX との差を埋める項目」に、「文字スタイルの OpenType の機能」がある（[ロードマップ](../roadmap.md)）。
文字スタイルに `features` の欄を加え、スモールキャップ、分数、数字の形式、スタイルセットなどを文字の範囲に当てられるようにする項目である。
書体にない機能の扱いと、合成のスモールキャップを作るかは ADR で決める、とロードマップは書いている。
出どころは [2026-10-17 の調査](../audits/2026-10-17-latex-gap-for-v1.md) の 15 であり、所有者はこの項目を v1.0.0 に置くと決めた（同じ記録の「所有者の決定」）。

この ADR は、同じ時期に書いた ADR の一つである。
[ADR 0269](0269-superscript-and-subscript.md)（上付きと下付き）は、この ADR が決める範囲ごとの機能の仕組みで書体の上付きの字形を選ぶので、この ADR の後に実装する。

### 今の機能の指定

OpenType の機能は、書体の役割ごとの `features` でしか指定できない（[仕様書の「フォント」](../specifications.md#フォント)）。
`FontRole` は和文と欧文のファイルと、機能の文字列の並び `frFeatures` を持つ（[`Style.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-project/src/Golem/Project/Style.hs#L207-L212)）。
文字スタイル `CharStyleDef` は機能の欄を持たない（[`Style.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-project/src/Golem/Project/Style.hs#L220-L247)）。
そのため、欧文の略語をスモールキャップで組むには、`smcp` を書いた役割を一つ増やし、文字スタイルの `font` でその役割を指すしかない。
役割を増やすと、同じフォントのファイルを二つの役割に書くことになり、本文の役割の機能を変えたときに二か所を直す必要がある。

役割の機能の文字列は、検査されない。
golem-font の C の側は、並びを `,` でつないだ文字列を HarfBuzz の `hb_feature_from_string` で一つずつ読み、読めない文字列を黙って捨て、33 個めからの機能も黙って捨てる（[`golem_font.c`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-font/cbits/golem/golem_font.c#L139-L161)）。
書き手の書いた機能が組版に適用されないことを、Golem は報告しない。

### 機能を足す今の仕組み

PDF のシェイピングは、役割の `features` の後ろに、カーニングの方式と `proportional-metrics` が決める機能を足す（[docs/adr/0020](0020-indesign-character-features.md)）。
足す機能は `Shaping` の `shExtra` に入り、`shapingOf` が字ごとに決める（[`Fonts.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-typeset/src/Golem/Typeset/Fonts.hs#L83-L91)、[`Fonts.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-typeset/src/Golem/Typeset/Fonts.hs#L506-L527)）。
HarfBuzz は、同じタグの機能が二度あると後ろのものを採る。
JLReq の規則で前後の空きを決める約物には、この仕組みで `-palt` と `-vpal` を最後に足し、役割の `palt` と `vpal` を打ち消している（[docs/adr/0053](0053-no-palt-on-jlreq-punctuation.md)）。

行分割の送りの計測と、描画のシェイピングは、同じ `Shaping` を受け取る `LoadedFonts` の関数で行う。
二つが同じ機能でシェイピングするので、行分割が見込んだ幅と描いた幅が一致する。
ランのシェイピングのメモ（[ADR 0253](0253-memoise-run-shaping-and-shorten-the-memo-key.md)）は、機能の文字列をキーに入れる。
符号のないタグ、`+` と `-` の付いたタグをキーの範囲に入れ、`kern=0` のような値の付いた形は範囲の外としてメモせずに計算する（[ADR 0255](0255-record-what-implementations-decided-on-2026-11-09.md)、[`Memo.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-typeset/src/Golem/Typeset/Memo.hs#L100-L118)）。

HTML と EPUB の CSS には、`proportional-metrics` だけを `font-feature-settings` に書いている（[`Html.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-html/src/Golem/Html.hs#L1102-L1109)）。
役割の `features` は CSS に書かない。

### InDesign と LaTeX

InDesign は、文字パネルのメニューで、分数、上付き序数表記、スワッシュ字形、スモールキャップ、数字の形式、スタイルセットなどを選び、文字スタイルと段落スタイルに保存できる（調査の 15）。
書体にない機能は、メニューで角括弧つきで示され、選んでも組版は続く。
スモールキャップは、書体にスモールキャップの字形がなければ大文字を縮めて合成する。
この調査は helpx.adobe.com の本文を読めず、検索の結果の抜粋で確かめたものである。
角括弧の表示と合成のスモールキャップのほかの振る舞い（機能を一つずつ持つのか、組み合わせて持つのか）は、確かめていない。

LaTeX は、fontspec の `\addfontfeatures` で、書体の定義に機能を足す。
スモールキャップの `\textsc` は、書体にスモールキャップがなければ、警告を出して元の字形で組む。

JLReq は、OpenType の機能を扱わない。
したがって、この ADR の規則は InDesign の振る舞いと Golem の原則（決定性、黙って出力を変えない）で決める。

## 実装すること

### style.toml の欄

文字スタイルと段落スタイルに、欄 `features` を加える。
値は、機能の文字列の配列である。

```toml
[character-styles.small-caps]
features = ["smcp"]

[character-styles.abbr]
based-on = "small-caps"
features = ["c2sc"]

[paragraph-styles.table-cell]
features = ["tnum", "lnum"]

[character-styles.alt]
features = ["salt=2", "-liga"]
```

段落スタイルにも置くのは、InDesign で文字の属性を段落スタイルも持つので、文字の送りの四つの欄と同じく両方に置くという [docs/adr/0020](0020-indesign-character-features.md) の考え方に合わせるためである（「メンテナーが決めること」の 1）。
表の数字を等幅にする、本文の数字をオールドスタイルにする、といった指定は段落の単位で書くことが多い。

### 機能の文字列の書き方

機能の文字列は、役割の `features` と同じ HarfBuzz の書き方のうち、次の四つの形だけを受け付ける。

| 形 | 意味 | 正規の形 |
| --- | --- | --- |
| `tag` | 機能を有効にする（値 1） | `tag` |
| `+tag` | 機能を有効にする（値 1） | `tag` |
| `-tag` | 機能を止める（値 0） | `-tag` |
| `tag=N` | 機能を値 N で有効にする。`N` は 0 から 65535 までの十進の整数 | `N` が 0 なら `-tag`、1 なら `tag`、ほかは `tag=N` |

`tag` は、英字と数字の 4 字である（`smcp`、`ss01`、`jp90` など）。
OpenType の登録済みの機能のタグはどれもこの形に入り、空白を含むタグは使われていない。
HarfBuzz が読めるほかの形（`kern[3:5]` のような範囲の指定、`aalt=on` のような語の値）は受け付けない。
範囲は Golem では文字スタイルで書くので、文字列の中に範囲を書く理由がない。

読めない文字列は、エラー（G03124）とする。
メッセージは `OpenType の機能の書き方が正しくありません: <文字列>（smcp、-liga、salt=2 のように書きます）` とし、位置は配列のその要素とする。
誤りのある要素を一つ報告するごとに一つの G03124 を出し、要素の順に並べる。
誤りのある定義は、ほかの `style.toml` の誤りと同じく捨てる。

役割の `features` にも、同じ検査をかける（「メンテナーが決めること」の 2）。
今まで黙って捨てていた文字列が、エラーになる。

原稿の `@style-def` では、配列を書けないので、`features="smcp,-liga"` のように `,` で区切った一つの文字列で書く。
空の要素（`features="smcp,"`）は G03124 とする。

### 機能の並べ方

ある字をシェイピングする機能の並びは、次の順につないだものとする。
後ろの機能が、前の同じタグの機能に勝つ。

1. 役割の `features`。縦書きの役割の既定の機能を含む（今と同じ）。
2. 段落スタイルの `features`。`based-on` の鎖の根から順に、子の定義を後ろに置く。
3. 文字スタイルの `features`。入れ子の外側から順に、各スタイルの中では `based-on` の鎖の根から順に置く。
4. Golem が足す機能。[ADR 0269](0269-superscript-and-subscript.md) の上付きと下付きの機能と、カーニングの方式、`proportional-metrics`、JLReq の約物の打ち消し（[docs/adr/0020](0020-indesign-character-features.md)、[docs/adr/0053](0053-no-palt-on-jlreq-punctuation.md)）である。

`features` は、ほかの欄と違い、`based-on` の子が親の値を置き換えるのではなく、親の並びの後ろにつなぐ。
InDesign では機能の一つずつが文字の属性なので、子のスタイルでスモールキャップを有効にしても、親のオールドスタイル数字は残る。
並びをつなぎ、同じタグでは後ろが勝つとすれば、この属性の振る舞いになる。
親の機能を止めたい子は、`-tag` を書く。
組み込みのスタイルと同じ名前の表を書いた場合と、`@style-def` で同じ名前の定義を重ねた場合も、元の定義の並びの後ろに、書いた並びをつなぐ。

つないだ並びは、タグごとに最後の値だけを残し、その位置に正規の形で置いた並びにしてから、シェイピングに渡す。
HarfBuzz の結果は、同じタグの前の機能を残しても変わらない。
並びを短くするのは、メモのキーを短くするためである。

Golem が足す機能を最後に置くので、カーニングの方式と `proportional-metrics` は `features` に勝つ。
`features = ["palt"]` を書いた文字スタイルでも、`kerning = "japanese-equal-width"` の字は全角で組み、JLReq の約物には `palt` が当たらない。
役割の `features` の `palt` と同じ扱いである。

### JLReq の約物と幅を変える機能

JLReq の規則で前後の空きを決める約物には、[docs/adr/0053](0053-no-palt-on-jlreq-punctuation.md) が `palt` と `vpal` を当てない。
同じ理由で、約物の字形を半角の幅にする機能 `halt`、`vhal`、`chws`、`vchw` も当てない（「メンテナーが決めること」の 3）。
これらは JLReq の約物の空きと同じことを書体の側で行う機能であり、Golem の空きと重なると、空きが二重に詰まる。
並び（役割、段落スタイル、文字スタイル）がこれらを有効にしている字が約物のときだけ、4 の段で `-halt`、`-vhal`、`-chws`、`-vchw` のうち有効なものを足す。
有効にしていない本の機能の並びは変わらない。

### シェイピングの範囲

機能の並びは、golem-layout の `Look` の新しい欄 `lkFeatures`（正規の形の並び、段落スタイルと文字スタイルの分だけ）に持たせる。
`Look` が違う字は今も別の箱になり、別々にシェイピングするので、機能の並びが変わる位置でシェイピングの範囲が切れる。
機能の境をまたいで合字やカーニングはかからない。
「ペアの一方が別の見た目のときは、カーニングしない」という今の規則の一つの場合である。

`shapingOf` は、`lkFeatures` を `shExtra` の前に置く。
行分割の計測（`lfAdvance`、`lfWordAdvance`）と描画（`lfShape`）が同じ `Shaping` を使う今の形を保つので、行分割の幅と描いた幅は一致する。

縦組みでも、機能は書いたとおりに渡す。
`proportional-metrics` は縦組みで `palt` を `vpal` に読み替えるが、`features` の文字列は読み替えない。
縦組みの和文に `palt` を書いても、縦書きの方向のシェイピングでは送りが変わらない。
縦書きの字形は HarfBuzz が縦書きの方向で既定に有効にするので、`-vert` を書けば横組みの字形になる。
縦組みの中で回転して組む欧文と縦中横は、横書きの方向でシェイピングし、同じ機能の並びを使う。

ルビの読みは、外側の書体と色で組む今の規則のとおり、外側の見た目の機能で組む。
圏点の字は、役割の機能だけで組み、文字スタイルの機能を当てない。
圏点の形の字を選ぶのは `[kenten]` の `shape` であり、文字スタイルの機能で字形を変える理由がないためである。
注の印は、印の文字スタイルの機能で組む。

golem-font の C の関数は、渡された機能をすべて HarfBuzz に渡す。
33 個めからを捨てる今の上限をなくし、機能の数だけ領域を取る。
文字スタイルを入れ子にすると、機能の数が 32 を超えることがあるためである。

### メモのキー

[ADR 0253](0253-memoise-run-shaping-and-shorten-the-memo-key.md) のキーの符号を、`tag=N` の形を範囲に入れるよう広げる。
符号（0 は符号なし、1 は `+`、2 は `-`）に 3 を足し、3 のときは値 `N` を三つめの要素に置く。
正規の形は `+tag` を作らないので、1 の符号はシェイピングに渡る機能には現れないが、逆の写像のために残す。
[ADR 0253](0253-memoise-run-shaping-and-shorten-the-memo-key.md) の I2（キーは単射で逆を持つ）と I3（キーの要素は範囲の中）を、`tag=N` を含めて保つ。

### 書体にない機能

有効にした機能を書体が持たないときは、PDF をターゲットに含む `golem build` で G08103 を出す。
重大度はプロファイルで変わり、dev では警告、prod ではエラーとする（G08100 と同じ）。
dev では PDF を書き、prod では PDF を書かず（前のビルドの PDF も消す）、ほかのターゲットは書く。
機能を書体が持たなければ字形は変わらず、書き手の意図と違う PDF ができるので、黙って組まない。
InDesign も角括弧で示すだけで組むが、Golem は CI で組むので、報告しなければ誰も気付かない。

書体が機能を持つとは、その書体の GSUB か GPOS の機能の一覧（FeatureList）にそのタグがあることとする。
用字系と言語系を問わない。
機能を持っていても、範囲の字にその機能の置き換えがない場合（スモールキャップを持つ書体の漢字など）は、報告しない。
字ごとに置き換えの有無を調べると、和欧の混じった範囲で報告が増えるためである。

報告の単位は、同じ見た目の字の連なり（ラン）である。
ランの字が使う書体（和文の字は和文の書体、欧文の字は欧文の書体）のどれもが、ランの並びで有効な機能を持たないとき、その機能を報告する。
和文と欧文が混じったランで、欧文の書体だけがスモールキャップを持つ場合は報告しない。
止める機能（値 0）は、書体が持たなくても報告しない。
止めたい機能がないことは、書き手の意図どおりである。
Golem が足す機能（縦書きの役割の既定、カーニングの方式、`proportional-metrics`、約物の打ち消し、[ADR 0269](0269-superscript-and-subscript.md) の上付きと下付き）は、報告の対象にしない。

G08103 は、フォントのファイルと機能のタグの組ごとに一つにまとめる。
位置は、その機能を有効にした `style.toml` の値（配列の要素）のうち、ファイルの中で最初のものとし、`@style-def` だけが書いた場合はその行とする。
メッセージは `フォント <パス> に OpenType の機能 <tag> がありません` とし、事実に `font`、`feature`、`pdf-pages`（その機能のランが現れたページ）を持たせる。
並びはフォントのパス、タグの順とする。
コードの番号（G03124 と G08103）は、採択のときに、使われていない番号であり同じ時期の ADR と重ならないことを確かめて振り直した（「決めたことの記録」）。
HTML、EPUB、プレーンテキストのターゲットと、`golem check`、LSP は報告しない。
HTML と EPUB では字を描くのは読書環境であり、`golem check` と LSP は組版をしないためである。

合成のスモールキャップは作らない（「メンテナーが決めること」の 4）。
書体が `smcp` を持たなければ、G08103 を出し、元の字形で組む。

### HTML と EPUB

`cs-名前` と `ps-名前` の CSS に、`font-feature-settings` を一つだけ書く。
値は、そのスタイルの `based-on` の鎖の並びをつなぎ、タグごとに最後の値を残した並びを、`"smcp" 1, "liga" 0, "salt" 2` の形にしたものである。
`proportional-metrics` が真なら、`"palt" 1`（縦組みの本では `"vpal" 1`）を最後に加える。
今は `proportional-metrics` だけを書いているので、二つの `font-feature-settings` を書いて後ろが前を消すことのないよう、一つの宣言にまとめる。
`features` を書かないスタイルの CSS は変わらない。

CSS の `font-feature-settings` は、外側の要素の値に足されず、内側の要素の値で置き換わる。
そのため、入れ子にした文字スタイルと、段落スタイルの中の文字スタイルでは、HTML と EPUB の機能が PDF と違い、内側のスタイルの並びだけが当たる。
媒体のあいだのこの差は、`palt` を約物に当て分けられない差（[docs/adr/0053](0053-no-palt-on-jlreq-punctuation.md)）と同じく、仕様書に書いて受け入れる。
役割の `features` は、今と同じく CSS に書かない。

プレーンテキストは、`features` を使わない。

### 互換と IR

意味論 IR とプラグインの ABI は変わらない。
文字スタイルは名前で IR に入り、`features` は `style.toml` の中だけの値である。
`abiVersion` と CDDL は変えない。
`style.toml` のスキーマ（LSP の補完の表）に、文字スタイルと段落スタイルの `features` を加える。

役割の `features` の検査で、今まで組めていた本が G03124 で止まることがある。
読めない文字列は今も適用されていないので、直しても PDF は変わらない。

### パッケージの依存

golem-* のパッケージのあいだの依存（ライブラリとテスト）は変えない。
`Look` は golem-layout に、機能の検査は golem-project に、書体の機能の一覧を読む関数は golem-font に、報告は golem-typeset に置き、どれも今の依存の中で済む。

### データ構造

- golem-project の `CharStyleDef` と `ParaStyleDef` に `csFeatures :: ![Feature]` と `psFeatures :: ![Feature]` を加える。`Feature` は、タグ（4 字）と値（0 から 65535）の組であり、`style.toml` の位置を持つ。`FontRole` の `frFeatures` も `[Feature]` にする。
- `overChar` と `overPara` は、`features` だけ、上書きではなく元の並びの後ろにつなぐ。
- 正規の形の文字列への写像と、タグごとに最後の値を残す関数を golem-project に置く。HTML の CSS と PDF のシェイピングが同じ関数を使う。
- golem-layout の `Look` に `lkFeatures :: ![Text]`（正規の形）を加える。
- golem-font に、書体の GSUB と GPOS の機能の一覧にタグがあるかを返す関数を加える（HarfBuzz の `hb_ot_layout_collect_features` を、用字系と言語系を問わずに呼ぶ）。
- golem-font の `golem_font_shape` は、機能の数を受け取り、上限を持たない。

### 文書

- docs/specifications.md：「style.toml」の節の文字スタイルと段落スタイルのキーに `features` を加え、書き方、つなぎ方、並べ方、HTML と EPUB の CSS を書く。「フォント」の節に、役割の `features` の検査、機能の並びの順、約物と幅を変える機能、G08103 を書く。
- docs/diagnostics.md：G03124 と G08103 を加える。G03006 の「使わない」の一覧に G03124 を加える。
- docs/roadmap.md：v1.0.0 の「LaTeX との差を埋める項目」から「文字スタイルの OpenType の機能」を消す。ほかの項目から取り出した部分はない。
- 使い手のマニュアル：`manual/chapters/05-style.gm` と `manual/appendices/c-style.gm` に `features` を書き、`manual/appendices/f-indesign.gm` に InDesign の OpenType の機能のメニューとの対応を書き、`manual/appendices/h-roadmap.gm` から項目を消す。`manual/appendices/e-errors.gm` が diagnostics の一覧から作られていなければ、G03124 と G08103 を加える。
- README は、機能の一覧を持たないので変えない。docs/markup.md は記法を変えないので変えない。

## 実装しないこと

- 合成のスモールキャップ（「メンテナーが決めること」の 4）。
- InDesign の文字パネルの「大文字小文字」（すべて大文字、スモールキャップ）にあたる、字を書き換える欄。原稿の字を変えずに字形を選ぶのは OpenType の機能の役目であり、字そのものを変える欄は別の項目になる。
- 機能の値の上限の検査（`salt=7` の書体に代替の字が 3 つしかない場合など）。書体の機能の中を調べる必要があり、費用に見合わない。
- 字ごとの置き換えの有無による報告。
- 縦組みで `palt` を `vpal` に読み替えること。`features` は書いたとおりに渡す。
- 圏点の字に文字スタイルの機能を当てること。
- 可変フォントの軸（`wght` など）の指定。軸は機能ではなく、CFF2 の書体は PDF に埋め込めない（[golem-font ADR 0003](../golem-font/adr/0003-reject-cff2-fonts-in-pdf.md)）。
- HTML と EPUB で、入れ子の機能を外側から足し合わせること。
- `features` の値の補完（タグの一覧）を LSP に加えること。

## 不変条件

ここで「並び」は、ある字のシェイピングに渡す機能の並び（`shExtra` の前に `lkFeatures` を置いたものの前に役割の機能を置いたもの）である。

- **I1 計測と描画が同じ並びを使う**：どの原稿、どの字でも、行分割がその字の送りを測った `Shaping` と、描画がその字をシェイピングした `Shaping` は等しい。行分割の箱の幅と、描いたグリフの送りの和が一致する。
- **I2 並びの順**：どの字でも、並びは「役割、段落スタイルの鎖、文字スタイルの入れ子と鎖、Golem が足す機能」の順の部分列になる。JLReq の約物では、並びの中の `palt`、`vpal`、`halt`、`vhal`、`chws`、`vchw` の最後の値は、有効にされていれば必ず 0 である。
- **I3 タグごとに一つ**：`lkFeatures` のどのタグも一度だけ現れ、その値は、つないだ並びの中でそのタグの最後の値に等しい。
- **I4 正規の形の往復**：受け付けたすべての文字列 s について、正規の形を読み直した組は s を読んだ組に等しい。正規の形を正規の形にしても変わらない。
- **I5 読めない文字列はちょうど一つずつ報告する**：`features` の配列の各要素について、受け付けない要素ごとに G03124 がちょうど一つ出て、受け付ける要素には出ない。順は要素の順である。
- **I6 機能を書かない本は変わらない**：`features` を文字スタイルと段落スタイルに書かず、役割の `features` がすべて受け付ける形である本では、PDF、HTML、EPUB、プレーンテキストのバイト列と diagnostics が、この変更の前と一致する。
- **I7 止める機能は報告しない**：値 0 の機能だけを書いた本では、G08103 が出ない。
- **I8 書体にない機能は一度だけ報告する**：G08103 は、フォントのファイルと機能のタグの組ごとに高々一つであり、その組の機能を有効にしたランが本に一つでもあり、ランの書体のどれもその機能を持たないときに限り出る。
- **I9 機能の境で範囲が切れる**：一つのシェイピングの呼び出しに渡す文字列の字は、どれも同じ並びを持つ。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 配列 | 空、一つ、同じタグが二つ（`["smcp", "smcp"]`）、有効と無効（`["smcp", "-smcp"]`）、無効と有効 |
| 形 | `smcp`、`+smcp`、`-smcp`、`smcp=0`、`smcp=1`、`salt=2`、`salt=65535`、`salt=65536` |
| 読めない文字列 | 空の文字列、3 字（`smc`）、5 字（`smcpx`）、`smcp=`、`smcp=-1`、`kern[3:5]`、空白を含む、ASCII でない字 |
| 鎖と入れ子 | 鎖の長さ 0、1、2、入れ子の深さ 0、1、2、親が有効で子が無効 |
| 機能の数 | 合わせて 32、33（上限をなくしたことの確かめ） |
| 書体 | 機能を持つ、持たない、和文だけが持つ、欧文だけが持つ |
| ラン | 和文だけ、欧文だけ、和欧の混じり、縦組みの和文、回転する欧文、縦中横 |

## テスト設計

実装の前に書き、失敗することを確かめる。
テストの名前には、不変条件の番号を入れる。

### golem-project（`modules/golem-project/test/Main.hs`）

- I4：受け付ける形のすべてを列挙して読み、正規の形の往復を確かめる。`+smcp` が `smcp`、`smcp=0` が `-smcp`、`smcp=1` が `smcp` になる。
- I5：境界の表の読めない文字列のそれぞれを `[character-styles.x] features` に書くと、その要素の位置に G03124 が一つ出る。二つの誤りを書くと、要素の順に二つ出る。役割の `features` でも同じである。`@style-def character x features="smcp,"` が G03124 になる。
- I3：`based-on` の鎖が `["onum", "smcp"]` と `["-smcp", "salt=2"]` のとき、解決した並びが `["onum", "-smcp", "salt=2"]` になる。組み込みと同じ名前の表と、`@style-def` で重ねた定義でも、元の並びの後ろにつながる。
- `features` を書かない定義が空の並びになり、ほかの欄の読み方は変わらない。

### golem-layout（`modules/golem-layout/test/`）

- I9：`ab[style sc: cd]ef` の段落で、`cd` が `ab` と `ef` と別の箱になり、箱の `Look` の `lkFeatures` が `["smcp"]` になる。同じ並びの入れ子（`[style sc: a[style sc: b]]`）では、箱の境で範囲が切れない。

### golem-typeset（`modules/golem-typeset/test/`）

- I2：`shapingOf` の結果の並びが、役割、段落スタイル、文字スタイル、Golem の機能の順になる。`features = ["palt"]` と `kerning = "japanese-equal-width"` の文字スタイルの和文の字の並びが `-palt` で終わる。`features = ["halt"]` の文字スタイルの `「` の並びに `-halt` が足され、`あ` には足されない。`halt` を書かない本の `「` の並びは今と同じである。
- I1：Source Sans Pro（`modules/golem-font/test/fonts/` の書体）の役割で、`smcp` の文字スタイルを当てた段落を組み、行の箱の幅と、描画のグリフの送りの和が一致する。
- I8：`smcp` を Noto Serif JP（和文だけ）の役割の和文のランに当てると G08103 が一つ出て、同じ機能を二か所に書いても一つである。Source Sans Pro の欧文と Noto Serif JP の和文が混じったランでは出ない。dev では警告で PDF を書き、prod ではエラーで PDF を書かない。
- I7：`-smcp` だけを Noto Serif JP の役割に当てても G08103 が出ない。
- 機能の数：役割の機能と文字スタイルの機能を合わせて 33 個にした範囲で、33 個めの機能（`smcp`）でグリフが置き換わる。
- メモのキー：`salt=2` を含む `Shaping` のキーが範囲の中にあり、`fromShapingTextKey` で元に戻る（[ADR 0253](0253-memoise-run-shaping-and-shorten-the-memo-key.md) の I2 と I3）。

### golem-font（`modules/golem-font/test/`）

- 書体の機能の一覧を返す関数が、Source Sans Pro で `smcp` と `sups` を持ち、Source Han Sans の縮めた書体で `smcp` を持たないと返す。

### golem-html（`modules/golem-html/test/`）

- `features = ["smcp", "-liga"]` の文字スタイルの CSS が `font-feature-settings: "smcp" 1, "liga" 0` を一つだけ持つ。`proportional-metrics = true` も書くと、同じ宣言の最後に `"palt" 1` が付く。
- `features` を書かないスタイルの CSS は今と同じである。

### golem-driver（`modules/golem-driver/test/`）

- I6：`features` を書かない fixture の PDF、HTML、EPUB、プレーンテキストのバイト列と diagnostics が、変更の前に記録したものと一致する。

## トレードオフ

書体にない機能を、prod でエラーにした。
InDesign は角括弧で示して組み、LaTeX の `\textsc` は警告して組む。
Golem の本は CI で組まれ、人が組版の画面を見ないので、警告で済ませると、スモールキャップのつもりの略語が小文字のまま入稿されうる。
dev では警告にとどめ、書きかけの原稿は組めるようにした。
書体にない字（G08100）と同じ扱いである。

報告をランの単位にし、ランの書体のどれかが機能を持てば報告しないことにした。
和文と欧文が混じった範囲に `smcp` を当てると、和文の書体は `smcp` を持たないのがふつうなので、書体ごとに報告すると誤りでない指定に報告が出続ける。
その代わり、和文だけの範囲に欧文の機能を当てた誤りは報告するが、欧文の書体の機能が和文の範囲に適用されないことは、欧文が一字でも混じれば報告しない。

`based-on` の鎖で、`features` だけを上書きでなくつなぐことにした。
ほかの欄は子が親を置き換えるので、規則が一つ増える。
置き換えにすると、子のスタイルでスモールキャップを足すたびに、親の数字の形式を書き写す必要があり、InDesign の属性の振る舞いとも違う。
親の機能を消したい子は `-tag` で止めるので、「親の機能を当てず、役割の機能に戻す」ことはできない。

機能の書き方を、HarfBuzz の書き方の一部に狭めた。
`kern[3:5]` のような範囲は、Golem では文字スタイルの範囲で書けるので要らない。
`aalt=on` のような語の値を受け付けると、HTML の CSS に写すときに値を数に直す規則が要る。

HTML と EPUB では、入れ子の機能を足し合わせない。
CSS の変数で足し合わせる書き方もあるが、`style.css` の規則が入れ子の組み合わせの数だけ増える。
HTML と EPUB の見た目の確かめは致命的な崩れだけを見る方針であり、機能の欠けは致命的な崩れではない。

## メンテナーが決めること

1. **段落スタイルにも `features` を置くか**：推奨は置くことである。InDesign では OpenType の機能を段落スタイルも持ち、[docs/adr/0020](0020-indesign-character-features.md) は文字の属性を文字スタイルと段落スタイルの両方に置いた。表や本文の数字の形式は段落の単位で決めることが多い。
   - 退けた案は、文字スタイルだけに置くことである。表の全体の数字を等幅にするには、すべてのセルを文字スタイルで包むか、役割を増やすことになる。
2. **役割の `features` も検査するか**：推奨は、文字スタイルと同じ書き方の検査（G03124）と書体にない機能の報告（G08103）を、役割の `features` にもかけることである。読めない文字列を黙って捨てる今の振る舞いは、書き手の指定を黙って無視する。
   - 退けた案は、文字スタイルと段落スタイルだけを検査することである。同じ値の形が欄によって検査されたりされなかったりする。
3. **約物に当てない機能を広げるか**：推奨は、`palt` と `vpal` に加えて、`halt`、`vhal`、`chws`、`vchw` も JLReq の約物に当てないことである（役割の `features` の分も含む）。どれも約物の空きを書体の側で詰める機能で、Golem の空きと重なる。打ち消しは並びがその機能を有効にしているときだけ足すので、書かない本は変わらない。
   - 退けた案は、[docs/adr/0053](0053-no-palt-on-jlreq-punctuation.md) のとおり `palt` と `vpal` だけにすることである。`halt` を書いた本の約物の空きが二重に詰まる。
4. **合成のスモールキャップを作るか**：推奨は作らないことである。大文字を縮めた字は線が細くなり、小文字の高さと太さが合わない。スモールキャップを持つ書体を使えば正しく組め、持たない書体では G08103 が知らせる。
   - 退けた案は、InDesign のとおり、`smcp` を持たない書体で大文字を縮めて合成することである。縮める比（InDesign の環境設定の既定の値）を確かめられず、合成した字の見た目は良い既定にならない。合成は字を書き換える処理であり、`features` の意味（字形の選択）からも外れる。
5. **書体にない機能の重大度**：推奨は、dev で警告、prod でエラー（G08100 と同じ）である。
   - 退けた案の一つは、いつも警告にすることである。CI で組む本では警告が見落とされ、意図と違う PDF が入稿される。
   - もう一つは、いつもエラーにすることである。書きかけの原稿を、書体を決める前に組めなくなる。

## 決めたことの記録

2026-11-09 に、tett23 がすべて推奨のとおりに決めた。

1. 推奨のとおり、段落スタイルにも `features` を置く。
2. 推奨のとおり、役割の `features` にも書き方の検査（G03124）と書体にない機能の報告（G08103）をかける。
3. 推奨のとおり、`palt` と `vpal` に加えて `halt`、`vhal`、`chws`、`vchw` も JLReq の約物に当てない。
4. 推奨のとおり、合成のスモールキャップは作らない。
5. 書体にない機能は、推奨のとおり dev で警告、prod でエラーとする（G08100 と同じ）。

diagnostic のコードは、採択のときに、docs/diagnostics.md と origin/main のコードで使われていない番号であり、同じ時期の ADR と重ならないことを確かめて、G03124 と G08103 とした。
草案の仮の番号から振り直した。

## 参考文献

- [2026-10-17 の調査](../audits/2026-10-17-latex-gap-for-v1.md) の 15 と「所有者の決定」
- [ロードマップ](../roadmap.md) の「LaTeX との差を埋める項目」
- [仕様書の「フォント」](../specifications.md#フォント)、[仕様書の「style.toml」](../specifications.md#styletoml)
- [docs/adr/0005](0005-character-and-paragraph-styles.md)、[docs/adr/0020](0020-indesign-character-features.md)、[docs/adr/0053](0053-no-palt-on-jlreq-punctuation.md)、[docs/adr/0014](0014-in-file-settings.md)
- [ADR 0253](0253-memoise-run-shaping-and-shorten-the-memo-key.md)、[ADR 0255](0255-record-what-implementations-decided-on-2026-11-09.md)、[docs/adr/0081](0081-missing-glyphs-warn-in-build.md)
- [ADR 0269](0269-superscript-and-subscript.md)
- [golem-font ADR 0001](../golem-font/adr/0001-shaping-and-metrics.md)、[golem-font ADR 0003](../golem-font/adr/0003-reject-cff2-fonts-in-pdf.md)
- Adobe, InDesign User Guide, "Apply OpenType font attributes", https://helpx.adobe.com/indesign/desktop/fonts/opentype-font-attributes.html（本文は読めず、調査の抜粋による）
- Adobe, InDesign User Guide, "Format characters", https://helpx.adobe.com/ca/indesign/using/formatting-characters.html（同上）
- Microsoft, OpenType specification, "Registered features", https://learn.microsoft.com/en-us/typography/opentype/spec/featuretags
- HarfBuzz, `hb_feature_from_string`、`hb_ot_layout_collect_features`, https://harfbuzz.github.io/
- W3C, CSS Fonts Module Level 4, `font-feature-settings`, https://www.w3.org/TR/css-fonts-4/#font-feature-settings-prop
- CTAN, fontspec, https://ctan.org/pkg/fontspec
