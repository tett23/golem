# ADR 0423: HTML と EPUB は、既定でフォントを同梱せず、総称の書体（明朝、ゴシック）だけを指定する

Status: accepted

## 文脈

HTML と EPUB は、今は `style.toml` の `[fonts]` の役割のフォントのファイルを同梱し、CSS の `@font-face` で指定する。
しかし、電子書籍の多くは、明朝かゴシック程度の指定で足りる。
フォントを同梱すると、EPUB が大きくなり、フォントのライセンスの文書を同梱する問題（ロードマップの「HTML と EPUB へのフォントのライセンスの文書の同梱」）も起きる。

tett23 は 2026-11-23 に、EPUB と HTML でフォントを埋め込まず、総称の書体だけを指定する機能を求め、これを既定にすると決めた。

## 調査した事項

`origin/main`（`89c64c21a`）で確かめた。

- `[fonts.<役割>]` のキーは、`ja`、`latin`、`features`、`punctuation-proportional`、`instance`、`axes` である。
  `ja` と `latin` はどちらも省ける。
- HTML の CSS は、役割ごとに `@font-face` を書き、ファミリー名を `golem-<役割>-<latin|ja>` とする。
- `font-family` の並びは、役割ではなく、スタイルの種類ごとに組む（`modules/golem-html/src/Golem/Html.hs`）。
  - 本文（`body`）は、`body` の役割のファミリー、最後に `serif` である（[1268 行](https://github.com/tett23/golem/blob/89c64c21a09f0f7233ab855a47d051f01e1e7d9b/modules/golem-html/src/Golem/Html.hs#L1268)）。
  - 段落スタイルは、その `font` の役割のファミリー、最後に `serif` である（[`fontStack`](https://github.com/tett23/golem/blob/89c64c21a09f0f7233ab855a47d051f01e1e7d9b/modules/golem-html/src/Golem/Html.hs#L1569-L1573)）。
  - 段落スタイル `code` は、その `font` の役割のファミリー、最後に `monospace` である（[`codeStack`](https://github.com/tett23/golem/blob/89c64c21a09f0f7233ab855a47d051f01e1e7d9b/modules/golem-html/src/Golem/Html.hs#L1352)）。
  - 文字スタイルは、その `font` の役割のファミリーの後に、`code` を継ぐものは `monospace`、ほかは `body` の役割のファミリーと `serif` を置く（[`fallback`](https://github.com/tett23/golem/blob/89c64c21a09f0f7233ab855a47d051f01e1e7d9b/modules/golem-html/src/Golem/Html.hs#L1411)）。
  - ファイルごとの規則などは `inherit` を書く。
- HTML は、見出しの `font` を使わない（ロードマップの v2 以降の「Web 経路のスタイル」）。
- HTML と EPUB は、`[fonts]` のすべての役割のファイルを `fonts/` に写して同梱する。
  EPUB は、それらを `package.opf` の manifest に載せる（[golem-project ADR 0004](../golem-project/adr/0004-font-file-check-per-target.md)）。
- フォントのファイルが欠けると、HTML と EPUB のビルドと `golem check` は G03010 を出し、`dev` では警告、`prod` ではエラーとして出力を書かない。
- [ADR 0421](0421-epub-determinism-per-version-and-fonts-outside-the-project.md) は、`style.toml` のファイルのパスがプロジェクトの外を指すときは、どの出力でもエラー G03279 にすると決めた。
- manifest の `[targets.html]` はキーを受けない空の表であり、`[targets.epub]` は `isbn` と `page-map` だけを受ける。
  manifest の列挙の値の誤り（`pdfa` など）は G03001 に入れている。
- PDF は同じ `[fonts]` の役割を使う。
- CSS Fonts Module Level 4 の総称のファミリーの節は、`serif` の例に明朝（Mincho）、`sans-serif` の例にゴシック（Gothic）を挙げ、総称は内容の言語や利用者の設定で変わってよいとする。
- 読書環境（Apple Books、Kobo など）が、`lang="ja"` の文書の総称を明朝とゴシックに当てるか、縦組みで縦書きの字形が当たるかは、確かめていない（未確認）。

## 実装すること

### 出力ごとの設定

- manifest の `[targets.html]` と `[targets.epub]` に、キー `fonts` を足す。
  値は `"generic"` か `"embed"` で、既定は `"generic"` とする。
  `"embed"` は今の振る舞い（フォントを同梱し、`@font-face` で指定する）である。
  書体を決めたい本は、`fonts = "embed"` を書く。
- `fonts = "generic"` の出力は、次のとおりにする。
  - フォントのファイルを同梱せず、`@font-face` を書かない。
  - EPUB の `package.opf` の manifest にフォントを載せない。
  - `font-family` の宣言は、`inherit` のものを除き、次の節で決まる総称だけを書く。
  - フォントのファイルの有無を調べず、G03010 を出さない。
    `golem check` も同じとする。
  - パスがプロジェクトの外を指すときは、[ADR 0421](0421-epub-determinism-per-version-and-fonts-outside-the-project.md) のとおり G03279 のエラーにする（外を指す設定は、出力によらず誤りである）。
- 設定は出力ごとなので、PDF の振る舞いは変わらない。

### 役割の総称

- `[fonts.<役割>]` に、キー `generic-family` を足す。
  値は `"serif"`（明朝の系統）、`"sans-serif"`（ゴシックの系統）、`"monospace"` のどれかとする。
- `font-family` の並びの最後の総称は、スタイルの種類ごとに次のとおりに決める。
  役割に `generic-family` を書かなければ、今と同じ総称になる。

| 箇所 | 最後の総称 |
| --- | --- |
| 本文（`body`） | `body` の役割の `generic-family`、なければ `serif` |
| 段落スタイル（`code` を除く） | その `font` の役割の `generic-family`、なければ `serif` |
| 段落スタイル `code` | その `font` の役割の `generic-family`、なければ `monospace` |
| `code` を継ぐ文字スタイル | その `font` の役割の `generic-family`、なければ `monospace` |
| ほかの文字スタイル | その `font` の役割の `generic-family`、なければ `body` の役割の `generic-family`、それもなければ `serif` |

- `fonts = "embed"` の出力では、役割のファミリーの並びの後に、上の表の総称を一つだけ置く。
  文字スタイルの並びに `body` の役割のファミリーを挟む今の形は残す。
- `fonts = "generic"` の出力では、上の表の総称だけを書く。
- `generic-family` は PDF では使わない。
  `ja` も `latin` もない役割に `generic-family` だけを書いても、PDF の G08007 と G08002 の規則は変わらない。

### 値の誤り

- manifest の `fonts` の値の誤りと、`generic-family` の値の誤りに、それぞれ新しいコードを振る（原因が違うため）。
  番号は、実装の時点の `docs/diagnostics.md` で次の空いている番号を選ぶ。

### 文書

- 仕様書のフォントの節と HTML と EPUB の節、manifest の `[targets.*]` の表、LSP のスキーマと補完、マニュアルを直す。
- ロードマップの「HTML と EPUB へのフォントのライセンスの文書の同梱」の項目に、`fonts = "generic"` ではこの問題が起きないことを書き足す。
- 採択したら、[golem-project ADR 0004](../golem-project/adr/0004-font-file-check-per-target.md) のステータスの行に、部分「HTML と EPUB のフォントのファイルの同梱と検査」をこの ADR による補足として足す（既定の `generic` では同梱も検査もしない）。

## 実装しないこと

- 総称の `system-ui`、`ui-serif` などは足さない。
  どのフォントにも当たらないことがあるためである。
- 役割ごとに同梱するかを選ぶ設定は設けない（出力ごとに一つ）。
- 見出しの書体を HTML で使うこと（ロードマップの v2 以降）は扱わない。
- 読書環境ごとの書体の割り当てと、縦組みの読書環境での見え方は確かめない。
  `lang` は、今と同じく `[metadata]` の言語から書く。

## 不変条件

- I1：`fonts = "generic"` のどの本の HTML と EPUB も、フォントのファイルを含まず、CSS に `@font-face` を含まない。
- I2：`fonts = "generic"` のどの本の CSS でも、`font-family` のどの宣言の値も、`inherit` か、上の表のその箇所の総称ただ一つである。
- I3：`fonts = "embed"` のどの本の CSS でも、`font-family` のどの宣言の並びの最後は、`inherit` を除き、上の表のその箇所の総称である。
- I4：`fonts = "generic"` のどの本でも、HTML と EPUB のビルドと `golem check` の diagnostic は、プロジェクトの中のフォントのファイルの有無によらない。
- I5：`fonts = "embed"` を書き、`generic-family` を書かない本の出力と diagnostic は、この ADR の前と同じである。
- I8：`fonts` を書かない本の HTML と EPUB は、`fonts = "generic"` を書いた本と同じである。
- I6：どの本でも、`fonts` と `generic-family` の値は PDF の出力と diagnostic を変えない。
- I7：`fonts` か `generic-family` に表にない値を書いた入力は、それぞれの新しいコードのエラーをちょうど一つ含む。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| `fonts = "generic"`、フォントのファイルあり | 同梱しない、`@font-face` なし | I1 |
| 同じ、フォントのファイルなし、`prod` | エラーなしで出力する | I4 |
| 同じ、外を指すフォントのパス | G03279 のエラー | I4 |
| `fonts = "generic"`、段落スタイルの役割に `generic-family = "sans-serif"` | `p.ps-<名前>` の `font-family: sans-serif` | I2 |
| `fonts = "embed"`、同じ役割 | `p.ps-<名前>` の並びの最後が `sans-serif` | I3 |
| `generic-family` を書かない `code` の段落スタイル | 最後が `monospace` | I3, I5 |
| `fonts = "embed"`、`generic-family` なし | 前と同じ | I5 |
| `fonts` を書かない本 | フォントを同梱しない（`generic` と同じ） | I8 |
| `fonts = "generic"` の本の PDF | 前と同じ | I6 |
| `fonts = "serif"` | `fonts` の値の誤りのコード | I7 |
| `generic-family = "mincho"` | `generic-family` の値の誤りのコード | I7 |

## 受けいれ条件

- A1：`fonts = "generic"` で、本文を `serif`、ある段落スタイルを `sans-serif` にした横組みと縦組みの HTML を Chromium で開き、二つが明朝とゴシックの系統で描かれることを、`lang="ja"` の文書で確かめる。
  結果を実装のプルリクエストに書く。

## テスト設計

- 名前は `root ADR 0423 I<番号>: ...` とする。
  テストは、実装の前に失敗することを確かめてから実装する。
- I1 から I4 と I7 は、golem-html、golem-epub、golem-project、golem-driver のテストで、境界の表の行ごとに確かめる。
- I2 と I3 は、生成した CSS の `font-family` の宣言をすべて取り出し、セレクターごとに期待する総称と比べる。
  上の表の五つの箇所と、`generic-family` の三つの値とない場合のすべての組で確かめる。
- I5 は、今の HTML と EPUB のテストに `fonts = "embed"` を足して、出力が変わらないことで確かめる。
  決定性のテスト（[ADR 0421](0421-epub-determinism-per-version-and-fonts-outside-the-project.md) の I1）は、`embed` と `generic` の両方で確かめる。
- I8 は、`fonts` を書かない本と `fonts = "generic"` の本の HTML と EPUB のバイト列が等しいことで確かめる。
- マニュアルと fixture のうち、HTML と EPUB でフォントの同梱を確かめているものは、`fonts = "embed"` を書くか、期待を直す。
- I6 は、`fonts` と `generic-family` を変えた同じ本の PDF のバイト列が等しいことで確かめる。
- 決定性のテストに、`fonts = "generic"` の EPUB を足す。
- A1 はブラウザーで手で確かめる。

## トレードオフ

総称の書体は、読み手の環境で決まる。
同じ本でも、読書環境ごとに書体が違う。
書体を決めたい本は、`fonts = "embed"` を書いて同梱する。

既定を `generic` にするので、今フォントを同梱している本の HTML と EPUB は、設定を足さなければ変わる。
v1.0.0 の前の変更であり、互換性の決まりの上で許される。
リリースノートに、同梱を続けるには `fonts = "embed"` を書くことを載せる。

総称の割り当てが日本語で明朝とゴシックになるかは、読書環境に任せる。
ブラウザーでの確かめ（A1）のほかは、確かめていない。

## 参考文献

- [golem-project ADR 0004](../golem-project/adr/0004-font-file-check-per-target.md)

- [ADR 0361](0361-epub-byte-determinism.md)
- [ADR 0421](0421-epub-determinism-per-version-and-fonts-outside-the-project.md)
- CSS Fonts Module Level 4, Generic font families：<https://www.w3.org/TR/css-fonts-4/#generic-font-families>
