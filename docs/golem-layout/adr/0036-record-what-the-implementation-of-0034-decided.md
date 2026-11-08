# ADR 0036: [golem-layout ADR 0034](0034-line-breaks-between-japanese-characters-in-inline-code.md) の実装が決めた点を記録する

ステータス: 採択（未実装）

## 文脈

[golem-layout ADR 0034](0034-line-breaks-between-japanese-characters-in-inline-code.md) は、本文の中のコードの和文の字のあいだと、和文と欧文の字の境で改行できるようにし、改行した位置に印（`wrap-mark`）を描くと決めた。
その実装（[#713](https://github.com/tett23/golem/pull/713)、マージのコミット `c638870f`）は、ADR に書かれていない規則を一つ足し、ADR の文の二点を ADR のとおりには読まなかった。
既定の印の字も、ADR の定めた手順で変えた。
どれもマージ済みで、仕様書かプルリクエストの説明に書かれているが、決めた ADR がない。

[docs/adr/0205](../../adr/0205-rules-added-by-the-implementation-of-adr-0180.md) と [docs/adr/0211](../../adr/0211-record-what-implementations-decided-found-by-the-review-of-2026-11-08.md) と同じく、この ADR は、それらを決めたこととして記録する。
決めた ADR がないまま残すと、注釈と仕様書から出どころをたどれず、規則を変える ADR を書くときに見落とす。
コードとテストの参照は、マージのコミット `c638870f` で確かめた。

### Knuth と Plass の方式：幅のある罰点で行があふれても、活きている節点を捨てない

Golem の行分割は、TeX と同じく、行の始まりの候補（活きている節点）を持ちながら項目を前から読む。
ある候補 b で、節点 a から b までの行が縮めても行長に入らなければ、TeX はその節点を捨てる（tex.web の §851 と §854）。
b より後ろの候補で終わる行は、b までの行より長くなるので、もう使えないという考えである。

TeX は、この判定の行の幅に、分割の位置の幅を含める。
和文の改行の印は、その候補で改行したときだけ行末に描くので、実装は印を候補の罰点の幅とした（`Penalty w p (WrapMark m)`、[`Japanese.hs`](https://github.com/tett23/golem/blob/c638870fb9f5fb8a66d13308fef727a7e202de19/modules/golem-layout/src/Golem/Layout/Japanese.hs#L1272-L1274)）。
TeX の離散の項目（discretionary）の前の部分の幅と同じ扱いである（tex.web の §869 は、前の部分の幅を足してから判定する）。

ところが、印の幅（1 em）は、その候補から次の候補までの字の幅より広いことがある。
b の印の幅で行があふれても、b の後ろの候補で終わる行は印の幅を持たず、収まることがある。
その節点を捨てると、収まる分割を見落とす。

0034 の 5 で足したコードの並びの列挙（[docs/adr/0209](../../adr/0209-line-breaking-invariants-by-exhaustive-small-inputs.md) の L7）が、これを見つけた。
最も小さい例は、`[lang en]` の区間の `[code: 漢/…]` を 2 字の行で組むものである。
列挙の送りでは、`漢` が 1 em、`/` と欧文の区間の `…` が 1/2 em、印の `⏎` が 1 em である。
`漢/…` はちょうど 2 em であり、一行に収まる（罰点 100）。
`/` の後の候補で改行すると、行は `漢/` と印で 2.5 em になり、あふれる。
TeX の規則では、ここで段落の始まりの節点を捨てるので、段落の終わりまでの一行を評価できず、`漢⏎` と `/…` の二行（罰点 200）になる。

2026-11-08 に、origin/main（`ec295f03`）の `alive` の式を TeX の規則（`not overfull`）に戻して確かめた。

| 列挙 | 結果 |
| --- | --- |
| 23 の部品、段 2 | 通る |
| コードの並び、段 2（プルリクエストの段） | 通る |
| コードの並び、段 3（`GOLEM_ENUM_LINES_DEPTH=3`） | L7 の違反。「pass 1: the demerits are 200, the least of every way is 100」、入力は上の例 |

### 実装が変えたこと

実装は、`evaluate` の返す値に、行が節点を活かしておくか（`alive`）を、行が収まるか（`fits`）と別に足した（[`KnuthPlass.hs`](https://github.com/tett23/golem/blob/c638870fb9f5fb8a66d13308fef727a7e202de19/modules/golem-layout/src/Golem/Layout/KnuthPlass.hs#L416-L421)）。

```haskell
alive = negate (shortfall + penW) <= shrink
```

`shortfall` は行長から自然な幅を引いた量であり、自然な幅は b の罰点の幅 `penW` を含む。
`alive` は、b の罰点の幅を除いた行が縮めて行長に入るかである。
`step` は、強制の改行でない b で、`alive` が真の節点を残す（[`KnuthPlass.hs`](https://github.com/tett23/golem/blob/c638870fb9f5fb8a66d13308fef727a7e202de19/modules/golem-layout/src/Golem/Layout/KnuthPlass.hs#L328-L347)）。
b で行を終えてよいか（feasible）は、今のとおり罰点の幅を含めて判定する。
印の幅で行長を超える行を、その候補で終えることはない。

罰点が幅を持つ候補は、印のほかに、パターンの分綴のハイフン（`-` の送りの幅、[`Japanese.hs`](https://github.com/tett23/golem/blob/c638870fb9f5fb8a66d13308fef727a7e202de19/modules/golem-layout/src/Golem/Layout/Japanese.hs#L1078)）がある。
新しい規則は、こちらにも当たる。
罰点の幅が 0 のとき、`alive` は今までの `not overfull` と同じ値になる。
幅のある罰点を持たない段落の分割は、変わらない。

ハイフンで差が出るのは、ハイフンの幅が、その候補から次の候補までの字の幅より広いときである。
パターンの分綴は、分けた後の部分に 3 字以上を残すので（[docs/adr/0209](../../adr/0209-line-breaking-invariants-by-exhaustive-small-inputs.md) の L9）、ふつうの書体では起こりにくい。
#713 の説明は、23 の部品の列挙（手元で段 3 まで）、マニュアルのほかの `scripts/visual` の入力、`scripts/determinism/hashes.txt` が変わらなかったと書く。

あわせて、`itemFlagged`（続くハイフンの罰点を数える印）が、改行の印の候補を数えないようにした（[`KnuthPlass.hs`](https://github.com/tett23/golem/blob/c638870fb9f5fb8a66d13308fef727a7e202de19/modules/golem-layout/src/Golem/Layout/KnuthPlass.hs#L140-L149)）。
これは 0034 の C6（コードの候補で分けた行の終わりにハイフンを描かない）から従うので、この ADR では記録だけをする。

仕様書の「行分割」の節は、この規則と、TeX がこの場合にも節点を捨てることを書いている。
出どころは 0034 へのリンクである。

### 0034 の文の二点

実装は、0034 の次の二つの文を、ADR のとおりには読まなかった（#713 の説明の「Points for the maintainer」の 3）。

一つめは、「トレードオフ」の節の最後の段落である。
この段落は、「コードの中の改行の位置に印を描かないので」、空白で分かれたのか字のあいだで分かれたのかが紙面から分からない、と書く。
これは「メンテナーが決めること」の 8 を決める前の推奨（既定では印を描かない）を前提にした文である。
メンテナーは、既定で印を描くと決め（「決めたことの記録」）、規則は「実装すること」の 8 に書かれた。
実装は「実装すること」の 8 に従い、既定で印を描く。
この段落は、決めた後の規則と食い違う。

二つめは、「テスト設計」の C2 の「`[code: a_あ]` は今は候補がないので失敗する」である。
0034 の前のコード（マージの一つめの親 `56bc7534`）では、`a_あ` は `a_` と `あ` の二つの箱になる（[`codeItems`](https://github.com/tett23/golem/blob/56bc75348f9b39f9eb6a35ae336a82c0549338fc/modules/golem-layout/src/Golem/Layout/Japanese.hs#L960-L982)）。
`_` の連なりが一つだけなので、[golem-layout ADR 0031](0031-line-breaks-after-low-lines-in-identifiers.md) の除外で、`_` の後で箱を分けないためである。
[`normalize`](https://github.com/tett23/golem/blob/56bc75348f9b39f9eb6a35ae336a82c0549338fc/modules/golem-layout/src/Golem/Layout/Japanese.hs#L1227-L1229) は、`_` で終わり、`_` でない字を含む箱の後に、罰点 100 の候補を置く。
0034 の前から、`a_` の後には罰点 100 の候補が一つあった。
C2 のテストは、候補が一つで罰点が 100 であることを確かめるので、前と後のどちらでも通り、先に失敗させられない。
テストの期待する値は、0034 の C2 のとおりである。

### 既定の印の字

0034 の「実装すること」の 8 は、既定を `"↩"`（U+21A9）とし、二つのマニュアルのコードの書体がその字形を持たなければ、字形のある別の印を既定にして、その字と理由を 0034 のステータスの行に足すと定めた。
実装は、Noto Sans JP と Source Code Pro の cmap を調べ、どちらも U+21A9 を持たないことを確かめた。
`↩` は和文の字のクラスに入り、Noto Sans JP で描かれる。
実装は、Noto Sans JP が持ち、同じく改行を表す `"⏎"`（U+23CE）を既定にし、0034 のステータスの行に書いた。
仕様書の文字スタイルの表と `wrap-mark` の段落も、`⏎` を既定とする。
0034 の手順のとおりであり、新しい選択は字の選び方だけである。

## 実装すること

ここに記録した規則は、どれも main に入っている（`c638870f` で確かめた）。
この ADR の実装は、次のことだけである。

### ステータスの行

[golem-layout ADR 0034](0034-line-breaks-between-japanese-characters-in-inline-code.md) のステータスの行の終わりに、`→改行の印の幅で行があふれる候補の活きている節点、トレードオフの節の印の文、C2 の a_あ の文は [golem-layout ADR 0036](0036-record-what-the-implementation-of-0034-decided.md)` を足す。
今の行の括弧の中の既定の印の文は、そのまま残す。

### 仕様書

- 「行分割」の節の、幅のある罰点の候補で節点を残す文の出どころのリンクを、0034 からこの ADR に改める。列挙が見つけたことの括弧書きは、そのまま残す。
- 文字スタイル `code` の `wrap-mark` の既定の文（`⏎` を既定にした理由）に、この ADR へのリンクを足す。

### コードとテストの注釈

- `Golem.Layout.KnuthPlass` の `evaluate` の `alive` の注釈と、`step` の `survivors` の注釈の出どころを、この ADR にする。
- 足すテスト（「テスト設計」）の名前に、この ADR と N1 から N3 の番号を入れる。

## 実装しないこと

- **規則の振る舞いを変えること**：記録だけを行う。
- **0034 の文を書き換えること**：コミット済みの ADR は、ステータスの行のほかは変えない。食い違いは、この ADR とステータスの行で示す。
- **パターンの分綴のハイフンだけ TeX の規則に戻すこと**：「メンテナーが決めること」の 1 の退けた案。
- **活きている節点をさらに残すこと**：字幅の伸縮と突き出しが、行の端の箱で自然な幅を変えるので、b より後ろの行が b の行より短くなることは、罰点の幅のほかにもありうる。列挙は、字幅の伸縮と突き出しを使う入力で L7 を調べていない（[docs/adr/0209](../../adr/0209-line-breaking-invariants-by-exhaustive-small-inputs.md) の「実装しないこと」）。見つかれば、別の ADR で扱う。

## 不変条件

「活きている節点」は、行の始まりの候補として `breakParagraph` が持つ節点とする。
b の「罰点の幅」は、b が罰点なら `itemWidth`、そうでなければ 0 とする。

- **N1**：どの行も、行末の候補の罰点の幅を含めて行長に収まるか、`lineOverfull` が真である（行を終えてよいかの判定は、この ADR の前と同じである）。印を描いた行は、印の幅を含めて行長に収まる（0034 の C8）。
- **N2**：`brPass` が 1 か 2 で、[docs/adr/0209](../../adr/0209-line-breaking-invariants-by-exhaustive-small-inputs.md) の 3 の条件に当たる入力では、`brDemerits` が素朴な探索の最小に等しい（L7）。コードの並びの入力も含む。
- **N3**：どの罰点も幅を持たない項目の並びでは、`breakParagraph` の結果は、節点を `not overfull` で残す規則の結果と同じである。

N3 は、罰点の幅が 0 なら `alive` の式が `not overfull` に等しいことから従う。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 罰点の幅と、次の候補までの字の幅 | 罰点の幅のほうが狭い、等しい、広い |
| 罰点の幅を除いた行の残り | 正、0（ちょうど収まる）、負（除いてもあふれる） |
| 罰点の種類 | 改行の印、パターンの分綴のハイフン、幅のない罰点 |
| 次の候補 | 同じ種類の罰点、空白のグルー、段落の終わり |

## テスト設計

今のテストが、各不変条件の一部を確かめている。

- N1：列挙の L5 と C8。golem-layout の `CodeJapaneseSpec` の「C8: with the wrap mark, every line but the last of broken Japanese code ends with the mark, and fits」。
- N2：コードの並びの列挙の L7。ただし、上の例は部品 3 個なので、毎晩の `enum.yml`（段 3）でだけ見つかる。プルリクエストの段 2 では、規則を TeX のものに戻しても通る（「文脈」の表）。

この ADR では、プルリクエストの CI で規則を固定するテストを足す。
テストの名前には、N1 から N3 の番号を入れる。

- **N2**：`LineBreakInvariantsSpec` の回帰のテストに、`[lang en]` の区間の `[code: 漢/…]` を 2 字の行で組み、行が `漢/…` の一行で、`brDemerits` が素朴な探索の最小と等しいことを足す。
- **N1、N2**：`LineBreakingSpec` で、項目を手で並べる。1 em の箱、幅 1 em で罰点 0 の罰点、1/2 em の箱、幅 1 em で罰点 0 の罰点、1/2 em の箱、段落の終わりを 2 em の行で分け、行が一つであること。罰点の幅を 1/4 em にした並びでも行が一つであること。二つめの罰点の後の箱を 1 em にした並び（除いてもあふれる）では、行が二つで、一つめの行が罰点の幅を含めて収まること。
- **N3**：二つの罰点の幅を 0 にした同じ並びで、結果が節点を `not overfull` で残すときと同じ（行が一つ）であること。

どれも今の実装で通る見込みで、先に失敗させることはできない。
今の振る舞いを固定するテストである。
N2 の二つのテストは、`alive` の式を `not overfull` に戻すと失敗することを、実装のプルリクエストで確かめ、説明に書く。

## トレードオフ

実装の後で ADR を書くので、規則を決める前に代わりの案を比べていない。

TeX との違いは、節点を捨てる時期である。
TeX は、分割の位置の幅を含めて行があふれた時点で捨てる。
Golem は、その幅を除いてもあふれる時点まで待つ。
活きている節点が増えるぶん、行分割の手間は増える。
罰点の幅は高々 1 em で、節点が残るのは、幅を除けば収まる候補のあいだだけなので、増え方は小さいと見込むが、測ってはいない。

TeX も、離散の項目の前の部分の幅で同じ判定をするので、前の部分が次の候補までの字より広ければ、同じ見落としが起こりうる。
TeX でこれが実際に起きるかは、確かめていない。
TeX の離散の項目の前の部分は、ふつうハイフン一字であり、Golem の印（1 em）より狭い。

規則は、幅のあるすべての罰点に当たる。
パターンの分綴のハイフンの段落も、列挙と見た目の参照では変わらなかったが、変わりうる。
規則は節点を多く残すだけなので、変わるのは TeX の規則で分割を見落としていた段落だけと見込む。
ただし、節点が増えると、どの段階で分割が見つかるかも変わりうるので、罰点の和が段落ごとに減るとまでは言えない。

## メンテナーが決めること

1. **この規則を採るか**：推奨は、このまま採ることである。改行の印の幅を候補の罰点の幅にする限り、TeX の規則は収まる一行の分割を見落とし、L7 が成り立たない。新しい規則は、幅のない罰点では TeX と同じであり、行を終えてよいかの判定も変えない。
   - 退けた案の一つは、TeX の規則に戻し、L7 の違反を「既知の不具合」にすることである。印のある本で、収まる行を余分な行に分ける。
   - 二つめは、改行の印だけにこの規則を当て、パターンの分綴のハイフンは TeX の規則に戻すことである。同じ判定に二つの規則が並ぶ。ハイフンでも、TeX の規則は同じ見落としをしうる。
   - 三つめは、印の幅を罰点の幅に含めないことである。印を描いた行が行長を超え、0034 の C8 が成り立たない。
2. **0034 の文の二点をどう扱うか**：推奨は、この ADR に記録し、0034 のステータスの行からこの ADR へ導くことである。コミット済みの ADR の文は変えられない（adr-guard）。
   - 退けた案は、0034 を破棄して書き直すことである。0034 の規則は実装されたとおりであり、食い違うのは二つの文だけである。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-08、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- Donald E. Knuth. TeX: The Program. Addison-Wesley, 1986.（§851、§854 の節点を捨てる判定、§869 の離散の項目の前の部分の幅）。tex.web（`This is TeX, Version 3.141592653`）を CTAN から取得して確かめた。https://mirrors.ctan.org/systems/knuth/dist/tex/tex.web 。参照日 2026-11-08
- Donald E. Knuth and Michael F. Plass. Breaking Paragraphs into Lines. Software: Practice and Experience 11(11), 1981.
- [#713](https://github.com/tett23/golem/pull/713) の説明（「What changes」の Knuth-Plass、「Points for the maintainer」の 3）
- [docs/adr/0205](../../adr/0205-rules-added-by-the-implementation-of-adr-0180.md)、[docs/adr/0209](../../adr/0209-line-breaking-invariants-by-exhaustive-small-inputs.md)、[docs/adr/0211](../../adr/0211-record-what-implementations-decided-found-by-the-review-of-2026-11-08.md)
- [golem-layout ADR 0031](0031-line-breaks-after-low-lines-in-identifiers.md)、[golem-layout ADR 0034](0034-line-breaks-between-japanese-characters-in-inline-code.md)
