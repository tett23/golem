# Golem のロードマップ

Golem のどのバージョンで何を扱うかを、この文書にまとめる。
今の Golem の振る舞いは [仕様書](specifications.md) に書き、この文書には書かない。
バージョンごとの節に載る項目は、どれも今の Golem にはまだない。
ほかに、実装は終わったが手作業の確かめが残っている項目（手で確かめる項目）、決まっていない事項（未決事項）、扱わないと決めた事項（課題にしなかった事項）もここにまとめる。

どの項目も、着手するときに ADR を作成する。
採択済みの ADR があり、まだ実装していない項目には「（未実装）」と書き、その ADR へリンクする。
実装を終えたら、その項目をこの文書から消し、振る舞いを仕様書に書く。

## リリースの予定

今の計画では、次に v0.1.0-rc4 のプレリリースを出し、rc4 の直後に v1.0.0 を出す。
これは今の時点の計画であり、変わりうる。
バージョンの付け方は、仕様書の [「バージョン」の節](specifications.md#バージョン) に従う。

## v0.1.0-rc4

v0.1.0-rc4 で扱う項目は、すべて実装した。

## v1.0.0

v1.0.0 のリリースまでに、次の項目を扱う。
v0.1.0-rc4 と v1.0.0 のどちらで扱うかは、まだ決めていない。
仕様や機能を変える項目は、着手するときに ADR を作成する。
節と項目は、上から順に実装できるように並べる。
ほかの項目に依る項目は、その項目より後に置く。

### IR、ABI、レイアウトエンジンの基盤

- **IR と ABI の設計と妥当性の検査**：意味論の IR とプラグインの ABI を設計し、その設計が妥当であることを検査する。どちらも v1.0.0 の後に変えると互換を壊すので、v1.0.0 の前に扱う。検査の方法は、着手するときに ADR で決める。記法、IR、ABI を変えるほかの項目は、この項目の後に扱う。
- **余白などのブロックの命令が重なったときの AST から IR への変換**：`@blank-line`、`@need-lines`、`@page-lines`、`@page-break`、`@column-break`、`@no-page-break` など、余白や改ページを決めるブロックの命令が、ほかのブロックを挟まずに複数並んだときに、AST をどの IR に変換するかを一般の規則として定める。今は `@blank-line` どうしの足し合わせ、`@blank-line` と改ページの組み合わせ（G04010）など、組み合わせごとに個別に決めているだけで（[docs/adr/0046](adr/0046-blank-line-command.md)、[docs/adr/0030](adr/0030-manual-page-break-control.md)）、決めていない組み合わせの変換は定義されていない。段落スタイルの分割禁止と連動（[ADR 0261](adr/0261-keep-options-of-paragraph-styles.md)）は改ページの手での制御と同じ仕組みで組んだ。
- **パス**：レイアウトエンジンにパスを入れ、仕様に書く。内部の Rect もパスとして扱う。速さのために、限られた部分で Rect を使うことはかまわない。閉じたパスには、その内側に文字を置けるようにする。閉じていないパスには、パスの上に文字を置けるようにする。テキストフレームは Rect に限らず、閉じたパスとして表せるようにし、その内側に文字を置く。v1.0.0 の「ボックスモデル」は、パスが入ることを考えて決めておく。開発者のマニュアルのレイアウトエンジンの章にも書く。ADR で決める。
- **任意のテキストフレームの配置**：本文を流し込むフレーム（版面と段）のほかに、ページの任意の位置にテキストフレームを置き、その中に文字を組めるようにする。InDesign でページにテキストフレームを置くことにあたる。テキストフレームは「パス」の閉じたパスとして表し、その内側に文字を置くので、「パス」の後に扱う。フレームを置く書き方（原稿のブロックコマンドか、マスターページか、その両方か）、位置と大きさの基準と単位、本文の流れとの関係（回り込みと重なり）、フレームどうしをつないで文字を流すか、HTML と EPUB での扱い、v2 以降に回したレベル 2 と 3 のフレーム（「フレーム」）との関係を ADR で決める（2026-11-09 の tett23 の決定で v1.0.0 に置いた）。
- **評価と書き出しを分けること**：golem-lsp のライブラリは、golem-driver から評価とその結果の補助と lint だけを使い、PDF の組版を使わない。それでも、評価と書き出しが一つのモジュール `Golem.Driver` にあるので、golem-lsp は golem-driver を通して golem-typeset にも依存する。PDF の組版を golem-typeset に分けたときに、評価の部分が PDF のモジュールを使わないようにしたので、評価を別のパッケージに分けられる。`Evaluated` の型と、評価と書き出しの両方が使う補助（`docStyles`、`localStylesOf`、`runningVars` など）の境目を読み、ADR で決める（[ADR 0192](adr/0192-split-pdf-typesetting-from-golem-driver.md)）。
- **時間のかかる `unsafe` の FFI の呼び出し**：プラグインのコンパイル（`golem_plugin_load`）と WAT から wasm への変換（`golem_wat2wasm`）は、`modules/golem-plugin/src/Golem/Plugin.hs` で `unsafe` として呼んでいる。`unsafe` の呼び出しは、終わるまで capability を手放さないので、そのあいだ GC の同期でほかのすべての capability が待たされる。この二つを `safe` の呼び出しにする。デッドロックにはならず遅れるだけであり、出力も変わらない（2026-10-17 のテストが止まる件の調査で見つかった）。

### テストと CI

- **軽量な形式手法の残りの範囲**：規則を不変条件として書き、小さな入力のすべてで確かめる手法を、範囲ごとに一つの ADR と一つのプルリクエストで広げる（[docs/adr/0208](adr/0208-widen-lightweight-formal-methods.md) の 1）。次の範囲では、試作で調べた入力を回帰テストに取り込み、CI で常時調べる範囲を実行時間から決める。
  - **パーサーと `golem fmt` の往復**：文法から作る短い原稿を列挙し、`golem fmt` の往復と diagnostics の位置の不変条件で確かめる。peg-hs の文法を読んで原稿を作る部品が先に要る。
  - **位置の変換**：UTF-16 の列、`pages.json`、LSP の位置の変換を、サロゲートペアを含む短い文字列の列挙で確かめる。家族の絵文字では、ゼロ幅接合子（ZWJ）の前後の文字境界と、一つのサロゲートペアの途中を区別する。
  - **長さの換算と丸め**：golem-length と `headingBlock` の丸めを、整数の範囲の列挙で確かめる。絶対長 5 単位の 325 入力で半 sp を含む丸めの境界を、見出し 1,296 入力で必要行数と上下余白を整数の述語で確かめた。この有限列挙を回帰テストに取り込み、列挙の範囲を超える値についても形式手法で丸めの性質を検証する。検証器と証明する範囲は着手時に決める。
  - **ページ分割の残りの要素**：罫線、コード、段の切り替え、手での制御、表、回り込む図版を、改ページの列挙の要素に足す。表と回り込む図版も含め、本文の各行と図版がそれぞれ一度ずつ出力されることを確かめる（[golem-layout ADR 0025](golem-layout/adr/0025-need-lines-and-blank-lines-after-figures-sent-on.md)）。
  - **画像の実効解像度と診断の境界**：整数の ppi がしきい値を下回る場合に G09006 が出ることを調べる。実効解像度が 1 ppi の入力に対し、しきい値 0、1、2 で native CLI を各 3 回動かすと、G09006 はそれぞれ 0、0、1 件だった。同じ述語を wasm32 のプリフライトのテストでも検査する。
- **改行しない範囲の S1 を実際の書体の送りで確かめる**：[ADR 0305](adr/0305-leave-soft-hyphens-in-or-next-to-a-no-break-range-out-of-i8.md) の S1 は、つないだ箱の幅を、つないだ文字列の送りで補正する。既存の回帰テストでは、試験用に作ったカーニングを使っている。字形と送りの性質が異なる 3 書体を当面の対象として、HarfBuzz で組んだ語の送りで S1 を確かめる。どの性質をどこまで網羅するかは改めて決める。

### 記法と設定の値

- **廃止予定の書き方をエラーにすること**：1.0.0 には廃止予定の書き方を残さない（[ADR 0174](adr/0174-compatibility-promises-for-1-0.md)）。`@listing` の `src=`（G02065）と、`-` で区切った範囲（G02108）を、それぞれ ADR を作ってエラーにする。[ADR 0184](adr/0184-table-positional-path.md) が廃止予定にした `@table` の `src=`（G02129）も同じである。[ADR 0177](adr/0177-note-mark-style-and-numerals.md) が廃止予定にした、`[lists]` の `numbers` の `{{` と `}}`（G03114）と一字の見本の差し込み（G03115）、柱の書式の `{{` と `}}`（G03116）、`[notes]` の `mark-size`（G03117）も同じである。G02065 は v0.1.0-rc2 と v0.1.0-rc3 で notice を出したので、v0.1.0-rc4 からエラーにしてよい。G02108 と G02129 は v0.1.0-rc4 で初めて notice を出すので、v0.1.0-rc4 の後にエラーにする（未決事項の「`-` で区切った範囲をエラーにするリリース」）。
- **`@listing` の位置引数のパスと `src=` の両方**：`@listing` に位置引数のパスと `src=` を両方書くと、位置引数のファイルを取り込み、`src=` に G02065 の notice を出し、`src=` のパスは黙って捨てる。`@table` は同じ書き方を G02130 のエラーにする（[ADR 0184](adr/0184-table-positional-path.md)）。`@listing` ではパスを二度指定したら同じパスでもエラーにする。`src=` の出現は一つまでとする。
- **単位のない 0**：長さとアキ量の欄、`@blank-line 0` は [Golem ADR 0345](adr/0345-revise-unitless-zero-in-length-fields.md) に従って実装した。
- **長さと量の名前**：段落スタイル、文字スタイル、長さの量などに名前を付け、スタイルやほかの設定から名前で指せるようにする。今の `style.toml` で名前を付けられるのは、段落スタイル、文字スタイル、アキ量のセット、色のスウォッチ、フォントの役割、マスターページであり、長さと量には名前を付けられない。字下げ、罫線の間隔、コードの余白、段間などの寸法は、どの欄にも `"1zw"` や `"3mm"` のような値をじかに書く。本の全体で同じ量を使うには同じ値を欄ごとに書き写すことになり、量を変えるときに直し漏れが起きる。アキの量の名前（`"二分"` など）は組み込みのもので、書き手は足せない。名前を付ける値の種類（絶対の寸法と `zw`、アキの量、行の数のような整数）、宣言の置き場所と名前の書き方、名前を指せる欄（`style.toml`、`@style-def`、`preflight.toml`）、`zw` の名前をどの文字の大きさで解決するか、組み込みの名前や単位と重なったときの扱い、LSP の補完と名前の変更を ADR で決める。段落スタイルと文字スタイルはすでに名前を持つので、スタイルについては、今の名前と `based-on` で足りないことがあるかを ADR で確かめる。`manifest.toml` の `[vars]` のプロジェクト全体の変数（[docs/adr/0185](adr/0185-project-wide-variables.md)）は原稿から読む値の名前であり、この項目は組版の設定の値の名前を扱う。

### diagnostics とビルドの結果

- **原稿の分量を調べるコマンド**：`golem stats`（仮称）で、文字数、行数、ワード数、原稿用紙換算の枚数を表示する。
  文字数は式や命令の記法を除き、当面は本文の書記素クラスタ一つを一文字と数える。
  たとえば、一つの書記素クラスタをなす家族の絵文字は一文字とする。
  行数は PDF 向けのレイアウト IR を適用して組版した結果から求め、折り返した各行と、`@blank-line` などが実際に空けた行を含める。
  この計算では PDF ファイルを書き出さない。
  ワード境界、原稿用紙の一行の字数と一枚の行数、端数の扱いは着手時に ADR で決める。

- **一つのコードに一つの原因の監査**：今の diagnostic のコードのうち、異なる原因を一つにまとめているものを洗い出し、コードを分ける（仕様書の「設計原則」の「一つのコードに一つの原因」）。コードを分けると、書き手や CI がコードで引いていた扱いが変わるので、1.0.0 の前に済ませる。
- **diagnostics の判定の近似の監査**：浮動小数点などの近似で diagnostic を決めている箇所が、ほかのモジュールにないかを調べる。同じ入力からはいつも同じ diagnostic を得るという原則（仕様書の「設計原則」）に反する箇所は、仕様書の「既知の不具合」に載せ、個別の ADR で直す（[golem-eval ADR 0006](golem-eval/adr/0006-exact-power-limit-before-range.md)）。
- **`golem check` が G01012 を二度出す件**：[ADR 0188](adr/0188-headings-beyond-level-3.md) の調査で、`golem check` が同じ見出しの G01012 を二度ずつ出し、`golem build --target html` は一度ずつ出した。`golem new` で作ったプロジェクトと、golem-driver の `sample` の fixture の写しに `#######` の行を足しただけでは、どちらのコマンドも一度だけ出す。二度出る条件を調べて直す。
- **フォントにない字があるときの preflight の完走**：フォントにない字は、prod のビルドで G08100 のエラーになる（[docs/adr/0081](adr/0081-missing-glyphs-warn-in-build.md)）。`golem preflight` は prod のビルドを走らせるので、`glyph-missing` の設定によらず終了コード 1 で終わる。字が欠けていても、preflight をほかの検査まで完走させ、結果をまとめて見られるようにする。
- **PDF を書かないエラーのときの前のビルドの PDF**：prod の G08100 では、前のビルドの `build/pdf` も消す（[ADR 0081](adr/0081-missing-glyphs-warn-in-build.md)）。G08010 など、ほかの PDF を書かないエラーでは前の PDF が残り、入稿のときに古い PDF を使うおそれがある。PDF を要求して新しい PDF を書けなかった場合は、dev では前の PDF を残し、prod では安全に片付けられる前の PDF とページ情報を消す。
- **入稿しない原稿の塗り足し**：会議の資料やスライドのように、印刷所に入稿しない原稿では、塗り足しがなくても警告やエラーを出さないようにする。今は、塗り足しの検査が入稿を前提にしており、プリフライトの `print` の設定は塗り足しの不足（G09010）と断裁の危険域（G09011、G09012）を検査し、日本式のトンボは塗り足しが 0 ならエラー（G07002）にする。入稿するかどうかを原稿の側で宣言する方法（`manifest.toml` か `style.toml` の欄、またはプリフライトの設定の選び方）と、宣言したときに外す検査の範囲を ADR で決める。`golem new` の雛形に、塗り足しを書かない入稿しない原稿の雛形を足すかも、同じ ADR で決める。

### フォント、PDF、EPUB の出力

- **CFF の表を短く切ったフォント**：`CFF ` の表の長さを、ファイルに収まる範囲で縮めたフォントは、diagnostic を出さずに、切れた CFF を埋め込んだ PDF を書く（[golem-pdf ADR 0013](golem-pdf/adr/0013-renamed-cff-table-is-g08003.md) の実装で、この振る舞いをテストで固定した）。書き手の入力と違う出力を黙って作らないように、埋め込む CFF を確かめてエラーにする。どのコードで報告するかは ADR で決める。
- **可変フォント**：可変フォントの軸（太さ、幅など）と名前付きのインスタンスの指定。今は可変フォントを既定のインスタンスとして組むが、サブセットで軸を固定しないので、使わない可変のデータ（fvar、gvar、HVAR、MVAR など）も PDF に埋め込んでいる。glyf の可変フォントで軸を既定の値に固定すると、描画を変えずに PDF が 35K から 8K に縮んだ。CFF2 の輪郭のフォントは、PDF に埋め込むと読めないので、それまでは PDF の組版で G08019 として拒む（[golem-font ADR 0003](golem-font/adr/0003-reject-cff2-fonts-in-pdf.md)）。CFF2 を CFF に変換して受け付けるのは、同梱の HarfBuzz の変換でグリフが崩れたので、HarfBuzz を更新し、描画を比べる回帰テストで確かめてからにする（[golem-font ADR 0001](golem-font/adr/0001-shaping-and-metrics.md)、[golem-driver ADR 0004](golem-driver/adr/0004-pdf-emphasis-and-character-styles.md)）。
- **取り込む PDF の内容の上限とストリームのつなぎ**：取り込む PDF の `Contents` が複数のストリームのとき、つなぐ改行も内容の大きさの上限（[docs/adr/0051](adr/0051-reuse-repeated-pdf-content-streams.md)）に数える。そのため、ストリームの展開の合計が展開の上限（256 MiB）ちょうどの PDF は、内容の上限で拒まれる（[ADR 0068](adr/0068-accepting-side-of-limits.md) の実装で見つかった）。つなぎの改行を数えるかを決め、二つの上限の関係を仕様書に書く。
- **ルビの親文字の中の参照**：ルビの親文字の中の `[ref-number]` と `[ref-title]` は、タグ付き PDF の構造の木で `Reference` にならない（[docs/adr/0215](adr/0215-ref-number-and-ref-title-as-reference.md)、[docs/adr/0229](adr/0229-record-the-procedures-adr-0215-and-0217-departed-from.md)）。親文字の中の参照をどの構造の要素にするかを ADR で決める。
- **EPUB の決定性**：EPUB の出力のバイト列の一致を、仕様として保証する。今の実装は zip のエントリの時刻を 0 にし、並びも決めて書いており、CI の決定性の検査も EPUB のハッシュを比べているが、仕様書はまだ保証しないとしている（[ADR docs/adr/0002](adr/0002-determinism.md)、[golem-epub ADR 0001](golem-epub/adr/0001-epub-packaging.md)）。保証すると決め直す ADR を書く。

### 行分割と禁則

- **行の調整で空けない字間**：JLReq の 3.1 の「行の調整処理で字間を空ける処理に使用しない箇所」に従い、分割禁止の字間（分離禁止文字の連続、連数字、前置省略記号と数、数と後置省略記号）を、行の調整で空けないようにする。今は分割の候補を消すだけで、漢字等どうしの 1/10 em の伸びが残るので、空いた行では `１２３` の字のあいだも他の字のあいだと同じだけ空く（[golem-layout ADR 0049](golem-layout/adr/0049-align-the-character-classes-and-unbreakable-pairs-with-jlreq.md)）。伸びを外すには、アキ量のセットの規則に分割禁止の組を表す方法が要り、`style.toml` のアキ量のセットの書き方も変わりうる。ADR で決める。

### スタイル

- **組版の自由の原則に反する箇所**：仕様書の「設計原則」の「組版の自由」に反し、スタイルを当てる手段のない文字を直す（[ADR 0177](adr/0177-note-mark-style-and-numerals.md) の「原則に反する今の箇所」）。それぞれ、組むものの範囲と既定の見た目を決め直す必要があるので、別々の ADR で直す。網羅したとは言えず、読んだ範囲で見つけたものである。
  - **リストの印**：印を項目の段落の見た目で組み、`[lists]` に文字スタイルの欄がない。
  - **柱とノンブル**：本文の役割の書体と版面の文字の大きさで描く。
  - **隠しノンブル**：本文の役割の書体で、`[hidden-folio]` の `size` だけを変えられる。
  - **脚注と章末の注の本文**：本文の段落スタイルの見た目で組み、段落スタイルを当てる手段がない。章末の注の一覧の見出しは、第 2 階層の見出しの書体で組む。
  - **図版のキャプションと傍注の本文**：段落スタイル `caption` と `sidenote` の見た目だけを使い、字下げ、`space-between`、`line-breaks` を当てない。
  - **正規表現スタイルの届かない文字**：見出し、定義リストの用語、注の本文には正規表現スタイルを当てない。
  - **ルビの読み**：外側の書体と色で、親文字の半分の大きさで組み、文字スタイルを当てる手段がない。
  - **トラッキングの届かない文字**：縦中横の箱とルビにトラッキングを足さない。
  - **傍注の `※` の印**：印の位置の見た目のまま組み、文字スタイルを当てる手段がない。
- **柱とノンブルのスタイル**：柱とノンブルに、書体、文字の大きさ、色を、段落スタイルか文字スタイルで設定できるようにする。今はマスターページの `running-head` と `folio` で位置と内容を決められるが、書体と大きさと色は決められない。v2 以降に回した「ページ番号と柱の拡張」のうち、柱とノンブルの書体と色はこの項目で v1.0.0 に前倒しする。
- **番号と題のあいだの区切りの設定**：見出し、図版、コードブロック、表のキャプションの番号と題のあいだの区切りを、段落スタイルで決められるようにする。今は本の言語で一つに決まり、コードブロックのリスト番号も同じ規則に従う（草案の ADR で決める）。
- **見出しの行取りの中の位置**：見出しを行取りの領域の中央のほかに、前寄せや後ろ寄せで置く設定。行取りの行数は `[headings.<階層>]` の `lines` で指定できるが（[golem-driver ADR 0032](golem-driver/adr/0032-default-heading-styles.md)）、見出しはいつも領域の中央に置く（[golem-driver ADR 0003](golem-driver/adr/0003-pdf-heading-styles.md)）。
- **段落スタイルの拡張**：行送り、次のスタイル、ドロップキャップと字取り、先頭文字スタイル、`@style` の引数による段落ごとの上書き、段落の先頭の始め括弧類の字下げの調整（JLReq）、見出し、リストなどへの段落スタイルの適用（[docs/adr/0005](adr/0005-character-and-paragraph-styles.md)、[docs/adr/0006](adr/0006-paragraph-indent.md)）。
- **発行の履歴の書式**：`@printings` は、奥付の発行の履歴の行（`2026年10月16日　初版第1刷発行` の形）を、日本語の一つの書式に固定して組む（[docs/adr/0033](adr/0033-colophon-contributors-and-printings.md)）。この書式を `style.toml` で変えられるようにする（`第1版第1刷` と書く本、日付と版の順を変える本など）。日本語でない本の書式も合わせて扱う。

### ページ分割

- **`@no-page-break` で送る行の数の設定**：今は、前の段落が 3 行以下なら全体を、4 行以上なら最後の 2 行を送る（草案の ADR で決める）。送る行の数を書き手が決められるようにする。
- **ページと見開きをまたぐ泣き別れの禁止**：表、図版とキャプション、箇条書きの項目、定義リストの用語と説明のように、ひとまとまりで読ませたいものが、ページの境や見開きの境で分かれないようにする。今の改ページがそれぞれをどこで分けているかを洗い出し、分けないものと、分けるときに残す量を ADR で決める。段落の単位の設定は仕様書の「改ページ」の節の段落スタイルの欄（[ADR 0261](adr/0261-keep-options-of-paragraph-styles.md)）で、見開きの単位の最適化は v2 以降の「改ページの大域の最適化」で扱うので、この項目はそれ以外のまとまりを扱う。

### ルビと和文組版の拡張

- **約物のプロポーショナルメトリクスの逃げ道**：JLReq が空きを決める約物に `palt` と `vpal` を当てない規則（草案の ADR で決める）は、役割の `features` に書いた `palt` にも当てる。約物にも当てたい本のための逃げ道を設ける。
- **ルビの拡張**：熟語の全体の読みが長い熟語ルビをグループルビとして配置し直すこと、片側だけのかけ、約物へのかけ、行頭と行末で親文字を行の端にそろえる配置、ルビの文字の大きさとルビを置く側の設定、ルビごとに配置を指定する記法、両側ルビ、ルビの中の圏点（[golem-layout ADR 0009](golem-layout/adr/0009-ruby-placement.md)）。
- **和文組版の拡張**：割注、左の傍線（[ADR 0270](adr/0270-underline-and-strikethrough.md) は右の傍線だけを引く）、縦組みの中の欧文を回転せずに一字ずつ組む方式、字送りを文字の大きさと異なる値にした（字間を詰めた）版面（[golem-layout ADR 0002](golem-layout/adr/0002-japanese-composition.md)、[golem-layout-spec ADR 0001](golem-layout-spec/adr/0001-page-geometry.md)）。

### 本の部品の拡張

- **平字の注の印**：縦組みで注の番号に漢数字を使うとき、上下の外枠を 50% にした漢数字（平字）で組めるようにする（JLReq の 4.2.2、[ADR 0177](adr/0177-note-mark-style-and-numerals.md) の「実装しないこと」）。字形を行の方向にだけ縮める描き方は二倍ダッシュ（[ADR 0172](adr/0172-continuous-double-dashes.md)）にあるが、印の箱の長さと字の位置の決め方が変わるので、要るときに ADR で決める。
- **図版とキャプションの拡張**：複数のページに分ける、見開きに置くといった扱い、ページの端や塗り足しの領域まで伸ばす図版、矩形以外の形の回り込み、キャプションの位置（画像の上、横）と揃え、画像とキャプションのあいだの空き、図番号とキャプションの本文で書体や大きさを変えること（[golem-driver ADR 0010](golem-driver/adr/0010-caption-style.md)、[golem-driver ADR 0005](golem-driver/adr/0005-pdf-wrapped-figures.md)、[golem-pdf ADR 0004](golem-pdf/adr/0004-crop-marks-and-bleed.md)、[golem-layout ADR 0004](golem-layout/adr/0004-wrapped-figures.md)）。矩形以外の形の回り込みは「パス」の後に扱う。
- **チャネルの番号をページごとに振り直す方式**：注の番号を、ページごとに 1 から振れるようにする。今の注の番号は、章（既定）、ファイル、本の全体のどれかの範囲で、文書の組み立て（S1）で振る。ページごとに振り直す方式は、ページが決まるまで番号が決まらないので採っていない（[docs/specifications.md の「注の番号」](specifications.md#注の番号)、[golem-driver ADR 0018](golem-driver/adr/0018-footnote-marks-and-numbers.md)）。番号の字の幅が組みを変え、組みがページを変えるので、番号をレイアウトの後（S2）に決める手順と、その繰り返しが止まることを ADR で決める。
- **韻文の拡張**：行番号（5 行ごとの番号など）（[docs/adr/0003](adr/0003-verse-line-breaks.md)）。
- **参考文献のスタイル**：雑誌や出版社ごとに決まった参考文献の書式を守れるように、参考文献のスタイルを選び、定められるようにする。TeX（BibTeX と biblatex）の文献のスタイルと同等のことができるのを目指す。v0.1.0-rc3 で欄を増やした書式（[golem-doc ADR 0005](golem-doc/adr/0005-bibliography-fields.md)）を既定のスタイルとして引き継ぐ。着手するときに ADR を作成する。本文の引用の印の書式（今は番号の書式の一種類だけ）を選べるようにすること、引用の前置きと後置き、`page` のほかの位置の種類（`chapter` など）、文献ごとの頁を一つの印に書く記法（biblatex の `\cites`）、引用の印の文言（`p.` と「頁」の選び方）、著者名の順の一覧、書誌のぶら下げ字下げもこの項目で決める（[golem-doc ADR 0002](golem-doc/adr/0002-document-assembly.md)、[golem-driver ADR 0007](golem-driver/adr/0007-pdf-index-and-bibliography.md)）。意味論 IR の引用はそれらの値をすでに持ち、今は出力の前の検査で止める（[docs/adr/0266](adr/0266-citation-locators-and-multiple-keys.md)）。
- **ページ番号と柱の拡張**：EPUB の `page-list`、柱とノンブルを見出しの書体で組むこと、柱、ノンブル、罫線、図版の色（[golem-driver ADR 0003](golem-driver/adr/0003-pdf-heading-styles.md)、[golem-driver ADR 0004](golem-driver/adr/0004-pdf-emphasis-and-character-styles.md)、[golem-driver ADR 0009](golem-driver/adr/0009-pdf-toc-page-numbers.md)、[golem-epub ADR 0001](golem-epub/adr/0001-epub-packaging.md)）。

### 機能をそろえた後の確かめ

- **wasm32 で落ちることがわかっているテストを 0 にする**：毎晩の `wasm-tests.yml` は、`golem.wasm` のパッケージのテストのスイートを wasm32 で走らせ、落ちることがわかっているテストを `scripts/wasm/test-failures.tsv` に、製品の問題（product）とテストの問題（test）に分けて載せる（[docs/adr/0293](adr/0293-run-the-test-suites-of-the-packages-of-golem-wasm-on-wasm32-every-night.md)）。一覧が空になるまで、一つずつ別のプルリクエストで直す。
- **より複雑な組版の fixture**：v0.1.0-rc4 で作る二冊の fixture（縦組みの一段の本と、横組みの二段の本）より複雑な組版の例を作り、fixture に入れる。二冊が組み合わせていない機能、たとえば縦組みの本文の段組みや、章ごとの書字方向と段数の切り替えのように後から足す機能を組み合わせ、機能のあいだの相互作用を、出力のゴールデン、決定性の検査、見た目の回帰テストで固定する。どの組み合わせを足すかと、fixture の数と大きさは、着手するときに ADR で決める。
- **PDF/X-4 の未照合事項**：印刷領域のリンク注釈は [ADR 0350](adr/0350-omit-page-link-annotations-from-pdf-x-4.md) に従って省く。v1.0.0 の前に、しおり、URI アクション一般、外観ストリームの条件、[golem-pdf ADR 0002](golem-pdf/adr/0002-pdf-x-4.md) の要件一覧について、公開資料と生成物で確定できていない点をメンテナーが照合し、監査記録に残す（[ADR 0226](adr/0226-move-the-iso-15930-7-check-to-before-v1.md)）。
- **Adobe の製品で確かめる見た目**：Adobe の製品を使う手の確かめは、費用がかかるので、v1.0.0 のリリースのときにメンテナーがまとめて行う（[docs/adr/0233](adr/0233-add-the-specimens-of-the-visual-checks-to-the-visual-regression-test.md) の「決めたことの記録」）。見本は、見た目の回帰テストの入力の `specimens-horizontal` と `specimens-vertical` を使える。
  - 縦組みのダッシュを、InDesign の縦組みと比べること（[golem-driver ADR 0015](golem-driver/adr/0015-vertical-dashes.md)）。
  - 圏点の十の形を、InDesign の圏点と比べること（[golem-driver ADR 0019](golem-driver/adr/0019-pdf-kenten-shapes.md)）。
  - Illustrator で図版の PDF と SVG（[golem-pdf ADR 0009](golem-pdf/adr/0009-svg-figures.md) の範囲の中）を書き出し、`modules/golem-driver/test/fixtures/figures-external/` に `illustrator.pdf` と `illustrator.svg` として加えること。README の表に版と書き出しの設定を書くと、golem-driver のテストがその二つも検査する（[docs/adr/0232](adr/0232-check-inks-fonts-figures-links-and-epubs-structurally-in-ci.md)）。
  - 12 の線の種類の脚注の区切り線と同じ太さと長さの線を InDesign で引いて並べ、多重線の比、点の間隔、和文の点線の形を比べること（[golem-driver ADR 0028](golem-driver/adr/0028-rule-colour-and-style.md)）。色が DeviceCMYK の版だけに出ることと、技術書のコードブロックの強調の網の版は、golem-driver のテストが内容のストリームの色で確かめる（[docs/adr/0232](adr/0232-check-inks-fonts-figures-links-and-epubs-structurally-in-ci.md)）。

## v1.x

v1.0.0 の後、v2 より前の minor のバージョンで扱う事項である。

- **人工言語と独自方言の言語タグ**：ロジバンなどの言語や独自方言について、著者が言語タグとその扱いを設定できるようにする。たとえばロジバンは `jbo`、著者独自の日本語の方言は私用部分を持つ `ja-x-my-dialect` と表せる。表示名と組版の継承規則、標準タグと設定の優先順位、各出力に書くタグを決める。
- **Emet から WebAssembly への変換**：Emet のコードを WebAssembly（Wasm）にコンパイルできるようにする。
- **数の表記の追加**：登録表に、和文と欧文のほかの表記（アラビア・インド数字、デーヴァナーガリー数字、ギリシャ文字、ヘブライ数字など）を加える（[ADR 0177](adr/0177-note-mark-style-and-numerals.md)）。CSS の表記と同じ規則の表記には、CSS の名前を使う。
- **オンメモリのプロジェクト**：プロジェクトを、ファイルシステムに読み書きせずに、メモリの上だけで組めるようにする。マニフェスト、`style.toml`、原稿、図版、フォント、表のファイルを仮想ファイルシステムから読み、出力も仮想ファイルシステムに書く。理由は二つある。一つは、テストのたびに一時ディレクトリにプロジェクトを作らずに済み、テストを書きやすく、速くすることである。もう一つは、Golem を部品として使うソフトウェアのためである。たとえば、外国語の論文の PDF を、日本語訳と原文を左右に並べて組み、原文をいつも確かめながら読めるソフトウェアを後に作る予定がある。このソフトウェアは訳を改めるたびに組み直すので、そのたびにファイルシステムに書き出すのは効率が悪い。仮想ファイルシステムの形（読み込みと書き出しの境界、パスの扱い、プロジェクトの外を指すパスの拒否）、どのモジュールがファイルシステムを直接触っているかの洗い出し、プラグインのキャッシュとフォントの扱い、ライブラリとして公開する API の形を ADR で決める。同じ入力なら、ディスクから組んでもメモリから組んでも同じバイト列になることを、決定性の検査に加える。CLI の振る舞いは変えない。
- **中国語と韓国語の組版**：`[lang]` と `@lang` で `zh` と `ko` を指定した部分は、欧文と同じに扱う（[ADR 0187](adr/0187-inline-language-switch.md)）。両用の文字は欧文の語に含め、漢字とハングルは和文の文字クラスで組むので、どちらの言語の規則にもなっていない。その部分に、中国語（簡体字と繁体字）と韓国語の組版の規則（約物の幅と配置、禁則、字間、ハングルの語間の空白と改行の位置）を当てる。拠る文書（W3C の clreq と klreq）と、本の言語が `zh` か `ko` の本をどこまで組めるようにするかを、ADR で決める。ハングルの音節の箱の単位は、v2 以降の「箱の単位と書記素クラスタの食い違い」と合わせて扱う。
- **HTML の本文の段落の空きの規則**：仕様書の「既知の不具合」の「HTML で本文の段落の前の空きが、すべての段落に当たる」と「HTML で本文の段落のあいだの空きが、どのスタイルの段落の後にも当たる」を直す。本文の規則を `p` ではなく `p:not([class])` に当てる案があるが、詳細度で [docs/adr/0217](adr/0217-html-spaces-of-paragraph-styles-redefined-in-files.md) の H1 を破らないかを確かめてから ADR で決める。
- **字間の空いた行の残り**：[golem-layout ADR 0045](golem-layout/adr/0045-break-inline-code-after-hyphens-and-full-stops-to-avoid-loose-lines.md) で、本文の中のコードの `-` と `.` の後でも改行するようにした後も、最後の段階で送り出して和文の字のあいだが四分を超えて空いた行が、二つのマニュアルに残る。多くは、付録 E の項目の見出しのように、コードの中に伸びるグルーがなく、識別子とコードのあいだの空白一つにすべての空きが寄る行である。JLReq の 3.8.4 の 4 に従ってコードの和文の字のあいだも空けるか、見出しの組み方を変えるかを比べ、ADR で決める（[golem-layout ADR 0045](golem-layout/adr/0045-break-inline-code-after-hyphens-and-full-stops-to-avoid-loose-lines.md) の「メンテナーが決めること」の 7）。空いた行を `golem preflight` の検査で報告するかも、同じく決める（同じく 9）。
- **行末の約物の空きを行の調整に使う**：JLReq の 3.8.3 の b と c は、行末の終わり括弧類、読点類、句点類の後ろの二分と、行末の中点類の前後の四分を、詰める処理の段としてベタ組にする。Golem の行末の空きは、グルーではなく行の最後の箱の端に置く固定の量であり、行の調整に使わない。二分かベタ組のどちらかを選ぶ空きは連続に動くグルーでは表せず、分割の候補ごとに二つの幅を量る変更が行分割に要る。既定のセット `gyomatsu-yakumono-hankaku` では行末の空きが 0 なので、既定の組版には関わらない。`gyomatsu-yakumono-zenkaku` の行末をどう扱うかを ADR で決める（[ADR 0278](adr/0278-use-the-places-of-line-adjustment-in-the-order-of-jlreq.md) の「メンテナーが決めること」の 7）。
- **語の最初の字が両用の字の語の書体**：区間の外の `“said` は、`ceWordAdvance` が語の最初の字の `“` でシェイピングを選ぶので、語の幅と端の字の送りを和文の書体で測る可能性がある。描く側の書体の選び方と合うかを調べ、ADR で決める（[docs/adr/0222](adr/0222-line-breaking-points-the-invariants-did-not-decide.md) の「メンテナーが決めること」の 6）。
- **`style.toml` の分割**：ほかのファイルを取り込む機能（[golem-project ADR 0002](golem-project/adr/0002-style-toml.md)）。
- **`@style-def` の複数行の記法**：一つのスタイルの定義を、複数の行に分けて書けるようにする。今は、一つのスタイルは一行の `@style-def` で定義し、同じ名前を二つの `@style-def` に分けて書くことはできない（[docs/adr/0014](adr/0014-in-file-settings.md)）。欄の多いスタイルや正規表現スタイルでは一行が長くなる。行の分け方（続きの行の字下げ、本体を持つブロックコマンドにするか）は ADR で決める。
- **行分割の拡張**：[ADR 0276](adr/0276-hyphenate-words-by-the-patterns-of-their-language.md) で同梱しなかった言語のパターン、パターンによるハイフネーションを含む TeX との参照テスト（[golem-layout ADR 0001](golem-layout/adr/0001-knuth-plass-line-breaking.md)、[golem-layout ADR 0007](golem-layout/adr/0007-knuth-plass-reference-test.md)、[golem-layout ADR 0008](golem-layout/adr/0008-explicit-hyphens.md)）。
- **ビルドと LSP の速度**：インクリメンタルなビルドと結果のキャッシュ、ファイルの変更の監視、ページへの配置の並列化、LSP の差分の同期とインクリメンタルな再解析、コンパイルでの回復しない解析、プラグインの初期化済みのメモリの複製。いずれも速度が問題になってから ADR で検討する（[golem-driver ADR 0001](golem-driver/adr/0001-build-pipeline.md)、[golem-driver ADR 0002](golem-driver/adr/0002-pdf-pipeline.md)、[golem-lsp ADR 0001](golem-lsp/adr/0001-language-server.md)、[golem-parser ADR 0002](golem-parser/adr/0002-parser-on-peg-hs.md)、[golem-plugin ADR 0001](golem-plugin/adr/0001-wasm-host-and-abi.md)）。
- **表の拡張**：罫線の色と種類（縦の罫、本体の行のあいだの罫を含む）、表のための `style.toml` の設定（罫線の太さ、列の間隔、表の寄せ）、セルの結合とセルの中のブロック、縦組みの本の中の横組みの表、表の行の途中での改ページ、表の続きを示す文言、見出しの行に本体と別の段落スタイルを当てること、v1.0.0 でセルに当てない段落スタイルの欄（`line-breaks`、`space-between`、`space-before`、`space-after`、`align`、字下げ、罫線、背景と囲み）をセルに当てること、表ごとのキャプションの位置（[golem-driver ADR 0008](golem-driver/adr/0008-pdf-tables.md)、[docs/adr/0262](adr/0262-table-numbers-captions-column-widths-and-cell-styles.md)）。使い手の組版の自由に応えるため、セルにも段落スタイルのすべての欄を当てられるようにする（2026-11-09 の tett23 の決定）。
- **文字の変形と詰め**：InDesign の文字パネルの水平比率と垂直比率、文字回転、文字ツメ、文字前と文字後のアキ量、二字の間に値を指定する手動のカーニング。水平比率と垂直比率は、縦組みでの比率の意味を資料で確かめられず、HTML と EPUB で字形を伸縮する CSS がない。長体と平体は、幅の異なる書体を役割に指定して代える（[docs/adr/0020](adr/0020-indesign-character-features.md)）。
- **面付け**：組んだページを、印刷の刷版の大きさの紙に、折りと製本の順に並べた PDF を出す。折丁（一枚の紙を折って作る 8 ページ、16 ページなどのまとまり）の大きさ、中綴じと無線綴じ、フォリオ（ページの上下や左右の並べ方）の選択、面付けの PDF に付けるトンボと折りの印を含む。今の Golem は、一ページを一枚の PDF のページとして出し、面付けは印刷所の側で行う前提である。

## v2 以降に回した事項

v1 の範囲から外し、v2 以降に送ると決めた事項である。
v2 では、数式の組版を先に扱い、その後に InDesign との互換性を高める。
v2.0.0-rc1 は、数式の組版かその下準備、あるいはその両方を扱う予定である。
それぞれの理由は、仕様書の対応する節と ADR に記載している。

- **数式の組版**：EPUB と HTML は MathML で出せるが、PDF には数式の組版エンジンが必要であり、それだけで独立した大きな仕事になる。当面は、数式を画像にして図版として入れる。
  - 数式と図の記法は、TeX の数式の記法と TikZ を採る。数式の組版のために新しい記法を覚えようとする使い手は、今ではほとんどいないはずだからである。どこまでを受け付けるか（TeX の数式の範囲、TikZ のライブラリの範囲）は ADR で決める。
  - 数式の組版のサンプルとして、短い本を三冊用意し、fixture とマニュアルの例に使う。内容は凝らなくてよい。
    - 「論理、集合と写像」のような本：命題と論理式、集合の記法、写像の定義と図式で、数式の組版の基本を確かめる。
    - 「圏論入門」のような本：可換図式で、TikZ が矢印の図を描けることを確かめる。
    - 「楕円曲線関数入門」のような本：曲線のグラフや図で、TikZ が座標の図を描けることを確かめる。
- **式の超越関数**：三角関数、指数関数、対数関数と、浮動小数点数の指数による累乗（[golem-eval ADR 0001](golem-eval/adr/0001-expression-language-and-numerics.md)）。
- **改ページの大域の最適化**：見開きの単位の最適化と、段組みの段の高さの調整を含む（[golem-layout ADR 0003](golem-layout/adr/0003-pagination-and-s2.md)）。
- **フレーム**：レベル 2 と 3 のフレーム。型は定義してあり、v1 では値を書くとエラーになる（[golem-layout-spec ADR 0001](golem-layout-spec/adr/0001-page-geometry.md)、[golem-project ADR 0002](golem-project/adr/0002-style-toml.md)）。
- **段組みの拡張**：v1 で実装する段組み（仕様書の [「style.toml」の節](specifications.md#styletoml) の段組み、[docs/adr/0018](adr/0018-multi-column-layout.md)）を超える部分。段抜きの見出し、索引のほかで一冊の中で段数を切り替えること、段組みの版面での回り込みと段をまたぐ除外領域を含む（[golem-driver ADR 0003](golem-driver/adr/0003-pdf-heading-styles.md)、[golem-driver ADR 0005](golem-driver/adr/0005-pdf-wrapped-figures.md)、[golem-driver ADR 0007](golem-driver/adr/0007-pdf-index-and-bibliography.md)、[golem-layout ADR 0004](golem-layout/adr/0004-wrapped-figures.md)）。段の高さの調整は「改ページの大域の最適化」に、段組みの版面での傍注の領域は「傍注の拡張」に含める。索引の段組みは [docs/adr/0025](adr/0025-index-columns.md) で v1 に入れた。
- **notice の局所的な抑制**：textlint の無効にするコメントのように、`.gm` の中で notice を局所的に抑制するブロックコマンド。今の抑制は `manifest.toml` の `silence-notices` と `--no-notices` による本の全体の単位であり、縮めた図版の notice の G07039 も図版ごとには抑制できない。本の全体での抑制で困る例が出たら、別の ADR で加える（[golem-driver ADR 0034](golem-driver/adr/0034-fit-figures-to-column.md)）。
- **目次の拡張**：章ごとの小目次（v1 の `@toc` は文書に一つだけ）、リーダーの字の設定、折り返した題のぶら下げ、図目次と表目次（[golem-driver ADR 0009](golem-driver/adr/0009-pdf-toc-page-numbers.md)）。
- **縦組みの傍注**：v1 の傍注は横組みに限る（[golem-layout ADR 0006](golem-layout/adr/0006-sidenotes.md)）。
- **索引の拡張**：索引の三段以上の階層（v1 は二段まで）、副項目の折り返した行の字下げ、縦組みの本の索引を横組みにして巻末から始めること。参考文献の書式の選択（著者名の順の一覧を含む）と書誌のぶら下げ字下げは、v1.0.0 の「参考文献のスタイル」で扱う（[golem-doc ADR 0002](golem-doc/adr/0002-document-assembly.md)、[golem-driver ADR 0007](golem-driver/adr/0007-pdf-index-and-bibliography.md)）。
- **Web 経路のスタイル**：HTML と EPUB で、見出しの `font` と `size`、文字スタイルの `size`、`caption` と `sidenote` 以外の段落スタイルの `size` を使うこと、Web 経路のフォントのサブセット化（[docs/adr/0005](adr/0005-character-and-paragraph-styles.md)、[golem-driver ADR 0010](golem-driver/adr/0010-caption-style.md)、[golem-html ADR 0001](golem-html/adr/0001-xhtml-serializer.md)）。
- **特色（スポットカラー）**：Separation と DeviceN の色空間。今の Golem はプロセスカラーだけを扱う（[golem-pdf ADR 0002](golem-pdf/adr/0002-pdf-x-4.md)）。
- **プラグインの配布機構**：レジストリと、許容するバージョンの範囲を宣言して解決する方式、配布されたバイナリがどのソースから作られたかの検証、キャッシュの削除と整理のコマンド（[golem-plugin ADR 0002](golem-plugin/adr/0002-distribution-and-lock.md)）。
- **配布の拡張**：macOS の実行ファイルの署名（Developer ID）と公証、Homebrew の tap とインストール用のスクリプト、再現可能なビルド、`-split-sections` による実行ファイルの縮小（[docs/adr/0004](adr/0004-binary-distribution-and-release.md)）。
- **傍注の拡張**：段組みの版面での傍注の領域、収まらない傍注を脚注に回すことと傍注のために本文の行を次のページに送ること、脚注の本文とキャプションの中の傍注の配置（[golem-driver ADR 0006](golem-driver/adr/0006-pdf-sidenotes.md)）、複数の段落の傍注（意味論 IR の傍注の本文はブロックの並びだが、`Golem.Doc.Validate` が段落をちょうど一つに限る。[docs/adr/0263](adr/0263-notes-with-more-than-one-paragraph.md)）。
- **注の本文のリストとコード**：脚注の本文に、リスト、コードなどの段落でないブロックを置くこと。意味論 IR の注の本文はブロックの並びだが、評価と `Golem.Doc.Validate` は段落だけを受け付ける。PDF の脚注の領域でのリストの字下げ、コードの背景と改ページを、注の行の格子の上で決める必要がある（[docs/adr/0263](adr/0263-notes-with-more-than-one-paragraph.md)）。
- **正規表現のエンジンを Oniguruma に基づくものにすること**：正規表現スタイルのエンジンを、Oniguruma を土台にしたものに置き換える。InDesign の正規表現の方言は、Oniguruma を改造して受け付けるようにする。v1 の正規表現スタイルのエンジンと方言は [docs/adr/0015](adr/0015-regex-styles.md) で決め、再実装した照合器（golem-regex）を使う。置き換えたときの方言の範囲と、v1 の方言で書いた設定との互換は、置き換えの ADR で決める。
- **オプティカルカーニング**：グリフの輪郭から二字の間の空きを決めるカーニング。InDesign のオプティカルは欧文のグリフ向けだが、和文でも仮名の字面を詰めて遊ぶ組み方に使うことがあるので、和文にも働く方式とする。InDesign はアルゴリズムを公開していないので、InDesign と同じ値にはしない。方式は ADR で決める。v1 では `kerning = "optical"` をエラー（G03021）とする（[docs/adr/0020](adr/0020-indesign-character-features.md)）。
- **縦組みの本の中の横組みの部分**：縦組みの本（右開き）に、横組みの原稿（付録、索引、欧文の論文など）を混ぜて組むこと。横組みの部分は左開きで読むので、本の後ろの側から始め、ページを逆の順に並べ、ノンブルも後ろから数える。横組みの部分の判型と版面、ノンブルの数え方（本の通しにするか、横組みの部分で振り直すか）、目次と相互参照のページ番号の表し方、PDF のページの並べ方を ADR で決める。「索引と参考文献の拡張」の「縦組みの本の索引を横組みにして巻末から始めること」は、この一部である。
- **漢文の訓点**：漢文に返り点（レ点、一二点、上下点など）、送り仮名、句読点を付けて組む機能。縦組みでは、返り点を漢字の左下に、送り仮名を右下に小さく置く。記法、意味論 IR、各媒体での表現は、JLReq の漢文の扱いを参照して ADR で決める。
- **二色刷り**：二つの版で刷る本の出力。今の Golem は扱っていない。色と版の指定の仕方は ADR で決める。
- **文字の斜体の角度（skew）**：字形を傾ける変形の角度を設定できるようにする。雑誌のような組版に要るためである。今の合成の斜体（`synthetic-italic`）は傾きが 1/5 に固定である。傾きを変える設定は [golem-driver ADR 0004](golem-driver/adr/0004-pdf-emphasis-and-character-styles.md) と [golem-driver ADR 0012](golem-driver/adr/0012-synthetic-bold-weight.md) で作らないと決めていたので、決め直す ADR が要る。
- **フォントにも Unicode にもない字形**：フォントにも Unicode にもそのままの形では収録されていない字を組む扱い。例として、笙野頼子『水晶内制度』の「原」の字の扱いがある。原稿での書き方と、各出力での表し方を ADR で決める。
- **JAN コード**：奥付やカバーに置く JAN（EAN-13）のバーコードの扱い。生成と配置の仕方は ADR で決める。
- **絵文字のレンダリング**：カラーの絵文字のフォント（COLR/CPAL、sbix、CBDT、OpenType の SVG）のグリフ、ZWJ でつないだ絵文字の並び、異体字セレクタによる絵文字の表示と文字の表示の切り替えを、PDF と HTML で組めるようにする。各形式の描き方、PDF/X-4 との関係、HTML でフォントに任せる範囲は ADR で決める。
- **フォントのフォールバック**：役割のフォントにグリフがない字を、`style.toml` に役割ごとに宣言した代わりのフォントの列から順に探して組む。代わりのフォントの選び方は、環境によらず同じ結果になるように決める。`golem build` の G08100 と `golem preflight` の G09002 との関係（代わりのフォントで組んだ字を報告するか）を ADR で決める。グリフがない字は、`golem build` が G08100 で報告する（dev では警告、prod ではエラー、[docs/adr/0081](adr/0081-missing-glyphs-warn-in-build.md)）。この項目は、代わりのフォントで補う仕組みを扱う。カラーの絵文字のフォントを代わりのフォントに使う場合は、「絵文字のレンダリング」と合わせて決める。
- **diagnostics の英語化**：diagnostics、ヒント、使い方の表示を英語でも出す。既定では実行時のロケールを読んで言語を選び、オプション（たとえば `--lang en`）と設定で指定できるようにする。出力するファイル（PDF、HTML、EPUB、テキスト）はロケールによらないという [docs/adr/0002](adr/0002-determinism.md) の規則は変えず、言語が変わるのは端末に出す文言だけとする。JSON の diagnostic のコードと位置は言語によらない。着手するときに ADR を作成する。
- **章末の注の一覧の改ページと見出し**：v1 の章末の注の一覧は、前で改ページせず、見出しの文言は「注」（日本語以外は「Notes」）に固定する。一覧の前で改ページする設定と、見出しの文言を変える設定を加える（[golem-driver ADR 0026](golem-driver/adr/0026-chapter-end-notes.md)）。
- **孤立行の規則の見直し**：段落の最初と最後の行をページの境に一つだけ残さない規則（[golem-layout ADR 0003](golem-layout/adr/0003-pagination-and-s2.md)）は、ページの末尾に 1 行か 2 行の空きを残す。出版された本でもあまり気にされていないので今はこのままとし、必要になったら和文の本で緩めるかを検討する。
- **条件テキスト**：一つの原稿から、媒体（PDF、EPUB、HTML）や版（紙の版と電子版、教師用と生徒用など）ごとに本文の一部を出し分けること。InDesign の条件テキストと条件セットにあたる。どの単位で条件を書くか、媒体ごとの出し分けを媒体契約（仕様書の [「設計原則」の節](specifications.md#設計原則)）の中でどう認めるかを ADR で決める（[2026-10-17 の調査](audits/2026-10-17-latex-gap-for-v1.md)）。
- **差し込み**：外部のデータ（CSV など）の値を、組版に差し込んで組むこと。InDesign のデータ結合にあたる。名簿、カタログ、一つの型から多数の文書を組む用途に使う。データの形式、差し込む記法、一件ごとに文書を分けるか一冊に続けて組むかを ADR で決める。
- **箱の単位と書記素クラスタの食い違い**：行分割の箱は、基底の字と続く結合文字（一般カテゴリーが Mn、Mc、Me の字）を一つにまとめて作る（[golem-driver ADR 0036](golem-driver/adr/0036-combining-characters.md)）。ハングルの音節、ZWJ でつないだ絵文字、地域指示子の組、インド系の文字の子音の結合のように、HarfBuzz のクラスタや UAX #29 の拡張書記素クラスタがこの単位と一致しない文字では、一つの字が二つの箱に分かれうる。日本語と欧文のほかの言語を組むときに、箱の単位をシェイピングの結果か UAX #29 から決める仕組みを扱う。
- **Emet の型クラス**：v2 で Emet に型クラスを実装する。Emet は今は型クラスを持たないが、足すときに作り直さずに済むよう、予約語、型の検査と評価器の形を決めてある（[ADR 0160](adr/0160-emet-function-language-core.md) の「型クラスの余地」）。`Eq`、`Ord` と `deriving` から始めるかは、着手するときに ADR で決める。

## v3 より前（時期は未定）

v1.x から v2 のあいだのどこかで扱う。
時期は決めていないが、v1.x で扱う見込みが高い。

- **HarfBuzz と FreeType の置き換え（sofer）**：シェイピングとフォントの読み込みを、Golem 自身の実装 sofer に置き換える。名前は、聖典を一字ずつ書き写す書記（ソフェル）から取った。今は、バージョンを固定した HarfBuzz と FreeType を同梱して使う（[golem-font ADR 0001](golem-font/adr/0001-shaping-and-metrics.md)）。C のライブラリは wasm の版でツールチェーンの回避策を要している（[docs/adr/0199](adr/0199-pdf-typesetting-as-wasm-reactor.md)、[docs/adr/0238](adr/0238-build-golem-wasm-with-the-standard-exception-handling-and-run-it-under-wasmtime.md)）。置き換えれば、この回避策は要らなくなる。範囲（シェイピング、フォントの読み込み、ラスタライズ）、見た目の回帰テストのラスタライザ shem と共有するか、パッケージの置き場所（golem のモジュールか、peg-hs のような別のリポジトリか）を ADR で決める。名前は crates.io と Hackage では使われていない（2026-11-08 に確かめた）。

## v3 以降に回した事項

v3 の GUI は、次の原則に従って作る。

- **応答の悪いアプリケーションは最悪である**：操作への応答の遅さは、機能の不足よりも使う人を損なう。
- **時間のかかる作業は使う人を止めない**：組版、書き出し、検査のような時間のかかる作業は、裏で進め、その間も操作を受け付ける。止めることがどうしても要る場合は、止めていること、何を待っているか、どこまで進んだかを画面に示す。
- **デザインシステムで一貫性を保つ**：画面の部品、色、文字、余白、操作は、デザインシステムに定めたものだけを使う。画面ごとの例外を作らず、要るものはデザインシステムに足してから使う。

- **デザインシステムの構築**：GUI を作る前に、画面の部品、色、文字、余白、操作の規則をまとめたデザインシステムを作る。GUI の画面と、マニュアルやウェブの文書の見た目は、このデザインシステムに従ってそろえる。どこまでを Golem のスタイルの仕組みで表すかは ADR で決める。
- **アクセシビリティの基準**：GUI が満たすアクセシビリティの基準（準拠する規格と水準、キーボードだけでの操作、スクリーンリーダー、色のコントラスト、文字の拡大など）を定める。デザインシステムの構築と同時に決め、デザインシステムの部品はこの基準を満たすように作る。
- **GUI**：原稿とスタイルを編集し、組版の結果を確かめる画面。v2 までの Golem は CLI と CI で完結させる。ページ画像の差分を取る仕組みを自前で持つ場合も、GUI より後に扱う。
- **GUI の作り方**：GUI は Tauri で作り、すべての描画を canvas に任せる。描く内容は Golem が決め、canvas はそれを描くだけにする（グリフのアウトラインを座標と一緒に受け取ってパスとして描くか、Golem がページを画像にしたものを並べる）。ブラウザの文字の描画（`fillText`）には頼らないので、プレビューは PDF と同じ見た目になり、OS ごとの WebView の違いは表示の速さしか左右しない。Golem の本体は今のまま CLI と LSP で動かし、GUI はそれと通信する別のプロセスにする。原稿の入力欄には WebView の入力の仕組みを使い、日本語の IME と縦書きの入力を扱う。Linux の WebKitGTK の canvas の性能が足りなければ、そのときに代わりを検討する。着手するときに ADR を作成する。

## 手で確かめる項目

実装は終わり、自動のテストも通っているが、ADR が求める手作業の確かめがまだ残っている項目をここにまとめる。
確かめたら、結果を実装のプルリクエストか `docs/audits/` の記録に書き、この一覧から消す。

- **エディタ向けの構文の定義の読み込み**：`tools/editors/README.md` の読み込ませ方のうち、Visual Studio Code の手順（手元の拡張機能の `package.json` を VS Code が読むこと）を、実際のエディタで確かめていない。文法そのものは、VS Code と同じ `vscode-textmate` で読む `vscode-tmgrammar-test` が、CI の `editors` ジョブで確かめている。Neovim の手順のうち nvim-treesitter を使わないものは CI の `editors-lsp` ジョブが、Helix の手順は `editors` ジョブが確かめる。nvim-treesitter で GitHub から入れる手順は、Neovim 0.12.6 と nvim-treesitter の main ブランチの `e289100` で、ヘッドレスで確かめた（[docs/adr/0170](adr/0170-emet-editor-support.md)、[docs/adr/0171](adr/0171-neovim-setup-from-github-and-emet-lsp.md)、[docs/adr/0231](adr/0231-run-the-lsp-and-the-editor-grammars-in-headless-neovim-and-helix.md)）。
- **CIDSystemInfo と異体字**（v1.0.0 のリリースで確かめる）：Adobe-Japan1 の ROS を持つ実際のフォント（小塚明朝 Pr6N など）で組んだ PDF を Acrobat のプリフライトにかけ、IVS の異体字が出ることと、InDesign の書き出しと同じであることを確かめていない。リポジトリにそうしたフォントがないためである（[golem-pdf ADR 0006](golem-pdf/adr/0006-cid-system-info.md)）。フォントの `ROS` が `CIDSystemInfo` に写ることは、`ROS` を Adobe-Japan1-7 に書き換えた Source Han Sans のサブセットで、golem-font と golem-driver のテストが確かめる（[docs/adr/0232](adr/0232-check-inks-fonts-figures-links-and-epubs-structurally-in-ci.md)）。
- **プリフライトと商用のプリフライトの差**（v1.0.0 のリリースで確かめる）：Golem の G09014 が出なかった PDF を Acrobat のプリフライト（PDF/X-4 の適合の検査）にかけ、Acrobat が PDF/X-4 の誤りを報告するかを確かめていない。差があれば `Golem.Pdf.X4.verify` に足す要件を ADR にし、結果は `docs/audits/` に残す。同じ条件の文書を InDesign のプリフライトにかけ、同じ種類の問題が両方で出るかも確かめていない（[golem-cli ADR 0006](golem-cli/adr/0006-preflight.md)）。
- **トンボのレジストレーションの色**（v1.0.0 のリリースで確かめる）：トンボを付けた PDF を Acrobat のプリフライトとインキの総量の検査にかけること、InDesign の書き出しと同じ形であることを確かめていない。トンボが全版に出ることと本文に特色が混ざらないことは、golem-driver のテストが内容のストリームの色で確かめる（[golem-pdf ADR 0007](golem-pdf/adr/0007-registration-crop-marks.md)、[docs/adr/0232](adr/0232-check-inks-fonts-figures-links-and-epubs-structurally-in-ci.md)）。
- **PDF の図版の商用のプリフライト**（v1.0.0 のリリースで確かめる）：sRGB に置き換えた DeviceRGB と透明のグループを含む図版を Acrobat の PDF/X-4 の検査に通し、結果を `docs/audits/` に残す（[golem-pdf ADR 0008](golem-pdf/adr/0008-pdf-figures.md)）。Inkscape、LibreOffice Draw、Chromium の印刷、matplotlib、pdfTeX、LuaTeX が書き出した図の PDF を置いて組めることと拒む理由、元の PDF と画素で近いことは、`modules/golem-driver/test/fixtures/figures-external/` の試料で golem-driver のテストが確かめる（[docs/adr/0232](adr/0232-check-inks-fonts-figures-links-and-epubs-structurally-in-ci.md)）。
- **SVG の図版の見た目**：SVG の図版を含む PDF を Acrobat の PDF/X-4 の検査に通し、結果を `docs/audits/` に残すこと（v1.0.0 のリリースで確かめる）が残っている（[golem-pdf ADR 0009](golem-pdf/adr/0009-svg-figures.md)）。Inkscape と draw.io の SVG の試料の取り込みと G08011 は、golem-driver のテストが確かめる。draw.io 32.4.1 の SVG は、図形だけでも範囲の外の属性（`data-cell-id` など）を持つので、範囲の中に収まらない（[docs/adr/0232](adr/0232-check-inks-fonts-figures-links-and-epubs-structurally-in-ci.md)）。
- **縦組みのダッシュ**：縦組みの HTML のダッシュの向きは、`browser.yml` が Chromium と Safari で確かめる（[docs/adr/0234](adr/0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md)）。PDF の見た目は見た目の回帰テストの見本（`specimens-vertical`）で見て受け入れ、InDesign との比べ合わせは v1.0.0 の「Adobe の製品で確かめる見た目」に移した（[golem-driver ADR 0015](golem-driver/adr/0015-vertical-dashes.md)、[docs/adr/0233](adr/0233-add-the-specimens-of-the-visual-checks-to-the-visual-regression-test.md)）。
- **リストの字下げ**：入れ子のリストと 10 項目を超える番号付きリストを、横組みと縦組みの EPUB にして目で見ていない。PDF の見た目は見た目の回帰テストの見本（`specimens-horizontal` と `specimens-vertical`）で見て受け入れ、10 番目からの項目の本文の行頭は golem-driver のテストが確かめる。決定性の検査の蟹工船とテンペストの出力は、`scripts/determinism/hashes.txt` が守る（[golem-driver ADR 0013](golem-driver/adr/0013-list-indents.md)、[docs/adr/0233](adr/0233-add-the-specimens-of-the-visual-checks-to-the-visual-regression-test.md)）。
- **コマンドの中の空白の semantic tokens の見え方**：Ghostty の Neovim の本人のテーマで、コマンドと式の中の空白（型は `operator`）に背景や下線が出ないことを、目で確かめていない。既定の色の組で、その位置の強調のグループが背景も下線も持たないことは、CI の `editors-lsp` ジョブが確かめる。本人のテーマの強調のグループは、手元で `NVIM_APPNAME=<設定の名前> GOLEM=<golem> NVIM=nvim sh tools/editors/nvim/test.sh --theme` を走らせて確かめられる。`--theme` は `--clean` を外し、その設定と色の組で空白のテストだけを走らせる。端末の上での色の見え方は、このテストでは確かめない（[golem-lsp ADR 0008](golem-lsp/adr/0008-semantic-tokens-for-whitespace-and-remaining-punctuation.md)、[docs/adr/0231](adr/0231-run-the-lsp-and-the-editor-grammars-in-headless-neovim-and-helix.md)）。
- **コードブロックの見え方**：コードブロックの EPUB を読書環境で開き、`pre` と `code` の見え方を目で確かめていない。HTML の `pre` と `code` の `white-space` と書体は `browser.yml` が Chromium と Safari で確かめ、背景の色の版とコードの書体の埋め込みは golem-driver のテストと `golem preflight` が確かめる（[docs/adr/0232](adr/0232-check-inks-fonts-figures-links-and-epubs-structurally-in-ci.md)、[docs/adr/0234](adr/0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md)、[golem-driver ADR 0017](golem-driver/adr/0017-pdf-code-blocks.md)）。
- **技術書のコードブロックの見え方**：行番号、キャプション、強調、注釈の印を付けたコードブロックを PDF と HTML で開き、技術書として読める見た目であることを目で確かめていない。HTML で行番号と差分の印が選択とコピーに含まれないことは、`browser.yml` が Chromium と Safari で確かめる（[docs/adr/0234](adr/0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md)、[golem-driver ADR 0023](golem-driver/adr/0023-code-block-book-features.md)）。
- **本文の中のコードの改行の印の刷り**：既定の改行の印は、コードの字の大きさの 1/20 の太さの線を、コードの色の半分の網で描く（13Q で 0.16mm、11Q で 0.14mm）。オフセットの印刷で、網点のために線が途切れて見えないかを、刷って確かめていない。画面と PNG では、二つのマニュアルを組んで目で見た（[golem-layout ADR 0042](golem-layout/adr/0042-draw-the-wrap-mark-of-inline-code-small-and-light.md)）。途切れて見えれば、線の太さか色の比を改める ADR を作る。
- **マニュアルの中の InDesign の記述**（v1.0.0 のリリースで確かめる）：利用者向けのマニュアルの InDesign との対応と比較の記述（「はじめに」と付録 E）を、InDesign に詳しい人が確かめていない（[docs/adr/0024](adr/0024-manual-audiences-and-policy.md)）。
- **shem が描く画像と図版**：画像と図版のある見た目の回帰テストの入力（`figures`、`complex-vertical`、`complex-horizontal`、`specimens-horizontal`、`specimens-vertical`）を shem と pdftoppm で描いて並べ、色、透過、向き、切り抜きが合うことを目で確かめていない。shem の描いた結果が正しいことは、shem 自身のテストでも見た目の回帰テストでも示せない（[docs/adr/0294](adr/0294-draw-images-and-figures-in-the-visual-regression-test.md)）。shem は ICC のプロファイルを使わないので、色は近ければよい。

- **v0.1.0-rc4 のリリースの前のマニュアルの目視**：rc3 の作業でマニュアルを直した箇所を、組んだ PDF と HTML で目で確かめていない。v0.1.0-rc3 のリリース（2026-10-24）までに見られなかったので、メンテナーが v0.1.0-rc4 のリリースの前にまとめて確かめる（[docs/adr/0233](adr/0233-add-the-specimens-of-the-visual-checks-to-the-visual-regression-test.md)）。
  - 行番号を付けたコードブロック。利用者のマニュアルの第 1 章の『高野聖』の原稿で、本文の「11 行目と 20 行目」が行番号と合っていること。第 4 章、第 5 章、第 8 章、開発者のマニュアルの `.wat`、チャネルの例、関数の型の一覧、ADR の雛形も見ること。
  - 利用者のマニュアルの第 3 章で、行アキの上限（G04011、[docs/adr 0047](adr/0047-blank-line-limit.md)）、回した図版を待つあいだの改段と白ページ、「数と式」に足した散文スロットの段落と、付録 E の G04011 の項。
  - 開発者のマニュアルのチャネルの図（`channels` と `channels-example`）のラベル（[golem-doc ADR 0007](golem-doc/adr/0007-plugin-channel-lists.md)）。
  - G08014 の言い換え（「動的なコンテンツ」）が入った箇所。
  - 開発者のマニュアルの 22 ページのコードの空白と前後の空き、利用者のマニュアルの 285 ページの参照の 11、12、14。
  - マニュアルの付録の注（[golem-driver ADR 0018](golem-driver/adr/0018-footnote-marks-and-numbers.md)）。
- **EPUB の読書環境での見え方**：別のファイルの参考文献への引用のリンク、ナビゲーション文書の深さ、プラグインの独自のチャネルを使った EPUB を、ブラウザと読書環境で開いて見え方を確かめていない。三つを含む fixture の `epub-forms` は、CI が epubcheck にかける（[docs/adr/0232](adr/0232-check-inks-fonts-figures-links-and-epubs-structurally-in-ci.md)、[golem-html ADR 0003](golem-html/adr/0003-cite-links-across-files.md)、[golem-epub ADR 0002](golem-epub/adr/0002-nav-and-toc-depth.md)、[golem-doc ADR 0007](golem-doc/adr/0007-plugin-channel-lists.md)）。
- **タグ付き PDF の読み上げ**：タグ付き PDF を、macOS の VoiceOver と Acrobat Reader、Windows の NVDA と Acrobat Reader で読み、縦組みの本文、ルビ（親文字の後に読み）、注（印の直後に注の本文）の読む順と、図版の代替テキストが読まれることを確かめていない。veraPDF が調べるのは PDF/UA-1 のうち自動で調べられる要件だけである（[docs/adr/0183](adr/0183-tagged-pdf-and-pdf-a.md)）。
- **PDF のリンクの注釈**（v1.0.0 のリリースで確かめる）：リンクを含む横組みと縦組みの PDF を、Acrobat Reader と macOS のプレビューで開き、リンクの矩形をクリックして URL が開くことを確かめていない。文書の中のリンクとしおり（[docs/adr/0267](adr/0267-pdf-bookmarks-and-links-inside-the-document.md)）も、横組みと縦組みの `conformance` の fixture の PDF を Acrobat Reader と macOS のプレビューで開き、しおりのパネルが開いて最上位の項目だけが並ぶこと、しおりと各種のリンクをクリックして行先の行がウィンドウの上端に来ることを確かめていない。Poppler の `pdfinfo -url` がリンクの注釈の URL とページを読むことは、golem-driver のテストが確かめる（[docs/adr/0232](adr/0232-check-inks-fonts-figures-links-and-epubs-structurally-in-ci.md)）。ISO 15930-7:2010（PDF/X-4）の本文で、注釈と URI のアクションを禁じる規定がないことも確かめていない。この照合は、v1.0.0 のタグの前にメンテナーが行い、`docs/audits/` に記録する（[docs/adr/0221](adr/0221-check-iso-15930-7-for-link-annotations-before-rc4.md)、[docs/adr/0226](adr/0226-move-the-iso-15930-7-check-to-before-v1.md)）。禁じる規定があれば、`[color] intent` のある本にリンクを書く扱いを改める ADR を作る（[docs/adr/0182](adr/0182-external-links.md)）。
- **CI のキャッシュの量**：`caches` ジョブを入れた後、`main` の 24 時間後と 7 日後（2026-11-15 ごろ）にキャッシュの量が 10 GB を下回り、プルリクエストのキャッシュが消えていることを確かめていない（[docs/adr/0228](adr/0228-keep-the-ci-caches-under-the-10-gb-limit.md) の I5）。結果は `docs/ci-timings/2026-11-08-ci-caches-under-the-limit.md` とは別の記録として `docs/ci-timings/` に書き、項目を外す。所要時間の数え直しは、`verapdf` を臨界経路から外した後の記録で代える（[docs/adr/0244](adr/0244-take-verapdf-off-the-critical-path-of-ci.md)）。
- **リリースノートのプロンプトの大きさ**：プロンプトの ADR を題名とステータスの行に絞り、プルリクエストの本文を 4000 バイトで切った後のリリースで、ジョブ `notes` のログのプロンプトのバイト数と、AI のノートが `check-notes.sh` を通ったことを確かめていない。v0.1.0-rc3 から v0.1.0-rc4 までの範囲では、手元で組んだプロンプトは 885692 バイトだった。次のリリースの `notes` のログか、タグの前に `workflow_dispatch` で動かした `release.yml` のログで確かめ、項目を外す（[docs/adr/0246](adr/0246-bound-the-prompt-of-the-release-notes.md)）。

## 未決事項

次の事項が決まっていない。
v1 より後のバージョンのための事項には、そのバージョンを書く。
決めたら、仕様書か ADR に書き、この一覧から消す。

- **Linux の Neovim での `silence-notices` の保存**：Neovim 0.12.6 は、`workspace/didChangeWatchedFiles` の動的な登録を macOS と Windows でだけ申し出て、Linux では申し出ない（`vim.lsp.protocol.make_client_capabilities`）。golem lsp は、ディスクの `manifest.toml` の変更をこの通知でだけ知る。この登録を申し出ないクライアントでは、`silence-notices` にコードを加えて保存しても、LSP を起動し直すまで notice が消えない（macOS の Neovim で、能力を Linux と同じにして確かめた）。CI の `editors-lsp` の notice のテストは、クライアントの能力でこの登録を申し出て確かめている。`manifest.toml` の保存（`textDocument/didSave`）でも評価し直すかが決まっていない（[docs/adr/0231](adr/0231-run-the-lsp-and-the-editor-grammars-in-headless-neovim-and-helix.md)）。[docs/adr/0231](adr/0231-run-the-lsp-and-the-editor-grammars-in-headless-neovim-and-helix.md) の I3 は、この登録を申し出るクライアントについての性質と読む（[docs/adr/0259](adr/0259-record-what-the-audit-of-the-ci-release-and-tooling-adrs-found-on-2026-11-09.md)）。
- **PDF/X-4 の要件と規格の本文の照合**：[golem-pdf ADR 0002](golem-pdf/adr/0002-pdf-x-4.md) は、規格の本文を参照せずに要件を書き、本文と照合して差分があれば新しい ADR を作るとしたが、照合の結果を記した ADR はない。文書情報辞書と XMP の値を一致させる要件も、本文では確かめていない（[golem-pdf ADR 0005](golem-pdf/adr/0005-producer.md)）。v1 の PDF を PDF/X-4 として出すまでに、本文と照合するか、商用のプリフライトでの確認で代えるかが決まっていない。
- **裸の語の `*`**：`a*[x]` が `a*` と `[x]` の二つの引数として読まれるなど、`*` を含む裸の語の扱いに不整合がある（[golem-parser ADR 0007](golem-parser/adr/0007-grammar-label-safety.md)）。受理する言語をどう決め直すかが決まっていない。
- **和字の直後の欧文の句読点の前の空き**：行組版は、和字の直後の欧文の句読点（`.`、`,`、`:` など）の前にも和欧間の空き（四分）を入れる。ASCII の文字をすべて欧文に分類するためである。JLReq の 3.2.6 は和字と欧文のあいだに四分の空きを置くと定めるが、欧文の句読点が和字の直後に来る場合の扱いは確かめた範囲の本文では読み取れなかった。JLReq と JIS X 4051 の本文で確かめ、変えるなら別の ADR で扱う（[golem-doc ADR 0004](golem-doc/adr/0004-bibliography-formatting.md)）。
- **減らした段より大きい図版、表、コードブロック**：図版、表、コードブロック、回り込む図版は、空の段なら段の残りより大きくても置く。`@page-lines` で段の行数を減らすと、これらが段からはみ出しうる。図版は一ページの行数に収めて縮めるので（G07039）、減らした段には収まらないことがある。見出しの同じ場面は notice の G07100 で知らせるが（[golem-layout ADR 0020](golem-layout/adr/0020-heading-taller-than-column.md)）、原因ごとにコードを分けるので、これらには含めていない。実機では確かめていない。diagnostic にするのか、重大度を何にするのかが決まっていない。
- **HTML の見た目の回帰テスト**：HTML の出力を画像にして比べるテストは、rc4 から外した。ブラウザーによって見た目が変わり、手間に見合わないからである。ブラウザー上の文書のレイアウトに細かくこだわる使い手は少ないと考えられ、大きく崩れなければよい。やるかどうかと、やるならどのブラウザーで比べるかが決まっていない。
- **開いた範囲と半開きの範囲**：`@listing` の `lines` とコードブロックの `highlight` の範囲、式の言語の範囲の値は、両端を含む閉じた範囲（`1...10`）だけである（[ADR 0113](adr/0113-closed-range-literal.md)）。`..` は、端を省いた範囲（`5..`、`..5`）と終わりを含まない範囲のために予約し、今は書くと予約された記法のコード G01100 になる（[ADR 0115](adr/0115-reserved-syntax-code.md)）。終わりを含むかどうかを一字の違い（`..` と `...`）で書き分けると、書き違いが黙って一行ずれた出力になる。省いた端の意味は、`lines` ではファイルの最後の行、`highlight` ではコードの最後の番号と箇所ごとに変わり、範囲の値として持つなら端のない範囲の表し方、比較、プラグインへの形も要る。`..` を使う範囲を設けるかどうかと、設けるならどの形にするかが決まっていない。
- **`-` で区切った範囲をエラーにするリリース**：`lines=10-20` のような `-` で区切った範囲は、廃止予定の notice（G02108）を出して受け付けている（[ADR 0113](adr/0113-closed-range-literal.md)）。1.0.0 には廃止予定の書き方を残さないので、v0.1.0-rc4 の後、1.0.0 までにエラーにすると決めた（[ADR 0174](adr/0174-compatibility-promises-for-1-0.md)、[docs/compatibility.md](compatibility.md) の「廃止予定の書き方」）。v0.1.0-rc4 の後にプレリリースを挟んでエラーにするか、1.0.0 でエラーにするかが決まっていない。エラーにするのは別の ADR で行う。
- **表のセルをインラインの記法として読むこと**：`@table` の `cells` のキーワード引数は、セルの読み方を決める引数として予約してあり、今は `text` だけを受け付け、`cells=markup` はエラー（G02084）になる（[golem-eval ADR 0004](golem-eval/adr/0004-tsv-tables.md)）。`cells=markup` は、将来セルをインラインの記法として読むための名前として決めた。実装するかと、どのバージョンで扱うかが決まっていない。
- **`tsv-table` と `@table` の上限の違い**：見本のプラグイン `tsv-table` は、TSV の大きさを 8 MiB、表のセルの合計を 50,000 個までとし、`@table` の 16 MiB とは違う（[docs/adr/0129](adr/0129-tsv-table-plugin.md)）。日本語の 16 MiB、50,000 セルの表で、一回の呼び出しの命令数の上限（約 10 億）を超えたためである。同じ TSV が `@table` では表になり、`tsv-table` ではならないことがある。上限の境界（命令数の上限をどこまで上げるか、プラグインの命令数をどこまで減らせるか）を調べ、二つの上限を揃えるかが決まっていない。
- **本の全体の大きさとメモリ**：PDF に組む表のセルの数の上限（G07108）は、表ごとに 100,000 である（[ADR 0224](adr/0224-limit-the-cells-of-a-table-set-in-pdf.md)）。上限の中の表をいくつも置いた本は、表の数に比例してメモリを使う（10 万セルの表を十個置けば、表だけで 10 GB ほどと推した。測っていない）。原稿の本文も、大きさに比例してメモリを使う（kanikosen の 204 KB で常駐 409 MB）。本の全体の表のセルの数や、本の全体のメモリに上限を置くかが決まっていない。
- **Emet の関数で IR を書き換えること**：Emet の関数で、文書の全体の意味論 IR を書き換えられるようにしたい。Emet のフィルタ（[ADR 0162](adr/0162-calling-emet-functions-from-gm.md)）は、プラグインのフィルタと同じくファイル内評価（S0）の一つのファイルしか見られない。文書の全体を見る関数を足すときは、[ADR 0162](adr/0162-calling-emet-functions-from-gm.md) の IR のデータ型を使い、関数の種類の語を一つ足す。どの段階（S1 の後など）で動かすか、評価の階層との関係をどう保つかが決まっていない。
- **組み込みのコマンドを Emet で書き換えること**：組み込みのコマンドの一部を Emet の関数で書き換える可能性がある。プラグインの `overrides` と同じく `manifest.toml` で宣言する形にするか、Golem が組み込みのコマンドを `.emet` で書いて同梱する形にするかが決まっていない（[ADR 0162](adr/0162-calling-emet-functions-from-gm.md) の「組み込みのコマンドとの関係」）。
- **Emet が `.gm` に返す共有された値の大きさ**：手数は、組み込みの関数と `++` が作る値の長さを数える（[docs/adr/0223](adr/0223-emet-sizes-before-building-values.md)）。`List.map` で同じ文字列を指す要素を百万並べた値を `.gm` に返すと、手数は百万の桁だが、意味論 IR の文字の延べの数はその文字列の長さ倍になる。結合の操作を通らないので、今の手数では数えない。返す時点で延べの大きさを数えるか、数えるなら値を返す経路（コマンド、式、フィルタ）ごとにどう数えるかが決まっていない。再現は試していない。
- **Emet の式文脈のキーワード引数**：Emet の `pub fn` は、`.gm` の式文脈の呼び出し（`f(x)`）がキーワード引数を持たないので、キーワード引数を持たない（[ADR 0162](adr/0162-calling-emet-functions-from-gm.md)）。式文脈の呼び出しにキーワード引数の記法を足すかが決まっていない。
- **Emet の要求の種類**：Emet の関数が求められる要求は、v0.1.0-rc4 ではファイルを読むこと（`file`）だけである（[ADR 0161](adr/0161-emet-requirements-and-driver-handlers.md)）。書字方向や数の表記のような本の文脈を読む要求を足すかと、利用者がハンドラを書けるようにするかが決まっていない。
- **Emet の関数から `@set` の変数を読むこと**：Emet の関数は、`.gm` の `@set` の変数を直接読めず、引数として受け取る（[ADR 0162](adr/0162-calling-emet-functions-from-gm.md)）。読めるようにすると、関数の結果が呼び出しの位置の変数の状態に依存し、同じ引数でも結果が変わる。読む手段を要求の種類として足すかが決まっていない。プロジェクト全体の変数（`manifest.toml` の `[vars]`）は、Emet の関数から直接読まず、引数として渡す（[docs/adr/0185](adr/0185-project-wide-variables.md)）。`vars` の値は本の全体で一つに決まり、呼び出しの位置によらないので、この「呼び出しの位置の変数の状態に依存する」問題は `vars` にはない。`vars` を読む要求の種類を足すかは、「Emet の要求の種類」とあわせて決める。
- **golem-eval の責務**：Emet の関数の表は golem-eval の `EvalContext` に置く（[ADR 0162](adr/0162-calling-emet-functions-from-gm.md)）。golem-eval は、式文脈の評価、ファイル内評価、プラグインと Emet の関数の呼び出しを抱えている。golem-eval をこのまま広げるか、関数の呼び出しなどの責務を別のパッケージに分けるかが決まっていない。
- **golem-emet-test を一つずつ走らせる制限を外すこと**：golem-emet-test は、aarch64 の GHC の不具合（GHC の issue [#28001](https://gitlab.haskell.org/ghc/ghc/-/issues/28001)）を避けるために、`localOption (NumThreads 1)` でテストを一つずつ走らせる（[docs/adr/0207](adr/0207-run-golem-emet-test-one-test-at-a-time-under-the-watchdog.md)）。GHC の 9.14.2 が ghcup に出たら、または #28001 が直った版が出たら、ADR の文脈の再現の手順（変更の前のテストのソースと、同時整形のプログラム）を aarch64 の macOS と Linux で走らせる。落ちも止まりも消えたら、`localOption (NumThreads 1)` を外す ADR を書く。どの版で直るかが決まっていない。
- **本番で .emet の構文解析が同時に走る経路**：言語サーバーは、semantic tokens の要求ごとにスレッドを立て、.emet の構文木を作る。構文解析が複数のスレッドで同時に走るので、golem-emet-test と同じ GHC の不具合に当たりうる（[docs/adr/0207](adr/0207-run-golem-emet-test-one-test-at-a-time-under-the-watchdog.md)）。macOS で 1,200 回の試しでは再現しなかったが、起きないとは言えない。組版の並列が .emet の評価を同時に起こすかどうかも調べていない。これらの経路がこの不具合に当たるかどうかが決まっていない。
- **golem のコードを使わない、GHC の不具合の再現**：GHC の issue #28001 の症状を、golem のコードを使わずに再現するプログラムはまだない（[docs/adr/0207](adr/0207-run-golem-emet-test-one-test-at-a-time-under-the-watchdog.md)）。今ある最小の再現は、golem-emet と peg-runtime を要する。上流の切り分けに使える再現を作れるかどうかが決まっていない。
- **段落と `@no-page-break` のあいだの行アキ**：段落と `@no-page-break` のあいだに行アキ（`@blank-line`）があると、段落は後を待たず、最後の行を後と同じ段に置こうとしない（[golem-layout ADR 0022](golem-layout/adr/0022-no-page-break-counts-spaces.md)）。段落の前後の空きは飛ばして後を待つので、二つの扱いが違う。仕様書はこの場合を決めていない。行アキを挟んでも後を待つかと、待つなら行アキの行を後の量に足すかが決まっていない。
- **自ら送られる図版の前の行アキ**：段に入らない図版の直前に行アキがあると、改ページは、行アキと図版の和が入る段まで進む。一段で段の行の数が 4 の版面に、1 行の段落、1 行の行アキ、3 行の図版、2 行の段落を置くと、図版は 2 ページに置かれ、1 ページの 3 行が空く。行アキと図版は同じ段にあり、どの不変条件も破らないので、[golem-layout ADR 0026](golem-layout/adr/0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) は変えなかった。自ら送られる図版も待つ図版と同じに扱えば段の末尾の空きは減るが、行アキと図版のどちらが先に段を移るかという、別の規則を決めることになる。変えるかどうかが決まっていない。
- **行末に足すハイフンの伸縮**：`[composition]` の `expansion` で伸縮した行でも、行末に足すハイフンは伸縮しない比率 100 で描く（[golem-pdf ADR 0015](golem-pdf/adr/0015-scaled-glyph-run-restores-horizontal-scaling.md)）。ハイフンの字形は、伸縮した行の字より最大 2% 広い、または狭い。ハイフンを行の伸縮の率で描くかは、行分割がハイフンの幅を伸縮できる箱として数えるかを確かめて、別の ADR で決める。
- **`@need-lines` の後の見出しの並び**：改ページの Alloy のモデルのコマンド `needSpaceAllButGreedy` には、スコープ 4 で解がある。段の行の数が 4 で 2 行を使った段に、`@need-lines 2`、見出し、改丁の見出し、改丁の見出しが来ると、P7（`spaceKeeps`）は一つめの見出しをこの段に求め、`keepHeading21` は三つの見出しを同じ段に求め、3 行は残りの 2 行に入らない（[docs/golem-layout/models/README.md](golem-layout/models/README.md)、[ADR 0242](adr/0242-run-the-heavy-commands-of-the-alloy-models-every-night.md)）。モデルの `firstPart` が見出しの最初の部分を見出しの 1 行とし、一緒に置く見出しの並びを数えないことが、モデルの誤りか、P7 と見出しの規則が両立しない組かが決まっていない。実装が同じ入力で何をするかも確かめていない。決めたら、改ページの規則の ADR で、モデルか規則と `nightly.txt` を直す。
- **GUI と Golem のあいだの通信の取り決め（v3）**：GUI（「GUI の作り方」）と Golem の本体のあいだで、何をどう受け渡すか。今の LSP を広げるのか、別の取り決めを作るのかが決まっていない。
- **描画の内容を渡す API（v3）**：GUI の canvas に、グリフのアウトラインを座標付きで渡すのか、ページの画像を渡すのか、その両方か。見た目の回帰テストで PDF を画像にする shem（[ADR 0093](adr/0093-fetch-shem-pinned-by-version-and-sha256.md)）と共有できるかも含めて決まっていない。

## 課題にしなかった事項

ADR と仕様が扱わないと決めたもので、課題として残さないものをここにまとめる。
扱う必要が出てきた場合は、新しい ADR で決め直す。

- **macOS と Windows での CI、stack によるビルド**：決定性の検査は Linux の二つのアーキテクチャで足り、依存のバージョンは cabal と freeze ファイルで固定できるので採らない（[docs/adr/0001](adr/0001-haskell-workspace-and-ci.md)）。
- **Windows と Intel の CPU の macOS の実行ファイル**：Windows では、WSL の上で Linux の静的な実行ファイルを使えば足りる。Windows でそのまま動く実行ファイルは、CI、リンク、改行の扱い、`scripts/` の検査を Windows のために保守する費用に見合わず、担当する人が現れても貢献が続く保証はないので作らない。Intel の CPU の macOS は、次の macOS のバージョンで Rosetta が使えなくなるので、対応しない。どちらも v2 の「配布の拡張」から移した（[docs/adr/0004](adr/0004-binary-distribution-and-release.md)）。
- **異なるバージョンの Golem の間での出力の一致**：Golem のバージョンは入力の一部であり、バージョンが変われば出力が変わってよいので求めない（[docs/adr/0002](adr/0002-determinism.md)）。
- **決定性に反する処理の静的な検出**：決定性の規則はレビューとテストで守ると決めたので作らない（[docs/adr/0002](adr/0002-determinism.md)）。
- **リリースの運用の自動化**：リリースの自動公開、リリースで確かめる項目の自動化、監査の記録を仕組みで変更できなくすることは、公開を人が行い、確かめは繰り返しが重くなってから自動化を考え、記録は約束とレビューで守ると決めたので扱わない（[docs/adr/0004](adr/0004-binary-distribution-and-release.md)、[docs/adr/0008](adr/0008-first-release-verification.md)、[docs/adr/0011](adr/0011-update-adr-guard-to-v0.8.0.md)）。
- **キャッシュの復元が egress の上限で失敗すること**：`actions/cache` の復元が「Failed to restore: Egress is over the account limit.」の警告で外れになり、依存をビルドし直してジョブが 15 分ほど遅くなることがある（2026-11-04 の実行 41915724203）。頻度が低く、再試行も時間切れの変更も役に立たないので、ワークフローは変えず、外れとして扱う。同じ警告が 7 日のうちに二つ以上の実行で出たら、egress を減らす方法を決める ADR を書く（[docs/adr/0167](adr/0167-leave-cache-restore-failures-as-misses.md)）。
- **CI の高速化の候補**：大きいランナー、aarch64 の `build` の省略、HarfBuzz と FreeType の切り出しや翻訳単位の分割、GHC を含むコンテナは、費用、決定性の検査、効果の見込みの理由で採らないと決めた（[docs/adr/0009](adr/0009-ci-speed.md)）。古いキャッシュを消すジョブは、後に [docs/adr/0228](adr/0228-keep-the-ci-caches-under-the-10-gb-limit.md) が採った。
- **スタイルの仕組みで作らないもの**：組み込みのスタイルを消すことと名前を変えること、`style.toml` の自動の書き換え、組み込みの文字スタイル `emphasis`、段落スタイルの `hang` のキー、原稿の先頭の全角の空白の除去と警告は、ADR が作らないと決め、`hang` は負の `first-line-indent` で表せるので扱わない（[docs/adr/0005](adr/0005-character-and-paragraph-styles.md)、[docs/adr/0006](adr/0006-paragraph-indent.md)）。
- **合成の太字と斜体の設定**：線の幅を変える設定、フォントや文字の大きさごとの値、太った分だけ送りを広げること、OS/2 テーブルから書体を選ぶことは、品質が要る本では太字や斜体の書体を役割で指定すればよいので作らない（[golem-driver ADR 0004](golem-driver/adr/0004-pdf-emphasis-and-character-styles.md)、[golem-driver ADR 0012](golem-driver/adr/0012-synthetic-bold-weight.md)）。傾きを変える設定は、v2 の「文字の斜体の角度（skew）」に移した。
- **lint の規則の設定と抑制、表記の規則**：規則は処理系が固定し、合意の取れない表記の規則は外部の校正ツールに任せると決めたので持たない（[golem-lint ADR 0001](golem-lint/adr/0001-lint-rules.md)、[「lint」の節](specifications.md#lint)）。
- **生の CSS**：媒体契約の外で見た目を変える抜け道になるので設けない（[golem-html ADR 0001](golem-html/adr/0001-xhtml-serializer.md)、[「style.toml」の節](specifications.md#styletoml)）。
- **fmt の表の列揃え、本文の折り返し、整形の規則の設定**：整形の結果が環境によって揺れず、書き手の改行を変えないことを優先したので作らない（[golem-fmt ADR 0001](golem-fmt/adr/0001-formatter.md)）。
- **式の拡張**：条件式、繰り返し、文字列の演算子は、書籍の原稿の計算で要る場面が少ないので、必要が明らかになるまで加えない（[golem-eval ADR 0001](golem-eval/adr/0001-expression-language-and-numerics.md)、[golem-parser ADR 0004](golem-parser/adr/0004-inline-grammar.md)）。
- **フォントの難読化と Type 3 による埋め込み**：v1 の出力に要らないので、ADR が扱わないと決めた（[golem-font ADR 0002](golem-font/adr/0002-subsetting-and-embedding.md)、[golem-html ADR 0001](golem-html/adr/0001-xhtml-serializer.md)、[golem-epub ADR 0001](golem-epub/adr/0001-epub-packaging.md)）。
- **複雑な文字体系の検証**：Golem の対象を和文と欧文に限るので、アラビア文字やインド系の文字は確かめない（[golem-font ADR 0001](golem-font/adr/0001-shaping-and-metrics.md)）。
- **固定レイアウトの EPUB**：EPUB は幾何を持たないリフローの媒体として扱うので作らない（[golem-epub ADR 0001](golem-epub/adr/0001-epub-packaging.md)、[「設計原則」の節](specifications.md#設計原則)）。
- **ICC プロファイルによる Web の色変換**：画面の色は印刷の色の近似でよいと決めたので、差が問題になるまで扱わない（[golem-html ADR 0001](golem-html/adr/0001-xhtml-serializer.md)）。
- **musl の malloc の速度**：GHC のヒープは RTS が自前で管理して影響が限られるので、問題になるまで扱わない（[docs/adr/0004](adr/0004-binary-distribution-and-release.md)）。
- **utf-32 の交渉と、`lsp` パッケージを使わない LSP の実装**：UTF-16 で常に応えられ、`lsp` への細工は一か所に閉じ込められるので採らない（[golem-lsp ADR 0002](golem-lsp/adr/0002-utf8-position-encoding.md)）。
- **PDF のリンクのほかの注釈**：テキストの注釈（付箋）、ハイライト、フォームのフィールド、添付ファイルの注釈は作らない。v1.0.0 の「PDF のしおりとリンク」の「リンクのほかの注釈も扱う」は、元の v2 の項目の「注釈」を合わせたときに残った語で、使う場面が書かれておらず、LaTeX との差の調査にも InDesign の調べにも不足が挙がっていない。PDF/X-4 と PDF/A-2 の注釈の制約を照合する手間も増える（[docs/adr/0267](adr/0267-pdf-bookmarks-and-links-inside-the-document.md)）。
- **diagnostics と CLI の文言の多言語化**：v1 の diagnostics と使い方の文言は日本語だけと決めたので扱わない（[golem-syntax ADR 0001](golem-syntax/adr/0001-source-spans-and-diagnostics.md)、[golem-cli ADR 0004](golem-cli/adr/0004-usage-error-exit-code.md)）。
