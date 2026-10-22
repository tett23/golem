# ADR 0019: アキの量を文字のクラスの組ごとに設定し、原稿にアキを入れる

ステータス: 採択→`[aki]` の行分割の項目の形は [golem-layout ADR 0012](../golem-layout/adr/0012-aki-glue-marker.md)、傍注の本文のアキ量のセットは、本文の食い違う二つの記述のうち「傍注の本文は `sidenote` の段落スタイルのセットで組む」を採る

## 文脈

和文の字間の空き（アキ）は、[golem-layout ADR 0002](../golem-layout/adr/0002-japanese-composition.md) の規則で決まり、量を変える設定はない。
今の実装（`Golem.Layout.Japanese` の `normalize`）は、次の値を固定で持つ。

- 約物の空きは、`punctSpace` が約物ごとに持つ字面の外側の空き（始め括弧類の前と、終わり括弧類、句点類、読点類の後に二分、中点類の前後に四分）を、`combined` が隣どうしで合わせて決める。空きは `Glue w 0 w` であり、最適が `w`、最小が 0、伸びない。
- 和文と欧文の間（和欧間）は `Glue (1/4) (1/4) (1/8)` であり、最適が四分、最小が八分、最大が二分になる。
- 和文どうしの分割できる位置には、行長の調整のための `Glue 0 (1/10) 0` を置く。
- 行末で分割すると、約物の後ろの空きの `Glue` は捨てられる。行末の終わり括弧類と句読点は半角になる。段落の先頭の始め括弧類は、前に二分の空きを持つ。

仕様書の「v1 の実装で次の段階以降に回した項目」（[specifications.md](../specifications.md)）は、この量を `style.toml` で変えられるようにし、原稿の任意の位置に五分アキなどを入れる記法を設けると決めている。
今は、原稿で空きを入れるには全角の空白を使うしかなく、寸法も `zw` の小数（五分は `0.2zw`）で書くしかない。

### InDesign の文字組みアキ量設定

InDesign は、この設定を「文字組みアキ量設定」として段落ごとに持つ。
確かめた資料と、そこから分かったことは次のとおりである。
Adobe のヘルプ（helpx.adobe.com）の該当するページは、取得を試みたが応答が 403 で、本文を読めなかった。

- Adobe の記事「第4回 文字を美しく組むための設定」（https://blog.adobe.com/jp/publish/2019/07/19/cc-indesign-basics-04-typesetting ）：定義済みのセットは 14 種で、四つの基本の組み方に段落の字下げの違いを掛け合わせたものである。詳細設定では、文字クラスの並びごとに最小、最適、最大と優先度を指定する。単位は「%」「分」「文字幅/分」から選ぶ。左揃え、右揃え、中央揃えでは最適の値で組み、均等配置では最小から最大の範囲で行の端数を調整する。優先度は 1 から 9 と「なし」の 10 段階で、番号の小さい項目から調整する。
- Adobe の「InDesign CS3 文字組み設定の手引き」（https://www.adobe.com/jp/print/pdfs/mojikumiWPCS3_web.pdf ）：本文の PDF は手元で読めず、検索エンジンの要約で次のことだけを確かめた。「行末約物半角」「約物半角」「行末約物全角」「約物全角」の四つは JIS X 4051 に準拠し、和欧間の最適を 25% とする。「行末約物全角／半角」は和欧間の最適を 0% とする。
- Illustrator のヘルプ（検索エンジンの要約）：文字組みの既定は「行末約物半角」（GyomatsuYakumonoHankaku）である。InDesign の既定も「行末約物半角」であることは、第三者の記事で見ただけで、Adobe の文書では確かめていない。
- InDesign のヘルプ（検索エンジンの要約）：文字パネルの「文字前のアキ量」と「文字後のアキ量」で、一つの文字の前後のアキを文字組みアキ量設定より優先して指定できる。単位は「分」であり、二分は全角の半分、四分は全角の四分の一である。
- BOOKHOUSE の解説（https://www.bookhouse.jp/default/spacing01.html 、第三者）：「行末約物半角」では、中黒と漢字の間が最小 0%、最適 25%、最大 25% で優先度 1、漢字の前後の最大は 100% で優先度「なし」である。

