# PDF/X-4 の印刷領域にあるリンク注釈（2026-11-11）

Golem 0.1.0-rc4 が PDF/X-4 として出力した1ページの PDF で、外部リンクの矩形が仕上がり領域の内側に入ることを確認した。
PDF Association の解説は PDF/X の印刷領域に注釈を置けないとし、印刷用の入稿サービス DUON は PDF/X-4 の仕上がりや塗り足しの領域にある通常の注釈をエラーの対象として説明する。
Golem のリンクは印刷用のマークでもトラッピングの情報でもない。

## 再現条件

golem-driver の conformance fixture の横組み設定を使い、フォントは CI の conformance-pdfs.sh と同じものを置いた。
原稿は見出し「見本」の次の段落に `[link "https://example.com/": 外部リンク]` を一つ置いた。
リポジトリにある golem-test-cmyk.icc を style.toml の [color] の intent に指定した。

`golem build --target pdf` は成功した。
`pdfinfo -box` は PDF/X-4 と表示し、`pdfinfo -url` は1ページ目の注釈として URL を返した。
ページの TrimBox と BleedBox はともに `[0 0 419.5276 595.2756]`、注釈の Rect は `[65.1969 447.874 107.5465 456.3779]`、フラグは `/F 4` だった。
PDF の適合宣言を読むだけではこの問題を見つけられない。

## 公開資料から判断できる範囲

| Golem が出力する構造 | 調査結果 |
| --- | --- |
| 外部リンク注釈と URI アクション | 生成物の矩形は印刷領域に入る。URI アクション一般が「外部への参照」に該当するかは未確認。 |
| 文書内の行先を持つリンク注釈 | 行先が同じ文書内でもページ上の矩形を使うため、印刷領域について同じ問題がある。 |
| Print フラグ、外観ストリーム | 資料が示す印刷領域の制限は、フラグを落とすだけ、または外観を追加するだけでは解決できない。外観ストリームを要求する全条件は未確認。 |
| しおり | Golem のしおりはページの注釈とは別の辞書で文書内の行先を指す。しおり全般の適合性は未確認。 |

本調査では ISO 15930-7:2010 の本文との突き合わせと、DUON への実際の入稿は行っていない。
本文リンクへの対処は [Golem ADR 0350](../adr/0350-omit-page-link-annotations-from-pdf-x-4.md)、要件一覧に残る照合は [Golem ADR 0221](../adr/0221-check-iso-15930-7-for-link-annotations-before-rc4.md) と [Golem ADR 0226](../adr/0226-move-the-iso-15930-7-check-to-before-v1.md) に記す。

## 修正前後の比較

同じ原稿を修正前後の CLI で組み、`pdftoppm -r 120` で描いたページと `pdftotext -bbox` で取り出した座標付きテキストをそれぞれ `cmp` で比べた。
どちらも終了コードは 0 だった。
`pdfinfo -url` が列挙する注釈は1個から0個になった。
`pdfinfo -struct-text` は見出しと段落を元の順に返し、段落の「外部リンク」は注釈への参照を持つ Link から文字を持つ Span になった。
同じ設定で PDF/A-2a と PDF/UA-1 も宣言して組んだ試料は、veraPDF 1.30.2 の 2a と ua1 の両方の検査を通った。
さらに CI の conformance-pdfs.sh が組む6冊を verapdf.sh に渡し、6冊とも両方の検査を通った。

## 資料

- [PDF Association, PDF/X in a Nutshell, p. 6](https://pdfa.org/wp-content/uploads/2017/05/PDFX-in-a-Nutshell.pdf)
- [DUON の PDF/X-4 入稿検査の説明](https://duon.zendesk.com/hc/en-us/articles/15531276542748--EN-Annotation-other-than-TrapNet-or-PrinterMark-inside-print-area-PDF-X-4)
