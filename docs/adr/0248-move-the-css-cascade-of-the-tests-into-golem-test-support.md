# ADR 0248: テストの CSS の評価器を golem-test-support に移す

ステータス: 採択（未実装）

## 文脈

### [ADR 0245](0245-keep-the-warnings-of-ci-at-zero.md) が残したもの

[ADR 0245](0245-keep-the-warnings-of-ci-at-zero.md) は、CI のログの warning を、許可の一覧にないかぎり CI の失敗にする。
cabal の `[relative-path-outside]` は、golem 自身が直せるので、許可の一覧に入れないと決めた（「メンテナーが決めること」の 3）。
直すまで [ADR 0245](0245-keep-the-warnings-of-ci-at-zero.md) の 6 を実装できないので、別の ADR で先に直す。
この ADR は、その別の ADR である。

### warning の出どころ

golem-driver の test-suite は、`hs-source-dirs` に `../golem-html/test` を持つ（[`golem-driver.cabal#L84-L85`](https://github.com/tett23/golem/blob/0cd8798d34137b2ac9fc518bf4b208f310fb9d1f/modules/golem-driver/golem-driver.cabal#L84-L85)）。
golem-html のテストの CSS の評価器 `CssCascade` を、golem-driver の `FileSpacesSpec` から使うためである。
[ADR 0217](0217-html-spaces-of-paragraph-styles-redefined-in-files.md) の実装（[#677](https://github.com/tett23/golem/pull/677)）がこの構成を作り、[ADR 0229](0229-record-the-procedures-adr-0215-and-0217-departed-from.md) がそれを記録して認めた（「メンテナーが決めること」の 2）。

CI のログには、cabal 3.16.1.0 の `Warning: [relative-path-outside]` が 6 回出ていた（[ADR 0245](0245-keep-the-warnings-of-ci-at-zero.md) の文脈の表）。
手元の cabal 3.18.1.0 では、`cabal build all --enable-tests --dry-run` には出なかった。
`modules/golem-driver` で `cabal check` を走らせると、同じ検査が誤りとして出る。

```
Error: [relative-path-outside] 'hs-source-dirs: ../golem-html/test' is a
relative path outside of the source tree. This will not work when generating a
tarball with 'sdist'.
```

リポジトリの .cabal のうち、パッケージの外を指すパスは、この一つだけである（`modules/*/*.cabal` の `../` を探した）。

### `CssCascade` が使うもの

`CssCascade`（[`CssCascade.hs`](https://github.com/tett23/golem/blob/0cd8798d34137b2ac9fc518bf4b208f310fb9d1f/modules/golem-html/test/CssCascade.hs)、238 行）が import するのは、base の `Data.Char`、`Data.List`、`Data.Maybe`、`Data.Ord` と、text の `Data.Text` だけである。
golem-html の型も、ほかの golem のパッケージも使わない。
[ADR 0229](0229-record-the-procedures-adr-0215-and-0217-departed-from.md) は、golem-test-support に移す案を「golem-html の内部の型を使うなら移せない」として退けたが、使っていないので移せる。

`CssCascade` を使うのは、次の三つである。

| モジュール | パッケージ | 使うもの |
| --- | --- | --- |
| `CssCascadeSpec` | golem-html の test-suite | 評価器そのもののテスト（66 行） |
| `XhtmlSpec` | golem-html の test-suite | `Elem`、`Page`、`Winner`、`winningMarginStarts` |
| `FileSpacesSpec` | golem-driver の test-suite | `Elem`、`Page`、`Winner`、`pageOf`、`winningMarginStarts` |

`CssCascadeSpec` が import するのは、`CssCascade`、base、text、tasty、tasty-hunit だけである。

### golem-test-support の規則

golem-test-support は、二つ以上のパッケージのテストが使う補助を持つ（[ADR 0028](0028-shared-test-support-package.md)）。
golem のパッケージに依存せず、Hackage のパッケージは、`cabal.project.freeze` で版を固定してあり、いずれかのテストスイートがすでに依存しているものに限る（[ADR 0087](0087-test-support-dependencies-and-shared-fixtures.md)）。
`scripts/ci/test-only-deps.sh` が、この二つと、ライブラリと実行ファイルが golem-test-support に依存しないことを確かめる。
golem-test-support のライブラリは、すでに base と text に依存している。
golem-driver の test-suite は、すでに golem-test-support に依存している。
golem-html の test-suite は、依存していない。

## 実装すること

### 1. 評価器を移す

`modules/golem-html/test/CssCascade.hs` を、`modules/golem-test-support/src/Golem/TestSupport/CssCascade.hs` に移す。
モジュールの名前を `Golem.TestSupport.CssCascade` にし、公開する名前と中身は変えない。
golem-test-support のライブラリの `exposed-modules` に足す。
ライブラリの `build-depends` は変えない。

### 2. 評価器のテストを移す

`modules/golem-html/test/CssCascadeSpec.hs` を、golem-test-support の test-suite（`golem-test-support-test`）に移す。
import を `Golem.TestSupport.CssCascade` に直し、テストの中身は変えない。
`golem-test-support-test` の `other-modules` に足し、その `Main` の木に `cssCascadeTests` を足す。
この test-suite は、すでに tasty、tasty-hunit、text に依存している。

### 3. 使う側

- golem-html の test-suite の `build-depends` に、golem-test-support を足す。golem のパッケージのあいだの依存の変更であり、この ADR が決める。テストスイートだけの依存なので、golem-html のライブラリと golem の実行ファイルの依存は変わらない。
- golem-html の test-suite の `other-modules` から `CssCascade` と `CssCascadeSpec` を除き、`Main` の木から `cssCascadeTests` を除く。
- `XhtmlSpec` と `FileSpacesSpec` の import を `Golem.TestSupport.CssCascade` に直す。
- golem-driver の test-suite の `hs-source-dirs` を `test` だけにし、`other-modules` から `CssCascade` を除き、注を消す。
- `FileSpacesSpec` の、`CssCascade` を golem-html のテストのものとする注を直す。

### 4. 文書

- `docs/specifications.md` の golem-test-support の段落に、`Golem.TestSupport.CssCascade` を足し、この ADR へのリンクを付ける。
- [ADR 0229](0229-record-the-procedures-adr-0215-and-0217-departed-from.md) のステータスの行を、「採択→パッケージをまたぐソースのディレクトリは [ADR 0248](0248-move-the-css-cascade-of-the-tests-into-golem-test-support.md)」にする。
- [ADR 0217](0217-html-spaces-of-paragraph-styles-redefined-in-files.md) のステータスの行の「golem-driver のテストが golem-html のテストのソースを読むことは [ADR 0229](0229-record-the-procedures-adr-0215-and-0217-departed-from.md)」を、評価器の置き場所はこの ADR、とする形に直す。

## 実装しないこと

- 評価器の中身（読むセレクターの範囲、詳細度、順序の規則）は変えない。
- golem-test-support の `build-depends` は変えない。
- パッケージの外を指すパスを検査するスクリプトは、作らない。[ADR 0245](0245-keep-the-warnings-of-ci-at-zero.md) のログの検査が、cabal の warning として見つける。
- `cabal check` を CI で走らせることはしない。golem のパッケージは Hackage に出さないので、`missing-upper-bounds` などのほかの指摘が多く、許可の一覧が要る。

## 不変条件

なし。
テストのコードの置き場所と、テストスイートの依存を決める ADR であり、golem の振る舞いを変えない。
代わりに、実装の後に次が成り立つことを確かめる。

1. `modules/*/*.cabal` のどの `hs-source-dirs` も、`../` を含まない。
2. `modules/golem-driver` の `cabal check` の出力に、`relative-path-outside` の行がない。CI のすべてのジョブのログにも、その行がない。
3. `scripts/ci/test-only-deps.sh` が、`dist-newstyle/cache/plan.json` で終了コード 0 を返す。
4. 移す前と後で、golem-html-test、golem-driver-test、golem-test-support-test のテストの名前の集合の和が等しい（`CssCascadeSpec` のテストが golem-html-test から golem-test-support-test に移るだけである）。

## テスト設計

- 1 と 2 は、先に失敗させる。実装の前に、今の `main` で `grep -nE 'hs-source-dirs:.*\.\./' modules/*/*.cabal` が一行を返すことと、`modules/golem-driver` の `cabal check` の出力に `relative-path-outside` があることを確かめる。実装の後に、どちらも出なくなることを確かめる。結果をプルリクエストに書く。
- 2 の CI のログは、実装のプルリクエストの CI の実行で、`gh run view --log` の出力に `relative-path-outside` がないことを確かめる。
- 3 は、CI の build ジョブの今の step が確かめる。
- 4 は、移す前と後で、三つのテストスイートを `--list-tests` で走らせ、名前の一覧を比べる。結果をプルリクエストに書く。
- 自動のテストは足さない。移すのはテストのコードそのものであり、`CssCascadeSpec` が移った先で評価器を確かめ続ける。

## トレードオフ

- golem-html の test-suite が golem-test-support に依存すると、golem-test-support を変えたときに golem-html のテストもビルドし直す。golem-test-support の変更は少なく、ほかの多くのテストスイートもすでに依存しているので、増える時間は小さいと見込む。
- 評価器が golem-test-support にあると、HTML の出力と離れたところで評価器を変えられる。今の構成でも、golem-driver のテストは同じ評価器を別のパッケージから読んでいたので、離れ方は変わらない。
- 写す案（golem-driver のテストに `CssCascade` の写しを置く）は、依存を足さない。その代わり、238 行の評価器が二つになり、片方だけを直すと、HTML のテストと golem-driver のテストが別の規則で勝つ宣言を選ぶ。小さな補助を写す慣習は、数行の関数を想定している。
- golem-html の中の公開しないサブライブラリにする案は、golem-driver がすでに golem-html に依存しているので、新しいパッケージの依存を足さない。その代わり、テストだけのコードが golem-html のライブラリの一つになる。golem の実行ファイルがそれに依存しないことを、`test-only-deps.sh` は確かめないので、検査を変える必要がある。

## メンテナーが決めること

1. **置き場所**：案 1 は golem-test-support、案 2 は golem-driver のテストへの写し、案 3 は golem-html のサブライブラリである。推奨は案 1 である。[ADR 0087](0087-test-support-dependencies-and-shared-fixtures.md) が、二つのパッケージのテストが使うものを golem-test-support に置くと決めており（`genText` の先例がある）、golem-test-support の依存の規則も検査も変えずに済む。
2. **評価器のテストの置き場所**：案 1 は golem-test-support のテスト、案 2 は golem-html のテストに残すことである。推奨は案 1 である。評価器と同じパッケージでテストすれば、golem-test-support を変えたときに、そのパッケージのテストだけで評価器を確かめられる。
3. **[ADR 0229](0229-record-the-procedures-adr-0215-and-0217-departed-from.md) の決定を変えること**：[ADR 0229](0229-record-the-procedures-adr-0215-and-0217-departed-from.md) の「メンテナーが決めること」の 2 は、ソースのディレクトリの共有を認めた。この ADR は、それを変える。推奨は、[ADR 0229](0229-record-the-procedures-adr-0215-and-0217-departed-from.md) のステータスの行で、この ADR への変更を示すことである（「実装すること」の 4）。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-09、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [ADR 0028](0028-shared-test-support-package.md)、[ADR 0087](0087-test-support-dependencies-and-shared-fixtures.md)、[ADR 0217](0217-html-spaces-of-paragraph-styles-redefined-in-files.md)、[ADR 0229](0229-record-the-procedures-adr-0215-and-0217-departed-from.md)、[ADR 0245](0245-keep-the-warnings-of-ci-at-zero.md)
- [#677](https://github.com/tett23/golem/pull/677) の説明
- Cabal User Guide, "Package Description"（`hs-source-dirs`）: https://cabal.readthedocs.io/en/stable/cabal-package-description-file.html
- Cabal User Guide, "cabal check": https://cabal.readthedocs.io/en/stable/cabal-commands.html#cabal-check
