# ADR 0251: ページ番号の不動点の二周め以降で、変わらない単位の組版を使い回す

ステータス: 採択

## 文脈

### 参照のある本は、すべての段落を二度組む

PDF のページ番号への参照は、仮のページ番号で組み、配置し、実際のページ番号が仮のものと一致するまで繰り返して解決する（[golem-layout ADR 0003](../golem-layout/adr/0003-pagination-and-s2.md)、[golem-driver ADR 0016](../golem-driver/adr/0016-output-and-layout-diagnostic-codes.md) の G07021）。
その一周は `Golem.Typeset.Flow` の `layoutFigures` の `round'` で、`buildFlow` がすべての単位（段落、見出し、表、図版など）を組み、`paginateWithin` が配置する（[`Flow.hs`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L485-L489)）。
`fixpoint` は、ラベルのページと索引の印のページが前の周と一致したときに止まる（[同](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L1058-L1075)）。

一周めは仮のページを持たない。
ラベルの参照は 1 ページとして、索引の印は `markPage` が 1 を返して組む（[同](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L1741)）。
したがって、ラベルか索引の印が一つでもあれば、一周めの結果は仮のもの（空）と一致せず、二周めが必ず走る。
二周めは `buildFlow` をもう一度呼び、ページ番号に関係のない段落も含めて、すべての単位を組み直す。

[docs/benchmarks/2026-11-09-typesetting-speed-survey.md](../benchmarks/2026-11-09-typesetting-speed-survey.md)（以下「記録」）の表 3 で、利用者向けマニュアル（単位 3,257、ラベル 82、索引の印 204）は二周で止まり、二周めの組版は壁時計で 1.84 秒、CPU 時間で 7.07 秒だった。
一周めは 2.66 秒と 8.19 秒で、二周めは一周めとほぼ同じ仕事をしている。
二周めは全体の 12.55 秒の 15% である。
開発者向けマニュアルは二周めが 1.78 秒で全体の 18%、`complex-horizontal` は 0.07 秒で 9% である。
参照のない十冊は一周で止まり、この費用を払っていない。

### 変わらない単位の組版は、純粋な関数の値である

`composeUnit` は `FlowEnv` と単位 `Unit` から `Composed` を作る純粋な関数である（[同](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L1803-L1812)）。
`FlowEnv` のうち周ごとに変わるのは `feAssumed`（仮のページ）だけで、それを読むのは二か所である。

- `composeEnv` の `cePageOf`（[同](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L1109)）。`[ref ... page]`（`Ref _ RefPage _`）の数字を決める。
- `flowUnits` の `markPage`（[同](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L1741)）。索引と出典の一覧の行の単位の中身（ページの列）を決める。

つまり、二周めで値が変わりうる単位は、インラインに `Ref _ RefPage _` を持つ単位と、`unitsOf` が仮のページから作る索引や一覧の単位だけである。
後者は `Unit` の値そのもの（`uInlines`）が変わる。
前者は `Unit` の値は同じで、組んだ結果だけが変わる。
`Unit` は `Eq` を持つ（[同](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L1201-L1223)）。
したがって、前の周の単位と同じ値で、`Ref _ RefPage _` を含まない単位の `Composed` は、組み直しても同じ値になる。
使い回しは、同じ値を計算し直さないだけで、結果を変えない。

## 実装すること

- `buildFlow` に、前の周の単位の列と組んだ結果（`singles`、`besides`、`tables` の `Map`）を渡せるようにする。一周めは `Nothing` を渡す。
- 二周め以降、単位の列の長さが前の周と同じとき、位置 i の単位 u について、`u == prev !! i`（`zip` で並べて比べる）かつ `refersToPage u` が偽ならば、前の周の `Composed` を使う。それ以外は今までどおり組む。
  - `refersToPage u` は、`uInlines u`（表の単位では見出しとセルのインラインも）を走査して `Ref _ RefPage _` があれば真とする。`Resolved` の中も走査する。
  - 図版に沿わせる段落（`besides`）は、図版の単位とそれに続く単位のすべてが前の周と同じときだけ使い回す。
  - 表（`tables`）は、単位が同じときに使い回す。
- `fixpoint` に、前の周の結果を次の周に渡す引数を足す。`layoutWith` の型を `Maybe prev -> Assumed -> IO (Either [Diagnostic] (b, [PageOut]))` の形にする。
- 保持するのは直前の一周だけである。
- 実装のプルリクエストで、記録と同じ方法でマニュアル、開発者向けマニュアル、`complex-horizontal` を測り直し、`docs/benchmarks/` に記録を足す。

期待する効果は、参照のある本で、二周め以降の組版の時間のほぼすべてである。
記録の表 3 から、利用者向けマニュアルで 12.55 秒のうち約 1.8 秒（15%）、開発者向けマニュアルで約 1.7 秒（18%）、`complex-horizontal` で約 0.07 秒（9%）である。
参照のない本では変わらない。

## 実装しないこと

- 一周めで仮のページを推定して周の数を減らすこと。周の数は変えず、各周の仕事を減らす。
- 単位の中の段落の一部（行分割の前のシェイピングなど）を使い回すこと。[ADR 0253](0253-memoise-run-shaping-and-shorten-the-memo-key.md) が扱う。
- 配置（`paginateWithin`）を使い回すこと。配置は逐次で全体の 2% 未満である（記録の表 3）。
- `Composed` を周をまたいでディスクに保存すること（インクリメンタルなビルド）。[docs/roadmap.md](../roadmap.md) の「ビルドと LSP の速度」の範囲で、別の ADR で扱う。
- G07021（収束しない参照）の判定を変えること。

