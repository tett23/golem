# ADR 0016: 版面、ページ番号の収束、縦組みの傍注、フォントの診断のコード

ステータス: 採択

## 文脈

PDF の経路の診断のうち、次の六つのコードには、条件とメッセージを定めた ADR がない（[docs/diagnostics.md](../../diagnostics.md) では「ADR なし」）。

- **G0701**：`style.toml` の版面の設定から、版面を計算できない（golem-layout-spec の `Golem.LayoutSpec.pageGeometry`）。
- **G0721**：ページ番号の参照が収束しない（`Golem.Driver.Pdf.fixpoint`）。[golem-driver ADR 0007](0007-pdf-index-and-bibliography.md) はメッセージに索引の語を加えたが、コードそのものは定めていない。
- **G0732**：縦組みの版面で傍注を使った（golem-layout の `Golem.Layout.Japanese.verticalSidenotes`）。[golem-layout ADR 0006](../../golem-layout/adr/0006-sidenotes.md) は縦組みの段落の中の傍注をエラーにすると定め、[golem-driver ADR 0006](0006-pdf-sidenotes.md) は既存のコードとして使うが、どちらもコードを定めていない。
- **G0801**：フォントを読まない `noFontProvider` で PDF を作ろうとした（`Golem.Driver.Pdf`）。
- **G0803**：フォントのファイルを OpenType として読めない（`Golem.Driver.Fonts`）。
- **G0804**：フォントの `fsType` が埋め込みを禁じている（`Golem.Driver.Fonts`）。[golem-font ADR 0001](../../golem-font/adr/0001-shaping-and-metrics.md) がエラーにすると定めたが、コードは定めていない。

この ADR は、六つのコードの条件、重大度、メッセージ、位置を、今の実装に合わせて定める。
あわせて、六つのコードと、同じ経路の G0725（[docs/adr/0006](../../adr/0006-paragraph-indent.md)）と G0802（[golem-project ADR 0004](../../golem-project/adr/0004-font-file-check-per-target.md)）について、実装を読んで見つけた次の問題に結論を出す。

**位置が `FileId 0` を指す**：G0701、G0721、G0725 の段落スタイルの検査、G0801、G0802 から G0805 の `Golem.Driver.Fonts` の分は、位置を `mkSpan (FileId 0) 0 0` にしている。
`FileId 0` は `manifest.toml` なので、`style.toml` の誤りである G0701、G0725、フォントの診断が、`manifest.toml` の先頭に表示される。
G0702（[golem-pdf ADR 0004](../../golem-pdf/adr/0004-crop-marks-and-bleed.md)）と、`targetFileDiagnostics` の G0802、G0806 は、すでに `style.toml` の先頭（`style.toml` がなければ `manifest.toml` の先頭）を指している。

**G0701 の判型と位置の検査が G0306 と分かれている**：`style.toml` の検査（G0306）は、`x` を含まない未知の判型の名前を報告し、`x` を含む名前は見逃す。
見逃した名前は、PDF の版面の計算で G0701 の `未知の判型です` になる。
同じ「未知の判型」が、名前によって別のコードになる。
マスターページの `running-head` と `folio` の `position` も、`style.toml` の読み込みでは検査せず、版面の計算で G0701 の `未知の位置です` になる。

**G0701 を `golem check` が報告しない**：版面の計算は PDF のレイアウトの中で行うので、`golem check`（`optCheckOnly`）は G0701 を出さない。
`golem check` が通っても、`golem build` が G0701 で止まる。

**G0725 の二つの条件**：G0725 は、`style.toml` の段落スタイルの検査（行長が段落の文字の大きさの 8 字分に満たない）と、原稿の段落の検査（回り込む図版の脇で、字下げを引いた行の長さが 0 以下になる）の二つに使っている。
前者は `style.toml` を、後者は原稿の段落を指すべきで、直す場所が違う。
また、前者のメッセージは「本文の文字の大きさの 8 字分」と言うが、条件は段落スタイル自身の文字の大きさで比べる。

