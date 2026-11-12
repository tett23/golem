# ADR 0354: 表ファイルの先頭に続く BOM を一度の整形ですべて取り除く

ステータス: 採択（未実装）

## 文脈

Golem [ADR 0211](0211-record-what-implementations-decided-found-by-the-review-of-2026-11-08.md) は、表ファイルの先頭に BOM（U+FEFF）が二つ続くとき、一度の整形で一つ取り除くと定めた。
Golem [ADR 0351](0351-prove-parser-formatter-round-trips.md) の不変条件 9 は、一度整形した表が二度目の整形で変わらないことを求める。

## 調査した事項

CSV の先頭に UTF-8 の BOM を二つ置き、実際の `golem fmt` を二度実行した。
先頭のバイト列を調べると、一度目の出力には BOM が一つ残り、二度目で消えた。
原稿の整形の前処理も、表の整形に使う `formatTable` を呼んでいる。

## 実装すること

CSV と TSV の整形では、ファイルの先頭から連続する U+FEFF を最初の一度ですべて取り除く。
残った部分には Golem [ADR 0186](0186-fmt-table-files.md) の改行変換を適用する。
Golem [ADR 0351](0351-prove-parser-formatter-round-trips.md) のセル値の保存では、先頭に続く二つ目以降の BOM を例外とする。
表の読み手は先頭の BOM を一つ読み飛ばすため、整形前に最初のセルの文字として読めた二つ目以降の BOM は、整形後のセルから消える。

## 実装しないこと

表を読み込むだけの操作や、原稿ファイルの BOM の扱いは変更の対象外とする。

## 不変条件

1. 表の先頭に続く BOM の個数にかかわらず、一度の整形で先頭の BOM はすべて消える。
2. 先頭の連続部分を過ぎた U+FEFF は、個数も順序も保つ。
3. 表を二度整形した結果は一度目の結果とバイト単位で一致する。

表中の B は U+FEFF 一文字を表す。

| 入力 | 一度目の出力 | 二度目の出力 |
| --- | --- | --- |
| 空 | 空 | 空 |
| B または BB | 空 | 空 |
| a | a | a |
| Ba または BBBa | a | a |
| BBaBBb | aBBb | aBBb |
| "Ba",b | "Ba",b | "Ba",b |

## テスト設計

不変条件 1〜3 を単体試験で検査する。
CSV と TSV を参照する原稿で通常の CLI を起動し、整形前後で表ファイルのバイト列と最初のセルの値を照合する。
二度目の整形で差が出ないことと、原稿ファイルの先頭の BOM を一つだけ取り除く既存の試験も確認する。

## トレードオフ

先頭のセルの値を U+FEFF から始めたい CSV では、セルを引用符で囲むと先頭の内容を保てる。
TSV でファイルの先頭に直接書いた U+FEFF はすべて整形で消える。

## 参考文献

- [Golem ADR 0186](0186-fmt-table-files.md)
- [Golem ADR 0211](0211-record-what-implementations-decided-found-by-the-review-of-2026-11-08.md)
- [Golem ADR 0351](0351-prove-parser-formatter-round-trips.md)
