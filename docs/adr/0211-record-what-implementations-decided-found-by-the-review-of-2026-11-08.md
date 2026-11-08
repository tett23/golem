# ADR 0211: 2026-11-08 の ADR のレビューで見つかった、実装が決めた点を記録する

ステータス: 採択

## 文脈

2026-11-08 に、[ADR 0173](0173-rc4-refactoring.md) から 0210 までと、[golem-layout ADR 0021](../golem-layout/adr/0021-keep-with-next-counts-widow-and-orphan.md) から 0025 の実装を、ADR の文と照らし合わせた（origin/main `6e5f852f` と `322c6949`）。
違反と、設計の判断が要る逸脱は、それぞれ別の ADR で直す。
残ったのは、実装が ADR の書いていない点を決めたもの、ADR の文が実装の前提を取り違えていたもの、実装の後に手順が変わったものである。
どれもマージ済みで、多くは仕様書かプルリクエストの説明に書かれているが、決めた ADR がない。

[ADR 0205](0205-rules-added-by-the-implementation-of-adr-0180.md) と同じく、この ADR は、それらを決めたこととして記録する。
決めた ADR がないまま残すと、注釈と仕様書から出どころをたどれず、規則を変える ADR を書くときに見落とす。
コードとテストの参照は、origin/main `4c808d07` で確かめた。

以下、元の ADR の番号の順に並べる。
各項目は、ADR の文、実装、そうした理由の順に書く。

### [ADR 0173](0173-rc4-refactoring.md)：整理の PR が見た目の回帰テストの参照を変えた

