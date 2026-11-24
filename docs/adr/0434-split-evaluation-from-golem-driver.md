# ADR 0434: プロジェクトの評価を golem-driver から新しいパッケージ golem-evaluate に分ける

Status: accepted

## 文脈

golem-lsp のライブラリが golem-driver から使うのは、プロジェクトの評価と、その結果の補助と、lint と、diagnostic の説明の URL だけで、PDF の組版は使わない。
それでも、評価と書き出しが一つのパッケージ golem-driver にあるので、golem-lsp は golem-driver を通して golem-typeset と、その先の golem-font（HarfBuzz と FreeType）、golem-layout、golem-html、golem-epub にも依存する。
[root ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) は、PDF の組版を golem-typeset に分けたときに、評価を別のパッケージに分けることをロードマップに回した。
この ADR は、その分け方を決める。

## 調査した事項

origin/main（[9efdc4f89](https://github.com/tett23/golem/commit/9efdc4f89b3fec75abcd37c11abb3e1d909c6725)）で、次のことを確かめた。

- PDF、HTML、EPUB のパッケージを import するのは、golem-driver の中では `Golem.Driver`（1732 行）と、`Golem.Driver.Html`、`Golem.Driver.PageMap` だけである。
- golem-lsp のライブラリが golem-driver から使うものは、`Evaluated(..)`、`assetRefs`、`builtinKeepStyles`、`evaluateLoose`、`evaluateProjectWith`、`keepStyles`、`metadataValues`、`Golem.Driver.Lint.lintEvaluated`、`Golem.Driver.Explain.codeDescriptionUrl` で、どれも評価の側である。
- `Evaluated`（[Driver.hs#L172-L207](https://github.com/tett23/golem/blob/9efdc4f89b3fec75abcd37c11abb3e1d909c6725/modules/golem-driver/src/Golem/Driver.hs#L172-L207)）のフィールドの型は、`Project`、`Style`、`EvalResult`、`Book`、`Program`、`Diagnostic` などで、PDF の型を含まない。
- 評価と書き出しの両方が使う補助は、`localStylesOf`、`docStyles`、`runningVars`、`sourceInfos`、`withEvaluatedSources`、`projectVarTexts`（`Golem.Driver.ProjectVars` にある）、ファイルの有無を調べる `isPresent` などで、型は評価のものだけである。
  `epubConfig` と `cssFontSize` は書き出しの側にある。
- 評価は、`Golem.Driver.Plugins`、`Golem.Driver.Functions`、`Golem.Driver.ProjectVars`、`Golem.Driver.Verse` を使う。
  cabal の flag `plugins` は、真なら golem-plugin に依存して `src-plugins/` の `Golem.Driver.Plugins` と `Golem.Driver.New`（`golem new`）を組み、偽なら `src-no-plugins/` の `Golem.Driver.Plugins` を組む（[root ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md)）。
  `cabal.project.wasm` は、組むパッケージを `packages:` に一つずつ挙げ、`package golem-driver` に `flags: -plugins` を書く。
  `cabal.project` は `modules/*/*.cabal` の glob で挙げる。
- `codeDescriptionUrl` は、`docs/diagnostics.md` の目録（`catalog`）に載ったコードだけに URL を返す。
  目録は、`scripts/gen-embedded.sh` が `docs/diagnostics.md` から生成してコミットした `Golem.Driver.Explain.Embedded` から作る（[root ADR 0203](0203-generated-modules-instead-of-template-haskell-in-golem-driver.md)）。
  golem-driver の `diagnostics.md` は根の `docs/diagnostics.md` へのシンボリックリンクで、cabal の `extra-source-files` に挙がる。
  golem-driver の `DiagnosticsSpec.hs` は、このファイルを読み、生成したモジュールと比べる。
  [root ADR 0203](0203-generated-modules-instead-of-template-haskell-in-golem-driver.md) は、テストが読むので `extra-source-files` の項目を残すと決めている。
  CI は、生成し直したモジュールとコミットしたものの差を調べ（`ci.yml` の 489 行と 490 行）、hlint と fourmolu の対象から外す（1209 行、1210 行、1232 行）。
  `scripts/test.sh` は、`gen-embedded.sh` の出力のパスを確かめる。
- `Golem.Driver.Version.Embedded`（`VERSION`）は、PDF の Producer に使う。
- 下位のモジュールを直に import するのは、golem-cli（`app/Main.hs`、`test/Main.hs`）、golem-driver のテスト（`DiagnosticsSpec.hs`、`FunctionsSpec.hs`、`PluginsSpec.hs` など七つ）、golem-lsp（`Server.hs`、`Workspace.hs`、`test/Main.hs`）である。
- golem-cli は `Golem.Driver` の全体を使い、golem-wasm は `buildPdfInMemory` と `golemVersion` だけを使う。
  golem-preflight は golem-driver を使わない。
- golem-lsp のライブラリは `Golem.Preflight.Rules.rulesSchema` を使い、golem-preflight は golem-pdf に依存する。
  評価を分けても、golem-lsp は golem-pdf には届く。
- `scripts/ci/doc-deps.sh` は、cabal の plan.json を読み、規則の表のパッケージのライブラリが、禁じたパッケージに届かないことを確かめる。
  規則の表のパッケージのライブラリが plan.json に無いと、終了コード 2 で終わる。
  試験の plan.json は `scripts/ci/testdata/doc-deps/` に八つある。
- 仕様書は、モジュールの依存の図（427 行から）、doc-deps の検査（541 行）、生成したモジュール（550 行）、プラグインのない版（688 行から 702 行）、diagnostic の埋め込み（5465 行）に golem-driver の構成を書く。
- 古いモジュールの名前とパスは、ほかに、`scripts/ci/test.sh`（`ci.yml` の段の文面とパスを確かめる）、`scripts/ci/docs-refs.sh`、`CONTRIBUTING.md` と `CONTRIBUTING.en.md`、開発者向けのマニュアルの `02-diagnostics.gm`、`08-build-test.gm`、`10-docs.gm`、`12-purity.gm`、`docs/diagnostics.md` の「段階とモジュール」（約 30 か所）に出る。
  開発者向けのマニュアルの `07-modules.gm` も、モジュールの一覧を持つ。
- golem-* のあいだの依存を変えるには ADR が要る（メンテナーの決まり）。

指示者は 2026-11-23 に、この ADR を書くよう求めた。

## 実装すること

### 新しいパッケージ

新しいパッケージ `golem-evaluate` を `modules/golem-evaluate/` に作る。
`golem-evaluate` に、次のものを移す。

- `Evaluated` の型と、評価の関数（`evaluateProject`、`evaluateProjectWith`、`evaluateLoose`）。
- 評価の結果の補助（`assetRefs`、`metadataValues`（評価と golem-lsp だけが使う）、`keepStyles`、`builtinKeepStyles`、`sourceSettingsOf`、`sourceInfos`、`withEvaluatedSources`、`hostContext`、`functionPaths`、`loadBibliography`、`localStylesOf`、`docStyles`、`runningVars`、`projectVarTexts`、`isPresent`）。
  `localStylesOf`、`docStyles`、`runningVars`、`isPresent` は、書き出しも使うが、型が評価のものだけなので、評価の側に置く。
- `Golem.Driver.Functions`、`Golem.Driver.ProjectVars`、`Golem.Driver.Verse`、`Golem.Driver.Plugins`（`src-plugins/` と `src-no-plugins/` の二つ）、`Golem.Driver.Lint`。
- `Golem.Driver.Explain` と、その目録と、生成した `Golem.Driver.Explain.Embedded`。

モジュールの名前は `Golem.Evaluate` と `Golem.Evaluate.*` にする（`Golem.Evaluate.Lint`、`Golem.Evaluate.Explain` など）。

`Explain` を golem-evaluate に置くのは、golem-lsp が `codeDescriptionUrl` を使い、`codeDescriptionUrl` が目録を要るからである。
`Explain` は golem-syntax だけに依存するので、golem-evaluate の依存を増やさない。

### flag `plugins`

golem-evaluate に、golem-driver と同じ意味の flag `plugins` を持たせる。
真なら golem-plugin に依存して `src-plugins/` の `Golem.Evaluate.Plugins` を組み、偽なら `src-no-plugins/` のものを組む。
golem-driver の flag `plugins` は、`Golem.Driver.New` を組むかどうかだけを決めるものとして残す。
`cabal.project.wasm` の `packages:` に `modules/golem-evaluate` を足し、`package golem-evaluate` の `flags: -plugins` を足す。
`cabal.project.wasm` の freeze の検査（`wasm-freeze.sh`）で、固定する版が変わらないことを確かめる。

### 生成したモジュール

`scripts/gen-embedded.sh` は、目録のモジュールを `modules/golem-evaluate/src/Golem/Evaluate/Explain/Embedded.hs` に書く。
`Golem.Driver.Version.Embedded` は golem-driver に残す。
`modules/golem-evaluate/diagnostics.md` を根の `docs/diagnostics.md` へのシンボリックリンクにし、golem-evaluate の cabal の `extra-source-files` に挙げる。
golem-driver の `diagnostics.md` のリンクと `extra-source-files` の項目は、`DiagnosticsSpec.hs` が読むので残す。
`ci.yml` の生成の差の検査、hlint と fourmolu の対象の外し、`scripts/ci/test.sh` の `ci.yml` の段の検査、`scripts/ci/docs-refs.sh` の除外、`scripts/test.sh` の `gen-embedded.sh` の検査、README と `CONTRIBUTING.md`（英語版を含む）の生成したモジュールの記述を、新しいパスに直す。

### golem-driver

golem-driver は、`golem-evaluate` に依存し、書き出し（PDF、HTML、EPUB、テキスト、page-map、preflight の組み立て）を受け持つ。
`Golem.Driver` は、移した評価の関数と型と補助を export し直す。
golem-cli と golem-wasm が `Golem.Driver` から使う名前を変えずに済ませるためである。

下位のモジュール（`Golem.Driver.Lint`、`Golem.Driver.Explain`、`Golem.Driver.Functions`、`Golem.Driver.Plugins`、`Golem.Driver.ProjectVars`、`Golem.Driver.Verse`）は、golem-driver に残さない。
古い名前で export し直すだけのモジュールは作らず、リポジトリの中の import を `Golem.Evaluate.*` に書き換える。
同じモジュールが二つの名前で見えると、どちらを使うかが場所ごとに割れるためである。

### golem-lsp

golem-lsp のライブラリは、golem-driver ではなく `golem-evaluate` に依存する。
golem-lsp のテストが golem-typeset と golem-plugin を直に使うことは、今のまま残す。

### 依存の検査

`scripts/ci/doc-deps.sh` の規則の表に、次の二つを足す。

- `golem-evaluate` のライブラリは、golem-driver、golem-typeset、golem-font、golem-layout、golem-html、golem-epub、golem-pdf に届かない。
- golem-lsp のライブラリは、golem-driver、golem-typeset、golem-font、golem-layout、golem-html、golem-epub に届かない。
  golem-pdf には、golem-preflight を通して届くことを許す。

規則の表に golem-evaluate と golem-lsp が入ると、試験の plan.json にもその二つのライブラリが要る（無いと終了コード 2 になる）。
`scripts/ci/testdata/doc-deps/` の八つの plan.json すべてに、二つのライブラリの項目を足す。

### パッケージの依存

golem-* のあいだの依存を、次のように変える。

| コンポーネント | 足す | 消す |
| --- | --- | --- |
| golem-evaluate のライブラリ | golem-assemble、golem-bibliography、golem-doc、golem-emet、golem-eval、golem-lint、golem-parser、golem-project、golem-syntax（移すモジュールが今 import するもの）。flag `plugins` が真のときだけ golem-plugin | なし（新しい） |
| golem-driver のライブラリ | golem-evaluate | 移したモジュールだけが使っていた golem-* があれば、それ |
| golem-driver の四つのテストのスイート | golem-evaluate | なし |
| golem-lsp のライブラリ | golem-evaluate | golem-driver |
| golem-lsp のテスト | golem-evaluate | なし |
| golem-cli の実行ファイルとテスト | golem-evaluate | なし |

golem-evaluate のライブラリの依存の一覧は、移すモジュールの import から決まる。
実装で一覧が変わったときは、プルリクエストに理由を書く。

### 文書

仕様書の依存の図、doc-deps の検査、生成したモジュール、プラグインのない版、diagnostic の埋め込みの節に、`golem-evaluate` を書く。
開発者向けのマニュアルの `02-diagnostics.gm`、`08-build-test.gm`、`10-docs.gm`、`12-purity.gm` と、`docs/diagnostics.md` の「段階とモジュール」の古いモジュールの名前を、`Golem.Evaluate.*` に直す。
開発者向けのマニュアルの `07-modules.gm` に、`golem-evaluate` を足す。
ロードマップの「評価と書き出しを分けること」の項目を消す。

### ステータスの行

採択したら、次の二つの ADR のステータスに、この ADR の変更を記録する。
0199 はすでに `superseded` なので、その配列に要素を足す。

- [root ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md) の「3. プラグインを外すフラグを足す」: flag `plugins` が golem-evaluate の `Golem.Evaluate.Plugins` も切り替えることを補った（`supplement`）。
- [root ADR 0203](0203-generated-modules-instead-of-template-haskell-in-golem-driver.md) の「1. 生成するスクリプト」: `Explain` の生成したモジュールのパスを置き換えた（`replace`）。

### テスト

golem-evaluate には新しいテストのスイートを作らず、移した関数のテストは golem-driver のテストに残す。
テストの import は、`Golem.Evaluate.*` に書き換える。

## 実装しないこと

評価と書き出しの振る舞いを変えない。
golem-lsp が golem-preflight を通して golem-pdf に届くことは、この ADR では切らない。
golem-lsp のテストが golem-typeset と golem-plugin を直に使うことは変えない。
`VERSION` の生成したモジュールは移さない。

## 不変条件

- I1: `golem-evaluate` のライブラリの推移的な依存は、golem-driver、golem-typeset、golem-font、golem-layout、golem-html、golem-epub、golem-pdf を含まない。
- I2: golem-lsp のライブラリの推移的な依存は、golem-driver、golem-typeset、golem-font、golem-layout、golem-html、golem-epub を含まない。
- I3: 同じ入力からの `golem build` の全ターゲットの出力と diagnostic は、この ADR の前と等しい。
- I4: `scripts/gen-embedded.sh` が書いた目録のモジュールは、コミットしたものと等しい。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| `golem-evaluate` の plan.json | 七つのパッケージに届かない | I1 |
| golem-lsp のライブラリの plan.json | 六つのパッケージに届かず、golem-pdf には届く | I2 |
| `golem-evaluate` に golem-typeset を足した試験の plan.json | 検査が落ちる | I1 |
| golem-lsp に golem-driver を足した試験の plan.json | 検査が落ちる | I2 |
| golem-evaluate のライブラリが無い試験の plan.json | 終了コード 2 | I1 |
| 決定性の検査の本 | ハッシュが変わらない | I3 |
| プラグインを使う本の `golem build` | 出力と diagnostic が変わらない | I3 |
| `docs/diagnostics.md` を変えずに `gen-embedded.sh` を走らせる | 差が無い | I4 |

## 受けいれ条件

なし。
不変条件の検査で足りるためである。

## テスト設計

root ADR 0434 I1 と I2 を名前の先頭に置いた検査を、`scripts/ci/test.sh` の doc-deps のテストに足す。
試験の plan.json に、届く場合と届かない場合と、ライブラリが無い場合を足し、検査が落ちることも確かめる。
I1 と I2 の検査は、実装の前に落ちることを確かめる。
I3 は、決定性の検査のハッシュと、golem-driver と golem-lsp の今のテストが変わらず通ることで確かめる。
I4 は、`scripts/test.sh` の `gen-embedded.sh` の検査と、CI の生成の差の検査を新しいパスで通すことで確かめる。

## トレードオフ

パッケージが一つ増え、リポジトリの中の import を書き換える手間がかかる。
その代わりに、golem-lsp は HarfBuzz と FreeType を含む組版のパッケージを組まずに済む。
組み立ての時間がどれだけ縮むかは、計っていない。

golem-lsp は、`Explain` の目録のために、大きな生成したモジュールを今までどおり組む。
目録を別のパッケージに分ければ避けられるが、パッケージがさらに増えるので、この ADR では分けない。

古い名前の下位のモジュールを残さないので、リポジトリの外で `Golem.Driver.Lint` などを import しているコードがあれば、書き換えが要る。

## 参考文献

- [root ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md)
- [root ADR 0196](0196-pass-project-vars-to-golem-typeset.md)
- [root ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md)
- [root ADR 0203](0203-generated-modules-instead-of-template-haskell-in-golem-driver.md)
