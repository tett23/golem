# ADR 0020: カーニングの方式、トラッキング、プロポーショナルメトリクス、ベースラインシフト

ステータス: 採択→和文のペアカーニングから除く一覧への分離禁止文字の追加は [golem-driver ADR 0020](../golem-driver/adr/0020-glyph-positioning-and-dash-kerning.md)、`palt` と `vpal` を約物に当てないことは [ADR 0053](0053-no-palt-on-jlreq-punctuation.md)

## 文脈

Golem が文字の送りに対して持つ設定は、フォントの役割ごとの OpenType の機能（`[fonts.<役割>]` の `features`）だけである（[specifications.md](../specifications.md) の「フォント」）。
今の実装（`Golem.Driver.Fonts` の `provide`）は、次のように文字の送りを測る。

- 欧文の語は、語の全体を HarfBuzz でシェイピングして幅を測る（`lfWordAdvance`）。HarfBuzz は既定で `kern` を有効にするので、語の中のペアカーニングは効く。語間の空白をまたぐペアと、明示のハイフンで分けた部分の間のペアには効かない（[golem-layout ADR 0008](../golem-layout/adr/0008-explicit-hyphens.md)）。
- 和文は、一字ずつシェイピングして送りを測る（`lfAdvance`）。役割の `features` に `palt` を書けば一字ごとの詰めは効くが、隣の字とのペアカーニングは効かない。
- 送りは、縦組みでも横書きの方向でシェイピングして測る（`shapeText role False`）。縦組みの詰め（`vpal`）とカーニング（`vkrn`）は測った幅に入らない。
- 機能は役割にだけ付くので、文字スタイルで一部の文字だけを詰めることはできない。

仕様書の「v1 の実装で次の段階以降に回した項目」は、InDesign が文字に対して持つ組版の機能を実装し、カーニングの方式（メトリクス、オプティカル、和文等幅、なし）を選べるようにし、既定をメトリクスとすると決めている。
トラッキング、プロポーショナルメトリクス、文字の比率（水平比率と垂直比率）、ベースラインシフトのうち、v1 で扱う範囲はこの ADR で決める。

### InDesign の機能

確かめた資料と、そこから分かったことは次のとおりである。
Adobe の InDesign のヘルプ（helpx.adobe.com）の該当するページは、取得を試みたが応答が 403 で、本文を読めなかった。
以下の Adobe のヘルプの内容は、検索エンジンの要約による。

- InDesign と InCopy のヘルプ「カーニングとトラッキング」（https://helpx.adobe.com/indesign/using/kerning-tracking.html 、https://helpx.adobe.com/jp/incopy/desktop/format-text/character-formatting/kerning-tracking.html ）：自動のカーニングにはメトリクスとオプティカルがある。メトリクスはフォントのカーニングペアを使い、既定である。オプティカルは隣り合う文字の形から間隔を決め、欧文のグリフ向けに作られている。メトリクスを止めるには「0」を選ぶ。カーニングとトラッキングの単位は全角の 1/1000 である。カーニングとトラッキングは和文にも効くが、通常は英数字の間隔の調整に使う。
- Adobe のコミュニティの回答（第三者）：メトリクスは、ペアの一方が別のフォント、斜体、太字、上付き、下付きの場合にはカーニングしない。和文のフォントでは、和字にカーニングとプロポーショナルメトリクスの情報があればメトリクスが効く。
- FONTPLUS DAY セミナーの記録（https://scrapbox.io/yamanoku/ 、第三者の覚え書き）：和文では、和文等幅とカーニング 0 は同じ結果にならない。

次のことは記憶によるものであり、資料では確かめていない。

- カーニングの方式の選択肢は「メトリクス」「メトリクス - 欧文のみ」「オプティカル」「和文等幅」「0」である。
- 和文等幅は、欧文にメトリクスのカーニングをかけ、和文を全角の送りのまま組む。
- プロポーショナルメトリクスは、OpenType の `palt`（縦組みでは `vpal`）を和文に適用する文字の属性である。
- 文字パネルは、ほかに水平比率、垂直比率、ベースラインシフト、文字回転、文字ツメ、文字前と文字後のアキ量を持つ。トラッキングの範囲は −1000 から 10000 である。
- トラッキングは、行の最後の文字の後ろにも空きを足す。

### 欄の置き場所

