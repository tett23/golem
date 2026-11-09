# グリフの符号を `Text.Printf` を使わずに書いた前後の `writePdf` の時間（2026-11-09）

[docs/adr/0254](../adr/0254-write-glyph-codes-without-printf.md) の「テスト設計」が求める計測の記録である。
グリフの符号と xref のオフセットを `printf` で書く `origin/main`（コミット `82861475`）と、`Builder` で直接に書く実装のブランチ（impl-0254）の `writePdf` の時間を、[docs/benchmarks/2026-11-09-typesetting-speed-survey.md](2026-11-09-typesetting-speed-survey.md)（以下「調査」）の表 3 の方法で測った。
コミットした後は変更しない。

## 環境

- 計算機：調査と同じ Apple M1 Max（10 コア）、メモリ 64GB、macOS 27.0。
- golem：impl-0254 の作業ツリーで `cabal build exe:golem --disable-tests` で作った二つ（GHC 9.10.3、最適化は cabal の既定）。「前」は `82861475` の `golem-pdf` のまま、「後」は [ADR 0254](../adr/0254-write-glyph-codes-without-printf.md) の変更を入れたものである。どちらも、調査の表 3 と同じく `Golem.Typeset.Flow` と `Golem.Typeset.Draw` に段階の前後で `GHC.Clock.getMonotonicTime` を読んで標準エラー出力に書く行を一時的に足し（コミットしていない）、`cabal.project.local` で `golem-cli` に `-rtsopts` を足してリンクした。
- 入力：`82861475` の `manual/`、`modules/golem-driver/test/fixtures/kanikosen/`、`modules/golem-driver/test/fixtures/pd/nightmare-abbey/` を作業用のディレクトリに写し、調査と同じフォントを置いた。
- 方法：一回ごとに `build/` を消し、`golem build --target pdf +RTS -s -RTS` を「前」と「後」の順に交互に走らせた。「書き出し」は、調査の表 3 と同じく `writePdf` のバイト列を `BS.length` で評価する時間である。値は中央値である。
- 負荷：同じ計算機でほかのエージェントが GHC のビルドとテストを動かしており、load average（1 分）は 11 から 22 だった。全体の壁時計は負荷で大きく揺れる（マニュアルで 10 秒から 62 秒）。そのため、交互に走らせて対にした値と、負荷の影響を受けない割り当ての量を主に見る。

## 結果

### 書き出し（`writePdf`）の時間

| 入力 | 回数 | 前（秒） | 後（秒） | 差 |
| --- | --- | --- | --- | --- |
| manual（1 回め） | 7 | 3.22 | 2.28 | −29% |
| manual（2 回め） | 9 | 3.46 | 2.94 | −15% |
| kanikosen | 7 | 0.77 | 0.57 | −26% |
| nightmare-abbey | 7 | 1.09 | 0.90 | −18% |

各回の値（秒）。

| 入力 | 前 | 後 |
| --- | --- | --- |
| manual（1 回め） | 5.85、3.22、2.57、10.77、3.63、2.77、2.73 | 5.07、2.05、12.67、10.60、2.04、2.28、2.13 |
| manual（2 回め） | 2.81、2.84、3.03、5.51、4.50、6.01、3.90、3.30、3.46 | 2.19、2.39、2.55、4.87、7.66、3.79、2.94、2.51、3.07 |
| kanikosen | 0.65、0.77、0.71、0.79、0.96、0.71、0.94 | 0.52、0.58、0.57、0.55、0.60、0.71、0.53 |
| nightmare-abbey | 1.07、1.68、1.11、1.07、1.12、1.09、1.09 | 1.04、0.93、0.81、0.85、0.87、0.90、0.91 |

交互に走らせた対で「後」のほうが短かったのは、マニュアルの 16 対のうち 14 対、『蟹工船』と『Nightmare Abbey』の 7 対のすべてである。

### 割り当ての量

`+RTS -s` の「bytes allocated in the heap」の中央値である。
回ごとの差は 0.001% 未満で、負荷によらない。

| 入力 | 前 | 後 | 差 |
| --- | --- | --- | --- |
| manual | 50.11GB | 48.71GB | −1.40GB（−2.8%） |
| kanikosen | 9.44GB | 9.06GB | −0.38GB（−4.0%） |
| nightmare-abbey | 9.79GB | 9.12GB | −0.67GB（−6.8%） |

### 全体の壁時計

| 入力 | 前（秒） | 後（秒） |
| --- | --- | --- |
| manual（2 回め、9 回） | 17.80 | 14.65 |
| kanikosen（7 回） | 2.55 | 2.23 |
| nightmare-abbey（7 回） | 2.90 | 2.74 |

負荷のため、調査の表 1（マニュアルで 11.55 秒）より長く、揺れも大きい。
差の大きさは、この表ではなく書き出しの時間と割り当ての量で読む。

### 出力

マニュアルの 18 回（前と後の 9 回ずつ）の PDF の MD5 はすべて同じだった。
`scripts/determinism.sh --no-manuals` の出力は、コミットされた `scripts/determinism/hashes.txt` と一致した。

## 読み取れること

- `writePdf` の時間は、マニュアルで 0.5 秒から 0.9 秒（15% から 29%）、『蟹工船』で 0.2 秒（26%）、『Nightmare Abbey』で 0.2 秒（18%）縮んだ。ADR の見積もり（マニュアルで 0.3 秒から 1 秒、`writePdf` の 1 割から 4 割）の範囲に入る。
- 割り当ては、マニュアルで 1.4GB 減った。グリフの数（調査の表 3 で描画のシェイピング 263,597 字）で割ると、一グリフあたり 5KB ほどである。`printf` が呼ぶたびに書式を解釈して `String` を作っていた分と見られる。
- `writePdf` の残り（マニュアルで 2.3 秒から 2.9 秒）は、`Builder` の構築、数の書き出し、Flate、`ByteString` の連結で、この ADR では縮まない。[ADR 0252](../adr/0252-draw-and-serialise-the-pages-of-the-pdf-in-parallel.md) がページごとに並列にする。

## 使ったコマンド

```sh
# ビルド（impl-0254 の作業ツリーで、一時的な計時の行を足して）
cabal build exe:golem --disable-tests
# 前と後を交互に、一回ごとに build/ を消して
cd manual && rm -rf build && golem build --target pdf +RTS -s -RTS
```

## 限界

- 負荷を制御できず、壁時計の揺れが大きい。書き出しの中央値も、マニュアルの二回の計測で 0.5 秒と 0.9 秒の差になった。
- 計時の行は描画の結果を `used` の走査で先に評価させるので、全体の壁時計は計時の行のないビルドとわずかに異なる。
