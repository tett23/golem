# ADR 0006: プロジェクトの段階の診断のコード G0301 から G0309 を定める

ステータス: 採択→toml-parser の文言の扱いは [ADR 0007](0007-toml-messages-in-japanese.md)、G0305 の経路が空の分岐は [ADR 0027](../../adr/0027-exhaustive-command-dispatch-by-types.md)、Golem の文言の誤りと読み込んだ後の検査の位置は [ADR 0008](0008-style-toml-value-positions.md)、未知の判型の G0306 から G0317 への移動は [ADR 0005](0005-page-size-by-dimensions.md)

## 文脈

[docs/diagnostics.md](../../diagnostics.md) は、ソースが出す診断のコードをすべて載せている。
そのうち G0301、G0302、G0303、G0304、G0305、G0306、G0307、G0309 は「ADR なし」である。
条件の一部は [golem-project ADR 0001](0001-manifest-and-import-graph.md) と [golem-project ADR 0002](0002-style-toml.md) が決めたが、どちらもコードの番号を割り当てていない。
G0306 に条件を加えた ADR は多いが、G0306 そのものを定めた ADR はない。
番号は [golem-syntax ADR 0001](../../golem-syntax/adr/0001-source-spans-and-diagnostics.md) の区分に従い、上 2 桁の 03 がプロジェクトの段階を表す。

この ADR は、これらのコードの今の振る舞いを、ソースを読んで確かめたとおりに追認する。
あわせて、読む中で見つけた次の問題に、それぞれ決定を与える。

- **一つのコードに二つの条件**：G0302 は、プロジェクトのルートに `manifest.toml` がないときと、章や `@import` が指すファイルがないときの両方に使っている。
  前者はプロジェクトそのものが見つからない誤りであり、後者は参照の誤りである。
  直し方が違う。
- **位置が表示されない**：`Golem.Driver.build` は、`evaluateProject` が `Left` を返すと、`brSources` を空にして診断を返す。
  `loadProjectWith` と `loadStyle` の失敗はすべてこの経路を通るので、G0301 から G0306 と G0309 は、CLI では `<unknown>:?:?` と表示される。
  TOML のスキーマの誤りは行と桁を持つのに、それが利用者に届かない。
  LSP は、プロジェクトの誤り（`wsProjectErrors`）をすべて `manifest.toml` に載せるので、原稿の `@import` の G0302 や `style.toml` の G0306 が `manifest.toml` の別の位置に出る。
- **大文字と小文字の検査がファイルシステムで変わる**：G0304 は、シンボリックリンクを解決した後のパスを比べる。
  大文字と小文字を区別しないファイルシステムでは、`Common.gm` と `common.gm` が同じ実体に解決され、衝突として検出されない。
  [golem-project ADR 0001](0001-manifest-and-import-graph.md) は「どの環境でも同じエラーになるほう」を選んだが、実装はそうなっていない。
  テスト（`modules/golem-project/test/Main.hs` の「error or single file」）も、どちらの結果も許している。
- **同じ診断が重なる**：G0307 は、存在しないマスターページを指す章の項目ごとに一つ出す。
  どれも `manifest.toml` の先頭を指し、文言も同じなので、同じ名前を三つの章で使うと、同じ行が三つ並ぶ。
- **G0309 の二重の検査**：`Golem.Project.Imports.importsOf` と `Golem.Eval.File.standalone` が、同じ文言の G0309 を別々の条件で出す。
  前者はパスに語か文字列だけを認め、後者は任意の位置引数を認める。
  プロジェクトのビルドでは前者が先に止めるので、後者は出ない。
  後者が出るのは、LSP がプロジェクトの外のファイル（`Golem.Lsp.Workspace.loose`）を評価するときである。
- **英語の文言**：G0301 と G0306 のスキーマの誤りは、toml-parser の文言（`unexpected key: foo (.page)` など）をそのまま出す。
  Golem が自分で書いた `fail` と `typeError` の文言にも英語が残っている（`column-gap is required when columns > 1` など）。
  ほかのコードの文言は日本語である。
  経路が空のときは `missing key: metadata ()` のように空の括弧が出る。
