# ADR 0007: 配布物の THIRD_PARTY_LICENSES にリンクしたものをすべて入れる

ステータス: 採択

## 文脈

[ADR 0004](0004-binary-distribution-and-release.md) は、配布物の `THIRD_PARTY_LICENSES/` を `scripts/release/licenses.sh` で作ると決めた。
今の `licenses.sh` が入れるのは、`plan.json` から辿った Haskell のパッケージ、GHC と RTS、HarfBuzz、FreeType、wasmtime の `LICENSE`、hyph-utf8 の英語のパターン、GMP のライセンスの文書である。
入れるものの一覧はスクリプトに固定で書かれており、実行ファイルに実際にリンクされたものとは照合していない。

コードとビルドの結果から、次のものが一覧から漏れていることがわかっている。

- Linux の実行ファイルは、Alpine の上で `--enable-executable-static` でリンクする（`scripts/release/build-linux.sh`）。このとき、C のライブラリとして musl の `libc.a` が、GHC の RTS が使う `libffi.a` が、それぞれ実行ファイルに入る。gcc が静的なリンクで暗に加える `libgcc.a` と `libgcc_eh.a` も入りうる。golem-font の cabal ファイルは Linux で `extra-libraries: stdc++` を指定するので、`libstdc++.a` のオブジェクトも、参照されれば入る。`build-linux.sh` は `ncurses-static` と `zlib-static` も入れており、これらが入るかどうかはリンクの結果でしか決まらない。
- musl は MIT ライセンスで、バイナリの配布にも著作権の表示を求める。libffi も MIT である。libgcc と libstdc++ は GPL-3.0 に GCC Runtime Library Exception 3.1 を付けたもので、例外の条件を満たせば GPL-3.0 の義務を負わずに配布できるが、どの例外に依って配布しているかを利用者が確かめられるよう、文書を添える。
- `libwasmtime.a` は wasmtime の Rust のコードと、それが依存するクレートを一つにまとめた静的ライブラリである。`third_party/wasmtime/LICENSE` は wasmtime 自身のライセンス（Apache-2.0 WITH LLVM-exception）だけで、依存するクレートのライセンスは入っていない。

`libwasmtime.a` に何が入っているかは、元のチェックアウトの `third_party/wasmtime`（`wasmtime-v49.0.2-aarch64-macos-c-api`）で次のように確かめた。

- `scripts/fetch-wasmtime.sh` は、配布物から `include/`、`lib/libwasmtime.a`、`LICENSE` だけを `third_party/wasmtime` に写す。写したものの中に、依存するクレートのライセンスの一覧はない。配布物にそれ以外のファイル（README やライセンスの一覧）があるかは、写さないので手元では確かめられない。
- `ar t` で見ると、メンバーは 426 個ある。Rust のコードは LTO で一つにまとめた `wasmtime-<hash>.wasmtime.<hash>-cgu.0.rcgu.o` と、`compiler_builtins` のものだけである。ほかに、cc クレートがビルドした C とアセンブリのオブジェクト（ring の `aes_nohw.o`、`p256.o`、`sha256-armv8-ios64.o` など、zstd の `zstd_compress.o` など、LLVM の compiler-rt の `absvdi2.o` など、aarch64 の `lse_cas1_acq.o` など、wasmtime の `helpers.o` と `gdbjit.o`）がある。
- シンボルは Rust の v0 の形でマングルされており、クレートの根は `Cs<識別子>_<長さ><名前>` で現れる。ここから取り出したクレートの名前は 100 前後あり、`cranelift_codegen`、`rustls`、`ring`、`tokio`、`hyper`、`h2`、`serde_json`、`icu_normalizer`、`zstd` などを含む。Rust の標準ライブラリ（`std`、`core`、`alloc`、`hashbrown`、`addr2line`、`gimli` など）も入っている。
- 文字列には、パニックの位置としてクレートのソースのパス（`index.crates.io-<hash>/<名前>-<版>/...`）が残っており、`ring-0.17.14`、`rustls-0.23.37`、`tokio-1.51.1` のように版まで取れる。シンボルからだけ取れる名前（`sha2`、`log`、`uuid` など）と、パスからだけ取れる名前（`percent-encoding`、`slab`、`winnow` など）があるので、漏れを見つけるには両方を使う必要がある。
- `rustc version 1.98.0 (88d9e12ae 2026-08-18)` の文字列があり、標準ライブラリはこの版のものである。
- パッケージの名前とライブラリの名前が異なるものがある。パッケージ `rustls-webpki` はシンボルでは `webpki` として現れる。

