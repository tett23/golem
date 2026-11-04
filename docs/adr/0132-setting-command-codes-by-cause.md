# ADR 0132: `@manifest` と `@style-def` の引数の誤りを原因ごとのコードに分ける

ステータス: 採択（未実装）

## 文脈

ファイルの設定の `@manifest` と `@style-def` は、引数の誤りをすべて G02052 にする（[docs/adr/0014](0014-in-file-settings.md)）。
[docs/adr/0014](0014-in-file-settings.md) の表と docs/diagnostics.md によれば、G02052 の条件は次の七つである。

1. 位置引数の数の誤り（`@manifest` の位置引数、`@style-def` の種類か名前の欠け、三つめの位置引数）
2. `@style-def` の未知の種類（`@style-def table a`）
3. 展開する引数（`*[...]`、`**[...]`）
4. 本体がある
5. `@manifest` に引数がない
6. 同じキーを二度書いた
7. 値が語と文字列のほか（`[= ...]` など）

どれも [`Golem.Eval.Settings`](https://github.com/tett23/golem/blob/399220d4bdffc0566f69725516b3ceeb471371fc/modules/golem-eval/src/Golem/Eval/Settings.hs#L55-L235) が出す。
引用は、断りのないかぎり origin/main の 399220d4 のものである。

メンテナーは「一つの原因に一つのコード」を、ほかの事情に優先する原則としている。
G02052 は七つの原因を一つのコードにまとめており、この原則に反する。
CI や LSP でコードを見て直し方を選ぶ使い手は、G02052 からはどの誤りかを決められず、メッセージの文を読むしかない。

このうち 3 は、[docs/adr/0112](0112-spread-arguments.md) が G02114（評価の前に引数を読むコマンドに展開を書いた）に移す。
ほかの六つにも、同じ原因のコードがすでにあるものがある。

- 4 は、[docs/adr/0056](0056-printings-diagnostic-codes-by-cause.md) と [docs/adr/0060](0060-page-break-command-codes-by-cause.md) が定めた G02097（本体を持てないコマンドに本体を書いた）と同じ原因である。
- 6 は、[golem-parser ADR 0013](../golem-parser/adr/0013-splat-after-keyword-arguments.md) が定めた G02077（同じキーを二度書いた）と同じ原因である。この ADR は、`@manifest` と `@style-def` は設定であり引数の読み方を別に持つとして、G02052 のまま残した。しかし、読み方が別でも、書き手の誤りは同じである。

[docs/adr/0056](0056-printings-diagnostic-codes-by-cause.md) と [docs/adr/0060](0060-page-break-command-codes-by-cause.md) は、`@printings` と `@page-break` で同じように一つのコードを原因ごとに分けた。
この ADR は、その方針を設定のコマンドに当てる。

## 実装すること

### 原因とコード

| 原因 | 今 | この ADR | 位置 |
| --- | --- | --- | --- |
| 位置引数の数の誤り（`@manifest` に位置引数がある、`@style-def` の位置引数が二つでない） | G02052 | G02052 | 余分な位置引数。足りないときはコマンドの行 |
| `@style-def` の未知の種類 | G02052 | G02117（新規） | 種類の引数 |
| 展開する引数 | G02052 | G02114（[docs/adr/0112](0112-spread-arguments.md)） | 展開の引数 |
| 本体がある | G02052 | G02097 | 本体の最初のブロック |
| `@manifest` に引数がない | G02052 | G02115（新規） | コマンドの行 |
| 同じキーを二度書いた | G02052 | G02077 | 二度めから後のそれぞれの引数の全体 |
| 値か位置引数が語と文字列のほか | G02052 | G02116（新規） | その引数 |

G02052 には、位置引数の数の誤りだけが残る。
G02052 の見出しは、`@manifest` か `@style-def` の位置引数の数の誤りだけを述べる文に改める。
`@manifest` が取る位置引数は零個、`@style-def` は二つ（種類と名前）であり、どちらも「書いた位置引数の数が、コマンドの取る数と違う」という一つの原因である。

### 新しいコード

| コード | 重大度 | 原因 | メッセージ |
| --- | --- | --- | --- |
| G02115 | エラー | `@manifest` にキーワード引数が一つもない | `@manifest には key=value を一つ以上書きます` |
| G02116 | エラー | `@manifest` か `@style-def` の値か位置引数を、語と文字列のほか（`[= ...]` など）で書いた | `値は語か文字列で書きます` |
| G02117 | エラー | `@style-def` の種類が `character`、`paragraph`、`regex` のどれでもない | `未知のスタイルの種類です: <種類>。character、paragraph、regex のどれかを書きます` |

- 一つの `@manifest` か `@style-def` に原因が複数あれば、原因ごとに一つずつ出す。G02052 と G02116 と G02077 は、それぞれの引数ごとに出す。
- 位置引数が二つあり、種類を `[= ...]` で書いた `@style-def` は、G02117 ではなく G02116 とする。種類が分からないのは、値の書き方の誤りの結果だからである。
- `@style-def` の種類と名前を文字列リテラル（`@style-def "paragraph" "note"`）で書いたものは、語と同じに読む。[docs/adr/0112](0112-spread-arguments.md) が、語だけを受け取っていた位置に同じ字の文字列リテラルを受け取らせるのと揃える。今は G02052 である。

### 誤りの後の扱い

どのコードもエラーであり、一つでも出ればビルドは失敗する。
ほかの誤りを一度に報告するために評価を続けるときの扱いは、今と変えない。

- `@manifest` に本体があるか引数がなければ、その `@manifest` を無視する。ほかの誤りは、誤りのある引数だけを無視し、ほかの引数の上書きは適用する。
- 誤りのある `@style-def` は、その定義の全体を捨てる。
- 同じキーを二度書いた `@manifest` と `@style-def` は、エラー（G02077）とする。

### ドキュメント

- docs/diagnostics.md：G02052 の見出し、意味、メッセージ、主な原因を位置引数の数の誤りだけに改める。G02115、G02116、G02117 を足す。G02077 と G02097 の対象に `@manifest` と `@style-def` を加え、G02077 の「`@manifest` と `@style-def` は同じキーを G02052 にする」という文を消す。
- docs/markup.md と docs/specifications.md：ファイルの設定の節に G02052 の条件を書いた箇所があれば、新しいコードに改める。
- この ADR を採択したら、[docs/adr/0014](0014-in-file-settings.md) のステータスの行に「G02052 の原因の分け方は [docs/adr/0132](0132-setting-command-codes-by-cause.md)」を、[golem-parser ADR 0013](../golem-parser/adr/0013-splat-after-keyword-arguments.md) のステータスの行に「採択→設定の同じキーのコードは [docs/adr/0132](0132-setting-command-codes-by-cause.md)」を加える。

## 実装しないこと

- 誤りの後の扱いを変えること。
- `@manifest` の値の誤り（G02051）と上書きできないキー（G02050）を変えること。どちらも一つの原因に一つのコードである。
- `@style-def` の欄の値の誤り（G03006 など）を変えること。
- 展開の扱い。[docs/adr/0112](0112-spread-arguments.md) が決める。

## テスト設計

先に次のテストを書き、今のコードで失敗することを確かめてから実装する。
golem-eval の `FileSpec` で、それぞれの原稿の diagnostic のコードの並びを確かめる。

| 原稿 | 期待 |
| --- | --- |
| `@style-def\n` | G02052 |
| `@style-def paragraph\n` | G02052 |
| `@style-def paragraph a b\n` | G02052 |
| `@manifest line\n` | G02052 |
| `@manifest line paragraph-separator=line\n` | G02052 で、`paragraph-separator` の上書きは適用される |
| `@style-def table a\n` | G02117 |
| `@style-def paragraph a font=[= "x"]\n` | G02116 |
| `@style-def [= "paragraph"] a\n` | G02116 |
| `@manifest title=[= "x"]\n`、`@manifest paragraph-separator=[= "line"]\n` | G02116 |
| `@style-def paragraph a indent=1zw indent=2zw\n` | G02077 |
| `@style-def character x weight=bold weight=normal\n` | G02077 |
| `@manifest title=x title=x\n`、`@manifest paragraph-separator=line paragraph-separator=line\n` | G02077 |
| `@style-def paragraph a\n  x\n` | G02097 |
| `@manifest title=x\n  a\n`、`@manifest paragraph-separator=line\n  a\n` | G02097 |
| `@manifest\n` | G02115 |
| `@style-def "paragraph" "note"\n\n@style note\na\n` | 誤りがなく、段落スタイル `note` が当たる |
| `@style-def table a b\n` | G02052 と G02117 |

- G02052 だけを期待していた今のテスト（`FileSpec` の「the arguments of @style-def and @manifest are G02052」と「the keys and values of @manifest」、[golem-parser ADR 0013](../golem-parser/adr/0013-splat-after-keyword-arguments.md) の `@style-def character x weight=bold weight=normal` のテスト）を、上の期待に改める。
- 誤りの後の扱いが変わらないこと（上の表の上書きが適用されるか、捨てた `@style-def` の名前が段落スタイルにならないこと）を確かめる。
- docs/diagnostics.md のコードの一覧とコードの実装が一致することを検査する既存のテストが通ること。

## トレードオフ

G02052 を手がかりに誤りを探していた使い手やスクリプトは、新しいコードも見る必要がある。
1.0.0 まではコードの互換を守らないので、今のうちに分ける。

## 決めたことの記録

- **G02052 を分けること**：メンテナーが、[docs/adr/0112](0112-spread-arguments.md) の草稿の報告で、G02052 に複数の原因がまとまって残っている件に「一つの原因につき一つのエラーコード」と答えた（2026-11-04）。
- **同じキー**：メンテナーが、同じキーを書いたときはエラー（G02077）とすると決めた（2026-11-04）。
- **既存のコードを使うか**：この草稿は、同じ原因のコードがすでにある本体（G02097）と同じキー（G02077）はそれを使い、ほかを新しいコードにする案にした。

## 参考文献

なし
