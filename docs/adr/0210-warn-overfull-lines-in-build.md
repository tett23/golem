# ADR 0210: 行長からはみ出す行を golem build の警告にする

ステータス: 採択（未実装）

## 文脈

利用者のマニュアルの付録 E を PDF で読むと、いくつかの項目の語が版面の右にはみ出している（メンテナーの指摘、2026-11-08）。
はみ出すのは、メッセージを入れた本文の中のコード（`[code: …]`）である。
コードは空白と `/` の後でしか改行しないので、空白のない和文のメッセージは一行に収まらない。
二つのマニュアルは diagnostic が一つでも出れば失敗する `scripts/manual/build.sh` で組んでいるのに、このはみ出しでは CI が止まらない。

同じ現象は、[docs/adr/0178](0178-colophon-commit-line-overflow.md) が奥付の行を直したときにも見つかっていた。
0178 は付録 E のはみ出しを直さず、ロードマップの v0.1.0-rc4 に「本文の中のコードの和文の改行」の項目を足すにとどめた。
CI でプリフライトを走らせて止める案も、付録 E のはみ出しが残るあいだは入れたとたんに失敗するとして、実装しないことにしている。

### 今の報告

はみ出す行を報告するのは `golem preflight` のプリフライトの検査 `overfull-lines`（G09013、組み込みの `print` と `basic` で警告）だけである。
仕様書の「行分割」の節は、はみ出す行を `golem build` では diagnostic にしないと定める（[golem-cli ADR 0006](../golem-cli/adr/0006-preflight.md)）。
`golem build` だけを使う書き手と、二つのマニュアルの CI には、はみ出しを知る手段がない。

コードブロックの行は、収まらなければ折り返し、notice の G07030 で知らせる（[golem-driver ADR 0017](../golem-driver/adr/0017-pdf-code-blocks.md)）。
段落の行には、これに当たる知らせがない。

### はみ出す行ができる仕組み

