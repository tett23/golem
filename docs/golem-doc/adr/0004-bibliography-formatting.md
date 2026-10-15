# ADR 0004: 参考文献の一件の書式を文字の種類に合わせる

ステータス: 採択

## 文脈

Golem の利用者のマニュアル（`manual/`）を組んだ PDF の参考文献には、`JIS X 4061:1996 日本語文字列照合順番. 日本規格協会 . 1996.` と組まれた行がある。
「日本規格協会」と「.」のあいだに空きが入っている。

書誌の文字列そのものに空白はない。
golem-driver の `Golem.Driver.loadBibliography` は、CSL-JSON の各項目から、著者、題（`title`）、発行者（`publisher`）、発行の年（`issued` の `date-parts` の最初の数）を取り出し、空でないものを `". "` でつなぎ、末尾に `"."` を付ける。
空きを入れたのは行組版である。
golem-layout の `Golem.Layout.CharClass.charClass` は ASCII の文字をすべて欧文（cl-27）に分類し、`Golem.Layout.Aki.defaultAkiSet` は和字と欧文のあいだに四分（最小 1/8、最大 1/2）の空きを置く。
ASCII のピリオドは欧文の文字なので、和字の直後のピリオドの前に四分が入る。
JLReq の 3.2.6 は、和字と欧文の文字や数字のあいだに四分の空きを置くと定めている。
欧文の句読点が和字の直後に来る場合をこの規則がどう扱うかは、確かめた範囲の本文では読み取れなかった。

つまり、和文の書誌に欧文の区切りを使う書式そのものに無理がある。
本文の和文で「。」の代わりに「.」を書く人はまずいない。
書誌の書式だけが、どの言語の文献にも欧文の区切りを使っている。

同じ関数を読むと、ほかにも欠けがある。

- **`literal` の名前**：CSL-JSON の名前のオブジェクトは、`family` と `given` のほかに、団体名などを一つの文字列で書く `literal` を持てる（CSL-JSON のスキーマの `name-variable`）。`nameOf` は `family` と `given` しか読まないので、`{"literal": "日本規格協会"}` の著者は空の文字列になり、一覧から消える。
- **和文の人名**：`nameOf` は `family`、空白、`given` の順につなぐ。`{"family": "山田", "given": "太郎"}` は「山田 太郎」になる。CSL の仕様は、中国語や日本語のような「姓、名」の順の文字体系の名前を姓、名の順に表示すると定め、例に空白のない「毛泽东」を挙げる。
- **日付の `literal`**：CSL-JSON の日付は `date-parts` のほかに `literal` を持てる。`date-parts` のない項目は年が出ない。
- **読めないファイル**：`loadBibliography` は、ファイルがないとき、JSON として読めないとき、配列でないときに、何も言わずに空の一覧を返す。その結果、本文のすべての `[cite ...]` が G0221（書誌データにないキー）になり、原因がファイルにあることがわからない。`manifest.toml` に存在しないファイルを書いて確かめると、G0221 だけが出る。
- **プレーンテキスト**：golem-text の `@bibliography` は、書誌ではなくキーを `[1] jlreq` のように並べる。HTML と PDF は `loadBibliography` の文字列を使う。

書式の置き場所も問題である。
書誌の書式は文書の内容であり、どの出力でも同じであるべきだが、今は golem-driver の I/O の関数の中にある。
golem-doc は aeson に依存しないので、JSON の読み込みは golem-driver に残し、書式だけを golem-doc に移すのが自然である。

書式の選択（CSL のスタイル）は「v2 以降に回した事項」の「索引と参考文献の拡張」に入っている。
この ADR は、v1 の一種類の書式の中で、上の欠けを埋める。

## 実装すること

### 書式の置き場所

golem-doc に `Golem.Doc.Bibliography` を加える。

