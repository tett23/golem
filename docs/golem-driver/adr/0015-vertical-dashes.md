# ADR 0015: 縦組みで縦書き用の字形がない約物を回転して描く

ステータス: 採択

## 文脈

[仕様書](../../specifications.md)の「v1 の実装で次の段階以降に回した項目」は、縦組みの PDF でダッシュを回転させずに横棒のまま描いていることを挙げている。
『蟹工船』の `——漁夫は` で確かめた不具合である。
fixture の原稿のダッシュは `U+2014`（EM DASH）であり、`——` を含む行が 235 行ある。

### 今の実装でダッシュが横棒になる仕組み

組版と描画の経路を読み、fixture のフォント（Noto Serif JP）で HarfBuzz のシェイピングの結果を確かめた（golem-font を `cabal repl` で読み込んで調べた）。

組版（golem-layout）では、`Golem.Layout.Japanese.charClass` が `U+2014` を分離禁止文字（cl-08、`Inseparable`）に分類する。
`textPieces` は、`U+2014` の両隣の最も近い文字が和文なら一字ずつの `PChar` にし、欧文の文字が隣にあるときだけ欧文の単語に含める（[golem-layout ADR 0008](../../golem-layout/adr/0008-explicit-hyphens.md)）。
`——漁夫は` のダッシュは、二つとも一字の箱（`KindText`）になる。
縦組みで回転する箱（`KindRotated`）になるのは、欧文の文字（cl-27）と欧文の単語だけである。

描画（golem-driver）では、`Golem.Driver.Pdf.writeDocument` の `runAt` が、`KindText` の箱を縦組みの向きのまま描く。
`lfShape` に縦組みを指定し、`Golem.Driver.Fonts` が HarfBuzz の方向を上から下（`HB_DIRECTION_TTB`）にしてシェイピングする。
同梱の HarfBuzz は、縦の方向で OpenType の `vert` を有効にする（`hb-ot-shape.cc` が `vert` だけを有効にし、`vrt2` は有効にしない）。
得たグリフを、`Identity-V` のフォントで正立のまま描く。

つまり、縦組みの和文の文字が縦の形になるかどうかは、フォントの `vert` がその文字のグリフを置き換えるかどうかだけで決まる。
Noto Serif JP での結果は次のとおりである。

| 文字 | 横組みのグリフ（送り） | 縦組みのグリフ |
|---|---|---|
| `U+2014` EM DASH | 466（890） | 466（置き換えなし） |
| `U+2015` HORIZONTAL BAR | 467（1000） | 15282 |
| `U+2026` HORIZONTAL ELLIPSIS | 479（1000） | 15280 |
| `U+2025` TWO DOT LEADER | 478（1000） | 15281 |
| `U+301C` WAVE DASH | 1171（1000） | 17592 |
| `U+FF5E` FULLWIDTH TILDE | 1171（1000） | 17592 |
| `U+300C` 始めかぎ括弧 | 1155（1000） | 15298 |
| `U+30FC` 長音記号 | 1392（1000） | 17777 |

送りの単位は、1000 を全角とするフォントの単位である。
`U+2014` だけが、横組みの送りが全角より狭いプロポーショナルな字形で、`vert` による置き換えを持たない。
Golem は縦書き用の字形がない和文の文字を回転させないので、`U+2014` は横組みの字形のまま正立で描かれ、縦の行の中に横棒が並ぶ。
これが不具合の原因である。

Noto Serif JP（Source Han の系列）が `U+2014` を縦書き用の字形を持たないプロポーショナルな字形にしているのは、`U+2014` を欧文のダッシュとして設計し、縦組みでは組版の処理系が回転させることを前提にしているためと考えられる（推測であり、フォントの資料では確かめていない）。
`U+2015` を使えば Noto Serif JP では縦の字形になるが、原稿の書き手に符号位置を選ばせることはできない。
`U+2014` と `U+2015` のどちらを全角のダッシュに使うかは、原稿の出どころ（JIS の対応表の流儀）によって分かれている。

