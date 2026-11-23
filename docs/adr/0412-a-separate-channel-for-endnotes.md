# ADR 0412: 章末の注を、脚注と別のチャネルにする

Status: proposed

## 文脈

今の注のチャネルは二つある。
脚注 `[note: …]` と、傍注 `[sidenote: …]` である。
脚注をページの下に置くか章の終わりにまとめるかは、`[notes].placement`（`"page-foot"` か `"chapter-end"`）で、本の全体に一つだけ選ぶ。
そのため、一冊の中で、ページの下の注と章末の注を一緒に使えない。

学術書には、説明の注をページの下に、出典の注を章の終わりに置く本がある。
tett23 は 2026-11-23 に、まれではあるが、二つを一冊の中で一緒に使えるように分けることを決めた。

[ADR 0404](0404-separate-footnote-and-chapter-end-styles.md) は、「新しい注チャネルや、注ごとに配置先を選ぶ記法は追加しない」と決めていた。
この ADR は、その部分を置き換える。

## 調査した事項

`origin/main`（`b540aa68a`）で確かめた。

- 仕様書の「チャネル」の節は、脚注、索引、参考文献を、インラインのコマンドが印を出して項目を送り、一覧を出す仕組みとしてまとめている（[docs/specifications.md](../specifications.md) の 7038 行から 7061 行）。
- 傍注は、「出典は脚注に、用語の補足は傍注に、と一冊の中で使い分けられるようにするため」に、別のコマンドにした（同 7388 行）。
  番号は脚注と別に数え、`numbering` の範囲は共有する（同 7114 行と 7390 行）。
