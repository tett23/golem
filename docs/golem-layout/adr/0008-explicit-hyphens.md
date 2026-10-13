# ADR 0008: 明示のハイフンでの行分割と、罰点の等しい候補の選び方

ステータス: 採択→罰点の等しい経路の選び方は [ADR 0010](0010-tie-breaking-tex.md)

## 文脈

欧文の語に書かれたハイフン（lime-tree の `-`）は、TeX では一回目の段階から分割の候補になる。
TeX は、フォントの `\hyphenchar` に当たる文字を入力から読むと、その直後に空の分割の候補（前に何も足さない discretionary）を置き、罰則を `\exhyphenpenalty`（plain TeX では 50）とする。
en ダッシュ（`--`）と em ダッシュ（`---`）も、入力の最後の文字が `-` なので、同じ候補になる。

Golem は、この候補を作っていない。
今の組み方は、`Golem.Layout.Japanese` の `textPieces` が欧文の文字の連なりを一つの語（`PWord`）にまとめ、`wordItems` がその語に Liang のパターンを当てる。
ハイフンは語の中の一文字として扱われ、ハイフンの後ろは分割の候補にならない。
仕様書の「今後の実装項目」（[specifications.md](../../specifications.md)）も、これを残っている項目に挙げている。
加えて、`breakParagraph` は一回目の段階でフラグの付いた罰則をすべて除くので、仮に明示のハイフンをフラグ付きの罰則にしても、一回目の段階では使われない。
[ADR 0007](0007-knuth-plass-reference-test.md) の参照テストが `\exhyphenpenalty=10000` で比べているのは、この差のためである。

今の実装を調べると、明示のハイフンを含む語には、次の三つの不具合もある。
いずれも、同梱の `hyph-en-us` のパターンをハイフンを含む語にそのまま当てることと、文字の分類から起こる。

- `well-known` には、パターンが `well-` の直後に候補を作る。この候補で分けると、罰則の幅のハイフンが行末に描かれ、行末が `well--` になる。パターンはハイフンを文字として読み、`.well-known.` の部分列に一致した値をそのまま使うためである。
- `self-evident` には `self-ev` と `self-evi` の位置に候補ができ、複合語の後半が分けられる。
- U+2010（HYPHEN）と U+2013（en ダッシュ）は、文字の分類で JLReq の cl-03（ハイフン類）になり、欧文の文字（`Western`）にならない。そのため欧文の中の `lime‐tree` や `1990–2000` は語が二つに分かれ、ダッシュと後ろの語の間に和欧間の四分の空きが入る。

調べる途中で、TeX と結果が異なりうる点がもう二つ見つかった。

- 罰点の合計が等しい経路が複数あるとき、Golem は前の位置の候補を選び、TeX は後の位置の候補を選ぶ。tex.web の `try_break` は、活性ノードの並び（位置の順）を調べながら `d<=minimal_demerits` で最良の候補を置き換えるので、等しいときは後から調べた候補が残る。[ADR 0001](0001-knuth-plass-line-breaking.md) は前の位置を選ぶと定め、[ADR 0007](0007-knuth-plass-reference-test.md) はこの差が出た `\hsize` をデータから除くと定めた。
- 行の罰点で、TeX は `\linepenalty` と不良度の和が 10000 以上になると、その二乗の代わりに 100000000 を使う（tex.web の `if abs(d)>=10000 then d:=100000000`）。Golem の `lineDemerits` はこの打ち切りをせず、常に二乗する。

手元の TeX（TeX Live 2026 の `tex`、`~/.local/texlive/2026`）で、この二つと明示のハイフンの振る舞いを確かめた。
結果は「TeX で確かめたこと」の節に書く。

## 実装すること

### 明示のハイフンの候補

欧文の語の中のハイフンとダッシュの直後を、分割の候補にする。
対象の文字は次の四つとする。

| 文字 | 名前 | 分割の候補 |
|---|---|---|
| U+002D | HYPHEN-MINUS | 直後 |
| U+2010 | HYPHEN | 直後 |
| U+2013 | EN DASH | 直後 |
| U+2014 | EM DASH | 直後 |
| U+2011 | NON-BREAKING HYPHEN | 作らない |

