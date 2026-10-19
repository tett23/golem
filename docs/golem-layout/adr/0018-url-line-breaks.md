# ADR 0018: URL の中で改行できる位置と、注の印の後の空き

ステータス: 採択

## 文脈

[docs/roadmap.md](../../roadmap.md) の v0.1.0-rc4 に「参考文献の URL の行の間延び」がある。
途中で改行できない長い URL を含む参考文献の項目で、行がひどく間延びする、という項目である。
ロードマップは、URL の中で改行できる位置を増やすか、間延びの代わりに何を許すかを ADR で決めるとしている。
二つのマニュアルを読み直したところ、脚注の本文が URL で始まる場合に、注の印と URL のあいだが大きく空くことも分かった。

### 再現

今の `main` から作った golem（a2b6106e、行分割の最後の段で収まらない箱を追い出す PR #231 を含む）で二つのマニュアルを組み、PNG に描いて確かめた。

- 利用者のマニュアルの参考文献（285 ページ）の 5 番めの項目は、一行めが `[5]`、書名の「ファイルシステム間での作業」と `Microsoft`、 `https://` だけになり、字のあいだが大きく空く。2 番め、7 番め、11 番め、12 番め、14 番めの項目も、URL の途中の `/` の後で行を終え、一行めの語間か字のあいだが広がる。26 番めの項目も同じである。
- 開発者のマニュアルの 22 ページの脚注 7 と 8 は、本文が `[code: https://github.com/…]` で始まる。注の印「*7」の終わりから URL の始まりまでが、およそ 23pt 空く。報告にある 15 ページの脚注も同じ形である。

### 原因

参考文献の URL は、組み込みの文字スタイル `url` で組む（[golem-doc ADR 0005](../../golem-doc/adr/0005-bibliography-fields.md)）。
`url` の文字は、コードと同じく `Golem.Layout.Japanese` の `codeItems` で箱に分けられ、改行してよい位置は空白と `/` の後だけである。
`//` のような `/` の並びでは、その最後の `/` の後でだけ改行する。
`https://learn.microsoft.com/ja-jp/windows/wsl/filesystems` の最初の改行の位置は `https://` の後で、次は `learn.microsoft.com/` の後である。
`https://` の後で行を終えると、`learn.microsoft.com/` が行に収まらないので、行は `https://` までになり、足りない幅を行の中のグルーが受け持つ。
JLReq の追い出しと同じく、行の中の字のあいだと語間が広がる。

脚注の本文は、`Golem.Driver.Pdf` の `withNoteMark` が、注の印の文字列に半角の空白を付けて本文の前に置いたものである。
この空白は本文の語間の空白と同じグルーで、伸び縮みし、改行の位置にもなる。
本文が改行できない長いコードで始まると、一行めには印と空白とコードの最初の部分しかない。
伸びるグルーは印の後の空白だけなので、行の不足をすべてその空白が受け持ち、印と本文が大きく離れる。

### 参照した組み方

仕様書の「仕様が不明瞭な場合」に従い、JLReq、InDesign、TeX と LaTeX の順に調べた。

- JLReq は、URL の改行について定めていない。
- InDesign は、URL を見分けて改行の位置を足す機能を持たない。欧文の語は空白とハイフンの位置で改行し、URL の途中で改行するには、書き手が改行可能な位置（ゼロ幅の空白）を手で入れる。
- LaTeX の url パッケージは、URL の中の `.`、`@`、`/`、`!`、`_`、`|`、`;`、`>`、`]`、`)`、`,`、`?`、`&`、`'`、`+`、`=`、`#` の後での改行を許し（`\UrlBreaks`）、`:` の後での改行をより強く許す（`\UrlBigBreaks`）。`-` の後の改行は、パッケージのオプション `hyphens` を付けたときだけ許す。改行の位置にハイフンは足さない。biblatex は、参考文献の URL にこの規則を使い、改行の罰点を `\biburlbreakpenalty` と `\biburlbigbreakpenalty` で決める。

参考として、『The Chicago Manual of Style』第 17 版は、URL を `:` と `//` の後、`.`、`,`、`-`、`_`、`~`、`/` などの前、`=` と `&` の前後で分け、ハイフンを足さないとする。
仕様書が拠る順には入らないので、この ADR では LaTeX の規則を採り、Chicago は比べるためにだけ使う。

## 実装すること

### URL の改行の位置（golem-layout）

文字スタイル `url`（`lkUrl` が真の見た目）の文字の改行の位置を、url パッケージの `\UrlBreaks` と `\UrlBigBreaks` に合わせて増やす。