InDesign では、これらは文字の属性であり、文字スタイルと段落スタイルの両方が持つ。
Golem でも、文字スタイル（[docs/adr/0005](0005-character-and-paragraph-styles.md)）と段落スタイルの欄にする。
`body` はすべての段落スタイルの根なので、`[paragraph-styles.body]` に書けば本の全体の既定になる。
フォントの役割の欄にする案は、役割が書体のファイルの選択であり、同じ書体を詰める文字と詰めない文字に分けられないので採らない。

## 実装すること

### style.toml の欄（golem-project）

`[character-styles.<名前>]` と `[paragraph-styles.<名前>]` に次の欄を加える。

| キー | 型 | `body` の既定 | 意味 |
|---|---|---|---|
| `kerning` | `"metrics"`、`"japanese-equal-width"`、`"none"`、`"optical"` | `"metrics"` | カーニングの方式 |
| `tracking` | 整数 | 0 | 文字ごとに足す空き。単位は文字の大きさの 1/1000。−1000 から 10000 まで |
| `proportional-metrics` | 真偽値 | `false` | 和文に `palt`（縦組みでは `vpal`）を適用する |
| `baseline-shift` | 符号付きの寸法 | `"0pt"` | 文字を、横組みでは上へ、縦組みでは右へずらす量。`zw` はその文字の大きさで数える |

- `CharStyleDef` に `csKerning :: Maybe Kerning`、`csTracking :: Maybe Int`、`csProportional :: Maybe Bool`、`csBaselineShift :: Maybe Dim` を、`ParaStyleDef` に同じ四つ（`ps` で始まる名前）を加える。`overChar`、`overPara` と `paraStyle` の既定を合わせて直す。
- `data Kerning = KernMetrics | KernJapaneseEqualWidth | KernNone | KernOptical` を `Golem.Project.Style` に置く。
- `kerning = "optical"` は G03021（文字の送りの欄の誤り）とし、メッセージを「v1 ではオプティカルカーニングを使えません」とする。型には値を持たせ、読み込みの検査で拒む。
- `tracking` の範囲の外の値、`baseline-shift` の寸法として読めない値は G03021 とする。`baseline-shift` は `parseSignedDim` で読む。

| 診断コード | 重大度 | メッセージ |
|---|---|---|
| G03021 | エラー | `<欄> の値が正しくありません: <値>`（`kerning = "optical"` は `v1 ではオプティカルカーニングを使えません`） |

G03021 は未使用である。`style.toml` の一般の誤りの G03006 から、カーニング、トラッキング、ベースラインシフトの欄の誤りを分けて、どの欄の誤りかをコードで引けるようにする（提案中の ADR のあいだで、G03017 から G03022 を分けて割り当てた）。

- ファイルの中の文字スタイルと段落スタイルの定義（[docs/adr/0014](0014-in-file-settings.md)）でも、同じ欄を書ける。

方式の意味は次のとおりとする。

| 方式 | 欧文 | 和文 |
|---|---|---|
| `metrics` | フォントのペアカーニング | フォントのペアカーニング |
| `japanese-equal-width` | フォントのペアカーニング | カーニングをかけず、`palt` と `vpal` を止める |
| `none` | カーニングをかけない | カーニングをかけない |

`japanese-equal-width` は、役割の `features` に `palt` があっても、`proportional-metrics` が真でも、和文を全角の送りで組む。
和文の送りを字送りの格子にそろえたい本文のための方式である。
InDesign の「メトリクス - 欧文のみ」は加えない（「実装しないこと」）。

### Look と測り方（golem-layout、golem-driver）

`Golem.Layout.Look` の `Look` に次の欄を加える。
`plainLook` の既定は、`metrics`、0、偽、0 とする。

```haskell
data Kerning = KernMetrics | KernJapaneseEqualWidth | KernNone
  deriving stock (Eq, Ord, Show)

data Look = Look
  { ...
    lkKerning :: !Kerning,
    lkTracking :: !Int,        -- 1/1000 em
    lkProportional :: !Bool,
    lkBaselineShift :: !Integer -- sp
  }
```

golem-layout は golem-project に依存しないので、`Kerning` は `Look` の側にも定義し、golem-driver で写す。
`KernOptical` は読み込みの検査で拒むので、`Look` には現れない。

`Golem.Driver.Pdf` の `LoadedFonts` の測る関数を、役割の名前の代わりに次の値を受け取るように変える。

