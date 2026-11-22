# プロジェクト設定の診断 G03001 と G03006 の発生条件

[Golem ADR 0356](../adr/0356-diagnostic-cause-audit.md) に従い、設定ファイルの別々の誤りが同じコードを返す例を調べた。
対象のソースは `9a9d5da2`、実行した CLI は Golem [ADR 0357](../adr/0357-validate-embedded-cff.md) のブランチでビルドしたものである。
各行の入力は `modules/golem-driver/test/fixtures/tempest` のコピーに単独で加えた。
そのディレクトリで `golem check` を実行すると、変更後は終了コード 1、表に示した修正後は終了コード 0 になった。

| コード | ファイル | 変更した入力 | 報告された箇所 | 修正 |
| --- | --- | --- | --- | --- |
| G03001 | manifest.toml | 先頭の `chapters` を `chaptrs` に変更 | 1 行目、必須の chapters が欠落 | キーを chapters に戻す |
| G03001 | manifest.toml | 最初の著者の role に `"invalid-role"` を指定 | 11 行目、役割名が語彙の範囲外 | role に `"author"` を指定 |
| G03006 | style.toml | 末尾に `[compositoin]` と `explicit-hyphen-penalty = 10` を追加 | 21 行目、未知のテーブル名 | テーブル名を composition に変更 |
| G03006 | style.toml | 末尾に `[composition]` と `explicit-hyphen-penalty = 10001` を追加 | 22 行目、値が上限 10000 を超過 | 値を 10 に変更 |

G03001 は `Golem.Project.Manifest` の `decodeStrictBy` がスキーマの誤りに割り当てる。
著者の役割は同じモジュールで列挙値と照合する。
既存の `modules/golem-project/test/FunctionsSpec.hs` では、関数の設定のキーや型の誤りにも G03001 を期待している。

G03006 は `Golem.Project.Style` の `decodeStrictWith` が未知のキーに割り当てる。
同じモジュールの `compositionChecks` はハイフンのペナルティーが範囲を外れた場合に G03006 を返す。
既存の `modules/golem-lsp/test/Main.hs` には、設定の編集後に LSP が返すコードの列を G03006 と照合する試験がある。

この記録の再現範囲は診断一覧 430 コードのうち上記の 2 コードである。
