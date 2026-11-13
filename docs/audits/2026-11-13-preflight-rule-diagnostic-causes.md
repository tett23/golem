# プリフライト設定の読み込みで発生する診断

[Golem ADR 0356](../adr/0356-diagnostic-cause-audit.md) の監査で、[Golem ADR 0321](../adr/0321-preflight-rule-error-causes.md) が区別する六つの入力条件を確認した。
対象はコミット `9a9d5da2` の設定読み込み処理である。
Golem [ADR 0357](../adr/0357-validate-embedded-cff.md) のブランチでビルドした CLI を使い、`modules/golem-driver/test/fixtures/tempest` のコピーで `golem preflight --rules printer.toml --format json` を実行した。

| printer.toml の内容または状態 | 終了コード | JSON に出たコード |
| --- | --- | --- |
| ファイルがない | 1 | G09100 |
| 1 バイトの ff | 1 | G09101 |
| 開き角括弧一文字 | 1 | G09001 |
| name に二行続けて別々の文字列を代入 | 1 | G09104 |
| `mystery=1` | 1 | G09103 |
| `based-on="strict"` | 1 | G09102 |
| `based-on="none"` | 0 | なし |

## G09102 の分割候補

G09102 は深刻度の語が未定義の場合と、二つのしきい値の大小が逆の場合に発生した。
次の入力はそれぞれ別のファイルに書いた。
どちらのファイルも先頭の行は `based-on="none"` とした。

| テーブル | 入力 | 修正 |
| --- | --- | --- |
| pdf-x | `severity="notice"` | 語を `"off"` に変更 |
| image-resolution | `gray={error-below=400,warning-below=300}` | error-below を 200 に変更 |

各入力で終了コードは 1 となり、JSON に G09102 が一度だけ出た。
各行の修正後は終了コード 0 で診断はなかった。
`Golem.Project.Manifest` がスキーマのエラーにコードを割り当てる。
旧コードを使う `modules/golem-preflight/test/Main.hs` の試験では、この二つの条件についてそれぞれ G09102 と行番号を期待している。
