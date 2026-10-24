# リファクタリングの調査（2026-10-25、rc4 の前）

この記録は、2026-10-25 の main（8a90425e、v0.1.0-rc3 のタグの直後）の Golem を、[ロードマップ](../roadmap.md)の rc4 の項目「リファクタリング」の入力として調べた結果である。
その項目は、モジュールの境界、重複した処理、大きくなった関数とテストの補助を見直し、出力を変えずに決定性の検査で確かめることを求めている。
この記録は、どこを直すかの候補を挙げ、分類し、順番をつける。
コードは変えていない。

ソースコードへのリンクは、すべて調べたコミット 8a90425e に固定した。
挙げた箇所は、どれもコードを読んで確かめたものである。
動かして確かめたのは、コードの行数と Git の履歴の数え上げだけで、重複の判定はコードの比較による。

## 調べ方

まず、各モジュールの大きなファイルと、v0.1.0-rc2（2026-10-16）から main までの 913 コミットで変更の多かったファイルを数えた。
rc2 からの変更の回数は、`modules/golem-driver/test/Main.hs` が 60 回、`modules/golem-driver/src/Golem/Driver/Pdf.hs` が 96 回、`Golem/Layout/Paginate.hs` が 22 回で、ほかの大半は 20 回未満である。
変更が集まるのは golem-driver の PDF の経路と、その試験である。

次に、ライブラリの名前の重なりを `rg` で引き、同名の関数の本体を並べて比べた。
テストの補助は、各パッケージの test/ を読み、同じ本体の関数と、同じ手順の書き写しを数えた。
使われていない export は、リポジトリ全体（modules、docs、manual、manual-dev、scripts）を検索して、定義と export の行以外に出てこないものだけを挙げた。

## 分類の基準

項目は三つに分ける。

- **(a)**：振る舞いを変えない機械的な整理。既存のテスト、ゴールデン、決定性の検査で確かめられる。
- **(b)**：ADR が要る。golem-\* のパッケージのあいだの build-depends（テストを含む）を変えるか、モジュールの境界か仕様を動かす。
- **(c)**：今はやらない。費用に見合わないか、やれない理由がある。

(a) の確かめ方は、どの項目でもおおむね同じである。
そのパッケージのテストと、golem-driver の `OutputGoldenSpec`（`test/golden/` の 4 つのダンプ）、そして `scripts/determinism.sh` の出力の一覧を変更の前後で取り、`diff` する。
決定性の検査は、CI では同じコミットの x86-64 と aarch64 の出力を比べるだけなので、コミットをまたいで出力が同じことは示さない（[2026-10-20 のロードマップのレビュー](2026-10-20-roadmap-review.md)）。
リファクタリングのプルリクエストでは、ベースのコミットの一覧を手元で作って比べる必要がある。
項目ごとに追加の確かめ方があるときだけ、下に書く。

## 一覧

