# ページ番号の不動点の二周めで変わらない単位の組版を使い回した前後の時間（2026-11-09）

[docs/adr/0251](../adr/0251-reuse-the-compositions-of-unchanged-units-between-fixpoint-rounds.md) の「テスト設計」が求める計測の記録である。
二周めにすべての単位を組み直す `main` と、変わらない単位の組版を前の周から使い回す実装のブランチ（impl-0251）を、[docs/benchmarks/2026-11-09-typesetting-speed-survey.md](2026-11-09-typesetting-speed-survey.md)（以下「調査」）の表 3 の方法で測った。
コミットした後は変更しない。

## 環境

- 計算機：調査と同じ Apple M1 Max（10 コア）、メモリ 64GB、macOS 27.0。
- golem：作業ツリーで `cabal build exe:golem --disable-tests` で作ったもの（GHC 9.10.3、最適化は cabal の既定）。「前」は `main` の `81e1d187`（[ADR 0249](../adr/0249-link-golem-with-a-64-mb-allocation-area.md)、[ADR 0250](../adr/0250-character-class-tables-instead-of-list-membership.md)、[ADR 0252](../adr/0252-draw-and-serialise-the-pages-of-the-pdf-in-parallel.md)、[ADR 0253](../adr/0253-memoise-run-shaping-and-shorten-the-memo-key.md)、[ADR 0254](../adr/0254-write-glyph-codes-without-printf.md) を含む）、「後」はそれに impl-0251 を合わせたものである。どちらも、調査の表 3 と同じく `Golem.Typeset.Flow` の `round'` と `Golem.Typeset.Draw` に段階の前後で時刻を読んで標準エラー出力に書く行を一時的に足し（コミットしていない）、`cabal.project.local` で `golem-cli` に `-rtsopts` を足してリンクした。
- 入力：`82861475` の `manual/`、`manual-dev/`、`modules/golem-driver/test/fixtures/complex-horizontal/` を作業用のディレクトリに写し、調査と同じフォントを置いた。三つとも二周で止まる。
- 方法：一回ごとに `build/` を消し、`golem build --target pdf +RTS -s -RTS` を「前」と「後」の順に交互に 5 回ずつ走らせた。capability は既定（10）である。値は中央値である。「組版」は調査の表 3 と同じく `buildFlow` の時間である。
- 負荷：同じ計算機でほかのエージェントが動いており、load average（1 分）は 5 から 7 だった。

## 結果

| 入力 | 前：全体（秒） | 後：全体 | 前：組版 1 周め | 後：組版 1 周め | 前：組版 2 周め | 後：組版 2 周め | 前：割り当て | 後：割り当て |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| manual | 4.13 | 3.71 | 1.071 | 1.063 | 0.531 | 0.204 | 19.49GB | 15.22GB |
| manual-dev | 3.46 | 2.87 | 0.584 | 0.590 | 0.404 | 0.079 | 16.68GB | 12.71GB |
| complex-horizontal | 0.41 | 0.38 | 0.177 | 0.177 | 0.041 | 0.004 | 1.59GB | 1.44GB |

各回の値（秒）。

| 入力 | 前：全体 | 後：全体 | 前：組版 2 周め | 後：組版 2 周め |
| --- | --- | --- | --- | --- |
| manual | 6.01、3.73、3.76、4.16、4.13 | 5.69、3.36、3.44、3.80、3.71 | 0.466、0.478、0.531、0.632、0.586 | 0.194、0.206、0.202、0.207、0.204 |
| manual-dev | 3.60、3.32、3.46、3.60、3.42 | 2.95、2.87、2.85、2.98、2.87 | 0.404、0.377、0.438、0.456、0.378 | 0.079、0.074、0.078、0.083、0.080 |
| complex-horizontal | 0.42、0.41、0.41、0.40、0.39 | 0.38、0.37、0.37、0.38、0.39 | 0.040、0.044、0.048、0.041、0.040 | 0.004、0.004、0.004、0.004、0.004 |

マニュアルの最大常駐は、前の 723MB から 728MB に対して、後は 890MB から 893MB だった。

### 出力

どの入力でも、前と後の 10 回の PDF の MD5 は一つだった。
`scripts/determinism.sh --no-manuals` の出力は `scripts/determinism/hashes.txt` と一致した。

## 読み取れること

- マニュアルの二周めの組版は 0.53 秒から 0.20 秒になり、ADR の「0.3 秒未満」を満たした。開発者向けマニュアルは 0.40 秒から 0.08 秒、`complex-horizontal` は 0.041 秒から 0.004 秒である。
- 全体の壁時計は、マニュアルで 10%、開発者向けマニュアルで 17%、`complex-horizontal` で 7% 縮んだ。
- 一周めの組版は前と後で変わらない（I4）。
- 縮んだ幅は ADR の見積もり（マニュアルで約 1.8 秒）より小さい。見積もりは調査の時点の二周めの 1.84 秒からで、その後に [ADR 0253](../adr/0253-memoise-run-shaping-and-shorten-the-memo-key.md) がシェイピングをメモ化したので、二周めのシェイピングの多くはメモから引かれていたと見られる。前の二周めは 0.53 秒で、そのうち 0.33 秒が縮んだ。
- マニュアルの二周めに残る 0.20 秒は、単位の列の作り直し（`flowUnits`）、前の周との比較、組み直す単位（`[ref-page]` を含む段落と索引の行）、行の番号付けと見られる。内訳は測っていない。
- 前の周の組版を次の周の終わりまで持つので、マニュアルの最大常駐は 165MB ほど増えた。ADR のトレードオフに書いたとおりである。

## 使ったコマンド

```sh
# ビルド（作業ツリーで、一時的な計時の行を足して）
cabal build exe:golem --disable-tests
# 前と後を交互に、一回ごとに build/ を消して
cd manual && rm -rf build && golem build --target pdf +RTS -s -RTS
```

## 限界

- 負荷を制御していない。交互に走らせて、前と後が同じ負荷を受けるようにした。
- 計時の行は、組版と配置の結果をその場で評価させるので、全体の壁時計は計時の行のないビルドとわずかに異なる。