行分割（[`breakParagraph`](https://github.com/tett23/golem/blob/2550eb4fcd423ed4f467c7b346270dfb02e47f45/modules/golem-layout/src/Golem/Layout/KnuthPlass.hs#L257-L261)）の最後の段は、行長に収まる分割がなくなった位置で、収まらない箱を次の行へ送る（[`pushOut`](https://github.com/tett23/golem/blob/2550eb4fcd423ed4f467c7b346270dfb02e47f45/modules/golem-layout/src/Golem/Layout/KnuthPlass.hs#L344-L353)）。
送れる候補がないとき、つまり改行の位置のあいだの箱の並びだけで行長を超えるときに限り、はみ出す行を作る（[`overfullRescue`](https://github.com/tett23/golem/blob/2550eb4fcd423ed4f467c7b346270dfb02e47f45/modules/golem-layout/src/Golem/Layout/KnuthPlass.hs#L354-L358)）。
詰めや字間の調整で収める処理はなく、その行のグルーを縮みの限度まで縮めたうえで、残りが行末から出る。

はみ出したかどうかは、行の [`lineOverfull`](https://github.com/tett23/golem/blob/2550eb4fcd423ed4f467c7b346270dfb02e47f45/modules/golem-layout/src/Golem/Layout/KnuthPlass.hs#L452) に入る。
条件は、行の自然な幅から縮みの合計を引いてもまだ行長より長いことである。
自然な幅は、行頭と行末の突き出し（ぶら下げ）を引き、ルビの掛かりとトラッキングの戻し（`bcEdgeStart`、`bcEdgeEnd`）を足した幅である。
行分割は、どれだけはみ出したかを数として持たない。

プリフライトは、描いた行ごとに [`overfullOf`](https://github.com/tett23/golem/blob/2550eb4fcd423ed4f467c7b346270dfb02e47f45/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L655-L659) で量を求める。
`lineOverfull` が真の行について、置いた箱の終わりの最大から行長を引き、0 未満なら 0 とする。
量は行分割の条件とは別の式で求めるので、二つは食い違うことがある（「確かめたこと」の最後の項目）。
G09013 の位置は、その行を含む原稿のブロックの始まりである（[`spanOfLine`](https://github.com/tett23/golem/blob/2550eb4fcd423ed4f467c7b346270dfb02e47f45/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L661-L666)）。

本文の中のコードの箱は、[`codePieces`](https://github.com/tett23/golem/blob/2550eb4fcd423ed4f467c7b346270dfb02e47f45/modules/golem-layout/src/Golem/Layout/Japanese.hs#L622-L637) が空白で区切り、[`codeItems`](https://github.com/tett23/golem/blob/2550eb4fcd423ed4f467c7b346270dfb02e47f45/modules/golem-layout/src/Golem/Layout/Japanese.hs#L903-L929) が `/` の後と、欧文と和文の境で分ける。
箱のあいだで改行してよいのは `/` の後だけである。
和文の字のあいだでは改行しないので、空白のない和文は、その全体が一つの改行できない並びになる。

### 確かめたこと

今の `main`（2550eb4f）から `cabal build golem-cli` で golem を作り、次を確かめた。
どの行がはみ出したかは、作業用の写しの `overfullOf` に一時的にトレースを入れて、行の箱の文字列と位置（`bcAt`）を出して調べた。
トレースはコミットしていない。

**最小の再現**：`golem new` の雛形（A6、縦組み、38 字詰め）に、コードの書体（Source Code Pro と Noto Sans JP）を足した本を組んだ。
横組みは、同じ本を `writing-mode = "horizontal"`、24 字詰めにしたものである。

| 段落 | 縦組み | 横組み |
| --- | --- | --- |
| A：空白のない和文のコード（50 字ほど） | 45.31mm はみ出す。地の仕上がりの線を 30.06mm 越える（G09012） | 89.06mm はみ出す。小口の仕上がりの線を 73.06mm 越える |
| B：`[code: https://…/0203-generated-…-driver.md]` | 11.41mm はみ出す | 55.16mm はみ出す |
| C：空白のない長い欧文の語 | はみ出さない | はみ出さない |
| D：`[style url: …]` の同じ URL | はみ出さない | 30.84mm はみ出す（`0203-…-driver.` の箱） |
| E：和文だけの段落 | はみ出さない | はみ出さない |

- どちらの向きでも、`golem build --target pdf` は diagnostic を一つも出さず、終了コード 0 で PDF を書いた。
- `golem preflight` は、はみ出した行ごとに G09013 を出した。位置は段落の始まり（`chapters/01.gm:5:1` など）だった。
- C の長い語がはみ出さなかった理由（分綴の位置が見つかったのか）は確かめていない。
- HTML は、本文の中のコードに `white-space` も `overflow-wrap` も指定しない（[`Golem.Html` の `pre` の規則](https://github.com/tett23/golem/blob/2550eb4fcd423ed4f467c7b346270dfb02e47f45/modules/golem-html/src/Golem/Html.hs#L973) は `pre` だけに `overflow-wrap: anywhere` を付ける）。HTML と EPUB の行を分けるのは読書環境で、Golem は行長を測らない。ブラウザーで描いて確かめてはいない。

**利用者のマニュアル**：`golem build` は diagnostic を出さなかった。
`golem preflight` は G09013 を 6 つと、G09012（文字が仕上がりの線に近すぎる）を 2 つ出した。
6 つはどれも付録 E の項目の語のコードである。

| ページ | 項目 | はみ出し | G09013 の位置 |
| --- | --- | --- | --- |
| 275 | G02134 | 2.11mm | `e-errors.gm:235` |
| 291 | G03029 | 37.86mm（小口の仕上がりの線を 7.86mm 越える） | `e-errors.gm:584` |
| 298 | G08013 | 32.01mm（のどの仕上がりの線を 18.01mm 越える） | `e-errors.gm:726` |
| 315 | G03120 | 8.61mm | `e-errors.gm:1088` |
| 317 | G07046 | 1.62mm | `e-errors.gm:1088` |
| 318 | G07101 | 6.01mm | `e-errors.gm:1088` |

G09013 の位置は、項目ではなく定義の一覧の始まりである。
315、317、318 ページの三つは同じ `e-errors.gm:1088`（G02062 の項目）を指し、どの項目がはみ出したかを位置から引けない。
指摘にあった G03117 の項目は、メッセージの空白で改行できるので、はみ出していなかった。
[docs/adr/0178](0178-colophon-commit-line-overflow.md) が数えた 4 か所（269、276、286、287 ページ）から、ページも数も変わっている。

**開発者のマニュアル**：`golem preflight` は G09013 を 4 つ出した。
どれも脚注の `[style url: https://github.com/tett23/golem/blob/main/docs/adr/0203-generated-modules-instead-of-template-haskell-in-golem-driver.md]` で、`0203-…-driver.` の箱が行長を 0.65mm 超える（33、118、131、179 ページ）。
`url` は `-` の後で改行しない（[golem-layout ADR 0018](../golem-layout/adr/0018-url-line-breaks.md)）。
位置は、脚注ではなく、注を付けた段落の始まりだった。

**CI のほかの入力**：次の入力を、CI と同じフォントを写して `golem preflight` で組み、G09013 もトレースも出ないことを確かめた。
golem-driver の fixture の sample（[scripts/determinism/pdf-style.toml](https://github.com/tett23/golem/blob/2550eb4fcd423ed4f467c7b346270dfb02e47f45/scripts/determinism/pdf-style.toml) の版面）、complex-vertical、complex-horizontal、conformance（横組みと縦組みの両方）、figures、languages、kanikosen、tempest、pd の十冊である。
bibliographies、functions、emet-samples、scripts/determinism、scripts/env-determinism/diagnostics は、PDF の版面を持たないので PDF を組めなかった。
CI もこれらの PDF は組まない。

**量の食い違い**：開発者のマニュアルの `[character-styles.code]` に `tracking = -10` を足して組むと、G09013 が 16 出て、量はどれも `0.00mm` だった（最初は `part1/01-cli.gm:71`、19 ページ）。
`lineOverfull` は真なのに、置いた箱の終わりは行長を超えていない。
負のトラッキングでは、行末で戻すトラッキング（`bcEdgeEnd`）が正になり、行分割の自然な幅だけを長くするためと見られるが、どの行かまでは確かめていない。

### 参照した組み方

仕様書の「仕様が不明瞭な場合」に従い、JLReq、InDesign、TeX の順に調べた。

- JLReq は、行長からはみ出す行を報告するかどうかを定めない。
- InDesign の段落の組み方は、行長を超える行を作るかどうかを含めて、確かめていない。ライブプリフライトには「オーバーセットテキスト」（フレームに入りきらない文字）の検査があるが、行の方向のはみ出しの検査ではない。
- TeX は、はみ出した行を作るたびに `Overfull \hbox (<量>pt too wide)` をログと端末に出す。量が `\hfuzz`（plain TeX では 0.1pt）以下なら出さない。`\overfullrule` を正にすると、はみ出した行の行末に黒い棒を描く。

## 実装すること

### はみ出しの量（golem-layout）

行のはみ出しの量を、行分割が使う条件と同じ式で求める関数を `Golem.Layout.KnuthPlass` に足す。

```haskell
{- | How far a line sticks out past its target (docs/adr ADR 0210): its
natural width, every shrink and the compression of the glyphs taken,
less the target; 0 when it fits.
-}
lineOverflow :: Line -> Sp
```

- 量は、`mkLine` の `natural - shrink - target` と同じ式で、整数の sp で求める。0 未満なら 0 とする。
- `lineOverfull` は、`lineOverflow` が正であることと同値にする。今の `lineOverfull` の条件（`shortfall < 0 && negate shortfall > shrink`）と同じなので、行分割の結果は変わらない。
- 量を `Line` の欄にするか、`Line` から求める関数にするかは、実装で決めてよい。

### G07105（golem build）

PDF をターゲットに含む `golem build` で、はみ出す行を G07105 の警告で報告する。

- 段階はレイアウト（07）とする。番号は、07 の 100 番台で今使っている G07104 の次である（[docs/diagnostics.md の番号の区分](../diagnostics.md#番号の区分)）。ほかの ADR の草稿も G07105 を使っていないことを確かめた。
- 重大度は、dev でも prod でも警告とする（「メンテナーが決めること」の 1）。警告なので、終了コードは変えず、PDF を書く。`silence-notices` と `--no-notices` では抑制できない。
- 対象は、PDF に描くすべての行のうち `lineOverflow` が正の行である。本文、見出し、表のセル、キャプション、脚注、傍注、目次の題の行を含む。今の G09013 と同じ集合である（「メンテナーが決めること」の 4）。
- 描いた行ごとに一つ出す。最初に置いた場所とは別のページにもう一度描く行（`Golem.Typeset.Draw` の `again` が真の行）は、描いたページごとに出す。
- メッセージは、今の G09013 と同じ文言にする。

  ```
  行が行長から <量> はみ出しています（PDF の <ページ> ページ目）
  ```

- `<量>` は `lineOverflow` を mm で書いたものである。0.01mm 単位に切り上げて書く（「メンテナーが決めること」の 3）。切り上げの関数は、単位の換算を一か所に置く [docs/adr/0103](0103-single-place-for-unit-conversions.md) に従い、`Golem.Length` の `mmText` の隣に置く。1sp のはみ出しは `0.01mm` になり、`0.00mm` とは書かない。
- JSON の `facts` に、今の G09013 と同じ `overfull`（メッセージと同じ表記の量）と `pdf-pages` を書く。
- 位置は、行の箱を行頭から順に見て、終わりが行長を超える最初の箱の、最初の字である（「メンテナーが決めること」の 2）。箱の `bcAt` と `bcSource` のファイルから、長さ 0 の位置を作る。その箱が原稿にない字（見出しの番号、目次の題など、`bcAt` が -1）なら、今の G09013 と同じく、その行を含む原稿のブロックの位置とする。
- 並びは、ほかの diagnostics と同じ `sortDiagnostics` に従う。並列で組んでも（`optParallel`）同じになる。
- golem-typeset の [`renderPdfAll`](https://github.com/tett23/golem/blob/2550eb4fcd423ed4f467c7b346270dfb02e47f45/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L99) が、描いた行（`LineRec`）から G07105 を求め、今の notice の一覧の後に足して返す。写し（`View`）を評価させないためである。
- メッセージと量の表記は、golem-preflight から関数として公開し、G07105 と G09013 の両方がこれを使う。golem-typeset はすでに golem-preflight に依存しているので、モジュールのあいだの依存は変えない（[docs/adr/0081](0081-missing-glyphs-warn-in-build.md) の G08100 と G09002 と同じ形）。
- `golem check` と LSP では出さない。組版をしないので、行がない。
- HTML、EPUB、プレーンテキストのターゲットでは出さない。行を分けるのは読書環境で、Golem は行長を測らない。

### G09013（golem preflight）

G09013 の検査とプリフライトの設定の `overfull-lines` は残す（「メンテナーが決めること」の 5）。
`golem preflight` は、はみ出す行について、ビルドの G07105 とプリフライトの G09013 を並べて出す（[docs/adr/0081](0081-missing-glyphs-warn-in-build.md) の G08100 と G09002 と同じ関係）。

- G09013 の量を、G07105 と同じ `lineOverflow` の切り上げにする。今の `overfullOf`（置いた箱の終わりから行長を引いた量）はやめる。
- G09013 の位置を、G07105 と同じ位置にする。
- 二つは同じ行について、同じ位置、同じメッセージ、同じ `facts` で並ぶ。重大度は、G07105 が警告、G09013 が `overfull-lines` の `severity` による。

### マニュアル

G07105 を足すと、今の二つのマニュアルは `build.sh` で失敗する。
実装のプルリクエストで、次のとおり原稿を直し、マニュアルを diagnostic なしに保つ（「メンテナーが決めること」の 6 と 7）。

- 利用者のマニュアルの付録 E（`manual/appendices/e-errors.gm`）の六つの項目の語のメッセージを、行に収まるところで切り、残りを `…` にする。

  | 項目 | 今の語のコード | 直した語のコード |
  | --- | --- | --- |
  | G02134 | `キャプションのないコードブロックは番号を持たないので、@nonumber は要りません` | `キャプションのないコードブロックは番号を持たないので、…` |
  | G03029 | `\[hidden-folio\] の gutter（…）が size（…）の半分（…）より小さいため、隠しノンブルの数字が仕上がりの線を越えます（…）` | `\[hidden-folio\] の gutter（…）が size（…）の半分（…）より小さいため、…` |
  | G08013 | `出力先がシンボリックリンクかディレクトリではないので、消すことも書くこともしません: …` | `出力先がシンボリックリンクかディレクトリではないので、…` |
  | G03120 | `段落の区切り方を書いていないので、改行の様式（paragraph-separator = "line"）で読みます` | `段落の区切り方を書いていないので、…` |
  | G07046 | `罫線を持つ段落が版面に入らないため、罫線を省いて分けて組みました` | `罫線を持つ段落が版面に入らないため、…` |
  | G07101 | `ダッシュの字形に線がないので、二倍ダッシュの線をつながずに描きます: …（…）` | `ダッシュの字形に線がないので、…` |

  作業用の写しでこの六つを直して `golem preflight` で組み、G09013 も G09012 も出ないことを確かめた。
  付録 E の冒頭の、メッセージの `…` の部分に名前やファイルのパスが入るという文に、長いメッセージの後ろも `…` で略すことを書き足す。
  略した部分は、各項目の説明の文に書かれていることを、実装のときに一つずつ確かめる。
- 開発者のマニュアルの `style.toml` の `[character-styles.url]` に `tracking = -10` を足す。作業用の写しで組み、G09013 が出なくなることを確かめた。脚注の URL はすべて字の送りが 1000 分の 10 だけ詰まる。
- どちらも原稿の変更なので、マニュアルの方針に従い、ADR は要しない。この ADR の実装と同じプルリクエストに入れるのは、別にすると間の `main` でマニュアルが組めなくなるからである。

### ドキュメント

- docs/diagnostics.md に G07105 の節を足す。主な原因と直し方は G09013 と同じものを書き、`golem preflight` では G09013 とともに出ることを書く。G09013 の節に、量と位置を G07105 にそろえたこと、同じ行を `golem build` が G07105 で報告することを書く。
- 仕様書（docs/specifications.md）の「行分割」の節の「はみ出す行は `golem build` では diagnostic にせず」の文を、G07105 で報告することに改め、この ADR へのリンクを付ける。「golem preflight」の節に、G07105 が G09013 とともに出ることを書く。
- [golem-cli ADR 0006](../golem-cli/adr/0006-preflight.md) のステータスの行に、はみ出す行をビルドでも G07105 で報告し、G09013 の量と位置を改めたことを、この ADR へのリンクで書き足す。
- [docs/roadmap.md](../roadmap.md) の「本文の中のコードの和文の改行」の項目の「`golem preflight` が 4 か所に G09013 を出す」を、付録 E の六つの項目のメッセージを略して避けていること、`golem build` が G07105 で報告することに書き改める。項目そのものは残す。
- 利用者のマニュアルの付録 E に G07105 を足す。付録 D（`manual/appendices/d-preflight.gm`）の `overfull-lines` の行と、スタイルの章（`manual/chapters/05-style.gm` の 719 行め）の、はみ出した行を `golem preflight` が警告（G09013）で知らせるという文に、`golem build` も G07105 で知らせることを書く。
- 開発者のマニュアルの diagnostics の章（`manual-dev/part1/02-diagnostics.gm`）に、レイアウトの段階の警告として G07105 が加わることを書く。今の章が段階ごとのコードを列挙していなければ、書き足さない。

## 実装しないこと

- はみ出しを避けること。本文の中のコードの和文を字のあいだで改行できるようにすることは、すべての本のコードの改行を変え、コードの中の禁則を決め直す必要がある（[docs/adr/0178](0178-colophon-commit-line-overflow.md) の「メンテナーが決めること」の 1）。別の ADR で決める（「メンテナーが決めること」の 8）。
- `url` の `-` の後で改行すること。[golem-layout ADR 0018](../golem-layout/adr/0018-url-line-breaks.md) がメンテナーの決定として退けた。
- はみ出しの許容量（TeX の `\hfuzz` に当たるもの）。
- はみ出した行に印を描くこと（TeX の `\overfullrule`）。PDF は変えない。
- 目次の行の、題の後に置くページ番号が行長からはみ出すこと。ページ番号は行分割の後に置くので、`lineOverflow` に入らない。G09013 も今は報告しない。
- 段より大きい図版、表、コードブロック（ロードマップの「減らした段より大きい図版、表、コードブロック」）と、段に入らない見出し（G07100）。行の方向のはみ出しではない。
- コードブロックの行。折り返すので行長を超えず、G07030 で知らせる。
- マニュアルの CI で `golem preflight` を走らせること。この ADR の後は、はみ出しを `build.sh` が G07105 で止める。プリフライトのほかの検査を CI に入れるかは、別に決める。
- 負のトラッキングで `lineOverfull` が真になる行の扱いを直すこと（「確かめたこと」の最後の項目）。この ADR の後は、その行は `lineOverflow` の量で G07105 になる。トラッキングの戻しを行の幅に数えるかどうかは、別に調べる。

## 不変条件

段落の行の並びを、`breakParagraph` が返す行とする。
行 i の行長を L(i)、行の自然な幅を N(i)、縮みの合計（字形の圧縮を含む）を Z(i) とする。
改行の位置のあいだの箱とグルーの並びを、改行できない並びと呼ぶ。

- **O1**：どの行でも、`lineOverflow` は max(0, N(i) − Z(i) − L(i)) に等しく、整数の sp である。
- **O2**：どの行でも、`lineOverfull` が真であることと `lineOverflow` が正であることは同値である。
- **O3**：段落のどの改行できない並びも、それを置きうるどの行の行長にも、縮みを使い切れば収まるなら、`lineOverflow` が正の行はない。
- **O4**：改行できない並びの一つが、縮みを使い切っても、それを置いた行の行長より長いなら、その行の `lineOverflow` は正である。
- **O5**：PDF をターゲットに含む `golem build` が出す G07105 は、描いた行のうち `lineOverflow` が正の行とちょうど一対一に対応する。`lineOverflow` が 0 の行には出さない。
- **O6**：G07105 の位置、メッセージ、`facts` は、その行だけから決まる。同じ入力からは、`optParallel` の有無によらず同じ diagnostics を同じ順に出す。
- **O7**：この ADR は PDF と `pages.json` のバイト列を変えない。同じ入力からは、この ADR の前と同じバイト列を書く。
- **O8**：`golem preflight` では、G07105 を出す行ごとに、同じ位置、同じメッセージ、同じ `facts` の G09013 を、`overfull-lines` が `off` でない限り一つ出す。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| N − Z − L | −1sp、0（ちょうど行長）、1sp、行長の 2 倍 |
| 縮み Z | 0、はみ出しをちょうど吸う量、1sp 足りない量 |
| 行末の突き出し | なし、句読点のぶら下げで行長を超えて描く行（はみ出しではない） |
| 改行できない並び | なし、一つが行長ちょうど、一つが行長 + 1sp、一行に二つ |
| 行の種類 | 本文、表のセル、脚注、目次の題、見出し |
| 組みの向き | 横組み、縦組み |
| 位置の元 | 原稿の字、原稿にない字（見出しの番号） |
| 量の表記 | 1sp（`0.01mm`）、0.005mm ちょうど、1.24mm ちょうど |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
テストの名前には、O1 から O8 の番号を入れる。

### golem-layout（`modules/golem-layout/test/Main.hs`）

- **O1、O2**：幅 30 の行長に、幅 30 − 1、30、30 + 1、60 の一つの箱の段落を `breakParagraph` で分ける。`lineOverflow` が 0、0、1、30 であり、`lineOverfull` がそれと同値である。縮み 1 のグルーを足した箱の並びで、自然な幅が 31 なら `lineOverflow` は 0、32 なら 1 である。
- **O1、O2**：句読点のぶら下げ（`pProtrusion`）で行末の字が行長の外に出る行は、`lineOverflow` が 0 である。
- **O3、O4**：小さい入力を数え尽くす性質のテスト（[docs/adr/0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) と同じ形）で、箱の幅とグルーと罰点の並びを作り、改行できない並びの最大の幅と行長から、はみ出す行の有無を決め、`breakParagraph` の結果と比べる。

### golem-typeset と golem-driver

- **O5**：横組みと縦組みのそれぞれで、空白のない和文の本文の中のコードが行長を超える本を `golem build --target pdf` の手順で組む。G07105 がちょうど一つ出て、位置がコードの最初の字（`[code: ` の直後のバイト）であり、量が `lineOverflow` の切り上げである。今は G07105 が出ないので失敗する。
- **O5**：同じ本の段落を、コードが行長にちょうど収まるようにした本では、G07105 が出ない。
- **O5**：はみ出すコードを二つの段落に置いた本では G07105 が二つ、脚注の本文に置いた本では、位置が脚注の中のコードの最初の字の G07105 が一つ出る。表のセルでも一つ出る。
- **O5**：番号の付く見出しで、原稿にない字の箱がはみ出す本では、位置が見出しのブロックの位置である。
- **O6**：上の本を `optParallel` の有無で組み、diagnostics の並びが一致する。
- **O7**：fixture の figures、conformance、languages の今の PDF のゴールデン（`OutputGoldenSpec` と `TaggedPdfSpec`）が変わらない。はみ出す本の PDF のバイト列が、G07105 を求める処理の有無で変わらない。
- **O8**：はみ出すコードを持つ本の `golem preflight` が、G07105 と G09013 を同じ位置、同じメッセージで一つずつ出す。`overfull-lines` を `off` にすると G07105 だけが出る。
- golem-preflight の G09013 のテスト（`modules/golem-preflight/test/Main.hs` の「G09013: an overfull line, in mm to two decimals」）を、量の切り上げに合わせ、1sp のはみ出しが `0.01mm` になることを足す。
- docs/diagnostics.md と diagnostic のコードの一覧が一致することを確かめる今の golem-driver のテストが、G07105 の節を求める。

### 自動テストにしない確かめ方

- 実装の後に二つのマニュアルを `scripts/manual/build.sh` で組み、diagnostic が出ないことを確かめる。付録 E の六つの項目のページと、開発者のマニュアルの 33、118、131、179 ページを PNG に描き、版面に収まったことを目で確かめる。
- 実装の前のマニュアルで、`golem build` が G07105 を、利用者のマニュアルで 6 つ、開発者のマニュアルで 4 つ出すことを確かめ、プルリクエストに書く。

### 変わるゴールデンとハッシュ

- `scripts/determinism.sh` と `scripts/env-determinism/check.sh` の入力は、上の「確かめたこと」のとおりはみ出す行を持たないので、標準エラー出力も出力のハッシュも変わらない。
- golem-driver の fixture の PDF のゴールデンは変わらない（O7）。
- 二つのマニュアルの PDF と HTML は、原稿の変更で変わる。見た目の回帰テストは、付録 E の六つの項目のページと、開発者のマニュアルの URL の脚注を持つすべてのページを受け入れ直す。付録 E の項目の語はどれも一行のままなので、ページの割り付けは変わらないと見込むが、確かめていない。
- `golem preflight` の G09013 の量は、行末の突き出しやトラッキングの戻しを持つ行で、今の値から変わりうる。位置は、定義の一覧の始まりから、はみ出した箱の字に変わる。

## トレードオフ

`golem preflight` は、はみ出す行ごとに G07105 と G09013 の二つを出す。
同じ行を二度読むことになるが、ビルドの報告とプリフライトの設定の重大度を切り離すためである。
入稿の前にはみ出しをエラーにしたい本は、`overfull-lines` を `error` にすれば、プリフライトで止められる。

警告は、書きかけの原稿を組むたびに出る。
長い URL や識別子を含む原稿では、書き手が直すまで警告が残る。
[golem-cli ADR 0006](../golem-cli/adr/0006-preflight.md) は、ビルドを速く保ち、止めるかどうかを印刷の条件から切り離すために、はみ出しをプリフライトだけに置いた。
この ADR はその判断を改め、版面の外に出る文字はどの本でも誤りとして扱う。
仕上がりの線を越えて断裁で切れる文字（「確かめたこと」の 291 ページと 298 ページ）は、印刷の条件によらず誤りだからである。

付録 E の六つの項目は、メッセージの後ろを略す。
書き手は、端末に出たメッセージの後ろの部分で付録 E を探せなくなる。
コードで引けば項目は見つかり、略した部分の意味は説明の文にある。
本文の中のコードの和文を改行できるようにする ADR を採れば、略さずに戻せる。

開発者のマニュアルの URL を詰めると、すべての脚注の URL の見た目が少し変わる。
四つの脚注のためだけの文字スタイルを足す方法もあるが、同じ URL を書くたびに書き手がスタイルを選び分けることになる。

## メンテナーが決めること

1. **重大度**：推奨は、dev でも prod でも警告とすることである。版面の外に出る文字は、組んだ結果の誤りで、仕上がりの線を越えれば断裁で切れる。
   - 退けた案の一つは、notice とすることである。notice は、Golem が組み方を変えたことを知らせるもの（G07030 のコードの行の折り返し）に使い、`silence-notices` で抑制できる。はみ出しは Golem が直した結果ではなく、抑制させたくない。
   - 二つめは、G08100 のように dev では警告、prod ではエラーとすることである。0.65mm のように余白の中に収まるはみ出しを、本ごとに許したい場合がある。入稿の前に止めたい本は、プリフライトの `overfull-lines` で止められる。
2. **位置**：推奨は、終わりが行長を超える最初の箱の最初の字（長さ 0）である。付録 E では、今の G09013 の位置（定義の一覧の始まり）から、どの項目がはみ出したかを引けなかった。
   - 退けた案の一つは、今の G09013 と同じ、行を含むブロックの位置である。上の理由で、書き手が直す場所を探せない。
   - 二つめは、本文の中のコードの範囲（`[code: …]` の全体）である。コード以外のはみ出し（長い語）では範囲がなく、箱の字の数と原稿のバイトの数は、エスケープ（`\[`）があると一致しない。
3. **しきい値と量の表記**：推奨は、1sp でもはみ出せば報告し、量は 0.01mm 単位に切り上げて書くことである。行分割の条件と同じなので、報告の有無を仕様の言葉で書ける。切り上げれば、正のはみ出しを `0.00mm` と書かない。
   - 退けた案の一つは、TeX の `\hfuzz` のような許容量（たとえば 0.1pt）である。値をもう一つ決めることになり、開発者のマニュアルの 0.65mm は許容量を置いても残る。
   - 二つめは、今の `mmText`（偶数への丸め）のままとすることである。1sp のはみ出しが `0.00mm はみ出しています` になり、文として矛盾する。
4. **対象**：推奨は、本文の中のコードに限らず、描いたすべての行とすることである。長い URL、長い語、グループルビも同じ仕組みではみ出し、G09013 と同じ集合にそろう。
   - 退けた案は、本文の中のコードだけとすることである。同じ原因（改行できない並びが行長より長い）を、並びの中身で報告したりしなかったりすることになる。
5. **G09013 との関係**：推奨は、G09013 を残し、量と位置を G07105 にそろえることである（[docs/adr/0081](0081-missing-glyphs-warn-in-build.md) の G08100 と G09002 と同じ）。
   - 退けた案の一つは、G09013 を廃止し、`overfull-lines` を知らないキーにすることである。今の `preflight.toml` が G09001 で読めなくなり、プリフライトではみ出しをエラーにする手段もなくなる。
   - 二つめは、G09013 の量と位置を今のままにすることである。同じ行の二つの diagnostic が、別の位置と別の量で並ぶ。
   - 三つめは、Golem を変えず、マニュアルの CI で `golem preflight` を走らせることである。`golem build` だけを使う書き手は、はみ出しを知らないままになる。
6. **利用者のマニュアルの直し方**：推奨は、付録 E の六つの項目のメッセージの後ろを `…` で略すことである。作業用の写しで、はみ出しが消えることを確かめた。今の付録 E も、[docs/adr/0068](0068-accepting-side-of-limits.md) が書くとおりメッセージの一部だけを載せる項目を持つ。
   - 退けた案の一つは、本文の中のコードの和文を改行できるようにする ADR を先に実装し、マニュアルを変えないことである。この ADR の実装が、すべての本のコードの改行の規則の決定を待つことになる。
   - 二つめは、項目の語のメッセージをコードにせず、本文の書体で組むことである。和文の字のあいだで改行できるようになるが、この六つの項目だけがほかの項目と違う見た目になる。
7. **開発者のマニュアルの直し方**：推奨は、`[character-styles.url]` に `tracking = -10` を足すことである。作業用の写しで、はみ出しが消えることを確かめた。
   - 退けた案の一つは、`url` で `-` の後の改行を許すことである。[golem-layout ADR 0018](../golem-layout/adr/0018-url-line-breaks.md) が退けた決定を覆すので、別の ADR が要る。
   - 二つめは、四つの脚注を `docs/adr/` の一覧の URL に替えることである。読み手は [ADR 0203](0203-generated-modules-instead-of-template-haskell-in-golem-driver.md) の文書に直接たどれなくなる。
8. **はみ出しを避けること**：推奨は、この ADR では扱わず、本文の中のコードの和文の改行を別の ADR で決めることである。報告と回避は別の決定で、回避はすべての本の組みを変える。ロードマップの v0.1.0-rc4 の「本文の中のコードの和文の改行」の項目は残す。
   - 退けた案は、この ADR で和文の字のあいだの改行も決めることである。コードの中の禁則、欧文との境、等幅の字送りの揃えを同時に決めることになり、報告だけを先に入れられなくなる。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-08、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [golem-cli ADR 0006](../golem-cli/adr/0006-preflight.md)
- [golem-driver ADR 0017](../golem-driver/adr/0017-pdf-code-blocks.md)
- [golem-layout ADR 0001](../golem-layout/adr/0001-knuth-plass-line-breaking.md)、[golem-layout ADR 0017](../golem-layout/adr/0017-spaces-inside-inline-code.md)、[golem-layout ADR 0018](../golem-layout/adr/0018-url-line-breaks.md)
- [docs/adr/0061](0061-five-digit-diagnostic-codes.md)、[docs/adr/0068](0068-accepting-side-of-limits.md)、[docs/adr/0081](0081-missing-glyphs-warn-in-build.md)、[docs/adr/0103](0103-single-place-for-unit-conversions.md)、[docs/adr/0178](0178-colophon-commit-line-overflow.md)、[docs/adr/0204](0204-pagination-invariants-by-exhaustive-small-inputs.md)
- Donald E. Knuth, The TeXbook（`\hfuzz`、`\overfullrule`、Overfull \hbox の報告）
- W3C, Requirements for Japanese Text Layout（JLReq）, https://www.w3.org/TR/jlreq/
