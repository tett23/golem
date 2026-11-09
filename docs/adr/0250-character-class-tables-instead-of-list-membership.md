# ADR 0250: 文字の種類の判定を `String` への `elem` から表の参照に変える

ステータス: 採択（未実装）

## 文脈

### 一文字の判定ごとにリテラルを復号している

[docs/benchmarks/2026-11-09-typesetting-speed-survey.md](../benchmarks/2026-11-09-typesetting-speed-survey.md)（以下「記録」）の表 4 で、`golem build --target pdf` のスタックを 1 ミリ秒ごとに集めて葉の関数を数えた。
動いている時間のうち、`GHC.CString.unpackNBytes#` が利用者向けマニュアルで 9.6%、開発者向けマニュアルで 8.1%、『蟹工船』で 4.4%、『Nightmare Abbey』で 7.6% を占める。
`Golem.Layout.CharClass.isDualCharacter` が同じ順に 6.3%、4.9%、4.1%、3.1%、`charClass` が 0.7% である。
三つを合わせると 8% から 17% になり、GC を除く関数ではもっとも大きい。

`unpackNBytes#` は `String` のリテラルを UTF-8 のバイト列から復号する関数である。
`Golem.Layout.CharClass` は文字の種類を次の形で判定する（[`CharClass.hs`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-layout/src/Golem/Layout/CharClass.hs#L38-L64)）。

```haskell
charClass c
  | c `elem` ("「『（［｛〈《【〔〘〖〝‘“｟«" :: String) = Opening
  | c `elem` ("」』）］｝〉》】〕〙〗〟’”｠»" :: String) = Closing
  ...
isDualCharacter c = c `elem` dualCharacters
```

GHC は `elem c (unpackCString# lit)` を `foldr/build` の規則で融合し、リストを作らない代わりに、呼ばれるたびにリテラルを先頭から復号しながら比べる。
`charClass` は一回の呼び出しで最大 9 個のリテラル（合わせて百字ほど）を復号する。
`isDualCharacter` は 13 字を復号する。
`isDualCharacter` は、シェイピングでフォントを決める `fontFor`（[`FontProvider.hs`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-typeset/src/Golem/Typeset/FontProvider.hs#L155-L162)）が一字ごとに、隣り合う二字の組ごとに呼ぶ。
`charClass` は組版（`Golem.Layout.Japanese`、`Golem.Layout.Aki`）と描画の両方が一字ごとに呼ぶ。
同じ形は `charClassIn`（[90 行から 91 行](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-layout/src/Golem/Layout/CharClass.hs#L90-L91)）と、`Golem.Layout.Japanese` の `isJoiner`（[661 行](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-layout/src/Golem/Layout/Japanese.hs#L661)）、`isHyphen`（[1097 行](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-layout/src/Golem/Layout/Japanese.hs#L1097)）にもある。

### 表を一度作れば復号は一度で済む

リテラルから `Data.IntSet`（containers、golem-layout の依存にある）を一度だけ作り（CAF）、判定を `IntSet.member (ord c)` にすれば、復号はプログラムの寿命で一度になる。
判定は要素の数の対数の比較で終わり、割り当てはない。
`case c of` で文字を直接に並べる形も同じ効果を持ち、GHC は二分探索かジャンプ表に落とすので最速だが、リテラルを JLReq の文字クラスの一覧として読める今の形を失う。

## 実装すること

- `Golem.Layout.CharClass` に、文字クラスごとの `IntSet` を CAF として置く。元の `String` のリテラルは、`IntSet` を作る式の中に残す。`charClass` と `charClassIn` の `elem` を `IntSet.member (ord c)` に置き換える。
- `dualCharacters` は公開された名前なので残し、`isDualCharacter` を `IntSet` の参照にする。
- `Golem.Layout.Japanese` の `isJoiner` と `isHyphen` も同じ形にする。
- `isExtending` は `generalCategory` の 3 要素のリストへの `elem` で、復号は起きないので変えない。
- 実装のプルリクエストで、記録と同じ方法でマニュアルと『蟹工船』と『Nightmare Abbey』を測り直し、`docs/benchmarks/` に記録を足す。

期待する効果は、記録の表 4 から、動いている時間の 8% から 17% の大半である。
壁時計では、マニュアルの 11.5 秒のうち 0.5 秒から 1 秒と見積もる。
GC の時間は変わらない（復号はほとんど割り当てない）。

## 実装しないこと

- 文字クラスの定義（どの文字がどのクラスか）を変えること。判定の結果は一文字も変えない。
- `charClass` の呼び出しの回数を減らすこと（組版と描画で同じ文字を何度も判定している）。呼び出しの構造の変更で、[ADR 0253](0253-memoise-run-shaping-and-shorten-the-memo-key.md) が扱う。
- `Data.Char.generalCategory` に基づく判定（`isExtending`）を変えること。
- golem-html や golem-epub の文字の判定を変えること。記録の表 1 で HTML は 1.4 秒で、問題になっていない。

## 不変条件

- **I1 `charClass` は変わらない**：すべてのコードポイント c（U+0000 から U+10FFFF）で、新しい `charClass c` は元の `charClass c` に等しい。
- **I2 `charClassIn` は変わらない**：すべてのコードポイント c と、言語の区間 `Nothing`、`Just "ja"`、`Just "en"` で、新しい `charClassIn l c` は元のものに等しい。
- **I3 `isDualCharacter`、`isJoiner`、`isHyphen` は変わらない**：すべてのコードポイントで、元の関数に等しい。
- **I4 出力は変わらない**：どの入力でも、`build/` の下のすべてのファイルのバイト列と diagnostics は変更の前と一致する。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| コードポイント | U+0000、U+10FFFF、各リテラルの最初と最後の文字、リテラルの文字の前後のコードポイント（U+300C「 と U+300D」など）、サロゲートの範囲 U+D800 から U+DFFF、非文字 U+FFFE |
| 言語の区間 | `Nothing`、`Just "ja"`、`Just "JA-JP"`、`Just "en"` |
| 文字の数 | 一字、二字（`fontFor` の組）、長い段落 |

## テスト設計

先に書いて失敗させてから実装するもの。

- I1 から I3：golem-layout のテストに、元の `elem` の定義をそのまま写した参照の実装（`String` への `elem`）を置き、U+0000 から U+10FFFF のすべてのコードポイントで新しい関数と比べる。110 万回の比較は 1 秒未満で終わる。テストの名前に I1 から I3 を入れる。実装の前は新しい関数がなく、ビルドが失敗する形になるので、先に参照の実装と新しい関数の名前だけを置き、参照と同じ `elem` の定義で一度通してから、本体を書き換える。
- 境界の表の値を、hedgehog の生成でなく列挙で確かめる。

既存のテストで確かめること。

- I4：`scripts/determinism.sh`、`scripts/visual/` の見た目の回帰テスト、golem-driver-test の fixture の PDF の比較。文字クラスが一文字でも変わればここで見つかる。

測って確かめること（実装のプルリクエストの説明に書く）。

- 記録と同じ方法でマニュアルの壁時計と CPU 時間を測り、CPU 時間が縮むことを確かめる。`sample` で `unpackNBytes#` と `isDualCharacter` が上位から消えることも確かめる。

## トレードオフ

- 参照の実装をテストに写すので、文字クラスの一覧がテストと実装の二か所になる。一覧を変えるときは両方を変える。変える頻度は低く（JLReq の文字クラスは安定している）、網羅のテストが食い違いを必ず見つける。
- `IntSet.member` は対数の時間で、`case` の定数の時間より遅い。差は数ナノ秒で、リテラルの復号（数百ナノ秒）に比べれば無視できる。
- `-O1` の最適化の挙動に依存する遅さを、コードの形で避ける。GHC の版が変わっても結果は同じである。

## メンテナーが決めること

1. **表の形**：推奨は `IntSet` の CAF である。リテラルを一覧として残せる。
   - 退けた案は `case` の直接の列挙である。最速だが、クラスごとに数十の文字を `case` の枝に並べ、一覧としての読みやすさを失う。
2. **`isExtending` も含めるか**：推奨は含めないことである。復号は起きず、記録の上位にもない。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-09、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [docs/benchmarks/2026-11-09-typesetting-speed-survey.md](../benchmarks/2026-11-09-typesetting-speed-survey.md)
- [golem-layout ADR 0002](../golem-layout/adr/0002-japanese-composition.md)（文字クラス）、[docs/adr/0187](0187-inline-language-switch.md)（両用の文字）、[docs/adr/0002](0002-determinism.md)
- [`modules/golem-layout/src/Golem/Layout/CharClass.hs`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-layout/src/Golem/Layout/CharClass.hs#L38-L64)、[`modules/golem-typeset/src/Golem/Typeset/FontProvider.hs` の `fontFor`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-typeset/src/Golem/Typeset/FontProvider.hs#L155-L162)
- GHC User's Guide 9.10, "Rewrite rules", and `GHC.CString` in ghc-prim（`unpackFoldrCString#` と `unpackNBytes#`）。https://hackage.haskell.org/package/ghc-prim/docs/GHC-CString.html