**G0802 の二つの条件**：G0802 は、フォントのファイルがない場合（[golem-project ADR 0004](../../golem-project/adr/0004-font-file-check-per-target.md)）に加えて、`style.toml` に本文のフォントの設定がない場合と、本文の役割にファイルが一つもない場合にも使っている。
後の二つは設定の欠けであり、ファイルを置いても直らない。
また、後の二つは `Golem.Driver.Fonts` がレイアウトの直前に出すので、`golem check` は報告しない。
本文の役割が `body` でない場合（`[fonts]` に `body` がなく、名前の順で最初の役割を本文にする場合）も、メッセージは `[fonts.body]` と書く。

**G0801 のメッセージが古い**：G0801 のメッセージは `フォントの処理（golem-font ADR 0001、0002）が未実装のため` と言うが、golem-font は実装済みであり、`golem` のコマンドは `golemFontProvider` を使う。
G0801 を出すのは、テストが使う `noFontProvider` だけである。

**G0803 と G0804 が最初の一つしか出ない**：`golemFontProvider` は、読み込めないフォントのうち最初の一つだけを報告する。
二つのファイルが壊れていれば、一つ直すたびにビルドし直さないと、もう一つが分からない。

**G0804 の判定が `fsType` の組み合わせを見逃す**：golem-font の `loadFont` は、`fsType` がちょうど `0x0002` のときと、ビット 9（`0x0200`、ビットマップの埋め込みだけを許す）が立っているときに埋め込みを禁じる。
OpenType の仕様では、ビット 0 から 3 は使用の許可を表し、複数が立っていれば最も緩い許可に従う。
ビット 1（制限付きのライセンス）とビット 8（`0x0100`、サブセット化の禁止）が立った `0x0102` は、`0x0002` と等しくないので通ってしまう。
また、Golem は常にサブセットを埋め込む（[golem-font ADR 0002](../../golem-font/adr/0002-subsetting-and-embedding.md)）ので、ビット 8 の立ったフォントを埋め込むことは、それ自体がライセンスに反する。

**G0732 のメッセージが条件より狭い**：`verticalSidenotes` は、段落だけでなく、図版のキャプション、脚注の本文、圏点や色や文字スタイルの中の傍注も報告するが、メッセージは「縦組みの段落の中」と言う。

## 実装すること

### 既存の振る舞いの追認

この節のコードは、どれも重大度がエラーであり、プロファイルによって変わらない。
どれも PDF をターゲットに含むビルドでだけ出る。
LSP は PDF のレイアウトを行わないので、どれも出さない。

#### G0701

`pageGeometry` が、次の順に検査し、最初に当てはまったものを一つだけ報告する。

| 順 | 条件 | メッセージ |
| --- | --- | --- |
| 1 | `style.toml` に `[page]` がない（`style.toml` がない場合を含む）。 | `style.toml に [page] がないため、版面を計算できません` |
| 2 | `[page]` の `size` が既知の判型でない。 | `未知の判型です: <名前>`（下の「変更」で G0317 に移す） |
| 3 | `[page.grid]` がない。 | `style.toml に [page.grid] がないため、版面を計算できません` |
| 4 | `[page.grid]` の `font-size` が、正の絶対的な寸法でない（`zw` など）。 | `文字の大きさは絶対的な寸法で書いてください` |
| 5 | `characters`、`lines`、`columns` のどれかが 0 以下か、`line-pitch` が `font-size` より小さい。 | `字数、行数、段数は 1 以上、行送りは文字の大きさ以上にしてください` |
| 6 | 奇数ページか偶数ページの版面が、判型の外にはみ出す。 | `版面がページからはみ出しています` |
| 7 | `[sidenotes]` があり、版面が縦組みである。 | `縦組みの版面には傍注欄を設けられません` |
| 8 | 奇数ページか偶数ページの傍注欄が、判型の外にはみ出す。 | `版面と傍注欄の合計がページからはみ出しています` |
| 9 | `[masters.<名前>]` の `running-head` か `folio` の `position` が、`top-outside`、`top-inside`、`top-center`、`bottom-outside`、`bottom-inside`、`bottom-center` のどれでもない。 | `未知の位置です: <位置>`（下の「変更」で G0317 に移す） |