- **到達しない分岐**：`Style` の `FromValue` の `[emphasis] は廃止しました` と `[verse] は廃止しました` の `fail` は、`EmphasisV` と `VerseV` の `fromValue` が先に必ず失敗するので、実行されない。
  G0305 の経路が空の分岐（`mkSpan (FileId 0) 0 0`）も、`findCycles` が空の経路を返さないので実行されない。
- **テストのないコード**：G0307 にはテストがない。
  G0301 の「出力ターゲットが一つもありません」と TOML の構文の誤り、G0306 の TOML の構文の誤り、G0309 にもテストがない。

提案中の ADR が `style.toml` の欄ごとに加える誤りは、G0306 ではなく別のコードにする（G0317 判型、G0318 マスターページの位置、G0319 廃止した欄、G0320 アキの量、G0321 文字の送りの欄、G0322 リストの書式）。この ADR は、今の G0306 の振る舞いだけを定める。
この ADR は今の振る舞いだけを定め、それらの提案が加える条件には立ち入らない。

## 実装すること

### 今の振る舞いの追認

以下は、すでに実装されている振る舞いである。
重大度はすべてエラーであり、プロファイル（dev と prod）で変わらない。
どのコードも `Golem.Syntax.Diagnostic.profileDependentCodes` に含めない。

診断の順序は、検査の順序に従う。
プロジェクトの読み込み（`Golem.Project.loadProjectWith`）は、次の順に進み、誤りを見つけた段で止まる。

1. `manifest.toml` の有無（G0302、下の変更で G0316）。
2. `manifest.toml` の読み込み（`Golem.Parser.Read.readSource` の G0101 から G0103）と、スキーマの照合（G0301）。
3. 章のパスの解決（G0302、G0303、G0304）。
  最初の誤りで止まる。
4. 章から `@import` をたどる幅優先の走査。
  ファイルごとに、`@import` の形（G0309）、パスの解決（G0302、G0303）、大文字と小文字の衝突（G0304）の順に調べ、誤りがあればそのファイルの誤りをすべて返して止まる。
5. 循環の検出（G0305）。
  循環ごとに一つ出す。

その後、`Golem.Driver.evaluateProjectWith` が `style.toml` を読み（G0306）、原稿に構文の誤りがなければ、マスターページの参照を調べる（G0307）。

#### G0301

**モジュール**：golem-project の `Golem.Project.Manifest.parseManifest`

| 条件 | メッセージ | 位置 |
| --- | --- | --- |
| `manifest.toml` が TOML として読めない | `TOML の誤りです: <toml-parser の文言>`（文言は `行:桁: ` で始まる） | `manifest.toml` の先頭 |
| スキーマに合わない（必須のキーがない、未知のキーがある、値の型が違う、章の項目がパスでも表でも配列でもない） | `<toml-parser または Golem の文言> (<経路>)`。経路は `.targets.html` や `.chapters[0]` のような、誤った値までのキーと添字 | 誤った値の位置（toml-parser が位置を返さないときは先頭） |
| `[targets]` があるが、`html`、`epub`、`pdf`、`text` のどれも有効でない（`[targets]` が空、または `[targets.text]` の `variants` が空） | `出力ターゲットが一つもありません` | `manifest.toml` の先頭 |

- 未知のキーは、toml-parser では警告であるが、`decodeStrict` がエラーに変える。
- `[targets]` がないときは、HTML だけを出力する既定値になり、G0301 は出ない。
- スキーマの誤りは、一度の照合で見つかったものをすべて出す。

#### G0302

**モジュール**：golem-project の `Golem.Project`

| 条件 | メッセージ | 位置 |
| --- | --- | --- |
| プロジェクトのルートに `manifest.toml` がない | `manifest.toml がありません` | `manifest.toml` の FileId の先頭（ファイルはない） |
| 章のパスを正規化した結果のファイルがない | `ファイルがありません: <書いたパス>` | `manifest.toml` の先頭 |
| `@import` のパスを正規化した結果のファイルがない | `ファイルがありません: <書いたパス>` | その `@import` のブロック全体 |

