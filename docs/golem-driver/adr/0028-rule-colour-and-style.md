# ADR 0028: 罫線の色と線の種類

ステータス: 採択

## 文脈

ロードマップの v1.0.0 の「罫線の色と線の種類」は、罫線の指定（[ADR 0024](0024-rule-spec-and-footnote-separator.md)）に、色と線の種類（実線、破線、点線、二重線など）を加える項目である。
色は名前の付いた色（仕様書の「色」の節）で書き、罫線の指定を使うすべての罫線に同時に加える。
[ADR 0024](0024-rule-spec-and-footnote-separator.md) は、色と線の種類をキーを足す ADR で扱うと決めていた。

罫線の指定の使い手は、脚注の区切り線（`[notes.rule]`、[ADR 0024](0024-rule-spec-and-footnote-separator.md)）と、段落スタイルと見出しの罫線（`rule-before`、`rule-after`、[ADR 0027](0027-paragraph-style-rules.md)）である。
表の罫線は罫線の指定を使わず、太さと位置を固定している（[ADR 0008](0008-pdf-tables.md)）。
表の罫線の設定は v2 の「表の拡張」に残る。

### 今のコード

コードで確かめると、次のとおりである。

- `Golem.Project.Style` の `RuleSpec` は、`length`、`weight`、`space-before`、`space-after` の四つのキーだけを読み、ほかのキーを G0306 にする。
- golem-pdf の罫線の描画の手段は、塗った矩形の `Rule`（`re f`）だけである。線を引く（stroke の）演算子も、曲線も書かない。トンボも矩形を塗って描く（[golem-pdf ADR 0007](../../golem-pdf/adr/0007-registration-crop-marks.md)）。
- 脚注の区切り線と表の罫線は、色を設定せずに描く。PDF の既定の塗りの色（DeviceGray の黒）になる。
- コードブロックの背景と枠は、`P.Saved [P.SetColor sw, P.Rule ...]` の形で、スウォッチの CMYK を DeviceCMYK で塗る（[ADR 0017](0017-pdf-code-blocks.md)、[ADR 0023](0023-code-block-book-features.md)）。`SetColor` は塗りと線の両方の色（`k` と `K`）を設定する。
- golem preflight は、罫線の太さを `RuleView` の `rvWeight` で検査し（G0918）、使ったスウォッチの総インキ量を `vwSwatchesUsed` で検査する（G0915）。罫線の色は、今はスウォッチとして数えていない。


### InDesign の線の種類と既定

メンテナーは、線の種類と既定の値を InDesign にそろえると決めた（「メンテナーが決めたこと」）。
そこで、InDesign の線パネルの種類と、その既定の値を調べた。
Adobe のヘルプ（helpx.adobe.com）の線の頁は取得できず（HTTP 403）、次の資料と記憶によった。

- **種類の一覧**：Adobe Community のスクリプトの質問への回答が、線の種類のスクリプトでの名前を挙げている。`ThickThinThick`、`ThinThick`、`ThinThickThin`、`ThinThin`、`Triple_Stroke`、`White Diamond`、`Japanese Dots`、`Canned Dashed 3x2`、`Canned Dashed 4x4`、`Left Slant Hash`、`Right Slant Hash`、`Straight Hash`、`Canned Dotted`、`Dashed`、`Wavy` である。線パネルの一覧にはこのほか「実線」「太線 - 太線」「太線 - 細線」もあったと記憶しているが、資料では確かめていない。
- **破線の割り付け**：CreativePro の記事によれば、線パネルの「角」の既定は「線分と間隔を調整」であり、InDesign は端点と角を線分で覆うように線分と間隔の両方の長さを変える。Adobe の DOM の `StrokeCornerAdjustment` の `DASHES_AND_GAPS` も、線分と間隔の両方を調整して角と端点を覆うと説明している。
- **点線の間隔**：CreativePro の記事は、組み込みの「点線」（`Dotted`）が、太さ 1pt の線で点を 3pt ごとに置くと書いている（検索結果の要約で読んだもので、記事の本文は取得できなかった）。点の直径を線の太さとすると、点と点のあいだの間隔は太さの 2 倍になる。組み込みの点線は端の点を端点の内側に置き、丸い端で描く自作の点線のように端点の外へははみ出さない、とも書いている。
- **破線の既定**：`Canned Dashed 3x2` と `Canned Dashed 4x4` は、線パネルの「破線（3 と 2）」と「破線（4 と 4）」にあたると見られる。数は線分と間隔の比を太さの倍数で表したものと推定したが、資料では確かめていない。自作の「破線」の線分と間隔の既定の値は、資料で確かめられなかった。
- **多重線の比**：「太線 - 細線」などの、線と間隔の太さの比は、資料で確かめられなかった。
- **和文の点線（`Japanese Dots`）の形**：点の形（丸か四角か）と間隔は、資料で確かめられなかった。

