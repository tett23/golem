# 見出しの上限を一つのプロセスで照合する

試作の基点は `706e5888fb1d63a53da68a0e7223b76f8441d2f9`。
Golem [ADR 0337](../../docs/adr/0337-test-build-and-check-in-the-same-process.md) と Golem [ADR 0323](../../docs/adr/0323-heading-level-diagnostic-occurrences.md) の六構成で、check と HTML ビルドの二つの経路を試した。
チェックアウトのルートで次の順に実行する。

```sh
git apply experiments/heading-in-process/in-process.patch
cabal test --offline -j4 golem-cli:test:golem-cli-test --test-options='-p heading-limit' --test-show-details=direct
export GOLEM_TEST="$(cabal list-bin golem-cli:test:golem-cli-test)"
experiments/heading-in-process/verify.sh
```

`modules/golem-cli/shared/Golem/Cli/BuildCommand.hs:11` は、CLI の二つのモードから本物の driver を呼び、JSON を組み立てる。
`modules/golem-cli/test/CommandsSpec.hs:115` は、一時プロジェクトを渡して実行する。
各モードで終了コード 1 を得た。
六構成の G01012 はモードごとに順に 2、2、2、3、1、1 件で、ファイル、開始位置、終了位置、行、列の配列まで一致した。
Cabal は 12 件成功、終了コード 0。
`verify.sh` は PATH の先頭に呼ばれたら終了コード 83 を返す golem を置いた。
同じ 12 件が通り、golem の呼び出しは 0 回だった（`zero-processes.txt`）。

比較のため、従来の、各入力で二つの実行ファイルを呼ぶ実験は `experiments/diagnostics/baseline.mjs:74` にある。
この回帰検査は引数の解析と標準エラー出力の割り当てを通らない。
それらは既存の CLI テストが受け持つ。
プロセス起動の節約時間は計測していない。

試作で作った実行ファイルにも、単独の章で `check --format json` と `build --target html --format json` を一度ずつ渡した。
両方とも標準出力は空、終了コードは 1 で、標準エラー出力の G01012 はバイト 23 から 29 の直前までと、46 から 49 の直前までを順に示した（`cli-comparison.txt`）。