macOS の実行ファイルについては、元のチェックアウトで `cabal build` した `golem` を調べた。

- `otool -L` で見える依存は `/usr/lib/libSystem.B.dylib`、`/usr/lib/libiconv.2.dylib`、`/usr/lib/libffi.dylib`、`/usr/lib/libcharset.1.dylib`、`Security.framework` だけである。libffi は OS のものに動的にリンクされる。
- golem-font は macOS で `extra-libraries: c++` を指定するが、libc++ は動的にも静的にもリンクされていない。`otool -L` に `libc++` が現れず、`nm -u` に C++ のシンボル（`__Z` で始まるもの、`__cxa_` を含むもの）が一つもない。HarfBuzz を `-fno-exceptions -fno-rtti -fno-threadsafe-statics` でビルドしているので、libc++ を参照しないためと考えられる（推測）。
- OS に付属する動的なライブラリは配布物に含めないので、ライセンスの文書を添える必要はない。
- clang は静的なリンクで `libclang_rt.osx.a` を暗に加えることがあるが、加わっているかは確かめていない。

Linux の実行ファイルは、リリースのワークフローをまだ一度も動かしていないので、何がリンクされるかを実物で確かめていない（[ADR 0008](0008-first-release-verification.md)）。
固定の一覧に足していくやり方では、確かめていないものの漏れを防げない。

## 実装すること

### 方針

`THIRD_PARTY_LICENSES/` に入れるものを、固定の一覧ではなく、実行ファイルのリンクの記録から決める。
リンカーに実行ファイルに入れたアーカイブの一覧（リンクマップ）を書かせ、アーカイブの一つ一つを、ライセンスの文書を持つ構成要素に対応させる。
対応の付かないアーカイブが一つでもあれば、`licenses.sh` はエラーで終える。

`libwasmtime.a` の中の Rust のクレートは、リンクマップでは一つのアーカイブとしか見えない。
クレートのライセンスの文書は、wasmtime の版を上げるときに人が生成してリポジトリにコミットし、リリースのたびに `libwasmtime.a` から取り出したクレートの一覧と照合する。

### リンクマップを書かせる

- `scripts/release/build-linux.sh` は、`cabal build` の前に `cabal.project.local` に次を追記する。`scripts/fetch-wasmtime.sh` が同じファイルに書く方式に合わせる。

  ```
  package golem-cli
    ghc-options: -optl-Wl,-Map=<リポジトリの絶対パス>/dist/golem.map
  ```

  GNU ld の `-Map` は、`Archive member included to satisfy reference by file (symbol)` の節に、実行ファイルに入れたアーカイブのメンバーを `/usr/lib/libc.a(printf.o)` の形で並べる。
- `scripts/release/build-macos.sh` は、同じく `-optl-Wl,-map,<リポジトリの絶対パス>/dist/golem.map` を書く。ld64 の `-map` は、`# Object files:` の節に `[ 12] /path/libwasmtime.a(foo.o)` の形でオブジェクトを並べ、`# Dylibs` 相当の情報は持たない。動的なライブラリは `otool -L` で別に確かめている（[ADR 0004](0004-binary-distribution-and-release.md) の `smoke` ジョブ）ので、リンクマップでは静的なアーカイブだけを扱う。
- リンクマップはリンカーの出力を変えないので、CI のビルドとの違いは増えない。

### リンクマップから構成要素を決める

`scripts/release/link-components.sh MAP` を足す。
リンクマップの形式（GNU ld か ld64 か）は、先頭の行で判定する。
リンクマップからアーカイブのパスを重複なく取り出し、次の規則で構成要素に対応させ、`構成要素<TAB>アーカイブのパス` の行を標準出力に書く。
規則は上から順に当て、最初に当たったものを採る。

