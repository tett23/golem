# ADR 0091: golem-pdf と golem-svg のテストの時間切れを CPU 時間で測り、実時間の上限を歯止めに残す

ステータス: 採択（未実装）

## 文脈

### 混んだマシンで落ちる二つのスイート

2026-10-25 のリファクタリングの作業で、二つのレーンが同じ現象に出会った。
origin/main の `cabal test all` を、ほかの作業と同時に走らせると、golem-pdf-test と golem-svg-test がそれぞれ一つか二つのテストで落ちる。
二つのスイートだけを走らせると、どちらも通る（232 と 197 のテスト）。

一つめのレーンの記録では、golem-svg-test が 197 のうち 1 つ、golem-pdf-test が 232 のうち 2 つ落ち、スイートの所要時間はそれぞれ 247.89 秒と 280.42 秒だった。
落ちた理由は三つとも時間切れで、出力には「Timed out after 60s」が二度、「Timed out after 120s」が一度ある。
再実行の案内（`Use -p '...'`）が名指すテストは、golem-svg の「a path of 1,000,001 segments drawn by the drawing itself is not counted」と、golem-pdf の「C3: one stream of 8 MiB named 40 times in Contents is inflated once and written once」である。
golem-pdf の「C3: one stream of 8 MiB named 30 times in Contents counts 8 MiB」にも `TIMEOUT (60.10s)` の行がある。
ただし、この実行はいくつものスイートの出力が行の単位で混ざっており、120 秒の時間切れがどのテストのものかは記録から決められない。
二つめのレーンの記録は、golem-svg-test が 197 のうち 1 つ（58.47 秒）、golem-pdf-test が 232 のうち 1 つ（125.09 秒）落ちたことだけを残している。

