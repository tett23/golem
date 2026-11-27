# ADR 0014: 数の糖衣構文に表記を指定する

Status: accepted

## 文脈

[golem-parser ADR 0011](0011-number-shorthand.md) の `##N##` は、`[number-text N]` と同じ意味である。
縦中横などの表記を個別に指定するときは、今は長いコマンドを書く必要がある。
2026-11-27 に、メンテナーは `##1:tcy##` のような記法を求め、表記を今後も `style` の引数として直接渡し、糖衣構文と `number-text` の IR を一致させると指定した。

## 調査した事項

origin/main の [4121ea73d](https://github.com/tett23/golem/commit/4121ea73d4466eaf47353e4b84d22f08327aed1e) で、次のことを確かめた。

- [Golem.hpeg](https://github.com/tett23/golem/blob/4121ea73d4466eaf47353e4b84d22f08327aed1e/modules/golem-parser/grammar/Golem.hpeg#L312-L327) は、`##` と ASCII の数字を開きとし、閉じまでの中身にコロンも読める。
- [File.hs](https://github.com/tett23/golem/blob/4121ea73d4466eaf47353e4b84d22f08327aed1e/modules/golem-eval/src/Golem/Eval/File.hs#L3293-L3296) は、`shorthandDigits` が受け付ける数字だけを `number-text` の引数に渡す。
  [shorthandDigits](https://github.com/tett23/golem/blob/4121ea73d4466eaf47353e4b84d22f08327aed1e/modules/golem-eval/src/Golem/Eval/File.hs#L3332-L3342) は、コロンを含む中身を受け付けない。
- [number-text の評価](https://github.com/tett23/golem/blob/4121ea73d4466eaf47353e4b84d22f08327aed1e/modules/golem-eval/src/Golem/Eval/File.hs#L3438-L3453) は、`style` に `kanji`、`kanji-digits`、`tcy` を受け付ける。
- 同じ評価処理を含む [root ADR 0468](../../adr/0468-paragraph-styles-for-headings-and-lists.md) の検証 CLI で、`golem inspect /private/tmp/golem-user-notation-repro.gm --as ir` を実行した。
  `##1##` は `Number 1 Nothing`、`[number-text 1 style=tcy]` は `Number 1 (Just StyleTcy)` になり、`##1:tcy##` は G02078 になった。
  CLI の SHA-256 は `57af1b6f61b1fa70dcb2a6691c3ad235c8bde50ac3d6f33cd8d6af3e74cef36b` である。

## 実装すること

### 記法と評価

`##N:S##` を、`[number-text N style=S]` と同じ意味の糖衣構文として受け付ける。
`N` は今の `##N##` と同じく、先頭に 0 を付けない ASCII の数字の並びか、`0` である。
`S` は英小文字で始まり、その後に英小文字、ASCII の数字、ハイフンを書ける名前である。
コロンの前後に空白は書けず、コロンは一つだけ書ける。

| 記法 | 同じ意味のコマンド |
| --- | --- |
| `##1:tcy##` | `[number-text 1 style=tcy]` |
| `##12:kanji##` | `[number-text 12 style=kanji]` |
| `##2026:kanji-digits##` | `[number-text 2026 style=kanji-digits]` |
| `##12##` | `[number-text 12]`（今と同じ） |

評価は、数と、書いた表記名をそのまま持つ `style=S` の引数を、既存の `number-text` の名前解決と評価の経路へ直接渡す。
糖衣構文の側に表記名の一覧や、表記ごとの別の IR 生成処理を持たせない。
今後 `number-text` の `style` が受け付ける名前が増えた場合も、糖衣構文から同じ引数を渡す。
原稿の位置を取り除いて比較した意味論 IR は、構築子、数の値、表記の指定を含むすべてのフィールドが一致しなければならない。
たとえば組み込みの `##1:tcy##` は、`[number-text 1 style=tcy]` と同じ `Number 1 (Just StyleTcy)` を作り、糖衣構文だけを `Tcy` や `Text` に変換しない。
表記の名前の有無、整数の範囲、書字方向ごとの出力は、そのコマンドと同じ規則で扱う。
組み込みの `number-text` が知らない表記（`##1:unknown##` など）は、同じく G02019 とする。
名前の上書きがある場合も、明示的なコマンドと同じ解決先を使う。

数字、コロン、表記の名前として読めない中身と、閉じの無い記法は、G02078 として何も組まない。
メッセージは `## と ## のあいだには算用数字、または算用数字:表記名を書きます。本文の ## は \\## と書きます` とする。
位置は、今と同じく記法全体である。

### 既存の扱いを保つ箇所

開きの条件と中身を読む文法、CST と AST の原稿を保持する形は変えない。
コードの散文スロットとコードブロックでは、`##N:S##` も書いた文字のままにする。
エスケープした `\##1:tcy##` も文字のままにする。
fmt は、糖衣構文と明示的なコマンドを互いに書き換えず、表記の指定も消さない。

仕様書、マニュアル、README に短い例を足し、diagnostics の G02078 の説明と埋め込みを同期する。
採択時に、[golem-parser ADR 0011](0011-number-shorthand.md) の「中身と閉じ」と「評価」と「診断」の、表記指定を認めない部分を、この ADR による変更として記録する。

## 実装しないこと

負の数、小数、桁区切り、先頭の 0 を認めることはしない。
`[numbers]` の既定の表記と、新しい表記名は足さない。
書式の好みを理由にコマンドを糖衣構文へ書き換える lint は足さない。

## 不変条件

- I1: 表記を指定しない既存の `##N##` の評価結果と diagnostics は変わらない。
- I2: コードの外で評価する、同じ解決先の `##N:S##` と `[number-text N style=S]` の意味論 IR は、原稿の位置を除く全フィールドが等しく、diagnostics のコードと重大度も一致する。
- I3: コードの中とエスケープした記法は、書いた文字のままである。
- I4: 中身か閉じが不正な記法ごとに、G02078 が一つ出て、その記法の文字も数も出力しない。
- I5: fmt を繰り返しても表記の指定は保たれ、二回目以降の出力は変わらない。
- I6: 糖衣構文が `number-text` へ渡す表記名は書いた `S` と等しく、糖衣構文の側で表記名を列挙して制限しない。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| `##0##`、`##12##` | 今と同じ | I1 |
| `##1:tcy##`、`##12:kanji##`、`##2026:kanji-digits##` | 明示コマンドと同じ | I2 |
| 横組みと縦組みの `##1:tcy##` | 明示コマンドと同じ `Number` IR。方向で別の構築子にしない | I2 |
| 上書きした `number-text` に、追加した表記名 `custom` を渡す | `style=custom` がそのまま届き、両記法の IR が一致 | I2, I6 |
| `##1:unknown##` | 組み込みでは G02019 | I2 |
| `##01:tcy##`、`##1:##`、`##1::tcy##`、`##1: tcy##`、閉じの無い `##1:tcy` | 各 G02078 一つ | I4 |
| 整数の範囲を一つ超える数字と表記指定 | 明示コマンドと同じ整数の範囲のエラー | I2 |
| `[code: ##1:tcy##]`、コードブロック、`\##1:tcy##` | 文字を保持 | I3 |
| 表記指定、隣接した数、見出しと表セルの数を含む原稿 | 整形の往復で表記を保持 | I5 |

## 受けいれ条件

- A1: 通常の CLI で、縦組みと横組みの PDF、HTML、EPUB、テキストを生成し、明示コマンドとの一致を確かめる。

## テスト設計

golem-parser、golem-eval、golem-fmt のテストに、不変条件ごとの名前を `golem-parser ADR 0014 I<n>: ` で始めて付ける。
評価の回帰テストを先に足し、未実装では表記指定が G02078 になる失敗を確かめる。
既存の [golem-parser ADR 0011](0011-number-shorthand.md) の不正な中身と、コードの中のテストを、変更後の有効な記法と照らす。
整数の範囲と名前の上書きも、明示コマンドを対照に確かめる。
表記ごとに、原稿の位置を正規化した IR 全体を等値比較する。
追加の表記名を受け取るテスト用の上書きも使い、`style` の文字列を直接渡すことと、糖衣構文の側に名前の固定リストが無いことを確かめる。
A1 では、両方の記法を置いた同じ原稿で比較する。

## トレードオフ

コロンは数の表記を短く書けるが、既存の `##N##` より覚える形が増える。
明示的なコマンドも残し、どちらで書くかは書き手が選ぶ。

## 参考文献

- [golem-parser ADR 0011](0011-number-shorthand.md)
- [root ADR 0453](../../adr/0453-override-built-in-commands-by-listed-imports-and-plugins.md)
