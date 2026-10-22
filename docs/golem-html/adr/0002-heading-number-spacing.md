# ADR 0002: 番号と題のあいだの区切り

ステータス: 採択→（区切りを置く箇所にコードブロックのキャプションを加えること）は [golem-driver ADR 0042](../../golem-driver/adr/0042-listing-caption-number-separator.md)

## 文脈

Golem の利用者のマニュアルを HTML に組むと、三章の見出しは「第3章原稿の記法」と表示される。
番号と題がくっついている。
同じ見出しは、PDF では「第3章　原稿の記法」と組まれる。

golem-html の `Golem.Html` の `block` は、見出しを次の形で書く。

```xml
<h1 id="..."><span class="number">第3章</span>原稿の記法</h1>
```

番号の `span` と題のあいだには何もなく、生成する CSS（`Golem.Html` の `css`）も `.number` に余白を付けない。
図版のキャプションも同じ形（`<figcaption><span class="number">図1-1</span>キャプション</figcaption>`）で、番号と本文がくっつく。

ほかの出力を調べると、番号と題のあいだの扱いは出力ごとにばらばらである。

| 出力 | 箇所 | 番号と題のあいだ |
| --- | --- | --- |
| PDF | 見出し（`Golem.Driver.Pdf` の `blocks` の `Heading`） | 全角の空白（U+3000） |
| PDF | 目次の項目（`TocOutput`） | 全角の空白 |
| PDF | キャプション（`captionInlines` の束縛） | 全角の空白 |
| PDF | 柱の `heading.<l>.numbered`（`runningHeadText`） | 全角の空白 |
| プレーンテキスト | 見出し、目次、キャプション（`Golem.Text`） | 全角の空白 |
| HTML | 見出し、キャプション | なし |
| HTML | 本文の `@toc`（`Golem.Html.toc`） | 半角の空白（U+0020） |
| HTML | 目次のページ（`Golem.Driver.indexPage`） | 半角の空白 |
| EPUB | ナビゲーション文書（`Golem.Epub` の `entry`） | 半角の空白 |

PDF とプレーンテキストは、本の言語によらず全角の空白を入れる。
英語の本（`golem new --language en` の雛形）でも「1　Introduction」と組まれる。
欧文の組版では、番号と題のあいだは語間の空白か、番号の後の句読点と空白で区切るのが普通であり、全角の空白は和文の慣習である。
欧文の書体の多くは U+3000 の字形を持たないので、PDF では和文の書体に切り替えて一字分の空きを置くことになる。

docs/specifications.md の柱の表は、`heading.<l>.numbered` を「番号の表記、全角の空白、短い題」と定め、PDF の目次の節も「番号、全角の空白、短い題」と書いている。
これらは日本語の本を前提にした記述である。

## 実装すること

### 区切りの規則

番号と題のあいだの区切りを、本の言語で一つに決める。

- `manifest.toml` の `[metadata] language` の主の副タグ（最初の `-` の前を英小文字にしたもの）が `ja` なら、全角の空白（U+3000）とする。
- それ以外の言語では、半角の空白（U+0020）とする。

番号の書式（`style.toml` の `[headings.<l>] number` と `[figures] number`）は区切りを変えない。
「第{n:kanji}章」と「{1}.{n}」のように書式が違っても、同じ本の中では同じ区切りを使う。
書式ごとに区切りを変えると、同じ本の章と節で見出しの頭の揃いが変わり、目次で番号の後の位置が揃わなくなるためである。

ただし、番号の文字列が空白（U+0020、U+3000、タブ）で終わるときは、区切りを足さない。
書式に区切りを書いた本（`number = "Chapter {n}: "` のような書式）で、空白が二重にならないためである。
`style.toml` の書式の検査（G0306 の「番号の書式が不正です」）は、末尾の空白を今も許している。

この規則を golem-doc の `Golem.Doc.Numbering` に置く。

```haskell
-- 本の言語（BCP 47 の言語タグ）と番号の文字列から、番号と題のあいだに置く文字列
numberSeparator :: Text -> Text -> Text
```

### 適用する箇所

上の表のすべての箇所で、番号と題のあいだに `numberSeparator` の文字列を置く。

- **HTML の見出しとキャプション**：区切りは `span` の外に、題の前のテキストとして書く。
  `<h1 id="..."><span class="number">第3章</span>　原稿の記法</h1>` の形である。
  CSS の余白ではなくテキストにするのは、コピーした文字列、スクリーンリーダー、検索エンジン、CSS を読まない閲覧環境でも区切りが残るためである。
- **HTML の `@toc`、目次のページ、EPUB のナビゲーション文書**：今の半角の空白を `numberSeparator` に替える。日本語の本では全角の空白になる。
- **PDF**：見出し、目次の項目、キャプション、柱の四箇所の `"\x3000"` と `"　"` を `numberSeparator` に替える。日本語の本の PDF は変わらない。英語の本の PDF は、全角の空白が半角の空白になる。
- **プレーンテキスト**：見出し、目次、キャプションを同じく替える。日本語の本の出力は変わらない。キャプションの `［図1-1　キャプション］` の括弧と `T.strip` は今のままとする。

番号を持たない見出し（`@nonumber`）と、番号のないキャプションには区切りを置かない。
今の振る舞いと同じである。

