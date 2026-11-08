# ADR 0033: 不変条件の「待つ図版」を、置き方から読む形で記録する

ステータス: 採択（未実装）

## 文脈

[golem-layout ADR 0026](0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) は、送った図版が待っているあいだに書いた図版（待つ図版）が、前の `@need-lines` と行アキの「次のブロック」にならないと決めた。
その「実装すること」の 3 は、不変条件の述語の P1′、P3′、P4′ のために、待つ図版を次のように定めた。

> 流れで後に書いたブロックの最初の部分より後の位置（ページ、段、段の中の順）に置かれた図版を、待つ図版とする。

実装（[#685](https://github.com/tett23/golem/pull/685)）で列挙を走らせると、この定義は、同じ ADR の 1 の改ページの規則と合わない反例を三つの形で出した。

1. 後のブロックが次の段へ進むと、待ちの列の図版が先にその段へ置かれるので、待つ図版はそのブロックより前に置かれる。定義はこの図版を待つ図版に数えず、P4′ が落ちる。例：`Input 6 1 [EPara 2, EFigure 5, EBlank 2, EFigure 1, ENotedPara 2]`。
2. 自ら送られる待ちの列の先頭の図版を、定義は待つ図版に数える。改ページの規則は、この図版に前の `@need-lines` を当てるので、間に改ページがあると、P1′ を別のブロックで判定してしまう。例：`[EFigure 6, EFigure 6, EBreak, EFigure 6, ENeedLines, EFigure 1]`。
3. 本の終わりの句（後に図版でないブロックがなければ待つ図版とする）を文字どおりに読むと、段に入って待っていない図版を待つ図版に数え、P5 が落ちる。例：`[EPara 1, EBlank 1, EFigure 1]`。

実装は、述語の `waitingFigures` を、待ちの列を出力から読む形に改めた（[`PaginateInvariants.hs`](https://github.com/tett23/golem/blob/ed9aafba3e0ffd788f921de86b261339d8f642cd/modules/golem-layout/test/PaginateInvariants.hs#L405-L440)）。
前の図版がまだ置かれていない位置に書いた図版と、書いた位置のページに置けない回した図版を、待つ図版とする。
述語は、今までどおり入力と出力だけを読む。
この読み方は、仕様書の「改ページ」の節と #685 の説明に書かれたが、決めた ADR がない。
メンテナーは、記録の ADR を作ると決めた（2026-11-08）。

## 実装すること

- [golem-layout ADR 0026](0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) の 3 の待つ図版の定義を、次の読み方に改めたものとして記録する。
  - 待つ図版は、改ページ（`place`）が待たせる図版である。つまり、流れでそれより前に書いた図版のうち、まだ出力のどこにも置かれていないものがある位置に書いた `FFigure` と、書いた位置のページに置けない `FPageFigure` である。
  - この判定は、入力の流れと出力の `PageOut` だけから行う。実装の内部（`St`、`sDeferred`）を読まない（[ADR 0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md) の決めごと）。
- [golem-layout ADR 0026](0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) のステータスの行に、待つ図版の定義はこの ADR が改めたことを書く。
- `waitingFigures` の注釈と、仕様書の「改ページ」の節の待つ図版の文に、この ADR へのリンクを足す。
- 上の三つの反例を、述語の回帰のテストとして `PaginateSpec` か `PaginateInvariantsSpec` に入れる（入っていなければ）。

## 実装しないこと

- **改ページの振る舞いを変えること**：記録だけを行う。[golem-layout ADR 0026](0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) の 1 と 2 の規則は変えない。
- **述語が実装の内部を読むこと**：「メンテナーが決めること」の 1 で退ける。

## 不変条件

- **W1 待つ図版の読み方**：入力の流れのある `FFigure` が待つ図版であるのは、流れでそれより前に書いた図版のうち、出力で置かれた位置がその図版の書いた位置より後のものがあるときである。`FPageFigure` は、書いた位置のページに置けないときに待つ図版である。
- **W2 内部を読まない**：W1 の判定は、入力の流れと出力の `PageOut` だけを使う。

P1′、P3′、P4′、P5 は、W1 で読んだ待つ図版について、[golem-layout ADR 0026](0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) の文のとおりに成り立つ。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 待ちの列 | なし、図版一つ、図版二つ、回した図版を含む |
| 後のブロック | 同じ段に入る、次の段へ進む、なし（本の終わり） |
| 改ページ | なし、待つ図版の前、待つ図版の後 |

## テスト設計

- 上の三つの反例で、今の `waitingFigures` が待つ図版を正しく読み、P1′、P4′、P5 が成り立つこと（回帰のテスト。今の実装で通る）。
- 列挙のすべての入力で P1′、P3′、P4′、P5 が成り立つことは、今のテストが確かめている。

どれも今の実装で通る見込みで、先に失敗させることはできない。
今の振る舞いを固定するテストである。

## トレードオフ

待つ図版を出力から読むと、述語が改ページの置き方の規則（どの図版が待たされるか）をなぞることになる。
置き方の規則を変える ADR は、この読み方も見直す必要がある。
その代わり、[ADR 0026](0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) の定義のように、置かれた位置の前後だけで決めると、待ちの列の図版が先に置かれる場合を取りこぼす。

## メンテナーが決めること

1. **待つ図版の読み方**：推奨は、実装のとおり、前の図版がまだ置かれていない位置に書いた図版を待つ図版とすることである。入力と出力だけから読め、三つの反例をどれも正しく扱う。
   - 退けた案の一つは、[golem-layout ADR 0026](0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) の文の定義に戻し、反例を既知の不具合として除くことである。正しい出力を違反として扱い続けることになる。
   - もう一つは、述語に実装の内部（`sDeferred`）を見せることである。[ADR 0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md) の、述語が実装の内部を読まないという決めごとに反し、実装の誤りを述語が写すおそれがある。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-08、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [golem-layout ADR 0026](0026-need-lines-and-blank-lines-pass-over-waiting-figures.md)、[golem-layout ADR 0027](0027-need-lines-judged-again-after-spaces.md)、[golem-layout ADR 0025](0025-need-lines-and-blank-lines-after-figures-sent-on.md)、[ADR 0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md)
- [#685](https://github.com/tett23/golem/pull/685) の説明