一つ目の条件は、下の変更で G0316 に移す。

#### G0303

**モジュール**：golem-project の `Golem.Project`（パスの判定は `Golem.Project.Paths.resolveInRoot`）

章と `@import` のパスについて、次の順に判定する。
位置は G0302 と同じく、章なら `manifest.toml` の先頭、`@import` ならそのブロック全体である。

| 条件 | メッセージ |
| --- | --- |
| パスが `://` を含む | `URL は使えません: <書いたパス>` |
| パスが `/` で始まる | `絶対パスは使えません: <書いたパス>` |
| `.` と `..` を字句の上で畳むと、ルートより上に出る | `プロジェクトルートの外を指しています: <書いたパス>` |
| ファイルはあるが、シンボリックリンクを解決した実体がルートの外にある | `プロジェクトルートの外を指しています: <書いたパス>` |

字句の上でルートの外に出るパスは、ファイルの有無を調べる前に G0303 になる。
字句の上で中に収まるパスは、ファイルがなければ G0302 になり、リンクの先は調べない。

#### G0304

**モジュール**：golem-project の `Golem.Project`

**条件**：解決したパス（ルートからの相対パス、区切りは `/`）を英小文字に畳んだものが、すでに登録したパスと一致し、元の綴りは異なる。
章は `manifest.toml` の順に、`@import` は走査の順に登録する。

**メッセージ**：`大文字と小文字だけが異なるパスです: <後のパス> と <先のパス>`

**位置**：章なら `manifest.toml` の先頭、`@import` ならそのブロック全体。

#### G0305

**モジュール**：golem-project の `Golem.Project`（検出は `Golem.Project.Imports.findCycles`）

**条件**：`@import` のグラフに循環がある。
自分自身の import は長さ 1 の循環である。
深さ優先の探索で見つけた後退辺ごとに、循環を一つ出す。

**メッセージ**：`import が循環しています: <ファイル> → <ファイル> → ... → <最初のファイル>`

**位置**：循環の最初のファイルにある `@import` のブロック全体。
関連位置に、循環に含まれる各 `@import` のブロックを `@import <パス>` の文言で載せる。

#### G0306

**モジュール**：golem-project の `Golem.Project.Style.parseStyle`

`style.toml` がないときは既定のスタイルを使い、G0306 は出ない。
`style.toml` の FileId は、プロジェクトのファイル表の項目数（どのファイルとも重ならない番号）である（`Golem.Driver.Pdf.styleFileId`）。

| 条件 | メッセージ | 位置 |
| --- | --- | --- |
| TOML として読めない | `TOML の誤りです: <toml-parser の文言>` | `style.toml` の先頭 |
| スキーマに合わない（未知のキー、値の型の違い、列挙にない値、廃止した欄、Golem が値の読み込みで調べる範囲） | `<toml-parser または Golem の文言> (<経路>)` | 誤った値の位置 |
| 読み込んだ後の検査に通らない | 下の表の文言 | `style.toml` の先頭 |

読み込んだ後の検査（`parseStyle` の `checks`）は次のとおりである。

| 条件 | メッセージ |
| --- | --- |
| `[figures] number` か見出しの `number` に、`{n}`、`{n:kanji}`、`{1}`、`{2}`、`{chapter}` 以外の差し込みがあるか、`{` が閉じていない | `番号の書式が不正です: <書式>` |
| 文字スタイルか段落スタイルの名前が、英小文字で始まり英小文字、数字、`-` だけからなる形でない | `スタイルの名前は英小文字で始まり、英小文字、数字、- だけからなります: <名前>` |
| `[composition] explicit-hyphen-penalty` が -9999 から 10000 の外 | `explicit-hyphen-penalty は -9999 から 10000 までです: <値>` |
| `[composition.ruby] overhang` が負 | `ルビのかけの量は 0 以上です（[composition.ruby] の overhang）` |
| `[page] size` が既知の判型の名前でなく、`x` も含まない | `未知の判型です: <判型>` |

読み込みの段で Golem が出す文言は次のとおりである（今の文言のまま）。

