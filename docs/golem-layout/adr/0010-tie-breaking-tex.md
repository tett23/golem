# ADR 0010: 罰点の等しい経路の選び方を、最後の行まで TeX に合わせる

ステータス: 採択

## 文脈

[ADR 0008](0008-explicit-hyphens.md) は、罰点の合計が最小の経路が複数あるとき、各経路の `(位置, 適合度)` を段落の終わりから並べた列を辞書式に比べ、大きいほうを選ぶと決めた。
根拠は TeX の振る舞いである。
tex.web の `try_break` は、ある分割の位置への最良の前任を `d<=minimal_demerits[fit_class]` で置き換えるので、罰点が等しければ、活性ノードの並びで後にある前任が残る。
活性ノードの並びは、位置の順、同じ位置では適合度の分類の番号の順（very loose が先）である。

ただし、段落の終わりで経路を一つに決める比較だけは、TeX は厳密な `<` を使う。
tex.web の「Find an active node with fewest demerits」は、活性ノードの並びを先頭から調べ、`total_demerits(r)<fewest_demerits` のときにだけ最良を置き換える（記憶による。手元に tex.web はない）。
段落の終わりの活性ノードは、「Create new active nodes for the best feasible breaks just found」が適合度の分類の番号の小さい順に作るので、並びでも番号の小さい順になる。
したがって TeX は、段落の終わりで罰点の等しいノードが複数あれば、最後の行の適合度の番号が最も小さいもの（very loose の側）を選ぶ。
[ADR 0008](0008-explicit-hyphens.md) の規則は、列の最初の要素（段落の終わりの位置と最後の行の適合度）でも大きいほうを取るので、最後の行の適合度だけが違う同点では、TeX と逆の経路を選ぶ。

### TeX で確かめたこと

手元の TeX（TeX Live 2026 の `tex`、`~/.local/texlive/2026`）で、次の段落を組んだ。
[ADR 0008](0008-explicit-hyphens.md) の `ties.tex` と同じ前置き（`\parfillskip=0pt plus 1fil`、`\pretolerance=100` など）を使う。

```tex
\setbox1=\vbox{\hsize=100pt \linepenalty=0 \adjdemerits=0
  \tracingparagraphs=1
  \noindent\hbox to 50pt{A\hss}\penalty10000\hskip 0pt plus 10pt minus 10pt\hbox to 50pt{B\hss}\penalty0
  \hbox to 6pt{C\hss}\penalty0
  \hbox to 50pt{D\hss}\penalty10000\hskip 0pt plus 10pt minus 10pt\hbox to 50pt{E\hss}\par}
```

B の後で分ければ、一行目は 100pt ちょうど（不良度 0、decent）で、二行目は 106pt を 6pt 縮める（不良度 22、tight）。
C の後で分ければ、一行目が 106pt を縮める tight の行で、二行目が 100pt ちょうどの decent の行になる。
どちらも罰点の合計は 484 である。
ログは次のとおりで、段落の終わりのノードは、decent の `@@3` が tight の `@@4` より先に作られている。

```text
@\par via @@1 b=22 p=-10000 d=484
@\par via @@2 b=0 p=-10000 d=0
@@3: line 2.2- t=484 -> @@2
@@4: line 2.3- t=484 -> @@1
```

`\showbox` では、一行目が A、B、C で `glue set - 0.6` であり、TeX は `@@3`（C の後で分け、最後の行が decent）を選んだ。
[ADR 0008](0008-explicit-hyphens.md) の規則では、最初の要素が `(終わり, 2)` と `(終わり, 3)` なので、`@@4`（B の後で分け、最後の行が tight）を選ぶ。
`\parfillskip=0pt` でも同じ結果になった。

### InDesign の同点の扱い

ユーザーの方針は、資料が見つかれば InDesign の挙動を優先することである。
InDesign の段落コンポーザー（Adobe 段落コンポーザー、日本語段落コンポーザー）について、次の資料を調べた。

