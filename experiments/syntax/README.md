# 記法と設定の値の試作

試作はコミット `2b7d1dffe359e065bf5e899a2df6cab85704905d` を基にした。
GHC 9.10.3 で試作のソースをコンパイルし、依存パッケージはコミット `0a8d21a091d830573fb6229111ed744f74162afd` のビルド結果を使った。
CLI の比較も同じコミットの実行ファイルを使った。

| ロードマップの項目 | 提案 ADR | Haskell のテスト（変更前の成功数 → 変更後の成功数） |
| --- | --- | --- |
| 掲載ファイルの旧記法、位置引数との併記 | [0315](../../docs/adr/0315-retire-listing-src.md) | 下の二行と合わせて 6/14 → 14/14 |
| 行の範囲の旧区切り | [0316](../../docs/adr/0316-retire-dash-line-ranges.md) | 同上 |
| 表ファイルの旧記法 | [0317](../../docs/adr/0317-retire-table-src.md) | 同上 |
| 一覧の括弧と番号の見本、柱の括弧、注番号のサイズ | [0318](../../docs/adr/0318-retire-legacy-style-formats.md) | 2/7 → 7/7 |
| 単位のないゼロ | [0319](../../docs/adr/0319-unitless-zero-in-length-fields.md) | 5/12 → 12/12 |
| 長さ、アキ量、行数の名前 | [0320](../../docs/adr/0320-named-layout-values.md) | 1/9 → 9/9 |

専用 worktree のルートから次のコマンドを実行する。

```sh
export GOLEM_STORE_DB="$HOME/.cabal/store/ghc-9.10.3-fe9c/package.db"
export GOLEM_LOCAL_DB="$PWD/../codex-impl-0308/dist-newstyle/packagedb/ghc-9.10.3"
sh experiments/syntax/sources.sh
sh experiments/syntax/formats.sh
sh experiments/syntax/dimensions.sh
sh experiments/syntax/names.sh
node --test experiments/syntax/test.mjs
node experiments/syntax/cli.mjs ../codex-impl-0308/dist-newstyle/build/aarch64-osx/ghc-9.10.3/golem-cli-0.1.0/x/golem/build/golem/golem
```

Haskell の四つのスクリプトはコンパイルから行い、終了時に一時ディレクトリを消す。
各スクリプトと同じ名前の `*-red.log` と `*-green.log` に変更前後の結果がある。
JavaScript のテストは規則を比較するための独立した試作で、[12 件の結果](green.log) がある。
CLI の比較は隔離したプロジェクトを作成し、実際の設定ファイル、原稿、フォントを使う。
[照合結果](cli.log) の preflight は G09001 を通過して G09014 を返した。

本実装で残る範囲は各 ADR の「テスト設計」にある。
ファイル読み込みは評価器に渡したアセットを対象とし、ドライバが先にディスクから読む範囲は未検証である。
