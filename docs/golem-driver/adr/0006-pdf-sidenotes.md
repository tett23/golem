# ADR 0006: 傍注を PDF に出力する

ステータス: 採択→段組みの版面での傍注欄の扱いは [docs/adr/0018](../../adr/0018-multi-column-layout.md)、傍注の番号の印の組み方と番号を振る範囲は [ADR 0018](0018-footnote-marks-and-numbers.md)、傍注の書体と大きさの欄は [ADR 0011](0011-sidenote-font.md)

## 文脈

[golem-layout ADR 0006](../../golem-layout/adr/0006-sidenotes.md) は、傍注欄の中で傍注を並べる規則を定めた。
golem-layout には、その部品の実装とテストがある。
`Golem.Layout.Sidenotes` の `placeSidenotes` が傍注欄の中の縦の位置を決め、`Golem.Layout.Japanese` の `verticalSidenotes` が縦組みの段落の中の傍注を G07032 として報告する。
傍注欄の矩形は、`Golem.LayoutSpec` の `sidenoteAreaFor` が奇数ページと偶数ページについて返す（[golem-layout-spec ADR 0001](../../golem-layout-spec/adr/0001-page-geometry.md)）。

PDF のパイプライン（[ADR 0002](0002-pdf-pipeline.md)）は、これらを使っていない。
`composeInlines` は傍注から `AnchorSidenote` と番号の箱を作るが、`Golem.Driver.Pdf` の `buildFlow` は `AnchorNote` だけを拾い、`AnchorSidenote` を捨てる。
そのため、PDF には本文の番号だけが出て、傍注の本文は出ない。
`verticalSidenotes` もパイプラインから呼ばれていないので、縦組みの原稿の傍注はエラーにならない。
`style.toml` の `marker` も使われておらず、本文の印はつねに番号である。

v1 の傍注は横組みに限る（[仕様書](../../specifications.md) の傍注の節）。

## 実装すること

### 傍注を使える原稿の検査

`buildFlow` の前に、本の全体の傍注を検査する関数を `Golem.Driver.Pdf` に加える。

```haskell
sidenoteDiagnostics :: PageGeometry -> Book -> [Diagnostic]
```

| 診断 | 条件 | 位置 |
|---|---|---|
| G07032 | 縦組みの版面で傍注を使った。`verticalSidenotes` をそのまま使う。 | 傍注 |
| G07034 | 横組みの版面で傍注を使ったが、`style.toml` に `[sidenotes]` がない。 | 傍注 |
| G07035 | 脚注の本文、または図版のキャプションの中に傍注を置いた。 | 傍注 |

診断は傍注ごとに出す。
一つでもあれば、行分割とページへの配置を行わずにエラーで止める。

縦組みの版面に `[sidenotes]` を書いた場合は、すでに `pageGeometry` が G07001 を出すので、この関数は呼ばれない。

G07034 は、傍注欄のない版面で傍注を黙って捨てないためのものである。
脚注に振り替えることは、[golem-layout ADR 0006](../../golem-layout/adr/0006-sidenotes.md) が書き手の意図しない形に注を変えるとして退けている。

G07035 は、印を含む行の位置が傍注の希望の位置を決めるという規則が、脚注の本文とキャプションの中では成り立たないためのものである。
脚注の本文の行はページの下部に、キャプションの行は図版の下に置かれ、どちらも本文の流れの行ではない。
HTML、EPUB、プレーンテキストはこれらの位置の傍注も出力できるが、PDF だけの制約として扱う。
同じ原稿が PDF のターゲットでだけエラーになるのは、G07032 と同じである。

### 本文の印

golem-layout の `ComposeEnv` に `ceSidenoteMarker :: SidenoteMarker` を加える。

```haskell
data SidenoteMarker = MarkerNumber | MarkerSymbol | MarkerNone
```

