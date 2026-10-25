# ADR 0092: golem-test-support の ExternalTool の export を needsTool と optionalTool に絞る

ステータス: 採択

## 文脈

golem-test-support の `Golem.TestSupport.ExternalTool` は、七つの名前を export している（[16 行目から 24 行目](https://github.com/tett23/golem/blob/51fcb43d67aed4f63e1f9b3c88a8a1848f3eb350/modules/golem-test-support/src/Golem/TestSupport/ExternalTool.hs#L16-L24)）。
`needsTool`、`optionalTool`、`toolsRequired`、`needsToolWith`、`optionalToolWith`、`missingTool`、`toolsRequiredBy` である。
`toolsRequired :: IO Bool` は、環境変数 `GOLEM_REQUIRE_EXTERNAL_TOOLS` が `1` のときだけ真を返す（[86 行目から 88 行目](https://github.com/tett23/golem/blob/51fcb43d67aed4f63e1f9b3c88a8a1848f3eb350/modules/golem-test-support/src/Golem/TestSupport/ExternalTool.hs#L86-L88)）。
`toolsRequiredBy :: Maybe String -> Bool` は、その判定を純粋な関数にしたものである。

これらの export には、別々の経緯がある。
[ADR 0028](0028-shared-test-support-package.md) は、公開する関数を `needsTool`、`optionalTool`、`toolsRequired` の三つとした。
四つのパッケージに写しで置かれていた `ExternalTool` の公開の範囲を、そのまま引き継いだ形である。
同じ ADR は、テストのために、必須かどうかを引数で受け取る `needsToolWith` と `optionalToolWith`、ツールがないときの `Result` を作る `missingTool` も公開するとした。
`toolsRequiredBy` は、[ADR 0028](0028-shared-test-support-package.md) のテスト設計から生まれた。
`toolsRequired` は環境変数を読むので、テストの中で `setEnv` せず、純粋な判定を切り出して確かめる、という決定である。

[2026-10-25 のリファクタリングの調査](../audits/2026-10-25-refactoring-survey.md) の R16 は、自分のモジュールの中でしか使われない export を外すよう求めた。
これを実装した [#405](https://github.com/tett23/golem/pull/405) と [#408](https://github.com/tett23/golem/pull/408) は、export を残すかどうかを、使われているかどうかで決めた。
文書が名前を挙げていることは、残す理由にしなかった。
テストスイートが使っている名前は、使われているものとして残した。
#408 は 40 の名前の export を外し、`toolsRequired` の前で止まった。
使われていないのは同じだが、外すと採択済みの [ADR 0028](0028-shared-test-support-package.md) の決定と食い違うからである。

### toolsRequired の使われ方

origin/main（51fcb43d）で `toolsRequired` を `rg -w` で探すと、コードで現れるのは `ExternalTool.hs` の中だけである。

- `needsTool` が `needsToolWith toolsRequired` として使う（[53 行目](https://github.com/tett23/golem/blob/51fcb43d67aed4f63e1f9b3c88a8a1848f3eb350/modules/golem-test-support/src/Golem/TestSupport/ExternalTool.hs#L53)）。
- `optionalTool` が `optionalToolWith toolsRequired` として使う（[72 行目](https://github.com/tett23/golem/blob/51fcb43d67aed4f63e1f9b3c88a8a1848f3eb350/modules/golem-test-support/src/Golem/TestSupport/ExternalTool.hs#L72)）。

`Golem.TestSupport.ExternalTool` を import しているのは、golem-doc、golem-pdf、golem-driver、golem-plugin のテストと、golem-test-support 自身のテストである。
どれも `toolsRequired` を呼ばない。
`scripts/`、`manual/`、`manual-dev/`、`README.md`、`CONTRIBUTING.md`、`CONTRIBUTING.en.md`、`docs/specifications.md` にも、この名前は出てこない。
文書で名前を挙げているのは [ADR 0028](0028-shared-test-support-package.md) だけである。
manual-dev の「決定性を守る」の章は `needsTool` と `optionalTool` を挙げるが、`toolsRequired` には触れていない（[12-determinism.gm の 188 行目](https://github.com/tett23/golem/blob/51fcb43d67aed4f63e1f9b3c88a8a1848f3eb350/manual-dev/part2/12-determinism.gm#L188)）。

### toolsRequiredBy の使われ方

`toolsRequiredBy` は、#408 の基準では使われている名前に当たる。
golem-test-support のテストの `requiredTests` が、五つの値（`1`、未設定、`0`、空、`true`）で呼んでいるからである（[test/Main.hs の 128 行目から 137 行目](https://github.com/tett23/golem/blob/51fcb43d67aed4f63e1f9b3c88a8a1848f3eb350/modules/golem-test-support/test/Main.hs#L128-L137)）。
ほかに呼ぶところはない。
文書で名前を挙げているのは [ADR 0074](0074-test-switches-by-environment-variables.md) だけで、環境変数の読み方を `envFlag` にまとめ、`toolsRequiredBy` もこれを使う、と書いている。

その結果、`toolsRequiredBy` は `envFlagBy` の別名になった（[90 行目から 92 行目](https://github.com/tett23/golem/blob/51fcb43d67aed4f63e1f9b3c88a8a1848f3eb350/modules/golem-test-support/src/Golem/TestSupport/ExternalTool.hs#L90-L92)）。
定義は `toolsRequiredBy = envFlagBy` の一行である。
`requiredTests` が確かめているのは、実のところ `envFlagBy` の振る舞いで、同じファイルの `envFlagTests` とほとんど重なる。
`envFlagTests` にない値は `true` だけである。

しかも、この二つのテストは、`needsTool` と `optionalTool` が `GOLEM_REQUIRE_EXTERNAL_TOOLS` を読むことを確かめていない。
`toolsRequiredBy` は環境変数の名前を知らないからである。
変数の名前を書き誤っても、`requiredTests` は通る。

[ADR 0028](0028-shared-test-support-package.md) がテストの中で `setEnv` しないと決めたのは、環境変数がプロセス全体で一つだからだった。
その後、[ADR 0072](0072-tests-restore-process-environment.md) が、環境変数を書き換えて元に戻す補助 `withEnv` を作った。
[ADR 0086](0086-any-test-suite-may-depend-on-test-support.md) の実装で、`withEnv` は golem-test-support の `Golem.TestSupport.Env` に移り、golem-test-support 自身のテストもそれで変数を書き換えて確かめている（[test/Main.hs の 165 行目から 197 行目](https://github.com/tett23/golem/blob/51fcb43d67aed4f63e1f9b3c88a8a1848f3eb350/modules/golem-test-support/test/Main.hs#L165-L197)）。
golem-test-support-test は `-threaded` でないので、テストは一つずつ走り、書き換えがほかのテストと競合しない。
環境変数を読む `needsTool` と `optionalTool` を、そのまま確かめられるようになった。

### needsToolWith、optionalToolWith、missingTool の使われ方

この三つを呼ぶのも、golem-test-support のテストだけである。
`needsToolTests`、`optionalToolTests` と、省いたテストを数えるテストが呼んでいる（[test/Main.hs の 74 行目から 126 行目](https://github.com/tett23/golem/blob/51fcb43d67aed4f63e1f9b3c88a8a1848f3eb350/modules/golem-test-support/test/Main.hs#L74-L126) と [272 行目から 280 行目](https://github.com/tett23/golem/blob/51fcb43d67aed4f63e1f9b3c88a8a1848f3eb350/modules/golem-test-support/test/Main.hs#L272-L280)）。
golem-doc、golem-pdf、golem-driver、golem-plugin のテストは、`needsTool` と `optionalTool` しか使わない。

ただし、`toolsRequiredBy` とは事情が違う。
三つは別名ではなく、`needsTool` と `optionalTool` の本体である。
必須かどうかを引数で渡せるので、ツールがあるとき、ないとき、必須のとき、必須でないときの組み合わせを、環境変数を書き換えずに確かめられる。
[ADR 0028](0028-shared-test-support-package.md) が三つを作った理由は、まだ働いている。

働いていないのは、公開する理由のほうである。
テストスイートは、ライブラリとは別のコンポーネントである。
cabal は、別のコンポーネントにライブラリの `exposed-modules` のモジュールしか見せない。
golem-test-support のテストが三つを使うために、三つは `Golem.TestSupport.ExternalTool` の export に置かれ、ほかのパッケージのテストにも同じように見えている。

### 使う側が読む名前

公開の範囲を狭めるのは、テストスイートだけが使うパッケージでも、使う側が読む名前の数が負担になるからである。
`Golem.TestSupport.ExternalTool` の export の七つのうち、golem-test-support の外のテストスイートが使うのは `needsTool` と `optionalTool` の二つだけである。
残りの五つは、中の実装の名前、別のモジュールの関数の別名、golem-test-support のテストのための関数である。
使う側は、どれを使えばよいかを読み分けなければならない。

### golem のほかのパッケージの内部のモジュール

golem のパッケージには、名前が `Internal` で終わるモジュールがまだない。
ライブラリに内部のモジュールを持つのは golem-driver だけで、それを `other-modules` に置いて、ほかのパッケージから隠している。
`Golem.Driver.Pdf.Draw` などである（[golem-driver.cabal の 40 行目](https://github.com/tett23/golem/blob/51fcb43d67aed4f63e1f9b3c88a8a1848f3eb350/modules/golem-driver/golem-driver.cabal#L40)）。
この形は、同じパッケージのテストスイートからも使えない。
テストスイートが別のコンポーネントだからである。
同じパッケージのテストだけが使う名前を置く先例は、golem にはない。

Hackage では、名前が `.Internal` で終わるモジュールを `exposed-modules` に置き、公開の約束の外にあることを名前で示すのが慣習である。
bytestring の `Data.ByteString.Internal` や text の `Data.Text.Internal` がこの形をとる。

## 実装すること

### Golem.TestSupport.ExternalTool.Internal を作る

- golem-test-support に、モジュール `Golem.TestSupport.ExternalTool.Internal` を足す。
- `needsToolWith`、`optionalToolWith`、`missingTool` の定義と haddock のコメントを、`Golem.TestSupport.ExternalTool` からこのモジュールに移す。export するのはこの三つだけである。
- 三つが使う型 `NeedsTool` とその `IsTest` のインスタンス、補助の `skippedReason`、`notInstalled`、`requiresIt` も移す。どれも export しない。`ExistentialQuantification` の言語拡張も、`NeedsTool` と一緒に移す。
- 関数の振る舞い、型、haddock のコメントの文面は変えない。
- このモジュールを、golem-test-support のライブラリの `exposed-modules` に足す。golem-test-support のテストスイートは別のコンポーネントなので、`other-modules` に置くと import できない。テストスイートの `hs-source-dirs` に `src` を足して取り込むこともしない。同じモジュールが二度コンパイルされ、ライブラリの `needsTool` が使う型とテストが使う型が別のものになる。
- 公開の約束の外にあることは、名前の `.Internal` と、モジュールの haddock のコメントで示す。コメントには、このモジュールが golem-test-support のテストのためにあること、ほかのパッケージのテストは import せず `Golem.TestSupport.ExternalTool` の `needsTool` と `optionalTool` を使うこと、予告なく変わることを書き、この ADR を挙げる。
- `Golem.TestSupport.ExternalTool` は、このモジュールを import して `needsTool` と `optionalTool` を定義する。

### toolsRequiredBy を消す

- `Golem.TestSupport.ExternalTool` から、`toolsRequiredBy` の export と定義を消す。
- `envFlagBy` の import を消す。`toolsRequiredBy` のほかに使うところがなく、残すと `-Wall` の未使用の import の警告が出る。
- `envFlagBy` は `Golem.TestSupport.Env` から export したまま残す。`envFlag` の判定を確かめる純粋な関数として、[ADR 0074](0074-test-switches-by-environment-variables.md) のとおりに使う。

### toolsRequired を中に閉じる

- `Golem.TestSupport.ExternalTool` の export の一覧から `toolsRequired` を外す。`Internal` のモジュールにも移さない。`toolsRequired` を使うのは `needsTool` と `optionalTool` だけで、golem-test-support のテストも呼ばない。
- 定義は `Golem.TestSupport.ExternalTool` に残す。`needsTool` と `optionalTool` の両方が使うので、環境変数を読む箇所を一つに保てる。`needsTool` と `optionalTool` に `envFlag "GOLEM_REQUIRE_EXTERNAL_TOOLS"` を直接書くと、変数の名前を読む箇所が二つになり、片方だけ直す誤りの余地ができる。
- 定義と haddock のコメントは変えない。

これで、`Golem.TestSupport.ExternalTool` の export は `needsTool` と `optionalTool` の二つになる。
二つの振る舞いは変わらない。
golem-doc、golem-pdf、golem-driver、golem-plugin のテストは、この二つしか使わないので、変更は要らない。

### golem-test-support のテスト

- `test/Main.hs` は、`needsToolWith`、`optionalToolWith`、`missingTool` を `Golem.TestSupport.ExternalTool.Internal` から import する。`needsToolTests`、`optionalToolTests` と、省いたテストを数えるテストの中身は変えない。
- `requiredTests` を消し、`toolsRequiredBy` を呼ぶテストをなくす。
- `requiredTests` にあって `envFlagTests` にない値 `true` を、`envFlagTests` に足す（`true: off`）。これで、`requiredTests` が確かめていた五つの値は、すべて `envFlagBy` のテストに残る。
- `needsTool` と `optionalTool` が `GOLEM_REQUIRE_EXTERNAL_TOOLS` を読むことを確かめるテストを足す。変数は `withEnv` で書き換え、テストの後に元に戻す。中身はテスト設計の節に書く。

### 公開の範囲とテスト設計を決めた ADR のステータス

[ADR 0028](0028-shared-test-support-package.md) の三つの決定が変わる。
一つめは、公開する関数を `needsTool`、`optionalTool`、`toolsRequired` の三つとしたこと（実装すること）である。
二つめは、`needsToolWith`、`optionalToolWith`、`missingTool` を `Golem.TestSupport.ExternalTool` から公開するとしたこと（実装すること）である。
三つは引き続き golem-test-support のライブラリにあるが、置き場所は `Golem.TestSupport.ExternalTool.Internal` になる。
三つめは、`toolsRequired` をテストの中で `setEnv` せず、純粋な判定を切り出して確かめるとしたこと（テスト設計）である。

[ADR 0028](0028-shared-test-support-package.md) のステータスの行は、今「採択→golem-test-support の依存と、golem の型を使わない補助の共有は [ADR 0087](0087-test-support-dependencies-and-shared-fixtures.md)」である。
読点でつないで、後ろに「`Golem.TestSupport.ExternalTool` が公開する関数と、`toolsRequired` の確かめ方は [ADR 0092](0092-remove-tools-required-exports.md)」を足す。

[ADR 0074](0074-test-switches-by-environment-variables.md) は `toolsRequiredBy` の名前を挙げているので、ステータスの行を「採択→`toolsRequiredBy` は [ADR 0092](0092-remove-tools-required-exports.md) で消した」に改める。
[ADR 0074](0074-test-switches-by-environment-variables.md) の `toolsRequiredBy` へのリンクは古いコミットに固定してあるので、そのまま開ける。

[ADR 0028](0028-shared-test-support-package.md) のほかの決定（`needsTool` と `optionalTool` を、必須かどうかを渡す版に `toolsRequired` を渡したものとして定義すること）は変わらない。

### 文書

- `CONTRIBUTING.md` の、外部ツールを使うテストを `needsTool` か `optionalTool` で書くという段落の後に、次の規則を足す。golem のパッケージの、名前が `.Internal` で終わるモジュールは、そのパッケージのテストのためにあり、ほかのパッケージから import しない。今あるのは `Golem.TestSupport.ExternalTool.Internal` だけである。
- `CONTRIBUTING.en.md` の対応する段落の後に、同じ規則を英語で足す。

ほかに変更する文書はない。
`docs/specifications.md`、`manual-dev/`、`README.md` は、`toolsRequired` も `toolsRequiredBy` も、必須かどうかを渡す三つの関数も挙げていない。
`docs/specifications.md` のモジュール構成の節は、golem-test-support を「外部ツールを使うテストの補助 `Golem.TestSupport.ExternalTool`」と述べるだけで、モジュールや公開する関数を列挙していない（[233 行目](https://github.com/tett23/golem/blob/51fcb43d67aed4f63e1f9b3c88a8a1848f3eb350/docs/specifications.md#L233)）。
`ExternalTool.hs` のモジュールの説明も、export をやめる名前を出していない。

## 実装しないこと

- `toolsRequired` の定義を消して、`needsTool` と `optionalTool` に環境変数の読み方を直接書くこと。上のとおり、変数の名前を読む箇所が二つになる。
- `needsToolWith`、`optionalToolWith`、`missingTool` を消し、それらのテストを、どれも環境変数を書き換えて確かめる形に書き直すこと。引数で必須かどうかを渡せば、組み合わせを環境変数なしで確かめられる。`Internal` のモジュールに移せば、この利点を保ったまま公開の範囲から外せる。
- `Golem.TestSupport.ExternalTool.Internal` を、`visibility: private` の内部のライブラリ（cabal の sublibrary）に置くこと。ほかのパッケージから import できないことを cabal が強いるが、三つの名前を隠すためにコンポーネントが一つ増える。golem-test-support はテストスイートだけが使うパッケージで、名前と haddock のコメントで足りる。
- ほかのパッケージが `.Internal` のモジュールを import していないことを、CI で検査すること。今そのモジュールは一つで、使う側が現れる見込みもない。
- 型や、ほかのモジュールの export を見直すこと。

## テスト設計

テストを先に書き、`toolsRequiredBy` を消した状態で `requiredTests` がコンパイルに失敗することを確かめてから、`requiredTests` を消す。
`test/Main.hs` の import を `Golem.TestSupport.ExternalTool.Internal` に改めたのち、`Internal` のモジュールがまだないのでコンパイルに失敗することを確かめてから、モジュールを作る。

golem-test-support の `test/Main.hs` に、次のテストを足す。
`GOLEM_REQUIRE_EXTERNAL_TOOLS` は `withEnv` で書き換え、テストの後に元の値に戻す。
CI は、この変数を `1` にして走らせるので、戻さないとほかのテストの結果が変わる。

- ツールのない `needsTool` のテストは、`GOLEM_REQUIRE_EXTERNAL_TOOLS=1` のもとで失敗し、説明は `tool is not installed, and GOLEM_REQUIRE_EXTERNAL_TOOLS=1 requires it` である。
- 同じテストは、`GOLEM_REQUIRE_EXTERNAL_TOOLS` が `0` と `true` のもとで成功し、`resultShortDescription` は `SKIP` である。
- ツールのない `optionalTool` は、`GOLEM_REQUIRE_EXTERNAL_TOOLS=1` のもとで例外を投げ、`0` のもとで `Nothing` を返す。
- `envFlagTests` に `true: off` を足す。

値の判定の全体（未設定、空、`0`、`yes`、`true`）は `envFlagBy` のテストが受け持つ。
`needsTool` と `optionalTool` のテストが受け持つのは、正しい名前の変数を読み、その値で振る舞いが分かれることである。
未設定の場合は、`withEnv` が変数を消せないので、`needsTool` のテストでは扱わない。

確かめ方は次のとおりである。

- `cabal build all` が警告なしで通る。`toolsRequired` は export しなくても `needsTool` と `optionalTool` が使うので、`-Wall` の未使用の定義の警告は出ない。
- `cabal test all` が通る。golem-test-support-test のテストの数は、`requiredTests` の五つが減り、上で足す六つ（`needsTool` の三つ、`optionalTool` の二つ、`envFlagBy` の一つ）が増える。ほかのテストスイートのテストの数は変わらない。`GOLEM_REQUIRE_EXTERNAL_TOOLS=1` を付けても付けなくても同じである。
- `rg -w toolsRequiredBy modules` が何も返さない。
- `rg -w toolsRequired modules` が、`ExternalTool.hs` の定義と二つの呼び出しだけを示す。
- `rg -l 'Golem\.TestSupport\.ExternalTool\.Internal' modules` が、golem-test-support の `golem-test-support.cabal`、`ExternalTool.hs`、`ExternalTool/Internal.hs`、`test/Main.hs` だけを示す。
- `rg -w 'needsToolWith|optionalToolWith|missingTool' modules` が、golem-test-support の `src` と `test` の中だけを示す。
- #408 の手順（各 `src` のモジュールの export の一覧の値を、そのモジュールを import するファイルで探す）をもう一度行うと、#408 が「Left exported」に残した名前から `toolsRequired` が消える。

## トレードオフ

- golem-test-support の外のテストが、環境変数の判定だけを使いたくなったときは、export を戻す変更が要る。今そのようなテストはなく、使う側が現れた時点で戻せば足りる。golem-test-support はテストスイートだけが使うパッケージで、外の利用者に対する互換性を考える必要はない。判定そのものは `envFlagBy` と `envFlag` で使える。
- `Golem.TestSupport.ExternalTool.Internal` は `exposed-modules` にあるので、ほかのパッケージのテストも import できる。止めるのは名前と haddock のコメントと `CONTRIBUTING.md` の規則だけで、cabal も CI も止めない。
- golem で初めての `.Internal` のモジュールになり、同じパッケージのテストだけが使う名前の置き場所の先例になる。ほかのパッケージで同じ必要が出たときも、この形に倣う。
- golem-test-support のテストが、プロセスの環境変数 `GOLEM_REQUIRE_EXTERNAL_TOOLS` を書き換えるようになる。[ADR 0028](0028-shared-test-support-package.md) が避けたことである。書き換えは `withEnv` で戻し、golem-test-support-test は `-threaded` でないので、同時に走るテストはない。このテストスイートを `-threaded` にするときは、これらのテストを見直す必要がある。
- 採択済みの ADR が決めた公開の範囲とテスト設計を、新しい ADR で狭める先例になる。ADR で名前を挙げた export でも、使われなくなるか別名にすぎなくなれば、新しい ADR で外せる、という運用である。ADR を一本ずつ書く手間はかかるが、ADR の決定を黙って破らずに済む。

## 参考文献

- [ADR 0028: テストの補助を共有するパッケージ](0028-shared-test-support-package.md)
- [ADR 0072: 環境変数を書き換えるテストは、書き換えを元に戻す](0072-tests-restore-process-environment.md)
- [ADR 0074: テストを切り替える環境変数の値の読み方をそろえ、省いたテストを数える](0074-test-switches-by-environment-variables.md)
- [ADR 0086: どのテストスイートも golem-test-support に依存してよいとする](0086-any-test-suite-may-depend-on-test-support.md)
- [ADR 0087](0087-test-support-dependencies-and-shared-fixtures.md)
- [2026-10-25 のリファクタリングの調査](../audits/2026-10-25-refactoring-survey.md) の R16
- [#405 Stop exporting names that only their own module uses (R16)](https://github.com/tett23/golem/pull/405)
- [#408 Stop exporting the rest of the names only their own module uses (R16)](https://github.com/tett23/golem/pull/408)
- [Cabal User Guide: Package Description（library の exposed-modules と other-modules、sublibrary の visibility）](https://cabal.readthedocs.io/en/stable/cabal-package-description-file.html)
