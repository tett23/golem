# ADR 0020: 段の残りの行より高い見出しを notice で知らせる

ステータス: 採択

## 文脈

見出しはページをまたいで分けない（[ADR 0003](0003-pagination-and-s2.md)、[golem-driver ADR 0003](../../golem-driver/adr/0003-pdf-heading-styles.md)）。
一ページの行数より多くの格子の行を占める見出しは、golem-driver が組む前にエラー G07024 とし、PDF を書かない（[golem-driver の G07024](https://github.com/tett23/golem/blob/dc451b46882b91d6fc57c516076471086b3465e3/modules/golem-driver/src/Golem/Driver/Pdf.hs#L2336-L2346)）。
比べる相手は一ページの行数であり、見出しを置く段の行数ではない。

ページ分けは、見出しが今の段に入らなければ次の段に送り、空の段なら入らなくても置く（[見出しの置き方](https://github.com/tett23/golem/blob/dc451b46882b91d6fc57c516076471086b3465e3/modules/golem-layout/src/Golem/Layout/Paginate.hs#L543-L546)）。
空の段に置いた見出しが段の行数を超えても、ページ分けは何も記録しない（[`putBlock`](https://github.com/tett23/golem/blob/dc451b46882b91d6fc57c516076471086b3465e3/modules/golem-layout/src/Golem/Layout/Paginate.hs#L814-L830)）。
罫線を持つ見出しも、罫線を省いてなお入らなければ同じ `putBlock` で置く（[`splitRuled`](https://github.com/tett23/golem/blob/dc451b46882b91d6fc57c516076471086b3465e3/modules/golem-layout/src/Golem/Layout/Paginate.hs#L775-L787)）。
ロードマップの未決事項「版面の行数より高い見出し」は、この振る舞いを [ADR 0067](../../adr/0067-generators-missing-boundary-inputs.md) の確認で見つけた（一行のページに二行取りの見出し）。
メンテナーは、これを diagnostic にすると決めた。
重大度は notice とし、置き方は変えない。

### どこで起きるか

golem-layout の `paginate` を直接呼べば、一ページの行数より高い見出しを渡せる。
ロードマップの例はこの形である。
golem-driver は、その見出しを G07024 で止め、ページ分けを呼ばない（[`round'`](https://github.com/tett23/golem/blob/dc451b46882b91d6fc57c516076471086b3465e3/modules/golem-driver/src/Golem/Driver/Pdf.hs#L990-L992)）。
したがって `golem build` で起きるのは、空の段の行数が一ページの行数より少ないときに限る。

段の行数を一ページの行数より減らすのは、今は `@page-lines` の負の値だけである（[docs/adr/0030](../../adr/0030-manual-page-break-control.md)）。
`@page-lines` は今の段の行数に足し、段には少なくとも一行を残す（[`adjustLines`](https://github.com/tett23/golem/blob/dc451b46882b91d6fc57c516076471086b3465e3/modules/golem-layout/src/Golem/Layout/Paginate.hs#L418-L427)）。
段の始まりで `@page-lines -15` を書けば、十六行の版面に一行の段ができる。
増減は次の段で 0 に戻る（[`advance`](https://github.com/tett23/golem/blob/dc451b46882b91d6fc57c516076471086b3465e3/modules/golem-layout/src/Golem/Layout/Paginate.hs#L847-L858)）。
見出しの `lines` の既定の値は一ページの行数で切り詰めるが、`@page-lines` で減らした段の行数では切り詰めない（[`headingLines`](https://github.com/tett23/golem/blob/dc451b46882b91d6fc57c516076471086b3465e3/modules/golem-driver/src/Golem/Driver/Pdf.hs#L612-L614)）。

ほかに段の行が減る場面は、見出しには関わらない。
索引の段はページの途中から始まり、前の段組みの脚注の行を残すが、索引の段に置くのは索引の項目の行だけである。
前のページから続く脚注のある段は空とみなさないので（[`isEmpty`](https://github.com/tett23/golem/blob/dc451b46882b91d6fc57c516076471086b3465e3/modules/golem-layout/src/Golem/Layout/Paginate.hs#L528-L529)）、入らない見出しは次の段に送られる。

### 確かめたこと

origin/main（dc451b46）を `cabal build exe:golem` でビルドし、`golem new` の雛形（縦組み、A6、十六行）で組んだ。

| 原稿の冒頭 | 見出し | PDF のページ数 | diagnostic |
| --- | --- | --- | --- |
| なし | `#`（五行取り） | 1 | なし |
| `@page-lines -15` | `#`（五行取り） | 2 | なし |
| `@page-lines -15` | `###`（二行取り） | 2 | なし |
| `@page-lines -10` | `#`（五行取り） | 1 | なし |

一行の段に五行取りと二行取りの見出しを置き、続く本文は次のページに送られた。
見出しは、書き手が `@page-lines` で取り除いた行に組まれ、終了コードは 0 だった。
六行の段では、見出しと本文の一行が一ページに入った。
`golem check` はページ分けを行わないので、G07024 も G07037 も出さない（`[headings.2]` の `lines = 20` で、`golem check` は終了コード 0、`golem build` は G07024 で終了コード 1）。

### 近い diagnostic

| コード | 重大度 | 場面 | PDF |
| --- | --- | --- | --- |
| G07024 | error | 見出しが一ページの行数を超える | 書かない |
| G07038 | error | 図版のキャプションが段の行数に達する | 書かない |
| G07039 | notice | 図版を段に収めるために縮めた | 書く |
| G07037 | warning | `@page-lines` などの指定を決まった規則で切り詰めた | 書く |
| G07046 | notice | 罫線を持つ段落か見出しが空の段に入らず、罫線を省いた | 書く |
| G07100（この ADR） | notice | 見出しが `@page-lines` で減らした段の残りより高い | 書く |

G07037、G07039、G07046 は、Golem が仕様に書いた規則で入力を変えて組んだことを知らせる。
G07100 では、Golem は入力を変えない。
見出しは段の頭から書いたとおりの行取りで組まれ、書き手が `@page-lines` で取り除いた行にはみ出す。

## 実装すること

### ページ分けの記録（golem-layout）

- `Unmet` に構成子 `TallHeading !Int !Int !Int` を足す。見出しの最初の行の番号、見出しが占める格子の行の数、置いた位置で段に残っていた格子の行の数（`free`）である。
- `putBlock` で見出しを置くとき、見出しの格子の行の数が段の残り（`free`）を超えれば、その段の `poUnmet` に `TallHeading` を加える。罫線を持つ見出しを `splitRuled` から置く場合も同じである。
- 見出しの置き方は変えない。見出しは空の段に置いたまま、続くものは次の段から置く。[docs/adr/0067](../../adr/0067-generators-missing-boundary-inputs.md) のプロパティ（すべての行を一度ずつ順に置く、ページの番号に抜けがない）はそのまま成り立つ。
- 注の行は数えない。見出しの格子の行が段に入り、見出しの注だけが入らない場合は、今のとおり注を次のページに続ける（[ADR 0013](0013-heading-footnotes.md)）。

### 新しいコード G07100（golem-driver、golem-syntax）

- `TallHeading` を、notice の G07100 として報告する。段階はレイアウト（07）で、新しいコードなので番号は 100 から取る（[docs/adr/0061](../../adr/0061-five-digit-diagnostic-codes.md)）。
- G07100 を golem-syntax の `noticeCodes` に足す。
- ほかの notice と同じく、G07100 は終了コードに影響せず、プロファイルで重大度が変わらず、出力のバイト列を変えない。`silence-notices` と `--no-notices` で抑制できる。
- PDF は書く。見出しは今のとおり段の頭に置き、段の残りの行の外にはみ出したまま組む。
- 位置は見出しの位置である。
- メッセージは次のとおりとする。`<階層>` と `<題>` は G07024 と同じものである。注の一覧の見出しでは、括弧の中の前半を `注の一覧の見出し: <題>` とする。

  ```
  見出しが段に入りません（<階層> の見出し: <題>。見出しは <n> 行、段の残りは <m> 行）
  ```

- 改ページの繰り返し（S2）の最後の回のページから求める。G07037 と同じである。
- 見出しの最初の行の番号から、位置とメッセージの見出しの部分を引く表を、G07024 を作る `buildFlow` で作る。
- 一ページの行数を超える見出しは、今のとおり G07024 だけを出す。G07024 があればページ分けは走らないので、同じ見出しに G07100 が重ねて出ることはない。
- `golem check` は、今のとおりページ分けを行わないので、G07100 を出さない。

### 文書

- [docs/specifications.md](../../specifications.md) の見出しの段落（G07024 の文）に、段の残りより高い見出しを置いたまま notice の G07100 で知らせることを足す。「改ページの手での制御」の箇条書きに、`@page-lines` で減らした段に見出しが入らなければ G07100 であることを足す。notice の一覧の段落に G07100 を足す。
- [docs/diagnostics.md](../../diagnostics.md) に G07100 の節を G07052 の後に足し、「お知らせ」の表に足す。G07024 の節の「意味」に、段の行数を `@page-lines` で減らした場合は G07100 であることを足す。
- マニュアルの付録 E（`manual/appendices/e-errors.gm`）の「紙面に収まらないとき」に、G07024 の次に G07100 を足す。直し方は、`@page-lines` の減らす行を少なくするか、`@page-lines` を見出しの後に移すか、見出しの `lines` を減らすことである。意図した組み方なら直さなくてよく、`silence-notices` で抑制できることも書く。
- マニュアルの「改ページの手での制御」（`manual/chapters/03-markup.gm`）の G07037 の文の後に、減らした段に見出しが入らなければ、見出しを置いたまま notice（G07100）を出すことを足す。
- [docs/roadmap.md](../../roadmap.md) の未決事項から「版面の行数より高い見出し」を消す。図版、表、コードブロック、回り込む図版が `@page-lines` で減らした段に入らない場合（「実装しないこと」）を、新しい未決事項として足す。

## 実装しないこと

- 見出しを入れるために `@page-lines` を切り詰めること。G07037 の `AdjustLinesPlaced` と同じ扱いにもできるが、段の行数を決めた後に置くものを見て決め直すことになり、ページ分けが一方向に進まなくなる。
- 図版、表、コードブロック、回り込む図版が段の残りより大きい場合の diagnostic。どれも空の段なら入らなくても置く（[図版](https://github.com/tett23/golem/blob/dc451b46882b91d6fc57c516076471086b3465e3/modules/golem-layout/src/Golem/Layout/Paginate.hs#L548-L551)、[表](https://github.com/tett23/golem/blob/dc451b46882b91d6fc57c516076471086b3465e3/modules/golem-layout/src/Golem/Layout/Paginate.hs#L535-L540)、[回り込む図版](https://github.com/tett23/golem/blob/dc451b46882b91d6fc57c516076471086b3465e3/modules/golem-layout/src/Golem/Layout/Paginate.hs#L556-L561)、[コードブロック](https://github.com/tett23/golem/blob/dc451b46882b91d6fc57c516076471086b3465e3/modules/golem-layout/src/Golem/Layout/Paginate.hs#L611-L615)）。図版は一ページの行数に収めて縮めるので（G07039）、`@page-lines` で減らした段では同じことが起きうる。原因ごとにコードを分けるので、この ADR のコードには含めず、ロードマップの未決事項に移す。実機では確かめていない。
- 段の残りより高い見出しの置き方を変えること（次のページに送る、見出しを縮めるなど）。notice は出力を変えないので、置き方は今のまま、段の頭から書いたとおりの行取りで組む。はみ出しを書き手が意図した組み方として残すためでもある。
- G07100 を警告やエラーにする設定。notice の重大度はプロファイルで変わらない。
- `golem check` でページ分けを行うこと。

## テスト設計

先に書き、今の実装で失敗することを確かめる。
golem-layout のテストは、`TallHeading` がないのでコンパイルに失敗する。

### golem-layout（`modules/golem-layout/test/PaginateSpec.hs`）

- 一行のページに二行取りの見出し：`paginate 1 1 [FHeading 2 False 2 (lines' 0 1), FParagraph (lines' 10 1)]` で、一ページ目の `poUnmet` が `[TallHeading 0 2 1]` であり、見出しは一ページ目、行 10 は二ページ目にある。
- `@page-lines` で減らした段：`paginate 1 16 [FAdjustLines mk (-15), FHeading 1 False 5 (lines' 0 1), FParagraph (lines' 10 1)]` で、`unmets` が `[TallHeading 0 5 1]` であり、置き方は今と同じである。
- 境界：`FAdjustLines mk (-11)`（五行の段）に五行取りの見出しを置くと、`TallHeading` はない。
- 空でない段で入らない見出しは次の段に送るので、`TallHeading` はない（`paginate 1 5 [FParagraph (lines' 0 4), FHeading 2 False 2 (lines' 10 1), FParagraph (lines' 20 1)]`）。
- 罫線を持つ見出しが罫線を省いても一行の段に入らない場合に、`TallHeading` を記録する。
- 見出しの格子の行は段に入り、注だけが入らない場合は `TallHeading` を記録しない。
- プロパティ：`genBlocks` と容量 1 から 9 で、`TallHeading` を持つ見出しの集合が、段の終わりを越える見出しの集合（「the slots of a page do not overlap and end within the page」が容量 2 以上に限って除いているもの）と一致する。

### golem-driver（`modules/golem-driver/test/PageElementsSpec.hs`）

- 三十行の版面で `@page-lines -29` の後に `# A`（既定の行取り）を置くと、ビルドは成功して PDF を書き、diagnostic は notice の G07100 だけである。メッセージは `見出しが段に入りません（1 の見出し: A。見出しは 5 行、段の残りは 1 行）` で、位置は見出しである。
- 同じ原稿で、`silence-notices = ["G07100"]` を書いたビルドと `--no-notices` を付けたビルドは diagnostic を出さず、PDF のバイト列（インスタンス ID を除く）は抑制しないビルドと同じである。
- `@page-lines -25`（五行の段）では、diagnostic はなく PDF を書く。
- 今の「a heading taller than the page is an error」と「the default lines are cut to a page of three lines; lines = 4 is G07024」は変えず、G07024 だけが出ることを確かめ続ける。

### golem-driver（`modules/golem-driver/test/DiagnosticsSpec.hs`）

- すべての notice を出すプロジェクト（`everyNoticeProjects`）に、`@page-lines` で減らした段に置く見出しを足し、G07100 も出す。「no notice of noticeCodes changes the outputs of the four targets」が、G07100 を含むすべての notice を抑制しても四つのターゲットの出力が変わらないことを確かめる。

### golem-syntax（`modules/golem-syntax/test/Main.hs`）

- `noticeCodes` の一覧のテストに G07100 を足す。

### 文書

- golem-driver のテスト（`modules/golem-driver/test/Main.hs`）が、ソースの G07100 が docs/diagnostics.md に状態「使用中」で載り、重大度が「お知らせ」であることを確かめる。

## トレードオフ

重大度を error にして PDF を書かない案もある。
仕様書の「緩い規則より厳しい規則」は、入力が仕様に反するときは推測で補わずに止めると定める。
しかし段の行を `@page-lines` で意図して減らし、その段に高い見出しを置くことは、仕様に反しない。
段の行を意図して減らし、その段に高い見出しだけを置く特殊な組み方では、見出しが段からはみ出すことを書き手が求めている。
error にすれば、その組み方は Golem で作れなくなる。
したがって、Golem は書き手に知らせ、止めない。

同じ見出しが一ページに入らない G07024 は error のままである。
G07024 の見出しは、どの段に置いても一ページの版面の外にはみ出す。
書き手がどう指定しても、意図した組み方として成り立たない。
G07100 の見出しは一ページの行数に収まるので（G07024 がないことで保証される）、はみ出す先は書き手が `@page-lines` で取り除いた版面の中の行である。
G07024 と G07100 の重大度の違いは、段とページの違いではなく、はみ出しが組み方として成り立つかどうかの違いである。

重大度を warning にする案もある。
G07037 は `@page-lines` を守れなかったことを warning で知らせるので、それとそろう。
しかし warning は直すべきものに使い、直さなくてよいものは notice にする（[golem-syntax ADR 0002](../../golem-syntax/adr/0002-notice-severity.md)）。
G07037 は、Golem が仕様に書いた規則で書き手の指定を切り詰め、書き手の指定と違う出力を作ったことを知らせる。
G07100 では、Golem は書き手の `@page-lines` と見出しの行取りをどちらも書いたとおりに組む。
意図した組み方なら直す必要はないので、notice にする。

代わりに、意図せず `@page-lines` の段に高い見出しを置いた書き手は、notice を見落とすか、`--no-notices` で消したまま気付かないことがある。
notice は既定では表示されるので、`--no-notices` を付けない限り、書き手は少なくとも一度は目にする。
`@page-lines` は組んだ PDF を見て最後に足す指定なので、はみ出しはその PDF でも目に見える。

記録を `Unmet` に足すと、名前（守れなかった手での制御）と中身がずれる。
`DroppedBlank` もすでに手での制御ではないものを運んでおり、`PageOut` に別の欄を足すと、`PageOut` を作る五か所を書き換えることになる。
段ごとの記録を最後の段に寄せる処理（`leftover`）も、そのまま使える。

位置は見出しであり、段の行を減らした `@page-lines` ではない。
ページ分けは、どの `@page-lines` が段を減らしたかを持たない。
メッセージの「段の残りは <m> 行」で、書き手は減らした段であることに気付ける。

## 参考文献

なし
