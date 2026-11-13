# ADR 0385: 書誌と本文の引用を共通の文献スタイルで組む

ステータス: 採択（未実装）

## 文脈

本の部品の拡張のうち、書き手が必要とする「参考文献のスタイル」の扱いを決める。

## 調査した事項

意味論 IR の引用は文献ごとのキー、位置、前置き、後置きをすでに持ち、今は出力の前の検査で止める（[docs/adr/0266](../adr/0266-citation-locators-and-multiple-keys.md)）。

## 実装すること

書き手が投稿先の規定に合わせて文献スタイルを作り、本ごとに指定できるようにする。
文献種別ごとに著者、年、題などの欄の順、欠けた欄の省略、区切り、著者名順のソートとぶら下げ字下げを宣言する。
引用は番号式と著者年式を選べる。
引用の各キーに位置の種類、値、前置き、後置きを対応づけ、スタイルが page や chapter のラベルを言語別に展開する。
既定の書誌と単一の番号引用には従来の出力を使う。

既存の cite に加えて、各文献を個別に書く `[cites: [cite a page=5]|[cite b chapter=2 prefix="参照"]]` を一つの印に組む。
Golem [ADR 0266](0266-citation-locators-and-multiple-keys.md) の G06009 の検査では、定義済みの位置の種類と妥当な前置き、後置きを許す。
配列内のキーの重複は現在の G02147 とし、重複するキーの位置で報告する。
各スロットには単一キーの cite を一つ置き、位置の種類の重複と未知の欄は拒む。
書誌スタイルに citation-mode（numeric または author-year）、sort（citation または author）、hanging-indent（非負の寸法）、種別ごとの fields（欄名の順序付き配列）と separator を持たせる。

投稿先ごとに著者名の順序とイニシャル、複数著者の列挙と省略、題や誌名の文字スタイル、欄の有無による条件分岐、各欄の前後の句読点を指定できるようにする。
書き手が定義したスタイルを選んで同じ論文を組み直せることを、投稿規定から採った書誌例と本文中の引用例の両方で照合する。

## 実装しないこと

BibTeX のスタイルプログラムの実行は扱わない。

## 不変条件

1. 文献キーに対応する位置、前置き、後置きは一覧のソート順を変えても同じキーに属する。

| 境界の入力 | 期待する結果 |
| --- | --- |
| 頁なし | 頁ラベルなし |
| 2文献に別の頁 | 各頁が対応する文献に付く |
| 同著者同年 | 文献キー順に a、b |

## テスト設計

- `inv1_bibliography_and_citation_styles_property` で次の述語を検査する。文献キーに対応する位置、前置き、後置きは一覧のソート順を変えても同じキーに属する。
- `inv1_bibliography_and_citation_styles_case_1` は「頁なし」を入力とし、「頁ラベルなし」を確かめる。
- `inv1_bibliography_and_citation_styles_case_2` は「2 文献に別の頁」を入力とし、「各頁が対応する文献に付く」を確かめる。
- `inv1_bibliography_and_citation_styles_case_3` は「同著者同年」を入力とし、「文献キー順に a、b」を確かめる。

投稿規定の異なる雑誌から番号式と著者年式の例を取り、共通の書誌データを使い、書き手が作ったスタイルの切り替えだけで規定どおりの引用と一覧になることを確かめる。

## トレードオフ

宣言的な書式は同じ入力の結果を比較しやすいが、既存の BibTeX スタイルを直接実行できない。

## 参考文献

- [Golem のロードマップ「本の部品の拡張」](../roadmap.md)
- [golem-doc ADR 0005](../golem-doc/adr/0005-bibliography-fields.md)
- [golem-doc ADR 0002](../golem-doc/adr/0002-document-assembly.md)
- [golem-driver ADR 0007](../golem-driver/adr/0007-pdf-index-and-bibliography.md)
- [docs/adr/0266](../adr/0266-citation-locators-and-multiple-keys.md)
