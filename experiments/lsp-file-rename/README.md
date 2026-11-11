# 改名前の参照更新を試した記録

Golem の試作用ビルドの基点は `706e5888fb1d63a53da68a0e7223b76f8441d2f9`。
Aleph は `5cdb2e503175564a23699e84320a8365a387ed5e` のローカル checkout を読んだ。
同 checkout の `docs/adr/0070-rename-sheets-and-folders-from-tree.md` は採択（未実装）で、`app/ui/tree.ts:228` はファイルを改名してからフックを呼び、`app/lsp/client.ts:94` はファイル操作の能力を申し出ていない。
`app/lsp/mount.ts:15` の同期対象は gm と emet、`app/wikilink.ts:119` が Wiki リンクの解決、`app/wikilinkmount.ts:278` が既存の改名後の更新を受け持つ。

このディレクトリで実行する。
BUILT_TREE は golem-cli と golem-lsp を GHC 9.10.3 でビルドした上記 checkout の絶対パスとする。

```sh
export BUILT_TREE
export GOLEM_BIN="$(cd "$BUILT_TREE" && cabal list-bin golem-cli:exe:golem)"
node baseline.mjs
./compile.sh
export PROBE_BUILD="$(mktemp -d)"
./server.sh
PROBE=1 GOLEM_BIN="$PROBE_BUILD/server" node baseline.mjs
node --test --test-name-pattern='a rename rewrites links' "$ALEPH/app/wikilink.test.ts"
```

| 検査 | 結果と根拠 |
| --- | --- |
| 基準版の標準入出力での実 LSP 要求 | 能力登録は空。willRenameFiles は −32601。`baseline.txt:1` |
| 実パーサーを使う範囲と名前の計算 | 9 ケース成功。2 箇所、重複、構成要素の境界、競合、同時置換、ルート外、未保存の本文を照合。`Probe.hs:7`、`ReferencePlan.hs:19`、`probe.txt:1` |
| ハンドラーを試作した Golem LSP | 実クライアントが open → will → change → ディスクの改名 → did を実行。版 7、元 URI、UTF-16 の 2 範囲を確認。重複時の応答は同一、競合は −32600、空と編集後の再要求は null。`baseline.mjs`、`server.patch`、`wire.txt:1` |
| Aleph の既存の仕様との対照 | パス指定とファイル名のリンクを書き換え、ラベルと見出しとタイトルによるリンクは保つ既存試験 1 件成功。`aleph.txt:1` |

試作用ハンドラーは、UTF-16 を使う一つの未保存の .gm に対象を固定した。
didRenameFiles の索引更新は未実装。
版衝突、閉じた文書、TOML、アセット、プロット、Wiki リンクを LSP から編集する機能、Aleph の適用と巻き戻しと GUI は受け入れ試験に残る。
