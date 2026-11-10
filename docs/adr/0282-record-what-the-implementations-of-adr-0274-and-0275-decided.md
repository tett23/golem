# ADR 0282: [ADR 0274](0274-prefer-pulling-in-and-limit-the-stretch-of-lines.md) と [ADR 0275](0275-keep-numbers-with-the-units-after-them.md) の実装が ADR を越えて決めた点を記録する

ステータス: 採択

## 文脈

2026-11-10 に、[ADR 0274](0274-prefer-pulling-in-and-limit-the-stretch-of-lines.md) の実装 [#824](https://github.com/tett23/golem/pull/824) と、[ADR 0275](0275-keep-numbers-with-the-units-after-them.md) の実装 [#826](https://github.com/tett23/golem/pull/826) がマージされた。
二つのプルリクエストの説明は、ADR の文と違うことをした点、ADR の文の中で食い違う箇所をどちらかに決めた点を、「確かめてほしい」として挙げている。
決めた ADR は、まだない。
この ADR は、[ADR 0255](0255-record-what-implementations-decided-on-2026-11-09.md) と [ADR 0256](0256-record-what-the-implementations-of-adr-0251-and-0252-decided.md) と同じく、それらを決めたこととして記録する。
どの点も、プルリクエストの説明を読み、`main` の `96d7e806`（#826 のマージ）のコードで確かめた。

以下、元の ADR の番号の順に並べる。
各項目は、ADR の文、実装、そうした理由の順に書く。

### [ADR 0274](0274-prefer-pulling-in-and-limit-the-stretch-of-lines.md)：プルリクエストの段で列挙する値

ADR のテスト設計は、[ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md) の組み方の環境に `line-adjustment` の二つの値と `stretch-limit` の三つの値（なし、0、2500）を足すとした。
プルリクエストの段で範囲ごとの予算 10 秒（[ADR 0208](0208-widen-lightweight-formal-methods.md) の 4）を超えるなら、`stretch-limit` だけを毎晩のジョブの段に移すとした。
つまり、ADR は、二つの値をどちらもプルリクエストで調べることを求めていた。

実装は、二つの値を合わせた六通りでも、二つの値だけでも、予算を超えたと報告している。
x86-64 の `tests-rest` で、「every input」のテストが 33 秒と 25 秒、R1 の golden との比較が 27 秒であった。
実装は、ADR の逃げ道より一段先まで移した（[`adjustsAt`](https://github.com/tett23/golem/blob/96d7e8067c941f1c18845af43a9b328cd6f6fe52/modules/golem-layout/test/LineBreakInvariantsSpec.hs#L628-L644)）。

- **プルリクエストの段**：既定の `"pull-in-first"` と上限なしの一通りだけを列挙する。
- **毎晩のジョブの段**（`GOLEM_ENUM_LINES_DEPTH` が 2 より大きい）：二つの値のそれぞれを、上限なし、0、2500 で組む。
- **R1**（`"balanced"` と上限なしの出力が ADR の前と同じ）：golden との比較を毎晩のジョブの段だけで行う（[`exhaustiveTests` の R1](https://github.com/tett23/golem/blob/96d7e8067c941f1c18845af43a9b328cd6f6fe52/modules/golem-layout/test/LineBreakInvariantsSpec.hs#L811-L819)）。#824 の初めの CI では、プルリクエストの段でも通っていた。
- **R7**（上限で分け方が変わらない）：プルリクエストでは部品 1 個まで、毎晩は部品 2 個までとする（[R7](https://github.com/tett23/golem/blob/96d7e8067c941f1c18845af43a9b328cd6f6fe52/modules/golem-layout/test/LineBreakInvariantsSpec.hs#L820-L824)）。R7 は二つの値をどちらも組むので、プルリクエストでも `"balanced"` は部品 1 個までは調べている。

予算の 10 秒の測り方と、超えたときにどこまで移してよいかは、[ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md) で決め直す。
その ADR の測り方（範囲のテストだけを走らせた時間）では、手元の 4 コアで、この範囲のプルリクエストの段は 3.3 秒から 4.8 秒であった。
同じ測り方で、行の調整の六通りをプルリクエストに戻すと 12 秒から 19 秒になり、手元でも 10 秒を超える。
x86-64 の CI の報告値（33 秒）は、ほかの約 30 のテストスイートと同時に走った時間であり、範囲そのものの重さではない。

### [ADR 0275](0275-keep-numbers-with-the-units-after-them.md)：コードと地の文の境

ADR の「実装すること」の 1 は、「本文の中のコード（`lkCode`）と URL（`lkUrl`）の箱どうしのあいだには当てない」とした。
一方、「不変条件」の節は、数と単位の組を「二つの箱がどちらも `lkCode` でも `lkUrl` でもないもの」と定めた。
`[code: 100]円` のように片方だけがコードの組は、1 によれば規則が当たり、不変条件によれば当たらない（W4 で、項目が ADR の前と同じでなければならない）。

実装は 1 に従い、二つの箱が両方ともコードか URL のときだけ除いた（[`between` の `numberUnit`](https://github.com/tett23/golem/blob/96d7e8067c941f1c18845af43a9b328cd6f6fe52/modules/golem-layout/src/Golem/Layout/Japanese.hs#L1848-L1861)）。
そのため、`[code: 100]円` の `0` と `円` のあいだには、既定では分割の候補がない。
W1 と W2 の列挙の述語も同じ読み方で書いた。

この読み方は、[golem-layout ADR 0049](../golem-layout/adr/0049-align-the-character-classes-and-unbreakable-pairs-with-jlreq.md) と同じである。
0049 は、分割禁止の三つの組を「`lkCode` と `lkUrl` の箱どうしのあいだには当てない」とし、実装も同じ条件を使う（[`pairKept`](https://github.com/tett23/golem/blob/96d7e8067c941f1c18845af43a9b328cd6f6fe52/modules/golem-layout/src/Golem/Layout/Japanese.hs#L1836-L1847)）。
同じ箇所に二つの規則が違う境を持つと、`[code: 100]％` は分けず `[code: 100]円` は分ける、という組が生まれる。
コードの中の改行は [golem-layout ADR 0034](../golem-layout/adr/0034-line-breaks-between-japanese-characters-in-inline-code.md) が決めるが、コードの箱と地の文の箱のあいだは地の文の側の境であり、0034 の範囲ではない。

### [ADR 0275](0275-keep-numbers-with-the-units-after-them.md)：縦組みの全角の数字の並び

ADR は、b の分類が仮名か漢字等のときに規則を当て、「縦組みでも横組みと同じに当てる」とした。
全角の数字（U+FF10 から U+FF19）の分類は漢字等である。
そのため、文のとおりに実装すると、`１２`、`１一` のように全角の数字の後に全角の数字か漢字が続く組にも、規則が当たる。

横組みでは、`１２` は [golem-layout ADR 0049](../golem-layout/adr/0049-align-the-character-classes-and-unbreakable-pairs-with-jlreq.md) の B2（連数字）がすでに分けないので、振る舞いは変わらない。
変わるのは縦組みである。
0049 は、JLReq の 3.1.10 の「縦組みでアラビア数字を一字ずつ並べた場合は分割してよい」に従い、縦組みの連数字には B2 を当てなかった。
0049 の B2 の不変条件は「縦組みでは、その位置の項目はこの ADR の前と同じである」と書く。
0275 の後は、縦組みの `１２３` も既定（`number-unit-penalty` が 10000）では字のあいだで分けない。

実装は ADR の文に従った。
仕様書にも「全角の数字は漢字等なので、縦組みの `１２３` の字のあいだも、この規則で既定では分けない」と書いた（[docs/specifications.md](../specifications.md) の「行分割」）。
0049 のテストは、0275 の変更を取り除いた項目（[`withoutNumberUnits`](https://github.com/tett23/golem/blob/96d7e8067c941f1c18845af43a9b328cd6f6fe52/modules/golem-layout/test/LineBreakInvariants.hs#L896-L904)）で比べるように変えた（[`UnbreakablePairsSpec` の `itemsV`](https://github.com/tett23/golem/blob/96d7e8067c941f1c18845af43a9b328cd6f6fe52/modules/golem-layout/test/UnbreakablePairsSpec.hs#L113-L118)）。
0049 の B2 が述べるのは 0049 の変更の前後の差であり、比べ方を変えれば今も成り立つ。

JLReq は、縦組みの連数字を「分割してよい」とするが、分割を求めてはいない。
縦組みで半角の数字を並べた `12` は一つの欧文の語の箱なので、今も字のあいだで分けない。
全角の `１２` だけが分けられると、同じ数を書く字の幅で、分けるかどうかが変わる。

### [ADR 0275](0275-keep-numbers-with-the-units-after-them.md)：W2 と分割禁止の組

W2 は、`number-unit-penalty` が 10000 より小さいとき、数と単位の組の位置の候補が「罰点 P の罰点の項目ちょうど一つ」であることを求める。
ところが、組の中には、[golem-layout ADR 0049](../golem-layout/adr/0049-align-the-character-classes-and-unbreakable-pairs-with-jlreq.md) が分けない組（横組みの `１２`、全角の後置省略記号の `１％`）がある。
そこには無限の罰点しかなく、P の候補はない。
W2 をそのまま読むと、0049 と両立しない。

実装は、禁則と 0049 の組を `number-unit-penalty` より先に判定し、そこを無限の罰点のままにした（[`kept`](https://github.com/tett23/golem/blob/96d7e8067c941f1c18845af43a9b328cd6f6fe52/modules/golem-layout/src/Golem/Layout/Japanese.hs#L1858-L1861)）。
W2 は、0049 が分けない組を除いた組で確かめる（[`w1w2NumberUnit`](https://github.com/tett23/golem/blob/96d7e8067c941f1c18845af43a9b328cd6f6fe52/modules/golem-layout/test/LineBreakInvariants.hs#L874-L893)、[W2 の例](https://github.com/tett23/golem/blob/96d7e8067c941f1c18845af43a9b328cd6f6fe52/modules/golem-layout/test/NumberUnitSpec.hs#L138-L141)）。
仕様書も、「JLReq の 3.1.10 が分割禁止とする組と、禁則で分けない位置では、`number-unit-penalty` によらず改行しない」と書いている。
ADR 自身も、W5 で改行しない範囲を P より先に置いており、同じ順の考え方である。

## 実装すること

ここに記録した振る舞いは、`main` の `96d7e806` に入っている。
この ADR の実装は、次のことだけを行う。

- ステータスの行を次のように変える。
  - [ADR 0274](0274-prefer-pulling-in-and-limit-the-stretch-of-lines.md)：`採択→プルリクエストの段で列挙する値と、R1 と R7 を調べる段は [ADR 0282](0282-record-what-the-implementations-of-adr-0274-and-0275-decided.md)`
  - [ADR 0275](0275-keep-numbers-with-the-units-after-them.md)：`採択→（数と単位の組のコードの境、縦組みの全角の数字の並び、W2 の読み方）は [ADR 0282](0282-record-what-the-implementations-of-adr-0274-and-0275-decided.md)`
  - [golem-layout ADR 0049](../golem-layout/adr/0049-align-the-character-classes-and-unbreakable-pairs-with-jlreq.md)：`採択→（縦組みの全角の数字の並び）は [ADR 0282](../../adr/0282-record-what-the-implementations-of-adr-0274-and-0275-decided.md)`
- [docs/specifications.md](../specifications.md) の「行分割」の連数字の項目（「横組みだけに当て、縦組みでは字のあいだで分けてよい」）に、縦組みの全角の数字の並びは数と単位の規則で既定では分けないことを書き足し、この ADR へのリンクを付ける。今の仕様書は、同じ節の二つの段落で、縦組みの `１２３` を「分けてよい」と「既定では分けない」と書いている。
- `numberUnit` と `w1w2NumberUnit` と `adjustsAt` の注釈に、この ADR へのリンクを足す。

## 実装しないこと

- **規則の振る舞いを変えること**：記録だけを行う。
- **プルリクエストの段の列挙を変えること**：何をプルリクエストに戻すかは、[ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md) の測り方で測り直して決める。
- **縦組みの全角の数字の並びを分けられるようにすること**：「メンテナーが決めること」の 3 で、推奨の案を採るなら行わない。

## 不変条件

なし。
すでに入った振る舞いと手順を記録するだけで、振る舞いを変えない。
コードの境と W2 の読み方は、今の `w1w2NumberUnit` がその読み方の述語として列挙の入力のすべてで確かめている。
縦組みの全角の数字の並びは、0275 の W1 が縦組みの例（`NumberUnitSpec` の縦組みの段）で確かめている。

## テスト設計

- ステータスの行と注釈と仕様書の文は、`adr-guard links --fix` と `adr-guard pre-commit --allow-status --allow-links` が通ることで確かめる。
- 仕様書の連数字の項目を直した後、「行分割」の節に、縦組みの `１２３` を「分けてよい」とだけ書いた文が残っていないことを、読んで確かめる。

## トレードオフ

実装の後で ADR を書くので、どの点も、決める前に代わりの案を比べていない。
[ADR 0255](0255-record-what-implementations-decided-on-2026-11-09.md) と同じく、点ごとに ADR を分けずに一本にまとめた。

[ADR 0274](0274-prefer-pulling-in-and-limit-the-stretch-of-lines.md) の分け方を記録すると、`"balanced"` と上限の値は、部品 2 個の入力では毎晩のジョブでしか調べないことを認める。
毎晩のジョブの行分割の段は、2026-11-09 の `8f8dc345` の実行を最後に、この ADR を書いた時点まで `main` で一度も走っていない（[ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md) の文脈）。
2026-11-10 の `5fe4b57f` の毎日の起動の実行は、この ADR を採択した時点では、まだ行分割の段に達していない。
したがって、二つの値の組み合わせの多くは、この ADR を書いた時点で、CI ではまだ調べられていない。

縦組みの全角の数字の並びを分けないと、狭い縦組みの行で長い全角の数を組んだとき、行の調整の余地が減り、はみ出す行（G07105）が増えうる。
`number-unit-penalty` を 10000 より小さくすれば、その位置は罰点 P の候補になる。

## メンテナーが決めること

1. **[ADR 0274](0274-prefer-pulling-in-and-limit-the-stretch-of-lines.md) のプルリクエストの段の列挙**：推奨は、今の分け方（プルリクエストは既定の `"pull-in-first"` と上限なし、毎晩は六通り、R1 は毎晩だけ）を記録して認め、[ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md) の測り方で予算に収まると測れたものは、その ADR の実装でプルリクエストに戻すことである。既定の値をプルリクエストで調べるという選び方は、0281 の推奨の規則（既定の組版はプルリクエストで調べる）に合う。
   - 退けた案の一つは、ADR の文に戻し、二つの値をプルリクエストで調べることである。CI の報告値（33 秒）が同時に走るほかのスイートの分を含むので、測り方を決めないまま戻しても、超えたかどうかを判定できない。
   - もう一つは、予算を超えたので `"balanced"` を列挙から外すことである。`"balanced"` は利用者が選べる値であり、どの段でも調べなくなる。
2. **コードと地の文の境**：推奨は、実装のとおり、二つの箱が両方ともコードか URL のときだけ除く読み方（「実装すること」の 1 の文）を採ることである。[golem-layout ADR 0049](../golem-layout/adr/0049-align-the-character-classes-and-unbreakable-pairs-with-jlreq.md) の三つの組と同じ境になり、同じ箇所の二つの規則が食い違わない。
   - 退けた案は、不変条件の文に合わせ、片方でもコードか URL の組を除くことである。`[code: 100]％` を分けず `[code: 100]円` を分ける組ができる。直すなら 0049 の境も同時に変えることになり、0049 の B8 とコードの列挙の述語を書き直す。
3. **縦組みの全角の数字の並び**：推奨は、実装のとおり、既定では分けないことである。ADR の文（縦組みでも同じに当てる）に合い、縦組みの半角の数字（一つの語の箱）とも揃う。JLReq は分割を許すだけで、求めてはいない。
   - 退けた案は、b が全角の数字のとき規則を当てず、0049 の縦組みの扱いに戻すことである。JLReq の許す分割を残せるが、`１２` と `12` で分けるかどうかが字の幅で変わり、既定の組版で数が行をまたぐ。
4. **W2 の読み方**：推奨は、実装のとおり、W2 を「禁則と 0049 の組で分けない位置を除く」と読むことである。JLReq の 3.1.10 の分割禁止は規定で、0275 の規則は読みやすさのための選択であり、規定が選択に勝つ順が自然である。W5 も同じ順で書かれている。
   - 退けた案は、P を 0049 の組にも当て、`１％` を P で分けられるようにすることである。JLReq の 3.1.10 に反する組版を、欄一つで作れるようになる。

## 決めたことの記録

2026-11-10 に、tett23 が「メンテナーが決めること」のすべてを推奨のとおりに決めた。

1. [ADR 0274](0274-prefer-pulling-in-and-limit-the-stretch-of-lines.md) のプルリクエストの段の列挙は、今の分け方（プルリクエストは既定の `"pull-in-first"` と上限なし、毎晩は六通り、R1 は毎晩だけ、R7 はプルリクエストで部品 1 個まで）を認める。[ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md) の量り方で予算に収まると測れたものは、その ADR の実装でプルリクエストに戻す。
2. 数と単位の組のコードと地の文の境は、二つの箱が両方ともコードか URL のときだけ除く読み方とする。
3. 縦組みの全角の数字の並びは、既定では分けない。
4. W2 は、禁則と [golem-layout ADR 0049](../golem-layout/adr/0049-align-the-character-classes-and-unbreakable-pairs-with-jlreq.md) の組で分けない位置を除いて読む。

採択にあたり、`main` の `5fe4b57f`（[ADR 0280](0280-breaks-between-latin-word-boxes-follow-the-joined-word.md) の実装のマージ）で、記録した振る舞いのコード（`numberUnit`、`pairKept`、`adjustsAt`、R1 と R7 の段）と、仕様書の連数字の二つの段落が `96d7e806` から変わっていないことを確かめた。

## 参考文献

- [ADR 0208](0208-widen-lightweight-formal-methods.md)、[ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md)、[ADR 0255](0255-record-what-implementations-decided-on-2026-11-09.md)、[ADR 0256](0256-record-what-the-implementations-of-adr-0251-and-0252-decided.md)、[ADR 0274](0274-prefer-pulling-in-and-limit-the-stretch-of-lines.md)、[ADR 0275](0275-keep-numbers-with-the-units-after-them.md)、[ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md)
- [golem-layout ADR 0034](../golem-layout/adr/0034-line-breaks-between-japanese-characters-in-inline-code.md)、[golem-layout ADR 0049](../golem-layout/adr/0049-align-the-character-classes-and-unbreakable-pairs-with-jlreq.md)
- 実装のプルリクエストの説明：[#824](https://github.com/tett23/golem/pull/824)、[#826](https://github.com/tett23/golem/pull/826)
- W3C. Requirements for Japanese Text Layout (JLReq). https://www.w3.org/TR/jlreq/（3.1.10 分割禁止）
