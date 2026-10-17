# ADR 0033: 奥付の関係者と刷

ステータス: 採択

## 文脈

v0.1.0-rc3 で、奥付に編集者、印刷所、製本所を載せられるようにし、版だけでなく刷も扱う（メンテナーの指示、[docs/roadmap.md](../roadmap.md) の「奥付の関係者と刷」）。

### 今のメタデータ

マニフェストの `[metadata]` が持つ値は次のとおりである（golem-project の `Golem.Project.Manifest` の `Metadata`、[golem-project ADR 0001](../golem-project/adr/0001-manifest-and-import-graph.md)）。

- `id`、`title`、`title-reading`、`language`、`date`（TOML の日付。`Day`）
- `edition`（任意の文字列）と `publisher`（任意の文字列）
- `creators`（`name`、`reading`、`role` の表の配列）

`creators` の `role` は MARC relator の符号を書くと仕様書の「メタデータ」の節は定めるが、コードは `Text` のまま読み、形も値も検査しない。
編集者や印刷所を書く欄はない。
`creators` に `role = "edt"` で編集者を書くことはできるが、EPUB のパッケージ文書では著者と同じ `dc:creator` になる。
刷を書く欄はなく、`edition` は版を表す自由な文字列である。

### 役割の符号の今の使われ方

`role` の値の書き方は、次の箇所が MARC relator の符号（`aut` など）で説明し、使っている。

- docs/specifications.md の「メタデータ」の節（例の `role = "aut"` と、MARC relator の符号を使うという文）
- ユーザー向けのマニュアルの第 4 章（`manual/chapters/04-manifest.gm`）と付録 B（`manual/appendices/b-manifest.gm`）。`"aut"`、`"edt"`、`"trl"` を例に挙げる
- 二つのマニュアルの `manifest.toml`（`role = "aut"`）
- golem-driver のテストの fixture の `manifest.toml` 13 個（`aut` が 13 箇所、frogs の `trl` が 1 箇所）
- golem-epub のテスト（`PackageSpec.hs`）。`EpubCreator` に符号を直に渡す

`golem new` のひな形は `creators` を書かない。

符号は 3 字の略語であり、`aut` が著者、`bnd` が製本所であることは、一覧を引かなければ分からない。
書き手が読み書きする `manifest.toml` には向かない。
符号が要るのは、EPUB のパッケージ文書の `role` だけである。

### 出力のメタデータ

コードを読んで確かめた、今の写し方は次のとおりである。

- **EPUB**（golem-epub の `packageDocument`、[golem-epub ADR 0001](../golem-epub/adr/0001-epub-packaging.md)）：`creators` のすべてを、役割によらず `dc:creator` に書き、役割を `refines` の `role`（`scheme="marc:relators"`）で、読みを `file-as` で付ける。`publisher` は `dc:publisher` に書く。`date` は `dcterms:modified` にだけ使い、`dc:date` は書かない。`edition` は書かない。
- **PDF**：XMP を書くのは出力インテントを指定した場合（PDF/X）だけである（golem-pdf の `xmpPacket`）。`dc:creator` には `creators` の名前を役割によらず並べる。文書情報辞書には `Producer` のほかの書誌の値を書かない。
- **HTML**：`head` に書くのは `title` だけである。

### 本文からの参照

本文は式文脈の名前空間 `meta` でメタデータを参照する（仕様書の「本文からの参照」）。
値は golem-driver の `metadataValues` が作り、`id`、`title`、`language`、`date`、あれば `title_reading`、`edition`、`publisher` を文字列で、`creators` を名前の文字列の配列で持つ。
`date` は `2026-10-16` の形の文字列である。
マニフェストのキーの `-` は、`meta` では `_` になる（`title-reading` と `title_reading`）。
式の言語では `-` が引き算の演算子だからである。

