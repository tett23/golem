# CI のキャッシュの大きさと復元の時間（2026-11-04、GHC と Hackage の索引のキャッシュを小さくした前後）

[ADR 0141](../adr/0141-smaller-ghc-and-hackage-index-caches.md) の実装の前後の、`ci.yml` の `build` のキャッシュの記録である。
時間は `gh run view <id> --json jobs` の手順の秒数で、大きさはジョブのログの `Cache Size` の行から取った。
2026-11-04 に作り、コミットした後は変更しない。

## 実行

| 組 | 実行 |
|---|---|
| 前 | 2026-11-04 の `main` への push とプルリクエストの 22 回（[41773489912](https://github.com/tett23/golem/actions/runs/41773489912) から [41815303999](https://github.com/tett23/golem/actions/runs/41815303999) まで）の、`build` のすべてのランナー |
| 後、キャッシュが外れた一回目 | [41816372306](https://github.com/tett23/golem/actions/runs/41816372306)（[#512](https://github.com/tett23/golem/pull/512)） |
| 後、二回目 | [41817232702](https://github.com/tett23/golem/actions/runs/41817232702)（#512） |

## 大きさ

| キャッシュ | 前、x86-64 | 後、x86-64 | 前、aarch64 | 後、aarch64 |
|---|---|---|---|---|
| GHC | 345 MB | 146 MB | 353 MB | 150 MB |
| Hackage の索引 | 259 MB | 242 MB | 259 MB | 242 MB |

一回目の実行で、消した後の GHC のディレクトリは、x86-64 で 1.1 GB、aarch64 で 1008 MB だった（`du -sh`）。

## 手順の時間

単位は秒である。
前は各ランナーの手順の最小、中央値、最大で、後は二回目の六つのランナーの値である。

| 手順 | 前、x86-64 | 後、x86-64 | 前、aarch64 | 後、aarch64 |
|---|---|---|---|---|
| Cache GHC | 6、9、13 | 4、3、4、4 | 7、9、11 | 2、3 |
| Cache the Hackage index | 3、5、8 | 3、4、5、4 | 2、3.5、6 | 3、4 |

## 読み方

GHC のキャッシュは、どちらのアーキテクチャでも半分より小さくなり、復元は 5 秒前後短くなった。
Hackage の索引のキャッシュは 17 MB しか小さくならず、復元の時間は変わらなかった。
手元の索引では `01-index.tar.gz` が 139 MB あったが、CI のキャッシュの縮み方から見ると、ランナーの上の `cabal update`（cabal-install 3.16.1.0）が残す `01-index.tar.gz` はずっと小さいと見られる。
ランナーの上のファイルの大きさは確かめていない。

一回目の実行では、六つのランナーのすべてで GHC の導入（96 秒から 115 秒）と `cabal update`（15 秒から 18 秒）が走り、ファイルを消す手順は 1 秒以内に終わった。
二回目の `cabal build` のログに `configuration changed` はなく、組み直したのは、`main` で変わった文書を読む golem-driver と、それに依存する部品だけだった。
