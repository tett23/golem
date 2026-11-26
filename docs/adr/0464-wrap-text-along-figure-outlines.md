# ADR 0464: 図版の輪郭を書き、輪郭に沿って本文を回り込ませる

Status: proposed

## 文脈

[Golem ADR 0382](0382-figure-extent-and-captions.md) は、回り込む図版の輪郭を指定できるようにし、行帯と輪郭の交差区間を本文幅から差し引くと決めた。
輪郭の処理にはパスの実装が要るので、0382 は輪郭の書き方と回り込みの求め方を後に回した。
[root ADR 0437](0437-paths-and-the-box-model.md) はパスの型と閉じたパスのテキストフレームを決め、図版の輪郭の書き方と輪郭に沿う回り込みは別の ADR で決めるとした。

メンテナーは、2026-11-26 に、この ADR を書くよう求めた。
この ADR は、図版の輪郭の書き方と、輪郭に沿う回り込みの行の幅の求め方を決める。

## 調査した事項

origin/main（[c034510](https://github.com/tett23/golem/commit/c034510e33476f4af68ba22636f5ab6ef8463f0a)）で、次のことを確かめた。
根拠の行は、調べを受け持ったエージェントが `git show` と `git grep` で返したものと、メインが `git show` で読んだものである。

- 回り込む図版は、`@figure` に `wrap=start` か `wrap=end` を書く（[File.hs#L2390-L2406](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-eval/src/Golem/Eval/File.hs#L2390-L2406)）。
  ほかの値は G02030 である。
  図版と本文のあいだの空きは、`style.toml` の `[figures]` の `wrap-gap` で決める（[Style.hs#L2969](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-project/src/Golem/Project/Style.hs#L2969)）。
- 仕様書は、画像とキャプションを含む矩形に `wrap-gap` を足した除外領域を作り、その脇の行を短く組むと定める（docs/specifications.md の 5757 行）。
  脇の行は、図版の直後の段落に限る（同 5758 行）。
- 除外領域は、側、幅、格子の行の数を持つ（[Wrap.hs#L16-L38](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-layout/src/Golem/Layout/Wrap.hs#L16-L38)）。
  脇の行の幅は、どの行も同じく、本文幅から除外領域の幅を引いたものである。
  0437 は、除外領域をボックスの形で表すのは輪郭の ADR で行うと決めた（docs/adr/0437 の 87 行）。
- パスは、始点と、線分と三次のベジェ曲線の並びと、閉じているかの印を持つ部分パスの並びである（[Geometry.hs#L37-L54](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-geometry/src/Golem/Geometry.hs#L37-L54)）。
  `style.toml` のパスは、SVG のパスのデータの `M`、`L`、`C`、`Z` と絶対座標で書き、`readStylePath` が読む（[PathData.hs#L37](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-project/src/Golem/Project/PathData.hs#L37)）。
- 閉じたパスのテキストフレームは、曲線を有理数の de Casteljau の分割で折れ線にし（[Polygon.hs#L50-L71](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-geometry/src/Golem/Geometry/Polygon.hs#L50-L71)）、行の帯の全体で内側にある区間を `stripInside` で求める（[Polygon.hs#L121-L133](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-geometry/src/Golem/Geometry/Polygon.hs#L121-L133)）。
  行の帯は、格子の行の始まりから文字の大きさの高さである（[BoxModel.hs#L86-L108](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-layout/src/Golem/Layout/BoxModel.hs#L86-L108)）。
  演算はすべて有理数で、浮動小数点を使わない。
- 画像のアルファチャンネルは、PDF の書き出しのソフトマスクだけが読む（[Image.hs#L54](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-pdf/src/Golem/Pdf/Image.hs#L54)）。
  画像から輪郭を取るコードは無い。
- golem-html の出力に、回り込む図版の `float` は無い（`git grep -n float c034510 -- 'modules/golem-html/src/**/*.hs'` の結果は傍注の 1 件だけ）。

## 実装すること

### 輪郭の書き方

`style.toml` に、名前を付けた輪郭の表 `[outlines.<名前>]` を足す。
表のキーは `path` だけで、値は 0437 と同じパスのデータの文字列である。
パスの座標は、単位を書かない数で、画像の固有の座標で書く。
ラスター画像ではピクセル、SVG では `viewBox` の単位、PDF の図版では最初のページの大きさの pt である。
原点は、テキストフレームのパスと同じく画像の左上で、y を下へ取る。
単位を書かない座標を読む道を、`readStylePath` と並べて golem-project に足す。
輪郭は閉じたパスでなければならず、塗りの規則は非ゼロの回転数とする。
輪郭のうち画像の矩形の外に出る部分は、画像の矩形で切り取る。

原稿では、回り込む図版の `@figure` に `outline=<名前>` を書く。
輪郭は、画像を置く大きさに合わせて、画像と同じ比で拡大か縮小する。
`wrap` の無い図版の `outline` は使わない。

### 輪郭に沿う行の幅

輪郭を書いた図版の除外領域は、置いた輪郭と、キャプションの矩形の和とする。
脇の行の幅は、行ごとに次のように求める。

1. 行の帯を、行の始まりから文字の大きさの高さとする。
   格子に揃える版面では格子の行の始まり、`alignment = "free"` の版面では段落の行送りで決まる行の始まりである。
2. 帯を上下に `wrap-gap` ずつ広げ、広げた帯と除外領域が重なる部分の、本文の側の端を求める。
   端は、帯の中にある頂点と、帯の上下の辺と輪郭の交点から、有理数で求める。
3. 端から `wrap-gap` 離れた位置を、その行の本文の始まり（`wrap=start`）か終わり（`wrap=end`）とする。
   その位置を本文の側へ `Sp` に切り上げ、行が除外領域に重ならないようにする。
4. 重なる部分の無い行は、本文幅のまま組む。

今の、脇の行の長さが 8 字に満たなければ G07022 とする検査は、脇の行のうち最も短い行で行う。

行ごとに、本文を置く区間は一つである。
輪郭のくぼみや穴の中には本文を置かない。

### 除外領域の表し方

除外領域を、側と、行の帯の始まりと終わりから本文の側の端を返す関数で表す。
格子に揃える版面も揃えない版面も、同じ関数で行の幅を求める。
矩形の図版は、今と同じ幅になるように表す。
これは 0437 が輪郭の ADR に回した、除外領域の形の表し方である。

### diagnostic

| 箇所 | コード | 重大度 | メッセージ |
| --- | --- | --- | --- |
| `[outlines.<名前>]` の `path` が読めないか、閉じていない | G03300 | エラー | `輪郭 <名前> のパスを読めません: <理由>` |
| `outline` の名前の輪郭が `style.toml` に無い | G02285 | エラー | `輪郭 <名前> がありません` |
| `wrap` の無い `@figure` に `outline` を書いた | G02286 | 警告 | `outline は wrap のある図版にだけ使います` |

G02285 と G02286 は、書いた `@figure` の一つごとに出す。
G02285 の図版は、矩形の除外領域で組む。

### HTML と EPUB

HTML と EPUB の図版は、今は回り込まない。
この ADR でも、HTML と EPUB の出力は変えない。

### 文書

仕様書の図版の回り込みの節と、`style.toml` の表の節に、輪郭と行の幅の求め方を書く。
`docs/diagnostics.md` に G02285、G02286、G03300 を足す。
ロードマップの「輪郭に沿った回り込み」の項目を消し、「パス」の項目から輪郭の文を消す。

採択したら、0382 のステータスの注記に加えて、`{"part":"輪郭の指定","by":["docs/adr/0464-wrap-text-along-figure-outlines.md"],"kind":"supplement"}` を記録する。

## 実装しないこと

画像のアルファチャンネルや SVG の形から、輪郭を自動で取ることはしない。
図版の両側に本文を流すことと、輪郭のくぼみの中に本文を置くことはしない。
HTML と EPUB の回り込み（CSS の `shape-outside`）は扱わない。
回り込む図版の直後の段落だけが脇の行になる決まりは変えない。

## 不変条件

- I1: `outline` を書かない図版の脇の行の幅は、この ADR の前と同じである。
- I2: 輪郭を書いた図版の脇の各行の、本文の区間と、帯を `wrap-gap` 広げた除外領域とは重ならない。
- I3: 輪郭を書いた図版の脇の各行の本文の幅は、同じ図版を矩形で組んだときの幅以上である。
- I4: 脇の各行の本文の端と除外領域の端の差は、`wrap-gap` 以上、`wrap-gap` に 1 sp を足した値未満である。
- I5: 同じ入力からは、どの環境でも同じ行の幅が出る（演算に浮動小数点を使わない）。
- I6: 読めない輪郭ごとに G03300 が、無い輪郭を指す `@figure` ごとに G02285 が、`wrap` の無い `@figure` の `outline` ごとに G02286 が、ちょうど一つ出る。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| `outline` の無い `wrap=start` の図版 | 今と同じ幅 | I1 |
| 画像と同じ矩形の輪郭 | 今の幅以上（キャプションを含む） | I3 |
| 画像の矩形の外に出る輪郭 | 画像の矩形で切り取る | I3 |
| `alignment = "free"` の版面と円の輪郭 | 段落の行送りの帯で幅が決まる | I2, I4 |
| 三角形の輪郭（左下、右下、上の頂点）、`wrap=end` | 上の行ほど長い | I2, I3, I4 |
| 円の輪郭（四つの三次のベジェ曲線） | 中ほどの行が最も短い | I2, I4, I5 |
| 輪郭の帯と重ならない行 | 本文幅のまま | I3 |
| 輪郭の頂点がちょうど帯の上の辺にある | その頂点を端に含む | I2 |
| `outline=missing` | G02285。矩形で組む | I1, I6 |
| `wrap` の無い図版の `outline` | G02286 | I6 |
| `[outlines.a] path = "M 0 0 L 10 0"`（閉じていない） | G03300 | I6 |

## 受けいれ条件

- A1: 円と星形の輪郭の図版を回り込ませた見本を PDF で組み、メンテナーが、本文が輪郭から `wrap-gap` 離れて沿っていることを目で確かめる。

## テスト設計

root ADR 0464 I1 から I6 を名前の先頭に置いたテストを、golem-geometry（帯と輪郭の端）、golem-layout（行の幅の並び）、golem-project（輪郭の表の読み込み）、golem-eval（`outline` の引数とdiagnostic）に足す。
I2 から I4 は、小さな多角形と帯の位置を総当たりで並べて確かめる。
A1 は、見本のプロジェクトをテストのデータに置き、組んだ PDF をメンテナーが見る。
テストは、実装の前に書いて落ちることを確かめる。

## トレードオフ

`wrap-gap` を、帯を上下に広げることと、端から横に離すことで表すので、輪郭からの空きは、正方形を輪郭に沿って動かした形になる。
輪郭からの距離を正確に一定にする（輪郭を円で太らせる）より大きく空くことがあるが、有理数の演算だけで求められる。

輪郭を `style.toml` に名前で置くので、原稿にはパスの数字が出ない。
同じ輪郭を、大きさの違う図版に使い回せる。

## 参考文献

- [Golem ADR 0382](0382-figure-extent-and-captions.md)
- [root ADR 0437](0437-paths-and-the-box-model.md)
- [root ADR 0447](0447-find-the-strip-intervals-by-pieces-between-vertices-and-crossings.md)
- [golem-layout ADR 0004](../golem-layout/adr/0004-wrapped-figures.md)
