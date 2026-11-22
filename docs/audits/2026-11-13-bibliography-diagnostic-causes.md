# 参考文献ファイルの G03026 の発生条件

[Golem ADR 0356](../adr/0356-diagnostic-cause-audit.md) の監査で、G03026 の三つの原因を再現した。
調査したソースは `9a9d5da2` の `Golem.Driver.loadBibliography` である。
`modules/golem-driver/test/fixtures/tempest` のコピーで manifest.toml の先頭に `bibliography = ["refs.json"]` を加えた。
Golem [ADR 0357](../adr/0357-validate-embedded-cff.md) のブランチでビルドした CLI を使い、各入力とその修正後に `golem check` を実行した。

| refs.json の状態 | 報告された原因 | 修正 |
| --- | --- | --- |
| ファイルが存在しない | ファイルがない | refs.json を作成し、空の配列を書く |
| 内容が `[` | JSON の末尾で値か閉じ角括弧が必要 | 閉じ角括弧を補う |
| 内容が `{}` | CSL-JSON の最上位が配列でない | 空のオブジェクトを空の配列に変更する |

各入力では manifest.toml の 1 行 1 列に G03026 が一度だけ出て、終了コードは 1 だった。
各修正後は終了コード 0 で、エラーはなかった。
実装はファイルの不在、JSON の構文エラー、最上位の型の不一致に同じコードを割り当てる。
ファイルを読む処理で例外を捕捉した場合も、不在と同じメッセージを返す。
例外の種類ごとの実行結果は未確認である。

旧コードを照合する試験は `modules/golem-driver/test/ReferencesSpec.hs` にある。
この試験はファイルの不在と JSON の誤りのほか、引用先が見つからない G02021 と G03026 の出力順も検査する。
