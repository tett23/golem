# 組版の速度の調査（2026-11-09）

メンテナーの「組版が遅すぎるので速度改善をする」を受けて、`main` の `golem` の時間がどこにかかっているかを測った記録である。
数字は ADR の根拠に使う（[docs/adr/0249](../adr/0249-link-golem-with-a-64-mb-allocation-area.md) から [docs/adr/0254](../adr/0254-write-glyph-codes-without-printf.md)）。
コミットした後は変更しない。

## 環境

- 計算機：Apple M1 Max（10 コア、性能コア 8 と効率コア 2）、メモリ 64GB、macOS 27.0。
- golem：`origin/main` のコミット `08d09332`（2026-11-09）を新しい作業ツリー（`git worktree add`）に取り出し、`cabal build exe:golem --disable-tests` でビルドしたもの。GHC 9.10.3、cabal 3.18.1.0、最適化は cabal の既定（`-O1`）。wasmtime はリポジトリの `third_party/wasmtime`（49.0.5）。
- RTS のオプションを変える計測のためだけに、`cabal.project.local` に `package golem-cli` の `ghc-options: -rtsopts` を足してリンクし直した。製品のビルド設定は変えていない。
- 入力：`manual/`（利用者向けマニュアル、.gm で 632KB、PDF 217 ページ）、`manual-dev/`（開発者向けマニュアル、485KB、PDF 220 ページ）、`modules/golem-driver/test/fixtures/` の `kanikosen`（204KB、129 ページ）、`complex-horizontal`、`complex-vertical`、`pd/` の十冊。フォントは `scripts/manual/fetch-fonts.sh` が取るものと `scripts/fixtures/copy-fonts.sh` と同じものを置いた。`complex-*` には `scripts/visual/build.sh` と同じく NotoSerifJP と SourceSansPro を置いた。
- 方法：一回ごとに `build/` を消し、`golem <コマンド> +RTS -s -RTS` を 3 回（`check`、HTML、EPUB は 2 回）実行した。壁時計はコマンドの前後の時刻の差、CPU 時間と割り当てと最大常駐は `+RTS -s` の値である。
- 負荷：ほかの作業ツリーのビルドは動かしていないが、同じ計算機でほかのエージェントのセッションが動いていた可能性があり、load average は制御していない。外れ値（マニュアルの 1 回め 16.7 秒、開発者向けマニュアルの 20.1 秒と 14.1 秒）はそのためと見て、中央値を使う。

## 表 1：コマンドと入力ごとの時間

壁時計と CPU 時間は 3 回（または 2 回）の中央値、割り当てとその比は中央値、最大常駐は最大である。
「GC」は CPU 時間に占める GC の割合、「CPU/壁」は CPU 時間を壁時計で割った値（並列の度合い）である。

