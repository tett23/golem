# ADR 0260: 前付けのノンブルとページラベル

ステータス: 採択（未実装）

## 文脈

[ロードマップ](../roadmap.md) の v1.0.0 の「LaTeX との差を埋める項目」に、「前付けのノンブルとページラベル」がある。
本の部分ごとにノンブルの様式と開始の番号を変え、PDF にページラベルを書き、目次、索引、相互参照のページ番号にも同じ書式を使う項目である。
[2026-10-17 の調査](../audits/2026-10-17-latex-gap-for-v1.md) の 6 が元であり、所有者はこの項目を v1.0.0 に置くと決めた（同じ調査の「所有者の決定」）。

前付けを別のノンブルにするのは、欧文の本に限らない。
JLReq の 2.6.3 は、本を通して数を続ける通しノンブルと、前付けや後付けを別に 1 から始める別ノンブルを挙げ、前付けと本文を別ノンブルにする場合は前付けにローマ数字の小文字を使う例が多い、と書く。
2.6.1 は、縦組みで掲げるノンブルは漢数字、横組みで掲げるノンブルはアラビア数字とし、前付けを別ノンブルにした横組みのノンブルにはローマ数字の小文字を使う、と書く。
2.6.2 は、ノンブルを紙葉の表面を 1 として始めるので、奇数のページが表（横組みでは右、縦組みでは左）になる、と書く。

### 今の Golem