```haskell
data Shaping = Shaping
  { shRole :: !Text,
    shVertical :: !Bool,
    -- | 役割の features の後ろに足す機能
    shExtra :: ![Text]
  }
  deriving stock (Eq, Ord, Show)

data LoadedFonts = LoadedFonts
  { lfAdvance :: Shaping -> Char -> Rational,
    lfWordAdvance :: Shaping -> Text -> Rational,
    lfPairKern :: Shaping -> Char -> Char -> Rational,
    lfShape :: Shaping -> Text -> [(Int, Int, Rational, Text)],
    ...
  }
```

- `shapeText` は、役割の `features` の後ろに `shExtra` を足して HarfBuzz に渡す。後ろの機能が前の同じ機能を上書きするのは HarfBuzz の規則である。
- `lfPairKern s a b` は、二字の並びをシェイピングした送りの和から、一字ずつの送りの和を引いた値（全角を 1 とする）とする。`memo` の鍵に `Shaping` を含める。
- `shVertical` は、縦組みの段落の和文で真にする。今の横書きの方向での測り方を改め、`vpal` と `vkrn` を測った幅に入れる。縦組みの中で回転して組む欧文は、今と同じく横書きの方向で測る。
- `Golem.Driver.Pdf` に `shapingOf :: Bool -> Look -> Char -> Shaping` を加え、`ceAdvance`、`ceWordAdvance`、描画の `runAt` から使う。`shExtra` は次の規則で決める。
  - 欧文：`none` なら `["-kern"]`、ほかは `[]`。
  - 和文：`none` なら `["-kern", "-vkrn"]`。`japanese-equal-width` なら `["-kern", "-vkrn", "-palt", "-vpal"]`。`metrics` なら、`proportional-metrics` が真のとき横組みで `["palt"]`、縦組みで `["vpal"]`、偽のとき `[]`。`japanese-equal-width` 以外で `proportional-metrics` が真なら、`none` にも同じ機能を足す。
- `restyle` と `paraLook` は、スタイルの四つの欄を `Look` に写す。文字スタイルが書かない欄は外側の値を引き継ぐ。

### 組み方（golem-layout）

`ComposeEnv` に `ceKern :: Look -> Char -> Char -> Rational` を加え、`defaultComposeEnv` では常に 0 を返す。
`Golem.Layout.Japanese` を次のように直す。

- 和文のペアカーニング：`normalize` の `between` で、前後がどちらも和文の一字の箱（`KindText` か `KindKenten`）で、`bcLook` が等しく、`lkKerning` が `KernMetrics` で、どちらも約物（始め括弧類、終わり括弧類、句点類、読点類、中点類）でないとき、`k = ceKern look a b` を sp にして前の箱の幅に足し、同じ箱の `bcEdgeEnd` から引く。行末に来た箱では、次の字とのカーニングを数えない。約物を除くのは、約物の前後の空きを JLReq の規則（[docs/adr/0019](0019-aki-settings.md) のアキ量のセット）で決めるためである。
- トラッキング：`t = lkTracking * lkSize / 1000` を、和文の一字の箱の幅に `t`、欧文の語の箱の幅に `t` × 語の文字（Unicode のスカラー値）の数だけ足し、各箱の `bcEdgeEnd` から `t` を引く。語間の空白の `Glue` の幅にも `t` を足す。行の最後の文字の後ろの空きは、行分割の幅にも描画にも入れない。ルビ、縦中横、注の印の箱には足さない。
- ベースラインシフトは、箱の幅にも行分割にも影響しない。`bcLook` に載せたまま、描画で使う。

`ceAdvance` と `ceWordAdvance` は今と同じ形で `Look` を受け取るので、プロポーショナルメトリクスと欧文のカーニングの方式は、測る関数の側（golem-driver）で幅に入る。

### 描画（golem-driver）

- `runAt` は、`shapingOf` で決めた機能でシェイピングする。各字の位置は、今と同じく箱の位置から決めるので、行分割で測った幅と描画の位置は一致する。
- 欧文の語の中では、各グリフの送りの後に `t` を足して次のグリフを置く。一つのクラスタの中の二つ目以降のグリフ（合字の結合文字など）には足さない。
- ベースラインシフト `s` は、横組みではグリフの原点の y に、縦組みでは x に足す。縦組みで回転して組む欧文も、行の方向に直交する向き（右）にずらす。行送りと行の格子は変えない。
- ルビと圏点は、親文字と同じ量だけずらす。