式の言語には、配列の要素を取り出す書き方も、配列を順に処理する書き方もない（[golem-eval ADR 0001](../golem-eval/adr/0001-expression-language-and-numerics.md)、golem-parser の `Expr`）。
配列を本文に埋め込むと型エラー（G0201）になる。
このため、今の Golem では `meta.creators` を本文に出す手段がない。
連想配列の入れ子は `meta.a.b` の形で引ける（golem-eval の `lookupMember`）。
ない鍵を引くと G0202 になる。

マニュアルの奥付（`manual/back.gm`）は、`meta.title`、`meta.date`、`meta.publisher` と、`scripts/manual/build-info.sh` が書いた `common/build-info.gm` の `build.edition`、`build.commit` から組んでいる。
マニュアルの「版」は Golem のバージョンであり、出版の版と刷ではない。

### 奥付の慣行について

日本の書籍の奥付には、書名、著者、発行の日の履歴（「2026年10月16日　初版第1刷発行」の形の行を版と刷ごとに重ねたもの）、発行者、発行所、印刷所、製本所、ISBN を載せることが多い。
これは市販の書籍の奥付を見た経験にもとづく前提であり、規格の本文では確かめていない。
JIS X 4051 は組版の規則の規格であり、奥付に載せる項目を定めているかは確かめていない。
この ADR は、特定の規格に合わせるのではなく、上の項目を書き手が組めることを目標にする。

刷は、同じ版を内容を変えずに刷り直した回である。
版を改めると刷は 1 に戻る。
版と刷の番号と、それぞれの発行の日は、本の履歴であり、一冊の奥付に並べて載せる。

### メンテナーが決めたこと

草稿の未決事項に、メンテナーが次のとおり答えた。

- 印刷所と製本所は、EPUB のパッケージ文書に書かない。PDF の XMP にも書かず、奥付のための値とする。
- `date`（出力の日時のもと）と、最後の刷の日付は独立にする。
- 縦組みの `@printings` の年は、一字ずつの漢数字（二〇二六）にする。
- `@printings` の書式は設定で変えられるようにするが、実装は v0.1.0-rc4 か v1.0.0 で行う。この ADR は一つの書式に固定する。
- 発行所は、今の `publisher` に書く。役割の語にはしない。
- 発行人（奥付に発行者として載せる個人。発行所とは別）も、マニフェストに書けるようにする。
- 書き手が書く役割は、`aut` のような略した符号ではなく、英語の語（`author`、`editor` など）にする。符号は、出力の形式が求める場所でだけ Golem が内部で使う。

### 未決

- 新しい診断のコード G0276 は、ほかの rc3 の草稿が使う番号（G0275 まで）の次として仮に選んだ。採択の前に空いていることを確かめる。

## 実装すること

### マニフェスト

`[metadata]` に二つの表の配列を加える。

```toml
[metadata]
id = "urn:uuid:3f6c..."
title = "Golem 入門"
language = "ja"
date = 2027-04-01
publisher = "ゴーレム書房"
publisher-person = "佐藤 一郎"

[[metadata.creators]]
name = "山田 太郎"
role = "author"

[[metadata.contributors]]
name = "鈴木 花子"
reading = "すずき はなこ"
role = "editor"

[[metadata.contributors]]
name = "株式会社〇〇印刷"
role = "printer"

[[metadata.contributors]]
name = "株式会社△△製本"
role = "binder"

[[metadata.printings]]
edition = 1
printing = 1
date = 2026-10-16

[[metadata.printings]]
edition = 1
printing = 2
date = 2027-04-01
```

