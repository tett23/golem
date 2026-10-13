# ADR 0013: 段落の区切り方をマニフェストで選ぶ

ステータス: 採択

## 文脈

今の記法では、段落は空行で区切る（[markup.md](../markup.md) の「段落と改行」、[仕様書](../specifications.md)の「段落内の改行」）。
段落の中の改行は文字を生まず、前後の地の文をそのままつなぐ。
日本語では行の折り返しの位置に空白を入れないための規則である。

この規則は、原稿の書き方の一つの流儀に合わせたものである。
欧文の原稿は、空行で段落を区切ることが多い。
和文の原稿（青空文庫の形式など）は、一行を一つの段落とし、改行ひとつで段落を区切ることが多い。
和文の原稿を今の記法に移すには、段落のあいだに空行を足す必要がある。
fixture の『蟹工船』を作る変換スクリプト（`scripts/fixtures/aozora_to_gm.py`）は、原典の空でない行を空行でつないで出力している。

そこで、段落の区切り方を二つの様式から選べるようにする。

- **空行の様式**：今の規則。空行で段落を区切り、段落の中の改行は文字を生まない。
- **改行の様式**：改行ひとつで段落を区切る。

### 今の処理の流れ

改行の扱いは、構文解析、AST への変換、評価の三段にまたがっている。

- 文法（`modules/golem-parser/grammar/Golem.peg`）の `Blocks` は、ブロックのあいだの空行を任意としている（`BlankLines?`）。段落の続きの行（`LineContinuation`）は、行頭がブロックの始まりの文字（`BlockStart`）でない行に限る。このため、段落の直後の行が `#` や `@` で始まれば、空行がなくても段落はそこで終わる（[golem-parser ADR 0003](../golem-parser/adr/0003-block-grammar.md)）。
- AST への変換は、段落の中の改行を `SoftBreak` として残す（[docs/adr/0003](0003-verse-line-breaks.md)）。空行は CST のトリビアであり、AST には残らない。
- 評価の入口（`Golem.Eval.File.normalizeBlock`）が、`joinSoftBreaks` で `SoftBreak` を落とし、前後の `Text` をつなぐ。韻文の本体の段落では、最上位の `SoftBreak` を残して行の区切りにする。

[docs/adr/0005](0005-character-and-paragraph-styles.md) は、韻文の扱いを段落スタイルの `line-breaks`（`join` か `keep`）に一般化した。
`keep` の段落では、最上位の `SoftBreak` が行の区切り（`LineBreak`）になる。
ADR は連番の順に実装するので、この ADR は [docs/adr/0005](0005-character-and-paragraph-styles.md) と [docs/adr/0006](0006-paragraph-indent.md) の実装の後の状態を前提に書く。

### 実装の層の比較

段落の区切り方の情報はマニフェストにあり、構文解析はマニフェストを読む前に行う。
次の二つを比べた。

- 構文の層で切り替える：文法の `LineContinuation` を様式で切り替え、改行の様式では段落を一行で終える。
- 評価の層で組み直す：文法と AST は変えず、評価の入口で、段落を最上位の `SoftBreak` で分けて複数の段落にする。

評価の層を採る。
理由は次の四つである。

- 構文の層で切り替えると、CST と AST がマニフェストに依存する。`golem fmt a.gm` のように一つのファイルを整形するだけでもマニフェストを読む必要が生じ、整形の不変条件（整形の前後で AST が一致する）も様式ごとに検査することになる。評価の層なら、CST と AST は原稿のテキストだけで決まる。
- LSP は、マニフェストの変更のたびに、すべてのファイルを構文解析し直すことになる。将来のインクリメンタルな再解析（[golem-lsp ADR 0001](../golem-lsp/adr/0001-language-server.md) が後に回した項目）でも、ファイルの先頭の上書き（[docs/adr/0014](0014-in-file-settings.md)）を一行変えるとファイル全体の解析が変わる。評価の層なら、解析の結果は様式によらない。
- 改行の様式で必要な情報は、すでに AST にある。最上位の `SoftBreak` が改行ひとつの位置であり、空行はブロックの境界として表れている。
- ブロックの記法の扱いが二つの様式で変わらない。見出しやリストは、今も空行なしで段落の直後に書ける。