- 米国特許 US6510441B1「Optimal line break determination」（Adobe、優先日 1998-12-11、https://patents.google.com/patent/US6510441B1/en ）。発明者の表記は Eric A. Kenninga である。InDesign の段落の組版の担当者として知られる Eric Menninga の誤記と考えられるが、確かめていない。分割の候補をノードとするグラフを決まった行数（例では 6 行）まで作り、罰点の累計が最小の経路の最初の分割を確定して、窓を一行ずつ進める方式を述べている。罰点の式は、不良度と行の調整の比、ハイフンの品質、連続するハイフン、最後の行の長さ、隣の行との詰まり具合の差の項から成る。罰点の等しい経路の扱い、比較が厳密かどうかは書かれていない。
- 米国特許出願 US20070186155A1「Automated Paragraph Layout」（Adobe、発明者 David E. Williamson と Eric Menninga、https://patents.google.com/patent/US20070186155 ）。段落全体の罰点を最小にする動的計画法を述べ、擬似コードには `<=` の比較（等しければ後に調べた候補を残す）と `<` の比較が混ざる。同点の規則として述べた文はなく、InDesign で使われているとも書かれていない。本文の終わりの 3 割ほどは読んでいない。
- InCopy のヘルプ「Composing CJK characters」（検索エンジンの要約）：日本語段落コンポーザーは、段落コンポーザーと同じく段落を単位に分割を評価し、段落の中を編集するとその前の行の文字組みも変わりうる。罰点の式と同点の扱いには触れていない。
- InDesign のヘルプの段落コンポーザーの説明（検索エンジンの要約）：分割の候補を洗い出し、字間、語間、ハイフンの均等さに基づく重みを付けて評価する。同点の扱いには触れていない。helpx.adobe.com のページは、取得を試みたが応答が 403 で、本文を読めなかった。
- Adobe の技術者による W3C の日本語組版の議論（https://lists.w3.org/Archives/Public/public-i18n-japanese/2023JulSep/0177.html ）：フレームグリッドの話であり、行分割には触れていない。
- CreativePro の記事「The Great Paragraph Composer Paradox」は、取得の応答が 403 で読めなかった。

InDesign の段落コンポーザーが罰点の等しい経路をどう選ぶかを述べた資料は見つからなかった。
US6510441B1 が InDesign の実装であるとすれば、InDesign は段落全体ではなく数行の窓の中で最小を取り、罰点の式も TeX と異なる。
そうであれば、同点の規則だけを InDesign に合わせても、同じ入力で InDesign と同じ分割にはならない。
同点の規則を InDesign に合わせる根拠は、資料からも、一致の効果の面からも得られない。

## 実装すること

### 罰点の等しい経路の選び方

[ADR 0008](0008-explicit-hyphens.md) の規則を、次の規則に置き換える。

> 罰点の合計が最小の経路が複数あるときは、まず段落の最後の行の適合度の番号が小さいもの（very loose の側）を選ぶ。それでも複数あれば、各経路の `(位置, 適合度)` を最後から二つ目の分割から段落の始まりへ並べた列を辞書式に比べ、大きいほうを選ぶ。

最後の分割の位置はどの経路でも段落の終わりなので、比べるのは最後の行の適合度だけである。
二つ目以降の要素の比較は [ADR 0008](0008-explicit-hyphens.md) のままであり、TeX が途中の分割で `<=` によって後の前任を残すことに当たる。

`Golem.Layout.KnuthPlass` の `run` の `key` を次のように変える。

```haskell
key a = case walk a of
  x : rest -> (Down (nFit x), [(nPos y, nFit y) | y <- rest])
  [] -> (Down 0, [])
```

`maximumBy (comparing key)` はそのまま使う。
`Data.Ord` から `Down` を取り込む。
`step` の `Map.insertWith` の `<=` は変えない。

### 参照のデータ

`modules/golem-layout/test/data/knuth-plass/ties.tex` に、「TeX で確かめたこと」の段落を三つ目（`GOLEM-TIE=3`）として加え、[ADR 0008](0008-explicit-hyphens.md) の README の手順で `ties.log` を作り直す。
README の `ties.tex` の節に、三つ目の段落の説明と TeX が選んだ経路（C の後で分け、罰点の合計 484）を加える。
`ties.tex` と `ties.log` はテストのデータであり、ADR と違って変更してよい。

