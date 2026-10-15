# ADR 0020: GPOS の配置のずらしと二倍ダッシュのカーニング

ステータス: 採択

## 文脈

この ADR は、仕様書の「v1 の実装で次の段階以降に回した項目」の二つを扱う。
どちらも、HarfBuzz が返す配置の値のうち、Golem が使っていないものと使いすぎているものの問題である。

### 配置のずらしを捨てている

HarfBuzz は、シェイピングの結果としてグリフごとに送り（x と y の advance）とずらし（x と y の offset）を返す。
OpenType の GPOS の調整（ValueRecord）は、送りを変える `XAdvance` と、グリフの置き場所だけを変える `XPlacement` と `YPlacement` を持つ。
`palt` と `vpal` は、一字ごとに送りを縮め、同時にグリフを縮めた箱の中に寄せる。
後者は `XPlacement`（縦組みでは `YPlacement`）で表される。

golem-font の `shapeUnits` は、四つの値（x と y の送り、x と y のずらし）を返す。
golem-driver の `Golem.Driver.Fonts` の `shapeText` は、そのうち送りだけを `Shaped` の `shAdvance` に入れ、ずらしを捨てている。

```haskell
glyph ix f r turned dir (g, c, (xa, ya, _, _)) =
  Shaped ix g (toInteger (if dir == Vertical then negate ya else xa) % toInteger (fontUnitsPerEm f)) (clusterText r c) turned c
```

`Golem.Driver.Pdf` の `runAt` は、`shAdvance` を足し合わせた位置にグリフの原点を置く。
`palt` で送りは縮むが、グリフは縮める前と同じ原点に置かれるので、字は縮んだ箱の中で片側に寄る。
始め括弧のように字面が箱の右半分にある字では、詰めた分だけ前の字に近づかず、後ろの字に重なることもある。
役割の `features` に `palt` を書いた場合（[docs/adr/0020](../../adr/0020-indesign-character-features.md)）も、文字スタイルの `proportional-metrics` の場合も同じである。
欧文のフォントの GPOS の mark の配置（結合文字のアクセントの位置）も、同じ理由で効いていない。

縦組みでは、もう一つ事情がある。
HarfBuzz は縦書きの方向のシェイピングで、各グリフのずらしから、そのグリフの縦組みの原点（`hb_font_get_glyph_v_origin` の値）を引いて返す（リポジトリの HarfBuzz の `hb-ot-shape.cc` の `hb_ot_position_default` が `subtract_glyph_v_origins` を呼ぶ）。
ずらしは横組みの原点（基準線の左端）から測った値になっており、GPOS の調整がないグリフでも 0 ではない。
Golem の縦組みの描画は、PDF の Identity-V のフォントで、グリフを縦組みの原点（字面の枠の上端の中央）に置く。
返されたずらしをそのまま足すと、すべての字が大きくずれる。

### 二倍ダッシュにカーニングがかかる

和文のペアカーニング（[docs/adr/0020](../../adr/0020-indesign-character-features.md)）は、golem-layout の `Golem.Layout.Japanese` の `kernPairs` が、和文の一字の箱が二つ並んだところにかける。
約物（始め括弧類、終わり括弧類、句点類、読点類、中点類）を含む組は除く。
約物の前後の空きを JLReq の規則（[docs/adr/0019](../../adr/0019-aki-settings.md) のアキ量のセット）で決めるためである。

二倍ダッシュ（U+2014 を二つ並べたもの）の U+2014 は、JLReq の分離禁止文字（cl-08）に当たり、`Golem.Layout.CharClass` で `Inseparable` に分類される。
`Inseparable` は除く一覧に入っていないので、`kerning = "metrics"`（既定）でフォントのペアカーニングがかかる。
蟹工船の縦組みでは、319 か所の二倍ダッシュに −0.088em のカーニングがかかり、二つのダッシュの線が重なる。
三点リーダー（…）と二点リーダー（‥）の並びも、フォントがカーニングの情報を持てば同じことが起きる。

