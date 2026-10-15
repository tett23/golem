# ADR 0011: ルビの親文字の中の文字スタイル

ステータス: 採択

## 文脈

ルビの親文字には、ほかのインラインの要素を入れ子にできる（[docs/markup.md](../../markup.md) の「ルビ」）。
意味論 IR の `RubySegment` の `rsBase` は `[InlineNoRuby]` であり、文字スタイル（`CharStyle`）、色（`Color`）、圏点（`Kenten`）を持てる。
正規表現スタイル（[docs/adr/0015](../../adr/0015-regex-styles.md)）も、一致した区間の境界が親文字の途中にあると、ルビの全体ではなく各セグメントの親文字の中を `CharStyle` で包む。

HTML と EPUB は、親文字の中の要素をそのまま `<ruby>` の中に書くので、親文字の一部だけを太字にしたり色を付けたりできる。
PDF では、それが効かない。
仕様書の「v1 の実装で次の段階以降に回した項目」の「ルビの親文字の中の文字スタイル」である。

### 今の組み方

`Golem.Layout.Japanese` の `rubyPieces` は、各セグメントの親文字を `plain` で文字列に平らにし、ルビの外側の `Look`（`ceLook env`）を一つだけ持つ部品にする。

```haskell
PRuby !Look !RubyKind !Text !(Maybe Text) -- ruby: the base and the reading
```

`plain` は `CharStyle` と `Color` と `Kenten` の中の文字を取り出し、スタイルを捨てる。
`itemsFor` は、親文字の各字の送りを外側の `Look` で測り（`baseAdvances`）、`placeRuby` で配置を決めて一つの箱にする。
箱の `bcText` は `親文字|読み` の文字列で、`bcLook` は外側の `Look` である。
golem-driver の `Golem.Driver.Pdf` の `drawLineAt` は、親文字の各字を `bcLook` で描く。

そのため、親文字の中の文字スタイルは、書体の役割、大きさ、合成の太字と斜体、色、ベースラインシフト、トラッキング、カーニングのどれも PDF に出ない。
親文字の一部に一致した正規表現スタイルも同じである。
[docs/adr/0015](../../adr/0015-regex-styles.md) のテスト設計は、親文字の中の一致が PDF で組めること（エラーにならないこと）だけを確かめており、見た目は確かめていない。

### InDesign のルビ

InDesign のルビは、テキストの範囲に属性として付き、親文字はそれぞれの字の文字の書式を保つと記憶している。
ルビの文字は、ルビの設定の書体と大きさで組む。
どちらも資料では確かめていない。

## 実装すること

### 部品と箱（golem-layout）

親文字の字ごとの `Look` を持たせる。

```haskell
PRuby !Look !RubyKind !Text ![Look] !(Maybe Text)
-- ルビの外側の Look、種類、親文字、親文字の字ごとの Look、読み
```

`[Look]` の長さは、親文字の文字列の字（Unicode のスカラー値）の数と同じとする。

`Golem.Layout.KnuthPlass` の `BoxContent` に欄を一つ加える。

```haskell
data BoxContent = BoxContent
  { ...
    -- | ルビの箱の親文字の字ごとの Look（golem-layout ADR 0011）。ほかの箱では空
    bcBaseLooks :: ![Look]
  }
```

行分割はこの欄を読まない。
`BoxContent` を作るすべての箇所（テストを含む）は、ルビの箱のほかは空の列を渡す。

### 親文字の Look の決め方

`rubyPieces` は、`plain` の代わりに、親文字の要素をたどって字と `Look` の組の列を作る。

