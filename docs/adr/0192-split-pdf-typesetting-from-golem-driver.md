# ADR 0192: PDF の組版を golem-driver から新しいパッケージに分ける

ステータス: 採択→`PdfInput` の `piProjectVars` と、`Golem.Driver` が export する `projectVarTexts` は [ADR 0196](0196-pass-project-vars-to-golem-typeset.md)

## 文脈

[ADR 0173](0173-rc4-refactoring.md) は、golem-driver の `src/` の 7,199 行のうち 4,050 行（56%）が PDF の組版と描画（`Golem.Driver.Pdf` とその下）であると測った。
仕様書の図は golem-driver を「パイプラインの束ね」とするが、PDF の組版の多くがここにある。
メンテナーは、PDF の組版を golem-driver から分けると決め、分け方をこの ADR で決めるよう求めた（「決めたことの記録」）。

分け方は、行数ではなく責務で決める（[ADR 0173](0173-rc4-refactoring.md) の「決めたことの記録」）。
4,050 行は、分けるかどうかを考えるきっかけであり、どこで分けるかの根拠にはならない。
そこで、main の `50b9fca8` で、golem-driver の各モジュールの import と、ほかのパッケージからの使われ方を読んだ（2026-11-07）。
この ADR のモジュールとパッケージの名前は、とくに断らないかぎり今の名前である。
[ADR 0173](0173-rc4-refactoring.md) の 3 で golem-doc を分けた後の名前（golem-assemble、golem-bibliography、golem-numerals）は、その旨を書く。

### PDF の組版を受け持つモジュール

