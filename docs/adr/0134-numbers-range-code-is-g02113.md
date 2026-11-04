# ADR 0134: コードブロックの `numbers` に書いた範囲は G02113 とする

ステータス: 採択

## 文脈

コードブロックの `numbers` に範囲を書いたときのコードを、二つの ADR が違うように決めている。

- [docs/adr/0113](0113-closed-range-literal.md) の「`numbers`」の節は、`numbers=5-5`、`numbers=5...5`、`numbers=[= 1...3]` を「`numbers` の値が正しくない」G02069 にすると決め、テスト設計にも同じ三つを書いた。
- [docs/adr/0111](0111-argument-words-as-number-literals.md) は、自然数を求める箇所の `<数のリテラル>...<数のリテラル>` の語と、範囲を受け取らない組み込みのコマンドの引数に届いた範囲の値を、G02113 にすると決めた。`numbers` は自然数を求める箇所なので、この規則に当たる。

[docs/adr/0111](0111-argument-words-as-number-literals.md) の文脈は「[ADR 0113](0113-closed-range-literal.md) は、範囲を受け取らない引数に範囲の値を渡したときのコードを決めていない」と書くが、`numbers` については決めていた。
この前提の誤りのため、[docs/adr/0111](0111-argument-words-as-number-literals.md) は `numbers` を一度も挙げず、二つの ADR の食い違いに気づかないまま採択された。

[docs/adr/0111](0111-argument-words-as-number-literals.md) を実装した PR #479 は、`numbers=5...5` と `numbers=[= 1...3]` を G02113 にした（[`numbersArg`](https://github.com/tett23/golem/blob/97be81e8de344a22a15079b2e56bf0e5ce20ea62/modules/golem-eval/src/Golem/Eval/File.hs#L2331-L2354)、[`naturalArg` の語の範囲](https://github.com/tett23/golem/blob/97be81e8de344a22a15079b2e56bf0e5ce20ea62/modules/golem-eval/src/Golem/Eval/File.hs#L2178)、[RangeSpec.hs の 186 行め](https://github.com/tett23/golem/blob/97be81e8de344a22a15079b2e56bf0e5ce20ea62/modules/golem-eval/test/RangeSpec.hs#L186)）。
実装者はこれを逸脱として申告し、[docs/adr/0113](0113-closed-range-literal.md) のステータスの行に「`numbers` に書いた `...` の範囲のコード（G02069 から G02113 に）は [ADR 0111](0111-argument-words-as-number-literals.md)」を足した。
[docs/adr/0111](0111-argument-words-as-number-literals.md) にその指示はない。

2026-11-04 の監査（[docs/audits/2026-11-04-rc4-plugin-adr-conformance.md](../audits/2026-11-04-rc4-plugin-adr-conformance.md) の F-13）は、実装の判断を妥当としたうえで、二つの ADR が同じ入力に別のコードを与えている状態を記録に残すよう求めた。
この ADR は、どちらの規則が今の振る舞いかを決める。

## 実装すること

### 規則

コードブロックの `numbers` に書いた範囲は、語でも式でも G02113 とする。
[docs/adr/0111](0111-argument-words-as-number-literals.md) の規則が、[docs/adr/0113](0113-closed-range-literal.md) の「`numbers`」の節のうち範囲の二つの例に優先する。

| 原稿 | [docs/adr/0113](0113-closed-range-literal.md) | 今の main とこの ADR |
| --- | --- | --- |
| `numbers=5...5` | G02069 | G02113 |
| `numbers=[= 1...3]` | G02069 | G02113 |
| `numbers=5-5` | G02069 | G02069 |
| `numbers=5`、`numbers=[= 5]`、`numbers=true` | なし | なし |

`numbers=5-5` は、[docs/adr/0111](0111-argument-words-as-number-literals.md) の規則では範囲の語ではなく、数として読めない語である。
自然数を求めるほかの箇所の数でない語と同じく、その箇所のコード（`numbers` なら G02069）のままとする。

### 理由

