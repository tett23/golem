# ADR 0234: HTML と golem.wasm を、版を固定したヘッドレスの Chromium と、ランナーの Safari と、Deno と wasmtime で夜ごとに確かめる

ステータス: 採択（未実装）

## 文脈

[docs/roadmap.md](../roadmap.md) の「手で確かめる項目」には、Safari と Chrome で開くことを求める項目が八つある。

| 項目 | ブラウザで確かめること |
| --- | --- |
| 縦組みのダッシュ | 縦組みの HTML のダッシュの向きが PDF と同じこと |
| コードブロックの見え方 | HTML と EPUB の `pre` と `code` の見え方 |
| 技術書のコードブロックの見え方 | 行番号と差分の印が、選択とコピーに含まれないこと |
| 二冊のマニュアルの HTML と PDF | 二冊のマニュアルの HTML |
| 組版の新しい機能の見え方 | 圏点の HTML、段落の罫線が段落の前後に出ること |
| PNG の tRNS の見た目 | PDF と同じ画素が透明になること |
| SVG の図版の見た目 | 輪郭の SVG と原稿の SVG の、文字の位置、縦書きの字の向き、太字が一致すること |
| wasm の版をブラウザで組むこと | `browser_wasi_shim` で kanikosen を組み、PDF の SHA-256 がネイティブと同じこと。wasmtime と Deno で動くこと |

CI にブラウザは一つもない。
[ADR 0217](0217-html-spaces-of-paragraph-styles-redefined-in-files.md) は、ヘッドレスのブラウザーで計算した値を読む案を、「CI にブラウザーを足すことになり、版によって結果が変わりうる」として退けている。
Chromium では、どちらの懸念も版を固定すれば小さくなる。
Safari では版を固定できず、二つめの懸念は残る。
この ADR は、それを受け入れて Safari も CI で確かめる（「決めたことの記録」の 4）。

### 問いの多くは、計算した値か画素で答えられる

八つの項目を、ブラウザが返す値で言い直すと次のようになる。

- 行番号が選択に含まれないことは、`pre` の全体を `Range` で選んだときの `getSelection().toString()` が、コードの文字列そのものであることと同じである。
- 段落の罫線が段落の前後に出ることは、罫線の要素の `getBoundingClientRect()` が、段落の矩形の上か下にあることと同じである。
- 圏点の形は、`getComputedStyle` の `text-emphasis-style` で読める。
- tRNS の透明の画素は、ページの画像を撮り、その位置の画素が背景の色であることで確かめられる。
- 縦組みのダッシュの向きは、ダッシュだけの要素の画像を撮り、墨の画素の外接矩形が縦に長いかで判定できる。
- 輪郭の SVG と原稿の SVG の文字の位置は、二つを同じ大きさで撮り、原稿の `text` の要素の `getBBox()` の範囲の墨の画素を比べれば確かめられる。

「見え方」のうち、見た目の良し悪しの判断だけは、値に言い直せない。
値と画像は、Chromium でも Safari でも同じ方法で取れる。
違うのは、ブラウザを操る規約だけである。

### wasm の項目は、ブラウザと二つの実行環境の話である

`ci.yml` の `wasm` ジョブは、`node:wasi` で golem.wasm を動かし、`scripts/wasm/compare.sh` でネイティブの golem と PDF と diagnostics の SHA-256 を比べている（[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md)）。
比べる仕組みはすでにあり、足りないのは `node:wasi` 以外の WASI の実装で golem.wasm を動かす入口である。

- **ブラウザ**：`browser_wasi_shim`（MIT と Apache-2.0）が、ブラウザの中で WASI の preview 1 を実装する。npm の `@bjorn3/browser_wasi_shim` にある。JavaScript だけで書かれているので、Chromium でも Safari でも同じものを読める。
- **Deno**：Deno は GitHub の denoland/deno のリリースに、版ごとの zip を置いている（MIT）。
- **wasmtime**：Golem はすでに wasmtime 49.0.5 の C API をリンクしており、その版は `scripts/fetch-wasmtime.sh` が固定している。同じリリースに CLI のアーカイブもある（Apache-2.0 と LLVM の例外）。

