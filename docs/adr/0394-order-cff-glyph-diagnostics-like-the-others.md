# ADR 0394: CFF のグリフの diagnostic をほかと同じ規則で並べる

Status: accepted

## 文脈

[ADR 0390](0390-deterministic-and-exhaustive-cff-random.md) は、G08108 と G08109 を「フォントとグリフの番号の組ごとに一度出し、フォントのパス、グリフの番号の順に並べる」と決めた。
一方、diagnostics の全体の並べ方は [golem-syntax ADR 0003](../golem-syntax/adr/0003-diagnostic-order.md) が決めており、同じコードのあいだでは、ファイルの順、開始位置の順、終了位置の順、メッセージの順で並べる。
G08108 と G08109 は位置が同じ（`style.toml` の先頭）なので、メッセージの文字列の順に並ぶ。
メッセージは `<フォントのパス> のグリフ <番号>` を含むので、同じフォントのグリフ 10 がグリフ 9 より先に出る。

[ADR 0390](0390-deterministic-and-exhaustive-cff-random.md) の実装（PR #1028）は、グリフの番号の順に作った diagnostic を全体の並べ替えに渡しており、出力はメッセージの文字列の順になっている。

tett23 は、2026-11-18 に、メッセージの文字列の順に並べると決めた。
書き手は、ふつうグリフの番号の順を意識していないためである。

## 調査した事項

- [golem-syntax ADR 0003](../golem-syntax/adr/0003-diagnostic-order.md) の並べ方のキーは、(notice か, ファイル, 開始位置, 終了位置, コード, メッセージ) の順で、メッセージは最後のキーである。仕様書の「構文木と diagnostics」の節も、群の中はコードの順、ファイルの順、開始位置の順、終了位置の順、メッセージの順で並べると書いている。
- 仕様書と `docs/diagnostics.md` には、G08108 と G08109 をグリフの番号の順に並べるとは書かれていない（`git grep -n 'グリフの番号の順' -- docs` は [ADR 0390](0390-deterministic-and-exhaustive-cff-random.md) の一行だけを返す）。

## 実装すること

- G08108 と G08109 は、ほかの diagnostic と同じく [golem-syntax ADR 0003](../golem-syntax/adr/0003-diagnostic-order.md) の規則で並べる。同じコードと同じ位置のあいだでは、メッセージの文字列の順になる。
- [ADR 0390](0390-deterministic-and-exhaustive-cff-random.md) の「フォントのパス、グリフの番号の順に並べる」を、この ADR で置き換える。[ADR 0390](0390-deterministic-and-exhaustive-cff-random.md) のステータスの行に、その部分を置き換えたことを記録する。
- 今の実装はすでにこの順で出すので、コードは変えない。

## 実装しないこと

- メッセージの中のグリフの番号を、桁をそろえて書くこと。
- [golem-syntax ADR 0003](../golem-syntax/adr/0003-diagnostic-order.md) の並べ方を変えること。

## 不変条件

- I1: G08108 と G08109 の並びは、[golem-syntax ADR 0003](../golem-syntax/adr/0003-diagnostic-order.md) の並べ方のキーの順に等しい。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| 同じフォントのグリフ 9 と 10 が G08109 に当たる | グリフ 10、グリフ 9 の順 | I1 |
| 二つのフォントのグリフが G08108 に当たる | フォントのパスの文字列の順 | I1 |

## 受けいれ条件

なし。
自動のテストで確かめられることは、不変条件に書いた。

## テスト設計

- I1 は、`ADR 0394 I1: ` で始まる名前のテストで、境界の表の二行を、[ADR 0390](0390-deterministic-and-exhaustive-cff-random.md) の試験用のフォントか合成した入力で確かめる。今の実装でも通るので、先に失敗させる手順の例外とする。

## トレードオフ

- グリフの番号が桁の違う数のとき、番号の大小の順と並びが一致しない。書き手はふつうグリフの番号の順を意識しないので、ほかの diagnostic と同じ規則で並ぶことを選んだ。

## 参考文献

- [ADR 0390](0390-deterministic-and-exhaustive-cff-random.md)
- [golem-syntax ADR 0003](../golem-syntax/adr/0003-diagnostic-order.md)
