# ADR 0011: CFF のフォントは CFF の表だけを `CIDFontType0C` で埋め込む

ステータス: 採択

## 文脈

[golem-font ADR 0002](../../golem-font/adr/0002-subsetting-and-embedding.md) は、輪郭が CFF のフォントを `CIDFontType0` と `FontFile3` で埋め込むと決めた。
`FontFile3` のストリームの `Subtype` と、ストリームに入れるバイト列の形（OpenType のフォントの全体か、CFF の表だけか）は決めていない。

[ADR 0006](0006-cid-system-info.md) は、文脈の「今の実装」で、CFF のフォントを `FontFile3`（`/Subtype /OpenType`）で書くと記した。
これは [ADR 0006](0006-cid-system-info.md) の文脈に書いた実装の記述であり、`Subtype` を決めたものではない。
[ADR 0006](0006-cid-system-info.md) をコミットした時点で、コードはすでにコミット cfaf4149 で埋め込みの形を変えており、この記述は古くなっていた。

コミット cfaf4149 の前は、CFF のフォントのサブセットを OpenType のフォントのまま `FontFile3` に入れ、`/Subtype /OpenType` を付けていた。
内容のストリームの文字のコードは、CID-keyed の CFF では CID である（[ADR 0006](0006-cid-system-info.md)）。
Chromium の PDF のビューアー（PDFium）は、OpenType に包んだ CID-keyed の CFF では、文字のコードをグリフ ID として読む。
Noto Serif JP は CID とグリフ ID が一致しないので、和文が一字も描かれず、CID とグリフ ID が一致する欧文だけが描かれた。

今のコードは次のとおりである。

- golem-driver の `Golem.Driver.Fonts` は、CFF のフォント（`fontIsCff`）のサブセットから `CFF ` の表だけを取り出し（`sfntTable`）、`CffProgram` として渡す。表が見つからなければ、OpenType のフォントの全体を `OpenTypeProgram` として渡す。
- golem-pdf の `Golem.Pdf.Writer.fontObjects` は、`CffProgram` を `FontFile3` に `/Subtype /CIDFontType0C` で、`OpenTypeProgram` を `/Subtype /OpenType` で書く。TrueType のフォントは `FontFile2` で書き、`Subtype` を付けない。
- golem-driver の `test/PdfSpec.hs` の「with real fonts: subset OpenType fonts, ToUnicode, deterministic and parallel-safe」が、PDF に `/Subtype /CIDFontType0C` があり、`/Subtype /OpenType` がないことを確かめている。

この形を決めた ADR がない。
docs/specifications.md の「フォント」の節も、Type 0 のフォントと CIDFont で書くことと `CIDSystemInfo` だけを書き、`FontFile3` の形を書いていない。

### 規格の記述

ISO 32000-1:2008（Adobe が公開する `PDF32000_2008.pdf`）の本文で確かめた。

9.9「Embedded Font Programs」の Table 126（Embedded font organization for various font types）は、`FontFile3` の `Subtype` の三つの値を、使える font dictionary とともに定める。

- `Type1C`（PDF 1.2）：CFF で表した Type 1 相当のプログラムである。Type1 か MMType1 の font dictionary の font descriptor にだけ現れうる。
- `CIDFontType0C`（PDF 1.3）：CFF で表した Type 0 の CIDFont のプログラムである。CIDFontType0 の CIDFont dictionary の font descriptor に現れうる。
- `OpenType`（PDF 1.6）：OpenType のフォントのプログラムである。CIDFontType0 の CIDFont dictionary には、`CFF ` の表の Top DICT が CIDFont の演算子を使う場合（表は「`CIDFontType0C` と同等」とする）と、使わない場合の両方で現れうる。どちらも、`CFF ` の表のほかに `cmap` の表を含まなければならない。

Table 127（Additional entries in an embedded font stream dictionary）の `Subtype` も、`FontFile3` から参照するときに必須とし、`Type1C`、`CIDFontType0C`、`OpenType` のどれかとする。

9.7.4.2「Glyph Selection in CIDFonts」は、CFF のプログラムを埋め込んだ CIDFont について、font descriptor の `FontFile3` は `CIDFontType0C` か `OpenType` でよいとし、グリフの選び方を二つの場合に分ける。

- Top DICT が CIDFont の演算子を使う（CID-keyed の）CFF：CID から、CFF の charset の表で GID を求め、その GID で CharStrings INDEX のグリフを引く。本文の注は、CID と GID が異なりうることを述べる。
- Top DICT が CIDFont の演算子を使わない CFF：CID をそのまま GID として使い、CharStrings INDEX のグリフを引く。

この二つの場合の区別は、`Subtype` が `CIDFontType0C` か `OpenType` かによらない。
9.9 の終わりの段落も、CIDFontType0 の `CFF` の表のグリフの選び方は 9.7.4.2 のとおりとする。

