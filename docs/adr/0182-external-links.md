# ADR 0182: 外部の URL へのリンクと、PDF のリンクの注釈

ステータス: 採択→散文スロットが二つ以上の `[link]` の G02038 は [ADR 0211](0211-record-what-implementations-decided-found-by-the-review-of-2026-11-08.md)

## 文脈

[docs/roadmap.md](../roadmap.md) の v0.1.0-rc4 の PDF の節に「PDF のリンク」がある。
原稿に外部の URL へのリンクを書く記法がなく、PDF にリンクの注釈を書かない、という項目である。
v1.0.0 の「PDF のしおりと文書の中のリンク」は、相互参照、目次、索引、脚注の印を PDF のリンクにする項目で、「PDF のリンク」で作るリンクの注釈の仕組みを使うと書いている。
この ADR は外部の URL へのリンクだけを扱うが、注釈の仕組みは v1.0.0 の文書の中のリンクと共有できる形にする。

### 今の振る舞い

`~/.local/bin/golem`（0.1.0-rc3）で、蟹工船の fixture（縦組み）の写しの本文を次の一段落に置き換えて組み、確かめた（2026-11-06）。

```
「おい地獄さ[ruby: 行 | え]ぐんだで！」——漁夫は[style url: https://example.com/kani]を見た。
```

- PDF には `/Annots`、`/Link`、`/URI` のどれもない（`grep -c` で 0 件）。URL は文字スタイル `url` で組んだ文字にすぎず、クリックできない。
- HTML は `<span class="cs-url">https://example.com/kani</span>` になる。リンクにはならない。
- プレーンテキストは URL の文字をそのまま書く。

URL を組む手段は、組み込みの文字スタイル `url` だけである（[golem-doc ADR 0005](../golem-doc/adr/0005-bibliography-fields.md)）。
`url` は改行の位置を URL 向けに変える（[golem-layout ADR 0018](../golem-layout/adr/0018-url-line-breaks.md)）が、リンクを作らない。
二つのマニュアルは、脚注に `[style url: ...]` を 199 か所書いている（`rg -c` で数えた）。
この URL も、PDF ではクリックできない。

参考文献の URL は、出力によって扱いが違う。
HTML と EPUB は、scheme が `http` か `https` の URL を `<a class="cs-url" href="URL">` にし、ほかの scheme の URL をリンクにしない（[`Html.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-html/src/Golem/Html.hs#L477-L482)）。
`javascript:` のような URL をリンクにしないためである（[golem-doc ADR 0005](../golem-doc/adr/0005-bibliography-fields.md)）。
PDF は、URL を文字スタイル `url` の文字にするだけである（[`Flow.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L881)）。

### URL を引数に書くときの問題

命令文脈の `:` は散文スロットの始まりである（[docs/markup.md](../markup.md) の「命令文脈」）。
そのため、URL を引用符で囲まずに引数に書くと、`https` の後の `:` で引数が終わる。
`[link https://example.com/: 例]` を `golem inspect --as ast` で読むと、位置引数は語 `https` だけになり、散文スロットは `//example.com/: 例` になった（今は `link` がないので、評価で G02022 の未知のコマンドになる）。
URL を引数に書くなら、文字列リテラル（`"..."`）にするしかない。

### PDF/X-4 の自前の検査