- 次の字の後で改行してよい：`/`、`.`、`@`、`!`、`_`、`|`、`;`、`>`、`]`、`)`、`,`、`?`、`&`、`'`、`+`、`=`、`#`、`:`。
- 例外として、`/` の並びは、今のとおりその最後の `/` の後でだけ改行する（[golem-doc ADR 0005](../../golem-doc/adr/0005-bibliography-fields.md)）。`:` は、次の字が `/` のときは改行しない。`https:` と `//` のあいだ、`/` と `/` のあいだで分かれないようにするためである。
- `-` の前と後、`%` の後では改行しない（url パッケージの既定、メンテナーの決定）。`-` の後で分けると、ハイフンを足さないので分綴との区別がつかない。URL の中で分綴もしない。`%` の後で分けると、パーセント符号化の三字（`%E3`）が分かれる。
- 罰点は、`/` の並びの後を 0（今のとおり）、ほかの字の後を 100 とする。行の割り付けが同じくらいなら、`/` の後で分ける組を選ばせるためである。
- 改行しても、今のとおりハイフンを描かない。URL にハイフンを足すことはない。
- `url` の文字の中のアキ量のセットの空き、ハイフネーションの扱いは変えない。

`codeItems` は、`url` の見た目のとき、上の字の後ごとに箱を分ける（今の `slashParts` を、改行してよい字の後で分ける形に広げる）。
`normalize` は、`url` の見た目の箱どうしのあいだに、前の箱の最後の字に応じた罰点を置く。

```haskell
-- | URL の中の改行の罰点：前の箱の最後の字の後で改行してよければ、その罰点
-- （golem-layout ADR 0018）
urlBreakAfter :: Text -> Maybe Int
```

文字スタイル `code` の改行の位置（空白と `/` の後）は変えない。

### 注の印の後の空き（golem-driver）

脚注の本文の前に置く注の印と本文のあいだを、伸び縮みせず、改行もしない空きにする。

- `withNoteMark` は、注の印の文字列の後に半角の空白を付ける代わりに、印の文字列と、四分アキの `[aki]`（`Aki` の `AkiZw (1/4)`、[golem-layout ADR 0012](0012-aki-glue-marker.md)）を置く。
- `[aki]` の箱は、前後で改行させず、アキ量のセットの空きも足さない。印と本文は同じ行に置かれ、そのあいだの幅は四分アキに固定される。
- 本文が改行できない長い語やコードで始まり、一行めに伸びるグルーがない場合、その行は今の行分割の最後の段で行頭に寄せて組まれる。
- 印の書式（`[notes] mark-format`、[golem-driver ADR 0025](../../golem-driver/adr/0025-note-mark-size-and-format.md)）は変えない。

### ドキュメント

- 仕様書の文字スタイル `url` の改行の規則を、この ADR の字と罰点に改め、この ADR へのリンクを付ける。
- 仕様書の脚注の節に、注の印と本文のあいだは四分アキの固定の空きで、そこで改行しないことを書く。
- [golem-doc ADR 0005](../../golem-doc/adr/0005-bibliography-fields.md) のステータスの行に、`url` の改行の位置をこの ADR で増やしたことを、この ADR へのリンクで書き足す。
- [docs/roadmap.md](../../roadmap.md) の v0.1.0-rc4 から「参考文献の URL の行の間延び」の項目を消す。
- 利用者のマニュアルの付録 H（`manual/appendices/h-roadmap.gm`）から「参考文献の長い URL の行が、ひどく間延びしないようにすること」を消す。
- 利用者のマニュアルの付録 C（`manual/appendices/c-style.gm`）の文字スタイル `url` の説明を改める。
- 開発者のマニュアルの脚注の URL を、`[code: …]` から `[style url: …]` に替える（メンテナーの決定）。この ADR を採択したあと、マニュアルのプルリクエストで行い、ADR は要しない。
- 同じプルリクエストで、開発者のマニュアルの `style.toml` に `[character-styles.url]` を書き、`font = "code"` と `color = "code"` で、書体と色をコードと同じにする。読み手が脚注の URL を今と同じ見た目で見分けられるようにするためである。背景と余白（`background`、`padding`）は `code` の系列の文字スタイルにだけ書けるので（[golem-driver ADR 0029](../../golem-driver/adr/0029-inline-code-background.md)）、URL には背景を塗らない。見た目の差は背景の有無だけになる。

## 実装しないこと

