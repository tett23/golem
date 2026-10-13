# ADR 0009: ルビの配置の設定

ステータス: 採択

## 文脈

ルビの配置は [ADR 0002](0002-japanese-composition.md) が定め、`style.toml` の `[composition]` の `ruby = { position = "mono-center", overhang = "1zw" }` で設定する。
`position` が取れる値は `"mono-center"` だけである（`Golem.Project.Style` の `RubyOpt`）。
[ADR 0002](0002-japanese-composition.md) は、この値でモノルビを親文字の中央にそろえ、グループルビを親文字の全体に均等に配置すると書いている。

今の実装は、この記述と一致していない。

- PDF の描画（golem-driver の `Pdf.hs` の `KindRuby`）は、読みを一続きの文字列として、箱の中央に置く。グループルビが親文字より短くても、読みの字間は空かない。
- ルビが親文字より長いとき、組み方（`Golem.Layout.Japanese` の `rubyPieces`）は親文字の箱を広げるが、描画は親文字を一続きの文字列として箱の中央に置く。親文字の字間は空かず、両端に空きができる。
- 隣の文字へのかけ（`overhang`）は、隣の文字の種類を見ない。コメントは仮名にかけると書いているが、`rubyPieces` は箱の幅を両側から `overhang` まで縮めるだけである。漢字にも、隣のルビにもかかる。
- そのため、モノルビを並べた `[ruby: 東/京|とう/きょう]` では、「きょう」が「東」の側に 1/4 字かかり、「とう」の「う」と重なる。「とう」は「東」の幅をちょうど使うので、空いている場所がない。
- 行頭と行末でもかけを戻さないので、行頭のルビは版面の外にはみ出す。
- 読みの幅は、組み方では読みの字数 × 親文字の大きさの半分で数え、描画では読みの文字列をシェイピングした幅で数える。仮名の読みでは一致するが、欧文の読みでは一致しない。

ユーザーの要望は、グループルビについて、ルビが親文字より短いときに読みの字間を空けて親文字の幅にそろえるか、詰めて中央に置くかを選べるようにすることである。
仕様書の「今後の実装項目」（[specifications.md](../../specifications.md)）は、ルビが長いときの隣の文字へのかけ方と、親文字の字間の空け方の設定も合わせて決めるとしている。

用語は、JLReq（Requirements for Japanese Text Layout）のルビの節に合わせる。

- **モノルビ**：親文字の一字ごとに振るルビ。
- **グループルビ**：複数の親文字のまとまりの全体に振るルビ。
- **熟語ルビ**：熟語の各字にモノルビとして振り、熟語の中では隣の親文字の空いている場所にかけることを許すルビ。
- **中付き**と**肩付き**：ルビが親文字より短いとき、ルビを親文字の中央に置くことと、親文字の始まりの側（縦組みでは上、横組みでは左）にそろえて置くこと。
- **1:2:1** と **0:1:0**：短い側の字間の空け方。字の間の空きを 2 とし、両端の空きを 1（または 0）とする比である。
- **ルビのかけ**：ルビが親文字より長いとき、はみ出す部分を隣の文字の上（縦組みでは右）に置くこと。

Golem の原稿では、`[ruby: 漢字|かんじ]` のように `/` を使わない場合がグループルビ、`[ruby: 東/京|とう/きょう]` のようにセグメントに分ける場合がモノルビである（[markup.md](../../markup.md)）。
意味論 IR の `Ruby` は `RubySegment` の列を持ち、セグメントが一つならグループルビ、複数ならモノルビとして扱っている。

## 実装すること

### style.toml の欄

`[composition]` の `ruby` を次の欄を持つ表にする。
今の `position` の欄はなくす。

```toml
[composition.ruby]
mono-align = "center"     # モノルビが親文字より短いとき
group-align = "1:2:1"     # グループルビが親文字より短いとき
base-spacing = "1:2:1"    # ルビが親文字より長いときの、親文字の字間
overhang = "0.5zw"        # 隣の文字へかける量の上限（片側）
overhang-onto = "kana"    # かけてよい隣の文字
```

