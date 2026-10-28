# ADR 0114: 長さの型と変換を golem-length に移し、golem-font から使われない sp の API を消す

ステータス: 採択（未実装）

## 文脈

メンテナーは、長さをつねに `Sp` で持つと決めた。
[ADR 0103](0103-single-place-for-unit-conversions.md) は `Sp` を golem-syntax の `Golem.Syntax.Length` の `newtype` にし、`type Sp = Integer` の六つの宣言を消した。
2026-10-28 の監査の [F-17](../audits/2026-10-28-rc4-adr-conformance.md) は、ページ組みの層が sp を `Integer` のまま持つことを挙げた。
プルリクエスト #460 がページ組みと罫線の型を `Sp` にし、残りを次のように書いた。
golem-font の `ShapeRequest`、`ShapedGlyph`、`unitsToSp` が sp を `Integer` で持ち、golem-font が golem-syntax に依存しないので、変えるには依存の変更と ADR が要る。
引用は、断りのないかぎり origin/main の 668ed3ac のものである。

### golem-font が sp を `Integer` で持つもの

golem-font の公開する名前のうち、sp を `Integer` で持つものは次の四つである（[`Golem.Font`](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-font/src/Golem/Font.hs#L204-L281)）。

| 名前 | 今の型 | sp の部分 |
| --- | --- | --- |
| `ShapeRequest` の `srSize` | `!Integer` | 文字の大きさ |
| `shapeRequest` | `Integer -> Text -> ShapeRequest` | 第一引数の文字の大きさ |
| `ShapedGlyph` の `sgAdvance`、`sgOffset` | `!Integer`、`!(Integer, Integer)` | 送りと字面の位置 |
| `unitsToSp` | `Int -> Integer -> Int -> Integer` | 第二引数の大きさと結果 |

`shape` は `shapeUnits` の結果を `unitsToSp` で sp にし、`ShapedGlyph` の並びを返す。
ほかの値（`fontUnitsPerEm`、`fontExtents`、`fontEmBoxCentral`、`glyphMetrics`、`glyphVerticalOrigin`、`shapeUnits` の位置）は、どれもフォントの単位の `Int` である。
フォントの単位は em を upem 等分した無次元の数であり、大きさを掛けるまで長さにならない。

### 呼び出しの箇所

`rg` で `srSize`、`shapeRequest`、`ShapedGlyph`、`sgAdvance`、`sgOffset`、`sgGlyphId`、`sgCluster`、`shape `、`unitsToSp` を `modules/` から探し、呼び出しの箇所を確かめた。

| 名前 | 本番のコード | テスト |
| --- | --- | --- |
| `srSize` | 読む箇所なし。`shape` の中だけで読む | なし |
| `shapeRequest` | golem-driver の [`Golem.Driver.Fonts` の 169 行め](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-driver/src/Golem/Driver/Fonts.hs#L169)（大きさに仮の 1000） | golem-font の `Main.hs` と `ConcurrencySpec.hs`（大きさに 1000 か `10 * 65536`） |
| `ShapedGlyph` とその欄 | なし | golem-font の `Main.hs` の一つのテスト（`sgCluster` だけを見る） |
| `shape` | なし | golem-font の `Main.hs` の同じテスト |
| `unitsToSp` | なし（`shape` の中だけ） | golem-font の `Main.hs` の丸めのテスト |

golem-font を import するのは、golem-driver の `Golem.Driver.Fonts` だけである。
ここは `shape` を呼ばず、`shapeUnits` を呼ぶ（[169〜170 行め](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-driver/src/Golem/Driver/Fonts.hs#L169-L170)）。
`shapeUnits` は `srSize` を読まないので、`shapeRequest` に渡す 1000 はどの値でもよい。
フォントの単位は、ここで upem に対する比（em の有理数）になる。
送りは `Shaped` の [`shAdvance :: Rational`](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-driver/src/Golem/Driver/Pdf/Fonts.hs#L124) に入り、組むときに `Golem.Syntax.Length` の [`zwToSp`](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-syntax/src/Golem/Syntax/Length.hs#L49-L50) で sp になる（[Flow.hs の 680 行め](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L679-L680)、[Draw.hs の 263〜264 行め](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-driver/src/Golem/Driver/Pdf/Draw.hs#L263-L264)）。

つまり、四つの名前はどれも、組版の経路では使われていない。
`srSize` だけは呼び出しの箇所があるが、渡した値を誰も読まない。
フォントの単位から sp への変換も、組版が使う `zwToSp` と、テストだけが使う `unitsToSp` の二つが並んでいる。
どちらも正確な有理数から一度だけ、偶数の側へ丸めるので、値は一致する。

[golem-font ADR 0001](../golem-font/adr/0001-shaping-and-metrics.md) は、`shape` が `sgAdvance :: !Sp` を返し、メトリクスも sp に変換して返すと書いた。
実装はメトリクスをフォントの単位で返し、golem-driver が em の比にしている。
開発者のマニュアルの純粋性の章は、`unitsToSp` が字の大きさへ拡大すると三か所で書く（[12-purity.gm の 201 行め](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/manual-dev/part2/12-purity.gm#L201)、[351 行め](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/manual-dev/part2/12-purity.gm#L351)、[368 行め](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/manual-dev/part2/12-purity.gm#L368)）。
組版の経路は `unitsToSp` を通らないので、この記述は今の実装と合わない。

### `Golem.Syntax.Length` が依存するもの

`Golem.Syntax.Length` は、`Data.Ratio`、`Data.Text` と、golem-syntax の `Golem.Syntax.Text` の `showRationalDigits` だけを使う（[Length.hs の 22〜25 行め](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-syntax/src/Golem/Syntax/Length.hs#L22-L25)）。
`showRationalDigits` と、その下の `roundHalfEven` は `Data.Ratio` と `Data.Text` だけで書かれている（[Text.hs の 34〜57 行め](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-syntax/src/Golem/Syntax/Text.hs#L34-L57)）。
`showRationalDigits` を使うのは、`Golem.Syntax.Length` のほかには golem-pdf の [`Golem.Pdf.Number`](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-pdf/src/Golem/Pdf/Number.hs#L15) だけであり、golem-pdf の `Drawing`、`Import`、`Writer` はそこから使う。
golem-syntax のほかのモジュールは、`Golem.Syntax.Length` も `Sp` も使わない。

`Golem.Syntax.Length` を直接 import するのは、次のパッケージである。

- ライブラリ：golem-doc、golem-driver、golem-html、golem-layout、golem-pdf、golem-preflight、golem-project
- テスト：golem-doc、golem-driver、golem-layout、golem-preflight、golem-project、golem-syntax（`LengthSpec`）

golem-layout-spec などは、golem-project の `Golem.Project.Style` が再び公開する `Sp` を使い、`Golem.Syntax.Length` を直接 import しない。

### 再ビルドの費用

golem-font は HarfBuzz と FreeType の C と C++ のソースを持ち、作り直すと時間がかかる。
CI の設定と検査は、ほかのパッケージの設定が変わるだけで golem-font が HarfBuzz をコンパイルし直すことを問題にしてきた（[docs/adr/0037](0037-ci-build-job-speedup.md)、[docs/adr/0097](0097-ci-same-path-before-build-and-env-check-runner.md)）。
golem-font が何かに依存すれば、その依存を変えるたびに golem-font も作り直しの対象になる。

## 実装すること

### 新しいパッケージ

`modules/golem-length/` に golem-length のパッケージを作る。
モジュールは二つにする。

| モジュール | 公開するもの | 元の場所 |
| --- | --- | --- |
| `Golem.Length` | `Sp (..)`、`Unit (..)`、`toSp`、`zwToSp`、`fromSp`、`mmText`、`mmRationalText`、`ptText`、`emText` | `Golem.Syntax.Length` の全部 |
| `Golem.Length.Decimal` | `showRationalDigits` | `Golem.Syntax.Text` の `showRationalDigits` と `roundHalfEven` |

- `Golem.Syntax.Length` は再び公開せずに消す。同じ型と関数に二つの名前を残さないためである。
- `Golem.Syntax.Text` から `showRationalDigits` と `roundHalfEven` を除く。`tshow`、`escapeXml`、`isSpaceTab` は残す。
- `showRationalDigits` は長さではないが、`ptText` と `emText` が使う。golem-length を golem-syntax に依存させないために、一緒に移す。十進の表記の規則は、[ADR 0103](0103-single-place-for-unit-conversions.md) のとおり一か所のままである。`Golem.Length` と同じモジュールに置かないのは、`Golem.Pdf.Number` が長さと関係のない行列の数を書くのに使うからである。
- golem-length のライブラリの `build-depends` は `base` と `text` だけにする。golem のどのパッケージにも依存しない。
- `LengthSpec` を golem-syntax のテストから golem-length のテスト（`golem-length-test`）に移す。依存は `base`、`text`、`hedgehog`、`tasty`、`tasty-hedgehog`、`tasty-hunit` とする。

パッケージの名前を golem-units にしないのは、フォントの単位を持たないからである。
フォントの単位は golem-font の中の無次元の数であり、golem-length には入れない。

### golem-font の変更

使われていない sp の API を、すべて消す。

| 名前 | 変更 |
| --- | --- |
| `ShapeRequest` の `srSize` | 消す |
| `shapeRequest` | `Integer -> Text -> ShapeRequest` を `Text -> ShapeRequest` にする |
| `ShapedGlyph`（`sgGlyphId`、`sgCluster`、`sgAdvance`、`sgOffset`） | 消す |
| `shape` | 消す |
| `unitsToSp` | 消す |

- `Golem.Font` の export の並びから `ShapedGlyph (..)`、`shape`、`unitsToSp` を除く。`Data.Ratio` の import が要らなくなれば消す。
- モジュールの冒頭の説明と `shapeUnits` の説明に、位置と寸法はフォントの単位で返し、大きさを掛けるのは呼ぶ側だと書く。
- `shapeUnits`、`glyphVerticalOrigin`、`glyphMetrics`、`fontExtents`、`fontEmBoxCentral`、`fontUnitsPerEm` の型は変えない。

どれを消すかは、残るものを `Sp` にする前提で一つずつ判断した。

- `srSize` を `Sp` にして残すと、誰も読まない大きさを呼ぶ側に渡させ続けることになる。シェイピングはフォントの単位で行うので、要求に大きさは要らない。
- `shape` と `ShapedGlyph` を `Sp` にして残すと、golem-driver が使う em の比の経路と別に、sp の位置を返す二つめの経路が残る。使う側はない。
- `unitsToSp` を `Sp` にして残すと、`zwToSp` と同じ変換の二つめの入口になる。

四つを消すと、golem-font の公開する値に長さは残らない。
そのため golem-font は golem-length にも依存せず、golem-font の `build-depends` は変わらない。
「長さはつねに `Sp`」は、golem-font が長さを持たないことで満たす。

### golem-driver の変更

- `Golem.Driver.Fonts` の `shapeRequest 1000 r` を `shapeRequest r` にする。
- ほかは `import Golem.Syntax.Length` の書き換えだけである。em の比と `zwToSp` の経路は変えない。

### ほかのパッケージの変更

- `import Golem.Syntax.Length` を `import Golem.Length` に書き換える。修飾つきの import（`qualified as L`）の名前は変えない。
- golem-pdf の `Golem.Pdf.Number` は `showRationalDigits` を `Golem.Length.Decimal` から import し、今のとおり再び公開する。
- 型と関数の中身は変えない。

### build-depends の辺

足す辺は次のとおりである。

| パッケージ | 部品 | 足す依存 |
| --- | --- | --- |
| golem-doc | ライブラリ、`golem-doc-test` | golem-length |
| golem-driver | ライブラリ、`golem-driver-test` | golem-length |
| golem-html | ライブラリ | golem-length |
| golem-layout | ライブラリ、`golem-layout-test` | golem-length |
| golem-pdf | ライブラリ | golem-length |
| golem-preflight | ライブラリ、`golem-preflight-test` | golem-length |
| golem-project | ライブラリ、`golem-project-test` | golem-length |

- golem-syntax には辺を足さない。移した後の golem-syntax は `Sp` を使わないので、依存すれば使わない辺になる。
- golem-font には辺を足さない。上のとおり、長さを持たなくなるからである。golem-font が golem-syntax に依存することは、どの形でも認めない。
- `golem-driver-parallel-test` などほかのテストスイートは、実装のときに `Golem.Length` を import するものにだけ足す。

循環はできない。
golem-length は golem のどのパッケージにも依存しないので、golem-length から出る辺がない。
golem-test-support は golem-length に依存せず、golem-length のライブラリも golem-test-support に依存しないので、`scripts/ci/test-only-deps.sh` の二つの検査はどちらも通る。

### テストの変更

- golem-font の「the ff ligature is one glyph whose cluster covers two letters」は、`shape` の代わりに `shapeUnits` のクラスタの番号を見る。期待する値（グリフが五つ、クラスタが `[0, 1, 3, 4, 5]`）は変えない。
- 「units are converted to sp with a single rounding」は golem-font から消す。同じ性質（一度だけ、偶数の側へ）は golem-length の `LengthSpec` の `zwToSp` のテストが持つ。`unitsToSp 1000 688128 333` の 229147 の例と、半分の偶数への丸めの二つの例を、`zwToSp` の例として `LengthSpec` に移す。
- golem-font のテストと `ConcurrencySpec` の `shapeRequest 1000` を `shapeRequest` にする。
- golem-font のシェイピングのゴールデン（`test/golden/*.txt`）は `shapeUnits` の結果なので変わらない。

### ほかの ADR との関係

[golem-font ADR 0001](../golem-font/adr/0001-shaping-and-metrics.md) の次の部分を、この ADR で置き換える。

- 「シェイピング」の `ShapedGlyph` と、位置を sp に変換すること。golem-font は位置をフォントの単位で返す。
- 「メトリクス」の、sp に変換して返すこと。今の実装のとおり、フォントの単位で返す。メトリクスを sp で返すには文字の大きさを引数に足すことになり、em の比で組む golem-driver の経路と合わない。
- テスト設計の、sp への変換の丸めの項目。golem-length の `zwToSp` のテストが持つ。

[ADR 0103](0103-single-place-for-unit-conversions.md) の「一か所の置き場所」（golem-syntax の `Golem.Syntax.Length`）も置き換える。
変換を一か所にまとめる規則はそのままで、その一か所が golem-length の `Golem.Length` に移る。
採択したら、[golem-font ADR 0001](../golem-font/adr/0001-shaping-and-metrics.md) と [ADR 0103](0103-single-place-for-unit-conversions.md) のステータスの行に、置き換えた部分とこの ADR へのリンクを足す。

### ドキュメント

- docs/specifications.md：「モジュール構成」の節に golem-length を足し、golem-syntax と同じく、使うモジュールが多いので矢印を省くと書く。1028 行め、1033 行め、2873 行めの `Golem.Syntax.Length` を `Golem.Length` にする。
- 開発者のマニュアルの 07-modules.gm：モジュールの表に golem-length を足し、golem-syntax の行から「長さの単位の変換と表記」を除く。58 行めの「golem-font のライブラリは Golem のほかのパッケージに依存しない」は今のまま成り立つ。
- 開発者のマニュアルの `images/src/modules.svg`：golem-length のノードを足し、注記の「golem-syntax への矢印を除いたもの」に golem-length への矢印も加える。
- 開発者のマニュアルの 12-purity.gm：
  - 201 行め：C の側からはフォントの単位の整数を受け取り、golem-font はそのまま返す。字の大きさを掛けて sp にするのは golem-driver であり、`Golem.Length` の規則で一度だけ丸める、と書く。
  - 349 行めと 359 行め：`Golem.Syntax.Length` を golem-length の `Golem.Length` にする。
  - 351 行め：「フォントの送り、カーニング、字面の位置」の行の型を「フォントの単位の整数を、upem に対する比（有理数）にしてから sp に換算」とし、場所を golem-font（フォントの単位）、golem-driver（比）、`Golem.Length` の `zwToSp`（sp）にする。
  - 368 行め：字の大きさへの拡大は、golem-driver が em の比に文字の大きさを掛けて `zwToSp` で行うと書く。

### CI と cabal.project

- `cabal.project` は `packages: modules/*/*.cabal` で読むので、変えない。
- CI のワークフローと `scripts/ci` の検査は、パッケージの一覧をどこにも書かず、`modules/*/` を探す（`incomplete-patterns.sh`、`unsafe-io.sh`）か、cabal の計画を読む（`test-only-deps.sh`）。どれも変えない。
- `cabal.project.freeze` は golem のパッケージを持たないので、変えない。
- `golem-length-test` は `cabal test all` で動く。
- golem-font は golem-length に依存しないので、golem-length を変えても HarfBuzz を作り直さない。

### 出力が変わらないことの確かめ方

モジュールの移動と、組版の経路が通らない API の削除だけなので、出力は変わらないはずである。
プルリクエスト #460 と同じ方法で確かめ、結果をプルリクエストの本文に書く。

- origin/main の golem と、このブランチの golem を作る。
- origin/main の同じソースから、二つの golem で次のものを作って比べる。マニュアルの原稿もこのブランチで変えるので、比べるときは origin/main の原稿を使う。
  - `GOLEM=<golem> scripts/visual/build.sh <出力先>` で作る、見た目の回帰テストの 17 の入力の PDF。バイト列が一致すること。
  - `GOLEM=<golem> scripts/determinism.sh` の一覧。すべての行が一致すること。
  - 二つのマニュアルの `build/`。一致すること。
- `OutputGoldenSpec` のゴールデンを更新せずに通ること。
- golem-font のシェイピングのゴールデン（`test/golden/*.txt`）を更新せずに通ること。
- `cabal test all` が通ること。

このブランチの原稿で組んだときに変わるのは、書き直した開発者のマニュアルのページ（07-modules.gm と 12-purity.gm の章、モジュールの図）だけである。
見た目の回帰テストのページの一覧で、変わったページがそれらに限られることを確かめる。

## 実装しないこと

- golem-font に長さの API を足すこと。sp の位置が要る使い手が出たら、golem-length に依存する形で別の ADR で決める。
- フォントの単位を `newtype` にすること。
- `glyphMetrics` などのメトリクスを sp で返すこと。
- golem-svg の長さの変換を golem-length に移すこと。[ADR 0103](0103-single-place-for-unit-conversions.md) と同じく、SVG の座標は CSS の px の体系であり、別の変換である。
- golem-syntax と golem-font に golem-length への辺を足すこと。
- `Golem.Syntax.Length` を再び公開する互換のモジュールを残すこと。
- 意味論 IR、CDDL、ABI、出力のバイト列の変更。

## テスト設計

先に次のテストを書き、今のコードで失敗することを確かめてから実装する。

- `golem-length-test` を作り、`LengthSpec` を `import Golem.Length` で移す。golem-length がない今は、パッケージがないので失敗する。移したテストの中身は変えない。
- `LengthSpec` に、golem-font から移す三つの例を足す。`zwToSp 688128 (333 % 1000)` が 229147 であり、桁ごとに丸めた値（`round (333 / 1000 × 10.5 × 100) / 100 × 65536` の倍精度の計算）と一致しないこと。`zwToSp 1 (1 % 2)` が 0、`zwToSp 3 (1 % 2)` が 2 であること。
- `LengthSpec` に、`showRationalDigits` を `Golem.Length.Decimal` から使うテストを足す（golem-pdf のテストの例のうち、4 桁、6 桁、10 桁の一つずつ）。
- golem-font の ff の合字のテストを `shapeUnits` と一引数の `shapeRequest` で書く。今のコードでは `shapeRequest` の引数の数が合わず、コンパイルが失敗する。
- `rg 'Golem\.Syntax\.Length|unitsToSp|ShapedGlyph|srSize|sgAdvance|sgOffset' modules/` が何も返さず、`rg 'newtype Sp'` が `modules/golem-length/src/Golem/Length.hs` の一行だけを返すことを、プルリクエストのレビューで確かめる。
- golem-font.cabal のライブラリが golem のどのパッケージにも依存しないことを、プルリクエストのレビューで確かめる。
- 上の「出力が変わらないことの確かめ方」のとおりであること。
- `scripts/manual/build.sh manual-dev` が diagnostic を出さないこと。

## トレードオフ

- パッケージが一つ増え、七つのパッケージの `build-depends` に辺が増える。代わりに、長さの型が構文と diagnostic の型のパッケージから離れ、構文に依存できないパッケージ（golem-font など）も長さを使えるようになる。
- golem-font の要求が `Sp` を持たなくなったので、今の時点で golem-length に依存するのは、もともと golem-syntax から長さを使っていたパッケージだけである。golem-length を作る理由は、golem-font のための依存ではなく、長さの置き場所を構文のパッケージから分けることにある。
- `showRationalDigits` が、長さではないのに golem-length に移る。golem-length を golem-syntax に依存させないための移動であり、モジュールを分けて名前で区別する。
- `Golem.Syntax.Length` を消すので、`import` を書き換えるファイルが三十余りある。再び公開するモジュールを残せば書き換えは要らないが、同じものに二つの名前が残る。
- golem-font の API が [golem-font ADR 0001](../golem-font/adr/0001-shaping-and-metrics.md) の設計から離れる。そちらの ADR は golem-font が sp を返すと書いたが、組版の経路は採択の後にフォントの単位と em の比で作られ、sp の API は使われないまま残った。設計を実装の側に合わせ、その経緯をステータスの行に残す。
- **案 A（golem-font を golem-syntax に依存させ、四つの名前を `Sp` にする）は採らない。** 循環はできず、辺も一本で済む。しかし、フォントのパッケージが構文と diagnostic のパッケージに依存するのは、一目で責務が合わない。メンテナーは、この依存をどの形でも認めないとした。
- **案 C（golem-font から sp の API を消し、依存を変えない）は、golem-font の部分をこの ADR に取り込んだ。** 長さの置き場所を golem-length に移すことは、案 C にはない。最初の草案は案 C だけを推したが、メンテナーは `Sp` を小さなパッケージに移す案 B を選び、そのうえで使われていない API を消すと決めた。

## 決めたことの記録

草案で開いていた点を、次のとおりに決めた。

- **置き場所**：最初の草案は案 C を推した。メンテナーが、golem-font が golem-syntax に依存するのは一目で誤りに見えるとして、`Sp` を小さなパッケージに移す案 B を選んだ。golem-font から golem-syntax への依存は、どの形でも認めない。
- **パッケージとモジュールの名前、再び公開するかどうか、移すもの**：この版で決めた。上の「新しいパッケージ」のとおりである。
- **golem-syntax の辺**：メンテナーの最初の指示は「golem-syntax と golem-font の両方が依存する小さなパッケージ」だった。`Golem.Syntax.Length` を丸ごと移すと golem-syntax は `Sp` を使わなくなるので、golem-syntax には辺を足さない形を提案し、メンテナーが了承した。
- **`showRationalDigits` の移動**：golem-length を golem-syntax に依存させずに `ptText` と `emText` を移すための移動として提案し、メンテナーが了承した。golem-font から golem-syntax に届く経路を作らないためでもある。
- **使われていない API**：メンテナーが、golem-font の使われていない sp の API をこの ADR で消すと決めた。呼び出しの箇所を確かめた結果、四つ（`srSize`、`ShapedGlyph`、`shape`、`unitsToSp`）がどれも組版の経路で使われていないので、すべて消す。その結果、golem-font は長さを持たず、golem-length にも依存しない。

## 参考文献

- [ADR 0103](0103-single-place-for-unit-conversions.md)
- [2026-10-28 の rc4 の ADR の適合の監査](../audits/2026-10-28-rc4-adr-conformance.md) の F-17
- プルリクエスト #460「layout, driver: hold the lengths of pagination and rule shapes as Sp (audit F-17)」
- [golem-font ADR 0001](../golem-font/adr/0001-shaping-and-metrics.md)
- [docs/adr/0037](0037-ci-build-job-speedup.md)、[docs/adr/0097](0097-ci-same-path-before-build-and-env-check-runner.md)
- [ADR 0028](0028-shared-test-support-package.md)、[ADR 0087](0087-test-support-dependencies-and-shared-fixtures.md)
- [ADR 0064](0064-goldens-that-fix-less-than-the-output.md)、[ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md)