### 版を固定したブラウザと、固定できないブラウザ

Google の Chrome for Testing は、版ごとに Linux の x86-64 の `chrome-headless-shell` の zip を配っている。
版の番号で URL が決まり、同じ版の zip は変わらないので、`fetch-shem.sh` と同じく、版と SHA-256 をスクリプトに書いて検査できる。

Safari は、macOS のランナーの像に入っているものしかなく、版を選べない。
2026-11-08 の runner-images の macOS 15 の一覧には、Safari 27.2 と SafariDriver 27.2 がある。
Safari の版は、像の更新に従って変わる。
`safaridriver` は Safari に同梱されており、`safaridriver --enable` で遠隔の操作を許すと、W3C WebDriver の規約で Safari を操れる（Apple の「Testing with WebDriver in Safari」）。
Safari にはヘッドレスの動かし方がなく、ウィンドウを開いて動く。

ブラウザを操る道具（Puppeteer、Playwright、Selenium）は入れない。
Chromium は Chrome DevTools Protocol（CDP）で操る。
CDP は WebSocket の上の JSON-RPC であり、Node の LTS には `WebSocket` が組み込まれている。
使う命令は、`Page.navigate`、`Runtime.evaluate`、`Page.captureScreenshot`、`Runtime.consoleAPICalled` と `Network.loadingFailed` の受け取りの五つほどで、小さな CDP のクライアントを書けば足りる。
Safari は CDP を話さず、`safaridriver` の WebDriver で操る。
WebDriver は HTTP の上の JSON であり、Node の LTS の組み込みの `fetch` で足りる。
使うのは、セッションの作成と削除、`Navigate To`、`Execute Script`、`Execute Async Script`、`Take Screenshot`、`Set Window Rect` の七つほどである。
WebDriver には、コンソールの誤りと読み込みの失敗を受け取る命令がない。

### 夜ごとの実行

ブラウザの zip と、wasm の実行は、どちらも軽くない。
`wasm` ジョブはキャッシュがあっても 4 分ほどかかる（2026-11-08 の `main` の run 42444096822）。
プルリクエストのたびに Chrome で golem.wasm を組むと、5 分の方針に収まらない。
`race.yml` と `enum.yml` は、`schedule` で夜ごとに走り、前の実行の後に `main` が進んでいなければ何もしない。
同じ形にすれば、プルリクエストの CI の時間を変えずに済む。

Safari のジョブは macOS のランナーで走る。
Golem のリポジトリは公開されており、公開のリポジトリの標準の GitHub-hosted runner は、macOS でも課金されない（GitHub の「GitHub Actions billing」）。
費用として残るのは、macOS のランナーを待つ時間と、同時に走る macOS のジョブの数である。
`ci.yml` の `scripts-macos` と `release.yml` もすでに `macos-15` を使っている。
夜ごとのジョブはプルリクエストの CI の外にあるので、5 分の方針には入らない。

## 実装すること

### 1. Chromium の取得

`scripts/browser/fetch-chromium.sh` を足す。
Chrome for Testing の `chrome-headless-shell` の版と、Linux の x86-64 の zip の SHA-256 をスクリプトに書き、取った zip をその SHA-256 で検査してから `third_party/chromium/` に展開する。
`fetch-shem.sh` と同じく、`third_party/chromium/VERSION` が今の版と SHA-256 なら取らない。
版を上げるときは、版と SHA-256 を同じプルリクエストで変え、3 から 5 のテストが通ることを確かめる。

### 2. ブラウザを操るクライアント

`scripts/browser/` に、二つの小さなクライアントと、ファイルを配るサーバーを足す。
どれも Node の LTS の組み込みのもの（`WebSocket`、`fetch`、`http`、`child_process`）だけを使い、npm のパッケージを要らない。

