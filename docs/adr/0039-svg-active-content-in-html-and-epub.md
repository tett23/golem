# ADR 0039: HTML と EPUB に写す SVG の図版の、動く中身を拒む

ステータス: 採択

## 文脈

[golem-pdf ADR 0009](../golem-pdf/adr/0009-svg-figures.md) は、SVG の図版を PDF ではベクターのまま描き、HTML と EPUB ではファイルをそのまま写して `<img>` で置くと決めた。
同じ ADR は、HTML と EPUB では SVG の中身を検査しないとも決めた。
PNG と JPEG の図版を HTML と EPUB で検査しないことに合わせた判断である。

2026-10-18 の rc3 のセキュリティ監査で、この決定に次の危険があることがわかった。
この監査の記録は、まだ `main` に入っていない。

- SVG は XML の文書であり、画像の形式であると同時に、スクリプトを持てる文書でもある。`script` の要素、`onload` などのイベントの属性、`javascript:` の URL を持つ `href`、HTML を埋め込む `foreignObject` を書ける。
- `<img>` で置いた SVG では、ブラウザーはスクリプトを動かさず、外部の資源も読まない。
- 一方、読者が SVG のファイルを直接開くと、SVG は文書として描かれ、スクリプトが動く。画像を新しいタブで開く操作や、SVG の URL へのリンクで、直接開くことになる。HTML の出力をサイトとして公開していれば、スクリプトはそのサイトのオリジンで動く。
- EPUB でも、リーダーによっては SVG の項目を文書として開ける。EPUB 3 は、スクリプトを持つ内容に `scripted` の属性を求めるが、Golem はそれを書かない。
- `golem build` で PDF も組めば、PDF の側の G0811 が `script` などを範囲の外として止める。しかし、HTML と EPUB だけを組む本や、`web` に SVG を指定した PDF の図版では、何も止めない。

[セキュリティ監査の脅威のモデル](../audits/2026-10-17-security-audit.md) では、原稿のリポジトリの中身はすべて攻撃者が書けて、Golem が書いた HTML と EPUB を読む人も被害者になりうる。
SVG の図版は、攻撃者の書いたスクリプトを、Golem の出力として読者に届ける道になる。
これは監査の候補 C12 にあたる。

直し方は三つ考えられる。

1. **拒む**：動く中身を持つ SVG を、diagnostic のエラーにしてビルドを止める。
2. **取り除く**：動く中身を消した SVG を書き出す。
3. **変換する**：PDF と同じ部分集合で読み、Golem が SVG を書き直すか、ラスタにする。

Golem は、利用者の入力を黙って別のものに変えない（[docs/adr/0015](0015-regex-styles.md) などの方針）。
取り除く案では、原稿と出力の SVG が食い違う。
取り除いたことをお知らせで伝えても、出力の SVG の中身を利用者が確かめる手間は残り、取り除き漏れがあれば、それが脆弱性になる。
変換する案は、[golem-pdf ADR 0009](../golem-pdf/adr/0009-svg-figures.md) が HTML と EPUB に認めた範囲（輪郭にしていない文字など）を狭めてしまう。
この ADR では拒む案を選ぶ。

## 実装すること

### 検査（G0814）

`golem build` の HTML と EPUB のターゲットは、出力に写す SVG のファイル（`@figure` の図版か `web` の、拡張子が `.svg` のもの）を、写す前に読んで検査する。
検査は golem-svg の XML の読み手（`Golem.Svg.Xml.parseXml`）で SVG を読み、要素と属性を文書の順にたどって行う。
次のどれかがあれば、新しいエラー G0814 を出す。

| 種類 | 拒むもの |
| --- | --- |
| スクリプトの要素 | `script`（名前空間を問わない） |
| 別の文書を埋め込む要素 | `foreignObject`、`iframe`、`embed`、`object`、`handler`、`listener` |
| イベントの属性 | 名前が `on` で始まる属性（大文字と小文字を区別しない） |
| 参照の属性 | `href` と `xlink:href` のうち、値が `#` で始まらないもの（文書の中の参照だけを許す） |
| アニメーションによる書き換え | `set`、`animate` の要素で、`attributeName` が `href`、`xlink:href`、または `on` で始まる名前のもの |
| CSS の外部の参照 | `style` の要素と `style` の属性の中の `@import` と、`url(` の後が `#` で始まらないもの |

- XML として読めない SVG、UTF-8 でない SVG、内部サブセットを持つ `DOCTYPE` を持つ SVG も、中身を確かめられないので G0814 とする。理由は、G0810 と同じ文言を括弧の中に書く。
- メッセージは `SVG の図版に、HTML と EPUB に写せない動く中身があります: <パス>:<行>:<桁>（<名前>）` とする。
  - `<名前>` は、要素の名前、属性の名前、または `url()` か `@import` である。
  - 見つかったものが複数あれば、G0811 と同じく最初のものを書き、`ほか <n> 件` を添える。
- 位置は、その SVG を参照する `@figure` のブロックとし、`@figure` ごとに一つ出す。
- G0814 は dev と prod の両方でエラーである。エラーがあれば、HTML と EPUB を書かない。
- 一つの SVG を複数の `@figure` が参照していても、ファイルは一度だけ読む。

### 変えないこと

