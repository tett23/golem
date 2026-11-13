# ADR 0360: タグ付き PDF のルビの親文字に Reference を残す

ステータス: 採択

## 文脈

フォント、PDF、EPUB の出力のうち、書き手が必要とする「ルビの親文字の中の参照」の扱いを決める。

## 調査した事項

ロードマップの「フォント、PDF、EPUB の出力」は「ルビの親文字の中の参照」を v1.0.0 の対象に挙げている。

## 実装すること

親文字を表す RB の下で ref-number と ref-title の範囲だけを Reference とする。
周囲の親文字と読みの RT は別に保持し、参照先と論理順を保つ。

RB は親文字、RT は読みの構造要素である。
参照の前後に通常文字がある場合も、本文の読み順で対応する描画内容を一度ずつ登録する。

## 実装しないこと

読みの内容を参照のラベルに含めない。

## 不変条件

1. 親文字内の有効な参照の数と RB の下の Reference の数が一致する。

| 境界の入力 | 期待する結果 |
| --- | --- |
| 参照なし | Reference が0個 |
| 親文字中の連続する2参照 | 原稿順に2個 |

## テスト設計

- `inv1_ruby_base_references_property` で次の述語を検査する。親文字内の有効な参照の数と RB の下の Reference の数が一致する。
- `inv1_ruby_base_references_case_1` は「参照なし」を入力とし、「Reference が 0 個」を確かめる。
- `inv1_ruby_base_references_case_2` は「親文字中の連続する 2 参照」を入力とし、「原稿順に 2 個」を確かめる。

## トレードオフ

親文字内部の範囲を記録するため、構造の木と描画との対応が細かくなる。

## 参考文献

- [Golem のロードマップ「フォント、PDF、EPUB の出力」](../roadmap.md)
- [docs/adr/0215](../adr/0215-ref-number-and-ref-title-as-reference.md)
- [docs/adr/0229](../adr/0229-record-the-procedures-adr-0215-and-0217-departed-from.md)