```haskell
data CslName
  = PersonalName {cnFamily :: !(Maybe Text), cnGiven :: !(Maybe Text)}
  | LiteralName !Text

data CslDate = DateYear !Integer | DateLiteral !Text

data CslEntry = CslEntry
  { ceId :: !Text,
    ceLanguage :: !(Maybe Text),
    ceAuthors :: ![CslName],
    ceTitle :: !(Maybe Text),
    cePublisher :: !(Maybe Text),
    ceIssued :: !(Maybe CslDate)
  }

formatEntry :: CslEntry -> Text
```

golem-driver の `loadBibliography` は、CSL-JSON を `CslEntry` に読み、`formatEntry` で文字列にする。
HTML、EPUB、PDF、プレーンテキストは、この文字列を使う。
golem-text の `@bibliography` は、キーの代わりに `[n] ` と書誌の文字列を並べる。
書誌にないキー（G0221 になったもの）は、今の HTML と PDF と同じくキーをそのまま出す。

### CSL-JSON の読み方

- 名前：`literal` が文字列なら `LiteralName` とし、`family` と `given` は読まない。そうでなければ `family` と `given` の文字列から `PersonalName` を作る。両方ない名前は捨てる。
- 日付：`issued` の `date-parts` の最初の要素の最初の数を年とする。`date-parts` から年が取れず、`literal` が文字列なら、それを `DateLiteral` とする。`raw`、`season`、`circa` は読まない。
- 言語：項目の `language` が文字列ならそれを使う。
- `id` が文字列でない項目は、今と同じく捨てる。

### 和文の項目と欧文の項目

項目ごとに、和文の項目か欧文の項目かを決める。

1. `language` があれば、その主の副タグ（最初の `-` の前）を英小文字にしたものが `ja` のときに和文、それ以外は欧文とする。
2. `language` がなければ、題が和字を一文字でも含むとき和文とする。題がなければ、著者、発行者の順に、最初にある欄で同じく判定する。どれもなければ欧文とする。

和字は、平仮名（U+3040 から U+309F）、片仮名（U+30A0 から U+30FF、U+31F0 から U+31FF）、CJK 統合漢字（U+4E00 から U+9FFF）とその拡張 A（U+3400 から U+4DBF）、CJK 互換漢字（U+F900 から U+FAFF）、「々」「〆」「〇」とする。
golem-doc は golem-layout に依存しないので、`charClass` を使わずにこの範囲で判定する。

項目の書式は次のとおりとする。

| | 欧文の項目 | 和文の項目 |
| --- | --- | --- |
| 欄の並び | 著者、題、発行者、年（今と同じ） | 同じ |
| 欄のあいだ | `. ` | `、` |
| 末尾 | `.` | `。` |
| 著者のあいだ | `, ` | `、` |

欧文の項目では、欄が `.`、`?`、`!` で終わるとき、その後の `. ` を ` ` に、末尾の `.` を付けないことにする。
`Breaking Paragraphs into Lines.` のように題が句点で終わる文献で、ピリオドが二つ並ばないためである。
和文の項目では、最後の欄が `。`、`？`、`！` で終わるとき、末尾の `。` を付けない。

### 名前の書き方

- `LiteralName`：文字列をそのまま書く。
- `PersonalName`：`family` か `given` のどちらかが和字を含むとき、`family`、`given` の順に空白なしでつなぐ。どちらも和字を含まないときは、今と同じく `family`、空白、`given` の順とする。片方しかなければ、その片方だけを書く。

欧文の名前の順（今は「Knuth Donald」）は変えない。
CSL の既定の表示順（名、姓）に直すかどうかは、書式の選択と一緒に決めるほうがよいからである。

### 例

`manual/references.json` の二件は、次のようになる。

```
日本語組版処理の要件、W3C、2020。
JIS X 4061:1996 日本語文字列照合順番、日本規格協会、1996。
```

`{"author": [{"family": "Knuth", "given": "Donald"}], "title": "Breaking Paragraphs into Lines", "issued": {"date-parts": [[1981]]}}` は、今と同じく `Knuth Donald. Breaking Paragraphs into Lines. 1981.` である。

### 読めない書誌のファイル（G0326）

`manifest.toml` の `bibliography` に並べたファイルについて、次の誤りを G0326 とする。

