# 用語集

Golem の仕様書、言語仕様、ADR で使う用語をまとめる。
説明は要約であり、規則の本体は各項目に添えた文書にある。
組版の一般的な用語は、Golem の中で使う意味に絞って説明する。

## 全体の原則

- **決定性**：同じ入力から、バイト単位で同じ出力を生成する性質。時計、乱数、環境変数、実行する機械に結果を左右させない。Golem のほかのあらゆる設計判断に優先する（[仕様書](specifications.md)、[ADR docs/adr/0002](adr/0002-determinism.md)）。
- **媒体契約**：PDF、EPUB、HTML、プレーンテキストのあいだで固定する不変条件。意味内容は全媒体で同一とし、提示と、ページに由来する派生物（ページ番号、柱、脚注の配置、相互参照の実現形）だけを媒体ごとに分ける（[仕様書](specifications.md)）。
- **幾何の隔離**：意味論 IR に位置や大きさの情報を持たせず、幾何はレイアウトの側に閉じ込める原則。リフローする EPUB と HTML を壊さないためである（[仕様書](specifications.md)）。
- **広い型、狭い実装**：型は将来の表現力まで見越して設計し、実装は当面の用途に絞り、使わない機能は縮退させる方針（[仕様書](specifications.md)）。
- **構文解釈の安定**：構文の解析がコマンドの定義に依存しない性質。プラグインを加えても、既存の原稿の解析結果は変わらない（[仕様書](specifications.md)、[markup.md](markup.md)）。
- **ADR**：設計の決定を一件ずつ記録する文書（Architecture Decision Record）。連番のファイルとして `docs/adr/` と `docs/<モジュール>/adr/` に置き、コミットした後はステータスの行を除いて変更しない。
- **adr-guard**：コミット済みの ADR と記録（`docs/audit/`、`docs/audits/`、`docs/benchmarks/`、`docs/benchmark/`）の変更を拒み、ADR がステータスの行をちょうど一つ持つことを確かめる検査。Git の pre-commit フックと CI の `adr` ジョブで動く（[README](../README.md)）。

## 原稿の記法

