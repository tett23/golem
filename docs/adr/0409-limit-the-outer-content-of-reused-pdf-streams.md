# ADR 0409: 使い回す PDF の内容の外側にも 256 MiB の上限をかける

Status: accepted-pending

## 文脈

PDF の図版は、ページの `Contents` の配列のストリームを展開し、改行でつないで一つの内容にする。
つないだ内容が 256 MiB を超えれば、G08015 で拒む（[ADR 0051](0051-reuse-repeated-pdf-content-streams.md)、[ADR 0359](0359-imported-content-separators.md)）。

[ADR 0051](0051-reuse-repeated-pdf-content-streams.md) は、`Contents` の中で二回以上名指したストリームを、内側の Form XObject として一度だけ書くと決めた。
外側の内容は、そのストリームを `/GolemC<番号> Do` の行で呼ぶ。
同じ ADR は、この経路について「この経路には、展開の合計の上限のほかの上限を設けない」と書いた。
外側の内容のうち名指しの回数に比例して大きくなるのは、`Do` の数バイトだけだからである。

この経路では、外側の内容が 256 MiB を超えても拒まない。
Codex の PR #975（閉じた）は、上限を超える外側の内容を作れる入力を示した。
空のストリームを二回名指しし、別のストリームで 256 MiB を展開した入力である。
超える量は `Do` の行の数に比例し、行の数は入力の大きさだけ増やせる。
そのため、上限に定数の余白を足しても、超える入力を作れる。

tett23 は 2026-11-23 に、この経路にも上限をかけることを決めた。

## 調査した事項

いずれも `b540aa68a` で確かめた。

