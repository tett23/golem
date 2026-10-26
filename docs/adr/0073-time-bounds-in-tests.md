# ADR 0073: テストの時間の上限を、止まらないことの検出に限り、上限の検査は数で書く

ステータス: 採択→golem-pdf と golem-svg のテストの時間切れと `linearTime` は [ADR 0091](0091-cpu-time-limits-in-pdf-and-svg-tests.md)

## 文脈

上限の検査（入力が大きくても計算が際限なく続かないこと）の多くは、時間で書かれている。
混んだランナーでは、正しい実装でも時間の上限を超えて落ちることがある。
逆に、上限の数を少し間違えた実装でも、速いランナーでは時間の上限に収まって通ることがある。

2026-10-23 のテストの品質の点検で、次の時間の断言を確かめた。

- [modules/golem-eval/test/ExprSpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-eval/test/ExprSpec.hs#L221-L223) の `withinASecond`（1 秒の時間切れ）を、同じファイルの 6 箇所のテストに付けている。
- [modules/golem-svg/test/SecuritySpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-svg/test/SecuritySpec.hs#L74-L88) の `linearTime` は、入力を倍にしたときの CPU 時間の比が 3 未満であることを断言する。注釈は、二回の実行が合わせて 1 秒を十分に超える大きさの入力を使うとしている。
- [modules/golem-driver/test/TableFilesSpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/TableFilesSpec.hs#L136-L143) は、`getMonotonicTime` で測ったビルドの時間が 10 秒未満であることを断言する。
- [modules/golem-svg/test/SecuritySpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-svg/test/SecuritySpec.hs) と [modules/golem-pdf/test/SecuritySpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-pdf/test/SecuritySpec.hs) は、それぞれ 15 と 14 の `mkTimeout`（多くは 5 秒）を持つ。

これらは二種類に分かれる。
一つは、計算が止まらない実装を失敗にするための時間切れである。
もう一つは、時間そのものを断言する検査（TableFilesSpec の 10 秒、SVG の比）である。
前者は、時間切れの値を十分に大きく取れば揺れない。
後者は、時間の代わりに「上限で拒んだこと」や「処理した要素の数」を断言できる。

## 実装すること

- 時間そのものの断言を、数の断言に置き換える。
  - TableFilesSpec：`t1 - t0 < 10` を削り、テストに 30 秒の時間切れを付ける。G02088 の diagnostic の断言は残す。
  - SVG の `linearTime`：時間の比を、割り当ての比（同じファイルの [`linearIn`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-svg/test/SecuritySpec.hs#L63-L72)）に置き換えられる箇所は置き換える。割り当てで測れない計算（割り当てずに二乗の時間がかかる処理）は、`linearTime` を残し、比の上限を 3 から 4 に緩める。
- 止まらないことの検出の時間切れは、値を 30 秒にそろえる。`withinASecond` は `withinHalfAMinute` に改め、1 秒の値をやめる。止まらない実装は 30 秒でも失敗になる。
- ADR のテスト設計が「10 秒以内」「5 秒以内」と書いた検査は、ADR の文言を変えずに、時間切れを 30 秒にし、上限で拒んだことの断言を残す。採択済みの ADR の時間の文言は、止まらないことの検出の意図として読む。この読み方を docs/roadmap.md の手で確かめる項目には書かず、CONTRIBUTING.md のテストの節に一文で書く。

## 実装しないこと

- 性能の回帰の検出。時間の上限は、性能の回帰を見つけるためのものではない。性能は `docs/benchmarks/` の計測で扱う。
- テストのスイート全体の所要時間に上限を設けること。スイート全体の上限は、テストごとの時間切れとは別に扱う。上限の値は、例えば直近 50 回の実行の所要時間の中央値を測って決める予定である。
- 時間切れのない上限の検査を足すこと。止まらない実装はスイートの時間切れ（[scripts/ci/suite-timeout.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/suite-timeout.sh)、10 分）でも止まるが、どのテストが止まったかがわからないので、テストごとの時間切れは残す。

## テスト設計

- SVG：割り当てに置き換えた検査が、二乗の割り当てを持つ変異で落ちることを確かめる。
- 時間切れの値の変更は自動テストにできない。実装の後、CI の 10 回の実行で、時間に関わる失敗が一度もないことを確かめる。

## トレードオフ

- 時間切れを 30 秒にすると、止まらない実装で失敗するまでの時間が延びる。失敗するのはその種の実装が入ったときだけである。
- `linearTime` の比を緩めると、二乗でなく 1.5 乗の悪化のような小さな悪化は見逃す。目的は二乗以上の悪化の検出である。

## 参考文献

- [ADR 0035](0035-security-hardening.md)
- [ADR 0043](0043-table-file-size-limits.md)