golem-driver のライブラリには 19 のモジュールがある（[`golem-driver.cabal`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/golem-driver.cabal#L22-L73)）。
import をたどると、次の九つが PDF の組版のためだけにある。

| モジュール | 受け持つこと |
| --- | --- |
| `Golem.Driver.Pdf` | 下の三つの公開の窓口。取り込みと export の一覧だけを持つ |
| `Golem.Driver.Pdf.Flow` | 意味論 IR の本を行に組み、ページに配置し、ページ番号への参照を収束させる（S2） |
| `Golem.Driver.Pdf.Draw` | 組んだページを golem-pdf の描画に直し、PDF を書く |
| `Golem.Driver.Pdf.Fonts` | PDF の書体の役割、シェイピングの型、`FontProvider`、`PdfInput` |
| `Golem.Driver.Fonts` | golem-font（HarfBuzz と FreeType）による `FontProvider` の実装 |
| `Golem.Driver.Memo` | シェイピングの結果を覚える純粋なメモ化 |
| `Golem.Driver.TextLayer` | PDF のテキストの層（ToUnicode と ActualText） |
| `Golem.Driver.Overhang` | ルビと圏点が行の外にはみ出す量 |
| `Golem.Driver.RuleShape` | 罫線の線種の形 |

`Golem.Driver.Svg` は二つの責務を持つ。
SVG の図版を golem-pdf の描画に直す `svgDrawing` と、G08011、G08016、G08017、G08101 の文言は、`Golem.Driver.Pdf.Flow` だけが使う。
HTML と EPUB の G08014 の文言を作る `activeMessage` は、`Golem.Driver` の HTML と EPUB の検査だけが使う（[`Svg.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Svg.hs#L103-L122)）。

九つのモジュールは、互いに import し合う。
`Golem.Driver.Fonts` は `Golem.Driver.Pdf` の型（`FontProvider`、`LoadedFonts`、`Shaping`）を実装し（[`Fonts.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Fonts.hs#L26-L28)）、`Golem.Driver.Memo` は `Shaping` をキーにする（[`Memo.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Memo.hs#L24)）。
`Golem.Driver.Pdf.Draw` は `Golem.Driver.Pdf.Flow` の組んだ結果を描き、`Golem.Driver.Overhang` は組むときと描くときの両方で同じはみ出しを求める。
一方で、九つのどれも、評価（golem-eval、golem-emet）、プラグイン（golem-plugin）、EPUB（golem-epub）、プレーンテキスト（golem-text）のパッケージを import しない。
golem-driver のほかのモジュールからは `Golem.Driver.Version` だけを、golem-html からは `codeTokens` だけを使う（どちらも後に書く）。

### golem-layout、golem-layout-spec、golem-pdf、golem-font との分担

[ADR 0173](0173-rc4-refactoring.md) は、組版と描画の境目を、golem-layout と golem-layout-spec との分担を含めて読み直す必要があるとした。
四つのパッケージは、それぞれ一つの仕組みを持ち、意味論 IR の本（集約した `Book`）を組む手順を持たない。

- **golem-layout**：行分割（Knuth-Plass）、和文の組版、改ページ、ルビの配置、表、傍注、回り込みの手順を持つ。golem-doc、golem-length、golem-project、golem-syntax に依存し、golem-pdf と golem-font には依存しない。golem-doc からは、IR の型（インラインの要素、ルビ、圏点、改ページの種類など）と漢数字を取り込むが、集約のモジュール（`Golem.Doc.Assemble`）は取り込まない。
- **golem-layout-spec**：`style.toml` からページの幾何（版面、行の格子、段、柱とノンブルの位置）を求める一つのモジュール `Golem.LayoutSpec` である。golem-pdf、golem-project、golem-syntax に依存する。
- **golem-pdf**：PDF/X-4 の PDF を決定的に書く。golem のパッケージでは golem-length と golem-syntax にだけ依存し、何を描くかを知らない。
- **golem-font**：フォントを読み、シェイピングとサブセット化を行う。golem のどのパッケージにも依存しない。

golem-driver の九つのモジュールは、この四つの手順を、意味論 IR の本に当てはめる。
本の段落を書体の役割とシェイピングで箱に直し、golem-layout の手順で行とページに組み、golem-layout-spec の幾何に置き、golem-pdf で書く。
四つのどれにも属さない、意味論 IR から PDF までを通す一つの責務である。

組むことと描くことは、別々のパッケージに分けられない。
`Golem.Driver.Pdf.Flow` は、組む段階で図版を golem-pdf の型（`P.FigureContent`、`P.Swatch`、`P.Turn`）で読み、PDF の図版を `P.importPage` で取り込む（[`Flow.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L55-L107)）。
`Golem.Driver.Pdf.Draw` は、`Golem.Driver.Pdf.Flow` の型を描く。
二つは同じ型と同じ依存を共有するので、分けても、一つの責務が二つのパッケージにまたがるだけである。

`Golem.Driver.Pdf.Flow` は golem-html の `codeTokens` も使う（[`Flow.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L84)）。
PDF のコードブロックを、HTML と同じ字句の分け方で色分けするためである（[golem-driver ADR 0023](../golem-driver/adr/0023-code-block-book-features.md)）。

### 残りの golem-driver が PDF のモジュールから使うもの

`Golem.Driver` は、PDF のモジュールから次のものを使う。

- **PDF を組み、書くこと**：`renderPdfView`、`PdfInput`、`pdfFileName`、`FontProvider`、`golemFontProvider`、`noFontProvider`（[`Driver.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver.hs#L1119-L1125)）。
- **PDF の検査と notice**：`styleLayoutDiagnostics`、`bodyFontDiagnostics`、`cff2FontDiagnostics`、`codeFontNotice`、`kentenRubyNotices`、PDF の書体の役割のファイルを求める `usedRoles`、`codeStyles`、`bookHasCode`（[`Driver.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver.hs#L744-L757)）。
- **PDF に限らないもの**：次の五つは、PDF のモジュールに定義があるが、評価か、PDF のほかのターゲットが使う。

| 名前 | 定義のある場所 | PDF のほかに使うところ |
| --- | --- | --- |
| `styleFileId`（`style.toml` の `FileId`） | [`Flow.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L2279-L2281) | 評価（[`lockFileId`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver.hs#L184-L185) と `style.toml` の diagnostics の位置、[`Driver.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver.hs#L223)） |
| `runningMetadata`（柱が示せる `[metadata]` の値） | [`Flow.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L565-L578) | 評価（`.gm` の `meta` の値、[`metadataValues`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver.hs#L412-L421)） |
| `listBullets`（PDF、HTML、EPUB の箇条書きの印） | [`Flow.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L1199-L1203) | HTML と EPUB（[`Driver.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver.hs#L1062)） |
| `textBullets`（プレーンテキストの箇条書きの印） | [`Flow.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L1205-L1207) | プレーンテキストだけ（[`Driver.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver.hs#L1161)） |
| `listNumberDiagnostics`（G07029） | [`Flow.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L932-L943) | すべてのターゲット（[`Driver.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver.hs#L776-L778)） |

この五つを PDF のパッケージに入れたまま分けると、評価とプレーンテキストの書き出しが、PDF の組版のパッケージを import することになる。
五つが頼るものを読むと、`styleFileId` はプロジェクトのファイルの表、`runningMetadata` は `Metadata`、`listBullets` と `textBullets` は `ListStyle` だけを使い、どれも golem-project の型である。
`listNumberDiagnostics` は、`style.toml` の `[lists]` の番号の書式のほかは、`Golem.Doc.ListMarkers` の `listSites`、`formatListNumber`、`defaultNumberFormat` と、`Golem.Doc.Assemble` の `Book` だけを使う。
これらの関数と型は、[ADR 0173](0173-rc4-refactoring.md) の 3 の後は golem-assemble にある。

### Golem のバージョン

`Golem.Driver.Pdf.Fonts` は、`Golem.Driver.Version` の `golemVersion` を import し、PDF の Producer とインスタンス ID の入力を作る（[`Fonts.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Fonts.hs#L170-L182)）。
`golemVersion` は、リポジトリの `VERSION` を Template Haskell でコンパイルのときに埋め込む（[`Version.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Version.hs)）。
golem-cli も `golemVersion` を `--version` に使う。
PDF のパッケージは golem-driver に依存できないので、バージョンの受け取り方を変える必要がある。
バージョンを入力の一部とする決まり（[docs/adr/0002](0002-determinism.md)）に沿えば、PDF の組版はバージョンを外から受け取ればよい。

### テスト

golem-driver の三つのテストのスイートの 30 のモジュールのうち、PDF のモジュールを import するものは 18 ある。
そのほとんどは、補助の `Support.hs` の `evaluateProject` でプロジェクトを評価してから、`layoutPdf` や `layoutPages` で組む（[`Support.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/test/Support.hs#L348-L358)）。
評価は golem-driver が持つので、これらのテストは golem-driver を通して PDF の組版を確かめる。
`Support.hs` を使わず、PDF のモジュールと下の層だけを使うのは、`MemoSpec` と `RuleShapeSpec` の二つである。

CI の `build` ジョブは、テストのスイートを、golem-driver のものとそのほかの二つのランナーに分ける（`scripts/ci/test-suites.sh`、[docs/adr/0140](0140-ci-split-test-runners-and-visual-pdfs-first.md)）。
`scripts/ci/test-only-deps.sh` は、cabal の計画のすべてのローカルのパッケージを調べるので、パッケージが増えても書き換えは要らない。

### LSP

golem-lsp のライブラリは、golem-driver から、評価とその結果の補助（`Evaluated`、`evaluateProjectWith`、`evaluateLoose`、`assetRefs`、`keepStyles`、`metadataValues`）、lint、`codeDescriptionUrl` だけを使い、PDF のモジュールを使わない。
それでも、golem-driver が PDF の組版のパッケージに依存するかぎり、golem-lsp もそれに依存する。
評価と書き出しが一つのモジュール `Golem.Driver` にあるからである。

## 実装すること

### 1. PDF に限らない値を下の層に移す

「文脈」の表の五つを、PDF のモジュールから、それぞれの型を持つパッケージに移す（「メンテナーが決めること」の 3）。

| 名前 | 移す先 |
| --- | --- |
| `styleFileId` | golem-project の `Golem.Project` |
| `runningMetadata` | golem-project の `Golem.Project.Manifest` |
| `listBullets`、`textBullets` | golem-project の `Golem.Project.Style` |
| `listNumberDiagnostics` | golem-assemble の `Golem.Assemble.ListMarkers` |

- `listNumberDiagnostics` は、`Style` の代わりに `[lists]` の番号の書式（`Maybe (NonEmpty NumberFormat)`）を受け取る。golem-assemble は golem-project に依存しないからである。呼び出し元は `lsNumbers (stLists style)` を渡す。G07029 のメッセージ、位置、並びの順は変えない。
- ほかの四つは、型も本体も変えない。
- golem-project と golem-assemble の `build-depends` は変えない。五つが使う型と関数は、どれもすでに移す先のパッケージか、その依存にある。

この 1 の後は、`Golem.Driver` の評価の関数（`evaluateProjectWith`、`evaluateLoose`、`metadataValues` など）と、HTML、EPUB、プレーンテキストの書き出しは、PDF のモジュールを使わない。

### 2. golem-typeset を作る

`modules/golem-typeset` に、新しいパッケージ golem-typeset を作る（「メンテナーが決めること」の 1 と 2）。
責務は、PDF の組版である。
意味論 IR の本と `style.toml` から、行とページを組み、PDF を書く。

モジュールは、名前を変えて次のように移す。
公開するか（`exposed-modules`）、内部に置くか（`other-modules`）は、今のとおりにする。

| 今のモジュール | 移した後のモジュール | 公開 |
| --- | --- | --- |
| `Golem.Driver.Pdf` | `Golem.Typeset` | する |
| `Golem.Driver.Pdf.Flow` | `Golem.Typeset.Flow` | しない |
| `Golem.Driver.Pdf.Draw` | `Golem.Typeset.Draw` | しない |
| `Golem.Driver.Pdf.Fonts` | `Golem.Typeset.Fonts` | しない |
| `Golem.Driver.Fonts` | `Golem.Typeset.FontProvider` | する |
| `Golem.Driver.Memo` | `Golem.Typeset.Memo` | する |
| `Golem.Driver.TextLayer` | `Golem.Typeset.TextLayer` | する |
| `Golem.Driver.Overhang` | `Golem.Typeset.Overhang` | する |
| `Golem.Driver.RuleShape` | `Golem.Typeset.RuleShape` | する |
| `Golem.Driver.Svg` の `svgDrawing`、`unsupportedMessage`、`markerMessage`、`markerSegmentsMessage` | `Golem.Typeset.Svg` | する |

- モジュールの名前は、ほかのパッケージと同じく、パッケージの名前に合わせる（golem-xxx なら `Golem.Xxx` の下）。`Golem.Driver.Fonts` は、`Golem.Typeset.Fonts`（今の `Golem.Driver.Pdf.Fonts`）と名前がぶつかるので、中身の `golemFontProvider` に合わせて `Golem.Typeset.FontProvider` とする。
- [ADR 0173](0173-rc4-refactoring.md) の 5 で `Golem.Driver.Pdf` の下に足したモジュールも、同じ規則で `Golem.Typeset` の下に移す。
- `Golem.Driver.Svg` には `activeMessage` だけを残す。HTML と EPUB の検査の文言だからである。
- 関数と型は、次に書くバージョンの受け取り方のほかは変えない。

Golem のバージョンは、PDF を書く関数の引数で受け取る（「メンテナーが決めること」の 4）。

- `renderPdf` と `renderPdfView` は、最初の引数に Golem のバージョン（`Text`）を受け取る。
- `producer` と `instanceIdInputs` も、最初の引数にバージョンを受け取る。作る値は今と同じである（`"Golem " <> v` と、入力の最後の `"golem-" <> v`）。
- `Golem.Driver` は、`golemVersion` を渡す。`Golem.Driver.Version` は golem-driver に残る。

`Golem.Driver` の export の一覧は変えない。
`FontProvider`、`LoadedFonts`、`noFontProvider` は golem-typeset から取り込んで、今のとおり export する。
golem-cli と golem-lsp は、取り込みの行も変わらない。

ADR を置くディレクトリは `docs/golem-typeset/adr/` とする。
PDF の組版を決めた今の ADR は、コミット済みなので `docs/golem-driver/adr/` に残し、コードのコメントの「golem-driver ADR NNNN」も書き換えない。

### 3. テストを移す

- golem-typeset に、テストのスイート `golem-typeset-test` を作り、`MemoSpec` と `RuleShapeSpec` を移す。golem-driver-test の `Main.hs` から、二つを外す。
- ほかのテストは、golem-driver の三つのスイートに残す（「メンテナーが決めること」の 5）。取り込みの行（`Golem.Driver.Pdf` を `Golem.Typeset` にするなど）と、`renderPdf`、`producer`、`instanceIdInputs` の呼び出しにバージョンを渡すほかは、テストの中身を変えない。
- `MemoSpec` と `RuleShapeSpec` は `-threaded` を要さず、プロセスの状態も変えないので、`golem-typeset-test` に `ghc-options` を足さない。
- `scripts/ci/test-suites.sh` は変えない。`golem-typeset-test` は、そのほかのスイートのランナーで走る。

### 4. 仕様書とドキュメントを直す

- [docs/specifications.md](../specifications.md) の「モジュール構成」の図に、PDF 経路の箱として「golem-typeset<br/>PDF の組版と描画」を足す。golem-driver から golem-font、golem-layout、golem-layout-spec への矢印を、golem-typeset からの矢印にし、golem-driver から golem-typeset への矢印を足す。ほかの依存を通して届く矢印を省く今の規則で、図の矢印を引き直す。
- 同じ節の「golem-driver が golem-svg の描画を golem-pdf の描画に直す」を golem-typeset にし、golem-length を使うモジュールの一覧に golem-typeset を加える。
- [docs/diagnostics.md](../diagnostics.md) の各コードの「段階とモジュール」が書く `Golem.Driver.Pdf`、`Golem.Driver.Fonts`、`Golem.Driver.Svg` を、新しい名前に直す。`Golem.Driver.Svg` は、G08014（`activeMessage`）の箇所だけに残す。「番号の区分」の 07 と 08 の主なモジュールに golem-typeset を加え、07 に G07029 を出す golem-assemble を加える。

### パッケージの依存

この ADR は、golem のパッケージのあいだの `build-depends` を、次のように変える。
golem-assemble、golem-bibliography、golem-numerals は、[ADR 0173](0173-rc4-refactoring.md) の 3 で作るパッケージである。
足すものと除くもののほかは変えない。

| パッケージの構成要素 | 足す | 除く |
| --- | --- | --- |
| golem-typeset のライブラリ（新規） | golem-assemble、golem-bibliography、golem-doc、golem-font、golem-html、golem-layout、golem-layout-spec、golem-length、golem-numerals、golem-pdf、golem-preflight、golem-project、golem-svg、golem-syntax | |
| golem-typeset のテスト（新規） | golem-layout-spec、golem-pdf、golem-project、golem-typeset | |
| golem-driver のライブラリ | golem-typeset | golem-font、golem-layout、golem-layout-spec、golem-numerals |
| golem-driver の三つのテスト（`golem-driver-test`、`golem-driver-global-test`、`golem-driver-parallel-test`） | golem-typeset | |

- golem-driver のライブラリは、golem-length、golem-pdf、golem-preflight、golem-svg を残す。HTML の設定の長さ（`Golem.Driver.Html`）、トンボの種類（`markStyle`）、`golem preflight`、SVG の動的なコンテンツの検査（G08014）に使うからである。
- golem-numerals は、[ADR 0173](0173-rc4-refactoring.md) の 3 が golem-driver のライブラリに足す。使うのは `Golem.Driver.Pdf.Flow` と `Golem.Driver.Pdf.Draw` だけなので、2 で除く。
- Hackage のパッケージでは、golem-driver のライブラリから `async` と `vector` を除き、golem-typeset のライブラリに足す。`async` は `Golem.Driver.Pdf.Flow` の段落ごとの並列の行分割だけが、`vector` は `Golem.Driver.Memo` だけが使う。golem-typeset のライブラリは、ほかに `base`、`bytestring`、`containers`、`filepath`、`text`、`time` に依存する。golem-typeset のテストは、`base`、`tasty`、`tasty-hunit`、`text` に依存する。
- golem-typeset のライブラリは golem-test-support に依存しない。テストは依存しないが、依存してもよい（[docs/adr/0087](0087-test-support-dependencies-and-shared-fixtures.md)）。
- golem-cli、golem-lsp、golem-project、golem-assemble の `build-depends` は変わらない。

パッケージは、[ADR 0173](0173-rc4-refactoring.md) の後の 28 から 29 になる。

### 順と確かめ方

この ADR は、[ADR 0173](0173-rc4-refactoring.md) の 1 から 6 がすべて main に入った後に実装する。

- 1 の出力のハッシュの一覧の比べ（`scripts/determinism/hashes.txt`）がないと、出力が変わらないことを確かめられない。
- 3 の後のパッケージの名前（golem-assemble など）で `build-depends` を書く。
- 5 は `Golem.Driver.Pdf.Flow` の `buildFlow` を分ける。モジュールを移す前に分け終えておけば、二つの変更の差分が混ざらない。

この ADR の実装は二つのプルリクエストに分ける。
一つめは「実装すること」の 1、二つめは 2 から 4 である。
どちらも、[ADR 0173](0173-rc4-refactoring.md) の「確かめ方」と同じく、次のものを変えない。

- `scripts/determinism/hashes.txt`
- `scripts/visual/pages/` の参照
- 各パッケージの `test/golden/` のファイル
- テストの期待値

CI の `determinism` ジョブが、出力が `hashes.txt` と一致することを確かめる。
プルリクエストの差分にこれらのファイルが現れたら、そのプルリクエストは出力を変えたので、整理ではない。
二つめのプルリクエストでは、移す前の `golem-driver-test` と移した後の `golem-typeset-test` のテストの名前の一覧（tasty の `--list-tests`）を比べ、`MemoSpec` と `RuleShapeSpec` のテストが一つも消えていないことを、レビューで確かめる。

## 実装しないこと

- **組むことと描くことを別のパッケージにすること**：「文脈」のとおり、同じ型と同じ依存を共有する（「メンテナーが決めること」の 1）。
- **`Golem.Driver.Pdf.Flow` を golem-layout に、`Golem.Driver.Pdf.Draw` を golem-pdf に移すこと**：同じく「メンテナーが決めること」の 1 で退ける。
- **golem-lsp が PDF の組版に依存しないようにすること**：評価と書き出しを別のパッケージに分ける必要があり、PDF の組版とは別の責務の分け方である（「メンテナーが決めること」の 6）。1 で、評価の部分が PDF のモジュールを使わないようにするところまでを行う。
- **`codeTokens` を golem-html から移すこと**：golem-typeset は golem-html に依存する（「メンテナーが決めること」の 7）。
- **PDF のテストを golem-typeset のテストに移すこと**：`MemoSpec` と `RuleShapeSpec` のほかは移さない（「メンテナーが決めること」の 5）。
- **テストのファイルを分けること**と、`PdfSpec` のように golem-driver と golem-typeset の両方を確かめるテストを書き分けること。
- **振る舞いを変えること**：[ADR 0173](0173-rc4-refactoring.md) と同じく、誤りを直す、diagnostic のメッセージを変える、性能を上げる、といった変更を混ぜない。

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから移す。

1 は、移す先のパッケージにテストを足す。
今の golem-project と golem-assemble には五つの関数がないので、足したテストはコンパイルで失敗する。

- golem-project：`styleFileId` がプロジェクトのファイルの数の `FileId` であること。`runningMetadata` が `id`、`title`、`language`、`date` と、値のある `title_reading`、`edition`、`publisher` だけを持ち、`creators` を持たないこと。`listBullets` は `bullets` がなければ `•`、`textBullets` は `・` であり、`bullets` があればそれを返すこと。
- golem-assemble：番号の書式で表せない番号の項目で、G07029 が項目の位置に出ること。書式を指定しないときは、横組みと縦組みの既定の書式で判定すること。表せる番号だけの本では、何も出ないこと。
- golem-driver の今のテスト（G07029 の `ParagraphSpec` など）が、そのまま通ること。

2 は、依存の向きを確かめる。

- golem-typeset のライブラリが、golem-driver、golem-eval、golem-emet、golem-plugin、golem-epub、golem-text、golem-lint、golem-fmt、golem-lsp、golem-cli に、直接にもほかのパッケージを通しても依存しないこと。[ADR 0173](0173-rc4-refactoring.md) の 3 が作る、`plan.json` を読む依存の向きの検査に、この規則を加える。
- 検査のスクリプトのテストは、`scripts/ci/testdata` に、golem-typeset のライブラリが golem-eval に依存する計画を置き、失敗することを確かめる。このテストを、規則を加える前に書く。
- golem-driver のライブラリから除いた依存（golem-font、golem-layout、golem-layout-spec、golem-numerals）は、残ったモジュールが一つでも取り込めばコンパイルが失敗するので、ビルドで確かめる。

バージョンの渡し方は、golem-driver の `BuildSpec` の今のテストで確かめる。
`producer` と `instanceIdInputs` に `golemVersion` を渡し、作る値が今の期待値と一致すること。

2 と 3 は、ほかに新しいテストを足さない。
今のテストがそのまま通り、「順と確かめ方」に挙げたファイルが変わらないことで確かめる。

## トレードオフ

golem-driver は、PDF の組版を知らないパイプラインの束ねに近づく。
その代わり、PDF のテストは golem-driver のスイートに残るので、golem-typeset を変えたときに走らせるテストの多くは、golem-driver のものである。
golem-typeset のテストだけを走らせても、PDF の組版のほとんどは確かめられない。
テストを移すには、評価を通さずに本を作る補助が要るが、それは [ADR 0191](0191-semantic-ir-generator-module.md) の意味論 IR の生成器とは別のもの（`style.toml` とプロジェクトを含む入力）であり、この ADR では作らない。

`renderPdf`、`renderPdfView`、`producer`、`instanceIdInputs` の型が変わるので、関数と型を変えないという [ADR 0173](0173-rc4-refactoring.md) の整理の規則からは外れる。
変わるのは引数が一つ増えることだけで、作る値は変わらないことを、`BuildSpec` と `hashes.txt` で確かめる。

五つの値を golem-project と golem-assemble に移すと、二つのパッケージの公開する関数が増える。
`listBullets` と `textBullets` の既定の印（`•` と `・`）は、出力の見た目の既定であり、`style.toml` を読むパッケージが持つのは、今の `Golem.Project.Style` の既定の値（`defaultStyle`）と同じ扱いである。
`listNumberDiagnostics` は、型が `Style` から番号の書式に変わる。

golem-typeset は golem-html に依存するので、PDF の組版が Web 経路のパッケージをリンクする。
今の golem-driver も両方に依存するので、リンクするものは増えない。

モジュールの名前を変えると、取り込みの行の差分が多くなる。
[ADR 0173](0173-rc4-refactoring.md) の 3 と同じく、2 のプルリクエストでは、名前を変えることと、バージョンの引数のほかの変更をしない。

## 決めたことの記録

- **PDF の組版を golem-driver から分けること**（2026-11-07、メンテナー）：[ADR 0173](0173-rc4-refactoring.md) の「メンテナーが決めること」の 4 に答え、分けると決めた。分け方は、新しい ADR で決めるよう求めた。この ADR がその ADR である。
- **モジュールの境界**（2026-11-07、メンテナー、[ADR 0173](0173-rc4-refactoring.md) のレビューで）：モジュールの境界は責務にもとづいて決める。行数だけを見て分けることは認めない。
- **パッケージの依存の変更**（2026-10-23、メンテナー）：golem のパッケージのあいだの `build-depends` は、テストのスイートを含め、ADR なしに変えない。この ADR の「パッケージの依存」の表が、変えるものを定める。

- **残りの項目**（2026-11-07、メンテナー）：「メンテナーが決めること」の 1 から 7 を、推奨のとおりとした。

## メンテナーが決めること

すべて決めた（「決めたことの記録」）。

1. **パッケージの数と範囲**：決めた。推奨のとおり、「文脈」の九つのモジュールと `Golem.Driver.Svg` の PDF の部分を、一つのパッケージにすることである。どれも、意味論 IR の本から PDF までを通す一つの責務に属する。
   - 退けた案の一つは、組むこと（`Golem.Driver.Pdf.Flow`）と描くこと（`Golem.Driver.Pdf.Draw`）を別々のパッケージにすることである。組む段階が golem-pdf の図版の型を使い、描く段階が組んだ結果の型を使うので、一つの責務が二つに分かれるだけである。
   - もう一つは、golem-font による `FontProvider` の実装（`Golem.Driver.Fonts`）とメモ化を、別のパッケージにすることである。実装する型（`FontProvider`、`LoadedFonts`、`Shaping`）は PDF の組版のパッケージにあり、ほかに使うパッケージがない。
   - もう一つは、組む部分を golem-layout に、描く部分を golem-pdf に入れることである。golem-layout は golem-pdf、golem-font、golem-svg、golem-html、golem-preflight に依存することになり、行分割と改ページの手順のパッケージでなくなる。golem-pdf は何を描くかを知らない PDF の書き手であり、golem-project にも依存しない。
2. **パッケージの名前**：決めた。推奨のとおり、golem-typeset とし、モジュールを `Golem.Typeset` の下に置くことである。仕様書は、行分割器とフォントエンジンを PDF 経路専用とし、Web 経路では読者側のエンジンが組むとする。Golem の中で組版をするのは PDF の経路だけなので、名前に PDF を入れなくても紛れない。
   - 退けた案の一つは、golem-pdf-typeset のように PDF を名前に入れることである。golem-pdf の一部（PDF の書き手の補助）に見える。
   - もう一つは、golem-compose のように、組むことだけを名前にすることである。描くことと PDF を書くことを含むので、範囲が名前より広い。
3. **PDF に限らない値の置き場所**：決めた。「実装すること」の 1 のとおり、`styleFileId`、`runningMetadata`、`listBullets`、`textBullets` を golem-project に、`listNumberDiagnostics` を golem-assemble に移すことである。どれも、使う型を持つパッケージに置く。
   - 退けた案の一つは、golem-typeset に置いたまま、golem-driver が取り込むことである。評価とプレーンテキストの書き出しが、PDF の組版のパッケージを使い続ける。golem-lsp を PDF の組版から切り離すときに、また移すことになる。
   - もう一つは、golem-driver に置くことである。golem-typeset も、`textBullets` のほかの四つを使う（柱の `runningMetadata`、`style.toml` の diagnostics の位置の `styleFileId`、PDF の箇条書きの印の `listBullets`、組む前の G07029 の `listNumberDiagnostics`）ので、golem-typeset が golem-driver に依存することになり、依存が循環する。
4. **Golem のバージョンの渡し方**：決めた。推奨のとおり、`renderPdf`、`renderPdfView`、`producer`、`instanceIdInputs` の引数で受け取ることである。バージョンを入力の一部とする決まり（[docs/adr/0002](0002-determinism.md)）のとおり、PDF の組版は外から受け取った値で Producer とインスタンス ID を作る。変わる呼び出しは、`Golem.Driver` の一か所と、テストの `renderPdf` の一か所と、`BuildSpec` の `producer` と `instanceIdInputs` である。
   - 退けた案の一つは、`PdfInput` の欄にすることである。入力として読みやすいが、テストが `PdfInput` を位置で作る 10 か所がすべて変わる。
   - もう一つは、golem-typeset でも `VERSION` を Template Haskell で埋め込むことである。`VERSION` を読む箇所が二つになり、`extra-source-files` の `VERSION` の symbolic link も二つ要る。
   - もう一つは、`Golem.Driver.Version` を下の層のパッケージに移すことである。golem-cli の取り込みが変わり、バージョンを持つことは PDF の組版の責務でもない。
5. **テストの置き場所**：決めた。推奨のとおり、`MemoSpec` と `RuleShapeSpec` だけを golem-typeset に移し、ほかの PDF のテストは golem-driver に残すことである。ほかのテストは、golem-driver の `evaluateProject` で評価したプロジェクトを組むので、golem-driver を通して確かめるテストである。
   - 退けた案は、PDF のテストをすべて golem-typeset に移すことである。golem-typeset のテストが golem-driver に依存するか、評価を通さずに入力を作る補助が要る。前者は依存の向きが逆になり、後者はテストの中身が変わるので、整理と混ざる。
6. **golem-lsp を PDF の組版から切り離すか**：決めた。推奨のとおり、この ADR では扱わず、評価と書き出しを分ける項目として docs/roadmap.md に載せることである。この ADR の 1 の後は、評価の部分が PDF のモジュールを使わないので、評価を別のパッケージに分けられる。
   - 退けた案は、この ADR で評価を新しいパッケージに分けることである。`Evaluated` の型と、評価と書き出しの両方が使う補助（`docStyles`、`localStylesOf`、`runningVars` など）の境目を読む必要があり、PDF の組版とは別の責務の分け方である。
7. **golem-html への依存**：決めた。推奨のとおり、golem-typeset が golem-html に依存し、`codeTokens` をそのまま使うことである。今の golem-driver も golem-html に依存しているので、リンクするものは増えない。
   - 退けた案は、`codeTokens` を golem-layout の `Golem.Layout.Code` に移すことである。golem-layout が skylighting に依存することになり、コードの字句の分け方をどのパッケージが持つかという別の問いになる。

## 参考文献

- [ADR 0173](0173-rc4-refactoring.md)、[ADR 0191](0191-semantic-ir-generator-module.md)、[docs/adr/0002](0002-determinism.md)、[docs/adr/0004](0004-binary-distribution-and-release.md)、[docs/adr/0087](0087-test-support-dependencies-and-shared-fixtures.md)、[docs/adr/0090](0090-html-settings-conversion-stays-in-driver.md)、[docs/adr/0140](0140-ci-split-test-runners-and-visual-pdfs-first.md)
- [golem-driver ADR 0001](../golem-driver/adr/0001-build-pipeline.md)、[golem-driver ADR 0002](../golem-driver/adr/0002-pdf-pipeline.md)、[golem-driver ADR 0023](../golem-driver/adr/0023-code-block-book-features.md)、[golem-driver ADR 0028](../golem-driver/adr/0028-rule-colour-and-style.md)、[golem-driver ADR 0030](../golem-driver/adr/0030-ligature-text-layer.md)
- [golem-layout-spec ADR 0001](../golem-layout-spec/adr/0001-page-geometry.md)、[golem-pdf ADR 0001](../golem-pdf/adr/0001-deterministic-pdf-writer.md)、[golem-pdf ADR 0009](../golem-pdf/adr/0009-svg-figures.md)、[golem-font ADR 0001](../golem-font/adr/0001-shaping-and-metrics.md)