ここから次のことが分かる。

- `CIDFontType0` の `FontFile3` に使える `Subtype` は、`CIDFontType0C` と `OpenType` の二つだけである。`Type1C` は単純なフォント（Type1、MMType1）のためのものであり、CIDFont には使えない。
- CID-keyed でない CFF を `CIDFontType0C` で埋め込み、グリフ ID を CID として書く今の形（[ADR 0006](0006-cid-system-info.md)）は、9.7.4.2 の二つ目の場合に当たり、規格が定める形である。
- OpenType に包んだ CID-keyed の CFF でも、CID は charset で GID に写さなければならない。PDFium が文字のコードをグリフ ID として読むのは、9.7.4.2 と食い違う PDFium の振る舞いであり、Golem が以前に書いていた `/Subtype /OpenType` の形は規格の上では正しかった。
- PDF/X-4 は PDF 1.6 を基にするので、`CIDFontType0C`（PDF 1.3）も `OpenType`（PDF 1.6）も使える。

ISO 32000-2:2020 の本文は読んでいない。
ISO 32000-2 を写した PDF Association の Arlington PDF Model（コミット d148fee5）も、`CIDFontType0` の `FontFile3` の `Subtype` を `CIDFontType0C` と、PDF 1.6 以降の `OpenType` に限っており、ISO 32000-1 と同じである。

## 実装すること

### 埋め込みの形

今の実装のとおり、輪郭が CFF のフォントは、サブセットの OpenType のフォントから `CFF ` の表だけを取り出し、`FontFile3` に `/Subtype /CIDFontType0C` で埋め込むと決める。

- `CIDFont` は `CIDFontType0` のままとする（[golem-font ADR 0002](../../golem-font/adr/0002-subsetting-and-embedding.md)）。
- `CIDSystemInfo` と文字のコードは [ADR 0006](0006-cid-system-info.md) のとおりとする。CID-keyed の CFF では CID を、そうでない CFF ではグリフ ID を文字のコードとする。
- CID-keyed でない CFF（たとえば Source Sans Pro）も、同じく `CIDFontType0C` で書く。
- `/Subtype /OpenType` の `FontFile3` は書かない。

### CFF の表を取り出せない場合

今の実装は、サブセットから `CFF ` の表を取り出せないと、OpenType のフォントの全体を `/Subtype /OpenType` で書く。
この形は規格が定める（ISO 32000-1 の Table 126 と 9.7.4.2）が、PDFium は CID-keyed の CFF の和文を描かない。
Golem は、ビューアーで描けない PDF を黙って書かない。
そのため、この場合をエラーにする。

| コード | 重大度 | 対象 | メッセージ | 位置 |
|---|---|---|---|---|
| G08018 | エラー | CFF の表を取り出せないフォント | `フォントから CFF の表を取り出せません: <パス>` | `style.toml` の先頭（`style.toml` がなければマニフェストの先頭） |

- `<パス>` は、`style.toml` に書いたとおりのフォントのパスである。
- PDF を組むとき（`golem build` の PDF と `golem preflight`）に出し、dev と prod の両方でエラーとする。G08018 があれば PDF を書かない。
- 位置は、ほかのフォントの diagnostic（G08002、G08003）と同じく `style.toml` の先頭とする。
- golem-pdf の `FontProgram` から `OpenTypeProgram` を除く。`Golem.Driver.Fonts` は、表を取り出せなければ `CffProgram` を作らず G08018 を返す。
- G08 の番号は G08014 まで使っている。G08015 は [docs/adr/0051](../../adr/0051-reuse-repeated-pdf-content-streams.md) の草稿が、G08016 と G08017 は [docs/adr/0054](../../adr/0054-svg-marker-cycle-and-depth-codes.md) の草稿が使う。G08018 は、origin の各ブランチと、この worktree のほかの草稿で使われていない。

### ADR のステータス

- [ADR 0006](0006-cid-system-info.md) のステータスの行の末尾に、次を足す。

  ```
  、CFF のフォントの `FontFile3` の形は [ADR 0011](0011-cff-fontfile3-subtype.md)
  ```

- [golem-font ADR 0002](../../golem-font/adr/0002-subsetting-and-embedding.md) のステータスの行の末尾に、次を足す。

  ```
  、`FontFile3` の `Subtype` は [golem-pdf ADR 0011](../../golem-pdf/adr/0011-cff-fontfile3-subtype.md)
  ```

### ドキュメント

- docs/specifications.md の「フォント」の節の、埋め込みの形を書いた段落（Type 0 のフォントと CIDFont で書く、の段落）に、次を足し、この ADR へのリンクを付ける。
  - 輪郭が CFF のフォントは `CIDFontType0` とし、`FontFile3` に CFF の表だけを `/Subtype /CIDFontType0C` で埋め込む。
  - 輪郭が TrueType のフォントは `CIDFontType2` とし、`FontFile2` に埋め込む。
  - OpenType に包んだ CFF を埋め込まない理由（PDFium が文字のコードをグリフ ID として読む）と、CFF の表を取り出せないフォントを G08018 とすること。