| 番号 | 分類 | 優先 | 項目 | 場所 |
| --- | --- | --- | --- | --- |
| R1 | (a) | 高 | `Golem.Driver.Pdf`（3614 行）を flow と drawing の二つの節で分ける | golem-driver |
| R2 | (a) | 高 | `writeDocumentView`（698 行）の `let` の束を top-level に出す | golem-driver |
| R3 | (a) | 中 | `paginateWithin`（562 行）の `where` を状態の操作と判定に分ける | golem-layout |
| R4 | (b) | 中 | `Golem.Driver` の HTML/CSS の変換と CSL-JSON の読み込みの置き場 | golem-driver、golem-html、golem-doc |
| R5 | (a) | 高 | `splitLines`、`isLineBreak` が golem-html と golem-text で同一 | golem-doc に寄せる |
| R6 | (a) | 中 | `escapeXml` が golem-html と golem-pdf で同一 | golem-syntax に寄せる |
| R7 | (a) | 低 | `tshow` が 5 パッケージの top-level と 8 箇所の `where` にある | golem-syntax に寄せる |
| R8 | (a) | 高 | パッケージの中の同一関数（`nubOn`、`flate`、`mergeText`、`toBlocks` ほか） | golem-driver、golem-pdf、golem-parser、golem-fixtures |
| R9 | (a) | 中 | `codePointText` が golem-syntax にあるのに 2 箇所で書き直されている | golem-driver、golem-preflight |
| R10 | (a) | 中 | 小数の文字列化が 4 箇所で別々に実装されている | golem-pdf、golem-html、golem-driver |
| R11 | (c) | 低 | sp から mm への変換が 3 通りで、丸めが違う | golem-preflight、golem-driver、golem-project |
| R12 | (c) | 低 | `abiVersion` が golem-doc と golem-plugin で二重に定義されている | golem-doc、golem-plugin |
| R13 | (c) | 低 | `type Sp = Integer` が 6 箇所にある | 6 パッケージ |
| R14 | (b) | 中 | golem-pdf が `Rect` のためだけに golem-layout-spec に依存する | golem-pdf、golem-layout-spec |
| R15 | (a) | 中 | 使われていない export が 3 つある | golem-eval、golem-parser、golem-syntax |
| R16 | (a) | 低 | モジュールの外で使われない export が約 30 ある | 各パッケージ |
| R17 | (c) | 低 | ADR の中の古い関数名（`writeDocument`、`runningHeadText`） | docs/golem-driver/adr ほか |
| R18 | (a)/(b) | 高 | テストの `inParallel`（4 箇所）、`raceFactor`（2 箇所）、`withEnv`（2 箇所）が同一 | golem-font、golem-driver、golem-plugin、golem-lsp |
| R19 | (a) | 高 | golem-driver のテストの小さなプロジェクトを書く 4 行が 4 箇所、ファイルを書く 1 行が 31 箇所 | golem-driver/test |
| R20 | (a) | 中 | `tinyJpeg` の 776 行のリテラルが fixture の `tiny.jpg` と同じバイト列 | golem-pdf/test |
| R21 | (a) | 中 | golem-eval のテストの `ctx` が 4 モジュールで別々に組まれ、解析して評価する補助が 7 通りある | golem-eval/test |
| R22 | (a) | 低 | golem-layout と golem-layout-spec のテストの定数と補助の重複 | golem-layout/test、golem-layout-spec/test |
| R23 | (b) | 低 | パッケージをまたぐテストの fixture（manifest のリテラル、`sp`、`hex`、`genText`） | golem-test-support |

## 大きな関数とモジュール

### R1：`Golem.Driver.Pdf` を節で分ける（a、高）

