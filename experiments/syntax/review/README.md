# 記法のレビューを反映した試作

Golem [ADR 0315](../../../docs/adr/0315-retire-listing-src.md)、[0316](../../../docs/adr/0316-retire-dash-line-ranges.md)、[0319](../../../docs/adr/0319-unitless-zero-in-length-fields.md) では、本物の Golem パーサーと評価器を組み合わせた。
[修正](review.patch) は作業用の一時ディレクトリにのみ適用する。Golem [ADR 0317](../../../docs/adr/0317-retire-table-src.md)、[0318](../../../docs/adr/0318-retire-legacy-style-formats.md) は初回の結果を使った。

```sh
export GOLEM_STORE_DB="$HOME/.cabal/store/ghc-9.10.3-fe9c/package.db"
export GOLEM_LOCAL_DB="$PWD/../codex-impl-0308/dist-newstyle/packagedb/ghc-9.10.3"
sh experiments/syntax/review/actual.sh baseline
sh experiments/syntax/review/actual.sh
sh experiments/syntax/review/names.sh
sh experiments/syntax/review/declaration.sh baseline
sh experiments/syntax/review/declaration.sh
node --test experiments/syntax/review/review.test.mjs
node experiments/syntax/review/current.mjs ../codex-impl-0308/dist-newstyle/build/aarch64-osx/ghc-9.10.3/golem-cli-0.1.0/x/golem/build/golem/golem
```

| 対象 | 入力と実測 |
| --- | --- |
| 掲載パス | 位置引数二つ、位置と src、src 二つ、位置と src 二つ。キー重複は展開後に検出し、二次エラーを出さない |
| 行番号 | 7 行に `lines="1...3, 5...7"` を指定。意味論 IR の行番号と本文は 1、2、3、5、6、7 に一致。誤記 `1.,.3, 5..,7` はエラー |
| 負号と式 | 行指定の語のパーサーは `-1` を G02110 にする。変数を通した 0 は G02037、-1 は G02103。別途、実パーサーの parseAst に行指定の構文検査を組み込み、掲載ファイルの存在にかかわらず負のリテラルを拒否することを確認 |
| ゼロ行 | IR は空。正の行アキの直前、直後に入れても IR に `BlankLines 2` だけが残った |
| 型で引く名前 | 実 TOML の名前を Haskell で引き、相対長、アキ量、行数、型違い、未定義等が [9/9](names-green.log)。共通の式の項、別名、前方参照、行数の加算、直接・間接の循環は独立した式の試作で検査した。通常の設定、補完、名前変更の統合は未検証 |
| 原稿の変数 | 実 CLI で旧宣言の参照成功、裸の新宣言は未定義、参照の @ は G01020。一行の識別試作で新宣言を旧 AST と同じ入力に直すと終了 0。実 PEG 文法で生成したパーサーでも新旧とも SetVar、コードブロックの例は CodeBlock。旧宣言の notice は未検証 |

パーサー単体は [変更前](declaration-red.log) が行指定 3/6、宣言 7/9、[変更後](declaration-green.log) が 6/6 と 9/9。
評価器の [変更前](actual-red.log) は 6/16、[変更後](actual-green.log) は 16/16。
行範囲ごとにコードブロックを作ったため試作の IR には二つのブロックが残る。キャプション、通し番号、PDF への出力は試していない。
[規則単独の試験](green.log) は 49/49。宣言の右辺に式を使う規則を加えた際の [変更前](typed-red.log) は 47 件中 39 件だった。[現行 CLI の結果](current.jsonl) は 16 入力と新宣言変換後の 1 入力である。