次のことは記憶によるものであり、資料では確かめていない。

- 詳細設定の文字クラスは、始め括弧、終わり括弧、読点、句点、中点、区切り約物、分離禁止文字、前置省略記号、後置省略記号、和字間隔、平仮名、上記以外の和字、半角欧文、行頭禁則和字、半角数字、全角数字などであり、行頭と行末と段落の先頭の扱いを別に持つ。
- 特殊文字として、全角スペース、二分スペース、四分スペース、六分スペース、細いスペース（八分）などの固定幅の空白を原稿に入れられる。

Golem の今の値は、和欧間（最適 25%、最小 12.5%、最大 50%）、括弧類と句読点（最適 50%、最小 0%）、中点（最適 25%、最小 0%、最大 25%）、行末の約物を半角にすることで、資料で確かめた「行末約物半角」の値と一致する。
一致しないのは和文の字間の最大で、InDesign は 100% で優先度を「なし」とし、Golem は 10% としている。
Golem は優先度を持たず、Knuth と Plass の方式で、行の伸縮をすべての空きに伸びの量の比で配る。
字間の伸びを小さくすることで、約物と和欧間を先に伸ばすという JLReq の優先順位に近づけている（[golem-layout ADR 0002](../golem-layout/adr/0002-japanese-composition.md)）。

### 設定の置き場所

`[composition]` に一つの値を置く案と、名前を付けたセットを定義して段落スタイルで選ぶ案を比べた。
InDesign は文字組みアキ量設定を段落の属性として持ち、段落スタイルで選ぶ。
本文と、引用や韻文で組み方を変えたい場合もある。
段落スタイルで選ぶ案を採る。
`body` はすべての段落スタイルの根なので、`[paragraph-styles.body]` で選べば本の全体の既定になり、`[composition]` に別の欄は要らない。

### 原稿の記法

InDesign の「文字前のアキ量」のように文字に属性として付ける案と、空白の文字のように位置に置く案を比べた。
属性の案は、`[style ...]` と同じ囲む形になり、一字のために散文スロットを書かせることになる。
原稿で空きを入れたい場面（数字と単位の間、人名の姓と名の間、見出しの番号と題の間）は、二つの文字の間の位置である。
位置に置くインラインのコマンド `[aki 量]` を設ける。

## 実装すること

### アキの量の書き方（golem-project）

アキの量は、次のいずれかで書く。
値は全角（`zw`）を 1 とする有理数として持ち、sp への変換は従来どおり一度だけ丸める。

| 書き方 | 値 |
|---|---|
| `"ベタ"` | 0 |
| `"全角"` | 1 |
| `"二分"` | 1/2 |
| `"三分"` | 1/3 |
| `"四分"` | 1/4 |
| `"五分"` | 1/5 |
| `"六分"` | 1/6 |
| `"八分"` | 1/8 |
| `"二分四分"` | 3/4 |
| `"0.2zw"` のような `zw` の小数 | その値 |
| `"25%"` のような百分率（小数を許す） | 値 ÷ 100 |

`Golem.Project.Style` に `parseAki :: Text -> Maybe Rational` を加える。
名前と百分率は、アキの量を書く欄（アキ量のセットの規則と、原稿の `[aki]`）でだけ受け付ける。
`indent` などのほかの寸法の欄は今のままとし、`"二分"` を書けば G0320（アキの量の誤り）とする。
負の値は書けない。

### アキ量のセット（golem-project）

`style.toml` に `[aki-sets.<名前>]` の節を新設する。

```toml
[aki-sets.wide-waou]
based-on = "gyomatsu-yakumono-hankaku"
rules = [
  { before = "japanese", after = "western", optimum = "三分", minimum = "四分", maximum = "二分" },
  { before = "western", after = "japanese", optimum = "三分", minimum = "四分", maximum = "二分" },
]

[paragraph-styles.body]
aki-set = "wide-waou"
```