- **`contributors`**：本に二次的に関わった人と組織である。項目のキーは `creators` と同じく `name`（必須）、`reading`（任意）、`role`（必須）とする。`creators` は主たる著作者（著者、訳者など）に、`contributors` はそのほか（編集者、印刷所、製本所、装丁者など）に使う。この区別は EPUB の `dc:creator` と `dc:contributor` の区別にそのまま対応する。
- **`printings`**：版と刷の履歴である。項目のキーは `edition`（1 以上の整数）、`printing`（1 以上の整数）、`date`（TOML の日付）で、どれも必須とする。最後の項目を、この出力の版と刷（現在の刷）とする。
- 既存の `edition`（自由な文字列）、`date`、`publisher` は変えない。`printings` とは独立の値である。
- 発行所は `publisher` に書く。
- **`publisher-person`**：発行人（発行者として奥付に載せる個人）の名前である。任意の文字列のキーとする（下の「発行人」）。

### 発行人

発行人は、`[metadata]` の文字列のキー `publisher-person` に書く。

キーの名前は、発行所の `publisher` と対になることが読んで分かるように選んだ。
略語や符号を使わず、英語の語だけでできている。
`issuer` は「発行する者」の意味では合うが、発行所との関係が名前から読めず、証券や証明書の発行者の意味で使われることが多いので採らない。
`publisher-name` は、発行所の名前と読めるので採らない。

役割の表の語（`contributors` の `role`）にはしない。
理由は三つある。

- 発行人はふつう一冊に一人であり、配列で書く必要がない。
- 役割の表の語は、出力のメタデータに写す MARC relator の符号と対応させている。発行人にあたる符号はない（Publishing director、`pbd` は、共同著作の全体をまとめる者であり、発行人とは意味が違う）。
- `publisher` と並べて書けるほうが、奥付の「発行人」と「発行所」の対と対応する。

読み（`reading`）は持たない。
出力のメタデータに書かないので、並べ替えや検索に使う場所がないためである。

本文からは `meta.publisher_person` で参照する（`title-reading` が `meta.title_reading` になるのと同じ規則）。
キーがなければ鍵もなく、引くと G0202 になる。

出力のメタデータには書かない。
EPUB の `dc:publisher` と XMP の `dc:publisher` は発行所（`publisher`）を書く欄であり、発行人に合う欄が EPUB にも XMP の Dublin Core にもないためである。
印刷所と製本所と同じく、奥付のための値とする。

`publisher` がなくても `publisher-person` だけを書ける。
個人で発行する本では、発行所がなく発行人だけを載せることがあるためである。

### 役割の語彙

`role` は次の表の語で書く。
`creators` と `contributors` で同じ表を使う。

| 語 | 奥付の項目 | MARC relator の符号 | 出力のメタデータ |
| --- | --- | --- | --- |
| `author` | 著者 | `aut`（Author） | 書く |
| `translator` | 訳者 | `trl`（Translator） | 書く |
| `editor` | 編集 | `edt`（Editor） | 書く |
| `illustrator` | 挿絵 | `ill`（Illustrator） | 書く |
| `book-designer` | 装丁 | `bkd`（Book designer） | 書く |
| `cover-designer` | カバーのデザイン | `cov`（Cover designer） | 書く |
| `typesetter` | 組版 | `cmt`（Compositor） | 書く |
| `printer` | 印刷所 | `prt`（Printer） | 書かない |
| `binder` | 製本所 | `bnd`（Binder） | 書かない |

語は、MARC relator の名前を英小文字にし、空白を `-` にしたものを基本とする。
`typesetter` だけは、MARC の名前の Compositor が日本語の「組版」の意味で通じにくいので、語を変えた。
製本所の符号は `bnd`（Binder）である。
`bdd` は Binding designer（製本の意匠を考える人）であり、製本所ではない。

表は Golem が持つ閉じた語彙とする。
語から符号を引くには表が要り、表にない語は符号に写せないためである。
表に語を足すのは、使う本が出たときに ADR なしの変更で行ってよい。
足した語は、仕様書とマニュアルの表に同時に足す。

印刷所と製本所は紙の本を作った者であり、電子書籍の書誌でも PDF の文書の書誌でもないので、出力のメタデータには書かない（下の「出力のメタデータ」）。
奥付の本文には `meta.roles` で組める。

