# ADR 0173: rc4 の前に、出力を変えずにコードを整理する

ステータス: 採択→整理のプルリクエストがマニュアルの原稿を直して見た目の回帰テストの参照を変えることは [ADR 0211](0211-record-what-implementations-decided-found-by-the-review-of-2026-11-08.md)

## 文脈

ロードマップの v0.1.0-rc4 の最初の項目は「リファクタリング」である（[docs/roadmap.md](../roadmap.md)）。
v0.1.0-rc3 までに入れたコードの、モジュールの境界、重複した処理、大きくなった関数、テストの補助を見直し、出力を変えずに、決定性の検査で確かめる、とある。

見直しを印象で始めると、手を付ける範囲が決まらない。
そこで、main の `50b9fca8` を測ってから、直すものを選んだ。
測り方は、ファイルの行数を `fd` と `wc` で、関数の長さを `awk` で数えた（2026-11-06）。
関数の長さは、最上位の束縛の最初の行から、次の最上位の宣言かコメントの前までの、字下げした最後の行までの行数である。
シグネチャと `where` の束縛を含む。
数えたスクリプトはコミットしない。

行数は、読む候補を探す手がかりにだけ使う。
関数とモジュールを分けるかどうかは、行数ではなく責務で決める（「決めたことの記録」）。

### 規模

`modules/` には 25 のパッケージがある。
`src/` と `app/` の Haskell は 46,336 行、`test/` は 41,105 行である。
生成したパーサー（golem-parser と golem-emet の `Generated.hs`）と、golem-parser のテストの `StrippedGrammar.hs` は数えていない。

1,000 行を超える手書きのモジュールは次の九つである。

| モジュール | 行数 |
| --- | --- |
| golem-eval の `Golem.Eval.File` | 2,675 |
| golem-project の `Golem.Project.Style` | 2,603 |
| golem-driver の `Golem.Driver.Pdf.Flow` | 2,307 |
| golem-emet の `Golem.Emet.Check` | 1,663 |
| golem-pdf の `Golem.Pdf.Import` | 1,554 |
| golem-driver の `Golem.Driver` | 1,175 |
| golem-html の `Golem.Html` | 1,170 |
| golem-driver の `Golem.Driver.Pdf.Draw` | 1,088 |
| golem-svg の `Golem.Svg` | 1,035 |

### 大きくなった関数

`src/` と `app/` の最上位の束縛は 4,395 個あり、50 行以上が 79 個、100 行以上が 23 個、200 行以上が 7 個だった。
150 行以上のものを候補にし、中身を読んで、抱えている責務の数で三つに分けた。

一つめは、データの表である。
UAX #50 の縦組みの向きの表（`voRanges`、899 行）、HTML の CSS の文字列（`css`、253 行）、SVG の色の名前の表（`names`、151 行）がこれに当たる。
責務は表を持つことの一つであり、長いのは表の行が多いからである。

