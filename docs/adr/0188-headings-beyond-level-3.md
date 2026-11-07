# ADR 0188: 見出しを 6 階層まで書けるようにする

ステータス: 採択（未実装）

## 文脈

見出しは 3 階層までである。
[golem-parser ADR 0003](../golem-parser/adr/0003-block-grammar.md) が `####` 以上で始まる行を構文の誤りとし、トレードオフに「書籍の構造は章、節、項で足りることが多く、階層を増やす必要が生じたら ADR で上限を変える」と書いた。
技術書と実用書には、項の下にもう一段か二段の見出しを置くものがある。
[2026-10-16 の TeX との機能の比較](../audits/2026-10-16-tex-feature-gap.md) は、TeX の七階層に対して Golem の三階層を、重要度「中」の差として挙げた。
ロードマップの v0.1.0-rc4 の「見出しの 4 階層め以降」は、この上限を広げる項目である。

### 3 階層の上限がある箇所

上限は一か所でなく、記法、IR、設定、出力に散っている。
コードを読み、v0.1.0-rc3 の `golem`（`~/.local/bin/golem`）で振る舞いを確かめた（2026-11-06）。

| 箇所 | 今の上限 | 確かめ方 |
| --- | --- | --- |
| 記法（golem-parser） | `###` の後に `#` が続けば G01012（`見出しの階層は 3 までです`）（[`Golem.hpeg`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-parser/grammar/Golem.hpeg#L239-L258)） | `#### 目` と `####### 七` が G01012 になった |
| 意味論 IR の CDDL | `level: 1..3`（[`golem-doc.cddl`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-doc/schema/golem-doc.cddl#L17)） | コードを読んだ |
| IR の不変条件（`Validate`） | 階層が 1 から 3 の外なら誤り（[`Validate.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-doc/src/Golem/Doc/Validate.hs#L65)） | コードを読んだ |
| `style.toml` の `[headings.N]` | N が 1、2、3 でなければ G03006（[`Style.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-project/src/Golem/Project/Style.hs#L1919-L1923)） | `[headings.4]` が G03006（`見出しの段は 1、2、3 のどれかです: 4`）になった |
| 番号の書式の差し込み | `{n}`、`{n:kanji}`、`{1}`、`{2}`、`{chapter}` だけ（[`validNumberFormat`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-project/src/Golem/Project/Style.hs#L1931-L1941)、[`formatNumber`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-doc/src/Golem/Doc/Numerals.hs#L61-L80)） | `[headings.2] number = "{3}.{n}"` が G03006（`番号の書式が不正です`）になった |
| 番号の数え方 | 三つの数（[`numberDocs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-doc/src/Golem/Doc/Assemble.hs#L284-L299)）。既定の書式は 3 階層めで `{1}.{2}.{n}`（[`defaultHeadingFormat`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-doc/src/Golem/Doc/Assemble.hs#L265-L269)） | コードを読んだ |
| `@toc` の `depth` | 1 から 3 でなければ G02025（[`File.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-eval/src/Golem/Eval/File.hs#L537-L542)） | コードを読んだ |
| tree-sitter の文法 | `#`、`##`、`###` だけ（[`grammar.js`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/tools/editors/tree-sitter-golem/grammar.js#L103-L106)） | コードを読んだ |
| TextMate の文法 | `#{1,3}`（[`golem.tmLanguage.json`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/tools/editors/textmate/golem.tmLanguage.json#L66)） | コードを読んだ |

一方、階層の数によらずに書かれている箇所もある。

- PDF の見出しの既定の大きさと行取り（`headingDefaults`）は、4 階層め以降に `1zw` と 1 行を返す（[`Fonts.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Fonts.hs#L551-L556)）。仕様書の既定の表は 3 階層までしか書いていない。
- HTML と EPUB の本文は、階層 l の見出しを `<h{l}>` で書く（[`Html.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-html/src/Golem/Html.hs#L401-L406)）。
- EPUB のナビゲーション文書は、項目を階層で入れ子にする（[`navDocument`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-epub/src/Golem/Epub.hs#L133-L137)）。HTML の本文の `@toc` は、項目に `toc-<階層>` の class を付ける。
- LSP のアウトライン（`textDocument/documentSymbol`）は、見出しを階層で入れ子にする（[`outline`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-lsp/src/Golem/Lsp/Features.hs#L838-L858)）。
- 柱の `heading.<l>` は、l が 1 以上の整数なら受け付ける（[`Style.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-project/src/Golem/Project/Style.hs#L963-L969)）。`content = "heading.9.short"` のマスターページを持つ `style.toml` を、`golem check` は終了コード 0 で通した。9 階層めの見出しはないので、この柱は何も出さない。
- PDF の目次は、階層 l の項目を (l − 1) 字下げする（[仕様書の「目次と文書構造の参照」](../specifications.md#目次と文書構造の参照)）。

なお、`golem check` は、同じ `####` の G01012 を二度ずつ出した。
`golem build --target html` は一度ずつ出す。
この ADR の範囲の外の不具合であり、別に直す。

## 実装すること

見出しの階層の上限を 6 にする（「メンテナーが決めること」の 1）。
HTML の見出しの要素が `h1` から `h6` までなので、本の構造を HTML と EPUB にそのまま写せる上限である。

### 記法（golem-parser）

- `#` から `######` までを見出しとする。`HashMark` の選択肢を六つにする。
- `#######` 以上で始まる行は、今と同じく G01012 とし、メッセージを `見出しの階層は 6 までです` に変える。位置は 7 つ目の `#` からとする。
- CST から AST への変換と golem-fmt は、階層を数として扱うので変えない（実装で確かめる）。

### 意味論 IR とプラグインの ABI

- CDDL の見出しを `level: 1..6` にする。`Validate` の範囲も 1 から 6 にする。
- ABI の変更である。v0.1.0-rc3 の ABI のバージョンは 7、今の main は 8 で、8 はまだどのリリースにも含まれていないので、バージョンは 8 のままである（[docs/adr/0052](0052-plugin-abi-version-bump-rule.md)）。
- プラグインが 4 から 6 の階層の見出しを返してもよくなる。7 以上は、今と同じく不変条件の違反である。
- Emet の IR のデータ型は `Heading Nat HeadingAttrs Inlines` で、階層を `Nat` で持つので、型は変えない。返した IR の検査は `Validate` の範囲に従う。

### `style.toml` の `[headings.N]`

- N に 1 から 6 を書ける。ほかの値は今と同じく G03006 とし、メッセージを `見出しの段は 1 から 6 のどれかです` に変える。
- 書けるキーは今と同じ（`font`、`size`、`lines`、`number`、`page-break`、`rule-before`、`rule-after` など）である。
- 4 から 6 の階層の既定は、`size = "1zw"`、`lines = 1` とする（「メンテナーが決めること」の 2）。今の `headingDefaults` のとおりであり、仕様書の既定の表に 4 から 6 の行を足す。
- HTML と EPUB の CSS は、今の `[headings.N]` の罫線と同じく、`h4` から `h6` にも書く。

### 番号

- 階層ごとの数を六つにする。階層 l の見出しは、l より深い階層の数を 0 に戻す。今の規則を六つに広げるだけである。
- 番号の書式の差し込みに `{3}`、`{4}`、`{5}` を足す。`{k}` は、その見出しの上の階層 k の今の番号である。
- 見出しの書式の `{k}` は、k がその見出しの階層より小さくなければ G03006 とする（「メンテナーが決めること」の 3）。今は `[headings.1] number = "{2}"` を受け付け、空の文字列に置き換える（コードを読んだ）。値がつねに空になる差し込みを黙って受けないためである。図版とコードブロックの書式（`[figures]` と `[code]` の `number`）の差し込みは変えない。
- 4 から 6 の階層の既定の書式は、`{1}.{2}.{3}.{n}`、`{1}.{2}.{3}.{4}.{n}`、`{1}.{2}.{3}.{4}.{5}.{n}` とする。今の 2 と 3 の階層の既定と同じ形である。
- `@number` と `@nonumber` は、どの階層の見出しにも今のとおり付けられる。

### 目次

- `@toc` の `depth` に 1 から 6 を書ける。ほかの値は今と同じく G02025 とし、メッセージを `@toc の depth は 1 から 6 の整数です` に変える。`depth` の既定は今のとおり 2 である。
- `@toc` のない本の EPUB のナビゲーション文書と HTML の目次のページは、今のとおり `@notoc` のない見出しをすべて載せるので、6 階層まで載る（[golem-epub ADR 0002](../golem-epub/adr/0002-nav-and-toc-depth.md)）。
- PDF の目次の字下げは、今の (l − 1) 字の規則のままとする。6 階層めは 5 字下げる。

### 柱

- 柱の `heading.<l>` と書式の `{heading.<l>....}` の l は、1 から 6 とする。7 以上は G03014 とする（「メンテナーが決めること」の 4）。今は受け付けて何も出さない。
- 有効な見出しの決め方（l より上の階層の見出しが現れると、階層 l の有効な見出しはなくなる）は変えない。

### HTML と EPUB

- 本文の見出しは、今のとおり `<h{l}>` で書くので、`h4` から `h6` になる。
- EPUB のナビゲーション文書と HTML の本文の `@toc` は、今のとおり階層で入れ子にし、`toc-4` から `toc-6` の class を付ける。
- 注の一覧の見出しは、今のとおり `<h2>` である。

### プレーンテキスト

見出しは今のとおり、番号と題の一行で書く。
階層で書き方を変えないので、変えない。

### LSP とエディタの文法

- LSP のアウトラインは階層で入れ子にするので、変えない。4 から 6 の階層の見出しが、親の見出しの子になることをテストで確かめる。
- tree-sitter の文法の `heading_marker` を `#` から `######` までにし、生成したファイル（`src/grammar.json` など）を作り直す。`tools/editors/test` の見本の原稿に 4 から 6 の階層の見出しを足す。
- TextMate の文法の見出しを `#{1,6}` にする。

### ドキュメント

- 仕様書の見出し、番号、目次、柱、`[headings.N]` の既定の表を 6 階層にする。
- [docs/markup.md](../markup.md) の見出しの節と `@toc` の行を改める。
- [docs/diagnostics.md](../diagnostics.md) の G01012、G02025、G03006、G03014 を改める。
- 使い手のマニュアルの見出しの記法と `[headings.<階層>]` の説明を改める。番号の書式の説明の「`{1}` と `{2}` が上の階層の番号」を、`{1}` から `{5}` に改める。
- [golem-parser ADR 0003](../golem-parser/adr/0003-block-grammar.md) と [golem-driver ADR 0032](../golem-driver/adr/0032-default-heading-styles.md) はコミット済みなので書き換えず、ステータスの行から、この ADR へのリンクを付ける。

## 実装しないこと

- 7 階層め以降の見出し。
- 見出しの段落に `aria-level` を付けるなど、HTML の `h6` を超える見出しを表すこと。
- 追い込みの見出し（見出しの後に同じ行で本文を続けること）。小見出しによく使うが、行取りの規則を変える別の機能である。
- 4 から 6 の階層に、見出しらしく見える既定の書体を決めること。
- `golem check` が G01012 を二度出す不具合を直すこと。別に直す。

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。

golem-parser のテストでは、次のことを確かめる。

- `####`、`#####`、`######` の行が、階層 4、5、6 の見出しになること。今は G01012 になるので失敗する。
- `#######` の行が G01012（新しいメッセージ）になり、位置が 7 つ目の `#` からであること。

golem-doc のテストでは、次のことを確かめる。

- `Validate` が階層 6 の見出しを受け、階層 7 と 0 を拒むこと。
- 階層 1 から 6 の見出しの番号が、既定の書式で `1`、`1.1`、`1.1.1`、`1.1.1.1`、`1.1.1.1.1`、`1.1.1.1.1.1` になること。階層 2 の見出しの後の階層 4 の見出しが、深い階層の数を 0 から数えること。
- `[headings.4] number = "{1}-{3}-{n}"` が書いたとおりに番号を作ること。
- 階層 4 の見出しを飛ばして階層 6 の見出しを置いても、番号が作られること（階層 4 と 5 の数は 0 である）。

golem-project のテストでは、次のことを確かめる。

- `[headings.6]` を受け、`[headings.7]` と `[headings.0]` が G03006 になること。
- `[headings.2] number = "{2}.{n}"` と `[headings.1] number = "{2}"` が G03006 になり、`[headings.5] number = "{4}.{n}"` を受けること。
- 柱の `heading.6.short` を受け、`heading.7.short` が G03014 になること。

golem-eval のテストでは、`@toc depth=6` を受け、`@toc depth=7` が G02025 になることを確かめる。

golem-driver のテストでは、次のことを確かめる。

- 6 階層の見出しを持つ本の PDF で、4 から 6 の階層の見出しが既定の `1zw` と 1 行で組まれ、PDF の目次の項目が 3 字から 5 字下がること。
- HTML と EPUB の本文が `<h4>` から `<h6>` を書き、ナビゲーション文書が 6 段に入れ子になること。
- 柱の `heading.5.short` が、そのページの階層 5 の見出しを出すこと。
- 3 階層までの fixture の出力のバイト列が変わらないことを、決定性の検査の期待値で確かめる。

golem-lsp のテストでは、アウトラインが階層 4 から 6 の見出しを親の見出しの子にすることを確かめる。

エディタの文法は、`tools/editors/test.sh` で、見本の原稿の `####` から `######` の行が見出しになり、`#######` が見出しにならないことを確かめる。

## トレードオフ

上限を 6 にしても、7 階層めは書けない。
HTML の見出しの要素に合わせた上限であり、TeX の七階層（`\part` を含む）には一つ足りない。
`\part` に当たる部の区切りは、見出しの階層でなく章の上の構造として別に扱うほうが自然だと考える。

4 から 6 の階層の既定は本文と同じ大きさで 1 行なので、`[headings.N]` で書体を決めないと、本文の段落と見分けにくい。
既定の書体を太字にする案もあるが、太字の役割があるとは限らない。

見出しの書式で、自分の階層以上の `{k}` を G03006 にするので、今の `style.toml` に `[headings.1] number = "{2}"` のような書式があれば、エラーになる。
その書式は今も空の文字列を出すだけなので、直して失うものはない。

柱の `heading.<l>` で 7 以上を G03014 にするので、今その値を書いた `style.toml` もエラーになる。
その柱は今も何も出さない。

## 決めたことの記録

- **見出しの 4 階層め以降**（ロードマップ）：意味論の IR の見出しは 3 階層までで、4 階層め以降の見出しを書けない。
- **扱う範囲**（2026-11-06、ADR の作成の依頼）：IR とプラグインの ABI、`style.toml` の `[headings.N]`、番号、目次、HTML の `h4` から `h6` と EPUB のナビゲーション文書、LSP のアウトライン、tree-sitter の文法を扱う。
- **すべての項目**（2026-11-07、メンテナー）：「推奨で問題なし」。「メンテナーが決めること」の 1 から 4 を、すべて推奨のとおりとした。

## メンテナーが決めること

すべて決めた（「決めたことの記録」）。

1. **上限の階層**：決めた。推奨のとおり、6 とする（「決めたことの記録」）。HTML の `h1` から `h6` にそのまま写せる。退けた案は、4 とすること（ロードマップの項目は満たすが、同じ箇所をもう一度変えることになりうる）と、上限を設けないこと（HTML と EPUB で 7 以上を表す手段がなく、`aria-level` などを別に決めることになる。PDF の目次の字下げも限りなく深くなる）。
2. **4 から 6 の階層の既定**：決めた。推奨のとおり、`size = "1zw"`、`lines = 1` とする（「決めたことの記録」）。今の `headingDefaults` がすでに返す値であり、小見出しは本文と同じ大きさで 1 行を占めることが多い。退けた案は、3 階層めと同じ `lines = 2` にすること（小見出しが続く本で行取りの空きが大きくなる）と、階層が深いほど小さくすること（本文より小さい見出しは、本文の格子の上で読みにくい）。
3. **番号の書式の検査**：決めた。推奨のとおり、見出しの書式の `{k}` を k がその階層より小さいときに限り、ほかを G03006 にする（「決めたことの記録」）。退けた案は、今のとおり受け付けて空の文字列にすること（値がつねに空になる差し込みを黙って受ける。仕様書の「緩い規則より厳しい規則」に反する）。
4. **柱の階層の検査**：決めた。推奨のとおり、`heading.<l>` の l を 1 から 6 に限り、7 以上を G03014 にする（「決めたことの記録」）。退けた案は、今のとおり受け付けること（決して現れない見出しを指す柱を、黙って何も出さない柱にする）。

## 参考文献

- WHATWG, *HTML Living Standard*, 4.3.6 The h1, h2, h3, h4, h5, and h6 elements. https://html.spec.whatwg.org/multipage/sections.html#the-h1,-h2,-h3,-h4,-h5,-and-h6-elements
- W3C, *EPUB 3.3*, the EPUB navigation document. https://www.w3.org/TR/epub-33/
- [golem-parser ADR 0003](../golem-parser/adr/0003-block-grammar.md)、[golem-parser ADR 0009](../golem-parser/adr/0009-syntax-diagnostic-codes.md)、[golem-driver ADR 0032](../golem-driver/adr/0032-default-heading-styles.md)、[golem-epub ADR 0002](../golem-epub/adr/0002-nav-and-toc-depth.md)、[docs/adr/0052](0052-plugin-abi-version-bump-rule.md)
- [2026-10-16 の TeX との機能の比較](../audits/2026-10-16-tex-feature-gap.md)
