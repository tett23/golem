# ADR 0430: 利用者に見せる文の「フォルダー」を「フォルダ」にそろえる

Status: accepted

## 文脈

利用者向けのマニュアルは、方針の文書（docs/manual-policy.md）に従い、「フォルダ」と書く。
2026-11-23 に、マニュアルの地の文に残っていた「フォルダー」を「フォルダ」にそろえた（PR #1117）。

ところが、Golem が出す diagnostic のメッセージの一つ（G08102）は、今も「フォルダー」と書いている。
マニュアルの付録 E は、このメッセージをそのまま引くので、そこだけ「フォルダー」が残った。
`golem explain` が出す説明の文にも、「フォルダー」が残っている。
メッセージを変えることは振る舞いの変更なので、この ADR で決める。

## 調査した事項

origin/main（[b6d301361](https://github.com/tett23/golem/commit/b6d301361d77f60faf87336b8a58b13d5905fa9f)）で、次のことを確かめた。

- Golem のソースコードのうち、利用者に見せる文で「フォルダー」を使うのは、G08102 のメッセージ「図版の画像の出力のパスが、プラグインの画像を置くフォルダー images/golem-plugin と重なります: <パス>」だけである（[Driver.hs#L1022](https://github.com/tett23/golem/blob/b6d301361d77f60faf87336b8a58b13d5905fa9f/modules/golem-driver/src/Golem/Driver.hs#L1022)）。
  このメッセージは [root ADR 0137](0137-plugin-image-folder-collision-g08102.md) が決めた。
  golem-driver の `PluginsSpec.hs` が、この文を確かめている。
- docs/diagnostics.md は、G08102 の見出しとメッセージと説明、G08104 の説明で、「フォルダー」を 6 回使う。
  `golem explain` は、docs/diagnostics.md の組み込みの写しを出すので、利用者にもこの文が見える。
- docs/manual-policy.md の InDesign の語との対応の表は、プロジェクトの `fonts/` を「Document Fonts フォルダー」と書く。
  マニュアルの付録 F の同じ対応は、PR #1117 で「Document Fonts フォルダ」に直した。
- 仕様書は「フォルダー」を 6 行で 8 回、README は 3 回使う。
  どちらもマニュアルの方針の対象ではない。
- docs/manual-policy.md の対応の表は、[root ADR 0024](0024-manual-audiences-and-policy.md) が最初の表として決めたものである。
  0024 は以後の表の変更を縛らないので、表を直しても 0024 の決定は変わらない。
- `experiments/diagnostics/` の記録（`catalog.tsv` など）にも、このメッセージと「フォルダー」が残っている。

指示者は 2026-11-23 に、「フォルダ」で統一するよう求め、この ADR を書くよう求めた。

## 実装すること

Golem が利用者に見せる文では、「フォルダ」と書く。
利用者に見せる文とは、diagnostic のメッセージと、`golem explain` が出す説明の文（docs/diagnostics.md とその組み込みの写し）である。

- G08102 のメッセージを、「図版の画像の出力のパスが、プラグインの画像を置くフォルダ images/golem-plugin と重なります: <パス>」にする。
  diagnostic のコード G08102 は変えない。
- docs/diagnostics.md の G08102 と G08104 の項の「フォルダー」を「フォルダ」にし、`scripts/gen-embedded.sh` で組み込みの写しを作り直す。
- マニュアルの付録 E の G08102 の項が引くメッセージを、新しいメッセージに直す。
- docs/manual-policy.md の対応の表の「Document Fonts フォルダー」を、マニュアルの付録 F に合わせて「Document Fonts フォルダ」にする。

これからメッセージや説明の文を足すときも、「フォルダ」と書く。
これを守らせるため、`scripts/ci/test.sh` に、`modules/*/src` と `modules/*/app` の Haskell のソースに「フォルダー」が無いことを確かめる検査を足す。

### ステータスの行

採択したら、[root ADR 0137](0137-plugin-image-folder-collision-g08102.md) のステータスに、`{"part":"メッセージ","by":["docs/adr/0430-use-folda-in-user-facing-text.md"],"kind":"replace"}` を足す。
0137 の今のステータスが `accepted` なら `superseded [...]` に、`superseded [...]` なら配列に足す。

## 実装しないこと

仕様書と README の「フォルダー」は変えない。
この ADR が定める利用者に見せる文（diagnostic のメッセージと `golem explain` の説明）に入らず、マニュアルの方針の対象でもないためである。
`experiments/` の記録と、コミット済みの ADR と監査の記録の「フォルダー」も変えない。
diagnostic のコード G08102 と、それを出す条件は変えない。
開発者向けのマニュアル（manual-dev）は、「フォルダー」を使っていないので変えない。

## 不変条件

- I1: G08102 のメッセージは「フォルダ」を含み、「フォルダー」を含まない。
- I2: `golem explain` が出すすべての項の文は、「フォルダー」を含まない。
- I3: 図版の画像の出力のパスが `images/golem-plugin/` の下にあるときに限り、G08102 が出る。
- I4: `modules/*/src` と `modules/*/app` の Haskell のソースは、「フォルダー」を含まない。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| 図版の画像の出力のパスが `images/golem-plugin` と重なるプロジェクト | 新しいメッセージの G08102 | I1, I3 |
| 図版の画像の出力のパスが重ならないプロジェクト | G08102 が出ない | I3 |
| 図版の画像の出力のパスが `images/golem-plugin-x/` の下 | G08102 が出ない | I3 |
| 図版の画像の出力のパスが `images/golem-plugin/a.png` | 新しいメッセージの G08102 | I1, I3 |
| `modules/*/src` の Haskell のソース | 「フォルダー」が無い | I4 |
| `golem explain G08102` | 「フォルダー」を含まない | I2 |
| `golem explain G08104` | 「フォルダー」を含まない | I2 |
| すべてのコードの `golem explain` | 「フォルダー」を含まない | I2 |

## 受けいれ条件

なし。
不変条件のテストで足りるためである。

## テスト設計

root ADR 0430 I1 から I3 を名前の先頭に置いたテストを golem-driver に、I4 を名前の先頭に置いたテストを `scripts/ci/test.sh` に足す。
I1 と I3 は、`PluginsSpec.hs` の G08102 のテストの期待を新しいメッセージに直し、境界の表の重ならない入力で G08102 が出ないことも確かめる。
I2 は、`DiagnosticsSpec.hs` で、組み込みの写しのすべての項の文に「フォルダー」が無いことを確かめる。
I1、I2、I4 は、実装の前に落ちることを確かめる。
マニュアルの付録 E の G08102 の項は、自動の検査が無いので、実装のときに新しいメッセージと照らして直す。

## トレードオフ

メッセージの文が変わるので、メッセージの文を照らし合わせている利用者のスクリプトは、直す必要がある。
diagnostic のコード（G08102）は変わらないので、コードで照らし合わせているスクリプトには影響しない。

仕様書と README には「フォルダー」が残るので、リポジトリの中で二つの書き方が混ざる。
利用者に見せる文だけをそろえるのは、マニュアルの方針が利用者に見せる語を決めているためである。

## 参考文献

- [root ADR 0024](0024-manual-audiences-and-policy.md)
- [root ADR 0137](0137-plugin-image-folder-collision-g08102.md)
- docs/manual-policy.md