- 注の IR は、[`Note` と `Sidenote`](https://github.com/tett23/golem/blob/b540aa68a3bbb45ed4a8754f79852984152f6cf6/modules/golem-doc/src/Golem/Doc/IR.hs#L340-L343) である。
  プラグインに渡す CBOR では、それぞれタグ 23 と 24 である。
- コマンドの名前は、golem-eval の組み込みのコマンドの一覧で決まる。
  パーサーと整形は、汎用の `[name args: prose]` を読むので、名前を知らない。
- 番号は、文書の組み立ての段で [`renumberNotes`](https://github.com/tett23/golem/blob/b540aa68a3bbb45ed4a8754f79852984152f6cf6/modules/golem-assemble/src/Golem/Assemble.hs#L764-L799) が、脚注と傍注を別々に数えて振る。
- PDF では、章末に置く本かどうかを本の全体で一つの真偽値として持つ。
  真のときは、ページの下の脚注を作らず、章の最後のファイルの末尾に一覧を差し込む。
- HTML、EPUB、プレーンテキストは、`placement` によらず、脚注を章末にまとめる。
- `[notes.footnote]` と `[notes.chapter-end]` の表は、[ADR 0404](0404-separate-footnote-and-chapter-end-styles.md) が、置き場所ごとの本文と見出しの段落スタイルを書くために使っている。
- `numbering = "page"`（[ADR 0383](0383-page-local-note-numbers.md)）は、ページの下の注のためのものである。
  章末の一覧で番号が重なれば、章ごとに警告 G07132 を出す（[ADR 0402](0402-define-page-local-note-fallback-diagnostics.md)）。
- rc4 の仕様には `placement` の二つの値がすでにある。
  リポジトリの中で `placement = "chapter-end"` を書く設定は、golem-driver の conformance の fixture の一つだけである。

## 実装すること

### 原稿の記法

- 章末の注のコマンド `[endnote: 本文]` を足す。
  二つ以上の段落を書く `@endnote 名前` と `[endnote 名前]` も、脚注の `@note` と `[note 名前]`（[ADR 0263](0263-notes-with-more-than-one-paragraph.md)）と同じ規則で足す。
- `[endnote]` は、どの出力でも章の終わりにまとめる。
- `[note]` は、今と同じく `[notes].placement` に従う。
  `placement = "chapter-end"` の本の `[note]` も、今と同じく章の終わりにまとめる。

### チャネルと番号

- `[endnote]` は、脚注と傍注と別のチャネルとし、別に番号を数える。
- 章末の注の設定は、新しい表 `[endnotes]` に書く。
  キーは `numbering`、`mark-format`、`mark-style`、`body-mark-style`、`mark-shape`、`body-style`、`heading-style` とし、意味は `[notes]` の同じ名前のキーと同じにする。
  `[endnotes]` に書かないキーは、`[notes]` の値を引き継がず、この ADR の既定の値を使う。
  `body-mark-style`、`mark-shape`、`body-style`、`heading-style` の既定は、`[notes]` と同じく「なし」とし、書かなければ `[notes]` の同じキーを書かないときと同じ組み方（本文の印は印の文字スタイルだけ、平字にしない、本文と見出しは組み込みの段落スタイル）で組む。
- `[endnotes]` の既定の値は、`numbering = "chapter"`、`mark-format = "{n}"`、`mark-style = "note-mark"` とする。
  `mark-format` の既定を脚注（`"*{n}"`）と変えるのは、一冊の中で二つを一緒に使うとき、既定のままでも印で見分けられるようにするためである。
- `[endnotes]` の `numbering = "page"` は、章末の一覧に物理ページの番号を振る意味がないので、設定の誤りとする。
  この誤りには新しいコードを一つ作る（「章末の注にはページごとの番号を使えない」）。

### 一覧

- 章の終わりに二つの一覧が並ぶときは、脚注の一覧を先に、`[endnote]` の一覧を後に置く。
  PDF では `placement = "chapter-end"` のとき、HTML、EPUB、プレーンテキストではいつも、二つの一覧が並ぶ。
- `[endnote]` の一覧の見出しは、マニフェストの `language` の主の副タグが `ja` なら「後注」、そうでなければ「Endnotes」とする（脚注の一覧の見出しと同じ判定）。
  脚注の一覧の見出し（「注」、「Notes」）と見分けるためである。
- HTML と EPUB では、`[endnote]` の一覧を `<section class="endnotes">` とし、一覧の側の id を `endnote-N`、本文の印の側の id を `endnoteref-N` とする。
  `numbering = "file"` で番号が重なるときは、`endnote-k-N` と `endnoteref-k-N` の形にし、G03027 は脚注と同じ規則で出す。
- プレーンテキストでは、`[endnote]` の一覧を脚注の一覧の後に出す。

### 設定と仕様

- [ADR 0404](0404-separate-footnote-and-chapter-end-styles.md) の `[notes.chapter-end]` は、今と同じく、`placement = "chapter-end"` の本の `[note]` の章末の一覧に当てる。
  `[endnote]` の一覧には当てない。
- 仕様書の「チャネル」「脚注」「注の番号と置き場所」「注の配置」の節、markup.md、LSP の補完と設定のスキーマ、diagnostic の一覧を直す。
- 注の IR に `Endnote` を足し、プラグインに渡す CBOR に新しいタグを足す。
  プラグインの ABI の版を上げる。
- 採択したら、[ADR 0404](0404-separate-footnote-and-chapter-end-styles.md) のステータスの行に、部分「新しい注チャネルや、注ごとに配置先を選ぶ記法を追加しないこと」（[ADR 0404](0404-separate-footnote-and-chapter-end-styles.md) の 31 行の一文の全体）を、この ADR による置き換えとして足す。

## 実装しないこと

- 注のコマンドに、置き場所を選ぶ引数は足さない。
  置き場所はコマンドで決める。
- `[endnote]` をページの下に置く設定は設けない。
- 本の終わりにまとめる後注（巻末注）は、この ADR では扱わない。
- 一覧の見出しの文言を変える設定は、この ADR では扱わない。
  ロードマップの見出しの文言の項目に、「後注」も足す。
- 傍注の規則は変えない。

## 不変条件

「チャネル」は、脚注、傍注、章末の注の三つとする。
「章」は、マニフェストの章とする。

- I1：どの原稿でも、章末の注のチャネルの番号は、脚注と傍注の数によらず、`[endnotes].numbering` の範囲ごとに 1 から連続する。
- I2：どの原稿でも、`[endnote]` の本文は、すべての出力で、その注を書いた章の章末の一覧にちょうど一度ずつ、原稿の順に出る。
- I3：どの原稿でも、`[endnote]` を一つも書かない本の出力は、この ADR の前と同じである。
- I4：`placement = "chapter-end"` の本で、一つの章に脚注と章末の注の両方があるとき、章末には脚注の一覧、章末の注の一覧の順に二つの一覧が出る。
- I5：`[endnotes]` に `numbering = "page"` を書くと、設定の位置に新しいコードのエラーを一つ出す。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| `[endnote]` のない本 | 前と同じ | I3 |
| `[endnote]` が一つ | 章末の一覧に 1 | I1, I2 |
| 脚注二つと章末の注一つが交互（ページの下に置く本） | 脚注は 1、2、章末の注は 1 | I1, I2 |
| 同じ（`placement = "chapter-end"` の本） | 章末に「注」と「後注」の二つの一覧 | I2, I4 |
| 二つの章に章末の注 | 章ごとに 1 から | I1, I2 |
| 章末の注を書いた章の最後のファイルが改ページで終わる | 一覧は改ページの前 | I2 |
| `[endnotes] numbering = "page"` | 新しいコードのエラー | I5 |
| 複数段落の `@endnote 名前` | 一つの注として出る | I2 |

## 受けいれ条件

なし。
この ADR の振る舞いは、不変条件のテストで確かめる。

## テスト設計

- 名前は `root ADR 0412 I<番号>: ...` とする。
  テストは、実装の前に失敗することを確かめてから実装する。
- I1 と I2 は、脚注、傍注、章末の注の三種を、長さ 0 から 4 のすべての並びで二つの章に置き、`[notes].numbering` の四つの値、`[endnotes].numbering` の `"page"` を除く三つの値、`placement` の二つの値のすべての組で、PDF、HTML、EPUB、プレーンテキストの一覧を確かめる。
- I3 は、今ある注のテストと visual の基準が変わらないことで確かめる。
- I4 は、`placement = "chapter-end"` の本の PDF と HTML で、二つの一覧の順と見出しを確かめる。
- I5 は、golem-project のテストで、設定の位置とコードを確かめる。
- プラグインの ABI のテストで、`Endnote` の CBOR の往復を確かめる。
- LSP の補完に `endnote` が出ることを確かめる。

## トレードオフ

`[endnote]` のコマンドを足すと、書き手は注を書くときに置き場所を選ぶことになる。
本の全体の置き場所を変えたいときは、今までどおり `[notes].placement` を使える。
一冊の中で両方を使う本は少ないと見込むので、既定の書き方（`[note]` だけ）は変えない。

章末の注の一覧の見出しを「後注」に決めたが、出版社によって呼び方は違う。
見出しの文言を変える設定は、ロードマップの項目で扱う。

## 参考文献

- [ADR 0404](0404-separate-footnote-and-chapter-end-styles.md)
- [ADR 0366](0366-note-body-styles.md)
- [ADR 0383](0383-page-local-note-numbers.md)
- [ADR 0402](0402-define-page-local-note-fallback-diagnostics.md)
- [ADR 0263](0263-notes-with-more-than-one-paragraph.md)