- `MarkerNumber`（既定）：これまでどおり、番号の箱を置く。
- `MarkerSymbol`：「※」の箱を、本文の文字の大きさの幅で置く。
- `MarkerNone`：箱を置かず、`AnchorSidenote` だけを置く。

`composeEnv` は `style.toml` の `[sidenotes]` の `marker` から値を決める。
`[sidenotes]` がなければ `MarkerNumber` とする。
この場合の傍注は G07034 で止まるので、値は使われない。

### 傍注の本文の組版

`AnchorSidenote` に傍注の `SrcSpan` を加え、診断の位置に使う。

```haskell
AnchorSidenote !Int !Int !SrcSpan [Inline] -- item index, sidenote number, span, body
```

`buildFlow` は、段落を組む仕事の中で、脚注と同じく傍注の本文を組む。

- 文字の大きさ `s` は `[sidenotes]` の `size` とし、省略時は本文の文字の大きさとする。
- 行送り `p` は、本文の行送りを文字の大きさの比で縮めた値 `本文の行送り × s ÷ 本文の文字の大きさ`（整数の除算）とする。
- 行長は傍注欄の幅とする。奇数ページと偶数ページで幅は同じなので、ページが決まる前に組める。
- 本文の先頭に印を付ける。`MarkerNumber` では番号と半角の空白、`MarkerSymbol` では「※」と半角の空白を付け、`MarkerNone` では何も付けない。
- 組版の環境は、`composeEnv` の `ceFontSize` を `s` にしたものとする。行分割の `kpParams` の `pEmergencyStretch` も `s` を基準に計算する。ページ番号への参照は、本文と同じく S2 の仮の値で組む。
- 傍注の高さは `(行数 − 1) × p + s` とする。

`SetLine` に `slSidenotes :: [(SrcSpan, [Line])]` を加え、傍注の印を含む行に、その傍注の本文の行を持たせる。
印を含む行の求め方は、脚注と同じ `lineIndexOfItems` を使う。
一つの行に複数の傍注がある場合は、行の中の出現の順に並べる。

フォントは本文のフォントを使う。
`[sidenotes]` の `font` は、見出しの `font` と同じく役割ごとのフォントの仕組みが PDF のパイプラインにできるまで使わない（[仕様書](../../specifications.md) の「見出しの書体と大きさ」の項目）。

### 傍注欄での配置

傍注欄での配置は、ページ番号の解決（S2）が収束した後に、最終回のページと行に対して一度だけ行う。
傍注の配置はページへの配置に影響しないので（[golem-layout ADR 0006](../../golem-layout/adr/0006-sidenotes.md)）、S2 の各回で行う必要はない。

```haskell
placePageSidenotes :: PageGeometry -> Sp -> Map Int SetLine -> PageOut -> Either [Diagnostic] [PlacedSidenote]
-- 版面の幾何、傍注の行送り p、行、ページ
```

ページごとに、次の手順で配置する。

1. `poSlots` を格子の番号の順にたどり、`SLine` の行の `slSidenotes` を順に集める。`FWrapped` の脇の行も `SLine` なので、同じ扱いになる。
2. 各傍注の希望の位置を、印を含む行の字面の上端とする。横組みの行の格子では、格子の番号 `k` の行の字面の上端は、版面の上辺から `k × 本文の行送り` 下にある。傍注欄の上端と高さは版面と同じなので、この値をそのまま傍注欄の上端からの距離に使う。
3. `placeSidenotes 傍注欄の高さ (本文の行送り ÷ 2) [(希望の位置, 傍注の高さ)]` で上端を決める。
4. `Left (TooTall i)` と `Left (DoesNotFit i)` は、i 番目の傍注の `SrcSpan` を示す G07033 にする。

| 診断 | 条件 |
|---|---|
| G07033 | 一つの傍注が傍注欄の高さを超える（`TooTall`）。または、前の傍注を上へ詰めても傍注欄に収まらない（`DoesNotFit`）。メッセージで二つを区別する。 |

