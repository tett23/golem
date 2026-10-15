# ADR 0019: PDF の圏点の形と位置

ステータス: 採択

## 文脈

圏点は `[kenten: 語]` と `[kenten shape=circle: 語]` で書き、形を省くと `style.toml` の `[composition]` の `kenten` に従う（[docs/markup.md](../../markup.md) の「圏点」）。
形は、golem-eval の `Golem.Eval.File` の `kentenShapes` にある `sesame`、`open-sesame`、`dot`、`open-dot`、`circle`、`open-circle` の六つであり、ほかの値は G0239 になる。
意味論 IR の `Kenten !SrcSpan !(Maybe Text) [Inline]` は、書いた形をそのまま持ち、省いた場合は `Nothing` である。

PDF の圏点には、仕様書の「v1 の実装で次の段階以降に回した項目」に挙げた不具合がある。
形を使わず常に `﹅` で描き、横組みでは圏点が右にずれ、字の上端に重なる。
コードを読むと、ほかにも次のことが分かる。

### 形が届いていない

golem-layout の `Golem.Layout.Japanese` の `piecesOf` は、`Kenten _ _ xs` の形を捨て、中の文字に真偽値の印（`PChar` の四つ目の値）だけを付ける。
`itemsFor` は、印の付いた字の箱を `KindKenten` にする。
golem-driver の `Golem.Driver.Pdf` の `drawLineAt` は、`KindKenten` の箱に、字と、半分の大きさの `﹅` を描く。

`style.toml` の既定の形も、どこでも使われていない。
`Golem.Project.Style` の `compKenten` は読み込んだ文字列をそのまま持ち、値を検査しない。
golem-driver は `compKenten` を評価の文脈の `ctxDefaultKenten` に渡すが、`Golem.Eval.File` はこの値を読まない。
HTML（`Golem.Html`）は、形を省いた圏点に `kenten-default` の class を付け、CSS の `.kenten` で常にゴマにする。
`kenten = "circle"` と書いても、PDF と HTML のどちらにも効かない。

### 位置がずれる

`drawLineAt` は、圏点のグリフの原点を、親文字の原点から行の方向に `(s − d) / 2`（`s` は親文字の大きさ、`d = s/2` は圏点の大きさ）だけ進め、行に直交する方向に、横組みでは `s`、縦組みでは `s/2 + d/2` だけずらした点に置く。
グリフの原点を置くだけで、グリフの字面がどこにあるかを見ていない。
`﹅`（U+FE45）は縦組みの互換の字形であり、多くの和文の書体で字面が全角の枠の右上に寄っている。
横組みでは、その寄りがそのまま右へのずれになる。
基準線から `s` 上げた位置は、親文字の字面の枠の上端（基準線から全角の 0.88 前後）より上だが、半分の大きさの圏点の字面の枠の下端がそこに来るので、字面が枠の下に寄った書体では親文字の上端に重なる。

### 約物に付く

`textPieces` は、圏点の中のすべての字に印を付ける。
`itemsFor` は、印の付いた字の箱を約物の判定より先に `KindKenten` にするので、句読点や括弧にも圏点が付く。
そのうえ、`drawLineAt` は約物の字面の前の空き（`punctSpace`）を `KindPunctuation` の箱にだけ足すので、圏点の中の始め括弧は、字面が半角ずれて描かれる。

欧文の語（`PWord`）には印が付かないので、圏点の中の欧文には圏点が付かない。
HTML の CSS の `text-emphasis` は欧文にも圏点を付ける。

### 形の種類

CSS Text Decoration Module Level 3 の `text-emphasis-style` は、塗りと白抜きの二種と、`dot`（•、◦）、`circle`（●、○）、`double-circle`（◉、◎）、`triangle`（▲、△）、`sesame`（﹅、﹆）の五つの形を持つ。
同じ仕様は、区切りの文字（Unicode の一般カテゴリ Z）、制御文字（Cc、Cf）、約物（P）には圏点を描かないと定めている。