| 条件 | メッセージ |
| --- | --- |
| ファイルがない | `参考文献のファイルがありません: <パス>` |
| JSON として読めない | `参考文献のファイルを JSON として読めません: <パス>（<aeson の文言>）` |
| 最上位が配列でない | `参考文献のファイルは CSL-JSON の配列で書きます: <パス>` |

- 重大度はエラーとし、プロファイルで変えない。
- 位置は `manifest.toml` の先頭とする。`Manifest` は値の位置を持たないためである（[golem-project ADR 0006](../../golem-project/adr/0006-project-diagnostic-codes.md) の G0302 と同じ扱い）。
- パスの形の誤り（URL、絶対パス、ルートの外）は、章のパスと同じ `Golem.Project.Paths.resolveInRoot` で調べ、G0303 とする。
- 読めなかったファイルの項目はないものとして評価を続けるので、そのファイルの文献を引く `[cite ...]` には G0221 も出る。G0326 が先に並ぶよう、ソートの規則（ファイル、位置、コード）に任せる。`manifest.toml` は FileId 0 である。
- `golem check` と、どのターゲットのビルドも G0326 を出す。書誌はどの出力でも使うからである。LSP は、プロジェクトの誤りと同じく `manifest.toml` に載せる。
- aeson の文言は英語である。文言を訳すのは G0326 の範囲に入れない。

G0326 を 03 の区分にするのは、`manifest.toml` が宣言したファイルの誤りであり、G0302 と同じ性質だからである。

### データ構造の変更

- golem-doc に `Golem.Doc.Bibliography`（上の型と `formatEntry`）を加える。
- golem-driver の `loadBibliography` の型を `FilePath -> Manifest -> IO ([Diagnostic], Set Text, Map Text Text)` に変える。
- golem-text の設定に、書誌の文字列の表（`Map Text Text`）を加える。

### ドキュメント

- docs/specifications.md の「引用と参考文献」に、一件の書式（欄の並び、和文の項目と欧文の項目の区切り、名前の書き方、`literal` の扱い）を書き、この ADR へリンクする。
- 同じく「今後の実装項目」の「記法と設定」から「参考文献の書式」の項を除く。
- 同じく「未決事項」か「v1 の実装で次の段階以降に回した項目」に、和字の直後の欧文の句読点（`.`、`,`、`:` など）の前に和欧間の空きを入れるかどうかを、JLReq と JIS X 4051 の本文で確かめる項目を加える。
- docs/diagnostics.md に G0326 の節を加える。
- 利用者のマニュアル（`manual/`）の `manual/chapters/04-manifest.gm` の「参考文献のデータ」の節の「一覧には、著者、題、発行者、発行の年を、この順に並べて組みます。」で始まる段落を、和文の文献は「、」と「。」で、欧文の文献は「. 」と「.」で区切ること、`literal` の名前と日付を使えることに改める。付録E「診断の一覧」（[golem-cli ADR 0006](../../golem-cli/adr/0006-preflight.md) より前に実装するときは付録D）に G0326 を加える（[docs/adr/0024](../../adr/0024-manual-audiences-and-policy.md)）。

## 実装しないこと

- CSL のスタイルの解釈と書式の選択。v2 以降に回したままである。
- `editor`、`container-title`、`volume`、`page`、`URL`、`DOI` など、今読まない欄を一覧に出すこと。
- 名前の `dropping-particle`、`non-dropping-particle`、`suffix`、`parse-names` の扱い。
- 日付の `raw` を解釈すること。
- 欧文の名前の順を変えること。
- 本文の和字と欧文の句読点のあいだの空きを変えること。行組版の規則の変更であり、JLReq と JIS X 4051 の本文で確かめてから別の ADR で扱う。
- 中国語と韓国語の項目の書式。`language` が `zh` や `ko` の項目は欧文の項目として組む。

## テスト設計

### 先に書いて失敗させるテスト

`modules/golem-doc/test`（`Golem.Doc.Bibliography`）：

