# rc4 の数と diagnostic の五つの ADR と実装の照合（2026-10-28）

この記録は、2026-10-28 の main（88b02acb、PR #455 のマージの直後）の Golem を、採択された五つの ADR と照らし合わせた結果である。
対象は、[docs/adr/0101](../adr/0101-rational-numbers-in-expressions.md)、[docs/adr/0102](../adr/0102-natural-number-type.md)、[docs/adr/0103](../adr/0103-single-place-for-unit-conversions.md)、[docs/adr/0104](../adr/0104-info-severity.md)、[[golem-cli ADR 0009](../golem-cli/adr/0009-explain-several-codes.md)](../golem-cli/adr/0009-explain-several-codes.md) と、それぞれを実装したプルリクエスト（#452、#453 と #454、#450 と #455、#451、#449）である。
コードは変えていない。

ソースコードへのリンクは、すべて調べたコミット 88b02acb に固定した。

## 目的と範囲

五つの ADR の「実装すること」「実装しないこと」「テスト設計」の各項目について、コード、テスト、文書（docs/specifications.md、docs/markup.md、docs/diagnostics.md、docs/roadmap.md、manual/、manual-dev/）が ADR のとおりかを調べた。
実装者がプルリクエストの本文で申告した逸脱は、妥当かどうかと、ほかの ADR の実装と整合するかを判断した。
判断の基準は、プロジェクトの原則である「一つの原因に一つのコード（つねに優先する）」「決定性の対象に diagnostic も含む」「出力を黙って変えない」「golem-\* のパッケージのあいだの build-depends は ADR なしに変えない」である。

所見は次の五つに分類した。

- **未実装**：ADR が実装するとした項目が、コードにない。
- **逸脱**：コードが ADR と違うことをしている。プルリクエストの本文で申告されていたかを併記する。
- **範囲外の変更**：ADR が決めていないことをコードが変えた。
- **テスト欠落**：テスト設計の項目に、対応するテストがない。
- **文書の不一致**：仕様書、マニュアル、diagnostics.md が、コードか ADR と食い違う。

重大度は、高、中、低の三段階である。
高は書き手の見る出力か diagnostic が ADR と違うもの、中はプロジェクトの原則か ADR の明示の規則に反するが影響の範囲が狭いもの、低は字面の違いか補助的なものとした。

## 方法

1. 五つの ADR を全文読み、各プルリクエストの本文と変更したファイルの一覧を `gh pr view` で取った。
2. ADR ごとに、コードとテストと文書を読み、項目ごとに対応する箇所を file:line で特定した。読み取りは ADR ごとに分担し、重要な所見はこの記録の執筆者がコードを読み直して確かめた。
3. 88b02acb を `cabal build golem-cli:exe:golem`（GHC 9.10.3）で組み、`golem explain`、`-v`、`golem check` を試した。wasmtime の C API は手元の別の checkout の `third_party/wasmtime` を `cabal.project.local` で指した。`cabal test all` は実行していない。マージのときに CI が通っていることを前提にし、テストの有無と内容だけを読んで確かめた。
4. PDF のバイト列が変わらないことと、決定性の検査の一覧が変わらないことは、再現していない。プルリクエストの本文の申告と、ゴールデンと見た目の回帰テストの一覧が Git の履歴で変わっていないことで判断した。

試した原稿と結果は、「[ADR 0102](../adr/0102-natural-number-type.md)」と「[ADR 0101](../adr/0101-rational-numbers-in-expressions.md)」の節に書く。

## [ADR 0101](../adr/0101-rational-numbers-in-expressions.md): 式の言語の数を自然数、整数、有理数の三つの型にし、浮動小数点数をなくす

### 適合を確かめたもの