### 今の符号からの移行

`role` の値は、符号から語に置き換える。
符号と語の両方を受け付ける案は採らない。
v1.0.0 の前であり、同じ値を二通りに書ける状態を残すと、仕様書、マニュアル、`meta.roles` の鍵がどちらの書き方にも対応しなければならなくなるためである。

置き換えた後で表の符号（`aut`、`trl` など）を `role` に書くと G0301 とし、語を示す。
メッセージは「役割は語で書きます。"aut" は "author" です」の形とする。
表にない符号（`pbl` など）も、表にない語と同じく G0301 とする。

リポジトリの中の `role = "aut"` と `role = "trl"`（二つのマニュアルの `manifest.toml` と、golem-driver の fixture の 13 個の `manifest.toml`）を、同じ変更で語に書き換える。
fixture の `manifest.toml` のバイト列が変わるので、その PDF のインスタンス ID が変わる。
EPUB のパッケージ文書の `role` は符号のままなので変わらない。

### 検査

次のどれも、マニフェストのほかの誤りと同じく G0301（エラー）とし、位置は誤った値とする。

- `role` が表の語でない（`creators` と `contributors`）。メッセージに表の語を並べる。表の符号を書いた場合は、上の移行のメッセージにする。
- `role = "publisher"`。メッセージは「発行所は [metadata] の publisher に、発行人は publisher-person に書きます」とする。
- `publisher-person` が空の文字列か、改行を含む。
- `name` が空の文字列である（`creators` と `contributors`）。
- `printings` の `edition` か `printing` が 1 より小さい。
- `printings` の項目が、（`edition`、`printing`）の辞書式の順で狭義に増えていない。同じ版と刷を二度書いた場合と、順を誤った場合が当たる。
- `printings` の `date` が、前の項目の `date` より前である。

刷の番号が飛ぶこと（第 1 刷の次に第 3 刷を書くこと）は許す。
奥付で途中の刷を省く本があるためである。

### 本文からの参照

`meta` に次の値を加える。

- **`meta.publisher_person`**：`publisher-person` の文字列である（上の「発行人」）。
- **`meta.roles.<役割>`**：`creators` と `contributors` のうち役割が `<役割>` である項目の名前の配列である。`<役割>` は表の語の `-` を `_` にしたもの（`meta.roles.cover_designer`）である。`creators` を先に、それぞれマニフェストの順に並べる。印刷所と製本所も含む。その役割の項目がなければ鍵もなく、引くと G0202 になる。
- **`meta.printing`**：現在の刷（`printings` の最後の項目）の連想配列であり、`edition`、`number`、`year`、`month`、`day` を整数で、`date` を `2026-10-16` の形の文字列で持つ。`printings` がなければ鍵もない。
- **`meta.printings`**：`printings` の全項目を、`meta.printing` と同じ形の連想配列の配列にしたものである。式の言語に配列を順に処理する書き方がないので、本文から直接は使わず、`len(meta.printings)` などに使う。

配列を本文に出すために、式の言語に組み込み関数 `join(配列, 区切り)` を加える。
`join` は文字列の配列の要素を、区切りの文字列をはさんでつないだ文字列を返す。
空の配列には空の文字列を返す。
要素に文字列でないものがある場合と、引数の型が違う場合は型エラー（G0201）とする。
これで `[= join(meta.roles.editor, "、")]` や `[= join(meta.creators, "、")]` と書ける。

刷の番号を縦組みで漢数字にしたい場合は、`[number-text [= meta.printing.number]]` と書く。

`meta` はファイル内評価（S0）の値のままである。
柱の差し込み（`{meta.<キー>}`、[golem-driver ADR 0022](../golem-driver/adr/0022-running-head-formats.md)）の表は変えない。
`publisher_person` も柱の差し込みには加えない。
柱に発行人を出す本は想定しにくく、表を広げる理由がないためである。

### 発行の履歴のブロック `@printings`