二つめは、一つの仕組みを一か所に書いたものである。
LSP の要求ごとのハンドラーを並べた `handlers`（224 行、[`Server.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-lsp/src/Golem/Lsp/Server.hs#L171-L394)）は、要求の一覧そのものである。
Emet の評価器の `evalCallLimited`（211 行、[`Eval.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-emet/src/Golem/Emet/Eval.hs#L159-L369)）は、手数と深さを数える一つのループである。
Knuth-Plass の `breakParagraph`（200 行、[`KnuthPlass.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-layout/src/Golem/Layout/KnuthPlass.hs#L212-L411)）は、TeX の行分割の手順を、段階ごとに `where` の束縛に分けて持つ。
どれも責務は一つである。
行数を理由に分けると、一つの表や手順が複数の関数に散るだけで、責務は分かれない。

三つめが、別々の責務を一つの関数に抱えたものである。

- **`buildFlow`**（463 行、[`Flow.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L1401-L1863)）：PDF の本文の単位ごとの組版の環境と行長、注と傍注、図版のキャプションと回り込み、表、行への番号付け、見出しと目次の項目、コードブロックを、一つの `do` とその `let` の中で扱う。コメントが「1.」から「3.」の段階を付けているが、段階は関数に分かれていない。
- **`styleChecks`**（205 行、[`Style.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-project/src/Golem/Project/Style.hs#L2007-L2211)）：`style.toml` の検査を、十あまりの内包表記（G03006、G03008、G03011 などのコード）をつないだ一つの式にし、それぞれの検査の本体を `where` に持つ。検査の規則ごとに責務が分かれている。
- **`writeTargetsChecked`**（157 行、[`Driver.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver.hs#L994-L1150)）：`style.toml` から HTML の設定を組み立てることと、四つのターゲットの書き出しを、一つの関数で行う。

150 行に満たない関数は、中身を読んでいない。
短い関数が別々の責務を抱えていることもあるので、この選び方で見つかるのは、長くて責務の多いものだけである。

### 重複した処理

二つ以上のパッケージの `src/` に同じ名前の最上位の束縛がある組を洗い出し、本体を読み比べた。
名前が同じだけで中身の違うもの（`splitLines`、`naturalOf`、`toSp`、`encodeInlines` など）を除くと、同じ処理を写したものは次の四つだった。

- **原稿の読み込みの段階の検査**：先頭の BOM（G01002）、UTF-8 として不正なバイト列（G01001）、CR（G01003）を調べる処理が、golem-parser の [`Read.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-parser/src/Golem/Parser/Read.hs#L35-L129) と golem-emet の [`Parse.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-emet/src/Golem/Emet/Parse.hs#L30-L76) に二つある。`bomDiagnostic` と `invalidOffset` は字句まで同じで、golem-emet の側のコメントは、golem-parser のものと同じだと書いている。golem-emet は golem-parser に依存しないので、写したと考えられる（推測）。
- **`divSp`**：golem-driver の [`RuleShape.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/RuleShape.hs#L116-L118) と golem-layout の [`RuleArea.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-layout/src/Golem/Layout/RuleArea.hs#L43-L45) に、コメントまで同じ 2 行がある。
- **`isqrt`**：golem-eval の [`Number.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-eval/src/Golem/Eval/Number.hs#L86-L96) と golem-svg の [`Number.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-svg/src/Golem/Svg/Number.hs#L156-L161) にある。初期値の取り方だけが違う。
- **意味論 IR の生成器**：golem-doc のテストの [`Gen.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-doc/test/Gen.hs) と golem-driver のテストの [`IRGen.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/test/IRGen.hs) は、モジュールの宣言を除く 179 行（空行を除くと 161 行）が一致する（`diff` で確かめた）。`IRGen.hs` のコメントは、[ADR 0162](0162-calling-emet-functions-from-gm.md) のために golem-doc のテストから写したと書いている。

`isqrt` の重複は、golem-svg が golem のどのパッケージにも依存しないと決めたことの結果である（[仕様書の「モジュール構成」](../specifications.md#モジュール構成)）。
意味論 IR の生成器は、新しいパッケージに移す（[ADR 0191](0191-semantic-ir-generator-module.md)）。

### テストの補助

同じパッケージのテストの、二つ以上のファイルに同じ名前の補助があるものは、66 の名前、176 の定義だった。
本体まで同じことを確かめたものの多い順に挙げる。

- golem-plugin のテストの `cbor`（CBOR の項をバイト列にする）が七つのファイルに、`callSpan`（呼び出しの位置）が六つのファイルに、同じ本体である（[`Main.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-plugin/test/Main.hs#L65-L78) など）。
- golem-lsp のテストの `codesOf`（ワークスペースのあるファイルの diagnostic のコード）が、`Main.hs`、`FunctionsLspSpec.hs`、`TableWatchSpec.hs`、`TomlSpec.hs` の四つに同じ本体である。
- golem-driver のテストの `codesOf` が四つのファイルにある。うち三つはコードの文字列の一覧を返す同じ処理で、二つは diagnostic の一覧を、一つは `BuildResult` を受け取り、三通りの書き方で書いている。golem-driver のテストには共通の補助 [`Support.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/test/Support.hs) がある。
- golem-project のテストの `offsetOf`（原稿の中の文字列のバイトの位置）が五つのファイルにある。三つは `offsetOf src needle`、[`OutputCharsSpec.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-project/test/OutputCharsSpec.hs#L33-L35) は `offsetOf needle src` で、引数の順が逆である。型はどちらも `Text -> Text -> Int` なので、取り違えてもコンパイルは通る。

パッケージをまたぐテストの補助は、golem-test-support に置けない。
golem-test-support は golem のパッケージに依存しないと決めているからである（[ADR 0087](0087-test-support-dependencies-and-shared-fixtures.md)）。
意味論 IR の生成器は golem-doc の型を使うので、ここに当たる。

### モジュールの境界

各パッケージの cabal ファイルのライブラリの `build-depends` を、仕様書のモジュールの依存の図と突き合わせた。
図の 31 本の矢印はどれも直接の依存であり、直接の依存（golem-syntax と golem-length を除く）はどれも図の矢印でたどれる。
図とコードは一致している。

食い違いは一か所の文にだけある。
仕様書は「golem-syntax は golem-regex、golem-font、golem-svg、golem-fixtures、golem-test-support を除くすべてのモジュールが使う」と書くが、golem-length も golem-syntax を使わない（golem-length の `build-depends` は `base` と `text` だけである）。

図と一致していても、境界が責務に沿うとは限らない。
責務の混ざったパッケージとして、golem-doc と golem-driver を調べた。

### golem-doc の責務

仕様書の図は、golem-doc を「意味論 IR と文書構造（S1）の集約」とする。
cabal ファイルの `synopsis` は「The semantic IR of Golem」だけである（[`golem-doc.cabal`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-doc/golem-doc.cabal#L4)）。
公開する 10 のモジュールを、import と、ほかのパッケージからの使われ方で読むと、責務は次の四つに分かれる。

| 責務 | モジュール | golem のパッケージへの依存 |
| --- | --- | --- |
| 意味論 IR とプラグインの ABI | `Golem.Doc.IR`、`Golem.Doc.Cbor`、`Golem.Doc.Validate`、`schema/golem-doc.cddl` | golem-length、golem-parser、golem-syntax |
| 文書構造（S1）の集約 | `Golem.Doc.Assemble`、`Golem.Doc.Collation`、`Golem.Doc.ListMarkers`、`Golem.Doc.Numbering` | 上の IR と、下の数の表記、golem-syntax |
| 参考文献 | `Golem.Doc.Bibliography`、`Golem.Doc.Bibliography.Csl` | golem-syntax |
| 数の表記 | `Golem.Doc.Numerals` | なし（`base` と `text` だけ） |

- IR の型が golem-parser に依存するのは、遅延した式 `DeferredExpr` が原稿の式の構文木を持つからである（[`IR.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-doc/src/Golem/Doc/IR.hs#L327)）。
- 参考文献の二つのモジュールは、IR も集約も使わない。CSL-JSON を読み、一件の書式を作る。
- 数の表記は、漢数字、丸数字、`style.toml` の番号の書式を作る。集約のほかに、golem-layout、golem-html、golem-text、golem-driver が直接に使う。golem-layout がこれを使うのは、IR の数 `Number` を漢数字で組むためである（[`Japanese.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-layout/src/Golem/Layout/Japanese.hs#L39)）。
- プラグインの宣言するチャネルの型 `ChannelDecl` と `ChannelOrder` は、集約のモジュール `Golem.Doc.Assemble` にある（[`Assemble.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-doc/src/Golem/Doc/Assemble.hs#L69-L80)）。一方で、その形は ABI の CDDL の `channel-decl` が定める（[`golem-doc.cddl`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-doc/schema/golem-doc.cddl#L146)）。golem-plugin と golem-eval のライブラリが `Golem.Doc.Assemble` から取り込むのは、この二つの型だけである。

ほかのパッケージのライブラリは、次のモジュールを使う（`rg` で import を数えた）。

| パッケージ | 使う golem-doc のモジュール |
| --- | --- |
| golem-cli | `Cbor` |
| golem-emet | `IR`、`Validate` |
| golem-eval | `IR`、`Assemble`（`ChannelDecl` だけ） |
| golem-plugin | `IR`、`Cbor`、`Validate`、`Assemble`（`ChannelDecl` と `ChannelOrder` だけ） |
| golem-project | `Assemble`（`NoteNumbering` だけ）、`ListMarkers` |
| golem-layout | `IR`、`Numerals` |
| golem-epub | `Assemble`、`Numbering` |
| golem-html、golem-text | `IR`、`Assemble`、`Bibliography`、`ListMarkers`、`Numbering`、`Numerals` |
| golem-driver | `IR`、`Assemble`、`Bibliography`、`Bibliography.Csl`、`ListMarkers`、`Numbering`、`Numerals` |
| golem-lsp | なし |

IR だけを使うパッケージ（golem-cli、golem-emet、golem-plugin、golem-eval）も、集約、参考文献、数の表記をリンクする。
golem-lsp のライブラリは `build-depends` に golem-doc を挙げるが、`Golem.Doc` のモジュールを一つも import しない（[`golem-lsp.cabal`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-lsp/golem-lsp.cabal#L29)）。

### golem-driver の大きさ

golem-driver の `src/` の 7,199 行のうち 4,050 行（56%）が PDF の組版と描画（`Golem.Driver.Pdf` とその下）である。
仕様書の図は golem-driver を「パイプラインの束ね」とするが、PDF の組版の多くがここにある。
golem-lsp は golem-driver に依存するので、LSP もこのコードをリンクする。
責務で分けるなら、PDF の組版もパイプラインの束ねから分かれる。
メンテナーは分けると決めた。
分け方は、golem-layout と golem-layout-spec との分担を含めて読み直し、[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) で決める（「メンテナーが決めること」の 4）。

### 今の安全網

「出力を変えない」を確かめる仕組みは、今は次の四つである。

- **ゴールデンのテスト**：七つのパッケージの `test/golden/` に 57 のファイルがある。golem-driver のものは 21 で、HTML、EPUB、プレーンテキスト、`golem new` の雛形、PDF の一部の値を固定する。
- **見た目の回帰テスト**：17 の PDF のページを 72 dpi で描き、ページごとのハッシュをコミットした参照と比べる（[ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md)）。ゴールデンのテストと同じく、コミットした期待値と比べるので、コミットをまたいだ変化を見つける。ただし PDF の画像だけを見るので、フォントのサブセット、メタデータ、画像と図版の中身の変化は見えない。
- **決定性の検査**：`scripts/determinism.sh` は、出力のファイル、`--format json` の標準出力と標準エラー出力、終了コードのハッシュの一覧を作る。CI は、同じコミットの x86-64 と aarch64 の一覧を比べるだけである。
- **環境を変えた検査**：同じコミットで環境だけを変えて比べる（[ADR 0029](0029-environment-variation-determinism-test.md)）。

ロードマップの「出力は変えず、決定性の検査で確かめる」は、今の決定性の検査では成り立たない。
決定性の検査は、コミットをまたいだ変化を見ないからである。
[2026-10-20 のロードマップのレビュー](../audits/2026-10-20-roadmap-review.md) がこの点を指摘し、ロードマップは v1.0.0 に「コミットをまたいだ出力の比べ」を置いた。

### rc4 のプラグインの仕上げ

ロードマップの項目は「rc4 のプラグインの仕上げに備える」と書くが、今の v0.1.0-rc4 の節に、プラグインを変える項目はない。
プラグインのための整理は、テストの補助の重複（golem-plugin の `cbor` と `callSpan`）と、IR を golem-doc に分けること（プラグインの ABI を持つパッケージが IR だけになる）を扱う。

## 実装すること

整理は、次の順に、それぞれ一つのプルリクエストで行う。
1 の検査が入るまで、2 から 6 に手を付けない。

### 1. コミットをまたいだ出力の比べ

v1.0.0 の「コミットをまたいだ出力の比べ」を、この ADR に前倒しする（「メンテナーが決めること」の 1）。

- `scripts/determinism.sh` に、マニュアルを組まない `--no-manuals` を加える。マニュアルは奥付にコミットのハッシュを書くので、一覧がコミットごとに変わる。マニュアルのページは見た目の回帰テストが比べる。
- `--no-manuals` で作った一覧を `scripts/determinism/hashes.txt` としてコミットする。
- CI の `determinism` ジョブは、今の x86-64 と aarch64 の比べに加えて、x86-64 の一覧からマニュアルの行を除いたものを `hashes.txt` と比べる。違えば、違う行を書いて失敗する。
- 意図して出力を変えるプルリクエストは、同じプルリクエストで `hashes.txt` を書き直す。`VERSION` を上げると PDF の Producer とインスタンス ID が変わるので、リリースのプルリクエストも書き直す。
- 仕様書の「決定性の検査は、同じコミットの出力どうしだけを比べる」を、この検査に合わせて書き直し、ロードマップの v1.0.0 から項目を消す。

### 2. 読み込みの段階の検査と `divSp` を下の層に移す

- BOM、UTF-8、CR の検査（`bomDiagnostic`、`invalidOffset`、CR の G01003）を golem-syntax の新しいモジュールに移し、golem-parser と golem-emet がそれを使う。golem-syntax はすでに `bytestring` と `text` に依存し、golem-parser と golem-emet はすでに golem-syntax に依存する。
- `divSp` を golem-length の `Golem.Length` に移し、golem-driver と golem-layout がそれを使う。二つはすでに golem-length に依存する。

### 3. golem-doc を責務で分ける

「文脈」の「golem-doc の責務」の四つの責務を、四つのパッケージにする（「メンテナーが決めること」の 2 と 5）。
golem-doc の名前は意味論 IR に残す。
ABI の CDDL の `schema/golem-doc.cddl` と、それを読む `scripts/ci/abi-version.sh` の道筋が変わらないからである。

| パッケージ | モジュール（今の名前から） | golem のパッケージへの依存 |
| --- | --- | --- |
| golem-doc（意味論 IR とプラグインの ABI） | `Golem.Doc.IR`、`Golem.Doc.Cbor`、`Golem.Doc.Validate` | golem-length、golem-parser、golem-syntax |
| golem-assemble（新規、文書構造の集約） | `Golem.Assemble`（`Golem.Doc.Assemble`）、`Golem.Assemble.Collation`、`Golem.Assemble.ListMarkers`、`Golem.Assemble.Numbering` | golem-doc、golem-numerals、golem-syntax |
| golem-bibliography（新規、参考文献） | `Golem.Bibliography`、`Golem.Bibliography.Csl` | golem-syntax |
| golem-numerals（新規、数の表記） | `Golem.Numerals` | なし |

- モジュールの名前は、ほかのパッケージと同じく、パッケージの名前に合わせる（golem-xxx なら `Golem.Xxx` の下）。名前を変えるだけで、関数と型は変えない。
- `ChannelDecl` と `ChannelOrder` を、`Golem.Doc.Assemble` から `Golem.Doc.IR` に移す。形を CDDL が定めるので、ABI の側に置く。集約は golem-doc から取り込む。
- テストも責務に沿って移す。golem-doc の `AssembleSpec`、`ListMarkersSpec`、`NumberingSpec` は golem-assemble に、`BibliographySpec` と `CslSpec` は golem-bibliography に、`Main.hs` の漢数字のテストは golem-numerals に移す。golem-doc のテストには、IR、CBOR、CDDL、検証のテストが残る。
- 新しい三つのパッケージの ADR は、`docs/golem-assemble/adr/` のように、パッケージの名前のディレクトリに置く。golem-doc の今の ADR は、コミット済みなので `docs/golem-doc/adr/` に残す。

### 4. テストの補助をパッケージの中でまとめる

- golem-plugin のテストに補助のモジュールを置き、`cbor` と `callSpan` を移す。`FuelSpec.hs` の `callSpan` は値が違うので残す。
- golem-lsp のテストに補助のモジュールを置き、`codesOf` を移す。
- golem-driver のテストの `codesOf` のうち、コードの文字列を返す三つを、diagnostic の一覧を受け取る `Support.hs` の一つにする。`BuildResult` を渡していた箇所は `brDiagnostics` を通して渡す。
- golem-project のテストの `offsetOf` を一つにし、引数の順を `offsetOf src needle` にそろえる。

補助のモジュールは、テストのスイートの `other-modules` に加える。
`build-depends` は変えない。
パッケージをまたぐ意味論 IR の生成器は、[ADR 0191](0191-semantic-ir-generator-module.md) が扱う。

### 5. 別々の責務を抱えた関数を、責務ごとに分ける

関数は責務で分け、行数では分けない（「メンテナーが決めること」の 3）。
分けた関数は、名前と型で一つの責務を言えるものにする。
次のような関数は作らない。

- 元の関数の何行目から何行目かを抜き出しただけで、名前が責務でなく段落を指すもの（`step2` のようなもの）。
- 呼び出し元の束縛をまとめて引数に受け取り、関係のない値の組を返すもの。
- 一か所からしか呼ばれず、読むときに呼び出し元と行き来しないと意味の分からないもの。

ほかの手続き型の言語で、DRY の名のもとに、引数と戻り値から何をするのか分からない `void` の関数ができるのと同じ問題である。
Haskell では副作用のない `void` の関数は書けないが、引数と戻り値の組で同じことが起こる。

「文脈」の三つめに挙げた `buildFlow`、`styleChecks`、`writeTargetsChecked` を、次の責務で分ける。

- `buildFlow` は、本文の単位ごとの組版の環境と行長、注と傍注、図版のキャプションと回り込み、表、行への番号付け、見出しと目次の項目、コードブロックを、それぞれ一つの関数にする。分けた関数の群れが一つの責務になるときだけ（注と傍注など）、`Golem.Driver.Pdf` の下の新しいモジュールに置く。`Flow.hs` の行数は、モジュールを分ける理由にしない。
- `styleChecks` は、検査の規則ごと（diagnostic のコードごと）に一つの関数にし、`styleChecks` はそれをつなぐだけにする。diagnostics の並びの順は変えない。
- `writeTargetsChecked` は、HTML の設定の組み立てと、ターゲットごとの書き出しを分ける。

どれも、同じパッケージの中で行い、パッケージの公開するモジュールと関数の型は変えない。

### 6. 仕様書を直す

- 「モジュール構成」の「golem-syntax は ... を除くすべてのモジュールが使う」の除くものに、golem-length と golem-numerals を加える。
- 「モジュール構成」の図と、モジュールの説明を、3 の分け方に合わせて書き直す。golem-doc の箱は「意味論 IR とプラグインの ABI」とし、golem-assemble、golem-bibliography、golem-numerals の箱を足す。
- 仕様書のほかの節が書くモジュールの名前（`Golem.Doc.Bibliography`、`Golem.Doc.Bibliography.Csl.decodeCslJson` など）を、新しい名前に直す。
- docs/diagnostics.md の「番号の区分」の、04（文書の組み立て）の主なモジュールを golem-assemble にする。

### パッケージの依存

この ADR は、golem のパッケージのあいだの `build-depends` を、次のように変える（「メンテナーが決めること」の 2）。
2 と 4 の移動は、すでにある依存の上で行う。
足すものと除くもののほかは変えない。

| パッケージの構成要素 | 足す | 除く |
| --- | --- | --- |
| golem-assemble のライブラリ（新規） | golem-doc、golem-numerals、golem-syntax | |
| golem-assemble のテスト（新規） | golem-assemble、golem-doc、golem-numerals、golem-syntax | |
| golem-bibliography のライブラリ（新規） | golem-syntax | |
| golem-bibliography のテスト（新規） | golem-bibliography | |
| golem-numerals のライブラリ（新規） | なし | |
| golem-numerals のテスト（新規） | golem-numerals | |
| golem-driver のライブラリ | golem-assemble、golem-bibliography、golem-numerals | |
| golem-driver の三つのテスト（`golem-driver-test`、`golem-driver-global-test`、`golem-driver-parallel-test`） | golem-assemble、golem-bibliography | |
| golem-html のライブラリ、golem-text のライブラリ | golem-assemble、golem-bibliography、golem-numerals | |
| golem-html のテスト、golem-text のテスト | golem-assemble、golem-bibliography | |
| golem-epub のライブラリ | golem-assemble | golem-doc |
| golem-epub のテスト | golem-assemble | |
| golem-project のライブラリとテスト | golem-assemble | golem-doc |
| golem-layout のライブラリ | golem-numerals | |
| golem-lsp のライブラリ | | golem-doc（使っていない） |

golem-driver の三つのテストは、どれも `Support.hs` を持ち、`Support.hs` が集約と参考文献を取り込むので、三つとも足す。
golem-cli、golem-emet、golem-eval、golem-plugin は、`ChannelDecl` と `ChannelOrder` が golem-doc に移るので、変わらない。
テストのスイートがどの golem のパッケージに依存してよいかは、[ADR 0191](0191-semantic-ir-generator-module.md) の生成器のパッケージのほかに変えない。

### 確かめ方

2 から 6 のプルリクエストは、次のものを変えない。

- `scripts/determinism/hashes.txt`
- `scripts/visual/pages/` の参照
- 各パッケージの `test/golden/` のファイル
- テストの期待値（補助の呼び出しと、移したテストのモジュールの名前を書き換えるほかに、テストの中身を変えない）

CI は、出力がこれらのファイルと一致することを確かめる。
プルリクエストの差分にこれらのファイルが現れたら、そのプルリクエストは出力を変えたので、整理ではない。
レビューでそれを見る。

3 のプルリクエストでは、移す前と後のテストの名前の一覧（tasty の `--list-tests`）を比べ、テストが一つも消えていないこともレビューで確かめる。

## 実装しないこと

- **PDF の組版を golem-driver から別のパッケージに移すこと**：[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) で扱う（「メンテナーが決めること」の 4）。
- **意味論 IR の生成器を共有すること**：[ADR 0191](0191-semantic-ir-generator-module.md) で扱う。
- **`isqrt` を共有すること**：golem-svg が golem のパッケージに依存しないことを守る。
- **データの表、LSP のハンドラーの一覧、Emet の評価器のループ、Knuth-Plass の行分割を分けること**：どれも責務が一つなので、分けない（「文脈」の一つめと二つめ）。
- **行数を理由にモジュールや関数を分けること**：`Golem.Eval.File` と `Golem.Project.Style` は、責務を調べていないので、この ADR では分けない（「トレードオフ」）。
- **テストのファイルを分けること**と、同じ名前でも中身の違うテストの補助をまとめること。
- **振る舞いを変えること**：誤りを直す、diagnostic のメッセージを変える、性能を上げる、といった変更は、この ADR の整理に混ぜない。整理の途中で見つけた不具合は、仕様書の「既知の不具合」かロードマップに載せる。
- **測ったスクリプトを残すこと**と、関数の長さの上限を CI で強いること。行数は分ける基準にしないので、上限を強いる理由がない。

## テスト設計

1 は、検査そのものを確かめる。

- `scripts/determinism.sh --no-manuals` の一覧に、`manual/` と `manual-dev/` の行がないこと。
- `--no-manuals` を付けないときの一覧が、今と同じであること（x86-64 と aarch64 の比べは変わらない）。
- 比べる手順が、一致する一覧で成功し、一行のハッシュが違う一覧、行が足りない一覧、行が多い一覧で失敗し、違う行を書くこと。`scripts/ci/testdata` にある、ほかの検査のスクリプトのテストと同じ形で書く。
- 検査を入れたプルリクエストで、CI の `determinism` ジョブが `hashes.txt` と一致すること。

2 は、移す前に、移す先のパッケージにテストを足す。

- golem-syntax：BOM、不正な UTF-8（途中、末尾の切れた多バイト文字）、CR、CRLF のそれぞれで、今の golem-parser と golem-emet と同じ diagnostic（コード、位置、メッセージ）になること。golem-parser と golem-emet の今のテストは、そのまま通ること。
- golem-length：`divSp` が負の数を負の無限大の向きに丸めること。

3 は、移したテストがそのまま通ることと、依存の向きを確かめる。

- golem-doc のライブラリが、golem-assemble、golem-bibliography、golem-numerals に依存しないこと。cabal の解決した計画（`plan.json`）を読んで確かめる。
- golem-bibliography と golem-numerals が、golem-doc に依存しないこと。同じく計画で確かめる。
- golem-plugin のテストの、プラグインの宣言するチャネルを読むテストが、そのまま通ること。

依存の向きの検査は、`scripts/ci/test-only-deps.sh` と同じく `plan.json` を読むスクリプトにし、CI の `build` ジョブで走らせる。
そのスクリプトのテストは、`scripts/ci/testdata` に、逆向きの依存を持つ計画を置いて、失敗することを確かめる。

4 と 5 は、新しいテストを足さない。
今のテストがそのまま通り、「確かめ方」に挙げたファイルが変わらないことで確かめる。

## トレードオフ

1 を前倒しすると、出力を変えるプルリクエストは、`hashes.txt` も書き直すことになる。
今は見た目の回帰テストの参照だけを書き直せばよかったので、手間が一つ増える。
その代わり、HTML、EPUB、プレーンテキスト、PDF のバイト列、diagnostics の変化が、コミットをまたいで見える。
画像だけを比べる見た目の回帰テストでは、整理の誤りでフォントのサブセットやメタデータが変わっても通ってしまう。

`hashes.txt` はハッシュの一覧なので、変わったことは分かるが、どう変わったかは分からない。
どう変わったかは、変わった入力を手元で組んで比べる。

golem-doc を四つに分けると、パッケージが 25 から 28 に増え、cabal ファイルと `build-depends` の行が増える。
golem-numerals は 81 行の一つのモジュールである。
その代わり、プラグインの ABI を持つパッケージが IR だけになり、golem-cli、golem-emet、golem-eval、golem-plugin は集約も参考文献もリンクしない。
集約や参考文献の書式を変えたときに、ABI を持つパッケージが変わらないことが、依存の向きで分かる。

モジュールの名前を変えると、取り込みの行の差分が多くなる。
差分は取り込みの行の書き換えだけだが、レビューで中身の変更と混ざらないように、3 のプルリクエストでは名前を変える以外の変更をしない。

関数を責務で分けると、関数の数は増えるが、短くなるとは限らない。
`buildFlow` から分けた関数のどれかが 150 行を超えて残っても、責務が一つならそのままにする。

`Golem.Eval.File`（2,675 行）と `Golem.Project.Style`（2,603 行）は大きいまま残る。
行数は分ける理由にならないが、行数が大きいので、責務が混ざっていても気付きにくい。
rc4 の段落スタイルの項目（行揃え、段落の前後のアキ）は `Golem.Project.Style` を、原稿の中の言語の切り替えは `Golem.Eval.File` を変えると考えられる（推測）。
それらの項目を実装するときに責務を読み、混ざっていれば別の ADR で分ける。

## 決めたことの記録

- **ロードマップの項目**（[docs/roadmap.md](../roadmap.md) の v0.1.0-rc4「リファクタリング」）：v0.1.0-rc4 の作業の前に、rc3 までのコードの、モジュールの境界、重複した処理、大きくなった関数、テストの補助を見直す。出力は変えず、決定性の検査で確かめる。
- **パッケージの依存の変更**（2026-10-23、メンテナー）：golem のパッケージのあいだの `build-depends` は、テストのスイートを含め、ADR なしに変えない。
- **出力が変わらないことの確かめ方**（2026-11-07、メンテナー）：出力のハッシュの一覧を CI で比べて確かめる。
- **モジュールの境界**（2026-11-07、メンテナー）：モジュールの境界は責務にもとづいて決める。少なくとも意味論 IR は分ける。
- **関数の分け方**（2026-11-07、メンテナー）：行数だけを見て関数を分けることは認めない。つねに責務で分ける。手続き型の言語で、DRY の名のもとに戻り値が `void` の意味の分からない関数ができるのと同じ問題であり、Haskell でもその形は起こりうる。
- **意味論 IR の生成器**（2026-11-07、メンテナー）：生成器は、新しいモジュールを作る ADR で扱う（[ADR 0191](0191-semantic-ir-generator-module.md)）。
- **PDF の組版を golem-driver から分けること**（2026-11-07、メンテナー）：分ける。分け方は、新しく作る ADR で決める（[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md)）。
- **golem-doc の意味論 IR のほかの分け方**（2026-11-07、メンテナー）：推奨のとおり、集約、参考文献、数の表記をそれぞれ一つのパッケージにする。
- **影響の大きい点**（2026-11-07、メンテナー）：この ADR の多くの `build-depends` の変更は問題ない。正しい設計のために受け入れる。同じ日に、[ADR 0177](0177-note-mark-style-and-numerals.md) で注のある縦組みの本の PDF がすべて変わること、[ADR 0183](0183-tagged-pdf-and-pdf-a.md) のタグ付けの大きな変更、実装の順（[ADR 0189](0189-paragraph-alignment-spacing-and-end-indent.md) を [ADR 0180](0180-verse-spacing-and-stanza-breaks.md) の前に、[ADR 0183](0183-tagged-pdf-and-pdf-a.md) を [ADR 0187](0187-inline-language-switch.md) と [ADR 0188](0188-headings-beyond-level-3.md) の前に）も、同じ理由で受け入れた。

## メンテナーが決めること

すべて決めた（「決めたことの記録」）。

1. **出力が変わらないことを何で確かめるか**：決めた。v1.0.0 の「コミットをまたいだ出力の比べ」をこの ADR の最初のプルリクエストに前倒しし、出力のハッシュの一覧をコミットして CI で比べる。
2. **パッケージの依存を変えるか**：決めた。モジュールの境界を責務で決め、少なくとも意味論 IR を golem-doc に分ける。そのための `build-depends` の変更は「パッケージの依存」の表のとおりである。
3. **関数を分ける基準**：決めた。行数ではなく、つねに責務で分ける。この ADR で分けるのは、別々の責務を抱えた三つの関数（`buildFlow`、`styleChecks`、`writeTargetsChecked`）である。
4. **PDF の組版を golem-driver から分けるか**：決めた。分ける。この ADR では分けず、責務の境目を調べる [ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) で分け方を決める。
   - 退けた案は、この ADR で `Golem.Driver.Pdf` とその下を新しいパッケージに移すことである。golem-driver の PDF のコードは、golem-layout と golem-layout-spec の手前の組み立て（`buildFlow`）と、golem-pdf への描画（`Golem.Driver.Pdf.Draw`）を含む。どこまでが一つの責務かを読まずに移すと、行数で分けるのと同じになる。
5. **golem-doc の意味論 IR のほかをどう分けるか**：決めた。「文脈」の四つの責務のとおり、集約、参考文献、数の表記をそれぞれ一つのパッケージにする。
   - 退けた案の一つは、IR だけを分け、残りを一つのパッケージ（集約）にまとめることである。参考文献は IR も集約も使わず、数の表記は golem-layout が IR の数を組むために使う。一つにまとめると、golem-layout は漢数字のために集約に依存し、集約のパッケージは三つの責務を持つ。
   - もう一つは、数の表記を golem-length に入れることである。golem-length は長さの型と単位の変換のパッケージであり、漢数字と丸数字は長さではない。

## 参考文献

- [2026-10-20 のロードマップのレビュー](../audits/2026-10-20-roadmap-review.md)
- [ADR 0028](0028-shared-test-support-package.md)、[ADR 0087](0087-test-support-dependencies-and-shared-fixtures.md)、[ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md)、[ADR 0029](0029-environment-variation-determinism-test.md)、[ADR 0162](0162-calling-emet-functions-from-gm.md)、[ADR 0191](0191-semantic-ir-generator-module.md)、[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md)
- [golem-doc ADR 0001](../golem-doc/adr/0001-semantic-ir-in-cddl.md)、[golem-doc ADR 0002](../golem-doc/adr/0002-document-assembly.md)、[golem-doc ADR 0007](../golem-doc/adr/0007-plugin-channel-lists.md)
- Unicode Standard Annex #50, *Unicode Vertical Text Layout*. https://www.unicode.org/reports/tr50/
