# 原稿と設定の入力補完の試作

基準は `ce1d423474050ed0dced10669cbd9499ff529bfb`。
Golem [ADR 0334](../../docs/adr/0334-complete-manifest-values-and-manuscript-expressions.md) の候補をこの worktree の通常の Cabal テストから実行した。

| ロードマップの項目 | 観測したこと | この worktree の根拠 |
| --- | --- | --- |
| TOML の有限値 | 未保存の manifest で表を切り替え、PDF 宣言には引用符の有無に合う 1 語、自由な language 欄には 0 個。役割 9 語、抑制コード、配列要素とスカラーの違いも検査 | `modules/golem-lsp/test/EditingSpec.hs:186`、`modules/golem-lsp/test/TomlSpec.hs:109`、`modules/golem-project/src/Golem/Project/Manifest.hs:673` |
| 命令、式、関数を入力位置で分ける | 行頭、絵文字の直後のインライン命令、式、通常の本文に実リクエスト。文字列、閉じ括弧、エスケープ、配列を含む式を純粋関数でも照合 | `modules/golem-lsp/test/EditingSpec.hs:176`、`modules/golem-lsp/src/Golem/Lsp/Features.hs:486` |
| 候補を選ぶときの説明 | `len` の説明と、Emet の `book.total` のファイル要求を含む署名を、実リクエストへの応答の documentation で照合 | `modules/golem-lsp/test/EditingSpec.hs:203`、`modules/golem-lsp/test/FunctionsLspSpec.hs:244`、`modules/golem-lsp/src/Golem/Lsp/Server.hs:440` |
| 名前を付けた寸法 | 候補の名前と型や rename は別の提案 Golem [ADR 0320](../../docs/adr/0320-named-layout-values.md) が定める。ここでは既存の参照を含む style/preflight のテストを再実行 | `modules/golem-lsp/test/TomlSpec.hs:80`、隣の `road-syntax/docs/adr/0320-named-layout-values.md:49` |

## コマンドと記録

- `cabal test --offline -j3 golem-lsp:test:golem-lsp-test --test-options='-p roadmap-completion' --test-show-details=direct` を旧実装で実行。終了 1。5 件のうち 4 件が失敗し、絵文字直後のインライン命令と通常の本文の対照だけが通った。`red.txt:189`。
- `cabal test --offline -j3 golem-lsp:test:golem-lsp-test --test-options='-p roadmap-completion -j1' --test-show-details=direct` を最初の実装で実行。終了 0。対照を 1 件増やした 6 件が通った。`green.txt:100`。
- `cabal test --offline -j3 golem-lsp:test:golem-lsp-test --test-options='-j1' --test-show-details=direct` を拡張後に実行。終了 0。既存の補完、Emet、エディターセッションを含む 197 件が通った。`suite.txt:554`。
- `cabal test --offline -j3 golem-project:test:golem-project-test --test-options='-p /paragraph-separator/||/pdfa/||/pdfua/' --test-show-details=direct` で既存 decoder の 6 件が通った。終了 0。`decoder.txt:37`。
- `adr-guard links --fix`、textlint のリポジトリ用 ADR 設定、`git diff --check` は `validation.txt` に記録。

## 未検証範囲

LSP の応答を検証した。Neovim、Helix、VS Code で選択時の説明の見た目と操作を確認していない。
複数行にまたがるコードブロックの内部での補完抑制、列挙の全葉と decoder の自動照合、新しい寸法名の提案と組み合わせたビルドは未検証。
