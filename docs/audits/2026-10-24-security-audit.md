# セキュリティ監査（2026-10-24、rc3）

この記録は、2026-10-24 の main（d974a9fd）の Golem を、v0.1.0-rc3 のタグを打つ前に監査した結果である。
[docs/adr/0035](../adr/0035-security-hardening.md) が、`v` で始まるタグのリリースの前に毎回の監査を求めている。
前回の記録は [2026-10-18 のセキュリティ監査](2026-10-18-security-audit.md)（a2b6106e）で、脅威のモデルは [2026-10-17 のセキュリティ監査](2026-10-17-security-audit.md) に、重大度の決め方は二つの記録に従う。

範囲は、a2b6106e から d974a9fd までの 466 のコミット（main へのマージは 131）である。
前回の問題を直した変更（[docs/adr/0040](../adr/0040-pdf-import-resource-limits.md) から [docs/adr/0044](../adr/0044-release-workflow-hardening.md)、[docs/adr/0051](../adr/0051-reuse-repeated-pdf-content-streams.md)、[docs/adr/0054](../adr/0054-svg-marker-cycle-and-depth-codes.md)）と、新しく信頼できない入力に触れるようになった経路を中心に調べた。
新しい経路のうち重く見たのは、`golem build` がフォントにない字を G08100 で報告するために本の全体の字を集める処理（[docs/adr/0081](../adr/0081-missing-glyphs-warn-in-build.md)）である。
CI は、新しい夜間の `race.yml`、macOS の `scripts-macos` ジョブ、`release.yml` の `notes` ジョブ、`scripts/ci` と `scripts/release` の変更を読んだ。