```
@printings
```

`printings` の全項目を、マニフェストの順に、一項目を一つの段落にして組むブロックコマンドである。
引数と散文スロットは取らない。
引数や散文スロットを書いた場合は、ほかのブロックコマンドと同じ引数の誤りとする。
`@style` などのブロックへの属性は、すべての段落に効く。

一つの段落は次の形である（`[metadata] language` が `ja` の場合）。

```
2026年10月16日　初版第1刷発行
2027年4月1日　初版第2刷発行
2028年1月10日　第2版第1刷発行
```

- 年、月、日と、版、刷の番号は、意味論 IR の `Number` にする。横組みでは算用数字、縦組みでは漢数字になる。年だけは `kanji-digits`（二〇二六）とし、月、日、版、刷は `[numbers]` の `vertical` の既定に従う。
- 版の番号が 1 なら「初版」、2 以上なら「第N版」とする。
- 日付と「初版」などのあいだには全角の空白を一つ置く。

書式はこの一つに固定する。
書式を `style.toml` で変えられるようにすることと、日本語でない本の書式は、v0.1.0-rc4 か v1.0.0 で扱う（[docs/roadmap.md](../roadmap.md) の v1.0.0 の「発行の履歴の書式」）。
そのときは、この ADR の書式を既定の値とし、別の ADR で設定のキーを決める。

`[metadata] language` が `ja` でない本で `@printings` を書くと、G0276（エラー）とし、何も組まない。
メッセージは「`@printings` は日本語の本（language = "ja"）でだけ使えます」とする。
`printings` のない本で `@printings` を書いた場合も G0276 とし、メッセージは「マニフェストに [[metadata.printings]] がありません」とする。

関係者の行（「印刷所　株式会社〇〇印刷」など）を組む組み込みの奥付は用意しない。
奥付に載せる項目、順序、見出しの語は本ごとに違い、`meta.roles` と `join` で書き手が組めるためである。
発行の履歴だけをブロックにするのは、項目の数が本ごとに違い、式の言語では順に処理できないためである。

### 出力のメタデータ

| 出力 | `creators` と `contributors` | `printings` |
| --- | --- | --- |
| EPUB | `creators` は今のとおり `dc:creator`、`contributors` は `dc:contributor`。どちらも役割を表の符号にして `refines` の `role`（`scheme="marc:relators"`）で、読みを `file-as` で付ける。`contributors` の `id` は `contributor1` からの連番 | 書かない |
| PDF（XMP を書く場合） | `creators` は今のとおり `dc:creator`（`rdf:Seq`）、`contributors` は `dc:contributor`（`rdf:Bag`）に名前を並べる。XMP の Dublin Core には役割を書く欄がないので、役割は書かない | 書かない |
| HTML | 書かない（今の `head` は `title` だけである） | 書かない |

役割が `printer` と `binder` の項目は、`creators` と `contributors` のどちらに書いても、EPUB と XMP に書かない。
連番の `id` は、書く項目だけで振る。
`publisher-person` も EPUB と XMP に書かない（上の「発行人」）。
`publisher` は今のとおり EPUB の `dc:publisher` に書く。
`printings` は奥付のための値であり、出力のメタデータの日付（`dcterms:modified`、XMP の日時）は今のとおり `date` から作る。

### 決定性

新しい値はすべてマニフェストから決まり、順序はマニフェストの配列の順である。
時刻やロケールを読まない。
`@printings` の文字列も `printings` と `language` だけで決まる。
入力のハッシュ（インスタンス ID）にはマニフェストが含まれるので、変更は要らない（[ADR 0002](0002-determinism.md)）。

### LSP と補完

`meta.` の補完に、`roles`、`printing`、`printings` を加える。
`meta.roles.` の補完は、マニフェストにある役割だけを出す。
組み込みの関数の補完に `join` を、ブロックコマンドの補完に `@printings` を加える。

