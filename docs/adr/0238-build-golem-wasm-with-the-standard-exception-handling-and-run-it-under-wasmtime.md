# ADR 0238: golem.wasm を標準化された例外処理（exnref）の形で作り、wasmtime でも確かめる

ステータス: 採択

## 文脈

### wasmtime で確かめていないこと

[ADR 0234](0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md) の 5 は、golem.wasm を `node:wasi`、Deno、wasmtime、Chromium と Safari の `browser_wasi_shim` の五つで動かし、ネイティブの golem と同じ PDF と diagnostics を出すことを確かめると決めた（その ADR の I5）。
実装のプルリクエスト（#712）は、wasmtime の部分（`run-wasmtime.sh` と `compare.sh --wasmtime`）を実装しなかった。
[docs/roadmap.md](../roadmap.md) の「wasmtime で golem.wasm を動かすこと」の項目が、その理由を二つ挙げている。
一つは、wasmtime 49.0.5 が golem.wasm をコンパイルできないことである。
もう一つは、golem.wasm がファイルを読まないので、プロジェクトのファイルを入力の枠にしてメモリに書くホストが要ることである。
メンテナーは、golem.wasm を新しい形の例外処理で作り直し、wasmtime で動かすと決めた。
この ADR は、その作り方と、wasmtime のホストと、確かめ方を決める。

以下の観察は、`main` の `c409d5ea`（#712 のマージ）と、その CI の実行 42482957055 の成果物 `golem-wasm` の golem.wasm（SHA-256 `5f6b692b…0e8e20`）で行った（2026-11-08、aarch64 の macOS 27.0）。

### 古い形の例外処理が入る場所