G0701 が出ると、PDF を書かない。

#### G0721

PDF のレイアウト（S2）は、ラベルのページと索引の印のページを仮定してレイアウトし、結果のページが仮定と一致するまで繰り返す（[golem-layout ADR 0003](../../golem-layout/adr/0003-pagination-and-s2.md)、[golem-driver ADR 0007](0007-pdf-index-and-bibliography.md)）。
上限の回数（`maxIterations`、5 回）のレイアウトで一致しなければ、G0721 を一つ出し、PDF を書かない。
繰り返しの途中のレイアウトがほかのエラーを出した場合は、そのエラーを返し、G0721 は出さない。

メッセージは `ページ番号の参照が収束しません: <並び>` である。
並びは、最後の二回のレイアウトでページの変わったラベルを名前の順に並べ、続けて、ページの変わった索引の印の語（`igTerms` を ` / ` でつないだもの）を印の位置の順に、重複を除いて並べ、`, ` でつなぐ。
目次のページ番号は繰り返しの外で決める（[golem-driver ADR 0009](0009-pdf-toc-page-numbers.md)）ので、並びに見出しは入らない。

#### G0732

版面が縦組みのとき、`sidenoteDiagnostics` は、本のすべてのインラインの列（段落、見出し、リストの項目、定義リストの語と定義、表のセル、図版のキャプション）を調べ、傍注（`[sidenote: ...]`）一つにつき G0732 を一つ出す。
圏点、色、文字スタイル、脚注の本文の中の傍注も数える。
位置は、傍注の位置である。
縦組みのときは、G0734 と G0735（[golem-driver ADR 0006](0006-pdf-sidenotes.md)）を出さない。
G0732 が一つでもあれば、PDF を書かない。

#### G0801

`noFontProvider` は、どの入力でも G0801 を一つ返す。
`golem` のコマンドは `golemFontProvider` を使うので、利用者が G0801 を見ることはない。
テストが、フォントなしで PDF の経路の手前までを確かめるために使う。

#### G0803 と G0804

`golemFontProvider` は、PDF が使う役割（`usedRoles`）のフォントのファイルを、役割の順、和文、欧文の順に読む。

- **G0803**：golem-font の `loadFont` が `Unreadable` を返した。ファイルを OpenType（TrueType の輪郭か CFF の輪郭）のフォントとして開けない場合である。メッセージは `フォントを読み込めません: <パス>`。
- **G0804**：`loadFont` が `EmbeddingRestricted` を返した。メッセージは `ライセンスが埋め込みを禁じているフォントです（fsType <値>）: <パス>`。判定は下の「変更」で改める。

パスは `style.toml` に書いたとおりの文字列である。
G0803 か G0804 が出ると、PDF を書かない。

### 変更

**位置を `style.toml` の先頭にする**：G0701、G0725 の段落スタイルの検査、G0801、G0802 から G0805 のうち `Golem.Driver.Fonts` が出す分、新設の G0807 の位置を、`style.toml` の先頭（`mkSpan <style.toml の FileId> 0 0`）にする。
`style.toml` がないときは、G0702 と同じく `manifest.toml` の先頭にする。
このために、`PdfInput` に、診断を置くファイルの `FileId`（`piStyleFile`）を足し、golem-driver が G0702 と同じ規則で選ぶ。
`pageGeometry` は、この `FileId` を引数に取る。
`FontProvider` の `loadFonts` も、ルートと `Style` に加えてこの `FileId` を受け取る形にする。

**G0721 の位置**：G0721 の位置を、並びの最初のもの（ラベルならそのラベルを付けたブロック、索引の語ならその印）の位置にする。
並びの二つ目以降のものの位置を、関連情報に `ページが定まりません` として載せる。
メッセージは変えない。