| 欄 | 値 | 既定値 | 意味 |
|---|---|---|---|
| `mono-align` | `"center"`、`"start"` | `"center"` | モノルビが親文字より短いときの配置。中付きか肩付きか |
| `group-align` | `"1:2:1"`、`"0:1:0"`、`"center"`、`"start"` | `"1:2:1"` | グループルビが親文字より短いときの読みの配置 |
| `base-spacing` | `"1:2:1"`、`"0:1:0"`、`"center"` | `"1:2:1"` | ルビが親文字より長いときの、親文字の字間の空け方 |
| `overhang` | 寸法 | `"0.5zw"` | 片側で隣の文字にかける量の上限。`zw` は段落の文字の大きさで数える（今と同じ） |
| `overhang-onto` | `"kana"`、`"none"` | `"kana"` | `"kana"` は仮名にだけかける。`"none"` はかけない |

- `group-align` の値の意味は次のとおりとする。`"1:2:1"` は読みの字の間に等しい空きを入れ、両端にその半分を置く。`"0:1:0"` は読みの最初と最後の字を親文字の両端にそろえ、残りを字の間に等しく配る。`"center"` は読みを詰めて中央に置く。`"start"` は詰めて親文字の始まりにそろえる。
- 読みが一字のときは、`"1:2:1"` と `"0:1:0"` は `"center"` と同じ配置になる。
- `base-spacing` の値の意味は、上の読みを親文字に置き換えたものである。
- 読みの字間を空けて親文字の幅にそろえるというユーザーの要望は `"0:1:0"` に、JLReq がグループルビに使う配置は `"1:2:1"` に、今の描画は `"center"` に当たる。
- 寸法の値が負の場合と、列挙にない値は G0306 とする。`enumKey` と `parseStyle` の `checks` で検査する。`position` の欄は未知の欄として G0306 になる。
- 五つの欄はどれも省ける。省いた欄は既定値になる。`[composition.ruby]` の表そのものを省けば、すべての欄が既定値になる。

### 既定値の根拠

既定値は、JLReq のルビの節が一般的な処理として示す組み方に合わせる。
各既定値が当たる規則は次のとおりである。

- `mono-align = "center"`：JLReq は、モノルビの読みが親文字より短いとき、読みを親文字の中央に置く中付きを一般的な処理とし、肩付きを縦組みの一部で使う別の処理としている。
- `group-align = "1:2:1"`：JLReq は、グループルビの読みが親文字より短いとき、読みの両端の空きと字の間の空きを 1:2:1 の比で配ることを一般的な処理としている。
- `base-spacing = "1:2:1"`：JLReq は、ルビが親文字より長くかけで収まらないとき、親文字の両端の空きと字の間の空きを 1:2:1 の比で配ることを一般的な処理としている。
- `overhang = "0.5zw"`：JLReq は、隣の文字にかける量の上限をルビの一字分としており、ルビの文字の大きさを親文字の半分とする Golem では親文字の半字に当たる。
- `overhang-onto = "kana"`：JLReq は、ルビを仮名にはかけてよく、漢字にはかけないことを一般的な処理としている。

JLReq は、片側だけでかけることと、句読点などの約物にかけることも許している。
この ADR はその二つを実装しない（「実装しないこと」を参照）ので、既定値の組み方は、JLReq の一般的な処理よりかけが少なく、親文字の字間が空く場合がある。

`Golem.Project.Style` の `Composition` の `compRubyOverhang :: Dim` を、次の型の `compRuby :: RubyStyleDef` に置き換える。

