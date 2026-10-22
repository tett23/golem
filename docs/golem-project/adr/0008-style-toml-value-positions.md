# ADR 0008: style.toml の値の誤りの位置

ステータス: 採択

## 文脈

`style.toml` の `[paragraph-styles.code]` に `padding = "0"` と単位のない寸法を書くと、`golem check` は次のように答える（main の a2b6106e）。

```
style.toml:1:1: error[G03006]: 長さの書き方が不正です: 0（0.5zw や 1mm のように書きます） (paragraph-styles.code)
  | [page]
```

位置は `padding` の値ではなく、ファイルの先頭である。
経路も、キーの `padding` を含まず、表の `paragraph-styles.code` で止まっている。
同じ症状は、`[page.grid]` の `line-pitch = "20"`、`position` の `gutter = "14"`、段落スタイルの `indent = "1"`、文字スタイルの `padding = "0"` でも出る。
一方、`padding = 3` のような型の誤りは `style.toml:25:11` と値の位置に出る。

### 仕様の定め

[golem-project ADR 0006](0006-project-diagnostic-codes.md) は、G03006 の位置を次のように定めている。

- スキーマに合わない誤り（未知のキー、値の型の違い、列挙にない値、廃止した欄、Golem が値の読み込みで調べる範囲）は、誤った値の位置。
- 読み込んだ後の検査に通らない誤りは、`style.toml` の先頭。

単位のない寸法は「Golem が値の読み込みで調べる範囲」に当たるので、値の位置に出るはずである。
したがって、上の振る舞いは、仕様の定めた振る舞いとの食い違いである。

### 原因

toml-parser の `Matcher` には、失敗の作り方が二つある。

- `failAt l msg`：注釈 `l`（値の位置）を持つ誤りを作る。toml-parser の `typeError` もこれを使う。
- `fail msg`（`MonadFail` のメソッド）：注釈を持たない誤りを作る。

`Golem.Project.Manifest.tomlDiagnosticsBy` は、注釈のない誤りをファイルの先頭の位置にする。
これは [golem-project ADR 0007](0007-toml-messages-in-japanese.md) が「位置が取れないとき」として定めたとおりの扱いである。

位置が失われるのは、Golem の `FromValue` の実装が `fail` で誤りを作っているからである。
[golem-project ADR 0006](0006-project-diagnostic-codes.md) は、英語の `typeError "dimension such as 13Q or 20mm"` を日本語の文言にするとき、`fail` で出すと書いた。
`typeError` は値の位置を持っていたが、`fail` に替えたことで位置が落ちた。
[ADR 0006](0006-project-diagnostic-codes.md) の表の位置の定めと、同じ ADR の「`fail` で出す」という書き方が食い違っており、実装は後者に従った。

`Golem.Project.Style` には `fail` が 34 か所ある（`failAt` は 30 か所）。
このうち `DimV` の `fromValue`（寸法）のようにキーの中で失敗するものは、経路は正しいが位置がない。
段落スタイルと文字スタイルの `padding` と `first-line-indent` は、`optKey` で文字列として読んだ後、表の中で `parseSignedDim` にかけて `fail` する。
こちらは位置がないうえに、経路がキーまで届かない。
`Golem.Project.Manifest` の章の項目（`章は、ファイルのパス、表、配列のどれかで書きます`）も同じ形である。

### 読み込んだ後の検査

読み込んだ後の検査（`Golem.Project.Style` の `styleChecks`）の誤りは、[ADR 0006](0006-project-diagnostic-codes.md) の定めのとおり、どれもファイルの先頭に出る。
次の三つで確かめた。

| 書いた値 | 出力 |
| --- | --- |
| `[paragraph-styles.code]` の `padding = "-1mm"` | `style.toml:1:1: error[G03006]: padding は 0 以上の寸法です` |
| `[paragraph-styles.body]` の `size = "30Q"` | `style.toml:1:1: error[G03011]: 段落スタイルの文字の大きさが版面の文字の大きさを超えます: body` |
| `[paragraph-styles.note]` の `based-on = "nothere"` | `style.toml:1:1: error[G03013]: style.toml のスタイルの参照が不正です: 段落スタイル note の based-on がありません: nothere` |

