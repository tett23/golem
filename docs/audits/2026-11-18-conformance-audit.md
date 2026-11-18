# ADR 違反と予算違反の監査（2026-11-18）

- 日付：2026-11-18
- 読んだコミット：cf244a2b5cc09cf117bd5f4c8e37ce40f978f706
- 範囲：root [ADR 0341](../adr/0341-revise-retire-listing-src.md)〜0395 のうち、`accepted` のものと、`superseded` と `superseded-pending` の ADR の置き換えられていない部分（2026-11-17 から 2026-11-18 に実装したもの）。予算違反の観点は、[docs/budgets.md](../budgets.md) の全行。
- 使ったモデル：Fable（`auditor`）。範囲を 0341〜0357、0358〜0375、0376〜0395 と予算の三つに分け、三つの `auditor` に並べて任せた。
- 指定した推論の強さ：指定なし
- `auditor` が報告した推論の強さ：三つとも「指定を受けておらず、自分では分からない」

以下は、三つの `auditor` が返した指摘を変えずに貼ったものである。

---

## root [ADR 0341](../adr/0341-revise-retire-listing-src.md)〜0357

モデルは Fable 5.2 (claude-fable-5-2) である。
推論の強さは、自分からは読み取れない (指定は受けていない)。

## 確かめ方

読んだコミットは cf244a2b5cc09cf117bd5f4c8e37ce40f978f706 である。
リポジトリの作業ツリーには書いていない (終了時の `git status --porcelain=v1` は開始時と同じ 3 行)。
`git archive cf244a2b` をスクラッチパッド `/private/tmp/claude-501/-Users-tett23-repositories-src-github-com-tett23-golem/cb1691be-4aee-4682-b663-ec1ca710eb2d/scratchpad/tree` に展開し、そこで `cabal build all --offline -j` を動かした。
全パッケージと全テストのリンクまで終わった。
cabal 自体は最後に `/Users/tett23/.cabal/logs/build.log: withFile: permission denied` で終了コード 1 を返した (サンドボックスがログの書き込みを拒んだため。コンパイルエラーは無い)。
下のパスは、断らない限り `/Users/tett23/repositories/src/github.com/tett23/golem/` の cf244a2b の中身である。

名前に ADR の番号を持つテストは、スイートごとに `-p '/ADR 034/ || /ADR 035/ || /ADR 0319/ || /M1 / || /T1 / || /X1\/X2/'` で動かした。
結果は次のとおりで、失敗は無い。
golem-eval-test 39 件、golem-project-test 31 件、golem-syntax-test 2 件、golem-fmt-test 4 件、golem-font-test 23 件、golem-pdf-test 7 件、golem-layout-test 6 件、golem-preflight-test 1 件、golem-lsp-test 38 件、golem-cli-test 15 件、golem-driver-test 36 件が、どれも `All N tests passed` だった。
`sh scripts/ci/test-warning-job-list.sh` ([ADR 0349](../adr/0349-retry-ci-job-list-on-rate-limit.md) I1〜I4) は終了コード 0 だった (BSD の `mktemp -d` がサンドボックスで失敗するので、PATH に一時ディレクトリを作る代わりの `mktemp` を置いて動かした)。

## 指摘

### 1. [ADR 0341](../adr/0341-revise-retire-listing-src.md)〜0344 の I3 (と I4、0344 I5 の rc4 側) のテストが CI でもテストスイートでも動かない

- 観点: ADR 違反 (不変条件のテスト)。
- 重大度: 中。
- ADR: `docs/adr/0341-revise-retire-listing-src.md:52,73`、`docs/adr/0342-revise-retire-dash-line-ranges.md:56,79`、`docs/adr/0343-revise-retire-table-src.md:47,68`、`docs/adr/0344-revise-retire-legacy-style-formats.md:47-49,72-73`。
- 実装: `experiments/syntax/listing-release.mjs:41,52`、`experiments/syntax/line-range-release.mjs:45,58`、`experiments/syntax/table-release.mjs:43,64`、`experiments/syntax/style-format-release.mjs:53,67,78`。
- 根拠: `rg -n --hidden 'experiments/|release\.mjs' .github scripts` は `scripts/visual/test.sh:435` (別の experiments/ci-wait) だけを返した。
- 問題: rc4 の CLI と候補の CLI を比べるテストは experiments にあるだけで、ワークフローにも cabal のテストにも呼び出しが無い。
- 問題: rc4 の notice と v1.0.0 のエラーを同じ入力で比べる I3 は、Haskell のテストには無い (Haskell 側は v1.0.0 の側だけを確かめる)。
- 手元の確かめ: `node experiments/syntax/<名前>-release.mjs /Users/tett23/.local/bin/golem <ビルドした golem>` は、listing 3 件、line-range 4 件、table 2 件、style-format 5 件がすべて pass だった。
- 未確認: `/Users/tett23/.local/bin/golem` (`golem 0.1.0-rc4`、11 月 9 日 08:10) が v0.1.0-rc4 のタグ (40eb98ce0、11 月 9 日 07:19) のビルドかどうかは確かめていない。

### 2. [ADR 0342](../adr/0342-revise-retire-dash-line-ranges.md)、[0343](../adr/0343-revise-retire-table-src.md)、[0344](../adr/0344-revise-retire-legacy-style-formats.md) の比較テストの名前に ADR の番号が無い

- 観点: ADR 違反 (テストの名前)。
- 重大度: 低。
- 根拠: `experiments/syntax/line-range-release.mjs:45` は `test("I3: a single old separator ...`、`experiments/syntax/table-release.mjs:43` は `test("I3: rc4 and v1 report ...`、`experiments/syntax/style-format-release.mjs:53` は `test("I3: one old form ...` である。
- 問題: `ADR NNNN I3: ` の形でなく、`I3: ` だけで始まる (`listing-release.mjs` は `ADR 0341 I3: ` の形)。

### 3. [ADR 0348](../adr/0348-revise-emet-expression-repl.md) の R7 と、R4 の端末の部分を確かめるテストが自動で動かない

- 観点: ADR 違反 (不変条件のテスト)。
- 重大度: 中。
- ADR: `docs/adr/0348-revise-emet-expression-repl.md:131,134` (R4、R7)、`:154-155,162-164` (R1 から R7 をテスト名に入れ、疑似端末で試す)。
- 実装: `modules/golem-cli/test/repl/terminal.rb:1` (`# R4/R7: Run with ruby terminal.rb /absolute/path/to/golem on a POSIX terminal.`)。
- 根拠: `rg -n --hidden 'terminal\.rb' . -g '!docs/adr/**'` は `terminal.rb` 自身の 1 行だけを返した。
- 根拠: `modules/golem-cli/test/CommandsSpec.hs:122-160` の testCase の名前は R1、R2、R3、R4、R5、R6 だけで、R7 は無い。
- 問題: Tab の補完、Ctrl-C の取り消し、継続プロンプトを確かめるのは手で動かす Ruby のスクリプトだけで、cabal のテストにも CI にも入っていない。
- 問題: R7 を名前に持つテストが無い (注釈にあるだけ)。
- 手元の確かめ: サンドボックスの外で `ruby terminal.rb <ビルドした golem>` を動かすと終了コード 0 だった (サンドボックスの中では `PTY.spawn: can't get Master/Slave device` で動かない)。

### 4. テスト自身の名前に ADR の番号が無いもの

- 観点: ADR 違反 (テストの名前)。
- 重大度: 低。
- [ADR 0347](../adr/0347-revise-complete-manifest-values-and-manuscript-expressions.md): `modules/golem-lsp/test/EditingSpec.hs:178,185,193,198,208,212,218` は `"M1 expression operands ..."`、`"T1 manifest ..."`、`"M1 D1 ..."` で、`modules/golem-lsp/test/TomlSpec.hs:112,124` は `"T1 ..."` である。
- 根拠: `git grep -n -E "ADR 0347|adr0347" cf244a2b -- modules scripts .github` は 0 件だった。
- [ADR 0348](../adr/0348-revise-emet-expression-repl.md): `modules/golem-cli/test/CommandsSpec.hs:122-160` は `"R1/R3/R4: ..."` などで、ADR の番号は testGroup の `"Emet REPL (Golem ADR 0348)"` (`:121`) にだけある。
- [ADR 0349](../adr/0349-retry-ci-job-list-on-rate-limit.md): `scripts/ci/test-warning-job-list.sh:83-88` は `'I1 one job'` などで、`scripts/ci/test.sh:773` の名前は `"CI warning job list I1-I4"` である。
- [ADR 0350](../adr/0350-omit-page-link-annotations-from-pdf-x-4.md): `modules/golem-pdf/test/Main.hs:476` は `"X1/X2/X3/X4: print links ... (Golem ADR 0350)"` で、番号が先頭に無く、四つを一つのテストにまとめている。
- [ADR 0353](../adr/0353-reject-footnotes-in-too-short-columns.md): `modules/golem-cli/test/Main.hs:318-319` は testGroup が `"Golem ADR 0353 I1/I2: ..."` で、中の testCase は `"capacities 1 and 2 report G07125 ..."` である。
- [ADR 0343](../adr/0343-revise-retire-table-src.md): `modules/golem-lsp/test/TableWatchSpec.hs:80` は `"ADR 0343: only a positional table path is watched"` で、不変条件の番号が無い。
- 問題: adr スキルの「入れ子の外側の名前に ADR を書いても、内側の名前に書くことを省かない」と、名前の先頭に `ADR <NNNN> I<番号>: ` を置く決まりに合わない。
- 補足: [ADR 0347](../adr/0347-revise-complete-manifest-values-and-manuscript-expressions.md)、[0348](../adr/0348-revise-emet-expression-repl.md)、[0350](../adr/0350-omit-page-link-annotations-from-pdf-x-4.md) は、ADR 自身が T1、M1、D1、R1〜R7、X1〜X4 という番号を使っている (`0347:76-78`、`0348:128-134`、`0350:47-50`)。ADR は変えられないので、直すなら新しい ADR が要る。

