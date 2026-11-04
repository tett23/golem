# ADR 0110: キーワード引数をプラグインに名前ごと渡す

ステータス: 採択

## 文脈

プラグインのコマンドの要求は、評価済みの引数を持つ（[golem-plugin ADR 0001](../golem-plugin/adr/0001-wasm-host-and-abi.md)）。
CDDL（`modules/golem-doc/schema/golem-doc.cddl`）は、引数を `argument = [0, value] / [1, key: tstr, value]` とし、位置引数とキーワード引数を区別する（[golem-doc.cddl](https://github.com/tett23/golem/blob/fa55dc76be6fef7189cb80883fd0bb0b0630911f/modules/golem-doc/schema/golem-doc.cddl#L102)）。
`[1, key, value]` がキーワード引数の形である。
開発者のマニュアルのプラグインの章も、同じ CDDL を載せている。

ところが、ホストはすべての引数を `[0, value]` で送っていた。
評価器はキーワード引数の名前を捨てて値だけを並べ（[`evalCommand`](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-eval/src/Golem/Eval/File.hs#L1689-L1692)）、要求を組む関数は値の列しか受け取らない（[`commandRequest`](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-plugin/src/Golem/Plugin.hs#L250-L253)）。
`[number-text 12 style=tcy]` と `[number-text 12 tcy]` は、プラグインには同じ要求になる。
`[greet a n=1]` を受け取ったプラグインには、`"a"` と `1` の二つの位置引数が届き、`n=` は消えている。
同じ箇所は、`*[式]` と `**[式]` の展開の引数を、評価せずに `[0, null]` として送っていた。

この食い違いは、二つの見本のプラグインを書いて、別々に見つかった。

- `kansuji`（[docs/adr/0125](0125-kansuji-plugin-overrides-number-text.md)）では、`[number-text 123 style=kanji-digits]` が「位置引数が二つ」の誤りになった。
- TSV から表を組むプラグイン（[docs/adr/0129](0129-tsv-table-plugin.md)）では、`align=left,right` を渡そうとして、プラグインからは `align` の値か二つめの位置引数かを見分けられなかった。Rust の補助のクレート（[docs/adr/0106](0106-sample-plugins-in-rust.md)）は `Arg::Keyword` を読む作りになっていたが、その枝に届く要求はなかった。

wat で書いたテスト用のプラグインは、どれもキーワード引数を読まないので、これまでのテストでは見つからなかった。
[golem-plugin ADR 0001](../golem-plugin/adr/0001-wasm-host-and-abi.md) は要求の中身を「評価済みの引数」とだけ書いており、キーを捨てるとは決めていない。
CDDL と実装の食い違いであり、どちらに合わせるかを決める必要がある。

組み込みのコマンドを上書きするプラグイン（[docs/adr/0031](0031-adr-code-mismatches.md)）にとって、これは致命的である。
組み込みの `number-text` と `kenten`（`shape=`）はキーワード引数で意味を変えるので、上書きしたプラグインが同じ書き方を受け取れない。

ロードマップの v0.1.0-rc4 の「`*[式]` の展開とプラグインへの引数」は、この二つ（キーの欠落と展開）を一つの項目に挙げている（[docs/roadmap.md](../roadmap.md)）。
展開の意味は、すでに docs/markup.md の「引数」の節が「`*[式]` は配列を位置引数に、`**[式]` は連想配列をキーワード引数に展開する」と定めている。
展開したキーがほかのキーワード引数と重なれば G02077 とすることも、[golem-parser ADR 0013](../golem-parser/adr/0013-splat-after-keyword-arguments.md) が決めている。
決まっていないのは、評価器が展開を実装していないことだけである。

この ADR は、二つのレーンがそれぞれ書いた草稿を一つにまとめたものである。
二つの草稿が食い違った点は、「決めたことの記録」のとおりに決めた。

## 実装すること

### キーワード引数

- 評価器は、キーワード引数を名前と値の組としてプラグインに渡す。引数の順は原稿に書いた順のままとする。
- 要求では、位置引数を `[0, value]`、キーワード引数を `[1, key, value]` と書く。CDDL の形は変えない。
- 同じキーを二度書いた引数は、今と同じく評価器が G02077 を報告し、二つめから後を除いてから渡す（[golem-parser ADR 0013](../golem-parser/adr/0013-splat-after-keyword-arguments.md)）。最初のものが残る。

CDDL のとおりに書くようにするだけだが、プラグインが受け取るバイト列は変わるので、ABI の変更にあたる。

### 展開の引数

`*[式]` と `**[式]` は、[docs/adr/0112](0112-spread-arguments.md) のとおり、組み込みのコマンドと同じ規則で、引数を読む前に一か所で展開する。
プラグインのコマンドには、展開した後の位置引数とキーワード引数が届き、展開の引数そのものは届かない。
型の誤り（G02111、G02112）と、展開したキーの重なり（G02077）も、[docs/adr/0112](0112-spread-arguments.md) のとおりである。
試しの実装でプラグインの呼び出しの中に書いた展開（コミット `dce87e9c`）は使わない。

### ABI

ABI のバージョンは 8 のままとする。
8 はまだリリースに含まれていない（[docs/adr/0052](0052-plugin-abi-version-bump-rule.md)）。

### データ構造

引数は、位置引数とキーワード引数の和の型で持つ。
`PluginArg` を golem-plugin ではなく golem-eval に置くのは、`PluginCommand` が golem-eval にあり、golem-plugin がすでに golem-eval に依存しているからである。

```haskell
-- Golem.Eval.Value
data PluginArg = PluginPositional !Value | PluginKeyword !Text !Value
pluginArgValue :: PluginArg -> Value

-- Golem.Eval.File
newtype PluginCommand = PluginCommand
  { pcCall :: [PluginArg] -> [[Inline]] -> SrcSpan -> Either [Diagnostic] ([Inline], [Diagnostic]) }

-- Golem.Plugin
commandRequest :: Plugin -> Text -> [PluginArg] -> [[Inline]] -> SrcSpan -> Either PluginError ByteString
callCommand :: Plugin -> Text -> [PluginArg] -> [[Inline]] -> SrcSpan -> Either PluginError ([Inline], [Diagnostic])
```

`[(Maybe Text, Value)]` の組でも同じことを表せるが、和の型なら位置引数とキーワード引数の違いを型で読める。

### 適用の範囲

この ADR はインラインのコマンドに当てる。
ブロックコマンドは [docs/adr/0122](0122-block-commands-in-plugins.md) で入り、その要求の引数も、この ADR と同じ `[0, value]` と `[1, key, value]` の形で書く。

どちらの形でも、golem-* のパッケージのあいだの build-depends は変えない。

### ドキュメント

- docs/specifications.md の「シリアライズ形式」に、キーワード引数を名前ごと渡すことと、展開した後の引数が届くこと（[docs/adr/0112](0112-spread-arguments.md)）を書く。
- 採択の後、docs/roadmap.md の「プラグインへのキーワード引数」を除く（展開の部分は [docs/adr/0112](0112-spread-arguments.md) で除く）。
- 開発者のマニュアルのプラグインの章の CDDL の注記に、キーワード引数の順と、展開した後の引数が届くことを書く。

## 実装しないこと

- 引数を名前ごとの表にして渡すこと。CDDL の形のまま、原稿の順の列で渡す。
- CDDL の `value` に連想配列を足すこと。
- プラグインが受け取るキーを `golem_describe` で宣言し、ホストが未知のキーを拒むこと。今は、未知のキーの報告はプラグインが自分の diagnostic で行う。
- 展開そのもの。[docs/adr/0112](0112-spread-arguments.md) が決める。

## テスト設計

下のテストのうち、見本のプラグイン kansuji（[docs/adr/0125](0125-kansuji-plugin-overrides-number-text.md)）と tsv-table（[docs/adr/0129](0129-tsv-table-plugin.md)）を使うものは、この ADR の実装では書かない。
この ADR の実装では、同じことを wat のテスト用のプラグイン（`modules/golem-plugin/test/` と golem-driver のテストの wat）で確かめるテストを先に書く。
見本のプラグインを使うテストは、結合のテストとして、その見本のプラグインの ADR を実装するときに足す。
見本のプラグインの ADR が、この ADR より後に実装されるからである。

二つの試しの実装で、次のテストを書いた。

number-tcy のレーンの試し（ブランチ `plugins-number-tcy` のコミット `49990eab` と `dce87e9c`）では、テストを先に書き、失敗することを確かめてから実装した。

- golem-plugin の `NumbersSpec`：`echo.wat` に位置引数、キーワード引数、位置引数の順で渡すと、要求の引数が `[0, 1]`、`[1, "style", "tcy"]`、`[0, "x"]` の順になる。`PluginArg` がない状態ではコンパイルできない。
- golem-driver の `PluginsSpec`：`kansuji` の `[number-text 123 style=kanji-digits]` が「一二三」になる。修正の前は `kansuji-arity` で失敗した。
- golem-driver の `PluginsSpec`：`[number-text *[[123]]]` が「百二十三」、`[number-text 12 **[{style: "tcy"}]]` が縦中横の数になる。`[number-text *[12]]` が G02111、`[number-text 12 **[[1]]]` が G02112、`[number-text 12 style=kanji **[{style: "tcy"}]]` が G02077 になる。修正の前は、`kansuji` の `kansuji-not-number` と `kansuji-arity` で失敗した。このテストは展開を扱うので、[docs/adr/0112](0112-spread-arguments.md) の実装の後に通す。
- 既存の golem-plugin、golem-eval、golem-driver のテストが通る。

TSV のレーンの試し（ブランチ `plugins-tsv-table`）では、次のことを確かめる。

- golem-plugin：`echo.wat` に渡した `[PluginKeyword "n" 3, PluginPositional true]` が、`[[1, "n", 3], [0, true]]` の引数になる（`BlockSpec.hs`）。
- golem-eval：`[greet a n=1]` で、プラグインが `[PluginPositional a, PluginKeyword "n" 1]` を受け取る（`FileSpec.hs`）。
- golem-driver：`@tsv-table sales align=left,right,center` の `align` がプラグインに届き、表の揃えになる（`PluginsSpec.hs`）。

TSV のレーンの試しのテストは、`[(Maybe Text, Value)]` の型で書いたので、上のとおり `PluginArg` に書き直す。

## トレードオフ

キーワード引数を持つ呼び出しで、要求のバイト列が変わる。
キーワード引数を位置引数として読んでいたプラグインは、`[1, key, value]` を読めずに壊れる。
見本のプラグインと wat のテスト用のプラグインには、そのようなものはない。
ABI のバージョン 8 はまだリリースしていないので、配布済みのプラグインへの影響もない。

キーを `golem_describe` で宣言させれば、綴りの誤りをホストが一律に報告できる。
その代わり、記述の欄がまた一つ増え、引数の型や必須かどうかまで宣言したくなる。
今回はキーを渡すところまでにとどめた。

## 決めたことの記録

- **キーワード引数を ADR にするか**：メンテナーが、ADR にすると決めた（2026-10-29）。
- **展開の扱い**（number-tcy のレーンの記録）：メンテナーは、仕様にするか、拒むか、範囲の外としてロードマップを指すかを決めるよう求めた。最初の草稿は、プラグインのコマンドだけ仕様にし、組み込みのコマンドを範囲の外とする案だった。メンテナーが、組み込みのコマンドの展開も rc4 までに要るので今行うと決めた（2026-10-29）。展開は [docs/adr/0112](0112-spread-arguments.md) に分け、この草稿はキーワード引数だけを扱う。
- **草稿の統合**：number-tcy のレーンと TSV のレーンが、同じ修正をそれぞれ草稿にしていた。二つを一つの ADR にまとめ、食い違う点を残した。
- **テストのプラグイン**：メンテナーが、土台の ADR は wat のテスト用のプラグインで試し、見本のプラグインを使う結合のテストは見本のプラグインの実装のときに足す運用にすると決めた（2026-11-04）。
- **統合で残った相違**：二つのレーンの草稿の食い違いを、この版で次のように決めた（2026-11-04）。展開は [docs/adr/0112](0112-spread-arguments.md) に従う（メンテナーの 2026-10-29 の決定に合う）。型は和の型 `PluginArg` にする。この ADR はインラインのコマンドに当て、ブロックコマンドは [docs/adr/0122](0122-block-commands-in-plugins.md) が同じ形を使う。ドキュメントには展開した後の引数が届くことも書く。

## 参考文献

- RFC 8610, Concise Data Definition Language (CDDL). https://www.rfc-editor.org/rfc/rfc8610
