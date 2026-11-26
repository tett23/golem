# ADR 0466: 段落スタイルの fit-characters で字取りを組む

Status: proposed

## 文脈

[root ADR 0374](0374-paragraph-style-controls.md) は、段落スタイルに `fit-characters`（0 より大きい自然数）を設け、「指定字数の幅に字間を均等配分する」と決めた（0374 の 18 行）。
また、`drop-lines` と `fit-characters` の併用を設定位置で拒むと決めた（0374 の 23 行）。
0374 は、段落の字数が指定字数を超えるとき、段落が二行以上になるとき、併用の誤りのコードを書いていない（ロードマップの「字取りの範囲」と「`drop-lines` と `fit-characters` の併用の誤りのコード」）。

メンテナーは、2026-11-26 に、0374 の残りを機能ごとの ADR に分けると決めた。
この ADR は、字取りの組み方と、併用の誤りのコードを決める。

## 調査した事項

origin/main（[c034510](https://github.com/tett23/golem/commit/c034510e33476f4af68ba22636f5ab6ef8463f0a)）で、次のことを確かめた。
根拠の行は、調べを受け持ったエージェントが `git show` と `git grep` で返したものである。

- `fit-characters` はコードに無い（`git grep -E 'fit-characters' c034510` の結果は docs/roadmap.md と 0374 だけ）。
  今は未知のキーとして G03006 になる。
- 段落スタイルのキーは、`style.toml` でも `@style-def` でも、`FromValue ParaStyleDef` が読む（[Style.hs#L2395-L2458](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-project/src/Golem/Project/Style.hs#L2395-L2458)）。
- docs/diagnostics.md の G03 の最大のコードは G03295 で、G03296 から G03300 は [root ADR 0463](0463-title-formats-for-numbered-headings-and-captions.md) と [root ADR 0464](0464-wrap-text-along-figure-outlines.md) の草案が使う。

## 実装すること

### キー

段落スタイルに `fit-characters` を足す。
値は 0 より大きい自然数で、ほかの値は今と同じく G03006 とする。
`fit-characters = n` の段落スタイルの段落は、一行の段落として、段落の文字の大きさの n 字分の幅に組む。
この幅を、字取りの幅と呼ぶ。

### 字間の配り方

段落の書記素が二つ以上なら、字取りの幅から書記素の送り幅の和を引いた長さを、書記素のあいだに均等に配る。
段落の始めと終わりには空きを置かない。
配る長さを `Sp` に丸めたときの余りは、始めのあいだから順に 1 sp ずつ足す。
書記素が一つなら、0374 の境界の表のとおり、字を字取りの幅の中央に置く。

字取りの幅に組んだ行は、段落の `align` に従って、行の中に置く。

### 字取りの幅に収まらない段落

書記素の送り幅の和が字取りの幅より大きい段落は、字取りをせず、字間を詰めずに今の組み方で組む。
そのときは、段落ごとに警告の G07144 `段落の字が fit-characters の <n> 字分の幅に収まらないので、字取りをしません` を出す。
位置は段落である。
字の送り幅は組版でしか分からないので、G07144 は組版の段の診断であり、PDF をターゲットに含むビルドと `golem check` で出す。
段落の中に改行（`LineBreak`）があるときも、同じく字取りをせず、G07144 を出す。

### 当てる段落

`fit-characters` は、文書の最上位の段落と、`@style` などの結果をその場に置く本体の中の段落に当てる。
[root ADR 0468](0468-paragraph-styles-for-headings-and-lists.md) の `paragraph-style` で段落スタイルを結び付けた見出しにも当てる。
リストの項目、表のセル、キャプション、注、フレームの中の段落には当てず、診断も出さない。

### drop-lines との併用

`based-on` をたどって決まった段落スタイルが、`drop-lines` と `fit-characters` の両方を持てば、エラーの G03301 `段落スタイル <名前> は drop-lines と fit-characters の両方を持っています。どちらか一方を書きます` を出す。
位置は、その段落スタイルの定義（`style.toml` の表か `@style-def` の行）である。
両方を持つ段落スタイルごとに一つ出す。
エラーの後は、その段落スタイルの段落を、二つのキーが無いものとして組む。

### HTML と EPUB

HTML と EPUB では、その段落スタイルの段落に、`width: <n>em`、`text-align: justify`、`text-align-last: justify` と `text-justify: inter-character` を書く。
ブラウザーの組み方は PDF と同じにならない。

### 文書

仕様書の段落スタイルのキーの表に `fit-characters` を書き、組み方の節を足す。
`docs/diagnostics.md` に G07144 と G03301 を足す。
ロードマップの「字取りの範囲」と「`drop-lines` と `fit-characters` の併用の誤りのコード」を消す。
採択したら、0374 のステータスに `{"part":"字取り","by":["docs/adr/0466-fit-characters.md"],"kind":"replace"}` を足す。

## 実装しないこと

字取りの幅に収まらない段落の字間を詰めることはしない。
二行以上の段落を、行ごとに字取りにすることはしない。

## 不変条件

- I1: `fit-characters` を書かない段落は、この ADR の前と同じに組む。
- I2: 字取りをした段落の行の長さは、字取りの幅に等しい。
- I3: 字取りをした段落の書記素のあいだの空きは、どの二つも差が 1 sp 以下である。
- I4: 字取りの幅に収まらない段落と改行のある段落の数を k とすると、G07144 はちょうど k 個出る。
- I5: `drop-lines` と `fit-characters` の両方を持つ段落スタイルの数を k とすると、G03301 はちょうど k 個出る。
- I6: 0 か自然数でない `fit-characters` の値ごとに、G03006 がちょうど一つ出る。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| `fit-characters` を書かない段落 | 今と同じ | I1 |
| 2 字の段落、`fit-characters = 4` | 4 字分の幅。字のあいだに 2 字分 | I2, I3 |
| 4 字の段落、`fit-characters = 4` | 4 字分の幅。空きは 0 | I2, I3 |
| 5 字の段落、`fit-characters = 4` | 字取りなし。G07144 | I4 |
| 1 字の段落、`fit-characters = 3` | 字を中央に置く | I2 |
| `paragraph-style` で結び付けた見出しの 2 字、`fit-characters = 4` | 4 字分の幅 | I2 |
| リストの項目の段落、`fit-characters = 4` | 字取りなし。診断なし | I1 |
| 改行のある段落 | 字取りなし。G07144 | I4 |
| `based-on` で `drop-lines` を継ぎ、自分で `fit-characters` を持つ段落スタイル | G03301 | I5 |
| `fit-characters = 0` | G03006 | I6 |

## 受けいれ条件

なし。
不変条件のテストで足りるためである。

## テスト設計

root ADR 0466 I1 から I6 を名前の先頭に置いたテストを、golem-project（キーの読み込みと併用の検査）と golem-typeset（行の長さと字間）に足す。
テストは、実装の前に書いて落ちることを確かめる。

## トレードオフ

収まらない段落を詰めずに警告にするのは、出力を黙って変えないためである。
書き手は、字数を減らすか `fit-characters` を大きくするかを選べる。

## 参考文献

- [root ADR 0374](0374-paragraph-style-controls.md)
- [root ADR 0465](0465-drop-caps.md)