### 5. 二つ以上の番号の区切りが決まりの形でないもの

- 観点: ADR 違反 (テストの名前)。
- 重大度: 低。
- 根拠: `rg -n '"ADR 03(4[1-9]|5[0-7]) I[0-9]+( I[0-9]+)+:' modules -g '*.hs' | wc -l` は 11 だった (例: `modules/golem-eval/test/RangeSpec.hs:181` の `"ADR 0342 I1 I2: ..."`、`modules/golem-driver/test/DiagnosticsSpec.hs:59` の `"ADR 0344 I2 I3: ..."`)。
- 根拠: `modules/golem-fmt/test/Main.hs:293` は `"Golem ADR 0354 I1/I2: ..."`、`modules/golem-cli/test/FmtTableSpec.hs:84` は `"Golem ADR 0354 I1-I3: ..."`、`modules/golem-eval/test/FunctionSpec.hs:90,102` は `"Golem ADR 0351 I7-I8: ..."` と `"Golem ADR 0351 I6-I7: ..."` である。
- 根拠: `modules/golem-driver/test/PageElementsSpec.hs:127,140,164` と `modules/golem-project/test/Main.hs:1009` は、番号を末尾の `(ADR 0344 I1)` に置いている。
- 問題: adr スキルの区切りは `, ` (`ADR 0124 I1, I2: …`) で、番号は名前の先頭に置く。
- 補足: 接頭辞は `ADR NNNN`、`Golem ADR NNNN` の二つが混ざっている (スキルのモノレポの形は `root ADR NNNN`)。プロジェクトの CLAUDE.md は「番号を入れる」としか書いていないので、接頭辞の違いは指摘に数えていない。

### 6. [ADR 0345](../adr/0345-revise-unitless-zero-in-length-fields.md) の I2 を名前に持つテストが無く、置き換えられた [ADR 0319](../adr/0319-unitless-zero-in-length-fields.md) の名前のテストが残っている

- 観点: ADR 違反 (不変条件のテスト、テストの名前)。
- 重大度: 中。
- ADR: `docs/adr/0345-revise-unitless-zero-in-length-fields.md:78-79` (I1、I2)、`:96-99` (テスト名に不変条件の番号を付ける)。
- 根拠: `git grep -n "ADR 0345" cf244a2b -- modules` のテストは、I1 が `modules/golem-project/test/Main.hs:1031` の 1 件 (傍注の `width` と `gap` だけ)、I3 と I4 が `modules/golem-eval/test/FileSpec.hs:1660,1667,1673,1679` と `modules/golem-eval/test/NaturalSpec.hs:104` で、I2 は 0 件である。
- 根拠: 入口の表のほかの欄と、不正な綴り (`+0`、`00`、`0.0`) を確かめるテストは `modules/golem-project/test/Main.hs:898` (`"ADR 0319 I1 I2: unitless zero is a typed zero"`)、`:906` (`"ADR 0319 I1: zero reaches style length fields"`)、`modules/golem-preflight/test/Main.hs:311` (`"ADR 0319 I1: preflight length accepts typed zero"`) である。
- 根拠: `docs/adr/0319-unitless-zero-in-length-fields.md:3` は `Status: superseded [{"by":["docs/adr/0345-..."],"part":null}]` である。
- 問題: adr スキルの「後の ADR が前の ADR の不変条件を変えたときは、テストの名前を変えた側の ADR の番号に付け直す」に合わない。

### 7. [ADR 0345](../adr/0345-revise-unitless-zero-in-length-fields.md) のテスト設計にある確かめのうち、テストに見つからないもの

- 観点: ADR 違反 (テスト設計)。
- 重大度: 低。
- ADR: `docs/adr/0345-revise-unitless-zero-in-length-fields.md:50-56` (入口の表)、`:91` (合計が 2 の 63 乗から 1 を引いた値)、`:96,101` (各欄で整数と文字列のゼロを読む、CSS 生成後の値まで調べる)。
- 根拠: `rg -n 'aki 0|aki -0' modules/*/test`、`rg -n 'column-gap = 0|top = 0|\[notes.rule\][^"]*= 0' modules/*/test` で、`[aki 0]`、`[page.grid]` の `column-gap` と `position`、`[notes.rule]` の間隔を整数のゼロで読むテストは見つからなかった (`[index] column-gap = 0` は `modules/golem-project/test/Main.hs:914` にある)。
- 根拠: `rg -n '0319|0345' modules/golem-html/test modules/golem-epub/test` は 0 件で、CSS の `0` を [ADR 0345](../adr/0345-revise-unitless-zero-in-length-fields.md) として確かめるテストは無い。
- 根拠: `modules/golem-eval/test/FileSpec.hs:1667-1672` は上限を超える側だけを確かめ、合計がちょうど 2 の 63 乗から 1 を引いた値で IR が一件になる側が無い。
- 振る舞いは手元で合っていた: tempest の写しで `[page] bleed = 0`、`bleed = "-0"`、`position = { top = 0, gutter = "0" }`、`[notes.rule]` の `space-before = 0`、`[lists] gap = 0`、`[index] column-gap = "0"`、`@style-def paragraph zz indent=0 first-line-indent=-0` は `golem check` が終了コード 0 だった。
- 振る舞いは手元で合っていた: `bleed = 0.0`、`"+0"`、`"00"`、`""`、`"1"` は G03006、`@figure ... width=0` は G02133、`@blank-line 9223372036854775806` と `@blank-line 1` の連続は終了コード 0、さらに `@blank-line 1` を足すと三つめの引数に G02091 だった。
- 振る舞いは手元で合っていた: `golem build --target html` の `style.css` は `p.ps-zz { ... padding-inline-start: 0; text-indent: 0; ...}` だった (`first-line-indent=0pt` も `0`)。

### 8. [ADR 0346](../adr/0346-revise-named-layout-values.md) の I4 の「preflight.toml からは見えない」を確かめるテストが無い

- 観点: ADR 違反 (不変条件のテスト)。
- 重大度: 低。
- ADR: `docs/adr/0346-revise-named-layout-values.md:91` (I4)、`:105` (境界の表)、`:110` (プリフライトからは引けないことを検査する)。
- 根拠: I4 を名前に持つテストは `modules/golem-eval/test/DiagnosticSitesSpec.hs:51` (`"ADR 0346 I4: an undefined layout value points at its use"`) だけで、未定義の名前の位置を確かめる。
- 根拠: `rg -n 'values\.|"indent"' modules/golem-preflight/test/Main.hs` は 0 件だった。
- 振る舞いは手元で合っていた: `style.toml` に `[values.length] indent = "3mm"` を置き、`preflight.toml` に `[bleed-size] min = "indent"` と書くと、`./preflight.toml:2:7: error[G09102]: min の値が正しくありません: indent（長さは 3mm や 0.25pt のように書きます）` だった。

### 9. [ADR 0346](../adr/0346-revise-named-layout-values.md) の宣言の右辺の未定義の名前と種類違いが G03256 になる