どれも直すべき値は一つに決まるのに、利用者はファイルの中からその値を探すことになる。
`styleChecks` は読み込んだ後の `Style` の値を見ており、`Style` は位置を持たないので、検査の側では位置がわからない。
ただし、`parseStyle` は G07044 のために、`Toml.parse` の結果をたどって `[index]` の `columns` の値の位置（`columnsAt`）を求めている。
同じたどり方を、検査の誤りのすべてに広げられる。

### この ADR の範囲

この ADR は、値の読み込みの誤りについては、実装を仕様の定めに合わせて直す。
読み込んだ後の検査については、[ADR 0006](0006-project-diagnostic-codes.md) の「`style.toml` の先頭」という定めを改め、直すべき値の位置に出す。
v0.1.0-rc3 で直すため、二つを一つの ADR で決める。
diagnostic のコードと文言は、どちらも変えない。

## 実装すること

### 値の読み込みの誤りの位置

- `manifest.toml`、`style.toml`、`plugins.lock` の `FromValue` の実装が作る誤りは、すべて `failAt` で作り、誤りの対象の値の位置（`valueAnn`）を持たせる。
- 文字列として読んでから解釈する値（`padding`、`first-line-indent` など）は、`optKeyOf` と `reqKeyOf` で値を受け取り、キーの中で解釈する。誤りの経路はそのキーまでになる（例：`paragraph-styles.code.padding`）。
- 表の中の二つ以上のキーの組み合わせで決まる誤りは、文言が直すよう求めているキーの値の位置に出す。
  - `columns が 2 以上のときは column-gap が要ります`：`columns` の値。
  - `罫線の length と end-indent は一緒に書けません`：`end-indent` の値。
  - `[hidden-folio] の gutter が size の半分より小さい…`：`gutter` の値。
  - `[sidenotes] の font と size は廃止しました…`：書かれている `font` か `size` の値（両方あれば `font`）。
- 対象の値がその表そのものである誤り（廃止した `[emphasis]` と `[verse]` の表、組み込みのアキ量のセットと同じ名前のセット）は、その表の値の位置に出す。toml-parser は、見出しで定めた表に見出しのキーの位置を付ける（`Toml.Semantics.framesToTable`）。
- diagnostic のコードと文言は変えない。文言の後ろの ` (<経路>)` も今のとおり付ける。

### 読み込んだ後の検査の位置

- `styleChecks` の誤りは、それぞれ直すべき値の経路を一つ持つ。経路は、`style.toml` のキーと配列の添字の列である。
- `parseStyle` は、`style.toml` の TOML の木を経路でたどり、誤りの位置を次の順で決める。
  1. 経路の値があれば、その値の位置。
  2. なければ、経路から最後のキーを除いた表（スタイルの表など）があれば、その表の位置。toml-parser は、見出しで定めた表に見出しのキーの位置を付ける。
  3. どちらもなければ、ファイルの先頭。
- `based-on` で受け継いだ値が誤りの原因であるときは、誤りを報告したスタイルの経路を持たせる。その値は、そのスタイルの表には書かれていないので、2 によってそのスタイルの表の位置になる。
- 同じコードと同じ文言の誤りは、今と同じく一つにまとめる。位置は、まとめた中で最初の経路から求める。
- G07044 の `columnsAt` も、同じたどり方の関数で求める。

検査ごとの経路は次のとおりとする。
`<n>` はスタイルの名前、`<l>` は見出しの段、`<i>` は配列の添字である。

