# CI の所要時間（2026-11-04、戻した dist-newstyle の setup-config の時刻を新しくした前後）

[ADR 0147](../adr/0147-touch-setup-config-after-restoring-dist.md) の実装の前後の、`ci.yml` の `build` のテストの手順の記録である。
数字は `gh run view <id> --json jobs` の手順の秒数と、ジョブのログから取った。
「設定し直し」はログの `has been changed. Re-configuring` の行の数、「リンク」は `Linking` の行の数、「golem-pdf-test の始まり」は `cabal test` の手順が始まってから golem-pdf-test が始まるまでの秒数である。
2026-11-04 に作り、コミットした後は変更しない。

## 前

[ADR 0147](../adr/0147-touch-setup-config-after-restoring-dist.md) の文脈の表の四つの実行（41818037051、41820029937、41819668909、41818197481）である。

| 項目 | 値 |
|---|---|
| `tests-rest` の `cabal test` の手順（秒） | 106、83、85、58（中央値 84） |
| golem-pdf-test の始まり（秒） | 31、25、27、18 |
| 設定し直し | 26〜32 |
| リンク | 8〜27 |

## 後

このプルリクエスト（[#530](https://github.com/tett23/golem/pull/530)）の実行である。

| 実行 | `tests-rest` の手順 | golem-pdf-test の始まり | aarch64 の `tests` の手順 | 設定し直し（`tests-rest`、aarch64 の `tests`、`tests-driver`） | リンク（同じ順） |
|---|---|---|---|---|---|
| [41851389554](https://github.com/tett23/golem/actions/runs/41851389554) | 56 | 15 | 90 | 0、0、0 | 11、5、5 |
| [41852174234](https://github.com/tett23/golem/actions/runs/41852174234)（下の確かめのコミット） | 70 | 16 | 80 | 0、0、0 | 16、6、7 |

setup-config の時刻を新しくする手順は、どの実行でも 1 秒かからなかった。

## .cabal を変えたときの確かめ

[ADR 0147](../adr/0147-touch-setup-config-after-restoring-dist.md) のテスト設計のとおり、golem-length のテストのスイートにモジュールを一つ足すコミット（33f3f515）を置いた。
実行 41852174234 の `tests-rest` のログでは、cabal-install が `golem-length-0.1.0 (lib) (configuration changed)` と `golem-length-0.1.0 (test:golem-length-test) (configuration changed)` を出し、足したモジュールをコンパイルした。
setup-config の時刻を新しくしても、`.cabal` の中身の変更は cabal-install が見つける。
この実行の失敗は、足したモジュールの fourmolu の検査だけだった。
コミットは次のコミットで戻した。

## 読み方

設定し直しは、どのランナーでもなくなった。
`tests-rest` の手順は、前の中央値 84 秒に対し、56 秒と 70 秒だった。
二回目は、確かめのコミットで golem-length をビルドし直した分を含む。
x86-64 のランナーの揺れ（約 1.7 倍）があり、二回で短縮の大きさを決めることはできない。
aarch64 の `tests` の手順（80〜90 秒）は、ほかのスイートとコアを取り合う golem-driver-test が終わりを決めており、変わらなかった。