- 観点: ADR 違反 (実装すること)、文書との食い違い。
- 重大度: 低。
- ADR: `docs/adr/0346-revise-named-layout-values.md:51` (宣言の右辺でも使用箇所でも名前を参照できる)、`:66-67` (宣言値の誤りは G03256、参照先がない場合は G03257、種類が違う場合は G03258 を参照位置に出す)。
- 根拠: `[values.length]` に `a = "missing"` だけを書くと `style.toml:21:5: error[G03256]: 値の名前がありません: missing` だった。
- 根拠: `[values.aki] h = "二分"` と `[values.length] a = "h"` では `style.toml:23:5: error[G03256]: 値 h の種類が違います: 要求 length、実際 aki` だった。
- 根拠: 使用箇所では `indent = "x"` が `error[G03257]: 値の名前がありません: x` で、同じ文面が二つのコードで出る。
- 問題: ADR の 66〜67 行めは、参照先がない場合と種類が違う場合を、宣言の右辺かどうかで分けていない。
- 問題: `docs/diagnostics.md` の G03256 の「意味」と「主な原因」は、宣言の中の未定義の名前を挙げていない。`docs/specifications.md:2340` は「未定義の参照は G03257、違う種類の参照は G03258」と書く。
- 補足: `docs/audits/2026-11-17-diagnostic-cause-audit.md` の概要は、この二つを G03257 と G03258 に移す提案として挙げている。

### 10. 仕様書が [ADR 0348](../adr/0348-revise-emet-expression-repl.md) の振る舞いの多くを書いておらず、コマンドの表に `golem repl` が無い

- 観点: 仕様書と README が ADR と合っているか。
- 重大度: 中。
- ADR: `docs/adr/0348-revise-emet-expression-repl.md:33-38` (要求の集合は空、プロンプト、`=> `)、`:55` (エラーの `[start,end)`)、`:58-61` (EOF、終了コード 0、1、2、パイプ)、`:63-65` (値の表記)、`:120` (BOM、CR、不正な UTF-8)。
- 根拠: `docs/specifications.md:7559-7568` の 9 行が REPL の記述のすべてで、プロンプトの文字列、`=> `、終了コード 0 と 2、エラーのバイト範囲、値の表記 (エスケープ、`(Just 2)`、`<function>`)、要求の集合が空であること (E05101) が無い。
- 根拠: `rg -n '^\| `golem ' docs/specifications.md` の表 (`:8524-8536`) に `golem repl` の行が無い (`golem stats` は `:8528` にある)。
- 根拠: `README.md:145-160` のコマンドの表に `golem repl emet` と `golem stats` の行が無い (本文の `README.md:31` と `:374-375` にはある)。
- 問題: 仕様書から REPL の振る舞いを作り直せない。
- 実装は手元で ADR と合っていた: パイプの入力 `(1` は `E01101 [2,2)` で終了コード 1、`1 + )` の後の `4` は `E01100 [4,5)` の後に `4`、`File.read "secret.txt"` は `E05101 [0,22)`、文字列は `"a\tb\n\u{1}\\ \""` と表示、関数値は `<function>`、`Just 2` は `(Just 2)`、不正な UTF-8 は G01001、`golem repl` と `golem repl lua` は終了コード 2 だった。

### 11. [ADR 0348](../adr/0348-revise-emet-expression-repl.md) のテスト設計のうち、テストに見つからないもの

- 観点: ADR 違反 (テスト設計)。
- 重大度: 低。
- ADR: `docs/adr/0348-revise-emet-expression-repl.md:156` (`golem repl --help` の言語一覧を検査する)、`:158` (R5 は同じ関数と引数を原稿と REPL から呼ぶ)、`:161` (R6 は型の別名、データ型、循環を調べる)。
- 根拠: `rg -n '"repl"' modules/*/test -g '*.hs'` は `modules/golem-cli/test/CommandsSpec.hs:152,167` の `["repl", "emet"]` だけを返し、`--help` を渡すテストが無い。
- 根拠: R5 のテスト (`modules/golem-cli/test/CommandsSpec.hs:127-146`) は REPL だけを動かし、原稿からの呼び出しと比べていない。
- 根拠: R6 のテスト (`:147-159`) は import の失敗と再定義の失敗だけで、型の別名、データ型、循環を入力していない。

### 12. [ADR 0350](../adr/0350-omit-page-link-annotations-from-pdf-x-4.md) の境界の表の入力のうち、PDF/X-4 で自動のテストに無いもの

- 観点: ADR 違反 (テスト設計)。
- 重大度: 低。
- ADR: `docs/adr/0350-omit-page-link-annotations-from-pdf-x-4.md:54,56` (リンクがない 1 ページ、行をまたぐリンク、目次としおりのある複数ページ)、`:62-64` (生成した PDF のページ辞書と構造ツリーをたどる、変更前後のページ画像と位置付きの抽出テキストを比べる)。
- 根拠: X1〜X4 のテストは `modules/golem-pdf/test/Main.hs:476-496` の 1 件で、手で組んだ 1 ページの文書をライターに渡す。
- 根拠: `rg -n 'X-4|PdfX|intent' modules/golem-driver/test/*.hs | rg -i 'link|annot'` は、[ADR 0393](../adr/0393-references-in-ruby-segments-without-readings.md) のテスト (`modules/golem-driver/test/TaggedPdfSpec.hs:236`) だけを返した。
- 問題: 原稿から組んだ PDF/X-4 で、行をまたぐリンク、目次、しおりを確かめるテストが見つからない。
- 振る舞いは手元で合っていた: tempest の写しに行をまたぐ `[link ...]`、`[note: ...]`、`@toc` を足し、`[color] intent` を付けて `golem build --target pdf` すると、`/Subtype /Link` 0 行、`/Annots` 0 行、`/Type /OBJR` 0 行、`/S /URI` 0 行、`/Outlines` 2 行、`/S /Span` 19 行だった。
- 振る舞いは手元で合っていた: `intent` を外すと `/Subtype /Link` 20 行、`/Type /OBJR` 19 行、`/S /URI` 2 行だった。

### 13. [ADR 0341](../adr/0341-revise-retire-listing-src.md)〜0344 の「リリースノートに削除手順を載せる」を受ける場所が無い

- 観点: ADR 違反 (実装すること)。
- 重大度: 低。
- ADR: `docs/adr/0341-revise-retire-listing-src.md:42`、`docs/adr/0342-revise-retire-dash-line-ranges.md:46`、`docs/adr/0343-revise-retire-table-src.md:37`、`docs/adr/0344-revise-retire-legacy-style-formats.md:37`。
- 根拠: `rg -n 'G02065|G02108|G02129|G0311[4-7]|旧記法|旧コード' docs/roadmap.md` は 0 件だった。
- 根拠: `docs/compatibility.md:60` は一般の手順として「リリースノートに、その行を消すよう書く」と書くが、v1.0.0 のノートの下書きは見つからない。
- 問題: v1.0.0 はまだ出ていないので違反ではないが、七つの廃止コード (G02065、G02108、G02129、G03114〜G03117) を `silence-notices` から消す手順をノートに載せることが、ロードマップにも残っていない。

## 未実装 (違反に数えない)

- [ADR 0351](../adr/0351-prove-parser-formatter-round-trips.md) (`docs/adr/0351-prove-parser-formatter-round-trips.md:3` は `superseded-pending`、置き換えは「不変条件 9 の先頭の連続 BOM」だけ)。
- `find . -name '*.lean' -not -path './dist-newstyle/*'` は 0 件で、Lean のモデル (`:30-44`) は無い。
- 名前に番号を持つテストは I2 (`modules/golem-fmt/test/Main.hs:178`)、I6、I7、I8 (`modules/golem-eval/test/FunctionSpec.hs:90,102,113,118,125`、`modules/golem-syntax/test/Main.hs:366,374`) だけで、I1、I3、I4、I5、I9、I10 は 0 件である。
- 文法からの生成器、全列挙、PR と毎晩のジョブ、artifact の保存 (`:91-111`) は確かめていない (未確認)。
- [ADR 0352](../adr/0352-prove-pagination-in-lean.md) は `accepted-pending` で範囲の外である。

## 問題が見つからなかった項目