| 入力 | コマンド | 壁時計（秒） | 3 回（秒） | CPU（秒） | 割り当て | 最大常駐 | GC | CPU/壁 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| manual | `build --target pdf` | 11.55 | 16.70、11.55、11.48 | 26.36 | 50.1GB | 845MB | 29% | 2.3 |
| manual | `build --target html` | 1.43 | 1.37、1.66、1.43 | 2.32 | 2.4GB | 73MB | 58% | 1.6 |
| manual | `check` | 0.89 | 0.89、0.95、0.88 | 1.38 | 1.2GB | 38MB | 61% | 1.6 |
| manual-dev | `build --target pdf` | 14.10 | 20.12、14.10、9.66 | 28.88 | 41.7GB | 602MB | 27% | 2.0 |
| manual-dev | `check` | 0.56 | 0.56、0.56 | 0.83 | 0.8GB | 28MB | 61% | 1.5 |
| kanikosen | `build --target pdf` | 2.48 | 2.48、2.29、2.54 | 5.21 | 9.4GB | 173MB | 29% | 2.1 |
| kanikosen | `build --target html` | 0.23 | 0.23、0.23 | 0.33 | 0.4GB | 30MB | 54% | 1.4 |
| kanikosen | `build --target epub` | 0.53 | 0.52、0.53 | 0.58 | 0.4GB | 30MB | 30% | 1.1 |
| kanikosen | `check` | 0.26 | 0.29、0.23 | 0.30 | 0.3GB | 30MB | 55% | 1.2 |
| complex-horizontal | `build --target pdf` | 0.79 | 0.79、0.78、0.79 | 1.45 | 2.6GB | 81MB | 40% | 1.8 |
| complex-vertical | `build --target pdf` | 0.43 | 0.43、0.42、0.43 | 0.67 | 1.3GB | 28MB | 26% | 1.6 |
| pd/elements-of-style | `build --target pdf` | 1.45 | 1.45、1.46、1.43 | 2.67 | 5.2GB | 88MB | 32% | 1.8 |
| pd/frogs | `build --target pdf` | 1.52 | 1.56、1.52、1.49 | 2.71 | 4.9GB | 96MB | 32% | 1.8 |
| pd/haru-to-shura | `build --target pdf` | 1.89 | 2.07、1.89、1.85 | 3.60 | 7.3GB | 130MB | 28% | 1.9 |
| pd/ichiaku-no-suna | `build --target pdf` | 0.96 | 0.95、0.96、0.98 | 1.69 | 3.2GB | 72MB | 35% | 1.8 |
| pd/koya-hijiri | `build --target pdf` | 1.73 | 1.73、1.73、1.74 | 3.27 | 6.2GB | 109MB | 33% | 1.9 |
| pd/merry-wives | `build --target pdf` | 2.49 | 2.44、2.86、2.49 | 4.67 | 8.6GB | 170MB | 33% | 1.9 |
| pd/nightmare-abbey | `build --target pdf` | 2.64 | 2.81、2.64、2.60 | 5.34 | 9.8GB | 198MB | 35% | 2.0 |
| pd/nightmare-abbey | `build --target html` | 0.20 | 0.19、0.20 | 0.28 | 0.4GB | 44MB | 56% | 1.4 |
| pd/nightmare-abbey | `build --target epub` | 0.22 | 0.23、0.21 | 0.30 | 0.4GB | 44MB | 51% | 1.4 |
| pd/nightmare-abbey | `check` | 0.18 | 0.18、0.18 | 0.25 | 0.3GB | 44MB | 58% | 1.4 |
| pd/snark | `build --target pdf` | 0.54 | 0.57、0.54、0.53 | 0.91 | 1.7GB | 37MB | 32% | 1.7 |
| pd/taira-no-masakado | `build --target pdf` | 2.38 | 2.41、2.38、2.26 | 6.62 | 9.2GB | 234MB | 34% | 2.8 |
| pd/ushiyama-hotel | `build --target pdf` | 1.20 | 1.20、1.22、1.13 | 2.39 | 4.9GB | 87MB | 30% | 2.0 |

十冊の PDF は [docs/benchmarks/2026-11-06-pd-fixtures-layout-time.md](2026-11-06-pd-fixtures-layout-time.md) と同じ程度である（`nightmare-abbey` は 2.27 秒から 2.64 秒）。

読み取れること。

- 時間は PDF にある。マニュアルの `check`（S0 と S1）は 0.9 秒、HTML は 1.4 秒で、PDF の 11.5 秒のうち 10 秒以上が PDF の経路である。
- GC が CPU 時間の 3 割を占める。マニュアルは 50GB を割り当て、世代 0 の GC が 5,400 回から 5,800 回起きる（表 2）。
- 並列の度合いは低い。10 個の capability で CPU/壁は 2.0 から 2.8 で、段落の組版の外は逐次である（表 3）。

## 表 2：RTS のオプション

`-rtsopts` でリンクし直した `golem` に `+RTS -s <オプション> -RTS` を付け、`build --target pdf` を各 3 回走らせた。
値は 3 回の範囲、GC 0 は世代 0 の GC の回数、メモリは `+RTS -s` の「total memory in use」である。