```haskell
data RubyStyleDef = RubyStyleDef
  { rdMonoAlign :: !Text,      -- "center" | "start"
    rdGroupAlign :: !Text,     -- "1:2:1" | "0:1:0" | "center" | "start"
    rdBaseSpacing :: !Text,    -- "1:2:1" | "0:1:0" | "center"
    rdOverhang :: !Dim,
    rdOverhangOnto :: !Text    -- "kana" | "none"
  }
```

### モノルビとグループルビの区別

組み方と HTML の出力で、次のように区別する。

- セグメントが二つ以上の `Ruby` は、各セグメントをモノルビとする。
- セグメントが一つで、親文字が一字の `Ruby` もモノルビとする。`[ruby: 字|じ]` のように一字に振るルビは、原稿の上でグループルビとモノルビの区別がなく、JLReq ではモノルビに当たるためである。
- セグメントが一つで、親文字が二字以上の `Ruby` はグループルビとする。

親文字の字数は、`rubyPieces` の `plain` で得た文字列の書記素ではなく文字（`Char`）で数える。

### 配置の計算

`modules/golem-layout/src/Golem/Layout/Ruby.hs` を加え、ルビの箱の幅と、箱の中の親文字と読みの各字の位置を計算する純粋な関数を置く。
組み方（箱の幅）と PDF の描画（各字の位置）が同じ関数を使い、両者の食い違いをなくす。

```haskell
data RubyAlign = Align121 | Align010 | AlignCenter | AlignStart
  deriving stock (Eq, Show)

data RubyStyle = RubyStyle
  { rsMonoAlign :: !RubyAlign,
    rsGroupAlign :: !RubyAlign,
    rsBaseSpacing :: !RubyAlign,
    rsOverhang :: !Sp,
    rsOverhangOntoKana :: !Bool
  }
  deriving stock (Eq, Show)

defaultRubyStyle :: Sp -> RubyStyle  -- 段落の文字の大きさから。overhang はその半分

data RubyKind = MonoRuby | GroupRuby
  deriving stock (Eq, Show)

data RubyPlacement = RubyPlacement
  { rpWidth :: !Sp,        -- 箱の幅
    rpOverhang :: !Sp,     -- 両側にかける量（左右で等しい）
    rpBase :: ![Sp],       -- 親文字の各字の、箱の始まりからの位置
    rpReading :: ![Sp]     -- 読みの各字の位置。かける場合は最初の字が負になる
  }
  deriving stock (Eq, Show)

-- | 親文字の各字の送り、読みの各字の送り、両側でかけてよい量から配置を決める。
placeRuby :: RubyStyle -> RubyKind -> [Sp] -> [Sp] -> (Sp, Sp) -> RubyPlacement
```

`B` を親文字の送りの和、`R` を読みの送りの和、`(a, b)` を始まりの側と終わりの側でかけてよい量とする。

1. `R <= B` の場合、箱の幅は `B`、かけは 0 とする。親文字は詰めて 0 から置き、読みは `B` の幅の中に、モノルビなら `rsMonoAlign`、グループルビなら `rsGroupAlign` で配る。
2. `R > B` の場合、かけを `o = minimum [a, b, (R - B) `div` 2]` とし、箱の幅を `W = max B (R - 2 * o)` とする。読みは `-(R - W) / 2` から詰めて置き、親文字は `W` の幅の中に `rsBaseSpacing` で配る。

かけを両側で等しくするのは、読みの中心を親文字の中心にそろえる（中付き）ためである。
片側だけがかけられる場合（片側が漢字の場合）は、かけない。

幅 `L` の中に、送りの和が `S` の `n` 字を配る規則は次のとおりとする。
空き `E = L - S` とする。

| 値 | 最初の字の位置 | 字の間の空き |
|---|---|---|
| `Align121` | `E / (2n)` | `E / n` |
| `Align010`（`n >= 2`） | 0 | `E / (n - 1)` |
| `AlignCenter`、`Align010`（`n = 1`） | `E / 2` | 0 |
| `AlignStart` | 0 | 0 |