JLReq は、圏点としてゴマと黒丸を主に挙げ、ほかの形にも触れている。
細かい記述は、この ADR を書く時点で本文を確かめていない。
InDesign の圏点は、ゴマ、白ゴマ、黒丸、白丸、黒三角、白三角、二重丸、蛇の目などの種類と、大きさ、位置（字との距離）、揃え、文字に対する位置（上か下か）の設定を持つと記憶しているが、資料では確かめていない。

## 実装すること

### 形の一覧（golem-eval、golem-project、golem-layout）

形を CSS の `text-emphasis-style` の十の組に合わせ、四つを加える。

| 形 | 字 | 名前 |
|---|---|---|
| `sesame` | ﹅（U+FE45） | ゴマ |
| `open-sesame` | ﹆（U+FE46） | 白ゴマ |
| `dot` | •（U+2022） | 小さい黒丸 |
| `open-dot` | ◦（U+25E6） | 小さい白丸 |
| `circle` | ●（U+25CF） | 黒丸 |
| `open-circle` | ○（U+25CB） | 白丸 |
| `double-circle` | ◉（U+25C9） | 蛇の目（加える） |
| `open-double-circle` | ◎（U+25CE） | 二重丸（加える） |
| `triangle` | ▲（U+25B2） | 黒三角（加える） |
| `open-triangle` | △（U+25B3） | 白三角（加える） |

- `kentenShapes` に四つを加える。一覧にない値は今と同じく G0239 とする。
- `[composition]` の `kenten` を、同じ一覧の `enumKey` で読む。一覧にない値は、ほかの `enumKey` の欄と同じく `style.toml` の値の誤り（G0306）とする。既定は今と同じ `"sesame"` とする。
- `Golem.Eval.File` は、形を省いた `[kenten]` の形を `ctxDefaultKenten` で埋め、IR の `Kenten` は常に `Just` の形を持つ。型は `Maybe Text` のまま変えない。プラグインが `Nothing` の圏点を返した場合は、各出力で `sesame` とみなす。
- golem-layout の `Golem.Layout.Look` に、形の型を置く。

```haskell
data KentenShape
  = KentenSesame | KentenOpenSesame | KentenDot | KentenOpenDot
  | KentenCircle | KentenOpenCircle | KentenDoubleCircle | KentenOpenDoubleCircle
  | KentenTriangle | KentenOpenTriangle
  deriving stock (Eq, Ord, Show, Enum, Bounded)

kentenChar :: KentenShape -> Char
```

### 形を文字の属性にする（golem-layout）

圏点を、ほかの文字の属性と同じく `Look` に載せる。

```haskell
data Look = Look
  { ...
    -- | 圏点の形（docs/golem-driver ADR 0019）。Nothing は圏点なし
    lkKenten :: !(Maybe KentenShape)
  }
```

- `plainLook` の既定は `Nothing` とする。
- `piecesOf` の `Kenten _ sh xs` は、中の字の `Look` の `lkKenten` を `sh` の形にして組む。入れ子の圏点は、内側の形が勝つ。
- `PChar` の四つ目の値（圏点の真偽値）は不要になるので除く。
- `itemsFor` は、`lkKenten` が `Just` で、字が約物でも区切りでもない場合にだけ箱を `KindKenten` にする。約物と区切りは、Unicode の一般カテゴリが P（約物）か Z（区切り）か Cc か Cf の字とする（GHC の `Data.Char.generalCategory` で判定する）。そうした字は圏点の中でも今までどおり `KindPunctuation` か `KindText` になり、圏点を描かない。長音記号（ー）と踊り字（々）は P でも Z でもないので、圏点が付く。
- 字の箱の `Look` が圏点の有無で変わるので、圏点の内と外の境のペアカーニング（[docs/adr/0020](../../adr/0020-indesign-character-features.md)）はかからなくなる。

### 描画（golem-driver）