傍注の番号とリストの印は、この ADR の範囲に入れない。
傍注の番号は本文と分けて組む要素であり、リストの印の後の空きは [golem-driver ADR 0013](../../golem-driver/adr/0013-list-indents.md) が決めている。

### データ構造の変更

- golem-doc に `Golem.Doc.Numbering.numberSeparator` を加える。
- 本の言語は、HTML は `HtmlConfig` の `hcLanguage` を、EPUB はパッケージの設定の言語を、PDF とプレーンテキストは golem-driver が渡す `[metadata] language` を使う。PDF の `PdfInput` とプレーンテキストの設定に言語の欄がなければ加える。

### ドキュメント

- docs/specifications.md の「見出し」の節に、番号と題のあいだの区切りの規則（日本語の本は全角の空白、ほかは半角の空白、番号が空白で終われば足さない）を書き、この ADR へリンクする。
- 同じく PDF の目次の節の「番号、全角の空白、短い題」と、柱の表の `heading.<l>.numbered` の「番号の表記、全角の空白、短い題」を、「番号、区切り、短い題」に改め、区切りの規則へ参照を付ける。
- 同じく「今後の実装項目」の「記法と設定」から「HTML の見出しの番号」の項を除く。
- 利用者のマニュアル（`manual/`）の見出しの番号を説明する箇所（`manual/chapters/05-style.gm` の「見出しの体裁」の節の `number` の項と、`manual/appendices/c-style.gm` の「`[headings.階層]`」の節）に、番号と題のあいだに日本語の本では全角の空白、英語の本では半角の空白が入ること、区切りを書式に書けば足さないことを書く（[docs/adr/0024](../../adr/0024-manual-audiences-and-policy.md)）。

## 実装しないこと

- 区切りを `style.toml` で選ぶキー（`number-separator` のような欄）。書式の末尾に空白を書く方法で足りる。全角の空白と半角の空白のほかの区切り（二分の空き、タブ）が要るようになったら、別の ADR で扱う。
- `.number` の CSS の余白で区切ること。
- 日本語と英語のほかの言語（中国語、韓国語など）の慣習に合わせること。ほかの言語はすべて半角の空白とする。
- 傍注の番号とリストの印の後の空き。

## テスト設計

### 先に書いて失敗させるテスト

`modules/golem-doc/test`：

- `numberSeparator "ja" "第3章"` が U+3000、`numberSeparator "ja-JP" "1.2"` が U+3000、`numberSeparator "en" "1"` が U+0020、`numberSeparator "EN-us" "1"` が U+0020 であること。
- `numberSeparator "en" "Chapter 1: "` と `numberSeparator "ja" "第1章　"` が空の文字列であること。

`modules/golem-driver/test/Main.hs`：

- `language = "ja"`、`[headings.1] number = "第{n:kanji}章"` の本の HTML に、`<span class="number">第一章</span>　` に題が続く見出しがあること。
- 同じ本の図版のキャプションが `<span class="number">図1-1</span>　` に本文が続くこと。
- `language = "en"`、`[headings.1] number = "{n}"` の本の HTML の見出しが `<span class="number">1</span> Introduction` の形であること。
- 日本語の本の本文の `@toc` と目次のページの項目で、番号の後が全角の空白であること。英語の本では半角の空白であること。
- 日本語の本の EPUB のナビゲーション文書の項目で、番号の後が全角の空白であること。
- `@nonumber` の見出しに区切りが付かないこと。
- `number = "Chapter {n}: "` の英語の本で、HTML と PDF の見出しの文字列に空白が二つ続かないこと。
- 英語の本の PDF の見出しの組む前の文字列（`Heading` の単位の `title`）が `1 Introduction` であり、U+3000 を含まないこと。日本語の本では今と同じく U+3000 であること。
- 英語の本の柱の `heading.1.numbered` の文字列が `1 Introduction` であること。

`modules/golem-text/test`：

- 英語の本の見出しが `1 Introduction`、日本語の本の見出しが `第一章　…` であること。

HTML の golden ファイル（`modules/golem-driver/test/golden/` の該当するもの）を更新する。

### 自動テストにしない確かめ方

マニュアルを HTML に組み、ブラウザで三章の見出しと目次を開いて、番号と題のあいだに一字分の空きがあることを目で確かめる。
`golem new --language en` の雛形の見出しに番号の書式を足して PDF と HTML に組み、番号と題のあいだが語間と同じ幅であることを確かめる。

## トレードオフ

英語の本の PDF とプレーンテキストの出力が変わる。
全角の空白は欧文の組版の慣習に合わないので、v1 のリリースの前に直しておくほうがよいと判断した。

区切りを言語だけで決めるので、日本語の本で欧文の流儀（「1.2 見出し」）にしたい人は、書式の末尾に半角の空白を書くことになる。
書式に書く方法は、出力のすべてで同じように効くので、キーを増やすより単純である。

HTML の区切りをテキストにすると、見た目の空きを CSS だけで変えることはできなくなる。
区切りの文字を変えたい人は書式で変えられるので、CSS で変える手段は設けない。

## 参考文献

- W3C, Requirements for Japanese Text Layout（JLReq）, https://www.w3.org/TR/jlreq/
- IETF BCP 47, Tags for Identifying Languages, https://www.rfc-editor.org/info/bcp47
