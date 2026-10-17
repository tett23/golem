# Alpine のパッケージのライセンスの文書

Linux の `golem` に静的にリンクした Alpine のパッケージ（musl、libffi、libgcc、libstdc++ など）のライセンスの文書は、`scripts/release/licenses.sh` が次の順に探して `THIRD_PARTY_LICENSES/<origin>/` に写す（[ADR 0007](../../docs/adr/0007-third-party-licenses.md)）。

1. `scripts/release/build-linux.sh` が `apk add <origin>-doc` で入れた `/usr/share/licenses/<origin>/` と `/usr/share/licenses/<パッケージ名>/` のファイル。
2. どちらにもファイルがなければ、このディレクトリの `<origin>/` のファイル。
3. それでもなければ、エラーとする。

このディレクトリには、Alpine のパッケージがライセンスの文書を入れない origin の分だけを置く。
`<origin>/` には、上流のソースから取った文書と、取った上流のバージョンを書いた `VERSION` を置く。
`VERSION` は、リンクしたパッケージのバージョン（`/lib/apk/db/installed` の `V:` から `-r<数>` を除いたもの）と一致しなければならない。
バージョンによって文面の変わらない文書（GCC の `COPYING3` と `COPYING.RUNTIME`）だけは、`VERSION` に `any` と書いてバージョンの照合を省く。
`VERSION` は配布物には写さない。

## 置いたもの

最初のプレリリースの確かめ（[ADR 0008](../../docs/adr/0008-first-release-verification.md)）の `build` ジョブで、`licenses.sh` は `gcc` と `musl` の文書がないと言って止まった。
Alpine 3.24 には `musl-doc` がなく、`gcc-doc` は `/usr/share/licenses/` にファイルを入れないためである。
この二つの分を、次のとおり置いた。

- **musl/**：`COPYRIGHT`。musl の `v1.2.6` のタグのもの（`https://git.musl-libc.org/cgit/musl/plain/COPYRIGHT?h=v1.2.6`、SHA-256 `b870108ec5e7790e9f9919064f1b9421d62d5f9b0e6c230c6adf7ea2da62e97b`）。リンクした `musl-dev` は 1.2.6-r2 なので、`VERSION` は `1.2.6` とした。
- **gcc/**：`COPYING3` と `COPYING.RUNTIME`。GCC の `releases/gcc-15.2.0` のタグのもの（GitHub の gcc-mirror/gcc から取得、SHA-256 はそれぞれ `8ceb4b9ee5adedde47b31e975c1d90c73ad27b6b165a1dcd80c7c545eb65b903` と `9d6b43ce4d8de0c878bf16b54d8e7a10d9bd42b75178153e3af6a815bdc90f74`）。バージョンによって文面が変わらないので、`VERSION` は `any` とした。

`libffi` は `libffi-doc` が `/usr/share/licenses/libffi/` に文書を入れるので、ここには置いていない。