ソースコードへのリンクは、すべて監査したコミット d974a9fd に固定した。
再現したテストは、ブランチ `security-audit-2026-10-24-tests`（コミット [b9b141b3](https://github.com/tett23/golem/commit/b9b141b3008b82f5a4224b2b2d3a228be97ff725)）にある。
このブランチはマージしない。
テストはどれも、小さな敵対的な入力を読む時間か割り当てを限り、diagnostic で拒むか限界の中で読めることを求める。
時間切れは [docs/adr/0073](../adr/0073-time-bounds-in-tests.md) に合わせて 30 秒にした。
d974a9fd では、どのテストも失敗する。

仕様を変えずに直せる問題は、この記録と別のプルリクエストで直した。
直すと仕様が変わる問題は、ADR の草稿を書かず、メンテナーの判断を待つ項目として下に挙げる。

## 重大度の決め方

前回と同じである。

- **高**：ビルドするだけで、プロジェクトの外のファイルが消えるか書き換わる。
- **中**：ビルドするだけで、Golem が止まらなくなるか落ちる、出力を読む人の環境でスクリプトが動く、またはサンドボックスの上限を越えられる。
- **低**：悪用に別の条件が要るか、被害が小さい。
- **情報**：今は問題にならないが、前提が変わると問題になる。

前回と同じく、ふつうの本より小さな図版か原稿で、Golem が数分より長く止まるものか、数 GB を割り当てるものは中とした。
時間と割り当ての測定は Apple Silicon のマシンで行い、割り当ては `GHC.Stats` の割り当てたバイト数を使った。

## 見つかった問題

「確かめ方」の列は、テストの名前（ブランチ `security-audit-2026-10-24-tests`）、CLI で動かした結果、またはコードを読んだことを書く。
「疑い」と書いたものは、動かして確かめていない。

### 再現した問題

| 番号 | 重大度 | 問題 | 場所 | 確かめ方 | 状態 |
| --- | --- | --- | --- | --- | --- |
| C1 | 中 | オブジェクトのストリームの `Filter` が、そのストリームの中のオブジェクトを指すと、読み込みが止まらない | golem-pdf `Import.objectStream`、`filtersOf` | golem-pdf「A-P1」。30 秒の時間切れ | 修正済み（[#377](https://github.com/tett23/golem/pull/377)） |
| C2 | 中 | `Kids` を参照で書いた配列を二つのノードが指すと、ページの木の訪問が深さの指数で増える | golem-pdf `Import.pageAt` | 「A-P2」。深さ 30 で時間切れ。深さ 18、20、22 の合計で 5.3 秒 | 修正済み（#377） |
| C3 | 中 | ファイルの中のオブジェクトを、参照のたびに解析し直す | golem-pdf `Import.fetchAt`、`checkObjects` | 「A-P3」。536 KB の PDF で 7.9 GB を割り当てる | 修正済み（#377） |
| C4 | 中 | オブジェクトのストリームの複数の組が同じ位置を指すと、その位置のオブジェクトを組の数だけ解析する | golem-pdf `Import.objectStream` | 「A-P4」。8.9 GB を割り当てる | 修正済み（#377） |
| C5 | 中 | G08100 のための字のまとめ方が、字の数の二乗の時間になる | golem-preflight `groups` | golem-preflight「A-G1」「A-G2」。`golem build` で 12 万 8 千字に 424 秒 | 修正済み（[#378](https://github.com/tett23/golem/pull/378)） |
| C6 | 中 | 円弧の半径に `1e-9999` のような小さな数を書くと、平方根の計算が止まらない | golem-svg `Number.exceeds`、`sqrtR`、`Svg.arc` | golem-svg「A-SA」。円弧 1 つに 2.1 秒、30 個（1 KB）で時間切れ | ADR が要る |
| C7 | 中 | `marker` の入れ子の深さは 9 までだが、各段の数に上限がない | golem-svg `Svg.markers`、`markerDepthLimit` | 「A-SB」。2 KB で時間切れ | ADR が要る |
| C8 | 低 | G08014 の検査が、CSS の文字列の中の `/*` を注釈の始まりと取り違え、エスケープで書いた `url(` と `@import` を見落とす | golem-svg `Active.cssRefs` | golem-svg「A-S2」「A-S3」 | 修正済み（[#379](https://github.com/tett23/golem/pull/379)） |
| C9 | 低 | G08014 の表にない書き方で、ブラウザーが外部を読む SVG が検査を通る | golem-svg `Active` | 「A-S4」から「A-S9」（検査を通ることを確かめた。ブラウザーが読むかは疑い） | ADR が要る |
| C10 | 低 | CSL-JSON の文字列の制御文字が、XHTML にそのまま書かれる | golem-html `Html.entryPart`、golem-eval `File.unwritableText` | CLI。U+0001 を含む `title` で、HTML と EPUB の XHTML が XML として読めない | ADR が要る |

### CI とリリースの問題

| 番号 | 重大度 | 問題 | 場所 | 確かめ方 | 状態 |
| --- | --- | --- | --- | --- | --- |
| CI1 | 低 | `check-notes.sh` を、行をまたぐリンクと、文字参照かエスケープで書いた `..` が通る | `scripts/release/check-notes.sh` | スクリプトを動かし、GitHub の Markdown の API でリンクに描かれることを確かめた | 修正済み（[#380](https://github.com/tett23/golem/pull/380)） |
| CI2 | 低 | `jdx/mise-action` が、mise の版を固定せずに最新を入れる | `release.yml` の `notes` ジョブ、`ci.yml` の `release-scripts` ジョブ | action の定義を読んだ | メンテナーの判断 |

### 情報

| 番号 | 重大度 | 問題 | 場所 | 確かめ方 | 状態 |
| --- | --- | --- | --- | --- | --- |
| I1 | 情報 | 人間向けの描画が、双方向の制御文字（U+202A から U+202E、U+2066 から U+2069）をそのまま端末に書く | golem-syntax `Render.isTerminalControl` | コードを読んだ | 記録のみ |
| I2 | 情報 | 取り込んだ PDF の Form XObject が自分を呼ぶと、その循環を出力の PDF に写す | golem-pdf `Import.collect` | コードを読んだ。出力を読む道具が止まるかは疑い | 記録のみ |
| I3 | 情報 | `release.yml` を `workflow_dispatch` で main 以外のブランチから動かすと、`notes` ジョブがそのブランチのコードで `ANTHROPIC_API_KEY` を使う | `release.yml` の `version` と `notes` のジョブ | コードを読んだ | 記録のみ |

## 再現した問題の詳細

### C1：自分の中を指すオブジェクトのストリームの `Filter`（中）

[`objectStream`](https://github.com/tett23/golem/blob/d974a9fd4226e623775c7f929e45db5b6db03903/modules/golem-pdf/src/Golem/Pdf/Import.hs#L549-L581) は、読み終えたオブジェクトのストリームを状態に入れて使い回す。
入れるのは読み終えた後なので、読んでいる途中のストリームはまだ入っていない。
ストリームを展開するとき、[`filtersOf`](https://github.com/tett23/golem/blob/d974a9fd4226e623775c7f929e45db5b6db03903/modules/golem-pdf/src/Golem/Pdf/Import.hs#L717-L735) は `Filter` と `DecodeParms` の参照をたどる。
その参照が同じストリームの中のオブジェクトを指すと、`objectStream` にもう一度入り、また同じストリームを読み始める。
深さの上限があるのは `Length` の参照だけで、`Filter` の経路にはない。
二つのストリームが互いの中の `Filter` を指しても同じことが起きる。
テストでは、2 つのオブジェクトだけのストリームを持つ数百バイトの PDF が、30 秒の時間切れになった。
このストリームはどう読んでも展開できないので、`オブジェクトのストリーム` の理由で拒むように直した。

### C2：参照で書いた `Kids` の配列（中）

前回の C1 の修正で、[`pageAt`](https://github.com/tett23/golem/blob/d974a9fd4226e623775c7f929e45db5b6db03903/modules/golem-pdf/src/Golem/Pdf/Import.hs#L917-L950) は訪れた参照の集合を木の全体で一つ持つようになった。
集合に入るのは、ノードの辞書を指す参照だけである。
`Kids` の値が配列を指す参照のとき、その配列は集合に入らない。
配列の中に直接書いたノードの辞書も、参照ではないので入らない。
そのため、二つのノードが同じ配列を指せば、配列の中のノードを二度訪れる。
各段の配列に二つのノードを置き、その二つが次の段の同じ配列を指すようにすると、訪問は 2 の深さ乗になる。
深さの上限は 64 である。
テストでは深さ 30 の木（数 KB）が時間切れになり、深さ 18、20、22 を続けて読むと 5.3 秒かかった。
[docs/adr/0040](../adr/0040-pdf-import-resource-limits.md) は、一度訪れたノードをもう一度指す参照を止めると決めている。
配列を指す参照も集合に入れ、もう一度指せば `ページの木` の理由で止めるように直した。
二度訪れるのは配列の中のノードなので、ADR の規則の中の修正である。

### C3：参照のたびの解析（中）

[`fetchAt`](https://github.com/tett23/golem/blob/d974a9fd4226e623775c7f929e45db5b6db03903/modules/golem-pdf/src/Golem/Pdf/Import.hs#L491-L495) は、ファイルの中のオブジェクトを参照のたびに解析し直す。
使い回すのは、展開したストリームとオブジェクトのストリームだけである。
[`checkObjects`](https://github.com/tett23/golem/blob/d974a9fd4226e623775c7f929e45db5b6db03903/modules/golem-pdf/src/Golem/Pdf/Import.hs#L1240-L1262) は、写すオブジェクトの中のフォントの辞書を一つずつ見て、その `FontDescriptor` をたどる。
同じ大きな記述子を指すフォントの辞書を n 個並べると、記述子を n 回解析する。
テストでは、512 KB の配列を持つ記述子を 200 個の辞書が指す 536 KB の PDF で、7.9 GB を割り当てた。
辞書が 1 つのときは 0.4 GB である。
展開の上限は展開したバイト数を数えるので、解析の繰り返しは数えない。
解析したオブジェクトを状態に入れて使い回すように直した。
仕様は変わらない。

### C4：同じ位置を指すオブジェクトのストリームの組（中）

`objectStream` は、ストリームの頭の組（オブジェクトの番号と位置）ごとに、その位置からオブジェクトを解析する（[572 行](https://github.com/tett23/golem/blob/d974a9fd4226e623775c7f929e45db5b6db03903/modules/golem-pdf/src/Golem/Pdf/Import.hs#L572)）。
組の位置が重なっているかは確かめない。
組の数 `N` は 1,000 万まで許す。
テストでは、512 KB の配列の位置を 200 の組が指すストリームで、8.9 GB を割り当てた。
組が 1 つのときは約 0.1 GB である。
位置ごとに一度だけ解析し、組はその結果を引くように直した。
重なった位置を拒むのではないので、仕様は変わらない。

### C5：G08100 の字のまとめ方（中）

[docs/adr/0081](../adr/0081-missing-glyphs-warn-in-build.md) により、PDF をターゲットに含む `golem build` は、PDF の写しの字の一覧から、グリフ番号 0 の字を符号位置とフォントでまとめる（[golem-driver の 1056 行](https://github.com/tett23/golem/blob/d974a9fd4226e623775c7f929e45db5b6db03903/modules/golem-driver/src/Golem/Driver.hs#L1056)）。
まとめる [`groups`](https://github.com/tett23/golem/blob/d974a9fd4226e623775c7f929e45db5b6db03903/modules/golem-preflight/src/Golem/Preflight.hs#L66-L70) は、`Map.fromListWith (flip (<>))` で各組の末尾に値を足していく。
足すたびに組のリストを先頭からたどるので、同じ字が n 個あれば n の二乗の時間になる。
組の並びを決める `nub` も、異なる字の数の二乗になる。
この処理は前から `golem preflight` にあったが、[ADR 0081](../adr/0081-missing-glyphs-warn-in-build.md) の後は、ふつうのビルドが本の全体の字について毎回これを走らせる。

golem-driver の sample の 2 章を、フォントにない一字（U+F0000）を並べた段落に替えて、`golem build --target pdf` を測った。

| 2 章の字 | 時間 |
| --- | --- |
| U+F0000 を 3 万 2 千字 | 15 秒 |
| U+F0000 を 6 万 4 千字 | 59 秒 |
| U+F0000 を 12 万 8 千字（約 512 KB） | 424 秒 |
| フォントにある U+306F を 6 万 4 千字 | 2 秒 |
| U+F0000 から異なる字を 6 万 4 千字 | 39 秒 |

フォントにある字なら 2 秒で済むので、時間はまとめる処理にかかっている。
字の数を 2 倍にすると時間は約 4 倍から 7 倍になり、512 KB の原稿で 7 分止まる。
一度の畳み込みで組を作るように直し、12 万 8 千字は 5 秒になった。
組、組の順、ページ、値の順は変わらない。

### C6：小さな数の円弧（中、ADR が要る）

前回の C11 の修正（[docs/adr/0041](../adr/0041-svg-marker-and-number-limits.md)）は、数の絶対値を 10^9 以下に限った。
小さいほうには限りがなく、[`exceeds`](https://github.com/tett23/golem/blob/d974a9fd4226e623775c7f929e45db5b6db03903/modules/golem-svg/src/Golem/Svg/Number.hs#L71-L77) は指数が -60 より小さい数をすべて通す。
指数は 4 桁まで書けるので、`1e-9999` は 10 の -9999 乗の有理数として読まれる。
[`arc`](https://github.com/tett23/golem/blob/d974a9fd4226e623775c7f929e45db5b6db03903/modules/golem-svg/src/Golem/Svg.hs#L768-L790) は半径の比の二乗 `lambda` を作り、半径が小さいと `lambda` は 10 の約 2 万乗になる。
[`sqrtR`](https://github.com/tett23/golem/blob/d974a9fd4226e623775c7f929e45db5b6db03903/modules/golem-svg/src/Golem/Svg/Number.hs#L111-L124) はこれを整数にしてから、値そのものを初期値にしたニュートン法で整数平方根を求めるので、桁の数に比例した回数の多倍長の除算を繰り返す。
テストでは、円弧 1 つで 2.1 秒、30 個を書いた 1 KB の SVG で 30 秒の時間切れになった。
半径を `1e-9` にした 6 個の円弧は、0.01 秒で終わる。
直し方は、0 でない数の絶対値の下限を決める、半径が小さすぎる円弧を拒む、などが考えられる。
どれも読める SVG の範囲を変えるので、ADR が要る。
`isqrt` の初期値を良くすれば一つの円弧は速くなるが、`lambda` の桁が大きいことは変わらない。

### C7：`marker` の各段の数（中、ADR が要る）

[docs/adr/0054](../adr/0054-svg-marker-cycle-and-depth-codes.md) は、`marker` の参照の鎖の深さを 9 までとした（[`markerDepthLimit`](https://github.com/tett23/golem/blob/d974a9fd4226e623775c7f929e45db5b6db03903/modules/golem-svg/src/Golem/Svg.hs#L973-L974)）。
[ADR 0041](../adr/0041-svg-marker-and-number-limits.md) のテストは、各段に 4 つの `marker` を置く入れ子を想定している。
しかし `marker-mid` は、パスの頂点ごとに一つの `marker` を置く（[`markers`](https://github.com/tett23/golem/blob/d974a9fd4226e623775c7f929e45db5b6db03903/modules/golem-svg/src/Golem/Svg.hs#L928-L946)）。
各段の `marker` の中身を頂点 20 のパスにすると、描く図形は段ごとに約 18 倍になり、深さ 9 で約 18^9 になる。
描く図形は共有されず、木として展開される。
テストでは、この 2 KB の SVG が 30 秒の時間切れになった。
直すには、置く `marker` の総数か描く図形の総数に上限を決める必要があり、ADR が要る。

### C8：G08014 の CSS の読み方（低）

[docs/adr/0039](../adr/0039-svg-active-content-in-html-and-epub.md) の表は、`style` の要素と属性の中の `@import` と、`#` で始まらない `url(` を拒む。
[`cssRefs`](https://github.com/tett23/golem/blob/d974a9fd4226e623775c7f929e45db5b6db03903/modules/golem-svg/src/Golem/Svg/Active.hs#L80-L96) は、注釈を空白にしてから文字列を探す。
注釈を消す処理は CSS の文字列を知らないので、`a{content:"/*"} rect{fill:url(https://…)} b{content:"*/"}` の `url(` を注釈の中と取り違えて見落とす。
また、文字列をそのまま探すので、CSS がエスケープを戻して `url(` と読む `\75 rl(` と、`@import` と読む `@\69mport` を見落とす。
どちらも ADR の表にあるものの見落としなので、仕様を変えずに直せる。
CSS の字句解析（CSS Syntax Level 3）と同じく、文字列の外の注釈を除き、エスケープを戻してから探すように直した。
重大度は、外部の CSS と画像を読ませられるが、スクリプトは動かないので低とした。

### C9：G08014 の表にない外部の参照（低、ADR が要る）

次の書き方は、G08014 の検査を通ることをテストで確かめた。

- 表現の属性の `url()`：`<rect fill="url(https://…#g)"/>`。`filter`、`clip-path`、`mask`、`marker-*`、`cursor` も同じ形を取る。
- `url(` を使わない CSS の関数：`image-set("https://…" 1x)`。
- 処理命令：`<?xml-stylesheet type="text/css" href="https://…"?>`。XML の読み手は処理命令を読み飛ばす（[`misc`](https://github.com/tett23/golem/blob/d974a9fd4226e623775c7f929e45db5b6db03903/modules/golem-svg/src/Golem/Svg/Xml.hs#L133-L141)）。
- XHTML の名前空間の要素の `src`：`<h:img xmlns:h="http://www.w3.org/1999/xhtml" src="https://…"/>`。
- `set` と `animate` で `style` や `fill` を書き換えるもの：`<set attributeName="style" to="fill:url(https://…)"/>`。表が拒むのは `attributeName` が `href`、`xlink:href`、`on` で始まる名前のものだけである。
- XLink の名前空間を `xlink` 以外の接頭辞で書いた `attributeName`：`<set attributeName="q:href" to="javascript:…"/>`（`q` は XLink の名前空間）。

どれも [ADR 0039](../adr/0039-svg-active-content-in-html-and-epub.md) の表にないので、検査を足すには ADR が要る。
各ブラウザーと EPUB の読書環境が、SVG を文書として開いたときにこれらを実際に読むかは確かめていない。
最後の項目でスクリプトが動くなら中になるが、確かめていないので低とした。

### C10：CSL-JSON の制御文字（低、ADR が要る）

[docs/adr/0042](../adr/0042-control-characters-and-glob-metacharacters.md) は、XML 1.0 が許さない文字を、`manifest.toml`（G03028）と、原稿、表のファイル、取り込んだコードとテキスト（G02089）で拒むと決めた。
CSL-JSON の文字列は、この一覧にない。
[`unwritableText`](https://github.com/tett23/golem/blob/d974a9fd4226e623775c7f929e45db5b6db03903/modules/golem-eval/src/Golem/Eval/File.hs#L241-L277) は引用（`Cite`）を見ず、参考文献の項目は [`entryPart`](https://github.com/tett23/golem/blob/d974a9fd4226e623775c7f929e45db5b6db03903/modules/golem-html/src/Golem/Html.hs#L466-L482) で `escapeXml` を通るだけである。
golem-driver の bibliographies の fixture の `refs.json` の `title` に `\u0001` と `\u001b` を書いて、`golem build --target html --target epub` を動かした。
ビルドは diagnostic を出さずに終了コード 0 で終わり、HTML と EPUB の XHTML に U+0001 と ESC がそのまま書かれた。
`xmllint` は、この XHTML を `PCDATA invalid Char value 1` で拒んだ。
前回の C15 と同じく、読む人の環境で何かが動くわけではないので低とした。
CSL-JSON の文字列を拒む場所とコードを決めるには、ADR が要る。

## CI とリリースの問題の詳細

### CI1：`check-notes.sh` を通るリンク（低）

前回の CI3 の修正（[docs/adr/0044](../adr/0044-release-workflow-hardening.md)）で、`check-notes.sh` はリンクの形を広く見つけ、許可リストの前置きで始まらないものを拒むようになった。
ただし、`[text](` の後の URL と `<a>` のタグを行ごとに探し（[49 行](https://github.com/tett23/golem/blob/d974a9fd4226e623775c7f929e45db5b6db03903/scripts/release/check-notes.sh#L49)、[56 行](https://github.com/tett23/golem/blob/d974a9fd4226e623775c7f929e45db5b6db03903/scripts/release/check-notes.sh#L56)）、`..` を文字どおりにだけ探す（[69 行](https://github.com/tett23/golem/blob/d974a9fd4226e623775c7f929e45db5b6db03903/scripts/release/check-notes.sh#L69)）。
次の四つは検査を通り、GitHub の Markdown の API（`gh api /markdown`、`gfm`）はどれもリンクとして描いた。

- `[one](` の次の行に `//evil.example/x)` を書く。描かれた `href` は `//evil.example/x` である。
- `<a` の次の行に `href="//evil.example/y">` を書く。
- `https://github.com/tett23/golem/&#46;&#46;/&#46;&#46;/attacker/repo` を指す。描かれた `href` は `https://github.com/tett23/golem/../../attacker/repo` で、ブラウザーはこれを `https://github.com/attacker/repo` に解決する。
- 同じ `..` を `\.\.` と書く。

CommonMark は、リンクの行き先とタグの属性が次の行から始まることを許し、行き先の中の文字参照と逆斜線のエスケープを文字に戻す。
ノートを書く Claude Code のプロンプトには、誰でも書けるプルリクエストの本文が入る。
リリースは下書きで作られ、メンテナーが公開するので、低とした。
ノートを一行につないでから探し、`&` か逆斜線を含む行き先を拒むように直した。
`<img src=//…>` は、GitHub が `src` を空にして描くので問題にならない。

### CI2：mise の版（低、メンテナーの判断）

`release.yml` の `notes` ジョブは、`jdx/mise-action@v5` で `mise.toml` の Claude Code（2.1.292 に固定）を入れる。
このジョブは `ANTHROPIC_API_KEY` を持つ。
action には `version` を渡していない。
action の定義は、`version` を省くと mise の最新の版（`minimum_release_age` を満たすもの）を入れると書いている。
mise の配布物が乗っ取られれば、このジョブの API キーを読める。
`ci.yml` の `release-scripts` ジョブも同じ action を使うが、秘密は持たない。
[docs/adr/0035](../adr/0035-security-hardening.md) は action をタグで指定すると決めたが、action が取得する道具の版には触れていない。
前回の CI1（Claude Code の版）は書き込みの権限を持つジョブにあったので中としたが、`notes` ジョブは読む権限だけなので低とした。
`version` と `sha256` を固定するかは、メンテナーの判断である。

### 問題のなかった項目

- `race.yml` の権限は `contents: read` と `actions: read` だけで、キャッシュは復元するだけで保存しない。
- `race-needed.sh` は、`gh run list` の答えが 40 桁の小文字の 16 進数でなければ失敗し、推測で進まない。`GITHUB_SHA` も同じく確かめる。イベントの名前は環境変数で渡し、`run:` の中で展開しない。
- `scripts-macos` ジョブは秘密を持たず、`PATH` をシステムの道具に固定している。
- プルリクエストが保存する `dist-newstyle` のキャッシュ（[docs/adr/0045](../adr/0045-split-x86-build-and-pull-request-cache.md)）は、そのプルリクエストの範囲に閉じる。main と夜間の `race.yml` は main のキャッシュだけを復元する。
- epubcheck は、キャッシュから復元した zip も SHA-256 で確かめる。
- `fetch-wasmtime.sh` は、`VERSION` に配布物の名前と SHA-256 を書き、両方が一致するときだけ取得を省く（前回の CI5）。
- `build-linux.sh` は、ghcup の起動スクリプトをコミットで固定して SHA-256 で確かめる（前回の CI4）。
- `write-notes.sh` は、ワークフローのコマンドのファイルを環境から外し、`claude -p` を `--tools ''` と `--strict-mcp-config` で動かす（前回の CI2）。
- `release.yml` の Claude Code は書き込みの権限のない `notes` ジョブに移り、版は `mise.toml` で固定している（前回の CI1）。
- `smoke.sh` の変更は、diagnostic が出ないことの検査を足しただけである。
- `pull_request_target` は使っていない。`run:` の中で `${{ github.event.* }}` を展開している箇所はない。`actions/checkout` はどれも `persist-credentials: false` である。

### 情報の項目

I1 の双方向の制御文字は、端末によっては行の見た目の順を入れ替える。
[`isTerminalControl`](https://github.com/tett23/golem/blob/d974a9fd4226e623775c7f929e45db5b6db03903/modules/golem-syntax/src/Golem/Syntax/Render.hs#L45-L46) が置き換えるのは C0 と C1 の制御文字だけで、範囲は [ADR 0042](../adr/0042-control-characters-and-glob-metacharacters.md) が決めている。
G08100 と G09002 のメッセージの「」の中にも、書式の文字（Cf）がそのまま入る。
多くの端末は双方向の並べ替えをしないので、記録のみとした。

I2 の Form XObject の循環は、Golem 自身を止めない。
`collect` は一度訪れたオブジェクトを写し直さないからである。
出力の PDF を読む RIP と閲覧ソフトが循環で止まるかは、確かめていない。

I3 は、書き込みの権限を持つ人だけが `workflow_dispatch` を動かせるので、記録のみとした。
そういう人は、ワークフローそのものも書き換えられる。

## 前回の問題の確認

前回の C1 から C15、T1、T2 は [ADR 0039](../adr/0039-svg-active-content-in-html-and-epub.md) から [0043](../adr/0043-table-file-size-limits.md)、[0051](../adr/0051-reuse-repeated-pdf-content-streams.md)、[0054](../adr/0054-svg-marker-cycle-and-depth-codes.md) が、CI1 から CI5 は [ADR 0044](../adr/0044-release-workflow-hardening.md) が扱い、これらの ADR はどれも採択（実装済み）である。
前回の C2、C9、C10 は、ADR なしで直っている。
d974a9fd で、golem-pdf、golem-svg、golem-syntax、golem-lsp、golem-eval、golem-html、golem-epub、golem-plugin、golem-project、golem-driver のテストがすべて通る。
前回の再現のテストは、各モジュールの SecuritySpec などに入っている。
`golem build` で G08100 がエラーになる prod の経路でも、`build/pdf` をプロジェクトの外へのシンボリックリンクにすると G08013 で止まり、リンクの先を消さないことを CLI で確かめた。

## 直し方

- C1 から C4 は、[#377](https://github.com/tett23/golem/pull/377) で直した。
- C5 は、[#378](https://github.com/tett23/golem/pull/378) で直した。
- C8 は、[#379](https://github.com/tett23/golem/pull/379) で直した。
- CI1 は、[#380](https://github.com/tett23/golem/pull/380) で直した。
- C6、C7、C9、C10 は仕様を変えるので、ADR が要る。草稿は書いていない。
- CI2 は、mise の版を固定するかをメンテナーが決める。
- I1 から I3 は記録のみである。

修正のプルリクエストは、どれもテストを先に書き、d974a9fd で失敗することを確かめてから直した。

## 調べ方

- a2b6106e からの変更のうち、信頼できない入力を読むコード（golem-pdf の取り込み、golem-svg、golem-preflight と golem-driver の G08100、golem-eval の表のファイル、golem-syntax の描画、golem-plugin）を読み、上限の数え方、再帰、`<>` による連結、`nub`、上限のないループを洗った。
- 問題らしいものは、小さな入力を作るテストにして、30 秒の時間切れと割り当ての測定で再現した。
- G08100、CSL-JSON、シンボリックリンクは、`golem build` を CLI で動かして確かめた。
- CI は、`.github/workflows/` の四つのワークフロー、`scripts/ci/`、`scripts/release/`、`mise.toml` を読み、`check-notes.sh` は動かして確かめた。リンクとして描かれるかは、GitHub の Markdown の API で確かめた。

## 参考文献

- ISO 32000-1:2008, Document management, Portable document format, Part 1: PDF 1.7（ページの木の `Kids`、オブジェクトのストリーム、Form XObject）。https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf
- W3C, Scalable Vector Graphics (SVG) 2, 2018（`marker`、表現の属性、アニメーション）。https://www.w3.org/TR/SVG2/
- W3C, CSS Syntax Module Level 3（4.3.7 エスケープ、注釈と文字列の字句解析）。https://www.w3.org/TR/css-syntax-3/
- W3C, Associating Style Sheets with XML documents 1.0（`xml-stylesheet` の処理命令）。https://www.w3.org/TR/xml-stylesheet/
- W3C, Extensible Markup Language (XML) 1.0 (Fifth Edition), 2008（`Char` の生成規則）。https://www.w3.org/TR/xml/
- CommonMark Spec 0.31.2（リンクの行き先、生の HTML、文字参照、逆斜線のエスケープ）。https://spec.commonmark.org/0.31.2/
- GitHub Docs, "Render a Markdown document"（`POST /markdown`）。https://docs.github.com/en/rest/markdown/markdown
- jdx/mise-action, `action.yml`（`version` と `sha256` の入力）。https://github.com/jdx/mise-action
- Nicholas Boucher and Ross Anderson, "Trojan Source: Invisible Vulnerabilities", 2021（双方向の制御文字）。https://trojansource.codes/