### HTML と EPUB（golem-html）

`HtmlCharStyle` と `HtmlParaStyle` に四つの欄を加え、`cs-名前` と `ps-名前` の CSS に次のように書く。
値が `body` の既定と同じ欄は書かない。

| 欄 | CSS |
|---|---|
| `kerning = "metrics"` | `font-kerning: normal` |
| `kerning = "japanese-equal-width"` | `font-kerning: normal` |
| `kerning = "none"` | `font-kerning: none` |
| `tracking` | `letter-spacing: 0.05em`（`tracking` ÷ 1000） |
| `proportional-metrics = true` | `font-feature-settings: "palt" 1`（縦組みの本では `"vpal" 1`） |
| `baseline-shift` | `vertical-align` に長さを書く。`zw` は `em`、絶対の寸法は `pt` |

CSS では、和文と欧文で別のカーニングを指定できない。
`japanese-equal-width` は、欧文のカーニングを保つことを優先して `font-kerning: normal` とし、和文のカーニングは閲覧環境の既定に任せる。
`letter-spacing` は行の最後の文字の後ろにも空きを足すが、PDF との差として受け入れる。
プレーンテキストは、どの欄も使わない。

### ドキュメント

- 仕様書の「style.toml」の節の文字スタイルと段落スタイルのキーの一覧に四つの欄を加え、方式の表と、HTML と EPUB での表し方を書く。
- 仕様書の「フォント」の節に、役割の `features` とスタイルの欄の関係（`shExtra` が役割の機能の後ろに足されること）を書く。
- 仕様書の「v1 の実装で次の段階以降に回した項目」から「InDesign の文字の組版の機能」の項目を消し、「v2 以降に回した事項」に、オプティカルカーニング（和文を含む）、水平比率と垂直比率、文字回転、文字ツメを加える。
- 用語集に「カーニング」「トラッキング」「プロポーショナルメトリクス」「ベースラインシフト」を加える。
- [docs/adr/0005](0005-character-and-paragraph-styles.md) のステータスの行に、文字スタイルと段落スタイルの欄をこの ADR で加えたことを書き足す（`採択→文字の送りの欄は [docs/adr/0020](0020-indesign-character-features.md)`）。

## 実装しないこと

- オプティカルカーニング。Adobe はアルゴリズムを公開しておらず、グリフの輪郭から間隔を決める方式を再実装しても、InDesign と同じ結果にはならない。InDesign に合わせるという目的に対して、費用に見合う一致が得られない。v2 以降で、InDesign との一致を求めない独自の方式として検討する。InDesign のオプティカルは欧文のグリフ向けだが、和文でも仮名の字面を詰めて遊ぶ組み方に使うことがあるので、v2 では和文にも効く方式とする。
- 「メトリクス - 欧文のみ」。資料で選択肢の名前を確かめられなかった。和文にカーニングをかけない点は `japanese-equal-width` と同じであり、違いは和文のプロポーショナルメトリクスを保つかどうかだけである。要る場合は、`metrics` で和文のペアカーニングだけを止める値として足す。
- 水平比率と垂直比率。PDF の横組みは `Tz` で表せる（`ScaledGlyphRun`、[golem-layout ADR 0005](../golem-layout/adr/0005-microtypography.md)）が、縦組みでの比率の意味（どちらの比率が送りを変えるか）を資料で確かめられず、HTML と EPUB では文字の流れを保ったまま字形を伸縮する CSS がない。長体と平体は、幅の異なる書体を役割に指定して代える。
- 文字回転、文字ツメ、文字前と文字後のアキ量、手動のカーニング（二字の間に値を指定すること）。
- ペアの一方が別の `Look` の場合のカーニング。InDesign のメトリクスも、別のフォントや書式の文字とのペアをカーニングしない（第三者の回答）。
- 欧文の語間の空白をまたぐペアカーニングと、明示のハイフンで分けた部分の間のペアカーニング。
- 縦組みの中で回転して組む欧文への `vkrn`。

## テスト設計

実装の前に書き、失敗することを確かめる。

### style.toml（`modules/golem-project/test/Main.hs`）

