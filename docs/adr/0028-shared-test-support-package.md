# ADR 0028: テストの補助を共有するパッケージ

ステータス: 採択

## 文脈

外部ツール（`cddl`、`qpdf`、`openssl`）を使うテストは、テストの補助のモジュール `ExternalTool` を通して書く。
ツールが見つからないとき、テストは成功の扱いのまま `SKIP` と表示される。
環境変数 `GOLEM_REQUIRE_EXTERNAL_TOOLS=1` があるときは、ツールがないことがテストの失敗になり、CI はこれを付けてテストを実行する（`.github/workflows/ci.yml`、README の「外部ツール」の段落）。

このモジュールは、golem-doc、golem-pdf、golem-driver、golem-plugin の `test/ExternalTool.hs` に、同じ内容で四つ置かれている。
四つのファイルのバイト列は一致しており、モジュールの説明にも「The same module is in the test directory of each package that uses it」と書いてある。
テストの補助を共有する場所がリポジトリにないので、写しで済ませた形である。
写しは、一つを直すと残りの三つも同じように直す必要があり、直し忘れても検出する仕組みがない。

テストのディレクトリを調べると、ほかに内容の同じファイルが二組ある。

- **SourceSerif のフォント**：golem-font の `test/fonts/SourceSerifVariable-Roman.ttf` と、golem-driver の `test/fixtures/tempest/fonts/SourceSerifVariable-Roman.ttf`。ライセンスの文書（`OFL.txt` と `LICENSE-SourceSerif.txt`）も内容が同じである。
- **golem-cli のゴールデンファイル**：`test/golden/help.txt` と `test/golden/no-arguments.txt`。同じパッケージの中の二つの期待値であり、引数なしの実行がヘルプと同じ出力になるという仕様をそれぞれ固定している。

また、`codes`（診断のリストからコードを取り出す）や `sp`（テスト用の `SrcSpan`）のような一行の補助が、いくつかのパッケージに似た名前で定義されている。
ただし、型も定義も揃っていない（`codes` の引数は、パッケージによって `[Diagnostic]`、`Text`、`Either [Diagnostic] a` である）。

## 実装すること

### パッケージ golem-test-support

`modules/golem-test-support` に、ライブラリだけを持つパッケージ `golem-test-support` を新しく置く。
テストスイートだけが使うパッケージであり、名前でそれを示す。

- モジュールは `Golem.TestSupport.ExternalTool` 一つである。公開する関数は今の `ExternalTool` と同じ `needsTool`、`optionalTool`、`toolsRequired` である。
- テストのために、環境変数を読む代わりに「必須かどうか」を引数で受け取る版（`needsToolWith :: IO Bool -> ...`、`optionalToolWith :: IO Bool -> ...`）と、ツールがないときの `Result` を作る `missingTool` を公開する。`needsTool` と `optionalTool` は、これらに `toolsRequired` を渡したものとして定義する。
- 依存は `base` と `tasty` だけにする（`Test.Tasty.Providers` と `Test.Tasty.Runners` は `tasty` にある）。golem のほかのパッケージには依存しない。
- 版は、ほかのパッケージと同じく `VERSION` の X.Y.Z にする。`scripts/release/check-version.sh` が `modules/*/*.cabal` のすべてを検査するためである。
- cabal のファイルの `common warnings` は、ほかのパッケージと同じものにする。
- テストスイート `golem-test-support-test` を持つ（テスト設計の節）。

### 移行

golem-doc、golem-pdf、golem-driver、golem-plugin で、次の三つを一つの変更で行う。

1. `test/ExternalTool.hs` を消す。
2. cabal のファイルのテストスイートの `other-modules` から `ExternalTool` を除き、`build-depends` に `golem-test-support` を足す。
3. テストの `import ExternalTool` を `import Golem.TestSupport.ExternalTool` に変える。

関数の名前と型は変えないので、テストの本体は変えない。