| キー | 型 | 意味 |
|---|---|---|
| `based-on` | セットの名前 | 基準にするセット。書かなければ `gyomatsu-yakumono-hankaku` |
| `rules` | 規則の配列 | 基準のセットの規則の後に足す規則 |

規則の欄は次のとおりとする。

| キー | 型 | 意味 |
|---|---|---|
| `before` | クラスの名前、またはその配列 | 前の文字のクラス。`line-start` と `paragraph-start` も書ける |
| `after` | クラスの名前、またはその配列 | 後ろの文字のクラス。`line-end` も書ける |
| `optimum` | アキの量 | 最適 |
| `minimum` | アキの量 | 最小。書かなければ `optimum` |
| `maximum` | アキの量 | 最大。書かなければ `optimum` |

クラスの名前は、今の `CharClass`（JLReq の分類）に合わせて次のとおりとする。

| 名前 | JLReq | `CharClass` |
|---|---|---|
| `opening` | cl-01 始め括弧類 | `Opening` |
| `closing` | cl-02 終わり括弧類 | `Closing` |
| `hyphen` | cl-03 ハイフン類 | `Hyphen` |
| `dividing` | cl-04 区切り約物 | `Dividing` |
| `middle-dot` | cl-05 中点類 | `MiddleDot` |
| `full-stop` | cl-06 句点類 | `FullStop` |
| `comma` | cl-07 読点類 | `Comma` |
| `inseparable` | cl-08 分離禁止文字 | `Inseparable` |
| `iteration` | cl-09 繰返し記号 | `Iteration` |
| `prolonged-sound` | cl-10 長音記号 | `ProlongedSound` |
| `small-kana` | cl-11 小書きの仮名 | `SmallKana` |
| `ideographic-space` | cl-14 和字間隔 | `IdeographicSpace` |
| `kana` | cl-15、cl-16 平仮名、片仮名 | `Kana` |
| `ideograph` | cl-19 漢字等 | `Ideograph` |
| `western` | cl-27 欧文 | `Western` |
| `japanese` | `western` 以外のすべて | |

規則の意味は次のとおりとする。

- `before` の各クラスと `after` の各クラスの組に、(最小, 最適, 最大) を割り当てる。後に書いた規則が、同じ組の前の規則を上書きする。基準のセットの規則は、子のセットの規則より前にある。
- `before = "paragraph-start"` は段落の最初の文字の前、`before = "line-start"` は段落の途中で改行した後の行頭の文字の前、`after = "line-end"` は改行する前の行末の文字の後ろの空きである。行頭と行末の空きは `optimum` の固定の量とし、`minimum` と `maximum` は使わない。
- 規則のない組の空きは 0 で、伸び縮みしない。
- `minimum <= optimum <= maximum` でない規則、未知のクラスの名前、`line-end` を `before` に書いた規則、`line-start` と `paragraph-start` を `after` に書いた規則は G0320 とする。

| 診断コード | 重大度 | メッセージ |
|---|---|---|
| G0320 | エラー | `アキの量の指定が正しくありません: <理由>` |

G0320 は未使用である。`style.toml` の一般の誤りの G0306 から、アキの量とアキ量のセットの誤りを分けて、どの欄の誤りかをコードで引けるようにする（提案中の ADR のあいだで、G0317 から G0322 を分けて割り当てた）。


### 組み込みのセット

組み込みのセットを二つ持つ。
どちらも、名前と考え方を InDesign の同名のセットに合わせ、値は今の Golem の組み方から決める。
InDesign の同名のセットの値とは、資料で確かめた項目（和欧間、括弧類と句読点、中点、行末の扱い）のほかは照合していない。

`gyomatsu-yakumono-hankaku`（行末約物半角）は既定のセットで、今の `normalize` と同じ組み方になる。
下の表では、`P` は `closing`、`full-stop`、`comma`、`O` は `opening`、`M` は `middle-dot`、`J` は `japanese` から `O`、`P`、`M` を除いたクラス、`W` は `western` を表す。
値は (最小, 最適, 最大) である。