`drawLineAt` の `KindKenten` の分岐を、次のように改める。

- 圏点の字は、`kentenChar` で形から決め、親文字の `Look` の和文の役割の書体で、行の方向（縦組みでは `vert` を有効にした縦書きの方向）にシェイピングする。
- 圏点の大きさ `d` は、親文字の大きさ `s` の半分（整数の除算）とする。
- 圏点の字面の中心を、次の点に置く。字面の中心は、シェイピングしたグリフの字面の矩形（FreeType の `gmBBox`）の中心を大きさ `d` で換算した点とし、グリフの原点をそこから逆算して置く。
  - **横組み**：行の方向には、親文字の送りの中央。行に直交する方向には、親文字の字面の枠の上端から `d/2` 上。親文字の字面の枠の上端は、基準線から `(c + 1/2) × s` 上である（`c` は `lfEmBoxCentral`、全角を 1 とする値）。
  - **縦組み**：行の方向には、親文字の送りの中央（箱の始まりから `s/2` 下）。行に直交する方向には、行の中心線から `s/2 + d/2` 右。
- 圏点の分の字面の外側の空きは、JLReq のルビと同じく、親文字の字面の枠に半分の大きさの枠を接して並べる形とする。字面の枠と圏点の枠の間に空きを入れない。
- 親文字のベースラインシフトは、今と同じく圏点にもかける。
- 圏点の色は、親文字の `Look` の色とする。

`LoadedFonts` に、グリフの字面の矩形を返す関数を加える。

```haskell
lfInkBox :: Int -> Int -> Maybe (Rational, Rational, Rational, Rational)
-- 書体の番号、グリフの番号 → 字面の矩形（xMin, yMin, xMax, yMax、全角を 1 とする値）
```

`Golem.Driver.Fonts` の `provide` は、golem-font の `glyphMetrics` の `gmBBox` を `fontUnitsPerEm` で割って返す。

### 圏点の字のない書体（G0809）

親文字の和文の書体が圏点の字を持たない（シェイピングの結果のグリフの番号が 0 である）と、`.notdef` の箱が描かれる。
これを黙って描かないために、PDF を書く前にエラーで止める。

| 診断 | 重大度 | メッセージ |
|---|---|---|
| G0809 | エラー | `役割 <役割> の和文の書体に圏点の形 <形> の字（U+<符号位置>）がありません` |

- レイアウトの後、すべての `KindKenten` の箱から、役割と形の組を集める。組ごとに一つだけ報告する。
- 位置は、`KindKenten` の箱が原稿の位置を持たないので、G0807 と同じく `style.toml` の先頭とし、なければ `manifest.toml` の先頭とする。
- 段階は出力（G08xx）とし、docs/diagnostics.md に節を足す。直し方には、`shape` を書体にある形に替えるか、圏点の字を持つ書体を役割に指定することを書く。

### ルビと重なる圏点（G0745）

ルビの親文字の中の圏点と、圏点の中のルビは、PDF では圏点を描かない。
圏点とルビが同じ側に重なるためである。
`rubyPieces` は今も親文字の中の圏点を捨て、圏点の中のルビにも圏点を付けないので、描かないことは今と同じである。
黙って落とさないように、お知らせ（[golem-syntax ADR 0002](../../golem-syntax/adr/0002-notice-severity.md)）で知らせる。

| 診断 | 重大度 | メッセージ |
|---|---|---|
| G0745 | お知らせ | `ルビの親文字の圏点は PDF では描きません` |

- `Golem.Driver.Pdf` に `kentenRubyNotices :: Book -> [Diagnostic]` を加え、`sidenoteDiagnostics` と同じく PDF を組むときにだけ呼ぶ。
- 位置は、ルビの親文字の中の `Kenten` ではその `Kenten` の位置、`Kenten` の中の `Ruby` ではその `Ruby` の位置とする。
- `noticeCodes` に G0745 を加える。HTML と EPUB は圏点とルビの両方を出すので、このお知らせは PDF の段階のものである。

