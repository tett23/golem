# ADR 0386: EPUB のページ一覧とページ部品の色を指定する

ステータス: 採択（未実装）

## 文脈

本の部品の拡張のうち、書き手が必要とする「ページ番号と柱の拡張」の扱いを決める。

## 調査した事項

ロードマップの「本の部品の拡張」は「ページ番号と柱の拡張」を v1.0.0 の対象に挙げている。

## 実装すること

対応する固定ページ版のページ情報が指定された場合だけ EPUB の page-list を作る。
各ページの先頭に対応する本文アンカーを文書順に並べ、対応先がないページは除く。
柱とノンブルは文字スタイルで見出しと同じ書体や色を参照できる。
罫線と単色図版の描画色を独立に指定し、多色画像の画素は保存する。

対応表には物理ページ順に表示ノンブルと原稿上の本文位置を持たせ、EPUB 生成時に XHTML のファイルと要素 ID に解決する。
古い原稿を指す対応表はエラーとする。

## 実装しないこと

リフロー後の閲覧端末の画面番号は扱わない。

## 不変条件

1. page-list のすべてのリンクは実在する本文アンカーを指し、リンクの順は固定ページ版の順序に一致する。

| 境界の入力 | 期待する結果 |
| --- | --- |
| ページ情報なし | 一覧なし |
| 対応先が一つ | リンク1件 |
| 多色画像 | 元の色 |

## テスト設計

- `inv1_page_list_and_page_colors_property` で次の述語を検査する。page-list のすべてのリンクは実在する本文アンカーを指し、リンクの順は固定ページ版の順序に一致する。
- `inv1_page_list_and_page_colors_case_1` は「ページ情報なし」を入力とし、「一覧なし」を確かめる。
- `inv1_page_list_and_page_colors_case_2` は「対応先が一つ」を入力とし、「リンク 1 件」を確かめる。
- `inv1_page_list_and_page_colors_case_3` は「多色画像」を入力とし、「元の色」を確かめる。

## トレードオフ

固定ページとの対応表が必要なため、EPUB 単体のビルドからページ番号を推定できない。

## 参考文献

- [Golem のロードマップ「本の部品の拡張」](../roadmap.md)
- [golem-driver ADR 0003](../golem-driver/adr/0003-pdf-heading-styles.md)
- [golem-driver ADR 0004](../golem-driver/adr/0004-pdf-emphasis-and-character-styles.md)
- [golem-driver ADR 0009](../golem-driver/adr/0009-pdf-toc-page-numbers.md)
- [golem-epub ADR 0001](../golem-epub/adr/0001-epub-packaging.md)
