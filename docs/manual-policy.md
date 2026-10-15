# マニュアルの方針

この文書は、Golem の二つのマニュアル（使い手のマニュアル `manual/` と開発者のマニュアル `manual-dev/`）を書く人とレビューする人の基準である。
最初の中身は [ADR 0024](adr/0024-manual-audiences-and-policy.md) が決めた。
[ADR 0022](adr/0022-manual-as-typesetting-sample.md) のうち、Golem 自身で組むこと、フォントをリポジトリに入れないこと、CI で組んで決定性を確かめること、リリースの資産に加えること、内容の範囲は、今も効いている。

この文書の変え方は次のとおりである。

- 読み手、内容の範囲、更新の検査、判型を変えるときは、新しい ADR を書く。
- 言い回しの例、規格の一覧への追加、InDesign との対応の表の行の追加、語の一覧への追加は、この文書を直接直してよい。

この文書は Golem の振る舞いを定めないので、`scripts/ci/needs-build.sh` のビルドが読む文書の一覧には入れない。

## 原稿と出力

| | 使い手のマニュアル | 開発者のマニュアル |
| --- | --- | --- |
| 原稿 | `manual/` | `manual-dev/` |
| 判型 | A5 の横組み | B5 の横組み |
| 版面 | 本文 13Q、行送り 22H、一行 32 字、29 行 | 本文 13Q、行送り 22H、一行 40 字、34 行 |
| 文体 | 敬体（です、ます） | 常体（である） |
| 出力 | PDF と HTML | PDF と HTML |
| リリースの資産 | `golem-manual-<タグ>.pdf`、`golem-manual-<タグ>-html.tar.gz` | `golem-dev-manual-<タグ>.pdf`、`golem-dev-manual-<タグ>-html.tar.gz` |

原稿は `.gm` のファイルだけである。
Markdown の版は持たない。
組んだものは、CI の `build` ジョブの成果物（`manual` と `manual-dev`）と、リリースの資産で読める。

## 組み方

```sh
GOLEM=$(cabal list-bin -v0 golem) sh scripts/manual/build.sh            # 二冊とも
GOLEM=$(cabal list-bin -v0 golem) sh scripts/manual/build.sh manual-dev # 一冊だけ
```

`build.sh` は、組む前に `scripts/manual/build-info.sh` で `common/build-info.gm`（奥付の版とコミットのハッシュ）を書き、フォントを取得し、`golem build --target pdf --target html` で組む。
エラー、警告、お知らせのどれか一つでも出れば失敗とする。
マニフェストに `[diagnostics]` の `silence-notices` を書いてはいけない（`build.sh` が組む前に止める）。
`golem build` に `--no-notices` を付けて呼ぶこともしない。
お知らせの原因（コードの書体の欠け、折り返したコードの行、勧めない記法など）は、原稿の側で取り除く。
勧めない書き方を例として見せたいときは、コードブロックの中に書く。
コードブロックの中身は解釈されない。

`build-info.gm` は生成物であり、Git では管理しない。
これがないまま `golem check` や LSP でマニュアルを開くと、`@import` の先がないエラー（G0302）になる。
マニュアルを編集する前に、一度次を実行する。

```sh
sh scripts/manual/build-info.sh manual
sh scripts/manual/build-info.sh manual-dev
```

Git のリポジトリの外で組むときは、`GOLEM_MANUAL_COMMIT` と `GOLEM_MANUAL_TAG` の環境変数で値を渡す。

## 内容の範囲

二つのマニュアルに書くのは、採択して実装を終えた仕様だけである。
docs/specifications.md の「今後の実装項目」に残っている事項、提案の ADR、未決事項は書かない。

決定の正は ADR と仕様書である。
マニュアルは新しい決定をしない。
マニュアルと ADR や仕様書が食い違ったときは、ADR と仕様書に従い、マニュアルを直す。

## 使い手のマニュアル

### 読み手

一般的な組版の知識（版面、行送り、禁則、ルビ、トンボと塗り足し、入稿）を持ち、InDesign を使える編集者と DTP オペレーターである。
著者も読むが、組版の用語の説明は読み手の知識を前提にして省く。
逆に、プログラムを書く人には当たり前の事柄（ターミナル、テキストの文字コード、TOML、Git、CI）は、読み手が知らないものとして説明する。

### 文体

敬体で書く。
ADR の番号、モジュールの名前、内部の型と処理の段階は本文に出さない。
根拠として仕様書の節を示すときは、脚注にリポジトリの文書の URL を置く。

### 技術の説明の厚さと根拠

次の事柄は、手順だけでなく、なぜそうするのかと、その根拠を書く。