### HTML と EPUB（golem-html）

- 圏点の class を、IR の形から `kenten kenten-<形>` とする。`Nothing` は `kenten-sesame` とする。
- CSS に `.kenten-sesame`（`.kenten` と同じゴマ）と、加えた四つの形の規則を足す。`double-circle` は `text-emphasis-style: double-circle`、`open-double-circle` は `open double-circle`、`triangle` は `triangle`、`open-triangle` は `open triangle` とする。
- `kenten-default` の class は書かなくなる。

### ドキュメント

- docs/markup.md の「圏点」の節に、十の形の一覧と、約物と区切りには圏点を付けないことを書く。
- 仕様書の「style.toml」の節の `[composition]` の `kenten` の説明に、取れる値を書く。
- 仕様書の「v1 の実装で次の段階以降に回した項目」から「PDF の圏点」の項目を消す。
- 利用者のマニュアル（`manual/`）の次の箇所を直す（[docs/adr/0024](../../adr/0024-manual-audiences-and-policy.md)）。
  - `manual/appendices/a-markup.gm` の「段落の中のコマンド」の `[kenten: ...]` の項：「今の版では、形の指定は HTML と EPUB でだけ効き、PDF では常にゴマで組みます。」を消し、形の一覧を十にする。
  - `manual/appendices/c-style.gm` の「`[composition]`」の表の `kenten` の行：「今の版では HTML と EPUB でだけ効きます。」を消す。
  - `manual/chapters/03-markup.gm` の「強調と圏点」の節：圏点の見本の段落で、形を一つ変えて見せる。
- docs/diagnostics.md に G0745 と G0809 の節を足す。
- 用語集の「圏点」に、形の一覧が docs/markup.md にあることと、約物と区切りには付けないことを書き足す。

## 実装しないこと

- 欧文の語への圏点。CSS は欧文にも圏点を付けるので、HTML と PDF で見た目が異なる。欧文の語は分けずに一つの箱で組むので、字ごとに圏点を置くには語の中の字の位置が要る。
- 圏点の大きさ、親文字との距離、揃え（中央か先頭か）、置く側（上か下か）の設定。CSS の `text-emphasis-position` に当たる設定も持たない。
- 任意の字を圏点に使うこと（CSS の文字列の `text-emphasis-style`、InDesign のカスタム）。
- 圏点とルビを同じ親文字に置くこと（G0745 で知らせる）。仕様書が v2 以降に回した「ルビの中の圏点」も扱わない。
- 圏点の分の行間の調整。圏点は行の間の空きに置き、行送りを変えない。今と同じである。
- 圏点の字を図形（パス）で描くこと。golem-pdf の描画は矩形の罫しか持たず、書体の字形を使うほうが書体の調子に合う。

## テスト設計

実装の前に書き、失敗することを確かめる。

### 評価と設定（`modules/golem-eval/test`、`modules/golem-project/test/Main.hs`）

- `[kenten: 語]` の IR が、`ctxDefaultKenten = "circle"` の文脈で `Kenten _ (Just "circle") _` になる。
- `shape=double-circle`、`open-double-circle`、`triangle`、`open-triangle` が受け付けられ、`shape=star` が G0239 になる。
- `[composition] kenten = "star"` が G0306 になり、`kenten = "triangle"` を読める。

### 組み方（`modules/golem-layout/test/Main.hs`）

- `[kenten shape=circle: 漢、「字」ー]` で、漢、字、ー の箱が `KindKenten` で `lkKenten = Just KentenCircle` を持ち、「、」「「」「」」の箱は `KindPunctuation` である。
- 入れ子の `[kenten shape=dot: あ[kenten shape=circle: い]]` で、い の形が `KentenCircle` である。
- 圏点の中の欧文の語の箱が `KindText` のままである。

### 描画（`modules/golem-driver/test/Main.hs`）

