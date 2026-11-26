# ADR 0461: ほかの誤りから続いて起きるdiagnosticも、箇所ごとに出す

Status: accepted-pending

## 文脈

これまでの ADR には、元の誤りを一か所で報告したとき、その誤りから続いて起きる diagnostic を出さないと決めたものがある。
同じ原因から誤りを重ねないためである。

- [docs/adr/0162](0162-calling-emet-functions-from-gm.md) の「取り込み」：`.emet` の読み込みか型の検査に誤りがあるとき、名前空間を通した呼び出しで G02022、G02009、G02002 を報告しない。
- [root ADR 0451](0451-import-listed-names-without-a-namespace.md) の I8：同じとき、その `.emet` から並べた名前の G02276 と重なりの検査をせず、その名前の呼び出しでも G02022、G02009、G02002 を出さない。
- [root ADR 0458](0458-rename-listed-imports-with-as.md) の I9：読み込めない `.emet` と、マニフェストの無いファイルの評価の変数のファイルから、別名で取り込んだ名前の呼び出しと参照は、diagnostic を出さない。
- [root ADR 0455](0455-resolve-variable-imports-through-the-import-graph.md)：マニフェストの無いファイルの評価で、変数のファイルから取り込んだ名前の参照は、何も報告しない。
- 0451 と [root ADR 0453](0453-override-built-in-commands-by-listed-imports-and-plugins.md)：二つの `@import` が同じ名前を並べたとき（G02272）、その名前の呼び出しは何も出力せず、何も報告しない。
- [golem-plugin ADR 0003](../golem-plugin/adr/0003-plugin-diagnostic-codes.md) の「変更」：プラグインの読み込みに誤りがあるとき、未知のコマンド（G02022）を報告しない。
  仕様書は、G02009 と G02090 も同じく報告しないと書く（docs/specifications.md の 9768 行）。
- [root ADR 0459](0459-take-the-next-block-as-the-body-without-indentation.md) の「コマンドの種類」：呼ぶ先の分からない名前のあるまとまりでは、G02011 と G02123 を出さない。

メンテナーは、2026-11-26 に、次のことを決めた。

- 同じコードでも、当てはまる箇所ごとに一つずつ出す。
  書き手に、数の分からない誤りを一つずつ直させないためである。
  誤りの数を少なく見積もるより、多く見積もるほうがよい。
- 上の決まりも改め、続いて起きる diagnostic も出す。

この ADR は、続いて起きる diagnostic のコードと、出す箇所を決める。

## 調査した事項

