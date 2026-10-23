# ADR 0027: 到達しない診断の分岐を型で除く

ステータス: 採択

## 文脈

テストを書く作業で、診断を出すのに実行されない分岐が三つ見つかった。

- **golem-eval の `builtinWith` の最後の枝**：`_ -> err "G02022" ...` である。
  `builtinWith` は、`evalInline` が名前を `builtinInlineCommands` にあると確かめてから、`builtin` を通して呼ぶ。
  `builtinInlineCommands` の名前のうち `aki` は `builtin` が先に処理し、残りの名前は `builtinWith` の `case` がすべて個別に処理する。
  そのため最後の枝に来る名前はない。
- **golem-driver の `Golem.Driver.Plugins` の `call` の `Nothing` の枝**：G02022 を返す。
  評価は `phCommands` か `phOverrides` にある名前でだけ `phCallCommand` を呼ぶ。
  `phCommands` は `commandOwner` のキーそのものである。
  `phOverrides` の名前は、G06006、G06007、G06008 の検査を通ったときに限り、`commandOwner` のキーに含まれる（検査が一つでも誤りを出すと、フックを作らない）。
  そのため `Map.lookup` が `Nothing` を返すことはない。
- **golem-project の `cycleDiagnostic` の `[]` の枝**：G03005 を `manifest.toml` の先頭（`mkSpan (FileId 0) 0 0`）に出す。
  `findCycles` が返す経路は、最後に `(f, site)` を一つ足して作るので、空にならない。
  `cycleDiagnostic` はモジュールの外に公開していないので、ほかの呼び出し元もない。

調べると、もう一つ同じ形の分岐がある。
golem-eval の `noPlugins` の `phCallCommand` は G02022 を返すが、`noPlugins` の `phCommands` と `phOverrides` は空なので、評価はこの関数を呼ばない。
golem-eval の `FileSpec.hs` のテストだけが、この関数を直接呼んでいる。

既存の ADR は、これらの分岐を残すと決めている。
[golem-eval ADR 0003](../golem-eval/adr/0003-evaluation-diagnostic-codes.md) は、`builtin` の最後の枝、`noPlugins` の `phCallCommand`、`Golem.Driver.Plugins` の `call` の G02022 を「プラグインのフックの関数を全域にするための枝として残し」とした。
[golem-project ADR 0006](../golem-project/adr/0006-project-diagnostic-codes.md) は、G03005 の経路が空の分岐を「`cycleDiagnostic` を全域関数に保つため」に残すとした。

どちらも、関数を全域にする手段として、到達しない入力に診断を割り当てている。
しかし、その入力は型が許しているだけで、実際には来ない。
来ない入力に診断を割り当てると、テストで確かめられない診断が残り、位置とメッセージも検査されない（`builtinWith` の枝はコマンド全体を、評価の入口の G02022 は名前を指していて、すでに食い違っている）。
型で入力を絞れば、関数は全域のまま、到達しない分岐を書かずに済む。

この ADR は、そのための型の変更を定め、上の二つの ADR の該当部分を置き換える。
変更が golem-eval、golem-driver、golem-project にまたがるので、横断的な ADR として `docs/adr/` に置く。

## 実装すること

### 組み込みのインラインのコマンドを直和型にする

golem-eval に、組み込みのインラインのコマンドを表す直和型 `BuiltinInline` を足す（データ構造の節）。
`BuiltinInline` は、プラグインが上書きできるもの（`OverridableBuiltin`）とできないもの（`FixedBuiltin`）の二つの直和型を束ねる。
上書きの可否は、述語ではなく型の違いとして表す。
新しいモジュール `Golem.Eval.Builtin` に置き、`Golem.Eval.File` から使う。

- `evalInline` は、名前を `parseBuiltin` で `Maybe BuiltinInline` に変えてから分岐する。
  `builtin` と `builtinWith` は `Text` の代わりに `BuiltinInline` を受け取る。