| 条件 | 今の文言 |
| --- | --- |
| 列挙のキーに許されない値 | `unknown value <値> for <キー>` |
| `columns` が 2 以上で `column-gap` がない | `column-gap is required when columns > 1` |
| `[page] bleed` に `zw` を使った | `塗り足しには zw を使えません` |
| 段落スタイルの `space-between` が負 | `space-between must be 0 or more` |
| 段落スタイルの `first-line-indent` が符号つきの長さとして読めない | `dimension such as 1zw or -1zw: <値>` |
| 長さが長さとして読めない | `expected dimension such as 13Q or 20mm but got <型>`（`typeError`） |
| 長さが文字列でない | `expected dimension string but got <型>`（`typeError`） |
| スウォッチの `cmyk` が 0 から 100 の整数四つでない | `cmyk must be four integers from 0 to 100` |
| 見出しの段が 1、2、3 以外 | `heading level must be 1, 2 or 3: <段>` |
| `[sidenotes]` に `font` か `size` がある | `[sidenotes] の font と size は廃止しました。[paragraph-styles.sidenote] の font と size に書き換えます` |
| `[emphasis]` がある | `[emphasis] は廃止しました。` で始まり、書き換え先を示す文言 |
| `[verse]` がある | `[verse] は廃止しました。` で始まり、書き換え先を示す文言 |

G0306 は、ファイルの欠落には使わない（[golem-project ADR 0004](0004-font-file-check-per-target.md)）。
フォントの役割の参照（G0308）、スタイルの参照（G0313）、文字の大きさ（G0311）、字下げ（G0312）は、この ADR の範囲の外である。

#### G0307

**モジュール**：golem-driver の `Golem.Driver.evaluateProjectWith`

**条件**：`manifest.toml` の章の項目 `{ file = ..., master = <名前> }` の `<名前>` が、`style.toml` の `[masters]` のキーにない。
`style.toml` がないときは `[masters]` が空なので、`master` を書いた項目はすべて該当する。
この検査は、`style.toml` の読み込みに成功し、原稿に構文の誤りがないときだけ行う。
構文の誤りがあれば、ビルドは構文の誤りだけを報告して止まる。

**メッセージ**：`style.toml にないマスターページです: <名前>`

**位置**：`manifest.toml` の先頭。

段階の番号が 03 なのは、マスターページの参照が `manifest.toml` と `style.toml` のあいだの整合性だからである。
検査を golem-driver で行うのは、二つのファイルを両方読むのが golem-driver だからである。
この配置は変えない。

#### G0309

**モジュール**：golem-project の `Golem.Project.Imports.importsOf`、golem-eval の `Golem.Eval.File.standalone`

**条件**（golem-project）：ブロックのコマンド `@import` の引数が、ちょうど三つの位置引数「語か文字列」「語 `as`」「語」の並びでない。
キーワード引数、展開、式の引数、コマンドの引数、引数の数の違いは、すべて該当する。
属性としてまとめたブロックのコマンドの中の `@import` も調べる。

**条件**（golem-eval）：引数が、三つの位置引数で、二つ目が語 `as`、三つ目が語である並びでない。
一つ目の種類は問わない。

**メッセージ**：`@import は「@import パス as 名前空間」の形で書きます`

**位置**：その `@import` のブロック全体。

### 変更

#### G0302 を分け、`manifest.toml` の欠落を G0316 にする

- `manifest.toml` がプロジェクトのルートにないときのコードを、G0302 から **G0316** に変える。
  メッセージは `manifest.toml がありません` のまま変えない。
- G0302 は、章と `@import` が指すファイルがないときだけに使う。
- G0316 を選んだのは、G0314 と G0315 が提案中の ADR に予約されているからである。
- [docs/diagnostics.md](../../diagnostics.md) に G0316 の節を加え、G0302 の節から一つ目の条件を除く。
  G0316 の節の ADR の欄にはこの ADR を書く。

#### 失敗した読み込みでも位置を表示する