- 候補を置くのは、語の中でこれらの文字（の連なり）の前に一文字以上あり、後ろにも一文字以上ある場合だけとする。語の先頭の `-5` や、語の終わりの `pre-` には置かない。語の終わりは、もともと語間の空きで分けられる。
- 同じ文字が続く場合（`a--b`）は、連なりの最後の文字の直後にだけ置く。
- 候補の罰則は `Penalty 0 p ExplicitHyphen` とする。幅は 0 であり、分けたときに新たなハイフンを足さない。行末に残るのは、語に書かれたハイフンそのものである。
- `p` は `style.toml` の `[composition]` の `explicit-hyphen-penalty` で決め、既定値は 50（TeX の `\exhyphenpenalty` の plain TeX の値）とする。10000 以上なら候補を置かず、語を一つの箱のままにする。
- TeX と同じく、明示のハイフンで分けた行が続く場合は `pDoubleHyphenDemerits` を加える。TeX は明示のハイフンの分割もハイフンによる分割（`hyphenated`）として扱うためである。

### 文字の分類と語のまとめ方

`Golem.Layout.Japanese` を次のように直す。

- `textPieces` の `isJoiner` に U+2010、U+2011、U+2013 を加える。今の `isJoiner` は引用符と em ダッシュを、どちらかの側の最も近い文字が欧文の文字なら語に含める。これと同じ規則で、欧文に挟まれたハイフンと en ダッシュを語に含める。和文に挟まれた U+2010 と U+2013 は、今と同じく cl-03 の一文字として組み、行頭禁則を保つ。
- `charClass` で U+2011 を `Hyphen` に分類する。今は `Ideograph` に落ちる。

和文の中のハイフン類（U+2010、U+301C、U+30A0、U+2013 と、和文に挟まれた U+002D）は、今の扱いを変えない。
JLReq はハイフン類を行頭禁則の文字としており、その後ろでの分割は和文の字間の分割と同じく罰則を付けない。

### パターンによるハイフネーションとの関係

`wordItems` は、語をまず明示のハイフンの位置で部分に分ける。
明示のハイフンを含む語には、Liang のパターンを当てない。

TeX も、明示のハイフンを含む語をハイフネーションしない。
tex.web の `hyphenate` の前の検査は、語の後ろに discretionary があるとハイフネーションをやめるためである。
これで、`well--` と `self-evi-dent` の不具合はなくなる。

部分ごとの箱の幅は、部分ごとに `ceWordAdvance` で測る。
ハイフンとその後ろの文字の間のカーニングは失われるが、パターンで分けた部分も今は同じ測り方をしている。

### 罰則の種類

`Golem.Layout.KnuthPlass` の `Item` の `Penalty` のフラグを、真偽値から種類に変える。

```haskell
data Hyphen
  = NoHyphen       -- 禁則、モノルビの間、行の終わりなど
  | PatternHyphen  -- Liang のパターンによる候補。分けると行末にハイフンを描く
  | ExplicitHyphen -- 明示のハイフンの直後。幅は 0
  deriving stock (Eq, Show)

data Item
  = Box     { itemWidth :: !Sp, itemContent :: !BoxContent }
  | Glue    { itemWidth :: !Sp, itemStretch :: !Sp, itemShrink :: !Sp }
  | Penalty { itemWidth :: !Sp, itemPenalty :: !Int, itemHyphen :: !Hyphen }

itemFlagged :: Item -> Bool  -- PatternHyphen と ExplicitHyphen で真
```

- `breakParagraph` の一回目の段階は、`PatternHyphen` の罰則だけを候補から除く。`ExplicitHyphen` は一回目から候補にする。TeX の一回目の段階が、ハイフネーションをせず、入力にある discretionary を使うことに合わせる。
- 連続するハイフンの罰点（`pDoubleHyphenDemerits`）は、今と同じく `itemFlagged` で判断する。
- `Golem.Layout.Table` の `cellExtent` は、`ExplicitHyphen` を最小の幅の区切りに含め、`PatternHyphen` は今と同じく含めない。
- golem-driver の `Pdf.hs` の行末のハイフンの描画（`Penalty hw _ True`）は、`PatternHyphen` に限る。

### 罰点の等しい経路の選び方

[ADR 0001](0001-knuth-plass-line-breaking.md) の「罰点が等しい候補が複数ある場合は、より前の位置で分割する候補を選ぶ」を、次の規則に置き換える。