| アーカイブ | 構成要素 | ライセンスの文書の出どころ |
|---|---|---|
| `libHS<名前>-<版>-*.a`（GHC の libdir、cabal のストア、`dist-newstyle` の下） | `haskell` | 今の `licenses.sh` の `plan.json` の処理 |
| GHC の libdir の下の `libHSrts*.a` | `ghc` | GHC の `LICENSE` |
| どこにあっても `libgmp.a` | `gmp` | 今の `licenses.sh` の GMP の処理（`GMP_SOURCE`） |
| `third_party/wasmtime/lib/libwasmtime.a` | `wasmtime` | コミットしたクレートのライセンスの文書（後述） |
| Alpine で、`/lib/apk/db/installed` に持ち主のパッケージが載っているもの | `apk:<origin>` | apk のパッケージ（後述） |
| macOS で、Xcode の道具の下の `libclang_rt.*.a` | `compiler-rt` | wasmtime の `LICENSE` と同じ Apache-2.0 WITH LLVM-exception の文書 |
| 上のどれにも当たらないもの | なし | エラー |

GHC の libdir の下にあって `libHS` で始まらないアーカイブ（GHC が同梱した libffi など）は、表のどの行にも当たらないのでエラーになる。
GHC 9.10.3 の配布物がそうしたアーカイブを持つかは確かめていないので、リンクマップに現れた時点で、その構成要素とライセンスの文書の出どころを表に足す。
ローカルのパッケージ（`libHSgolem-*.a`）は `haskell` に当たるが、`golem-` で始まるので、今の `licenses.sh` と同じく Golem 自身として扱う。
HarfBuzz、FreeType、zlib-clib の C のコードは Haskell のパッケージのアーカイブの中に入るので、今の固定の一覧（`harfbuzz/`、`freetype/`、`haskell/zlib-clib-*/`）で扱う。

`/lib/apk/db/installed` は、`P:`（パッケージ名）、`V:`（版）、`o:`（origin）、`L:`（SPDX のライセンスの式）、`F:`（ディレクトリ）、`R:`（ファイル）の行を持つ記録を空行で区切って並べたものである。
`apk` のコマンドではなくこのファイルを読むのは、apk-tools の版によるコマンドの出力の違いに左右されず、テストで代わりのファイルを渡せるためである。
パスは `/usr/lib/libc.a` と `/lib/libc.a` のように、シンボリックリンクを解決した形でも引けるようにする。

対応の付かないアーカイブがあれば、そのパスをすべて標準エラー出力に書き、終了コード 1 で終える。

### Alpine のパッケージのライセンスの文書

- `build-linux.sh` は、リンクの後に `link-components.sh` を実行し、`apk:<origin>` の origin ごとに `apk add --no-cache <origin>-doc` を試す。`-doc` のパッケージがない origin では失敗を無視する。
- `licenses.sh` は、`apk:<origin>` ごとに `/usr/share/licenses/<origin>/` と `/usr/share/licenses/<パッケージ名>/` の下のファイルを、`THIRD_PARTY_LICENSES/<origin>/` に写す。
- どちらにもファイルがない origin は、リポジトリの `licenses/alpine/<origin>/` を探す。ここには、Alpine のパッケージがライセンスの文書を入れない場合に限り、上流のソースから取った文書と、取った上流の版を書いた `VERSION` を置く。`VERSION` が `V:` から `-r<数>` を除いた版と一致しなければエラーとする。版によって文面の変わらない文書（GCC の `COPYING3` と `COPYING.RUNTIME`）だけは、`VERSION` に `any` と書いて版の照合を省く。
- それでも見つからなければエラーとする。
- 実装の最初に、ダイジェストで固定した Alpine 3.24 のイメージで `musl-doc`、`libffi-doc`、`gcc-doc` などを入れ、`/usr/share/licenses/` に何が入るかを確かめる。足りない origin の分だけ `licenses/alpine/` に置き、置いた理由をそのディレクトリの README に書く。

`THIRD_PARTY_LICENSES/README` には、`apk:<origin>` ごとに、リンクしたパッケージの名前と版、`L:` のライセンスの式を書く。
origin が `gcc` のもの（libgcc、libgcc_eh、libstdc++）には、次の段落を加える。

```
libgcc and libstdc++ are under the GNU General Public License, version 3
(gcc/COPYING3), with the GCC Runtime Library Exception, version 3.1
(gcc/COPYING.RUNTIME). golem is compiled with GCC, an Eligible Compilation
Process, and the exception permits distributing it under the terms of its
own license.
```

### wasmtime のクレートのライセンスの文書