- `Value` は `VNat`、`VInt`、`VRat` を持ち、`VFloat` と `EFloat` はリポジトリに残っていない（[Value.hs#L24-L33](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-eval/src/Golem/Eval/Value.hs#L24-L33)）。`typeName` は自然数、整数、有理数を返す。
- 文法の `Number` は `[0-9]+ ('.' [0-9]+)? ('e' [+\-]? [0-9]+)?` で、小文字の `e` だけを読む（[Golem.hpeg#L456](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-parser/grammar/Golem.hpeg#L456)）。`[= 1E3]` は閉じ括弧の誤り（G01017）になることを実機で確かめた。
- 演算の結果の型の二つの表は、`Golem.Eval.Expr` の実装と一致する。`%` は割る数が自然数なら自然数、`abs` の整数は自然数、`min(1, 1.0)` は `VRat`、`**` は指数の型が自然数なら底の型である。
- 有効数字 17 桁の丸めは `k = max(0, 16 - p)` で、整数部を丸めない（[Number.hs#L58-L84](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-eval/src/Golem/Eval/Number.hs#L58-L84)）。循環小数の判定は、分母から 2 と 5 を取り除いて 1 になるかで行う。`sqrt` は整数の平方根と整数の比較だけで計算する。
- G02086 と G02091 の文言は ADR と一字一句同じである（[Expr.hs#L52](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-eval/src/Golem/Eval/Expr.hs#L52)、[File.hs#L1988](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-eval/src/Golem/Eval/File.hs#L1988)）。G02004 と G02095 は docs/diagnostics.md で廃止になっている。
- CDDL に `rational = #6.30([numerator: int64, denominator: 1..9223372036854775807])`、式の `[12, span, uint64]` と `[13, span, rational]`、`value` の `rational` があり、ABI のバージョンは 8 である。`floatTerm` と `halfExact` は消えている。
- プラグインが書いた浮動小数点数は正確な有理数に変わり、負のゼロは 0、NaN と無限大は `FloatNotFinite` から G06100 になる（[Cbor.hs#L275-L285](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-doc/src/Golem/Doc/Cbor.hs#L275-L285)、[Plugins.hs#L153-L156](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-driver/src/Golem/Driver/Plugins.hs#L153-L156)）。
- テスト設計の項目は、golem-parser の `LowerSpec`、golem-eval の `RationalSpec`、golem-doc の `CborExprSpec`、golem-plugin の `NumbersSpec`（`echo.wat` が受け取ったバイト列を返す）、golem-driver の `PluginsSpec` に、列挙のとおりある。構成子と推論した型のプロパティテストは、申告のとおり [ADR 0102](../adr/0102-natural-number-type.md) の `NaturalSpec` にある。
- golem-eval と golem-plugin の cabal の変更は、テストの `other-modules` の追加だけで、build-depends は変わっていない。
- docs/markup.md の「式文脈」と「数の規則」、仕様書の CBOR と ABI、diagnostics.md の新設と改訂、両マニュアル、`scripts/determinism/exprs.gm`、[golem-eval ADR 0001](../golem-eval/adr/0001-expression-language-and-numerics.md)、[0005](../golem-eval/adr/0005-float-overflow.md)、[0006](../golem-eval/adr/0006-exact-power-limit-before-range.md)、[0007](../golem-eval/adr/0007-power-limit-message.md) のステータスの行は ADR のとおりである。

### 所見

**F-01（逸脱、申告あり、中）：指数の絶対値が 1300 を超えるリテラルを、パーサーが別の値に置き換える。**
ADR は「指数の絶対値が 1300 を超えるリテラルは、`10` の累乗を作る前に G02086 とする」と書く。
実装は、パーサーがそのリテラルを `2^4096` かその逆数に置き換え（[Lower.hs#L380-L381](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-parser/src/Golem/Parser/Lower.hs#L380-L381)）、評価器が上限の検査で G02086 を出す。
式の中では ADR の結果になり、`[= 1e1301]` と `[= 0e1301]` が G02086 になることを実機で確かめた。
しかし、[ADR 0102](../adr/0102-natural-number-type.md) の自然数を求める語も同じ `number` を通る（`numberWord`、[Lower.hs#L358-L366](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-parser/src/Golem/Parser/Lower.hs#L358-L366)）ので、`@blank-line 1e1301` は置き換えた値 `2^4096` が int64 の検査に進み、G02091 になる。
これも実機で確かめた。
同じ原因（指数が 1300 を超える）が、式では G02086、語では G02091 になり、「一つの原因に一つのコード」に反する。
[ADR 0102](../adr/0102-natural-number-type.md) の「数として読めるが自然数でない語は、式で書いた同じ値と同じ誤りにする」にも合わない。
決定性は保たれる（同じ入力からは同じ結果になる）。
直し方の候補は、置き換えではなく AST に上限超過の印を持たせるか、`naturalArg` の語の経路で上限を先に検査することである。

**F-02（逸脱、申告あり、低）：既約でないタグ 30 の組を `Golem.Doc.Validate` ではなく復号器が拒む。**
ADR は「既約でない組を受け取ったら `Golem.Doc.Validate` で拒む」と書く。
実装は復号器で `gcd n' d' /= 1` を `スキーマに合いません: 有理数が既約ではありません` にする（[Cbor.hs#L288-L296](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-doc/src/Golem/Doc/Cbor.hs#L288-L296)）。
`Validate.hs` は、この五つのプルリクエストのどれも変えていない（最後の変更は ac05f0bc）。
`Rational` に復号すると既約になり `Validate` が見られないので、置き場所の変更は妥当である。
プラグインが受けるコードは、ほかのスキーマの不一致と同じ G06009 で、メッセージの末尾で区別する。
[ADR 0102](../adr/0102-natural-number-type.md) の負の値の拒否（F-08）と同じ形であり、二つの ADR の実装は互いに整合している。
仕様書はこの振る舞いを書いている。

**F-03（文書の不一致、申告なし、中）：開発者のマニュアルのプラグインの章が ABI のバージョンを 7 と書く。**
[manual-dev/part1/05-plugins.gm#L145](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/manual-dev/part1/05-plugins.gm#L145) は「今の ABI のバージョンは 7 である」と書く。
コードは 8 で、同じ章の wat の例と仕様書は 8 に直されている。
ADR は「仕様書のプラグインの節の CBOR の説明と ABI のバージョンを改める」「開発者のマニュアルの…プラグインの章の CBOR の数の説明を直す」と書く。
PR #454 は `manual-dev/part1/06-ir.gm` の 7 を 8 に直したが、この行は残った。

**F-04（文書の不一致、申告なし、低）：ロードマップの「課題にしなかった事項」に、指数表記を加えないという行が残る。**
[docs/roadmap.md#L273](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/docs/roadmap.md#L273) は「浮動小数点数の指数表記は…必要が明らかになるまで加えない」と書く。
ADR は指数の書き方を加え、実装済みである。
「式の言語の指数の書き方」の項目は消したが、この行は残った。

**F-05（テスト欠落、低）：遅延した式の G02086 の分岐に直接のテストがない。**
`doc` を参照する式のリテラルを置き換えた後に `overLimit` で G02086 を出す分岐（[File.hs#L1653-L1657](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-eval/src/Golem/Eval/File.hs#L1653-L1657)）は、申告した逸脱の振る舞いだが、`FileSpec` に G02086 のテストはない。
`RationalSpec` の `1e1301` は `evalExpr` を直接呼び、この分岐を通らない。

**F-06（テスト欠落、低）：`1E3` のテストが振る舞いを固定していない。**
[LowerSpec.hs#L197-L199](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-parser/test/LowerSpec.hs#L197-L199) は「診断が出る、または `ERat 1000` でない」のどちらかで通る。
ADR の「`1E3` が数のリテラルとして読めないこと」の最低限は満たすが、どの診断になるか（実機では G01017）は固定されない。

**F-07（テスト欠落、低）：driver の層の G06100 は NaN だけを確かめる。**
ADR のテスト設計は NaN、Infinity、-Infinity をコマンドとフィルタの両方で求める。
golem-plugin の `NumbersSpec` は三つの値を両方で確かめるが、G06100 のコードと完全なメッセージを確かめる [PluginsSpec.hs#L199-L213](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-driver/test/PluginsSpec.hs#L199-L213) は NaN だけである。
値を埋める関数は共通なので、実質は覆われている。

## [ADR 0102](../adr/0102-natural-number-type.md): 負になりえない量を自然数で受け取り、負になりうる値を評価の前に調べる

### 適合を確かめたもの

- `Golem.Eval.Analysis` の `inferExpr` と `analyse` が、リテラル、S0 の名前、`doc` の表、演算の表で型を推論し、`round` と `fixed` の桁数が自然数でなく `doc` を参照しないときに S0 で G02103 か G02104 を出す。解析が diagnostic を出した式は評価しない（[File.hs#L1641-L1643](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-eval/src/Golem/Eval/File.hs#L1641-L1643)）。S1 の検査は同じ関数 `digitsDiagnostic` で同じコード、メッセージ、位置になる。
- `naturalArg` は、語を `numberWord`（先頭の `-` を許す）で、式を解析つきで読み、負は G02103、整数でない数は G02104、数でないものは各箇所のコードにする。`@toc` の `depth`、`@need-lines`、`@blank-line`、`@number`、図版の `page` がこれを通る。
- `@blank-line -1` が G02103 で `@blank-line の引数には 0 以上の整数を書きます（書かれた値は -1）`、`[= round(1.25, 0 - 1)]` が G02103 で `round の桁数には…`、`lines=1.5-2` が G02104 になることを実機で確かめた。
- 設定のファイルでは、toml-parser の `integer out of range for Natural` だけを G02103 にし、ほかは各ファイルのコードのままである（[Manifest.hs#L494-L497](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-project/src/Golem/Project/Manifest.hs#L494-L497)）。メッセージは `TomlMessage` の訳、位置は値である。版面の字数、行数、段数、見出しの `lines`、`edition` と `printing`、`[index]` の `columns`、`countOf` が対象である。
- CDDL の `heading-attrs` と `list-item` の `number`、図版の `page`、`code-line` の `number`、アキの `sp` と `zw` の分子は `uint64` になり、`haNumber`、`itemNumber`、`clNumber`、`figPage` は `Natural` である。符号化は変わらず、0 以上の値のバイト列は同じである。
- G02103 を設定のファイルの段階でも出すことは、ADR が「一つの原因に一つのコード」を優先して決めたものであり、実装はそのとおりである。
- テスト設計の項目は `NaturalSpec`、`NaturalKeySpec`、golem-preflight と golem-doc と golem-driver のテストにある（下の F-10 と F-13 を除く）。
- golem-eval と golem-project の cabal の変更はモジュールの追加だけで、build-depends は変わっていない。
- docs/markup.md の「自然数を求める箇所」、diagnostics.md の G02103 と G02104 と表の各コードの原因、付録 A と E、manual-dev の 06-ir、ロードマップの項目の削除は ADR のとおりである。

### 所見

**F-08（逸脱、申告あり、中）：`@listing` の `lines` の両端は式を受け取らない。**
ADR は「自然数を求める箇所は、どれも語と式の両方を受け取る。今は語しか受け取らないもの（…`lines`）も、式を受け取るようになる」と書き、箇所の一覧に「`@listing` の `lines` の両端」を挙げる。
実装の `rangeText` は式を一つの値の文字列にし、`lines` は `T.splitOn "-"` で二つに分かれなければ G02037 にする（[File.hs#L1415-L1421](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-eval/src/Golem/Eval/File.hs#L1415-L1421)、[File.hs#L1964-L1975](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-eval/src/Golem/Eval/File.hs#L1964-L1975)）。
`lines=[= 2]` が G02037 になることを実機で確かめた。
式で両端を書けるのは `lines=[= "1-2"]` のような文字列の式だけで、これは自然数の式ではない。
語で負の端を書いても、`-` が区切りとして割れるので G02103 にならない。
`lines=-1` と `lines=3--1` が G02037 になることを実機で確かめた。
`numbers` と `highlight` の両端も、別々の式では書けない。
申告された逸脱だが、ADR の「記法の規則を一つにそろえる」という目的に対しては未実装の部分が残り、[docs/markup.md#L1036-L1039](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/docs/markup.md#L1036-L1039)、[docs/diagnostics.md#L1542](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/docs/diagnostics.md#L1542)（「両端が負の数なら G02103」）、[manual/appendices/a-markup.gm#L431](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/manual/appendices/a-markup.gm#L431) は実装で成り立たない形を含む。
範囲の記法（`a-b`、`a,b-c`）と式をどう組み合わせるかは、別の ADR で決めるのがよい。

**F-09（逸脱、申告あり、低）：`Golem.Doc.Validate` に負の値の検査を足していない。**
ADR は「`Golem.Doc.Validate` に、プラグインが返した文書のこれらの欄が 0 以上であることの検査を足す」と書き、テスト設計で「`Validate` も拒むこと」を求める。
欄が `Natural` なので負の値は復号器で止まり（[Cbor.hs#L299-L300](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-doc/src/Golem/Doc/Cbor.hs#L299-L300)）、`Validate` には届かない。
型で表せないものを `Validate` で検査できないので妥当であり、F-02 と同じ形である。
プラグインが受けるコードは G06009 で、仕様書に書いてある。

**F-10（テスト欠落、低）：外部の CDDL の検証器で -1 を拒むテストがない。**
ADR のテスト設計は「CDDL の検証器でスキーマに合わず、`Validate` も拒むこと」と書く。
[golem-doc/test/Main.hs#L112-L130](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-doc/test/Main.hs#L112-L130) の `cddl` CLI のテストは、生成した文書が合うことと ABI のバージョンの違いだけで、-1 の拒否は Haskell の復号器のテスト（[同#L278-L299](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-doc/test/Main.hs#L278-L299)）だけで確かめている。

**F-11（逸脱、申告あり、低）：設定の Haskell の欄は `Int` のままである。**
ADR は「Haskell の欄の型は `Natural` にし、`Int` に変える箇所はその場で上限を確かめる」と書く。
実装は `naturalIntOf` で `Natural` として読み、`Int` の上限を確かめてから `Int` に入れる（[Manifest.hs#L515-L519](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-project/src/Golem/Project/Manifest.hs#L515-L519)）。
diagnostic を決めるのは読み方なので、振る舞いの差はない。

**F-12（逸脱、申告なし、低）：`[index]` の `columns` と `countOf` は、負のときだけ `Natural` で読む。**
[Style.hs#L1819](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-project/src/Golem/Project/Style.hs#L1819) と [Rules.hs#L252-L254](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-preflight/src/Golem/Preflight/Rules.hs#L252-L254) は、`n < 0` の分岐でだけ `naturalOf` を呼び、ほかは従来の経路である。
ADR の「次のキーを、toml-parser の `Natural` で読む」の字面とは違うが、出る diagnostic は同じである。
`Rules.hs` の `負の値は使えません` の分岐は、到達しないまま残る。

**F-13（テスト欠落、低）：S1 の diagnostic の位置を確かめるテストがない。**
ADR は S1 で「同じ位置に出す」と書く。
[DiagnosticsSpec.hs#L444-L454](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-driver/test/DiagnosticsSpec.hs#L444-L454) はコードとメッセージだけを確かめる。
S0 と S1 は同じ `locSpan d` を使うので、実害は低い。

**F-14（文書の不一致、低）：`@number` が負の数を取れるという古い記述が残る。**
[docs/markup.md#L651](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/docs/markup.md#L651) は「`@number` の `N` は -2 の 63 乗以上、2 の 63 乗未満の整数に限る」、[manual/appendices/a-markup.gm#L432](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/manual/appendices/a-markup.gm#L432) は「`[number-text ...]` と `@number` に渡せる整数は、-2 の 63 乗以上」と書く。
`@number` の負の数は G02103 になるので、下限 -2 の 63 乗は当てはまらない。
[manual/chapters/03-markup.gm#L547](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/manual/chapters/03-markup.gm#L547) の「`page` は…1 以上の整数でなければエラー（G02075）」も、負は G02103、小数は G02104 になる今は不正確である。
ADR は「使い手のマニュアルの式の章と、各コマンドの説明の『負の数』の記述を改める」と書くが、PR #453 は章の本文に触れていない。

**F-15（文書の不一致、低）：仕様書に `doc` の名前の型の表がなく、開発者のマニュアルの「評価の章」が存在しない。**
ADR は「仕様書と `docs/markup.md` に、…`doc` の名前の型の表を書く」「開発者のマニュアルの評価の章に、評価の前の解析を書く」と書く。
仕様書は二文を足して docs/markup.md に委ねている。
manual-dev に評価の章はなく、解析の説明は「決定性と純粋性」の章（[12-purity.gm#L380](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/manual-dev/part2/12-purity.gm#L380) 以降）にある。
置き場所の判断は妥当だが、申告されていない。

**F-16（文書の不一致、低）：G02104 のメッセージで、ラテン文字と「には」のあいだに空白がない。**
`@listing の lines` を `<何>` に入れると、`@listing の linesには 0 以上の整数を書きます` になる（実機で確認）。
`<何>` の末尾がラテン文字の箇所に限る。
ADR のメッセージの形 `<何>には…` のとおりではあるが、ほかの diagnostic はラテン文字と日本語のあいだに空白を置く。

## [ADR 0103](../adr/0103-single-place-for-unit-conversions.md): 長さの単位の変換を一か所にまとめ、表示の桁と丸めをそろえる

### 適合を確かめたもの

- `Golem.Syntax.Length` に `newtype Sp = Sp {unSp :: Integer} deriving newtype (Eq, Ord, Show, Num)`、`Unit`、`toSp`、`zwToSp`、`fromSp`、`mmText`、`ptText`、`emText` があり、型は ADR と一致する（[Length.hs#L28-L29](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-syntax/src/Golem/Syntax/Length.hs#L28-L29)）。
- 単位の比（72、25.4、65536）を書く src は、golem-svg と図版の描画の固定小数を除いて `Length.hs` だけである。
- `rg 'type Sp = Integer'` は何も返さず、`rg 'newtype Sp'` は `Length.hs` の一行だけを返す。
- `parseDim`、`mmToSp`、`dimToSp`、`pageTrimSize`、`Golem.Layout.Japanese` のアキ、`spToPt`、`akiLength`、`cssLength`、`cssFontSize`、`ppiOf` は ADR のとおり `Length` の関数を使う。
- `mmText` は 2 桁、偶数への丸め、絶対値を丸めてから符号、丸めた値が 0 なら符号なし、末尾の 0 を残す、空白なし（[Length.hs#L64-L70](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-syntax/src/Golem/Syntax/Length.hs#L64-L70)）。`ptText` と `emText` は `showRationalDigits 4`。
- テスト設計の項目は、golem-syntax の `LengthSpec`（プロパティを含む）、golem-project（G03029 の 2 桁、ちょうど半分の偶数丸め、直し方の値の往復、判型の表の 9 名の sp）、golem-preflight（G09018 の `0.06mm` と `0.10mm`、G09004 と G09013 の事実）、golem-driver（G07041 の形、CSS の `8.5039pt`）にある。`OutputGoldenSpec` とゴールデンは両プルリクエストで変わっていない。
- 意味論 IR の欄の型は変わっていない（[IR.hs#L246](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-doc/src/Golem/Doc/IR.hs#L246)）。golem-text の `floor` と golem-svg も変わっていない。
- golem-syntax の cabal の変更はモジュールの追加だけで、build-depends は変わっていない。
- 仕様書の単位の節（[specifications.md#L1020-L1031](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/docs/specifications.md#L1020-L1031)）、docs/markup.md の「数の規則」の区別、diagnostics.md の八つのコードの例、付録 E、manual-dev のモジュールの表と純粋性の節、[golem-cli ADR 0006](../golem-cli/adr/0006-preflight.md) と docs/adr/0003 のステータスの行、ロードマップの項目の削除は ADR のとおりである。使い手のマニュアルのプリフライトと検査の章に、古い 1 桁の mm の例は残っていない。

### 所見

**F-17（未実装の部分、申告あり、中）：ページ組みの層は sp を `Integer` のまま持つ。**
ADR は「`type Sp = Integer` の六つの宣言を消し」「sp と `Integer` を混ぜる箇所には `Sp` か `unSp` を明示することになり、取り違えがコンパイルの誤りになる」と書く。
六つの宣言は消えたが、golem-layout のページ組みの型は sp を `Integer` で持ち続ける。
`lbOverhang`（[Paginate/Types.hs#L47](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-layout/src/Golem/Layout/Paginate/Types.hs#L47)）、`csMeasure` と `csGap`（[同#L148-L150](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-layout/src/Golem/Layout/Paginate/Types.hs#L148-L150)）、`hbPitch`（[同#L171](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-layout/src/Golem/Layout/Paginate/Types.hs#L171)）、`RuleGrid` と `RuleSide`（[RuleArea.hs#L21](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-layout/src/Golem/Layout/RuleArea.hs#L21)）、`placeSidenotes`（[Sidenotes.hs#L23](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-layout/src/Golem/Layout/Sidenotes.hs#L23)）、golem-driver の `RuleShape.Local`（[RuleShape.hs#L33-L38](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-driver/src/Golem/Driver/RuleShape.hs#L33-L38)）である。
これらは型の別名ではなく明示の `Integer` なので ADR の六か所には入らないが、取り違えを型で防ぐという目的はこの層で達していない。
変換は golem-driver の境界に集まり（`Flow.hs` の `unSp` が 23 か所、`Sp (` が 16 か所）、申告のとおり「後に回した」状態である。
ロードマップか次の ADR に残りの範囲を書くのがよい。

**F-18（逸脱、申告あり、低）：`mmRationalText` を公開し、G03029 の「半分」の値を sp を経ずに書く。**
`Length.hs` は ADR の一覧にない `mmRationalText :: Rational -> Text` を公開し（[Length.hs#L16](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-syntax/src/Golem/Syntax/Length.hs#L16)）、G03029 は `size / 2` をこれで書く（[Style.hs#L853](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-project/src/Golem/Project/Style.hs#L853)）。
`mmText` 自身が `mmRationalText . fromSp Mm` なので丸めの規則は一つであり、表示の食い違いは生じない。
妥当である。

**F-19（逸脱、申告なし、低）：`inchesInMm` が sp を経由して二度丸める。**
[Style.hs#L1255-L1256](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-project/src/Golem/Project/Style.hs#L1255-L1256) の `inchesInMm i = L.fromSp L.Mm (L.toSp L.In i)` は、インチの判型を sp に丸めてから mm に戻し、`pageTrimSize` の `mmToSp` でもう一度丸める。
ADR は「sp に一度だけ…丸める」と書く。
4.25in と 6.875in の sp は正確な整数なので今の値は変わらず、テストが固定している。
単位の比を `Style.hs` に書かないための回避だが、`toSp In` を直接返すほうが規則に沿う。

**F-20（逸脱、申告あり、低）：罫線の空きの `rem` も 3 桁から 4 桁になった。**
ADR の表は「出力のうち変わるのは、HTML と EPUB の CSS の長さ（`cssLength` と `cssFontSize` が書く値）だけ」と書くが、`Golem.Driver.Html` の `rem`（[Html.hs#L93](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-driver/src/Golem/Driver/Html.hs#L93)）も `emText` で 4 桁になった。
`decimal3` を消した以上の自然な結果であり、仕様書は「pt と em（CSS の `rem` を含む）で小数点以下 4 桁」と書いている。

**F-21（文書の不一致、低）：[ADR 0103](../adr/0103-single-place-for-unit-conversions.md) の前提と docstring。**
[ADR 0103](../adr/0103-single-place-for-unit-conversions.md) は「意味論 IR の欄の型（アキの `sp` など）は、[ADR 0102](../adr/0102-natural-number-type.md) の `Natural` のままとし」と書くが、`AkiAbs` は `Integer` のままで、[ADR 0102](../adr/0102-natural-number-type.md) もアキを 0103 に委ねた。
どちらの ADR もアキの量を `Natural` にしていない。
0103 の実装としては「IR を変えない」に適合し、前提の記述だけが現状と合わない。
また [Table.hs#L3](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-layout/src/Golem/Layout/Table.hs#L3) の「Integer sp only」は、型が `Sp` になった後も残る。

**未確認**：PDF のバイト列が変わらないこと、決定性の一覧がマニュアルの CSS 以外で同じこと、二つのマニュアルの CSS の差分が桁だけであることは、申告のままで再現していない。
`Golem.Syntax.Length` のテストをモジュールのない状態で失敗させた手順も、履歴からは判定できない。

## [ADR 0104](../adr/0104-info-severity.md): diagnostic の重大度 info を notice の下に設ける

### 適合を確かめたもの

- `Severity = Error | Warning | Notice | Info`、`infoCodes = ["G07047"]`、`infoDiagnostic`、`dropInfo`、`silenceInfo`、`noticeCodes` の 18 件（G07047 なし）、`sortDiagnostics` の最初のキーの三段、`severityText Info = "info"`（人が読む形式と JSON が同じ関数を使う）。
- `finishWith` と `Golem.Driver.Lint` の順序は、プロファイル、`silence-notices`、`silence-info`、`--verbose` がなければ info を落とす、並べ替えである。`golem preflight` は driver の `defaultOptions`（`optVerbose = False`）で組むので info を落とす。
- `--verbose` と `-v` は build、check、lint だけにある。`golem -v`、`golem preflight -v`、`golem explain -v`、`golem inspect FILE --verbose` が終了コード 2 になり、`golem -v` がバージョンを表示しないことを実機で確かめた。`golem check -v --format json` の `severity` は `error`、`notice` の値を出す。
- `manifestSilencedInfo`、`SilenceList` の二つのキーでの共有、G03024 の四つのメッセージは ADR と一字一句同じである。
- LSP は `Info` を `Hint` に写し、`publishable` が `silence-notices` と `silence-info` を当てる。
- テスト設計の項目は、golem-syntax、golem-project、golem-driver（`everyNoticeProjects` の拡張を含む）、golem-cli、golem-lsp のテストにすべてある。
- 文書は、仕様書の「構文木と診断」「CLI」「LSP」と `[diagnostics]`、diagnostics.md の節の形と「情報」の節と G07047 と G03024、docs/markup.md、docs/glossary.md、README、両マニュアル、[ADR 0046](../adr/0046-blank-line-command.md) と [golem-syntax ADR 0002](../golem-syntax/adr/0002-notice-severity.md) のステータスの行、ロードマップが ADR のとおりである。申告された三つの逸脱（マニュアルの例の書き方）は妥当である。

### 所見

**F-22（逸脱、申告なし、低）：`golem inspect` に `silence-info` を当てていない。**
ADR は「`silence-notices` を当てるすべての箇所（`finishWith`、`Golem.Driver.Lint`、`golem inspect`、LSP）で、同じ時点に当てる」と書く。
[cli/app/Main.hs#L329](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-cli/app/Main.hs#L329) の `finish` は `silenceNotices` だけを当て、[同#L355-L357](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-cli/app/Main.hs#L355-L357) の `dropInfo` が info をすべて落とす。
観測できる差はない。

**F-23（文書の不一致、低）：G03024 のメッセージには、訳の表にないため経路の後置きが付く。**
`silenceList` の文は `TomlMessage.translateSchema` の表にないので、`schemaMessage` が ` (diagnostics.silence-notices[0])` を末尾に付ける（[TomlMessage.hs#L28-L33](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-project/src/Golem/Project/TomlMessage.hs#L28-L33)）。
PR #451 の本文の実機の出力もこの形である。
ADR と [docs/diagnostics.md#L4093](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/docs/diagnostics.md#L4093) は後置きのない文を書き、テストは `T.isInfixOf` で比べる（[project/test/Main.hs#L156](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/modules/golem-project/test/Main.hs#L156)）。
`silence-notices` の従来のメッセージも同じ形なので、この ADR の実装が持ち込んだものではない。

**未確認**：ADR の「自動テストにできないものの確かめ方」（実際のフォントで PDF を組み、`golem build -v` で `info[G07047]` が出ること）は、PR #451 の本文の記録で確かめられており、この監査では再現していない。

## [golem-cli ADR 0009](../golem-cli/adr/0009-explain-several-codes.md): golem explain に複数のコードを渡す

### 適合を確かめたもの

- `Explain [T.Text]`、`many (strArgument (metavar "CODE..."))`、純粋な `checkCode`、`codeArg` の削除、ヘルプの説明の不変。
- 実機で `golem explain G01017 G99999 G0101 nope NOPE` を実行すると、標準出力に G01017 の節が一つ、標準エラー出力に `未知の診断のコードです: G99999…`、`診断のコードは G と 5 桁の数字です: G0101`、`診断のコードは G と 5 桁の数字です: nope` の三行（`NOPE` は重複として一度だけ、最初の綴り）、終了コード 2、使い方の表示なし。
- `golem explain G01017 G01002` の出力は、G01017 だけの出力と先頭の部分でバイト列まで同じで、節のあいだは空行一つである（実機で確認）。
- `--format json` は未知のオプションとして終了コード 2。
- テスト設計の七つのテストは `modules/golem-cli/test/Main.hs` の `severalCodesTests` にすべてある。golden の三つは更新されている。
- 仕様書の CLI の表、manual-dev の 01-cli と 02-diagnostics、[golem-cli ADR 0005](../golem-cli/adr/0005-explain-diagnostic-codes.md) のステータスの行、ロードマップは ADR のとおりである。

### 所見

**F-24（文書の不一致、低）：README の行が、重複、区切り、誤ったコードの報告と終了コードを書かない。**
ADR は「README のコマンドの表の行を同じく改める」と書き、仕様書には順、重複、区切り、誤ったコードの報告、終了コードを書くとする。
[README.md#L87](https://github.com/tett23/golem/blob/88b02acb6bfd65f401a1a867742e6a6e7d417c41/README.md#L87) は「複数のコードを渡すと、渡した順に続けて表示する」だけである。
README の表はもともと簡潔なので、低である。

実装者の「逸脱なし」の申告は妥当である。

## 横断的な所見

**一つの原因に一つのコード**：[ADR 0102](../adr/0102-natural-number-type.md) が設定のファイルの段階でも G02103 を出すことは、原則を優先した ADR の決定であり、実装はそのとおりである。
原則に反する箇所は F-01 の一つで、指数が 1300 を超えるリテラルが、式では G02086、自然数を求める語では G02091 になる。
[ADR 0101](../adr/0101-rational-numbers-in-expressions.md) の申告（パーサーが値を置き換える）と [ADR 0102](../adr/0102-natural-number-type.md) の規則（語と式を同じ誤りにする）が組み合わさって生じたもので、どちらのプルリクエストも単独では気付きにくい。

**復号器で拒むか `Validate` で拒むか**：[ADR 0101](../adr/0101-rational-numbers-in-expressions.md)（既約でない有理数）と [ADR 0102](../adr/0102-natural-number-type.md)（負の自然数）は、どちらも `Validate` で拒むと書いたが、実装はどちらも復号器で拒む（F-02、F-09）。
`Rational` と `Natural` に復号した後では検査できないので、二つの実装は同じ理由で同じ形になっており、互いに整合している。
プラグインが受けるコードはどちらも G06009 で、仕様書に書いてある。
今後の ADR は、型で表せる制約は復号器、表せない制約は `Validate` と書き分けるのがよい。

**決定性と出力**：五つの ADR のどれも、出力を黙って変えていない。
[ADR 0101](../adr/0101-rational-numbers-in-expressions.md) と 0103 の出力の変化（式の表記、CSS の桁、diagnostic の mm の桁）は ADR が予告したものであり、[ADR 0104](../adr/0104-info-severity.md) の `--verbose` と `silence-info` は出力のバイト列を変えないことをテストが確かめている。
PDF のバイト列の不変は申告のままである（未確認）。

**build-depends**：五つの ADR のプルリクエストで変わった cabal ファイル（golem-eval、golem-plugin、golem-syntax、golem-project）は、どれもモジュールの追加だけで、golem-\* のあいだの build-depends は変わっていない。

**申告の質**：申告された逸脱は、F-12（負のときだけ `Natural` で読む）、F-15（評価の章がない）、F-19（`inchesInMm`）、F-22（`inspect` の `silence-info`）を除いて、プルリクエストの本文に書かれていた。
申告のない四つはどれも低である。
一方で、F-03（ABI 7 の記述）と F-14（`@number` の負の数の記述）のような、プルリクエストが触らなかった文書の古い記述は、申告の対象に入っていなかった。

**後に回したもの**：F-08（`lines` の両端の式）と F-17（ページ組みの `Integer`）は、ADR の目的に対して実装が途中で止まっている。
どちらもプルリクエストで申告されているが、ロードマップには載っていない。
ロードマップに載せるか、別の ADR で範囲を決めるのがよい。

## 要約表

| 番号 | 所見 | 分類 | 重大度 | 根拠 |
| --- | --- | --- | --- | --- |
| F-01 | 指数が 1300 を超えるリテラルが、式では G02086、自然数を求める語では G02091 になる | 逸脱（申告あり） | 中 | Lower.hs#L380-L381、実機 |
| F-03 | 開発者のマニュアルが ABI を 7 と書く | 文書の不一致 | 中 | 05-plugins.gm#L145 |
| F-08 | `@listing` の `lines` の両端が式を受け取らず、語の負の端が G02103 にならない | 逸脱（申告あり） | 中 | File.hs#L1415-L1421、実機 |
| F-17 | ページ組みの層が sp を `Integer` のまま持つ | 未実装の部分（申告あり） | 中 | Paginate/Types.hs#L47 ほか |
| F-02 | 既約でないタグ 30 を復号器が拒む | 逸脱（申告あり） | 低 | Cbor.hs#L288-L296 |
| F-04 | ロードマップに指数表記を加えないという行が残る | 文書の不一致 | 低 | roadmap.md#L273 |
| F-05 | 遅延した式の G02086 の分岐にテストがない | テスト欠落 | 低 | File.hs#L1653-L1657 |
| F-06 | `1E3` のテストが振る舞いを固定しない | テスト欠落 | 低 | LowerSpec.hs#L197-L199 |
| F-07 | driver の G06100 のテストが NaN だけ | テスト欠落 | 低 | PluginsSpec.hs#L199-L213 |
| F-09 | 負の自然数を復号器が拒む | 逸脱（申告あり） | 低 | Cbor.hs#L299-L300 |
| F-10 | 外部の CDDL の検証器で -1 を拒むテストがない | テスト欠落 | 低 | golem-doc/test/Main.hs#L112-L130 |
| F-11 | 設定の欄が `Int` のまま | 逸脱（申告あり） | 低 | Manifest.hs#L515-L519 |
| F-12 | `[index]` の `columns` と `countOf` は負のときだけ `Natural` で読む | 逸脱（申告なし） | 低 | Style.hs#L1819、Rules.hs#L252-L254 |
| F-13 | S1 の diagnostic の位置のテストがない | テスト欠落 | 低 | DiagnosticsSpec.hs#L444-L454 |
| F-14 | `@number` と `page` の負の数の古い記述 | 文書の不一致 | 低 | markup.md#L651、a-markup.gm#L432、03-markup.gm#L547 |
| F-15 | 仕様書の `doc` の型の表がなく、評価の章がない | 文書の不一致（申告なし） | 低 | 12-purity.gm#L380 |
| F-16 | G02104 のメッセージの空白 | 文書の不一致 | 低 | 実機 |
| F-18 | `mmRationalText` の公開 | 逸脱（申告あり） | 低 | Length.hs#L16、Style.hs#L853 |
| F-19 | `inchesInMm` の二度の丸め | 逸脱（申告なし） | 低 | Style.hs#L1255-L1256 |
| F-20 | 罫線の `rem` の 4 桁化 | 逸脱（申告あり） | 低 | Driver/Html.hs#L93 |
| F-21 | [ADR 0103](../adr/0103-single-place-for-unit-conversions.md) の IR の前提と Table.hs の docstring | 文書の不一致 | 低 | IR.hs#L246、Table.hs#L3 |
| F-22 | `golem inspect` に `silence-info` を当てない | 逸脱（申告なし） | 低 | cli/app/Main.hs#L329 |
| F-23 | G03024 のメッセージの経路の後置き | 文書の不一致 | 低 | TomlMessage.hs#L28-L33 |
| F-24 | README の `golem explain` の行の粒度 | 文書の不一致 | 低 | README.md#L87 |

高の所見はない。
中の四つのうち、F-01 は原則に反する diagnostic のコードの食い違い、F-03 は文書の誤り、F-08 と F-17 は後に回した実装の範囲である。