origin/main（[c034510](https://github.com/tett23/golem/commit/c034510e33476f4af68ba22636f5ab6ef8463f0a)）で、次のことを確かめた。

- 読み込めない `.emet` から並べた名前と、G02272 の名前は、何も報告しない名前として取り込み、その呼び出しは何も出力しない（[File.hs#L670](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-eval/src/Golem/Eval/File.hs#L670)、[File.hs#L739](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-eval/src/Golem/Eval/File.hs#L739)）。
- `.emet` のどれか一つに誤りがあれば、すべての `.emet` を読み込めないものとして扱う（[File.hs#L775](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-eval/src/Golem/Eval/File.hs#L775)、docs/specifications.md の 9233 行）。
- マニフェストの無いファイルの評価では、変数のファイルから取り込んだ名前を `stUnresolvedVars` に入れ、その参照は何も報告しない（[File.hs#L827-L829](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-eval/src/Golem/Eval/File.hs#L827-L829)）。
  この評価は `.emet` を読み込まず、`.emet` を読み込めないときと同じに扱う（[Evaluate.hs#L427-L431](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-evaluate/src/Golem/Evaluate.hs#L427-L431)）。
- 呼ぶ先の分からない名前のあるまとまりでは、`quiet` で G02011 と G02123 を出さない（[File.hs#L1354](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-eval/src/Golem/Eval/File.hs#L1354)）。
  `quiet` はまとまりごとに決まり、まとまりの中に作り直した入れ子のまとまりには伝わらない。
  そのため、`@b`（読み込めない `.emet` の名前）、`@lang en`、`@toc`、段落の原稿は、入れ子の側で G02011 を出す。
  これは 0459 の「そのまとまりでは G02011 と G02123 を出さない」と食い違う（impl-0459 のビルドの `golem inspect --as ir` で、調べを受け持ったエージェントが確かめた）。
- 式の評価は、最初の誤りで止まり、一つの式につき一つだけ diagnostic を出す（[golem-eval ADR 0003](../golem-eval/adr/0003-evaluation-diagnostic-codes.md) の 64 行）。

## 実装すること

### 続いて起きるdiagnostic

元の誤りから続いて起きる箇所ごとに、次の diagnostic を一つずつ出す。
どれもエラーとする。
元の誤りの diagnostic も、今と同じく出す。

| 箇所 | コード | メッセージ |
| --- | --- | --- |
| `.emet` の誤りのため読み込めない `.emet` から取り込んだ名前（並べた名前、別名、名前空間つきの名前）の、呼び出しと参照 | G02279 | `.emet の誤りのため、この名前を呼べません: <名前>` |
| G02272 になった名前の、呼び出しと参照 | G02280 | `ほかの @import と重なった名前を呼んでいます: <名前>` |
| マニフェストの無いファイルの評価で、変数のファイルと `.emet` から取り込んだ名前の、呼び出しと参照 | G02281 | `マニフェストの無いファイルでは、取り込んだ名前を解きません: <名前>` |
| プラグインの読み込みか検査の誤りのとき、未知のインラインのコマンド（今の G02022）、未知のブロックコマンド（今の G02009）、宣言されていないチャネル（今の G02090）の箇所 | G02282 | `プラグインの誤りのため、この名前のコマンドがあるかを決められません: <名前>` |

`<名前>` は、原稿に書いた名前である。
別名で取り込んだときは別名を、名前空間つきのときは `<名前空間>.<名前>` を書く。

それぞれ、元の誤りとは原因が別なので、別のコードにする。
G02279 は、今の実装が誤りの無い `.emet` も読み込めないものとして扱うので、誤りの無い `.emet` の名前の呼び出しにも出る。
そのため、メッセージにはパスを書かない。

箇所は、呼び出しか参照を含む式、インラインのコマンド、ブロックコマンドの一つごとに数える。
式の評価は今と同じく最初の誤りで止まるので、一つの式に二つの呼び出しがあっても、一つだけ出す。
`@set y = price` の式の中の参照も一つと数える。
その `@set` は今と同じく変数を定義せず、`y` の参照は今と同じく G02002 である。

G02279、G02280、G02282 の呼び出しは、今と同じく何も出力しない。
G02281 の参照を含む式は、今と同じく評価しない。

読み込めない `.emet` から並べた名前の G02276 と重なりの検査は、`.emet` の公開する名前が分からないので、今と同じく行わない。
これは、確かめられないことを報告しないためで、報告を減らすためではない。

### 呼ぶ先の分からない名前のあるまとまり

0459 の「そのまとまりでは G02011 と G02123 を出さない」を改める。
呼ぶ先の分からない名前のあるまとまりでも、ほかのまとまりと同じ規則で G02011 と G02123 を出す。
呼ぶ先の分からない名前は、今と同じく出すだけのコマンドとして扱う。
入れ子のまとまりにも、同じ規則を当てる。

### 文書

仕様書の、上の ADR の diagnostic を出さない記述を、この ADR に合わせて書き改める。
`docs/diagnostics.md` に G02279、G02280、G02281、G02282 を足し、G02009、G02011、G02022、G02090、G02123、G02272 の説明を直す。

採択したら、次の ADR のステータスに記録する。
どの記録も `"by":["docs/adr/0461-report-the-diagnostics-that-follow-from-another-error.md"]` を持つ。

- 0162：`{"part":"取り込み","kind":"replace"}`
- 0451：`{"part":"名前が重なったとき","kind":"replace"}`
- 0453：`{"part":"名前を探す順","kind":"supplement"}`
- 0455：`{"part":"マニフェストの無いファイルの評価","kind":"replace"}`
- 0458：`{"part":"不変条件の I9","kind":"replace"}` と `{"part":"別名の意味","kind":"supplement"}`
- 0459：`{"part":"コマンドの種類","kind":"replace"}`
- [golem-plugin ADR 0003](../golem-plugin/adr/0003-plugin-diagnostic-codes.md)：`{"part":"変更","kind":"replace"}`

## 実装しないこと

元の誤りの diagnostic は変えない。
続いて起きる箇所の出力（何も出力しない、式を評価しない）は変えない。
読み込めない `.emet` の公開する名前を推し量ることはしない。
誤りの無い `.emet` を読み込めるようにすることは、この ADR では扱わない。
式の評価を最初の誤りで止める決まりは変えない。

## 不変条件

- I1: 読み込めない `.emet` から取り込んだ名前の呼び出しか参照を含む、式、インラインのコマンド、ブロックコマンドの数を k とすると、G02279 はちょうど k 個出る。
- I2: G02272 になった名前の呼び出しか参照を含む、式、インラインのコマンド、ブロックコマンドの数を k とすると、G02280 はちょうど k 個出る。
- I3: マニフェストの無いファイルの評価で、取り込んだ名前の呼び出しか参照を含む、式、インラインのコマンド、ブロックコマンドの数を k とすると、G02281 はちょうど k 個出る。
- I4: プラグインの誤りのとき、今は G02022、G02009、G02090 を出さずにいる箇所の数を k とすると、G02282 はちょうど k 個出る。
- I5: 呼ぶ先の分からない名前のあるまとまりの G02011 と G02123 は、その名前を本体を受け取らない出すだけのコマンドに替えた原稿と同じに出る。
- I6: 元の誤りの diagnostic の数とコードは、この ADR の前と同じである。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| 型の誤りのある `.emet` から `{ total }` と、`[= total(1)]` を二回 | `.emet` の誤りと、G02279 が二つ | I1, I6 |
| 型の誤りのある `.emet` から `{ total }` と、`[= total(1) + total(2)]` | G02279 が一つ | I1 |
| 型の誤りのある `.emet` と誤りの無い `.emet` から一つずつ取り込み、両方を一回ずつ呼ぶ | G02279 が二つ | I1 |
| 型の誤りのある `.emet` を `* as s` で取り込み、`@s.f` を三回 | G02279 が三つ | I1 |
| 型の誤りのある `.emet` から `{ total as sum }` と `[= sum(1)]` | G02279 が一つ。名前は `sum` | I1 |
| 二つの `@import` が `{ n }` を並べ、`[n]` を一回 | G02272 が二つ、G02280 が一つ | I2, I6 |
| マニフェストの無いファイルの `{ price }` と `[= price]`、`[= price + 1]` | G02281 が二つ | I3 |
| マニフェストの無いファイルの `{ price }`、`@set y = price`、`[= y]` | G02281 が一つ、G02002 が一つ | I3, I6 |
| マニフェストの無いファイルの `.emet` の `{ total }` と `[= total(1)]` | G02281 が一つ | I3 |
| 読み込めないプラグインと、未知のインラインのコマンド二つ | G02282 が二つ | I4 |
| `@b`（読み込めない `.emet` の名前）、`@lang en`、`@toc`、段落 | G02011 が出る | I5 |
| `@label x`、`@b`、`@toc`、段落 | 今は出ない G02011 が出る | I5 |
| 読み込めた `.emet` の名前の呼び出し（どの `.emet` にも誤りが無い） | 今と同じ | I6 |

## 受けいれ条件

なし。
不変条件のテストで足りるためである。

## テスト設計

root ADR 0461 I1 から I6 を名前の先頭に置いたテストを、golem-eval と golem-evaluate（マニフェストの無いファイルの評価とプラグイン）に足す。
表の入力で、diagnostic のコードと数を数えて確かめる。
テストは、実装の前に書いて落ちることを確かめる。

## トレードオフ

元の誤りが一つでも、続いて起きる箇所の数だけ diagnostic が並ぶ。
`.emet` の一つに誤りがあれば、誤りの無い `.emet` の呼び出しにも G02279 が出るので、数は実際に呼べない箇所より多い。
元の誤りを直すと、続いて起きる diagnostic も消える。
書き手は、どの箇所が影響を受けるかを一度のビルドで知れるので、直した後に別の箇所の誤りが新しく見つかることが減る。

## 参考文献

- [docs/adr/0162](0162-calling-emet-functions-from-gm.md)
- [root ADR 0451](0451-import-listed-names-without-a-namespace.md)
- [root ADR 0453](0453-override-built-in-commands-by-listed-imports-and-plugins.md)
- [root ADR 0455](0455-resolve-variable-imports-through-the-import-graph.md)
- [root ADR 0458](0458-rename-listed-imports-with-as.md)
- [root ADR 0459](0459-take-the-next-block-as-the-body-without-indentation.md)
- [golem-plugin ADR 0003](../golem-plugin/adr/0003-plugin-diagnostic-codes.md)
- [golem-eval ADR 0003](../golem-eval/adr/0003-evaluation-diagnostic-codes.md)
