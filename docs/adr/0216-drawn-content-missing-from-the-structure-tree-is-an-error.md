# ADR 0216: 構造の木にない内容を描いた PDF をエラーにする

ステータス: 採択→テストの置き場所とテスト用の関数は [ADR 0236](0236-record-what-implementations-decided-found-by-the-second-review-of-2026-11-08.md)

## 文脈

[ADR 0183](0183-tagged-pdf-and-pdf-a.md) は、すべての PDF に構造の木を付けることにした。
golem-typeset が意味論 IR から構造の木を作り、木の葉に番号を振る。
描く箱は、その字が属す葉の番号を持ち、`Draw` は同じ葉の隣り合った箱を一つの印付きの内容（`Tagged`）にまとめる（0183 の「構造の木と描いた箱の対応」）。
柱、ノンブル、罫のように行の外で描くものは、アーティファクトにする。
したがって、描いた印付きの内容の葉は、どれも構造の木にあるはずである。
0183 は、木にない葉を描いた場合を書いていない。

### 実装の fallback

golem-pdf の書き手は、描いた葉のうち木にないもの（孤立した葉）を、一つずつ `P` にして、`Document` の子の最後に足す（[`withOrphans`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L651-L664)、呼ぶところは [`Writer.hs` の 547 行](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L547)）。
diagnostic は出さない。
golem-pdf のテストは、この振る舞いを「a leaf drawn but not in the tree becomes a P at the end of the Document」として固定している（[`test/Main.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-pdf/test/Main.hs#L616-L618)）。
仕様書にも書かれていない。

孤立した葉ができるのは、Golem の誤りのときだけである。
構造の木を作る処理（[`structureTree`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-typeset/src/Golem/Typeset/Structure.hs#L44-L123)）と、箱に葉の番号を振る処理（`Flow`）は別々にあり、片方に単位の種類や場所を足して、もう片方に足し忘れると、孤立した葉ができる。
たとえば、`unitKids` は知らない単位の種類に `[]` を返す（[`Structure.hs` の 123 行](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-typeset/src/Golem/Typeset/Structure.hs#L123)）。
書き手の原稿では直せない。

### 孤立した葉が今あるか

conformance の fixture を横組みで組んだ PDF と、表のセル、定義リストの用語と説明、箇条書きの項目に脚注を置き、`[notes]` の `placement` を `"page-foot"` と `"chapter-end"` にした小さな本の PDF の構造の木を読んだ（`golem 0.1.0-rc3`、`bcbe7140` のビルド、2026-11-08）。
どれも、`Document` の子の最後は原稿の最後の段落であり、孤立した葉の `P` は見つからなかった。
今の fixture で fallback が働く入力は、見つけていない。

### fallback が出力をどう変えるか

孤立した葉は、紙面のどこに描いても、読む順では文書の最後になり、見出しや表のような本来の構造の型を失う。
PDF/UA-1 を宣言した本でも、veraPDF の自動の検査はこれを誤りとしない可能性がある（`P` は標準の型で、読む順の誤りは自動の検査の外にある）。
カタログは `/MarkInfo << /Marked true >>` を持ち、読む順が正しいと宣言したまま、その宣言に反する PDF を書く。
Golem は出力を黙って変えないので、この fallback は原則に反する。

## 実装すること

### 検査（golem-pdf、golem-typeset）

- golem-pdf は、構造の木と描いた葉から孤立した葉を返す関数 `orphanLeaves :: StructElem -> [LeafId] -> [LeafId]` を公開する。順は、最初に描いた順とする。
- golem-typeset は、すべてのページを描いた後、PDF を書く前に `orphanLeaves` を呼ぶ。孤立した葉が一つでもあれば、新しいエラー G07107 を出し、PDF を書かない（「メンテナーが決めること」の 1）。
- G07107 は、孤立した葉ごとではなく、PDF ごとに一つ出す。原因は Golem の一つの誤りであり、書き手が直すことはない。
- 重大度は、dev でも prod でも、`pdfa` と `pdfua` の宣言によらずエラーとする（「メンテナーが決めること」の 2）。
- 位置は、最初の孤立した葉の番号から引ける原稿の位置とする。単位の葉（`unitSite` などの単位の番号で始まる番号）はその単位の位置、注と傍注の葉（`noteSite`、`sidenoteSite`）はその注の位置である。引けないときは `manifest.toml` の先頭とする。
- 書き手の `withOrphans` は、関数が全域であるために残すが、golem からは孤立した葉を渡さない。注釈に、G07107 の検査の後でしか呼ばないことを書く。

メッセージは次のとおりとする。

```text
G07107: 構造の木にない内容を描きました（<n> か所）。Golem の誤りです。この入力を添えて報告してください
```

### 文書

- docs/specifications.md の「タグ付き PDF」の節に、描いた印付きの内容がすべて構造の木にあること、ないときは G07107 で PDF を書かないことを書く。
- docs/diagnostics.md に G07107 の節を足す。「直し方」は G08001 と同じく、利用者が直すことはなく、Golem の誤りとして報告する、とする。golem-driver の `golem explain` の埋め込みの文書も足す。
- [ADR 0183](0183-tagged-pdf-and-pdf-a.md) のステータスの行に、「構造の木にない内容の扱いは ADR 0216」と足す。

## 実装しないこと

- **孤立した葉の原因を直すこと**：今の fixture では見つかっていない。見つかったときは、その原因を直すプルリクエスト（必要なら ADR）で扱う。
- **書き手の `withOrphans` を消すこと**：golem-pdf の関数を全域に保つために残す。
- **木にあって描かない葉**：構造の木の葉のうち、どのページにも描かないもの（空の葉）は、今のとおり書かない。この ADR は、描いたものが木にあることだけを確かめる。

## 不変条件

ある PDF の構造の木の葉の集合を T、描いた印付きの内容（`Tagged`、中身のあるもの）の葉の並びを D とする。

- **S1**：D のすべての葉が T にあるとき、G07107 は出ず、PDF のバイト列はこの ADR の前と同じである。
- **S2**：D に T にない葉があるとき、G07107 がちょうど一つ出て、PDF を書かない。`<n>` は、T にない D の葉の異なるものの数である。
- **S3**：S2 の位置は、T にない最初の葉から決まり、同じ入力からは同じ位置になる。
- **S4**：G07107 の有無は、dev と prod、`pdfa` と `pdfua` の宣言によらない。
- **S5**：Golem の fixture（`modules/golem-driver/test/fixtures` のすべての本、二つのマニュアル、`scripts/visual` の PDF）のどれでも、G07107 は出ない。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 孤立した葉の数 | 0、1、2（同じ葉を二つのページに描いたものを含む） |
| 孤立した葉の場所 | 単位の葉、注の葉、傍注の葉、原稿の位置を引けない葉 |
| 宣言 | なし、`pdfa = "2a"`、`pdfua = "1"` |
| プロファイル | dev、prod |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。

- golem-pdf のテスト：`orphanLeaves` が、木にある葉だけを描いた文書で空を、木にない葉を描いた文書でその葉を最初に描いた順に返すこと。二つのページに同じ孤立した葉を描くと、一つだけ返すこと。今の「a leaf drawn but not in the tree becomes a P at the end of the Document」は、`withOrphans` の全域性のテストとして名前を改めて残す。
- golem-typeset のテスト：構造の木から一つの単位を除くテスト用の差し替えで組むと、G07107 が一つ出て PDF を書かず、位置がその単位であること（S2、S3）。注の葉を除いたときは、注の位置であること。dev、prod、宣言の有無で同じであること（S4）。今は G07107 がないので失敗する。
- golem-driver のテスト：fixture のすべての本を PDF に組み、G07107 が出ないこと（S5）。今の実装でも通る見込みで、先に失敗させることはできない。孤立した葉がないことを固定するテストである。
- 今のゴールデンとハッシュは変わらない（S1）。

## トレードオフ

Golem の誤りで、書き手の本が PDF を組めなくなる。
書き手は報告して直るのを待つしかなく、そのあいだその本の PDF を入稿できない。
ただし、そのとき書かれるはずだった PDF は、読む順と構造が誤っているのに、正しいと宣言している。
誤った PDF を黙って書くより、組めないことを知らせるほうが、決定性と厳しさの原則に合う。
fixture のすべてで孤立した葉がないことをテストで固定するので、出荷する Golem で G07107 が出る見込みは小さい。

## メンテナーが決めること

1. **孤立した葉の扱い**：推奨は、新しいエラー G07107 を出し、PDF を書かないことである。孤立した葉は Golem の誤りでしかできず、fallback の `P` は読む順と構造を誤ったまま、正しいと宣言した PDF を作る。
   - 退けた案の一つは、今の fallback のまま、仕様書に書いておくことである。出力を黙って変えることに変わりはない。
   - 二つめは、fallback のまま警告を出すことである。警告を読まない CI では、誤った PDF のまま入稿される。書き手が警告を見ても、直す手段がない。
   - 三つめは、孤立した葉をアーティファクトにすることである。紙面に見える文字を、支援技術から隠すことになる。
   - 四つめは、テストで孤立した葉がないことだけを固定し、組むときには調べないことである。fixture にない入力で起きたとき、誰も気づかない。
2. **重大度を宣言で分けるか**：推奨は、分けず、すべての PDF でエラーとすることである。[ADR 0183](0183-tagged-pdf-and-pdf-a.md) は、宣言によらずすべての PDF にタグを付け、`/MarkInfo` で読む順を宣言する。
   - 退けた案は、`pdfa = "2a"` か `pdfua = "1"` を宣言した本だけをエラーにし、ほかは警告にすることである。宣言のない PDF も構造の木を持ち、支援技術はそれで読む。同じ原因で重大度を変える理由がない。
3. **一つの PDF の報告の数**：推奨は、PDF ごとに一つとし、孤立した葉の数をメッセージに入れることである。原因は Golem の一つの誤りで、葉ごとに出しても書き手にできることは変わらない。
   - 退けた案は、孤立した葉ごとに一つ出すことである。一つの単位の種類の足し忘れで、その単位を使うすべての行が並ぶ。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-08、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [ADR 0183](0183-tagged-pdf-and-pdf-a.md)、[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md)
- [golem-driver ADR 0016](../golem-driver/adr/0016-output-and-layout-diagnostic-codes.md)（G07 の範囲）
- ISO 32000-1:2008, 14.7 Logical Structure、14.8 Tagged PDF
- ISO 14289-1:2014（PDF/UA-1）