- `manual/references.json` の二件にあたる `CslEntry` が、上の例の二行になること。
- Knuth の項目が `Knuth Donald. Breaking Paragraphs into Lines. 1981.` のままであること。
- `LiteralName "日本規格協会"` の著者と和文の題の項目が、`日本規格協会、<題>、<年>。` になること。
- `PersonalName (Just "山田") (Just "太郎")` が `山田太郎` に、`PersonalName (Just "Knuth") Nothing` が `Knuth` になること。
- 和文の著者二人が `、` で、欧文の著者二人が `, ` でつながること。
- `language = "ja-JP"` で題が欧文だけの項目が、和文の区切りになること。`language = "en"` で題が和文の項目が、欧文の区切りになること。
- `language` がなく、題がなく、発行者が和文の項目が、和文の区切りになること。
- 題が `What Is Typesetting?` の欧文の項目で、`?` の後が `. ` ではなく ` ` になること。最後の欄が `.` で終わる項目で、末尾にピリオドを足さないこと。
- 題が `。` で終わり、それが最後の欄である和文の項目で、末尾に `。` を足さないこと。
- `DateLiteral "1996年3月"` の項目で、年の欄がその文字列になること。

`modules/golem-driver/test/Main.hs`：

- `literal` の著者を持つ CSL-JSON を `loadBibliography` に読ませ、書誌の文字列にその名前が入ること。
- `issued` が `{"literal": "n.d."}` の項目で、年の欄が `n.d.` になること。
- `bibliography = ["nope.json"]` のプロジェクトで、G0326 の `参考文献のファイルがありません: nope.json` が `manifest.toml` の先頭に出ること。
- 中身が `{` だけのファイルで G0326 の JSON の文言が、`{}` のファイルで配列の文言が出ること。
- `bibliography = ["/abs.json"]` が G0303 になること。
- 和文の項目を引用する原稿の HTML の `<li>` に `、` と `。` で区切った書誌が出ること。
- 同じ原稿の PDF の書誌の行の文字列に `日本規格協会 .` が現れず、`日本規格協会、` が現れること（`bibliographyLines` に渡る表で確かめる）。

`modules/golem-text/test`：

- `@bibliography` の行が `[1] jlreq` ではなく `[1] 日本語組版処理の要件、W3C、2020。` になること。

### 自動テストにしない確かめ方

マニュアルを PDF に組み、巻末の参考文献の二行で、「、」と「。」のあとの空きが本文の句読点と同じに見えること、「日本規格協会」の後に余分な空きがないことを目で確かめる。

## トレードオフ

和文の項目に「、」と「。」を使う書式は、SIST 02 のように和文の書誌にも欧文の句読点を使う流儀とは合わない。
その流儀を選ぶと、和欧間の空きの扱いを行組版の側で変えない限り、今と同じ空きが入る。
行組版の規則を書誌のために変えると本文にも効くので、書式の側で和文の句読点に寄せるほうが影響が狭い。
SIST 02 の流儀は、v2 で書式を選べるようにするときに、選べる書式の一つとして扱える。

和文の項目かどうかを題の文字で推すので、和文の題を持つ欧文の文献（題を原語のまま挙げた翻訳書の書誌など）は和文の区切りになる。
`language` を書けば正しく分けられるので、推定は `language` がないときの既定にとどめる。

G0326 を出すと、今まで黙って空の一覧になっていたプロジェクトがエラーで止まる。
読めないファイルを黙って捨てると G0221 が原稿のすべての引用に出て、原因を探す手間のほうが大きい。

## 参考文献

- Citation Style Language 1.0.2 Specification, "Name-part Order" and "Names", https://docs.citationstyles.org/en/stable/specification.html
- CSL-JSON schema (`csl-data.json`), https://github.com/citation-style-language/schema/blob/master/schemas/input/csl-data.json
- W3C, Requirements for Japanese Text Layout（JLReq）, 3.2.6 "Handling of Western Text in Japanese Text using Proportional Western Fonts", https://www.w3.org/TR/jlreq/
- JIS X 4051:2004 日本語文書の組版方法
- 科学技術振興機構, SIST 02 参照文献の書き方