## データ構造

```haskell
data Role
  = Author | Translator | Editor | Illustrator | BookDesigner
  | CoverDesigner | Typesetter | Printer | Binder
  deriving stock (Eq, Ord, Show, Enum, Bounded)

roleWord :: Role -> Text        -- "author"、"cover-designer" など
marcRelator :: Role -> Text     -- "aut"、"cov" など
inMetadata :: Role -> Bool      -- Printer と Binder だけ False

data Creator = Creator
  { crName :: !Text,
    crReading :: !(Maybe Text),
    crRole :: !Role
  }

data Metadata = Metadata
  { ...,
    mdPublisherPerson :: !(Maybe Text),
    mdContributors :: ![Creator],
    mdPrintings :: ![Printing]
  }

data Printing = Printing
  { prEdition :: !Int,
    prNumber :: !Int,
    prDate :: !Day
  }
```

`crRole` を `Text` から `Role` に変える。
語と符号の表は `Role` の関数として一箇所に置き、`[minBound .. maxBound]` から検査のメッセージと逆引きを作る。
`Creator` は `creators` と `contributors` で共有する。
golem-epub の `EpubCreator` の役割は符号の `Text` のままとし、golem-driver が `marcRelator` で写す。
golem-epub の `EpubConfig` に `epContributors :: [EpubCreator]` を、golem-pdf の `PdfX` に `pxContributors :: [Text]` を加える。
`@printings` は golem-eval の組み込みのブロックコマンド（`Fixed`）として加え、[ADR 0027](0027-exhaustive-command-dispatch-by-types.md) の型による網羅に入れる。
`meta.printings` は `@printings` が読む値でもある。

## 実装しないこと

- 組み込みの奥付のブロック（関係者、ISBN、発行所の住所などを並べるもの）。書き手が `meta` から組む。
- 符号から日本語の名前（「編集」など）を引くこと。
- 役割の符号を `role` に書く書き方（移行の誤りとして案内するだけ）。
- `@printings` の欧文の書式と、書式を変える設定（v0.1.0-rc4 か v1.0.0）。
- EPUB の `dc:date` と、XMP や PDF の文書情報辞書への版と刷の書き込み。電子書籍の発行日と紙の本の刷の日付は意味が違い、どの日付を書くかを決める材料がないためである。
- 印刷所と製本所の、EPUB と XMP への書き込み。
- HTML の `head` への書誌の値の書き込み。
- 式の言語の配列の添え字と、配列を順に処理する書き方。
- `edition` と `printings` の整合の検査。`edition` は自由な文字列であり、マニュアルのように版を表さない使い方もあるためである。
- 発行人の読みと、発行人を出力のメタデータに書くこと。
- 発行所の住所、電話番号、URL などの欄。必要なら `@import` した値で書く。
- JAN コード（[docs/roadmap.md](../roadmap.md) の v2 以降）。

## テスト設計

実装の前に次のテストを書き、失敗することを確かめる。

### golem-project

- `contributors` と `printings` を持つマニフェストを読み、`mdContributors` と `mdPrintings` がマニフェストの順に入ること。表のすべての語が `Role` に読めること。
- 次のそれぞれが G0301 になり、位置が誤った値であること：`role = "aut"`（メッセージに `"author"` を含む）、`role = "trl"`（`"translator"` を含む）、`role = "pbl"`、`role = "Author"`、`role = "writer"`（メッセージに表の語を並べる）、`role = "publisher"`（メッセージに `publisher` と `publisher-person` のキーを含む）、`publisher-person = ""`、改行を含む `publisher-person`、`name = ""`（`creators` と `contributors` の両方）、`edition = 0`、`printing = 0`、同じ（版、刷）の二項目、（1, 2）の後の（1, 1）、（2, 1）の後の（1, 3）、前の項目より前の `date`。
- 刷の番号が飛ぶ（（1, 1）の次に（1, 3））マニフェストがエラーにならないこと。
- `contributors` の未知のキーが G0301 になること。
- 表のすべての `Role` について、`roleWord` が互いに異なり、`marcRelator` が英小文字 3 字で互いに異なること。