| 前 | 後ろ | アキ |
|---|---|---|
| `J` | `kana`、`ideograph`、`ideographic-space`、`inseparable` | (0, 0, 0.1zw) |
| `inseparable` | `inseparable` | (0, 0, 0) |
| `J`、`W`、`O` | `O` | (0, 二分, 二分) |
| `J`、`W`、`O` | `M` | (0, 四分, 四分) |
| `P`、`M` | `O` | `P` は (0, 二分, 二分)、`M` は (0, 二分四分, 二分四分) |
| `P` | `J`、`W` | (0, 二分, 二分) |
| `P` | `M` | (0, 二分四分, 二分四分) |
| `M` | `J`、`W` | (0, 四分, 四分) |
| `M` | `M` | (0, 二分, 二分) |
| `J` | `W` | (八分, 四分, 二分) |
| `W` | `J` | (八分, 四分, 二分) |
| `paragraph-start` | `O` | (0, 二分, 二分) |
| `paragraph-start` | `M` | (0, 四分, 四分) |

表にない組（`J` から `hyphen`、`dividing`、`iteration`、`prolonged-sound`、`small-kana` への組、`P` どうし、`O` から `J` と `P` と `W` への組、`line-start` と `line-end` を含む組など）は 0 である。
行末の約物の後ろの空きが 0 なので、行末の終わり括弧類と句読点は半角になる。

`gyomatsu-yakumono-zenkaku`（行末約物全角）は、`gyomatsu-yakumono-hankaku` に次の規則を足したものとする。

| 前 | 後ろ | アキ |
|---|---|---|
| `P` | `line-end` | 二分 |
| `M` | `line-end` | 四分 |

利用者が組み込みと同じ名前の節を書くとエラー（G0320）とする。
組み込みのセットの値を変えたい場合は、`based-on` で引き継いだ別の名前のセットを作る。
段落スタイルと違い、組み込みのセットは InDesign の定義済みのセットに当たり、InDesign でも定義済みのセットは編集できない（記憶）。

### 段落スタイルの欄

`[paragraph-styles.<名前>]` に `aki-set`（セットの名前）を加える。
`body` の既定は `gyomatsu-yakumono-hankaku` とし、ほかの段落スタイルは `based-on` から引き継ぐ。
存在しないセットを指す `aki-set` と `based-on`、循環する `based-on` は G0313 とする。
ファイルの中の段落スタイルの定義（[docs/adr/0014](0014-in-file-settings.md)）でも `aki-set` を書けるが、セットそのものは `style.toml` にだけ定義できる。
セットは `[composition]` と同じく本の全体で一つの資源だからである。

段落スタイルの効く範囲は今のままとする。
見出し、表、目次、索引、脚注と傍注の本文（`sidenote` の段落スタイルの `font` と `size` のほか）は `body` のセットで組む。
キャプションは `caption` の、傍注の本文は `sidenote` の段落スタイルのセットで組む。

### 組み方（golem-layout）

新しいモジュール `Golem.Layout.Aki` を設ける。

```haskell
data AkiPos = AkiChar !CharClass | AkiLineStart | AkiParagraphStart | AkiLineEnd
  deriving stock (Eq, Ord, Show)

-- | 全角を 1 とする最小、最適、最大
data Aki = Aki {akiMinimum, akiOptimum, akiMaximum :: !Rational}
  deriving stock (Eq, Show)

newtype AkiSet = AkiSet (Map (AkiPos, AkiPos) Aki)

akiBetween :: AkiSet -> AkiPos -> AkiPos -> Aki  -- 規則のない組は Aki 0 0 0
builtinAkiSets :: Map Text AkiSet
defaultAkiSet :: AkiSet                          -- gyomatsu-yakumono-hankaku
```

`CharClass` に `Ord` を導出する。
`ComposeEnv` に `ceAkiSet :: !AkiSet` を加え、`defaultComposeEnv` では `defaultAkiSet` とする。

`normalize` の `between` を次のように書き換える。
禁則（`noBreak`）の判定と、欧文どうし、ルビ、縦中横の箱の扱いは今のままとする。