- [ADR 0341](../adr/0341-revise-retire-listing-src.md): `modules/golem-eval/src/Golem/Eval/File.hs:2217-2236` が ADR の順 (重複の `src=` は G02077、二つのパスは G02253、`src=` だけは G02250、無しは G02036) で、CLI でも `src=a.txt` は G02250、`a.txt src=a.txt` と `a.txt a.txt` は G02253、`src=a.txt src=a.txt` は G02077 だった。I1、I2、I4 のテストは通った。
- [ADR 0342](../adr/0342-revise-retire-dash-line-ranges.md): CLI で `1`、`1...1`、`"1...3, 5...7"` は成功、`1-2` と `1-2,4-5` と `highlight=1-2,4-5` と式の `"1-2"` は G02251 が一件、`3--1` は G02110、`"1.,.3, 5..,7"` は G02105、`5..7` は G01100、`[= 0]` は G02037、`[= 0 - 1]` は G02103 だった。I1、I2、I4 のテストは通った。
- [ADR 0343](../adr/0343-revise-retire-table-src.md): I1、I2、I4 のテストは通り、`docs/specifications.md:4821`、`docs/markup.md:285`、README.md:297 が合っている。
- [ADR 0344](../adr/0344-revise-retire-legacy-style-formats.md): I1〜I5 のテストは通り、`docs/diagnostics.md` は G03114〜G03117 が「廃止」、G03250〜G03253 が「エラー、使用中」である。
- [ADR 0341](../adr/0341-revise-retire-listing-src.md)〜0344 の「v1.0.0 より前のプレリリースでは notice」: `docs/roadmap.md:14` と `docs/compatibility.md:63` が rc4 の次を 1.0.0 としているので、main のエラー化は食い違わない。
- [ADR 0345](../adr/0345-revise-unitless-zero-in-length-fields.md) の行アキ: `@blank-line 0` の連続は G02254 が一件、`0,2,0` は診断なし、`1,0,2` は G02094 だけ、式の 0 も G02254 だった。`[notes.rule]` の `start-indent` は G03006 のままだった。
- [ADR 0346](../adr/0346-revise-named-layout-values.md): 重複は G03254、名前の字面は G03255、未定義の参照は G03257、種類違いは G03258 (`@style-def` でも)、絶対長の欄への `zw` の名前は直接書いたときと同じ G03006 だった。I1、I2、I3、I5 のテストは通った。
- [ADR 0347](../adr/0347-revise-complete-manifest-values-and-manuscript-expressions.md): T1、M1、D1 のテスト (`modules/golem-lsp/test/EditingSpec.hs`、`TomlSpec.hs`) は通った。README.md と `docs/specifications.md` に ADR へのリンクがある。
- [ADR 0349](../adr/0349-retry-ci-job-list-on-rate-limit.md): I1〜I4 のシェルのテストは通った。境界 (解除が 10 秒後なら 111 秒めに再取得、期限ちょうどと一秒後は再問い合わせなし) が `scripts/ci/test-warning-job-list.sh:83-88` にある。
- [ADR 0350](../adr/0350-omit-page-link-annotations-from-pdf-x-4.md) の文書: `docs/specifications.md:124,6423`、`README.md:319`、`manual/chapters/03-markup.gm:862-863`、`docs/audits/2026-11-11-pdf-x-4-page-links.md`、`docs/roadmap.md:121`、[ADR 0267](../adr/0267-pdf-bookmarks-and-links-inside-the-document.md)、[0221](../adr/0221-check-iso-15930-7-for-link-annotations-before-rc4.md)、[0226](../adr/0226-move-the-iso-15930-7-check-to-before-v1.md) のステータスの行のリンクがある。PDF/A と PDF/UA の試料は `scripts/ci/conformance-pdfs.sh:23,48-49` が出力インテント付きで組む。
- [ADR 0353](../adr/0353-reject-footnotes-in-too-short-columns.md): CLI で容量 1 と 2 は G07125 で PDF なし (メッセージは ADR の文面どおり)、容量 3 は成功、`@page-lines -1` は成功、脚注なしの容量 1 と 2 は成功だった。I1、I2 のテストは通った。
- [ADR 0354](../adr/0354-remove-leading-boms-from-table-files.md): I1〜I3 のテスト (`modules/golem-fmt/test/Main.hs:196,293,298`、`modules/golem-cli/test/FmtTableSpec.hs:84`) は通った。
- [ADR 0355](../adr/0355-manuscript-statistics.md): `inv1`〜`inv5` のテストは通った。CLI で、空は 0 ページ、家族の絵文字は 1 文字 0 ワード 1 ページ、41 字の 40 字×1 行は 2 ページ、40 字の 32 段落は 1 ページ (既定では 4 ページ)、空行を足すと 2 ページ、寸法の 0、負数、小数は「正の整数を指定してください」だった。境界は `modules/golem-cli/cbits/stats.c` の同梱の libgrapheme で数える。
- [ADR 0356](../adr/0356-diagnostic-cause-audit.md): `docs/audits/2026-11-17-diagnostic-cause-audit.md` が候補 62 件、単一 359 件、未調査 2 件を記録し、`docs/roadmap.md:63` に分割の項目がある。改番はしていない。
- [ADR 0357](../adr/0357-validate-embedded-cff.md): `inv1_validate_embedded_cff_property`、`_case_1`、`_case_2` (`modules/golem-font/test/CffSpec.hs:30,40,47`、`modules/golem-driver/test/PdfSpec.hs:259,264`) は通った。`docs/diagnostics.md` の G08107 は「エラー、使用中」である。
- ステータスの行: 範囲の ADR はどれも `Status:` の行を一つ持つ ([ADR 0387](../adr/0387-update-adr-guard-to-v0.13.1-and-migrate-status-lines.md) で移した形)。

## 未確認

- CI での結果: `gh run list --commit cf244a2b...` は、サンドボックスの中で TLS の検証に失敗して取れなかった。
- テストスイートの全件: 動かしたのは上のパターンに合うテストだけで、各スイートの全件は動かしていない。
- [ADR 0347](../adr/0347-revise-complete-manifest-values-and-manuscript-expressions.md) の T1 の全欄: `page-numbering.style` の 12 語は `modules/golem-lsp/test/TomlSpec.hs:114` が `arabic` を含むことだけを確かめており、集合の一致は手元でも確かめていない。
- [ADR 0345](../adr/0345-revise-unitless-zero-in-length-fields.md) のアキ量のセットの規則の量、`[composition.ruby] overhang` の整数のゼロ以外の欄、EPUB の CSS は動かしていない。
- [ADR 0346](../adr/0346-revise-named-layout-values.md) の「文字サイズが 10 pt と 12 pt の箇所で `1zw`」の PDF での寸法と、LSP の複数ファイルの名前変更は、テストが通ったことだけを確かめた。
- [ADR 0350](../adr/0350-omit-page-link-annotations-from-pdf-x-4.md) の X2 の変更前後のページ画像の比較は、行われた記録を確かめていない。
- [ADR 0354](../adr/0354-remove-leading-boms-from-table-files.md)、[0357](../adr/0357-validate-embedded-cff.md) は、テストが通ったことと文書の対応だけを確かめ、CLI での境界の表は動かしていない。

---

## root [ADR 0358](../adr/0358-font-instance-selection.md)〜0375

モデルは Fable 5.2 (claude-fable-5-2) である。
推論の強さは指定を受けておらず、自分では分からない (モデルの既定と思われる)。
読んだコミットは cf244a2b5cc09cf117bd5f4c8e37ce40f978f706 である。
リポジトリは /Users/tett23/repositories/src/github.com/tett23/golem である。
以下の相対パスは、どれもこのリポジトリのルートからの、上のコミットでのパスである。

## 結論

重大度が高と中の指摘は無い。
低の指摘が 6 件ある。
14 本とも、ADR のテスト設計が挙げる名前のテストがすべてあり、名前で絞った実行で通った。
14 本とも、ステータスの行は `Status: accepted` で、後の ADR による replace は無い。
0367 を参照する root [ADR 0389](../adr/0389-diagnose-caption-and-sidenote-indents-that-leave-no-width.md) と、0360 を参照する root [ADR 0393](../adr/0393-references-in-ruby-segments-without-readings.md) は、どちらも足す側の ADR である。
14 本とも「受けいれ条件」の節を持たないので、手で確かめる手順の観点は当たらない。

## 動かしたこと

コミットを `git archive cf244a2b | tar -x` でスクラッチパッドに写し、そこで cabal を動かした。
写した先は /private/tmp/claude-501/-Users-tett23-repositories-src-github-com-tett23-golem/cb1691be-4aee-4682-b663-ec1ca710eb2d/scratchpad/audit-cf244a2b である。
`cabal build golem-font-test golem-pdf-test golem-assemble-test golem-driver-test golem-layout-test golem-epub-test golem-eval-test golem-html-test golem-project-test` を動かした。
九つのテストの実行ファイルはできたが、cabal は最後に `/Users/tett23/.cabal/logs/build.log: withFile: permission denied` を出して終了コード 1 で終わった (サンドボックスの書き込みの制限)。
各モジュールのディレクトリで、実行ファイルに `-p '/ADR 0358/ || /ADR 0359/ || ... || /ADR 0375/'` (14 本ぶん) を渡して動かした。
出力は次のとおりで、失敗は無い。

| スイート | 出力 |
| --- | --- |
| golem-font-test | All 10 tests passed (0.17s) |
| golem-pdf-test | All 6 tests passed (55.08s) |
| golem-assemble-test | All 1 tests passed (0.04s) |
| golem-layout-test | All 13 tests passed (20.51s) |
| golem-epub-test | All 3 tests passed (0.10s) |
| golem-eval-test | All 15 tests passed (0.43s) |
| golem-html-test | All 6 tests passed (0.08s) |
| golem-project-test | All 11 tests passed (0.50s) |
| golem-driver-test | All 41 tests passed (0.69s) |

