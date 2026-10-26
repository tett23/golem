# ADR 0014: PNG の tRNS の透過を SMask で PDF に入れる

ステータス: 採択

## 文脈

PNG の透過には二つの書き方がある。
一つは色の種類 4 と 6 の画素が持つアルファのチャンネルで、もう一つは tRNS のチャンクである。
golem-pdf は前者を SMask として PDF に入れるが、後者を読まない。
tRNS を持つ PNG を図版に置くと、PDF では透過が消え、diagnostic も出ない。

仕様書の設計原則「緩い規則より厳しい規則」は、書き手の入力と違う出力を黙って作らないと定める。
透過する前提で描かれた画素が、透過せずに紙面に出る。
これは、その原則に反する。

### 今の振る舞い

PNG を読むのは golem-pdf の `Golem.Pdf.Image.readPng` である（[Image.hs の 107 行から 163 行](https://github.com/tett23/golem/blob/f537c213c4991b1e5f4a81fba6f669808af91c6c/modules/golem-pdf/src/Golem/Pdf/Image.hs#L107-L163)）。

- チャンクの一覧から引くのは、`IHDR`、`IDAT`、`iCCP`、`PLTE` の四つだけである。`tRNS` を引く箇所はない。
- アルファを取り出すのは、色の種類が 4 か 6 のときだけである（[153 行から 162 行](https://github.com/tett23/golem/blob/f537c213c4991b1e5f4a81fba6f669808af91c6c/modules/golem-pdf/src/Golem/Pdf/Image.hs#L153-L162)）。取り出したアルファは、画像と同じビット深度の標本の列として `imgAlpha` に入る。
- 色の種類 3（パレット）は、パレットの番号をそのまま標本にし、`PLTE` を `Indexed` の色空間の表にする。

PDF を書くのは `Golem.Pdf.Writer.imageObjects` である（[Writer.hs の 648 行から 686 行](https://github.com/tett23/golem/blob/f537c213c4991b1e5f4a81fba6f669808af91c6c/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L648-L686)）。
`imgAlpha` があれば画像の辞書に `/SMask` を書き、`DeviceGray` の画像の XObject を一つ足す。
SMask の `BitsPerComponent` は、画像の `imgBits` をそのまま使う。
画像のオブジェクトの数（[400 行](https://github.com/tett23/golem/blob/f537c213c4991b1e5f4a81fba6f669808af91c6c/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L400-L401)）も、`imgAlpha` があるかで一つ増える。
`/Mask` は書かない。

HTML と EPUB は、図版の PNG を中身を見ずに写す。
HTML は golem-driver がファイルを読んでそのまま書き（[Driver.hs の 909 行](https://github.com/tett23/golem/blob/f537c213c4991b1e5f4a81fba6f669808af91c6c/modules/golem-driver/src/Golem/Driver.hs#L909)、[970 行](https://github.com/tett23/golem/blob/f537c213c4991b1e5f4a81fba6f669808af91c6c/modules/golem-driver/src/Golem/Driver.hs#L970)）、EPUB は golem-epub が読んだバイト列を書庫に入れる（[Epub.hs の 142 行](https://github.com/tett23/golem/blob/f537c213c4991b1e5f4a81fba6f669808af91c6c/modules/golem-epub/src/Golem/Epub.hs#L142)）。
tRNS は HTML と EPUB に残り、読む側が解釈する。
同じ図版が、PDF と HTML で違って見えうる。

### 確かめた振る舞い

シェルの `printf` と `cksum -o 3`（CRC-32）で、tRNS を持つ 4 枚の PNG を作った。
zlib は無圧縮のブロックで書いた。
macOS 27.0 の ImageIO（CoreGraphics）で RGBA に描くと、4 枚とも tRNS のとおりに透過した。

| PNG | tRNS | ImageIO で描いた画素 |
| --- | --- | --- |
| パレット、8 ビット、2×1、赤と青 | `00`（番号 0 のアルファが 0） | 1 画素めが透明、2 画素めが不透明の青 |
| グレー、8 ビット、2×1、`00` と `80` | `0080` | 1 画素めが不透明、2 画素めが透明 |
| RGB、8 ビット、2×1、赤と緑 | 緑 | 1 画素めが不透明の赤、2 画素めが透明 |
| RGB、16 ビット、2×1、`(0, 0x00FF, 0)` と `(0, 0, 0)` | `(0, 0x00FF, 0)` | 1 画素めが透明、2 画素めが不透明 |

16 ビットの 2 画素は、上位の 8 ビットに縮めるとどちらも `(0, 0, 0)` になる。
2 画素めが不透明に残ったので、ImageIO は 16 ビットのまま比べている。

同じ 4 枚を origin/main の `f537c213` の golem-pdf で `readImage` に渡すと、4 枚とも `imgAlpha` が `Nothing` になった。
`Left` にはならず、PDF には透過のない画像が入る。

仕様に反する tRNS も ImageIO で描いてみた。

- 色の種類 6 の PNG に tRNS を足すと、tRNS を無視し、画素のアルファで描いた。
- パレットが 2 色の PNG に 3 バイトの tRNS を付けると、tRNS 全体を無視し、2 画素とも不透明で描いた。番号 0 のアルファの 0 も働かなかった。
- 8 ビットのグレーに上位のバイトが 0 でない tRNS（`FF80`）を付けると、下位の 8 ビットの `80` と比べて透過した。

ブラウザーの振る舞いは確かめていない。

### PNG の仕様が定める tRNS

PNG の仕様（第 3 版、W3C 勧告 2025-06-24）の 11.3.1.1 節は、tRNS を色の種類ごとに次のとおり定める。

- **色の種類 3**：パレットの番号ごとの 1 バイトのアルファの列である。0 が完全な透明、255 が完全な不透明で、画像のビット深度によらない。パレットの数より多く書いてはならず、少なければ残りの番号のアルファは 255 とみなす。
- **色の種類 0 と 2**：一つの色を 2 バイトの標本で書く（グレーは 1 標本、RGB は 3 標本）。その色の画素は透明（アルファ 0）、ほかの画素は完全な不透明である。ビット深度が 16 より小さければ下位のビットを使い、デコーダーはほかのビットを 0 にしてから使わなければならない。
- **色の種類 4 と 6**：tRNS を置いてはならない。
- **16 ビット**：16 ビットの値全体が一致する画素だけが透明である。デコーダーは、透過を判定してからビット深度を変換する。

5.6 節の表は、tRNS を「PLTE の後、IDAT の前」に置き、一つのファイルに二つ以上置けないと定める。

### PDF の二つの仕組み

ISO 32000-1:2008 は、画像の一部を描かない仕組みを二つ持つ。

- **色のキーのマスク**（8.9.6.4 節）：画像の辞書の `/Mask` に、色の成分ごとの最小と最大の整数の組 `[min1 max1 … minn maxn]` を書く。整数は 0 から 2^BitsPerComponent - 1 の範囲で、`Decode` を当てる前の標本の値を表す。すべての成分が範囲に入る標本は描かない。
- **SMask**（表 89 の `SMask`、11.6.5.3 節）：画像の辞書の `/SMask` に、`DeviceGray` の画像の XObject を指す。透明のモデルの形または不透明度の源になり、あれば `/Mask` に勝つ。SMask の `BitsPerComponent` は必須で、表 145 は親の画像と同じ値にすることを求めていない。

PNG の tRNS を PDF に移すと、色の種類ごとに次の違いが出る。

- **パレット**：アルファが 0 と 255 のあいだの値を取れるので、SMask でなければ表せない。0 と 255 だけでも、透明にする番号が飛び飛びなら、`Indexed` の色空間の成分は一つなので、一組の範囲では表せない。
- **グレーと RGB**：透明の色は一つなので、`min = max` の色のキーで表せる。Golem は PNG の標本を変えずに Flate で書くので、比べる値は PNG の標本と一致し、16 ビットでも全桁で比べる。SMask でも、Golem が全桁で比べた結果を 0 と 255 で書けば同じ結果になる。

PDF/X-4 は透明を許す（[ADR 0002](0002-pdf-x-4.md)、[ADR 0008](0008-pdf-figures.md)）。
色の種類 4 と 6 の PNG は、すでに SMask で PDF に入っている。

### 選択肢

- **(a) tRNS を読んで透過を入れる**：パレットは SMask にする。グレーと RGB は、色のキーのマスクか SMask のどちらかにする。
- **(b) tRNS を持つ PNG を拒む**：G08010 の理由を一つ足すか、新しいコード（5 桁の割り当ての規則（[docs/adr/0061](../../adr/0061-five-digit-diagnostic-codes.md)）では G08102 が空いている）でエラーか警告にする。

(b) のエラーは、PNG の仕様が定める標準の透過の書き方を持つ画像を、PDF でだけ置けなくする。
書き手は、同じ画像をアルファのチャンネルを持つ PNG に書き出し直すことになる。
HTML と EPUB ではそのまま使えるので、PDF だけの制約が増える。
(b) の警告は、透過を落とした出力を知らせたうえで作るので、設計原則には反しない。
それでも、PDF と HTML の見た目の違いは残る。

(a) は、仕様が定める意味のとおりに読めば、推測を一つも足さずに書き手の意図した画像を PDF に入れられる。
仕様に反する tRNS（長すぎる、色の種類 4 と 6 にある、二つある）だけを拒めば、厳しい規則とも両立する。
この ADR は (a) を採り、グレーと RGB にも SMask を使う。
色のキーにしない理由は「トレードオフ」に書く。

## 実装すること

### tRNS の読み込み（golem-pdf の `Golem.Pdf.Image`）

`readPng` が `tRNS` を読み、アルファの面を作って `imgAlpha` に入れる。
アルファの面は、画素ごとに 1 バイト（8 ビット）とする。

- **色の種類 3**：画素のパレットの番号を取り出し、tRNS のその番号のバイトをアルファにする。tRNS が短く、番号に当たるバイトがなければ 255 とする。ビット深度が 1、2、4 のときは、行ごとにビットを上位から読み、行の末尾の埋め草のビットは読まない。
- **色の種類 0**：tRNS の 2 バイトを 16 ビットの整数として読み、ビット深度が 16 より小さければ下位のビット深度ぶんだけを残す。画素の標本が一致すれば 0、しなければ 255 とする。ビット深度が 1、2、4 のときは、パレットと同じく行ごとにビットを読む。
- **色の種類 2**：tRNS の 6 バイトを三つの 16 ビットの整数として読み、色の種類 0 と同じく下位のビットを残す。三つの標本がすべて一致する画素を 0、ほかを 255 とする。
- **16 ビット**：標本を 16 ビットの整数のまま比べる。8 ビットに縮めてから比べない。

tRNS があれば、透明の画素が一つもなくても SMask を書く。
SMask を書くかどうかは、tRNS のチャンクがあるかだけで決まる。

### 拒む tRNS（G08010）

PNG の仕様に反する tRNS は、図版を置かずに G08010 のエラーにする。
理由の文言は次の四つとする。

| 場合 | 理由 |
| --- | --- |
| 色の種類 4 か 6 に tRNS がある | `アルファのある PNG に tRNS があります` |
| 色の種類 3 の tRNS が、PLTE の色の数より長い | `PNG の tRNS がパレットより長いです` |
| 色の種類 0 の tRNS が 2 バイトでない、色の種類 2 の tRNS が 6 バイトでない | `PNG の tRNS の長さが色の種類に合いません` |
| tRNS が二つ以上ある | `PNG に tRNS が二つ以上あります` |

ImageIO は、はじめの二つを黙って無視した（「確かめた振る舞い」）。
読む側によって結果が変わる入力なので、どれか一つの読み方を推測で選ばず、誤りとして止める。

ビット深度が 16 より小さい画像の tRNS で、上位のビットが 0 でない値は拒まない。
仕様がデコーダーに下位のビットだけを使うよう求めており、読み方が一つに決まるためである。

### アルファの面の大きさの上限

アルファの面は画素ごとに 1 バイトなので、ビット深度が 1 の画像では画素のデータの 8 倍になる。
[docs/adr/0035](../../adr/0035-security-hardening.md) の上限（フィルタの前の画素のデータが 512 MiB まで）だけでは、アルファの面が 4 GiB に届きうる。
tRNS を持つ PNG は、`幅 × 高さ` が 2^29 を超えれば、G08010 の新しい理由 `tRNS を持つ PNG の画素が多すぎます` にする。
今の `PNG の画像が大きすぎます`（フィルタの前の画素のデータの上限）とは原因が違うので、文言を分け、書き手がどちらの上限を超えたかを見分けられるようにする。
判定は IDAT を展開する前に、`Integer` で行う。

### SMask の書き出し（golem-pdf の `Golem.Pdf.Writer`）

`imageObjects` は、SMask の `BitsPerComponent` を、画像の `imgBits` ではなくアルファの面のビット深度から書く。
色の種類 4 と 6 のアルファの面は、今と同じく画像のビット深度（8 か 16）のままとし、今の出力のバイト列を変えない。
`/Mask` は今と同じく書かない。

### データ構造

`ImageData` の `imgAlpha` の型を、標本の列だけから、ビット深度と標本の組に変える。

```haskell
-- | A soft mask: DeviceGray samples, one per pixel.
data Alpha = Alpha
  { alphaBits :: !Int,
    alphaSamples :: !ByteString
  }
  deriving stock (Eq, Show)

data ImageData = ImageData
  { ...
    -- | the soft mask of PNG: the alpha channel (colour types 4 and 6) or tRNS
    imgAlpha :: !(Maybe Alpha)
  }
```

画像のオブジェクトの数の数え方（`imgAlpha` があれば一つ増やす）は変えない。

### 仕様書、diagnostics、マニュアル

- 仕様書（`docs/specifications.md`）の「図版」の節に、PNG の透過（アルファのチャンネルと tRNS）を SMask で PDF に入れることと、仕様に反する tRNS を G08010 にすることを書く。
- golem-pdf の仕様書（`docs/golem-pdf/specifications.md`）に「PNG の画像」の節を設け、色の種類ごとのアルファの面の作り方、下位のビットの扱い、16 ビットの比べ方、アルファの面の上限を書く。
- `docs/diagnostics.md` の G08010 に、上の四つの理由と、アルファの面の上限による `tRNS を持つ PNG の画素が多すぎます` を足し、ADR の欄にこの ADR を足す。「主な原因」と「直し方」に、tRNS が壊れた PNG を書き出し直すことを足す。
- 利用者のマニュアルの記法の章（`manual/chapters/03-markup.gm`）の画像の形式の段落に、PNG の透過は PDF でも保たれることを足す。エラーの付録（`manual/appendices/e-errors.gm`）の G08010 に、tRNS が仕様に反する PNG の場合を足す。
- ロードマップの rc4 の「PDF」の節から、この項目を消す。

## 実装しないこと

- **色のキーのマスク**：`/Mask` の配列は書かない。理由は「トレードオフ」に書く。
- **tRNS の置き場所の検査**：tRNS が PLTE の前や IDAT の後にあっても拒まない。今の `readPng` は、ほかのチャンクの順も調べていない。順を調べるなら、すべてのチャンクを同じ ADR で扱う。
- **透明の画素がない tRNS の省略**：tRNS があれば、全画素が不透明でも SMask を書く。
- **bKGD**：背景の色のチャンクは読まない。PDF では紙面が背景になる。
- **SMask のビット深度を縮めること**：グレーと RGB のアルファは 0 と 255 しか取らないが、1 ビットの SMask にはしない。
- **HTML と EPUB の変更**：今と同じく PNG をそのまま写す。仕様に反する tRNS も、HTML と EPUB では diagnostic を出さない。G08010 が PDF を組むときにだけ出るという今の区別に従う。
- **JPEG と取り込んだ PDF の中の画像**：どちらも変えない。

## テスト設計

テストを先に書き、今のコードで失敗することを確かめてから実装する。

### golem-pdf の単体のテスト（`test/ImageSpec.hs`）

PNG は、今のテストと同じく、テストの中の `png`、`ihdr`、`chunk`、`idat` で作る。

次のテストは、今のコードで失敗する（`imgAlpha` が `Nothing` になるか、`Left` にならない）。

- パレット、8 ビット、3×1、3 色、tRNS `[0, 128]` の画像で、アルファの面が `Alpha 8 [0, 128, 255]` になる（3 色めは tRNS が短いので 255）。
- パレット、2 ビット、3×1（行の末尾に 2 ビットの埋め草）で、番号ごとのアルファが画素の順に並び、埋め草を読まない。
- グレー、8 ビット、2×1、`[0x00, 0x80]`、tRNS `0x0080` で、`Alpha 8 [255, 0]` になる。
- グレー、2 ビット、4×1、標本 `0, 1, 2, 3`、tRNS `0xFF02` で、上位のビットを捨てて `Alpha 8 [255, 255, 0, 255]` になる。
- RGB、8 ビット、2×1、赤と緑、tRNS が緑で、`Alpha 8 [255, 0]` になる。
- RGB、16 ビット、2×1、`(0, 0x00FF, 0)` と `(0, 0, 0)`、tRNS `(0, 0x00FF, 0)` で、`Alpha 8 [0, 255]` になる。8 ビットに縮めて比べると 2 画素とも 0 になるので、この差を見る。
- グレー、16 ビット、2×1、`0x0001` と `0x0000`、tRNS `0x0001` で、`Alpha 8 [0, 255]` になる。
- 透明の画素のない tRNS（RGB の画像に、どの画素とも違う色）でも、`Alpha 8 [255, …]` になる。
- 色の種類 4 と 6 に tRNS を足すと、`アルファのある PNG に tRNS があります` の `Left` になる。
- 2 色の PLTE に 3 バイトの tRNS で、`PNG の tRNS がパレットより長いです` の `Left` になる。
- 色の種類 0 で 1 バイトと 3 バイト、色の種類 2 で 2 バイトの tRNS で、`PNG の tRNS の長さが色の種類に合いません` の `Left` になる。
- tRNS が二つある画像で、`PNG に tRNS が二つ以上あります` の `Left` になる。
- tRNS を持ち、幅 × 高さが 2^29 を超える 1 ビットのグレーの画像（IHDR だけを大きくし、IDAT は小さいもの）が、IDAT を展開せずに `tRNS を持つ PNG の画素が多すぎます` になる。フィルタの前の画素のデータは 512 MiB 以下に収まる大きさを選び、tRNS を外すと別の理由（画素のデータが足りない）になることも確かめる。

次のテストは、今も通り、変更の後も通る。

- 色の種類 6、16 ビットの画像のアルファの面が `Alpha 16 …` で、標本が今と同じである。
- tRNS のない PNG の `imgAlpha` が `Nothing` である。

### golem-pdf の PDF のテスト

- パレット、2 ビット、tRNS を持つ画像の PDF で、画像の辞書が `/BitsPerComponent 2` と `/SMask` を持ち、SMask の辞書が `/BitsPerComponent 8` と `/ColorSpace /DeviceGray` を持ち、SMask のストリームを展開するとアルファの面と一致する。今は `/SMask` がないので失敗する。
- tRNS を持つ RGB の画像の PDF に `/Mask` がない。

### golem-driver のテスト

- tRNS を持つパレットの PNG を図版に置いた本の PDF のビルドが、diagnostic を出さずに終わり、画像の辞書が `/SMask` を持つ。今は `/SMask` がないので失敗する。
- 色の種類 6 に tRNS を足した PNG を図版に置くと、その `@figure` に `図版を PDF に置けません: <パス>（アルファのある PNG に tRNS があります）` の G08010 が出て、PDF を書かない。今は diagnostic が出ないので失敗する。
- 同じ本の HTML のビルドは、G08010 を出さず、PNG のバイト列をそのまま写す。

### 出力のゴールデン

figures の fixture（`modules/golem-driver/test/fixtures/figures/`）に、tRNS を持つ PNG を 4 枚足し、`@figure` で置く。

| ファイル | PNG | tRNS | 見え方 |
| --- | --- | --- | --- |
| `trns-palette.png` | 4×2、パレット、2 ビット、赤、緑、青、黄の 4 色、2 行めは Sub のフィルタ | `[0x00, 0x80]` | 赤が透明、緑が半透明、青と黄が不透明 |
| `trns-gray.png` | 4×1、グレー、2 ビット、標本 `0, 1, 2, 3` | `0x0002` | 3 画素めが透明 |
| `trns-rgb.png` | 2×2、RGB、8 ビット、赤、緑、青、黄 | 緑 | 緑が透明 |
| `trns-rgb16.png` | 2×1、RGB、16 ビット、`(0, 0x00FF, 0)` と `(0, 0, 0)` | `(0, 0x00FF, 0)` | 1 画素めが透明、2 画素めが黒 |

- ファイルは、シェルの `printf` で 1 バイトずつ書き、CRC を `cksum -o 3` で計算する。zlib は無圧縮のブロックで書く。作るスクリプトはコミットしない（PR #423 の fixture と同じ）。
- 透明にする画素の色は白以外にする。透過が落ちると、その色が紙面に出るので、見た目で分かる。
- 作った PNG を macOS の ImageIO（`sips`）か別のデコーダーで読み、画素とアルファが表の「見え方」のとおりであることを確かめ、実装のプルリクエストに書く。
- `pdf-figures.txt` と `epub-figures.txt` を更新する。`pdf-figures.txt` では、4 枚の画像の辞書が `/SMask` を持ち、SMask のストリームの SHA-256 が並ぶことを差分で確かめる。`epub-figures.txt` では、4 枚のファイルの SHA-256 が元の PNG と同じであることを確かめる。
- 既存の 4 枚の PNG（`gray.png`、`rgba.png`、`palette.png`、`gray-icc.png`）の画像と SMask のストリームの行が、変わらないことを差分で確かめる。

### 見た目の確かめ

ロードマップの rc4 の見た目の回帰テスト（shem）は、画像の中身を描かずに灰色の箱で描くので、この変更を確かめられない。
次の手作業で確かめ、結果を実装のプルリクエストに書く。

- figures の fixture の PDF を、CoreGraphics（macOS のプレビュー）と Poppler の `pdftoppm`（使える環境で）で画像にし、4 枚の tRNS の PNG の透明の画素で紙面の白が見えること、半透明の緑が紙面と混ざることを確かめる。
- 同じ fixture の HTML を Safari と Chrome で開き、PDF と同じ画素が透明になることを確かめる。
- 確かめられなかった環境は、ロードマップの「手で確かめる項目」に足す。

## トレードオフ

### グレーと RGB を色のキーにしない理由

色のキーのマスクは、`Decode` の前の標本の値で比べるので、16 ビットでも全桁で一致する画素だけを描かない。
Golem は PNG の標本を変えずに書くので、精度は SMask と変わらない。
ストリームが一つ減り、透明のモデルを使わずに済む。

それでも SMask に揃える。
パレットのアルファは SMask でしか表せないので、色のキーを足すと、PNG の透過を PDF に移す道が二つになる。
SMask だけなら、`readPng` が tRNS をアルファの面に直した後は、色の種類 4 と 6 と同じ道を通り、`imageObjects` は tRNS を知らずに済む。
読み込みの側に tRNS の意味を閉じ込められるので、色の種類ごとの分岐が書き出しの側に漏れない。

代わりに、グレーと RGB の tRNS を持つ画像は、画素ごとに 1 バイトの SMask の分だけ PDF が大きくなる。
透明の色を持つ PNG は、透明の画素が一様に並ぶことが多いので、Flate で圧縮すれば小さく収まることが多いと見込むが、測ってはいない。
PDF に透明が入るので、透明を平坦化する RIP では処理が増える。
PDF/X-4 は透明を許し、色の種類 4 と 6 の PNG はすでに SMask で入っているので、新しい種類の要素は増えない。

### アルファの面を 8 ビットにする理由

グレーと RGB のアルファは 0 と 255 しか取らないので、1 ビットの SMask で足りる。
8 ビットにそろえれば、パレットとグレーと RGB で、アルファの面の作り方とビット深度が一つになる。
1 ビットにすると、行の末尾の埋め草を含めてビットを詰める処理が要り、色の種類で SMask のビット深度が分かれる。
大きさの差は Flate が縮める。

### tRNS があれば SMask を書くこと

透明の画素がないときに SMask を省けば、PDF は小さくなる。
ただ、出力の形が tRNS の有無ではなく画素の値で変わり、画素を一つ変えると SMask が現れたり消えたりする。
チャンクの有無だけで決まるほうが、出力を予測しやすい。

### 仕様に反する tRNS を拒むこと

拒むと、ImageIO が描ける PNG を Golem が拒む場合が出る（長すぎる tRNS、色の種類 6 の tRNS）。
ImageIO は長すぎる tRNS を丸ごと無視したが、ほかのデコーダーが同じ読み方をするかは確かめていない。
読む側によって透過する画素が変わりうる入力を、Golem が一つの読み方で組むと、PDF と HTML の見た目の違いを黙って作ることになる。
誤りとして止め、書き出し直してもらうほうを採る。

### 決定性

アルファの面は、標本と tRNS の整数の比べで決まり、浮動小数点数を使わない。
SMask のストリームは、ほかのストリームと同じ `flate`（レベル 9）で圧縮する。
同じ PNG からは、同じ SMask のバイト列と同じ diagnostic が得られる。

## 参考文献

- W3C, "Portable Network Graphics (PNG) Specification (Third Edition)", W3C Recommendation, 24 June 2025. 5.6 節「Chunk ordering」、6.2 節「Alpha representation」、11.3.1.1 節「tRNS Transparency」。<https://www.w3.org/TR/png-3/>
- ISO 32000-1:2008, "Document management, Portable document format, Part 1: PDF 1.7"（Adobe による公開版 PDF32000_2008.pdf）。8.9.5 節の表 89（`Mask`、`SMask`）、8.9.6.4 節「Colour Key Masking」、11.6.5.3 節「Soft-Mask Images」と表 145。<https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf>
- golem-pdf の `Golem.Pdf.Image`（[f537c213 の Image.hs](https://github.com/tett23/golem/blob/f537c213c4991b1e5f4a81fba6f669808af91c6c/modules/golem-pdf/src/Golem/Pdf/Image.hs)）と `Golem.Pdf.Writer`（[f537c213 の Writer.hs](https://github.com/tett23/golem/blob/f537c213c4991b1e5f4a81fba6f669808af91c6c/modules/golem-pdf/src/Golem/Pdf/Writer.hs)）。
- PR #423「test: fix PNG figures in the output goldens」。<https://github.com/tett23/golem/pull/423>
