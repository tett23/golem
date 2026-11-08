# 改ページの規則の Alloy のモデル

`pagination.als` は、改ページの規則を Alloy の述語として書いたモデルである（[docs/adr/0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md) の 5）。
規則どうしが両立しない入力を探すための道具であり、Golem の実装を確かめるものではない。
実装は golem-layout のテスト（`modules/golem-layout/test/PaginateInvariantsSpec.hs`）が確かめる。
CI では走らせない。
改ページの規則を変える ADR では、モデルを直して走らせ直し、この文書の結果を書き直す（[docs/roadmap.md](../../roadmap.md) の「手で確かめる項目」）。

## モデル

一つの段と次の段の境目だけを扱う。

- 入力は、格子の行の数 `cap`（3 から 6）の段と、その段で既に使った行の数 `used`（0 なら空の段）と、流れの順に並んだ要素である。
- 要素は、段落の行（`Line`。同じ段落の行は続けて並ぶ）、一行の見出し（`Heading`）、高々二つの図版（`Figure`、1 行から `cap + 1` 行）、高々一つの一行の行アキ（`Blank`）、高々一つの一行の空き（`Space`）、高々二つの `@need-lines`（`Need`、1 行から `cap + 1` 行）である。図版を二つと行アキは [golem-layout ADR 0026](../adr/0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) で、空きと `@need-lines` は [golem-layout ADR 0027](../adr/0027-need-lines-judged-again-after-spaces.md) で、二つめの `@need-lines` と行の数は [golem-layout ADR 0035](../adr/0035-a-larger-need-lines-after-a-judged-one-is-judged-again.md) で足した。[golem-layout ADR 0027](../adr/0027-need-lines-judged-again-after-spaces.md) のコマンドは、`@need-lines` が高々一つで 2 行の入力（述語 `inDomain27`）だけを調べる。
- 空きは本文の一種として置き、`brk` の前ならこの段の一行を取る。
- 改丁の見出し（`Recto`）は、見出しの一種である。[docs/adr/0206](../../adr/0206-pagination-points-the-invariants-did-not-decide.md) の決めたことを調べる述語だけが、ほかの見出しと区別する。
- 配置（`Placement`）は、本文の要素を `brk` の前までこの段に、残りを次の段に置き、それぞれの図版をこの段に置く（`kept`）か次の段に送り、行アキをこの段に置く（`placed`）か置かない。
- 入力ごとに、すべての配置を原子として持つ（事実 `allPlacements`）。そのため「どの配置も規則を満たさない」を一階の論理で書ける。
- 次の段があふれるかは調べない。

規則は事実ではなく述語である。

| 述語 | 規則 |
| --- | --- |
| `fits` | この段の行が段に収まる |
| `greedy` | 本文を先頭から詰め、次の本文が入らない位置で段を改める（貪欲法） |
| `order` | この段に置いた図版の前の本文は、すべてこの段にある（I3） |
| `figure` | 図版は、現れた位置に入ればそこに置き、入らなければ次の段に送る |
| `orphan` | 段落の最初の行だけを段の末尾に残さない。空の段の先頭では除く（I4） |
| `widow` | 段落の最後の行だけを次の段に送らない。空の段から始まる段落では除く（I5） |
| `keepHeading` | 段の最初でない見出しは、続く見出しと、その後の段落の最初の 2 行と同じ段に置く（I6） |
| `noSendFromEmpty` | 空の段では、最初の要素を送らない |

[docs/adr/0206](../../adr/0206-pagination-points-the-invariants-did-not-decide.md) の決めたことを調べるために、次の述語を足した。

| 述語 | 規則 |
| --- | --- |
| `lineAfterHeadings` | 段の先頭から見出しだけを置いた段では、見出しの後の行を一行は置く（仕様書の、[docs/adr/0206](../../adr/0206-pagination-points-the-invariants-did-not-decide.md) の前の文） |
| `orphanH`、`widowH` | `orphan` と `widow` で、段の先頭から見出しだけを置いた段を空の段と同じに扱う（[docs/adr/0206](../../adr/0206-pagination-points-the-invariants-did-not-decide.md) の 2） |
| `keepHeading21` | `keepHeading` の段落の量を [golem-layout ADR 0021](../adr/0021-keep-with-next-counts-widow-and-orphan.md) のもの（3 行以下の段落は全体、4 行以上は 2 行）にし、改丁の見出しもほかの見出しと同じに数える |
| `keepHeadingR` | `keepHeading21` の見出しの並びを、改丁の見出しの前で切る（[docs/adr/0206](../../adr/0206-pagination-points-the-invariants-did-not-decide.md) の 4） |
| `recto` | この段に置いた改丁の見出しは、段の最初の要素である（I8 を段の境目で読んだもの） |
| `base` | `fits`、`order`、`figure`、`noSendFromEmpty` を合わせたもの |