- `builtinWith` の `case` は `BuiltinInline` の構築子で分け、ワイルドカードの枝を置かない。
  `aki` も `builtinWith` の `case` の枝の一つにし、`builtin` の `name == "aki"` の特別扱いを除く。
  `builtinWith` は先頭で `keywords` を呼ぶが、`keywords` は引数から組を取り出すだけの純粋な関数で、診断も状態の変化も起こさない。
  `aki` の枝が `keywords` の後に来ても、出力と診断は変わらない。
  `aki` は G02014 と G02038 の検査（`ref-*` と `noSlotCommands` に限る）の対象でもないので、検査の順が変わっても影響しない。
- `builtinInlineCommands`、`overridableCommands`、`noSlotCommands` は、`BuiltinInline` から導く。
  `builtinInlineCommands` と `overridableCommands` は今の型（`[Text]`）と今の並びのまま公開を続ける。
  golem-driver の `Golem.Driver.Plugins` と golem-lsp の補完（`Golem.Lsp.Features`）は、今と同じ一覧を受け取る。
- `builtinWith` の G02022 の枝を除く。

### プラグインのコマンドを型で二つに分ける

golem-eval の `PluginHook` の `phCommands`、`phOverrides`、`phCallCommand` を、次の二つの `Map` に置き換える（データ構造の節）。

- **phOverrides**：組み込みのコマンドを上書きするプラグインのコマンド。キーは `OverridableBuiltin` である。
- **phCommands**：組み込みと名前が重ならないプラグインのコマンド。キーは `PluginCommandName` である。

`PluginCommandName` は `Text` の newtype で、構築子を公開しない。
作る関数は `pluginCommandName :: Text -> Maybe PluginCommandName` だけで、組み込みの名前には `Nothing` を返す。
そのため、組み込みと同じ名前のプラグインのコマンドは `phOverrides` にしか入れられず、`phOverrides` のキーは上書きできる組み込みのコマンドに限られる。
宣言のない上書き（今の `phCommands` に `strong` があって `phOverrides` にない状態）や、上書きできない組み込みの上書き（`note` など）は、`PluginHook` として組み立てられない。
名前と呼び出しが同じ値の中で組になるので、名前はあるのに呼び出しがない状態も表せない。

評価の入口（`evalInline` の `A.Command`）は、名前を次のように分ける。

1. `parseBuiltin` が `Overridable o` を返し、`o` が `phOverrides` にあれば、そのプラグインのコマンドを呼ぶ。
2. `parseBuiltin` が `Just b` を返せば、組み込みのコマンド `b` を評価する。
3. `pluginCommandName` で作った名前が `phCommands` にあれば、そのプラグインのコマンドを呼ぶ。
4. どれでもなければ G02022 を出す（名前の位置）。

今の順「上書きのプラグイン、組み込み、プラグイン、G02022」と同じである。

golem-driver の `loadPlugins` は、検査と型への変換を一つの手順で行う。
プラグインが提供するコマンドの名前ごとに、`pluginCommandName` が `Just` を返せば `phCommands` の要素にする。
`Nothing`（組み込みの名前）なら、そのプラグインの `overrides` に宣言があり、`OverridableBuiltin` に変換できるときだけ `phOverrides` の要素にする。
宣言がなければ G06007、宣言はあるが上書きできない名前なら G06008 を、その変換の失敗として出す。
`overrides` に書いた名前をプラグインが提供していない場合の G06008 と、二つのプラグインが同じ名前を提供する場合の G06006 は、今と同じく出す。
検査で確かめた条件を、検査の結果の値の型が持つので、検査の後に名前を引き直して `Maybe` を扱う箇所がなくなる。
`call` の `Nothing` の枝はなくなる。
`noPlugins` の二つの `Map` は空になり、G02022 を返す関数はなくなる。

### 循環の経路を NonEmpty にする

golem-project の `findCycles` の型を `ImportGraph -> [NonEmpty (FileId, ImportSite)]` に変える。
経路は今と同じく、`dropWhile` で切り出した祖先の辺の後に `(f, site)` を足して作り、その最後の要素を `NonEmpty` の構築で保証する。
`cycleDiagnostic` は `NonEmpty (FileId, ImportSite)` を受け取り、`[]` の枝を除く。
位置、メッセージ、関連位置の作り方は変えない。

### 不完全なパターンをエラーにする

