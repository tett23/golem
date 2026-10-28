# ADR 0104: diagnostic の重大度 info を notice の下に設ける

ステータス: 採択（未実装）

## 文脈

diagnostic の重大度は、error、warning、notice の三つである（[`Severity`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-syntax/src/Golem/Syntax/Diagnostic.hs#L32)、[golem-syntax ADR 0002](../golem-syntax/adr/0002-notice-severity.md)）。
notice は「誤りではないが、書き手が知っておいたほうがよいこと」を伝える。
終了コードに影響せず、プロファイルで重大度が変わらず、出力のバイト列を変えない。
引用はすべて origin/main の 466884da のものである。

notice の中に、書き手が知らなくても困らないものが一つある。
段の先頭で捨てた行アキの G07047 である（[docs/adr/0046](0046-blank-line-command.md)）。
PDF で `@blank-line` が段の先頭に来ると、空きを取らずに捨て、捨てた `@blank-line` ごとに G07047 を出す（[`Golem.Driver.Pdf.Flow` の 501 行め](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L501)）。
[docs/adr/0046](0046-blank-line-command.md) は、これを「組版の通常の結果であり、書き手が直す必要があるとは限らない」とし、notice より下の info を設けたら移す予定だと書いた。
docs/diagnostics.md の G07047 の節の「直し方」も、最初の文が「捨ててよければ、そのままでよい」である。
場面の区切りに `@blank-line` を使う小説では、組むたびにどこかの段の先頭に来る。
そのたびに notice が出れば、ほかの notice が埋もれる。

notice を止める手段はあるが、info の代わりにはならない。
`silence-notices` はプロジェクトの全体でそのコードを止め（[golem-syntax ADR 0002](../golem-syntax/adr/0002-notice-severity.md)）、止めたコードはどの実行でも見えなくなる。
`--no-notices` はその実行のすべての notice を止める。
「ふだんは出さず、見たいときにだけ見る」という扱いは、どちらでも表せない。

開発者のマニュアルは、notice をログの水準の info と同じものと読まないよう注意し、「Golem には info に当たる重大度はない」と書いている（`manual-dev/part1/02-diagnostics.gm` の「重大度と notice」の節）。
info を設けるなら、この説明は改めることになる。

### 今の実装

- **重大度**：`data Severity = Error | Warning | Notice` であり、`Ord` で `Error < Warning < Notice` になる。notice のコードは [`noticeCodes`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-syntax/src/Golem/Syntax/Diagnostic.hs#L82-L105) の一箇所に並べ、G07047 もここにある。
- **プロファイル**：[`adjustForProfile`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-syntax/src/Golem/Syntax/Diagnostic.hs#L143-L147) は、[`profileDependentCodes`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-syntax/src/Golem/Syntax/Diagnostic.hs#L125-L130) のコードだけを、dev では warning、prod では error にする。
- **抑制**：[`silenceNotices`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-syntax/src/Golem/Syntax/Diagnostic.hs#L111-L114) は、重大度が `Notice` の diagnostic だけを落とす。`silence-notices` は `manifest.toml` の `[diagnostics]` の表に書く。[`silenceList`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-project/src/Golem/Project/Manifest.hs#L230-L240) は、要素ごとに、コードの形でない文字列、`noticeCodes` にないコード、文字列でない値をその要素の位置で報告し、[`manifestCode`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-project/src/Golem/Project/Manifest.hs#L246-L249) がそれを G03024 にする。`noticeCodes` にないコードのメッセージは `抑制できるのはお知らせのコードだけです: <コード>` である。
- **並び順**：[`sortDiagnostics`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-syntax/src/Golem/Syntax/Diagnostic.hs#L154-L167) の最初のキーは「notice か」であり、error と warning を先に、notice を後に並べる（[golem-syntax ADR 0003](../golem-syntax/adr/0003-diagnostic-order.md)）。
- **表示**：[`severityText`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-syntax/src/Golem/Syntax/Render.hs#L27-L30) が `error`、`warning`、`notice` を返し、人が読む形式（[`renderHuman`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-syntax/src/Golem/Syntax/Render.hs#L106-L107)）と JSON の形式（[`renderJson`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-syntax/src/Golem/Syntax/Render.hs#L168-L169) の `severity`）がこれを使う。
- **一覧の仕上げ**：`golem build` と `golem check` は golem-driver の [`finishWith`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-driver/src/Golem/Driver.hs#L632) で、`golem lint` は [`Golem.Driver.Lint`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-driver/src/Golem/Driver/Lint.hs#L31) で、プロファイル、抑制、並べ替えの順に一覧を仕上げる。`golem preflight` は、ビルドの一覧に検査の結果を足して並べ直す（[722 行め](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-driver/src/Golem/Driver.hs#L722)）。`golem inspect` は golem-cli の [app/Main.hs の 315 行め](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-cli/app/Main.hs#L315) で、`silence-notices` だけを当てる。
- **CLI**：`--no-notices` は `golem build`、`golem check`、`golem lint` だけにある（[app/Main.hs の 113〜114 行め](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-cli/app/Main.hs#L113-L114)）。`--verbose` を持つコマンドはない。短い形のオプションは `-h`（`--help`）だけであり、`--version` も短い形を持たない（[81〜87 行め](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-cli/app/Main.hs#L81-L87)）。
- **LSP**：[`lspSeverity`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-lsp/src/Golem/Lsp/Server.hs#L319-L326) は notice を `Information` に写す。LSP が公開するのは評価と lint の diagnostics であり、`silence-notices` を当ててから公開する（[`Golem.Lsp.Workspace` の 291〜292 行め](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-lsp/src/Golem/Lsp/Workspace.hs#L291-L292)）。PDF の組版をしないので、G07047 などのレイアウトの diagnostic は LSP に載らない。
- **説明の文書**：目録の重大度の値は `エラー`、`警告`、`dev では警告、prod ではエラー`、`お知らせ` と、プリフライトの設定によるもの（[`severities`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-driver/src/Golem/Driver/Explain/Catalog.hs#L39-L40)）。golem-driver のテストは、不正な重大度の例として `- 重大度: 情報` を使っている（[DiagnosticsSpec.hs の 317 行め](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-driver/test/DiagnosticsSpec.hs#L317)）。
- **notice が出力を変えないことの検査**：[`everyNoticeProjects`](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-driver/test/DiagnosticsSpec.hs#L117-L144) の二つのプロジェクトで、すべての notice を出す。テスト「no notice of noticeCodes changes the outputs of the four targets」（[203〜217 行め](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-driver/test/DiagnosticsSpec.hs#L203-L217)）は、出した notice のコードの集合が `noticeCodes` と等しいことと、`silence-notices` と `--no-notices` で出力のバイト列が変わらないことを確かめる。G07047 も、このプロジェクトの原稿の `@page-break` の直後の `@blank-line` で出る。
- **名前**：golem-cli の app/Main.hs は `Golem.Syntax` と `Options.Applicative` を修飾なしで import し、optparse-applicative の `info` を使う（[78 行め](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-cli/app/Main.hs#L78)、[174 行め](https://github.com/tett23/golem/blob/466884dab4f15f163e2f7eb4f572102af2dad300/modules/golem-cli/app/Main.hs#L174)）。golem-syntax が `notice` にならって `info` という関数を公開すると、この二箇所で名前が衝突する。

## 実装すること

### 重大度の追加

`Severity` に `Info` を加え、notice より下の重大度とする。
日本語の名前は「情報」、英語の表記は `info` とする。
使い手のマニュアルのロードマップの付録（`manual/appendices/h-roadmap.gm`）が、すでに「情報」（info）と書いている。

info は次の性質を持つ。

- `--verbose`（`-v`）を付けたときにだけ出す。付けなければ、その実行の diagnostics の一覧から落とす。
- 終了コードに影響しない。`isError` と `hasErrors` は変えない。
- プロファイルで重大度が変わらない。`profileDependentCodes` に info のコードを入れない。
- 出力を変えない。info を出すかどうかで、PDF、HTML、EPUB、プレーンテキストのバイト列は変わらない。`--verbose` の有無でも、`silence-info` の有無でも変わらない。
- lint の規則（G05xxx）、プラグイン、プリフライト（G09xxx）は info を出さない。lint は「ほぼ確実に誤りである記述」だけを扱い、プラグインの応答の重大度は 0（error）と 1（warning）だけを受け付け、プリフライトの設定で選べる重大度は error、warning、off である。どれも notice を出さない理由と同じである（[golem-syntax ADR 0002](../golem-syntax/adr/0002-notice-severity.md)）。

### notice と info の分け方

notice と info を分ける基準は、書き手がそれを知る必要があるかどうかである。

- **notice**：原稿か設定に理由があり、書き手が知っておいたほうがよいもの。効果のない書き方、廃止予定の書き方、書いた意図と違う結果になったものなど。
- **info**：組版の規則どおりに処理系が行ったことの記録で、書き手が知らなくても困らないもの。

迷うものは notice にする。
info はふだん見えないので、info にしたものを書き手が見落としても困らないと言い切れるものに限る。

### 一つのコードに一つの原因

一つのコードの重大度は一つに決まる。
同じコードが、場合によって notice になったり info になったりすることはない。
例外は今と同じく、`profileDependentCodes`（プロファイルで決まる）と `preflightCodes`（プリフライトの設定で決まる）だけである。
同じ現象に、知らせるべき場合と記録でよい場合があるなら、それは別々の原因なので、コードを分ける。

### info のコード

info のコードは、`Golem.Syntax.Diagnostic` の `infoCodes :: [DiagnosticCode]` の一箇所に並べる。
`noticeCodes` と同じ置き方である。
info を作る関数は `infoDiagnostic :: Text -> SrcSpan -> Text -> Diagnostic` とする。
`info` という名前は、golem-cli で optparse-applicative の `info` と衝突するので使わない。

最初の info は G07047 だけとする。

- G07047 を `noticeCodes` から外し、`infoCodes` に入れる。
- `Golem.Driver.Pdf.Flow` の G07047 を `notice` から `infoDiagnostic` に変える。メッセージと位置は変えない。
- コードは G07047 のまま変えない。原因（段の先頭に来た行アキを捨てた）が同じなので、新しいコードを割り当てない。重大度を変えることは、番号の使い回し（別の意味への再利用）に当たらない。

ほかの notice を info に移すかどうかは、この ADR では決めない。
コードごとに、上の基準に照らした判断が要るからである。

### --verbose と -v

- `golem build`、`golem check`、`golem lint` に `--verbose` と、その短い形の `-v` を設ける。`--no-notices` を持つコマンドと同じ組である。ヘルプの説明は `情報（info）の diagnostic も表示する` とする。
- `-v` は `--version` の短い形ではない。`--version` は今と同じく `golem` にだけ付けられ、短い形を持たない。
- `--verbose` が変えるのは、info を出すかどうかだけとする。進み具合のログなど、ほかの出力は加えない。
- `golem fmt`、`golem explain`、`golem inspect`、`golem preflight`、`golem new`、`golem plugin`、`golem lsp` は `--verbose` と `-v` を受け付けず、使い方の誤り（終了コード 2）とする。この中で diagnostic を出すコマンドは、info をつねに落とす。
- `--verbose` と `--no-notices` は互いに独立とする。両方を付けると、notice を出さず、info を出す。

`--verbose` を持つコマンドは、当面この三つにとどめる。
ビルドの途中で処理系が行ったこと（フォントの選択、図版の縮小など）は、今後 info として出すことになると見込まれ、そのとき `golem preflight` などのほかのコマンドにも `--verbose` が要る可能性がある。
どのコマンドに広げるかは、info に移すコードを決める ADR で、コマンドごとに決める。

golem-driver の `Options` に `optVerbose :: Bool` を足し、既定を `False` とする。
`finishWith` と `Golem.Driver.Lint` は、抑制の後、並べ替えの前に、`optVerbose` が偽なら info を落とす。
`lintProject` は `--verbose` を表す引数を一つ受け取る。
golem-cli の `golem inspect` の仕上げ（app/Main.hs の 315 行め）は、info をつねに落とす。

`golem explain` の案内の行（[golem-cli ADR 0005](../golem-cli/adr/0005-explain-diagnostic-codes.md)）は、今と同じく、書いた diagnostics から作る。
`--verbose` を付けなければ info は一覧にないので、info のコードは案内の例に選ばれない。

### silence-info

`manifest.toml` の `[diagnostics]` の表に、`silence-info` を設ける。
`silence-notices` と同じく、コードを並べた配列であり、並べたコードの info を出さない。

```toml
[diagnostics]
silence-notices = ["G02062"]
silence-info = ["G07047"]
```

`--verbose` を付けない実行では、もともと info は出ない。
`silence-info` が働くのは、`--verbose` を付けた実行と LSP である。
`--verbose` を付けて、ほかの info は見たいが、場面の区切りのたびに出る G07047 は見たくない、という使い方に向く。
LSP は info をつねに公開する（下の「LSP」）ので、エディタで特定の info を止める手段は `silence-info` だけである。

- **書く場所**：`manifest.toml` の `[diagnostics]` だけとする。`silence-notices` と同じく、プロジェクトの方針として書く。`style.toml`、原稿、プロファイルごとの設定には設けない。
- **当てる箇所**：`silence-notices` を当てるすべての箇所（`finishWith`、`Golem.Driver.Lint`、`golem inspect`、LSP）で、同じ時点に当てる。
- **`--verbose` との関係**：`--verbose` は info を出すかどうかを決め、`silence-info` は出す info のうちどのコードを除くかを決める。`--verbose` を付けても、`silence-info` のコードの info は出ない。二つの絞り込みは順序によらず同じ結果になる。
- **`--no-notices` との関係**：`--no-notices` は info を落とさず、`silence-info` は notice を落とさない。
- **すべての info を止める値**は設けない。`silence-notices` と同じく、止めるものをコードで書く。

要素の検査は次のとおりとする。

| 書いたもの | 結果 |
| --- | --- |
| `silence-info` に info のコード | そのコードの info を出さない |
| `silence-info` に info でないコード（notice、error、warning、廃止、存在しないコード） | G03024 |
| `silence-notices` に info のコード（G07047 など） | G03024 |
| どちらかにコードの形でない文字列、文字列でない値 | G03024（今の `silence-notices` と同じ） |
| どちらかが配列でない、`[diagnostics]` の未知のキー | G03001（今と同じ） |

G03024 の原因を「抑制の一覧に、その一覧では抑制できないコードを書いた」と改め、`silence-info` の誤りも同じコードにする。
`silence-notices` に info のコードを書くことと、`silence-info` に notice のコードを書くことは、一覧を取り違えたという同じ原因であり、直し方（正しい一覧に移すか消す）も同じだからである。
G03024 の題は `抑制の一覧に抑制できないコードがあります` に改める。
メッセージは、コードがもう一方の一覧に書けるときに、その一覧の名前を添える。

- `silence-notices` の誤り：`抑制できるのはお知らせのコードだけです: <コード>`。`<コード>` が info のコードなら、後に `（情報のコードは silence-info に書きます）` を添える。
- `silence-info` の誤り：`silence-info に書けるのは情報のコードだけです: <コード>`。`<コード>` が notice のコードなら、後に `（お知らせのコードは silence-notices に書きます）` を添える。

コードの形の誤りと文字列でない値が今の G03024 に同居していることは、この ADR では変えない。
v1.0.0 の「一つのコードに一つの原因の監査」で扱う。

### 表示

人が読む形式では、重大度を `info` と書く。

```
chapters/02.gm:40:1: info[G07047]: 段の先頭に来た @blank-line の空きを捨てました
  | @blank-line
```

JSON の形式では、`severity` を `"info"` とする。
ほかの欄は変えない。
JSON の形式も、`--verbose` を付けたときにだけ info を含む。
人が読む形式と JSON の形式で、出す diagnostic の集合を同じにするためである。

### 並び順

error と warning、notice、info の順に並べる。
`sortDiagnostics` の最初のキーを「notice か」から重大度の段（error と warning は 0、notice は 1、info は 2）に変える。
二つめ以降のキー（コード、ファイル、開始位置、終了位置、メッセージ、残りの欄）は変えない（[golem-syntax ADR 0003](../golem-syntax/adr/0003-diagnostic-order.md)）。
error と warning は、今と同じく区別せずに混ぜる。

### LSP

LSP では、info を `DiagnosticSeverity` の `Hint`（4）に写し、公開する。
`silence-info` に並べたコードの info は公開しない。

LSP には `--verbose` に当たる設定がない。
info を公開しないと、エディタでは info を見る方法がなくなる。
`Information` に写すと、notice と同じく問題の一覧に載り、ふだんは出さないという info の性質と合わない。
`Hint` は、エディタの多くが目立たない形で表示し、問題の一覧に載せない（[golem-syntax ADR 0002](../golem-syntax/adr/0002-notice-severity.md) が notice を `Hint` にしなかった理由）。
見たい人だけがカーソルを合わせて見る、という扱いが info の性質に合う。

[golem-syntax ADR 0002](../golem-syntax/adr/0002-notice-severity.md) は、抑制した notice を `Hint` に下げて残すことを退けた。
そのときの理由は、CLI で書き手が止めたものがエディタでだけ見えると、どちらを正とするかで混乱することだった。
info は書き手が止めたものではなく、ふだん出さないだけなので、この理由は当たらない。
書き手が `silence-info` で止めた info は、エディタでも公開しないので、この理由とも食い違わない。

今の LSP は組版をしないので、G07047 は LSP に載らない。
`lspSeverity` に `Info` の場合を足すのは、評価の段階の info を将来足したときのためである。

### 決定性

diagnostics も決定性の対象である（[docs/adr/0002](0002-determinism.md)）。
`--verbose` は、出力を変えず、diagnostics の一覧だけを変える CLI のオプションである。
同じ入力と同じオプションからは、同じ info を同じ順で出す。
並び順の規則は上の「並び順」のとおり一つに決まる。
出力のバイト列は `--verbose` と `silence-info` の有無によらず同じであり、これは下の「テスト設計」で確かめる。

### docs/diagnostics.md と目録

- 「節の形」の重大度に「情報」を加える。info は `--verbose` を付けたときだけ出し、終了コードと出力に影響せず、`silence-info` で止められ、`silence-notices` と `--no-notices` の対象でないことを書く。
- 「お知らせ」の節の後に「情報」の節を設け、info のコードの一覧（今は G07047 だけ）と、notice と info の分け方、`silence-info` の書き方を書く。
- 「お知らせ」の節の表から G07047 を外し、「今は次の十九である」を十八に改める。
- G07047 の節の重大度を「情報」にし、「info に移す予定である」の文を削り、`--verbose` を付けたときにだけ出ることと、止めるときは `silence-info` に書くことを書く。
- G03024 の節の題、意味、メッセージ、主な原因を、`silence-info` を含む形に改める。
- golem-driver の `Golem.Driver.Explain.Catalog` の `severities` に `"情報"` を加える。

### データ構造の変更

```haskell
data Severity = Error | Warning | Notice | Info
  deriving stock (Eq, Ord, Show)

infoCodes :: [DiagnosticCode]

infoDiagnostic :: Text -> SrcSpan -> Text -> Diagnostic
infoDiagnostic code = diagnostic code Info

-- info をすべて落とす。--verbose がないときに使う
dropInfo :: [Diagnostic] -> [Diagnostic]

-- silence-info のコードの info を落とす。ほかの重大度は残す
silenceInfo :: Set DiagnosticCode -> [Diagnostic] -> [Diagnostic]
```

golem-project の `Manifest` に `manifestSilencedInfo :: Set DiagnosticCode` を、golem-driver の `Options` に `optVerbose :: Bool` を、golem-lsp の `lspSeverity` に `Info -> DiagnosticSeverity_Hint` を足す。
`silenceList` は、受け付けるコードの一覧と、もう一方の一覧の名前を引数にとる形に改め、二つのキーで共有する。
`manifestCode` は、`silence-info` の要素の位置も G03024 にする。
パッケージの依存は変えない。

### ドキュメント

- docs/specifications.md の「構文木と診断」に、四つの重大度、info の性質、notice と info の分け方、並び順、`--verbose` と `-v`、`silence-info` を書く。notice が出力のバイト列を変えないという規則に、info、`--verbose`、`silence-info` も加える。今の notice の列挙から G07047 を外す。マニフェストの `[diagnostics]` の説明に `silence-info` を加える。
- 同じく「CLI」の表の `golem build`、`golem check`、`golem lint` に `--verbose` と `-v` を加え、LSP の節に info を `Hint` に写すことと `silence-info` を当てることを書く。
- docs/markup.md の行アキの節の「notice（G07047）」を「info（G07047、`--verbose` を付けたときだけ出す）」に改める。
- docs/glossary.md の diagnostic の項の重大度を四つにし、info の項を足す。notice の項の「info を加える予定があり」の文を改める。
- README の CLI の表に `--verbose` と `-v` を加える。
- 開発者のマニュアルの「重大度と notice」の節（`manual-dev/part1/02-diagnostics.gm`）の「Golem には info に当たる重大度はない」を改め、notice と info の違いを書く。notice の表から G07047 を外す。LSP の章（`manual-dev/part1/04-lsp.gm`）の重大度の対応に info と `Hint` を足し、CLI の章（`manual-dev/part1/01-cli.gm`）に `--verbose` と `-v` を足す。
- 使い手のマニュアルの「検査と診断」の章（`manual/chapters/07-check.gm`）の notice の一覧から G07047 を外し、info、`--verbose`、`silence-info` を書く。記法の章（`manual/chapters/03-markup.gm`）で G07047 を notice とした文と、付録 E（`manual/appendices/e-errors.gm`）の G07047 と G03024 も改める。ロードマップの付録（`manual/appendices/h-roadmap.gm`）の項目を消す。
- [docs/adr/0046](0046-blank-line-command.md) のステータスの行を「採択→G07047 の重大度は [ADR 0104](0104-info-severity.md)」にする。
- [golem-syntax ADR 0002](../golem-syntax/adr/0002-notice-severity.md) のステータスの行に「、notice の下の info と並び順の最後の段と `silence-info` は [docs/adr/0104](../../adr/0104-info-severity.md)」を足す。

## 実装しないこと

- G07047 のほかの notice を info に移すこと。
- プラグイン、lint の規則、プリフライトの info。
- `--verbose` を `golem preflight`、`golem inspect` などに設けること。info に移すコードを決める ADR で、コマンドごとに決める。
- info をコードごとに出す手段（`--verbose=G07047` など）。
- すべての info を止める `silence-info` の値と、`style.toml` や原稿で info を止める手段。
- LSP の info を、`silence-info` のほかの設定で出し分けること。
- info のほかの出力を `--verbose` で増やすこと。
- G07047 を `silence-notices` に書いたプロジェクトのための移行の期間。

## テスト設計

### 先に書いて失敗させるテスト

golem-syntax のテストで、次を確かめる。

- `Notice < Info` であること（`Error < Warning < Notice < Info`）。
- `hasErrors` が、info だけの一覧で偽になること。
- `adjustForProfile Prod` が info の重大度を変えないこと。
- `infoCodes` が `["G07047"]` であり、`noticeCodes` と `profileDependentCodes` のどちらとも共通のコードを持たないこと。`noticeCodes` の一覧を固定しているテスト（`test/Main.hs`）から G07047 を外す。
- `sortDiagnostics` が、コードと位置の早い info を、コードと位置の遅い notice より後に並べること。入力の順をシャッフルしても結果が同じであること（プロパティテスト）。
- `dropInfo` が info をすべて落とし、ほかの重大度の diagnostic をすべて残すこと（プロパティテスト）。
- `silenceInfo` が、集合のコードの info だけを落とし、集合にないコードの info と、ほかの重大度の diagnostic を残すこと。集合のコードと同じコードの notice があっても落とさないこと（プロパティテスト）。
- `silenceNotices Nothing` が info を残すこと。
- 人が読む形式の golden テストで、見出しの行が `info[G07047]` になること。JSON の形式の golden テストで、`"severity":"info"` になり、notice の後に並ぶこと。

golem-project のテストで、次を確かめる。

- `silence-info = ["G07047"]` を読み、`manifestSilencedInfo` が `{G07047}` になること。
- `silence-notices = ["G07047"]` が、その要素の位置で G03024 になり、メッセージが `抑制できるのはお知らせのコードだけです: G07047（情報のコードは silence-info に書きます）` であること。
- `silence-info = ["G02062"]`（notice）が、その要素の位置で G03024 になり、メッセージが `silence-info に書けるのは情報のコードだけです: G02062（お知らせのコードは silence-notices に書きます）` であること。
- `silence-info = ["G01001"]`（error）と `silence-info = ["G0747"]` と `silence-info = [1]` が、その要素の位置で G03024 になること。誤った要素が二つあれば、二つとも報告すること。
- `silence-info = "G07047"`（配列でない）が G03001 になること。

golem-driver のテストで、次を確かめる。

- 段の先頭に来た `@blank-line` のプロジェクト（今の G07047 のテストの原稿）で、`optVerbose` が偽なら G07047 が出ず、真なら重大度 `Info` の G07047 が一つ、今と同じ位置に出ること。
- 同じプロジェクトに `silence-info = ["G07047"]` を書くと、`optVerbose` が真でも G07047 が出ないこと。
- `optVerbose` と `optNoNotices` をともに真にすると、notice が出ず、G07047 が出ること。
- `everyNoticeProjects` のテストを、notice と info の両方に広げる。`optVerbose` なしで出したコードの集合が `noticeCodes` に等しく、`optVerbose` を付けて出した info のコードの集合が `infoCodes` に等しいこと。`optVerbose` の有無と、`silence-info` にすべての `infoCodes` を並べた場合とで、四つのターゲットの出力のバイト列が同じであること。今のテストのうち、`silence-notices` と `--no-notices` で出力が変わらないことの検査は残す。
- docs/diagnostics.md で重大度が「情報」のコードの集合が `infoCodes` と一致すること。目録の解析が「情報」を受け付けること。不正な重大度の例（DiagnosticsSpec.hs の 317 行め）を「情報」から、五つの値のどれでもない値（「ヒント」など）に変える。

golem-cli のテストで、次を確かめる。
golem-cli のテストは実際のフォントを持たず PDF を組まないので、G07047 そのものは golem-driver のテストで確かめる。

- `golem build --verbose`、`golem check -v`、`golem lint --verbose` を受け付けること。notice を出すプロジェクトで、`golem build --verbose` の出力のバイト列が `--verbose` なしと同じであること。
- `golem fmt --verbose`、`golem explain -v`、`golem inspect <FILE> --verbose`、`golem preflight -v` が使い方の誤り（終了コード 2）になること。`golem -v` が使い方の誤りになり、バージョンを表示しないこと。
- `golem build --help` の golden に `-v,--verbose` の行が加わること。

golem-lsp のテストで、`lspSeverity Info` が `DiagnosticSeverity_Hint` になることと、`silence-info` のコードの info を公開しないことを確かめる。
今の LSP は info を出さないので、後者は公開の前の絞り込みの関数を、info を含む一覧に当てて確かめる。

### 自動テストにできないものの確かめ方

- `@blank-line` が段の先頭に来るプロジェクトを PDF に組み、`golem build` で G07047 が出ず、`golem build -v` で `info[G07047]` が出て、`silence-info = ["G07047"]` を書くと `golem build -v` でも出ないことを、実際の `golem` で確かめる。
- 結果は、実装のプルリクエストのコメントに書く。

## トレードオフ

- 重大度が一つ増え、diagnostic を出す側は notice と info のどちらにするかを判断する必要が出る。基準を「書き手が知る必要があるか」の一つにし、迷うものは notice にする。
- info はふだん見えないので、info にしたものに書き手が困る場合があっても、気づきにくい。最初は G07047 だけにし、[docs/adr/0046](0046-blank-line-command.md) が直す必要はないと判断したものに限る。
- 抑制の設定が二つ（`silence-notices` と `silence-info`）になり、書き手は書くコードの重大度を知っている必要がある。取り違えたら G03024 が正しい一覧の名前を示すので、書き直しは一度で済む。
- `silence-notices` に G07047 を書いていたプロジェクトは、版を上げるとエラーになる。黙って無視すると、何も止めない行が抑制の一覧に残る。メッセージが `silence-info` を示す。
- LSP では info を `Hint` で公開するので、CLI では `--verbose` を付けないと見えないものが、エディタではつねに目立たない形で見える。CLI とエディタの見え方が一致しない。エディタの `Hint` は問題の一覧に載らず、書き手が `silence-info` で止めたものは公開しないので、この差を受け入れる。
- JSON の形式も `--verbose` でしか info を含まないので、プログラムで info を集めるには `--verbose` を付ける必要がある。人が読む形式と JSON の形式で集合をそろえることを優先した。
- `-v` を `--verbose` に使うので、ほかのツールの慣習で `-v` を `--version` と読む利用者は、`golem -v` で使い方の誤りを見ることになる。Golem の `--version` はもともと短い形を持たない。

## 決めたことの記録

草案で開いていた点を、次のとおりに決めた。

- **LSP を `Hint` に写すこと、info にするのは G07047 だけ、JSON は `--verbose` のときだけ info を含むこと、名前（`Info`、「情報」、`infoDiagnostic`）**：メンテナーが草案のとおりに承認した。
- **`-v`**：メンテナーが、`--verbose` の短い形として設けると決めた。
- **`silence-info`**：メンテナーが設けると決めた。書く場所（`manifest.toml` の `[diagnostics]`）、要素の検査、`--verbose` と LSP との関係は、この版で決めた。取り違えた一覧の誤りは、一つの原因として G03024 にまとめ、題とメッセージを改めた。
- **`silence-notices` に info のコード**：草案のとおり G03024 とする。メンテナーの指示はなく、草案の案を保った。メッセージに `silence-info` の案内を添えるのは、この版で足した。
- **`--verbose` を持つコマンド**：メンテナーが、当面 `golem build`、`golem check`、`golem lint` の三つとすると決めた。ほかのコマンドへの広げ方は別の ADR で決める。

## 参考文献

- [golem-syntax ADR 0002](../golem-syntax/adr/0002-notice-severity.md)
- [golem-syntax ADR 0003](../golem-syntax/adr/0003-diagnostic-order.md)
- [golem-cli ADR 0005](../golem-cli/adr/0005-explain-diagnostic-codes.md)
- [docs/adr/0002](0002-determinism.md)
- [docs/adr/0046](0046-blank-line-command.md)
- Language Server Protocol Specification 3.17, DiagnosticSeverity. https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#diagnosticSeverity