wasmtime のクレートのライセンスの文書は、リリースのワークフローでは集めない。
wasmtime の版（49.0.2）を固定しているので、版を上げるまで文書は変わらず、リリースのたびにネットワークから集め直す理由がないためである。
版を上げるときは [CONTRIBUTING.md](../../CONTRIBUTING.md) のとおり ADR を書くので、そのときに作り直す。

`scripts/wasmtime-licenses.sh` を足す。
人が手元で実行し、出力をコミットする道具であり、ネットワークに接続する。
POSIX のシェルと `jq`、`cargo`、`rustup` で書き、`cargo about` のような道具は使わない。
要るのは「依存の一覧を求め、各クレートのライセンスのファイルを写す」ことだけで、`cargo metadata` と数十行のシェルで再実装できるためである。

1. `scripts/fetch-wasmtime.sh` と同じ SHA-256 で、三つのプラットフォームの C API の配布物（`aarch64-macos`、`x86_64-musl`、`aarch64-musl`）を取得する。配布物の中のファイルの一覧（`tar -tf`）を出力の `ARCHIVES` に書く。配布物にライセンスの一覧が含まれていれば、それも出力に写す。
2. 各配布物の `libwasmtime.a` から、後述の `rust-crates.sh` でクレートの一覧と rustc の版を取り出す。三つで rustc の版が異なれば、エラーとする。
3. wasmtime の `v49.0.2` のタグを、スクリプトに固定したコミットのハッシュで確かめて取得する。ハッシュは、最初に実行するときに実装者が記録する。
4. `crates/c-api` で、`cargo metadata --locked --format-version 1 --filter-platform <triple>` を三つの triple（`aarch64-apple-darwin`、`x86_64-unknown-linux-musl`、`aarch64-unknown-linux-musl`）で実行する。`resolve` を `wasmtime-c-api` から、`dep_kinds` の `kind` が `null`（通常の依存）の辺だけで辿り、三つの和をとる。開発用とビルド用の依存は実行ファイルに入らないので除く。
5. 4 の一覧のクレートごとに、`cargo fetch` で取得したソースの最上位から、`licenses.sh` と同じ正規表現（`LICEN[CS]E`、`COPYING`、`COPYRIGHT`、`NOTICE`）に当たるファイルを写す。`links` を持つクレート（C のソースを同梱してビルドするもの、`ring` と `zstd-sys` など）は、同梱したソースのライセンスの文書がサブディレクトリにあるので、スクリプトに固定した対応表（例：`zstd-sys` は `zstd/LICENSE` と `zstd/COPYING`）で写す。`links` を持つのに対応表にないクレートがあれば、エラーとする。ライセンスのファイルが一つもないクレートもエラーとする。
6. rustc 1.98.0 を `rustup toolchain install 1.98.0 --component rust-src` で入れ、`$(rustc +1.98.0 --print sysroot)/share/doc/rust/` の `COPYRIGHT`、`LICENSE-APACHE`、`LICENSE-MIT` を写す。標準ライブラリが依存する crates.io のクレートは、`lib/rustlib/src/rust/library/Cargo.lock` から 4 と 5 と同じ手順で写す。compiler_builtins が同梱する LLVM の compiler-rt のライセンスは、llvm-project の `compiler-rt/LICENSE.TXT` を、rustc が使った LLVM の版のタグからスクリプトに固定した SHA-256 で検証して写す。
7. 2 のクレートの一覧が、4 と 6 の一覧にすべて含まれることを確かめる。含まれないものがあればエラーとする。
8. `ar t` で見た C とアセンブリのメンバーの名前（先頭の `<hash>-` を除いたもの）を、プラットフォームごとに `c-objects.tsv` に書く。各行の構成要素（`ring`、`zstd-sys`、`compiler_builtins`、`wasmtime` など）の列は、スクリプトが埋めずに人が埋める。cc クレートのオブジェクトの名前はソースのディレクトリのハッシュしか持たず、クレートに機械的に対応させられないためである。

出力は `licenses/wasmtime-v49.0.2/` に置き、コミットする。
`third_party/` は `.gitignore` に入っているので、その下には置かない。

