# ADR 0186: `golem fmt` で表のファイルの BOM と改行を直す

ステータス: 採択（未実装）

## 文脈

`@table` が読む CSV と TSV のファイル（以下、表のファイル）は、読み込みのときに先頭の BOM を読み飛ばし、行の終わりに LF と CRLF を受け付ける。
LF の前にない CR（単独の CR）だけはエラー（G02082）にする（[golem-eval ADR 0004](../golem-eval/adr/0004-tsv-tables.md)、[`checkTableText`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-parser/src/Golem/Parser/Read.hs#L63-L73)）。
表計算のソフトが書き出した CSV には、BOM と CRLF が付いていることが多い。
読み込みが受け付けるので、BOM と CRLF はリポジトリに残り続ける。
単独の CR は読み込みで止まるが、直す道具がない。

原稿のほうは、`golem fmt` の前処理が BOM を取り除き、CRLF と単独の CR を LF に直す（[golem-fmt ADR 0003](../golem-fmt/adr/0003-lone-cr-to-lf.md)、[golem-fmt ADR 0004](../golem-fmt/adr/0004-fmt-without-arguments-fixes-cr.md)）。
ロードマップの v0.1.0-rc4 の「fmt で表のファイルの BOM と改行を直す」は、同じことを表のファイルにも行う項目である。

### 今の `golem fmt` と表のファイル

v0.1.0-rc3 の `golem`（`~/.local/bin/golem`）で確かめた（2026-11-06）。
`golem new` で作ったプロジェクトに、BOM と CRLF の CSV、単独の CR を引用符の中に持つ CSV を置き、`@table src=` で読ませた。

- 引数なしの `golem fmt --check` も `golem fmt` も、終了コード 0 で終わり、表のファイルに触れない。引数なしの `golem fmt` が整形するのは、プロジェクトのソース（章と `@import` で読むファイル）と `.emet` だけである（[`formatFiles`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-cli/app/Main.hs#L436-L470)）。
- 単独の CR を持つ表のファイルがあっても、引数なしの `golem fmt` は止まらない。G02082 を出すのは golem-driver の表のファイルを読む段階であり、`golem fmt` が使う `loadProjectWith` は表のファイルを読まないからである（[`LoadedAssets`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver.hs#L503-L512)）。ロードマップは「表のファイルの G02082 で読み込みが止まっても整形できるようにする」ことを挙げているが、今の読み込みはそもそも止まらない。

一方、表のファイルを引数に渡すと、`golem fmt` はそれを原稿として整形し、セルの中身を壊す。
`.emet` でないファイルは、すべて原稿の整形（`Golem.Fmt.format`）にかけるからである。

| 引数に渡したファイル | `golem fmt` の後 | 結果 |
| --- | --- | --- |
| TSV の `  x\t\ty  ` の行 | `  x\t\ty` | 最後のセルの末尾の空白が消える |
| TSV の `\tz` の行（最初のセルが空） | `  z` | 行頭のタブが二つの空白になり、セルが一つ減る。`golem check` が G02085 になる |
| CSV の `"x\n\n\ny  ",1` | `"x\n\ny",1` | 引用符の中の空行が一つになり、末尾の空白が消える |

どれも、原稿の整形の規則（行頭の字下げのタブ、行末の空白、空行の数）が表のファイルに当たったものである。
`golem fmt --check` も、これらのファイルを整形されていないファイルとして示す。

### 引用符の中の CRLF

CSV の引用符の中の改行は、セルの中の改行である。
CRLF を LF に直してもセルの中身が変わらないかは、読み手が引用符の中の CRLF をどう読むかで決まる。

読み手（`parseCsv`）は、引用符の中の CRLF を LF にしてセルに入れる（[`parseCsv`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-eval/src/Golem/Eval/File.hs#L1653-L1699)）。
`golem inspect --as ir` で確かめた。
BOM と CRLF を持つ `a,b\r\n"x\r\ny",2\r\n` と、LF だけの `a,b\n"x\ny",2\n` は、どちらも見出しの行が `a`、`b`、本体のセルが `"x\ny"` と `"2"` の同じ表になる。
TSV も、BOM と CRLF を持つ `a\tb\r\nx\t\r\n` と、LF だけの `a\tb\nx\t\n` が、同じ表（本体のセルは `"x"` と空）になる。

引用符の中の単独の CR は、今は G02082 で止まる（`a,b\n"p\rq",2\n` で確かめた）。
LF に直すと、セルの中の改行として `"p\nq"` を持つ表になる。

## 実装すること

### 表のファイルの前処理

golem-fmt に、表のファイルの前処理を足す（`Golem.Fmt.formatTable :: Text -> Text`、名前は実装で決める）。
前処理は次の三つだけであり、この順に行う。

- 先頭の BOM（U+FEFF）を一つ取り除く。
- CRLF を LF に直す。
- 残った単独の CR を LF に直す。CRLF を先に直すので、CRLF は二つの改行にならない。

原稿の前処理（`preprocess`）が行う、行頭の字下げのタブを空白に直すことは行わない。
TSV のタブはセルの区切りだからである。
空白、空行、タブ、引用符、セルの区切りには触れない。
CSV と TSV で前処理は同じなので、`golem fmt` は形式（`format`）を見分けなくてよい。

上の「引用符の中の CRLF」のとおり、BOM と CRLF を直しても、読み手が作る表は変わらない。
単独の CR を直すと、G02082 で止まっていた表が組めるようになる。

### 引数なしの `golem fmt`

引数なしの `golem fmt` は、整形するファイルに、プロジェクトのソースが `@table` で読む表のファイルを加える。

- 表のファイルは、ビルドと同じく `assetRefs` で集め、使い方が `UseTable` のファイルとする（[`assetRefs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver.hs#L655-L675)）。golem-cli はすでに golem-driver に依存しているので、モジュールの依存は変わらない。
- パスを式で書いた `@table` の表のファイルは、`assetRefs` が集めないので整形しない。ビルドが前もって読むファイルと同じ範囲である。
- 同じファイルを `@table` と `@listing` の両方が読む場合も、表のファイルとして前処理にかける。`@listing` は取り込む内容を行に分けて使うので、行の終わりの CR が消えるほかは変わらない（推測。実装で `@listing` の出力を比べて確かめる）。
- ないファイル、プロジェクトのルートの外を指すファイルは、整形しない。diagnostics はビルドが出すので、`golem fmt` は出さない。
- UTF-8 として読めない表のファイルは、原稿と同じく `UTF-8 として読めないため整形しません` を出し、終了コードを 1 にする。
- G02082 を出す表のファイル（単独の CR を持つもの）も、前処理にかける。G02082 は golem-driver の読み込みの段階の diagnostic であり、`golem fmt` の読み込みでは出ないので、[golem-fmt ADR 0004](../golem-fmt/adr/0004-fmt-without-arguments-fixes-cr.md) のような読み直しは要らない。この性質を壊さないよう、表のファイルを集めるのに golem-driver の読み込みの段階（`loadAssets`）を使わない。
- 原稿の G01003 で読み込みが止まったときの読み直し（[golem-fmt ADR 0004](../golem-fmt/adr/0004-fmt-without-arguments-fixes-cr.md)）は今のままとし、読み込めた後のソースから表のファイルを集める。

### 引数に渡したファイル

引数に渡したファイルは、拡張子で扱いを分ける（「メンテナーが決めること」の 1）。

- 拡張子が `.csv` か `.tsv` のファイル（大文字と小文字を区別しない）は、表のファイルの前処理だけをかける。
- 拡張子が `.emet` のファイルは、今のとおり `.emet` の整形にかける。
- ほかのファイルは、今のとおり原稿として整形する。

`.txt` のように別の拡張子の表のファイル（`format=tsv` で読ませるもの）を引数に渡すと、原稿として整形され、上の表のようにセルを壊す。
これは引数なしの `golem fmt` では起きない（`assetRefs` で表のファイルと分かる）。
仕様書とマニュアルには、別の拡張子の表のファイルは引数なしの `golem fmt` で直すことを書く。

### `golem fmt --check`

`--check` は、BOM、CRLF、単独の CR のどれかを持つ表のファイルを、整形されていないファイルとしてパスを示し、書き換えない。
終了コードは、原稿と同じく、整形されていないファイルが一つでもあれば 1 である。

### ドキュメント

- 仕様書の「fmt」の節に、表のファイルの前処理と、引数なしと引数ありの扱いを書く。「`golem fmt` は TOML を整形しない」の段落の近くに、表のファイルでは BOM と改行のほかを直さないことを書く。
- 仕様書の `@table` の節（表のファイルの読み方）に、`golem fmt` で BOM と改行を直せることを書く。
- [docs/diagnostics.md](../diagnostics.md) の G02082 の直し方に、`golem fmt` で LF に直せることを足す。
- 使い手のマニュアルの `golem fmt` の説明に、表のファイルを直すことと、別の拡張子の表のファイルの注意を書く。
- [golem-eval ADR 0004](../golem-eval/adr/0004-tsv-tables.md) と [golem-fmt ADR 0004](../golem-fmt/adr/0004-fmt-without-arguments-fixes-cr.md) はコミット済みなので書き換えず、ステータスの行から、この ADR へのリンクを付ける。

## 実装しないこと

- 読み込みが BOM と CRLF を受け付けることをやめること。今のとおり受け付ける。表計算のソフトの書き出しをそのまま読めることのほうが大事である。
- 単独の CR を読み込みで LF とみなすこと。今のとおり G02082 とする（仕様書の「緩い規則より厳しい規則」）。
- セルの中身を整えること（前後の空白、引用符の付け方、空行、セルの区切りの統一、末尾の改行の有無）。
- `.csv` と `.tsv` でない拡張子の表のファイルを、引数に渡したときに見分けること（「メンテナーが決めること」の 1）。
- `@listing` が読むだけのファイルを整形すること。`@listing` のファイルは Golem 以外のソースであり、改行の形はそのファイルの持ち主が決める。
- G02082 の diagnostic に、`golem fmt` で直す修正案を付けること。修正案は今は原稿のファイルの G01003 にだけ付く。付けるかは、修正案の仕組みとあわせて別に決める。
- LSP の整形の要求で表のファイルを整形すること。LSP は拡張子が `.gm` でないファイルを原稿として扱わない。

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。

golem-fmt のテストでは、次のことを確かめる。

- `formatTable "\xFEFFa,b\r\n1,2\r\n"` が `"a,b\n1,2\n"` を返すこと。
- `formatTable "a,b\r1,2\r"` が `"a,b\n1,2\n"`、`formatTable "a\r\r\nb"` が `"a\n\nb"` を返すこと（CRLF が二つの改行にならない）。
- `formatTable "a\tb\n\tz  \n"` と、空行、末尾の空白、引用符を含む CSV が、そのまま返ること。今の `format` ではタブと空白が変わる。
- 二度かけても結果が変わらないこと（プロパティテスト）。
- 単独の CR を含まない入力では、前処理の前と後の文字列を `parseCsv` と `parseTsv` で読んだ表が同じになること（プロパティテスト）。golem-fmt は golem-eval に依存しないので、このテストは golem-cli のテストスイートに置き、テストスイートの依存に golem-fmt を足す（golem-cli の本体はすでに golem-fmt に依存している。依存の変更はこの ADR で決める）。

golem-cli のテストでは、次のことを確かめる。

- BOM と CRLF の CSV、CRLF の TSV、単独の CR の CSV を `@table` で読むプロジェクトで、引数なしの `golem fmt` が三つを LF だけにし、続く `golem check` が G02082 を出さないこと。今はどれも書き換えないので失敗する。
- 同じプロジェクトで、`golem fmt --check` が三つのパスを示して終了コード 1 になり、書き換えないこと。
- `golem fmt data/s.tsv`（`\tz` の行を持つ TSV）が、行頭のタブを残すこと。今は二つの空白になるので失敗する。
- `golem fmt data/t.CSV` が表のファイルとして扱われること。
- `format=tsv` で読む `data/export.txt` を、引数なしの `golem fmt` が表のファイルとして直すこと。
- 原稿とならぶ `@listing` だけが読むファイルの CRLF を、引数なしの `golem fmt` が変えないこと。
- 原稿の CR で読み込みが止まり、表のファイルにも CRLF があるプロジェクトで、引数なしの `golem fmt` が両方を直すこと。

## トレードオフ

拡張子で表のファイルを見分けるので、引数に渡した `.txt` の表のファイルは、今のとおり原稿として整形され、セルを壊す。
引数があるときもプロジェクトを読み込んで `@table` の参照を引けば防げるが、引数に渡したファイルの扱いが、カレントのディレクトリのプロジェクトの内容で変わるようになる。
同じ引数で同じ結果になるほうを選んだ（「メンテナーが決めること」の 1）。

表のファイルの改行がリポジトリで LF にそろうので、表計算のソフトで開いて書き出し直すと、また CRLF に戻ることがある。
`golem fmt --check` を CI で動かしていれば、そのたびに見つかる。

## 決めたことの記録

- **fmt で表のファイルの BOM と改行を直すこと**（ロードマップ）：`golem fmt` で、`@table` が読む CSV と TSV のファイルの先頭の BOM を取り除き、CRLF と単独の CR を LF に直す。表のファイルでは BOM と改行のほかを直さず、セルの中身は変えない。引用符の中の CRLF をどう読むかを確かめること、`--check`、引数なしの `golem fmt`、G02082 で止まった表のファイル、引数に渡したファイルの扱いを ADR で決める。
- **すべての項目**（2026-11-07、メンテナー）：「推奨で問題ない」。「メンテナーが決めること」の 1 から 3 を、すべて推奨のとおりとした。

## メンテナーが決めること

すべて決めた（「決めたことの記録」）。

1. **引数に渡したファイルの見分け方**：決めた。推奨のとおり、拡張子が `.csv` か `.tsv`（大文字と小文字を区別しない）のファイルを表のファイルとする（「決めたことの記録」）。同じ引数なら、どのディレクトリで動かしても同じ扱いになる。退けた案は、引数があるときもプロジェクトを読み込み、`@table` が読むファイルを表のファイルとすること（引数のファイルの扱いがプロジェクトの内容で変わり、プロジェクトの外のファイルでは働かない）と、`.gm` でも `.emet` でもないファイルをすべて表のファイルとすること（拡張子のない原稿や `.txt` の原稿の扱いが変わる。今の `golem fmt` は拡張子を問わず原稿として整形する）。
2. **`@listing` のファイル**：決めた。推奨のとおり、`@listing` だけが読むファイルは整形しない（「決めたことの記録」）。Golem の原稿でも表でもないソースであり、CRLF が意味を持つこともある。同じファイルを `@table` も読むなら、表のファイルとして直す。退けた案は、`@listing` のファイルの改行も直すこと（Golem の外のソースのファイルを書き換える）。
3. **単独の CR を直すこと**：決めた。推奨とロードマップのとおり、LF に直す（「決めたことの記録」）。原稿の単独の CR と同じ扱いである（[golem-fmt ADR 0003](../golem-fmt/adr/0003-lone-cr-to-lf.md)）。引用符の中の単独の CR はセルの中の改行になる。退けた案は、単独の CR を直さず G02082 のままにすること（直す道具がなく、表計算のソフトの古い書き出しを手で直すことになる）。

## 参考文献

- [golem-eval ADR 0004](../golem-eval/adr/0004-tsv-tables.md)
- [golem-fmt ADR 0003](../golem-fmt/adr/0003-lone-cr-to-lf.md)、[golem-fmt ADR 0004](../golem-fmt/adr/0004-fmt-without-arguments-fixes-cr.md)
- Y. Shafranovich, *Common Format and MIME Type for Comma-Separated Values (CSV) Files*, RFC 4180. https://www.rfc-editor.org/rfc/rfc4180
- IANA, *text/tab-separated-values*. https://www.iana.org/assignments/media-types/text/tab-separated-values