`Golem.Pdf.X4.verify` は、PDF のどこかに `URI` の名前があれば、PDF/X-4 の要件「JavaScript と外部への参照」に反するとして報告する（[`X4.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-pdf/src/Golem/Pdf/X4.hs#L179)、[golem-pdf ADR 0012](../golem-pdf/adr/0012-x4-forbidden-names-in-found-order.md)）。
`golem preflight` の G09014 はこの検査の結果である。
このまま URI のアクションを書くと、`[color] intent` を持ち、リンクを含む本は、すべて G09014 になる。

`URI` を禁止の名前に入れた根拠は、[golem-pdf ADR 0002](../golem-pdf/adr/0002-pdf-x-4.md) の「外部への参照を含めない」の一文である。
その ADR は、規格（ISO 15930-7:2010）の本文を参照せずに要件を書いたと断っている。
PDF/X の「外部への参照」が、印刷に使う内容をファイルの外から読むこと（外部のストリームなど）を指すのか、URI のアクションも含むのかは、本文で確かめていない。

一方、PDF/A-2 は URI のアクションを持つリンクの注釈を許す。
[ADR 0183](0183-tagged-pdf-and-pdf-a.md) の調べで、出力インテントのある蟹工船の PDF に、`/F 4`（印刷のフラグ）を持ち、外観のストリーム（`/AP`）を持たないリンクの注釈を足し、veraPDF 1.30 で PDF/A-2b と PDF/A-2u に適合すると判定されることを確かめた。
`/F` がないと規則 6.3.2-1 に、`/F 2`（隠す）にすると規則 6.3.2-2 に反する。
`/AP` は、veraPDF の規則 6.3.3-1 がリンクの注釈を除外している。

### HTML の入れ子のリンク

HTML は、相互参照、脚注の印、引用の印を、すでに `<a>` にしている（[`Html.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-html/src/Golem/Html.hs#L625-L643)）。
リンクの中にこれらを置くと、`<a>` の中に `<a>` ができる。
HTML の `a` 要素は、中に対話的な内容（ほかの `a` 要素）を持てない。

### 行をまたぐ範囲の矩形

行の中の範囲に矩形を描く仕組みは、すでにある。
行の中のコードの背景（[golem-driver ADR 0029](../golem-driver/adr/0029-inline-code-background.md)）は、行ごとに、同じ見た目の箱の連なりを一つの矩形にする（[`Draw.hs` の `codeBackgrounds`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Draw.hs#L487-L511)）。
縦組みでは、行の中心線から字の大きさの半分ずつの幅を持つ縦長の矩形になる。
行をまたぐ範囲は、行ごとの矩形に分かれる。
リンクの注釈の矩形も、同じ形で求められる。

## 実装すること

### 記法

インラインのコマンド `[link]` を加える（「メンテナーが決めること」の 1）。

```
[link "https://www.w3.org/TR/jlreq/": 日本語組版処理の要件]
[link "https://www.w3.org/TR/jlreq/"]
```

- 最初の位置引数に URL を文字列で書く。文字列リテラルのほか、文字列を値に持つ式文脈（`[link [= values.site]: ...]`）も書ける。
- 散文スロットに書いた内容が、リンクの文字になる。
- 散文スロットを省くと、URL そのものを文字スタイル `url` で組んだ文字がリンクの文字になる（「メンテナーが決めること」の 2）。`[link "U"]` は、意味論の IR では `[link "U": [style url: U]]` と同じになる。
- 位置引数は URL の一つだけで、キーワード引数は取らない。
- URL がない、位置引数が二つ以上ある、キーワード引数を書いた、URL が文字列でない場合は、G02124（`link の引数が誤っています`）とし、コマンドを実行しない。URL の位置引数が語で、散文スロットが `//` で始まるときは、メッセージに `URL は "https://..." のように引用符で囲みます` を添える。`[link https://...: ...]` と書いた誤りを、そのまま知らせるためである。
- `link` は、プラグインが上書きできない組み込みのコマンドとする。`ref-number` や `note` と同じく、v1.0.0 で PDF のリンクになる要素だからである。
- リンクは見た目を変えない。色、下線、枠を付けない。見た目を変えたいときは、`[link "U": [style 名前: ...]]` のように文字スタイルを入れ子にする。

### URL の検査

URL は、評価のときに次の順に検査する（「メンテナーが決めること」の 3 と 7）。
どれか一つに当たれば、その diagnostic を出し、リンクを作らない。

1. URL が RFC 3986 の絶対 URI（scheme、`//`、ホスト、パス、クエリ、フラグメント）の形でなければ G02125（`URL の形が誤っています: <URL>`）とする。空白と制御文字、`%` の後に 16 進の数字が二つ続かない並び、空のホストもこれに当たる。ただし、パス、クエリ、フラグメントの ASCII でない文字は、RFC 3987 の IRI として許す。
2. scheme が `http` か `https`（大文字と小文字を区別しない）でなければ G02126（`リンクにできる URL は http と https だけです: <URL>`）とする。
3. ホストに ASCII でない文字があれば G02127（`URL のホストは ASCII で書きます: <URL>`）とする。国際化ドメイン名は、利用者が Punycode（`xn--`）で書く。

検査は、評価器の `[link]` と、`Golem.Doc.Validate` の両方で行う。
プラグインと Emet の関数が返したリンクも、同じ規則で拒む（プラグインの出力なら G06009、関数の出力なら E06104 になる）。

diagnostic のコードの番号は、今の最大の G02123 に続けて仮に置いた。
同じ時期の ADR とコードの番号が重なるときは、採択のときに番号を振り直す。

### 意味論 IR とプラグインの ABI

意味論 IR のインラインに、リンクのコンストラクタを加える（[`IR.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-doc/src/Golem/Doc/IR.hs#L239-L260)）。

```haskell
  | -- | a link to an external URL, as written (docs/adr ADR 0182)
    Link !SrcSpan !Text [InlineF r]
```

- CDDL には `[20, span, uri: tstr, inlines]` を加える（[`golem-doc.cddl`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-doc/schema/golem-doc.cddl#L52-L69)）。
- IR は、原稿に書いた URL をそのまま持つ。ASCII への符号化は、出力ごとに行う。
- ルビの親文字（`inlines-no-ruby`）の中にも置ける。文字スタイルと同じ扱いである。
- `Golem.Doc.Validate` に二つの不変条件を加える。URL が上の検査を通ること、リンクの中に、リンク、相互参照（`Ref`）、脚注（`Note`）、傍注（`Sidenote`）、引用（`Cite`）がないことである。
- 評価器は、リンクの中にこれらを書いた原稿を G02128（`リンクの中にリンクになる要素は置けません: <要素>`）とする（「メンテナーが決めること」の 6）。どれも HTML で `<a>` になり、v1.0.0 では PDF のリンクにもなる要素であり、入れ子のリンクは HTML では書けないためである。
- 目次の項目、柱、`[ref-title]` で写した題、EPUB のナビゲーション文書では、リンクを外し、中の文字だけを写す。写しの位置にリンクを残すと、v1.0.0 で目次の項目そのものがリンクになるときに入れ子になるからである。索引の印を写しから落とす扱い（[docs/adr/0145](0145-title-copies-drop-anchor-inlines.md)）とは違い、文字は残す。
- 正規表現スタイルは、文字スタイルと同じく、リンクの中にも当てる。

プラグインの SDK（`plugins/golem-plugin-sdk` の `Inline`、[`ir.rs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/plugins/golem-plugin-sdk/src/ir.rs#L49-L84)）にも、同じ形の `Link { span, uri, body }` を加え、CBOR の読み書きを足す。

プラグインとの ABI のバージョンは、8 のままとする。
v0.1.0-rc3 の ABI は 7 で、8 はまだどのリリースにも含まれていないからである（[docs/adr/0052](0052-plugin-abi-version-bump-rule.md)）。

Emet の組み込みの型 `Inline` にも、コンストラクタ `Link String (List Inline)` を加える（[`Builtins.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-emet/src/Golem/Emet/Builtins.hs#L55-L72)）。
Emet のパターンマッチは網羅していなければならないので、`Inline` のすべてのコンストラクタを並べた関数は、`Link` の場合を書き足すまで E03100 になる。
Emet は v0.1.0-rc3 の仕様書になく、リリースに含まれていないので、配った関数を壊すことはない。
リポジトリの中の `.emet`（fixture と見本）は、同じプルリクエストで直す。

### PDF の注釈の矩形（golem-layout と golem-driver）

リンクの範囲は、行分割の箱の見た目（`Look`）に持たせる。

- `Look` に `lkLink :: Maybe LinkTarget` を加え、`data LinkTarget = LinkUri Text` とする。リンクの中の箱の見た目は、`lkUrl` と同じく、インラインをたどるときに決める（[`Fonts.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Fonts.hs#L437)）。Knuth と Plass の行分割は、この欄を読まない。
- 行ごとに、同じ `lkLink` を持つ箱の連なり（あいだのグルーを含む）を一つの範囲とし、その範囲の行の面を矩形にする。求め方は `codeBackgrounds` と同じで、横組みでは範囲の始まりから終わりまでの、字の大きさの高さの矩形、縦組みでは行の中心線から字の大きさの半分ずつの幅を持つ縦長の矩形である。
- 行をまたぐリンクは、行ごとの矩形に分かれ、矩形ごとに一つの注釈になる。段とページをまたいでも同じである。分綴したときのハイフンは、行末の矩形に含める。
- ルビの読みは、矩形に含めない。矩形は親文字の行の面である。
- 回した図版のキャプション（[golem-driver ADR 0034](../golem-driver/adr/0034-fit-figures-to-column.md)）の中のリンクは、`turnRect` で回した後のページの上の矩形にする。
- 一つのページの注釈は、描いた順に並べる。同じ入力からは同じ並びになる。

`LinkTarget` を型にしておくのは、v1.0.0 の文書の中のリンクで、行先（`LinkDest`）を足すだけで矩形の求め方を共有するためである。
相互参照、脚注の印、目次の項目は、それぞれの箱にこの欄を持たせればよい。

### URL とリンクの文字の改行（golem-layout）

紙面に組んだ URL は、どこで行を分けても、行末にハイフンを描かない（「メンテナーが決めること」の 8）。
行末のハイフンが分綴の印なのか URL の一部なのか、読み手が見分けられないからである。
この禁止に例外は置かない。

URL の文字は、文字スタイル `url` で組んだ文字である。
散文スロットを省いた `[link "U"]` の文字、参考文献の URL、本文の `[style url: ...]` がこれに当たる。
これらの改行は、今の規則（[golem-layout ADR 0018](../golem-layout/adr/0018-url-line-breaks.md)）のまま変えない。
今のコードで確かめた規則は次のとおりである。

- `url` の文字は、`code` と同じく `breaksAsCode` の経路で箱に分け、パターンの分綴をかけない（[`textPiecesAt`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-layout/src/Golem/Layout/Japanese.hs#L365-L367)、[`breaksAsCode`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-layout/src/Golem/Layout/Japanese.hs#L705-L709)）。
- 行を分けてよいのは、空白と、`/.@!_|;>]),?&'+=#:` のどれかの字の後である（[`urlParts` と `urlBreakAfter`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-layout/src/Golem/Layout/Japanese.hs#L676-L703)）。`/` の並びと `https:` の後の `//` の中では分けない。罰点は `/` の後が 0、ほかの字の後が 100 である。
- `-` の前と後、`%` の後では分けない。
- 分けた位置にハイフンを描かない。描くのは `PatternHyphen` の罰点で分けた行だけで（[`drawLineAt`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Draw.hs#L656-L661)）、`url` の箱のあいだの罰点は `NoHyphen` である。

`code` の文字が空白と `/` の後でだけ分かれるのに対し、`url` の文字は上の字の後でも分かれる。
URL の文字は、`/` などの後でハイフンを描かずに分けてよい、とする。
分けない案は、長い URL の前の行が大きく間延びする問題（[golem-layout ADR 0018](../golem-layout/adr/0018-url-line-breaks.md) の文脈）を戻す。

散文スロットに書いたリンクの文字は、URL の文字ではないが、URL に似た文字列（`example.com` など）を書くことがある。
そのため、リンクの中（`lkLink` が `Nothing` でない見た目）の欧文の語は、語の中で行を分けない。

- パターンの分綴をしない。
- 原稿に書いたハイフンとダッシュの後でも分けない（今の `wordItems` は、`-‐‑–—` を含む語を、その後ろで分ける。[`wordItems`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-layout/src/Golem/Layout/Japanese.hs#L749-L774)）。
- 空白、和文の字のあいだ、リンクの中に入れ子にした `url` の文字の上の位置では、今のとおり分ける。

`wordItems` は、見た目の `lkLink` を読み、リンクの中の語を一つの箱にする。
Knuth と Plass の行分割は、今のとおり `Look` を読まない。

### PDF の書き方（golem-pdf）

- `Page` に `pageAnnots :: [Annotation]` を加える。`data Annotation = LinkAnnotation Rect LinkAction`、`data LinkAction = UriAction Text` とする。v1.0.0 は `LinkAction` に文書の中の行先へのアクションを足す。
- 注釈のあるページの辞書に `/Annots` を書き、注釈ごとに次の辞書を間接オブジェクトとして書く。

  ```
  << /A << /S /URI /URI (https://example.com/) >> /Border [0 0 0] /F 4 /Rect [x1 y1 x2 y2] /Subtype /Link /Type /Annot >>
  ```

- `/Border [0 0 0]` で枠を描かない。`/AP` は書かない。紙の上でも画面の上でも、リンクは見た目を変えない。
- `/F 4`（印刷のフラグ）を書く。PDF/A-2 が要るフラグである（[ADR 0183](0183-tagged-pdf-and-pdf-a.md)）。外観を持たないので、印刷される内容はない。
- URI の文字列は 7 ビットの ASCII で書く（ISO 32000-1 の 12.6.4.7。記憶によるもので、本文では確かめていない）。ASCII でない文字は UTF-8 のバイトの `%XX` に符号化する。すでに `%XX` で書かれた部分は、そのままにする。
- オブジェクトの番号は、今の並び（カタログ、ページの木、ページ、フォント、画像など）を崩さない位置に、決まった順で振る。同じ入力から同じバイト列になる（[golem-pdf ADR 0001](../golem-pdf/adr/0001-deterministic-pdf-writer.md)）。
- タグ付き PDF（[ADR 0183](0183-tagged-pdf-and-pdf-a.md)）は、この辞書に代替の文字の `/Contents` と構造の木への `/StructParent` を、注釈のあるページに `/Tabs /S` を加え、リンクを構造の要素 `Link` にする。この ADR の実装では書かず、[ADR 0183](0183-tagged-pdf-and-pdf-a.md) の実装で加える。

参考文献の URL も、PDF でリンクにする。
`EntryUrl` の URL が上の検査を通れば、`Link` で包む。
通らなければ、今のとおり文字スタイル `url` の文字だけにする（HTML と EPUB の今の扱いと同じ）。
本文の `[style url: ...]` は、リンクにしない。
文字スタイルは見た目の指定であり、リンクにしたい URL は `[link]` で書く。

### PDF/X-4

`[color] intent` のある本（PDF/X-4 の PDF）にも、リンクの注釈を書く（「メンテナーが決めること」の 4）。

- `Golem.Pdf.X4.verify` は、ページの `/Annots` にあるリンクの注釈の `/A` が、`/S /URI` のアクションである場合に限り、その中の `URI` を禁止の名前として数えない。ほかの位置の `URI` と、`JavaScript`、`JS`、`Launch`、`GoToR` は、今のとおり禁止する。
- 仕様書の G09014 の説明（禁止の名前の一覧）を、この例外を含めて書き直す。
- 実装に入る前に、ISO 15930-7:2010 の本文で、注釈とアクションについての規定を確かめる。[golem-pdf ADR 0002](../golem-pdf/adr/0002-pdf-x-4.md) が実装の前に本文と照合するとした手順を、注釈について行うものである。リンクの注釈か URI のアクションを禁じる規定があれば、この節を改める ADR を作る。

### HTML と EPUB

- リンクを `<a href="URL">…</a>` にする。中身は、今のインラインの出力のままである。散文スロットを省いたリンクは、`<a href="URL"><span class="cs-url">URL</span></a>` になる。
- `href` には、原稿に書いた URL を XML の文字参照で書く。ASCII でない文字は符号化しない。HTML と EPUB の `href` は IRI を受け付けるからである。
- `target` と `rel` は書かない。

### プレーンテキスト

散文スロットを書いたリンクは、`表示の文字（URL）` の形で書く（「メンテナーが決めること」の 5）。
ルビの `対象（読み）` と同じ全角の括弧を使う。
表示の文字が URL と同じ文字列なら、括弧を付けない。
散文スロットを省いたリンクは、URL だけを書く。

### LSP

- 新しいコード（G02124 から G02128）は評価器が出すので、LSP は今の仕組みのまま diagnostics に出す。
- コマンドの名前の補完は、組み込みのコマンドの一覧から作るので（[`Features.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-lsp/src/Golem/Lsp/Features.hs#L528)）、`link` は一覧に加えれば補完に出る。
- semantic tokens は、URL を今の文字列リテラルの型で色付けする。変える必要はない。

### 文書

- [docs/markup.md](../markup.md) のインラインの節に「リンク」を加え、文字スタイル `url` の項から `[link]` を案内する。
- [docs/specifications.md](../specifications.md) に、リンクの記法、検査、IR と CDDL、PDF の注釈、HTML と EPUB とプレーンテキストの出力、G09014 の例外を書く。改行の規則の節に、URL の文字を分綴しないことと、リンクの中の欧文の語を語の中で分けないことを書く。
- [docs/diagnostics.md](../diagnostics.md) に G02124 から G02128 を加える。
- [docs/roadmap.md](../roadmap.md) から「PDF のリンク」を消す。
- マニュアルの `[style url: ...]` を `[link]` に書き換えるかは、マニュアルの方針に従い、マニュアルのプルリクエストで決める。この ADR では書き換えない。

## 実装しないこと

- 相互参照、目次、索引、脚注の印のリンクと、PDF のしおり。v1.0.0 の「PDF のしおりと文書の中のリンク」で扱う。
- ラベルを指す `[link]`（文書の中のリンクを利用者が書く記法）。v1.0.0 の項目は既存の要素をリンクにするもので、この記法を要しない。
- `http` と `https` のほかの scheme（`mailto`、`tel`、`ftp`、`file` など）と、相対 URL。
- リンクの見た目の既定（色、下線、枠）。
- 本文の URL の文字列や `[style url: ...]` を、自動でリンクにすること。
- 国際化ドメイン名を Punycode に変えること（IDNA と UTS #46 の対応表の実装が要る）。
- 注釈の `/QuadPoints`。行ごとに注釈を分けるので要らない。`/QuadPoints` を読まない閲覧ソフトは `/Rect` を使うので、複数行を一つの `/Rect` で覆うと、行のあいだの余白までリンクになる。
- 注釈の外観のストリーム（`/AP`）。
- 注釈の `/Contents`（代替の文字）と、リンクの構造の要素。タグ付き PDF の [ADR 0183](0183-tagged-pdf-and-pdf-a.md) で扱う。
- 本文に地の文として書いた URL の文字列を見分けて、分綴を止めること。Golem が URL と知るのは、文字スタイル `url` の文字だけである。
- URL の先が存在するかの確かめ。ネットワークに触れると、出力と diagnostics が入力だけで決まらなくなる。
- LSP の `textDocument/documentLink`。

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。

golem-parser と golem-eval のテストでは、次のことを確かめる。

- `[link "https://example.com/": 例]` が `Link` になり、中身が `例` であること。
- `[link "https://example.com/"]` が `Link` になり、中身が文字スタイル `url` の `https://example.com/` であること。
- 式文脈の文字列（`[link [= "https://example.com/"]: 例]`）も受け付けること。
- `[link https://example.com/: 例]` が G02124 になり、メッセージに引用符の案内が付くこと。URL がない、位置引数が二つ、キーワード引数がある、URL が数である場合も G02124 になること。
- 空白を含む URL、`%` の後が 16 進の二桁でない URL、ホストのない `https:///a` が G02125 になること。
- `javascript:alert(1)`、`mailto:a@example.com`、scheme のない `example.com` が G02126 になること。`HTTPS://EXAMPLE.COM/` は通ること。
- `https://例え.jp/` が G02127 になり、`https://ja.wikipedia.org/wiki/組版` は通ること。
- リンクの中のリンク、`[ref-number]`、`[note]`、`[sidenote]`、`[cite]` が G02128 になること。リンクの中の `[ruby]`、`[style]`、`[index]` は通ること。
- プラグインに `link` を上書きさせると、上書きできないコマンドの今のエラーになること。

golem-doc と golem-plugin のテストでは、次のことを確かめる。

- `Link` が CBOR の `[20, span, uri, inlines]` と往復すること。CDDL の検査が新しい形を受け付けること。プラグインの SDK の `Inline::Link` も、同じバイト列と往復すること。
- `Golem.Doc.Validate` が、検査を通らない URL と入れ子のリンクを拒むこと。
- プラグインの出力の不正なリンクが G06009 になり、Emet の関数の出力の不正なリンクが E06104 になること。

golem-layout と golem-driver のテストでは、次のことを確かめる。

- 横組みで一行に収まるリンクが、一つの注釈になり、矩形がリンクの文字の始まりから終わりまでであること。
- 行をまたぐリンクが、行ごとに一つずつの注釈になり、矩形が行ごとの範囲に一致すること。段とページをまたぐ場合も同じであること。
- 縦組みのリンクの矩形が、行の中心線から字の大きさの半分ずつの幅の縦長の矩形になること。
- ルビ付きの親文字を含むリンクの矩形が、親文字の行の面であること。
- 回したキャプションの中のリンクの矩形が、回した後のページの上の矩形であること。
- 行長より長い `[link "https://example.com/a-very-long-path/with-hyphens/"]` が、`/` などの後で分かれ、どの行末にもハイフンを描かず、`-` の前と後で分かれないこと。今の `url` の規則の回帰テストである。
- `[link "https://example.com/": hyphenation porte-monnaie]` の中の `hyphenation` と `porte-monnaie` が、狭い行長でも語の中で分かれないこと。リンクの外の同じ語は、今のとおりパターンと書いたハイフンの後で分かれること。今の実装ではリンクの中の語も分かれるので失敗する。
- 参考文献の `http` と `https` の URL が注釈になり、ほかの scheme の URL が注釈にならないこと。
- 本文の `[style url: ...]` が注釈にならないこと。
- リンクを含む本の PDF が、決定性の検査（同じ入力から同じバイト列）を通ること。リンクのない本の PDF のバイト列は変わらないこと。

golem-pdf のテストでは、次のことを確かめる。

- 注釈の辞書が上の形（`/Border [0 0 0]`、`/F 4`、`/S /URI`、`/AP` なし）で書かれ、ページの `/Annots` から参照されること。
- ASCII でない文字を含む URL が、UTF-8 の `%XX` で書かれ、すでにある `%XX` が二重に符号化されないこと。
- 出力の PDF が `qpdf --check` を通ること。
- `X4.verify` が、リンクの注釈の URI のアクションを報告せず、ほかの位置の `URI`（たとえばカタログの `/URI`）を今のとおり報告すること。

golem-html、golem-epub、golem-text のテストでは、次のことを確かめる。

- HTML と EPUB で `<a href="URL">` になり、散文スロットを省いたリンクが `<a href="URL"><span class="cs-url">URL</span></a>` になること。`href` の `&` が `&amp;` になること。
- プレーンテキストで `例（https://example.com/）` になり、表示の文字が URL と同じなら `https://example.com/` だけになること。
- 目次、柱、`[ref-title]` の写しと EPUB のナビゲーション文書に、`<a>` の入れ子と注釈ができないこと。

手で確かめることとして、リンクを含む横組みと縦組みの PDF を、Acrobat Reader、macOS のプレビュー、Chrome の PDF ビューアで開き、リンクの矩形をクリックして URL が開くことを確かめる。

## トレードオフ

URL を引用符で囲む書き方は、`[style url: ...]` より文字が多い。
その代わり、URL の `:`、`|`、`]` が命令文脈の区切りと衝突しない。
囲み忘れた書き方は G02124 の案内で直せる。

リンクは見た目を変えないので、紙では、どこがリンクだったかは分からない。
画面で読む PDF でも、リンクの場所は、マウスを重ねたときの指の形でしか分からない。
印刷を主とする本では、色や下線を既定にすると紙面に不要な装飾が残るので、見た目を変えたい本は文字スタイルで指定する。

行をまたぐリンクは、行の数だけ注釈になる。
支援技術は、一つのリンクを複数のリンクとして読み上げることがある（推測であり、確かめていない）。
一つのリンクとしてまとめるのは、タグ付き PDF の構造（`Link` の構造の要素が複数の注釈を持つ形）の仕事であり、[ADR 0183](0183-tagged-pdf-and-pdf-a.md) で扱う。

リンクの中の欧文の語を語の中で分けないので、狭い行長で長い語をリンクにすると、その行は分綴できる場合より間延びする。
URL に似た表示の文字にハイフンが付く誤読を、どの場合にも起こさないほうを選んだ。
地の文に書いた URL の文字列は、Golem には URL と分からないので、今のとおり分綴されうる。
URL は `[link]` か `[style url: ...]` で書く、とマニュアルに書く。

PDF/X-4 の PDF にリンクの注釈を書くことは、規格の本文で確かめていない。
規格がこれを禁じていれば、Golem の PDF/X-4 の PDF は、商用のプリフライトで初めて誤りになる。
実装の前に本文を確かめる手順を置いたのは、この危険のためである。

プレーンテキストでは、表示の文字と URL の両方を書くので、文が長くなる。
転載したときに URL を失わないためである。

`link` を組み込みのコマンドの名前にすると、同じ名前のコマンドを持つプラグインは、その名前を使えなくなる。
今のプラグインの宣言の規則でどうなるか（エラーか、プラグインのコマンドが届かないか）は、この ADR を書くときに確かめていない。
リポジトリの見本のプラグイン（`plugins/`）のコマンドに、`link` という名前のものはない（`rg` で確かめた）。

## 決めたことの記録

- **ロードマップの項目**（2026-10-16、ロードマップ）：v0.1.0-rc4 の PDF の節に「PDF のリンク」を置いた。外部の URL の記法は、どの一覧にもなかったとした。
- **文書の中のリンクとの共有**（2026-10-17、ロードマップ）：v1.0.0 の「PDF のしおりと文書の中のリンク」が、この項目で作るリンクの注釈の仕組みを使うとした。
- **URL を分綴しないこと**（2026-11-07、メンテナー）：紙面の URL はハイフネーションしない。行末のハイフンが紛らわしいからである。どこで行を分けてよいかは 8 で決める。
- **ほかの項目**（2026-11-07、メンテナー）：「メンテナーが決めること」の 1 から 7 を推奨のとおりとした。
- **URL とリンクの文字の改行の位置**（2026-11-07、メンテナー）：問題ないとした。「メンテナーが決めること」の 8 を推奨のとおりとした。

## メンテナーが決めること

すべて決めた（「決めたことの記録」）。
8 は、URL を分綴しないという決定を受けて加えた。

1. **記法**：決めた。`[link "URL": 表示の文字]` とする。
   退けた案は三つある。
   `[url: https://...]` のように URL を散文スロットに書く案は、マニュアルの `[style url: ...]` に近いが、散文スロットはインラインの要素の列であり、`[`、`]`、`|`、`%%`、`\` を記法として読む。URL を文字列として受け取れず、表示の文字も別に書けない。仕様書も、`url` に `[url: ...]` の別名はないとしている。
   `[link url="...": ...]` のようにキーワード引数にする案は、URL が必須の引数なのに書く量だけが増える。
   Markdown の `[文字](URL)` に似た新しい記法は、`[` が常にインラインの要素の始まりであるという今の規則を崩す。
2. **散文スロットを省いたとき**：決めた。URL そのものを文字スタイル `url` で組んだ文字をリンクの文字にする。脚注に URL だけを書く今のマニュアルの書き方を、`[link "URL"]` でそのまま書ける。散文スロットを必須にする案は、同じ URL を二度書かせるので退けた。
3. **許す scheme**：決めた。`http` と `https` だけにする。参考文献の URL を HTML でリンクにする条件（[golem-doc ADR 0005](../golem-doc/adr/0005-bibliography-fields.md)）とそろう。`mailto` を加える案は、RFC 6068 の形の検査が別に要り、紙の上では意味を持たないので、要る本が現れてから加える。scheme を問わない案は、`javascript:` のような URL をリンクにしうるので退けた。
4. **PDF/X-4 の PDF にもリンクを書くか**：決めた。書く。外観を持たないリンクの注釈は印刷に何も描かず、[ADR 0183](0183-tagged-pdf-and-pdf-a.md) の PDF/A-2 は出力インテントを要するので、PDF/X-4 の PDF でリンクを書かなければ、PDF/A の PDF からもリンクが消える。PDF/X-4 の PDF ではリンクを書かない案は、Golem の今の検査（`URI` の禁止）を変えずに済むが、その検査の根拠が規格の本文でないことは「文脈」に書いたとおりである。書くかどうかを設定で選ばせる案は、設定の欄を一つ増やすので、規格の本文で禁止が見つかってから考える。
5. **プレーンテキストの書き方**：決めた。`表示の文字（URL）` とし、表示の文字が URL と同じなら URL だけにする。表示の文字だけを書く案は、ブログなどへの転載で URL を失う。URL だけを書く案は、文の中の語が URL に置き換わり、文として読めなくなる。
6. **リンクの中に置けない要素**：決めた。リンク、相互参照、脚注、傍注、引用を、リンクの中に置けない（G02128）とする。中のリンクを出力で黙って外す案は、原稿に書いたものを出力が知らせずに変えるので退けた。
7. **ASCII でない文字を含む URL**：決めた。パス、クエリ、フラグメントの ASCII でない文字を許し、PDF では UTF-8 の `%XX` に符号化し、ホストだけは ASCII（Punycode）を求める。ASCII だけを許す案は、日本語の Wikipedia の URL のように、日本語のパスを持つ URL を利用者に符号化させ、原稿で読めなくする。ホストの国際化ドメイン名を Golem が Punycode に変える案は、UTS #46 の対応表の実装が要り、この項目の範囲を超える。
8. **URL とリンクの文字の改行の位置**：決めた。次の二つとする。
   文字スタイル `url` の文字は、今の規則（[golem-layout ADR 0018](../golem-layout/adr/0018-url-line-breaks.md)）のまま、空白と `/.@!_|;>]),?&'+=#:` の後でハイフンを描かずに分け、`-` の前後と `%` の後では分けない。
   散文スロットに書いたリンクの文字の欧文の語は、パターンでも書いたハイフンとダッシュの後でも、語の中で分けない。
   退けた案は三つある。
   URL をどこでも分けない案は、長い URL の前の行が大きく間延びする、[golem-layout ADR 0018](../golem-layout/adr/0018-url-line-breaks.md) が直した問題を戻す。
   `code` と同じく空白と `/` の後でだけ分ける案は、[golem-layout ADR 0018](../golem-layout/adr/0018-url-line-breaks.md) が足した位置を減らし、同じ間延びを増やす。
   リンクの文字を今のとおり分綴する案は、`example.com` のような URL に似た表示の文字に行末のハイフンが付き、URL の分綴と見分けられない。

## 参考文献

- ISO 32000-1:2008, *Document management: Portable document format, Part 1: PDF 1.7*, 12.5.3 Annotation Flags, 12.5.6.5 Link Annotations, 12.6.4.7 URI Actions. 節の番号と内容は、この ADR を書くときに本文で確かめていない。
- ISO 19005-2:2011（PDF/A-2）の 6.3.2 と 6.3.3。veraPDF の検証プロファイル（https://github.com/veraPDF/veraPDF-validation-profiles 、`fc5a92f`）の規則 6.3.2-1、6.3.2-2、6.3.3-1 の記述で読んだ。
- RFC 3986, *Uniform Resource Identifier (URI): Generic Syntax*. https://www.rfc-editor.org/rfc/rfc3986
- RFC 3987, *Internationalized Resource Identifiers (IRIs)*. https://www.rfc-editor.org/rfc/rfc3987
- RFC 6068, *The 'mailto' URI Scheme*. https://www.rfc-editor.org/rfc/rfc6068
- Unicode Technical Standard #46, *Unicode IDNA Compatibility Processing*. https://www.unicode.org/reports/tr46/
- WHATWG, *HTML Living Standard*, 4.5.1 The a element（内容のモデル）. https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-a-element
- veraPDF 1.30（nixpkgs の `verapdf` 1.30.2）。[ADR 0183](0183-tagged-pdf-and-pdf-a.md) の調べで使った。
- [golem-doc ADR 0005](../golem-doc/adr/0005-bibliography-fields.md)、[golem-layout ADR 0018](../golem-layout/adr/0018-url-line-breaks.md)、[golem-driver ADR 0029](../golem-driver/adr/0029-inline-code-background.md)、[golem-pdf ADR 0001](../golem-pdf/adr/0001-deterministic-pdf-writer.md)、[golem-pdf ADR 0002](../golem-pdf/adr/0002-pdf-x-4.md)、[golem-pdf ADR 0012](../golem-pdf/adr/0012-x4-forbidden-names-in-found-order.md)、[docs/adr/0052](0052-plugin-abi-version-bump-rule.md)、[docs/adr/0145](0145-title-copies-drop-anchor-inlines.md)
