# ADR 0312: 整数で長さの換算と見出しの丸めを確かめる

ステータス: 採択

## 文脈

Golem [ADR 0311](0311-enumerate-source-position-conversions.md) の試作は、製品の変換を別の計算で照合した。
長さでも同じ方法を使える。
Golem の長さの内部単位 sp は 1 pt の 65536 分の 1 である。
見出しでは、行送りを sp に丸めた後、それを収める本文の行数を決める。

## 実装すること

絶対長の各単位で、換算結果が半 sp の整数倍になる有理数を作る。
負数を含めて最も近い整数を求め、距離が等しければ偶数を選ぶ。
見出しでは、丸めた行送り、必要な最小行数、上下の余白という出力の条件を調べる。
SBV はテストの依存に加えない。

PR の上限は、[ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md) の時間の予算に照らして決める。
試作の件数は、この上限を決めるための候補である。

## 実装しないこと

任意の整数についての定理証明や、画面に表示する小数文字列の網羅は対象外とする。

## 不変条件

1. L1：pt、mm、in、Q、H の半 sp 境界で、最寄りの sp が二つあれば偶数を返す。
2. L2：見出しの行送りは厳密な値から半 sp 以内であり、半 sp 離れた場合は偶数となる。
3. L3：見出しの占める行数は、指定した最小行数以上で見出しを収める最小の値となり、上下の余白の差は 0 か 1 sp となる。

| 境界の入力 | 期待する結果 |
| --- | --- |
| −1.5 sp、−0.5 sp | −2 sp、0 sp |
| 0.5 sp、1.5 sp | 0 sp、2 sp |
| 見出しが領域にちょうど収まる | 上下の余白は 0 |
| 領域に 1 sp 余る | 上の余白は 0、下は 1 sp |

## テスト設計

未コミットの `experiments/formal/Length.hs:8` を `experiments/formal/compile.sh experiments/formal/Length.hs` で実行した。
絶対長は分子 −32 から 32 の 65 通りを 5 単位で調べた。
見出しでは本文サイズ 1 から 4 sp、本文の行送りは本文サイズから 6 sp、見出しサイズ 1 から 8 sp、行数と最小行数は 1 から 3 とした。
325 個の換算と 1296 個の見出しで終了コード 0 を得た。
本実装では L1 を golem-length、L2 と L3 を golem-layout のテスト名に付ける。

ちょうど半分なら常に切り上げる対照は、L1 の偶数丸めで失敗した。
再現には試作のルートで `experiments/formal/mutations.sh` を使う。

## トレードオフ

SBV を使えば上限を広げるための別の手段になるが、試作の述語は有理数と整数の演算だけで既存の関数に直接適用できた。
列挙の上限を越えた整数については、本提案の結果から結論を出せない。

## 参考文献

- [単位と sp の換算](https://github.com/tett23/golem/blob/2b7d1dffe359e065bf5e899a2df6cab85704905d/modules/golem-length/src/Golem/Length.hs#L39)
- [見出しの行送りと高さ](https://github.com/tett23/golem/blob/2b7d1dffe359e065bf5e899a2df6cab85704905d/modules/golem-layout/src/Golem/Layout/Paginate.hs#L75)