仕様書の「図版」の節は、図版を縮めて空の段に必ず収める。
そのため、`tallFigure` のほかのコマンドは、図版が段の行の数を超えない入力（述語 `figuresFit`）だけを調べる。
[docs/adr/0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md) と [docs/adr/0206](../../adr/0206-pagination-points-the-invariants-did-not-decide.md) のコマンドは、図版が高々一つで行アキのない入力（述語 `inDomain`）だけを調べるので、要素を足しても結果は変わらない。

[golem-layout ADR 0026](../adr/0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) の規則を調べるために、次の述語を足した。

| 述語 | 規則 |
| --- | --- |
| `figures` | 図版は、前の本文と図版と、段の先頭でない行アキの後に入り、前の図版を送っていなければ、そこに置き、そうでなければ次の段に送る（[golem-layout ADR 0015](../adr/0015-figure-order.md)、[docs/adr/0046](../../adr/0046-blank-line-command.md)） |
| `figureOrder` | この段に置いた図版の前の図版は、すべてこの段にある（二つの図版の I3） |
| `waitingIn` | 送った図版の後に書いた、送った図版（待つ図版） |
| `blankWithNext` | 行アキは、次のブロック（待つ図版を飛ばした最初の要素）と同じ段に置く。段の先頭なら置かない。次のブロックがなければ置かない（P4′、P5） |
| `blankWithNext25` | `blankWithNext` の次のブロックを、待つ図版も含めた最初の要素にしたもの（この ADR の前の読み方） |
| `base26` | `fits`、`order`、`figures`、`figureOrder`、`noSendFromEmpty` を合わせたもの |

`noSendFromEmpty` は、行アキと `@need-lines` を段の最初の要素に数えない。
どちらもそれだけでは何も置かないからである。
[docs/adr/0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md)、[docs/adr/0206](../../adr/0206-pagination-points-the-invariants-did-not-decide.md)、[golem-layout ADR 0026](../adr/0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) のコマンドは、空きと `@need-lines` のない入力だけを調べる。

[golem-layout ADR 0027](../adr/0027-need-lines-judged-again-after-spaces.md) の規則を調べるために、次の述語を足した。

| 述語 | 規則 |
| --- | --- |
| `needNext` | `@need-lines` の次のブロック：空き、行アキ、待つ図版を飛ばした最初の要素 |
| `needMet` | `@need-lines` の次のブロックをこの段に置き、段の最初でなければ、ブロックの前の残りは 2 行以上ある。残りは空きと行アキを数えない（P1） |
| `spaceKeeps` | `@need-lines` が書いた位置で守られ、次のブロックの最初の部分が空きと行アキの後に入れば、ブロックをこの段に置く（P7） |
| `figures27` | `figures` に、`@need-lines` の次のブロックである図版は、`@need-lines` が守られなければ次の段に送ることを足したもの |
| `base27` | `fits`、`order`、`figures27`、`figureOrder`、`noSendFromEmpty`、`blankWithNext` を合わせたもの |

[golem-layout ADR 0035](../adr/0035-a-larger-need-lines-after-a-judged-one-is-judged-again.md) の規則を調べるために、次の述語を足した。
`needMet`、`spaceKeeps`、`figures27` の 2 行は、`@need-lines` の行の数（`lines`）にした。

| 述語 | 規則 |
| --- | --- |
| `spaceKeepsFirst` | `spaceKeeps` を、ブロックの最初の `@need-lines` だけに当てたもの（この ADR の前の改ページ） |
| `spaceKeeps35` | ブロックの最初の `@need-lines` は書いた位置で判定し、後の `@need-lines` のうち前のどれよりも大きいものは、書いた位置で、前に置いた空きを数えて判定し直す。判定したものがすべて守られ、次のブロックの最初の部分が空きと行アキの後に入れば、ブロックをこの段に置く（P7 を合わせた値で言い直したもの） |

## 走らせ方

