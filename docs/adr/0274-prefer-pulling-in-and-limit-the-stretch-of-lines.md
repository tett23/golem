# ADR 0274: 行の調整で追い込みを優先し、行の伸びの上限を段落スタイルで決められるようにする

ステータス: 採択→プルリクエストの段で列挙する値と、R1 と R7 を調べる段は [ADR 0282](0282-record-what-the-implementations-of-adr-0274-and-0275-decided.md)、段に分けて置く行（`AdjustStaged`）での R5 の前半の読み方は [ADR 0278](0278-use-the-places-of-line-adjustment-in-the-order-of-jlreq.md)

## 文脈

### ロードマップの項目

[docs/roadmap.md](../roadmap.md) の v1.0.0 の「行分割と禁則」に、次の項目がある。

- **追い込みと追い出しの設定**：行末に収まらない字を前の行に追い込むか、次の行に追い出すかと、その優先の順を、段落スタイルで設定できるようにする（JLReq の 3.8）。改行できないコードや URL の前の行で字のあいだが大きく空く場合を、この設定で避けられるようにする（[golem-driver ADR 0037](../golem-driver/adr/0037-table-column-widths.md)）。

同じ節の「語句の泣き別れの禁止」は、この項目の後に扱うと書かれている。
語句を分けないために行の調整がどこまで崩れてよいかは、この ADR が決める欄で答えることになる（[ADR 0275](0275-keep-numbers-with-the-units-after-them.md)）。

### 今の行の調整