- 前後の箱のクラスが分かるとき（`lastClass` と `firstClass` が `Just`）、`akiBetween` で空きを引く。
- 空きが `Aki 0 0 0` なら、今の「空きのない位置」と同じく、分割できれば `Penalty 0 0 NoHyphen` を置き、できなければ何も置かない。
- そうでなければ、分割できない位置では `Penalty 0 infPenalty NoHyphen` を置いてから、`Glue o (x - o) (o - n)` を置く（`n`、`o`、`x` は最小、最適、最大を sp にした値）。
- `leading` は `AkiParagraphStart` の規則で、段落の最初の箱の前に同じ形の `Glue` を置く。

`combined` と、和欧間の判定（`waou`）は消す。
`punctSpace` は、約物の箱の幅から字面の外側の空きを除くためと、PDF の描画の位置のため（`Golem.Driver.Pdf` の `pre`）に残す。

行頭と行末の空きは、箱の `bcEdgeStart` と `bcEdgeEnd` に足す。
この二つの欄は、行頭と行末に来た箱にだけ効き、行分割の幅と `placeLine` の両方が数える（[golem-layout ADR 0009](../golem-layout/adr/0009-ruby-placement.md)）。
約物の箱はルビの箱と別の種類なので、ルビのかけの戻しと重ならない。

`zw` の基準の大きさは次のとおりとする。

- 前後の一方だけが約物（`O`、`P`、`M`）なら、その約物の箱の大きさ。今の「約物の空きはその箱の大きさで測る」（[golem-driver ADR 0004](../golem-driver/adr/0004-pdf-emphasis-and-character-styles.md)）を保つ。
- 両方が約物なら、大きいほうの箱の大きさ。
- どちらも約物でなければ、段落の文字の大きさ（`ceFontSize`）。今の和欧間と字間の空きと同じである。
- 行頭、行末、段落の先頭の空きは、その箱の大きさ。

### 原稿の `[aki]`（golem-eval、golem-doc）

```
第一章[aki 全角]吾輩は猫である
3[aki 四分]kg
```

`[aki 量]` は、その位置に固定の幅の空きを置く。
量は、上の表のアキの量か、絶対の寸法（`1mm`、`2pt` など）で書く。
散文スロットは取らない。

- 意味論 IR の `InlineF` に `Aki !SrcSpan !AkiAmount` を加える。`data AkiAmount = AkiZw !Rational | AkiAbs !Sp` とする。
- CDDL（`modules/golem-doc/schema/golem-doc.cddl`）の `inline-no-ruby` に `[18, span, zw: [int, uint] / null, sp: int / null]`（`zw` は分子と分母、どちらか一方だけが値を持つ）を加え、`Golem.Doc.Cbor` と `Golem.Doc.Validate` をそろえる。
- インラインを足すと、フィルタのプラグインとの間の IR の形が変わるので、ABI の版を一つ上げる。今の版は 3 で、この ADR だけを実装すれば 4 になる。この ADR の実装より前に別の ADR（[docs/adr/0017](0017-forced-page-breaks.md) など）が版を上げていれば、その次の版にする。`Golem.Doc` と golem-plugin の `abiVersion`、テストのプラグイン（`modules/golem-plugin/test/plugins/*.wat`）の `golem_abi_version` の戻り値を同じ版にそろえる。
- `Golem.Eval.File` の `builtinInlineCommands` に `aki` を加える。位置引数が一つでない、量を読めない、散文スロットがある場合は G0255 とし、メッセージで書ける量を示す。G0255 は今のコードと ADR で使われていない（`git grep` で確かめた）。`overridableCommands` には加えない。
- golem-layout は、`Aki` を幅が固定の `Glue w 0 0` にし、前に `Penalty 0 infPenalty NoHyphen` を置く。`[aki]` の前後では分割しない。`zw` は、その位置の文字の大きさ（`ceLook` の `lkSize`）で測る。
- `[aki]` を挟んだ二つの文字の間には、アキ量のセットの空きを置かない。`[aki]` は、その位置の空きを書き手が決めたものとして扱う。`normalize` は `Aki` の `Glue` を、前後の箱の組の判定から外す（`between` に渡す前の箱を `Nothing` にする）。

