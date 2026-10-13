# ADR 0005: 回り込みの図版を PDF のパイプラインにつなぐ

ステータス: 採択→段組みの版面での回り込みの扱いは [docs/adr/0018](../../adr/0018-multi-column-layout.md)

## 文脈

[golem-layout ADR 0004](../../golem-layout/adr/0004-wrapped-figures.md) は、`wrap` を指定した図版から除外領域を作り、行長 L*(i) と改ページにつなぐ規則を定めた。
golem-layout には、その部品の実装とテストがある。
`Golem.Layout.Wrap` の `exclusion` と `wrappedLineWidth` が除外領域と L*(i) を計算し、`Golem.Layout.Paginate` の `FWrapped` が図版と脇の行を一つの塊としてページに置く。

PDF のパイプライン（[ADR 0002](0002-pdf-pipeline.md)）は、これらを使っていない。
`Golem.Driver.Pdf` の `buildFlow` は、すべての段落を `breakParagraph params (const measure)` で組み、図版をすべて `FFigure` にする。
`figWrap` と `figWidth` は読まれず、図版の幅はつねに版面の行長である。

図版の描き方にも、回り込みの前に直すべき点が二つある。
一つは、キャプションと図番号を PDF に出していないことである。
`unitsOf` は `figCaption` を捨てており、`FFigure` の行数は画像の高さだけから決まる。
除外領域はキャプションを含む矩形なので（[golem-layout ADR 0004](../../golem-layout/adr/0004-wrapped-figures.md)）、キャプションを組まなければ除外領域の大きさが決まらない。
もう一つは、`writeDocument` の `figureRect` が縦組みでも横組みの式で矩形を計算していることである。
縦組みの図版は、行の送りの方向（右から左）ではなく版面の左下を基準に置かれ、行数の見積もりも画像の縦の長さで行われている。

## 実装すること

### 図版の大きさ

画像の行の方向の長さを `along`、行の送りの方向の長さを `across` と呼ぶ。
横組みでは `along` が幅、`across` が高さであり、縦組みでは逆になる。

- 回り込ませない図版の `along` は、これまでどおり版面の行長とする。
- 回り込ませる図版の `along` は、`figWidth` を `parseDim`（golem-project）で読み、本文の文字の大きさで sp に変換した値とする。`zw` は本文の文字の大きさを基準にする。
- `across` は、`along` と画像の縦横の画素数から整数の除算で求める。横組みでは `along × 高さ ÷ 幅`、縦組みでは `along × 幅 ÷ 高さ` である。
- 画像が占める行の格子の数を `m = ⌈across ÷ 行送り⌉` とする。

`loadFigures` は画像の読み込みだけを行い、`Map Text (Maybe P.ImageData)` を返す。
同じ画像を異なる `width` で使う場合があるので、大きさは `buildFlow` で図版ごとに計算する。

### キャプション

- キャプションの内容は、S1 の図番号（`bookFigures` を図版のブロックの `SrcSpan` で引いたもの）、全角の空白、`figCaption` の段落のインラインをこの順に並べたものとする。HTML の `figcaption` と同じ内容である。
- キャプションは本文と同じフォントと文字の大きさで、`along` を行長として組む。行分割は本文と同じ `composeEnv` と `kpParams` を使う。
- キャプションの行は、画像が占める `m` 個の格子の直後の格子から、`n` 行を置く。
- 図版がページの上で占める格子の数は `m + n` とする。回り込ませない図版の `FFigure` の `ffLines` もこの値にする。

キャプションの行を行の格子に載せるので、図版の後の本文も格子からずれない。

### 除外領域

回り込ませる図版について、`exclusion side pitch gap along depth` で除外領域を作る。

- `gap` は `style.toml` の `stWrapGap` を本文の文字の大きさで sp にした値とする。
- `depth` は、キャプションがある場合は `(m + n − 1) × 行送り + 文字の大きさ`、ない場合は `across` とする。最後の行の字面の端までを図版の範囲とするためである。
- `exWidth` は `along + gap`、`exLines` は `⌈(depth + gap) ÷ 行送り⌉` になる（`exclusion` の既存の計算）。