JLReq は、分離禁止文字の連続を分割しない、間を空けないと定めている。
アキ量のセットも、分離禁止文字どうしの組の空きを 0 にしている（`Golem.Layout.Aki`）。
二字を一続きの線や点の並びとして見せるための規則であり、フォントのカーニングで間を詰めると、線が重なって濃くなるか、点の間隔が不揃いになる。

## 実装すること

### ずらしを `Shaped` に入れる（golem-font、golem-driver）

golem-font に、グリフの縦組みの原点を返す関数を加える。

```haskell
-- | 縦組みの原点（x、y）、フォントの単位。hb_font_get_glyph_v_origin の値
glyphVerticalOrigin :: Font -> Int -> (Int, Int)
```

C の側には `golem_font_v_origin(golem_font *f, uint32_t gid, int32_t *x, int32_t *y)` を加える。

`Golem.Driver.Pdf` の `Shaped` に、ずらしの欄を加える。

```haskell
data Shaped = Shaped
  { ...
    -- | GPOS のずらし（x、y）、全角を 1 とする値。グリフの描く向きの座標で、y は上が正
    shOffset :: !(Rational, Rational)
  }
```

`shapeText` は、ずらしを次のように入れる。

- 横書きの方向でシェイピングしたグリフ（横組みの字、縦組みで回して組む字と欧文）：HarfBuzz の x と y のずらしをそのまま使う。
- 縦書きの方向でシェイピングしたグリフ：HarfBuzz のずらしに `glyphVerticalOrigin` を足し戻す。GPOS の調整がないグリフでは (0, 0) になる。

送りの値と、送りを測る関数（`lfAdvance`、`lfWordAdvance`、`lfPairKern`）は変えない。
ずらしは送りを変えないので、行分割、改ページ、相互参照のページ番号は変わらない。

### ずらしを描画に使う（golem-driver）

`runAt` は、各グリフの原点にずらしを `size` 倍して足す。

- 横組み：`(x0 + off + dx, y0 + dy)`。
- 縦組みの立てて組む字（`GlyphRun` の縦組みのフォント）：`(x0 + dx, y0 − off + dy)`。
- 縦組みで時計回りに回して組む字（`RotatedGlyphRun` と `turned` のグリフ）：グリフの座標を 90 度回すので、`(gx + dy, gy − dx)` とする（`gx` と `gy` は今の原点）。
- 伸縮（`ScaledGlyphRun`、[golem-layout ADR 0005](../../golem-layout/adr/0005-microtypography.md)）のグリフ：x のずらしにも水平比率をかけ、`dx × (1000 + scale) / 1000` とする。
- 合成の斜体と太字（`StyledGlyphRun`）は、原点をずらした後に今と同じく描く。

ルビの読み、圏点、注の印、柱、ノンブルは、どれも `runAt` で描くので、同じくずらしが効く。

### 分離禁止文字の組にカーニングをかけない（golem-layout）

`kernPairs` の `single` の除く一覧に `Inseparable` を加える。

```haskell
charClass ch `notElem` [Western, Opening, Closing, FullStop, Comma, MiddleDot, Inseparable]
```

- 分離禁止文字（—、…、‥、〳、〴、〵）を前か後ろに含む組には、ペアカーニングをかけない。二字がどちらも分離禁止文字の組だけでなく、「漢」と「—」のような組にもかけない。
- 横組みと縦組みのどちらにも効く。縦組みの `vkrn` も、同じ `kernPairs` で除かれる。
- 欧文の語の中の U+2014（`textPieces` が欧文の語に含めるもの）は、語の全体をシェイピングして測るので、この規則の外にある（「実装しないこと」）。

### ドキュメント