- 取り除くことも、書き直すこともしない。検査を通った SVG は、今と同じくバイト列をそのまま写す。
- 輪郭にしていない文字、`@font-face`、PDF の部分集合の外のプロパティは、HTML と EPUB では今と同じく許す。G0814 が見るのは、上の表のものだけである。
- PDF のターゲットは変えない。PDF の側の G0810 と G0811 は今のままである。
- PNG と JPEG の図版は検査しない。

### SVG の図版の ADR との関係

この ADR は、[golem-pdf ADR 0009](../golem-pdf/adr/0009-svg-figures.md) の「HTML と EPUB は SVG の中身を検査しない」を、上の表のものについて改める。
採択するときに、その ADR のステータスの行に、HTML と EPUB での SVG の動く中身の検査はこの ADR が置き換えたことを、この ADR へのリンクで足す。

### ドキュメント

- `docs/diagnostics.md` に G0814 の節を足す。
- 仕様書の [「図版」の節](../specifications.md#図版) の、HTML と EPUB での SVG の扱いに、G0814 の検査を書く。
- `docs/markup.md` の「図版」の節と、利用者向けマニュアルの図版の章と diagnostic の付録に、HTML と EPUB に写せない SVG を書く。
- 開発者向けマニュアルの、SVG の図版を扱う章に、検査の場所と表を書く。
- この ADR をコミットするプルリクエストで、`docs/adr/0021-docs-workflow-and-ci-gate.md` の 199 行目の「peg-hs ADR 0039」に、peg-hs のその ADR への絶対リンクを付ける。adr-guard は、この ADR を足すと、その「ADR 0039」をこの ADR への参照と読み、リンクがないと指摘するためである。リンクを付けるだけの変更なので、`--allow-links` で許される。

## 実装しないこと

- 動く中身を取り除いた SVG を書き出すこと。理由は「文脈」にある。
- SVG をラスタにするか、Golem が SVG を書き直すこと。
- EPUB の項目に `scripted` の属性を書いて、スクリプトを持つ SVG を許すこと。
- HTML の出力に Content Security Policy の `meta` を書くこと。`<img>` の外で直接開いた SVG には適用されず、公開するサーバーの設定に任せる。
- `image` の要素と `use` の要素の、文書の中の参照（`#` で始まる値）の禁止。文書の外を読まないので、拒む理由がない。
- PNG と JPEG を検査すること。

## テスト設計

どれも、修正の前に失敗することを確かめてから実装する。
SVG は、テストの中に短い文字列で書く。
スクリプトの中身は動く必要がないので、空の要素か、何もしない値にする。

- golem-svg（検査の関数の単体テスト）
  - 空の `script` の要素を持つ SVG が、`script` の名前と位置を返す。
  - `onload` の属性（値は空）を持つ `rect` が、`onload` を返す。`ONLOAD` と書いても同じ。
  - `href` が `#a` の `use` は通り、`href` が `other.svg` の `use` は `href` を返す。`xlink:href` も同じ。
  - 空の `foreignObject` を持つ SVG が、`foreignObject` を返す。
  - `attributeName` が `href` の `set` の要素が、`set` を返す。
  - `style` の要素の `@import` と、`fill: url(x.svg#a)` が返り、`fill: url(#g)` は通る。
  - 輪郭にしていない `text` の要素と `@font-face` だけを持つ SVG は通る（PDF の部分集合と違うことの確かめ）。
  - 見つかったものは文書の順に並ぶ。
- golem-driver
  - 空の `script` の要素を持つ SVG の図版で、`golem build --target html` と `--target epub` が G0814 を出し、`build/html` と `build/epub` に何も書かない。メッセージにパス、行、桁、名前がある。
  - 同じ SVG を `web` にした PDF の図版で、`--target html` が G0814 を出す。
  - 検査を通る SVG の図版の HTML と EPUB の出力が、この変更の前とバイト列で同じである。
  - G0814 が dev と prod の両方でエラーである。
- `docs/diagnostics.md` の G0814 の節は、golem-driver の既存のテスト（使っているコードが文書に載っていること）が確かめる。

## トレードオフ

- 拒む案では、外部のファイルを参照する SVG や、Web 用に作ったインタラクティブな SVG は、HTML と EPUB に使えなくなる。そうした図は、`web` に PNG を置くか、参照を外した SVG を用意する必要がある。
- 拒むものを列挙する方式なので、表にない動く中身（ブラウザーの新しい機能など）は通りうる。許すものだけを並べる方式は、[golem-pdf ADR 0009](../golem-pdf/adr/0009-svg-figures.md) が HTML と EPUB に認めた範囲を狭めるので、選ばなかった。
- HTML と EPUB のビルドが SVG を読むようになり、大きな SVG ではビルドが遅くなる。
- `golem-svg` の XML の読み手を、PDF 以外の出力でも使うことになる。読み手の計算量の問題は、そのまま HTML と EPUB のビルドにも及ぶ。

## 参考文献

- W3C, Scalable Vector Graphics (SVG) 2, 2018（`script` の要素、イベントの属性、`foreignObject`）。https://www.w3.org/TR/SVG2/
- W3C, SVG Integration, 2014（`<img>` で参照した SVG の、スクリプトを動かさない「secure animated mode」）。https://www.w3.org/TR/svg-integration/
- W3C, EPUB 3.3, 2023（`scripted` の属性と、スクリプトを持つ内容の扱い）。https://www.w3.org/TR/epub-33/
- OWASP, "Cross Site Scripting Prevention Cheat Sheet". https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html