- 図版のページを読む [`importM`](https://github.com/tett23/golem/blob/b540aa68a3bbb45ed4a8754f79852984152f6cf6/modules/golem-pdf/src/Golem/Pdf/Import.hs#L1079-L1080) は、[1117 行から 1123 行](https://github.com/tett23/golem/blob/b540aa68a3bbb45ed4a8754f79852984152f6cf6/modules/golem-pdf/src/Golem/Pdf/Import.hs#L1117-L1123) で、`reusedContent` が `Just` を返せばその内容をそのまま使う。
  上限の検査（`total > maxStreamBytes` のとき `ContentTooLarge`）は、`Nothing` の枝にしかない。
- [`reusedContent`](https://github.com/tett23/golem/blob/b540aa68a3bbb45ed4a8754f79852984152f6cf6/modules/golem-pdf/src/Golem/Pdf/Import.hs#L1226-L1244) は、部品と `Do` の行を改行でつなぎ、長さを見ない。
- 上限の定数は [`maxStreamBytes`](https://github.com/tett23/golem/blob/b540aa68a3bbb45ed4a8754f79852984152f6cf6/modules/golem-pdf/src/Golem/Pdf/Import.hs#L163)（256 MiB）である。
- [ADR 0051](0051-reuse-repeated-pdf-content-streams.md) の 87 行は、上の「ほかの上限を設けない」を書く。
  96 行は、「上限は 256 MiB とする」として、一つの Form XObject の内容として書く大きさの上限をそろえると書く。
  87 行の経路だけが、このそろえた上限から外れている。
- PR #975 の差分（`gh pr diff 975`）は、外側の内容と使い回さない内容の両方を、一つの関数 `joinContent` でつなぎ、長さを数えて上限を検査する。
  テストは、使い回す経路で `Left (ContentTooLarge (256 MiB + 2 × "/GolemC4 Do" の長さ + 2))` を確かめる。
  PR 本文は「24 バイト超える」と書くが、手元では再現していない（未確認、推測の扱い）。

## 実装すること

- 外側の内容も、使い回さない内容と同じく、つないだ後の長さが 256 MiB を超えれば G08015 で拒む。
  長さには、部品、`Do` の行、あいだの改行のすべてを数える。
- 長さを数えてつなぐ関数 `joinContent :: [ByteString] -> R ByteString` を一つ作り、二つの経路のどちらもこの関数でつなぐ。
  `joinContent` は、つなぐ前に部品の長さとあいだの改行の数を足して長さを計算し、256 MiB を超えれば内容を作らずに G08015 を返す（[ADR 0051](0051-reuse-repeated-pdf-content-streams.md) の「つなぐ前に計算し、超える内容をメモリに作らない」と同じ）。
- 数える長さは、各経路がつなぐ部品の長さとする。
  使い回さない経路は、今と同じく書き換える前の部品をつなぐ。
  使い回す経路は、今と同じく書き換えた後の部品と `Do` の行をつなぐ。
  `rewriteContent` が書き換えで内容を長くする分（DeviceRGB の色の演算子の置き換えなど）は、使い回さない経路では今と同じく数えない。
- [ADR 0051](0051-reuse-repeated-pdf-content-streams.md) の 87 行の「この経路には、展開の合計の上限のほかの上限を設けない」を、この ADR で置き換える。
  採択したら、[ADR 0051](0051-reuse-repeated-pdf-content-streams.md) のステータスの行に、部分「使い回すときの出力」のうち、外側の内容にほかの上限を設けないとした一文を、この ADR による置き換えとして足す。
- G08015 の一覧（`docs/diagnostics.md`）と golem-pdf の仕様書の「資源の上限」に、使い回す経路の外側の内容も数えることを書く。

## 実装しないこと

- 上限の値は変えない（256 MiB のまま）。
- 展開の合計の上限（G08010）と、使い回しの判定は変えない。
- 新しいコードは作らない。
  使い回す経路でも使い回さない経路でも、原因は「ページの内容をつなぐと 256 MiB を超える」の一つだからである。

## 不変条件

「つなぐ長さ」は、`joinContent` がつなぐ前に計算する長さ（部品の長さとあいだの改行の数の和）とする。

- I1：どの部品の列でも、`joinContent` が内容を返すなら、つなぐ長さは 256 MiB 以下であり、返す内容の `BS.length` はつなぐ長さに等しい。
- I2：どの図版の PDF でも、使い回す経路と使い回さない経路のどちらでも、つなぐ長さが 256 MiB を超えるなら、`importM` は G08015 を返す。
  使い回す経路でも使い回さない経路でも同じである。
- I3：使い回す経路で長さが 256 MiB 以下の入力の出す内容は、この ADR の前と同じである。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| 256 MiB のストリーム一つ | 読める | I1 |
| 空のストリームを二回、256 MiB のストリームを一回名指し | G08015（`Do` の行と改行の分だけ超える） | I2 |
| 128 MiB のストリーム二つ（使い回さない） | G08015（改行の 1 バイト超える） | I2 |
| 使い回す経路で、つないだ長さがちょうど 256 MiB | 読める | I1, I3 |
| 同、ちょうど 256 MiB + 1 | G08015 | I2 |

## 受けいれ条件

なし。
この ADR の振る舞いは、不変条件のテストで確かめる。

## テスト設計

- golem-pdf の `test/SecuritySpec.hs` に、上の表の行ごとのテストを置く。
  名前は `root ADR 0409 I<番号>: ...` とする。
- I2 の使い回す経路のテストは、実装の前に、今のコードで内容が返ることを確かめて失敗させる。
- I1 と I2 は、部品の数 1〜4、各部品の長さ {0, 1, 3}、名指しの重なりのありなしのすべての組で、`joinContent` の計算した長さが、返した内容の `BS.length` に等しいことを確かめる。
  境界の 256 MiB の入力は、部品の長さを上限から逆算して作る。
- I3 は、今ある [ADR 0051](0051-reuse-repeated-pdf-content-streams.md) と [ADR 0359](0359-imported-content-separators.md) のテストが変わらずに通ることで確かめる。

## トレードオフ

境界の近くで読めていた正当な PDF のうち、使い回す経路で 256 MiB を `Do` の行の分だけ超えるものは、G08015 になる。
そのような PDF は、ほぼ存在しないと見込む（確かめていない）。
規則が「どの経路でも、書く内容は 256 MiB まで」の一つになり、境界の説明が一つで済む。

## 参考文献

- [ADR 0051](0051-reuse-repeated-pdf-content-streams.md)
- [ADR 0359](0359-imported-content-separators.md)
- [ADR 0040](0040-pdf-import-resource-limits.md)
- Codex の PR #975（閉じた）：<https://github.com/tett23/golem/pull/975>
