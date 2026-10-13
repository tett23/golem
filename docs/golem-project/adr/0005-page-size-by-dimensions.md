# ADR 0005: 判型を寸法で指定する

ステータス: 採択

## 文脈

[ADR 0002](0002-style-toml.md) は、判型の名前を寸法に写す表を持ち、表にない判型は寸法で書くと決めた。
表は A4、A5、A6、B5、B6、四六判で、[ADR 0003](0003-mass-market-paperback-size.md) が `mass-market` を加えた。
寸法で書く方法は、[ADR 0003](0003-mass-market-paperback-size.md) が別の ADR に回したまま決まっていない。

今の実装は次のとおりである。

- `Golem.Project.Style` の `Page` は、`[page]` の `size` を文字列のまま `pageSizeName :: Text` に持つ。
- `parseStyle` の検査は、表にない名前を G0306（`未知の判型です`）とするが、`x` を含む文字列は通す。寸法による指定のために空けておいた抜け道である。
- `Golem.LayoutSpec.pageGeometry` は、`pageSize (pageSizeName page)` が `Nothing` なら G0701（`未知の判型です`）を返す。`x` を含む文字列はここで止まる。
- したがって `size = "148mm x 210mm"` は、`golem check` を通り、PDF のビルドで G0701 になる。HTML、EPUB、プレーンテキストは判型を使わないので、これらのビルドは通る。

