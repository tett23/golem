# ADR 0252: PDF のページの描画と内容ストリームの直列化を、ページごとに並列にする

ステータス: 採択→`Draw.hs` の spark は [ADR 0256](0256-record-what-the-implementations-of-adr-0251-and-0252-decided.md)

## 文脈

### 組版の後の四割は逐次である

[docs/benchmarks/2026-11-09-typesetting-speed-survey.md](../benchmarks/2026-11-09-typesetting-speed-survey.md)（以下「記録」）の表 3 で、`golem build --target pdf` の段階ごとの時間を測った。
利用者向けマニュアルは全体 12.55 秒のうち、描画（`writeDocumentView` の全ページの描画）が 2.33 秒、書き出し（`writePdf`）が 2.55 秒で、二つで 39% である。
『蟹工船』は 2.50 秒のうち 0.80 秒と 0.76 秒で 62%、『Nightmare Abbey』は 2.92 秒のうち 0.86 秒と 1.11 秒で 67% である。
この二つの段階は、capability が 1 でも 10 でも同じ時間である（マニュアルで 2.07 秒と 2.45 秒、『蟹工船』で 0.74 秒と 0.76 秒）。
段落の組版だけが並列で（[golem-driver ADR 0002](../golem-driver/adr/0002-pdf-pipeline.md)）、その後は一つのスレッドで進む。
[golem-driver ADR 0002](../golem-driver/adr/0002-pdf-pipeline.md) の「実装しないこと」は配置の並列化を挙げたが、描画と書き出しには触れていない。

### ページごとの仕事は独立である

描画は `Golem.Typeset.Draw` の `drawn = zipWith (drawPage env) (pagesOf (plPages layout)) masters` で、ページごとの純粋な関数の値の列である（[`Draw.hs`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L345)）。
ページの描画は配置の結果（`PdfLayout`）だけに依存し、ほかのページの描画には依存しない。
書き出しは `Golem.Pdf.Writer` の `documentObjects` と `serializePdf` で、ページごとに内容ストリームを作り（`contentStreamWith`）、Flate で圧縮し（`flate`、zlib のレベル 9）、オブジェクトとして直列化する（[`Writer.hs`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L465-L488)）。
ページの内容ストリームは、フォントと画像とフォームの番号（全ページの印から先に決める `fontNames` など）を除けば、そのページの印だけから決まる。
フォントの番号は全ページの印を一度走査して決めるが、走査は軽い。
ページの順は列の順で、並列に計算しても列の順で並べれば結果は同じである。

描画の結果は遅延評価のサンクで、`writePdf` が内容ストリームを作るときに初めて計算される。
したがって、並列にする単位として自然なのは「ページの印からそのページの内容ストリームのバイト列（圧縮済み）を作る」仕事で、これは描画と直列化と圧縮を一つにまとめて強制する。

### 純粋なまま並列にする

`writePdf :: Document -> ByteString` は純粋である（[golem-pdf ADR 0001](../golem-pdf/adr/0001-deterministic-pdf-writer.md)）。
golem-pdf は wasm のリアクタにもビルドされ（[docs/adr/0199](0199-pdf-typesetting-as-wasm-reactor.md)）、そこでは RTS はスレッドを持たない。
純粋性を保って並列にするには、base の `GHC.Conc` の `par` と `pseq`（spark）を使う。
spark は値の計算を別の capability に委ねるだけで、結果は逐次に計算したものと同じである。
スレッドのない RTS では `par` は何もしないので、wasm でも同じコードが動く。
`parallel` パッケージの `parList` は小さな関数で、依存を足さずに同じものを書ける（CLAUDE.md の方針）。

## 実装すること

