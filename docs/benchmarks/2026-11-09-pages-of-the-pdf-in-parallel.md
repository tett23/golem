# PDF のページの描画と内容のストリームを並列にした前後の時間（2026-11-09）

[docs/adr/0252](../adr/0252-draw-and-serialise-the-pages-of-the-pdf-in-parallel.md) の「テスト設計」が求める計測の記録である。
ページの描画と内容のストリームの直列化と圧縮を逐次に進める `main` と、spark で並列にした実装のブランチ（impl-0252）を、[docs/benchmarks/2026-11-09-typesetting-speed-survey.md](2026-11-09-typesetting-speed-survey.md)（以下「調査」）の表 3 の方法で、既定の capability と `-N1` で測った。
コミットした後は変更しない。

## 環境

- 計算機：調査と同じ Apple M1 Max（10 コア）、メモリ 64GB、macOS 27.0。
- golem：作業ツリーで `cabal build exe:golem --disable-tests` で作ったもの（GHC 9.10.3、最適化は cabal の既定）。どちらも、調査の表 3 と同じく `Golem.Typeset.Flow` と `Golem.Typeset.Draw` に段階の前後で時刻を読んで標準エラー出力に書く行を一時的に足し（コミットしていない）、`cabal.project.local` で `golem-cli` に `-rtsopts` を足してリンクした。
- 二組を測った。
  - 組 1：「前」は `main` の `b0dbdb11`（[ADR 0249](../adr/0249-link-golem-with-a-64-mb-allocation-area.md) と [ADR 0250](../adr/0250-character-class-tables-instead-of-list-membership.md) を含む）、「後」はそれに impl-0252 を合わせたもの。
  - 組 2：「前」は `main` の `dbfcc661`（[ADR 0254](../adr/0254-write-glyph-codes-without-printf.md) の直後、[ADR 0249](../adr/0249-link-golem-with-a-64-mb-allocation-area.md) と 0250 の前）、「後」はそれに impl-0252 を合わせたもの。
- 入力：`82861475` の `manual/`、`modules/golem-driver/test/fixtures/kanikosen/`、`modules/golem-driver/test/fixtures/pd/nightmare-abbey/` を作業用のディレクトリに写し、調査と同じフォントを置いた。二組とも同じ入力である。
- 方法：一回ごとに `build/` を消し、`golem build --target pdf +RTS -s -RTS` を「前」と「後」の順に交互に走らせた。既定の capability（10）で 5 回、`+RTS -N1 -RTS` で 3 回である。値は中央値である。「描画」は調査の表 3 と同じく `used`（各フォントで使ったグリフ）を評価する時間、「書き出し」は `writePdf` のバイト列を評価する時間である。
- 負荷：同じ計算機でほかのエージェントがビルドとテストを動かしており、load average（1 分）は 5 から 11 だった。

## 結果

### 組 1（`b0dbdb11` の上）

| 入力 | capability | 前：全体（秒） | 後：全体 | 前：描画 | 後：描画 | 前：書き出し | 後：書き出し |
| --- | --- | --- | --- | --- | --- | --- | --- |
| manual | 10 | 5.43 | 4.05 | 0.77 | 0.37 | 1.86 | 0.92 |
| manual | 1 | 11.60 | 11.34 | 0.99 | 1.03 | 1.95 | 1.66 |
| kanikosen | 10 | 1.14 | 0.77 | 0.30 | 0.13 | 0.42 | 0.21 |
| kanikosen | 1 | 2.42 | 2.32 | 0.47 | 0.45 | 0.59 | 0.52 |
| nightmare-abbey | 10 | 1.22 | 0.68 | 0.23 | 0.11 | 0.62 | 0.18 |
| nightmare-abbey | 1 | 2.56 | 2.26 | 0.48 | 0.45 | 0.87 | 0.61 |

全体の壁時計の各回（秒）。

| 入力 | capability | 前 | 後 |
| --- | --- | --- | --- |
| manual | 10 | 7.53、5.43、5.66、5.30、5.24 | 6.42、4.05、3.89、3.90、4.08 |
| manual | 1 | 11.53、11.73、11.60 | 11.34、11.17、11.34 |
| kanikosen | 10 | 1.14、1.13、1.14、1.17、1.20 | 0.76、0.77、0.75、0.77、0.81 |
| kanikosen | 1 | 2.42、2.43、2.38 | 2.35、2.32、2.30 |
| nightmare-abbey | 10 | 1.24、1.25、1.21、1.22、1.21 | 0.68、0.66、0.68、0.68、0.68 |
| nightmare-abbey | 1 | 2.50、2.70、2.56 | 2.24、2.26、2.28 |

描画と書き出しの合計の、`-N1` に対する速度向上（「後」どうし）。