> 罰点の合計が最小の経路が複数あるときは、各経路の分割の位置と適合度の分類の組 `(位置, 適合度)` を段落の終わりから並べた列を辞書式に比べ、大きいほうを選ぶ。

TeX は、行長が一定の段落では行の番号を区別せず、分割の位置と適合度の分類ごとに一つの活性ノードを持つ。
活性ノードの並びは、位置の順、同じ位置では適合度の分類の番号の順（very loose が先）であり、等しい罰点では後から調べた候補が残る。
したがって TeX の選ぶ経路は、終わりから一つずつ、等しい候補の中で並びの最も後ろの前任を選んだものになり、上の辞書式の最大と一致する。
Golem の `Fitness` の番号（0 が very loose、3 が tight）は TeX の `fit_class` と同じ順である。

実装は二か所を直す。

- `step` の中の `Map.insertWith` の比較を、`nDem new < nDem old` から `nDem new <= nDem old` に変える。`feasible` は活性ノードの並びの順（位置の順、同じ位置では行の数と適合度の順）なので、同じ鍵 `(行の数, 適合度)` で罰点が等しければ後の前任が残る。
- `run` の最後の選び方を、`sortOn nDem ends` の先頭から、罰点が最小のものの中で `[(nPos n, nFit n) | n <- walk best]` の列が辞書式に最大のものに変える。Golem は行の数ごとに活性ノードを分けて持つので、TeX が途中で一つにまとめた経路が最後まで別々に残る。最後の比較でそれをまとめる。

### 行の罰点の打ち切り

`lineDemerits` を TeX と同じく次の式にする。

```haskell
lineDemerits ps b p =
  let l = toInteger (pLinePenalty ps + b)
      base = if abs l >= 10000 then 100000000 else l * l
   in ...  -- 罰則の項は今のまま
```

`pLinePenalty` が 10 なら、不良度が 9990 以上の行で差が出る。
許容度を 9990 以上にした `style.toml` と、4 番目の段階（許容度 10000）で効く。

### style.toml

`[composition]` に次の欄を加える。

| 欄 | 型 | 既定値 | 意味 |
|---|---|---|---|
| `explicit-hyphen-penalty` | 整数 | 50 | 明示のハイフンの直後で分けるときの罰則。−9999 から 10000 まで |

- `Golem.Project.Style` の `Composition` に `compExplicitHyphenPenalty :: Int` を加え、範囲の外の値は G0306 とする（`parseStyle` の `checks` に加える）。−10000 以下は強制の改行になるので許さない。
- golem-driver の `Pdf.hs` は、この値を `ComposeEnv` に加える `ceExplicitHyphenPenalty :: Int` に渡す。`defaultComposeEnv` の既定値は 50 とする。

### 参照テストの拡張

[ADR 0007](0007-knuth-plass-reference-test.md) の参照テストを、明示のハイフンありで TeX と比べるように変える。
ハイフネーション（`\hyphenpenalty=10000`）は今と同じく止める。

`frog-king.tex` を次のように直す。

- `\exhyphenpenalty=10000` を `\exhyphenpenalty=50` にする。
- `\hsize` に 260pt を加え、160pt、200pt、240pt、260pt、300pt の五つにする。260pt は、一回目の段階で `lime-` の直後の分割が選ばれる幅である。
- [ADR 0007](0007-knuth-plass-reference-test.md) の幅の条件（`Overfull \hbox` がないこと）に、トレースに `b=*` がないことを加える。`\hfuzz` より小さいはみ出しは警告にならないためである（「TeX で確かめたこと」）。今の四つの幅と 260pt は、この条件を満たす。
- 語を測るマクロ（`\golemmeasure`）は、`-` を含む語を `-` の直後で部分に分けて、部分ごとに `\hbox` で測る。部分の間に `exhyphen` の記録を書く。段落の中で `-` を含む語は `lime-tree` だけである。

`frog-king.words` の `lime-tree` の記録は、次の三行になる。

```text
box 1419949 lime-
exhyphen
box 1094088 tree
```

テストのコード（`modules/golem-layout/test/KnuthPlassReference.hs`）は次のように直す。

