# ADR 0001: EPUB のパッケージング

ステータス: 採択

## 文脈

EPUB の本文は XHTML と CSS であり、golem-html の出力をそのまま使う。
golem-epub は、その上にパッケージ文書、ナビゲーション文書、コンテナを加えて zip にまとめる薄い層である。
EPUB の決定性（zip のエントリの時刻と順序の固定）は v2 で扱うと決めている。

## 実装すること

### 構成

- EPUB 3.3 に従う。
- zip の最初のエントリは、無圧縮の `mimetype`（`application/epub+zip`）とする。
- `META-INF/container.xml`、パッケージ文書（`OEBPS/package.opf`）、ナビゲーション文書（`OEBPS/nav.xhtml`）、golem-html の本文、CSS、画像、フォントを入れる。

### パッケージ文書

| EPUB | 値の出どころ |
|---|---|
| `dc:identifier` | 電子版の ISBN（`[targets.epub].isbn`）。なければマニフェストの `id` |
| `dc:title` | `metadata.title`。読みがあれば `file-as` で付ける |
| `dc:language` | `metadata.language` |
| `dc:creator` | `metadata.creators`。役割（`role`）と読み（`file-as`）を `refines` で付ける |
| `dc:publisher` | `metadata.publisher` |
| `dcterms:modified` | `metadata.date` の日付の 00:00:00 UTC |

- スパインの順序は、マニフェストの章の順とする。
- 既定の書字方向が縦書きの場合は、`page-progression-direction` を `rtl` にする。

### ナビゲーション文書

- 目次のチャネル（[golem-doc ADR 0002](../../golem-doc/adr/0002-document-assembly.md)）から作る。
- `@toc` の有無にかかわらず、EPUB のナビゲーション文書は必ず出力する。`@toc` がない場合は、`@notoc` のない見出しをすべて載せる。

### 注

注の印には `epub:type="noteref"` を、注の本文には `aside` と `epub:type="footnote"` を付け、リーダーがポップアップで表示できるようにする。
傍注は、golem-html の出力のとおり段落の直後の `aside` とし、ポップアップにはしない。

### 検証

CI で、出力した EPUB を epubcheck で検査する。

## 実装しないこと

- EPUB の決定性。v2 で扱う。
- フォントの難読化。
- 固定レイアウトの EPUB。
- page-list による紙のページ番号との対応付け。

## テスト設計

- docs/markup.md の例を含む原稿から EPUB を作り、epubcheck がエラーと警告を出さないことを確かめる。
- パッケージ文書とナビゲーション文書を golden テストで固定する。zip の全体はバイト列が揺れうるので、golden テストの対象にしない。
- 縦書きの既定で `page-progression-direction` が `rtl` になることを確かめる。
- ISBN の有無で `dc:identifier` が切り替わることを確かめる。

## トレードオフ

zip の決定性を v2 に回すので、v1 の EPUB は同じ入力からでもバイト列が一致しない場合がある。
その代わり、パッケージ文書とナビゲーション文書は決定的に作り、golden テストで固定することで、内容の変化は検出できるようにする。