InDesign の新規ドキュメントのダイアログは、ページサイズを名前の付いたプリセットから選ぶか、幅と高さの二つの欄に値を入れて決める。
ページサイズは、塗り足しなどを断裁した後の仕上がりの寸法である（Adobe のヘルプ「[Create new documents](https://helpx.adobe.com/indesign/using/create-new-documents.html)」、InDesign CC 2015 以前の版の記述）。
Golem の判型も仕上がりの寸法であり、塗り足しは `[page]` の `bleed` で別に持つ（[golem-pdf ADR 0004](../../golem-pdf/adr/0004-crop-marks-and-bleed.md)）。

### 比較した書き方

| 書き方 | 例 | 利点 | 欠点 |
|---|---|---|---|
| A. 文字列 | `size = "148mm x 210mm"` | 短い。寸法を書く習慣に近い | 区切りの `x` の前後の空白、`×`（U+00D7）、大文字の `X` を受け付けるかという小さな文法が要る。誤りの位置が文字列の中のどこかを示せない |
| B. インラインテーブル | `size = { width = "148mm", height = "210mm" }` | TOML の構造で書け、各寸法は既存の寸法の文字列と同じ規則で読める。`[page.grid]` の `position = { top = …, gutter = … }` と同じ形である。InDesign の幅と高さの欄に対応する | A より長い |
| C. `[page]` の `width` と `height` の欄 | `width = "148mm"`、`height = "210mm"` | 一段浅い | `size` との排他の規則が要り、`[page]` の欄が増える |

B を採る。
`size` の一つの欄に、名前か寸法のどちらかを書く形が保たれ、排他の規則が要らない。
文字列の中の文法を新たに作らずに済み、誤りは TOML の値の位置で示せる。

## 実装すること

### 書き方

`[page]` の `size` は、次のどちらかで書く。

- 文字列：判型の表の名前（`"A4"`、`"A5"`、`"A6"`、`"B5"`、`"B6"`、`"四六判"`、`"菊判"`、`"新書判"`、`"mass-market"`）。
- インラインテーブル（またはテーブル）：`width`（幅）と `height`（高さ）の二つの欄を持つ。どちらも必須で、値は寸法の文字列である。

```toml
[page]
size = { width = "148mm", height = "210mm" }
```

- 単位は `mm`、`pt`、`Q`、`H` とする。幅と高さで単位が異なってもよい。
- `zw` は使えない。判型は文字の大きさに依存しない長さだからである（`bleed` と同じ扱い）。
- 幅と高さは、横組みと縦組みのどちらでも、ページを正立させたときの横と縦の寸法である。綴じの方向や組み方向で入れ替えない。
- 幅が高さより大きい判型（横長の本）も受け付ける。
- 判型の表の名前は、これまでどおり縦長の寸法を表す。表の名前を横長にする書き方は設けない。横長にするには寸法で書く。

### 検査

次はすべて G0317（判型の誤り）とし、位置は `size` の値の位置とする。
読み込みの段階（`decodeStrict` の `FromValue`）で失敗させるので、`golem check` と、PDF を含まないビルドでも検出する。

| 場合 | メッセージ |
|---|---|
| 表にない名前（`x` を含む文字列を含む） | `未知の判型です: <名前>。表にない判型は size = { width = "…", height = "…" } で書きます` |
| `width` か `height` がない | `判型の width と height はどちらも必須です` |
| `width` と `height` 以外の欄がある | 未知のキーの既存のメッセージ |
| 寸法として読めない値 | 寸法の既存のメッセージ |
| `zw` の値 | `判型には zw を使えません` |
| 0 以下の値 | `判型の幅と高さは 0 より大きい寸法です` |

G0317 を新しく割り当てる。
G0317 は未使用である。`style.toml` の一般の誤りの G0306 から判型の誤りを分け、どの欄の誤りかをコードで引けるようにする（提案中の ADR のあいだで、G0317 から G0322 を分けて割り当てた）。
[golem-driver ADR 0016](../../golem-driver/adr/0016-output-and-layout-diagnostic-codes.md) が `pageGeometry` から移す「未知の判型」の検査も、G0317 とする。
これまで `style.toml` の値の誤りは G0306 にまとめていた（[ADR 0002](0002-style-toml.md)）が、判型の誤りはこの G0317 に分ける。

`parseStyle` の `checks` から、`未知の判型です` の検査と `x` を含む文字列を通す条件を削る。
読み込みで判型が確定するので、`Golem.LayoutSpec.pageGeometry` の `未知の判型です`（G0701）の分岐はなくなる。

### データ構造

`Golem.Project.Style` を次のように変える。

```haskell
-- | [page] の size。名前は読み込みで表と照合済みである。
data PageSize
  = NamedSize !Text      -- 判型の表の名前
  | CustomSize !Sp !Sp   -- 幅と高さ（sp）
  deriving stock (Eq, Show)

data Page = Page
  { pageSizeSpec :: !PageSize,   -- pageSizeName :: Text を置き換える
    ...
  }

-- | 仕上がりの幅と高さ（sp）。
pageTrimSize :: Page -> (Sp, Sp)
```

- `pageTrimSize` は、`NamedSize` なら表の mm の値を、`CustomSize` ならその値を返す。`NamedSize` の名前は読み込みで表にあることを確かめてあるので、表を引けない場合は起こらない。
- 表の mm から sp への変換は、今の `Golem.LayoutSpec` の `mmToSp`（有理数で計算し、最後に一度だけ最近接偶数丸め）を golem-project に移して使う。寸法の文字列の変換（`parseDim`）と同じ丸めであり、`"mass-market"` と `{ width = "107.95mm", height = "174.625mm" }` は同じ sp になる。
- 判型の表の関数 `pageSize :: Text -> Maybe (Rational, Rational)` は残す。
- `Golem.LayoutSpec.pageGeometry` は、`pageSize (pageSizeName page)` の代わりに `pageTrimSize page` を使う。
- `pageSizeName` を使っている箇所（golem-project のテスト）は、`pageSizeSpec` に合わせる。

### 媒体

判型を使うのは PDF だけである。
HTML、EPUB、プレーンテキストは、これまでどおり判型を読まない。

### ドキュメント

- 仕様書の「style.toml」の節に、`size` に表の名前か `{ width, height }` を書けること、表の名前の一覧（菊判と新書判を含む）、単位と検査を書く。
- 仕様書の「v1 の実装で次の段階以降に回した項目」から「寸法による判型の指定」を削る。
- [ADR 0002](0002-style-toml.md) のステータスの行に「判型の寸法による指定は ADR 0005」を加え、この ADR へのリンクを付ける。

### 判型の表に加える名前

和文の書籍で慣用の判型のうち、表になかった二つを加える。

| 名前 | 幅 × 高さ |
|---|---|
| `"菊判"` | 150mm × 220mm |
| `"新書判"` | 103mm × 182mm |

- 名前は、表の `"四六判"` と同じく「判」で書く。「菊版」「新書版」とは書かず、別名も設けない。
- どちらの判型も JIS で定めた寸法ではなく、出版社によって数ミリの幅がある（菊判の 152mm × 218mm、新書判の 105mm × 173mm など）。表には、印刷所と出版社の判型の案内で最も多く見られる値を採る。違う寸法で組む本は、この ADR の `{ width, height }` で書く。
- `pageSize` に二つの行を加える。縦長の寸法とし、ほかの名前と同じく横長にする書き方は設けない。

## 実装しないこと

- 文字列の書き方（比較の A）と、`[page]` の `width` と `height` の欄（比較の C）。書き方を一つにする。
- インチの単位（`in`）。[ADR 0003](0003-mass-market-paperback-size.md) と同じく加えない。インチの判型は `mm`（1in = 25.4mm）か `pt`（1in = 72pt）で厳密に書ける。たとえば 5.5in × 8.5in は `{ width = "396pt", height = "612pt" }` である。
- 上の二つのほかの、判型の表への名前の追加。[ADR 0002](0002-style-toml.md) のとおり、名前を加えるたびに ADR を作る。
- 表の名前を横長にする指定（InDesign の方向のボタンに当たるもの）。
- 判型の上限の検査。PDF の実装上の上限（記憶によれば、PDF 1.7 の付録 C で 14,400 単位、200in）や InDesign の上限（Adobe のコミュニティの回答によれば 216in）を超える本は想定しにくく、MediaBox はトンボと塗り足しの分だけ判型より大きくなるので、上限は判型ではなく MediaBox で決めることになる。必要になってから ADR で扱う。
- 小さすぎる判型の個別の検査。版面が収まらなければ、今の `pageGeometry` の G0701（`版面がページからはみ出しています`）になる。

## テスト設計

### golem-project（`modules/golem-project/test/Main.hs`）

- `[page]\nsize = { width = "148mm", height = "210mm" }\n` を読むと、`pageTrimSize` が `parseDim "148mm"` と `parseDim "210mm"` の sp の組になる。
- `size = { width = "107.95mm", height = "174.625mm" }` の `pageTrimSize` が、`size = "mass-market"` の `pageTrimSize` と一致する。
- `size = { width = "396pt", height = "612pt" }` の `pageTrimSize` が `(396 * 65536, 612 * 65536)` になる。
- 幅と高さで単位が異なる `{ width = "100mm", height = "600Q" }` を読める。
- 横長の `{ width = "210mm", height = "148mm" }` を読める。
- 次がそれぞれ G0317 になり、メッセージに上の表の文言が含まれる。
  - `size = "148mm x 210mm"`
  - `size = "A3"`
  - `size = { width = "148mm" }`
  - `size = { width = "148mm", height = "210mm", depth = "1mm" }`
  - `size = { width = "10zw", height = "210mm" }`
  - `size = { width = "0mm", height = "210mm" }`
  - `size = { width = "148", height = "210mm" }`
- 既存の判型の名前の `pageTrimSize` が、`pageSize` の mm の値を sp にしたものと一致する（A4 から `mass-market` までの七つ）。
- `size = "菊判"` の `pageTrimSize` が `{ width = "150mm", height = "220mm" }` の値と、`size = "新書判"` の `pageTrimSize` が `{ width = "103mm", height = "182mm" }` の値と一致する。今は G0306 になることを確かめてから実装する。
- `size = "菊版"` と `size = "新書版"` は G0317 になる。
- 仕様書の例の `style.toml` を読むと、`pageSizeSpec` が `NamedSize "B6"` になる。

### golem-layout-spec（`modules/golem-layout-spec/test/Main.hs`）

- `size = { width = "128mm", height = "182mm" }` の版面の幾何（`pgPageSize`、`pgTypeArea`、`pgTypeAreaEven`）が、`size = "B6"` の版面の幾何と一致する。

### golem-driver（`modules/golem-driver/test/Main.hs`）

- 寸法で判型を書いたテスト用のプロジェクトで PDF をビルドすると、TrimBox が指定の寸法（pt）になる。
- `size = "148mm x 210mm"` のプロジェクトで `golem check` に当たる検査がエラーになる。今は通ることを確かめてから実装する。

## トレードオフ

インラインテーブルは、文字列の `"148mm x 210mm"` より長い。
判型は一冊に一度だけ書く値であり、長さよりも、寸法の文字列の規則をそのまま使えること、誤りを値の位置で示せることを取る。

`size` が文字列とテーブルの二つの型を取るので、読み込みの型の分岐が一つ増える。
`[page]` に `width` と `height` を並べる形（比較の C）にすれば型は一つになるが、`size` との排他を検査する必要があり、どちらを書いたかで意味が変わる欄が二組できる。

`x` を含む文字列は、これまで `golem check` を通っていたが、エラーになる。
寸法による指定は実装されていなかったので、PDF のビルドはもともと G0701 で止まっていた。
エラーになる段階が早まるだけで、出力が変わる原稿はない。

## 参考文献

- 菊判と新書判の寸法は、国内の印刷所と出版社が公開している判型の一覧で、最も多く見られる値を採った。JIS P 0138（紙加工仕上寸法）は A 列と B 列を定め、菊判と新書判は定めていない。
