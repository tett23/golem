# ADR 0007: コマンドと式の記号にも semantic tokens を付ける

ステータス: 採択

## 文脈

[golem-lsp ADR 0006](0006-semantic-tokens-highlighting.md) は、`.gm` の色付けを semantic tokens で返すと決め、地の文、散文スロットの中身、コードブロックの中身、構文エラーの箇所にはトークンを作らないとした。
コマンドと式の記号のうち、どれにトークンを付けるかは決めていない。

Golem のエディタの Aleph（https://github.com/tett23/aleph）は、`.gm` の命令と式を等幅のフォントで、散文を本文のフォントで出す（[tett23/aleph ADR 0006](https://github.com/tett23/aleph/blob/96d97b8/docs/adr/0006-horizontal-editor.md)）。
その区別を semantic tokens の型から決めるとし、型だけで決められない箇所があれば Golem に型か修飾子を足すよう依頼するとしている（[tett23/aleph ADR 0009](https://github.com/tett23/aleph/blob/96d97b8/docs/adr/0009-lsp-and-formatting.md)）。

golem 0.1.0-rc3 の `golem lsp` に、次の行を `textDocument/semanticTokens/full` で求めた（2026-11-07）。

```
[ruby: 霧笛|むてき]は[= book.liters(12)]リットル。[book.stamp 赤]消印
```

返ったトークンは、`ruby`（function）、`|`（operator）、`[=`（keyword）、`book`（function）、`12`（number）、`book.stamp`（function）、`赤`（string）だった。
次の文字にはトークンがなかった。

- インラインのコマンドの `[`、`:`、`]`
- 式の `.liters`（呼び出す関数の名前の続き）、`(`、`)`、閉じの `]`

このため、トークンだけでは、コマンドと式の範囲（等幅にする範囲）が決まらない。
Aleph は今、トークンの付いた範囲と、Aleph 自身の簡単な字句の読み方で命令と式とした範囲を合わせて等幅にしている。

## 実装すること

- インラインのコマンドの `KLBracket`、`KColon`、`KRBracket`（`NInlineCommand` の直下）に `operator` を付ける。散文スロットの区切りの `|` は今と同じ `operator` とする。
- 式（`NExpr`）の中で今トークンのない記号（`KDot` とその後の名前、括弧、閉じの `]`）にトークンを付ける。名前の続きは呼び出しの名前と同じ `function`、記号は `operator` とする。
- これで、コマンドと式の中では、散文スロットの中身を除くすべての文字がどれかのトークンに入る。散文スロットの中身にトークンを付けない決まりは変えない。

## 実装しないこと

- 地の文や散文スロットの中身へのトークン。
- 新しい型や修飾子。標準の型の `operator` と `function` で足りる。

## テスト設計

- 上の行の semantic tokens を求め、`[`、`:`、`]`、`.liters`、`(`、`)` にトークンがあり、`霧笛`（散文スロット）とその後の地の文にはないことを確かめる。
- 複数行にまたがる散文スロットと、入れ子のコマンドで、行ごとに分けたトークンが重ならないことを確かめる。

## トレードオフ

- トークンの数が増え、応答が少し大きくなる。[golem-lsp ADR 0005](0005-keystroke-latency-and-ordered-evaluation.md) のキー入力の目標を守るか、測って確かめる必要がある。

## 参考文献

- [golem-lsp ADR 0006](0006-semantic-tokens-highlighting.md)
- tett23/aleph の仕様書の「LSP と整形」：https://github.com/tett23/aleph/blob/96d97b8/docs/specifications.md