確かめられなかった値は、この ADR で決め、「実装すること」でその旨を書く。

### メンテナーが決めたこと

- 破線と点線の既定の値と、線の種類は、InDesign にそろえる。InDesign の線の種類のうち、罫線として意味のあるものを採る。
- 既定の値の出どころを書き、資料で確かめられなかった値はそう書く。
- この ADR は v0.1.0-rc3 で実装する。

## 実装すること

### 罫線の指定のキー

罫線の指定に、四つのキーを加える。

| キー | 型 | 意味 |
| --- | --- | --- |
| `color` | スウォッチの名前 | 罫線の色。既定はなし（色を設定せずに描く。今と同じ） |
| `style` | 文字列 | 線の種類（次の表）。既定は `"solid"` |
| `dash` | 寸法 | 破線の一つの線分の長さ。既定は `weight` の 3 倍 |
| `gap` | 寸法 | 破線の線分と線分のあいだ、点線の点と点のあいだの間隔。既定は線の種類による（次の表） |

線の種類は、InDesign の線の種類のうち、罫線として意味のある 12 種とする。

| `style` | InDesign の種類 | 形 | `gap` の既定 |
| --- | --- | --- | --- |
| `"solid"` | 実線 | 一本の線 | 書けない |
| `"thin-thin"` | 細線 - 細線（`ThinThin`） | 二本の線。線、間隔、線の比が 1:1:1 | 書けない |
| `"thick-thick"` | 太線 - 太線 | 二本の線。比が 2:1:2 | 書けない |
| `"thick-thin"` | 太線 - 細線 | 二本の線。比が 2:1:1 | 書けない |
| `"thin-thick"` | 細線 - 太線（`ThinThick`） | 二本の線。比が 1:1:2 | 書けない |
| `"thick-thin-thick"` | 太線 - 細線 - 太線（`ThickThinThick`） | 三本の線。比が 2:1:1:1:2 | 書けない |
| `"thin-thick-thin"` | 細線 - 太線 - 細線（`ThinThickThin`） | 三本の線。比が 1:1:2:1:1 | 書けない |
| `"triple"` | 三重線（`Triple_Stroke`） | 三本の線。比が 1:1:1:1:1 | 書けない |
| `"dashed"` | 破線（`Dashed`、`Canned Dashed 3x2`） | 線分の並び | `weight` の 2 倍 |
| `"dotted"` | 点線（`Canned Dotted`） | 丸い点の並び | `weight` の 2 倍 |
| `"japanese-dots"` | 和文の点線（`Japanese Dots`） | 四角い点の並び | `weight` と同じ |
| `"wavy"` | 波線（`Wavy`） | 波の形の線 | 書けない |

既定の値の出どころは次のとおりである。

- **破線の線分 3 倍と間隔 2 倍**：InDesign の「破線（3 と 2）」の名前から推定した比である。資料では確かめていない。自作の「破線」の既定は確かめられなかったので、既定の破線を「破線（3 と 2）」にそろえた。「破線（4 と 4）」は、`dash` と `gap` を書いて表す。
- **点線の間隔 2 倍**：CreativePro の記事の「太さ 1pt の線で 3pt ごと」から求めた値である（記事の本文は取得できず、検索結果の要約による）。
- **和文の点線の四角い点と間隔 1 倍**：資料で確かめられなかったので、この ADR で決めた値である。
- **多重線の比**：資料で確かめられなかったので、この ADR で決めた比である。比の中の「1」は、細い線と、線と線のあいだの間隔の太さである。
- **波線の形**：資料で確かめられなかったので、この ADR で決めた形である（「線の種類の形」の節）。