- `cdp.mjs`：`chrome-headless-shell --remote-debugging-port=0 --user-data-dir=<一時ディレクトリ>` を起動し、標準エラーの `DevTools listening on` の行から URL を読む。
- `webdriver.mjs`：`safaridriver --port <空いた番号>` を起動し、W3C WebDriver の HTTP の命令を送る。Safari は一度に一つのセッションしか持てないので、検査のすべてを一つのセッションで順に走らせる。セッションの作成の応答の `browserVersion` を返す。
- `serve.mjs`：検査するファイルを `127.0.0.1` の空いた番号で配る。`file://` の扱いはブラウザごとに違い、`file://` からの `fetch` は Chromium でも拒まれる。`127.0.0.1` は安全な文脈なので、`crypto.subtle` で SHA-256 を計算できる。二つのブラウザとも、このサーバーの URL を開く。

二つのクライアントは、同じ形の関数の組を返す。
関数は六つあり、URL を開くもの、式を評価して値を返すもの、非同期の式を評価して値を返すもの、ウィンドウの大きさを決めるもの、画像を撮るもの、終えるものである。
加えて `cdp.mjs` だけが、コンソールの誤りと読み込みの失敗の一覧を返す。
`webdriver.mjs` は、その一覧の代わりに「取れない」ことを返す。
3 から 5 の検査は、この組だけを受け取り、どちらのブラウザかで分岐しない。
スクリプトの引数で、ブラウザ（`chromium` か `safari`）と、どの検査を走らせるかを選ぶ。

画像の大きさは、ウィンドウの大きさと `devicePixelRatio` で決まる。
Safari では倍率を決められないので、検査は撮った画像の画素を `devicePixelRatio` で CSS の座標に戻してから比べる。

### 3. HTML の検査

`scripts/browser/html-checks.mjs` に、次の検査を置く。
どの検査も、golem で組んだ HTML を一時ディレクトリに置き、`serve.mjs` で配って開く。
Chromium と Safari のそれぞれで、すべての検査を走らせる。

- **選択とコピー**：技術書のコードブロックの fixture で、`pre` の全体を選んだ文字列に、行番号と差分の印の文字がなく、原稿のコードの文字列と一致すること（[golem-driver ADR 0023](../golem-driver/adr/0023-code-block-book-features.md)）。`user-select: none` の扱いはブラウザごとに違うので、Safari で走らせる意味が大きい。
- **`pre` と `code`**：コードブロックの `white-space` が `pre` か `pre-wrap` で、`font-family` の先頭が style.toml のコードの書体であり、`document.fonts` でその書体が読み込まれていること（[golem-driver ADR 0017](../golem-driver/adr/0017-pdf-code-blocks.md)）。
- **縦組みのダッシュ**：縦組みの HTML のダッシュだけの要素を撮り、墨の外接矩形の高さが幅より大きいこと（[golem-driver ADR 0015](../golem-driver/adr/0015-vertical-dashes.md)）。
- **圏点**：十の形のそれぞれの `text-emphasis-style` が、[golem-driver ADR 0019](../golem-driver/adr/0019-pdf-kenten-shapes.md) の HTML の対応のとおりであること。検査は、golem が書く名前のプロパティだけを読み、接頭辞のついた名前に代えて読まない。ブラウザが golem の書く名前を解さなければ、それは検査の失敗として出る。
- **段落の罫線**：罫線を付けた段落の罫線の矩形が、段落の矩形の前か後にあり、横組みでは上下、縦組みでは左右にあること（[golem-driver ADR 0027](../golem-driver/adr/0027-paragraph-style-rules.md)）。
- **tRNS**：figures の fixture の HTML を撮り、tRNS を持つ 4 枚の PNG の透明の画素の位置が、ページの背景の色であること（[golem-pdf ADR 0014](../golem-pdf/adr/0014-png-trns-transparency.md)）。
- **マニュアル**：二冊のマニュアルの HTML のすべてのページを開き、読み込みの失敗がないことと、ページの中の `#` のリンクの先の `id` があることを確かめる（[ADR 0024](0024-manual-audiences-and-policy.md)）。読み込みの失敗は、どちらのブラウザでも、ページの中の値で確かめる。すべての `img` の `complete` が真で `naturalWidth` が 0 でないこと、すべてのスタイルシートの `link` の `sheet` があること、`document.fonts.ready` の後にすべての書体の `status` が `loaded` であることである。Chromium では、加えてコンソールの誤りと `Network.loadingFailed` がないことを確かめる。Safari では、この二つは取れないので確かめない。

