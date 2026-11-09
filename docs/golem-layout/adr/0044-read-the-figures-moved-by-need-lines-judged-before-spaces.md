# ADR 0044: 空きの前で判定した `@need-lines` が動かした図版を、述語が読む

ステータス: 採択

## 文脈

[golem-layout ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) は、`@need-lines` の前に置いた空き（`FSpace`）も判定の残りに数えないと決め、述語の `waitingFigures` は変えないとした。
改ページの変更はプルリクエスト #759（`e0ae4f18`）で main に入った。
ただし、[ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) のテスト設計の最後の項目（毎晩と同じ変数で、すべての入力のテストと抜き取りのテストが通ること）が成り立たないので、ステータスは採択（未実装）のままである。

### 毎晩の抜き取りが返す反例

2026-11-09 に、main の `223734cd` で、毎晩と同じ `GOLEM_ENUM_DEPTH=5`、`GOLEM_ENUM_PAGINATION_SAMPLES=5000000` で `cabal test golem-layout-test` を走らせた。
要素 5 個までのすべての入力のテストは通り、要素 6 個の抜き取りのテストは次の反例で P1 の違反を返した。

```haskell
paginateWithin maxBound 1 (ColumnSet 1 0 0 0) 6
  (enumFlows [EPara 2, EFigure 6, ESpace, ENeedLinesMore 5, EFigure 4, EHeading])
-- 1 ページ: SLine 0, SLine 1
-- 2 ページ: SFigure 1000
-- 3 ページ: SFigure 1001, SHeading 2 1
-- 記録: なし
```

改ページは、6 行の図版 1000 を残りの 4 行に置けずに送る。
空きを置いた後に `@need-lines 5` が来ると、[ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) のとおり、空きを置く前の残り 4 行で判定し、満たされないので次の段へ進む。
進んだ段には送った図版 1000 が置かれ、残りが 0 行なので、さらに次の段へ進む。
4 行の図版 1001 と見出しは、3 ページに置かれる。