### golem-eval

- `join(["a", "b"], "、")` が「a、b」、`join([], "、")` が空の文字列になること。
- `join([1], "、")`、`join("a", "、")`、`join(["a"], 1)` が G0201 になること。
- `meta.roles.editor`、`meta.roles.cover_designer`、`meta.roles.printer`、`meta.printing.number`、`meta.printing.year`、`meta.printing.date` が期待の値になること。`creators` と `contributors` の両方に `author` がある場合に `creators` が先に並ぶこと。
- `meta.publisher_person` が `publisher-person` の文字列になること。`publisher` のない本でも参照できること。
- 項目のない役割（`meta.roles.binder`）、`printings` のない本の `meta.printing`、`publisher-person` のない本の `meta.publisher_person` が G0202 になること。
- `@printings` が三項目の `printings` から三つの段落を作り、横組みの段落の文字列が上の例の三行と一致すること。版 1 が「初版」、版 2 が「第2版」になること。
- 縦組みで、年が「二〇二六」、月と日と刷が `[numbers]` の既定の表記になること（IR の `Number` と `style` で確かめる）。
- `language = "en"` の本と、`printings` のない本の `@printings` が G0276 になり、何も組まないこと。
- `@printings` に引数を書いた場合が、ほかのブロックコマンドと同じ引数の誤りになること。

### golem-epub、golem-pdf、golem-driver

- パッケージ文書の golden テストに、`contributors` の `editor` が `dc:contributor` と `role` の `refines`（`edt`）で並ぶこと、`printer` と `binder` が `creators` と `contributors` のどちらにあっても書かれないこと、`printings` と `publisher-person` が何も書かれないこと、`publisher` が今のとおり `dc:publisher` に書かれることを加える。
- `creators` の `translator` が `trl` の `refines` になること（符号への写しの確認）。
- `contributors` のある本の EPUB を epubcheck で検査し、エラーと警告がないこと。
- 出力インテントを指定した PDF の XMP に `dc:contributor` の `rdf:Bag` が入り、`printer` と `binder` の名前と `publisher-person` が入らないこと。書く項目がなければ要素を書かないこと。
- 語に書き換えた fixture の `manifest.toml` で、golem-driver の既存のテストが通ること。

### 決定性

- `contributors` と `printings` を持つ fixture を二回組み、PDF、HTML、プレーンテキストのバイト列が一致すること。

### 手で確かめること

- 縦組みと横組みの奥付を `@printings` と `meta.roles` で組んだ PDF を目で見て、日本語の奥付として読めること。
- `contributors` のある EPUB を Apple Books か Thorium で開き、書誌の表示が崩れないこと。
- 二つのマニュアルが、語に書き換えた `manifest.toml` で診断なしに組めること（`scripts/manual/build.sh`）。

## トレードオフ

`creators` と `contributors` を分けたので、書き手は役割のほかに主たる著作者かどうかを選ぶ。
一つの配列にして役割から `dc:creator` と `dc:contributor` を振り分ける案もあったが、`translator` のように本によって主にも従にもなる役割があり、Golem が決めると書き手の意図とずれる。
EPUB の区別をそのまま書き手に見せるほうが、写し方が一つに決まる。

役割を閉じた語彙にしたので、表にない役割（写真、監修など）は、語を足すまで書けない。
符号をそのまま書く今の方式なら MARC のすべての役割を書けるが、書き手が略語を読み解く負担のほうが大きいと判断した。
語の追加は表に一行足すだけで済む。

符号を語に置き換えるので、`role = "aut"` と書いた既存のプロジェクトは G0301 になる。
v1.0.0 の前の変更であり、メッセージが書き換える語を示すので、直す手間は一行ごとに一度で済む。