Alloy 6.2.0 の CLI（`alloy6`）と OpenJDK 27.0.1 で走らせた（2026-11-08）。
サンドボックスの中で Java が一時ファイルを書けない環境では、`-Djava.io.tmpdir` で書ける場所を渡す。

```sh
cd docs/golem-layout/models
JAVA_TOOL_OPTIONS="-Djava.io.tmpdir=$TMPDIR" alloy6 exec -q -n -t text -c noneMeetsAll -o - pagination.als
```

`-n` は算術のあふれを含む解を除く。
[golem-layout ADR 0026](../adr/0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) で足したコマンドは、図版と行アキの数の上限をコマンドに書く（`2 Figure, 1 Blank`）。
書かなければ、事実で数を限っても、解く問題が大きくなるためである。
`-c` を省くと最初のコマンドだけを、`-c '*'` ですべてを走らせる。
解があれば `---Trace---` の後に入力と配置を書き、なければ何も書かない。

最も小さい例は、要素の数の上限（スコープ）を 2 から順に上げて、最初に解が出たスコープの解とした。

```sh
for c in $(grep -E '^run [A-Za-z0-9]+' pagination.als | awk '{print $2}'); do
  found=none
  for k in 2 3 4 5; do
    sed "s/for 5 but/for $k but/" pagination.als > "$TMPDIR/m.als"
    JAVA_TOOL_OPTIONS="-Djava.io.tmpdir=$TMPDIR" alloy6 exec -q -n -t text -c "$c" -o - "$TMPDIR/m.als" > "$TMPDIR/$c-$k.txt" 2>&1 || true
    if grep -q -- '---Trace---' "$TMPDIR/$c-$k.txt"; then found=$k; break; fi
  done
  echo "$c $found"
done
```

## 結果

2026-11-08 に、スコープ 2 から 5 まで（要素は 5 個まで、整数は 5 ビット）で走らせた結果である。
「なし」は、スコープ 5 までに解がなかったことを示す。

| コマンド | 調べること | 最も小さい例のスコープ |
| --- | --- | --- |
| `someFits` | 段に収まる配置があるか | 2 |
| `noneMeetsAll` | すべての規則を満たす配置がない入力があるか | 2 |
| `noneMeetsAllButGreedy` | 貪欲法のほかのすべての規則を満たす配置がない入力があるか | なし |
| `greedyOrphan` | `greedy` と `orphan` | 2 |
| `greedyWidow` | `greedy` と `widow` | 2 |
| `greedyKeepHeading` | `greedy` と `keepHeading` | 2 |
| `greedyFigure` | `greedy` と `figure` | なし |
| `orphanEmpty` | `orphan` と `noSendFromEmpty` | なし |
| `widowEmpty` | `widow` と `noSendFromEmpty` | なし |
| `keepHeadingEmpty` | `keepHeading` と `noSendFromEmpty` | なし |
| `orphanWidow` | `orphan` と `widow` | なし |
| `keepHeadingOrphan` | `keepHeading` と `orphan` | なし |
| `keepHeadingWidow` | `keepHeading` と `widow` | なし |
| `keepHeadingFigure` | `keepHeading` と `figure` | なし |
| `figureOrder` | `figure` と `order` | なし |
| `figureEmpty` | `figure` と `noSendFromEmpty` | なし |
| `tallFigure` | 段より高い図版で、`fits`、`figure`、`noSendFromEmpty` | 2 |
| `strictAfterHeadings` | `base`、`orphan`、`widow`、`keepHeading21`、`lineAfterHeadings`（改丁の見出しなし） | 4 |
| `relaxedAfterHeadings` | `base`、`orphanH`、`widowH`、`keepHeading21`、`lineAfterHeadings`（改丁の見出しなし） | なし |
| `rectoKept` | `base`、`orphanH`、`widowH`、`keepHeading21`、`lineAfterHeadings`、`recto` | なし |
| `rectoEnds` | `base`、`orphanH`、`widowH`、`keepHeadingR`、`lineAfterHeadings`、`recto` | なし |
| `keep21` | `base`、`orphan`、`widow`、`keepHeading21`（改丁の見出しなし） | なし |
| `decidedSome` | 決めた規則のすべてを満たす配置が、改丁の見出しのある入力にあるか | 2 |

モデルは空でも全否定でもない。
規則を課さなければ配置があり（`someFits`）、すべてを課すと配置のない入力がある（`noneMeetsAll`）。

