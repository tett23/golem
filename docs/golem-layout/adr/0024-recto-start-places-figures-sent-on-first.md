# ADR 0024: 奇数（偶数）ページから始める前に、送った図版と続きの注を置ききる

ステータス: 採択

## 文脈

### 見つかった違反

[ADR 0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md) の改ページの不変条件のテストは、仕様書の「既知の不具合」の「送った図版の後の改丁の見出しが、偶数ページに置かれる」を、テストの中の既知の不具合の一覧で除いている（[`PaginateInvariantsSpec.hs`](https://github.com/tett23/golem/blob/499f6d95fd32c1188555a81c8f4b60c0cc612d83/modules/golem-layout/test/PaginateInvariantsSpec.hs#L237-L242)）。
違反するのは I8 と、I6 である。

一段で段の行の数が 3 の版面で、`PaginateEnum` の要素で書くと、次の二つの形で起きる。
出力は、`cabal repl golem-layout:test:golem-layout-test` で `paginateInput` を呼んで確かめた（2026-11-08、コミット 499f6d95）。

| 入力 | 今の出力 |
| --- | --- |
| `[EPara 1, EFigure 3, ERecto]` | 1 ページに段落、2 ページが白ページ、3 ページに図版、4 ページに見出し |
| `[EPara 3, EPara 1, EFigure 3, ERecto, EPara 1]` | 2 ページに段落の 1 行、3 ページに図版、4 ページに見出しと段落 |

一つめは、図版が白ページの次に移り、見出しが偶数ページに置かれる。
二つめは、奇数ページの 3 ページを図版が埋め、見出しが偶数ページの 4 ページに置かれる。

### 原因

改丁の見出しと、`@page-break recto` と `@page-break verso` は、どれも `parityStart` でページを改める（[`State.hs`](https://github.com/tett23/golem/blob/499f6d95fd32c1188555a81c8f4b60c0cc612d83/modules/golem-layout/src/Golem/Layout/Paginate/State.hs#L123-L129)、[`Paginate.hs` の `applyBreak`](https://github.com/tett23/golem/blob/499f6d95fd32c1188555a81c8f4b60c0cc612d83/modules/golem-layout/src/Golem/Layout/Paginate.hs#L232-L237)、[見出し](https://github.com/tett23/golem/blob/499f6d95fd32c1188555a81c8f4b60c0cc612d83/modules/golem-layout/src/Golem/Layout/Paginate.hs#L266-L269)）。
`parityStart` は、今のページが空でなければ `nextPage` で次のページに進み、そのページの番号の奇数と偶数が合わなければ `blankPage` で白ページにする。

`nextPage` は、新しいページの先頭に、待っている図版と続きの注の本文を置く（[`advance`](https://github.com/tett23/golem/blob/499f6d95fd32c1188555a81c8f4b60c0cc612d83/modules/golem-layout/src/Golem/Layout/Paginate/State.hs#L201-L230)）。
`blankPage` は、今のページが空だという前提で、中身のない白ページを出力に足し、ページの番号を一つ進める。
今の段に置いた図版（`sSlots`）は消さないので、図版は次のページに持ち越されて出力される。
これが一つめの形である。

奇数と偶数が合っていれば、見出しは送った図版の後に置かれる。
見出しが図版の後に入らなければ、見出しの手順は次の段に進み（[golem-layout ADR 0023](0023-keep-with-next-after-figures-sent-on.md) の 2 の判定）、奇数と偶数を確かめずに偶数ページに置く。
これが二つめの形である。

どちらも、`parityStart` が、ページを改めた後に送った図版がそのページを取ることを考えていないことから出ている。
[golem-layout ADR 0023](0023-keep-with-next-after-figures-sent-on.md) の原因（見出しを次の段に送った後に確かめ直さない）とは別の箇所であり、片方を直しても、もう片方の違反は残る。
作業用の変更で、`keep` だけを直すと、要素 4 個の入力で I8 の違反が 21,182、I6 の違反が 3,182 残った（I6 は、どれも改丁の見出しのもの）。
`parityStart` だけを直すと、I8 の違反はなくなり、I6 と I7 の違反は、既知の不具合の一覧の数（3,654 と 757）のまま残った。

### 送った図版をどこに置くか

直し方は、送った図版を、改丁の見出しの前のページに置くか、改丁の見出しのページに置くかで分かれる。
仕様書の「改ページ」の節は「送った図版と続きの脚注は、改ページの後の新しいページに置き、白ページには置かない」と定め、[ADR 0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md) の I8 は改丁の見出しを「奇数ページの最初の段の最初」に置くと定める。
改ページの後の新しいページが奇数ページなら、二つは両立しない。
どちらを採るかは、[docs/adr/0206](../../adr/0206-pagination-points-the-invariants-did-not-decide.md) の 3 で決める。
この ADR は、その推奨（送った図版を改丁の前に置ききる）を前提にする。

## 実装すること

### 1. `parityStart` の前に、送った図版と続きの注を置ききる

`Golem.Layout.Paginate.State` の `parityStart` を、次の手順にする。

1. 待っている図版か続きの注の本文があれば、`flushDeferred` で、それらを置ききるまで次の段に進む。
2. 今のページが空でなければ、次のページに進む。
3. ページの番号の奇数と偶数が合わなければ、白ページにする。

1 の後は待っている図版も続きの注もないので、2 で進んだページは空であり、3 の `blankPage` の前提が成り立つ。
`flushDeferred` は本の最後と段組みの切り替え（`FSwitchColumns`）で使っている関数である（[`State.hs`](https://github.com/tett23/golem/blob/499f6d95fd32c1188555a81c8f4b60c0cc612d83/modules/golem-layout/src/Golem/Layout/Paginate/State.hs#L283-L286)）。

`parityStart` を呼ぶ 5 か所（改丁の見出し、罫線を持つ改丁の見出し、改丁の見出しの前の行アキ、`@page-break recto`、`@page-break verso`）は、どれも同じに変わる。

### 2. 文書

- [docs/specifications.md](../../specifications.md) の「改ページ」の節の「送った図版と続きの脚注は、改ページの後の新しいページに置き、白ページには置かない」の後に、「改丁の見出しと `@page-break recto`、`@page-break verso` では、送った図版と続きの脚注をすべて置いてから、奇数（偶数）ページを始める。改丁の見出しは、送った図版の後に置かない」を足す（[docs/adr/0206](../../adr/0206-pagination-points-the-invariants-did-not-decide.md) の 3）。
- 仕様書の「既知の不具合」から、「送った図版の後の改丁の見出しが、偶数ページに置かれる」を消す。
- docs/roadmap.md の「改ページの既知の不具合」の項目から、同じものを消す。三つの項目がすべて消えれば、項目ごと消す。

### 3. 出力の変化

送った図版がある状態で改丁の見出しか `@page-break recto`、`@page-break verso` が来る本で、PDF のバイト列が変わる。

| 入力（一段、C = 3） | 直した後の出力 |
| --- | --- |
| `[EPara 1, EFigure 3, ERecto]` | 1 ページに段落、2 ページに図版、3 ページに見出し |
| `[EPara 3, EPara 1, EFigure 3, ERecto, EPara 1]` | 3 ページに図版、4 ページが白ページ、5 ページに見出しと段落 |

一つめはページが一つ減り、二つめは一つ増える。

この ADR を書く段で、1 の変更と [golem-layout ADR 0023](0023-keep-with-next-after-figures-sent-on.md) の変更を入れた `golem` と、コミット 499f6d95 の `golem` で、golem-driver の fixture の `sample`、`figures`、`complex-vertical`、`complex-horizontal`、`kanikosen`、`tempest` と、使い手のマニュアルの PDF を組んで比べ、どれもバイト列が一致した（2026-11-08。手順は [golem-layout ADR 0023](0023-keep-with-next-after-figures-sent-on.md) の「出力の変化」）。
golem-driver のテストも、すべて通った。
ほかの本は比べていないので、実装のプルリクエストの見た目の回帰テストで変わったページがあれば、目で確かめてから参照（`scripts/visual/pages/`）を改める。

## 実装しないこと

- **回したページの図版（`FPageFigure`）の扱いを変えること**：`flushDeferred` の中の `nextColumn` が、今のとおり本文を持たないページに置く（[golem-driver ADR 0034](../../golem-driver/adr/0034-fit-figures-to-column.md)、[0039](../../golem-driver/adr/0039-breaks-around-turned-figures.md)）。
- **`@page-break`（奇数と偶数を問わない改ページ）**：送った図版を新しいページの先頭に置く今の規則を変えない。
- **白ページを減らす工夫**：送った図版を改丁の前の白ページになるはずのページに置くことは、1 の手順でそうなる。それより前のページに図版を戻すことはしない。
- **見出しを送った図版の後に置くかの判定**：[golem-layout ADR 0023](0023-keep-with-next-after-figures-sent-on.md) で直す。

## 不変条件

- **R1**：改丁の見出しは、奇数ページの最初の段の、最初の要素である。前に、送った図版も、ほかの見出しも置かない（I8。[docs/adr/0206](../../adr/0206-pagination-points-the-invariants-did-not-decide.md) の 3 で強めたもの）。
- **R2**：`@page-break recto` の後の最初の要素は奇数ページの最初の段の最初に、`@page-break verso` の後の最初の要素は偶数ページの最初の段の最初に置かれる。
- **R3**：白ページは、図版も行も注の本文も持たない。すべての図版は、ちょうど一度ずつ置かれる（I1）。
- **R4**：改丁の見出しより前に流れに現れた図版は、改丁の見出しのページより前のページに置かれる。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 待っている図版の数 | 0、1、2 |
| 改ページの後の新しいページ | 奇数、偶数 |
| 送った図版が新しいページで取る行 | 1、C − 1、C |
| 続きの注の本文 | なし、1 行 |
| 改める印 | 改丁の見出し、`@page-break recto`、`@page-break verso` |
| 段の数 | 1、2 |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
テストの名前には、R1 から R4 の番号を入れる。

- **R1（列挙）**：改ページの不変条件のテストの既知の不具合の一覧から、「送った図版の後の改丁の見出しが、偶数ページに置かれる」の項目を消し、I8 の述語を [docs/adr/0206](../../adr/0206-pagination-points-the-invariants-did-not-decide.md) の 3 のとおり強める。要素 3 個まで（プルリクエスト）と 5 個まで（毎晩の `enum.yml`）で、I6 と I8 の違反がないこと。今は要素 3 個で違反が出るので失敗する。
- **R1（回帰）**：`PaginateSpec` に、文脈の二つの入力を `renderCase` の形で足し、「出力の変化」の表のとおりになること。二段組みの `[EPara 1, EFigure 3, ERecto]` では、1 ページの 2 段めに図版、2 ページが白ページ、3 ページに見出しが置かれること。
- **R2**：`FBreak BreakRecto` と `FBreak BreakVerso` の前に送った図版がある流れを、改ページの後の新しいページが奇数の場合と偶数の場合で `PaginateSpec` に足す。列挙は `BreakPage` だけなので、手で選ぶ。
- **R3**：上のすべての例で、白ページの `poSlots` と `poFootnotes` が空であること。続きの注の本文がある状態の改丁の見出しの例を足す。
- **R4**：上のすべての例で、図版の段が、改丁の見出しの段より前にあること。
- 既存の `PaginateSpec` の改丁と改ページの例（回したページの図版の後の改ページを含む）が、そのまま通ること。

## トレードオフ

改丁の前の送った図版のために、図版だけのページと白ページが一枚ずつ増えることがある（「出力の変化」の二つめ）。
送った図版を改丁の見出しのページの先頭に置けば増えないが、前の章の図版が次の章の扉に出る。
LaTeX の `\cleardoublepage` も、待っている図版をすべて出力してから奇数ページを始める。

`flushDeferred` を使うので、本の最後と段組みの切り替えと同じ置き方になる。
送った図版の置き方を一か所で変えれば、三つが揃って変わる。

## メンテナーが決めること

1. **直す場所**：推奨は、`parityStart` の最初に `flushDeferred` を呼ぶことである。改丁の見出しと `@page-break recto`、`@page-break verso` が一か所で直り、`blankPage` を呼ぶときにページが空であることが手順の上で保たれる。
   - 退けた案は、`blankPage` を、今の段に置いたものがあれば先にそのページを閉じる形にすることである。一つめの形は直るが、送った図版が改丁の見出しのページの先頭に残り、二つめの形が直らない。[docs/adr/0206](../../adr/0206-pagination-points-the-invariants-did-not-decide.md) の 3 で、送った図版を改丁の見出しのページに置く案を選んだときに、この案に戻る。
2. **`@page-break verso` も同じにするか**：推奨は、同じにすることである。三つは同じ `parityStart` を通り、仕様書も同じ規則として書いている。
   - 退けた案は、改丁の見出しだけを直すことである。`@page-break recto` の後に見出しを書いた原稿と、`page-break = "recto"` の見出しとで、送った図版の置き方が変わる。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-08、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [ADR 0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md)、[docs/adr/0017](../../adr/0017-forced-page-breaks.md)、[docs/adr/0206](../../adr/0206-pagination-points-the-invariants-did-not-decide.md)
- [golem-layout ADR 0003](0003-pagination-and-s2.md)、[golem-layout ADR 0015](0015-figure-order.md)、[golem-layout ADR 0023](0023-keep-with-next-after-figures-sent-on.md)
- [golem-driver ADR 0034](../../golem-driver/adr/0034-fit-figures-to-column.md)、[golem-driver ADR 0039](../../golem-driver/adr/0039-breaks-around-turned-figures.md)
- [ADR 0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md) の実装のプルリクエスト（[#641](https://github.com/tett23/golem/pull/641)）の報告
- "LaTeX2e: An unofficial reference manual", `\clearpage & \cleardoublepage`. https://latexref.xyz/_005cclearpage-_0026-_005ccleardoublepage.html（今のページを終え、待っている図版と表をすべて出力する。2026-11-08 に確かめた）