- `Golem.Pdf.Writer` に、ページごとの内容ストリームのバイト列（`flate` 済み）を spark で並列に計算する `parPages :: [a] -> [a]`（`parList rseq` と同じ、`GHC.Conc.par` と `pseq` で書く）を置き、`documentObjects` のページのオブジェクトを作る箇所で、全ページの内容ストリームの列に適用する。各要素は弱頭部正規形まで評価すればよい（`ByteString` は正格なので、それで全体が評価される）。
- 内容ストリームの計算は、ページの印（`pageMarks`）の評価を含む。`Golem.Typeset.Draw` の `drawPage` の結果は `writeDocumentView` が `P.framePageWith ... (pdContent pd)` で `Page` に入れるので（[`Draw.hs`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L357-L360)）、内容ストリームを並列に計算すれば描画も並列になる。`Draw.hs` は変えない。
- `used`（各フォントで使ったグリフ、[`Draw.hs`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L367)）は `writePdf` より前に `pdUses` を全ページ走査して強制するので、描画の一部（グリフの決定）はそこで逐次に進む。`renderPdfAllWith` で、`used` を取る前に `pdfPages` の内容ストリームを spark で先に投げる形にするかどうかは、実装のときに測って決める（「メンテナーが決めること」の 2）。
- golem-pdf の `writePdf` の結果が、spark の有無で一致するテストを足す。
- 実装のプルリクエストで、記録と同じ方法でマニュアル、『蟹工船』、『Nightmare Abbey』を `-N1` と既定の capability で測り直し、`docs/benchmarks/` に記録を足す。

期待する効果は、描画と書き出しの合計（マニュアルで 4.9 秒、『蟹工船』で 1.56 秒、『Nightmare Abbey』で 1.97 秒）が、段落の組版と同じ 2.2 倍から 3 倍の速度向上を得ることである（記録の表 3 の組版の CPU 時間と壁時計の比）。
マニュアルで 12.55 秒のうち約 2.5 秒から 3 秒（20% から 25%）、『蟹工船』で約 0.9 秒（35%）、『Nightmare Abbey』で約 1.2 秒（40%）と見積もる。
xref と trailer の直列化、フォントの番号付け、`instanceId` の SHA-256 は逐次のまま残る。

## 実装しないこと

- 配置（`paginateWithin`）の並列化。前のページの結果に依存する（[golem-driver ADR 0002](../golem-driver/adr/0002-pdf-pipeline.md)）。
- `writePdf` を `IO` にして `mapConcurrently` を使うこと。golem-pdf の純粋な API と wasm のビルドを保つ。
- `parallel` パッケージを依存に足すこと。必要な関数は数行である。
- Flate のレベルを変えること。出力のバイト列が変わる。並列にしてもなお書き出しが長ければ、別の ADR で測って決める。
- `Text.Printf` の置き換え。[ADR 0254](0254-write-glyph-codes-without-printf.md) が扱う。
- HTML と EPUB の出力の並列化。記録の表 1 で 1.4 秒以下である。

## 不変条件

- **I1 出力は変わらない**：どの入力でも、spark を使う `writePdf` のバイト列は、spark を使わない（`parPages = id`）ものと一致する。したがって capability の数（1、2、すべて）によらない。
- **I2 ページの順**：PDF のページのオブジェクトの順と内容は、`docPages` の順である。
- **I3 依存は増えない**：golem-pdf と golem-typeset の `build-depends` は変わらない。`GHC.Conc` は base にある。
- **I4 スレッドのない RTS でも動く**：wasm のビルド（`golem-wasm`）は変わらずビルドでき、同じバイト列を出す。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| ページの数 | 0（空の本は G07xxx で止まるので、`Document` のテストでは 1）、1、2、capability の数と同じ、capability の数より多い（380） |
| capability の数 | 1、2、すべて |
| ページの内容 | 空のページ（白ページ）、グリフだけ、画像とフォームを含む、注釈（リンク）を含む |
| 内容ストリームの大きさ | 数バイト、圧縮で小さくなるもの、ほぼ縮まないもの（画像） |

## テスト設計

先に書いて失敗させてから実装するもの。

