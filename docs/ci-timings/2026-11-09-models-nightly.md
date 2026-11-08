# models-nightly.yml の測定（2026-11-09、[ADR 0242](../adr/0242-run-the-heavy-commands-of-the-alloy-models-every-night.md) の実装のプルリクエスト）

[ADR 0242](../adr/0242-run-the-heavy-commands-of-the-alloy-models-every-night.md) が実装のプルリクエストで測ることにした値の記録である。
ADR はコミットした後に変えられないので、ADR の文脈の測定の後に測った値をここに置く。
2026-11-09 に作り、コミットした後は変更しない。

## 測った実行

- **測定の実行**（実行 42496303670）：ADR を書く前に、一時的なブランチ `measure-alloy-nightly` の一時的なワークフローで、14 のコマンドをスコープ 5 で一つのジョブに一つずつ走らせた。`needMoreNone` のスコープ 4 を、SAT4J、MiniSat、Glucose で走らせた。時間は `/usr/bin/time -v` の実時間である。
- **確かめの実行**（実行 42518069179）：ブランチ `impl-0242` の push で、`models-nightly.yml` を一時的に走らせた。`nightly.txt` の `needSpaceSome` を、一時的にわざと `none` にした。時間は、ジョブの始まりから終わりまでである（チェックアウトと jar の取得を含む）。

どちらも `ubuntu-24.04` のランナーで、Java 17、Alloy 6.2.0 の jar、SAT4J である。
`workflow_dispatch` は既定のブランチにあるワークフローしか起動できないので、確かめの間だけ push で起動した。

## コマンドごとの時間

| コマンド | 一覧の結果 | スコープ | 測定の実行 | 確かめの実行のジョブ | 確かめの実行の結果 |
|---|---|---|---|---|---|
| `waitingBlankSome` | found | 5 | 7 秒 | 15 秒 | found |
| `waitingBlankNone` | none | 5 | 1,893 秒 | 22 分 39 秒 | none |
| `waitingBlankAllButGreedy` | none | 5 | 3,694 秒 | 1 時間 2 分 7 秒 | none |
| `blankFigureOrder` | none | 5 | 648 秒 | 14 分 25 秒 | none |
| `blankBeforeWaiting25` | found | 5 | 8 秒 | 22 秒 | found |
| `blankRules25` | none | 5 | 436 秒 | 8 分 27 秒 | none |
| `needSpaceSome` | found | 5 | 7 秒 | 14 秒 | found（一覧を `none` にしたので、ジョブは失敗） |
| `needSpaceNone` | none | 5 | 13,138 秒 | 3 時間 7 分 8 秒 | none |
| `needSpaceAllButGreedy` | found | 5 | 127 秒 | 2 分 37 秒 | found |
| `needFigure` | found | 5 | 14 秒 | 16 秒 | found |
| `needGreedy` | found | 5 | 10 秒 | 14 秒 | found |
| `needMoreSome` | found | 5 | 13 秒 | 21 秒 | found |
| `needMore27` | found | 5 | 48 秒 | 40 秒 | found |
| `needMoreNone` | none | 4 | 822 秒（スコープ 4） | 13 分 17 秒 | none |

`needMoreNone` のスコープ 5 は、測定の実行で、ジョブの上限の 5 時間 55 分で取り消されるまで終わらなかった。
手元（Apple Silicon の macOS）でも、16,718 秒で止めるまで終わらなかった。

測定の実行の最大の常駐は、どのコマンドも 760 MB 以下だった。

## ソルバー

`needMoreNone` のスコープ 4 の、測定の実行の時間である。

| SAT4J | MiniSat | Glucose |
|---|---|---|
| 822 秒 | 1,012 秒 | 580 秒 |

## 結果の誤りでジョブが落ちること

確かめの実行で、`nightly.txt` を `needSpaceSome none` にしたジョブは、次の行を書いて失敗した。

```
check: docs/golem-layout/models/pagination.als needSpaceSome: found, but nightly.txt says none
```

同じ実行で、`scripts-linux` と `scripts-macos` の `scripts/ci/test.sh` は、`models-nightly.yml: I6 only schedule and workflow_dispatch` だけで落ちた。
一時的に足した push の起動を、I6 の検査が見つけたものである。

## 実行の全体

確かめの実行は、`prepare` の始まり（20:02:51 UTC）から `needSpaceNone` の終わり（23:10:06 UTC）まで、3 時間 7 分 15 秒だった。
二つ目に長い `waitingBlankAllButGreedy` は 1 時間 2 分 7 秒で、ほかの 11 のジョブは 15 分以内に終わった。
`needSpaceNone` は、測定の実行の 13,138 秒より、確かめの実行（ジョブで 11,228 秒）のほうが短かった。
