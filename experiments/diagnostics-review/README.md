# レビュー後の diagnostics の試作

Golem [ADR 0321](../../docs/adr/0321-preflight-rule-error-causes.md)、[0324](../../docs/adr/0324-manifest-language-form.md)、[0325](../../docs/adr/0325-preflight-glyph-severity.md)、[0326](../../docs/adr/0326-discard-stale-pdf-after-build-errors.md)、[0329](../../docs/adr/0329-output-path-file-diagnostic.md) について、実際の Golem CLI と一時プロジェクトで確かめた。
再現スクリプトはソースを書き換えたり、テスト用のルートの外のファイルを消したりしない。
比較対象の [前回の CLI](../integrated/README.md) と、Golem [ADR 0308](../../docs/adr/0308-tell-a-japanese-book-by-the-primary-subtag-of-its-language.md) の実装を含むコミット `0a8d21a091d830573fb6229111ed744f74162afd` に [今回の試作差分](diagnostics-revised.patch) を適用した CLI を使った。
.DS_Store の変更前だけは、同じコミットを変更せずにビルドした CLI を使った。

| 試した入力 | 観測した結果 |
| --- | --- |
| TOML の二つの独立した文法エラー、未知のキー、値の誤り | CLI 単独では一行目の一件。回復試作で一、二、四、六行目の四件。 |
| 閉じない複数行文字列 | 文法エラー一件、残りは未検査。内部の文字を新しいセクションにしない。 |
| 原稿の二か所に七階層の見出し | 一行目と三行目の両方に G01012。 |
| `ja-JP`、`en-US`、`JP`、`US`、`DE`、`de`、`jbo`、`sl-rozaj`、`ja-x-my-dialect` | HTML ビルド成功、出力の lang 属性が原文に一致。`ja_JP` は G03119。 |
| 壊れた PNG と塗り足し不足 | 前回は G08010 のみ。今回は G08010 と G09010 を一度の preflight で得た。 |
| dev と prod で PDF を書けない | 両方が G08010 で失敗。dev は前回の PDF と pages.json が両方とも同じバイト列。prod は両方とも消える。 |
| 通常の .DS_Store を含むプロジェクトと外部へのリンク | fmt --check は保持、fmt はルートと原稿の親を掃除。build --target pdf はルートと build と build/pdf を掃除。外部のファイルと対象外の HTML は保持。 |

[変更前の出力](before.json)、[変更後の出力](after.json)、[Finder のファイルの変更前](finder-before.json)、[変更後](finder.json) は実行時の結果である。
TOML 回復の試作だけは専用 CLI の外で、不正な単独の代入をマスクして同じ CLI で読み直す。
複数行の一般の TOML のトークン回復、未検査の範囲を CLI の出力形式で渡す処理、欠けたページ情報に依存する全検査の列挙は本実装の課題である。
試作の .DS_Store のファイル種別検査は macOS の POSIX API を使う。
並行して親ディレクトリが差し替えられる場合までの保証は測っていない。

次のコマンドを試作差分適用先のルートで実行する。
`PROBES` にはこの README のディレクトリの絶対パスを設定する。
Node.js で試料を作って CLI を呼び、期待する位置と結果から外れたら終了 1 となる。

```sh
cabal build golem-cli:exe:golem --offline -j2
export GOLEM_BIN="$(cabal list-bin golem-cli:exe:golem)"
REVISED_EXPECTATIONS=1 node "$PROBES/probe.mjs"
REVISED_EXPECTATIONS=1 node "$PROBES/finder.mjs"
```
