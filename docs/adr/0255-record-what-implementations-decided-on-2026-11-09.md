# ADR 0255: 2026-11-09 の実装が ADR を越えて決めた点を記録する

ステータス: 採択（未実装）

## 文脈

2026-11-09 に、[ADR 0249](0249-link-golem-with-a-64-mb-allocation-area.md)、[ADR 0250](0250-character-class-tables-instead-of-list-membership.md)、[ADR 0253](0253-memoise-run-shaping-and-shorten-the-memo-key.md)、[golem-layout ADR 0045](../golem-layout/adr/0045-break-inline-code-after-hyphens-and-full-stops-to-avoid-loose-lines.md) を実装した。
実装のプルリクエストは、順に [#765](https://github.com/tett23/golem/pull/765)、[#768](https://github.com/tett23/golem/pull/768)、[#769](https://github.com/tett23/golem/pull/769)、[#767](https://github.com/tett23/golem/pull/767) である。
#767 のほかはマージ済みで、#767 はこの ADR を書いた時点でまだ開いている（先頭のコミットは `06b6a02b`）。

どの実装にも、ADR が書いていない点を決めたもの、ADR の前提を取り違えていたもの、ADR の見積もりや期待が外れたものがある。
多くはプルリクエストの説明と `docs/benchmarks/` の記録に書かれているが、決めた ADR がない。
この ADR は、[ADR 0205](0205-rules-added-by-the-implementation-of-adr-0180.md)、[ADR 0211](0211-record-what-implementations-decided-found-by-the-review-of-2026-11-08.md)、[ADR 0236](0236-record-what-implementations-decided-found-by-the-second-review-of-2026-11-08.md) と同じく、それらを決めたこととして記録する。
どの点も、プルリクエストの説明を読み、マージのコミット（#767 は先頭のコミット）のコードで確かめた。

一つだけ、記録より重いものがある。
[golem-layout ADR 0045](../golem-layout/adr/0045-break-inline-code-after-hyphens-and-full-stops-to-avoid-loose-lines.md) の実装は、ADR が名を挙げていない表の列の幅の規則を変えた。
ADR の候補を足しただけでは、開発者のマニュアルが警告なしで組めなかったからである。
これは「メンテナーが決めること」の 1 で、記録して認めるかを決める。

以下、元の ADR の番号の順に並べる。
各項目は、ADR の文、実装、そうした理由の順に書く。

### [ADR 0249](0249-link-golem-with-a-64-mb-allocation-area.md)：小さい本のメモリ、速さの比べ方、CI の時間

小さい本のメモリの増え方は、ADR が書いている。
実装の記録（[docs/benchmarks/2026-11-09-link-golem-with-a-64-mb-allocation-area.md](../benchmarks/2026-11-09-link-golem-with-a-64-mb-allocation-area.md)）では、「total memory in use」が小さい入力で 130 MiB 前後から 800 MiB 前後になった（`snark` は 128 MiB から 720 MiB）。
比では 5 倍を超えるが、増えた量は十冊と『蟹工船』で 449 MiB から 638 MiB である。
ADR は「10 個の capability で `-A64m` は 640 MB」、トレードオフで「一回のビルドのメモリが 0.5 GB ほど増える」と書いており、増えた量はこれに合う。
ADR がメモリを載せた最小の入力は『蟹工船』（オプションなしで 0.44 GB から 0.46 GB、`-A64m` で 0.97 GB から 1.01 GB）で、比が最も大きくなる小さい入力を表に載せていなかっただけである。
この点は記録しない。

テスト設計は、壁時計の中央値が「記録の「なし」より 20% 以上短いこと」を、3 回の計測で確かめるとした。
実装は、変更前と変更後を交互に 5 周走らせ、同じ周の二回の比の中央値で 20% を判定した。
計測の計算機にほかのビルドの負荷があり（load average の中央値 15.2）、壁時計の絶対値が調査より長くなったためである。
変更後のマニュアルの壁時計の中央値は 10.35 秒で、調査の「なし」の 9.67 秒から 9.88 秒より長い。
ADR の文のとおりに調査の値と比べると、この計測は判定に使えない。

テスト設計の「CI の `cabal test` の時間は変わらないことを、実装のプルリクエストの実行で確かめる」は、プルリクエストの説明にも記録にも書かれていない。

### [ADR 0250](0250-character-class-tables-instead-of-list-membership.md)：判定の関数の公開と、割り当ての見積もり

ADR は、`Golem.Layout.Japanese` の局所の定義の `isJoiner` と `isHyphen` を「同じ形にする」とだけ書いた。
実装は、字の判定を `isJoinerCharacter` と `isHyphenCharacter` として `Golem.Layout.CharClass` から公開した（[`CharClass.hs`](https://github.com/tett23/golem/blob/b0dbdb113cfae9ee05cbeece842ba6b250e9c305/modules/golem-layout/src/Golem/Layout/CharClass.hs#L94-L108)）。
`isJoiner` は区間の条件を残し、字の判定だけをこの関数に任せる（[`Japanese.hs` の 661 行](https://github.com/tett23/golem/blob/b0dbdb113cfae9ee05cbeece842ba6b250e9c305/modules/golem-layout/src/Golem/Layout/Japanese.hs#L661)、[1097 行](https://github.com/tett23/golem/blob/b0dbdb113cfae9ee05cbeece842ba6b250e9c305/modules/golem-layout/src/Golem/Layout/Japanese.hs#L1097)）。
不変条件 I3 は二つの関数をすべてのコードポイントで元の定義と比べることを求め、局所の定義ではテストから呼べないためである（[`CharClassSpec.hs`](https://github.com/tett23/golem/blob/b0dbdb113cfae9ee05cbeece842ba6b250e9c305/modules/golem-layout/test/CharClassSpec.hs#L22-L27)）。

ADR は「GC の時間は変わらない（復号はほとんど割り当てない）」と見積もった。
実装の記録（[docs/benchmarks/2026-11-09-character-class-tables.md](../benchmarks/2026-11-09-character-class-tables.md)）では、割り当てが半分になった（マニュアルで 50.0 GB から 23.2 GB）。
世代 0 の GC の回数も 73 回から 32 回になった。
融合の後の `elem` も、リテラルの復号で割り当てていたことになる。
GC の時間そのものは、記録に書かれていない。
見積もりが外れた向きは良い側で、振る舞いは変わらない（I4）。

### [ADR 0253](0253-memoise-run-shaping-and-shorten-the-memo-key.md)：符号つきの特徴、スタイルにない役割、二つの見積もり、テストの依存

ADR は、特徴を「OpenType のタグ 4 字」として、4 字を 14 ビットずつの 2 要素にするとした。
`shapingOf` が渡す特徴には、`-kern`、`-vkrn`、`-palt`、`-vpal` のように符号の付いたものがある（[`Fonts.hs`](https://github.com/tett23/golem/blob/fdb37d76dd919e4ede5d89fbb46a6741ce5d5276/modules/golem-typeset/src/Golem/Typeset/Fonts.hs#L514-L527)）。
ADR の文のとおりに符号の付いた特徴を範囲の外にすると、これらの特徴を持つキーはメモに残らない。
約物と欧文の送りは ADR の前からメモに残っていたので、これは後退になる。
実装は、2 要素の形を保ったまま、一つめの要素の 14 ビットの上に符号の値（`+` は 1、`-` は 2、符号なしは 0）を置いた（[`Memo.hs` の `featureDigits`](https://github.com/tett23/golem/blob/fdb37d76dd919e4ede5d89fbb46a6741ce5d5276/modules/golem-typeset/src/Golem/Typeset/Memo.hs#L100-L115)、逆は [`fromShapingTextKey`](https://github.com/tett23/golem/blob/fdb37d76dd919e4ede5d89fbb46a6741ce5d5276/modules/golem-typeset/src/Golem/Typeset/Memo.hs#L145-L153)）。
一つめの要素は最大で 2 × 2^14 + 2^14 − 1 = 49,151 で、`digitLimit`（2^24）より小さい。
`digitLimit` も木の深さも変わらない。
`kern=0` のようなタグでない形と ASCII でない特徴は、ADR のとおり範囲の外で、メモせずに計算する。

ADR の境界の表は、スタイルにない役割を挙げたが、そのキーを決めていない。
実装は、役割の表の最後の番号の次の番号を付け、その後に役割の名前を文字列として並べる（[`Memo.hs` の `shapingTextKey`](https://github.com/tett23/golem/blob/fdb37d76dd919e4ede5d89fbb46a6741ce5d5276/modules/golem-typeset/src/Golem/Typeset/Memo.hs#L81-L95)）。
キーは範囲の中にあり、逆を持つ。

ADR のテスト設計は「`sample` で `trieAt` の割合が半分以下になること」を求めた。
実装の記録（[docs/benchmarks/2026-11-09-memoise-run-shaping.md](../benchmarks/2026-11-09-memoise-run-shaping.md)）では、マニュアルで 6.0% から 5.8% で、満たさない。
一字の送りのキーは短くなった（`body` で特徴がないとき 10 要素から 4 要素）が、新しく単語とランのシェイピングもメモを引くようになり、そのキーはテキストの字の数だけ長い。

ADR のトレードオフは、メモリの増加を「数十 MB」と見積もった。
最大常駐は、マニュアルで 664 MB から 720 MB、開発者向けマニュアルで 497 MB から 629 MB に増えた。
「total memory in use」は、マニュアルで 2,327 MiB から 2,527 MiB、開発者向けマニュアルで 1,657 MiB から 1,947 MiB に増えた。
測った三冊のパブリックドメインの本では、最大常駐は『蟹工船』と『平将門』で減り、『Nightmare Abbey』で 7 MB 増えただけだった。
その代わり、壁時計はマニュアルで 2%、開発者向けマニュアルで 3%、『蟹工船』で 17% 短くなった。

テスト設計は、I2 と I3 を hedgehog の性質で確かめるとした。
golem-typeset-test は hedgehog に依存していなかったので、実装は `hedgehog` と `tasty-hedgehog` を足した（[`golem-typeset.cabal`](https://github.com/tett23/golem/blob/fdb37d76dd919e4ede5d89fbb46a6741ce5d5276/modules/golem-typeset/golem-typeset.cabal#L76-L78)）。
どちらも golem の外のパッケージで、golem-* のあいだの依存は変わらない。
テスト設計の「メモを通さない `shapeText`（テストだけに公開する）」は、メモを通さない提供者 `unmemoisedFontProvider` を `Golem.Typeset.FontProvider` から公開する形にした（[`FontProvider.hs`](https://github.com/tett23/golem/blob/fdb37d76dd919e4ede5d89fbb46a6741ce5d5276/modules/golem-typeset/src/Golem/Typeset/FontProvider.hs#L48-L53)）。

### [golem-layout ADR 0045](../golem-layout/adr/0045-break-inline-code-after-hyphens-and-full-stops-to-avoid-loose-lines.md)：表のセルの最小の幅、G09013 の文、J5 の確かめ方

ADR は、表の列の幅の規則に触れていない。
プルリクエストの説明によれば、ADR の候補だけを足すと、開発者のマニュアルの表のセル `[code: \[index reading=...: ...\]]`（[`06-ir.gm` の 272 行](https://github.com/tett23/golem/blob/06b6a02b85f3b450638ca92ae56f436bd7d79e63/manual-dev/part1/06-ir.gm#L272)）に、G07105 のはみ出した行が出た。
`...` の後に新しい候補ができ、列の幅が最も広い部分 `reading=...` の幅まで縮んだ。
その候補で改行した行は改行の印も持つので、どちらの候補でも行に収まらなかった。

原因は `Golem.Layout.Table.cellExtent` にある。
`cellExtent` は、改行の候補のあいだの最も広い部分の幅をセルの最小の幅とする。
候補の罰点で終わる部分の幅に、罰点の幅（その候補で改行した行が行末に持つ改行の印の幅）を足していなかった。
コードの改行の候補は、印の幅を罰点の幅として持つ（[`Japanese.hs` の `codeBreak`](https://github.com/tett23/golem/blob/06b6a02b85f3b450638ca92ae56f436bd7d79e63/modules/golem-layout/src/Golem/Layout/Japanese.hs#L1349-L1354)）。
同じ欠けは、`/` の後の候補と [golem-layout ADR 0034](../golem-layout/adr/0034-line-breaks-between-japanese-characters-in-inline-code.md) の和文の字との境の候補にも、前からあった。
実装は、罰点で終わる部分の幅に、その罰点の幅を足した（[`Table.hs`](https://github.com/tett23/golem/blob/06b6a02b85f3b450638ca92ae56f436bd7d79e63/modules/golem-layout/src/Golem/Layout/Table.hs#L20-L41)）。
テストは `ab-c` と `ab/c` のセルで、最小の幅が 3 字と印の幅の和になることを確かめる（[`Main.hs`](https://github.com/tett23/golem/blob/06b6a02b85f3b450638ca92ae56f436bd7d79e63/modules/golem-layout/test/Main.hs#L1005-L1011)）。
仕様書の表の節の列の幅の文に、印の幅を含むことを書いた。
golem-layout の段落の項目で、幅を持つ有限の罰点は、パターンの分綴とこの印の二つだけである。
パターンの分綴は前から候補に数えないので、変わるのはコードの改行の印を描く候補で終わる部分だけである。

ADR の「実装すること」の 4 は、G07105 と G09013 の主な原因のうち、コードの改行の位置を挙げる文に `-` と `.` を足すとした。
[G09013](../diagnostics.md#g09013) の主な原因には、コードの改行の位置を挙げる文がない（「分割できない長い語や URL がある」と「行長が短い」だけである）。
実装は G07105 の文だけを変えた。

ADR の「実装すること」の 3 は、J1 から J7 を列挙の述語として足すとした。
J5 は、項目をこの ADR の前の実装の項目と比べる性質で、一つの出力からは判定できない。
実装は J5 を述語にせず（[`LineBreakInvariants.hs`](https://github.com/tett23/golem/blob/06b6a02b85f3b450638ca92ae56f436bd7d79e63/modules/golem-layout/test/LineBreakInvariants.hs#L55-L62)）、ADR のテスト設計の J5 のとおり、[golem-layout ADR 0018](../golem-layout/adr/0018-url-line-breaks.md)、[0031](../golem-layout/adr/0031-line-breaks-after-low-lines-in-identifiers.md)、[0034](../golem-layout/adr/0034-line-breaks-between-japanese-characters-in-inline-code.md) の今のテストを変えずに通すことと、新しい J5 のテスト（`url` と地の文の `lime-tree`）で確かめた。

## 実装すること

ここに記録した規則と手順は、#767 のほかは main に入っている（`fdb37d76` で確かめた）。
この ADR の実装は、#767 がマージされた後に、次のことだけを行う。

- 次の ADR のステータスの行に、この ADR が記録した点を足す。すでに `→` を持つ行には `、` でつないで足す。
  - 0249（速さの比べ方、CI の時間）、0250（判定の関数の公開、割り当ての見積もり）、0253（符号つきの特徴、スタイルにない役割のキー、`trieAt` とメモリの見積もり、テストの依存と公開した提供者）
  - golem-layout 0045（表のセルの最小の幅、G09013 の文、J5 の確かめ方）
- 仕様書の表の節の、列の最小の幅が印の幅を含むという文に、この ADR へのリンクを足す。
- `Golem.Layout.Table.cellExtent` と `Golem.Typeset.Memo.featureDigits` の注釈に、この ADR へのリンクを足す。
- `cellExtent` のテストに、不変条件 W1 の境界の入力のうち今のテストが覆っていない行を足し、テストの名前に W1 を入れる。
- この ADR が #767 の先頭のコミット `06b6a02b` を指す URL を、#767 のマージのコミットを指す URL に替える。リンクだけの変更なので、コミットの後でも adr-guard が許す。

## 実装しないこと

- **規則の振る舞いを変えること**：記録だけを行う。`cellExtent` の変更は #767 が入れる。
- **G09013 の主な原因にコードの改行の位置の文を足すこと**：G09013 の主な原因は短く、コードの文は G07105 にある。足すかは、G09013 の文を変えるプルリクエストで決める。
- **J5 を述語にすること**：前の実装を列挙のテストに残すことになり、J5 のためだけに古い項目の作り方を保つことになる。
- **[ADR 0253](0253-memoise-run-shaping-and-shorten-the-memo-key.md) のメモリを調べること**：「メンテナーが決めること」の 3 で、推奨の案を採るなら行わない。
- **[ADR 0249](0249-link-golem-with-a-64-mb-allocation-area.md) の計測をやり直すこと**：負荷のない計算機で調査の値と比べ直すことはしない。同じ周の比は、同じ負荷のもとで前と後を比べており、判定の目的に足りる。
- **CI の `cabal test` の時間を今から確かめること**：テストのスイートの RTS は変わっていない（[ADR 0249](0249-link-golem-with-a-64-mb-allocation-area.md) の「実装しないこと」）。

## 不変条件

[ADR 0249](0249-link-golem-with-a-64-mb-allocation-area.md)、[ADR 0250](0250-character-class-tables-instead-of-list-membership.md)、[ADR 0253](0253-memoise-run-shaping-and-shorten-the-memo-key.md) の分は、なし。
すでに入った振る舞いと手順を記録するだけで、振る舞いを変えない。
符号つきの特徴のキーは、[ADR 0253](0253-memoise-run-shaping-and-shorten-the-memo-key.md) の I2 と I3 がそのまま覆う（I3 の「OpenType のタグ」を、符号の付いたタグを含むと読む）。

表のセルの最小の幅について、次の性質が成り立つ。
「部分」は、セルの項目を改行の候補（箱の後のグルーと、罰点が無限でなくパターンの分綴でない罰点）で区切った一つとする。

- **W1 罰点で終わる部分は罰点の幅を持つ**：どのセルの項目でも、`cellExtent` の最小の幅は、各部分の幅の最大である。罰点で終わる部分の幅は、部分の中の箱とグルーの幅の和に、その罰点の幅を足したものである。グルーで終わる部分と、項目の終わりで終わる部分の幅は、部分の中の箱とグルーの幅の和である。

W1 から、罰点の幅が 0 の候補（`wrap-mark = ""` の `NoHyphen`、明示のハイフン、コードの外の和文の改行）だけを持つセルの最小の幅は、この ADR の前と変わらない。
W1 は、部分だけを一行に組んでその終わりの候補で改行したときに行末に描く印の幅を、列の最小の幅に数えることを述べる。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 部分の終わり | コードの `-` の後の候補（`ab-c`）、`/` の後の候補（`ab/c`）、`_` の連なりの後の候補、和文の字との境の候補（`ab漢字`）、グルー、項目の終わり |
| 印 | 既定の印、`wrap-mark = ""`（幅 0） |
| 最も広い部分 | 罰点で終わる部分、項目の終わりで終わる部分（印を持たない最後の部分が最も広い） |
| 候補の数 | なし（`abcd`）、一つ、二つ（`a-b.c`） |
| 罰点 | 有限、無限（候補でない）、パターンの分綴（候補でない） |

## テスト設計

- W1：`modules/golem-layout/test/Main.hs` の `cellExtent` のテストに、境界の表のうち今のテスト（`ab-c` と `ab/c`）が覆っていない行（`_` の候補、和文の字との境、`wrap-mark = ""`、印を持たない最後の部分が最も広いセル、候補のないセル、候補の二つあるセル）を足す。今のテストの名前にも W1 を入れる。実装は #767 で入っているので、足すテストは初めから通る。#767 の変更の前の `cellExtent`（罰点の幅を足さない形）で、印を持つ行のテストが失敗することを一度確かめる。
- ステータスの行と注釈と仕様書の文は、`adr-guard links --fix` と `adr-guard pre-commit --allow-status --allow-links` が通ることで確かめる。

## トレードオフ

実装の後で ADR を書くので、どの点も、決める前に代わりの案を比べていない。
[ADR 0236](0236-record-what-implementations-decided-found-by-the-second-review-of-2026-11-08.md) と同じく、点ごとに ADR を分けずに一本にまとめ、ステータスの行からその節を引けるようにした。

表のセルの最小の幅は、[golem-layout ADR 0045](../golem-layout/adr/0045-break-inline-code-after-hyphens-and-full-stops-to-avoid-loose-lines.md) の範囲の外の規則を、その実装のプルリクエストで変えた。
別のプルリクエストに分ければ、二つの変更の出力の差を別々に見られた。
分けると、#767 だけでは開発者のマニュアルに G07105 が出て、マニュアルを警告なしで組むこと（[golem-layout ADR 0045](../golem-layout/adr/0045-break-inline-code-after-hyphens-and-full-stops-to-avoid-loose-lines.md) の「メンテナーが決めること」の 6）を満たさない。

[ADR 0253](0253-memoise-run-shaping-and-shorten-the-memo-key.md) の符号の置き方は、ADR の推奨の「2 要素、14 ビットずつ」を保ち、使っていなかった上のビットを使う。
符号の種類が増えれば（HarfBuzz の特徴の文字列には `kern=0` や範囲の指定もある）、また範囲の外になる。
今の `shapingOf` が作るのは、符号なしと `-` の付いたタグだけである。

[ADR 0253](0253-memoise-run-shaping-and-shorten-the-memo-key.md) のメモリの増加は、見積もりの数倍である。
壁時計の短縮は、マニュアルで 2% から 3% と小さく、縦組みの本で大きい。
メモリの小さい計算機でマニュアルを組む利用者には、この交換は良くない。
[ADR 0249](0249-link-golem-with-a-64-mb-allocation-area.md) の nursery の 640 MB に比べれば小さく、今は問題になっていない。

## メンテナーが決めること

1. **表のセルの最小の幅に罰点の幅を含めること**：推奨は、#767 の形を記録して認めることである。印を描く行は印の幅だけ長いので、列の幅が印を含まなければ、その候補で改行した行は収まらない。前から `/` と和文の字との境の候補にあった欠けも直る。
   - 退けた案は、`cellExtent` を戻し、表のセルではコードの `-` と `.` の候補を置かないことである。セルと本文で改行の位置が変わり、`/` の候補の欠けも残る。
2. **[ADR 0253](0253-memoise-run-shaping-and-shorten-the-memo-key.md) の符号つきの特徴の符号**：推奨は、今の符号（14 ビットの上に `+` は 1、`-` は 2）を記録して認めることである。ADR の推奨した 2 要素の形と `digitLimit` を保ち、ADR の前にメモに残っていたキーを残す。
   - 退けた案は、ADR の文のとおり符号の付いた特徴を範囲の外にすることである。約物と欧文の送りがメモに残らなくなり、遅くなる。
   - もう一つは、符号を 3 つめの要素にすることである。範囲は広いが、キーが一要素長くなる。
3. **[ADR 0253](0253-memoise-run-shaping-and-shorten-the-memo-key.md) のメモリと `trieAt` を調べるか**：推奨は、今は調べず、記録だけにすることである。出力は変わらず、すべての入力で壁時計と CPU 時間が縮んでいる。メモリが問題になったとき（メモリの小さい CI のランナーで組めないなど）に、ランのメモのキーの形（テキストの字の数だけ長い）とメモに残す範囲を見直す ADR を書く。
   - 退けた案は、今、ロードマップに調べる項目を足すことである。何を目標にするか（メモリの上限か、`trieAt` の割合か）が決まっておらず、項目が閉じられない。
4. **そのほかの記録をこのまま採るか**：推奨は、このまま採ることである。どれも、ADR の前提の誤りを ADR の目的に合わせて正したか、ADR が書いていない端を近くの規則にそろえたか、見積もりの外れを記録したものである。
   - 退けた案は、[ADR 0249](0249-link-golem-with-a-64-mb-allocation-area.md) を負荷のない計算機で測り直し、調査の値と比べることである。同じ周の比のほうが負荷の影響を受けにくく、測り直しの費用に見合わない。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-09、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [ADR 0205](0205-rules-added-by-the-implementation-of-adr-0180.md)、[ADR 0211](0211-record-what-implementations-decided-found-by-the-review-of-2026-11-08.md)、[ADR 0236](0236-record-what-implementations-decided-found-by-the-second-review-of-2026-11-08.md)、[ADR 0249](0249-link-golem-with-a-64-mb-allocation-area.md)、[ADR 0250](0250-character-class-tables-instead-of-list-membership.md)、[ADR 0253](0253-memoise-run-shaping-and-shorten-the-memo-key.md)
- [golem-layout ADR 0018](../golem-layout/adr/0018-url-line-breaks.md)、[golem-layout ADR 0031](../golem-layout/adr/0031-line-breaks-after-low-lines-in-identifiers.md)、[golem-layout ADR 0034](../golem-layout/adr/0034-line-breaks-between-japanese-characters-in-inline-code.md)、[golem-layout ADR 0045](../golem-layout/adr/0045-break-inline-code-after-hyphens-and-full-stops-to-avoid-loose-lines.md)、[golem-driver ADR 0037](../golem-driver/adr/0037-table-column-widths.md)
- [docs/benchmarks/2026-11-09-link-golem-with-a-64-mb-allocation-area.md](../benchmarks/2026-11-09-link-golem-with-a-64-mb-allocation-area.md)、[docs/benchmarks/2026-11-09-character-class-tables.md](../benchmarks/2026-11-09-character-class-tables.md)、[docs/benchmarks/2026-11-09-memoise-run-shaping.md](../benchmarks/2026-11-09-memoise-run-shaping.md)
- 実装のプルリクエストの説明：[#765](https://github.com/tett23/golem/pull/765)、[#767](https://github.com/tett23/golem/pull/767)、[#768](https://github.com/tett23/golem/pull/768)、[#769](https://github.com/tett23/golem/pull/769)