### 4. SVG の文字の位置

`scripts/browser/svg-text.mjs` を足す。
開発者のマニュアルの原稿の SVG（`manual-dev/images/src/`）と、`scripts/manual/outline-figures.sh` が文字を輪郭にした SVG（`manual-dev/images/`）の組を、同じ大きさ（SVG の大きさの 2 倍の CSS の大きさ）に描いて撮る。
Chromium と Safari のそれぞれで走らせる。
原稿の SVG の `text` の要素ごとに `getBBox()` の矩形を読み、その矩形を少し広げた範囲の中の墨の画素の外接矩形を、二つの画像のそれぞれで求める。
比べるのは、外接矩形の中心の差と大きさの差が、それぞれ CSS の 1 画素以下であることである。
中央揃えと `dominant-baseline: central` の位置の誤りは中心の差に、太字の落ちは墨の画素の数の差に、縦書きの字の向きの誤りは外接矩形の縦と横の比に出る。
墨の画素の数の差の上限は、実装のプルリクエストで今の六つの図について二つのブラウザで測り、ADR の記録に足す。
上限は二つのブラウザで共通の一つの値とし、ブラウザごとに変えない。

### 5. golem.wasm の四つの実行環境

`scripts/wasm/` に、Deno と wasmtime とブラウザの入口を足す。

- Deno の入口：`run.mjs` が Deno の Node 互換の `node:wasi` でそのまま動くかを、実装の最初に確かめる。動けば `deno run` で `run.mjs` を走らせ、動かなければ `browser_wasi_shim` を Deno で読む `run-deno.mjs` を書く。どちらにしたかと理由を、`scripts/wasm/README` に書く。
- `run-wasmtime.sh`：wasmtime の CLI の `--dir` でプロジェクトを渡して動かす。
- `browser/run.html` と `run-browser.mjs`：`browser_wasi_shim` で golem.wasm を読み、プロジェクトのファイルをメモリの上のファイルシステムに置いて組み、PDF の SHA-256 を返す。`serve.mjs` で配り、`cdp.mjs` か `webdriver.mjs` で開く。同じ `run.html` を Chromium と Safari の両方で開く。

`compare.sh` に `--deno`、`--wasmtime`、`--browser chromium`、`--browser safari` を足し、今の `node:wasi` の一覧と同じ形の一覧を書く。
夜ごとのジョブは、四つの一覧のそれぞれを、同じコミットのネイティブの一覧と `compare.sh --check` で比べる。

`browser_wasi_shim` は、`tools/editors` と同じく、`scripts/browser/package.json` と `package-lock.json` で版を固定する。
Deno と wasmtime の CLI は、1 と同じく版と SHA-256 で取る。

### 6. 夜ごとのワークフロー

`.github/workflows/browser.yml` を足す。

