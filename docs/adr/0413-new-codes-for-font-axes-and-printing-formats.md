# ADR 0413: フォントの軸と刷の書式の誤りに、原因ごとの新しいコードを振る

Status: accepted

## 文脈

[ADR 0358](0358-font-instance-selection.md) の `instance` と `axes`、[ADR 0375](0375-printings-format.md) の `[printings]` の `format` の誤りは、どれも `style.toml` の誤りのコード G03006 に入っている。
G03006 は、構文、未知のキー、型、値の範囲などの多くの原因を束ねるコードであり、2026-11-17 の監査（[docs/audits/2026-11-17-diagnostic-cause-audit.md](../audits/2026-11-17-diagnostic-cause-audit.md)）が分ける候補に挙げている。
そこに新しい原因を足し続けると、一つのコードに一つの原因という決まりから、さらに離れる。
tett23 は 2026-11-23 に、これらを新しいコードに分けることを決めた。

あわせて、二つのことを確かめた。
一つは、刷の書式を書いた本に、G02076（日本語の本でだけ使えるという誤り）が誤って出る経路があるかである。
もう一つは、LSP で G01020 が同じ位置に二度出る問題（[golem-parser ADR 0009](../golem-parser/adr/0009-syntax-diagnostic-codes.md) の既知の問題の 4）が残っているかである。

## 調査した事項

`origin/main`（`b540aa68a`）で確かめた。