- `Words` の `wBoxes :: [(Text, Sp)]` を、`data WordRec = WordBox !Text !Sp | WordExHyphen` の列に変える。`parseWords` は `exhyphen` の記録を `WordExHyphen` として読む。
- `paragraphItems` は、`WordExHyphen` の位置に、語間の空きの代わりに `Penalty 0 50 ExplicitHyphen` を置く。
- データの検査（`whole` との比較）の語間の数は、箱の数から 1 と `exhyphen` の数を引いた値にする。
- `wordsOf` は、ログに印字された語のうち、`-` の後ろに文字が続くものを `-` の直後で分けて数える。TeX は実行可能な分割の位置ごとに印字を区切るので、`lime-` で分割が実行可能なら `lime-` と `tree` が別々に、そうでなければ `lime-tree` が一続きに印字される。分けて数えれば、どちらの場合も語の番号が箱の番号と一致する。
- `referenceHsizes` に 260 を加える。

再生成の手順は [ADR 0007](0007-knuth-plass-reference-test.md) と同じで、手元の TeX を使う。

```sh
cd modules/golem-layout/test/data/knuth-plass
export PATH="$(echo ~/.local/texlive/2026/bin/*/):$PATH"
tex --version | head -1   # TeX 3.141592653 (TeX Live 2026)
shasum -a 256 "$(kpsewhich cmr10.tfm)"   # README の値と一致すること
max_print_line=10000 tex -interaction=batchmode frog-king.tex
# frog-king.log の一行目（版と日時）を除く
```

### 罰点の等しい経路の参照データ

`modules/golem-layout/test/data/knuth-plass/` に `ties.tex` と `ties.log` を加える。
`ties.tex` は「TeX で確かめたこと」の二つの段落を組み、`\tracingparagraphs=1` と `\showbox` を出す。
テストはこのログを読まず、期待値を単体テストに書き写す。
ログは期待値の出所として置き、README に再生成の手順と、二つの段落で TeX が選んだ経路を書く。

### ドキュメント

- 仕様書の「今後の実装項目」から「ハイフネーション」の項目を消す。
- 仕様書の「行分割」の節に、明示のハイフンの直後を一回目の段階から候補にすること、ダッシュの扱い、明示のハイフンを含む語にパターンを当てないこと、罰点の等しい経路の選び方を書く。参照テストの条件の文（ハイフネーションと明示のハイフンを止める）を、ハイフネーションだけを止める文に直す。
- 仕様書の `style.toml` の例と説明に `explicit-hyphen-penalty` を加える。
- テストのデータの README（`modules/golem-layout/test/data/knuth-plass/README.md`）の「組版の条件」を直し、`\hsize` の表に 260pt を加え、`ties.tex` の節を加える。
- [ADR 0001](0001-knuth-plass-line-breaking.md) のステータスを「採択→罰点が等しい候補の選び方は [ADR 0008](0008-explicit-hyphens.md)」に、[ADR 0007](0007-knuth-plass-reference-test.md) のステータスを「採択→明示のハイフンの扱いと、罰点が等しい場合の不一致の扱いは [ADR 0008](0008-explicit-hyphens.md)」に変える。

## TeX で確かめたこと

`frog-king.tex` を `\exhyphenpenalty=50` に変え、`\hsize` を 150pt から 360pt まで 1pt 刻みで組んだ。

- 160pt、200pt、240pt、300pt は、`\exhyphenpenalty=10000` のときと同じ段階、同じ罰点の合計（64047、81520、9361、2031）になる。`lime-` は分割の候補になるが、選ばれない。
- 257pt から 267pt では、一回目の段階で `lime-` の直後の分割が選ばれ、`Overfull \hbox` は出ない。260pt の罰点の合計は 7674 である。
- 二回目の段階で `lime-` の直後が選ばれるのは 184pt と 185pt だけで、どちらも `Overfull \hbox` が出る。[ADR 0007](0007-knuth-plass-reference-test.md) の条件で除く。
- `lime-` と `tree` を別々に測った幅の和（1419949 + 1094088）は、`lime-tree` の幅 2514037 に等しい。cmr10 には `-` と `t` の間のカーニングがない。

罰点の等しい経路について、次の二つの段落を組んだ。