- `Text` の字は、その位置の `Look` を持つ。最初の位置の `Look` はルビの外側の `Look` である。
- `CharStyle` と `Color` の中は、`piecesOf` の `restyled` と同じく `ceRestyle env lk inl` で内側の `Look` にして続ける。内側の設定が勝ち、書かない欄は外側から引き継ぐ。
- `Tcy` と `Number` は、今の `plain` と同じ文字列を、その位置の `Look` で持つ。
- `Kenten` の中の字は、その位置の `Look` で持つ。親文字の字の `Look` は、圏点の形の欄（[golem-driver ADR 0019](../../golem-driver/adr/0019-pdf-kenten-shapes.md) の `lkKenten`）を常に空にする。圏点の中のルビでも同じである。親文字の圏点は描かない（[golem-driver ADR 0019](../../golem-driver/adr/0019-pdf-kenten-shapes.md) の G0745）。
- そのほかの要素（注、索引の印など）は、今の `plain` と同じく字を出さない。

`InlineNoRuby` を `ceRestyle` に渡すときは、`Ruby` を持たない型から `Inline` に写す（`vacuous` と同じ写し方）。

### 送りと配置

- `baseAdvances` は、親文字の各字の送りを、その字の `Look` で測る。大きさや書体の役割が異なる字は、その字の大きさと書体で測る。
- 読みの大きさは、今と同じくルビの外側の `Look` の大きさの半分とする。読みの色と書体も外側の `Look` に従う。親文字の中の文字スタイルは読みに効かない。
- 隣のルビへのかけの余地（`allowance`）を求めるときも、隣のルビの親文字の字ごとの `Look` で測る。
- 親文字の中ではペアカーニングをかけない。親文字の中の字にはトラッキングを足さない。どちらも今と同じである（[docs/adr/0020](../../adr/0020-indesign-character-features.md) はルビの箱にトラッキングを足さないと決めている）。
- 箱の `bcLook` は、ルビの外側の `Look` のままとする。前後の字との空きと禁則は、今と同じく箱を和字として判定する。

### 描画（golem-driver）

`drawLineAt` の `KindRuby` と `KindGroupRuby` の分岐を、次のように改める。

- 親文字の `k` 番目の字を、`bcBaseLooks` の `k` 番目の `Look` で `runAt` に渡して描く。合成の太字と斜体、ベースラインシフト、書体の役割は、その `Look` に従う。`bcBaseLooks` が空の箱（プラグインやテストが作ったもの）は、今と同じく `bcLook` で描く。
- 読みの行に直交する方向の位置は、親文字の字の大きさのうち最も大きいもの `S` で決める。横組みでは基準線から `S` 上、縦組みでは中心線から `S/2 + r/2` 右とする（`r` は読みの大きさ）。親文字の大きさがそろっていれば、今と同じ位置である。
- 色の異なる親文字の字は、`P.Saved` の中で `P.SetColor` をしてから描く。箱の色（外側の `Look` の色）と同じ字は、今と同じく箱の色でまとめて描く。

### HTML と EPUB

変えない。
親文字の中の要素は、すでに `<ruby>` の中に書かれている。

### ドキュメント

- 仕様書の「v1 の実装で次の段階以降に回した項目」から「ルビの親文字の中の文字スタイル」の項目を消す。
- docs/markup.md の「ルビ」の節に、親文字の中の文字スタイルと色は親文字の字にだけ効き、読みには効かないことを書く。
- 利用者のマニュアル（`manual/`）を直す（[docs/adr/0024](../../adr/0024-manual-audiences-and-policy.md)）。
  - `manual/chapters/03-markup.gm` の「ルビ」の節（ラベル `ruby`）に、親文字の一部にスタイルを当てられることを書き、親文字の一部を太字にしたルビの見本を一つ加える。
  - `manual/chapters/05-style.gm` の「正規表現スタイル」の節に、正規表現スタイルがルビの親文字の一部にも当たることを書く。
  - `manual/appendices/a-markup.gm` の `[ruby: 親文字|読み]` の項に、親文字の中に文字スタイルのコマンドを書けることを書く。
  - 今の版で PDF に効かないと書いた箇所があれば消す（origin/main の `manual/` には見当たらない）。

## 実装しないこと