- ターミナルとコマンドの基本（作業中のフォルダ、終了コード、標準エラー出力）
- テキストのファイル（UTF-8、BOM、改行の LF、Unicode の正規化をしない理由、異体字セレクタ）
- TOML の書き方（表、配列、文字列の二つの書き方、型の誤り）
- Git と CI（版の管理、差分、CI で毎回組むこと、決定性）
- フォント（OpenType の機能、埋め込みのライセンスと `fsType`、プロジェクトの中にフォントを置く理由）
- PDF/X-4、出力インテント、ICC プロファイル、トンボと塗り足し
- CSL と CSL-JSON
- LSP

根拠は、仕様や規格があればそれを示す。
仕様や規格へのリンクは脚注（`[note: ...]`）に置き、本文には規格の名前だけを書く。
規格の本文を読める形で公開していないもの（JIS X 4051、ISO 15930-7）は、規格の名前と発行元の案内のページを示し、Golem がどこまで従うかを仕様書の節で示す。
PDF/X-4 は、Golem 自身では適合を判定できず、入稿の前に商用のプリフライトで確かめる必要があることを書く。

### 規格の一覧

| 事柄 | 仕様と規格 | URL |
| --- | --- | --- |
| TOML | TOML v1.0.0 | https://toml.io/en/v1.0.0 |
| 文字コード | The Unicode Standard | https://www.unicode.org/versions/latest/ |
| 文字コード | RFC 3629（UTF-8） | https://www.rfc-editor.org/rfc/rfc3629 |
| 縦組みの字の向き | UAX #50（Unicode Vertical Text Layout） | https://www.unicode.org/reports/tr50/ |
| 文字の幅 | UAX #11（East Asian Width） | https://www.unicode.org/reports/tr11/ |
| 文字の区切り | UAX #29（Unicode Text Segmentation） | https://www.unicode.org/reports/tr29/ |
| 異体字 | Ideographic Variation Database | https://unicode.org/ivd/ |
| 日本語の組版 | JIS X 4051:2004（日本産業標準調査会の JIS の検索） | https://www.jisc.go.jp/app/jis/general/GnrJISSearch.html |
| 日本語の組版 | W3C, Requirements for Japanese Text Layout（JLReq） | https://www.w3.org/TR/jlreq/ |
| 入稿用の PDF | ISO 15930-7:2010（PDF/X-4） | https://www.iso.org/standard/55843.html |
| 色 | ICC.1:2022（ICC プロファイルの仕様） | https://www.color.org/specification/ICC.1-2022-05.pdf |
| 色 | Japan Color（日本印刷産業機械工業会の Japan Color 認証制度の案内。Japan Color 2001 Coated はその印刷の基準の一つ） | https://japancolor.jp/ |
| フォント | OpenType の仕様の OS/2 の表（`fsType`） | https://learn.microsoft.com/en-us/typography/opentype/spec/os2 |
| フォント | OpenType の機能のタグの一覧 | https://learn.microsoft.com/en-us/typography/opentype/spec/featurelist |
| 参考文献 | Citation Style Language 1.0.2 の仕様 | https://docs.citationstyles.org/en/stable/specification.html |
| 参考文献 | CSL-JSON のスキーマ | https://github.com/citation-style-language/schema |
| EPUB | EPUB 3.3 | https://www.w3.org/TR/epub-33/ |
| HTML | HTML Living Standard | https://html.spec.whatwg.org/multipage/ |
| CSS | CSS Text Module Level 3 | https://www.w3.org/TR/css-text-3/ |
| エディタ | Language Server Protocol 3.17 | https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/ |
| フォントのライセンス | SIL Open Font License 1.1 | https://openfontlicense.org/ |
| 版の管理 | Git の公式の文書 | https://git-scm.com/doc |

### 言葉の選び方

読み手は、プログラムを書く人の言葉を知らない前提で書く。

- 「ディレクトリ」は、最初に出る箇所で「ディレクトリ（Finder やエクスプローラーで見るフォルダのことです）」のようにフォルダであると明示する。以後の地の文では「フォルダ」と書く。「ディレクトリ」を使うのは、コマンドの名前、オプションの名前、Golem やほかのプログラムが表示する文言を引くときに限る。
- 読み手は Git を知らない前提で書く。下の一覧の Git と CI の語は、最初に出る箇所で、何のための仕組みかを Git を知らない人の言葉で説明する。説明する前の語を、ほかの章で先に使わない。使う必要があれば、説明の箇所へ相互参照を付ける。
- 第 1 章と第 2 章は Git を使わずに読めるように書く。Git の語は第 8 章「版の管理と CI」で初めて説明する。

下の一覧の語は、最初の説明の箇所より前に使わない。
付録 F「用語の一覧」にも同じ語を載せる。
どの語がこの扱いに当たるかは、この一覧で管理し、レビューで足す。