PDF の段落は、Knuth と Plass の方式で行に分ける（[golem-layout ADR 0001](../golem-layout/adr/0001-knuth-plass-line-breaking.md)）。
詰める余地と空ける余地は、どちらもグルーの伸びと縮みとして項目の並びに入っている。
既定のアキ量のセットでは、句読点と括弧の前後の二分アキは最小 0、和欧間の四分アキは最小八分であり、仮名と漢字のあいだのグルーは幅 0、伸び 1/10 em、縮み 0 である（[`defaultAkiSet`](https://github.com/tett23/golem/blob/9608953da3806ab63cb82abf091bfc1e04b76533/modules/golem-layout/src/Golem/Layout/Aki.hs#L89-L119)）。
つまり、約物の空きを詰めて字を前の行に入れること（追い込み）も、今の行分割はすでに候補として量っている。

量り方は、詰める行と空ける行で対称である。
不良度は、足りない幅か余る幅を、行の伸びか縮みの合計で割った比 r から、TeX と同じく約 100 |r|³ で求める（[`badness`](https://github.com/tett23/golem/blob/9608953da3806ab63cb82abf091bfc1e04b76533/modules/golem-layout/src/Golem/Layout/KnuthPlass.hs#L236-L246)、[`evaluate`](https://github.com/tett23/golem/blob/9608953da3806ab63cb82abf091bfc1e04b76533/modules/golem-layout/src/Golem/Layout/KnuthPlass.hs#L405-L437)）。
和文の行は伸びの合計が大きく、縮みの合計が小さい。
40 字の行で、次の行の頭の「。」を追い込むには二分を詰める必要があり、行の中の読点が一つなら縮みの合計も二分なので、r = −1、不良度は 100 になる。
同じ箇所で一字を追い出すと、39 か所の字のあいだの伸び 3.9 em で一字分を埋めるので、r はおよそ 0.26、不良度はおよそ 2 になる。
この計算のとおり、今の行分割は追い込める箇所でも追い出しを選びやすい。
ロードマップの「今は追い込みをせず」は、この偏りを指している（この計算は式から求めたもので、本を組んで数えてはいない）。

許容度の範囲に分割がなくなった位置では、最後の段階で収まらない箱を次の行へ送り出す（[`pushOut`](https://github.com/tett23/golem/blob/9608953da3806ab63cb82abf091bfc1e04b76533/modules/golem-layout/src/Golem/Layout/KnuthPlass.hs#L376-L387)）。
送り出した行は、伸びの許す限り字のあいだを空けて行長にそろえる（[docs/specifications.md](../specifications.md) の「行分割」）。
置き方は、行の比をすべてのグルーに同じ割合で掛ける（[`glueRatio`](https://github.com/tett23/golem/blob/9608953da3806ab63cb82abf091bfc1e04b76533/modules/golem-layout/src/Golem/Layout/KnuthPlass.hs#L548-L565)）。

### JLReq の行の調整

JLReq の 3.8.2 は、詰める処理（追込み）と空ける処理（追出し）を挙げ、通常は詰める処理を優先し、それで処理できない場合に空ける処理を行うとする。
理由として、ベタ組の箇所をできるだけ空けないという考え方を挙げている。
3.8.3 は詰める順（欧文間隔を四分まで、行末の約物の後ろ、中点類の前後、括弧類と読点の前後、和欧間を八分まで）を、3.8.4 は空ける順を定める。
3.8.4 の最後の段は、それまでの段で調整できなければ、分割禁止でない字間を均等に空けるとする（[golem-layout ADR 0045](../golem-layout/adr/0045-break-inline-code-after-hyphens-and-full-stops-to-avoid-loose-lines.md) の「InDesign と JLReq」）。
JLReq は、空ける量に上限を置かない。

InDesign の段落の禁則調整方式（追い込み優先、追い出し優先、追い出しのみ、調整量を優先）が、ここで扱う選択にあたると考えられる。
InDesign で組んで振る舞いを確かめてはいないので、この ADR は JLReq の記述に従う。

### 改行できないコードの前の空いた行

[golem-layout ADR 0045](../golem-layout/adr/0045-break-inline-code-after-hyphens-and-full-stops-to-avoid-loose-lines.md) は、本文の中のコードの `-` と `.` の後に改行の候補を足し、字間の空いた行を約 3 割減らした。
それでも、和文の字のあいだが四分を超える行（r > 2.5）は、利用者のマニュアルで約 163、開発者のマニュアルで約 54 残る見込みであり、どれも最後の段階で送り出した行であった。
こうした行では、追い込もうにも縮みが足りない。
追い込みを優先しても、改行できないコードの前の行は空いたまま残る。

この ADR の後に空いた行を避ける手段は、行の伸びに上限を置き、上限を超える分を行末に残すことである。
開発者のマニュアルの表のセル（「超越関数を持たない。sp と有理数。」の行）は、セルの段落スタイル（[ADR 0262](0262-table-numbers-captions-column-widths-and-cell-styles.md)）で上限を書けば、字のあいだを大きく空けずに組める。
その行が今どれだけ空いているかは、この ADR の作成では組み直して測っていない。

## 実装すること

### 1. 段落スタイルの欄 `line-adjustment`

段落スタイルに、行の調整の優先を決める欄 `line-adjustment` を足す。
取れる値は二つである。

- **`"pull-in-first"`**：追い込みを優先する（JLReq の 3.8.2 の通常の方法）。既定とする。
- **`"balanced"`**：今の振る舞い。詰める行と空ける行を同じ式で量る。

`"pull-in-first"` では、行の不良度の求め方を一か所だけ変える。
足りない幅が負（行を縮める）で、その量がグルーの縮みの合計以下なら、不良度を 0 とし、適合度の分類を decent（2）とする。
グルーの縮みの合計には、欧文の字幅の圧縮（[golem-layout ADR 0005](../golem-layout/adr/0005-microtypography.md)）を含めない。
グルーの縮みだけでは足りず、字幅の圧縮を足して収まる行は、今のとおり TeX の式で量る。
ほかの行（伸ばす行、ちょうどの行、収まらない行）の量り方は変えない。

これで、追い込める箇所では、詰める行の罰点が行の罰点の最小（`\linepenalty` に当たる値の二乗）になり、空ける行より選ばれやすくなる。
詰める量の上限は今のとおりアキ量のセットの最小が決めるので、詰めすぎた行はできない。
段落の全体で罰点を最小にする方式は変えないので、詰めた行の後の行が大きく空く場合は、追い出しを選ぶことがある。
JLReq の「優先」を、一行ずつ前から決める方式ではなく、罰点の差として入れる。

`golem-layout` の `Params` に、この選択を表す欄（`pPullInFirst :: Bool`）を足す。
`defaultParams` は今のとおり `False` とし、段落スタイルから値を渡す箇所で既定の `"pull-in-first"` を当てる。

### 2. 段落スタイルの欄 `stretch-limit`

段落スタイルに、行のグルーを伸ばす比の上限を決める欄 `stretch-limit` を足す。
値は 0 以上の整数で、千分率で書く（`expansion` の `limit` と同じ）。
書かなければ上限を置かない（今のとおり）。

上限 m を書いた段落では、行を置くときのグルーの比を m/1000 で頭打ちにする。
頭打ちにした行は、行長に足りない分を行末に残し、行頭にそろう。
縦組みでは行の頭（上）にそろう。
行分割の判定（不良度、罰点、どの段階で決まったか、送り出し）は変えない。
上限は、決まった分割の行を置くときにだけ適用される。

既定のアキ量のセットでの値の目安は次のとおりである。

| `stretch-limit` | 仮名と漢字のあいだ | 和欧間（最適の四分に足す量） | JLReq の 3.8.4 での位置 |
| --- | --- | --- | --- |
| 1000 | 1/10 em まで | 1/4 em まで | 伸びの最大値 |
| 2500 | 1/4 em まで | 5/8 em まで | 3 の段の上限（字間を四分まで） |
| 書かない | 上限なし | 上限なし | 4 の段（分割禁止でない字間を均等に空ける） |

`Line` に、頭打ちの比を持つ欄（`lineStretchLimit :: Maybe Rational`）を足し、`mkLine` が `Params` の値を写す。
`glueRatio` は、行を伸ばすときの比をこの値で頭打ちにする。
`placeLine` は `glueRatio` を使うので、行の項目は行頭から詰めて置かれ、残りは最後の項目の後に残る。
両端を揃えない段落（[docs/adr/0189](0189-paragraph-alignment-spacing-and-end-indent.md)）の行はグルーが伸びないので、この欄は出力を変えない。
段落の最後の行は、段落の終わりのグルーが伸びを受け持つので、`align = "fully-justified"` の段落の最後の行のほかでは出力を変えない。

### 3. 欄を当てる組版

二つの欄は、アキ量のセット（`aki-set`）と同じ段落スタイルから引く（[`akiSetOf`](https://github.com/tett23/golem/blob/9608953da3806ab63cb82abf091bfc1e04b76533/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L1210-L1211)）。

- 本文の段落と `@style` を付けた段落：その段落スタイル。
- 図版のキャプションと傍注の本文：`caption` と `sidenote`。
- 表のセル：セルの段落スタイル（`@style` を付けた表はその段落スタイル、ほかは `table`）。
- 目次の項目：その階層の段落スタイル `toc-1` から `toc-6`（[ADR 0264](0264-paragraph-styles-for-toc-entries.md)）。
- 脚注と章末の注の本文、定義リストと箇条書きの段落：今のアキ量のセットと同じく `body`。

`based-on` で引き継ぎ、`code` のほかの組み込みの段落スタイルに書ける。
`@style-def` でも書ける。
`code` は書けるキーを、書体と大きさと背景と余白の四つと、枠の五つのキー（`border`、`border-width`、`border-style`、`border-sides`、`border-radius`。[ADR 0271](0271-paragraph-backgrounds-and-borders.md)）に限っており、ほかのキーは G03006 とする（[docs/specifications.md](../specifications.md)）。
コードブロックの行の折り返しは行分割の方式が別なので、二つの欄も今の規則のとおり `code` には書けない。

### 4. 値の検査

`line-adjustment` が二つの値のどちらでもないとき、`stretch-limit` が負の数か整数でないときは、その値の位置で G03006 とする。
新しいコードは足さない。
G03006 は `style.toml` の値の誤りのコードであり、`explicit-hyphen-penalty` の範囲の誤りと同じ原因の分類である。

### 5. HTML と EPUB

HTML と EPUB には書き出さない。
CSS に、行の調整の優先と伸びの上限を指定する性質はなく、ブラウザーの両端揃えは処理系が決める。

### 6. 文書

- [docs/specifications.md](../specifications.md) の段落スタイルのキーの一覧に二つの欄を足し、「行分割」の節に、追い込みを優先する量り方と、伸びの上限の置き方を書く。表のセル、キャプション、傍注に当てる欄の一覧にも足す。
- 「行分割」の節の「送り出した行は伸びの許すかぎり字間を空けて行長にそろえる」に、`stretch-limit` を書いた段落では上限を超える分を行末に残すことを足す。
- [TeX と InDesign との差異](../differences-from-tex-and-indesign.md) に、追い込みの優先を罰点の差として入れたこと、InDesign の禁則調整方式を確かめていないことを書く。
- [docs/roadmap.md](../roadmap.md) の v1.0.0 の「行分割と禁則」から「**追い込みと追い出しの設定**」の行を消す。「語句の泣き別れの禁止」の「『追い込みと追い出しの設定』の後に扱う」は、[ADR 0275](0275-keep-numbers-with-the-units-after-them.md) が扱う。
- JLReq の 3.8.3 と 3.8.4 の調整の順（「メンテナーが決めること」の 7）は、この ADR を採択したプルリクエストがロードマップの v1.0.0 の「行分割と禁則」に足した項目のまま残す。別の ADR で決める。

### 7. 出力の変化

既定を `"pull-in-first"` にするので、両端を揃える段落の多くの出力が変わる。
二つのマニュアル、golden、complex fixture、kanikosen、Nightmare Abbey の PDF と決定性のハッシュ、`scripts/visual/pages/` の参照が変わる。
実装のプルリクエストで、[golem-layout ADR 0045](../golem-layout/adr/0045-break-inline-code-after-hyphens-and-full-stops-to-avoid-loose-lines.md) の「頻度」と同じ数え方で、二つのマニュアルの r > 1、r > 2.5、r < 0 の行の数、ページの数、画像の変わったページの数を、この ADR の前と後で数えて説明に書く。
英語の本（Nightmare Abbey）の行も同じく数える。

## 実装しないこと

- **JLReq の 3.8.3 と 3.8.4 の詰める順と空ける順**：今は、行の比をすべてのグルーに同じ割合で掛ける。順に従うには、グルーの種類（約物の空き、和欧間、欧文間隔、字間）を項目に持たせ、段ごとに比を求める置き方が要る（「メンテナーが決めること」の 7）。v1.0.0 で、別の ADR で扱う（「決めたことの記録」の 7）。
- **追い出し優先と追い出しのみ**：追い出しのみは、アキ量のセットの最小を最適と同じにすれば今でも書ける。追い出し優先は、伸ばす行の不良度を 0 にすると字の少ない行に罰点がかからなくなるので、入れない（「メンテナーが決めること」の 1）。
- **上限を超えた行の報告**：上限は書き手が決めた値なので、頭打ちにした行を diagnostic で報告しない（「メンテナーが決めること」の 6）。
- **上限を考えた分割の選び直し**：頭打ちにした行の不良度を量り直さない。分割の選び方と置き方を分け、上限が分割を変えないようにする。
- **ぶら下げ組の扱い**：`hanging-punctuation` は今のとおり `[composition]` の欄とし、段落スタイルに移さない。
- **HTML と EPUB**：5 のとおり。

## 不変条件

「行」は `brLines` の各行、W は行の幅とする。
「グルーの縮み」は行のグルーの縮みの合計、「詰める行」は、足りない幅が負で、その量がグルーの縮み以下の行とする。
p は `line-adjustment` の値、m は `stretch-limit` の値（ない場合は上限なし）とする。

- **R1 balanced は今と同じ**：p が `"balanced"` で m がない入力の `Breaks` と、各行の `placeLine` は、この ADR の前と同じである。
- **R2 追い込みの量り方**：p が `"pull-in-first"` の入力で、`brPass` が 1 か 2 なら、`brDemerits` は、詰める行の不良度を 0、適合度を decent とした量り方で、同じ段階の許容度で作れる分割のすべてのうちの罰点の和の最小に等しい（[ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md) の L7 を、この量り方に広げたもの）。
- **R3 一行に詰められる段落**：p が `"pull-in-first"` で、負の罰点を含まない入力で、段落の全体が一行にグルーの縮みだけで収まるなら、`brLines` は一行である。
- **R4 詰める行は量り方だけが変わる**：p を `"balanced"` から `"pull-in-first"` に替えても、`breakParagraph` に渡す項目の並びは変わらない。
- **R5 伸びの上限**：m のある入力で、はみ出していない行の `glueRatio` は m/1000 以下である。m がない入力と同じ分割の行で、上限のない比が m/1000 以下の行の `placeLine` は、m がない入力と同じである。
- **R6 頭打ちの行は行頭にそろう**：上限のない比が m/1000 を超える行は、最初の項目の位置が m がない入力と同じで、最後の項目の終わりが W より前にある。行の項目の終わりは、行頭から自然な幅と、伸びの合計の m/1000 倍を足した位置である（丸めの 1 sp を許す）。
- **R7 上限は分割を変えない**：m を変えても、`brPositions`、`brDemerits`、`brPass` は変わらない。
- **R8 欄の検査**：`line-adjustment` と `stretch-limit` の誤った値のそれぞれに、G03006 がちょうど一つ出る。正しい値には diagnostic を出さない。`code` に書いた値には、今の規則のとおり G03006 がちょうど一つ出る。
- **R9 HTML と EPUB**：二つの欄をどう書いても、HTML と EPUB の出力のバイト列は、欄を書かない入力と同じである。

[ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md) の L1 から L13 との関わりは次のとおりである。

- L6（両端揃え）は、R6 の行を除いて成り立つ。R6 の行は、L6 の例外として述語に足す。
- L7（最適）は、p が `"pull-in-first"` の入力では R2 に置き換える。
- L5 は変わらない。上限は行を短くするだけで、行長を超えさせない。
- ほかの不変条件は、量り方と置き方だけが変わるので、そのまま成り立つ。

[golem-layout ADR 0032](../golem-layout/adr/0032-drop-word-spaces-before-the-end-of-a-paragraph.md) の T1、[golem-layout ADR 0034](../golem-layout/adr/0034-line-breaks-between-japanese-characters-in-inline-code.md) の C1 から C8、[golem-layout ADR 0045](../golem-layout/adr/0045-break-inline-code-after-hyphens-and-full-stops-to-avoid-loose-lines.md) の J1 から J7 は、項目の並びを変えない（R4）ので、そのまま成り立つ。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 追い込みに要る縮み | 0、グルーの縮みより 1 sp 少ない、ちょうどグルーの縮み、1 sp 多い（字幅の圧縮の有無） |
| 行の約物 | なし、読点一つ、括弧の対、中点、和欧間 |
| 罰点 | すべて 0 以上、負の罰点（`explicit-hyphen-penalty = -100`）を含む |
| `stretch-limit` | 書かない、0、1000、2500、上限のない比にちょうど等しい値、それより 1 小さい値 |
| 行の位置 | 最初の行、中ほどの行、最後の行（`align` が `"fully-justified"` と既定） |
| 段落の揃え | 両端揃え、行頭揃え（[docs/adr/0189](0189-paragraph-alignment-spacing-and-end-indent.md)） |
| 組方向 | 横組み、縦組み |
| 段階 | 1、2、送り出し（4）、はみ出す行 |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
テストの名前には、R1 から R9 の番号を入れる。

- **R1**：[ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md) の列挙の入力のすべてで、`"balanced"` と上限なしの出力が、この ADR の前の実装の出力と同じであること。実装の最初に、今の実装の出力を列挙の部品 2 個まで記録して比べる。
- **R2**：`KnuthPlassBrute` の素朴な探索に、詰める行の不良度を 0 にした量り方を足し、列挙の入力で `brDemerits` と比べること。
- **R3**：4 字の行に「あいう、えお」（読点の後の二分を詰めれば 4 字に収まる幅の送りの表）を組み、`"pull-in-first"` で一行、`"balanced"` で二行になること。今の実装では二行になるので失敗する。字の送りと行の幅は実装の最初に決め、今の実装で失敗することを確かめる。
- **R4**：同じ段落を二つの値で組み、`composeInlines` の項目の並びが等しいこと。
- **R5**：上限 1000 の段落で、上限のない比が 1/2 の行と 3 の行を作り、前の行の `placeLine` が上限のない入力と同じで、後の行の `glueRatio` が 1 であること。今は欄がないので失敗する。
- **R6**：R5 の後の行の最後の項目の終わりが、行頭から自然な幅と伸びの合計を足した位置にあり、W より前にあること。縦組みでも同じであること。
- **R7**：列挙の入力のすべてで、上限を 0、1000、2500 にして組み、`brPositions`、`brDemerits`、`brPass` が上限なしと同じであること。
- **R8**：`line-adjustment = "fast"`、`stretch-limit = -1`、`stretch-limit = 2.5` がそれぞれ G03006 を一つ出し、`[paragraph-styles.code]` の `stretch-limit = 1000` が G03006 を一つ出すこと。`style.toml` と `@style-def` の両方で確かめる。
- **R9**：二つの欄を書いた本と書かない本の HTML と EPUB のバイト列が同じであること。
- **列挙**：[ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md) の組み方の環境に、`line-adjustment` の二つの値と、`stretch-limit` の三つの値（なし、0、2500）を足す。プルリクエストの段で部品 2 個までの時間を測り、範囲ごとの予算 10 秒（[ADR 0208](0208-widen-lightweight-formal-methods.md) の 4）を超えるなら、`stretch-limit` は毎晩のジョブの段だけで足す。
- **二つのマニュアルの数え直し**：実装の「7. 出力の変化」の数え方で数え、説明に書く。手で確かめる項目であり、自動のテストにはしない。

## トレードオフ

追い込みを優先すると、英語の段落も詰め気味に組まれる。
JLReq の 3.8.3 は欧文間隔を四分まで詰めることを最初の段に置くので、和文の本の中の欧文としては規則どおりである。
英語の本では、TeX が許容度の範囲で空ける行と詰める行を同じに量るのと違い、語間が狭い行が増えうる。
その本では、段落スタイルに `"balanced"` を書けば今の組み方に戻る。

罰点の差として入れたので、「追い込める箇所では必ず追い込む」ことは保証しない。
詰めた行の後の行が大きく空くなら、段落の全体の罰点で追い出しを選ぶ。
一行ずつ前から決める方式なら保証できるが、Knuth と Plass の方式の利点（後の行を見て前の行を決める）を手放すことになる。

`stretch-limit` の比は、すべてのグルーに同じ割合で適用される。
JLReq の 3.8.4 は、和欧間を二分まで、字間を四分まで、のように種類ごとに上限を決める。
比の上限 2500 では、字間は四分までになるが、和欧間は 5/8 em まで空く。
種類ごとの上限は、7 の調整の順と同じく、グルーの種類を項目に持たせてから入れることになる。

上限で頭打ちにした行は、両端揃えの段落の中で行末がそろわない。
JLReq の 3.8.1 は、書籍の本文では行末をそろえることを原則とする。
既定では上限を置かず、書き手が欄を書いた段落でだけ、この原則から外れる。

## メンテナーが決めること

1. **`line-adjustment` の既定**：推奨は `"pull-in-first"` である。JLReq の 3.8.2 が通常の方法とし、既定のままでよい組版を得ることを優先する。
   - 退けた案の一つは、既定を `"balanced"`（今の振る舞い）にすることである。出力は変わらないが、既定の組版が JLReq の優先と逆の向きに偏ったまま残る。
   - もう一つは、追い出し優先（`"push-out-first"`）も値に加えることである。伸ばす行の不良度を 0 にすると、字の少ない行が罰点なしで選ばれる。追い出しのみは、アキ量のセットの最小を最適と同じにすれば書ける。
2. **詰める行の量り方**：推奨は、グルーの縮みだけで収まる行の不良度を 0 にすることである。罰点の差がいちばん大きくなり、規則も一行で書ける。
   - 退けた案の一つは、詰める行の不良度に 1/2 のような係数を掛けることである。係数の値に根拠がない。
   - もう一つは、各行を前から一行ずつ、詰めて収まるなら詰めると決めることである。段落の全体の最適を手放す。
3. **欧文間隔の縮みも 0 にするか**：推奨は、和文の約物の空きと欧文間隔を区別せず、グルーの縮みのすべてを同じに扱うことである。JLReq の 3.8.3 は欧文間隔を詰める処理の最初の段に置く。
   - 退けた案は、アキ量のセットの空きの縮みだけを 0 にすることである。グルーに種類を持たせる変更が要り、英語の段落の組み方は変えずに済むが、JLReq の段の順とも合わない。
4. **字幅の圧縮の扱い**：推奨は、字幅の圧縮を 0 の量り方に含めず、今のとおり TeX の式で量ることである。字幅の圧縮は JLReq の詰める処理にない、欧文の微調整である。
   - 退けた案は、圧縮も含めることである。`expansion` を書いた本で、字を細くする行が罰点なしで選ばれる。
5. **`stretch-limit` の単位と既定**：推奨は、グルーの比の千分率の整数とし、既定は上限なしとすることである。`expansion` と同じく整数で書け、比較が正確である。既定の上限なしは、JLReq の 3.8.4 の最後の段（均等に空ける）のとおりである。
   - 退けた案の一つは、字間の空きの長さ（`"0.25zw"`）で書くことである。グルーの伸びは字の組ごとにアキ量のセットで変わるので、一つの長さから比を決められない。
   - もう一つは、既定を 2500（JLReq の 3 の段の上限）にすることである。両端揃えの本文で、行末のそろわない行が既定で出る。
6. **上限を超えた行の残りの置き場と報告**：推奨は、残りを行末に置き（行頭揃え）、報告しないことである。上限は書き手が書いた値であり、その結果を警告にすると、マニュアルのように警告なしで組む本で欄を使えない。
   - 退けた案の一つは、残りを行の両端に分ける（中央揃え）ことである。前後の行と行頭がそろわない。
   - もう一つは、頭打ちにした行ごとに notice を出すことである。
7. **JLReq の詰める順と空ける順**：推奨は、この ADR では入れず、ロードマップの v1.x に「行の調整の順」として足すことである。グルーの種類を項目に持たせ、段ごとに比を求める置き方が要り、行分割の項目の型（`Item`）が変わる。
   - 退けた案は、この ADR で入れることである。追い込みの優先と、置き方の変更の二つの大きな変更が一つの ADR に入る。

## 決めたことの記録

2026-11-10 に、tett23 が次のとおり決めた。
7 のほかは推奨のとおりである。

1. `line-adjustment` の既定は、推奨のとおり `"pull-in-first"` とする。
2. 詰める行は、推奨のとおりグルーの縮みだけで収まる行の不良度を 0 にして量る。
3. 欧文間隔の縮みも、推奨のとおり和文の約物の空きと区別せずに扱う。
4. 字幅の圧縮は、推奨のとおり 0 の量り方に含めず、今のとおり TeX の式で量る。
5. `stretch-limit` は、推奨のとおりグルーの比の千分率の整数とし、既定は上限なしとする。
6. 上限を超えた行の残りは、推奨のとおり行末に置き、報告しない。
7. JLReq の 3.8.3 と 3.8.4 の詰める順と空ける順は、推奨と違い、v1.x に回さず v1.0.0 で扱う。扱うのはこの ADR ではなく、別の ADR である。この ADR の範囲は変えない。採択のプルリクエストで、ロードマップの v1.0.0 の「行分割と禁則」に、別の ADR で決める項目として足した。推奨の v1.x の項目は足さない。

採択のときに、草案の後に origin/main に入った ADR に合わせて二か所を直した。
「3. 欄を当てる組版」に、目次の項目の段落スタイル（[ADR 0264](0264-paragraph-styles-for-toc-entries.md)）を足した。
`code` に書けるキーに、枠の五つのキー（[ADR 0271](0271-paragraph-backgrounds-and-borders.md)）を足した。

## 参考文献

- [golem-layout ADR 0001](../golem-layout/adr/0001-knuth-plass-line-breaking.md)、[golem-layout ADR 0005](../golem-layout/adr/0005-microtypography.md)、[golem-layout ADR 0032](../golem-layout/adr/0032-drop-word-spaces-before-the-end-of-a-paragraph.md)、[golem-layout ADR 0034](../golem-layout/adr/0034-line-breaks-between-japanese-characters-in-inline-code.md)、[golem-layout ADR 0045](../golem-layout/adr/0045-break-inline-code-after-hyphens-and-full-stops-to-avoid-loose-lines.md)、[golem-driver ADR 0037](../golem-driver/adr/0037-table-column-widths.md)
- [ADR 0189](0189-paragraph-alignment-spacing-and-end-indent.md)、[ADR 0208](0208-widen-lightweight-formal-methods.md)、[ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md)、[ADR 0262](0262-table-numbers-captions-column-widths-and-cell-styles.md)、[ADR 0264](0264-paragraph-styles-for-toc-entries.md)、[ADR 0271](0271-paragraph-backgrounds-and-borders.md)、[ADR 0275](0275-keep-numbers-with-the-units-after-them.md)
- W3C. Requirements for Japanese Text Layout (JLReq). https://www.w3.org/TR/jlreq/（3.8.1 行の調整処理の必要性、3.8.2 詰める処理と空ける処理、3.8.3 詰める処理の優先順位、3.8.4 空ける処理の優先順位）。w3c/jlreq の `index.html`（`43942474`）を 2026-11-10 に読んだ。
- Donald E. Knuth, Michael F. Plass. "Breaking Paragraphs into Lines". Software: Practice and Experience 11(11), 1981.
- InDesign の段落の禁則調整方式は、Golem の開発の環境で動かせないので確かめていない。