- 親文字の中の圏点（[golem-driver ADR 0019](../../golem-driver/adr/0019-pdf-kenten-shapes.md) の G0745 で知らせる）。
- 読みの中の文字スタイル。読みには文字だけを書ける（docs/markup.md）。
- 親文字の中の字の大きさの違いに応じて、読みの大きさを字ごとに変えること。読みはルビの全体で一つの大きさとする。
- 親文字の中のペアカーニングとトラッキング。
- 親文字の大きさが外側より大きいときに、行送りを広げること。行の格子は変えない。大きな親文字と読みが隣の行に重なる場合は、書き手が大きさを選び直す。

## テスト設計

実装の前に書き、失敗することを確かめる。

### 組み方（`modules/golem-layout/test/Main.hs`）

測る関数には、`Look` の書体の役割によって異なる送りを返す関数を入れる（役割 `body` では 1、役割 `heading` では 1.2）。

- 親文字が `漢` と `CharStyle "h" [字]`（`h` は役割 `heading` の文字スタイル）のグループルビで、箱の `bcBaseLooks` が `[外側の Look, heading の Look]` になる。読みが親文字より短いとき、箱の幅が `2.2 × s` である。
- 同じ原稿で文字スタイルのない場合、`bcBaseLooks` がすべて外側の `Look` で、箱の幅が今と同じ `2 × s` である。
- `Color` の中の親文字の字の `Look` が、その色を持つ。
- 親文字の中の `Kenten` の字の `Look` が圏点を持たない。
- モノルビの隣り合うセグメントで、かけの余地が隣の親文字の字の `Look` で測られる。
- ルビのほかの箱の `bcBaseLooks` が空である。

### 描画（`modules/golem-driver/test/Main.hs`）

- 親文字の二字目にだけ `bold` を当てたルビで、二字目のグリフが合成の太字の `StyledGlyphRun` で描かれ、一字目と読みは普通の `GlyphRun` で描かれる。
- 親文字の一字目にだけ色を当てたルビで、一字目のグリフの前に `SetColor` があり、読みは既定の色である。
- 親文字の一字目の大きさを 1.5 倍にしたルビで、読みの基準線が親文字の基準線から `1.5 × s` 上にある。
- [docs/adr/0015](../../adr/0015-regex-styles.md) のテスト設計の `[ruby: 東京12|とうきょう]` 相当の原稿で、`12` に一致する正規表現スタイル `n`（役割 `heading`）を当てると、`12` のグリフが `heading` の書体で描かれる。
- 文字スタイルのないルビを含む既存の PDF の golden テストが変わらない。

### 自動テストにしない確かめ方

- マニュアルに加えるルビの見本を PDF で開き、親文字の一部だけが太字になり、読みの位置と大きさが変わらないことを目で確かめる。同じ見本の HTML と見比べる。

## データ構造の変更

- `Golem.Layout.Japanese` の `PRuby` に、親文字の字ごとの `Look` の列を加える。
- `Golem.Layout.KnuthPlass` の `BoxContent` に `bcBaseLooks :: [Look]` を加える。

## トレードオフ

字ごとの `Look` を `BoxContent` に持たせた。
`BoxContent` は行分割の型であり、行分割が読まない描画のための欄が一つ増える。
すでに `bcLook` と `bcTag` が同じ性質の欄として載っているので、同じ扱いにした。
ルビの箱を親文字の字ごとの箱に分ける案は、ルビの配置（`placeRuby`）が親文字の全体を一つの単位として扱うので採らない。

読みをルビの外側の `Look` で組むことにした。
親文字の一部が太字でも、読みは太字にならない。
HTML の `<rt>` は、親文字の中の `<span>` のスタイルを受け継がないので、HTML と同じ結果になる。

親文字の大きさが異なるときの読みの位置を、最も大きい字に合わせた。
小さい字の上では読みが字から離れるが、読みが大きい字に重なるよりよい。

## 参考文献

- W3C, Requirements for Japanese Text Layout（JLReq）, https://www.w3.org/TR/jlreq/ 。ルビの配置。
- W3C, Ruby Annotation（HTML Living Standard の `ruby` 要素）, https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-ruby-element 。
- InDesign のルビの書式。記憶によるものであり、Adobe のヘルプの本文では確かめていない。