| コード | 検査 | 経路 |
| --- | --- | --- |
| G03006 | 段落スタイル `code` の `padding` が負 | `paragraph-styles.code.padding` |
| G03006 | 文字スタイルの `padding` が負 | `character-styles.<n>.padding` |
| G03006 | 段落スタイル `code` に書けないキー | 書けないキーのうち、文言の一覧の最初のキー |
| G03006 | `background` と `padding` を `code` 以外の段落スタイルに書いた | `paragraph-styles.<n>.background`。なければ `padding` |
| G03006 | 文字スタイルの `background` と `padding` を code の系列でない文字スタイルに書いた | `character-styles.<n>.background`。なければ `padding` |
| G03006 | `border` と `border-width` を `code` 以外に書いた | `paragraph-styles.<n>.border`。なければ `border-width` |
| G03006 | `code` の `border-width` が zw か負 | `paragraph-styles.code.border-width` |
| G03006 | スタイルの名前が英小文字の規則に合わない | `paragraph-styles.<n>` か `character-styles.<n>` |
| G03006 | 見出しと `[code]` の番号の書式 | `headings.<l>.number`、`code.number` |
| G03006 | `[composition]` などの値の範囲（`checks` の各項） | 文言が名指すキー（例：`composition.ruby.overhang`） |
| G03006 | `caption`、`sidenote`、`code` の罫線 | `paragraph-styles.<n>.rule-before`。なければ `rule-after` |
| G03006 | 段落の罫線の長さが 0 以下 | `paragraph-styles.<n>.rule-before`。なければ `rule-after` |
| G03008 | `[fonts]` にない書体の役割 | `headings.<l>.font`、`character-styles.<n>.font`、`paragraph-styles.<n>.font` |
| G03011 | 段落スタイルの文字の大きさが版面の文字の大きさを超える | `paragraph-styles.<n>.size` |
| G03012 | 段落の最初の行が版面の外に出る | `paragraph-styles.<n>.first-line-indent`。なければ `indent` |
| G03013 | `based-on` の先がない、`body` の `based-on`、`code` を `based-on` に書いた | `<種類>.<n>.based-on` |
| G03013 | `based-on` の循環 | 循環に含まれるスタイルのうち、名前の順で最初のものの `based-on` |
| G03013 | スウォッチがない | その色を書いたキー（`character-styles.<n>.color`、`paragraph-styles.<n>.border`、`notes.rule.color`、`headings.<l>.rule-before.color`、`code.colors.<k>` など） |
| G03013 | アキ量のセットがない、セットの `based-on` の先がない、セットの循環 | `paragraph-styles.<n>.aki-set`、`aki-sets.<n>.based-on` |
| G03013 | 正規表現スタイルの文字スタイルと段落スタイルがない | `paragraph-styles.<n>.regex-styles[<i>].style` |
| G03015 | 正規表現を解釈できない | `paragraph-styles.<n>.regex-styles[<i>].pattern` |
| G03021 | オプティカルカーニング | `character-styles.<n>.kerning`、`paragraph-styles.<n>.kerning` |

ここにない検査を加えるときも、直すべき値の経路を一つ持たせる。

`@style-def` の検査は、今と同じく `styleChecks` のスタイルの名前で原稿の `@style-def` のブロックに出し、経路を使わない。

### データ構造

`styleChecks` の結果に経路を足す。
経路は toml-parser の `Scope`（`ScopeKey` と `ScopeIndex`）の列で表し、[ADR 0007](0007-toml-messages-in-japanese.md) の `pathText` と同じ型にする。

```haskell
-- コード、スタイルの名前、直すべき値の経路、文言
styleChecks :: Text -> Style -> [(Text, Text, [Scope], Text)]

-- 経路の値の位置。なければ経路の親の表の位置。どちらもなければ Nothing
checkPosition :: Table' Position -> [Scope] -> Maybe Position
```

`Style` には位置を足さない。
`styleChecks` を使う golem-eval の `Golem.Eval.Settings` は、経路を読み捨てる。

### `fail` を書けなくする

`Golem.Project.Style` と `Golem.Project.Manifest` は、`Prelude` の `fail` を隠して読み込む（`import Prelude hiding (fail)`）。
これらのモジュールで `fail` を書くとコンパイルが通らなくなるので、位置のない誤りを新たに書くことはできない。
`do` の中のパターンの照合の失敗も `MonadFail` の `fail` を呼ぶが、名前を隠しても防げない。
この形の照合は今のこれらのモジュールの `FromValue` にないので、下のテストで位置を確かめるだけにする。

`ParseTable` の中で値を持たない誤りを作るときは、toml-parser の `failTableAt` に位置を渡す。

### 経路の表記

経路の付け方は [golem-project ADR 0007](0007-toml-messages-in-japanese.md) のまま変えない。
キーの中で失敗する誤りが増えるので、上の `padding` の例の経路は `paragraph-styles.code` から `paragraph-styles.code.padding` に変わる。

## 実装しないこと