`date` と `printings` を独立にしたので、刷を重ねるときは `date` と `printings` の二箇所を書き換える。
`date` を最後の刷の日付から導く案は、`printings` を書かない本で `date` が要ることと、刷を増やさずに電子版だけを更新する場合に `date` を変えたいことから採らなかった。

`@printings` の書式を v0.1.0-rc3 では一つに固定するので、書式の違う本（「第1版第1刷」と書く本など）は、設定が入るまで `meta.printing` から一行ずつ書くことになる。

印刷所と製本所を出力のメタデータに書かないので、メタデータは全媒体で同一という媒体契約に、役割による例外が一つできる。
印刷所と製本所は紙の本の製造の記録であり、電子書籍と PDF の文書の書誌ではないと考えた。
例外は表の一列で決まり、媒体ごとの分岐にはしない（EPUB と XMP で同じ扱いにする）。

発行人を役割の語ではなく専用のキーにしたので、`meta.roles` で関係者を並べる奥付でも、発行人だけは `meta.publisher_person` で書く。
ふつう一冊に一人であること、出力の符号がないこと、`publisher` と対で読めることを、書き方の一貫性より優先した。
発行人が二人いる本は、一つの文字列に「、」などで並べて書く。

`join` は奥付のための関数だが、式の言語の一般の関数として加える。
ほかの配列（`meta.creators` など）にも使え、式の言語の型の規則も増やさない。

## ドキュメント

- docs/specifications.md：「メタデータ」の節の例と、役割を MARC relator の符号で書くという文を、語の表に置き換える。`contributors`、`printings`、`publisher-person`、検査、EPUB と XMP の写し方（印刷所、製本所、発行人を書かないこと）を書く。「本文からの参照」に `meta.publisher_person`、`meta.roles`、`meta.printing`、`meta.printings` を書く。
- docs/markup.md：式文脈の組み込み関数に `join` を、予約された名前空間 `meta` の説明に新しい値を、ブロックコマンドに `@printings` を加える。
- docs/diagnostics.md：G0301 の意味に役割、名前、刷の検査と、符号を書いた場合の案内を加える。G0276 の節を加える。G0201 と G0202 の例に `join` と `meta.roles` を加える。
- docs/roadmap.md：v0.1.0-rc3 の「奥付の関係者と刷」の項目を消す。v1.0.0 の「発行の履歴の書式」は残す。
- ユーザー向けのマニュアル：第 4 章（`chapters/04-manifest.gm`）と付録 B（`appendices/b-manifest.gm`）の `role` の説明と例を語に直し、`contributors`、`printings`、`publisher-person` を書く。第 3 章と付録 A に `join` と `@printings` を、付録 E に G0276 を書く。付録 H の rc3 の項目を消す。奥付の作り方の例を第 4 章に置く。
- 二つのマニュアルの `manifest.toml` と、golem-driver の fixture の `manifest.toml` の `role` を語に直す。
- 開発者向けのマニュアル：メタデータの写し方を述べた箇所があれば、`dc:contributor` と役割の表を加える。
- [golem-epub ADR 0001](../golem-epub/adr/0001-epub-packaging.md) のステータスの行を「採択→`dc:contributor` と役割の写し方は ADR 0033」とする。
- [golem-eval ADR 0001](../golem-eval/adr/0001-expression-language-and-numerics.md) のステータスの行を「採択→組み込み関数の `join` は ADR 0033」とする。

## 参考文献

- MARC Code List for Relators, Library of Congress. https://www.loc.gov/marc/relators/relaterm.html （表の符号と、`bnd` と `bdd` の違いを確かめた）
- EPUB 3.3, W3C Recommendation. https://www.w3.org/TR/epub-33/ （`dc:creator`、`dc:contributor`、`refines` の `role` と `file-as`）
- XMP Specification Part 1, Adobe. Dublin Core 名前空間の `dc:contributor`