両立しない組の最も小さい例は次のとおりである。

- `noneMeetsAll`：段の行の数が 5 で 4 行を使った段に、見出しが二つ続く。貪欲法は一つめの見出しをこの段に置き、`keepHeading` は二つめの見出しも同じ段に求めるが、段に入らない。
- `greedyOrphan` と `greedyWidow`：段の行の数が 3 で 2 行を使った段に、2 行の段落が来る。貪欲法は最初の行をこの段に置くが、それは孤立行であり、同時に最後の行だけを次の段に送る寡婦行でもある。
- `greedyKeepHeading`：`noneMeetsAll` より小さい段（3 行のうち 2 行を使った段）に、見出しが二つ続く。
- `tallFigure`：段の行の数が 6 の空の段に、7 行の図版が来る。空の段からは送れず、置けば段からあふれ、図版の規則は送ることを求める。仕様書は図版を縮めて空の段に収めるので、この入力は改ページに届かない。
- `strictAfterHeadings`：段の行の数が 3 の空の段に、見出しと 3 行の段落が来る。見出しは空の段から送れず、見出しの後に 1 行を置けば孤立行、2 行を置けば寡婦行になる。見出しだけの段を空の段と同じに扱えば、配置のない入力はなくなる（`relaxedAfterHeadings`）。

両立しない組は、どれも貪欲法と、改ページの位置を前にずらす規則の組である。
仕様書は、どれも後者を優先すると決めている（「改ページ」の節の、孤立行と寡婦行の行を次の段に送る規則と、[golem-layout ADR 0003](../adr/0003-pagination-and-s2.md) の「見出しの直後では改ページしない。見出しを次のページに送る」）。
docs/roadmap.md の「未決事項」に足す組はない。

貪欲法を除くと、スコープ 5 までのどの入力にも、すべての規則を満たす配置がある（`noneMeetsAllButGreedy`）。
とくに、見出しの規則と図版を送る規則の組（`keepHeadingFigure`）は両立しない組として出なかった。
仕様書の「既知の不具合」にあった「図版を追い越した見出しが、本文から離れる」は、規則どうしの矛盾ではない。
見出しを図版とともに次の段に送れば、すべての規則を満たす。
改ページの不変条件のテストが示したとおり、見出しを置くかを決めるときに送った図版を数えない実装の不具合であり、[golem-layout ADR 0023](../adr/0023-keep-with-next-after-figures-sent-on.md) で直した。
[ADR 0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md) のテスト設計は、この組が両立しない組として出ることを確かめる項目に挙げていたが、そうはならなかった。

[docs/adr/0206](../../adr/0206-pagination-points-the-invariants-did-not-decide.md) の決めたことについて、次のことがわかった。

- 見出しだけを置いた段の後の行は、孤立行と寡婦行の規則を緩めなければ、すべてを満たす配置のない入力がある（`strictAfterHeadings`）。緩めれば、ない（`relaxedAfterHeadings`）。
- 改丁の見出しを見出しの並びに数えても（`rectoKept`）、並びを改丁の見出しの前で切っても（`rectoEnds`）、配置のない入力は出なかった。モデルは一つの段と次の段の境目だけを扱い、前の見出しを改丁の見出しとともに次の段に送れば、境目の規則はすべて満たせるからである。並びをどこで切るかは、規則の矛盾の解き方ではなく、どちらの出力が望ましいかの選択である。
- [golem-layout ADR 0021](../adr/0021-keep-with-next-counts-widow-and-orphan.md) の量の I6 でも、貪欲法のほかのすべての規則を満たす配置がある（`keep21`）。
- 決めた規則のすべてを課しても、改丁の見出しのある入力に配置がある（`decidedSome`）。モデルは全否定ではない。
- 送った図版と改丁の見出しの順（[docs/adr/0206](../../adr/0206-pagination-points-the-invariants-did-not-decide.md) の 3）は、ページの奇数と偶数に関わるので、このモデルでは書けない。改ページの不変条件のテストが確かめる。

### [golem-layout ADR 0026](../adr/0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) のコマンド

2026-11-08 に、スコープ 2 から 4 まで（要素は 4 個まで、整数は 5 ビット）で走らせた結果である。
待つ図版の形は、送る図版、行アキ、待つ図版、後のブロックの 4 個で作れる。
スコープ 4 で、解のないコマンドに SAT4J が 2 分から 20 分かかったので、スコープ 5 は走らせていない。
`blankFigureOrder` のスコープ 4 は 1 時間を超えても終わらなかったので打ち切り、スコープ 3 までの結果を書いた。
「なし」は、スコープ 4 までに解がなかったことを示す。