採らなかった InDesign の種類は、斜線（`Left Slant Hash`、`Right Slant Hash`）、縦線（`Straight Hash`）、白抜きの菱形（`White Diamond`）である。
どれも帯の中に短い線か図形を並べる飾りの線であり、罫線の太さ（0.3pt から 1pt 程度）では形が読み取れない。
飾りの線が要るとわかったら、種類を足す ADR で扱う。

```toml
[notes.rule]
length = "10zw"
weight = "0.5pt"
style = "dotted"
color = "accent"
```

- 値の検査は、どの使い手でも同じにする。
  - `color` が `[color.swatches]` にない場合は G0313 とする。文字スタイルの `color` と同じ扱いである。
  - `style` が表の値のどれでもない場合は G0306 とする。
  - `dash` と `gap` が寸法として読めない値の場合、0 以下の場合、`zw` の場合は G0306 とする。線分の長さは `weight` と同じく字の大きさに比例させる理由がないので、`zw` を受け付けない。
  - `dash` は `"dashed"` のときだけ、`gap` は `"dashed"`、`"dotted"`、`"japanese-dots"` のときだけ書ける。ほかの線の種類に書くと G0306 とする。効果のないキーを黙って受け付けないためである。
- 既定の値は今の振る舞いと同じなので、四つのキーを書かない本の出力は変わらない。
- 使い手ごとに変える事項はない。四つのキーは、脚注の区切り線、段落スタイルの罫線、見出しの罫線で同じ意味を持つ。

### 線の種類の形

罫線は、長さ `L`、太さ `w` の帯の中に描く。
帯の位置と向きは、使い手が決める今の位置のままとする。
どの線の種類でも帯の外には描かないので、罫線の領域の計算（[ADR 0024](0024-rule-spec-and-footnote-separator.md)、[ADR 0027](0027-paragraph-style-rules.md)）は変わらない。
帯の「前」は、横組みでは上、縦組みでは右とする。

- **実線**：帯の全体を一つの矩形で塗る。今と同じである。
- **多重線**：帯を、表の比で前から順に線と間隔に分け、線の部分を塗る。比の和を U、前から j 番目の境目までの比の和を c_j とすると、境目の位置は `(c_j × w) div U` である。
- **破線**：InDesign の「線分と間隔を調整」にそろえ、両端を線分で終えるよう、線分と間隔の両方の長さを変える。線分の数 n は、`(L + g)` を `(d + g)` で割って四捨五入した値と 1 の大きいほうとする（`d` は `dash`、`g` は `gap`）。`T = n × d + (n − 1) × g` とし、i 番目（0 から）の線分を、帯の始まりから `(i × (d + g) × L) div T` の位置から `((i × (d + g) + d) × L) div T` の位置まで塗る。n が 1 なら、帯の全体を一本の線で塗る。
- **点線**：直径 `w` の丸い点を並べる。点の数 n は、`(L − w)` を `(w + g)` で割って四捨五入した値に 1 を足し、1 との大きいほうとする。i 番目の点の中心を、帯の始まりから `w/2 + (i × (L − w)) div (n − 1)` に置く。n が 1 なら、帯の中央に一つ置く。最初と最後の点は帯の端の内側に収まる。
- **和文の点線**：一辺 `w` の四角い点を、点線と同じ規則で並べる。
- **波線**：線の太さ `t` を `w div 4`、振幅 `a` を `(w − t) div 2` とし、帯の中心線のまわりを上下する波を、太さ `t` の帯として塗る。半周期の数 m は、`L` を `2 × w` で割って四捨五入した値と 1 の大きいほうとし、j 番目（0 から）の半周期を、帯の始まりから `(j × L) div m` の位置から `((j + 1) × L) div m` の位置までとし、その長さを `h` とする。各半周期は、山（または谷）を一つの 3 次ベジエ曲線で描き、制御点を半周期の始まりから `h/3` と `2h/3`、中心線から `4a/3` に置く。こうすると山の高さはちょうど `a` になり、隣の半周期との継ぎ目で接線が連続する。波の上の縁は中心線を `t/2` 上げた曲線、下の縁は `t/2` 下げた曲線とし、そのあいだを塗る。

