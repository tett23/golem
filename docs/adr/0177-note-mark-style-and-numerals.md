# ADR 0177: 注の印の文字スタイルと数字の表記

ステータス: 採択→見出し、図版、コードブロック、ノンブルの表せない番号は [ADR 0213](0213-numbers-the-number-formats-cannot-write.md)

## 文脈

docs/roadmap.md の v0.1.0-rc4 には、注の印について二つの項目がある。

- 「注の印の文字スタイル」：注の印に文字スタイル（`[notes]` の `mark-style`）を当てられるようにする。
- 「注の印の数字の表記」：注の印の番号を、算用数字のほかに、漢数字や記号の連なり（JLReq の 4.2.2 が挙げる形）で組めるようにする。

どちらも、[golem-driver ADR 0025](../golem-driver/adr/0025-note-mark-size-and-format.md) が「実装しないこと」に置いた事項である。
[golem-driver ADR 0025](../golem-driver/adr/0025-note-mark-size-and-format.md) のメンテナーの決定は、`mark-style` を v0.1.0-rc4 で加えること、加えた後も `mark-size` と `mark-format` の意味を変えないこと、の二つである。
この ADR は二つの項目を一つにまとめて扱う。
数字の表記を変えると印の字の種類が変わり、縦組みで印をどの向きに組むかが変わる。
文字スタイルで書体を変えると、印の位置の計算が変わる。
どちらも同じ印の箱（`KindNoteMark`）の組み方を変えるので、別々に決めると二度手直しすることになる。

草稿のレビューで、メンテナーは、この ADR に限らない設計原則を一つ決めた（2026-11-07）。
すべての文字には段落スタイルや文字スタイルを当てられるべきであり、組版の自由を制限してはいけない。
この ADR は、その原則を docs/specifications.md の「設計原則」の節に加える。
原則はこの ADR の外にも及ぶので、原則に反する今の箇所を下の「原則に反する今の箇所」に挙げる。

### 今の印の組み方

コードを読んで確かめた（`50b9fca8`）。