決定性は、どちらの層でも保てる。
評価の層でも、出力はマニフェストと原稿のテキストだけで決まる。

## 実装すること

### マニフェストの欄

`manifest.toml` に `[source]` の節を設け、`paragraph-separator` のキーを置く。

```toml
chapters = [
  "chapters/01.gm",
  { file = "chapters/02-en.gm", paragraph-separator = "blank-line" },
]

[source]
paragraph-separator = "line"
```

| キー | 値 | 既定 | 意味 |
|---|---|---|---|
| `paragraph-separator` | `"blank-line"` か `"line"` | `"blank-line"` | `blank-line` は空行の様式、`line` は改行の様式 |

- `[source]` は、原稿の読み方を決める設定の節である。ファイルごとに変えられる設定は、この節のキーに限る。
- 章の配列の項目（`{ file = "...", master = "..." }` の形）にも、`[source]` のキーを書ける。その章のファイルにだけ効く。
- 既定は `blank-line` とする。既存の原稿の出力を変えないためである。`[metadata]` の `language` からは推定しない。言語を変えただけで段落の数が変わるのを避けるためである。
- 一つのファイルに効く値は、次の順で最初に見つかったものとする。ファイルの中の上書き（[docs/adr/0014](0014-in-file-settings.md)）、章の項目、`[source]`、既定。
- `@import` でだけ参照されるファイルには、`[source]` の値が効く。
- 未知のキー、不正な値は、マニフェストのほかの誤りと同じく G0301 とする。同じファイルを章の配列に二度並べ、項目の `[source]` のキーの値が異なる場合も G0301 とする。

### 値の型と表（golem-parser）

様式の型と、`[source]` のキーの表を、golem-parser の新しいモジュール `Golem.Parser.SourceSettings` に置く。

```haskell
data ParagraphSeparator = BlankLineSeparated | LineSeparated
  deriving stock (Eq, Show)

newtype SourceSettings = SourceSettings
  { ssParagraphSeparator :: ParagraphSeparator
  }
  deriving stock (Eq, Show)

defaultSourceSettings :: SourceSettings

-- | [source] のキーと、文字列の値を読んで設定を書き換える関数。
-- 値が不正なら、受け付ける値を並べたメッセージを返す。
sourceKeys :: [(Text, Text -> Either Text (SourceSettings -> SourceSettings))]
```

golem-project（マニフェストの読み込み）、golem-eval（評価とファイルの中の上書き）、golem-lint、golem-lsp は、いずれもすでに golem-parser に依存している。
ここに置けば、依存の辺を増やさずに、マニフェストとファイルの中の上書き（[docs/adr/0014](0014-in-file-settings.md)）で同じ表を使える。
様式は AST の `SoftBreak` の読み方を決める値なので、AST と同じパッケージに置く。

### マニフェストの読み込み（golem-project）

- `Manifest` に `manifestSource :: !SourceSettings` を加える。`[source]` の節を、文字列の値の表として読み、各キーを `sourceKeys` で解釈する。表にないキーは G0301 とする。
- `ChapterEntry` の `ChapterFile` に、項目に書いた `[source]` のキーの書き換え（`SourceSettings -> SourceSettings` の列。書いた順）を持たせる。`chapterFiles` は、パスとマスターページに加えてこの書き換えを返す。表の形の項目で、`file` と `master` のほかのキーは `sourceKeys` で解釈し、表にないキーは G0301 とする。
- `Project` に `projectSourceSettings :: !(Map FileId SourceSettings)` を加える。章のファイルには `[source]` の値に項目の書き換えを適用した値を、`@import` でだけ参照されるファイルには `[source]` の値を入れる。

### 評価（golem-eval）

`EvalContext` に `ctxSource :: !SourceSettings` を加える。
golem-driver の `reeval` は `projectSourceSettings` の値を渡す。
`EvalResult` に `erSource :: !SourceSettings` を加え、そのファイルに実際に効いた設定を返す。
lint と LSP が改行の扱いを知るためである。
この ADR の範囲では `ctxSource` と同じ値であり、[docs/adr/0014](0014-in-file-settings.md) でファイルの中の上書きを反映する。

`evalFile` は、`normalizeBlock` の前に次の関数を通す。

