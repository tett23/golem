# ADR 違反の監査（2026-11-17）

- 日付：2026-11-17
- 読んだコミット：888dc03b293dbb57cd5185cb69e9e8f247d6f831
- 範囲：root [ADR 0260](../adr/0260-front-matter-folios-and-page-labels.md)〜0305 と [golem-layout ADR 0046](../golem-layout/adr/0046-the-alloy-model-judges-a-larger-need-lines-without-the-spaces-before-it.md)〜0049（2026-11-08 から 2026-11-11 に実装したもの）。予算違反の観点は含まない。
- 使ったモデル：Fable（`auditor`）。範囲を三つに分け、三つの `auditor` に並べて任せた。
- 指定した推論の強さ：指定なし
- `auditor` が報告した推論の強さ：報告させていない

以下は、三つの `auditor` が返した指摘を変えずに貼ったものである。

---

# [ADR 0260](../adr/0260-front-matter-folios-and-page-labels.md)–0275 と [golem-layout ADR 0046](../golem-layout/adr/0046-the-alloy-model-judges-a-larger-need-lines-without-the-spaces-before-it.md)–0049 の乖離の監査（888dc03b）

## 結論

振る舞いが ADR に反すると確かめられた箇所はありません。指摘は 7 件で、テスト設計との食い違いが 5 件、文書の食い違いが 2 件です。ステータスの行の誤りは見つかりませんでした。

ただし、Haskell のテストは一つも走らせていません（888dc03b のビルドが要るため）。テストについては「名前と中身を読んだ」までで、通るかどうかは未確認です。

## 監査のやり方

- 対象は `888dc03b293dbb57cd5185cb69e9e8f247d6f831` です。`git fetch origin main` はサンドボックスのネットワーク制限で失敗しましたが、`git rev-parse origin/main` はこのハッシュを返し、コミットは手元にありました。
- チェックアウトは変えず、`git archive 888dc03b | tar -x` でスクラッチパッドに展開して読みました。展開先は `/private/tmp/claude-501/-Users-tett23-repositories-src-github-com-tett23-golem/cb1691be-4aee-4682-b663-ec1ca710eb2d/scratchpad/new` です。以下の `file:line` はこのコミットのリポジトリ相対のパスです。
- 20 本とも「実装すること」「実装しないこと」「不変条件」「テスト設計」を読み、型、diagnostic のコード、テストの名前、仕様書、ロードマップ、マニュアルを `rg` で突き合わせました。
- superseded の部分は後の ADR で判定しました: 0261 は 0304、0267 は 0350、0272 は 0285、0297、0305、0274 と 0275 と layout 0049 は 0282 と 0278。

## 指摘

### 1. [ADR 0270](../adr/0270-underline-and-strikethrough.md): I1 から I4 の列挙のテストがない（missing）

- **ADR**: `docs/adr/0270-underline-and-strikethrough.md` の「テスト設計」の「golem-layout と golem-typeset」。I1 は「小さな入力のすべてで列挙し」行分割が等しいこと、I2、I3、I4 は「同じ列挙で」区画を確かめることを求めています。
- **実装**: `modules/golem-driver/test/DecorationsSpec.hs:67`（I1）、`:126`（I3）、`:131`（I2、I4）は、どれも一つか二つの原稿の例です。I1 は `漢字漢字…` の一つの原稿を区切り 2 通りで比べるだけです。
- **確かめ**: `rg -n -i 'underline|decoration' modules/golem-layout/test modules/golem-typeset/test -g '*.hs' -l` は何も返しません。golem-layout と golem-typeset に下線のテストはありません。
- ステータスは accepted のままです。

### 2. [ADR 0263](../adr/0263-notes-with-more-than-one-paragraph.md): I2 のテストが PDF のバイト列を比べていない（missing、違反の可能性は未確認）

- **ADR**: `docs/adr/0263-notes-with-more-than-one-paragraph.md` の不変条件 I2 は「`@note` のブロックを別の位置に動かしても、どの出力のバイト列も変わらない」。テスト設計は「ブロックを置けるすべての位置に動かして、四つの出力のバイト列が等しい」。
- **実装**: `modules/golem-driver/test/NotesSpec.hs:75-93`。動かす位置は三つ（印の前、後、リストの項目の中）だけです。PDF は `notPdf` でバイト列の比較から外し、ページごとの描いたグリフ（`drawnGlyphs`）だけを比べます。
- **根拠**: 同ファイル 82 行のコメントが `-- the PDF follows the places of the text in the source (its structure), not only the text` と書いています。
- **未確認**: PDF のバイト列が実際に違うかは、ビルドしていないので確かめていません。違うなら I2 の文への違反で、記録する ADR が要ります。`rg -l '0263' docs` で、I2 を読み替えた後の ADR は見つかりませんでした。

### 3. [ADR 0260](../adr/0260-front-matter-folios-and-page-labels.md): I4 のテストが「fixture のすべて」でない（missing、軽い）

- **ADR**: `docs/adr/0260-front-matter-folios-and-page-labels.md:306`。「`page-numbering` のない本の PDF が今の PDF とバイト列で等しいことを、golem-driver の fixture のすべてで確かめる（I4）」。
- **実装**: `modules/golem-driver/test/PageLabelsSpec.hs:141-145`。メモリ上の一冊について、ラベルが (p, p, 表記なし) であること、`/PageLabels` を書かないこと、ノンブルの文字列だけを確かめます。
- **補う事実**: 実装の PR #798 は fixture の golden を変えていません。`git diff --stat ddcd16e4^1 ddcd16e4 | grep -vE '\.hs|\.md'` に出る `.txt` は `scripts/visual/pages/manual.txt` と `manual-dev.txt` だけでした。

### 4. 「golem-typeset のテスト」が golem-driver にあり、記録がない（doc mismatch、軽い）

- **ADR**: 次の ADR のテスト設計は、テストを golem-typeset に置くと書いています。
- **実装**: golem-typeset のテストは `BoxSpec`、`GlyphRunsSpec`、`MemoSpec`、`RuleShapeSpec`、`TcySpec`、`WrapMarkSpec` だけです（`ls modules/golem-typeset/test`）。該当のテストは golem-driver にあります。