- `\hsize=10pt` で、幅 10pt、0pt、10pt の三つの箱の間に `\penalty0` を置いた段落。一つ目の箱の後と二つ目の箱の後のどちらで分けても罰点の合計は 200 になり、TeX は二つ目の箱の後（後の位置）を選ぶ。
- `\hsize=20pt`、`\linepenalty=0`、`\adjdemerits=0` で、幅 20pt の箱、`\penalty0`、幅 10pt の箱と `\hskip0pt plus1fil` と `\penalty0`、幅 10pt の箱と `\hskip0pt plus1fil` と `\penalty0`、幅 20pt の箱を並べた段落。三行の経路と四行の経路がどちらも罰点 0 になり、TeX は四行の経路を選ぶ。Golem は行の数ごとに活性ノードを分け、最後に `sortOn nDem` の先頭（行の数の少ないほう）を選ぶので、三行の経路を選ぶ。

Golem の側は、`Golem.Layout.KnuthPlass` の写しに、この ADR の三つの変更（明示のハイフンを一回目の段階から使うこと、罰点の等しい経路の選び方、行の罰点の打ち切り）を加えた試作で確かめた。
`lime-tree` を `lime-`、罰則 50、`tree` に分けた並びで、160pt、200pt、240pt、257pt から 267pt、300pt のすべてで、分割の位置、段階、罰点の合計、適合度、調整比が TeX と一致した。
選び方と打ち切りの変更の前後で、150pt から 360pt の結果は一つも変わらなかった。
`frog-king` の段落では、罰点の等しい候補は `Overfull \hbox` の出る 210pt にしか現れない。
選び方の規則は、上の二つの段落の単体テストで確かめる。

試作では、`Overfull \hbox` の出ない 234pt と 289pt で、TeX と Golem の結果が異なった。
TeX のログでは、どちらも一行目が `b=*`（許容度を超える行を、活性ノードがなくなるのを避けるために作った行）であり、`\showbox` の glue set は −1.0 である。
はみ出しの量が plain TeX の `\hfuzz`（0.1pt）より小さいので、警告が出ないと考えられる。
この差は明示のハイフンとは関係がなく、`\exhyphenpenalty=10000` でも同じ二つの幅で TeX は二回目の段階で `b=*` の行を作る。

## 実装しないこと

- ソフトハイフン（U+00AD）と、原稿で分割の位置を指定する記法。
- `\finalhyphendemerits`。[ADR 0007](0007-knuth-plass-reference-test.md) と同じく、Golem に加えない。
- 明示のハイフンを含む語の部分ごとのハイフネーション。TeX と同じく当てない。
- en ダッシュと em ダッシュの前での分割。TeX と同じく後ろだけを候補にする。
- 語の先頭のハイフン（`-5`）の後ろでの分割。TeX は候補にするが、負の数や記号の後で行が分かれるのを避ける。
- 和文の中のハイフン類の後ろの分割に罰則を付けること。
- `\parshape` に当たる、行長の変わる段落での TeX との一致。下の「トレードオフ」に書く。
- HTML と EPUB の出力の変更。行分割は読者の側のエンジンが行う。

## テスト設計

`modules/golem-layout/test/Main.hs` に加える。
実装の前に書き、失敗することを確かめる。

### 組み方

- `compose env "lime-tree"`（`cePatterns = Just englishUS`）の箱が `["lime-", "tree"]` で、その間に `Penalty 0 50 ExplicitHyphen` がある。
- `compose env "well-known"` と `compose env "self-evident"` に `PatternHyphen` の罰則がない。`Box` の列は `["well-", "known"]` と `["self-", "evident"]` である。
- `ceExplicitHyphenPenalty = 10000` の `compose env "lime-tree"` は、箱が `["lime-tree"]` 一つになる。
- `compose env "-5"`、`compose env "pre-"`、`compose env "a--b"` の罰則が、それぞれ 0 個、0 個、1 個（`a--` の後）である。
- `compose env "us!”—“We"` の箱が `["us!”—", "“We"]` で、間に `ExplicitHyphen` の罰則がある。
- `compose env "lime‐tree"`（U+2010）と `compose env "1990–2000"`（U+2013）に、和欧間の四分の空きの `Glue` がなく、`ExplicitHyphen` の罰則が一つある。
- `compose env "東京–大阪"` は、今と同じく `–` が一文字の箱であり、その前に分割の候補がない。
- `compose env "non‑breaking"`（U+2011）は、箱が一つで罰則がない。

### 行分割