各字の位置は有理数で計算し、字ごとに一度だけ切り捨てて sp にする。
`placeLine` と同じく、丸めの誤差を字ごとに積み上げないためである。

### 隣の文字とかけてよい量

`rubyPieces` は今、ルビの幅を決めて `PBox` を作る。
これを、親文字と読みと種類を持つ新しい部品 `PRuby` に変え、幅は `itemsFor` で隣の部品を見て決める。
`itemsFor` は隣の部品を受け取っているが、今は使っていない。

```haskell
data Piece
  = ...
  | PRuby !Look !RubyKind !Text !(Maybe Text)  -- 親文字、読み（部分ルビでは Nothing）
```

隣の部品は、`PAnchor` を飛ばして探す。
片側でかけてよい量は、その側の隣の部品によって次のように決める。

| 隣の部品 | かけてよい量 |
|---|---|
| 圏点のない平仮名、片仮名、小書きの仮名、長音記号の `PChar` | `min rsOverhang (その字の送り / 2)` |
| 読みのない `PRuby`（部分ルビ）で、接する親文字が上の仮名 | 同じ |
| 読みのある `PRuby`（モノルビの隣のセグメント） | `min rsOverhang (隣の読みの、こちら側の空き)` |
| それ以外（漢字、欧文、約物、縦中横、圏点のある字、段落の端） | 0 |

- `overhang-onto = "none"` なら、どの隣でも 0 とする。
- 隣の字の送りの半分を上限にするのは、仮名の両側にルビがかかる場合に、二つの読みが重ならないようにするためである。
- 隣のセグメントの読みの空きは、隣のセグメントを `placeRuby` で置いたときの、こちら側の端の空きとする。読みが親文字より長い隣では 0 になる。これで `[ruby: 東/京|とう/きょう]` の重なりがなくなり、`[ruby: 東/京|ひ/きょう]` のように隣の読みが短い場合は、その空きにかけられる。JLReq の熟語ルビの規則のうち、隣の親文字の空いている場所にかける部分だけを実装する。
- 圏点のある字を除くのは、圏点がルビと同じ側に置かれるためである。

### 行頭と行末のかけを戻す

かけは隣の文字があって初めて成り立つ。
ルビの箱が行頭に来ると始まりの側の隣は前の行にあり、行末に来ると終わりの側の隣は次の行にある。
その側のかけを戻し、読みが版面の外に出ないようにする。

`Golem.Layout.KnuthPlass` の `BoxContent` に二つの欄を加える。

```haskell
    -- | 行頭（行末）に来たときに、行の内側に足す空き。ルビのかけを戻す量（ADR 0009）
    bcEdgeStart :: !Sp,
    bcEdgeEnd :: !Sp,
```

- `evaluate` と `mkLine` は、行の最初の箱の `bcEdgeStart` と最後の箱の `bcEdgeEnd` を、行の自然な幅に加える。今の突き出し（`protrusionOf`）と同じ位置で計算するが、`pProtrusion` によらず常に効かせる。
- `Line` に `lineEdge :: !(Sp, Sp)` を加え、`placeLine` は最初の箱の位置を `bcEdgeStart` だけ後ろにずらす。`glueRatio` の自然な幅にも加える。
- ルビの箱は、`bcEdgeStart` と `bcEdgeEnd` を `rpOverhang` にする。ほかの箱は 0 とする。

行頭のルビは、読みが行頭にそろい、親文字が `rpOverhang` だけ後ろに下がる。
行末も同じである。

### 組み方の変更

`Golem.Layout.Japanese` を次のように直す。