| ADR | ADR が golem-typeset に置くとした番号 | 実際の場所 |
| --- | --- | --- |
| 0260 | I5、I8、I9、G07110 | `modules/golem-driver/test/PageLabelsSpec.hs:114-219` |
| 0262 | I8、I9（I11 は golem-assemble） | `modules/golem-driver/test/TableCaptionsSpec.hs:74-172` |
| 0263 | I4、I5 | `modules/golem-driver/test/NotesSpec.hs:47-63` |
| 0264 | I2 から I7 | `modules/golem-driver/test/TocStylesSpec.hs:58-109` |
| 0265 | I4、I5、I7 | `modules/golem-driver/test/IndexRangeSpec.hs:105-198` |
| 0267 | I2、I3、I4、G07120 | `modules/golem-driver/test/InsideLinksSpec.hs:268-492` |
| 0268 | I1、I2、I7、I8 | `modules/golem-driver/test/OpenTypeFeaturesSpec.hs:80-165` |
| 0269 | I1、I2、I3、I7、I8 | `modules/golem-driver/test/ScriptsSpec.hs:68-129` |

- 同じ置き換えは、前の ADR については `docs/adr/0236-…md:55-56` と `docs/adr/0257-…md` が記録しています。上の 8 本について記録した ADR は見つかりませんでした（`rg -n 'golem-typeset のテスト' docs/adr/02[0-9][0-9]-*.md docs/adr/03*.md` は 0216、0227、0236、0257 だけ）。

### 5. [ADR 0262](../adr/0262-table-numbers-captions-column-widths-and-cell-styles.md): golem-epub のテストがない（missing、軽い）

- **ADR**: `docs/adr/0262-…md` の「テスト設計」の「golem-html、golem-epub、golem-text のテスト（I4）」。
- **実装**: golem-html は `modules/golem-html/test/XhtmlSpec.hs:782-800`、golem-text は `modules/golem-text/test/TextOutputSpec.hs:224` にあります。
- **確かめ**: `rg -n -i 'caption|colgroup|<table' modules/golem-epub/test -g '*.hs'` は何も返しません。

### 6. docs/markup.md の組み込みの文字スタイルの数がコードと違う（doc mismatch）

- **文書**: `docs/markup.md:1303` は「組み込みの文字スタイルは `strong`、`bold`、`italic`、`code`、`url`、`no-break` の六つである」。
- **コード**: `modules/golem-project/src/Golem/Project/Style.hs:645-662` は十です。`note-mark`、`subscript`、`superscript`（[ADR 0269](../adr/0269-superscript-and-subscript.md)）、`toc-page-number`（[ADR 0264](../adr/0264-paragraph-styles-for-toc-entries.md)）が markup.md にありません。
- **裏づけ**: `modules/golem-project/test/Main.hs:1424` が十の名前を固定し、`docs/specifications.md:2743` も「次の十である」と書いています。
- [ADR 0272](../adr/0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md) は markup.md の一覧に `no-break` を足すことだけを求め、0264 と 0269 は markup.md を変えないとしたので、どの ADR にも反しませんが、文はコードと食い違います。

### 7. docs/specifications.md の HTML の要素の対応が [ADR 0269](../adr/0269-superscript-and-subscript.md) と違う（doc mismatch）

- **文書**: `docs/specifications.md:3614-3615` は、要素にするのは `strong`、`bold`、`italic`、`code` だけで、「ほかの文字スタイルは `cs-名前` の class にする」と書いています。
- **ADR とコード**: [ADR 0269](../adr/0269-superscript-and-subscript.md) の「HTML と EPUB」は `<sup>` と `<sub>` を求め、`modules/golem-html/src/Golem/Html.hs:751-754` がそう出します。テストは `modules/golem-html/test/XhtmlSpec.hs:522-530` です。
- 同じ仕様書の `docs/specifications.md:2634-2635` は `<sup>` と `<sub>` を正しく書いているので、仕様書の中で二か所が食い違います。

## 問題が見つからなかった ADR

「テスト設計のテストがある」は、名前と中身を読んだという意味です。

- **0260**: `PageLabel` と `pageLabelInlines`（`modules/golem-layout/src/Golem/Layout/PageLabel.hs:28,86`）、`/PageLabels`（`modules/golem-pdf/src/Golem/Pdf/Writer.hs:704`）、G03121 から G03123、G07109、G07110、`manual/manifest.toml:5,12`、PL1、PL2、PL3、PL7 の列挙、仕様書と diagnostics.md とロードマップを確かめました。指摘は 3 と 4 だけです。
- **0261**（毎晩の上限は 0304）: 五つのキー、`Keep`、`FKeepNext`、G07111 から G07113、CSS、K1 から K7 のテスト、`pagination.als` の `keepFirst`、`keepLast`、`keepAll` を確かめました。`FStart` は ADR が許すとおり `FSection (OfParagraph _)` です。
- **0262**: タグ 14、`abiVersion = 9`、六つのコード、`[tables]`、`<caption>` と `<colgroup>`、タグ付き PDF の `Caption`（`TableCaptionsSpec.hs:167-171`）を確かめました。指摘は 4 と 5 だけです。
- **0264**: `toc-1` から `toc-6`、`toc-page-number`、G07117、`nav.toc li.toc-<l>` の CSS、ロードマップを確かめました。指摘は 4 だけです。
- **0265**: `IndexKind`、`SeeKind`、九つのコード、`section-headings`、I1 から I8 のテスト、ロードマップを確かめました。指摘は 4 だけです。
- **0266**: `CiteItem`、`citationPieces`、タグ 25、G02147 から G02151、古い G02021 のメッセージが消えたこと、`<span class="cite">`、I1 から I8 のテストを確かめました。
- **0267**（PDF/X-4 の本文リンクは 0350）: `LinkDest`、`Dest`、`OutlineItem`、`/Outlines` と `/PageMode`、G07120、I1 から I11 のテスト、ロードマップを確かめました。指摘は 4 だけです。
- **0268**: `features`、G03124、G08103、`halt` などの打ち消し（`modules/golem-typeset/src/Golem/Typeset/Fonts.hs:594`）、33 個めの機能のテスト、一つの `font-feature-settings` を確かめました。指摘は 4 だけです。
- **0269**: `position`、二つの組み込み、7/12（`modules/golem-layout/src/Golem/Layout/Japanese.hs:1383`）、G03125、I1 から I8 のテストを確かめました。指摘は 4 と 7 だけです。
- **0271**: 七つのキー、`FBoxed`、`poBoxes`、G07121、B1 から B9 のテスト、`browser.yml` の `div.box` の検査、specimens の `10-boxes.gm` を確かめました。
- **0272**（0285、0297、0305 で判定）: `SoftHyphen`、`[shy]`、`@hyphenation-exceptions`、`no-break`、十のコード、`NoBreakEnum` の I7 と S1、S2、I5、I6、I12、I13 のテスト、0209 のステータスの行、README を確かめました。
- **0273**: `planProject`、`targetEntries`（`modules/golem-driver/src-plugins/Golem/Driver/New.hs:253,292`）、G03131 から G03134、I1 から I8 のテスト、README、マニュアル、[golem-cli ADR 0001](../golem-cli/adr/0001-command-line-interface.md) のステータスの行を確かめました。
- **0274**（0282、0278 で判定）: `pPullInFirst`、`lineStretchLimit`、R1 から R9 のテスト、ロードマップ、差異の文書を確かめました。
- **0275**（0282 で判定）: 規則（`Japanese.hs:2170`）、`number-unit-penalty`、W1 から W8 のテスト、markup.md の例を確かめました。
- **golem-layout 0046**: `judgedBefore` が消えたこと、README、`expected.txt:27-28`、0043 のステータスの行を確かめました。Alloy の二つのコマンドは実際に走らせました（下記）。
- **golem-layout 0047**: P9′ と P11 の述語と例、改ページの印と自ら送られる図版の例（`modules/golem-layout/test/PaginateSpec.hs:1637-1669`）、仕様書を確かめました。
- **golem-layout 0048**: D1 から D5（`modules/golem-layout/test/CodePaddingSpec.hs`）、D6 と D7（`modules/golem-driver/test/PdfSpec.hs:1736-1755`）、仕様書の既知の不具合とロードマップの行が消えたことを確かめました。
- **golem-layout 0049**（縦組みの全角の数字は 0282）: 四つの述語、B1 から B8 のテスト（`modules/golem-layout/test/UnbreakablePairsSpec.hs`）、ロードマップを確かめました。

