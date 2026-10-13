# ADR 0004: style.toml が指すファイルの存在をターゲットごとに検査する

ステータス: 採択

## 文脈

`style.toml` は、フォントのファイル（`[fonts.<役割>]` の `ja` と `latin`）と、出力インテントの ICC プロファイル（`[color] intent`）をパスで指す。
[ADR 0002](0002-style-toml.md) は、これらのファイルがプロジェクトルートの中に存在しなければエラーとした。
この検査は `Golem.Project.Style.loadStyle` が行い、存在しないファイルを G0306 のエラーにする。

`loadStyle` は `Golem.Driver.evaluateProjectWith` の最初に呼ばれる。
`style.toml` の読み込みに失敗すると、評価はそこで止まり、どのターゲットも出力されない。
そのため、PDF しか使わないファイルが欠けているだけで、HTML、EPUB、プレーンテキストもビルドできない。

`golem new --no-fonts`（[golem-cli ADR 0003](../../golem-cli/adr/0003-new-project-page-and-fonts.md)）は、フォントを取得せずに、フォントのパスを書いた `style.toml` を作る。
このプロジェクトは、利用者がフォントを置くまで、`golem build --target html` も G0306 で失敗する。
`golem check` と `golem lint` も同じ評価を通るので、原稿の誤りを一つも報告できない。
LSP も同じ評価を使い（`Golem.Lsp.Workspace.fullEvaluate`）、評価に失敗すると `wsEvaluated` が `Nothing` になるので、原稿のファイルの診断を出さず、`manifest.toml` に G0306 を出すだけになる。

### ファイルを使うターゲット

コードで確かめた、各ターゲットとファイルの関係は次のとおりである。

| ターゲット | フォントのファイル | ICC プロファイル |
|---|---|---|
| PDF | 本文の役割と、見出しの `font`、`bold-font`、`italic-font`、文字スタイルの `font` が指す役割（`Golem.Driver.Pdf.usedRoles`）のファイルを読み、埋め込む | `Golem.Driver.Pdf.loadIntent` が読み、出力インテントとして埋め込む |
| HTML | `[fonts]` のすべての役割のファイルを `build/html/fonts/` に写し、`style.css` の `@font-face` で指す（`Golem.Html.renderXhtml` の `siteAssets` と `css`） | 使わない |
| EPUB | HTML と同じ `siteAssets` を `OEBPS/fonts/` に同梱し、`package.opf` に載せる（`Golem.Epub.writeEpub`） | 使わない |
| プレーンテキスト | 使わない | 使わない |

PDF は、使わない役割のファイルを読まない。
PDF の経路には、`usedRoles` のファイルが存在しない場合の G0802（`Golem.Driver.Fonts`）がすでにある。
ICC プロファイルは、`loadStyle` の検査を外すと、`loadIntent` の `BS.readFile` が例外で止まる。
HTML と EPUB も、存在しないフォントを `BS.readFile` で読もうとして例外で止まる。
したがって、`loadStyle` の検査を外すだけでは足りず、各ターゲットが自分の使うファイルを検査する必要がある。

## 実装すること

### 方針

- `style.toml` の読み込み（`loadStyle`）は、ファイルの存在を検査しない。TOML の構文、未知のキー、値の範囲、役割の参照（G0308）など、ファイルシステムを見ない検査はこれまでどおりすべてのターゲットで行う。
- ファイルの存在は、出力の前に、そのファイルを使うターゲットについてだけ検査する。
- PDF が使うファイルの欠落はエラーとする。PDF はフォントがなければ一字も組めず、ICC プロファイルがなければ PDF/X-4 にならないためである。
- HTML と EPUB が使うフォントの欠落は、dev のプロファイルでは警告とし、prod のプロファイルではエラーとする。欠けたフォントは同梱せず、`@font-face` も書かない。ブラウザーは `font-family` の並びの残り（最後は `serif`）で組むので、出力は読める。
- プレーンテキストはファイルを検査しない。

### 診断のコード

