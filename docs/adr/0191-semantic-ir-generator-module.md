# ADR 0191: 意味論 IR の生成器を、テストだけが使うパッケージにする

ステータス: 採択（未実装）

## 文脈

意味論 IR の hedgehog の生成器が、二つのパッケージのテストに写してある。
[ADR 0173](0173-rc4-refactoring.md) の見直しで見つけたもので、メンテナーは、生成器を新しいモジュールにする ADR を作ると決めた（「決めたことの記録」）。
この ADR がそれである。

### 二つの写し

golem-doc のテストの [`Gen.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-doc/test/Gen.hs)（180 行）と、golem-driver のテストの [`IRGen.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/test/IRGen.hs)（183 行）を `diff` で比べた（2026-11-07）。
違うのは、モジュールの宣言の行だけである。

- `Gen.hs` は `module Gen (genDocument, genInline, genExpr, genInt64) where` の 1 行である。
- `IRGen.hs` は、golem-doc のテストから写したと書くコメントの 3 行と、`module IRGen (genDocument, genInline) where` の 1 行である。

宣言を除いた 179 行（空行を除くと 161 行）は、字句まで同じである。
`IRGen.hs` は、[ADR 0162](0162-calling-emet-functions-from-gm.md) の実装のコミット（`76ebaf85`）で写された。