- `ComposeEnv` の `ceRubyOverhang :: Sp` を `ceRuby :: RubyStyle` に置き換える。`defaultComposeEnv fs` は `defaultRubyStyle fs` を使う。
- 親文字と読みの各字の送りは `advance env` で測る。読みは、親文字の見た目の大きさを半分にした見た目（`lk {lkSize = lkSize lk `div` 2}`）で測る。描画と同じ測り方にするためである。
- モノルビのセグメントの間には、今と同じく `Penalty 0 0` を置く。
- `BoxContent` の `bcText` は、今と同じく `親文字|読み` とする。描画が種類を知る必要があるので、モノルビの箱は `bcTag` を `KindRuby`、グループルビの箱は新しい `KindGroupRuby` にする。`normalize` の `firstClass` と `lastClass` は、両方を今の `KindRuby` と同じく扱う。

### PDF の描画

golem-driver の `Pdf.hs` の `KindRuby` の描画を、`placeRuby` の結果で親文字と読みを一字ずつ置く形に変える。

- 描画は、箱の幅 `w`、親文字と読みの各字の送りから `placeRuby` を呼び直す。かけてよい量は、`R > w` なら `((R - w) / 2, (R - w) / 2)`、そうでなければ `(0, 0)` を渡す。組み方の決めた幅が、そのまま同じ配置になる。
- 各字の位置は、箱の位置（`placeLine` が行頭のかけを戻した後の位置）に `rpBase` と `rpReading` の値を足したものである。
- 縦組みでも、行の方向の位置に同じ値を使う。

`RubyStyle` は、`style.toml` の `compRuby` から `Pdf.hs` の `ComposeEnv` を作るところで作る。
`zw` は今と同じく段落の文字の大きさ（`dimToSp fs`）で sp にする。

### HTML と EPUB

HTML の `<ruby>` の出力（`Golem.Html` の `Ruby`）に、モノルビなら `class="mono"` を付ける。
`css` に次の規則を加え、`HtmlConfig` に `hcRubyMonoAlign`、`hcRubyGroupAlign`、`hcRubyBaseSpacing :: Text` を加える。

```css
ruby { ruby-align: <base-spacing>; }
rt { ruby-align: <group-align>; }
ruby.mono rt { ruby-align: <mono-align>; }
```

値は次のように写す。

| style.toml の値 | CSS の `ruby-align` |
|---|---|
| `"1:2:1"` | `space-around` |
| `"0:1:0"` | `space-between` |
| `"center"` | `center` |
| `"start"` | `start` |

CSS の `ruby-align` は、ルビの親文字と読みのうち短いほうの中の配置を決め、親文字と読みのそれぞれに指定できる。
`ruby` に指定した値は親文字の匿名の箱に継承され、`rt` に指定した値は読みに効く。
初期値は `space-around` であり、`ruby-align` に対応しない読者の環境では、既定値の `"1:2:1"` と同じ配置になる。

かけ（`overhang` と `overhang-onto`）は、HTML と EPUB では表さない。
今の CSS Ruby の仕様の草案には、作者がかけの量を指定するプロパティがなく、かけるかどうかは読者の環境が決める。

EPUB は HTML と同じシリアライザを使うので、同じ CSS が入る。
テキストの出力（`golem-text`）は変えない。

### ドキュメント

- 仕様書の「今後の実装項目」から「ルビの配置の設定」の項目を消す。
- 仕様書の `style.toml` の例の `ruby = { position = "mono-center", overhang = "1zw" }` を、`[composition.ruby]` の表に書き換え、各欄の説明を加える。
- 仕様書の Web 経路の説明に、`ruby-align` で配置を表し、かけは表さないことを書く。
- [ADR 0002](0002-japanese-composition.md) のステータスを「採択→ルビの配置は [ADR 0009](0009-ruby-placement.md)」に変える。
- 用語集の「ルビ」に、熟語ルビ、中付き、肩付き、ルビのかけを加える。

## 実装しないこと

