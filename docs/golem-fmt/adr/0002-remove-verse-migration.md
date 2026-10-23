# ADR 0002: golem fmt の移行の段階を外す

ステータス: 採択

## 文脈

[docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md) は、韻文の記法 `@verse` をなくし、段落スタイルを付ける `@style verse` に替えた。
あわせて `golem fmt` に移行の段階を加え、`@verse` を `@style verse` に書き換えるようにした。
移行の段階は v1 の間は残し、外すときは別の ADR で決めるとしている。

移行の段階があるため、整形の不変条件に例外が一つある。
[ADR 0001](0001-formatter.md) の不変条件は「整形の前と後で AST が一致する」だが、今は「移行の後の原稿と、整形の結果とで AST が一致する」になっている。
`@verse` を `@style verse` に替えると AST が変わるので、移行の前の原稿とは一致しない。
仕様書の「v1 の実装で次の段階以降に回した項目」（[specifications.md](../../specifications.md)）は、v1 のリリースまでに移行の段階を外し、この例外をなくすとしている。

今の実装は次のとおりである。

- `Golem.Fmt.migrate` が、引数のない `@verse` のブロックコマンドの名前のトークンを、`style verse` を解析した場合と同じトークンの並びに替える。
- `Golem.Fmt.format` は、前処理と解析の後に `migrate` をかけて描画した文字列を新しい原稿とし、AST の一致を検査する基準（`astFingerprint`）をこの文字列から取る。
- LSP の整形（`Golem.Lsp.Features.formatting`）も `format` を呼ぶので、同じ移行が効く。
- 評価（`Golem.Eval.File`）は、`@verse` を G02048（`@verse は @style verse に変わりました。golem fmt で書き換えられます`）とする。ほかの未知のブロックコマンドは G02009（`未知のブロックコマンドです: @名前`）である。

公開した版は、最初のプレリリースの v0.1.0-rc1（2026-10-13、[docs/adr/0008](../../adr/0008-first-release-verification.md)）だけである。
v0.1.0-rc1 でも `@verse` はすでにエラー（G02048）であり、正しい原稿として組めた版はない。
`@verse` を使って組んだ実際の本はまだない。
`@verse` を含む原稿を持つのは、開発中の Golem を使った原稿だけである。
リポジトリの中で `@verse` を使う原稿は、`golem-fmt` と `golem-cli` のテストの入力だけであり、`tempest.gm` などのフィクスチャはすでに `@style verse` に書き換えてある。

## 実装すること

### golem-fmt

- `Golem.Fmt` から `migrate` を削除し、エクスポートの一覧からも外す。
- `format` は、前処理の後の原稿をそのまま解析し、`astFingerprint` をその原稿から取る。整形の規則を順に適用する処理は変えない。
- 整形の不変条件を [ADR 0001](0001-formatter.md) のとおり「前処理の後の原稿と、整形の結果とで AST が一致する」に戻す。前処理（BOM、CRLF、インデントのタブ）は読み込みの段階でエラーになる箇所だけを直し、AST を変えないので、これは「整形の前後で AST が一致する」と同じである。
- `@verse` は、ほかのブロックコマンドと同じく構文としては正しいので、`golem fmt` は整形の規則だけを適用し、名前を書き換えない。
- モジュールの先頭のコメントと `format` のコメントから、移行の説明を除く。

### golem-eval

- `Golem.Eval.File` のブロックコマンドの振り分けから `"verse"` の場合を削除する。`@verse` は、ほかの未知のブロックコマンドと同じ経路で G02009（`未知のブロックコマンドです: @verse`）になる。
- G02048 は廃止する。診断コードは別の意味に再利用しない（[golem-syntax ADR 0001](../../golem-syntax/adr/0001-source-spans-and-diagnostics.md)）ので、G02048 は欠番として残す。

### 移行の案内

`@verse` は削除し、`@verse` のための個別の文言と自動の書き換えは設けない。
`@verse` で組んだ実際の本がまだないので、書き換えの道を残す必要がない。
`@verse` を含む原稿は、公開した版の Golem でも一度も正しい原稿として扱われていない。
ただし v0.1.0-rc1 の `golem fmt` は `@verse` を書き換えていたので、次のリリースのリリースノートの「削除」に、`golem fmt` が `@verse` を書き換えなくなったことを載せる。
開発中の Golem で書いた原稿の持ち主には、G02009 の位置で `@verse` が示されるので、`@style verse` に書き換えれば足りる。

