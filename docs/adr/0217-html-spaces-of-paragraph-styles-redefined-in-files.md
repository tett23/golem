# ADR 0217: ファイルの `@style-def` で改めた段落の前後のアキを、HTML と EPUB にも当てる

ステータス: 採択（未実装）

## 文脈

[ADR 0189](0189-paragraph-alignment-spacing-and-end-indent.md) は、段落スタイルに `space-before` と `space-after` を加えた。
PDF では二つのブロックのあいだの行を数え、HTML と EPUB では隣り合う兄弟の要素のセレクターで `margin-block-start` を書く。
同じ ADR は、`@style-def` で定義を重ねたファイルでは、空きの宣言を `body.file-<n>` で始まる規則ですべて書き直すと決めている。

ところが、ファイルの定義で後のアキを 0 に戻すと、PDF では空きが消え、HTML と EPUB では style.toml の空きが残る。
仕様書の「段落スタイル」の節は、この食い違いを今の振る舞いとして書いている（「style.toml の後のアキを、ファイルの定義で 0 に戻しても、style.toml の後のアキの規則は残る」）。
2026-11-08 のレビューは、これを [ADR 0189](0189-paragraph-alignment-spacing-and-end-indent.md) からの逸脱とした。
書き手が `@style-def` に書いた値を、HTML だけが黙って使わないことになる。

### 再現

style.toml に後のアキを持つ段落スタイルを置き、ファイルの先頭で 0 に戻した（origin/main の `f366145c` を組んだ `golem`、2026-11-08）。

```toml
[paragraph-styles.note]
based-on = "body"
space-after = 2
```

```
@style-def paragraph note space-after=0

# はじめに

@style note
  注の段落。

本文。
```

`golem build --target html` の `style.css` には、次の規則が並んだ（抜粋）。

```css
p.ps-note + :not(.ps-note):not(.blank-line) { margin-block-start: 2em; }
body.file-1 p.ps-note { font-family: inherit; margin-block: 1em; … }
body.file-1 p.ps-note + p.ps-note { margin-block-start: 1em; }
```

`body.file-1` の後のアキの規則がないので、「本文。」の段落の上には style.toml の 2em が残る。
PDF は、そのファイルの段落スタイルで空きを数える（[`gapLines`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L1471-L1486)）ので、空きは 0 行になる。

### 原因

