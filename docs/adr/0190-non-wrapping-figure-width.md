# ADR 0190: 回り込ませない図版の幅を `width` で指定する

ステータス: 採択

## 文脈

`@figure` の `width` は、今は回り込ませる図版（`wrap`）のためだけのキーである（[markup.md](../markup.md) の「図版」の節）。
回り込ませない図版は、PDF で段の行長にそろえ、段に収まらなければ縦横の比を保って縮める（[golem-driver ADR 0034](../golem-driver/adr/0034-fit-figures-to-column.md)）。
小さなアイコンも縦長のスクリーンショットも、行長まで引き伸ばされる。

それでも、回り込ませない図版に `width` を書くことはできる。
評価は `width` を文字列のまま意味論 IR の `Figure` の `figWidth` に入れ（[`Figure`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-doc/src/Golem/Doc/IR.hs#L221-L233)）、回り込ませない図版では値を検査しない（[`figureLayoutError`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-eval/src/Golem/Eval/File.hs#L1383-L1387)）。
PDF の `placeFigure` は、回り込ませない図版の行の方向の長さを段の行長（回した図版では枠の行長）に決め、`figWidth` を読まない（[`placeFigure`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L1495-L1501)）。
HTML と EPUB は `<img>` に大きさを書かない（[`Golem.Html`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-html/src/Golem/Html.hs#L461)）。
書き手が書いた値は、どの出力にも届かず、diagnostic も出ない。

ロードマップの v0.1.0-rc4 の「回り込ませない図版の幅」は、これを直す項目である（[docs/roadmap.md](../roadmap.md)）。
v2 の「図版とキャプションの拡張」の「回り込ませない図版の幅の指定」を先に取り出す。
根拠は [2026-10-17 の調査](../audits/2026-10-17-latex-gap-for-v1.md) の 4 である。
LaTeX は graphicx の `\includegraphics` の `width` で図版の大きさを決め、InDesign はフレームの大きさと内容の合わせ方で決める。

### 今の振る舞いの確かめ

`~/.local/bin/golem`（`golem --version` は `0.1.0-rc3`、2026-11-06 にビルドしたもの）で、横組み、A5、本文 10pt、一行 30 字の小さなプロジェクトを組んだ。
図版は fixture の `modules/golem-driver/test/fixtures/figures/images/diagram.svg`（横長の SVG）で、次の二つを置いた。

```
@figure images/diagram.svg alt="図" width=10zw
  図。

@figure images/diagram.svg alt="図" width=abc
  図。
```

`golem build`（PDF、HTML、EPUB、プレーンテキスト）は diagnostic を一つも出さずに終わった。
PDF の 1 ページを 50dpi の画像にして（`shem render`）見ると、二つの図版はどちらも行長いっぱいの幅で置かれていた。
HTML の `<img>` は、どちらも `src` と `alt` だけを持っていた。
`width=10zw` は無視され、寸法として読めない `width=abc` も通った。

### 回り込ませる図版の `width`

回り込ませる図版は、`width` を必須とし、行の方向の長さ（横組みでは幅、縦組みでは高さ）として読む。
`width` は `mm`、`pt`、`Q`、`H`、`in`、`zw` の寸法で書き、`zw` は本文の文字の大きさ（`[page.grid]` の `font-size`）を一字とする（[`parseDim`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-project/src/Golem/Project/Style.hs#L131-L149)、`placeFigure` の `dimToSp fs`）。
寸法として読めない値は、PDF を組むときに G07022 とする（[`placeFigure` の `errs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L1543-L1550)）。
G07022 は、脇の行の長さが本文の 8 字分に満たない場合も同じコードで報告する。

### 寄せ

[golem-driver ADR 0034](../golem-driver/adr/0034-fit-figures-to-column.md) は、段に収めるために縮めた図版を、段の二つの端のうち仕上がりの紙の端までの距離が短いほうの端に寄せる。
`imageRect` は、図版の行の方向の長さが縮める前の長さ（`pfFullAlong`）より短いときに、この規則で位置を決める（[`imageRect` と `nearerEnd`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L2222-L2247)）。
ロードマップは、`width` で短くした図版の寄せも、この規則を既定にするとした。

## 実装すること

### `width` の意味

回り込ませない図版の `width` を、回り込ませる図版と同じく、図版の行の方向の長さ（横組みでは幅、縦組みでは高さ）とする。
省けば、今のとおり段の行長とする。
`rotate=true` の図版では、枠の行の方向の長さとする（「メンテナーが決めること」の 5）。

### 書き方

`width` は、今の寸法（`mm`、`pt`、`Q`、`H`、`in`、`zw`）に加え、段の行長に対する割合（`%`）で書ける（「メンテナーが決めること」の 1）。

- `zw` は、今の回り込ませる図版と同じく、本文の文字の大きさを一字とする。
- `%` は、回り込ませない図版では段の行長、回した図版では枠の行長、回り込ませる図版では段の行長に対する割合である。`50%` は行長の半分である。数の書き方は寸法の数と同じ（整数か小数、符号なし）とする。
- `%` は、回り込ませる図版の `width` でも書ける。寸法を読む関数を一つにするためである。回り込ませる図版の脇の行の検査（G07022）は今のとおりである。

### 検査

`width` が寸法としても割合としても読めない場合と、値が 0 の場合は、評価で新しいエラーのコード G02133 とする（「メンテナーが決めること」の 2）。
メッセージは `図版の width が読めません。寸法（10zw、50mm など）か行長の割合（50% など）で書きます: <値>` とし、位置は `width` の引数とする。
回り込ませる図版も、回り込ませない図版も、回した図版も対象にする。
評価で報告するので、PDF のほか、HTML、EPUB、プレーンテキストのどれを組んでも、`golem check` でもエラーになる。
dev と prod の両方でエラーである。

回り込ませる図版で `width` が読めない場合は、今の G07022 に代えて G02133 で報告する。
G07022 には、脇の行の長さが本文の 8 字分に満たないという原因だけが残る。
一つのコードに違う原因をまとめないためである。
G07022 のメッセージの「寸法で書き、」は外す。

`100%` を超える割合と、段の行長より大きい寸法は、誤りとしない。
次の節の規則で段に収めて縮め、notice（G07039）で知らせる。

### 大きさ（PDF）

[golem-driver ADR 0034](../golem-driver/adr/0034-fit-figures-to-column.md) の「図版の大きさ」の手順 1 を、次のように改める。
手順 2 から 5 は変えない。

1. `along₀` を、`width` があればその長さ、なければ段の行長（回した図版では枠の行長 `Fm`）とする。`along₀` が段の行長（枠の行長）より大きければ、`along₁` を段の行長（枠の行長）、そうでなければ `along₀` とする。`across₀` は、`along₁` に画像の縦横の比を掛けた値とする。
2. 手順 3 と 4 の `along₀` を `along₁` と読み替えて、`across` の上限 `acrossMax` に収める。

縮めたかどうか（G07039 を出すか）は、最後の行の方向の長さ `along` が `along₀` より短いかで決める。
`width` を行長より大きく書いて行長に縮めた図版も、段の行の送りの方向に収めるために縮めた図版も、同じ G07039 で知らせる。
メッセージの割合 `r` は、今と同じく `along × 100 ÷ along₀` の切り捨てであり、書き手が書いた `width` に対する割合になる。
`rotate=true` の案内を足す条件は変えない。

縦横の比の計算は、今と同じく有理数で行い、sp に切り捨てる（[docs/adr/0002](0002-determinism.md)）。
`%` の長さは、`行長 × 割合 ÷ 100` を有理数で計算し、sp に切り捨てる。

### 寄せ（PDF）

行の方向の長さが段の行長より短い図版は、[golem-driver ADR 0034](../golem-driver/adr/0034-fit-figures-to-column.md) の「寄せ」の規則で、段の二つの端のうち紙の端までの距離が短いほうの端にそろえる（「メンテナーが決めること」の 4）。
縮めた図版と `width` で短くした図版を区別しない。
`imageRect` が比べる `pfFullAlong` は、`width` ではなく段の行長（回した図版では枠の行長）とする。
回り込ませる図版の位置（`wrap` の `start` と `end`）は変えない。

### キャプション（PDF）

キャプションは、今のとおり段の行長（回した図版では枠の行長）で、段の行の始まりから組む（「メンテナーが決めること」の 3）。
図版の幅には合わせない。

### 回り込ませる図版

回り込ませる図版の大きさと位置は変えない。
`width` が段の行長より大きい回り込ませる図版は、脇の行が残らないので、今のとおり G07022 である。

### HTML と EPUB

`width` を持つ図版の `<img>` に、`style` の属性で大きさを書く（「メンテナーが決めること」の 6）。
横組みの本では `width`、縦組みの本では `height` に書き、同じ向きの `max-width: 100%` か `max-height: 100%` を添える。
行長より大きい図版を、PDF と同じく行長に収めるためである。
長さは、`mm`、`pt`、`Q`、`H`、`in` を `pt` に換算し、`zw` を `em`、`%` を `%` にする。
`em` は `<figure>` の文字の大きさで解決し、本文の文字の大きさに当たる。
回り込ませる図版も、HTML と EPUB では回り込ませない図版として置くので、同じく `width` を書く。
`width` を持たない図版の `<img>` は変わらない。

### プレーンテキスト

プレーンテキストは図版を描かないので、変わらない。
G02133 は評価で出すので、プレーンテキストだけを組むビルドでも出る。

### 仕様書とマニュアル

[docs/specifications.md](../specifications.md) の「図版」の節の、回り込ませない図版の大きさの規則に `width` を加え、[markup.md](../markup.md) の「図版」の節に `width` の書き方（`%` を含む）と G02133 を書く。
[docs/diagnostics.md](../diagnostics.md) に G02133 を加え、G07022 と G07039 の説明を改める。
[golem-driver ADR 0034](../golem-driver/adr/0034-fit-figures-to-column.md) のステータスの行に、「図版の大きさ」の手順 1 をこの ADR が改めたことを書く。
[docs/roadmap.md](../roadmap.md) の項目を外し、v2 の「図版とキャプションの拡張」から「回り込ませない図版の幅の指定」を外す。

## 実装しないこと

- 図版の高さ（行の送りの方向の長さ）の指定（`\includegraphics` の `height`）と、拡大縮小の率（`scale`）の指定。
- 寄せを図版ごとに選ぶ引数（「メンテナーが決めること」の 4）。
- キャプションの行長を図版の幅に合わせること（「メンテナーが決めること」の 3）。v2 の「図版とキャプションの拡張」のキャプションの位置と揃えのまま残す。
- 行長より大きい図版を、段や版面の外に張り出して置くこと（v2 の「図版とキャプションの拡張」の、ページの端や塗り足しまで伸ばす図版）。
- 画像の画素の数から大きさを決めること（PNG の解像度の情報を読むなど）。
- `style.toml` に図版の既定の幅を書くこと。

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。

golem-eval のテストでは、次のことを確かめる。

- `width=abc`、`width=0zw`、`width=0%`、`width=-3zw`、`width=50` が、回り込ませない図版でも、回り込ませる図版でも、回した図版でも、 G02133 になり、位置が `width` の引数であること。
- `width=12zw`、`width=40mm`、`width=50%`、`width=150%` が誤りにならないこと。
- 回り込ませる図版の `width=abc` が、G07022 ではなく G02133 になること。

golem-driver のテストでは、PDF の図版の大きさと位置を確かめる。

- 横組みと縦組みで、`width=10zw` の回り込ませない図版の行の方向の長さが 10zw で、行の送りの方向の長さが縦横の比から求めた値であること。G07039 が出ないこと。
- `width=50%` の図版の行の方向の長さが、段の行長の半分（sp に切り捨て）であること。回した図版では枠の行長の半分であること。
- `width` を段の行長より大きく書いた図版が段の行長に縮められ、G07039 の割合が `width` に対する割合であること。
- `width` で短くした図版が、[golem-driver ADR 0034](../golem-driver/adr/0034-fit-figures-to-column.md) の寄せの規則のとおり、奇数ページと偶数ページで紙の端に近いほうの端に寄ること。段組みの左の段と右の段でも確かめる。
- `width` で短くした縦長の図版が、段の行の送りの方向に収まらないとき、さらに縮められて G07039 が出ること。
- キャプションの行が、`width` によらず段の行長で組まれること。
- 回り込ませる図版の `width=50%` が、行長の半分の除外領域になること。
- `width` を書かない図版の出力のバイト列が今と同じであること。

golem-html のテストでは、横組みの本の `<img>` に `width` と `max-width: 100%`、縦組みの本の `<img>` に `height` と `max-height: 100%` が書かれ、単位が換算されること、`width` を持たない図版の `<img>` が今と同じであることを確かめる。

決定性の検査が通ること、既存の fixture の出力が変わらないこと（`modules/golem-driver/test/fixtures` の `.gm` に `width` を持つ図版はない。2026-11-06 に `rg` で確かめた）を確かめる。
複雑な組版の fixture（ロードマップの「複雑な組版の fixture」）に、`width` を持つ回り込ませない図版を加え、見た目の回帰テストの参照に入れる。

## トレードオフ

`width` で短くした図版は、紙の端に近いほうの段の端に寄る。
縮めた図版の余りは小さいことが多いが、`width=50%` の図版では段の半分が空き、キャプションは段の行の始まりから組まれる。
左綴じの横組みでノドの余白が小口より小さい版面では、偶数ページの図版は右に寄り、キャプションは左から始まる。
LaTeX の `\centering` を使った図版の多くは中央に置かれるので、LaTeX から移る書き手には意外な置き方になりうる。
寄せの規則を一つにするというメンテナーの判断（[golem-driver ADR 0034](../golem-driver/adr/0034-fit-figures-to-column.md) の「メンテナーの判断」）とロードマップに従ったので、中央に置く引数は「メンテナーが決めること」の 4 に挙げる。

`width` が読めない値を評価のエラーにすると、今は組めている本が組めなくなることがある。
今の値は無視されていたので、エラーで止めても出力の意味は変わらず、書き手は値を直すか消すだけでよい。
回り込ませる図版の `width` の誤りのコードが G07022 から G02133 に変わるので、`G07022` を検査する CI は書き換えが要る。

使い手のマニュアルには、`wrap=end` と `width` を持つ図版が三つある（`manual/chapters/01-first-book.gm` に二つ、`06-output.gm` に一つ。2026-11-06 に `rg` で確かめた）。
この三つは、HTML と EPUB で `width` の大きさになり、今の、画像の本来の大きさのままの表示から変わる。
PDF は変わらない。

HTML と EPUB の `%` は、`<img>` の包含ブロック（`<figure>`）の幅に対する割合であり、PDF の段の行長とは基準が違う。
ブラウザーの `figure` の既定の余白（左右 40px）の分だけ、HTML の図版は小さくなる。

## 決めたことの記録

- **`width` で回り込ませない図版の幅を指定すること**（ロードマップ、v0.1.0-rc4 の「回り込ませない図版の幅」）：行長より大きい値は [golem-driver ADR 0034](../golem-driver/adr/0034-fit-figures-to-column.md) の段に収める規則で縮める。行の中の寄せは、その ADR の寄せ（紙の端に近いほうの段の端）を既定にする。
- **縮めた図版を必ず知らせること**（[golem-driver ADR 0034](../golem-driver/adr/0034-fit-figures-to-column.md) の「メンテナーの判断」）：利用者が気づけないことを Golem が黙って行うのが最も悪いので、縮めたら notice を出す。`width` を行長より大きく書いて縮めた場合も G07039 を出す根拠である。
- **すべての項目**（2026-11-07、メンテナー）：「問題なし」。「メンテナーが決めること」の 1 から 6 を、すべて推奨のとおりとした。

## メンテナーが決めること

すべて決めた（「決めたことの記録」）。

1. **`width` の単位**：決めた。推奨のとおり、今の寸法に、段の行長に対する割合（`%`）を加える（「決めたことの記録」）。LaTeX で最も多い書き方は `width=0.5\linewidth` のような行長に対する割合で、判型や版面を変えても図版と行長の比が保たれる。HTML の `%` にもそのまま写せる。退けた案は、今の寸法だけにする案である。判型を変えるたびに書き手が `width` を計算し直す必要がある。
2. **読めない `width` の diagnostic**：決めた。推奨のとおり、評価で新しいエラーのコードにし、回り込ませる図版の読めない `width` も G07022 からこのコードに移す（「決めたことの記録」）。どの出力を組んでも、`golem check` でも同じ誤りが出る。G07022 に残る原因は脇の行の長さの不足だけになる。退けた案の一つは、回り込ませない図版の読めない `width` も G07022 で報告する案である。違う原因を一つのコードにまとめたままになり、PDF を組まないビルドでは出ない。もう一つは、notice を出して `width` を無視する案で、書き手の値を黙って捨てる今の振る舞いを、知らせるだけで残すことになる。
3. **キャプションの行長**：決めた。推奨のとおり、[golem-driver ADR 0034](../golem-driver/adr/0034-fit-figures-to-column.md) と同じく、段の行長で段の行の始まりから組む（「決めたことの記録」）。縮めた図版と `width` で短くした図版の扱いが一つになる。退けた案は、図版の幅で組み、図版と同じ端に寄せる案である。図版と縦にそろって見えるが、細い図版ではキャプションの行が増え、段に収まる大きさの計算（手順 2 の `s`）が `width` に依存する。キャプションの位置と揃えは v2 の「図版とキャプションの拡張」の項目なので、そこで決める。
4. **寄せ**：決めた。推奨とロードマップのとおり、[golem-driver ADR 0034](../golem-driver/adr/0034-fit-figures-to-column.md) の寄せだけを使い、図版ごとに寄せを選ぶ引数を作らない（「決めたことの記録」）。後から引数を足しても、引数を書かない図版の出力は変わらないので、互換を壊さずに足せる。退けた案の一つは、`align=start|center|end` の引数を今加える案である。LaTeX の `\centering` に当たる置き方ができるが、記法と HTML の出力を広げる。もう一つは、`width` で短くした図版だけ既定を中央にする案で、縮めた図版と寄せの規則が二つになり、[golem-driver ADR 0034](../golem-driver/adr/0034-fit-figures-to-column.md) の「規則は一つのほうがよい」という判断に反する。
5. **回した図版の `width`**：決めた。推奨のとおり、枠の行長に対する長さとして当てる（「決めたことの記録」）。LaTeX の `sidewaysfigure` の中の `\includegraphics[width=...]` と同じく、回した図版も大きさを選べる。退けた案の一つは、`rotate=true` と `width` を両方書くと G02087 にする案である。回した図版を小さく置く手段がなくなる。もう一つは、回した図版では `width` を無視する案で、この ADR が直す「書いた値を黙って捨てる」振る舞いを残す。
6. **HTML と EPUB の書き方**：決めた。推奨のとおり、本の書字の方向で `width` か `height` を選び、`<img>` の `style` の属性に書く（「決めたことの記録」）。図版ごとに値が違うので、規則を CSS のファイルに集めるより属性のほうが単純であり、アキの `<span>` に `style` の属性を書く前例がある。物理的なプロパティは、論理的なプロパティより古い読書環境でも読まれると考えられる（確かめていない）。退けた案は、論理的なプロパティの `inline-size` と `max-inline-size` を書く案である。書字の方向で分ける処理が要らないが、EPUB の読書環境が読むかを確かめていない。

## 参考文献

- [2026-10-17 の LaTeX との差の調査](../audits/2026-10-17-latex-gap-for-v1.md) の 4。
- graphicx package（`\includegraphics` の `width`、`height`、`scale`、`keepaspectratio`）. https://ctan.org/pkg/graphicx
- Adobe, InDesign User Guide, "Fit objects to frames". https://helpx.adobe.com/indesign/desktop/add-graphics-and-media/manage-frames-and-objects/fit-object-to-frame.html
- W3C, CSS Box Sizing Module Level 3, `width`、`max-width`. https://www.w3.org/TR/css-sizing-3/
- [golem-driver ADR 0005](../golem-driver/adr/0005-pdf-wrapped-figures.md)、[golem-driver ADR 0016](../golem-driver/adr/0016-output-and-layout-diagnostic-codes.md)、[golem-driver ADR 0034](../golem-driver/adr/0034-fit-figures-to-column.md)、[golem-layout ADR 0004](../golem-layout/adr/0004-wrapped-figures.md)