| 入力 | `-N1`（秒） | 10（秒） | 比 |
| --- | --- | --- | --- |
| manual | 2.69 | 1.29 | 2.1 倍 |
| kanikosen | 0.97 | 0.34 | 2.9 倍 |
| nightmare-abbey | 1.06 | 0.29 | 3.7 倍 |

`+RTS -s` の `SPARKS` の行（「後」、capability 10）。

| 入力 | spark | converted | fizzled | GC'd |
| --- | --- | --- | --- | --- |
| manual | 752 | 750 | 2 | 0 |
| kanikosen | 258 | 256 | 2 | 0 |
| nightmare-abbey | 176 | 174 から 175 | 1 から 2 | 0 |

spark の数はページの数の 2 倍である（描画のグリフの決定と、内容のストリームの二つ）。
マニュアルの最大常駐は、前の 626MB から 629MB に対して、後は 622MB から 624MB だった。

### 組 2（`dbfcc661` の上）

| 入力 | capability | 前：全体（秒） | 後：全体 | 前：描画 | 後：描画 | 前：書き出し | 後：書き出し |
| --- | --- | --- | --- | --- | --- | --- | --- |
| manual | 10 | 9.37 | 7.48 | 1.62 | 0.50 | 2.04 | 1.09 |
| manual | 1 | 16.32 | 16.08 | 1.47 | 1.47 | 2.36 | 1.92 |
| kanikosen | 10 | 1.95 | 1.30 | 0.58 | 0.18 | 0.51 | 0.27 |
| kanikosen | 1 | 3.24 | 3.17 | 0.55 | 0.55 | 0.44 | 0.46 |
| nightmare-abbey | 10 | 2.29 | 1.31 | 0.71 | 0.20 | 0.78 | 0.27 |
| nightmare-abbey | 1 | 3.36 | 3.24 | 0.70 | 0.65 | 0.77 | 0.56 |

### 書き出しだけを並列にした場合

「メンテナーが決めること」の 2 のとおり、まず `writePdf` の中だけで並列にして測った（組 2 と同じ `dbfcc661` の上、capability 10、5 回の中央値）。

| 入力 | 前：描画 | 前：書き出し | 書き出しだけ：描画 | 書き出しだけ：書き出し |
| --- | --- | --- | --- | --- |
| manual | 1.61 | 1.98 | 1.60 | 1.01 |
| kanikosen | 0.56 | 0.49 | 0.56 | 0.25 |
| nightmare-abbey | 0.70 | 0.77 | 0.69 | 0.24 |

書き出しは半分から三分の一になったが、描画は `used` の走査で逐次に進んだままだった。
描画と書き出しの合計の `-N1` に対する比は、マニュアルで 1.2 倍にとどまり、ADR の「2 倍以上」に届かなかった。
描画の逐次の分（マニュアルで 1.6 秒）が大きいので、各ページのグリフの決定も spark で先に投げる形にした（上の「後」）。

### 出力

どの組でも、同じ入力の PDF の MD5 は、前と後、capability 10 と 1 のすべての回で一つだった（マニュアル、『蟹工船』、『Nightmare Abbey』の各 16 回）。
`scripts/determinism.sh --no-manuals` の出力は `scripts/determinism/hashes.txt` と一致し、`scripts/env-determinism/check.sh` の `caps-one` と `caps-two` は通った。

## 読み取れること

- 描画と書き出しの合計は、capability 10 で `-N1` の 2.1 倍から 3.7 倍速くなった。ADR の見積もり（2.2 倍から 3 倍）とほぼ同じである。
- 全体の壁時計は、組 1 でマニュアルが 25%、『蟹工船』が 32%、『Nightmare Abbey』が 44% 縮んだ。組 2 では 20%、33%、43% である。ADR の見積もり（20% から 25%、35%、40%）とほぼ同じである。
- spark はほとんどが converted で、fizzled は各回 2 つ以下だった。`-N1` では半分ほどが fizzled になるが、出力は変わらない。
- マニュアルの書き出しには、並列にした後も 0.9 秒から 1.1 秒が残る。全ページの印を走査するフォントの番号付け、構造の木、xref と trailer の直列化は逐次である。

## 使ったコマンド

```sh
# ビルド（作業ツリーで、一時的な計時の行を足して）
cabal build exe:golem --disable-tests
# 前と後を交互に、一回ごとに build/ を消して
cd manual && rm -rf build && golem build --target pdf +RTS -s -RTS
cd manual && rm -rf build && golem build --target pdf +RTS -s -N1 -RTS
```

## 限界

- 負荷を制御していない。交互に走らせて、前と後が同じ負荷を受けるようにした。
- 計時の行は描画の結果を `used` の走査で先に評価させるので、全体の壁時計は計時の行のないビルドとわずかに異なる。