Source Han Sans のサブセット（`modules/golem-font/test/fonts/`）を本文の書体にする。
サブセットに圏点の字がなければ、十の字を加えたサブセットを作り直し、README に経緯を書く。

- 横組みの `[kenten: 漢]` で、圏点のグリフが U+FE45 のグリフであり、大きさが `s/2` である。グリフの字面の矩形の中心が、親文字の送りの中央の上、親文字の字面の枠の上端から `s/4` 上にある。
- 縦組みで、圏点の字面の中心が、行の中心線から `3s/4` 右、親文字の箱の始まりから `s/2` 下にある。
- `shape=triangle` で、U+25B2 のグリフが描かれる。
- `[composition] kenten = "open-circle"` のとき、形を省いた圏点で U+25CB のグリフが描かれる。
- 圏点の中の「「」のグリフの位置が、圏点のない「「」と同じである。
- 圏点の字を持たない書体（Source Sans Pro を和文の役割に指定する）で G0809 が一つだけ出て、PDF を書かない。
- `[ruby: [kenten: 漢]|かん]` と `[kenten: [ruby: 漢|かん]]` で、それぞれ G0745 のお知らせが出て、PDF は書かれる。
- 既存の圏点を含む PDF の golden テストは、圏点の位置が変わるので期待値を直す。直す前に、変わったのが圏点のグリフだけであることを確かめる。

### HTML（`modules/golem-html/test`）

- 形を省いた圏点の class が `kenten kenten-sesame` になり、`shape=open-triangle` の class が `kenten kenten-open-triangle` になる。
- CSS に四つの形の規則と `.kenten-sesame` がある。

### 自動テストにしない確かめ方

- 十の形の圏点を横組みと縦組みで組んだ PDF を目で見て、圏点が親文字の中央の上（縦組みでは右）にあり、親文字にも隣の行にも重ならないことを確かめる。
- 同じ原稿の HTML を Safari と Chrome で開き、形が PDF と同じであることを確かめる。
- 手元に InDesign があれば、同じ書体で組んだ圏点と位置を比べ、差を実装のプルリクエストに書く。

## トレードオフ

圏点を字の字面の中心で置くことにした。
グリフの原点と送りで置けば、書体の設計者の意図した位置になるが、`﹅` のように縦組みの互換の字形が横組みでずれることが、今の不具合の原因である。
字面で中心を取れば、書体によらず中央にそろう。
その代わり、ゴマのように形の重心が字面の矩形の中心と異なる字では、目で見た中央から少しずれる可能性がある。

圏点の字のない書体をエラーにした。
警告にして圏点を描かずに組む案もあるが、書き手の強調が黙って落ちる。
エラーの位置を原稿の圏点ではなく `style.toml` にしたので、どの圏点で起きたかは分からないが、直すのは書体か形の設定であり、原稿の位置は要らない。

圏点の形を `Look` に載せたので、圏点の内と外の境でペアカーニングがかからなくなる。
InDesign のメトリクスのカーニングも、書式の異なる字のペアにはかけないと記憶している（[docs/adr/0020](../../adr/0020-indesign-character-features.md) の第三者の回答）。

約物に圏点を付けない規則を、CSS の一般カテゴリの判定に合わせた。
JLReq と InDesign が約物の圏点をどう扱うかは確かめていない。
HTML と PDF で圏点の付く字がそろうことを優先した。

## 参考文献

- W3C, CSS Text Decoration Module Level 3, https://www.w3.org/TR/css-text-decor-3/ 。`text-emphasis-style` の形と字、圏点を描かない字。
- W3C, Requirements for Japanese Text Layout（JLReq）, https://www.w3.org/TR/jlreq/ 。圏点の形と配置。この ADR の決定に使った範囲の本文は確かめていない。
- Unicode Character Database, General Category。
- InDesign の圏点の設定。記憶によるものであり、Adobe のヘルプの本文では確かめていない。
