# ADR 0369: ルビの読みの文字スタイルを選ぶ

ステータス: 採択

## 文脈

スタイルのうち、書き手が必要とする「ルビの読み」の扱いを決める。

## 調査した事項

Golem [ADR 0177](0177-note-mark-style-and-numerals.md) の調査は、次の扱いを記録している。
外側の書体と色で、親文字の半分の大きさで組み、文字スタイルを当てる手段がない（[`readingAdvances`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-layout/src/Golem/Layout/Japanese.hs#L574-L576)、[golem-layout ADR 0011](../golem-layout/adr/0011-ruby-base-character-styles.md)）。

## 実装すること

読みだけに文字スタイルを当てる。
未指定の書体と色は外側から継承し、サイズは親文字の半分を既定とする。
明示した読みのサイズで計測して配置する。

`[composition.ruby]` の reading-style に文字スタイル名を指定する。

## 実装しないこと

既存の原稿を新しい指定へ自動変換する機能は設けない。

## 不変条件

1. 読みの指定だけを変えても親文字の実効書体、大きさ、色は変わらない。

| 境界の入力 | 期待する結果 |
| --- | --- |
| 指定なし | 親文字の半分 |
| 色のみ | サイズは半分 |
| サイズ指定 | 指定値 |

## テスト設計

- `inv1_ruby_reading_style_property` で次の述語を検査する。読みの指定だけを変えても親文字の実効書体、大きさ、色は変わらない。
- `inv1_ruby_reading_style_case_1` は「指定なし」を入力とし、「親文字の半分」を確かめる。
- `inv1_ruby_reading_style_case_2` は「色のみ」を入力とし、「サイズは半分」を確かめる。
- `inv1_ruby_reading_style_case_3` は「サイズ指定」を入力とし、「指定値」を確かめる。

## トレードオフ

読みの実寸を使うため、大きな読みでは親文字の占有幅も増えうる。

## 参考文献

- [Golem のロードマップ「スタイル」](../roadmap.md)
