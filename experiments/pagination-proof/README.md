# Golem [ADR 0352](../../docs/adr/0352-prove-pagination-in-lean.md) の Lean 証明

このディレクトリは、[Golem ADR 0352](../../docs/adr/0352-prove-pagination-in-lean.md) の改ページ証明を作る場所である。`check.sh` は Alloy の42コマンドと期待値の一覧が一致することを確かめ、各コマンドに対応する Lean の宣言を要求する。

現在の `Pagination.lean` には、42コマンドのうち13コマンドと同名の宣言がある。ただし、元の述語の全体と同値なものはまだない。`tallFigure` については、図版が段より高いと旧規則が衝突することを任意の自然数の高さについて示し、縮小後に衝突が解消することを示す。キャプション付き図版の寸法についても、入力の行数から占有できる高さの上限を証明する。

残る29コマンド、既存宣言と元の述語の同値性、キャプションの行分割、改ページの全状態遷移と終了、出力の過不足と順序、実装との境界例の照合は未完である。`check.sh` は最初の欠落を報告して失敗する。移行が完了するまで Alloy の定期実行と既存の参照を維持する。

手元では次のコマンドで Lean 4.7.0 の証明を検査する。

```sh
lean experiments/pagination-proof/Pagination.lean
sh experiments/pagination-proof/check.sh
```
