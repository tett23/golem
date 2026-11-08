# ADR 0240: golem.wasm のライセンスの文書で、コードを持たない system-cxx-std-lib を写さない

ステータス: 採択（未実装）

## 文脈

### 止まったリリースのワークフロー

2026-11-08 に `workflow_dispatch` で起動した `release.yml`（[run 42481025090](https://github.com/tett23/golem/actions/runs/42481025090)、ブランチ `impl-0230`）で、ジョブ `wasm` が `golem-<tag>-wasm32-wasi.tar.gz` を作るステップで止まった。
`scripts/release/package-wasm.sh` が呼ぶ `scripts/release/licenses.sh --wasm` が、次を出して 1 で終わった。

```
licenses: no license file for: system-cxx-std-lib-1.0
```

この後のアーカイブの検査（`check-wasm-archive.sh`、[ADR 0230](0230-check-the-release-workflow-and-ci-history-by-scripts.md)）は走っていない。
`release` はタグの push でしか走らないので、このまま v0.1.0-rc4 のタグを打てば、`wasm` が失敗して下書きのリリースは作られない。

### system-cxx-std-lib

system-cxx-std-lib は、GHC 9.4 から GHC のパッケージのデータベースに入っている仮想のパッケージである。
C++ の標準ライブラリにリンクするための設定だけを持ち、Haskell のコードを持たない。
GHC 9.10.3 のネイティブの GHC（ghcup の aarch64 の macOS の配布物）では、`package.conf.d/system-cxx-std-lib-1.0.conf` は `exposed-modules` が空で、`extra-libraries` に `c++ c++abi` を持つ。
`license` は `BSD-3-Clause` と書かれている。

`licenses.sh` は、GHC に付いてくるパッケージ（plan の `pre-existing`）のライセンスを、`GHC_DOCDIR/<名前>-<版>/` から写す（[licenses.sh の 173〜187 行](https://github.com/tett23/golem/blob/5408768304be08010aa30e1a8f88f3d8a0e8c549/scripts/release/licenses.sh#L173-L187)）。
GHC の `share/doc` には、system-cxx-std-lib のディレクトリがない。
ネイティブの GHC 9.10.3 の `share/doc/aarch64-osx-ghc-9.10.3/` にもないことを、2026-11-09 に手元で確かめた。
wasm の GHC の `GHC_DOCDIR`（`wasm32-wasi-ghc-<版>-inplace`）にもないので、写すものが見つからずに止まった。

同じく GHC に付いてきてコードの置き場所が GHC である `rts` は、すでに名前で分けてある。
`rts` は写さず、GHC の `LICENSE`（`GHC_DOCDIR/ghc-<版>/LICENSE`）があることだけを確かめる（[licenses.sh の 173〜177 行](https://github.com/tett23/golem/blob/5408768304be08010aa30e1a8f88f3d8a0e8c549/scripts/release/licenses.sh#L173-L177)）。

### golem.wasm にリンクされる C++ の標準ライブラリ

`golem.wasm` にリンクされる C++ の標準ライブラリは、wasm のツールチェーンの wasi-sdk の libc++ と libc++abi である。
その文書は、`licenses.sh --wasm` が `licenses/wasi-sdk/llvm/` から `THIRD_PARTY_LICENSES/wasi-sdk/llvm/` にすでに写している（`libcxx-LICENSE.TXT` と `libcxxabi-LICENSE.TXT`、[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md)）。
`check-wasm-archive.sh` も、この二つがアーカイブにあることを確かめる。
system-cxx-std-lib の conf が書く `BSD-3-Clause` は GHC のライセンスで、その文書は `THIRD_PARTY_LICENSES/ghc/LICENSE` に入っている。
つまり、system-cxx-std-lib のディレクトリを `haskell/` の下に作らなくても、それが指すもののライセンスはすべてアーカイブにある。

### ネイティブの配布物

ネイティブの配布物（`licenses.sh` を `--wasm` なしで呼ぶ道）には、今は同じ問題がない。
同じ run の `build` の三つのジョブ（x86-64 と aarch64 の Linux、aarch64 の macOS）は、`package.sh` の中の `licenses.sh` を含めて成功した。
手元の aarch64 の macOS で GHC 9.10.3 のネイティブの `dist-newstyle/cache/plan.json` を調べると、system-cxx-std-lib は `install-plan` に一つもない。
GHC に付いてくる `text-2.1.3` の依存も、`array`、`base`、`binary`、`bytestring`、`deepseq`、`ghc-prim`、`template-haskell` だけである。

ただし、ネイティブの plan に system-cxx-std-lib が入れば、同じ行で止まる。
そのときにリンクされる C++ の標準ライブラリは、Linux では Alpine の gcc の libstdc++（リンクマップから `apk:gcc` として入る）、macOS ではシステムの libc++（動的にリンクし、配布物に入らない）であり、wasm と違う。
どの部品の文書がそれを覆うかは、道ごとに違う。

wasm の plan で、どのパッケージが system-cxx-std-lib に依存しているかは、この ADR の時点では確かめていない。

## 実装すること

### 1. `licenses.sh --wasm` で system-cxx-std-lib を写さない

`licenses.sh` の `pre-existing` のパッケージの扱いで、`rts` の分岐の隣に、名前が `system-cxx-std-lib` で `--wasm` のときの分岐を足す。

- `GHC_DOCDIR` からは何も写さない。`THIRD_PARTY_LICENSES/haskell/system-cxx-std-lib-<版>/` を作らない。
- その代わり、`licenses/wasi-sdk/llvm/libcxx-LICENSE.TXT` と `licenses/wasi-sdk/llvm/libcxxabi-LICENSE.TXT` があることを確かめる。どちらかがなければ、ほかの見つからないパッケージと同じく `MISSING` に `system-cxx-std-lib-<版>` を足し、`no license file for:` で 1 で終わる。
- 分岐の注釈に、コードを持たない仮想のパッケージで、ライセンスは wasi-sdk の libc++ と libc++abi のものであることと、この ADR へのリンクを書く。

`--wasm` なしの道は変えない。
ネイティブの plan に system-cxx-std-lib が入れば、今と同じく `no license file for: system-cxx-std-lib-<版>` で止まる。

### 2. 文書

- `licenses.sh` の冒頭の `--wasm` の説明に、system-cxx-std-lib を写さないことを一文足す。
- `docs/specifications.md` のリリースの手順の、wasm の版の `THIRD_PARTY_LICENSES/` の段落に、system-cxx-std-lib はコードを持たず、そのライセンスは同梱した libc++ と libc++abi のものなので、`haskell/` の下に置かないことを書く（この ADR へのリンク）。
- README の wasm の版の `THIRD_PARTY_LICENSES/` の文は、中身の一覧が変わらないので変えない。
- `docs/roadmap.md` に rc4 の項目として載っていれば消す。

### 3. リリースのワークフローで確かめる

実装をマージした後、`main` で `release.yml` を `workflow_dispatch` で起動し、ジョブ `wasm` の `golem-<tag>-wasm32-wasi.tar.gz` のステップ（`licenses.sh --wasm`）と、アーカイブの検査のステップが通ることを確かめる。
`workflow_dispatch` では `release` が走らない（`github.event_name == 'push' && github.ref_type == 'tag'` を条件に持つ）ので、リリースも下書きも作られない。

## 実装しないこと

- GHC の `LICENSE` を `haskell/system-cxx-std-lib-<版>/` に写すこと。メンテナーが退けた（決めたことの記録）。
- system-cxx-std-lib のライセンスのディレクトリをリポジトリ（`licenses/`）に置くこと。メンテナーが退けた。
- `--wasm` なしの道で system-cxx-std-lib を写さないこと。今のネイティブの plan には入っておらず、入ったときに覆う部品が Linux と macOS で違う。入ったときに、その部品を決める ADR を作る。
- コードを持たない `pre-existing` のパッケージを conf の `exposed-modules` などから見分けて、名前を並べずに飛ばすこと。名前で決めた集合の外は、今と同じくエラーにする。
- `check-wasm-archive.sh` の変更。libc++ と libc++abi の文書は、すでに検査している。
- wasm の plan で system-cxx-std-lib に依存するパッケージを調べて、依存を外すこと。

## 不変条件

述語は、`licenses.sh` の出力のディレクトリ `OUT` と終わりの状態についてのものである。
「コードを持たない集合」は、`--wasm` のとき {`rts`, `system-cxx-std-lib`}、`--wasm` なしのとき {`rts`} である。

| 番号 | 不変条件 |
| --- | --- |
| I1 | `licenses.sh` が 0 で終わったとき、plan の `exe:golem`（`--wasm` では `exe:golem-wasm`）の依存の閉包にある `pre-existing` のパッケージのそれぞれは、`OUT/haskell/<名前>-<版>/` に `GHC_DOCDIR/<名前>-<版>/` のライセンスのファイルを持つか、コードを持たない集合に入るかの、ちょうど一方である。 |
| I2 | コードを持たない集合のパッケージは、`OUT/haskell/<名前>-<版>/` を持たない。 |
| I3 | `licenses.sh` が 0 で終わったとき、閉包にあるコードを持たない集合のパッケージのそれぞれについて、それを覆う文書が `OUT` にある。`rts` は `OUT/ghc/LICENSE`、`system-cxx-std-lib` は `OUT/wasi-sdk/llvm/libcxx-LICENSE.TXT` と `OUT/wasi-sdk/llvm/libcxxabi-LICENSE.TXT` である。 |
| I4 | 閉包にある `pre-existing` のパッケージが、コードを持たない集合に入らず、`GHC_DOCDIR/<名前>-<版>/` にライセンスのファイルを持たなければ、`licenses.sh` は 1 で終わり、標準エラーの `no license file for:` の行にその `<名前>-<版>` を含む。 |
| I5 | 閉包に `system-cxx-std-lib` があり、`--wasm` で、`licenses/wasi-sdk/llvm/` に `libcxx-LICENSE.TXT` か `libcxxabi-LICENSE.TXT` がなければ、`licenses.sh` は 1 で終わり、標準エラーに `system-cxx-std-lib-<版>` を含む。 |

境界の入力は次のとおりである。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| `--wasm`、`pre-existing` は `base` と `rts` だけ（今のテストの plan） | 0 で終わる。`haskell/base-*/LICENSE` と `ghc/LICENSE` がある。`haskell/rts-*` はない | I1、I2、I3 |
| `--wasm`、`base` が `system-cxx-std-lib-1.0` に依存し、`GHC_DOCDIR` にそのディレクトリがない | 0 で終わる。`haskell/system-cxx-std-lib-1.0` はない。`wasi-sdk/llvm/` に二つの文書がある | I1、I2、I3 |
| 上と同じで、`licenses/wasi-sdk/llvm/libcxxabi-LICENSE.TXT` だけがない | 1 で終わり、`system-cxx-std-lib-1.0` を出す | I5 |
| 上と同じで、`licenses/wasi-sdk/llvm/libcxx-LICENSE.TXT` だけがない | 1 で終わり、`system-cxx-std-lib-1.0` を出す | I5 |
| `--wasm`、`system-cxx-std-lib` が plan にあるが、`exe:golem-wasm` の閉包の外にある | 0 で終わる。何も写さず、llvm の二つの文書も問わない（`wasi-sdk/llvm/` は今と同じく写す） | I1 |
| `--wasm`、`GHC_DOCDIR` にディレクトリのない別の `pre-existing` のパッケージ（`ghc-fake-1.0`）が閉包にある | 1 で終わり、`ghc-fake-1.0` を出す | I4 |
| `--wasm` なし、`base` が `system-cxx-std-lib-1.0` に依存し、`GHC_DOCDIR` にそのディレクトリがない | 1 で終わり、`system-cxx-std-lib-1.0` を出す | I4 |

## テスト設計

`scripts/release/test.sh` の `licenses.sh --wasm` の節に、次のテストを先に足す。
テストの名前（`ok` と `ng` の文）には、不変条件の番号を入れる。

- wasm の偽の plan に、`base` の依存として `system-cxx-std-lib-1.0`（`pre-existing`、`depends` は空）を足した plan を作る。`licenses/wasi-sdk/llvm/` の偽の文書に `libcxxabi-LICENSE.TXT` を足す。この plan で `licenses_wasm` が 0 で終わり（I1）、`haskell/system-cxx-std-lib-1.0` がなく（I2）、`wasi-sdk/llvm/libcxx-LICENSE.TXT` と `wasi-sdk/llvm/libcxxabi-LICENSE.TXT` がある（I3）こと。今の `licenses.sh` では 1 で終わり、失敗することを確かめてから実装する。
- 同じ plan で、`libcxxabi-LICENSE.TXT` を退けると 1 で終わり、標準エラーに `system-cxx-std-lib-1.0` があること（I5）。`libcxx-LICENSE.TXT` を退けたときも同じこと（I5）。
- `system-cxx-std-lib-1.0` を plan に置くが、閉包のどこからも依存しないとき、0 で終わること（I1）。
- 同じ wasm の plan に、`GHC_DOCDIR` にディレクトリのない `ghc-fake-1.0` を `base` の依存として足すと、1 で終わり、標準エラーに `ghc-fake-1.0` があること（I4）。
- ネイティブの節の偽の plan で、`base` の依存に `system-cxx-std-lib-1.0` を足すと、`licenses` が 1 で終わり、標準エラーに `system-cxx-std-lib-1.0` があること（I4）。このテストは今の `licenses.sh` でも通る。ネイティブの道を変えていないことを固定するためのものである。
- 今ある wasm の節のテスト（`rts-1.0.2` を写さないことなど）は変えずに通ること（I2）。

自動のテストのほかに、実装をマージした後の `main` で `release.yml` を `workflow_dispatch` で起動し、ジョブ `wasm` の `licenses.sh --wasm` のステップとアーカイブの検査のステップが通ることを確かめる（実装すること 3）。

## トレードオフ

- 名前の集合に `system-cxx-std-lib` を足すので、GHC が別の仮想のパッケージを足せば、また止まる。止まることは、ライセンスの文書の足りない配布物を作らないための今の設計のとおりであり、そのたびに名前と覆う部品を ADR で決める。
- system-cxx-std-lib の conf が書く `BSD-3-Clause` の文書を `haskell/` の下に置かない。配布物を読む人は、`haskell/` の一覧だけでは、このパッケージが閉包にあることに気づかない。中身のないパッケージであり、conf の `BSD-3-Clause` の文書は `ghc/LICENSE` に、リンクしたものの文書は `wasi-sdk/llvm/` にある。`rts` も同じ扱いで、`haskell/` の下にない。
- `--wasm` なしの道は、今は通る入力のままで、system-cxx-std-lib が入れば止まる。二つの道で扱いが違うが、覆う部品が違うので、確かめていない道まで決めない。
- 覆う文書の確かめは、`licenses/wasi-sdk/llvm/` の二つのファイルがあることだけで、wasm の GHC が実際に wasi-sdk の libc++ と libc++abi をリンクしたかは見ない。`licenses/wasi-sdk/VERSION` と `scripts/fetch-ghc-wasm.sh` の wasi-sdk の一致は、今のとおり確かめる（[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md)）。

## 決めたことの記録

- **system-cxx-std-lib の扱い**（2026-11-09、メンテナー）：`rts` と同じく扱う。Haskell のコードを持たず、そのライセンスはすでに同梱している libc++ と libc++abi のものなので、`licenses.sh` は写さない（案 a）。GHC の `LICENSE` を写す案と、ライセンスのディレクトリをリポジトリに置く案は退けた。

## 参考文献

- [GHC 9.4.1 のリリースノート](https://downloads.haskell.org/ghc/9.4.1/docs/users_guide/9.4.1-notes.html)（パッケージのデータベースに仮想の `system-cxx-std-lib` が入り、C++ の標準ライブラリにリンクする設定を持つこと）
- GHC 9.10.3 の `package.conf.d/system-cxx-std-lib-1.0.conf`（ghcup の aarch64 の macOS の配布物、2026-11-09 に手元で読んだ）
- [run 42481025090](https://github.com/tett23/golem/actions/runs/42481025090)（ジョブ `wasm` の失敗）
- [ADR 0007](0007-third-party-licenses.md)、[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md)、[ADR 0202](0202-packages-that-do-not-build-for-wasm.md)、[ADR 0230](0230-check-the-release-workflow-and-ci-history-by-scripts.md)
