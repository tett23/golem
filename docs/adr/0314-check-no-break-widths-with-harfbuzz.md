# ADR 0314: 実際の書体の送りで改行しない範囲の箱の幅を確かめる

ステータス: 採択（未実装）

## 文脈

[ADR 0305](0305-leave-soft-hyphens-in-or-next-to-a-no-break-range-out-of-i8.md) の S1 は、ソフトハイフンが改行しない範囲に接するとき、同じテキスト内で分かれた箱をつなぐ。
両側の送りを足した値と、つないだ文字列を組んだ送りは異なる場合がある。
S1 の既存の列挙に、実際に書体から求めた語の送りを渡す。

## 実装すること

テストで同梱の Source Sans Pro、Source Serif Variable、Source Han Sans のサブセットを読み、HarfBuzz が返す横送りの合計を、書体の 1 em の単位数で割る。
語の送りを組版環境と S1 の述語の双方に渡す。
既存の 13 部品の内外を区別した長さ 0 から 2 の列を調べる。
さらに `A`、`V`、`f`、`i`、ソフトハイフンの内外を区別した長さ 0 から 3 の列を調べる。
後者では、ソフトハイフンを挟む 2 文字を結合したときの幅の差が現れる。

PR の上限は、[ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md) の時間の予算に照らして決める。
試作の件数は、この上限を決めるための候補である。

## 実装しないこと

書体をネットワークや OS の設定から取得する処理、縦組の送り、別の書体への切り替えは対象外とする。

## 不変条件

1. H1：基準にする Source Sans Pro で組んだ `AV` の送りは、別々に組んだ `A` と `V` の送りの和と異なる。
2. S1：範囲を無効にした結果から [ADR 0305](0305-leave-soft-hyphens-in-or-next-to-a-no-break-range-out-of-i8.md) の手順で得た項目列と、範囲を有効にして組んだ項目列が一致し、結合した箱の幅には同じ環境の語の送りによる補正を含む。

| 境界の入力 | 期待する結果 |
| --- | --- |
| 部品なし | 二つの項目列が一致する |
| `A` と `V` を別々に計測 | 結合して計測した値と差がある |
| 範囲内の `A`、ソフトハイフン、`V` | ソフトハイフンを除いた語の送りで照合する |
| ソフトハイフンが範囲のすぐ外側 | 元の S1 の境界判定を使う |

## テスト設計

未コミットの `experiments/formal/Shape.hs:11` が書体を読み、`modules/golem-layout/test/NoBreakEnum.hs:439` が列挙する。
`experiments/formal/compile.sh -imodules/golem-layout/test experiments/formal/Shape.hs` は各書体 1814 入力、合計 5442 入力で終了コード 0 だった。
二つの列挙に共通する入力も、それぞれ 1 件に数えた。
いずれも 1 em が 1000 単位だった。
表の送りの差は、まとめて組んだ送りから、一文字ずつ組んだ送りの和を引いた値である。
「日」のグリフ ID が 0 の書体では、その文字に対応するグリフがなかった。
測定値は `experiments/formal/review-results.txt` にある。

| 同梱の書体 | AV の送りの差 | fi のグリフ数 | 日のグリフ ID | S1 |
| --- | ---: | ---: | ---: | ---: |
| Source Sans Pro | −14 | 2 | 0 | 1814 件成功 |
| Source Serif Variable | −130 | 1 | 0 | 1814 件成功 |
| Source Han Sans のサブセット | −15 | 1 | 3949 | 1814 件成功 |

この試作では組み合わせの送り、合字、漢字の収録の違いがある書体を選んだ。
3 書体は当面の比較対象であり、書体の性質を網羅する数は決めていない。
本実装では H1 と S1 をテスト名に付ける。
この試作は語の送りを差し替えたもので、各文字の送りやルビの送りまで実書体を使う検査は未実施である。

幅の補正を外す対照では、範囲内の `A`、ソフトハイフン、`V` の箱を 694026 sp と見積もり、実際の 684851 sp と一致しなかった。
再現には試作のルートで `experiments/formal/mutations.sh` を使う。

## トレードオフ

実書体の依存はテストに限り、golem-layout のライブラリがフォントを読み込む必要はない。
書体を更新すると H1 の差がなくなる可能性があるため、H1 を単独でも実行して試験入力が幅補正を通ることを確かめる。

## 参考文献

- [語の送りによる幅の補正](https://github.com/tett23/golem/blob/2b7d1dffe359e065bf5e899a2df6cab85704905d/modules/golem-layout/test/NoBreakEnum.hs#L224)
- [HarfBuzz の結果の単位と座標](https://github.com/tett23/golem/blob/2b7d1dffe359e065bf5e899a2df6cab85704905d/modules/golem-font/src/Golem/Font.hs#L230)