- I1、I2：golem-pdf のテストに、ページ 1、2、8、64 の `Document` を作り、`writePdf` と、テストだけが使う `writePdfWith :: ([ByteString] -> [ByteString]) -> Document -> ByteString` に `id` を渡したものの一致を確かめるテストを足す。実装の前は `writePdfWith` がないので失敗する。
- I1：golem-driver-test の `ParallelSpec` の fixture の本（`tempest`、`kanikosen`）のテスト「parallel builds on every capability give the bytes of a sequential build」が、描画と書き出しも含めて並列と逐次を比べている。これは `optParallel` の切り替えで段落の組版だけを変える。spark は RTS の capability の数で決まるので、このテストではなく `scripts/env-determinism/check.sh` の `caps-one`、`caps-two`（[docs/adr/0050](0050-run-golem-on-every-processor.md)）が I1 を確かめる。両方を変えずに走らせる。
- I3：`scripts/ci/test-only-deps.sh` と `cabal build` で、`build-depends` が変わっていないことを確かめる（変更がなければ通る）。
- I4：CI の `wasm` ジョブ（[docs/adr/0199](0199-pdf-typesetting-as-wasm-reactor.md)）が通ること。

測って確かめること（実装のプルリクエストの説明に書く）。

- 記録の表 3 の方法で、描画と書き出しの合計が `-N1` に対して 2 倍以上速くなることを確かめる。`+RTS -s` の `SPARKS` の行で、spark が converted され、fizzled や GC'd が大半でないことを確かめる。

## トレードオフ

- spark は capability が空いているときだけ使われるので、速度向上は計算機と負荷で変わる。結果は変わらない。
- ページの内容ストリームを並列に作ると、全ページのバイト列が同時にメモリに載る。今も `bodies` は全オブジェクトの `ByteString` の列として作られるので（[`Writer.hs`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L473)）、最大常駐は大きくは変わらない。描画のサンクが早く評価される分、ピークが前に移る。
- `par` の spark は GC で捨てられることがある（fizzled）。`parList` の形で全要素を先に投げてから `pseq` で順に待てば、大半は converted される。
- 並列 GC との相互作用で CPU 時間は増える。[ADR 0249](0249-link-golem-with-a-64-mb-allocation-area.md) の nursery の拡大と組み合わせると、GC の同期は減る。

## メンテナーが決めること

1. **並列にする層**：推奨は golem-pdf の `writePdf` の中で、ページの内容ストリームを spark で計算することである。純粋で、wasm のビルドも変わらない。
   - 退けた案は、`Golem.Typeset.Draw` の `renderPdfAllWith`（`IO`）で `mapConcurrently` を使い、ページの描画を `evaluate` で強制することである。描画の結果を深く強制するには `NFData` か `show` による強制が要り、`show` による強制は今の `forceComposed` と同じく大きな文字列を作る。
2. **`used` の前に spark を投げるか**：推奨は、まず書き出しの中だけで並列にして測り、描画が `used` の走査で逐次に進んでしまう分が大きければ、`renderPdfAllWith` で `pdfPages` を先に spark で投げることである。
3. **Flate のレベル**：推奨は変えないことである。出力のバイト列が変わり、見た目の回帰テストの参照と `docs/benchmarks/` の過去の記録との比較が難しくなる。並列にした後も書き出しが長ければ、レベルごとの時間と大きさを測って別の ADR で決める。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-09、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [golem-driver ADR 0002](../golem-driver/adr/0002-pdf-pipeline.md)、[golem-pdf ADR 0001](../golem-pdf/adr/0001-deterministic-pdf-writer.md)、[docs/adr/0002](0002-determinism.md)、[docs/adr/0050](0050-run-golem-on-every-processor.md)、[docs/adr/0199](0199-pdf-typesetting-as-wasm-reactor.md)、[docs/adr/0249](0249-link-golem-with-a-64-mb-allocation-area.md)
- [docs/benchmarks/2026-11-09-typesetting-speed-survey.md](../benchmarks/2026-11-09-typesetting-speed-survey.md)
- [`modules/golem-typeset/src/Golem/Typeset/Draw.hs` の `writeDocumentView`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L321-L370)、[`modules/golem-pdf/src/Golem/Pdf/Writer.hs` の `serializePdf`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L465-L488)
- GHC `GHC.Conc`（`par`、`pseq`）。https://hackage.haskell.org/package/base/docs/GHC-Conc.html
- Simon Marlow, "Parallel and Concurrent Programming in Haskell", O'Reilly, 2013, chapter 2（Evaluation Strategies、`parList`）。
