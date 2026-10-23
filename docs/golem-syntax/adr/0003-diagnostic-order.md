# ADR 0003: diagnostics をコードの順を先にして並べる

ステータス: 採択

## 文脈

diagnostics の並び順は、[ADR 0001](0001-source-spans-and-diagnostics.md) の 66 行めと [ADR 0002](0002-notice-severity.md) の 77 行めが「ファイルの順、位置の順、コードの順」と定める。
docs/specifications.md の 501 行めと 1999 行めも同じ言葉で書く。
「位置」が開始位置だけを指すのか、終了位置も含むのかは書かれていない。

実装の [`sortDiagnostics`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-syntax/src/Golem/Syntax/Diagnostic.hs#L147-L163) は、(notice か, ファイル, 開始位置, 終了位置, コード, メッセージ, 残りの欄の `show`) の順で並べる。
最初のキーは、notice をエラーと警告の後に並べる規則（[ADR 0002](0002-notice-severity.md)）である。
エラーと警告は区別せず、混ぜて並べる。

テストは、この順を固定していない。
プロパティ「sorting ignores input order」（[modules/golem-syntax/test/Main.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-syntax/test/Main.hs#L143-L146)）は、入力の順に依らないことだけを見る。
並び順は、同じ入力から同じ diagnostics を得るという決定性（[docs/adr/0002](../../adr/0002-determinism.md)）の一部である。

メンテナーは、コードを先にして並べるほうが読みやすいと判断した。
大量の diagnostics を流し読みするときに、行頭のコードで種類を見分けられるからである。
同じコードの diagnostics がまとまれば、同じ原因の誤りを続けて読み、続けて直せる。

### 並び順を使う箇所

`sortDiagnostics` は次の箇所で使われている。

- 人が読む形式（[`renderHuman`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-syntax/src/Golem/Syntax/Render.hs#L106)）と JSON の形式（[`renderJson`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-syntax/src/Golem/Syntax/Render.hs#L171)）は、書く前に並べ直す。CLI のすべてのコマンドの diagnostics の出力がこの順になる。
- `golem build`、`golem check`、`golem preflight`（[golem-driver の `finishWith` と `preflight`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/src/Golem/Driver.hs#L726)）、`golem lint`（[golem-driver の `Golem.Driver.Lint`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/src/Golem/Driver/Lint.hs#L31)）、golem-cli の [app/Main.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-cli/app/Main.hs#L315)、golem-lint の [`Golem.Lint`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-lint/src/Golem/Lint.hs#L45)、golem-doc の [`Golem.Doc.Assemble`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-doc/src/Golem/Doc/Assemble.hs#L392) が、結果の一覧を並べる。テストが `brDiagnostics` などの一覧を断言するときは、この順で比べる。
- LSP（[`Golem.Lsp.Workspace`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-lsp/src/Golem/Lsp/Workspace.hs#L264)）は、評価の結果を `sortDiagnostics` で並べる。ただし、プロジェクトのファイルに公開する一覧は、ファイルごとに分けた後、[`sortOn (spanStart . diagSpan)`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-lsp/src/Golem/Lsp/Workspace.hs#L299) で開始位置の順に並べ直す。プロジェクトの外のファイル（[`looseDiags`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-lsp/src/Golem/Lsp/Workspace.hs#L280)）は、`sortDiagnostics` の順のまま公開する。

### 順に頼っている記述

[golem-doc ADR 0004](../../golem-doc/adr/0004-bibliography-formatting.md) の 129 行めは、読めない書誌のファイルの G03026 を、それが引き起こす `[cite ...]` の G02021 より先に並べると定め、その順をソートの規則（ファイル、位置、コード）に任せた。
G03026 は `manifest.toml`（FileId 0）の先頭に出るので、ファイルを先に比べる今の順では先に並ぶ。
docs/diagnostics.md の G03026 の節の「G03026 はそれらより先に並ぶ」と、golem-driver の [ReferencesSpec.hs のテスト「golem check reports G03026 before the G02021 it causes」](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/ReferencesSpec.hs#L247-L251) も、この順を書き、固定している。
コードを先にすれば、G02021 が G03026 より先に並ぶ。

## 実装すること

### 並び順

`sortDiagnostics` のキーを次の順にする。

1. notice か（notice を後にする）
2. コード
3. ファイル
4. 開始位置
5. 終了位置
6. メッセージ
7. 残りの欄の `show`（全順序にするための実装の詳細）

- notice をエラーと警告の後に並べる規則（[ADR 0002](0002-notice-severity.md)）は残す。コードより先に比べるので、notice のコードがエラーのコードより小さくても、notice は後に並ぶ。
- エラーと警告は、今と同じく区別しない。コードの順で混ざって並ぶ。重大度を並び順のキーには足さない。
- 人が読む形式と JSON の形式は、今と同じく同じ順で出す。
- LSP は、プロジェクトのファイルの一覧を `sortOn (spanStart . diagSpan)` ではなく `sortDiagnostics` で並べ、プロジェクトの外のファイルと同じ順で公開する。
- `sortDiagnostics` の注釈を新しい順に合わせて書き直す。

### 原因の後に並ぶ G03026

G03026 は、それが引き起こす G02021 の後に並ぶ。
並び順をコードで決める規則に例外を設けない。
G03026 のメッセージは書誌のファイルの名前を持つので、G02021 の後にあっても、二つを結びつけて読める。

### ドキュメント

- 仕様書（docs/specifications.md）の「構文木と diagnostics」の節の「エラーと警告のあいだは、ファイルの順、位置の順、コードの順で並べ」（1999 行め）を、「コードの順、ファイルの順、開始位置の順、終了位置の順、メッセージの順で並べ」に改め、この ADR へのリンクを付ける。エラーと警告を区別しないことも書く。
- 仕様書の 501 行めの「並びの順はファイルの順と位置の順に固定する」を、「並びの順はコードの順、ファイルの順、位置の順に固定する」に改める。
- docs/diagnostics.md の G03026 の節の「G03026 はそれらより先に並ぶ」を「G03026 はそれらの後に並ぶ」に改める。
- 開発者のマニュアルの `manual-dev/part1/02-diagnostics.gm` の並び順の節（104 行め）と、`manual-dev/part2/12-determinism.gm` の 36 行めを、新しい順に書き改める。
- 次のコミット済みの ADR のステータスの行に、この ADR へのリンクを書き足す。
  - [ADR 0001](0001-source-spans-and-diagnostics.md)：末尾に「、並び順は [ADR 0003](0003-diagnostic-order.md)」。
  - [ADR 0002](0002-notice-severity.md)：末尾に「、エラーと警告のあいだとお知らせどうしの並び順は [ADR 0003](0003-diagnostic-order.md)」。
  - [docs/adr/0002](../../adr/0002-determinism.md)：末尾に「、診断の出力順は [golem-syntax ADR 0003](../golem-syntax/adr/0003-diagnostic-order.md)」。
  - [golem-doc ADR 0004](../../golem-doc/adr/0004-bibliography-formatting.md)：末尾に「、G03026 と G02021 の並び順は [golem-syntax ADR 0003](../../golem-syntax/adr/0003-diagnostic-order.md)」。

## 実装しないこと

- 重大度（エラーと警告）で並べ分けること。
- 原因の diagnostic を、それが引き起こした diagnostic より先に並べる仕組み。
- 残りの欄（関連する位置、修正の候補、事実の欄）の順を仕様にすること。

## テスト設計

先に次のテストを書き、今の実装で失敗することを確かめてから `sortDiagnostics` を変える。

[modules/golem-syntax/test/Main.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-syntax/test/Main.hs) に、次の単体テストを足す。

- ファイル 0 の位置 40 の `G01001` と、ファイル 0 の位置 10 の `G05004` を与えると、`G01001` が先になる。今は位置の順で `G05004` が先なので失敗する。
- ファイル 1 の `G01001` と、ファイル 0 の `G05004` を与えると、`G01001` が先になる。今はファイルの順で `G05004` が先なので失敗する。
- [既存のテスト「errors and warnings stay mixed in the order of their positions」](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-syntax/test/Main.hs#L221-L225) を、「errors and warnings stay mixed in the order of their codes」に改める。位置 0 の警告 `G02005`、位置 5 のエラー `G02001`、位置 1 の notice `G02062` を並べた期待値を、`[w, e, n]` から `[e, w, n]` にする。重大度で並べ分けないことを固定する。今は位置の順で `[w, e, n]` なので失敗する。
- notice の `G02062`（ファイル 0、位置 0）とエラーの `G05004`（ファイル 1、位置 50）を与えると、エラーが先になる。notice を後にする規則を固定する。今の実装でも通る（[既存のテスト](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-syntax/test/Main.hs#L217-L220) と同じ性質）。
- 同じコードのあいだでは、ファイルの順、開始位置の順、終了位置の順、メッセージの順になる。それぞれ一つ前のキーだけが等しい二つの組で確かめる。今の実装でも通る。
- プロパティ：任意の diagnostics の列（[genDiagWithNotices](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-syntax/test/Main.hs#L259-L263)）を並べた結果で、隣り合う二つの (notice か, コード, ファイル, 開始位置, 終了位置, メッセージ) が減らない。今の実装では、位置がコードより先なので失敗する。
- `renderHuman` と `renderJson` に、位置の順とコードの順が逆の二つの diagnostics を与えると、コードの順で書く。今は失敗する。

ほかのモジュールのテストの期待値は、次のとおり変わる。

- golem-driver の [ReferencesSpec.hs の 247-251 行め](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/ReferencesSpec.hs#L247-L251)：期待値を `[G02021, G03026]` にし、テストの名前を「golem check reports G03026 after the G02021 it causes」に改める。先に書き換えると、今の実装で失敗する。
- golem-lsp の [test/Main.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-lsp/test/Main.hs)：lint の G05004（参照されていない `@label`）を前の行に、評価のエラー（G02 のコード）を後の行に持つプロジェクトのファイルの一覧が、G02 のコードを先にすること。今は開始位置の順なので失敗する。
- そのほかの一覧の期待値：`sortDiagnostics` を変えた後に全モジュールのテストを走らせ、落ちたテストの期待値を新しい順に直す。直したテストは、期待値の並びが変わっただけで、中身（コード、位置、メッセージの集合）が変わっていないことを、プルリクエストの説明に一覧で書く。
- 出力のゴールデン（golem-driver の [test/golden](https://github.com/tett23/golem/tree/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/golden)）は、PDF、EPUB、HTML、プレーンテキスト、雛形の中身であり、diagnostics を含まないので変わらない。
- [scripts/env-determinism/check.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/env-determinism/check.sh) は、同じコミットの二つの環境の標準エラー出力を比べるので、この変更で失敗しない。

## トレードオフ

- 原稿の順に読み進めたい書き手には、コードの順は読みにくい。同じファイルの前の行の誤りが、後の行の誤りより後に出ることがある。
- 原因の diagnostic が、それが引き起こした diagnostic の後に並ぶことがある。段階の番号はおおむね処理の順（01 構文、02 評価、03 プロジェクト）だが、プロジェクトの段階（03）の誤りが評価の段階（02）の誤りを引き起こす G03026 と G02021 のように、逆になる組がある。
- 利用者の見る順が変わる。JSON の出力を位置の順に読んでいたツールは、自分で並べ直す必要がある。
- LSP の公開する一覧の順も変わる。エディターは問題の一覧を自分で並べ直すことが多いので、見た目への影響は小さい。

## 参考文献

- [ADR 0001](0001-source-spans-and-diagnostics.md)
- [ADR 0002](0002-notice-severity.md)
- [docs/adr/0002](../../adr/0002-determinism.md)
- [golem-doc ADR 0004](../../golem-doc/adr/0004-bibliography-formatting.md)
