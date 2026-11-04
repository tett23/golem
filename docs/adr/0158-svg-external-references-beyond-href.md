# ADR 0158: G08014 の検査を、属性の値の CSS、処理命令、XHTML の要素、接頭辞つきの `attributeName` に広げる

ステータス: 採択

## 文脈

[ADR 0039](0039-svg-active-content-in-html-and-epub.md) は、HTML と EPUB に写す SVG の図版から、ブラウザーが SVG を文書として開いたときに動かすか読むもの（動的なコンテンツ）を G08014 で拒むと決めた。
拒むものは、[ADR 0039](0039-svg-active-content-in-html-and-epub.md) の表（仕様書の「図版」の節の表と同じ）に列挙した。

[2026-10-24 の監査](../audits/2026-10-24-security-audit.md) の C9 は、この表にない書き方の外部の参照が G08014 の検査を通ることを示し、roadmap の「セキュリティ監査の残り」に「G08014 の表にない外部の参照」として残した。
roadmap は、表を広げるか、広げるならどの形を足すか、ブラウザーが読むかを確かめる手順を ADR で決めるとしている。
[2026-11-05 のセキュリティ監査](../audits/2026-11-05-security-audit.md) の V-02 は、今のソースで同じ不足を再び確かめた。

### 検査を通る形

二つの監査が、検査の関数か CLI で通ることを確かめた形は次のとおりである。

| 形 | 例 | 確かめた監査 |
| --- | --- | --- |
| 表現の属性の `url()` | `<rect fill="url(https://example.invalid/a#g)"/>`。`filter`、`clip-path`、`mask`、`marker-*`、`cursor` も同じ | 2026-10-24、2026-11-05（関数と CLI） |
| `url(` を使わない CSS の関数 | `style="background: image-set('https://…' 1x)"` | 2026-10-24 |
| 処理命令 | `<?xml-stylesheet type="text/css" href="https://…"?>` | 2026-10-24、2026-11-05（関数と CLI） |
| XHTML の名前空間の要素 | `<h:img xmlns:h="http://www.w3.org/1999/xhtml" src="https://…"/>` | 2026-10-24 |
| アニメーションで `style` や表現の属性を書き換えるもの | `<set attributeName="style" to="fill:url(https://…)"/>` | 2026-10-24、2026-11-05（関数） |
| XLink の名前空間を `xlink` 以外の接頭辞で書いた `attributeName` | `<set attributeName="q:href" to="javascript:…"/>`（`q` は XLink の名前空間） | 2026-10-24 |

原因は三つある。

