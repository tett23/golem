# ADR 0047: 空きと `@need-lines` のあいだに待つ図版があっても、空きを判定の残りに数えない

ステータス: 採択（未実装）

## 文脈

[golem-layout ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) は、`@need-lines` の前に置いた空き（`FSpace`）も判定の残りに数えないと決めた。
「実装すること」の 1 は、実装の形として「状態に、前のブロックの後に置いた空きの行の数を持たせる。ブロックを置けば 0 に戻す」と書いた。
不変条件 P9 は、「前のブロックと `@need-lines` のあいだの空き」を `@need-lines` の後へ移しても出力が変わらないことを求めるが、その判定の対象を「空きの直後に `@need-lines` がある入力」に限った。

2026-11-09 の監査で、実装（[#759](https://github.com/tett23/golem/pull/759)）がこの形より広く空きを忘れることが分かった。
改ページは、制御でない要素を一つ処理するたびに、置いたか置かなかったかにかかわらず、空きの記録 `sSpaces` を空にする（[`Paginate.hs` の 174 行から 175 行](https://github.com/tett23/golem/blob/81e1d1870965141ed297c408790270dd3e006897/modules/golem-layout/src/Golem/Layout/Paginate.hs#L174-L175)。注釈は「the spaces before a need-lines are those after the last block, placed or not」）。
待つ図版（[golem-layout ADR 0026](0026-need-lines-and-blank-lines-pass-over-waiting-figures.md)）は、前の図版が送られているあいだは何も置かずに待ちの列に入るが、この要素も空きの記録を消す。
空きと `@need-lines` のあいだに待つ図版があると、`@need-lines` は空きを数えた位置で判定される。

### 確かめた出力

2026-11-09 に、origin/main（`81e1d187`）の golem-layout のテストに一時のテストを足し、段の行の数 3、一段の版面で `paginateInput` を走らせた（コミットしていない）。
図版 1000 は 3 行、図版 1001 は 1 行、`@need-lines` は 2 行である。

| 流れ | 出力 |
| --- | --- |
| `[EPara 1, EFigure 3, ESpace, EFigure 1, ENeedLines, EPara 1]` | 1 ページ：行 0。2 ページ：図版 1000。3 ページ：図版 1001、行 1 |
| `[EPara 1, EFigure 3, EFigure 1, ESpace, ENeedLines, EPara 1]` | 1 ページ：行 0、空き、行 1（格子の 2 行め）。2 ページ：図版 1000。3 ページ：図版 1001 |
| `[EPara 1, EFigure 3, ESpace, ENeedLines, EFigure 1, EPara 1]` | 同上 |
| `[EPara 1, EFigure 3, ENeedLines, ESpace, EFigure 1, EPara 1]` | 同上 |
| `[EPara 1, EFigure 3, ESpace, ENeedLines, EPara 1]` | 1 ページ：行 0、空き、行 1。2 ページ：図版 1000 |

一行めだけが違う。
空きの後に待つ図版（図版 1001）が来て空きの記録が消え、`@need-lines 2` は空きを置いた後の残り 1 行で判定されて満たされず、流れは次の段へ進む。
次の段には送った図版 1000 が置かれ、その次の段に図版 1001 と段落が置かれる。
待つ図版の位置を一つ前か後ろへ動かすだけで、段落は 1 ページの 2 行めに戻る。
述語はどの入力にも違反を返さない。
`waitingFigures` も、待つ図版の前の空きの記録を捨てる（[`PaginateInvariants.hs` の 515 行](https://github.com/tett23/golem/blob/81e1d1870965141ed297c408790270dd3e006897/modules/golem-layout/test/PaginateInvariants.hs#L515)）ので、述語と改ページは一致している。
P9 は空きの直後に `@need-lines` がある入力しか入れ替えないので、この形を調べない。

### どの ADR も決めていない

[ADR 0026](0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) は、待つ図版が前の `@need-lines` と行アキの「次のブロック」にならないと決めた。
待つ図版が、`@need-lines` から見て「前のブロック」になるか、つまり前の空きの記録を区切るかは、決めていない。
[ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) の「ブロックを置けば 0 に戻す」を文字どおりに読むと、何も置かない待つ図版は記録を消さない。
実装の注釈は「placed or not」と書き、ADR と違う読みをしているが、プルリクエストの説明にも ADR にも、そう決めた理由は書かれていない。
仕様書の「改ページの手での制御」の文（「`@need-lines` の前に置いた空きも数えない」）は、待つ図版について何も言わない。

## 実装すること

「メンテナーが決めること」の 1 から 3 を推奨のとおりとした場合を書く。

### 1. 待つ図版は空きの記録を消さない

改ページは、待つ図版（`waitsBehind` が真で何も置かない `FFigure`）と、書いた位置のページに置けずにためる `FPageFigure` を処理しても、`sSpaces` を保つ。
空きの記録を消すのは、段に何かを置いたブロック（段落の行、置いた図版、見出し、表、コードブロック）を処理したときだけとする。
自ら送られる図版（前に送られた図版がなく、この段に入らずに次の段へ送る図版）は、この段に何も置かないが、記録を消す（「メンテナーが決めること」の 3）。
`@need-lines` は、[ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) のとおり、空きを置く前の位置で判定する。

例外が一つある。
待つ図版の前に改ページの印がたまっていれば、待つ図版でも記録を消す。
空きは前の改ページの印を適用してから置くので、たまった印は、空きの後、待つ図版の前に書いたものである。
待つ図版はその印を適用し、流れは次の段かページへ進む。
記録した空きは、流れが離れた段にある。
記録を保つと、後の `@need-lines` は、進んだ先の段の残りから、その段にない空きの行を引いて判定する。
次の段へ進めば、空きをその段に置き直しもする。
今の改ページも、`@need-lines` の前に改ページの印がたまっていれば、空きの前で判定しない（[`Paginate.hs` の 197 行から 200 行の `needAfterSpaces`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-layout/src/Golem/Layout/Paginate.hs#L197-L200)）。
この例外は、待つ図版が印を先に適用する場合を、それと同じに扱う。
改ページの印は P9′ と P11 の対象の外なので、この例外は例のテストで確かめる。

### 2. 述語

`waitingFigures` は、待つ図版で `before` を捨てる分岐を、空きの記録を保つ形に改める。
入力の流れと出力だけを読むこと（[ADR 0033](0033-read-waiting-figures-from-the-placement.md) の W2）は変えない。

P11 は、P9′ とは別の述語として足す。
P11 は、P9′ と P9 から従う。
空き、待つ図版、`@need-lines` の順の入力を A、待つ図版を空きの前に書いた入力を B とする。
A に P9′ を当てると、A と、空きを `@need-lines` の直後へ移した A′ は、出力が同じになる。
B に P9 を当てると、B と、空きと `@need-lines` を入れ替えた B′ は、出力が同じになる。
A′ と B′ は同じ流れなので、A と B の出力は、図版の置かれ方まで含めて同じになる。
B は A と同じ要素を並べ替えた入力なので、すべての入力のテストでは、同じ深さで A とともに組まれる。
B の改ページの印などを調べる範囲は A の範囲に含まれるので、A を P9′ が判定すれば、B も P9 が判定する。
それでも別の述語とするのは、抜き取りのテストが A と B を組にして引かないからである。
P11 の違反は、待つ図版が空きの記録を区切ったことを、名前で示しもする。

### 3. P9 を広げる

P9 の判定の対象を、「前のブロックと `@need-lines` のあいだに空きがあり、あいだに改ページの印、`@no-page-break`、`@page-lines` がない入力」とし、空きと `@need-lines` のあいだに待つ図版があってもよいことにする。
入れ替えは、空きを `@need-lines` の直後へ移す。
空きと `@need-lines` のあいだの図版が待つ図版かは、`waitingFigures` で読む。

[ADR 0044](0044-read-the-figures-moved-by-need-lines-judged-before-spaces.md) の W3 は、P9 と同じ関数（`spacesMoved`）で入れ替えた入力を作る。
P9 を P9′ に広げると、W3 の対象も、空きと `@need-lines` のあいだに待つ図版がある入力へ広がる。
W3 の述語の文は変えない。

### 4. 文書

- 仕様書の「改ページの手での制御」の `@need-lines` の文に、空きと `@need-lines` のあいだに待つ図版があっても空きを数えないことと、この ADR へのリンクを足す。
- [ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) のステータスの行に、待つ図版を挟む空きの扱いをこの ADR が決めたことを書く。
- 出力が変わる本があれば、変わったページを目で確かめてから、`scripts/determinism/hashes.txt`、golden、見た目の回帰テストの参照を改める。

## 実装しないこと

- **述語を改ページに合わせること**：「メンテナーが決めること」の 1 の退けた案。
- **待つ図版が `@need-lines` の次のブロックになること**：[ADR 0026](0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) のままとする。
- **改ページの印の後の空き**：[ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) のままとする。

## 不変条件

C は段の行の数とする。

- **P9′ 待つ図版を挟んでも空きの位置によらない**：前のブロックと `@need-lines` のあいだの空きを、あいだの待つ図版を飛ばして `@need-lines` の直後へ移した入力は、すべてのページの枠（`poSlots`）と記録（`poUnmet`）が元の入力と同じになる。あいだに改ページの印、`@no-page-break`、`@page-lines` がない入力に限る。P9 はこの特別な場合（待つ図版がない）である。
- **P11 待つ図版は空きを区切らない**：空きの後に待つ図版だけを挟んで `@need-lines` が来る入力の出力は、待つ図版を空きの前に書いた入力の出力と、待つ図版の置かれ方を除いて同じである。P9′ と同じく、あいだに改ページの印、`@no-page-break`、`@page-lines` がない入力に限る。すべての入力の上では P9′ と P9 から従うが、別の述語として確かめる（「実装すること」の 2）。
- **P1 から P5、P9、P10、W3**：この ADR の後も、要素 5 個までのすべての入力と要素 6 個の抜き取りで成り立つ。W3 は、P9′ が入れ替える入力にも当てる（「実装すること」の 3）。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 空きと `@need-lines` のあいだの待つ図版の数 | 0、1、2 |
| 待つ図版の行の数 | 1、C |
| 空きの数 | 1、2 |
| 空きの前の残り | N − 1、N、N + 空きの数 − 1、N + 空きの数 |
| 次のブロック | 1 行の段落、図版 |
| 段の数 | 1、2 |
| 空きと待つ図版のあいだの改ページの印 | なし、1（記録を消す。「実装すること」の 1 の例外） |
| 空きと `@need-lines` のあいだの図版の種類 | 待つ図版（記録を保つ）、自ら送られる図版（記録を消す。「メンテナーが決めること」の 3） |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
テストの名前には、P9′、P11 の番号を入れる。

- **P11**：「確かめた出力」の表の一行めで、二つめの段落が 1 ページの 2 行めに置かれること。今は 3 ページに置かれるので失敗する。
- **P9′**：`PaginateInvariantsSpec` の P9 の述語を広げ、プルリクエストの深さ（3）と毎晩の深さ（5）で走らせる。今は表の一行めの形（要素 6 個）で失敗するので、要素 6 個の例を回帰のテストとして `PaginateSpec` にも足す。
- 境界の表の各行の例のテストを `PaginateSpec` に足す。改ページの印と自ら送られる図版の二行は、P9′ と P11 の対象の外なので、述語でなく例で確かめる。
  - 改ページの印：空き、改ページの印、待つ図版、`@need-lines`、ブロックの順の入力で、`@need-lines` が、進んだ先の段の、送った図版を置いた後の残りで判定されること。前の段の空きの行は引かれない。
  - 自ら送られる図版：空き、自ら送られる図版、`@need-lines`、ブロックの順の入力で、出力が今の改ページと変わらないこと。
- 毎晩と同じ `GOLEM_ENUM_DEPTH=5` と `GOLEM_ENUM_PAGINATION_SAMPLES=5000000` で、すべての入力のテストと抜き取りのテストが通ること。

## トレードオフ

待つ図版を挟んでも空きを数えないと、[ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) のトレードオフと同じく、見た目の上で N 行が空かないブロックが置かれることがある。
その代わり、図版が待っているかどうか（書き手が原稿から予想しにくい状態）で `@need-lines` の結果が変わらなくなる。

改ページの状態の消し方が一つ変わり、出力が変わる本が出る可能性がある。
変わるのは、図版が送られているあいだに、空き、別の図版、`@need-lines`、ブロックの順に書いた原稿だけである。

述語に合わせる案なら、どちらも起きないが、[ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) が消した「空きの出どころで結果が分かれる」形が、待つ図版を挟むときだけ残る。

## メンテナーが決めること

1. **どちらに合わせるか**：推奨は、改ページと述語の両方を改め、待つ図版が空きの記録を消さないことである。[ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) の「ブロックを置けば 0 に戻す」の文のとおりになり、[ADR 0026](0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) の、待つ図版は `@need-lines` の判定に関わらないという考えとも合う。
   - 退けた案の一つは、今の振る舞いを仕様とし、仕様書に「空きと `@need-lines` のあいだに待つ図版があれば、空きを数える」と書くことである。出力は変わらないが、待つ図版という書き手に見えない状態で結果が分かれる。
   - もう一つは、`FPageFigure` だけを区切りとすることである。回した図版は書いた位置のページに置けないことが原稿から分かるが、二つの図版の扱いが分かれる。
2. **P9 を広げるか**：推奨は、P9′ として広げることである。今の P9 は空きの直後の `@need-lines` しか調べず、この形を見つけられなかった。
3. **自ら送られる図版も空きの記録を保つか**：「実装すること」の 1 の「段に何かを置いたブロック」と「待つ図版」は、自ら送られる図版をどちらとも決めない。前に送られた図版がなく、この段に入らずに次の段へ送る図版は、この段に何も置かないが、待つ図版でもない。推奨は、記録を保つのを待つ図版に限り、自ら送られる図版は記録を消すことである。[ADR 0026](0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) と仕様書は、自ら送られる図版を、前の `@need-lines` を受け取る次のブロックとする。前の空きは、その図版までの制御に属する。後の `@need-lines` から見ても、その図版は前のブロックになる。P9′ と W3 も、`waitingFigures` が待つ図版と読むものだけを飛ばすので、この扱いと合う。
   - 退けた案は、自ら送られる図版も記録を保つことである。後の `@need-lines` の結果は、図版が段に入るかによらなくなる。ただし、その図版は、前の `@need-lines` から見ればブロックなのに、後の `@need-lines` から見ればブロックでない、という二重の扱いになる。P9′ と W3 も、自ら送られる図版を飛ばすように広げなければならない。

## 決めたことの記録

2026-11-09 に、tett23 が推奨のとおりに決めた。

1. 改ページと述語の両方を改め、待つ図版は空きの記録を消さない。
2. P9 を P9′ に広げる。
3. 記録を保つのは待つ図版に限り、自ら送られる図版は記録を消す。

## 参考文献

- [golem-layout ADR 0026](0026-need-lines-and-blank-lines-pass-over-waiting-figures.md)、[golem-layout ADR 0027](0027-need-lines-judged-again-after-spaces.md)、[golem-layout ADR 0033](0033-read-waiting-figures-from-the-placement.md)、[golem-layout ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md)、[golem-layout ADR 0044](0044-read-the-figures-moved-by-need-lines-judged-before-spaces.md)
- [docs/adr/0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md)、[docs/adr/0208](../../adr/0208-widen-lightweight-formal-methods.md)
- [#759](https://github.com/tett23/golem/pull/759) の説明