| 語 | 最初の説明の箇所 |
| --- | --- |
| ターミナル | 第 1 章「配布物を取得する」（詳しくは第 2 章「ターミナルとコマンド」） |
| コマンド、オプション、引数 | 第 1 章「配布物を取得する」（詳しくは第 2 章「ターミナルとコマンド」） |
| ディレクトリ（フォルダ） | 第 1 章「プロジェクトを作る」（詳しくは第 2 章「フォルダとファイル」） |
| 作業中のフォルダ | 第 2 章「フォルダとファイル」 |
| パス | 第 2 章「フォルダとファイル」 |
| 終了コード | 第 2 章「ターミナルとコマンド」 |
| 標準出力、標準エラー出力 | 第 2 章「ターミナルとコマンド」 |
| 文字コード、UTF-8、BOM | 第 2 章「テキストのファイル」 |
| 改行コード（LF、CR） | 第 2 章「テキストのファイル」 |
| Unicode の正規化、異体字セレクタ | 第 2 章「テキストのファイル」 |
| テキストエディタ | 第 2 章「テキストのファイル」 |
| TOML、表、配列 | 第 2 章「TOML の書き方」 |
| ハッシュ（ファイルの） | 第 1 章「配布物を取得する」 |
| 版の管理 | 第 8 章「版を管理する理由」 |
| Git、リポジトリ | 第 8 章「Git を入れてリポジトリを作る」 |
| コミット、コミットのハッシュ | 第 8 章「変更を記録する」 |
| 差分 | 第 8 章「差分を読む」 |
| ブランチ | 第 8 章「ブランチとプルリクエスト」 |
| クローン、プッシュ | 第 8 章「置き場所と共有」 |
| プルリクエスト | 第 8 章「ブランチとプルリクエスト」 |
| CI | 第 8 章「CI で毎回組む」 |
| 決定性 | はじめに「Golem とは」（詳しくは第 6 章「同じ原稿から同じ出力」） |
| LSP | 第 9 章「エディタと LSP」 |

はじめにの「InDesign との違い」は、Git と CI を名前だけ出し、第 8 章への相互参照を付ける。

### はじめに

「はじめに」には、次の三つを置く。

1. InDesign との違い。確かめられる事実だけを書く。InDesign にあって Golem にないもの（画面の上で直接組むこと、個々の行やオブジェクトを手で動かす調整、雑誌のような自由なフレームの配置、特色、プリフライトの全体）も同じ節に書く。
2. TeX との違い。同じく確かめられる事実に限る。TeX にあって Golem にないもの（数式の組版、長い歴史とパッケージの蓄積）も書く。
3. 読み手ごとの説得。編集者、DTP オペレーター、著者のそれぞれに向ける。

主張の一つ一つに、根拠（仕様書の節、CI のジョブ）を脚注で示す。
次のことは書かない。

- 「InDesign と同じ品質」「TeX より美しい」のような、比べ方を定められない主張。
- 速さの比較。計測の記録（`docs/benchmarks/`）があるときに限り、その記録を示して書く。
- 「PDF/X-4 に準拠することを保証する」。

### 章立て

前付け、本文の章、付録、後付けの順に並べる。

- 前付け：はじめに（`@nonumber`、目次に載せる）、目次
- 第 1 章 インストールと最初の一冊
- 第 2 章 テキストで本を作るための基礎（ターミナル、フォルダとファイル、テキストのファイル、TOML）
- 第 3 章 原稿の記法
- 第 4 章 プロジェクトの設定
- 第 5 章 スタイルの設定
- 第 6 章 出力
- 第 7 章 検査と診断（お知らせと、その抑制を含む）
- 第 8 章 版の管理と CI
- 第 9 章 エディタと LSP
- 第 10 章 プラグイン
- 付録 A 記法、B マニフェスト、C スタイル、D 診断の一覧、E InDesign との対応、F 用語の一覧
- 後付け：参考文献、索引、奥付

ノンブルは「はじめに」の最初のページから通しで振る。
各節では、その節で説明する機能を、その節の中で実際に使う。

### InDesign との対応

Golem の概念に InDesign の対応物があるときは、初出でその名前を示す。
付録 E に同じ表を載せる。