| コマンド | 調べること | 最も小さい例のスコープ |
| --- | --- | --- |
| `waitingBlankSome` | 送った図版の後の行アキと待つ図版と後の本文があり、`base26` と `blankWithNext` を満たし、行アキと後の本文をこの段に置く配置がある入力があるか | 4 |
| `waitingBlankNone` | `base26` と `blankWithNext` を満たす配置がない入力があるか | なし |
| `waitingBlankAllButGreedy` | `waitingBlankNone` に `orphan`、`widow`、`keepHeading21` を足したもの | なし |
| `blankFigureOrder` | `blankWithNext` と、`figures` と `figureOrder` の組 | なし（スコープ 3 まで） |
| `blankBeforeWaiting25` | この ADR の前の読み方で、行アキが待つ図版とともに次の段に移り、後の本文だけがこの段に残る配置がある入力があるか | 4 |
| `blankRules25` | この ADR の前の読み方で、`base26` と `blankWithNext25` を満たす配置がない入力があるか | なし |

`waitingBlankSome` の最も小さい例は、段の行の数が 4 で 2 行を使った段に、4 行の図版、行アキ、4 行の図版、改丁の見出しが来るものである。
一つめの図版は入らずに送られ、二つめの図版は待つ。
行アキは見出しとともにこの段に置かれる。
モデルは空ではなく、この ADR の直す形を入力に持つ。

`blankBeforeWaiting25` の最も小さい例は、段の行の数が 5 で 4 行を使った段に、4 行の図版、行アキ、5 行の図版、見出しが来るものである。
この ADR の前の読み方では、行アキは待つ図版とともに次の段に移り、見出しは行アキなしにこの段に置かれる。
読み方を変えても、規則を満たす配置のない入力は出ない（`blankRules25`）。
二つの読み方の違いは規則の矛盾ではなく、行アキをどちらのブロックに付けるかの選択である。

行アキを次のブロックと同じ段に置く規則と、図版の順の規則は、スコープ 4 までのどの入力でも両立する（`waitingBlankNone`、`waitingBlankAllButGreedy`）。
両立しない規則の組として出るものはなく、[docs/roadmap.md](../../roadmap.md) の「未決事項」に足す組はない。
最初に走らせたとき、`waitingBlankNone` は、段の行の数が 3 で 1 行を使った段に、行アキと 2 行の図版が来る入力を返した。
図版の規則が、置いた行アキだけを数え、置くかどうかを図版で決める行アキを数えていなかったためである。
改ページの実装（`placeBlank`）は、行アキと次の最初の部分の和で量るので、モデルの誤りとして `figures` を直した。

### [golem-layout ADR 0027](../adr/0027-need-lines-judged-again-after-spaces.md) のコマンド

2026-11-08 に、スコープ 2 から 3 まで（要素は 3 個まで、整数は 5 ビット）で走らせた結果である。
`@need-lines`、空き、次のブロックの 3 個で、この ADR の形を作れる。
`needSpaceNone` のスコープ 3 に SAT4J が 33 分かかったので、スコープ 4 は走らせていない。
「なし」は、スコープ 3 までに解がなかったことを示す。

| コマンド | 調べること | 最も小さい例のスコープ |
| --- | --- | --- |
| `needSpaceSome` | `@need-lines`、空き、次のブロックがあり、`base27`、`needMet`、`spaceKeeps` を満たし、空きと次のブロックをこの段に置く配置がある入力があるか | 3 |
| `needFigure` | `needMet` と、`figures` と `figureOrder` の組 | 2 |
| `needGreedy` | `needMet` と `greedy` の組 | 2 |
| `needSpaceNone` | `base27`、`needMet`、`spaceKeeps` を満たす配置がない入力があるか | なし |
| `needSpaceAllButGreedy` | `needSpaceNone` に `orphan`、`widow`、`keepHeading21` を足したもの | なし |

`needSpaceSome` の最も小さい例は、段の行の数が 3 で 1 行を使った段に、`@need-lines 2`、空き、見出しが来るものである。
`@need-lines` は空きの前で守られ、見出しは空きの後に入る。
モデルは空ではなく、この ADR の形を入力に持つ。

