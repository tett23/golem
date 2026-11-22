# ADR 0414: [ADR 0370](0370-tracking-inline-boxes.md) と [ADR 0395](0395-bring-the-pull-request-ci-under-five-minutes.md) の実装が ADR を越えて決めた点を記録する

Status: accepted

## 文脈

2026-11-18 に、[ADR 0370](0370-tracking-inline-boxes.md) と [ADR 0395](0395-bring-the-pull-request-ci-under-five-minutes.md) を実装した。
実装のプルリクエストは、ADR の文が決めていない点を実装で決め、確かめてほしいとして挙げた。
tett23 は 2026-11-23 に、どれも実装のとおりとすることを決めた。
この ADR は、[ADR 0282](0282-record-what-the-implementations-of-adr-0274-and-0275-decided.md) と同じく、それらを決めたこととして記録する。

## 調査した事項

`origin/main`（`b540aa68a`）で確かめた。

### [ADR 0370](0370-tracking-inline-boxes.md)

- ADR は、縦中横とルビをそれぞれ外側の一つの箱として数え、隣り合う箱のあいだに一度だけトラッキングを足し、行末には足さないと書く。
  「箱」にふつうの字を含むかは書いていない。
- 実装は、ふつうの字も一つの箱として数える。
  そのため、縦中横やルビの後にふつうの字が続けば、そのあいだにトラッキングが入る。
  仕様書は、「ルビと縦中横は、それぞれを外から見て一つの箱として、箱の後ろに一度だけ足す」と書く（[docs/specifications.md](../specifications.md) の 2661 行）。
- ADR は HTML と EPUB に触れていない。
  HTML と EPUB のトラッキングは、今の `letter-spacing` のままである（同 2674 行）。
  `letter-spacing` は字ごとに空きを足すので、ルビの読みの中や縦中横の中にも空きが入りうる。
  ブラウザーでの見え方は確かめていない（未確認）。

### [ADR 0395](0395-bring-the-pull-request-ci-under-five-minutes.md)

- I2 は、キャッシュを消すスクリプトが、同じプルリクエストの `dist-` のキャッシュのうち、作った日時の最も新しいもの以外を消すと書く。
- 実装（`scripts/ci/pr-caches.sh`）は、キャッシュのキーから最後の部分（コミットのハッシュ）を除いたもの（族）ごとに、最も新しいものを残す。
  族のキーは `runner.arch` を含むので、プルリクエストごとに、アーキテクチャの数（今は x86-64 と ARM64 の二つ）だけ残る。
- ADR は、一つのプルリクエストのキャッシュの組を約 970 MB と見積もっている。
  この見積もりが、アーキテクチャごとの一組か、二組の合計かは、ADR の文から決まらない。

## 実装すること

次のことを、決めたこととして記録する。
コードは変えない。

1. **ふつうの字とのあいだのトラッキング**：縦中横とルビの箱の後にふつうの字が続くときも、そのあいだにトラッキングを一度だけ足す。
   トラッキングをかけた行の中で、縦中横やルビの前後だけ字間が詰まらないようにするためである。
2. **HTML と EPUB のトラッキング**：HTML と EPUB は、今の `letter-spacing` のままとする。
   ルビの読みの中と縦中横の中にも空きが入りうることを、PDF との差として受け入れる。
   仕様書のトラッキングの節に、この差を書く。
3. **プルリクエストごとに残すキャッシュ**：[ADR 0395](0395-bring-the-pull-request-ci-under-five-minutes.md) の I2 の「最も新しいもの以外を消す」は、族ごとに読む。
   族は、キャッシュのキーからコミットのハッシュを除いたものであり、アーキテクチャのほか、`cabal.project` と `cabal.project.freeze` と `fetch-wasmtime.sh` のハッシュも含む。
   プルリクエストごとに、族の数（ふつうはアーキテクチャの数）だけキャッシュが残る。
   [ADR 0395](0395-bring-the-pull-request-ci-under-five-minutes.md) の境界の表の「同じプルリクエストの `dist-` が二つ → 古いほうだけ消す」は、同じ族の二つと読む。

採択したら、[ADR 0370](0370-tracking-inline-boxes.md) と [ADR 0395](0395-bring-the-pull-request-ci-under-five-minutes.md) のステータスの行に、この ADR による補足を足す。
部分の名前は、0370 は「箱とふつうの字のあいだ、HTML と EPUB」、0395 は「I2 の残すキャッシュの単位」とする。

## 実装しないこと

- HTML と EPUB で、縦中横とルビを一つの箱として扱うトラッキングは実装しない。
- キャッシュの容量の見積もりを測り直すことは、この ADR では扱わない。
  合計が 9 GB を超えたら古いものから消す規則（[ADR 0395](0395-bring-the-pull-request-ci-under-five-minutes.md) の項目 5）が、上限を守る。

## 不変条件

項目 1 だけを不変条件にする。
項目 2 と 3 は、今の振る舞いと仕様書の記述であり、[ADR 0370](0370-tracking-inline-boxes.md) と [ADR 0395](0395-bring-the-pull-request-ci-under-five-minutes.md) の今のテストが確かめている。

- I1：トラッキング t の行のどの位置でも、縦中横かルビの箱と、その前か後のふつうの字のあいだに足す空きは、ちょうど t である（行末の箱の後ろには足さない）。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| 縦中横の後にふつうの字 | あいだに t | I1 |
| ふつうの字の後にルビ | あいだに t | I1 |
| 行末の縦中横 | 後ろに足さない | I1 |
| トラッキング 0 | 空きは 0 | I1 |

## 受けいれ条件

なし。
この ADR の振る舞いは、不変条件のテストで確かめる。

## テスト設計

- 仕様書を直した後、`sh scripts/ci/textlint.sh origin/main` が通ることを確かめる。
- I1 のテストを `root ADR 0414 I1: ...` の名前で golem-layout に置く。
  境界の表の行と、縦中横、モノルビ、グループルビとふつうの字の長さ 0 から 3 のすべての並びを、トラッキング -100、0、100 で確かめる。
  今の実装で通るので、先に失敗させる手順の例外とし、通ることを実装の前に確かめてプルリクエストに書く。

## トレードオフ

HTML と EPUB のトラッキングを PDF とそろえるには、縦中横とルビの中の字に `letter-spacing` を打ち消す CSS を足す必要がある。
ブラウザーごとの差を確かめる手間に見合わないので、差として受け入れる。

## 参考文献

- [ADR 0370](0370-tracking-inline-boxes.md)
- [ADR 0395](0395-bring-the-pull-request-ci-under-five-minutes.md)
- [ADR 0282](0282-record-what-the-implementations-of-adr-0274-and-0275-decided.md)