## 走らせたコマンド

Alloy（[golem-layout ADR 0046](../golem-layout/adr/0046-the-alloy-model-judges-a-larger-need-lines-without-the-spaces-before-it.md) のテスト設計の二つのコマンド）は、`docs/golem-layout/models` で次のとおり走らせました。Java の既定の一時ディレクトリがサンドボックスで書けなかったので、`JAVA_TOOL_OPTIONS="-Djava.io.tmpdir=$TMPDIR"` を付けています。

```
alloy6 exec -q -n -t text -c needMoreSpace46 -o - pagination.als      → none
alloy6 exec -q -n -t text -c needMoreSpace46Here -o - pagination.als  → found
```

`expected.txt:27-28` の `needMoreSpace46 none`、`needMoreSpace46Here found` と一致しました。

## 未確認

- **Haskell のテスト**: 一つも走らせていません。
- **adr-guard**: `adr-guard check-status` と `adr-guard links` は、展開したツリーが git リポジトリでないため「ADRを列挙できませんでした」で終わりました。
- **重い Alloy のコマンド**: `needMoreNone` など毎晩のものは走らせていません。
- **リリースノート**: 0264 と 0269 が求める記載は、実装を含むタグがまだないので判定していません（`git tag --contains 574a21f5` は空、最新のタグは v0.1.0-rc4）。
- **手で確かめる項目**: 0267 の Acrobat とプレビューでの確かめ、0270 の見本の目視、0274 と 0275 の行の数え直しは、PR の説明を読んでいません。
- **深さ**: 実装の中身は、主に型、コード、定数、テストの期待値との突き合わせで読みました。各 ADR の細かい規則の一つずつを、コードの分岐まで追ってはいません。

---

# [ADR 0276](../adr/0276-hyphenate-words-by-the-patterns-of-their-language.md)〜0290 の乖離の監査（main = 888dc03b293dbb57cd5185cb69e9e8f247d6f831）

## 結論

15 本のうち、明確な違反はなかった。指摘は 4 件で、欠落（一部）が 1 件、予算の超過の記録が 1 件、軽微なテストの食い違いが 2 件である。Haskell のテストは動かしていないので、Haskell 側は「読んで確かめた」にとどまる。

## 前提と、確かめられなかったこと

- **読んだツリー**：ローカルの checkout は e313e3b0 のままで古い。`git archive 888dc03b | tar -x` で scratchpad に展開したツリーを読んだ。リポジトリのファイル、ブランチ、PR は変えていない（`git fetch` も不要だった。コミットは手元にあった）。
  - 展開先：`/private/tmp/claude-501/-Users-tett23-repositories-src-github-com-tett23-golem/cb1691be-4aee-4682-b663-ec1ca710eb2d/scratchpad/new`
  - 以下のパスは `/Users/tett23/repositories/src/github.com/tett23/golem/` からの相対で、行番号は 888dc03b のものである。
- **ADR の本文**：23d74179 と 888dc03b のあいだで、対象の 15 本はステータスの行しか変わっていない。
  - コマンド：`git diff 23d74179 888dc03b -- <ADR>` の変更行を数えた。どれも 2 行（ステータスの行の旧と新）。
- **後続の ADR**：ステータスの行が示す置き換えは 0280→0283/0285、0281→0286/0351、0283→0298、0285→0297 である。この四つは後の ADR で判定した。
- **未確認**：
  - `cabal test` は動かしていない（888dc03b のビルドが手元にない）。Haskell のテストは、名前と中身を読んだだけである。
  - CI と毎晩の `enum.yml` の実行結果は読めなかった（`gh run list` が sandbox で api.github.com に届かない）。
  - `scripts/browser/test/unit.test.mjs` の bind を使う一件（「S1, S4: the server answers 404 …」）と `browser.test.mjs` は動かせなかった。sandbox の中で node が `InternalCallbackScope::Close()` の assertion で落ちる。
  - `browser.yml` の H1、H2 の段（wasmtime のホストをビルドして走らせる）は動かしていない。

## 動かしたもの