- 字の後でなく、字の前で改行すること（Chicago の流儀）。
- 欧文の文字や数字のあいだでの改行（biblatex の `\biburlucpenalty`、`\biburllcpenalty`、`\biburlnumpenalty`）。biblatex も既定では許していない。
- URL を本文から自動で見分けること。URL の改行の規則は、文字スタイル `url` の文字にだけかける。`[code: https://…]` のようにコードとして書いた URL は、コードの規則のまま組む。
- 原稿に外部の URL へのリンクを書く記法と、PDF のリンクの注釈。v0.1.0-rc4 の「PDF のリンク」で扱う。
- 傍注の印と本文のあいだ。傍注の印は本文と別に置くので、この問題は起きない（[golem-driver ADR 0006](../../golem-driver/adr/0006-pdf-sidenotes.md)）。

## テスト設計

実装の前に書き、失敗することを確かめる。

### golem-layout（`modules/golem-layout/test/Main.hs`）

- `url` の見た目の `https://learn.microsoft.com/ja-jp/windows/wsl/filesystems` を `composeInlines` で項目にすると、改行の位置（`infPenalty` 未満の罰点）が、`https://`、`learn.`、`microsoft.`、`com/`、`ja-jp/`、`windows/`、`wsl/` の後にある。`/` の後の罰点は 0、`.` の後は 100 である。
- `https:` と `//` のあいだ、`/` と `/` のあいだ、`ja-` と `jp` のあいだには改行の位置がない。
- `url` の見た目の `a?b=c&d#e` で、`?`、`=`、`&`、`#` の後に罰点 100 の改行の位置がある。`%E3%81` の中には改行の位置がない。
- `code` の見た目の `a.b/c` では、今のとおり `/` の後だけに改行の位置がある。
- 改行の位置で分けた行の最後に、ハイフンの幅を持つ罰点がない。

### golem-driver（`modules/golem-driver/test/ReferencesSpec.hs`）

- 利用者のマニュアルの参考文献の 5 番めの項目と同じ CSL-JSON の項目を、利用者のマニュアルと同じ版面と書体の本で組む。一行めの字のあいだのグルーの伸びの比（`glueRatio`）が 1 以下である。実装の前は 1 を大きく超える。
- 脚注の本文が `[code: https://github.com/tett23/golem/blob/main/docs/golem-pdf/adr/0004-crop-marks-and-bleed.md]` で始まる本を、開発者のマニュアルと同じ版面で組む。注の印の最後の字の終わりから本文の最初の字の始まりまでが、本文の文字の大きさの四分の一に等しい。
- 同じ本で、注の印と本文の最初の箱のあいだに改行の位置がない。
- 本文が和文で始まる脚注で、注の印と本文のあいだの幅が四分アキである。

### 自動テストにしない確かめ方

- 二つのマニュアルを組み、利用者のマニュアルの参考文献のページと、開発者のマニュアルの 15 ページと 22 ページの脚注を PNG に描いて、間延びと印の後の空きが解消されたことを確かめる。

## トレードオフ

改行の位置を増やすと、URL が `.` の後で分かれ、行末に `learn.` のような断片が残る。
読み手は、`.` で終わる行を文の終わりと読み違えるおそれがある。
Chicago が `.` の前で分けるのは、この読み違えを避けるためである。
仕様書の拠る順に従って LaTeX の規則を採ったが、行頭に `.` が来る組み方のほうが読みやすいと判断すれば、別の ADR で Chicago の流儀に替えることもできる。

注の印の後を四分アキの固定にすると、今の半角の空白の幅（本文の欧文の書体の空白の送り）との差のぶん、すべての脚注の一行めの組み方が少し変わる。
二つのマニュアルの PDF は、脚注のある多くのページで変わる。
代わりに、印と本文のあいだの幅が、書体によらず一定になる。

## 参考文献

- W3C, Requirements for Japanese Text Layout（JLReq）, https://www.w3.org/TR/jlreq/
- Donald Arseneau, url.sty（`\UrlBreaks`、`\UrlBigBreaks`、オプション `hyphens`）, https://ctan.org/pkg/url
- Philipp Lehman, Philip Kime ほか, The biblatex Package（`\biburlbreakpenalty`、`\biburlbigbreakpenalty`、`\biburlnumpenalty`）, https://ctan.org/pkg/biblatex
- 『The Chicago Manual of Style』第 17 版（URL の改行を定める節。節の番号は確かめていない）
- [golem-doc ADR 0005](../../golem-doc/adr/0005-bibliography-fields.md)
- [golem-layout ADR 0012](0012-aki-glue-marker.md)
- [golem-driver ADR 0025](../../golem-driver/adr/0025-note-mark-size-and-format.md)
