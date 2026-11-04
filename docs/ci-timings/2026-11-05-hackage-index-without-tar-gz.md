# CI の Hackage の索引のキャッシュ（2026-11-05、01-index.tar.gz を消してから保存した前後）

[ADR 0152](../adr/0152-remove-hackage-index-tar-gz-before-cache.md) の実装の、Hackage の索引のキャッシュの大きさと復元の時間の記録である。
大きさはジョブのログの `Cache Size` と `ls -l`、`du -sh` の行と、`gh api repos/tett23/golem/actions/caches` から、時間は `gh run view <id> --json jobs` の手順の秒数から取った。
2026-11-05 に作り、コミットした後は変更しない。

## 実行

| 組 | 実行 |
|---|---|
| 前 | [2026-11-04 の記録](2026-11-04-smaller-ghc-and-index-caches.md)の、[ADR 0141](../adr/0141-smaller-ghc-and-hackage-index-caches.md) の後の実行 |
| 後、キャッシュが外れた一回目 | [41856732951](https://github.com/tett23/golem/actions/runs/41856732951)（[#532](https://github.com/tett23/golem/pull/532)） |
| 後、二回目 | [41858115872](https://github.com/tett23/golem/actions/runs/41858115872)（#532） |

## 一回目：ランナーの上の索引

キャッシュが外れ、六つのランナーのすべてで `cabal update` が走った。
`ls -l` が書いた `01-index.tar.gz` は、x86-64 でも aarch64 でも 140298351 バイト（約 134 MiB）だった。
消した後の `du -sh` は 1015M だった。
`01-index.tar.gz` を消した後の `cabal build` と `cabal test` は、x86-64 と aarch64 の両方で通った。
cabal-install 3.16.1.0 は、`01-index.tar.gz` がなくても計画を立てられる。

## 大きさ

| キャッシュのキー | 大きさ |
|---|---|
| `hackage-index-…`（[ADR 0141](../adr/0141-smaller-ghc-and-hackage-index-caches.md) の前） | 259 MB |
| `hackage-index-tar-…`（[ADR 0141](../adr/0141-smaller-ghc-and-hackage-index-caches.md) の後） | 242 MB |
| `hackage-index-no-gz-…`（この ADR の後、`refs/pull/532/merge`） | 113937076 バイト（約 109 MB） |

## 二回目：復元

| ランナー | Cache the Hackage index（秒） |
|---|---|
| x86-64 の `tests-driver`、`outputs`、`tests-rest`、`env` | 5、4、4、3 |
| aarch64 の `tests`、`outputs` | 4、3 |

[ADR 0141](../adr/0141-smaller-ghc-and-hackage-index-caches.md) の後は、x86-64 で 3〜5 秒、aarch64 で 3〜4 秒だった。
二回目のどのランナーでも `cabal update` の手順は飛ばされ、`cabal build` はビルドするものを並べず、`cabal update` を求める行もなかった。

## 読み方

キャッシュは 242 MB から約 109 MB になった。
復元の時間は、手順の秒数の揺れの中で変わらなかった。

2026-11-04 の記録は、キャッシュが 17 MB しか縮まなかったことから、ランナーの上の `01-index.tar.gz` が手元より「ずっと小さいと見られる」と書いた。
この推測は誤りだった。
ランナーの上の `01-index.tar.gz` は手元と同じく約 134 MiB で、キャッシュが縮まなかった原因は、actions/cache の `path` の `!` の行が何も除いていなかったことである（[ADR 0152](../adr/0152-remove-hackage-index-tar-gz-before-cache.md) の文脈）。