時間切れを付けているのは、tasty の `localOption (mkTimeout ...)` である。
golem-pdf-test には 22 箇所（[SecuritySpec](https://github.com/tett23/golem/blob/b9af6f478de3dda7932a81ccf31f065ad7e351a1/modules/golem-pdf/test/SecuritySpec.hs) に 20、[ImageSpec](https://github.com/tett23/golem/blob/b9af6f478de3dda7932a81ccf31f065ad7e351a1/modules/golem-pdf/test/ImageSpec.hs#L277-L287) に 2）、golem-svg-test には 25 箇所（[SecuritySpec](https://github.com/tett23/golem/blob/b9af6f478de3dda7932a81ccf31f065ad7e351a1/modules/golem-svg/test/SecuritySpec.hs) に 24、[NumberSpec](https://github.com/tett23/golem/blob/b9af6f478de3dda7932a81ccf31f065ad7e351a1/modules/golem-svg/test/NumberSpec.hs#L74-L78) に 1）ある。
値の内訳は、0.1 秒が 1、5 秒が 3、30 秒が 29、60 秒が 8、120 秒が 5、300 秒が 1 である。
tasty は時間切れを `System.Timeout.timeout` で実装しており（[tasty 1.5.4 の Run.hs](https://hackage.haskell.org/package/tasty-1.5.4/src/Test/Tasty/Run.hs)）、測るのは実時間である。

### 測った量

測った環境は、Apple silicon の 10 コア、64 GB のメモリの macOS で、GHC 9.10.3、origin/main の 48dd0756 である。
qpdf を入れていないので、golem-pdf-test の 4 つのテストは SKIP になる。
同じマシンでは、ほかの作業のセッションも動いていた。

まず、二つのスイートを一つずつ単独で走らせた。
golem-svg-test は 12.72 秒、golem-pdf-test は 45.49 秒で、どちらも通った。
次に `cabal test all` を三回走らせ、さらに `yes > /dev/null` を 10 個並べて三回、20 個並べて三回走らせた。
九回とも、二つのスイートは通った。
20 個のときは負荷の平均が 264 まで上がり、golem-svg-test は最長で 96.72 秒、golem-pdf-test は 255.51 秒かかった。
単独のときの 7.6 倍と 5.6 倍である。

時間切れに最も近づいたテストを、単独のときと比べると次のようになる。

| テスト | 時間切れ | 単独 | 20 個の負荷の下の最長 |
| --- | --- | --- | --- |
| golem-pdf の「named 40 times … inflated once」 | 60 秒 | 4.81 秒 | 40.63 秒 |
| golem-pdf の「named 40 times, is ContentTooLarge」 | 120 秒 | 7.33 秒 | 36.32 秒 |
| golem-pdf の「named 32 times is refused, of one named 31 times read」 | 300 秒 | 19.74 秒 | 102.19 秒 |
| golem-svg の「a path of 1,000,001 segments」 | 60 秒 | 3.10 秒 | 28.00 秒 |
| golem-svg の「the heaviest arcs within the range」 | 5 秒 | 0.30 秒 | 2.68 秒 |

一つめのテストは、時間切れの 68% まで使った。
レーンが落ちたときの golem-svg-test の所要時間は単独の約 19 倍で、私が作れた負荷よりさらに重い。

実時間が延びても、テストが使う CPU 時間は延びていない。
`/usr/bin/time -p` で一つのテストだけを走らせ、横に並べる `yes` の数を変えた。

| テスト | `yes` の数 | 実時間 | ユーザーの CPU 時間 |
| --- | --- | --- | --- |
| golem-pdf の「named 40 times … inflated once」 | 0 | 5.54 秒 | 5.39 秒 |
| 同上 | 150 | 41.61 秒 | 4.70 秒 |
| 同上 | 250 | 52.08 秒 | 4.80 秒 |
| golem-svg の「a path of 1,000,001 segments」 | 1 | 3.39 秒 | 3.15 秒 |
| 同上 | 200 | 36.45 秒 | 3.08 秒 |

実時間は 7.5 倍から 11 倍に延びたが、CPU 時間は同じか少し短い。
時間切れが数えているのは、テストの仕事の量ではなく、ほかのプロセスに CPU を取られて待った時間である。

落ちる場面は、`taskpolicy -b`（バックグラウンドの QoS）で作れた。
このもとでは、golem-svg の「a path of 1,000,001 segments」が実時間の 60 秒で時間切れになった。
そのあいだに使った CPU 時間は 6.09 秒である。
golem-pdf の「named 40 times … inflated once」は通ったが、実時間は 36.54 秒、CPU 時間は 16.66 秒だった。
同じテストを単独で走らせたときの CPU 時間は 5.15 秒なので、CPU 時間も 3.2 倍に延びている。
Apple silicon の効率のコアで走ると、同じ仕事にかかる CPU 時間が延びるためと考えられる（コアの割り当ては確かめていない）。
つまり、CPU 時間もマシンの状態と無関係ではない。
ただし、その延びはコアの速さの比で頭打ちになり、実時間のように際限なく延びはしない。

### ほかの候補の確かめ

`-with-rtsopts=-N` の capability の数は、原因ではない。
二つのスイートの `ghc-options` は `-rtsopts -with-rtsopts=-T` だけで、`-threaded` を付けていない（[golem-pdf.cabal](https://github.com/tett23/golem/blob/b9af6f478de3dda7932a81ccf31f065ad7e351a1/modules/golem-pdf/golem-pdf.cabal#L51)、[golem-svg.cabal](https://github.com/tett23/golem/blob/b9af6f478de3dda7932a81ccf31f065ad7e351a1/modules/golem-svg/golem-svg.cabal#L40)）。
threaded でない RTS では、tasty の `NumThreads` の既定値は 1 であり（[tasty 1.5.4 の Options/Core.hs](https://hackage.haskell.org/package/tasty-1.5.4/src/Test/Tasty/Options/Core.hs)）、テストは一つずつ走る。
一時ファイルの共有も原因ではない。
時間切れになったテストは、入力をメモリの上で組み立てて読むだけで、ファイルを書かない。
GC の圧力も、主な原因とは言えない。
CPU 時間には GC の時間も入るが、`yes` を並べた表のとおり、負荷の下でも CPU 時間は増えていない。

### CPU 時間では見えない止まり方

CPU 時間だけで測ると、見張れなくなる止まり方がある。
ロックや `MVar` を待ち続けるテストは、CPU をほとんど使わないので、CPU 時間の上限にいつまでも届かない。
今の二つのスイートで時間切れを付けたテストは、メモリの上の計算だけをするので、このように止まる経路は見当たらない。
しかし、実装の誤りで待ちが入れば、そのテストは CPU 時間の上限では止まらない。

そうなると、残る歯止めは CI のスイートの時間切れ（[suite-timeout.sh](https://github.com/tett23/golem/blob/b9af6f478de3dda7932a81ccf31f065ad7e351a1/scripts/ci/suite-timeout.sh#L11)、600 秒）だけである。
[ADR 0073](0073-time-bounds-in-tests.md) が実装しないことに書いたとおり、スイートの時間切れでは、どのテストが止まったかがわからない。
手元の `cabal test` には、スイートの時間切れもない。
今の tasty の時間切れは実時間で測るので、待ち続けるテストもテストごとに止めている。
CPU 時間に切り替えるだけでは、この働きが失われる。

### CI で同じことが起きるか

CI は 4 コアのランナーで `cabal test all` を走らせる（[ci.yml](https://github.com/tett23/golem/blob/b9af6f478de3dda7932a81ccf31f065ad7e351a1/.github/workflows/ci.yml#L243)）。
cabal はいくつものスイートを同時に走らせており、ログの時刻もそれを示している。
main の直近の実行（40137542156）では、golem-pdf-test が 41.32 秒（x86）と 51.19 秒（arm）、golem-svg-test が 11.71 秒と 11.50 秒で、手元の単独の値と同じ程度だった。
直近の 100 回の `ci.yml` の実行（2026-10-24 まで）は、成功が 89、失敗が 9、取り消しが 2 である。
失敗した 9 回のうち 7 回は CI のスクリプトのテストか mise のアクションで、残りの 2 回は golem-cli-test のテストの失敗だった。
golem-pdf-test と golem-svg-test の失敗は一度もない。
今の CI で落ちるには、golem-pdf の「named 40 times … inflated once」が単独のときの 12 倍ほど遅くなる必要がある。
CI ではまだ起きていないが、ランナーの性能や、同時に走るスイートの数が変われば起きうる。

### 実時間で書いた検査の残り

[ADR 0073](0073-time-bounds-in-tests.md) は、時間の上限を止まらないことの検出に限り、値を 30 秒にそろえた。
しかし、[ADR 0073](0073-time-bounds-in-tests.md) の後に入ったテストは、5 秒の時間切れを 3 つ（[ADR 0083](0083-svg-number-lower-limit.md) と [ADR 0084](0084-svg-marker-drawn-segment-limit.md) のテスト）と、0.1 秒の時間切れを 1 つ持つ。
どちらも、[CONTRIBUTING.md](https://github.com/tett23/golem/blob/b9af6f478de3dda7932a81ccf31f065ad7e351a1/CONTRIBUTING.md#L99) の「テストの時間切れを 30 秒にして」という読み方に反している。

0.1 秒の時間切れは、[NumberSpec](https://github.com/tett23/golem/blob/b9af6f478de3dda7932a81ccf31f065ad7e351a1/modules/golem-svg/test/NumberSpec.hs#L74-L78) の「仮数が 60 桁で指数が `-9999` の数を、10 の累乗を作らずに判定する」テストに付いている。
ところが、10 の累乗を作っても、この判定は遅くならない。
仮数を `10^9990` の Integer と比べる素朴な判定は、CPU 時間で 0.66 ミリ秒だった（今の実装は 0.12 ミリ秒）。
0.1 秒の時間切れは、この二つを見分けられない。
働いているのは、混んだマシンで落ちうる短い時間切れとしてだけである。

roadmap の未決事項の「実時間を断言するテスト」は、golem-svg の `linearTime` と、30 秒より長い時間切れを挙げ、実時間に頼らずに確かめる方法が決まっていないとしている。
`linearTime`（[SecuritySpec](https://github.com/tett23/golem/blob/b9af6f478de3dda7932a81ccf31f065ad7e351a1/modules/golem-svg/test/SecuritySpec.hs#L75-L95)）は、属性が 2 万個と 4 万個の要素を読む CPU 時間の比が 4 未満であることを断言する。
注釈は二回の実行が合わせて 1 秒を十分に超えるとしているが、今の実装ではテストの所要時間が 0.12 秒から 0.18 秒しかない。
このテストが見張る重複の検査（[Xml.hs](https://github.com/tett23/golem/blob/b9af6f478de3dda7932a81ccf31f065ad7e351a1/modules/golem-svg/src/Golem/Svg/Xml.hs#L179-L194)）の `Set.member` を、読んだ属性の列を `any` でなめる検査に変えてみた。
二乗の時間がかかり、割り当てはしない変異である。
CPU 時間と割り当ては次のとおりだった。

| 属性の数 | 今の実装の CPU 時間 | 変異の CPU 時間 | 変異の割り当て |
| --- | --- | --- | --- |
| 2 万 | 0.05 秒 | 3.43 秒 | 208 MB |
| 4 万 | 0.11 秒 | 11.41 秒 | 408 MB |
| 8 万 | 測っていない | 34.40 秒 | 827 MB |
| 10 万 | 0.28 秒 | 測っていない | 測っていない |
| 20 万 | 0.57 秒 | 測っていない | 測っていない |
| 40 万 | 1.19 秒 | 測っていない | 測っていない |

変異の割り当ては属性の数に比例しており、割り当ての検査（`linearIn`）では見つからない。
変異の時間は、属性の数を倍にするたびに 3.0 倍から 3.3 倍になる。
線形の部分があるので、4 倍には届かない。
この変異のもとで `linearTime` のテストを三回走らせると、比が 4.007 と 4.43 で二回落ち、一回は通った。
`linearTime` は、見張るはずの二乗の悪化を、比の上限のすぐ上でしか捉えていない。

## 実装すること

### 時間の上限の補助

- golem-test-support に `Golem.TestSupport.TimeLimit` を足し、次の三つを置く。
  - 上限の組 `data TimeLimits = TimeLimits { cpuSeconds :: Integer, wallSeconds :: Integer }`。
  - 二つのスイートが使う値 `hangLimits :: TimeLimits`。CPU 時間が 60 秒、実時間が 300 秒である。値はここ一か所に置き、47 箇所のテストには書かない。
  - `withinTimeLimits :: TimeLimits -> IO a -> IO a`。
- `withinTimeLimits` は次のように振る舞う。
  - 動作を始める前に、プロセスの CPU 時間（`System.CPUTime.getCPUTime`）と単調な時計（`GHC.Clock.getMonotonicTime`）を読む。
  - 見張りのスレッドを `forkIO` で立て、0.1 秒ごとに二つを読む。始めたときから CPU 時間が `cpuSeconds` を超えたら `CpuTimeExceeded` を、実時間が `wallSeconds` を超えたら `WallTimeExceeded` を、動作のスレッドに投げる。表示は、それぞれ `used more than N seconds of CPU time` と `took more than N seconds of wall-clock time` とする。止まった原因が違うので、例外も表示も分ける。
  - 動作が終われば、正常に終わっても例外で終わっても、見張りのスレッドを止める。
  - 動作の値をそのまま返す。
  - threaded の RTS（`Control.Concurrent.rtsSupportsBoundThreads` が真）では、動作を始めずに失敗する。threaded の RTS では tasty がテストを並べて走らせ、プロセスの CPU 時間がほかのテストの分も含むからである。
- 二つの上限は、どちらも止まらないことの検出だけに使う（[ADR 0073](0073-time-bounds-in-tests.md)）。CPU 時間の上限は計算を続けて止まらないテストを、実時間の上限は待ち続けて止まったテストを、テストごとに止める。上限に収まったことは、テストが速いことを意味しない。
- この補助は `base` だけを使う（`System.CPUTime`、`GHC.Clock`、`Control.Concurrent`、`Control.Exception`）。golem-test-support に依存を足さない。[ADR 0087](0087-test-support-dependencies-and-shared-fixtures.md) が足す依存（`bytestring`、`hedgehog`、`text`）にも頼らないので、[ADR 0087](0087-test-support-dependencies-and-shared-fixtures.md) の実装の前でも後でも入れられる。
- golem-svg-test の build-depends に golem-test-support を足す。[ADR 0086](0086-any-test-suite-may-depend-on-test-support.md) により、テストスイートが golem-test-support に依存するのに ADR は要らない。b9af6f47 の時点で、golem-svg-test はまだ依存していない（[golem-svg.cabal](https://github.com/tett23/golem/blob/b9af6f478de3dda7932a81ccf31f065ad7e351a1/modules/golem-svg/golem-svg.cabal#L41-L50)）。[ADR 0086](0086-any-test-suite-may-depend-on-test-support.md) の実装（[#410](https://github.com/tett23/golem/pull/410)）も、2026-10-25 の時点で開いている [ADR 0087](0087-test-support-dependencies-and-shared-fixtures.md) の実装（[#413](https://github.com/tett23/golem/pull/413)）も、golem-svg.cabal を変えていない。golem-pdf-test はすでに依存している（[golem-pdf.cabal](https://github.com/tett23/golem/blob/b9af6f478de3dda7932a81ccf31f065ad7e351a1/modules/golem-pdf/golem-pdf.cabal#L59)）。

### 実時間の上限の値

実時間の上限は 300 秒とし、CPU 時間の上限（60 秒）より十分に大きく取る。
負荷だけでは届かず、CI のスイートの時間切れより先に働く値である。

- 文脈の測定で最も重い負荷（20 個の `yes`）の下でも、golem-pdf-test のスイート全体は 255.51 秒で終わった。300 秒はこれより長い。正しいテストがこの上限に届くのは、そのテスト一つが、測ったうちで最も重い負荷の下のスイート全体より長くかかったときに限られる。
- 一つのテストで実時間が最も延びたのは、同じ負荷の下の golem-pdf の「named 32 times is refused, of one named 31 times read」の 102.19 秒である。このテストは下の節で二つに分けるが、分けないままでも 300 秒まで 2.9 倍の余裕がある。`yes` を 250 個並べた下の「named 40 times … inflated once」の 52.08 秒に対しては、5.8 倍である。
- 10 秒の予算からも見積もる。レーンが落ちたときの golem-svg-test のスイートは、単独の約 19 倍の実時間がかかった。単独で CPU 時間を 10 秒使うテストが同じだけ延びても、約 190 秒で収まる。
- CI のスイートの時間切れ（600 秒）より短い。CI の golem-pdf-test はスイート全体が 41 秒から 51 秒で終わるので、どのテストで待ち続けても、スイートが始まってから約 350 秒までにテストごとの上限が働き、止まったテストの名前が出る。

### 二つのスイートの時間切れ

- golem-pdf-test と golem-svg-test の `mkTimeout` の 47 箇所を、すべて `withinTimeLimits hangLimits` に置き換える。二つのスイートには、tasty の時間切れを残さない。実時間の上限は補助が持つ。
- 値は `hangLimits` の一つにそろえる。止まらない計算は、どれだけ CPU を得ても 60 秒の CPU 時間を使い切るので、この値で失敗になる。
- 時間の上限を付けるテストは、単独で走らせたときの CPU 時間を 10 秒以内に収める。効率のコアで CPU 時間が 3.2 倍に延びても（文脈の測定）、60 秒まで 1.8 倍の余裕が残る。
- 今のテストで 10 秒を超えるのは、golem-pdf の「the joined content of a stream named 32 times is refused, of one named 31 times read」（[SecuritySpec](https://github.com/tett23/golem/blob/b9af6f478de3dda7932a81ccf31f065ad7e351a1/modules/golem-pdf/test/SecuritySpec.hs#L211-L217)、CPU 時間 15.46 秒）だけである。32 回で拒むことと 31 回で読むことの二つのテストに分ける。断言は変えない。

### 実時間を断言するテストの置き換え

- golem-svg の C10 のテスト（[SecuritySpec](https://github.com/tett23/golem/blob/b9af6f478de3dda7932a81ccf31f065ad7e351a1/modules/golem-svg/test/SecuritySpec.hs#L202-L204)）は、`linearTime` をやめ、属性が 20 万個の要素を一度だけ読む。`withinTimeLimits hangLimits` を付け、読めたことを断言する。
  - 今の実装は 20 万個を 0.57 秒で読む。60 秒まで 100 倍の余裕がある。
  - 文脈の変異は 8 万個で 34.40 秒かかり、倍にするたびに 3 倍を超えて増える。16 万個で 100 秒を超えると見込めるので、20 万個では 60 秒の CPU 時間の上限で落ちる。
- `linearTime` と `cpuSeconds` を消す。
- NumberSpec の 0.1 秒の時間切れは、ほかと同じ `withinTimeLimits hangLimits` にする。断言（`1e-9999` と 60 桁の仮数の数を読まないこと、範囲の外と判定すること）は残す。

### 文書

- `CONTRIBUTING.md` のテストの節に、次を書く。golem-pdf と golem-svg のテストでは、時間の上限に `withinTimeLimits hangLimits` を使い、プロセスの CPU 時間の 60 秒と実時間の 300 秒の二つで止める。時間の上限を付けるテストの CPU 時間は、単独で 10 秒以内に収める。[ADR 0073](0073-time-bounds-in-tests.md) の 30 秒の読み方の一文は、この二つのスイートの外のテストの規則として残す。
- `docs/specifications.md` のモジュール構成の節の golem-test-support の段落に、時間の上限の補助 `Golem.TestSupport.TimeLimit` を足し、この ADR へのリンクを付ける。
- `docs/roadmap.md` の未決事項から「実時間を断言するテスト」を消し、v0.1.0-rc4 にこの ADR の項目を足す（この ADR と同じプルリクエストで行う）。
- [ADR 0073](0073-time-bounds-in-tests.md) のステータスの行を「採択→golem-pdf と golem-svg のテストの時間切れと `linearTime` は [ADR 0091](0091-cpu-time-limits-in-pdf-and-svg-tests.md)」に改める。

## 実装しないこと

- ほかのスイートの時間切れを CPU 時間に変えること。golem-eval の `withinHalfAMinute`、golem-driver の TableFilesSpec、golem-plugin の通信のテストなどは、ファイルや通信を待つか、threaded の RTS で動く。待つあいだは CPU 時間が進まず、threaded の RTS ではプロセスの CPU 時間がほかのテストの分も含むので、この補助は当てられない。これらのスイートでは、時間切れの失敗を観測していない。
- テストごとに上限の値を変えること。二つのスイートは `hangLimits` だけを使う。
- 製品のコードに仕事の数を数える仕掛けを入れること。比較の回数や展開したバイトの数を数えれば、時間に頼らずに二乗の悪化を断言できる。しかし、テストのためだけの数え上げが製品のコードの経路に入る。
- cabal の並列の度合いを下げること（`--jobs`）や、重いテストだけを順に走らせること。手元の測定でも、負荷には同じマシンのほかのセッションの分が含まれていた。cabal の設定では、cabal の外から来る負荷を取り除けない。
- CPU 時間の比の断言。比は、文脈のとおり、二乗の悪化を確実には捉えない。
- 10 の累乗を作らないことの検査。文脈の測定のとおり、作っても判定は 1 ミリ秒に満たず、実時間でも CPU 時間でも見分けられない。コードのレビューで確かめる。
- v1.0.0 の「テストのスイートの時間の上限」。スイート全体の所要時間の上限は、テストごとの時間切れとは別に扱う（[ADR 0073](0073-time-bounds-in-tests.md)）。golem-syntax の 2 秒の時間切れも、その項目のとおり残す。スイートの上限を実時間で測るか CPU 時間で測るかは、その項目の ADR で決める。

## テスト設計

golem-test-support の `test/` には、次を置く。
どれも、補助がない状態でコンパイルが失敗することを確かめてから実装する。

- 止まらない計算（割り当てを続ける無限の列の長さ）を `withinTimeLimits (TimeLimits 1 60)` で走らせると、`CpuTimeExceeded` で失敗すること。失敗までに使った CPU 時間が 3 秒未満であること。
- `threadDelay` で 2 秒眠る動作を `withinTimeLimits (TimeLimits 1 60)` で走らせると、失敗せずに終わること。眠るあいだは CPU 時間が進まないからである。
- `threadDelay` で 60 秒眠る動作を `withinTimeLimits (TimeLimits 60 1)` で走らせると、`WallTimeExceeded` で失敗すること。そのあいだに使った CPU 時間が 1 秒未満であること。CPU を使わずに待ち続けるテストが、実時間の上限で止まることを示す。眠り終わる前に例外で終わったことは、例外の種類で断言し、かかった実時間は断言しない。待ちには、誰も書かない `MVar` ではなく `threadDelay` を使う。誰も書かない `MVar` を待つと、RTS が `BlockedIndefinitelyOnMVar` を投げて、上限より先に終わることがあるからである。
- 動作の値がそのまま返ること。動作が投げた例外が、そのまま外に出ること。

golem-svg の `test/SecuritySpec.hs` の C10 のテストは、置き換えた後に、文脈の変異（`Set.member` を `any` の検査に変える）で落ちることを手で確かめ、結果をプルリクエストに書く。

上限の値と置き換えの働きは、自動テストにできない。
実装の後に、次を確かめる。

- `taskpolicy -b` のもとで golem-svg の「a path of 1,000,001 segments」と golem-pdf の「named 40 times … inflated once」を走らせ、通ること。今はこの方法で前者が落ちる。
- `yes` を 20 個並べた `cabal test all` を三回走らせ、二つのスイートが通ること。
- [ADR 0073](0073-time-bounds-in-tests.md) と同じく、CI の 10 回の実行で、時間に関わる失敗が一度もないこと。

## トレードオフ

- CPU 時間も、マシンの状態と無関係ではない。効率のコアで走ると 3.2 倍に延びた。10 秒の予算と 60 秒の上限で、この延びを吸収する。コアの速さの比がもっと大きいマシンでは、余裕が減る。
- 実時間の上限は、負荷だけで落ちる余地を残す。単独で CPU 時間を 10 秒使うテストは、30 倍に延びれば 300 秒に届く。測ったうちで最も大きい延びは、レーンの golem-svg-test の約 19 倍だった。
- 止まらないテストが失敗になるまでの実時間が延びる。計算を続けて止まらないテストは、混んだマシンでは 60 秒の CPU 時間を使い切る前に、300 秒の実時間の上限で止まることもある。待ち続けて止まったテストは、どのマシンでも 300 秒かかる。
- tasty の `mkTimeout (seconds 300)` を実時間の上限として残す案もある。新しいコードは減るが、47 箇所のそれぞれに二つの仕組みを書くことになり、golem-test-support のテストで実時間の上限の働きを確かめられない。補助にまとめれば、二つの値も `hangLimits` の一か所に置ける。
- プロセスの CPU 時間を測るので、テストが一つずつ走ることに頼る。threaded の RTS で失敗させることで、この前提が崩れたときに気づけるようにする。
- 値が [ADR 0073](0073-time-bounds-in-tests.md) の 30 秒と違う。この二つのスイートだけ、測る量（CPU 時間と実時間）も値（60 秒と 300 秒）も違う規則になる。
- C10 のテストは 20 万個の属性を読むので、一回で 0.57 秒の CPU 時間と約 2.3 GB の割り当てを使う。今の二回の実行より重い。
- 割り当てをしないループは、tasty の時間切れと同じく、この補助でも止められない。CPU 時間の上限でも実時間の上限でも同じである。見張りのスレッドが動けるのは、動作のスレッドが割り当てなどで止まる点に限られるからである。

## 参考文献

- [ADR 0028](0028-shared-test-support-package.md)
- [ADR 0073](0073-time-bounds-in-tests.md)
- [ADR 0083](0083-svg-number-lower-limit.md)
- [ADR 0084](0084-svg-marker-drawn-segment-limit.md)
- [ADR 0086](0086-any-test-suite-may-depend-on-test-support.md)
- [ADR 0087](0087-test-support-dependencies-and-shared-fixtures.md)
- tasty 1.5.4 の [Test/Tasty/Run.hs](https://hackage.haskell.org/package/tasty-1.5.4/src/Test/Tasty/Run.hs)（時間切れの実装）と [Test/Tasty/Options/Core.hs](https://hackage.haskell.org/package/tasty-1.5.4/src/Test/Tasty/Options/Core.hs)（`NumThreads` の既定値）
- base の [System.CPUTime](https://hackage.haskell.org/package/base/docs/System-CPUTime.html) と [GHC.Clock](https://hackage.haskell.org/package/base/docs/GHC-Clock.html)
