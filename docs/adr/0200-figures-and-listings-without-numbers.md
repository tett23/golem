# ADR 0200: 番号を振らない図版とコードブロックを `@nonumber` で書けるようにする

ステータス: 採択→Emet と Rust の SDK の `nonumber` は [ADR 0211](0211-record-what-implementations-decided-found-by-the-review-of-2026-11-08.md)

## 文脈

使い手のマニュアルの「はじめに」に、本を作る仕事の流れがどう変わるかを示す図を置こうとした。
`manual/preface.gm` の宣言の段落の後に `@label` と `@figure` を置いて `scripts/manual/build.sh manual` で組むと、次のエラーで止まる。

```
preface.gm:48:1: error[G04004]: 章の外にある図版とコードには、章番号を使う番号を振れません。章は番号を持つ階層 1 の見出しから始まります
```

「はじめに」は `@nonumber` の階層 1 の見出しなので、その後は章の外になる。
使い手のマニュアルの図番号は既定の書式 `図{chapter}-{n}` で、章の番号を使う（[docs/specifications.md](../specifications.md) の `[figures]`）。
前付け、後書き、付録の扉の前のように、章の番号を持たない場所に図を置く手段が、今の Golem にはない。

### 今の振る舞い

図番号とリスト番号は、文書の組み立て（S1）の `numberDocs` が振る。
図版は例外なく図番号を一つ取り、キャプションを付けたコードブロックは例外なくリスト番号を一つ取る（[`numberDocs` の図版とコードブロック](https://github.com/tett23/golem/blob/89bbc5556e7f1a1368ffe4b27e492b38002e3496/modules/golem-assemble/src/Golem/Assemble.hs#L302-L311)）。
章の番号を持たない図版とコードブロックは、書式が `{chapter}` を含むときに G04004 になる（[G04004 の検査](https://github.com/tett23/golem/blob/89bbc5556e7f1a1368ffe4b27e492b38002e3496/modules/golem-assemble/src/Golem/Assemble.hs#L337-L343)）。
条件は [golem-doc ADR 0003](../golem-doc/adr/0003-document-diagnostic-codes.md) が定め、[golem-driver ADR 0023](../golem-driver/adr/0023-code-block-book-features.md) がコードブロックに広げた。

番号を振らない指定は、見出しにだけある。
評価の `applyAttr` は、`@nonumber` を見出しにだけ付け、ほかのブロックでは G02013 にする（[`applyAttr`](https://github.com/tett23/golem/blob/89bbc5556e7f1a1368ffe4b27e492b38002e3496/modules/golem-eval/src/Golem/Eval/File.hs#L1127-L1137)）。
`golem 0.1.0-rc3`（e261745e からビルドしたもの）で、`@nonumber` を `@figure` の前の行と、`@caption` を付けたコードブロックの前の行に書くと、どちらも `error[G02013]: @nonumber はこのブロックには付けられません` になることを確かめた。

番号を持たない図版を出力が描く準備は、すでにある。
PDF の `numberedTitle`、HTML と EPUB の `numberSpan`、プレーンテキストの `numbered` は、どれも番号を `Maybe` で受け取り、`Nothing` なら番号と区切りを書かない（[PDF](https://github.com/tett23/golem/blob/89bbc5556e7f1a1368ffe4b27e492b38002e3496/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L613-L614)、[HTML](https://github.com/tett23/golem/blob/89bbc5556e7f1a1368ffe4b27e492b38002e3496/modules/golem-html/src/Golem/Html.hs#L473-L475)、[テキスト](https://github.com/tett23/golem/blob/89bbc5556e7f1a1368ffe4b27e492b38002e3496/modules/golem-text/src/Golem/Text.hs#L147-L150)）。
番号は `bookFigures` と `bookListings` から引くので、そこに載らない図版とコードブロックは、番号なしで組まれる。
`[ref-number ...]` が番号を持たない要素を指せば、組み立ては G04005 を出す（[G04005](https://github.com/tett23/golem/blob/89bbc5556e7f1a1368ffe4b27e492b38002e3496/modules/golem-assemble/src/Golem/Assemble.hs#L598-L601)）。

ただし、番号もキャプションもない図版は、今は作れないので、出力の形が決まっていない。
HTML は空の `<figcaption></figcaption>` を書き、プレーンテキストは `［］` を書く。
PDF は、キャプションの行内要素が空ならキャプションの行を組まない。

### 表

表は番号を持たない（[docs/specifications.md](../specifications.md) の「目次と文書構造の参照」）。
G04004 にもならないので、この ADR の対象ではない。

## 実装すること

### `@nonumber` を図版とコードブロックに付けられるようにする

見出しと同じ `@nonumber` の属性を、図版（`@figure`）と、コードブロック（```` ``` ```` と `@listing`）にも付けられるようにする。

```
@label fig-workflow
@nonumber
@figure images/workflow.svg alt="…"
  本を作る仕事の流れの、これまでとこれから。
```

- `@nonumber` の図版は図番号を取らず、番号を消費しない。後の図版は、`@nonumber` の図版がないときと同じ番号になる。見出しの `@nonumber` と同じ規則である。
- `@nonumber` のコードブロックはリスト番号を取らず、番号を消費しない。
- 章の中でも外でも書ける。
- `@nonumber` の図版とコードブロックは、`{chapter}` を使う書式でも G04004 にならない。
- キャプションのないコードブロックは、もともと番号を持たない。そこに `@nonumber` を書いたら、新しいコード G02134 のエラーにする。メッセージは `キャプションのないコードブロックは番号を持たないので、@nonumber は要りません` とする。属性の順（`@caption` と `@nonumber` のどちらが先か）によらず、そのブロックの属性をすべて当てた後で判定する。位置は `@nonumber` の行である。
- 図版とコードブロックのほかのブロック（段落、リスト、表など）への `@nonumber` は、今のとおり G02013 である。

### 参照

- `@nonumber` の図版とコードブロックを `[ref-number ...]` で指したら、今の G04005 にする。docs/diagnostics.md の G04005 の「番号を持つのは、`@nonumber` のない見出し、図版、キャプションを付けたコードブロックである」を、「`@nonumber` のない見出し、`@nonumber` のない図版、`@nonumber` のない、キャプションを付けたコードブロック」に改める。
- `[ref-title ...]` と `[ref-page ...]` は、番号のある図版と同じく使える。題は、図版では代替テキスト、コードブロックではキャプションのままである。

### G04004 のメッセージ

G04004 の条件は変えない。
直し方の候補が増えるので、メッセージの後に `。番号を振らないなら @nonumber を付けます` を足す。
diagnostics.md の G04004 の「直し方」にも、`@nonumber` を足す。

### 意味論 IR と ABI

番号を振らないことは、見出しの `heading-attrs` の `nonumber` と同じく、意味論 IR に持たせる。

- CDDL（`modules/golem-doc/schema/golem-doc.cddl`）の `figure` と `code` の末尾に `nonumber: bool` を足す。Haskell の `Figure` に `figNoNumber`、`Code` に `codeNoNumber` を足し、CBOR の読み書きをそろえる（[CDDL](https://github.com/tett23/golem/blob/89bbc5556e7f1a1368ffe4b27e492b38002e3496/modules/golem-doc/schema/golem-doc.cddl#L39-L40)、[IR](https://github.com/tett23/golem/blob/89bbc5556e7f1a1368ffe4b27e492b38002e3496/modules/golem-doc/src/Golem/Doc/IR.hs#L203-L248)）。
- プラグインが返す図版とコードブロックも `nonumber` を持てる。`Golem.Doc.Validate` は、`nonumber` が真で `caption` が null のコードブロックを不変条件の違反にする。メッセージは G02134 と同じ文言にする。
- ABI のバージョンは [docs/adr/0052](0052-plugin-abi-version-bump-rule.md) の規則に従う。今の 8 がまだどのリリースにも含まれていなければ 8 のまま、含まれていれば 9 に上げる。

### 番号もキャプションもない図版の出力

`@nonumber` で、番号もキャプションもない図版が書けるようになる。

- PDF は今のとおり、キャプションの行を組まない。
- HTML と EPUB は、`<figcaption>` を書かない。
- プレーンテキストは、その図版の行を書かない（`［］` を書かない）。

番号がなくキャプションのある図版は、どの出力もキャプションだけを書く。
キャプションの前に「図」のような見出しの語は付けない。
番号のない見出しが、番号を書かずに題だけを書くのと同じである。

### LSP

golem-lsp は、評価と組み立ての diagnostic をそのまま出すので、G02134 と、文言を足した G04004 は、変更なしに届く。
`@nonumber` の補完と hover は、今も見出しのためのものがなく、この ADR でも足さない。
golem-lsp のテストに、`@nonumber` の図版の前後で、G04004 が出ないことと、`[ref-number]` が G04005 になることの二つを足す。

### 文書

- docs/markup.md の「ブロックへの属性」と「図版」と「コードブロック」の節に、`@nonumber` を書く。
- docs/specifications.md の「目次と文書構造の参照」の番号を持つ要素の文と、図番号とリスト番号の節を改める。
- docs/diagnostics.md に G02134 を足し、G04004、G04005、G02013 の説明を改める。
- 使い手のマニュアルの付録 A（記法の一覧）と、図版とコードブロックを説明する章に、`@nonumber` を足す。
- 実装の PR では、「はじめに」の図（`manual/images/workflow.svg`）を `@nonumber` で置く。

## 実装しないこと

- **`[ref-number]` の書式の不具合**：`[ref-number]` が `[figures]` と `[code]` の `number` の書式に従わず、`章の番号-番号` を返す問題（[docs/specifications.md](../specifications.md) の既知の不具合）は直さない。`@nonumber` の図版は `[ref-number]` で指せないので、この ADR の振る舞いはその不具合に左右されない。
- **章の外の図版に自動で番号を振らないこと**：「メンテナーが決めること」の案 A である。
- **キャプションの見出しの語**：番号のない図版のキャプションに「図」のような語を付ける設定は足さない。
- **表の番号**：表は番号を持たないままである。
- **`@nonumber` の補完と hover**：見出しの `@nonumber` にもないので、足さない。
- **章の外の図版の番号の別の書式**：前付けの図に「図 0-1」や「図 i」のような別の書式で番号を振る設定は足さない。

## テスト設計

先に書いて、失敗することを確かめてから実装する。

### 評価（golem-eval）

- `@nonumber` の後の `@figure` が、`figNoNumber = True` の図版になり、diagnostic を出さない。
- `@caption` と `@nonumber` を付けたコードブロックが、`codeNoNumber = True` になる。二つの属性の順を入れ替えても同じである。
- `@nonumber` を付けた `@listing` も同じである。
- キャプションのないコードブロックへの `@nonumber` が、`@nonumber` の行を指す G02134 になる。
- 段落と表への `@nonumber` が、今のとおり G02013 になる。

### 組み立て（golem-assemble）

- 書式が `{chapter}` を含むとき、章の外の `@nonumber` の図版とコードブロックが G04004 にならず、`bookFigures` と `bookListings` に載らない。
- 章の中で、`@nonumber` の図版を挟んだ前後の図版が、1 と 2 の番号を取る。リスト番号も同じである。
- `@nonumber` の図版を指す `[ref-number]` が G04005 になり、`[ref-title]` が代替テキストを返す。
- `@nonumber` のない章の外の図版は、今のとおり G04004 になり、メッセージが `@nonumber` の案内を含む。

### 意味論 IR とプラグイン（golem-doc、golem-plugin）

- `nonumber` を含む `figure` と `code` が、CBOR で往復して同じ値に戻る。
- `nonumber` が真で `caption` が null のコードブロックを返すプラグインの出力を、`Golem.Doc.Validate` が違反として報告する。
- `scripts/ci/abi-version.sh` が、ABI のバージョンの規則どおりに通る。

### 出力

- PDF：章の外の `@nonumber` の図版のキャプションが、番号と区切りなしで組まれる。番号もキャプションもない図版で、キャプションの行がない。golem-driver のゴールデンで固定する。
- HTML と EPUB：番号のない図版の `<figcaption>` に `<span class="number">` がない。番号もキャプションもない図版に `<figcaption>` がない。
- プレーンテキスト：番号のない図版が `［キャプション］` になり、番号もキャプションもない図版の行がない。

### LSP（golem-lsp）

- `@nonumber` の図版を「はじめに」に置いた文書で、G04004 が出ない。
- その図版を指す `[ref-number]` の位置に G04005 が出る。

### マニュアル

- 実装の PR で「はじめに」に図を置き、`scripts/manual/build.sh manual` が diagnostic なしで通ることを確かめる。

## トレードオフ

- **得るもの**：前付けと後書きにも図とコードを置ける。章の中でも、番号の要らない装飾的な図や短い例を、番号を消費せずに置ける。書き手は見出しで知っている `@nonumber` を、そのまま使える。
- **失うもの**：意味論 IR の `figure` と `code` に欄が一つずつ増え、ABI が変わる。プラグインの作者は、`nonumber` を書く必要がある。
- **明示の手間**：章の外に図を置くたびに `@nonumber` を書く必要がある。書き忘れは G04004 で止まり、黙って番号が消えることはない。

## メンテナーが決めること

### 1. 章の外の図版の扱い（推奨：案 B）

- **案 A**：章の外の図版とコードブロックには、自動で番号を振らない。G04004 は廃止し、`[ref-number]` で指したら G04005 にする。意味論 IR は変わらず、ABI も変わらない。
- **案 B（推奨）**：`@nonumber` を書いた図版とコードブロックだけ番号を振らない。G04004 は残す。

案 B を推す理由は三つある。
一つ目に、案 A では、書式に `{chapter}` があるかどうかで、章の外の図版に番号が付いたり付かなかったりする。
`図{n}` の書式なら番号が付き、`図{chapter}-{n}` なら黙って消える。
二つ目に、最初の章の見出しを書き忘れた原稿では、案 A だと章の前の図版の番号が diagnostic なしで消える。
出力を黙って変えないという方針に合わない。
三つ目に、案 B は、章の中で番号の要らない図にも使え、見出しの `@nonumber` と同じ考え方で覚えられる。

### 2. 指定の書き方（推奨：属性の行の `@nonumber`）

- **`@nonumber` の属性の行（推奨）**：見出しと同じ書き方である。`@caption` と同じく、```` ``` ```` のコードブロックにも `@listing` にも付けられる。
- **`@figure` のキーワード引数 `number=false`**：コードブロックの行番号の `numbers=true` と名前が似て、取り違えやすい。```` ``` ```` のコードブロックにも別に足す必要がある。採らない。

### 3. キャプションのないコードブロックへの `@nonumber`（推奨：新しいコード G02134 のエラー）

- **G02134 のエラー（推奨）**：付けられる種類のブロックに付けたが、意味がない、という原因は、G02013（その種類のブロックには付けられない）と別である。原因ごとにコードを分ける方針に合わせる。
- **G02013 のエラー**：コードを増やさずに済むが、コードブロックに `@nonumber` を付けられると説明しながら、同じコードブロックで G02013 が出ることになり、説明が食い違う。採らない。
- **何もしない**：書いた指定が何も変えず、diagnostic も出ない。採らない。

G02131 と G02132 は [docs/adr/0187](0187-inline-language-switch.md) が使い、G02133 は使用中なので、次の空きを G02134 とした。
実装の時点で空いていなければ、次の空きを使う。

### 4. 番号を振らないことを意味論 IR に持たせるか（推奨：持たせる）

- **IR に持たせる（推奨）**：見出しの `nonumber` と同じ場所に置き、プラグインも番号のない図版を返せる。
- **IR の外に持たせる**：評価が番号を振らないブロックの位置の集合を作り、組み立ての設定（`AssembleConfig`）で渡す。G04007 の `acNumberSites` と同じ形で、ABI は変わらない。ただし、プラグインは番号のない図版を返せず、同じブロックの性質が二か所に分かれる。採らない。

### 5. 番号もキャプションもない図版のプレーンテキスト（推奨：行を書かない）

- **行を書かない（推奨）**：プレーンテキストは画像を持たないので、番号もキャプションもない図版から読み手に伝わるものがない。
- **代替テキストを `［代替テキスト］` で書く**：情報は残るが、番号のある図版はキャプションだけを書くので、図版によって書くものが変わる。採らない。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-07、メンテナー）：どれも推奨のとおりとした。

## 参考文献

なし
