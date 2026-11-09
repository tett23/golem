# ADR 0254: PDF の内容ストリームのグリフの符号を `Text.Printf` を使わずに書く

ステータス: 採択

## 文脈

### グリフごとに `printf` を呼んでいる

`Golem.Pdf.Writer` の `markBuilder` は、グリフを `Tj` で描くたびに、グリフの番号を 4 桁の 16 進にする（[`Writer.hs`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L413-L428)）。

```haskell
hex4 g = B.string7 (printf "%04X" g)
```

`Text.Printf.printf` は書式の文字列を呼ぶたびに解釈し、`String` を作り、`B.string7` がそれを `Builder` に写す。
`ToUnicode` の CMap（[同 997 行](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L997)）と xref の表（[同 481 行](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L481)）も同じ形である。

[docs/benchmarks/2026-11-09-typesetting-speed-survey.md](../benchmarks/2026-11-09-typesetting-speed-survey.md)（以下「記録」）の表 3 で、利用者向けマニュアルの `writePdf` は 2.55 秒かかり、全体の 20% である。
描画で 263,597 字をシェイピングしているので、グリフの `Tj` はその程度の回数書かれ、`printf` も同じ回数呼ばれる。
記録の表 4 のサンプルでは、`printf` の内部（`GHC.Internal.Base.++`、`Text.Printf` のローカルな関数）は分類の「その他」と「ghc-internal」に散り、`writePdf` の中の内訳は切り分けられていない。
したがって、この ADR の効果は見積もりで、実装のプルリクエストで `writePdf` の時間を前後で測ることを求める。

### `Builder` で直接に書ける

bytestring の `Builder` は 16 進の固定幅の関数（`word16HexFixed`）を持つが、小文字で書く。
`%04X` は大文字なので、出力のバイト列を変えないためには、大文字の 16 進を書く小さな関数を置く。
4 桁なので、4 回のシフトとマスクと表の参照で済み、`String` も書式の解釈も要らない。

## 実装すること

- `Golem.Pdf.Number`（または `Writer`）に `hex4 :: Int -> B.Builder` を置き、大文字の 16 進 4 桁を `B.word8` 4 つで書く。`markBuilder` の `hex4` と `ToUnicode` の `printf "%04X"` をこれに置き換える。0 未満と 0xFFFF を超える値は、今の `printf "%04X"` と同じ文字列（桁があふれた形）を出すか、呼び出し側でそのような値が来ないことを確かめる（「メンテナーが決めること」の 1）。
- xref の `printf "%010d 00000 n \n"` を、`B.intDec` を 0 で左から埋める形にする。オブジェクトの数だけなので効果は小さいが、同じ形をそろえる。
- `pdfDate` と URL のパーセント符号化の `printf`（[同 228 行](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L228)、[同 311 行](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L311)）は一回ずつか文字ごとで、頻度が低いので変えない。
- 実装のプルリクエストで、記録の表 3 の方法で `writePdf` の時間を前後で測り、`docs/benchmarks/` に記録を足す。

期待する効果は、`Text.Printf` の一回あたり数マイクロ秒（書式の解釈と `String` の構築）がグリフの数だけ消えることである。
マニュアルで 26 万回なら 0.3 秒から 1 秒で、`writePdf` の 2.55 秒の 1 割から 4 割と見積もる。
見積もりの幅が広いのは、`writePdf` の内訳を測れていないためである。

## 実装しないこと

- 数（座標と比）の書き方（`Golem.Pdf.Number`）を変えること。整数の算術で丸めて `Builder` で書いており、`printf` を使っていない。
- Flate のレベルや内容ストリームの形を変えること。出力のバイト列が変わる。
- `Text.Printf` を golem-pdf からすべて消すこと。頻度の低い箇所は残す。

## 不変条件

- **I1 符号は同じ**：0 以上 0xFFFF 以下のすべての整数 g で、新しい `hex4 g` の出力は `printf "%04X" g` の出力と等しい。
- **I2 出力は変わらない**：どの入力でも、PDF のバイト列は変更の前と一致する。
- **I3 xref は同じ**：0 以上 9,999,999,999 以下のすべてのオフセットで、新しい書き方は `printf "%010d"` と等しい。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| グリフの番号 | 0、1、0x000F、0x0010、0x0FFF、0x1000、0xFFFF、65536（範囲の外、「メンテナーが決めること」の 1） |
| xref のオフセット | 0、9、10、9,999,999,999 |
| 内容ストリーム | グリフなし、一つ、数十万（マニュアル） |

## テスト設計

先に書いて失敗させてから実装するもの。

- I1：golem-pdf のテストに、0 から 0xFFFF のすべての g で `hex4 g` と `printf "%04X" g` を比べる網羅のテストを足す。実装の前は新しい `hex4` がないので失敗する。
- I3：xref の書き方を 0、9、10、10^10 − 1 と hedgehog の生成で `printf "%010d"` と比べる。

既存のテストで確かめること。

- I2：golem-pdf の golden のテスト、`scripts/determinism.sh`、見た目の回帰テスト、golem-driver-test の fixture の PDF。

測って確かめること（実装のプルリクエストの説明に書く）。

- 記録の表 3 の方法で、マニュアルの `writePdf` の時間を前後で測る。縮まなければ、この ADR の効果はなかったとして記録し、`writePdf` の内訳を測る別の調査に進む。

## トレードオフ

- `Text.Printf` の書式は読めば意味がわかるが、手で書いた 16 進の関数は一行のコメントが要る。
- 効果は見積もりで、測って初めてわかる。変更は小さく、I1 と I2 で安全なので、測るための費用は低い。
- `writePdf` の 2.55 秒の残り（`Builder` の構築、Flate、`ByteString` の連結）はこの ADR では縮まない。[ADR 0252](0252-draw-and-serialise-the-pages-of-the-pdf-in-parallel.md) がページごとに並列にする。

## メンテナーが決めること

1. **範囲の外の値**：推奨は、`hex4` を `Word16` を受け取る形にし、呼び出し側で `fromIntegral` することである。グリフの番号は CID で 0xFFFF 以下であり、サブセット化の後の番号も同じ範囲にある。`printf "%04X"` の桁あふれの形を真似る必要はない。
   - 退けた案は、`Int` のまま受け取り、0xFFFF を超えたら `printf` と同じ桁数の多い形を出すことである。起きない値のために分岐を持つ。
2. **この ADR の順番**：推奨は、[ADR 0252](0252-draw-and-serialise-the-pages-of-the-pdf-in-parallel.md) より前に実装して測ることである。逐次のまま測るほうが差が見えやすい。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-09、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [golem-pdf ADR 0001](../golem-pdf/adr/0001-deterministic-pdf-writer.md)、[docs/adr/0002](0002-determinism.md)、[ADR 0252](0252-draw-and-serialise-the-pages-of-the-pdf-in-parallel.md)
- [docs/benchmarks/2026-11-09-typesetting-speed-survey.md](../benchmarks/2026-11-09-typesetting-speed-survey.md)
- [`modules/golem-pdf/src/Golem/Pdf/Writer.hs` の `markBuilder`](https://github.com/tett23/golem/blob/08d093321f3384652fb895715d76dfb2dd95c606/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L357-L432)
- bytestring, `Data.ByteString.Builder`（`word16HexFixed`、`intDec`）。https://hackage.haskell.org/package/bytestring/docs/Data-ByteString-Builder.html