- `schedule` で一日に一度と、`workflow_dispatch` で走る。前の実行の後に `main` が進んでいなければ、`race.yml` と同じく何もしない。
- ジョブは `prepare`、`chromium`、`safari` の三つにする。`chromium` と `safari` は、どちらも `prepare` だけを待つ。片方の失敗が、もう片方の実行を止めない。
- `prepare`（`ubuntu-24.04`）：最新の成功した `main` の `ci.yml` の実行から、成果物 `golem-wasm`、`wasm-native-list`、`manual`、`manual-dev`、[ADR 0231](0231-run-the-lsp-and-the-editor-grammars-in-headless-neovim-and-helix.md) の `golem-linux-x86_64` を取る。ビルドはしない。3 の fixture の HTML を `golem` で組み、取った成果物と合わせて成果物 `browser-inputs` に上げる。
- `chromium`（`ubuntu-24.04`）：`browser-inputs` を取り、3、4、5 の Chromium と Deno と wasmtime の検査を走らせる。
- `safari`（`macos-15`）：`browser-inputs` を取り、`sudo safaridriver --enable` の後に、3、4、5 の Safari の検査を走らせる。Deno と wasmtime は走らせない。`golem` を macOS で組まないので、ネイティブの golem は要らない。
- `safari` のジョブは、検査の前に版を記録する。`scripts/browser/safari-versions.sh` が、`sw_vers` の macOS の版とビルドの番号、ランナーの環境変数 `ImageOS` と `ImageVersion`、`/Applications/Safari.app/Contents/Info.plist` の `CFBundleShortVersionString` と `CFBundleVersion` を表にして、`$GITHUB_STEP_SUMMARY` に書く。WebDriver のセッションの `browserVersion` も、同じ表に足す。検査が途中で失敗しても、表は残る。
- `chromium` のジョブも、固定した Chromium の版を `$GITHUB_STEP_SUMMARY` に書く。
- 失敗した実行が知らせになる。`safari` のジョブに `continue-on-error` を付けない。
- `timeout-minutes` は、実装のプルリクエストで三つのジョブの時間を測り、その倍ほどにする。測った時間を、ADR の記録に足す。

[ADR 0231](0231-run-the-lsp-and-the-editor-grammars-in-headless-neovim-and-helix.md) が採択されない場合は、このワークフローが `golem` を作るか、`ci.yml` の `outputs` の runner に `golem` の成果物を上げるステップをこの ADR で足す。

`safari` のジョブが失敗したら、まずジョブの要約の表を前の成功した実行の表と比べる。
Safari か像の版が変わっていれば、Safari の更新を疑う。
直し方は、そのときに決める。
golem の HTML を直すこともあれば、検査を直すこともある。
検査を緩めるか外すときは、その変更のプルリクエストに理由を書く。

### 7. ロードマップと文書

- 「技術書のコードブロックの見え方」から、Safari と Chrome の選択とコピーを外す。
- 「コードブロックの見え方」から、Safari と Chrome の `pre` と `code` を外す。
- 「縦組みのダッシュ」と「組版の新しい機能の見え方」の圏点と段落の罫線から、Safari と Chrome を外す。
- 「PNG の tRNS の見た目」から、Safari と Chrome を外す。
- 「SVG の図版の見た目」から、輪郭の SVG と原稿の SVG を Chrome で並べることを外す。
- 「二冊のマニュアルの HTML と PDF」から、HTML をブラウザで開くことを外す。
- 「wasm の版をブラウザで組むこと」の項目を外す。Safari、Chrome、wasmtime、Deno のすべてを CI が確かめるので、残るものがない。README と `scripts/wasm/README` の「見込み」の記述を、確かめた版の記述に改める。
- ブラウザの部分を外した後も、PDF を Acrobat で見ることや、見た目の良し悪しを目で見ることは、それぞれの項目に残す。
- 仕様書の CI の節と CONTRIBUTING.md の GitHub Actions の節に、`browser.yml` を足す。Safari の版は固定せず、ランナーの像に従うことと、ジョブの要約に版を記録することを書く。

## 実装しないこと

- Safari の版を固定すること。macOS のランナーの像に入っているものしか使えない。
- macOS のランナーで Chromium、Deno、wasmtime を走らせること。版を固定したものは、Linux の一か所で確かめれば足りる。
- WebKit を Linux で動かすこと（WebKitGTK、Playwright の WebKit）。利用者が開くのは macOS と iOS の Safari である。
- Safari で、コンソールの誤りを集めること。WebDriver に命令がなく、ページを読んだ後に聞き手を足しても、読み込みの間の誤りを取りこぼす。
- iOS の Safari を、シミュレーターで動かすこと。
- Puppeteer、Playwright、Selenium を依存に入れること。使う命令は少なく、2 のクライアントで足りる。
- EPUB を読書環境（Apple Books、Kobo、Kindle、Thorium Reader）で開くこと。
- 見た目の良し悪しを、画像の比べ合わせで判断すること。
- `browser.yml` をプルリクエストで走らせること。
- Safari の失敗を、自動で再実行するか、無視すること。