| 入力 | オプション | 壁時計（秒） | CPU（秒） | GC 0 | メモリ |
| --- | --- | --- | --- | --- | --- |
| manual | なし | 9.67 から 9.88 | 22.36 から 22.62 | 5283 から 5368 | 1.80GB から 1.87GB |
| manual | `-N1` | 16.83 から 18.59 | 16.48 から 17.75 | 11836 から 11837 | 1.84GB から 1.85GB |
| manual | `-N4` | 11.11 から 12.98 | 19.09 から 22.07 | 6803 から 6869 | 1.73GB から 1.95GB |
| manual | `-N8` | 9.84 から 10.37 | 20.95 から 21.64 | 5467 から 5568 | 1.76GB から 1.80GB |
| manual | `-qg` | 10.55 から 10.70 | 18.23 から 18.37 | 5264 から 5274 | 1.88GB から 1.94GB |
| manual | `-A16m` | 9.26 から 9.83 | 19.48 から 19.67 | 348 | 2.01GB から 2.04GB |
| manual | `-A32m -qn4` | 7.38 から 7.57 | 18.44 から 18.69 | 155 | 2.36GB から 2.37GB |
| manual | `-A64m` | 7.12 から 7.84 | 18.77 から 19.14 | 73 | 2.34GB |
| manual | `-A64m -qg` | 8.78 から 9.51 | 16.13 から 16.73 | 73 | 2.32GB |
| manual | `-A64m -qn4` | 7.18 から 8.70 | 17.36 から 18.34 | 73 | 2.33GB から 2.34GB |
| manual | `-A64m -n4m -qn4` | 7.53 から 8.29 | 17.74 から 18.62 | 73 | 2.34GB |
| manual | `-A64m -qg -N4` | 11.09 から 11.80 | 17.02 から 17.88 | 183 | 2.04GB から 2.06GB |
| manual | `-A64m -qg -N8` | 9.18 から 10.53 | 16.43 から 17.63 | 90 から 91 | 2.24GB |
| manual | `-A128m -n4m` | 6.90 から 6.97 | 17.59 から 18.18 | 33 | 3.15GB から 3.16GB |
| manual | `--nonmoving-gc -A64m` | 9.36 から 10.56 | 19.16 から 19.40 | 73 | 2.54GB から 2.62GB |
| manual-dev | なし | 8.42 から 13.89 | 19.23 から 22.18 | 5037 から 5669 | 1.29GB から 1.31GB |
| manual-dev | `-qg` | 9.12 から 9.35 | 15.30 から 15.74 | 4988 から 5014 | 1.22GB から 1.30GB |
| manual-dev | `-A32m` | 6.28 から 6.45 | 16.77 から 17.26 | 126 | 1.52GB から 1.58GB |
| manual-dev | `-A32m -qn4` | 6.37 から 6.75 | 15.28 から 15.66 | 126 | 1.57GB |
| manual-dev | `-A64m` | 6.10 から 6.22 | 15.99 から 16.36 | 57 | 1.78GB から 1.86GB |
| manual-dev | `-A64m -qg` | 7.87 から 7.91 | 14.06 から 14.10 | 57 | 1.85GB |
| manual-dev | `-A64m -qn4` | 6.36 から 6.97 | 14.87 から 15.26 | 57 | 1.79GB から 1.88GB |
| kanikosen | なし | 2.06 から 2.13 | 4.50 から 4.53 | 1106 から 1130 | 0.44GB から 0.46GB |
| kanikosen | `-A32m` | 1.53 から 1.56 | 3.81 から 3.82 | 25 | 0.69GB |
| kanikosen | `-A32m -qn4` | 1.57 から 1.59 | 3.49 から 3.50 | 25 | 0.69GB |
| kanikosen | `-A64m` | 1.53 から 1.59 | 3.64 から 3.75 | 11 | 0.97GB から 1.01GB |
| kanikosen | `-A64m -qg` | 1.90 から 1.95 | 3.28 から 3.30 | 11 | 0.98GB から 0.99GB |
| kanikosen | `-A64m -qn4` | 1.58 から 1.61 | 3.42 から 3.47 | 11 | 0.96GB から 1.00GB |
| nightmare-abbey | なし | 2.49 から 2.55 | 5.10 から 5.15 | 1339 から 1344 | 0.48GB から 0.49GB |
| nightmare-abbey | `-A32m` | 1.83 から 1.87 | 4.05 から 4.13 | 25 | 0.66GB から 0.69GB |
| nightmare-abbey | `-A32m -qn4` | 1.82 から 1.86 | 3.66 から 3.68 | 25 | 0.64GB から 0.68GB |
| nightmare-abbey | `-A64m` | 1.77 から 1.81 | 3.80 から 3.85 | 12 | 0.93GB から 0.94GB |
| nightmare-abbey | `-A64m -qg` | 2.26 から 2.27 | 3.37 から 3.40 | 11 | 1.01GB |
| nightmare-abbey | `-A64m -qn4` | 1.81 から 1.87 | 3.54 から 3.63 | 11 | 1.00GB から 1.01GB |

読み取れること。

