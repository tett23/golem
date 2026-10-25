# ADR 0090: style.toml の値を golem-html の設定に直す処理を golem-driver に残し、モジュールに分ける

ステータス: 採択（未実装）

## 文脈

golem-driver の `Golem.Driver`（1245 行）の末尾に、`style.toml` の値を CSS の文字列に直す関数が並んでいる（[1078 行目から 1213 行目](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-driver/src/Golem/Driver.hs#L1078-L1213)）。
`htmlCharStyles`、`htmlParaStyles`、`htmlRule`、`htmlFeatures`、`rubyAlignCss`、`cssLength`、`cssFontSize`、`decimal3` の八つである。
あいだに golem-text の設定を作る `textIndents` が一つ挟まっている。
八つは互いのほかに `Golem.Driver` の関数を呼ばないので、まとめて取り出せる。
`decimal3` は、調査の R10 を実装した [#403](https://github.com/tett23/golem/pull/403) で、golem-syntax の `Golem.Syntax.Text` の `showRationalDigits 3` を呼ぶ一行の定義になった。
HTML の CSS で小数を三桁に丸める名前として残っている（golem-html は四桁で書く）。
どれも、`writeTargetsChecked` が golem-html に渡す設定 `HtmlConfig` を組むときに使う（[925 行目から 990 行目](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-driver/src/Golem/Driver.hs#L925-L990)）。
その後ろに、HTML のターゲットの目次のページを作る `indexPage` がある（[1215 行目から 1245 行目](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-driver/src/Golem/Driver.hs#L1215-L1245)）。

[2026-10-25 のリファクタリングの調査](../audits/2026-10-25-refactoring-survey.md) の R4 は、これらを「ほかのパッケージの主題に属する処理」とし、golem-html に移すか、golem-driver の中でモジュールに切り出すかを、境界を動かすかどうかで決めるよう求めた。
golem-html は golem-project に依存しない（[golem-html.cabal](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-html/golem-html.cabal#L19-L26)）ので、`Style` を受け取る関数は golem-html に置けない。

コードを読むと、二つのことが分かる。

一つめに、golem-html の入力は、`style.toml` の型ではなく、golem-html が自分で定義した型である。
`HtmlConfig` の欄は `HtmlCharStyle`、`HtmlParaStyle`、`HtmlRule`、`HtmlFeatures` などで、値はすでに CSS の文字列（`"0.846em"`、`"solid"`）に直してある。
golem-html は、`style.toml` の継承（`based-on`）の解決も、zw と pt の換算も、スウォッチの CMYK から RGB への変換も知らない。
これは偶然ではなく、ほかの経路でも同じ形をとっている。
golem-pdf は golem-svg に依存せず、golem-driver が golem-svg の描画を golem-pdf の描画に直す（[仕様書のモジュール構成の節](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/docs/specifications.md#L163)）。
golem-text の設定も、golem-driver の `textLists` と `textIndents` が `Style` から作る（[1067 行目](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-driver/src/Golem/Driver.hs#L1067-L1076)、[1169 行目](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-driver/src/Golem/Driver.hs#L1169-L1182)）。
出力のパッケージは、自分の型で書いた設定を受け取り、golem-driver がそれを組む。

二つめに、`indexPage` は `Style` を使わない。
使うのは `HtmlConfig`、golem-html の `pagePath`、`escapeXml`、golem-doc の `tocWithinDepth`、`inlineText`、`numberSeparator` だけで、どれも golem-html がすでに依存しているパッケージにある。
`escapeXml` は、調査の R6 を実装した [#397](https://github.com/tett23/golem/pull/397) で golem-syntax の `Golem.Syntax.Text` に移り、golem-html の `Golem.Html` が再 export している。
`Golem.Html` はすでに `Golem.Syntax.Text` から `escapeXml` を import しているので、`indexPage` を移しても import を足さずに済む。
調査は `indexPage` を `Style` の変換と一括りにしたが、こちらは依存を変えずに golem-html に置ける。

## 実装すること

### 境界

golem-html は golem-project に依存しないままとする。
`style.toml` の値を golem-html の型に直すのは golem-driver の役目とし、この境界を仕様書に書く。

### golem-driver の新しいモジュール

- golem-driver に `Golem.Driver.Html` を足し、`htmlCharStyles`、`htmlParaStyles`、`htmlRule`、`htmlFeatures`、`rubyAlignCss`、`cssLength`、`cssFontSize`、`decimal3` の八つを、本体を変えずに移す。`decimal3` は `showRationalDigits 3` の定義のまま移し、呼び出し側を `showRationalDigits 3` に書き換えることはしない。
- `Golem.Driver` は `Golem.Driver.Html` を import して `HtmlConfig` を組む。`HtmlConfig` を組む式そのもの（`writeTargetsChecked` の中）は `Evaluated` を使うので、`Golem.Driver` に残す。`Golem.Driver.Html` が `Golem.Driver` を import すると閉路になるからである。
- `Golem.Driver` は、今 export している `cssFontSize` を再 export し続ける。golem-driver の `PageElementsSpec` が `Golem.Driver` から import している（[PageElementsSpec.hs](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-driver/test/PageElementsSpec.hs#L1001-L1004)）。

### golem-html に移す関数

- `indexPage :: HtmlConfig -> FileTable -> Book -> Text` を、本体を変えずに golem-html の `Golem.Html` に移し、export する。
- `Golem.Driver` は golem-html の `indexPage` を呼ぶ。

### build-depends の変更

なし。
golem-driver の `exposed-modules` に `Golem.Driver.Html` を足すだけである。
golem のパッケージのあいだの依存のグラフは変わらないので、閉路も生じない。

```
前と後で同じ：golem-html → golem-doc, golem-syntax
              golem-epub → golem-doc, golem-html, golem-syntax
              golem-driver → golem-html, golem-project, ...（16 のパッケージ）
```

### golem-driver の責務を分けること

golem-driver の責務は、いずれこの ADR より大きく分ける必要が出るだろう。
`Golem.Driver` は、プロジェクトの読み込み、評価、diagnostic の収集、参考文献の読み込み、各ターゲットへの書き出しを一つのモジュールに持っている。
PDF の経路は調査の R1 と R2 で `Golem.Driver.Pdf.Fonts`、`Golem.Driver.Pdf.Flow`、`Golem.Driver.Pdf.Draw` に分かれたが、パッケージとしての golem-driver は、ほとんどのパッケージに依存したままである。

この ADR が行うのは、HTML の設定の変換を `Golem.Driver.Html` に取り出すことだけである。
それより大きく golem-driver を分けること（モジュールの組み替えや、別のパッケージへの切り出し）は、別の ADR で決める。

### 文書

- `docs/specifications.md` のモジュール構成の節で、golem-pdf と golem-svg の関係を述べた文（[163 行目](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/docs/specifications.md#L163)）の後に、「golem-html は golem-project に依存せず、golem-driver が `style.toml` の値を golem-html の設定の型に直す」と一文を足し、この ADR へのリンクを付ける。
- `manual-dev/part2/07-modules.gm` の、golem-html と golem-epub の関係を述べた段落（[84 行目](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/manual-dev/part2/07-modules.gm#L84)）に、同じことを一文で足す。
- モジュール構成の図と `README.md` は変えない。

## 実装しないこと

- golem-html を golem-project に依存させること。
- `textLists` と `textIndents`（golem-text の設定を作る関数）を移すこと。調査が挙げた範囲に入っておらず、同じ形の整理は別に判断する。
- `HtmlConfig` を組む式を関数に切り出すこと。
- golem-driver の責務を、`Golem.Driver.Html` の取り出しより大きく分けること。別の ADR で決める。
- 関数の名前、型、振る舞い、CSS の数の桁数の変更。

## テスト設計

### 先に書くテスト

golem-html の `XhtmlSpec` に、`indexPage` のテストを足す。
golem-html が `indexPage` を export していないので、コンパイルが失敗する。

- 見出しを二つ（1 階層めと 2 階層め、1 階層めに番号つき）持つ二つのファイルの本で、`indexPage` の結果の全体が、期待する文字列と一致する。期待する文字列は、移す前の golem-driver の `indexPage` に同じ入力を渡した結果を、テストに書き写したものである。
- 題と言語に `<` と `&` を含む `HtmlConfig` で、`<title>`、`<h1>`、`lang`、`xml:lang` がそれぞれ実体参照に直っている。
- `@toc` の深さを 1 にした本で、2 階層めの見出しが一覧に出ない（[golem-epub ADR 0002](../golem-epub/adr/0002-nav-and-toc-depth.md) の `tocWithinDepth`）。

### 移した後の確かめ

- golem-html-test と golem-driver-test が通り、`--list-tests` の出力は golem-html-test にテストが増えたことを除いて同じである。
- golem-driver の `BuildSpec`、`ReferencesSpec`、`ChapterNotesSpec` の `index.xhtml` を読むテストが通る。
- golem-driver の `PageElementsSpec` の `cssFontSize` のテストが通る。
- `rg -n '^(htmlCharStyles|htmlParaStyles|htmlRule|htmlFeatures|rubyAlignCss|cssLength|cssFontSize|decimal3|indexPage) ::' modules/golem-driver/src/Golem/Driver.hs` が何も返さない。

### 出力が変わらないことの確かめ

- golem-driver の HTML の golden（`test/golden/html-01.xhtml`、`html-02.xhtml`、`html-front.xhtml`、`html-style.css`、`prod-html-01.xhtml`）を使うテストが通る。
- golem-driver の `OutputGoldenSpec` が通る。`epub-sample.txt` と `epub-figures.txt` は golem-html の出力を包んだ EPUB のダンプである。
- ベースのコミットと変更後のコミットでそれぞれ golem をビルドし、`GOLEM=<その golem> sh scripts/determinism.sh` の出力の一覧を取って `diff` し、差がない。一覧には、`scripts/determinism` と `sample` の HTML（`index.xhtml` と `style.css` を含む）と、二つのマニュアルの出力が入る。

## トレードオフ

- golem-html に移す案（golem-html が golem-project に依存する）は、`Style` から CSS への変換と CSS を書く処理を一つのパッケージに置ける。その代わり、golem-html と golem-epub が golem-project、golem-doc、golem-parser、golem-regex の変更のたびに作り直され、golem-html の入力が `style.toml` の型に縛られる。`style.toml` の欄を足す変更が golem-html の型に直接及び、今の「出力のパッケージは自分の型の設定を受け取る」形が HTML だけ崩れる。
- `Golem.Driver.Html` は golem-driver の中のモジュールなので、`style.toml` の値の変換のテストは、今後も golem-driver のテストに置く。golem-html のテストは、変換の済んだ `HtmlConfig` を入力にとる今の形を保つ。
- `indexPage` を golem-html に移すと、目次のページの文字列を golem-html の単体のテストで確かめられる。今は golem-driver のテストがプロジェクトを組んで `index.xhtml` を読むことでしか確かめていない。
- 変換を切り出しても、`Golem.Driver` の行数は 150 行ほど減るだけである。この ADR の主な意味は行数ではなく、境界を決めて書いておくことにある。今後、同じ形の変換が golem-html に入り込むのを防ぐ。

## 参考文献

- [2026-10-25 のリファクタリングの調査](../audits/2026-10-25-refactoring-survey.md) の R1、R2、R4、R6、R10
- [#397](https://github.com/tett23/golem/pull/397)（R6：`escapeXml` を `Golem.Syntax.Text` に移した）、[#403](https://github.com/tett23/golem/pull/403)（R10 の golem-driver の部分：`decimal3` を `showRationalDigits 3` にした）
- [ADR 0005](0005-character-and-paragraph-styles.md)（`HtmlCharStyle` と `HtmlParaStyle`）
- [golem-pdf ADR 0009](../golem-pdf/adr/0009-svg-figures.md)（golem-driver が golem-svg の描画を golem-pdf の描画に直す形）
