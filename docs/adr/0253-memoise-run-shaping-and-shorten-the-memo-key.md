# ADR 0253: ランのシェイピングもメモ化し、メモのキーを短くする

ステータス: 採択

## 文脈

### 同じテキストを組版と描画で二度シェイピングしている

[docs/adr/0034](0034-fewer-unsafe-perform-io.md) は、一字の送り（`lfAdvance`）と二字のカーニング（`lfPairKern`）を、状態のない遅延評価の木（memo trie）でメモ化した。
単語やランのシェイピング（`lfWordAdvance`、`lfShape`）はメモ化していない（[`FontProvider.hs`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-typeset/src/Golem/Typeset/FontProvider.hs#L126-L150)）。

[docs/benchmarks/2026-11-09-typesetting-speed-survey.md](../benchmarks/2026-11-09-typesetting-speed-survey.md)（以下「記録」）の表 3 で、HarfBuzz を呼ぶ `shapeUnits` の回数を数えた。
利用者向けマニュアルでは、組版（二周）で 58,602 回、196,000 字をシェイピングし、描画でさらに 189,156 回、263,597 字をシェイピングする。
描画は、行に置いた箱のテキストを `lfShape` でもう一度シェイピングしてグリフを得る（[`Draw.hs`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L516)）。
組版でも、ラテン文字の単語は `ceWordAdvance` を通して `lfWordAdvance` で測り（[`Japanese.hs`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-layout/src/Golem/Layout/Japanese.hs#L1133)）、同じ単語が本の中に何度現れても毎回シェイピングする。
不動点の二周め（[ADR 0251](0251-reuse-the-compositions-of-unchanged-units-between-fixpoint-rounds.md)）も、使い回せない単位では同じ単語をまたシェイピングする。
『蟹工船』では組版の 25,721 回に対して描画が 129,596 回、『平将門』では 24,045 回に対して 86,639 回である。

記録の表 4 で、HarfBuzz そのもの（C++）は動いている時間の 1.8% から 5.2% である。
シェイピング一回の費用の多くは Haskell 側にある。
`shapeUnits` はテキストを UTF-8 に変換し、スクリプトと言語と特徴の文字列を `withCString` で三回変換し、結果の配列を三つ `peekArray` で読み、タプルの列を作る（[`Font.hs`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-font/src/Golem/Font.hs#L223-L240)）。
`shapeText` はその結果をクラスタごとに集め、縦書きでは横と縦の二回シェイピングして比べる（[`FontProvider.hs`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-typeset/src/Golem/Typeset/FontProvider.hs#L169-L200)）。

### メモのキーが長い

記録の表 4 で、メモの木を降りる `Golem.Typeset.Memo.trieAt` は、利用者向けマニュアルで動いている時間の 6.3%、開発者向けマニュアルで 7.4%、『蟹工船』で 1.9% を占める。
キーは `shapingTextKey` が作る `[Int]` で、縦横、両用、役割の名前の長さと各文字、特徴の数と各特徴の各文字、テキストの長さと各文字を並べる（[`Memo.hs`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-typeset/src/Golem/Typeset/Memo.hs#L84-L86)）。
役割の名前が `body`（4 字）で特徴がないとき、一字の送りのキーは 10 要素で、要素ごとに 8 段の 8 分木を降りるので、一回の参照で 80 段を降りる。
特徴（`palt` など）が付くと、特徴の文字の分だけ長くなる。
役割と特徴の組（`Shaping`）は、スタイルの役割の数と特徴の組み合わせで決まる少数の値である。

## 実装すること

### キーを短くする

- `Shaping` の役割と特徴を、短い符号でキーに入れる。`provide` が受け取る役割の表（`roles`）のキーの順で役割に番号を付け、特徴の列は、本の中で現れうる列（役割の特徴に `extra` を足したもの）を `provide` の時点では列挙できないので、特徴ごとに OpenType のタグ 4 字を 1 要素（4 字を 7 ビットずつ詰めた 28 ビット、`digitLimit` の 2^24 を超えるので `digitLimit` を 2^28 に上げるか、タグを 2 要素に分ける）にする。
- 一字の送りのキーは、縦横と両用の 2 ビットと役割の番号を 1 要素にまとめ、特徴の数、特徴、テキストの長さ、文字の順にする。`body` で特徴がないとき 4 要素になり、降りる段は 80 から 32 になる。
- `fromShapingTextKey` を新しい符号の逆に書き換え、`memoWith` の `decode` が `encode` の逆であることを保つ。

### ランのシェイピングもメモ化する

- `lfShape`（`shapeText`）と `lfWordAdvance` を、同じ `memoWith` で `(Shaping, Text)` のキーでメモ化する。`lfWordAdvance` は `lfShape` の結果の送りの和なので、`lfShape` のメモから計算すれば一つの表で済む。
- 描画が同じ `LoadedFonts` を使うので、組版でシェイピングしたテキストは描画でメモに当たる。不動点の二周めも当たる。
- メモは `LoadedFonts` の寿命（一回のビルド）だけ生きる。

### 測り直し

- 実装のプルリクエストで、記録の表 3 の方法で `shapeUnits` の回数（組版と描画）と `trieAt` の割合を測り直し、`docs/benchmarks/` に記録を足す。

期待する効果は二つある。
キーの短縮で `trieAt` の 2% から 7% の半分以上が消える。
ランのメモ化で、描画のシェイピングの大半（マニュアルで 189,156 回のうち、組版で既に見たテキストの分）と、組版で繰り返し現れる単語の分が消える。
シェイピングの Haskell 側の費用は記録の表 4 で切り分けられていないが、`shapeUnits` と HarfBuzz と `FontProvider` の集計を合わせて 3% から 8% で、その大半である。
合わせて、CPU 時間の 5% から 12% と見積もる。

## 実装しないこと

- メモを `IORef` の表にすること。[docs/adr/0034](0034-fewer-unsafe-perform-io.md) の純粋な形を保つ。
- 組版の結果のグリフを描画に渡して、描画でのシェイピングをなくすこと。箱のテキストから描画で再びシェイピングする構造（[docs/adr/0227](0227-draw-the-glyphs-of-a-box-in-the-order-of-its-text.md)）を変えるのは大きく、メモで同じ効果が得られる。
- `shapeUnits` の C との境界（`withCString` の三回の変換など）を速くすること。メモに当たればその回数が減る。残れば別の ADR で扱う。
- 文字クラスの判定の変更。[ADR 0250](0250-character-class-tables-instead-of-list-membership.md) が扱う。

## 不変条件

- **I1 メモ化した関数は元の関数と等しい**：すべての `Shaping` とテキスト t で、メモ化した `lfShape s t` と `lfWordAdvance s t` は、メモ化しない `shapeText s t` とその送りの和に等しい。
- **I2 キーは単射で逆を持つ**：すべての `Shaping` とテキストで、`fromShapingTextKey (shapingTextKey k) == k`。異なるキーは異なる `[Int]` になる。
- **I3 キーの要素は範囲の中**：役割がスタイルにあり、特徴が OpenType のタグ（ASCII 4 字）で、テキストの各文字がコードポイントであるとき、キーのすべての要素は 0 以上 `digitLimit` 未満である。範囲の外のキーは（今までどおり）メモせずに計算する。
- **I4 出力は変わらない**：どの入力でも、PDF のバイト列と diagnostics は変更の前と一致する。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| テキスト | 空、一字、二字、結合文字を含む、異体字セレクタを含む、U+10FFFF を含む、長い行 |
| 役割 | `body`、スタイルの最後の役割、スタイルにない役割（本文の役割に戻る） |
| 特徴 | なし、一つ、三つ、タグが ASCII でない（範囲の外、メモしない） |
| 縦横と両用 | 四つの組み合わせすべて |
| 同じキーの参照 | 一度、二度（二度めがメモに当たる）、並列の二つのスレッドから同時 |

## テスト設計

先に書いて失敗させてから実装するもの。

- I2、I3：golem-typeset（または golem-driver）の `Memo` のテストに、hedgehog で `Shaping` とテキストを生成して `fromShapingTextKey . shapingTextKey` が恒等であること、キーの要素が範囲の中にあることを確かめる性質を足す。新しい符号の `shapingTextKey` では、今のテストの期待（要素の並び）と変わるので、まず新しい符号を期待するテストを書いて失敗させる。
- I1：fixture のフォントで `provide` を作り、hedgehog で生成した `Shaping` とテキストについて、`lfShape` を二度呼んだ結果と、メモを通さない `shapeText`（テストだけに公開する）の結果が等しいことを確かめる。
- 境界の表の値を列挙で確かめる。

既存のテストで確かめること。

- I4：`scripts/determinism.sh`、見た目の回帰テスト、golem-driver-test の fixture の PDF、`ParallelSpec`（並列と逐次の一致。メモは複数のスレッドから参照される）。

測って確かめること（実装のプルリクエストの説明に書く）。

- 記録の表 3 の方法で、描画の `shapeUnits` の回数がマニュアルで 189,156 回から大きく減ること（組版で見ていないテキストの分だけ残る）を確かめる。
- `sample` で `trieAt` の割合が半分以下になることを確かめる。

## トレードオフ

- メモはシェイピングしたテキストの数だけ `Shaped` の列を保持する。本の中の相異なる（`Shaping`、テキスト）の組の数で、単語の種類の数程度である。マニュアルの最大常駐 0.85GB に対して、数十 MB の増加と見積もる。実装のプルリクエストで `+RTS -s` の最大常駐を測る。
- キーの符号を変えると、`digitLimit` の上限を上げるか要素を増やすかの選択が要る。上限を 2^28 にすると、木の深さが 8 段から 10 段に増え（3 ビットずつ）、すべての参照が 2 段ずつ深くなる。タグを 2 要素（14 ビットずつ）に分ければ深さは変わらない。「メンテナーが決めること」の 1 に残す。
- 二つのスレッドが同じキーを同時に参照すると、純粋なサンクを二度評価することがある（[docs/adr/0034](0034-fewer-unsafe-perform-io.md) の既知の性質）。結果は同じである。

## メンテナーが決めること

1. **特徴の符号**：推奨は、OpenType のタグ 4 字を 14 ビットずつの 2 要素に分けることである。`digitLimit` と木の深さを変えずに済む。
   - 退けた案は `digitLimit` を 2^28 にすることである。すべての参照が深くなる。
2. **`lfWordAdvance` を別にメモするか**：推奨は、`lfShape` のメモから送りの和を計算し、表を一つにすることである。`lfWordAdvance` の結果（`Rational`）だけを別にメモすると表が二つになり、メモリが増える。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-09、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [docs/adr/0034](0034-fewer-unsafe-perform-io.md)、[docs/adr/0020](0020-indesign-character-features.md)、[docs/adr/0227](0227-draw-the-glyphs-of-a-box-in-the-order-of-its-text.md)、[golem-font ADR 0001](../golem-font/adr/0001-shaping-and-metrics.md)、[docs/adr/0002](0002-determinism.md)
- [docs/benchmarks/2026-11-09-typesetting-speed-survey.md](../benchmarks/2026-11-09-typesetting-speed-survey.md)
- [`modules/golem-typeset/src/Golem/Typeset/Memo.hs`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-typeset/src/Golem/Typeset/Memo.hs)、[`modules/golem-typeset/src/Golem/Typeset/FontProvider.hs` の `provide`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-typeset/src/Golem/Typeset/FontProvider.hs#L126-L200)、[`modules/golem-font/src/Golem/Font.hs` の `shapeUnits`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-font/src/Golem/Font.hs#L223-L240)、[`modules/golem-typeset/src/Golem/Typeset/Draw.hs` の `runAtSqueezed`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L489-L520)
- Conal Elliott, "Elegant memoization with functional memo tries", 2008. http://conal.net/blog/posts/elegant-memoization-with-functional-memo-tries
