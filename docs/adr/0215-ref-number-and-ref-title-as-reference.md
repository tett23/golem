# ADR 0215: `[ref-number]` と `[ref-title]` をタグ付き PDF の `Reference` にする

ステータス: 採択→手順から外れた点（テストの順と、G06009 の Resolved の規則）は [ADR 0229](0229-record-the-procedures-adr-0215-and-0217-departed-from.md)

## 文脈

[ADR 0183](0183-tagged-pdf-and-pdf-a.md) は、すべての PDF に構造の木を付け、IR の要素と構造の要素の対応を表で決めた。
表の一行は、次のとおりである。

| IR の要素 | 構造の要素 |
| --- | --- |
| 相互参照（`[ref-*]`）、引用の印（`[cite]`） | `Reference` |

`[ref-*]` は、`[ref-number]`、`[ref-title]`、`[ref-page]` の三つである。
ISO 32000-1 の 14.8.4.4 は、`Reference` を、文書の別の場所の内容を指す引用（citation）の要素とする。
「第 2 章「設計」で説明する」の「2」と「設計」は、その用途に当たる。

### 実装は `[ref-page]` だけを `Reference` にした

`[ref-number]` と `[ref-title]` は、文書の組み立て（golem-assemble）で、参照先の番号と題の文字に置き換わる（[`Assemble.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-assemble/src/Golem/Assemble.hs#L606-L622)）。
`Ref` のまま組版に届くのは、ページが決まるまで番号が決まらない `[ref-page]` だけである。
構造の木を作る golem-layout の `inlineStructure` は、届いた `Ref` と `Cite` を `RoleReference` にする（[`Japanese.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/src/Golem/Layout/Japanese.hs#L392-L393)）。
置き換わった後の文字は、ほかの本文の文字と区別がつかないので、親の `P` の中身になる。

sample の fixture の `詳しくは第[ref-number design]章「[ref-title design]」で説明する。`（[`01.gm`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-driver/test/fixtures/sample/chapters/01.gm#L10)）は、構造の木のゴールデンで、`Reference` のない一つの `P` になっている（[`structure-sample.txt`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-driver/test/golden/structure-sample.txt#L35)）。
実装のプルリクエストは、仕様書の対応の表を実装に合わせて「`[ref-number]` と `[ref-title]` は、PDF に届く前に番号と題の文字になるので、親の要素の中身になる」と書き換えた（[`specifications.md`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/docs/specifications.md#L93)）。
ADR の決定と仕様書が食い違っている。

### 何が分かれ目か

同じ相互参照が、構造の要素になるかどうかを、Golem のどの段階で文字が決まるかで分けている。
書き手から見れば、`[ref-page]` と `[ref-number]` はどちらも別の場所を指す参照である。
支援技術は、一方を参照として、もう一方を地の文として読む。

v1.0.0 では、PDF の文書の中のリンクを入れる予定である（[ADR 0183](0183-tagged-pdf-and-pdf-a.md) の「メンテナーが決めること」の 9）。
そのとき `[ref-number]` を参照先に結ぶには、組版に届く IR が、その文字がどのラベルを指すかを持っていなければならない。
今の IR は、組み立てでラベルを捨てている。

## 実装すること

### IR（golem-doc）

組み立てで置き換えた参照を表すインラインの要素 `Resolved` を、golem-doc の IR に加える（「メンテナーが決めること」の 1、2）。

```haskell
  | -- | [ref-number] and [ref-title] after S1: the kind, the label and the
    -- inlines they resolve to (docs/adr/0215)
    Resolved !SrcSpan !RefKind !Text [InlineF r]
```

- `Resolved` を作るのは golem-assemble だけである。`RefKind` は `RefNumber` か `RefTitle` で、`RefPage` の `Resolved` は作らない。
- 中のインラインは、今の組み立てが返す文字と同じ（`relocate` した番号の文字、`[ref-title]` では見出しの題の写し）とする。
- CBOR の符号は、インラインの次のタグ（今の最大は `Lang` の 21）とし、CDDL（`modules/golem-doc/schema/golem-doc.cddl`）に加える。評価（S0）の IR には現れないので、プラグインと `golem inspect` に渡る IR は変わらない。
- `noRuby`、`withoutAnchors` などの IR の関数は、`Link` と同じく中身をたどる。

### 組み立て（golem-assemble）

`Ref sp RefNumber l` と `Ref sp RefTitle l` を、今の文字の代わりに、その文字を包む `Resolved sp k l [...]` に置き換える。
G04003、G04005、G04006 の条件と、そのときに何も残さないことは変えない。

### 出力

- **PDF の構造の木**（golem-layout、golem-typeset）：`inlineStructure` は、`Resolved` を `RoleReference` の要素にし、中のインラインをその子にする。`Reference` の中に `Ruby` などの要素が入ることがある。
- **PDF の紙面**：`Resolved` は、中のインラインを今と同じく組む。行分割、描く字、内容のストリームの字と位置は変えない。
- **HTML、EPUB、プレーンテキスト**：`Resolved` は、中のインラインを今と同じく書く。この ADR では、HTML のリンクにしない。
- 目次、柱、索引、そのほか IR の文字を集める処理は、`Resolved` の中のインラインを今の文字と同じく読む。

### 文書

- docs/specifications.md の「タグ付き PDF」の節の対応の表の、相互参照（`[ref-number]`、`[ref-title]`、`[ref-page]`）と引用の印（`[cite]`）の行の型を、`Reference` だけに戻す。golem-doc の仕様書に `Resolved` を足す。
- [ADR 0183](0183-tagged-pdf-and-pdf-a.md) のステータスの行に、「`[ref-number]` と `[ref-title]` の `Reference` は ADR 0215 で実装」と足す。

## 実装しないこと

- **HTML と EPUB のリンク**：`[ref-number]` と `[ref-title]` を `<a>` にすることは、別の ADR で決める。`Resolved` がラベルを持つので、そのときに IR を変えずに済む。
- **PDF の文書の中のリンク**：`Reference` の中の `Link` は、[ADR 0183](0183-tagged-pdf-and-pdf-a.md) のとおり v1.0.0 で入れる。
- **`[ref-number]` の図番号とリスト番号の書式**：仕様書の「既知の不具合」にある、図番号とリスト番号が `[figures]` と `[code]` の書式に従わない件は、別に扱う。
- **評価の段階の `Ref`**：`[ref-page]` は今のとおり `Ref` のまま組版に届く。

## 不変条件

- **R1**：組み立てを通った IR に、`RefNumber` と `RefTitle` の `Ref` は残らない。ラベルが解決した `[ref-number]` と `[ref-title]` は、それぞれちょうど一つの `Resolved` になる。
- **R2**：`Resolved` の中のインラインは、この ADR の前の組み立てが同じ参照に返した文字とインラインに等しい。
- **R3**：PDF の構造の木で、`[ref-number]`、`[ref-title]`、`[ref-page]`、`[cite]` の一つずつが、ちょうど一つの `Reference` になり、その葉の文字列は紙面に描いたその参照の文字に等しい。
- **R4**：PDF の内容のストリームの描く演算子、HTML、EPUB、プレーンテキストのバイト列は、この ADR の前と同じである。変わるのは、PDF の構造の木と、印付きの内容の区切り（`BDC` と `EMC`、MCID）だけである。
- **R5**：G04003、G04005、G04006 の diagnostics は、この ADR の前と同じである。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 参照の種類 | `[ref-number]`、`[ref-title]`、`[ref-page]`、`[cite]` |
| 参照先 | 見出し、図版、コードブロック、番号付きの項目、存在しないラベル（G04003）、番号のない要素（G04005）、題のない要素（G04006） |
| 題の中身 | 文字だけ、ルビ、圏点、言語の区間（`[lang]`）、注 |
| 置く場所 | 段落、表のセル、注の本文、キャプション |
| 組み方 | 横組み、縦組み（縦組みの漢数字の番号） |
| 行 | 一行に収まる、参照の途中で行が分かれる |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。

- golem-assemble のテスト：境界の入力の参照先ごとに、`[ref-number]` と `[ref-title]` が `Resolved` になり、中身が今の文字と等しいこと（R1、R2）。三つのエラーの場合は今と同じ diagnostics で、何も残さないこと（R5）。
- golem-doc のテスト：`Resolved` が CBOR で往復すること。
- golem-layout の `StructureSpec`：`Resolved` が `RoleReference` の要素になり、ルビを含む題では中に `Ruby` があること（R3）。
- golem-driver の `TaggedPdfSpec`：sample の fixture の構造の木のゴールデン（`structure-sample.txt`）で、「第」「章「」「」で説明する」の間に二つの `Reference` ができること。今は一つの `P` なので失敗する（R3）。
- 見た目の回帰テストの参照の画像、HTML と EPUB とプレーンテキストのゴールデン、`scripts/visual` のハッシュのうち描く内容が変わらないこと（R4）。PDF のバイト列のハッシュは構造の木の分だけ変わるので、変わるハッシュを実装のプルリクエストに挙げる。

## トレードオフ

IR のインラインに要素を一つ足す。
IR のインラインをすべての場合に分けて読む関数（golem-doc、golem-assemble、golem-eval、golem-layout、golem-html、golem-text、golem-plugin、golem-emet）に、一つずつ枝が要る。
そのほとんどは、`Link` と同じく中身をたどるだけである。

代わりに、`[ref-number]` と `[ref-title]` が何を指すかを IR が持ち続ける。
v1.0.0 で PDF の文書の中のリンクを入れるときと、HTML のリンクを決めるときに、IR をもう一度変えずに済む。

## メンテナーが決めること

1. **対応の表のどちらに合わせるか**：推奨は、[ADR 0183](0183-tagged-pdf-and-pdf-a.md) の表のとおり `[ref-number]` と `[ref-title]` を `Reference` にし、仕様書を ADR に戻すことである。`[ref-page]` と同じ相互参照であり、ISO 32000-1 の `Reference` の定義に当たる。構造の要素を、Golem の内部でいつ文字が決まるかで分ける理由はない。
   - 退けた案は、仕様書のとおり親の要素の中身とし、[ADR 0183](0183-tagged-pdf-and-pdf-a.md) の表を改めることである。同じ種類の参照の一方だけを、支援技術が参照として読めなくなる。v1.0.0 のリンクを入れるときに、結局 IR にラベルを残すことになる。
2. **ラベルを組版に届ける方法**：推奨は、組み立てが置き換えた文字を包む `Resolved` を IR に加えることである。番号と題を決める処理は組み立ての一か所に残り、どの出力も同じ文字を書く。
   - 退けた案の一つは、`[ref-number]` と `[ref-title]` を `[ref-page]` と同じく `Ref` のまま組版に届け、出力ごとに文字にすることである。番号と題の文字を作る処理が、PDF、HTML、プレーンテキスト、目次の写しに分かれ、出力ごとに食い違いうる。
   - 二つめは、IR を変えず、`Book` に置き換えた範囲（`SrcSpan`）の表を持たせることである。`[ref-title]` の題の写しのうちルビや圏点の要素は、見出しの原稿の位置を持ったまま写るので、範囲では見出しそのものと区別できない。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-08、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [ADR 0183](0183-tagged-pdf-and-pdf-a.md)、[ADR 0145](0145-title-copies-drop-anchor-inlines.md)、[ADR 0182](0182-external-links.md)
- [golem-doc ADR 0001](../golem-doc/adr/0001-semantic-ir-in-cddl.md)、[golem-doc ADR 0002](../golem-doc/adr/0002-document-assembly.md)
- ISO 32000-1:2008, 14.8.4.4 Inline-Level Structure Elements（`Reference`）