**判型と位置の検査を style.toml の読み込みに移す**：`style.toml` の検査（`Golem.Project.Style` の `checks`）は、`x` を含むかどうかにかかわらず、`pageSize` の知らない判型の名前を G0317 の `未知の判型です: <名前>` とする。
マスターページの `running-head` と `folio` の `position` が上の 6 つのどれでもなければ、G0318 の `未知の位置です: <位置>` とする。
G0317（判型の誤り）は [golem-project ADR 0005](../../golem-project/adr/0005-page-size-by-dimensions.md) と共有し、G0318（マスターページの位置の誤り）はこの ADR で新しく割り当てる。どちらも未使用であり、`style.toml` の一般の誤りの G0306 から欄ごとの誤りを分けるために、提案中の ADR のあいだで G0317 から G0322 を分けて割り当てた。
`pageGeometry` の 2 と 9 の検査は、到達しなくなるので消す。
`style.toml` の値の誤りは、LSP と `golem check` を含めて、ターゲットにかかわらず報告されるようになる。
寸法で判型を書く方法を実装するときは、その ADR で G0317 の検査を広げる。

**G0701 を `golem check` でも出す**：PDF をターゲットに含むときは、ビルドと `golem check` の両方で、レイアウトの前に `pageGeometry` を呼び、G0701 を報告する。
G0702 と同じく、PDF を書く前の検査として扱う。

**G0725 を分け、G0728 を新設する**：G0725 は、段落スタイルの検査だけに使う。
条件は今のまま、`style.toml` のそれぞれの段落スタイルについて、版面の段の行長から `indent` と `max 0 first-line-indent` を引いた値が、その段落スタイルの文字の大きさの 8 字分に満たないこととする。
メッセージを `段落スタイルの字下げが大きすぎます。行長を段落の文字の大きさの 8 字分以上残してください: <名前>` に改める。
位置は上のとおり `style.toml` の先頭とし、G0701 と同じく `golem check` でも出す。
回り込む図版の脇の検査は、G0728 とする。
条件は今の G0725 の二つ目の場合のまま、回り込む図版の脇の段落で、図版の脇の行の長さから字下げを引いた値が 0 以下になる行があることとする。
重大度はエラー、メッセージは `回り込む図版の脇で、字下げを引くと行が残りません`、位置はその段落の位置とし、段落一つにつき一つ出す。
G0726 と G0727 はほかの提案の ADR が使うので、レイアウトの区分（07）の、その次の使っていない番号を当てる。

**G0802 を分け、G0807 を新設する**：G0802 は、PDF が使う役割のフォントのファイルがない場合だけに使い、[golem-project ADR 0004](../../golem-project/adr/0004-font-file-check-per-target.md) のとおりとする。
`style.toml` に本文のフォントの設定がない場合は、G0807 とする。
重大度はエラーで、条件とメッセージは次の二つである。

- `[fonts]` に役割が一つもない：`style.toml に本文のフォントがありません。[fonts.body] を書いてください`
- 本文の役割（`bodyRole`）に `ja` も `latin` もない：`[fonts.<役割>] にフォントのファイルがありません`。`<役割>` には、`body` に限らず実際の本文の役割の名前を書く。

G0807 は、`Golem.Driver.Fonts` ではなく、`targetFileDiagnostics` が PDF のターゲットについて出す。
したがって、`golem check` も報告し、G0807 があれば PDF のレイアウトに進まない。
G0802 と同じく、LSP は出さない。
出力の区分（08）の、最後に使った G0806 の次の番号を当てる。
`Golem.Driver.Fonts` の、ファイルを解決できない場合の G0802 は、`targetFileDiagnostics` の G0802 の後では到達しないが、`FontProvider` を単独で使う場合のために残し、メッセージと位置を `targetFileDiagnostics` の G0802 にそろえる。

**G0801 のメッセージ**：`フォントを読まない設定（noFontProvider）では PDF を出力できません` に改める。
コードは使い回さないので、G0801 はこのまま `noFontProvider` に残す。

