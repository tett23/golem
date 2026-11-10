# ADR 0301: テストを足して伸びたスイートの上限を、伸びた後の時間から決める

ステータス: 採択（未実装）

## 文脈

[ADR 0292](0292-limit-the-time-of-each-test-suite-by-the-median-of-main.md) は、テストのスイートの上限を、直近の `main` への push の 20 回の秒の中央値 m から `max(10, ceil(2 × m))` とした。
テストを足して伸びたスイートについては、「そのプルリクエストで `suite-limits.sh --fetch 20` で表を作り直し、増えたスイートの行は、プルリクエストの CI の秒を中央値に加えた値で上限を求める」とした（4 の 2 つめ）。

[ADR 0292](0292-limit-the-time-of-each-test-suite-by-the-median-of-main.md) の実装で、2026-11-10 に `main` への push の直近 20 回（テストを走らせたもの）の `suite-timeout.sh` の行を集めた。
`golem-layout-test` の秒は、新しい順に次のとおりであった。

| アーキテクチャ | 秒（新しい順） | 中央値 | 式の上限 |
| --- | --- | --- | --- |
| x86-64 | 72、51、47、81、59、35、42、57、59、35、47、33、31、25、22、19、22、25、26、28 | 35 | 70 |
| aarch64 | 46、48、47、45、32、33、32、33、32、27、25、26、23、19、20、17、17、17、18、16 | 26.5 | 53 |

この 20 回のあいだに、列挙のテスト（[ADR 0274](0274-prefer-pulling-in-and-limit-the-stretch-of-lines.md) から 0280）が足され、`golem-layout-test` は約 2.5 倍になった。
中央値は伸びる前の値に引かれ、式の上限は、表を作った 20 回のうちの 2 回（x86-64 の 72 秒と 81 秒）をすでに超える。
[ADR 0286](0286-leave-the-start-of-cabal-out-of-the-time-of-an-enumeration-area.md) の実装（`[lang fr]`、R1、行の調整の三つの順をプルリクエストに戻す）の後、プルリクエスト #853 の CI では、`golem-layout-test` が x86-64 で 71 秒、aarch64 で 57 秒と 59 秒（二回の実行）であり、どちらも式の上限（70 秒と 53 秒）を超える。

このまま表をコミットすると、`main` への push の CI が、揺れではなく伸びた後の普通の時間で落ちる。
[ADR 0292](0292-limit-the-time-of-each-test-suite-by-the-median-of-main.md) のテスト設計の「揺れ」（実装の後の `main` への push の 10 回で、上限で落ちたスイートがないこと）も満たせない見込みが高い。