- `sh scripts/ci/test.sh`（mktemp が TMPDIR を見るようにする shim を PATH に置いて実行）
  - 出力：`973 tests, 1 failures, 39 skipped`
  - 落ちた一件は `FAIL: process check: the files checked include scripts/ci/test.sh, scripts/test.sh and tools/editors/nvim/test.sh (I8)` で、`.git` のない展開先で走らせたためと見られる（`sed: read error on …/scripts/ci/../../: Is a directory`）。対象の ADR の検査ではない。原因は確かめていない。
  - 対象の ADR の検査（0281 の N4、N5、0286 の M1〜M4、0287 の P1〜P4、0289 の H4）に FAIL はない。
- `node --test --test-name-pattern='S[1-4]' scripts/browser/test/unit.test.mjs`
  - bind の要らない 6 件が通った（S2、S3、S1 が三つ、root がリンクの S2）。
- `shasum -a 256` と、ghq の hyphenation/tex-hyphen の `git show 5684c0f5…:<path>` との比べ
  - `data/hyphenation/` の 12 のパターンと例外のファイル、8 の LICENSE のファイルがすべて `same`。
- `sh scripts/ci/enum-timings.sh --list`
  - 8 の範囲の段がすべて `!cancelled()` を持つ。

## 指摘

### 1. [ADR 0278](../adr/0278-use-the-places-of-line-adjustment-in-the-order-of-jlreq.md)：`@style-def` では、二つの名前の段と空の順を書けない（欠落、一部）

- **ADR**：`docs/adr/0278-use-the-places-of-line-adjustment-in-the-order-of-jlreq.md`
  - 175〜198 行（3 節）：値は「名前か、名前の配列（同じ段に置く種類）」の配列で、「`based-on` で引き継ぎ、`@style-def` でも書ける」。`shrink-order = []` は「すべてを同じ割合で詰める」。
  - 327 行（A10）：六つの誤った値を「`style.toml` と `@style-def` の両方で確かめる」。
- **実装**：`modules/golem-project/src/Golem/Project/Style.hs:3392-3395`
  - `@style-def` の `shrink-order` と `stretch-order` の値を `T.splitOn ","` で分け、名前一つを一つの段にする。
- **テスト**：`modules/golem-project/test/Main.hs:395-400`
  - `"brackets,comma"` が `[["brackets"], ["comma"]]` になることを期待する。
  - 空の値 `""` が G03006 になることを期待する。
- **食い違い**：
  - 既定の `["brackets", "comma"]` のような同じ段の二つの種類を、`@style-def` では書けない。
  - 空の順（`[]`）も `@style-def` では書けない。
  - A10 の `[[]]` と `[["brackets", ["comma"]]]` は、`@style-def` では確かめようがなく、テストにない。
- **記録**：仕様書はこの狭め方を書いている（`docs/specifications.md:2826`）。[ADR 0278](../adr/0278-use-the-places-of-line-adjustment-in-the-order-of-jlreq.md) を改める ADR も記録の ADR もない。
  - コマンド：`rg -l "shrink-order" docs --glob '*.md'`
  - 出力：ADR は 0278 だけ（ほかは `diagnostics.md`、`differences-from-tex-and-indesign.md`、`specifications.md`）。

### 2. [ADR 0281](../adr/0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md)：README が、毎晩の予算 60 分を超えた実行を二回記録している（予算の超過の記録）

- **ADR**：`docs/adr/0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md`
  - 157 行：毎晩のジョブはすべての範囲の和を 60 分とする。
  - 186 行：超えたら上限を一つ下げ、下げた段を抜き取りに回す。
  - 214 行：和が 60 分を超えていれば、4 の順で手を打つ。
- **文書**：`README.md` の `enum.yml` の節（896 行から。二つめの表とその後の文）
  - 実行 42837473529 と 42848615465 の和が「60 分 35 秒」「61 分 10 秒」。
  - 「段の和の中央値は 57 分 17 秒で、60 分に収まった」「一回目と二回目は、行分割の段が 37 分ほどかかり、和が 60 分を超えた」。
- **食い違い**：毎晩の予算を、複数の実行の中央値で判定してよいと決めた文は、[ADR 0281](../adr/0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md) にも [ADR 0286](../adr/0286-leave-the-start-of-cabal-out-of-the-time-of-an-enumeration-area.md) にもない。[ADR 0286](../adr/0286-leave-the-start-of-cabal-out-of-the-time-of-an-enumeration-area.md) の中央値は、プルリクエストの予算を同じコミットの四つのジョブで量るときのものである。
- **未確認**：今の `main` での毎晩の実行の時間は読めていない。この二回は [ADR 0304](../adr/0304-check-the-keep-options-up-to-4-elements-and-draw-5-every-night.md) の実装のときのブランチの実行で、[ADR 0304](../adr/0304-check-the-keep-options-up-to-4-elements-and-draw-5-every-night.md) は監査の範囲の外である。

### 3. [ADR 0278](../adr/0278-use-the-places-of-line-adjustment-in-the-order-of-jlreq.md)：A12 の番号を持つテストがない（テストの名前、軽微）

- **ADR**：0278 の 320 行（テストの名前に A1 から A12 を入れる）、329 行（A12 は二つのマニュアルを二度組む今の決定性の検査）。
- **テスト**：`modules/golem-layout/test/AdjustOrderSpec.hs:5-8`
  - モジュールの注釈は「A1 to A9 and A12」と書くが、A12 の名前の `testCase` はない。
  - コマンド：`rg -n "A12" modules scripts .github -g '!*.tsv'`
  - 出力：`AdjustOrderSpec.hs:7` の注釈の一行だけ。
- **食い違い**：決定性の検査そのものがあるかは確かめていない。番号を名前に持つテストがないことだけを確かめた。

### 4. [ADR 0277](../adr/0277-keep-the-page-label-of-a-citation-mark-with-its-value.md)：C6 のテストの入力が、テスト設計と違う（テストの入力、軽微）

- **ADR**：`docs/adr/0277-keep-the-page-label-of-a-citation-mark-with-its-value.md:162`
  - 「行長 2 字の本で `[cite a page=xii]` を組み」G07105 だけが出ること。
- **テスト**：`modules/golem-driver/test/SoftHyphenSpec.hs:106-109`
  - 行長 12 字の本で、21 桁の値（`page="111…1"`）を組む。
- **食い違い**：述語（G07105 だけ、範囲の中では G07122 だけ）は C6 のとおりで、名前も C6 を持つ。入力だけが違う。