## 不変条件

- **I1 結果は組み直しと同じ**：どの入力でも、使い回しを有効にした `layoutPdf` の結果（`PdfLayout`）は、使い回しを無効にしたものと等しい。したがって PDF のバイト列と diagnostics も一致する。
- **I2 ページを参照する単位は使い回さない**：`Ref _ RefPage _` を含む単位は、周ごとに必ず組み直される。
- **I3 変わった単位は使い回さない**：前の周と `Unit` の値が異なる単位（索引の行など）は、必ず組み直される。
- **I4 一周めは今までどおり**：前の周がないとき、すべての単位を組む。
- **I5 保持は一周分**：周 k で保持するのは周 k − 1 の結果だけで、周 k − 2 以前の結果は参照されない。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 周の数 | 1（参照なし）、2、3 以上（ラベルのページが二周めで動くもの）、`maxIterations` に達して G07021 になるもの |
| ラベルと索引の印 | なし、ラベル 1 つだけ、索引の印 1 つだけ、両方 |
| `Ref _ RefPage _` を含む単位 | なし、本文の段落、脚注の中、表のセルの中、図版のキャプションの中 |
| 単位の列 | 長さが前の周と同じ、異なる（使い回しをすべてやめる） |
| 図版に沿わせる段落 | 図版だけが変わる、続く段落だけが変わる、どちらも変わらない |

## テスト設計

先に書いて失敗させてから実装するもの。

- I1：golem-driver-test の `ParallelSpec` と同じ形で、ラベルと索引の印と `[ref ... page]` を持つ小さな本を、使い回しを有効にした場合と無効にした場合で組み、PDF のバイト列が一致することを確かめる。使い回しの有無は、テストだけが使う `layoutPdfWith :: Bool -> ...` で切り替える。実装の前は `layoutPdfWith` がないので失敗する。
- I2、I3、I4：シェイピングの呼び出しを数える `FontProvider`（`fakeProvider` に数える機能を足す）で、本文の段落 100 と索引の印 1 と `[ref ... page]` を持つ段落 1 の本を組む。二周めに数えるシェイピングの回数が、索引の行と `[ref ... page]` の段落の分だけで、本文の段落 100 の分を含まないことを確かめる。一周めの回数は今までと同じであることを確かめる。
- I5：`fixpoint` に渡す `layoutWith` が受け取る前の周の値が、直前の周の値であることを、周ごとに番号を返す偽の `layoutWith` で確かめる。
- 境界の表の各行を golem-driver-test の fixture として置く。

既存のテストで確かめること。

- I1：`scripts/determinism.sh`、見た目の回帰テスト、golem-driver-test の fixture の PDF（`complex-horizontal` は二周で止まる）。
- G07021 のテスト（golem-driver-test）が今までどおり通ること。

測って確かめること（実装のプルリクエストの説明に書く）。

- 記録の表 3 の方法で、マニュアルの二周めの組版の時間が 0.3 秒未満になることを確かめる。

## トレードオフ

- 前の周の `Composed` を次の周の終わりまで保持するので、最大常駐が二周のあいだ増える。マニュアルの最大常駐は 0.85GB で（記録の表 1）、`Composed` はその一部である。増加は一周分の `Composed` を超えない。
- 単位の比較（`==`）は単位の中身を走査する。インラインの木の比較は、組版（シェイピングと行分割）より桁違いに軽い。
- `Ref _ RefPage _` を持つ単位は毎周組み直す。ラベルのページが変わらなかったときも組み直すので、使い回しの機会を一部捨てる。ラベルごとの依存を追えばさらに減らせるが、単純さを優先する。
- 単位の列の長さが変わったときは使い回しをすべてやめる。索引の行の数が周で変わる本がそれに当たるが、まれである。

## メンテナーが決めること

1. **使い回しのキー**：推奨は、位置 i の単位の `==` と `refersToPage` の二つで決めることである。単純で、I1 を純粋性から直接に導ける。
   - 退けた案は、単位ごとに参照するラベルの集合を取り、そのラベルのページが変わったときだけ組み直すことである。使い回しの機会は増えるが、依存の追跡を誤ると出力が変わる。
2. **切り替えの置き場**：推奨は、`PdfInput` には足さず、テストだけが使う `layoutPdfWith` を `Golem.Typeset` から公開することである。利用者に切り替える理由はない。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-09、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [golem-layout ADR 0003](../golem-layout/adr/0003-pagination-and-s2.md)、[golem-driver ADR 0002](../golem-driver/adr/0002-pdf-pipeline.md)、[golem-driver ADR 0016](../golem-driver/adr/0016-output-and-layout-diagnostic-codes.md)、[docs/adr/0118](0118-ref-page-numerals-in-vertical-text.md)、[docs/adr/0215](0215-ref-number-and-ref-title-as-reference.md)、[docs/adr/0002](0002-determinism.md)
- [docs/benchmarks/2026-11-09-typesetting-speed-survey.md](../benchmarks/2026-11-09-typesetting-speed-survey.md)
- [`modules/golem-typeset/src/Golem/Typeset/Flow.hs` の `round'`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L485-L489)、[同 `fixpoint`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L1058-L1075)、[同 `buildFlow`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L2384-L2440)、[同 `composeUnit`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L1803-L1812)
