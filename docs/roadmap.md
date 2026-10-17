# Golem のロードマップ

Golem のどのバージョンで何を扱うかを、この文書にまとめる。
今の Golem の振る舞いは [仕様書](specifications.md) に書き、この文書には書かない。
バージョンごとの節に載る項目は、どれも今の Golem にはまだない。
ほかに、実装は終わったが手作業の確かめが残っている項目（手で確かめる項目）、決まっていない事項（未決事項）、扱わないと決めた事項（課題にしなかった事項）もここにまとめる。

どの項目も、着手するときに ADR を作成する。
採択済みの ADR があり、まだ実装していない項目には「（未実装）」と書き、その ADR へリンクする。
実装を終えたら、その項目をこの文書から消し、振る舞いを仕様書に書く。

## リリースの予定

今の計画では、v0.1.0-rc3、v0.1.0-rc4 の順にプレリリースを出し、rc4 の直後に v1.0.0 を出す。
これは今の時点の計画であり、変わりうる。
バージョンの付け方は、仕様書の [「バージョン」の節](specifications.md#バージョン) に従う。

## v0.1.0-rc3

- **数の糖衣構文 `##1##`**（未実装、[golem-parser ADR 0011](golem-parser/adr/0011-number-shorthand.md)）：数を `##1##` の形で書ける記法を加える。意味は ADR で決める。`[number-text ...]`（[docs/markup.md](markup.md)）と、数の抽象値との関係もその ADR で決める。

### PDF

- **本文の中のコードの背景の色**（未実装、[golem-driver ADR 0029](golem-driver/adr/0029-inline-code-background.md)）：コードの書体の役割、コードブロックの組み方は [golem-driver ADR 0017](golem-driver/adr/0017-pdf-code-blocks.md) で、技術書のためのコードブロックの機能は [golem-driver ADR 0023](golem-driver/adr/0023-code-block-book-features.md) で実装した。本文の中のコード（`[code: ...]`）の背景の色は扱っていない。
- **章末の注**（未実装、[golem-driver ADR 0026](golem-driver/adr/0026-chapter-end-notes.md)）：`[notes] placement = "chapter-end"` を読み込むが、どの出力も注の置き方を変えない。仕様書とマニュアルは章末に置けると書いていない形に直したが、章末の注そのものはまだない。
- **PDF の図版**（未実装、[golem-pdf ADR 0008](golem-pdf/adr/0008-pdf-figures.md)）：仕様は PDF（ベクター）の図版を置けると定めているが（仕様書の [「図版」の節](specifications.md#図版)）、実装（golem-pdf の `readImage`）は JPEG と PNG だけを受け付ける。マニュアルも PDF の図版を使えると書いている。仕様のとおり、PDF の図版を PDF の出力に置けるようにする。Web 用の代替画像の扱いも合わせて決める。
- **SVG の図版**（未実装、[golem-pdf ADR 0009](golem-pdf/adr/0009-svg-figures.md)）：仕様は SVG を v1 では扱わないと定めているが（仕様書の [「図版」の節](specifications.md#図版)）、v1 で扱えるようにする。開発者向けのマニュアルの図は、SVG を原稿にして PNG に描いたものを置いている。PDF の出力での描き方（ベクターのまま描くか、変換するか）と、HTML と EPUB でそのまま使うかを決める。
- **段落スタイルの罫線**（未実装、[golem-driver ADR 0027](golem-driver/adr/0027-paragraph-style-rules.md)）：段落スタイルに、段落の前と後に引く罫線（InDesign の段落境界線にあたるもの）を書けるようにする。見出しの下の罫線や、節の区切りの罫線に使う。長さ、太さ、間隔は、[golem-driver ADR 0024](golem-driver/adr/0024-rule-spec-and-footnote-separator.md) の罫線の指定の形で書く。長さの既定は、当面は段の行長（段の最大の長さ）に固定する。罫線を持つ段落は改ページと改段で分けず、一つのページ（段）に置く。その段落の注のうち、そのページに収まらないものは、次のページ（見開きで扱う場合は次の見開き）に回す。間隔と行の格子の合わせ方は、[未決事項](#未決事項) の「段落の罫線の間隔と行の格子」で決める。
- **合字のテキスト層**（未実装、[golem-driver ADR 0030](golem-driver/adr/0030-ligature-text-layer.md)）：PDF の ToUnicode が合字のグリフを一字目だけに対応させるので、PDF から文字列を抜き出すと fi、fl、ff、ffi が f になる（`Golem.Driver.Fonts` の `clusterText`）。十冊の fixture の英語の本と、テンペストで起きる。
- **改ページの手での制御**（未実装、[docs/adr 0030](adr/0030-manual-page-break-control.md)）：原稿で、ここで改ページしない、この先にこれだけの空きが要る、このページの行を一行増やす、といった指定を書く手段がない（TeX の `\nopagebreak`、needspace、`\enlargethispage` にあたるもの）。
- **PDF に置けない図版**（未実装、[golem-pdf ADR 0008](golem-pdf/adr/0008-pdf-figures.md)）：`golem build` は、JPEG と PNG として読めない `@figure` の画像（PDF の図版、壊れた画像）を、diagnostic を出さず、終了コード 0 のまま PDF から落とす。2026-10-16 の main の `golem build` で、`%PDF-1.4` だけのファイルと PNG でないファイルを `@figure` に置いて確かめた（PDF に画像は一つも入らなかった）。`golem preflight` は同じ二つを G0905 で報告する。置けない形式と壊れた画像のほかに落とす場合があるかは確かめていない。`golem build` のエラーにするかどうかは決めていない（[golem-cli ADR 0006](golem-cli/adr/0006-preflight.md)）。

### 記法と設定

- **ADR とコードの食い違い**（未実装、[docs/adr 0031](adr/0031-adr-code-mismatches.md)）：`overridableCommands` に `code` が入っている。LSP の補完にプラグインのコマンドの名前が出ない。`golem inspect` のオプションの書き方が ADR と違う。ホストが `golem_dealloc` を一度も呼ばない。どちらに合わせるかを決めて直す。
- **奥付の関係者と刷**（未実装、[docs/adr 0033](adr/0033-colophon-contributors-and-printings.md)）：マニフェストの `[metadata]` が持つのは、著者（`creators`）、発行者（`publisher`）、版（`edition`）、発行の日（`date`）だけである。奥付に載せる編集者、印刷所、製本所を書く欄がない。版とは別に刷（同じ版を刷り直した回）を書く欄もなく、版と刷ごとの発行の日の履歴（「2026 年 10 月 16 日初版第 1 刷発行」の形の行）も書けない。関係者を役割とともに書けるようにし、版と刷とその日付を書けるようにして、本文から `meta` で参照できるようにする。役割の語彙、EPUB と PDF のメタデータへの写し方、組み込みの奥付を用意するかどうかは ADR で決める。
- **keep の段落の行末のエスケープした空白**（未実装、[golem-parser ADR 0012](golem-parser/adr/0012-keep-trailing-escaped-space.md)）：keep の段落の行末に書いた `\ `（エスケープした空白）は、行の末尾の空白とともに除かれているように読める（golem-parser の `trimLine`）。[docs/markup.md](markup.md) は、エスケープした空白を行の先頭では無視すると書いており、行末では残ると読めるので、仕様と食い違っている可能性がある（コードを読んだ結果で、実際の出力では確かめていない）。
- **マニュアルのライセンス**：二つのマニュアルの原稿（`.gm`）と、組んだ PDF と HTML を CC0 にする。リポジトリのほかの部分は今のとおり MIT とする。PDF に埋め込むフォントは SIL Open Font License 1.1 のままで、CC0 の対象にならないことを、マニュアルの奥付とライセンスの表示に書く。ライセンスの表示の置き場所（`manual/` と `manual-dev/` の LICENSE、奥付、README）を決める。
- **TSV の表**（未実装、[golem-eval ADR 0004](golem-eval/adr/0004-tsv-tables.md)）：`@table` は CSV（RFC 4180）のファイルからしか表を作れない（golem-eval の `Golem.Eval.File` の `csvTable`）。タブで区切った TSV のファイルからも表を作れるようにする。形式の見分け方（拡張子か、引数で明示するか）、セルの中のタブと改行の書き方、見出しの行と揃え、セルの中身をインラインの記法として読むかどうか、誤りの位置（ファイルの行と列）の報告は ADR で決める。

### 既知の不具合の修正

仕様書の「[既知の不具合](specifications.md#既知の不具合)」に載せた不具合を直す。
次の直し方は案であり、着手するときに ADR で決める。

- **ぶら下げの量**（未実装、[golem-layout ADR 0014](golem-layout/adr/0014-protrusion-amount.md)）：[golem-layout ADR 0005](golem-layout/adr/0005-microtypography.md) のとおり、行の端の字の送りに比を掛ける。既存のテストの期待値を ADR の表から計算し直し、fixture の出力の変化を決定性の検査の基準に反映する。
- **`golem inspect` の終了コード、文言、対象**（未実装、[golem-cli ADR 0007](golem-cli/adr/0007-inspect-output.md)）：ほかのコマンドと同じ diagnostics の出力を通し、誤りがあれば終了コード 1 にする。ないファイルは日本語の誤りにする。`--as ir` は引数のファイルの IR を、人が読める形で出す。二つの不具合を一つの ADR で直す。
- **LSP の古い diagnostics**（未実装、[golem-lsp ADR 0004](golem-lsp/adr/0004-stale-s1-diagnostics.md)）：ラベルを参照する箇所の集合が変わったときにも S1 を評価し直す。[golem-lsp ADR 0001](golem-lsp/adr/0001-language-server.md) の再評価の規則を改める ADR が要る。

## v0.1.0-rc4

- **総ルビのプラグイン**：本文のすべての漢字にルビを振るプラグインを作る。読みの決め方、配布の形、Golem の本体に要る変更は ADR で決める。
- **初出の語にルビを振るプラグイン**：指定した語に、章ごとの最初の出現でだけルビを振るプラグインを作る。語と読みの指定の仕方、章の境の判定、配布の形は ADR で決める。
- **diagnostic の info**：diagnostic の重大度に、notice より下の info を加える。info は `--verbose` を付けたときにだけ出力し、ふだんの出力と `golem check` の結果、終了コードには影響しない。何を info にするか、`--verbose` を持つコマンド、LSP での扱い（Information と Hint のどちらに写すか）、JSON の出力、notice の抑制の設定（[golem-syntax ADR 0002](golem-syntax/adr/0002-notice-severity.md)）との関係は ADR で決める。開発者向けのマニュアルの「Golem に info はない」という説明も、このとき改める。
- **注の印の文字スタイル**：注の印に文字スタイル（`[notes]` の `mark-style`）を当てられるようにする。印の大きさと書式は `mark-size` と `mark-format` で指定できる（[golem-driver ADR 0025](golem-driver/adr/0025-note-mark-size-and-format.md)）。
- **注の印の数字の表記**：注の印の番号を、算用数字のほかに、漢数字や記号の連なり（JLReq の 4.2.2 が挙げる形）で組めるようにする。今の `mark-format` は算用数字の番号だけを置き換える（[golem-driver ADR 0025](golem-driver/adr/0025-note-mark-size-and-format.md)）。

### PDF

- **奥付のコミットの行**：コミットしていない変更がある状態でマニュアルを組むと、奥付のコミットの行が版面の右にはみ出す（[docs/adr/0024](adr/0024-manual-audiences-and-policy.md)）。
- **書体にない字**：`golem build` は、書体にグリフがない字を誤りにせずに組み、PDF に .notdef の箱を描くか、何も描かない。`golem preflight` だけが G0902 で報告する。代わりのフォントで補う仕組みは、v2 の「フォントのフォールバック」で扱う。
- **明示したハイフンの前の行**：原稿に書いたハイフンで終わる行が、極端に間延びする（fixture の The Elements of Style の目次と本文）。
- **韻文の後の空き**：韻文の段落と、その直後の本文の段落とのあいだに空きがない（fixture の The Hunting of the Snark）。
- **連の分割**：韻文の連が、ページの境で 2 行ずつに分かれる（fixture の The Hunting of the Snark）。
- **脚注の多い本の組版の時間**：脚注を 14 件持つ Nightmare Abbey の fixture だけ、PDF の組版に 17 秒から 20 秒かかる。ほかの九冊は 1 秒から 6 秒である。
- **PDF のリンク**：原稿に外部の URL へのリンクを書く記法がなく、PDF にリンクの注釈を書かない。相互参照のリンクとしおりは v2 の「PDF のしおりとリンク」で扱うが、外部の URL の記法はどの一覧にもなかった。
- **タグ付き PDF と PDF/A**：PDF に構造のタグ（`/StructTreeRoot`）を書かず、PDF/UA と PDF/A に対応しない。

### 記法と設定

- **`@table` の位置引数のパス**：`@table` はファイルのパスを `src=` だけで受け付ける。`@listing` は位置引数を正とし `src=` を廃止予定にした（[golem-syntax ADR 0002](golem-syntax/adr/0002-notice-severity.md)）ので、`@table` でもパスを最初の引数に書けるようにするかを検討する。記法の追加が要るので ADR で決める。
- **`*[式]` の展開とプラグインへの引数**：パーサーは `*[式]` を読むが、評価はそれを展開しない。プラグインのコマンドに渡すキーワード引数は、キーを落として `[0, value]` で送っている。展開したキーがほかのキーワード引数と重なれば G0277 とする（[golem-parser ADR 0013](golem-parser/adr/0013-splat-after-keyword-arguments.md)）。
- **出力インテントの条件**：PDF/X-4 の出力インテントは `[color] intent` があるときにだけ書くが、仕様書にこの条件が書かれていない。
- **原稿の中の言語の切り替え**：本の言語は manifest の `language` だけで決まり、原稿の一部の言語を指定する記法がない。原稿の一部の言語を指定する記法を加え、引用符と和欧の扱いを、その部分の言語で切り替えられるようにする。その部分の言語で分綴することは、v1.0.0 の「本の中の別の言語の分綴」で扱う。
- **見出しの 4 階層め以降**：意味論の IR の見出しは 3 階層までで、4 階層め以降の見出しを書けない。

### 既知の不具合の修正

仕様書の「[既知の不具合](specifications.md#既知の不具合)」に載せた不具合を直す。
次の直し方は案であり、原因や仕様を確かめてから、着手するときに ADR で決める。
ひとまず v0.1.0-rc4 に置く。

- **三点リーダーの後の句点の行頭禁則**：`……。` を含む最小の例で再現させて原因を調べ、回帰のテストを足してから直す。分離禁止文字と句点の間の改行の位置か、カーニングを止める処理と禁則の判定の順が疑わしい。
- **結合文字**：HarfBuzz のクラスタの単位で箱を作り、結合文字を前の字と一つの箱にする。文字のクラスはクラスタの先頭の字で決める。golem-driver の「合字のテキスト層」の ADR の草稿と同じくクラスタの単位で扱う。
- **IR の大きな整数**：CDDL を実装に合わせ、式の整数に bignum を許す。プラグインの ABI のバージョンを上げるかを決める。
- **浮動小数点数の桁あふれ**：負の整数の累乗を有理数のまま計算してから小数に直し、整数と小数の比較を正確に行う。[golem-eval ADR 0001](golem-eval/adr/0001-expression-language-and-numerics.md) を改める ADR で定める。

### LaTeX との差を埋める項目

数式を除いて LaTeX との差を埋めるための項目である（[2026-10-17 の調査](audits/2026-10-17-latex-gap-for-v1.md)）。
どれも着手するときに ADR を作成する。

- **段落の行揃え**：段落スタイルに行揃え（左、中央、右、均等配置と最終行の揃え）の欄を加える。縦組みでは天付き、中央、地付きと読む。今は両端揃えしかなく、扉、献辞、署名、奥付を組めない。値は InDesign の行揃えに合わせる。ノド側と小口側の揃えを作るかは ADR で決める。v2 の「段落スタイルの拡張」の行揃えを先に取り出す。
- **段落の前後のアキ**：段落スタイルに、段落の前と後の空きの欄を加える。単位は `space-between` と同じく行の数とし、行の格子を崩さない。段の先頭で段落の前の空きを捨てるか（InDesign は捨てる）は ADR で決める。v2 の「段落スタイルの拡張」の段落の前後の空きを先に取り出す。
- **行の終わりの側の字下げ**：段落スタイルに、行の終わりの側の字下げの欄を加え、引用を両側から字下げして組めるようにする。行揃えと段落の前後のアキと同じ ADR で決めてよい。v2 の「段落スタイルの拡張」の行の終わりの側の字下げを先に取り出す。
- **回り込ませない図版の幅**：回り込ませない図版の幅を `@figure` の `width` で指定できるようにする。今は行長に固定し、`width` を書いても diagnostic を出さずに無視する（golem-driver の `placeFigure`）。行の中の寄せと、行長より大きい図版の縮小も合わせて決める。v2 の「図版とキャプションの拡張」の図版の幅の指定を先に取り出す。

## v1.0.0

v1.0.0 のリリースまでに、次の項目を扱う。
v0.1.0-rc4 と v1.0.0 のどちらで扱うかは、まだ決めていない。
仕様や機能を変える項目は、着手するときに ADR を作成する。

- **本の中の別の言語の分綴**：原稿の一部の言語を指定する手段がないので、英語の本の中のフランス語の語も英語のパターンで分綴される（fixture の Nightmare Abbey の「prover-be」）。原稿の一部の言語を指定する記法は、v0.1.0-rc4 の「原稿の中の言語の切り替え」で扱う。この項目は、その記法で指定した部分を、その言語の分綴のパターンで分綴することを扱う。
- **発行の履歴の書式**：v0.1.0-rc3 の「奥付の関係者と刷」では、奥付の発行の履歴の行（`2026年10月16日　初版第1刷発行` の形）を、日本語の一つの書式に固定して組む予定である。この書式を `style.toml` で変えられるようにする（`第1版第1刷` と書く本、日付と版の順を変える本など）。日本語でない本の書式も合わせて扱う。
- **参考文献のスタイル**：雑誌や出版社ごとに決まった参考文献の書式を守れるように、参考文献のスタイルを選び、定められるようにする。TeX（BibTeX と biblatex）の文献のスタイルと同等のことができるのを目指す。v0.1.0-rc3 で欄を増やした書式（[golem-doc ADR 0005](golem-doc/adr/0005-bibliography-fields.md)）を既定のスタイルとして引き継ぐ。着手するときに ADR を作成する。
- **時間のかかる `unsafe` の FFI の呼び出し**：プラグインのコンパイル（`golem_plugin_load`）と WAT から wasm への変換（`golem_wat2wasm`）は、`modules/golem-plugin/src/Golem/Plugin.hs` で `unsafe` として呼んでいる。`unsafe` の呼び出しは、終わるまで capability を手放さないので、そのあいだ GC の同期でほかのすべての capability が待たされる。この二つを `safe` の呼び出しにする。デッドロックにはならず遅れるだけであり、出力も変わらない（2026-10-17 のテストが止まる件の調査で見つかった）。

### LaTeX との差を埋める項目

数式を除いて LaTeX との差を埋めるための項目である（[2026-10-17 の調査](audits/2026-10-17-latex-gap-for-v1.md)）。
どれも着手するときに ADR を作成する。
記法、意味論の IR、プラグインの ABI を変える項目（前付けのノンブル、表の番号、複数段落の注、索引の参照、引用の頁）は、互換を壊す変更になるので 1.0.0 の前に扱う。
v2 以降に回した事項から一部を取り出した項目は、実装を終えたときに、この項目とともに v2 の側の記述から取り出した部分を消す。

- **PDF のしおりと文書の中のリンク**：見出しから PDF のしおりを作り、相互参照、目次、索引、脚注の印を PDF のリンクにする。v0.1.0-rc4 の「PDF のリンク」で作るリンクの注釈の仕組みを使う。v2 の「PDF のしおりとリンク」の大部分を先に取り出す。
- **前付けのノンブルとページラベル**：本の部分ごとにノンブルの様式（ローマ数字など）と開始の番号を変え、PDF にページラベルを書く。InDesign のセクションの開始にあたる。目次、索引、相互参照のページ番号にも同じ書式を使う。v2 の「ページ番号と柱の拡張」の前付けのノンブルと振り直しを先に取り出す。
- **段落スタイルの分割禁止と連動**：段落スタイルに、次の段落と連動、段落を分割しない、段落の始めと終わりに残す行の数（孤立行の行数）、段落の開始位置（次の段、次のページなど）の欄を加える。InDesign の段落の分割禁止オプションにあたる。v0.1.0-rc3 の改ページの手での制御と同じ仕組みで組む。行の数の欄は、InDesign の「段落の始めと終わりの行数」にあたり、書かなければ今の規則（最初と最後の行を一つだけ残さない）のままとする。
- **表の番号とキャプション、列の幅、文字の大きさ**：表に番号とキャプションを付けて相互参照できるようにし、列の幅の指定と、表のセルへの段落スタイルの適用（本文より小さい文字の表）を加える。v2 の「表の拡張」のこれらの部分を先に取り出す。セルの結合は v2 に残す。
- **複数段落の注**：注の本文を複数の段落にできるようにする。注の本文の型をインラインからブロックに変えるので、意味論の IR とプラグインの ABI が変わる。実装を終えたら、v2 の「複数段落の注」も消す。
- **目次の項目の書式**：目次の階層ごとに段落スタイルを当て、書体、大きさ、字下げ、空きを変えられるようにする。InDesign の目次スタイルの項目のスタイルにあたる。図目次、表目次、章ごとの小目次は v2 の「目次の拡張」に残す。
- **索引の参照、ページの範囲、見出し**：索引の項目に「を見よ」「をも見よ」の参照とページの範囲を書けるようにし、索引に行の見出し（「あ」「か」など）を入れられるようにする。`[index]` の記法と IR が変わる。v2 の「索引と参考文献の拡張」のこれらの部分を先に取り出す。
- **引用の頁の指定と複数の文献**：`[cite]` に頁（引用の位置）を書けるようにし、複数の文献を一度に引けるようにする。InDesign に組み込みの引用の機能がないので、LaTeX の `\cite[p.~5]{a,b}` と biblatex を参考にする。「参考文献のスタイル」より先に、引用が持つ値を決める。
- **下線と打ち消し線**：文字スタイルに下線と打ち消し線の欄を加え、線の太さ、種類、位置、色を罫線の指定で書けるようにする。縦組みでの線の側（傍線）は、InDesign の振る舞いを確かめてから決める。v2 の「和文組版の拡張」の傍線を含む。
- **上付きと下付き**：組み込みの文字スタイル `superscript` と `subscript` を加える。書体の上付きと下付きの機能があればそれを使い、なければ大きさと位置で近似する（InDesign と同じ）。HTML と EPUB では `sup` と `sub` にする。v2 の「和文組版の拡張」の添え字を含む。
- **文字スタイルの OpenType の機能**：文字スタイルに `features` の欄を加え、スモールキャップ、分数、数字の形式、スタイルセットなどを文字の範囲に当てられるようにする。書体にない機能の扱いと、合成のスモールキャップを作るかは ADR で決める。
- **段落の背景と囲み罫**：今は段落スタイル `code` にだけ書ける背景と枠を、ほかの段落スタイルにも書けるようにする。コラムや注意書きの囲みに使う。v0.1.0-rc3 の段落スタイルの罫線と罫線の色と種類を枠に使う。続く段落を一つの囲みにまとめることと、ページをまたぐ分割は ADR で決める。
- **任意ハイフン、分綴の例外、分離禁止**：ソフトハイフン（U+00AD）を分割してよい位置として扱い、本ごとの分綴の例外の一覧と、改行しない範囲を指定する文字スタイルを加える。「本の中の別の言語の分綴」と同じ時期に扱う。v2 の「行分割の拡張」のソフトハイフンと分割の位置の指定を先に取り出す。

## v2 以降に回した事項

v1 の範囲から外し、v2 以降に送ると決めた事項である。
それぞれの理由は、仕様書の対応する節と ADR に記載している。

- **数式の組版**：EPUB と HTML は MathML で出せるが、PDF には数式の組版エンジンが必要であり、それだけで独立した大きな仕事になる。当面は、数式を画像にして図版として入れる。
  - 数式と図の記法は、TeX の数式の記法と TikZ を採る。数式の組版のために新しい記法を覚えようとする使い手は、今ではほとんどいないはずだからである。どこまでを受け付けるか（TeX の数式の範囲、TikZ のライブラリの範囲）は ADR で決める。
  - 数式の組版のサンプルとして、短い本を三冊用意し、fixture とマニュアルの例に使う。内容は凝らなくてよい。
    - 「論理、集合と写像」のような本：命題と論理式、集合の記法、写像の定義と図式で、数式の組版の基本を確かめる。
    - 「圏論入門」のような本：可換図式で、TikZ が矢印の図を描けることを確かめる。
    - 「楕円曲線関数入門」のような本：曲線のグラフや図で、TikZ が座標の図を描けることを確かめる。
- **EPUB の決定性**：zip のエントリの時刻と順序の固定（[ADR docs/adr/0002](adr/0002-determinism.md)、[golem-epub ADR 0001](golem-epub/adr/0001-epub-packaging.md)）。
- **式の超越関数**：三角関数、指数関数、対数関数と、浮動小数点数の指数による累乗（[golem-eval ADR 0001](golem-eval/adr/0001-expression-language-and-numerics.md)）。
- **改ページの大域の最適化**：見開きの単位の最適化と、段組みの段の高さの調整を含む（[golem-layout ADR 0003](golem-layout/adr/0003-pagination-and-s2.md)）。
- **フレーム**：レベル 2 と 3 のフレーム。型は定義してあり、v1 では値を書くとエラーになる（[golem-layout-spec ADR 0001](golem-layout-spec/adr/0001-page-geometry.md)、[golem-project ADR 0002](golem-project/adr/0002-style-toml.md)）。
- **段組みの拡張**：v1 で実装する段組み（仕様書の [「style.toml」の節](specifications.md#styletoml) の段組み、[docs/adr/0018](adr/0018-multi-column-layout.md)）を超える部分。段抜きの見出し、索引のほかで一冊の中で段数を切り替えること、段組みの版面での回り込みと段をまたぐ除外領域を含む（[golem-driver ADR 0003](golem-driver/adr/0003-pdf-heading-styles.md)、[golem-driver ADR 0005](golem-driver/adr/0005-pdf-wrapped-figures.md)、[golem-driver ADR 0007](golem-driver/adr/0007-pdf-index-and-bibliography.md)、[golem-layout ADR 0004](golem-layout/adr/0004-wrapped-figures.md)）。段の高さの調整は「改ページの大域の最適化」に、段組みの版面での傍注欄は「傍注の拡張」に含める。索引の段組みは [docs/adr/0025](adr/0025-index-columns.md) で v1 に入れた。
- **図版とキャプションの拡張**：版面より大きい図版を縮小する、複数のページに分ける、見開きに置くといった扱い（v1 は空のページにそのまま置く）、回り込ませない図版の幅の指定、ページの端や塗り足しの領域まで伸ばす図版、矩形以外の形の回り込み、キャプションの位置（画像の上、横）と揃え、画像とキャプションのあいだの空き、図番号とキャプションの本文で書体や大きさを変えること（[golem-driver ADR 0010](golem-driver/adr/0010-caption-style.md)、[golem-driver ADR 0005](golem-driver/adr/0005-pdf-wrapped-figures.md)、[golem-pdf ADR 0004](golem-pdf/adr/0004-crop-marks-and-bleed.md)、[golem-layout ADR 0004](golem-layout/adr/0004-wrapped-figures.md)）。
- **複数段落の注**：v1 の注は一つの段落に限る。
- **目次の拡張**：章ごとの小目次（v1 の `@toc` は文書に一つだけ）、`[toc]` の `font` と `size` による項目の書体と大きさ、階層ごとの書体の切り替え、字下げ、空き、リーダーの字の設定、折り返した題のぶら下げ、図目次と表目次（[golem-driver ADR 0009](golem-driver/adr/0009-pdf-toc-page-numbers.md)）。
- **ページ番号と柱の拡張**：ノンブルの書式を目次と索引のページ番号に使うこと、前付けのローマ数字のノンブルと、前付けと本文でのページ番号の振り直し、EPUB の `page-list`、柱とノンブルと目次の項目を見出しの書体で組むこと、柱、ノンブル、罫線、図版の色（[golem-driver ADR 0003](golem-driver/adr/0003-pdf-heading-styles.md)、[golem-driver ADR 0004](golem-driver/adr/0004-pdf-emphasis-and-character-styles.md)、[golem-driver ADR 0009](golem-driver/adr/0009-pdf-toc-page-numbers.md)、[golem-epub ADR 0001](golem-epub/adr/0001-epub-packaging.md)）。
- **縦組みの傍注**：v1 の傍注は横組みに限る（[golem-layout ADR 0006](golem-layout/adr/0006-sidenotes.md)）。
- **索引と参考文献の拡張**：索引の三段以上の階層と「〜を見よ」のような項目間の参照（v1 は二段まで）、索引の見出し（「あ」「か」のような行の区切り）、ページ番号の範囲の圧縮、副項目の折り返した行の字下げ、縦組みの本の索引を横組みにして巻末から始めること、参考文献の書式の選択（著者名の順の一覧を含む）と書誌のぶら下げ字下げ（[golem-doc ADR 0002](golem-doc/adr/0002-document-assembly.md)、[golem-driver ADR 0007](golem-driver/adr/0007-pdf-index-and-bibliography.md)）。
- **`style.toml` の分割**：ほかのファイルを取り込む機能（[golem-project ADR 0002](golem-project/adr/0002-style-toml.md)）。
- **`@style-def` の複数行の記法**：一つのスタイルの定義を、複数の行に分けて書けるようにする。v1 では、一つのスタイルは一行の `@style-def` で定義し、同じ名前を二つの `@style-def` に分けて書くことはできない（[docs/adr/0014](adr/0014-in-file-settings.md)）。欄の多いスタイルや正規表現スタイルでは一行が長くなる。行の分け方（続きの行の字下げ、本体を持つブロックコマンドにするか）は ADR で決める。
- **段落スタイルの拡張**：行送り、段落の前後の空き、行揃え、次のスタイル、ドロップキャップと字取り、先頭文字スタイル、`@style` の引数による段落ごとの上書き、行の終わりの側の字下げ、段落の先頭の始め括弧類の字下げの調整（JLReq）、見出し、リスト、表などへの段落スタイルの適用（[docs/adr/0005](adr/0005-character-and-paragraph-styles.md)、[docs/adr/0006](adr/0006-paragraph-indent.md)）。
- **Web 経路のスタイル**：HTML と EPUB で、見出しの `font` と `size`、文字スタイルの `size`、`caption` と `sidenote` 以外の段落スタイルの `size` を使うこと、Web 経路のフォントのサブセット化（[docs/adr/0005](adr/0005-character-and-paragraph-styles.md)、[golem-driver ADR 0010](golem-driver/adr/0010-caption-style.md)、[golem-html ADR 0001](golem-html/adr/0001-xhtml-serializer.md)）。
- **韻文の拡張**：行番号（5 行ごとの番号など）、連をページで分けない指定（[docs/adr/0003](adr/0003-verse-line-breaks.md)）。
- **ルビの拡張**：熟語の全体の読みが長い熟語ルビをグループルビとして配置し直すこと、片側だけのかけ、約物へのかけ、行頭と行末で親文字を行の端にそろえる配置、ルビの文字の大きさとルビを置く側の設定、ルビごとに配置を指定する記法、両側ルビ、ルビの中の圏点（[golem-layout ADR 0009](golem-layout/adr/0009-ruby-placement.md)）。
- **和文組版の拡張**：割注、傍線、添え字、縦組みの中の欧文を回転せずに一字ずつ組む方式、字送りを文字の大きさと異なる値にした（字間を詰めた）版面（[golem-layout ADR 0002](golem-layout/adr/0002-japanese-composition.md)、[golem-layout-spec ADR 0001](golem-layout-spec/adr/0001-page-geometry.md)）。
- **行分割の拡張**：英語以外の欧文のハイフネーションのパターン、ソフトハイフン（U+00AD）と原稿で分割の位置を指定する記法、パターンによるハイフネーションを含む TeX との参照テスト（[golem-layout ADR 0001](golem-layout/adr/0001-knuth-plass-line-breaking.md)、[golem-layout ADR 0007](golem-layout/adr/0007-knuth-plass-reference-test.md)、[golem-layout ADR 0008](golem-layout/adr/0008-explicit-hyphens.md)）。
- **特色（スポットカラー）**：Separation と DeviceN の色空間。今の Golem はプロセスカラーだけを扱う（[golem-pdf ADR 0002](golem-pdf/adr/0002-pdf-x-4.md)）。
- **PDF のしおりとリンク**：アウトライン、文書の中のリンク、注釈（[golem-pdf ADR 0001](golem-pdf/adr/0001-deterministic-pdf-writer.md)）。
- **プラグインの配布機構**：レジストリとバージョンの解決、配布されたバイナリがどのソースから作られたかの検証、キャッシュの削除と整理のコマンド（[golem-plugin ADR 0002](golem-plugin/adr/0002-distribution-and-lock.md)）。
- **配布の拡張**：macOS の実行ファイルの署名（Developer ID）と公証、Homebrew の tap とインストール用のスクリプト、再現可能なビルド、`-split-sections` による実行ファイルの縮小（[docs/adr/0004](adr/0004-binary-distribution-and-release.md)）。
- **ビルドと LSP の速度**：インクリメンタルなビルドと結果のキャッシュ、ファイルの変更の監視、ページへの配置の並列化、LSP の差分の同期とインクリメンタルな再解析、コンパイルでの回復しない解析、プラグインの初期化済みのメモリの複製。いずれも速度が問題になってから ADR で検討する（[golem-driver ADR 0001](golem-driver/adr/0001-build-pipeline.md)、[golem-driver ADR 0002](golem-driver/adr/0002-pdf-pipeline.md)、[golem-lsp ADR 0001](golem-lsp/adr/0001-language-server.md)、[golem-parser ADR 0002](golem-parser/adr/0002-parser-on-peg-hs.md)、[golem-plugin ADR 0001](golem-plugin/adr/0001-wasm-host-and-abi.md)）。
- **見出しの行取りの中の位置**：見出しを行取りの領域の中央のほかに、前寄せや後ろ寄せで置く設定。行取りの行数は `[headings.<階層>]` の `lines` で指定できるが（[golem-driver ADR 0032](golem-driver/adr/0032-default-heading-styles.md)）、見出しはいつも領域の中央に置く（[golem-driver ADR 0003](golem-driver/adr/0003-pdf-heading-styles.md)）。
- **可変フォント**：可変フォントの軸（太さ、幅など）と名前付きのインスタンスの指定。v1 は可変フォントを既定のインスタンスとして扱う（[golem-font ADR 0001](golem-font/adr/0001-shaping-and-metrics.md)、[golem-driver ADR 0004](golem-driver/adr/0004-pdf-emphasis-and-character-styles.md)）。
- **傍注の拡張**：段組みの版面での傍注欄、収まらない傍注を脚注に回すことと傍注のために本文の行を次のページに送ること、脚注の本文とキャプションの中の傍注の配置（[golem-driver ADR 0006](golem-driver/adr/0006-pdf-sidenotes.md)）。
- **表の拡張**：罫線の色と種類（縦の罫、本体の行のあいだの罫を含む）、表のための `style.toml` の設定（文字の大きさ、罫線の太さ、列の間隔、表の寄せ）、本文より小さい文字の表、列の幅の指定、セルの結合とセルの中のブロック、縦組みの本の中の横組みの表、表の行の途中での改ページ、表の番号とキャプション、表の続きを示す文言（[golem-driver ADR 0008](golem-driver/adr/0008-pdf-tables.md)）。
- **正規表現のエンジンを Oniguruma に基づくものにすること**：正規表現スタイルのエンジンを、Oniguruma を土台にしたものに置き換える。InDesign の正規表現の方言は、Oniguruma を改造して受け付けるようにする。v1 の正規表現スタイルのエンジンと方言は [docs/adr/0015](adr/0015-regex-styles.md) で決め、再実装した照合器（golem-regex）を使う。置き換えたときの方言の範囲と、v1 の方言で書いた設定との互換は、置き換えの ADR で決める。
- **オプティカルカーニング**：グリフの輪郭から二字の間の空きを決めるカーニング。InDesign のオプティカルは欧文のグリフ向けだが、和文でも仮名の字面を詰めて遊ぶ組み方に使うことがあるので、和文にも効く方式とする。InDesign はアルゴリズムを公開していないので、InDesign と同じ値にはしない。方式は ADR で決める。v1 では `kerning = "optical"` をエラー（G0321）とする（[docs/adr/0020](adr/0020-indesign-character-features.md)）。
- **文字の変形と詰め**：InDesign の文字パネルの水平比率と垂直比率、文字回転、文字ツメ、文字前と文字後のアキ量、二字の間に値を指定する手動のカーニング。水平比率と垂直比率は、縦組みでの比率の意味を資料で確かめられず、HTML と EPUB で字形を伸縮する CSS がない。長体と平体は、幅の異なる書体を役割に指定して代える（[docs/adr/0020](adr/0020-indesign-character-features.md)）。
- **面付け**：組んだページを、印刷の刷版の大きさの紙に、折りと製本の順に並べた PDF を出す。折丁（一枚の紙を折って作る 8 ページ、16 ページなどのまとまり）の大きさ、中綴じと無線綴じ、フォリオ（ページの上下や左右の並べ方）の選択、面付けの PDF に付けるトンボと折りの印を含む。今の Golem は、一ページを一枚の PDF のページとして出し、面付けは印刷所の側で行う前提である。
- **縦組みの本の中の横組みの部分**：縦組みの本（右開き）に、横組みの原稿（付録、索引、欧文の論文など）を混ぜて組むこと。横組みの部分は左開きで読むので、本の後ろの側から始め、ページを逆の順に並べ、ノンブルも後ろから数える。横組みの部分の判型と版面、ノンブルの数え方（本の通しにするか、横組みの部分で振り直すか）、目次と相互参照のページ番号の表し方、PDF のページの並べ方を ADR で決める。「索引と参考文献の拡張」の「縦組みの本の索引を横組みにして巻末から始めること」は、この一部である。
- **漢文の訓点**：漢文に返り点（レ点、一二点、上下点など）、送り仮名、句読点を付けて組む機能。縦組みでは、返り点を漢字の左下に、送り仮名を右下に小さく置く。記法、意味論 IR、各媒体での表現は、JLReq の漢文の扱いを参照して ADR で決める。
- **二色刷り**：二つの版で刷る本の出力。今の Golem は扱っていない。色と版の指定の仕方は ADR で決める。
- **文字の斜体の角度（skew）**：字形を傾ける変形の角度を設定できるようにする。雑誌のような組版に要るためである。今の合成の斜体（`synthetic-italic`）は傾きが 1/5 に固定である。傾きを変える設定は [golem-driver ADR 0004](golem-driver/adr/0004-pdf-emphasis-and-character-styles.md) と [golem-driver ADR 0012](golem-driver/adr/0012-synthetic-bold-weight.md) で作らないと決めていたので、決め直す ADR が要る。
- **フォントにも Unicode にもない字形**：フォントにも Unicode にもそのままの形では収録されていない字を組む扱い。例として、笙野頼子『水晶内制度』の「原」の字の扱いがある。原稿での書き方と、各出力での表し方を ADR で決める。
- **JAN コード**：奥付やカバーに置く JAN（EAN-13）のバーコードの扱い。生成と配置の仕方は ADR で決める。
- **絵文字のレンダリング**：カラーの絵文字のフォント（COLR/CPAL、sbix、CBDT、OpenType の SVG）のグリフ、ZWJ でつないだ絵文字の並び、異体字セレクタによる絵文字の表示と文字の表示の切り替えを、PDF と HTML で組めるようにする。各形式の描き方、PDF/X-4 との関係、HTML でフォントに任せる範囲は ADR で決める。
- **フォントのフォールバック**：役割のフォントにグリフがない字を、`style.toml` に役割ごとに宣言した代わりのフォントの列から順に探して組む。代わりのフォントの選び方は、環境によらず同じ結果になるように決める。`golem preflight` の G0902 との関係（代わりのフォントで組んだ字を報告するか）を ADR で決める。グリフがない字を `golem build` が誤りにしないことは v0.1.0-rc4 の「書体にない字」で扱い、この項目はその後に代わりのフォントで補う仕組みを扱う。カラーの絵文字のフォントを代わりのフォントに使う場合は、「絵文字のレンダリング」と合わせて決める。
- **diagnostics の英語化**：diagnostics、ヒント、使い方の表示を英語でも出す。既定では実行時のロケールを読んで言語を選び、オプション（たとえば `--lang en`）と設定で指定できるようにする。出力するファイル（PDF、HTML、EPUB、テキスト）はロケールによらないという [docs/adr/0002](adr/0002-determinism.md) の規則は変えず、言語が変わるのは端末に出す文言だけとする。JSON の diagnostic のコードと位置は言語によらない。着手するときに ADR を作成する。
- **見た目の回帰テスト**：Golem の PDF と HTML の出力を画像にして、前のコミットの出力と比べるテスト。今の検査は同じコミットのバイト列の一致だけを見るので、組版の見た目が崩れる変更でも通る。画像にするツールとそのバージョンの固定、比べ方、参照の画像の置き場所、CI の費用を ADR で決める。仕様書の [「Golem が強いるワークフロー」の節](specifications.md#golem-が強いるワークフロー) が外部のツールに任せるとした、利用者のための差分の仕組みとは別のもので、Golem 自身の開発のためのテストである。検討の材料は、開発者向けのマニュアルの「決定性を守る」の章にまとめている。
- **章末の注の一覧の改ページと見出し**：v1 の章末の注の一覧は、前で改ページせず、見出しの文言は「注」（日本語以外は「Notes」）に固定する。一覧の前で改ページする設定と、見出しの文言を変える設定を加える。
- **孤立行の規則の見直し**：段落の最初と最後の行をページの境に一つだけ残さない規則（[golem-layout ADR 0003](golem-layout/adr/0003-pagination-and-s2.md)）は、ページの末尾に 1 行か 2 行の空きを残す。出版された本でもあまり気にされていないので今はこのままとし、必要になったら和文の本で緩めるかを検討する。利用者が行の数を指定する欄は v1.0.0 の「段落スタイルの分割禁止と連動」に移したので、この項目には、既定の規則を和文の本で緩めるかどうかだけが残る。
- **条件テキスト**：一つの原稿から、媒体（PDF、EPUB、HTML）や版（紙の版と電子版、教師用と生徒用など）ごとに本文の一部を出し分けること。InDesign の条件テキストと条件セットにあたる。どの単位で条件を書くか、媒体ごとの出し分けを媒体契約（仕様書の [「設計原則」の節](specifications.md#設計原則)）の中でどう認めるかを ADR で決める（[2026-10-17 の調査](audits/2026-10-17-latex-gap-for-v1.md)）。
- **差し込み**：外部のデータ（CSV など）の値を、組版に差し込んで組むこと。InDesign のデータ結合にあたる。名簿、カタログ、一つの型から多数の文書を組む用途に使う。データの形式、差し込む記法、一件ごとに文書を分けるか一冊に続けて組むかを ADR で決める。

## v3 以降に回した事項

- **GUI**：原稿とスタイルを編集し、組版の結果を確かめる画面。v2 までの Golem は CLI と CI で完結させる。ページ画像の差分を取る仕組みを自前で持つ場合も、GUI より後に扱う。
- **GUI の作り方**：GUI は Tauri で作り、すべての描画を canvas に任せる。描く内容は Golem が決め、canvas はそれを描くだけにする（グリフのアウトラインを座標と一緒に受け取ってパスとして描くか、Golem がページを画像にしたものを並べる）。ブラウザの文字の描画（`fillText`）には頼らないので、プレビューは PDF と同じ見た目になり、OS ごとの WebView の違いは表示の速さにしか効かない。Golem の本体は今のまま CLI と LSP で動かし、GUI はそれと通信する別のプロセスにする。原稿の入力欄には WebView の入力の仕組みを使い、日本語の IME と縦書きの入力を扱う。Linux の WebKitGTK の canvas の性能が足りなければ、そのときに代わりを検討する。着手するときに ADR を作成する。
- **HarfBuzz と FreeType の置き換え**：シェイピングとフォントの読み込みを Golem 自身の実装に置き換える。v2 までは、バージョンを固定した HarfBuzz と FreeType を同梱して使う（[golem-font ADR 0001](golem-font/adr/0001-shaping-and-metrics.md)）。

## 手で確かめる項目

実装は終わり、自動のテストも通っているが、ADR が求める手作業の確かめがまだ残っている項目をここにまとめる。
確かめたら、結果を実装のプルリクエストか `docs/audits/` の記録に書き、この一覧から消す。

- **LSP の位置の扱い**：UTF-8 の位置の交渉と、行の長さを超える列の丸めを、実際のエディタ（Neovim）で確かめていない（[golem-lsp ADR 0002](golem-lsp/adr/0002-utf8-position-encoding.md)、[golem-lsp ADR 0003](golem-lsp/adr/0003-position-handling.md)）。
- **CIDSystemInfo と異体字**：Adobe-Japan1 の ROS を持つフォント（小塚明朝 Pr6N など）で組んだ PDF を Acrobat のプリフライトにかけ、`CIDSystemInfo` がフォントの ROS になっていること、IVS の異体字が出ることを確かめていない。リポジトリにそうしたフォントがないためである（[golem-pdf ADR 0006](golem-pdf/adr/0006-cid-system-info.md)）。
- **プリフライトと商用のプリフライトの差**：Golem の G0914 が出なかった PDF を Acrobat のプリフライト（PDF/X-4 の適合の検査）にかけ、Acrobat が PDF/X-4 の誤りを報告するかを確かめていない。差があれば `Golem.Pdf.X4.verify` に足す要件を ADR にし、結果は `docs/audits/` に残す。同じ条件の文書を InDesign のプリフライトにかけ、同じ種類の問題が両方で出るかも確かめていない（[golem-cli ADR 0006](golem-cli/adr/0006-preflight.md)）。
- **トンボのレジストレーションの色**：トンボを付けた PDF を Acrobat の出力プレビューとプリフライトで開き、トンボが全版に出ること、本文に特色が混ざらないこと、InDesign の書き出しと同じ形であることを確かめていない（[golem-pdf ADR 0007](golem-pdf/adr/0007-registration-crop-marks.md)）。
- **縦組みのダッシュ**：縦組みの PDF を目で見ること、InDesign の縦組みとの比較、縦組みの HTML を Safari と Chrome で開いて向きが PDF と同じことの確かめが残っている（[golem-driver ADR 0015](golem-driver/adr/0015-vertical-dashes.md)）。
- **リストの字下げ**：入れ子のリストと 10 項目を超える番号付きリストを、横組みと縦組みで PDF と EPUB にして目で見ることと、決定性の検査の蟹工船とテンペストの出力が変わらないことの確かめが残っている（[golem-driver ADR 0013](golem-driver/adr/0013-list-indents.md)）。
- **段組みの脚注**：段組みの版面で、脚注がその段の下に組まれることを PDF で目で確かめていない。自動のテストでだけ確かめている（[docs/adr/0018](adr/0018-multi-column-layout.md)）。
- **LSP のお知らせ**：Neovim で、お知らせが Information として表示され、問題の一覧に載ることと、`silence-notices` に加えると保存の後に消えることを確かめていない（[golem-syntax ADR 0002](golem-syntax/adr/0002-notice-severity.md)）。
- **diagnostic の説明へのリンク**：GitHub の上で `docs/diagnostics.md#g0117` を開き、G0117 の節に移ることを確かめていない（[golem-cli ADR 0005](golem-cli/adr/0005-explain-diagnostic-codes.md)）。
- **コードブロックの見え方**：コードブロックの PDF を Acrobat の出力プレビューで開き、背景の色が DeviceCMYK の版だけに出ることと、コードの書体が埋め込まれていることを確かめていない。HTML と EPUB の `pre` と `code` の見え方も、Safari と Chrome で確かめていない（[golem-driver ADR 0017](golem-driver/adr/0017-pdf-code-blocks.md)）。
- **技術書のコードブロックの見え方**：行番号、キャプション、強調、注釈の印を付けたコードブロックを PDF と HTML で開き、技術書として読める見た目であることと、強調の網が墨の版だけに出ることを目で確かめていない。HTML で行番号と差分の印が選択とコピーに含まれないことも、Safari と Chrome で確かめていない（[golem-driver ADR 0023](golem-driver/adr/0023-code-block-book-features.md)）。
- **二冊のマニュアルの HTML と PDF**：利用者向けと開発者向けのマニュアルの HTML を、ブラウザで開いて確かめていない。PDF は、Acrobat でフォントの一覧と埋め込みを確かめていない（[docs/adr/0024](adr/0024-manual-audiences-and-policy.md)）。
- **マニュアルの中の InDesign の記述**：利用者向けのマニュアルの InDesign との対応と比較の記述（「はじめに」と付録 E）を、InDesign に詳しい人が確かめていない（[docs/adr/0024](adr/0024-manual-audiences-and-policy.md)）。
- **開発者向けのマニュアルの例**：プラグインの WebAssembly のテキスト形式（`.wat`）の例を、実際に組んで動かしていない（[docs/adr/0024](adr/0024-manual-audiences-and-policy.md)）。
- **組版の新しい機能の見え方**：次の機能の PDF を目で見て確かめていない。環境に PDF を画像にする道具がなく、実装のプルリクエストでは確かめられなかった。
  - 圏点の十の形を、横組みと縦組みで見ること。HTML を Safari と Chrome で見ることと、InDesign の圏点との比較（[golem-driver ADR 0019](golem-driver/adr/0019-pdf-kenten-shapes.md)）。
  - 隠しノンブルを、トンボを付けた PDF で Acrobat で見ること（[golem-driver ADR 0021](golem-driver/adr/0021-hidden-folios.md)）。
  - `palt` と `vpal` の約物の位置と、二倍ダッシュが一本の線に見えること（[golem-driver ADR 0020](golem-driver/adr/0020-glyph-positioning-and-dash-kerning.md)）。
  - ルビの親文字の一部を太字にしたマニュアルの見本（[golem-layout ADR 0011](golem-layout/adr/0011-ruby-base-character-styles.md)）。
  - 縦組みの注の印と、マニュアルの付録の注（[golem-driver ADR 0018](golem-driver/adr/0018-footnote-marks-and-numbers.md)）。
  - 参考文献の一件の中の空き（[golem-doc ADR 0004](golem-doc/adr/0004-bibliography-formatting.md)）。
  - 技術書のコードブロックを Acrobat の出力プレビューで開くこと（[golem-driver ADR 0023](golem-driver/adr/0023-code-block-book-features.md)）。
  - The Elements of Style の 39 ページ、縦組みの表を足した蟹工船、二冊のマニュアルの表のあるページで、罫が字面に接しないこと、空の見出しの行の罫が二重にならないこと、表の前後に一行の空きがあること（[golem-driver ADR 0031](golem-driver/adr/0031-table-spacing-and-rules.md)）。
  - 12 の線の種類と色を付けた脚注の区切り線を Acrobat の出力プレビューで開き、破線と点線の両端、点の丸さ、波線のつながり、色が DeviceCMYK の版だけに出ることを見ること。同じ太さと長さの線を InDesign で引いて並べ、多重線の比、点の間隔、和文の点線の形を比べること（[golem-driver ADR 0028](golem-driver/adr/0028-rule-colour-and-style.md)）。

## 未決事項

次の事項が決まっていない。
v1 より後のバージョンのための事項には、そのバージョンを書く。
決めたら、仕様書か ADR に書き、この一覧から消す。

- **PDF/X-4 の要件と規格の本文の照合**：[golem-pdf ADR 0002](golem-pdf/adr/0002-pdf-x-4.md) は、規格の本文を参照せずに要件を書き、本文と照合して差分があれば新しい ADR を作るとしたが、照合の結果を記した ADR はない。文書情報辞書と XMP の値を一致させる要件も、本文では確かめていない（[golem-pdf ADR 0005](golem-pdf/adr/0005-producer.md)）。v1 の PDF を PDF/X-4 として出すまでに、本文と照合するか、商用のプリフライトでの確認で代えるかが決まっていない。
- **裸の語の `*`**：`a*[x]` が `a*` と `[x]` の二つの引数として読まれるなど、`*` を含む裸の語の扱いに不整合がある（[golem-parser ADR 0007](golem-parser/adr/0007-grammar-label-safety.md)）。受理する言語をどう決め直すかが決まっていない。
- **和字の直後の欧文の句読点の前の空き**：行組版は、和字の直後の欧文の句読点（`.`、`,`、`:` など）の前にも和欧間の空き（四分）を入れる。ASCII の文字をすべて欧文に分類するためである。JLReq の 3.2.6 は和字と欧文のあいだに四分の空きを置くと定めるが、欧文の句読点が和字の直後に来る場合の扱いは確かめた範囲の本文では読み取れなかった。JLReq と JIS X 4051 の本文で確かめ、変えるなら別の ADR で扱う（[golem-doc ADR 0004](golem-doc/adr/0004-bibliography-formatting.md)）。
- **段落の罫線の間隔と行の格子**：段落スタイルの罫線（この文書の v0.1.0-rc3 の「段落スタイルの罫線」）の前後の間隔を、行の格子とどう合わせるかが決まっていない。脚注の区切り線は区切りの領域を格子の行の整数倍に切り上げるが（[golem-driver ADR 0024](golem-driver/adr/0024-rule-spec-and-footnote-separator.md)）、段落の罫線は本文の行のあいだに入るので、同じ決め方が使えるかはわからない。
- **GUI と Golem のあいだの通信の取り決め（v3）**：GUI（「GUI の作り方」）と Golem の本体のあいだで、何をどう受け渡すか。今の LSP を広げるのか、別の取り決めを作るのかが決まっていない。
- **描画の内容を渡す API（v3）**：GUI の canvas に、グリフのアウトラインを座標付きで渡すのか、ページの画像を渡すのか、その両方か。v2 の「見た目の回帰テスト」で PDF を画像にする仕組みと共有できるかも含めて決まっていない。

## 課題にしなかった事項

ADR と仕様が扱わないと決めたもので、課題として残さないものをここにまとめる。
扱う必要が出てきた場合は、新しい ADR で決め直す。

- **macOS と Windows での CI、stack によるビルド**：決定性の検査は Linux の二つのアーキテクチャで足り、依存のバージョンは cabal と freeze ファイルで固定できるので採らない（[docs/adr/0001](adr/0001-haskell-workspace-and-ci.md)）。
- **Windows と Intel の CPU の macOS の実行ファイル**：Windows では、WSL の上で Linux の静的な実行ファイルを使えば足りる。Windows でそのまま動く実行ファイルは、CI、リンク、改行の扱い、`scripts/` の検査を Windows のために保守する費用に見合わず、担当する人が現れても貢献が続く保証はないので作らない。Intel の CPU の macOS は、次の macOS のバージョンで Rosetta が使えなくなるので、対応しない。どちらも v2 の「配布の拡張」から移した（[docs/adr/0004](adr/0004-binary-distribution-and-release.md)）。
- **異なるバージョンの Golem の間での出力の一致**：Golem のバージョンは入力の一部であり、バージョンが変われば出力が変わってよいので求めない（[docs/adr/0002](adr/0002-determinism.md)）。
- **決定性に反する処理の静的な検出**：決定性の規則はレビューとテストで守ると決めたので作らない（[docs/adr/0002](adr/0002-determinism.md)）。
- **リリースの運用の自動化**：リリースの自動公開、リリースで確かめる項目の自動化、監査の記録を仕組みで変更できなくすることは、公開を人が行い、確かめは繰り返しが重くなってから自動化を考え、記録は約束とレビューで守ると決めたので扱わない（[docs/adr/0004](adr/0004-binary-distribution-and-release.md)、[docs/adr/0008](adr/0008-first-release-verification.md)、[docs/adr/0011](adr/0011-update-adr-guard-to-v0.8.0.md)）。
- **CI の高速化の候補**：大きいランナー、aarch64 の `build` の省略、HarfBuzz と FreeType の切り出しや翻訳単位の分割、GHC を含むコンテナ、古いキャッシュを消すジョブは、費用、決定性の検査、効果の見込みの理由で採らないと決めた（[docs/adr/0009](adr/0009-ci-speed.md)）。
- **スタイルの仕組みで作らないもの**：組み込みのスタイルを消すことと名前を変えること、`style.toml` の自動の書き換え、組み込みの文字スタイル `emphasis`、段落スタイルの `hang` のキー、原稿の先頭の全角の空白の除去と警告は、ADR が作らないと決め、`hang` は負の `first-line-indent` で表せるので扱わない（[docs/adr/0005](adr/0005-character-and-paragraph-styles.md)、[docs/adr/0006](adr/0006-paragraph-indent.md)）。
- **合成の太字と斜体の設定**：線の幅を変える設定、フォントや文字の大きさごとの値、太った分だけ送りを広げること、OS/2 テーブルから書体を選ぶことは、品質が要る本では太字や斜体の書体を役割で指定すればよいので作らない（[golem-driver ADR 0004](golem-driver/adr/0004-pdf-emphasis-and-character-styles.md)、[golem-driver ADR 0012](golem-driver/adr/0012-synthetic-bold-weight.md)）。傾きを変える設定は、v2 の「文字の斜体の角度（skew）」に移した。
- **lint の規則の設定と抑制、表記の規則**：規則は処理系が固定し、合意の取れない表記の規則は外部の校正ツールに任せると決めたので持たない（[golem-lint ADR 0001](golem-lint/adr/0001-lint-rules.md)、[「lint」の節](specifications.md#lint)）。
- **生の CSS**：媒体契約の外で見た目を変える抜け道になるので設けない（[golem-html ADR 0001](golem-html/adr/0001-xhtml-serializer.md)、[「style.toml」の節](specifications.md#styletoml)）。
- **fmt の表の列揃え、本文の折り返し、整形の規則の設定**：整形の結果が環境によって揺れず、書き手の改行を変えないことを優先したので作らない（[golem-fmt ADR 0001](golem-fmt/adr/0001-formatter.md)）。
- **式の拡張**：ユーザー定義の関数、条件式、繰り返し、文字列の演算子、浮動小数点数の指数表記は、書籍の原稿の計算で要る場面が少ないので、必要が明らかになるまで加えない（[golem-eval ADR 0001](golem-eval/adr/0001-expression-language-and-numerics.md)、[golem-parser ADR 0004](golem-parser/adr/0004-inline-grammar.md)）。
- **フォントの難読化と Type 3 による埋め込み**：v1 の出力に要らないので、ADR が扱わないと決めた（[golem-font ADR 0002](golem-font/adr/0002-subsetting-and-embedding.md)、[golem-html ADR 0001](golem-html/adr/0001-xhtml-serializer.md)、[golem-epub ADR 0001](golem-epub/adr/0001-epub-packaging.md)）。
- **複雑な文字体系の検証**：Golem の対象を和文と欧文に限るので、アラビア文字やインド系の文字は確かめない（[golem-font ADR 0001](golem-font/adr/0001-shaping-and-metrics.md)）。
- **固定レイアウトの EPUB**：EPUB は幾何を持たないリフローの媒体として扱うので作らない（[golem-epub ADR 0001](golem-epub/adr/0001-epub-packaging.md)、[「設計原則」の節](specifications.md#設計原則)）。
- **ICC プロファイルによる Web の色変換**：画面の色は印刷の色の近似でよいと決めたので、差が問題になるまで扱わない（[golem-html ADR 0001](golem-html/adr/0001-xhtml-serializer.md)）。
- **musl の malloc の速度**：GHC のヒープは RTS が自前で管理して影響が限られるので、問題になるまで扱わない（[docs/adr/0004](adr/0004-binary-distribution-and-release.md)）。
- **utf-32 の交渉と、`lsp` パッケージを使わない LSP の実装**：UTF-16 で常に応えられ、`lsp` への細工は一か所に閉じ込められるので採らない（[golem-lsp ADR 0002](golem-lsp/adr/0002-utf8-position-encoding.md)）。
- **diagnostics と CLI の文言の多言語化**：v1 の diagnostics と使い方の文言は日本語だけと決めたので扱わない（[golem-syntax ADR 0001](golem-syntax/adr/0001-source-spans-and-diagnostics.md)、[golem-cli ADR 0004](golem-cli/adr/0004-usage-error-exit-code.md)）。