- 仕様書の「v1 の実装で次の段階以降に回した項目」から「GPOS の配置のずらし」と「二倍ダッシュのカーニング」の二つの項目を消す。
- 仕様書の「style.toml」の節の `kerning` の説明と、用語集の「カーニング」の項の「和文のペアカーニングは約物を含む組にはかけない」に、分離禁止文字を含む組にもかけないことを書き足す。
- 利用者のマニュアル（`manual/`）の、カーニングをかけない組の説明を直す（[docs/adr/0024](../../adr/0024-manual-audiences-and-policy.md)）。対象は `manual/chapters/05-style.gm` の「文字の送り」の節の「約物（括弧類、句読点、中点類）を含む字の組には、和文のカーニングをかけません。」の段落と、`manual/appendices/c-style.gm` の「`[character-styles.名前]`」の `kerning` の値の説明、`manual/appendices/f-indesign.gm`（今の `e-indesign.gm`、[golem-cli ADR 0006](../../golem-cli/adr/0006-preflight.md) で付録F に繰り下がる）の「カーニングとトラッキング」の節である。この ADR の変更と食い違う記述がなければ、マニュアルは変えない。
- [docs/adr/0020](../../adr/0020-indesign-character-features.md) のステータスの行に、除く一覧に分離禁止文字を加えたことを、この ADR へのリンクで書き足す。

## 実装しないこと

- 欧文の語の中の U+2014 の並びのカーニング。欧文で U+2014 を二つ並べるのは、人名の伏せ字のようにまれであり、語の中のカーニングはフォントの設計に任せる。
- 分離禁止文字のほかに、アキ量のセットが空きを決めるクラス（区切り約物、ハイフン類、繰返し記号など）をカーニングから除くこと。蟹工船とマニュアルで問題が見つかっていない。必要になったら、[docs/adr/0020](../../adr/0020-indesign-character-features.md) の一覧の考え方に従って足す。
- 縦組みの描画の原点を、HarfBuzz の縦組みの原点と PDF の Identity-V の原点（`DW2` の既定の 880）で一致させること。今の描画の前提であり、この ADR はずらしだけを扱う。
- GPOS の cursive attachment と、送りを複数のグリフにまたがって調整する機能の確かめ。Golem の対象の和文と欧文の書体では使われないと見込む。

## テスト設計

実装の前に書き、失敗することを確かめる。

### シェイピング（`modules/golem-font/test/Main.hs`）

`modules/golem-font/test/fonts/` の Source Han Sans のサブセットを使う。

- 横書きの方向で `palt` を有効にした「「」の x のずらしが 0 ではなく、`palt` を止めた「「」の x と y のずらしが 0 である。
- 縦書きの方向で、機能を足さない「漢」のずらしに `glyphVerticalOrigin` を足した値が (0, 0) である。HarfBuzz が縦組みの原点を引いて返すという前提を、このテストで確かめる。
- 縦書きの方向で `vpal` を有効にした「「」の y のずらし（縦組みの原点を足し戻した値）が 0 ではない。

### 描画（`modules/golem-driver/test/Main.hs`）

- 横組みで `proportional-metrics = true` の段落の「漢「字」」を組み、「「」のグリフの原点の x が、「「」の箱の始まりに `palt` の x のずらしを足した値である。今の実装では箱の始まりに置かれるので、失敗する。
- 縦組みで同じ段落を組み、「「」のグリフの原点の y が、箱の始まりから `vpal` の y のずらしだけ動いている。`palt` も `vpal` もない字の原点は今と変わらない。
- `Shaped` の `shOffset` が、`palt` のない段落ではすべて (0, 0) である。既存の PDF の golden テストのうち、`palt` も `vpal` も使わないものの出力が変わらないことをあわせて確かめる。
- 伸縮のかかった欧文の行で、ずらしのあるグリフの x に水平比率がかかっている。テストの書体にずらしのある欧文のグリフがなければ、`Shaped` を直接作って `runAt` に渡す形で確かめる。

### カーニング（`modules/golem-layout/test/Main.hs`）