なお、`——` の二字を一緒にシェイピングすると、Noto Serif JP は横組みでも縦組みでもグリフ 1100（送り 1692）の一つにする。
Golem は和文の文字を一字ずつの箱にしてシェイピングするので、この合字は今も使われていない。

### Unicode の縦組みの向き

Unicode の UAX #50 は、文字ごとに縦組みでの向き（Vertical_Orientation）を定める。
値は、正立（U）、回転（R）、縦書き用の字形があれば使い、なければ正立（Tu）、縦書き用の字形があれば使い、なければ回転（Tr）の四つである。
Unicode の最新の `VerticalOrientation.txt` で、次の値を確かめた。

| 範囲 | 値 | 文字 |
|---|---|---|
| `U+2010` から `U+2015` | R | ハイフン、ダッシュ |
| `U+2022` から `U+2027` | R | 三点リーダー、二点リーダーを含む |
| `U+2E3A`、`U+2E3B` | R | 二倍と三倍のダッシュ |
| `U+FF0D` | R | 全角のハイフンマイナス |
| `U+3008` から `U+3011`、`U+FF08`、`U+FF09` | Tr | 括弧類 |
| `U+301C`、`U+FF5E` | Tr | 波ダッシュ、全角のチルダ |
| `U+30FC` | Tr | 長音記号 |
| `U+3001`、`U+3002` | Tu | 読点、句点 |
| `U+FE31`、`U+FE32` | U | 縦書き用のダッシュの表示形 |

`U+2014` は R であり、縦組みでは回転させる文字である。

### 縦組みの HTML

golem-html は、縦組みの本の `body` に `writing-mode: vertical-rl` を指定し、`text-orientation` は指定しない（`Golem.Html` の CSS、[golem-html ADR 0001](../../golem-html/adr/0001-xhtml-serializer.md)）。
`text-orientation` の既定は `mixed` である。
CSS Writing Modes Level 3 の `mixed` は、UAX #50 の値に従って文字の向きを決める（記憶による整理で、本文の節は確かめていない）。
R は回転、U と Tu は正立、Tr は縦書き用の字形がフォントにあれば正立でそれを使い、なければ回転する。
したがって、ブラウザと EPUB のリーダーは、`U+2014` を回転させて縦の線として表示する。
縦組みの HTML と PDF で、`——` の見え方が食い違っている。

### JLReq と InDesign

JLReq は、縦組みでダッシュ、リーダー、括弧類、波ダッシュなどを、横組みの字形を 90 度回した形（または縦書き用の字形）で組むとする（記憶による。JLReq の該当の節は確かめていない）。

InDesign は縦組みで OpenType の縦書き用の字形を使う。
縦書き用の字形がないプロポーショナルな和文の約物を InDesign が回転させるかどうかは、確かめた資料がない。
Noto Serif JP の `U+2014` を InDesign の縦組みで組んだときの挙動は、手作業の確認で調べる（テスト設計を参照）。

## 実装すること

縦組みの和文の文字の向きを、次の順で決める。

1. 縦組みでシェイピングしたグリフが、横組みでシェイピングしたグリフと異なる（フォントの `vert` が置き換えた）なら、縦書き用の字形を正立で描く。今の挙動である。
2. 置き換えがなく、UAX #50 の値が R か Tr なら、横組みの字形を時計回りに 90 度回転して描く。
3. それ以外（U と Tu）は、今のとおり正立で描く。

ダッシュ、リーダー、波ダッシュ、括弧類を名指しの一覧にはしない。
JLReq が縦組みで回す文字は、UAX #50 の R か Tr に含まれており、UAX #50 の値で決めれば HTML の `text-orientation: mixed` と同じ規則になるためである。
欧文の文字と欧文の単語（cl-27 と、欧文の単語に含まれるダッシュ）は、今のとおり単語ごとに回転して組み、この規則の対象にしない。

### 縦組みの向きの表（golem-layout）

- `Golem.Layout.Orientation` を加え、次の型と関数を公開する。