[golem-cli ADR 0005](../../golem-cli/adr/0005-explain-diagnostic-codes.md) の診断の説明を実装した場合は、廃止したコードとして G02048 の項目を残し、`@verse` を `@style verse` に書き換えることをそこに書く。

### ドキュメント

- 仕様書の「fmt」の節から、移行の段階の段落（`@verse` の書き換え、コードブロックの扱い、不変条件の例外、`--check` での報告）を削る。
- 仕様書の「v1 の実装で次の段階以降に回した項目」から「`golem fmt` の移行の段階を外すこと」の項目を削る。
- docs/markup.md の「以前の `@verse` はエラーになる。`golem fmt` が `@verse` を `@style verse` に書き換える。」の二文を削る。
- [docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md) のステータスの行を「採択→fmt の移行の段階と G02048 は golem-fmt ADR 0002」に変え、この ADR へのリンクを、書き込む先のファイルからの相対パスで付ける。
- [ADR 0001](0001-formatter.md) のステータスの行を「採択→移行の段階は [docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md) で加え、[ADR 0002](0002-remove-verse-migration.md) で外した」に変える。
- ソースの中で `@verse` を例に挙げたコメント（`Golem.Parser.AST` の先頭のコメント）を `@style verse` に直す。

## 実装しないこと

- `@verse` を `@style verse` の別名として残すこと。[docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md) が別名を退けた理由（段落スタイルを増やすたびに別名を増やすかを決める必要が生じる）は変わらない。
- `@verse` に G02009 と異なる専用のメッセージや、診断の修正案（`diagFixes`）で `@style verse` を示すこと。公開した版に `@verse` がないので、案内を保つ費用に見合わない。
- `golem fmt` に別の移行の段階を加える仕組み。今後、記法を変える場合も、移行の要否はその ADR で決める。
- ほかの廃止した設定（`[emphasis]`、`[verse]` の `stanza-gap` など）の G03006 のメッセージにある書き換え先の案内の削除。これらは `style.toml` の読み込みのエラーであり、fmt の不変条件に関わらない。

## テスト設計

先に次のテストを書き換えて失敗させる。

### golem-fmt（`modules/golem-fmt/test/Main.hs`）

- 移行のテストグループ（名前は `migration (docs/adr ADR 0005)`）を削除し、次のテストを置く。
  - `formatted "@verse\n  a\n"` が `"@verse\n  a\n"` になる（名前を書き換えない）。
  - `formatted "@verse   \n  a  \n"` が `"@verse\n  a\n"` になる（整形の規則だけを適用する）。
  - `format "@label song\n@verse\n  Full fathom five\n"` の結果の `astFingerprint` が、入力の `astFingerprint` と一致する。
- golden の `verse` の入力の `@verse` を `@style verse` に替える。期待する出力（`test/golden/verse.gm`）は変えない。
- プロパティ「output is unchanged: the AST is preserved」の生成器 `block` に、`@verse` を名前とするブロックコマンドとその本体を加える。整形の結果の `astFingerprint` が `preprocess` の後の入力のものと一致すること、冪等であることを、`@verse` を含む原稿でも確かめるためである。

### golem-eval（`modules/golem-eval/test/FileSpec.hs`）

- `errs "@verse\n  A\n"` が `["G02009"]` になる。今の `["G02048"]` を書き換える。

### golem-cli（`modules/golem-cli/test/Main.hs`）

- 「golem fmt --check reports a file with @verse」を次のテストに替える。`"@verse\n  Full fathom five\n"` を書いた `a.gm` に `golem fmt --check a.gm` を実行すると終了コードが 0 になり、`golem fmt a.gm` の後もファイルの内容が変わらない。

### 実装の後の確かめ

- `git grep -n "G02048"` が、ADR と診断の説明の文書のほかに一致しないこと。
- `git grep -n "migrate"` が、golem-fmt に一致しないこと。

## トレードオフ

開発中の Golem で `@verse` を使って書いた原稿は、自動では書き換わらなくなる。
`@verse` で組んだ実際の本はまだなく、該当する原稿は開発中の Golem で書いたものだけであり、G02009 がすべての位置を示すので、手で直す量は `@verse` の数に限られる。
その代わり、整形の不変条件から例外がなくなり、fmt は AST を変えない処理だけになる。
LSP の整形も同じ `format` を通るので、エディタでの整形が原稿の意味を変えることもなくなる。

`@verse` の誤りが一般の G02009 になるので、メッセージから書き換え先は読み取れない。
書き換え先は、廃止した G02048 の説明と、docs/markup.md の `@style verse` の説明で示す。