[`Golem.Driver.Pdf`](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-driver/src/Golem/Driver/Pdf.hs) は 3614 行で、生成されたパーサーを除けばリポジトリで最大のモジュールである。
rc2 からの変更も 96 回で最多で、rc4 のプラグインの仕上げでも触ることになる。
ファイルの中には、すでに二つの節の区切りがある。
[649 行目の `flow`](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-driver/src/Golem/Driver/Pdf.hs#L649) と [2857 行目の `drawing`](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-driver/src/Golem/Driver/Pdf.hs#L2857) である。
その前の 1 行目から 648 行目は、フォントの役割と診断（`bodyRole`、`bodyFontDiagnostics`、`codeFontNotice`、`kentenRubyNotices` など）である。

切り方は、この三つの節をそのままモジュールにする。
`Golem.Driver.Pdf.Fonts`（役割と診断）、`Golem.Driver.Pdf.Flow`（`buildFlow`、`fixpoint`、`layoutPages`、ページ要素の配置）、`Golem.Driver.Pdf.Draw`（`writeDocumentView`、`renderPdf`）である。
`Golem.Driver.Pdf` は今の export の一覧を保って三つを再 export する。
これなら、golem-driver のテストと golem-lsp の import は変えずに済む。
export の一覧に 60 を超える名前が並ぶのは、テストが内部の関数を直接呼んでいるためで、分割の後に一覧を縮めるかどうかは別の判断になる。

確かめ方は、冒頭に書いた共通の手順である。
加えて、`Golem.Driver.Pdf` の export の一覧を分割の前後で `diff` し、名前の集合が同じことを見る。

### R2：`writeDocumentView` の `let` を top-level に出す（a、高）

[`writeDocumentView`](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-driver/src/Golem/Driver/Pdf.hs#L2907-L3605) は 698 行の一つの `let` 式である。
その中に `runAt`（2934 行目）、`drawLineAt`（3097 行目から 3215 行目）、`drawColumn`（3228 行目から 3337 行目）、`drawPage`（3338 行目）、表と罫線とコードの描画（3374 行目から 3497 行目）、`masterMarks`（3507 行目）が並ぶ。
ADR の文章がこの中の名前を指すこともある（`drawPage`、`runAt`、`figureRect`）。
`figureRect` はすでに top-level に出ているが、`drawPage` と `runAt` は局所である。

出し方は、`let` の束が共有する値（`inp`、`geom`、`fonts`、`layout`、`masters`、`heads`、`gridAt`）を一つのレコード（たとえば `DrawEnv`）にまとめ、`runAt`、`drawLineAt`、`drawColumn`、`drawPage` をそのレコードを受け取る top-level の関数にする。
一度に全部を出す必要はなく、`drawColumn` と `drawPage` から始めるのが安全である。
この二つは末尾に近く、ほかの局所の関数を呼ぶだけで、呼ばれることはない。

確かめ方は共通の手順に加え、`PdfSpec` と `PageElementsSpec` の全件である。
この二つは描画の結果を PDF のストリームから読んで比べるので、描画の順や座標が変われば落ちる。

### R3：`paginateWithin` の `where` を分ける（a、中）

[`paginateWithin`](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-layout/src/Golem/Layout/Paginate.hs#L355-L917) は 562 行で、`where` に約 60 の局所の定義を持つ。
中身は二種類に分かれる。
一つは状態 `st` を進める操作（`putLine`、`nextColumn`、`nextPage`、`closePage`、`startSet`、`placeTable`、`pageFigure`）、もう一つは状態を読むだけの判定（`free`、`isEmpty`、`fitting`、`roomForLine`、`needIn`、`joinsNext`、`planOf`）である。
判定のほうは、引数の `capacity` と `columns` を受け取れば top-level に出せる。
操作のほうは、状態の型にまとめて `Golem.Layout.Paginate.State` のようなモジュールに置ける。

この関数は、rc3 で罫線の結合（`placeRuled`、`planOf`、`flushJoin`）と表の分割（`placeTable`）が足されて大きくなった。
rc4 で注の配置や追い込みの設定を足すなら、その前に分けておくほうが差分を読みやすい。
確かめ方は共通の手順と `golem-layout` の `PaginateSpec`、そして golem-driver のゴールデンである。
ページ割りが変われば、ゴールデンのページ数と行の位置が変わる。

### R4：`Golem.Driver` の HTML/CSS の変換と CSL-JSON の読み込み（b、中）

[`Golem.Driver`](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-driver/src/Golem/Driver.hs)（1249 行）には、ほかのパッケージの主題に属する処理が二つある。

一つは、[1078 行目から 1249 行目](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-driver/src/Golem/Driver.hs#L1078-L1249)の `htmlCharStyles`、`htmlParaStyles`、`htmlRule`、`htmlFeatures`、`rubyAlignCss`、`cssLength`、`cssFontSize`、`decimal3`、`indexPage` である。
これらは `Style` を CSS の文字列と XHTML に写す。
golem-html が golem-project に依存していないので、`Style` を知るドライバが変換を引き受けている（[golem-html の cabal](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-html/golem-html.cabal#L23-L24)）。
golem-html に移すには golem-html が golem-project に依存することになり、ADR が要る。
もう一つの道は、ドライバに残したまま `Golem.Driver.Html` のモジュールに切り出すことで、こちらは (a) である。
境界を動かすかどうかを先に決め、動かさないなら切り出しだけを行う。

もう一つは、[550 行目から 655 行目](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-driver/src/Golem/Driver.hs#L550-L655)の `loadBibliography`、`cslEntry`、`cslYear` である。
CSL-JSON を aeson で読んで golem-doc の `CslEntry` に写す。
golem-doc が `CslEntry` と `formatEntry` を持つのに読み込みだけがドライバにあるのは、aeson が golem-driver、golem-lsp、golem-cli の依存にしかないからである。
golem-doc に aeson を足すのは golem-\* のあいだの依存ではないが、ライブラリの依存を増やすので、ADR で決めるほうがよい。

## ライブラリの重複

### R5：`splitLines` と `isLineBreak`（a、高）

[golem-html の 667 行目から 676 行目](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-html/src/Golem/Html.hs#L667-L676)と[golem-text の 188 行目から 197 行目](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-text/src/Golem/Text.hs#L188-L197)は、コメントまで同じである。
両方とも IR の `InlineF` を扱う関数で、両パッケージはすでに golem-doc に依存している。
golem-doc の `Golem.Doc.IR` に置けば、依存を変えずに一つになる。

### R6：`escapeXml`（a、中）

[golem-html の 218 行目から 224 行目](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-html/src/Golem/Html.hs#L218-L224)と[golem-pdf の X4 の 41 行目から 42 行目](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-pdf/src/Golem/Pdf/X4.hs#L41-L42)は、同じ 4 文字を同じ実体参照に写す。
golem-epub は golem-html のものを使う。
二つのパッケージが共に依存するのは golem-syntax だけなので、置き場は golem-syntax になる。
golem-syntax はすでに `Sha256` を「golem-pdf と golem-plugin が共有するため」に抱えている（[Golem.Pdf.Sha256 のコメント](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-pdf/src/Golem/Pdf/Sha256.hs#L1)）ので、前例はある。
ただし、golem-syntax が小道具の置き場になっていくことには注意が要る。
R7 と R9 と合わせて、`Golem.Syntax.Text` のような一つのモジュールにまとめるなら、散らばりは防げる。

### R7：`tshow`（a、低）

`tshow = T.pack . show` が golem-doc、golem-html、golem-pdf、golem-preflight、golem-syntax の top-level にあり、golem-driver、golem-eval、golem-fixtures の `where` にも 8 箇所ある。
golem-syntax の [`Render.hs` の 166 行目](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-syntax/src/Golem/Syntax/Render.hs#L166-L167)だけは `Int -> Text` に型が狭い。
害はないが、R6 と同じ置き場ができるなら、そこに一つ置いて他を消すのは機械的である。
単独でやる価値は低い。

### R8：パッケージの中の同一関数（a、高）

同じパッケージの中に同じ関数が二つある箇所は、依存を変えずに消せる。

- `nubOn`：[Driver/Pdf.hs の 1560 行目](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-driver/src/Golem/Driver/Pdf.hs#L1560)と [Driver/Fonts.hs の 91 行目](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-driver/src/Golem/Driver/Fonts.hs#L91)。`foldl` と `foldl'` の違いだけで、どちらも `elem` を使う二乗の時間の実装である。golem-pdf の `Import.hs` は containers の `nubOrdOn` を使っている。`nubOrdOn` に置き換えると結果の順は同じで（最初の出現を残す）、`Ord` の制約が増えるだけである。
- `flate`：[Import.hs の 1377 行目](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-pdf/src/Golem/Pdf/Import.hs#L1377-L1378)と [Writer.hs の 293 行目](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L293-L294)が同一。Writer は Import をすでに import している。圧縮のレベルが出力のバイト列を決めるので、一つにしておく価値は高い。
- `mergeText` と `joinText`：[Parser/Lower.hs の 252 行目](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-parser/src/Golem/Parser/Lower.hs#L252-L256)と [Parser/AST.hs の 150 行目](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-parser/src/Golem/Parser/AST.hs#L150-L154)。`joinText` が export されていないので Lower が書き直した。
- golem-fixtures の `Gutenberg.hs` と `GutenbergText.hs`：[`toBlocks`](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-fixtures/src/Golem/Fixtures/Gutenberg.hs#L39-L45) と [`GutenbergText` の同名の関数](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-fixtures/src/Golem/Fixtures/GutenbergText.hs#L77-L83)、`indentOf`、`escapeSlot` が同一。両方が import する `Golem.Fixtures.Python` に置ける。fixture の生成器なので、fixture の `.gm` を再生成して `diff` が空なことで確かめる。
- `isSpaceTab`：golem-fmt、golem-eval、golem-parser の 3 箇所。パッケージをまたぐので R6 の置き場に入れる。

### R9：`codePointText` の書き直し（a、中）

golem-syntax は [`codePointText`](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-syntax/src/Golem/Syntax/Chars.hs#L34-L37) を export しているが、[Driver/Pdf.hs の 405 行目](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-driver/src/Golem/Driver/Pdf.hs#L405)と [Preflight.hs の 155 行目](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-preflight/src/Golem/Preflight.hs#L155)が同じ式を書き直している。
両パッケージは golem-syntax に依存している。
`U+` の有無だけが違うので、置き換えは文字列の連結の位置を見るだけで済む。
診断のメッセージに出る文字列なので、確かめ方は `DiagnosticsSpec` と golem-preflight のテストである。

### R10：小数の文字列化（a、中）

有理数を小数の文字列にする関数が 4 箇所にある。
golem-pdf の [`showDecimal4` と `showRationalDigits`](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-pdf/src/Golem/Pdf/Number.hs#L22-L57)、golem-html の [`akiLength` の局所の `decimal`](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-html/src/Golem/Html.hs#L655-L664)、golem-driver の [`decimal3`](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-driver/src/Golem/Driver.hs#L1211-L1217) である。
`showDecimal4` は `showRationalDigits 4` と同じ結果を返すので、golem-pdf の中だけでも一つにできる。
golem-html と golem-driver のものは、桁数（4 と 3）が違うだけで、丸めは `round`（半分は偶数へ）で同じである。
桁数の違いは、同じスタイルシートの中で CSS の長さが 3 桁と 4 桁で混ざるという意味で不揃いだが、揃えると HTML の出力が変わる。
出力を変えないリファクタリングの範囲では、関数を一つにして桁数を引数で渡すところまでにとどめる。
桁数を揃えるのは、見た目の回帰テストが入ってから別に判断する。

### R11：sp から mm への変換（c、低）

[Preflight の `mmText`](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-preflight/src/Golem/Preflight.hs#L93-L97)、[Driver/Pdf.hs の局所の `mm`](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-driver/src/Golem/Driver/Pdf.hs#L2228)、[Style.hs の `spToMm` と `mm2`](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-project/src/Golem/Project/Style.hs#L874-L880) の 3 つは、桁数と丸めが違う。
前の二つは 1 桁で半分を偶数へ、`mm2` は 2 桁で半分を切り上げる。
`mm` は負の値の符号を扱わず、`mmText` は扱う。
どれも診断のメッセージに出る文字列で、一つにすると文字列が変わる診断が出る。
診断も決定性の対象なので（[仕様書の設計原則](../specifications.md)）、これは出力を変える変更であり、今回の範囲では扱わない。
揃えるなら「一つのコードに一つの原因」の監査と合わせて ADR で決める。

### R12：`abiVersion` の二重定義（c、低）

[golem-doc の `Int`](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-doc/src/Golem/Doc/IR.hs#L62-L63) と [golem-plugin の `Word32`](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-plugin/src/Golem/Plugin.hs#L72-L73) が同じ値 7 を別の型で持ち、golem-plugin は `Golem.Doc.IR hiding (abiVersion)` で片方を隠している。
一致はテストと `scripts/ci/abi-version.sh` が守っている。
rc4 のプラグインの作業で ABI が変わる（ロードマップの「数を有理数に寄せる」）ので、そのときに一つにするほうがよい。
今はやらない。

### R13：`type Sp = Integer` の 6 箇所（c、低）

golem-project、golem-layout（3 モジュール）、golem-driver、golem-pdf にそれぞれ別名がある。
型の別名は同じ `Integer` に解けるので、コンパイルも意味も変わらない。
一つにするには、どのパッケージも依存する golem-syntax に置くか、golem-pdf が golem-project を直接依存に加える必要があり、後者は ADR が要る。
別名を 6 箇所で宣言する費用は小さく、今はやらない。

### R14：golem-pdf の `Rect` のための依存（b、中）

golem-pdf は [Writer](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L48)、[Marks](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-pdf/src/Golem/Pdf/Marks.hs#L18)、[X4](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-pdf/src/Golem/Pdf/X4.hs#L21) で `Golem.LayoutSpec (Rect (..))` だけを import する。
golem-layout-spec は golem-project に、golem-project は golem-doc、golem-parser、golem-regex に依存するので、PDF の書き出しが矩形の型のためだけにパーサーまで引き込んでいる。
`Rect` を golem-pdf か golem-syntax に移して golem-layout-spec が再 export するか、golem-pdf が自分の矩形を持つかは、依存の向きを変えるので ADR で決める。
ビルドの時間と、golem-pdf を単独で使えるかに関わる。

## 使われていないコードと古い記述

### R15：使われていない export（a、中）

リポジトリ全体で定義と export の行以外に現れないものが 3 つある。

- [`Golem.Eval.Expr.emptyEnv`](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-eval/src/Golem/Eval/Expr.hs#L36-L37)
- [`Golem.Parser.CST.isTriviaKind`](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-parser/src/Golem/Parser/CST.hs#L117-L118)
- [`Golem.Syntax.Span.lookupFileId`](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-syntax/src/Golem/Syntax/Span.hs#L78-L79)

消しても何も壊れない。
確かめ方は全パッケージのビルドである。

### R16：モジュールの外で使われない export（a、低）

export されているが自分のモジュールの中でしか使われない名前が、golem-project の `Style.hs`（`builtinAkiSetNames`、`codeParaKeys`、`validStyleName` など 9 つ）を中心に約 30 ある。
export を外すと GHC の `-Wall`（各 cabal の `ghc-options`）の未使用の警告が効くようになり、以後の不要なコードが見つかる。
ただし、テストが内部を直接呼ぶために export している名前と区別する必要があり、一つずつ `rg` で確かめる。
R1 で `Golem.Driver.Pdf` の export を見直すときに、同じ手順で進めるのがよい。

### R17：ADR の中の古い関数名（c）

`writeDocument` は `writeDocumentView` に名前が変わったが、golem-driver の 13 本（[golem-driver ADR 0003](../golem-driver/adr/0003-pdf-heading-styles.md) から [golem-driver ADR 0022](../golem-driver/adr/0022-running-head-formats.md) まで）、golem-pdf の 2 本（[golem-pdf ADR 0004](../golem-pdf/adr/0004-crop-marks-and-bleed.md)、[golem-pdf ADR 0005](../golem-pdf/adr/0005-producer.md)）、横断の 2 本（[docs/adr/0005](../adr/0005-character-and-paragraph-styles.md)、[docs/adr/0018](../adr/0018-multi-column-layout.md)）が古い名前で指している。
`runningHeadText` も src にはなく、[golem-driver ADR 0014](../golem-driver/adr/0014-running-heads.md) と [golem-html ADR 0002](../golem-html/adr/0002-heading-number-spacing.md) に残る。
コミット済みの ADR はステータスの行を除いて変更できないので、直せない。
ADR は書いた時点の記録として読み、コードの名前は現在のものを当てる。
今後の ADR で局所の関数名を指すときは、R2 で top-level に出した名前を使えば、こうしたずれは減る。

## テストの補助

テストの補助の重複は、ライブラリより多い。
メンテナーの方針は、golem-\* の依存を足すより重複を許すことである（`raceFactor` はこの方針で意図して二つある）。
以下は、その方針の中で消せる重複と、方針の判断が要る重複を分けて挙げる。

### R18：`inParallel`、`raceFactor`、`withEnv`（a と b、高）

[`inParallel`](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-font/test/ConcurrencySpec.hs#L47-L58) は golem-font（`ConcurrencySpec` と `race/Main.hs`）、[golem-driver](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-driver/test/ParallelSpec.hs#L54-L65)、[golem-plugin](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-plugin/test/ConcurrencySpec.hs#L31-L42) の 4 箇所で本体が同一である。
`raceFactor` は golem-font と golem-driver の 2 箇所、`withEnv` は golem-driver の `Support.hs` と golem-lsp の `Main.hs` の 2 箇所で同一である。

golem-driver と golem-plugin の試験は golem-test-support にすでに依存しているので、`inParallel` と `raceFactor` を golem-test-support に置いてこの二つが使うのは、build-depends を変えない (a) である。
golem-font の試験は golem-test-support に依存していない（[cabal](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-font/golem-font.cabal)）ので、golem-font の分を消すには依存を足すことになり、ADR が要る。
golem-lsp の試験も同じく依存していないので、`withEnv` の統合も ADR が要る。
`raceFactor` が 2 つなのは方針どおりだが、`inParallel` が 4 つになったのは方針の境を越えている。
golem-test-support を導入した [docs/adr/0028](../adr/0028-shared-test-support-package.md) の方針で、どの試験が依存してよいかを一度決めるのがよい。

### R19：golem-driver のテストのプロジェクトの書き出し（a、高）

golem-driver のテストは、小さなプロジェクトを一時ディレクトリに書く 4 行を [`Support.buildMiniErrors`](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-driver/test/Support.hs#L185-L189)、[`PdfSpec.buildAllWith`](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-driver/test/PdfSpec.hs#L1024-L1028)、[`CliSpec.withPreflightProject`](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-driver/test/CliSpec.hs#L156-L160)、`FigureSpec.buildIn` に持つ。
ファイルを一つ書く行 `createDirectoryIfMissing True (takeDirectory (tmp </> to)) >> BS.writeFile (tmp </> to) bytes` は、golem-driver のテストに 31 回ある。
`Support.hs` に `writeProject :: FilePath -> ByteString -> ByteString -> Text -> [(FilePath, ByteString)] -> IO ()` を一つ置けば、4 箇所の 4 行と 31 行の多くが消える。
`PdfSpec.codeOf` は `Support.ofCode` の引数の順を入れ替えただけで、`PdfSpec.notoFonts` と `ParallelSpec.notoFonts` も同一である。
`Support.hs` は 730 行で export の一覧がなく、同じモジュールの中にあるものを別の名前で書き直している箇所が見つけにくい。
rc2 からの変更が最多の `test/Main.hs` と合わせ、golem-driver のテストはこの調査で最も費用対効果の高い整理の対象である。
確かめ方はテストの件数と結果が変わらないことで、`--list` の出力を前後で `diff` する。

### R20：`tinyJpeg` のリテラル（a、中）

[golem-pdf の `test/Main.hs` の 64 行目から 845 行目](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-pdf/test/Main.hs#L64-L845)は、776 バイトの JPEG を 1 バイト 1 行で書いたリテラルで、`test/fixtures/tiny.jpg`（776 バイト）と同じ内容である。
golem-driver と golem-cli のテストはこのファイルを読んでいる。
golem-pdf のテストもファイルを読めば、1409 行のファイルが約 630 行になる。
確かめ方は、リテラルとファイルの SHA-256 が同じことと、テストの結果である。

### R21：golem-eval のテストの `ctx` と評価の補助（a、中）

`EvalContext` の 15 のフィールドを埋める `ctx` が [`FileSpec`](https://github.com/tett23/golem/blob/8a90425e5e8119776ec0969b57bf3f9638c4f861/modules/golem-eval/test/FileSpec.hs#L27-L66)、`DiagnosticSitesSpec`、`DeferredSpec`、`TableSpec` の 4 モジュールにあり、それぞれ違うフィールドを埋めている。
「`parseAst (FileId 1)` してから `evalFile`」の補助は `FileSpec` の中だけで `run`、`diagsWith`、`runS`、`blocksIn` と局所の 3 つの、合わせて 7 通りある。
`ctx` は一つの既定値と、それを更新する記法に置き換えられる。
評価の補助は、結果のどの部分を取るかの違いなので、一つの関数と射影に分けられる。
確かめ方はテストの件数と結果である。

### R22：golem-layout と golem-layout-spec のテストの定数（a、低）

golem-layout のテストでは `fs = 10 * 65536` が 6 モジュール、`look0` が 3 モジュール、`compose` が 4 通りある。
`Main.hs` には `mkSpan (FileId 0) 0 0` が 11 箇所で直書きされ、`where` で `sp` を 6 回結び直している。
golem-layout-spec のテストでは `pt`、`grid`、`geom` が `Main.hs` と `GeometrySpec.hs` で同一で、後者のコメントが前者を参照している。
どれも一つのパッケージの中なので、テストの共通モジュールを一つ足せば消える。
件数が多いので機械的な置き換えになり、価値は低いが安全である。

### R23：パッケージをまたぐテストの fixture（b、低）

manifest の `urn:uuid:11111111-...` のリテラルは golem-cli、golem-lsp、golem-driver の 14 箇所、`sp`（`FileId 0` の 1 文字の範囲）は 6 パッケージ、`hex` は golem-pdf と golem-syntax、`genText` は golem-lsp と golem-syntax にある。
これらを一つにするには、今は golem-test-support に依存していない試験（golem-cli、golem-lsp、golem-syntax、golem-layout など）が依存を足すことになる。
golem-test-support は base と tasty にしか依存しないので、`Diagnostic` や `SrcSpan` を扱う補助は置けない。
置くなら golem-test-support が golem-syntax に依存することになり、これも ADR の範囲である。
R18 で依存の方針を決めるまで、重複のまま置く。

## 優先する項目

rc4 のプラグインの作業に先立つなら、次の順がよい。

1. **R19 と R18 の (a) の部分**：golem-driver のテストの補助を `Support.hs` にまとめ、`inParallel` と `raceFactor` を golem-driver と golem-plugin で golem-test-support から使う。変更が最も多いファイルの差分が小さくなる。ライブラリに触らないので、出力に関わらない。
2. **R1 と R2**：`Golem.Driver.Pdf` を三つに分け、`writeDocumentView` の `drawColumn` と `drawPage` を top-level に出す。export の一覧を保てば、他のパッケージの変更は要らない。
3. **R8 と R5**：パッケージの中と golem-doc への寄せで消せる同一関数。`flate` と `nubOn` は出力に関わるので、ゴールデンで確かめる価値がある。
4. **R15 と R9**：使われていない export の削除と `codePointText` の置き換え。小さく、半日で終わる。
5. **R3**：`paginateWithin` の分割。注と追い込みの設定を rc4 以降で足す前に済ませる。

ADR が要る項目（R4、R14、R18 の golem-font と golem-lsp の部分、R23）は、一つの ADR で「試験が golem-test-support に依存してよい条件」と「golem-test-support が golem-syntax に依存してよいか」を決めれば、R18 と R23 がまとめて動く。
R4 と R14 はライブラリの境界なので、別の ADR になる。

やらない項目（R11、R12、R13、R17）は、出力か診断が変わるか、変更できない文書か、費用に見合わない。
R11 と R12 は、rc4 の ABI の変更と「一つのコードに一つの原因」の監査のときに拾う。

## 参考文献

- [docs/roadmap.md](../roadmap.md) の rc4 の「リファクタリング」と「見た目の回帰テスト」
- [docs/adr/0028](../adr/0028-shared-test-support-package.md) golem-test-support の導入
- [2026-10-20 のロードマップのレビュー](2026-10-20-roadmap-review.md) 決定性の検査がコミットをまたがないこと
- `scripts/determinism.sh`、`modules/golem-driver/test/OutputGoldenSpec.hs`