```haskell
-- | Vertical_Orientation of UAX #50.
data Orientation = Upright | Rotated | TransformedUpright | TransformedRotated
  deriving stock (Eq, Show)

verticalOrientation :: Char -> Orientation

-- | R and Tr: turned 90° clockwise when the font has no vertical form.
turnsInVertical :: Char -> Bool
```

- 表は、Unicode の `VerticalOrientation.txt` の全範囲を、符号位置の昇順の範囲のリストとして Haskell のソースに持ち、二分探索で引く。ファイルに記載のない符号位置は、ファイルの冒頭の注釈が定める既定値に従う。
- 表は `scripts/` に置くシェルスクリプト（`scripts/gen-vertical-orientation.sh`、POSIX の `sh` と `awk` で書く）で `VerticalOrientation.txt` から生成し、生成したソースをコミットする。スクリプトはファイルのパスを引数に取り、ネットワークに接続しない。表の元にした Unicode の版をソースの注釈に書く。
- 実装の時点の Unicode の最新の版を使う。版を上げるときは、表を生成し直し、テストの期待値を確かめる。依存を増やさず、表を再実装する。UAX #50 のデータは Unicode のライセンスで利用でき、表の生成は短いスクリプトで済むためである。

### 回転するグリフの判定（golem-font と golem-driver）

- golem-font の C の層に `int golem_font_embox_central(golem_font *f)` を加え、`Golem.Font` に `fontEmBoxCentral :: Font -> Int` を公開する。値は `hb_ot_layout_get_baseline_with_fallback` の `HB_OT_LAYOUT_BASELINE_TAG_IDEO_EMBOX_CENTRAL`（横の方向、文字体系 `hani`）で得る、ベースラインから仮想ボディの中心までの高さ（フォントの単位）である。`BASE` の表がないフォントでは、HarfBuzz の代替の計算に任せる。
- `Golem.Driver.Pdf` に、シェイピングの結果のグリフを表す型を置き、`LoadedFonts` の `lfShape` の結果をこの型のリストに変える。

```haskell
data Shaped = Shaped
  { shFace :: !Int,
    shGlyph :: !Int,
    -- | the advance in em along the line
    shAdvance :: !Rational,
    -- | the text the glyph stands for
    shText :: !Text,
    -- | drawn turned 90° clockwise in vertical text (golem-driver ADR 0015)
    shTurned :: !Bool
  }
```

- `LoadedFonts` に `lfEmBoxCentral :: Int -> Rational` を加える。フォントの番号から、仮想ボディの中心の高さを em で返す（`fontEmBoxCentral` をフォントの単位の 1em で割った値）。
- `Golem.Driver.Fonts.shapeText` は、縦組みのとき、和文の連なりを縦と横の両方でシェイピングし、クラスタ（文字列のバイトの位置）ごとにグリフの列を比べる。縦と横でグリフの列が同じで、クラスタの先頭の文字が `turnsInVertical` を満たすなら、そのクラスタを横組みのグリフと横組みの送りで返し、`shTurned` を真にする。それ以外のクラスタは、今のとおり縦組みのグリフと縦の送りで返し、`shTurned` を偽にする。
- 欧文の連なり（`fontFor` が欧文のフォントを選んだ連なり）と横組みのシェイピングでは、`shTurned` は常に偽とする。
- `lfAdvance` と `lfWordAdvance` は変えない。どちらも横組みでシェイピングした送りを返すので、組版の箱の幅は、回転して描くグリフの送りと一致する。

### 回転するグリフの描き方（`Golem.Driver.Pdf`）