生成器は、`BlockBody` の 12 の構成子と、`InlineF` の 17 の構成子をすべて作る（[`IR.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-doc/src/Golem/Doc/IR.hs#L98-L115) と生成器を読み比べて確かめた）。
整数は CDDL の `int64` と `uint64` の端を含めて作る（[golem-doc ADR 0006](../golem-doc/adr/0006-integer-range-in-ir.md)）。
遅延した式 `DeferredExpr` のために、原稿の式の構文木（golem-parser の `Golem.Parser.AST`）も作る。

### 生成器を使う性質

| テストのスイート | 性質 | 使う生成器 |
| --- | --- | --- |
| golem-doc-test | CBOR が CDDL に合うこと（`cddl` のコマンド、[golem-doc ADR 0001](../golem-doc/adr/0001-semantic-ir-in-cddl.md)） | `genDocument` |
| golem-doc-test | CBOR の往復、符号化が正準であること | `genDocument` |
| golem-doc-test | 式の CBOR の往復（`CborExprSpec`） | `genExpr` |
| golem-driver-test | `.emet` のデータ型が IR を、位置、ラベル、注の番号ごと返すこと（[ADR 0162](0162-calling-emet-functions-from-gm.md)、[`CallsSpec.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/test/CallsSpec.hs#L125-L132)） | `genDocument`、`genInline` |

どれも、プラグインの ABI か、`.emet` との境界で IR がそのまま往復することを確かめる。
IR に構成子や欄を足したのに、二つの写しの一方だけを直すと、もう一方の性質は新しい形を試さないまま通る。

### 置き場所の候補

golem-test-support には置けない。
golem-test-support は golem のパッケージに依存しないと決めており（[ADR 0087](0087-test-support-dependencies-and-shared-fixtures.md)）、生成器は golem-doc の型を使うからである。

残る候補は、golem-doc の公開のサブライブラリ（`golem-doc:gen`）と、新しいパッケージの二つである。
リポジトリのどの cabal ファイルにも、名前の付いたライブラリ（`library gen` のような節）はない（`rg` で確かめた）。

### テストだけが使う依存の検査

[`scripts/ci/test-only-deps.sh`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/scripts/ci/test-only-deps.sh) は、cabal の解決した計画（`plan.json`）を読み、二つを確かめる。

- リポジトリのライブラリと実行ファイル（golem-test-support のものを除く）が、golem-test-support に届かないこと。
- golem-test-support のライブラリが、リポジトリのパッケージに届かないこと。

CI の `build` ジョブと、リリースの `scripts/release/package.sh` が走らせる。
生成器は `hedgehog` を使うので、`golem` の実行ファイルに届くと、配布物のライセンスの一覧（`scripts/release/licenses.sh`）にも `hedgehog` が入る。
今の検査は golem-test-support の名前だけを見るので、生成器のパッケージに `golem` が依存しても止まらない。

### golem-doc の分割との関係

[ADR 0173](0173-rc4-refactoring.md) は、golem-doc を責務で分け、golem-doc に意味論 IR とプラグインの ABI だけを残す。
生成器が使うのは、IR の型、golem-length の `Sp`、golem-parser の構文木、golem-syntax の位置だけである。
golem-doc が IR だけになった後なら、生成器のパッケージは集約も参考文献もリンクしない。

## 実装すること

[ADR 0173](0173-rc4-refactoring.md) の「3. golem-doc を責務で分ける」の後に、一つのプルリクエストで行う。

### パッケージ

`modules/golem-doc-gen` に、新しいパッケージ golem-doc-gen を作る（「メンテナーが決めること」の 1 と 2）。

- ライブラリは `Golem.DocGen` の一つのモジュールを公開する。中身は今の `Gen.hs` の本体であり、`genDocument`、`genInline`、`genExpr`、`genInt64` を公開する。今の二つの写しが公開するものを合わせたものである。
- cabal ファイルの `description` に、テストのスイートだけが依存してよいことと、`test-only-deps.sh` がそれを確かめることを書く（golem-test-support と同じ形）。
- golem-doc の `test/Gen.hs` と golem-driver の `test/IRGen.hs` を消し、二つのテストは `Golem.DocGen` を取り込む。

### パッケージの依存

golem のパッケージのあいだの `build-depends` を、次のように変える。

| パッケージの構成要素 | 足す | 除く |
| --- | --- | --- |
| golem-doc-gen のライブラリ（新規） | golem-doc、golem-length、golem-parser、golem-syntax | |
| golem-doc-gen のテスト（新規） | golem-doc-gen、golem-doc | |
| golem-doc のテスト（golem-doc-test） | golem-doc-gen | |
| golem-driver のテスト（golem-driver-test） | golem-doc-gen | |

golem-doc-test の `other-modules` から `Gen` を、golem-driver-test の `other-modules` から `IRGen` を除く。
golem-driver-global-test と golem-driver-parallel-test は生成器を使わないので、変えない。
Hackage のパッケージ（`hedgehog` など）は、二つのテストのスイートがすでに依存し、`cabal.project.freeze` が版を固定しているものだけを使う。

### IR との同期

生成器が IR のすべての構成子を作り続けることを、golem-doc-gen のテストで確かめる（「メンテナーが決めること」の 3）。

- golem-doc-gen のテストに、構成子の種類を表す型（`BlockKind` と `InlineKind`、`Enum` と `Bounded` を導く）と、IR の値から種類を返す関数を置く。関数は `case` ですべての構成子を書き、`_` で受けない。
- golem のパッケージは `-Werror=incomplete-patterns` でコンパイルするので、IR に構成子を足すと、この関数がコンパイルできなくなる。足した人は、種類の型にも一つ足す。
- 性質のテストは、生成した文書に現れる種類を集め、hedgehog の `cover` で、種類のそれぞれが少なくとも 1% の文書に現れることを求める。生成器が新しい構成子を作らなければ、このテストが落ちる。

### 依存の検査

`scripts/ci/test-only-deps.sh` の一つめの検査の対象を、golem-test-support と golem-doc-gen の二つにする。

- 起点は、この二つのパッケージを除く、リポジトリのライブラリと実行ファイルである。どの起点も、二つのどちらにも届かないこと。
- 二つめの検査（golem-test-support がリポジトリのパッケージに届かないこと）は、golem-test-support だけに当てる。golem-doc-gen は golem-doc に依存するので、当てない。
- 仕様書の「モジュール構成」の、golem-test-support と並べて、golem-doc-gen を書き、図には含めないことを書く。

## 実装しないこと

- **生成器を golem-test-support に置くこと**：[ADR 0087](0087-test-support-dependencies-and-shared-fixtures.md) の、golem のパッケージに依存しない決まりを変えることになる。
- **ほかのテストを生成器に移すこと**：golem-plugin のテストの CBOR の往復などは、手で作った IR を使う。生成器に移すかは、それぞれのテストを直すときに決める。
- **CDDL のすべての選択肢を生成器が作ることを確かめること**：CDDL を読んで選択肢を数える仕組みが要る。IR の型と CDDL が一致することは、今のとおり golem-doc-test の `cddl` のコマンドの性質で確かめる。
- **`Generic` から生成器を導くこと**：「トレードオフ」に書く。
- **生成器の中身を変えること**：分布、範囲、構成子の重みは今のままにする。性質のテストの結果が変わらないようにするためである。

## テスト設計

先に書いて、失敗させてから実装するもの。

- golem-doc-gen の同期のテスト：今の生成器で通ること。生成器から `Sidenote` の行を一時的に除くと、`cover` で落ちることを手元で確かめる。
- `test-only-deps.sh`：`scripts/ci/testdata/test-only-deps/` に計画を足し、`scripts/ci/test.sh` で確かめる。
  - golem-driver のライブラリが golem-doc-gen に直接に依存する計画で、終了コード 1 になり、標準エラー出力にその構成要素を書くこと。
  - golem-driver のライブラリが、ほかのパッケージを通して golem-doc-gen に届く計画でも、同じく 1 になること。
  - golem-doc-gen のライブラリが golem-doc に依存し、テストのスイートだけが golem-doc-gen に依存する計画で、終了コード 0 になること。
  - 今の計画のテストは、そのまま通ること。

そのまま通ることで確かめるもの。

- golem-doc-test と golem-driver-test の、生成器を使う性質。
- CI の `build` ジョブの `test-only-deps.sh` と、リリースの `package.sh`。

## トレードオフ

新しいパッケージを一つ足すので、cabal ファイルと `build-depends` の行が増え、パッケージは [ADR 0173](0173-rc4-refactoring.md) の後の 28 から 29 になる。
その代わり、生成器の写しはなくなり、IR を変えた人は一か所を直せば済む。

golem-doc の公開のサブライブラリにすれば、パッケージは増えない。
ただし、リポジトリで初めての名前の付いたライブラリになり、`test-only-deps.sh` の起点（`lib:*`）にもなる。
検査を構成要素の名前で書き分けることになり、golem-test-support と同じ形の、パッケージの名前で見る検査より複雑になる。
golem-doc の cabal ファイルに `hedgehog` への依存も入る。

構成子の種類の型は、IR の構成子を写した一覧であり、IR を変えるたびに直す。
写しを一つ残す代わりに、写し忘れをコンパイラーが見つける。
`GHC.Generics` で構成子の名前を取れば一覧は要らないが、IR の型に `Generic` を導く変更が要り、golem-doc の型を変えることになる。
同じ理由で、`Generic` から生成器そのものを導くこともしない。
導いた生成器は、`int64` の端、ルビの中にルビを置かないこと、文書の先頭にだけ置く改ページのような、IR の決まりを知らない。

`cover` の 1% は、今の生成器の重みで、どの種類も届く値として選んだ。
実装のときに、今の生成器で種類ごとの割合を測り、届かない種類があれば、生成器を変えずに割合の下限のほうを下げる。

## 決めたことの記録

- **生成器を新しいモジュールにすること**（2026-11-07、メンテナー）：意味論 IR の生成器は、新しいモジュールを作る ADR で扱う。[ADR 0173](0173-rc4-refactoring.md) のレビューで決めた。
- **置き場所、名前、IR との同期、使うテストのスイート**（2026-11-07、メンテナー）：問題ないとした。「メンテナーが決めること」の 1 から 4 を推奨のとおりとした。

## メンテナーが決めること

すべて決めた（「決めたことの記録」）。

1. **置き場所**：決めた。新しいパッケージにする。
   - 退けた案の一つは、golem-doc の公開のサブライブラリ（`golem-doc:gen`）にすることである。リポジトリで初めての名前の付いたライブラリになり、`test-only-deps.sh` を構成要素の名前で書き分けることになる。
   - もう一つは、golem-test-support に置くことである。[ADR 0087](0087-test-support-dependencies-and-shared-fixtures.md) の決まりを変えることになる。
2. **名前**：決めた。パッケージを golem-doc-gen、モジュールを `Golem.DocGen` とする。
   - 退けた案は、golem-ir-gen のように IR の名前を付けることである。IR を持つパッケージの名前は golem-doc のままなので（[ADR 0173](0173-rc4-refactoring.md)）、名前がずれる。
3. **IR との同期**：決めた。構成子の種類の型と、`_` を使わない関数をテストに置き、`cover` で、生成器がどの種類も作ることを確かめる。
   - 退けた案の一つは、レビューに任せることである。今の写しも、レビューを通って main に入った。
   - もう一つは、`Generic` から生成器を導くことである。IR の決まりを知らない生成器になる。
4. **生成器を使うテストのスイート**：決めた。今の二つ（golem-doc-test と golem-driver-test）だけを移す。
   - 退けた案は、IR を手で作るほかのテスト（golem-plugin のテストなど）も、この ADR で生成器に移すことである。テストの中身が変わるので、整理と混ざる。

## 参考文献

- hedgehog, `Hedgehog.cover`. https://hackage.haskell.org/package/hedgehog
- Cabal User Guide, "Sublibraries"（名前の付いたライブラリと `visibility: public`）。 https://cabal.readthedocs.io/en/stable/cabal-package-description-file.html
- [ADR 0028](0028-shared-test-support-package.md)、[ADR 0087](0087-test-support-dependencies-and-shared-fixtures.md)、[ADR 0162](0162-calling-emet-functions-from-gm.md)、[ADR 0173](0173-rc4-refactoring.md)
- [golem-doc ADR 0001](../golem-doc/adr/0001-semantic-ir-in-cddl.md)、[golem-doc ADR 0006](../golem-doc/adr/0006-integer-range-in-ir.md)
