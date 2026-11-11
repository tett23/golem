# ADR 0311: 短い文字列で UTF-16 の列とページの開始位置を照合する

ステータス: 採択（未実装）

## 文脈

Golem [ADR 0310](0310-enumerate-parser-formatter-round-trips.md) の試作では、同じ見出しの前に置く文字によって diagnostic のバイト位置が変わった。
一方、[ADR 0195](0195-page-start-positions-of-pdf.md) の `pages.json` は、原稿内の位置を UTF-16 の列で書く。
この二つを混同すると、絵文字の後の文字をエディターで選べない。

## 実装すること

長さ 0 から 3 の文字列を ASCII、漢字、絵文字、改行の 4 文字から生成する。
これに家族絵文字（👨‍👩‍👧‍👦）を単独で置いた原稿、前後に文字を置いた原稿、改行を挟んで二度置いた原稿を加える。
家族絵文字は 4 個の補助平面の文字と、その間の 3 個のゼロ幅接合子（ZWJ、U+200D）からなる。
各文字境界で UTF-8 のバイト数を数え、最後の改行からその位置までを UTF-16LE に変換したバイト数の半分を列の期待値とする。
同じ文字列とバイト位置を LSP の変換関数と `pagesJson` に渡す。
LSP では UTF-8 の交渉結果も調べる。

PR の上限は、[ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md) の時間の予算に照らして決める。
試作の件数は、この上限を決めるための候補である。

## 実装しないこと

結合した絵文字をエディターがどう描くかは扱わない。
位置を照合する単位は Unicode のコードポイント境界である。
`pages.json` に渡すバイト位置は、原稿に存在する文字境界に限る。

## 不変条件

1. U1：有効な境界から LSP の位置へ変換して戻すと、UTF-8 と UTF-16 のどちらでも元のバイト位置になる。
2. U2：`pages.json` の行と列は、独立に求めた 0 始まりの行と UTF-16 の列に一致する。
3. U3：絵文字のサロゲートペアの間を指定すると LSP の逆変換は `Nothing` を返す。

| 境界の入力 | 期待する結果 |
| --- | --- |
| 空文字列の末尾 | 行 0、列 0 |
| `a😀` の末尾 | UTF-8 の列は 5、UTF-16 の列は 3 |
| `a😀` の UTF-16 列 2 | `Nothing` |
| 👨‍👩‍👧‍👦 の途中と末尾 | UTF-8 の境界 0、4、7、11、14、18、21、25 が UTF-16 の列 0、2、3、5、6、8、9、11 に対応する |
| 家族絵文字の UTF-16 列 1、4、7、10 | いずれもサロゲートペアの内側なので `Nothing` |
| 改行だけの原稿の末尾 | 行 1、列 0 |

## テスト設計

未コミットの `experiments/formal/Position.hs:12` を `experiments/formal/compile.sh experiments/formal/Position.hs` で実行した。
短い文字列 85 件の 313 境界に、家族絵文字を含む 3 件の 36 境界を加えた。
計 88 件の 349 境界で U1 から U3 を照合し、終了コードは 0 だった。
測定値は `experiments/formal/review-results.txt` にある。
本実装では U1 から U3 をテスト名に付ける。
既存の LSP の行末を越えた列を行末へ寄せる規則は、サロゲートペアの内側とは別のテストで守る。

期待する列を UTF-8 のバイト数に変えると、漢字と絵文字を含む原稿で失敗した。
再現には試作のルートで `experiments/formal/mutations.sh` を使う。

## トレードオフ

独立した期待値は短い接頭辞を毎回エンコードする。
この範囲では入力が小さく、製品の行索引を期待値の計算にも使って同じ誤りを見逃すことを避けられる。

## 参考文献

- [文字位置の変換](https://github.com/tett23/golem/blob/2b7d1dffe359e065bf5e899a2df6cab85704905d/modules/golem-syntax/src/Golem/Syntax/Position.hs#L101)
- [LSP の行末の扱い](https://github.com/tett23/golem/blob/2b7d1dffe359e065bf5e899a2df6cab85704905d/modules/golem-lsp/src/Golem/Lsp/Features.hs#L79)
- [ページの JSON](https://github.com/tett23/golem/blob/2b7d1dffe359e065bf5e899a2df6cab85704905d/modules/golem-typeset/src/Golem/Typeset/Pages.hs#L64)