- nursery を 64MB にすると、四つの入力のすべてで壁時計が 25% から 30% 縮む。32MB でもほぼ同じである。
- `-N1` の CPU 時間（16.5 秒）と `-N10` の CPU 時間（22.4 秒）の差は、並列化の費用（GC の同期と、capability ごとの nursery が埋まるたびの停止）である。
- 並列 GC を止める `-qg` は CPU 時間を減らすが壁時計を延ばす。GC のスレッドを限る `-qn4` は `-A64m` 単独と差がない。

## 表 3：段階ごとの時間

`Golem.Typeset.Flow` と `Golem.Typeset.Draw` に、段階の前後で `GHC.Clock.getMonotonicTime` を読んで標準エラー出力に書く行を一時的に足し（コミットしていない）、`build --target pdf` を 1 回ずつ走らせた。
`Golem.Font.shapeUnits`（HarfBuzz の呼び出し）と `Golem.Layout.KnuthPlass.breakParagraph` の回数も、同じく一時的なカウンタで数えた。
「組版」は `buildFlow`（段落ごとのシェイピングと行分割、行の番号付け）、「配置」は `paginateWithin`、「描画」は `writeDocumentView` の結果の `used`（全ページの描画）を評価する時間、「書き出し」は `writePdf` のバイト列を評価する時間である。
S0 と S1（解析、評価、文書の組み立て）は表 1 の `check` の時間で読む。
「その他」は全体の壁時計からこれらを引いた残りで、プロセスの起動、入力の読み込み、PDF の後の diagnostics と view の計算、ファイルの書き出しを含む。

| 入力 | capability | 全体（秒） | 組版 1 周め（秒、CPU） | 配置 1 周め | 組版 2 周め（秒、CPU） | 配置 2 周め | 描画（秒） | サブセット化（秒） | 書き出し（秒） | その他（秒） |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| manual | 10 | 12.55 | 2.66（8.19） | 0.23 | 1.84（7.07） | 0.10 | 2.33 | 0.05 | 2.55 | 2.79 |
| manual | 1 | 16.50 | 5.74（5.71） | 0.09 | 4.87（4.85） | 0.08 | 2.07 | 0.04 | 2.45 | 1.16 |
| manual-dev | 10 | 9.62 | 1.43（6.02） | 0.36 | 1.78（5.71） | 0.36 | 2.07 | 0.04 | 2.42 | 1.16 |
| kanikosen | 10 | 2.50 | 0.63（2.52） | 0.02 | なし | なし | 0.80 | 0.03 | 0.76 | 0.26 |
| kanikosen | 1 | 3.71 | 1.89（1.85） | 0.01 | なし | なし | 0.74 | 0.03 | 0.76 | 0.28 |
| nightmare-abbey | 10 | 2.92 | 0.64（2.41） | 0.07 | なし | なし | 0.86 | 0.00 | 1.11 | 0.24 |
| nightmare-abbey | 1 | 4.04 | 1.68（1.67） | 0.05 | なし | なし | 0.94 | 0.01 | 1.11 | 0.25 |
| taira-no-masakado | 10 | 2.82 | 1.39（5.03） | 0.01 | なし | なし | 0.59 | 0.03 | 0.55 | 0.25 |
| complex-horizontal | 10 | 0.80 | 0.42（0.86） | 0.01 | 0.07（0.27） | 0.01 | 0.07 | 0.01 | 0.09 | 0.12 |
| snark | 10 | 0.56 | 0.08（0.29） | 0.00 | なし | なし | 0.15 | 0.00 | 0.22 | 0.11 |

単位と行の数、シェイピングと行分割の回数。
「シェイピング（組版）」は `layoutPdf` が終わるまでの `shapeUnits` の回数と文字数、「シェイピング（描画）」は描画で増えた分である。

| 入力 | 単位 | 行 | ページ | ラベル | 索引の印 | 行分割の段落 | 行分割の項目 | シェイピング（組版） | シェイピング（描画） |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| manual | 3257 | 9073 | 380（面） | 82 | 204 | 8497 | 644,443 | 58,602 回、196,000 字 | 189,156 回、263,597 字 |
| manual-dev | 1664 | 5090 | 220 | 32 | 115 | 5386 | 493,898 | 45,970 回、201,933 字 | 144,916 回、225,482 字 |
| kanikosen | 864 | 1938 | 129 | 0 | 0 | 862 | 114,973 | 25,721 回、48,158 字 | 129,596 回、129,814 字 |
| nightmare-abbey | 772 | 2680 | 88 | 0 | 0 | 761 | 75,459 | 36,551 回、126,901 字 | 37,568 回、129,283 字 |
| taira-no-masakado | 63 | 963 | 61 | 0 | 0 | 63 | 73,531 | 24,045 回、44,311 字 | 86,639 回、86,732 字 |
| complex-horizontal | 135 | 427 | 28 | 4 | 13 | 372 | 21,829 | 2,996 回、7,206 字 | 6,268 回、7,720 字 |
| snark | 777 | 661 | 28 | 0 | 0 | 614 | 14,025 | 6,217 回、22,880 字 | 6,347 回、23,313 字 |

