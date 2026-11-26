# ADR 0463: 番号のある見出しとキャプションの題を、変数を差し込める書式で組む

Status: proposed

## 文脈

[Golem ADR 0372](0372-number-title-separator.md) は、番号と題のあいだの区切りを、スタイルの `number-title-separator` に文字列で書けるようにした。
書けるのは、番号、区切り、題の順に並ぶときの区切りだけである。
そのため、題の後に文字を置くこと、番号と題のあいだに変数の値を置くこと、題を番号の前に置くことはできない。

メンテナーは、2026-11-26 に、番号と題の並べ方を、書き手が変数を参照して任意に書けるようにすると決めた。
スタイルに指定が無ければ、今の出力を変えない。

この ADR は、番号のある見出しとキャプションの題の書式を足す。
見出しの書式は `[headings.<階層>]` に書くので、ロードマップの「見出しの番号と題の区切りを書く場所」は、見出しの区切りと書式を `[headings.<階層>]` に書くことで決まる。

## 調査した事項

origin/main（[c034510](https://github.com/tett23/golem/commit/c034510e33476f4af68ba22636f5ab6ef8463f0a)）で、次のことを確かめた。

- 番号と区切りと題は、組版では `numberedTitleWith` で一つのテキストにつなぐ（[Flow.hs#L1214-L1225](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L1214-L1225)）。
  区切りは、見出しの階層とファイルの組（`bookTitleSeparators`）で引く。
  番号の無いときは題だけを返す。
- 柱の `heading.<l>.numbered` も、同じ区切りで、番号と区切りと短い題をつなぐ（[Flow.hs#L1200](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L1200)）。
- HTML は、番号を `<span class="number">` に入れ、その後に区切りと題を書く（[golem-html ADR 0002](../golem-html/adr/0002-heading-number-spacing.md) の 71 行）。
- 柱の書式は、差し込みのある書式として `parseRunningFormatLegacy` が読む（[Style.hs#L1583-L1616](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-project/src/Golem/Project/Style.hs#L1583-L1616)）。
  差し込みは `heading.*`、`meta.<キー>`、`set.<名前>`、`set.<名前空間>.<名前>`、`vars.<名前>` で、末尾の `?` で値が無いときに空の文字列にする。
  読み方は最初の誤りで止まる。
  旧記法の `{{` と `}}` は波括弧として読み、G03252 で報告する（[Style.hs#L1574-L1577](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-project/src/Golem/Project/Style.hs#L1574-L1577)）。
- 柱の `set.*` の値は、章のファイルごとに `runningVars` が、ファイルの公開する変数から求める（[Evaluate.hs#L486-L515](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-evaluate/src/Golem/Evaluate.hs#L486-L515)）。
  ファイルに無い変数は G02067、文字列でも数でもない値は G02068 で、どちらもファイルと名前ごとに一つであり、PDF をターゲットに含むビルドと `golem check` でだけ検査する（docs/specifications.md の 4715 行）。
  `[vars]` に無い名前は G03111、文字列でも数でもない値は G03112 で、`style.toml` を読んだところで検査する（同 4716 行）。
- 柱では、`?` の無い差し込みのうち一つでも値が無ければ、その行を描かない（docs/specifications.md の 4690 行から 4695 行）。
- 言語サーバーは、柱の書式に `{set.<名前>}` があるとき、その変数の改名を断る（[root ADR 0454](0454-rename-set-variables-in-the-language-server.md) の「改名を断る場合」）。
- 仕様書の「見出しの属性と番号」の節は、`number-title-separator` を、見出し、三つのキャプション、目次の項目、PDF のしおり、柱の `heading.<l>.numbered` に当てると定める（docs/specifications.md の 2073 行から 2093 行）。

## 実装すること

### 書式のキー

`[headings.<階層>]` と段落スタイルに、文字列のキー `title-format` を足す。
キーを書く場所と、キーの決まり方は `number-title-separator` と同じである。
見出しの書式は、その階層の `[headings.<階層>]` に書く。
図版、コードブロック、表のキャプションの書式は、段落スタイル `caption` に書き、`based-on` をたどって決まる。
原稿の `@style-def paragraph caption` に書いた書式は、そのファイルのキャプションに当たる。

`title-format` を書いた見出しとキャプションは、番号を持つとき、題の代わりに書式を組む。
番号を持たない見出しとキャプションは、書式を書いても、今と同じく題だけを組む。
`title-format` を書かない見出しとキャプションは、今と同じく、番号と区切りと題を組む。

### 書式の形

書式は、柱の書式と同じ「差し込みのある書式」であり、文字、エスケープ、差し込みからなる。
差し込みは次のとおりである。

| 差し込み | 値 |
| --- | --- |
| `{number}` | 番号の表記（`number` の書式で組んだもの） |
| `{title}` | 題。見出しとキャプションでは原稿の題で、ルビなどのインラインを保つ。目次の項目、PDF のしおり、柱では、今と同じく短い題 |
| `{separator}` | `number-title-separator` の値。書いていなければ、本の言語で決まる既定の区切り |
| `{meta.<キー>}` | マニフェストの `[metadata]` の値。キーは柱の書式と同じ |
| `{set.<名前>}`、`{set.<名前空間>.<名前>}` | 見出しかキャプションのあるファイルが公開する変数か、そのファイルが取り込んだ変数。決まりは柱の書式と同じ |
| `{vars.<名前>}` | マニフェストの `[vars]` の変数 |

`{separator}` は、番号の文字列が空白で終わるときにも、書いた位置にそのまま置く。
書式が `{number}` と `{title}` を含むかは検査しない。
`title-format` は新しいキーなので、旧記法の `{{` と `}}` を受け付けない。

差し込みの名前の末尾の `?` は、値が無いときに空の文字列にする。
`?` の無い差し込みに値が無ければ、下のdiagnosticを出し、その差し込みを空の文字列として組む。
柱と違って、題の行を描かないことはしない。
題は本文の見出しとキャプションなので、行ごと消すと本文が欠けるからである。

### 書式を組む段

`{meta.*}`、`{vars.*}`、`{set.*}` は、評価（S0）の後に、ファイルと階層ごとに値で置き換える。
置き換えた書式は、`{number}`、`{title}`、`{separator}` の差し込みと文字の片の並びであり、文字列に戻して読み直さない。
変数の値が波括弧を含んでも、差し込みにならない。
この並びを、今の区切りの表と同じ道で、ファイルと階層ごとに組版と HTML の出力に渡す。
意味論 IR と、golem-* のパッケージの依存は変えない。

### 当てる出力

`title-format` は、`number-title-separator` を当てる出力のすべてに当てる。
見出し、図版のキャプション、コードブロックのキャプション、表のキャプション、目次の項目（PDF の目次、本文の `@toc`、HTML の目次のページ、EPUB のナビゲーション文書、PDF のしおり）、柱の `heading.<l>.numbered` である。
目次の項目と柱は、元の見出しの階層の書式と、元の見出しのファイルの変数を使う。

HTML では、書式の `{number}` の出るたびに、番号を `<span class="number">` に入れて書く。
`{title}` の位置に題のインラインを書き、書式のほかの部分は、テキストとして書く。

### diagnostic

| 箇所 | コード | 重大度 | メッセージ |
| --- | --- | --- | --- |
| 値が文字列でない | G03006 | エラー | 今と同じ |
| 書式として読めない（未知の差し込み、閉じない `{`、`{{` と `}}`、改行） | G03296 | エラー | `title-format を書式として読めません: <理由>` |
| `?` の無い `{vars.<名前>}` の名前が `[vars]` に無い | G03297 | エラー | `題の書式が参照する変数 <名前> が [vars] にありません` |
| `{vars.<名前>}` の値が文字列でも数でもない | G03298 | エラー | `題の書式に出せるのは文字列と数です: vars.<名前> は <型>` |
| `?` の無い `{meta.<キー>}` のキーがマニフェストに無い | G03299 | エラー | `題の書式が参照する [metadata] の <キー> がありません` |
| `?` の無い `{set.*}` の変数が、見出しかキャプションのファイルに無い | G02283 | エラー | `題の書式が参照する変数 <名前> が、このファイルにありません` |
| `{set.*}` の値が文字列でも数でもない | G02284 | エラー | `題の書式に出せるのは文字列と数です: <名前> は <型>` |

G03296 から G03299 は、`style.toml` と `@style-def` を読んだところで、書いた値ごとに出す。
書式の読み方は最初の誤りで止まるので、G03296 は値ごとに一つである。
G02283 と G02284 は、S0 の評価の後に、どのターゲットのビルドと `golem check` でも検査する。
書式を組む見出しとキャプションの一つごと、名前ごとに一つ出し、位置はその見出しかキャプションである。
目次や柱が同じ見出しを組み直しても、同じ見出しについて重ねて出さない。
柱の G02067、G02068、G03111、G03112 とは、参照する場所が別の原因なので、別のコードにする。

### ほかの道具

言語サーバーは、`title-format` に `{set.<名前>}` か `{set.<名前空間>.<名前>}` があるとき、0454 の柱の書式と同じく、その変数の改名を断る。
golem-lint は、`title-format` が参照する変数を、使われた変数として数える（G05002 にしない）。

### 文書

仕様書の「見出しの属性と番号」の節と、段落スタイルと `[headings.<階層>]` のキーの表に、`title-format` を書く。
`docs/diagnostics.md` に G02283、G02284、G03296 から G03299 を足し、G03006 の説明に `title-format` の書式の誤りを使わないことを書く。
マニュアルの見出しの番号の節に、書式の例を足す。
ロードマップの「見出しの番号と題の区切りを書く場所」を消す。

採択したら、次の ADR のステータスに記録する。
どの記録も `"by":["docs/adr/0463-title-formats-for-numbered-headings-and-captions.md"]` を持つ。

- 0372：`{"part":null,"kind":"supplement"}`
- 0454：`{"part":"改名を断る場合","kind":"supplement"}`

## 実装しないこと

番号を持たない見出しとキャプションの書式は足さない。
差し込みに、式や、数の表記の指定は書けない。
傍注の番号とリストの印には当てない。
`number-title-separator` の決まりは変えない。
柱の書式のdiagnosticと、柱の変数を golem-lint が数えるかは変えない。

## 不変条件

- I1: `title-format` をどこにも書かない本は、どの出力も、この ADR の前と同じである。
- I2: 番号のある見出しかキャプションの、書式を当てる出力の文字列は、書式の各差し込みを値（値が無ければ空の文字列）で置き換えた文字列と等しい。
- I3: 番号を持たない見出しとキャプションの文字列は、`title-format` の有無にかかわらず、題だけである。
- I4: 目次の項目と柱の `heading.<l>.numbered` の文字列は、元の見出しの階層の書式の `{title}` を短い題にし、`{set.*}` を元の見出しのファイルの変数にして組んだものと等しい。
- I5: G02283 の数は、書式を組む見出しとキャプションと、`?` の無い値の無い `{set.*}` の名前の組の数に等しく、出力とターゲットの数によらない。G02284 も、値が文字列でも数でもない名前について同じである。
- I6: 書式として読めない `title-format` の値ごとに、G03296 がちょうど一つ出る。
- I7: 文字列でない `title-format` の値ごとに G03006 が、`?` の無い値の無い `{vars.*}` と `{meta.*}` の差し込みごとに G03297 か G03299 が、文字列でも数でもない `{vars.*}` ごとに G03298 が、ちょうど一つ出る。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| `title-format` を書かない本 | 今と同じ | I1 |
| `[headings.1] number = "第{n}章"`、`title-format = "{number}{separator}{title}"`、言語 `ja` | 今と同じ文字列 | I2 |
| `title-format = "{title}（{number}）"`、題「序論」、番号「第1章」 | 「序論（第1章）」 | I2 |
| 同じ書式の HTML の見出し | `序論（<span class="number">第1章</span>）` | I2 |
| `title-format = "{number}　{set.part}　{title}"`、ファイルに `@set part = "上"` | 「第1章　上　序論」 | I2 |
| 番号からの除外を指定した見出しと `title-format` | 題だけ | I3 |
| 短い題「序」を持つ見出しの `@toc` の項目と `title-format = "{title}（{number}）"` | 「序（第1章）」 | I4 |
| `{set.part}` の無いファイルの見出し二つと、その目次と柱、HTML と PDF の二つのターゲット | G02283 が二つ。差し込みは空 | I5 |
| `{set.part?}` の無いファイルの見出し | diagnosticなし。空の文字列 | I2 |
| `@set part = [1, 2]` と `{set.part}` の見出し | G02284 が一つ | I5 |
| `@set part = "{title}"` と `title-format = "{set.part}：{title}"`、題「序論」 | 「{title}：序論」 | I2 |
| `title-format = "{nmber}{titel}"` | G03296 が一つ | I6 |
| `title-format = "{{number}}"` | G03296 が一つ | I6 |
| `title-format = 1` | G03006 | I7 |
| `title-format = "{vars.series}"`、`[vars]` に `series` が無い | G03297 | I7 |

## 受けいれ条件

なし。
不変条件のテストで足りるためである。

## テスト設計

root ADR 0463 I1 から I7 を名前の先頭に置いたテストを、golem-project（書式の読み込み）、golem-evaluate（変数の置き換えとdiagnostic）、golem-typeset（PDF の見出し、目次、柱）、golem-html（HTML と EPUB の見出しとナビゲーション文書）に足す。
I1 は、今ある見出しとキャプションのテストと、視覚の回帰の参照が変わらないことで確かめる。
言語サーバーの改名を断る場合と、golem-lint の数え方も、golem-lsp と golem-lint のテストで確かめる。
テストは、実装の前に書いて落ちることを確かめる。

## トレードオフ

`{number}`、`{title}`、`{separator}` を差し込みにしたので、今の出力は `{number}{separator}{title}` とほぼ同じ書式で書ける。
ただし、今の規則は、題が空のときと、番号が空白で終わるときに区切りを省く。
書式はこの省き方をしないので、書式を書かないときの出力を、書式に読み替えて実装せず、今の規則のまま残す。

番号を持たない見出しに書式を当てないので、番号を持たない見出しの前後に文字を置くことはできない。
番号の無い見出しに書式を当てると、`{number}` の値が無く、書き手が多くの書式に `?` を書くことになるためである。

## 参考文献

- [Golem ADR 0372](0372-number-title-separator.md)
- [golem-html ADR 0002](../golem-html/adr/0002-heading-number-spacing.md)
- [golem-driver ADR 0022](../golem-driver/adr/0022-running-head-formats.md)
- [root ADR 0454](0454-rename-set-variables-in-the-language-server.md)
- [root ADR 0461](0461-report-the-diagnostics-that-follow-from-another-error.md)
