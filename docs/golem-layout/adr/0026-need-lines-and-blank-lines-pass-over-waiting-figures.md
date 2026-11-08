# ADR 0026: 待つ図版は、前の `@need-lines` と行アキの「次のブロック」にならない

ステータス: 採択→Alloy のスコープと行アキを捨てる段は [ADR 0236](../../adr/0236-record-what-implementations-decided-found-by-the-second-review-of-2026-11-08.md)

## 文脈

[golem-layout ADR 0025](0025-need-lines-and-blank-lines-after-figures-sent-on.md) は、送った図版の後の段でも、`@need-lines` と行アキが段に入るまで進むようにした。
その不変条件 P1、P3、P4 は、一つの形を除いたまま採択された。
送った図版が待っているあいだに書いた図版（以下、**待つ図版**）の直前に、`@need-lines` か行アキがある形である。
仕様書の「既知の不具合」の「送った図版の後で待つ図版の前の `@need-lines` と行アキが、その図版と別の段で扱われる」が、この形を記録している。
改ページの不変条件のテスト（[`PaginateInvariantsSpec.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/test/PaginateInvariantsSpec.hs#L365-L377)）は、既知の不具合の一覧でこの形を除き、除いた入力の数を要素 4 個で 96、5 個で 4,482 に固定している。

仕様も ADR も、待つ図版の前の `@need-lines` と行アキをどの段で扱うかを定めていない。
この ADR は、それを決めて直す。

### 待つ図版は、置く位置を流れから受け取らない

仕様書の「図版」の節は、「送った図版が待っているあいだは、後の図版も、収まるかどうかにかかわらず、待っている図版の後に送る」と定める（[golem-layout ADR 0015](0015-figure-order.md)）。
実装では、`place` の `FFigure` の枝が、`sDeferred` が空でなければ、段の残りを見ずに図版を待ちの列に足す（[`Paginate.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/src/Golem/Layout/Paginate.hs#L286-L290)）。
回す図版（`FPageFigure`）も、何もないページに置けなければ待つ（同じファイルの [`L291-L294`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/src/Golem/Layout/Paginate.hs#L291-L294)）。
待つ図版は、流れのその位置の段に何も置かない。

ところが、`placeAll` は、図版の前に `ready`（改ページと `@need-lines`）と `placeBlank`（行アキ）を、ほかのブロックと同じく当てる（[`Paginate.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/src/Golem/Layout/Paginate.hs#L141-L148)）。
`placeBlank` は、行アキの行数と図版の行数の和が今の段に入るかで、進むかを決める（[`L162-L178`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/src/Golem/Layout/Paginate.hs#L162-L178)）。
`@need-lines` と行アキは今の段で使われ、その図版は後の段に送られる。
二つの規則が、別の段の上で判定している。

### 確かめたこと

`cabal repl golem-layout-test` で、`PaginateEnum` の `paginateInput` と `PaginateInvariants` の `breaches` を使って確かめた（2026-11-08、golem-layout のソースは origin/main の `4c808d07` と同じもの）。
`Input C k es` は、段の行の数 C、段の数 k、要素の並び es の入力である。

- `Input 3 1 [EPara 1, EFigure 3, EBlank 1, EFigure 1]`：行アキは 1 ページの段落の後に置かれ、二つめの図版は 3 ページに置かれる。P3 と P4 が違反になる。
- `Input 4 1 [EPara 2, EFigure 3, ENeedLines, EFigure 1]`：二つめの図版は 2 ページの図版の後の、残りが 1 行の位置に置かれる。P1 が違反になる。
- `Input 4 1 [EPara 2, EFigure 3, EBlank 1, EFigure 2, EPara 1]`：1 行の段落が 3 ページに置かれ、1 ページの 2 行が空いたまま残る。行アキは 3 ページの先頭で捨てられ、`DroppedBlank`（G07047）が記録される。行アキを除いた `Input 4 1 [EPara 2, EFigure 3, EFigure 2, EPara 1]` では、段落は 1 ページに置かれる。どの不変条件も違反にしないが、行アキが待つ図版の 2 行と合わせて量られたために、本文が段を一つ飛ばしている。

三つめの例が示すのは、不具合が不変条件の違反だけにとどまらないことである。
待つ図版の前に行アキを書くと、後の本文が段を飛び、段の末尾に空きが残る。

一方、`@need-lines` では、出力は変わらない場合が多い。
`Input 4 1 [EPara 2, EFigure 3, ENeedLines, EFigure 1, EPara 1]` では、`@need-lines` は 1 ページで守られ、最後の段落も 1 ページに置かれる。
`@need-lines` を待つ図版で使い切っても、図版は段に何も置かないので、後の段落は判定した段の同じ残りに置かれるためである。
それでも P1 は、二つめの図版を `@need-lines` のブロックとして調べ、違反を返す。
`@need-lines` で直すべきなのは、主に「次のブロック」の定義のほうである。

### 参照した組み方

JLReq は、図版を送ったときに、その前の行アキと改ページの指定をどこに残すかを定めていない。
InDesign の振る舞いは確かめていない（InDesign には、送った図版の後の図版をまとめて待たせる仕組みと、Golem の `@need-lines` に当たる指定の組み合わせがない見込みが高いが、確かめていない）。
仕様書の「仕様が不明瞭な場合」の順に従い、TeX と LaTeX を参照した。
LaTeX の `figure` の環境は浮動体であり、中身は本文の縦のリストから外れて浮動体の列に入る。
環境の前に書いた `\vspace` は、本文の縦のリストに残る。
つまり、図版が送られても、その前の空きは本文の側に残り、後の本文の前に置かれる。

## 実装すること

### 1. 待つ図版は、前の制御を受け取らない

`placeAll` の、改ページの制御でも空き（`FSpace`）でもないブロックの枝（[`Paginate.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/src/Golem/Layout/Paginate.hs#L141-L148)）を、次のように改める。

1. 先に改ページ（`applyBreaks`）だけを当てる。改ページで次のページに移ると、待ちの列の図版が先に置かれ、待つ図版が待たなくなることがあるためである。
2. 改ページを当てた後の状態で、そのブロックが待つ図版かを判定する。待つ図版は、`sDeferred` が空でないときの `FFigure` と、今は置けない `FPageFigure` である（`place` の二つの枝と同じ条件）。
3. 待つ図版なら、`applyNeed` と `placeBlank` を当てず、`sNeed` と `sBlank` を残したまま図版を待ちの列に足す。残した `@need-lines` と行アキは、流れで次に来る、待つ図版でないブロックに当てる。
4. 待つ図版でなければ、今と同じく `ready` と `placeBlank` を当てる。

`@no-page-break` の扱い（`checkNoBreak`）と、`sSeen`、`sLastDeferred` の更新は変えない。

### 2. 本の終わりまで残った行アキ

待つ図版の後に、待つ図版のほかに何もなく本が終わると、行アキが残る。
本の最後の行アキは文書の組み立てで捨てる（G04009）が、そこでは図版もブロックに数えるので、この行アキは捨てられずに改ページに届く。
今の `placeAll []` は、残った行アキを記録せずに捨てる（[`Paginate.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/src/Golem/Layout/Paginate.hs#L126-L129)）ので、何もしなければ、この ADR で黙って消える行アキが生まれる。

本の終わりで、待ちの列の図版は `flushDeferred` で次の段の先頭から置かれる（[`State.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/src/Golem/Layout/Paginate/State.hs#L293-L296)）。
残った行アキは、その段の先頭に来るものとして、`@blank-line` ごとに `DroppedBlank` を一つ記録して捨てる（「メンテナーが決めること」の 2）。
記録は今の `DroppedBlank` と同じく G07047 になる。
残った `@need-lines` は、今と同じく捨てる。
待ちの列の図版は段の先頭から置かれるので、`@need-lines` の行の数（段の行の数以下）は必ず空いている。

### 3. 不変条件の述語

`PaginateInvariants` の `waiting`（[`PaginateInvariants.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/test/PaginateInvariants.hs#L344-L368)）は、制御の後の最初のブロックを、制御の「次のブロック」としている。
これを、待つ図版を飛ばした最初のブロックに改める。
待つ図版かどうかは、出力から判定する。
流れで後に書いたブロックの最初の部分より後の位置（ページ、段、段の中の順）に置かれた図版を、待つ図版とする。
図版の後に図版のほかのブロックがなければ、その図版は待つ図版とする。

この定義は、待ちの列の先頭になる図版（段に入らずに自ら送られる図版）も含む。
その図版の前の `@need-lines` は今も判定した段で使われるが、図版は段に何も置かないので、後のブロックは判定した段の同じ残りに置かれる。
述語の定義を広げても、判定は変わらない。

### 4. 既知の不具合の一覧

`PaginateInvariantsSpec` の `knownBugs` から、「送った図版の後で待つ図版の前の `@need-lines` と行アキが、その図版と別の段で扱われる」の項目と `waitingFigures` を除く。

### 5. Alloy のモデル

`docs/golem-layout/models/pagination.als` は、高々一つの図版と、一つの段と次の段の境目だけを扱い、`@need-lines` と行アキを持たない。
この ADR の規則は、図版の順（[golem-layout ADR 0015](0015-figure-order.md)）、送った図版の後の段（[golem-layout ADR 0025](0025-need-lines-and-blank-lines-after-figures-sent-on.md)）、行アキを後と同じ段に置く規則（[docs/adr/0046](../../adr/0046-blank-line-command.md)）、`@need-lines`（[docs/adr/0030](../../adr/0030-manual-page-break-control.md)）の四つと端で重なる。
[docs/roadmap.md](../../roadmap.md) の「規則の Alloy のモデル」に従い、モデルに二つめの図版と、図版の前の行アキ（`Blank`）を足し、両立しない規則の組を探す（「メンテナーが決めること」の 4）。
結果は、モデルの README と、この ADR の実装の PR の説明に書く。

### 6. 文書

- [docs/specifications.md](../../specifications.md) の「図版」の節に、待つ図版は前の `@need-lines` と行アキを受け取らず、それらは流れで次に来る、待つ図版でないブロックに当たることを書く。
- 「行アキ」の節に、本の終わりまで待つ図版しか続かない行アキは、待つ図版を置く段の先頭で捨て、G07047 を出すことを書く。
- 「改ページの手での制御」の `@need-lines` の文に、待つ図版を数えないことを書く。
- 「既知の不具合」から、この項目を除く。
- [docs/roadmap.md](../../roadmap.md) の「送った図版の後で待つ図版の前の `@need-lines` と行アキ」の項目を除く。
- 出力が変わる本があれば、変わったページを目で確かめてから、`scripts/determinism/hashes.txt`、golden、見た目の回帰テストの参照を改める。
- [golem-layout ADR 0025](0025-need-lines-and-blank-lines-after-figures-sent-on.md) のステータスの行に、P1、P3、P4 の「次のブロック」をこの ADR が改めたことを書く。

## 実装しないこと

- **自ら送られる図版の前の行アキ**：段に入らない図版の直前に行アキがあると、`placeBlank` は行アキと図版の和が入る段まで進む。`Input 4 1 [EPara 1, EBlank 1, EFigure 3, EPara 2]` では、図版が 2 ページに置かれ、1 ページの 3 行が空く。行アキと図版は同じ段にあり、どの不変条件も破らないので、この ADR では変えない（「メンテナーが決めること」の 3）。
- **`@need-lines` の後の空き**：空き（`FSpace`）が `@need-lines` を使い切る不具合は、[golem-layout ADR 0027](0027-need-lines-judged-again-after-spaces.md) で直す。
- **`@no-page-break` の前の待つ図版**：送った図版の後の `@no-page-break` は、今も守れない指定として記録する（`sLastDeferred`）。変えない。
- **表と回り込む図版**：待つことがないので、この ADR の対象ではない。

## 不変条件

段の行の数を C、今の段の行の数（`@page-lines` を当てたもの）を C' とする。
制御（`@need-lines`、行アキ、空き、改ページ）の「次のブロック」を、流れでその後に書いたブロックのうち、待つ図版を飛ばした最初のものとする。
待つ図版は、「実装すること」の 3 のとおり出力から判定する。

- **P1′ `@need-lines` を守る**：`@need-lines N`（N ≤ C'）の次のブロックは、置く直前の段の残りが N 行以上ある段に置かれる。ただし、その段が空の段であるときを除く。数え方は [golem-layout ADR 0025](0025-need-lines-and-blank-lines-after-figures-sent-on.md) の P1 と同じである。
- **P3′ 行アキはあふれない**：行アキを置いた段では、置いたものと行アキと注の本文と区切りの行の和が C' を超えない。
- **P4′ 行アキは次のブロックと同じ段に置くか、捨てて記録する**：行アキは、次のブロックの最初の部分と同じ段に置かれるか、段の先頭で捨てられて、`@blank-line` ごとにちょうど一つの `DroppedBlank` が記録される。
- **P5 次のブロックのない行アキ**：次のブロックがなく、待つ図版だけが後に続く行アキは、どの段にも置かれず、`@blank-line` ごとにちょうど一つの `DroppedBlank` が記録される。
- **P6 行アキのない形を変えない**：待つ図版の前に行アキも `@need-lines` もない入力では、この ADR の前と同じ出力になる。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 待っている図版の数 | 0、1、2 |
| 待つ図版の前の制御 | `@need-lines` だけ、行アキだけ、両方、制御と図版のあいだに空き |
| 待つ図版の後 | 段落、見出し、もう一つの待つ図版、なし（本の終わり） |
| 判定するときの段の残り | 0、N − 1、N、行アキと次のブロックの最初の部分がちょうど入る、一行足りない |
| 待つ図版の行の数 | 1、次のブロックの最初の部分と同じ、C |
| 図版の種類 | 版面の図版、回す図版 |
| 制御の前の改ページ | なし、あり（改ページで待ちの列が空になり、図版が待たなくなる） |
| 段の数 | 1、2 |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
テストの名前には、P1′ から P6 の番号を入れる。

### 回帰（`PaginateSpec`）

- **P3′、P4′、P5**：`paginate` で `Input 3 1 [EPara 1, EFigure 3, EBlank 1, EFigure 1]` と同じ流れを組み、行アキが 1 ページに置かれず、`DroppedBlank` が一つ記録されること。今は 1 ページに置かれ、記録されないので失敗する。
- **P4′**：`Input 4 1 [EPara 2, EFigure 3, EBlank 1, EFigure 2, EPara 1]` で、行アキと最後の段落が 1 ページに置かれ、`DroppedBlank` が記録されないこと。今は段落が 3 ページに置かれるので失敗する。
- **P1′**：`Input 4 1 [EPara 2, EFigure 3, ENeedLines, EFigure 1, EPara 1]` で、最後の段落が 1 ページに置かれること。今も通る。述語が二つめの図版を `@need-lines` のブロックとして調べないことを、述語のテストで確かめる。
- **P6**：制御の前に改ページがあり、改ページで待ちの列が空になる入力で、図版がその段に置かれ、行アキが図版と同じ段に置かれること。
- 回す図版：待つ回す図版の前の行アキが、後の段落と同じ段に置かれること。

### 述語（`PaginateInvariantsSpec`）

- 待つ図版の判定：手で作った出力で、後のブロックより後に置かれた図版を待つ図版とし、そうでない図版を待つ図版としないこと。
- P5：手で作った、記録のない出力で違反を返し、記録が二つある出力でも違反を返すこと。

### 列挙

- 既知の不具合の一覧から項目を除くと、今の実装では、要素 4 個（毎晩の深さ）の入力で違反が出て、テストが失敗すること。プルリクエストの深さ（3）では、既知の不具合の数は 0 なので、先に失敗させるのは回帰のテストで行う。
- 実装の後で、プルリクエストの深さと、毎晩の深さ（`GOLEM_ENUM_DEPTH=5`）の両方で、P1′ から P5 と I1 から I8 が成り立つこと。
- P6 は、今の `PaginateSpec` のテスト、golden、`scripts/determinism/hashes.txt` が、待つ図版の前に制御を持たない入力で変わらないことで確かめる。待つ図版でないブロックの手順は、改ページを先に当てる順のほかは変わらず、`ready` の中の `applyBreaks` は二度目には何もしない。

### Alloy のモデル

「実装すること」の 5 で足した述語で、行アキを次のブロックと同じ段に置く規則と、図版の順の規則が両立しない入力がないことを `run` で確かめ、結果を README に書く。
モデルは CI で走らせないので、手で確かめる。

## トレードオフ

待つ図版の前に書いた行アキは、図版の前ではなく、後の本文の前に置かれる。
書き手が図版との区切りのつもりで書いた行アキでも、図版が送られれば本文どうしの区切りになる。
LaTeX の浮動体と同じ振る舞いで、図版の位置が組んでみるまで決まらない以上、行アキを図版に付けて運ぶよりも、本文の流れに残すほうが、原稿の順に近い。

`@need-lines` は、出力をほとんど変えずに、不変条件の定義を改めることになる。
規則を変えたのか、テストを直したのかが分かりにくいので、「確かめたこと」に出力の比べを残した。

本の終わりの行アキを G07047 にすると、このコードが「段の先頭で捨てた」以外の場面でも出るように見える。
待つ図版は次の段の先頭から置かれるので、行アキが段の先頭で捨てられることに違いはない。
原因が同じなので、コードを分けない。

## メンテナーが決めること

1. **待つ図版の前の制御を、どのブロックに当てるか**：推奨は、待つ図版を飛ばし、流れで次に来る、待つ図版でないブロックに当てることである。LaTeX の浮動体と同じく、送った図版の前の空きは本文の側に残る。待つ図版は流れの位置の段に何も置かないので、そこで行アキと `@need-lines` を使い切る理由がない。
   - 退けた案の一つは、制御を図版と一緒に待ちの列に入れ、図版を置くときに当てることである。待ちの列の図版は段の先頭から置くので、行アキはほぼ必ず段の先頭で捨てられ、図版と図版のあいだにだけ残る。待ちの列に状態が増え、`flushDeferred` と `advance` の手順も変わる。
   - 二つめは、待つ図版の前の行アキと `@need-lines` を捨てて記録することである。図版が送られるかは組んでみるまで分からず、書き手は原稿の順を変えるほかに避けようがない。一つの原因に新しいコードも要る。
   - 三つめは、コードを変えず、P1、P3、P4 の述語からこの形を除いたままにすることである。「確かめたこと」の三つめの例の、本文が段を飛ぶ出力が残る。
2. **本の終わりまで残った行アキの記録**：推奨は、待つ図版を置く段の先頭で捨てたものとして `DroppedBlank`（G07047）を記録することである。待つ図版は `flushDeferred` で次の段の先頭から置かれるので、行アキが段の先頭で捨てられることは、ほかの G07047 と同じである。
   - 退けた案の一つは、新しいコード（本の終わりで捨てた行アキ）にすることである。原因は段の先頭で捨てたことで、G07047 と同じである。一つの原因に一つのコードの原則に反して二つのコードを持つことになる。
   - 二つめは、今の `placeAll []` のまま記録せずに捨てることである。この ADR が、黙って消える行アキを作る。
3. **自ら送られる図版の前の行アキ**：推奨は、この ADR では変えず、[docs/roadmap.md](../../roadmap.md) の未決事項に足すことである。行アキと図版は同じ段にあり、どの不変条件も破らない。変えると、大きな図版の前に行アキを置いた本の出力が、不具合の直しとは別の理由で変わる。
   - 退けた案は、この ADR で、自ら送られる図版も待つ図版と同じに扱うことである。段の末尾の空きは減るが、行アキと図版のどちらが先に段を移るかという、別の規則を決めることになる。
4. **Alloy のモデル**：推奨は、モデルに二つめの図版と、図版の前の行アキを足して走らせることである。この規則は四つの規則と端で重なるので、[docs/roadmap.md](../../roadmap.md) の「規則の Alloy のモデル」が、モデルを求める。
   - 退けた案は、モデルの範囲の外として、README に書くだけにすることである。ロードマップの規則に反する。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-08、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [golem-layout ADR 0015](0015-figure-order.md)、[golem-layout ADR 0023](0023-keep-with-next-after-figures-sent-on.md)、[golem-layout ADR 0025](0025-need-lines-and-blank-lines-after-figures-sent-on.md)、[golem-layout ADR 0027](0027-need-lines-judged-again-after-spaces.md)
- [docs/adr/0030](../../adr/0030-manual-page-break-control.md)、[docs/adr/0046](../../adr/0046-blank-line-command.md)、[ADR 0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md)、[ADR 0208](../../adr/0208-widen-lightweight-formal-methods.md)
- [docs/specifications.md](../../specifications.md) の「図版」、「行アキ」、「改ページの手での制御」、「既知の不具合」の節
- [docs/roadmap.md](../../roadmap.md) の「規則の Alloy のモデル」
- 日本語組版処理の要件（JLReq）、<https://www.w3.org/TR/jlreq/>（図版を送ったときの行アキの扱いは定めていない）
- LaTeX2e のソースの `ltfloat.dtx`（浮動体の仕組み）
