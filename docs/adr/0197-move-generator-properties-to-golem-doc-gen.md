# ADR 0197: golem-doc のテストの生成器を使う性質を、golem-doc-gen のテストに移す

ステータス: 採択

## 文脈

[ADR 0191](0191-semantic-ir-generator-module.md) は、二つのテストに写してあった意味論 IR の hedgehog の生成器を、テストだけが使う新しいパッケージ golem-doc-gen にまとめると決めた。
golem-doc のテストの `test/Gen.hs` と、golem-driver のテストの `test/IRGen.hs` を消し、二つのテストのスイートが golem-doc-gen に依存する、というものである。

[ADR 0191](0191-semantic-ir-generator-module.md) の実装（#607）は、このうち golem-doc の側を実装できなかった。
golem-doc-test が golem-doc-gen に依存する計画を、cabal-install 3.18.1.0 が次のように退けたからである（#607 の説明、2026-11-07 に読んだ）。

```
rejecting: golem-doc:*test (cyclic dependencies; conflict set: golem-doc, golem-doc-gen)
```

golem-doc-gen のライブラリは golem-doc に依存する。
cabal の依存の解決は、構成要素ではなくパッケージの単位で循環を見るので、golem-doc のテストのスイートが golem-doc-gen に依存すると、golem-doc → golem-doc-gen → golem-doc の循環になる。
golem-driver の側は実装され、`IRGen.hs` は消えた。
golem-doc の [`test/Gen.hs`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-doc/test/Gen.hs#L1-L4) は、golem-doc-gen の `Golem.DocGen` の写しであることと、二つを一緒に直すことを書いたコメントを付けて残った。
[ADR 0191](0191-semantic-ir-generator-module.md) のステータスの行は「採択（未実装）」のままである。

写しが残るかぎり、[ADR 0191](0191-semantic-ir-generator-module.md) が解こうとした問題も残る。
IR に構成子を足して `Golem.DocGen` だけを直すと、golem-doc のテストの性質は新しい形を試さないまま通る。
golem-doc-gen のテストの `cover` は `Golem.DocGen` を確かめるので、写しの直し忘れには気付けない。

### 生成器を使う golem-doc のテスト

golem-doc-test のうち、生成器を使うのは次の五つの性質である（2026-11-07 に `rg` で確かめた）。
[ADR 0191](0191-semantic-ir-generator-module.md) の「生成器を使う性質」の表は、これを三つの行にまとめている。

| モジュール | 性質（tasty の名前） | 生成器 | 回数 |
| --- | --- | --- | --- |
| `Main` | `CBOR conforms to the CDDL (the cddl CLI)` | `genDocument` | 60 |
| `Main` | `CBOR round trip` | `genDocument` | 300 |
| `Main` | `encoding is canonical` | `genDocument` | 100（既定） |
| `CborExprSpec` | `every kind of expression survives the round trip` | `genExpr` | 300 |
| `CborExprSpec` | `every expression has the shape of the expr rule of the CDDL` | `genExpr` | 300 |

`Main` の三つは、`golem-doc (ADR 0001)` の組（`cbor`）にある（[`Main.hs`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-doc/test/Main.hs#L125-L153)）。
`CborExprSpec` の二つは、`deferred expressions in CBOR (golem-doc ADR 0001)` の組にある（[`CborExprSpec.hs`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-doc/test/CborExprSpec.hs#L45-L56)）。
`genInline` と `genInt64` は、golem-doc-test のどこも使わない。
ほかのテストは、どれも手で作った値を使う。

五つの性質が頼る補助は、次のとおりである。

- `CBOR conforms to the CDDL` は、`cddl` のコマンドを探す `cddlValidator`（[`Main.hs`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-doc/test/Main.hs#L33-L39)）と、golem-test-support の `needsTool` を使う。スキーマはパッケージのディレクトリからの相対の道 `schema/golem-doc.cddl` で読む。`cddlValidator` は、`cddl` を使うほかの二つのテストケースも使う。
- `every expression has the shape of the expr rule of the CDDL` は、CDDL の `expr` の規則を写した `isExpr` とその補助（`isSpan`、`isInt`、`isUint`、`termInteger`、`isRational`、`isTstr`、`isBool`）を使う（[`CborExprSpec.hs`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-doc/test/CborExprSpec.hs#L68-L136)）。`isExpr` の一族を使うのは、この性質だけである。
- `CborExprSpec` の二つは、式を一つの遅延したインラインに包む `deferred` と、その CBOR を項として読み戻す `wireExpr` を使う（[`CborExprSpec.hs`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-doc/test/CborExprSpec.hs#L25-L43)）。この二つと `sp`、`spanTerm` は、範囲の式のテストケースなど、`CborExprSpec` に残るテストも使う。

### 移した後に golem-doc-test が使わなくなるもの

五つの性質を除くと、golem-doc-test は hedgehog の性質を一つも持たない。
`Gen.hs` のほかに golem-length を取り込むモジュールもない（[`golem-doc.cabal`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-doc/golem-doc.cabal)、2026-11-07 に `rg` で確かめた）。

## 実装すること

### 性質を移す

五つの性質を、golem-doc のテストから golem-doc-gen のテスト（`golem-doc-gen-test`）に移す。
性質の名前、中身、回数（`withTests`）は変えない。

- golem-doc-gen のテストに `CborSpec` を作り、`Main` の三つの性質を移す。組の名前は `golem-doc (ADR 0001)` のままにする。
- golem-doc-gen のテストに `CborExprSpec` を作り、`CborExprSpec` の二つの性質と、`isExpr` の一族（「文脈」）を移す。組の名前は `deferred expressions in CBOR (golem-doc ADR 0001)` のままにする。
- `cddlValidator`、`deferred`、`wireExpr`、`sp`、`spanTerm` は、golem-doc のテストに残るテストも使うので、golem-doc-gen のテストに写す。どれも数行であり、二つのテストのスイートが共有するモジュールを作るより小さい（[docs/adr/0087](0087-test-support-dependencies-and-shared-fixtures.md) の、写して持つ扱い）。
- `CBOR conforms to the CDDL` のスキーマは、golem-doc-gen のディレクトリからの相対の道 `../golem-doc/schema/golem-doc.cddl` で読む。golem-driver のテストが `../golem-font/test/fonts/` を読むのと同じ扱いである。
- golem-doc-gen のテストの `main` を、golem-test-support の `defaultMainReportingSkips` にする。`needsTool` が飛ばしたテストを数えて書くためである（[docs/adr/0074](0074-test-switches-by-environment-variables.md) の決まり）。今の `golem-doc-gen` の組（構成子の `cover`）は、その下に残す。

### 写しを消す

- `modules/golem-doc/test/Gen.hs` を消し、golem-doc-test の `other-modules` から `Gen` を除く。
- golem-doc の `Main` と `CborExprSpec` から、五つの性質と、それだけが使う import（`Gen`、`Hedgehog`、`Test.Tasty.Hedgehog`）を除く。`isExpr` の一族も除く。

### パッケージの依存

golem のパッケージのあいだの `build-depends` を、次のように変える。

| パッケージの構成要素 | 足す | 除く |
| --- | --- | --- |
| golem-doc-gen のテスト（`golem-doc-gen-test`） | golem-parser、golem-syntax、golem-test-support | |
| golem-doc のテスト（`golem-doc-test`） | | golem-length |

- golem-doc-gen のテストは、すでに golem-doc と golem-doc-gen に依存する。足す三つは、`deferred` と `sp` が使う構文木と位置（golem-parser、golem-syntax）と、`needsTool` と `defaultMainReportingSkips`（golem-test-support）のためである。
- golem-doc-test の golem-length は、`Gen.hs` だけが使っていた。
- Hackage のパッケージでは、golem-doc-gen のテストに `bytestring`、`cborg`、`directory`、`filepath`、`process`、`temporary`、`tasty-hunit` のうち、移したテストが使うものを足す。どれも golem-doc-test がすでに依存し、`cabal.project.freeze` が版を固定している。golem-doc-test からは、使わなくなる `hedgehog` と `tasty-hedgehog` を除く。
- golem-doc-gen のライブラリと、ほかのパッケージの `build-depends` は変えない。

golem-doc-gen のテストが golem-test-support に依存することは、[docs/adr/0087](0087-test-support-dependencies-and-shared-fixtures.md) の決まり（テストのスイートは依存してよい）の中にある。
`scripts/ci/test-only-deps.sh` の検査は、ライブラリと実行ファイルを起点にするので、変えない。

### CI

`scripts/ci/test-suites.sh` と `.github/workflows/ci.yml` は変えない。
golem-doc-gen-test は、golem-doc-test と同じく、golem-driver のほかのスイートのランナー（`rest`）で走る。
そのランナーは `cddl` のコマンドを入れ、`GOLEM_REQUIRE_EXTERNAL_TOOLS=1` で走らせるので、移した後も `CBOR conforms to the CDDL` が飛ばされずに走る。

### 文書

- golem-doc-gen の cabal ファイルの `description` を、golem-doc-gen のテストが golem-doc の CBOR の性質を持つことを含めて直す。
- golem-test-support の `Golem.TestSupport.ExternalTool` の、使うテストのスイートの一覧のコメントに、golem-doc-gen を加える。
- [docs/specifications.md](../specifications.md) の「モジュール構成」の golem-doc-gen の段落から、golem-doc-test が生成器の写しを使うことと、その理由（cabal の循環）の二文を除く。代わりに、golem-doc の CBOR と CDDL の性質を golem-doc-gen のテストが持つことと、その理由（golem-doc のテストは golem-doc-gen に依存できない）を書く。

### ステータスの行

この ADR は一つのプルリクエストで実装する。
そのプルリクエストで、この ADR のステータスの行を「採択」にし、[ADR 0191](0191-semantic-ir-generator-module.md) のステータスの行を「採択（未実装）」から「採択→golem-doc のテストの生成器の写しを消し、生成器を使う性質を golem-doc-gen のテストに移すことは [ADR 0197](0197-move-generator-properties-to-golem-doc-gen.md)」にする。
[ADR 0191](0191-semantic-ir-generator-module.md) の「実装すること」のうち、golem-doc の側（`Gen.hs` を消すこと、golem-doc-test が golem-doc-gen に依存すること）を、この ADR が置き換える。
ほかの部分は #607 で実装済みである。

## 実装しないこと

- **golem-doc の公開のサブライブラリ（`golem-doc:gen`）にすること**：[ADR 0191](0191-semantic-ir-generator-module.md) が退けた案である（[ADR 0191](0191-semantic-ir-generator-module.md) の「メンテナーが決めること」の 1）。リポジトリで初めての名前の付いたライブラリになり、`test-only-deps.sh` の検査を構成要素の名前で書き分けることになる。
- **写しを残すこと**：「文脈」のとおり、写しの直し忘れにどの検査も気付けない。
- **golem-doc のテストの `hs-source-dirs` に golem-doc-gen の `src/` を加えること**：golem-doc-test が `Golem.DocGen` のソースを自分のモジュールとしてコンパイルし、cabal の依存の宣言を通さずに循環を避ける。ソースは一つになるが、golem-doc-gen への依存が cabal ファイルに現れず、`plan.json` を読む検査からも見えなくなる。リポジトリには、パッケージの外のディレクトリをソースにする cabal ファイルがない（2026-11-07 に `rg` で確かめた）。
- **性質の中身を変えること**：回数、生成器、断言を変えない。移す前と同じことを確かめるためである。
- **`cddlValidator` などの補助を golem-test-support に移すこと**：`cddlValidator` は golem-doc の `cddl` のコマンドを探す一つの関数であり、ほかのパッケージは使わない。
- **golem-doc の手で作った値のテストを生成器に移すこと**：[ADR 0191](0191-semantic-ir-generator-module.md) の「実装しないこと」と同じく、それぞれのテストを直すときに決める。

## テスト設計

性質を移すことは、テストを足すのではなく、テストの置き場所を変えることである。
そのため、移す前と後のテストの名前の一覧を比べ、一つも消えず、増えていないことを確かめる。
[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) の `MemoSpec` と `RuleShapeSpec` の移し方と同じ確かめ方である。

- 移す前に、`golem-doc-test` と `golem-doc-gen-test` のテストの名前の一覧（tasty の `--list-tests`）を書き出す。
- 移した後に、同じ二つの一覧を書き出す。
- `golem-doc-test` の一覧から消えた名前が、一番上の組の名前（`golem-doc` と `golem-doc-gen`）を除いて、「文脈」の表の五つとちょうど一致すること。
- `golem-doc-gen-test` の一覧に増えた名前が、一番上の組の名前を除いて、同じ五つとちょうど一致すること。
- 二つの一覧の比べは、プルリクエストの説明に書き、レビューで確かめる。

そのまま通ることで確かめるもの。

- 移した五つの性質と、golem-doc-gen の構成子の `cover`。
- golem-doc に残るテスト（`cddl` のコマンドが ABI の版の違う文書を退けること、範囲の式の形など）。
- CI の `build` ジョブの `test-only-deps.sh` と、`rest` のランナーで `CBOR conforms to the CDDL` が飛ばされないこと（`GOLEM_REQUIRE_EXTERNAL_TOOLS=1` のもとで、`cddl` が見つからなければ失敗になる）。

写しが消えたことは、`modules/golem-doc/test/Gen.hs` がないことと、golem-doc-test の cabal の節に golem-doc-gen も golem-length もないことで確かめる。

## トレードオフ

golem-doc の CBOR と CDDL の性質が、golem-doc のテストでなく、golem-doc-gen のテストにある。
golem-doc の符号化を変えた人は、golem-doc-test だけを走らせても、その性質を確かめられない。
golem-doc-gen-test も走らせる必要がある。
CI は両方を同じランナーで走らせるので、CI での見落としにはならない。
手元で走らせるときに見落としやすくなる。

`cddlValidator`、`deferred`、`wireExpr` などの補助が、二つのテストに写される。
[ADR 0191](0191-semantic-ir-generator-module.md) は生成器の写しを消すための ADR であり、別の写しを作ることになる。
ただし、写すのは合わせて十数行の補助であり、IR の構成子を足しても直す必要がない。
生成器の写しは、IR を変えるたびに二つを揃える必要があった。

golem-doc-gen のテストが golem-test-support と golem-parser に依存し、パッケージのあいだの依存の行が増える。
その代わり、golem-doc-test の依存は golem-length と hedgehog の分だけ減る。

## 決めたことの記録

- **生成器を使う性質の置き場所**（2026-11-07、メンテナー）：golem-doc-test の、生成器を使う性質を golem-doc-gen のテストに移し、`modules/golem-doc/test/Gen.hs` を消す。
- **退けた案**（2026-11-07、メンテナー）：golem-doc の公開のサブライブラリ `golem-doc:gen`（[ADR 0191](0191-semantic-ir-generator-module.md) でも退けた）と、写しを残すことを退けた。
- **移す性質の数**（2026-11-07、メンテナー）：生成器を使う性質は、[ADR 0191](0191-semantic-ir-generator-module.md) の表の三行ではなく五つあり、草案の推奨のとおり五つとも移すとした。

## 参考文献

- [ADR 0087](0087-test-support-dependencies-and-shared-fixtures.md)、[ADR 0191](0191-semantic-ir-generator-module.md)、[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md)
- [golem-doc ADR 0001](../golem-doc/adr/0001-semantic-ir-in-cddl.md)
- プルリクエスト #607（[ADR 0191](0191-semantic-ir-generator-module.md) の実装）の説明
- Cabal User Guide, "Sublibraries". https://cabal.readthedocs.io/en/stable/cabal-package-description-file.html