| Golem | InDesign |
| --- | --- |
| プロジェクト（`manifest.toml` と原稿と `style.toml`） | ドキュメントとブック |
| `style.toml` の `[page]` と `[page.grid]` | 新規ドキュメントとレイアウトグリッドの設定 |
| 段落スタイル、文字スタイル、`based-on` | 段落スタイル、文字スタイル、基準 |
| 正規表現スタイル | 正規表現スタイル（GREP スタイル） |
| アキ量のセット | 文字組みアキ量設定 |
| `kerning`、`tracking`、`proportional-metrics`、`baseline-shift` | カーニング、トラッキング、プロポーショナルメトリクス、ベースラインシフト |
| マスターページ（`[masters]`） | 親ページ（InDesign 2022 より前はマスターページ） |
| プロジェクトの `fonts/` | Document Fonts フォルダー |
| スウォッチ（`[color.swatches]`） | スウォッチ |
| `golem build` | 書き出し |
| `golem check` | プリフライトの一部（原稿と設定の検査に限る） |

対応は名前と役割の近さを示すもので、振る舞いが同じであることを意味しない。
振る舞いが違う箇所（たとえば、Golem の段落スタイルは行送りを持たず、本文は常に行の格子に載ること）は、対応を示した同じ節で違いを書く。
InDesign の操作の手順は説明しない。

## 開発者のマニュアル

### 読み手と構成

- 第一部「Golem で仕組みを作る」：Golem を使って仕組みを作る人（プラグインの作者、CI で自動の組版を組む人、エディタに LSP をつなぐ人）に向ける。
- 第二部「Golem を開発する」：Golem そのものを開発する人に向ける。

### 文体とリンク

常体で書く。
モジュールの名前、型の名前、ADR の番号は本文に出してよい。

診断の重大度は、`error`、`warning`、`notice` の名前で書く。
使い手のマニュアルと docs/diagnostics.md が使う「お知らせ」は、開発者のマニュアルでは使わない。
開発者は「お知らせ」から重大度の `notice` を引きにくく、ログの水準の info と取り違えやすいためである。
docs/diagnostics.md の重大度の欄の値を説明するときに限り、その値として「お知らせ」を引く。

開発者のマニュアルは、docs/ の仕様書、各モジュールの仕様書、ADR、CONTRIBUTING.md をまとめ、その文書へリンクする。
リンクは脚注に置き、リポジトリの文書は `https://github.com/tett23/golem/blob/main/` から始まる URL で書く。
版やコミットを含む URL にはしない。
どのコミットから組んだかは、奥付の版で示す。

## 二つのマニュアルに共通する体裁

- 前付けの順（番号のない「はじめに」、目次）、索引の二段組み、奥付の版の表示をそろえる。
- 奥付は `@import common/build-info.gm as build` で読み、「版：[= build.edition]」と「コミット：[code: [= build.commit]]」の二行を載せる。
- コードブロックは組み込みの段落スタイル `code` で組み、背景のスウォッチ（`{ cmyk = [0, 0, 0, 8] }` を出発点にする）と内側の余白を付ける。
- 本文の中のファイル名、コマンド、パス、キーは `[code: ...]` で書く。`[style code: ...]` は使わない。
- 書体の役割 `code` には、欧文に Source Code Pro の Regular、和文に Noto Sans JP の Regular を使う。
- 書体はリポジトリに入れず、`scripts/manual/fetch-fonts.sh` が版を固定した URL から取得して SHA-256 を確かめる。どれも SIL Open Font License 1.1 である。
- 本文が拠りどころにする規格と文献は、最初に出る箇所で `[cite キー]` で引用し、巻末の参考文献（`@bibliography`）に載せる。書誌のデータは、各マニュアルの `references.json` に置く。リンクは今までどおり脚注に置く。参考文献の一覧は引用した文献だけを並べるので、脚注にだけ書いた規格は一覧に載らない。
- 開発者のマニュアルの図は、`manual-dev/images/src/` の SVG を原稿とし、`scripts/manual/render-figures.sh` で PNG にして、両方をコミットする。今の Golem は図版に PNG と JPEG を使い、SVG を扱わないためである。図の文字は、組版と同じ Noto Sans JP で描く。

## 更新の決まり

`scripts/manual/check-updated.sh BASE HEAD` が、ブランチの変更を次の規則で検査する。
`.githooks/pre-push` と、CI の `docs.yml` の `manual` ジョブが呼ぶ。

1. docs/markup.md か docs/specifications.md を変えたら、`manual/` か `manual-dev/` の下のどれかのファイルを変えていなければならない。
2. CONTRIBUTING.md か CONTRIBUTING.en.md を変えたら、`manual-dev/` の下のどれかのファイルを変えていなければならない。
3. どちらの規則も、範囲のコミットのどれかのメッセージに `Manual: unchanged` のトレーラーがあれば通す。

規則 1 は二つのマニュアルのどちらを直しても通る。
使い手から見える振る舞いが変わったら使い手のマニュアルを、開発者にだけ見える変更なら開発者のマニュアルを直す。
どちらを直すべきかはレビューで確かめる。
各モジュールの仕様書と ADR の変更は検査しない。
細部のずれはレビューで見つける。