`inv1_` を名前に持つテストの OK の数は、ADR ごとに次のとおりである。
0358 が 4、0359 が 4、0360 が 5、0361 が 3、0362 が 3、0363 が 3、0364 が 3、0367 が 3、0368 が 3、0369 が 7、0370 が 3、0371 が 3、0373 が 4、0375 が 4 で、合わせて 52 である。
`adr-guard --help` (0.13.1) は、行頭の `Status:` もステータスの行として認めると書いている。

## 指摘

### 1. docs/diagnostics.md の G03006 の項に、[ADR 0358](../adr/0358-font-instance-selection.md) と [ADR 0373](../adr/0373-heading-block-alignment.md) が足した条件が無い

- 観点は、仕様書類と ADR の一致である。
- 重大度は低である。
- 根拠の一つめは docs/specifications.md:4375 で、`instance` が文字列でない場合と `axes` が数の表でない場合を G03006 と書く ([ADR 0358](../adr/0358-font-instance-selection.md) の「実装すること」、docs/adr/0358-font-instance-selection.md:17)。
- 根拠の二つめは docs/specifications.md:3906 で、`block-align` のほかの値を G03006 と書く (docs/adr/0373-heading-block-alignment.md:15)。
- 実装はそのとおりで、modules/golem-project/test/Main.hs:1252 と modules/golem-project/test/Main.hs:991 のテストが G03006 を確かめ、通った。
- docs/diagnostics.md:6355 の「条件を加えた ADR」の並びのうち 0340 番台より後のものは、`grep -o -E "adr/0(3[4-9][0-9])-[a-z-]+"` で 0367 と 0375 だけが出た。
- docs/diagnostics.md:6356 から 6392 を `instance|axes|block-align` で探しても、一致は無かった。
- `grep -n "0358\|0373" docs/diagnostics.md` は、G08110 から G08112 の項の 12226、12256、12286 行だけを出した。
- 問題は、G03006 の項が条件を足した ADR を並べる形なのに、この二本が並びにも「主な原因」にも無いことである。

### 2. docs/roadmap.md に、実装を終えた [ADR 0369](../adr/0369-ruby-reading-style.md) の項目が残っている

- 観点は、仕様書類と ADR の一致である (ロードマップは頼まれた三つの文書の外だが、見つけたので書く)。
- 重大度は低である。
- 根拠は docs/roadmap.md:86 の「**ルビの読み**：読みだけに文字スタイルを指定できる。Golem [ADR 0369](../adr/0369-ruby-reading-style.md)」である。
- docs/roadmap.md の冒頭は「実装を終えたら、その項目をこの文書から消し、振る舞いを仕様書に書く」と決めている。
- 同じ並びのほかの項目は「（未実装）」か「（未決）」を持つが (docs/roadmap.md:83 から 85)、この項目は印を持たない。
- [ADR 0369](../adr/0369-ruby-reading-style.md) は accepted で、docs/specifications.md:4173 から 4182 に振る舞いがあり、テストも通った。
- 問題は、もう在る振る舞いが、まだ無いものの一覧に載っていることである。

### 3. `I1` を名前に持つが、I1 の述語を確かめないテストがある

- 観点は、テストの名前である。
- 重大度は低である。
- [ADR 0375](../adr/0375-printings-format.md) の I1 は「明示書式で生成する行数は言語にかかわらず発行履歴の項目数に等しい」である (docs/adr/0375-printings-format.md:30)。
- modules/golem-eval/test/FileSpec.hs:2139 の `ADR 0375 I1: braces that do not pair are G03006` は、書式の読み込みのエラーだけを確かめる。
- 同じく modules/golem-eval/test/FileSpec.hs:2136、2144、2149、2154 は、十進数字、エスケープ、メッセージの文言、書式を省いた本の G02076 を確かめる。
- [ADR 0362](../adr/0362-unbreakable-spacing.md) の modules/golem-layout/test/UnbreakableSpacingSpec.hs:85 と、[ADR 0368](../adr/0368-regex-style-scope.md) の modules/golem-eval/test/RegexStyleSpec.hs:103 も、I1 の述語そのものではなく「実装すること」のほかの文を確かめる。
- 同じリポジトリには、不変条件でないテストを `ADR 0358: ...` のように番号なしで名づける例がある (modules/golem-font/test/InstanceSpec.hs:61)。
- 問題は、番号から不変条件のテストを引くと、関係の無いテストが混ざることである。
- これは読んで判断したことで、名前を機械的に検査してはいない。

### 4. `[printings]` の `format` のエラーの文言が、[ADR 0375](../adr/0375-printings-format.md) の書き方と違う書き方を勧める