両立しない組は二つ出た。

- `needFigure`：段の行の数が 5 で 4 行を使った段に、`@need-lines 2` と 1 行の図版が来る。図版は残りの 1 行に入るが、`@need-lines` は 2 行を求める。
- `needGreedy`：段の行の数が 3 で 2 行を使った段に、`@need-lines 2` と見出しが来る。貪欲法は見出しを残りの 1 行に置くが、`@need-lines` は 2 行を求める。

どちらも、ブロックを入る位置に置く規則と `@need-lines` の組であり、`@need-lines` が段を改めるという指定そのものである。
仕様書は、`@need-lines` を次のブロックを置く直前に判定すると決めているので、`@need-lines` を優先する。
`figures27` は、この順をモデルに書いたものである。
`@need-lines`、空きを段の先頭で捨てる規則、送った図版の規則を合わせても、規則を満たす配置のない入力はない（`needSpaceNone`、`needSpaceAllButGreedy`）。
[docs/roadmap.md](../../roadmap.md) の「未決事項」に足す組はない。

最初に走らせたとき、`needSpaceNone` は二つの入力を返した。
一つは、空の段に `@need-lines` だけが来る入力で、`noSendFromEmpty` が `@need-lines` を段の最初の要素に数えていたためである。
もう一つは、段の行の数が 5 で 1 行を使った段に、`@need-lines 2`、行アキ、4 行の図版が来る入力で、`spaceKeeps` が、次のブロックとともに量る行アキを数えていなかったためである。
どちらもモデルの誤りとして直した。


### [golem-layout ADR 0035](../adr/0035-a-larger-need-lines-after-a-judged-one-is-judged-again.md) のコマンド

2026-11-08 に、スコープ 2 から 4 まで（要素は 4 個まで、整数は 5 ビット）で走らせた結果である。
この ADR の形は、`@need-lines`、空き、より大きい `@need-lines`、次のブロックの 4 個で作れるので、ADR のテスト設計のスコープ 3 には現れない。
そのためスコープ 4 まで走らせた。
`needMoreNone` のスコープ 3 は約 2 分、スコープ 4 は約 14 分かかった。
「なし」は、スコープ 4 までに解がなかったことを示す。

| コマンド | 調べること | 最も小さい例のスコープ |
| --- | --- | --- |
| `needMoreSome` | `@need-lines`、空き、段に収まるより大きい `@need-lines`、次のブロックがあり、`base27`、`needMet`、`spaceKeeps35` を満たし、空きと次のブロックを段の先頭でない位置に置く配置がある入力があるか | 4 |
| `needMore27` | 二つの `@need-lines` のあいだに空きがあり、`base27`、`needMet`、`spaceKeepsFirst` を満たす配置がない入力があるか（この ADR の前の改ページ） | 4 |
| `needMoreNone` | `@need-lines` が二つの入力で、`base27`、`needMet`、`spaceKeeps35` を満たす配置がない入力があるか | なし |

`needMoreSome` の最も小さい例は、段の行の数が 6 で 2 行を使った段に、`@need-lines 2`、空き、`@need-lines 4`、1 行の段落が来るものである。
モデルは空ではなく、この ADR の形を入力に持つ。

`needMore27` の最も小さい例は、段の行の数が 4 で 2 行を使った段に、`@need-lines 1`、空き、`@need-lines 4`、改丁の見出しが来るものである。
一つめの `@need-lines` は空きの前で守られ、見出しは空きの後に入るので、この ADR の前の P7 は見出しをこの段に置くことを求める。
P1 は、合わせた 4 行が残りの 2 行にないので、見出しを次の段に送ることを求める。
この ADR の直した不具合が、規則の組として現れたものである。
`spaceKeeps35` に替えると、規則を満たす配置のない入力はない（`needMoreNone`）。
[docs/roadmap.md](../../roadmap.md) の「未決事項」に足す組はない。

最初に走らせたとき、`needMoreNone` は、段の行の数が 4 で 2 行を使った段に、`@need-lines 3`、`@need-lines 1`、1 行の図版が来る入力を返した。
`spaceKeeps35` が、一つめの小さい `@need-lines` の判定だけを見て、後に続く大きい `@need-lines` を見ていなかったためである。
ブロックの前のすべての `@need-lines` のうち、前のどれよりも大きいものを判定するように、モデルの誤りとして直した。
