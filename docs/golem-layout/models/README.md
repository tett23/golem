# 改ページの規則の Alloy のモデル

`pagination.als` は、改ページの規則を Alloy の述語として書いたモデルである（[docs/adr/0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md) の 5）。
規則どうしが両立しない入力を探すための道具であり、Golem の実装を確かめるものではない。
実装は golem-layout のテスト（`modules/golem-layout/test/PaginateInvariantsSpec.hs`）が確かめる。
CI では走らせない。
改ページの規則を変える ADR では、モデルを直して走らせ直し、この文書の結果を書き直す（[docs/roadmap.md](../../roadmap.md) の「手で確かめる項目」）。

## モデル

一つの段と次の段の境目だけを扱う。

- 入力は、格子の行の数 `cap`（3 から 6）の段と、その段で既に使った行の数 `used`（0 なら空の段）と、流れの順に並んだ要素である。
- 要素は、段落の行（`Line`。同じ段落の行は続けて並ぶ）、一行の見出し（`Heading`）、高々一つの図版（`Figure`、1 行から `cap + 1` 行）である。
- 改丁の見出し（`Recto`）は、見出しの一種である。[docs/adr/0206](../../adr/0206-pagination-points-the-invariants-did-not-decide.md) の決めたことを調べる述語だけが、ほかの見出しと区別する。
- 配置（`Placement`）は、本文の要素を `brk` の前までこの段に、残りを次の段に置き、図版をこの段に置く（`kept`）か次の段に送る。
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
そのため、`tallFigure` のほかのコマンドは、図版が段の行の数を超えない入力（述語 `inDomain`）だけを調べる。

## 走らせ方

Alloy 6.2.0 の CLI（`alloy6`）と OpenJDK 27.0.1 で走らせた（2026-11-08）。
サンドボックスの中で Java が一時ファイルを書けない環境では、`-Djava.io.tmpdir` で書ける場所を渡す。

```sh
cd docs/golem-layout/models
JAVA_TOOL_OPTIONS="-Djava.io.tmpdir=$TMPDIR" alloy6 exec -q -n -t text -c noneMeetsAll -o - pagination.als
```

`-n` は算術のあふれを含む解を除く。
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
仕様書の「既知の不具合」の「図版を追い越した見出しが、本文から離れる」は、規則どうしの矛盾ではない。
見出しを図版とともに次の段に送れば、すべての規則を満たす。
改ページの不変条件のテストが示すとおり、見出しを置くかを決めるときに送った図版を数えない実装の不具合である。
[ADR 0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md) のテスト設計は、この組が両立しない組として出ることを確かめる項目に挙げていたが、そうはならなかった。

[docs/adr/0206](../../adr/0206-pagination-points-the-invariants-did-not-decide.md) の決めたことについて、次のことがわかった。

- 見出しだけを置いた段の後の行は、孤立行と寡婦行の規則を緩めなければ、すべてを満たす配置のない入力がある（`strictAfterHeadings`）。緩めれば、ない（`relaxedAfterHeadings`）。
- 改丁の見出しを見出しの並びに数えても（`rectoKept`）、並びを改丁の見出しの前で切っても（`rectoEnds`）、配置のない入力は出なかった。モデルは一つの段と次の段の境目だけを扱い、前の見出しを改丁の見出しとともに次の段に送れば、境目の規則はすべて満たせるからである。並びをどこで切るかは、規則の矛盾の解き方ではなく、どちらの出力が望ましいかの選択である。
- [golem-layout ADR 0021](../adr/0021-keep-with-next-counts-widow-and-orphan.md) の量の I6 でも、貪欲法のほかのすべての規則を満たす配置がある（`keep21`）。
- 決めた規則のすべてを課しても、改丁の見出しのある入力に配置がある（`decidedSome`）。モデルは全否定ではない。
- 送った図版と改丁の見出しの順（[docs/adr/0206](../../adr/0206-pagination-points-the-invariants-did-not-decide.md) の 3）は、ページの奇数と偶数に関わるので、このモデルでは書けない。改ページの不変条件のテストが確かめる。