破線と点の位置を割り付けるのは、罫線の両端を線分か点で終えるためである。
PDF の破線のパターン（`d` の演算子）に任せると、罫線の終わりが間隔の途中で切れることがあり、端の見え方が長さによって変わる。

どの計算も sp の整数で行い、割り算は一度だけ切り捨てるか四捨五入する（[docs/adr/0002](../../adr/0002-determinism.md)）。

### PDF の描き方

- 実線、多重線、破線、和文の点線は、今の `Rule`（塗った矩形）を並べて描く。
- 点線のために、golem-pdf の `Mark` に塗った円 `Disc`（中心の x と y、半径）を加える。円は、四つの 3 次ベジエ曲線（`m`、`c` を四つ、`f`）で書く。制御点は、中心から半径に 0.5523 を掛けた距離に置き、sp に丸める。
- 波線のために、`Mark` に塗った閉じた曲線 `CurveFill`（始点と、3 次ベジエ曲線の制御点と終点の並び）を加える。`m`、`c` の並び、`h`、`f` で書く。
- `color` があれば、罫線の矩形と円と曲線を `Saved [SetColor sw, ...]` で囲み、スウォッチの CMYK を DeviceCMYK で塗る。コードブロックの背景と同じ形である。`color` がなければ、今と同じく色を設定しない。
- 線を引く演算子（`S`）、線の端の形（`J`）、破線のパターン（`d`）は使わない。罫線をすべて塗りで描くので、golem preflight の線の太さの検査が、塗った形の太さだけを見ればよい。

### golem preflight

- `pdRules` と `RuleView` の `rvWeight` には、線の種類の最も細い部分の太さを入れる。実線と破線では `w`、多重線では最も細い線の太さ、点線と和文の点線では `w`、波線では `t` とする。多重線の細い線や波線が細すぎる場合に G0918 で報告するためである。
- 罫線の色のスウォッチを、使ったスウォッチ（`vwSwatchesUsed`）に加える。総インキ量の検査（G0915）が、罫線の色にも及ぶ。

### HTML と EPUB

段落スタイルと見出しの罫線（[ADR 0027](0027-paragraph-style-rules.md)）の `border-block-start` に、線の種類と色を書く。

- 線の種類は、CSS の `border-style` に写す。`"solid"` は `solid`、`"dashed"` は `dashed`、`"dotted"` と `"japanese-dots"` は `dotted`、多重線の 7 種は `double` とする。`"wavy"` は CSS の枠線で表せないので `solid` とする。
- 色は、スウォッチの RGB の近似で書く。文字スタイルの `color` と同じ変換である。`color` がなければ、今と同じく書かない。
- `dash` と `gap` は CSS で表せないので、書かない。線分と間隔の長さは読者側のエンジンが決める。

脚注の区切り線は、今と同じく HTML と EPUB に出さない。
プレーンテキストには罫線を出力しない。

### データ構造

- `RuleSpec` に、`rsColor :: Maybe Text` と `rsStyle :: RuleStyle` を加える。

```haskell
-- | The line style of a rule (golem-driver ADR 0028); lengths in sp.
data RuleStyle
  = RuleSolid
  | RuleMulti ![Int] -- ^ the proportions, line, gap, line, ... from the before side
  | RuleDashed !Sp !Sp -- ^ dash, gap
  | RuleDotted !Sp -- ^ gap
  | RuleJapaneseDots !Sp -- ^ gap
  | RuleWavy
```

