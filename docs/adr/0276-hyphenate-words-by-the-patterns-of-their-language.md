# ADR 0276: 欧文の語を、その語の言語の分綴のパターンで分綴する

ステータス: 採択

## 文脈

### ロードマップの項目

[docs/roadmap.md](../roadmap.md) の v1.0.0 の「行分割と禁則」に、次の項目がある。

- **本の中の別の言語の分綴**：分綴のパターンは英語のパターン一つだけで、`[lang]` と `@lang` で英語のほかの言語を指定した部分はパターンで分綴しない。区間の外の語は英語のパターンで分綴するので、英語の本の中のフランス語の語も、区間で包まなければ英語のパターンで分綴される（fixture の Nightmare Abbey の「prover-be」）。この項目は、言語の区間と、言語からパターンを引く関数（`Golem.Layout.Hyphenation.Languages.patternsFor`）に、ほかの言語のパターンを足し、区間の言語で分綴する。

v1.x の「行分割の拡張」にも「英語以外の欧文のハイフネーションのパターン」がある。

### 今の分綴

語の箱を分綴するパターンは、語の言語から引く（[`patternsFor`](https://github.com/tett23/golem/blob/9608953da3806ab63cb82abf091bfc1e04b76533/modules/golem-layout/src/Golem/Layout/Hyphenation/Languages.hs#L27-L32)）。
主の副タグが `en` の区間と区間の外は英語（en-US）のパターンを、ほかの言語の区間は `Nothing`（パターンで分綴しない）を返す。
[ADR 0187](0187-inline-language-switch.md) は、v1.0.0 でこの関数にパターンを足すだけで区間の言語の分綴になるように、この形を決めた。
区間の外の語の分綴の例外は、`en-US` で引く（[`outsideSpanTag`](https://github.com/tett23/golem/blob/9608953da3806ab63cb82abf091bfc1e04b76533/modules/golem-layout/src/Golem/Layout/Hyphenation/Languages.hs#L37-L38)、[ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md)）。

同梱のパターンは hyph-utf8 の US English のパターンと例外で、コミット `5684c0f5` のファイルを golem-layout の `data/hyphenation/` に置き、コンパイルのときに埋め込む（[golem-layout ADR 0001](../golem-layout/adr/0001-knuth-plass-line-breaking.md)、[`EnUs.hs`](https://github.com/tett23/golem/blob/9608953da3806ab63cb82abf091bfc1e04b76533/modules/golem-layout/src/Golem/Layout/Hyphenation/EnUs.hs)）。
リリースのアーカイブは、そのライセンスを `scripts/release/licenses.sh` と `scripts/release/check-wasm-archive.sh` で同梱して確かめる。

### 区間の外の語は、本の言語を見ない

区間の外の欧文の語は、本の言語によらず英語のパターンで分綴する。
[ADR 0187](0187-inline-language-switch.md) は、区間の外の両用の文字の扱いで本の言語を見ないと決めた。
今の本の出力を変えないためであった。
その結果、`manifest.toml` の `language` が `fr` の本でも、区間で包まない語はすべて英語のパターンで分けられる。
フランス語の本の書き手は、本文の全体を `@lang fr` で包まない限り、フランス語の分綴を得られない。

### hyph-utf8 のパターン

ghq で取得した hyphenation/tex-hyphen の同じコミット（`5684c0f51c0b81133db2efbe60a408b4155a3ff5`）で、主な欧文の言語のパターンのライセンス、前後に残す字の数、大きさを、`hyph-*.tex` の頭の注記と `patterns/txt` のファイルから読んだ（2026-11-10）。

| タグ | 言語 | ライセンス | 前、後に残す字 | パターンの大きさ |
| --- | --- | --- | --- | --- |
| `en-us` | 英語（米国） | 同梱のとおり | 2、3 | 31 KB |
| `en-gb` | 英語（英国） | MIT | 2、3 | 55 KB |
| `fr` | フランス語 | MIT | 2、2 | 10 KB |
| `de-1996` | ドイツ語（新正書法） | MIT | 2、2 | 272 KB |
| `es` | スペイン語 | MIT/X11 | 2、2 | 40 KB |
| `it` | イタリア語 | LPPL と MIT から選べる | 2、2 | 2 KB |
| `pt` | ポルトガル語 | BSD 3-clause | 2、3 | 2 KB |
| `nl` | オランダ語 | MIT | 2、2 | 83 KB |

どれも Golem の MIT ライセンスと両立し、ライセンスの文をアーカイブに同梱すればよい。
ほかの言語（ラテン語、北欧の言語、スラブの言語など）もあるが、ライセンスと文字（キリル文字、ギリシア文字）の扱いをまだ確かめていない。

InDesign の言語ごとの分綴は確かめていない。
TeX の babel は、言語を切り替えると、その言語のパターンと前後に残す字の数を使う。

## 実装すること

### 1. 同梱するパターン

hyph-utf8 のコミット `5684c0f51c0b81133db2efbe60a408b4155a3ff5` から、次の言語のパターンと例外のファイル（例外のある言語だけ）と、ライセンスの注記を、golem-layout の `data/hyphenation/` に足す。

- `en-gb`、`fr`、`de-1996`、`es`、`it`、`pt`、`nl`

英語（米国）のファイルは変えない。
前と後に残す字の数は、上の表の hyph-utf8 の値とする。
`data/hyphenation/README.md` に、言語ごとのファイル、出所、ライセンスを足す。
ライセンスの注記は、英語（米国）と同じく `hyph-*.tex` の頭の注記を `LICENSE-hyph-*.txt` に写す。
イタリア語のライセンスは MIT を選ぶ。

`Golem.Layout.Hyphenation` の下に、言語ごとに `EnUs.hs` と同じ形のモジュールを足し、コンパイルのときに埋め込む。
`golem-layout.cabal` の `extra-source-files` は今の `data/hyphenation/*.txt` のままで足りる。
新しい build-depends は足さない。

### 2. 言語からパターンを引く

`patternsFor` は、語の言語のタグを、同梱のパターンの表から RFC 4647 の lookup（[`lookupTag`](https://github.com/tett23/golem/blob/9608953da3806ab63cb82abf091bfc1e04b76533/modules/golem-layout/src/Golem/Layout/Hyphenation/Languages.hs#L62-L71)）で引く。
表のキーは次のとおりとする。

| キー | パターン |
| --- | --- |
| `en`、`en-us` | 英語（米国） |
| `en-gb` | 英語（英国） |
| `fr` | フランス語 |
| `de` | ドイツ語（新正書法） |
| `es` | スペイン語 |
| `it` | イタリア語 |
| `pt` | ポルトガル語 |
| `nl` | オランダ語 |

`en-AU` は `en` で英語（米国）に、`de-CH` と `de-1901` は `de` でドイツ語（新正書法）に、`pt-BR` は `pt` に当たる。
表に当たらない言語（`ja` を含む）は、今のとおり `Nothing` を返す。

### 3. 区間の外の語の言語

区間の外の欧文の語は、本の言語（`manifest.toml` の `[metadata] language`）で、2 の表から引く。
本の言語が表に当たらない（`ja`、`zh` など）か、本の言語がなければ、今のとおり英語（米国）のパターンを使う。
分綴の例外も、同じタグで引く。
区間の外の語を引くタグは、本の言語が表に当たれば本の言語、当たらなければ `en-US` とする（`outsideSpanTag` を、本の言語から決める関数に替える）。

本の言語は、golem-typeset が `cePatterns` を作る箇所（[`Flow.hs`](https://github.com/tett23/golem/blob/9608953da3806ab63cb82abf091bfc1e04b76533/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L1171) と [`Flow.hs`](https://github.com/tett23/golem/blob/9608953da3806ab63cb82abf091bfc1e04b76533/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L1800)）に渡す。
両用の文字の扱い（区間の外は最も近い文字で決める）は変えない。
変えるのは分綴のパターンと例外を引く言語だけである。

### 4. 変えないもの

- パターンに渡す字の範囲（要素の最初の字から、次の字でない文字の前まで。[docs/adr/0222](0222-line-breaking-points-the-invariants-did-not-decide.md)）。
- 明示のハイフンとダッシュの後の候補、ソフトハイフン、分綴の例外の一覧の書き方と引き方の順（[ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md)）。
- パターンの候補の罰点（50）と、最初の段階で使わないこと。
- HTML、EPUB、プレーンテキスト。自動の分綴をしないので、パターンを読まない。

### 5. 文書とリリース

- [docs/specifications.md](../specifications.md) の「原稿の中の言語」の「分綴」に、2 の表、区間の外は本の言語で引くこと、前後に残す字の数が言語ごとに違うことを書き、この ADR へのリンクを付ける。「行分割」の節の「英語の区間と区間の外の語は英語（en-US）のパターンで分綴し」も書き換える。
- `scripts/release/licenses.sh` と `scripts/release/check-wasm-archive.sh` に、足した言語のライセンスの注記を足す。
- [docs/roadmap.md](../roadmap.md) の v1.0.0 の「行分割と禁則」から「**本の中の別の言語の分綴**」の行を消す。v1.x の「行分割の拡張」の「英語以外の欧文のハイフネーションのパターン」を、「この ADR で同梱しなかった言語のパターン」に書き換え、この ADR へのリンクを付ける。
- [TeX と InDesign との差異](../differences-from-tex-and-indesign.md) に、区間の外の語を本の言語で分綴することと、babel との比べを書く。

### 6. 出力の変化

`en` でない欧文の区間の語と、本の言語が表に当たる本の区間の外の語の分綴が変わる。
`en-GB` の区間の語は、英国の英語のパターンで分けるようになる。
本の言語が `ja` の本で、英語のほかの言語の区間を含まない本は変わらない。
二つのマニュアル（本の言語は `ja`）の PDF は、`[lang]` の区間を含む箇所だけが変わりうる。
Nightmare Abbey の fixture（本の言語は `en`）は、区間の外の語のパターンが今と同じ英語（米国）なので変わらない。
「prover-be」は、書き手が `[lang fr: proverbe]` と包めば、フランス語のパターンで分ける（どこで分かれるかは確かめていない）。
実装のプルリクエストで、golden と fixture のうち変わった PDF を説明に書く。

## 実装しないこと

- **表にない言語のパターン**：ライセンスと文字の扱いを言語ごとに確かめてから、別の ADR で足す（「メンテナーが決めること」の 1）。
- **フランス語の省略のアポストロフィの後の分綴**：`l’homme` は、パターンに渡す字が `l` で終わり、`homme` を分綴しない。babel のように、アポストロフィの後を別の要素として分綴するかは、パターンに渡す字の範囲（[docs/adr/0222](0222-line-breaking-points-the-invariants-did-not-decide.md)）を変えることになり、別の ADR で決める。
- **ドイツ語の旧正書法とスイスの正書法のパターン**：`de-1901` と `de-CH` は新正書法で分ける（「メンテナーが決めること」の 3）。
- **言語ごとの前後に残す字の数を `style.toml` で変えること**：TeX の `\lefthyphenmin` と `\righthyphenmin` にあたる設定は足さない。
- **パターンのない言語の区間の報告**：今のとおり diagnostic を出さずに、パターンで分綴しない。

## 不変条件

「語の言語」は、語を含む最も内側の言語の区間のタグとし、区間の外の語では本の言語とする（本の言語がなければ、ないとする）。
「表」は、2 の表とする。
「パターン L で分ける位置」は、語の要素の字の並びに、言語 L のパターンと前後に残す字の数で Liang の方式を当てた位置とする。

- **F1 パターンの引き方**：`patternsFor` は、タグを表から lookup で引き、当たったキーのパターンを返す。当たらなければ `Nothing` を返す。区間の外の語は、本の言語が表に当たればそのパターン、当たらなければ英語（米国）のパターンを使う。
- **F2 語の言語で分ける**：分綴の例外の一覧に当たらず、ソフトハイフンを含まない要素のパターンの分綴の罰点の位置は、語の言語が表に当たれば、その言語のパターンで分ける位置にちょうど等しい。当たらない区間の語では、パターンの分綴の罰点がない。
- **F3 英語（米国）の入力は変わらない**：本の言語が表に当たらない本の区間の外の語と、`en` と `en-US` の区間の語の項目は、この ADR の前と同じである。
- **F4 区間の外と同じ言語の区間**：本の言語が表に当たる本で、区間の外の段落の項目は、同じ段落を本の言語の `[lang]` で包んだ段落の項目と、語の箱の言語の欄のほかは同じである。
- **F5 例外も同じ言語で引く**：区間の外の語の例外は、F1 でパターンを引いたタグで lookup する。[ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md) の I5、I6、I12、I13 は、このタグで読んで成り立つ。
- **F6 同梱のファイル**：`data/hyphenation/` の各ファイルのバイト列は、hyph-utf8 のコミット `5684c0f51c0b81133db2efbe60a408b4155a3ff5` の同じファイルに等しい。
- **F7 HTML と EPUB**：HTML、EPUB、プレーンテキストの出力のバイト列は、この ADR の前と同じである。

[ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md) の L9（分綴の行末）は、「前に 2 字、後に 3 字」を、語の言語の前後に残す字の数に読み替える。
L8 と、ほかの不変条件は、パターンが変わるだけなので、そのまま成り立つ。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 区間の言語 | なし、`en`、`en-US`、`en-GB`、`en-AU`、`fr`、`fr-CA`、`de`、`de-1901`、`de-CH`、`pt-BR`、`ja`、`ru`、`zh` |
| 本の言語 | `ja`、`en`、`en-GB`、`fr`、`de`、書かない |
| 語の長さ | 前と後に残す字の数の和、和より一つ多い、長い語 |
| 語の形 | 例外の一覧の語、ソフトハイフンを含む語、明示のハイフンを含む語、`l’homme` |
| 段階 | 1（パターンを使わない）、2 |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
テストの名前には、F1 から F7 の番号を入れる。

- **F1**：`patternsFor` が、2 の表のキーと境界の入力のタグで、期待のパターン（言語の名前で見分ける）か `Nothing` を返すこと。今は `fr` と `de` で `Nothing` を返すので失敗する。区間の外は、本の言語が `fr` ならフランス語、`ja` なら英語（米国）を使うこと。
- **F2**：言語ごとに、hyph-utf8 のパターンで TeX が分けた語の例を数語ずつ選び、分綴の罰点の位置がそれに等しいこと。期待の位置は、実装の最初に TeX Live の Docker のイメージで `\showhyphens` を使って求め、テストのデータの README に手順を書く（[golem-layout ADR 0007](../golem-layout/adr/0007-knuth-plass-reference-test.md) の参照のテストと同じ扱い）。`[lang fr: proverbe]` の分綴の罰点の位置が、TeX がフランス語のパターンで求めた位置に等しいこと（今は罰点がないので失敗する）。
- **F3**：本の言語が `ja` の今の golden と、英語の区間の入力の項目が、この ADR の前と同じであること。
- **F4**：本の言語を `fr` にした本で、区間の外の段落と `[lang fr: …]` で包んだ段落の分綴の罰点の位置が等しいこと。今は区間の外が英語のパターンなので失敗する。
- **F5**：本の言語を `fr` にした本の `[composition.hyphenation-exceptions]` に `fr = ["pro-ver-be"]` を書き、区間の外の `proverbe` がその位置で分かれること。
- **F6**：同梱のファイルの SHA-256 を、README に書いた値と比べるテスト。
- **F7**：本の言語を `fr` にした本の HTML と EPUB のバイト列が、この ADR の前と同じであること。
- **列挙**：[ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md) の列挙の区間の言語に `fr` を足し、L1 から L13（L9 は読み替えたもの）が成り立つことを確かめる。プルリクエストの段の時間が範囲ごとの予算 10 秒（[ADR 0208](0208-widen-lightweight-formal-methods.md) の 4）を超えるなら、`fr` は毎晩のジョブの段だけで足す。

## トレードオフ

区間の外の語を本の言語で分綴すると、[ADR 0187](0187-inline-language-switch.md) の「区間の外は本の言語を見ない」が、分綴についてだけ変わる。
両用の文字は今のとおり最も近い文字で決め、分綴は本の言語で決めるので、区間の外の規則が二つになる。
それでも、フランス語やドイツ語の本の書き手が本文の全体を `@lang` で包まずに済むことを選ぶ。

パターンを埋め込むので、golem の実行ファイルが大きくなる。
足すパターンの合計はおよそ 460 KB の文字列であり、ドイツ語のパターンがその六割を占める。
wasm 版のアーカイブも同じだけ大きくなる。

`en-GB` の区間は、英国の英語のパターンで分けるようになり、今の出力が変わる。
今は英国の英語の語を米国の英語のパターンで分けており、分け方が正書法に合わない語がある。

## メンテナーが決めること

1. **同梱する言語**：推奨は、`en-gb`、`fr`、`de-1996`、`es`、`it`、`pt`、`nl` の七つである。ラテン文字の主な言語で、ライセンスが MIT か BSD か MIT を選べるものであり、合計の大きさも 460 KB ほどに収まる。
   - 退けた案の一つは、hyph-utf8 のすべての言語を同梱することである。ライセンス（LPPL だけのもの、GPL を含むもの）を言語ごとに確かめる必要があり、キリル文字とギリシア文字の語の箱の扱いも確かめていない。
   - もう一つは、フランス語だけを足すことである。ロードマップの例は満たすが、ほかの言語の書き手が同じ問題に当たる。
2. **区間の外の語の言語**：推奨は、本の言語が表に当たれば本の言語で、当たらなければ英語（米国）で分綴することである。既定のままでフランス語の本がフランス語で分綴され、本の言語が `ja` の本は今と変わらない。
   - 退けた案は、今のとおり区間の外は英語（米国）にすることである。[ADR 0187](0187-inline-language-switch.md) の規則は一つのままだが、英語でない本の書き手は本文の全体を `@lang` で包むことになる。
3. **ドイツ語の正書法**：推奨は、`de` とその下のすべてのタグを新正書法（`de-1996`）で分けることである。今のドイツ語の本の多くが新正書法で書かれる。
   - 退けた案は、`de-1901` と `de-CH-1901` のパターンも同梱することである。合わせて 535 KB が増える。
4. **イタリア語のライセンス**：推奨は、LPPL と MIT から MIT を選ぶことである。Golem のライセンスと同じで、注記の扱いも英語（米国）と同じにできる。
   - 退けた案は、LPPL を選ぶことである。改変したファイルの名前の規則など、MIT にない条件が加わる。

## 決めたことの記録

2026-11-10 に、tett23 がすべて推奨のとおりに決めた。

1. 同梱する言語は、推奨のとおり `en-gb`、`fr`、`de-1996`、`es`、`it`、`pt`、`nl` の七つとする。
2. 区間の外の語は、推奨のとおり本の言語が表に当たれば本の言語で、当たらなければ英語（米国）で分綴する。
3. `de` とその下のすべてのタグは、推奨のとおり新正書法（`de-1996`）で分ける。
4. イタリア語のライセンスは、推奨のとおり MIT を選ぶ。

## 参考文献

- [ADR 0187](0187-inline-language-switch.md)、[ADR 0208](0208-widen-lightweight-formal-methods.md)、[ADR 0209](0209-line-breaking-invariants-by-exhaustive-small-inputs.md)、[ADR 0222](0222-line-breaking-points-the-invariants-did-not-decide.md)、[ADR 0272](0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md)
- [golem-layout ADR 0001](../golem-layout/adr/0001-knuth-plass-line-breaking.md)、[golem-layout ADR 0007](../golem-layout/adr/0007-knuth-plass-reference-test.md)
- hyph-utf8（hyphenation/tex-hyphen）. https://github.com/hyphenation/tex-hyphen（コミット `5684c0f51c0b81133db2efbe60a408b4155a3ff5`。`hyph-utf8/tex/generic/hyph-utf8/patterns/tex/` の各 `hyph-*.tex` の頭の注記でライセンスと前後に残す字の数を、`patterns/txt/` の大きさを 2026-11-10 に読んだ）
- Frank M. Liang. "Word Hy-phen-a-tion by Com-put-er". Stanford University, 1983.
- A. Phillips, M. Davis. RFC 4647, Matching of Language Tags. 2006.
- InDesign の言語ごとの分綴の辞書は、Golem の開発の環境で動かせないので確かめていない。
