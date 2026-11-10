# ADR 0280: 隣り合う欧文の語の箱のあいだの分割を、つないだ語の分割に合わせる

ステータス: 採択

## 文脈

### 列挙が見つけた L8 の違反

[ADR 0277](0277-keep-the-page-label-of-a-citation-mark-with-its-value.md) の実装（[#822](https://github.com/tett23/golem/pull/822)）は、引用の印を部品に足した行分割の列挙（[`CiteBreakEnum`](https://github.com/tett23/golem/blob/79c91475c33a9840797e625a14c9ea2a68490143/modules/golem-layout/test/CiteBreakEnum.hs)）を足した。
プルリクエストの CI は部品 2 個まで調べる（[`citePrDepth`](https://github.com/tett23/golem/blob/79c91475c33a9840797e625a14c9ea2a68490143/modules/golem-layout/test/CiteBreakEnum.hs#L272-L273)）。
`GOLEM_ENUM_CITE_DEPTH=3` で走らせると、[ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md) の L8 の違反が見つかる。
2026-11-10 に origin/main（`7f496c77`）で走らせ、手元の 4 コアで 44.6 秒で失敗した。

最も小さい入力は、部品 `a`、`—`（U+2014）、`[cite a page=5]` を、行の幅 2 em、区間の外、禁則の strict で組んだ段落である。
`a—` と印の `[1,` が別の箱になり、そのあいだに罰点 0 の分割の候補（`Penalty 0 0 NoHyphen`）ができ、行がそこで分かれる。
L8 の述語（[`l8InsideWords`](https://github.com/tett23/golem/blob/79c91475c33a9840797e625a14c9ea2a68490143/modules/golem-layout/test/LineBreakInvariants.hs#L351-L370)）は、二つの欧文の語の箱のあいだで分けてよい位置を、語間のグルーと、ハイフンの種類を持つ罰点（パターンの分綴、明示のハイフン、ソフトハイフン）に限る。
罰点 0 の `NoHyphen` はそのどれでもない。

[ADR 0277](0277-keep-the-page-label-of-a-citation-mark-with-its-value.md) の C2 は、印を同じ文字列のテキストに置き換えた段落と項目を比べる。
置き換えた段落でも印は別のインラインなので、同じ位置に同じ候補ができる。
違反は [ADR 0277](0277-keep-the-page-label-of-a-citation-mark-with-its-value.md) の前からある。

### 原因

箱のあいだの分割と空きは、`normalize` の [`between`](https://github.com/tett23/golem/blob/79c91475c33a9840797e625a14c9ea2a68490143/modules/golem-layout/src/Golem/Layout/Japanese.hs#L1819-L1864) が、前の箱の最後の字と後の箱の最初の字の文字クラスで決める。
二つの欧文の語の箱のあいだで分けない規則は、両方の字の文字クラスが欧文（`Western`）のときにだけ当たる（[1829 行](https://github.com/tett23/golem/blob/79c91475c33a9840797e625a14c9ea2a68490143/modules/golem-layout/src/Golem/Layout/Japanese.hs#L1829)）。
区間の外では、語に入った両用の文字（[`isJoiner`](https://github.com/tett23/golem/blob/79c91475c33a9840797e625a14c9ea2a68490143/modules/golem-layout/src/Golem/Layout/Japanese.hs#L938-L947)）の文字クラスは和文のクラスのままである。
`—` は分離禁止文字、`–‐‑` はハイフン類、`’”` は終わり括弧類、`“` は始め括弧類になる。
そのため、語の端の字がこれらの字なら欧文どうしの規則が当たらず、和文の字間と同じく禁則だけで分割を決める。
空きは、語の箱を両端とも欧文として扱うので（[`akiFirst` と `akiLast`](https://github.com/tett23/golem/blob/79c91475c33a9840797e625a14c9ea2a68490143/modules/golem-layout/src/Golem/Layout/Japanese.hs#L1816-L1817)）、正しく 0 になる。
分割の判定だけが、仕様書の「欧文の単語の箱は、両端の引用符やダッシュを含めて欧文（`western`）として扱う」（[仕様書の「style.toml」の節](../specifications.md#styletoml) のアキ量のセットの段落）と食い違っている。

一つの語が二つの箱に分かれるのは、語の途中にインラインの境目があるときである。
文字スタイル、言語の区間、リンク、引用の印の境目は、語の箱の境目になる（[ADR 0187](0187-inline-language-switch.md)、[ADR 0172](0172-continuous-double-dashes.md) のテスト設計）。
[ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md) の列挙は、続くテキストの部品を一つのテキストにまとめるので、境目を作らない。
引用の印は、列挙が境目を作る最初の部品である。

### 今の振る舞い

2026-11-10 に origin/main（`7f496c77`）の golem-layout を `cabal repl` で読み込み、`defaultComposeEnv` で二つのインライン（前のテキストと、`[strong: …]` の中のテキスト）の項目を、つないだ一つのテキストの項目と比べた。
表の「候補」は、二つの箱のあいだの項目である。

| 前 | 後 | 二つのインライン | 一つのテキスト |
| --- | --- | --- | --- |
| `a—` | `b` | 罰点 0 | 明示のハイフンの罰点 50 |
| `a—` | `[1,` | 罰点 0 | 明示のハイフンの罰点 50 |
| `a–`、`a‐` | `b` | 罰点 0 | 明示のハイフンの罰点 50 |
| `a‑` | `b` | 罰点 0 | 候補なし（U+2011 は候補を作らない） |
| `a-` | `b` | 候補なし | 明示のハイフンの罰点 50 |
| `a` | `—b` | 罰点 0 | 明示のハイフンの罰点 50（`a—` の後） |
| `a` | `–b`、`‐b`、`-b` | 候補なし | 明示のハイフンの罰点 50（`a–` などの後） |
| `a’`、`a”` | `s`、`b` | 罰点 0 | 候補なし |
| `a` | `’s`、`“b` | 罰点 0 | 候補なし |
| `ab`、`a.`、`a,` | `cd`、`b` | 候補なし | 候補なし |

`[lang en: …]` の中では、両用の文字が欧文のクラスになるので、どの組でも候補がない。
一つのテキストなら罰点 50 の候補ができる `a—` と `b` のあいだでも、候補がない。

二つのインラインの振る舞いは、境目の両側の字のクラスで四通りに割れる。
L8 を破るのは、罰点 0 の行（ダッシュの後と前、引用符とアポストロフィの前後）である。
L8 を破らないが一つのテキストと違うのは、`a-` と `b` のように候補がなくなる行である。

同じ日に、`golem new` の雛形（Noto Serif JP）を横組み、行長 14 字にした本で、`あ`×11 `[strong: aaaa]—bbbbbbbbbb` を組んだ（インストール済みの `golem 0.1.0-rc4`）。
PDF を `sips` で画像にして見ると、二行目が `—bbbbbbbbbb` で始まった。
欧文の語の中で、ダッシュの前で行が分かれている。

### 拠るもの

仕様書は、組版の振る舞いを JLReq、InDesign、TeX と LaTeX の順に拠って決めるとする（[仕様書の「仕様が不明瞭な場合」](../specifications.md#仕様が不明瞭な場合)）。

- JLReq は、和文の中の欧文の語を、ハイフネーションの位置のほかで分けないとする（英語の題が「Handling of Western Text in Japanese Text using Proportional Western Fonts」の節）。文字スタイルの境目には触れていない。`—` の分離禁止（3.1.10）は和文の字の規則であり、欧文の語の中の `—` は欧文の字である。
- InDesign の振る舞いは、Golem の開発の環境で動かせないので確かめていない。
- TeX は、入力の文字が `\hyphenchar` に当たると、その直後に空の discretionary を置く（[golem-layout ADR 0008](../golem-layout/adr/0008-explicit-hyphens.md) の文脈）。判定は字ごとであり、後ろでフォントが替わっても変わらない。2026-11-10 に手元の TeX Live 2026 の `tex` で、段落の中の `aaa-{\bf bbb}` と `ccc---{\bf ddd}` を `\showlists` で見ると、`-` と `---` の合字の後に、一つのテキストの `eee-bbb` と同じく `\discretionary` があった。フォントの境目で語が途切れても、そこは分割の候補にならない（ボックスとグルーのない位置は分けられない）。

[ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md) は、見つけた違反を直すことを「実装しないこと」に置き、直す ADR を違反ごとに作るとした。
L8 は罰点 0 の候補を禁じるが、ダッシュの後を明示のハイフンの候補にするか、候補を置かないかは決めない。
どちらも L8 を満たす。
この ADR は、それを決める。

## 実装すること

### 1. 隣り合う欧文の語の箱のあいだ

「隣り合う欧文の語の箱」は、`normalize` に入る項目の列で、あいだにほかの項目を挟まずに続く二つの箱で、どちらも伸縮を受ける箱（`bcExpandable`）であるものとする。
「つないだ語」は、そのように続く欧文の語の箱の並びの、すべての箱の字をつないだ文字列とする。

隣り合う欧文の語の箱のあいだの項目を、次の規則で決める。
空きは今のとおり置かない。

- 境目が、つないだ語の [`explicitParts`](https://github.com/tett23/golem/blob/79c91475c33a9840797e625a14c9ea2a68490143/modules/golem-layout/src/Golem/Layout/Japanese.hs#L1602-L1618) が語を分ける位置（ハイフンとダッシュの連なり `-‐–—` の直後で、連なりの前に一字以上、後に一字以上あるもの）なら、明示のハイフンの罰点 `Penalty 0 p ExplicitHyphen` を一つ置く。`p` は `explicit-hyphen-penalty` である。
- その罰点には、今の明示のハイフンの候補と同じ規則を当てる。`p` が 10000 以上なら置かない（[golem-layout ADR 0008](../golem-layout/adr/0008-explicit-hyphens.md)）。後の字が行頭禁則の文字なら、またはダッシュと後の字がどちらも分離禁止文字なら置かない（[golem-layout ADR 0028](../golem-layout/adr/0028-kinsoku-across-spaces-and-explicit-hyphens.md)）。
- ほかの境目には、何も置かない。ダッシュの前、連なりの途中（`a-` と `-b`）、U+2011 の後、引用符とアポストロフィの前後がこれに当たる。

規則は、区間の外と言語の区間の中で同じである。
欧文の区間で `a—` と `b` のあいだに候補ができるのは、一つのテキストの `[lang en: a—b]` と同じにするためである。

### 2. 語の箱の頭の連なり

1 の規則だけでは、ハイフンとダッシュの連なりが後の箱の頭にあるとき、つないだ語の分ける位置が箱の中に残る。
`a` と `[strong: —b]` では、つないだ語 `a—b` は `—` の後で分けるが、箱 `—b` は前に字がないので `explicitParts` で切れない。

そこで、欧文の語の箱がハイフンとダッシュの連なりで始まり、その前に隣り合う欧文の語の箱があり、つないだ語でその連なりの前に字があるときは、箱を連なりの後でも切る。
連なりは前の箱から続いていてもよい（`a-` と `-b` では、つないだ語 `a--b` の連なり `--` の後、つまり後の箱の `-` の後で切る）。
連なりの後に箱の字が残らないとき（`—` だけの箱）は切らず、1 の境目の規則で決める。
切った位置には、語の中の明示のハイフンと同じ罰点 `Penalty 0 p ExplicitHyphen` を置き、同じ禁則を当てる。
`p` が 10000 以上なら、一つのテキストの語と同じく切らない。
リンクの語は、今のとおり一つの箱とし、切らない（[ADR 0182](0182-external-links.md)）。

これで、つないだ語の `explicitParts` の分ける位置は、境目にあっても箱の中にあっても、一つのテキストと同じ候補になる。
ほかの片の作り方は変えない。
インラインの境目で語の箱を分けることは変えない。
パターンの分綴は今のとおり箱ごとに当て、つないだ語には当てない（「実装しないこと」）。
カーニングも今のとおり箱をまたがない。

### 3. 列挙

- [ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md) の列挙に、インラインの境目を足した列挙を足す（W3）。部品は、欧文の部品（`a`、`lime-tree`、`“`、`”`、`.`、空白）、ダッシュとハイフン（`-`、`‐`、`‑`、`–`、`—`）、アポストロフィ `’`、和文の `あ` とする。並びの隣り合う二つの部品のあいだは、同じテキストか、文字スタイルの境目かのどちらかとし、その二通りをすべて調べる。設定は区間なし、`[lang en]`、`[lang ja]` と、`explicit-hyphen-penalty` の 50 と 10000 とする。
  [ADR 0276](0276-hyphenate-words-by-the-patterns-of-their-language.md) の後、列挙の環境（`patternsFor`）は区間の外と `[lang en]` で en-US のパターンを持つ。
  W2 は、同じ入力を、`cePatterns` がつねに `Nothing` を返す環境でも組んで確かめる。
- プルリクエストの段の上限は、範囲ごとの予算 10 秒（[ADR 0208](0208-widen-lightweight-formal-methods.md) の 4）に収まる部品の数を実装で測って決める。
- `.github/workflows/enum.yml` に、引用の印の列挙（`GOLEM_ENUM_CITE_DEPTH=3`）と、この境目の列挙を毎晩の段として足す。引用の印の部品 3 個の列挙は、手元の 4 コアで 1 分ほどであり（違反の直るまでは 44.6 秒で止まる）、部品 4 個は部品の数の比（32 の 4 乗と 27 の 4 乗の差を 3 乗の差で割って約 40 倍）から手元で 30 分を超えると見込む。今の毎晩の段（ページ分割の約 3 分、行分割の約 9 分から 13 分、改行しない範囲）と合わせても 60 分に収まるので、上限は 3 とする。
  行分割の段の時間は [ADR 0276](0276-hyphenate-words-by-the-patterns-of-their-language.md) が `[lang fr]` の区間を足す前のもので、設定の数の比（3 から 4）で約 17 分までになると見込んでも、60 分に収まる。
  最初の三回の実行の時間を README の `enum.yml` の行に書く。

### 4. 文書

- [docs/specifications.md](../specifications.md) の「行分割」の節の、明示のハイフンの候補の段落に、語がインラインの境目で二つの箱に分かれても、候補はつないだ語と同じ位置にだけ置き、ほかの境目では分けないことと、箱の頭の連なりの後でも切ることを足す。
- README の CI のジョブの表の `enum.yml` の行に、引用の印と境目の段を足す。
- [ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md) のステータスの行は変えない。L8 の述語は変えず、W1 と W2 を足すだけである。

### 5. 出力の変化

語の途中に文字スタイル、言語の区間、リンク、引用の印の境目があり、境目の字がダッシュ、ハイフン、引用符、アポストロフィである段落の行の分け方が変わりうる。
実装のプルリクエストで、決定性のハッシュと見た目の回帰テストの変わったものと、その理由を説明に書く。

## 実装しないこと

- **つないだ語の分綴**：境目をまたいでパターンを当てると、箱の作り方が箱ごとでなくなり、字の位置とインラインの構造（[ADR 0183](0183-tagged-pdf-and-pdf-a.md)）の対応を変えることになる。`[strong: hyphen]ation` の中では、今のとおり箱ごとに分綴する。
- **境目のソフトハイフン**：ソフトハイフンが境目にちょうど来る場合（`a[strong: \xAD b]` の形）は、今の [ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md) の規則のままとする。境目の列挙に部品として入れ、L8 と I3 が成り立つことだけを確かめる。
- **欧文の語の箱と和文の字のあいだ**：和欧間の規則と禁則は変えない。`a—` と `あ` のあいだは、今のとおり和欧間の空きと禁則で決める。
- **本文の中のコードと URL の箱**：伸縮を受けないので、この規則に当たらない。[golem-layout ADR 0034](../golem-layout/adr/0034-line-breaks-between-japanese-characters-in-inline-code.md) と [golem-layout ADR 0045](../golem-layout/adr/0045-break-inline-code-after-hyphens-and-full-stops-to-avoid-loose-lines.md) の規則のままである。
- **HTML と EPUB**：閲覧環境は要素の境目をまたいで語を分けないので、変えない。

## 不変条件

「隣り合う欧文の語の箱」と「つないだ語」は、「実装すること」の 1 のとおりとする。
「境目の項目」は、`composeInlines` の項目の列で、隣り合う欧文の語の箱のあいだにある項目の並びとする。

- **W1 境目の候補**：境目の項目は、空か、明示のハイフンの罰点 `Penalty 0 p ExplicitHyphen` 一つである。後者は、境目がつないだ語の `explicitParts` の分ける位置であり、`p` が 10000 より小さく、後の字に [golem-layout ADR 0028](../golem-layout/adr/0028-kinsoku-across-spaces-and-explicit-hyphens.md) の禁則が当たらないとき、そのときに限る。
- **W2 一つのテキストと同じ**：分綴のパターンを持たない設定（`cePatterns` が `Nothing` を返す）では、テキストの部品の並びを境目で分けた段落と、一つのテキストにした段落とで、分割の候補（罰点が 10000 より小さい罰点と、箱の後のグルー）の位置を段落の字の数えで表した列と、それぞれの罰点と種類が等しい。
- **W3 列挙**：境目の列挙のすべての入力で、[ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md) の L1 から L13（L8 と L9 は [ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md) の I2 と I3 のとおりに広げたもの）と W1 が成り立ち、`cePatterns` がつねに `Nothing` を返す環境で W2 が成り立つ。引用の印の列挙では、部品 3 個まで L1 から L13 と [ADR 0277](0277-keep-the-page-label-of-a-citation-mark-with-its-value.md) の C1、C2 が成り立つ。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 境目の前の字 | 欧文の字、`-`、`‐`、`‑`、`–`、`—`、`——`、`’`、`”`、`“`、`.` |
| 境目の後の字 | 欧文の字、`-`、`—`、`’`、`“`、`”`、`[`（引用の印） |
| 連なりの前の字 | あり（`a—`）、なし（`—` だけの箱で、前の箱が欧文の字で終わる、終わらない） |
| 箱の頭の連なり | `a` と `-b`、`a` と `–b`、`a` と `—b`、`a-` と `-b`、前に箱のない `—b`、`あ` と `—b` |
| 境目の数 | 一つ、二つ（`a` と `—` と `b` が三つの箱） |
| 区間 | なし、`[lang en]`、`[lang ja]` |
| `explicit-hyphen-penalty` | 50、10000 |
| 後の字の禁則 | 行頭禁則の字（`”`）、分離禁止文字（`—` の後の `…`）、どちらでもない |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
テストの名前には、L8 と W1 から W3 の番号を入れる。

- **回帰（L8）**：列挙が見つけた最も小さい入力（部品 `a`、`—`、`[cite a page=5]`、行の幅 2 em、区間なし、禁則の strict、字幅の伸縮なし）を名前のあるテストにし、L8 が成り立つことを確かめる。今は `a—` と `[1,` のあいだの罰点 0 で分けるので失敗する。
- **W1**：「今の振る舞い」の表の組のすべてで、境目の項目が W1 のとおりであること。今は `a—` と `b`、`a` と `—b`、`a’` と `s` などで失敗する。
- **W2**：表の組と境界の入力の表の組で、二つのインラインと一つのテキストの分割の候補が等しいこと。今は `a-` と `b`、`a` と `—b`、`a-` と `-b` で失敗する。
- **W3**：境目の列挙をプルリクエストの上限まで走らせる。引用の印の列挙を `GOLEM_ENUM_CITE_DEPTH=3` で手で走らせ、実装の後に成り立つことをプルリクエストの説明に書く。
- **述語のテスト**：W1 と W2 の述語が、今の実装の `a—` と `b` の項目を違反として返すこと。
- **毎晩のジョブ**：自動のテストにできないので、実装の後に `enum.yml` を `workflow_dispatch` で起動し、引用の印と境目の段が通ることと、段ごとの時間を確かめる。

## トレードオフ

- 語の途中のインラインの境目で、一つのテキストと同じ位置でしか分けなくなる。境目の引用符やアポストロフィの前後で分けられた段落は、分ける位置が減り、行が空くか、はみ出しうる。分けられない欧文の長い語と同じ扱いである。
- `a-` と `[strong: b]` のように、今は分けない位置に明示のハイフンの候補が増える。行の調整の余地が増える代わりに、ハイフンで終わる行が増えうる。
- 境目の判定に、つないだ語の文字列が要る。`normalize` は、隣り合う欧文の語の箱の並びの字を持ち回ることになる。
- 箱の頭の連なりの後で切るには、語の箱を作るときに、前に隣り合う欧文の語の箱の字が要る。語の箱は、自分のインラインの字だけでは決まらなくなる。
- `[strong: —b]` のように、文字スタイルの中の語が二つの箱に分かれる。語の中の明示のハイフンで切るのと同じ切り方であり、箱の葉（[ADR 0183](0183-tagged-pdf-and-pdf-a.md)）は変わらない。
- パターンの分綴は箱ごとのままなので、W2 はパターンを持たない設定でしか成り立たない。`[strong: hyphen]ation` の分綴の位置は、一つのテキストの `hyphenation` と違いうる。

## メンテナーが決めること

1. **ダッシュとハイフンの後の境目**：推奨は、つないだ語と同じく明示のハイフンの罰点を置くことである。拠るものの順で JLReq と InDesign が決めず、TeX は字ごとに discretionary を置くので、フォントが替わる位置でも `-` の後で分けうる。文字スタイルを付けたかどうかで行の分け方が変わらない。
   - 退けた案は、隣り合う欧文の語の箱のあいだでは一つも候補を置かないことである。実装は、[1829 行](https://github.com/tett23/golem/blob/79c91475c33a9840797e625a14c9ea2a68490143/modules/golem-layout/src/Golem/Layout/Japanese.hs#L1829) の条件を `bcExpandable p && bcExpandable c` だけにする一行で済み、`[lang en]` の今の振る舞いとも同じになる。ただし、一つのテキストの `a—b` で分けうる位置が、`a—[strong: b]` では分けられなくなり、文字スタイルで行の分け方が変わる。
2. **範囲**：推奨は、隣り合う欧文の語の箱のすべてに当てることである。境目を作るのは引用の印のほか、文字スタイル、言語の区間、リンクであり、どれも同じ `between` を通る。
   - 退けた案は、引用の印の前後だけを直すことである。列挙が見つけた入力は直るが、表の文字スタイルの組の違反が残る。
3. **毎晩のジョブの上限**：推奨は、引用の印の列挙を 3 とすることである。4 は手元で 30 分を超えると見込み、毎晩の予算 60 分の半分を一つの範囲で使う。
   - 退けた案は、毎晩の段に足さず、プルリクエストの 2 のままにすることである。今回の違反は 3 で初めて見つかった。

## 決めたことの記録

2026-11-10 に、tett23 がすべて推奨のとおりに決めた（次の 1 から 3）。

1. ダッシュとハイフンの後の境目には、推奨のとおり、つないだ語と同じく明示のハイフンの罰点を置く。
2. 範囲は、推奨のとおり、隣り合う欧文の語の箱のすべてとする。
3. 毎晩のジョブの引用の印の列挙の上限は、推奨のとおり 3 とする。

採択の前に、草案の 1 の規則と「片の作り方は変えない」のままでは、W2 が `a` と `[strong: —b]`、`a` と `-b`、`a-` と `-b` で成り立たないことがわかった。
連なりが後の箱の頭にあると、つないだ語の分ける位置が箱の中に残り、その箱は前に字がないので切れないためである。
2026-11-10 に、tett23 は次の二つの案のうち案 A を選んだ。

- 案 A：箱の中の候補も、つないだ語の `explicitParts` に合わせる。連なりが箱の頭から始まり、前に隣り合う欧文の語の箱があるときは、連なりの後でも箱を切る（「実装すること」の 2）。草案の「片の作り方は変えない」を、この点で変える。
- 案 B：W2 を、境目の位置の候補だけを比べる形に狭め、`[strong: —b]` で `—` の後に候補がないことをトレードオフに書く。

案 A を選んだ理由は、決めたことの 1 の推奨の理由と同じく、文字スタイルを付けたかどうかで行の分け方が変わらないようにするためである。
案 B では、文字スタイルを付けると分けうる位置が一つ減る場合が残る。
W2 は草案のまま変えない。

## 参考文献

- [ADR 0172](0172-continuous-double-dashes.md)、[ADR 0182](0182-external-links.md)、[ADR 0183](0183-tagged-pdf-and-pdf-a.md)、[ADR 0187](0187-inline-language-switch.md)、[ADR 0208](0208-widen-lightweight-formal-methods.md)、[ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md)、[ADR 0211](0211-record-what-implementations-decided-found-by-the-review-of-2026-11-08.md)、[ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md)、[ADR 0277](0277-keep-the-page-label-of-a-citation-mark-with-its-value.md)
- [golem-layout ADR 0008](../golem-layout/adr/0008-explicit-hyphens.md)、[golem-layout ADR 0028](../golem-layout/adr/0028-kinsoku-across-spaces-and-explicit-hyphens.md)、[golem-layout ADR 0034](../golem-layout/adr/0034-line-breaks-between-japanese-characters-in-inline-code.md)、[golem-layout ADR 0045](../golem-layout/adr/0045-break-inline-code-after-hyphens-and-full-stops-to-avoid-loose-lines.md)
- W3C. Requirements for Japanese Text Layout (JLReq). https://www.w3.org/TR/jlreq/（3.1.10 分割禁止と、英語の題が「Handling of Western Text in Japanese Text using Proportional Western Fonts」の節）
- D. E. Knuth. TeX: The Program（tex.web の main control で `\hyphenchar` の後に置く空の discretionary）。TeX Live 2026 の `tex` で 2026-11-10 に確かめた。
- InDesign の振る舞いは、Golem の開発の環境で動かせないので確かめていない。