次の場合はコンパイルエラーとし、図版のブロックの `SrcSpan` を示す。

| 診断 | 条件 |
|---|---|
| G0722 | `width` が寸法として読めない。または、版面の行長から `exWidth` を引いた残りが、本文の文字の大きさの 8 倍に満たない。 |
| G0723 | `exLines` が一ページの行数を超える。 |

G0722 の下限は、脇の行が数文字分の長さになる組版を防ぐためのものである。行が短いと伸縮できる箇所が足りず、Knuth-Plass の行分割が許容度の中で解を見つけられなくなる。
G0723 は、[golem-layout ADR 0004](../../golem-layout/adr/0004-wrapped-figures.md) の「除外領域がページの終わりを越えることは許さない」を実装する。
`paginate` の `FWrapped` は、空のページでは大きさを確かめずに置くので、この検査をページへの配置の前に行う。

### 脇の行の組み方

`buildFlow` は、段落の行分割を次の二段に分け、それぞれを並列または逐次に実行する。

1. 回り込ませる図版ごとに、一つの仕事を作る。仕事は、図版の直後に続く `UPara` の単位を文書の順に逐次に組む。段落の開始の位置 `offset` を 0 から始め、各段落を `wrappedLineWidth measure ex offset` を L*(i) として組み、組んだ行数を `offset` に足す。`offset` が `exLines` に達するか、`UPara` でない単位が来たところで仕事を終え、組んだ段落の数を返す。
2. 1 の仕事を互いに並列に実行する。仕事どうしは独立である。図版の脇の段落は、次の回り込みの図版より前で必ず終わるためである。
3. 1 の仕事が組まなかった単位を、それぞれ一つの仕事として、`const measure` で並列に組む。
4. すべての結果を、完了の順ではなく文書の順に並べ直してから行に番号を振る（[ADR 0002](0002-pdf-pipeline.md) の並列性の規則）。

見出し、定義リストの用語、ほかの図版、目次などの `UPara` でない単位が来たら、そこで除外領域の脇の行は終わる。
除外領域の残りの格子は空けたままにし、その単位は除外領域の後の格子から置く。
`paginate` の `FWrapped` は、図版の格子の数と脇の行の数の大きいほうを使うので、この空きは既存の実装でそのまま得られる。

脇の行は除外領域の前後で長さが変わるが、`wrap=start` では行の始まりの位置も変わる。
`SetLine` に行の始まりのずらし `slIndent` を加え、`wrap=start` の除外領域にかかる行では `exWidth`、それ以外の行では 0 とする。
`drawLine` は、行の中の位置に `slIndent` を足してから `origin` を計算する。

### 流れの作り方

図版の仕事の結果から、次の `Flow` を作る。

- 図版と、除外領域にかかる行（最大で `exLines` 行。複数の段落にまたがってよい）を、`FWrapped id exLines labels beside` にする。`labels` は図版のラベルである。
- 除外領域にかかる行が段落の途中で終わる場合、その段落の残りの行を、新しい `FContinued [LineBox]` にする。
- それより後の段落は、これまでどおり `FParagraph` にする。

`FContinued` は golem-layout の `Paginate` に加える構成子である。
`placeLines` を `isStart = False` で呼び、段落の最初の行の孤立の規則を適用しない。
段落の最初の行は `FWrapped` の中にあり、残りの行の先頭は段落の先頭ではないためである。
最後の行の孤立の規則はそのまま適用する。

### 改ページとのつなぎ方

改ページの規則は、golem-layout の既存の実装と [golem-layout ADR 0004](../../golem-layout/adr/0004-wrapped-figures.md) に従い、この ADR では変えない。

- `FWrapped` の大きさ（`exLines` と脇の行の数の大きいほう）がページの残りに収まらない場合は、図版を脇の行とともに次のページの先頭に送る。
- 送ったページの残りは空白のままにする。脇の行は除外領域の幅で組まれているので、図版の前に詰めることはできない。[golem-layout ADR 0003](../../golem-layout/adr/0003-pagination-and-s2.md) の「送った図版より後の本文は、図版の前に詰めてよい」は許可であり、義務ではない。
- G0723 の検査によって `exLines` は一ページの行数以下なので、送った先のページで除外領域がページの終わりを越えることはない。
- 脇の行に脚注の印がある場合は、`placeLines` の既存の処理で脚注の本文の行数がページの残りから引かれる。このとき `FWrapped` の大きさの見積もりは脚注を含まないので、脇の行の一部が収まらない場合がある。その場合は、`placeLines` の既存の処理で、収まらない行が次のページに送られる。

