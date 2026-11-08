# ADR 0030: 語の頭のアポストロフィを、行頭禁則の終わり括弧類として扱わない

ステータス: 採択（未実装）

## 文脈

[golem-layout ADR 0028](0028-kinsoku-across-spaces-and-explicit-hyphens.md) は、行頭禁則と行末禁則を、語間の空白をまたいで当てると決めた。
その実装（[#670](https://github.com/tett23/golem/pull/670)）で、英語の本の行の分け方が変わった。
『テンペスト』の p.43 と『ウィンザーの陽気な女房たち』（`pd-merry-wives`）の p.60 と p.66 で、`’tis` や `’s` のようにアポストロフィで始まる語が、空白の後で行を始めなくなった。

英語の組版では、`’tis`（it is）、`’em`（them）、`’90s` のように、語の頭の字を略した印のアポストロフィで行を始めてよい。
二つの fixture には、こうした語が多い（`’tis` と `’Tis` が 67、`’em` が 19 など）。

### アポストロフィと閉じの一重引用符は、同じ字である

英語の原稿は、アポストロフィにも閉じの一重引用符にも U+2019（`’`）を使う。
Unicode も、アポストロフィには U+2019 を推奨している。
Golem の文字クラスの表は、区間の外の `’` を終わり括弧類にする（[`charClass`](https://github.com/tett23/golem/blob/6380b99853307e4d4f3e35e8a448a84ce879412d/modules/golem-layout/src/Golem/Layout/CharClass.hs#L41)）。
欧文の区間でも、禁則の判定は両用の字をその字の和文の文字クラスで引き（[`breakClass`](https://github.com/tett23/golem/blob/6380b99853307e4d4f3e35e8a448a84ce879412d/modules/golem-layout/src/Golem/Layout/Japanese.hs#L1228)、[docs/adr/0211](../../adr/0211-record-what-implementations-decided-found-by-the-review-of-2026-11-08.md)）、`’` は終わり括弧類になる（[`dualJapaneseClass`](https://github.com/tett23/golem/blob/6380b99853307e4d4f3e35e8a448a84ce879412d/modules/golem-layout/src/Golem/Layout/CharClass.hs#L88-L93)）。
終わり括弧類は行頭禁則の文字なので、`’tis` の前の空白は、[`normalize`](https://github.com/tett23/golem/blob/6380b99853307e4d4f3e35e8a448a84ce879412d/modules/golem-layout/src/Golem/Layout/Japanese.hs#L1160-L1168) で分割の候補でなくなる。

テストの送りの表（golem-layout のテストの `LineBreakEnum`）で、次のとおりに確かめた（2026-11-08、origin/main の 6380b998）。

- 2 字の行に `aaa ’tis` を組むと、行は `aaa’tis` の一つで、行長からはみ出す。`aaa tis` は `aaa` と `tis` の二行になる。
- 項目は `aaa`、罰点 10000、空白のグルー、`’tis` であり、空白の前に分割を禁じる罰点が入る。
- `[lang en]` の区間でも同じである。`’90` も同じく分けない。

二つの fixture の行が詰まる程度で済んだのは、空白がほかにもある行だったからである。
ほかに空白のない短い行では、はみ出す行になる。

### 閉じの一重引用符が空白の後の語の頭に来ることは、ほとんどない

英語の閉じ引用符は、前の語に付けて書く（`‘Hello,’ she said`）。
Golem も、区間の外の引用符を隣の欧文の語の箱に含める（[`isJoiner`](https://github.com/tett23/golem/blob/6380b99853307e4d4f3e35e8a448a84ce879412d/modules/golem-layout/src/Golem/Layout/Japanese.hs#L605)）。
そのため、空白の後の語の最初の字が `’` で、その次が字か数字なら、それは語の頭を略したアポストロフィと読める。
閉じ引用符を空白の後に離して書いた原稿（`a ’`）では、`’` の次に字がない。
[golem-layout ADR 0028](0028-kinsoku-across-spaces-and-explicit-hyphens.md) の K5 のテスト（`a ”` を `a”` に組む）は、この形を確かめている。

### 本の言語では分けられない

[docs/adr/0187](../../adr/0187-inline-language-switch.md) は、区間の外の両用の字の扱いを最も近い字で決め、本の言語（`manifest.toml` の `[metadata] language`）を見ないと決めた。
アポストロフィの問題は、英語の本だけで起きるのではない。
日本語の本の区間の外に英語の引用を書いても、`’tis` は同じく行を始めない。
逆に、本の言語が英語なら禁則を当てないとすると、英語の本のフランス語の区間の `« Bonjour »` の空白で分けるようになり、[golem-layout ADR 0028](0028-kinsoku-across-spaces-and-explicit-hyphens.md) の「トレードオフ」の判断と食い違う。

## 実装すること

### 1. 語の頭のアポストロフィは、禁則の判定で欧文の字とする

`normalize` の禁則の判定で、次の三つを満たす字を、文字クラスの欧文（`Western`）として扱う。

- 字は U+2019 である。
- 字は欧文の語の箱（`bcExpandable` の箱）の最初の字である。
- 箱の中の次の字が、字か数字（Unicode の一般カテゴリが L か Nd）である。結合文字は、今のとおり前の字と一つの単位として飛ばす。

区間の外と欧文の区間で同じ規則を当てる。
和文の区間の `’` は欧文の語の箱に入らないので、この規則に当たらず、今のとおり終わり括弧類である。

変えるのは、`breakClass` が箱の最初の字に返す文字クラスだけである。
空白をまたぐ判定（`prohibitedAcross`）と、隣り合う二つの箱のあいだの判定（`between`）の両方が、この文字クラスを使う。
`charClass`、`charClassIn`、`dualCharacters` の表は変えない。

### 2. 文書

- 仕様書の「行分割」の節の禁則の段落に、「欧文の語の箱の最初の字が U+2019 で、次の字が字か数字なら、その字は語の頭のアポストロフィとし、行頭禁則を当てない」と、この ADR へのリンクを足す。
- 仕様書の「両用の文字」の節の、欧文の区間の改行の文に、同じ例外を足す。
- 利用者のマニュアルに禁則の文字の一覧を書いた箇所があれば、同じ例外を足す。

### 3. 出力の変化

`’tis` のような語を空白の後に書いた段落だけが変わる。
『テンペスト』の p.43 と `pd-merry-wives` の p.60 と p.66 は、[golem-layout ADR 0028](0028-kinsoku-across-spaces-and-explicit-hyphens.md) の前の組み方に戻る見込みである。
実装のプルリクエストで、golden、`scripts/visual/` の参照、二つのマニュアルと complex fixture の決定性のハッシュが変わるかを確かめ、説明に書く。

## 実装しないこと

- **アポストロフィの書体**：日本語の書体を持つ本の区間の外の `’tis` は、`’` を和文の書体で描く（golem-typeset の [`fontFor`](https://github.com/tett23/golem/blob/6380b99853307e4d4f3e35e8a448a84ce879412d/modules/golem-typeset/src/Golem/Typeset/FontProvider.hs#L158-L161) は、区間の外の字の書体を `charClass` で選ぶ）。語の最初の字が両用の字の語の書体は、[docs/adr/0222](../../adr/0222-line-breaking-points-the-invariants-did-not-decide.md) の「メンテナーが決めること」の 6 で別の ADR にすると決めた点であり、ここでは変えない。
- **語の中と語の末尾の `’`**：`I’ll` の `’` は箱の中にあり、禁則の判定に来ない。`dogs’` の `’` は箱の最後の字で、行末禁則は始め括弧類にだけ当たるので、今も分割を妨げない。
- **U+2018 で書いた略の印**：`‘tis` は始め括弧類で始まる語であり、行頭禁則に当たらない。
- **列挙の部品**：[docs/adr/0209](../../adr/0209-line-breaking-invariants-by-exhaustive-small-inputs.md) の列挙の部品に `’` と `’tis` を足さない。部品を増やすと、段 3 の入力の数と毎晩の実行時間が増える。手で選んだ段落のテストで確かめる。
- **本の言語による切り替え**：本の言語は、今のとおり禁則に使わない（「メンテナーが決めること」の 1）。

## 不変条件

行の幅を W とする。
「語の頭のアポストロフィ」は、欧文の語の箱の最初の字の U+2019 で、箱の中の次の単位の最初の字が一般カテゴリ L か Nd のものとする。

- **A1**：語の頭のアポストロフィで始まる箱の前の語間の空白は、前の箱の最後の字が始め括弧類でなければ、分割の候補である。
- **A2**：語の頭のアポストロフィで始まる箱と、その前の隣り合う箱のあいだの禁則は、アポストロフィを欧文の字として判定する。
- **A3**：箱の最初の U+2019 の次の単位が字でも数字でもない（`’`、`”`、`.`、箱の終わり）なら、その字は今のとおり終わり括弧類である。
- **A4**：和文の区間の `’` は、今のとおり終わり括弧類である。
- **A5**：A1 から A3 の判定は、本の言語に依らない。
- **A6**：A1 に当たらない空白と、語の頭のアポストロフィで始まらない箱の項目は、この ADR の前と同じである。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| `’` の後の字 | 欧文の字（`’tis`）、大文字（`’Tis`）、数字（`’90`）、結合文字の付いた字、`’`、`”`、`.`、なし（`’` だけの語） |
| `’` の位置 | 箱の最初、箱の中（`I’ll`）、箱の最後（`dogs’`） |
| 区間の言語 | なし、`en`、`fr`、`ja` |
| 前の項目 | 語間の空白、和文の字の箱（空白なし）、始め括弧類で終わる箱と空白 |
| 本の言語 | `en`、`ja` |
| 行の残りの幅 | `’tis` の前でちょうど終わる、`’tis` の最初の字で足りない |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
テストの名前には、A1 から A6 の番号を入れる。

- **A1**：`LineBreakingSpec` で、2 字の行に `aaa ’tis` を組むと、`aaa` と `’tis` の二行になること。区間の外と `[lang en]` で確かめる。今は `aaa’tis` の一行になるので失敗する。`aaa ’90` も同じ。
- **A2**：`あ’tis` の `あ` と `’tis` のあいだに、分割を禁じる罰点がないこと。
- **A3**：`aaa ’`、`aaa ’”`、`aaa ’.` の `’` の前の空白が、今のとおり分割の候補でないこと。
- **A4**：`[lang ja]` の区間の `aaa ’tis` で、`’` の前で分けないこと（今の振る舞い）。
- **A5**：golem-driver のテストで、本の言語が `en` と `ja` の二つのプロジェクトに同じ段落を組み、行の分け方が同じであること。
- **A6**：[golem-layout ADR 0028](0028-kinsoku-across-spaces-and-explicit-hyphens.md) の K1 から K7 のテストが、そのまま通ること。
- 列挙：段 2 までのすべての入力のテストが、そのまま通ること。

## トレードオフ

字の文字クラスを、字だけでなく箱の中の次の字で決めることになる。
禁則の判定のほかの箇所（文字クラスの表、和欧間の空き、突き出し）は字だけで決めるので、文脈を見る箇所が一つ増える。
ただ、U+2019 がアポストロフィか引用符かは、字だけでは決まらない。
文脈を見ない限り、どちらかの用法を誤って組むことになる。

閉じの一重引用符を、空白の後に離して、次の語に付けて書いた原稿（`‘a ’b`）は、`’` をアポストロフィと読み、行頭に来うる。
英語の正書法にない書き方であり、そう書いた原稿の意図を推し量る規則は作らない。

## メンテナーが決めること

1. **アポストロフィと閉じの一重引用符を、どう見分けるか**：推奨は、欧文の語の箱の最初の U+2019 で、次の字が字か数字のものをアポストロフィとし、禁則の判定で欧文の字とすることである。英語の閉じ引用符は前の語に付くので、空白の後の語の頭には来ない。本の言語を見ないので、日本語の本の区間の外の英語にも同じく当たる。
   - 退けた案の一つは、本の言語が `ja` でない本では、区間の外の両用の字の禁則を当てないことである。日本語の本の中の英語の `’tis` は直らない。[docs/adr/0187](../../adr/0187-inline-language-switch.md) の「区間の外では本の言語を見ない」とも食い違う。
   - 二つめは、欧文の語の箱どうしのあいだの空白に、禁則を当てないことである。フランス語の区間の `« Bonjour »` の内側の空白で分けるようになり、[golem-layout ADR 0028](0028-kinsoku-across-spaces-and-explicit-hyphens.md) の K5 と「トレードオフ」の判断を覆す。
   - 三つめは、今のままとし、アポストロフィを U+02BC（MODIFIER LETTER APOSTROPHE）で書くよう書き手に求めることである。Unicode が推奨するのは U+2019 であり、パブリックドメインの原稿もそう書いている。書体が U+02BC を持たない場合もある。
2. **次の字に数えるもの**：推奨は、一般カテゴリ L と Nd である。`’90s` のように、年の略も英語の慣用である。
   - 退けた案は、L だけとすることである。`’90s` が行を始められない。
3. **和文の区間の `’`**：推奨は、今のとおり終わり括弧類とすることである。和文の区間は、書き手が両用の字を和文の約物として組むよう指定した区間である（[docs/adr/0187](../../adr/0187-inline-language-switch.md)）。
   - 退けた案は、和文の区間でも次の字で見分けることである。書き手の指定を、字の並びで覆すことになる。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-08、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- The Unicode Standard, Version 15.1, 6.2 General Punctuation（Apostrophes）。https://www.unicode.org/versions/Unicode15.1.0/
- [docs/adr/0187](../../adr/0187-inline-language-switch.md)、[docs/adr/0209](../../adr/0209-line-breaking-invariants-by-exhaustive-small-inputs.md)、[docs/adr/0211](../../adr/0211-record-what-implementations-decided-found-by-the-review-of-2026-11-08.md)、[docs/adr/0222](../../adr/0222-line-breaking-points-the-invariants-did-not-decide.md)
- [golem-layout ADR 0008](0008-explicit-hyphens.md)、[golem-layout ADR 0028](0028-kinsoku-across-spaces-and-explicit-hyphens.md)
- [#670](https://github.com/tett23/golem/pull/670) の説明（「Output changes」）