## 不変条件

| 番号 | 不変条件 |
| --- | --- |
| I1 | 技術書のコードブロックの HTML で、`pre` の全体を選んだ文字列は、Chromium でも Safari でも、原稿のコードの文字列と一致する。 |
| I2 | 二冊のマニュアルの HTML のすべてのページで、Chromium でも Safari でも、読み込みに失敗した画像、スタイルシート、書体はなく、`#` のリンクの先の `id` はある。Chromium では、加えてコンソールの誤りも `Network.loadingFailed` もない。 |
| I3 | tRNS の透明の画素は、Chromium でも Safari でも、HTML でページの背景が見える。 |
| I4 | 開発者のマニュアルの輪郭の SVG の文字は、Chromium でも Safari でも、そのブラウザで描いた原稿の SVG の文字と、CSS の 1 画素以下の差の位置と大きさにある。 |
| I5 | golem.wasm は、`node:wasi`、Deno、wasmtime、Chromium の `browser_wasi_shim`、Safari の `browser_wasi_shim` のどれで動かしても、`compare.sh` の入力のすべてで、ネイティブの golem と同じ PDF と diagnostics を出す。 |
| I6 | 3 から 5 の検査は、どちらのブラウザでも同じ関数で走り、同じ入力に同じ合否の基準を当てる。ブラウザで変わるのは、Safari でコンソールの誤りと `Network.loadingFailed` を確かめないことだけである。 |
| I7 | `safari` のジョブの要約には、検査が通っても失敗しても、macOS の版、`ImageVersion`、Safari の版、`browserVersion` がある。 |

境界の入力は次のとおりである。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| 空のコードブロック | 選んだ文字列は空で、検査は通る | I1 |
| 一行のコードブロックで、行番号だけ `user-select: none` | 選んだ文字列はその一行 | I1 |
| 行番号を `user-select: none` にしないコードブロック | 検査が失敗する | I1 |
| 画像を一枚も持たないページ | 読み込みの失敗はなく、通る | I2 |
| 存在しない画像を一枚だけ参照するページ | 両方のブラウザで失敗する | I2 |
| ページを読んだ後に `console.error` を一度だけ呼ぶページ | Chromium で失敗し、Safari では通る | I2、I6 |
| 透明の画素の上に色を塗ったページ | 検査が失敗する | I3 |
| 文字の中心の差がちょうど CSS の 1 画素 | 通る | I4 |
| 文字の中心の差が CSS の 1 画素を一つ超える | 失敗する | I4 |
| `devicePixelRatio` が 1 と 2 | 同じ合否になる | I4、I6 |
| `compare.sh` の入力のうち一つだけ PDF の SHA-256 が違う | その実行環境の比べ合わせが失敗する | I5 |
| `safaridriver` のセッションの作成が失敗する | ジョブは失敗し、要約には `browserVersion` 以外の版がある | I7 |

## テスト設計

`cdp.mjs`、`webdriver.mjs`、`html-checks.mjs`、`svg-text.mjs` には、`node --test` のテストを先に書いて失敗させる。
テストの名前には、不変条件の番号を入れる。
テストは `scripts/browser/test/` に、手で書いた小さな HTML を置く。

- I1：行番号を `user-select: none` にしない HTML で、選択とコピーの検査が失敗すること。空のコードブロックで通ること。
- I2：存在しない画像を参照する HTML で、マニュアルの検査が読み込みの失敗を報告すること。読み込めない書体を指す HTML で、書体の失敗を報告すること。
- I3：透明の画素の上に色を塗った HTML で、tRNS の検査が失敗すること。
- 縦組みのダッシュ：横に倒したダッシュの HTML で、縦組みのダッシュの検査が失敗すること。
- I4：文字を 2 画素ずらした輪郭の SVG の組で、SVG の検査が失敗すること。1 画素ずらした組で通ること。
- I6：上の HTML のテストを、同じテストの関数で `chromium` と `safari` の両方について走らせる。Safari の側で、コンソールの誤りの HTML が通ることも確かめる。