- JLReq の熟語ルビの規則のうち、熟語の全体の読みが親文字より長い場合にグループルビとして配置し直すこと。隣のセグメントの空いている場所にかけることだけを実装する。
- 片側だけでかけること。片側が漢字なら、もう一方の側が仮名でもかけない。
- 約物（括弧、句読点）の字面の外の空きにかけること。約物の空きは行の調整で詰められるので、かけた量が行の調整と干渉する。
- 行頭と行末で、親文字を行の端にそろえる配置（JLReq の行頭と行末のルビの規則）。行の端ではかけを戻すだけとする。
- ルビの文字の大きさ（親文字の半分）と、ルビを置く側（横組みで上、縦組みで右）の設定。
- 原稿の中で、一つのルビごとに配置を指定する記法。
- 両側ルビ、ルビの中の圏点、ルビの行送りへの影響の調整。
- HTML と EPUB でのかけの指定。

## テスト設計

実装の前に書き、失敗することを確かめる。

### placeRuby（`modules/golem-layout/test/Main.hs`）

文字の大きさを 1000sp とし、親文字の一字の送りを 1000、読みの一字の送りを 500 とする。

- 親文字三字（`B = 3000`）、読み二字（`R = 1000`）のグループルビ：`rpReading` が、`Align121` で `[500, 2000]`、`Align010` で `[0, 2500]`、`AlignCenter` で `[1000, 1500]`、`AlignStart` で `[0, 500]` になる。どれも `rpWidth` が 3000、`rpBase` が `[0, 1000, 2000]` である。
- 読みが一字のグループルビ：`Align121` と `Align010` が `AlignCenter` と同じ位置になる。
- 親文字一字、読み一字のモノルビ：`rsMonoAlign` が `AlignCenter` なら `[250]`、`AlignStart` なら `[0]` になる。
- 親文字二字（2000）、読み六字（3000）、かけてよい量 `(500, 500)`：`rpOverhang` が 500、`rpWidth` が 2000、`rpReading` の最初が −500、`rpBase` が `[0, 1000]` である。
- 同じ親文字と読みで、かけてよい量 `(250, 250)`：`rpWidth` が 2500、`rpReading` の最初が −250 であり、`rpBase` が `Align121` で `[125, 1375]`、`Align010` で `[0, 1500]`、`AlignCenter` で `[250, 1250]` である。
- かけてよい量 `(500, 0)`：`rpOverhang` が 0、`rpWidth` が 3000 である。
- 任意の送りの列とかけてよい量で、`rpWidth >= B`、`rpWidth >= R - 2 * rpOverhang`、`rpBase` と `rpReading` が単調増加で、最後の親文字の右端が `rpWidth` 以下であることを、プロパティテストで確かめる。

### 組み方（`modules/golem-layout/test/Main.hs`）

`defaultComposeEnv 1000` を使い、ルビの箱の幅を `boxKind` で取り出す。

- 「の[ruby: 字|あいう]の」：箱の幅が 1000、`bcEdgeStart` と `bcEdgeEnd` が 250 である。
- 「漢[ruby: 字|あいう]の」：左が漢字なので、箱の幅が 1500、かけが 0 である。
- 「[kenten: の][ruby: 字|あいう]の」：左が圏点のある字なので、箱の幅が 1500 である。
- `overhang-onto` が `none` に当たる `RubyStyle` で「の[ruby: 字|あいう]の」：箱の幅が 1500 である。
- 「の[ruby: 東/京|とう/きょう]の」：箱の幅が `[1000, 1500]` である。「京」の左の「東」の読みに空きがないため、今の実装の `[1000, 1000]` から変わる。
- 「の[ruby: 東/京|ひ/きょう]の」：箱の幅が `[1000, 1000]` であり、「京」のかけが 250 である。
- 欧文の読み「[ruby: 字|ab]」の箱の幅が、`ceAdvance` で測った読みの幅から決まる（字数 × 500 ではない）。
- 既存の「ruby wider than its base overhangs, then widens the base」を、`ceRuby` を使う形に書き換える。

### 行頭と行末（`modules/golem-layout/test/Main.hs`）