述語は、空きの前で判定した `@need-lines` で流れが次の段へ進むことを、空きが `@need-lines` の後にあるときだけ読む（[`PaginateInvariants.hs`](https://github.com/tett23/golem/blob/223734cd52871a7903362f3b94e9ba8ea2dbec5c/modules/golem-layout/test/PaginateInvariants.hs#L450-L459)）。
この反例では空きが前にあるので、述語は流れが 1 ページにとどまり、図版 1000 がまだ置かれていないと読む。
すると図版 1001 は待つ図版になり（[golem-layout ADR 0033](0033-read-waiting-figures-from-the-placement.md) の W1）、`@need-lines 5` の次のブロックは見出しになる（[golem-layout ADR 0026](0026-need-lines-and-blank-lines-pass-over-waiting-figures.md)）。
見出しの前の残りは 2 行なので、P1 の違反になる。
空きと `@need-lines` を入れ替えた入力は同じ出力になり、述語は違反を返さない。

同じ食い違いは、二段の版面で P5 の違反としても現れる（実装者が見つけた反例。2026-11-09 に `cabal test` で確かめた）。

```haskell
paginateWithin maxBound 1 (ColumnSet 2 0 0 0) 8
  (enumFlows [EFigure 8, EFigure 1, ESpace, EBlank 2, ENeedLinesMore 7, EFigure 3])
-- 1 ページの一段め: SFigure 1000
-- 1 ページの二段め: SFigure 1001, SFigure 1002
-- 記録: なし
```

一段めは図版 1000 で埋まり、図版 1001 は送られる。
`@need-lines 7` は空きを置く前の残り 0 行で判定され、流れは二段めへ進み、送った図版 1001 がその段に置かれる。
図版 1002 は、二段めで図版 1001 の後に、前の行アキとともに置かれる。
述語は流れが一段めにとどまると読むので、図版 1002 を待つ図版と読む。
P5 は、待つ図版の前の行アキが一度捨てられたと記録されることを求めるので、違反になる。

### [ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) の前からある食い違い

プルリクエスト #759 の境界のテストは、もう一つの形で P5 を除いている（[`PaginateSpec.hs`](https://github.com/tett23/golem/blob/223734cd52871a7903362f3b94e9ba8ea2dbec5c/modules/golem-layout/test/PaginateSpec.hs#L1383-L1399)）。
最も小さい例は次の入力である。

```haskell
paginateInput (Input 6 1 [EPara 4, ENeedLines, ESpace, EFigure 2, EBlank 1, EFigure 1])
-- 1 ページ: SLine 0, SLine 1, SLine 2, SLine 3
-- 2 ページ: SFigure 1000, SFigure 1001
-- 記録: なし
```

`@need-lines 2` は空きの前の残り 2 行で満たされる。
空きを置いた後の残りは 1 行で、2 行の図版 1000 は入らない。
改ページは、[golem-layout ADR 0027](0027-need-lines-judged-again-after-spaces.md) のとおり、ブロックの最初の部分が空きの後の残りに入らないので、流れを次の段へ進め、その段で判定し直す（[`Paginate.hs`](https://github.com/tett23/golem/blob/223734cd52871a7903362f3b94e9ba8ea2dbec5c/modules/golem-layout/src/Golem/Layout/Paginate.hs#L245-L250)）。
図版 1000 は `@need-lines` に動かされて 2 ページの先頭に置かれ、行アキと図版 1001 が続く。

述語は、`@need-lines` が図版を動かしたかを、最後に置いた部分の後の残りが `@need-lines` に足りないかだけで量る（[`PaginateInvariants.hs`](https://github.com/tett23/golem/blob/223734cd52871a7903362f3b94e9ba8ea2dbec5c/modules/golem-layout/test/PaginateInvariants.hs#L471-L482)）。
残りは 2 行で足りているので、述語は図版 1000 を自ら送られた図版と読み、図版 1001 を待つ図版と読む。
P5 は行アキの捨てた記録を求めるので、違反になる。
この形は [ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) の前の main（`f821c96c`）でも同じ違反になり、[docs/roadmap.md](../../roadmap.md) の未決事項に載っている。

### 仕様書の文と述語

仕様書は、流れが来た段を「空きの前で判定した `@need-lines` で次の段へ進めば、その段である」と書く（[docs/specifications.md](../../specifications.md) の「改ページ」の節）。
この文は、空きが `@need-lines` の前にあるか後にあるかを限らない。
述語は、後にあるときだけを実装している。
これが一つめと二つめの反例の原因である。

仕様書は、自ら送られる図版を「直前の行アキと、残りに足りない `@need-lines` に動かされずに置かれた図版」とも書く。
空きの前で満たされ、空きの後の残りに入らずに動いた図版は、この文の「動かされた」に当たるかが書かれていない。
[ADR 0027](0027-need-lines-judged-again-after-spaces.md) の規則では、流れが段を移るので、図版は `@need-lines` に動かされている。
述語がこれを読まないことが、三つめの反例の原因である。

### 述語を直せば通ることの確認

述語だけを改め、次の二つを足した形を試した（コミットしていない）。

- 前のブロックの後の空きに続く `@need-lines` で、それまでの `@need-lines` の最も大きい値が最後に置いた部分の後の残りより大きければ、流れは次の段へ来る。空きの後の `@need-lines` について、今の述語が空きでしていることと同じである。
- `@need-lines` と空きの後の図版は、最後に置いた部分の後の残りから空きの行を引いた残りに入らなければ、`@need-lines` に動かされた図版とする。

結果は次のとおりである（2026-11-09、`223734cd` に上の変更を当てた作業ツリー）。

- golem-layout-test の 975 のテストが通る。三つの反例を足したテストと、境界のテストの P5 の除外を外したものを含む。除外を外すと、今の述語では境界のテストの 14 のケースが P5 の違反を返す。
- 毎晩と同じ変数で、要素 5 個までのすべての入力のテストと、要素 6 個の 500 万の抜き取りのテストが通る。`knownBugs` は空のままである。
- 「不変条件」の W3 を、すべての入力のテストと抜き取りのテストに足した形でも、毎晩と同じ変数で両方が通る。試した形は、空きの直後に `@need-lines` があるすべての入力で、入れ替えた入力の出力が同じなら `waitingFigures` の値を比べた。P9 が判定しない入力も含むので、W3 より広い。
- 今の述語に同じ W3 の検査を足すと、要素 5 個の `[EPara 2, EFigure 2, ESpace, ENeedLines, EFigure 1]`（段の行の数 3、一段）で値が `[1001]` と `[]` に分かれ、すべての入力のテストが失敗する。

改めた述語が改ページの不具合を見落とさないかも、同じ作業ツリーで確かめた。
改ページの修正を一つずつ戻し、毎晩と同じ変数でテストを走らせた（コミットしていない）。

| 戻した修正 | P9 | 述語 | すべての入力（要素 5 個まで） | 抜き取り（要素 6 個） |
| --- | --- | --- | --- | --- |
| [ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) | 調べる | 改めた述語 | P9 の違反 | P9 の違反 |
| [ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) | 外す | 改めた述語 | P1 の違反 | P1 の違反 |
| [ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) | 外す | 今の述語 | 通る | P5 の違反 |
| [ADR 0035](0035-a-larger-need-lines-after-a-judged-one-is-judged-again.md) | 調べる | 改めた述語 | P1 の違反 | P1 の違反 |
| [ADR 0035](0035-a-larger-need-lines-after-a-judged-one-is-judged-again.md) | 外す | 改めた述語 | P1 の違反 | P1 の違反 |
| [ADR 0035](0035-a-larger-need-lines-after-a-judged-one-is-judged-again.md) | 外す | 今の述語 | P1 の違反 | P1 の違反 |

[ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) の修正を戻し P9 を外すと、今の述語は要素 5 個までの入力で違反を見つけず、抜き取りで初めて見つける。
改めた述語は、空きの前の `@need-lines` で流れが進むと読むので、要素 5 個の `[EPara 2, EFigure 2, ESpace, ENeedLines, EFigure 1]`（段の行の数 3、一段）で P1 の違反を返す。
読みを広げても、この二つの不具合を見つける力は落ちない。

## 実装すること

### 1. 述語 `waitingFigures`

[golem-layout ADR 0033](0033-read-waiting-figures-from-the-placement.md) の読み方に、次の二つを足す。
どちらも、入力の流れと出力だけを読む（W2）。

1. **空きの前の `@need-lines` で進んだ段**：最後のブロックの後に空きがあり、改ページの印を挟まずに `@need-lines` が来たとき、それまでの `@need-lines` の最も大きい値を、最後に置いた部分の後の残り（注と区切りを数える。今の `leftAt`）と比べる。残りが少なければ、流れは次の段へ来る。その段より後に置かれていない保留の図版は、置かれたものとする。空きの後の `@need-lines` について今の述語がしていることを、空きの前の `@need-lines` にも広げる。
2. **空きの後の残りに入らない図版**：`@need-lines` と空きの後に、改ページの印を挟まずに書いた図版が、流れが来た段より後に置かれたとする。最後に置いた部分の後の残りから、そのあいだの空きの行を引いた残りが、図版の行の数より少なければ、図版は `@need-lines` に動かされた図版であり、自ら送られた図版ではない。

述語の注釈（`waitingFigures` の Haddock）にも、この二つを書く。

### 2. テスト

- 「文脈」の三つの反例を、`PaginateSpec` の [ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) のテストの群に、回帰のテストとして足す。
- 境界のテストの P5 の除外（`goesOnAfterSpaces` とその注釈）を外し、すべての不変条件を調べる。
- 「不変条件」の W3 を、すべての入力のテストと抜き取りのテストに足す（「メンテナーが決めること」の 2）。

### 3. 文書

- [docs/specifications.md](../../specifications.md) の「改ページ」の節の、流れが来た段の文を、空きが `@need-lines` の前にあっても後にあっても同じと読める形に改め、この ADR へのリンクを足す。
- 同じ節の、自ら送られる図版の文に、空きの前で満たされても空きの後の残りに入らない図版は `@need-lines` に動かされた図版であることを足す。
- [docs/roadmap.md](../../roadmap.md) の未決事項から、「空きの後の `@need-lines` と待つ図版の読み方」と「空きの後に入らずに段を移った図版の後の行アキ」の二つを取り除く。
- [golem-layout ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) のステータスを採択にする。毎晩と同じ変数のテストが通ることを、プルリクエストで確かめてからにする。
- [golem-layout ADR 0033](0033-read-waiting-figures-from-the-placement.md) のステータスの行に、空きの前で判定した `@need-lines` が動かした図版の読み方をこの ADR が足したことを書く。

## 実装しないこと

- **改ページを変えること**：三つの反例の出力は、[ADR 0027](0027-need-lines-judged-again-after-spaces.md) と [ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) の規則のとおりである。直すのは述語だけとする。
- **Alloy のモデルを変えること**：[docs/golem-layout/models/pagination.als](../models/pagination.als) の `waitingIn` は、モデルが選んだ配置（`p.kept`）から待つ図版を決め、出力から読み直さない。この ADR が直す読み方の食い違いは、モデルにはない。`nightly.txt` と `expected.txt` も変えない。
- **流れが二つ以上の段を進むことを述語が読むこと**：一つめの反例では、改ページは 2 ページを経て 3 ページへ進む。述語は、今の空きの後の `@need-lines` と同じく、次の段へ来たとだけ読む。後の図版は、来た段より後に置かれた自ら送られた図版と読まれ、違反にはならない。読みを細かくするのは、この近似が違反を返したときに別の ADR で決める。
- **空きの行を出力から読むこと**：空きは出力の枠に現れない。述語は、入力に書いた空きの行の数を引く。段の先頭で捨てられる空きも数えるので、近似である。
要素 5 個までのすべての入力と 500 万の抜き取りで、この近似が違反を生まないことを確かめた。

## 不変条件

C は段の行の数、N は `@need-lines` の行の数とする。
「最後に置いた部分の後の残り」は、今の述語の `leftAt` のとおり、前のブロックと書いた位置に置かれた図版の最後の部分の後の残りから、その段の注と区切りを引いたものとする。

- **W2 内部を読まない**：[golem-layout ADR 0033](0033-read-waiting-figures-from-the-placement.md) のとおり、`waitingFigures` は入力の流れと出力の `PageOut` だけを使う。この ADR の後も変わらない。
- **W3 空きの位置によらない読み方**：P9 が判定する入力（空きの直後に `@need-lines` があり、前のブロックと次のブロックのあいだに改ページの印、`@no-page-break`、`@page-lines` がない）で、空きと `@need-lines` を入れ替えた入力の出力が元の出力と同じなら、`waitingFigures` は二つの入力で同じ図版の並びを返す。
- **W4 空きの前の判定で進んだ段**：前のブロックの後に、空きと `@need-lines` がどの順で並んでも、最後に置いた部分の後の残りが N より少なければ、流れは次の段へ来る。その段までに置かれた保留の図版の後に書いた図版は、そのことだけでは待つ図版にならない。
- **W5 空きの後に入らずに動いた図版**：`@need-lines` が最後に置いた部分の後の残りで満たされ、その残りから空きの行を引いた残りに図版が入らず、図版が後の段に置かれたなら、その図版は自ら送られた図版ではない。後に書いた図版は、そのことだけでは待つ図版にならない。
- **全体**：I1 から I8、P1 から P5、P9 は、`knownBugs` が空で、境界のテストに除外がないまま、要素 5 個までのすべての入力と、要素 6 個の 500 万の抜き取りで成り立つ。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 空きの位置 | `@need-lines` の前、後、前と後の両方 |
| 最後に置いた部分の後の残り | N − 1、N、N + 空きの行の数 − 1、N + 空きの行の数 |
| 空きの後の図版 | 残りから空きを引いた行にちょうど入る、1 行あふれる、C 行 |
| 保留の図版 | なし、次の段に置かれる図版一つ、次の段を埋める図版一つ |
| 図版の後 | なし、行アキと図版、見出し |
| 段の数 | 1、2 |
| `@need-lines` の数 | 一つ、より大きい二つめ（[golem-layout ADR 0035](0035-a-larger-need-lines-after-a-judged-one-is-judged-again.md)） |

## テスト設計

テストを先に書き、今の述語で失敗することを確かめてから述語を改める。
テストの名前には、W3、W4、W5 と P1、P5 の番号を入れる。

- **W4、P1**：一つめの反例で、`waitingFigures` が空を返し、`breaches` が違反を返さないこと。今は `[1001]` と P1 を返すので失敗する（2026-11-09 に確かめた）。
- **W4、P5**：二つめの反例で、`waitingFigures` が空を返し、`breaches` が違反を返さないこと。今は `[1002]` と P5 を返すので失敗する（同日に確かめた）。
- **W5、P5**：三つめの反例で、`waitingFigures` が空を返し、`breaches` が違反を返さないこと。今は `[1001]` と P5 を返すので失敗する（同日に確かめた）。
- **境界のテスト**：[ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) の境界のテストから P5 の除外を外したもの。今は 14 のケースが P5 の違反を返すので失敗する（同日に確かめた）。
- **W3**：すべての入力のテストと抜き取りのテストで、P9 が入れ替えた入力を組み直したとき、出力が同じなら `waitingFigures` の値も同じことを確かめる。今の述語では、要素 5 個の `[EPara 2, EFigure 2, ESpace, ENeedLines, EFigure 1]`（段の行の数 3、一段）で値が分かれるので失敗する（同日に確かめた）。
- **W2**：自動のテストは書けない。足した分岐が入力の流れと `PageOut` のほかを読まないことを、レビューで確かめる。
- **全体**：毎晩と同じ `GOLEM_ENUM_DEPTH=5` と `GOLEM_ENUM_PAGINATION_SAMPLES=5000000` で、すべての入力のテストと抜き取りのテストが通ること。プルリクエストの説明に、走らせた時刻と結果を書く。
- **述語が不具合を見落とさないこと**：プルリクエストを作る前に、改ページの [golem-layout ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) と [golem-layout ADR 0035](0035-a-larger-need-lines-after-a-judged-one-is-judged-again.md) の修正を手元で一つずつ戻し、毎晩と同じ変数のテストが違反を返すことを確かめる。P9 を外した場合も確かめ、結果をプルリクエストの説明に書く。コミットはしない。

## トレードオフ

述語の読みを広げると、述語が許す出力も広がる。
W5 の読みは、空きの後の残りに入らない図版を動かされた図版とするので、改ページが誤って図版を後の段へ移しても、その図版の後の図版を待つ図版と読まなくなる。
この誤りは、P9、P1、[golem-layout ADR 0027](0027-need-lines-judged-again-after-spaces.md) のテストが別に捕まえる。
「文脈」の表のとおり、改ページの [ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) と [ADR 0035](0035-a-larger-need-lines-after-a-judged-one-is-judged-again.md) の修正を戻した版では、改めた述語でも違反を返す。

W5 の条件を、図版の行の数と空きの後の残りで量らず、`@need-lines` と空きの後にあるだけで動かされた図版とする形もある。
条件は短くなるが、空きの後の残りに入る図版を改ページが誤って移したときに、述語が自ら送られた図版の読みを通して捕まえる道がなくなる。
「メンテナーが決めること」の 1 で決める。

述語の分岐が一つ増え、空きの位置で同じ判定を二か所に書く。
二か所を一つの関数にまとめ、空きの前と後で同じ判定をしていることをコードの形で示す。

## メンテナーが決めること

1. **W5 の条件の細かさ**：推奨は、図版の行の数が空きの後の残りより多いときだけ動かされた図版とすることである。改ページの規則（[ADR 0027](0027-need-lines-judged-again-after-spaces.md) の「ブロックの最初の部分が空きの後の残りに入れば、その段に置く」）をそのまま写した形で、規則にない移り方を見逃さない。
   - 退けた案は、`@need-lines` と空きの後にある図版を、後の段に置かれればいつも動かされた図版とすることである。どちらも 975 のテストと毎晩の変数のテストを通すが、改ページの誤りを見逃す範囲が広がる。
2. **W3 をテストにするか**：推奨は、P9 の入れ替えのついでに、`waitingFigures` の値も比べることである。今回の食い違いは、空きの位置で述語の読みが分かれたことそのものであり、W3 なら要素 6 個の抜き取りを待たずに要素 5 個までの列挙で見つかる。
   - 退けた案は、三つの反例の回帰のテストだけにすることである。同じ形の読みの分かれが、行アキや改ページの印との組で起きたときに、また抜き取りに頼ることになる。
3. **[ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) を採択にする時**：推奨は、この ADR を実装するプルリクエストで、毎晩と同じ変数のテストが通ったことを確かめてから、[ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) のステータスを採択にすることである。
   - 退けた案は、[ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) をすぐに採択にし、この ADR を別の課題とすることである。[ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) のテスト設計の項目が満たされないまま採択になり、毎晩の失敗も残る。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-09、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [golem-layout ADR 0025](0025-need-lines-and-blank-lines-after-figures-sent-on.md)、[golem-layout ADR 0026](0026-need-lines-and-blank-lines-pass-over-waiting-figures.md)、[golem-layout ADR 0027](0027-need-lines-judged-again-after-spaces.md)、[golem-layout ADR 0033](0033-read-waiting-figures-from-the-placement.md)、[golem-layout ADR 0035](0035-a-larger-need-lines-after-a-judged-one-is-judged-again.md)、[golem-layout ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md)
- [docs/adr/0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md)、[docs/adr/0208](../../adr/0208-widen-lightweight-formal-methods.md)
- [docs/specifications.md](../../specifications.md) の「改ページの手での制御」と「改ページ」の節
- [docs/roadmap.md](../../roadmap.md) の未決事項の「空きの後の `@need-lines` と待つ図版の読み方」と「空きの後に入らずに段を移った図版の後の行アキ」
- プルリクエスト #759（`e0ae4f18`）
