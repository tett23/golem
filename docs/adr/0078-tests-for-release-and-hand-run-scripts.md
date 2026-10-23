# ADR 0078: リリースのときと手でだけ動くスクリプトにテストを書く

ステータス: 採択（未実装）

## 文脈

scripts の下のスクリプトのうち、テスト（[scripts の下](https://github.com/tett23/golem/tree/e874129709193ecc0b4a21a299028de7875aa8ce/scripts) の各ディレクトリの test.sh）で一度も実行されないものが 15 本ある（2026-10-23 のテストの品質の点検）。
ただし、テストで実行されなくても、CI が毎回動かすスクリプトは、壊れればその場で CI が落ちる。
15 本を、いつ動くかで三つに分けた。

- CI が毎回動かすもの（5 本）：[scripts/ci/fetch-hlint.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/fetch-hlint.sh)、[scripts/ci/textlint.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/textlint.sh)（[docs.yml](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/.github/workflows/docs.yml)）、[scripts/determinism.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/determinism.sh)、[scripts/gen-parser.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/gen-parser.sh)（[ci.yml](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/.github/workflows/ci.yml) が生成したパーサーと文法の一致を確かめる）、[scripts/manual/check-figures.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/manual/check-figures.sh)（docs.yml）。[scripts/manual/outline-figures.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/manual/outline-figures.sh) は check-figures.sh が呼ぶので、ここに入る。
- リリースのときだけ動くもの（5 本）：[scripts/release/smoke.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/release/smoke.sh)、[package.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/release/package.sh)、[build-macos.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/release/build-macos.sh)、[fetch-gmp.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/release/fetch-gmp.sh)、[gmp-version.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/release/gmp-version.sh)（[release.yml](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/.github/workflows/release.yml)）。
- 手でだけ動くもの（4 本）：[scripts/gen-vertical-orientation.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/gen-vertical-orientation.sh)、[scripts/fixtures/copy-fonts.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/fixtures/copy-fonts.sh)、[scripts/fixtures/fetch-public-domain.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/fixtures/fetch-public-domain.sh)、[scripts/wasmtime-licenses.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/wasmtime-licenses.sh)（wasmtime の版を上げたときに動かし、出力をコミットする。出力は release の [licenses.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/release/licenses.sh) が検査する）。

二つめと三つめは、壊れても次にリリースするときか、次に手で動かすときまで気付かない。
リリースのときに気付くと、タグを打った後に直すことになる。
[build-linux.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/release/build-linux.sh) は、[scripts/release/test.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/release/test.sh#L419-L426) が中身を grep するだけで実行しない。

## 実装すること

リリースのときと手でだけ動くスクリプトに、ネットワークと本物のツールチェーンを使わないテストを書く。
外部のコマンド（`curl`、`ghc`、`codesign`、`otool`、`strip`）は、今の test.sh と同じく、`PATH` の先頭に置いた偽物で差し替える。

- package.sh：偽の実行ファイルと偽の licenses.sh の入力から作ったアーカイブに、golem、LICENSE、BUILDINFO、THIRD_PARTY_LICENSES/README があり、`.sha256` が中身と一致する。
- gmp-version.sh：偽の `ghc --print-libdir` が指すディレクトリに置いた `ghc-gmp.h`（macOS の形）と、`<gmp.h>` を読む `ghc-gmp.h`（Alpine の形）の両方から、版を読む。
- fetch-gmp.sh：偽の `curl` で、最初の配布元が失敗し二つめが成功するとき、SHA-256 を確かめて置く。SHA-256 が合わないときは失敗し、ファイルを残さない。表にない版は失敗する。
- build-macos.sh と build-linux.sh：実行のすべては試さない。引数の検査と、呼ぶ順序（fetch-gmp.sh、ビルド、package.sh）を、各段を偽物にして確かめる。偽物にできる形にスクリプトを分けられないなら、この二本は対象から外し、その理由を test.sh の注釈に書く。
- smoke.sh：偽の golem（`--version` と `new` と `build` に固定の振る舞いを返すシェルのスクリプト）を入れた偽のアーカイブで、版の不一致、ファイルの欠け、`.sha256` の不一致のそれぞれで失敗し、すべてそろえば成功する。`--offline` で動かし、フォントを取りに行かない。
- gen-vertical-orientation.sh：数行の `VerticalOrientation.txt` の fixture（`@missing` の行と、隣り合う同じ値の範囲を含む）から、期待する表を作る。
- copy-fonts.sh と fetch-public-domain.sh：copy-fonts.sh は、一時ディレクトリに作った fixture の木で、和書に Noto Serif JP、英書に Source Serif がライセンスとともに入ることを確かめる。fetch-public-domain.sh は偽の `curl` で、取得した本文の SHA-256 が合わないとき、変換（golem-fixtures と `golem fmt`）に進まずに失敗することを確かめる。
- これらのテストは [scripts/release/test.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/release/test.sh) と、新しい scripts/test.sh（gen-vertical-orientation.sh と [scripts/fixtures](https://github.com/tett23/golem/tree/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/fixtures) の二本のため）に置く。scripts/test.sh は ci.yml の `changes` ジョブで走らせる。

## 実装しないこと

- CI が毎回動かす 5 本（と outline-figures.sh）にテストを足すこと。壊れれば CI が落ちる。
- 本物の GHC でリリースのビルドを試すこと。release.yml が行う。
- [scripts/wasmtime-licenses.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/wasmtime-licenses.sh) のテスト。curl、git、jq、nm、strings、ar、cargo、rustup を使い、偽物で差し替える範囲が大きすぎる。出力はリリースのときに licenses.sh が検査する。
- smoke.sh が確かめる中身を増やすこと。[ADR 0080](0080-release-smoke-checks-diagnostics.md) で扱う。

## テスト設計

ここに書いたテストそのものがこの ADR の実装である。
それぞれ、対象のスクリプトの主な分岐を壊した変異（SHA-256 の検査を省く、版の比較を省く、ファイルを一つ書かない）で落ちることを確かめる。

## トレードオフ

- 偽物のコマンドで試すので、本物のツールの振る舞いの変化（`otool` の出力の形の変化など）は見つからない。それはリリースのときに見つかる。
- build-macos.sh と build-linux.sh は、偽物で差し替えられる形にするためにスクリプトを分ける可能性がある。分けると読みにくくなるなら、対象から外す。

## 参考文献

- [ADR 0004](0004-binary-distribution-and-release.md)
- [ADR 0026](0026-ten-public-domain-fixtures.md)
- [ADR 0080](0080-release-smoke-checks-diagnostics.md)