- `Golem.Project.loadProjectWith` の失敗は、診断とともに、それまでに登録したファイルの `SourceInfo`（パスと行の索引）を返す。
  登録したファイルは、`manifest.toml`（存在するとき）と、読み込んだ原稿である。
  型は `Either ProjectFailure Project` とし、`ProjectFailure` は `pfDiagnostics :: [Diagnostic]` と `pfSources :: Map FileId SourceInfo` を持つレコードとする。
- `Golem.Driver.evaluateProjectWith` の失敗も `ProjectFailure` を返す。
  `style.toml` の読み込みに失敗したときは、プロジェクトの `SourceInfo` に `style.toml` の `SourceInfo` を加える。
- `Golem.Driver.build` は、失敗のときも `pfSources` を `brSources` に入れる。
  CLI は、G0301 から G0306 と G0309 を `manifest.toml:3:1:` や `a.gm:1:1:` の形で表示する。
- ソースの読み込み（`readSource`）の失敗は、提案中の [golem-parser ADR 0009](../../golem-parser/adr/0009-syntax-diagnostic-codes.md) の `ReadFailure` が別の型で表す。`ProjectFailure` は設定の誤りの失敗を表し、両方を実装したときは `ReadFailure` の `rfSources` と `rfDiagnostics` を `pfSources` と `pfDiagnostics` に合わせる。どちらの ADR も、他方の採否に依らずに実装できる。
- LSP（`Golem.Lsp.Workspace.diagnosticsFor`）は、プロジェクトの誤りを、診断の位置の FileId が `pfSources` で指すファイルに載せる。
  `pfSources` にない FileId の診断（G0316 など）は、これまでどおり `manifest.toml` に載せる。

#### G0304 を書いたパスでも調べる

- 衝突の検査に、シンボリックリンクを解決する前のパス（`normalizeRelative` の結果）も使う。
  書いたパスを英小文字に畳んだものが、すでに登録した書いたパスと一致し、元の綴りが異なれば、G0304 とする。
- これにより、大文字と小文字を区別しないファイルシステムでも、区別するファイルシステムでも、`Common.gm` と `common.gm` の参照は G0304 になる。
- メッセージの二つのパスは、書いたパスとする。
- 解決した後のパスによる今の検査は残す。
  区別するファイルシステムで、別々の綴りのリンクが大文字と小文字だけ異なる実体を指す場合を拾うためである。

#### G0307 を名前ごとに一つにする

- 存在しないマスターページの名前ごとに、G0307 を一つだけ出す。
  順序は、`manifest.toml` の章の順で名前が最初に現れた順とする。

#### G0309 の条件を一つにする

- `Golem.Project.Imports` に、引数の並びから `ImportSite` か G0309 の診断を作る関数 `importSite :: SrcSpan -> [Argument] -> Either Diagnostic ImportSite` を公開する。
  `importsOf` はこれを使う。
- `Golem.Eval.File.standalone` の `@import` は、この関数で引数を判定する。
  golem-eval はすでに golem-project に依存しているので、依存は増えない。
- これにより、プロジェクトの外のファイル（LSP の `loose`）でも、式やコマンドをパスに書いた `@import` は G0309 になる。
- golem-eval の G0309 は残す。
  プロジェクトの外のファイルは golem-project の走査を通らないからである。
  プロジェクトのビルドでは golem-project が先に止めるので、同じ `@import` に G0309 が二つ出ることはない。

#### Golem が書いた文言を日本語にする

G0301 と G0306 の文言のうち、Golem のソースが書いている英語の文言を、次の日本語に変える。

| 今の文言 | 新しい文言 |
| --- | --- |
| `unknown value <値> for <キー>` | `<キー> に使えない値です: <値>（<許す値をカンマと空白で区切った一覧> のどれか）` |
| `column-gap is required when columns > 1` | `columns が 2 以上のときは column-gap が要ります` |
| `space-between must be 0 or more` | `space-between は 0 以上です` |
| `dimension such as 1zw or -1zw: <値>` | `長さの書き方が不正です: <値>（1zw や -1zw のように書きます）` |
| `typeError "dimension such as 13Q or 20mm"` | `長さの書き方が不正です: <値>（13Q や 20mm のように書きます）`（`fail` で出す） |
| `typeError "dimension string"` | `長さは文字列で書きます`（`fail` で出す） |
| `cmyk must be four integers from 0 to 100` | `cmyk は 0 から 100 までの整数四つです` |
| `heading level must be 1, 2 or 3: <段>` | `見出しの段は 1、2、3 のどれかです: <段>` |
| `typeError "file path, table or array"`（`manifest.toml` の章） | `章は、ファイルのパス、表、配列のどれかで書きます`（`fail` で出す） |