- 多重線の 7 種は、`style` の名前から `RuleMulti` の比に写す。比は golem-project の一か所の表に置く。
- 破線と点線の既定の長さは、`RuleSpec` を読むときに `weight` から求めて入れる。使う側は既定を知らなくてよい。
- スウォッチの検査は、`[color.swatches]` を読んだ後に、`Style` の中のすべての `RuleSpec`（`stNotesRule`、段落スタイルと見出しの罫線）について行う。`parseRuleSpec` は罫線の指定だけを読む関数なので、スウォッチを知らない。
- golem-pdf の `Mark` に `Disc` と `CurveFill` を加え、`contentStream` で曲線として書く。
- 罫線の形を矩形、円、曲線の並びに分ける純粋な関数を golem-driver に置き、`noteRule` と段落の罫線の描画がそれを使う。

### ドキュメント

- docs/specifications.md：「罫線の指定」の表と検査の段落に四つのキーと線の種類の表を加え、「style.toml」の例に `style` と `color` を書く。「色」の節に、罫線の色も DeviceCMYK で塗ることを加える。
- docs/diagnostics.md：G0306 と G0313 の主な原因に、罫線の指定のキーを加える。
- docs/roadmap.md：v1.0.0 の「罫線の色と線の種類」を消す。v0.1.0-rc3 の節に、この ADR を実装することを書く。
- [ADR 0024](0024-rule-spec-and-footnote-separator.md) のステータスを「採択→罫線の色と線の種類は [ADR 0028](0028-rule-colour-and-style.md)」にする。
- 使い手のマニュアル：`manual/chapters/05-style.gm` の注の設定と段落スタイルの罫線の説明、`manual/appendices/c-style.gm` の罫線の指定の表に四つのキーと線の種類を加える。`manual/appendices/f-indesign.gm` に、InDesign の線パネルの種類との対応と、採らなかった種類を加える。`manual/appendices/h-roadmap.gm` から罫線の色と線の種類を消す。
- 開発者のマニュアル：golem-pdf の描画の手段を説明する箇所があれば、`Disc` と `CurveFill` を加える。

## 実装しないこと

- InDesign の斜線、縦線、白抜きの菱形の線の種類（「InDesign の線の種類と既定」の節）。
- 自作の線の種類（InDesign の線のスタイルの新規作成にあたるもの）と、いくつもの長さの並び（`[3, 1, 1, 1]` のような一点鎖線）で破線を書くこと。
- 多重線の比と、波線の波長と振幅を書くこと。
- 線の端の形（丸い端、四角い端）と、破線の線分の端の丸め。
- 間隔の色（InDesign の線の間隔のカラー）。
- 破線の割り付けの方法を選ぶこと（InDesign の「角」の「なし」や「間隔を調整」にあたるもの）。「線分と間隔を調整」だけにする。
- 罫線の濃淡（スウォッチの網の割合）と、オーバープリントの設定。スウォッチの CMYK をそのまま使う。
- 表の罫線の色と線の種類。v2 の「表の拡張」で、罫線の指定の形を使って扱う。
- HTML と EPUB の破線の長さと間隔、多重線の比、波線。

## テスト設計

実装の前に書き、失敗することを確かめる。

### 罫線の指定（`modules/golem-project/test/Main.hs`）

- 四つのキーを書かない罫線の指定が、`rsColor` が `Nothing`、`rsStyle` が `RuleSolid` になる。
- `style = "dashed"`、`weight = "0.5pt"` を読むと、`RuleDashed`（1.5pt、1pt）になる。`dash = "3pt"`、`gap = "1.5pt"` を書けば、その値になる。
- `style = "dotted"`、`weight = "1pt"` を読むと、`RuleDotted`（2pt）になる。`style = "japanese-dots"`、`weight = "1pt"` を読むと、`RuleJapaneseDots`（1pt）になる。
- 多重線の 7 種が、表の比の `RuleMulti` になる（`"thick-thin"` は `[2, 1, 1]`、`"triple"` は `[1, 1, 1, 1, 1]`）。
- `style = "wavy"` が `RuleWavy` になる。
- `style = "straight-hash"`、`style = "double"`、`dash = "1zw"`、`gap = "0pt"`、`"solid"` と `dash` の組、`"dotted"` と `dash` の組、`"thin-thin"` と `gap` の組、`"wavy"` と `gap` の組が、それぞれ G0306 になる。
- `[notes.rule]` の `color = "accent"` で `[color.swatches]` に `accent` があれば読め、なければ G0313 になる。段落スタイルの `rule-before` と見出しの `rule-after` の `color` も同じく検査される。

