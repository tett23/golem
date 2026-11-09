# 文字の種類の判定を表にした `golem` の速さ（2026-11-09）

[docs/adr/0250](../adr/0250-character-class-tables-instead-of-list-membership.md) の実装のプルリクエストで、文字の種類の判定を `String` への `elem` から `IntSet` の参照に変える前と後の `golem build --target pdf` を測った記録である。
方法は [docs/benchmarks/2026-11-09-typesetting-speed-survey.md](2026-11-09-typesetting-speed-survey.md)（以下「調査」）の表 1 と表 4 にそろえた。
コミットした後は変更しない。

## 環境

- 計算機：調査と同じ Apple M1 Max（10 コア、性能コア 8 と効率コア 2）、メモリ 64GB、macOS 27.0。
- 変更前：`origin/main` のコミット `8f8dc345` に、[docs/adr/0249](../adr/0249-link-golem-with-a-64-mb-allocation-area.md) の `-with-rtsopts=-N -A64m` を足してビルドしたもの。[ADR 0249](../adr/0249-link-golem-with-a-64-mb-allocation-area.md) は実行ファイルの設定だけを変えるので、[ADR 0249](../adr/0249-link-golem-with-a-64-mb-allocation-area.md) を取り込んだ `main` と同じ `golem` である。
- 変更後：このプルリクエストのコミット `a85d3690` に、同じく `-with-rtsopts=-N -A64m` を足してビルドしたもの。
- どちらも、`+RTS -s` を使うためだけに、作業ツリーの `cabal.project.local` に `package golem-cli` の `ghc-options: -rtsopts` を足した。製品のビルド設定には `-rtsopts` を入れていない。
- GHC 9.10.3、cabal 3.18.1.0、最適化は cabal の既定（`-O1`）。
- 入力：調査と同じ `manual/`、`manual-dev/`、`modules/golem-driver/test/fixtures/` の `kanikosen` と `pd/nightmare-abbey`。フォントも調査と同じものを置いた。

## 方法

一回ごとに `build/` を消し、`golem build --target pdf +RTS -s<ファイル> -RTS` を実行した。
入力ごとに変更前と変更後を交互に一回ずつ走らせ、これを 5 周した。
40 回の計測の開始のときの load average（1 分）は 4.6 から 8.1、中央値は 6.3 だった。
同じ計算機で別のエージェントのビルドが動いていたので、比は同じ周の二回の比を 5 周で中央値にしたもの（下の表の「短縮」）で読む。

出力は、`build/` の下のすべてのファイルの SHA-256 と標準出力と標準エラー出力をまとめたハッシュで比べた。
四つの入力のすべての 10 回で、ハッシュは一つだった（変更前と変更後で一致する）。

## 表 1：変更前と変更後

壁時計と CPU 時間と割り当てと GC 0 は 5 回の中央値、最大常駐は 5 回の最大である。
GC 0 は世代 0 の GC の回数である。

| 入力 | 壁時計 前（秒） | 壁時計 後（秒） | 壁時計の短縮 | CPU 前（秒） | CPU 後（秒） | CPU の短縮 | 割り当て 前 | 割り当て 後 | GC 0 前 | GC 0 後 | 最大常駐 前（MB） | 最大常駐 後（MB） | 出力が同じ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| manual | 7.19 | 5.78 | 17% | 19.77 | 14.38 | 27% | 50.0GB | 23.2GB | 73 | 32 | 788 | 664 | はい |
| manual-dev | 6.29 | 5.20 | 19% | 16.86 | 12.46 | 26% | 41.7GB | 19.9GB | 57 | 24 | 603 | 500 | はい |
| kanikosen | 1.61 | 1.39 | 11% | 3.85 | 2.88 | 24% | 9.4GB | 4.7GB | 11 | 5 | 139 | 145 | はい |
| nightmare-abbey | 1.83 | 1.53 | 17% | 4.03 | 3.05 | 24% | 9.8GB | 5.2GB | 12 | 4 | 168 | 156 | はい |

各回の壁時計（秒、周の順）。