- **一つの原因に一つのコード**：`@blank-line 1...3`、`[number-text 1...3]`、`numbers=1...3` は、どれも「範囲を受け取らない引数に範囲を書いた」という同じ原因である。`numbers` だけを G02069 にすると、同じ原因が箇所によって二つのコードに分かれる。
- **G02069 の広さ**：G02069 は「コードブロックのキーの値が正しくない」で、`numbers` の数でない値、`highlight` のコードにない行、ほかのキーの誤りをまとめている。範囲を書いた誤りは、その中でも直し方（範囲ではなく一つの数を書く）が決まっている。G02113 の「直し方」の節がそのまま当てはまる。
- **出した書き方は変わらない**：rc3 の `numbers` は数字だけの語を受け取り、`5...5` を書けなかった。G02069 と G02113 のどちらでもエラーであり、通っていた原稿が通らなくなることはない。

### コードと文書

コードは変えない。
今の main が、この ADR の規則のとおりに振る舞う。

- [docs/adr/0113](0113-closed-range-literal.md) のステータスの行は、PR #479 が足した句を、この ADR を指す句に改める。たとえば「`numbers` に書いた `...` の範囲のコード（G02069 から G02113 に）は [ADR 0111](0111-argument-words-as-number-literals.md) と [ADR 0134](0134-numbers-range-code-is-g02113.md)」とする。
- [docs/adr/0111](0111-argument-words-as-number-literals.md) のステータスの行に、「範囲を受け取らない箇所に `numbers` を含むことは [ADR 0134](0134-numbers-range-code-is-g02113.md)」を足す。
- docs/diagnostics.md の G02069 と G02113 の「意味」、docs/markup.md の「`numbers`」の段落（今の 1092 行め）は、すでにこの規則で書かれている。G02069 と G02113 の ADR の欄にこの ADR を足す。
- docs/diagnostics.md の G02069 の「主な原因」は「`numbers` に範囲か数でない語……を書いた」と書き、`...` の範囲もこのコードの原因と読める。「`numbers` に `-` で区切った範囲か数でない語」に改める。

## 実装しないこと

- `numbers` に範囲を受け取らせること（`numbers=5...7` を 5 から始まる番号として読むなど）。[docs/adr/0113](0113-closed-range-literal.md) が `numbers` を範囲の読み取りから外した判断は変えない。
- `numbers=5-5` を G02113 にすること。`-` の範囲は廃止予定の書き方で、範囲を受け取る箇所（`lines`、`highlight`）でだけ範囲として読む。範囲を受け取らない箇所で `-` を範囲として読み始めると、廃止予定の書き方を受け付ける箇所が広がる。
- [docs/adr/0111](0111-argument-words-as-number-literals.md) の文脈の誤りを、その ADR の本文で直すこと。コミット済みの ADR は書き換えない。この ADR が訂正の記録である。

## テスト設計

コードを変えないので、新しいテストは書かない。
今のテストが、この ADR の規則を固定している。

- golem-eval の `RangeSpec`：`numbers=5-5` が G02069、`numbers=5...5` と `numbers=[= 1...3]` が G02113、`numbers=5`、`numbers=[= 5]`、`numbers=true` が誤りにならない（[RangeSpec.hs の 184 行めから 188 行め](https://github.com/tett23/golem/blob/97be81e8de344a22a15079b2e56bf0e5ce20ea62/modules/golem-eval/test/RangeSpec.hs#L184-L188)）。

ステータスの行と文書を直した後、`adr-guard links` と `adr-guard check-status` が通ることを確かめる。

## トレードオフ

採択済みの ADR の明示の決定を、後の ADR の一般の規則が黙って上書きした状態を、事後に追認することになる。
追認せずに [docs/adr/0113](0113-closed-range-literal.md) に戻す（`numbers` の範囲を G02069 にする）案もある。
戻すと、範囲を受け取らない箇所のうち `numbers` だけが別のコードになり、「一つの原因に一つのコード」に反する。
今の振る舞いを変える理由はなく、変えれば利用者の見るコードがもう一度変わるので、追認を選ぶ。

この食い違いは、ADR を書くときに、範囲を受け取らない箇所を列挙して先の ADR と照らし合わせていれば防げた。
[docs/adr/0111](0111-argument-words-as-number-literals.md) の文脈は「決めていない」と断定したが、その根拠に [docs/adr/0113](0113-closed-range-literal.md) の該当の節を引いていなかった。

## 決めたことの記録

- **採択**：メンテナーが、この ADR の案のとおり採択した（2026-11-04）。

## 参考文献

- [docs/audits/2026-11-04-rc4-plugin-adr-conformance.md](../audits/2026-11-04-rc4-plugin-adr-conformance.md)（F-13）