`modules/*/*.cabal` のすべて（21 のパッケージ）の `common warnings` の `ghc-options` に `-Werror=incomplete-patterns` を足す。
[ADR 0028](0028-shared-test-support-package.md) が足す golem-test-support も同じにする。
`BuiltinInline` に構築子を足して `builtinWith` の枝を書き忘れると、ビルドが失敗する。
今は `-Wall` の警告だけで、CI は警告で止まらない。
この ADR を書く時点（origin/main の 68bf3b1）で、新しい builddir に全パッケージのライブラリ、実行ファイル、テストスイートを `cabal build all` でビルドし、警告を調べた。
`-Wincomplete-patterns` の警告は一つもなかったので、フラグを足すために直す箇所はない。
ほかに `-Wincomplete-uni-patterns` の警告が一つある（golem-layout の `test/Main.hs` の 825 行目のラムダ `\(Box bw _, x) -> ...`）。
`-Werror=incomplete-patterns` はこの警告をエラーにしないので、この ADR では直さない。
実装までのあいだに警告が増えていれば、実装の中で直す。

### 診断のコード

G02022 と G03005 は廃止しない。

- G02022 は、評価の入口（`Golem.Eval.File` の `evalInline`）で、組み込みにもプラグインにもない名前に出し続ける。出す箇所はここだけになる。
- G03005 は、`cycleDiagnostic` の空でない経路の枝で出し続ける。

`docs/diagnostics.md` の G02022 の「段階とモジュール」から、golem-driver の `Golem.Driver.Plugins` を除き、golem-eval の `Golem.Eval.File` だけにする。
G03005 の節は変えない。
`docs/specifications.md` の G02022 の記述（プラグインの読み込みの失敗の後に報告しないこと）は変えない。
golem-driver の `Driver.hs` の、読み込みの失敗の後に G02022 を除く処理も変えない。

### 既存の ADR のステータス

採択のときに、次の二つの ADR のステータスの行を変える。

- [golem-eval ADR 0003](../golem-eval/adr/0003-evaluation-diagnostic-codes.md)：`採択→到達しない G02022 の枝の扱いは ADR 0027`（相対リンクを付ける）
- [golem-project ADR 0006](../golem-project/adr/0006-project-diagnostic-codes.md)：`採択→toml-parser の文言の扱いは ADR 0007、G03005 の経路が空の分岐は ADR 0027`（相対リンクを付ける）

## データ構造

### BuiltinInline

```haskell
-- | 組み込みのインラインのコマンド。並びは builtinInlineCommands の並び。
data BuiltinInline
  = Overridable !OverridableBuiltin
  | Fixed !FixedBuiltin
  deriving stock (Eq, Ord, Show)

-- | プラグインが上書きできるもの（今の overridableCommands）。
data OverridableBuiltin
  = BStrong | BBold | BItalic | BCode | BRuby | BKenten | BColor | BStyle | BTcy | BNumberText
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | 上書きできないもの。
data FixedBuiltin
  = BRefNumber | BRefTitle | BRefPage | BNote | BSidenote | BIndex | BCite | BAki
  deriving stock (Eq, Ord, Show, Enum, Bounded)

allBuiltins :: [BuiltinInline]                -- 上書きできるもの、できないものの順
builtinName :: BuiltinInline -> Text          -- ワイルドカードなしの case
parseBuiltin :: Text -> Maybe BuiltinInline   -- allBuiltins と builtinName から作る表で引く
takesNoSlot :: BuiltinInline -> Bool          -- ワイルドカードなしの case（noSlotCommands）
```

今の `builtinInlineCommands` は、上書きできる 10 の名前の後に、上書きできない 8 の名前が並ぶ。
`allBuiltins` をこの順に作るので、`builtinInlineCommands` と `overridableCommands` の並びは変わらない。
`builtinName` と `takesNoSlot` はワイルドカードを使わずに全構築子を書く。
構築子を足したときに、名前と散文スロットの扱いを決め忘れると、`-Werror=incomplete-patterns` で止まる。
上書きの可否は、構築子をどちらの型に置くかで決まるので、決め忘れることがない。
`parseBuiltin` は `builtinName` の逆として作るので、名前の表を二か所に書かない。

### PluginHook