ページ番号の解決（S2）の各回は、ページ番号の仮の値から `buildFlow` をやり直す。
参照の表記の幅が変わると脇の段落の行数が変わり、除外領域にかかる行の集合も変わるが、これは各回の入力から決まる。
L*(i) は除外領域の始まりからの行の番号だけで決まり、図版が置かれるページには依存しない。
そのため、図版を次のページに送っても行分割はやり直さず、S2 の繰り返しの回数は増えない。

### 図版の描き方

`figureRect` を次の形に置き換え、横組みと縦組みを区別する。

```haskell
figureRect :: PageGeometry -> Rect -> Int -> PlacedFigure -> Rect
-- 版面、画像の先頭の格子の番号、図版
```

行の格子の `slot` の行の字面の、行の送りの方向の始まりの辺を、画像の始まりの辺とする。

- 横組み：画像の上辺を、版面の上辺から `slot × 行送り` 下に置く。`wrap` がないか `start` なら左辺を版面の左辺に、`end` なら右辺を版面の右辺にそろえる。
- 縦組み：画像の右辺を、版面の右辺から `slot × 行送り` 左に置く。`wrap` がないか `start` なら上辺を版面の上辺に、`end` なら下辺を版面の下辺にそろえる。

キャプションの行は、画像の先頭の格子から `m` 個後の格子から順に、画像と同じ行の始まりの位置に置く。

### データ構造

```haskell
-- Golem.Driver.Pdf
data SetLine = SetLine
  { slLine :: !Line,
    slSize :: !Sp,
    slIndent :: !Sp, -- 行の始まりからのずらし
    slNotes :: ![(Int, [Line])]
  }

data PlacedFigure = PlacedFigure
  { pfImage :: !P.ImageData,
    pfAlong :: !Sp,
    pfAcross :: !Sp,
    pfWrap :: !(Maybe Wrap),
    pfImageLines :: !Int, -- m
    pfCaption :: ![Line]
  }

-- レイアウトの結果。writeDocument とテストが読む
data PdfLayout = PdfLayout
  { plPages :: ![PageOut],
    plLines :: !(Map Int SetLine),
    plFigures :: !(Map Int PlacedFigure)
  }

layoutPdf :: PdfInput -> PageGeometry -> LoadedFonts -> IO (Either [Diagnostic] PdfLayout)
```

`renderPdf` は、`layoutPdf` の結果を `writeDocument` に渡すだけにする。
`Built` は `PdfLayout` に置き換える。
`Unit` に単位のブロックの `SrcSpan`（`uSpan`）を加え、診断に使う。

golem-layout の `Paginate` には `FContinued [LineBox]` を加え、`nextNeed` では `FParagraph` と同じく `min 2 (length ls)` を返す。

### 決定性

すべての寸法は整数の sp で計算し、除算は `div` で切り捨てる（`m` と `exLines` は切り上げの式を整数で書く）。
仕事の結果を文書の順に並べ直すので、並列と逐次で同じ行の番号と同じ PDF になる（[docs/adr/0002](../../adr/0002-determinism.md)）。

### ドキュメント

- [仕様書](../../specifications.md) の「v1 の実装で次の段階以降に回した項目」から、回り込みの図版の項目を削る。
- [仕様書](../../specifications.md) の図版の節に、PDF では図番号とキャプションを図版の下（縦組みでは左）に組むことを書き、この ADR へのリンクを付ける。

## 実装しないこと

- 回り込ませない図版の `width`。回り込ませない図版は、これまでどおり版面の行長に合わせる。
- キャプションの書体と大きさの設定。`style.toml` に欄がないので、本文と同じにする。
- 一ページに収まらない回り込ませない図版の扱い。`paginate` の既存の動作（空のページにそのまま置く）を変えない。
- 送った回り込みの図版の前に、後の本文を詰めること。
- 段組みの版面での回り込み。パイプラインは今のところ最初の段の行長だけを使う。
- 回り込みの図版の脇で、見出しなどの段落でないブロックを組むこと。