今の Golem では、ページの番号は本の通し番号の一つだけである。
`style.toml` のマスターページの `folio` の `format` には、ほかの番号の書式と同じく表記を書ける（[ADR 0177](0177-note-mark-style-and-numerals.md)）。
`format = "{n:lower-roman}"` のマスターページを前付けのファイルに当てれば、前付けのノンブルはローマ数字で描ける。
ただし、番号は通し番号のままで、本文の最初のページを 1 に戻す手段はない。
ノンブルは、通し番号を `formatNumber` で書いた文字列である（[`Draw.hs` の `masterMarks`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L1414-L1420)、[`formatNumber`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-numerals/src/Golem/Numerals/Format.hs#L224-L246)）。

ページを指す値は、三つの経路でどれも通し番号の整数である。

- **相互参照**：`[ref-page]` は文書の組み立て（S1）で解決せず、`Ref` のまま改ページまで残る（[`Assemble.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-assemble/src/Golem/Assemble.hs#L637)）。組版は、ラベルのページの通し番号を引き、縦組みでは `[numbers]` の `ref-page` の表記の数として、横組みでは算用数字の文字列として組む（[`Japanese.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-layout/src/Golem/Layout/Japanese.hs#L541-L547)、[ADR 0118](0118-ref-page-numerals-in-vertical-text.md)）。
- **索引とチャネルの一覧**：印のページの通し番号を、表記の決まっていない数 `Number` として並べる（[`indexLines`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L918-L930)、[golem-driver ADR 0007](../golem-driver/adr/0007-pdf-index-and-bibliography.md)）。
- **目次**：見出しのページの通し番号を `Number` として組む（[`pageNumberLine`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L861-L865)）。仕様書は「数はページの通し番号であり、ノンブルの書式は使わない」と書く（[golem-driver ADR 0009](../golem-driver/adr/0009-pdf-toc-page-numbers.md)）。

ラベルと索引の印のページは、レイアウトの繰り返し（S2）が仮定する値でもある。
仮定の値は通し番号の表であり（[`Assumed`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L1057-L1061)、[`labelPages` と `markPages`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-layout/src/Golem/Layout/Paginate.hs#L603-L609)）、前の回と同じになるまで組み直す。

PDF の文書カタログは `/PageLabels` を持たない（[`Writer.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L598-L610)）。
PDF のビューアーは、ページラベルのない PDF のページを 1 からの通し番号で示す。
前付けにローマ数字のノンブルを描いても、ビューアーの「ページへ移動」で本文の 1 ページを開くには、前付けのページ数を足した数を打つことになる。

HTML と EPUB は、`[ref-page]` を参照先の題へのリンクにする（[`Html.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-html/src/Golem/Html.hs#L686-L688)）。
プレーンテキストは、参照先の題を「」で括る（[`Text.hs`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-text/src/Golem/Text.hs#L222-L224)）。
どちらもページ番号を出さないので、ノンブルの様式はこの三つの出力に関わらない。

### どこに書くか

InDesign は、ページを選んでセクションを開始し、セクションごとにノンブルの開始の番号、様式、接頭辞を決める（調査の 6 に挙げた Adobe のヘルプ）。
ブックでは、ドキュメントごとに同じ設定を持つ。
LaTeX は、原稿の中の `\frontmatter`、`\mainmatter`、`\backmatter` と `\pagenumbering` で、様式を変えて番号を 1 に戻す。
book クラスの既定（`openright`）では、`\mainmatter` などは `\cleardoublepage` で次の奇数ページから始める。

Golem の一冊は、マニフェストの章の配列に並べたファイルからなる（仕様書の [「プロジェクトの構成と import」](../specifications.md#プロジェクトの構成と-import)）。
前付けの目次も、マニフェストに並べた前付けのファイルに書く。
ファイルごとのマスターページも、章の項目の `master` で決める（[`ChapterEntry`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-project/src/Golem/Project/Manifest.hs#L186-L189)）。
本のどの部分が前付けかは、本の構成の情報であり、原稿の中身ではない。
InDesign のブックのドキュメントごとの設定に当たるのは、マニフェストの章の項目である。
この ADR は、セクションをマニフェストの章の項目に書く（「メンテナーが決めること」の 1）。

### 互換について

[ロードマップ](../roadmap.md) は、この項目を記法、意味論の IR、プラグインの ABI を変える項目に数えている。
調査は、ページ番号の値の表し方が意味論の IR の参照の値に関わると見た。
コードを読むと、ページの値は IR に入らない。
`[ref-page]` は IR の中では `Ref` のまま改ページまで残り、ページの値はレイアウトの中でだけ決まる。
プラグインも、ページ番号（S2）の値を受け取れない（仕様書の「プラグイン」の「実行の範囲」）。
この ADR の設計では、原稿の記法も、意味論の IR も、CDDL も変わらず、ABI のバージョンは上がらない。
変わるのは `manifest.toml` の章の項目のキーを足すことであり、[ADR 0174](0174-compatibility-promises-for-1-0.md) はキーを足すことを互換を壊す変更に数えない。
それでも、所有者の決定のとおり v1.0.0 に置く。

### ほかの ADR との関係

この ADR は、ページを指す値（下の「ページラベル」）と、それを書く規則を決める。
同じ時期の ADR のうち、[ADR 0264](0264-paragraph-styles-for-toc-entries.md)（目次の項目の書式）と [ADR 0265](0265-index-cross-references-page-ranges-and-section-headings.md)（索引の参照、ページの範囲、見出し）は、この ADR のページラベルを使う。
[ADR 0267](0267-pdf-bookmarks-and-links-inside-the-document.md)（PDF のしおりとリンク）は、リンクの先のページを通し番号で指す。
この ADR は、それらより先に実装する。

## 実装すること

### セクション

**セクション**は、ノンブルの数え方を共有するページの並びである。
セクションは、章の項目の `page-numbering` で始める。

```toml
chapters = [
  { file = "front/title.gm", master = "plain", page-numbering = { style = "lower-roman" } },
  { file = "front/preface.gm", master = "front" },
  { file = "front/toc.gm", master = "front" },
  { file = "chapters/01.gm", page-numbering = { style = "arabic", start = 1 } },
  "chapters/02.gm",
]
```

`page-numbering` は表であり、二つのキーを持つ。

| キー | 値 | 省いたとき | 意味 |
| --- | --- | --- | --- |
| `style` | 数の表記の名前 | 表記を決めない | セクションのノンブルの表記 |
| `start` | 1 以上の整数 | 前のページの番号に 1 を足して続ける | セクションの最初のページの番号 |

`style` には、golem-numerals の登録表の名前（`arabic`、`kanji`、`kanji-digits`、`circled`、`lower-alpha`、`upper-alpha`、`lower-roman`、`upper-roman`、`iroha`、`aiueo`、`asterisks`、`note-symbols`、仕様書の「style.toml」の表記の表）を書く。
`arabic` は、省いたときと同じく表記を決めない数として扱う。
縦組みの本の相互参照と目次の番号が、今と同じく `[numbers]` の表記で組まれるようにするためである。
表の空の `page-numbering = {}` は、表記を変えずに改ページだけをする、つまり今の番号を続けるセクションである。

`page-numbering` は、ファイルを指す表の形の項目にだけ書ける。
最初のセクションより前のページ（本の最初のファイルに `page-numbering` がない本）は、表記を決めず 1 から数える暗黙のセクションに属する。
`page-numbering` を一つも書かない本は、この暗黙のセクションだけからなり、今と同じ番号になる。

### セクションの前の改ページ

`page-numbering` を持つ項目のファイルは、新しいページから始める。
改ページの種類は `start` で決める。

- `start` が奇数なら、改丁（`@page-break recto` と同じ規則）。今のページが空で奇数なら何もせず、そうでなければ次の奇数ページから続け、途中のページを白ページにする。
- `start` が偶数なら、次の偶数ページから（`@page-break verso` と同じ規則）。
- `start` を省いたら、今のページが空でなければ次のページから続け、空なら何もしない。

この改ページは、ファイルの最初のブロックの前に、レイアウトの流れの要素として置く。
意味論の IR の `BreakKind` は変えない。
`start` を省いた改ページは、空のページを閉じない点で `@page-break` と違うので、golem-layout の流れの中にだけある種類として足す。

セクションの**最初のページ**は、この改ページが開いたページである。
ファイルの最初のものが `page-break = "recto"` の見出しで、改ページの後に白ページができる場合も、最初のページは改ページが開いたページ（白ページ）である。
同じページを最初のページとするセクションが二つ以上あれば、後のセクションがそのページから始まり、前のセクションはページを持たない。

改ページを置くのは、表の側の奇数ページを奇数の番号にするためである（JLReq の 2.6.2）。
Golem のページの左右は通し番号の偶奇で決まる（仕様書の柱の規則）。
`start` の偶奇に合わせて改ページするので、どのページでも、ノンブルの番号の偶奇と通し番号の偶奇が等しい。
`start` を省いたセクションは前のページから数を続けるので、偶奇はそのまま保たれる。

### ページラベル

**ページラベル**は、ページを指す値である。

```haskell
-- golem-layout
data PageLabel = PageLabel
  { -- | 通し番号。1 から。PDF のページの位置と同じ
    plIndex :: !Int,
    -- | セクションの中の番号
    plNumber :: !Integer,
    -- | セクションの表記。Nothing は表記を決めていない数（arabic を含む）
    plNotation :: !(Maybe Notation)
  }
```

ページ p のページラベルは、次のように決める。

1. p 以前に最初のページを持つセクションのうち最後のものを、p のセクションとする。
2. p がセクションの最初のページなら、番号は `start`、`start` がなければ p − 1 の番号に 1 を足した数（p が 1 なら 1）とする。
3. そうでなければ、番号は p − 1 の番号に 1 を足した数とする。
4. 表記はセクションの `style` とする。

ページラベルを**書く**とは、次の規則で inline にすることである。
規則は一つの関数（`pageLabelInlines`）に置き、相互参照、目次、索引、チャネルの一覧のすべてがそれを使う。

- 表記を決めていないラベルは、今と同じく番号の `Number` にする。縦組みでは `[numbers]` の表記（相互参照では `ref-page`）、横組みでは算用数字になる。
- 表記を決めたラベルは、golem-numerals の `writeNumber` で書いた文字列の `Text` にする。縦組みの中のローマ数字は、ほかの欧文と同じく回転して組む。

目次、索引、相互参照には、マスターページの `folio` の `format` の飾り（`"- {n} -"` の `-` など）を使わず、表記だけを使う。
`format` はマスターページごとに違い、どの `format` を使うかが一つに決まらないからである。
LaTeX でも、目次に出るのは `\thepage` であり、柱の飾りではない。

### ノンブル

マスターページの `folio` の `format` の差し込みは、通し番号ではなく、ページラベルの番号を書く。
表記を書かない `{n}` は、セクションの表記で書き、表記を決めていないセクションでは今と同じく算用数字で書く。
`{n:upper-roman}` のように表記を書いた差し込みは、セクションによらずその表記で書く。

隠しノンブル（[golem-driver ADR 0021](../golem-driver/adr/0021-hidden-folios.md)）は、今と同じく通し番号を算用数字で入れる。
つまり、隠しノンブルは前付けと本文を通して数えた番号であり、セクションの表記と番号によらない。
前付けを `lower-roman` にして本文を `start = 1` から数え直した本でも、本文の最初のページの隠しノンブルは、前付けのページ数に 1 を足した数になる。
製本で確かめるのはページの物理的な順だからである（2026-11-09 の tett23 の決定）。
柱の偶数と奇数、白ページ、`drawsFolio` の判定も、今と同じく通し番号で決める。

### 収束

S2 の仮定の値（`Assumed`）は、ラベルと索引の印のそれぞれについて、通し番号の整数に代えてページラベルを持つ。
`labelPages` と `markPages` は、ページの列とセクションの最初のページからページラベルを作る。
セクションの最初のページが回ごとに動けば、通し番号が同じでもラベルの番号が変わるので、組み直しの条件に入る。
上限の回数（5 回）までに収束しなければ、今と同じく G07021 とする。
[ADR 0251](0251-reuse-the-compositions-of-unchanged-units-between-fixpoint-rounds.md) の使い回しは、`[ref-page]` を含む単位を毎回組み直すので、そのまま成り立つ。

目次のページ番号は、今と同じく収束した後に一度だけ求める（[golem-driver ADR 0009](../golem-driver/adr/0009-pdf-toc-page-numbers.md)）。
目次の行分割はページ番号 999 の幅を予約して決めるので、ページラベルの文字列の幅は目次の行数を変えない。
`xxviii` のように予約より広いラベルは、今の `tocPage` のとおりリーダーを縮めて置く。

索引の一つの項目のページは、通し番号の昇順に並べ、同じページは一度だけ出す。
番号の昇順ではないのは、前付けの `iii` と本文の `3` が同じ番号を持つからである。
範囲（`3–5`）の作り方は [ADR 0265](0265-index-cross-references-page-ranges-and-section-headings.md) が決める。
同じセクションの続くページかどうかは、二つのページラベルの通し番号の差が 1 で、後のページがセクションの最初のページでないことで判定できる。

### マニュアルで試すこと

実装のプルリクエストは、使い手のマニュアル（`manual/`）の「はじめに」を、小文字のローマ数字のノンブルで組む。
tett23 が、この ADR の設定で実際の本を組めるかを試すように求めたからである。

- `manual/manifest.toml` の章の配列で、`preface.gm` の項目を `{ file = "preface.gm", page-numbering = { style = "lower-roman" } }` にし、`chapters/01-first-book.gm` の項目を `{ file = "chapters/01-first-book.gm", page-numbering = { style = "arabic", start = 1 } }` にする。
- 「はじめに」と目次（`toc.gm`）は、`lower-roman` のセクションに入る。目次は `page-numbering` を持たないので、「はじめに」の番号を続ける。
- 第 1 章は改丁で始まり、ノンブルは 1 に戻る。マスターページ `body` の `folio` の `format` は `{n}` なので、変えずにセクションの表記で書かれる。
- 目次の第 1 章からのページ番号は算用数字の 1 から始まる。「はじめに」を指す相互参照と索引の印があれば、そのページ番号はローマ数字になる。
- 組んだ PDF の `/PageLabels` を読み、前付けの範囲が `/S /r`、第 1 章からの範囲が `/S /D` であることと、トンボを付けて組んだ PDF の隠しノンブルが前付けから通した番号であることを確かめる。

組めない、または組んだ結果が読み手に誤ったページを示すとわかれば、実装のプルリクエストで止め、tett23 に報告する。

### PDF のページラベル

ページラベルの列が「表記を決めない数で 1 から始まる一つの範囲」でない本では、文書カタログに `/PageLabels` を書く（ISO 32000-1 の 12.4.2）。
今と同じ番号の本には書かず、PDF のバイト列を変えない。

`/PageLabels` は数の木であり、`/Nums` の配列に、範囲の最初のページの位置（0 から）とラベルの辞書を昇順に並べる。

- 表記を決めないセクションは `/S /D`、`upper-roman` は `/S /R`、`lower-roman` は `/S /r` とし、`/St` に最初のページの番号を書く。1 なら `/St` を省く。
- ほかの表記のセクションは、ページごとに一つの範囲を作り、`/P` に `writeNumber` の文字列を書き、`/S` を書かない。

`/S /A` と `/S /a` は使わない。
PDF の文字の様式は 26 を超えると `AA`、`BB` と同じ字を重ねるので、Golem の `lower-alpha`（`aa`、`ab`）と食い違うからである。
`/P` の文字列は、文書カタログの `/Lang` と同じ `pdfTextString` で書く。

タグ付き PDF（[ADR 0183](0183-tagged-pdf-and-pdf-a.md)）の構造は変わらない。
ノンブルは今と同じく `Pagination` の Artifact であり、目次の項目の `TOCI` はページラベルの文字列を含む。
`/PageLabels` を PDF/X-4、PDF/A-2a、PDF/UA-1 の規格がどう扱うかは、規格の本文で確かめていない。
実装のときに、golem-pdf の PDF/X-4 の検証器（[golem-pdf ADR 0003](../golem-pdf/adr/0003-pdf-x-4-validator.md)）と、CI の `verapdf` ジョブ（veraPDF）で確かめる。

### HTML、EPUB、プレーンテキスト

`page-numbering` は、HTML、EPUB、プレーンテキストの出力を変えない。
三つはページを持たず、`[ref-page]` は今と同じく題へのリンクか題である。
`page-numbering` の値の誤り（下の G03121 から G03123）は、マニフェストを読むときの誤りなので、どのターゲットでも出る。
EPUB の `page-list` は扱わない（「実装しないこと」）。

### diagnostics

コードの番号は、採択のときに、使われていない番号であり同じ時期の ADR と重ならないことを確かめて振り直した（「決めたことの記録」）。

- **G03121**（エラー）：`style` が登録表の名前でない。位置は `style` の値。メッセージは `page-numbering の style <値> は数の表記の名前ではありません` とし、書ける名前を添える。
- **G03122**（エラー）：`start` が 0 である。位置は `start` の値。負の数は、ほかの自然数と同じく G02103 とする（[ADR 0102](0102-natural-number-type.md)）。整数でない値と、`page-numbering` の未知のキーは、ほかのスキーマの誤りと同じく G03001 とする。
- **G03123**（エラー）：同じファイルを章の配列に二度並べ、二つの項目の `page-numbering` が異なる。位置は二つ目の項目の `page-numbering` の値で、一つ目を関連する位置として添える。ページとファイルの対応はファイルごとなので、どちらの値を使うかが決まらないからである。
- **G07109**（警告）：セクションがページを持たない。後のセクションが同じページから始まった場合と、本がそのセクションの改ページの後に何も置かずに終わった場合である。位置はそのセクションの `page-numbering` の値。PDF をターゲットに含むときだけ出す。ページを持たないセクションは何も変えないので出力は正しいが、書いた設定が働いていないことを黙らないために知らせる。
- **G07110**（エラー）：セクションの表記で、そのセクションのページの番号を書けない（`circled` の 51 ページなど、[ADR 0213](0213-numbers-the-number-formats-cannot-write.md)）。セクションごとに、書けない最初のページについて一つだけ、`style` の値の位置に出し、PDF を書かない。ノンブルを描かないページでも、ページラベルとして書くので検査する。表記を書かない `{n}` のノンブルがこの理由で書けないときは G07110 だけを出し、G07106 は出さない。G07106 は、`format` に書いた表記で書けない場合に限る。

G07109 と G07110 は、[`folioErrors`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L150-L167) と同じ所で、収束した最終回のページから求める。
出す順は、マニフェストのセクションの順とする。

### モジュールと依存

- golem-project：`ChapterFile` に `page-numbering` の値を足し、G03121 から G03123 を検査する。表記の名前は、今も使っている golem-assemble の `Golem.Assemble.Formats`（golem-numerals の再輸出）の `notationNamed` で引く。
- golem-layout：`PageLabel` と、セクションの最初のページの記録（流れの要素とページの欄）、`start` を省いた改ページを足す。golem-layout はすでに golem-numerals に依存している。
- golem-typeset：`Assumed`、`pageNumberLine`、`indexLines`、`channelLines`、`masterMarks`、`folioErrors` をページラベルで書き直し、G07109 と G07110 を出す。
- golem-pdf：`Document` にページラベルの範囲の列を足し、文書カタログに `/PageLabels` を書く。golem-pdf の型は golem-numerals に依らず、様式（`D`、`R`、`r`、なし）と接頭辞の文字列と開始の番号だけを持つ。

golem-* のパッケージのあいだの build-depends は足さない。

### 文書

実装のプルリクエストは、次の文書を直す。

- docs/specifications.md：「プロジェクトの構成と import」に `page-numbering` を、「目次と文書構造の参照」の目次の段落の「数はページの通し番号であり、ノンブルの書式は使わない」をページラベルの規則に、「style.toml」のマスターページと `[numbers]` の `ref-page` と隠しノンブルの段落に通し番号とページラベルの区別を、「索引」の並べ方を、PDF の出力に `/PageLabels` を書く。
- docs/diagnostics.md：G03121、G03122、G03123、G07109、G07110 を足し、G07106 の意味に G07110 との分け方を書く。
- 使い手のマニュアル：前付けのノンブルの書き方の例を、docs/manual-policy.md に従って置く。「マニュアルで試すこと」のとおり、`manual/manifest.toml` の「はじめに」と第 1 章の項目に `page-numbering` を書く。
- README：変えない。
- docs/roadmap.md：「LaTeX との差を埋める項目」の「前付けのノンブルとページラベル」の項目を消す。v1.0.0 の「ページ番号と柱の拡張」から「ノンブルの書式を目次と索引のページ番号に使うこと、」と「前付けのローマ数字のノンブルと、前付けと本文でのページ番号の振り直し、」を消す。残るのは「EPUB の `page-list`、柱とノンブルと目次の項目を見出しの書体で組むこと、柱、ノンブル、罫線、図版の色」である。

## 実装しないこと

- **原稿の中のセクションの開始**：ファイルの途中から番号を変える記法（LaTeX の `\pagenumbering` を本文に書く形）は作らない。前付け、本文、後付けの境はファイルの境と一致するからである。
- **接頭辞**：InDesign のセクションの接頭辞（`A-1` の `A-`）と、マニュアルに多い章ごとの番号の接頭辞（JLReq の 2.6.3）は扱わない。`PageLabel` に欄を足せば後から加えられ、PDF の `/P` も使える。
- **逆ノンブル**：縦組みの本の巻末の横組みの部分の逆ノンブル（JLReq の 2.6.3）は、v2 以降の「縦組みの本の中の横組みの部分」に残す。
- **EPUB の `page-list`**：v1.0.0 の「ページ番号と柱の拡張」に残す。
- **diagnostics のページの位置**：diagnostics の事実（`pdf-pages`）、`pages.json`、プリフライトの報告のページは、今と同じく通し番号のままとする。PDF のビューアーとツールが示すページの位置と同じ数だからである。
- **目次の予約の幅**：ページラベルの表記に合わせて予約の幅を変えることはしない。予約が実際のページによらないことが、目次の収束の前提である（[golem-driver ADR 0009](../golem-driver/adr/0009-pdf-toc-page-numbers.md)）。

## 不変条件

ページの列を p = 1 … N、ページラベルを L(p) と書く。

- **I1 偶奇**：どのページ p でも、L(p) の番号と p の偶奇は等しい。
- **I2 続く番号**：p がセクションの最初のページでなければ、L(p) の番号は L(p − 1) の番号に 1 を足した数であり、L(p) の表記は L(p − 1) の表記と同じである。
- **I3 セクションの始まり**：p が `start` を持つセクションの最初のページなら、L(p) の番号は `start` である。`start` のないセクションの最初のページなら、L(p − 1) の番号に 1 を足した数（p = 1 なら 1）である。
- **I4 書かない本は変わらない**：`page-numbering` を書かない本では、どの p でも L(p) = (p, p, 表記なし) であり、PDF のバイト列と diagnostics は今と同じである。
- **I5 書き方は一つ**：ページ p を指す相互参照、目次の項目、索引とチャネルの一覧のページ番号の inline は、どれも `pageLabelInlines` の L(p) に対する値に等しい。表記を書かない `{n}` のノンブルの文字列は、L(p) の表記で書いた L(p) の番号に等しい。
- **I6 PDF のページラベル**：書いた `/PageLabels` を ISO 32000-1 の 12.4.2 の規則で読むと、どのページ位置 i（0 から）のラベルも、L(i + 1) を表記で書いた文字列（表記なしは算用数字）に等しい。I4 の本では `/PageLabels` を書かない。
- **I7 改ページ**：`page-numbering` を持つファイルの最初のブロックは、そのセクションの最初のページか、それより後のページに置かれる。前のファイルのブロックは、そのセクションの最初のページより前のページにだけ置かれる。
- **I8 ページのないセクション**：G07109 は、ページを持たないセクションごとにちょうど一つ出る。ページを持つセクションには出ない。
- **I9 隠しノンブルは通し番号**：隠しノンブルを入れるどのページ p でも、隠しノンブルの文字列は p を算用数字で書いたものであり、`page-numbering` の有無とセクションの表記と番号によらない。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| セクションの数 | 0、1（最初のファイル）、1（途中のファイル）、2、3 |
| `start` | 省く、1、2、3、3999、4000（`upper-roman` で書けない） |
| 前のセクションのページ数 | 0、1（奇数）、2（偶数） |
| セクションの改ページの前のページ | 空で奇数、空で偶数、空でなく奇数、空でなく偶数 |
| ファイルの最初のブロック | 段落、`page-break = "recto"` の見出し、何もない（空のファイル） |
| 続くセクション | 二つのファイルが続けてどちらも `page-numbering` を持ち、前のファイルが空 |
| 表記 | なし、`arabic`、`lower-roman`、`kanji`、`circled`（50 ページと 51 ページ） |
| 組方向 | 横組み、縦組み |
| 本の終わり | 最後のファイルが空で `page-numbering` を持つ |
| 隠しノンブル | 前付けの最後のページ、本文のセクションの最初のページ、セクションの改ページが作った白ページ |

## テスト設計

テストの名前に不変条件の番号を入れる。

- golem-layout の `PaginateInvariantsSpec` に、[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md) の要素の列にセクションの開始（`start` が省く、1、2）を足し、要素の少ない順にすべて組んで I1、I2、I3、I7 の述語が違反を返さないことを確かめる。
- golem-layout の単体のテストで、上の表の「セクションの改ページの前のページ」の四つと「ファイルの最初のブロック」の三つの組について、最初のページと白ページの位置を確かめる（I1、I3、I7）。
- golem-typeset のテストで、前付けを `lower-roman`、本文を `start = 1` にした本の目次、索引、`[ref-page]`、ノンブルの文字列が `pageLabelInlines` の値と一致することを確かめる（I5）。縦組みでは表記なしのラベルが `[numbers]` の表記になることも確かめる。
- golem-typeset のテストで、`page-numbering` のない本の PDF が今の PDF とバイト列で等しいことを、golem-driver の fixture のすべてで確かめる（I4）。
- golem-pdf のテストに、数の木を読んでページ位置ごとのラベルを返す小さな読み手を置き、セクションの組（表記なし、`R`、`r`、`/P` だけ、混在）について I6 を確かめる。
- golem-typeset のテストで、G07109（後のセクションが同じページから始まる場合と、本が終わる場合）と G07110（`circled` の 51 ページ）を確かめる（I8）。
- golem-project のテストで、G03121、G03122、G02103（`start = -1`）、G03123、未知のキーの G03001 を確かめる。
- golem-typeset のテストで、前付けを `lower-roman` にし、本文を `start = 1` にした本をトンボ付きで組み、上の表の「隠しノンブル」の三つのページの隠しノンブルが通し番号であることを確かめる（I9）。
- golem-driver のテストで、「マニュアルで試すこと」の設定にした使い手のマニュアルが diagnostics のエラーなく組め、`/PageLabels` の範囲が前付けの `/S /r` と第 1 章からの `/S /D` の二つであることを確かめる。マニュアルの golden は、この変更に合わせて更新する。

テストは実装の前に書き、今のコードで落ちることを確かめる。
I4 のテストだけは今のコードでも通る。

## トレードオフ

- セクションをマニフェストに書くので、原稿だけを読んでもノンブルの変わり目がわからない。マスターページも同じくマニフェストで決めており、本の構成はマニフェストにまとまる。
- `page-numbering` を書くと、改ページを暗に入れる。改ページを入れない設定は作らない。セクションの境がページの途中に来ると、そのページの番号が決まらないからである。
- 表記を決めたラベルは文字列として組むので、縦組みの `[numbers] ref-page` の `sideways` などの指定は適用されない。前付けの横組みのローマ数字を縦組みの本文から参照する場面は少ないと見て、表記を決めた側を優先した。
- `/PageLabels` の `/P` だけの範囲はページの数だけ増える。`kanji` の前付けが数十ページなら、数十の小さな辞書である。

## メンテナーが決めること

1. **セクションを書く場所**
   - 推奨：マニフェストの章の項目の `page-numbering`。本のどの部分が前付けかは構成の情報で、マスターページの指定と同じ所にある。InDesign のブックのドキュメントごとの番号の設定に当たる。
   - 退けた案：原稿のブロックコマンド（`@page-numbering style=lower-roman`）。LaTeX の `\pagenumbering` に近いが、ファイルの途中に書くとセクションの最初のページが段落の位置から決まらず、記法を足すことになる。
   - 退けた案：`style.toml` のマスターページに番号の振り直しを書く。マスターページは離れたファイルが共有するので、どこで数え直すかが決まらない。
   - 退けた案：マニフェストを `front-matter`、`chapters`、`back-matter` の三つの配列に分ける（LaTeX の `\frontmatter` に近い）。部分が三つに固定され、口絵や付録を別に数える本を書けない。
2. **セクションの前の改ページ**
   - 推奨：`start` の偶奇で改丁か偶数ページへの改ページを暗に入れる。LaTeX の `\mainmatter` の `\cleardoublepage` と同じく、表の側を奇数にする（JLReq の 2.6.2）。
   - 退けた案：改ページを入れず、番号と左右の偶奇が食い違えばエラーにする。前付けのページ数が変わるたびに利用者が改ページを直すことになる。
   - 退けた案：InDesign のように番号の偶奇でページの左右を入れ替える。Golem の左右は通し番号で決まり、柱、隠しノンブル、ノドの位置のすべてに関わる。
3. **`style` に書ける値**
   - 推奨：登録表のすべての名前。書けない番号は G07110 とする。表記は一つの表にまとめ、足すときは表に一行を足すという [ADR 0177](0177-note-mark-style-and-numerals.md) の方針に合う。
   - 退けた案：`arabic`、`lower-roman`、`upper-roman` の三つに絞る。和文の前付けを漢数字にする本が書けない。
4. **`arabic` の扱い**
   - 推奨：表記を決めない数と同じにする。縦組みの本の参照と目次は今と同じく `[numbers]` の表記になる。
   - 退けた案：算用数字に固定する。縦組みの本で `style = "arabic"` と書くと、目次のページ番号が漢数字から算用数字に変わる。
5. **目次、索引、相互参照に出すもの**
   - 推奨：セクションの表記と番号だけ。
   - 退けた案：マスターページの `folio` の `format` の全体。飾りの `-` が目次に入り、ファイルごとにマスターページが違うとどれを使うかが決まらない。
6. **`/PageLabels` を書く条件**
   - 推奨：ページラベルが今の番号と違う本だけに書く。今の本の PDF のバイト列を変えない。
   - 退けた案：いつも書く。すべての本の PDF が変わり、ビューアーの表示は変わらない。
7. **G07109 の重大度**
   - 推奨：警告。ページを持たないセクションは出力を変えず、書いた設定が働いていないことを知らせれば足りる。
   - 退けた案：エラー。最後のファイルを一時的に空にしただけでビルドが止まる。

## 決めたことの記録

2026-11-09 に、tett23 が次のとおり決めた。

1. セクションは、推奨のとおりマニフェストの章の項目の `page-numbering` に書く。
2. セクションの前の改ページは、推奨のとおり `start` の偶奇で改丁か偶数ページへの改ページを暗に入れる。
3. `style` には、推奨のとおり登録表のすべての名前を書ける。
4. `arabic` は、推奨のとおり表記を決めない数と同じに扱う。
5. 目次、索引、相互参照には、推奨のとおりセクションの表記と番号だけを出す。
6. `/PageLabels` は、推奨のとおりページラベルが今の番号と違う本だけに書く。
7. G07109 は、推奨のとおり警告とする。
8. 隠しノンブルは、前付けと本文を通した番号とする。草案は、隠しノンブルを今と同じ通し番号のままにすると書いていた。この決定はその振る舞いを変えず、明示した。不変条件の I9 と、そのテストを足した。
9. 実装のプルリクエストで、使い手のマニュアルの「はじめに」を小文字のローマ数字のノンブルで組めるかを試す（「マニュアルで試すこと」）。
10. diagnostic のコードは、採択のときに使われていない番号を確かめ、G03121、G03122、G03123、G07109、G07110 とした。草案の仮の番号と同じである。

## 参考文献

- [2026-10-17 の調査](../audits/2026-10-17-latex-gap-for-v1.md)（6 と「所有者の決定」）
- [ロードマップ](../roadmap.md)
- [仕様書](../specifications.md)
- [ADR 0102](0102-natural-number-type.md)、[ADR 0118](0118-ref-page-numerals-in-vertical-text.md)、[ADR 0174](0174-compatibility-promises-for-1-0.md)、[ADR 0177](0177-note-mark-style-and-numerals.md)、[ADR 0183](0183-tagged-pdf-and-pdf-a.md)、[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md)、[ADR 0213](0213-numbers-the-number-formats-cannot-write.md)、[ADR 0251](0251-reuse-the-compositions-of-unchanged-units-between-fixpoint-rounds.md)
- [golem-driver ADR 0007](../golem-driver/adr/0007-pdf-index-and-bibliography.md)、[golem-driver ADR 0009](../golem-driver/adr/0009-pdf-toc-page-numbers.md)、[golem-driver ADR 0014](../golem-driver/adr/0014-running-heads.md)、[golem-driver ADR 0021](../golem-driver/adr/0021-hidden-folios.md)、[golem-driver ADR 0022](../golem-driver/adr/0022-running-head-formats.md)
- [golem-layout ADR 0003](../golem-layout/adr/0003-pagination-and-s2.md)
- W3C, Requirements for Japanese Text Layout（JLReq）, 2.6.1、2.6.2、2.6.3, https://www.w3.org/TR/jlreq/#running_heads_and_page_numbers（2026-11-09 に本文を読んで確かめた）
- Adobe, InDesign User Guide, Document numbering options, https://helpx.adobe.com/indesign/desktop/create-and-organize-pages/page-numbers-chapters-and-sections/document-numbering-options.html（本文は読めず、調査の抜粋による。セクションのノンブルが PDF のページラベルになるかは確かめていない）
- LaTeX2e unofficial reference manual, `\pagenumbering`, `\frontmatter`, `\mainmatter`, https://latexref.xyz/
- hyperref の `pdfpagelabels`, https://ctan.org/pkg/hyperref
- ISO 32000-1:2008, 7.9.7 Number Trees、12.4.2 Page Labels
