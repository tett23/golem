# ADR 0031: 欧文の語とコードの中の `_` の後で、ハイフンを描かずに改行できるようにする

ステータス: 採択（未実装）

## 文脈

[docs/adr/0222](../../adr/0222-line-breaking-points-the-invariants-did-not-decide.md) の決めること 4 は、分綴のパターンに渡すのを、要素の最初の字（一般カテゴリが L の字）から、その後の最初の字でない文字の前までとした。
その実装（[#682](https://github.com/tett23/golem/pull/682)）で、開発者のマニュアルの p.200 の脚注の行が大きく空いた。
脚注は、地の文に `THIRD_PARTY_LICENSES` を書いている（[`14-fixtures.gm`](https://github.com/tett23/golem/blob/6380b99853307e4d4f3e35e8a448a84ce879412d/manual-dev/part2/14-fixtures.gm#L103)）。
この ADR の前は `THIRD_PARTY_LI-CENSES` と分綴していたが、今はパターンが `THIRD` だけを見るので、語のどこでも分けられない。

### `_` を含む語には、分割の候補が一つもない

テストの送りの表（golem-layout のテストの `LineBreakEnum`）で、次のとおりに確かめた（2026-11-08、origin/main の 6380b998）。

- `THIRD_PARTY_LICENSES` の項目は、箱が一つと段落の終わりの項目だけである。
- `LICENSES` だけなら、`LI`、パターンの分綴の罰点、`CENSES` になる。
- `third_party_licenses` も、箱が一つである。

`_` の後の部分（`_PARTY_LICENSES`）は、[`wordItems`](https://github.com/tett23/golem/blob/6380b99853307e4d4f3e35e8a448a84ce879412d/modules/golem-layout/src/Golem/Layout/Japanese.hs#L1037-L1060) で、分綴した最後の部分に戻す「後の文字」になる。
これは 0222 の「実装しないこと」の `U.S.A.` と同じ扱いであり、0222 の規則のとおりである。
はみ出さない限り [ADR 0210](../../adr/0210-warn-overfull-lines-in-build.md) の G07105 も出ないので、空いた行は黙って残る。

### 三つの組み方で、`_` の扱いが違う

`_` を含む識別子は、地の文、文字スタイル `code`、文字スタイル `url` のどれでも書かれる。
今の規則は、三つで違う。

| 組み方 | 今の改行の位置 | 根拠 |
| --- | --- | --- |
| 地の文 | 空白、明示のハイフンの後、パターンの分綴（`_` の前の字の並びだけ） | [docs/adr/0179](../../adr/0179-lines-ending-in-explicit-hyphens.md)、[docs/adr/0222](../../adr/0222-line-breaking-points-the-invariants-did-not-decide.md) |
| `code` | 空白と `/` の後（[`codeParts`](https://github.com/tett23/golem/blob/6380b99853307e4d4f3e35e8a448a84ce879412d/modules/golem-layout/src/Golem/Layout/Japanese.hs#L936-L941)） | [golem-driver ADR 0017](../../golem-driver/adr/0017-pdf-code-blocks.md) |
| `url` | 空白と、`_` を含む url パッケージの字の後（[`urlBreakChars`](https://github.com/tett23/golem/blob/6380b99853307e4d4f3e35e8a448a84ce879412d/modules/golem-layout/src/Golem/Layout/Japanese.hs#L959-L960)）、罰点 100 | [golem-layout ADR 0018](0018-url-line-breaks.md) |

`url` だけが、`_` の後で分けられる。
識別子を `code` で書くと、地の文より分けにくくなり、地の文に書いても 0222 の後は分けられない。

### `_` は、自然言語の語に現れない

U+005F（LOW LINE）は、英語の正書法の字ではない。
地の文の語に `_` があれば、それはプログラムの識別子かファイルの名前である。
`.`、`,`、`'` は文の終わりや略語に現れるので、語の中のどこで分けてよいかを字だけで決められない。
`_` には、この曖昧さがない。

識別子は自然言語の語ではないので、英語のパターンで分綴して `LI-CENSES` とハイフンを描くと、ハイフンが識別子の一部に見える。
LaTeX の url パッケージも『The Chicago Manual of Style』も、URL を分けた位置にハイフンを足さない（[golem-layout ADR 0018](0018-url-line-breaks.md) の「文脈」）。

## 実装すること

### 1. 地の文の欧文の語は、`_` の連なりの後で分けられる

欧文の語（リンクの語を除く）が `_` を含むなら、語を `_` の連なりの後で要素に分け、要素のあいだに `Penalty 0 100 NoHyphen` を置く。

- 語の最初の `_` の連なり（`__init__` の前の `__`）の後と、語の最後の `_` の連なりの後では分けない。[`explicitParts`](https://github.com/tett23/golem/blob/6380b99853307e4d4f3e35e8a448a84ce879412d/modules/golem-layout/src/Golem/Layout/Japanese.hs#L1080-L1091) と同じ規則である。
- `_` を含む語は、パターンで分綴しない（「メンテナーが決めること」の 2）。
- 語が明示のハイフンも含むなら（`foo_bar-baz`）、明示のハイフンの後の候補は今のとおり置き、`_` の後の候補も置く。どちらの要素もパターンで分綴しない。
- `explicit-hyphen-penalty = 10000` で語を一つの箱にする規則（[docs/adr/0179](../../adr/0179-lines-ending-in-explicit-hyphens.md)）は、明示のハイフンの候補にだけ当て、`_` の候補には当てない。
- 和欧間の空き、禁則、突き出しは、今のとおりである。`_` は欧文の字なので、要素のあいだに禁則は当たらない。

### 2. 文字スタイル `code` も、`_` の連なりの後で分けられる

`codeParts` で、`/` の後に加えて `_` の連なりの後でも部分を分ける（1 と同じく、最初と最後の連なりの後を除く）。
`normalize` の `code` の箱のあいだの罰点（[`Japanese.hs`](https://github.com/tett23/golem/blob/6380b99853307e4d4f3e35e8a448a84ce879412d/modules/golem-layout/src/Golem/Layout/Japanese.hs#L1152)）は、`/` の後を今のとおり 0、`_` の後を 100 とする。
ハイフンは描かない。
`url` は変えない。

### 3. 文書

- 仕様書の「行分割」の節の分綴の段落に、「`_` を含む欧文の語は、パターンで分綴せず、`_` の連なりの後（語の最初と最後の連なりを除く）で、ハイフンを描かずに改行できる。罰点は 100 である」と、この ADR へのリンクを足す。
- 仕様書の文字スタイル `code` の段落の「改行してよい位置を空白と `/` の後に限る」を、「空白、`/` の後、`_` の連なりの後に限る」に改める。
- 利用者のマニュアルの `code` の改行の説明があれば、同じく改める。

### 4. 出力の変化

`_` を含む語を書いた段落が変わる。
開発者のマニュアルの p.200 の脚注は、`THIRD_` か `PARTY_` の後で分けられるようになる。
コードの中の識別子（`THIRD_PARTY_LICENSES/` など）も分かれうる。
実装のプルリクエストで、golden、`scripts/visual/` の参照、二つのマニュアルと complex fixture の決定性のハッシュの変化を確かめ、説明に書く。

## 実装しないこと

- **`_` のほかの識別子の字**：地の文の `.`、`/`、`::`、`->` の後では分けない。`.` と `/` は文と略語と分数にも現れ、字だけで識別子と決められない。識別子として分けたい語は `code` か `url` で書く。
- **CamelCase の境目**：`ComposeEnv` の大文字の前では分けない。英語の固有名詞（`McDonald`）と区別できない。
- **`url` の規則**：[golem-layout ADR 0018](0018-url-line-breaks.md) のままとする。
- **HTML と EPUB**：ブラウザーの改行に任せる今のままとする。

## 不変条件

「`_` の候補」は、1 と 2 で置く、`_` の連なりの後の `Penalty 0 100 NoHyphen` とする。

- **U1**：地の文の欧文の語（リンクの語を除く）と `code` の語の、最初でも最後でもない `_` の連なりの後には、`_` の候補が一つずつある。ほかの位置には `_` の候補がない。
- **U2**：`_` を含む地の文の語には、パターンの分綴の罰点がない。
- **U3**：`_` の候補で分けた行の終わりに、ハイフンを描かない。分けた二つの行の字をつなぐと、元の語になる。
- **U4**：`_` を含まない語の項目は、この ADR の前と同じである。
- **U5**：`url` の語の項目は、この ADR の前と同じである。
- **U6**：`code` の `/` の後の候補は、今のとおり罰点 0 である。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| `_` の位置 | 語の最初（`_private`）、語の最後（`foo_`）、両端（`__init__`）、中ほど一つ（`a_b`）、連なり（`a__b`）、複数（`THIRD_PARTY_LICENSES`） |
| ほかの字 | 明示のハイフン（`foo_bar-baz`）、句点（`foo_bar.`）、引用符（`“foo_bar”`）、`/`（`THIRD_PARTY_LICENSES/`） |
| 組み方 | 地の文、`code`、`url`、リンクの語 |
| 区間の言語 | なし、`en`、`fr`、`ja` |
| `explicit-hyphen-penalty` | 既定の 50、10000 |
| 行の残りの幅 | `_` の候補の前でちょうど終わる、候補の前の字で足りない |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
テストの名前には、U1 から U6 の番号を入れる。

- **U1、U2**：`LineBreakingSpec` の項目のテストで、`THIRD_PARTY_LICENSES` が `THIRD_`、罰点 100、`PARTY_`、罰点 100、`LICENSES` になること。今は箱一つなので失敗する。`__init__`、`_private`、`foo_` は箱一つのままであること。`a__b` は `a__` の後でだけ分けること。
- **U1**：`[code: THIRD_PARTY_LICENSES/]` の項目に、`_` の後の罰点 100 と `/` の後の罰点 0 があること。今は `_` の後にないので失敗する。
- **U3**：2 字の行に `THIRD_PARTY_LICENSES` を組み、行の字をつなぐと元の語になり、どの行の終わりにもハイフンの罰点がないこと。
- **U4**：`table`、`lime-tree`、`table.` の項目が、今のテストのとおりであること。
- **U5**：`url` の語の項目が、[golem-layout ADR 0018](0018-url-line-breaks.md) のテストのとおりであること。
- 列挙：[docs/adr/0209](../../adr/0209-line-breaking-invariants-by-exhaustive-small-inputs.md) の段 2 までのすべての入力のテストが、そのまま通ること。部品に `_` はないので、固定した数は変わらない。

## トレードオフ

地の文の `_` を含む語は、パターンで分綴しなくなる。
`THIRD_PARTY_LICENSES` の `LI-CENSES` のような分綴の位置は失うが、`_` の後の候補がそれより多く、識別子にハイフンを描かない。

`code` の識別子が `_` の後で分かれると、等幅の書体の行の端が識別子の途中になる。
今の `code` は `/` の後でも同じく分けており、`_` だけを分けない理由はない。
コードブロックの行は、収まる最後のシェイピングのクラスタの後で折り返す別の規則で組むので（仕様書の「コードブロック」の節）、この規則が変えるのはインラインのコードだけである。

罰点 100 は、[golem-layout ADR 0018](0018-url-line-breaks.md) の url の `_` と同じ値である。
三つの組み方で同じ字に同じ値を使うので、設定を足さない。

## メンテナーが決めること

1. **地の文の `_` を含む語を、どこで分けるか**：推奨は、`_` の連なりの後でハイフンを描かずに分けることである。`_` は自然言語の語に現れず、識別子の区切りと読める。URL を分ける慣習（ハイフンを足さない）にも合う。
   - 退けた案の一つは、`_` で区切った字の並びのそれぞれをパターンで分綴することである（0222 の前の `THIRD_PARTY_LI-CENSES`）。識別子の中にハイフンを描き、読み手はハイフンが識別子の一部かを見分けられない。
   - 二つめは、今のままとし、識別子を `url` で書くよう書き手に求めることである。空いた行は警告されず、書き手は気付けない。リンクでない識別子に `url` を使うのも、文字スタイルの意味に合わない。
   - 三つめは、golem-lint の規則で、地の文の `_` を含む語を知らせることである。知らせても、分ける規則がないことは変わらない。
2. **`_` を含む語を、パターンで分綴するか**：推奨は、しないことである。1 のとおり、識別子にハイフンを描かない。
   - 退けた案は、`_` の候補に加えて、要素ごとにパターンで分綴することである。1 の一つめの案と同じく、ハイフンが識別子に入る。
3. **`code` にも当てるか**：推奨は、当てることである。当てないと、識別子を `code` で書いた書き手のほうが、地の文に書いた書き手より分けにくい行を得る。
   - 退けた案は、地の文だけに当てることである。[golem-driver ADR 0017](../../golem-driver/adr/0017-pdf-code-blocks.md) の「`/` の後に限る」は、パスと URL を理由にしており、`_` を除く理由を書いていない。
4. **罰点の値**：推奨は、url の `_` と同じ 100 に固定することである。
   - 退けた案の一つは、`explicit-hyphen-penalty` を使うことである。このキーは明示のハイフンの後の改行の罰点であり（[docs/adr/0179](../../adr/0179-lines-ending-in-explicit-hyphens.md)）、10000 で語を一つの箱にする意味も持つ。`_` に当てると、ハイフンを分けたくない書き手の識別子まで分けられなくなる。
   - 二つめは、0 とすることである。`/` の後と同じく分けやすくなり、識別子が短い要素で頻繁に分かれる。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-08、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- The University of Chicago Press. The Chicago Manual of Style. 17th ed., 2017.（URL の改行）
- LaTeX の url パッケージ（`\UrlBreaks`）。https://ctan.org/pkg/url
- [docs/adr/0179](../../adr/0179-lines-ending-in-explicit-hyphens.md)、[docs/adr/0209](../../adr/0209-line-breaking-invariants-by-exhaustive-small-inputs.md)、[docs/adr/0210](../../adr/0210-warn-overfull-lines-in-build.md)、[docs/adr/0222](../../adr/0222-line-breaking-points-the-invariants-did-not-decide.md)
- [golem-driver ADR 0017](../../golem-driver/adr/0017-pdf-code-blocks.md)、[golem-layout ADR 0008](0008-explicit-hyphens.md)、[golem-layout ADR 0018](0018-url-line-breaks.md)
- [#682](https://github.com/tett23/golem/pull/682) の説明（「Output changes」）
