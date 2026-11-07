# ADR 0202: wasm で組めなかったパッケージの扱い

ステータス: 採択→golem-driver の Template Haskell の扱いは [ADR 0203](0203-generated-modules-instead-of-template-haskell-in-golem-driver.md)

## 文脈

[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md) は、PDF の組版を wasm の reactor モジュールにして配ると決めた。
その「1. 最初に組めるかを確かめる」は、ほかの作業の前に、golem-plugin を外した golem-driver の依存がすべて wasm で組めるかを確かめ、組めないものがあればそこで止めて、扱いを新しい ADR で決めるとした。
この ADR が、その新しい ADR である。

### 確かめた条件

2026-11-07 に、main の作業用のブランチで、golem-driver の cabal から golem-plugin と `Golem.Driver.New` を外し、`Golem.Driver.Plugins` を何もしない版に差し替えて組んだ（変更はコミットしていない）。
ツールチェーンは、ghc-wasm-meta（`8079eb96`）の 9.10 の flavour の配布物で、GHC は `9.10.3.20260731`、cabal は 3.14.2.0 である。
`cabal.project.wasm` には、golem-driver が依存する golem のパッケージと peg-runtime を並べ、`tests: False` と zlib の `+bundled-c-zlib` を書いた。

[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md) は x86-64 の Linux の向けの配布物だけを取ると決めたが、確かめたのは手元の macOS で、aarch64-darwin の向けの配布物を使った。
下のエラーは、どれも wasm の側（wasi-libc のヘッダー、32 ビットの型、ないライブラリ）で起きており、ホストの種類には依らないと見込める。
ただし、x86-64 の Linux では確かめていない。

### 組めなかったもの

組めなかったものは五つある。
cabal は、一つが失敗しても、それに依らないパッケージを組み続けるので、五つは同じビルドで見つかった。
一方で、この五つに依るパッケージ（golem のパッケージのすべてを含む）は、まだ一度も組めていない。
そのため、五つを片付けた後に、さらに組めないものが見つかる見込みがある。