ブラウザを要るテストは、`browser.yml` で走らせる。
`chromium` のジョブは `chromium` の側を、`safari` のジョブは `safari` の側を走らせる。

`webdriver.mjs` の命令の形と、誤りの応答の扱いは、`127.0.0.1` に立てた偽の WebDriver のサーバーで確かめる。
このテストは Safari を要らないので、`prepare` のジョブで走らせる。

I7 は、`safari-versions.sh` に fixture の `Info.plist` と環境変数を渡し、表の行がそろうことを `scripts/ci/test.sh` で確かめる。
`Info.plist` を読むのに macOS の道具を使うので、このテストは `ci.yml` の `scripts-macos` で走らせる。
`fetch-chromium.sh` と `compare.sh` の新しい引数の、引数の誤りと SHA-256 の不一致の扱いも、`scripts/ci/test.sh` に足し、プルリクエストの CI で走らせる。

5 は、`node:wasi` の一覧と同じ形の一覧を書くことを、`compare.sh` の今のテストに足す。
四つの実行環境のどれかで一覧が違えば、それは I5 の破れであり、golem.wasm か入口の誤りか、Safari ではその版の振る舞いである。

`sudo safaridriver --enable` の後に macOS のランナーで Safari がウィンドウを開いて動くことは、自動のテストにできない。
実装のプルリクエストで `workflow_dispatch` から `browser.yml` を走らせ、`safari` のジョブが通ることと、要約に版の表が出ることを確かめる。

## トレードオフ

Chromium の版を固定すると、利用者のブラウザの今の振る舞いとずれていく。
確かめているのは「ある固定した版の Chromium で、こう計算される」ことであり、利用者の Chrome の版で同じになることではない。
版は、Node の LTS と同じく、半年に一度ほど上げる見込みである。
上げるたびに検査が変わるなら、それはブラウザの振る舞いの変化であり、知る価値がある。

Safari の版は固定しない。
ランナーの像が更新されると、Golem が変わらなくても `safari` のジョブが失敗しうる。
失敗が Golem の変更か Safari の更新かは、その場では区別できない。
ジョブの要約の版の表を前の実行と比べれば、どちらを疑うべきかの手がかりにはなる。
メンテナーは、PDF に関わる部分は Safari の更新で簡単には壊れないと見ており、壊れたときにそのつど対処することを受け入れた。
代わりに、Safari の利用者に近い振る舞いを毎日確かめられ、リリースの前に手で見る項目が減る。

`browser.yml` は、`main` が進んだ日にしか走らない。
`main` が止まっている間に Safari が更新されても、次に `main` が進むまで気づかない。
そのときの失敗は、Golem の変更と Safari の更新が重なって見える。
`workflow_dispatch` で走らせれば、`main` の今のコミットで切り分けられる。

Safari で確かめないこともある。
コンソールの誤りと、読み込みの失敗のうちページの中の値に出ないものは、Chromium だけが確かめる。

夜ごとの実行は、壊したプルリクエストのマージの後に失敗する。
失敗に気づくのは翌日になり、その間に入ったほかの変更と切り分ける手間がかかる。
`race.yml` と同じ扱いであり、プルリクエストの 5 分を守る代わりの費用である。

macOS のランナーは、公開のリポジトリでは課金されないが、同時に走れる数が Linux より少ない。
夜ごとの `safari` のジョブは、同じ時刻のプルリクエストの `scripts-macos` を待たせうる。
`schedule` の時刻を、プルリクエストの少ない時刻に置く。

Chrome for Testing の zip は、キャッシュがなければ実行のたびに取る。
キャッシュの量は、[ADR 0228](0228-keep-the-ci-caches-under-the-10-gb-limit.md) の 10 GB の見積もりに足される。
`schedule` の実行は `main` の範囲でキャッシュを保存するので、版を上げない限り一つだけ残る。
実装のプルリクエストで zip の大きさを測り、[ADR 0228](0228-keep-the-ci-caches-under-the-10-gb-limit.md) の I5 の見積もりに足しても 10 GB の下にあることを確かめる。
Safari のジョブは何もキャッシュしない。

