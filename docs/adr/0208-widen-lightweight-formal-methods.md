# ADR 0208: 軽量な形式手法を、ページ分割のほかの範囲に広げる

ステータス: 採択

## 文脈

### 試験導入の結果

[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) は、ページ分割の規則を不変条件として書き、小さな入力のすべてで確かめる手法を、試験として入れた。
実装（PR #641、2026-11-08）の結果は次のとおりである。

- 仕様書の「既知の不具合」にあった、図版を追い越した見出しを、列挙が見つけた。最も小さい反例は、段の行の数 C = 3 の `[EPara 2, EFigure 2, EHeading, EPara 1]` であり、追い越しがなくても起きる。
- 新しい違反を二つ見つけた。送った図版の後の改丁の見出しが偶数ページに置かれる（I8）ものと、送った図版の後の見出しの注が次のページに送られる（I7）ものである。どちらも C = 3、要素 3 個か 4 個で起きる。
- [golem-layout ADR 0021](../golem-layout/adr/0021-keep-with-next-counts-widow-and-orphan.md) が直した形（見出しの後の 3 行の段落）も、その ADR が入る前の main で見つけていた。
- 述語を書く段で、仕様書から一つに決まらない箇所が 5 つ出た（段より高い図版、見出しだけの段の後の孤立行と寡婦行、改丁の見出しが続く見出し、改丁の前の送った図版、[golem-layout ADR 0021](../golem-layout/adr/0021-keep-with-next-counts-widow-and-orphan.md) の後の I6 の行の数）。
- Alloy のモデルが出した両立しない規則の組は、貪欲法と、孤立行、寡婦行、見出しの規則の組だけであり、どれも仕様書が優先を決めていた。[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) のテスト設計が期待した「見出しと図版を送る規則」の組は出ず、図版を追い越した見出しは規則の矛盾ではなく実装の不具合とわかった。
- 保守の量は、列挙の部品（[`Golem.TestSupport.Enum`](https://github.com/tett23/golem/blob/499f6d95fd32c1188555a81c8f4b60c0cc612d83/modules/golem-test-support/src/Golem/TestSupport/Enum.hs)）が 138 行、ページ分割の列挙、述語、テストが 795 行である。

[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の準備で置いた成功の基準（既知の不具合を見つけ、新しい違反か曖昧さを一つ以上見つけ、プルリクエストの CI の延びが 30 秒以内）は満たした。
ただし、最後の一つは、プルリクエストの上限を [ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の推奨の 5 個から 3 個に下げて満たしたものである。

### 列挙の増え方

上限を下げたのは、入力の数が要素の数とともに指数的に増えるためである。
ページ分割の列挙は、段の行の数（3 から 8）と段の数（1 と 2）の 12 通りの組ごとに、17 から 22 の要素の候補の並びを作る。
要素を一つ増やすと、入力はおよそ 20 倍になる。

| 要素の数の上限 | 入力の数 | x86-64 の CI での golem-layout のテストの延び |
| --- | --- | --- |
| 3 | 95,870 | 4.0 秒 |
| 4 | 1,910,980 | 53.8 秒 |
| 5 | 38,357,494 | （手元で 8〜13 分） |
| 6 | 775,040,892 | |
| 7 | 15,758,794,638 | |

範囲を行分割や表に広げれば、列挙は範囲の数だけ増える。
同じやり方のままでは、範囲を一つ足すごとに、プルリクエストの上限を下げることになる。
入力を減らす工夫を、範囲を広げる前に入れておきたい。

### 入力を減らす工夫の見積もり

入力の減らし方を四つ考え、ページ分割の列挙で測った。
測ったのは、[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の述語をすべての入力に当て、違反の種類ごとに、見つかった入力の数と、最も小さい段と、最も小さい C を数えるプログラムである（main には入れていない）。
時間は手元の Apple Silicon（10 コア）での値であり、CI の x86-64 とは違う。
同じ手元で、今のテスト（上限 4）は 36.8 秒かかり、CI では 53.8 秒であった（CI は手元の約 1.5 倍）。

**型ごとの上限**：入力の要素を、境界の値に絞る。
[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の「境界の入力」の表は、図版の行の数として 1、C − 1、C、C + 1 を挙げているが、列挙は 1 から C + 1 までのすべてを作っている。
図版を表の四つの値に絞ると、C = 8 では候補が 22 から 17 に減る。

**段の行の数の上限**：段の行の数を 3 から 5 に絞る。
段落は 4 行まで、図版は C + 1 行までなので、C が 6 以上の段では、要素が段の境目に当たるのは、いくつかの要素が積み重なったときだけになる。
PR #641 の反例はどれも C = 3 か 4 であった。

| 列挙 | 段の行の数 | 図版の行の数 | 上限 4 の入力 | 上限 5 の入力 | 上限 6 の入力 |
| --- | --- | --- | --- | --- | --- |
| [ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) のまま | 3 から 8 | 1 から C + 1 | 1,910,980 | 38,357,494 | 775,040,892 |
| 型ごとの上限 | 3 から 8 | 1、C − 1、C、C + 1 | 1,064,892 | 18,103,176 | 307,754,004 |
| 段の行の数の上限 | 3 から 5 | 1 から C + 1 | 674,906 | 12,245,954 | 222,637,302 |
| 両方 | 3 から 5 | 1、C − 1、C、C + 1 | 532,446 | 9,051,588 | 153,877,002 |

上限 4 では、四つの列挙のどれもが、[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) のままの列挙と同じ違反を、同じ段で見つけた。
I6 と I7 は要素 4 個の段で、I8 は要素 3 個の段で最初に現れ、最も小さい C はどれも 3 である。
両方を当てた列挙は、上限 5 でも同じであった（違反した入力は I6 が 86,300、I7 が 19,693、I8 が 203,716）。
一段で増える倍率は 20 から 17 に下がるだけだが、上限 6 では入力が約 5 分の 1 になる。

測る途中で、もう一つ短くできるところが見つかった。
今のテストは、違反を探す走査と、既知の不具合の数を数える走査を別に行い、形の条件に当たる入力を二度組む。
一つの走査で両方を数えるプログラムは、[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) のままの列挙の上限 4 を 23.6 秒で調べた（今のテストは 36.8 秒）。

**中間表現での重複の除去**：二つの入力が、検査する関数に渡る値（ページ分割なら `[Flow]`、行分割なら Knuth と Plass の項目の並び）で同じなら、一つだけを調べる。
ページ分割の列挙は、要素の並びから流れを一つずつ作るので、同じ流れは生まれず、この工夫は役に立たない。
行分割では、組み方の環境の 8 通りのうち、入力の字が関わらない設定（長音記号のない並びでの禁則の strict と loose など）が同じ項目を作るので、役に立つ見込みがある。
除いてよいことは、除く前と除いた後とで違反の集まりが同じことを、小さな上限で確かめれば示せる。

**並列化**：一つの段の入力を、プロセッサの数に分けて調べる。
CI の runner は 4 コアであり、毎晩のジョブはほかのテストと同時には走らないので、ほぼ 4 倍の速さになる見込みである。
最も小さい反例を返すことは、段の中の位置の最も小さい違反を選べば保てる。
両方を当てた列挙の上限 4 は、1 コアで 12.0 秒、4 コアで 3.0 秒であり、ほぼ 4 倍になった。
上限 5 は 4 コアで 66.5 秒であった。
ただし、GHC の並列のごみ集め（GC）を止め（`-qg`）、割り当ての領域を広げた（`-A64m`）ときに限る。
既定の RTS の設定では 8.4 秒であり、1.4 倍にとどまった。
[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) のままの列挙では、同じ設定で 23.6 秒から 12.8 秒であり、1.8 倍にとどまった。
差の原因は調べていない。

ほかに二つを考えて、退けた。
一つは対称性の除去である。
ページ分割の入力には、入れ替えても結果が同じになる要素の組がほとんどない（注のある段落と注のない段落は別の規則に当たる）。
もう一つは、ページ分割の途中の状態をまとめる方法（同じ状態に至った前半の並びの、後半を一度だけ調べる）である。
状態空間の探索として大きく役に立つ可能性はあるが、述語が実装の内部（`St`）を読まないという [ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の決めごとに反し、テストが実装の構造に縛られる。

上限より大きい入力は、すべてを調べる代わりに抜き取れる。
種を固定した擬似乱数で、上限より一つか二つ大きい段の入力を決まった数だけ作れば、同じコミットでは同じ入力を調べる（[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) が時間で上限を決める案を退けた理由は、ここでは当たらない）。
抜き取りで見つけた反例は最も小さいとは限らないので、要素を一つずつ取り除いても違反が残るかぎり取り除き、残ったものを示す。

### LiquidHaskell と SBV

[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) は、LiquidHaskell と SBV を範囲を広げる ADR で決めるとした。
手元で次のことを確かめた（2026-11-08）。

**LiquidHaskell**：GHC 9.10.3 で動くのは 0.9.10.1.2（liquidhaskell と liquidhaskell-boot、liquid-fixpoint 0.9.6.3.2）である。
liquidhaskell-boot 0.9.10.1.2 は `ghc ^>= 9.10` に依存し、Hackage の次の版 0.9.12.2 は GHC 9.12 に上がっている。
scratch の cabal のプロジェクトで、依存は golem の `cabal.project.freeze` にない 38 のパッケージを足し、手元で約 29 分かけて作れた（ほかのビルドと同時）。

- モジュールの頭に `{-# OPTIONS_GHC -fplugin=LiquidHaskell #-}` を書いたモジュールだけを検査し、書かないモジュールは普通に作る。モジュールごとに入れられる。
- 検査はコンパイルのときに Z3 を呼ぶ。Z3 が PATH にないと、プラグインは「LiquidHaskell requires an SMT Solver」と止まり、モジュールを作れない。
- 小さな仕様は通った。`Golem.Syntax.Position` の `utf16LeadUnits` の値が 0 から 2 であること、`utf16Units` が負にならないこと、`lineOf` の二分探索の値が `[lo, hi]` にあり停止すること（停止の尺度 `hi - lo` を書いた）、`start <= end` を型に持つ区間、`divSp` の `q * n <= x < q * n + n`。わざと `start > end` の区間を作る関数は、型の不一致として退けた。
- `Golem.Syntax.Position` をそのまま写したモジュールは、注釈なしでは通らなかった。一つめに、二分探索の再帰の停止を示せなかった。二つめに、停止の検査を止めても、`c < BS.length bytes && isContinuation (BS.index bytes c)` の `BS.index` の範囲を、`&&` の左の条件から知ることができず、誤りとして報告した。LiquidHaskell で検査するには、今のコードを書き換えることになる。

**SBV**：Hackage の最新は 14.9（`base >= 4.19.2`）であるが、手元の Hackage の索引が古いため、索引にある最新の 14.8 で確かめた。
golem の `cabal.project.freeze` にない 12 のパッケージ（libBF、haskell-src-exts、haskell-src-meta、th-orphans など）を足し、GHC 9.10.3 で作れた。
Z3 は、証明を走らせるときにだけ要る。

`SInteger` の上に書き直した golem の式について、次を Z3（手元の `z3` 5.3.2）で証明した。
四つの証明と二つの反例の検査を合わせて、`cabal run` で約 5 秒であった。

- `Golem.Length.divSp`：`n > 0` なら `q * n <= x < q * n + n`。
- `Golem.Length.Decimal.roundHalfEven`：すべての整数 `n` と正の `d` で、`2 |n − r d| <= d` であり、ちょうど半分のときは `r` が偶数。わざと書いた四捨五入（半分を切り上げる）は、`n = −7`、`d = 2` の反例で退けた。
- `toSp Mm`（1 mm = 23592960/127 sp）：すべての有理数 `a/b` で、丸めの誤差が半 sp 以下。
- `Golem.Layout.Paginate.headingBlock`：段の行の数が見出しを収め、`least` でないかぎり一行少なくすると収まらず、上の空きが負にならない。見出しの送りの丸めは、丸めの性質だけを制約として書いた。仮定が矛盾していないことは、仮定の下で偽の命題に反例が出ることで確かめた。

どれも、証明したのは SBV の型で書き直した式であり、golem のコードそのものではない。
書き直した式と golem の関数が一致することは、別に確かめる必要がある（整数の範囲を列挙して両方を比べるなど）。

### Alloy の運用

[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の Alloy のモデルは、ADR を書く段で規則の矛盾を探す道具として、一度役に立った。
期待した矛盾が出なかったことで、図版を追い越した見出しを、規則の優先を決める ADR ではなく、実装を直す ADR で扱えるとわかった。
モデルは 1 ファイル（[docs/golem-layout/models/pagination.als](../golem-layout/models/pagination.als)）であり、走らせ方は README に書いてある。
一方で、モデルは実装と別に書くので、規則を変える ADR がモデルを直し忘れても、気付く仕組みがない。

### 範囲の候補

[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の準備で、範囲の候補を、境界のバグの証拠と手法で並べた。

| 範囲 | 境界のバグの証拠 | 手法 |
| --- | --- | --- |
| 和文の行分割（`Golem.Layout.Japanese`、`KnuthPlass`） | [golem-layout ADR 0016](../golem-layout/adr/0016-ellipsis-before-full-stop.md)、最後の行分割の段階の送り出し、[ADR 0172](0172-continuous-double-dashes.md) | 列挙と不変条件、素朴な最適化の探索との比べ |
| 表の列の幅（`Golem.Layout.Table`） | [golem-driver ADR 0037](../golem-driver/adr/0037-table-column-widths.md)（短い列から満たし、セルの最後の二字を保つ） | 列挙と不変条件 |
| パーサーと `golem fmt` の往復 | keep の行の末尾のエスケープした空白（[golem-parser ADR 0012](../golem-parser/adr/0012-keep-trailing-escaped-space.md)、G0279）、表のファイルの往復の改行（[ADR 0186](0186-fmt-table-files.md)） | 文法から作る短い原稿の列挙と、往復と diagnostics の位置の不変条件 |
| 位置の変換（UTF-16 の列、`pages.json`、LSP） | [golem-lsp ADR 0003](../golem-lsp/adr/0003-position-handling.md)、[ADR 0195](0195-page-start-positions-of-pdf.md) の 0 字の見出しの区間 | サロゲートペアを含む短い文字列の列挙、LiquidHaskell |
| 長さの換算と丸め（golem-length、`headingBlock`） | SVG の回転の行列の最後の桁 | SBV、整数の範囲の列挙 |
| ページ分割の残りの要素（罫線、コード、段の切り替え、手での制御） | [ADR 0017](0017-forced-page-breaks.md)、[ADR 0030](0030-manual-page-break-control.md)、[ADR 0046](0046-blank-line-command.md)、[golem-driver ADR 0035](../golem-driver/adr/0035-paragraph-rules-split-and-space-units.md)、[golem-layout ADR 0022](../golem-layout/adr/0022-no-page-break-counts-spaces.md) | [ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の列挙に要素を足す |
| LSP の編集の順序 | [golem-lsp ADR 0005](../golem-lsp/adr/0005-keystroke-latency-and-ordered-evaluation.md) | TLA+。今のバグの傾向に合わない |

## 実装すること

### 1. 範囲ごとの ADR と順

範囲ごとに一つの ADR を書き、ADR ごとに一つのプルリクエストで実装する。
各 ADR は、CLAUDE.md の規則のとおり「不変条件」の節を持ち、[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) と同じ形（列挙、述語、既知の不具合の一覧、反例の表示、毎晩のジョブ）で実装する。
順は、見込める成果の大きい順とする（「メンテナーが決めること」の 1）。

| 順 | 範囲 | ADR | 前提 |
| --- | --- | --- | --- |
| 1 | 和文の行分割 | [ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md) | この ADR の 2 と 3 |
| 2 | 表の列の幅 | 未作成 | 1 の結果 |
| 3 | パーサーと `golem fmt` の往復 | 未作成 | 文法から原稿を作る部品（peg-hs の文法を読む） |
| 4 | 位置の変換 | 未作成 | |
| 5 | 長さの換算と丸め | 未作成 | |
| 6 | ページ分割の残りの要素 | 未作成 | PR #641 の違反を直す ADR |

行分割を最初にするのは、境界のバグの証拠が最も多く、入力が字の並びだけで作れ、素朴な探索という、ページ分割になかった確かめ方を足せるからである。
表の列の幅は、入力（列ごとの最小の幅と自然な幅、使える幅）が整数の小さな組で作れるが、[golem-driver ADR 0037](../golem-driver/adr/0037-table-column-widths.md) の後のバグの報告はまだない。
パーサーの往復は、見込める成果は大きいが、文法から原稿を作る部品を先に作る必要がある。
位置の変換と長さの換算は、コードが小さく、今のテスト（hedgehog の性質）でもかなり確かめている。
ページ分割の残りの要素は、PR #641 の違反を直す ADR が入ってから足す。
直す前に要素を足すと、既知の不具合の一覧が、直す ADR と同時に変わる。

LSP の編集の順序には、形式手法を当てない。
[golem-lsp ADR 0005](../golem-lsp/adr/0005-keystroke-latency-and-ordered-evaluation.md) が直したのは、キー入力を遅らせずに編集を順に評価することであり、規則が端で重なる形のバグではない。
並行の振る舞いを調べる TLA+ を入れる手間に、今のバグの傾向が見合わない。

### 2. 列挙の部品を足す

golem-test-support の `Golem.TestSupport.Enum` に、次を足す。

- **並列の検査**：`checkAllPar` は、`checkAll` と同じ値を返す。段ごとに、段の入力をプロセッサの数に分けて調べ、違反のあった入力のうち段の中の位置が最も小さいものを返す。使うテストの部品は `-threaded "-with-rtsopts=-N -qg -A64m"` で作る（[`rts-capabilities.sh`](https://github.com/tett23/golem/blob/499f6d95fd32c1188555a81c8f4b60c0cc612d83/scripts/ci/rts-capabilities.sh) の規則）。
- **重複の除去**：`nubTiersOn :: Ord k => (a -> k) -> Tiers a -> Tiers a` は、キーが同じ値のうち、最も小さい段の最初のものだけを残す。キーには、検査する関数に渡る中間の値を使う。
- **抜き取り**：`sampleT :: Word64 -> Int -> (SplitMix -> (a, SplitMix)) -> [a]` は、種と、数と、擬似乱数の状態から入力を一つ作る関数から、決まった入力の並びを作る。擬似乱数は SplitMix64 を書き直す（Steele、Lea、Flood の算法。Hackage の splitmix は BSD-3-Clause だが、使うのは数十行である）。
- **反例を小さくする**：`shrinkList :: ([a] -> Bool) -> [a] -> [a]` は、要素を一つ取り除いても述語が真であるかぎり、先頭から順に取り除く。

### 3. ページ分割の列挙を短くする

[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の 2 の列挙を、次のように変える。

- 段の行の数：3 から 8 を、3 から 5 にする。
- 図版の行の数：1 から C + 1 までを、1、C − 1、C、C + 1 にする。
- 既知の不具合の数を数える検査を、違反を探す検査と一つの走査にまとめる。
- 毎晩のジョブでは、`checkAllPar` を使う。
- 毎晩のジョブで、段の行の数 6 から 8 と図版の行の数のすべてを含む [ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の列挙から、上限の一つ上の段を抜き取って調べる（2 の抜き取り）。3 で除いた入力を、毎晩の抜き取りで補う。

上限は、プルリクエストでは 3 のまま、毎晩のジョブでは 6 とする（「メンテナーが決めること」の 6）。
プルリクエストの上限 3 の入力は 31,320 になり、今の 95,870 より少ない。
毎晩の上限 6 は、手元の 4 コアで上限 5 が 66.5 秒であることと一段の倍率 17 から、手元で約 19 分、CI で約 30 分と見込む。
実装のときに CI で測り、30 分を超えるなら上限を 5 にし、6 を抜き取りに回す。
既知の不具合の一覧の数（`kbCounts`）は、新しい列挙で数え直して固定する。

### 4. CI の予算

- **プルリクエスト**：範囲ごとの列挙のテストは、x86-64 の `tests-rest` で 10 秒以内に収める。すべての範囲の和は 30 秒以内とする（[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の成功の基準と同じ値）。上限は、範囲の ADR を実装するときに測って決める。
- **毎晩のジョブ**（`enum.yml`）：すべての範囲の和を 60 分以内に収め、ジョブの時間の上限は 90 分のままとする。範囲ごとに段（step）を分け、それぞれ上限と抜き取りの数を環境の変数で渡す。予算を超えた範囲は、上限を一つ下げ、下げた段を抜き取りに回す。
- **環境の変数**：`GOLEM_ENUM_DEPTH` は、ページ分割の上限として残す。範囲ごとに `GOLEM_ENUM_<範囲>_DEPTH` と `GOLEM_ENUM_<範囲>_SAMPLES` を足す（「メンテナーが決めること」の 4）。

### 5. ADR の段での Alloy

規則を足すか変える ADR のうち、その範囲に Alloy のモデル（`docs/<モジュール>/models/`）があるものは、モデルを直して走らせ、結果をモデルの README と ADR の「テスト設計」に書く。
モデルのない範囲では、規則が三つ以上の他の規則と端で重なる ADR だけが、新しくモデルを書く。
モデルは CI で走らせない（[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の決めごとのまま）。
docs/roadmap.md の「手で確かめる項目」の、ページ分割のモデルを走らせ直す項目を、モデルのあるすべての範囲に広げる。

### 6. LiquidHaskell と SBV

LiquidHaskell は入れない（「メンテナーが決めること」の 5）。
SBV は、この ADR では入れず、長さの換算と丸めの範囲の ADR で、golem-length のテストにだけ入れるかを決める。
Z3 と Alloy は CI に入れない。
SBV を入れると決めた ADR が、Z3 の公式の配布物を SHA-256 で固定して取るスクリプト（`scripts/fetch-wasmtime.sh` と同じ形）を足す。

### 7. 文書

- `CONTRIBUTING.md` に、範囲ごとの列挙のテストを手元で走らせる方法と、抜き取りで見つけた反例を例にする手順を書く。
- README の CI のジョブの表の `enum.yml` の行を、範囲ごとの段に書き直す。
- docs/roadmap.md に、1 の表の未作成の ADR を「まだ実装していない項目」として足す。

### パッケージの依存

golem のパッケージのあいだの `build-depends` は変えない。
golem-test-support に Hackage のパッケージは足さない（SplitMix64 は書き直す）。

## 不変条件

列挙の部品と、短くしたページ分割の列挙について、次が成り立つ。

- **E1 並列の検査は同じ値を返す**：どの上限、列挙、述語でも、`checkAllPar` は `checkAll` と同じ値を返す。プロセッサの数によらない。
- **E2 重複の除去はキーを漏らさない**：`nubTiersOn k xs` の上限までの値のキーの集まりは、`xs` の上限までの値のキーの集まりに等しく、同じキーは一度しか現れない。残した値は、そのキーを持つ値のうち、最も小さい段の最初のものである。
- **E3 抜き取りは決まっている**：同じ種、数、入力を作る関数からは、いつも同じ入力の並びを作る。
- **E4 小さくした反例は、まだ違反する**：`shrinkList p xs` は `p` を満たし、どの一つの要素を取り除いても `p` を満たさない（`p xs` が真のとき）。
- **E5 短くした列挙は、元の列挙の一部**：3 の列挙の上限までのどの入力も、[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の列挙の同じ段にある。
- **E6 短くした列挙は、既知の反例を含む**：PR #641 が示した最も小さい反例（図版を追い越した見出し、改丁、見出しの注、[golem-layout ADR 0021](../golem-layout/adr/0021-keep-with-next-counts-widow-and-orphan.md) の前の見出し）は、どれも 3 の列挙の同じ段にある。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 段の入力の数 | 0、1、プロセッサの数より少ない、ちょうど割り切れる、一つ余る |
| 違反のある入力 | なし、段の最初、段の最後、同じ段に二つ（並列の分け方の別々の組に） |
| キーが同じ値 | なし、同じ段に二つ、別の段に二つ |
| 抜き取りの数 | 0、1、段の入力の数より多い |
| 反例の要素の数 | 0、1、取り除けない要素だけ |

## 実装しないこと

- **範囲ごとの列挙と述語**：1 の表の範囲は、それぞれの ADR で決める。この ADR の後に書くのは、行分割の [ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md) だけである。
- **ページ分割の違反を直すこと**：PR #641 の違反と仕様書の曖昧さは、別の ADR で扱う。
- **状態空間の探索**：ページ分割の途中の状態をまとめる方法（「文脈」）。
- **Alloy と Z3 を CI に入れること**：6 の結論による。
- **TLA+**：LSP の編集の順序には当てない。

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。

### 列挙の部品（golem-test-support のテスト）

- E1：大きさの違う段を持つ列挙と、違反の位置を変えた述語で、`checkAllPar` と `checkAll` の値が等しいこと。境界の表の段の入力の数と違反の位置をすべて試す。テストの部品を `-N1` と `-N4` で走らせても同じであること。
- E2：キーの関数を、恒等、定数、偶奇にしたとき、キーの集まりと残した値が、素朴に作ったものと一致すること。
- E3：同じ種で二度作った並びが等しく、種を変えると（少なくとも一つの種の組で）違うこと。SplitMix64 の最初のいくつかの値が、論文の参照の実装の値と一致すること。
- E4：手で作った述語（「3 を含む」「長さが 2 以上」など）で、結果が述語を満たし、どの要素を取り除いても満たさないこと。

### ページ分割の列挙（golem-layout のテスト）

- E5：上限 3 までの新しい列挙の入力が、[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の列挙に含まれること。
- E6：PR #641 の四つの反例が、新しい列挙のそれぞれの段にあること。
- 既知の不具合の一覧の数を、新しい列挙で数え直した値に固定すること。

### 道具と CI

自動のテストを書けないものは、実装の後に次を確かめる。

- 毎晩のジョブの範囲ごとの時間を、最初の三回の実行で測り、予算に収まることを PR の説明と README に書く。
- プルリクエストの CI の golem-layout のテストの延びが、3 の変更の前より短いか同じであること。

## トレードオフ

段の行の数を 5 までにすると、6 から 8 の段でだけ起きる違反は、プルリクエストでは見つからない。
今の反例はどれも C = 3 か 4 で起きているが、それは列挙が小さい要素から調べたためでもあり、大きな段でだけ起きる違反がないことは示していない。
毎晩の抜き取りで 6 から 8 の段を調べて、その分を補う。
抜き取りは漏れを許すので、見つかるのは main に入った後であり、見つからないこともある。

図版の行の数を境界の値に絞ると、境界の表に載っていない値（C = 8 での 3 行の図版など）でだけ起きる違反を見逃す。
表の値は [ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) が境界として選んだものであり、ほかの値は「段に入るが、境界ではない」図版として 1 行の図版と同じ扱いを受ける見込みである。

並列の検査は、テストの部品を `-threaded` にする。
GHC 9.10.3 の threaded の RTS には、能力の数を実行中に変えると止まる不具合があり、`rts-capabilities.sh` がそれを防いでいる。
`-with-rtsopts=-N` を付けるかぎり、この規則の中に収まる。

抜き取りは、すべての入力を調べる保証を手放す。
その代わり、上限より大きい入力にも手が届く。
最も小さい反例を示す性質は、反例を小さくする手順で補うが、それは局所的に最も小さいものであり、全体で最も小さいとは限らない。

範囲ごとに ADR と PR を分けると、ADR の数が増える。
一つの ADR にまとめると、範囲ごとの不変条件が一つの ADR に並び、実装の PR が大きくなり、一つの範囲の曖昧さが全体の採択を止める。

## メンテナーが決めること

1. **範囲の順**：推奨は、1 の表の順である。
   - 退けた案は、パーサーの往復を最初にすることである。見込める成果は大きいが、文法から原稿を作る部品が先に要り、最初の範囲として実装の量が大きい。
2. **一つの ADR か、範囲ごとか**：推奨は、この ADR を傘にして、範囲ごとに ADR を書くことである。
   - 退けた案は、すべての範囲を一つの ADR にすることである（「トレードオフ」）。
3. **ページ分割の列挙を短くするか**：推奨は、3 のとおり短くし、除いた入力を毎晩の抜き取りで補うことである。
   - 退けた案は、[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の列挙のまま並列化だけをすることである。4 倍速くなっても、入力は一段で約 20 倍になるので、上限は一つも上がらない。
4. **環境の変数**：推奨は、範囲ごとに上限と抜き取りの数の変数を持つことである。範囲ごとに一段の重さが違い、一つの数で上限を揃えられない。
   - 退けた案は、`GOLEM_ENUM=nightly` のような一つの変数で、範囲ごとの毎晩の上限をコードに書くことである。手元で一つの範囲だけ上限を変えて調べられない。
5. **LiquidHaskell と SBV を入れるか**：推奨は、LiquidHaskell を入れず、SBV を長さの換算の範囲の ADR で決めることである。
   - LiquidHaskell を入れない理由は三つある。検査するモジュールを作るすべての環境（手元、CI のすべての行列）に Z3 が要る。liquidhaskell-boot は GHC の版に縛られ、GHC を上げるたびに対応する LiquidHaskell の版を待つ。今のコードは注釈なしでは通らず、`&&` の短絡に頼る範囲の検査のような普通の書き方を書き換えることになる。位置の変換の範囲は、列挙で確かめる。
   - SBV は、Z3 がテストを走らせるときにだけ要り、証明は数秒で済む。ただし、証明するのは書き直した式であり、golem の関数との一致を別に確かめる手間がかかる。長さの換算の範囲は 1 の順で 5 番めなので、そのときに決める。
   - 退けた案は、今の段で SBV を golem-test-support に入れることである。使う範囲がまだなく、12 のパッケージと Z3 を CI に先に入れることになる。
6. **毎晩のジョブのページ分割の上限**：推奨は、短くした列挙で 6 である（3 の見込みで CI で約 30 分）。毎晩の予算 60 分の半分を使うので、ほかの範囲の毎晩の上限は残りの 30 分に収める。
   - 退けた案は、5 のままにして、6 と 7 を抜き取ることである。時間は数分で済むが、短くした列挙の上限 5 は今の毎晩の上限 5 の一部であり、すべてを調べる範囲が今より狭くなる。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-08、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md)、[ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md)、[ADR 0172](0172-continuous-double-dashes.md)、[ADR 0186](0186-fmt-table-files.md)、[ADR 0195](0195-page-start-positions-of-pdf.md)
- [golem-layout ADR 0016](../golem-layout/adr/0016-ellipsis-before-full-stop.md)、[golem-layout ADR 0021](../golem-layout/adr/0021-keep-with-next-counts-widow-and-orphan.md)、[golem-layout ADR 0022](../golem-layout/adr/0022-no-page-break-counts-spaces.md)、[golem-driver ADR 0037](../golem-driver/adr/0037-table-column-widths.md)、[golem-lsp ADR 0003](../golem-lsp/adr/0003-position-handling.md)、[golem-lsp ADR 0005](../golem-lsp/adr/0005-keystroke-latency-and-ordered-evaluation.md)
- Guy L. Steele Jr., Doug Lea, Christine H. Flood. "Fast Splittable Pseudorandom Number Generators". OOPSLA 2014（SplitMix64）.
- Daniel Jackson. Software Abstractions: Logic, Language, and Analysis. Revised edition, MIT Press, 2012.
