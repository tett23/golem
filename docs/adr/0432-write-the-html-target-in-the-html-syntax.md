# ADR 0432: HTML のターゲットを HTML の書き方で書き、EPUB は XHTML のまま書く

Status: accepted-pending

## 文脈

HTML のターゲットは、今、XML としても HTML としても読める形（polyglot の XHTML）で書いている（[golem-html ADR 0001](../golem-html/adr/0001-xhtml-serializer.md)）。
EPUB の本文は XHTML でなければならないので、HTML と EPUB が同じ本文を使えるようにするためである。

ところが、HTML の利用者にとって XHTML は扱いづらい。
ファイルの拡張子は `.xhtml` で、XML の宣言、名前空間、`xml:lang`、空要素の `/` が付き、EPUB にしか意味の無い `epub:type` も HTML に残る。
指示者は 2026-10-24 に、HTML の出力を HTML の書き方に変えると決めた。
この ADR は、その書き方と、EPUB との本文の分け方を決める。

## 調査した事項

origin/main（[9efdc4f89](https://github.com/tett23/golem/commit/9efdc4f89b3fec75abcd37c11abb3e1d909c6725)）で、次のことを確かめた。

- HTML と EPUB は一つの書き出し（`Golem.Html` の `renderXhtml :: HtmlConfig -> FileTable -> Book -> XhtmlSite`）を使い、EPUB は改ページの表を渡す `renderXhtmlWithPageBreaks` を使う（[Html.hs#L385-L392](https://github.com/tett23/golem/blob/9efdc4f89b3fec75abcd37c11abb3e1d909c6725/modules/golem-html/src/Golem/Html.hs#L385-L392)）。
  ページは拡張子 `xhtml` で、目次は `index.xhtml` である。
  本文は文字列をつないで作り、要素の木は持たない。
- ページの頭は、`<?xml version="1.0" encoding="UTF-8"?>`、`<!DOCTYPE html>`、`xmlns` と `xmlns:epub` と `lang` と `xml:lang` を持つ `<html>`、`<meta charset="UTF-8"/>` である（[Html.hs#L443-L450](https://github.com/tett23/golem/blob/9efdc4f89b3fec75abcd37c11abb3e1d909c6725/modules/golem-html/src/Golem/Html.hs#L443-L450)）。
- HTML のターゲットにも、EPUB の語彙の `epub:type`（注の参照の `noteref`、脚注の `footnote`、後注の `endnote`、目次の `toc`）を書いている。
  改ページの `span`（`epub:type="pagebreak"` と `role="doc-pagebreak"`）は、EPUB にだけ書く（[Driver.hs#L1297](https://github.com/tett23/golem/blob/9efdc4f89b3fec75abcd37c11abb3e1d909c6725/modules/golem-driver/src/Golem/Driver.hs#L1297)、[Driver.hs#L1529](https://github.com/tett23/golem/blob/9efdc4f89b3fec75abcd37c11abb3e1d909c6725/modules/golem-driver/src/Golem/Driver.hs#L1529)）。
  本文の `role` は、この改ページのものだけである。
- 言語の区間とブロックにも、`lang` と `xml:lang` の両方を書く（[Html.hs#L468](https://github.com/tett23/golem/blob/9efdc4f89b3fec75abcd37c11abb3e1d909c6725/modules/golem-html/src/Golem/Html.hs#L468)）。
  [root ADR 0187](0187-inline-language-switch.md) の「HTML と EPUB」の節は、HTML の出力が XHTML なので両方を書くと決めている。
  インラインの SVG は `xmlns` を持ち、SVG の中の空要素も `/>` で閉じる。
- HTML の空要素は `<br/>`、`<col/>`、`<meta/>`、`<link/>`、`<img/>` と書く。
- 文字のエスケープは `&amp; &lt; &gt; &quot;` で、ほかに、アキの前後に語の結合子を数値の参照 `&#x2060;` で書く（[Html.hs#L1018](https://github.com/tett23/golem/blob/9efdc4f89b3fec75abcd37c11abb3e1d909c6725/modules/golem-html/src/Golem/Html.hs#L1018)）。
  CDATA と `<style>` と `<script>` は書かない。
- EPUB は、同じ `XhtmlSite` を `writeEpub` に渡し、`nav.xhtml` を自分で作る（[golem-epub ADR 0001](../golem-epub/adr/0001-epub-packaging.md)）。
- 出力を固定しているもの: golem-html の `XhtmlSpec.hs`、golem-driver の golden（`html-01.xhtml` など）、`scripts/determinism/hashes.txt` の `build/html/*.xhtml` と EPUB のハッシュ、`browser.yml` のブラウザの検査（`.xhtml` を `application/xhtml+xml` で配り、XML の読み取りで開く）、CI の epubcheck 5.4.0。
- [golem-html ADR 0001](../golem-html/adr/0001-xhtml-serializer.md) の「テスト設計」は、すべての golden のテストで出力が整形式の XML かを確かめると書いているが、その検査は見つからなかった。
- 仕様書は、golem-html を「XHTML と CSS」と図に書き（468 行）、共通の書き出しの上に EPUB を載せると書き（872 行）、HTML の目次のページを `index.xhtml` と書く（1771 行）。
- HTML の書き方では、HTML の空要素は `/` を付けなくてよく、SVG のような外来の要素は `/>` で閉じてよい（WHATWG HTML の「The HTML syntax」）。
- v0.1.0-rc2 から rc4 のタグが出ており、rc の出力は `.xhtml` である。

指示者は 2026-11-23 に、この ADR を書くよう求めた。

## 実装すること

### 一つの本文から二つの書き方で書き出す

HTML と EPUB は、今までどおり一つの本文（同じ要素、同じ属性、同じ並び）を作る。
本文は、文字列ではなく、小さな要素の木（要素、属性、文字、生の SVG のための外部の内容）として作る。
その木を、HTML の書き方と XHTML の書き方の二つで書き出す。

`renderXhtml` は、型と出力を変えず、EPUB のための XHTML を作る。
HTML のターゲットのために、同じ木から HTML の書き方で書き出す `renderHtml` を足す。
二つの書き方は、次の点だけが違う。

| 点 | HTML のターゲット | EPUB（XHTML） |
| --- | --- | --- |
| ファイルの拡張子と目次 | `.html`、`index.html` | `.xhtml`、今と同じ |
| XML の宣言 | 書かない | 書く |
| `<html>` の名前空間 | 書かない | `xmlns`、`xmlns:epub` |
| 言語（根、区間、ブロック） | `lang` だけ | `lang` と `xml:lang` |
| HTML の空要素（`br`、`col`、`meta`、`link`、`img` など） | `<br>` のように `/` を付けない | `<br/>` |
| 注の参照、脚注、後注、目次の意味の印 | `role="doc-noteref"`、`role="doc-footnote"`、`role="doc-endnote"`、`role="doc-toc"` | 今と同じ `epub:type` |
| 改ページの `span` | 書かない（今と同じ） | 今と同じ |
| インラインの SVG の `xmlns` | 書かない | 書く |
| インラインの SVG の中の空要素 | `/>` で閉じる | `/>` で閉じる |
| 文字の参照 | `&amp; &lt; &gt; &quot;` と `&#x2060;` | 同じ |
| 本の中のリンクの先の拡張子 | `.html` | `.xhtml` |

HTML のターゲットの `epub:type` は、同じ意味の DPUB-ARIA の `role` に置き換える。
`epub:type` を外すだけにすると、HTML の注と目次が意味の印を失うためである。
EPUB の出力は変えないので、EPUB には `role` を足さない。

`/` を外すのは HTML の空要素だけで、インラインの SVG の要素は、HTML の書き方でも `/>` で閉じる。
HTML の読み取りでは、外来の要素の `/>` が空要素を表すからである。

### 検査

HTML のターゲットの出力が HTML として正しく読めることを、ブラウザの検査で確かめる。
`browser.yml` は、`.html` を `text/html` で配り、HTML の読み取りで開く。
EPUB の本文が整形式の XML であることは、golem-html のテストで XML として読んで確かめ、CI の epubcheck でも確かめる。
golem-html のテストには、二つの書き出しが同じ木から出ることを確かめるテスト（I3）を足す。
I3 は、HTML と XML の構文解析器を使わず、書き出した文字列の上で確かめる。
XHTML の文字列に、表の違いを順に当てる変換（XML の宣言と名前空間と `xml:lang` を消す、HTML の空要素の `/` を消す、`epub:type` を `role` に置き換える、リンクの先の `.xhtml` を `.html` にする）をかけ、HTML の文字列と比べる。
書き出しは Golem が持つので、この変換は文字列の上で一つに決まる。

### 移行

HTML のターゲットの golden、決定性の検査のハッシュ、ブラウザの検査の拡張子と MIME の型を、新しい出力に合わせて作り直す。
EPUB のハッシュは変えない（A2）。
仕様書、マニュアル、開発者向けのマニュアル、README の、HTML のターゲットの出力として `index.xhtml`、`.xhtml`、`epub:type`、`xml:lang` を書く記述を、すべて直す。
仕様書では、少なくとも 468 行、872 行、1771 行、6832 行（言語の属性）、7814 行と 7914 行（注の `epub:type`）、8159 行（`.xhtml` へのリンクの例）が当たる。
ロードマップの「HTML の出力の HTML の書き方への変更」の項目を消す。
rc の利用者に向けて、HTML の出力の拡張子が変わることを、次のリリースノートに書く。

### ステータスの行

採択したら、[golem-html ADR 0001](../golem-html/adr/0001-xhtml-serializer.md) のステータスの配列に、次の二つを足す。

- 「入力と出力」の部分（polyglot の書き方と、HTML と EPUB が同じ `XhtmlSite` を使うこと）を、この ADR が置き換えた。
- 「テスト設計」の、すべての golden で整形式の XML かを確かめる項目を、この ADR が置き換えた。

また、[root ADR 0187](0187-inline-language-switch.md) のステータスの配列に、「HTML と EPUB」の節の、HTML の出力に `xml:lang` を書くことを、この ADR が置き換えたと足す。

```text
superseded [{"by":["docs/golem-driver/adr/0026-chapter-end-notes.md"],"part":"注の本文をまとめる場所と一覧の見出し"},{"part":"入力と出力","by":["docs/adr/0432-write-the-html-target-in-the-html-syntax.md"],"kind":"replace"},{"part":"テスト設計の、すべての golden で整形式の XML かを確かめる項目","by":["docs/adr/0432-write-the-html-target-in-the-html-syntax.md"],"kind":"replace"}]
```

EPUB の出力は変えないので、[golem-epub ADR 0001](../golem-epub/adr/0001-epub-packaging.md) のステータスは変えない。

## 実装しないこと

EPUB の本文の書き方（XHTML）と、EPUB の出力のバイト列は変えない。
HTML と EPUB で、本文の要素や並びを変えない。
CSS（`style.css`）は変えない。
`<script>` や `<style>` を本文に書かない。
`.xhtml` の古い名前から `.html` への転送は作らない。

## 不変条件

- I1: HTML のターゲットの各ページは `<!DOCTYPE html>` で始まり、根にも区間にもブロックにも、XML の宣言、`xmlns`、`xml:lang`、`epub:type` を含まず、HTML の空要素に `/` を付けない。
- I2: EPUB の本文は、XHTML の書き出しだけで決まり、HTML の書き出しを変えても変わらない。
- I3: 同じ本文の木から書き出した XHTML の文字列に、表の違いを当てる変換をかけたものは、HTML の文字列と等しい。
- I4: HTML のターゲットの本の中のリンクは `.html` のファイルを指し、EPUB の中のリンクは `.xhtml` のファイルを指す。
- I5: 同じ入力からの HTML のターゲットの出力は、バイト列まで等しい。
- I6: HTML のターゲットのインラインの SVG の中の空要素は `/>` で閉じる。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| 空の本 | `index.html` だけがあり、`<!DOCTYPE html>` で始まる | I1 |
| 改行（`<br>`）、表の列（`<col>`）、画像（`<img>`）を持つ章 | HTML では `/` 無し、EPUB では `/` 付き | I1, I2, I3 |
| 注と後注と目次を持つ本 | HTML に `epub:type` が無く `doc-*` の `role` があり、EPUB は今と同じ `epub:type` | I1, I3 |
| 改ページを持つ章 | HTML に改ページの `span` が無く、EPUB にある | I1, I2 |
| 言語の区間を持つ段落 | HTML の `span` に `lang` だけがあり、EPUB に両方がある | I1, I3 |
| インラインの SVG を持つ図版 | HTML の SVG に `xmlns` が無く、中の `<path .../>` は `/>` のまま | I1, I6 |
| `&` と `<` を含む文字 | 両方で `&amp;` と `&lt;` | I3 |
| アキを含む行 | 両方で `&#x2060;` | I3 |
| 章をまたぐ参照 | HTML は `.html` を、EPUB は `.xhtml` を指す | I3, I4 |
| HTML の書き出しだけを変えた後の EPUB | バイト列が変わらない | I2 |
| 同じ入力で二回組む | 同じバイト列 | I5 |

## 受けいれ条件

A1: マニュアルを HTML のターゲットで組み、Chromium と Safari で、各ページが HTML として開き、リンクと注と図版が働くことを確かめる（`browser.yml` が確かめる）。

A2: 実装のプルリクエストで、決定性の検査の EPUB のハッシュが、この ADR の前と変わらないことを確かめる。

## テスト設計

root ADR 0432 I1 から I6 を名前の先頭に置いたテストを、golem-html と golem-driver に足す。
I1 と I6 は、境界の表の原稿を組み、出力の文字列を調べる。
I2 は、HTML の書き出しの関数を差し替えても EPUB の書き出しの結果が変わらないことを、golem-html のテストで確かめる。
I3 は、hedgehog で作った本文の木と、境界の表の原稿で、変換をかけた XHTML の文字列と HTML の文字列を比べる。
I4 は、章をまたぐ参照の `href` を調べる。
I5 は、決定性の検査のハッシュで確かめる。
I1、I4、I6 は、実装の前に落ちることを確かめる。
root ADR 0432 A1 は、`browser.yml` の検査で確かめる。
root ADR 0432 A2 は、実装のプルリクエストの CI の決定性の検査で確かめる。

## トレードオフ

本文を要素の木で作り直すので、書き出しのコードの多くを書き換える。
その代わりに、二つの書き方の違いが書き出しの一か所に集まり、HTML と EPUB の本文が食い違わない。

HTML の出力のファイルの名前が変わるので、rc の出力を参照している利用者のリンクとスクリプトは切れる。
転送のページは作らず、リリースノートで知らせる。
v1.0.0 の前に変えれば、v1.0.0 の後の利用者には影響しない。

## 参考文献

- [golem-html ADR 0001](../golem-html/adr/0001-xhtml-serializer.md)
- [golem-epub ADR 0001](../golem-epub/adr/0001-epub-packaging.md)
- W3C, EPUB 3.3, XHTML content documents
- WHATWG, HTML Living Standard, The HTML syntax