各媒体での表し方は次のとおりとする。

- PDF：上の `Glue` のとおりに組む。
- HTML と EPUB：`&#x2060;<span class="aki" style="margin-inline-start: 0.2em"></span>&#x2060;` のように、空の `span` の論理方向の余白で表す。U+2060（WORD JOINER）は、前後での改行を避けるために置く。`zw` は `em`、絶対の寸法は `pt` で書く。
- プレーンテキスト：`zw` で書いた量の整数部の数だけ全角の空白（U+3000）を出す。1 に満たない量と、絶対の寸法は何も出さない。

### ドキュメント

- 仕様書の「style.toml」の節に、`[aki-sets.<名前>]`、組み込みのセット、段落スタイルの `aki-set`、アキの量の書き方を書く。例の `style.toml` は変えない。
- 仕様書の「v1 の実装で次の段階以降に回した項目」から「アキの指定」の項目を消す。
- markup.md の「インライン」に「アキ」の節を加える。
- 用語集の「和欧間」を「既定では四分の空きを置き、量はアキ量のセットで変えられる」に直し、「アキ量のセット」を加える。
- [golem-layout ADR 0002](../golem-layout/adr/0002-japanese-composition.md) のステータスの行に、字間の空きの量はこの ADR で変えたことを書き足す（`採択→ルビの配置は[ADR 0009](0009-ruby-placement.md)、字間の空きの量は [docs/adr/0019](../../adr/0019-aki-settings.md)`）。

## 実装しないこと

- 優先度。InDesign の優先度（1 から 9 と「なし」）は、行の伸縮を項目の順に配る仕組みであり、Knuth と Plass の方式の伸縮の配り方（伸びの量の比）と合わない。優先度を入れるには、行分割の不良度の計算と `placeLine` の配り方を変える必要があるので、別の ADR で扱う。
- InDesign の定義済みのセットのうち、「約物半角」「約物全角」「行末約物全角／半角」などの残りのセットと、段落の字下げを含むセット。値を InDesign で照合してから足す。字下げは段落スタイルの `indent` と `first-line-indent` で表す（[docs/adr/0006](0006-paragraph-indent.md)）。
- 前置省略記号（¥、$ など）、後置省略記号（%、℃ など）、全角数字、半角数字、行頭禁則和字のクラス。今の `charClass` が区別しておらず、分類の表を広げる ADR が要る。
- 「文字前のアキ量」と「文字後のアキ量」のように、文字に付ける属性としてのアキ。
- 行頭と行末の空きの伸縮。
- `[aki]` の前後で改行を許す指定。
- HTML と EPUB でのアキ量のセット。ブラウザーの組版は文字のクラスの組ごとの空きを指定する手段を持たない。CSS の `text-spacing-trim` と `text-autospace` は約物の詰めと和欧間の有無だけを選ぶものであり、量を指定できない。HTML と EPUB では、今と同じくブラウザーの既定で組む。

## テスト設計

実装の前に書き、失敗することを確かめる。

### アキの量と style.toml（`modules/golem-project/test/Main.hs`）

- `parseAki` が `"ベタ"`、`"全角"`、`"二分"`、`"三分"`、`"四分"`、`"五分"`、`"六分"`、`"八分"`、`"二分四分"`、`"0.2zw"`、`"12.5%"` を 0、1、1/2、1/3、1/4、1/5、1/6、1/8、3/4、1/5、1/8 に読み、`"-1zw"`、`"1mm"`、`"十分"` を読まない。
- 上の例の `[aki-sets.wide-waou]` と `aki-set = "wide-waou"` を読める。
- `minimum` が `optimum` より大きい規則、未知のクラス、`before = "line-end"`、組み込みと同じ名前の節が G0320 になる。
- 存在しないセットを指す `aki-set` と `based-on`、循環する `based-on` が G0313 になる。
- `indent = "二分"` が G0320 になる。

