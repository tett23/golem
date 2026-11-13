# ADR 0364: 柱とノンブルの文字スタイルを個別に選ぶ

ステータス: 採択

## 文脈

スタイルのうち、書き手が必要とする「柱とノンブル」の扱いを決める。

## 調査した事項

Golem [ADR 0177](0177-note-mark-style-and-numerals.md) の調査は、次の扱いを記録している。
`masterMarks` と `textAt` が、本文の役割の書体と版面の文字の大きさで描く（[`Draw.hs` の `masterMarks`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Draw.hs#L1056-L1072)、[`textAt`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Draw.hs#L681-L689)）。

## 実装すること

文字を表示する部品には、原則として段落スタイルと文字スタイルを適用できるようにする（[仕様書の設計原則](../specifications.md#組版の自由)）。
マスターページの running-head と folio でそれぞれ character-style を参照する。
書体、大きさ、色を解決してから配置する。
省略時は従来の本文書体と版面の文字サイズを使う。

同一マスターの奇数ページと偶数ページで内容が異なっても、各部品には同じ指定を使う。

## 実装しないこと

既存の原稿を新しい指定へ自動変換する機能は設けない。

## 不変条件

1. 同じマスターの柱だけを変更してもノンブルの実効文字スタイルは変わらない。

| 境界の入力 | 期待する結果 |
| --- | --- |
| 柱だけ指定 | ノンブルは既定 |
| 両方指定 | 各自のスタイル |

## テスト設計

- `inv1_running_head_folio_style_property` で次の述語を検査する。同じマスターの柱だけを変更してもノンブルの実効文字スタイルは変わらない。
- `inv1_running_head_folio_style_case_1` は「柱だけ指定」を入力とし、「ノンブルは既定」を確かめる。
- `inv1_running_head_folio_style_case_2` は「両方指定」を入力とし、「各自のスタイル」を確かめる。

## トレードオフ

柱の書体を変えると欄をはみ出す可能性があり、使用する書体で幅を測り直す必要がある。

## 参考文献

- [Golem のロードマップ「スタイル」](../roadmap.md)
