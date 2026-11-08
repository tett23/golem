# ADR 0183: タグ付き PDF と、PDF/A-2a と PDF/UA-1 への準拠

ステータス: 採択→構造の木にない内容の扱いは [ADR 0216](0216-drawn-content-missing-from-the-structure-tree-is-an-error.md)、CI の ICC プロファイル、最初の見出しの G07103 のメッセージ、校正のコメントの行は [ADR 0211](0211-record-what-implementations-decided-found-by-the-review-of-2026-11-08.md)、`[ref-number]` と `[ref-title]` の `Reference` は [ADR 0215](0215-ref-number-and-ref-title-as-reference.md) で実装、一つの葉の中の字形の順は [ADR 0227](0227-draw-the-glyphs-of-a-box-in-the-order-of-its-text.md)、CI の `verapdf` の待ち方は [ADR 0244](0244-take-verapdf-off-the-critical-path-of-ci.md)

## 文脈

[docs/roadmap.md](../roadmap.md) の v0.1.0-rc4 の PDF の節に「タグ付き PDF と PDF/A」がある。
PDF に構造のタグ（`/StructTreeRoot`）を書かず、PDF/UA と PDF/A に対応しない、という項目である。
タグ付き PDF、PDF/UA、PDF/A は、名前が並んで語られることが多いが、求めるものは違う。

- **PDF/A**（ISO 19005）は、長期保存のための規格である。PDF/A-2b は見た目の再現（フォントの埋め込み、色の定義、メタデータ）を、PDF/A-2u はそれに加えて、すべての字を Unicode に対応づけることを求める。PDF/A-2a は、さらにタグ付けを求める。
- **PDF/UA**（ISO 14289）は、支援技術で読めるための規格である。すべての内容をタグ付けするか、アーティファクト（柱やノンブルのように読み上げない内容）として印を付けることを求める。
- **タグ付き PDF** は、PDF の中に論理構造の木（段落、見出し、表、図など）を持たせる仕組みであり、PDF/UA と PDF/A-2a の土台である。

この ADR は、タグ付き PDF と PDF/A の両方を扱い、PDF/UA-1 にも準拠させる。
v2 に回さないのは、v2 の範囲が膨らむのを抑えるためである（「決めたことの記録」）。

### 今の PDF

`~/.local/bin/golem`（0.1.0-rc3）で蟹工船の fixture（縦組み、ルビ、Noto Serif JP の CFF）の写しを組み、PDF を調べた（2026-11-06）。

- カタログは `<< /Pages 2 0 R /Type /Catalog >>` だけで、`/StructTreeRoot`、`/MarkInfo`、`/Lang` はない。PDF の版は 1.6 である。
- `[color] intent` を足して組むと、カタログに `GTS_PDFX` の出力インテントと XMP のメタデータが加わる（[golem-pdf ADR 0002](../golem-pdf/adr/0002-pdf-x-4.md)）。

PDF に書く順は、論理の順と違う。
1 ページ目の内容のストリームから、`Tj` の字を ToUnicode で文字に戻して並べた（scratchpad の Python で確かめた。コミットはしない）。
本文が先に来て、ルビの読みは親文字の直後に続く（`蝸牛かたつむり`）。
見出しの「一」とノンブルの「1」は、ページの最後に来る。
タグのない PDF から文字を抜き出す閲覧ソフトは、この順か、位置から推した順で読む。

### veraPDF で確かめた差

veraPDF は、PDF Association の PDF/A と PDF/UA の検証器である。
この環境には入っていなかったので、nixpkgs の `verapdf` 1.30.2 を、作業用の場所に `nix build` で取得した。
nixpkgs の定義は、veraPDF の公式の GitHub（`veraPDF/veraPDF-apps` の `v1.30.2` のタグ）のソースを SHA-256（`sha256-gYSHo0QLDlBNgDi5GFYsT+D2Toud754iAgRxXEQXPhI=`）で固定しており、ビルド済みのものは cache.nixos.org の署名付きのキャッシュから届いた。
実行すると、版は `veraPDF 1.30.0` と表示される。

`[color] intent` のない PDF と、ある PDF（PDF/X-4）を検証した結果は次のとおりである。
出力インテントには、macOS の `Generic CMYK Profile.icc` を使った（Japan Color 2001 Coated ではない）。

| 検証の対象 | intent なし | intent あり（PDF/X-4） |
| --- | --- | --- |
| PDF/A-2b | 6.2.4.3-4（出力インテントなしの DeviceGray、65,095 件）、6.6.2.1-1（XMP がない） | 6.2.4.3-4（PDF/A の出力インテントがない DeviceGray）、6.6.2.3.1-1 と 6.6.2.3.1-2（`pdf:Trapped` と `pdfxid:GTS_PDFXVersion` が定義済みの XMP のスキーマにない）、6.6.4-1（`pdfaid` がない） |
| PDF/A-2u | 2b と同じ | 2b と同じ |
| PDF/UA-1 | 7.1-3（タグもアーティファクトの印もない内容）、7.1-8（XMP がない）、7.1-10（`DisplayDocTitle`）、7.1-11（`StructTreeRoot`）、6.2-1（`MarkInfo`）、7.2-34（内容の言語） | 左から 7.1-8 が消え、5-1（`pdfuaid`）と 7.2-33（メタデータの言語）が加わる |

PDF/A-2u の検証で、ToUnicode の規則（字を Unicode に対応づけること）に反した字はなかった。
字の Unicode への対応は、すでに golem-driver の ToUnicode と ActualText の仕組み（[golem-driver ADR 0030](../golem-driver/adr/0030-ligature-text-layer.md)）が持っている。

### PDF/A-2u に足りないもの

足りないものがメタデータと出力インテントだけなら、PDF/X-4 の PDF に手で足せば PDF/A-2u になるはずである。
これを確かめるため、intent ありの PDF に、scratchpad の Python で増分更新を書き足した（コミットはしない）。

- カタログの `OutputIntents` に、`S` が `GTS_PDFA1` の出力インテントを足す。`DestOutputProfile` は、`GTS_PDFX` の出力インテントと同じ間接オブジェクトを指す。
- XMP に `pdfaid:part`（2）と `pdfaid:conformance`（`U`）を足し、`pdf:Trapped` と `pdfxid:GTS_PDFXVersion` を PDF/A の拡張スキーマ（`pdfaExtension:schemas`）で定義する。
- 1 ページ目に、`/F 4` を持ち `/AP` を持たないリンクの注釈を一つ足す（[ADR 0182](0182-external-links.md) の形）。

この PDF は、veraPDF の PDF/A-2b と PDF/A-2u の両方で適合と判定された。
同じ手順で、The Tempest の fixture（横組み、英語、TrueType の可変フォント）と、figures の fixture（PNG、JPEG、SVG、PDF の図版。フォントは Noto Serif JP で代えた）も、PDF/A-2u に適合した。
二つの出力インテントが同じプロファイルを指すことは、PDF/A-2 の規則 6.2.3-2 が、PDF/X-4 にも同時に適合するファイルを例に挙げて求めている（veraPDF の検証プロファイルの記述で読んだ）。

### PDF/A-4 と PDF/X-4