マニュアルの「ページ」は 380 で、`paginateWithin` が返す段の数である（見開きの左右で数える）。
行分割の段落の数が単位の数より多いのは、脚注、傍注、キャプション、表の各セルも段落として分割し、二周めで二度数えるためである。

読み取れること。

- マニュアルの 12.55 秒は、組版 4.5 秒（二周）、描画 2.3 秒、書き出し 2.6 秒、配置 0.3 秒、S0 と S1 の 0.9 秒、その他 2 秒ほどに分かれる。
- ページ番号の参照の不動点（[golem-layout ADR 0003](../golem-layout/adr/0003-pagination-and-s2.md)）は、索引の印かラベルがあると二周めが必ず走り、すべての単位を組み直す。二周めは一周めとほぼ同じ時間（1.84 秒、CPU 7.07 秒）で、全体の 15% である。十冊には参照がなく一周で終わる。
- 描画と書き出しは逐次で、capability が 1 でも 10 でも同じ時間である。二つで全体の 39%（マニュアル）から 62%（kanikosen）を占める。
- 段落の組版の並列の速度向上は、10 個の capability で 2.2 倍から 3.0 倍にとどまる。CPU 時間は `-N1` の 5.7 秒から `-N10` の 8.2 秒に増える。
- 描画はシェイピングを組版より多く呼ぶ。マニュアルで組版の 58,602 回に対して描画は 189,156 回で、同じテキストを組版と描画で二度シェイピングしている。組版では一字の送りと二字のカーニングだけがメモ化され（[docs/adr/0034](../adr/0034-fewer-unsafe-perform-io.md)）、単語とランのシェイピングはメモ化されない。

## 表 4：関数ごとの時間の見積もり

GHC のプロファイルのビルドは、この計算機の空き容量（1.1GB）では依存するパッケージをプロファイル付きでビルドし直せず、取れなかった。
代わりに、macOS の `sample` で `golem build --target pdf` のすべてのスレッドのスタックを 1 ミリ秒ごとに集め、葉のフレームのアドレスを `nm -n golem` のシンボル表で GHC のトップレベルの関数に対応づけて数えた（スクリプトは `attrib.py`、この記録とともに置いていない）。
待ちのスレッド（`kevent`、`__psynch_cvwait` など）を除いた「動いている」サンプルに対する割合である。
関数の中のローカルなラベルは、それを含むトップレベルの関数に数えた。
遅延評価のサンク（`stg_upd_frame`、`stg_ap_*`）は呼び出し元を持たないので、関数に割り当てられない。

| 分類 | manual | manual-dev | kanikosen | nightmare-abbey |
| --- | --- | --- | --- | --- |
| GC（`evacuate`、`scavenge_block`、`alloc_for_copy` など） | 24.6% | 24.0% | 28.8% | 48.3% |
| RTS のサンクの更新と適用（`stg_upd_frame`、`stg_ap_*`、`stg_BLACKHOLE`） | 15.9% | 14.6% | 15.5% | 11.8% |
| スレッドローカル記憶の取得（`_tlv_get_addr`、GC のワーカーが使う） | 5.7% | 4.8% | 7.7% | 11.0% |
| golem-layout | 13.0% | 15.0% | 6.4% | 5.1% |
| golem-typeset | 7.9% | 8.5% | 5.7% | 1.1% |
| golem-font | 0.7% | 0.3% | 2.4% | 0.6% |
| HarfBuzz（C++） | 1.8% | 0.5% | 5.2% | 1.8% |
| ghc-prim（`unpackNBytes#` など、String リテラルの展開） | 10.9% | 9.4% | 5.0% | 7.6% |
| ghc-bignum（`Integer` の乗除） | 3.6% | 5.7% | 1.1% | 0.2% |
| ghc-internal（`++`、`length`、`round` など） | 4.6% | 6.3% | 3.4% | 1.8% |
| その他（割り当てられないローカルなラベル、`eval_thunk_selector` など） | 8.3% | 7.1% | 12.9% | 7.5% |

