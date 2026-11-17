# 家族絵文字と三つの同梱書体

Golem [ADR 0311](../../docs/adr/0311-enumerate-source-position-conversions.md) の試作を家族絵文字に、Golem [ADR 0314](../../docs/adr/0314-check-no-break-widths-with-harfbuzz.md) の S1 を三つの同梱書体に広げた。
パッケージデータベースを用意する手順は `compile.sh` の冒頭にある。
`realProbe` を追加する差分がまだない作業ツリーでは、次の最初の行を一度実行する。

```sh
git apply experiments/formal/real-probe.patch
experiments/formal/compile.sh -imodules/golem-layout/test experiments/formal/Position.hs
experiments/formal/compile.sh -imodules/golem-layout/test experiments/formal/Shape.hs
```

どちらも終了コード 0。
`review-results.txt` は測定したコードポイント境界、送りの差、グリフ数、漢字「日」のグリフ ID、入力件数を記録している。
書体データは `modules/golem-font/test/fonts/`、HarfBuzz の成形は水平方向であり、`AV` と `fi` には Latn と en を指定した。
可変書体の軸は動かしていない。
