# ADR 0023: 見出しを次の段に送ったら、送った図版を置いた後で、もう一度入るかを確かめる

ステータス: 採択

## 文脈

### 見つかった二つの違反

[ADR 0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md) の改ページの不変条件のテストは、仕様書の「既知の不具合」の二つの項目を、テストの中の既知の不具合の一覧で除いている（[`PaginateInvariantsSpec.hs`](https://github.com/tett23/golem/blob/499f6d95fd32c1188555a81c8f4b60c0cc612d83/modules/golem-layout/test/PaginateInvariantsSpec.hs#L235-L257)）。

- **図版を追い越した見出しが、本文から離れる**（I6）。
- **送った図版の後の見出しの注が、次のページに送られる**（I7）。

最も小さい反例は、どちらも一段で段の行の数が 3 の版面である。
`PaginateEnum` の要素で書くと、次のとおりである。

| 反例 | 出力 |
| --- | --- |
| I6：`[EPara 2, EFigure 2, EHeading, EPara 1]` | 1 ページに段落の 2 行、2 ページに図版と見出し、3 ページに段落の 1 行 |
| I6（追い越す形）：`[EPara 2, EFigure 2, EFigure 2, EHeading, EPara 1]` | 1 ページに段落の 2 行、2 ページに一つめの図版と見出し、3 ページに二つめの図版と段落の 1 行 |
| I7：`[EPara 1, EFigure 3, EFigure 1, ENotedHeading]` | 1 ページに段落、2 ページに 3 行の図版、3 ページに 1 行の図版と見出し、4 ページに見出しの注の本文 |

出力は、`cabal repl golem-layout:test:golem-layout-test` で `paginateInput` を呼んで確かめた（2026-11-08、コミット 499f6d95）。

### 原因

見出しを置く手順は、次の二つの判定を一度ずつ行う（[`Paginate.hs`](https://github.com/tett23/golem/blob/499f6d95fd32c1188555a81c8f4b60c0cc612d83/modules/golem-layout/src/Golem/Layout/Paginate.hs#L264-L269)）。

1. `keep`：見出しと、見出しが後に続くものとして数える量（`nextNeed`）が今の段に入らず、段が空でなければ、次の段に進む（[`State.hs`](https://github.com/tett23/golem/blob/499f6d95fd32c1188555a81c8f4b60c0cc612d83/modules/golem-layout/src/Golem/Layout/Paginate/State.hs#L119-L120)）。
2. 見出しだけ（行と注と区切り）が入らず、段が空でなければ、次の段に進む。

次の段に進む `nextColumn` は、新しい段の先頭に、待っている図版を入るだけ置く（[`State.hs` の `advance`](https://github.com/tett23/golem/blob/499f6d95fd32c1188555a81c8f4b60c0cc612d83/modules/golem-layout/src/Golem/Layout/Paginate/State.hs#L201-L230)、[`placeDeferred`](https://github.com/tett23/golem/blob/499f6d95fd32c1188555a81c8f4b60c0cc612d83/modules/golem-layout/src/Golem/Layout/Paginate/State.hs#L274-L281)）。
二つの判定は、進む前の段で決めたことを、進んだ後の段で確かめ直さない。
進んだ段は空だという前提で書かれているが、図版を待っているときは、進んだ段の先頭を図版が取っている。

- I6 の反例では、1 の判定で 2 ページに進むと、2 ページの先頭に図版が 2 行を取り、残りは 1 行になる。2 の判定は見出しの 1 行だけを数えるので、見出しを 2 ページの最後の行に置く。段落の 1 行は 3 ページに送られる。
- I7 の反例では、1 の判定で 2 ページに進むと、3 行の図版が段を埋める。2 の判定で 3 ページに進むと、1 行の図版が先頭を取り、残りは 2 行になる。見出しは置くが、注の本文と区切りの 2 行が入らず、注の本文は 4 ページに送られる。

二つの違反は、同じ原因から出ている。
2 の判定が見出しの行と注を数えるのに、見出しの後の量を数えないのも、1 の判定の後の段が空だという前提のためである。

段落の行を置く `placeLines` は、次の段に進んだ後に、入る行の数を求め直す（[`Paginate.hs`](https://github.com/tett23/golem/blob/499f6d95fd32c1188555a81c8f4b60c0cc612d83/modules/golem-layout/src/Golem/Layout/Paginate.hs#L331-L345)）。
そのため、段落には同じ違反が出ない。

`keep` は、見出しのほかに、定義リストの用語（`FDefTerm`、[`Paginate.hs` の 196 行め](https://github.com/tett23/golem/blob/499f6d95fd32c1188555a81c8f4b60c0cc612d83/modules/golem-layout/src/Golem/Layout/Paginate.hs#L196) と [264 行め](https://github.com/tett23/golem/blob/499f6d95fd32c1188555a81c8f4b60c0cc612d83/modules/golem-layout/src/Golem/Layout/Paginate.hs#L264)）と、罫線を持つ見出し（[`Paginate.hs` の 393 行め](https://github.com/tett23/golem/blob/499f6d95fd32c1188555a81c8f4b60c0cc612d83/modules/golem-layout/src/Golem/Layout/Paginate.hs#L393)）からも呼ばれる。
用語と罫線は改ページの不変条件のテストの列挙にないので、違反を確かめていない。
ただ、`keep` の一度だけ進む作りは同じである。

### 規則どうしの矛盾ではない

[ADR 0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md) の Alloy のモデルでは、見出しの規則と図版を送る規則の組は、両立しない組として出なかった（[`docs/golem-layout/models/README.md`](../models/README.md)）。
見出しを図版とともに次の段に送れば、すべての規則を満たす。
したがって、規則の優先を決める必要はなく、実装を規則に合わせればよい。

### 試した直し方

`keep` を、入るまで、または段が空になるまで次の段に進み続ける形に変えて、改ページの不変条件のテストの全体を走らせた（2026-11-08、作業用の変更で、コミットしていない）。

- 要素 4 個までのすべての入力で、I6 と I7 の違反がなくなった。
- 直す前に既知の不具合の一覧が除いていた入力の数（要素 4 個で、I6 が 3,654、I7 が 757）が 0 になった。
- 残った違反は I8 と、改丁の見出しの I6 だけで、[golem-layout ADR 0024](0024-recto-start-places-figures-sent-on-first.md) の原因によるものだった。
- [golem-layout ADR 0024](0024-recto-start-places-figures-sent-on-first.md) の変更も入れると、要素 5 個まで違反は一つもなかった（[docs/adr/0206](../../adr/0206-pagination-points-the-invariants-did-not-decide.md) の推奨のとおりに強めた述語で）。
- `PaginateSpec` の手で選んだ例は、どれも変わらなかった。

## 実装すること

### 1. `keep` を、入るまで進み続ける形にする

`Golem.Layout.Paginate.State` の `keep` を、次のように変える。

- 量を、数ではなく、段の状態から量を求める関数で受け取る（`keep :: Env -> St -> (St -> Int) -> St`）。区切りの領域を数えるかは段の注の有無で変わるので、進んだ段で量を求め直す。
- 量が今の段に入らず、段が空でなければ、次の段に進み、進んだ段でもう一度同じ判定をする。量が入るか、段が空になったところで止まる。

止まることの根拠：次の段に進むたびに、待っている図版の少なくとも一つが置かれるか（空の段は待っている最初の図版を必ず置く）、続きの注の本文の少なくとも 1 行が置かれる（`carryNote` は段に本文の 1 行を残して置く）。
待っている図版と続きの注が尽きれば、進んだ段は空になる。

呼ぶ側の 4 か所（見出し、定義リストの用語の 2 か所、罫線を持つ見出し）を、量を求める関数を渡す形に変える。
見出しの 2 の判定（見出しだけが入るか）は残す。
1 の判定の後は、量が入るか段が空なので、2 の判定は改丁の見出しのときにだけ意味を持つ。

### 2. 文書

- [docs/specifications.md](../../specifications.md) の「改ページ」の節の「それらを合わせて段に収まらないときも、空の段からは送らない」の後に、「次の段に送ったときに、送った図版がその段の先頭を取って、それらが入らなくなれば、さらに次の段に送る」を足す。
- 仕様書の「既知の不具合」から、「図版を追い越した見出しが、本文から離れる」と「送った図版の後の見出しの注が、次のページに送られる」を消す。
- docs/roadmap.md の「改ページの既知の不具合」の項目から、同じ二つを消す。

### 3. 出力の変化

見出しを送った図版の後に置かず、図版の後の段に送る場面では、PDF のバイト列が変わる。

この ADR を書く段で、1 の変更と [golem-layout ADR 0024](0024-recto-start-places-figures-sent-on-first.md) の変更を入れた `golem` と、コミット 499f6d95 の `golem` で、次の本の PDF を組んで比べた（2026-11-08）。
どれも、バイト列が一致した。

- golem-driver の fixture の `sample`（`scripts/determinism/pdf-style.toml` を使う）、`figures`、`complex-vertical`、`complex-horizontal`、`kanikosen`、`tempest`（`scripts/visual/build.sh` と同じフォント）。
- 使い手のマニュアル（`scripts/manual/build.sh`、`GOLEM_MANUAL_COMMIT` と `GOLEM_MANUAL_TAG` は `scripts/visual/build.sh` と同じ固定の値）。開発者のマニュアルは、手元にフォントがなく組めなかった。

golem-driver のテスト（`golem-driver-test`、1,066 個）も、すべて通った。

仕様書の「既知の不具合」は、この不具合が `complex-vertical`（[ADR 0175](../../adr/0175-complex-typesetting-fixture.md)）の第一章の図 1-2 と「字面と字送り」の見出しで起きると書くが、今の fixture では、直す前と後で PDF が変わらない。
fixture が変わって、この形が今は起きていないと考えられる。
実装のときに、そのページを目で確かめ、仕様書の項目を消すときに、この食い違いもプルリクエストに書く。

開発者のマニュアル、十冊のパブリックドメインの本（`pd-*`）、`languages`、`kanikosen-marks-japanese` は比べていない。
実装のプルリクエストの CI（見た目の回帰テスト）で、変わったページがあれば、目で確かめてから参照（`scripts/visual/pages/`）を改める。

## 実装しないこと

- **見出しの先読みの量を変えること**：`nextNeed` の数える量（[golem-layout ADR 0021](0021-keep-with-next-counts-widow-and-orphan.md)）は変えない。見出しの直後の図版が待ちの列に入るときに、先読みが図版の行を数えすぎること（[golem-layout ADR 0015](0015-figure-order.md) の「トレードオフ」）も、この ADR では扱わない。
- **送った図版の置き方を変えること**：送った図版は、今のとおり次の段の先頭に置く（[golem-layout ADR 0015](0015-figure-order.md)）。
- **送った図版だけの段を空の段とみなすこと**：「メンテナーが決めること」の 2 で退ける。
- **一度だけ次の段に進むほかの箇所**：`@need-lines`（`applyNeed`）と行アキ（`placeBlank`）も、次の段に一度だけ進む。改ページの不変条件のテストの列挙にないので、この ADR を書く段では調べていない。違反が見つかれば、別の ADR で直す。
- **改丁の見出しの前の送った図版**：[golem-layout ADR 0024](0024-recto-start-places-figures-sent-on-first.md) で直す。

## 不変条件

段の行の数を C とする。
[ADR 0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md) の I6 と I7 を、送った図版のある入力でも成り立たせる。

- **F1**：見出しが段の最初の要素でなければ、その見出しは、続く見出しのすべてと、その後の段落の最初の部分（[golem-layout ADR 0021](0021-keep-with-next-counts-widow-and-orphan.md) の量）と同じ段にある。見出しの前に、送った図版があってもよい（I6）。
- **F2**：見出しの注の本文の最初の行は、見出しと同じページにある。見出しの前に送った図版があってもよい（I7）。
- **F3**：`keep` の返す段では、渡した量が段に入るか、段が空である。
- **F4**：`keep` は止まる。進む回数は、待っている図版の数と、続きの注の本文の行の数の和を超えない。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 待っている図版の数 | 0、1、2 |
| 進んだ段で図版が取る行 | 0、C − 2、C − 1、C |
| 見出しの後の量 | 1（見出しだけ）、2、3（3 行の段落の全体） |
| 見出しの注 | なし、1 行 |
| 段の数 | 1、2 |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
テストの名前には、F1 から F4 の番号を入れる。

- **F1、F2（列挙）**：改ページの不変条件のテストの既知の不具合の一覧から、「図版を追い越した見出しが、本文から離れる」と「送った図版の後の見出しの注が、次のページに送られる」の項目を消す。要素 3 個まで（プルリクエスト）と 5 個まで（毎晩の `enum.yml`）で、I6 と I7 の違反がないこと。今は、要素 4 個の入力で違反が出るので失敗する（要素 3 個では出ないので、次の回帰の例で先に失敗を確かめる）。
- **F1（回帰）**：`PaginateSpec` に、最も小さい反例を、`renderCase` の形で足す。
  - `[EPara 2, EFigure 2, EHeading, EPara 1]`、C = 3、一段：1 ページに段落の 2 行、2 ページに図版だけ、3 ページに見出しと段落の 1 行。
  - `[EPara 2, EFigure 2, EFigure 2, EHeading, EPara 1]`、C = 3、一段：2 ページに一つめの図版、3 ページに二つめの図版、4 ページに見出しと段落の 1 行。
  - 同じ二つを二段組みで置き、段の単位で同じ順になること。
- **F2（回帰）**：`[EPara 1, EFigure 3, EFigure 1, ENotedHeading]`、C = 3、一段：3 ページに 1 行の図版だけ、4 ページに見出しとその注の本文。
- **F3、F4**：`keep` に、待っている図版が 0 から 3 個（行の数は 1 から C）、続きの注の本文が 0 から 2 行の状態と、1 から C + 1 の量を、すべての組で渡し、F3 が成り立ち、進んだ回数が F4 の上限以内であること。
- **用語と罫線を持つ見出し**：送った図版の後の定義リストの用語と、罫線を持つ見出しで、F1 と同じ形の例を `PaginateSpec` に足す。今の実装で失敗するかを確かめ、失敗しなければ、その旨をプルリクエストに書く。
- 既存の `PaginateSpec` の例と、golem-driver の改ページのテストが、そのまま通ること。

## トレードオフ

送った図版だけを置いた段ができる。
I6 の反例では、2 ページは 3 行のうち 2 行を図版が取り、最後の 1 行が空く。
見出しが本文と離れるより、段の末尾が空くほうを選ぶ。
段落の孤立行と寡婦行の規則でも、同じ空きは前からできる。

`keep` が何度も進むので、待っている図版が多い原稿では、見出しが何段も後に移ることがある。
その間の段は、送った図版で埋まっているので、図版の順と本文の順のずれは今と変わらない。

量を関数で渡すので、呼ぶ側の書き方が少し長くなる。
数で渡したまま、進んだ後に呼ぶ側が量を求め直す形にすると、4 か所のそれぞれに同じ繰り返しを書くことになる。

## メンテナーが決めること

1. **直す場所**：推奨は、`keep` を入るまで進み続ける形に変えることである。見出し、定義リストの用語、罫線を持つ見出しが同じ作りなので、一か所で直る。段落の `placeLines` が進んだ後に求め直すのと同じ形になる。
   - 退けた案の一つは、`keep` の判定で、次の段の先頭に送った図版が取る行を先に数えることである。次の段で図版がいくつ置けるかと、続きの注がどれだけ入るかを、`advance` と別に計算することになり、`advance` を変えるたびに食い違うおそれがある。
   - もう一つは、見出しの `place` の枝だけを直すことである。用語と罫線を持つ見出しに、同じ作りが残る。
2. **送った図版だけを置いた段の扱い**：推奨は、空の段とみなさないことである。見出しと後に続くものが入らなければ、さらに次の段に送る。Alloy のモデルが示したとおり、そうすれば見出しの規則と図版の規則の両方を満たせる。
   - 退けた案は、送った図版だけの段を空の段とみなし、そこからは見出しを送らないことである。今の出力とほとんど変わらず、I6 の違反が残る。I6 の例外（見出しが段の最初の要素）も広げることになる。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-08、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [ADR 0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md)、[ADR 0175](../../adr/0175-complex-typesetting-fixture.md)、[docs/adr/0206](../../adr/0206-pagination-points-the-invariants-did-not-decide.md)
- [golem-layout ADR 0003](0003-pagination-and-s2.md)、[golem-layout ADR 0013](0013-heading-footnotes.md)、[golem-layout ADR 0015](0015-figure-order.md)、[golem-layout ADR 0019](0019-keep-with-next-counts-footnotes.md)、[golem-layout ADR 0021](0021-keep-with-next-counts-widow-and-orphan.md)、[golem-layout ADR 0024](0024-recto-start-places-figures-sent-on-first.md)
- [ADR 0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md) の実装のプルリクエスト（[#641](https://github.com/tett23/golem/pull/641)）の報告
- [`docs/golem-layout/models/README.md`](../models/README.md)
