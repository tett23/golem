# ADR 0045: 本文の中のコードの `-` と `.` の後でも改行し、字間の空いた行を減らす

ステータス: 採択→表のセルの最小の幅、G09013 の文、J5 の確かめ方は [ADR 0255](../../adr/0255-record-what-implementations-decided-on-2026-11-09.md)

## 文脈

### 開発者のマニュアルで、字間の大きく空いた行が出た

開発者のマニュアルのリリースの章に、次の文を書いた（[`13-release.gm`](https://github.com/tett23/golem/blob/ae65401bf45d32994d99f4e99ee2bedfcb0f24d7/manual-dev/part2/13-release.gm#L112)）。

```
実行ファイルのアーカイブ（[code: golem-*.tar.gz]）には、[code: actions/attest-build-provenance] で来歴の証明を付ける。
```

組むと、段落の一行めが「実行ファイルのアーカイブ（golem-*.tar.gz）には、actions/⏎」で終わり、その行の和文の字のあいだが一字近く空いた。
語順を入れ替えた版（[`e10bc3f5`](https://github.com/tett23/golem/blob/e10bc3f5dde39ebe59100679fa348f8f46a61a24/manual-dev/part2/13-release.gm#L112)）でも、一行めの字間が空いた。
[#760](https://github.com/tett23/golem/pull/760) は文を二つに分けて避けたが、組版の側は何も変わっていない。

### 再現と測り方

origin/main の `9472163b` で golem を作り（golem-layout と golem-typeset は `b9803a0e` と同じ）、開発者のマニュアルの `style.toml`（B5、13Q、40 字詰め、`hanging-punctuation = true`）と同じ設定の小さな本に、元の文の段落と語順を入れ替えた段落を置いて組んだ（2026-11-09）。
行の伸び縮みは、`breakParagraph` の結果の各行の `lineRatio` を、環境変数で標準エラーに書き出す試作で読んだ（コミットしていない）。
和文の字のあいだのグルーは、幅 0、伸び 1/10 em、縮み 0 である（[`Aki.hs`](https://github.com/tett23/golem/blob/b9803a0e8191f09408b6f6f7c4a624b58345c085/modules/golem-layout/src/Golem/Layout/Aki.hs#L100)）。
`lineRatio` が r なら、和文の字のあいだは r/10 em 空く。

| 段落 | 一行め | `lineRatio` | 和文の字のあいだ | 段階（`brPass`） |
| --- | --- | --- | --- | --- |
| 元の文 | `…（golem-*.tar.gz）には、actions/` | 7.58 | 0.76 em | 4 |
| 語順を入れ替えた文 | `actions/attest-build-provenance で、実行ファイルのアーカイブ` | 5.70 | 0.57 em | 4 |

### なぜ空いた行を選ぶか

コードの欧文の字のあいだで改行できるのは、空白、`/` の後、`_` の連なりの後だけである（[golem-driver ADR 0017](../../golem-driver/adr/0017-pdf-code-blocks.md)、[golem-layout ADR 0031](0031-line-breaks-after-low-lines-in-identifiers.md)、[golem-layout ADR 0034](0034-line-breaks-between-japanese-characters-in-inline-code.md)、[`codeItems`](https://github.com/tett23/golem/blob/b9803a0e8191f09408b6f6f7c4a624b58345c085/modules/golem-layout/src/Golem/Layout/Japanese.hs#L979-L1003) と [`normalize`](https://github.com/tett23/golem/blob/b9803a0e8191f09408b6f6f7c4a624b58345c085/modules/golem-layout/src/Golem/Layout/Japanese.hs#L1252-L1258)）。
`actions/attest-build-provenance` の中の候補は `actions/` の後の一つだけで、`attest-build-provenance` の 23 字は分けられない。
一行めは、`actions/` の前で終えるか後で終えるかしかない。
後で終えても行長に 7.6 字分ほど足りず、その行で伸びる和文の字のあいだは 10 か所、合わせて 1 字分しかない。
語順を入れ替えた文でも、`golem-*.tar.gz` に候補がないので、`（` の前で終えるしかない。

行分割は四つの段階で進む（[`breakParagraph`](https://github.com/tett23/golem/blob/b9803a0e8191f09408b6f6f7c4a624b58345c085/modules/golem-layout/src/Golem/Layout/KnuthPlass.hs#L279-L294)）。
不良度は TeX と同じく約 100 r³ であり、既定の `tolerance` 200 で許す r はおよそ 1.26 までである。
既定の `emergency-stretch` は 0 なので、三つめの段階は飛ばす（[`defaultComposition`](https://github.com/tett23/golem/blob/b9803a0e8191f09408b6f6f7c4a624b58345c085/modules/golem-project/src/Golem/Project/Style.hs#L1343)）。
最後の段階は、行長に収まる分割がなくなった位置で、収まらない箱を次の行へ送り出し、その前のいちばん後ろの候補で行を終える（[`pushOut`](https://github.com/tett23/golem/blob/b9803a0e8191f09408b6f6f7c4a624b58345c085/modules/golem-layout/src/Golem/Layout/KnuthPlass.hs#L360-L369)）。
仕様書の「行分割」の節は、この振る舞いを JLReq の追い出しとして定め、長いインラインのコードを次の行の先頭に置く例まで挙げている（[docs/specifications.md](../../specifications.md)）。
空いた行は仕様のとおりの出力であり、原因は改行の候補の少なさにある。

### `tolerance` と `emergency-stretch` では直らない

二つのマニュアルの `style.toml` の `[composition]` に値を足して組み、「頻度」の節と同じ数え方で比べた（コミットしていない）。

| 設定 | 利用者のマニュアル（r > 2.5） | 開発者のマニュアル（r > 2.5） |
| --- | --- | --- |
| 今の既定 | 229 | 73 |
| `tolerance = 1600` | 229 | 73 |
| `emergency-stretch = "3zw"` | 275 | 152 |

`tolerance` を 1600（r がおよそ 2.5 まで）にしても、数は一つも変わらなかった。
空いた行は、許容度の範囲に分割がなく最後の段階で送り出した行であり、許容度を上げてもその範囲に入らない。
`emergency-stretch` は、三つめの段階で各行に伸びを足して不良度を量る。
和文の字のあいだの伸びは一字 1/10 em と小さいので、3 字分の伸びを足すと多くの行が許容度に入り、空いた行は逆に増えた。

### TeX の振る舞い

TeX Live 2026 の Docker のイメージ（`texlive/texlive:latest`、ID `07e806263724`）で、pLaTeX と jsarticle で 40 字の行に同じ文を組んだ（2026-11-09、観察）。
jsarticle の既定は `\tolerance` 200、`\emergencystretch` 3zw であり、`\kanjiskip` は 0pt plus 0.92473pt（約 1/10 字）であった。

| 書き方 | 結果 |
| --- | --- |
| `\texttt` | 一行めに `actions/attest-build-provenance` の全体を入れ、17.75pt はみ出した（Overfull \hbox） |
| `\url`（url 3.4） | 同じく 19.25pt はみ出した |
| `\texttt`、語順を入れ替えた文 | 10.81pt はみ出した |
| `\usepackage[hyphens]{url}` の `\url` | `attest-` と `build-` の後に候補ができ、一行めを `actions/attest-build-` で終えた（不良度 9）。はみ出しも空いた行もない |

TeX は、許容度の範囲に分割がなければ、最後の段階で行長からはみ出す行を作る。
Golem は、行長に収まる分割の候補がある限りはみ出す行を作らないので（[docs/adr/0210](../../adr/0210-warn-overfull-lines-in-build.md)）、同じ入力で空いた行になる。
url パッケージは、`hyphens` のオプションを付けたときだけ `-` の後で改行する。
Golem の文字スタイル `url` は、url パッケージの既定の `\UrlBreaks` と `\UrlBigBreaks` の字の後で改行し、`-` の後では改行しない（[golem-layout ADR 0018](0018-url-line-breaks.md)、[`urlBreakChars`](https://github.com/tett23/golem/blob/b9803a0e8191f09408b6f6f7c4a624b58345c085/modules/golem-layout/src/Golem/Layout/Japanese.hs#L1021-L1022)）。

### InDesign と JLReq

InDesign で同じ文を組んで確かめてはいない。
InDesign の振る舞いがわからないときは JLReq に従う（メンテナーの規則）。

JLReq の 3.8（行の調整処理）は、詰める処理（追込み）を優先し、詰められないときに空ける処理（追出し）を行うとする。
空ける処理の順は次のとおりである（3.8.4、JIS X 4051 の規定として）。

1. 欧文間隔を、最大で二分まで空ける。
2. 和文と欧文のあいだの四分アキを、最大で二分（または三分）まで空ける。
3. 1 と 2 のほかの、空けてよい字間を、最大で四分まで空ける。
4. 1 から 3 で調整できなければ、分割禁止でない字間を均等に空ける。欧文用文字の字間を含めるかは処理系定義とする。

JLReq は、和文の字のあいだを四分までは通常の調整とみなし、それを超える空きは 4 の最後の手段とする。
再現の二つの行は 0.57 em と 0.76 em で、4 に当たる。
3.1.12 の図の例（[行の調整処理例](https://www.w3.org/TR/jlreq/#examples_of_line_adjustment)）も、追い出しで一行めの字間を空ける。
ただし、その例で空けるのは送り出した一字の分であり、9 字分を空けることは想定していない。

JLReq は、欧文用文字（cl-27）どうしのあいだを分割不可とし、ハイフネーションでだけ分ける（付録 C の注、[C.2](https://www.w3.org/TR/jlreq/#notes_a3)）。
コードの中の改行について定める節はない。
コードの欧文の並びをどこで分けるかは、JLReq からは決まらず、TeX の url パッケージと Golem の今の規則（`/` の後と `_` の後）にならう。

### 頻度

二つのマニュアルを試作の golem で組み、段落の最後の行と両端を揃えない段落の行とはみ出す行を除いたすべての行の `lineRatio` を数えた。
行の字と `lineRatio` の組で重複を除いた（同じ段落を同じ幅で組み直した行を一度に数える）。
表、注、キャプション、索引の行も含む。

| 数えた行 | 利用者のマニュアル（376 ページ） | 開発者のマニュアル（217 ページ） |
| --- | --- | --- |
| 行の数 | 4,924 | 3,150 |
| r > 1（和字間が伸びの限度の 1/10 em を超える） | 448（9.1%） | 176（5.6%） |
| r > 2.5（和字間が JLReq の 3 の限度の四分を超える） | 229（4.7%） | 73（2.3%） |
| r > 5（和字間が二分を超える） | 122 | 30 |
| r > 2.5 のうち、行末の箱か次の行の最初の箱がコード | 209 | 47 |
| r > 2.5 のうち、最後の段階の行 | 229 | 73 |

r > 2.5 の行はすべて最後の段階で送り出した行であり、利用者のマニュアルでは 9 割、開発者のマニュアルでは 6 割がコードの前後で分けた行であった。
利用者のマニュアルの 229 のうち 85 は、付録 E の項目の見出し（`G03117 [code: \[notes\] の mark-size は…]`）の行である。
見出しはコードの識別子とコードのメッセージだけでできており、伸びるグルーがあいだの空白一つしかない。
付録 E の本文にも、「段落スタイル caption か sidenote に」の字のあいだが大きく空いた行がある（318 ページ）。

### 試作

`codeItems` と `normalize` に、コードの欧文の並びの中の候補を足す試作を作った（コミットしていない）。

- A：`-` と `.` の連なりの後に候補を置く。空白で区切ったコードの最初と最後の連なりの後には置かない（[golem-layout ADR 0031](0031-line-breaks-after-low-lines-in-identifiers.md) の `_` と同じ）。罰点は 100、改行の印は `/` の後と同じく描く。
- A′：A の字に、`url` の `\UrlBreaks` の残りの字（`@!|;>]),?&+=#:`）を足す。
- A＋どこでも：A に加え、コードの欧文の字のどのあいだにも罰点 1000 の候補を置く（CSS の `overflow-wrap: anywhere` に当たる最後の手段）。

| 試作 | 再現の一行め | 利用者（r > 2.5、r > 5） | 開発者（r > 2.5、r > 5） |
| --- | --- | --- | --- |
| 今 | 上の表 | 229、122 | 73、30 |
| A | 元の文 `…には、actions/attest-build-⏎`（r = −0.15、段階 1）、入れ替えた文 `…アーカイブ（golem-⏎`（r = 0.34、段階 1） | 163、90 | 54、21 |
| A′ | A と同じ | 158、88 | 51、18 |
| A＋どこでも | A と同じ | 93、54 | 21、11 |

A は再現の二つの段落をともに最初の段階で組み、二つのマニュアルの空いた行を約 3 割減らした。
A′ は A より数行しか減らさなかった。
A＋どこでもは、さらに半分近くに減らすが、`attestation` のような語を任意の字のあいだで分ける。

A の後に残る空いた行は、主に次の三つである。

- 付録 E の項目の見出し（85）。コードの中に伸びるグルーがなく、識別子とコードのあいだの空白一つにすべての空きが寄る。
- 脚注と参考文献の URL（文字スタイル `url`）。`-` の後で改行しない。
- 表の狭いセルの行。

A で、利用者のマニュアルの 376 ページのうち 195 ページ、開発者のマニュアルの 217 ページのうち 109 ページの画像が変わった（shem で 40 dpi に描いて比べた）。
ページの数は変わらなかった。

## 実装すること

### 1. コードの `-` と `.` の連なりの後に、候補を置く（golem-layout）

文字スタイル `code`（`lkCode` が真で `lkUrl` が偽の見た目）の空白で区切った並びの中で、`-` と `.` の連なりの後に、分割の候補を一つ置く。
連なりは、`-` か `.` が一字以上続いたものとする（`--`、`...`、`-.` も一つの連なり）。
次のすべてに当たるときだけ置く。

- 連なりの前に、同じ並びの字がある（並びの最初の連なりではない）。`-n`、`--target`、`.wasm` の後では改行しない。
- 連なりの後に、同じ並びの字がある（並びの最後の連なりではない）。`foo.`、`a-` の後では改行しない。
- 連なりの前の字と後の字が、どちらも欧文の字であり、`/` でも `_` でもない。
- 連なりの前の字と後の字が、ともに数字（`0` から `9`）ではない。`1.0.0`、`0.5zw`、`2026-11-09` の数字のあいだでは改行しない。

後の字が和文の字のところは [golem-layout ADR 0034](0034-line-breaks-between-japanese-characters-in-inline-code.md) の候補（禁則に当たらなければ罰点 0 の一つ）のままとし、この候補を重ねない。
`/` と `_` の後の候補も今のままとする。

候補の罰点は 100 とする（`_` の連なりの後と同じ）。
候補は [golem-layout ADR 0034](0034-line-breaks-between-japanese-characters-in-inline-code.md) の空白でないコードの候補と同じく、改行した行の行末に `wrap-mark` を描き、その幅を罰点の項目の幅に含める（[golem-layout ADR 0036](0036-record-what-the-implementation-of-0034-decided.md)、[golem-layout ADR 0042](0042-draw-the-wrap-mark-of-inline-code-small-and-light.md)）。
`wrap-mark = ""` なら印を描かず、幅は 0 である。
ハイフンは足さない。
`-` は字のまま行末に残るので、改行の印が、書いたハイフンと改行のためのハイフンの区別を受け持つ。
候補は分綴のパターンの候補ではないので、最初の段階から使う。

`codeItems` は、この候補の位置でもコードの欧文の並びを箱に分ける。
箱の幅は今のとおり、各部分の `ceWordAdvance` にトラッキングを足した値とする。

### 2. 変えないもの

- 許容度（`pretolerance` 100、`tolerance` 200）と `emergency-stretch`（0）の既定。「文脈」のとおり、空いた行を減らさないか、増やす。
- 最後の段階の送り出し（JLReq の追い出し）。行長に収まる候補がある限り、はみ出す行は作らない。
- 和文の字のあいだの伸び（1/10 em）。
- 文字スタイル `url` の改行の位置（[golem-layout ADR 0018](0018-url-line-breaks.md)）。
- コードブロックの折り返し。
- HTML と EPUB の `style.css`。

### 3. 列挙の不変条件を広げる

[golem-layout ADR 0034](0034-line-breaks-between-japanese-characters-in-inline-code.md) の 5 で `LineBreakEnum` に足したコードの並びの部品に、`-`、`.`、`1` の三つを足す。
`1` は数字のあいだの除外を作るためである。
プルリクエストの段と毎晩のジョブの段は 0034 のままとし、実装のプルリクエストで時間を測る。
範囲ごとの予算 10 秒（[ADR 0208](../../adr/0208-widen-lightweight-formal-methods.md) の 4）を超えるなら、コードの並びの行の幅を 3 字までにする。
下の J1 から J7 を述語として足し、[ADR 0209](../../adr/0209-line-breaking-invariants-by-exhaustive-small-inputs.md) の L1 から L13 と 0034 の C1 から C8 とともに、すべての入力で確かめる。
0034 の C3 と C4 は、この ADR で J3 と J5 に置き換える。

### 4. 文書

- [docs/specifications.md](../../specifications.md) の文字スタイル `code` の段落の「欧文の字どうしのあいだで改行してよい位置は、空白、`/` の後、`_` の連なりの後に限る」に、`-` と `.` の連なりの後（1 の条件、罰点 100、改行の印）を足し、この ADR へのリンクを付ける。
- 同じく「行分割」の節の、長いインラインのコードを次の行の先頭に置く例の後に、コードの `-` と `.` の後でも改行できるので、そうした長いコードでも前の行が空きにくいことを足す。
- `docs/diagnostics.md` の G07105 と G09013 の主な原因と直し方のうち、コードの改行の位置を挙げる文に `-` と `.` を足す。`scripts/gen-embedded.sh` で `Golem.Driver.Explain.Embedded` を作り直す。
- [TeX と InDesign との差異](../../differences-from-tex-and-indesign.md) の「本文の中のコードの和文の改行」の節に、TeX がはみ出す行を作るところで Golem が空いた行を作ること、コードの `-` と `.` の後で改行することと url パッケージの `hyphens` のオプションとの比べ、この ADR へのリンクを足す。
- [golem-layout ADR 0034](0034-line-breaks-between-japanese-characters-in-inline-code.md) のステータスの行に、C3 と C4 をこの ADR が置き換えたことを足す。[golem-driver ADR 0017](../../golem-driver/adr/0017-pdf-code-blocks.md) と [golem-layout ADR 0031](0031-line-breaks-after-low-lines-in-identifiers.md) のステータスの行に、コードの改行の位置をこの ADR が足したことを書く。
- 開発者のマニュアルのリリースの章の文は、[#760](https://github.com/tett23/golem/pull/760) の分けた形のままとする。元の文に戻すかは、実装の後に書き手が決める。

### 5. 出力の変化

二つのマニュアルの PDF、`scripts/visual/pages/manual.txt` と `manual-dev.txt` の参照、二つのマニュアルの決定性のハッシュが変わる。
試作 A では、ページの数は変わらず、利用者のマニュアルで 195 ページ、開発者のマニュアルで 109 ページの画像が変わった（「文脈」）。
試作は数字のあいだを除いていないので、変わるページはこれより少し減りうる。
実装のプルリクエストで、空いた行の数を「文脈」と同じ方法で数え直し、説明に書く。
golden、complex fixture、kanikosen などのほかの入力も、`-` か `.` を含む本文の中のコードがあれば変わる。

## 実装しないこと

- **コードの欧文のどこででも分ける最後の手段**：「メンテナーが決めること」の 4。
- **許容度と `emergency-stretch` の既定を変えること**：「メンテナーが決めること」の 5。
- **TeX と同じく、空いた行の代わりにはみ出す行を作ること**：「メンテナーが決めること」の 6。
- **コードの中に伸びるグルーを置くこと**：付録 E の項目の見出しの空いた行（85）は、この ADR では直らない。コードの中の空きを決めた [golem-driver ADR 0017](../../golem-driver/adr/0017-pdf-code-blocks.md) と [golem-layout ADR 0034](0034-line-breaks-between-japanese-characters-in-inline-code.md) を変えることになり、別の ADR で決める（「メンテナーが決めること」の 7）。
- **文字スタイル `url` の `-` の後の改行**：`url` は改行の印を描かないので、書いたハイフンと区別できない（「メンテナーが決めること」の 8）。
- **空いた行の報告**：「メンテナーが決めること」の 9。
- **HTML と EPUB**：ブラウザーの `<code>` の改行は UAX #14 による。`-` と `.` の後で改行するかは確かめておらず、この ADR では変えない。
- **ASCII の記号を約物のクラスで扱うこと**：[golem-layout ADR 0034](0034-line-breaks-between-japanese-characters-in-inline-code.md) のとおり、すべて欧文の字とする。

## 不変条件

「並び」は、文字スタイル `code`（`url` でない）の文字列を空白で区切った一つとする。
「区切りの字」は `-` と `.`、「連なり」は並びの中で区切りの字が続いた最も長い部分とする。
「欧文の字」と「和文の字」は [golem-layout ADR 0034](0034-line-breaks-between-japanese-characters-in-inline-code.md) と同じく、区間の言語で決めた字のクラスによる。
「J1 の位置」は、連なりの直後で、連なりの前に字 p、後に字 y が同じ並びにあり、p と y がともに欧文の字で `/` でも `_` でもなく、p と y がともに数字ではない位置とする。

- **J1 候補の位置**：J1 の位置には、分割の候補がちょうど一つある。
- **J2 罰点と印**：J1 の位置の候補は、罰点 100 の `WrapMark` の項目であり、その幅は [golem-layout ADR 0042](0042-draw-the-wrap-mark-of-inline-code-small-and-light.md) の印の幅である。`wrap-mark = ""` では、罰点 100 の幅 0 の `NoHyphen` の項目である。
- **J3 ほかの欧文の字のあいだ**：並びの中で隣り合う二つの欧文の字のあいだの分割の候補は、`/` の後、`_` の連なりの後（[golem-layout ADR 0031](0031-line-breaks-after-low-lines-in-identifiers.md)）、J1 の位置のどれかにだけある。これは 0034 の C3 を置き換える。
- **J4 和文の字との境**：連なりの後の字が和文の字のところには、0034 の C1 と C2 の候補だけがある（候補は高々一つ）。
- **J5 区切りの字を含まない入力**：`-` も `.` も含まない `code` の文字列の項目と、`code` を含まない段落の項目は、この ADR の前と同じである。`url` の文字列の項目も、この ADR の前と同じである。これは 0034 の C4 を置き換える。
- **J6 字を失わない**：`code` の文字列の箱の字をつなぐと、空白を除いた元の文字列になる。J1 の位置で分けた行の終わりには、`wrap-mark` の字がちょうど一つあり、ハイフンを描かず、その行は行長に収まる（0034 の C8）。
- **J7 候補を足しても悪くならない**：同じ項目の J1 の位置の罰点を `infPenalty` に替えた項目（この ADR の前と同じ分割の候補）と比べ、`brPass` は大きくならない。どちらも `brPass` が 2 以下なら、`brDemerits` は大きくならない。

J7 は、候補を足すだけの変更なので、前の最適な分割がそのまま使えることを述語にしたものである。
箱を分けても幅の和は変わらない（トラッキングは字ごと、余白は最初と最後の箱にだけ付く）ことが、この性質の前提である。
最後の二つの段階（送り出しと、はみ出す行を許す段階）は罰点の最小を探す手順ではないので、`brDemerits` を比べない（[ADR 0209](../../adr/0209-line-breaking-invariants-by-exhaustive-small-inputs.md) の L7 と同じ扱い）。

[ADR 0209](../../adr/0209-line-breaking-invariants-by-exhaustive-small-inputs.md) の L1 から L13 との関わりは次のとおりである。

- L1 は、改行の印が箱の字ではないので、J6 とともにそのまま成り立つ。
- L5 と L6 は、印の幅を候補の項目に含めるので、そのまま成り立つ（0036 の N1 から N3）。
- L7 は、J1 の候補も通常の罰点なので、最初の二つの段階でそのまま成り立つ。
- L8 と L9 は、伸縮を受ける地の文の語とパターンの分綴についてのものであり、コードの箱は伸縮を受けないので、空に成り立つ。
- ほかの不変条件は、コードの並びに区切りの字を足しても読み方が変わらない。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 連なりの位置 | 並びの最初（`-n`、`.wasm`、`--target`）、中ほど（`a-b`、`a.b`）、最後（`a-`、`foo.`） |
| 連なりの長さ | 1（`a-b`）、2（`a--b`、`a.-b`）、3（`a...b`） |
| 前と後の字 | 英字、数字（`1.0`、`a1.b`、`1.a`、`2026-11`）、記号（`golem-*`、`*.tar`）、`/`（`a-/b`、`a/-b`）、`_`（`a-_b`、`a_-b`）、`"`（`a."b`） |
| 和文の字との境 | `a-あ`、`あ-a`、`a.。`（行頭禁則）、`a-（`（後が始め括弧） |
| 並びの数 | 一つ、空白で区切った二つ（`a-b c.d`） |
| `wrap-mark` | 既定、`""` |
| 行の残りの幅 | 連なりの後でちょうど終わる、印の幅だけ足りない、連なりの前で終わる |
| 組方向 | 横組み、縦組み |
| 区間の言語 | なし、`en`、`ja` |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
テストの名前には、J1 から J7 の番号を入れる。

- **J1**：`[code: attest-build-provenance]` の項目が、`attest-`、罰点 100 の候補、`build-`、罰点 100 の候補、`provenance` の箱になること。今は箱一つなので失敗する。`[code: golem-*.tar.gz]` の `golem-` の後、`*.` の後、`tar.` の後に候補が一つずつあること。今は候補がないので失敗する。
- **J1 の除外**：`[code: -n]`、`[code: --target]`、`[code: .wasm]`、`[code: foo.]`、`[code: a-]`、`[code: 1.0.0]`、`[code: 0.5zw]` の `0.5` のあいだ、`[code: 2026-11-09]` に、J1 の候補がないこと。`0.5` は `.` の前と後がともに数字なので候補がない。`[code: a1.b]` と `[code: 1.a]` には候補が一つあること。`[code: a--b]` と `[code: a...b]` は、連なりの後にだけ候補が一つあること。
- **J2**：J1 の候補が `WrapMark` を持ち、幅が `/` の後の候補と同じであること。`wrap-mark = ""` の文字スタイルでは、幅 0 の `NoHyphen` であること。
- **J3**：`[code: abc"def]`、`[code: a:b]`、`[code: a=b]` に候補がないこと。`[code: a/-b]` は `/` の後の候補だけ、`[code: a-/b]` は `/` の後の候補だけを持つこと。
- **J4**：`[code: a-あ]` の `-` の後の候補が罰点 0 の一つだけであること。`[code: a.。]` の `.` の後に候補がないこと。
- **J5**：[golem-layout ADR 0018](0018-url-line-breaks.md)、[golem-layout ADR 0031](0031-line-breaks-after-low-lines-in-identifiers.md)、[golem-layout ADR 0034](0034-line-breaks-between-japanese-characters-in-inline-code.md) の今のテストのうち、`code` に `-` も `.` も含まないものが、変えずに通ること。地の文の `lime-tree` の項目が変わらないこと。
- **J6**：4 字の行に `[code: aaaa-bbbb.cccc]` を組み、行が `aaaa-`、`bbbb.`、`cccc` に分かれ、最後の行のほかの行末に印が一つずつあり、どの行も `lineOverflow` が 0 で、行の字をつなぐと元の文字列になること。今は一行ではみ出すので失敗する。
- **再現**：テストの送りの表で、和文の字と `[code: aaaaaaa/aaaaaaaaaaaa-aaaaaaaaaa]` を、今の実装では一行めが最後の段階で送り出されて r > 2.5 になる行の幅で組み、この ADR の後は `brPass` が 2 以下で、最後の行のほかのどの行も r ≤ 1 になること。字の数と行の幅は実装の最初に決め、今の実装で失敗することを確かめる。
- **J7**：述語に、J1 の位置の罰点を `infPenalty` に替えた項目より `brPass` が大きい出力を手で作って渡すと、J7 だけが違反を返すこと。列挙では、コードの並びのすべての入力でこの比べを行う。
- **列挙**：3 の部品で、L1 から L13、C1、C2、C5 から C8、J1 から J7 が、プルリクエストの段のすべての入力で成り立つこと。
- **二つのマニュアル**：実装のプルリクエストで、二つのマニュアルを組み、「文脈」の数え方で r > 2.5 の行が試作 A と同程度（利用者 163、開発者 54 の前後）に減ることを確かめ、説明に書く。手で確かめる項目であり、自動のテストにはしない。

## トレードオフ

`-` と `.` の後で改行すると、識別子やファイル名が二行に分かれる。
`attest-build-⏎provenance` は、改行の印がなければ、書いたハイフンなのか改行のためのハイフンなのかを読み手が決められない。
コードは改行の印を描くので区別できるが、`wrap-mark = ""` にした本では区別できない。
その本では、`/` と `_` の後の改行と同じく、書き手がそれを受け入れたものとする。

`.` の後で改行すると、`golem.toml` が `golem.⏎toml` に、`Golem.Layout.Japanese` が `Golem.Layout.⏎Japanese` に分かれる。
罰点 100 は `_` の後と同じで、ほかに行を空けずに済む分け方があれば選ばれにくい。
数字のあいだを除くので、版の番号と日付は分かれない。
数字と英字のあいだ（`v1.0.0-rc4` の `-` の後）は分かれうる。
`.` の後に `)` や `"` が続く並び（`foo.)`）でも分かれ、閉じる記号が行頭に来る。
ASCII の記号をすべて欧文の字とした [golem-layout ADR 0034](0034-line-breaks-between-japanese-characters-in-inline-code.md) の判断と同じく、記号ごとの禁則は持たない。

コードの中の改行が増えると、行の並びが大きく変わる。
試作では、二つのマニュアルの半分ほどのページの画像が変わった。
空いた行を減らす代わりに、見た目の回帰テストと決定性のハッシュの更新が大きくなる。

この ADR の後も、空いた行は残る。
利用者のマニュアルで r > 2.5 の行は 229 から約 163 に減るだけで、半分は付録 E の見出しのように、コードの中に伸びがないことによる。
JLReq の 3.8.4 の 4 は、分割禁止でない字間を均等に空けるとするので、コードの和文の字のあいだも空ける対象になりうる。
それを入れるかは、コードの中に空きを入れないとした [golem-driver ADR 0017](../../golem-driver/adr/0017-pdf-code-blocks.md) と衝突するので、別の ADR で決める。

TeX と違い、Golem は空いた行を作り、はみ出す行を作らない。
TeX の利用者は、Overfull \hbox の警告で書き直す場所を知るが、Golem の空いた行は警告を出さない。
空いた行は、PDF を見るまで気付かない。

## メンテナーが決めること

1. **候補を足す字**：推奨は `-` と `.` である。識別子、ファイル名、モジュールの名前、パッケージの名前に最も多い区切りであり、試作 A で空いた行を約 3 割減らした。
   - 退けた案の一つは、url パッケージの `\UrlBreaks` の字をすべて足すこと（試作 A′）である。A より数行しか減らず、`)`、`,`、`:` の後のように閉じる記号の後でない位置でも分かれる。
   - もう一つは、`-` だけにすることである。`golem-*.tar.gz` のようなファイル名で `.` の後に候補がなく、`.toml` や `.gm` を含む語が残る。
2. **罰点**：推奨は 100 である。`_` の連なりの後（[golem-layout ADR 0031](0031-line-breaks-after-low-lines-in-identifiers.md)）と同じで、識別子の中の分け目を、`/` の後（0）より選ばれにくくする。
   - 退けた案は、地の文の明示のハイフンの `explicit-hyphen-penalty`（既定 50）に合わせることである。地の文の語の分け方であり、コードの分け目とは別の値である。設定を足すことにもなる。
3. **数字のあいだ**：推奨は、前と後がともに数字の位置を除くことである。版の番号（`1.0.0`）、大きさ（`0.5zw`）、日付（`2026-11-09`）を分けない。
   - 退けた案は、除かないことである。数の途中で分かれると、読み手が数を読み違える。
4. **どこででも分ける最後の手段**：推奨は入れないことである。試作の A＋どこでもは空いた行を A からさらに半分近くに減らしたが、`attestation` を `attes⏎tation` のように任意の字で分け、[golem-layout ADR 0034](0034-line-breaks-between-japanese-characters-in-inline-code.md) が退けた案と同じになる。
   - 退けた案は、罰点 1000 ほどの候補をコードの欧文の字のすべてのあいだに置くことである。
5. **許容度と `emergency-stretch` の既定**：推奨は変えないことである。`tolerance` 1600 では数が変わらず、`emergency-stretch` 3zw では空いた行が増えた（「文脈」）。
6. **TeX と同じく、はみ出す行を作るか**：推奨は作らないことである。仕様書は行長に収まる候補がある限りはみ出す行を作らないと定め、はみ出す行は G07105 の警告になる（[docs/adr/0210](../../adr/0210-warn-overfull-lines-in-build.md)）。マニュアルは警告なしで組むことを求めている。
7. **付録 E の見出しのような、コードの中に伸びがない行**：推奨は、この ADR の後に別の ADR で扱うことである。利用者のマニュアルの空いた行の約半分であり、JLReq の 3.8.4 の 4 に従ってコードの和文の字のあいだを空けるか、見出しの組み方（左揃え）を変えるかを比べる必要がある。
8. **文字スタイル `url` の `-` の後**：推奨は変えないことである。`url` は改行の印を描かないので、書いたハイフンと区別できない。url パッケージも、既定では `-` の後で改行しない。
9. **空いた行の報告**：推奨は、この ADR では足さないことである。既定のまま組んでも空いた行が少ない出力にすることを先にする。報告を足すなら、`golem preflight` の検査（たとえば `loose-lines`）にし、`r` の閾値を 2.5（JLReq の四分）にすることが考えられる。二つのマニュアルは警告なしで組むことを求めているので、`golem build` の警告にすると、この ADR の後も残る行のために二つのマニュアルが組めなくなる。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-09、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [golem-driver ADR 0017](../../golem-driver/adr/0017-pdf-code-blocks.md)、[golem-layout ADR 0001](0001-knuth-plass-line-breaking.md)、[golem-layout ADR 0018](0018-url-line-breaks.md)、[golem-layout ADR 0031](0031-line-breaks-after-low-lines-in-identifiers.md)、[golem-layout ADR 0034](0034-line-breaks-between-japanese-characters-in-inline-code.md)、[golem-layout ADR 0036](0036-record-what-the-implementation-of-0034-decided.md)、[golem-layout ADR 0042](0042-draw-the-wrap-mark-of-inline-code-small-and-light.md)
- [ADR 0208](../../adr/0208-widen-lightweight-formal-methods.md)、[ADR 0209](../../adr/0209-line-breaking-invariants-by-exhaustive-small-inputs.md)、[ADR 0210](../../adr/0210-warn-overfull-lines-in-build.md)
- [TeX と InDesign との差異](../../differences-from-tex-and-indesign.md)
- W3C. Requirements for Japanese Text Layout (JLReq). https://www.w3.org/TR/jlreq/（3.1.12 の行の調整処理例、3.8 行の調整処理、3.8.4 空ける処理の優先順位、付録 C の C.2）。w3c/jlreq の `index.html` を 2026-11-09 に読んだ。
- Donald E. Arseneau. url.sty 3.4（2013/09/16）。TeX Live 2026 の Docker のイメージで、`hyphens` のオプションの有無を組んで確かめた（2026-11-09）。
- 奥村晴彦ほか. jsarticle.cls（2025/04/27）。`\emergencystretch` の既定（3zw）を読んだ。
- Donald E. Knuth, Michael F. Plass. "Breaking Paragraphs into Lines". Software: Practice and Experience 11(11), 1981.