`placeSidenotes` はページごとに最初の失敗だけを返すので、G07033 はページごとに最大で一つになる。
すべてのページを調べ、ページの順に診断を集める。
一つでもあれば PDF を書かずにエラーで止める。

### 改ページとの関係

[golem-layout ADR 0006](../../golem-layout/adr/0006-sidenotes.md) の決定に従い、傍注は改ページを変えない。

- 傍注は、印を含む行が置かれたページに置く。段落がページをまたぐ場合、段落の孤立の規則で行が次のページに送られる場合、脚注の量で行が次のページに送られる場合、回り込みの図版とともに脇の行が送られる場合（[ADR 0005](0005-pdf-wrapped-figures.md)）のいずれでも、傍注は行についていく。
- 傍注が傍注欄に収まらないページがあっても、本文の行を次のページに送らない。G07033 で書き手に知らせる。
- 傍注の本文の行数は `LineBox` に載せないので、`paginate` は傍注を知らない。印の箱の幅は本文の行分割に影響するが、傍注の本文の長さは影響しない。

傍注の本文にページ番号への参照がある場合、本文の表記の幅は S2 の各回で変わりうる。
しかし傍注の本文は `paginate` に渡らないので、ページ番号の収束には関わらない。
配置と G07033 の判定は、収束した最終回の本文の行で行う。

### 描き方

`writeDocument` は、`drawLine` から、行の始まりの点を受け取って行を描く部分を `drawLineAt` として切り出す。
本文の行は、これまでどおり版面と格子から始まりの点を計算して `drawLineAt` を呼ぶ。

傍注は、ページ `n` の傍注欄 `sidenoteAreaFor geom n` の中に描く。
上端が `t` の傍注の `j` 行目（0 から数える）のベースラインは、傍注欄の上辺から `t + j × p + round(s × baselineRatio)` 下に置き、行の始まりを傍注欄の左辺とする。
文字の大きさは `s` とする。
傍注のグリフは `drawLineAt` が返す使用済みのグリフに含まれるので、フォントのサブセットにも入る。

### データ構造

```haskell
-- Golem.Driver.Pdf
data SetLine = SetLine
  { slLine :: !Line,
    slSize :: !Sp,
    slIndent :: !Sp,
    slNotes :: ![(Int, [Line])],
    slSidenotes :: ![(SrcSpan, [Line])]
  }

data PlacedSidenote = PlacedSidenote
  { psSpan :: !SrcSpan,
    psTop :: !Sp, -- 傍注欄の上端からの距離
    psLines :: ![Line]
  }

data PdfLayout = PdfLayout
  { plPages :: ![PageOut],
    plLines :: !(Map Int SetLine),
    plFigures :: !(Map Int PlacedFigure),
    plSidenotes :: !(Map Int [PlacedSidenote]) -- ページの番号ごと
  }
```

`slIndent`、`PlacedFigure`、`PdfLayout`、`layoutPdf` は [ADR 0005](0005-pdf-wrapped-figures.md) で加えるものであり、この ADR は `slSidenotes` と `plSidenotes` を足す。

### 決定性

寸法はすべて整数の sp で計算する。
傍注を集める順序は、格子の番号の順と行の中の出現の順で決まり、並列に組んだ傍注の本文も文書の順に並べ直した行に付く（[docs/adr/0002](../../adr/0002-determinism.md)）。
配置は収束した最終回の結果だけから決まる純粋な関数である。

### ドキュメント

- [仕様書](../../specifications.md) の「v1 の実装で次の段階以降に回した項目」から、傍注の項目を削る。
- [仕様書](../../specifications.md) の傍注の節に、`[sidenotes]` がない横組みの版面で傍注を使うとエラーになること、脚注の本文とキャプションの中の傍注は PDF でエラーになることを書き、この ADR へのリンクを付ける。
- [記法の仕様](../../markup.md) の傍注の節に、同じ二つの制約を書く。

## 実装しないこと