## メンテナーが決めること

1. **ブラウザの配布元**：推奨は、Chrome for Testing の `chrome-headless-shell` である。版ごとの URL が変わらず、ヘッドレスに要るものだけを含む。実装の前に、配布の条件を読み、CI で走らせることが許されていることを確かめる。
   - 退けた案の一つは、Chromium のスナップショットのビルド（`chromium-browser-snapshots`）である。BSD のライセンスで条件は明快だが、リビジョンの番号で取るので、どの Chrome の版に当たるかがわかりにくい。一つめの案の配布の条件が CI に合わなければ、こちらにする。
   - 二つめは、Ubuntu の apt の Chromium である。Ubuntu 24.04 では snap になり、版を固定できない。
2. **ブラウザを操る道具**：推奨は、CDP の小さなクライアントを書くことである。
   - 退けた案は、Puppeteer か Playwright を入れることである。どちらもブラウザを自分で取りに行き、その取得に SHA-256 の検査がない。取得を止めて使うと、残るのは CDP のクライアントの部分だけで、それは 2 で書ける。
3. **走らせる頻度**：推奨は、夜ごとである。
   - 退けた案は、HTML のモジュール（golem-html、golem-epub）か golem-wasm を変えたプルリクエストでだけ走らせることである。どのモジュールの変更が HTML を変えるかは依存をたどる必要があり、`changes` ジョブの判定が複雑になる。そのうえ、走ったときは 5 分を超える。
4. **Safari**：起草のときの推奨は、手で確かめる項目に残し、リリースの前にメンテナーがまとめて見ることだった。版を固定できず、CI の結果が像の更新で変わるからである。
   - 起草のときに退けた案は、macOS のランナーの Safari を `safaridriver` で動かすことだった。版がランナーの像に従って変わり、失敗が Golem の変更か Safari の更新かを区別できないからである。

## 決めたことの記録

2026-11-08 に、メンテナーが次のように決めた。

1. ブラウザの配布元は、推奨のとおり Chrome for Testing の `chrome-headless-shell` にする。
2. ブラウザを操る道具は、推奨のとおり CDP の小さなクライアントを書く。Safari のために、同じ考えで WebDriver の小さなクライアントも書く。
3. 走らせる頻度は、推奨のとおり夜ごとにする。
4. Safari は、推奨を退け、macOS のランナーの Safari を `safaridriver` で CI で確かめる。メンテナーの理由は、「PDF 関連が簡単に壊れるとは思わないので Safari も CI で検証して。壊れたときは壊れたときで。」である。版がランナーの像に従って変わることは受け入れ、失敗の手がかりとしてジョブの要約に版を記録する。

## 参考文献

- Chrome for Testing, https://developer.chrome.com/blog/chrome-for-testing
- Chrome DevTools Protocol, https://chromedevtools.github.io/devtools-protocol/
- Apple, Testing with WebDriver in Safari, https://developer.apple.com/documentation/webkit/testing-with-webdriver-in-safari
- Apple, About WebDriver for Safari, https://developer.apple.com/documentation/webkit/about-webdriver-for-safari
- W3C, WebDriver Level 2, https://www.w3.org/TR/webdriver2/
- GitHub, actions/runner-images, macOS 15 arm64, https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md
- GitHub Docs, GitHub Actions billing, https://docs.github.com/en/billing/concepts/product-billing/github-actions
- bjorn3, browser_wasi_shim, https://github.com/bjorn3/browser_wasi_shim
- Deno, https://github.com/denoland/deno
- Bytecode Alliance, wasmtime, https://github.com/bytecodealliance/wasmtime
- W3C, CSS Text Decoration Module Level 3（`text-emphasis-style`）, https://www.w3.org/TR/css-text-decor-3/
- W3C, SVG 1.1, SVGLocatable（`getBBox`）, https://www.w3.org/TR/SVG11/types.html