### 参照テスト（[ADR 0007](0007-knuth-plass-reference-test.md)）への影響

[ADR 0007](0007-knuth-plass-reference-test.md) の参照テスト（`frog-king.tex`）の期待値は変わらない。
[ADR 0008](0008-explicit-hyphens.md) の「TeX で確かめたこと」のとおり、`frog-king` の段落で罰点の等しい経路が現れるのは `Overfull \hbox` の出る 210pt だけであり、210pt は参照のデータに含めていない。
同点のない段落では、選び方の規則は結果に影響しない。

行長の変わる段落（`\parshape` に当たる L*(i)）で TeX と一致しない場合があることは、[ADR 0008](0008-explicit-hyphens.md) のトレードオフのとおり変わらない。

### ドキュメント

- 仕様書の「行分割」の節の、罰点の等しい経路の選び方の文を、この ADR の規則に直す。
- [ADR 0008](0008-explicit-hyphens.md) のステータスを「採択→罰点の等しい経路の選び方は [ADR 0010](0010-tie-breaking-tex.md)」に変える。

## 実装しないこと

- InDesign の段落コンポーザーの同点の規則に合わせること。資料が見つからなかった。資料が見つかれば、新しい ADR で決め直す。
- InDesign の段落コンポーザーの窓の方式と罰点の式（連続するハイフンの梯子、最後の行の長さ、隣の行との詰まり具合の差）の再現。
- 行長の変わる段落での TeX との同点の一致。

## テスト設計

`modules/golem-layout/test/Main.hs` に加える。
実装の前に書き、失敗することを確かめる。

- 「TeX で確かめたこと」の段落を、`pLinePenalty = 0`、`pAdjDemerits = 0`、行長 100 で組む。並びは `[box 50, Penalty 0 infPenalty NoHyphen, Glue 0 10 10, box 50, Penalty 0 0 NoHyphen, box 6, Penalty 0 0 NoHyphen, box 50, Penalty 0 infPenalty NoHyphen, Glue 0 10 10, box 50] <> finish` とする。`brPositions` が `[6, length items - 1]`、`brDemerits` が 484、`brPass` が 1、最後の行の適合度が decent（2）である。今の実装は `[4, length items - 1]` を返すので失敗する。
- [ADR 0008](0008-explicit-hyphens.md) の三つの同点のテスト（「the later break wins」「four lines over three」「fitness counts in the comparison from the end」）が、そのまま通る。
- 総当たりの `bruteBest` の比較を、最後の行の適合度の小さいものを先に取り、残りを終わりからの辞書式で最大のものを取る形に直す。総当たりのプロパティテスト二つ（「the result has the least total demerits of all break sequences」「of the least-demerit break sequences, the one greatest from the end is chosen」）は、直した `bruteBest` で通る。後者の名前を、規則に合わせて直す。
- 参照テスト（`modules/golem-layout/test/KnuthPlassReference.hs`）の期待値が変わらずに通る。

## トレードオフ

TeX に合わせると、比較の規則が「最後の要素だけ向きが逆」という非対称な形になる。
今の規則のままにすれば規則は一様だが、TeX の結果を期待値にする参照のテストの方針（[ADR 0007](0007-knuth-plass-reference-test.md)）と、[ADR 0008](0008-explicit-hyphens.md) が同点の規則を TeX に合わせた理由に反する。
InDesign の挙動が分からない以上、出所を説明できる TeX の規則に合わせる。

この変更で選ぶ経路が変わるのは、罰点の合計が完全に等しく、最後の行の適合度だけが違う段落に限られる。
最後の行は段落の終わりの無限の伸びを持つので、伸ばす側では常に decent になり、違いが出るのは最後の行を縮める経路と縮めない経路が同点になる場合だけである。
既存の PDF の出力が変わる段落は、ほとんどないと考える。
