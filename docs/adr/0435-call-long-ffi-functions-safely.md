# ADR 0435: 長くかかりうる FFI の呼び出しを safe で呼び、unsafe の呼び出しを一覧で管理する

Status: proposed

## 文脈

GHC の `unsafe` の FFI の呼び出しは、終わるまで capability を手放さない。
そのあいだに GC の同期が起きると、ほかのすべての capability が、その呼び出しが終わるまで待たされる。
短い呼び出しなら問題にならないが、長い呼び出しを `unsafe` で呼ぶと、ほかのスレッドがまとめて遅れる。

golem-plugin は、プラグインのコンパイル（`golem_plugin_load`）と、WAT から wasm への変換（`golem_wat2wasm`）を `unsafe` で呼んでいる。
どちらも wasmtime の中でコンパイルをするので、長くかかりうる。
2026-10-17 のテストが止まる件の調査で、このことが見つかった。
デッドロックにはならず、遅れるだけで、出力も変わらない。
golem-font にも、フォントを開く呼び出しとサブセットを作る呼び出しのように、入力の大きさに応じて長くかかりうる `unsafe` の呼び出しがある。
この ADR は、これらを `safe` で呼び、これから `unsafe` の呼び出しを足すときの決まりを決める。

## 調査した事項

origin/main（[9efdc4f89](https://github.com/tett23/golem/commit/9efdc4f89b3fec75abcd37c11abb3e1d909c6725)）で、次のことを確かめた。

- modules の Haskell のソースの `foreign import` は、どれも `safe` か `unsafe` を同じ行に書く。
  `unsafe` の行は 36 本で、golem-font の `Font.hs` に 24 本、golem-plugin の `Plugin.hs` に 7 本、golem-test-support の `Watchdog.hs` に 4 本、golem-test-support のテストの `Main.hs` に 1 本ある。
  そのうち 2 本（`Font.hs` の `"golem_font.h &golem_font_close"` と `Plugin.hs` の `"golem_plugin.h &golem_plugin_free"`）は、関数のアドレスを取る import で、呼び出しではない。
- 呼び出しの規約は、どれも `capi` か `ccall` で、安全さの語はその直後に書く。
  `scripts/ci/unsafe-io.sh` は、注釈と文字列を除く近似の字句解析で、ソースの `unsafePerformIO` などを数える（[root ADR 0069](0069-lint-scripts-bypassed-by-plain-rewrites.md)）。
- `golem_plugin_load` と `golem_wat2wasm` は `foreign import capi unsafe` である（[Plugin.hs#L87](https://github.com/tett23/golem/blob/9efdc4f89b3fec75abcd37c11abb3e1d909c6725/modules/golem-plugin/src/Golem/Plugin.hs#L87)、[Plugin.hs#L102](https://github.com/tett23/golem/blob/9efdc4f89b3fec75abcd37c11abb3e1d909c6725/modules/golem-plugin/src/Golem/Plugin.hs#L102)）。
  同じファイルのプラグインの関数の呼び出し（`golem_plugin_call`）は、すでに `safe` である。
- `golem_plugin_load` は、プラグインを読み込むごとに呼ぶ。
  C の側では、プラグインごとに新しい engine を作り、`wasmtime_module_new` で Cranelift のコンパイルをする。
  `golem_wat2wasm` は `wasmtime_wat2wasm` を呼び、それを包む `watToWasm` を使うのは、golem-plugin、golem-driver、golem-lsp のテストだけである。
  どちらも Haskell を呼び返さず、大域の状態を持たない。
  コードを読んでの判断で、実行して確かめてはいない。
- golem-font の `golem_font_open` は、フォントを `FT_New_Memory_Face` と `hb_blob_create` でメモリから開く（開発者向けのマニュアルの `12-purity.gm`）。
  `golem_font_subset` は、PDF に埋め込むフォントのサブセットを作る。
  どちらもフォントごとに呼び、語ごとには呼ばない。
  `golem_font_shape` は語ごとに呼ぶので、呼び出しの数が多い。
  これらにかかる時間は、計っていない。
- Haskell の側は、ByteString を `unsafeUseAsCStringLen` で、文字列を `withCStringLen` などで渡す。
  ByteString の領域は GC で動かないので、`safe` の呼び出しのあいだに GC が走っても、渡したメモリは動かない。
  これは、コードを読んでの判断である。
- golem-test-support の `Watchdog` の 4 本の `unsafe` の呼び出しは、表のロックを短く取るだけである（[root ADR 0117](0117-watchdog-outside-the-runtime-for-threaded-tests.md)）。
  見張りは C のスレッドで動き、capability を取らない。
  同じパッケージのテストの `sleep(3)` は、非 threaded のランタイムの唯一の OS のスレッドを止めるために、わざと `unsafe` で呼ぶ。
- 実行ファイル `golem` は `-threaded -N` で動き、LSP もこの実行ファイルの中で動く。
- golem-plugin は wasm32 のビルドから外れている。
- リポジトリが使う GHC は 9.10.3 である（`cabal.project` の `with-compiler`）。

指示者は 2026-11-23 に、この ADR を書くよう求めた。

## 実装すること

### safe にする呼び出し

次の四つを `foreign import capi safe` にする。

- golem-plugin の `golem_plugin_load` と `golem_wat2wasm`
- golem-font の `golem_font_open` と `golem_font_subset`

呼び方と、渡す値と、返る値は変えない。
golem-font の二つは、フォントごとにしか呼ばないので、`safe` の呼び出しの費用は無視できる。
長さを計らずに `safe` にするのは、次の節の決まりで、長さが入力によらず短いと言えない呼び出しは `safe` にするからである。

### unsafe にしてよい呼び出し

`unsafe` にしてよいのは、次の三つのどれかに当たる呼び出しだけとする。

1. 呼び出しの時間が入力の大きさによらず短く、ロックを待たない呼び出し（値の読み出し、領域の解放など）。
2. 呼び出しの数が多く、`safe` の呼び出しの費用が無視できないので、理由を書いて `unsafe` のまま残す呼び出し。
3. capability を手放さないことそのものが目的の呼び出し（golem-test-support のテストの `sleep`）。

`Watchdog` の 4 本は、一つめの理由に当たる。

golem-font の `golem_font_shape` は、二つめの理由で、今は `unsafe` のまま残す。
`safe` にするかは、時間を計ってから別の ADR で決める。

### unsafe の一覧

リポジトリの `unsafe` の FFI の呼び出しを、一覧のファイル `scripts/ci/unsafe-ffi.tsv` に書く。
一行に、モジュールのパス、C の関数の名前、上の三つの理由の番号、理由の文を、タブで区切って書く。

`scripts/ci/test.sh` に、次の検査を足す。

- 検査は、modules の下の `.hs` のファイルを、`scripts/ci/unsafe-io.sh` と同じ近似の字句解析で注釈を除いて読み、`foreign import` の宣言を探す。
- 宣言の `foreign import` の次の語（呼び出しの規約、`capi` か `ccall`）の、さらに次の語を安全さの語とする。
  それが `safe` でも `unsafe` でもなければ、検査を落とす。
  安全さの指定を省いた呼び出しは、GHC の既定で `safe` になるが、一覧の検査をすり抜けないように、どちらかを書かせる。
- 安全さの語が `unsafe` の宣言について、その後の引用符の中の文字列の最後の語を、C の関数の名前とする（`"golem_font.h golem_font_shape"` なら `golem_font_shape`）。
  最後の語が `&` で始まる宣言（関数のアドレスを取るだけの import）は、呼び出しではないので数えない。
- ソースから得た（モジュールのパス、C の関数の名前）の集合と、一覧の行の集合が等しくなければ、検査を落とし、足りない行と余る行を一つずつ出す。

### 文書

開発者向けのマニュアルの `12-purity.gm` の「C のライブラリを純粋な関数として包む」の節に、`safe` と `unsafe` の違いと、`unsafe` にしてよい三つの理由と、一覧の決まりを書く。
ロードマップの「時間のかかる `unsafe` の FFI の呼び出し」の項目を消す。

## 実装しないこと

`golem_font_shape` と、一つめと三つめの理由の呼び出しを `safe` にしない。
C の側（`cbits`）は変えない。
プラグインを並べて読み込むようにはしない。
時間を計る検査を CI に足さない。

## 不変条件

- I1: `golem_plugin_load`、`golem_wat2wasm`、`golem_font_open`、`golem_font_subset` の foreign import は `safe` である。
- I2: modules の Haskell のソースの `unsafe` の foreign import の（モジュールのパス、C の関数の名前）の集合は、`scripts/ci/unsafe-ffi.tsv` の行の集合と等しい。
- I3: modules の Haskell のソースのどの `foreign import` の行も、`safe` か `unsafe` を含む。
- I4: プラグインを使う本の出力と diagnostic は、この ADR の前と等しい。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| 今のソース | 四つが `safe` で、ほかの `unsafe` がすべて一覧にある | I1, I2, I3 |
| 一覧に無い `unsafe` の import を足した試験のソース | 検査が落ち、足りない行を出す | I2 |
| ソースに無い行を持つ試験の一覧 | 検査が落ち、余る行を出す | I2 |
| 空の一覧と、`unsafe` の無い試験のソース | 検査が通る | I2 |
| 最後の語が `&` で始まる `unsafe` の import だけを持つ試験のソース | 一覧が空で検査が通る | I2 |
| 注釈の中にだけ `foreign import ... unsafe` がある試験のソース | 数えず、検査が通る | I2 |
| 名前に `unsafe` を含む `safe` の import | `unsafe` に数えない | I2 |
| `safe` も `unsafe` も書かない import を持つ試験のソース | 検査が落ちる | I3 |
| プラグインを使う golem-plugin と golem-driver のテスト | 変わらず通る | I4 |

## 受けいれ条件

なし。
不変条件の検査で足りるためである。

## テスト設計

root ADR 0435 I1 から I3 を名前の先頭に置いた検査を、`scripts/ci/test.sh` に足す。
I2 と I3 は、試験のソースと一覧の組を作り、境界の表の各行を確かめる。
I1 と I2 は、実装の前に落ちることを確かめる。
I4 は、golem-plugin のテストと、golem-driver の `PluginsSpec` と、golem-font のテストが変わらず通ることで確かめる。

## トレードオフ

`safe` の呼び出しは `unsafe` より費用が大きいが、四つの呼び出しはどれもプラグインかフォントの数だけしか呼ばないので、無視できる。
その代わりに、プラグインのコンパイルやフォントのサブセットのあいだ、ほかのスレッド（LSP の応答、並べて組むページ）が GC の同期で止まらない。

遅れを直に計るテストは、ランナーによって結果がぶれるので足さない。
ソースの検査で、`unsafe` の呼び出しが気付かずに増えることを防ぐ。

## 参考文献

- [root ADR 0069](0069-lint-scripts-bypassed-by-plain-rewrites.md)
- [root ADR 0117](0117-watchdog-outside-the-runtime-for-threaded-tests.md)
- [GHC 9.10.3 User's Guide, Foreign function interface](https://downloads.haskell.org/ghc/9.10.3/docs/users_guide/exts/ffi.html)
