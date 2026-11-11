# ADR 0317: @table のパスを位置引数にそろえる

ステータス: 採択

## 文脈

CSV または TSV から表を作る `@table` は、パスを位置引数と `src=` で取る。
旧記法には G02129 が付き、パスを二つ書くとさらに G02130 が付く。

## 実装すること

`src=` だけなら引数に G02252 を出し、パスを最初の引数に移すよう案内する。
位置引数と `src=` を併記したら、既存の G02130 だけをこれまでと同じ指令の範囲に出す。
いずれも評価器が表のアセットの内容を要求する前に、そのブロックの評価を終える。

変更は rc4 の次のリリースから 1.0.0 までに入れる。
rc4 のタグには G02129 が notice として登録されている。
旧コードを廃止し、G02252 をエラーとして登録する。
旧コードを `silence-notices` に書いた設定は G03024 になるので、リリースノートに削除手順を載せる。

## 実装しないこと

原稿や設定ファイルをビルド中に書き換える機能は扱わない。

## 不変条件

1. `src=` を含まない有効な入力は、同じ表を作る。
2. パスが二つあれば、同じパスでも G02130 を一つ出し、評価器は表のアセットの内容を要求しない。

| 入力 | 結果 |
| --- | --- |
| なし | G02034 |
| `t.csv` | 表を作る |
| `src=t.csv` | G02252 |
| `t.csv src=u.tsv` | G02130 のみ |
| `t.csv t.csv` | G02130 のみ |

## テスト設計

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

二つのパスに二つのエラーを出すと、どちらを消した時点で表を組めるのかが伝わりにくい。
既存の G02130 は二つのパスを一つにする修正を直接示す。

## 参考文献

- [互換性と廃止の手順](0174-compatibility-promises-for-1-0.md)
- [rc4 の notice 一覧](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/modules/golem-syntax/src/Golem/Syntax/Diagnostic.hs)
- [現行の読み込み処理](https://github.com/tett23/golem/blob/2b7d1dffe359e065bf5e899a2df6cab85704905d/modules/golem-eval/src/Golem/Eval/File.hs#L1764-L1797)
