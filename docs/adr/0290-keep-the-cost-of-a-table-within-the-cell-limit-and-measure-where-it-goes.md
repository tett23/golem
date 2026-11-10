# ADR 0290: セルの上限の内側の表の費用を変えず、どこに使われるかを測って記録する

ステータス: 採択

## 文脈

[ADR 0224](0224-limit-the-cells-of-a-table-set-in-pdf.md) は、PDF に組む表のセルの総数に上限（100,000、G07108）を置いた。
セルを組む前に数えるので、上限を超える表は確保の前に拒まれる（[`Flow.hs#L2528-L2542`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L2528-L2542)）。

[2026-11-09 の監査](../audits/2026-11-09-security-audit.md) の T-02（情報）は、上限の内側の費用を測った。
一字のセル（`x`）を 10,000 行 10 列に並べた 100,000 セルの表は、常駐 402 MB、割り当て 23.9 GB、9 秒でビルドに成功する。
80,000 セルでは、常駐 330 MB、割り当て 8 GB、6 秒である。
監査は、セルごとに `composeInlines` を呼ぶ費用がセルの数に比例して残ると書き、[ADR 0224](0224-limit-the-cells-of-a-table-set-in-pdf.md) が上限を「本の表としては十分」とした範囲の中であることから、重大度を情報とした。
下げるには、列の幅の検査をセルを組む前に移すなどの案があり、仕様を変えるので ADR が要るとした。

費用の行き先は、まだわかっていない。
`composeTableCells` は、すべてのセルを `composeInlines` で項目にし、`layoutTable` がすべてのセルの最小の幅と自然な幅から列の幅を決め、各セルを行に分ける（[`Flow.hs#L2549-L2577`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L2549-L2577)、[`Table.hs#L152-L195`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/modules/golem-layout/src/Golem/Layout/Table.hs#L152-L195)）。
列の幅はすべてのセルに依るので、どのセルも一度は組む必要がある。
組んだ行は PDF に書くまで要る。
ここまでは、セルの数に比例する常駐の説明になる。

一方、80,000 セルから 100,000 セルへの 25% の増加で、割り当ては 8 GB から 23.9 GB へ約 3 倍になっている。
セルの数に比例する費用だけでは、この増え方は説明できない。
表が多くのページにわたるので、改ページの探索か、改ページの固定点の繰り返し（[ADR 0251](0251-reuse-the-compositions-of-unchanged-units-between-fixpoint-rounds.md)）が、セルの数より速く増える費用を持つ可能性がある。
監査は二点しか測っておらず、これ以上は推測になる。

## 実装すること

1. 振る舞いを変えない。セルの上限（100,000）も、セルの組み方も変えない。
2. 監査の `make-fixtures.sh` と同じ形の表（一字のセル、10 列）を、10,000、20,000、40,000、80,000、100,000 セルで組み、`+RTS -s` の常駐と割り当てと時間を測る。配布の `golem` は `-rtsopts` なしでリンクされるので、監査と同じく、同じ `Main.hs` を `-rtsopts` でリンクし直したものを使う。
3. 100,000 セルの表で、`-prof` の割り当ての内訳（`+RTS -p`）を取り、割り当ての上位の関数を記録する。
4. 2 と 3 の結果を `docs/benchmarks/` の新しい記録に置く。割り当てがセルの数の 1 乗より速く増えていれば、その関数と増え方を書き、[docs/roadmap.md](../roadmap.md) の v1.0.0 の「機能をそろえた後の確かめ」に、その費用を下げる項目を足す。下げる方法は、その項目の ADR で決める。
5. [docs/roadmap.md](../roadmap.md) の「2026-11-09 の監査の情報の所見」の項目から、T-02 を外す。

## 実装しないこと

- セルの上限を下げること（「メンテナーが決めること」の 1）。
- セルを二度組む、列ごとの最小の幅と自然な幅だけを先に求めて項目を捨てる、などの組み方の変更。費用の行き先を測る前に組み方を変えると、費用の下がらない変更を入れうる。
- 4 の測定の結果で費用を下げること。下げる変更は、別の ADR で決める。

## 不変条件

なし。
この ADR は振る舞いを変えず、測定の手順と記録の置き場所だけを決める。
出力の PDF、diagnostics、G07108 の判定は、[ADR 0224](0224-limit-the-cells-of-a-table-set-in-pdf.md) の不変条件のままである。

## テスト設計

自動のテストは足さない。
測定は時間とメモリの値で、ランナーごとに揺れるので、テストの述語にしない（[ADR 0073](0073-time-bounds-in-tests.md)）。

- 実装のプルリクエストで、2 と 3 を手元の一台のマシンで行い、マシン（CPU、コアの数、メモリ）、GHC の版、コミットを記録に書く。
- 監査の二点（80,000 と 100,000 セル）の値が、同じ形の入力で同じ桁で再現することを確かめる。再現しなければ、その差を記録に書く。

## トレードオフ

上限の内側で数百 MB を使う表は、そのまま残る。
利用者のマシンのメモリが足りなければ、ビルドは止まる。
本の表で 10,000 セルを超えるものは少ないと見込むが、確かめてはいない。

## メンテナーが決めること

1. **上限の内側の費用を今変えるか**：推奨は、変えずに測ることである。割り当ての増え方が監査の二点からは読めず、どこを直すかが決まらない。
   - 退けた案の一つは、上限を 10,000 セルに下げることである。費用はおよそ一桁下がるが、[ADR 0224](0224-limit-the-cells-of-a-table-set-in-pdf.md) が通した表を G07108 で拒むようになる。
   - もう一つは、列の幅を決める段で項目を捨て、行に分ける段で組み直すことである。常駐は下がりうるが、`composeInlines` が二倍になり、時間と割り当ては増える。割り当てがセルの数より速く増える原因が別にあれば、それも残る。
2. **測定の置き場所**：推奨は `docs/benchmarks/` の新しい記録である。コミットの後は変えない記録として、次の比較の基準になる。
   - 退けた案は、仕様書に値を書くことである。仕様書は今の振る舞いを書く場所で、測定の値はマシンと版で変わる。

## 決めたことの記録

2026-11-10 に、tett23 が「メンテナーが決めること」のすべてを推奨のとおりに決めた。

1. 上限の内側の表の費用は今は変えず、どこに使われるかを測る。
2. 測定は `docs/benchmarks/` の新しい記録に置く。

採択にあたり、ソースコードへのリンクを `main` の `9acc137a`（[ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md) の実装のマージ）に合わせた。

## 参考文献

- [2026-11-09 の監査](../audits/2026-11-09-security-audit.md)（T-01、T-02）と、その [`make-fixtures.sh`](../audits/2026-11-09-evidence/make-fixtures.sh)
- [ADR 0073](0073-time-bounds-in-tests.md)、[ADR 0224](0224-limit-the-cells-of-a-table-set-in-pdf.md)、[ADR 0251](0251-reuse-the-compositions-of-unchanged-units-between-fixpoint-rounds.md)
- [golem-driver ADR 0008](../golem-driver/adr/0008-pdf-tables.md)、[golem-driver ADR 0037](../golem-driver/adr/0037-table-column-widths.md)
- [`modules/golem-typeset/src/Golem/Typeset/Flow.hs`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L2524-L2577)、[`modules/golem-layout/src/Golem/Layout/Table.hs`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/modules/golem-layout/src/Golem/Layout/Table.hs#L152-L195)