- **プロジェクト**：マニフェスト（`manifest.toml`）を置いたディレクトリを根とする、原稿、スタイル、図版、フォントの集まり。章の順、メタデータ、ターゲットごとの設定はマニフェストに書く（[仕様書](specifications.md)、[golem-project ADR 0001](golem-project/adr/0001-manifest-and-import-graph.md)）。
- **ブロック**：段落、見出し、リスト、定義リスト、表、コードブロック、ブロックコマンドのように、行を単位とする原稿の構成要素。種類は行頭の文字で決まる（[markup.md](markup.md)）。
- **ブロックコマンド**：行頭の `@` で始まる命令。`@figure`、`@toc`、`@import` などがある。
- **属性**：ブロックの直前の行に書くブロックコマンドで、次のブロックに付く指定。`@label`、`@nonumber`、`@notoc` などがある（[markup.md](markup.md)）。
- **インラインの要素**：段落の中に `[` で始めて書く要素。`[` の直後の一文字で、式文脈か命令文脈かが決まる。
- **式文脈**：`[= ...]` の中。式の言語で値を計算し、その結果を本文に埋め込む（[markup.md](markup.md)、[golem-eval ADR 0001](golem-eval/adr/0001-expression-language-and-numerics.md)）。
- **命令文脈**：`[name ...]` の中。コマンドの名前、引数、散文スロットを書く（[markup.md](markup.md)）。
- **段落の区切り方**：原稿の段落を何で区切るか。空行で区切り、段落の中の改行が文字を生まない空行の様式（既定）と、改行ひとつで区切る改行の様式の二つがある。マニフェストの `[source]` の `paragraph-separator` で選び、章の項目ごとにも変えられる（[markup.md](markup.md)、[docs/adr/0013](adr/0013-paragraph-separator.md)）。
- **強制改行**：段落を分けずに行を改めること。行末の `\` で書く。強制改行の後の行には、一行目の字下げを掛けない（[markup.md](markup.md)、[docs/adr/0016](adr/0016-hard-line-breaks.md)）。
- **韻文**：組み込みの段落スタイル `verse` を `@style verse` で付けた段落。段落の中の改行が行の区切りになり、段落の一つが一つの連になる（[markup.md](markup.md)、[docs/adr/0003](adr/0003-verse-line-breaks.md)、[docs/adr/0005](adr/0005-character-and-paragraph-styles.md)）。
- **文字スタイル**：文字の見た目（書体、大きさ、色、合成の太字と斜体）に名前を付けたもの。`style.toml` の `[character-styles.<名前>]` に定義し、ファイルの先頭の `@style-def character` でもそのファイルにだけ効く文字スタイルを定義できる。原稿では `[style 名前: ...]` で付ける。`[strong: ...]`、`[bold: ...]`、`[italic: ...]` は組み込みの文字スタイルの別名である。`based-on` で別の文字スタイルを引き継ぐ（[markup.md](markup.md)、[docs/adr/0005](adr/0005-character-and-paragraph-styles.md)）。
- **段落スタイル**：段落の見た目（書体、大きさ、改行の扱い、同じスタイルの段落の間の空き）に名前を付けたもの。`style.toml` の `[paragraph-styles.<名前>]` に定義し、ファイルの先頭の `@style-def paragraph` でもそのファイルにだけ効く段落スタイルを定義できる。原稿では `@style 名前` で付ける。段落スタイルを付けない段落は `body` で組む（[markup.md](markup.md)、[docs/adr/0005](adr/0005-character-and-paragraph-styles.md)）。
- **ファイルの設定**：ファイルの先頭に並べた `@manifest` と `@style-def` の行。`@manifest` はマニフェストの `[source]` のキーを、`@style-def` は文字スタイルと段落スタイルを、そのファイルについてだけ上書きか定義する（[markup.md](markup.md)、[docs/adr/0014](adr/0014-in-file-settings.md)）。
- **散文スロット**：命令文脈の `:` の後に書く本文の欄。`|` で区切って複数書ける。`[ruby: 漢字|かんじ]` の「漢字」と「かんじ」がそれぞれ散文スロットである。
- **エスケープ**：特別な意味を持つ文字を本文の文字として書くための `\`。`\` が唯一のエスケープ文字である。
- **校正用のコメント**：`%%=` で始まるコメント。dev のプロファイルでだけ出力に現れ、prod のプロファイルで残っていると警告になる（[仕様書](specifications.md)）。
- **プロファイル**：ビルドの用途を表す dev と prod の二つ。dev は書きかけの原稿のために一部の検査を警告にとどめ、prod は出荷する本のためにエラーにする。

## 評価と文書構造

- **CST**：原稿を、空白とコメントまで含めて失わずに表す具象構文木（Concrete Syntax Tree）。元のテキストを一字一句復元でき、整形と LSP が使う（[golem-parser ADR 0001](golem-parser/adr/0001-cst-types-and-invariants.md)）。
- **AST**：CST から空白とコメントを取り除き、意味だけを残した抽象構文木。エスケープした文字は印を付けて残し、評価が地の文に戻す。評価器は AST だけを読む（[golem-parser ADR 0005](golem-parser/adr/0005-cst-to-ast.md)、[golem-parser ADR 0010](golem-parser/adr/0010-ruby-slash-escape-and-table-cell-breaks.md)）。
- **意味論 IR**：評価が済んだ文書の表現。幾何を持たず、全媒体の出力がここから分かれる。正典は CDDL で書いたスキーマであり、CBOR で直列化する（[golem-doc ADR 0001](golem-doc/adr/0001-semantic-ir-in-cddl.md)）。
- **評価の段階（S0、S1、S2）**：値がいつ決まるかによる三つの段階。**S0** はファイルの中だけで決まる値（変数、import した定義、見出しの文字列）、**S1** は全ファイルから決まる文書構造（目次、章番号、ラベルの章題と番号）、**S2** はレイアウトの後に決まる値（ページ番号）である（[仕様書](specifications.md)、[golem-eval ADR 0002](golem-eval/adr/0002-file-evaluation.md)）。
- **DeferredExpr**：S1 で初めて値が決まる式（`doc` 名前空間を参照する式）を、意味論 IR の中に評価を遅らせて保持したもの（[golem-eval ADR 0002](golem-eval/adr/0002-file-evaluation.md)）。
- **チャネル**：文書の各所から項目を集め、別の位置に一覧として出す仕組み。目次、脚注、索引、参考文献がこの形をとる（[仕様書](specifications.md)）。
- **ラベル**：`@label` でブロックに付ける名前。相互参照（章番号、章題、ページ番号）の参照先になる。

## 組版

- **版面**：ページの中で本文を組む領域。文字の大きさ、一行の字数、行数、行送り、段数で決め、余白はその位置から従属的に決まる（[仕様書](specifications.md)、[golem-layout-spec ADR 0001](golem-layout-spec/adr/0001-page-geometry.md)）。
- **ノド**と**小口**：ページの綴じる側の端と、その反対側の端。右綴じの本では奇数ページのノドが右にある（[golem-layout-spec ADR 0002](golem-layout-spec/adr/0002-gutter-side-of-odd-pages.md)）。
- **天**と**地**：ページの上端と下端。版面の位置は天とノドからの距離で決める。
- **柱**と**ノンブル**：ページの余白に置く章題などの見出しと、ページ番号。マスターページで位置と内容を決める。柱の内容は、マスターページの `running-head` の `content`（または `even` と `odd`）に、`heading.1.short` や `title` のような値で書く（[golem-driver ADR 0014](golem-driver/adr/0014-running-heads.md)）。
- **マスターページ**：柱とノンブルの位置と内容をまとめた、ページの雛形。`style.toml` の `[masters]` に書く。柱の内容は `running-head` の `content`（または `even` と `odd`）で決める。章のファイルごとにマニフェストの `master` で選び、指定のないファイルは `body` を使う（[golem-driver ADR 0014](golem-driver/adr/0014-running-heads.md)）。
- **行の格子**：版面の中で各行を置く位置の並び（ベースライングリッド）。見開きの左右のページで行の位置がそろう。
- **sp**：Golem が内部で使う長さの単位。1pt の 65536 分の 1 であり、すべての寸法を整数で扱うためにある。`style.toml` では mm、pt、Q（級）、H（歯）、zw（全角一字分）で書き、読み込むときに sp へ変換する。
- **Knuth-Plass の行分割**：段落全体を見て、行の詰まり具合の悪さ（不良度）と罰点の合計が最小になる改行の位置を選ぶ方法。行ごとに目標の行長（L*(i)）を変えられる（[golem-layout ADR 0001](golem-layout/adr/0001-knuth-plass-line-breaking.md)）。
- **禁則**：行頭や行末に置いてはいけない文字を、その位置に来させない規則。閉じ括弧や句読点は行頭に置かない（[golem-layout ADR 0002](golem-layout/adr/0002-japanese-composition.md)）。
- **約物**：句読点、括弧、中点などの記号。和文では字面の外側に空きを持ち、隣り合うと空きを詰める。
- **和欧間**：和文と欧文の文字が隣り合う位置。既定では四分の空きを置き、量はアキ量のセットで変えられる（[docs/adr/0019](adr/0019-aki-settings.md)）。
- **アキ**と**アキ量のセット**：文字と文字の間の空きと、その量を文字のクラスの組ごとに最小、最適、最大で決めた設定。InDesign の文字組みアキ量設定に当たる。`style.toml` の `[aki-sets.<名前>]` で定義し、段落スタイルの `aki-set` で選ぶ。組み込みのセットは `gyomatsu-yakumono-hankaku`（行末約物半角、既定）と `gyomatsu-yakumono-zenkaku`（行末約物全角）である。量は全角、二分、四分、五分などの名前、`zw`、百分率で書く。原稿の任意の位置には `[aki 五分]` のように固定の空きを置ける（[docs/adr/0019](adr/0019-aki-settings.md)）。
- **ぶら下げ組**：行末の句読点を版面の外に出すことを許す組み方。
- **カーニング**：隣り合う二字のあいだの空きを、字の組ごとに詰めたり広げたりすること。Golem はフォントの持つペアカーニングの情報を使う方式（メトリクス）を既定とし、欧文だけにかける方式（和文等幅、`japanese-equal-width`）と、かけない方式（`none`）を文字スタイルと段落スタイルの `kerning` で選べる。和文のペアカーニングは約物を含む組にはかけない（[docs/adr/0020](adr/0020-indesign-character-features.md)）。分離禁止文字（二倍ダッシュの `—`、三点リーダーの `…` など）を含む組にもかけない（[golem-driver ADR 0020](golem-driver/adr/0020-glyph-positioning-and-dash-kerning.md)）。
- **トラッキング**：文字ごとに一定の空きを足して、字間をそろえて広げたり詰めたりすること。文字スタイルと段落スタイルの `tracking` で、文字の大きさの 1/1000 を単位に指定する。PDF では行の最後の文字の後ろには足さない（[docs/adr/0020](adr/0020-indesign-character-features.md)）。
- **プロポーショナルメトリクス**：和文の字を、全角の送りではなく字面に合わせた送りで組むこと。OpenType の `palt`（縦組みでは `vpal`）を使い、文字スタイルと段落スタイルの `proportional-metrics` で指定する（[docs/adr/0020](adr/0020-indesign-character-features.md)）。
- **ベースラインシフト**：文字を、行分割と行送りを変えずに、横組みでは上へ、縦組みでは右へずらすこと。文字スタイルと段落スタイルの `baseline-shift` で指定する（[docs/adr/0020](adr/0020-indesign-character-features.md)）。
- **字下げ**：段落の行の始まりを下げること。段落スタイルの `indent`（すべての行）と `first-line-indent`（最初の行に加える量。負なら二行目以降が下がるぶら下げになる）で指定し、横組みでも縦組みでも行の始まりの側から測る（[docs/adr/0006](adr/0006-paragraph-indent.md)）。リストの項目は段落スタイルの字下げを受けず、PDF では印の幅だけ本文を下げて印をぶら下げ、入れ子のリストは外の項目の本文の始まりから下げる（[golem-driver ADR 0013](golem-driver/adr/0013-list-indents.md)）。
- **正規表現スタイル**：段落スタイルの中の、正規表現と文字スタイルの組の並び。段落の中で正規表現に一致した文字に、組の文字スタイルを当てる。InDesign の正規表現スタイル（英語版の GREP スタイル）に当たる（[docs/adr/0015](adr/0015-regex-styles.md)）。
- **ルビ**：親文字の傍らに小さく添える読み。親文字一字ごとに振る**モノルビ**と、語の全体に振る**グループルビ**がある（[markup.md](markup.md)）。熟語の各字にモノルビとして振り、熟語の中では隣の親文字の空いている場所にかけることを許すものを**熟語ルビ**という。ルビが親文字より短いとき、ルビを親文字の中央に置くことを**中付き**、親文字の始まりの側（縦組みでは上、横組みでは左）にそろえて置くことを**肩付き**という。ルビが親文字より長いとき、はみ出す部分を隣の文字の上（縦組みでは右）に置くことを**ルビのかけ**という（[golem-layout ADR 0009](golem-layout/adr/0009-ruby-placement.md)）。
- **圏点**：強調のために親文字の傍らに打つ点。形（ゴマなど）は `style.toml` の既定か引数で決める。
- **縦中横**：縦組みの中で、短い文字列を横向きのまま一字分の幅に組むこと。
- **縦組みの向き（Vertical_Orientation）**：Unicode の UAX #50 が文字ごとに定める、縦組みでの文字の向き。正立（U）、回転（R）、縦書き用の字形があれば使い、なければ正立（Tu）、縦書き用の字形があれば使い、なければ回転（Tr）の四つの値がある。Golem の PDF は、縦書き用の字形がない R と Tr の文字を、横組みの字形を時計回りに 90 度回して描く（[golem-driver ADR 0015](golem-driver/adr/0015-vertical-dashes.md)）。
- **突き出し**と**伸縮（hz）**：行末のハイフンや句読点を版面の外へわずかに出すことと、欧文のグリフの幅をわずかに伸び縮みさせること。どちらも語間の空きのばらつきを減らす（[golem-layout ADR 0005](golem-layout/adr/0005-microtypography.md)）。
- **回り込み**：図版の脇に本文を流し込むこと。図版の周りを除外領域とし、そこにかかる行の行長を短くする（[golem-layout ADR 0004](golem-layout/adr/0004-wrapped-figures.md)）。
- **傍注**：版面の外の小口側に設けた傍注欄に置く注（[golem-layout ADR 0006](golem-layout/adr/0006-sidenotes.md)）。
- **改ページ**：今のページを閉じ、次のページから続けること。原稿では `@page-break` で指定する（[markup.md](markup.md)、[docs/adr/0017](adr/0017-forced-page-breaks.md)）。
- **改丁**：次の奇数ページから始めること。原稿では `@page-break recto`、見出しでは `style.toml` の `page-break = "recto"` で指定する（[docs/adr/0017](adr/0017-forced-page-breaks.md)）。
- **白ページ**：改ページや改丁で中身のないまま閉じたページ。柱もノンブルも描かない（[docs/adr/0017](adr/0017-forced-page-breaks.md)）。
- **段**と**段間**：段組みの版面を等しい幅に分けた一つの領域と、段と段のあいだの空き。`style.toml` の `[page.grid]` の `columns`（段数）と `column-gap`（段間）で決める。本文は横組みでは左の段から右の段へ、縦組みでは上の段から下の段へ流れる（[docs/adr/0018](adr/0018-multi-column-layout.md)）。PDF の索引は、`[index]` の `columns` と `column-gap` で、版面と異なる段数の段（索引の段）で組める。索引の段は版面の文字の領域を等しい幅に分け、行の位置は版面の行の格子に置く（[docs/adr/0025](adr/0025-index-columns.md)）。
- **改段**：今の段を閉じ、次の段から続けること。最後の段なら次のページの最初の段に進む。原稿では `@column-break` で指定する（[docs/adr/0017](adr/0017-forced-page-breaks.md)、[docs/adr/0018](adr/0018-multi-column-layout.md)）。

## 出力

- **ターゲット**：出力する形式。PDF、EPUB、HTML、プレーンテキストの四つがある。`golem build` は既定で四つすべてを生成し、`--target` で絞れる（[golem-cli ADR 0002](golem-cli/adr/0002-build-all-targets-by-default.md)）。
- **PDF/X-4**：印刷用の PDF の規格（ISO 15930-7:2010）。出力インテント、フォントの埋め込み、XMP のメタデータなどを求める（[golem-pdf ADR 0002](golem-pdf/adr/0002-pdf-x-4.md)）。
- **出力インテント**：印刷の条件を表す ICC プロファイル。v1 では Japan Color 2001 Coated とし、色の名前と CMYK の値はこれに結び付けて定義する。
- **スウォッチ**：名前を付けた色。`style.toml` に CMYK の値で定義し、原稿からは名前で指す。
- **シェイピング**：文字の並びを、フォントのグリフの並びと位置に変換すること。合字、カーニング、縦書き用の字形の置き換えを含み、HarfBuzz で行う（[golem-font ADR 0001](golem-font/adr/0001-shaping-and-metrics.md)）。
- **サブセット化**：フォントを、文書で使ったグリフだけを含む形に縮めること。Golem はグリフ番号を振り直さずに保つ（[golem-font ADR 0002](golem-font/adr/0002-subsetting-and-embedding.md)）。
- **ToUnicode**：PDF の中のグリフから元の文字列へ戻すための対応表。PDF からの文字の抽出と検索に使われる。
- **異体字セレクタ**と**IVS**：異体字セレクタは、直前の文字の字形を選ぶ Unicode の文字（`U+FE00` から `U+FE0F` と `U+E0100` から `U+E01EF`）。基底の文字と異体字セレクタの組を IVS（Ideographic Variation Sequence）という。PDF では基底の文字と一緒にシェイピングしてフォントの字形を選び、ToUnicode には基底の文字だけを書く（[golem-pdf ADR 0006](golem-pdf/adr/0006-cid-system-info.md)）。
- **文書 ID** と**インスタンス ID**：PDF と XMP に書く識別子。文書 ID は本の識別子から、インスタンス ID は入力全体のハッシュから導出し、乱数を使わない（[仕様書](specifications.md)）。
- **塗り足し**：仕上がりの判型の外側に設ける、断裁のずれを吸収するための領域。`style.toml` の `[page]` の `bleed` で幅を決める（[golem-pdf ADR 0004](golem-pdf/adr/0004-crop-marks-and-bleed.md)）。
- **トンボ**：断裁の位置を示すために、仕上がりの判型の外側に描く線。日本式は仕上がりの線と塗り足しの線の二重、欧文は仕上がりの線だけの一重で、`golem build` の `--marks` で選ぶ（[golem-pdf ADR 0004](golem-pdf/adr/0004-crop-marks-and-bleed.md)）。
- **プリフライト**：印刷所に入稿する前に、組んだ PDF が印刷に耐えるかを検査すること。Golem では `golem preflight` が、`golem build --target pdf --profile prod` と同じ PDF を組んで検査する。ビルドを止める原稿と設定の誤りとは分け、印刷の条件で止める（[golem-cli ADR 0006](golem-cli/adr/0006-preflight.md)）。
- **プリフライトの設定**：プリフライトで行う検査、その重大度、しきい値の組。InDesign のプリフライトプロファイルにあたる。TOML のファイル（既定は `preflight.toml`）に書き、組み込みの `basic`、`print`、`none` のどれかを基にする。「プロファイル」の語は dev と prod を指すので使わない（[golem-cli ADR 0006](golem-cli/adr/0006-preflight.md)）。
- **実効の解像度**：紙面に置いた画像の解像度。画素数を、置いた大きさ（インチ）で割った値で、縦と横の小さいほうを ppi で表す（[golem-cli ADR 0006](golem-cli/adr/0006-preflight.md)）。
- **断裁の危険域**：断裁のずれで切れたり、白い縁が出たりする位置。仕上がりの線の内側の一定の幅と、仕上がりの線から塗り足しの線までのあいだである（[golem-cli ADR 0006](golem-cli/adr/0006-preflight.md)）。
- **安全域**：仕上がりの線から一定の幅だけ内側に縮めた矩形。文字と線をこの中に収めれば、断裁のずれで切れない（[golem-cli ADR 0006](golem-cli/adr/0006-preflight.md)）。
- **レジストレーションの色**：すべての版に出る色。PDF では色材の名前が `All` の Separation の色空間で表す。Golem はトンボだけをこの色で描き、本文や図版には使わない（[golem-pdf ADR 0007](golem-pdf/adr/0007-registration-crop-marks.md)）。

## ツールと拡張

- **lint**：原稿の誤りの可能性を指摘する検査。規則は処理系が固定し、利用者が加えたり止めたりはできない（[golem-lint ADR 0001](golem-lint/adr/0001-lint-rules.md)）。
- **fmt**：出力を変えずに原稿の書式を整える整形。整形の前後で AST が一致することを保つ（[golem-fmt ADR 0001](golem-fmt/adr/0001-formatter.md)）。
- **LSP**：エディタに診断、補完、定義への移動などを提供する言語サーバーの規約（Language Server Protocol）。`golem lsp` が話す（[golem-lsp ADR 0001](golem-lsp/adr/0001-language-server.md)）。
- **診断**：構文の誤り、評価の誤り、lint の指摘などを、ソース上の位置と符号（`G0101` など）を付けて報告したもの。重大度はエラー、警告、お知らせの三つである（[golem-syntax ADR 0001](golem-syntax/adr/0001-source-spans-and-diagnostics.md)、[golem-syntax ADR 0002](golem-syntax/adr/0002-notice-severity.md)）。コードの一覧と説明は [docs/diagnostics.md](diagnostics.md) にある。
- **お知らせ**：警告より下の診断の重大度（`notice`）。誤りではないが書き手が知っておいたほうがよいこと（スタイルの上書き、効果のない書き方、廃止予定の書き方など）を伝える。終了コードと出力を変えず、マニフェストの `[diagnostics]` の `silence-notices` と、コマンドの `--no-notices` で抑制できる。抑制できる診断はお知らせだけである（[golem-syntax ADR 0002](golem-syntax/adr/0002-notice-severity.md)）。
- **プラグイン**：wasm のモジュールとして配布する拡張。import を一切受け取らず、呼び出しごとに新しいインスタンスで実行する。文書から呼ぶ**コマンド**と、ファイル一つ分の文書を書き換える**フィルタ**の二種類がある（[golem-plugin ADR 0001](golem-plugin/adr/0001-wasm-host-and-abi.md)）。
- **命令数の上限**：プラグインが一回の呼び出しで実行できる命令の数の上限（wasmtime の fuel）。命令の数で数えるので、上限に達する位置も決定的である。
- **ロックファイル**：プラグインの配布物の URL と SHA-256 を記録した `plugins.lock`。処理系だけが書き、ビルドはこのハッシュと一致するキャッシュからだけプラグインを読む（[golem-plugin ADR 0002](golem-plugin/adr/0002-distribution-and-lock.md)）。

## マニュアル

- **使い手のマニュアル**：Golem で本を作る人に向けたマニュアル。読み手は、組版の知識を持ち InDesign を使える編集者と DTP オペレーターで、敬体で書く。原稿は `manual/` の Golem のプロジェクトで、A5 判の PDF と HTML に組む（[docs/adr/0022](adr/0022-manual-as-typesetting-sample.md)、[docs/adr/0024](adr/0024-manual-audiences-and-policy.md)）。
- **開発者のマニュアル**：Golem を使って仕組みを作る人（第一部）と、Golem そのものを開発する人（第二部）に向けたマニュアル。常体で書き、仕様書と ADR をまとめてリンクする。原稿は `manual-dev/` で、B5 判の PDF と HTML に組む（[docs/adr/0024](adr/0024-manual-audiences-and-policy.md)）。
- **マニュアルの方針**：二つのマニュアルの読み手、文体、説明の厚さ、根拠と脚注、規格の一覧、章立て、コードの表示、更新の決まりを書いた文書 [docs/manual-policy.md](manual-policy.md)。マニュアルを書く人とレビューする人の基準である（[docs/adr/0024](adr/0024-manual-audiences-and-policy.md)）。
- **奥付の版**：マニュアルの奥付に載せる版（タグか、`VERSION` に「の開発版」を続けたもの）と、組んだコミットの 40 桁のハッシュ。`scripts/manual/build-info.sh` が組む前に `common/build-info.gm` に書き、奥付が `@import` で読む（[docs/adr/0024](adr/0024-manual-audiences-and-policy.md)）。