一つめは、FreeType である。
golem-font が同梱する FreeType 2.14.3 の `ftstdlib.h` は、`<setjmp.h>` を無条件に読む（[`ftstdlib.h`](https://github.com/tett23/golem/blob/00f8170102387807f9c5ff6d2f093745bd6230b8/modules/golem-font/cbits/freetype/include/freetype/config/ftstdlib.h#L166-L173)）。
wasi-sdk の `setjmp.h` は、`-mllvm -wasm-enable-sjlj` を付けずに読むと `#error` で止まる。
エラーの文は、setjmp と longjmp には wasm の例外処理（exception handling）の提案が要り、それを実装したエンジンを使うよう求める。
Golem が組み込む FreeType のモジュールで `ft_setjmp` を呼ぶのは、`cmap` のサブテーブルを検証する箇所だけである（[`ttcmap.c`](https://github.com/tett23/golem/blob/00f8170102387807f9c5ff6d2f093745bd6230b8/modules/golem-font/cbits/freetype/src/sfnt/ttcmap.c#L3843-L3847)）。
検証が誤りを見つけると longjmp で戻り、そのサブテーブルを使わずに次へ進む。
つまり、壊れた `cmap` を持つフォントでも、ネイティブの Golem は止まらずに組む。

二つめは、cborg 0.2.10.0 である。
`Codec.CBOR.Decoding` で `Word64#` と `Word#`（`Int64#` と `Int#`）の型が合わず、`Codec.CBOR.Magic` は `GHC.IntWord64` を見つけられない。
wasm32 は 32 ビットなので、64 ビットのプリミティブの型が `Word#` と別になるためである。
Hackage の索引（2026-10-12）では、0.2.10.0 が cborg の最新である。
上流の GitHub の master には、32 ビットで組めるようにする変更（[`ecc1360d`](https://github.com/well-typed/cborg/commit/ecc1360dcf9e9ee27d08de5206b844e075c88ca4)、2025-07-16）と、wasm32 でスレッドを使わない変更（[`2634c110`](https://github.com/well-typed/cborg/commit/2634c110fe360fc03e2f9b5f5a0dc5aa1a971edb)、2026-05-13）が入っているが、リリースされていない。
Golem で cborg を使うのは、golem-doc の `Golem.Doc.Cbor`（プラグインの ABI の符号化）だけである（[`golem-doc.cabal`](https://github.com/tett23/golem/blob/00f8170102387807f9c5ff6d2f093745bd6230b8/modules/golem-doc/golem-doc.cabal#L28)）。
これを取り込むのは golem-plugin と golem-cli と、テストだけで、PDF の組版の道は使わない。
[ADR 0173](0173-rc4-refactoring.md) は、`Golem.Doc.Cbor` を「意味論 IR とプラグインの ABI」の golem-doc に置くと決めている。

三つめと四つめは、`entropy` 0.4.1.11 と `network-info` 0.2.1 である。
`entropy` は独自の `Setup` を持ち、cabal がその `Setup` を wasm の GHC でリンクしようとして、threaded の RTS（`-lHSrts-1.0.2_thr`）がないために失敗した。
`network-info` は、wasi-libc にない `netdb.h` を読む。
二つとも、`uuid` 1.3.16.1 だけが依存している。
`uuid` を使うのは、golem-pdf の文書 ID（`Data.UUID.V5.generateNamed` で作る名前による UUID）と、golem-cli（`golem new` の `Data.UUID.V4`）である（[`Writer.hs`](https://github.com/tett23/golem/blob/00f8170102387807f9c5ff6d2f093745bd6230b8/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L279-L281)、[`golem-pdf.cabal`](https://github.com/tett23/golem/blob/00f8170102387807f9c5ff6d2f093745bd6230b8/modules/golem-pdf/golem-pdf.cabal#L39)）。
golem-cli は wasm に入らない。
golem-pdf は SHA-256 を golem-syntax の実装で計算しており（[`Sha256.hs`](https://github.com/tett23/golem/blob/00f8170102387807f9c5ff6d2f093745bd6230b8/modules/golem-pdf/src/Golem/Pdf/Sha256.hs)）、ハッシュを自前で持つ前例がある。

五つめは、`network` 3.2.9.0 である。
wasi-libc に `getaddrinfo` などの宣言がなく、C のコンパイルで止まる。
WASI の preview 1 にはソケットがない。
上流の GitHub の master（`1f6aa85`、2026-11-04）にも、WASI に対応する変更はない。
`network` には、次の連なりで依存している。

- golem-html が `skylighting` 0.15 に依存する（[`golem-html.cabal`](https://github.com/tett23/golem/blob/00f8170102387807f9c5ff6d2f093745bd6230b8/modules/golem-html/golem-html.cabal#L29)）。
- `skylighting-core` 0.15 が `xml-conduit` に、`xml-conduit` が `conduit-extra` に、`conduit-extra` と `streaming-commons` が `network` に依存する。

`skylighting-core` で `xml-conduit` を使うのは、XML の構文の定義を読む `Skylighting.Parser` だけであり、それを `Skylighting.Loader` が使う。
Golem が使うのは、`lookupSyntax`、`tokenize`、`defaultSyntaxMap` だけである（[`Html.hs`](https://github.com/tett23/golem/blob/00f8170102387807f9c5ff6d2f093745bd6230b8/modules/golem-html/src/Golem/Html.hs#L756-L776)）。
`defaultSyntaxMap` は、`skylighting` の中に Haskell のソースとして生成済みの構文の表で、XML を読まない。
ただし、`skylighting` の `Skylighting` のモジュールが `Skylighting.Parser` と `Skylighting.Loader` を再びエクスポートするので、パッケージとしては外せない。
PDF の組版もコードの色分けに golem-html の `codeTokens` を使う（[`Flow.hs`](https://github.com/tett23/golem/blob/00f8170102387807f9c5ff6d2f093745bd6230b8/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L102)）ので、wasm から `skylighting` を外すと、PDF のバイト列がネイティブと変わる。
`skylighting` のライセンスは GPL-2.0、`skylighting-core` は BSD-3-Clause である。

### 組めたもの

`toml-parser` 2.0.2.0 は、はじめ `alex` が見つからずに止まった。
cabal は、wasm に向けて組むとき、`build-tool-depends` の `alex` と `happy` を組まず、`PATH` から探す。
ネイティブの GHC で組んだ `alex` 3.5.4.2 と `happy` 2.2 を `PATH` に置くと、組めた。

wasi-sdk の clang で、HarfBuzz の `harfbuzz-world.cc` を golem-font と同じオプションでコンパイルできた。
`pthread_mutex_t` の初期化、ロック、解放を呼ぶ C のプログラムも、wasm32-wasi に向けてコンパイルしてリンクできた（動かしてはいない）。
[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md) の 5 が「なければ何もしないマクロにする」とした pthread の関数は、wasi-sdk にある。

### まだ確かめていないもの

- Template Haskell の三つのモジュール（`Golem.Driver.Version`、`Golem.Driver.Explain`、`Golem.Layout.Hyphenation.EnUs`）。golem のパッケージまでビルドが進んでいない。
- golem-font のリンク（`c++` と `c++abi` のライブラリの名前）。
- 五つに依るパッケージのすべて（`skylighting` の残り、`zlib`、peg-runtime、golem のパッケージ）。
- 例外処理の提案を使う wasm を、Node の LTS とブラウザが動かせるか。

## 実装すること

### 方針

組めない理由ごとに、ネイティブの出力を変えない扱いを選ぶ。
PDF の組版の道にあるもの（FreeType、`uuid`、`skylighting`）は、wasm でもネイティブと同じ結果を返すように扱う。
道にないもの（cborg）は、組めさえすればよい。
上流が直していれば上流を使い、直していなければ、要るところだけを Golem の側で持つ。

### 1. 文書 ID の UUID を golem-pdf で作る

- golem-pdf に `Golem.Pdf.Sha1` を作り、SHA-1（FIPS 180-4）を実装する。golem-pdf のほかに使うところがないので、golem-syntax には置かない。
- `documentId` を、RFC 9562 の 5.5 節の UUID version 5 の手順で作り直す。名前空間は今と同じ URL の名前空間（`6ba7b811-9dad-11d1-80b4-00c04fd430c8`）、名前は今と同じ識別子の UTF-8 のバイト列とする。
- golem-pdf のライブラリの `build-depends` から `uuid` を除く（「メンテナーが決めること」の 3）。golem-cli の `uuid` はそのままにする。
- 出力は変えないので、`scripts/determinism/hashes.txt` と golden のファイルが差分に現れないことを確かめる。

このプルリクエストはネイティブだけを変え、[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md) の 2 より前に入れる。

### 2. wasm のビルドに加えること

次の四つは、[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md) の 5 から 7 の作業に加える。
ネイティブのビルドは変えない。

- **FreeType**：golem-font の cabal の `if os(wasi)` の枝で、`cc-options` に `-mllvm -wasm-enable-sjlj` を足し、wasi-libc の `setjmp` のライブラリをリンクする（「メンテナーが決めること」の 1）。FreeType のソースは変えない。
- **cborg**：`cabal.project.wasm` に、cborg の上流の GitHub のコミット `6ef2791ca41b397a3e36c868ad3e66a0d09f19b2`（`subdir: cborg`）を `source-repository-package` で書く（「メンテナーが決めること」の 2）。`cabal.project` の peg-hs と同じ形である。
- **skylighting**：`scripts/fetch-wasm-packages.sh` を作り、Hackage から `skylighting-core-0.15` と `skylighting-0.15` のアーカイブを取り、SHA-256 を確かめて `third_party/wasm-packages/` に展開し、`scripts/wasm/patches/` の差分を `patch -p1` で当てる（「メンテナーが決めること」の 4）。差分は、`Skylighting.Parser` と `Skylighting.Loader` のモジュール、それらの再エクスポート、`xml-conduit` の依存を除くだけにする。`cabal.project.wasm` の `packages:` に、展開した二つのディレクトリを並べる。
- **alex と happy**：wasm のジョブで、ネイティブの GHC 9.10.3 と cabal で `alex` 3.5.4.2 と `happy` 2.2（`cabal.project.freeze` の版）を組み、`PATH` に置く（「メンテナーが決めること」の 5）。組んだものは `actions/cache` に置く。

[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md) の 6 は、`cabal.project.wasm.freeze` と `cabal.project.freeze` の両方にあるパッケージの版が一致することを CI で確かめるとした。
cborg、`skylighting-core`、`skylighting` は、この検査から外し、外した理由をスクリプトの中に書く。
差分を当てた `skylighting` と `skylighting-core` は、版の番号が Hackage のものと同じで、中身が違う。
版の一致を検査に通すと、その違いが見えなくなるので、外す。

`THIRD_PARTY_LICENSES/` には、cborg の上流のコミットと、`skylighting` と `skylighting-core` の差分のファイルと元のアーカイブの URL を入れる（[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md) の 8）。

### 3. 組めるかをもう一度確かめる

1 と 2 を当てた状態で、[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md) の 1 をもう一度行う。
今度は x86-64 の Linux で、[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md) が決めたとおりの配布物を使う（「メンテナーが決めること」の 6）。

- 確かめるもの：「まだ確かめていないもの」の四つと、golem-driver（golem-plugin を外した版）の依存のすべて。例外処理の提案を使う wasm は、Node の LTS の `node:wasi` で、壊れた `cmap` を持つフォントを読ませて longjmp が戻ることを確かめる。
- 結果は、[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md) の 1 が決めたとおり、[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md) の 2 のプルリクエストの説明と `docs/ci-timings/` に書く。
- また組めないものが見つかれば、そこで止め、新しい ADR で扱いを決める。Template Haskell が組めなければ、[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md) の「メンテナーが決めること」の 5 が挙げた、生成したモジュールをコミットする案から検討する。

### 4. 文書

- [ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md) のステータスの行に、組めなかったものの扱いをこの ADR が決めたことを書く。
- [ADR 0173](0173-rc4-refactoring.md) は変えない（cborg を golem-doc に置いたままにするため）。
- [docs/specifications.md](../specifications.md) は、文書 ID を「名前ベースの UUID（v5）で導出する」と書き、パッケージの名前を書いていないので、変えない。
- README の「固定しているネイティブライブラリ」に、cborg の上流のコミットと、`skylighting` の差分を書く（[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md) の 9 と同じプルリクエスト）。

### パッケージの依存

この ADR は、golem のパッケージのあいだの `build-depends` を変えない。
Hackage のパッケージでは、golem-pdf のライブラリから `uuid` を除き、golem-pdf のテストに `uuid`（今の版の範囲）を足す。

## 実装しないこと

- **ネイティブで cborg と skylighting を差し替えること**：ネイティブは今の Hackage の版のままとする。
- **network を WASI に移すこと**：WASI の preview 1 にソケットがなく、Golem の使わない機能のために C の部分を書き直すことになる。
- **wasm だけコードの色分けをやめること**：PDF のバイト列がネイティブと変わり、[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md) の比べが通らない。
- **FreeType のソースを書き換えること**：同梱の FreeType を上げるたびに、書き換えを当て直すことになる。
- **`Golem.Doc.Cbor` を golem-doc から出すこと**：[ADR 0173](0173-rc4-refactoring.md) の分け方を変えることになる（「メンテナーが決めること」の 2）。
- **上流に修正を送ること**：cborg のリリースを頼むことも、skylighting に `xml-conduit` を外すフラグを頼むことも、この ADR では行わない。送るなら、実機で確かめたことだけを書く。

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。

### 1 のテスト（ネイティブ）

- `Golem.Pdf.Sha1`：FIPS 180-4 の例（`abc`、空のバイト列、448 ビットの例の `abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq`、`a` を 100 万回）で、決まった値を返すこと。64 バイトの区切りの前後の長さ（55、56、63、64、65 バイト）は、次の UUID の性質のテストが生成する長さに必ず含める。
- `documentId`：RFC 9562 の付録 A.4 の例（DNS の名前空間と `www.example.com`）で、付録の値の UUID を作ること（名前空間を引数に取る内部の関数で確かめる）。
- `documentId`：生成した任意の `Text`（空、ASCII、日本語、長さ 0 から 300 バイト）で、`uuid` の `Data.UUID.V5.generateNamed namespaceURL` と同じ 16 バイトを返すこと（hedgehog の性質のテスト。golem-pdf のテストに `uuid` を足す）。
- 今の golem-pdf と golem-driver のテスト、`scripts/determinism/hashes.txt`、golden のファイルが変わらないこと。

### 2 と 3 で確かめること（wasm）

wasm のビルドは、自動のテストを先に書けない。
3 で次のことを確かめ、結果を [ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md) の 2 のプルリクエストの説明に書く。

- `cabal.project.wasm` で、golem-driver（golem-plugin を外した版）の依存のすべてが組めること。
- `-mllvm -wasm-enable-sjlj` で組んだ golem-font を Node の LTS で動かし、正しいフォントのグリフの ID と送り幅がネイティブと一致すること。`cmap` の長さを壊したフォントで、ネイティブと同じく止まらずに、そのサブテーブルを使わずに組めること。
- 差分を当てた `skylighting` で、golem-html のコードの色分けのテストの入力（Haskell、Rust、TOML など、今のテストが使う言語）のトークンの列が、ネイティブと一致すること。

[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md) の 7 の PDF のバイト列の比べが通れば、FreeType、`skylighting`、文書 ID のどれも、ネイティブと同じ結果を返していることになる。
そのため、3 で確かめた後は、ここに挙げたものを別のテストとして CI に置かない。

### 2 の検査のスクリプト

- `scripts/fetch-wasm-packages.sh`：アーカイブの SHA-256 を一文字変えると、展開せずに失敗すること。差分が当たらないとき（`patch` が失敗したとき）に、失敗すること。二度走らせても、同じ木になること。
- freeze の一致の検査：cborg、`skylighting-core`、`skylighting` のほかで版が違う一覧を `scripts/ci/testdata` に置き、検査が失敗すること。

## トレードオフ

`-mllvm -wasm-enable-sjlj` で組んだ wasm は、例外処理の提案を実装したエンジンでしか動かない。
ページの ADR が狙うブラウザと、CI の Node が対応しているかは、3 で確かめるまでわからない。
対応していなければ、FreeType の扱いを決め直す必要がある。
その代わり、壊れたフォントの扱いまでネイティブと同じになり、FreeType のソースも変えない。

cborg は、wasm だけリリースされていない上流のコミットを使う。
ネイティブと wasm で cborg の中身が違うが、PDF の組版の道は cborg を使わないので、比べには現れない。
上流が新しい版をリリースしたら、ネイティブと wasm を同じ版にそろえる ADR を作れる。

`skylighting` の差分は、Golem が持ち続けることになる。
`skylighting` を上げるたびに、差分を当て直し、`fetch-wasm-packages.sh` の SHA-256 を書き換える。
差分はモジュールとエクスポートと依存を除くだけなので、当て直しは小さいと見込める。
GPL-2.0 の `skylighting` を変えたものを wasm の配布物に入れるので、変えた部分のソースを示す必要がある。
差分のファイルをリポジトリと `THIRD_PARTY_LICENSES/` に置くことで示すが、これで GPL-2.0 の義務を満たすかは、法的には確かめていない。

文書 ID のために SHA-1 を実装すると、テストの対象が増える。
`uuid` との一致を性質のテストで確かめるので、出力が変わればテストが落ちる。
その代わり、golem-pdf が `uuid` と、その先の `entropy`、`network-info`、`random`、`cryptohash-md5`、`cryptohash-sha1` に依存しなくなる。

wasm のジョブは、`alex` と `happy` のためにネイティブの GHC も用意するので、CI の時間が延びる。
どれだけ延びるかは、3 で測る。

## メンテナーが決めること

1. **FreeType の setjmp**：推奨は、wasm だけ `-mllvm -wasm-enable-sjlj` で組み、例外処理の提案を使うことである。FreeType のソースを変えず、壊れた `cmap` の扱いもネイティブと同じになる。
   - 退けた案の一つは、`__wasi__` のときに `ft_setjmp` を常に 0 を返すものにし、`ft_longjmp` で止める（trap する）ことである。正しいフォントでは同じ結果になるが、壊れた `cmap` を持つフォントで、ネイティブは組み、wasm は diagnostics を返さずに止まる。diagnostics も決定性の対象とする [docs/adr/0071](0071-determinism-check-compares-diagnostics.md) に合わない。
   - もう一つは、`ttcmap.c` の検証を、longjmp を使わない形に書き換えることである。FreeType を上げるたびに当て直すことになる。
   - もう一つは、`cmap` の検証をやめることである。壊れたフォントで、ネイティブと違うグリフを選ぶ。
2. **cborg**：推奨は、wasm だけ上流の GitHub のコミット `6ef2791c` を使うことである。32 ビットの修正は上流のものであり、Golem の側で差分を持たない。
   - 退けた案の一つは、`Golem.Doc.Cbor` を golem-doc から新しいパッケージに出し、wasm が cborg に依存しないようにすることである。依存の向きはきれいになるが、[ADR 0173](0173-rc4-refactoring.md) が決めた「意味論 IR とプラグインの ABI」の分け方を変え、golem-plugin、golem-cli、golem-doc-gen のテストの依存が変わる。
   - もう一つは、golem-doc に cabal のフラグを足し、wasm では `Golem.Doc.Cbor` を外すことである。フラグでエクスポートするモジュールが変わり、外した版は wasm のジョブでしか組まれない。
   - もう一つは、cborg 0.2.10.0 に 32 ビットの差分を Golem の側で当てることである。上流にすでにある修正を写すことになる。
3. **uuid**：推奨は、golem-pdf で SHA-1 と UUID version 5 を実装し、`uuid` を除くことである。使うのは関数一つで、RFC 9562 と FIPS 180-4 に決まった手順があり、SHA-256 を自前で持つ前例もある。
   - 退けた案の一つは、`entropy` と `network-info` に差分を当てることである。golem-pdf が使わない乱数とネットワークの情報のために、二つのパッケージの差分を持つことになる。
   - もう一つは、`uuid-types` と `cryptohash-sha1` で作ることである。`cryptohash-sha1` は C のコードを持ち、wasm で組めるかを確かめていない。
4. **skylighting**：推奨は、wasm だけ、Hackage の `skylighting-core` と `skylighting` に、XML を読むモジュールを除く差分を当てることである。Golem が使う関数は変わらず、`xml-conduit`、`conduit-extra`、`streaming-commons`、`network` が wasm のビルドから消える。
   - 退けた案の一つは、`conduit-extra` と `streaming-commons` に、`network` を使うモジュールを除く差分を当てることである。差分の数は同じで、wasm に組み込むものが多く残る。
   - もう一つは、`network` に WASI の差分を当てることである（「実装しないこと」）。
   - もう一つは、ネイティブも差分を当てた `skylighting` を使うことである。ネイティブと wasm で同じソースになるが、ネイティブのビルドと開発の手順が差分のスクリプトに依るようになる。
5. **alex と happy**：推奨は、wasm のジョブでネイティブの GHC で組み、`PATH` に置くことである。手元で確かめた方法で、`toml-parser` に差分を当てずに済む。
   - 退けた案は、`toml-parser` の生成済みの字句解析器と構文解析器を差分として持つことである。`toml-parser` を上げるたびに作り直すことになる。
6. **もう一度確かめる場所**：推奨は、GitHub Actions の `ubuntu-24.04` のランナーで、作業用のブランチの一時的なワークフローとして走らせ、ワークフローはマージしないことである。[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md) が決めた x86-64 の Linux の配布物で、エミュレーションなしに確かめられる。
   - 退けた案の一つは、手元の Docker（`--platform linux/amd64`）で走らせることである。手元は aarch64 の macOS なので、x86-64 のエミュレーションになり、GHC と依存のすべてを組むのに時間がかかる。
   - もう一つは、手元で aarch64-darwin の配布物のまま確かめることである。[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md) が CI で使う配布物と違う。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-07、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md)、[ADR 0173](0173-rc4-refactoring.md)、[docs/adr/0002](0002-determinism.md)、[docs/adr/0007](0007-third-party-licenses.md)、[docs/adr/0071](0071-determinism-check-compares-diagnostics.md)
- RFC 9562, Universally Unique IDentifiers (UUIDs), 5.5 節と付録 A.4. https://www.rfc-editor.org/rfc/rfc9562
- FIPS 180-4, Secure Hash Standard (SHS). https://csrc.nist.gov/pubs/fips/180-4/upd1/final
- cborg の上流のリポジトリ（コミット `6ef2791ca41b397a3e36c868ad3e66a0d09f19b2`、`ecc1360dcf9e9ee27d08de5206b844e075c88ca4`、`2634c110fe360fc03e2f9b5f5a0dc5aa1a971edb`）。https://github.com/well-typed/cborg
- skylighting 0.15 と skylighting-core 0.15 の Hackage のソース（`Skylighting.hs`、`Skylighting/Core.hs`、`Skylighting/Parser.hs`、`Skylighting/Loader.hs`、`skylighting-core.cabal`）。https://hackage.haskell.org/package/skylighting-core-0.15
- network の上流のリポジトリ（コミット `1f6aa85`）。https://github.com/haskell/network
- streaming-commons 0.2.3.1 の `streaming-commons.cabal`。https://github.com/fpco/streaming-commons
- wasi-sdk の wasi-libc の `setjmp.h`（ghc-wasm-meta `8079eb96` の 9.10 の flavour の配布物に含まれるもの）。
- 確かめたときの記録：ビルドのログ（`build1.log`、`build2.log`）と cabal の各パッケージのログ。コミットしていない。