golem.wasm が使う例外処理は、Haskell の側ではなく FreeType の側から入る。
golem-font の cabal は、wasm32-wasi のときだけ C に `-mllvm -wasm-enable-sjlj` を付け、wasi-sdk の `libsetjmp` をリンクする（[`golem-font.cabal`](https://github.com/tett23/golem/blob/c409d5ea29b2400976ebb1c9251bfef65f7eb844/modules/golem-font/golem-font.cabal#L69-L78)）。
FreeType は `setjmp.h` を読み、wasi-sdk はそれを wasm の例外処理で `setjmp` と `longjmp` を実装する道でしか受け付けないためである（[ADR 0202](0202-packages-that-do-not-build-for-wasm.md)）。
golem-font が組む FreeType のうち、`ft_setjmp` を呼ぶのは、cmap の部分表を検証する `tt_face_build_cmaps` だけである（[`ttcmap.c`](https://github.com/tett23/golem/blob/c409d5ea29b2400976ebb1c9251bfef65f7eb844/modules/golem-font/cbits/freetype/src/sfnt/ttcmap.c#L3838-L3847)）。
ほかに呼ぶ `gxvalid` と `otvalid` は組まず、`pngshim.c` の呼び出しは `FT_CONFIG_OPTION_USE_PNG` を定義しないので外れる。
検証が部分表を壊れていると判じると `longjmp` で戻り、FreeType はその部分表を捨てて読み進める。

`wasm-tools print`（1.263.0）で golem.wasm の命令を数えると、例外処理の命令は次のとおりだった。

| 命令 | 数 | 関数 | 形 |
| --- | --- | --- | --- |
| `try` | 2 | `tt_face_build_cmaps` | 古い形だけ |
| `catch` | 1 | `tt_face_build_cmaps` | 古い形だけ |
| `delegate` | 1 | `tt_face_build_cmaps` | 古い形だけ |
| `throw` | 1 | `__wasm_longjmp`（`libsetjmp`） | 両方の形にある |

古い形の命令は、155066 の関数のうち一つにしかない。
`throw` は二つの形に共通の命令であり、`libsetjmp` はそのまま使える。
`producers` の節によれば、C をコンパイルしたのは ghc-wasm-meta の wasi-sdk の fork の clang 21.1.8 である（wasi-sdk 29.0 を元にしたもの、[`fetch-ghc-wasm.sh`](https://github.com/tett23/golem/blob/c409d5ea29b2400976ebb1c9251bfef65f7eb844/scripts/fetch-ghc-wasm.sh)）。
LLVM の `-wasm-use-legacy-eh` の選択肢の既定は真であり、例外処理を有効にすると古い形を出す（LLVM の PR #122158）。

### wasmtime が読む形

wasmtime は、標準化された例外処理（exnref の形）だけを実装している。
37.0.0 で実装し、47.0.0 で既定で有効にした（それぞれのリリースノート）。
古い形は実装していない。

手元で wasmtime 49.0.5 の CLI（公式のリリースの aarch64-macos のアーカイブを SHA-256 で確かめたもの）を使うと、次のようになった。

- 今の golem.wasm の `wasmtime compile` は、`-W exceptions=y` を付けても「legacy_exceptions feature required for try instruction」で失敗する。
- exnref の形の golem.wasm（次の節で作ったもの）は、何も付けずにコンパイルできる。`-W exceptions=n` を付けると「exceptions proposal not enabled」で失敗する。つまり 49.0.5 では、新しい形の例外処理が既定で有効である。

### 新しい形を出す二つの道

一つめは、clang に `-mllvm -wasm-use-legacy-eh=false` を足すことである。
ghc-wasm-meta の同じリリース（`20251219T213239`）の aarch64-darwin の wasi-sdk（autogen.json の SRI の値で確かめたもの）で、FreeType の `sfnt.c` を golem-font と同じ選択肢でコンパイルし、二つを比べた。

| 選択肢 | 例外処理の命令 |
| --- | --- |
| `-mllvm -wasm-enable-sjlj` | `try` 2、`catch` 1、`delegate` 1 |
| それに `-mllvm -wasm-use-legacy-eh=false` を足す | `try_table` 2、`throw_ref` 1 |

FreeType のすべての C のファイルを同じ二通りでコンパイルし、フォントを `FT_New_Memory_Face` で開いて `num_charmaps` を出す小さな WASI のプログラムを、`libsetjmp` とリンクして作った。
新しい形のプログラムは、wasmtime 49.0.5、Node 26.11.1、Deno 2.9.7 のどれでも動き、どれも同じ値を出した。
古い形のプログラムは、wasmtime で動かなかった。
大きさの差は 22 バイトだった（466879 バイトと 466901 バイト）。

二つめは、リンクした後の golem.wasm を binaryen の `wasm-opt --translate-to-exnref` で書き換えることである。
binaryen version_133（ghc-wasm-meta の autogen.json が挙げる版、公式のリリースを SHA-256 で確かめたもの）で今の golem.wasm を書き換えると、古い形の命令はなくなり、`try_table` 2、`throw_ref` 1、`throw` 1 になった。
書き換えは関数の本体のすべてを書き直す。
コードの節は 28254126 バイトから 18957206 バイトに縮み、`name` の節はなくなった（`-g` を付ければ残る）。
`--all-features` を付けると、ブラウザも wasmtime も読まない新しい提案（import の節の詰めた書き方）で書かれた。
付けなければ、モジュールの `target_features` の節の機能だけを使う。

### 書き換えた golem.wasm で、PDF が変わらないこと

binaryen で書き換えた golem.wasm（`-g` なし）を、次の環境で動かした。

| 環境 | 結果 |
| --- | --- |
| Node 26.11.1 の `node:wasi`（`compare.sh`） | 七つの入力のすべてで、一覧が CI のネイティブの一覧（`wasm-native-list`）と同じ |
| Deno 2.9.7 の `node:wasi`（`compare.sh --deno`） | 同じ |
| wasmtime 49.0.5 の C API（手で書いた小さなホスト） | kanikosen の PDF の SHA-256 がネイティブと同じ |
| macOS 27.0 の JavaScriptCore（`jsc`）と `browser_wasi_shim` 0.4.2 | kanikosen の PDF の SHA-256 がネイティブと同じ |

`compare.sh` の時間は、書き換えの前が 21 秒、後が 20 秒だった。
wasmtime の C API で golem.wasm をコンパイルするのには、手元で 12 秒ほど（CPU の時間で 46 秒ほど）かかった。

Chromium（Chrome for Testing 157）と、CI の Safari 27.2 では動かしていない。
webassembly.org の機能の表（`features.json`、2026-11-02 のコミット `128c3812`）によれば、exnref の形に対応したのは Chrome 137、Firefox 131、Safari 18.4、Node 24.15、Deno 2.3.2、wasmtime 47 である。
CI の版（Chrome for Testing 157、Safari 27.2、Node の LTS、Deno 2.9.8、wasmtime 49.0.5）は、どれもこの版より新しい。
古い形には、Chrome 95、Firefox 100、Safari 15.2、Node 17.0、Deno 1.16 から対応している。

### `longjmp` の道は、今の比べ合わせで通らない

今の `compare.sh` の入力のフォントには、壊れた cmap の部分表がない。
そのため、`tt_face_build_cmaps` の `longjmp` は一度も起きず、例外を投げて受ける道は確かめられていない。
書き換えた golem.wasm の `__wasm_longjmp` の先頭に、呼ばれた数を数える import を足して確かめると、kanikosen では 0 回だった。

kanikosen の NotoSerifJP-Regular.otf の、Macintosh の format 6 の部分表の `entryCount`（ファイルの先頭から 30205 バイトめからの 2 バイト、元は `00 01`）を `FF FF` にすると、FreeType の検証がこの部分表を退ける。
このフォントで、次のことを観察した。

- 数える import を足した golem.wasm は、Node と wasmtime の C API のどちらでも、`longjmp` が 2 回起きて、例外を受けて組み終えた。
- FreeType だけのプログラムの `num_charmaps` は、6 から 5 に減った。
- golem は PDF を出さず、G08009（圏点の形の字がない）で終わった。HarfBuzz が cmap の表の全体を退けるためと見られる（HarfBuzz の中は確かめていない）。今の golem.wasm（古い形）を Node で動かしても、手元のネイティブの golem 0.1.0-rc3 でも、同じ diagnostics の符号の並びになった。

format 4 の部分表の `segCountX2` を `FF FE` にしたフォントでも、`longjmp` は 4 回起き、同じく G08009 で終わり、FreeType の `num_charmaps` は 6 から 4 になった。

### wasmtime のホスト

golem.wasm は、前もって開くディレクトリを要らず、ファイルを読まない（[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md)）。
wasmtime の CLI は、エクスポートの関数を `--invoke` で呼べるが、メモリにバイト列を書いて渡す手段がない。
[ADR 0234](0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md) の 5 が書いた「CLI の `--dir` でプロジェクトを渡して動かす」は、そのままでは成り立たない。

Golem は、golem-plugin のために wasmtime 49.0.5 の C API をすでに `scripts/fetch-wasmtime.sh` で版と SHA-256 を固定して取っている（[ADR 0156](0156-wasmtime-49-0-5.md)）。
その C API に WASI の preview 1 の実装も入っている。
手元で 80 行ほどの C のホストを書き、入力の枠のファイルを読んで `_initialize`、`hs_init(0, 0)`、`golem_alloc`、`golem_build_pdf`、`golem_result_len` を呼び、結果の枠を書き出すと、上の表のとおり動いた。

## 実装すること

### 1. golem.wasm を新しい形で作る

golem-font の cabal の `if os(wasi)` の `cc-options` に、`-mllvm -wasm-use-legacy-eh=false` を足す（「メンテナーが決めること」の 1）。
`-mllvm -wasm-enable-sjlj` と `libsetjmp` はそのまま残す。
注記に、新しい形を選ぶ理由とこの ADR を書く。
ネイティブのビルドは変わらない。
`scripts/fetch-ghc-wasm.sh` と、`cabal.project.wasm` と、その freeze は変えない。

### 2. 古い形の命令がないことの検査

`scripts/wasm/legacy-eh.sh` を足す。
引数の wasm のモジュールを Node で二度検証し、既定の Node では正しく、`--no-experimental-wasm-legacy-eh` を付けた Node では正しくないとき、古い形の命令があると報告して 1 で終わる。
既定の Node でも正しくないモジュールは、古い形の有無と別の誤りとして 2 で終わる。
`ci.yml` の `wasm` ジョブで、golem.wasm を作った直後にこれを走らせる（「メンテナーが決めること」の 5）。
V8 のこの選択肢の名前は、Node の LTS を上げるプルリクエストで確かめる。

### 3. `longjmp` の道を通る入力

`compare.sh` の入力に `broken-cmap` を足す。
kanikosen を写し、NotoSerifJP-Regular.otf の SHA-256 が `2c9a12db…4b2f04` であることを確かめてから、30205 バイトめからの 2 バイトを `dd` で `FF FF` にする。
SHA-256 が違えば、`compare.sh` は失敗する（フォントを替えたときに、壊す場所がずれたことに気づくため）。
この入力は、今の観察では PDF を出さずに G08009 で終わる。
終わり方は、ネイティブの一覧と同じであればよく、この ADR は決めない（「メンテナーが決めること」の 4）。

golem-font のテストに、この壊れたフォントを FreeType で開くと `num_charmaps` が元のフォントより一つ少ないことを確かめるテストを足す。
テストの中で元のフォントのバイト列の 2 バイトを書き換えて作り、ファイルを増やさない。
`num_charmaps` を返す C の関数は、テストの `c-sources` に置き、golem-font のライブラリの API を増やさない。
このテストが、`broken-cmap` の入力で FreeType が `longjmp` を通ることの根拠になる。
wasm の版の FreeType はネイティブと同じソースで同じ検証をするので、同じ入力で同じ道を通る。

### 4. wasmtime のホスト

`scripts/wasm/run-wasmtime.c` と `scripts/wasm/run-wasmtime.sh` を足す（「メンテナーが決めること」の 2）。

- `run-wasmtime.c` は、wasmtime 49.0.5 の C API にリンクする。`compile WASM CWASM` で golem.wasm をコンパイルして直列化し、`call CWASM` で標準入力の入力の枠を golem.wasm に渡し、結果の枠を標準出力に書く。WASI には引数 `golem.wasm` だけを渡し、ディレクトリを一つも開かず、環境変数を渡さない。
- 入力の枠を作ることと、結果の枠を読むことは、`run.mjs` に `frame DIR`（入力の枠を標準出力に書く）と `result PDF`（標準入力の結果の枠から PDF を書き、diagnostics の JSON を標準エラーに書き、`build` と同じ終了コードで終わる）を足して、そこで行う。枠を読み書きする実装は、`run.mjs` の一つだけにする。比べのために、`run.mjs` に `call WASM` も足す（`run-wasmtime.c` の `call` と同じ入出力を `node:wasi` で行う）。
- `run-wasmtime.sh` は、`scripts/fetch-wasmtime.sh` の取った `third_party/wasmtime` の C API で `run-wasmtime.c` を `cc` でコンパイルし、golem.wasm を一度だけ `compile` して、入力ごとに `run.mjs frame`、`call`、`run.mjs result` をつなぐ。
- `compare.sh` に `--wasmtime WASM` を足し、今の一覧と同じ形の一覧を書く。

wasmtime の CLI は取らない。
[ADR 0234](0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md) の 5 の「wasmtime の CLI の `--dir` でプロジェクトを渡して動かす」と「Deno と wasmtime の CLI は、1 と同じく版と SHA-256 で取る」の wasmtime の部分は、この 4 に替わる。

### 5. 夜ごとのワークフロー

`browser.yml` の `chromium` のジョブで、`scripts/fetch-wasmtime.sh` を走らせ、`compare.sh --wasmtime` の一覧を、同じコミットのネイティブの一覧と `compare.sh --check` で比べる。
ジョブの要約の版の表に、wasmtime の版を足す。
`safari` のジョブでは走らせない（[ADR 0234](0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md) の「実装しないこと」のとおり）。
`timeout-minutes` は、実装のプルリクエストで `chromium` のジョブの時間を測り直して決める。

これで、[ADR 0234](0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md) の 5 の残りが実装される。
同じプルリクエストで、[ADR 0234](0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md) のステータスを採択にし、wasmtime の入口はこの ADR が決めたと書く。

### 6. 文書

- docs/roadmap.md から「wasmtime で golem.wasm を動かすこと」の項目を外す。
- README と `scripts/wasm/README` と docs/specifications.md の、「wasmtime 49.0.5 の CLI では動かない」の記述を、wasmtime 49.0.5 の C API のホストで確かめていることに改める。あわせて、golem.wasm が標準化された例外処理を使い、それに対応した版の実行環境を要ることを書く。対応した最初の版は、Chrome 137、Firefox 131、Safari 18.4、Node 24.15、Deno 2.3.2、wasmtime 47 である。
- docs/specifications.md の CI の節の `wasm` ジョブに、2 の検査を足す。
- [ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md) のステータスの行に、例外処理の形はこの ADR が決めたと書く。

## 実装しないこと

- **binaryen で書き換えること**：リンクした後の golem.wasm を `wasm-opt --translate-to-exnref` で書き換えない（「メンテナーが決めること」の 1）。
- **古い形の golem.wasm も配ること**：リリースに添える golem.wasm は、新しい形の一つだけにする（「メンテナーが決めること」の 3）。
- **wasmtime の CLI で動かすこと**：CLI はメモリにバイト列を書けない。プロジェクトを読む WASI のコマンドのモジュールを別に作り、golem.wasm とつなぐ道もあるが、二つのモジュールのメモリをまたいでバイト列を写す仕組みが要る。
- **例外処理を使わずに FreeType を組むこと**：`longjmp` を罠（trap）にする `setjmp` の代わりを置くと、壊れた cmap の部分表を持つフォントで、ネイティブは読み進めるのに wasm は止まる。ネイティブと同じ PDF と diagnostics を出すという [ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md) の約束を破る。
- **ghc-wasm-meta の版を上げること**：今の版の clang 21.1.8 で新しい形を出せる。
- **HarfBuzz と GHC の生成するコード**：HarfBuzz は `-fno-exceptions` でコンパイルしており、GHC の wasm のコードは例外処理の命令を使わない。どちらも変えない。
- **Safari で wasmtime を走らせること**：[ADR 0234](0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md) と同じく、wasmtime は Linux の一か所で確かめる。

## 不変条件

| 番号 | 不変条件 |
| --- | --- |
| I1 | CI が作る golem.wasm は、古い形の例外処理の命令（`try`、`catch`、`catch_all`、`delegate`、`rethrow`）を一つも含まない。述語：`legacy-eh.sh golem.wasm` が 0 で終わる。 |
| I2 | `compare.sh` の入力のすべてで、golem.wasm の一覧は、`node:wasi`、Deno、wasmtime の C API、Chromium の `browser_wasi_shim`、Safari の `browser_wasi_shim` のどれで作っても、ネイティブの golem の一覧と同じである。 |
| I3 | `compare.sh` の入力には、FreeType の cmap の検証が `longjmp` で部分表を退けるフォントを持つものが少なくとも一つある。述語：golem-font のテストで、その入力のフォントの `num_charmaps` が、壊す前のフォントの `num_charmaps` より一つ少ない。 |
| I4 | 1 の変更は、ネイティブの出力を変えない。述語：実装のプルリクエストの `wasm-native-list` の、変更の前からある七つの入力の行が、`main` の `c409d5ea` の一覧と同じである（その間にネイティブの出力を変えたプルリクエストがあれば、その後の `main` の一覧と比べる）。 |
| I5 | 同じ入力の枠に、`run-wasmtime.c` の `call` と `run.mjs` の `call` は、同じバイト列の結果の枠を返す。 |

境界の入力は次のとおりである。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| 例外処理の命令を一つも持たない小さなモジュール | `legacy-eh.sh` は 0 で終わる | I1 |
| `try` を一つだけ持つ小さなモジュール | 1 で終わる | I1 |
| `try_table` と `throw_ref` だけを持つ小さなモジュール | 0 で終わる | I1 |
| `throw` だけを持つ小さなモジュール | 0 で終わる | I1 |
| 既定の Node でも正しくないバイト列 | 2 で終わる | I1 |
| `c409d5ea` の CI の golem.wasm | 1 で終わる（観察済み） | I1 |
| 壊れた部分表を持たないフォント（kanikosen） | 一覧はネイティブと同じ、`longjmp` は起きない | I2 |
| Unicode でない部分表が一つだけ壊れたフォント（`broken-cmap`） | `num_charmaps` は 6 から 5 になり、一覧はネイティブと同じ | I2、I3 |
| 二つの Unicode の記録が指す部分表が壊れたフォント（format 4 の `segCountX2` を `FF FE`） | `num_charmaps` は 6 から 4 になる（観察済み） | I3 |
| 正規化されていないパスの入力の枠 | 二つの `call` とも状態 1 で、同じバイト列 | I5 |
| ファイルが一つもない入力の枠 | 二つの `call` は同じバイト列 | I5 |

## テスト設計

次のテストを先に書き、今の `main` で失敗させてから実装する。
テストの名前には、不変条件の番号を入れる。

- I1：`scripts/ci/test.sh` に、上の表の五つの小さなモジュールをバイト列で書き、`legacy-eh.sh` の終了コードを確かめるテストを足す。プルリクエストの CI で走る。`c409d5ea` の golem.wasm で 1 になることは、実装のプルリクエストの最初のコミットで `wasm` ジョブに 2 を入れて確かめる（1 の前なので失敗する）。
- I3：golem-font のテストに、kanikosen のフォントとその壊したバイト列の `num_charmaps` を比べるテストを足す。ネイティブで走る。format 4 の場合も同じテストに入れる。
- I2：`compare.sh` に `broken-cmap` を足し、`ci.yml` の `wasm` ジョブ（`node:wasi`）と `browser.yml`（Deno、Chromium、Safari）で比べる。wasmtime は 5 で足す。`compare.sh` の引数の誤りと、フォントの SHA-256 が違うときに失敗することを、`scripts/ci/test.sh` に足す。
- I4：実装のプルリクエストの `wasm-native-list` を、`c409d5ea` の一覧と手で比べ、結果をプルリクエストに書く。自動のテストにはしない。ネイティブの出力を変えないことは、`if os(wasi)` の枝だけを変えることで構造的に決まり、比べ合わせはその確認である。
- I5：`browser.yml` の `chromium` のジョブで、上の表の二つの入力の枠と kanikosen の入力の枠を、二つの `call` に渡して `cmp` で比べる。

## トレードオフ

古い実行環境は、新しい golem.wasm を動かせなくなる。
Safari 15.2 から 18.3、Chrome 95 から 136、Firefox 100 から 130 は古い形にしか対応しておらず、golem.wasm のコンパイルで失敗する。
golem.wasm を使うページ（tett23/tett23 の [ADR 0005](0005-character-and-paragraph-styles.md)）を開く人のブラウザが古ければ、組めない。
Safari 18.4 と Chrome 137 は、どちらも 2025 年の前半に出ており、この ADR の時点で一年半ほど経つ。

`-mllvm -wasm-use-legacy-eh=false` は、clang の公開の選択肢ではなく、LLVM の内部の選択肢である。
LLVM 20 で `-wasm-enable-exnref` から名前を変えたことがある（PR #122158）。
ghc-wasm-meta を上げたときに名前が消えれば、clang が知らない選択肢として誤りを出し、ビルドが止まる。
既定が偽に変わったときは、この選択肢は何もしなくなるだけで害はない。
既定が戻ることはないと見込むが、戻っても I1 の検査が止める。

決定性について、PDF と diagnostics は変わらない見込みである。
例外処理の形は `longjmp` の道のコードを変えるだけで、FreeType の検証の結果も、それを使う組版も変えない。
binaryen で書き換えた golem.wasm では、七つの入力の一覧がネイティブと同じだった。
clang で作り直した golem.wasm の全体では確かめておらず、I2 と I4 が実装のプルリクエストで確かめる。
golem.wasm のバイト列は変わるので、リリースの golem.wasm の SHA-256 は前の版と違う。

[ADR 0219](0219-frequency-of-the-wasm-job-and-its-uncached-runs.md) のキャッシュのない実行は、この ADR では起きない。
`fetch-ghc-wasm.sh` も `cabal.project.wasm` も freeze も変えないので、ツールチェーンと cabal の store のキャッシュは当たる。
`dist-wasm` は `restore-keys` で戻り、golem-font とそれに依存するパッケージを組み直す。
golem-font を変えるほかのプルリクエストと同じ量である。
5 分を超えたかどうかを、実装のプルリクエストで測って書く。

大きさと速さは、ほとんど変わらない見込みである。
FreeType だけのプログラムでは 22 バイト増えた。
`compare.sh` の時間は、binaryen で書き換えた golem.wasm で 21 秒から 20 秒だった。

wasmtime のホストは、Golem で初めての C のスクリプトになる。
C の API は golem-plugin がすでに使っているもので、取るものは増えない。
代わりに、Cranelift で golem.wasm をコンパイルする時間（手元で 12 秒ほど）が、夜ごとの `chromium` のジョブに加わる。
入力ごとにコンパイルし直さないよう、4 で一度だけコンパイルして直列化する。

## メンテナーが決めること

1. **新しい形を出す方法**：推奨は、clang に `-mllvm -wasm-use-legacy-eh=false` を足すことである。変わるのは一つの関数のコードだけで、ツールチェーンも、後の工程も増えない。
   - 退けた案は、binaryen の `wasm-opt --translate-to-exnref` で書き換えることである。ghc-wasm-meta は binaryen version_133 も配っているので、`fetch-ghc-wasm.sh` に足すことはできる。しかし、書き換えは関数の本体のすべてを書き直し、golem.wasm の中身を binaryen の版に依存させる。`fetch-ghc-wasm.sh` が変わるので、[ADR 0219](0219-frequency-of-the-wasm-job-and-its-uncached-runs.md) のキャッシュのない実行も一度起きる。clang の選択肢が使えなくなったときの代わりとして残す。
2. **wasmtime のホスト**：推奨は、wasmtime 49.0.5 の C API にリンクする小さな C のホストである。`fetch-wasmtime.sh` がすでに取っている C API を使い、手元で動いた。
   - 退けた案の一つは、golem-plugin の wasmtime の束縛を使う Haskell のホストである。夜ごとのジョブでネイティブの GHC のビルドが要り、golem-* のパッケージの間の依存も増える。
   - 二つめは、wasmtime の CLI と、プロジェクトを読む WASI のコマンドのモジュールを組み合わせることである。二つのモジュールのメモリをまたいでバイト列を写す仕組みが要る。
3. **古い実行環境**：推奨は、新しい形の golem.wasm だけを配ることである。
   - 退けた案は、古い形の golem.wasm も添えることである。リリースの成果物と、比べ合わせの組が倍になる。
4. **`broken-cmap` の入力の終わり方**：推奨は、今の観察どおり G08009 で PDF を出さずに終わる入力として足すことである。比べるのは `longjmp` の道を通ることとネイティブとの一致であり、PDF ができることは要らない。
   - 退けた案は、FreeType は退けるが HarfBuzz は受け入れる壊し方を探し、PDF のできる入力にすることである。探す手間に比べ、確かめられることが増えない。
5. **古い形の命令の検査の置き場所**：推奨は、プルリクエストごとの `wasm` ジョブで、Node の V8 の選択肢を使うことである。取るものが増えず、夜を待たずに気づける。
   - 退けた案は、wasm-tools を版と SHA-256 で取り、命令を数えることである。正確だが、取るものが一つ増える。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-08、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [ADR 0156](0156-wasmtime-49-0-5.md)、[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md)、[ADR 0202](0202-packages-that-do-not-build-for-wasm.md)、[ADR 0219](0219-frequency-of-the-wasm-job-and-its-uncached-runs.md)、[ADR 0234](0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md)
- WebAssembly, Exception Handling（exnref の形）, https://github.com/WebAssembly/exception-handling/blob/master/proposals/exception-handling/Exceptions.md
- WebAssembly, Legacy Exception Handling, https://github.com/WebAssembly/exception-handling/blob/master/proposals/exception-handling/legacy/Exceptions.md
- webassembly.org, Feature Extensions（`features.json`、コミット `128c38126af305f53bc22b31c30aefa3f5efe824`）, https://webassembly.org/features/
- LLVM, PR #122158, WebAssembly: Add -wasm-use-legacy-eh option, https://github.com/llvm/llvm-project/pull/122158
- Bytecode Alliance, wasmtime 37.0.0、47.0.0、49.0.5 のリリースノート, https://github.com/bytecodealliance/wasmtime/releases
- Bytecode Alliance, wasm-tools 1.263.0, https://github.com/bytecodealliance/wasm-tools
- WebAssembly, binaryen version_133, https://github.com/WebAssembly/binaryen
- ghc-wasm-meta（コミット `8079eb96bbc63823d99ad8acaff0765532625474`）の `autogen.json`, https://gitlab.haskell.org/haskell-wasm/ghc-wasm-meta
- FreeType 2.14.3, `src/sfnt/ttcmap.c`
