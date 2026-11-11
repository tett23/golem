# ADR 0332: 日本式トンボの G07002 で正の塗り足しを案内する

ステータス: 採択

## 文脈

日本式のトンボは、仕上がりの線と塗り足しの線の間隔で、紙をどこまで塗るかを示す。
二本の線が重なるため、塗り足しがゼロの PDF には日本式のトンボを付けられない。
このとき Golem は G07002 を出す。

[golem-pdf ADR 0004](../golem-pdf/adr/0004-crop-marks-and-bleed.md) の「診断」は、`style.toml` の `[page]` に `bleed` を書くよう案内する文言を定めた。
すでに `bleed = "0pt"` を書いた人が案内どおりにキーを確認しても、変えるべき値が分からない。

Golem [ADR 0319](0319-unitless-zero-in-length-fields.md) の提案は、長さのゼロを単位なしの整数 `0` でも表せるようにする。
Golem [ADR 0327](0327-screen-preflight-and-template.md) の提案は、画面向けの本を `golem new --screen` で作り、その本のひな形では塗り足しを省く。
二つの提案を試したところ、画面向けのひな形に `bleed = 0` を追記し、日本式トンボを指定した場合にも「bleed を書いてください」と表示された。
この文言は、既存の単位付きゼロ、提案中の単位なしゼロ、ひな形での省略のすべてに同じ修正を伝える必要がある。

## 実装すること

[golem-pdf ADR 0004](../golem-pdf/adr/0004-crop-marks-and-bleed.md) の「診断」が指定する G07002 のメッセージを次の文に変更する。

> 日本式のトンボには塗り足しが要ります。style.toml の [page] の bleed に 0 より大きい長さを書いてください

`docs/diagnostics.md` の G07002 のメッセージ欄に同じ文を載せ、`golem explain G07002` の出力にも反映する。
`3mm` は正の長さの一例であり、入稿先が求める塗り足しの最小値は別途プリフライト規則で指定する。

## 実装しないこと

日本式トンボを要求したか、PDF を対象にするか、塗り足しがゼロかという発行条件は従来のものを使う。
塗り足しの既定値、エラーの重大度と位置、画面向けの規則に例外を設ける変更は扱わない。
単位なしの長さを読む変更とひな形の追加は、それぞれの提案で扱う。

## 不変条件

1. **M1** PDF のトンボを検査する段階まで進んだ本で、日本式トンボを要求し、塗り足しの値がゼロなら G07002 のエラーを一つ出す。
   メッセージは上記の文と等しく、キーを省いた場合も明示した場合も同じである。
2. **M2** 有効な正の塗り足しがある場合、または PDF が対象にない場合は G07002 を出さない。
   日本式トンボを要求しない場合にも G07002 を出さない。
3. **M3** `golem explain G07002` に掲載するメッセージは、実際に発行する G07002 のメッセージと等しい。

| 日本式トンボ | 対象 | 塗り足し | 結果 |
| --- | --- | --- | --- |
| 指定 | プリフライトで組む PDF | 省略 | M1 |
| 指定 | 同上 | `"0pt"`、または単位なしゼロの提案を適用した `0` | M1 |
| 指定 | 同上 | `"3mm"` | M2 |
| 指定 | HTML だけをビルド | ゼロ | M2 |
| なし | プリフライトで組む PDF | ゼロ | M2 |

## テスト設計

[組み合わせの試験](../../experiments/integrated/check.mjs) の M1、M2、M3 を CLI で確かめる。
単位なしのゼロを入力した場合は通常の引数で実行し、既存の単位付きゼロは第 2 引数に `unitful` を渡す。
HTML だけを指定したビルドと、ゼロを `"3mm"` に書き換えて日本式トンボを指定したプリフライトが成功することを確かめる。

```sh
cabal build golem-cli:exe:golem --offline -j2
node experiments/integrated/check.mjs "$(cabal list-bin golem-cli:exe:golem)"
node experiments/integrated/check.mjs "$(cabal list-bin golem-cli:exe:golem)" unitful
```

統合直後の CLI は [20 件中 17 件](../../experiments/integrated/merged-red.jsonl) で期待値と一致した。
一致しなかったのは M1 の省略と明示の二件、および M3 の説明の一件である。
発行箇所と説明を直した後は、[単位なしゼロの 20 件](../../experiments/integrated/green.jsonl) と [単位付きゼロの 20 件](../../experiments/integrated/unitful-green.jsonl) がすべて一致した。
実際に画面向けの本を使い、塗り足しを `"3mm"` に変えて同じ日本式トンボを付けると、プリフライトが終了コード 0 を返した。

## トレードオフ

省略時だけ「キーを足す」、ゼロを明示したときだけ「値を変える」と出し分けるには、キーがあったかを組版まで渡す必要がある。
塗り足しの値を正にするという同じ修正を示せば、どちらも一文で案内できる。

## 参考文献

- [従来のメッセージと発行条件](https://github.com/tett23/golem/blob/0a8d21a091d830573fb6229111ed744f74162afd/docs/golem-pdf/adr/0004-crop-marks-and-bleed.md#L163-L167)
- [check で PDF も検査する変更](../golem-pdf/adr/0010-golem-check-g0702-and-template-bleed.md)
- [単位なしゼロと塗り足しを省くひな形を試した結果](../../experiments/integrated/README.md)
