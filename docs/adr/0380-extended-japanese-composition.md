# ADR 0380: 割注、左傍線、縦組みの正立欧文と字送りを扱う

ステータス: 採択（未実装）

## 文脈

ルビと和文組版の拡張のうち、書き手が必要とする「和文組版の拡張」の扱いを決める。

## 調査した事項

ロードマップの「ルビと和文組版の拡張」は「和文組版の拡張」を v1.0.0 の対象に挙げている。

## 実装すること

割注を二行に分け、両行の長い方の幅が最小になる書記素境界を選ぶ。
同値なら先頭に近い境界を採る。
縦組みの傍線は左右を選択可能とする。
正立を選んだ欧文は書記素ごとに回転せず置く。
版面の字送りを正の長さで指定し、字形の大きさを保ったまま配置の間隔に使う。

割注は `[warichu: 本文]`、縦組みの正立欧文は `[upright: ABC]` と書く。
縦組みの傍線には side=left または right を指定し、既定は right とする。
版面の character-advance を省略した場合は現行の字送りを使う。

## 実装しないこと

既存の原稿を新しい指定へ自動変換する機能は設けない。

## 不変条件

1. 割注を二行に割った結果を順に連結すると元の書記素列に一致する。

| 境界の入力 | 期待する結果 |
| --- | --- |
| 割注が1文字 | 一方は空 |
| 正立のAB | 正立2字 |
| 字送り0 | 拒否 |

## テスト設計

- `inv1_extended_japanese_composition_property` で次の述語を検査する。割注を二行に割った結果を順に連結すると元の書記素列に一致する。
- `inv1_extended_japanese_composition_case_1` は「割注が 1 文字」を入力とし、「一方は空」を確かめる。
- `inv1_extended_japanese_composition_case_2` は「正立の AB」を入力とし、「正立 2 字」を確かめる。
- `inv1_extended_japanese_composition_case_3` は「字送り 0」を入力とし、「拒否」を確かめる。

## トレードオフ

個別の字送りを使うと、全角の字数から単純に行幅を逆算できなくなる。

## 参考文献

- [Golem のロードマップ「ルビと和文組版の拡張」](../roadmap.md)
- [ADR 0270](../adr/0270-underline-and-strikethrough.md)
- [golem-layout ADR 0002](../golem-layout/adr/0002-japanese-composition.md)
- [golem-layout-spec ADR 0001](../golem-layout-spec/adr/0001-page-geometry.md)