```haskell
-- | 改行の様式で、段落を最上位の SoftBreak で分ける。
-- 空行の様式では何もしない。
splitLines :: SourceSettings -> Map Text LineBreaks -> [A.Located A.Block] -> [A.Located A.Block]
```

改行の様式では、ブロックの列を次の規則で書き換える。
`Map Text LineBreaks` は `ctxParaStyles`（[docs/adr/0005](0005-character-and-paragraph-styles.md)）である。

1. `A.Paragraph is` は、`is` を最上位の `SoftBreak` で分け、分けた列ごとに一つの `A.Paragraph` にする。
   - 各列の先頭の `Text` の先頭の空白とタブを取り除く。全角の空白（U+3000）は取り除かない。
   - 空になった列は捨てる（コメントだけの行など）。校正用のコメント（`ProofComment`）だけの列は、AST への変換が校正用のコメントだけの段落を残す規則（[golem-parser ADR 0005](../golem-parser/adr/0005-cst-to-ast.md)）に合わせて残す。
   - 各段落の位置は、列の最初の要素の始まりから最後の要素の終わりまでとする。
2. `A.Attributed cmds (Just t)` で `t` が段落の場合：
   - `cmds` に `@style 名前` があり、名前の `line-breaks` が `keep` なら、何もしない。段落の中の改行は行の区切りになる。
   - それ以外は、`t` を 1 の規則で分け、最初の段落を対象のブロックに残し、残りの段落をまとまりの直後に独立したブロックとして並べる。属性は直後のブロックに付くという規則（[markup.md](../markup.md) の「ブロックへの属性」）を、分けた後の段落に当てはめた結果である。
3. 本体を持つ `@style 名前` で、名前の `line-breaks` が `keep` なら、本体を書き換えない。韻文の連は、二つの様式のどちらでも空行で区切る。
4. ほかのブロックコマンドの本体（本体を持つ `join` の `@style`、`@figure` のキャプションなど）、リストの項目、定義リストの説明は、中のブロックの列に再帰して適用する。
5. 見出し、定義リストの用語、表、コードブロックは書き換えない。どれも一行で書く記法である。

`SoftBreak` を分けた後の各段落には、今と同じく `normalizeBlock` が `joinSoftBreaks` をかける。
散文スロットの中の改行（`"[note: a\nb]"` の中など）は最上位の `SoftBreak` でないので、段落を分けず、二つの様式のどちらでも文字を生まない。
コメントの中の改行も、AST に `SoftBreak` として残らないので段落を分けない。

### 改行の様式での記法の扱い

markup.md の「段落と改行」に、改行の様式の節を加え、次を書く。

- 空行は無視する。空行がいくつあっても、改行ひとつと同じく段落の区切りになるだけで、空きを生まない。
- 見出し、リスト、定義リスト、表、コードブロック、ブロックコマンドは、空行の様式と同じ規則で書く。段落の直後の行でも、行頭の文字でブロックが始まる。
- リストの項目の続きの行（2 つ深くインデントした行）は、項目の中の次の段落になる。
- 属性は、直後の一行の段落にだけ付く。複数の段落に段落スタイルを付けるには、本体を持つ `@style` を使う。
- `line-breaks = "keep"` の段落スタイルの段落（`@style verse` など）では、改行は行の区切りであり、連は空行で区切る。空行の様式と変わらない。
- 段落の中で行を折り返して書く手段は設けない。一つの段落は一行で書く。行末の `\` は、空行の様式と同じく構文エラーのままとする。
- 散文スロットの中とコメントの中の改行は、段落を区切らない。

### lint（golem-lint）

G0501（段落の中の改行の前後がともに欧文）は、改行の様式の段落の最上位の改行には当てない。
そこでは改行が段落の区切りであり、単語はつながらないためである。

- `FileLint` に `flSource :: !SourceSettings` を加え、`latinJoinedByNewline` の引数にする。
- 改行の様式では、`NParagraph` と `NListItem` の最上位の改行を調べず、入れ子の `NProseSlot` だけを調べる。今の `keep` の段落スタイルの段落の扱い（[docs/adr/0005](0005-character-and-paragraph-styles.md)）と同じ走査である。
- `Golem.Driver.Lint` は、評価の結果の `erSource` を渡す。

[golem-lint ADR 0001](../golem-lint/adr/0001-lint-rules.md) のステータスの行の末尾に「、G0501 の改行の様式の扱いは docs/adr/0013」を加え、この ADR へのリンクを付ける。

### fmt（golem-fmt）

コードは変えない。
fmt は改行の位置を変えず（[golem-fmt ADR 0001](../golem-fmt/adr/0001-formatter.md)）、AST は様式によらないので、整形の不変条件はそのまま成り立つ。
改行の様式では `"a\n\nb"` と `"a\nb"` が同じ出力になるが、AST は異なるので、fmt はどちらかに寄せない。

### LSP（golem-lsp）

- 診断は、`erSource` を使う lint を通して出る。プロジェクトの外のファイル（`wsLoose`）の `latinJoinedByNewline` には、評価の結果の `erSource` を渡す。
- `manifest.toml` を変えたときは、今と同じくプロジェクト全体を評価し直す。構文解析の結果は変わらない。

### 変換スクリプトと fixture

- `scripts/fixtures/aozora_to_gm.py` は、本文の段落を改行ひとつでつないで出力する。見出し（`@nonumber` と `# ...` の組）と奥付の見出しの前後には、読みやすさのために空行を置く。
- `modules/golem-driver/test/fixtures/kanikosen/manifest.toml` に `[source] paragraph-separator = "line"` を加え、`kanikosen.gm` を `scripts/fixtures/fetch-public-domain.sh` で作り直す。
- `scripts/fixtures/gutenberg_play_to_gm.py` と `tempest` は変えない。欧文の原稿として空行の様式のまま使う。

