# ADR 0293: `golem.wasm` のパッケージのテストのスイートを、wasm32 で毎晩走らせる

ステータス: 採択（未実装）

## 文脈

[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md) の `golem.wasm` は、wasm32 の GHC でビルドする。
wasm32 の `Int` は 32 ビットで、ネイティブ（x86-64、aarch64）は 64 ビットである。
[ADR 0247](0247-keep-the-values-of-golem-wasm-independent-of-the-width-of-int.md) は、`Int` の幅で値が変わる箇所を調べて直したが、調べたのは決まった形（`maxBound :: Int`、大きなリテラル、31 以上のずらし、golem-pdf の `Import.hs` と `Image.hs` の `fromInteger`）だけである。
ほかのモジュールの `fromIntegral` と `fromInteger`（約 200 か所）は、一つずつは読んでいない。

今、wasm32 で走る確かめは、`scripts/wasm/compare.sh` が組む決まった入力の PDF と diagnostics を、ネイティブのものと比べることだけである（[`ci.yml#L787-L807`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/.github/workflows/ci.yml#L795-L806)）。
入力が通らない経路の幅の違いは、この比較では見つからない。

テストのスイートは、もっと多くの経路を通る。
同じスイートを wasm32 でビルドして走らせれば、ネイティブで通る断言が wasm32 で落ちたところが、幅に依るコードの候補になる。
`cabal.project.wasm` は `tests: False` で、今はテストを wasm32 でビルドしない（[`cabal.project.wasm`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/cabal.project.wasm)）。

### 走らせるのに要るもの

この ADR を書く時点で、手元（macOS、aarch64）では wasm のツールチェーン（`scripts/fetch-ghc-wasm.sh`、x86-64 の Linux 向けだけ）を動かせず、次の点は確かめていない。

- テストの依存（`tasty`、`tasty-hunit`、`tasty-hedgehog`、`hedgehog`、`tasty-golden`、`temporary`、`process` など。`golem.wasm` のパッケージの 27 のスイートで数えた）が、wasm32 の GHC でビルドできるか。`hedgehog` は依存が多い。
- `-threaded` を付けたスイート（golem-driver の二つなど）を、wasm32 の GHC がどう扱うか。
- 相対のパスで読むファイルの扱い。テストは、パッケージのディレクトリを作業のディレクトリとして、`../golem-font/test/fonts/` などを読む。WASI には作業のディレクトリがなく、wasi-libc は相対のパスを、初めは `/` から解決する。

外の道具を使うテストは、`Golem.TestSupport.ExternalTool` の `needsTool` と `optionalTool` を通す（[`ExternalTool.hs`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/modules/golem-test-support/src/Golem/TestSupport/ExternalTool.hs)）。
`GOLEM_REQUIRE_EXTERNAL_TOOLS` を渡さなければ、道具の見つからないテストは SKIP になり、スイートの終わりに数が出る（[ADR 0074](0074-test-switches-by-environment-variables.md)）。
WASI では外のプロセスを起動できないので、wasm32 ではこれらのテストが SKIP になる見込みである。

## 実装すること

### 1. ビルド

- `cabal.project.wasm-tests` を足す。`cabal.project.wasm` を `import` し、`tests: True` とする。
- テストの依存の版は、`cabal.project.freeze` の版に合わせ、`cabal.project.wasm.freeze` に足す。`scripts/ci/wasm-freeze.sh` の検査を、この project にも当てる。
- wasm32 でビルドできない依存やオプションは、スイートの `.cabal` に `if arch(wasm32)` の条件を足して外す。golem のパッケージのあいだの `build-depends` は、2 のほかに変えない。

### 2. 作業のディレクトリ

`golem-test-support` に、wasm32 でだけ働く `enterPackageDirectory :: IO ()` を足す。
環境の変数 `GOLEM_TEST_PACKAGE_DIR` があれば、そこへ `setCurrentDirectory` する。
ネイティブでは何もしない。
wasm32 で走らせるスイートの `main` の最初で呼ぶ。
今 `golem-test-support` に依らない `golem.wasm` のパッケージのスイートには、`golem-test-support` への `build-depends` を足す（この ADR がその変更を決める。[`test-only-deps.sh`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/scripts/ci/test-only-deps.sh) の、テストのスイートだけが依るという規則は保つ）。

### 3. 走らせ方

`scripts/wasm/run-tests.mjs` を足す。
Node LTS の `node:wasi` で、リポジトリの根を `/` に preopen し、`GOLEM_TEST_PACKAGE_DIR=/modules/<パッケージ>` と `TASTY_NO_CREATE=true` を渡して、スイートの wasm を一つ走らせる。
ほかの環境の変数、標準入力は渡さない。
終了コードは、スイートの終了コードとする。

### 4. 落ちることがわかっているテスト

`scripts/wasm/test-failures.tsv` に、wasm32 で落ちることがわかっているテストを、スイート、tasty のテストの名前、理由、扱いの一行ずつで書く。
扱いは次の二つのどれかとする。

- **product**：製品のコードが `Int` の幅に依る。[ADR 0247](0247-keep-the-values-of-golem-wasm-independent-of-the-width-of-int.md) と同じ形で直す。直す ADR へのリンクを理由に書く。
- **test**：テストの断言が、ホストに依る値（`maxBound :: Int` そのものなど）を期待している。断言を幅に依らない形に直す。

一覧のテストは `-p` の式で除いて走らせ、別に一覧のテストだけを走らせて、落ちることを確かめる。
一覧にないテストが落ちたら、毎晩のジョブは落ちる。
一覧のテストが通ったら、それも落ちる（一覧から外すため）。
最初の実装は、走らせて落ちたテストを一覧にし、扱いを分けたところで止めてよい。
直すのは、それぞれ別のプルリクエストで行う。

### 5. 毎晩のジョブ

`.github/workflows/wasm-tests.yml` を足す。
`schedule`（毎晩）と `workflow_dispatch` で起動し、`ci.yml` の `wasm` のジョブと同じキャッシュの形（ツールチェーン、wasm の cabal の store、`dist-wasm`）で組み、3 でスイートを一つずつ走らせる。
スイートごとの時間をジョブの要約に書く。
ジョブの上限は 120 分とする。
SKIP の数は、スイートの出力をそのまま残し、ジョブの要約にスイートごとの数を書く。

### 6. 文書

- 仕様書の wasm の節に、wasm32 でテストを走らせることと、落ちることがわかっているテストの一覧の意味を書く。
- README の CI のジョブの表に `wasm-tests.yml` の行を足す。
- [docs/roadmap.md](../roadmap.md) の「golem のテストのスイートを wasm32 で走らせる」の項目を外す。一覧が空でないうちは、v1.0.0 の「機能をそろえた後の確かめ」に「wasm32 で落ちることがわかっているテストを 0 にする」を足す。

## 実装しないこと

- プルリクエストの CI で wasm32 のテストを走らせること（「メンテナーが決めること」の 1）。
- `golem.wasm` に入らないパッケージ（golem-cli、golem-lsp、golem-plugin、golem-fmt、golem-fixtures、golem-doc-gen、golem-test-support 自身）のスイート。
- 外の道具を使うテストを wasm32 で走らせること。WASI でプロセスを起動する手段を足さない。
- ブラウザーと wasmtime でテストを走らせること。`golem.wasm` のホストの違いは [ADR 0234](0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md) と [ADR 0238](0238-build-golem-wasm-with-the-standard-exception-handling-and-run-it-under-wasmtime.md) が確かめる。

## 不変条件

wasm32 で走らせるスイートの集合を W、スイート s のテストの集合を T(s)、一覧のテストの集合を F、外の道具を `needsTool` か `optionalTool` で要るテストの集合を X とする。

- **A1 すべてのスイート**：W は、`cabal.project.wasm` の `packages:` にある golem のパッケージのすべてのテストのスイートである。
- **A2 一覧のほかは通る**：s ∈ W の t ∈ T(s) で、t ∉ F かつ t ∉ X なら、wasm32 で t は通る。
- **A3 一覧は今落ちる**：t ∈ F なら、wasm32 で t は落ち、ネイティブで t は通る。
- **A4 SKIP は外の道具だけ**：wasm32 で SKIP になるテストは、X の要素だけである。
- **A5 ネイティブは変わらない**：`enterPackageDirectory` はネイティブで何もせず、ネイティブのスイートの結果は今と同じである。

境界の入力：

| 入力 | 期待 |
| --- | --- |
| 一覧が空 | すべてのテストが通るか SKIP（A2、A4） |
| 一覧のテストが通るようになった | ジョブが落ちる（A3） |
| 一覧にないテストが落ちる | ジョブが落ちる（A2） |
| `GOLEM_TEST_PACKAGE_DIR` がない | 作業のディレクトリを変えない |
| 新しいスイートを `golem.wasm` のパッケージに足す | W に入る（A1） |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
テストの名前には、A1 から A5 の番号を入れる。

- **A1**：`scripts/ci/test.sh` で、`wasm-tests.yml` が走らせるスイートの一覧（`scripts/ci/test-suites.sh` に `wasm` の部分を足して求める）が、`cabal.project.wasm` の `packages:` の golem のパッケージのスイートにちょうど等しいことを確かめる。
- **A2、A3**：`wasm-tests.yml` そのものが確かめる。今は一覧がなく、ジョブもないので落ちる。
- **A4**：`wasm-tests.yml` で、SKIP になったテストの名前を、`needsTool` と `optionalTool` を使うテストの名前と比べる。名前の一覧は、ネイティブで `GOLEM_REQUIRE_EXTERNAL_TOOLS` を渡さず、道具を `PATH` から外して走らせたときの SKIP から作る。
- **A5**：`golem-test-support-test` に、ネイティブで `enterPackageDirectory` が作業のディレクトリを変えないテストを足す。
- **最初の実装の確かめ**：文脈の確かめていない三点を、実装のプルリクエストで `workflow_dispatch` の実行で確かめ、ビルドできなかった依存と、その扱いをプルリクエストの説明に書く。

## トレードオフ

毎晩だけなので、幅に依るコードを入れたプルリクエストは、マージの後に見つかる。
`compare.sh` の比較はプルリクエストで走るので、決まった入力の PDF と diagnostics の違いは、今のとおりマージの前に見つかる。

Node の WASI は、ネイティブより遅い。
スイートの時間はネイティブの数倍になる見込みで、確かめていない。
120 分に収まらなければ、スイートを複数のジョブに分ける。

テストのために `golem-test-support` に依るスイートが増える。
依るのはテストのスイートだけで、ライブラリの依存は変わらない。

## メンテナーが決めること

1. **どこで走らせるか**：推奨は毎晩のジョブ（`wasm-tests.yml`）である。テストのビルドと Node の WASI での実行の時間が測れておらず、プルリクエストの CI の時間に足せるかがわからない。
   - 退けた案の一つは、プルリクエストの `ci.yml` の `wasm` のジョブで走らせることである。幅に依るコードをマージの前に見つけられるが、`wasm` のジョブ（中央値 201 秒）が数倍になれば、CI の臨界経路になる。毎晩の時間を測ってから、プルリクエストに移すかを別の ADR で決める。
   - もう一つは、`browser.yml` に足すことである。`browser.yml` はブラウザーとホストの違いを見るジョブで、役目が違う。
2. **作業のディレクトリの作り方**：推奨は、リポジトリの根を `/` に preopen し、`main` の最初で `GOLEM_TEST_PACKAGE_DIR` へ移ることである。テストの相対のパスを変えずに済む。
   - 退けた案の一つは、テストの相対のパスを、リポジトリの根からのパスに書き換えることである。数百か所のパスを変え、ネイティブの `cabal test` の作業のディレクトリの前提も変わる。
   - もう一つは、パッケージのディレクトリを preopen することである。`../golem-font` のような、パッケージの外へのパスが解決できない。
3. **落ちたテストの扱い**：推奨は、一覧に載せて扱いを分け、直すのは別のプルリクエストにすることである。最初の実行で何件落ちるかがわからず、この ADR の実装に直す作業を含めると、終わりが見えない。
   - 退けた案は、最初の実装で落ちたものをすべて直すことである。

## 決めたことの記録

2026-11-10 に、tett23 が「メンテナーが決めること」のすべてを推奨のとおりに決めた。

1. wasm32 のテストは、毎晩のジョブ（`wasm-tests.yml`）で走らせる。
2. 作業のディレクトリは、リポジトリの根を `/` に preopen し、`main` の最初で `GOLEM_TEST_PACKAGE_DIR` へ移って作る。
3. 落ちたテストは一覧に載せて扱いを分け、直すのは別のプルリクエストで行う。

採択にあたり、ソースコードへのリンクを `main` の `9acc137a`（[ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md) の実装のマージ）に合わせた。

## 参考文献

- [ADR 0074](0074-test-switches-by-environment-variables.md)、[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md)、[ADR 0202](0202-packages-that-do-not-build-for-wasm.md)、[ADR 0219](0219-frequency-of-the-wasm-job-and-its-uncached-runs.md)、[ADR 0223](0223-emet-sizes-before-building-values.md)、[ADR 0247](0247-keep-the-values-of-golem-wasm-independent-of-the-width-of-int.md)
- [`cabal.project.wasm`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/cabal.project.wasm)、[`.github/workflows/ci.yml` の `wasm`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/.github/workflows/ci.yml#L621-L826)、[`modules/golem-test-support/src/Golem/TestSupport/ExternalTool.hs`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/modules/golem-test-support/src/Golem/TestSupport/ExternalTool.hs)
- WASI preview 1 の preopen と、wasi-libc の相対のパスの解決（作業のディレクトリの既定は `/`）