- toml-parser 自身の文言（`missing key`、`unexpected key`、`expected ... but got ...`）は変えない。
- `tomlDiagnostics` は、経路が空のとき、` (<経路>)` の部分を付けない。

#### 到達しない分岐を除く

- `Style` の `FromValue` から、`when (isJust retiredEmphasis) $ fail "[emphasis] は廃止しました"` と `when (isJust retiredVerse) $ fail "[verse] は廃止しました"` を除く。
  `EmphasisV` と `VerseV` の `fromValue` が書き換え先を示す文言で失敗するので、振る舞いは変わらない。
- G0305 の経路が空の分岐は残す。
  `cycleDiagnostic` を全域関数に保つためであり、位置の FileId 0 は `manifest.toml` である。

#### 文書

- [docs/diagnostics.md](../../diagnostics.md) の G0301 から G0307、G0309、G0316 の節の ADR の欄に、この ADR を書く。
  文言を変えたコードは、メッセージの欄も直す。
- `docs/specifications.md` の診断のコードに触れる箇所があれば、G0316 を加える。

## 実装しないこと

- 章の項目、`[masters]` の参照、読み込んだ後の検査の誤りを、`manifest.toml` や `style.toml` の該当する行で指すこと。
  `Manifest` と `Style` は値の位置を持たないので、位置を持たせる型の変更が要る。
  この ADR では、位置をファイルの先頭のままにする。
- TOML の構文の誤りの位置を、toml-parser の文言の `行:桁` から取り出すこと。
  文言の形は toml-parser の版で変わりうる。
- toml-parser 自身の文言の翻訳。
- 大文字と小文字だけが実体と異なる綴りで、ファイルを一つだけ参照すること（`a.gm` を `A.gm` と書く）の検出。
  区別しないファイルシステムでは通り、区別するファイルシステムでは G0302 になる。
  検出にはディレクトリの一覧と綴りを比べる必要がある。
- G0307 の検査を、構文の誤りがあるときにも行うこと。
- G0306 の条件の追加。
  提案中の golem-driver の 0014 番と golem-project の 0005 番の ADR が、それぞれ扱う。

## テスト設計

### すでにあるテスト

`modules/golem-project/test/Main.hs` に次のテストがある。

- **G0301**：未知の節 `[extra]` と、`[targets.pdf]` の未知のキー `marks`。
- **G0302**：章のファイルがない。
- **G0303**：`@import ../x.gm`（ルートの外）と `@import "https://e.com/x.gm"`（URL）。
- **G0304**：`Common.gm` と `common.gm`。
  区別しないファイルシステムでは成功も許している。
- **G0305**：長さ 2 の循環と自分自身の import。
- **G0306**：未知のキー、列挙にない値、範囲外の CMYK、不正な番号の書式、廃止した欄、ルビの値、`bleed` の `zw` など。

G0307 と G0309 のテストはない。

### 加えるテスト

先に次のテストを書き、変更の部分が失敗することを確かめてから実装する。

`modules/golem-project/test/Main.hs`：

- `manifest.toml` のないルートで、`loadProject` のコードが `["G0316"]` で、メッセージが `manifest.toml がありません` であることを確かめる。
- `@import nope.gm as x` の G0302 の位置が、その `@import` の行であることを確かめる。
- `@import /abs.gm as x` が G0303 で `絶対パスは使えません: /abs.gm` であること、ルートの外へのシンボリックリンクが G0303 であることを確かめる。
- `Common.gm` と `common.gm` のテストを、コードが `["G0304"]` であることの厳密な検査に変える。
  メッセージが `大文字と小文字だけが異なるパスです: common.gm と Common.gm` であることも確かめる。
