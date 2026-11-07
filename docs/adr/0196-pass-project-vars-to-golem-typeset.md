# ADR 0196: `[vars]` の文字列を、golem-driver が評価して `PdfInput` で golem-typeset に渡す

ステータス: 採択

## 文脈

[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) は、PDF の組版を golem-driver から新しいパッケージ golem-typeset に分ける。
その根拠の一つは、PDF の組版の九つのモジュールが、評価のパッケージ（golem-eval、golem-emet）を import せず、golem-driver のほかのモジュールからは `Golem.Driver.Version` だけを使うことだった。
[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) は main の `50b9fca8` でこれを確かめ、golem-typeset のライブラリが golem-eval に届かないことを、`plan.json` を読む依存の向きの検査に加えると決めた（[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) の「テスト設計」）。

[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) の実装は二つのプルリクエストに分かれる。
一つめ（「実装すること」の 1）は #611 で main に入った。
二つめ（2 から 4）は #612 であり、#611 の後の main（`9db4930f`）に対しては完成しているが、今の main とはマージできないため、下書きのまま止まっている（#612 の説明、2026-11-07 に読んだ）。

### 止まった理由

[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) の二つめの実装のあいだに、[ADR 0185](0185-project-wide-variables.md)（`manifest.toml` の `[vars]`、#605）が main に入った。
[ADR 0185](0185-project-wide-variables.md) の実装は、柱が `{vars.<name>}` で `[vars]` の値を示すために、golem-driver に `Golem.Driver.ProjectVars` を足した。
このモジュールの `projectVarTexts` は、`[vars]` の値を golem-eval の `projectVarValues` で評価の値に直し、`embedValue` で地の文に埋め込む形の文字列にする（[`ProjectVars.hs`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-driver/src/Golem/Driver/ProjectVars.hs#L15-L16)、[`ProjectVars.hs`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-driver/src/Golem/Driver/ProjectVars.hs#L30-L42)）。

`Golem.Driver.Pdf.Flow` は、このモジュールを import する（[`Flow.hs`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L77)）。
柱の行を求める `runningHeads` が、`PdfInput` の `piProject` から `manifestVars` を取り、その場で `projectVarTexts` を呼ぶ（[`Flow.hs`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L640-L656)）。
`Golem.Driver.Pdf.Flow` がこのまま `Golem.Typeset.Flow` に移ると、golem-typeset は golem-eval に依存することになる。
[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) の依存の表と、それが求める依存の向きの検査の両方に反する。

`projectVarTexts` を golem-project に移すこともできない。
golem-eval は golem-project に依存するので（[`golem-eval.cabal`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-eval/golem-eval.cabal#L32-L37)）、golem-project が `projectVarValues` と `embedValue` を使えば、依存が循環する。

残る道は、golem-driver で評価した文字列を、golem-typeset が外から受け取ることである。
ただし、[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) は、移したモジュールの関数と型を、Golem のバージョンの受け取り方のほかは変えないと決めている（[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) の「実装すること」の 2）。
外から受け取るには、関数か型のどちらかを変えることになる。
#612 は、この二つの決まりのどちらを外すかを選ばずに止まった。
メンテナーは、文字列を golem-driver が評価して golem-typeset に渡すと決めた（「決めたことの記録」）。
この ADR は、その渡し方を決め、[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) の決まりの例外を定める。

### 受け取る口の候補

`PdfInput` には、すでに同じ形の前例がある。
章のファイルごとに柱が示す変数の文字列は、golem-driver が評価の結果から求め、`piRunningVars :: !(Map FileId (Map [Text] Text))` として渡す（[`Fonts.hs`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-driver/src/Golem/Driver/Pdf/Fonts.hs#L184-L206)、[golem-driver ADR 0022](../golem-driver/adr/0022-running-head-formats.md)）。
golem-driver は、`Golem.Driver` の `runningVars` でこれを求め、`writePdfTarget` で `PdfInput` を作るときに渡す（[`Driver.hs`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-driver/src/Golem/Driver.hs#L1165)）。
`[vars]` の文字列も、評価が作り、柱だけが読む値なので、同じ扱いにできる。

一方、関数の引数にするなら、通り道のすべての関数が変わる。
`runningHeads` を呼ぶのは、描く段階の `writeDocumentView`（[`Draw.hs`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-driver/src/Golem/Driver/Pdf/Draw.hs#L159-L173)）と、G07051 を出す `runningHeadNotices`（[`Flow.hs`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L662-L670)）である。
どちらも `renderPdfView` の中で `PdfInput` を受け取って呼ばれる（[`Draw.hs`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-driver/src/Golem/Driver/Pdf/Draw.hs#L44-L78)）。
引数にすると、`renderPdf`、`renderPdfView`、`writeDocumentView`、`runningHeadNotices`、`runningHeads` の五つの型が変わる。

`PdfInput` を作る箇所は、`Golem.Driver` の一か所と、golem-driver のテストの 10 か所である（`Support.hs` の 4 か所、`StylesSpec` の 2 か所、`ChapterNotesSpec`、`PluginsSpec`、`DiagnosticSitesSpec`、`PdfSpec` の各 1 か所、2026-11-07 に `rg` で数えた）。
どれも構成子に欄を位置で並べる。
欄を足せば、この 11 か所に値が一つ増える。
[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) がバージョンを `PdfInput` の欄にしなかったのは、この 10 か所が変わるからだった（[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) の「メンテナーが決めること」の 4）。
バージョンは PDF を書く関数だけが使うので、引数にしても変わる関数が少なかった。
`[vars]` の文字列は、組む段階の奥（`runningHeads`）で使うので、事情が逆になる。

## 実装すること

### `PdfInput` の欄

`PdfInput` の最後に、欄を一つ足す。

```haskell
    {- | the text of every value of [vars] of manifest.toml a running head
    can show, by its path (docs/adr/0185, docs/adr/0196)
    -} piProjectVars :: !(Map [Text] Text)
```

- 型は、今の `projectVarTexts` の結果と同じ `Map [Text] Text` である。キーは `[vars]` の表をたどる道（`{vars.author.short}` なら `["author", "short"]`）であり、値は文字列と数を地の文に埋め込んだ文字列である。
- 欄は `piRunningVars` の後、最後に置く。位置で作る箇所の変更が、末尾に値を一つ足すことだけで済むからである。
- 欄を足すのは、[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) の後の `Golem.Typeset.Fonts`（今の `Golem.Driver.Pdf.Fonts`）である。

### golem-typeset の側

- `runningHeads` は、`projectVars` を `piProjectVars inp` から取る。`projectVarTexts` も `manifestVars` も呼ばない。
- `Golem.Typeset.Flow` は `Golem.Driver.ProjectVars` を import しない。`manifestVars` の import が要らなくなれば、それも除く。
- `runningHeadLines` の型と本体は変えない。柱の行の作り方（`RefProjectVar` の引き方、`?` の扱い）も変えない。

### golem-driver の側

- `Golem.Driver.ProjectVars` は golem-driver に残す。`projectVarTexts` と `projectVarDiagnostics` の型と本体は変えない。
- `writePdfTarget` は、`PdfInput` の最後の値として `projectVarTexts (manifestVars (projectManifest project))` を渡す。今の `runningHeads` が求めていたものと同じ値である。
- `Golem.Driver` は、テストが同じ値を作れるように、`projectVarTexts` を export する。`runningVars` を export しているのと同じ扱いである。`Golem.Driver.ProjectVars` は `other-modules` のまま置く。

### テストの側

- golem-driver のテストの 10 か所は、`PdfInput` の最後の値に `projectVarTexts (manifestVars (projectManifest (evProject e)))` を渡す。今の `runningHeads` が同じプロジェクトから求めていた値なので、どのテストの期待値も変わらない。
- `Map.empty` を渡して済ませることはしない。`[vars]` を持つプロジェクトで柱を組むテストが、気付かないまま `[vars]` のない柱を確かめることになるからである。

### [ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) の決まりの例外

[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) の「実装すること」の 2 にある「関数と型は、次に書くバージョンの受け取り方のほかは変えない」に、次の二つの例外を加える。

- `PdfInput` に `piProjectVars` を足すこと。
- `Golem.Driver` の export の一覧に `projectVarTexts` を足すこと。[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) は「`Golem.Driver` の export の一覧は変えない」とも決めており、その例外でもある。

ほかの関数と型は、[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) のとおり変えない。
[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) の依存の表も変えない。
golem-typeset のライブラリは golem-eval に依存せず、依存の向きの検査（#612 の `scripts/ci/doc-deps.sh` の規則）もそのまま当てる。

### 順と、ステータスの行

この ADR は、[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) の二つめのプルリクエスト（#612）の中で実装する。

- #612 のブランチ（`impl-0192-typeset`）に main をマージし、[ADR 0185](0185-project-wide-variables.md) の変更を取り込む。rebase はしない。
- マージで `Golem.Driver.Pdf.Flow` に入った `projectVarTexts` の呼び出しを、移した後の `Golem.Typeset.Flow` で、この ADR のとおり `piProjectVars` に直す。この変更は、モジュールを移すコミットと別のコミットにする。
- #612 は、[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) のステータスの行を「採択」でなく「採択→`PdfInput` の `piProjectVars` と、`Golem.Driver` が export する `projectVarTexts` は [ADR 0196](0196-pass-project-vars-to-golem-typeset.md)」とし、この ADR のステータスの行を「採択」にする。

[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) の「順と確かめ方」の決まりは、この変更にも当てる。
`scripts/determinism/hashes.txt`、`scripts/visual/pages/` の参照、各パッケージの `test/golden/`、テストの期待値は変わらない。

### 文書

- [docs/specifications.md](../specifications.md) は直さない。柱が `[vars]` を示す振る舞いは変わらず、仕様書は `PdfInput` を書いていない（2026-11-07 に `rg` で確かめた）。
- [docs/diagnostics.md](../diagnostics.md) の G03111 と G03112 の「段階とモジュール」（`Golem.Driver.ProjectVars`）も直さない。二つを出すのは、golem-driver に残る `projectVarDiagnostics` である。

## 実装しないこと

- **golem-typeset を golem-eval に依存させること**：[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) の依存の表と依存の向きの検査に反する。PDF の組版が評価のパッケージをリンクすれば、評価と組版の境目がまた崩れる（「決めたことの記録」）。
- **`projectVarTexts` を golem-project か golem-typeset に移すこと**：golem-project に置けば依存が循環する（「文脈」）。golem-typeset に置けば、golem-typeset が golem-eval に依存する。
- **関数の引数で渡すこと**：「文脈」のとおり、五つの関数の型が変わる。
- **`piRunningVars` にまとめること**：`piRunningVars` は章のファイルごとの表であり、`RefVar` が引く。`[vars]` は本の全体で一つの表であり、`RefProjectVar` が引く（[`Flow.hs`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L570-L586)）。まとめると、すべての章の表に同じ値を写し、二つの参照の引き方を一つの表で書き分けることになり、`runningHeadLines` の型も変わる。
- **評価の値（`Value`）のまま渡すこと**：`Value` は golem-eval の型なので、golem-typeset が golem-eval に依存する。
- **`[vars]` の文字列の作り方を変えること**：数の埋め込み方、表をたどる道、文字列と数のほかの値を落とすことは、[ADR 0185](0185-project-wide-variables.md) のとおりにする。

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。

- `VarsSpec` に、`piProjectVars` が柱の値の出どころであることを確かめるテストを二つ足す。`Support.hs` の `layoutHeads` に、渡す `piProjectVars` を差し替えられる版を足して使う。
  - `[vars]` を持たないプロジェクトで、`piProjectVars` に `["product"]` の文字列を渡すと、`{vars.product}` の柱がその文字列を示すこと。
  - `[vars]` に `product` を持つプロジェクトで、`piProjectVars` に空の表を渡すと、`x{vars.product?}` の柱が `x` になること。`runningHeads` がマニフェストを読み直していないことを確かめる。
  - 欄がないので、二つとも今はコンパイルで失敗する。
- `VarsSpec` の今のテスト（`{vars.product}` の柱、`{vars.missing?}`、G03111、G03112 など）が、期待値を変えずに通ること。
- 依存の向きは、#612 が足す `scripts/ci/doc-deps.sh` の規則で確かめる。golem-typeset のライブラリが golem-eval に届かないことを、CI の `build` ジョブが今の計画で確かめる。[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) の「テスト設計」のとおり、規則のテスト（`typeset-eval.json`）は #612 にある。
- 出力が変わらないことは、CI の `determinism` ジョブが `scripts/determinism/hashes.txt` との一致で確かめる。ただし、リポジトリの `style.toml` のどれも、柱の書式に `{vars.` を書かない（2026-11-07 に `rg` で確かめた）。柱が `[vars]` を示す経路を出力で確かめるのは、`VarsSpec` のテストだけである。

## トレードオフ

[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) は、移したモジュールの関数と型を変えないことで、二つめのプルリクエストを整理だけの差分にしようとした。
この ADR で、型が一つ（`PdfInput`）と export の一覧が一つ（`Golem.Driver`）変わる。
#612 の差分は、名前を変えることと、バージョンの引数のほかに、この変更を含むことになる。
別のコミットに分けることで、レビューで見分けられるようにする。

`PdfInput` を位置で作る 11 か所が、値を一つずつ増やす。
[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) がバージョンで避けた変更であり、今度は避けない。
その代わり、組む段階の奥まで値を引数で運ぶことはせず、通り道の関数の型を変えずに済む。
[golem-driver ADR 0022](../golem-driver/adr/0022-running-head-formats.md) の `piRunningVars` と同じ形なので、柱の値の受け取り方が一つに揃う。

`PdfInput` の中で、`[vars]` の表が二か所にあることになる。
`piProject` のマニフェストの `manifestVars` と、それを評価した `piProjectVars` である。
二つが食い違う `PdfInput` を作れるが、`Golem.Driver` は一か所で前者から後者を作る。
golem-typeset は後者だけを読むので、食い違えば後者が出力に出る。
テストで二つを食い違わせて、出どころを確かめる（「テスト設計」）。

`Golem.Driver` が `projectVarTexts` を export すると、golem-cli と golem-lsp からも見える。
今の二つは使わない。
`runningVars` と同じく、PDF を組むための評価の補助である。

## 決めたことの記録

- **`[vars]` の文字列の渡し方**（2026-11-07、メンテナー）：golem-driver が `[vars]` を文字列に評価し、golem-typeset に渡す。`PdfInput` の欄か引数かは、コードの形に合うほうを選ぶ。このために、[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) の「バージョンのほかは関数と型を変えない」の決まりを、この変更に限って改める。この ADR は欄を選んだ（「文脈」）。
- **退けた案**（2026-11-07、メンテナー）：golem-typeset を golem-eval に依存させることは退けた。
- **草案の確認点**（2026-11-07、メンテナー）：`Golem.Driver` の export に `projectVarTexts` を足すことと、#612 の中で実装することを、草案の推奨のとおりとした。

## 参考文献

- [ADR 0185](0185-project-wide-variables.md)、[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md)
- [golem-driver ADR 0014](../golem-driver/adr/0014-running-heads.md)、[golem-driver ADR 0022](../golem-driver/adr/0022-running-head-formats.md)
- プルリクエスト #605（[ADR 0185](0185-project-wide-variables.md) の実装）、#611 と #612（[ADR 0192](0192-split-pdf-typesetting-from-golem-driver.md) の実装）の説明