### リリースのビルドに入らないことの検査

golem の実行ファイルは、golem-test-support に依存してはいけない。
リリースのビルドは `cabal build exe:golem` で、`exe:golem` の依存だけをビルドするので、テストスイートだけが依存するパッケージはビルドされず、リンクもされない。
`scripts/release/licenses.sh` も `exe:golem` の依存だけを辿り、`golem-` で始まるパッケージを除くので、変更はいらない。

この前提を、cabal が解決した依存の計画（`dist-newstyle/cache/plan.json`）の検査で守る。
cabal のファイルを読むのではなく計画を読むのは、条件の節（`if os(darwin)` など）や `common` の節の `import` を cabal 自身が解いた後の依存を見るためである。

新しいスクリプト `scripts/ci/test-only-deps.sh PLAN_JSON` は、jq で計画を読み、次を確かめる。

- **起点**：計画の `install-plan` のうち、`style` が `local` の要素の、ライブラリ（`lib` と `lib:*`）と実行ファイル（`exe:*`）の部品。部品ごとの要素（`component-name` を持つ）と、パッケージごとの要素（`components` の表を持つ）の両方を扱う。golem-test-support 自身の部品は起点から除く。
- **辿り方**：`depends` と、パッケージごとの要素の `lib` の部品の `depends` を、推移的に辿る。`exe-depends`（ビルドのための道具）と `setup` は辿らない。`scripts/release/licenses.sh` が `exe:golem` の依存を辿る規則と同じである。
- **判定**：辿った先に `pkg-name` が `golem-test-support` の要素があれば、起点の部品の名前（`golem-driver:lib` など）を標準エラーに一行ずつ書き、終了コード 1 で終わる。なければ終了コード 0 で終わる。
- **計画を読めないとき**：ファイルがない、JSON として読めない、`install-plan` がない場合は、理由を標準エラーに書いて終了コード 2 で終わる。検査を飛ばして成功にはしない。

ライブラリも起点にするのは、ライブラリが依存すると、そのライブラリを使う実行ファイルが後から依存しうるからである。
実行ファイルだけを起点にすると、どの実行ファイルもまだ使っていないライブラリの依存を見逃す。

このスクリプトは二か所で実行する。

- **CI**：`ci.yml` の `build` のジョブで、`cabal build all` の直後に実行する。`build` は計画を作るジョブであり、`tests: True` の下で全パッケージの部品が計画に入る。新しいジョブは足さない。
- **リリース**：`scripts/release/package.sh` で、`licenses.sh` を呼ぶ前に、同じ計画に対して実行する。リリースのビルドは `cabal build exe:golem` だけをビルドするが、計画は全パッケージについて作られるので、同じ検査ができる。失敗すれば配布物を作らない。

### CI の変更の検出

`scripts/ci/needs-build.sh` は、`docs/` の下とルートの Markdown 以外の変更で、ビルドとテストを全体に対して行う。
モジュールごとに変更を検出する仕組みはないので、`modules/golem-test-support` の変更は、ほかのモジュールの変更と同じくビルドとテストの全体を走らせる。
`needs-build.sh` は変えない。
fourmolu と hlint は `modules/` の下をすべて対象にしているので、新しいパッケージも検査される。

### フィクスチャは対象にしない

golem-test-support は Haskell のモジュールだけを持ち、フォントなどのフィクスチャのファイルは持たない。
SourceSerif のフォントの写しは、次の理由で今のまま残す。