### 線の形（golem-driver の純粋な関数のテスト）

- 長さ 100pt、太さ 1pt の `"thin-thin"` が、`1pt div 3` の太さの二本の矩形になり、二本の外側の端が帯の両端に一致する。
- 太さ 4pt の `"thick-thin"` が、前から 2pt の矩形、1pt の間隔、1pt の矩形になる。
- 太さ 7pt の `"thick-thin-thick"` が、2pt、1pt、1pt、1pt、2pt の順の三本の線と二つの間隔になる。
- 長さ 100pt、線分 3pt、間隔 2pt の破線が、`(102 / 5)` を四捨五入した 20 本の線分になり、最初の線分が 0 から始まり、最後の線分が 100pt で終わる。`T` = 98pt なので、線分の長さはどれも 3pt の 100/98 倍に近い。
- 長さ 3pt、線分 3pt、間隔 2pt の破線が 1 本の実線になる。
- 長さ 100pt、太さ 1pt、間隔 2pt の点線が、`99 / 3` を四捨五入した 33 に 1 を足した 34 個の点になり、最初の点の中心が 0.5pt、最後の点の中心が 99.5pt にある。
- 同じ条件の和文の点線が、一辺 1pt の 34 個の矩形になる。
- 長さ 100pt、太さ 4pt の波線が、半周期 `100 / 8` を四捨五入した 13 個の曲線からなり、最も高い点が帯の前の端に、最も低い点が後の端に一致し、帯の外に出ない。
- 縦組みの向きで、同じ割り付けが帯の上端から下へ並ぶ。

### PDF（`modules/golem-pdf/test/Main.hs`、`modules/golem-driver/test/Main.hs`）

- `Disc` が、`m`、四つの `c`、`f` の内容のストリームになり、制御点が半径の 0.5523 倍の位置にある。
- `CurveFill` が、`m`、`c` の並び、`h`、`f` の内容のストリームになる。
- 脚注の区切り線に `color = "accent"` を書くと、区切り線の矩形の前に `accent` の CMYK の `k` と `K` が書かれ、`q` と `Q` で囲まれる。
- 段落スタイルの罫線に `style = "dotted"` を書くと、PDF の内容に点の数だけの円が描かれる。
- 内容のストリームに `S`、`J`、`d` の演算子が現れない。
- 四つのキーを書かない本の PDF のバイト列が変わらないことを、既存の PDF のテストと決定性の検査で確かめる。
- golem preflight の見え方で、`"thin-thin"` の罫線の `rvWeight` が細い線の太さに、波線の `rvWeight` が `t` になり、罫線の色のスウォッチが `vwSwatchesUsed` に入る。総インキ量の多いスウォッチを罫線の色にだけ使うと、G0915 が出る。

### HTML（`modules/golem-html/test/Main.hs`）

- `rule-before = { style = "dashed", color = "accent" }` の段落スタイルの CSS が、`border-block-start` に `dashed` と `accent` の RGB の近似を持つ。
- `"thick-thin"` が `double` に、`"japanese-dots"` が `dotted` に、`"wavy"` が `solid` になる。

### 自動テストにしない確かめ方

- 12 の線の種類と色を付けた脚注の区切り線と段落の罫線を組み、PDF を Acrobat で開いて、破線と点線の両端が線分と点で終わること、点が円に見えること、波線が滑らかにつながること、色が DeviceCMYK の版だけに出ることを、出力プレビューで確かめる。
- 同じ太さと長さの罫線を InDesign で各線の種類で引き、PDF に書き出して並べ、多重線の比、点の間隔、和文の点線の形が大きく違わないかを目で確かめる。違う場合は、値を改める ADR を作る。