- `style.toml` の誤りのコードは、値の経路で [`codeAt`](https://github.com/tett23/golem/blob/b540aa68a3bbb45ed4a8754f79852984152f6cf6/modules/golem-project/src/Golem/Project/Style.hs#L3231-L3248) が決め、どの経路にも当たらなければ G03006 になる。
  失敗を作る `failAt` は文言だけを持つ。
  アキ量の誤りは、文言の先頭を見て G03020 に付け直している（同じファイルの `akiCode`）。
- [ADR 0358](0358-font-instance-selection.md) の誤りは、[`axesKey`](https://github.com/tett23/golem/blob/b540aa68a3bbb45ed4a8754f79852984152f6cf6/modules/golem-project/src/Golem/Project/Style.hs#L2150-L2167) と、`instance` を読む汎用の `optKey` が作る。
  メッセージは次の三つと、`instance` の型の誤りの汎用のメッセージである。
  - `axes には軸のタグと数の表を書きます（{ wght = 650 } のように書きます）`
  - `軸の値には数を書きます`
  - `軸の値には有限の数を書きます`
- [ADR 0375](0375-printings-format.md) の誤りは、[`printingTemplate`](https://github.com/tett23/golem/blob/b540aa68a3bbb45ed4a8754f79852984152f6cf6/modules/golem-project/src/Golem/Project/Style.hs#L2801-L2810) が作る。
  `printingTemplate` は、先に改行を検査し、次に golem-numerals の [`parseFormat`](https://github.com/tett23/golem/blob/b540aa68a3bbb45ed4a8754f79852984152f6cf6/modules/golem-numerals/src/Golem/Numerals/Format.hs#L70-L110) で書式を前から読む。
  `parseFormat` は、最初の誤りで止まり、理由の文を返す。
  欄の名前の表（`slot`）は `printingTemplate` が渡し、型は `Text -> Either Text (Slot a)` である。
  理由は次のとおりである。
  - 改行を含む（`printingTemplate` の検査）。
  - 表にない欄（`slot` の `Left`。`{volume}` や、名前の空の `{:kanji}`）。
  - 欄に表記を付けた（`{edition:kanji}`、`{year:}`。刷の書式の欄は、どれも文字の欄である）。
  - 閉じていない `{`。
  - 対応する `{` のない `}`。
  - 空の差し込み `{}`。
  - `\` の後に `{`、`}`、`\` のどれでもない字がある。
  - 書式の末尾に `\` がある。
- 仕様書は、`instance` と `axes` の誤り（[docs/specifications.md](../specifications.md) の 4532 行）と、`[printings]` の `format` の誤り（同 2112 行の表）を G03006 と書いている。
- G02076 のメッセージは「@printings は日本語の本（language の主の副タグが ja）でだけ使えます」である。
  このメッセージは、日本語でない本で `[printings]` の `format` を書かないときだけ出る（[`File.hs` の 1100 行から 1106 行](https://github.com/tett23/golem/blob/b540aa68a3bbb45ed4a8754f79852984152f6cf6/modules/golem-eval/src/Golem/Eval/File.hs#L1100-L1106)）。
  `format` を書いた本で、このメッセージが誤って出る経路はない。
- LSP がプロジェクトの外のファイルを評価する [`evaluateLoose`](https://github.com/tett23/golem/blob/b540aa68a3bbb45ed4a8754f79852984152f6cf6/modules/golem-driver/src/Golem/Driver.hs#L493-L501) は、構文のエラーがあるときは構文の diagnostic だけを返す。
  golem-lsp のテスト「an empty expression outside the project is one G01020」は、`[=]` で G01020 が一つだけであることを確かめている。
  [golem-parser ADR 0009](../golem-parser/adr/0009-syntax-diagnostic-codes.md) の既知の問題の 4 は、すでに解けている。

## 実装すること

### 新しいコード

次のコードを足す。
どれもエラーで、位置は誤りの値に置く。
メッセージは今の文を使う。

| コード | 原因 |
| --- | --- |
| G03260 | フォントの役割の `instance` が文字列でない |
| G03261 | フォントの役割の `axes` が表でない |
| G03262 | `axes` の軸の値が数でない |
| G03263 | `axes` の軸の値が有限でない（無限大か NaN） |
| G03264 | `[printings]` の `format` が改行を含む |
| G03265 | `[printings]` の `format` に表にない欄がある |
| G03266 | `[printings]` の `format` の欄に表記を付けた |
| G03267 | `[printings]` の `format` に閉じていない `{` がある |
| G03268 | `[printings]` の `format` に、対応する `{` のない `}` がある |
| G03269 | `[printings]` の `format` に空の差し込み `{}` がある |
| G03270 | `[printings]` の `format` の `\` の後の字が `{`、`}`、`\` のどれでもない |
| G03271 | `[printings]` の `format` の末尾に `\` がある |

### コードを選ぶ仕組み

- `style.toml` の読みに、コードを持つ失敗（`failAtCode`）を足す。
  `codeAt` は今のまま、コードを持たない失敗にだけ当てる。
- `parseFormat` は、理由の文の代わりに、原因を表す値（原因ごとの構成子）と文の組を返すようにする。
  欄の名前の表の型も、原因の値を返せるように変える。
- `printingTemplate`、`axesKey`、`instance` の読みは、原因から上の表のコードを選んで `failAtCode` で失敗する。
- ほかの書式（注の印、見出しの番号、リストの番号など）が `parseFormat` の原因をどのコードにするかは、この ADR では変えない。
  原因の値を文に戻して、今と同じ文言とコードにする。

### 文書

- 新しいコードを `docs/diagnostics.md` に足し、組み込みの写しを作り直す（`scripts/gen-embedded.sh`）。
- G03006 の項の「主な原因」とメッセージの並びから、上の原因と文言を消す。
- 仕様書の 2 箇所（フォントの役割の節と、`[printings]` の書式の表）のコードを、新しいコードに直す。

### 確かめた二つのこと

- G02076 は変えない。
  `format` を書いた本では出ないので、メッセージは条件と合っている。
- [golem-parser ADR 0009](../golem-parser/adr/0009-syntax-diagnostic-codes.md) の既知の問題の 4（G01020 の重複）は、すでに解けている。
  採択したら、[golem-parser ADR 0009](../golem-parser/adr/0009-syntax-diagnostic-codes.md) のステータスの行に、部分「既知の問題の 4」の注記（`kind` が `note`、修正先なし）として、`evaluateLoose` が構文のエラーのあるファイルでは評価の diagnostic を返さないことを足す。

## 実装しないこと

- `[hidden-folio]` の誤り（大きさ、`gutter`、`pages`、未知のキー）は、[ADR 0365](0365-hidden-folio-style.md) より前の規則であり、この ADR では分けない。
- G03006 のほかの原因の分割は、別の ADR で決める。
- `parseFormat` を使うほかの書式のコードは変えない。

## 不変条件

「原因」は、上のコードの表の一行とする。

- I1：上の表の原因をちょうど一つ含む入力では、diagnostic はその行のコードをちょうど一つ含み、G03006 を含まない。
- I2：`format` に二つ以上の原因があるときは、改行を先に、残りは書式の前から読んで最初に出会う原因のコードを一つだけ出す。
- I3：上の表の原因を含まない `style.toml` の diagnostic のコードは、この ADR の前と同じである。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| `instance = 1` | G03260 | I1 |
| `axes = 650` | G03261 | I1 |
| `axes = { wght = "a" }` | G03262 | I1 |
| `axes = { wght = inf }`、`nan` | G03263 | I1 |
| `format = "{year}\n"` | G03264 | I1 |
| `format = "{volume}"`、`format = "{:kanji}"` | G03265 | I1 |
| `format = "{edition:kanji}"`、`format = "{year:}"` | G03266 | I1 |
| `format = "{year"` | G03267 | I1 |
| `format = "year}"` | G03268 | I1 |
| `format = "{}"` | G03269 | I1 |
| `format = "\\a"` | G03270 | I1 |
| `format = "{year}\\"` | G03271 | I1 |
| `format = "{volume}\n"` | G03264 だけ | I2 |
| `format = "{volume}{"` | G03265 だけ | I2 |
| 正しい `instance`、`axes`、`format` | diagnostic なし | I3 |
| `[notes]` の `mark-format` の誤り | 今と同じコードと文言 | I3 |

## 受けいれ条件

なし。
この ADR の振る舞いは、不変条件のテストで確かめる。

## テスト設計

- 名前は `root ADR 0413 I<番号>: ...` とする。
  テストは、実装の前に失敗することを確かめてから実装する。
- I1 と I2 は、上の表の行ごとに golem-project のテストで、コードと位置を確かめる。
- I3 は、今ある [ADR 0358](0358-font-instance-selection.md) と [ADR 0375](0375-printings-format.md) の正しい入力のテストと、`parseFormat` を使うほかの書式のテストが、コードも文言も変わらないことで確かめる。
- 今のテストのうち、上の原因で G03006 を期待するものは、新しいコードに書き換える。

## トレードオフ

コードが十二増える。
書き手は、コードを見るだけで、どの値をどう直せばよいかが分かる。
エラーは `silence-notices` で抑えられないので、コードを指す設定の移行は要らない。

`failAtCode` を足すと、`style.toml` のコードを決める場所が `codeAt` と二つになる。
値の経路では原因を区別できない（同じキーの値の誤りに、原因が複数ある）ので、原因を知る読みの関数がコードを選ぶ。

## 参考文献

- [ADR 0358](0358-font-instance-selection.md)
- [ADR 0375](0375-printings-format.md)
- [ADR 0365](0365-hidden-folio-style.md)
- [golem-parser ADR 0009](../golem-parser/adr/0009-syntax-diagnostic-codes.md)
- [docs/audits/2026-11-17-diagnostic-cause-audit.md](../audits/2026-11-17-diagnostic-cause-audit.md)
