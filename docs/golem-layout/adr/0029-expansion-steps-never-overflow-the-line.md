# ADR 0029: 字幅の伸縮の刻みで、行を行長の外に出さない

ステータス: 採択（未実装）

## 文脈

[docs/adr/0209](../../adr/0209-line-breaking-invariants-by-exhaustive-small-inputs.md) の列挙は、字幅の伸縮（`expansion`）で縮める行が行長からはみ出すことを見つけた（L5、L6）。
仕様書の「既知の不具合」の「字幅の伸縮の刻みで行長を超える行」である。
最も小さい例は、`protrusion` と `expansion = { limit = 20, step = 5 }` で 5 字の行に `hyphenation.` を組むもので、行は行長と突き出しの量の和を約 0.02 em 超える。
それでも `lineOverfull` は偽のままである。
テストの既知の不具合の一覧（[`lineBugs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/test/LineBreakInvariantsSpec.hs#L519-L524)）は、この形の入力を、部品 2 個までで 32、3 個までで 2,923 除いている。

### 行分割は伸縮を連続の量として数え、行を組むときに刻みへ切り捨てる

行分割の判定（`evaluate`）は、伸縮を受ける箱の幅の和に `limit` の千分率を掛けた量を、そのまま伸びと縮みに足す（[`expansionOf`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/src/Golem/Layout/KnuthPlass.hs#L420-L422)）。
この量は刻みを知らない。
行が収まるか（`overfull`）も、この連続の縮みで決める（[`KnuthPlass.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/src/Golem/Layout/KnuthPlass.hs#L452)）。

行を組むとき（`mkLine`）は、調整比に `limit` を掛けた値を、0 の側に刻みの整数倍へ切り捨てる（[`expansionStep`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/src/Golem/Layout/KnuthPlass.hs#L461-L469)）。
切り捨てた残りは、グルーが受け持つ（[`glueRatio`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/src/Golem/Layout/KnuthPlass.hs#L494-L511)）。
グルーの縮みの比は −1 で止まる。
縮めたい残りをグルーが受け持てないとき、つまり行にグルーがないか、グルーがもう縮みきっているとき、残りは行長の外に出る。

伸ばす向きでも切り捨ては起きるが、残りはグルーが伸びて受け持つ。
グルーの伸びの比には上限がないので、伸びるグルーがある行は行長にそろう。
伸びるグルーがない行は行長に足りないまま残り、行長の外には出ない（[docs/adr/0222](../../adr/0222-line-breaking-points-the-invariants-did-not-decide.md) の L6）。

### 刻みと限度が割り切れない設定

`limit` と `step` は、どちらも千分率の整数であり、`style.toml` の読み込みは範囲も割り切れるかも調べない（[`Style.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-project/src/Golem/Project/Style.hs#L1685)）。
`limit = 22, step = 5` では、刻みの整数倍で届く伸縮は 20 までだが、判定は 22 まで縮められるものとして行を作る。
この行も、刻みを丸める向きによらず、20 を超えては縮められない。

### [ADR 0210](../../adr/0210-warn-overfull-lines-in-build.md) との関係

[ADR 0210](../../adr/0210-warn-overfull-lines-in-build.md) は、はみ出しの量 `lineOverflow` を足し、正の行ごとに `golem build` で G07105 を出す。
その O1 は、量を max(0, N − Z − L) とし、Z に字形の圧縮を含める。
今の連続の縮みを Z に使えば、この ADR の例の行の `lineOverflow` は 0 になる。
描いた行は行長の外に出るのに、G07105 は出ない。
二つの ADR の数え方をそろえないと、O5（描いた行のはみ出しと G07105 が一対一）が成り立たない。

### 組み方の例

pdfTeX の字幅の伸縮（`\pdfadjustspacing`）は、フォントの拡大の刻みを持つ。
Golem の伸縮（[golem-layout ADR 0005](0005-microtypography.md)）はこれに倣ったが、刻みへの丸めの向きと、丸めの残りの扱いを pdfTeX の実装で確かめてはいない。
InDesign の字幅の調整（グリフの拡大と縮小）は刻みを持たない。
どちらに倣っても、行長の外に字を出す理由にはならない。

## 実装すること

### 1. 縮める向きは、刻みの整数倍に切り上げる

`mkLine` の伸縮を、次のとおりに決める。

- 伸ばす行（調整比が正）：今のとおり、調整比 × 限度を 0 の側に刻みの整数倍へ切り捨てる。残りはグルーが伸びて受け持つ。
- 縮める行（調整比が負）：調整比 × 限度の絶対値を、刻みの整数倍に切り上げる。

縮める行では、伸縮が連続の量で受け持つはずの分より多く縮めるので、グルーが縮む分は連続の量のときより少なくなる。
グルーの縮みの比は、行の調整比（−1 以上）を下回らず、行は行長に収まる。
切り上げで行に要る縮みの全体を超えたときは、超えた分をグルーが伸びて受け持つ。
伸びるグルーがない行は、超えた分だけ行長に足りなくなる。
足りない量は、刻み一つ分の伸縮（伸縮を受ける箱の幅 × `step` ÷ 1000）より小さい。

### 2. 判定に使う限度を、刻みで届く値にする

`evaluate` と `mkLine` が伸縮の限度として使う値を、`limit` を刻みの整数倍に切り捨てた値（`limit` div `step` × `step`）にする。
`step` が `limit` より大きい設定と、`step` が 0 以下の設定では、限度は 0 であり、伸縮しない（今の `expansionStep` の `stp <= 0` の枝と同じ）。
1 の切り上げは、この限度を超えない。

### 3. `lineOverfull` と [ADR 0210](../../adr/0210-warn-overfull-lines-in-build.md) の量

1 と 2 の後では、`lineOverfull` が偽の行は、刻みの整数倍の伸縮とグルーの縮みの比 −1 以内で行長に収まる。
[ADR 0210](../../adr/0210-warn-overfull-lines-in-build.md) の O1 の Z の「字形の圧縮」は、2 の限度で数える。
[ADR 0210](../../adr/0210-warn-overfull-lines-in-build.md) がこの ADR より先に入るなら、その実装の Z をこの ADR の実装で 2 の限度に改める。
後に入るなら、2 の限度で実装する。

### 4. テストの既知の不具合の一覧から消す

`lineBugs` から「字幅の伸縮の刻みで行長を超える行」と `shrunkWithoutGlue` を消す。

### 5. 不変条件の L5 と L6 の読み方

[docs/adr/0209](../../adr/0209-line-breaking-invariants-by-exhaustive-small-inputs.md) の L5 は変えない。
L6 の「判定しない」場合（伸びるグルーのない行が行長に足りない）は、[docs/adr/0222](../../adr/0222-line-breaking-points-the-invariants-did-not-decide.md) が決める。
この ADR は、そこに次の上限を足す。
伸びるグルーがなく、伸縮が限度に達していない行の足りない量は、刻み一つ分の伸縮より小さい。

### 6. 文書

- 仕様書の `[composition]` の `expansion` の段落に、「縮める行は刻みに切り上げ、伸ばす行は刻みに切り捨てる。限度は刻みの整数倍に切り捨てた値として使う」と、この ADR へのリンクを足す。
- 仕様書の「既知の不具合」から項目を消し、「行分割」の節の一覧の文を改める。
- ロードマップの「不変条件のテストで見つかった行分割の不具合」から、この項目を消す。

### 7. 出力の変化

リポジトリの本（二つのマニュアルと complex fixture）は、どれも `expansion` を書いていない。
PDF と `pages.json` が変わるのは、golem-layout のテストのうち伸縮を使うもの（`AlignSpec` など）だけの見込みである。
実装のプルリクエストで、golden と決定性のハッシュが変わらないことを確かめ、説明に書く。

## 実装しないこと

- **`limit` と `step` の値の検査**：負の値、`step` が `limit` より大きい値、`step` が 0 の値を `style.toml` の読み込みでエラーにするかは、この ADR では決めない。2 は、どの値でも行長の外に出さないことだけを決める。値の検査は、diagnostic のコードを足す別の ADR とする。
- **伸ばす向きの丸め**：今のとおり切り捨てる。伸びるグルーのない行が足りないまま残ることは、[docs/adr/0222](../../adr/0222-line-breaking-points-the-invariants-did-not-decide.md) で扱う。
- **伸縮を使う入力の L7**：[docs/adr/0209](../../adr/0209-line-breaking-invariants-by-exhaustive-small-inputs.md) のとおり調べない。

## 不変条件

行の幅を W、行末の突き出しの量を P、伸縮を受ける箱の幅の和を X とする。
`limit` を刻みの整数倍に切り捨てた値を M とする。

- **E1**：どの行でも、`lineExpansion` は `step` の整数倍で、絶対値は M 以下である。M が 0 なら `lineExpansion` は 0 である。
- **E2**：`lineOverfull` が偽の行は、`placeLine` で置いた最後の項目の終わりが W + P を超えない（丸めの 1 sp を許す）。
- **E3**：縮める行の `lineExpansion` の絶対値は、調整比 × M の絶対値を刻みの整数倍に切り上げた値（M を超えない）であり、その行の `glueRatio` は行の調整比以上である。
- **E4**：伸ばす行の `lineExpansion` は、調整比 × M を 0 の側に刻みの整数倍へ切り捨てた値である（今のとおり）。
- **E5**：`lineOverfull` が真であることと、伸縮 M とグルーの縮みのすべてを使っても行の自然な幅が W より長いことは、同値である。
- **E6**：伸びるグルーがなく、`lineOverfull` が偽で、|`lineExpansion`| が M より小さい最後でない行の終わりは、W + P − X × `step` ÷ 1000 より後ろにある。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| `limit` と `step` | 20 と 5、22 と 5（M = 20）、5 と 5、3 と 5（M = 0）、20 と 0 |
| 調整比 × M | 刻みの整数倍ちょうど、整数倍より 1 sp 分大きい、M ちょうど、−M ちょうど |
| 行のグルー | なし、縮むグルー一つ、縮みきったグルー |
| 伸縮を受ける箱 | なし、一つ、二つ |
| 突き出し | なし、行末のハイフン |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
テストの名前には、E1 から E6 の番号を入れる。

- 列挙：`lineBugs` から実装すること 4 の項目を消し、部品 2 個までのすべての入力のテストが、今の実装で L5 と L6 の違反を返して失敗することを確かめる。
- E2、E3：文脈の例（`hyphenation.`、5 字、`protrusion` と `limit = 20, step = 5`）で、行の終わりが W + P を超えないこと。縮むグルーのある行で、`glueRatio` が行の調整比以上であること。
- E1、E5：`limit = 22, step = 5` で、ちょうど 21 の縮みが要る段落が `lineOverfull` になり、20 で足りる段落が収まること。今は 21 でも収まるとするので失敗する。
- E1：`limit = 3, step = 5` と `step = 0` で、どの行も伸縮しないこと。
- E4：伸ばす行の伸縮が、この ADR の前と同じであること（`AlignSpec` の今のテストが変わらず通る）。
- E6：伸びるグルーのない一語の行で、足りない量が刻み一つ分より小さいこと。
- [ADR 0210](../../adr/0210-warn-overfull-lines-in-build.md) が先に入っていれば、E5 の段落で `lineOverflow` が正であり、2 の限度で数えることを確かめる。

## トレードオフ

縮める行を切り上げると、縮める行の字は前より少し細くなり、語間はその分だけ広がる。
リポジトリの本は伸縮を使わないので、見た目の回帰はない。
伸縮を使う本では、縮める行のすべてで PDF が変わる。

切り上げる代わりに、グルーが受け持てない行だけを切り上げる案もある。
変わる行は少ないが、丸めの向きが行のグルーの状態で変わり、規則を一文で書けない。
今の規則（切り捨て）のまま、はみ出しを `lineOverfull` にして知らせる案は、行長に収められる行を外に出し、そのうえで警告を出すことになる。

## メンテナーが決めること

1. **縮める行の丸めの向き**：推奨は、縮める行は刻みに切り上げ、伸ばす行は切り捨てることである。縮める行でグルーが縮む分は連続の量のときより多くならないので、行長の外に字を出す丸めがなくなる。規則を一文で書ける。
   - 退けた案の一つは、切り捨てたうえで、残りをグルーが受け持てない行だけを切り上げることである。変わる行は少ないが、丸めの向きが行のグルーの状態で変わり、述語と仕様書の文が二つの場合に分かれる。
   - 二つめは、最も近い刻みに丸めることである。縮める行の半分で、今と同じく残りが行長の外に出うる。
   - 三つめは、丸めを変えず、残りがはみ出す行を `lineOverfull` にして [ADR 0210](../../adr/0210-warn-overfull-lines-in-build.md) の G07105 で知らせることである。刻みを切り上げれば収まる行を外に出したうえで警告し、書き手には直す手段がない。
2. **刻みで届かない限度**：推奨は、`limit` を刻みの整数倍に切り捨てた値を、判定と組みの両方で限度に使うことである。判定が届かない縮みを当てにすると、1 の丸めをどう決めても行が収まらない。
   - 退けた案は、`limit` が `step` で割り切れない設定を、`style.toml` の読み込みでエラーにすることである。今の本を読めなくする変更であり、値の検査は diagnostic のコードを足す別の ADR で決める（「実装しないこと」）。
3. **[ADR 0210](../../adr/0210-warn-overfull-lines-in-build.md) の Z の数え方**：推奨は、2 の限度で数え、どちらの ADR が先に入っても、描いた行のはみ出しと `lineOverflow` を一致させることである。
   - 退けた案は、[ADR 0210](../../adr/0210-warn-overfull-lines-in-build.md) の O1 を今の連続の縮みのまま実装することである。2 の限度との差の分だけ、描いた行がはみ出しても G07105 が出ない。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-08、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [golem-layout ADR 0005](0005-microtypography.md)、[golem-layout ADR 0014](0014-protrusion-amount.md)、[golem-layout ADR 0028](0028-kinsoku-across-spaces-and-explicit-hyphens.md)
- [docs/adr/0209](../../adr/0209-line-breaking-invariants-by-exhaustive-small-inputs.md)、[docs/adr/0210](../../adr/0210-warn-overfull-lines-in-build.md)、[docs/adr/0222](../../adr/0222-line-breaking-points-the-invariants-did-not-decide.md)
- Hàn Thế Thành. "Micro-typographic extensions to the TeX typesetting system". Masaryk University Brno, 2000.
- [#655](https://github.com/tett23/golem/pull/655) の説明（最も小さい例と、固定した数）
