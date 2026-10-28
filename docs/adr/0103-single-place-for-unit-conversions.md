# ADR 0103: 長さの単位の変換を一か所にまとめ、表示の桁と丸めをそろえる

ステータス: 採択→一か所の置き場所（golem-syntax の `Golem.Syntax.Length`）は [ADR 0114](0114-sp-in-a-length-package.md) で golem-length の `Golem.Length` に移した

## 文脈

Golem の長さの単位は sp（1pt の 65536 分の 1）である。
書き手は `style.toml`、`preflight.toml`、原稿の `[aki]` と図版の `width` に、`mm`、`pt`、`in`、`Q`、`H`、`zw` を付けた寸法を書き、処理系は sp に直して組む。
diagnostic と出力は、sp を mm、pt、em に直して書く。
変換が別々の場所にあると、同じ長さを直した値が少しずつ食い違っていく。
[2026-10-25 のリファクタリングの調査](../audits/2026-10-25-refactoring-survey.md) の R11 と R13 は、その食い違いがすでにあることを示した。
メンテナーは [ADR 0087](0087-test-support-dependencies-and-shared-fixtures.md) の「単位の変換の統一」で、変換を一か所にまとめなければならないと警告した。

### 書かれた寸法を sp に直す変換

書かれた寸法は、すべて [`Golem.Project.Style.parseDim`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-project/src/Golem/Project/Style.hs#L121-L145) で読む（[golem-project ADR 0010](../golem-project/adr/0010-inch-unit.md)）。
数を正確な有理数で読み、sp に一度だけ、等距離なら偶数の側へ丸める（Haskell の `round`）。

| 単位 | 変換 | 箇所 |
| --- | --- | --- |
| `pt` | `round (r × 65536)` | `parseDim` |
| `in` | `round (r × 72 × 65536)` | `parseDim` |
| `mm` | `round (r × 72 × 65536 / 25.4)` | [`mmToSp`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-project/src/Golem/Project/Style.hs#L1252-L1254) |
| `Q`、`H` | `mmToSp (r / 4)` | `parseDim` |
| `zw` | 文字の大きさが決まるまで `Zw r` で持ち、`round (r × 文字の大きさ)` | [`dimToSp`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-project/src/Golem/Project/Style.hs#L158-L161) |

この向きの変換は、丸めの規則がそろっている。
ただし、`zw` を sp に直す計算は `dimToSp` のほかに、アキの量を組む [`Golem.Layout.Japanese`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-layout/src/Golem/Layout/Japanese.hs#L589) にもう一つある（`round (r × 文字の大きさ)`、同じ規則）。
判型の表の寸法も、`mmToSp` で sp にする（[`pageTrimSize`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-project/src/Golem/Project/Style.hs#L1246-L1250)）。

### sp を書き出す変換

sp を人と出力のために書く変換は、そろっていない。

| 箇所 | 単位 | 桁 | 丸め | 負の値 | 単位の前の空白 | 使う diagnostic と出力 |
| --- | --- | --- | --- | --- | --- | --- |
| golem-preflight の [`mmText`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-preflight/src/Golem/Preflight.hs#L88-L93) | mm | 1 | 偶数へ | 符号を付ける | なし | G09004、G09010、G09011、G09012、G09013、G09018 |
| golem-driver の `Golem.Driver.Pdf.Flow` の [局所の `mm`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L1664-L1668) | mm | 1 | 偶数へ | 誤る | あり（`12.3 mm`） | G07041 |
| golem-project の `hiddenFolioChecks` の [`spToMm` と `mm2`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-project/src/Golem/Project/Style.hs#L861-L868) | mm | 2 | 半分を切り上げ | 誤る | なし | G03029 |
| golem-pdf の [`spToPt`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-pdf/src/Golem/Pdf/Number.hs#L17-L22) | pt | 4 | 偶数へ | 符号を付ける | （PDF の数） | PDF の座標 |
| golem-html の [`akiLength`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-html/src/Golem/Html.hs#L645-L651) | pt、em | 4 | 偶数へ | 符号を付ける | なし | HTML のアキ |
| golem-driver の `Golem.Driver.Html` の [`decimal3`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-driver/src/Golem/Driver/Html.hs#L130-L148) | pt、em | 3 | 偶数へ | 符号を付ける | なし | HTML と EPUB の CSS（`cssLength` と `cssFontSize`） |

後の三つは、`Golem.Syntax.Text.showRationalDigits` を共有しており、違うのは桁だけである（調査の R10）。
mm の三つは、それぞれ自分で十進の文字列を組み立てる。

「誤る」は、負の値を渡すと誤った文字列になることを指す。
手元の GHC で二つの関数をそのまま評価して確かめた。
`Flow` の `mm` は、商と余りを負の無限大の方向への `div` と `mod` で求めるので、-0.1mm に当たる -18577sp を `-1.9` と書く。
`mm2` は、-0.5mm を `-1.50mm` と書く。
今の二つの diagnostic に負の値が届くかどうかは、確かめていない。

mm の桁が 1 では足りない量もある。
`preflight.toml` の `stroke-weight` の既定の閾値は 0.1mm である（[golem-cli ADR 0006](../golem-cli/adr/0006-preflight.md)）。
0.06mm の線を 1 桁で書くと「0.1mm」になり、G09018 は `線が細すぎます: …（0.1mm、0.1mm 未満、…）` という、値と閾値が同じに見える文になる。

ほかに、golem-preflight の [`ppiOf`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-preflight/src/Golem/Preflight.hs#L95-L104) は、画素の数を sp で表した大きさで割って、1 インチあたりの画素の数を切り捨てで求める（`px × 72 × 65536 div sp`）。
golem-text は、アキの `zw` を全角の空白の数に直すときに、`floor` で切り捨てる（[`Golem.Text`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-text/src/Golem/Text.hs#L232)）。
golem-svg は、SVG の根の要素の長さを、CSS の px に直す独自の表を持つ（[`rootLength`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-svg/src/Golem/Svg.hs#L431-L436)）。
golem-svg は golem のどのパッケージにも依存しない。

### `type Sp = Integer` の六か所

`Sp` の型の別名は、次の六か所で別々に宣言されている（調査の R13）。

- golem-project の [`Golem.Project.Style`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-project/src/Golem/Project/Style.hs#L114-L115)
- golem-layout の [`Golem.Layout.Code`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-layout/src/Golem/Layout/Code.hs#L29)、[`Golem.Layout.Ruby`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-layout/src/Golem/Layout/Ruby.hs#L18)、[`Golem.Layout.KnuthPlass`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-layout/src/Golem/Layout/KnuthPlass.hs#L36)
- golem-driver の [`Golem.Driver.Overhang`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-driver/src/Golem/Driver/Overhang.hs#L23)
- golem-pdf の [`Golem.Pdf.Writer`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L58)

golem-preflight は golem-project の `Sp` を使う。
golem-syntax は、golem-svg を除くこれらのパッケージがすべて依存し、golem-syntax 自身は golem のパッケージに依存しない。
型の別名なので、sp の値と、ページの番号や字数のようなほかの整数を取り違えても、型の検査では見つからない。

### 丸めと出力

mm の表示をそろえると、G03029、G07041、G09004 などのメッセージの文言が変わる。
diagnostic も決定性の対象であり（仕様書の「設計原則」）、文言を変えるのは出力を変える変更である。
pt と em の桁をそろえれば、PDF か HTML と EPUB のどちらかのバイト列が変わる。
ロードマップは、この統一を [ADR 0101](0101-rational-numbers-in-expressions.md) と同じ時期に扱い、丸めで文言が変わる diagnostic をこのときに見直し、それ以外の diagnostic は v1.0.0 の「一つのコードに一つの原因の監査」で扱うとしている。

出力の変化を見るための検査は三つある。

- golem-driver の出力のゴールデン（`OutputGoldenSpec`）。PDF は `sample` と `figures`、EPUB は同じ二つ、HTML は `html-*.xhtml` と `html-style.css` を固定する（[ADR 0064](0064-goldens-that-fix-less-than-the-output.md)）。
- 見た目の回帰テスト。PDF のページを 72 dpi で描き、ページごとの SHA-256 をコミットした一覧と比べる（[ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md)）。PDF だけを見る。
- 決定性の検査。同じコミットを二つのアーキテクチャで組んで比べるので、コミットのあいだの変化は見ない。

今の HTML と EPUB のゴールデンに出る CSS の長さは `0.25em` と `0.85em` だけであり、どちらも小数点以下 2 桁で書き切れる。

### この ADR と組になる ADR

[ADR 0101](0101-rational-numbers-in-expressions.md) は、式の言語の数を自然数、整数、有理数にし、本文に数を埋め込む表記を決める。
[ADR 0102](0102-natural-number-type.md) は、負になりえない量を自然数で受け取る。
式の言語は長さの値を持たないので、この ADR の変換は式の評価と交わらない。
交わるのは、有理数を十進の文字列にする規則である。

## 実装すること

### 一か所の置き場所

golem-syntax に `Golem.Syntax.Length` を作り、長さの型と、単位の変換と、長さの表示をここに集める。

```haskell
-- 1pt = 65536sp。ほかの整数と取り違えないように newtype にする
newtype Sp = Sp {unSp :: Integer}
  deriving newtype (Eq, Ord, Show, Num)

data Unit = Pt | Mm | In | Q | H

-- 書かれた量（正確な有理数）を sp に、一度だけ、等距離なら偶数の側へ丸める
toSp :: Unit -> Rational -> Sp

-- zw を、その位置の文字の大きさで sp に直す（同じ丸め）
zwToSp :: Sp -> Rational -> Sp

-- sp を単位の正確な有理数にする（丸めない）
fromSp :: Unit -> Sp -> Rational

-- diagnostic に書く mm の表記
mmText :: Sp -> Text

-- 出力に書く pt と em の数の表記（小数点以下 4 桁）
ptText :: Sp -> Text
emText :: Rational -> Text
```

- 単位の比（1in = 72pt、1in = 25.4mm、1Q = 1H = 0.25mm）は、このモジュールにだけ書く。
- `Golem.Project.Style` の `parseDim`、`mmToSp`、`dimToSp`、`pageTrimSize` は、`toSp` と `zwToSp` を使う。`Dim` の型と、寸法の文字列を読む処理は golem-project に残す。
- `Golem.Layout.Japanese` のアキの計算は `zwToSp` を使う。
- golem-pdf の `spToPt`、golem-html の `akiLength`、golem-driver の `cssLength` と `cssFontSize` は、`ptText` と `emText` を使う。
- golem-preflight の `ppiOf` は、`fromSp In` で大きさをインチの有理数にしてから、今と同じく切り捨てる。
- `type Sp = Integer` の六つの宣言を消し、`Golem.Syntax.Length.Sp` を使う。

`Sp` は `newtype` にする。
`Num` を導出するので、sp どうしの足し算と、リテラルの `0 :: Sp` は今のまま書ける。
sp と `Integer` を混ぜる箇所には `Sp` か `unSp` を明示することになり、取り違えがコンパイルの誤りになる。
`Num` があるので sp どうしの掛け算も書けてしまうが、これを防ぐには演算を一つずつ定義し直す必要があり、六つのパッケージの書き換えがさらに増える。
取り違えのうち多いのは整数との混同なので、それを防ぐところまでにする。
意味論 IR の欄の型（アキの `sp` など）は、[ADR 0102](0102-natural-number-type.md) の `Natural` のままとし、IR を読む箇所で `Sp` に変える。

golem-syntax に置くので、パッケージのあいだの build-depends は変わらない。
golem-pdf が golem-project に依存する必要もない。

### mm の表記

diagnostic に書く mm の表記を一つにする。

- 小数点以下 2 桁にする。
- 正確な有理数（`fromSp Mm`）を、等距離なら偶数の側へ丸める。27pt（ちょうど 9.525mm）は `9.52mm` になる。
- 負の値は、絶対値を丸めてから `-` を付ける。丸めた値が 0 なら符号を付けない。
- 末尾の 0 は残す（`3.00mm`）。桁がそろっていれば、閾値と値を並べたときに見比べやすい。
- 単位の前に空白を入れない（`3.00mm`）。

2 桁にするのは、1 桁では閾値の近くの値が閾値と同じに見えるからである（上の `stroke-weight` の例）。
2 桁なら、0.06mm の線は `0.06mm` と書かれ、閾値の `0.10mm` と区別できる。
G03029 は今も 2 桁で書いているので、そちらに合わせることにもなる。

丸めを偶数の側にするのは、処理系が長さを丸めるほかの箇所（sp への変換、`showRationalDigits` による pt と em の表記）がすべて偶数の側へ丸めるからである。
書き手の多くは四捨五入のほうを見慣れている。
しかし、長さの表記は処理系が測った値を伝えるためのものであり、丸めの向きに偏りがない偶数への丸めのほうが、測った値の表記として自然である。
同じ長さが、変換の向きによって違う規則で丸められることもなくなる。
四捨五入は、書き手が値を決める式の `round` と `fixed` に残す（下の「式の言語との関係」）。

これに合わせて、次の diagnostic のメッセージが変わる。

| コード | 今 | この ADR の後 |
| --- | --- | --- |
| G03029 | `[hidden-folio] の gutter（1.50mm）が…`（2 桁、半分を切り上げ） | 桁は同じ。ちょうど半分の値だけ、偶数の側へ丸めた表記に変わる |
| G07041 | `表の列の最小の幅の合計（12.3 mm）が…`（1 桁、空白あり） | `表の列の最小の幅の合計（12.30mm）が…` |
| G09004、G09010、G09011、G09012、G09013、G09018 | `mmText` の 1 桁（`3.2mm`） | 2 桁（`3.18mm`） |

G09004 の事実の `size` と、G09013 の事実の `overfull` は、`mmText` の文字列を値に持つ。
JSON の diagnostics のこの二つの値も、2 桁に変わる。

G03029 の直し方の値（「gutter を X 以上にするか、size を Y 以下にします」）は、今と同じく 0.01mm 単位で探し、探した値をそのまま 2 桁で書く。
探した値は 0.01mm の倍数なので、書いた値は丸めずに正確である。
書き手がその値を写して `style.toml` に書けば、G03029 は出ない。
探す処理は、`mm2` の代わりに `mmText (toSp Mm (k / 100))` で書く。
sp の刻み（約 0.0000054mm）は 0.005mm よりずっと小さいので、0.01mm の倍数を sp に直して戻しても、2 桁の表記は元の値になる。
facts（JSON の diagnostics の `gutter`、`size`、`min-gutter`、`max-size`）は sp のままで、値も変わらない。

### pt と em の表記

出力に書く pt と em の数の桁を、小数点以下 4 桁にそろえる。
丸めは今と同じく偶数の側へ、末尾の 0 は書かない（`showRationalDigits 4`）。

4 桁にするのは次の理由による。

- PDF の座標と寸法は、すでに 4 桁である（[golem-pdf ADR 0001](../golem-pdf/adr/0001-deterministic-pdf-writer.md)）。4 桁にそろえれば PDF のバイト列は変わらず、PDF のゴールデンと見た目の回帰テストのページの一覧を更新せずに済む。3 桁にそろえると、すべての PDF の多くの座標が変わる。
- 0.0001pt は約 0.000035mm であり、印刷でも画面でも見分けられない。3 桁（約 0.00035mm）でも足りるが、4 桁に広げても困ることはない。
- HTML のアキ（`akiLength`）も 4 桁なので、HTML の中で桁が二通りあった状態がなくなる。

出力のうち変わるのは、HTML と EPUB の CSS の長さ（`cssLength` と `cssFontSize` が書く値）だけである。
小数点以下 4 桁めが 0 でない長さだけが変わる。
たとえば `style.toml` に `3mm` と書いた字下げは、`8.504pt` から `8.5039pt` に、9pt の文字を 12.6pt の基準で書いた `font-size` は `0.714em` から `0.7143em` に変わる。

変わるものと変わらないものは次のとおりである。

| 検査と出力 | 変わるか |
| --- | --- |
| PDF のバイト列 | 変わらない |
| PDF のゴールデン（`sample`、`figures`） | 変わらない |
| 見た目の回帰テストのページの一覧（[ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md)） | 変わらない。PDF だけを描くからである |
| HTML と EPUB のゴールデン（`html-style.css`、`epub-sample.txt`、`epub-figures.txt` など） | 変わらない。CSS の長さは `0.25em` と `0.85em` だけで、4 桁でも同じ表記になる |
| HTML と EPUB の CSS（ゴールデンのない fixture、マニュアル、利用者のプロジェクト） | mm、Q、H などで書いた長さと、比で書く `font-size` の多くが変わる |
| プレーンテキスト | 変わらない |
| diagnostic のメッセージ | 上の「mm の表記」の表のとおり変わる |

プルリクエストでは、この表のとおりであることを、ゴールデンが変わらないことと、二つのマニュアルの HTML の CSS の差分が数の桁だけであることで確かめる。

図版の描画の数（`Golem.Pdf.Drawing` の 6 桁と、Form XObject の `BBox` の 6 桁と `Matrix` の 10 桁）は、sp を書き出す変換ではないので、この ADR では変えない。
図版の座標系の数であり、sp の長さを pt に直したものではないからである。

### 式の言語との関係

[ADR 0101](0101-rational-numbers-in-expressions.md) の `round` と `fixed` は、0 から遠い方向へ丸める（書き手の四捨五入）。
この ADR の mm、pt、em の表記と、sp への変換は、偶数の側へ丸める。
丸めの規則は二つ残る。
式の `round` と `fixed` は書き手が値を決めるための関数であり、四捨五入の期待に合わせる。
単位の変換と長さの表記は処理系が長さを決めて伝える規則であり、偏りのない偶数への丸めを使う。
この区別を仕様書の「数の規則」と「長さの単位」に書く。

### ほかの ADR との関係

この ADR は、次の規則を置き換える。
採択したら、それぞれのステータスの行に、置き換えた部分とこの ADR へのリンクを足す。

- [golem-cli ADR 0006](../golem-cli/adr/0006-preflight.md)：プリフライトの diagnostic の mm の桁（小数点以下 1 桁）。
- [docs/adr/0003](0003-verse-line-breaks.md)：CSS の長さの桁（小数は 3 桁まで）。

### モジュールと依存

- golem-syntax：`Golem.Syntax.Length` を足す。
- golem-project、golem-layout、golem-driver、golem-pdf、golem-preflight、golem-html：変換と `Sp` を `Golem.Syntax.Length` から使う。
- build-depends は変えない。どのパッケージも、すでに golem-syntax に依存している。

### ドキュメント

- 仕様書の「style.toml」の単位の節に、変換の規則（正確な有理数から一度だけ、偶数の側へ）と、diagnostic の mm の表記と、出力の pt と em の桁を書く。
- `docs/diagnostics.md` の G03029、G07041、G09004、G09010、G09011、G09012、G09013、G09018 のメッセージの例を改める。
- 使い手のマニュアルの、プリフライトと検査の章のメッセージの例を改める。
- 開発者のマニュアルのモジュールの説明に、`Golem.Syntax.Length` を足す。

## 実装しないこと

- golem-svg の長さの変換を `Golem.Syntax.Length` に移すこと。SVG の座標は CSS の px（1in = 96px）の体系であり、Golem の sp と別の変換である。移すには golem-svg が golem-syntax に依存する必要があり、build-depends を変える ADR が要る。
- 図版の描画の数（6 桁と 10 桁）の桁を変えること。
- golem-text のアキの `floor` を変えること。プレーンテキストの全角の空白の数は、長さを丸める処理ではなく、空白を何個置くかの判断である。
- `Sp` の掛け算を型で禁じること。
- 意味論 IR の欄の型を `Sp` にすること。
- 新しい単位（`cm`、`pc`、`px`）を加えること（[golem-project ADR 0010](../golem-project/adr/0010-inch-unit.md) のとおり）。
- 丸めで文言が変わらない diagnostic の見直し。v1.0.0 の「一つのコードに一つの原因の監査」で扱う。

## テスト設計

先に次のテストを書き、今のコードで失敗することを確かめてから実装する。
`Golem.Syntax.Length` のテストは、モジュールがない状態でコンパイルが失敗することを確かめる。

### golem-syntax

- `toSp Pt 1 = 65536`、`toSp In 1 = 4718592`、`toSp Mm 25.4 = 4718592`、`toSp Q 4 = toSp Mm 1`、`toSp H 4 = toSp Mm 1` であること。
- 性質：任意の有理数 `r` について、`toSp Mm r` が `round (r × 72 × 65536 / 25.4)` と等しく、`toSp Pt r` が `round (r × 65536)` と等しいこと（今の `parseDim` と同じ値になることを、変換の前後で固定する）。
- 性質：任意の sp `s` について `fromSp Pt s × 65536 = unSp s`、`fromSp In s × 72 × 65536 = unSp s` であること。
- `zwToSp 655360 (1/4) = 163840`、`zwToSp 10 (1/4) = 2`（2.5 は偶数の側へ）、`zwToSp 14 (1/4) = 4`（3.5 は偶数の側へ）であること。
- `mmText 18577` が `0.10mm`、`mmText (-18577)` が `-0.10mm`、`mmText 0` が `0.00mm`、`mmText (-1)` が `0.00mm`（符号を付けない）、`mmText (toSp Mm 3)` が `3.00mm`、`mmText (toSp Pt 18)`（ちょうど 6.35mm）が `6.35mm`、`mmText (toSp Pt 27)`（ちょうど 9.525mm）が `9.52mm`（偶数の側へ）、`mmText (toSp Pt 9)`（ちょうど 3.175mm）が `3.18mm` であること。今の `Flow` の `mm` は -18577 を `-1.9` と書くので、この性質を `Flow` の呼び出しで確かめるテストは失敗する。
- 性質：任意の自然数 `k` について、`mmText (toSp Mm (k / 100))` が `k / 100` を 2 桁で書いたものと等しいこと（G03029 の直し方の値が丸められないこと）。
- `ptText 1` が `0`（4 桁めの後で丸めて 0）、`ptText 65536` が `1`、`ptText (toSp Mm 3)` が `8.5039`、`emText (9 / 12.6)` が `0.7143` であること。

### golem-project

- G03029 のメッセージが、今と同じ 2 桁の mm で書かれ、直し方の値を写して `style.toml` に書くと G03029 が出ないこと。
- 判型の表のすべての名前で、`pageTrimSize` の値が変更の前後で変わらないこと。

### golem-preflight

- G09018 の閾値の近くの線（0.06mm）で、メッセージが `0.06mm` と `0.10mm` を書くこと。今は両方が `0.1mm` になる。
- G09004 と G09013 の事実の `size` と `overfull` が 2 桁の mm であること。

### golem-driver

- G07041 のメッセージが `（12.30mm）` の形になること。
- `style.toml` に `indent = "3mm"` と書いたプロジェクトの HTML の CSS が `8.5039pt` を書くこと。今は `8.504pt` である。
- `OutputGoldenSpec` のゴールデンが、変更の前後で変わらないこと。
- PDF の出力のバイト列が変わらないことを、`OutputGoldenSpec` と見た目の回帰テストのページの一覧で確かめる。

### 型の別名

- `rg 'type Sp = Integer'` が何も返さず、`rg 'newtype Sp'` が `modules/golem-syntax/src/Golem/Syntax/Length.hs` の一行だけを返すことを、CI の検査ではなくプルリクエストのレビューで確かめる。

## トレードオフ

- プリフライトの六つの diagnostic と G07041 の文言が変わる。1 桁では閾値の近くの値が閾値と区別できないので、文言の変更を受け入れる。
- 偶数の側への丸めは、書き手が手で四捨五入した値と、ちょうど半分の場合だけ食い違う。sp から mm に直した値が小数点以下 3 桁めでちょうど半分になるのは、9pt の奇数倍の長さだけである（9pt は 3.175mm）。
- HTML と EPUB の CSS の長さの多くが変わる。PDF のバイト列を変えない 4 桁を選び、変わる出力を CSS に限った。CSS の 4 桁めは、ブラウザーの描画では見分けられない。
- `Sp` を `newtype` にすると、六つのパッケージの多くの式に `Sp` と `unSp` が入る。整数との取り違えをコンパイルの誤りにすることと引き換えにする。
- golem-syntax は構文と位置の型のパッケージであり、長さの単位は構文ではない。新しいパッケージ（golem-units など）を作れば責務は分かれるが、六つのパッケージの build-depends を変える ADR が要る。golem-syntax には `showRationalDigits` のような数の表記の関数がすでにあり、どのパッケージも依存しているので、ここに置く。
- 丸めの規則が二つ（式の四捨五入と、単位の変換と表記の偶数への丸め）残る。一つにするには、書き手の `round(2.5)` を 2 にするか、長さの丸めに偏りを入れるかのどちらかが要る。

## 決めたことの記録

草案で開いていた点を、次のとおりに決めた。

- **置き場所**：メンテナーが、golem-syntax の `Golem.Syntax.Length` を承認した。
- **`Sp` の型**：メンテナーが、`newtype` にすると決めた。導出する型クラス（`Eq`、`Ord`、`Show`、`Num`）と、IR の欄を `Sp` にしないことは、この版で決めた。
- **mm の表記の桁と丸め**：メンテナーが、小数点以下 2 桁、偶数の側への丸めと決めた。
- **G03029 の直し方の値の探索**：メンテナーが、表示と同じ 2 桁（0.01mm）とすると決めた。今の探索の単位と同じなので、探索は変わらない。
- **単位の前の空白**：メンテナーが、入れないと決めた。
- **golem-svg**：メンテナーが、今は範囲の外とすると決めた。
- **pt と em の桁**：メンテナーが、この ADR でそろえると決めた。桁は、この版で 4 桁を選んだ。PDF のバイト列を変えないためである。
- **末尾の 0**：メンテナーの指示はなく、草案の案（mm の表記では残す）を保った。

## 参考文献

- [2026-10-25 のリファクタリングの調査](../audits/2026-10-25-refactoring-survey.md) の R10、R11、R13
- [ADR 0087](0087-test-support-dependencies-and-shared-fixtures.md) の「単位の変換の統一」
- [ADR 0064](0064-goldens-that-fix-less-than-the-output.md)、[ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md)
- [golem-project ADR 0010](../golem-project/adr/0010-inch-unit.md)
- [golem-driver ADR 0041](../golem-driver/adr/0041-hidden-folio-overlap-check-by-size.md)
- [golem-pdf ADR 0001](../golem-pdf/adr/0001-deterministic-pdf-writer.md)
- [golem-cli ADR 0006](../golem-cli/adr/0006-preflight.md)
- Donald E. Knuth, The TeXbook, Addison-Wesley, 1984（sp と pt の定義）