- golem-driver の `test/fixtures/tempest/` は、`manifest.toml` と `style.toml` と原稿とフォントを持つ一つのプロジェクトであり、テストはこのディレクトリをそのままプロジェクトとしてビルドする。フォントをほかの場所から参照すると、`style.toml` のフォントのパスがプロジェクトのルートの外を指すことになり、golem-driver の検査が G0802（プロジェクトルートの外を指しています）で拒む。プロジェクトとして閉じていることが、このフィクスチャの役割である。
- ほかのテストは、すでに `../golem-font/test/fonts/` を相対パスで直接読んでいる。パッケージをまたいでファイルを読む方法はこれで足りており、フォントを cabal の `data-files` にして共有する理由がない。
- `data-files` で共有すると、テストの実行時にパスを `Paths_golem_test_support` で引く必要があり、相対パスで読むより手順が増える。

golem-cli の二つのゴールデンファイルは、別の仕様をそれぞれ固定する期待値なので、内容が同じでも一つにしない。

### 一行の補助は対象にしない

`codes` や `sp` のような補助は、パッケージごとに型と定義が違い、golem-syntax の型に依存する。
golem-test-support に入れると、このパッケージが golem-syntax に依存し、依存を `tasty` だけに絞れなくなる。
これらは各パッケージのテストに残す。

### 文書

- `README.md` の外部ツールの段落に、テストの補助が `modules/golem-test-support` にあることを一文で足す。
- `CONTRIBUTING.md` と `CONTRIBUTING.en.md` に、外部ツールを使うテストは golem-test-support の `needsTool` か `optionalTool` で書くことを足す。
- `manual-dev/part2/07-modules.gm` のモジュールの一覧の表に、golem-test-support を「テストの補助（テストスイートだけが使う）」として足す。golem-syntax の行の「golem-regex、golem-font、golem-fixtures を除く」に golem-test-support を加える。
- `manual-dev/part2/08-build-test.gm` の外部ツールの段落に、golem-test-support を一文で足す。
- `docs/specifications.md` のモジュール構成の節で、golem-syntax を使わないモジュールの列挙に golem-test-support を加え、図の後の golem-fixtures の段落と同じく、図に含めないことと、golem の実行ファイルが依存せずリリースの配布物に入らないことを書く。モジュールの依存の図（mermaid と `manual-dev/images/modules.png`）には加えない。

## 実装しないこと

- フィクスチャ（フォント、ゴールデンファイル、プロジェクトのディレクトリ）の共有。
- `codes`、`sp` のような、golem の型に依存するテストの補助の共有。
- 外部ツールの探し方（`findExecutable`、`GOLEM_CDDL` など）の共通化。探し方は今どおり各テストが `locate` として渡す。
- `ExternalTool` の振る舞いの変更。`SKIP` の表示、メッセージ、環境変数の名前と値は今のままにする。
- モジュールごとの CI の変更の検出。

## テスト設計

### golem-test-support のテスト

パッケージを作り、テストを先に書いて、`Golem.TestSupport.ExternalTool` がない状態でコンパイルが失敗することを確かめてから、今の `ExternalTool.hs` を移す。
テストは `run`（`Test.Tasty.Providers`）で、`needsToolWith` が包んだテストを直接実行して結果を見る。
環境変数は書き換えず、「必須かどうか」は引数で渡す。

- ツールがあり（`locate` が `Just`）、中のテストが成功するとき、結果は成功で、`resultShortDescription` は `SKIP` ではない。
- ツールがあり、中のテストが失敗するとき、結果は失敗である。
- ツールがなく、必須でないとき、結果は成功で、`resultShortDescription` は `SKIP`、説明は `<名前> is not installed; GOLEM_REQUIRE_EXTERNAL_TOOLS=1 makes this a failure` である。
- ツールがなく、必須のとき、結果は失敗で、説明は `<名前> is not installed, and GOLEM_REQUIRE_EXTERNAL_TOOLS=1 requires it` である。
- `needsToolWith` は、`TestGroup` の中のすべての `SingleTest` を包む。二段のグループの中のテストも `SKIP` になる。
- `optionalToolWith`：ツールがあればそのパスを返し、なくて必須でなければ `Nothing` を返し、なくて必須なら例外を投げる。
- `toolsRequired` は、`GOLEM_REQUIRE_EXTERNAL_TOOLS` が `1` のときだけ真である。このテストだけは環境変数を読むので、テストの中で `setEnv` せず、純粋な判定（`Maybe String -> Bool`）を切り出して確かめる。

