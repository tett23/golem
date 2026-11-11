# 見出しの上限を共有原稿で確かめるテスト

Golem [ADR 0310](../../docs/adr/0310-enumerate-parser-formatter-round-trips.md) の G3、Golem [ADR 0311](../../docs/adr/0311-enumerate-source-position-conversions.md) の UTF-16 の位置、Golem [ADR 0323](../../docs/adr/0323-heading-level-diagnostic-occurrences.md) の H1 と H2 を、同じ原稿で照合した。
作業の基点は `706e5888fb1d63a53da68a0e7223b76f8441d2f9` である。
差分は既存の三つの Cabal テストスイートと、それらがすでに依存する golem-test-support にある。

| 読む箇所 | 調べること |
| --- | --- |
| [入力](../../modules/golem-test-support/src/Golem/TestSupport/Heading.hs) の 9 行目 | 絵文字から始まり、六階層の正常な見出しと七階層の不正な見出し二つを含む原稿 |
| [パーサー](../../modules/golem-parser/test/ParserSpec.hs) の 533 行目 | 返った全 diagnostics が二つの G01012 であり、順に UTF-8 の半開区間 [23, 29)、[46, 49) を指す |
| [CLI](../../modules/golem-cli/test/CommandsSpec.hs) の 114 行目 | 二章が同じファイルを import する。check と HTML build はどちらも終了コード 1。G01012 を二つ、同じ原稿上の同じ位置に返す |
| [LSP](../../modules/golem-lsp/test/EditingSpec.hs) の 156 行目 | 二章の import 先を編集し、UTF-16 を選んだクライアントが受け取る G01012 の範囲を順に比較する |

UTF-8 のバイト位置は 0 始まりである。
最初の不正な見出しの 7 個目の `#` は、絵文字 4 バイト、改行 2 バイト、正常な見出し 9 バイト、改行 2 バイト、先行する `#` 6 バイトの後にある。
二つの不正な見出しの範囲を UTF-16 で書くと (4,6) から (4,10)、(8,6) から (8,9) となる。
最初の不正な見出しの末尾にある絵文字が UTF-16 の 2 単位を占める。

## 再現

worktree のルートで、GHC 9.10.3 とプロジェクトの Wasmtime を使って実行する。

```sh
cabal test --offline -j4 golem-cli:test:golem-cli-test golem-lsp:test:golem-lsp-test golem-parser:test:golem-parser-test --test-options='-p heading-limit' --test-show-details=direct
cabal test --offline golem-lsp:test:golem-lsp-test --test-options='-p renaming' --test-show-details=direct
```

一つ目は追加した 4 件（parser 1、CLI 2、LSP 1）、二つ目は既存の編集機能を含む LSP の 22 件が成功し、どちらも終了コード 0 だった。
二つ目の 22 件には新しい LSP テスト 1 件を含む。
実行ログの抜粋は [green.txt](green.txt) にある。

先に期待値だけを変えて同じ 4 件を走らせた。
パーサーは開始位置を 24 とした期待値、CLI は最初の G01012 が二度出る期待値、LSP は絵文字の後の列を 9 とした期待値でそれぞれ失敗した。
4 件とも失敗し、Cabal の終了コードは 1 だった。
[red.txt](red.txt) に期待値と実際の値を残した。

この組み合わせでは製品コードの修正を要する反例は出ていない。
過去に報告された重複が消えたコミット、ほかの import グラフ、WASI とブラウザー上での挙動は未検証である。
