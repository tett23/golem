# ADR 0024: マニュアルの読み手と方針

ステータス: 採択

## 文脈

[ADR 0022](0022-manual-as-typesetting-sample.md) は、使い手のためのマニュアルを二つの原稿で持つと決めた。
Markdown の docs/manual.md を正とし、それを手で Golem の記法に書き直した `manual/` を Golem で組む。
二つの原稿のずれは、見出しの照合（`scripts/manual/check-headings.sh`）で検出する。

この形には、運用してみて見えた問題が三つある。

一つ目は、二重の手間である。
マニュアルに付録を加えるプルリクエスト（[#74](https://github.com/tett23/golem/pull/74)）は、docs/manual.md に 968 行を足し、`manual/` に付録の四つのファイル（1300 行余り）を足している。
同じ内容を二度書き、見出しだけを機械で照合し、本文のずれはレビューで探すことになる。
Markdown の版を置いた理由は、GitHub の上で読めることと差分のレビューのしやすさだった。
しかし、`manual/` の `.gm` もテキストであり、差分はそのまま読める。
組んだ HTML と PDF は、CI の成果物とリリースの資産で読める。

二つ目は、読み手の定め方である。
[ADR 0022](0022-manual-as-typesetting-sample.md) は読み手を「Golem で本を作る人（著者、編集者、組版の担当者）」とし、技術の説明の厚さや根拠の示し方を決めていない。
所有者は、使い手のマニュアルの読み手を「一般的な組版の知識があり、InDesign を使える編集者と DTP オペレーター」と定め、技術にかかわる部分（TOML、CLI、Git、Unicode、フォント、PDF/X）は説明を厚くし、根拠を示すことを求めている。
仕様や規格があるものは、そのリンクを脚注で示す。
「はじめに」には、InDesign と TeX に対する違いと、編集者、DTP オペレーター、著者に向けた説得を書く。
今のマニュアルを読んだ所有者の指摘として、次のことも求められている。
「はじめに」を目次より前に置くこと、奥付の版にコミットのハッシュを書くこと、「ディレクトリ」という語は伝わらないので最初にフォルダのことだと明示すること、読み手は Git も知らないこと、索引を二段で組むことである。

三つ目は、開発者向けのマニュアルがないことである。
Golem を使って仕組みを作る人（プラグインの作者、CI で自動の組版を組む人、エディタに LSP をつなぐ人）と、Golem そのものを開発する人は、今は docs/ の仕様書、各モジュールの仕様書、ADR、CONTRIBUTING.md を自分でたどるしかない。
これらは決定の記録であり、「何をどう使うか」の順には並んでいない。

コードの表示にも課題がある。
今の `manual/` は、コードブロックを本文と同じ書体で組み、行頭の空白も残らない。
所有者は、コードを背景の色を付けて、コード用の等幅の書体で組むことを求めている。
この組み方は [golem-driver ADR 0017](../golem-driver/adr/0017-pdf-code-blocks.md) が決める。

検査にも一つ加える。
[golem-syntax ADR 0002](../golem-syntax/adr/0002-notice-severity.md) は、エラーと警告の下にお知らせ（notice）の重大度を設ける。
マニュアルは組版の見本なので、お知らせも出さずに組めることを求める。

## 実装すること

### 置き換える決定

この ADR は、[ADR 0022](0022-manual-as-typesetting-sample.md) の次の部分を置き換える。
置き換えない部分（Golem 自身で組むこと、フォントを取得してリポジトリに入れないこと、CI で組んで決定性を確かめること、リリースの資産に加えること、内容の範囲）は、[ADR 0022](0022-manual-as-typesetting-sample.md) のとおりとする。

- 「二つの原稿」：docs/manual.md を廃し、`manual/` を唯一の原稿にする。見出しの照合をやめる。
- 「読み手と書き方」：使い手のマニュアルの読み手と、技術の説明の厚さを改める（下の「使い手のマニュアル」）。
- 「章立て」：章を足し、「はじめに」を番号のない前書きにして目次の前に置く（同じく下）。
- 「体裁」：コードの書体、索引の二段組み、奥付の版の表示を足す。
- 「CI」の手順 1 と、`needs-build.sh` に docs/manual.md を入れること。
- 「仕様の変更とマニュアルの更新」：検査の条件を改める（下の「更新の検査」）。

実装のときに、[ADR 0022](0022-manual-as-typesetting-sample.md) のステータスの行の値を「採択→原稿、読み手、章立て、更新の検査は [ADR 0024](0024-manual-audiences-and-policy.md)」に改める。

### マニュアルの方針の文書

docs/manual.md を消し、代わりに docs/manual-policy.md を置く。
この文書は、二つのマニュアルの読み手、文体、説明の厚さ、根拠と脚注の書き方、参照する規格の一覧、構成、コードの表示、内容の範囲、更新の決まりを書く。
マニュアルを書く人とレビューする人は、この文書を基準にする。

この ADR は、方針の文書の最初の中身を決める。
以後の変更は、次のように分ける。

- 読み手、内容の範囲、更新の検査、判型を変えるときは、新しい ADR を書く。
- 言い回しの例、規格の一覧への追加、InDesign との対応の表の行の追加は、方針の文書を直接直してよい。

方針の文書は、Golem の振る舞いを定めないので、`scripts/ci/needs-build.sh` のビルドが読む文書の一覧には入れない。

### 使い手のマニュアル

**読み手**。
一般的な組版の知識（版面、行送り、禁則、ルビ、トンボと塗り足し、入稿）を持ち、InDesign を使える編集者と DTP オペレーターとする。
著者も読むが、組版の用語の説明は読み手の知識を前提にして省く。
逆に、プログラムを書く人には当たり前の事柄（ターミナル、テキストの文字コード、TOML、Git、CI）は、読み手が知らないものとして説明する。

**InDesign との対応**。
Golem の概念に InDesign の対応物があるときは、初出でその名前を示す。
方針の文書に対応の表を置き、マニュアルの付録にも同じ表を載せる。
最初の表は次のとおりとする。

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

**技術の説明の厚さと根拠**。
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
仕様や規格へのリンクは脚注に置き、本文には規格の名前だけを書く。
最初の規格の一覧は次のとおりとし、方針の文書に URL とともに載せる。

| 事柄 | 仕様と規格 |
| --- | --- |
| TOML | TOML v1.0.0 |
| 文字コード | The Unicode Standard、RFC 3629（UTF-8） |
| 縦組みの字の向き | UAX #50（Unicode Vertical Text Layout） |
| 文字の幅と区切り | UAX #11（East Asian Width）、UAX #29（Text Segmentation） |
| 異体字 | Ideographic Variation Database |
| 日本語の組版 | JIS X 4051:2004、W3C の Requirements for Japanese Text Layout（JLReq） |
| 入稿用の PDF | ISO 15930-7:2010（PDF/X-4） |
| 色 | ICC.1（ICC プロファイルの仕様）、Japan Color 2001 Coated |
| フォント | OpenType の仕様（OS/2 の `fsType`、機能のタグの一覧） |
| 参考文献 | CSL 1.0.2 の仕様、CSL-JSON のスキーマ |
| EPUB と HTML | EPUB 3.3、HTML Living Standard、CSS Text Module Level 3 |
| エディタ | Language Server Protocol 3.17 |
| フォントのライセンス | SIL Open Font License 1.1 |

規格の本文を読める形で公開していないもの（JIS X 4051、ISO 15930-7）は、規格の名前と発行元の案内のページを示し、Golem がどこまで従うかを仕様書の節で示す。
とくに PDF/X-4 は、Golem 自身では適合を判定できず、入稿の前に商用のプリフライトで確かめる必要があることを書く（[golem-pdf ADR 0003](../golem-pdf/adr/0003-pdf-x-4-validator.md)）。

**文体**。
[ADR 0022](0022-manual-as-typesetting-sample.md) のとおり敬体とする。
ADR の番号、モジュールの名前、内部の型と処理の段階を本文に出さない決まりも保つ。
根拠として仕様書の節を示すときは、脚注にリポジトリの文書の URL を置く。

**言葉の選び方**。
読み手は、プログラムを書く人の言葉を知らない前提で書く。
次の二つを、方針の文書に決まりとして書く。

- 「ディレクトリ」は、最初に出る箇所で「ディレクトリ（Finder やエクスプローラーで見るフォルダのことです）」のようにフォルダであると明示する。以後の地の文では「フォルダ」と書く。「ディレクトリ」を使うのは、コマンドの名前、オプションの名前、Golem やほかのプログラムが表示する文言を引くときに限る。端末に出る文言と本文の語が違っても読み手が迷わないように、最初の箇所で両方の語を結び付けておく。
- 読み手は Git を知らない前提で書く。リポジトリ、コミット、ハッシュ、差分、ブランチ、クローン、プッシュ、プルリクエスト、CI のように、マニュアルで使う Git と CI の語は、最初に出る箇所で、何のための仕組みかを Git を知らない人の言葉で説明する（たとえば「コミットは、ファイルの変更をひとまとまりにして履歴に記録したものです」）。説明する前の語を、ほかの章で先に使わない。使う必要があれば、説明の箇所へ相互参照を付ける。
- 方針の文書に、これらの語と最初の説明の箇所の一覧を置き、付録の用語の一覧にも載せる。

ほかにも、ターミナル、コマンド、オプション、終了コード、文字コードのように、DTP の現場で使わない語は同じ扱いにする。
どの語がこれに当たるかの判断は方針の文書の一覧で管理し、レビューで足す。

**はじめに**。
「はじめに」に、次の三つを置く。

1. InDesign との違い。書いてよいのは、確かめられる事実だけである。たとえば、原稿と体裁がテキストのファイルであり Git の差分で変更を追えること、同じ版の Golem は同じ入力から同じバイト列の PDF を作り、CI の `determinism` ジョブが x86-64 と aarch64 でそれを確かめていること、一つの原稿から PDF、EPUB、HTML、プレーンテキストを作ること、ライセンスが MIT であること。あわせて、InDesign にあって Golem にないもの（画面の上で直接組むこと、個々の行やオブジェクトを手で動かす調整、雑誌のような自由なフレームの配置、特色、プリフライトの全体）を同じ節に書く。
2. TeX との違い。同じく確かめられる事実に限る。たとえば、診断が原稿の位置とコードを持ち、マクロの展開で位置が失われないこと、日本語の組版（禁則、ルビ、アキ量のセット）が追加のパッケージなしで組み込まれていること、体裁を `style.toml` のデータとして書くこと、LSP でエディタが診断と補完を出すこと。TeX にあって Golem にないもの（数式の組版、長い歴史とパッケージの蓄積）も書く。
3. 読み手ごとの説得。編集者には、push のたびに CI が組んだ最新のゲラを全員が同じ URL で見られることと、変更の履歴が残ることを。DTP オペレーターには、段落スタイルやアキ量のセットの考え方がそのまま使えることと、フォントをプロジェクトに置くので機械ごとの組み上がりの差がないことを。著者には、好きなテキストエディタで書けて、体裁を気にせずに原稿に集中できることを書く。

書かないことも決める。
「InDesign と同じ品質」「TeX より美しい」のような、比べ方を定められない主張は書かない。
速さの比較は、計測の記録（`docs/benchmarks/`）があるときに限り、その記録を示して書く。
「PDF/X-4 に準拠することを保証する」とは書かない。

**章立て**。
本の並びは、前付け、本文の章、後付けの順とする。
前付けは「はじめに」、目次の順に置き、「はじめに」を目次より前にする。

「はじめに」は、番号のない前書き（`@nonumber` の見出し）とし、本文の章の番号は「インストールと最初の一冊」を第 1 章として数える。
目次より前に置く文章に章の番号を振ると、目次が第 2 章から始まるように見え、番号の並びと本の並びが食い違う。
和文の書籍の「はじめに」と「まえがき」は、番号を振らずに目次の前に置くのが通例であり、読み手の編集者と DTP オペレーターにもなじみがある。
「はじめに」は目次には載せる（`@notoc` を付けない）。
ノンブルは、Golem が前付けと本文で別の数え方（ローマ数字の前付けなど）を持たないので、「はじめに」の最初のページから通しで振る。

[ADR 0022](0022-manual-as-typesetting-sample.md) の章に二つの章を足し、付録を置く。

- 前付け：はじめに（番号なし）、目次
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
- 付録（記法、マニフェスト、スタイル、診断の一覧、InDesign との対応の表、用語の一覧）
- 後付け：参考文献、索引、奥付

第 8 章「版の管理と CI」は、Git を知らない読み手のために、版の管理とは何かから始める。
変更の履歴を残す理由、Git の入手、リポジトリを作ってコミットするまでの最小の手順、差分の見方、GitHub のような置き場所にプッシュすること、CI が push のたびに本を組むこと、決定性とゲラの共有の順に進める。
第 1 章と第 2 章は Git を使わずに読めるように書き、Git の語は第 8 章で初めて説明する。

付録の記法、マニフェスト、スタイル、診断は、#74 の付録をこの形に合わせて引き継ぐ。

**索引**。
索引は二段で組む。
本文は一段なので、一冊の中で段数を切り替える必要があり、[ADR 0025](0025-index-columns.md) の `[index]` の `columns` で指定する。
二段にするのは、索引の項目の多くが一行の半分に収まる短い語で、一段では行の後半が空き、索引のページ数がその分だけ増えるからである。

### 開発者のマニュアル

**置き場所と形**。
リポジトリの根に `manual-dev/` を置き、Golem のプロジェクトとして組む。
出力は PDF と HTML の二つとする。
判型は B5 の横組みとし、版面は本文 13Q、行送り 22H、一行 40 字、一ページ 34 行を出発点にする。
コードを多く載せるので、A5 より行長の長い判型を選んだ。
B5 は和文の技術書で広く使われる判型である。
本文 13Q と `code` の段落スタイルの `size = "11Q"` では、背景の内側の余白を除いて、一行におよそ 77 字のコードが収まる（行長 130mm から左右の余白（各 1.375mm）を引き、Source Code Pro の送り 0.6 字の 1.65mm で割った値）。
組み見て変えた値は、`style.toml` のコメントに理由とともに書く。
前付けの順（番号のない「はじめに」、目次）、索引の二段組み、奥付の版の表示は、使い手のマニュアルと同じにする。

**読み手と構成**。
二つの部に分ける。

- 第一部「Golem で仕組みを作る」：Golem を使って仕組みを作る人に向ける。CLI の終了コードと診断の JSON の形式、診断のコードと `golem explain`、お知らせとその抑制、CI で本を組む手順と決定性の使い方、ページ画像の差分を外部の道具で取る方法、LSP のつなぎ方（位置の単位の交渉を含む）、プラグインの ABI（CBOR の形、呼び出し規約、`plugins.lock`）、意味論 IR とレイアウト IR の概要。
- 第二部「Golem を開発する」：Golem そのものを開発する人に向ける。モジュールの構成と処理の流れ、ビルドとテスト、ADR の書き方と adr-guard、ドキュメントの決まり、テストを先に書く順序、CI のジョブ、決定性を守るための注意、リリースの手順、フィクスチャとライセンス。

**仕様書と ADR との関係**。
開発者のマニュアルは、docs/ の仕様書、各モジュールの仕様書、ADR、CONTRIBUTING.md をまとめ、その文書へリンクする。
決定の正は、今と同じく ADR と仕様書であり、マニュアルは新しい決定をしない。
マニュアルと ADR や仕様書が食い違ったときは、ADR と仕様書に従い、マニュアルを直す。
リンクは脚注に置き、リポジトリの文書は `https://github.com/tett23/golem/blob/main/` から始まる URL で書く。
版やコミットを含む URL にはしない。
本文の脚注がコミットごとに変わると、内容を変えていないページまで差分に現れるからである。
どのコミットから組んだかは、奥付の版で示す（下の「奥付の版」）。
内容の範囲は、使い手のマニュアルと同じく、採択して実装を終えたものに限る。

**文体**。
常体（である）とする。
読み手が開発者であり、リポジトリの docs/ と CONTRIBUTING.md と同じ文体のほうが、引用とリンクの行き来で文体が揺れないからである。
モジュールの名前、型の名前、ADR の番号は本文に出してよい。

**資産**。
リリースのワークフローは、`manual-dev/` を組んだ `golem-dev-manual-<タグ>.pdf` と `golem-dev-manual-<タグ>-html.tar.gz` をリリースの資産と `SHA256SUMS` に加える。
組むのに使う `golem` は、使い手のマニュアルと同じく、そのリリースの x86-64 の Linux の配布物とする。

### コードの表示と書体

二つのマニュアルのコードは、[golem-driver ADR 0017](../golem-driver/adr/0017-pdf-code-blocks.md) の組み方で組む。

- コードブロックは、組み込みの段落スタイル `code` に背景の色と内側の余白を付けて組む。背景のスウォッチは、墨だけのごく薄い色（`{ cmyk = [0, 0, 0, 8] }` を出発点にする）とする。本文の文字の色と重ならず、モノクロで印刷しても沈まない色にするためである。
- 本文の中のコードの名前は `[code: ...]` で書く。今の `[style code: ...]` は書き換える。
- 書体の役割 `code` に、欧文は Source Code Pro の Regular、和文は Noto Sans JP の Regular を使う。

Source Code Pro と Noto Sans JP は、どちらも SIL Open Font License 1.1 であり、PDF への埋め込みとサブセット化を許している。
取得の元は次のとおりとする。

| 書体 | 配布元 | タグ | ファイル |
| --- | --- | --- | --- |
| Source Code Pro | adobe-fonts/source-code-pro | `2.042R-u/1.062R-i/1.026R-vf`（2023-04-12） | `OTF/SourceCodePro-Regular.otf`、`LICENSE.md` |
| Noto Sans JP | notofonts/noto-cjk | `Sans2.004`（今の見出しの Bold と同じタグ） | `Sans/SubsetOTF/JP/NotoSansJP-Regular.otf`、`LICENSE` |

和文に Source Han Code JP を使う案も検討した。
Source Han Code JP は、Source Han Sans の和文と、送りを 667 単位（2/3 字）に広げた Source Code Pro の欧文を組み合わせた書体である。
Golem の役割は和文と欧文に別のフォントを指定するので、欧文には Source Code Pro そのものを使い、和文の字形だけを使うことになる。
その和文の字形は Source Han Sans の JP であり、Noto Sans JP と同じ字形である。
しかも Source Han Code JP の最後のリリースは 2020 年の 2.012R である。
同じ字形を、保守の続いている配布元から、すでに使っている版で取れるので、Noto Sans JP を選んだ。

`scripts/manual/fetch-fonts.sh` に二つの書体とライセンスの文書を加え、SHA-256 を固定する。
SHA-256 は、実装のときに取得して確かめた値を書く。
Source Code Pro のタグは `/` を含むが、`raw.githubusercontent.com` の URL でそのまま取得できることを、2026-10-14 に GitHub の API で確かめた。

### 奥付の版

二つのマニュアルの奥付に、版と、組んだコミットのハッシュを載せる。
手元の PDF がどの時点の原稿と Golem から組まれたかを、読み手と開発者が突き合わせられるようにするためである。

Golem の原稿はコミットのハッシュを読む手段を持たず、式に条件式もない（仕様書の「課題にしなかった事項」の「式の拡張」）。
そこで、組む前にスクリプトが値を書いたファイルを作り、奥付がそれを `@import` で読む。

- `scripts/manual/build-info.sh PROJECT` を置く。`PROJECT` のフォルダの `common/build-info.gm` に、次の二つの変数を書く。

  ```
  %% scripts/manual/build-info.sh が書いたファイル。手で編集しない %%
  @set edition = "v0.1.0"
  @set commit = "0123456789abcdef0123456789abcdef01234567"
  ```

- `edition` は、組むコミットに `v` で始まるタグがあればそのタグ、なければリポジトリの根の `VERSION` の内容に「の開発版」を続けた文字列（`0.1.0-rc2 の開発版`）とする。
- `commit` は `git rev-parse HEAD` の 40 桁のハッシュとする。作業ツリーにコミットしていない変更があれば（`git status --porcelain --untracked-files=no` が空でなければ）、ハッシュの後に「（コミットしていない変更を含む）」を続ける。短縮したハッシュにしないのは、短縮の桁数がリポジトリの大きさで変わり、同じコミットでも表記が揺れるからである。
- 環境変数 `GOLEM_MANUAL_COMMIT` と `GOLEM_MANUAL_TAG` があれば、git を読まずにその値を使う。Git のリポジトリの外（ソースの圧縮ファイルなど）で組む場合のためである。どちらもなく、git でハッシュを読めない場合は、終了コード 1 で終わる。版のわからない見本を配らないためである。
- 二つの変数は、どちらも奥付で使う。使わない変数を書くと、lint の「使われていない `@set` 変数」のエラーになるので、書く変数と奥付で使う変数を一致させる。
- `manual/back.gm` と `manual-dev/` の奥付のファイルは、`@import common/build-info.gm as build` で読み、「版：[= build.edition]」と「コミット：[code: [= build.commit]]」の二行を載せる。
- `build-info.gm` は生成物なので、`.gitignore` に `manual/common/build-info.gm` と `manual-dev/common/build-info.gm` を加える。
- `scripts/manual/build.sh` は、組む前に `build-info.sh` を呼ぶ。

リリースのワークフローは、`GOLEM_MANUAL_TAG` にリリースのタグを渡して組む。
タグのコミットを取り出して組むので、ハッシュはタグのコミットになる。
タグを環境変数で渡すのは、チェックアウトの設定によってタグの参照が手元にない場合でも、版の表記を確実にするためである。
プルリクエストの CI では、GitHub が作るマージのコミットを取り出して組むので、奥付のハッシュはそのマージのコミットのものになる。
組んだものと奥付のハッシュが一致することを優先し、ブランチの先端のハッシュには差し替えない。

決定性への影響は次のとおりである。
コミットのハッシュも入力の一部になるので、マニュアルの PDF と HTML は、内容を変えていないコミットでも奥付の分だけバイト列が変わる。
CI の `determinism` ジョブは、同じコミットを x86-64 と aarch64 で組んで比べるので、この変化の影響を受けない。
異なるコミットのマニュアルのバイト列を比べる仕組みは今はなく、作るときは奥付を除いて比べる必要がある。

`build-info.gm` がないまま `golem check` や LSP でマニュアルを開くと、`@import` の先がないエラー（G0302）になる。
マニュアルを編集する人は、一度 `scripts/manual/build-info.sh manual` を実行する。
この手順を README の開発の節と方針の文書に書く。

### 組み方と検査

`scripts/manual/build.sh` を次のように改める。

```
build.sh [PROJECT...]
```

- `PROJECT` は `manual` か `manual-dev` で、省くと両方を組む。
- それぞれのプロジェクトの `fonts/` にフォントを取得し（すでにあれば検査だけ）、`golem build --target pdf --target html` で組む。
- 今と同じく、`golem build` が何かを出力すれば失敗とする。エラーと警告に加え、お知らせも失敗になる。マニュアルは見本なので、お知らせの原因（コードの書体の欠け、折り返したコードの行、勧めない記法など）も残さない。
- マニフェストに `silence-notices` があれば、組む前に失敗とする。抑制でお知らせを消すことを、マニュアルでは認めない。
- `--no-notices` を付けて `golem build` を呼ぶことはしない。

`scripts/manual/check-headings.sh` と、`scripts/manual/test.sh` のその検査を消す。
`ci.yml` の `build` ジョブから見出しの照合の手順を消し、組む手順で二つのマニュアルを組み、x86-64 のジョブで成果物 `manual` と `manual-dev` を上げる。
フォントのキャッシュは、今と同じく `scripts/manual/fetch-fonts.sh` のハッシュを鍵とし、`manual/fonts` と `manual-dev/fonts` の両方を対象にする。
`scripts/determinism.sh` は、二つのマニュアルの出力のハッシュを書く。
`.gitignore` に `manual-dev/fonts/` と `manual-dev/build/` を加える。
`scripts/ci/needs-build.sh` のビルドが読む文書の一覧から `docs/manual.md` を消す。
`manual-dev/` は docs/ の外にあるので、今の判定のままビルドする側になる。

### 更新の検査

`scripts/manual/check-updated.sh BASE HEAD` の規則を次のように改める。
`BASE...HEAD` の変更のパスと、`BASE..HEAD` のコミットのメッセージを読むことは変えない。

1. docs/markup.md か docs/specifications.md を変えたら、`manual/` か `manual-dev/` の下のどれかのファイルを変えていなければならない。
2. CONTRIBUTING.md か CONTRIBUTING.en.md を変えたら、`manual-dev/` の下のどれかのファイルを変えていなければならない。
3. どちらの規則も、範囲のコミットのどれかのメッセージに `Manual: unchanged` のトレーラーがあれば通す。

失敗したときは、どの規則に当たったか、変えたファイル、直し方を標準エラー出力に書く。
規則 1 で二つのマニュアルのどちらでもよいとするのは、仕様書の変更には、使い手から見える振る舞いの変更と、開発者にだけ見える変更（CI の仕組みなど）があり、どちらのマニュアルを直すべきかを機械では決められないからである。
規則 2 は、第二部が CONTRIBUTING.md をまとめているので、開発の手順の変更が第二部に届くようにするためである。
各モジュールの仕様書と ADR の変更は検査しない。
数が多く、そのほとんどがマニュアルの粒度より細かいからである。

`.githooks/pre-push` と `docs.yml` の `manual` ジョブは、このスクリプトを呼ぶので、変えない。
`main` のルールセットの必須の検査も変えない。

### 実装の順序

[golem-syntax ADR 0002](../golem-syntax/adr/0002-notice-severity.md) と [golem-driver ADR 0017](../golem-driver/adr/0017-pdf-code-blocks.md) の後に実装する。
マニュアルが `[code: ...]` と段落スタイル `code` を使い、検査がお知らせを数えるためである。
索引の二段組みは [ADR 0025](0025-index-columns.md) に頼るので、それもこの ADR より先に実装する。
[#74](https://github.com/tett23/golem/pull/74) は、この ADR の実装より先にマージする前提とし、実装のプルリクエストで docs/manual.md の付録を `manual/` の付録に一本化する。

### ドキュメント

- README の冒頭近くのマニュアルの案内を、リリースの資産の PDF と HTML（使い手と開発者の二つ）と、`manual/` と `manual-dev/` の原稿、docs/manual-policy.md への案内に改める。docs/manual.md へのリンクを消す。
- README の開発の節と CI の表を、二つのマニュアル、`build.sh` の引数、`build-info.sh`、見出しの照合の廃止、更新の検査の新しい規則に合わせて改める。
- CONTRIBUTING.md と CONTRIBUTING.en.md の「ドキュメント」の節を、方針の文書と、更新の検査の新しい規則に合わせて改める。
- docs/specifications.md の「マニュアル」の節を書き換える。
- docs/glossary.md に、マニュアルの用語を加える必要があれば加える。

## 実装しないこと

- docs/manual.md を `manual/` から生成すること。Markdown の版そのものを持たない。
- 開発者のマニュアルの英語の版と、使い手のマニュアルの英語の版。
- GitHub Pages での公開。リリースの資産と CI の成果物で足りる（[ADR 0022](0022-manual-as-typesetting-sample.md) と同じ）。
- 各モジュールの仕様書と ADR の変更に、マニュアルの更新を求める検査。
- マニュアルの本文と仕様書の内容の機械的な照合。
- InDesign の操作の手順の説明。対応する概念の名前を示すにとどめる。
- 開発者のマニュアルの EPUB とプレーンテキストの出力。
- 前付けのノンブルを本文と別の数え方（ローマ数字など）にすること。Golem にその機能がない。
- Golem の原稿からコミットのハッシュや版を直接読む機能。スクリプトが書くファイルで足りる。
- 「ディレクトリ」と Git の語の使い方の機械的な検査。方針の文書の一覧とレビューで守る。

## テスト設計

### 先に書いて失敗させるテスト（`scripts/manual/test.sh`）

`check-updated.sh` について、今と同じく一時ディレクトリに git のリポジトリを作り、`main` から切ったブランチにコミットを積んで確かめる。

- `docs/markup.md` を変え、`manual/` も `manual-dev/` も変えていないとき、終了コード 1 で、標準エラー出力に `docs/markup.md` が出る。
- `docs/markup.md` と `manual/chapters/04-markup.gm` を変えたとき、終了コード 0。
- `docs/specifications.md` と `manual-dev/part1/cli.gm` を変えたとき、終了コード 0。
- `docs/manual.md` だけを変えた古い直し方（`docs/specifications.md` と `docs/manual.md`）では、終了コード 1。
- `CONTRIBUTING.md` を変え、`manual/` だけを変えたとき、終了コード 1 で、標準エラー出力に `CONTRIBUTING.md` と `manual-dev/` が出る。
- `CONTRIBUTING.en.md` と `manual-dev/` の下のファイルを変えたとき、終了コード 0。
- `CONTRIBUTING.md` を変え、範囲のコミットに `Manual: unchanged` のトレーラーがあるとき、終了コード 0。
- `docs/golem-pdf/specifications.md` だけを変えたとき、終了コード 0。
- 今のテストのうち、トレーラーが本文の途中にあるだけのとき 1 になること、`modules/` だけの変更で 0 になること、分岐点からの差分であることは残す。

`build.sh` について、`GOLEM` に偽の `golem`（引数を記録し、決まった文字列を標準エラー出力に書いて決まった終了コードで終わるスクリプト）を渡し、`fetch-fonts.sh` を通さない環境変数（`GOLEM_MANUAL_SKIP_FONTS=1`）を設けて確かめる。

- 偽の `golem` が何も書かず 0 で終わるとき、終了コード 0。
- 偽の `golem` が `notice[G0730]` の行だけを書いて 0 で終わるとき、終了コード 1。
- 偽の `golem` が `warning[G0205]` の行を書いて 0 で終わるとき、終了コード 1。
- 引数を省くと、`manual` と `manual-dev` の両方で `golem build --target pdf --target html` が呼ばれること。`manual-dev` だけを渡すと、`manual-dev` だけで呼ばれること。
- `--no-notices` を付けて呼ばないこと。
- 一時ディレクトリのマニフェストに `silence-notices` があるとき、`golem` を呼ぶ前に終了コード 1 で終わること。
- 未知の引数（`docs`）で、終了コード 2。

`build-info.sh` について、一時ディレクトリに git のリポジトリと `VERSION`（`0.1.0-rc2`）と `PROJECT/common/` を作って確かめる。
`build-info.gm` の中身は、全体を期待する文字列と比べる。

- `v0.1.0-rc2` のタグがあるコミットで、`edition` が `"v0.1.0-rc2"`、`commit` が `git rev-parse HEAD` の 40 桁であること。
- タグのないコミットで、`edition` が `"0.1.0-rc2 の開発版"` であること。`v` で始まらないタグ（`fixture-1`）だけがあるコミットでも同じであること。
- 追跡しているファイルにコミットしていない変更があるとき、`commit` の値の末尾に「（コミットしていない変更を含む）」が付くこと。追跡していないファイルだけがあるときは付かないこと。
- `GOLEM_MANUAL_COMMIT` と `GOLEM_MANUAL_TAG` を与えると、git のリポジトリの外でもその値で書くこと。
- git のリポジトリの外で、環境変数もないとき、終了コード 1 で、ファイルを書かないこと。
- 二度続けて実行しても、ファイルの中身が同じであること。

`build.sh` が `build-info.sh` を組む前に呼ぶことを、偽の `golem` の呼ばれた時点で `common/build-info.gm` があることで確かめる。

前付けの順と奥付は、`manual/` を組んだ結果で確かめる（golem-driver のテストの形は使わず、次の「自動テストにできないもの」の確かめ方で見る）。
ただし、`manual/manifest.toml` の章の並びの最初のファイルが「はじめに」で、その次が目次（`@toc`）を含むファイルであることは、`scripts/manual/test.sh` で `manifest.toml` を読んで確かめる。

`fetch-fonts.sh` について、今のテスト（SHA-256 が合わないファイルを消して失敗すること）を、新しく加えた `SourceCodePro-Regular.otf` と `NotoSansJP-Regular.otf` でも確かめる。

`scripts/ci/test.sh` について、次を確かめる。

- `needs-build.sh` の表から `docs/manual.md` の行を消し、`docs/manual-policy.md` だけの変更で `false` を出すことを加える。
- `manual-dev/style.toml` だけの変更で `true` を出すこと。
- docs の一覧の漏れの検査が、`docs/manual.md` を消した後のリポジトリで通ること。

### 自動テストにできないものの確かめ方

- 二つのマニュアルの PDF を開き、判型（A5 と B5）、本文と見出しとコードの書体、コードブロックの背景と字下げを目で確かめる。Acrobat のフォントの一覧で、Source Code Pro と Noto Sans JP の Regular が埋め込まれていることを確かめる。
- HTML をブラウザで開き、コードが `code` の役割の書体と背景で表示されることを確かめる。
- PDF で、「はじめに」が目次より前にあり、番号がなく、目次に載っていること、第 1 章が「インストールと最初の一冊」であることを確かめる。
- 奥付の版とハッシュが、組んだコミットと一致することを確かめる。リリースの資産では、版がタグであることを確かめる。
- 索引が二段で組まれていることを確かめる。
- 「ディレクトリ」の最初の箇所でフォルダであると書かれていること、Git の語の一覧のそれぞれが最初の箇所で説明されていることを、方針の文書の一覧と突き合わせてレビューで確かめる。
- 使い手のマニュアルの「はじめに」の主張の一つ一つについて、根拠（仕様書の節、CI のジョブ、ADR）が脚注にあることを、レビューで確かめる。比べ方を定められない主張がないことも確かめる。
- InDesign との対応の表を、InDesign を使う人（所有者）が読み、対応の誤りと、違いの書き漏れがないことを確かめる。
- 最初のリリースで、資産に開発者のマニュアルの PDF と HTML が載り、`SHA256SUMS` と一致することを確かめる。
- CI の `determinism` ジョブで、開発者のマニュアルのハッシュも x86-64 と aarch64 で一致することを確かめる。

確かめた結果は、実装のプルリクエストのコメントか、リリースの監査の記録（`docs/audits/releases/<タグ>.md`）に書く。

## トレードオフ

- Markdown の版をやめると、GitHub の上で整形されたマニュアルを読めなくなる。読むには CI の成果物かリリースの資産を開く必要がある。代わりに、同じ内容を二度書く手間と、本文のずれをレビューで探す負担がなくなる。`.gm` もテキストなので、差分のレビューはできる。
- 見出しの照合をやめると、二つの原稿の対応を確かめる検査がなくなるが、原稿が一つになるので照合の対象もなくなる。
- 開発者のマニュアルを足すと、CI の `build` ジョブが、もう一冊を組む分だけ長くなる。実装の後に `docs/ci-timings/` に記録する。
- 開発者のマニュアルは、CONTRIBUTING.md と仕様書の内容をまとめ直すので、ずれる危険がある。正は ADR と仕様書と決め、CONTRIBUTING.md の変更は検査で第二部に届くようにする。各モジュールの仕様書の変更は検査しないので、細部のずれはレビューで見つけるしかない。
- 更新の検査の規則 1 は、二つのマニュアルのどちらを直しても通るので、使い手から見える変更で開発者のマニュアルだけを直しても通ってしまう。どちらを直すべきかを機械で決める規則を作るより、レビューに任せる。
- お知らせも検査で失敗にするので、マニュアルを書く人は、勧めない書き方の例を本文に載せられない。廃止予定の書き方を見せたい場合は、組まれないコードブロックの中に書く（コードブロックの中身は解釈されない）。
- B5 の判型は、A5 の使い手のマニュアルと並べると大きさがそろわない。コードの行長を優先した。
- InDesign との対応を示すと、読み手は同じ振る舞いを期待しやすい。違いを同じ節で書く決まりで補う。
- 開発者のマニュアルのリンクを `main` の URL にするので、古い版の PDF のリンクが、今の `main` の文書を指す。脚注がコミットごとに変わらないことを優先し、どのコミットかは奥付で示す。
- 奥付にハッシュを載せると、マニュアルの出力がコミットごとに変わる。決定性の検査は同じコミットのあいだの比較なので影響しないが、将来コミットのあいだで出力を比べる仕組みを作るときは、奥付を除く必要がある。
- `build-info.gm` を生成物にするので、生成する前の `golem check` と LSP は G0302 のエラーを出す。仮の値のファイルをコミットしておけば避けられるが、組むたびにコミット済みのファイルが書き換わり、作業ツリーが常に変更ありの状態になる。一度スクリプトを実行する手間のほうを選んだ。
- 「はじめに」を番号のない前書きにすると、[ADR 0022](0022-manual-as-typesetting-sample.md) の「1. はじめに」から章の番号が一つずつずれ、マニュアルの中の章の参照（`[ref-number ...]`）は自動で追従するが、外部から章の番号で参照している箇所があれば直す必要がある。今はそうした参照はない。
- 「ディレクトリ」の言い換えと Git の語の説明を求めると、マニュアルの分量が増え、技術に慣れた読み手には冗長に感じられる。読み手を編集者と DTP オペレーターに定めた以上、その読み手に届くことを優先した。

## 参考文献

- TOML v1.0.0. https://toml.io/en/v1.0.0
- The Unicode Standard. https://www.unicode.org/versions/latest/
- RFC 3629, UTF-8, a transformation format of ISO 10646. https://www.rfc-editor.org/rfc/rfc3629
- Unicode Standard Annex #50, Unicode Vertical Text Layout. https://www.unicode.org/reports/tr50/
- Unicode Standard Annex #11, East Asian Width. https://www.unicode.org/reports/tr11/
- Unicode Standard Annex #29, Unicode Text Segmentation. https://www.unicode.org/reports/tr29/
- Ideographic Variation Database. https://unicode.org/ivd/
- JIS X 4051:2004 日本語文書の組版方法（日本産業標準調査会の JIS の検索）. https://www.jisc.go.jp/app/jis/general/GnrJISSearch.html
- W3C, Requirements for Japanese Text Layout. https://www.w3.org/TR/jlreq/
- ISO 15930-7:2010, Graphic technology: Prepress digital data exchange using PDF, Part 7（PDF/X-4）. https://www.iso.org/standard/55843.html
- ICC.1:2022, Image technology colour management. https://www.color.org/specification/ICC.1-2022-05.pdf
- OpenType specification, OS/2 table. https://learn.microsoft.com/en-us/typography/opentype/spec/os2
- OpenType specification, Registered features. https://learn.microsoft.com/en-us/typography/opentype/spec/featurelist
- Citation Style Language 1.0.2 Specification. https://docs.citationstyles.org/en/stable/specification.html
- CSL-JSON schema. https://github.com/citation-style-language/schema
- EPUB 3.3. https://www.w3.org/TR/epub-33/
- HTML Living Standard. https://html.spec.whatwg.org/multipage/
- CSS Text Module Level 3. https://www.w3.org/TR/css-text-3/
- Language Server Protocol Specification 3.17. https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/
- SIL Open Font License 1.1. https://openfontlicense.org/
- Source Code Pro. https://github.com/adobe-fonts/source-code-pro
- Source Han Code JP（検討して採らなかった書体）. https://github.com/adobe-fonts/source-han-code-jp
- Noto CJK. https://github.com/notofonts/noto-cjk
- Adobe Community, Why have Master Pages in InDesign been renamed to Parent Pages?（InDesign 2022 で名称が変わったこと）. https://community.adobe.com/t5/indesign-discussions/why-have-master-pages-in-indesign-been-renamed-to-parent-pages/m-p/12517120