```haskell
-- | プラグインのコマンド一つの呼び出し。
newtype PluginCommand = PluginCommand
  { pcCall :: [Value] -> [[Inline]] -> SrcSpan -> Either [Diagnostic] ([Inline], [Diagnostic])
  }

-- | 組み込みと重ならない名前。構築子は公開しない。
newtype PluginCommandName = PluginCommandName Text
  deriving stock (Eq, Ord, Show)

pluginCommandName :: Text -> Maybe PluginCommandName  -- 組み込みの名前なら Nothing
unPluginCommandName :: PluginCommandName -> Text

data PluginHook = PluginHook
  { phOverrides :: !(Map OverridableBuiltin PluginCommand),
    phCommands :: !(Map PluginCommandName PluginCommand),
    phApplyFilters :: FilePath -> Document -> Either [Diagnostic] (Document, [Diagnostic])
  }
```

`phCallCommand` はなくなり、`phOverrides` と `phCommands` の型が変わる。
`noPlugins` は `PluginHook Map.empty Map.empty (\_ d -> Right (d, []))` になる。
`PluginCommandName` と `pluginCommandName` は `Golem.Eval.Builtin` に置き、構築子を隠す。

### findCycles

```haskell
findCycles :: ImportGraph -> [NonEmpty (FileId, ImportSite)]
cycleDiagnostic :: FileTable -> NonEmpty (FileId, ImportSite) -> Diagnostic
```

## 実装しないこと

- G02022 と G03005 の番号、重大度、メッセージ、位置は変えない。
- `-Wincomplete-uni-patterns` と `-Wincomplete-record-updates` は、警告のままにする。エラーにするのは、`case` と関数の定義の網羅性を見る `-Wincomplete-patterns` だけである。
- `phApplyFilters` の型は変えない。フィルタの名前の検査（G06010）は今のままである。
- `builtinInlineCommands` と `overridableCommands` を公開から外さない。golem-driver と golem-lsp の使い方を変えないためである。
- ブロックのコマンド（`@figure` など）と属性のコマンドの名前を直和型にすることは、この ADR では行わない。到達しない分岐は見つかっていない。
- [golem-project ADR 0006](../golem-project/adr/0006-project-diagnostic-codes.md) が挙げた `Style` の `FromValue` の到達しない `fail` は、同じ ADR が除くと決めているので、ここでは扱わない。

## テスト設計

型を変える前に、次のテストを書く。
新しい名前（`BuiltinInline`、`PluginCommand`、`NonEmpty` を返す `findCycles`）を使うテストは、型を変える前はコンパイルが通らず、失敗する。
今の挙動を固定するテストは、変更の前と後の両方で通ることを確かめる。

### golem-eval

- `parseBuiltin (builtinName b) == Just b` が、`allBuiltins` のすべての `b` で成り立つ。
- `allBuiltins` が、`OverridableBuiltin` と `FixedBuiltin` のすべての構築子を一度ずつ含む。
- `parseBuiltin` は、組み込みでない名前（`nope`、空文字列、`Strong` のような大文字）に `Nothing` を返す。
- `builtinInlineCommands` が、今の一覧と同じ並びで等しい（`["strong", "bold", "italic", "code", "ruby", "kenten", "color", "style", "tcy", "number-text", "ref-number", "ref-title", "ref-page", "note", "sidenote", "index", "cite", "aki"]`）。
- `overridableCommands` が、今の一覧と同じ並びで等しい。
- `noSlotCommands` にあたる名前（`number-text`、`ref-number`、`ref-title`、`ref-page`、`cite`）に散文スロットを書くと、今と同じ G02038 が出る。
- `aki` の今のテスト（G02055 を含む）が変わらずに通る。`aki` に散文スロットを書いた場合も、今と同じ G02055 が出る。
- プラグインのコマンドの上書き：`phOverrides` に `BStrong` を持つフックで `[strong: x]` がプラグインの出力になる（今の `FileSpec.hs` のテストを新しい型で書き直す）。
- `phCommands` に組み込みでない名前（`greet`）を持つフックで `[greet: x]` がプラグインの出力になり、`[nope: x]` は G02022 になる。
- `pluginCommandName` は、`builtinInlineCommands` のすべての名前に `Nothing` を返し、`greet` には `Just` を返す。
- G02022 の今のテスト（`[nope: x]` の位置が名前であること）は変えずに通る。`noPlugins` の `phCallCommand` を直接呼ぶ部分は、関数がなくなるので除く。