## トレードオフ

線の種類を、線を引く演算子と破線のパターンではなく、塗った矩形、円、曲線の並びで描くことにした。
PDF の破線のパターンを使えば、内容のストリームは短くなり、RIP が線を描く。
しかし、破線の終わりが間隔の途中で切れうるうえ、golem preflight の線の太さの検査と、今の罫線とトンボの描き方（どれも塗り）に、線を引く描き方が混ざる。
破線と点線の数は罫線一本あたり数十から百程度なので、PDF の大きさへの影響は小さいと見込む（計測はしていない）。

点線の点を、長さ 0 の線を丸い端で引く形（PDF の仕様が丸い点として描くと定める形）ではなく、ベジエ曲線の円にした。
長さ 0 の線の扱いは、RIP によって描かれないことがあると言われている（確かめた資料はない）。
ベジエの円は、どの RIP でも同じ塗りとして扱われる。
円は 0.5523 の係数による近似であり、真の円とわずかに違う。

破線の割り付けを InDesign の既定の「線分と間隔を調整」にそろえたので、`dash` と `gap` はどちらも書いた値どおりにならない。
両端を線分で終えることを、長さを正確に保つことより優先した。
線分の数を四捨五入で決めるので、調整の量は線分と間隔の和の半分を超えない。

既定の値のうち、資料で確かめられたのは、破線の割り付けの方法と、点線の間隔（検索結果の要約による）だけである。
破線の既定の比、多重線の比、和文の点線の形、波線の形は、名前からの推定か、この ADR で決めた値である。
InDesign と並べて見る確かめ方を「自動テストにしない確かめ方」に置き、違いが大きければ別の ADR で改める。

`dash` と `gap` を `zw` で書けないことにした。
`weight` と同じく、線の見え方を字の大きさに合わせる理由がない。
既定を `weight` の倍数にしたので、太い罫線では線分と間隔も長くなる。

多重線の比と波線の形を固定した。
比を書けるようにすると、キーが増え、線の太さが 0 になる場合の検査も要る。

罫線の色の既定を、墨のスウォッチではなく「色を設定しない」にした。
既定を変えると、色を書かない本の PDF のバイト列が変わる。
色を設定しない描き方は DeviceGray の黒になり、墨一色で刷る本では墨の版に出る。

HTML と EPUB では、線の種類を CSS の `border-style` の 4 種に丸めるので、PDF と見え方が違う。
CSS の枠線には多重線の比も波線もなく、`dashed` と `dotted` の長さはエンジンが決めるためである。

## 参考文献

- ISO 32000-1:2008, Document management — Portable document format — Part 1: PDF 1.7, 8.5.2 Path Construction Operators, 8.5.3 Path-Painting Operators.
- W3C, CSS Backgrounds and Borders Module Level 3, 3.2 Line Patterns: the border-style properties. https://www.w3.org/TR/css-backgrounds-3/#border-style
- Adobe Community, "JS: how to create a dotted line". https://community.adobe.com/t5/indesign-discussions/js-how-to-create-a-dotted-line/m-p/8820513 。線の種類のスクリプトでの名前。
- CreativePro, "Setting a Dash Stroke with Exact Gap and Dash Values in InDesign". https://creativepro.com/setting-dash-stroke-exact-gap-dash-values-indesign/ 。「角」の既定が「線分と間隔を調整」であること。
- CreativePro, "Understanding Dotted Stroke Styles in InDesign". https://creativepro.com/understanding-dotted-stroke-styles-indesign 。組み込みの点線と和文の点線。本文は取得できず、検索結果の要約で読んだ。
- CreativePro, "Spaced out dots…". https://creativepro.com/spaced-out-dots/ 。太さ 1pt の点線の点の間隔。本文は取得できず、検索結果の要約で読んだ。
- Adobe, InDesign DOM, StrokeCornerAdjustment. https://developer.adobe.com/indesign/dom/api/s/StrokeCornerAdjustment 。`DASHES_AND_GAPS` の説明。