## 指摘のなかった ADR

Haskell のテストは、どれも名前と中身を読んだだけで、動かしていない。

- **[ADR 0276](../adr/0276-hyphenate-words-by-the-patterns-of-their-language.md)**：指摘なし。
  - 同梱の七言語のファイルとモジュール、表のキー（`Languages.hs` の `bundled`）、`outsideSpanTag`、前後に残す字の数（`parsePatterns 2 2` と `2 3`）が ADR のとおり。
  - F1〜F7 のテストがある（`LanguagesSpec.hs:126-172`、`BookLanguageSpec.hs:129-147`）。F6 のバイト列は上のとおり動かして確かめた。
  - `licenses.sh`、`check-wasm-archive.sh`、roadmap、仕様書、差異の文書が ADR のとおり。`fr` の列挙はプルリクエストに戻っている（[ADR 0286](../adr/0286-leave-the-start-of-cabal-out-of-the-time-of-an-enumeration-area.md)）。
- **[ADR 0277](../adr/0277-keep-the-page-label-of-a-citation-mark-with-its-value.md)**：指摘 4 のほかはなし。
  - `CiteLocator`（`Citation.hs:25,75-76,94`）、U+00A0（`Html.hs:784`）、保持した空白の前の罰点 10000（`Japanese.hs:919-931,1430`）。
  - C1〜C6 のテストが五つのパッケージにある。仕様書、`diagnostics.md` の G07105、差異の文書に記述がある。
- **[ADR 0278](../adr/0278-use-the-places-of-line-adjustment-in-the-order-of-jlreq.md)**：指摘 1 と 3 のほかはなし。
  - `GlueKind`、`AdjustOrder`、`glueAmounts`（`KnuthPlass.hs:678-`）の配り方が 2 節のとおり。`defaultParams` は `AdjustUniform`。
  - 既定の順（`Style.hs:562-563`）、G03006 の検査、`code` での拒否、A1〜A11 と種類のテスト、roadmap、[ADR 0274](../adr/0274-prefer-pulling-in-and-limit-the-stretch-of-lines.md) のステータスの行。
- **[ADR 0279](../adr/0279-no-hanging-punctuation-inside-paragraph-boxes.md)**：指摘なし。
  - `composeUnit` が囲みの単位で `ceHanging` を偽にし、`pProtrusion` を `protrusion` だけにする（`Flow.hs:2343-2346`）。
  - H1〜H3（`BoxesSpec.hs:172-185`。横組みと縦組み、`protrusion` の両方、二つの頁に分かれる囲み）。仕様書とマニュアルの二か所。
- **[ADR 0280](../adr/0280-breaks-between-latin-word-boxes-follow-the-joined-word.md)**（0283、0285 で読み替え）：指摘なし。
  - L8 の回帰、W1〜W3、述語のテスト（`JoinedWordEnum.hs:863-912`）。設定は区間なし、`en`、`ja` と罰点 50、10000。
  - `enum.yml` の `GOLEM_ENUM_CITE_DEPTH=3` と `GOLEM_ENUM_JOINED_DEPTH=3`。README と仕様書。
- **[ADR 0281](../adr/0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md)**（0286 で読み替え）：指摘 2 のほかはなし。
  - 時間を量る段、`!cancelled()`、N1〜N3（`EnumSplitSpec.hs:105-133`）、N4 と N5（`scripts/ci/test.sh:3009-3129`、動かして通った）、README、`CONTRIBUTING.md`。
- **[ADR 0282](../adr/0282-record-what-the-implementations-of-adr-0274-and-0275-decided.md)**：指摘なし。
  - 0274、0275、golem-layout 0049 のステータスの行、仕様書の連数字の項目（`specifications.md:5421,5457`）、注釈のリンク。
- **[ADR 0283](../adr/0283-decide-the-roles-of-characters-of-both-scripts-across-inline-boundaries.md)**（引用の印は 0298）：指摘なし。
  - `textEdges` と `edgeOf`（`Japanese.hs:483-539`）、E1〜E4 と述語のテスト、driver の `pd-merry-wives` の回帰。
  - 仕様書の「既知の不具合」の項目と、列挙の狭め方の文が消えている。golem-layout 0030 のステータスの行。
- **[ADR 0284](../adr/0284-merge-spaces-on-both-sides-of-an-inline-boundary.md)**：指摘なし。
  - `mergeSpaces`（`Japanese.hs:394-409`）、S1〜S5（`JoinedWordEnum.hs:840-912`）、driver のテスト（`AlignSpaceSpec.hs:40`）、仕様書。
- **[ADR 0285](../adr/0285-read-soft-hyphens-at-inline-boundaries-in-the-joined-word.md)**（notice の一部は 0297）：指摘なし。
  - H1〜H5 と述語のテスト（`JoinedWordEnum.hs:697-708,912`）、driver のテスト（`SoftHyphenSpec.hs:49`）、0272 と 0280 のステータスの行、仕様書。
- **[ADR 0286](../adr/0286-leave-the-start-of-cabal-out-of-the-time-of-an-enumeration-area.md)**：指摘なし。
  - `enum-timings.sh` が `cabal list-bin` の実行ファイルを走らせ、`--median` を持つ。M1〜M4 は動かして通った。
  - `workflow_dispatch` の入力 `timings` と `medians` のジョブ、0281 のステータスの行、README、`CONTRIBUTING.md`。戻したもの（`fr`、R1、順の三通り）がコードの注釈と仕様書にある。
- **[ADR 0287](../adr/0287-keep-actions-write-of-the-ci-call-in-release-yml-for-the-caches-job-alone.md)**：指摘なし。
  - P1〜P4 は、今の二つのワークフローと `testdata/ci-permissions` の六つの組で動かして通った。
  - `release.yml:27-40` の注釈、仕様書（`specifications.md:8642`）、0228 のステータスの行、roadmap に CI-01 がない。
- **[ADR 0288](../adr/0288-serve-no-file-whose-real-path-leaves-the-root-of-the-browser-checks.md)**：指摘なし（bind の要るテストは未確認）。
  - `servedFile` と起動のときの `realpath`（`scripts/browser/serve.mjs:54-76`）、ヘッダーの注釈、S1〜S4 のテスト、仕様書（`specifications.md:1474`）、roadmap に B-01 がない。
