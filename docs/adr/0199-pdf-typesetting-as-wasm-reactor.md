# ADR 0199: PDF の組版をファイルを読まない wasm の reactor モジュールにして配る

ステータス: 採択→組めなかったパッケージの扱いは [ADR 0202](0202-packages-that-do-not-build-for-wasm.md)、golem_result_len の長さの接頭辞、wasm ジョブの待ち方、GMP の版の調べ方は [ADR 0211](0211-record-what-implementations-decided-found-by-the-review-of-2026-11-08.md)

## 文脈

### 求められていること

tett23/tett23 の [ADR 0005](https://github.com/tett23/tett23/blob/79a0e603603b9644ab8129cd750a6e82d80e7e22/.github/docs/adr/0005-golem-page.md)（Golem のページとプレイグラウンド。以下、ページの ADR）は、ブラウザの Worker の中で原稿を Golem で組み、shem でラスタライズしてプレビューするページを作ると決めた。
その「前提となる Golem と shem 側の変更」の節が、Golem に次の四つを求めている。

- プラグインの機能（golem-plugin、wasmtime）を外すビルドのフラグを足す。
- FreeType と HarfBuzz を wasi-sdk でビルドし、GHC の wasm バックエンドで、PDF を組む部分を reactor モジュールにする。並列の処理は、順に組む道を使う。
- ファイルを読まない入口をエクスポートする。原稿（`.gm`）、`style.toml`、フォントのバイト列を引数で受け取り、PDF のバイト列か、diagnostics（ファイル、行、列、メッセージ）を返す。
- その wasm を、リリースに添付する。

この ADR は、このうち Golem の側を決める。
shem の側（`wasm32-unknown-unknown` のビルドと、ページごとの画素を返す関数）と、ページそのものは扱わない。

以下の事実は、main の `e491d789`（[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) の一つめのプルリクエストを入れた後）で読んだものである（2026-11-07）。
[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) の二つめのプルリクエスト（golem-typeset を作るもの、#612）は、まだ下書きである。
そのため、PDF の組版のモジュールは今の名前（`Golem.Driver.Pdf` など）で書き、golem-typeset に移った後の名前を必要なところで添える。

### wasm で組むのを妨げるもの

ページの ADR は障害を五つ挙げた。
コードで確かめると、どれも事実であり、ほかに二つが加わる。

一つめは、プラグインである。
golem-driver のライブラリは golem-plugin に無条件で依存する（[`golem-driver.cabal`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-driver/golem-driver.cabal#L45-L76)）。
golem-plugin は、wasmtime 49.0.5 の C API を静的にリンクし、`http-client` と `http-client-tls` に依存する（[`golem-plugin.cabal`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-plugin/golem-plugin.cabal#L23-L52)）。
golem-driver の中で golem-plugin を取り込むのは、`Golem.Driver`（`HostContext`、`defaultCacheDir`）、`Golem.Driver.Plugins`、`Golem.Driver.Functions`（`maxDataBytes`）、`Golem.Driver.New`（`Fetcher`、`hashHex`）の四つのモジュールである。
評価の側の `PluginHook` と `noPlugins` は golem-eval にあり、golem-plugin には依存しない。

二つめは、FreeType と HarfBuzz である。
golem-font は、HarfBuzz 14.6.0 と FreeType 2.14.3 のソースを `cbits/` に同梱し、cabal の `c-sources` と `cxx-sources` でコンパイルする（[`golem-font.cabal`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-font/golem-font.cabal#L42-L72)）。
FMA を使わないよう `-ffp-contract=off` を付け、C++ は `-fno-exceptions -fno-rtti -fno-threadsafe-statics` でコンパイルする。
リンクする C++ の標準ライブラリは、macOS では `c++`、それ以外では `stdc++` である。
グルーの `golem_font.c` は、FreeType の呼び出しを `pthread_mutex_t` で守る（[`golem_font.c`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-font/cbits/golem/golem_font.c#L14-L69)）。
フォントは `FT_New_Memory_Face` と `hb_blob_create` でメモリから読み、ファイルを開かない。

三つめは、並列である。
golem-cli は `-threaded "-with-rtsopts=-N"` でリンクする（[`golem-cli.cabal`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-cli/golem-cli.cabal#L11-L16)）。
PDF の組版は、`piParallel` が真なら段落を `mapConcurrently` で、偽なら `mapM` で組む（[`Flow.hs`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L1990-L1996)）。
`BuildOptions` の既定は並列である（[`Driver.hs`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-driver/src/Golem/Driver.hs#L128-L129)）。
並列と順の出力が一致することは、golem-driver-parallel-test が確かめている。

四つめは、Template Haskell である。
使うのは、`Golem.Driver.Version`（`VERSION` を埋め込む）、`Golem.Driver.Explain`（`docs/diagnostics.md` を埋め込む）、golem-layout の `Golem.Layout.Hyphenation.EnUs`（hyph-utf8 のパターンを埋め込む）の三つである（[`EnUs.hs`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-layout/src/Golem/Layout/Hyphenation/EnUs.hs#L1-L40)、[`Version.hs`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-driver/src/Golem/Driver/Version.hs)、[`Explain.hs`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-driver/src/Golem/Driver/Explain.hs#L30-L41)）。
三つとも `runIO` でコンパイルのときにファイルを読む。
PDF の組版は英語のハイフネーションに `EnUs` を使うので、golem-typeset だけを wasm にしても、Template Haskell は一つ残る。

五つめは、ファイルである。
ビルドは、プロジェクトのフォルダーからファイルを読む。
読む箇所は、golem-project（`manifest.toml` と章と import のファイル、[`Project.hs`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-project/src/Golem/Project.hs#L90-L97)）、golem-driver の評価（`style.toml`、`plugins.lock`、`@table` などのアセット、書誌、関数、[`Driver.hs`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-driver/src/Golem/Driver.hs#L214-L254)）、PDF の組版（フォント、図版、出力インテントの ICC プロファイル）に散らばる。
パスの解決は `resolveInRoot` が一つで受け持ち、`canonicalizePath` でシンボリックリンクをたどってルートの外を指していないかを調べる（[`Paths.hs`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-project/src/Golem/Project/Paths.hs#L47-L62)）。
PDF の組版では、フォントの読み込みはすでに `FontProvider` という値で差し替えられる（[`Pdf/Fonts.hs`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-driver/src/Golem/Driver/Pdf/Fonts.hs#L160-L169)）が、その実装 `golemFontProvider` はディスクから読む（[`Fonts.hs`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-driver/src/Golem/Driver/Fonts.hs#L44-L55)）。
図版と ICC プロファイルは `BS.readFile` で直接読む（[`Flow.hs`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L2336-L2344)、[`Flow.hs`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L2472-L2480)）。

ページの ADR が障害として挙げなかったものの一つめは、入口の引数に `manifest.toml` がないことである。
ページの ADR も、プロジェクトが `manifest.toml` をファイルとして読むことは書いている。
`manifest.toml` がなければ、プロジェクトの読み込みは G03016 で止まる。
PDF のバイト列も `manifest.toml` に依存する。
インスタンス ID の入力の先頭は `manifest.toml` のテキストであり（[`Driver.hs`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-driver/src/Golem/Driver.hs#L1156-L1165)）、`[metadata]` の `id` は PDF の文書 ID に、`title` は文書の題になる（[`Draw.hs`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-driver/src/Golem/Driver/Pdf/Draw.hs#L208-L210)）。
`language` は、見出しや図版の番号の組み方を変える。
`[source]` の `paragraph-separator` は原稿の読み方を変え、書いていなければ notice の G03120 が出る。
ページの ADR の入口の引数（原稿、`style.toml`、フォント）では、PDF のバイト列を決める入力がそろわない。

もう一つは、Hackage のパッケージである。
golem-pdf は文書 ID を作るのに `uuid` の `Data.UUID.V5.generateNamed` だけを使う（[`Writer.hs`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L208)）。
手元の `dist-newstyle/cache/plan.json` を読むと、`uuid` は `entropy`、`network-info`、`random`、`cryptohash-md5`、`cryptohash-sha1` に依存する。
ghc-wasm-meta のテストのスクリプトには、`entropy` が独自の `Setup` を持つために依存を避けたと読める注記がある（`tests/agda-language-server.sh`、「lsp-2.8.0.0 -> websockets -> entropy, custom Setup」）。
`uuid` が wasm で組めるかは、確かめていない。
golem-html は `skylighting` に依存し、golem-pdf の zlib は `bundled-c-zlib` で C のソースからコンパイルされる。
この二つが wasm で組めるかも、確かめていない。

### GHC の wasm バックエンドについて確かめたこと

GHC 9.10.3 の User's Guide は、wasm バックエンドを「still a tech preview」とし、公式の配布物には入っていないとする。
導入には ghc-wasm-meta に従うよう書いている。
同じ文書が確かめられることは次のとおりである。

- reactor モジュールは `-no-hs-main -optl-mexec-model=reactor -optl-Wl,--export=...` で作り、ホストは `_initialize` を一度呼んでからほかのエクスポートを呼ぶ。
- RTS は single-threaded である。
- `foreign export javascript`（JSFFI）のエクスポートは常に非同期で、Promise を返す。

ghc-wasm-meta（`8079eb96`、2026-10-12）の README と配布物の一覧（`autogen.json`）からは、次のことを確かめた。

- `9.10` の flavour があり、ghc-wasm-meta の GHC の fork の `ghc-9.10` の枝を追う。bignum は `gmp` である。`native` の bignum の flavour は upstream の `master` を追うので、9.10 ではない。
- 配布物は GitHub の `haskell-wasm/ghc-wasm-bindists` のリリースにあり、`autogen.json` が URL と SHA-256（SRI の形）を持つ。9.10 の配布物は `20260731T193144` のリリースのものである。
- C と C++ のツールチェーンは、ghc-wasm-meta の wasi-sdk の fork を使う。README は「Upstream `wasi-sdk` won't work yet」と書く。
- `foreign export ccall` の関数と `hs_init` を `--export` で出す reactor の例があり、ホストの側で `malloc` と `free` を使ってバッファを受け渡せる。
- cabal は 3.14 以前を使うよう書いており、3.16 には致命的な退行があるとする。ghc-wasm-meta が配る cabal は 3.14.2.0 である。Golem のネイティブのビルドは cabal 3.16.1.0 を使う（`release.yml`）。
- `setup.sh` は、`9.10`、`9.12`、`9.14` の flavour のときに `cabal.th.config`（`shared: True`）を cabal の設定に写す。
- 実行できる環境に、wasmtime、Node（組み込みの `wasi`）、Deno、ブラウザ（`browser_wasi_shim`）を挙げる。

Template Haskell については、確かめきれていない。
GHC 9.14.1 の User's Guide は、Template Haskell の splice を node の `dyld` のスクリプトで評価すると書く。
9.10.3 と 9.12.1 の User's Guide の wasm の章は、Template Haskell に触れない。
ghc-wasm-meta が 9.10 の flavour にも Template Haskell 向けの cabal の設定を写すことから、fork の 9.10 の枝が対応している可能性はあるが、動かしてはいない。

`cabal` の条件の式は、`os(wasi)` と `arch(wasm32)` を書ける。
GHC 9.10.3 に付く Cabal-syntax 3.12.1.0 の `Distribution.System` に、`Wasi` と `Wasm32` がある。

### 決定性

[docs/adr/0002](0002-determinism.md) は、同じ入力からバイト単位で同じ出力を得ることを Golem の存在理由とし、入力を `manifest.toml`、`style.toml`、ソース、フォントなどと、Golem 自身の版に限る。
[docs/adr/0071](0071-determinism-check-compares-diagnostics.md) は、diagnostics も決定性の検査の対象とする。
wasm で組んだ PDF も、同じ入力からネイティブの `golem build` と同じバイト列にならなければ、ブラウザで「出力が同じバイト列になることを見た人の手元で確かめられる」というページの ADR の利点が成り立たない。
wasm の版は、C と C++ を別のコンパイラ（wasi-sdk の clang）で、Haskell を別の GHC（fork の 9.10）でコンパイルする。
レイアウトは整数の sp で計算し、HarfBuzz と FreeType は FMA を使わずにコンパイルするので、一致すると見込める。
見込みであって、確かめてはいない。

## 実装すること

### 方針

wasm の入口は、新しい組み立てを作らず、`golem build` と同じ `buildCore` を通す。
`buildCore` は、評価、notice、PDF の検査、`listNumberDiagnostics`、G08100 までを一つの手順に持つ。
これを wasm のために写すと、二つの道の diagnostics と出力がずれていく。
同じ手順を通せば、ずれるのはファイルの読み方とプラグインの有無だけになる。

そのために、二つのことをする。
ファイルの読み方を値にして、ディスクとメモリを差し替えられるようにする。
golem-driver に、golem-plugin を外すフラグを足す。

### 1. 最初に組めるかを確かめる

ほかの作業の前に、ghc-wasm-meta の 9.10 の flavour で、`golem-driver`（golem-plugin を外した版）の依存のすべてが組めるかを確かめる（「メンテナーが決めること」の 4）。
この段階では、main のコードを変えない。
手元の作業用のブランチで、golem-driver の cabal から golem-plugin とそれを使うモジュールを一時的に外して確かめ、その変更はコミットしない。

- 確かめるもの：`uuid`、`skylighting`、`zlib`、`toml-parser`、`peg-runtime` などの Hackage のパッケージ、Template Haskell の三つのモジュール、golem-font の C と C++、`foreign import capi`。
- 結果（組めたもの、組めなかったものとエラー、GHC と boot のパッケージの版、ビルドにかかった時間、wasm の大きさ）を、2 のプルリクエストの説明に書く。ビルドにかかった時間は `docs/ci-timings/` にも記録する。
- 組めないものがあれば、そこで止め、扱い方を新しい ADR で決める（「メンテナーが決めること」の 5）。この ADR の中で、パッケージを差し替えたり Template Haskell を外したりはしない。

### 2. ファイルの読み方を値にする

golem-project に、ファイルの読み方を表す値を足す。
型クラスではなく、関数を持つレコードにする。

```haskell
-- Golem.Project.Files（golem-project）
data Files = Files
  { -- | resolveInRoot と同じ規則でパスを解決する。結果はルートからの相対パス
    filesResolve :: FilePath -> IO (Either PathError FilePath),
    -- | 解決したパスのバイト列
    filesRead :: FilePath -> IO ByteString,
    -- | 解決したパスのバイト数（G02088 の判定に使う）
    filesSize :: FilePath -> IO Integer
  }

diskFiles :: FilePath -> Files                -- 今の振る舞い
memoryFiles :: Map FilePath ByteString -> Files
```

- `diskFiles root` は、今の `resolveInRoot root`、`BS.readFile (root </> rel)`、`getFileSize` をそのまま包む。
- `memoryFiles` は、`normalizeRelative` で正規化したパスを表のキーと比べる。ないパスは `Missing` である。シンボリックリンクはないので、`canonicalizePath` に当たる処理はない。表のキーは、正規化した相対パスで持つ。正規化していないキーを渡したときは、入口が diagnostic ではなくエラーの戻り値で断る（4）。
- 次の箇所の読み込みを、`Files` を通すように書き換える。書き込み（`build/` の掃除と書き出し）は書き換えない。
  - golem-project：`loadProjectWith` と `loadSources`（`manifest.toml`、章、import）。
  - golem-driver：`evaluateProjectWith`（`style.toml`、`plugins.lock`）、`loadAssets`、`loadBibliography`、`loadRequiredFiles`、`loadFunctions`、`functionRoots`、`buildCore` の `style.toml` の有無、`missingStyleFiles`、`cff2FontDiagnostics`、`activeContentDiagnostics`。
  - PDF の組版（[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) の後は golem-typeset）：`loadFigures`、`loadIntent`。`PdfInput` の `piRoot` を `piFiles :: Files` に置き換える。
  - `FontProvider` の `loadFonts` は、ルートの代わりに `Files` を受け取る。`golemFontProvider` は `Files` から読む。ディスクのときの振る舞いは変えない。
- `Files` を受け取る関数は、今の名前のまま `Files` を引数に足す。ディスクから読む今の呼び出しは、`diskFiles root` を渡す。`BuildOptions` に `optFiles :: Files` を足し、`defaultOptions root` は `diskFiles root` を入れる。LSP の overlay（`Map FilePath Text`）は今のまま残す。overlay は `Files` の上に重ねる編集中のテキストであり、別の働きだからである。
- この段階では、出力も diagnostics も変えない。`scripts/determinism/hashes.txt`、`scripts/visual/pages/` の参照、各パッケージの `test/golden/`、テストの期待値は変わらない。

golem-driver に、メモリから PDF を組む関数を足す。

```haskell
-- Golem.Driver
buildPdfInMemory :: Map FilePath ByteString -> IO BuildInMemory

data BuildInMemory = BuildInMemory
  { bimPdf :: !(Maybe ByteString),          -- error のときは Nothing
    bimDiagnostics :: ![Diagnostic],        -- finishDiagnostics を通した後
    bimSources :: !(Map FileId SourceInfo)  -- renderJson に渡す
  }
```

- `buildPdfInMemory files` は、`buildCore True` を、`memoryFiles files`、`optTargets = Just [TargetPdf]`、`optParallel = False`、ほかは `defaultOptions` の値（`Dev`、トンボなし、notice と info は既定のとおり）で呼ぶ。
- `buildCore` の `inMemory` は、`golem preflight` のために PDF を書かずに返す今の道である。`buildPdfInMemory` もこの道を使うので、何も書き込まない。
- 結果の PDF と diagnostics は、同じプロジェクトを同じ版の `golem build --target pdf --format json` で組んだときの PDF のバイト列と、標準エラーの JSON と同じになる。

### 3. プラグインを外すフラグを足す

golem-driver の cabal に、フラグ `plugins` を足す（「メンテナーが決めること」の 2）。
既定は真で、今のビルドは何も変わらない。

- `if flag(plugins)` のときだけ、golem-plugin に依存し、`Golem.Driver.Plugins` と `Golem.Driver.New` を組む。
- 偽のときは、別のソースのディレクトリ（`src-no-plugins/`）の `Golem.Driver.Plugins` を組み、`Golem.Driver.New` を組まない。`golem new` は CLI の機能であり、wasm では使わないからである。
- 二つの `Golem.Driver.Plugins` は同じ名前と型を export する。今の `Golem.Driver` と `Golem.Driver.Functions` が golem-plugin から直接取り込む `HostContext`、`defaultCacheDir`、`maxDataBytes` も、`Golem.Driver.Plugins` を通して取り込むように変える。プラグインのない版は、`HostContext` を同じ形の型として、`maxDataBytes` を同じ値として持つ（golem-plugin を足さないために写す）。CPP は使わない。
- プラグインのない版の `loadPlugins` は、マニフェストに `[plugins]` もプラグインの `[[filters]]` もなければ、今と同じく `noPlugins` を返す。どちらかがあれば、マニフェストの先頭に error の G06106 を一つ出す。メッセージは「このビルドの Golem にはプラグインの機能がありません」とする。番号は、実装するときに docs/diagnostics.md で空いている番号を使う（G06106 は 2026-11-07 の時点で空いている）。
- golem-cli と golem-lsp は、フラグを使わない。どちらも golem-plugin に直接依存するので、プラグインのない golem-driver とは組まない。

### 4. wasm の入口のパッケージ golem-wasm を作る

`modules/golem-wasm` に、新しいパッケージ golem-wasm を作る（「メンテナーが決めること」の 3 と 7）。

- ライブラリ：入力と出力のバイト列の枠（下に書く）を読み書きする純粋なモジュール `Golem.Wasm.Frame` だけを持つ。ネイティブでも組み、テストする。
- 実行ファイル `golem-wasm`：`foreign export ccall` で入口を出す。`if !arch(wasm32)` のときは `buildable: False` にする。`ghc-options` は `-no-hs-main -optl-mexec-model=reactor` と、下の名前を出す `-optl-Wl,--export=...` である。`-threaded` は付けない。

エクスポートは C の ABI で、次の五つと `hs_init` に限る。

| 名前 | 型（C） | 働き |
| --- | --- | --- |
| `golem_alloc` | `uint8_t *golem_alloc(uint32_t len)` | 入力のバッファを確保する |
| `golem_free` | `void golem_free(uint8_t *p)` | `golem_alloc` と結果のバッファを解放する |
| `golem_build_pdf` | `uint8_t *golem_build_pdf(const uint8_t *in, uint32_t len)` | 入力の枠を読んで組み、結果の枠を返す |
| `golem_result_len` | `uint32_t golem_result_len(const uint8_t *r)` | 結果の枠の長さ |
| `golem_version` | `uint8_t *golem_version(void)` | `VERSION` の値（UTF-8、長さは `golem_result_len`） |

ホストは、`_initialize` を一度、`hs_init(0, 0)` を一度呼んでから使う。

入力の枠は、ファイルの並びである。
ファイルごとに、パスの長さ（`uint32` のリトルエンディアン）、パス（UTF-8）、中身の長さ（同じ）、中身を続ける。
パスは、プロジェクトのルートからの相対パスで、`normalizeRelative` の結果と一致しなければならない（`manifest.toml`、`style.toml`、`kumo-no-ito.gm`、`fonts/NotoSerifJP-Regular.otf` など）。
同じパスが二度現れたら断る。

結果の枠は、状態の 1 バイト、PDF の長さと PDF、diagnostics の JSON の長さと JSON である（長さはどれも `uint32` のリトルエンディアン）。

- 状態 0：組んだ。PDF の長さが 0 なら、error の diagnostic があって PDF がない。
- 状態 1：入力の枠を読めない（長さが足りない、パスが UTF-8 でない、パスが正規化されていない、同じパスが二度ある）。PDF と JSON の長さは 0 である。原稿や設定の誤りではなく、ホストの誤りなので、diagnostic にはしない。
- diagnostics の JSON は、`renderJson`（golem-syntax）が書くものと同じで、`golem build --format json` が標準エラーに書くものと同じバイト列である。各要素は、コード、重大度、ファイル、行、列、メッセージを持つ。

### 5. golem-font を wasi-sdk で組めるようにする

golem-font の cabal の `extra-libraries` に、`if os(wasi)` の枝を足し、wasi-sdk の C++ の標準ライブラリをリンクする。
ライブラリの名前（`c++` と `c++abi` を見込んでいる）は、1 で確かめる。
`cc-options` と `cxx-options` は変えない。

`golem_font.c` の `pthread_mutex_t` は、wasi-sdk の `wasm32-wasi` の向けに pthread の関数があるかを、1 で確かめる。
なければ、`__wasi__` のときだけロックを何もしないマクロにする。
wasm の RTS は single-threaded で、golem-font の FFI の呼び出しは `unsafe` なので、FreeType の呼び出しが重なることはない。
HarfBuzz の内部のロックも、同じく 1 で確かめる。
ネイティブのビルドのコンパイルの結果は変えない。

### 6. ツールチェーンを版と SHA-256 で固定して取る

`scripts/fetch-ghc-wasm.sh` を作り、ghc-wasm-meta の 9.10 の flavour のツールチェーンを取る（「メンテナーが決めること」の 4）。
[`scripts/fetch-wasmtime.sh`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/scripts/fetch-wasmtime.sh) と同じ形にする。

- 取るものは、ghc-wasm-meta の `autogen.json` が挙げる `haskell-wasm/ghc-wasm-bindists` のリリースの `wasm32-wasi-ghc-9.10`、`wasi-sdk`、`libffi-wasm`、ghc-wasm-meta が配る `cabal`（3.14.2.0）と `nodejs`（Template Haskell の評価に要る場合）である。ghc-wasm-meta のコミットと、各アーカイブの SHA-256 を、スクリプトの中に書く。`autogen.json` の SRI の値は 16 進に直して書く。
- `bootstrap.sh` を `curl | sh` で走らせることはしない。`setup.sh` のうち、取ったアーカイブを展開し、`env` を書く部分だけを、スクリプトに書き写す。展開先は `third_party/ghc-wasm/` とし、`~/.ghc-wasm` には書かない。
- 取るのは x86-64 の Linux の向けだけとする。

wasm のビルドは、別の cabal のプロジェクトのファイル `cabal.project.wasm` で行う。

- `packages:` には、golem-wasm と、その依存の golem のパッケージだけを並べる。golem-plugin、golem-cli、golem-lsp、golem-fixtures、golem-test-support は並べない。
- `package golem-driver` の `flags: -plugins`、`package zlib` の `flags: +bundled-c-zlib`、`tests: False` を書く。
- `cabal.project.wasm.freeze` を置き、Hackage のパッケージの版を `cabal.project.freeze` と同じにする。boot のパッケージ（`base`、`text`、`bytestring` など）は wasm の GHC のものになるので、1 で版を記録する。二つの freeze の、両方にあるパッケージの版が一致することを、CI の検査のスクリプトで確かめる。
- `peg-hs` の `source-repository-package` は、`cabal.project` と同じコミットを書く。

### 7. CI

`ci.yml` に、ジョブ `wasm` を足す（「メンテナーが決めること」の 6）。

- `changes` ジョブの `build` の出力が真のとき（Haskell のソースか cabal のファイルが変わったとき）と、wasm のスクリプトが変わったときに走る。
- `fetch-ghc-wasm.sh` で取ったツールチェーンを `actions/cache` に置き、`cabal.project.wasm` で `golem-wasm` を組む。
- 組んだ wasm で、「テスト設計」の wasm の比べを行う。今の `build` ジョブは `golem` の実行ファイルを成果物として上げないので、比べの相手は一覧にする。`build` ジョブの x86-64 のランナーが、比べの入力を `golem build --target pdf --format json` で組み、PDF と標準エラーと終了コードの SHA-256 の一覧（`scripts/wasm/compare.sh --native`）を成果物として上げる。`wasm` ジョブは、wasm で作った同じ形の一覧と、その一覧を `diff` で比べる。
- Node は `setup-node` の `lts/*` を使う（今の `ci.yml` と同じ）。ホストのスクリプトは `scripts/wasm/run.mjs` の一つとし、Node の組み込みの `node:wasi` で動かす。前もって開くディレクトリ（preopen）を一つも渡さない。

### 8. リリース

`release.yml` に、ジョブ `wasm` を足し、`release` のジョブの `needs` に加える（「メンテナーが決めること」の 7）。

- 7 と同じ手順で組み、x86-64 の Linux のアーカイブの `golem` と比べる。
- `golem-<タグ>-wasm32-wasi.tar.gz` を作る。中身は `golem.wasm`、`LICENSE`、`THIRD_PARTY_LICENSES/`、`README`（エクスポートと枠の形）である。今のアーカイブと同じく `--sort=name --mtime=@0` で作る。
- `THIRD_PARTY_LICENSES/` は、[docs/adr/0007](0007-third-party-licenses.md) の `licenses.sh` で作る。wasm の GHC の RTS と boot のパッケージ、HarfBuzz、FreeType、hyph-utf8、zlib、wasi-sdk の wasi-libc と libc++、GMP を入れる。wasm にリンクした GMP の版は、1 で調べ方を決める。GMP のソースのアーカイブは、今の `fetch-gmp.sh` で同じくリリースに添える。
- アーカイブの名前は `golem-*.tar.gz` に当たるので、`SHA256SUMS` と `attest-build-provenance` と `gh release create` の今の glob にそのまま入る。`dist/*.wasm`（プラグインの見本）とは名前が重ならない。

### 9. 仕様書とドキュメント

- [docs/specifications.md](../specifications.md) の「モジュール構成」に golem-wasm を足し、golem-driver の `plugins` のフラグと、`Files` によるファイルの読み方を書く。
- [docs/diagnostics.md](../diagnostics.md) に G06106 を足す。
- README の「Installation」に wasm のアーカイブと、エクスポートと枠の形を、「固定しているネイティブライブラリ」に wasm のツールチェーンの版を書く。
- docs/roadmap.md の「手で確かめる項目」に、ブラウザ（Safari と Chrome）で `browser_wasi_shim` を使って組めることを足す。CI は Node で確かめるだけだからである。

### パッケージの依存

この ADR は、golem のパッケージのあいだの `build-depends` を、次のように変える。
足すものと除くもののほかは変えない。

| パッケージの構成要素 | 足す | 除く |
| --- | --- | --- |
| golem-driver のライブラリ | | golem-plugin を `if flag(plugins)` の中に移す（既定のフラグでは変わらない） |
| golem-wasm のライブラリ（新規） | | |
| golem-wasm の実行ファイル（新規） | golem-driver、golem-syntax、golem-wasm | |
| golem-wasm のテスト（新規） | golem-wasm | |

- golem-project、golem-typeset（または今の golem-driver の PDF のモジュール）、golem-font、golem-cli、golem-lsp の `build-depends` は変わらない。`Files` は golem-project に置き、golem-driver と golem-typeset はすでに golem-project に依存している。
- Hackage のパッケージでは、golem-wasm のライブラリは `base` と `bytestring`、実行ファイルはそれに `containers` と `text`、テストは `base`、`bytestring`、`hedgehog`、`tasty`、`tasty-hedgehog`、`tasty-hunit` に依存する。golem-project のテストに、`hedgehog` と `tasty-hedgehog` を足す（版の範囲は golem-eval のテストと同じ）。
- 1 で組めないパッケージが見つかったときの差し替えは、この表に含めない。新しい ADR で決める。

### 順と確かめ方

この ADR は、[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) の二つめのプルリクエストが main に入った後に実装する。
PDF の組版のモジュールの移動と、`Files` への書き換えの差分を混ぜないためである。

プルリクエストは、2（説明に 1 の結果を書く）、3、4 から 7、8 と 9 の順に分ける。
2 と 3 は出力を変えないので、`scripts/determinism/hashes.txt` と golden のファイルが差分に現れないことを確かめる。

## 実装しないこと

- **shem の側とページ**：tett23/tett23 と shem のリポジトリで行う。
- **プラグインを wasm で動かすこと**：プラグインは wasmtime の上で動く。ブラウザの WebAssembly の API で動かす道もありうるが、燃料による命令の数の制限（[docs/adr/0124](0124-filter-fuel-by-document-size.md)）を同じに保てるかがわからない。
- **ビルドのオプション**：入口は、プロファイル、トンボ、`--no-notices`、`--verbose` を受け取らない。`golem build --target pdf` の既定と同じにする。必要になったら、入力の枠に足す ADR を作る。
- **PDF のほかのターゲット**：HTML、EPUB、プレーンテキストは組まない。`optTargets` を PDF に限る。
- **wasm のバイト列の再現性**：同じソースから同じ `golem.wasm` ができることは保証しない。保証するのは、wasm で組んだ PDF と diagnostics が、ネイティブのものと一致することである。
- **x86-64 の Linux のほかで wasm を組むこと**：wasm は一つの成果物なので、一か所で組めば足りる。
- **JSFFI のエクスポート**：「メンテナーが決めること」の 3 で退ける。
- **WASI の仮想のファイルシステムに置いたプロジェクトを読むこと**：「メンテナーが決めること」の 1 で退ける。
- **GHC の版を上げること**：ネイティブは GHC 9.10.3 のままとする（[docs/adr/0001](0001-haskell-workspace-and-ci.md)）。
- **ビルドの時間と wasm の大きさの目標**：1 で測って記録するだけにする。

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。

### 2 のテスト（ネイティブ）

- golem-project：`memoryFiles` の `filesResolve` が、`normalizeRelative` の誤り（`Absolute`、`Url`、`EscapesRoot`）を同じに返し、表にないパスを `Missing` とすること。一時ディレクトリにファイルを書き、シンボリックリンクのない木では、`diskFiles` と `memoryFiles` の `filesResolve` と `filesRead` が、生成した相対パスのどれでも同じ結果になること（hedgehog の性質のテスト）。
- golem-driver：`buildPdfInMemory` に、golem-driver の `test/fixtures/kanikosen/`（`manifest.toml`、`style.toml`、`kanikosen.gm`、Noto Serif JP のサブセット）のファイルを表で渡すと、同じフォルダーを `build`（`optTargets = Just [TargetPdf]`）で組んだ PDF と同じバイト列になり、diagnostics の `renderJson` も同じになること。
- 同じく、`scripts/determinism/` の入力に PDF の `style.toml` を加えたもの、図版と `@table` と書誌を使う今のテストのプロジェクトの一つ（`FigureSpec` か `TableFilesSpec` のもの）で、同じことを確かめる。表に図版と CSV と CSL-JSON を含めれば、メモリからも読めることを確かめられる。
- `style.toml` を壊したプロジェクトで、`bimPdf` が `Nothing` になり、`style.toml` の行と列を持つ diagnostic が、ディスクから組んだときと同じ JSON で返ること。
- `style.toml` が指すフォントを表に入れないと、ディスクでフォントのファイルがないときと同じ diagnostic（同じコード、位置、メッセージ）が返ること。
- `manifest.toml` を表に入れないと、G03016 が返ること。
- `buildPdfInMemory` が何も書かないこと：空の作業用のディレクトリをカレントディレクトリにして呼び、呼んだ後もそのディレクトリが空であること。

### 3 のテスト

- 既定のフラグでは、golem-driver の今のテストがすべて通り、`hashes.txt` が変わらないこと。
- `-plugins` のビルドは、7 の wasm のジョブで確かめる（下）。ネイティブで `-plugins` の golem-driver を組んで走らせるジョブは作らない。golem-driver を二度組む時間に見合わないからである。

### 4 のテスト（ネイティブ）

- `Golem.Wasm.Frame`：ファイルの並びを書いて読むと元に戻ること（hedgehog）。長さが足りない枠、UTF-8 でないパス、正規化されていないパス（`./a.gm`、`a//b.gm`、`../a.gm`）、同じパスが二度ある枠を、状態 1 として断ること。結果の枠を書くと、決めた形のバイト列になること（小さな例を golden で持つ）。

### 7 の wasm のテスト

`scripts/wasm/run.mjs` で wasm を動かし、同じコミットのネイティブの `golem` の結果と比べる。
シェルのスクリプト `scripts/wasm/compare.sh` が、入力ごとに PDF、diagnostics の JSON、終了の状態の SHA-256 の一覧を書く。
`--native` を付けるとネイティブの `golem` で、付けないと wasm で組む。
CI は、二つの一覧が一致することを `diff` で確かめる（7）。

- **PDF のバイト列**：kanikosen と `scripts/determinism/` の入力（PDF の `style.toml` を加えたもの）で、wasm の PDF の SHA-256 が、`golem build --target pdf` の PDF の SHA-256 と一致すること。
- **diagnostics**：同じ入力と、`style.toml` を壊したもの、フォントを欠いたもので、wasm の JSON が `golem build --target pdf --format json` の標準エラーとバイト単位で一致すること。
- **繰り返し**：同じインスタンスで同じ入力を二度組むと同じバイト列になり、新しいインスタンスで組んでも同じになること。前の呼び出しの状態が残らないことを確かめる。
- **プラグイン**：`[plugins]` を書いたマニフェストで、PDF が返らず G06106 が一つ返ること。
- **ファイルを読まないこと**：ホストは preopen を渡さないので、Golem がファイルを開こうとすれば失敗する。上の比べがすべて通ることで、入口がファイルを読まないことを確かめる。
- **エクスポートとインポート**：`WebAssembly.Module.exports` が `memory`、`_initialize`、`hs_init`、4 の五つだけであり、`WebAssembly.Module.imports` が `wasi_snapshot_preview1` のものだけであること。
- **枠の誤り**：正規化されていないパスの入力で、状態 1 が返ること。

この比べ自体のテストとして、`scripts/ci/testdata` に、PDF の SHA-256 の一行を変えた一覧を置き、比べが失敗することを確かめる。

### 手で確かめること

- 8 の後、`v` のタグの下書きのリリースに `golem-<タグ>-wasm32-wasi.tar.gz` があり、`SHA256SUMS` と `gh attestation verify` が通ること。
- `browser_wasi_shim` を使い、Safari と Chrome で kanikosen を組み、ネイティブと同じ SHA-256 になること。結果を docs/roadmap.md の項目に書き、その項目を外す。

## トレードオフ

`Files` を通すために、ファイルを読む関数のほとんどの型が変わる。
変える関数は多いが、どれも引数が一つ増えるだけで、ディスクのときの振る舞いは変わらない。
その代わりに、wasm の入口は `golem build` と同じ手順を通り、図版、表、書誌、関数も、表に入れればそのまま使える。
入口を原稿一つと `style.toml` とフォントに絞り、評価を写して組む道を作れば、型は変わらないが、diagnostics と出力が二つの道でずれていく。

プラグインを外すフラグは、golem-driver に二つの版の `Golem.Driver.Plugins` を持たせる。
二つが同じ名前と型を export することは、コンパイラが確かめてくれない。
プラグインのない版が組めることは、wasm のジョブでしか確かめない。
フラグを足さずに、評価を golem-driver から別のパッケージに分けて、プラグインに依存しない評価を作る道もある（[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) の「メンテナーが決めること」の 6 が docs/roadmap.md に回した項目）。
その道のほうが依存の向きはきれいだが、`Evaluated` とその補助の境目を決める作業が先に要り、この ADR の範囲を超える。

入口が `manifest.toml` を受け取るので、ページの ADR が決めた引数（原稿、`style.toml`、フォント）と違う。
ページの側は、`manifest.toml` を一つ持ち、表に加える必要がある。
受け取らない場合は、入口の中に固定のマニフェストを持つことになり、PDF のバイト列を決める入力が、Golem の中に隠れる（「メンテナーが決めること」の 1）。

wasm のツールチェーンは、GHC の公式の配布物ではなく、ghc-wasm-meta の fork と、そのリリースの配布物である。
GHC の User's Guide が導入の手順として指すのは ghc-wasm-meta なので、upstream はそこになる。
fork の 9.10 の枝が GHC 9.10.3 とどこまで同じかは確かめていない。
PDF のバイト列の比べが、その違いが出力に及ばないことを確かめる。

9.10 の flavour は GMP を使うので、wasm にも LGPL-3.0 の GMP が静的にリンクされる。
ネイティブのアーカイブと同じく、ライセンスの文書と GMP のソースを添える手間がかかる。
GMP を使わない `native` の flavour は upstream の `master` を追うので、9.10 に揃えられない。

wasm のジョブは、ネイティブとは別に GHC と依存のすべてを組むので、CI の時間が延びる。
どれだけ延びるかは 1 で測る。

## メンテナーが決めること

1. **入口が受け取るもの**：推奨は、プロジェクトのファイルを、ルートからの相対パスとバイト列の並びで受け取ることである。`manifest.toml`、`style.toml`、章の `.gm`、フォントを、同じ形で渡す。PDF のバイト列を決める入力（`manifest.toml` の `[metadata]` と `[source]`）が、すべて入口の引数に現れる。ネイティブとの比べは、同じフォルダーをそのまま渡せば済む。
   - 退けた案の一つは、ページの ADR のとおり、原稿一つ、`style.toml`、フォントを別々の引数で受け取り、マニフェストを入口の中に固定で持つことである。固定のマニフェストが PDF の入力になるのに、使い手からは見えない。言語や題を変えられない。フォントを `style.toml` のどのパスに当てるかも、別に決める必要がある。
   - もう一つは、WASI の仮想のファイルシステム（`browser_wasi_shim` のメモリの木）にプロジェクトを置き、今の `build` をそのまま呼ぶことである。Golem のコードは変わらないが、`canonicalizePath` やシンボリックリンクの検査の振る舞いが、ホストの WASI の実装に左右される。ページの ADR の「ファイルを読まない入口」にも合わない。
2. **プラグインを外す方法**：推奨は、golem-driver の cabal のフラグ `plugins`（既定は真）と、二つのソースのディレクトリの `Golem.Driver.Plugins` である。ページの ADR が求めたとおりで、既定のビルドは何も変わらない。
   - 退けた案の一つは、`{-# LANGUAGE CPP #-}` で `Golem.Driver` の中を切り替えることである。プラグインの有無が、評価の関数の中に散らばる。
   - もう一つは、評価を golem-driver から別のパッケージに分けることである（「トレードオフ」）。
3. **エクスポートの ABI**：推奨は、`foreign export ccall` の C の ABI と、長さで区切ったバイト列の枠である。wasmtime、Node、Deno、ブラウザのどれでも、JavaScript の糊のコードなしに呼べる。shem も C の ABI で出す（ページの ADR）。
   - 退けた案の一つは、JSFFI（`foreign export javascript`）である。後処理のスクリプトが作る JavaScript のモジュールが要り、ホストが JavaScript に限られる。9.10.3 では常に非同期で、Promise を返す。
   - もう一つは、入力を CBOR（golem-doc がすでに使う `cborg`）にすることである。ホストに CBOR の符号器が要り、ファイルの並びを表すには大きすぎる。
   - もう一つは、ファイルを一つずつ渡す関数（`golem_add_file`）を出すことである。入口が呼び出しのあいだの状態を持つことになる。
4. **ツールチェーン**：推奨は、ghc-wasm-meta の 9.10 の flavour の配布物を、ghc-wasm-meta のコミットと SHA-256 で固定し、`scripts/fetch-ghc-wasm.sh` で `third_party/` に取ることである。ネイティブと同じ GHC の系列（9.10、`base` 4.20）にそろえられる。
   - 退けた案の一つは、wasm だけ 9.14 の flavour にすることである。9.14 は User's Guide が Template Haskell に対応すると書く。しかし、ネイティブ（9.10.3）と GHC の版が違えば boot のパッケージの版もそろわず、各パッケージの `base >=4.20 && <4.21` を満たさない見込みが高い（9.14 の `base` の版は確かめていない）。ネイティブと wasm で別の GHC の系列を保つことにもなる。
   - もう一つは、GHC と wasi-sdk をソースから組むことである。時間がかかり、ghc-wasm-meta の配布物に頼らない理由がない。
   - もう一つは、`bootstrap.sh` を `curl | sh` で走らせることである。取るものの SHA-256 をこちらで固定できず、`~/.ghc-wasm` に書く。
5. **1 で組めないものが見つかったとき**：推奨は、そこで止め、パッケージごとに新しい ADR で扱いを決めることである。`uuid` なら、RFC 9562 の名前による UUID（SHA-1）を golem-pdf で実装し直す案、Template Haskell なら、生成したモジュールをコミットする案（`scripts/gen-vertical-orientation.sh` と同じ形）が考えられる。どちらも出力を変えないことを `hashes.txt` で確かめる必要があり、何が組めないかがわかってから決めるほうが、要らない変更をしない。
   - 退けた案は、この ADR の中で、前もって `uuid` を差し替え、Template Haskell を外すことである。組めるものまで変えることになる。
6. **wasm のジョブを走らせる頻度**：推奨は、プルリクエストごとに、Haskell のソースか cabal のファイルか wasm のスクリプトが変わったときに走らせることである。ネイティブと wasm の出力のずれを、マージの前に見つけられる。1 で測ったビルドの時間が長すぎるときは、頻度を新しい ADR で決め直す。
   - 退けた案の一つは、リリースのときだけ走らせることである。ずれがタグを打ってから見つかる。
   - もう一つは、毎晩走らせることである（`race.yml` のように）。ずれが main に入ってから見つかる。
7. **パッケージの名前とリリースの形**：推奨は、パッケージを golem-wasm、リリースのファイルを `golem-<タグ>-wasm32-wasi.tar.gz`（`golem.wasm` とライセンスの文書を入れる）とすることである。ネイティブのアーカイブと同じく、ライセンスの文書が配布物と一緒にあり、`SHA256SUMS` と provenance の今の glob に入る。
   - 退けた案の一つは、`golem.wasm` をそのまま添えることである。ページの側は展開しなくて済むが、LGPL-3.0 の GMP を含む配布物から、ライセンスの文書が離れる。
   - 名前の退けた案は、golem-browser と golem-embed である。前者は、Node と wasmtime でも動くことと合わない。後者は、何に埋め込むのかを示さない。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-07、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- tett23/tett23 [ADR 0005: Golem のページとプレイグラウンド](https://github.com/tett23/tett23/blob/79a0e603603b9644ab8129cd750a6e82d80e7e22/.github/docs/adr/0005-golem-page.md)
- [ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md)、[ADR 0173](0173-rc4-refactoring.md)、[docs/adr/0001](0001-haskell-workspace-and-ci.md)、[docs/adr/0002](0002-determinism.md)、[docs/adr/0004](0004-binary-distribution-and-release.md)、[docs/adr/0007](0007-third-party-licenses.md)、[docs/adr/0034](0034-fewer-unsafe-perform-io.md)、[docs/adr/0071](0071-determinism-check-compares-diagnostics.md)、[docs/adr/0093](0093-fetch-shem-pinned-by-version-and-sha256.md)、[docs/adr/0146](0146-threaded-golem-driver-test.md)、[docs/adr/0156](0156-wasmtime-49-0-5.md)
- [golem-driver ADR 0001](../golem-driver/adr/0001-build-pipeline.md)、[golem-driver ADR 0002](../golem-driver/adr/0002-pdf-pipeline.md)、[golem-plugin ADR 0001](../golem-plugin/adr/0001-wasm-host-and-abi.md)、[golem-font ADR 0001](../golem-font/adr/0001-shaping-and-metrics.md)、[golem-project ADR 0001](../golem-project/adr/0001-manifest-and-import-graph.md)、[golem-layout ADR 0001](../golem-layout/adr/0001-knuth-plass-line-breaking.md)
- GHC 9.10.3 User's Guide, "Using the GHC WebAssembly backend". https://downloads.haskell.org/ghc/9.10.3/docs/users_guide/wasm.html
- GHC 9.12.1 User's Guide, "Using the GHC WebAssembly backend". https://downloads.haskell.org/ghc/9.12.1/docs/users_guide/wasm.html
- GHC 9.14.1 User's Guide, "Using the GHC WebAssembly backend". https://downloads.haskell.org/ghc/9.14.1/docs/users_guide/wasm.html
- ghc-wasm-meta（コミット `8079eb96bbc63823d99ad8acaff0765532625474`）の `README.md`、`setup.sh`、`autogen.json`、`cabal.th.config`、`tests/agda-language-server.sh`。https://gitlab.haskell.org/haskell-wasm/ghc-wasm-meta
- Cabal-syntax 3.12.1.0, `Distribution.System`（`OS` の `Wasi`、`Arch` の `Wasm32`）。GHC 9.10.3 に付く haddock で確かめた。
- RFC 9562, Universally Unique IDentifiers (UUIDs). https://www.rfc-editor.org/rfc/rfc9562