- 縦組みの傍注（[仕様書](../../specifications.md) の「v2 以降に回した事項」）。
- `[sidenotes]` の `font` による書体の指定。役割ごとのフォントの仕組みを PDF のパイプラインに入れるときに、見出しと一緒に扱う。
- 収まらない傍注を脚注に回すこと、および傍注のために本文の行を次のページに送ること。
- 脚注の本文とキャプションの中の傍注の配置。
- 段組みの版面での傍注欄。

## テスト設計

golem-driver のテスト（modules/golem-driver/test/Main.hs）に加える。
フォントは `fakeFonts` を使う。
横組みのスタイルは、既存の `horizontalStyle`（A5、10pt、12 字、30 行、行送り 15pt）に `[sidenotes]` の `width = "6zw"`、`gap = "1zw"`、`size = "8pt"` を足したものとする。
傍注の行送り `p` は 12pt、傍注欄の高さは 445pt になる。
各テストは `layoutPdf` の `PdfLayout` を調べる。

- 傍注を一つ含む段落で、傍注が印を含む行と同じページの `plSidenotes` にあり、`psTop` がその行の格子の番号 × 15pt であること。
- 隣り合う二行にそれぞれ二行の傍注（高さ 20pt）を置くと、二つめの `psTop` が一つめの `psTop + 20pt + 7.5pt` に等しくなり、順序が保たれること。
- ページの最後の行に傍注を置き、前の行にも傍注を置くと、最後の傍注が傍注欄の下端に収まり、前の傍注が上へ詰められること。
- 一ページの行の印に、傍注欄に収まらない量の傍注を付けると、G07033 になり、収まらない傍注の `SrcSpan` が示されること。傍注欄より高い一つの傍注でも G07033 になること。
- 傍注の本文だけを短いものと長いもの（どちらも収まる）に変えた二つの原稿で、`plPages` が一致すること。
- 段落がページをまたぎ、次のページの行に印がある場合、傍注が次のページに置かれること。
- `marker = "symbol"` では本文と傍注の本文の両方に「※」（U+203B）のグリフが出ること。`marker = "none"` では、本文の行の箱の数が傍注を除いた原稿と同じになり、傍注の本文の先頭に印がないこと。
- `[sidenotes]` のない横組みのスタイルで傍注を使うと G07034 になること。縦組みのスタイル（既存の `pdfStyle`）で傍注を使うと G07032 になること。`[note: ...]` の中と図版のキャプションの中の傍注が G07035 になること。
- 傍注の本文の文字が、傍注欄の矩形の中に描かれること。`drawLineAt` に渡す始まりの点の x が傍注欄の左辺に一致し、PDF の内容に大きさ 8 の `Tf` が現れることで確かめる。
- 傍注の本文にページ番号への参照を置いた原稿が、エラーなしに収束すること。
- 傍注を含む原稿を並列と逐次でビルドし、PDF のバイト列が一致すること。二回のビルドでも一致すること。

golem-layout のテスト（modules/golem-layout/test/Main.hs）に加える。

- `ceSidenoteMarker` ごとに、`composeInlines` が返す箱の内容（番号、「※」、なし）と、`AnchorSidenote` が傍注の `SrcSpan` を持つこと。

## トレードオフ

傍注の配置を S2 の後に一度だけ行うので、G07033 は本文のページが確定した後にしか分からない。
傍注の量で改ページを変えないという決定の帰結であり、配置を各回で行っても結果は同じになる。

脚注の本文とキャプションの中の傍注を PDF でエラーにするので、Web の媒体では使える書き方が PDF では使えない。
これらの位置の傍注は、どの行の注かという対応が本文の流れの外にあり、傍注欄に置く根拠となる行がない。
本文の流れにある行に移すよう書き手に求めるほうが、置き場所を推測するより確かである。

傍注の書体を本文と同じにする。
`font` の設定は読み込まれるが、PDF には反映されない。
見出しの書体と同じ状態であり、役割ごとのフォントを入れる ADR でまとめて解消する。