- `docs/diagnostics.md` に G08018 の節を足す。
- 使い手のマニュアルの付録 E に G08018 を足す。

## 実装しないこと

- CID-keyed でない CFF を `Type1C` で埋め込むこと。ISO 32000-1 の Table 126 は、`Type1C` を Type1 と MMType1 の font dictionary にだけ認め、`CIDFontType0` には認めない。単純なフォント（Type 1）で埋め込むことは、Golem がどのフォントも Type 0 のフォントと CIDFont で埋め込むので（[golem-font ADR 0002](../../golem-font/adr/0002-subsetting-and-embedding.md)）、選ばない。
- `CFF2` の表を持つフォント（可変フォントの CFF2）の扱い。今の `fontIsCff` は `CFF ` の表だけを見るので、この ADR の範囲の外である。
- サブセットを作れないときに元のフォントの全体を埋め込む今の振る舞い（`subsetFont` が `Nothing` を返したとき）の変更。元のフォントから `CFF ` の表を取り出せれば、`CIDFontType0C` で書く。

## テスト設計

次のテストを先に書き、失敗させてから実装する。

- golem-driver の `Golem.Driver.Fonts` で、`CFF ` の表を持たない OpenType のバイト列（`CFF ` を別の名前に書き換えた Source Sans Pro など）を CFF のフォントとして埋め込もうとすると、G08018 になり、`/Subtype /OpenType` の `FontFile3` を作らないこと。
- golem-driver の `test/PdfSpec.hs`：そのフォントを `[fonts.body]` に書いたプロジェクトの PDF のビルドが、`style.toml` の先頭に G08018 を一つ出し、PDF を書かないこと。

今の振る舞いを固定するテストを足す。

- golem-driver の `test/PdfSpec.hs` の「with real fonts ...」が、`/Subtype /CIDFontType0C` があり `/Subtype /OpenType` がないことを確かめている（今のテスト）。このテストは Noto Serif JP（CID-keyed の CFF）を使う。
- CID-keyed でない CFF のフォント（golem-font のテストの Source Sans Pro）で組んだ PDF でも、`FontFile3` が `/Subtype /CIDFontType0C` であり、そのストリームの先頭が CFF のヘッダー（版の番号 1）で、`OTTO` で始まらないことを確かめるテストを足す。
- 手で確かめること：Noto Serif JP と Source Sans Pro で組んだ PDF を、Chromium の PDF のビューアーと Poppler（`pdftoppm`）で開き、和文と欧文が描かれることを見る。

golem-syntax では、次を確かめる。

- docs の diagnostic の一覧とコードの一致の検査が、G08018 を含めて通ること。

## トレードオフ

- `CIDFontType0C` は CFF の表だけを埋め込むので、OpenType のほかの表（`GSUB`、`GPOS`、`cmap` など）は PDF に入らない。PDF の描画はグリフ ID か CID と輪郭だけで足り、シェイピングは Golem が先に済ませているので、失うものはない。
- `/Subtype /OpenType` は規格が定める形であり、和文を描かないのは PDFium が 9.7.4.2 と食い違うためである。それでも、PDFium は Chromium の PDF のビューアーとして広く使われるので、ビューアーの互換を優先した。`CIDFontType0C` も規格が定める形なので、規格から外れることはない。
- 今は `/Subtype /OpenType` で書けていたフォントが、G08018 で PDF を組めなくなる。どういうフォントで表を取り出せないかは確かめていない。サブセットを作れずに元のフォントを使った場合で、元のフォントが一つの OpenType でないとき（たとえばフォントのコレクションの `.ttc`）が考えられる。

## 参考文献

- [golem-font ADR 0002](../../golem-font/adr/0002-subsetting-and-embedding.md)
- [ADR 0006](0006-cid-system-info.md)
- [docs/adr/0054](../../adr/0054-svg-marker-cycle-and-depth-codes.md)（G08016、G08017）
- コミット cfaf4149（fix(golem-driver): embed CFF fonts as bare CFF (CIDFontType0C)）
- ISO 32000-1:2008, 9.7.4.2 Glyph Selection in CIDFonts、9.9 Embedded Font Programs（Table 126、Table 127）。Adobe が公開する版（SHA-256 `9de0ca9e8570d6209e8bd48a355be8eb6ec376acfc3fc3ae97cd8730351417ff`）。https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf
- PDF Association, Arlington PDF Model, `tsv/latest/FontDescriptorCIDType0.tsv`、`FontFile3CIDType0.tsv`、`FontFile3OpenType.tsv`（コミット d148fee5）。https://github.com/pdf-association/arlington-pdf-model
- Adobe, Technical Note #5176, The Compact Font Format Specification。