- レイアウトの段階の検査（G07002、G07025、G07050 など golem-driver の G07xxx）の位置。`style.toml` の先頭のままとする。これらは `Style` から組んだ版面とページを見て決まり、一つの値に帰せない誤りが多い。
- `Style` に位置を持たせること。
- `@style-def` の誤りの位置。原稿の `@style-def` のブロックに出しており、`style.toml` の読み込みと別の経路である。
- 未知のキーの文言とほかの toml-parser の文言。[golem-project ADR 0007](0007-toml-messages-in-japanese.md) で決めた。

## テスト設計

### 先に書いて失敗させるテスト

`modules/golem-project/test/Main.hs` に、表の形のテストを加える。
各行は `style.toml` の断片と、期待するコード、位置（行と桁）、経路を持つ。
Golem が `FromValue` で作る誤りの文言ごとに、一行以上を置く。
少なくとも次の行を含める。

| 断片 | 期待 |
| --- | --- |
| `[paragraph-styles.code]` の `padding = "0"` | G03006、`padding` の値の位置、経路 `paragraph-styles.code.padding` |
| `[character-styles.code]` の `padding = "0"` | G03006、`padding` の値の位置 |
| `[paragraph-styles.body]` の `first-line-indent = "1"` | G03006、値の位置 |
| `[page.grid]` の `line-pitch = "20"` | G03006、値の位置、経路 `page.grid.line-pitch` |
| `[page.grid]` の `position = { top = "14mm", gutter = "14" }` | G03006、`"14"` の位置 |
| `[page.grid]` の `columns = 2` で `column-gap` なし | G03006、`columns` の値の位置 |
| `[page]` の `bleed = "1zw"` | `塗り足しには zw を使えません`、値の位置 |
| `[page]` の `size = 3` | G03017、値の位置 |
| `[hidden-folio]` の `gutter` が `size` の半分より小さい | `gutter` の値の位置 |
| `[aki-sets]` の値に寸法でない文字列 | G03020、値の位置 |
| `[color.swatches.<名前>]` の `cmyk` に五つの整数 | 値の位置 |
| `[emphasis]` の表 | その表の見出しの行 |

`modules/golem-project/test/Main.hs` に、`manifest.toml` の `chapters = [3]` が `3` の位置に出るテストを加える。

読み込んだ後の検査について、同じ表の形のテストを加える。
`styleChecks` が出すコードごとに一行以上を置き、上の経路の表の行ごとに一行を置く。
少なくとも次の行を含める。

| 断片 | 期待 |
| --- | --- |
| `[paragraph-styles.code]` の `padding = "-1mm"` | G03006、`"-1mm"` の位置 |
| `[paragraph-styles.body]` に `background = "x"`（`[color.swatches]` に `x` あり） | G03006、`background` の値の位置 |
| `[paragraph-styles.Body]` の表 | G03006、`Body` の見出しの位置 |
| `[headings.1]` の `font = "nothere"` | G03008、`font` の値の位置 |
| `[paragraph-styles.body]` の `size = "30Q"` | G03011、`"30Q"` の位置 |
| `[paragraph-styles.quote]` の `indent = "0zw"` と `first-line-indent = "-2zw"` | G03012、`first-line-indent` の値の位置 |
| `[paragraph-styles.note]` の `based-on = "nothere"` | G03013、`based-on` の値の位置 |
| `a` と `b` の段落スタイルが互いを `based-on` に書く | G03013 が一つ、`a` の `based-on` の値の位置 |
| `[character-styles.em]` の `color = "nothere"` | G03013、`color` の値の位置 |
| `regex-styles = [{ pattern = "(?s)a", style = "em" }]` | G03015、`pattern` の値の位置 |
| `regex-styles = [{ pattern = "a", style = "nothere" }]` | G03013、`style` の値の位置 |
| `[character-styles.em]` の `kerning = "optical"` | G03021、`kerning` の値の位置 |
| `based-on` で親の大きい `size` を受け継ぎ、自分では `size` を書かない段落スタイル | G03011、そのスタイルの表の見出しの位置 |

`checkPosition` の単体のテストを加える。
ファイルの先頭への後退は、このテストと `parseStyle` の `Nothing` の扱いで確かめる。
経路の値があればその位置、値がなく親の表があれば表の見出しのキーの位置、どちらもなければ `Nothing` であること。
配列の添字（`regex-styles[1]`）をたどれることも確かめる。

