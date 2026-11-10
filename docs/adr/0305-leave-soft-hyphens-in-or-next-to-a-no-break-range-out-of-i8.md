# ADR 0305: 改行しない範囲の中と隣のソフトハイフンを、I8 の比べる相手から除く

ステータス: 採択

## 文脈

### 毎晩のジョブの改行しない範囲の段が、I8 の違反で落ちた

2026-11-10 の `enum.yml` の実行 42777778394 は、改行しない範囲の段（`GOLEM_ENUM_NOBREAK_DEPTH` が 3）で落ちた。
実行したコミットは、プルリクエスト [#889](https://github.com/tett23/golem/pull/889) のブランチの `9121329a` である。
#889 は行分割のコードを変えていない。
落ちたテストは、[ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md) の I7 と I8 を確かめる `NoBreakEnum` の列挙である。
最も小さい入力と違反は次のとおりであった。

```
the smallest input that breaks I7 or I8 has 3 parts: Input {inPre = 0, inRun = [(PText "a",False),(PText "\173",False),(PText "a",True)], inPost = 0, inWidth = 2}
I8: the items are [(0,327680,0,0,"a",0,0),(0,327680,0,0,"a",0,0),(2,0,0,0,"",10000,0),(1,0,1125899906842624,0,"",0,0),(2,0,0,0,"",-10000,0)], not [(0,327680,0,0,"a",0,0),(2,163840,0,0,"",50,4),(0,327680,0,0,"a",0,0),(2,0,0,0,"",10000,0),(1,0,1125899906842624,0,"",0,0),(2,0,0,0,"",-10000,0)]
```

入力は、範囲の外の `a`、範囲の外のソフトハイフン、範囲の中の `a` である。
述語は、二つの `a` のあいだにソフトハイフンの罰点（幅 163840、罰則 50）があることを求めた。
組版の項目には、その罰点がない。

手元の `main`（`4f586873`）でも同じに落ちた。
`GOLEM_ENUM_NOBREAK_DEPTH=3 cabal test golem-layout-test --test-option=-p --test-option='/ranges that do not break on every small input/'` は、7 個のテストのうちこの 1 個だけが落ち、最も小さい入力と違反の文は上と同じであった。

### 組版は [ADR 0285](0285-read-soft-hyphens-at-inline-boundaries-in-the-joined-word.md) と [ADR 0297](0297-report-soft-hyphens-next-to-unbreakable-characters-as-g07124.md) のとおりで、述語が [ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md) の I8 の文のとおりである

組版がこの罰点を置かないのは、[ADR 0285](0285-read-soft-hyphens-at-inline-boundaries-in-the-joined-word.md) の「実装すること」の 2 による。
2 は、候補の前の字か後の字が改行しない字（リンクの語、コード、改行しない範囲）なら候補にしないと決めた。
[ADR 0297](0297-report-soft-hyphens-next-to-unbreakable-characters-as-g07124.md) は、このソフトハイフンの notice を G07124 とし、候補にするかどうかは変えないとした。
コードでは、[`joinRun` の `roleOf`](https://github.com/tett23/golem/blob/4f5868731ba6b8e44ad170dd56b83f0b3abbcea9/modules/golem-layout/src/Golem/Layout/Japanese.hs#L1759-L1769) が、ソフトハイフン自身か前後の字の `Look` が `unbreakable` なら候補にしない。

述語は、[ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md) の I8 の文をそのまま書いている（[`i8OnlyBreaks`](https://github.com/tett23/golem/blob/4f5868731ba6b8e44ad170dd56b83f0b3abbcea9/modules/golem-layout/test/NoBreakEnum.hs#L134-L183)）。
I8 は「`lkNoBreak` をすべて偽にした入力の項目の並びから、範囲の中の候補を無限の罰点に置き換えたものが、もとの入力の項目の並びに等しい」である。
述語は、前の最も近い字と後の最も近い字がどちらも範囲の字である位置を「範囲の中」と読む。
これは、組版の [`keepRanges`](https://github.com/tett23/golem/blob/4f5868731ba6b8e44ad170dd56b83f0b3abbcea9/modules/golem-layout/src/Golem/Layout/Japanese.hs#L690-L714) と同じ読み方である。
範囲をすべて外した入力では、二つの `a` は一つのつないだ語になり、ソフトハイフンは候補になる。
片側だけが範囲の字なので、述語は罰点 50 がそのまま残ることを求める。
ところが [ADR 0285](0285-read-soft-hyphens-at-inline-boundaries-in-the-joined-word.md) の 2 により、範囲を付けた入力では候補にならない。

したがって、組版のコードの誤りではない。
I8 の文が、後の [ADR 0285](0285-read-soft-hyphens-at-inline-boundaries-in-the-joined-word.md) と [ADR 0297](0297-report-soft-hyphens-next-to-unbreakable-characters-as-g07124.md) で決めたソフトハイフンの扱いと食い違っている。

### 食い違いは二つの形で出る

深さ 3 までの列挙のすべての入力 511,812 個を、`cabal repl golem-layout-test` で `i8OnlyBreaks` に通した。
I8 に違反する入力は 3,136 個であった。
3,136 個のどれもが、範囲の中のソフトハイフンか、範囲の部品の隣のソフトハイフンを含む。
そうしたソフトハイフンを含まない違反は 0 個であった。

違反は二つの形に分かれる。

- 範囲の境のソフトハイフン（上の最小の入力）：範囲を外した入力には罰点 50 があり、もとの入力にはない。プルリクエスト [#836](https://github.com/tett23/golem/pull/836)（[ADR 0285](0285-read-soft-hyphens-at-inline-boundaries-in-the-joined-word.md) の実装）で、インラインの境目のソフトハイフンがつないだ語で読まれるようになってから出る。#836 の前は、範囲を外した入力でも候補にならなかった（[ADR 0285](0285-read-soft-hyphens-at-inline-boundaries-in-the-joined-word.md) の「今の振る舞い」の表）。
- 範囲の中のソフトハイフン（`[(PText "a",True),(PText "\173",True),(PText "a",True)]` など）：もとの入力は `aa` を一つの箱にし、ソフトハイフンの罰点を置かない。範囲を外した入力は `a` と `a` の二つの箱のあいだに罰点 50 を置く。述語は箱の数の違いを違反として返す。プルリクエスト [#866](https://github.com/tett23/golem/pull/866)（[ADR 0297](0297-report-soft-hyphens-next-to-unbreakable-characters-as-g07124.md) の実装）の後に出る。

二つ目の形は、[ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md) の中の二つの不変条件の食い違いでもある。
I3 は、ソフトハイフンの罰点が改行しない範囲の外にだけあるとする。
I8 は、範囲の中の候補を無限の罰点に置き換えるとする。
範囲の中のソフトハイフンに I8 の文を当てると、範囲の中に幅 `-` のソフトハイフンの罰点（罰則 10000）が残り、I3 に反する。
#866 は I3 に従い、範囲の中のソフトハイフンの罰点をなくした。
#866 の説明は、これを [ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md) の I3 に対する誤りの修正とした。
[ADR 0297](0297-report-soft-hyphens-next-to-unbreakable-characters-as-g07124.md) の N4（項目の並びはこの ADR の前と同じ）は、この変化を述べていない。

### プルリクエストの段では見つからなかった

違反には、字、ソフトハイフン、字の三つの部品が要る。
プルリクエストでの改行しない範囲の上限は 2 部品なので（[`noBreakPrDepth`](https://github.com/tett23/golem/blob/4f5868731ba6b8e44ad170dd56b83f0b3abbcea9/modules/golem-layout/test/NoBreakEnum.hs#L213-L215)）、プルリクエストの CI はこの入力を作らない。
#836 の後に毎晩の設定で走った実行 42758479173 は、ページ分割の段が cancelled になり、改行しない範囲の段は skipped であった（`gh run view 42758479173 --json jobs` の段の結果）。
改行しない範囲の段が #836 の後に深さ 3 で走ったのは、42777778394 が初めてである。

## 実装すること

### 1. I8 を置き換える

[ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md) の I8 を、この ADR の「不変条件」の S1 で置き換える。
範囲に触れるソフトハイフンを、次のように定義する。

- **範囲に触れるソフトハイフン**：ソフトハイフン自身が改行しない範囲の字であるか、つないだ語（[ADR 0285](0285-read-soft-hyphens-at-inline-boundaries-in-the-joined-word.md)）の中で前の字か後の字が改行しない範囲の字であるソフトハイフン。

S1 は、範囲を外した入力の項目から、範囲に触れるソフトハイフンの罰点を先に除き、それから範囲の中の候補を無限の罰点に置き換える。
罰点を除いたソフトハイフンが、一つのテキストのインライン（IR の `Text`）の中にあったときは、その前後の箱を一つの箱として比べる。
範囲を付けた入力では、そのソフトハイフンで語を切らないからである。
つないだ箱の幅は、二つの箱の幅の和に、つないだ文字列の送りと二つの文字列の送りの和との差を足したものとする。
この差は、二つの文字列の境の字のあいだのカーニングである。

### 2. 述語とテスト

`NoBreakEnum` の `i8OnlyBreaks` を S1 の述語に書き換える。
述語は、入力の部品から範囲に触れるソフトハイフンと、部品が属するテキストのインラインを決める。
箱と部品の対応は、箱の `bcAt` で読む。
述語は、部品ごとに原稿の位置をずらした `SrcSpan` をインラインに付け、`ceSourceAt` が字ごとの位置を返す環境で、範囲を付けた入力と外した入力を組む。
こうすると、各箱の最初の字がどの部品の字かが `bcAt` からわかる。
ソフトハイフンの罰点には、その後の最も近い箱の最初の字の直前にあるソフトハイフンを対応させる。
対応させられない罰点は、述語の誤りとして違反にする。
`SrcSpan` と `ceSourceAt` は箱の位置の情報だけを変え、項目の値を変えない（「トレードオフ」の確かめ）。

### 3. 文書

- [ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md) のステータスの行に「（I8）は ADR 0305」を足す。
- [ADR 0297](0297-report-soft-hyphens-next-to-unbreakable-characters-as-g07124.md) のステータスの行に「（N4 の範囲の中のソフトハイフン）は ADR 0305」を足す（「決めたことの記録」の 2）。この注記は、採択のプルリクエストで足す。
- [docs/specifications.md](../specifications.md) の「改行しない範囲」の節に、範囲に触れるソフトハイフンは候補にならず罰点を残さないことを書き、この ADR へのリンクを付ける。今の節は、罰則 10000 の罰点に置き換える候補の列挙にソフトハイフンを含めており、#866 の後の組版と合わない。この列挙からソフトハイフンを除く。
- [docs/specifications.md](../specifications.md) の列挙の検査の段落が I8 を引いているところを、S1 と S2 に書き換える。

組版の振る舞いは変えない。
出力も notice も変わらない。

## 実装しないこと

- 組版のコードを [ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md) の I8 の文に合わせて戻すこと。範囲の境のソフトハイフンに罰点 50 を残すと、[ADR 0285](0285-read-soft-hyphens-at-inline-boundaries-in-the-joined-word.md) の 2 に反する。範囲の中のソフトハイフンに罰則 10000 の罰点を戻すと、[ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md) の I3 に反する。
- 範囲に触れるソフトハイフンを入力から消した段落を比べる相手にすること。[ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md) の I4 により、ソフトハイフンを含む要素はパターンで分綴しない。ソフトハイフンを消すと要素がパターンで分綴され、項目が変わる。深さ 3 までで、隣の部品が範囲の部品であるソフトハイフンを消して比べる試作の述語を走らせると、19,180 個の入力で違反を返した。
- 改行しない範囲の列挙の上限を変えること。プルリクエストで 2 部品、毎晩で 3 部品のままとする。
- [ADR 0297](0297-report-soft-hyphens-next-to-unbreakable-characters-as-g07124.md) の N4 の文を直すこと。#866 の変化は、[ADR 0297](0297-report-soft-hyphens-next-to-unbreakable-characters-as-g07124.md) のステータスの行の注記で扱う（「決めたことの記録」の 2）。

## 不変条件

段落の入力と項目の並びは、[ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md) の「不変条件」の定義のとおりとする。
比べる項目の値は、今の述語と同じく、箱の幅と文字列、グルーの幅と伸縮、罰点の幅と罰則と種類である。

- **S1 範囲は候補を消すだけ**（[ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md) の I8 を置き換える）：`lkNoBreak` をすべて偽にした入力の項目の並びに、次の二つをこの順に当てたものが、もとの入力の項目の並びに等しい。
  1. 範囲に触れるソフトハイフンの罰点を除く。そのソフトハイフンの前後の箱が一つのテキストのインライン（IR の `Text`）から出たものなら、二つを、文字列をつないだ一つの箱にする。その幅は、二つの箱の幅の和に、つないだ文字列の送りと二つの文字列の送りの和との差を足したものである。
  2. 残った候補のうち、前の最も近い字と後の最も近い字がどちらも範囲の字であるものを、無限の罰点に置き換える。グルーの候補では、グルーの前に罰則 10000 の罰点を置く。
- **S2 範囲に触れるソフトハイフンは罰点を残さない**：範囲に触れるソフトハイフンの位置には、`SoftHyphen` の罰点が、罰則によらず一つもない（[ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md) の I3 を、範囲の境まで含めて読むもの）。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| ソフトハイフンの前の部品 | 範囲の外の字、範囲の中の字、句読点、なし |
| ソフトハイフン自身 | 範囲の外、範囲の中 |
| ソフトハイフンの後の部品 | 範囲の外の字、範囲の中の字、句読点、なし |
| 前後の部品の語 | `a`、`table`、`hyphenation`、`lime-tree` |
| 一つのテキストのインラインか | ソフトハイフンと前後の字が一つのインライン、前か後でインラインが分かれる |

## テスト設計

テストを先に書き、今の述語で失敗することを確かめてから述語を直す。
テストの名前には S1、S2 の番号を入れる。

- **S1 の回帰**：42777778394 の最小の入力 `Input 0 [(PText "a",False),(PText "\173",False),(PText "a",True)] 0 2` で、S1 の述語が違反を返さないこと。今の `i8OnlyBreaks` は I8 の違反を返すので失敗する。
- **S1 の範囲の中**：`Input 0 [(PText "a",True),(PText "\173",True),(PText "a",True)] 0 2` で、S1 の述語が違反を返さないこと。今の述語は箱の数の違いを返すので失敗する。
- **S1 の述語のテスト**：最小の入力の項目に、範囲の境に罰点 50 の `SoftHyphen` を足したものを、S1 の述語が違反として返すこと。範囲の中の入力 `Input 0 [(PText "a",True),(PText "\173",True),(PText "a",True)] 0 2` の項目の箱 `aa` を、箱 `a`、罰則 10000 の `SoftHyphen` の罰点、箱 `a` に置き換えたものも、違反として返すこと。
- **S2**：境界の入力の表の組で、範囲に触れるソフトハイフンの位置に `SoftHyphen` の罰点がないこと。
- **列挙**：`GOLEM_ENUM_NOBREAK_DEPTH=3` で、改行しない範囲の列挙のすべての入力が S1、S2、I7 を満たすこと。手元で走らせ、毎晩のジョブでも確かめる。

## トレードオフ

- S1 は I8 より長い。範囲に触れるソフトハイフンを決めるために、述語がつないだ語の読み方（[ADR 0285](0285-read-soft-hyphens-at-inline-boundaries-in-the-joined-word.md)）を持つ。組版のコードと同じ読み方を述語に書き写すので、両方が同じ誤りを持つおそれがある。S2 と、`JoinedWordEnum` の N4 のテストが、別の向きからこれを確かめる。
- 最初の試作の述語（範囲の字を `lkColor` で印し、罰点の両側の箱から範囲に触れるかを決めるもの）は、896 個の入力で違反を返した。896 個の部品の並びは 32 通りで、どれも範囲の中のソフトハイフンが範囲の外の語に挟まれる形か、範囲の外のソフトハイフンが範囲の中の語に挟まれる形であった。前者は、ソフトハイフン自身の範囲を箱から読めないこと、後者は、別のテキストのインラインの箱をつないだことによる、試作の誤りである。「実装すること」の 2 の述語は、範囲に触れるかとテキストのインラインを入力の部品から決め、この二つを直したものである。
- 「実装すること」の 2 の述語を、`main`（`db145a81`）の組版で、深さ 3 までのすべての入力 511,812 個に通した。述語は作業用のモジュールに書き、`cabal repl golem-layout-test -v0` に `:set -Wwarn -Wno-missing-home-modules -fobject-code -O1`、`:load`、`GHC.Conc.setNumCapabilities 8` を与えて走らせた。S1、S2、I7 の違反と、罰点とソフトハイフンを対応させられない入力は、どれも 0 個であった。位置を付けた環境と付けない環境で項目の値が違う入力も、0 個であった。今の `i8OnlyBreaks` を同じ入力に通すと、違反は 3,136 個で、「文脈」の数と同じである。S1 の 1 で罰点を除いた入力は 3,136 個、そのうち箱をつないだ入力は 448 個であった。
- 述語が違反を見逃さないことも、同じ作業用のモジュールで確かめた。42777778394 の最小の入力の項目に、範囲を外した入力の罰点 50 の `SoftHyphen` を二つの `a` のあいだに足すと、述語は S1 と S2 の違反を返した。`Input 0 [(PText "a",True),(PText "\173",True),(PText "a",True)] 0 2` の箱 `aa` を、箱 `a`、罰則 10000 の `SoftHyphen` の罰点、箱 `a` に置き換えても、S1 と S2 の違反を返した。
- カーニングは、テストの環境の `ceWordAdvance` に、隣り合う二つの英字ごとに -1/16 字を足して確かめた。深さ 3 で、箱の幅を二つの箱の幅の和で比べる述語は、箱をつないだ 448 個の入力のすべてで S1 の違反を返した。そのため、S1 のつないだ箱の幅に、つないだ文字列の送りと二つの文字列の送りの和との差を足すことにした。この幅で比べると、カーニングのある環境でもない環境でも、511,812 個の入力の違反は 0 個であった。実際の書体のカーニング（HarfBuzz で組む語の送り）での確かめは未確認である。列挙は今の述語と同じ書体の設定で走らせる。

## 決めたことの記録

2026-11-10 に tett23 が次の三つを決めた。

1. **I8 の扱い**：I8 を S1 で置き換えるか、範囲に触れるソフトハイフンを含む入力を I8 の対象から外して S2 と I7 だけで確かめるかを問うた。tett23 の答えは「S1」であった。対象から外す案のほうが述語は短いが、範囲に触れるソフトハイフンを含む入力で、範囲がほかの項目を変えていないことを確かめなくなる。
2. **[ADR 0297](0297-report-soft-hyphens-next-to-unbreakable-characters-as-g07124.md) の N4**：#866 は、範囲の中のソフトハイフンの項目を変えた（罰則 10000 の罰点がなくなり、語が一つの箱になった）。行の分け方は変わらない。これを [ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md) の I3 に対する修正として認め、[ADR 0297](0297-report-soft-hyphens-next-to-unbreakable-characters-as-g07124.md) のステータスの行に注記するかを問うた。tett23 の答えは「2 (b)注記して」であった。採択のプルリクエストで、[ADR 0297](0297-report-soft-hyphens-next-to-unbreakable-characters-as-g07124.md) のステータスの行に「（N4 の範囲の中のソフトハイフン）は ADR 0305」を足す。
3. **採択**：S1 を確かめた後、tett23 はこの ADR を採択した。答えは『「0305」採択』であった。

## 参考文献

- `enum.yml` の実行 42777778394 のログ（`gh run view 42777778394 --repo tett23/golem --log-failed`）
- [ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md)
- [ADR 0285](0285-read-soft-hyphens-at-inline-boundaries-in-the-joined-word.md)
- [ADR 0297](0297-report-soft-hyphens-next-to-unbreakable-characters-as-g07124.md)
- プルリクエスト [#836](https://github.com/tett23/golem/pull/836)、[#866](https://github.com/tett23/golem/pull/866)、[#889](https://github.com/tett23/golem/pull/889)