- **[ADR 0289](../adr/0289-bound-the-input-and-the-memory-of-the-wasmtime-host.md)**：指摘なし（`browser.yml` の段は未確認）。
  - 上限、`uint32_t`、確保の失敗の文、`wasmtime_config_wasm_memory64_set(config, false)`（`scripts/wasm/run-wasmtime.c:36-37,79,150-171`）。
  - `browser.yml:217-240` の H1 と H2、`test.sh` の H4（動かして通った）、仕様書（`specifications.md:752-`）、roadmap に WT-01 と WT-02 がない。
- **[ADR 0290](../adr/0290-keep-the-cost-of-a-table-within-the-cell-limit-and-measure-where-it-goes.md)**：指摘なし。
  - 記録 `docs/benchmarks/2026-11-10-cost-of-tables-within-the-cell-limit.md` に、五つの大きさ、プロファイル、マシン、GHC、コミットがある。
  - 割り当ては 1 乗（指数 0.985〜0.999）と記録しているので、roadmap に項目を足す条件に当たらない。roadmap に T-02 がない。

---

# [ADR 0291](../adr/0291-run-the-tests-of-every-package-on-every-change.md)〜0305 の乖離の監査（main = 888dc03b293dbb57cd5185cb69e9e8f247d6f831）

## 進め方と制約

- 作業ツリーは古い HEAD (e313e3b0) のままなので、リポジトリには触れず、`git archive 888dc03b | tar -x` で `/private/tmp/claude-501/-Users-tett23-repositories-src-github-com-tett23-golem/cb1691be-4aee-4682-b663-ec1ca710eb2d/scratchpad/m2` に展開して読んだ。以下の `file:line` はすべて 888dc03b のもの。
- `git fetch origin main` は sandbox のネットワーク制限で失敗した (github.com:22)。888dc03b はローカルに既にあり、`git rev-parse origin/main` は 888dc03b を返した。
- `gh` の読み取りだけの呼び出し (リポジトリの Actions の設定、夜間ジョブの結果とログ) は sandbox の外で 4 回動かした。書き込みはしていない。
- **未確認**: `cabal build` / `cabal test` と `scripts/ci/test.sh` の全体は動かしていない (展開先は git リポジトリではなく、ビルドも重い)。Haskell のテストは、存在と名前と中身を読んで確かめただけである。各 ADR が「プルリクエストの説明に書く」とした手での確かめ (0292 の後退の検出と揺れ、0300 の B1〜B3、0303 の I2〜I6、0304 の時間) は確かめていない。
- 後続 ADR による置き換えはステータスの行に従った: 0292→0301、0293→0307 (3 の preopen)、0297→0305 (N4)、0299→0306 (最大常駐)、0303→0309 (Safari の WebContent の例外)。0293 と 0299 は、どちらも今は実装済みの扱い (superseded の部分つき) である。

## 指摘

### 1. root [ADR 0293](../adr/0293-run-the-test-suites-of-the-packages-of-golem-wasm-on-wasm32-every-night.md) の A2・A3: 夜間の `wasm-tests.yml` が 2026-11-12 から毎晩落ちている (violation)

- ADR: `docs/adr/0293-...md:94-95` (A2「一覧のほかは通る」、A3「一覧は今落ちる」)、`:62-64` (一覧にないテストが落ちたら落ちる、一覧のテストが通ったらそれも落ちる)。`docs/adr/0307-...md` の「5. 文書」は、毎晩の `wasm-tests.yml` が通ってから 0293 を採択にするとしている。
- 実態: `gh run list --workflow wasm-tests.yml --limit 6` は 6 回とも `schedule failure` (2026-11-12T01:40Z から 2026-11-17T02:37Z、最新は 8e8e0fb9)。最後の成功は `schedule 6adc1c27 2026-11-11T00:14:55Z`。
- 最新の実行 44004335314 の `--log-failed` の要る行:
  ```
  A2 golem-driver-test: failed: ...untrusted projects (docs/adr ADR 0035).Golem ADR 0329 O2: build as a symbolic link out of the project is G08013, and nothing there is removed
  A2 golem-driver-test: failed: ...Golem ADR 0329 O1: a broken output link remains G08013
  A2 golem-driver-test: failed: ...Golem ADR 0329 O3 and O4: build removes selected regular .DS_Store files
  A2 golem-driver-test: failed: ...Golem ADR 0329 O4: a .DS_Store link and its target remain
  A2 golem-driver-test: failed: ...Golem ADR 0329 O4: Finder cleanup stays in real visible project folders
  A2 golem-driver-test: failed: ...Golem ADR 0326 B3: prod failure keeps a linked PDF directory's target
  A3 golem-driver-test: listed, but passes or is not a test of the suite: ...build as a symbolic link out of the project is G08013, and nothing there is removed
  A2 golem-emet-test: failed: golem-emet.the .emet language (docs/adr/0160).the limit of steps.R5: a manuscript call and its REPL expression share the last available step
  A3 golem-svg-test: listed, but passes or is not a test of the suite: ...a path of 1,000,001 segments drawn by the drawing itself
  A3 golem-driver-test: listed, but does not pass natively: ...build as a symbolic link out of the project is G08013, and nothing there is removed   (skips ジョブ)
  ```
- 888dc03b でも同じ状態である。`git diff --stat 8e8e0fb9 888dc03b -- scripts/wasm/test-failures.tsv modules/golem-driver/test modules/golem-emet/test .github/workflows` は空。
  - `scripts/wasm/test-failures.tsv:57` は古い名前「build as a symbolic link out of the project is G08013, ...」を載せているが、テストは `modules/golem-driver/test/SecuritySpec.hs:49` で「Golem [ADR 0329](../adr/0329-output-path-file-diagnostic.md) O2: build as a symbolic link ...」に改名されている。
  - `Golem ADR 0329 O1`、`Golem ADR 0326 B3`、`R5: a manuscript call` (`modules/golem-emet/test/LanguageSpec.hs:508`) は一覧に 0 件 (`grep -cF` で確かめた)。
  - `scripts/wasm/test-failures.tsv:292` の golem-svg の行は、テスト (`modules/golem-svg/test/SecuritySpec.hs:405`) が今もあるのに A3 で「通るか、スイートのテストでない」とされた。通るようになったのか名前の道が変わったのかは未確認。