- `runAt` は、縦組みで回転しない箱を描くとき、`shTurned` が真のグリフを、横組みのフォント（`ref ix False`）の `P.RotatedGlyphRun` で描く。グリフの原点は `(x0 - c, y0 - off)` とし、`c` は `lfEmBoxCentral ix` に文字の大きさを掛けて sp に丸めた値とする。回転したグリフの仮想ボディの中心が、縦の行の中心線に重なる。
- 合成の斜体と太字（[ADR 0004](0004-pdf-emphasis-and-character-styles.md)、[ADR 0012](0012-synthetic-bold-weight.md)）がかかるときは、`P.StyledGlyphRun` の `rsRotated` を真にし、フォントを横組みのものにする。
- `byFont` の分類の鍵に `shTurned` を加え、回転するグリフと正立のグリフを別の内容の列にまとめる。
- 使ったグリフの一覧（埋め込みと ToUnicode の入力）には、回転するグリフを横組みのフォントの側で加える。
- 欧文の回転（`KindRotated` の箱と、行末のハイフン）の原点のずらし方（文字の大きさの 3/10）は変えない。

ルビの文字、圏点の付いた文字、縦中横の外の文字も `runAt` を通るので、同じ規則で描かれる。
縦中横の中の文字は横組みでシェイピングするので、対象にならない。

### HTML と EPUB

golem-html の CSS は変えない。
`text-orientation` の既定の `mixed` が UAX #50 に従うので、`U+2014` は今も回転して表示されている。
この ADR の PDF の規則と HTML の規則は、R と Tr の文字のうちフォントに縦書き用の字形がないものを回転させる点で一致する。
異なるのは、R の文字にフォントの縦書き用の字形がある場合（Noto Serif JP の `U+2015`、`U+2025`、`U+2026`）である。
PDF はフォントの縦書き用の字形を使い、HTML は CSS の定めのとおり横組みの字形を回転させる。
どちらも縦の線と縦に並んだ点として表示され、字形の細部と位置だけが異なりうる。

### 決定性

- 向きは、文字、UAX #50 の表、フォントのバイト列（`vert` の有無）だけで決まる。
- 回転の原点は、整数の sp と、フォントの単位からの有理数を一度だけ丸めた値で決める。

### ドキュメント

- 仕様書の「v1 の実装で次の段階以降に回した項目」の「PDF」から「縦組みのダッシュ」の項目を除く。
- 仕様書の「フォント」の節の、縦書き用の字形を既定で有効にする文の後に、縦書き用の字形がない文字のうち UAX #50 で R か Tr のものを、PDF では横組みの字形を回転して描き、HTML と EPUB では CSS の `text-orientation: mixed` に任せることを書き、この ADR へのリンクを付ける。
- 用語集に、UAX #50 の縦組みの向き（Vertical_Orientation）を加える。
- [golem-layout ADR 0002](../../golem-layout/adr/0002-japanese-composition.md) のステータスの行に「、縦書き用の字形がない文字の回転は [golem-driver ADR 0015](../../golem-driver/adr/0015-vertical-dashes.md)」を加える。リンクは書き込む先のファイルからの相対パスである。

### 診断

新しい診断は加えない。

## 実装しないこと

- `vrt2` を有効にすること。同梱の HarfBuzz は縦の方向で `vert` だけを有効にする。`vrt2` は、プロポーショナルな字形を回転した字形に置き換える機能を含むことがあり、この ADR の回転と二重にかかるおそれがある。
- `U+2014` を `U+2015` に置き換えるような、原稿の文字の書き換え。
- 和文の `——` を一つの箱にして、フォントの二倍のダッシュの合字（Noto Serif JP のグリフ 1100）を使うこと。和文の文字を一字ずつ箱にする組版の構造を変える必要がある。
- 回転するダッシュの送りを全角にそろえること。`U+2014` を回転して描くと、送りはフォントの横組みの送り（Noto Serif JP では 0.89 字）のままになる。
- 正立で描く縦組みのグリフの送りを、組版の箱の幅に反映させること。今の箱の幅は横組みの送りで決まる。プロポーショナルな縦の送り（`vpal`、`vhal`）とともに別の ADR で扱う。
- 欧文の回転の原点を仮想ボディの中心にそろえ直すこと。
- HTML と EPUB で `text-orientation` を指定すること。

## テスト設計

### golem-layout（`modules/golem-layout/test/Main.hs`）

