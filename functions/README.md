# 関数の見本

このディレクトリには、Golem の関数を書く言語 Emet（拡張子 `.emet`）で書いた関数の見本を置く。
関数は、出版社や編集部で本を作る人と組版のオペレーターが、自分たちの本のために書くものである（使い手のマニュアルの付録 J「関数を書く言語 Emet」）。
ほかの人に配って使ってもらう機能はプラグインとして作り、その見本は [`plugins/`](../plugins/) にある。
関数には配布の仕組みがないので、使うときはファイルをプロジェクトにコピーする。

Emet は、Golem の 1.x のあいだ実験的な機能である。
二つ目の数が上がったバージョンで、ここの関数が動かなくなることがある。

## ファイル

| ファイル | 関数 |
| --- | --- |
| [`numbers.emet`](./numbers.emet) | `commas`（3 桁ごとのカンマ）、`withUnits`（「1億2345万6789」の書き方）、`yen`（金額）。ほかのファイルが使う `kanji`（位取りの漢数字） |
| [`dates.emet`](./dates.emet) | `wareki`（和暦）、`year-both`（「2026（令和8）年」）、`isoDate`（ISO 8601 の日付を「2026年11月8日」に）、`isoWareki`（ISO 8601 の日付を和暦に） |
| [`colophon.emet`](./colophon.emet) | `isbn`（検査数字を計算し、確かめる ISBN）、`price`（「定価1,980円（本体1,800円＋税10%）」）、`edition`（「初版第3刷」）、`issued`（発行の行）、`printings`（刷の履歴の段落） |
| [`text.emet`](./text.emet) | `zenkaku`（半角の英数字を全角に）、`mama`（「ママ」のルビ）、`epigraph`（題辞の段落） |

`dates.emet` は `numbers.emet` を、`colophon.emet` は `numbers.emet` と `dates.emet` を `import` で使う。
各関数の使い方と結果の例は、ファイルの中の関数の前のコメントにある。

数を漢数字で組むコマンドは見本のプラグイン `kansuji` に、初出の語にルビを付けるフィルタは `first-ruby` にあるので、ここには置かない。

## 使い方

このディレクトリを、プロジェクトのフォルダの直下に `functions/` としてコピーする。
`import` のパスはプロジェクトのフォルダからの相対パスで、ファイルどうしは `functions/numbers.emet` のように互いを指すので、置き場所を変えるときは `import` の行も書き換える。
使わないファイルは消してよいが、`import` されているファイルは残す。

原稿からは `@import` で取り込み、`as` の後の名前を前に付けて呼ぶ。
次の原稿は、空行で段落を区切るプロジェクト（`paragraph-separator = "blank-line"`）のものである。

```
@import functions/colophon.emet as colophon

[colophon.issued "2026-11-08"]

[colophon.isbn 978-4-00-310101]

[colophon.price 1800]
```

三つの段落は、次のように組まれる（どれも `colophon.emet` の例にある）。

```
2026年11月8日　初版第1刷発行

ISBN978-4-00-310101-8

定価1,980円（本体1,800円＋税10%）
```

ここの関数は、ファイルを読まないので、`manifest.toml` の `[functions.requires]` は要らない。
`text.emet` の `epigraph` は、段落スタイル `epigraph` と `epigraph-source` を使うので、`style.toml` に二つを定義する。

```toml
[paragraph-styles.epigraph]
indent = "2zw"

[paragraph-styles.epigraph-source]
align = "right"
```

## テスト

関数の前のコメントの `-- >>> ` の行が呼び出しの例で、その後ろのコメントの行が、その例を組んだプレーンテキストである。
golem-driver のテスト（[`modules/golem-driver/test/FunctionLibrarySpec.hs`](../modules/golem-driver/test/FunctionLibrarySpec.hs)）は、例を一つずつ章にして組み、プレーンテキストが例のとおりになることを確かめる。
原稿から呼べる関数（`pub inline`、`pub block`、`pub fn`）には、例が一つ以上なければならない。
ほかに、どのファイルも `golem fmt` の整形のとおりであること、`golem lint` が何も報告しないことも確かめる。

```sh
cabal test golem-driver:test:golem-driver-test --test-option=-p --test-option='/functions of the repository/'
```

## ライセンス

このディレクトリの関数は、リポジトリのコードと同じく [MIT License](../LICENSE) で公開する。
マニュアルの原稿（`manual/`）は CC0 1.0 だが、ここの関数はプロジェクトにコピーして動かすプログラムなので、コードと同じ扱いにした。
MIT License の条件により、コピーしたファイルには、著作権の表示と許諾の文（[`LICENSE`](../LICENSE)）を添える。
