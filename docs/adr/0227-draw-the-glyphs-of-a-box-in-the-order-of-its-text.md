# ADR 0227: 一つの箱の字形を、書体ごとにまとめず、原稿の字の順に内容のストリームに描く

ステータス: 採択（未実装）

## 文脈

[ADR 0183](0183-tagged-pdf-and-pdf-a.md) は、タグ付き PDF の読む順を構造の木の順とし、内容のストリームに描く順を今のままにすると決めた。
構造の木の葉は、マークした内容の並び（`BDC` から `EMC` まで）一つずつであり、一つの葉の中の字の順は、内容のストリームに描いた字形の順になる。

`languages` の fixture の構造の木の golden は、区間の外の `“Hello”` を `“”Hello` と書いている（[`structure-languages.txt`](https://github.com/tett23/golem/blob/6380b99853307e4d4f3e35e8a448a84ce879412d/modules/golem-driver/test/golden/structure-languages.txt#L5)）。
[ADR 0222](0222-line-breaking-points-the-invariants-did-not-decide.md) の実装（[#682](https://github.com/tett23/golem/pull/682)）の前は、`“Hel”lo` だった。
0222 は、`Hello` の分綴の位置を変えて、語を二つの箱から一つの箱にしただけであり、順が乱れる原因ではない。
golden は乱れた順をそのまま固定している。

### 一つの箱の字形を、書体の番号の順に描いている

golem-typeset の [`runAt`](https://github.com/tett23/golem/blob/6380b99853307e4d4f3e35e8a448a84ce879412d/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L440-L504) は、箱の字を書体ごとの連なりに分けてシェイピングし、字形を原稿の順に並べる。
ところが、描く段で、字形を書体の番号（と合成の太字と斜体、縦組みで回す字形かどうか）をキーにした `Map` にまとめ、キーの順に一つずつの字形の連なり（`GlyphRun`）にする（[`byFont` と `marksOf`](https://github.com/tett23/golem/blob/6380b99853307e4d4f3e35e8a448a84ce879412d/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L471-L472)）。
字形はそれぞれの位置に描くので、紙面の見た目は変わらない。
変わるのは、内容のストリームの中の字形の順だけである。

区間の外の `“Hello”` は、引用符が隣の欧文の語の箱に入る（golem-layout の `isJoiner`）。
一方、描く書体は、golem-typeset の [`fontFor`](https://github.com/tett23/golem/blob/6380b99853307e4d4f3e35e8a448a84ce879412d/modules/golem-typeset/src/Golem/Typeset/FontProvider.hs#L158-L161) が字の文字クラスで選ぶ。
区間の外の `“` と `”` は欧文（`Western`）の字ではないので、和文の書体で描く。
一つの箱に二つの書体が混じり、和文の書体の番号が小さいので、`“”` を先に、`Hello` を後に描く。
0222 の前は、`“Hel` と `lo”` の二つの箱で、二つめの箱の `”` が `lo` より先に来ていた。

同じ形は、引用符に限らない。
区間の外の `a—b` のように、和文の書体で描く両用の字を含む欧文の語の箱と、合成の太字か斜体の字が一部だけ違う箱でも、字形の順が原稿の順と違いうる。

### 同じファイルの別の描き方は、すでに原稿の順に描いている

全角のダッシュの連なりを描く経路は、「同じ書体の字形が続く限り一つの連なりにする」とし、続く字形だけをまとめている（[`Draw.hs`](https://github.com/tett23/golem/blob/6380b99853307e4d4f3e35e8a448a84ce879412d/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L558-L565)）。
`runAt` だけが、続いていない字形もまとめる。

### 読む順の規格

ISO 32000-1 の 14.8.2.3（Page Content Order）は、マークした内容の並びの中の内容を、内容のストリームの順に読むとする。
PDF/UA-1（ISO 14289-1）は、構造の木が論理の読む順を表すことを求める。
Matterhorn Protocol の検査項目 09-001（タグが論理の読む順にない）は、検証器では調べられない、人が確かめる項目である。
veraPDF は、この乱れを見つけない。
CI の `conformance-pdfs` の `languages` が検証を通っているのは、そのためである。

## 実装すること

### 1. `runAt` は、続く字形だけを一つの連なりにまとめる

`marksOf` で、字形を `Map` にまとめず、原稿の順に並んだ字形を、キー（書体の番号、合成の太字と斜体、回す字形かどうか）が同じものが続く限り一つの連なりにまとめる。
キーが変われば、新しい連なりを始める。
全角のダッシュの連なりの `marksOf` と同じ規則である。

- 一つの字形の位置、大きさ、色、`ActualText` の扱い（[golem-driver ADR 0030](../golem-driver/adr/0030-ligature-text-layer.md)）は変えない。
- 連なりの数は、書体が交互に変わる箱で増える。`“Hello”` は、一つの連なりの二つから、三つになる。

### 2. 構造の木の golden を直す

`structure-languages.txt` の `“”Hello` を `“Hello”` に直す。
ほかの構造の木の golden（`sample`、`kanikosen`、`conformance` の二つ）が変わるかを確かめ、変われば原稿の順になったことを確かめて直す。

### 3. 箱の字の順を確かめるテストを足す

golem-typeset か golem-driver のテストに、葉の字の順を確かめるテストを足す（「テスト設計」）。
`structureText` は、葉ごとに描いた字形の ToUnicode を内容のストリームの順につなぐので（[`structureText`](https://github.com/tett23/golem/blob/6380b99853307e4d4f3e35e8a448a84ce879412d/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L758-L794)）、このテストに使える。

### 4. 文書

- 仕様書のタグ付き PDF の節に、「一つの葉の中の字形は、原稿の字の順に内容のストリームに描く。書体が変わるたびに字形の連なりを分ける」と、この ADR へのリンクを足す。
- [ADR 0183](0183-tagged-pdf-and-pdf-a.md) の「内容のストリームに描く順は今のままとし、論理の順に並べ替えない」は、葉と葉のあいだの順についての決定であり、この ADR はそれを変えない。採択したら、[ADR 0183](0183-tagged-pdf-and-pdf-a.md) のステータスの行に「（一つの葉の中の字形の順）は ADR 0227」を足す。

### 5. 出力の変化

紙面の見た目は変わらない。
一つの箱に二つ以上の書体か合成の書体が混じる本の PDF のバイト列は変わる。
`scripts/visual/` の参照は変わらない見込みであり、golden（構造の木）と、二つのマニュアルと complex fixture の決定性のハッシュは変わりうる。
実装のプルリクエストで確かめ、説明に書く。

## 実装しないこと

- **区間の外の引用符の書体**：区間の外の `“Hello”` の引用符を和文の書体で描く今の選び方は変えない。書体を欧文に変えても、合成の太字と斜体の混じる箱で同じ乱れが残る。語の最初の字が両用の字の語の書体は、[ADR 0222](0222-line-breaking-points-the-invariants-did-not-decide.md) の「メンテナーが決めること」の 6 とロードマップの項目で、別に決める。
- **[ADR 0222](0222-line-breaking-points-the-invariants-did-not-decide.md) の D3 の前提**：0222 の「文脈」は、`said”` の `”` を欧文の書体で組むと書いた。実際は、`ceWordCharAdvance` は語の最初の字のシェイピングの役割で `”` を測り、その役割の中の書体は `fontFor` が文字クラスで選ぶので、和文の書体を持つ本では和文の書体で測る（[`Flow.hs`](https://github.com/tett23/golem/blob/6380b99853307e4d4f3e35e8a448a84ce879412d/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L1087)）。描く書体も同じ `fontFor` で選ぶので、測る書体と描く書体は合っており、D3 の「突き出しはその字の送りを超えない」は成り立つ。この ADR の字形の順とは別の点であり、ここでは扱わない。
- **葉と葉のあいだの順**：[ADR 0183](0183-tagged-pdf-and-pdf-a.md) のとおり、構造の木の順で決める。
- **語間の空白の字**：構造の木の葉の字には、語間の空白がない（golden の `AnoteinEnglish`）。空白は字形を描かないグルーだからである。読み手の側が字の位置から語の区切りを推し量れるかは確かめておらず、この ADR では扱わない。

## 不変条件

- **R1**：一つの葉の字形を内容のストリームの順に並べ、ToUnicode か `ActualText` で字に戻してつなぐと、その葉の箱の字を原稿の順につないだものになる。ただし、ハイフンの字形（分綴の位置に描く `-`）は、前の箱の字の後に来る。
- **R2**：書体のキーが同じ字形が続けば、一つの連なりにまとめる。続かない字形は、同じキーでもまとめない。
- **R3**：字形の位置、大きさ、色は、この ADR の前と同じである。`scripts/visual/` の参照の画像は変わらない。
- **R4**：一つの書体だけで描く箱の内容のストリームは、この ADR の前と同じである。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 箱の書体 | 一つ、二つ（`“Hello”`）、交互に三回以上（`“a—b”`） |
| 合成の書体 | なし、太字だけの字が混じる、斜体だけの字が混じる |
| 組方向 | 横組み、縦組み（回す欧文の字形と立てる字形が混じる箱） |
| `ActualText` | なし、合字のクラスタを含む |
| 区間の言語 | なし、`en`、`ja` |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
テストの名前には、R1 から R4 の番号を入れる。

- **R1**：`structure-languages.txt` の golden を `“Hello”` に直し、今の実装で失敗すること。
- **R1**：小さなプロジェクト（`miniStructure`）で、区間の外の `“a—b”`、`[lang ja: “Hello”]`、合成の太字の字を含む語を組み、葉の字が原稿の順であること。今は `“a—b”` で失敗する見込みである。
- **R1**：fixture の `languages`、`complex-horizontal`、`complex-vertical` の構造の木で、各葉の字から空白を除いたものが、その葉の箱の字をつないだものと一致すること。
- **R2、R4**：golem-typeset のテストで、`“Hello”` の箱の内容が三つの字形の連なりになり、一つの書体の箱（`Hello`）が一つの連なりのままであること。
- **R3**：`scripts/visual/` の参照の画像が変わらないこと（実装のプルリクエストの CI で確かめる）。

## トレードオフ

書体が交互に変わる箱では、字形の連なりと書体の切り替え（`Tf`）が増え、PDF が少し大きくなる。
英語の引用符を区間の外に書いた日本語の本では、引用符を含む語の箱ごとに、連なりが一つか二つ増える。

`ActualText` で葉の字を原稿の順に書き添える案は、内容のストリームを変えずに読む順を直せる。
ただし、`ActualText` を読まない読み手（テキストの検索と選択）には、乱れた順が残る。
`ActualText` の中に、[golem-driver ADR 0030](../golem-driver/adr/0030-ligature-text-layer.md) の `ActualText` を入れ子にすることにもなる。

## メンテナーが決めること

1. **字形の順を、どこで直すか**：推奨は、`runAt` で、続く字形だけを一つの連なりにまとめ、原稿の字の順に描くことである。同じファイルのダッシュの描き方と同じ規則であり、紙面を変えずに、内容のストリームの順を読む順に合わせる。
   - 退けた案の一つは、書体が混じる箱を `ActualText` で包むことである（「トレードオフ」）。
   - 二つめは、区間の外の引用符を欧文の書体で描き、一つの箱の書体を一つにすることである。紙面の見た目を変え、合成の書体と回す字形の混じる箱の乱れは直らない。
   - 三つめは、golden を直さず、今の順を既知の不具合として仕様書に載せることである。支援技術が `“”Hello` と読む PDF を、PDF/UA の本として出し続ける。
2. **葉の字の順を、fixture の全体で確かめるか**：推奨は、確かめることである（「テスト設計」の R1 の三つめ）。今の golden は、乱れた順をそのまま固定しており、golden だけでは乱れに気付けない。
   - 退けた案は、`languages` の golden だけを直すことである。ほかの形の箱の乱れを見逃す。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-08、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- ISO 32000-1:2008, Document management: Portable document format, Part 1: PDF 1.7.（14.8.2.3 Page Content Order）
- ISO 14289-1:2014, Document management applications: Electronic document file format enhancement for accessibility, Part 1: Use of ISO 32000-1 (PDF/UA-1).
- PDF Association. Matterhorn Protocol 1.1.（検査項目 09-001）
- [ADR 0183](0183-tagged-pdf-and-pdf-a.md)、[ADR 0187](0187-inline-language-switch.md)、[ADR 0222](0222-line-breaking-points-the-invariants-did-not-decide.md)
- [golem-driver ADR 0030](../golem-driver/adr/0030-ligature-text-layer.md)
- [#682](https://github.com/tett23/golem/pull/682) の説明（「The tagged-PDF text of “Hello” in the languages fixture was already out of order」）
