# ADR 0315: @listing のパスを位置引数にそろえる

ステータス: 採択→[ADR 0341](0341-revise-retire-listing-src.md)

## 文脈

`@listing` は掲載するファイルのパスを最初の引数で取る。
現行 CLI に `@listing a.txt src=missing.txt` を渡すと、存在する `a.txt` を掲載し、G02065 の notice だけを出す。
このため、著者は捨てられたパスの誤りに気付きにくい。

## 実装すること

`src=` だけなら、その引数に G02250 を出し、パスを最初の引数に移すよう案内する。
先に `src=` の個数を調べる。
二つ目以降の各キーに G02077 を出し、この指令を終える。
位置引数を二つ書いた場合も、二つ目を指して G02253 を出す。
位置引数と `src=` を併記した場合は、同じファイル名でも `src=` の位置に G02253 を一つ出す。
二つの位置引数の場合も含め、メッセージに両方のパスを示し、採用する一方だけを位置引数に残すよう案内する。
いずれも評価器がアセットの内容を要求する前にそのブロックの評価を終える。

変更は rc4 の次のリリースから 1.0.0 までに入れる。
rc4 のタグには G02065 が notice として登録されている。
旧コードを廃止し、G02250 と G02253 をエラーとして登録する。
旧コードを `silence-notices` に書いた設定は G03024 になるので、リリースノートに削除手順を載せる。

## 実装しないこと

原稿や設定ファイルをビルド中に書き換える機能は扱わない。

## 不変条件

1. 位置引数が一つで `src=` のない従来有効な `@listing` では、掲載する内容と diagnostics が従来と一致する。
2. 位置引数と `src=` の組合せに応じて、評価器がアセットの内容を要求した回数が次の表と一致する。

| 入力 | 結果 |
| --- | --- |
| 引数なし | G02036、0 回 |
| `a.txt` | `a.txt` を 1 回 |
| `src=a.txt` | G02250、0 回 |
| `a.txt src=a.txt`、`a.txt src=b.txt` | G02253、0 回 |
| `a.txt a.txt`、`a.txt b.txt` | G02253、0 回 |
| `src=a.txt src=a.txt`、`a.txt src=a.txt src=b.txt` | G02077、0 回 |

## テスト設計

[改訂後の評価器の試験](../../experiments/syntax/review/Sources.hs) は、三つの提案を合わせて変更前に 16 件中 6 件、変更後に [16 件すべて](../../experiments/syntax/review/actual-green.log) が通った。
初回の試作と改訂後の結果は [実験の記録](../../experiments/syntax/review/README.md) に分けて記した。

[改訂の試験](../../experiments/syntax/review/review.test.mjs) で引数の個数とエラーの優先順を調べる。

[試作のテスト](../../experiments/syntax/test.mjs) を `node --test experiments/syntax/test.mjs` で動かす。
[現行 CLI との照合](../../experiments/syntax/cli.mjs) は `node experiments/syntax/cli.mjs /path/to/golem` で再現する。
CLI の比較には Golem のコミット `0a8d21a0` をビルドして使った。
[実行結果](../../experiments/syntax/cli.log) に、旧記法の notice と、移行後の入力での終了コードを記録した。
Haskell の評価器も変更し、実際に原稿をパースして評価した。
[評価器のテスト](../../experiments/syntax/Sources.hs) は三つの提案を合わせて 14 通りを検査する。
変更前は 6 通り、変更後は [14 通りすべて](../../experiments/syntax/sources-green.log) が期待したコードに一致した。
再現コマンドは `sh experiments/syntax/sources.sh` である。
採択後は引数の正確な位置、ファイルの先読み、各ターゲットの出力も検査する。
試作は評価器へ渡したアセットの参照の結果と意味論 IR のブロック数を記録した。
ドライバが評価前に読むファイルの集合は未確認である。
`--no-notices` を指定しても新しいエラーによってビルドは失敗することを確かめる。

## トレードオフ

`src=` を一律に G02250 にしても旧記法は止められるが、パスを二つ書いた人にはどちらを残すかの案内が要る。

## 参考文献

- [互換性と廃止の手順](0174-compatibility-promises-for-1-0.md)
- [rc4 の notice 一覧](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/modules/golem-syntax/src/Golem/Syntax/Diagnostic.hs)
- [現行の読み込み処理](https://github.com/tett23/golem/blob/2b7d1dffe359e065bf5e899a2df6cab85704905d/modules/golem-eval/src/Golem/Eval/File.hs#L2052-L2068)
