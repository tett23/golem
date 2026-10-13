# Alpine のパッケージのライセンスの文書

Linux の `golem` に静的にリンクした Alpine のパッケージ（musl、libffi、libgcc、libstdc++ など）のライセンスの文書は、`scripts/release/licenses.sh` が次の順に探して `THIRD_PARTY_LICENSES/<origin>/` に写す（[ADR 0007](../../docs/adr/0007-third-party-licenses.md)）。

1. `scripts/release/build-linux.sh` が `apk add <origin>-doc` で入れた `/usr/share/licenses/<origin>/` と `/usr/share/licenses/<パッケージ名>/` のファイル。
2. どちらにもファイルがなければ、このディレクトリの `<origin>/` のファイル。
3. それでもなければ、エラーとする。

このディレクトリには、Alpine のパッケージがライセンスの文書を入れない origin の分だけを置く。
`<origin>/` には、上流のソースから取った文書と、取った上流の版を書いた `VERSION` を置く。
`VERSION` は、リンクしたパッケージの版（`/lib/apk/db/installed` の `V:` から `-r<数>` を除いたもの）と一致しなければならない。
版によって文面の変わらない文書（GCC の `COPYING3` と `COPYING.RUNTIME`）だけは、`VERSION` に `any` と書いて版の照合を省く。
`VERSION` は配布物には写さない。

## 置いたもの

まだ何も置いていない。
各 origin の `-doc` パッケージが `/usr/share/licenses/` に何を入れるかは、Alpine のコンテナで確かめていないためである。
最初のプレリリースの確かめ（[ADR 0008](../../docs/adr/0008-first-release-verification.md)）で、`build` ジョブのリンクマップと `licenses.sh` の結果から足りない origin を見つけ、その分をここに置き、置いた理由をこの節に書く。
