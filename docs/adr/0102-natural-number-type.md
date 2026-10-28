# ADR 0102: 負になりえない量を自然数で受け取り、負になりうる値を評価の前に調べる

ステータス: 採択（未実装）

## 文脈

行数、回数、深さ、桁数、番号は負にならない。
それでも今は、量を受け取る箇所ごとに、負の値と 0 の扱いを決めている。
ADR を書くたびに「負の数を書いたらどうなるか」を決め直し、ADR を読むたびにそれを確かめることになる。
メンテナーは、負になりえない量を自然数の型で受け取り、負の数を型で除くと決めた（[ロードマップ](../roadmap.md) の「自然数の型」）。
ADR を読むたびに、それぞれの量で負の数をどう扱うかを考えずに済むようにするためである。

### 負の数と 0 を拒む今の箇所

評価（golem-eval）では、量を受け取る箇所が、それぞれ自分の読み方と自分のコードを持つ。

| 箇所 | 受け取る形 | 下限 | 誤りのコード |
| --- | --- | --- | --- |
| [`@toc` の `depth`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-eval/src/Golem/Eval/File.hs#L489-L494) | 語 | 1（上限 3） | G02025 |
| [`@need-lines`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-eval/src/Golem/Eval/File.hs#L691-L707) | 語（9 桁まで） | 1 | G02070 |
| [`@blank-line`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-eval/src/Golem/Eval/File.hs#L709-L731) | 語 | 1 | G02092 |
| [`@number`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-eval/src/Golem/Eval/File.hs#L815-L821) | 語 | 0 | G02027 |
| [図版の `page`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-eval/src/Golem/Eval/File.hs#L1024) | 語（9 桁まで） | 1 | G02075 |
| [`@listing` の `lines`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-eval/src/Golem/Eval/File.hs#L1386-L1393) | 語の範囲 | 1 | G02037 |
| [コードブロックの `numbers` と `highlight`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-eval/src/Golem/Eval/File.hs#L1425-L1460) | 語か式 | 0 | G02069 |
| [`round` と `fixed` の桁数](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-eval/src/Golem/Eval/Expr.hs#L225-L228) | 式 | 0（上限 1000） | G02007、G02086 |

ASCII の数字の並びを読む局所の関数が、少なくとも四つある（`count`、`decimalInt`、`natural`、`@blank-line` と図版の `page` の条件式）。
引数の語は、[`argValueRaw`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-eval/src/Golem/Eval/File.hs#L1858-L1863) が ASCII の数字だけの語を整数にし、ほかを文字列にする。
`-1` という語は文字列になるので、語で書いた負の数は「整数でない語」として拒まれる。
負の数が整数として届くのは、式（`[= ...]`）で書いた場合だけである。
表のうち式を受け取るのは、コードブロックの `numbers` と、`round` と `fixed` の桁数である。

`@blank-line` の G02092 は、0、負の数、小数、整数でない語、二つ以上の位置引数、キーワード引数、本体を、一つのコードで拒む（[ADR 0046](0046-blank-line-command.md)）。
このうち負の数と小数と整数でない語は、今のコードでは区別されていない。
どれも「ASCII の数字だけの語ではない」として同じメッセージになる。

設定のファイルでも、同じことが起きている。

- `style.toml` の [`lines`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-project/src/Golem/Project/Style.hs#L1516) と `[index]` の [`columns`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-project/src/Golem/Project/Style.hs#L1813-L1817) は、`Int` で読んでから 1 以上を確かめる。
- `manifest.toml` の刷の [`edition` と `printing`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-project/src/Golem/Project/Manifest.hs#L307-L311) は 1 以上を確かめる。
- `preflight.toml` の [`countOf`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-preflight/src/Golem/Preflight/Rules.hs#L250-L256) は、下限を引数にとり、0 なら `負の値は使えません`、1 なら `1 以上の整数にします` と書き分ける。
- [`Golem.Project.TomlMessage`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-project/src/Golem/Project/TomlMessage.hs#L45) は、toml-parser の `FromValue Natural` が出す `integer out of range for Natural` を `には 0 以上の整数を書きます` で終わる文に訳す。toml-parser 2.0.2.0 の `Toml.Schema.FromValue` はこの文を出す。しかし、今の golem-project に `Natural` で読む欄はなく、この訳は使われていない。

設定のファイルの誤りのコードは、ファイルごとに一つである（`style.toml` は G03006、`manifest.toml` は G03001、`preflight.toml` は G09001）。
どのコードも、TOML として読めない場合、知らないキー、値の型と範囲の誤りを一つにまとめている。
負の数を書いた誤りは、ファイルによって三つのコードに分かれ、しかもそれぞれのコードの中でほかの原因と区別されない。

意味論 IR の検査（[`Golem.Doc.Validate`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-doc/src/Golem/Doc/Validate.hs#L37-L44)）も、`@need-lines` と行アキの行数が 1 以上であることを確かめる。

### 下限の多くは 0 ではなく 1

上の表の下限は、ほとんどが 1 である。
それでも、自然数は 0 を含める。
0 は足し算の単位元であり、後で、隣り合うアキを一つにまとめる計算（アキの吸収）を自然数の上で書くときに要るからである。
1 以上の整数の型を別に設けることはしない。
「1 以上」の検査は、量ごとの範囲の検査として残る。

### 式の値がわかる時期

[ADR 0101](0101-rational-numbers-in-expressions.md) は、数の型を自然数、整数、有理数の三つにし、型を値からではなく式から決めるとした。
型が式から決まるなら、式を評価する前に、その式が負になりうるかどうかの多くがわかる。

Golem の式は、二つの時期に評価される（仕様書の「目次と文書構造の参照」）。

- **S0**：一つのファイルの評価。リテラル、`@set` で定義した名前、`meta` の値がわかる。`@set` の名前は、使う時点でその値が決まっている。
- **S1**：全ファイルを集めた後。`doc` の値（`doc.chapters.count` など）がわかる。`doc` を参照する式は、S0 で S0 の名前を値に置き換え（[`substitute`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-eval/src/Golem/Eval/File.hs#L1568-L1578)）、S1 で評価する（[`evalDeferred`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-driver/src/Golem/Driver.hs#L285-L289)）。

コマンドの引数の式は S0 で評価し、`doc` を参照できない（[`argValue`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-eval/src/Golem/Eval/File.hs#L1866-L1872) の環境は S0 の名前だけを持つ）。
S1 まで値のわからない式は、本文に埋め込む遅延した式だけである。
その中に自然数を求める箇所（`round` と `fixed` の桁数）を書くことはできる。
`[= round(x, doc.chapters.count - 5)]` の桁数は、S1 まで負になるかどうかがわからない。

### 意味論 IR と CBOR

CDDL は、すでに `uint64 = 0..9223372036854775807` を持ち、位置、ファイル、注と傍注の番号、目次の深さに使っている（[CDDL](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-doc/schema/golem-doc.cddl#L5-L12)）。
一方で、評価が 0 以上の値しか入れない次の欄は `int64` のままである。

- 見出しと番号付きリストの項目の `@number`（語だけを受け取るので 0 以上）
- 図版の `page`（1 以上）
- コードブロックの行番号（`numbers` が 0 以上、`lines` が 1 以上）
- アキの `zw` の分子と `sp`。[`[aki]` の量](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-eval/src/Golem/Eval/File.hs#L1751-L1773) は `parseAki` と `parseDim` で読み、どちらも `-` を読まない。

0 以上の整数は、CBOR では今も major type 0（`uint`）で書かれている。
CDDL の型を狭めても、ホストが書くバイト列は変わらない。
変わるのは、プラグインが負の値を書いた文書がスキーマに合わなくなることである。

### この ADR と組になる ADR

[ADR 0101](0101-rational-numbers-in-expressions.md) は、数の三つの型、演算の結果の型、狭める変換を決める。
この ADR は、その上に、自然数を求める箇所の受け取り方と、評価の前の解析を決める。
[ADR 0103](0103-single-place-for-unit-conversions.md) は長さの単位の変換をまとめる。
三つはロードマップで同じ時期に、プラグインの項目より前に扱うとされている。

## 実装すること

### 自然数を求める箇所

**自然数を求める箇所**は、0 以上の整数だけを受け取る引数と関数の引数である。
次のものを自然数を求める箇所にする。
どれも今、負の数を拒んでいる。

- `@toc` の `depth`、`@need-lines`、`@blank-line`、`@number`、図版の `page`、`@listing` の `lines` の両端、コードブロックの `numbers` と `highlight` の両端
- `round` と `fixed` の桁数

次のものは自然数にしない。

- `[number-text ...]` の数。負の数を組むことがある。
- `@page-lines` の `+1` と `-1`。符号付きの量である。
- アキの量。長さであり、[ADR 0103](0103-single-place-for-unit-conversions.md) で扱う。

自然数を求める箇所は、どれも語と式の両方を受け取る。
今は語しか受け取らないもの（`@toc` の `depth`、`@need-lines`、`@blank-line`、`@number`、図版の `page`、`lines`）も、式を受け取るようになる。
記法の規則を「自然数を求める引数には式を書ける」の一つにそろえるためである。

### 評価の前の解析

式を評価する前に、式の型を推論して解析する。
解析は S0 で、すべての式（コマンドの引数の式、本文に埋め込む式、S1 に遅らせる式）に対して行う。

```haskell
data NumType = TNat | TInt | TRat

data StaticType = SNum NumType | SString | SBool | SNil | SArray | SHash | SDoc DocType

-- 式の型を推論する。自然数を求める箇所の誤りは、ここで diagnostic にする
inferExpr :: TypeEnv -> Located Expr -> Either Diagnostic StaticType
```

型の決め方は次のとおりである。

- **リテラル**：[ADR 0101](0101-rational-numbers-in-expressions.md) のとおり、整数のリテラルは自然数、小数と指数のリテラルは有理数である。
- **S0 の名前**：`@set` の名前と `meta` の値は、使う時点で値が決まっているので、その値の構成子を型とする。
- **`doc` の名前**：仕様書に型を書き、解析はその表を引く。今の `doc.chapters.count` は自然数である。
- **演算と関数**：[ADR 0101](0101-rational-numbers-in-expressions.md) の「演算」の表で決める。引き算は、自然数どうしでも整数になる。

自然数を求める箇所に置いた式は、次の三つのどれかで扱う。

1. **型が自然数の式**：値はつねに 0 以上の整数である。検査を置かない。`len(x)`、`abs(a - b)`、`a % 3`、`doc.chapters.count` などである。
2. **型が自然数でなく、`doc` を参照しない式**：値は S0 で決まる。解析の中で S0 の値を使って式を畳み、負なら G02103、整数でなければ G02104 とする。コマンドの引数の式はすべてここに入る。リテラルだけの式（`0 - 1`、`7 / 2`）も、`@set` の名前を使う式（`n - 1`）もここに入る。
3. **型が自然数でなく、`doc` を参照する式**：S1 まで値がわからない。S1 で評価したときに、同じコード（G02103、G02104）と同じメッセージで、同じ位置に出す。

2 と 3 の区別が結果を変えるのは、遅延した式の中である。
`[= round(1 / 3, 0 - 1) + doc.chapters.count]` は S1 に遅らせる式だが、桁数の `0 - 1` は `doc` を参照しないので、S0 の解析で G02103 になる。
今は S1 の評価まで見つからない。
`[= round(1 / 3, doc.chapters.count)]` の桁数は型が自然数なので、負の数の検査は要らない。
`[= round(1 / 3, doc.chapters.count - 5)]` の桁数は型が整数で `doc` を参照するので、S1 で検査する。

評価の前にわかるのは、型が自然数であること（1）と、S0 で値が決まる式の値（2）である。
評価の後まで残るのは、`doc` を参照し、型が自然数でない式（3）だけである。
解析が型を自然数と推論した式の値が負になることはない。
これは [ADR 0101](0101-rational-numbers-in-expressions.md) の「評価した値の構成子は、推論した型と一致する」から従い、同じプロパティテストで確かめる。

解析が 2 で diagnostic を出した式は、評価しない。
同じ誤りを二度出さないためである。
1 以上や上限（`@toc` の 3、`round` の 1000）のような量ごとの範囲の検査は、今のコードのまま、値が決まった後に行う。

### 自然数を受け取る一つの関数

評価で自然数を求める箇所は、すべて一つの関数を通す。

```haskell
-- 引数の値を自然数として受け取る。語は数のリテラルとして読み、式は解析と値で判定する
naturalArg :: Text -> A.ArgValue -> M (Either NaturalError Natural)
```

- 語は、[ADR 0101](0101-rational-numbers-in-expressions.md) の数のリテラルとして読み、先頭の `-` も許す。`3` は自然数の 3 である。`-1`、`1.5` のように、数として読めるが自然数でない語は、式で書いた同じ値と同じ誤りにする。`1e3` は値が整数なので 1000 として受け取る。
- 式は、上の解析を通してから、[ADR 0101](0101-rational-numbers-in-expressions.md) の規則で評価し、狭める変換で自然数にする。
- 負の数は G02103 とする。
- 整数でない数（`1.5`、`7 / 2`）は G02104 とする。
- 数でない値（文字列、真偽値など）と、数として読めない語は、今の各箇所のコードのままとする。
- `int64` の範囲を超える自然数は、IR の欄に入れるときに今と同じく G02091 とする。

### 設定のファイルのキー

`style.toml`、`manifest.toml`、`preflight.toml` で、負の数を拒んでいる次のキーを、toml-parser の `Natural` で読む。

- `style.toml`：`lines`、`[index]` の `columns`、版面の字数、行数、段数（[`Golem.LayoutSpec`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-layout-spec/src/Golem/LayoutSpec.hs#L164) が 1 以上を確かめるもの）
- `manifest.toml`：刷の `edition` と `printing`
- `preflight.toml`：`countOf` で読むキー

負の値は、toml-parser の `integer out of range for Natural` になる。
これを、原稿の負の数と同じ G02103 にし、`TomlMessage` の訳（`<キー> には 0 以上の整数を書きます`）をメッセージとする。
原因が一つなので、ファイルごとのコードに分けない。
`preflight.toml` は golem-preflight が読むが、プロジェクトの設定のファイルを読む段階の誤りとして、プロジェクトの段階のコードを使う。
golem-preflight は今も golem-project に依存しており、依存は変わらない。

TOML の `1.5` は、TOML の型で小数であり、整数のキーに小数を書いた型の誤りとして、今の各ファイルのコードのまま扱う。
TOML は整数と小数を構文で区別するので、文字列を書いた場合と同じ「型が違う」という原因になる。
1 以上の検査も、今のメッセージとコードのまま残す。
Haskell の欄の型は `Natural` にし、`Int` に変える箇所はその場で上限を確かめる。

### 意味論 IR と CBOR

CDDL で、評価が 0 以上の値しか入れない次の欄を `uint64` にする。

- `heading-attrs` と `list-item` の `number`
- 図版の `page`
- `code-line` の `number`
- アキの `sp`
- アキの `zw` の分子。`[int64, 1..9223372036854775807]` を `[uint64, 1..9223372036854775807]` にする。

Haskell の IR の型（`haNumber`、`itemNumber` など）は、`Natural` にする。
`Golem.Doc.Validate` に、プラグインが返した文書のこれらの欄が 0 以上であることの検査を足す。
CDDL と `Validate.hs` が変わるので、プラグインの ABI が変わる。
ABI のバージョンは [ADR 0052](0052-plugin-abi-version-bump-rule.md) の規則による。
[ADR 0101](0101-rational-numbers-in-expressions.md) と同じリリースのあいだに入るので、上がるのは 7 から 8 への一回だけである。

プラグインに渡す `value` は、この ADR では変えない。
自然数は整数でもあり、`int64` として今と同じバイト列で渡る。

### 既存の diagnostic の整理

| コード | 今の原因 | この ADR の後 |
| --- | --- | --- |
| G02092 | `@blank-line` の 0、負の数、小数、整数でない語、引数の数、キーワード引数、本体 | 負の数は G02103、小数は G02104 に移る。0、数として読めない語、引数の数、キーワード引数、本体が残る |
| G02070 | `@need-lines` の引数の誤り | 負の数は G02103、小数は G02104 に移る |
| G02025 | `@toc` の `depth` の誤り | 同上 |
| G02027 | `@number` の誤り | 同上 |
| G02075 | 図版の `page` の誤り | 同上 |
| G02037 | `lines` の範囲の誤り | 同上 |
| G02069 | コードブロックの開始の行の誤り | `numbers` と `highlight` の負の数と小数が移る |
| G02007 | 組み込み関数の引数の誤り | `round` と `fixed` の負の桁数と小数の桁数が移る |
| G03006、G03001、G09001 | 各ファイルの誤り | 自然数のキーの負の数は G02103 に移る |

各コードに残る原因のうち、「0」と「上限を超える」と「数として読めない語」が一つのコードに同居するものは、v1.0.0 の「一つのコードに一つの原因の監査」で扱う。
この ADR が分けるのは、自然数の型が決める原因（負の数、整数でない数）だけである。

### diagnostic

番号は [docs/adr/0061](0061-five-digit-diagnostic-codes.md) に従い、各段階の 100 からとる。
[ADR 0101](0101-rational-numbers-in-expressions.md) が G02101 と G02102 を使う。

| コード | 重大度 | 原因 | メッセージ |
| --- | --- | --- | --- |
| G02103 | error | 自然数を求める箇所（原稿と設定のファイル）に負の数 | 原稿では `<何>には 0 以上の整数を書きます（書かれた値は <値>）`、設定のファイルでは `<キー> には 0 以上の整数を書きます` |
| G02104 | error | 原稿の自然数を求める箇所に整数でない数 | `<何>には 0 以上の整数を書きます（書かれた値 <値> は整数ではありません）` |

`<何>` は箇所の名前（`@blank-line の引数`、`round の桁数` など）、`<値>` は [ADR 0101](0101-rational-numbers-in-expressions.md) の本文の表記で書いた値である。
ただし、循環小数になる値（`7 / 3`）は、丸めた表記ではなく分数（`7/3`）で書く。
メッセージは書かれた値を正確に伝えるためのものであり、丸めた値を書くと、書き手が見る値と誤りの理由が食い違いうるからである。
設定のファイルのメッセージに値を含めないのは、toml-parser の誤りの文が値を持たないからである。
位置がそのキーの値を指すので、書き手は値を位置で確かめられる。

原稿の負の数と設定のファイルの負の数は、どちらも「自然数を求める箇所に負の数」という同じ原因なので、同じ G02103 にする。
コードの上 2 桁は diagnostic を出す段階を表す（[golem-syntax ADR 0001](../golem-syntax/adr/0001-source-spans-and-diagnostics.md)）が、メンテナーは「一つの原因に一つのコード」がつねに優先すると決めた。
そのため、設定のファイルを読む段階でも G02103 を出し、段階を表す上 2 桁の規則には、この例外ができる。
直す場所は、位置とメッセージで分かる。

### モジュールと依存

- golem-eval：`inferExpr`、`naturalArg`、各箇所の読み方、`typeName`、`round` と `fixed`、遅延した式の S0 での解析。
- golem-driver：遅延した式の S1 での検査（`evalDeferred`）。
- golem-doc：CDDL、IR の型、`Cbor`、`Validate`。
- golem-project と golem-preflight：TOML のキーの型と G02103。
- golem-layout-spec、golem-layout、golem-driver、golem-html、golem-epub、golem-text：IR の型が `Natural` になった欄を読む箇所。
- `Numeric.Natural` は base にあるので、外部の依存は増えない。パッケージのあいだの build-depends は変えない。

### ドキュメント

- 仕様書と `docs/markup.md` に、自然数を求める箇所の一覧、語と式の受け取り方、評価の前の解析で何がわかるか、`doc` の名前の型の表を書く。
- `docs/diagnostics.md` に G02103 と G02104 の節を足し（G02103 の節は原稿と設定のファイルの両方を書く）、表の各コードの原因を改める。
- 使い手のマニュアルの式の章と、各コマンドの説明の「負の数」の記述を改める。
- 開発者のマニュアルの評価の章に、評価の前の解析を書く。

## 実装しないこと

- 型の宣言と型の注釈を、式の言語に加えること。
- 自然数どうしの引き算を、負になる位置でエラーにすること（Haskell の `Natural` の引き算のように）。式の途中で負の値を経ること（`a - b + c`）はよくある。
- 型が自然数でない式を、自然数を求める箇所に書いたこと自体をエラーにすること。`n - 1` のような式を書けなくなり、狭める関数を書かせることになる。
- 1 以上の整数の型を、自然数とは別に加えること。
- `[number-text]`、`@page-lines`、`style.toml` の `tracking` のように、負の値に意味がある量。
- コードを一つの原因ずつに分け直す監査。v1.0.0 の「一つのコードに一つの原因の監査」で行う。
- プラグインに渡す `value` の型を変えること。

## テスト設計

先に次のテストを書き、今のコードで失敗することを確かめてから実装する。

### golem-eval の解析

- `inferExpr` が、`len("a")`、`abs(0 - 3)`、`7 % 3`、`doc.chapters.count` を自然数と、`3 - 1` と `doc.chapters.count - 1` を整数と、`6 / 2` を有理数と推論すること。
- `@set n = 3` の後の `n - 1` を整数と推論し、`n` を自然数と推論すること。
- 遅延した式 `[= round(1 / 3, 0 - 1) + doc.chapters.count]` が、ファイルの評価（S0）の結果の diagnostics に G02103 を持つこと。今は S0 で出ない。
- 遅延した式 `[= round(1 / 3, doc.chapters.count - 5)]` が、S0 の diagnostics には何も出さず、章が三つのプロジェクトの S1 で G02103 を出すこと（golem-driver のテスト）。章が五つ以上なら出ないこと。
- 性質：生成した任意の式について、`inferExpr` が自然数と推論した式の評価した値が 0 以上の整数であること。

### golem-eval の引数

- `@blank-line [= 0 - 1]`、`@need-lines [= 0 - 1]`、`@toc depth=[= 0 - 1]`、`@number [= 0 - 1]` が、どれも G02103 になること。今は前の二つが G02092 と G02070、後の二つが G02025 と G02027 である。
- `@blank-line -1` と `@blank-line [= 0 - 1]` が、同じコードと同じメッセージ（G02103）になること。
- `@blank-line 1.5` と `@blank-line [= 3 / 2]` が G02104 になり、メッセージの値が「1.5」であること。`@blank-line [= 7 / 3]` の G02104 のメッセージの値が「7/3」であること。
- `@blank-line 0` と `@blank-line x` が、今と同じく G02092 になること。
- `@blank-line [= 4 / 2]` と `@blank-line 2.0` が行アキの 2 行になること（有理数の型でも、値が自然数なら受け取る）。
- `@set n = 3` の後の `@blank-line [= n - 1]` が行アキの 2 行になること。
- `[= round(1.25, 0 - 1)]` が G02103、`[= round(1.25, 1.5)]` が G02104、`[= round(1.25, 1001)]` が今と同じく G02086 になること。
- コードブロックの `numbers=[= 0 - 1]` が G02103 になること。今は G02069 である。
- `[number-text [= 0 - 5]]` が、今と同じく負の数を組むこと。
- `typeName` が、`VNat 3` に「自然数」、`VInt 3`（`5 - 2` の値）と `VInt (-3)` に「整数」、`VRat 3`（`6 / 2` の値）に「有理数」を返すこと。

### golem-doc

- 見出しの `number`、リストの項目の `number`、図版の `page`、行番号、アキの `sp` と `zw` の分子に -1 を書いた文書が、CDDL の検証器でスキーマに合わず、`Validate` も拒むこと。
- 0 以上の値の文書のバイト列が、変更の前後で同じであること（ゴールデンで確かめる）。

### golem-project と golem-preflight

- `style.toml` の `lines = -1`、`manifest.toml` の刷の `edition = -1`、`preflight.toml` の `countOf` で読むキーの `-1` が、どれも G02103 になり、メッセージが `<キー> には 0 以上の整数を書きます` であり、位置がその値であること。
- `lines = 0` が、今のメッセージ（1 以上）と今のコードのままであること。`lines = 1.5` が、今のコードの型の誤りのままであること。

### 出力

- 決定性の検査とゴールデンの出力が、負の数を書かない原稿では変わらないこと。

## トレードオフ

- 評価の前の解析が一つ増える。式の言語は関数の定義と条件分岐を持たず、名前は `@set`、`meta`、`doc` だけなので、解析は式の木を一度たどるだけで終わる。
- 型が自然数でない式を自然数を求める箇所に書いても、値が 0 以上なら受け取る。型だけで拒めば、負になりえないことを解析が示せない式（`n - 1`）を書けなくなる。値で判定する分、型が自然数でない式の誤りは、値が決まる時期（多くは S0、`doc` を参照する式では S1）にしか見つからない。
- 1 以上を求める量が多いので、自然数の型だけでは「この量に 0 を書いたらどうなるか」を量ごとに決める手間が残る。負の数の扱いは一つに決まるので、ADR に書くことは一つ減る。0 を含めることは、アキの吸収のような計算で単位元を使えることと引き換えである。
- 語しか受け取らなかった引数が式を受け取るようになる。書き手にできることが増え、記法の規則は「自然数を求める引数には式を書ける」の一つにそろう。
- 設定のファイルの負の数も、原稿の負の数と同じ G02103 になる。コードの上 2 桁が段階を表す規則に例外ができるが、「一つの原因に一つのコード」を優先した。
- IR の型を `Natural` にすると、レイアウトの計算で `Int` や `Integer` と混ぜる箇所に変換が要る。変換は IR を読む箇所に限られ、プラグインとのバイト列は変わらない。

## 決めたことの記録

草案で開いていた点を、次のとおりに決めた。

- **自然数の表し方**：メンテナーが、[ADR 0101](0101-rational-numbers-in-expressions.md) で自然数、整数、有理数を別々の型にすると決めた。自然数どうしの引き算は整数とし、負になった位置ではエラーにしない。
- **0 を含めるか**：メンテナーが、0 を含めると決めた。1 以上の型は設けず、量ごとの下限は範囲の検査として残す。
- **評価の前の解析**：メンテナーが、負になりうる自然数を評価の前にできるだけ見つけると決めた。解析で決められること（型が自然数であること、S0 で値が決まる式の値）と、S1 の検査に残すこと（`doc` を参照し、型が自然数でない式）の分け方は、この版で決めた。
- **語だけの引数に式を許すか**：メンテナーが、許すと決めた。
- **IR の欄**：メンテナーが、`uint64` にすると決めた。
- **設定のファイルのキー**：メンテナーが、自然数で読むと決めた（草案の案）。一つの原因に一つのコードがつねに優先するというメンテナーの決定で、三つのファイルの負の数を、原稿と同じ G02103 にまとめた。TOML の小数は型の誤りとして今のコードに残した。
- **G02103 と G02104**：メンテナーが、草案のとおり自然数を求める箇所で共通のコードにすると決めた。
- **メッセージの値の書き方**：メンテナーが、循環小数を `7/3` の分数で書くと決めた（草案の案）。

## 参考文献

- [ADR 0046](0046-blank-line-command.md)、[ADR 0052](0052-plugin-abi-version-bump-rule.md)、[ADR 0061](0061-five-digit-diagnostic-codes.md)
- [golem-doc ADR 0006](../golem-doc/adr/0006-integer-range-in-ir.md)、[golem-syntax ADR 0001](../golem-syntax/adr/0001-source-spans-and-diagnostics.md)
- toml-parser 2.0.2.0、`Toml.Schema.FromValue` の `instance FromValue Natural`。https://hackage.haskell.org/package/toml-parser-2.0.2.0
- GHC base、`Numeric.Natural`。https://hackage.haskell.org/package/base/docs/Numeric-Natural.html
