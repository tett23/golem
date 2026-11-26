# ADR 0469: 始め括弧の字下げを HTML と EPUB にも当てる

Status: proposed

## 文脈

[root ADR 0374](0374-paragraph-style-controls.md) は、段落スタイルの `opening-indent`（`normal` か `half`）で、始め括弧で始まる段落の字下げから半角分を引く方式を選べると決めた（0374 の 19 行）。
この方式は PDF だけに当たり、HTML と EPUB の字下げは変わらない（ロードマップの「HTML と EPUB の始め括弧の字下げ」）。

メンテナーは、2026-11-26 に、0374 の残りを機能ごとの ADR に分けると決めた。
この ADR は、`opening-indent` を HTML と EPUB にも当てる。

## 調査した事項

origin/main（[c034510](https://github.com/tett23/golem/commit/c034510e33476f4af68ba22636f5ab6ef8463f0a)）で、次のことを確かめた。

- PDF の組版は、`opening-indent = "half"` の段落の先頭の字が始め括弧類なら、1 行目の字下げから文字の大きさの半分を引く（[Flow.hs#L2782-L2788](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L2782-L2788)）。
  引いた値の下限は、段落の始まりの字下げの負の値である。
  0374 の 19 行は「下限は 0 とする」と書き、実装と食い違う。
  メンテナーは、2026-11-26 に、下限は 0 であり、ただし字下げそのものは負になりうると決めた。
  PDF の実装を 0374 に合わせて直すことは、ロードマップの v1.0.0 の課題に載せる。
  先頭の字の種類は、その字の区間の言語で決める。
- HTML は、`body` の段落を、class の無い `p`（`p:where(:not([class]))`）の規則でも選ぶ（[Html.hs#L1728](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-html/src/Golem/Html.hs#L1728)）。
- 先頭の字の種類の判定（`lookClass`）は golem-layout に、先頭の字の取り出し（`firstCharOf`）は golem-typeset にあり、golem-html はどちらにも依存しない（調べを受け持ったエージェントが読んだ golem-html.cabal の 25 行から 31 行）。
- HTML は、段落スタイルの字下げを、`p.ps-<名前>` の CSS の `padding-inline-start` と `text-indent` に書く（[Html.hs#L1725-L1736](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-html/src/Golem/Html.hs#L1725-L1736)）。
- `psOpeningIndent` を参照するのは golem-project の Style.hs と golem-typeset の Flow.hs だけで、golem-html と golem-driver の HTML の出力には無い（調べを受け持ったエージェントの `git grep` による）。

## 実装すること

HTML と EPUB の出力は、`opening-indent = "half"` の段落スタイルの段落のうち、PDF と同じ規則で先頭の字が始め括弧類であるものに、属性 `data-opening` を足す。
class を足さないのは、class の無い `p` を選ぶ `body` の規則を、今のまま当てるためである。
その段落スタイルの CSS に、`p.ps-<名前>[data-opening]`（`body` では `p[data-opening]`）の規則で、字下げを書く。
字下げの値は、0374 のとおり、1 行目の字下げから `0.5em` を引いた値とし、下限を 0 とする。
ただし、1 行目の字下げがもともと負（ぶら下げ）なら、半角分を引かず、その値のままとする。
式で書けば、1 行目の字下げを f として `max(min(f, 0), f - 0.5em)` である。
f の値が分かっているので、出力の側で計算した値を書く。
f が `em` でない単位なら、CSS の `max()` で書く。

字の種類は、golem-html がすでに依存する golem-unicode の `charClassIn` で決め、先頭の字の取り出し（`firstCharOf`）だけを golem-html に写す。
golem-* のパッケージの依存は変えない。
`line-breaks = "keep"` の段落スタイルの段落は、HTML では一つの `p` なので、1 行目にだけ当てる。

### 文書

仕様書の `opening-indent` の記述に、HTML と EPUB の出力を書く。
ロードマップの「HTML と EPUB の始め括弧の字下げ」を消す。
採択したら、0374 のステータスに `{"part":"始め括弧の字下げ","by":["docs/adr/0469-opening-indent-in-html-and-epub.md"],"kind":"supplement"}` を足す。

## 実装しないこと

PDF の組み方は変えない。
字の判定に、ブラウザーの CSS の機能（`text-spacing-trim` など）は使わない。

## 不変条件

- I1: `opening-indent = "half"` を持たない段落スタイルの HTML と EPUB の出力は、この ADR の前と同じである。
- I2: `line-breaks = "keep"` でない段落の判定と、`keep` の段落の 1 行目の判定は、表の入力について、HTML（`data-opening` を持つか）と PDF（字下げから半角分を引くか）が、同じ期待の表に等しい。
- I3: `data-opening` を持つ段落に当たる CSS の規則は、字下げの規則のほかは、持たないときと同じである。
- I4: 1 行目の字下げを f とすると、`data-opening` を持つ段落の 1 行目の字下げは `max(min(f, 0), f - 0.5em)` である。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| `opening-indent` の無い段落スタイル | 今と同じ | I1 |
| `half` で「「」で始まる段落 | `data-opening` | I2 |
| `half` を持つ `body` の「「」で始まる段落が二つ続く | 段落のあいだの空きは今と同じ | I3 |
| `half` で「あ」で始まる段落 | `data-opening` なし | I2 |
| `half` で `[lang en]` の区間の `(` で始まる段落 | PDF と同じ判定 | I2 |
| 空の段落 | `data-opening` なし | I2 |
| `first-line-indent = "1em"` と「「」 | 字下げ `0.5em` | I4 |
| `first-line-indent = "0.25em"` と「「」 | 字下げ 0 | I4 |
| `first-line-indent = "-1em"` と「「」 | 字下げ `-1em` のまま | I4 |

## 受けいれ条件

なし。
不変条件のテストで足りるためである。
ブラウザーでの見え方は、視覚の確かめの決まりのとおり、致命的な崩れだけを見る。

## テスト設計

root ADR 0469 I1 から I4 を名前の先頭に置いたテストを golem-html と golem-typeset に足す。
I2 は、同じ期待の表を golem-html と golem-typeset のテストに置き、それぞれの判定を表と比べる。
テストは、実装の前に書いて落ちることを確かめる。

## トレードオフ

先頭の字の判定を出力の側で行うので、CSS の機能のブラウザーごとの違いに依らない。
ブラウザーの `em` は段落の文字の大きさなので、半角分は PDF と同じ長さになる。

## 参考文献

- [root ADR 0374](0374-paragraph-style-controls.md)