### 組み方（`modules/golem-layout/test/Main.hs`）

- 等価のテスト：今の `normalize` を写した参照の関数をテストに置く。`kinsoku = "strict"` で、15 のクラスの代表の文字の全ての組（225 組）と、各クラスの文字で始まる段落について、`defaultAkiSet` の `composeInlines` の結果が参照の関数と一致する。文字の大きさはすべて同じにする。今の字間の伸びは文字の大きさを 10 で割って切り捨てた値で、新しい変換は丸めなので、参照の関数の字間の伸びも丸めに直して比べる。文字の大きさが 10sp の倍数でないときだけ、1sp 異なりうる。
- `kinsoku = "loose"` では、`J` から `small-kana` と `prolonged-sound` への組だけが参照の関数と異なり、`Glue 0 (fs/10) 0` の代わりに `Penalty 0 0 NoHyphen` になる。
- 和欧間を (四分, 三分, 二分) にしたセットで、`compose env "漢A"` の和欧間の `Glue` が `Glue (fs/3) (fs/6) (fs/12)` になる。
- `gyomatsu-yakumono-zenkaku` で、「」」の直後で改行する段落の行の幅に二分が含まれ、`placeLine` の最後の箱の右端から行末までが二分である。`gyomatsu-yakumono-hankaku` では 0 である。
- `paragraph-start` の `opening` を 0 にしたセットで、「「」で始まる段落の最初の項目が箱になる。
- 括弧の文字だけを大きくした文字スタイルの中の「」」と、後ろの漢字の間の空きが、括弧の大きさの二分である。

### `[aki]`

- `modules/golem-eval/test`：`[aki 五分]` が `Aki sp (AkiZw (1/5))`、`[aki 1mm]` が `AkiAbs` になる。`[aki]`、`[aki 十分]`、`[aki 四分: 語]` が G0255 になる。
- `modules/golem-doc/test`：`Aki` を CBOR に書いて読み戻すと同じ値になり、CDDL の検査を通る。
- `modules/golem-layout/test/Main.hs`：`漢[aki 五分]A` が `[箱 漢, Penalty 0 inf, Glue (fs/5) 0 0, 箱 A]` になり、和欧間の `Glue` を含まない。
- `modules/golem-html/test`：`[aki 五分]` が `margin-inline-start: 0.2em` の `span` になり、前後に U+2060 がある。
- `modules/golem-text/test`：`[aki 全角]` が U+3000 一つ、`[aki 五分]` が空になる。

### PDF（`modules/golem-driver/test/Main.hs`）

- 既存の PDF の golden テストが、セットを指定しない `style.toml` で変わらないことを確かめる。

## トレードオフ

既定のセットを今の組み方と同じにしたので、既存の本の PDF は、`kinsoku = "loose"` の段落、大きさの異なる約物が隣り合う段落、字間の伸びの 1sp の丸めの差で分割が変わる段落を除いて変わらない。
一方で、和文の字間の最大は InDesign の「行末約物半角」と異なる。
InDesign の値（100%）をそのまま入れると、優先度のない Golem では字間が和欧間や約物より先に大きく伸び、JLReq の優先順位から遠ざかる。
優先度を実装するまで、字間の伸びは小さいままにする。

アキの量の名前を、アキの欄でだけ受け付けることにした。
すべての寸法の欄で受け付けると、`indent = "二分"` のような書き方もできるが、`parseDim` を使う欄（版面、塗り足し、傍注の欄など）の多くは絶対の寸法を求め、名前を許す欄と許さない欄の区別がかえって分かりにくくなる。

`[aki]` の前後で改行しないことにした。
数字と単位、姓と名の間のように、空きを入れたい位置の多くは改行してほしくない位置である。
改行してよい空きは、全角の空白で書ける。

行頭と行末の空きを固定の量にしたので、行末約物全角の行末の二分は、行の伸縮の調整に使われない。
`bcEdgeEnd` に伸縮を持たせるには、`Item` の型と行分割の幅の計算を変える必要がある。