[ADR 0292](0292-limit-the-time-of-each-test-suite-by-the-median-of-main.md) の実装のプルリクエスト（[#891](https://github.com/tett23/golem/pull/891)）は、[ADR 0286](0286-leave-the-start-of-cabal-out-of-the-time-of-an-enumeration-area.md) のマージの数時間後に表を作り直し、`golem-layout-test` の上限は x86-64 で 98 秒、aarch64 で 65 秒になった。
20 回のうち伸びた後の値が増えたからで、規則が伸びに追いついたわけではない。
aarch64 の 65 秒は、#853 の 59 秒の 1.1 倍にとどまる。

4 の規則は、この場合を救わない。
「プルリクエストの CI の秒を中央値に加えた値」は、二通りに読める。

- 読み方 A：プルリクエストの秒を、中央値を求める入力に一つ加える。21 個の中央値は、20 個の中央値からほとんど動かない（aarch64 で 26.5 秒から 27 秒、上限 54 秒）。伸びたスイートは、伸びた後の値が 11 個そろうまで落ち続ける。
- 読み方 B：中央値 m にプルリクエストの秒 t を足した m + t を新しい中央値とする。aarch64 で 26.5 + 59 = 85.5、上限 171 秒になり、上限は伸びた後の値の約 3 倍になる。後退を見つける力が弱まる。

どちらの読み方でも、テストを足して伸びたスイートの上限は、伸びた後の時間の 2 倍にならない。

## 実装すること

（推奨案。「メンテナーが決めること」の 1 で決める）

1. テストを足して伸びたスイートの行は、伸びた後の時間だけから求める。具体的には、そのプルリクエストの CI の秒 t を、その行の中央値 m の代わりに使い、上限を `max(10, ceil(2 × t))` とする。
2. `suite-limits.sh` に、行を一つだけ指定の秒から求め直す `--set ARCH SUITE SECONDS` を足す。ほかの行は変えない。
3. 伸びた後の `main` への push が 20 回たまったら、`suite-limits.sh --fetch 20` で表全体を作り直してよい。作り直しは、上限を超えたときの 4 の規則とは別の、任意の手順とする。
4. [ADR 0292](0292-limit-the-time-of-each-test-suite-by-the-median-of-main.md) の 4 の 2 つめを、この ADR で置き換える。[ADR 0292](0292-limit-the-time-of-each-test-suite-by-the-median-of-main.md) のステータスの行に、テストを足して伸びたスイートの上限はこの ADR で決めたことを書き足す。
5. [ADR 0292](0292-limit-the-time-of-each-test-suite-by-the-median-of-main.md) の実装が置いた最初の表の `golem-layout-test` の行を、この ADR の実装で、[ADR 0286](0286-leave-the-start-of-cabal-out-of-the-time-of-an-enumeration-area.md) の後のプルリクエスト #853 の CI の秒から 1 の式で求め直す。x86-64 は 71 秒から 142 秒、aarch64 は二回の実行の 57 秒と 59 秒の中央値 58 秒から 116 秒である。ほかの行は変えない。

## 実装しないこと

- 式（`max(10, ceil(2 × m))`）と、20 回という数を変えること。
- 伸びたかどうかを自動で見分けること。伸びがテストを足したことによるかは、[ADR 0292](0292-limit-the-time-of-each-test-suite-by-the-median-of-main.md) の 4 のとおり、プルリクエストで人が調べて決める。

## 不変条件

- **G1 指定の行だけが変わる**：`suite-limits.sh --set a s t` の後の表は、(a, s) の行の秒が `max(10, ceil(2 × t))` であることだけが前の表と違う。
- **G2 ない行は足さない**：(a, s) の行がない表に `--set a s t` を与えると、表を変えずに 0 でない終了の状態で終わる。新しいスイートの行は、[ADR 0292](0292-limit-the-time-of-each-test-suite-by-the-median-of-main.md) の 4 の 3 つめのとおり、手で足す。

境界の入力：

| 入力 | 期待 |
| --- | --- |
| t = 0、4.9、5、5.1 | 10、10、10、11（G1） |
| 表にない (a, s) | 落ちる（G2） |
| 同じ s のもう一方のアーキテクチャ | 変わらない（G1） |

## テスト設計

- G1 と G2 を `scripts/ci/test.sh` で、小さな表に `--set` を与えて確かめる。テストの名前に番号を入れる。
- 5 は自動のテストにしない。この ADR の実装のプルリクエストの説明に、前と後の上限と、使った CI の秒を書く。

## トレードオフ

一回のプルリクエストの CI の秒は、ランナーの揺れ（x86-64 で最大 1.8 倍）を含む。
速いランナーに当たった秒から求めた上限は、遅いランナーで落ちうる。
中央値を使わない分、[ADR 0292](0292-limit-the-time-of-each-test-suite-by-the-median-of-main.md) が避けたかった揺れによる失敗が増える。
代わりに、テストを足したプルリクエストのすぐ後から、伸びた後の時間の 2 倍で後退を見つけられる。

## メンテナーが決めること

1. **伸びたスイートの上限の求め方**：推奨は、プルリクエストの CI の秒だけから求めること（実装すること 1）。
   - 退けた案の一つは、読み方 A（秒を中央値の入力に加える）である。伸びた後の値が過半になるまで落ち続ける。
   - もう一つは、読み方 B（m + t を中央値とする）である。上限が伸びた後の時間の約 3 倍になる。
   - もう一つは、伸びた後の `main` への push だけで中央値を求めることである（20 回たまるまでは、たまった回数で求める）。揺れには強いが、伸びた後の push が一回もない最初のプルリクエストでは値がない。推奨案の 3 と組み合わせれば、作り直しの手順になる。
   - もう一つは、プルリクエストの CI の x86-64 と aarch64 の秒を、`workflow_dispatch` で数回走らせて中央値を取ることである。揺れに強いが、テストを足すたびにランナーの時間を使う。
2. **[ADR 0292](0292-limit-the-time-of-each-test-suite-by-the-median-of-main.md) の最初の表**：推奨は、`golem-layout-test` の行だけを 1 で求め、ほかの行は [ADR 0292](0292-limit-the-time-of-each-test-suite-by-the-median-of-main.md) の式のままにすることである。退けた案は、[ADR 0286](0286-leave-the-start-of-cabal-out-of-the-time-of-an-enumeration-area.md) の後の `main` への push が 20 回たまるまで [ADR 0292](0292-limit-the-time-of-each-test-suite-by-the-median-of-main.md) の実装を待つことである。

## 決めたことの記録

2026-11-10 に、tett23 が「メンテナーが決めること」のすべてを推奨のとおりに決めた。

1. テストを足して伸びたスイートの行は、そのプルリクエストの CI の秒 t だけから `max(10, ceil(2 × t))` で求める。表全体の作り直しは、伸びた後の `main` への push が 20 回たまった後の任意の手順とする。
2. 最初の表は、`golem-layout-test` の行だけを 1 で求め、ほかの行は [ADR 0292](0292-limit-the-time-of-each-test-suite-by-the-median-of-main.md) の式のままにする。

[ADR 0292](0292-limit-the-time-of-each-test-suite-by-the-median-of-main.md) の実装のプルリクエスト（#891）は、この ADR の採択の前に、[ADR 0286](0286-leave-the-start-of-cabal-out-of-the-time-of-an-enumeration-area.md) のマージの後の直近の 20 回で表を作り直した。
そのため採択にあたり、実装すること 5 を、[ADR 0292](0292-limit-the-time-of-each-test-suite-by-the-median-of-main.md) の実装の後にこの ADR の実装で行を求め直す形に書き直し、使う秒（#853 の x86-64 の 71 秒、aarch64 の二回の中央値 58 秒）を書いた。

## 参考文献

- [ADR 0292](0292-limit-the-time-of-each-test-suite-by-the-median-of-main.md)、[ADR 0286](0286-leave-the-start-of-cabal-out-of-the-time-of-an-enumeration-area.md)、[ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md)
- CI の実行：`main` への push の直近 20 回（2026-11-10 に `scripts/ci/suite-limits.sh --fetch 20` で集めた。[ADR 0292](0292-limit-the-time-of-each-test-suite-by-the-median-of-main.md) の実装のブランチ `impl-0292`、[#891](https://github.com/tett23/golem/pull/891)）、プルリクエスト #853 の実行 42764141414 と 42765857983 の `build (…, tests-rest)`
