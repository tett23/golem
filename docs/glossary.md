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
- **韻文**：組み込みの段落スタイル `verse` を `@style verse` で付けた段落。段落の中の改行が行の区切りになり、段落の一つが一つの連になる（[markup.md](markup.md)、[docs/adr/0003](adr/0003-verse-line-breaks.md)、[docs/adr/0005](adr/0005-character-and-paragraph-styles.md)）。
- **文字スタイル**：文字の見た目（書体、大きさ、色、合成の太字と斜体）に名前を付けたもの。`style.toml` の `[character-styles.<名前>]` に定義し、原稿では `[style 名前: ...]` で付ける。`[strong: ...]`、`[bold: ...]`、`[italic: ...]` は組み込みの文字スタイルの別名である。`based-on` で別の文字スタイルを引き継ぐ（[markup.md](markup.md)、[docs/adr/0005](adr/0005-character-and-paragraph-styles.md)）。
- **段落スタイル**：段落の見た目（書体、大きさ、改行の扱い、同じスタイルの段落の間の空き）に名前を付けたもの。`style.toml` の `[paragraph-styles.<名前>]` に定義し、原稿では `@style 名前` で付ける。段落スタイルを付けない段落は `body` で組む（[markup.md](markup.md)、[docs/adr/0005](adr/0005-character-and-paragraph-styles.md)）。
- **散文スロット**：命令文脈の `:` の後に書く本文の欄。`|` で区切って複数書ける。`[ruby: 漢字|かんじ]` の「漢字」と「かんじ」がそれぞれ散文スロットである。
- **エスケープ**：特別な意味を持つ文字を本文の文字として書くための `\`。`\` が唯一のエスケープ文字である。
- **校正用のコメント**：`%%=` で始まるコメント。dev のプロファイルでだけ出力に現れ、prod のプロファイルで残っていると警告になる（[仕様書](specifications.md)）。
- **プロファイル**：ビルドの用途を表す dev と prod の二つ。dev は書きかけの原稿のために一部の検査を警告にとどめ、prod は出荷する本のためにエラーにする。

## 評価と文書構造

- **CST**：原稿を、空白とコメントまで含めて失わずに表す具象構文木（Concrete Syntax Tree）。元のテキストを一字一句復元でき、整形と LSP が使う（[golem-parser ADR 0001](golem-parser/adr/0001-cst-types-and-invariants.md)）。
- **AST**：CST から空白、コメント、エスケープを取り除き、意味だけを残した抽象構文木。評価器は AST だけを読む（[golem-parser ADR 0005](golem-parser/adr/0005-cst-to-ast.md)）。
- **意味論 IR**：評価が済んだ文書の表現。幾何を持たず、全媒体の出力がここから分かれる。正典は CDDL で書いたスキーマであり、CBOR で直列化する（[golem-doc ADR 0001](golem-doc/adr/0001-semantic-ir-in-cddl.md)）。
- **評価の段階（S0、S1、S2）**：値がいつ決まるかによる三つの段階。**S0** はファイルの中だけで決まる値（変数、import した定義、見出しの文字列）、**S1** は全ファイルから決まる文書構造（目次、章番号、ラベルの章題と番号）、**S2** はレイアウトの後に決まる値（ページ番号）である（[仕様書](specifications.md)、[golem-eval ADR 0002](golem-eval/adr/0002-file-evaluation.md)）。
- **DeferredExpr**：S1 で初めて値が決まる式（`doc` 名前空間を参照する式）を、意味論 IR の中に評価を遅らせて保持したもの（[golem-eval ADR 0002](golem-eval/adr/0002-file-evaluation.md)）。
- **チャネル**：文書の各所から項目を集め、別の位置に一覧として出す仕組み。目次、脚注、索引、参考文献がこの形をとる（[仕様書](specifications.md)）。
- **ラベル**：`@label` でブロックに付ける名前。相互参照（章番号、章題、ページ番号）の参照先になる。

## 組版

- **版面**：ページの中で本文を組む領域。文字の大きさ、一行の字数、行数、行送り、段数で決め、余白はその位置から従属的に決まる（[仕様書](specifications.md)、[golem-layout-spec ADR 0001](golem-layout-spec/adr/0001-page-geometry.md)）。
- **ノド**と**小口**：ページの綴じる側の端と、その反対側の端。右綴じの本では奇数ページのノドが右にある（[golem-layout-spec ADR 0002](golem-layout-spec/adr/0002-gutter-side-of-odd-pages.md)）。
- **天**と**地**：ページの上端と下端。版面の位置は天とノドからの距離で決める。
- **柱**と**ノンブル**：ページの余白に置く章題などの見出しと、ページ番号。マスターページで位置と内容を決める。
- **マスターページ**：柱とノンブルの位置と内容をまとめた、ページの雛形。`style.toml` の `[masters]` に書く。
- **行の格子**：版面の中で各行を置く位置の並び（ベースライングリッド）。見開きの左右のページで行の位置がそろう。
- **sp**：Golem が内部で使う長さの単位。1pt の 65536 分の 1 であり、すべての寸法を整数で扱うためにある。`style.toml` では mm、pt、Q（級）、H（歯）、zw（全角一字分）で書き、読み込むときに sp へ変換する。
- **Knuth-Plass の行分割**：段落全体を見て、行の詰まり具合の悪さ（不良度）と罰点の合計が最小になる改行の位置を選ぶ方法。行ごとに目標の行長（L*(i)）を変えられる（[golem-layout ADR 0001](golem-layout/adr/0001-knuth-plass-line-breaking.md)）。
- **禁則**：行頭や行末に置いてはいけない文字を、その位置に来させない規則。閉じ括弧や句読点は行頭に置かない（[golem-layout ADR 0002](golem-layout/adr/0002-japanese-composition.md)）。
- **約物**：句読点、括弧、中点などの記号。和文では字面の外側に空きを持ち、隣り合うと空きを詰める。
- **和欧間**：和文と欧文の文字が隣り合う位置。四分の空きを置く。
- **ぶら下げ組**：行末の句読点を版面の外に出すことを許す組み方。
- **字下げ**：段落の行の始まりを下げること。段落スタイルの `indent`（すべての行）と `first-line-indent`（最初の行に加える量。負なら二行目以降が下がるぶら下げになる）で指定し、横組みでも縦組みでも行の始まりの側から測る（[docs/adr/0006](adr/0006-paragraph-indent.md)）。
- **ルビ**：親文字の傍らに小さく添える読み。親文字一字ごとに振る**モノルビ**と、語の全体に振る**グループルビ**がある（[markup.md](markup.md)）。
- **圏点**：強調のために親文字の傍らに打つ点。形（ゴマなど）は `style.toml` の既定か引数で決める。
- **縦中横**：縦組みの中で、短い文字列を横向きのまま一字分の幅に組むこと。
- **突き出し**と**伸縮（hz）**：行末のハイフンや句読点を版面の外へわずかに出すことと、欧文のグリフの幅をわずかに伸び縮みさせること。どちらも語間の空きのばらつきを減らす（[golem-layout ADR 0005](golem-layout/adr/0005-microtypography.md)）。
- **回り込み**：図版の脇に本文を流し込むこと。図版の周りを除外領域とし、そこにかかる行の行長を短くする（[golem-layout ADR 0004](golem-layout/adr/0004-wrapped-figures.md)）。
- **傍注**：版面の外の小口側に設けた傍注欄に置く注（[golem-layout ADR 0006](golem-layout/adr/0006-sidenotes.md)）。

## 出力

- **ターゲット**：出力する形式。PDF、EPUB、HTML、プレーンテキストの四つがある。`golem build` は既定で四つすべてを生成し、`--target` で絞れる（[golem-cli ADR 0002](golem-cli/adr/0002-build-all-targets-by-default.md)）。
- **PDF/X-4**：印刷用の PDF の規格（ISO 15930-7:2010）。出力インテント、フォントの埋め込み、XMP のメタデータなどを求める（[golem-pdf ADR 0002](golem-pdf/adr/0002-pdf-x-4.md)）。
- **出力インテント**：印刷の条件を表す ICC プロファイル。v1 では Japan Color 2001 Coated とし、色の名前と CMYK の値はこれに結び付けて定義する。
- **スウォッチ**：名前を付けた色。`style.toml` に CMYK の値で定義し、原稿からは名前で指す。
- **シェイピング**：文字の並びを、フォントのグリフの並びと位置に変換すること。合字、カーニング、縦書き用の字形の置き換えを含み、HarfBuzz で行う（[golem-font ADR 0001](golem-font/adr/0001-shaping-and-metrics.md)）。
- **サブセット化**：フォントを、文書で使ったグリフだけを含む形に縮めること。Golem はグリフ番号を振り直さずに保つ（[golem-font ADR 0002](golem-font/adr/0002-subsetting-and-embedding.md)）。
- **ToUnicode**：PDF の中のグリフから元の文字列へ戻すための対応表。PDF からの文字の抽出と検索に使われる。
- **文書 ID** と**インスタンス ID**：PDF と XMP に書く識別子。文書 ID は本の識別子から、インスタンス ID は入力全体のハッシュから導出し、乱数を使わない（[仕様書](specifications.md)）。
- **塗り足し**：仕上がりの判型の外側に設ける、断裁のずれを吸収するための領域。`style.toml` の `[page]` の `bleed` で幅を決める（[golem-pdf ADR 0004](golem-pdf/adr/0004-crop-marks-and-bleed.md)）。
- **トンボ**：断裁の位置を示すために、仕上がりの判型の外側に描く線。日本式は仕上がりの線と塗り足しの線の二重、欧文は仕上がりの線だけの一重で、`golem build` の `--marks` で選ぶ（[golem-pdf ADR 0004](golem-pdf/adr/0004-crop-marks-and-bleed.md)）。

## ツールと拡張

- **lint**：原稿の誤りの可能性を指摘する検査。規則は処理系が固定し、利用者が加えたり止めたりはできない（[golem-lint ADR 0001](golem-lint/adr/0001-lint-rules.md)）。
- **fmt**：出力を変えずに原稿の書式を整える整形。整形の前後で AST が一致することを保つ（[golem-fmt ADR 0001](golem-fmt/adr/0001-formatter.md)）。
- **LSP**：エディタに診断、補完、定義への移動などを提供する言語サーバーの規約（Language Server Protocol）。`golem lsp` が話す（[golem-lsp ADR 0001](golem-lsp/adr/0001-language-server.md)）。
- **診断**：構文の誤り、評価の誤り、lint の指摘などを、ソース上の位置と符号（`G0101` など）を付けて報告したもの。重大度はエラーと警告の二つである（[golem-syntax ADR 0001](golem-syntax/adr/0001-source-spans-and-diagnostics.md)）。
- **プラグイン**：wasm のモジュールとして配布する拡張。import を一切受け取らず、呼び出しごとに新しいインスタンスで実行する。文書から呼ぶ**コマンド**と、ファイル一つ分の文書を書き換える**フィルタ**の二種類がある（[golem-plugin ADR 0001](golem-plugin/adr/0001-wasm-host-and-abi.md)）。
- **命令数の上限**：プラグインが一回の呼び出しで実行できる命令の数の上限（wasmtime の fuel）。命令の数で数えるので、上限に達する位置も決定的である。
- **ロックファイル**：プラグインの配布物の URL と SHA-256 を記録した `plugins.lock`。処理系だけが書き、ビルドはこのハッシュと一致するキャッシュからだけプラグインを読む（[golem-plugin ADR 0002](golem-plugin/adr/0002-distribution-and-lock.md)）。