- 食い違い: 一覧が後の変更 ([ADR 0326](../adr/0326-discard-stale-pdf-after-build-errors.md)、[0329](../adr/0329-output-path-file-diagnostic.md) など) に追随しておらず、A2 と A3 が成り立っていない。ステータスの行 (`docs/adr/0293-...md:3`) は実装済みの扱いである。

### 2. root [ADR 0296](../adr/0296-pin-every-github-action-by-commit-sha.md) の I6 と「版の上げ方」: `advisories.yml` の `actions` ジョブが 2026-11-11 から毎日落ちたまま (violation)

- ADR: `docs/adr/0296-...md:147` (「`actions` ジョブが失敗したら、手元で `update` を動かし、プルリクエストを出す」)、`:202` (I6)。
- 実態: `advisories.yml` の直近 7 回 (2026-11-11 から 11-17) はすべて `actions=failure`。実行 44015257617 のログ:
  ```
  jdx/mise-action: the newest is v5.2.9 (236a21c3...), pinned v5.2.7 (b44d12e7...)
  cachix/install-nix-action: the newest is v31.11.5 (3dc140bf...), pinned v31.11.3 (75c75c31...)
  ```
  `verify` は通っている (`151 uses: lines checked`)。
- 888dc03b の固定: `.github/workflows/*.yml` の `jdx/mise-action@b44d12e7... # v5.2.7` (2 行) と `cachix/install-nix-action@75c75c31... # v31.11.3` (1 行)。`tett23/adr-guard` は v0.13.1 に上がっている ([ADR 0387](../adr/0387-update-adr-guard-to-v0.13.1-and-migrate-status-lines.md)) ので、版を上げる手順そのものは使われているが、この二つは 7 日間上がっていない。
- 補足: 11-17 は `wasmtime` ジョブも落ちている ([ADR 0157](../adr/0157-check-wasmtime-pin-against-advisories.md) の範囲で、今回の範囲の外)。

### 3. root [ADR 0302](../adr/0302-full-width-glyphs-for-punctuation-and-boxes-for-narrower-ones.md) のテスト設計: テストの置き場所と、欠けている場合 (missing、軽い)

- ADR: テスト設計の「golem-typeset」の N6・N7 と「golem-layout」の N8、「golem-driver」の N9 (隣が和文の字の行、隣が空白の行、行の終わりの行、負のトラッキングだけで重なる行)。
- 実態:
  - N6・N7 の `shapingOf` のテストは golem-typeset になく、`modules/golem-driver/test/PunctuationWidthSpec.hs:111-128` にある。理由は同ファイルの `:1-5` に書いてある (golem-typeset のテストは golem-layout とフォントに依らない)。`rg -c 'punctuation-width|PunctuationFont|lkFullWidthPunctuation' modules/*/test/` は golem-project、golem-driver、golem-layout の `AdjustOrderSpec.hs` (表示から欄を消すだけ) にしか当たらない。
  - golem-layout の N8 (段落スタイルと入れ子の文字スタイルから `Look` の値が決まること) にあたるテストはない。`Look` の欄を決めるのは golem-typeset (`modules/golem-typeset/src/Golem/Typeset/Fonts.hs:476`、`:557`) で、確かめているのは golem-driver の `PunctuationWidthSpec.hs:141-163` だけである。そこは段落スタイル、文字スタイル一段、段落 `"font"` に文字 `"full-width"` の組で、**入れ子の文字スタイル** と **`based-on` の鎖を通した `Look`** の組はない (`based-on` は golem-project の `Main.hs:2195` 付近で定義の値としては確かめている)。
  - N9 の「隣が空白の行」の組がない。`PunctuationWidthSpec.hs:184-193` の入力は `あ”い`、`う”え`、`お”` (段落の終わり)、`か[style tight: ”]き` だけである。
- 実装そのもの (既定の `fwid`、幅の機能が勝つ規則、`narrowPunctuation`、`punctuation-width`、G07126、文書、[ADR 0053](../adr/0053-no-palt-on-jlreq-punctuation.md) のステータス) は読んで ADR と合っていた (下の「問題なし」)。

### 4. root [ADR 0299](../adr/0299-force-a-composed-table-without-turning-it-into-a-string.md) のテスト設計: I2・I3 のテストの置き場所 (doc mismatch、軽い)

- ADR: `docs/adr/0299-...md` のテスト設計「golem-typeset のテストに ... 足す」。
- 実態: `modules/golem-driver/test/ForceTableSpec.hs` にある (golem-typeset のテストに `forceTable` はない)。理由は同ファイルの `:1-7` に書いてある。テストの名前は I2、I3 を持つ。

### 5. root [ADR 0303](../adr/0303-check-only-the-processes-a-test-started.md) の 3: SKIP の行の文言 (doc mismatch、ごく軽い)

- ADR: 「`SKIP compare.sh: the children of the host (pgrep cannot list processes)` を出す」。
- 実態: `scripts/ci/test.sh:3931` は `skip 1 "compare.sh: the children of the host (pgrep -P cannot list processes)"` で、`skip` (`:51-54`) は `SKIP 1 compare.sh: ... (pgrep -P cannot list processes)` と出す。数と `-P` が入り、ADR の文字列とは一致しない。

## 問題が見つからなかった ADR (確かめたこと)

