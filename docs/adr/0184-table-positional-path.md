# ADR 0184: `@table` のパスを最初の引数に書く

ステータス: 採択

## 文脈

ファイルを読むブロックコマンドは三つあり、パスの書き方がそろっていない。

- `@figure` はパスを位置引数で書く。位置引数がちょうど一つでなければ G02032 とする（[`figure`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-eval/src/Golem/Eval/File.hs#L1395-L1445)）。
- `@listing` はパスを位置引数で書く。`src=` でも書けるが廃止予定であり、notice（G02065）を出す（[golem-syntax ADR 0002](../golem-syntax/adr/0002-notice-severity.md)、[`listing`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-eval/src/Golem/Eval/File.hs#L1767-L1778)）。
- `@table` はパスを `src=` だけで受け付ける（[`csvTable`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-eval/src/Golem/Eval/File.hs#L1486-L1508)）。

[golem-syntax ADR 0002](../golem-syntax/adr/0002-notice-severity.md) は、`@listing` の位置引数を正とし、`@table` に位置引数を足すことは「記法の追加が要る」として後に回した。
ロードマップの v0.1.0-rc4 の「`@table` の位置引数のパス」は、この残りである。

### 今の振る舞い

v0.1.0-rc3 の `golem`（`~/.local/bin/golem`）で、`golem new` で作ったプロジェクトに `data/t.csv` と `data/other.csv` を置いて確かめた（2026-11-06）。

| 原稿 | 結果 |
| --- | --- |
| `@table data/t.csv` | G02034（`@table には src が必要です`）。位置引数は読まない |
| `@table data/other.csv src=data/t.csv` | diagnostics なしで `data/t.csv` の表を組む。位置引数は黙って捨てる |
| `@listing data/other.csv src=data/t.csv` | `data/other.csv` を取り込み、`src=` に G02065 の notice を出す。`src=` のパスは黙って捨てる |
| `@figure a.png b.png` | G02032（`@figure には画像のパスを一つ書きます`） |

`@listing` に慣れた書き手が `@table data/t.csv` と書くと、G02034 のメッセージは `src` を求めるので直し方は分かる。
しかし、二つめの行のように位置引数と `src=` を両方書くと、位置引数が黙って捨てられ、書き手の意図と違う表が組まれる。

ビルドが読むファイルを集める `assetRefs` も、`@table` では `src=` だけを見る（[`assetRefs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver.hs#L655-L675)）。
LSP は、この関数で、評価し直すかどうかを決め、監視する表のファイルを集める。

## 実装すること

### 記法

`@table` のパスを最初の位置引数に書く。

```
@table data/sizes.tsv align=left,right,right
@table data/export.txt format=tsv
```

- パスは、`@figure` と `@listing` と同じく、語か文字列で書く。
- `src=` は廃止予定とし、新しい notice（G02129）を出す。メッセージは G02065 にならい「`@table` の `src=` は廃止予定であり、パスを最初の引数に書く」旨の文とする（「メンテナーが決めること」の 1）。位置は `src=` の引数である。読む表は今と変わらない。G02065 を共有しないのは、コマンドが違えば原因も違うからである（一つのコードに一つの原因）。
- パスが二つ以上あるとき（位置引数が二つ以上か、位置引数と `src=` の両方）は、新しいエラー（G02130、`@table にはファイルのパスを一つ書きます`）とし、表を組まない（「メンテナーが決めること」の 2）。位置はコマンドの行である。`src=` の notice（G02129）も、あわせて出す。
- パスがないときは、今のとおり G02034 とし、メッセージを `@table にはファイルのパスが必要です` に変える（`@listing` の G02036 と同じ形）。
- `format`、`align`、`cells` は今のまま、キーワード引数で書く。`format` を省いたときに拡張子で形式を決める規則も、位置引数のパスに当てる。

新しいコードの番号は、ほかの草案と重ならないよう、採択の前に確かめて振り直す。

### ファイルの収集と LSP

- `assetRefs` は、`@table` の最初の位置引数と `src=` の両方を集める（`@listing` と同じ形）。これで、位置引数で書いた表のファイルも、ビルドが読み、LSP が監視する。
- LSP の補完と diagnostics は、評価の結果を使うので、ほかに変えるところはない。

### ドキュメント

- [docs/markup.md](../markup.md) の「表」の節の例と引数の表を、位置引数のパスに書き換え、`src=` を廃止予定と書く。ブロックコマンドの一覧の `@table` の行も同じ。
- [docs/diagnostics.md](../diagnostics.md) に G02129 と G02130 を足し、G02034 のメッセージと直し方を改める。
- 使い手のマニュアルの `@table src=` の説明と例（`manual/chapters/03-markup.gm` と `manual/appendices/a-markup.gm`）を、位置引数に書き換える。マニュアルの原稿が使う `@table` も位置引数にするので、マニュアルを組んでも G02129 は出ない。
- [golem-eval ADR 0004](../golem-eval/adr/0004-tsv-tables.md) はコミット済みなので書き換えず、ステータスの行を「採択→`@table` のパスの書き方は docs/adr/0184」にし、この ADR へのリンクを付ける。

## 実装しないこと

- `src=` をエラーにすること。いつエラーにするかは、`-` で区切った範囲（G02108）と同じく、v0.1.0-rc4 の「1.0 で約束すること」の ADR が廃止の手順を決め直した後に決める（[docs/roadmap.md](../roadmap.md) の「`-` で区切った範囲をエラーにする時期」）。
- `@listing` で位置引数と `src=` を両方書いたときに `src=` のパスを黙って捨てること（上の表の三つめの行）を誤りにすること。`@listing` の振る舞いを変えるので、別の ADR にする。ロードマップに項目を足すことを提案する。
- `@table` に未知のキーワード引数（`foo=1`）を書いたときに diagnostics を出すこと。今は黙って無視する（2026-11-06 に v0.1.0-rc3 の `golem check` で確かめた）。ほかのコマンドにも同じ振る舞いがあり、この ADR の範囲を超える。
- `golem fmt` が `src=` を位置引数に書き換えること。fmt は AST を変えない（[仕様書の「fmt」](../specifications.md#fmt)）。

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。

golem-eval のテストでは、次のことを確かめる。

- `@table data/t.csv` が、`@table src=data/t.csv` と同じ IR の表になり、diagnostics を出さないこと。今は G02034 になるので失敗する。
- `@table src=data/t.csv` が今と同じ表を組み、`src=` の引数の位置に G02129 の notice を出すこと。
- `@table data/a.csv src=data/b.csv` と `@table data/a.csv data/b.csv` が G02130 になり、表を組まないこと。前者には G02129 も出ること。
- `@table` だけの行が G02034 になり、メッセージが新しい文であること。
- `@table data/export.txt format=tsv` と、`format` を省いた `@table data/x.TSV` が、`src=` と同じ形式で読まれること。

golem-driver のテストでは、`assetRefs` が `@table data/t.csv` から `(data/t.csv, UseTable)` を返すことを確かめる。

golem-cli のテストでは、位置引数で書いた `@table` のプロジェクトを `golem build` で組み、`src=` で書いた同じプロジェクトと、四つのターゲットの出力のバイト列が同じであることを確かめる。

golem-lsp のテストでは、位置引数で書いた `@table` の表のファイルが、監視するファイルに入ることを確かめる。

## トレードオフ

`src=` の書き方は、廃止予定の notice を出しながら残る。
同じことを書く方法が二つある期間は続くが、v0.1.0-rc3 までに書いた原稿は、書き換えずに組める。

G02130 を足すので、今は黙って `src=` の表を組む原稿（位置引数と `src=` の両方を書いた原稿）が、エラーで止まるようになる。
どちらのパスが正しいかを処理系は知らないので、黙って一方を選ぶより、書き手に直させる。
仕様書の「緩い規則より厳しい規則」に従う。

一方、`@listing` は同じ書き方で今のまま `src=` を捨てるので、二つのコマンドの扱いが食い違う期間が残る。

## 決めたことの記録

- **`@table` の位置引数のパスを検討すること**（ロードマップ）：`@listing` が位置引数を正とし `src=` を廃止予定にしたので、`@table` でもパスを最初の引数に書けるようにするかを検討し、記法の追加が要るので ADR で決める。
- **すべての項目**（2026-11-07、メンテナー）：「推奨で問題ない」。「メンテナーが決めること」の 1 から 3 を、すべて推奨のとおりとした。

## メンテナーが決めること

すべて決めた（「決めたことの記録」）。

1. **`src=` の扱い**：決めた。推奨のとおり、位置引数を正とし、`src=` を廃止予定の notice（G02129）にする（「決めたことの記録」）。`@listing` と同じ手順になる。退けた案は、`src=` をすぐにエラーにすること（v0.1.0-rc3 までの原稿が、版を上げただけで組めなくなる）と、二つの書き方をどちらも正とし続けること（同じことを書く方法が二つ残り、`@listing` と食い違う）。
2. **パスが二つあるとき**：決めた。推奨のとおり、エラー（G02130）にして表を組まない（「決めたことの記録」）。`@figure` の G02032 と同じ扱いになる。退けた案は、`@listing` に合わせて位置引数を選び `src=` を捨てること（黙って一方を捨てると、書き手が意図と違う表に気づかない）と、`src=` を選ぶ今の振る舞いを残すこと（位置引数を正とする方針と逆になる）。
3. **新しいコードの番号**：決めた。推奨のとおり、G02129（notice）と G02130（エラー）の二つを足す（「決めたことの記録」）。G02065 を共有する案は、一つのコードに一つの原因の原則に反するので退ける。

## 参考文献

- [golem-syntax ADR 0002](../golem-syntax/adr/0002-notice-severity.md)
- [golem-eval ADR 0004](../golem-eval/adr/0004-tsv-tables.md)
- [docs/roadmap.md](../roadmap.md) の「`@table` の位置引数のパス」
