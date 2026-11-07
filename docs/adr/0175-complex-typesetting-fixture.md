# ADR 0175: 機能を組み合わせた二冊の fixture で、機能のあいだの相互作用を固定する

ステータス: 採択（未実装）

## 文脈

v0.1.0-rc4 のロードマップは、「複雑な組版の fixture」の項目を持つ（[docs/roadmap.md](../roadmap.md)）。
縦組みと横組み、段組み、ルビと圏点、注、図版と回り込み、表、コードブロック、罫線を持つ段落と見出し、索引、目次、参考文献などを一冊の中で組み合わせ、機能のあいだの相互作用を、出力のゴールデンと決定性の検査で固定する。
同じプルリクエストで、見た目の回帰テスト（[ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md)）の入力にも加える。
[ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md) の「入力」も、この fixture ができたら同じプルリクエストで入力に加えると定めている。

### 今の入力が組み合わせていない機能

今の fixture と二つのマニュアルが、どの機能を使っているかを、原稿（`.gm`）と `style.toml` を `rg` で数えて確かめた（2026-11-06、main の `50b9fca8`）。
数は、その記法を含むファイルの数である。

| 入力 | 書字方向 | 本文の段数 | ルビ | 圏点 | 脚注 | 図版 | 回り込み | 表 | コード | 索引 | 目次 | 引用 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `sample` | 縦（PDF） | 1 | 1 | 0 | 1 | 0 | 0 | 1 | 1 | 0 | 1 | 0 |
| `figures` | 横 | 1 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| `kanikosen` | 縦 | 1 | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| パブリックドメインの十冊 | 縦 5、横 5 | 1 | 5 冊 | 1 冊 | 1 冊 | 0 | 0 | 1 冊 | 0 | 0 | 0 | 0 |
| 使い手のマニュアル | 横 | 1 | 7 | 4 | 16 | 3 | 2 | 12 | 16 | 20 | 2 | 11 |
| 開発者のマニュアル | 横 | 1 | 0 | 0 | 17 | 3 | 0 | 16 | 14 | 17 | 2 | 7 |

ここから、次の五つが分かる。