同じ PDF を PDF/A-4 で検証すると、ヘッダーが `%PDF-2.n` でない（6.1.2-1）、文書情報辞書が `ModDate` のほかを持つ（6.1.3-5）などの誤りになった。
PDF/A-4 は PDF 2.0 を基礎とする。
PDF/X-4 は PDF 1.6 を基礎とし、Golem の検査も版を 1.6 以下に限る（[`X4.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-pdf/src/Golem/Pdf/X4.hs#L190-L196)）。
一つのファイルを、PDF/A-4 と PDF/X-4 の両方に適合させることはできない。

### 出力インテントのない PDF

intent のない PDF は、黒の文字を色を指定せずに描くので、DeviceGray を使う。
PDF/A-2 の規則 6.2.4.3 は、PDF/A の出力インテントがあれば DeviceGray を許す。
DeviceCMYK は、CMYK のプロファイルを持つ PDF/A の出力インテントがなければ許さない（veraPDF の検証プロファイルの 6.2.4.3-3 の記述で読んだ）。
Golem のスウォッチは DeviceCMYK で描く（[`Writer.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L261-L263)）。
intent のない本に sRGB の出力インテントを足しても、スウォッチを使う本は PDF/A にならない。

### veraPDF が PDF/A-2a と PDF/UA-1 で検査すること

上の増分更新で PDF/A-2u に適合した蟹工船の PDF を、PDF/A-2a と PDF/UA-1 でも検証した（2026-11-07、同じ veraPDF）。
veraPDF は、適合すれば終了コード 0 を、適合しなければ 1 を返した。

- PDF/A-2a では、6.6.4-3（`pdfaid:conformance` が `A` でない）、6.7.2.2-1（`MarkInfo`）、6.7.3.3-1（`StructTreeRoot`）の三つだけが誤りになった。
- PDF/UA-1 では、5-1、6.2-1、7.1-3、7.1-10、7.1-11、7.2-33、7.2-34 に加えて、リンクの注釈についての 7.18.1-2（注釈の代替の文字）、7.18.3-1（`/Tabs /S`）、7.18.5-1（リンクを `Link` の構造の要素にすること）、7.18.5-2（リンクの `/Contents`）が誤りになった。

veraPDF の検証プロファイル（`fc5a92f`）を読むと、PDF/A-2a に固有の規則は八つしかない。
`MarkInfo`、`StructTreeRoot`、標準でない構造の型の対応づけ（三つ）、`Lang` の値の形、私用領域の字の `ActualText`、`pdfaid:conformance` である。
内容がタグ付けされているか、図版に代替の文字があるか、表やリストの形が正しいかは、PDF/A-2a の検証では調べない。

PDF/UA-1 の検証プロファイルは、次のものを自動で調べる。

- すべての内容が、タグ付けされているかアーティファクトであること（7.1-3）。アーティファクトとタグ付けした内容が入れ子にならないこと（7.1-1、7.1-2）。
- 標準でない構造の型の対応づけ（7.1-5 から 7.1-7）。
- `Figure` の代替の文字（7.3-1）。
- 表（`Table`、`TR`、`TH`、`TD` の親子、`TH` の `Scope`、行と列の数）、リスト（`L`、`LI`、`Lbl`、`LBody` の親子）、目次（`TOC`、`TOCI`）の形（7.2-3 から 7.2-43、7.5-1）。
- 見出し：`H1` から始め、段を飛ばさない（7.4.2-1）。
- `Note` の `ID` が一つずつあり重ならないこと（7.9-1、7.9-2）。
- 注釈の代替の文字、リンクの構造の要素、`/Tabs /S`（7.18）。
- 内容、代替の文字、メタデータの言語が決まること（7.2-21 から 7.2-34）。カタログの `/Lang` があれば、内容とメタデータの言語は決まる（7.2-33 と 7.2-34 の検査の式を読んだ）。
- フォントの埋め込み、ToUnicode、`.notdef` の字を描かないこと（7.21）。

PDF/UA-1 には、検証器では調べられない要件もある（代替の文字が図を正しく説明しているか、構造の順が読む順として正しいかなど）。
veraPDF が調べるのは、上の自動で調べられる部分だけである。

### 今の PDF の書き方

PDF を描くのは golem-driver の `Golem.Driver.Pdf.Draw` で、書くのは golem-pdf の `Golem.Pdf.Writer` である。
コードを読み、タグ付けに要る変更を見積もった。