- `[box 30, Penalty 0 50 ExplicitHyphen, box 30] <> finish` を行長 30 で組むと、一回目の段階（`brPass` が 1）で罰則の位置で分かれる。`PatternHyphen` に変えた同じ並びは、一回目の段階では分かれない。
- 明示のハイフンで終わる行の `lineItems` の最後の罰則の幅が 0 であり、`placeLine` の最後の箱の右端が行長に一致する。
- `lineDemerits defaultParams 9990 0` が 100000000、`lineDemerits defaultParams 9989 0` が 99980001 である。
- 罰点の等しい経路（一つ目）：`[box 10, Penalty 0 0 NoHyphen, box 0, Penalty 0 0 NoHyphen, box 10] <> finish` を行長 10 で組むと、`brPositions` が `[3, length items - 1]`、`brDemerits` が 200 である。既存の「equal demerits: the earlier break wins」を、この期待値に置き換える。
- 罰点の等しい経路（二つ目）：「TeX で確かめたこと」の二つ目の段落を、`pLinePenalty = 0`、`pAdjDemerits = 0`、行長 20 で組むと四行になり、`brDemerits` が 0 である。`\hskip0pt plus1fil` は `Glue 0 filStretch 0` で表す。
- 既存の総当たりのプロパティテストに、罰点が最小の分割の列の中で、選んだ列が終わりからの辞書式で最大であることを加える。

### 参照テスト

- 「the data has every \hsize of frog-king.tex, from both passes」の期待値を、260pt を含む五つにする。
- 260pt の `compareRun` が空であり、TeX の経路に `lime-` の直後の分割が含まれる（`tbWordIndex` が `lime-` の語の番号である）ことを確かめる。
- `parseWords` が `exhyphen` の記録を読み、`paragraphItems` が `[refBox "" 20, refBox "lime-" a, Penalty 0 50 ExplicitHyphen, refBox "tree" b] <> finish` を作る単体テスト。
- `wordsOf "lime-tree in"` が三語、`wordsOf "lime-"` が一語になる単体テスト。

### style.toml と PDF

- `modules/golem-project/test/Main.hs`：`explicit-hyphen-penalty = 100` を読めること、`-10000` と `10001` が G0306 になること、欄がなければ 50 になること。
- `modules/golem-driver/test/Main.hs`：狭い行長の横組みの段落に `well-known` を並べて PDF を作り、内容のストリームの `<002D>` の数が原稿の `-` の数と等しいこと。行末にハイフンが足されていないことを確かめる。

## トレードオフ

罰点の等しい経路の選び方を TeX に合わせるので、[ADR 0001](0001-knuth-plass-line-breaking.md) の「前の位置を選ぶ」をやめる。
どちらの規則も結果を一つに決めるので、決定性は変わらない。
今の PDF のうち、罰点の等しい経路を含む段落は分割が変わりうる。
TeX と同じ選び方にすれば、参照テストで不一致の `\hsize` をデータから除く必要がなくなる。

この規則は、行長が一定の段落で TeX と一致する。
TeX は `\parshape` のある段落では、特別な行の範囲で行の番号ごとに活性ノードを分け、最後に並びの先頭（行の番号の小さいほう）を選ぶ。
Golem の L*(i) は関数であり、行長が一定かどうかを `breakParagraph` は知らないので、行長の変わる段落（回り込みの脇の行、韻文の字下げ）では、罰点の等しい経路について TeX と異なる経路を選ぶ場合がある。
罰点が完全に等しくなるのはまれであり、この場合の一致は求めない。

明示のハイフンを含む語にパターンを当てないので、`counter-revolutionary` のような長い複合語は、ハイフンの後ろでしか分けられない。
狭い行では、語間が広がるか、二回目以降の段階に進む。
部分ごとにパターンを当てれば分割の候補は増えるが、一つの語に明示のハイフンとパターンのハイフンが並び、TeX とも結果が変わる。
TeX と同じ扱いを選ぶ。

語の先頭のハイフンの後ろを候補にしないので、その位置では TeX と結果が異なる。
参照テストの段落には該当する語がない。

`Item` の罰則のフラグを真偽値から型に変えるので、`Penalty w p True` の形で書いたテストと golem-driver の描画をすべて書き換える。
真偽値のまま幅で区別する案（幅が正ならパターン、0 なら明示）は、変更は小さいが、幅 0 のパターンの候補（ハイフンを描かない言語）を表せなくなる。
種類を型で表す。