**G0803 と G0804 をすべて報告する**：`golemFontProvider` は、読み込めないフォントのファイルをすべて、パスごとに一つずつ報告する。
二つの役割が同じパスを指す場合は、一つにまとめる。
G0805 の検査は、G0803 と G0804 がないときだけ行う。

**G0804 の判定と表記**：golem-font の `loadFont` の判定を次のとおりに改める。
次のどれかに当てはまれば `EmbeddingRestricted` とする。

- ビット 1（`0x0002`）が立ち、ビット 2（`0x0004`）とビット 3（`0x0008`）が立っていない。最も緩い許可が制限付きのライセンスである場合である。
- ビット 8（`0x0100`、サブセット化の禁止）が立っている。Golem はサブセットしか埋め込まないためである。
- ビット 9（`0x0200`、ビットマップの埋め込みだけを許す）が立っている。

メッセージの `<値>` は、`0x0102` のように `0x` と 4 桁の大文字の 16 進数で書く。

**G0732 のメッセージ**：`縦組みの版面では傍注を使えません。脚注に替えてください` に改める。
段落の外の傍注も同じコードで報告していることに、メッセージを合わせる。

[docs/diagnostics.md](../../diagnostics.md) の G0701、G0721、G0725、G0732、G0801、G0802、G0803、G0804 の節を改め、G0728 と G0807 の節を足し、各節の「ADR」の項にこの ADR を書く。
[docs/specifications.md](../../specifications.md) と README に G0802 と G0725 の説明があれば、あわせて改める。

## 実装しないこと

- G0701 の検査を、`style.toml` の位置を持つ形にすること。`Style` は位置を持たないので、位置は `style.toml` の先頭にとどめる。G0306 と同じ扱いである。
- G0732、G0734、G0735 を `golem check` で出すこと。これらは本の全体を調べる必要があり、`style.toml` だけで決まる G0701 と G0725 とは事情が違う。
- G0721 の上限の回数（5 回）の変更。
- G0805 の条件と位置以外の変更。位置は上のとおり `style.toml` の先頭に改めるが、条件とメッセージは [golem-driver ADR 0003](0003-pdf-heading-styles.md) のとおりとする。
- G0806 の変更。[golem-project ADR 0004](../../golem-project/adr/0004-font-file-check-per-target.md) のとおりとする。

## テスト設計

今のテストの状況は次のとおりである。

- G0701：`modules/golem-layout-spec/test/Main.hs` が、はみ出しと傍注欄の誤りが `Left` になることだけを確かめている。コード、メッセージ、位置は確かめていない。
- G0721：テストがない。
- G0725：`modules/golem-driver/test/Main.hs` が、字数の少ない版面の字下げで G0725 になることを、コードだけで確かめている。
- G0732：`modules/golem-driver/test/Main.hs` が、縦組みのスタイルの傍注が G0732 になることを、コードだけで確かめている。
- G0801：`modules/golem-driver/test/Main.hs` が、`noFontProvider` で G0801 になることを、コードだけで確かめている。
- G0802：`modules/golem-driver/test/Main.hs` と `modules/golem-cli/test/Main.hs` が、ファイルのないフォントと、フォントの設定のない `pdfStyle` の両方を G0802 として確かめている。
- G0803：テストがない。
- G0804：`modules/golem-font/test/Main.hs` が、`fsType` が `0x0002` と `0x0200` のフォントで `EmbeddingRestricted` になることを確かめている。golem-driver のテストはない。

次のテストを足すか改める。
変更の分は、テストを先に足して失敗させてから実装する。

