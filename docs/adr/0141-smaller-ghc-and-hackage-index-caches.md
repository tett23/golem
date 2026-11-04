# ADR 0141: GHC と Hackage の索引のキャッシュから、CI が読まないファイルを除く

ステータス: 採択（未実装）

## 文脈

`build` の行列の各ランナーは、仕事の前に五つのキャッシュを戻す（[ADR 0009](0009-ci-speed.md)、[ADR 0045](0045-split-x86-build-and-pull-request-cache.md)）。
2026-11-04 の `main` への push の実行 [41786252402](https://github.com/tett23/golem/actions/runs/41786252402) の大きさと時間は、次のとおりである。

| キャッシュ | x86-64 の大きさ | x86-64 の手順の秒 | aarch64 の大きさ | aarch64 の手順の秒 |
|---|---|---|---|---|
| GHC | 345 MB | 8 | 353 MB | 9 |
| Hackage の索引 | 259 MB | 4 | 259 MB | 5 |
| cabal の store | 98 MB | 3 | 135 MB | 6 |
| `dist-newstyle` | 257 MB | 4 | 403 MB | 10 |

x86-64 の GHC の手順の 8 秒のうち、取り寄せは約 2 秒で、残りの約 5 秒は展開である。
どのランナーもこの時間を払うので、縮めればそのまま実行全体が縮む（[ADR 0140](0140-ci-split-test-runners-and-visual-pdfs-first.md) の計測では、`build` の各ランナーがほぼ同じ時刻に終わる）。

### Hackage の索引

`cabal update` は、`~/.cabal/packages/hackage.haskell.org` に、圧縮した索引 `01-index.tar.gz` と、それを展開した `01-index.tar` の両方を置く。
手元の索引（index-state 2026-10-11）では、`01-index.tar.gz` が 139 MB、`01-index.tar` が 1.0 GB だった。
`01-index.tar.gz` はすでに圧縮されているので、キャッシュの zstd でも縮まず、キャッシュの 259 MB の半分ほどを占めると見られる。

ビルドの計画を立てるとき、cabal は `01-index.tar` と、その索引（`01-index.tar.idx`、`01-index.cache`）を読む。
手元（cabal-install 3.18.1.0）で、`01-index.tar.gz` を除いた索引だけを置いた `CABAL_DIR` で、このリポジトリの `cabal build --dry-run all` が終了コード 0 で計画を出すことを確かめた。
CI の cabal-install 3.16.1.0 では確かめていない。

### GHC

GHC のキャッシュは、ghcup が入れた GHC のディレクトリ全体である。
手元の macOS の GHC 9.10.3 は 2.1 GB で、そのうち `share/doc` が 774 MB、プロファイリング用のライブラリ（`*_p.a` と `*.p_hi`）が約 600 MB だった。
CI はプロファイリングでビルドせず、Haddock も動かさない。
Linux の配布物の内訳は確かめていない。

### キーを変える必要

GitHub Actions のキャッシュは、キーが一致すると保存しない。
中身を減らしても、今のキーのままでは、今の大きなキャッシュが使われ続ける。
キーは [ADR 0009](0009-ci-speed.md) が決めているので、この ADR で変える。

## 実装すること

- Hackage の索引のキャッシュの `path` に、`!~/.cabal/packages/hackage.haskell.org/01-index.tar.gz` を足す。キーを `hackage-index-tar-${{ hashFiles('cabal.project.freeze') }}` にする。
- GHC のキャッシュのキーを `ghc-${{ env.GHC_VERSION }}-${{ runner.os }}-${{ runner.arch }}-${{ env.ImageOS }}-slim` にする。
- GHC のキャッシュが外れたときだけ、`haskell-actions/setup` の後に、GHC のディレクトリから `share/doc`、`*_p.a`、`*.p_hi` を消す手順を置く。キャッシュは、ジョブの終わりに消した後の中身で保存される。
- 二つのキャッシュの、キーの形と消すファイルの検査を `scripts/ci/test.sh` に足す。
- 計測の結果を `docs/ci-timings/` に記録する。

## 実装しないこと

- **`dist-newstyle` を小さくすること。** 中身はインクリメンタルなビルドに要る `.o` と `.hi` が大半で、除けるものを確かめていない。
- **索引の下の、依存のパッケージの tarball を除くこと。** store のキャッシュが一部だけ当たったとき、cabal はそれを使ってビルドする。除くと、Hackage からの取得がそのつど要り、ネットワークの失敗が CI の失敗になりうる。
- **キャッシュの復元を一つの手順にまとめること。** キーの変わる条件が、GHC はイメージ、索引は freeze ファイル、store はプロジェクトと、それぞれ違う。

## テスト設計

### 先に書いて失敗させるテスト（`scripts/ci/test.sh`）

- Hackage の索引のキャッシュの `path` が `01-index.tar.gz` を除き、キーが `hackage-index-tar-` で始まること。
- GHC のキャッシュのキーが `-slim` で終わること。
- GHC のファイルを消す手順が、GHC のキャッシュの `cache-hit` が真でないときだけ動き、`haskell-actions/setup` の後、`cabal build` の前にあること。

### 自動テストにできないものの確かめ方

下書きのプルリクエストで、次を確かめて記録する。

- キャッシュが外れた一回目の実行で、`cabal build` と `cabal test` が通り、`Save dist-newstyle` が動くこと。
- 二回目の実行で、二つのキャッシュの大きさと手順の秒数が、上の表より小さいこと。x86-64 と aarch64 の両方で取る。
- 二回目の実行の `cabal build` が、今と同じく `Up to date` か、変えたモジュールだけをコンパイルすること。

## トレードオフ

- 見込める短縮は、各ランナーで数秒（GHC で 2 秒から 4 秒、索引で 1 秒から 2 秒）と小さい。上の大きさの比から見積もった値で、確かめていない。
- キーを変えた最初の実行では、すべてのランナーで GHC の導入（約 2 分）と `cabal update` が走る。
- GHC からプロファイリング用のライブラリを消すと、CI の中で `-prof` のビルドはできない。今の CI にはその手順がない。

## 決めたことの記録

- **[docs/adr/0009](0009-ci-speed.md) のキーを変えること**：数秒の短縮のためにキャッシュのキーを変えることを、メンテナーが認めた（2026-11-04）。

## 参考文献

- [ci.yml（今の GHC と索引のキャッシュ）](https://github.com/tett23/golem/blob/2511d517ac2b2d09b352f6d3ca0a429275ab31d1/.github/workflows/ci.yml#L183-L210)
- actions/cache, "Usage"（`path` の `!` による除外）. https://github.com/actions/cache#inputs
- cabal-install のユーザーガイド, "cabal update". https://cabal.readthedocs.io/en/stable/cabal-commands.html#cabal-update
- [ADR 0009](0009-ci-speed.md)、[ADR 0045](0045-split-x86-build-and-pull-request-cache.md)、[ADR 0140](0140-ci-split-test-runners-and-visual-pdfs-first.md)
