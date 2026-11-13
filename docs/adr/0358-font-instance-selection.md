# ADR 0358: 指定した可変フォントのインスタンスで組み、PDF に固定する

ステータス: 採択（未実装）

## 文脈

フォント、PDF、EPUB の出力のうち、書き手が必要とする「可変フォント」の扱いを決める。

## 調査した事項

今は可変フォントを既定のインスタンスとして組むが、サブセットで軸を固定しないので、使わない可変のデータ（fvar、gvar、HVAR、MVAR など）も PDF に埋め込んでいる。

## 実装すること

書体の役割に名前付きインスタンスと軸タグ別の座標を指定できるようにする。
名前で選んだ座標に、明示した軸の値を上書きする。
未知の名前、軸、範囲外の値は拒む。
同じ座標でシェーピングと固定化を行う。
CFF2 は HarfBuzz 更新後、変換前後の全使用グリフの描画比較を通すまで G08019 を保つ。

例として `[fonts.body]` に `instance = "Bold"` と `axes = { wght = 650 }` を書く。
明示されない軸は、名前を指定した場合はそのインスタンスの座標、指定しなければフォント既定の座標とする。

## 実装しないこと

可変フォントの編集機能は設けない。

## 不変条件

1. 計測、描画、サブセットに渡す軸座標は各軸で一致する。

| 境界の入力 | 期待する結果 |
| --- | --- |
| 指定なし | 既定座標 |
| 軸の上限 | 受理 |
| 上限超過 | 拒否 |

## テスト設計

- `inv1_font_instance_selection_property` で次の述語を検査する。計測、描画、サブセットに渡す軸座標は各軸で一致する。
- `inv1_font_instance_selection_case_1` は「指定なし」を入力とし、「既定座標」を確かめる。
- `inv1_font_instance_selection_case_2` は「軸の上限」を入力とし、「受理」を確かめる。
- `inv1_font_instance_selection_case_3` は「上限超過」を入力とし、「拒否」を確かめる。

## トレードオフ

固定化で PDF のサイズは減るが、インスタンスごとに別のフォントを埋め込む。

## 参考文献

- [Golem のロードマップ「フォント、PDF、EPUB の出力」](../roadmap.md)
- [golem-font ADR 0003](../golem-font/adr/0003-reject-cff2-fonts-in-pdf.md)
- [golem-font ADR 0001](../golem-font/adr/0001-shaping-and-metrics.md)
- [golem-driver ADR 0004](../golem-driver/adr/0004-pdf-emphasis-and-character-styles.md)
