# ADR 0195: PDF の各ページが原稿のどこから始まるかを出す

ステータス: 採択（未実装）

## 文脈

Golem のエディタの Aleph（https://github.com/tett23/aleph）は、`.gm` のエディタに改ページの位置の印を出す。
今は、段落の字数を版面の字詰めで割った行数と見出しの行数から見積もっていて、禁則、ルビ、行アキは数えていない（[tett23/aleph ADR 0006](https://github.com/tett23/aleph/blob/96d97b8/docs/adr/0006-horizontal-editor.md)）。
正確な位置を出すために、Golem に、PDF の各ページが原稿のどこから始まるかを出す機能を依頼するとしている。
ページを押して原稿のその位置に移る機能も、この対応ができてから決めるとしている（[tett23/aleph ADR 0010](https://github.com/tett23/aleph/blob/96d97b8/docs/adr/0010-previews.md)）。

golem 0.1.0-rc3 の `golem build` のオプションは `--target`、`--profile`、`--marks`、`--no-notices`、`-v`、`--format` で、ページと原稿の対応を出すものはない（`golem build --help` で確かめた、2026-11-07）。

## 実装すること

- `golem build --target pdf` のとき、`build/pdf/` に、PDF の各ページについて、そのページの最初の行が原稿のどのファイルの何行何列から始まるかを JSON で書く。
- 位置の単位は、LSP と同じく行と列とする。

## 実装しないこと

- ページの中の各行と原稿の対応。
- PDF 以外のターゲット。

## テスト設計

- 改ページを含む見本の原稿を組み、各ページの最初の行の原稿の位置が、出した JSON と一致することを確かめる。

## トレードオフ

- 組版の途中で原稿の位置を持ち回る必要がある。

## 決めたことの記録

- **出し方**（2026-11-07、メンテナー）：草案の案のとおり、`build/pdf/` に、各ページの最初の行が始まる原稿の位置を JSON で書くと決めた。

## 参考文献

- tett23/aleph の仕様書の「横書きのエディタ」：https://github.com/tett23/aleph/blob/96d97b8/docs/specifications.md