## テスト設計

golem-driver のテスト（modules/golem-driver/test/Main.hs）に加える。
画像には golem-pdf のテストの 2 × 3 画素の JPEG（`../golem-pdf/test/fixtures/tiny.jpg`）を `images/tiny.jpg` として複製し、フォントは `fakeFonts` を使う。
横組みのスタイルは、既存の `horizontalStyle` の字数を 24 にしたもの（10pt、行送り 15pt、30 行、行長 240pt）とする。
各テストは `layoutPdf` の `PdfLayout` を調べる。

- `wrap=end width=4zw` の図版の後に長い段落を置く。`along` は 40pt、`across` は 60pt、`m` は 4 になる。`FWrapped` の `exLines` が、キャプションの行数 `n` から `⌈((4 + n − 1) × 15 + 10 + 10) ÷ 15⌉` に一致すること。
- 同じ原稿で、`FWrapped` の脇の行の `lineTarget` がすべて 190pt（240 − 50）であり、`slIndent` が 0 であること。`FContinued` の行の `lineTarget` が 240pt であること。
- `wrap=start` では、脇の行の `slIndent` が 50pt であり、`figureRect` の左辺が版面の左辺に一致すること。`wrap=end` では右辺が版面の右辺に一致すること。
- 脇の段落が除外領域の途中で終わり、次の段落が続く場合、次の段落の最初の行の `lineTarget` が、除外領域の残りに応じて 190pt になること。
- 図版の直後に見出しを置くと、見出しの行が除外領域の後の格子（図版の格子 + `exLines`）に置かれること。
- ページの残りが `exLines` より少ない位置に回り込みの図版を置くと、図版と脇の行が次のページの先頭の格子 0 から置かれ、前のページの残りの格子に何も置かれないこと。
- 縦組みのスタイル（既存の `pdfStyle`）で `wrap=start width=4zw` の図版を置くと、画像の上辺が版面の上辺に、右辺が先頭の格子の行の右端に一致し、脇の行の `slIndent` が `4zw + 1zw` になること。
- `width=3em` で G0722、`width=22zw`（残りが 1 字分）で G0722 になること。
- 行数を 10 にした横組みのスタイルで `width=10zw` の図版を置くと、`m` が 10 になり `exLines` が 10 を超えるので G0723 になり、図版の `SrcSpan` が示されること。
- 回り込ませない図版の `ffLines` が `m + n` であり、キャプションの文字のグリフが PDF の内容に現れること。
- 縦組みで回り込ませない図版の矩形が、版面の内側にあること（`figureRect` の修正の確認）。
- 脇の段落にページ番号への参照を置いた原稿で、エラーなしに収束すること。
- 回り込みの図版を含む原稿を並列と逐次でビルドし、PDF のバイト列が一致すること。二回のビルドでも一致すること。

golem-layout のテスト（modules/golem-layout/test/Main.hs）に加える。

- `FContinued` の行は、ページの末尾に一行だけ残っても次のページに送られないこと（段落の最初の行の孤立の規則を適用しないこと）。最後の一行だけが次のページに送られる場合は、一行前で改ページすること。

## トレードオフ

図版を次のページに送ったとき、前のページの残りを空白にする。
後の本文を詰めるには、脇の行を除外領域なしで組み直す必要があり、組み直した行数が変わると改ページも変わる。
改ページと行分割の往復を一つの回り込みのために持ち込むより、空白を受け入れる。
空白が目立つ場合は、書き手が図版の位置を原稿の上で動かせばよい。

除外領域にかかる段落を逐次に組むので、回り込みの図版の脇の段落は並列に組めない。
仕事は除外領域の行数に達したところで終わるので、逐次になるのは図版ごとに数段落にとどまる。

キャプションの書体と大きさを本文と同じにする。
書籍では本文より小さい文字で組むことが多いが、その設定は `style.toml` に欄を加える別の ADR で扱う。