- `modules/golem-layout-spec/test/Main.hs`：表の 1、3 から 8 の条件それぞれについて、`pageGeometry` が G0701 を一つだけ返し、メッセージが表のとおりで、位置が引数の `FileId` の先頭であること（位置は変更）。
- `modules/golem-project/test/Main.hs`：`size = "148x210"` と、`position = "middle"` のマスターページが、それぞれ G0317 と G0318 の `未知の判型です` と `未知の位置です` になること（変更）。
- `modules/golem-driver/test/Main.hs`：
  - G0701：`[page.grid]` のない `style.toml` で、PDF のビルドが G0701 になり、位置の `FileId` が `evStyleFile` であること。`style.toml` のないプロジェクトでは `manifest.toml` の先頭であること。`optCheckOnly` の `build` も G0701 を報告すること（変更）。
  - G0721：`fixpoint` を公開し、仮定のページを受け取るたびにラベルのページを 1 と 2 で交互に返すレイアウトを渡して、G0721 が一つ出て、メッセージにそのラベルが並び、位置がそのラベルを付けたブロックであること（位置は変更）。途中のレイアウトがエラーを返すと、G0721 ではなくそのエラーになること。
  - G0725：既存のテストに、新しいメッセージと `style.toml` の位置の確認を足し、`optCheckOnly` でも出ることを確かめる（変更）。
  - G0728：回り込む図版の脇の段落の字下げが行を残さない原稿で、G0728 がその段落の位置に一つ出て、G0725 が出ないこと（新設）。
  - G0732：既存のテストに、新しいメッセージの確認と、キャプションと脚注の中の傍注も G0732 になり、G0735 にならないことの確認を足す（メッセージは変更）。
  - G0801：既存のテストに、新しいメッセージと `style.toml` の位置の確認を足す（変更）。
  - G0802 と G0807：フォントの設定のない `pdfStyle` の既存のテスト（「a missing body font is reported」）を、G0807 の `style.toml に本文のフォントがありません` を期待する形に改める。`[fonts.mincho]` だけに `features` しかない `style.toml` で、`[fonts.mincho] にフォントのファイルがありません` の G0807 になること。`optCheckOnly` でも G0807 が出て、`FontProvider` が呼ばれないこと（新設）。
  - G0803：中身がフォントでないファイルを本文のフォントにして、G0803 になり、位置が `style.toml` の先頭であること。壊れたファイルを二つの役割に別々に指定すると、G0803 が二つ出ること（変更）。
  - G0804：`fsType` を `0x0002` に書き換えたフォントで、G0804 のメッセージが `fsType 0x0002` を含むこと（表記は変更）。
- `modules/golem-font/test/Main.hs`：`fsType` が `0x0102`、`0x0100`、`0x0302` のフォントが `EmbeddingRestricted` になり、`0x0000`、`0x0004`、`0x0008`、`0x0006`、`0x000A` のフォントが読み込めること（変更）。
- `modules/golem-cli/test/Main.hs`：ソースのコードがすべて [docs/diagnostics.md](../../diagnostics.md) に載っていることの既存の検査が、G0728 と G0807 の節の追加を確かめる。

## トレードオフ

G0725 と G0802 は、既存のコードの意味を狭め、外した条件に新しい番号を当てる。
番号を使い回さない規則（[golem-syntax ADR 0001](../../golem-syntax/adr/0001-source-spans-and-diagnostics.md)）には反しないが、外した条件で G0725 や G0802 を期待していた利用者の CI の設定は、新しい番号に直す必要がある。
v1 の前であり、直す場所の違う条件を一つのコードにしておく不便のほうが大きい。

判型と位置の検査を style.toml の読み込み（G0317 と G0318）に移すと、HTML だけを作るプロジェクトでも、不正な判型の名前がエラーになる。
今も `x` を含まない不正な名前は G0306 でエラーになっているので、`x` を含むかどうかで扱いが変わる今の状態より一貫する。

G0804 の判定を広げると、今は埋め込めているフォントのいくつかが埋め込めなくなる。
ライセンスに反する PDF を黙って作るよりは、ビルドを止めて書き手に判断させるほうを選ぶ。

G0721 の位置は、変わり続けたもののうち最初のものにとどめる。
収束しない原因は、並びのどれか一つの近くにあることが多いが、どれかは分からないので、ほかを関連情報に並べる。

## 参考文献

- Microsoft, "OS/2: OS/2 and Windows Metrics Table", OpenType specification, `fsType` の節。https://learn.microsoft.com/en-us/typography/opentype/spec/os2#fstype