### 移行の確かめ

- `GOLEM_REQUIRE_EXTERNAL_TOOLS=1` を付けた `cabal test all` が、移行の前と後で同じテストの数で通る。
- 外部ツールのない環境で `cabal test all` を実行し、`SKIP` と表示されるテストの名前が、移行の前と後で同じである。
- `find modules -name ExternalTool.hs` が何も返さない。

### test-only-deps.sh のテスト

`scripts/ci/test.sh` に次を足す。
入力の計画は、`scripts/ci/testdata/` に小さな JSON として置く（要素は数個で、実際の計画から必要な欄だけを残す）。

- golem-test-support が、テストスイートの部品（`test:*`）からだけ依存される計画で、終了コード 0。
- 実行ファイルの部品が、golem-test-support に直接依存する計画で、終了コード 1。標準エラーにその部品の名前が出る。
- 実行ファイルの部品が、ほかのライブラリを通して推移的に依存する計画で、終了コード 1。標準エラーに実行ファイルとライブラリの両方の名前が出る。
- ライブラリの部品だけが依存し、どの実行ファイルもそのライブラリを使わない計画で、終了コード 1。
- パッケージごとの要素（`components` の表）の `lib` の部品が依存する計画で、終了コード 1。
- `exe-depends` からだけ辿れる計画（ビルドの道具が依存する）で、終了コード 0。
- `style` が `local` でない要素（Hackage のパッケージ）が依存する計画で、終了コード 0。起点にしないためである（実際にはありえないが、規則を固定する）。
- golem-test-support が計画にない場合に、終了コード 0。
- ファイルがない場合、JSON でない場合、`install-plan` がない場合に、終了コード 2。

### CI とリリースでの確かめ

- CI の `build` のジョブで、移行の後の計画に対して終了コード 0 になる。
- 移行の後に、一時的に golem-driver のライブラリの `build-depends` に golem-test-support を足し、CI と同じ手順（`cabal build all` の後に `test-only-deps.sh`）で終了コード 1 になることを手で確かめる（コミットしない）。
- `package.sh` には今テストがないので、`test-only-deps.sh` を呼ぶ一行は自動のテストを書かない。リリースのワークフローを `workflow_dispatch` で一度動かし、ログに検査の実行が出ることを確かめる。

## トレードオフ

- パッケージが一つ増え、ビルドの単位も増える。依存は `base` と `tasty` だけなので、ビルドの時間はほとんど増えない。
- テストだけが使うパッケージを `modules/` に置くと、モジュールの一覧に製品の部品でないものが混ざる。golem-fixtures と同じ扱い（一覧には載せ、依存の図には載せない）にして、区別を文書で示す。
- 写しのままにする案もある。写しは四つのパッケージが独立にビルドできる利点を持つが、cabal のプロジェクトは全パッケージを一度にビルドするので、その利点は使われていない。
- 計画を読む検査は、計画を作った後（`cabal build` の後）でなければ動かない。cabal のファイルを読む検査なら変更の直後の `changes` のジョブで動くが、条件の節と `import` を自前で解くことになる。cabal が解いた結果を使うほうが単純なので、ビルドの後に動くことを受け入れる。
- 計画の JSON の形は cabal の版に依存する。`licenses.sh` がすでに同じ形を読んでいるので、cabal を上げるときに両方を一緒に確かめる。
- フォントのフィクスチャを共有しないので、SourceSerif のフォント（約 570 KB）とライセンスの文書がリポジトリに二つずつ残る。

## 参考文献

- tasty の `Test.Tasty.Providers` と `Test.Tasty.Runners`：https://hackage.haskell.org/package/tasty