G07044 のテスト（`[index]` の `columns` の位置）が、`columnsAt` を `checkPosition` に替えた後も変えずに通ること。
`@style-def` の G03011 と G03013 が、今と同じく `@style-def` のブロックに出ること（`modules/golem-eval/test`）。

ほかに、上の表がどの誤りの文言も漏らさないことを、テストの側で確かめる。
`Golem.Project.Style` と `Golem.Project.Manifest` の `failAt` と `failTableAt` の文言を、テストの表の文言と突き合わせる。
文言を一覧にする仕組みはないので、テストの表に「この文言はこの行で確かめた」という対応を持たせ、レビューで漏れを見る。

`modules/golem-cli/test/Main.hs`：

- `[paragraph-styles.code]` に `padding = "0"` を書いたプロジェクトで、`golem check` の出力が `style.toml:1:1` を含まず、`padding` の行と桁で始まること。
- `[paragraph-styles.body]` に `size = "30Q"` を書いたプロジェクトで、G03011 の行が `size` の行と桁で始まること。

### 自動テストにしない確かめ方

`import Prelude hiding (fail)` を加えた後に、どちらかのモジュールに `fail "x"` を書いてビルドし、コンパイルの誤りになることを一度確かめる。

## トレードオフ

`fail` を隠すので、これらのモジュールで `MonadFail` に頼る書き方（`Just x <- ...` のような `do` の照合）を新たに使うと、位置のない誤りが紛れ込みうる。
名前の隠し方では防げないので、表の形のテストで拾う。

経路がキーまで届くようになり、`padding` などの文言の後ろの経路が変わる。
文言に合わせたテストとスクリプトは直す必要があるが、v1 のリリースの前なので受け入れる。

読み込んだ後の検査は、経路を手で書くので、誤った経路を書いてもコンパイルは通る。
その場合は、親の表かファイルの先頭に出るだけで、diagnostic そのものは失われない。
コードごとの表の形のテストで、経路の誤りを拾う。

検査の位置を求めるために、`style.toml` の TOML の木を一度読み直す。
今も `columnsAt` のために読み直しているので、読み直しの回数は増えない。

組み合わせの誤りの位置を、文言が直すよう求めるキーに決めたので、利用者が直したいキーと違う場合もある。
`columns = 2` の本で、段数を 1 に戻したい利用者は `columns` の行を見て直せる。
`column-gap` を足したい利用者には、文言が足すべきキーの名前を示す。

## ドキュメント

- docs/diagnostics.md の G03006 の節の「読み込んだ後の検査では `style.toml` の先頭である」を、直すべき値の位置（値がなければそのスタイルなどの表、それもなければ先頭）と改める。
- docs/diagnostics.md の G03008、G03011、G03012、G03013、G03015、G03021 の節に、`style.toml` の検査の位置が直すべき値の位置であることを書く。今のこれらの節は `@style-def` の位置だけを書いている。
- docs/diagnostics.md の G03001、G03017、G03018、G03020、G03022、G03025 の節が、値の読み込みの誤りを値の位置としているかを確かめ、先頭としている箇所があれば改める。
- 上のどの節も、ADR の欄にこの ADR を加える。
- docs/specifications.md の、`manifest.toml`、`style.toml`、`plugins.lock` の誤りの文言を述べる段落（TOML の構文の誤りをその行の位置で出すと書いた箇所）に、Golem が値の読み込みで出す誤りと読み込んだ後の検査の誤りも、その値の位置に出すことと、値がないときの位置の決め方を書き、この ADR へリンクする。
- 利用者のマニュアルの付録の diagnostic の一覧で、これらのコードの位置を `style.toml` の先頭と説明している箇所があれば改める。
- [golem-project ADR 0006](0006-project-diagnostic-codes.md) のステータスの行を「採択→Golem の文言の誤りと読み込んだ後の検査の位置は [ADR 0008](0008-style-toml-value-positions.md)」の形で改める（今のステータスの行の記述は残す）。

## 参考文献

- toml-parser 2.0.2.0（Hackage）のソース：`Toml.Schema.Matcher`（`failAt` と `MonadFail` のインスタンス）、`Toml.Schema.ParseTable`（`failTableAt`）、`Toml.Schema.FromValue`（`typeError`）
