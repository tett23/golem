# ADR 0256: [ADR 0251](0251-reuse-the-compositions-of-unchanged-units-between-fixpoint-rounds.md) と [ADR 0252](0252-draw-and-serialise-the-pages-of-the-pdf-in-parallel.md) の実装が ADR を越えて決めた点を記録する

ステータス: 採択（未実装）

## 文脈

[ADR 0255](0255-record-what-implementations-decided-on-2026-11-09.md) は、2026-11-09 の実装のうち [ADR 0249](0249-link-golem-with-a-64-mb-allocation-area.md)、[ADR 0250](0250-character-class-tables-instead-of-list-membership.md)、[ADR 0253](0253-memoise-run-shaping-and-shorten-the-memo-key.md) の分を記録した。
[ADR 0251](0251-reuse-the-compositions-of-unchanged-units-between-fixpoint-rounds.md) と [ADR 0252](0252-draw-and-serialise-the-pages-of-the-pdf-in-parallel.md) は、[ADR 0255](0255-record-what-implementations-decided-on-2026-11-09.md) を書いた時点では実装が終わっていなかった。
その後、[#770](https://github.com/tett23/golem/pull/770)（[ADR 0252](0252-draw-and-serialise-the-pages-of-the-pdf-in-parallel.md)）と [#774](https://github.com/tett23/golem/pull/774)（[ADR 0251](0251-reuse-the-compositions-of-unchanged-units-between-fixpoint-rounds.md)）がマージされた。
2026-11-09 の監査で、この二つの実装にも、ADR が書いていない点を決めたものと、ADR の前提を取り違えていたものが見つかった。
この ADR は、[ADR 0255](0255-record-what-implementations-decided-on-2026-11-09.md) と同じく、それらを決めたこととして記録する。
どの点も、プルリクエストの説明と `docs/benchmarks/` の記録を読み、`main` の `3a93bf6d` のコードで確かめた。
採択の前に、`main` の `e6fa2944` でも、ここで挙げた `Flow.hs`、`Draw.hs`、`Writer.hs` が `3a93bf6d` から変わっていないことを確かめた。

以下、元の ADR の番号の順に並べる。
各項目は、ADR の文、実装、そうした理由の順に書く。

### [ADR 0251](0251-reuse-the-compositions-of-unchanged-units-between-fixpoint-rounds.md)：`Unit` の `Eq`、リストの印の幅、公開した関数、本の形で確かめていない境界

ADR は「`Unit` は `Eq` を持つ」と書き、`Unit` の定義の行を指した。
指した行の `Unit` は `deriving` を持たず、`UnitKind` も持っていなかった。
実装は、`Unit` と `UnitKind` に `deriving stock (Eq)` を足した（[`Flow.hs` の 1244 行](https://github.com/tett23/golem/blob/3a93bf6d5530cad30c056c26b81efcd36a65bfce/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L1244)、[1405 行](https://github.com/tett23/golem/blob/3a93bf6d5530cad30c056c26b81efcd36a65bfce/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L1405)）。
`Unit` のすべてのフィールドの型（`Style`、`Look`、`Frame`、`Figure`、`Code` など）は `Eq` を持っていたので、導出だけで済んだ。
導出した `==` は構造の比較で、ADR が使い回しのキーとした「前の周の単位と同じ値」をそのまま判定する。

ADR は、使い回しの条件を「単位の列の長さが前の周と同じ」「位置 i の単位が前の周と等しい」「`refersToPage` が偽」の三つとした。
実装は、これに「リストの印の幅の表（`widths`）が前の周と等しい」を足した（[`Flow.hs` の 2410 行から 2413 行](https://github.com/tett23/golem/blob/3a93bf6d5530cad30c056c26b81efcd36a65bfce/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L2410-L2413)）。
`composeUnit` は単位と環境のほかに `widths` を引数に取り、リストの中の段落の字下げをそれで決める。
`widths` は、その周の全単位の印から `listWidths` が計算する。
印の中身が周で変わる単位があれば、同じリストのほかの単位の字下げも変わりうるので、単位そのものが等しくても組版は等しくない。
`listMarker` が作る印はスタイルの記号と番号の書式だけで `[ref-page]` を持たないので、`widths` が周で変わる本は今のコードでは作れない。
条件は守りのためで、費用は `Map` の比較一回である。

ADR は、使い回しの切り替えを「テストだけが使う `layoutPdfWith` を `Golem.Typeset` から公開する」とした。
実装は、それに加えて `renderPdfAllReusing` を `Golem.Typeset.Draw` から公開した（[`Draw.hs` の 105 行から 106 行](https://github.com/tett23/golem/blob/3a93bf6d5530cad30c056c26b81efcd36a65bfce/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L105-L106)）。
不変条件 I1 は PDF のバイト列と diagnostics の一致を求め、`layoutPdfWith` の結果（`PdfLayout`）には `Eq` がない。
`ParallelSpec` と同じ形で PDF のバイト列を比べるには、描画と書き出しまで通す入口が要る。

ADR の境界の表は、周の数に「3 以上」と「`maxIterations` に達して G07021 になるもの」、単位の列に「長さが前の周と異なる」を挙げ、テスト設計は「境界の表の各行を golem-driver-test の fixture として置く」とした。
実装は、この三つの行を本の形の fixture では置いていない。
周の数の二つは、`fixpoint` に周ごとに番号を返す偽の `layoutWith` を渡すテストが覆う。
I5 のテストはラベルのページを周ごとに入れ替え、5 周めで止まるまでの各周が直前の周の値だけを受け取ることを確かめる（[`ReuseSpec.hs` の 128 行から 137 行](https://github.com/tett23/golem/blob/3a93bf6d5530cad30c056c26b81efcd36a65bfce/modules/golem-driver/test/ReuseSpec.hs#L128-L137)）。
G07021 のテストは前からあり、`layoutWith` の型の変更に合わせて引数を一つ足した（[`DiagnosticsSpec.hs` の 593 行から 621 行](https://github.com/tett23/golem/blob/3a93bf6d5530cad30c056c26b81efcd36a65bfce/modules/golem-driver/test/DiagnosticsSpec.hs#L593-L621)）。
本の形で 3 周めに入るには、2 周めで仮のページを得たラベルの参照が行数を変え、別のラベルのページを動かす本が要る。
行数が変わるかは行分割の結果で決まり、小さな本で狙って作るのは難しい。
単位の列の長さが周で変わる本は、知られていない。
`unitsOf` は索引と一覧の行の中身（ページの列）を仮のページから作るが、行の数は変えない。
長さの条件は守りのためにあり、条件が偽になる入力を今のコードでは作れない。

境界の表の「図版に沿わせる段落：図版だけが変わる」の行も、#774 では置かれていなかった。
これは、キャプションに `[ref-page]` を持つ回り込みの図版で作れるので、監査のプルリクエスト [#778](https://github.com/tett23/golem/pull/778) が fixture を足した。

### [ADR 0252](0252-draw-and-serialise-the-pages-of-the-pdf-in-parallel.md)：`Draw.hs` の spark

ADR は「`Draw.hs` は変えない」と書いた。
「メンテナーが決めること」の 2 は、まず `writePdf` の中だけで並列にして測り、描画が `used` の走査で逐次に進む分が大きければ、`renderPdfAllWith` で `pdfPages` を先に spark で投げるとした。
実装は、`writePdf` の中だけで並列にして測った。
書き出しはマニュアルで 1.98 秒から 1.01 秒になったが、描画は 1.6 秒のまま動かず、描画と書き出しの合計は `-N1` の 1.2 倍にとどまった（[docs/benchmarks/2026-11-09-pages-of-the-pdf-in-parallel.md](../benchmarks/2026-11-09-pages-of-the-pdf-in-parallel.md) の「書き出しだけを並列にした場合」）。
そこで実装は、`Draw.hs` の `writeDocumentView` で、`used` を取る前に各ページの `pdUses`（そのページが使うグリフ）を `parPages` で spark に投げた（[`Draw.hs` の 381 行から 383 行](https://github.com/tett23/golem/blob/3a93bf6d5530cad30c056c26b81efcd36a65bfce/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L381-L383)）。
spark が弱頭部正規形まで評価するのは、ページごとのグリフの番号とテキストの長さの和で、これが各ページのシェイピングを別の capability で進める。
`parPages` は golem-pdf の `Golem.Pdf.Writer` から公開し、golem-typeset が使う。
golem-typeset は前から golem-pdf に依存しているので、`build-depends` は変わらない（I3）。

ADR の推奨の形（`pdfPages` を先に投げる）を採らなかった理由は、依存の向きにある。
ページの内容ストリームの印は、ActualText を決めるために `deTextEntries` を読む（[`Draw.hs` の 549 行](https://github.com/tett23/golem/blob/3a93bf6d5530cad30c056c26b81efcd36a65bfce/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L549)）。
`deTextEntries` は `used` から作る。
したがって `pdfPages` の評価は `used` の評価を含み、`used` の前に `pdfPages` を投げても、描画の逐次の分は減らない。
`pdUses` は `deTextEntries` を読まないので、`used` の前に投げられる。

結果は変わらない。
記録では、前と後、capability 10 と 1 のすべての回で同じ入力の PDF の MD5 は一つで、`scripts/env-determinism/check.sh` の `caps-one` と `caps-two` も通った。
描画と書き出しの合計は `-N1` の 2.1 倍から 3.7 倍になり、ADR の見積もり（2.2 倍から 3 倍）に合う。

## 実装すること

ここに記録した規則と手順は、`main` の `3a93bf6d` に入っている。
この ADR の実装は、次のことだけを行う。

- [ADR 0251](0251-reuse-the-compositions-of-unchanged-units-between-fixpoint-rounds.md) と [ADR 0252](0252-draw-and-serialise-the-pages-of-the-pdf-in-parallel.md) のステータスの行に、この ADR が記録した点を足す。0251 は「`Unit` の `Eq`、リストの印の幅の条件、公開した関数、本の形で確かめていない境界」、0252 は「`Draw.hs` の spark」である。
- 仕様書の、使い回しの条件を書いた文（「単位の数か、リストの印の幅が前の周と異なる周は、すべての単位を組み直す」）と、描画が並列になることを書いた文に、この ADR へのリンクを足す。
- `Golem.Typeset.Flow` の `buildFlow` の `unchanged` の注釈と、`Golem.Typeset.Draw` の `used` の注釈に、この ADR へのリンクを足す。
- 「図版だけが変わる」の fixture は [#778](https://github.com/tett23/golem/pull/778) が足した。この ADR の実装では足さない。

## 実装しないこと

- **規則の振る舞いを変えること**：記録だけを行う。
- **「3 以上」「G07021」「長さが異なる」を本の形の fixture にすること**：「メンテナーが決めること」の 3 で、推奨の案を採るなら行わない。
- **`Draw.hs` の spark を ADR の文のとおり `renderPdfAllWith` に移すこと**：`pdfPages` は `used` に依存するので、移しても描画は並列にならない。
- **`widths` の条件を外すこと**：費用は `Map` の比較一回で、外して得るものがない。

## 不変条件

なし。
すでに入った振る舞いと手順を記録するだけで、振る舞いを変えない。
`Draw.hs` の spark は [ADR 0252](0252-draw-and-serialise-the-pages-of-the-pdf-in-parallel.md) の I1（spark の有無で出力は変わらない）がそのまま覆う。
`Unit` の `Eq` と `widths` の条件は [ADR 0251](0251-reuse-the-compositions-of-unchanged-units-between-fixpoint-rounds.md) の I1（使い回しの結果は組み直しと同じ）が覆う。
`widths` の条件が偽になる入力は今のコードでは作れないので、その条件だけを確かめる述語は書けない。

## テスト設計

- ステータスの行と注釈と仕様書の文は、`adr-guard links --fix` と `adr-guard pre-commit --allow-status --allow-links` が通ることで確かめる。
- 「図版だけが変わる」の fixture は、[#778](https://github.com/tett23/golem/pull/778) のテスト（`ReuseSpec` の I3 と I1 の行）が通ることで確かめる。そのテストは、キャプションに `[ref-page]` を持つ回り込みの図版に沿わせた段落が、使い回しの有無によらず同じ回数だけ組まれること（図版の単位が周で変わるので、沿わせた段落も組み直す）と、PDF のバイト列と diagnostics が一致することを確かめる。

## トレードオフ

実装の後で ADR を書くので、どの点も、決める前に代わりの案を比べていない。
[ADR 0255](0255-record-what-implementations-decided-on-2026-11-09.md) と同じく、点ごとに ADR を分けずに一本にまとめた。

`Draw.hs` の spark は、[ADR 0252](0252-draw-and-serialise-the-pages-of-the-pdf-in-parallel.md) が「変えない」と書いたファイルを変えた。
ADR の推奨は `pdfPages` を投げることだったが、それでは描画が並列にならないことは、依存を読めば ADR を書いた時点でわかった。
ADR の前提の誤りを実装が見つけて直した形で、[ADR 0255](0255-record-what-implementations-decided-on-2026-11-09.md) の [ADR 0253](0253-memoise-run-shaping-and-shorten-the-memo-key.md) の符号つきの特徴と同じ種類である。

本の形で確かめていない境界の三つの行は、`fixpoint` の偽の `layoutWith` のテストで覆われている。
偽の `layoutWith` は `buildFlow` を通らないので、3 周め以降に使い回しが正しく働くことは、I1 の性質（使い回しの結果は組み直しと同じ）と、2 周めで働くことの組み合わせから導くしかない。
使い回しのコードは周の番号を見ず、直前の周の値だけを見るので、2 周めと 3 周めで違う経路はない。

## メンテナーが決めること

1. **`Draw.hs` の spark を記録して認めるか**：推奨は、認めることである。描画と書き出しの合計の速度向上は ADR の見積もりどおりで、出力は変わらない。
   - 退けた案は、`Draw.hs` を戻して `writePdf` の中だけで並列にすることである。合計の速度向上は 1.2 倍にとどまり、ADR の「2 倍以上」を満たさない。
2. **`Unit` と `UnitKind` の `Eq` と、`widths` の条件を記録して認めるか**：推奨は、認めることである。`Eq` は ADR が前提にしたものを補っただけで、`widths` の条件は守りのためで費用がない。
3. **本の形で確かめていない境界の行をどうするか**：推奨は、`fixpoint` の偽の `layoutWith` のテストで覆われているとして記録し、本の形の fixture は足さないことである。3 周めに入る小さな本は狙って作れず、長さの変わる本は今のコードでは作れない。
   - 退けた案は、`buildFlow` をテストに公開し、前の周の `Built` を手で作って長さの異なる列を渡すことである。コードの経路は確かめられるが、公開する内部の型（`Built`、`ComposedUnits`）が増える。
   - もう一つは、ロードマップに「3 周で止まる fixture を探す」項目を足すことである。何をもって閉じるかが決まらない。
4. **`renderPdfAllReusing` と `parPages` の公開を記録して認めるか**：推奨は、認めることである。どちらもテストと golem-typeset のためで、利用者に見えない。

## 決めたことの記録

2026-11-09 に、tett23 が「メンテナーが決めること」のすべてを推奨のとおりとした。

1. **`Draw.hs` の spark**：記録して認める。`Draw.hs` を戻して `writePdf` の中だけで並列にする案は退けた。
2. **`Unit` と `UnitKind` の `Eq` と、`widths` の条件**：記録して認める。
3. **本の形で確かめていない境界の行**：`fixpoint` の偽の `layoutWith` のテストで覆われているとして記録し、本の形の fixture は足さない。`buildFlow` をテストに公開する案と、ロードマップに項目を足す案は退けた。
4. **`renderPdfAllReusing` と `parPages` の公開**：記録して認める。

## 参考文献

- [ADR 0251](0251-reuse-the-compositions-of-unchanged-units-between-fixpoint-rounds.md)、[ADR 0252](0252-draw-and-serialise-the-pages-of-the-pdf-in-parallel.md)、[ADR 0255](0255-record-what-implementations-decided-on-2026-11-09.md)、[golem-driver ADR 0016](../golem-driver/adr/0016-output-and-layout-diagnostic-codes.md)
- [docs/benchmarks/2026-11-09-pages-of-the-pdf-in-parallel.md](../benchmarks/2026-11-09-pages-of-the-pdf-in-parallel.md)、[docs/benchmarks/2026-11-09-reuse-compositions-between-fixpoint-rounds.md](../benchmarks/2026-11-09-reuse-compositions-between-fixpoint-rounds.md)
- 実装のプルリクエストの説明：[#770](https://github.com/tett23/golem/pull/770)、[#774](https://github.com/tett23/golem/pull/774)。監査のプルリクエスト：[#778](https://github.com/tett23/golem/pull/778)
- [`modules/golem-typeset/src/Golem/Typeset/Flow.hs` の `buildFlow`](https://github.com/tett23/golem/blob/3a93bf6d5530cad30c056c26b81efcd36a65bfce/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L2404-L2416)、[`modules/golem-typeset/src/Golem/Typeset/Draw.hs` の `writeDocumentView`](https://github.com/tett23/golem/blob/3a93bf6d5530cad30c056c26b81efcd36a65bfce/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L333-L383)、[`modules/golem-pdf/src/Golem/Pdf/Writer.hs` の `parPages`](https://github.com/tett23/golem/blob/3a93bf6d5530cad30c056c26b81efcd36a65bfce/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L480-L487)