| パス | 内容 |
|---|---|
| `MANIFEST.tsv` | クレートごとに、パッケージの名前、版、ライブラリの名前、Cargo.toml の `license`、写したファイルの一覧 |
| `crates/<名前>-<版>/` | クレートのライセンスの文書 |
| `rust/` | Rust の標準ライブラリと compiler-rt のライセンスの文書、rustc の版 |
| `c-objects.tsv` | プラットフォーム、C のメンバーの名前、構成要素 |
| `ARCHIVES` | 三つの配布物の名前、SHA-256、中のファイルの一覧 |
| `README` | 生成した日、使った wasmtime のコミット、rustc の版、生成のコマンド |

### libwasmtime.a のクレートを照合する

`scripts/release/rust-crates.sh NM_OUTPUT STRINGS_OUTPUT` を足す。
入力は `nm` と `strings -a` の出力を書いたファイルとし、`libwasmtime.a` そのものは読まない。
テストで小さな入力を渡せるようにするためである。

- `NM_OUTPUT` の各行の最後の欄のうち `_R` または `__R` で始まるものから、`Cs[0-9A-Za-z]*_` に続く `<長さ><名前>` を awk で取り出す。長さの分だけを名前とし、`_` で始まる名前は捨てる。
- `STRINGS_OUTPUT` から `index.crates.io-[0-9a-f]+/<名前>-<版>` を取り出し、名前の `-` を `_` に置き換える。
- `rustc version <版>` を取り出す。
- 出力は、`crate<TAB><ライブラリの名前><TAB><版または ->` の行と、`rustc<TAB><版>` の一行とする。

`licenses.sh` は、構成要素 `wasmtime` があるとき次を行う。

- `build-linux.sh` と `build-macos.sh` が `nm` と `strings -a` で作った二つのファイルを環境変数 `WASMTIME_NM` と `WASMTIME_STRINGS` で受け取り、`rust-crates.sh` を実行する。
- 取り出したライブラリの名前が、`MANIFEST.tsv` のライブラリの名前か、`rust/` に記録した標準ライブラリのクレートの名前のどれかに当たることを確かめる。版が取れたものは版も比べる。当たらないものがあれば、名前を標準エラー出力に書いてエラーとする。
- rustc の版が `rust/` に記録したものと異なれば、エラーとする。
- `ar t` の C のメンバーが、`c-objects.tsv` のそのプラットフォームの行にすべてあることを確かめる。ないものがあればエラーとする。
- `licenses/wasmtime-v49.0.2/` を `THIRD_PARTY_LICENSES/wasmtime/` に写す。今の `third_party/wasmtime/LICENSE` も同じ場所に置く。

照合は `libwasmtime.a` に対して行い、リンクした `golem` には行わない。
`golem` は `strip` するので、シンボルが残らないためである。
`libwasmtime.a` の中にあってリンクで捨てられたクレートの文書も入ることになるが、多く入れる分には害がない。

### licenses.sh の変更

- 環境変数 `LINK_MAP`（必須）、`APK_DB`（既定は `/lib/apk/db/installed`）、`APK_LICENSES`（既定は `/usr/share/licenses`）、`WASMTIME_NM`、`WASMTIME_STRINGS`、`WASMTIME_AR`（`ar t` の出力）を受け取る。
- `link-components.sh "$LINK_MAP"` の結果に従って、上の各節の文書を写す。今の固定の一覧のうち、`ghc/` と `wasmtime/` は、リンクマップに当たる構成要素があるときだけ写す。GMP は、リンクマップに `libgmp.a` が現れなくても今のとおり常に写す。GHC が GMP を `libHSghc-bignum` の中に取り込んでいる場合、リンクマップには Haskell のパッケージとしてしか現れないためである。`libgmp.a` が現れたときは `gmp` の構成要素とし、`apk:gmp` としては扱わない。
- HarfBuzz、FreeType、zlib-clib、hyph-utf8 は、リンクマップでは Haskell のパッケージのアーカイブの中にあって区別できないので、今のとおり固定で写す。
- `THIRD_PARTY_LICENSES/README` の構成要素の一覧を、固定の文ではなく、実際に写したディレクトリから作る。
- `package.sh` は、受け取った環境変数を `licenses.sh` に渡す。

`build-linux.sh` と `build-macos.sh` は、`package.sh` の前に `nm third_party/wasmtime/lib/libwasmtime.a`、`strings -a ...`、`ar t ...` の出力を `dist/` の下に書き、`LINK_MAP` などを設定する。
リンクマップと三つの出力は配布物には入れないが、ワークフローの成果物として `build` ジョブから上げ、後で調べられるようにする。