- 本文を二段以上に組む入力がない。どの `style.toml` も `[page.grid]` の `columns` は 1 である。二つのマニュアルの `columns = 2` は、`[index]` の段数である。
- 縦組みの入力は、図版、回り込み、索引、参考文献のどれも使わない。表とコードを使うのは `sample` の PDF だけで、3 ページしかない。
- 段落スタイルと見出しの罫線（`rule-before` と `rule-after`、[golem-driver ADR 0027](../golem-driver/adr/0027-paragraph-style-rules.md)）を使う入力がない。罫線は、三つの入力の `[notes.rule]` だけである。
- Emet の関数とフィルタを使う `functions` と `emet-samples` は、決定性の検査で HTML、EPUB、テキストだけを組み、PDF を組まない（[`scripts/determinism.sh`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/scripts/determinism.sh#L49-L52)）。見た目の回帰テストの入力にもない（[`scripts/visual/build.sh`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/scripts/visual/build.sh#L29-L33)）。Emet の出力が PDF の組版を通る経路は、どの検査も固定していない。
- 出力のゴールデン（[`OutputGoldenSpec`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/test/OutputGoldenSpec.hs#L61-L69)）は、`sample` と `figures` の PDF と EPUB だけを固定する。

### 一冊には収まらない組み合わせ

ロードマップは「一冊の中で」と書くが、今の Golem では、挙げた機能のすべてを一冊に入れることはできない。
仕様書とコードを読み、試作した原稿を `golem` で組んで確かめた。

- **書字方向は本で一つ**：`writing-mode` は `style.toml` の `[page]` のキーで（[`Style.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-project/src/Golem/Project/Style.hs#L1424)）、マスターページにも章にも書けない。縦組みの本の中に横組みの章を置く手段はない。
- **段組みと回り込み**：本文を二段以上にした版面で `@figure` に `wrap` を書くと、G07026 のエラーになる（[`Flow.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L1546)）。
- **傍注**：傍注の領域は、縦組みの版面にも段組みの版面にも設けられない（G07001、[`LayoutSpec.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-layout-spec/src/Golem/LayoutSpec.hs#L171-L173)）。

試作は、`kanikosen` の Noto Serif JP と golem-font の Source Sans Pro で、B6 の縦組みの一段の本と、A5 の横組みの二段の本を、同じ原稿から組んだ。
使った `golem` は `~/.local/bin/golem`（`golem 0.1.0-rc3` と名乗るが、`E` のコードと二倍ダッシュの G07101 を持つので、rc3 より後の main から作ったものである）である。
縦組みの本に `[sidenotes]` を書くと、`縦組みの版面には傍注の領域を設けられません`（G07001）で止まった。
横組みの二段の本では、回り込ませる図版が G07026 で止まり、`wrap` を外すと組めた。

### 試作で見えた相互作用

同じ試作で、次の相互作用が出力に現れた。
どれも、ほかの入力では起きない組み合わせである。

- `functions` の fixture のフィルタ `mark-first`（最初の見出しに圏点を付ける）を、ルビを含む見出しに当てると、`ルビの親文字の圏点は PDF では描きません`（G07045）の notice が出た。フィルタの出力が、ルビと圏点の規則に届いている。
- 横組みの本の目次は、フィルタが付けた圏点と、見出しのルビを、目次の項目にも写して描いた（72 dpi の PNG に描いて見た）。
- 縦組みの本で、回り込ませる図版の後の、罫線を持つ段落は、図版の脇に組まれず、図版の後に置かれた。仕様書の「回り込む図版の脇には、罫線を持つ段落を組まない」のとおりである。
- 縦組みの本の `[index]` を二段にすると、索引だけが二段（上下の段）で組まれた（[docs/adr/0025](0025-index-columns.md) の段数の切り替え）。

試作の PDF は、縦組みが 5 ページ、横組みが 2 ページで、縦組みの本の四つのターゲットを組むのに 0.35 秒かかった（Apple silicon の 10 コアの macOS、負荷の平均は 5 から 7）。
同じマシンで、129 ページの『蟹工船』の PDF は 1.96 秒だった。

## 実装すること

### 二冊にする

fixture は、縦組みの一冊と横組みの一冊の二冊にする（「メンテナーが決めること」の 1）。
書字方向が本で一つなので、縦組みと横組みの相互作用は二冊に分けるほかない。
二冊は、それぞれの版面で使える機能をすべて組み合わせる。

| | `complex-vertical` | `complex-horizontal` |
| --- | --- | --- |
| 判型と版面 | B6、縦組み、本文は一段 | A5、横組み、本文は二段 |
| 段組み | `[index]` の二段で、索引の位置で段数を切り替える | 本文の二段。`[index]` は三段で、段数を切り替える |
| 回り込み | 使う | 使わない（G07026） |
| 傍注 | 使わない（G07001） | 使わない（G07001） |

縦組みの本を一段にし、横組みの本を二段にするのは、組み合わせのうち今の入力にないものを選ぶためである。
横組みの一段の本（回り込みと傍注を含む）は、使い手のマニュアルが組んでいる。
縦組みの二段の本は、「メンテナーが決めること」の 1 の別の案に挙げる。

二冊は、プロジェクトとして別のディレクトリ（`modules/golem-driver/test/fixtures/complex-vertical/` と `complex-horizontal/`）に置く。
プロジェクトのルートの外のファイルは読めない（G03003）ので、原稿を二冊で共有できない。
二冊の原稿は、同じ文章を写さず、それぞれの組み方に合った内容で書く。
縦組みの本は和文の読み物（ルビ、圏点、縦中横の多い文章）、横組みの本は技術書（コード、表、欧文の分綴の多い文章）とする。
Emet の関数を置く `.emet` は、二冊で同じものを要るなら写して持つ。

### 二冊が使う機能

二冊のどちらも、次のものを使う。

- 三階層の見出しと番号、見出しの `rule-before` と `rule-after`。
- 段落スタイルの `rule-before` と `rule-after`。ページ（横組みの本では段）の境で分かれる段落を一つ以上含む（[golem-driver ADR 0035](../golem-driver/adr/0035-paragraph-rules-split-and-space-units.md)）。
- マスターページの柱とノンブル。柱に見出しの番号と題を出す。
- `@toc` の目次。
- ルビ（モノルビとグループルビ）と圏点。見出しの中のルビと圏点を含む。
- 脚注と `[notes.rule]`。脚注の中の `[cite ...]` を含む。
- 図版（SVG と PNG か JPEG）と図番号、`[ref-number]` と `[ref-title]` の相互参照。
- `@table` の表（ファイルから読む表と、原稿に書く表）。ページか段の境で分かれる表を一つ以上含む。
- コードブロック（`@listing` と、原稿に書くコードブロック）。折り返す行と、ページか段の境で分かれるコードブロックを含む。
- 番号付きリストと定義リスト。
- 二階層の索引の印。見出し、脚注、表のセルの中の印を含む。
- `@bibliography` の参考文献（CSL-JSON）。
- Emet の関数（インラインとブロック、`File.read` で TSV を読んで表を作るもの）と、マニフェストの `[[filters]]` のフィルタ。フィルタは見出しを変え、その結果を目次と柱に写す。

縦組みの本は、ほかに縦中横（`[tcy: ...]` と `[number-text ... style=tcy]`）、回り込ませる図版と、その後の罫線を持つ段落、段に収まらずに回す図版（[golem-driver ADR 0034](../golem-driver/adr/0034-fit-figures-to-column.md)）、二倍ダッシュ（[ADR 0172](0172-continuous-double-dashes.md)）を使う。
横組みの本は、ほかに段の下部に置く脚注、段の行長に縮める図版、欧文の分綴とハイフンを使う。

### 大きさとフォント

一冊は 16 ページから 24 ページとする（「メンテナーが決めること」の 3）。
相互作用を起こすのに要るのは、ページと段の境、目次と索引のページ番号、柱の切り替わりであり、ページの数ではない。
ページが増えるほど、ゴールデンの差分が読めなくなり、CI の時間も増える。

フォントは `sample` と `figures` と同じく、`kanikosen` の Noto Serif JP と golem-font の Source Sans Pro を、組む前に `fonts/ja.otf` と `fonts/latin.otf` に写す（[`OutputGoldenSpec` の `copyFonts`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/test/OutputGoldenSpec.hs#L84-L88)）。
fixture にはフォントをコミットしない。
コードの書体の役割（`[fonts.code]`）にも同じ二つを書き、G08008 の notice を出さない。
等幅のフォントはリポジトリにないので、コードの書体の違いは使い手のマニュアルに任せる。

### diagnostics

二冊は、どのターゲットでも diagnostic を一つも出さない（「メンテナーが決めること」の 4）。
ゴールデンのテストは、`buildOne` の断言（[`OutputGoldenSpec`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/test/OutputGoldenSpec.hs#L119-L123)）で、diagnostics が空であることを確かめる。
相互作用が notice を出す組み合わせ（試作の G07045 など）は、原稿で避ける。
変更が新しい notice を出すようになれば、テストが落ちて気付ける。

### 固定する検査

二冊を、次の三つの検査の入力に加える。

- **出力のゴールデン**：`OutputGoldenSpec` に、二冊の PDF と EPUB のゴールデン（`pdf-complex-vertical.txt`、`epub-complex-vertical.txt`、`pdf-complex-horizontal.txt`、`epub-complex-horizontal.txt`）を足す。形は `sample` と `figures` のゴールデンと同じである。
- **決定性の検査**：`scripts/determinism.sh` で、二冊を四つのターゲット（PDF、HTML、EPUB、テキスト）で組み、`--format json` の標準出力と標準エラー出力、終了コードとともに一覧に書く。`scripts/env-determinism/check.sh` には、小さな入力として加え、プルリクエストの `--quick` でも検査する（[ADR 0038](0038-env-determinism-quick-on-pull-requests.md)）。
- **見た目の回帰テスト**：`scripts/visual/build.sh` の入力に `complex-vertical` と `complex-horizontal` を足し、参照の `scripts/visual/pages/complex-vertical.txt` と `complex-horizontal.txt` を同じプルリクエストに入れる。フォントは `build.sh` の `fonts` で写す。

新しい CI のジョブは作らない（「メンテナーが決めること」の 5）。

### ゴールデンの更新のレビュー

二冊のゴールデンと参照の更新には、新しい仕組みを足さない（「メンテナーが決めること」の 6）。
[ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md) と同じく、参照とゴールデンの差分そのものが、変わったことの記録になる。
レビューでは、CI の要約と成果物にある、変わったページの前後の画像と差分の画像（[ADR 0096](0096-before-and-after-images-of-changed-pages.md)）を見る。

二冊は多くの機能を一度に使うので、一つの変更で多くのページが変わりやすい。
そのため、二冊の参照を書き直すプルリクエストは、説明に、変わったページと、変わった理由（どの機能の変更か）を書く。
これは CONTRIBUTING.md の約束として書き、スクリプトでは検査しない。

### 文書

- fixtures の README（`modules/golem-driver/test/fixtures/README.md`）に、二冊の行と、二冊が使う機能、一冊にしない理由、フォントの写し方を書く。
- [docs/specifications.md](../specifications.md) の見た目の回帰テストの段落の入力の数（17）と一覧を、19 に直す。
- README の Development の節と、開発者のマニュアルの「CI のジョブ」の章（`determinism.sh` と `visual` の入力の一覧）と「決定性を守る」の章（見た目の回帰テストの入力）を、二冊を含めて直す。
- CONTRIBUTING.md に、二冊の参照を書き直すときにプルリクエストの説明に書くことを足す。
- ロードマップの rc4 の「複雑な組版の fixture」の項目を、実装の後に消す。
- ロードマップの v1.x の節に、二冊より複雑な組版の例を以降のバージョンで扱う項目を置く（「決めたことの記録」）。項目がまだなければ足し、すでにあれば文言を次に揃える。

  > **より複雑な組版の fixture**：v0.1.0-rc4 で作る二冊の fixture（縦組みの一段の本と、横組みの二段の本）より複雑な組版の例を作り、fixture に入れる。二冊が組み合わせていない機能、たとえば縦組みの本文の段組みや、章ごとの書字方向と段数の切り替えのように後から足す機能を組み合わせ、機能のあいだの相互作用を、出力のゴールデン、決定性の検査、見た目の回帰テストで固定する。どの組み合わせを足すかと、fixture の数と大きさは、着手するときに ADR で決める。

## 実装しないこと

- 二冊より複雑な組版の例。以降のバージョンで扱い、ロードマップの v1.x に項目を置く（「決めたことの記録」）。
- 一冊の中で書字方向や本文の段数を切り替えること。章ごとの書字方向と段数は、組版の機能の追加であり、別の ADR で決める。
- 傍注。どちらの本の版面にも置けず、横組みの一段の本で使い手のマニュアルが組んでいる。
- プラグイン。プラグインの配布物（wasm）をビルドする手順が要り、プラグインの経路は `golem-driver` の別のテストが受け持つ。
- トンボと塗り足し。『蟹工船』の日本式のトンボの入力が受け持つ。
- PDF の図版と、PNG の色の種類。`figures` が受け持つ。
- 等幅のフォントをリポジトリに足すこと。
- 二冊の HTML とテキストのゴールデン。EPUB のゴールデンが XHTML と CSS を含み、決定性の検査が四つのターゲットのハッシュを比べる。
- 二冊の原稿を、パブリックドメインの本のように変換のスクリプトで作ること。機能を狙って置くので、手で書く。
- 閾値のある画像の比較。[ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md) のとおり、完全な一致で比べる。

## テスト設計

テストを先に書き、fixture がない今の main で失敗することを確かめてから、fixture を書く。

- `OutputGoldenSpec` の四つのゴールデンのテスト。fixture とゴールデンのファイルがないので、今は失敗する。fixture を書いた後に `--accept` でゴールデンを作り、作ったゴールデンを人が読んで、各機能が出力に現れていることを確かめる（ルビと圏点の描画、脚注と区切り線、索引と目次のページ番号、参考文献の項目、Emet の関数の出力）。
- 二冊のそれぞれで、diagnostics が空であること（`buildOne` の断言）。
- 二冊が「二冊が使う機能」のすべてを使うことを、原稿を読む golem-driver のテストで断言する。fixture の原稿と `style.toml` を読み、各機能の記法（`[ruby`、`[kenten`、`@figure` の `wrap`、`rule-before` など）が一つ以上あることを確かめる。後の変更で原稿から機能が抜けたときに気付くためである。
- `scripts/visual/test.sh` に、`build.sh --list` が `complex-vertical` と `complex-horizontal` を含み、`build.sh` が二冊にフォントを写すことの検査を足す。
- `scripts/determinism.sh` の一覧に二冊の行が現れること。決定性の検査の CI（x86-64 と aarch64）で一致すること。

自動のテストにできない次のことは、実装のプルリクエストで確かめて記録する。

- 二冊の全ページを 72 dpi で描き、各機能が見た目にも現れ、崩れていないこと。崩れていた場合は、fixture で隠さず、不具合として roadmap か既知の不具合に載せる。
- 二冊を加えた後の CI の `visual` と `determinism` のジョブの時間を、加える前の直近の実行と比べること。

## トレードオフ

二冊に分けるので、縦組みと横組みの相互作用（縦組みの本の中の横組みの章など）は固定できない。
今の Golem にない機能なので、固定するものがない。
章ごとの書字方向を足すときに、この fixture に章を足す。

本文を二段にした横組みの本には、回り込みと傍注を置けない。
回り込みと段組みの相互作用（G07026 のエラーそのもの）は、golem-driver の単体のテストが受け持つ。

原稿に機能を詰め込むので、ある機能の変更が、関係のない機能の多いページを動かす。
二冊の参照とゴールデンは、ほかの入力より頻繁に書き直すことになる。
その代わり、機能の組み合わせで起きる崩れが、どの検査にも見つからないまま残ることを減らせる。

PDF のゴールデンは、`sample`（3 ページ）で 26,224 バイト、`figures`（8 ページ）で 30,119 バイトある。
二冊の PDF のゴールデンは、ページの数から見て、一冊で 100 KB 前後になると見込む（推測であり、測っていない）。
差分は大きくなるが、ストリームを伸長したテキストなので、どのページのどの描画命令が変わったかは読める。

CI の時間は、試作の組版の時間と『蟹工船』の時間から見て、二冊を組むのに一回あたり数秒、見た目の回帰テストの描画に 1,779 ページの 2 % ほどが増えると見込む（推測）。

フォントをコミットしないので、fixture のディレクトリで `golem build` を打っても、フォントを写すまで組めない。
`figures` と同じ扱いであり、README に写し方を書く。

## 決めたことの記録

- **fixture を作ること**（ロードマップ、v0.1.0-rc4）：Golem で今できる組版の機能を組み合わせた fixture を作り、出力のゴールデンと決定性の検査で相互作用を固定し、見た目の回帰テストの入力にも同じプルリクエストで加える。
- **二冊に分けること**（2026-11-07、メンテナー）：「2 冊にわけて問題ない」。縦組みの一段の本と横組みの二段の本の二冊にする。
- **より複雑な例**（2026-11-07、メンテナー）：より複雑な例は以降のバージョンで扱い、さらに複雑な組版をロードマップに入れるとした。実装は、ロードマップの v1.x に「より複雑な組版の fixture」の項目を置く。
- **ほかの項目**（2026-11-07、メンテナー）：「ほかは問題なし」。「メンテナーが決めること」の 2 から 6 を、すべて推奨のとおりとした。

## メンテナーが決めること

すべて決めた（「決めたことの記録」）。

1. **一冊にするか、二冊にするか**：決めた。推奨のとおり、縦組みの一段の本と、横組みの二段の本の二冊にする。より複雑な例は、以降のバージョンで扱う（「決めたことの記録」）。
   - 退けた案（一冊、縦組みの一段）：縦組みの本の柱、回した図版、回転した欧文で「横組み」を代える。横組みの本文と本文の段組みがどの入力にもないまま残る。
   - 退けた案（一つの原稿から `style.toml` を替えて二冊を組む）：`kanikosen-marks-japanese` と同じく、スクリプトで `style.toml` を差し替える。原稿を共有できるが、回り込みの図版が段組みの版で G07026 になるので、原稿もスクリプトで書き換えることになる。原稿の書き換えは、テストとスクリプトの三か所（`OutputGoldenSpec`、`determinism.sh`、`visual/build.sh`）で揃える必要があり、壊れやすい。
   - 退けた案（三冊、縦組みの二段の本も足す）：縦組みの本文の段組みも固定できるが、原稿とゴールデンが一冊分増える。縦組みの二段は、二冊の後に足せる。
2. **置き場所と名前**：決めた。推奨のとおり、`modules/golem-driver/test/fixtures/complex-vertical/` と `complex-horizontal/` とする。見た目の回帰テストの入力の名前もこれに合わせる（「決めたことの記録」）。
   - 退けた案（`complex/vertical/` と `complex/horizontal/`）：入力の名前とディレクトリの名前がずれ、`build.sh` の `copy` に階層を足すことになる。
3. **大きさ**：決めた。推奨のとおり、一冊 16 ページから 24 ページとする（「決めたことの記録」）。
   - 退けた案（マニュアルと同じ程度、100 ページ以上）：機能の数は増えず、ゴールデンが読めなくなる。
   - 退けた案（8 ページ以下）：目次、索引、参考文献の前付けと後付けだけでページが埋まり、ページと段の境をまたぐ表、コード、罫線を持つ段落を置く余地がない。
4. **diagnostics**：決めた。推奨のとおり、一つも出さない（「決めたことの記録」）。
   - 退けた案（相互作用の notice を一つ以上わざと出し、`buildOne` で固定する）：試作の G07045 のような相互作用を固定できるが、notice は原稿の側で取り除くものであり、fixture を「よい原稿」の例として読めなくなる。notice の条件は golem-driver の単体のテストが受け持つ。
5. **CI の費用**：決めた。推奨のとおり、今のジョブ（golem-driver のテスト、`determinism`、`env-determinism`、`visual`）に入力として足し、新しいジョブを作らない。`env-determinism` では小さな入力とし、プルリクエストでも検査する（「決めたことの記録」）。
   - 退けた案（`GOLEM_PD_BOOKS` のような環境変数で、手元と `main` への push だけで組む）：二冊は数秒で組めると見込むので、プルリクエストで見つけられる崩れを `main` まで遅らせる理由がない。
6. **ゴールデンの更新のレビュー**：決めた。推奨のとおり、新しい仕組みを作らず、[ADR 0096](0096-before-and-after-images-of-changed-pages.md) の前後の画像を見て、プルリクエストの説明に変わったページと理由を書く（「決めたことの記録」）。
   - 退けた案（CODEOWNERS で、二冊のゴールデンの変更にメンテナーの承認を求める）：リポジトリには CODEOWNERS がなく、承認の運用を新しく作ることになる。この fixture だけを特別に扱う理由が弱い。
   - 退けた案（変わったページの数が閾値を超えたら、CI を落とす）：意図した変更でも落ち、`--accept` の手順が増えるだけになる。

## 参考文献

- [docs/roadmap.md](../roadmap.md) の v0.1.0-rc4 の「複雑な組版の fixture」
- [ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md)、[ADR 0096](0096-before-and-after-images-of-changed-pages.md)、[ADR 0064](0064-goldens-that-fix-less-than-the-output.md)、[ADR 0071](0071-determinism-check-compares-diagnostics.md)、[ADR 0029](0029-environment-variation-determinism-test.md)、[ADR 0038](0038-env-determinism-quick-on-pull-requests.md)
- [docs/adr/0025](0025-index-columns.md)、[ADR 0162](0162-calling-emet-functions-from-gm.md)、[ADR 0172](0172-continuous-double-dashes.md)
- [golem-driver ADR 0027](../golem-driver/adr/0027-paragraph-style-rules.md)、[golem-driver ADR 0034](../golem-driver/adr/0034-fit-figures-to-column.md)、[golem-driver ADR 0035](../golem-driver/adr/0035-paragraph-rules-split-and-space-units.md)
- [modules/golem-driver/test/fixtures/README.md](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/test/fixtures/README.md)
