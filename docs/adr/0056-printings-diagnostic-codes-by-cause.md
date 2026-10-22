# ADR 0056: `@printings` の誤りを原因ごとのコードに分ける

ステータス: 採択

## 文脈

[ADR 0033](0033-colophon-contributors-and-printings.md) は、発行の履歴のブロック `@printings` を決めた。
誤りについては、次の三つを書いた。

- 引数と本体（散文スロット）：ほかのブロックコマンドと同じ引数の誤りとする。
- `[metadata] language` が `ja` でない本：G0276（エラー）とする。メッセージは `@printings は日本語の本（language = "ja"）でだけ使えます` である。
- `printings` のない本：G0276 とする。メッセージは `マニフェストに [[metadata.printings]] がありません` である。

ブロックコマンドに共通の引数の誤りのコードはない。
golem-eval の `Golem.Eval.File` では、コマンドごとに自分のコードを出す（`@page-break` と `@column-break` は G0258、`@no-page-break`、`@need-lines`、`@page-lines` は G0270）。
ADR の文言からは、`@printings` の引数の誤りがどのコードかが決まらない。

実装（`Golem.Eval.File` の `printingsBlock`）は、引数か本体があれば G0276 を出し、メッセージを「@printings は引数も本体も取りません」とする。
仕様書、`docs/diagnostics.md` の G0276 の節、使い手のマニュアルの付録 E も同じである。
今の G0276 は、引数、本体、本の言語、`printings` の欠けの四つの原因を一つのコードで出している。

### 一つのコードに一つの原因

メンテナーは、異なる原因に一つの diagnostic のコードを共有させないと決めた。
コードから原因が一つに決まらないと、利用者は `golem explain` の説明のどの原因が自分に当たるかを探すことになり、混乱するためである。

四つの原因は、直す場所も違う。

- 引数：原稿の `@printings` の行を直す。
- 本体：原稿の `@printings` の下の字下げした行を直す。
- 本の言語：マニフェストの `[metadata] language` を直すか、`@printings` を使わない。
- `printings` の欠け：マニフェストに `[[metadata.printings]]` を書く。

## 実装すること

`@printings` の誤りを、原因ごとに一つのコードにする。
どれも重大度はエラーで、dev と prod の両方でエラーとする。
どれか一つでもあれば、`@printings` は何も組まない。

| コード | 対象 | メッセージ | 位置 |
|---|---|---|---|
| G0296 | 引数（位置引数、キーワード引数、展開した引数のどれでも） | `@printings は引数を取りません` | `@printings` の行 |
| G0297 | 本体 | `@printings は本体を持てません` | 本体の最初のブロック |
| G0276 | 本の言語が `ja` でない | `@printings は日本語の本（language = "ja"）でだけ使えます` | `@printings` の行 |
| G0298 | `[[metadata.printings]]` がない | `マニフェストに [[metadata.printings]] がありません` | `@printings` の行 |

- G0296 は「引数を取らないコマンドに引数を書いた」、G0297 は「本体を持てないコマンドに本体を書いた」という原因のコードであり、メッセージは `<名前> は引数を取りません`、`<名前> は本体を持てません` の形とする。直し方がコマンドによらず同じなので、同じ原因のほかのコマンドにも使う（改ページのコマンドは [ADR 0060](0060-page-break-command-codes-by-cause.md)）。
- G0276 は、本の言語の誤りだけに絞る。題を `@printings を組めません` から `@printings は日本語の本でだけ使えます` に改める。
- 四つは互いに独立に判定し、当たるものをすべて、表の順に出す。今の実装は最初に当たったものだけを出すが、一つを直すと別の誤りが現れる、という繰り返しを避ける。
- 02 の区分は G0295 まで使っている。G0296、G0297、G0298 は、origin の各ブランチと、この worktree のほかの草稿で使われていない。

### ADR のステータス

- [ADR 0033](0033-colophon-contributors-and-printings.md) のステータスの行を次のようにする。

  ```
  ステータス: 採択→`@printings` の誤りのコード（G0296、G0297、G0298 と G0276 の範囲）は [ADR 0056](0056-printings-diagnostic-codes-by-cause.md)
  ```

### ドキュメント

- `docs/diagnostics.md` に G0296、G0297、G0298 の節を足し、G0276 の節を本の言語の誤りだけに改める。
- 仕様書の「本文からの参照」の節の `@printings` の段落を、四つのコードに改め、この ADR へのリンクを付ける。
- 使い手のマニュアルの付録 E の G0276 の項を改め、G0296、G0297、G0298 の項を足す。

## 実装しないこと

- ブロックコマンドに共通の引数の誤りのコードを設けること。原因はコマンドごとに違う直し方を持つので、コマンドごとのコードのままとする。
- ほかのコマンドの誤りのコードを分けること。改ページのコマンド（G0258、G0270）は [ADR 0060](0060-page-break-command-codes-by-cause.md) で分ける。

## テスト設計

次のテストを golem-eval の `test/FileSpec.hs` に先に書き、失敗させてから実装する。
今の「a book not in Japanese, or without printings, is G0276 and sets nothing」と「an argument or a body is an error and sets nothing」は、新しいコードに合わせて書き直す。

- `@printings 1` が、G0296 を一つだけ出し、メッセージが `@printings は引数を取りません` で、何も組まないこと。
- `@printings key=1` が、G0296 を一つだけ出すこと。
- 本体のある `@printings` が、G0297 を一つだけ出し、位置が本体の最初のブロックで、何も組まないこと。
- 引数と本体の両方を持つ `@printings` が、G0296 と G0297 をこの順に出すこと。
- 日本語でない本の `@printings` が、G0276 だけを出すこと。
- `printings` のない日本語の本の `@printings` が、G0298 だけを出し、メッセージが `マニフェストに [[metadata.printings]] がありません` であること。
- `printings` のない日本語でない本で `@printings 1` を書くと、G0296、G0276、G0298 がこの順に出ること。

golem-syntax では、次を確かめる。

- docs の diagnostic の一覧とコードの一致の検査が、G0296、G0297、G0298 を含めて通ること。

## トレードオフ

- コードが三つ増える。代わりに、コードを見れば原因と直す場所が一つに決まる。
- 四つを独立に判定するので、一つの `@printings` に複数のエラーが出ることがある。どれも直す必要のある誤りなので、まとめて知らせる。
- G0276 の範囲が狭まる。G0276 で引数の誤りを抑えるような使い方はできない（エラーは `silence-notices` で抑えられない）ので、利用者の設定は変わらない。

## 参考文献

- [ADR 0033](0033-colophon-contributors-and-printings.md)
- [ADR 0030](0030-manual-page-break-control.md)（G0270）