- `verticalOrientation` が、文脈の表の文字で表の値を返すこと（`U+2014`、`U+2015`、`U+2026`、`U+2E3A` が `Rotated`、`U+301C`、`U+FF5E`、`U+300C`、`U+30FC` が `TransformedRotated`、`U+3001` が `TransformedUpright`、`漢`、`あ`、`U+FE31` が `Upright`）。
- 表の範囲が昇順で重ならないこと。
- 表に記載のない符号位置で、ファイルの既定値の規則のとおりの値を返すこと（CJK の統合漢字の未割り当ての符号位置と、それ以外の未割り当ての符号位置を一つずつ）。

### golem-font（`modules/golem-font/test/Main.hs`）

- Source Han Sans のサブセットの `fontEmBoxCentral` が、`fontExtents` の高さの範囲の中にあること。実装の時点で値を確かめ、その値を期待値として固定する。

### golem-driver（`modules/golem-driver/test/Main.hs`）

『蟹工船』の fixture の Noto Serif JP を使う。

- 縦組みの `lfShape` で、`U+2014` がグリフ 466、送り 890/1000、`shTurned` が真になること。
- 縦組みの `lfShape` で、`U+2015` がグリフ 15282、`U+2026` がグリフ 15280、`U+301C` がグリフ 17592、`、` が縦書き用の字形になり、どれも `shTurned` が偽になること。
- 縦組みの `lfShape` で、`漢` の `shTurned` が偽であること。横組みの `lfShape` では、どの文字でも `shTurned` が偽であること。
- 縦組みの小さなプロジェクトで `——漁夫は` を組んだ PDF の内容のストリームに、横組みのフォントの `0 -1 1 0` の文字の行列で、CID 722（グリフ 466、`<02D2>`）を描く行が二つあること。縦組みのフォント（`Identity-V`）の内容の列に `<02D2>` がないこと。横組みのフォントの ToUnicode が `<02D2>` を `U+2014` に対応させること。
- 同じ PDF で、回転したダッシュの原点の x 座標が、行の中心線から `lfEmBoxCentral` の分だけ左にあること。
- 『蟹工船』の PDF の内容のストリームに、`<02D2>` を `0 -1 1 0` の行列で描く行があること（既存の「縦組みで組める」のテストに加える）。
- HTML の CSS の golden（`test/golden/html-style.css`）が変わらないこと。
- `lfShape` の結果の型が変わるので、テストの `fakeFonts` を `Shaped` を返すように直す。

### 手作業の確認

- 『蟹工船』の PDF を開き、`——漁夫は` のダッシュが縦の線として行の中心に描かれることを確かめる。
- Noto Serif JP で `——漁夫は` を InDesign の縦組みで組んで書き出した PDF と見比べ、InDesign が `U+2014` を回転させるか、どの位置に置くかを記録する。食い違いがあれば、この ADR を改める ADR を作る。
- 同じ原稿の縦組みの HTML を Safari と Chrome で開き、`——`、`―`、`…`、`〜`、括弧類の向きが PDF と同じであることを確かめる。

## トレードオフ

フォントの縦書き用の字形を先に使うので、R の文字でも、フォントが縦書き用の字形を持てば回転させない。
UAX #50 の R を常に回転させれば HTML と字形まで一致するが、フォントの設計者が縦組みのために用意した字形を捨てることになる。
縦の字形と回転した字形は、どちらも縦の線や縦に並んだ点として読めるので、HTML との違いは字形の細部にとどまる。

回転を描画の段で決め、組版の箱の種類（`KindRotated`）は変えないので、禁則と約物の空きは今のとおり文字の分類で決まる。
その代わり、向きを決めるために、縦組みの和文の連なりを縦と横の二回シェイピングする。
シェイピングの回数が増える分だけ、縦組みの PDF のビルドが遅くなる。

`U+2014` を回転すると、二つ並べたダッシュの長さは、Noto Serif JP では全角二字分より短い 1.78 字になる。
全角二字分にそろえるには、送りを変えるか合字を使う必要があり、どちらも組版の箱の作り方を変える。
ダッシュの向きの不具合を直すことを先にし、長さは別に扱う。
