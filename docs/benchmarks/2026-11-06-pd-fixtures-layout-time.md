# パブリックドメインの十冊の PDF の組版の時間（[docs/adr/0181](../adr/0181-footnote-heavy-layout-time.md)）

[docs/adr/0181](../adr/0181-footnote-heavy-layout-time.md) の「テスト設計」が求める計測の記録である。
ADR を書いたときと同じ方法で、今の `main` の PDF の組版の時間を測り直した。
ファイルの名前は ADR が決めたもので、測ったのは 2026-11-07 である。
コミットした後は変更しない。

## 対象

- fixture：`modules/golem-driver/test/fixtures/pd/` の十冊。
- 脚注なしの『Nightmare Abbey』：`nightmare-abbey.gm` から 14 件の `[note: ...]` を、入れ子の括弧と `\` のエスケープを含めて取り除いたもの（原稿 159265 バイトが 155513 バイトになった）。ほかのファイルは同じである。

## 環境

- 計算機：Apple M1 Max（10 コア）、メモリ 64GB、macOS 27.0（26A428）。
- golem：`main` のコミット `508c639b` から、実装のブランチ（impl-0181）の作業ツリーで `cabal build exe:golem --disable-tests` で作ったもの（GHC 9.10.3、最適化は cabal の既定、ほかのフラグもリポジトリのまま）。作業ツリーは新しく作ったもので、前のビルドの `dist-newstyle` はない。wasmtime は `scripts/fetch-wasmtime.sh` が取得した 49.0.5。
- 入力：十冊を作業用のディレクトリに写し、`scripts/fixtures/copy-fonts.sh` と同じフォントを置いた。
- 方法：一冊ごとに `build/` を消してから `golem build --target pdf +RTS -s -RTS` を 5 回実行し、`/usr/bin/time -p` の壁時計の時間（real）の中央値を取った。割り当ての量は 5 回めの `+RTS -s` の「bytes allocated in the heap」である。並列化は既定のまま（`-N10`）。
- 負荷：ADR の計測と違い、同じ計算機でほかの作業ツリーの GHC と clang のビルドが動いていた。計測のあいだの load average（1 分）は 7 から 23 である。測る前に load average が 3 を下回るのを 10 分ほど待ったが、下回らなかった。

## 結果

| 本 | 原稿 | 5 回（秒） | 中央値 | 割り当て |
| --- | --- | --- | --- | --- |
| elements-of-style | 88KB | 3.46、1.14、1.17、1.15、1.22 | 1.17 秒 | 4.7GB |
| frogs | 96KB | 1.22、1.19、1.21、1.21、1.16 | 1.21 秒 | 4.4GB |
| haru-to-shura | 158KB | 1.51、1.55、1.55、1.57、1.62 | 1.55 秒 | 6.7GB |
| ichiaku-no-suna | 82KB | 0.84、0.82、0.80、0.84、0.94 | 0.84 秒 | 2.8GB |
| koya-hijiri | 163KB | 1.38、1.37、1.31、1.35、1.39 | 1.37 秒 | 5.4GB |
| merry-wives | 165KB | 2.08、2.64、7.04、4.29、3.25 | 3.25 秒 | 7.8GB |
| nightmare-abbey | 159KB | 2.27、2.25、2.36、2.19、2.33 | 2.27 秒 | 9.0GB |
| snark | 36KB | 0.48、0.47、0.46、0.44、0.45 | 0.46 秒 | 1.5GB |
| taira-no-masakado | 146KB | 1.65、1.73、1.77、1.76、1.66 | 1.73 秒 | 8.3GB |
| ushiyama-hotel | 114KB | 0.91、0.89、0.89、0.90、0.96 | 0.90 秒 | 4.4GB |
| nightmare-abbey（脚注なし） | 156KB | 2.05、2.02、2.02、2.04、2.07 | 2.04 秒 | 8.7GB |

`merry-wives` の 5 回は、ほかのビルドの負荷で大きく揺れた。
割り当ての量は 5 回のあいだでほとんど変わらない（どの本も 0.01% 未満の差）ので、揺れたのは計算機の混み具合である。
十冊を測った直後に、`merry-wives` と `nightmare-abbey` を同じ方法でもう一度測った。

| 本 | 5 回（秒） | 中央値 |
| --- | --- | --- |
| merry-wives | 2.08、2.09、2.07、2.49、2.32 | 2.09 秒 |
| nightmare-abbey | 3.00、2.32、2.37、2.37、2.50 | 2.37 秒 |

## 読み取れること

『Nightmare Abbey』の中央値は 2.27 秒と 2.37 秒で、ADR に書いた `50b9fca8` の 2.07 秒に近い。
原稿の大きさが近いほかの本の中央値は、`merry-wives` が 2.09 秒（二回めの計測）、`haru-to-shura` が 1.55 秒、`koya-hijiri` が 1.37 秒である。
『Nightmare Abbey』は、もっとも短い `koya-hijiri` の二倍（2.74 秒）も超えない。
ADR の「テスト設計」が項目を閉じない条件とした「ほかの本の二倍を超える」には当たらないので、ロードマップの項目を閉じる。

脚注を取り除いた『Nightmare Abbey』は 2.04 秒で、脚注のある原稿との差は 0.2 秒ほどである。
割り当ての量も 9.0GB と 8.7GB で、脚注の分は全体の 3% にとどまる。
今の `main` でも、脚注は組版の時間の大きな部分を占めていない。