- ページの中身は `Mark` の列である（[`Writer.hs` の `Mark`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L87-L134)、[`Page`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L151-L157)）。字の連なり、罫、円、曲線、画像、図版の Form、色の指定と、それらを `q` と `Q` で包むもの（`Saved`、`Translated`、`Turned`）がある。
- 印付きの内容は、合字の置き換えの文字の `ActualText` だけである（[`contentStreamWith`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L232-L293)、[golem-driver ADR 0030](../golem-driver/adr/0030-ligature-text-layer.md)）。`/Span << /ActualText ... >> BDC` を書き、MCID と構造の木は持たない。
- 一ページの中身は、`drawPage` が、コードの背景、段の行、傍注の行、柱とノンブル、図版、罫、隠しノンブルの順に並べる（[`drawPage`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Draw.hs#L815-L847)）。この順は論理の順ではない。
- 行は `LineRec` の種類（`傍注の行` など）と原稿の位置を持つが、どのブロックのどの部分の行かは持たない。ページの段の格子は、行と図版と見出しとコードブロックの番号を持つ（[`Slotted`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-layout/src/Golem/Layout/Paginate/Types.hs#L157-L167)）。
- 行分割の箱（`BoxContent`）は、行分割の算法が読まない欄をすでに持つ。原稿の位置の `bcSource` は、`golem preflight` のためだけの欄である（[`BoxContent`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-layout/src/Golem/Layout/KnuthPlass.hs#L40-L67)）。同じ形で、箱がどの構造の要素に属すかを持たせられる。
- ルビの親文字と読みは、同じ箱から別々に描く（[`drawLineAt`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Draw.hs#L582-L608)）。親文字と読みを別の印付きの内容にできる。
- 取り込んだ PDF の図版は、ページの中身を Form にして写す。`StructParent` と `StructParents` は写さないが（[`skipKeys`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-pdf/src/Golem/Pdf/Import.hs#L1190-L1191)）、内容のストリームの中の `BMC`、`BDC`、`EMC` は残る。

構造の木は、行やページからは作れない。
意味論 IR からブロックとインラインの要素の木を作り、その葉（字の連なり）が描かれた箱に、葉の番号を持たせる必要がある。
変更は、golem-pdf の書き方（ページの中身の型、構造の木、`ParentTree`）、golem-layout の箱の欄、golem-driver の `Flow` で行を作るすべての経路と `Draw` の描き方に及ぶ。
すべての PDF のバイト列が変わる。
規模は大きいが、記法、意味論 IR、プラグインの ABI は変えない。

## 実装すること

### 範囲

この ADR で、次のことを行う（「メンテナーが決めること」の 1、2、6、7）。

- すべての PDF をタグ付き PDF にする。構造の木、印付きの内容、アーティファクト、カタログの `/Lang`、題の表示を書く。
- `manifest.toml` で宣言した本を、PDF/A-2a と PDF/UA-1 に準拠させる。PDF/A-2a は PDF/X-4 にも準拠する。
- CI で、宣言した fixture の PDF を veraPDF で PDF/A-2a と PDF/UA-1 として検証し、適合しなければ CI を失敗させる。

すべての PDF をタグ付きにするのは、支援技術への対応を落とせない仕様とした決定（[ADR 0187](0187-inline-language-switch.md) の「決めたことの記録」の 2026-11-07）による。
宣言しない本の PDF も、構造をたどって読め、言語が分かる。
宣言は、PDF/A と PDF/UA の識別のメタデータを書かせ、宣言にだけ要る検査をさせるためのものである。

### 宣言（golem-project）

`manifest.toml` の `[targets.pdf]` に、キー `pdfa` と `pdfua` を加える（「メンテナーが決めること」の 3 と 6）。

```toml
[targets.pdf]
pdfa = "2a"
pdfua = "1"
```

- `pdfa` に書ける値は `"2a"` だけ、`pdfua` に書ける値は `"1"` だけとする。ほかの値と、文字列でない値は G03001 とする。値を文字列にしたのは、版と水準を後で足せるようにするためである。
- 二つは別々に書ける。`pdfua` だけを書いた本は、出力インテントを要しない。
- `pdfa` を書き、`style.toml` に `[color] intent` がない本は、G03113（`PDF/A には [color] の intent が要ります`）のエラーとし、PDF を書かない（「メンテナーが決めること」の 4）。位置は `pdfa` の値である。dev と prod の両方でエラーとする。HTML、EPUB、プレーンテキストは書く。
- 文書 ID とインスタンス ID は、今のとおり入力全体のハッシュから作るので、`pdfa` と `pdfua` を変えれば ID も変わる。

### 宣言した本の検査

宣言した本には、veraPDF が調べる要件のうち、原稿で決まり、Golem の構造の木の作り方では満たせないものを、Golem が PDF を書く前に検査する（「メンテナーが決めること」の 8）。
どれもエラーとし、PDF を書かない。
HTML、EPUB、プレーンテキストは書く。

- `pdfa` か `pdfua` を書いた本で、`[metadata] language` が BCP 47 の形でなければ、新しいコード G03119（`PDF/A と PDF/UA には、language を言語のタグの形で書きます: <値>`）とする。位置は `language` の値である。形の検査は、[ADR 0187](0187-inline-language-switch.md) の `[lang]` のタグと同じ関数で行う。PDF/A-2 の 6.7.4-1 と PDF/UA-1 の 7.2-29 は、`/Lang` の値の形を調べる。
- `pdfua` を書いた本で、最初の見出しが 1 の段でないか、見出しの段が二つ以上深くなれば、新しいコード G07103（`PDF/UA では見出しの段を飛ばせません: <前の段> から <この段>`）とする。位置はその見出しである。PDF/UA-1 の 7.4.2-1 の要件である。浅くなる向きには、いくつ段を戻ってもよい。
- `pdfa` を書いた本で、PDF に描く字が Unicode の私用領域（U+E000 から U+F8FF、U+F0000 から U+FFFFD、U+100000 から U+10FFFD）の字に対応づけられれば、新しいコード G07104（`PDF/A-2a の PDF に私用領域の字は書けません: U+<符号位置>`）とする。位置はその字を含む原稿の位置である。PDF/A-2a の 6.2.11.7.3-1 は、私用領域の字に `ActualText` を求めるが、Golem には字の意味が分からない。

コードの番号は、ほかの草案の G03109 から G03118 と G07102 を避けて仮に置いた。
同じ時期の ADR と重なるときは、採択のときに振り直す。

### 構造の木（golem-driver）

意味論 IR から、ISO 32000-1 の標準の構造の型だけで構造の木を作る（「メンテナーが決めること」の 9）。
標準でない型を使わないので、`RoleMap` は書かない。
構造の木の順は、IR の順である。

| IR の要素 | 構造の要素 |
| --- | --- |
| 文書の全体 | `Document`。縦組みの本は、属性 `/A << /O /Layout /WritingMode /TbRl >>` を持つ |
| 段落（段落スタイルによらない） | `P` |
| 見出し（段 n） | `Hn`。見出しの番号と題を含む。今の上限は 3 で、[ADR 0188](0188-headings-beyond-level-3.md) が 6 に広げれば `H6` まで使う |
| 箇条書き、番号付きの箇条書き | `L`（`/A << /O /List /ListNumbering /Disc >>`、番号付きは `/Decimal`）、項目は `LI`、その中の行頭の記号と番号は `Lbl`、項目のブロックは `LBody` |
| 定義リスト | `L`（`/ListNumbering /None`）、組は `LI`、用語は `Lbl`、説明のブロックは `LBody` |
| 表 | `Table`、行は `TR`、見出しの行のセルは `TH`（`/A << /O /Table /Scope /Column >>`）、ほかのセルは `TD` |
| コードブロック | `Div`。キャプション（リスト番号を含む）は `Caption`、コードの行は `P` の中の `Code` |
| 図版 | `Div` の中に、`Figure` とキャプションの `Caption` を並べる。`Figure` は `/Alt` に `figAlt` を、`/A << /O /Layout /BBox [...] /Placement /Block >>` に描いた矩形を持つ |
| 目次（`@toc`） | `TOC`、項目は `TOCI`。項目の題と番号とページ番号を含む |
| 索引（`@index`） | `Index`、見出しの文字と項目の行は `P` |
| 参考文献（`@bibliography`） | `L`（`/ListNumbering /None`）、項目は `LI`、番号は `Lbl`、項目の文は `LBody` の中の `BibEntry` |
| プラグインのチャネルの一覧 | `Div`、項目は `P` |
| ルビ（読みのある区切り一つ） | `Ruby`、親文字は `RB`、読みは `RT` |
| 脚注、傍注、章末の注 | 本文の注の印は `Reference`、その直後に `Note`。`Note` は `ID`（`note-1` から文書の順に振る）、注の側の印の `Lbl`、注の本文の `P` を持つ |
| 相互参照（`[ref-*]`）、引用の印（`[cite]`） | `Reference` |
| 外部のリンク（[ADR 0182](0182-external-links.md)） | `Link`。リンクの文字と、行ごとの注釈の `OBJR` を持つ |
| 文字スタイル `code`（と、それに行き着く文字スタイル） | `Code` |
| ほかの文字スタイル、色、圏点の親文字、縦中横、数、遅延の式の値 | 親の構造の要素の中身のまま（構造の要素を作らない） |

- 図版の `Caption` を `Figure` の外に置くのは、`Figure` の `/Alt` が `Figure` の中身の全体を置き換えるからである。中に置けば、キャプションが読まれない。
- `Note` を注の印の直後に置くのは、支援技術が、注の本文を印の位置で読めるようにするためである（「メンテナーが決めること」の 9）。紙面では注の本文はページの下や章の終わりにあるが、構造の木の順が読む順を決めるので、描く位置は問わない。
- 番号付きの箇条書きの番号、見出しの番号、図版の番号のように、Golem が足した文字も、紙面に見える内容なのでタグ付けする。
- プラグインと `.gm` の関数が返したブロックも、同じ対応で構造の要素にする。
- [ADR 0187](0187-inline-language-switch.md) の言語の区間とブロックの言語は、[ADR 0187](0187-inline-language-switch.md) の実装で、`Span` と構造の要素の `/Lang` として足す。ADR は番号の順に実装するので、この ADR の実装のときには、まだ IR にない。

### アーティファクト

読む内容でないものは、アーティファクトにする。

| 描くもの | 種類 |
| --- | --- |
| 柱、ノンブル、隠しノンブル（[golem-driver ADR 0021](../golem-driver/adr/0021-hidden-folios.md)） | `/Artifact << /Type /Pagination >>` |
| トンボ（レジストレーションの線） | `/Artifact << /Type /Pagination >>` |
| ページをまたいだ表の、二ページめからの見出しの行 | `/Artifact << /Type /Pagination >>`。最初の見出しの行だけを `TH` にする |
| ページをまたいだコードブロックの続きの表示 | `/Artifact << /Type /Pagination >>` |
| 罫（段落と見出しの罫、表の罫、注の区切りの線）、コードの背景と枠、強調と差分の帯、行の中のコードの背景 | `/Artifact << /Type /Layout >>` |
| コードの行番号と折り返した印 | `/Artifact << /Type /Layout >>` |
| 目次の項目のリーダー | `/Artifact << /Type /Layout >>` |
| 圏点の印 | `/Artifact << /Type /Layout >>` |
| 章末の注の一覧の見出し（「注」「Notes」） | `/Artifact << /Type /Layout >>`。`Note` を印の位置に置くので、一覧の見出しは読む順のどこにも入らない |
| 校正のコメント（dev の出力） | `/Artifact << /Type /Layout >>` |

`/Pagination` には `/Subtype` を書かない。
柱とノンブルは、版面の設定によってページの上にも下にも来るので、`Header` と `Footer` を決められないからである。

### 印付きの内容とページの中身の型（golem-pdf）

ページの中身を、タグ付けした内容かアーティファクトしか持てない型にする。

```haskell
-- | What a page shows: each piece is real content of a structure element or an artifact (docs/adr ADR 0183).
data Content
  = Tagged !LeafId ![Mark] -- /<type> << /MCID n >> BDC ... EMC
  | Artifact !ArtifactKind ![Mark] -- /Artifact << /Type /... >> BDC ... EMC
  | Moved !Move ![Content] -- q cm ... Q around content: a translation or a turn (golem-driver ADR 0034)

data ArtifactKind = Pagination | Layout
```

- `Page` の `pageContent` を `[Content]` にする。タグもアーティファクトの印もない内容は、型の上で書けない（PDF/UA-1 の 7.1-3）。`Content` は `Tagged` と `Artifact` を入れ子にしないので、MCID の入れ子と、タグ付けした内容とアーティファクトの入れ子も書けない（7.1-1、7.1-2）。
- `Mark` は今のまま、`ActualText` を持つ。`ActualText` は MCID を持たない `/Span` の印付きの内容で、MCID の印付きの内容の中に入れ子にしてよい。
- `Document` に構造の木を加える。

```haskell
data StructElem = StructElem
  { seType :: !StructType, -- the standard types of ISO 32000-1 14.8.4 only
    seLang :: !(Maybe Text),
    seAlt :: !(Maybe Text),
    seId :: !(Maybe Text),
    seAttrs :: ![Attribute],
    seKids :: ![StructKid]
  }

data StructKid = KidElem !StructElem | KidLeaf !LeafId | KidAnnot !AnnotId
```

- `StructType` は、上の表に使う標準の型だけを持つ閉じた和型とする。標準でない型は書けないので、`RoleMap` は要らない（7.1-5 から 7.1-7）。
- 書き手は、ページを書くときに、`Tagged` の葉に、ページごとに 0 から内容のストリームの順に MCID を振る。一つの葉が二つのページに分かれれば（ページをまたぐ段落の行）、ページごとに別の MCID になり、構造の要素の子は `<< /Type /MCR /Pg p /MCID n >>` になる。
- `StructTreeRoot`、`ParentTree`（数の木）、`ParentTreeNextKey`、`IDTree`（`Note` の `ID`）を書く。ページは `StructParents` を、注釈は `StructParent` を持つ。番号は、ページの順、その後に注釈の順で振る。
- カタログに `/MarkInfo << /Marked true >>` を書く。
- 構造の要素とその辞書のオブジェクトの番号は、今のオブジェクトの並びの後、文書情報辞書の前に、構造の木の前順で振る。出力は今のとおり入力だけで決まる（[golem-pdf ADR 0001](../golem-pdf/adr/0001-deterministic-pdf-writer.md)）。

### 構造の木と描いた箱の対応（golem-layout、golem-driver）

- golem-driver の `Flow` は、行を作るときに、IR のブロックとインラインの要素から構造の木の節を作り、前順で番号を振る。番号は IR だけで決まる。
- golem-layout の `BoxContent` に、箱の字が属す構造の葉の番号の欄を加える。`bcSource` と同じく、行分割の算法は読まない。
- `Draw` は、一つの行の中で、同じ葉の番号を持つ隣り合った箱を一つの `Tagged` にまとめる。ルビの箱は、親文字を `RB` の葉、読みを `RT` の葉の `Tagged` に分ける。圏点の箱は、字を親の葉の `Tagged` に、印を `Artifact` にする。
- 柱、ノンブル、罫、背景のように、`Draw` が行の外で描くものは `Artifact` にする。
- 図版の画像と Form は、`Figure` の葉の `Tagged` にする。回した図版のページ（[golem-driver ADR 0034](../golem-driver/adr/0034-fit-figures-to-column.md)）では、`Moved` の中に `Tagged` と `Artifact` を置く。

### 読む順と縦組み

読む順は、構造の木の順である。
内容のストリームに描く順は今のままとし、論理の順に並べ替えない。
縦組みの本も、構造の木の順で読むので、読む順のための特別な扱いはいらない。
ルビの読みが親文字の直後に描かれ、見出しとノンブルがページの最後に描かれる今の順は、構造の木では、`Ruby` の中の `RB` と `RT` の順と、本文の中の見出しの位置と、アーティファクトになる。

縦組みの本の `Document` は、`WritingMode` を `TbRl` とする属性を持つ。
`WritingMode` は受け継がれる属性で、すべての子に及ぶ。
縦組みの中で回して描く欧文と、縦中横の字は、字の向きが違うだけで、読む順は構造の木の順のままである。

### ルビ

ルビは、読みのある区切り一つごとに `Ruby` の構造の要素にし、親文字を `RB`、読みを `RT` にする。
読みのない区切りの親文字は、`Ruby` を作らず、親の要素の中身にする。
`RP`（ルビの括弧）は使わない。
PDF の紙面には括弧を描かないので、`RP` にする内容がない。
プレーンテキストの `対象（読み）` の括弧は、PDF にはない。

### 言語

- カタログに、`manifest.toml` の `language` を `/Lang` として書く（`/Lang (ja)`）。区間とブロックの言語のない字は、この言語で読む。
- 原稿の一部の言語は、[ADR 0187](0187-inline-language-switch.md) の `[lang]` と `@lang` で決まり、[ADR 0187](0187-inline-language-switch.md) の実装が `Span` と構造の要素の `/Lang` に書く。
- `Figure` の `/Alt`、リンクの注釈の `/Contents`、`ActualText` の言語は、それを含む構造の要素の `/Lang` か、カタログの `/Lang` で決まる（7.2-21 から 7.2-24）。

### リンクの注釈

[ADR 0182](0182-external-links.md) のリンクの注釈に、次のものを足す。

- 注釈の辞書に、`/StructParent` と `/Contents` を書く。`/Contents` は、プレーンテキストのリンクの書き方（[ADR 0182](0182-external-links.md) の「プレーンテキスト」）と同じ文字列とする。散文スロットを書いたリンクは `表示の文字（URL）`、省いたリンクは URL である。
- リンクの `Link` の構造の要素は、リンクの文字の葉と、行ごとの注釈の `OBJR`（`<< /Type /OBJR /Obj n 0 R /Pg p >>`）を、行の順に持つ。行をまたぐリンクも、一つの `Link` になる。
- 注釈のあるページの辞書に、`/Tabs /S` を書く。

### 取り込んだ PDF の図版

取り込んだ PDF の図版の内容のストリームから、`Artifact` の印付きの内容と、`MCID` を持つ印付きの内容の、印の演算子（`BMC`、`BDC`、`EMC`）を取り除き、中の内容は残す。

- 図版は `Figure` の葉の `Tagged` の中に描くので、図版の中の `Artifact` は 7.1-1 に反し、図版の中の MCID は、写さない構造の木を指して宙に浮く。
- `/OC`（オプショナルコンテンツ）の印付きの内容は、表示を変えるので残す。
- 印の演算子は表示を変えないので、図版の見た目は変わらない。
- 今の `Golem.Pdf.Import` は、取り込んだ内容のストリームを一度読みながら DeviceRGB の演算子を書き換えている（[`rewriteContent`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-pdf/src/Golem/Pdf/Import.hs#L1376-L1387)）。印の演算子を取り除くのも、この書き換えに加える。

### PDF/A-2a と PDF/UA-1 の PDF に足すもの

PDF/A を、PDF/X-4 の上にだけ表せる型にする。
`PdfX` に `pxPdfA :: Maybe PdfALevel` を加え、`data PdfALevel = PdfA2a` とする。
PDF/X-4 のない PDF/A は、型の上で作れない。
PDF/UA は、`Document` に `docPdfUa :: Maybe PdfUaPart`（`data PdfUaPart = PdfUa1`）を加えて表す。

`pdfa = "2a"` の PDF には、PDF/X-4 の PDF に次のものを足す。

- カタログの `OutputIntents` の二つめに、`<< /DestOutputProfile n 0 R /OutputConditionIdentifier (...) /S /GTS_PDFA1 /Type /OutputIntent >>` を書く。`n` と `OutputConditionIdentifier` は、`GTS_PDFX` の出力インテントと同じにする。
- XMP（[`X4.hs` の `xmpPacket`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-pdf/src/Golem/Pdf/X4.hs#L45-L86)）に、`pdfaid`、`pdfaExtension`、`pdfaSchema`、`pdfaProperty` の名前空間と、`<pdfaid:part>2</pdfaid:part>`、`<pdfaid:conformance>A</pdfaid:conformance>` を書く。
- XMP に、`pdfxid:GTS_PDFXVersion`（`http://www.npes.org/pdfx/ns/id/`）と `pdf:Trapped`（`http://ns.adobe.com/pdf/1.3/`）を定義する拡張スキーマを書く。値の型は `Text`、分類は `internal` とする。

`pdfua = "1"` の PDF には、次のものを足す。

- XMP に `<pdfuaid:part>1</pdfuaid:part>`（`http://www.aiim.org/pdfua/ns/id/`）を書く。`pdfa` もある PDF では、`pdfuaid:part` を定義する拡張スキーマも書く。PDF/A-2 は、定義済みでないスキーマの属性に拡張スキーマを求めるからである。
- intent のない PDF には今は XMP がないので、`pdfua` の PDF には、intent によらず XMP を書く。XMP には、今の PDF/X-4 の XMP と同じく `dc:title` を書く（7.1-9）。

どれも決まった文字列であり、出力は今のとおり入力だけで決まる。
PDF の版（1.6）、フォント、色、画像の書き方は変えない。
構造の木で使う機能（構造の要素、`ActualText`、`Ruby`、`/Tabs`）は、どれも PDF 1.5 までに入ったもので、版 1.6 のまま書ける。

`Golem.Pdf.X4.verify` と `golem preflight` の G09014 は、PDF/A-2a の PDF にも今のとおり当て、PDF/X-4 の要件を検査する。
PDF/A と PDF/UA の要件を Golem の中で一般に検査する関数は作らない（「実装しないこと」）。

### 言語と題の表示（すべての PDF）

- カタログに `/Lang` を書く（「言語」）。
- カタログに `/ViewerPreferences << /DisplayDocTitle true >>` を書く。閲覧ソフトのタイトルバーに、ファイルの名前（`urn-uuid-….pdf`）の代わりに題を表示させる。
- 宣言しない本にも書く。どちらも閲覧と読み上げにだけ働き、印刷の結果は変えない。

### CI での検証

CI に、veraPDF で PDF/A-2a と PDF/UA-1 を検証するジョブ `verapdf` を加える（「メンテナーが決めること」の 5 と 10）。

**veraPDF の取得**：nixpkgs の `verapdf` を、nixpkgs のコミットを固定して取得する。

- ci.yml の `env` に、nixpkgs のコミットのハッシュ（`VERAPDF_NIXPKGS_REV`）と、そのコミットで作られる x86-64 の Linux の出力の Nix のストアのパス（`VERAPDF_STORE_PATH`）を書く。値は実装のときに決め、版を上げるときはプルリクエストで二つを書き換える。
- ジョブは、Nix を入れるアクション（`cachix/install-nix-action`。CLAUDE.md の規則で、Node 24 以降で動く最新のメジャー版を使う）で Nix を入れ、`nix build --no-link --print-out-paths "github:NixOS/nixpkgs/$VERAPDF_NIXPKGS_REV#verapdf"` で取得する。
- 取得したストアのパスが `VERAPDF_STORE_PATH` と違えば、検証の前に失敗させる。ストアのパスは、ソースの SHA-256 を含む導出の全体から決まるので、違えば別のものを作ったことになる。
- ビルド済みのものは cache.nixos.org から届き、Nix がその署名を確かめる（Nix の既定の `require-sigs`）。
- 取得したものは、Nix のストアをキャッシュせず、ジョブのたびに cache.nixos.org から取る。この環境で取得した veraPDF と依存（JDK を含む）は、約 704 MiB だった。

**検証する PDF**：build のジョブの出力の部（`ubuntu-24.04`）で、次の fixture の写しに宣言を足して組み、成果物 `conformance-pdfs` として上げる。

- 蟹工船（縦組み、ルビ、CFF のフォント）
- The Tempest（横組み、英語、TrueType の可変フォント）
- figures（PNG、JPEG、SVG、PDF の図版、回した図版、キャプション）
- 新しい fixture `conformance`：見出し、箇条書きの入れ子、定義リスト、ページをまたぐ表、キャプションと行番号のあるコードブロック、脚注、傍注、章末の注、目次、索引、参考文献、外部のリンク（[ADR 0182](0182-external-links.md)）、圏点、縦中横、ルビを一冊に含む。横組みと縦組みの二通りに組む。[ADR 0187](0187-inline-language-switch.md) と [ADR 0188](0188-headings-beyond-level-3.md) の実装は、それぞれ言語の区間とブロックの言語、4 段めから 6 段めの見出しを、この fixture に足す。

写しは、`style.toml` に `[color] intent` を、`manifest.toml` の `[targets.pdf]` に `pdfa = "2a"` と `pdfua = "1"` を足す。
写しを作って組むのは、コミットするシェルスクリプト `scripts/ci/conformance-pdfs.sh` である。
CI で使う CMYK の ICC プロファイルは、再配布できるものを選び、ライセンスとともにリポジトリに置く。
Japan Color 2001 Coated の再配布の条件は、この ADR を書くときに確かめていない。
選ぶのは実装のときとし、選んだプロファイルの出所とライセンスを、実装のプルリクエストに書く。

**検証と失敗**：ジョブ `verapdf` は、`build` の後に動き、シェルスクリプト `scripts/ci/verapdf.sh` を走らせる。

- 最初に、`scripts/ci/testdata/verapdf/` に置いた、タグのない小さな PDF を `verapdf -f ua1` で検証し、適合しない（終了コード 1）ことを確かめる。veraPDF の呼び方の誤りで、何でも通る検証にならないためである。
- 次に、`conformance-pdfs` のすべての PDF を `verapdf -f 2a` と `verapdf -f ua1` で検証する。どれか一つでも終了コードが 0 でなければ、その PDF と規則の番号を、veraPDF の文字の報告（`--format text`）で書き、終了コード 1 で終える。
- ジョブ `ci`（main の保護が求める唯一の検査）の `needs` と、`scripts/ci/gate.sh` の `NAMES` に `verapdf` を足す。`verapdf` が失敗すれば `ci` が失敗し、プルリクエストはマージできない（[docs/adr/0021](0021-docs-workflow-and-ci-gate.md)）。
- 文書だけを変えたプルリクエストでは、build と同じく飛ばす。飛ばしたジョブは `gate.sh` で成功と同じに扱う。

### 文書

- [docs/specifications.md](../specifications.md) に、タグ付き PDF の構造の木の対応（上の表）、アーティファクト、読む順、`[targets.pdf]` の `pdfa` と `pdfua`、G03113、G03119、G07103、G07104、PDF/A-2a と PDF/UA-1 の PDF に足すもの、すべての PDF の `/Lang` と `DisplayDocTitle`、CI の veraPDF の検証を書く。
- [docs/diagnostics.md](../diagnostics.md) に G03113、G03119、G07103、G07104 を加え、G03001 の条件に `pdfa` と `pdfua` の値の誤りを加える。
- [docs/roadmap.md](../roadmap.md) の v0.1.0-rc4 から「タグ付き PDF と PDF/A」を消す。v2 以降には何も足さない。
- [docs/roadmap.md](../roadmap.md) の「手で確かめる項目」に、タグ付き PDF をスクリーンリーダー（macOS の VoiceOver と Acrobat Reader、Windows の NVDA と Acrobat Reader）で読み、縦組みとルビと注の読む順を確かめる項目を足す。
- 使い手のマニュアルに、`pdfa` と `pdfua` の書き方と、図版の `alt` が支援技術で読まれることを書く。

## 実装しないこと

- PDF/A-2b と PDF/A-2u を選べるようにすること。すべての PDF をタグ付きにするので、2a に足りないものはない。
- PDF/A-4 と PDF/UA-2。どちらも PDF 2.0 を基礎とし、PDF/X-4 と一つのファイルで両立しない。
- intent のない本の PDF/A（sRGB の出力インテントを足すことなど）。
- PDF/A と PDF/UA の要件を、Golem の中で一般に検査すること（`golem preflight` の検査の追加）。Golem が検査するのは、「宣言した本の検査」の三つだけである。
- 内容のストリームに描く順を、論理の順に並べ替えること。読む順は、構造の木で決める。
- 強い構造（`Sect` と `H`）。見出しは `H1` から `H6` の弱い構造で書き、章や節を `Sect` で包まない。PDF/UA-1 は、強い構造と弱い構造を混ぜることを禁じる（7.4.4-2）。
- 目次の項目の入れ子（`TOCI` の中の `TOC`）。目次は見出しの段によらず一列の `TOCI` にする。
- 圏点の強調を構造で表すこと。PDF 1.7 の標準の型に強調の型（PDF 2.0 の `Em`）がない。
- ルビの属性（`RubyAlign`、`RubyPosition`）。
- 段落スタイルの名前から構造の型を決めること（`quote` を `BlockQuote` にするなど）。段落スタイルの名前は利用者が決めるもので、意味を持たない。
- 取り込んだ PDF の図版の構造の木を写すこと。図版は一つの `Figure` として、`figAlt` で読む。
- 構造の木の外の、PDF のしおりと文書の中のリンク（v1.0.0 の「PDF のしおりと文書の中のリンク」）。
- PDF/A-3 の添付ファイル。

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。

golem-project のテストでは、次のことを確かめる。

- `[targets.pdf]` の `pdfa = "2a"` と `pdfua = "1"` を読めること。`pdfa = "2u"`、`pdfa = "2b"`、`pdfa = "4"`、`pdfa = true`、`pdfua = "2"`、`pdfua = 1` が G03001 になること。

golem-pdf のテストでは、次のことを確かめる。

- `Tagged` が `/<型> << /MCID n >> BDC` と `EMC` で書かれ、MCID がページごとに 0 から内容のストリームの順に振られること。`Artifact` が `/Artifact << /Type /Pagination >> BDC` か `/Layout` で書かれること。
- 二つのページに分かれた葉が、ページごとの MCID と、`/Pg` を持つ `MCR` になること。
- `ParentTree` が、ページの `StructParents` と注釈の `StructParent` から、MCID と注釈の構造の要素を引けること。`IDTree` が `Note` の `ID` を引けること。
- `Link` の構造の要素が `OBJR` を持ち、注釈が `/Contents` と `/StructParent` を持ち、ページが `/Tabs /S` を持つこと。
- すべての PDF のカタログに、`/MarkInfo << /Marked true >>`、`/StructTreeRoot`、本の言語の `/Lang`、`/ViewerPreferences << /DisplayDocTitle true >>` があること。
- PDF/A-2a の PDF のカタログの `OutputIntents` が二つで、`S` が `GTS_PDFX` と `GTS_PDFA1` であり、`DestOutputProfile` が同じ間接オブジェクトを指すこと。
- XMP をゴールデンで固定する。`pdfaid:conformance` が `A` であること。PDF/A-2a と PDF/UA-1 の両方の PDF で、拡張スキーマが `pdfuaid:part` も定義すること。`pdfua` だけの PDF が、intent なしで XMP を持つこと。
- 取り込んだ PDF の図版の、`Artifact` と MCID を持つ印付きの内容の演算子が取り除かれ、`/OC` の印付きの内容と、中の描く演算子が残ること。
- PDF が、決定性の検査と `qpdf --check` を通ること。

golem-driver のテストでは、次のことを確かめる。

- 構造の木を文字にしたもの（型、`/Lang`、`/Alt`、`ID`、属性、子の葉の文字列）をゴールデンで固定する。対象は、sample の fixture、蟹工船の fixture、新しい `conformance` の fixture である。上の対応の表の行ごとに、その構造の要素ができることを確かめる。
- ページをまたぐ表の二ページめの見出しの行、柱、ノンブル、罫、圏点の印が、アーティファクトで、構造の木の葉にないこと。
- 縦組みの本の `Document` が `WritingMode` の `TbRl` を持つこと。
- ルビの `Ruby` の中が `RB`、`RT` の順で、`RT` の葉の文字列が読みであること。
- `Note` が注の印の `Reference` の直後にあり、`ID` が文書の中で重ならないこと。
- `pdfa = "2a"` を書き、`[color] intent` のない本が G03113 になり、位置が `pdfa` の値で、PDF を書かず、HTML とプレーンテキストを書くこと。dev と prod の両方で同じであること。
- `pdfua = "1"` の本で、`language = "日本 語!"` が G03119、`#` の直後の見出しを `###` にした原稿と、最初の見出しが `##` の原稿が G07103 になること。`###` の後に `#` を置いた原稿は通ること。`pdfua` のない本では、どれも誤りにならないこと。
- `pdfa = "2a"` の本で、原稿の U+E000 の字が G07104 になること。
- `pdfa = "2a"` と `[color] intent` のある本の PDF が、`X4.verify` で何も報告されないこと。
- 見た目の回帰テストの参照の画像が変わらないこと。タグ付けは描く内容を変えない。

CI の veraPDF のジョブでは、「CI での検証」の PDF が、`verapdf -f 2a` と `verapdf -f ua1` で適合と判定されることを確かめる。
このジョブが失敗することも一度確かめる。
タグ付けを実装する前の golem で組んだ PDF を `conformance-pdfs` に入れ、ジョブが失敗し、`ci` が失敗することを、実装のプルリクエストで一度示す。

## トレードオフ

すべての PDF をタグ付きにするので、宣言しない本の PDF のバイト列も変わり、構造の木と `ParentTree` の分だけ大きくなる。
大きくなる量は測っていない。
見た目は変わらない。
その代わり、宣言の有無で PDF を書く経路が分かれず、どの本も支援技術で読める。

PDF/A-2a と PDF/UA-1 を宣言した PDF は、Golem が書くものについては veraPDF で確かめるが、利用者が入れた PDF の図版の中身までは確かめない。
取り込んだ PDF が PDF/A の規則に反する要素（埋め込んでいないフォントなど）を持てば、Golem の PDF も適合しなくなる。
PDF/X-4 と同じく、入稿や保存の前に、利用者が veraPDF などで確かめることになる（[golem-pdf ADR 0003](../golem-pdf/adr/0003-pdf-x-4-validator.md)）。

veraPDF が調べるのは、PDF/UA-1 の要件のうち、検証器が自動で調べられるものだけである。
構造の木の順が正しく読めるか、代替の文字が図を説明しているかは、スクリーンリーダーで手で確かめる。
Golem の構造の木は IR から決まった規則で作るので、原稿の構造が正しければ、読む順も正しくなる。

PDF/A に intent を要するので、PDF/A の PDF はいつも PDF/X-4 にも準拠する。
印刷を考えない本でも、CMYK の出力インテントを用意することになる。
その代わり、Golem の色の扱い（スウォッチを CMYK で書くこと）を変えずに済む。
支援技術のための PDF/UA は、intent なしで宣言できる。

注を印の位置で読ませるので、スクリーンリーダーは文の途中で注の本文を読む。
注の本文をページの下や章の終わりで読む案より、印と注の対応が分かりやすいと考えた。
圏点は印をアーティファクトにするので、強調は読み上げで伝わらない。
章末の注の一覧の見出しは、アーティファクトにするので読まれない。

見出しの段を飛ばす原稿は、`pdfua` を宣言すると組めなくなる。
宣言しない本は今のとおり組めるが、その PDF の見出しの構造は PDF/UA-1 の要件を満たさない。

CI に veraPDF を加えると、CI の時間と取得する量が増える。
この環境で取得した veraPDF と依存（JDK を含む）の Nix のクロージャは、`nix path-info -rS` で約 704 MiB だった。
GitHub Actions に Nix を入れる時間と、検証の時間は、この ADR を書くときに測っていない。
蟹工船の PDF の PDF/A-2b の検証は、この環境で約 1.6 秒だった。

## 決めたことの記録

- **ロードマップの項目**（2026-10-16、ロードマップ）：v0.1.0-rc4 の PDF の節に「タグ付き PDF と PDF/A」を置いた。
- **タグ付き PDF と PDF/A をこの ADR で扱うこと**（2026-11-07、メンテナー）：タグ付き PDF と PDF/A は、この ADR で対応する。v2 の肥大化を抑えたいので、v2 に回さない。草稿の推奨（PDF/A-2u だけを行い、タグ付けを v2 以降に回す）を退けた。
- **veraPDF の CI**（2026-11-07、メンテナー）：veraPDF を CI で使えるようにし、PDF を検査する。
- **ほかの項目**（2026-11-07、メンテナー）：v2 に回そうとした部分のほかは、推奨のとおりとした。「メンテナーが決めること」の 3、4、5 である。
- **支援技術**（2026-11-07、メンテナー、[ADR 0187](0187-inline-language-switch.md) の確認で）：支援技術への対応は落とせない仕様である。本はすべての人のためにある。この ADR の「メンテナーが決めること」の 7 の推奨は、これによる。
- **タグ付けの詳細**（2026-11-07、メンテナー）：問題ないとした。「メンテナーが決めること」の 6 から 10 を推奨のとおりとした。
- **影響の大きい点**（2026-11-07、メンテナー）：タグ付けの大きな変更と、この ADR を [ADR 0187](0187-inline-language-switch.md) と [ADR 0188](0188-headings-beyond-level-3.md) の前に実装する順は問題ない。正しい設計のために受け入れる。同じ日に、[ADR 0177](0177-note-mark-style-and-numerals.md) で注のある縦組みの本の PDF がすべて変わること、[ADR 0173](0173-rc4-refactoring.md) の多くの `build-depends` の変更、[ADR 0189](0189-paragraph-alignment-spacing-and-end-indent.md) を [ADR 0180](0180-verse-spacing-and-stanza-breaks.md) の前に実装する順も、同じ理由で受け入れた。

## メンテナーが決めること

すべて決めた（「決めたことの記録」）。
6 から 10 は、タグ付けをこの ADR で扱うという決定を受けて加えた。

1. **この ADR の範囲**：決めた。タグ付き PDF と PDF/A の両方を、この ADR で扱う。草稿は、PDF/A-2u だけを行い、タグ付けを後に回すことを推奨していた。
2. **タグ付けを扱うバージョン**：決めた。この ADR で扱い、v2 以降に回さない。ロードマップの v2 以降に項目を足さない。
3. **宣言の置き場所と値**：決めた。`manifest.toml` の `[targets.pdf]` のキー `pdfa` に、文字列で書く。`intent` のある本をいつも PDF/A にする案、`style.toml` に置く案、真偽値にする案、CLI の引数にする案は退けた。書ける値は 6 で決める。
4. **intent のない本の PDF/A**：決めた。エラー（G03113）とする。
5. **CI で veraPDF を得る方法**：決めた。版を固定した nixpkgs から `verapdf` を取得する。この ADR では、nixpkgs のコミットに加えて、出力の Nix のストアのパスも固定して確かめる形にした（「CI での検証」）。
6. **宣言できる準拠の水準**：決めた。`pdfa = "2a"` と `pdfua = "1"` の二つのキーとし、それぞれ一つの値だけを書けるようにする。
   PDF/A-2a だけでは足りない。
   veraPDF の PDF/A-2a の検証は、`MarkInfo` と `StructTreeRoot` があるかなどの八つの規則しか持たず、内容がタグ付けされているかを調べない（「文脈」）。
   内容のタグ付け、図版の代替の文字、表とリストと見出しの形を veraPDF に調べさせるには、PDF/UA-1 として検証する必要がある。
   PDF/UA-1 を別のキーにするのは、PDF/UA が出力インテントを要さず、印刷を考えない本でも宣言できるようにするためである。
   退けた案は四つある。
   `pdfa = "2u"` を残す案は、すべての PDF をタグ付きにすれば 2a に足りないものがなく、選ばせる理由がない。
   PDF/A-2a だけにする案は、タグ付けの誤りを veraPDF が見つけられない。
   PDF/A-4 と PDF/UA-2 にする案は、PDF 2.0 を基礎とし、PDF/X-4（PDF 1.6）と一つのファイルで両立しない。
   `pdfa` に PDF/UA を含める案（`pdfa = "2a"` で PDF/UA-1 も宣言する）は、PDF/UA だけを宣言したい本が出力インテントを用意することになる。
7. **タグ付けをすべての PDF に行うか**：決めた。宣言によらず、すべての PDF をタグ付きにする。支援技術への対応を落とせない仕様とした決定（[ADR 0187](0187-inline-language-switch.md)）に従う。退けた案は、`pdfa` か `pdfua` を宣言した本だけをタグ付きにすることである。宣言しない多くの本が支援技術で読めないまま残り、PDF を書く経路が宣言の有無で二つに分かれる。
8. **宣言した本の追加の検査**：決めた。`language` の形（G03119）、見出しの段の飛び（G07103）、私用領域の字（G07104）を、宣言した本でだけエラーにする。
   退けた案は三つある。
   検査せずに書く案は、Golem が適合しない PDF に PDF/A や PDF/UA の識別を書き、利用者が veraPDF で初めて気づく。
   notice にとどめて書く案も、適合しない PDF に識別を書く点は同じである。
   見出しの段を Golem が詰めて書く案（`#` の次の `###` を `H2` にするなど）は、原稿と違う構造を、知らせずに出力に書く。
   すべての本で検査する案は、宣言しない本が今のとおり組めなくなる。
9. **注の構造の位置**：決めた。`Note` を本文の注の印（`Reference`）の直後に置く。HTML と EPUB は注を章末に置き、本文の参照とリンクでつなぐが、PDF の文書の中のリンクは v1.0.0 まで入らない。印の直後に置けば、リンクがなくても、支援技術で注を印と対応づけて読める。退けた案は、紙面に描いた位置（ページの下、章の終わり）に置くことである。スクリーンリーダーは、注の本文を、印から離れたページの終わりや章の終わりで読み、どの印の注かを読み手が対応づけることになる。
10. **CI で検証する PDF**：決めた。蟹工船、The Tempest、figures の三つの fixture の写しと、すべての構造の要素を含む新しい fixture `conformance` の横組みと縦組みの二通りとする。
    退けた案は二つある。
    十冊の PD の本（`GOLEM_PD_BOOKS`）もすべて検証する案は、CI の時間が延び、構造の要素の種類は `conformance` の fixture で足りる。
    `conformance` の fixture だけにする案は、縦組みのルビの多い本文、英語の本文と可変フォント、PDF と SVG の図版のような、実際の本の組み合わせを確かめられない。

## 参考文献

- ISO 19005-2:2011, *Document management: Electronic document file format for long-term preservation, Part 2: Use of ISO 32000-1 (PDF/A-2)*。本文は参照していない。規則は veraPDF の検証プロファイル（https://github.com/veraPDF/veraPDF-validation-profiles 、`fc5a92f`）の `PDF_A/2b` と `PDF_A/2a` の記述（6.2.3、6.2.4.3、6.2.11.7.3、6.3.2、6.3.3、6.6.2.3.1、6.6.4、6.7）で読んだ。
- ISO 19005-4:2020（PDF/A-4）。本文は参照していない。veraPDF の判定（6.1.2-1、6.1.3-5）で確かめた。
- ISO 14289-1:2014（PDF/UA-1）。本文は参照していない。規則は veraPDF の検証プロファイルの `PDF_UA/1` の記述（5、6.2、7.1、7.2、7.3、7.4、7.5、7.9、7.18、7.21）と判定で読んだ。
- ISO 32000-1:2008, 14.7 Logical Structure, 14.8 Tagged PDF（標準の構造の型と属性、本当の内容とアーティファクト）、14.9.2 Natural Language Specification。節の番号と内容は、この ADR を書くときに本文で確かめていない。構造の型の親子と属性は、veraPDF の PDF/UA-1 の規則の記述と照らした。
- ISO 15930-7:2010（PDF/X-4）。本文は参照していない（[golem-pdf ADR 0002](../golem-pdf/adr/0002-pdf-x-4.md) と同じ）。
- veraPDF 1.30. https://verapdf.org/
- nixpkgs の `verapdf` 1.30.2 のソース. https://github.com/veraPDF/veraPDF-apps/archive/refs/tags/v1.30.2.tar.gz
- PDF Association, *Matterhorn Protocol 1.1*（PDF/UA-1 の検査の条件の一覧）. https://pdfa.org/resource/the-matterhorn-protocol/ 。この ADR を書くときに本文は読んでいない。
- [golem-pdf ADR 0001](../golem-pdf/adr/0001-deterministic-pdf-writer.md)、[golem-pdf ADR 0002](../golem-pdf/adr/0002-pdf-x-4.md)、[golem-pdf ADR 0003](../golem-pdf/adr/0003-pdf-x-4-validator.md)、[golem-driver ADR 0021](../golem-driver/adr/0021-hidden-folios.md)、[golem-driver ADR 0030](../golem-driver/adr/0030-ligature-text-layer.md)、[golem-driver ADR 0034](../golem-driver/adr/0034-fit-figures-to-column.md)、[docs/adr/0021](0021-docs-workflow-and-ci-gate.md)、[ADR 0182](0182-external-links.md)、[ADR 0187](0187-inline-language-switch.md)、[ADR 0188](0188-headings-beyond-level-3.md)