### ドキュメント

- markup.md の「段落と改行」を、二つの様式の説明に書き直す。
- 仕様書の「段落内の改行」に、改行の様式とマニフェストの `[source]` を書く。「メタデータ」の節の前後に、`[source]` の節と値の優先の順を書く。
- docs/glossary.md の「原稿の記法」に「段落の区切り方」の項目を加える。

## 実装しないこと

- 改行の様式で、空行を空きとして残すこと。AST に空行の数を持たせ、意味論 IR に空きのブロックを加える必要がある。行の空きは、アキの指定（[仕様書](../specifications.md)の「v1 の実装で次の段階以降に回した項目」）と合わせて別の ADR で扱う。
- 改行の様式で、一つの段落を複数の行に折り返して書く記法（行末の記号による継続など）。行末の `\` は、段落一般の強制改行（[docs/adr/0003](0003-verse-line-breaks.md) が後に回した項目）に残しておく。`\` の後の改行を継続の意味にすると、エスケープした文字を本文の文字にする規則と逆の意味になり、強制改行と両立しないためである。
- 二つの様式のあいだで原稿を書き換える機能（`golem fmt` の変換など）。
- `golem new` の雛形に `[source]` を書くこと。`--language ja` でも既定の空行の様式のままとする。
- 一つのファイルの中で様式を切り替えること。ファイルより細かい単位では、本体を持つ `@style` と段落スタイルで足りる。
- 属性のまとまりと後ろのブロックのあいだに空行が要る場合の扱い（`@set` の行の直後に段落を書くと G0211 になるなど）。様式によらない今の規則であり、変えない。

## テスト設計

先に書き、失敗させてから実装する。

### golem-parser

- `sourceKeys` の `paragraph-separator` が、`"line"` で `LineSeparated`、`"blank-line"` で `BlankLineSeparated` を設定し、`"Line"` と `"lines"` で誤りを返すこと。

### golem-project（`test/Main.hs`）

- `[source]` のないマニフェストの `manifestSource` が `defaultSourceSettings` であること。
- `[source] paragraph-separator = "line"` を読むこと。`"lines"` と、`[source]` の未知のキーが G0301 になること。
- 章の項目 `{ file = "b.gm", paragraph-separator = "blank-line" }` と `[source] paragraph-separator = "line"` で、`projectSourceSettings` の `b.gm` が `BlankLineSeparated`、ほかの章と `@import` でだけ参照されるファイルが `LineSeparated` になること。
- 同じファイルを二つの項目に並べ、`paragraph-separator` の値を変えると G0301 になること。

### golem-eval（`test/FileSpec.hs`）

`ctxSource` を改行の様式にした文脈と、空行の様式の文脈の両方で確かめる。

- `"a\nb\n"` が、改行の様式で二つの段落 `a` と `b`、空行の様式で一つの段落 `ab` になること。
- `"a\n\n\nb\n"` が、どちらの様式でも二つの段落になること。
- 改行の様式で、`"a\n  b\n"` の二つ目の段落が `b`、`"a\n　b\n"` の二つ目の段落が `　b` になること。
- 改行の様式で、`"a\n%% c %%\nb\n"` が二つの段落になり、空の段落ができないこと。`"a %% x\ny %% b\n"` が一つの段落になること。
- 改行の様式で、`"[note: x\ny] z\nw\n"` の一つ目の段落の注の本文が `xy` であり、二つ目の段落が `w` であること。
- 改行の様式で、`"@label p\na\nb\n"` のラベル `p` が段落 `a` にだけ付くこと。
- 改行の様式で、`"@style verse\na\nb\n"` が `LineBreak` で二行をつないだ一つの段落になること。`"@style verse\n  a\n  b\n\n  c\n"` が二つの段落（二行と一行）になること。
- 改行の様式で、`"@style quote\n  a\n  b\n"` が `quote` の二つの段落になること（`ctxParaStyles` に `quote` を `join` で入れる）。
- 改行の様式で、`"- a\n  b\n"` の項目が二つの段落を持つこと。
- `"a\n# h\nb\n"` が、どちらの様式でも段落、見出し、段落の三つのブロックになること。
- 改行の様式で、`"@figure x.png alt=a\n  c1\n  c2\n"` のキャプションが二つの段落になること。
- `erSource` が `ctxSource` と一致すること。

### golem-lint（`test/Main.hs`）

- 改行の様式で、`"Full fathom\nfive\n"` に G0501 が出ないこと。空行の様式では出ること。
- 改行の様式で、`"[note: a\nb] x\n"` の散文スロットの中の改行に G0501 が出ること。

### golem-driver（`test/Main.hs`）

作業用のディレクトリに、`[source] paragraph-separator = "line"` の章と、章の項目で `blank-line` にした章を持つプロジェクトを作る。

- 改行の様式の章で、改行ひとつで区切った三行が HTML の三つの `<p>` になること。
- 空行の様式の章で、改行でつないだ二行が一つの `<p>` になること。
- 既存の golden と、`scripts/determinism.sh` の sample の各ファイルのハッシュが、この ADR の前と変わらないこと。

### golem-lsp（`test/Main.hs`）

- `[source] paragraph-separator = "line"` のプロジェクトで、欧文の二行を改行ひとつで書いたファイルに G0501 の診断が出ないこと。

### 変換スクリプトと fixture

自動テストにはしない。
実装の後で、次を確かめる。

- 作り直した `kanikosen.gm` に、本文の段落のあいだの空行がなく、`golem fmt --check` が通ること。
- `kanikosen` の HTML とプレーンテキストの出力が、作り直す前の fixture（空行の様式）の出力とバイト単位で一致すること。様式を変えても意味論 IR が変わらないことの確認である。

## トレードオフ

評価の層で段落を分けるので、CST と AST の段落は、改行の様式では出力の段落と一致しない。
`A.Paragraph` 一つが、評価の後に複数の段落になる。
LSP のアウトラインや出現位置の収集のように AST を読む機能は、段落を単位にしていないので影響はないが、今後 AST の段落を単位にする機能を作るときは、様式を考慮する必要がある。
代わりに、構文解析、整形、構文の診断が、マニフェストを知らずに済む。

改行の様式では、空行が意味を持たない。
青空文庫の原典のように、空行で場面の切り替えを表す原稿は、その空きを失う。
空きを残すには AST と意味論 IR の両方を変える必要があり、アキの指定の設計と切り離して決めると、空きの量を指定する手段が二つできるおそれがある。

改行の様式では、長い段落を一行で書くことになる。
エディタの折り返し表示に頼る書き方であり、差分の単位も段落になる。
和文の原稿はもともとこの形で書かれることが多いので、受け入れる。

[docs/adr/0005](0005-character-and-paragraph-styles.md) の `keep` の段落は、様式によらず改行を行の区切りにする。
`@style verse` の属性の形では、改行の様式でも直後の段落の全体が一つの韻文の連になり、一行ではない。
属性は直後の一行に付くという規則の例外になるが、韻文を属性の形で書けなくなるよりよい。