### golem-driver

- `loadPlugins` が作るフックの `phOverrides` と `phCommands` のキーを名前に戻して合わせたものが、今の `phCommands`（`commandOwner` のキー）と等しく、`phOverrides` のキーの名前が今の `phOverrides` と等しい。上書きを宣言したプラグインと、上書きのないプラグインの二つの場合で確かめる。
- 上書きのコマンドを使う原稿のビルドで、プラグインの出力が使われる（既存の `PluginsSpec.hs` のテストが通ること）。
- G06006、G06007、G06008 の既存のテストが、コード、メッセージ、位置、出る順まで変わらずに通る。検査と変換を一つにしても、出す診断の並び（G06006、G06007、G06008、G06010 の順）は変えない。
- 読み込みの失敗の後に G02022 を出さない既存のテスト（`PluginsSpec.hs` と `DiagnosticsSpec.hs`）が変わらずに通る。
- `docs/diagnostics.md` と、ソースが使うコードの照合（`modules/golem-driver/test/Main.hs`）が通る。G02022 と G03005 は、ソースで使われ続けるので「使用中」のままである。

### golem-project

- `findCycles` を直接呼ぶテストを足す。自分自身の import は長さ 1 の経路を一つ、`a → b → a` は長さ 2 の経路を一つ、`a → b → c → a` は長さ 3 の経路を一つ返す。循環のないグラフには空のリストを返す。
- G03005 の既存のテスト（長さ 2 の循環と自分自身の import）の位置、メッセージ、関連位置が変わらない。

### 振る舞いが変わらないことの確かめ方

- 全パッケージのテスト（`cabal test all`）が通る。
- `scripts/determinism.sh` の出力が、変更の前と後で同じである。
- `-Werror=incomplete-patterns` を足した後に、作り直し（`--builddir` を新しくする）で `cabal build all` が通る。確かめとして、一時的に `FixedBuiltin` に構築子を一つ足し、golem-eval のビルドが失敗することを手で確かめる（コミットしない）。
- `scripts/ci/` に、すべての `modules/*/*.cabal` の `ghc-options` に `-Werror=incomplete-patterns` があることを確かめる検査を足し、`scripts/ci/test.sh` から呼ぶ。パッケージを足したときに付け忘れると CI が失敗する。

## トレードオフ

- 組み込みのコマンドの名前は、`BuiltinInline` の構築子と `builtinName` の二か所に現れる。今は `builtinInlineCommands` の一覧と `builtinWith` の文字列のパターンの二か所なので、数は増えない。代わりに、二か所の食い違いをコンパイラが見つける。
- 上書きと上書きでないプラグインのコマンドを、二つの `Map` と隠した構築子で分ける。型と関数が増え、`loadPlugins` は名前を型に変換する手順を持つことになる。代わりに、宣言のない上書きと上書きできない組み込みの上書きは、`loadPlugins` を通らずに組み立てたフック（テストのものも含む）でも表せなくなり、評価の分岐の正しさが `loadPlugins` の検査に依存しなくなる。一つの `Map` にまとめて検査に任せる案は、検査を通らないフックで評価が今と違うコマンドを選びうるので採らない。
- `PluginCommandName` の構築子を隠しても、`Golem.Eval.Builtin` の中では作れる。隠すのは、モジュールの外（golem-driver とテスト）から組み込みの名前を `phCommands` に入れられないようにするためで、モジュールの中の正しさは `pluginCommandName` のテストで確かめる。
- `-Werror=incomplete-patterns` は、一時的な書きかけの状態でもビルドを止める。開発の途中で不便になる場面があるが、網羅していない `case` を残さないことを優先する。全パッケージに付けるのは、パッケージごとに規則が違うと、どのパッケージで網羅性が保証されるかを覚えておく必要が生じるからである。
- `-Werror` を付けても、ワイルドカードの枝（`_ ->`）を書けば網羅性の検査は通る。ワイルドカードを禁じる検査は GHC にないので、レビューで見る。
- G02022 と G03005 の出る箇所を減らすので、`docs/diagnostics.md` の記述と既存の ADR のステータスを更新する手間がかかる。

## 参考文献

なし