| 入力 | 変更前 | 変更後 |
| --- | --- | --- |
| manual | 9.32、7.33、7.11、7.19、6.62 | 7.95、6.05、5.77、5.78、5.57 |
| manual-dev | 6.28、6.54、6.29、6.31、6.02 | 5.22、5.20、5.10、5.13、5.46 |
| kanikosen | 1.65、1.57、1.56、1.61、1.63 | 1.36、1.43、1.39、1.33、1.57 |
| nightmare-abbey | 1.85、1.82、1.83、1.76、1.95 | 1.55、1.53、1.53、1.44、1.48 |

読み取れること。

- CPU 時間は 24% から 27% 縮み、壁時計は 11% から 19% 縮んだ。[ADR 0250](../adr/0250-character-class-tables-instead-of-list-membership.md) は動いている時間の 8% から 17% を見積もっていたが、それより大きい。
- 割り当てが半分になった。マニュアルで 50.0GB から 23.2GB、ほかの三つも同じ割合である。[ADR 0250](../adr/0250-character-class-tables-instead-of-list-membership.md) は「復号はほとんど割り当てない」と見ていたが、そうではなかった。融合の後も、`elem` はリテラルを復号した `Char` の箱か、復号の途中の値を割り当てていたと見る。その結果、世代 0 の GC の回数も半分ほどになった。
- 出力のバイト列と diagnostics は変わらなかった（[ADR 0250](../adr/0250-character-class-tables-instead-of-list-membership.md) の I4）。

## 表 2：関数ごとの時間の見積もり

調査の表 4 と同じく、macOS の `sample` で `golem build --target pdf`（マニュアル）のすべてのスレッドのスタックを 1 ミリ秒ごとに集めた。
`sample` は `-wait` で `golem` の起動を待ってから集めた。
呼び出しの木の各フレームの自分の分（そのフレームの数から子のフレームの数を引いたもの）を、アドレスの直前にあるローカルでないシンボル（`nm -n`）に割り当てて数えた。
待ちのスレッド（`kevent`、`__psynch_cvwait` など）を除いた「動いている」サンプルに対する割合である。
各 1 回の計測である。

| 関数 | 変更前 | 変更後 |
| --- | --- | --- |
| 動いているサンプルの数 | 16,980 | 12,070 |
| `GHC.CString.unpackNBytes#` | 7.9% | 0.0% |
| `Golem.Layout.CharClass.isDualCharacter` | 4.7% | 0.0% |
| `Golem.Layout.CharClass.charClass` | 0.7% | 0.0% |
| `Data.IntSet.Internal.member`（変更後の表の参照） | 0.0% | 1.5% |
| `Golem.Typeset.Memo.trieAt` | 6.6% | 5.9% |
| `evacuate`（GC） | 14.1% | 19.2% |

`unpackNBytes#` と `isDualCharacter` と `charClass` の三つは、合わせて 13.3% から 0% になり、上位から消えた。
代わりに表の参照（`IntSet.member`）が 1.5% 現れた。
動いているサンプルの数は 29% 減った。
GC の割合が増えたのは、ほかの関数の時間が減ったためで、GC の回数は表 1 のとおり減っている。

## 使ったコマンド

```sh
# 変更前と変更後のビルド（cabal.project.local に package golem-cli / ghc-options: -rtsopts）
cabal build exe:golem --disable-tests
# 一回の計測（入力ごとに、変更前と変更後を交互に 5 周）
cd manual && rm -rf build && golem build --target pdf +RTS -s/path/rts.txt -RTS
# 表 2：起動を待って 1 ミリ秒ごとにサンプルを集め、シンボル表で関数に割り当てる
sample golem 30 1 -wait -mayDie -file sample.txt &
golem build --target pdf
nm -n golem > golem.nm
```

## 限界

- 負荷を制御できず、交互の計測で負荷の影響を減らしたが、なくしてはいない。
- 表 2 は各 1 回で、サンプルの葉のフレームの集計である。関数の包含時間ではない。
- 計測と集計のスクリプトは、この記録とともに置いていない。