| コード | 重大度 | 意味 | 出すターゲット |
|---|---|---|---|
| G0306 | エラー | `style.toml` の内容の誤り（これまでどおり）。ファイルの欠落には使わない | すべて |
| G0802 | エラー | PDF が使う役割のフォントのファイルがない（今の意味のまま） | PDF |
| G0806 | エラー | 出力インテントの ICC プロファイルのファイルがない（新設） | PDF |
| G0310 | dev は警告、prod はエラー | HTML と EPUB に同梱するフォントのファイルがない（新設） | HTML、EPUB |

- G0310 は、`style.toml` が指すファイルの検査なのでプロジェクトの段階（03）の番号とする。G0301 から G0309 は使用済みであり、G0310 は空いている。
- G0806 は、ICC プロファイルを読むのが PDF の出力の段階なので、出力の段階（08）の番号とする。G0801 から G0805 は使用済みである。
- G0310 を `Golem.Syntax.Diagnostic.profileDependentCodes` に加える。重大度は G0310 を警告として作り、`adjustForProfile` が prod でエラーにする。
- 診断の位置は、今の G0306 と同じく `style.toml` の先頭（`mkSpan <style.toml の FileId> 0 0`）とする。メッセージにはパスを書く。G0802 は `フォントのファイルがありません: <パス>`、G0806 は `出力インテントの ICC プロファイルがありません: <パス>`、G0310 は `フォントのファイルがないので、HTML と EPUB に同梱しません: <パス>` とする。
- パスの形の誤り（絶対パス、URL、プロジェクトルートの外）も、存在しないファイルと同じコードで報告し、メッセージを `Golem.Project.pathDiagnostic` と同じ文言（`絶対パスは使えません` など）にする。今の `loadStyle` はパスの形を見ていないので、これは検査の追加である。
- 一つのパスを複数の役割が指す場合も、HTML と EPUB の両方を作る場合も、同じコードと同じパスの診断は一つだけ出す。

### golem-project

- `loadStyle` から存在の検査を外し、`loadStyle :: FileId -> Maybe Text -> Either [Diagnostic] Style` にする。`IO` と、存在を問い合わせる関数の引数がなくなる。
- `Golem.Project.Style` に次の関数を加える。

```haskell
-- | Font files named by [fonts]: role, then Japanese before Latin, roles in name order.
fontFiles :: Style -> [(Text, FilePath)]
```

- ICC プロファイルのパスは、今の `stIntent` をそのまま使う。

### golem-driver

`Golem.Driver` に、出力の前の検査を加える。

```haskell
-- | Files of style.toml that cannot be used: path -> why (resolveInRoot).
missingStyleFiles :: FilePath -> Style -> IO (Map FilePath PathError)

-- | Diagnostics of the missing files for one target (golem-project ADR 0004).
targetFileDiagnostics :: FileId -> Style -> Map FilePath PathError -> Target -> [Diagnostic]
```

- `missingStyleFiles` は、`fontFiles` のすべてのパスと `stIntent` を `Golem.Project.Paths.resolveInRoot` で解決し、失敗したものを集める。
- `targetFileDiagnostics` は、`TargetPdf` では `usedRoles` の役割のファイル（G0802）と `stIntent`（G0806）、`TargetHtml` と `TargetEpub` では `[fonts]` のすべての役割のファイル（G0310）、`TargetText` では何も返さない。`usedRoles` は `Golem.Driver.Pdf` から使う。
- `Evaluated` に `evStyleFile :: !FileId` を加え、`evaluateProjectWith` が今計算している `styleFid` を入れる。`loadStyle` の呼び出しを新しい型に合わせる。

`build` を次のように変える。

1. 評価の後、`missingStyleFiles` で欠けたファイルを集める。
2. 対象のターゲット（`fromMaybe (targetsOf manifest) (optTargets opts)`）ごとに `targetFileDiagnostics` を求め、`adjustForProfile` を通す。全ターゲットの診断を重複なく結果に加える。
3. `optCheckOnly` の場合は、ここまでの診断を返して終える。
4. そうでない場合、自分の診断にエラーがあるターゲットは書かない。PDF は G0802 か G0806 があれば `renderPdf` を呼ばない。HTML と EPUB は、prod で G0310 がエラーになった場合に書かない。
5. HTML と EPUB を書く場合は、`HtmlConfig` の `hcFonts` から欠けたファイルを `Nothing` にしてから `renderXhtml` に渡す。欠けたファイルは `siteAssets` にも `@font-face` にも現れず、`writeEpub` も読まない。golem-html と golem-epub は変えない。

