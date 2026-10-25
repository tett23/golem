# ADR 0088: 矩形の型 Rect を golem-pdf に移し、golem-pdf を golem-layout-spec から切り離す

ステータス: 採択（未実装）

## 文脈

golem-pdf のライブラリは golem-layout-spec に依存している（[golem-pdf.cabal](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-pdf/golem-pdf.cabal#L34)）。
golem-pdf が golem-layout-spec から使うのは、矩形の型 `Rect` だけである。
[Writer](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L47)、[Marks](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-pdf/src/Golem/Pdf/Marks.hs#L18)、[X4](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-pdf/src/Golem/Pdf/X4.hs#L21) の三つのモジュールが `Golem.LayoutSpec (Rect (..))` を import し、ほかの名前は import しない。
golem-pdf のテストも同じで、[Main.hs](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-pdf/test/Main.hs#L18)、[ImportSpec](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-pdf/test/ImportSpec.hs#L15)、[ImageSpec](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-pdf/test/ImageSpec.hs#L18)、[DrawingSpec](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-pdf/test/DrawingSpec.hs#L10) が `Rect` だけを import する。

golem-layout-spec は golem-project に依存し（[golem-layout-spec.cabal](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-layout-spec/golem-layout-spec.cabal#L22)）、golem-project は golem-doc、golem-parser、golem-regex に依存する。
PDF の直列化は、四つのフィールドの型のために、原稿のパーサーと `style.toml` の読み込みまで引き込んでいる。
[2026-10-25 のリファクタリングの調査](../audits/2026-10-25-refactoring-survey.md) の R14 が挙げた点である。
golem-pdf を作り直すたびに golem-project より下が揃うのを待つことになり、golem-pdf だけを取り出して使うこともできない。

同じ形の依存がほかに二つある。

- golem-preflight は、golem-layout-spec から `Rect` だけを import する（[Preflight.hs](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-preflight/src/Golem/Preflight.hs#L23)、[View.hs](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-preflight/src/Golem/Preflight/View.hs#L25)、テストの [Main.hs](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-preflight/test/Main.hs#L8)）。golem-preflight はほかに golem-project の `Sp` と `SizeSource` などを使うので、golem-project への依存は残る。
- golem-layout のライブラリは golem-layout-spec を build-depends に持つ（[golem-layout.cabal](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-layout/golem-layout.cabal#L44)）が、`modules/golem-layout` のどのモジュールも `Golem.LayoutSpec` を import しない。使われていない依存である。各パッケージの `ghc-options` に `-Wunused-packages` がないので、警告も出ていない。

`Rect` の定義は四つのフィールドを持つレコードで、`Eq` と `Show` を導出する（[LayoutSpec.hs](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-layout-spec/src/Golem/LayoutSpec.hs#L32-L33)）。
モジュールの説明は、長さの単位が sp で、原点が PDF と同じくページの左下であると書いている（[LayoutSpec.hs の冒頭](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-layout-spec/src/Golem/LayoutSpec.hs#L1-L5)）。
`Rect` は、もともと PDF の座標の矩形である。
golem-pdf の公開する型（ページの MediaBox、TrimBox、BleedBox、描画の `Mark` の罫と図版の位置）も、この矩形で書かれている（[Writer.hs](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L98-L152)）。

置き場の候補は四つある。

1. golem-pdf に置き、golem-layout-spec が golem-pdf に依存して再 export する。
2. golem-syntax に置き、golem-layout-spec と golem-pdf がそこから使う。
3. golem-pdf が自分の矩形を別に持ち、golem-driver が golem-layout-spec の矩形から変換する。
4. 矩形だけを持つ新しいパッケージを作る。

## 実装すること

候補 1 を採る。
`Rect` が PDF の座標の矩形であり、golem-pdf の公開する型の大半がこの矩形で書かれているからである。
golem-layout のライブラリから使われていない golem-layout-spec への依存を消すことも、この ADR に含める（理由は下の build-depends の変更の節）。

### 型の置き場

- golem-pdf に、新しいモジュール `Golem.Pdf.Rect` を置き、`Rect` をここで定義する。定義は今と同じ `data Rect = Rect {rectX, rectY, rectW, rectH}` の四つのフィールドで、`Eq` と `Show` を `deriving stock` で導出する。フィールドの型は `Integer` と書く。今のフィールドの型 `Sp` は golem-project の `type Sp = Integer` であり、同じ型である。
- golem-pdf の Writer、Marks、X4 は `Golem.Pdf.Rect (Rect (..))` を import する。`Golem.Pdf.Writer` の `type Sp = Integer` は今のまま残す（[調査の R13](../audits/2026-10-25-refactoring-survey.md) は別名の統一を今はやらないとした）。
- golem-layout-spec は `Rect` の定義を消し、`Golem.Pdf.Rect (Rect (..))` を import して、export の一覧の `Rect (..)` で再 export する。golem-driver のモジュールとテスト、golem-layout-spec のテストの `import Golem.LayoutSpec (Rect (..))` は変えずに済む。
- golem-preflight は `Golem.LayoutSpec` の import を `Golem.Pdf.Rect` に替える。
- golem-pdf のテストの四つのモジュールは、`Golem.LayoutSpec` の import を `Golem.Pdf.Rect` に替える。

### build-depends の変更

| パッケージ | 部品 | 変更 |
| --- | --- | --- |
| golem-pdf | library | `golem-layout-spec` を消す。`exposed-modules` に `Golem.Pdf.Rect` を足す |
| golem-pdf | golem-pdf-test | `golem-layout-spec` を消す |
| golem-layout-spec | library | `golem-pdf` を足す |
| golem-layout-spec | golem-layout-spec-test | 変えない（`Golem.LayoutSpec` の再 export を使う） |
| golem-preflight | library | `golem-layout-spec` を消す |
| golem-preflight | golem-preflight-test | `golem-layout-spec` を消す |
| golem-layout | library | `golem-layout-spec` を消す（使われていない依存） |
| golem-driver | library とテストスイート | 変えない |

golem-layout の依存を消すのは、消さないと golem-layout が golem-layout-spec を通して golem-pdf に依存するようになり、行分割と改ページのパッケージのビルドが PDF の直列化を待つことになるからである。

### 依存のグラフ

ライブラリの、golem のパッケージへの直接の依存を示す（golem-syntax への依存は省かずに書く）。
変わる行だけを挙げる。

```
前：golem-pdf          → golem-layout-spec, golem-syntax
    golem-layout-spec  → golem-project, golem-syntax
    golem-preflight    → golem-layout-spec, golem-pdf, golem-project, golem-syntax
    golem-layout       → golem-doc, golem-layout-spec, golem-project, golem-syntax
後：golem-pdf          → golem-syntax
    golem-layout-spec  → golem-pdf, golem-project, golem-syntax
    golem-preflight    → golem-pdf, golem-project, golem-syntax
    golem-layout       → golem-doc, golem-project, golem-syntax
```

閉路がないことは、変更後の golem-pdf の推移的な依存が golem-syntax だけであることから分かる。
golem-pdf に依存するのは golem-layout-spec、golem-preflight、golem-driver で、どれも golem-pdf から辿れない。
golem-project から golem-pdf と golem-layout-spec へは、前も後も辿れない。

golem-pdf の推移的な依存は、golem-layout-spec、golem-project、golem-doc、golem-parser、golem-regex、golem-syntax の六つから、golem-syntax の一つになる。

### 文書

- `docs/specifications.md` のモジュール構成の図（[mermaid](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/docs/specifications.md#L168-L224)）の辺を次のように変える。図は「ほかの依存を通して届く依存の矢印」を省くので、届かなくなった依存の矢印を足す。
  - 消す：`pdf --> layoutspec`、`layout --> layoutspec`。
  - 足す：`layoutspec --> pdf`、`layout --> project`、`driver --> layoutspec`、`preflight --> project`。
  - `driver --> layoutspec` は、これまで `driver --> layout --> layoutspec` で届いていた。`preflight --> project` は `preflight --> pdf --> layoutspec --> project` で届いていた。`layout --> project` は `layout --> layoutspec --> project` で届いていた。
- `manual-dev/images/src/modules.svg` の矢印を同じように変え、`scripts/manual/outline-figures.sh` で `manual-dev/images/modules.svg` を作り直す。
- `manual-dev/part2/07-modules.gm` の、golem-svg と golem-pdf の関係を述べた段落の近くに、golem-pdf が golem の型としては golem-syntax だけに依存し、ページの幾何の矩形は golem-pdf の型を golem-layout-spec が使うことを一文で足す。図の代替テキスト（[`@figure` の alt](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/manual-dev/part2/07-modules.gm#L47)）は driver が使うパッケージを列挙しているので、そこに layout-spec を加え、layout-spec が pdf を使うことを足す。
- `README.md` と各モジュールの仕様書（`docs/golem-pdf/specifications.md` など）は、パッケージの依存を書いていないので変えない。

## 実装しないこと

- `type Sp = Integer` の別名を一つにすること（調査の R13）。
- golem-driver の import を `Golem.LayoutSpec` から `Golem.Pdf.Rect` に替えること。再 export があるので要らない。調査の R1 と R2 で分かれた `Golem.Driver.Pdf.Flow` と `Golem.Driver.Pdf.Draw` は `Rect` と一緒に `PageGeometry` などのページの幾何の名前を `Golem.LayoutSpec` から import しており、`Rect` だけを別の import に分けても読みやすくならない。`Rect` だけを import する `Golem.Driver.RuleShape` も、ほかのモジュールと揃えて今のままにする。
- 使われていない依存を見つける `-Wunused-packages` を各パッケージに付けること。
- `Rect` にフィールドや関数を足すこと。

## テスト設計

### 先に書くテスト

- golem-pdf のテストの `Golem.LayoutSpec` の import を `Golem.Pdf.Rect` に替える。`Golem.Pdf.Rect` がないので、コンパイルが失敗する。golem-pdf-test の build-depends から `golem-layout-spec` を消した状態でも、同じく失敗する。
- golem-preflight のテストの import を同じく替え、コンパイルが失敗することを確かめる。

### 実装の後の確かめ

- `cabal build all` が通り、golem-pdf、golem-layout-spec、golem-layout、golem-preflight、golem-driver のテストスイートが通る。各テストスイートの `--list-tests` の出力は、変更の前と後で同じである。
- `rg -n 'Golem.LayoutSpec' modules/golem-pdf modules/golem-preflight modules/golem-layout` が何も返さない。
- 計画（`dist-newstyle/cache/plan.json`）で、golem-pdf のライブラリの部品から `depends` を辿った先に、`style` が `local` の要素が golem-syntax しかない。自動のテストにはせず、jq で一度確かめる（cabal の設定の値を確かめる変更なので）。

### 出力が変わらないことの確かめ

型の定義の場所が変わるだけで、型も値も変わらない。
導出した `Show` は、構築子とフィールドの名前を書き、モジュールの名前を書かないので、文字列も同じである。
それを次で確かめる。

- golem-driver の `OutputGoldenSpec`（`test/golden/` の `pdf-sample.txt`、`pdf-figures.txt`、`epub-sample.txt`、`epub-figures.txt`）が通る。
- golem-driver の `PdfSpec` と `PageElementsSpec` が通る。どちらも PDF のストリームを読んで位置を比べる。
- ベースのコミットと変更後のコミットでそれぞれ golem をビルドし、`GOLEM=<その golem> sh scripts/determinism.sh` の出力の一覧を取って `diff` し、差がない。一覧には PDF の経路の入力（`pdf`）と二つのマニュアルの PDF が入る。

## トレードオフ

- golem-layout-spec が golem-pdf に依存する。ページの幾何を計算するパッケージが、PDF を書くパッケージを待ってビルドされる。golem-layout-spec が使うのは型一つだが、golem-pdf の全体（`zlib`、`uuid` を含む）がビルドの前提になる。golem-layout-spec の利用者は golem-driver だけで、golem-driver は golem-pdf にも依存しているので、golem の実行ファイルのビルドに要るものは変わらない。
- 候補 2（golem-syntax に置く）は、どのパッケージの依存も増やさずに済む。golem-syntax はソースの位置と diagnostic のパッケージであり、PDF の座標の型はその主題から外れる。調査の R6 は、golem-syntax に小道具が集まることに注意を促しており、R6 の実装も共有の関数を `Golem.Syntax` が再 export しない `Golem.Syntax.Text` に分けて置いた。
- 候補 3（golem-pdf が別の矩形を持つ）は、golem-layout-spec と golem-pdf を独立させる。同じ四つのフィールドの型が二つでき、golem-driver の配置と描画（`Golem.Driver.Pdf.Flow` と `Golem.Driver.Pdf.Draw`、合わせて 3300 行ほど）のあちこちで変換が要る。描画の位置を変換し忘れても型が同じ形なので見つけにくい。
- 候補 4（新しいパッケージ）は、型一つのためにパッケージを足し、モジュールの一覧、依存の図、リリースの検査（`scripts/release/check-version.sh` など）の対象を増やす。
- golem-layout の使われていない依存を消すのは、この ADR の主題（`Rect`）とは別の整理である。golem-layout-spec の依存を変えるこの変更と同時でないと、golem-layout が golem-pdf を引き込むので、ここで扱う。

## 参考文献

- [2026-10-25 のリファクタリングの調査](../audits/2026-10-25-refactoring-survey.md) の R1、R2、R6、R13、R14
- [golem-layout-spec ADR 0001](../golem-layout-spec/adr/0001-page-geometry.md)
- [golem-pdf ADR 0004](../golem-pdf/adr/0004-crop-marks-and-bleed.md)