- 本文の印は、golem-layout の `piecesOf` が、`mark-format` の `{n}` を算用数字に置き換えた文字列で `KindNoteMark` の箱を作る（[`Japanese.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-layout/src/Golem/Layout/Japanese.hs#L300-L305)、[`markPiece`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-layout/src/Golem/Layout/Japanese.hs#L321-L340)）。置き換えは `T.replace "{n}"` であり、ほかの `{` と `}` は文字のまま残る。
- 箱は、印の位置の `Look` をそのまま持つ。印を描くときは、その `Look` の大きさだけを `mark-size` の大きさに替える（[`Draw.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Draw.hs#L626-L638)）。書体と色は印の位置の文字と同じになる。
- 横組みでは、印の基準線を本文の基準線より `(s − m) × (c + 1/2)` 上に置く。`c` は本文の和文の書体の字面の枠の中心（`lfEmBoxCentral`）である。
- 縦組みでは、印を横書きの向きで描き、印の右端を本文の字面の枠の右端にそろえる。箱の行の方向の長さは `m` である（[golem-driver ADR 0018](../golem-driver/adr/0018-footnote-marks-and-numbers.md)）。
- 注の本文の先頭の印は、golem-driver の `withNoteMark` が同じ書式の文字列と四分アキを付けて作る（[`Flow.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L1075-L1076)）。この印はふつうの文字として、注の本文の書体と大きさで組む。
- `style.toml` を読むときは、`mark-format` が `{n}` をちょうど一つ含むことだけを確かめる（[`Style.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-project/src/Golem/Project/Style.hs#L1729-L1732)）。
- 仕様書は、トラッキングを注の印に足さないとしている（「style.toml」の節の四つのキーの説明）。
- HTML と EPUB は、本文の参照（`noteref`）と、注の一覧の戻りのリンクの文字を、算用数字の番号だけで書く（[`Html.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-html/src/Golem/Html.hs#L629-L631)、[同じファイルの注の一覧](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-html/src/Golem/Html.hs#L674)）。EPUB の本文は golem-epub が golem-html の同じ関数で書く。
- プレーンテキストは、横書きで `*1`、縦書きで `※1` に固定している（[`Text.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-text/src/Golem/Text.hs#L103-L104)、[golem-text ADR 0001](../golem-text/adr/0001-plain-text-output.md)）。

### 組んで確かめたこと

蟹工船の fixture（縦組み、Noto Serif JP、13Q）の写しに注を二つ足し、`[notes]` に `mark-size = "0.65zw"` と `mark-format = "（{n}）"` を書いて、`golem 0.1.0-rc3` で組んだ（2026-11-06）。
1 ページ目を 600dpi の画像にして見た結果は次のとおりである。

- 本文の印は、全角の括弧も含めて `（1）` 全体が横書きの向きで、行の右端にそろって並ぶ。
- 注の本文の先頭の印は、括弧が縦組みの字形になり、`1` は欧文として横に倒れている。縦中横にはならない。
- HTML の `noteref` の文字は `1`、プレーンテキストの注は `※1 函館は北海道の港町。` であり、どちらも `mark-format` によらない。

同じ写しで、次の二つも確かめた。

- `mark-format = "（{一}）"` は、`{n}` を含まないので G03006 になる。
- `mark-format = "{n}{x}"` はエラーにならず、`{x}` が文字のまま印に入る。

`[notes]` に `mark-style` を書くと、知らないキーとして G03006 になる。

### JLReq の 4.2.2 と 4.2.3

JLReq（W3C の公開版）の 4.2.2「注の番号」と 4.2.3「合印の処理」の本文を、2026-11-06 に取得した写しで 2026-11-07 に読み直した。
図は見ていない。
本文の言うことは次のとおりである。

4.2.2 は、注の番号の字と形を述べる。

- 注の番号には、アラビア数字（縦組みと横組み）と漢数字（縦組み）がよく使われる。
- ほかに、アステリスクの個数で示す方法（`＊`、`＊＊`、…）と、アステリスク、ダガー、ダブルダガー、段落記号、節記号、双柱、番号記号の順で示す方法がある。英語版は、それぞれを ASTERISK、DAGGER、DOUBLE DAGGER、PILCROW SIGN、SECTION SIGN、DOUBLE VERTICAL LINE、NUMBER SIGN と呼ぶ。
- アラビア数字か漢数字の番号には、前後に括弧類を付ける形もある。縦組みでは前に始め小括弧、後ろに終わり小括弧を付ける形が多く、横組みでは後ろに終わり小括弧だけを付ける形が多い。
- 縦組みで注の番号にアラビア数字を用いた場合は、一般に縦中横にする。
- 縦組みで注の番号に漢数字を用いた場合は、文字を変形して上下の外枠を 50% にした漢数字（平字）を使う例が多い。
- 本文の該当箇所に付けた注の番号を合印といい、文字クラスは合印中の文字（cl-20）である。
- 番号を始め直す単位は、後注では章や節が多く、縦組みの傍注では見開き、横組みの脚注ではページが多い。

4.2.3 は、合印を置く位置と組み方を述べる。

- 合印は、該当項目に接して行間（縦組みでは右、横組みでは上）に置く方法と、該当項目の後ろの行の中に置く方法がある。行の中に置き、該当項目が文末なら、一般に句点類の前に置く。
- 縦組みで行の中に置く場合、合印の文字の大きさは基本版面の文字の大きさより 1 段階か 2 段階小さくし、行送りの方向の位置は行の右端にそろえる。
- 行の中に置く合印は、始め括弧類と終わり括弧類を含めて一体として扱い、その字間で 2 行に分けない。行の調整で字間を空けず、前後とはベタ組みにする（後ろに始め括弧類が来る場合を除く）。
- 横組みで行の中に置く合印の文字は、添え字の上付き文字と同じとする。

縦組みの合印の向きについて、本文が直接述べるのは「アラビア数字は縦中横」と「漢数字は平字」の二つである。
括弧類は合印の一部として行の中に置き、行の右端にそろえる。
縦組みの行の中の括弧類は、縦組みの字形で組むものである。
したがって JLReq に従う縦組みの合印は、字の列が行の方向に並び、アラビア数字だけが縦中横になる形である。
今の Golem の、括弧を含めた印の全体を横書きの向きで並べる組み方は、これに合わない。

記号の連なりが尽きたとき（八つめの注）にどうするかは、4.2.2 にも 4.2.3 にも書かれていない。
Golem は、ページごとに振り直す方式を v1 では採らない（docs/specifications.md の「脚注」の節）。
章ごとに振り直す本では、七つの記号は一つの章の中で尽きやすい。

### 書式の差し込みと括弧

`style.toml` には、差し込みを `{` と `}` で囲む書式が、注のほかに三つある。
括弧そのものの書き方は、書式ごとに違う。

| 書式 | 読む関数 | 差し込み | 括弧そのもの |
| --- | --- | --- | --- |
| `[notes]` の `mark-format` | `T.replace "{n}"`（[`Japanese.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-layout/src/Golem/Layout/Japanese.hs#L330-L332)） | `{n}` | ほかの括弧はそのまま文字 |
| `[lists]` の `numbers` | golem-doc の [`parseNumberFormat`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-doc/src/Golem/Doc/ListMarkers.hs#L65-L91) | `{n}`、`{1}`、`{一}`、`{①}`、`{a}`、`{A}`、`{i}`、`{I}`、`{イ}`、`{ア}` | `{{` と `}}` |
| 柱の書式 | golem-project の [`parseRunningFormat`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-project/src/Golem/Project/Style.hs#L974-L1010) | `{heading.1.short}`、`{meta.title}` など | `{{` と `}}` |
| 見出し、図版、コードブロック、ノンブルの番号の書式 | golem-doc の [`formatNumber`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-doc/src/Golem/Doc/Numerals.hs#L61-L80)、検査は golem-project の [`validNumberFormat`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-project/src/Golem/Project/Style.hs#L1930-L1941) | `{n}`、`{n:kanji}`、`{1}`、`{2}`、`{chapter}` | 書けない。対応のない `}` は文字のまま |

原稿のエスケープは、バックスラッシュ `\` だけである（[docs/markup.md](../markup.md) の「エスケープ」）。
`{{` と `}}` は、書式の中だけの例外である。

数字の表記の名前も、書式ごとに違う。
`[lists]` は表記を一字の見本（`{一}`、`{①}`）で選び、見出しの番号の書式は `{n:kanji}` で選ぶ。
`[number-text ...]` の `style` と `[numbers]` の `vertical` は、`kanji` と `kanji-digits` の語で選ぶ（[golem-parser ADR 0011](../golem-parser/adr/0011-number-shorthand.md)）。
`{1}` は、`[lists]` では算用数字、見出しの番号の書式では第 1 階層の番号を指す。
`[lists]` の表記の表は、`ListNumberStyle` の型と `placeholders` の表と `formatListNumber` の場合分けの三か所に分かれており、表記を一つ足すには三か所を直す（[`ListMarkers.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-doc/src/Golem/Doc/ListMarkers.hs#L28-L122)）。

表せない番号（丸数字の 51 番など）は、リストでは G07029 とし、どのターゲットも書かない。
golem-project、golem-layout、golem-html、golem-text は、どれもすでに golem-doc に依存している（各モジュールの cabal ファイルで確かめた）。

### 原則に反する今の箇所

「すべての文字に段落スタイルか文字スタイルを当てられる」という原則に照らして、今の Golem のコードを読んだ（`50b9fca8`）。
決まった書体や大きさで組み、スタイルを当てる手段のない文字は、次のとおりである。
網羅したとは言えない。
読んだ範囲で見つけたものである。

1. **注の印**：この ADR で直す。
2. **リストの印**：`listMarker` は印をただの `Text` にし、項目の段落の見た目で組む（[`Flow.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L1212-L1228)）。`[lists]` に文字スタイルの欄はない。
3. **柱とノンブル**：`masterMarks` と `textAt` が、本文の役割の書体と版面の文字の大きさで描く（[`Draw.hs` の `masterMarks`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Draw.hs#L1056-L1072)、[`textAt`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Draw.hs#L681-L689)）。
4. **隠しノンブル**：本文の役割の書体で、`[hidden-folio]` の `size` だけを変えられる（[`hiddenMarks`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Draw.hs#L1041-L1054)）。
5. **脚注と章末の注の本文**：本文の段落スタイルの見た目（`bodyLook`）で組み、段落スタイルを当てる手段がない（[脚注](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L1462-L1470)、[章末の注](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L1258-L1264)）。章末の注の一覧の見出しは、第 2 階層の見出しの書体で組む。
6. **図版のキャプションと傍注の本文**：段落スタイル `caption` と `sidenote` の見た目だけを使い、字下げ、`space-between`、`line-breaks` を当てない（[`Flow.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L1507-L1511)、[golem-driver ADR 0010](../golem-driver/adr/0010-caption-style.md)、[golem-driver ADR 0043](../golem-driver/adr/0043-caption-sidenote-do-not-inherit-indent.md)）。
7. **正規表現スタイルの届かない文字**：見出し、定義リストの用語、表のセル、注の本文には正規表現スタイルを当てない（[`RegexStyle.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-eval/src/Golem/Eval/RegexStyle.hs#L50-L80)）。原稿で `[style ...]` を書けば、文字スタイルは当てられる。
8. **ルビの読み**：外側の書体と色で、親文字の半分の大きさで組み、文字スタイルを当てる手段がない（[`readingAdvances`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-layout/src/Golem/Layout/Japanese.hs#L574-L576)、[golem-layout ADR 0011](../golem-layout/adr/0011-ruby-base-character-styles.md)）。
9. **トラッキングの届かない文字**：縦中横の箱は外側の見た目の大きさで一つの箱になり、トラッキングを足さない（[`Japanese.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-layout/src/Golem/Layout/Japanese.hs#L289)）。仕様書は、ルビ、縦中横、注の印にトラッキングを足さないとしている。注の印はこの ADR で直す。
10. **傍注の `※` の印**：印の位置の見た目のまま組み、文字スタイルを当てる手段がない（[`Japanese.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-layout/src/Golem/Layout/Japanese.hs#L301-L305)）。

1 のほかは、この ADR では直さず、docs/roadmap.md に載せる（「メンテナーが決めること」の 15）。

## 実装すること

### 設計原則（docs/specifications.md）

docs/specifications.md の「設計原則」の節の最後に、次の段落を加える。

```markdown
**組版の自由**。
組版するすべての文字に、段落スタイルか文字スタイルを当てられる。
Golem は、ある文字に当てられるスタイルのキーを狭めず、特定の文字のための専用の欄でスタイルの代わりをしない。
専用の欄は欄の数だけ仕様と実装を増やし、書き手がすでに使っているスタイルの仕組みを、その文字にだけ使えなくするためである。
処理系が文字の位置を決める箇所（注の印の高さなど）も、スタイルを当てた結果の書体と大きさから位置を求める。
この原則に反する今の箇所は [docs/roadmap.md](roadmap.md) に挙げる。
```

原則はこの ADR の外にも及ぶ。
今後の ADR は、文字の見た目を決める欄を足すとき、この原則に照らす。

### 数字の表記の登録表（golem-doc）

数字の表記を、golem-doc の一つの表（登録表）にまとめる（「メンテナーが決めること」の 3）。
表記を足すときは、表に一行を足すだけにする。

- 表の各行は、表記の名前と、番号を書く規則のデータを持つ。
- 規則のデータは次の五種類とする。CSS Counter Styles Level 3 の `system` のうち、ここで要るものと同じ考え方である。
  - **位取り**（numeric）：数字の字の並び。算用数字。
  - **アルファベット**（alphabetic）：字の並び。26 を超えると `aa`、`ab` と続ける。
  - **加法**（additive）：重みと字の組の並び。ローマ数字。
  - **固定**（fixed）：1 番から順に使う字の並び。丸数字、イロハ、アイウエオ、記号の連なり。並びが尽きれば表せない。
  - **繰り返し**（repeat）：一つの字を番号の数だけ並べる。アステリスク。
- データで書けない表記（位取りをする漢数字の `千`、`万` の規則）だけは、関数を持つ行とする。今の `Golem.Doc.Numerals.kanji` と `kanjiDigits` を使う。
- 表せる範囲（最小と最大）は、行のデータから決まる。

v1 の表は次の十一の行とする（「メンテナーが決めること」の 9）。

| 名前 | 表記 | 規則 | 例（3 番、12 番） | 表せる番号 | 今の `[lists]` の差し込み |
| --- | --- | --- | --- | --- | --- |
| `arabic` | 算用数字 | 位取り | `3`、`12` | 0 以上 | `{1}` |
| `kanji` | 位取りをする漢数字 | 関数 | `三`、`十二` | 0 以上 | `{一}` |
| `kanji-digits` | 一字ずつの漢数字 | 関数 | `三`、`一二` | 0 以上 | なし |
| `circled` | 丸数字 | 固定 | `③`、`⑫` | 1 から 50 | `{①}` |
| `lower-alpha` | ラテン文字の小文字 | アルファベット | `c`、`l` | 1 以上 | `{a}` |
| `upper-alpha` | ラテン文字の大文字 | アルファベット | `C`、`L` | 1 以上 | `{A}` |
| `lower-roman` | ローマ数字の小文字 | 加法 | `iii`、`xii` | 1 から 3999 | `{i}` |
| `upper-roman` | ローマ数字の大文字 | 加法 | `III`、`XII` | 1 から 3999 | `{I}` |
| `iroha` | 片仮名のイロハ順 | 固定 | `ハ`、`ヲ` | 1 から 47 | `{イ}` |
| `aiueo` | 片仮名のアイウエオ順 | 固定 | `ウ`、`シ` | 1 から 46 | `{ア}` |
| `asterisks` | U+002A を番号の数だけ並べる | 繰り返し | `***`、`************` | 1 以上 | なし |
| `note-symbols` | JLReq の 4.2.2 の七つの記号の順 | 固定 | `‡`、表せない | 1 から 7 | なし |

`note-symbols` の字は、JLReq の 4.2.2 の順と英語の文字名のとおり、U+002A（`*`）、U+2020（`†`）、U+2021（`‡`）、U+00B6（`¶`）、U+00A7（`§`）、U+2016（`‖`）、U+0023（`#`）とする（「メンテナーが決めること」の 4）。

`kanji` と `kanji-digits` の名前と規則は、`[number-text ...]` の `style` と `[numbers]` の `vertical` の同じ名前と同じにする。
今のリストの表記と同じ規則の行は、今と同じ字を書く。

### 書式の読み方（golem-doc）

差し込みを持つ書式を読む関数を、golem-doc に一つ作る。
四つの書式（注、リスト、柱、番号）は、どれもこの関数で読み、差し込みの名前の表だけを書式ごとに渡す（「メンテナーが決めること」の 12）。

- 書式は、文字、エスケープ、差し込みからなる。
- エスケープは、原稿と同じくバックスラッシュとする。`\{` は `{`、`\}` は `}`、`\\` は `\` を書く。`\` の後にほかの字を書くか、`\` で書式が終わると誤りである。
- 差し込みは `{` と `}` で囲む。エスケープしない `{` で閉じていないもの、エスケープしない `}` で対応のないものは誤りである。
- 数を書く差し込みは `{<数>}` か `{<数>:<表記>}` とする。`<表記>` は登録表の名前である。`{<数>}` の表記は書式ごとに決まる。
- `style.toml` の基本の文字列（`"..."`）では、TOML の規則で `\{` を書けない。リテラル文字列（`'...'`）で `'\{{n}\}'` と書くか、基本の文字列で `"\\{{n}\\}"` と書く。仕様書の正規表現スタイルの説明と同じ注意を書く。

四つの書式の数の差し込みは、次のとおりとする。

| 書式 | 数 | `{<数>}` の表記 |
| --- | --- | --- |
| `[notes]` の `mark-format` | `n`（注の番号） | `arabic`（[golem-driver ADR 0025](../golem-driver/adr/0025-note-mark-size-and-format.md)） |
| `[lists]` の `numbers` | `n`（項目の番号） | 本の数の表記（今のとおり） |
| 見出し、図版、コードブロック、ノンブルの番号の書式 | `n`、`1`、`2`、`chapter`（今のとおり） | `arabic`（今のとおり） |
| 柱の書式 | なし | なし |

見出しの番号の書式の `{n:kanji}` は、新しい規則の一つの場合になる。
見出しの番号の書式でも、`{n:circled}` や `{chapter:upper-roman}` を書ける。

### 今の書き方の移行（golem-project）

`{{` と `}}`、`[lists]` の一字の見本の差し込みは、docs/diagnostics.md の「廃止予定の手順」に従って廃止する（「メンテナーが決めること」の 12 と 13）。
この ADR では、今の書き方を今と同じ意味に読み、廃止予定の notice を出す。
エラーにするのは、notice を出す minor のバージョンを一つ以上リリースした後の、次の ADR である。

| 書き方 | 読み方 | notice |
| --- | --- | --- |
| `[lists]` の `numbers` の `{{` と `}}` | `{` と `}` | G03114 |
| `[lists]` の `numbers` の `{1}`、`{一}`、`{①}`、`{a}`、`{A}`、`{i}`、`{I}`、`{イ}`、`{ア}` | `{n:arabic}`、`{n:kanji}`、`{n:circled}`、`{n:lower-alpha}`、`{n:upper-alpha}`、`{n:lower-roman}`、`{n:upper-roman}`、`{n:iroha}`、`{n:aiueo}` | G03115 |
| 柱の書式の `{{` と `}}` | `{` と `}` | G03116 |

- メッセージは、表の下のコードブロックのとおりとする。
- 三つとも重大度は notice とし、位置はその値とし、`Golem.Syntax.Diagnostic.noticeCodes` に加える。直す場所と書き換え先が違うので、コードを分ける。
- `[notes]` の `mark-format` は、今 `{{` を特別に読まない（`{{n}}` は `{3}` になる）。新しい読み方では `{{` を誤りとし、notice を出さない。`{{` を書いた書式が今と違う印になることを、黙って許さないためである。
- 見出し、図版、コードブロック、ノンブルの番号の書式には、今 `{{` がない。新しい読み方で、対応のない `}` と `\` が誤り（G03006）になる。今の仕様書は、これらを文字として書けるとは書いていない。
- `[lists]` の書式の誤りは今のとおり G03022、柱の書式の誤りは今のとおり G03014、ほかの書式の誤りは今のとおり G03006 とする。

```text
G03114: [lists] の numbers の {{ と }} は廃止予定です。\{ と \} と書きます: <書式>
G03115: [lists] の numbers の {<見本>} は廃止予定です。{n:<名前>} と書きます: <書式>
G03116: 柱の書式の {{ と }} は廃止予定です。\{ と \} と書きます: <書式>
```

### 設定（golem-project）

`[notes]` に `mark-style` と `body-mark-style` を加え、`mark-format` を新しい書式の読み方で読む（「メンテナーが決めること」の 1、2、10）。

```toml
[character-styles.note-mark]
font = "gothic"
size = "0.65zw"
color = "accent"

[notes]
mark-format = '（{n:kanji}）'
mark-style = "note-mark"
body-mark-style = "strong"
```

| キー | 型 | 意味 |
| --- | --- | --- |
| `mark-format` | 文字列 | PDF の本文の印と注の本文の先頭の印の書式。数の差し込みをちょうど一つ含む。既定は `"*{n}"` |
| `mark-style` | 文字列 | PDF の本文の印（合印）に当てる文字スタイルの名前。既定は組み込みの `note-mark` |
| `body-mark-style` | 文字列 | PDF の注の本文の先頭の印に当てる文字スタイルの名前。既定はなし（注の本文の文字のまま） |
| `mark-size` | 寸法 | 廃止予定。下の「`mark-size` の移行」 |

- 組み込みの文字スタイルに `note-mark`（`size = "0.5zw"`）を加える。今の `mark-size` の既定（`"0.5zw"`）と同じ大きさである。利用者が `[character-styles.note-mark]` を書くと、ほかの組み込みと同じく、書いたキーだけが上書きされる。
- `mark-style` と `body-mark-style` の文字スタイルは、すべてのキーを当てる（「メンテナーが決めること」の 2）。ふつうの文字スタイルと同じ規則で、`based-on` をたどった結果のキーを使う。
- 文字スタイルの `size` の `zw` は、ふつうの文字スタイルと同じく外側の文字の大きさで数える。本文の印では印の位置の文字、注の本文の先頭の印では注の本文の文字が外側である。
- `mark-style` と `body-mark-style` の名前が `[character-styles]` にない場合は、正規表現スタイルの `style` と同じく G03013 とする。`style.toml` の `[notes]` は本に一つなので、原稿の `@style-def` の文字スタイルは指せない。
- `mark-format` の数の差し込みは `{n}` か `{n:<表記>}` である。差し込みを含まない書式、二つ以上含む書式、表にない名前、ほかの書式の誤りは、今と同じく G03006 とする。
- `Style` の `stNotesMarkFormat` の型を、読んだ書式（接頭辞、表記、接尾辞）に替える。`stNotesMarkStyle :: Text` と `stNotesBodyMarkStyle :: Maybe Text` を加える。

#### `mark-size` の移行

`mark-size` を廃止予定とする（「メンテナーが決めること」の 10）。
印の大きさは、印の文字スタイルの `size` で決める。

- `mark-size` を書くと、廃止予定の notice G03117 を出す。重大度は notice、位置は `mark-size` の値とし、メッセージは下のコードブロックのとおりとする。
- 廃止までのあいだ、`mark-size` は「本文の印の文字スタイルの `size`」の省略形として読む。`mark-style` を書かない本では、組み込みの `note-mark` の `size` を `mark-size` の値に替えたものとして組む。今の本の印の大きさは変わらない。
- `mark-size` の今の検査（0 より大きく、`zw` では 1 以下）と、絶対の寸法が印の位置の文字の大きさを超えるとその大きさで組む規則は、`mark-size` に限って残す。
- `mark-size` と、`size` を持つ（`based-on` の先を含む）文字スタイルを指す `mark-style` を一緒に書くと、G03006 とする。メッセージは `[notes] の mark-size と、size を持つ mark-style <名前> は一緒に書けません` とする。大きさを決める値が二つあると、どちらかを黙って捨てることになるためである。
- 文字スタイルの `size` には、印の位置の文字より大きい値も書ける。上限で切り詰めることはしない。

```text
G03117: [notes] の mark-size は廃止予定です。[character-styles.note-mark] の size に書きます
```

### 番号を表せない注

番号が書式の表記で表せない注（`note-symbols` の 8 番、`circled` の 51 番など）は、その注の位置でエラーとする（「メンテナーが決めること」の 5）。

- コードは新しい G07102 とする。リストの G07029 とは原因が違う（直すキーが `[notes]` の `mark-format` である）ので、同じコードにしない。
- メッセージは `注の番号 <番号> は、[notes] の mark-format <書式> で表せません` とする。
- PDF、HTML、EPUB、プレーンテキストのどれを組んでも報告し、どれも書かない。同じ入力から同じ diagnostics が出るようにするためである。
- 番号は S1 で決まるので、G07029 と同じく出力の段階で報告する。

### 文字スタイルを当てる（golem-layout、golem-driver）

本文の印には `mark-style` を、注の本文の先頭の印には `body-mark-style` を当てる（「メンテナーが決めること」の 1）。

- golem-layout の `ComposeEnv` に、印の `Look` を作る関数 `ceNoteMarkLook :: Look -> Look` を加える。golem-driver は、文字スタイルを当てる今の関数 `restyle`（[`Fonts.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-driver/src/Golem/Driver/Pdf/Fonts.hs#L397-L422)）でその関数を作る。
- 本文の印の箱は、印の位置の `Look` に `ceNoteMarkLook` を当てた `Look` で組む。印の大きさ `m` は、その `Look` の大きさである。箱の幅を測る関数と描く関数が同じ `Look` を使うことは、今と変わらない。
- 印の中の字は、ふつうの文字と同じく、文字スタイルのカーニング、トラッキング、プロポーショナルメトリクスで送る。仕様書の「注の印にはトラッキングを足さない」を消す。印の最後の字の後のトラッキングは、行末の字と同じく足さない。
- 印は、JLReq の 4.2.3 のとおり、括弧類を含めて一つの箱とし、中で行を分けず、中にアキ量のセットの空きを入れない。
- 横組みの印の位置は、本文の書体の字面の枠の中心 `c_t` と、印の書体の字面の枠の中心 `c_m` を別々に求め、印の字面の枠の上端を本文の字面の枠の上端にそろえる。印の基準線は本文の基準線より `s × (c_t + 1/2) − m × (c_m + 1/2)` 上にある。二つの書体が同じなら、今の `(s − m) × (c + 1/2)` と同じ値になる。
- 文字スタイルの `baseline-shift` は、上で求めた位置からさらにずらす。横組みでは上へ、縦組みでは右へずらす。ふつうの文字と同じである。
- 色、合成の太字と斜体、`code` の `background` と `padding` も、ふつうの文字スタイルと同じ仕組みで描く。
- 注の本文の先頭の印は、印の文字列を `body-mark-style` の文字スタイルの中に置いたものとして、注の本文の行の中で組む。印の後の四分アキは変えない。
- 番号の印の傍注（`marker = "number"`）の箱も、同じ `KindNoteMark` の箱なので、`mark-style` を当てる。書式は今のまま番号だけとし、表記も使わない。

### 縦組みの印（golem-layout、golem-driver）

縦組みの印の向きは、JLReq の 4.2.2 と 4.2.3 に従う（「メンテナーが決めること」の 6）。
本文の印と注の本文の先頭の印は、同じ規則で字を並べる。

- 印の字は、行の方向に並べる。ふつうの縦組みの文字と同じく、和文の字（漢数字、仮名、丸数字、括弧類など）は縦組みの字形（`vert`）で立て、欧文の字は横に倒す。
- 表記が `arabic` の番号は、2 字までを縦中横にする。3 字以上は欧文として横に倒す（「メンテナーが決めること」の 14）。リストの印の `{n}` と同じ規則であり、印を組む関数はリストの `listMarker` と共有する。
- 接頭辞と接尾辞は、ふつうの文字として組む。`（{n}）` の括弧は縦組みの字形になり、`1` は縦中横になる。JLReq の 4.2.2 が挙げる縦組みの形である。
- 本文の印は、字の列の右端を本文の字面の枠の右端（行の中心線から `s/2` 右）にそろえる。字の列の中心線は、行の中心線から `(s − m)/2` 右にある。JLReq の 4.2.3 の「行の右端にそろえて配置」である。
- 本文の印の箱の行の方向の長さは、印の字を大きさ `m` で縦組みに並べた送りの和（縦中横は `m`）にトラッキングを足した値とする。
- 字の列の幅は `m` なので、`m` が `s` 以下なら、[golem-driver ADR 0018](../golem-driver/adr/0018-footnote-marks-and-numbers.md) が書いた「印が行の外にはみ出す」ことは起きない。文字スタイルで `m` を `s` より大きくすると、印は行の外にはみ出す。仕様書の該当の記述は、条件を「印の大きさが本文の文字の大きさを超えると」に改める。
- 縦組みの今の本は、横書きの向きで並べていた印が縦に並ぶので、PDF が変わる。

### HTML、EPUB、プレーンテキスト

HTML と EPUB は、本文の参照（`noteref`）と、注の一覧の戻りのリンクの文字を、`mark-format` の表記で書く（「メンテナーが決めること」の 8）。

- 接頭辞と接尾辞は書かない。`mark-format = '（{n:kanji}）'` の 3 番の注は、リンクの文字が `三` になる。
- `{n}` は今と同じ算用数字なので、表記を変えない本の HTML と EPUB は変わらない。
- `mark-style`、`body-mark-style`、`mark-size` は使わない。印の大きさと書体は、今のとおり CSS とリーダーが決める。
- golem-html は golem-project に依存しないので、golem-driver が表記を golem-html の設定（`HtmlConfig`）に渡す。表記の型は golem-doc にあるので、モジュールの依存は増えない。

プレーンテキストは変えない。
[golem-text ADR 0001](../golem-text/adr/0001-plain-text-output.md) が `*1` と `※1` に固定しており、`asterisks` の注を `※***` と書くような形を避けるためである。

### ドキュメント

- docs/specifications.md の「設計原則」の節に、上の「組版の自由」の段落を加える。
- docs/specifications.md の「脚注」の節に、表記の登録表、`mark-style`、`body-mark-style`、`mark-size` の移行、縦組みの印の向き、注の本文の先頭の印の縦中横、HTML と EPUB のリンクの文字を書く。「style.toml」の節の `[notes]` の説明、組み込みの文字スタイルの一覧（`note-mark`）、トラッキングの説明を改める。
- docs/specifications.md の `[lists]` の節と柱の書式の節と番号の書式の説明を、新しい書式の読み方（エスケープ、`{n:<表記>}`）に改め、廃止予定の書き方と notice のコードを書く。
- docs/diagnostics.md に G07102、G03114、G03115、G03116、G03117 の節を足し、notice の表に四つの notice を加える。G03006、G03013、G03014、G03022 の節に、新しい誤りを足す。
- docs/roadmap.md の v0.1.0-rc4 から、「注の印の文字スタイル」と「注の印の数字の表記」を消す。「原則に反する今の箇所」の 2 から 10 を、組版の自由の原則に反する箇所として載せる。G03114、G03115、G03116、G03117 の書き方をエラーにする ADR を、notice を出す minor のバージョンの次に載せる。
- 利用者のマニュアルの `manual/chapters/05-style.gm` の「注と図の設定」の節と `manual/appendices/c-style.gm` の `[notes]` と `[lists]` の節に、`mark-style`、`body-mark-style`、表記の名前、エスケープを加え、`mark-size` を `note-mark` の `size` に書き換える。
- [golem-driver ADR 0025](../golem-driver/adr/0025-note-mark-size-and-format.md) のステータスの行に、「実装しないこと」の数字の表記と文字スタイルをこの ADR で扱ったことを書く。[golem-driver ADR 0018](../golem-driver/adr/0018-footnote-marks-and-numbers.md) のステータスの行に、縦組みの印の向きをこの ADR で変えたことを書く。

## 実装しないこと

- 平字（上下の外枠を 50% にした漢数字）。JLReq の 4.2.2 は例が多いと書くが、向きではなく字形の変形である。字形を行の方向にだけ縮める描き方は [docs/adr/0172](0172-continuous-double-dashes.md) の二倍ダッシュにあるが、印の箱の長さと字の位置の決め方が変わるので、要るときに別の ADR で決める（「メンテナーが決めること」の 16）。
- 印を行間に置く組み方。[golem-driver ADR 0018](../golem-driver/adr/0018-footnote-marks-and-numbers.md) の「実装しないこと」のまま残す。
- 記号の連なりが尽きた後に、記号を重ねる（`**`、`††`）か、算用数字に戻るか、最初に戻ること。
- ページごと、見開きごとに番号を振り直すこと。
- 傍注の番号の印に、`mark-format` の書式と表記を使うこと。
- HTML と EPUB の印に、`mark-style` と `body-mark-style` を CSS で当てること。
- プレーンテキストの印の変更。
- 「原則に反する今の箇所」の 2 から 10 を直すこと。ロードマップに載せる。
- 登録表に、和文と欧文のほかの表記（アラビア・インド数字、デーヴァナーガリー数字、ギリシャ文字、ヘブライ数字など）を加えること。v1.x で加える。
- `[number-text ...]` の `style` に、登録表のほかの名前を書けるようにすること。

## テスト設計

実装の前に書き、失敗することを確かめる。

### 表記の登録表と書式の読み方（`modules/golem-doc/test`）

- 登録表の各行の 1、2、3、12 番と、範囲の端と外の番号の結果。`asterisks` の 1、2、3 番が `*`、`**`、`***`、`note-symbols` の 1 から 7 番が U+002A、U+2020、U+2021、U+00B6、U+00A7、U+2016、U+0023 であり、0 番と 8 番は表せない。
- 今のリストの差し込みと同じ規則の行が、今の `formatListNumber` と同じ結果を返す（1 から 200 と範囲の端で比べる）。
- 登録表の名前がすべて違い、英小文字、数字、`-` だけからなる。
- 書式の読み方：`\{`、`\}`、`\\` が文字になり、`'\{{n}\}'` の接頭辞が `{`、接尾辞が `}` である。`\a`、末尾の `\`、閉じていない `{`、対応のない `}`、表にない名前、差し込みのない書式、二つの差し込みが誤りになる。
- 渡す差し込みの表が違えば、同じ文字列でも読める差し込みが違う（`{chapter}` は番号の書式でだけ読める）。

### style.toml（`modules/golem-project/test/Main.hs`）

- `[notes]` がないとき、`mark-format` の既定が `*` と `{n}`（`arabic`）の書式であり、`mark-style` が `note-mark`、`body-mark-style` が `Nothing` である。
- `mark-format` の `"{n}"`、`'（{n:kanji}）'`、`"{n:circled}"`、`"{n:asterisks}"`、`"{n:note-symbols}"`、`'\{{n}\}'` を読める。
- `mark-format` の `"注"`、`"{n}-{n}"`、`"{x}"`、`"{n:x}"`、`"{n}{x}"`、`"{n"`、`"{{n}}"`、`'{n}\'` が G03006 になる。
- `mark-style` と `body-mark-style` に、`size`、`baseline-shift`、`tracking` を持つ文字スタイルと、組み込みの `code` を書いても誤りにならない。
- `mark-style` か `body-mark-style` が存在しない文字スタイルを指すと G03013 になる。
- `mark-size` を書くと G03117 になり、組み込みの `note-mark` の大きさがその値になる。`mark-size` と、`based-on` の先で `size` を持つ文字スタイルを指す `mark-style` を一緒に書くと G03006 になる。
- `[lists]` の `numbers` の `"{{{n}}}"` が今と同じ書式になり G03114 を出す。`"{一}"` が `{n:kanji}` と同じ書式になり G03115 を出す。`'\{{n:kanji}\}'` は notice を出さない。
- `[lists]` の `numbers` に `"{n:asterisks}"` を書ける。
- 柱の書式の `"{{x}}"` が今と同じ値になり G03116 を出す。`'\{x\}'` は notice を出さない。
- 見出しの番号の書式の `"第{n:kanji}章"` が今と同じに読め、`"{chapter:upper-roman}"` を読める。対応のない `}` が G03006 になる。

### 箱（`modules/golem-layout/test/Main.hs`）

測る関数には、テストの中で固定の値を返す関数を使う。

- `mark-format = '（{n:kanji}）'` の 3 番の注で、印の箱の文字列が `（三）` である。
- `ceNoteMarkLook` で書体と大きさを替えると、横組みの印の箱の幅が、替えた書体と大きさで測った値になる。トラッキングを持つ文字スタイルでは、最後の字の後を除いてトラッキングが足される。
- 縦組みで `（{n}）` の 12 番の印が、縦組みの括弧、縦中横の `12`、縦組みの括弧の順に並び、箱の長さが三つの送りの和である。123 番の `123` は横に倒した欧文になる。
- 縦組みの注の本文の先頭の印で、`{n}` の 12 番が縦中横の箱になり、123 番が横に倒した欧文の箱になる。
- 番号の印の傍注の箱の文字列が、`mark-format` によらず番号だけである。

### PDF（`modules/golem-driver/test/Main.hs`）

- 本文の書体と違う書体を `mark-style` で当てた横組みの印で、印の基準線が本文の基準線より `s × (c_t + 1/2) − m × (c_m + 1/2)` 上にあり、印の字形がその書体のフォントで描かれる。`baseline-shift` を持つ文字スタイルでは、その量だけさらに上にある。
- `mark-style` の `color` のスウォッチで本文の印が、`body-mark-style` の `color` で注の本文の先頭の印が描かれる。
- 縦組みで `（{n:kanji}）` の書式の印の字形が縦組みの字形で描かれ、字の列の右端が行の中心線から `s/2` 右にある。
- `note-symbols` の書式で 8 番めの注があると G07102 が出て、PDF を書かない。HTML、EPUB、プレーンテキストを組んでも同じエラーが出る。
- `mark-format`、`mark-style`、`body-mark-style`、`mark-size` を書かない横組みの本は、PDF のページの内容のストリームが今と同じである。今の PDF のテストがそのまま通ることで確かめる。`mark-size` だけを書いた横組みの本も、PDF が今と同じである。
- 二つのマニュアルを組み、diagnostics が出ない。

### HTML と EPUB（`modules/golem-html/test`）

- `mark-format = '（{n:kanji}）'` の本で、`noteref` と注の一覧の戻りのリンクの文字が `三` である。
- 既定の書式の本で、リンクの文字が今と同じ `3` である。

### 自動テストにしない確かめ方

- 蟹工船の fixture の写しに注を足し、`{n}`、`（{n}）`、`（{n:kanji}）` の書式で組んで画像にする。本文の印が行の方向に並び、`（1）` の括弧が縦組みの字形で `1` が縦中横になり、印の右端が行の右端にそろい、隣の行と重ならないことを目で確かめる。
- 二つのマニュアルの写しに `mark-style` を書いて組み、横組みの印の上端が本文の字面の上端にそろうことを目で確かめる。

## トレードオフ

組版の自由の原則に従い、印の文字スタイルにはすべてのキーを当てる。
印の位置は、文字スタイルを当てた結果の大きさと書体から求めるので、位置の式は二つの書体の値を持つ。
大きさを決める値が `mark-size` と文字スタイルの `size` の二つになる期間は、廃止予定の notice を出す期間に限る。
その期間は二つを一緒に書くことを誤りとし、どちらが勝つかの規則を作らない。

本文の印と注の本文の先頭の印に、別々の文字スタイルを当てる。
文字スタイルが大きさを持てるので、一つの文字スタイルを両方に当てると、上付きの小さい印に合わせた大きさが注の本文の先頭の印にも当たる。
二つの印の書体と色をそろえたい本は、二つのキーに同じ文字スタイルを書くか、大きさだけを変えた文字スタイルを `based-on` で作る。

数字の表記を登録表から名前で選ぶので、`[lists]` の今の一字の見本の差し込みと、見出しの番号の書式の `{1}` との食い違いがなくなる。
その代わり、`'（{n:kanji}）'` は `（{一}）` より長く、和文の書き手には見本のほうが読みやすい。
名前は、`[number-text ...]` と `[numbers]` がすでに使う `kanji` と `kanji-digits` にそろえた。
CSS Counter Styles の名前（`japanese-informal` など）には合わせない。
CSS の `japanese-informal` は 0 を `零` と書き、9999 までしか表せないので、Golem の `kanji`（0 を `〇`、`京` の位まで）と規則が違う。
規則の違う表記に同じ名前を付けると、HTML と PDF で同じ名前が違う字になる。

書式の括弧そのものをエスケープで書くので、`{{` という書式だけの例外がなくなる。
その代わり、`style.toml` の基本の文字列では `\` を `\\` と書く必要があり、リテラル文字列を勧めることになる。
`[lists]` と柱の書式の `{{` は、廃止予定の手順に従って当面は読むので、今の本は組める。
`mark-format` の `{{` は、今は特別な意味がなく、新しい読み方で誤りになる。
見出しなどの番号の書式の、対応のない `}` と `\` も誤りになる。
どちらも、今の仕様書が意味を書いていない書き方である。

`mark-format` の `{n}` を算用数字のまま残すので、リストの `{n}`（本の数の表記）と意味が食い違う。
`{n}` をリストに合わせると、縦組みの本の注の印が、書式を変えていないのに漢数字に変わる。
[golem-driver ADR 0025](../golem-driver/adr/0025-note-mark-size-and-format.md) のメンテナーは `mark-format` の意味を変えないと決めたので、食い違いを仕様書に書いて残す。

記号の連なりは七つで尽き、八つめの注はエラーになる。
Golem はページごとに番号を振り直さないので、章ごとに振り直す本でも `note-symbols` を使える場面は少ない。

縦組みの本文の印を JLReq に合わせて行の方向に並べるので、注を持つ縦組みの本の PDF は、キーを書き換えなくても変わる。
既定の `*{n}` の印は、`*` が欧文として横に倒れ、`1` が縦中横になる。
今の横書きの向きの印より、行の方向に長くなる。
縦組みの注の本文の先頭の算用数字も縦中横になる。
見た目の回帰テストに縦組みの注を含む参照があれば、更新が要る（あるかどうかは確かめていない）。

HTML と EPUB のリンクの文字に表記だけを使うので、PDF の印（`（三）`）と HTML の印（`三`）は同じではない。
番号の表記は同じなので、読み手が注を取り違えることは少ないと考える（推測である）。
プレーンテキストの印は算用数字のままなので、`note-symbols` の本では PDF とプレーンテキストの印がまったく違う。

## 決めたことの記録

- **ロードマップの項目**：docs/roadmap.md の v0.1.0-rc4 の「注の印の文字スタイル」と「注の印の数字の表記」を、この ADR で扱う。
- **`mark-style` を加える版**（[golem-driver ADR 0025](../golem-driver/adr/0025-note-mark-size-and-format.md)、メンテナー）：注の印の文字スタイルは、`[notes]` の `mark-style` として v0.1.0-rc4 で加える。`mark-size` と `mark-format` は、`mark-style` を加えた後も意味を変えない。
- **組版の自由の原則**（2026-11-07、メンテナー）：この ADR に限らず、すべての文字に段落スタイルや文字スタイルを当てられるべきであり、組版の自由を制限してはいけない。これを設計原則に加える。
- **印の文字スタイルのキー**（2026-11-07、メンテナー）：「メンテナーが決めること」の 2 の推奨（`font`、`color`、合成の太字と斜体だけを当て、ほかを G03006 とする案）を退けた。文字スタイルの特殊化は避けなければならない。実装の量と仕様が爆発し、利用者の自由な組版を破るからである。
- **書式の括弧**（2026-11-07、メンテナー）：`{{` は例外を生むので、括弧そのものはエスケープで書くことに統一する。
- **数字の表記**（2026-11-07、メンテナー）：数字の表記は v1.x で和文と欧文のほかにも対応するので、決め打ちにしない。
- **連なりが尽きたとき**（2026-11-07、メンテナー）：推奨のとおり、表せない番号の注はエラーとする。
- **縦組みの印の向き**（2026-11-07、メンテナー）：JLReq に従う。JLReq から外れるほどの理由がない。
- **縦組みの注の本文の先頭の算用数字、HTML と EPUB**（2026-11-07、メンテナー）：推奨のとおりとした。縦組みの注の本文の先頭の算用数字は縦中横にし、HTML と EPUB は表記だけを書き、プレーンテキストは変えない。
- **ほかの項目**（2026-11-07、メンテナー）：問題ないとした。「メンテナーが決めること」の 1、4、9 から 16 を推奨のとおりとした。
- **影響の大きい点**（2026-11-07、メンテナー）：注のある縦組みの本の PDF がすべて変わることは問題ない。正しい設計のために受け入れる。同じ日に、[ADR 0183](0183-tagged-pdf-and-pdf-a.md) のタグ付けの大きな変更、[ADR 0173](0173-rc4-refactoring.md) の多くの `build-depends` の変更、実装の順（[ADR 0189](0189-paragraph-alignment-spacing-and-end-indent.md) を [ADR 0180](0180-verse-spacing-and-stanza-breaks.md) の前に、[ADR 0183](0183-tagged-pdf-and-pdf-a.md) を [ADR 0187](0187-inline-language-switch.md) と [ADR 0188](0188-headings-beyond-level-3.md) の前に）も、同じ理由で受け入れた。

## メンテナーが決めること

すべて決めた（「決めたことの記録」）。

1. **文字スタイルを当てる印**：決めた。本文の印に `mark-style` を、注の本文の先頭の印に `body-mark-style` を当てる。草稿の推奨（一つの `mark-style` を両方に当てる）は、2 の決定で文字スタイルが大きさを持てるようになったので改めた。
   - 一つの `mark-style` を両方に当てる案は採らない。上付きの小さい印の大きさが、注の本文の先頭の印にも当たる。大きさだけを当てない規則を作れば、2 で退けた文字スタイルの特殊化になる。
   - 本文の印だけに当て、注の本文の先頭の印には当てない案は採らない。注の本文の先頭の印に文字スタイルを当てる手段がなくなり、組版の自由の原則に反する。
   - キーの名前は `body-mark-style` とする。仕様書は「注の本文の先頭の印」と呼ぶので、「本文」の語が本の本文と紛れるおそれはある。
2. **文字スタイルで当てるキー**：決めた。すべてのキーを当てる。
3. **数字の表記の書き方**：決めた。表記を決め打ちにせず、一つの登録表から名前で選ぶ。表記を足すときは表に行を足すだけにする。名前の付け方は 9 で決める。
4. **記号の連なりの文字**：決めた。`asterisks` を U+002A の繰り返しとし、`note-symbols` を JLReq の 4.2.2 の順の七つ（U+002A、U+2020、U+2021、U+00B6、U+00A7、U+2016、U+0023）とする。登録表の行なので、リストの書式でも使える。草稿の推奨（注だけの差し込みにする）は、登録表を一つにする 3 の決定に合わせて改めた。
   - 全角のアステリスク（U+FF0A）と全角の番号記号（U+FF03）を使う案は採らない。JLReq の英語版の文字名は ASTERISK と NUMBER SIGN であり、既定の `*{n}` の `*` も U+002A である。全角の字が要る本は、v1.x で登録表に行を足せる。
   - 注の書式だけで使える行にする案は採らない。書式ごとに使える行を分けると、表記の特殊化になる。
5. **連なりが尽きたとき**：決めた。表せない番号の注を G07102 のエラーとし、どのターゲットも書かない。
6. **縦組みの本文の印の向き**：決めた。JLReq に従い、印の字を行の方向に並べ、括弧類を縦組みの字形にし、算用数字を縦中横にする。
7. **縦組みの注の本文の先頭の算用数字**：決めた。2 字までを縦中横にする。
8. **HTML と EPUB の印**：決めた。リンクの文字を表記で書き、接頭辞、接尾辞、大きさ、文字スタイルは使わない。プレーンテキストは変えない。
9. **表記の名前と差し込みの形**：決めた。差し込みを `{<数>:<表記>}` とし、表記の名前を英小文字、数字、`-` からなる語（`arabic`、`kanji`、`kanji-digits`、`circled`、`lower-alpha`、`upper-alpha`、`lower-roman`、`upper-roman`、`iroha`、`aiueo`、`asterisks`、`note-symbols`）とする。`mark-format` の `{n}` は今のとおり `arabic` とする。
   - 見出しの番号の書式がすでに `{n:kanji}` の形を持ち、`kanji` と `kanji-digits` は `[number-text ...]` と `[numbers]` の語である。新しい形を作らずに、今ある形を広げられる。
   - 一字の見本（`{一}`、`{①}`）で選ぶ今のリストの形は採らない。和文と欧文のほかの表記を足すと、見本の字が決めにくく（ギリシャ文字の `α` とラテン文字の `a`、ローマ数字の `i` とラテン文字の `i`）、`{1}` は見出しの番号の書式の第 1 階層と食い違う。
   - CSS Counter Styles の名前に合わせる案は採らない。CSS の `japanese-informal` は Golem の `kanji` と規則が違う（トレードオフ）。v1.x で加える表記が CSS の表記と同じ規則なら、その表記には CSS の名前を使う（`arabic-indic`、`devanagari`、`lower-greek` など）。
10. **`mark-size` の扱い**：決めた。`mark-size` を廃止予定とし、印の大きさを組み込みの文字スタイル `note-mark` の `size`（既定 `"0.5zw"`）で決める。廃止までのあいだ、`mark-size` は本文の印の文字スタイルの `size` の省略形として読み、`size` を持つ `mark-style` と一緒に書けば G03006 とする。
    - `mark-size` を省略形として残し続ける案は採らない。同じ値を二つのキーで書ける形が続き、文字スタイルの `size` と `mark-size` の関係を仕様書に書き続けることになる。
    - 文字スタイルの `size` が `mark-size` に勝つ案は採らない。書いた `mark-size` が黙って使われない出力を作る。
11. **注の本文の先頭の印の文字スタイルの既定**：決めた。`body-mark-style` の既定をなし（注の本文の文字のまま）とする。今の PDF を変えない。組み込みの文字スタイルを足す案は、キーのない文字スタイルを一つ増やすだけで、組みが変わらない。
12. **エスケープを揃える範囲**：決めた。`[notes]` と `[lists]` のほかに、柱の書式と、見出し、図版、コードブロック、ノンブルの番号の書式も、同じ読み方（バックスラッシュのエスケープと `{<数>:<表記>}`）に揃える。四つの書式を golem-doc の一つの関数で読み、差し込みの表だけを書式ごとに渡す。
    - `[notes]` と `[lists]` だけを揃える案は採らない。柱の書式に `{{` の例外が残り、番号の書式では括弧そのものを書けないまま残る。
    - 柱の `{{` は、`[lists]` と同じく廃止予定の手順に従い、G03116 の notice を出す。
    - 番号の書式の対応のない `}` と `\` は、仕様書が意味を書いていない書き方なので、notice を経ずに G03006 とする。notice を経る案は採らない。もう一つコードが要る。
13. **`[lists]` の一字の見本の差し込み**：決めた。`{1}`、`{一}` などを廃止予定とし、G03115 の notice を出す。9 の名前と見本の二つの書き方を残し続けると、例外が残る。見本を読み続け、廃止しない案は採らない。和文の書き手には見本のほうが読みやすいが、v1.x で足す表記には見本がない。
14. **縦組みの 3 字以上の算用数字**：決めた。3 字以上の算用数字の番号は、欧文として横に倒す。リストの印の `{n}` と `[numbers]` の `auto` が 2 字までを縦中横にしているので、規則を一つにする。JLReq は字数の上限を書いていない。すべての字数を縦中横にする案は、3 字以上を一字の幅に詰めることになり、字が読みにくくなる。
15. **原則に反する今の箇所**：決めた。「原則に反する今の箇所」の 2 から 10 を docs/roadmap.md に載せ、それぞれを別の ADR で直す。どれも、組むものの範囲と既定の見た目を決め直す必要があり、この ADR の注の印とは直す場所が違う。
16. **平字**：決めた。平字は向きではなく字形の変形なので、この ADR では作らず、docs/roadmap.md に載せる。字形を行の方向にだけ縮める描き方は二倍ダッシュ（[docs/adr/0172](0172-continuous-double-dashes.md)）にあるが、印の箱の長さと字の位置の決め方が増える。

## 参考文献

- W3C, *Requirements for Japanese Text Layout*（JLReq）, 4.2.2 Note Numbers 注の番号. https://www.w3.org/TR/jlreq/#note_numbers（2026-11-06 に取得し、2026-11-07 に本文を読み直した。図は見ていない）
- W3C, *Requirements for Japanese Text Layout*（JLReq）, 4.2.3 The Processing of the Reference Mark 合印の処理. https://www.w3.org/TR/jlreq/#the_processing_of_the_reference_mark（同上）
- W3C, *CSS Counter Styles Level 3*, 6 Simple Predefined Counter Styles、7 Complex Predefined Counter Styles. https://www.w3.org/TR/css-counter-styles-3/（2026-11-07 に読んだ。`system` の種類と、`japanese-informal` の範囲が -9999 から 9999 であることを確かめた）
- [golem-driver ADR 0018](../golem-driver/adr/0018-footnote-marks-and-numbers.md)、[golem-driver ADR 0025](../golem-driver/adr/0025-note-mark-size-and-format.md)、[golem-driver ADR 0013](../golem-driver/adr/0013-list-indents.md)、[golem-driver ADR 0010](../golem-driver/adr/0010-caption-style.md)、[golem-driver ADR 0043](../golem-driver/adr/0043-caption-sidenote-do-not-inherit-indent.md)、[golem-layout ADR 0011](../golem-layout/adr/0011-ruby-base-character-styles.md)、[golem-parser ADR 0011](../golem-parser/adr/0011-number-shorthand.md)、[golem-text ADR 0001](../golem-text/adr/0001-plain-text-output.md)、[docs/adr/0172](0172-continuous-double-dashes.md)
