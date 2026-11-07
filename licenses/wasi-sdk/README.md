# wasm のツールチェーンがリンクするライブラリのライセンスの文書

`golem.wasm` は、ghc-wasm-meta の 9.10 の flavour のツールチェーン（`scripts/fetch-ghc-wasm.sh`）で組む（[ADR 0199](../../docs/adr/0199-pdf-typesetting-as-wasm-reactor.md)）。
そのリンカーは、wasi-sdk の wasi-libc、libc++、libc++abi、compiler-rt と、wasm の GHC の RTS が使う libffi-wasm を `golem.wasm` に入れる。
ghc-wasm-meta の wasi-sdk と libffi-wasm の配布物はライセンスの文書を持たないので、上流のリポジトリから取ってここに置く。
`scripts/release/licenses.sh --wasm` は、このディレクトリの `wasi-libc/`、`llvm/`、`libffi-wasm/` を `THIRD_PARTY_LICENSES/wasi-sdk/` に写す（[ADR 0007](../../docs/adr/0007-third-party-licenses.md)）。

## 出どころ

- **wasi-sdk**：`scripts/fetch-ghc-wasm.sh` が取る haskell-wasm/ghc-wasm-bindists の `20251219T213239` のリリースの `wasi-sdk.tar.gz`（`VERSION`）。wasi-sdk 29.0 を元にした ghc-wasm-meta の fork で、clang は `21.1.8-wasi-sdk` である。
- **wasi-libc**：[WebAssembly/wasi-libc](https://github.com/WebAssembly/wasi-libc) のタグ `wasi-sdk-29`（コミット `ac020b86fd44bafe60aa4fa12f407d16e3731329`）の `LICENSE-APACHE`、`LICENSE-APACHE-LLVM`、`LICENSE-MIT` と、`libc-top-half/musl/COPYRIGHT`（`COPYRIGHT-musl`）。
- **LLVM**：[llvm/llvm-project](https://github.com/llvm/llvm-project) のタグ `llvmorg-21.1.8`（コミット `2078da43e25a4623cab2d0d60decddf709aaea28`）の `libcxx/LICENSE.TXT`、`libcxxabi/LICENSE.TXT`、`compiler-rt/LICENSE.TXT`（それぞれ `libcxx-LICENSE.TXT`、`libcxxabi-LICENSE.TXT`、`compiler-rt-LICENSE.TXT`）。
- **libffi-wasm**：[haskell-wasm/libffi-wasm](https://gitlab.haskell.org/haskell-wasm/libffi-wasm) のコミット `788aec0a4ca936c3e6c706e010c979a3c4eea2d6` の `LICENSE`（MIT）。ツールチェーンの配布物は `20250310T060803` のリリースのもので、ライセンスの文書は 2026-11-08 の時点の `master` から取った。

ghc-wasm-meta の fork の wasi-sdk が、どの wasi-libc と LLVM のコミットから組まれたかは、配布物からはわからない。
上の文書は、元にした wasi-sdk 29.0 の版のものである。

## SHA-256

| ファイル | SHA-256 |
| --- | --- |
| `wasi-libc/LICENSE-APACHE` | `a60eea817514531668d7e00765731449fe14d059d3249e0bc93b36de45f759f2` |
| `wasi-libc/LICENSE-APACHE-LLVM` | `268872b9816f90fd8e85db5a28d33f8150ebb8dd016653fb39ef1f94f2686bc5` |
| `wasi-libc/LICENSE-MIT` | `23f18e03dc49df91622fe2a76176497404e46ced8a715d9d2b67a7446571cca3` |
| `wasi-libc/COPYRIGHT-musl` | `f9bc4423732350eb0b3f7ed7e91d530298476f8fec0c6c427a1c04ade22655af` |
| `llvm/libcxx-LICENSE.TXT` | `539dd7aed86e8a4f12cbdd0e6c50c189c7d74847e4fecc64ce2c6ee3a01da38b` |
| `llvm/libcxxabi-LICENSE.TXT` | `e2b35be49f7284a45b7baca8fc7b3ab7440e7902392b2528a457816b5bb2a15c` |
| `llvm/compiler-rt-LICENSE.TXT` | `1a8f1058753f1ba890de984e48f0242a3a5c29a6a8f2ed9fd813f36985387e8d` |
| `libffi-wasm/LICENSE` | `53a203d582e76ea32c77f1423fbef9b642fab27eb85cbc8164f19f4b047a6940` |

`scripts/fetch-ghc-wasm.sh` の wasi-sdk を変えたら、その版の文書を確かめ、ここのファイルと `VERSION` を更新する。
`VERSION` が `scripts/fetch-ghc-wasm.sh` の `SDK_URL` と食い違うと、`licenses.sh --wasm` は失敗する。
