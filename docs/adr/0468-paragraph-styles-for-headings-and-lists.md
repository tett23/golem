# ADR 0468: 見出しとリストの項目に段落スタイルを結び付ける

Status: proposed

## 文脈

[root ADR 0374](0374-paragraph-style-controls.md) は、見出しとリストを含む段落に、行送り、次の段落の既定のスタイル、先頭の書記素の文字スタイルを指定すると決めた（0374 の 15 行）。
しかし、見出しは段落スタイルでなく `[headings.<階層>]` で組み、リストの項目の段落は `body` で組む。
0374 は、見出しとリストにどの段落スタイルを結び付けるかを書いていない（ロードマップの「見出しとリストへの適用の方法」）。

メンテナーは、2026-11-26 に、0374 の残りを機能ごとの ADR に分けると決めた。
この ADR は、見出しとリストの項目に段落スタイルを結び付ける方法を決める。

## 調査した事項

origin/main（[c034510](https://github.com/tett23/golem/commit/c034510e33476f4af68ba22636f5ab6ef8463f0a)）で、次のことを確かめた。
根拠の行は、調べを受け持ったエージェントが `git show` と `git grep` で返したものである。

- `[headings.<階層>]` のキーは、`font`、`size`、`number`、`page-break`、`lines`、`running-head`（廃止、G03019）、`rule-before`、`rule-after`、`number-title-separator`、`block-align` である（[Style.hs#L2550-L2566](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-project/src/Golem/Project/Style.hs#L2550-L2566)）。
  段落スタイルの名前を指すキーは無い。
- 組版は、見出しを、段落スタイルを持たない形（`styleLook style Nothing`）で組む（[Flow.hs#L3064-L3070](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L3064-L3070)）。
- リストの項目の段落は、その段落が持つ段落スタイルで組み、持たなければ `body` で組む（[Flow.hs#L3141-L3146](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L3141-L3146)、[Flow.hs#L3050](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L3050)）。
  リストの中の段落は字下げをしない（[Flow.hs#L3061](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L3061)）。

## 実装すること

### 見出し

`[headings.<階層>]` に、段落スタイルの名前を指すキー `paragraph-style` を足す。
`paragraph-style` を書いた階層の見出しには、その段落スタイルの次のキーだけが当たる。

- `line-pitch`：二行以上の見出しの行のあいだ。見出しの占める格子の行数は、今と同じく `[headings.<階層>]` の `lines` で決める
- `next-style`、`initial-style`
- `align`、`features`
- [root ADR 0466](0466-fit-characters.md) の `fit-characters`

ほかのキー（前後の空き、字下げ、囲み、背景、行の調整など）は、見出しには当てず、診断も出さない。
見出しの前後の空きと行取りは、今と同じく `[headings.<階層>]` で決めるからである。
`[headings.<階層>]` と段落スタイルの両方にあるキー（`font`、`size`、`page-break`、`rule-before`、`rule-after`、`number-title-separator`、[root ADR 0463](0463-title-formats-for-numbered-headings-and-captions.md) の `title-format`）は、`[headings.<階層>]` の値を使う。
両方にあるキーは、上の当たるキーに含めない。

HTML と EPUB の見出しの要素には、class `ps-<名前>` を付け、上の当たるキーの CSS を `h<階層>.ps-<名前>` の規則として書く。
`paragraph-style` を書かない見出しは、今と同じく組む。

段落スタイルの次スタイル（`next-style`）は、見出しの次の段落の段落スタイルを決める。
段落スタイルの `initial-style` は、見出しの題の先頭の書記素に当たる。

`paragraph-style` に無い段落スタイルの名前を書けば、エラーの G03302 `見出しの paragraph-style が指す段落スタイル <名前> がありません` とする。
位置は `[headings.<階層>]` の値である。
エラーの後は、`paragraph-style` が無いものとして組む。

### リストの項目

リストの項目の段落は、今と同じく、その段落が持つ段落スタイルか `body` で組む。
リストの全体に段落スタイルを当てるには、[root ADR 0460](0460-let-style-take-any-blocks-as-its-body.md) の本体の形の `@style` で、リストを本体に書く。
本体の段落スタイルは、項目の段落のうち、段落スタイルを持たないものに当たる。
リストの中の段落を字下げしない今の決まりは、段落スタイルを当てても変えない。

### 文書

仕様書の `[headings.<階層>]` のキーの表に `paragraph-style` を書き、見出しとリストの節に段落スタイルの当たり方を書く。
`docs/diagnostics.md` に G03302 を足す。
ロードマップの「見出しとリストへの適用の方法」を消す。
採択したら、0374 のステータスに `{"part":"見出しとリストへの適用","by":["docs/adr/0468-paragraph-styles-for-headings-and-lists.md"],"kind":"replace"}` を足す。

## 実装しないこと

見出しの原稿に、見出しごとの段落スタイルを書く記法は足さない。
`[lists]` に段落スタイルのキーは足さない。

## 不変条件

- I1: `paragraph-style` を書かない見出しと、`@style` の本体に無いリストは、この ADR の前と同じに組む。
- I2: `paragraph-style = s` の見出しの、当たるキーのうち `[headings.<階層>]` に無いものの値は、段落スタイル s の値に等しい。当たらないキーは、見出しの組み方を変えない。
- I3: `paragraph-style = s` の見出しの、`[headings.<階層>]` にあるキーの値は、`[headings.<階層>]` の値に等しい。
- I4: 本体の形の `@style s` の中のリストの、段落スタイルを持たない項目の段落は s で組み、持つ段落はその段落スタイルで組む。
- I5: 無い段落スタイルを指す `paragraph-style` の値ごとに、G03302 がちょうど一つ出る。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| `paragraph-style` の無い見出し | 今と同じ | I1 |
| `[headings.1] paragraph-style = "h"`、`h` の `line-pitch = "20pt"` | 見出しの行送り 20pt | I2 |
| `h` の `size = "12pt"`、`[headings.1] size = "16pt"` | 16pt | I3 |
| `h` の `next-style = "first"` | 見出しの次の段落は first | I2 |
| `paragraph-style = "missing"` | G03302。今と同じに組む | I1, I5 |
| `h` の `space-before = "2lh"` | 見出しの前の空きは今と同じ | I2 |
| `h` と `[headings.1]` の両方に `page-break` | `[headings.1]` の値 | I3 |
| `@style small` の本体のリストと、`@style body` の付いた項目 | ほかの項目は small、その項目は body | I4 |

## 受けいれ条件

なし。
不変条件のテストで足りるためである。

## テスト設計

root ADR 0468 I1 から I5 を名前の先頭に置いたテストを、golem-project（キーの読み込み）、golem-eval（リストの本体）、golem-typeset（組んだ見出しと項目）、golem-html（見出しの class と CSS）に足す。
テストは、実装の前に書いて落ちることを確かめる。

## トレードオフ

見出しの書体と大きさを `[headings.<階層>]` に残すので、今のスタイルはそのまま動く。
段落スタイルは、見出しに無いキーを足す道具になる。

リストに専用のキーを足さないのは、本体の形の `@style` で同じことが書けるからである。

## 参考文献

- [root ADR 0374](0374-paragraph-style-controls.md)
- [root ADR 0460](0460-let-style-take-any-blocks-as-its-body.md)
- [root ADR 0463](0463-title-formats-for-numbered-headings-and-captions.md)