[ADR 0173](0173-rc4-refactoring.md) の「確かめ方」は、2 から 6 のプルリクエストが `scripts/visual/pages/` の参照を変えないこと、変えたらそのプルリクエストは整理ではないことを定める。
6 の [#602](https://github.com/tett23/golem/pull/602)（マージ `78061f99`）は、`scripts/visual/pages/manual-dev.txt` の 28 行を変えた。
同じプルリクエストが、開発者のマニュアルの原稿（`manual-dev/part2/07-modules.gm`、`12-purity.gm`、モジュールの図）を、整理した後のモジュールの名前に合わせて直したためである。
組版の処理は変わっておらず、`scripts/determinism/hashes.txt` と各パッケージの `test/golden/` は 2 から 6 のどのプルリクエストでも変わっていない。

「確かめ方」は、組版の処理を変えたかを参照の差分で見る。
原稿を変えれば参照も変わるので、マニュアルの原稿を直す整理のプルリクエストには、この見方は当てはまらない。
この ADR は、#602 の差分を、マニュアルの原稿の修正によるものとして受け入れる。

### [ADR 0182](0182-external-links.md)：散文スロットが二つ以上の `[link]`

[ADR 0182](0182-external-links.md) は、`link` の引数の誤りを G02124 と定めるが、散文スロット[^slot]が二つ以上の場合を書いていない。
実装は、ほかのインラインのコマンドと同じく G02038（`link の散文スロットは一つまでです`）とした（[`File.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-eval/src/Golem/Eval/File.hs#L2313)）。
`docs/diagnostics.md` の G02038 は、意味を「散文スロットの数が違います」とし、`link` の文を足してある。
散文スロットの数の誤りは、G02124 の引数の誤りとは別の原因であり、一つのコードに一つの原因の原則に合う。
[ADR 0187](0187-inline-language-switch.md) も、`[lang]` で同じ扱いを明文で決めている。

[^slot]: **散文スロット**：命令文脈の `:` の後に書く本文の欄。`|` で区切って複数書ける。

### [ADR 0183](0183-tagged-pdf-and-pdf-a.md)：構造の木の三点

[ADR 0183](0183-tagged-pdf-and-pdf-a.md) の実装（[#615](https://github.com/tett23/golem/pull/615)、マージ `19961845`）には、ADR と違う点が三つある。

一つめは、CI の CMYK の ICC プロファイルである。
ADR は「再配布できるものを選び、ライセンスとともにリポジトリに置く」とし、選んだプロファイルの出所とライセンスを実装のプルリクエストに書くとした。
実装は、CC0 か自由に再配布できる印刷用の CMYK のプロファイルを見つけられず、Golem のために小さなプロファイル `scripts/ci/testdata/conformance/golem-test-cmyk.icc` を作り、MIT とした。
出所とライセンスは、同じディレクトリの `README.md` と #615 の説明に書かれ、仕様書もこのプロファイルを書く。
再配布でき、ライセンスがはっきりしているという ADR の目的は満たす。

二つめは、最初の見出しの G07103 のメッセージである。
ADR のメッセージは `PDF/UA では見出しの段を飛ばせません: <前の段> から <この段>` で、最初の見出しのときの「前の段」を決めていない。
実装は、文書を 0 の段として `0 から 2` と書く（[`Draw.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L122-L126)）。
`docs/diagnostics.md` の G07103 も「最初の見出しでは、前の段を 0（文書）として述べる」と書く。

三つめは、アーティファクトの表の「校正のコメント（dev の出力）」の行である。
ADR はこれを `/Artifact << /Type /Layout >>` にするとしたが、PDF は校正のコメントをそもそも描かない（[`Japanese.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/src/Golem/Layout/Japanese.hs#L496)）。
描かないものには印を付けようがないので、この行は空振りである。
仕様書のアーティファクトの表は、この行を持たない。

### [ADR 0184](0184-table-positional-path.md)：golem-cli のテストが PDF のインスタンス ID を比べない

[ADR 0184](0184-table-positional-path.md) のテスト設計は、位置引数で書いた `@table` と `src=` で書いた同じプロジェクトとで、四つのターゲットの出力のバイト列が同じことを確かめるとした。
PDF の `/ID` の二つめ（インスタンス ID）は、すべての入力のバイト列のハッシュである（[docs/adr/0002](0002-determinism.md)）。
原稿のバイト列が違えばインスタンス ID も違うので、PDF の全体は同じにならない。
実装のテストは、インスタンス ID の 32 桁だけを 0 で塗って比べる（[`CommandsSpec.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-cli/test/CommandsSpec.hs#L234-L239)）。
HTML、EPUB、プレーンテキストはバイト列のまま比べ、PDF も `/ID` の二つめのほかはバイト列のまま比べる。

### [ADR 0185](0185-project-wide-variables.md)：ホバーの環境の `vars`

[ADR 0185](0185-project-wide-variables.md) は、ホバーで `[= vars.product]` の結果を表示するのは「今の式のホバーのままでよい」とした。
今の式のホバーの環境には `vars` がなく、そのままでは同じ ADR のテスト設計「ホバーが新しい値になること」が通らない。
実装は、ホバーの環境に `vars` を足した（[`Features.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-lsp/src/Golem/Lsp/Features.hs#L817-L818)）。
ADR の前提の誤りを、テスト設計に合わせて正したものである。
`meta` は、今もホバーの環境にない（[#605](https://github.com/tett23/golem/pull/605) の説明）。

### [ADR 0186](0186-fmt-table-files.md)：二つめの BOM と、`@listing` と共有する表のファイル

[ADR 0186](0186-fmt-table-files.md) は、表のファイルの「先頭の BOM（U+FEFF）を一つ取り除く」ことと、二度かけても結果が変わらないこと（プロパティテスト）の両方を定めた。
BOM が二つ続くファイルでは、この二つは両立しない。
`formatTable` は先頭の BOM を一つだけ取り除くので（[`Fmt.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-fmt/src/Golem/Fmt.hs#L51-L54)）、`golem fmt` を一度かけた後のファイルはまだ BOM で始まり、二度めにまた変わる。
読み手の `parseCsv` と `parseTsv` も BOM を一つしか読み飛ばさず、二つめの BOM を最初のセルの字として残す。
実装は、読み手に合わせて「一つ」を取り、冪等性のプロパティテストの生成器から二つめの BOM を除いた（[`test/Main.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-fmt/test/Main.hs#L203-L210)）。
二つめの BOM まで取り除くと、`golem fmt` が読み手の作る表を変えてしまう。

同じ ADR は、`@table` と `@listing` の両方が読むファイルについて、「行の終わりの CR が消えるほかは変わらない（推測。実装で確かめる）」と書いた。
[#596](https://github.com/tett23/golem/pull/596) で確かめると、`@listing` の一行めから BOM も消えた。
`@listing` は BOM を残して取り込むので（[`TableFilesSpec.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-driver/test/TableFilesSpec.hs#L123-L124)）、`golem fmt` が表のファイルとして BOM を取り除けば、`@listing` の出力からも消える。
規則（共有するファイルも表のファイルとして直す）のとおりの結果で、推測だけが外れた。

### [ADR 0187](0187-inline-language-switch.md)：欧文の区間の両用の文字の隣の改行

[ADR 0187](0187-inline-language-switch.md) は、欧文の区間の両用の文字を欧文の語の箱にし、隣に和欧間の空きもアキ量のセットの空きも入れないとしただけで、隣で改行してよいかを書いていない。
実装（[#630](https://github.com/tett23/golem/pull/630)）は、両用の文字の隣の改行の可否を、その字の和文の文字クラスの禁則で決めた（[`Japanese.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/src/Golem/Layout/Japanese.hs#L1161-L1167)）。
`[lang en: “東京”]` の `“` と `東` のあいだ、`京` と `”` のあいだでは改行しない（[`LangSpec.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/test/LangSpec.hs#L96-L99)）。
欧文の語の箱の中では改行しないので、和文の字と隣り合う境だけが問題になる。
そこで禁則を外せば、始め括弧の後ろで行が終わる。
仕様書の「原稿の中の言語」の節は、この規則を書いている。

### [ADR 0189](0189-paragraph-alignment-spacing-and-end-indent.md)：三つの点と `fully-justified`

[ADR 0189](0189-paragraph-alignment-spacing-and-end-indent.md) の実装（[#610](https://github.com/tett23/golem/pull/610)、マージ `87db2352`）は、ADR の文のとおりにできなかった点を、説明の「Points where the ADR could not be followed literally」に挙げた。
そのうち、`@style-def` で `space-after` を 0 に戻せないことは、媒体のあいだで結果が食い違うので、設計の判断として別の ADR で扱う。
残りの三つを、ここに記録する。

**`fully-justified` の行分割**：ADR は「段落の終わりの `filStretch` のグルーを置かず、最後の行もほかの行と同じく行の領域いっぱいに伸ばす」とした。
終わりのグルーがないと、短い最後の行の badness が 10000 になり、行分割の最後の段階はそれを受け入れない。
そのため、語を送り出して、一行の段落まで伸び切った二行に分けてしまう。
実装は、`left-justified` と同じく終わりのグルーを置いて分け、組むときに最後の行の終わりのグルーの伸びを 0 にした（[`Align.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/src/Golem/Layout/Align.hs#L41-L57)）。
最後の行のほかのグルーが、行の残りを埋める。
見た目は ADR の文のとおり（最後の行もほかの行と同じ幅、伸びるグルーのない最後の行は始まりに寄る）だが、分ける位置は `left-justified` と同じであり、最後の行の badness を見る行分割ではない。
仕様書は実装のとおりに書いてある。

**HTML の組の規則のセレクター**：ADR は、後のアキを持つ A と前のアキを持つ B の組の規則を `p.ps-A + p.ps-B` とし、後のアキの規則 `p.ps-A + :not(.ps-A):not(.blank-line)` の後に書けば勝つとした。
前者の詳細度は (0,2,2)、後者は (0,3,1) なので、後に書いても前者は負ける。
実装は、組の規則を `p.ps-A + p.ps-B:not(.ps-A)` とし、`body` の後では `p:not([class]) + p.ps-B`（詳細度が同じで、後に書くので勝つ）、`body` の前では `p.ps-A + p:not([class]):not(.ps-A)` とした（[`Html.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-html/src/Golem/Html.hs#L1165-L1185)）。
`body` の後のアキは `p:not([class]) + :not(p):not(.blank-line), p:not([class]) + p[class]` に書く。
組の規則が勝つという ADR の意図を、詳細度の上で実現したものである。

**改ページの前とファイルの境の空き**：ADR は、空きを置かない場所を決めていない。
実装は、強制の改ページ（`ForcedBreak`）と改ページの手での制御（`PageControl`）の直前には空きを置かず（[`Flow.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L1477-L1481)）、`space-between` と同じく、空きを一つの文書のブロックのあいだにだけ置いた。
ファイルの境の前後のブロックは、隣り合う兄弟として扱わない（[`Flow.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L1462-L1464)）。
改ページの直前の空きは、段の末尾に残るだけで何も離さない。
仕様書は、改ページの前の規則を書いているが、ファイルの境の規則は書いていない。

### [ADR 0193](0193-line-paragraph-separator-by-default.md)：決定性の検査の期待値の一行

[ADR 0193](0193-line-paragraph-separator-by-default.md) は、既存のプロジェクトで「決定性の検査の期待値は変わらない」とした。
実装のコミット `264f74f0`（[#599](https://github.com/tett23/golem/pull/599)）は、`scripts/determinism/hashes.txt` の PDF の一行を改めた。
インスタンス ID は `manifest.toml` のバイト列を含み、`sample` の fixture に `[source]` の表を書いたので、その一行だけが変わった。
PDF の本文は変わっていない。
ADR の見込みが、インスタンス ID の入力を数え漏らしていた。

### [ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md)：wasm の三点

[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md) の実装（[#643](https://github.com/tett23/golem/pull/643)、[#644](https://github.com/tett23/golem/pull/644)、[#645](https://github.com/tett23/golem/pull/645)、[#648](https://github.com/tett23/golem/pull/648)）には、ADR と違う点が三つある。

一つめは、`golem_result_len` である。
ADR の関数の表は、`golem_result_len` を「結果の枠の長さ」とし、同じ関数で `golem_version` の文字列の長さも読むとした。
結果の枠と版の文字列は形が違うので、一つの関数で両方の長さを読むには、長さを枠の外に持つほかない。
実装は、渡すすべてのバッファの直前の 4 バイトに長さを置き、`golem_result_len` はそれを読む（[`Main.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-wasm/app/Main.hs#L6-L8)、[`Main.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-wasm/app/Main.hs#L40-L56)）。
`golem_free` も、同じ接頭辞から元の割り当てを解放する。
`README.md` と `scripts/wasm/README` は、この形を書いている。

二つめは、`wasm` ジョブの比べの相手の待ち方である。
ADR は、`build` ジョブの x86-64 のランナーが比べの一覧を成果物として上げ、`wasm` ジョブがそれと比べるとしただけで、`needs` を決めていない。
実装は、`build` ジョブの全体を `needs` にせず、`scripts/visual/wait-pdfs.sh` で `build (ubuntu-24.04, outputs)` の成果物 `wasm-native-list` だけを待つ（[`ci.yml`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/.github/workflows/ci.yml#L691-L696)）。
`build` のほかのランナーを待たずに、wasm を組む時間を重ねられる。
待つジョブが成果物なしで終われば、`wait-pdfs.sh` は 1 で止まる。

三つめは、GMP の版の調べ方である。
ADR は、wasm にリンクした GMP の版を「1 で調べ方を決める」とした。
1 のプルリクエスト（[#632](https://github.com/tett23/golem/pull/632)、[#639](https://github.com/tett23/golem/pull/639)）では決まらず、#648 が、wasm の GHC の `ghc-gmp.h` から読むと決めた（`GMP_GHC=wasm32-wasi-ghc` で `scripts/release/gmp-version.sh` を動かす。[`release.yml`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/.github/workflows/release.yml#L294)）。
仕様書の「リリース」の節は、この調べ方を書いている。

### [ADR 0200](0200-figures-and-listings-without-numbers.md)：Emet と Rust の SDK の `nonumber`

[ADR 0200](0200-figures-and-listings-without-numbers.md) の「意味論 IR と ABI」の節は、CDDL、golem-doc の型、`Golem.Doc.Validate` だけを挙げた。
実装（[#627](https://github.com/tett23/golem/pull/627)、マージ `d71d2cc7`）は、ほかに Emet の `Figure` と `Code`（`modules/golem-emet/src/Golem/Emet/IR.hs`、`Builtins.hs`、`docs/golem-emet/specifications.md`）、Rust の SDK の `figure`（`plugins/golem-plugin-sdk/src/ir.rs`）を改め、見本のプラグイン `plugins/wasm/bar-chart.wasm` を組み直した。
Emet と SDK は意味論 IR の構成子を位置で写すので、IR の欄を足せば、二つも同じ位置に欄を足さないと読み書きが壊れる。
IR を変える ADR が、Emet と SDK を挙げ忘れたものである。

### [ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) と [ADR 0206](0206-pagination-points-the-invariants-did-not-decide.md)：述語のテストと境界の表

[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) のテスト設計は、述語ごとに規則を破った出力を手で作り、「その述語だけが違反を返すこと」を確かめるとした。
I6 の二つの例は、I6 だけでなく I4 と I5 も破る出力であり、テストは `[I4, I6]` と `[I5, I6]` を期待する（[`PaginateInvariantsSpec.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/test/PaginateInvariantsSpec.hs#L264)、[`PaginateInvariantsSpec.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/test/PaginateInvariantsSpec.hs#L272)）。
見出しを後と離した出力は、段の始まりか終わりの孤立行も作るので、I6 だけを破る出力は作れない。
期待する違反の一覧を固定しているので、述語の誤りは見つかる。

二つの ADR の「境界の入力」の表は、段落の行の数に C と C + 1 を挙げる（0204 の表、0206 の「見出しだけの段の後の段落の行の数」）。
列挙の段落は 1 行から 4 行で（[`PaginateEnum.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/test/PaginateEnum.hs#L70-L77)）、[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の「実装すること」の 2 もそう定める。
段の行の数 C は 3 から 8（[ADR 0208](0208-widen-lightweight-formal-methods.md) の後のプルリクエストでは 3 から 5）なので、C 行の段落は C が 3 と 4 のとき、C + 1 行の段落は C が 3 のときにしか現れない。
実装は、「実装すること」の 2 に従った。

### [golem-layout ADR 0023](../golem-layout/adr/0023-keep-with-next-after-figures-sent-on.md)：F4 の上限

[golem-layout ADR 0023](../golem-layout/adr/0023-keep-with-next-after-figures-sent-on.md) の F4 は、`keep` が進む回数を「待っている図版の数と、続きの注の本文の行の数の和を超えない」とした。
待つものがなく、量が今の段に入らなければ、`keep` は空の段まで一度進む（[`State.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/src/Golem/Layout/Paginate/State.hs#L124-L125)）。
このとき待つものの数は 0 で、進む回数は 1 なので、F4 の上限は一つ小さい。
テストは `1 + length figs + noteLen` を上限として確かめる（[`PaginateSpec.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/test/PaginateSpec.hs#L989-L991)）。
ADR の式の誤りであり、実装とテストが正しい。

### [ADR 0208](0208-widen-lightweight-formal-methods.md)：四つの点

[ADR 0208](0208-widen-lightweight-formal-methods.md) の実装（[#653](https://github.com/tett23/golem/pull/653)、マージ `fd8cb25a`）は、説明の「Where the ADR does not match the code」に四つを挙げた。

**図版の行の数**：ADR の 3 は、短くした列挙の図版の行の数を 1、C − 1、C、C + 1 とした。
[ADR 0206](0206-pagination-points-the-invariants-did-not-decide.md) の後の `elementsFor` は C 行までの図版しか作らず、短くした列挙が [ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の列挙の部分集合であること（E5）が、C + 1 を許さない。
実装は 1、C − 1、C とした（[`PaginateEnum.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/test/PaginateEnum.hs#L79-L91)）。
そのため、プルリクエストの上限 3 の入力は、ADR の 31,320 でなく 26,214 になった。

**`checkAllPar` の分け方**：ADR は、段ごとに段の入力をプロセッサの数に分けて調べるとした。
段 6 には約 10⁸ の入力があり、段を丸ごと分けると、段の全体をメモリに持つことになる。
実装は、段を「プロセッサの数 × 一つの部分の大きさ」の塊に区切り、塊を続いた部分に分けて spark で調べ、一度に一つの塊だけを持つ（[`Enum.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-test-support/src/Golem/TestSupport/Enum.hs#L182-L194)）。
違反のあった最初の部分の値を返すので、`checkAll` と同じ値を返す（E1）ことは変わらない。

**毎晩のページ分割の上限**：ADR の 3 は、毎晩の上限を 6 とし、実装のときに CI で測って 30 分を超えるなら 5 にするとした。
上限 6 を CI で測ったのは、[golem-layout ADR 0025](../golem-layout/adr/0025-need-lines-and-blank-lines-after-figures-sent-on.md) が要素を三つ足す前の、一段の候補が 16 の列挙であり、19 分 56 秒だった（run 42412608229）。
三つを足した後の候補は 19 になり、実装はこれを測らず、一段の倍率から約 55 分と見積もって 5 にした（[`enum.yml`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/.github/workflows/enum.yml#L120)）。
上限 5 は、測った値ではなく見積もりから決めたものである。

**抜き取りの範囲**：ADR の 3 は、短くした列挙が除いた入力を「毎晩の抜き取りで補う」とした。
実装は、[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の列挙の、上限の一つ上の段（要素が 6 個）だけから抜き取る。
上限以下の段で短くした列挙が除いた入力（段の行の数 6 から 8、行の数が 2 から C − 2 の図版）は、要素が 6 個になるまで抜き取りに現れない。
ADR の 2 の「上限の一つ上の段を抜き取って調べる」の文に従ったもので、補うのは要素が 6 個の入力だけである。

### [ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md)：五つの点

[ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md) の実装（[#655](https://github.com/tett23/golem/pull/655)、マージ `322c6949`）は、説明の「Where the ADR does not match」に、次の点を挙げた。

**正規形と縦組みのテストの段**：ADR のテスト設計は、正規形と縦組みのテストを段 2 まで行うとした。
段 2 で行うと、x86-64 のランナーで golem-layout-test が 40 秒かかり、[ADR 0208](0208-widen-lightweight-formal-methods.md) の 4 の 10 秒を大きく超えた。
ADR の 5 の逃げ道（プルリクエストでは行の幅を 4 字まで）を使っても、10 秒に収まらなかった。
実装は、プルリクエストでは正規形と縦組みを段 1 まで、毎晩のジョブでは段 2 まで調べる（[`LineBreakInvariantsSpec.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/test/LineBreakInvariantsSpec.hs#L58-L66)）。
L1 から L13 のすべての入力のテストは、決めたことの 8 のとおり、プルリクエストで段 2 のままである。
行の幅を 4 字までにしたことは、ADR の 5 が許した逃げ道であり、逸脱ではない。

**上限の変数**：毎晩のジョブで行の幅を 5 字までにすることと、L7 の素朴な探索で分割の候補を 16 までにすることは、専用の環境の変数を持たず、`GOLEM_ENUM_LINES_DEPTH` がプルリクエストの上限 2 より大きいことから決まる（[`LineBreakInvariantsSpec.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/test/LineBreakInvariantsSpec.hs#L50-L56)）。
[ADR 0208](0208-widen-lightweight-formal-methods.md) の 4 は、範囲ごとに上限と抜き取りの数の二つの変数だけを挙げる。

**正規形の比べ方**：ADR の 1 は、正規形を当てない入力と当てた入力とで「`breakParagraph` に渡す値」が同じであることで確かめるとした。
値が等しくなるのは、パラメータを正規化したとき（字幅の伸縮はそれを受ける箱があるときだけ、突き出しは突き出す項目があるときだけ与える）に限る。
`breakParagraph` は、それ以外のときには、どちらを与えても同じ結果を返す。
実装は、正規形が除く環境を、その環境の正規形と、組の並びごとに一つずつ比べる。
集まりが同じことより強い比べ方である。
縦組みは箱の種類（`bcTag`）を変えるが、`breakParagraph` はそれを読まないので、読む値（幅、伸縮、突き出しと端、グルー、罰点、箱の文字）を比べる。

**[golem-layout ADR 0016](../golem-layout/adr/0016-ellipsis-before-full-stop.md) の回帰の述語**：ADR のテスト設計は、`…` と `。` のあいだで分ける出力を L4（分離禁止）が違反とするとした。
`。` は句点で行頭禁則の字なので、この出力を捕まえるのは L2 である。
実装は、この出力で L2 を確かめ、二つの `…` のあいだで分ける出力で L4 を確かめる（[`LineBreakInvariantsSpec.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/test/LineBreakInvariantsSpec.hs#L444-L452)）。

**L7 の 3 行の段落**：ADR のテスト設計は、Knuth と Plass の論文の例の最初の 3 行に当たる短い段落で、手で計算した罰点の和を確かめるとした。
実装は、論文の例ではなく、幅 30、30、25 の語を二度並べた自作の 3 行の段落を使い、罰点の和 388 を手で数えた（[`LineBreakInvariantsSpec.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/test/LineBreakInvariantsSpec.hs#L392-L402)）。
論文の例は golem-layout のテスト（[golem-layout ADR 0007](../golem-layout/adr/0007-knuth-plass-reference-test.md)）がすでに持ち、L7 のテストに要るのは、計算を手で追える小ささである。

### [golem-layout ADR 0025](../golem-layout/adr/0025-need-lines-and-blank-lines-after-figures-sent-on.md)：四つの点

[golem-layout ADR 0025](../golem-layout/adr/0025-need-lines-and-blank-lines-after-figures-sent-on.md) の実装（[#654](https://github.com/tett23/golem/pull/654)、マージ `44ca9230`）には、ADR と違う点が四つある。

**行アキの手順 3 は段の先頭で止まる**：ADR は、仕様書の「行アキ」の手順 3 を「入るか、段が空になるまで次の段へ進む」に改めるとした。
素の `keep` は空の段でしか止まらないので、続きの脚注だけを持つ段の先頭を飛ばす。
その段の先頭に来た行アキは、どのみち捨てられる（手順 4）。
実装は、量を段の先頭（`sUsed == top`）では 0 にして、`keep` を段の先頭で止めた（[`Paginate.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/src/Golem/Layout/Paginate.hs#L162-L173)）。
手順 3 の条件「今の段が空でなく」を、進んだ段ごとに当てたことになる。
送った図版を置いた段は段の先頭ではないので、そこで行アキが入れば置く。
仕様書は、ADR の文のとおり「段が空になるまで」と書いたままで、コードと食い違っている。

**続きの注の後の回り込む図版**：ADR の 3 は、表と回り込む図版について、送った図版の後で違反が起きるかを確かめ、起きれば同じ原因として直すとした。
回り込む図版（`FWrapped`）は、先に `flushFigures` で待つ図版をすべて置くので、送った図版の後では違反しない。
続きの注の後では違反した（`[注 5 行を持つ 1 行, 回り込む図版 3]` で、4 行の段に 6 行）。
`keep` は送った図版と続きの注の両方を扱う（[golem-layout ADR 0023](../golem-layout/adr/0023-keep-with-next-after-figures-sent-on.md) の「送った図版と続きの注」）ので、実装は同じ原因とみて、`keep` で直した（[`Paginate.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/src/Golem/Layout/Paginate.hs#L295-L301)）。

**P4 の 6 行の例**：ADR のテスト設計は、段の行の数 6 の入力 `paginate 1 6 [3 行, 図版 3, 行アキ 2, 1 行]` で、行アキが図版の後に置かれることを確かめるとした。
この入力では、図版が 1 ページに入るので、送られない。
実装は、最初の段落を 5 行にして、図版を送らせた（[`PaginateSpec.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/test/PaginateSpec.hs#L1105-L1112)）。

**P3 の読み方**：出力では、行アキは後のブロックの前の空いた格子の行としてしか見えず、どの段が行アキを持つかを述語は読めない。
実装の P3 の述語は、捨てておらず、後のブロックの前にも見えない行アキを、P3 の違反とする（P4 の違反にもなる。[`PaginateInvariants.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/test/PaginateInvariants.hs#L495-L503)）。
仕様書の不変条件のテストの段落は、この読み方を書いている。

## 実装すること

ここに記録した規則と手順は、どれも main に入っている（`4c808d07` で確かめた）。
この ADR の実装は、次のことだけである。

### ステータスの行

次の ADR のステータスの行に、この ADR が記録した点を足す。
すでに `→` を持つ行には、[ADR 0205](0205-rules-added-by-the-implementation-of-adr-0180.md) の後の行と同じく `、` でつないで足す。

| ADR | 足す文（`<この ADR>` は `[ADR 0211](0211-record-what-implementations-decided-found-by-the-review-of-2026-11-08.md)`、golem-layout からは `../../adr/` を前に付ける） |
| --- | --- |
| 0173 | 採択→整理のプルリクエストがマニュアルの原稿を直して見た目の回帰テストの参照を変えることは `<この ADR>` |
| 0182 | 採択→散文スロットが二つ以上の `[link]` の G02038 は `<この ADR>` |
| 0183 | 採択→CI の ICC プロファイル、最初の見出しの G07103 のメッセージ、校正のコメントの行は `<この ADR>` |
| 0184 | 採択→golem-cli のテストが PDF のインスタンス ID を比べないことは `<この ADR>` |
| 0185 | 採択→ホバーの環境の `vars` は `<この ADR>` |
| 0186 | 採択→二つめの BOM と冪等性、`@listing` と共有するファイルの BOM は `<この ADR>` |
| 0187 | 採択→欧文の区間の両用の文字の隣の改行は `<この ADR>` |
| 0189 | 今の行に、`、fully-justified の行分割、HTML の組の規則のセレクター、改ページの前とファイルの境の空きは <この ADR>` を足す |
| 0193 | 採択→決定性の検査の期待値の一行は `<この ADR>` |
| 0199 | 今の行に、`、golem_result_len の長さの接頭辞、wasm ジョブの待ち方、GMP の版の調べ方は <この ADR>` を足す |
| 0200 | 採択→Emet と Rust の SDK の `nonumber` は `<この ADR>` |
| 0204 | 今の行に、`、I6 の述語のテストの期待する違反と、境界の表の段落の行の数 C、C + 1 は <この ADR>` を足す |
| 0206 | 採択→境界の表の段落の行の数 C、C + 1 は `<この ADR>` |
| 0208 | 採択→図版の行の数、`checkAllPar` の分け方、毎晩のページ分割の上限、抜き取りの範囲は `<この ADR>` |
| 0209 | 採択→正規形と縦組みのテストの段、上限の変数、正規形の比べ方、[golem-layout ADR 0016](../golem-layout/adr/0016-ellipsis-before-full-stop.md) の回帰の述語、L7 の 3 行の段落は `<この ADR>` |
| golem-layout 0023 | 採択→F4 の上限は `<この ADR>` |
| golem-layout 0025 | 採択→行アキの手順 3 が段の先頭で止まること、続きの注の後の回り込む図版、P4 の 6 行の例、P3 の読み方は `<この ADR>` |

[ADR 0189](0189-paragraph-alignment-spacing-and-end-indent.md) の今の行は、[ADR 0205](0205-rules-added-by-the-implementation-of-adr-0180.md) の規則を持つ。
`<この ADR>` の部分は、`adr-guard links --fix` が許すリンクの形で書く。

### 仕様書

- 「行アキ」の手順 3 の「入るか、段が空になるまで次の段へ進む」を、「入るか、段の先頭に来るまで次の段へ進む」に改める。続きの脚注だけを持つ段も段の先頭であることと、この ADR へのリンクを足す。
- 段落の前後のアキの節に、「空きは一つのファイルのブロックのあいだにだけ置き、ファイルの境には置かない」の一文と、この ADR へのリンクを足す。改ページの前の空きの文にも、この ADR へのリンクを足す。
- `fully-justified` の文、HTML の組の規則のセレクターの文、両用の文字の隣の改行の文、表のファイルの BOM の文（二つめの BOM と `@listing` の BOM。文がなければ、文書の fix のプルリクエストが足したものに）に、この ADR へのリンクを足す。

### コードとテストの注釈

次の注釈に、この ADR を出どころとして足す。

- `Golem.Typeset.Flow` の `gapLines` の注釈（改ページの前とファイルの境）。
- `Golem.Html` の `spaceRules` の注釈（組の規則のセレクター）。
- `Golem.Layout.Align` の `breakAligned` の注釈（`fully-justified`）。
- `Golem.Layout.Japanese` の `latinDual` の注釈（両用の文字の隣の改行）。
- `Golem.Fmt` の `formatTable` の注釈（BOM を一つ）。
- `Golem.Layout.Paginate` の `placeBlank` の注釈（段の先頭で止まる）。
- `Golem.Lsp.Features` のホバーの環境の注釈（`vars`）。

golem-cli の `CommandsSpec` の注釈は、インスタンス ID の出どころを `docs/adr/0004`（版の配布）と書いている（[`CommandsSpec.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-cli/test/CommandsSpec.hs#L236-L239)）。
インスタンス ID がすべての入力のハッシュであることを決めたのは [docs/adr/0002](0002-determinism.md) なので、`docs/adr/0002` に改め、この ADR を足す。

## 実装しないこと

- **`@style-def` で `space-after` を 0 に戻せないこと**：PDF と HTML の結果が食い違うので、別の ADR で扱う。
- **送った図版の後で待つ図版の前の `@need-lines` と行アキ、`@need-lines` の後の空き**：仕様書の「既知の不具合」の項目であり、golem-layout の別の ADR で直す。
- **境界の表の段落の行の数を列挙に足すこと**：段落を C + 1 行まで作ると、一段の候補が増え、毎晩の上限が下がる。範囲を広げる ADR（[ADR 0208](0208-widen-lightweight-formal-methods.md) の 1）で、ほかの要素と合わせて決める。
- **毎晩のページ分割の上限 6 を測ること**：上限は 5 のままとする。測り直すのは、一段の候補が変わるときである。
- **[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md) の残りの点**：wasi-sdk と libffi-wasm のライセンスの文書の出どころ、`golem_free` から `golem_font_free` への改名、`release.yml` の alex と happy の検査は、この ADR で扱わない。
- **規則の振る舞いを変えること**：記録だけを行う。

## 不変条件

記録する規則のうち、振る舞いを固定するものを不変条件として書く。
C は段の行の数とする。

- **A1 `fully-justified` の分割**：`fully-justified` の段落の行の分け方は、同じ項目の `left-justified` の段落と同じである。最後の行では、段落の終わりのグルーの伸びが 0 であり、ほかのグルーの伸びの和が足りるなら行は行長いっぱいになる。伸びるグルーのない最後の行は、行の始まりに寄る。
- **A2 改ページの前とファイルの境の空き**：強制の改ページと改ページの手での制御の直前、ファイルの最後のブロックと次のファイルの最初のブロックのあいだには、段落スタイルの空きの行を置かない。行アキ（`@blank-line`）は、この規則の対象ではない。
- **A3 両用の文字の隣の改行**：欧文の区間の両用の文字と、隣の和文の字のあいだで改行してよいのは、その両用の文字の和文の文字クラスの禁則と分離禁止が許すときだけである。
- **A4 表のファイルの BOM**：`formatTable` は、先頭の BOM をちょうど一つ取り除き、ほかの BOM を残す。先頭の BOM が一つまでの入力では、`formatTable` は冪等である。
- **A5 行アキの手順 3**：送った図版の後に続く行アキは、行アキと後の最初の部分が入る段か、段の先頭まで進む。段の先頭では捨てられ、`@blank-line` ごとに一つの `DroppedBlank` が記録される。送った図版を置いた段は、段の先頭ではない。
- **A6 `keep` の進む回数**：`keep` が進む段の数は、待っている図版の数と、続きの注の本文の行の数の和に 1 を足した数を超えない（[golem-layout ADR 0023](../golem-layout/adr/0023-keep-with-next-after-figures-sent-on.md) の F4 を改めたもの）。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| `fully-justified` の最後の行の伸びるグルー | 0、1、行の残りをちょうど埋める量、足りない量 |
| `fully-justified` の段落の行の数 | 1（短い一行）、2、`left-justified` が送り出しで分ける段落 |
| 空きの後に続くもの | 強制の改ページ、`@need-lines`、`@no-page-break`、次のファイルの最初の段落、同じファイルの段落 |
| `space-after` の行の数 | 0、1、C |
| 両用の文字 | 始め括弧類（`“`、`«`）、終わり括弧類（`”`、`›`）、分離禁止（`…`）、ダッシュ（`—`） |
| 先頭の BOM の数 | 0、1、2 |
| 行アキを置く段 | 送った図版を先頭に置いた段、続きの脚注だけを持つ段の先頭、空の段 |
| 待つものの数（A6） | 待つものなし、図版 1、図版 3 と注の本文 2 行 |

## テスト設計

今のテストが、各不変条件の一部を確かめている。

- A1：golem-layout の `AlignSpec` の「fully-justified sets the last line as wide as the others」ほか二つ。
- A3：golem-layout の `LangSpec` の「`the Latin marks of [lang en: “東京”] take no aki and no break beside the kanji`」。
- A4：golem-fmt のテストの「only the BOM at the start, and only one, is removed」と冪等性のプロパティ。
- A5：golem-layout の `PaginateSpec` の P4 の二つ。
- A6：golem-layout の `PaginateSpec` の「F3, F4」。

この ADR では、境界の入力の表の残りを足す。
テストの名前には、A1 から A6 の番号を入れる。

- **A1**：同じ項目を `left-justified` と `fully-justified` で分け、改行の位置が同じであること。表の三つの段落の形で確かめる。
- **A2**：golem-driver の PDF のテストで、`space-after` が 1 と C の段落の直後に強制の改ページ、`@need-lines`、`@no-page-break` を置いたとき、段の末尾に空きの行がないこと。二つのファイルの境の前後の段落のあいだに空きがなく、同じファイルの中の同じ組には空きがあること。
- **A3**：表の四つの両用の文字を `[lang en: …]` に入れ、和文の字と隣り合わせて 2 字の行で組み、禁則が許す側でだけ分かれること。
- **A4**：BOM が 0、1、2 の入力で、取り除く数がそれぞれ 0、1、1 であること。golem-cli のテストで、`@table` と `@listing` が読む一つのファイルに `golem fmt` をかけた後、`@listing` の一行めが BOM で始まらないこと。
- **A5**：続きの脚注だけを持つ段の先頭で、行アキが捨てられて記録され、その段を飛ばさないこと。
- **A6**：待つものがなく量が入らない状態で、進む回数がちょうど 1 であること。

A1 から A6 は今の実装で通る見込みで、先に失敗させることはできない。
今の振る舞いを固定するテストである。
仕様書の文とステータスの行は、`adr-guard links --fix` と `adr-guard pre-commit --allow-status --allow-links` が通ることで確かめる。

## トレードオフ

実装の後で ADR を書くので、どの点も、決める前に代わりの案を比べていない。
多くは、ADR の前提の誤り（セレクターの詳細度、`fully-justified` の badness、インスタンス ID の入力、F4 の式、P4 の例の入力）を、ADR の目的に合わせて正したものである。
残りは、ADR が書いていない端（散文スロットの数、両用の文字の禁則、ファイルの境、二つめの BOM、段の先頭）を、近くの既存の規則にそろえたものである。

一本の ADR に十五の ADR の点を集めたので、一つの点を変えたいときは、この ADR のその節だけを改める ADR を書くことになる。
点ごとに ADR を分けると、十五本の記録の ADR が並び、ステータスの行が読めなくなる。
規則を変えるときに出どころをたどれれば足りるので、節を元の ADR ごとに分け、ステータスの行からその節を引けるようにした。

[ADR 0208](0208-widen-lightweight-formal-methods.md) の毎晩の上限 5 と抜き取りの範囲は、記録すると、すべてを調べる範囲が ADR の見込みより狭いことを認めることになる。
上限を測り直す手間と、毎晩の 60 分の予算とを比べ、測るのは候補が変わるときまで延ばす。

## メンテナーが決めること

1. **規則と手順の記録（[ADR 0173](0173-rc4-refactoring.md)、[0182](0182-external-links.md)、[0183](0183-tagged-pdf-and-pdf-a.md)、[0184](0184-table-positional-path.md)、[0185](0185-project-wide-variables.md)、[0186](0186-fmt-table-files.md)、[0187](0187-inline-language-switch.md)、[0189](0189-paragraph-alignment-spacing-and-end-indent.md)、[0193](0193-line-paragraph-separator-by-default.md)、[0199](0199-pdf-typesetting-as-wasm-reactor.md)、[0200](0200-figures-and-listings-without-numbers.md)、[golem-layout ADR 0025](../golem-layout/adr/0025-need-lines-and-blank-lines-after-figures-sent-on.md)）をこのまま採るか**：推奨は、このまま採ることである。どれも ADR の目的を満たし、仕様書かプルリクエストの説明が書いている振る舞いを、ADR の出どころとして固定するだけである。
   - 退けた案の一つは、`fully-justified` を ADR の文のとおり、最後の行の badness を見る行分割に作り直すことである。終わりのグルーなしで分けると、一行の段落が二行に割れるので、行分割の最後の段階に `fully-justified` 用の例外を足すことになる。見た目は今と同じで、分ける位置が変わるだけである。
   - 二つめは、`formatTable` が先頭の BOM をすべて取り除くことである。読み手は二つめの BOM をセルの字として読むので、`golem fmt` が表の中身を変える。
   - 三つめは、ファイルの境の前後にも段落スタイルの空きを置くことである。`space-between` はファイルの境に置かないので、二つの空きの扱いが食い違う。
2. **テストの記録（[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md)、[0206](0206-pagination-points-the-invariants-did-not-decide.md)、[0208](0208-widen-lightweight-formal-methods.md)、[0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md)、[golem-layout ADR 0023](../golem-layout/adr/0023-keep-with-next-after-figures-sent-on.md)）をこのまま採るか**：推奨は、このまま採ることである。述語、列挙、上限の変数は、ADR の文より強いか、ADR の予算の中に収めるための変更である。
   - 退けた案の一つは、正規形と縦組みのテストをプルリクエストでも段 2 まで行うことである。golem-layout-test が 40 秒になり、[ADR 0208](0208-widen-lightweight-formal-methods.md) の 10 秒の予算を超える。
   - 二つめは、行の幅と L7 の候補の上限に専用の変数を足すことである。手元で一つだけを変えて調べる場面がまだなく、[ADR 0208](0208-widen-lightweight-formal-methods.md) の 4 の二つの変数の形を崩す。
3. **[ADR 0208](0208-widen-lightweight-formal-methods.md) の毎晩の上限**：推奨は、見積もりのまま 5 とし、一段の候補が変わるときに測り直すことである。測っても、見積もり（約 55 分）が 30 分の境の向こうにあるかぎり結論は変わらない。
   - 退けた案は、候補 19 の上限 6 を一度 CI で測ることである。測るための 60 分前後の実行は、毎晩の予算を一晩分使う。
4. **[ADR 0208](0208-widen-lightweight-formal-methods.md) の抜き取りの範囲**：推奨は、上限の一つ上の段だけから抜き取ることを記録し、上限以下の段で除いた入力を補うかは、範囲を広げる次の ADR で決めることである。
   - 退けた案は、上限以下の段の除いた入力からも抜き取ることである。抜き取りの数を段ごとに分ける規則が要り、今の一つの変数 `GOLEM_ENUM_PAGINATION_SAMPLES` で表せない。
5. **境界の表の段落の行の数（[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md)、[0206](0206-pagination-points-the-invariants-did-not-decide.md)）**：推奨は、C 行と C + 1 行の段落が C = 3（C 行は C = 4 も）でしか現れないことを記録し、列挙を広げるのは範囲を広げる ADR に回すことである。
   - 退けた案は、この ADR で段落を C + 1 行まで作ることである。一段の候補が段ごとに変わり、毎晩の上限と [ADR 0208](0208-widen-lightweight-formal-methods.md) の見積もりを測り直すことになる。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-08、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [ADR 0173](0173-rc4-refactoring.md)、[ADR 0182](0182-external-links.md)、[ADR 0183](0183-tagged-pdf-and-pdf-a.md)、[ADR 0184](0184-table-positional-path.md)、[ADR 0185](0185-project-wide-variables.md)、[ADR 0186](0186-fmt-table-files.md)、[ADR 0187](0187-inline-language-switch.md)、[ADR 0189](0189-paragraph-alignment-spacing-and-end-indent.md)、[ADR 0193](0193-line-paragraph-separator-by-default.md)、[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md)、[ADR 0200](0200-figures-and-listings-without-numbers.md)、[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md)、[ADR 0205](0205-rules-added-by-the-implementation-of-adr-0180.md)、[ADR 0206](0206-pagination-points-the-invariants-did-not-decide.md)、[ADR 0208](0208-widen-lightweight-formal-methods.md)、[ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md)、[docs/adr/0002](0002-determinism.md)
- [golem-layout ADR 0007](../golem-layout/adr/0007-knuth-plass-reference-test.md)、[golem-layout ADR 0016](../golem-layout/adr/0016-ellipsis-before-full-stop.md)、[golem-layout ADR 0023](../golem-layout/adr/0023-keep-with-next-after-figures-sent-on.md)、[golem-layout ADR 0025](../golem-layout/adr/0025-need-lines-and-blank-lines-after-figures-sent-on.md)
- 実装のプルリクエストの説明：[#596](https://github.com/tett23/golem/pull/596)、[#599](https://github.com/tett23/golem/pull/599)、[#602](https://github.com/tett23/golem/pull/602)、[#605](https://github.com/tett23/golem/pull/605)、[#610](https://github.com/tett23/golem/pull/610)、[#615](https://github.com/tett23/golem/pull/615)、[#627](https://github.com/tett23/golem/pull/627)、[#630](https://github.com/tett23/golem/pull/630)、[#643](https://github.com/tett23/golem/pull/643)、[#648](https://github.com/tett23/golem/pull/648)、[#650](https://github.com/tett23/golem/pull/650)、[#653](https://github.com/tett23/golem/pull/653)、[#654](https://github.com/tett23/golem/pull/654)、[#655](https://github.com/tett23/golem/pull/655)
- CSS の詳細度：Selectors Level 3、<https://www.w3.org/TR/selectors-3/#specificity>