`renderPdf` と `golemFontProvider` の G0802 は、`build` を通らない呼び出し（テストの `flowLines` など）のために残す。
`loadIntent` は、ファイルを読めない場合に例外ではなく G0806 を返すようにし、型を `IO (Either [Diagnostic] (Maybe P.PdfX))` にする。
`renderPdf` は、行分割と改ページの前に `loadIntent` を呼ぶ順に変え、欠けたプロファイルで組版の時間を使わないようにする。

### golem check

- golem-cli の `Check` は、`build` に `optTargets = Just allTargets` と `optCheckOnly = True` を渡す。`--target` を省いた `golem build` と同じターゲットを検査し、`golem check` が通れば `golem build` もファイルの欠落では失敗しないようにする。
- `golem check` は出力を書かないが、手順 2 の診断は出す。`--no-fonts` で作ったプロジェクトでは、G0310 の警告と G0802 のエラーを出し、終了コードは 1 になる。

### LSP と lint

- LSP と `golem lint` は `evaluateProjectWith` を使い、出力の前の検査を呼ばない。`loadStyle` が存在を検査しなくなるので、フォントがなくても評価が通り、原稿の診断と lint を出す。
- LSP は G0802、G0806、G0310 を出さない。LSP はターゲットを出力せず、どのターゲットを作るかを知らないためである。

### ドキュメント

- 仕様書の「v1 の実装で次の段階以降に回した項目」から「`--no-fonts` で作ったプロジェクトのビルド」を削る。
- 仕様書の `style.toml` の節に、ファイルの存在はそれを使うターゲットのビルドと `golem check` でだけ検査すること、HTML と EPUB では欠けたフォントを同梱せずに警告（prod ではエラー）とすること、PDF ではエラーとすることを書き、この ADR へのリンクを付ける。
- 仕様書の `golem check` の説明に、出力の前のファイルの検査も行うことを足す。
- README の `golem new --no-fonts` の説明に、フォントを置く前でも HTML、EPUB、プレーンテキストを作れることを足す。

## 実装しないこと

- 図版、表と `@listing` の取り込むファイル、参考文献のファイルの検査の変更。これらは原稿から参照され、評価の段階で扱う。
- 診断の位置を、`style.toml` の中のパスを書いたキーの位置にすること。`Style` はキーの位置を持たないので、今の G0306 と同じく先頭とする。
- HTML と EPUB で欠けたフォントの代わりに別のフォントを指定すること。CSS の並びの残りに任せる。
- `golem check --target`。`golem check` は常に四つのターゲットを検査する。
- LSP でファイルの欠落を報告すること。
- PDF の使わない役割のファイルの検査。PDF は読まないファイルを報告しない。HTML か EPUB を作れば G0310 として報告される。

## テスト設計

先に書いて失敗させるテストを並べる。

### golem-project（modules/golem-project/test/Main.hs）

- `[fonts.body] ja = "fonts/none.otf"` と `[color] intent = "icc/none.icc"` を含む `style.toml` を `loadStyle` で読むと、`Right` になること。今は G0306 になるので失敗する。
- `fontFiles` が、役割の名前の順に、和文、欧文の順でパスを返すこと（`[fonts.mono] latin = "m.otf"` と `[fonts.body] ja = "b.otf"`、`latin = "l.otf"` で `[("body", "b.otf"), ("body", "l.otf"), ("mono", "m.otf")]`）。

### golem-driver（modules/golem-driver/test/Main.hs）

`fixture`（`test/fixtures/sample`）を一時ディレクトリに写し、`style.toml` を `horizontalStyle` に `[fonts.body] ja = "fonts/missing.otf"` を足したものにする。
これを「欠けたプロジェクト」と呼ぶ。

