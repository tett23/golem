# 見た目の回帰テストの所要時間（2026-11-05、PDF を並べて描いた後）

[ADR 0168](../adr/0168-render-visual-pdfs-side-by-side-with-shem-jobs-1.md) の実装（[#557](https://github.com/tett23/golem/pull/557)）で、`scripts/visual/check.sh` が PDF をプロセッサの数まで同時に、各 shem に `--jobs 1` を渡して描くようにした後の所要時間の記録である。
shem は v0.1.0-rc4 である。
並べる前の rc4 の値は [2026-11-05-shem-rc4.md](2026-11-05-shem-rc4.md) にある。
単位は秒である。
2026-11-05 に作り、コミットした後は変更しない。

## CI

秒数と「PDF の後」の意味は [2026-11-05-shem-rc4.md](2026-11-05-shem-rc4.md) と同じである。
CI の秒数は、ステップの `startedAt` と `completedAt` の差で、1 秒単位である。

| 実行 | `visual` の全体 | ダウンロード | 比べる手順 | PDF の後 | `outputs` の PDF を組む手順 |
|---|---|---|---|---|---|
| [41939462891](https://github.com/tett23/golem/actions/runs/41939462891) | 104 | 3 | 3 | 17 | 40 |
| [41940185438](https://github.com/tett23/golem/actions/runs/41940185438) | 100 | 1 | 4 | 11 | 43 |

一回めの実行は、`scripts-macos` のテストの誤り（macOS の `sh` で、関数の前の代入が残る）で失敗したが、`visual` は通った。
二回めの実行では、すべての検査が通った。
二回めの `visual` の標準エラー出力では、描き始めた順が `manual-dev`、`manual`、`kanikosen-marks-japanese`、`kanikosen` の順で、最後が `figures`、`sample` だった（PDF の大きい順）。

並べる前の rc4 の比べる手順は、#552 の 3 回で 4、4、5 秒だった。

## 手元

10 コアの Apple silicon の macOS で、main の 3693218a の PDF（17 の PDF、1,813 ページ）に対して、並べる前の `check.sh`（origin/main）と、この変更の `check.sh` を交互に 3 回ずつ動かした実時間（`/usr/bin/time -p`）である。
shem は aarch64-apple-darwin の v0.1.0-rc4 である。

| `check.sh` | 1 回め | 2 回め | 3 回め |
|---|---|---|---|
| 並べる前 | 2.53 | 2.34 | 2.34 |
| 並べた後 | 1.53 | 1.50 | 1.46 |

二つの `check.sh` の標準出力は一致した（どちらも空で、終了コードは 0）。

## 読み取れること

- 手元では、比べる手順が約 2.4 秒から約 1.5 秒に縮んだ。[ADR 0168](../adr/0168-render-visual-pdfs-side-by-side-with-shem-jobs-1.md) の測定（描いてハッシュを取るまでで約 2.3 秒から約 1.2 秒）と合う。
- CI の比べる手順は 3 秒と 4 秒で、並べる前の 4〜5 秒より短い。[ADR 0168](../adr/0168-render-visual-pdfs-side-by-side-with-shem-jobs-1.md) の見込み（約 1 秒の短縮）と矛盾しないが、1 秒単位の記録の 2 回では差を言い切れない。
- `visual` のジョブ全体は、PDF を待つ手順が大半を占めるので、この変更で目に見えては縮まない。