- 観点は、「実装すること」が実装に表れているかである。
- 重大度は低である。
- ADR は「文字としての波括弧は {{ と }} で書く」と決める (docs/adr/0375-printings-format.md:21)。
- modules/golem-numerals/src/Golem/Numerals/Format.hs:86 の文言は「閉じていない { があります。文字の { は \\{ と書きます」である。
- modules/golem-eval/test/FileSpec.hs:2152 が、`[printings]` の `format` でこの文言が出ることを固定している。
- `{{` も `\{` も受け付けるので (docs/specifications.md:1287 と 1288、FileSpec.hs:2141 のテストが通った)、振る舞いの誤りではない。
- 問題は、ADR が決めた書き方を、この書式のエラーの文言が案内しないことである。

### 5. `_property` のテストの一部が、手で選んだ少数の入力だけを回す

- 観点は、不変条件のテストである。
- 重大度は低である。
- ADR のテスト設計は、`inv1_..._property` で不変条件の述語を検査すると書く (たとえば docs/adr/0364-running-head-folio-style.md:35 付近の「テスト設計」)。
- modules/golem-driver/test/PageElementsSpec.hs:356 ([ADR 0364](../adr/0364-running-head-folio-style.md)) は、ノンブルの指定 3 通りと柱の指定 3 通りの 9 通りだけである。
- modules/golem-driver/test/ParagraphSpec.hs:292 ([ADR 0363](../adr/0363-list-marker-style.md)) は、文字スタイル 4 つと原稿 7 つである。
- modules/golem-driver/test/PageElementsSpec.hs:1226 ([ADR 0371](../adr/0371-sidenote-marker-style.md)) は、文字スタイル 4 つと原稿 5 つである。
- modules/golem-driver/test/PdfSpec.hs:849 ([ADR 0369](../adr/0369-ruby-reading-style.md)) は、文字スタイル 6 つと原稿 6 つである。
- ほかの ADR は、乱数の性質テストか、小さな入力の総当たりである (0358 は Hedgehog の 100 件、0362 は 13 字の 1 字から 3 字の列の総当たり、0367 は字下げの組の総当たり、0370 は 5 箱までの総当たり、0375 は 168 通り)。
- 問題は、この 4 本では「どの入力でも成り立つ」ことの確かめが、選んだ例の範囲に留まることである。
- 4 本とも通っており、反例は見つけていない。

### 6. 不変条件の節の形が、adr スキルの「番号とテストの名前」の形と違う

- 観点は、番号とテストの名前である。
- 重大度は低である。
- 14 本とも、不変条件を `1.` と書き、境界の入力の表の列は「境界の入力」「期待する結果」の二つである (たとえば docs/adr/0358-font-instance-selection.md:30 と 32、docs/adr/0373-heading-block-alignment.md:27 と 29)。
- adr スキルは、番号を `I1` とし、表に「不変条件」の列を置くと決める (/Users/tett23/.claude/skills/adr/SKILL.md:120 から 128)。
- 同じコミットの root [ADR 0389](../adr/0389-diagnose-caption-and-sidenote-indents-that-leave-no-width.md)、[0393](../adr/0393-references-in-ruby-segments-without-readings.md)、[0395](../adr/0395-bring-the-pull-request-ci-under-five-minutes.md) は `- I1:` の形で書いている。
- プロジェクトの CLAUDE.md の「一つずつ番号を付けて書き、境界の入力の表を添える」には合っている。
- テストの側は 14 本とも `ADR NNNN I1: inv1_...` で、番号と対応が取れる。
- コミット済みの ADR は変えられないので、直す対象は無く、記録だけである。

## 問題が無かったこと

- テストの名前の形: 14 本とも `ADR NNNN I1: inv1_<名前>_property` か `_case_N` で、このリポジトリで最も多い形である (`testCase "ADR NNNN In:` が 275 件、`root ADR NNNN In:` は 2 件)。
- モジュールの ADR の番号は最大で golem-layout の 0049 なので、`ADR 0358` から `ADR 0375` はモジュールの ADR と取り違えない。
- [ADR 0358](../adr/0358-font-instance-selection.md): 名前と軸の解決、拒否、三つの用途の座標の一致、可変の表を持たないサブセット、CFF2 の G08019 が、modules/golem-font/test/InstanceSpec.hs:28 から 104 と modules/golem-driver/test/FontInstanceSpec.hs:94 にあり、通った。docs/specifications.md:4340 から 4392 と README.md:212 は ADR と合う。
- [ADR 0359](../adr/0359-imported-content-separators.md): 連結長が長さの和と n − 1 の和であること、256 MiB の三つの境界、展開の合計が先に失敗することが、modules/golem-pdf/test/SecuritySpec.hs:446 から 470 にあり、通った。docs/specifications.md:4622 から 4629、README.md:284、docs/diagnostics.md:11721 付近は合う。
- [ADR 0360](../adr/0360-ruby-base-references.md): RB の下の Reference の数と順、読みが RB に入らないことが、modules/golem-driver/test/TaggedPdfSpec.hs:203 から 219 にあり、通った。docs/specifications.md:115 と 1599 は合う。
- [ADR 0361](../adr/0361-epub-byte-determinism.md): 別のディレクトリ、別の時刻、素材の順の違いでバイト列が同じこと、ルートのパスを含まないことが、modules/golem-epub/test/PackageSpec.hs:129 から 148 にあり、通った。docs/specifications.md:1313 から 1320 と 1428、README.md:7 は合い、「EPUB は保証しない」という古い文は残っていない。scripts/env-determinism/check.sh:224 は `build/` の下の全ファイルのハッシュを比べる。
- [ADR 0362](../adr/0362-unbreakable-spacing.md): 伸びだけを 0 にし幅と縮みを保つこと、独自のセットにも当てること、禁則と同じ判定 (`pairKept`) を使うことが、modules/golem-layout/src/Golem/Layout/Japanese.hs:2378 から 2386 と modules/golem-layout/test/UnbreakableSpacingSpec.hs:37 から 88 にあり、通った。docs/specifications.md:5811 から 5816 と README.md:261 は合う。
- [ADR 0363](../adr/0363-list-marker-style.md): 印だけに当たること、当てた後の幅で測ること、番号の前後の文字も印に含むことが、modules/golem-driver/test/ParagraphSpec.hs:292 から 325 にあり、通った。docs/specifications.md:3589 と docs/diagnostics.md:6561 は合う。
- [ADR 0364](../adr/0364-running-head-folio-style.md): 柱とノンブルの独立、省略のときの既定、奇数と偶数のページで同じ指定が、modules/golem-driver/test/PageElementsSpec.hs:356 から 390 にあり、通った。docs/specifications.md:4110 から 4112 と README.md:231 は合う。
- [ADR 0367](../adr/0367-caption-sidenote-paragraphs.md): 各行の幅、先頭行だけの字下げ、行数の反映、組み込みの 0 の字下げが、modules/golem-driver/test/CaptionSidenoteParagraphsSpec.hs:92 から 135 と modules/golem-project/test/Main.hs:1828 から 1864 にあり、通った。表のキャプションはコードブロックと同じ `captionLinesOf` を通る (modules/golem-typeset/src/Golem/Typeset/Flow.hs:3103 から 3113)。docs/specifications.md:3121 から 3149 と README.md:304 は合う。
- [ADR 0368](../adr/0368-regex-style-scope.md): 見出し、用語、注の本文の段落ごとの照合、生成する番号を入れないこと、段落をまたがないことが、modules/golem-eval/test/RegexStyleSpec.hs:66 から 105 にあり、通った。docs/specifications.md:3545 から 3550 と README.md:253 から 254 は合う。
- [ADR 0369](../adr/0369-ruby-reading-style.md): 親文字が変わらないこと、既定の半分、指定した大きさでの計測が、modules/golem-driver/test/PdfSpec.hs:849 から 925 と modules/golem-html/test/XhtmlSpec.hs:481 から 497 にあり、通った。docs/specifications.md:4173 から 4182 と README.md:228 は合う。
- [ADR 0370](../adr/0370-tracking-inline-boxes.md): max(0, n − 1) × t、箱の中に配らないこと、先の箱の値、行末で戻すことが、modules/golem-layout/test/TrackingBoxesSpec.hs:25 から 45 と modules/golem-driver/test/PdfSpec.hs:907 にあり、通った。docs/specifications.md:2585 と 4256、README.md:246 は合い、「ルビと縦中横に足さない」という古い文は残っていない。
- [ADR 0371](../adr/0371-sidenote-marker-style.md): 本文の中の印だけに当たること、傍注の本文が変わらないこと、当てた後の幅が、modules/golem-driver/test/PageElementsSpec.hs:1226 から 1266 にあり、通った。docs/specifications.md:7228 から 7232 と README.md:303 は合う。
- [ADR 0373](../adr/0373-heading-block-alignment.md): 前と後の空きの和、三つの寄せ方、既定の center、縦組みが、modules/golem-layout/test/Main.hs:989 から 1012 と modules/golem-driver/test/PageElementsSpec.hs:700 にあり、通った。docs/specifications.md:3904 から 3911 と README.md:216 は合う。
- [ADR 0375](../adr/0375-printings-format.md): 六つの欄、`{date}` の形、未知の欄の拒否、省略のときの既定と G02076 が、modules/golem-eval/test/FileSpec.hs:2105 から 2155 にあり、通った。docs/specifications.md:1282 から 1290 と 2071 から 2073、README.md:182、docs/diagnostics.md:3815 から 3831 は合う。
- 「実装しないこと」: 可変フォントの編集 (0358)、上限の引き上げ (0359、値は 256 MiB のまま)、原稿の自動変換 (0363 ほか) にあたる実装は、読んだ範囲に無かった。
- docs/specifications.md から 14 本の ADR を示す箇所は、どれもリンクつきである。

## 未確認

- 九つのスイートの全体 (名前で絞らない実行) は動かしていない。
- CI での結果は見ていない。
- `golem` の CLI はビルドしておらず、原稿から PDF や EPUB を組んで確かめる端から端の確かめはしていない。
- 実装のコードを読んだのは、0359、0362、0367 の主な箇所だけである。ほかの ADR は、テストの中身と通ったことから判断した。
- 0369 の「サイズは親文字の半分」と仕様書の「ルビの外側の大きさの半分」(docs/specifications.md:4175) が、親文字の中に大きさを変える文字スタイルがあるときに食い違うかは、動かして確かめていない。
- docs/diagnostics.md と modules/golem-driver/src/Golem/Driver/Explain/Embedded.hs が同じ中身かは確かめていない。
- モジュールごとの仕様書は、docs/golem-pdf/specifications.md:128 から 129 ([ADR 0359](../adr/0359-imported-content-separators.md) と合う) のほかは読んでいない。

## 監査の副作用

リポジトリの作業ツリーは変えていない。
監査の後の `git status --porcelain=v1` は ` M docs/specifications.md`、`?? .claude/`、`?? docs/adr/0339-comments-in-arguments-and-manuscript-expressions.md` で、`git rev-parse HEAD` は dc8bf92ec33549ae2cd3b1cbf43487d451b1071a であり、始めの状態と同じである。
スクラッチパッドには、上の audit-cf244a2b のディレクトリと、/private/tmp/claude-501/-Users-tett23-repositories-src-github-com-tett23-golem/cb1691be-4aee-4682-b663-ec1ca710eb2d/scratchpad/audit-test-*.log の九つのログを書いた。
ビルドのログを /private/tmp/claude-501/-Users-tett23-repositories-src-github-com-tett23-golem/cb1691be-4aee-4682-b663-ec1ca710eb2d/scratchpad/build.log に書いたが、同じ時刻に別のビルド (同じスクラッチパッドの `tree` ディレクトリ) も同じファイルに書いていた。
そのため、このファイルは私の書き出しで一度切り詰められ、二つのビルドの出力が混ざっている。
別のビルドの側がこのログを使うなら、取り直しが要る。

---

## root [ADR 0376](../adr/0376-no-page-break-lines.md)〜0395 と予算

モデルは Fable 5.2 (claude-fable-5-2) である。
推論の強さは指定を受けておらず、自分では分からない。
読んだコミットは origin/main = cf244a2b5cc09cf117bd5f4c8e37ce40f978f706 である。
リポジトリの作業ツリーは変えていない (`git status --porcelain=v1` は監査の前と同じ 3 行、HEAD は dc8bf92ec)。
シェルのテストを動かすため、`git archive` でスクラッチパッドに展開した (/private/tmp/claude-501/-Users-tett23-repositories-src-github-com-tett23-golem/cb1691be-4aee-4682-b663-ec1ca710eb2d/scratchpad/tree-cf244a2b)。
`gh` はサンドボックスの中で TLS の検証に失敗したので、読み取りの呼び出しだけをサンドボックスの外で動かした。

## 指摘

### 1. 予算違反: プルリクエストの CI の時間 (重大度: 高)
- 予算: docs/budgets.md:23 の `<= 300` 秒 (root [ADR 0392](../adr/0392-budget-the-pull-request-ci-at-five-minutes.md) の 36 行)。
- コマンド: 展開したツリーで `GH_REPO=tett23/golem sh scripts/ci/ci-critical-path.sh`。
- 出力: 最後の行は `558`。20 回の値は 311 から 1071 で、300 以下の回は無い。
- 実装の PR #1033 の本文の値は `521.5` である。
- 問題: 中央値が予算の 1.86 倍である。
- 20 回には root [ADR 0395](../adr/0395-bring-the-pull-request-ci-under-five-minutes.md) の実装 (e543685d8、2026-11-18 11:19) より前の実行が混じっている。0395 の後だけの値は未確認。

### 2. ADR 違反: root [ADR 0395](../adr/0395-bring-the-pull-request-ci-under-five-minutes.md) の A2 と項目 7 が未実施のまま accepted (重大度: 中)
- ADR: docs/adr/0395-bring-the-pull-request-ci-under-five-minutes.md の 78 行 (項目 7)、142 行 (A2)、151 行。
- コマンド: `git ls-tree --name-only cf244a2b docs/ci-timings/`。
- 出力: 最新は `2026-11-10-the-build-runners-that-finish-last.md` で、0395 の後の記録は無い。
- docs/roadmap.md:43 に「プルリクエストの CI の時間を測り直す」として残っている。
- 問題: A2 の記録が無く、項目 8 (300 秒を超えたら別の ADR) の判断もまだである。ステータスは `accepted` である。

### 3. ADR 違反: root [ADR 0388](../adr/0388-widen-the-time-limits-of-tests-on-wasm32.md) の I2 のテストが wasm32 で走らない (重大度: 中)
- ADR: docs/adr/0388-widen-the-time-limits-of-tests-on-wasm32.md の 70 行「このテストは、毎晩の `wasm-tests.yml` で走る」。
- テスト: modules/golem-test-support/test/Main.hs:403 (`root ADR 0388 I2, I3: ...`)。
- コマンド: 展開したツリーで `sh scripts/ci/test-suites.sh wasm | grep -c test-support`。
- 出力: `0`。
- 原因: scripts/ci/test-suites.sh:33 は cabal.project.wasm のパッケージだけを読む。golem-test-support は cabal.project.wasm-tests:20 にだけある。
- 問題: wasm32 の値 (600 秒、1200 秒) を確かめるテストは、どの CI でも動かない。PR #1003 の本文の 29 行も同じことを書いている。

### 4. 予算違反の疑い: 毎晩の列挙の和 60 分 (重大度: 中)
- 予算: docs/budgets.md:39 (root [ADR 0281](../adr/0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md) の 12 行と 157 行、[ADR 0304](../adr/0304-check-the-keep-options-up-to-4-elements-and-draw-5-every-night.md) の 41 行)。
- 記録: README.md:1015 の四回の和は 60 分 35 秒、61 分 10 秒、53 分 58 秒、43 分 12 秒である。
- README.md:1019 から 1020 は、中央値 57 分 17 秒で収まったとし、一回目と二回目は超えたと書いている。
- 問題: [ADR 0281](../adr/0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md) と 0304 は中央値で判定するとは書いていない。記録の 4 回のうち 2 回が 60 分を超えている。
- 60 分はジョブが自分で落とさない (docs/budgets.md:50 から 51)。その後の実行の和は未確認。

### 5. ADR 違反: root [ADR 0391](../adr/0391-keep-the-at-sign-on-variable-declarations.md) の A1 の記録が PR の本文に無い (重大度: 低)
- ADR: docs/adr/0391-keep-the-at-sign-on-variable-declarations.md の 113 行と 123 行。
- コマンド: `gh pr view 1037 -R tett23/golem --json body`。
- 出力: 本文の `0391` は 0 件、`git grep` は 0 件。本文は root [ADR 0344](../adr/0344-revise-retire-legacy-style-formats.md) の実装の説明である。
- 中身は満たしている。`git grep -n -E '^set [A-Za-z_][A-Za-z0-9_-]* = ' cf244a2b -- '*.gm'` は何も返さず、scripts/manual/build-info.sh:57 から 59 は `@set` を書く。
- 問題: 手で確かめる受けいれ条件の記録が、決めた場所に無い。

### 6. テストの名前: root [ADR 0391](../adr/0391-keep-the-at-sign-on-variable-declarations.md) の番号の区切り (重大度: 低)
- 場所: modules/golem-eval/test/FileSpec.hs:388 と 393 (`ADR 0391 I1 I3: ...`)、modules/golem-parser/test/LowerSpec.hs:229 (`ADR 0391 I1 I2: ...`)。
- 決まり: adr スキルの「番号とテストの名前」は、区切りを `, ` とする (`ADR 0391 I1, I3: `)。

### 7. テストの名前: root [ADR 0387](../adr/0387-update-adr-guard-to-v0.13.1-and-migrate-status-lines.md) の S1 から S4 (重大度: 低)
- ADR: docs/adr/0387-update-adr-guard-to-v0.13.1-and-migrate-status-lines.md の 308 行が `S1` から `S4` と決めている。
- 場所: scripts/release/test.sh:452 から 464 (`notes: S1 S2 S3 ...`)、868 から 875 (`write-notes: S4 ...`)。
- 問題: 名前に `ADR 0387` が無く、番号が `I` でなく `S` である。adr スキルは `S1` などを不変条件の番号に使わないとする。
- ADR 自身が決めた形なので、直すには ADR が要る。

### 8. テストの名前: root [ADR 0390](../adr/0390-deterministic-and-exhaustive-cff-random.md) の入れ子の内側に番号が無い (重大度: 低)
- 場所: modules/golem-cli/test/CffRandomSpec.hs:44 から 46。`testGroup "ADR 0390 I8, I9: ..."` の中の `testCase` の名前が `profile <> ": " <> show text` である。
- 決まり: 入れ子の外側に書いても、内側の名前に書くことを省かない。

### 9. テストの名前: root [ADR 0381](../adr/0381-compressed-note-marks.md) の番号の無いテスト (重大度: 低)
- 場所: modules/golem-layout/test/CompressedNoteMarksSpec.hs:94 と 102、modules/golem-project/test/Main.hs:1094 (`ADR 0381: ...`)。
- 問題: ADR の番号だけで、不変条件の番号が無い。

### 10. ADR の形: root [ADR 0376](../adr/0376-no-page-break-lines.md)、[0378](../adr/0378-punctuation-proportional-features.md)、[0381](../adr/0381-compressed-note-marks.md)、[0387](../adr/0387-update-adr-guard-to-v0.13.1-and-migrate-status-lines.md) の不変条件の番号 (重大度: 低)
- 場所: 0376 の 34 行、0378 の 32 行、0381 の 27 行、0387 の 283 から 286 行。
- 問題: 番号が `1.` の形で `I1:` でない。0376、0378、0381 の境界の表には「不変条件」の列が無い。
- テストは `ADR 0376 I1: inv1_...` の形で対応している。コミット済みの ADR なので変えられない。

### 11. README: root [ADR 0381](../adr/0381-compressed-note-marks.md) の `mark-shape` が無い (重大度: 低)
- コマンド: `git grep -n -E "mark-shape|平字|flat" cf244a2b -- README.md`。
- 出力: 無し。
- 仕様書には docs/specifications.md:6963、6969、7037、7048 にある。
- 問題: README の `[notes]` の段落 (README.md:307 から 310) に、新しい指定が無い。[ADR 0381](../adr/0381-compressed-note-marks.md) は README の変更を書いていないが、プロジェクトの決まりは仕様の変更で README も直すとする。

### 12. 予算の一覧: キャッシュの比較が ADR と違う (重大度: 低)
- 一覧: docs/budgets.md:22 は `<=` 10 である。
- ADR: docs/adr/0228-keep-the-ci-caches-under-the-10-gb-limit.md の 144 行は「10 GB の下にある」である。
- 一覧の docs/budgets.md:28 が、ちょうど 10 GB は超えると注記している。
- 問題: 表の値だけを読む `bin/budget-check` は、ちょうど 10 GB を満たすと判定する。

### 13. 予算の一覧: root [ADR 0392](../adr/0392-budget-the-pull-request-ci-at-five-minutes.md) の予算に番号が無い (重大度: 低)
- 一覧: docs/budgets.md:23 の ADR の列は `ADR 0392` だけである。
- ADR: 予算は「実装すること」の 36 行にあり、受けいれ条件 A1 (82 行) は「予算を満たすかどうかは問わない」である。
- 問題: conformance-audit スキルは、ADR の列に番号 (`ADR NNNN A1` など) を書くとする。指す番号が ADR に無い。

### 14. 予算の一覧: Alloy の行の「強制するもの」 (重大度: 低)
- 一覧: docs/budgets.md:46 は `check.sh` の `TIMEOUT` だけを挙げる。
- 実装: 30 分は .github/workflows/models.yml:28、345 分は .github/workflows/models-nightly.yml:61 の `timeout-minutes` である。`TIMEOUT=19800` は models-nightly.yml:85 だけである。
- 問題: 三つの上限のうち二つを強制するものが、列に無い。

## 問題が見つからなかった項目

- テストの通過: cf244a2b の CI は `build` の 8 レッグ (tests-driver、tests-rest を含む)、`ci`、`determinism`、`visual`、`wasm`、`adr` が success である (`gh api repos/tett23/golem/commits/cf244a2b.../check-runs`)。手元の cabal では動かしていない。
- シェルのテスト: 展開したツリーで `sh scripts/ci/test.sh` は 1035 件のうち失敗 1 件、`sh scripts/release/test.sh` は 485 件のうち失敗 2 件である。失敗は Git のリポジトリでないことと、サンドボックスの `mktemp` によるもので、[ADR 0387](../adr/0387-update-adr-guard-to-v0.13.1-and-migrate-status-lines.md)、[0392](../adr/0392-budget-the-pull-request-ci-at-five-minutes.md)、[0395](../adr/0395-bring-the-pull-request-ci-under-five-minutes.md) の名前のテストに失敗は無い。
- root [ADR 0376](../adr/0376-no-page-break-lines.md): 不変条件 1 のテストは PaginateSpec.hs:659 から 691、FileSpec.hs:1594、ParagraphSpec.hs:491 にある。仕様書 5529 行、markup.md:923、README.md:312 から 313、diagnostics.md の G02156 が合う。
- root [ADR 0378](../adr/0378-punctuation-proportional-features.md): テストは PunctuationWidthSpec.hs:111 から 126、FeaturesSpec.hs:18 にある。仕様書 4239 行と 4300 行、README.md:249 から 250 が合う。
- root [ADR 0381](../adr/0381-compressed-note-marks.md): テストは golem-layout の CompressedNoteMarksSpec.hs:55 から 86 にある。仕様書は合う。
- root [ADR 0387](../adr/0387-update-adr-guard-to-v0.13.1-and-migrate-status-lines.md): docs.yml:35 は `ab55769152ed0f8a3465ee3435a2df43ab9d067f # v0.13.1` である。`^ステータス:` の ADR は 0 件で、`^Status:` は 581 ファイルに 1 行ずつある。[ADR 0194](../adr/0194-update-adr-guard-to-v0.10.0.md) のステータス、notes.sh:82 と 85、write-notes.sh:62、pre-commit、README、CONTRIBUTING、CLAUDE.md:20、仕様書 20 から 22 行と 9080 行、manual-dev、textlint の設定が合う。`"part"` の誤りを探す二つの検索は何も出さない。
- root [ADR 0388](../adr/0388-widen-the-time-limits-of-tests-on-wasm32.md): I1 と I3 は Main.hs:408、CPP は TimeLimit.hs:55 から 58、仕様書 531 から 534 行、[ADR 0091](../adr/0091-cpu-time-limits-in-pdf-and-svg-tests.md) のステータスが合う。test-failures.tsv に 1,000,001 の行は無い。A1 と A2 は PR #1003 の本文に、実行 44064582275、44068632734、44073062562 と時間がある。
- root [ADR 0389](../adr/0389-diagnose-caption-and-sidenote-indents-that-leave-no-width.md): I1 から I11 と A1 のテストは CaptionSidenoteIndentSpec.hs:213 から 304、golem-lsp の Main.hs:338、DiagnosticsSpec.hs:447 にある。`profileDependentCodes` (Diagnostic.hs:192 から 193)、diagnostics.md:78 から 79、README.md:306、マニュアルの付録、ロードマップの項目の削除が合う。
- root [ADR 0390](../adr/0390-deterministic-and-exhaustive-cff-random.md) (0394 が置き換えた部分を除く): I1 から I9 と A1 のテストは RandomFontSpec.hs:191 から 265、CffSpec.hs:111 から 165、CffRandomSpec.hs:35 から 57 にある。cbits/golem は `FT_New_Library` を使い、`FT_Init_FreeType` を呼ばない (golem_font.c:76 から 88)。仕様書 1325 から 1343 行と 4466 行、README、diagnostics.md が合う。
- root [ADR 0391](../adr/0391-keep-the-at-sign-on-variable-declarations.md): `SetDeclarationStart` は 0 件、G02155 は `noticeCodes` と src に無い。diagnostics.md:6017 から 6041 は状態が廃止である。compatibility.md:68、[ADR 0336](../adr/0336-unprefixed-variable-declarations.md) のステータス、README.md:205、markup.md:276、仕様書 1244 行が合う。`ADR 0336` の名前のテストは 0 件である。I1 から I5 のテストがある。
- root [ADR 0392](../adr/0392-budget-the-pull-request-ci-at-five-minutes.md): I1 から I4 は scripts/ci/test.sh:4663 から 4715 にあり通る。CONTRIBUTING.md:463、budgets.md の行、A1 の PR #1033 の本文が合う。
- root [ADR 0393](../adr/0393-references-in-ruby-segments-without-readings.md): I1 から I3 は StructureSpec.hs:130 から 144、TaggedPdfSpec.hs:221 から 236 にある。仕様書 128 から 129 行、README.md:334、ロードマップの項目の削除が合う。
- root [ADR 0394](../adr/0394-order-cff-glyph-diagnostics-like-the-others.md): I1 は PdfSpec.hs:183 と 195 にある。[ADR 0390](../adr/0390-deterministic-and-exhaustive-cff-random.md) のステータス、diagnostics.md の G08109 の並びの文が合う。
- root [ADR 0395](../adr/0395-bring-the-pull-request-ci-under-five-minutes.md) (A2 を除く): I1 から I4 と A1 は scripts/ci/test.sh:4739 から 4935 にあり通る。pr-caches.yml は `workflow_run` と `pull_request_target` で動き、チェックアウトをしない。[ADR 0228](../adr/0228-keep-the-ci-caches-under-the-10-gb-limit.md) のステータス、README、仕様書、manual-dev、CONTRIBUTING が合う。閉じたプルリクエストのキャッシュは 0 件である (`gh api repos/tett23/golem/actions/caches`、開いているのは 962、964、988)。
- 予算「Actions のキャッシュの合計」: `gh api repos/tett23/golem/actions/cache/usage --jq '.active_caches_size_in_bytes / 1000000000'` は `5.07` で、10 以下である。
- 予算「列挙の範囲ごとの時間」と「和」: 毎晩の実行 44215045635 の時間を量る段の表では、最大 5.86 秒、和 21.47 秒である。一回の値で、一覧の計測のコマンド (4 回の中央値) は動かしていない。
- 強制する上限の値: enum.yml:46 の 90 分、suite-timeout.sh:22 の 600 秒、suite-limits.sh:123 から 125 の式、TimeLimit.hs:56 と 58、Support.hs:52 の 300 秒、ParallelMain.hs:15 の `300 * race`、fetch-url.sh:38 の 120 秒と 15 行の 3 回が、一覧と ADR に合う。

## 未確認

- Haskell のテストを手元の cabal で動かすこと。cf244a2b の作業ツリーが無く、初めからのビルドが重いためである。根拠は CI の結果だけである。
- wasm32 でのテストの通過。cf244a2b での `wasm-tests.yml` の実行は無い。直近の予定の実行 44219046261 (78993062c) は success である。
- 予算「列挙の範囲ごとの時間」と「和」の、一覧の計測のコマンドでの値。
- 予算「CI の warning が 0 行」と「テストスイートごとの時間」の、今の値。CI の `ci` ジョブの success だけを見た。
- root [ADR 0387](../adr/0387-update-adr-guard-to-v0.13.1-and-migrate-status-lines.md) の移行の手順 (移行の前後の `adr-guard unimplemented` の一致、移行のコミットのメッセージの SHA)。手元の `adr-guard` は動かしていない。CI の `adr` ジョブは success である。
- root [ADR 0388](../adr/0388-widen-the-time-limits-of-tests-on-wasm32.md) の A3 (ネイティブの結果と時間が実装の前と同じ)。時間は比べていない。
- root [ADR 0389](../adr/0389-diagnose-caption-and-sidenote-indents-that-leave-no-width.md) の I7 の golden が、実装の前のコミットで作られたか。
- root [ADR 0395](../adr/0395-bring-the-pull-request-ci-under-five-minutes.md) の項目 1 から 3 の ci.yml の中身。A1 のテストの通過だけを見た。

## 範囲の外で見つけたこと

- 毎晩の `enum.yml` の実行 44215045635 (2026-11-18、c5993c5ee) が失敗している。
- 落ちたのは golem-layout-test の `vertical writing: ... (golem-layout ADR 0049, B2)` (test/LineBreakInvariantsSpec.hs:264) で、`failedValue = ["１","１"]` である。
- 範囲の ADR ではなく、cf244a2b より前のコミットである。

