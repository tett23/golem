# ADR 0417: 解決した禁則とぶら下げの設定を JSON で出す

Status: accepted-pending

## 文脈

エディタの Aleph は、Golem の原稿を編集しながら、エディタの折り返しに、Golem の禁則とぶら下げ組を反映したい ([tett23/aleph ADR 0090: エディタの折り返しに禁則とぶら下げ組を反映する](https://github.com/tett23/aleph/blob/8a36f1754613c4cc9eb62d5f8645b50616b3dc6d/docs/adr/0090-editor-composition-settings.md))。
そのとき Aleph は、Golem の設定の解決 (既定値、省略、誤り) を自分で持たず、Golem が解決した値を使うと決めている。
しかし、今の Golem には、解決した組版の設定を外に出す口が無い。
Aleph が `style.toml` を自分で読むと、既定値と誤りの扱いを Golem と二重に持つことになり、Golem が規則を変えたときに食い違う。

この ADR は、プロジェクトの解決した組版の設定のうち、禁則の強さ (`kinsoku`) とぶら下げ (`hanging-punctuation`) の二つを、CLI から JSON で出す口を決める。

## 調査した事項

コードは、main のコミット [b540aa6](https://github.com/tett23/golem/tree/b540aa68a3bbb45ed4a8754f79852984152f6cf6) のものである。

- `style.toml` の `[composition]` は、`kinsoku` (`"strict"` か `"loose"`) と `hanging-punctuation` (真偽) を持つ。既定は `strict` と偽である ([`Style.hs` の `defaultComposition`](https://github.com/tett23/golem/blob/b540aa68a3bbb45ed4a8754f79852984152f6cf6/modules/golem-project/src/Golem/Project/Style.hs#L1873-L1874)、[`instance FromValue Composition`](https://github.com/tett23/golem/blob/b540aa68a3bbb45ed4a8754f79852984152f6cf6/modules/golem-project/src/Golem/Project/Style.hs#L2466-L2484))。
- `[composition]` はプロジェクトに一つで、原稿のファイルごとの上書き (`withLocalStyles`) は、文字スタイルと段落スタイルだけを重ねる ([`Style.hs`](https://github.com/tett23/golem/blob/b540aa68a3bbb45ed4a8754f79852984152f6cf6/modules/golem-project/src/Golem/Project/Style.hs#L3909-L3918))。組版は `stComposition` から禁則とぶら下げを取る ([`Flow.hs`](https://github.com/tett23/golem/blob/b540aa68a3bbb45ed4a8754f79852984152f6cf6/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L1828-L1841))。
- 行頭禁止と行末禁止の分類は、[`Japanese.hs` の `lineStartProhibited` と `lineEndProhibited`](https://github.com/tett23/golem/blob/b540aa68a3bbb45ed4a8754f79852984152f6cf6/modules/golem-layout/src/Golem/Layout/Japanese.hs#L91-L105) にある。`strict` のときだけ、長音記号と小書きの仮名を行頭禁止にする。ぶら下げの対象は、[句点と読点](https://github.com/tett23/golem/blob/b540aa68a3bbb45ed4a8754f79852984152f6cf6/modules/golem-layout/src/Golem/Layout/Japanese.hs#L1553) である。
- CLI のコマンドは `new build check preflight plugin lint fmt lsp inspect explain repl stats` である ([`Main.hs` の `commands`](https://github.com/tett23/golem/blob/b540aa68a3bbb45ed4a8754f79852984152f6cf6/modules/golem-cli/app/Main.hs#L206-L232))。どれも、解決した組版の設定を出さない。`kinsoku` という名前のコマンドは無い。
- CLI のコマンドは、今のフォルダをプロジェクトの根とし、親へたどらない ([`Main.hs`](https://github.com/tett23/golem/blob/b540aa68a3bbb45ed4a8754f79852984152f6cf6/modules/golem-cli/app/Main.hs#L266-L267) の `runBuild "."`)。親へたどって最も近い `manifest.toml` を探すのは、LSP の [`findRoot`](https://github.com/tett23/golem/blob/b540aa68a3bbb45ed4a8754f79852984152f6cf6/modules/golem-lsp/src/Golem/Lsp/Server.hs#L65-L72) だけである。`findRoot` は `makeAbsolute` で絶対パスにし、シンボリックリンクは解かない。
- `golem build` は、マニフェストとすべての原稿を読んだ後に `style.toml` を読み ([`Driver.hs`](https://github.com/tett23/golem/blob/b540aa68a3bbb45ed4a8754f79852984152f6cf6/modules/golem-driver/src/Golem/Driver.hs#L246-L266))、`style.toml` だけの解決は `loadStyle` が行う。
- 既存の `--format human|json` は、diagnostics の出力の形を決め、既定は `human` である ([`Main.hs` の `formatOpt`](https://github.com/tett23/golem/blob/b540aa68a3bbb45ed4a8754f79852984152f6cf6/modules/golem-cli/app/Main.hs#L182-L186))。
- LSP にも、組版の設定を返す要求は無い (`modules/golem-lsp/src` に `kinsoku`、`hanging`、`stComposition` の語は無い)。
- Aleph の側の調べ ([tett23/aleph の 2026-11-23 の調査](https://github.com/tett23/aleph/pull/169)) では、WebKit の `line-break: strict` が、試した字で Golem の `strict` と同じ折り返しになった。`hanging-punctuation: allow-end` は、句点と読点だけを、要るときだけぶら下げた。`loose` は、WebKit の CSS では表せなかった。

## 実装すること

### コマンド

- コマンド `golem kinsoku [PATH]` を足す。名前は、出すものに合わせて狭くする。`style` のような広い名前にすると、`style.toml` のほかの値も出すと読めるためである。ぶら下げも禁則処理の方式の一つなので、`kinsoku` の名前で出す。出力はいつも JSON で、`--format` は持たない (既存の `--format` は diagnostics の形を決めるので、同じ名前で出力の形を決めると混ざるためである)。
- `PATH` は、プロジェクトのフォルダか、その中のファイルとする。省いたときは、今のフォルダとする。`PATH` が存在しないときは、存在する最も近い親のフォルダから始める。編集中でまだ保存していないファイルのパスも渡せるようにするためである。
- 始めのフォルダから親へたどり、最も近い `manifest.toml` のあるフォルダをプロジェクトの根とする。LSP の `findRoot` と同じ探し方である。
- プロジェクトの根の `style.toml` だけを読み、`loadStyle` で解決する。マニフェストの中身の解釈と、原稿の読み込みはしない。そのため、章のファイルが無いことやマニフェストの誤りは、このコマンドの結果を変えない。
- 標準出力に、次の形の JSON を一行で書き、末尾に改行を一つ置く。キーの順は `schema`、`project`、`composition` とする。

```json
{"schema":1,"project":"/path/to/project","composition":{"kinsoku":"strict","hangingPunctuation":false}}
```

- `project` は、プロジェクトの根の絶対パス (`makeAbsolute` の結果。シンボリックリンクは解かず、末尾に区切りを付けない) とする。プロジェクトが見つからないときは `null` とし、`composition` を既定値にする。
- `composition` の値は、`style.toml` に書いた値か、省いたときの既定値である。どちらなのかは区別しない (使う側が要るのは、解決した値だけである)。`style.toml` が無いときも既定値とし、notice は書かない。
- JSON のキーは、JSON で広く使われる形にそろえて `hangingPunctuation` とする。
- 終了コードは、値を書いたとき 0 とする。

### 誤りと diagnostics

- `loadStyle` が誤りを返したときは、diagnostics を human の形で標準エラー出力に書き、終了コード 1 で終える。標準出力には何も書かない。使う側は、前に読めた値を保つか、既定値を使う。
- `loadStyle` が warning や notice だけを返したときは、それを標準エラー出力に書き、JSON を標準出力に書いて終了コード 0 とする。
- diagnostic のファイルのパスは、`style.toml` の絶対パスとする。今のフォルダがプロジェクトの根とは限らないためである。
- 使い方の誤り (引数が二つ以上など) は、[golem-cli ADR 0004](../golem-cli/adr/0004-usage-error-exit-code.md) のとおり終了コード 2 とする。
- 出すキーは、`schema` を上げずに足せる。キーを除くか意味を変えるときは、`schema` を上げる。

### 文書

- 仕様書の「CLI」の節の表と、開発者向けのマニュアル (`manual-dev/part1/01-cli.gm`) の「コマンドの一覧」と「標準出力と標準エラー出力」、README のコマンドの表に、このコマンドを書く。

## 実装しないこと

- 行頭禁止と行末禁止の字の集合を出すこと。WebKit の `line-break: strict` が試した字で Golem と同じ折り返しになったので、今は要らない。`loose` をエディタで表すときは、別の ADR で決める。
- 段落ごとの組版の指定 (囲みを持つ段落でぶら下げないことなど) を出すこと。
- `[composition]` のほかのキーを出すこと。要るキーは、使う側の ADR とあわせて足す。
- LSP の要求で同じ値を返すこと。
- ほかの CLI のコマンドの、プロジェクトの探し方を変えること。

## 不変条件

- I1: プロジェクトが見つかり、`style.toml` が誤りを含まないとき、`composition` は、同じプロジェクトを `evaluateProject` で解決した `stComposition (evStyle e)` の `compKinsokuStrict` と `compHanging` に等しく (`kinsoku` は `compKinsokuStrict` が真なら `"strict"`、偽なら `"loose"`)、終了コードは 0 である。
- I2: プロジェクトが見つからないとき、`project` は `null` で、`composition` は `defaultComposition` の値に等しく、終了コードは 0 である。
- I3: `loadStyle` が誤りを返すとき、標準出力は空で、終了コードは 1 である。
- I4: プロジェクトが見つかったとき、`project` は、始めのフォルダから親へたどって最初に `manifest.toml` を持つフォルダの、`makeAbsolute` の結果に等しい。
- I5: 標準出力は、一行の JSON と末尾の改行一つで、キーは `schema`、`project`、`composition` の順である。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| `style.toml` が無い | 既定値 (`strict`、偽)、notice は書かない、終了コード 0 | I1 |
| `[composition]` が無い | 既定値、終了コード 0 | I1 |
| `kinsoku = "loose"` だけ | `loose`、偽 | I1 |
| `hanging-punctuation = true` だけ | `strict`、真 | I1 |
| 両方を書く | 書いた値 | I1 |
| `style.toml` に警告だけがある | 標準出力に JSON、標準エラー出力に警告、終了コード 0 | I1 |
| `PATH` がプロジェクトの中の章のファイル | そのプロジェクトの値 | I1, I4 |
| `PATH` を省き、今のフォルダがプロジェクトの根 | そのプロジェクトの値 | I1, I4 |
| `PATH` がプロジェクトの中の、存在しないファイル | そのプロジェクトの値 | I1, I4 |
| 入れ子のプロジェクトの内側のファイル | 内側のプロジェクト | I4 |
| `PATH` が、`manifest.toml` を親にも持たないフォルダ | `project` は `null`、既定値、終了コード 0 | I2 |
| `PATH` が、`manifest.toml` を親にも持たないファイル | `project` は `null`、既定値、終了コード 0 | I2 |
| 章のファイルが無いプロジェクト | そのプロジェクトの値 (結果は変わらない) | I1 |
| `kinsoku = "medium"` (誤り) | 標準出力は空、終了コード 1 | I3 |
| `style.toml` が TOML として読めない | 標準出力は空、終了コード 1 | I3 |
| 引数が二つ | 終了コード 2 | ([golem-cli ADR 0004](../golem-cli/adr/0004-usage-error-exit-code.md)) |
| どの成功の場合も | 一行の JSON と改行一つ、キーの順は決まったとおり | I5 |

## 受けいれ条件

- A1: Aleph が `golem kinsoku <ファイルのパス>` を呼び、終了コードと JSON から `kinsoku` と `hangingPunctuation` を読める。`kinsoku = "loose"` をエディタで再現することは、この ADR の範囲に含まない。

## テスト設計

- I1 から I5 は、CLI の統合テストで、境界の表の行ごとに一時のプロジェクトを作って確かめる。I1 は、同じプロジェクトを `evaluateProject Dev root` で解決した `stComposition (evStyle e)` とも比べる。出力は JSON として読んで比べ、I5 だけは文字列で比べる。
- テストの名前は、モノレポのルートの ADR の決まりに従い、`root ADR 0417 I1: …` のようにする。
- A1 は、Aleph の [ADR 0090](0090-html-settings-conversion-stays-in-driver.md) の実装で確かめる。

## トレードオフ

LSP の要求にすると、開いているファイルごとに、プロセスを起こさずに値を得られる。
しかし、エディタは `style.toml` を保存したときに一度読み直せばよく、CLI を一度呼ぶ重さは問題にならない。
CLI なら、エディタのほかの道具 (スクリプト、CI) からも同じ値を得られる。

このコマンドだけが、ほかの CLI のコマンドと違い、親へたどってプロジェクトを探す。
エディタは、開いたファイルのパスしか持たず、プロジェクトの根を知らないことがあるためである。
探し方は LSP の `findRoot` と同じにして、Golem の中で探し方が三通りに増えないようにする。

字の集合を出さないので、`loose` の折り返しをエディタで再現するには、別の ADR で集合を出す口を足す必要がある。
今は、WebKit の `strict` で Golem の `strict` を表せる見込みが立ったので、要る分だけを先に出す。

プロジェクトの外のファイルに既定値を出すのは、Aleph が、プロジェクトに属さないファイルに Golem の既定値を使うと決めているためである ([tett23/aleph ADR 0090](https://github.com/tett23/aleph/blob/8a36f1754613c4cc9eb62d5f8645b50616b3dc6d/docs/adr/0090-editor-composition-settings.md))。
Golem 自身は、`manifest.toml` の無いフォルダを組まない。

## 参考文献

- [tett23/aleph ADR 0090: エディタの折り返しに禁則とぶら下げ組を反映する](https://github.com/tett23/aleph/blob/8a36f1754613c4cc9eb62d5f8645b50616b3dc6d/docs/adr/0090-editor-composition-settings.md)
- [golem-cli ADR 0004](../golem-cli/adr/0004-usage-error-exit-code.md)
- [golem-cli ADR 0007](../golem-cli/adr/0007-inspect-output.md)
