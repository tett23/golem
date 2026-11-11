# ADR 0322: 数に関する diagnostics を実装の型と境界の入力で確かめる

ステータス: 採択（未実装）

## 文脈

数の表示を丸めることと、丸めた結果を diagnostic の判定に使うことは異なる。
[golem-eval ADR 0006](../golem-eval/adr/0006-exact-power-limit-before-range.md) は累乗の上限を調べるときの近似を正確な判定に変えた。
ほかの diagnostic にも同じ変更が要るかを調べるには、判定に達する数の型と、境界の両側に置いたときの結果が要る。

試作の `node experiments/diagnostics/survey.mjs` は固定したコミットの Haskell のソースから、浮動小数点の型、変換、有限性の判定と、平方根や丸めの候補を抽出する。
CBOR はデータをバイト列にする形式である。
CBOR を読む箇所は非有限の値を拒み、有限の値を有理数に変える。
マニフェストの変数を読む箇所は TOML の浮動小数点数を拒む。
これらの箇所には、近似した計算値をしきい値と比較する処理は見つからなかった。

## 実装すること

プリフライトの G09006 を回帰テストに加える。
G09006 は画像を置いた寸法から求めた解像度が指定値に足りないときの diagnostic である。
ピクセル数を整数、インチで表した長さを有理数として割り、小数点以下を切り捨てた ppi をしきい値と比較する。

新たに近似が疑われる箇所は、入力のバイト列、正確な値、各実行環境の diagnostics を残して調べる。
同一の入力で結果が異なったときは、仕様書の既知の不具合に記録し、その判定だけを変える ADR を作る。

## 実装しないこと

ソースで丸めを使うという理由だけで、その丸めを除かない。
今回の調査では native と WASM の diagnostics が異なる新たな入力は未確認である。
個別の不具合として仕様書に載せる入力はまだない。

## 不変条件

1. A1：有限で正の配置寸法について、実効解像度の整数値が正のしきい値未満のときだけ G09006 を得る。
2. A2：入力と設定が一致すれば、native と WASM で G09006 の重大度、位置、`facts.ppi` は一致する。

| 実効解像度 | しきい値 | G09006 |
| --- | --- | --- |
| 1 ppi | 0（検査を外す） | なし |
| 1 ppi | 1 | なし |
| 1 ppi | 2 | あり |

## テスト設計

`experiments/diagnostics/baseline.mjs` はリポジトリの小さい JPEG を実際の PDF に配置し、しきい値を一つずつ変える。
各入力を native CLI で三度ずつ試すと、しきい値 0、1、2 の diagnostics の件数はそれぞれ 0、0、1 だった。
各しきい値で三度の diagnostic は一致した。
`expected.mjs` の A1 がこの九回を比較する。
A2 の受け入れ時には `golem-preflight:test:golem-preflight-test` に共通のページ情報としきい値を渡し、同じ diagnostic の期待値を native と wasm32 の両方で照合する。
このスイートは `sh scripts/ci/test-suites.sh wasm` に含まれる。
公開した WASM の呼び出し口は PDF のビルドに限られ、プリフライトを直接呼べない。
基準コミットの WASM で `run.mjs preflight` は使い方を返し、終了コードは 2 だった。
試作では `modules/golem-preflight/test/Main.hs` に A2 を書き、GHC 9.10.3 の native 版で一件成功した。
wasm32 で同じテストを走らせる検証は残っている。
字形の選択する外部ライブラリと実行環境ごとの結果まで、この抽出だけで検証できない。

## トレードオフ

境界をまたぐ小さな入力なら、出力の違いが画像の判定に由来するかを調べやすい。
語の検索は候補収集には使えるが、型推論を経た値や外部関数から返る値は呼び出し側まで読む必要がある。

## 参考文献

- [WASM の試料を取得した CI](https://github.com/tett23/golem/actions/runs/42892137240)
- [同じテストを wasm32 でビルドするジョブ](https://github.com/tett23/golem/blob/0a8d21a091d830573fb6229111ed744f74162afd/.github/workflows/wasm-tests.yml#L224-L238)
- [画像の解像度の計算](https://github.com/tett23/golem/blob/0a8d21a091d830573fb6229111ed744f74162afd/modules/golem-preflight/src/Golem/Preflight.hs#L98-L108)
- [G09006 のしきい値の比較](https://github.com/tett23/golem/blob/0a8d21a091d830573fb6229111ed744f74162afd/modules/golem-preflight/src/Golem/Preflight.hs#L221-L239)
- [CBOR の数を読む処理](https://github.com/tett23/golem/blob/0a8d21a091d830573fb6229111ed744f74162afd/modules/golem-doc/src/Golem/Doc/Cbor.hs#L319-L329)