- `[character-styles.tight]` の `kerning = "none"`、`tracking = -50`、`proportional-metrics = true`、`baseline-shift = "1pt"` を読める。
- `kerning = "optical"` と `kerning = "auto"`、`tracking = 10001`、`tracking = -1001`、`baseline-shift = "up"` が G03021 になる。
- 段落スタイルの `based-on` の鎖で、子が書かない欄を親から引き継ぎ、`body` が何も書かなければ `metrics`、0、偽、0 になる。

### 測り方（`modules/golem-driver/test/Main.hs`、`modules/golem-font/test`）

`modules/golem-font/test/fonts/` の Source Sans Pro と Source Han Sans のサブセットを使う。

- `lfWordAdvance` の `AV`（Source Sans Pro）が、`shExtra = ["-kern"]` のとき `A` と `V` の送りの和に等しく、`[]` のとき和より小さい。
- `lfAdvance` の「「」（Source Han Sans）が、`shExtra = ["palt"]` のとき 1 より小さく、`["-palt"]` のとき 1 である。役割の `features = ["palt"]` に `shExtra = ["-palt"]` を足すと 1 になる。
- `lfPairKern` が、二字の並びのシェイピングの送りの和と、一字ずつの送りの和の差に等しい。
- 縦組みの `Shaping` で、`vpal` を足した「「」の送りが 1 より小さい。

### 組み方（`modules/golem-layout/test/Main.hs`）

測る関数は、テストの中で固定の値を返す関数を `ComposeEnv` に入れる。

- `ceKern` が「あい」に −0.1 を返す環境で、`compose env "あい"` の「あ」の箱の幅が 0.9 全角で、`bcEdgeEnd` が 0.1 全角である。`lkKerning = KernNone` の `Look` では、幅は 1 全角で `bcEdgeEnd` は 0 である。
- 「あ」と「」」の組には `ceKern` を使わない。
- `lkTracking = 100` の `Look` で、和文の一字の箱の幅が 1.1 全角、欧文の語 `abc` の箱の幅が測った幅に 0.3 全角を足した値、語間の `Glue` の幅が 0.1 全角だけ広い。どの箱も `bcEdgeEnd` が −0.1 全角である。
- `lkTracking = 100` の段落を組んだ各行で、`placeLine` の最後の箱の右端が行長に一致する。
- `lkBaselineShift` の異なる二つの `Look` で、同じ段落の行分割の結果が同じである。

### PDF と HTML

- `modules/golem-driver/test/Main.hs`：`baseline-shift = "2pt"` の文字スタイルの文字のグリフの原点の y が、横組みで 2pt 上にある。縦組みでは x が 2pt 右にある。
- `modules/golem-driver/test/Main.hs`：既存の PDF の golden テスト（スタイルの欄を書かない `style.toml`）のうち、和文のフォントがペアカーニングの情報を持たないものは変わらない。変わる場合は、ペアカーニングによる変化であることを `lfPairKern` の値で確かめてから期待値を直す。
- `modules/golem-html/test`：`[character-styles.tight]` の CSS に `font-kerning: none`、`letter-spacing: -0.05em`、`font-feature-settings: "palt" 1`、`vertical-align: 1pt` が並び、`body` と同じ値の欄は書かれない。

## トレードオフ

既定の `metrics` は和文にもペアカーニングをかけるので、和文のフォントがカーニングの情報を持つ場合、既存の本の PDF の和文の送りが変わり、字送りの格子からずれる行が出る。
InDesign の既定に合わせることを優先する。
格子にそろえたい本は、`[paragraph-styles.body] kerning = "japanese-equal-width"` と書く。

和文のペアカーニングを、約物を含む組に効かせないことにした。
約物の空きはアキ量のセットで決まり、フォントのカーニングと重ねると、JLReq の規則の値からずれるためである。
InDesign が約物を含むペアにカーニングをかけるかどうかは確かめていない。

トラッキングを行の最後の文字の後ろに入れないことにした。
InDesign はこの空きを入れると記憶しているが、確かめていない。
入れると、均等配置の行の終わりが、版面の端からトラッキングの分だけ内側にずれて見える。
Golem は版面の端をそろえることを優先する。

測る関数の鍵に `Shaping` を加えるので、`memo` の表が大きくなる。
文字スタイルで機能を変える文字は本文の一部であり、表の大きさは書体と機能の組の数に比例する。