- `bcEdgeStart = 3` の箱が行頭に来る並びで、`placeLine` の最初の箱の位置が 3 であり、行の幅の計算に 3 が含まれる（行が目標の行長に収まる）。
- 同じ箱が行の途中にあるときは、位置がずれない。
- 行末の `bcEdgeEnd` も同じく確かめる。
- `pProtrusion = False` でも上の三つが成り立つ。

### style.toml（`modules/golem-project/test/Main.hs`）

- `[composition.ruby]` の五つの欄を読み、`RubyStyleDef` になる。欄がなければ既定値になる。
- `group-align = "justify"`、`mono-align = "1:2:1"`、`overhang = "-1zw"` が G0306 になる。
- `position = "mono-center"` が G0306 になる。仕様書の例の文字列を使う既存のテストを、新しい表に書き換える。

### PDF（`modules/golem-driver/test/Main.hs`）

- 横組みで「[ruby: 五月雨|さみだれ]」を含む段落を、`group-align` を `"1:2:1"` と `"center"` にして二回組む。読みの四字のテキストの位置を内容のストリームから読み出し、`placeRuby` の値と一致すること、二つの PDF で位置が異なることを確かめる。
- 行頭にルビが来る段落で、読みの最初の字の位置が版面の始まりより前にないことを確かめる。

### HTML（`modules/golem-driver/test/Main.hs` の HTML の golden）

- `[ruby: 組/版|くみ/はん]` が `<ruby class="mono">` で出力される。golden の `html-01.xhtml` を更新する。
- `[ruby: 五月雨|さみだれ]` が `class` のない `<ruby>` で出力される。
- `style.css` に、既定値で `ruby { ruby-align: space-around; }`、`rt { ruby-align: space-around; }`、`ruby.mono rt { ruby-align: center; }` が含まれ、`group-align = "0:1:0"` で `rt { ruby-align: space-between; }` になる。

### 自動テストにしないもの

実装の後、`modules/golem-driver/test/fixtures/kanikosen/` の原稿を縦組みで組み、`[ruby: 蝸牛 | かたつむり]`（長い読み）、`[ruby: 煙草 | たばこ]`（親文字と同じ長さ）、`[ruby: 巾 | はば]`（一字の親文字に二字の読み）が、読みと親文字の重なりなく置かれていることを目で確かめる。
`group-align` の四つの値で同じ原稿を組み、違いを見比べる。

## トレードオフ

既定値を JLReq に合わせ、`group-align` と `base-spacing` を `"1:2:1"`、`overhang` を `"0.5zw"` にする。
今の PDF は、グループルビの読みを詰めて中央に置き、かけの上限を一字としているので、既定値のままでも、ルビを含む既存のプロジェクトの PDF の出力が変わる。
この出力の変化は受け入れる。
v1 のリリースの前であり、今の配置は [ADR 0002](0002-japanese-composition.md) の記述とも一致していないので、既定値を今の描画に合わせて残す理由がない。
今の描画に近い組み方が要る利用者は、`group-align = "center"` と `base-spacing = "center"` を指定する。
かけの上限を親文字の一字から半字に下げるのは、ルビの文字の大きさを親文字の半分としているので、半字がルビの一字に当たるためである。

かけを両側で等しくするので、片側が漢字の場合はもう一方が仮名でもかけず、親文字の字間が空く。
片側だけかける組み方は読みの中心が親文字の中心からずれ、中付きの原則と食い違う。
中心をそろえることを優先する。

`position` の欄をなくすので、今の仕様書の例をそのまま書いた `style.toml` は G0306 になる。
`position` が取れた値は `"mono-center"` だけで、配置を変える働きがなかった。
v1 のリリースの前なので、互換の別名を残さない。

HTML と EPUB では、`ruby-align` に対応しない読者の環境がある。
その環境では CSS の初期値（`space-around`）で表示され、既定値の配置と一致する。
既定値以外を選んだ場合に、PDF と画面で配置が異なることがある。
