# 文字スタイルの継承で G03013 が出る条件

[Golem ADR 0356](../adr/0356-diagnostic-cause-audit.md) の監査で、継承先を定義していない場合と、定義した継承関係が循環する場合を比較した。
対象は `9a9d5da2` の `Golem.Project.Style` である。
Golem [ADR 0357](../adr/0357-validate-embedded-cff.md) のブランチでビルドした CLI を使い、tempest フィクスチャーの style.toml の末尾に次の設定を個別に加えて `golem check` を実行した。

| 文字スタイルの設定 | 報告された原因 | 修正 |
| --- | --- | --- |
| child の based-on に absent を指定し、absent を定義しない | child の継承先 absent が存在しない | 空の表 `[character-styles.absent]` を追加 |
| first の based-on に second、second の based-on に first を指定 | first と second の継承が循環する | second の表を残し、second の based-on を削除 |

各入力は終了コード 1 となり、style.toml の 22 行 10 列に G03013 が一度出た。
各修正後はエラーが消え、終了コードは 0 だった。
実装は文字スタイルの集合に継承先があるかを検査し、循環したスタイルには別のメッセージを組み立てる。
`modules/golem-project/test/Main.hs` の文字スタイルの参照を検査する試験は、この二つの入力に G03013 を期待している。