### ネットワーク

リリースのワークフローで新たにネットワークを使うのは、`build-linux.sh` の `apk add <origin>-doc` だけである。
これは今の `apk add` と同じ段で行い、新しい段は増やさない。
wasmtime のクレートの文書はコミットしたものを使うので、リリースのワークフローは crates.io に接続しない。

### ドキュメント

- [仕様書](../specifications.md)の「配布物」の節に、`THIRD_PARTY_LICENSES/` の中身をリンクマップから決めることと、この ADR へのリンクを書く。
- [CONTRIBUTING.md](../../CONTRIBUTING.md) と `CONTRIBUTING.en.md` の、固定したネイティブライブラリの版を上げるときの段落に、wasmtime の版を上げるときは `scripts/wasmtime-licenses.sh` で `licenses/` を作り直すことを書く。
- README の Development の節に、`licenses/` の役割を一行書く。

## 実装しないこと

- リリースのワークフローの中でクレートのライセンスを集めること。理由は「wasmtime のクレートのライセンスの文書」の節に書いた。
- `cargo about`、`cargo deny` のような道具の導入。要る機能が一覧と写しだけで、再実装が容易なためである。
- クレートの `license` の式を解釈して、ライセンスの条件の両立を自動で判定すること。一覧には式を記録するが、判定は人が行う。
- 写したライセンスの文書の重複の除去。Apache-2.0 の同じ本文が多く重なるが、MIT のように著作権者の表示がクレートごとに異なるものがあるので、クレートごとに置く。
- ライセンスの文書を `golem` の実行ファイルに埋め込み、コマンドで表示すること。
- OS に付属する動的なライブラリ（macOS の libSystem、libffi、libiconv、Security.framework）のライセンスの文書。配布物に含めないためである。
- macOS の libc++ の扱い。今はリンクされていないことを確かめた。将来静的にリンクされれば、リンクマップの照合でエラーになり、そのときに対応表へ足す。

## テスト設計

### リリースのスクリプト（`scripts/release/test.sh`）

`testdata/` に小さなリンクマップと入力のファイルを置き、今の `licenses.sh` のテストと同じく一時ディレクトリで実行する。

`link-components.sh`：

- GNU ld のリンクマップ（`Archive member included to satisfy reference by file (symbol)` の節に、`libHSbase-4.20.2.0-*.a`、`libHSrts-1.0.2_thr.a`、`/usr/lib/libc.a`、`/usr/lib/libffi.a`、`/usr/lib/gcc/x86_64-alpine-linux-musl/14.2.0/libgcc.a`、`/usr/lib/libstdc++.a`、`third_party/wasmtime/lib/libwasmtime.a` のメンバーを並べたもの）と、それらの持ち主を載せた `installed` の代わりのファイルで、`haskell`、`ghc`、`apk:musl`、`apk:libffi`、`apk:gcc`、`wasmtime` が一行ずつ、決まった順に出ること。
- 同じアーカイブのメンバーが何行あっても、構成要素は一度だけ出ること。
- `/usr/lib/libncursesw.a` を足し、`installed` に持ち主を載せないと、終了コード 1 になり、標準エラー出力にそのパスが出ること。
- ld64 のリンクマップ（`# Object files:` の節に、GHC の libdir の `libHS*.a`、`libgmp.a`、`libwasmtime.a` のメンバーを並べたもの）で、`haskell`、`ghc`、`gmp`、`wasmtime` が出ること。
- ld64 のリンクマップに `libclang_rt.osx.a` を足すと、`compiler-rt` が出ること。
- `installed` で `/lib/libc.a` として載っているファイルが、リンクマップの `/usr/lib/libc.a` から引けること（テストの中でシンボリックリンクを作る）。

`rust-crates.sh`：

- `__RNvCs6h3VoTfJ7Jy_8wasmtime3foo` と `_RNvCsairsClScZ4T_14wasmtime_c_api3bar` の二行の `nm` の出力から、`wasmtime` と `wasmtime_c_api` が出ること。
- `Cs<識別子>_8___rust` を含む行から、名前が出ないこと。
- `strings` の出力の `/index.crates.io-1949cf8c6b5b557f/rustls-webpki-0.103.13/src/lib.rs` から、`rustls_webpki` と `0.103.13` が出ること。
- `rustc version 1.98.0 (88d9e12ae 2026-08-18)` から `rustc<TAB>1.98.0` が出ること。

