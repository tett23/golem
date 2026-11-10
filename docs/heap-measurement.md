# 最大常駐を条件にする変更の測り方

最大常駐を条件にする ADR では、ヒープのプロファイルから、生きているデータの山を測る。
山とは、プロファイルの標本ごとの合計の最大である。
測り方は [Golem ADR 0306](adr/0306-measure-the-residency-of-forcing-a-table-by-heap-profiles.md) に従う。
この文書は共通の手順であり、測定結果は `docs/benchmarks/` の新しい記録に置く。

## 測定の準備

比較する二つのコミットと入力を、測定前に決める。
[Golem ADR 0306](adr/0306-measure-the-residency-of-forcing-a-table-by-heap-profiles.md) の表の検証では、前は `ff5d9b118f3aa1910bfa763a27f52e30ce736a85`、後は `2e074342c2a5473016bec162c79b0c9c6224a560` とする。
ほかの変更では、その ADR が指定するコミットと入力を使う。

二つの作業ツリーの `cabal.project.local` に、次の設定を加えてビルドする。
製品の RTS の設定は変えず、測る実行ファイルだけで RTS オプションを受け取れるようにする。

```cabal
package golem-cli
  ghc-options: -rtsopts
```

## 測定と比較

PDF のビルドを、次の RTS オプションで走らせる。
`-N` は製品と同じく有効のままにする。

```sh
golem build --target pdf +RTS -hT -i0.01 -A1m -s -RTS
```

入力ごとに前と後を交互に 3 回ずつ走らせ、各回の山を求める。
前の 3 回と後の 3 回からそれぞれ中央値を取り、後を前で割る。
[Golem ADR 0306](adr/0306-measure-the-residency-of-forcing-a-table-by-heap-profiles.md) の表の検証の上限は 1.05 である。
ほかの変更の許容値と、条件を満たさなかったときの扱いは、その ADR で定める。

各回の `.hp` と、標準エラーに出る `-s` の統計を別々のファイルに保存する。
終了コードと出力のハッシュも記録する。
出力の一致を条件にするかは、それぞれの ADR で定める。
[Golem ADR 0306](adr/0306-measure-the-residency-of-forcing-a-table-by-heap-profiles.md) の表の検証では、前後の出力が一致することを確かめる。
記録には、各回の値、中央値の比、山の標本の上位の型を載せる。

集計の確かめ方も、それぞれの ADR に書く。
[Golem ADR 0306](adr/0306-measure-the-residency-of-forcing-a-table-by-heap-profiles.md) は、c10-r2000 の一回で、同じ実行の `.hp` の山と `-s` の maximum residency が 1% 以内で一致することを確かめる。
また、36 回の割り当てを元の記録の表 1 と比べ、差が 1% 以内であることを確かめる。
これらは [Golem ADR 0306](adr/0306-measure-the-residency-of-forcing-a-table-by-heap-profiles.md) が指定した検査であり、ほかの入力や比較元の記録がない測定に、そのまま当てはめる条件ではない。

## 値の読み方

この手順の山は、標本の間にある短い山を見落とすことがある。
また、`-A1m` は製品の `-A64m` と異なり、並列の評価の進み方によって、同時に生きるデータの量が変わりうる。
測定値を真の最大とみなさず、これらの制約とともに読む。

プロファイルを取らない `-s` の maximum residency は、GC の時点に左右される。
割り当てを減らした変更では、前後で標本の時点がずれるため、その値だけで保持の増減を判断しない。
RTS が OS から取った total memory in use も、この手順の山とは別の値である。

過去の測定記録は書き換えない。
測り直しや追加の検証は、新しい記録として残す。