- 欠けたプロジェクトで `evaluateProject` が `Right` を返すこと。
- `optTargets = Just [TargetHtml, TargetEpub, TargetText]` の `build` で、診断が G0310 の警告一つだけであり、HTML、EPUB、プレーンテキストのファイルが書かれること。`build/html/style.css` に `@font-face` がなく、`build/html/fonts/` が存在せず、EPUB の書庫に `OEBPS/fonts/` で始まる項目がないこと。
- `optTargets = Just [TargetPdf]` の `build` で、診断が G0802 のエラー一つだけであり、その位置が `style.toml` の `FileId` であること。PDF が書かれず、`countingFonts` の呼び出しが 0 回であること。
- `optTargets = Just [TargetText]` の `build` で、診断がないこと。
- `optProfile = Prod` と `optTargets = Just [TargetHtml]` の `build` で、G0310 がエラーになり、`build/html/` が書かれないこと。
- 本文の役割のファイルは存在し（`fakeFontFiles`）、`[fonts.mono] latin = "fonts/missing.otf"` が欠けている場合に、偽のフォントで PDF を作ると G0802 が出ないこと。同じプロジェクトで HTML を作ると G0310 が一つ出て、`style.css` に `golem-body-ja` の `@font-face` があり、`golem-mono-latin` の `@font-face` がないこと。
- `[color] intent = "icc/none.icc"` を足し、フォントは存在するプロジェクトで、PDF を作ると例外ではなく G0806 になり、HTML を作ると診断がないこと。
- 欠けたプロジェクトで `optCheckOnly = True` と `optTargets = Just allTargets` の `build` が、G0310 と G0802 を返し、`build/` に何も書かないこと。
- 一つのパスを二つの役割が指し、そのファイルが欠けている場合に、HTML と EPUB を作っても G0310 が一つだけであること。
- `createProject` を `--no-fonts` に当たる指定（取得の関数なし）で呼んだ雛形を `optTargets = Just allTargets` でビルドすると、HTML、EPUB、プレーンテキストが書かれ、診断が G0310 の警告と G0802 のエラーであること。言語ごと（`ja` と `en`）に確かめる。

### golem-cli（modules/golem-cli/test/Main.hs）

- 欠けたプロジェクトで `golem check` が終了コード 1 で終わり、標準エラー出力に G0802 と G0310 があること。
- 欠けたプロジェクトで `golem build --target html` が終了コード 0 で終わり、標準エラー出力に G0310 があること。

### golem-lsp（modules/golem-lsp/test/Main.hs）

- 欠けたプロジェクトで `fullEvaluate` の後の `wsEvaluated` が `Just` であり、原稿に置いた構文の誤りの診断が `diagnosticsFor` の原稿のファイルに出ること。`diagnosticsFor` に G0306、G0310、G0802 が現れないこと。

### 手で確かめること

実装の後に、`golem new --no-fonts` で日本語と英語のプロジェクトを作り、`golem build --target html --target epub --target text` が終了コード 0 で三つのターゲットを作ること、フォントを置いた後の `golem build` が終了コード 0 で四つのターゲットを作ることを確かめる。

## トレードオフ

`golem build --target html` は、フォントが欠けていても成功するようになる。
dev のプロファイルでは警告だけなので、フォントを置き忘れたまま、ブラウザーの既定の書体で組まれた HTML を作ってしまうことがある。
出荷する本は prod でビルドする前提とし、prod ではエラーにして止める。

`golem check` は、出力を書かないのにターゲットのファイルを検査する。
`golem check` は「`golem build` が通るか」を先に知るための命令と考え、評価の誤りだけでなく、ビルドを止める欠落も報告する。
その結果、`--no-fonts` で作った直後のプロジェクトでは、原稿に誤りがなくても `golem check` が失敗する。
PDF を作らない利用者には不要な失敗だが、`golem build` の既定が四つのターゲットであること（[golem-cli ADR 0002](../../golem-cli/adr/0002-build-all-targets-by-default.md)）に合わせる。

LSP はファイルの欠落を報告しないので、エディタだけを見ている利用者は、ビルドするまで欠落に気付かない。
代わりに、フォントがなくても原稿の診断が出るようになる。
今の LSP は、欠落があると原稿の診断を一つも出さないので、こちらのほうが失うものが少ない。

ファイルの存在の検査が `loadStyle` と `build` の二箇所に分かれず、`build` の一箇所に移る。
`evaluateProjectWith` だけを呼ぶ経路（LSP、lint、`golem inspect`）は、欠けたファイルを知らないまま進む。
これらはファイルを読まないので、問題にならない。