- **0291**: 仕様書 `docs/specifications.md:564` に理由と記録へのリンクがある。`docs/ci-timings/2026-11-10-the-build-runners-that-finish-last.md` がある。ロードマップに「変更のないパッケージ」の項目はない (`grep` 0 件)。テストを選ぶ仕組みは足されていない。
- **0292 / 0301**: `sh scripts/ci/suite-limits.sh --check` は exit 0。境界の入力を実際に通した (`5.1 秒 → 11`、`5 と 10 → 15`)。`suite-timeout.sh` は L1〜L3、L6 のとおり。`scripts/ci/test.sh:1056-1158` に L1〜L6、G1、G2 の名前のテストがある。`ci.yml:69` の `changes` で `--check` が走る。`golem-layout-test` の行は x86_64 142、aarch64 116 (0301 の 5 のとおり)。`modules/golem-syntax/test/Main.hs:109` は 30 秒。[ADR 0073](../adr/0073-time-bounds-in-tests.md) と [golem-lsp ADR 0002](../golem-lsp/adr/0002-utf8-position-encoding.md) のステータスに 0292 がある。仕様書 `:569-590`、`CONTRIBUTING.md:144-150` に規則がある。ロードマップの項目はない。
- **0293 (指摘 1 のほか)**: `scripts/wasm/run-tests.mjs:33-42` は `/` と `/tmp` を preopen し、環境の変数は二つだけ、stdin は `/dev/null`、後で一時のディレクトリを消す (0307 のとおり)。`sh scripts/ci/test-suites.sh wasm` は 27 スイートで、範囲の外のパッケージは入らない。`cabal.project.wasm-tests`、`wasm-freeze.sh` の検査、`wasm` ジョブの 120 分、要約、A1 (`test.sh:3310-3329`)、A4 (`check-skips.sh`)、A5 (`golem-test-support/test/Main.hs:77`)、README、仕様書 `:687-713`、ロードマップ `:130` がある。`pull_request` では走らない。
- **0294**: `scripts/visual/fetch-shem.sh:34` は 0.1.0-rc9。`scripts/visual/pdf-subset.txt` (47 種)、`modules/golem-driver/test/VisualSubsetSpec.hs:62-71` の V1・V2 (`contentOperations` を使う)、仕様書 `:1338` と `:1420-1421`、ロードマップの手で確かめる項目 `:244` がある。`figures-external` は入力にない。V4 (shem のリリースノート) は未確認。
- **0295**: `modules/golem-layout/src/Golem/Layout/Table.hs:73-91` は残りを水位にある列だけに配る。`ColumnWidthInvariantsSpec.hs` に C1〜C8 と素朴な探索、上限 (PR は (4,3) と (3,3)、毎晩は (5,4) と (4,3))。`Main.hs:1079` に `Right [1, 1, 0]` の例、hedgehog の性質も残る。`enum.yml:221-225` に `!cancelled()` つきの段。仕様書 `:4570`、README `:923`、[golem-driver ADR 0037](../golem-driver/adr/0037-table-column-widths.md) のステータスがある。夜間の `enum.yml` は直近 4 回成功 (8e8e0fb9 まで)。
- **0296 (指摘 2 のほか)**: mktemp の代用を `PATH` に置いて `sh scripts/ci/actions-pins.sh check` を動かし、`151 uses: lines checked`、exit 0。`uses:` は `./.github/workflows/ci.yml` のほかすべて 40 桁の SHA と版の注釈で、同じリポジトリは同じ SHA。`ci.yml:116-117`、`advisories.yml:35-52` (`contents: read`、10 分、`verify` と `latest`)、`test.sh` の I1〜I7、[ADR 0035](../adr/0035-security-hardening.md)・0044・0085 のステータス、CONTRIBUTING (日英)、開発者のマニュアル、仕様書 `:1271-1277` がある。`gh api repos/tett23/golem/actions/permissions` は `"sha_pinning_required":true`。Dependabot やロックファイルは足されていない。
- **0297 / 0305**: `Japanese.hs:1780-1790` の `roleOf` は 1〜4 の順のとおり。メッセージは `Flow.hs:1264`、`docs/diagnostics.md:10747-10815`、`Embedded.hs` で ADR の文と一致。`JoinedWordEnum.hs:797-803` に N1〜N5、`SoftHyphenSpec.hs:119` に golem-driver の N1。`NoBreakEnum.hs:355-421` に S1・S2 と述語のテスト。[ADR 0285](../adr/0285-read-soft-hyphens-at-inline-boundaries-in-the-joined-word.md)・0272・0297 のステータス、仕様書 `:5589-5607`、`:5628`、`:5756-5757`、`docs/markup.md:1507`、`manual/appendices/a-markup.gm:407` がある。上限は PR 2、毎晩 3 のまま。
- **0298**: `dualAtMark` はテストにない (`grep` 0 件)。`CiteBreakEnum.hs:373-383` に M1・M2、`JoinedWordEnum.hs:601-608` に M3・M4 (`stoppers` から引用の印が外れている)、`BookLanguageSpec.hs:117` に golem-driver のテスト。[ADR 0283](../adr/0283-decide-the-roles-of-characters-of-both-scripts-across-inline-boundaries.md) のステータス、仕様書 `:5821` がある。
- **0299 / 0306 (指摘 4 のほか)**: `Flow.hs:2618-2628` の `forceTable` は `show` も `deepseq` も使わず、ADR の深さで評価する。呼び出しは `:3231`。記録 `docs/benchmarks/2026-11-10-force-a-composed-table-without-show.md` は割り当て 52.3〜53.2% 減。`docs/benchmarks/2026-11-11-force-table-heap-profiles.md:44-49` の比は 0.960〜1.018 で、0306 の 1.05 以下。脚本二つと結果がある。
- **0300**: `golem-driver.cabal:199-202`、`:251-254` の `if flag(plugins)`、`Main.hs` と `GlobalMain.hs` の CPP、`ImportSpec.hs:38` の `Int64`、`HexSpec.hs:26` の `maxOffset`、仕様書 `:695-696` 付近の記述がある。B1〜B3 の比較は未確認。
- **0303 (指摘 5 のほか)**: `test.sh:3904` の偽のホスト、`:3914-3936` の断言と SKIP、`:11` の後始末、`:4542-4588` の静的な検査と I8 のテスト、`testdata/process-checks/` の二つがある。対象の 11 ファイルに同じ正規表現を当て、当たる行は 0。`scripts/wasm/test/browser-leftovers.sh` の WebContent の読み取りは [ADR 0309](../adr/0309-run-golem-wasm-in-a-worker-of-the-browser-page.md) の例外にあたる。
- **0304**: `enum.yml:163` と `:169-174` の式と変数は ADR のとおり。`test.sh:3024-3054` に KS1・KS2、`PaginateInvariantsSpec.hs:549` に KS3・KS4、`:599-606` の抜き取りと縮小。仕様書 `:5023-5024`、README `:913`、[ADR 0261](../adr/0261-keep-options-of-paragraph-styles.md) のステータスがある。

## ステータスの行

0291〜0305 のステータスに、実装が欠けているのに採択、という形のものは見つからなかった。ただし 0293 は、指摘 1 のとおり、不変条件 A2・A3 が今の main で成り立っていない。
