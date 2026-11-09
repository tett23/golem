# ADR 0261: 段落スタイルの分割禁止と連動

ステータス: 採択

## 文脈

[ロードマップ](../roadmap.md) の v1.0.0 の「LaTeX との差を埋める項目」に「段落スタイルの分割禁止と連動」がある。
段落スタイルに、次の段落と連動、段落を分割しない、段落の始めと終わりに残す行の数、段落の開始位置の欄を加える項目である（[2026-10-17 の調査](../audits/2026-10-17-latex-gap-for-v1.md) の 7）。
調査の「所有者の決定」は、孤立行の行数の欄をこの項目に入れると決めた。
v2 の「孤立行の規則の見直し」には、既定の規則を和文の本で緩めるかどうかだけが残る。

### 今の改ページが段落について決めていること

改ページの規則は、段落の分け方を一つしか持たない。
段落の最初の 1 行だけを段の末尾に残さず、最後の 1 行だけを次の段に送らない（[golem-layout ADR 0003](../golem-layout/adr/0003-pagination-and-s2.md)、[仕様書の「改ページ」](../specifications.md#改ページ)）。
この規則は `splitAtBreak` の二つの固定の数（孤立行と寡婦行の 1 行）で書かれている（[`Decide.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-layout/src/Golem/Layout/Paginate/Decide.hs#L121-L136)）。
見出しの先読みが数える段落の最初の部分（`firstPart`、[golem-layout ADR 0021](../golem-layout/adr/0021-keep-with-next-counts-widow-and-orphan.md)）も、同じ関数から求める。
韻文の連（`FStanza`）は、韻文の行を単位にして同じ関数を使う（[docs/adr/0180](0180-verse-spacing-and-stanza-breaks.md)、[`Paginate.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-layout/src/Golem/Layout/Paginate.hs#L484-L510)）。

段落を次のものと離さない手段は、原稿の一か所に置く `@no-page-break` だけである（[docs/adr/0030](0030-manual-page-break-control.md)）。
その前の段落は、最後の 2 行（3 行以下なら全体）を後の最初の部分と同じ段に置く（`placeFlow` と `placeKept`、[`Paginate.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-layout/src/Golem/Layout/Paginate.hs#L324-L363)、[docs/adr/0055](0055-no-page-break-moves-short-paragraphs-whole.md)）。
守れなければ、改ページの結果に `UnmetNoBreak` を載せ、golem-driver が G07037 の警告にする。
段落を次の段やページから始める手段は、原稿の `@page-break` と `@column-break`（[docs/adr/0017](0017-forced-page-breaks.md)）と、見出しの `page-break = "recto"` だけである。

罫線を持つ段落（`FRuled`）は、すでに分けないまとまりとして置かれる（[golem-driver ADR 0027](../golem-driver/adr/0027-paragraph-style-rules.md)）。
空の段にも入らなければ notice（G07046）を出し、罫線を外して段落と同じ規則で分ける（[`Paginate.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-layout/src/Golem/Layout/Paginate.hs#L512-L569)）。

段落スタイルは、golem-typeset が単位（`Unit`）を作るときに読む（[`Flow.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L1537-L1549)）。
単位を流れ（`Flow`）にする `numberText` は、段落を `FParagraph`、`FStanza`、`FRuled` のどれかにする（[`Flow.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L2366-L2380)）。
流れの要素は段落スタイルの名前を持たないので、改ページはスタイルを読めない。
`space-before` と罫線は、リストの中の段落には当てない（`null ctx` の条件）。

### InDesign と LaTeX

InDesign は、段落の分割禁止オプションとして、次の段落と連動（後の段落の最大 5 行）、前の段落と連動、段落を分割しない（すべての行、または段落の始めと終わりの行数）、段落の開始位置（任意の位置、次の段、次のフレーム、次のページ、次の奇数ページ、次の偶数ページ）を持ち、段落スタイルに書ける。
出典は調査の 7 に挙げたヘルプの頁である。
調査は helpx.adobe.com の本文を読めず、検索の抜粋で確かめた。
次の点は確かめていない。

- 段落の始めと終わりの行数の既定の値と、とれる値の範囲。
- 段の先頭にすでにある段落に「次のページ」を当てたときに、白ページを足すか。
- 次の段落と連動が三つ以上の段落に連なり、段に入らないときの分け方。

LaTeX は段落ごとの指定を持たず、`\nopagebreak`、`\samepage`、needspace の `\needspace` を原稿に書くか、`\widowpenalty` と `\clubpenalty` で本の全体の罰則を変える。
JLReq が孤立行と段落ごとの指定について何を求めるかは、この ADR を書くときに本文で確かめていない。
仕様の決め方の順（JLReq、InDesign、TeX と LaTeX）に従い、欄の形と値の名前は InDesign に合わせ、確かめられない振る舞いはこの ADR で決める。

### 依存

この ADR は [ADR 0260](0260-front-matter-folios-and-page-labels.md) の後に実装する。
[ADR 0260](0260-front-matter-folios-and-page-labels.md) は、セクションの前に空のページを閉じない改ページを足す。
段落の開始位置は、その改ページの要素を使う（「改ページの型」）。
[ADR 0271](0271-paragraph-backgrounds-and-borders.md) は、この ADR の欄を囲みの中の段落にも当てるので、この ADR の後に実装する。

## 実装すること

### style.toml の欄

段落スタイル（`[paragraph-styles.<名前>]`）に五つのキーを加える。
どれも `based-on` で引き継ぎ、書いた値が勝つ。

| キー | 型 | 既定 | 意味 | InDesign |
| --- | --- | --- | --- | --- |
| `keep-with-next` | 0 から 5 の整数 | 0 | 段落の最後の行を、後に続くものの最初の部分と同じ段に置く。後が段落なら、その最初の少なくとも N 行を最初の部分とする。0 は連動しない | 次の段落と連動 |
| `keep-all-lines` | 真偽値 | `false` | 段落を段で分けない | 段落を分割しない（すべての行） |
| `keep-first-lines` | 1 以上の整数 | 2 | 段で分けるとき、前の段に残す最初の部分の最小の行数 | 段落の始めの行数 |
| `keep-last-lines` | 1 以上の整数 | 2 | 段で分けるとき、次の段に送る最後の部分の最小の行数 | 段落の終わりの行数 |
| `page-break` | `"any"`、`"column"`、`"page"`、`"recto"`、`"verso"` | `"any"` | 段落を、次の段、次のページ、次の奇数ページ、次の偶数ページから始める | 段落の開始位置 |

- `keep-first-lines = 2` と `keep-last-lines = 2` は、今の規則（最初と最後の行を一つだけ残さない）と同じ置き方になる。どれも書かない本の PDF は変わらない。
- 行の数は、`line-breaks = "keep"` の段落（連）では韻文の行の数とする。折り返した韻文の行のあいだでは、今のとおり段を分けない。
- `page-break` の名前と `"recto"`、`"any"` の値は、見出しの `page-break`（`[headings.N]`）と同じにする。`"column"`、`"page"`、`"verso"` は段落スタイルにだけ加える。値の名前は `@page-break recto`、`@page-break verso` と `@column-break` に合わせる。
- 値の誤り（範囲の外の整数、真偽値でない値、表にない文字列）は G03006 とする。負の整数は、ほかの自然数のキーと同じく G02103 とする。
- 組み込みの段落スタイル `code` には書けない（今の規則のとおり G03006）。`caption` と `sidenote` には書ける。キャプションと傍注の本文には当てず、`@style caption` などを付けた原稿の段落に当てる（`space-before` と同じ）。
- `@style-def` にも同じキーを同じ検査で書ける（golem-eval の `Golem.Eval.Settings`）。
- `Golem.Project.Style` の `ParaStyleDef` に `psKeepWithNext`、`psKeepAllLines`、`psKeepFirstLines`、`psKeepLastLines`、`psPageBreak` を加え、`overPara` と、LSP の補完が読む `paraStyleNode` にも加える（[`Style.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-project/src/Golem/Project/Style.hs#L269-L306)、[`Style.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-project/src/Golem/Project/Style.hs#L2817-L2842)）。`psPageBreak` の型は `Maybe ParaStart`（`StartAnywhere`、`StartColumn`、`StartPage`、`StartRecto`、`StartVerso`）とする。golem-project は golem-doc の `BreakKind` を使わず、golem-typeset が写す。

### 当てる段落

- `keep-first-lines`、`keep-last-lines`、`keep-all-lines` は、改ページが段落として置くすべての段落（文書の最上位、リストの項目、定義リストの説明の段落）に当てる。今の孤立行の規則がリストの中の段落にも働いているからである。
- `keep-with-next` と `page-break` は、文書の最上位の段落にだけ当てる。リストの項目、表のセル、注の本文、定義リストの中の段落には当てない。`space-before` と罫線（`null ctx` の条件）と同じ範囲である。
- 見出し、定義リストの用語、表、コードブロック、図版は、段落スタイルを持たないので変わらない。

### 改ページの型（golem-layout）

`Golem.Layout.Paginate.Types` に、段落の分け方を表す型を加える。

```haskell
-- | How a paragraph is broken between columns (docs/adr/0261): the
-- fewest lines (verse lines of a stanza) of its first and last parts,
-- and whether it is not broken at all.
data Keep = Keep {kFirst :: !Int, kLast :: !Int, kAll :: !Bool}
  deriving stock (Eq, Show)

defaultKeep :: Keep
defaultKeep = Keep 2 2 False
```

`Flow` を次のように変える（[`Types.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-layout/src/Golem/Layout/Paginate/Types.hs#L52-L130)）。

- `FParagraph`、`FStanza`、`FContinued` と、`RuledLines` に `Keep` の欄を加える。今の値は `defaultKeep` を持つ。
- `FStart !SrcSpan !BreakKind` を加える。段落の開始位置であり、golem-typeset が段落の流れの直前に置く。[ADR 0260](0260-front-matter-folios-and-page-labels.md) は、セクションの前に、空のページを閉じない改ページを流れの要素として足す。この ADR はそれを先に実装した要素として使い、改段の種類（`BreakColumn`）と段落の範囲を持てるように広げる。[ADR 0260](0260-front-matter-folios-and-page-labels.md) の実装が別の名前を付けていれば、その名前を使い、`FStart` の要素を別に作らない。
- `FKeepNext !SrcSpan !Int` を加える。次の段落と連動であり、golem-typeset が段落の流れの直後に置く。`SrcSpan` は段落の範囲である。
- `Unmet` に `UnmetKeepNext !SrcSpan`、`SplitKept !Int`（分けた段落の最初の行の `lbId`）、`ShortPart !Int !Int !Int`（段落の最初の行の `lbId`、求めた行の数、置いた行の数）を加える。

`Keep` を `Flow` の欄にするのは、行の数が段落を分ける位置そのものを決め、ほかの要素から離して置けないからである。
開始位置と連動は段落と段落のあいだの一点に働くので、`FBreak` と `FNoBreak` と同じく別の要素にする。

意味論 IR、CDDL、プラグインの ABI は変えない。
欄は style.toml にだけあり、golem-typeset が改ページの流れに写すからである。
golem のパッケージのあいだの `build-depends` も変えない。

### 分ける位置

`splitAtBreak` と `firstPart` に `Keep` を渡す（[`Decide.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-layout/src/Golem/Layout/Paginate/Decide.hs#L121-L136)）。
n 行（韻文の行）の段落のうち、段に k 行が入るとき、段の前に置く行の数を次の順で決める。

1. `kAll` が真で k < n なら 0 とする。
2. 0 < n − k < `kLast` なら、k を max 0 (n − `kLast`) にする（寡婦行）。
3. 段落がこの段から始まり、0 < k < `kFirst` なら 0 にする（孤立行）。

`Keep 2 2 False` では、今の `splitAtBreak` と同じ値になる（2 の「n − k = 1 なら k − 1」と同じ）。
最初の部分（`firstPart`）は、`kAll` が真なら n、そうでなければ、上の手順が k をそのまま返す最も小さい k（`kFirst` 以上）とする。

空の段と、段の先頭から見出しだけを置いた段では、今のとおり、一行も置けなくなる場合は入るだけの行を置く。
そのとき、置いた最初の部分か次の段に送った最後の部分が `kFirst`、`kLast` より少なければ、`ShortPart` を記録する。

### 段落を分割しない

`kAll` が真の段落は、今の段に全体が入らなければ、次の段から置く（`keep`、空の段からは送らない）。
空の段（見出しだけの段を含む）にも入らなければ、`kAll` を偽として `kFirst` と `kLast` で分け、`SplitKept` を記録する。
罫線を持つ段落の「空の段にも入らないまとまり」と同じく、次の段から置いてから分ける（「メンテナーが決めること」の 2）。

### 次の段落と連動

`FKeepNext sp n` は、`@no-page-break`（`FNoBreak`）と同じ仕組みで置く。

- 前の段落の `placeKept` は、最後の 2 行の代わりに、`kLast` 行（`kLast` 以下の段落と、`kFirst + kLast` より短い段落は全体）を後の最初の部分と同じ段に送る。`@no-page-break` の前の段落も、同じく自らの `kLast` を使う（既定では今と同じ）。
- 後の最初の部分は `nextNeed` と同じ量とし、後が段落か連なら、その最初の部分を n 行以上に広げる。広げた量が段落の全体を超えれば全体とする。n が `nextNeed` の量より小さければ、`nextNeed` の量のままである。
- 後の段落も `keep-with-next` を持ち、その全体が最初の部分に入るときは、その後の最初の部分も足す。見出しの先読みが続く見出しを足すのと同じである（[`Decide.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-layout/src/Golem/Layout/Paginate/Decide.hs#L58-L100)）。足した量は段の行の格子の数を上限とする。
- 前が罫線を持つ段落なら、まとまりの全体を、後の最初の部分と合わせて段に入る位置に送る。空の段からは送らない。
- 後の最初の部分が前の最後の行と同じ段に置かれなければ、`UnmetKeepNext sp` を記録する。後が送った図版の場合、後が `FStart` か改丁の見出しで段を改めた場合、本の末尾の場合、合わせて段に入らない場合が、これに含まれる。
- `@no-page-break` と `keep-with-next` が同じ位置にあれば、一つの連動として扱い、大きいほうの量を取る。どちらかを守れなければ、両方を記録する。

### 段落の開始位置

`FStart sp k` は、ためた改ページの印（`sBreaks`）を適用した後に、次のように置く。

- `BreakColumn`：今の段が空でなければ次の段へ進む。
- `BreakPage`、`BreakRecto`、`BreakVerso`：見出しの `page-break = "recto"` と同じ `parityStart` で、送った図版と続きの脚注を置いてから、今のページが空で段 0 にいれば留まり、そうでなければ次のページへ進み、偶奇が合わなければ白ページを入れる（[`State.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-layout/src/Golem/Layout/Paginate/State.hs#L134-L143)）。

`@page-break` と違い、空の段や空のページでは何もしない。
[ADR 0260](0260-front-matter-folios-and-page-labels.md) のセクションの前の改ページと同じ規則である。
`@page-break` の直後に `page-break = "page"` の段落を書いても、白ページは一ページもできない。
同じスタイルの段落が続けば、一つずつ新しい段かページから始まる。

`nextNeed` は、`FStart` の後を何も数えない（`startsRecto` と同じく `mempty`）。
`FStart` の前の見出しは、改丁の見出しの前の見出しと同じく、後に続くものを数えずに置く（[docs/adr/0206](0206-pagination-points-the-invariants-did-not-decide.md)）。
見出しが前の段の末尾に残るが、開始位置の指定を優先する。
これは利用者の書いた二つの指定の組み合わせの結果なので、diagnostic は出さない。
`keep-with-next` の段落の後の `FStart` は、上のとおり `UnmetKeepNext` になる。

### diagnostics（golem-driver）

改ページの繰り返し（S2）の最後の回の結果から、次の diagnostic を出す。
位置は段落の範囲（`SplitKept` と `ShortPart` は最初の行の段落の範囲）である。

| コード | 重大度 | 条件 | メッセージ |
| --- | --- | --- | --- |
| G07111 | 警告 | `UnmetKeepNext` | `段落スタイル <名前> の keep-with-next を守れませんでした` |
| G07112 | notice | `SplitKept` | `段落スタイル <名前> の段落が段に入らないので、keep-all-lines を外して分けました` |
| G07113 | notice | `ShortPart` | `段の行が足りないので、段落の <最初か最後> の部分を <置いた数> 行にしました（keep-<first か last>-lines = <求めた数>）` |

コードの番号は、採択のときに、使われていない番号であり同じ時期の ADR と重ならないことを確かめて振り直した（「決めたことの記録」）。

G07111 を警告にするのは、`@no-page-break` の G07037 と同じく、指定を守らずに組んだ結果だからである。
G07112 と G07113 を notice にするのは、罫線の段落の G07046 と同じく、版面に入らないものを組むための唯一の置き方だからである。
G07113 は、書いた値でも既定の値（2）でも出す。
今の本でも、空の段で 1 行だけの部分ができれば出るようになる（「トレードオフ」）。

### HTML と EPUB

`style.css` の段落スタイルの規則（`p.ps-<名前>`、`body` は `p`）に、次の CSS を書く。
既定の値なら書かない。

| キー | CSS |
| --- | --- |
| `keep-with-next` が 1 以上 | `break-after: avoid` |
| `keep-all-lines = true` | `break-inside: avoid` |
| `keep-first-lines` | `orphans` |
| `keep-last-lines` | `widows` |
| `page-break` | `break-before: column`、`page`、`recto`、`verso` |

CSS の `orphans` と `widows` の既定は 2 なので、Golem の既定と一致する。
ファイルの `@style-def` で改めた段落スタイルは、行揃えなどと同じく `body.file-<n>` の規則で書き直す（[docs/adr/0217](0217-html-spaces-of-paragraph-styles-redefined-in-files.md)）。
EPUB の読書環境がこれらを読むかは確かめていない。
プレーンテキスト（golem-text）は、改ページと同じく何も出力しない。

### 文書

- [docs/specifications.md](../specifications.md) の「style.toml」の段落スタイルのキーの節と、「改ページ」の節に、上の規則を書く。「改ページ」の節の段落の規則は、`keep-first-lines` と `keep-last-lines` の既定の値として書き直す。不変条件とテストの場所の段落に K1 から K6 を足す。
- [docs/diagnostics.md](../diagnostics.md) に G07111 から G07113 を足し、G03006 の主な原因に新しいキーの値の誤りを足す。
- docs/markup.md は変えない（記法を変えないため）。
- マニュアルの style.toml の章（`manual/chapters/05-style.gm`）と InDesign との対応の付録（`manual/appendices/f-indesign.gm`）に欄を足す。
- [ロードマップ](../roadmap.md) から次を消す。
  - 「LaTeX との差を埋める項目」の「段落スタイルの分割禁止と連動」の項目。
  - v2 の「韻文の拡張」の「連をページで分けない指定は、v1.0.0 の「段落スタイルの分割禁止と連動」の段落を分割しない欄で扱う。」の一文。
  - v2 の「孤立行の規則の見直し」の「利用者が行の数を指定する欄は v1.0.0 の「段落スタイルの分割禁止と連動」に移したので、この項目には、既定の規則を和文の本で緩めるかどうかだけが残る。」の一文。項目の残りはそのまま残す。
  - 「ページと見開きをまたぐ泣き別れの禁止」の「段落の単位の設定は「段落スタイルの分割禁止と連動」で」の部分は、仕様書の「改ページ」の節を指す文に改める。
- `docs/golem-layout/models/pagination.als` に `keep-first-lines`、`keep-last-lines`、`keep-all-lines` を述語として足し、走らせ直して `docs/golem-layout/models/README.md` に結果を書く（ロードマップの「手で確かめる項目」の規則）。

## 実装しないこと

- **前の段落と連動**：InDesign の「前の段落と連動」は作らない。同じ組み方は、前の段落のスタイルの `keep-with-next` か `@no-page-break` で書ける。二つの段落のどちらの欄で決めるかの規則が増えるので、要るとわかってから足す。
- **次のフレーム**：Golem にはテキストフレームがないので、`page-break` に `"frame"` の値はない。
- **見出しの `page-break` の値を広げること**：見出しは `"recto"` と `"any"` のままにする。`"page"` などを見出しに足すかは、見出しの体裁の ADR で決める。
- **組み込みのスタイルの既定を変えること**：`verse` に `keep-all-lines = true` を持たせない（「メンテナーが決めること」の 3）。
- **既定の規則を和文の本で緩めること**：v2 の「孤立行の規則の見直し」に残す。
- **改ページの大域の最適化**：連動の連なりは、先頭から詰める今の改ページの中で解く。
- **表のセル、注の本文、キャプション、傍注の本文の改ページ**：これらは改ページが段落として置かないので、欄を当てない。

## 不変条件

段の行の数を C とする。
段落 P の `Keep` を (F, L, A)、`keep-with-next` を N、`page-break` を S とする。
「部分」は、一つの段に置かれた P の行（連では韻文の行）の並びである。
「空の段から置いた」は、P の行を置く前に、その段に何も置かれていないか見出しだけが置かれていたことを言う。

- **K1 最初の部分**：P が二つ以上の部分に分かれれば、最初の部分は F 行以上である。ただし、最初の部分を空の段から置き、出力が P の `ShortPart` を記録するときは除く。
- **K2 最後の部分**：P が二つ以上の部分に分かれれば、最後の部分は L 行以上である。ただし、最後の部分の前の部分を空の段から置き、その段が P の行だけを持ち、出力が P の `ShortPart` を記録するときは除く。
- **K3 分割しない**：A が真の P は一つの段に置かれる。ただし、P の最初の部分を空の段から置き、出力が P の `SplitKept` を記録するときは除く。
- **K4 連動**：N > 0 の P と、その後に置くブロック B について、P の最後の行と B の最初の部分（「次の段落と連動」の量）が同じ段に置かれることと、出力が P の `UnmetKeepNext` を記録することの、ちょうど一方が成り立つ。
- **K5 開始位置**：S が `"column"` なら、P の最初の行の段には、P より前に書いたもののうち、送った図版と続きの脚注のほかに何も置かれていない。`"page"` なら、そのページのどの段にもそれらのほかに何も置かれていない。`"recto"`、`"verso"` なら、さらにページの番号が奇数、偶数である。
- **K6 余分な改めがない**：S が `"column"` なら、P の段は、流れが来た段か、その次の段である。`"page"` なら、流れが来た段のページか、その次のページである。`"recto"`、`"verso"` なら、流れが来た段のページ以後で偶奇の合う最初のページである。流れが来た段は仕様書の「改ページ」の節の語である。
- **K7 既定は今と同じ**：すべての段落が `defaultKeep` を持ち、`FStart` と `FKeepNext` のない流れの出力は、この ADR の前の実装の出力と等しい。

[docs/adr/0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の I4 と I5 は、K1 と K2 の F = L = 2 の場合である。
I4、I5 の述語は、段落の `Keep` を読む K1、K2 の述語に置き換える。
I6 の「その後の段落の最初の 2 行」は、その段落の最初の部分（上の `firstPart`）と読む。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 段落の行の数 n | 1、F − 1、F、F + L − 1、F + L、C、C + 1 |
| F、L | 1（規則なし）、2（既定）、3 |
| A | 偽、真で n ≤ C、真で n = C + 1 |
| N | 0、2（`nextNeed` と同じ）、3（後の段落の最初の部分を広げる） |
| 連動の連なり | 一つ、二つ、合わせて C を超える二つ |
| S | `"any"`、`"column"`、`"page"`、`"recto"`、`"verso"`、空の段の直後、`@page-break` の直後 |
| 段の数 | 1、2 |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。

### 列挙の拡張（golem-layout のテスト）

[docs/adr/0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の `PaginateEnum` に、次の要素を足す（[`PaginateEnum.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-layout/test/PaginateEnum.hs#L38-L84)）。

- `EKept Keep !Int`：`Keep` を持つ n 行の段落。`Keep` は (1, 1, 偽)、(3, 3, 偽)、(2, 2, 真) の三つ、n は 1 から 5。
- `EStanza Keep [Int]`：連。韻文の行の数は 3 と 4 で、各韻文の行は 1 行。一つの連だけ、二つめの韻文の行を 2 行にする。`Keep` は既定と (2, 2, 真)。
- `EKeepNext !Int`：直前の要素が段落か連なら、その後に置く `FKeepNext`。N は 2 と 3。
- `EStart BreakKind`：直後の段落の前に置く `FStart`。四つの種類のすべて。

今の要素の列挙（`inputs`、`fullInputs`）には足さず、別の列挙 `keepInputs` にする。
`keepInputs` の要素は、上の要素に、`EPara` の 1 から 4、`EHeading`、`EFigure` の C、`ESpace`、`EBreak` を加えたものとする。
段の行の数は 3 から 5、段の数は 1 と 2 である。
プルリクエストの CI は要素 3 個まで、毎晩の `enum.yml` は要素 5 個まで調べる（[docs/adr/0208](0208-widen-lightweight-formal-methods.md) の数と同じ）。
実装のときに時間を測り、プルリクエストで golem-layout のテストが 30 秒以上延びるなら、上限を下げる（[docs/adr/0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の「メンテナーが決めること」の 3）。

### 述語（golem-layout のテスト）

- `PaginateInvariants` に K1 から K6 の述語を足し、`keepInputs` のすべての入力で、I1 から I8（I4、I5 は K1、K2 に置き換えたもの）と K1 から K6 が違反を返さないことを確かめる。テストの名前に番号を入れる（`K1 first part`、`K4 keep with next` など）。
- 述語のテスト：K1 から K6 のそれぞれについて、規則を破った出力を手で作り、その述語だけが違反を返すこと。`ShortPart`、`SplitKept`、`UnmetKeepNext` を記録した出力では、K1、K2、K3、K4 が違反を返さないこと。K4 では、守ったのに `UnmetKeepNext` を記録した出力も違反とすること。
- K7：今の `inputs` のすべての入力で、`defaultKeep` を持つ流れの出力が、この ADR の前の実装の出力を固定した値と等しいこと。前の実装の出力は、実装の前に今の `inputs` を組んだ結果のハッシュをテストに固定して比べる。

### 例のテスト（golem-layout の `PaginateSpec`）

- `splitAtBreak` が `defaultKeep` で今の値を返すこと（n が 1 から 8、k が 0 から n のすべて）。
- 5 行の段落に F = 3 を当て、段に 2 行だけ入るとき、全体を次の段に送ること。L = 3 で 4 行が入るとき、2 行だけを置くこと。
- `keep-all-lines` の C + 1 行の段落が、段の途中から始まるとき、次の段の先頭から置かれ、`SplitKept` を記録すること。
- `keep-with-next = 3` の段落の後の 6 行の段落について、最初の 3 行が前の段落の最後の行と同じ段にあること。
- 連動の連なりの合計が C を超えるとき、先頭の段落を次の段から置き、入らない連動の一か所だけを `UnmetKeepNext` として記録すること。
- `@page-break` の直後の `page-break = "page"` の段落が、白ページを作らないこと。`page-break = "recto"` の段落が、偶数ページの後に白ページを入れること。
- 見出しの直後の `page-break = "page"` の段落で、見出しが前のページに残り、diagnostic を記録しないこと。

### golem-project と golem-driver のテスト

- 五つのキーの読み込み、`based-on` の引き継ぎ、値の誤り（G03006）、負の整数（G02103）、`code` に書いた場合（G03006）。
- `@style-def` に書いたキーの読み込みと誤り。
- golem-driver：G07111 から G07113 を、最後の回の結果から、それぞれ段落の範囲に出すこと。同じ入力で二度組んで、diagnostics の順が同じであること。
- HTML：上の表の CSS を既定でないときだけ書き、既定の本の `style.css` が変わらないこと。
- golden：今の fixture の PDF と diagnostics が変わらないこと（K7 を本の単位で確かめる）。G07113 が新しく出る fixture があれば、その notice を golden に足し、PR の説明に挙げる。

## トレードオフ

`Keep` を `FParagraph` などの欄にするので、改ページのテストの流れをすべて書き直す。
書き直しは `defaultKeep` を足すだけの決まった手順のものである。
代わりに、段落の分け方が型に現れ、述語が段落ごとの規則を読める。

段落を分割しない段落が段に入らないとき、次の段から置いてから分ける。
罫線の段落と同じ置き方なので規則は一つで済むが、前の段の残りが空く。
段より長い段落に `keep-all-lines` を当てた本では、そのたびに段の下が空く。
G07112 がそれを知らせる。

G07113 を既定の値でも出すので、今の本でも、空の段や見出しだけの段で 1 行の部分ができる箇所に notice が出るようになる。
置き方は変わらず、diagnostics だけが増える。
「出力を黙って変えない」の原則に従い、規則を守れなかった置き方を知らせる。

連動の連なりは、段に入る分だけ先読みして、入らなければ先頭を送る貪欲な解き方である。
InDesign がどう分けるかは確かめていない。
大域の最適化を使えば空きの少ない分け方を選べるが、v1 では改ページを先頭から詰める手順のままにする（[golem-layout ADR 0003](../golem-layout/adr/0003-pagination-and-s2.md)）。

## メンテナーが決めること

1. **欄の名前**：推奨は、InDesign のスクリプトの属性の名前（`keepWithNext`、`keepAllLinesTogether`、`keepFirstLines`、`keepLastLines`）を kebab-case にした `keep-with-next`、`keep-all-lines`、`keep-first-lines`、`keep-last-lines` と、見出しと同じ `page-break` である。属性の名前は、この ADR を書くときにヘルプで確かめていない。
   - 退けた案の一つは、開始位置を InDesign の名前どおり `start-paragraph` にすることである。見出しの `page-break` と同じ意味の欄に二つの名前ができる。
   - もう一つは、行の数を一つの表（`keep = { first = 2, last = 2, all = false }`）にすることである。`based-on` で表ごとに引き継ぐか欄ごとに引き継ぐかの規則が増え、ほかの段落スタイルのキーが平らなのと揃わない。
2. **段に入らない `keep-all-lines` の段落の置き方**：推奨は、次の段から置いてから分けることである。罫線を持つ段落と同じ規則になり、「分けないもの」の置き方が一つで済む。
   - 退けた案は、空の段にも入らないとわかる段落を、今の位置から分けることである。前の段の空きはなくなるが、空の段に入るかを、注の行も含めて先に求める手順が要り、罫線の段落と規則が分かれる。
3. **組み込みの `verse` の既定**：推奨は、`keep-all-lines` を持たせず、今の連の規則のままにすることである。所有者の決定は、書かなければ今の規則のままとした。fixture の『The Hunting of the Snark』は 33 行の版面に 5 行周期の連が続くので、分けない既定にするとほぼすべてのページの下に空きが残る。
   - 退けた案は、`verse` に `keep-all-lines = true` を持たせることである。連を分けない組み方は詩集で好まれるが、空きの量が版面と連の長さで大きく変わり、既定として当たり外れが大きい。
4. **`keep-with-next` の上限**：推奨は、InDesign と同じ 5 である。InDesign の値の範囲は、ヘルプの抜粋で「最大 5 行」と確かめた。
   - 退けた案は、上限を設けず段の行の数で切り詰めることである。InDesign から移る人に値の意味が同じであることを優先する。
5. **G07113 を既定の値でも出すか**：推奨は、出すことである。書いた値と既定の値で diagnostics が変わると、同じ組み方に二つの diagnostic の規則ができる。
   - 退けた案は、利用者が書いたときだけ出すことである。今の本の diagnostics は変わらないが、`keep-last-lines = 2` を書いただけで notice が増える。

## 決めたことの記録

2026-11-09 に、tett23 がすべて推奨のとおりに決めた。

1. 欄の名前は、推奨のとおり `keep-with-next`、`keep-all-lines`、`keep-first-lines`、`keep-last-lines` と、見出しと同じ `page-break` とする。
2. 段に入らない `keep-all-lines` の段落は、推奨のとおり次の段から置いてから分ける。
3. 組み込みの `verse` は、推奨のとおり `keep-all-lines` を持たず、今の連の規則のままとする。
4. `keep-with-next` の上限は、推奨のとおり 5 とする。
5. G07113 は、推奨のとおり既定の値でも出す。

diagnostic のコードは、採択のときに、docs/diagnostics.md と origin/main のコードで使われていない番号であり、同じ時期の ADR と重ならないことを確かめて、G07111、G07112、G07113 とした。
草案の仮の番号から振り直した。

## 参考文献

- [2026-10-17 の調査](../audits/2026-10-17-latex-gap-for-v1.md) の 7 と「所有者の決定」
- [golem-layout ADR 0003](../golem-layout/adr/0003-pagination-and-s2.md)、[golem-layout ADR 0019](../golem-layout/adr/0019-keep-with-next-counts-footnotes.md)、[golem-layout ADR 0021](../golem-layout/adr/0021-keep-with-next-counts-widow-and-orphan.md)
- [docs/adr/0017](0017-forced-page-breaks.md)、[docs/adr/0030](0030-manual-page-break-control.md)、[docs/adr/0055](0055-no-page-break-moves-short-paragraphs-whole.md)、[docs/adr/0180](0180-verse-spacing-and-stanza-breaks.md)、[docs/adr/0189](0189-paragraph-alignment-spacing-and-end-indent.md)、[docs/adr/0204](0204-pagination-invariants-by-exhaustive-small-inputs.md)、[docs/adr/0206](0206-pagination-points-the-invariants-did-not-decide.md)、[docs/adr/0208](0208-widen-lightweight-formal-methods.md)、[docs/adr/0217](0217-html-spaces-of-paragraph-styles-redefined-in-files.md)
- [golem-driver ADR 0027](../golem-driver/adr/0027-paragraph-style-rules.md)
- Adobe, InDesign User Guide, Paragraph break options, https://helpx.adobe.com/indesign/desktop/format-and-style-text/composition-and-text-wrapping/paragraph-break-options-in-indesign.html（本文は読めず、検索の抜粋で確かめた）
- W3C, Requirements for Japanese Text Layout, https://www.w3.org/TR/jlreq/（該当する節は確かめていない）
- W3C, CSS Fragmentation Module Level 3, https://www.w3.org/TR/css-break-3/（`break-before`、`break-after`、`break-inside`、`orphans`、`widows`）
- CTAN, needspace, https://ctan.org/pkg/needspace
- LaTeX2e unofficial reference manual, https://latexref.xyz/（`\nopagebreak`、`\samepage`、`\widowpenalty`、`\clubpenalty`）