`ceKern` に、どの組にも −0.088 を返す関数を入れた環境で組む。

- 「あ」と U+2014 二つと「い」を並べた段落で、二つの U+2014 の箱の幅が送りのままであり、`bcEdgeEnd` が 0 である。「あ」と最初の U+2014 の組にもかからない。
- 「……」と「‥‥」でも同じである。
- 「あい」には今と同じくカーニングがかかる。
- 縦組みの環境でも同じ結果になる。

### 決定性と出力の差

- 決定性の検査に使う蟹工船の縦組みの PDF が変わる。差が二倍ダッシュの位置（319 か所）と、それ以降の行の送りの変化に限られることを、変更の前後の行の切れ目を比べて確かめ、実装のプルリクエストに書く。
- `palt` を使うマニュアルの PDF が変わる。差がグリフの位置だけで、行の切れ目とページが変わらないことを確かめる。

### 自動テストにしない確かめ方

- `palt` を有効にした横組みと `vpal` を有効にした縦組みの段落を PDF で目で見て、括弧と句読点が詰めた箱の中で正しい側に寄り、隣の字に重ならないことを確かめる。
- 蟹工船の縦組みの PDF で、二倍ダッシュが一本の線に見え、重なって濃くなっていないことを目で確かめる。

## トレードオフ

分離禁止文字を、両隣とのカーニングから一律に除いた。
二字がどちらも分離禁止文字の組だけを除けば、「漢」と「—」のような組にはカーニングが残る。
しかし、アキ量のセットは分離禁止文字の前後の空きも規則で持っており、[docs/adr/0020](../../adr/0020-indesign-character-features.md) が約物を除いたのと同じ理由がそのまま当てはまる。
規則を一つにしておくほうが、書き手にも説明しやすい。
InDesign が分離禁止文字の組にカーニングをかけるかどうかは確かめていない。

本ごとに文字スタイル（`kerning = "none"`）を正規表現スタイルで二倍ダッシュにかける方法でも、今の版のままずれは直せる。
しかし、分離禁止は本ごとに変わる好みではなく組版の規則なので、エンジンの既定で守る。
文字スタイルに任せると、書き忘れた本では二倍ダッシュが黙って重なり、新しく本を作る人ほど気づきにくい。
ペアカーニングから約物を除く一覧もエンジンの側にあり、分離禁止文字だけを書き手に任せる理由がない。
文字スタイルで `kerning` を指定する方法は、既定から外れた調整をしたい場合のために残る。

ずらしを描画だけに使い、送りの測り方は変えない。
GPOS の調整のうち、送りの変化はすでに測った幅に入っているので、描画のずれだけを直せば、行分割の結果は保たれる。

縦組みのずらしを、HarfBuzz の縦組みの原点を足し戻して求めることにした。
足し戻しの前提は HarfBuzz の実装の性質であり、HarfBuzz の版を上げると変わる可能性がある。
シェイピングのテストの一つで前提を確かめるので、変わったときはテストが落ちる。

## 参考文献

- Microsoft, OpenType Specification, GPOS — The Glyph Positioning Table（ValueRecord の XPlacement、YPlacement、XAdvance、YAdvance）, https://learn.microsoft.com/en-us/typography/opentype/spec/gpos 。
- Microsoft, OpenType Feature Registry, `palt` と `vpal`, https://learn.microsoft.com/en-us/typography/opentype/spec/features_pt 。
- HarfBuzz 14.6.0 のソース、`src/hb-ot-shape.cc` の `hb_ot_position_default`。リポジトリに含む版で確かめる。
- W3C, Requirements for Japanese Text Layout（JLReq）, https://www.w3.org/TR/jlreq/ 。分離禁止文字（cl-08）。
- Adobe, PDF Reference（ISO 32000-1）, 9.7.4.3 Glyph Metrics in CIDFonts（縦組みの位置ベクトルと `DW2`）。