`licenses.sh`：

- 今の「all found」の入力に、リンクマップ、`installed`、`/usr/share/licenses` の代わりのディレクトリ（`musl/COPYRIGHT`、`libffi/LICENSE`）、`licenses/alpine/gcc/`（`COPYING3`、`COPYING.RUNTIME`、`VERSION` に `any`）、小さな `licenses/wasmtime-v49.0.2/` を加え、終了コード 0 で `musl/COPYRIGHT`、`libffi/LICENSE`、`gcc/COPYING3`、`gcc/COPYING.RUNTIME`、`wasmtime/crates/<名前>-<版>/LICENSE` が書かれること。
- README に `GCC Runtime Library Exception` と、`installed` の `L:` のライセンスの式が現れること。
- `/usr/share/licenses` の代わりから `libffi/` を除き、`licenses/alpine/libffi/` もないと、終了コード 1 になり、`libffi` が標準エラー出力に出ること。
- `licenses/alpine/<origin>/VERSION` が `installed` の版と異なると、終了コード 1 になること。
- `rust-crates.sh` の入力に `MANIFEST.tsv` にないクレート（例：`left_pad`）を足すと、終了コード 1 になり、その名前が標準エラー出力に出ること。
- `MANIFEST.tsv` の版と異なる版のパス（`ring-0.17.15`）を足すと、終了コード 1 になること。
- rustc の版が `rust/` の記録と異なると、終了コード 1 になること。
- `ar t` の出力に `c-objects.tsv` にない C のメンバーを足すと、終了コード 1 になること。
- `LINK_MAP` を設定しないと、終了コード 1 になること。
- リンクマップに `wasmtime` の構成要素がないと、`THIRD_PARTY_LICENSES/wasmtime/` が書かれず、README にも wasmtime が現れないこと。

これらのテストは、`link-components.sh` と `rust-crates.sh` を足す前に書いて失敗させる。

### 自動テストにしないもの

- `scripts/wasmtime-licenses.sh` はネットワークと Rust の道具を要するので、CI では実行しない。最初に実行したときに、7 の照合が通ることと、出力の `MANIFEST.tsv` の行数が手元の `libwasmtime.a` から取れたクレートの数以上であることを確かめ、結果を README に書く。
- リリースのワークフローでの確かめは [ADR 0008](0008-first-release-verification.md) の手順で行う。三つの配布物の `THIRD_PARTY_LICENSES/` に、Linux では `musl/`、`libffi/`、`gcc/` が、三つとも `wasmtime/crates/` があることを、`build` ジョブが上げたリンクマップと突き合わせて確かめる。

## トレードオフ

リンクマップから決めるので、リンクの結果が変われば、配布物の中身も黙って追随する。
新しいアーカイブが加われば、対応表に足すまでリリースが止まる。
リリースの直前に止まるのは手間だが、ライセンスの文書を欠いた配布物を出すよりよい。

wasmtime のクレートの文書をコミットするので、リポジトリが 1MB 程度大きくなる（Apache-2.0 の本文が約 11KB で、クレートが 100 前後あるため。概算）。
代わりに、リリースのワークフローが crates.io に依存せず、文書の差分をプルリクエストで読める。

クレートの照合は、シンボルとパニックの位置の文字列という、Rust のコンパイラの出力の形に頼る。
v0 のマングルの形やパスの書き方が変われば照合が通らなくなりうるが、その場合はエラーで止まり、黙って漏れることはない。
逆に、パニックの位置も公開のシンボルも持たないクレートは照合から漏れうる。
この漏れは `cargo metadata` で辿った依存の一覧で補う。

cc クレートが作った C のメンバーの構成要素を人が埋めるので、wasmtime の版を上げるたびに手作業がある。
版を上げるのは ADR を書くときだけなので、頻度は低い。

Alpine のパッケージの文書は、パッケージがライセンスのファイルを入れていればその版のものを使えるが、入れていなければリポジトリに置いた文書の版を手で合わせる必要がある。
どちらになるかは、実装の最初に確かめる。