葉の関数の上位（manual、動いているサンプル 6,285 のうち）。

| 関数 | 割合 |
| --- | --- |
| `evacuate`（GC） | 14.9% |
| `GHC.CString.unpackNBytes#` | 9.6% |
| `stg_upd_frame` | 7.7% |
| `Golem.Layout.CharClass.isDualCharacter` | 6.3% |
| `Golem.Typeset.Memo.trieAt` | 6.3% |
| `_tlv_get_addr` | 5.7% |
| `scavenge_block`（GC） | 3.9% |
| `stg_ap_pp_fast` | 3.6% |
| `alloc_for_copy`（GC） | 2.8% |
| `Golem.Layout.KnuthPlass` の内部の `go`（活性のノードの走査） | 2.5% |
| `stg_BLACKHOLE` | 2.3% |
| `Golem.Layout.Japanese.markPartsText` | 1.6% |
| `GHC.Num.Integer.integerMul` | 0.9% |
| `Golem.Layout.CharClass.charClass` | 0.7% |
| `Golem.Font.shapeUnits`（HarfBuzz を呼ぶ側） | 0.4% |

manual-dev では `Memo.trieAt` が 7.4%、`unpackNBytes#` が 8.1%、`isDualCharacter` が 4.9%、`KnuthPlass` の `go` が 4.1%、`markPartsText` が 3.2% である。
kanikosen では `unpackNBytes#` が 4.4%、`isDualCharacter` が 4.1%、`Memo.trieAt` が 1.9%、`shapeUnits` が 1.7% である。

読み取れること。

- `unpackNBytes#` と `isDualCharacter` と `charClass` を合わせて、動いている時間の 8% から 17% である。`Golem.Layout.CharClass` は文字の種類を `c \`elem\` ("「『（…" :: String)` の並びで判定し、`isDualCharacter` も 13 字の `String` への `elem` である（[`CharClass.hs`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-layout/src/Golem/Layout/CharClass.hs#L38-L64)）。GHC は `elem c (unpackCString# lit)` を、リテラルを呼ぶたびに UTF-8 から復号する形に書き換えるので、一文字の判定ごとに数十字から百字ほどを復号する。`isDualCharacter` は、シェイピングのフォントを決める `fontFor` が一字ごとに呼ぶ。
- `Memo.trieAt` は 2% から 7% である。一字の送りのメモの鍵が `[Int]`（縦横、両用、役割の文字列、特徴の文字列、テキスト）で 10 個ほどの要素を持ち、要素ごとに 8 段の木を降りる。
- `Integer` の演算（`Sp` は `newtype Sp = Sp Integer`）は 4% から 6% である。
- HarfBuzz そのものは 2% から 5% で、シェイピングの費用の多くは Haskell 側（引数の変換、結果の読み出し、クラスタの集計）とサンクにある。

## 使ったコマンド

```sh
# ビルド（新しい作業ツリーで）
cabal build exe:golem --disable-tests
# 表 1：一回ごとに build/ を消して 3 回
cd manual && rm -rf build && golem build --target pdf +RTS -s -RTS
# 表 2：cabal.project.local に package golem-cli / ghc-options: -rtsopts を足してリンクし直し
golem build --target pdf +RTS -s -A64m -RTS
# 表 3：Flow.hs と Draw.hs に一時的な計時の行を足してビルドし直し、標準エラー出力の [perf] の行を読む
/usr/bin/time -p golem build --target pdf
# 表 4：1 ミリ秒ごとのサンプルと、シンボル表による対応づけ
golem build --target pdf & sample $! 11 1 -mayDie -file sample.txt
nm -n golem > golem.nm
```

## 限界

- プロファイルのビルド（`--enable-profiling`）は空き容量の不足で取れなかった。表 4 はサンプルの葉のフレームの集計で、関数の包含時間（呼び出し先を含む時間）ではない。
- 表 3 は各 1 回の計測で、表 1 の中央値より 1 秒ほど長い（計時の行の分と、揺れ）。
- 「その他」の 1 秒から 3 秒は分けて測っていない。PDF の後の diagnostics（`dashInkNotices`、`runningHeadNotices`、`missingGlyphs`）と view の計算、`pages.json` の書き出しを含む。
- 負荷を制御していないので、外れ値を含む行がある。