ファイルの規則は、[`spaceRules`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-html/src/Golem/Html.hs#L1166-L1193) を接頭辞 `body.file-<n>` で呼んで作る（[`localRules`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-html/src/Golem/Html.hs#L1261)）。
`spaceRules` は、値が 0 より大きい空きだけを規則にする（[L1183-L1192](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-html/src/Golem/Html.hs#L1183-L1192)）。
style.toml の規則（[L1008](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-html/src/Golem/Html.hs#L1008)）は、どのファイルのページにも当たる。
ファイルの値が 0 なら、打ち消す規則がなく、style.toml の規則が勝つ。

同じ原因は、後のアキの規則だけでなく、組の規則にも及ぶ。
style.toml の組の規則 `p.ps-A + p.ps-B:not(.ps-A)` の詳細度は (0, 3, 2) で、ファイルの段落の規則 `body.file-<n> p.ps-B`（(0, 2, 2)）より高い。
style.toml で A の後のアキが 1、B の前のアキが 3 なら、組の規則は 3em になる。
ファイルで B の前のアキを 0 に戻すと、PDF は max(1, 0) = 1 行を空け、HTML は組の規則の 3em を残す。
前のアキの規則（`p.ps-B`）は詳細度 (0, 1, 1) で、ファイルの規則に負けるので、単独では食い違わない。

0 より大きい値への書き換えは食い違わない。
ファイルの後のアキの規則（(0, 4, 2)）が style.toml の規則（(0, 3, 1)）に勝つからである。
食い違うのは、style.toml の空きの規則が残り、ファイルの側に同じ要素に当たる規則がない場合だけである。

### 0 に戻す値が CSS にない

ファイルの側で 0 の規則を書けば直る、とは言えない。
後のアキの規則が当たるのは、次の兄弟の要素（段落、見出し、図版、リスト）である。
後のアキが 0 のときの `margin-block-start` は、その要素の側の規則（見出しの余白、ブラウザーの `p` の 1em）で決まる。
ファイルの規則がその値を書くには、次の要素の種類ごとの余白を知る必要があり、`revert` は Golem の書いたほかの規則まで捨てる。
style.toml の規則を、そのファイルのページに当てないことでしか、0 に戻せない。

## 実装すること

### style.toml の空きの規則の範囲

style.toml の段落の前後のアキの規則のうち、セレクターに段落スタイル S を含むもの（S の前のアキ、S の後のアキ、S を含む組、`div.blank-line + p.ps-S`、`body` では `p` と `p:not([class])` の規則）は、S を `@style-def` で定義したファイルのページに当てない。
S を定義したファイルの番号が n₁、n₂、… なら、その規則のセレクターの前に `body:not(.file-n₁):not(.file-n₂)…` を付ける。
`:not()` の中は単純なセレクターなので、[ADR 0189](0189-paragraph-alignment-spacing-and-end-indent.md) と同じく Selectors Level 3 の範囲に収まる。
S を定義したファイルがなければ、規則は今のまま書く。
`@style-def` を使わない本の CSS は、バイト列が変わらない。

ファイルの規則は今のとおり、そのファイルの定義と style.toml の定義を合わせたスタイルで、空きの規則を書き直す。
ファイルのページに当たる空きの規則は、そのファイルの規則と、そのファイルが定義していないスタイルどうしの style.toml の規則だけになる。

`body.file-<n>` の class は、今のとおり、`@style-def` を持つファイルのページの `body` にだけ付ける（[`Html.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-html/src/Golem/Html.hs#L346)）。

### 文書

- 仕様書の「段落スタイル」の節：「style.toml の後のアキを、ファイルの定義で 0 に戻しても、style.toml の後のアキの規則は残る」を消し、上の範囲の規則を書く。
- [ADR 0189](0189-paragraph-alignment-spacing-and-end-indent.md) のステータスの行に、ファイルの定義で改めた空きの HTML の規則はこの ADR、と足す。

## 実装しないこと

- **空きを要素ごとに計算して書くこと**：HTML の書き手が隣り合うブロックから空きを計算し、要素の class か `style` 属性に書く案は採らない（「メンテナーが決めること」の 1）。
- **ブラウザーの既定の余白との違い**：空きが 0 の段落のあいだに、ブラウザーの `p` の 1em が残ることは変えない。[ADR 0189](0189-paragraph-alignment-spacing-and-end-indent.md) が、HTML では既定と見分けがつかないとして受け入れた違いである。
- **文字スタイルと、ほかの段落スタイルのキー**：行揃え、字下げ、`end-indent` は、ファイルの規則が `margin-block` などと同じく値を必ず書くので、0 に戻せる。この ADR は空きの規則だけを扱う。
- **PDF**：変えない。

## 不変条件

本の中の一つのファイル f のページで、文書の最上位に続いて並ぶ二つのブロック A と B を考える。
PDF の `gapLines` が A と B のあいだに置く行の数を g とする（f の段落スタイルで数える）。
「勝つ宣言」は、`style.css` の規則のうち、B に当たる `margin-block-start`（`margin-block` を含む）の宣言で、詳細度と順序で最後に勝つものである。

- **H1**：g > 0 なら、B の勝つ宣言の値は `<g>em` である。
- **H2**：g = 0 で、A と B のあいだに行アキがなければ、B の勝つ宣言は、同じ本から段落の前後のアキのキーをすべて除いたときの B の勝つ宣言と同じである（空きの規則がどれも B に勝たない）。ただし、A と B が同じスタイルの段落なら、`space-between` の規則を除く。
- **H3**：A と B のあいだに行アキがあり、B が f で前のアキを持つ段落なら、B の勝つ宣言の値は 0 である。
- **H4**：`@style-def` で段落スタイルを定義したファイルのない本では、`style.css` のバイト列がこの ADR の前と同じである。
- **H5**：PDF、`pages.json`、プレーンテキストのバイト列は、この ADR の前と同じである。
- **H6**：同じ入力からは、同じ `style.css` を書く。ファイルの番号の並びは、マニフェストの章の順で決まる。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| style.toml の A の後のアキ | 0、1、2 |
| style.toml の B の前のアキ | 0、1、3 |
| ファイルの定義 | 定義しない、空きのキーを書かない定義、0 に戻す、小さくする、同じ値、大きくする |
| 定義する側 | A だけ、B だけ、A と B の両方 |
| A と B の組 | 同じスタイル、別のスタイル、A が `body`、B が `body` |
| B の種類 | 段落、見出し、図版、リスト、表、コードブロック、行アキ |
| 定義するファイル | 一つ、二つのファイルが違う値で定義する、最初の章と最後の章 |
| `line-breaks` | `keep` の段落（`verse`）、ほかの段落 |
| ターゲット | HTML、EPUB |

## テスト設計

テストは実装の前に書き、今の実装で H1 から H3 の少なくとも「0 に戻す」と「組で 0 に戻す」の二つが失敗することを確かめる。

### CSS の勝つ宣言を選ぶテスト用の評価器

golem-html のテストに、Golem が書くセレクターの範囲（型、class、属性の有無、単純なセレクターの `:not()`、子孫、隣接の兄弟 `+`）だけを読む、小さな評価器を作る。
評価器は、要素の並び（`body` の class、兄弟の要素の名前と class）と `style.css` を受け取り、各要素の `margin-block-start` の勝つ宣言を、詳細度と出現の順で選ぶ。
範囲の外のセレクターに当たったら、テストを失敗させる（黙って読み飛ばさない）。
評価器そのものは、詳細度の計算と順序の規則を手で作った規則の組で確かめる。

### 不変条件のテスト

- 境界の入力の表の組を、各軸の値をすべて掛け合わせずに、各値が一度は現れる組み合わせで並べる。各組で、PDF の空きの行（`AlignSpaceSpec` の `slotsOf`）と、評価器が選ぶ HTML の勝つ宣言を比べ、H1 から H3 を確かめる。
- H4：`@style-def` のない今の HTML と EPUB のゴールデン（`OutputGoldenSpec`）が変わらないこと。
- 二つのファイルが違う値で同じスタイルを定義する本で、それぞれのページの勝つ宣言がそのファイルの値になること。
- 回帰：「文脈」の再現の本で、「本文。」の勝つ宣言がブラウザーの既定（評価器では Golem の空きの規則が当たらないこと）になること。

### 自動テストにしない確かめ方

再現の本と、組の規則を 0 に戻す本を HTML と EPUB で組み、ブラウザーで空きを目で確かめる。
結果はプルリクエストの説明に書く。

## トレードオフ

- style.toml の規則に `body:not(.file-n)` を付けるので、`@style-def` で空きを持つスタイルを定義するファイルが多い本では、セレクターが長くなる。定義するファイルの数だけ `:not()` が増える。
- 規則の詳細度が上がる。仕様書には、利用者が自分の CSS を `style.css` に足す機能がない（2026-11-08 に検索した）ので、詳細度の変化で壊れる使い方は見つかっていない。
- 空きの規則の組み立てが、どのファイルがどのスタイルを定義したかに依る。規則を作る関数の入力が増える。

## メンテナーが決めること

1. **直し方**：推奨は、style.toml の空きの規則を、そのスタイルを定義したファイルのページに当てないことである。CSS の側だけで直り、`@style-def` のない本の出力は変わらない。
   - 退けた案の一つは、ファイルの規則に 0 の空きも書くことである。後のアキの規則は次の要素に当たり、0 のときの余白は次の要素の種類で違うので、書く値が決まらない（「文脈」）。
   - 二つめは、HTML の書き手がブロックの並びから空きを計算し、要素ごとに class か `style` 属性で書くことである。セレクターの詳細度の問題はなくなるが、PDF の `gapLines` と同じ規則を golem-html にもう一つ書くことになり、`verse` を使うすべての本の HTML と EPUB が変わる。[ADR 0189](0189-paragraph-alignment-spacing-and-end-indent.md) が決めた CSS の形を改めることになり、この食い違いを直すのに要る範囲を超える。
   - 三つめは、食い違いを記録だけして残すことである。書き手が `@style-def` に書いた値を HTML と EPUB が黙って使わないことになり、黙って出力を変えないという原則に反する。
2. **組の規則も直すか**：推奨は、後のアキの規則と同じ ADR で、組の規則と行アキの後の規則も同じ範囲の規則で直すことである。原因は同じ（style.toml の規則がファイルの規則に勝つこと）で、一つの規則で直る。
   - 退けた案は、レビューが挙げた後のアキだけを直すことである。組の規則で同じ食い違いが残る（「原因」の 3em の例）。
3. **確かめ方**：推奨は、テスト用の小さな CSS の評価器で勝つ宣言を確かめることである。規則の文字列ではなく、どの宣言が勝つかを不変条件として書ける。
   - 退けた案の一つは、`style.css` の文字列を断言するテストだけにすることである。今の不具合は、規則の文字列が正しくても詳細度で負けることから来ており、文字列の断言では見つからない。
   - 二つめは、ヘッドレスのブラウザーで計算した値を読むことである。CI にブラウザーを足すことになり、版によって結果が変わりうる。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-08、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [ADR 0189](0189-paragraph-alignment-spacing-and-end-indent.md)、[docs/adr/0014](0014-in-file-settings.md)
- Selectors Level 3（W3C 勧告）、「Calculating a selector's specificity」：https://www.w3.org/TR/selectors-3/#specificity
- CSS Cascading and Inheritance Level 4、「Cascade Sorting Order」：https://www.w3.org/TR/css-cascade-4/#cascade-sort
