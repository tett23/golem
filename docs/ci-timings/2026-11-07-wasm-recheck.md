# wasm のビルドの所要時間（2026-11-07、[ADR 0202](../adr/0202-packages-that-do-not-build-for-wasm.md) の 3 の確かめ直し）

[ADR 0202](../adr/0202-packages-that-do-not-build-for-wasm.md) の「3. 組めるかをもう一度確かめる」で、[ADR 0199](../adr/0199-pdf-typesetting-as-wasm-reactor.md) の 1 をもう一度行ったときの所要時間の記録である。
[ADR 0199](../adr/0199-pdf-typesetting-as-wasm-reactor.md) の 1 は、ビルドにかかった時間を `docs/ci-timings/` に記録するとした。
2026-11-07 に作り、コミットした後は変更しない。

## 条件

作業用のブランチ `wasm-recheck-0202` の一時的なワークフローで、GitHub Actions の `ubuntu-24.04`（x86-64）のランナーで走らせた。
ブランチはマージせず、確かめた後に消した。
表の一つめの実行のコミットは `215f7c5e`、二つめは `f5b31e69` である。
あいだの実行（`fcbcf3b0`）は、ワークフローの誤りで取り消した。

- ツールチェーン：ghc-wasm-meta（`8079eb96bbc63823d99ad8acaff0765532625474`）の 9.10 の flavour の x86-64 の Linux の配布物。GHC は `9.10.3.20260731`、cabal は 3.14.2.0、wasi-sdk の clang は 21.1.8。各アーカイブの SHA-256 と、`autogen.json` の SRI の値を確かめた。
- ネイティブ：`haskell-actions/setup` の GHC 9.10.3 と cabal 3.16.1.0 で、`alex` 3.5.4.2 と `happy` 2.2 を組み、`PATH` に置いた。
- キャッシュ：ワークフローは `actions/cache` を使っていない。ツールチェーンと、wasm の側の Hackage の索引とストアは、毎回取り直した。
- 組んだもの：golem-plugin を外した golem-driver の依存のすべてと、確かめのための実行ファイル。一つめの実行は golem-driver に依存する `feas-driver` だけを、二つめの実行はそれに加えて golem-font、golem-html、golem-layout、golem-pdf に依存する `feas-font` を組んだ。cabal の `--keep-going` で組んだ。

## 結果

golem-driver のライブラリが Template Haskell で止まったので、`feas-driver` は組めていない。
そのため、下の「wasm のビルド」は、golem-driver の手前までの時間であり、golem-driver の全体を組む時間ではない。

| 実行 | ネイティブの GHC の用意 | `alex` と `happy` | ツールチェーンの取得と展開 | `wasm32-wasi-cabal update` | wasm のビルド | ジョブ全体 |
|---|---|---|---|---|---|---|
| [42383283239](https://github.com/tett23/golem/actions/runs/42383283239) | 128 | 19 | 120 | 16 | 622 | 939 |
| [42384840870](https://github.com/tett23/golem/actions/runs/42384840870) | 133 | 19 | 115 | 16 | 647 | 967 |

数字は秒である。
ジョブ全体は、ジョブの始まりから終わりまでである。
ほかの列は、`gh run view <id> --json jobs` の各ステップの始まりと終わり、またはジョブの中で `date +%s` で測った値である。

`feas-font` の wasm は 18,459,166 バイトである（cabal の設定で `executable-stripping: False`）。
