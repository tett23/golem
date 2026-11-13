# ADR 0367: キャプションと傍注に段落の組み方も適用する

ステータス: 採択（未実装）

## 文脈

スタイルのうち、書き手が必要とする「図版のキャプションと傍注の本文」の扱いを決める。

## 調査した事項

Golem [ADR 0177](0177-note-mark-style-and-numerals.md) の調査は、次の扱いを記録している。
段落スタイル `caption` と `sidenote` の見た目だけを使い、字下げ、`space-between`、`line-breaks` を当てない（[`Flow.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L1507-L1511)、[golem-driver ADR 0010](../golem-driver/adr/0010-caption-style.md)、[golem-driver ADR 0043](../golem-driver/adr/0043-caption-sidenote-do-not-inherit-indent.md)）。

## 実装すること

caption と sidenote の段落スタイルから字下げ、space-between、line-breaks を本文と同じ順序で解決する。
領域の幅は各部品の内幅を使い、決定した行数を部品の高さに反映する。

本文からの自動継承を防ぐ組み込みの indent、first-line-indent、end-indent の 0 指定は保つ。

## 実装しないこと

既存の原稿を新しい指定へ自動変換する機能は設けない。

## 不変条件

1. 各行の使用可能幅は部品の内幅からその行に適用する字下げを引いた値に等しい。

| 境界の入力 | 期待する結果 |
| --- | --- |
| 字下げ0 | 全幅を使用 |
| 先頭行だけ1字下げ | 先頭行だけ有効幅が1字減る |

## テスト設計

- `inv1_caption_sidenote_paragraphs_property` で次の述語を検査する。各行の使用可能幅は部品の内幅からその行に適用する字下げを引いた値に等しい。
- `inv1_caption_sidenote_paragraphs_case_1` は「字下げ 0」を入力とし、「全幅を使用」を確かめる。
- `inv1_caption_sidenote_paragraphs_case_2` は「先頭行だけ 1 字下げ」を入力とし、「先頭行だけ有効幅が 1 字減る」を確かめる。

## トレードオフ

部品にも段落の規則を適用すると、必要な高さが増える原稿がある。

## 参考文献

- [Golem のロードマップ「スタイル」](../roadmap.md)