- `Golem.Svg.Active.attribute` は、CSS の参照（`@import` と `url(`）を `style` の属性の値でしか探さない（[Active.hs#L61-L68](https://github.com/tett23/golem/blob/709b499ae29a0eb78515d67320f0924f996e4071/modules/golem-svg/src/Golem/Svg/Active.hs#L61-L68)）。`image-set(` は、どこでも探さない。
- `Golem.Svg.Xml` は、処理命令を読んで捨てる（[Xml.hs#L133-L141](https://github.com/tett23/golem/blob/709b499ae29a0eb78515d67320f0924f996e4071/modules/golem-svg/src/Golem/Svg/Xml.hs#L133-L141) と、要素の中身の読み手）。検査の関数は処理命令を見られない。
- `set` と `animate` の `attributeName` は、値の文字列を `href`、`xlink:href`、`on` で始まる名前と比べる（[Active.hs#L39-L59](https://github.com/tett23/golem/blob/709b499ae29a0eb78515d67320f0924f996e4071/modules/golem-svg/src/Golem/Svg/Active.hs#L39-L59)）。接頭辞の名前空間を解決しない。XHTML の名前空間の要素は、表のどの行にも当たらない。

### ブラウザーが読むか

どちらの監査も、ブラウザーと EPUB の読書環境がこれらの形を実際に読むかは確かめていない。
この ADR は、確かめた結果に拒むかどうかを依存させない。
検査の目的は、写した SVG が文書の外を読まないことを Golem が保証することにある。
読まないことを確かめていない形は、読むものとして扱う。
読むかを確かめる手順は決めない（「実装しないこと」）。

### コードの選び方

新しく拒む形は、どれも [ADR 0039](0039-svg-active-content-in-html-and-epub.md) の表の「CSS の外部の参照」と「参照の属性」と同じ原因（写した SVG が、文書を開いたときに外部を読むか、スクリプトを動かしうる書き方を持つ）である。
直し方も同じく、メッセージに名前のあるものを SVG から除くことである。
新しいコードを作らず、G08014 の表に行を足す。
G08014 は、読めない SVG（G08010 と同じ理由）も同じコードで拒んでいる。
この束ねは、v1.0.0 の roadmap の、原因を束ねたコードの見直しで扱い、この ADR では変えない。

## 実装すること

### 拒むものの表

G08014 の表を次のようにする。
太字の行が、この ADR で足すか変える行である。

| 種類 | 拒むもの | `<名前>` |
| --- | --- | --- |
| スクリプトの要素 | `script`（名前空間を問わない） | 要素の名前 |
| 別の文書を埋め込む要素 | `foreignObject`、`iframe`、`embed`、`object`、`handler`、`listener` | 要素の名前 |
| **XHTML の要素** | 名前空間が `http://www.w3.org/1999/xhtml` の要素（`foreignObject` の外でも） | 要素の名前 |
| イベントの属性 | 名前が `on` で始まる属性（大文字と小文字を区別しない） | 属性の名前 |
| 参照の属性 | `href` と `xlink:href` のうち、値が `#` で始まらないもの | 属性の名前 |
| **アニメーションによる書き換え** | `set`、`animate` の要素で、`attributeName` の局所名（`:` の後。`:` がなければ全体）が `href` か、`on` で始まる名前のもの。大文字と小文字を区別しない | 要素の名前 |
| **CSS の外部の参照** | `style` の要素の中身と、**すべての属性の値**の中の `@import`、`url(` の後が `#` で始まらないもの、**`image-set(`** | `@import`、`url()`、`image-set()` |
| **処理命令** | 対象が `xml-stylesheet` の処理命令（文書のどこにあっても。対象の名前は大文字と小文字を区別しない） | `xml-stylesheet` |

- 「すべての属性の値」は、名前空間を問わない。`fill`、`filter`、`clip-path`、`mask`、`marker-start`、`cursor` などの表現の属性、`set` と `animate` の `to`、`from`、`by`、`values` を含む。値は、今の `style` の属性と同じく CSS の字句として読む（コメントを捨て、エスケープを解く）。`-webkit-image-set(` も `image-set(` を含むので当たる。
- アニメーションで `style` や `fill` を書き換えるもの（`<set attributeName="style" to="fill:url(…)"/>`）は、`to` の値の `url(` で当たる。`attributeName` が `style` であることだけでは拒まない。
- `attributeName` の接頭辞は解決しない。局所名が `href` なら、接頭辞がどの名前空間を指していても拒む。
- XML の宣言（`<?xml version="1.0"?>`）は処理命令ではないので、今と同じく読む。
- 内部の参照 `url(#id)` と `href="#id"` は、今と同じく通す。

### XML の読み手（データ構造）

`Golem.Svg.Xml` が処理命令を残すようにする。

- `Node` に構成子 `NInstruction !Text !Pos` を足す。`Text` は処理命令の対象の名前、`Pos` は `<?` の位置である。要素の中身の処理命令は、この構成子で子として残す。
- ルートの要素の前と後の処理命令は、`parseXmlDocument :: ByteString -> Either Text Document` が返す `Document` の `docInstructions :: [(Text, Pos)]` に、文書の順で残す。`Document` はほかに `docRoot :: Element` を持つ。
- `parseXml` は `docRoot <$> parseXmlDocument` とし、型を変えない。
- PDF の側（SVG の図版を描く golem-svg の利用者）は `NInstruction` を読み飛ばす。今は処理命令を捨てているので、PDF の出力は変わらない。
- `activeContent` は `parseXmlDocument` で読み、`docInstructions` と要素の中の `NInstruction` を、ほかのものと合わせて文書の順に並べる。

### ドキュメント

- 仕様書の「図版」の節の G08014 の表を、上の表にする。
- `docs/diagnostics.md` の G08014 の節に、拒む形を足す。
- 利用者向けマニュアルの図版の章と diagnostic の付録、開発者向けマニュアルの SVG の検査の表を同じく直す。
- `docs/roadmap.md` の「G08014 の表にない外部の参照」の項目を消す。
- golem-svg の仕様書に、`NInstruction` と `parseXmlDocument` を書く。

## 実装しないこと

- ブラウザーと EPUB の読書環境で、各形が実際に読まれるかを確かめる手順と試験。拒むかどうかは、その結果によらない。
- 対象が `xml-stylesheet` でない処理命令の拒否。ブラウザーが働きを定めている処理命令は `xml-stylesheet` だけである。メタデータを処理命令で書く書き出し（XMP の `<?xpacket?>` など）を拒まないためでもある。ただし、どの描画ソフトがそうした処理命令を書くかは確かめていない。
- `foreignObject` の外の、XHTML 以外の名前空間の要素の拒否。Inkscape の `sodipodi:namedview` や RDF のメタデータのように、描画ソフトがよく書く。
- SVG を許可リストで書き直して写すこと（監査が案として挙げた方式）。[ADR 0039](0039-svg-active-content-in-html-and-epub.md) が、検査を通った SVG をバイト列のまま写すと決めており、書き直すと Golem が出力を黙って変える。
- G08014 を原因ごとに分けること。理由は「コードの選び方」の節にある。
- PNG と JPEG の検査、PDF の側の G08010 と G08011 の変更。

## テスト設計

どれも、変更の前に失敗することを確かめてから実装する。
SVG はテストの中に短い文字列で書き、外部の URL には `.invalid` の名前を使う。

- golem-svg（`activeContent` の単体テスト）
  - `<rect fill="url(https://example.invalid/a#g)"/>` が `url()` を返す。`filter`、`clip-path`、`mask`、`marker-start`、`cursor` の属性でも同じ。
  - `<rect fill="url(#g)"/>` と `<rect fill="URL( '#g' )"/>` は通る。
  - `fill="u\72l(https://example.invalid/a)"`（エスケープ）が `url()` を返す。
  - `style="background: image-set('https://example.invalid/a.png' 1x)"` と `-webkit-image-set(` が `image-set()` を返す。
  - 先頭の `<?xml-stylesheet type="text/css" href="https://example.invalid/a.css"?>` が `xml-stylesheet` を、その処理命令の位置で返す。要素の中にあっても同じ。`<?XML-STYLESHEET …?>` も同じ。
  - `<?xpacket begin=""?>` と XML の宣言は通る。
  - `<set attributeName="style" to="fill:url(https://example.invalid/a#g)"/>` が `url()` を返す。
  - `<set xmlns:q="http://www.w3.org/1999/xlink" attributeName="q:href" to="javascript:void(0)"/>` が `set` を返す。`attributeName="Q:HREF"` も同じ。
  - `<h:img xmlns:h="http://www.w3.org/1999/xhtml" src="https://example.invalid/a.png"/>` が `img` を返す。
  - Inkscape の `sodipodi:namedview` と `metadata` の中の `rdf:RDF` を持つ SVG は通る。
  - 見つかったものは、処理命令を含めて文書の順に並ぶ。
- golem-svg（XML の読み手）
  - `parseXml` の結果が、処理命令を含む SVG と、それを除いた SVG とで、`NInstruction` の子を除いて同じである。
  - golem-pdf の SVG の図版のテストが、処理命令を含む SVG で今と同じ PDF を書く。
- golem-driver
  - `fill` の外部の参照と `xml-stylesheet` を持つ SVG の図版で、`golem build --target html` と `--target epub` が G08014 を出し、HTML と EPUB を書かない（2026-11-05 の監査の CLI の再現と同じ入力）。
  - 検査を通る SVG の図版の HTML と EPUB の出力が、この変更の前とバイト列で同じである。

## トレードオフ

- すべての属性の値を CSS として探すので、`url(` で始まる外部の文字列を書いた、ブラウザーが読まない属性（`aria-label` など）も拒む。外部を読む属性の一覧を保つよりも、一覧の漏れがない。
- `xml-stylesheet` のほかの処理命令を通すので、将来ブラウザーが別の処理命令に働きを与えると漏れる。描画ソフトのメタデータを拒まないことを優先した。
- XHTML の要素は `src` の有無にかかわらず拒む。SVG の図版に XHTML の要素を `foreignObject` の外で書く理由は乏しく、属性の一覧（`src`、`srcset`、`poster` など）を保たずに済む。
- ブラウザーが読むかを確かめないので、実際には読まない形も拒んでいる可能性がある。拒まれた利用者は、その形を SVG から除く手間を負う。

## 決めたことの記録

- **採択**：メンテナーが採択した（2026-11-05）。この ADR が決めてほしい点として挙げた項目は、どれも ADR の推奨のとおりとする。

## 参考文献

- [2026-10-24 のセキュリティ監査](../audits/2026-10-24-security-audit.md) の C9
- [2026-11-05 のセキュリティ監査](../audits/2026-11-05-security-audit.md) の V-02、[svg-probe.hs](../audits/2026-11-05-evidence/svg-probe.hs)、[svg-probe.txt](../audits/2026-11-05-evidence/svg-probe.txt)
- W3C, "Scalable Vector Graphics (SVG) 2", 16.2 "Styling" と 19 "Animation". https://www.w3.org/TR/SVG2/
- W3C, "Associating Style Sheets with XML documents 1.0 (Second Edition)". https://www.w3.org/TR/xml-stylesheet/
- W3C, "CSS Images Module Level 4", `image-set()`. https://www.w3.org/TR/css-images-4/#image-set-notation
