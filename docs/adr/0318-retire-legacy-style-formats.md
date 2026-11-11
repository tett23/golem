# ADR 0318: 番号と柱の旧書式および注番号の旧サイズ指定を廃止する

ステータス: 採択

## 文脈

一覧の番号と柱は、文字としての波括弧をバックスラッシュでエスケープする。
一覧では番号の種類を `{n:lower-alpha}` のように書く。
注番号の大きさは文字スタイル `note-mark` で指定する。
これらの指定には、今も同じ意味に読む旧記法がある。

## 実装すること

次の表に従い、一覧の番号、柱、注番号の値を読む段階で、該当する原因ごとにエラーを一つ出す。
一字の見本は元の対応表に従い、たとえば `{一}` なら `{n:kanji}` と書くようメッセージで案内する。
波括弧と一字の見本が同じ値にある場合は両方を出す。
G03253 は `mark-style` とのサイズの競合の判定に先立つ。
種類名を明示した式やサイズ指定と旧記法が並んでも、旧記法があれば組版を止める。

変更は rc4 の次のリリースから 1.0.0 までに入れる。
rc4 のタグには G03114、G03115、G03116、G03117 が notice として登録されている。
旧コードを廃止し、G03250 から G03253 をエラーとして登録する。
旧コードを `silence-notices` に書いた設定は G03024 になるので、リリースノートに削除手順を載せる。

## 実装しないこと

原稿や設定ファイルをビルド中に書き換える機能は扱わない。

## 不変条件

1. 新しい指定だけを使う値は、旧記法のエラーを一つも出さない。
2. 旧記法の原因の種類とエラーコードの集合が表の対応に等しい。

| 入力 | 結果 |
| --- | --- |
| `[lists] numbers` の `{{`、`}}` | G03250。`\{`、`\}` に替える |
| `[lists] numbers` の `{a}` | G03251。`{n:lower-alpha}` に替える |
| 柱の `{{`、`}}` | G03252。`\{`、`\}` に替える |
| `[notes] mark-size` | G03253。`[character-styles.note-mark] size` に移す |
| 新しい指定だけ、指定なし | 上の四つは出ない |

## テスト設計

[試作のテスト](../../experiments/syntax/test.mjs) を `node --test experiments/syntax/test.mjs` で動かす。
[現行 CLI との照合](../../experiments/syntax/cli.mjs) は `node experiments/syntax/cli.mjs /path/to/golem` で再現する。
CLI の比較には Golem のコミット `0a8d21a0` をビルドして使った。
[実行結果](../../experiments/syntax/cli.log) に、旧記法の notice と、移行後の入力での終了コードを記録した。
Haskell の設定読み込みでも旧書式をエラーにした。
`sh experiments/syntax/formats.sh` は、[設定のテスト](../../experiments/syntax/Formats.hs) を `parseStyle` に直接渡す。
変更前は 7 件中 5 件が失敗し、[変更後の 7 件](../../experiments/syntax/formats-green.log) はすべて成功した。
二種類の旧記法を一つの値に含める例でも二つのコードが出た。
採択後は表のコード、個数、位置を CLI から検査し、四つのターゲットの終了コードを調べる。
`--no-notices` を指定しても新しいエラーによってビルドは失敗することを確かめる。

## トレードオフ

四つを一度に廃止すると複数の設定を直す本がある。
原因ごとにコードを分けることで、著者は一箇所ずつ直して再検査できる。


## 参考文献

- [番号の見本と種類名の対応表](0177-note-mark-style-and-numerals.md)
- [互換性と廃止の手順](0174-compatibility-promises-for-1-0.md)
- [rc4 の notice 一覧](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/modules/golem-syntax/src/Golem/Syntax/Diagnostic.hs)
- [現行の読み込み処理](https://github.com/tett23/golem/blob/2b7d1dffe359e065bf5e899a2df6cab85704905d/modules/golem-project/src/Golem/Project/Style.hs#L749-L785)
