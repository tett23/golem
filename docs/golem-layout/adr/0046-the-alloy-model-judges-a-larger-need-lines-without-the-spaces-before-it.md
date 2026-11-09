# ADR 0046: Alloy のモデルの `spaceKeeps35` を、前の空きを数えない判定に改める

ステータス: 採択（未実装）

## 文脈

2026-11-09 の監査で、[golem-layout ADR 0033](0033-read-waiting-figures-from-the-placement.md)、[0035](0035-a-larger-need-lines-after-a-judged-one-is-judged-again.md)、[0043](0043-spaces-before-need-lines-are-not-counted-either.md)、[0044](0044-read-the-figures-moved-by-need-lines-judged-before-spaces.md) の実装を ADR の文と照らした（origin/main `81e1d187`）。
改ページ（`Paginate.hs`）、述語（`PaginateInvariants.hs`）、仕様書は、どれも ADR のとおりだった。
一つだけ、改ページの Alloy のモデルが、[ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) の後の改ページと逆のことを言っている。

### モデルは、より大きい `@need-lines` の判定に前の空きを数える

[ADR 0035](0035-a-larger-need-lines-after-a-judged-one-is-judged-again.md) の実装（[#710](https://github.com/tett23/golem/pull/710)）は、モデルに述語 `spaceKeeps35` と関数 `judgedBefore` を足した（[`pagination.als`](https://github.com/tett23/golem/blob/81e1d1870965141ed297c408790270dd3e006897/docs/golem-layout/models/pagination.als#L475-L504)）。
`judgedBefore` は、`placedBefore`（空きを数えない、段に置いた行の数）に、その項目より前に置いた空きの数を足す。
`spaceKeeps35` は、前のどれよりも大きい `@need-lines` を、`judgedBefore` で、つまり前に置いた空きを数えて判定し直す。
モデルの README も「書いた位置で、前に置いた空きを数えて判定し直す」と書く（[`README.md` の 81 行](https://github.com/tett23/golem/blob/81e1d1870965141ed297c408790270dd3e006897/docs/golem-layout/models/README.md#L81)）。

これは、0035 を実装した時点の改ページのとおりだった。
その後の [ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) は、`@need-lines` の前に置いた空きも判定の残りに数えないと決め、実装（[#759](https://github.com/tett23/golem/pull/759)）は、合わせて増えた `@need-lines` も `needAfterSpaces` から `needBeforeSpaces` へ渡し、空きを置く前の位置で判定するようにした（[`Paginate.hs` の 185 行から 215 行](https://github.com/tett23/golem/blob/81e1d1870965141ed297c408790270dd3e006897/modules/golem-layout/src/Golem/Layout/Paginate.hs#L185-L215)）。
仕様書もそう書く（[docs/specifications.md](../../specifications.md) の「改ページの手での制御」の `@need-lines` の文の「増えた値の前に空きを置いていれば、増えた値も空きを置く前の位置で判定する」）。

0043 の「実装すること」は、仕様書と [ADR 0027](0027-need-lines-judged-again-after-spaces.md) のステータスの行を挙げ、モデルを挙げていない。
0044 は「Alloy のモデルを変えること」を「実装しないこと」に置いた。
0044 が直した述語の読み方の食い違いはモデルにないからであり、0035 の述語の判定の位置については何も言っていない。
つまり、モデルのこの食い違いは、どの ADR の不履行でもなく、0043 が見落とした更新である。

### ブロックの最初の `@need-lines` は、すでに空きを数えない

`placedBefore` は、`Text - Space` を数える（[`pagination.als` の 387 行から 389 行](https://github.com/tett23/golem/blob/81e1d1870965141ed297c408790270dd3e006897/docs/golem-layout/models/pagination.als#L387-L389)）。
`spaceKeeps`（P7）と `needMet`（P1）は `placedBefore` で判定するので、ブロックの最初の `@need-lines` の判定は、0043 のとおり前の空きを数えていない。
空きを数えるのは、`spaceKeeps35` の、より大きい `@need-lines` の分岐だけである。

## 実装すること

1. `spaceKeeps35` の、より大きい `@need-lines` の判定を、`judgedBefore` から `placedBefore` に改める。`judgedBefore` は使われなくなるので消す。述語の注釈の「the spaces placed before it counted」を、数えないことに改め、[ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) へのリンクを書く。
2. README の `spaceKeeps35` の行を、「前に置いた空きを数えずに判定し直す（[ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md)）」に改める。
3. [ADR 0035](0035-a-larger-need-lines-after-a-judged-one-is-judged-again.md) のコマンド `needMoreSome`、`needMore27`、`needMoreNone` を、README の「走らせ方」のとおりスコープ 2 から 4 で走らせ直し、結果を README の 0035 の節に、日付とともに書き足す。`nightly.txt` の `needMoreNone none 4` は、結果が変わらなければそのままとし、変われば [ADR 0242](../../adr/0242-run-the-heavy-commands-of-the-alloy-models-every-night.md) の手順で直す。2026-11-09 の時点で、この三つのコマンドは、改めたモデルではまだ走らせていない。README に足す結果の行は、走らせた人が日付とともに書く。
4. [ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) のステータスの行に、モデルの更新はこの ADR で行ったことを書く。

## 実装しないこと

- **改ページ、述語、仕様書を変えること**：どれも [ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) のとおりである。
- **0044 の読み方をモデルに写すこと**：0044 の「実装しないこと」のとおり、モデルの `waitingIn` は配置から待つ図版を決めるので、述語の読み方の食い違いはモデルにない。
- **`needMoreNone` をスコープ 5 で走らせること**：[ADR 0242](../../adr/0242-run-the-heavy-commands-of-the-alloy-models-every-night.md) の記録のとおり、ランナーの上限を過ぎても終わらない。

## 不変条件

- **M1 判定の位置が一つ**：モデルのどの `@need-lines` の判定も、`placedBefore`（空きを数えない）で行う。空きを数えるのは、段に物理的に入るかを見るところだけである。`load`、`loadBefore`、`figure`、`figures`、`figures27` がそれに当たり、`#{t: Text | …}` が `Space` を `Text` の一つとして数える。段に入るかは置いた空きの行を含めて決まるので、これは正しい。`needNext` は次のブロックから `Space` を除くが、行の数を数えはしない。
- **M2 0035 の形の解**：`needMoreSome` と `needMore27` はスコープ 4 で解を持ち、`needMoreNone` はスコープ 4 までに解を持たない。これは [ADR 0035](0035-a-larger-need-lines-after-a-judged-one-is-judged-again.md) の実装の結果と同じである。

境界の入力は、Alloy の全数の探索がスコープの中のすべてを調べるので、表にしない。
M1 はモデルを読んで確かめる。

## テスト設計

- M1：`pagination.als` を二つの検索で読む。自動のテストにはしない。
  - `rg -n 'Space' pagination.als` は、空きを除くところ（`Text - Space`、`Item - Space`）を見つける。`placedBefore` と `needNext` のほかに、`@need-lines` の判定に関わるものがないことを確かめる。
  - 空きを数えるところは `Space` の名を書かないので、この検索では見つからない。`rg -n '#\{t: Text \|' pagination.als` で読み、どれも M1 に挙げた、段に入るかを見る関数か述語の中にあることを確かめる（`tpos` は順番を決めるだけで、行の数ではない）。
- M2：`scripts/models/check.sh` を `nightly.txt` で走らせ、`needMoreSome found`、`needMore27 found`、`needMoreNone none 4` のままであることを確かめる。毎晩の `enum.yml` のモデルの段でも確かめられる。
- 改めた判定：[ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) のテスト設計の P10 の形（`[EPara 1, ESpace, ENeedLines, EPara 1]`、段の行の数 3）は、`@need-lines` が一つしかない。より大きい `@need-lines` の分岐に入らず、`judgedBefore` を使っていた前のモデルでも同じ解を持つので、この ADR の変更を確かめない。代わりに、`@need-lines` を二つ持つ次の入力で確かめる。段の行の数は 4 で、1 行を使っている。そこへ `@need-lines 1`、空き、`@need-lines 3`、1 行の段落が来る。二つめの `@need-lines 3` は、空きを数えなければ残り 3 行で満たされ、段落はこの段に置かれる。前のモデルは空きを数えて残り 2 行で判定するので、段落を次の段へ送る配置も許す。

  ```alloy
  run needMoreSpace46 {
    Col.cap = 4 and Col.used = 1 and no Figure and no Blank and no Heading and #Line = 1 and #Need = 2 and #Space = 1
    some p: Placement, sp: Space, n, m: Need, b: Line |
      n.pos = 0 and sp.pos = 1 and m.pos = 2 and b.pos = 3 and n.lines = 1 and m.lines = 3
        and base27[p] and needMet[p] and spaceKeeps35[p] and here[p, sp] and not here[p, b]
  } for 4 but 5 Int, 8 Placement
  ```

  改めたモデルでは解がない（none）ことを確かめる。最後の `not here[p, b]` を `here[p, b]` にしたコマンドは、解を持つ（found）ことを確かめる。2026-11-09 に、alloy6 6.2.0 で、README の「走らせ方」と同じ `alloy6 exec -q -n -t text` でこの二つを走らせた。準備した実装のモデルでは none と found で、origin/main（`87857c6e`）のモデルではどちらも found だった。コマンドは README に書き、`expected.txt` には足さない（軽いコマンドなので、足してもよい。実装のプルリクエストで時間を測って決める）。

## トレードオフ

モデルを実装に合わせて直すので、モデルが実装の誤りを写すおそれがある。
ただし、この点は [ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) が仕様として決め、列挙（P9、P10）がすでに確かめている。
モデルが決めていない規則を実装が先に決めたのではなく、決めた規則をモデルが追っていないだけである。

`judgedBefore` を消すと、0035 を実装した時点の改ページの振る舞いは、モデルから読めなくなる。
git の履歴と 0035、0043 の文に残る。

## メンテナーが決めること

1. **モデルを 0043 に合わせるか**：推奨は、合わせることである。モデルと README が、仕様書と実装の逆を言ったままでは、モデルを読んで規則を知る人を誤らせる。
   - 退けた案は、README にだけ食い違いを書いて残すことである。毎晩のモデルの検査が、仕様と違う規則を確かめ続ける。

## 決めたことの記録

2026-11-09 に、tett23 が推奨のとおりに決めた。

1. モデルと README を [ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md) に合わせる。

## 参考文献

- [golem-layout ADR 0027](0027-need-lines-judged-again-after-spaces.md)、[golem-layout ADR 0035](0035-a-larger-need-lines-after-a-judged-one-is-judged-again.md)、[golem-layout ADR 0043](0043-spaces-before-need-lines-are-not-counted-either.md)、[golem-layout ADR 0044](0044-read-the-figures-moved-by-need-lines-judged-before-spaces.md)
- [docs/adr/0204](../../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md)、[docs/adr/0242](../../adr/0242-run-the-heavy-commands-of-the-alloy-models-every-night.md)
- [docs/golem-layout/models/README.md](../models/README.md)、[docs/golem-layout/models/pagination.als](../models/pagination.als)
