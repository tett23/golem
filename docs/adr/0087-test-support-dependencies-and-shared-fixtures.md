# ADR 0087: golem-test-support が依存してよいパッケージと、パッケージをまたぐテストの値

ステータス: 採択（未実装）

## 文脈

[ADR 0028](0028-shared-test-support-package.md) は、golem-test-support の依存を `base` と `tasty` だけにした（[ADR 0028 の実装すること](0028-shared-test-support-package.md)）。
同じ ADR は、`codes` や `sp` のような一行の補助を対象から外した。
理由は、それらが golem-syntax の型に依存し、入れると依存を `tasty` だけに絞れなくなることだった。

[2026-10-25 のリファクタリングの調査](../audits/2026-10-25-refactoring-survey.md) の R23 は、パッケージをまたいで重なるテストの値として、manifest のリテラル、`sp`、`hex`、`genText` を挙げた。
調査は、これらを一つにするには golem-test-support が golem-syntax に依存する必要があるとした。
コードを読むと、この前提が当てはまるのは `sp` だけである。

- **`hex`**：[golem-pdf のテスト](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-pdf/test/Main.hs#L45-L48) と [golem-syntax のテスト](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-syntax/test/Main.hs#L333-L336) で本体が同じである。バイト列を小文字の十六進の文字列にする関数で、要るのは `bytestring` だけである。
- **`genText`**：[golem-syntax のテスト](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-syntax/test/Main.hs#L24-L31) と [golem-lsp のテスト](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-lsp/test/Main.hs#L81-L86) で本体が同じである。ASCII、仮名、漢字、改行、4 バイトの文字を混ぜ、バイト、コードポイント、UTF-16 の単位の数がずれる文字列を作る。要るのは `hedgehog` と `text` である。同じ名前の [golem-doc の Gen.hs](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-doc/test/Gen.hs#L18-L19) と [golem-font の ConcurrencySpec](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-font/test/ConcurrencySpec.hs#L60-L61) は、文字の集合も長さも違う別の生成器である。
- **manifest のリテラル**：`urn:uuid:11111111-2222-4333-8444-555555555555` を書いた行が、Haskell のテストのソースに golem-cli で 9 行、golem-lsp で 5 行、golem-driver で 4 行ある（調査は 14 箇所とした）。中身は TOML の文字列で、要るのは `text` だけである。章、`title`、`language`、ターゲット、`[[metadata.creators]]` などの追加の節が箇所ごとに違い、`id` と `date = 2026-10-11` と節の並びが共通である。例として [golem-cli の Main.hs の 192 行目](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-cli/test/Main.hs#L192)、[golem-lsp の TableWatchSpec](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-lsp/test/TableWatchSpec.hs#L31)、[golem-driver の Support.hs](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-driver/test/Support.hs#L174) がある。
- **`sp`**：golem-syntax の `SrcSpan` を返すので、置けば golem-syntax への依存が要る。ただし、値も型も揃っていない。golem-doc の [ListMarkersSpec](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-doc/test/ListMarkersSpec.hs#L10-L11)、[Main.hs](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-doc/test/Main.hs#L35-L36)、[CborExprSpec](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-doc/test/CborExprSpec.hs#L26-L27) と [golem-lint](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-lint/test/Main.hs#L32-L33) は `FileId 0` の 0 から 1、[golem-layout の Fixtures.hs](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-layout/test/Fixtures.hs#L27-L28) は `FileId 0` の幅 0、[golem-eval の RegexStyleSpec](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-eval/test/RegexStyleSpec.hs#L15-L16) は `FileId 1` の幅 0 である。[golem-text](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-text/test/Main.hs#L52-L53) と [golem-doc の AssembleSpec](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-doc/test/AssembleSpec.hs#L18-L19) は引数を取る関数である。同じ値は golem-doc と golem-lint の二つのパッケージにしかない。

したがって、R23 のうち共有する価値のある三つは、golem のパッケージに依存せずに置ける。
[ADR 0028](0028-shared-test-support-package.md) が依存を `base` と `tasty` に絞ったのは、golem-syntax に依存しないためであり、Hackage のパッケージを避けるためではない（[ADR 0028](0028-shared-test-support-package.md) の「一行の補助は対象にしない」）。
ただ、今の依存の規則は「`base` と `tasty` だけ」なので、`bytestring` や `hedgehog` を足すにも決定が要る。

## 実装すること

### golem-test-support の依存の規則

- golem-test-support は、`modules/` のパッケージ（golem-\*）に依存しない。直接も、ほかのパッケージを通してもである。
- golem-test-support は、Hackage のパッケージのうち、`cabal.project.freeze` で版を固定してあり、いずれかのテストスイートがすでに依存しているものに依存してよい。依存を足すのに ADR は要らない。
- この ADR で足すのは `bytestring`、`text`、`hedgehog` である。版の範囲は、ほかのパッケージの cabal のファイルと同じ（`bytestring >=0.11 && <0.13`、`text >=2.0 && <2.2`、`hedgehog >=1.4 && <1.6`）にする。

### 規則の検査

`scripts/ci/test-only-deps.sh` に、二つめの判定を足す。

- **判定**：計画の `install-plan` の、`pkg-name` が `golem-test-support` のライブラリの部品（部品ごとの要素なら `component-name` が `lib` のもの、パッケージごとの要素なら `components` の `lib`）を起点に、`depends` を推移的に辿る（辿り方は今の判定と同じ）。golem-test-support 自身のテストスイートの部品は起点にしない。このテストスイートは golem-test-support のライブラリに依存するのが正しいからである。辿った先に `style` が `local` の要素があれば、その `pkg-name` を `test-only-deps: golem-test-support depends on <名前>, a package of this repository` の形で標準エラーに一行ずつ書き、終了コード 1 で終わる。
- 今の判定（ライブラリと実行ファイルが golem-test-support に依存しない）は変えない。二つの判定のどちらかが失敗すれば、終了コード 1 にする。
- 計画を読めないときの終了コード 2 も変えない。

### 共有する値と置き場

| モジュール | 名前 | 中身 |
| --- | --- | --- |
| `Golem.TestSupport.Bytes` | `hex :: ByteString -> String` | 今の `hex` の本体 |
| `Golem.TestSupport.Gen` | `genText :: Gen Text` | golem-syntax と golem-lsp の `genText` の本体 |
| `Golem.TestSupport.Manifest` | `testBookId :: Text` | `"urn:uuid:11111111-2222-4333-8444-555555555555"` |
| `Golem.TestSupport.Manifest` | `TestManifest (..)`、`testManifest :: TestManifest`、`manifestToml :: TestManifest -> Text` | 下の manifest の組み立て |

`TestManifest` は、章（`tmChapters :: [Text]`）、題（`tmTitle :: Text`）、言語（`tmLanguage :: Text`）、`date` の行の後に挟む文字列（`tmExtra :: Text`）、ターゲット（`tmTargets :: [Text]`）を持つ。
`testManifest` は、章が `a.gm` の一つ、題が `T`、言語が `ja`、挟む文字列が空、ターゲットが `html` の一つである。
`manifestToml` は、次の文字列を返す。

```
"chapters = [" <> 章をそれぞれ "\"" で囲み ", " でつないだもの <> "]\n\n[metadata]\nid = \""
  <> testBookId <> "\"\ntitle = \"" <> 題 <> "\"\nlanguage = \"" <> 言語
  <> "\"\ndate = 2026-10-11\n" <> 挟む文字列
  <> ターゲットごとに "\n[targets." <> ターゲット <> "]\n" をつないだもの
```

値に `"` と `\` を含めることは想定せず、引用符の中を逃がさない。
テストの入力として固定の文字列を作るためのもので、TOML の書き出しではないからである。
この形は、今のリテラルのうち `id` の後が `title`、`language`、`date` の順で、ターゲットの節で終わるものと、バイト列で一致する。
たとえば `testManifest { tmTargets = ["html", "epub", "text"] }` は、[golem-driver の DiagnosticsSpec の 225 行目](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-driver/test/DiagnosticsSpec.hs#L225) の manifest と同じバイト列になる。

### 置き換える箇所

- `hex`：golem-pdf と golem-syntax のテストの定義を消し、`Golem.TestSupport.Bytes` を使う。
- `genText`：golem-syntax と golem-lsp のテストの定義を消し、`Golem.TestSupport.Gen` を使う。golem-doc と golem-font の `genText` は別の生成器なので残す。
- manifest：golem-cli、golem-lsp、golem-driver のテストのリテラルのうち、`manifestToml` で同じバイト列を作れるものを置き換える。呼び出し側は、リテラルの型が `ByteString` なら `TE.encodeUtf8` で、`String` なら `T.unpack` で変換する。同じバイト列を作れない箇所（たとえば [golem-driver の ColophonSpec](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-driver/test/ColophonSpec.hs#L26-L45) のように `date` の後に別のキーを並べ、節の区切りが違うもの）は、`testBookId` だけを使うか、そのまま残す。テストの入力を変えないことを優先する。
- fixture のファイル（`test/fixtures/*/manifest.toml`）と golden のファイルは変えない。

### build-depends の変更

| パッケージ | 部品 | 変更 |
| --- | --- | --- |
| golem-test-support | library | `bytestring`、`text`、`hedgehog` を足す。`exposed-modules` に `Golem.TestSupport.Bytes`、`Golem.TestSupport.Gen`、`Golem.TestSupport.Manifest` を足す |
| golem-test-support | golem-test-support-test | `bytestring`、`text`、`hedgehog` を足す |
| golem-syntax | golem-syntax-test | `golem-test-support` を足す |
| golem-cli | golem-cli-test | `golem-test-support` を足す |
| golem-lsp | golem-lsp-test | [ADR 0086](0086-any-test-suite-may-depend-on-test-support.md) が足した `golem-test-support` を使う。[ADR 0086](0086-any-test-suite-may-depend-on-test-support.md) より先に実装するなら、ここで足す |
| golem-pdf、golem-driver | テストスイート | 変えない（すでに依存している） |

golem-syntax-test と golem-cli-test が依存してよいことは、[ADR 0086](0086-any-test-suite-may-depend-on-test-support.md) の方針による。
ライブラリと実行ファイルの build-depends は、どのパッケージでも変えない。

### 依存のグラフ

golem-test-support から golem のパッケージへの辺はないままなので、閉路はできない。

```
前：golem-test-support   → base, tasty
    golem-syntax-test    → golem-syntax
    golem-cli-test       → golem-doc, golem-driver, golem-eval, golem-project, golem-syntax
後：golem-test-support   → base, tasty, bytestring, text, hedgehog
    golem-syntax-test    → golem-syntax, golem-test-support
    golem-cli-test       → golem-doc, golem-driver, golem-eval, golem-project, golem-syntax, golem-test-support
```

### 文書

- `docs/specifications.md` のモジュール構成の節の golem-test-support の段落（[229 行目から 232 行目](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/docs/specifications.md#L229-L232)）の「外部ツールを使うテストの補助 `Golem.TestSupport.ExternalTool` と、いくつもの capability で動作を同時に走らせる補助 `Golem.TestSupport.Parallel` などを持ち、`base` と `tasty` だけに依存する」を、テストの補助を持ち、golem のパッケージに依存しないこと、Hackage の依存は版を固定してテストスイートが使っているものに限ることに改める。`test-only-deps.sh` が golem-test-support の依存も確かめることを足し、この ADR へのリンクを付ける。
- `modules/golem-test-support/golem-test-support.cabal` の `description` に、golem のパッケージに依存しないことを足す。
- `CONTRIBUTING.md` と `CONTRIBUTING.en.md` に、golem-test-support が golem のパッケージに依存してはいけないこと、`test-only-deps.sh` がそれを確かめることを足す。
- `manual-dev/part2/11-ci-jobs.gm`（[104 行目](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/manual-dev/part2/11-ci-jobs.gm#L104)）の `test-only-deps.sh` の説明に、二つめの判定を足す。
- [ADR 0028](0028-shared-test-support-package.md) のステータスの行を「採択→golem-test-support の依存と、golem の型を使わない補助の共有は [ADR 0087](0087-test-support-dependencies-and-shared-fixtures.md)」に改める。

## 実装しないこと

- `sp`、`codes` のような、golem の型を使う補助の共有。値も型も揃っておらず、置けば golem-test-support が golem-syntax に依存する。`sp` はこの ADR の範囲に入れない。
- 長さの単位 sp の変換と、単位の変換の全体を一つにすること。下の「単位の変換の統一」に書く。
- golem-test-support が golem のパッケージに依存すること。
- fixture のファイル（フォント、プロジェクトのディレクトリ、golden）の共有（[ADR 0028](0028-shared-test-support-package.md) の「フィクスチャは対象にしない」のまま）。
- golem-pdf と golem-epub のテストの、manifest でない場所の `urn:uuid:11111111-...`（PDF の文書の ID と EPUB の識別子）の置き換え。manifest の値と同じであることに意味がなく、テストの読みやすさのほうが大きい。
- golem-doc と golem-font の `genText` を一つにすること。別の目的の生成器である。

### 単位の変換の統一

テストの補助の `sp` は、ソースの位置 `SrcSpan` を作る関数である。
長さの単位の sp（1pt の 65536 分の 1）とは名前が同じだけで、関係はない。
それでも、名前の重なりから、単位の sp の扱いについてメンテナが警告したことをここに残す。

sp との相互の変換と、単位の変換の全体（sp と mm、pt、in、zw などのあいだ）は、一か所にまとめなければならない。
まとめないと、同じ長さを別々の変換で直した値が、少しずつ食い違っていく。
[2026-10-25 のリファクタリングの調査](../audits/2026-10-25-refactoring-survey.md) は、その食い違いがすでにあることを示した。
R11 は、sp から mm への変換が三通りあり、桁数、丸め、負の値の符号の扱いがそれぞれ違うことを挙げた（golem-preflight の `mmText`、golem-driver の `Golem.Driver.Pdf.Flow` の局所の `mm`、golem-project の `Golem.Project.Style` の `spToMm` と `mm2`）。
R13 は、`type Sp = Integer` が六か所で別々に宣言されていることを挙げた。

この統一は、この ADR では扱わない。
テストの補助の共有とは別の主題であり、丸めを揃えると diagnostic の文言が変わるので、出力を変える変更として別の ADR が要る。
rc4 の項目「単位の変換の統一」として [ロードマップ](../roadmap.md#v010-rc4) に置いた。
数の扱いが変わるので、rc4 の「数を有理数に寄せる」と同じ時期に扱う。

## テスト設計

### golem-test-support のテスト

テストを先に書き、モジュールがない状態でコンパイルが失敗することを確かめてから実装する。

- `hex ""` は `""`、`hex "\x00\x0f\xff"` は `"000fff"` である。
- `genText` の値は、`Gen.sample` で 100 個取り、すべての文字が `"ab 漢字かな\r\n😀𠮷x"` に含まれ、長さが 0 以上 80 以下である。
- `manifestToml testManifest` は、[golem-lsp の TableWatchSpec の 31 行目](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-lsp/test/TableWatchSpec.hs#L31) のリテラルと同じ文字列である。
- `manifestToml testManifest { tmTargets = ["html", "epub", "text"] }` は、golem-driver の DiagnosticsSpec の 225 行目の manifest と同じ文字列である。
- `manifestToml testManifest { tmChapters = ["a.gm", "b.gm"] }` は、[golem-cli の CommandsSpec の `manifestWith`](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-cli/test/CommandsSpec.hs#L101-L105) に `["a.gm", "b.gm"]` を渡した文字列と同じである。
- 追加の節を挟む例として、[golem-lsp の Main.hs の 305 行目](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-lsp/test/Main.hs#L305) の manifest と同じ文字列を `tmExtra` で作れる。
- 期待値の文字列は、上のリテラルを今の形のままテストに書き写す。置き換えた後もリテラルが一つ残り、`manifestToml` を変えればこのテストが落ちる。

### test-only-deps.sh のテスト

`scripts/ci/test.sh` に次を足し、`scripts/ci/testdata/test-only-deps/` に小さな計画を置く。
スクリプトを変える前に足し、落ちることを確かめる。

- golem-test-support のライブラリが、`style` が `local` の要素（golem-syntax）に直接依存する計画で、終了コード 1。標準エラーに `golem-syntax` が出る。
- Hackage の要素（`style` が `global`）を通して、`local` の要素に辿り着く計画で、終了コード 1。規則を固定するための入力で、実際にはありえない。
- golem-test-support のライブラリが Hackage の要素（`bytestring`、`hedgehog`）にだけ依存する計画で、終了コード 0。
- golem-test-support のテストスイートの部品が golem-test-support のライブラリに依存する計画（今の `test-only.json` がその形を含む）で、終了コード 0。
- 今の十二の確かめ（`deps` による十一と、引数を渡さない一つ）は、同じ終了コードのままである。

### 置き換えた後の確かめ

- `rg -n '^(hex|genText) ::' modules/golem-pdf/test modules/golem-syntax/test modules/golem-lsp/test` が何も返さない。
- golem-test-support-test、golem-syntax-test、golem-pdf-test、golem-cli-test、golem-lsp-test、golem-driver-test の `--list-tests` の出力が、変更の前と後で同じである。
- 上のテストスイートが通る。golem-syntax-test は `-M64m` のヒープの上限（[golem-syntax.cabal](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-syntax/golem-syntax.cabal#L42-L43)）の下でも通る。
- CI の `build` ジョブの `test-only-deps.sh` が終了コード 0 で終わる。

### 出力が変わらないことの確かめ

ライブラリと実行ファイルは変えないので、出力は変わらない。
[ADR 0086](0086-any-test-suite-may-depend-on-test-support.md) と同じく、`golem-cli:exe:golem` から辿れる部品の集合が変わらないこと、golem-driver の `OutputGoldenSpec` が通ること、`scripts/determinism.sh` の出力の一覧を変更の前と後のコミットで取って `diff` し差がないことを確かめる。

## トレードオフ

- golem-test-support のビルドに `hedgehog` などが加わり、このパッケージに依存するテストスイートは、それらが揃うまで待つ。どれもすでにほかのテストスイートが使っているので、新しくビルドするパッケージは増えない。
- `manifestToml` は、TOML の正しさを確かめない固定の文字列の組み立てである。値に `"` を含めると壊れた TOML になるが、テストの入力を作る目的には足りる。逃がしを入れると、今のリテラルとバイト列が一致しなくなる箇所が出る可能性がある。
- 置き換えられないリテラルが残るので、`urn:uuid:11111111-...` の文字列はリポジトリから消えない。消すことより、テストの入力を一字も変えないことを優先する。
- golem-syntax に依存して `sp` まで共有する案もある。共有できる同じ値は二つのパッケージにしかなく、golem-test-support が golem-syntax の変更で作り直されるようになり、それに依存するテストスイート（[ADR 0086](0086-any-test-suite-may-depend-on-test-support.md) とこの ADR の後で十）も作り直される。得るものに対して費用が大きい。
- 依存の規則を「`base` と `tasty` だけ」のまま、`hex` と `genText` と manifest を写しのままにする案もある。写しは R23 の重複を残す。調査の優先は低だが、規則を変えるだけで消せる。

## 参考文献

- [2026-10-25 のリファクタリングの調査](../audits/2026-10-25-refactoring-survey.md) の R23
- [ADR 0028](0028-shared-test-support-package.md)、[ADR 0086](0086-any-test-suite-may-depend-on-test-support.md)
- hedgehog の `Hedgehog.Gen.sample`：https://hackage.haskell.org/package/hedgehog