- 長さ 3 の循環で、メッセージが三つのファイルと最初のファイルを ` → ` でつなぎ、関連位置が三つあることを確かめる。
- `[targets]` が空の `manifest.toml` が G0301 で `出力ターゲットが一つもありません` であることを確かめる。
- `manifest.toml` の TOML の構文の誤りが G0301 で、メッセージが `TOML の誤りです: ` で始まることを確かめる。
- `[metadata]` のない `manifest.toml` のメッセージが `missing key: metadata` で終わり、` ()` を含まないことを確かめる。
- `@import x.gm`、`@import x.gm as`、`@import [= 1] as x`、`@import x.gm as x extra` が、それぞれ G0309 であることを確かめる。
  属性としてまとめたブロックの中の `@import x.gm` も G0309 であることを確かめる。
- `parseStyle` で、TOML の構文の誤りが G0306 で `TOML の誤りです: ` で始まることを確かめる。
- `parseStyle` で、上の表の日本語の文言が出ることを確かめる（列挙の値、`column-gap`、`space-between`、`first-line-indent`、長さ、`cmyk`、見出しの段）。
- `parseStyle` で、読み込んだ後の検査の五つの文言を一つずつ確かめる。

`modules/golem-eval/test/FileSpec.hs`：

- プロジェクトを通さずに `evalFile` で評価した `@import [= 1] as x` が G0309 になることを確かめる。
  今は G0309 にならないので、変更の前は失敗する。

`modules/golem-driver/test/Main.hs`：

- `{ file = "b.gm", master = "nope" }` と `{ file = "c.gm", master = "nope" }` を持つプロジェクトで、G0307 がちょうど一つ出て、メッセージが `style.toml にないマスターページです: nope` であることを確かめる。
- `style.toml` の `[masters.body]` を指す項目では G0307 が出ないことを確かめる。
- 原稿に構文の誤りがあるとき、G0307 が出ないことを確かめる。
- `style.toml` の未知のキーで `build` が失敗したとき、`brSources` に `style.toml` の `SourceInfo` があり、`renderHuman` の出力が `style.toml:` で始まることを確かめる。
- 章のファイルがないとき、`renderHuman` の出力が `manifest.toml:1:1:` で始まることを確かめる。

`modules/golem-lsp/test/Main.hs`：

- 原稿の `@import nope.gm as x` の G0302 が、`manifest.toml` ではなく、その原稿のファイルに載ることを確かめる。
- `style.toml` の未知のキーの G0306 が、`style.toml` に載ることを確かめる。

`modules/golem-cli/test/Main.hs` の、ソースのコードがすべて `docs/diagnostics.md` に載っていることのテストが、G0316 の節を求めることも確かめる。

## トレードオフ

G0302 を分けると、`manifest.toml` がないときに G0302 を前提にしていた利用者のスクリプトは動かなくなる。
まだ最初のリリースの前なので、コードの意味を一つに保つほうを選ぶ。

`ProjectFailure` を返すと、`loadProjectWith` と `evaluateProjectWith` の型が変わり、golem-driver、golem-lsp、golem-cli の呼び出し側を直す必要がある。
位置のない診断は直し方を探す手がかりを失うので、この手間を払う。

G0304 を書いたパスでも調べると、区別するファイルシステムで、大文字と小文字だけ異なる二つのファイルを意図して置くことはできなくなる。
これは [golem-project ADR 0001](0001-manifest-and-import-graph.md) がすでに選んだ制約であり、実装をそれに合わせる。

G0307 を名前ごとに一つにすると、どの章の項目が誤っているかは診断から読めなくなる。
位置がファイルの先頭である以上、同じ行を繰り返しても情報は増えないので、名前ごとに一つにする。

toml-parser の文言を英語のまま残すので、G0301 と G0306 の文言は日本語と英語が混ざる。
翻訳すると toml-parser の版が上がるたびに文言の対応を保つ必要があり、その手間に見合わない。

## 参考文献

なし
