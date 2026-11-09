# ADR 0264: 目次の項目の書式

ステータス: 採択（未実装）

## 文脈

[ロードマップ](../roadmap.md) の v1.0.0 の「LaTeX との差を埋める項目」に、「目次の項目の書式」がある。
目次の階層ごとに段落スタイルを当て、書体、大きさ、字下げ、空きを変えられるようにする項目である。
[2026-10-17 の調査](../audits/2026-10-17-latex-gap-for-v1.md) の 10 が元であり、所有者は、この項目がなければ v1 とは呼べないとして v1.0.0 に置いた（同じ調査の「所有者の決定」）。

目次は本の顔の一つである。
章を太い書体で大きく、節を本文の書体で一段下げて、という組み方は和文の本にも欧文の本にも多い。
今の Golem では、どの階層の項目も同じ書体と大きさで組まれる。

### 今の PDF の目次

PDF の目次の項目は、段落スタイルを持たない単位である（[golem-driver ADR 0009](../golem-driver/adr/0009-pdf-toc-page-numbers.md)）。
`@toc` の各項目を `UTocEntry` の単位にし、本文の役割と版面の文字の大きさ fs の見た目（`bodyLook`）で組む（[`Flow.hs` の `@toc`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L1568)、[`plainUnit`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L1531)）。
階層 l の項目は、すべての行を (l − 1) × fs だけ字下げする（[`tocIndent`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L1797-L1805)）。
行の終わりの側には、ページ番号 999 を本文の見た目で組んだ幅 W に二字分を足した幅 R を予約する（[`tocGeometry`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L874-L879)）。
ページ番号は最後の行の段の端にそろえ、題とのあいだを三点リーダーで埋める。
`style.toml` で変えられるのは、`[toc]` の `leader`（`"dots"` か `"none"`）だけである（[`TocSec`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-project/src/Golem/Project/Style.hs#L1984-L1987)）。

HTML の本文の `@toc` と目次のページは、項目を `<li class="toc-<階層>">` にする（[`Html.hs` の `toc`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-html/src/Golem/Html.hs#L567-L582)）。
EPUB のナビゲーション文書も同じ項目の並びから作る（[golem-epub ADR 0002](../golem-epub/adr/0002-nav-and-toc-depth.md)）。
プレーンテキストの目次は題の一覧である。

### 組み込みの段落スタイル

組み込みの段落スタイルは `body`、`verse`、`caption`、`sidenote`、`code` の五つである（[`builtinParaStyles`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-project/src/Golem/Project/Style.hs#L519-L530)、仕様書の「style.toml」）。
`caption` と `sidenote` は、PDF の図版のキャプションと傍注の本文を組む段落スタイルであり、利用者は同じ名前の表を書いて上書きする。
組み込みの文字スタイルは `bold`、`italic`、`strong`、`code`、`url`、`note-mark` の六つであり、`note-mark` は注の印を組む既定の文字スタイルである（[ADR 0177](0177-note-mark-style-and-numerals.md)）。
スタイルの名前は、英小文字で始まり、英小文字、数字、`-` だけからなる。

### InDesign と LaTeX

InDesign は、目次スタイルで、目次に載せる段落スタイルごとに、項目のスタイル（段落スタイル）、レベル、ページ番号の位置と文字スタイル、項目とページ番号のあいだの文字と文字スタイルを決める。
リーダーは、項目の段落スタイルのタブのリーダーで描く。
出典は調査の 10 に挙げた Adobe のヘルプであり、本文は読めず、調査の抜粋による。

LaTeX は、tocloft と titletoc で、階層ごとの書体、字下げ、リーダー、ページ番号の書体を決める。

JLReq は、目次の版面を基本版面より小さくする例を挙げる（2.2 と 2.6.2）が、項目の書式は定めていない。
この ADR は、項目の書式を InDesign の方式（項目に段落スタイルを当てる）で決める。
新しく足すのは、組み込みのスタイルの名前だけになる。

### ほかの ADR との関係

目次のページ番号の値と書き方は [ADR 0260](0260-front-matter-folios-and-page-labels.md) が決める。
この ADR は [ADR 0260](0260-front-matter-folios-and-page-labels.md) の後に実装し、ページ番号はそのページラベルを書いた inline をそのまま組む。
段落スタイルを表のセルに当てることは [ADR 0262](0262-table-numbers-captions-column-widths-and-cell-styles.md) が決める。
どちらも、段落スタイルの欄の意味を変えずに、新しい場所に段落スタイルを当てる。
見出し、リストへの段落スタイルの適用は、v1.0.0 の「段落スタイルの拡張」に残る。

## 実装すること

### 組み込みのスタイル

組み込みの段落スタイルに `toc-1` から `toc-6` の六つを、組み込みの文字スタイルに `toc-page-number` を足す。

| 名前 | 種類 | 組み込みの定義 |
| --- | --- | --- |
| `toc-<l>`（l は 1 から 6） | 段落スタイル | `based-on = "body"`、`size = "1zw"`、`indent = "<l − 1>zw"`、`first-line-indent = "0zw"`、`end-indent = "0zw"` |
| `toc-page-number` | 文字スタイル | キーなし |

`toc-1` の `indent` は `"0zw"`、`toc-6` は `"5zw"` である。
組み込みの定義は、今の目次の形（版面の文字の大きさで、すべての行を (l − 1) 字下げし、行の終わりの側の字下げはない）を、段落スタイルの欄で書き直したものである。
`size` と字下げを書くのは、`body` に書いた大きさと字下げを目次に引き継がないためである。
ほかの欄（`font`、`align`、`aki-set`、`kerning`、`tracking`、`proportional-metrics`、`baseline-shift`、`regex-styles`）は `body` から引き継ぐ。

利用者は、ほかの組み込みのスタイルと同じく、同じ名前の表を書いて上書きする。

```toml
[paragraph-styles.toc-1]
font = "gothic"
space-before = 1

[paragraph-styles.toc-2]
indent = "2zw"

[character-styles.toc-page-number]
font = "gothic"
```

ファイルの先頭の `@style-def` でも上書きできる。
目次の項目は、`@toc` を書いたファイルのスタイル（`style.toml` にそのファイルの定義を重ねたもの）で組む。
原稿の段落に `@style toc-1` を書くこともでき、その段落はふつうの段落として組む。

### 段落スタイルを当てる

PDF の目次の階層 l の項目を、段落スタイル `toc-<l>` の段落として組む。
この ADR では、これを「項目に段落スタイルを当てる」と呼ぶ。
段落スタイルの欄は、本文の段落と同じ意味を持つ。

- 書体と大きさは、`font` と `size` で決める。`size` が版面の文字の大きさを超えれば、今と同じく G03011 とする。
- 字下げは、`indent`、`first-line-indent`、`end-indent` で決める。`first-line-indent` を負にすれば、折り返した行を下げる形になる。
- 項目の前後とあいだの空きは、`space-before`、`space-after`、`space-between` で決める。同じ階層の項目が続くときは `space-between` を使う。
- `rule-before` と `rule-after` を書けば、項目の前と後に罫線を引く（[golem-driver ADR 0027](../golem-driver/adr/0027-paragraph-style-rules.md)）。
- `line-breaks` は、題の中に段落内の改行がないので組版を変えない。

項目の中身（番号、区切り、短い題）と、リーダーの有無（`[toc]` の `leader`）は今と同じである。
リーダーの字は、項目の段落スタイルの見た目で組む。
InDesign のリーダーが項目の段落スタイルのタブで描かれるのと同じである。
ページ番号は、[ADR 0260](0260-front-matter-folios-and-page-labels.md) のページラベルを書いた inline を、文字スタイル `toc-page-number` で包み、項目の段落スタイルの見た目の上に組む。

### ページ番号の位置と予約の幅

ページ番号の終わりは、項目の段落スタイルの `end-indent` によらず、段の行長の端にそろえる。
`end-indent` は題の行だけを短くする。
ページ番号の位置を階層ごとに変えると、上下の項目の番号がそろわないからである。

予約の幅は、`@toc` の `depth` 以下の全階層で一つとする。

- W は、ページ番号 999 を、階層 l の項目の見た目に `toc-page-number` を重ねて組んだ幅の、l = 1 … `depth` の最大とする。
- 空き g は、今と同じく fs ÷ 2 とする。
- R は、今と同じく W + 2 × fs とする。
- 項目の行 k の長さは、段の行長から、行 k の字下げ（`indent`、一行めは `first-line-indent` を足す）、`end-indent`、R を引いた長さとする。

リーダーの終わりは、すべての階層で、段の行長から W と g を引いた位置になる。
階層ごとに文字の大きさが違っても、ページ番号が W に収まる限り、リーダーの終わりはそろう。
W より広いページ番号は、今の `tocPage` のとおりリーダーを縮めて置く。
W も R も実際のページ番号によらないので、目次の行分割がページ番号によらないという今の性質（[golem-driver ADR 0009](../golem-driver/adr/0009-pdf-toc-page-numbers.md)）は保たれる。

### 今の本の出力

`style.toml` と `@style-def` に `toc-1` から `toc-6` と `toc-page-number` を書かない本では、W、R、字下げ、大きさが今と同じになる。
ただし、`body` に `align`、`aki-set`、`regex-styles` など引き継ぐ欄を書いた本では、目次の項目にもその欄が適用され、PDF が変わりうる。
今の目次は `body` の文字の特徴（`kerning`、`tracking` など）を使い、段落としての欄を使っていないからである（[`styleLook`](https://github.com/tett23/golem/blob/87857c6e74c3494d5f23149101415cb566b2d850/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L1436-L1437)）。
実装のプルリクエストは、golem-driver の fixture と見本の本のすべてで、変更の前と後の PDF を比べ、変わった本と理由を説明に書く。
リリースノートの「変更」にも書く。

### HTML と EPUB

HTML の本文の `@toc` と目次のページ（`index.xhtml`）の項目 `<li class="toc-<l>">` には、`toc-<l>` の `font` があれば、ほかの段落スタイルと同じく `font-family` を書く（`nav.toc li.toc-<l> { font-family: ...; }`）。
`size`、字下げ、空き、罫線は書かない。
HTML と EPUB でそれらを使うことは、v2 の「Web 経路のスタイル」で扱う。
EPUB のナビゲーション文書には何も書かない。
読書システムは、ナビゲーション文書を自分の画面で示すことが多いからである。
`toc-page-number` は、ページ番号を出さない HTML と EPUB には現れない。

### プレーンテキスト

プレーンテキストは、どの欄も使わない。
目次は今と同じく題の一覧である。

### タグ付き PDF

目次の構造（`TOC` と `TOCI`、[ADR 0183](0183-tagged-pdf-and-pdf-a.md)）は変わらない。
`toc-page-number` は文字スタイルなので、構造の要素を足さない。
目次の項目を PDF のリンクにすることは [ADR 0267](0267-pdf-bookmarks-and-links-inside-the-document.md) が決める。

### diagnostics

コードの番号は、採択のときに、使われていない番号であり同じ時期の ADR と重ならないことを確かめて振り直した（「決めたことの記録」）。

- **G07117**（エラー）：目次の階層 l の項目の行の長さ（段の行長から、最も大きい行の字下げ、`end-indent`、R を引いた長さ）が、`toc-<l>` の文字の大きさの一字に満たない。`@toc` の `depth` 以下の階層で、その階層の項目が目次にあるときだけ、階層ごとに一つ出す。位置は、`style.toml` か `@style-def` に `toc-<l>` を書いていればその表、書いていなければ `@toc` の位置とする。PDF をターゲットに含むときだけ出し、PDF を書かない。字下げを大きく書いた設定で、題が一字も置けない行を黙って組まないためである。

ほかの誤り（未知のキー、範囲の外の値、`toc-<l>` に `background` を書くこと）は、ほかの段落スタイルと同じコードになる。

### 文書

実装のプルリクエストは、次の文書を直す。

- docs/specifications.md：「目次と文書構造の参照」の PDF の目次の段落を、項目に段落スタイルを当てる規則と予約の幅の規則に書き直す。「style.toml」の組み込みの段落スタイルと文字スタイルの一覧に `toc-1` から `toc-6` と `toc-page-number` を足す。
- docs/diagnostics.md：G07117 を足す。
- 使い手のマニュアル：目次の書式を変える例を、docs/manual-policy.md に従って置く。
- README：変えない。
- docs/roadmap.md：「LaTeX との差を埋める項目」の「目次の項目の書式」の項目を消す。v2 の「目次の拡張」から「`[toc]` の `font` と `size` による項目の書体と大きさ、階層ごとの書体の切り替え、字下げ、空き、」を消す。残るのは「章ごとの小目次（v1 の `@toc` は文書に一つだけ）、リーダーの字の設定、折り返した題のぶら下げ、図目次と表目次」である。v1.0.0 の「ページ番号と柱の拡張」の「柱とノンブルと目次の項目を見出しの書体で組むこと」を「柱とノンブルを見出しの書体で組むこと」にする（「メンテナーが決めること」の 6）。

## 実装しないこと

- **図目次、表目次、章ごとの小目次**：v2 の「目次の拡張」に残す。InDesign でも、図目次は別の目次スタイルで作る別の目次である。
- **リーダーの字の設定**：v2 の「目次の拡張」に残す。
- **番号の幅にそろえたぶら下げ**：折り返した題の行を、番号の後の題の始まりにそろえる組み方は、番号の幅で字下げが変わるので、v2 の「目次の拡張」に残す。`first-line-indent` を負にすれば、決まった幅のぶら下げは書ける。
- **目次の題の段落スタイル**：「目次」という見出しは利用者が書くふつうの見出しであり、この ADR は変えない。
- **見出し、リストへの段落スタイルの適用**：v1.0.0 の「段落スタイルの拡張」に残す。
- **階層と段落スタイルの対応を書く欄**：`[toc]` に階層ごとの段落スタイルの名前を書く欄は作らない（「メンテナーが決めること」の 1）。

## 不変条件

- **I1 書かない本は変わらない**：`toc-1` から `toc-6`、`toc-page-number` を書かず、`body` に組み込みの定義と違う欄を書かない本では、PDF のバイト列と diagnostics は今と同じである。
- **I2 階層とスタイル**：目次のどの項目も、階層 l なら段落スタイル `toc-<l>` の書体と大きさで組まれ、行 k の始まりは段の始まりから `toc-<l>` の行 k の字下げの位置にある。
- **I3 番号と重ならない**：目次のどの項目のどの行も、題の終わりが、段の行長から `end-indent` と R を引いた位置を超えない。
- **I4 リーダーの終わり**：ページ番号の幅が W 以下の二つの項目は、階層によらず、リーダーの終わりの位置が等しい。
- **I5 番号の終わり**：どの項目のページ番号も、終わりが段の行長の端にある。ページ番号が段に収まらないほど広い場合を除く。
- **I6 ページ番号によらない行分割**：目次のどの項目の行の数と行の中身も、ページラベルの値（[ADR 0260](0260-front-matter-folios-and-page-labels.md)）によらない。
- **I7 行の長さの検査**：G07117 が出るのは、`depth` 以下の階層 l の項目の行の長さが `toc-<l>` の一字に満たないときに限り、そのときは階層ごとにちょうど一つ出る。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| `depth` | 1、2、6 |
| 項目の数 | 0（載せる見出しがない）、1、階層ごとに 2 |
| 階層の大きさ | すべて `1zw`、`toc-1` だけ版面の文字の大きさの半分、階層ごとに違う |
| 題の長さ | 行にちょうど収まる、一字あふれる、三行 |
| 行の長さ | `toc-<l>` の一字ちょうど、一字より 1 sp 短い |
| ページ番号の幅 | W ちょうど、W より 1 sp 広い（[ADR 0260](0260-front-matter-folios-and-page-labels.md) の `xxviii` など） |
| `first-line-indent` | 0、正、負（ぶら下げ） |
| `end-indent` | 0、正 |
| `[toc]` の `leader` | `"dots"`、`"none"` |
| 組方向 | 横組み、縦組み |

## テスト設計

テストの名前に不変条件の番号を入れる。
テストは実装の前に書き、今のコードで落ちることを確かめる。
I1 と I6 のテストは今のコードでも通る。

- golem-project のテストで、組み込みの `toc-1` から `toc-6` と `toc-page-number` の定義と、利用者の表が書いたキーだけを上書きすることを確かめる。
- golem-typeset のテストで、上の表の入力を組み合わせた目次を組み、項目の行の配置から I2、I3、I4、I5 を確かめる。
- golem-typeset のテストで、同じ目次をページラベルの値を変えて二度組み、行の数と行の中身が等しいことを確かめる（I6）。
- golem-typeset のテストで、行の長さが一字ちょうどと、一字より 1 sp 短い設定について、G07117 の有無と数を確かめる（I7）。
- golem-driver のテストで、fixture のすべてについて、組み込みの定義だけの本の PDF が今のバイト列と等しいことを確かめる（I1）。`body` に引き継ぐ欄を書いた fixture は、実装のプルリクエストで差を説明する。
- golem-html のテストで、`toc-1` に `font` を書いた本の `style.css` に `nav.toc li.toc-1` の `font-family` があり、書かない本にないことを確かめる。

## トレードオフ

- 組み込みの名前が七つ増える。`toc-1` などを自分で定義していた本では、その定義が組み込みの上書きになり、目次の組み方が変わる。名前の規則は英小文字と数字と `-` なので、この衝突は起こりうる。2026-11-09 の main（87857c6e）のリポジトリには、`toc-` で始まるスタイルを定義する fixture も見本もない。
- `toc-<l>` が `body` を引き継ぐので、`body` を変えると目次も変わる。目次の書体を本文と別に決めたいときは、`toc-<l>` に書く。引き継がない設計（`code` のように `body` を根にしない）にすると、和文のアキ量のセットなどを六つの階層すべてに書き写すことになる。
- 予約の幅を全階層の最大にすると、小さな階層の題の行は、自分の番号の幅より広い予約の分だけ短くなる。リーダーの終わりをそろえることを優先した。

## メンテナーが決めること

1. **段落スタイルの決め方**
   - 推奨：組み込みの名前 `toc-1` から `toc-6` を足し、利用者は同じ名前の表で上書きする。`caption` と `sidenote` と同じ方式で、新しい欄が要らない。
   - 退けた案：`[toc]` に `styles = ["chapter-toc", "section-toc"]` のように階層ごとの名前を書く。InDesign の方式に近いが、名前の対応という間接を一つ足し、書かない本の既定を別に決めることになる。
   - 退けた案：段落スタイル `toc` を一つ足し、階層ごとの字下げを処理系で足す。階層ごとに書体と大きさを変えられない。
2. **ページ番号の文字スタイル**
   - 推奨：組み込みの文字スタイル `toc-page-number` を足す。InDesign の目次スタイルにも、ページ番号の文字スタイルがある。
   - 退けた案：足さず、ページ番号を項目の段落スタイルのまま組む。ページ番号だけを欧文の書体や太字にする組み方が書けない。
3. **`toc-<l>` の親**
   - 推奨：`body` を親にし、`size` と字下げだけを組み込みの定義に書く。
   - 退けた案：`code` のように `body` を根にしない。アキ量のセットや正規表現スタイルを、階層の数だけ書き写すことになる。
4. **予約の幅**
   - 推奨：`depth` 以下の全階層で一つの W を使い、リーダーの終わりをそろえる。今の仕様の「上下の項目の点がそろう」を保つ。
   - 退けた案：階層ごとの W。階層ごとにリーダーの終わりがずれる。
5. **HTML と EPUB**
   - 推奨：本文の `@toc` と目次のページの項目に `font-family` だけを書き、ナビゲーション文書には書かない。ほかの段落スタイルの HTML での扱いと同じ範囲である。
   - 退けた案：何も書かない。段落スタイルの `font` を HTML に書くという今の媒体の扱いと食い違う。
   - 退けた案：`size`、字下げ、空きも書く。ほかの段落スタイルの `size` を HTML で使うことは v2 の「Web 経路のスタイル」にあり、目次だけを先に変えると扱いが分かれる。
6. **「ページ番号と柱の拡張」の目次の項目**
   - 推奨：v1.0.0 の「ページ番号と柱の拡張」の「柱とノンブルと目次の項目を見出しの書体で組むこと」から「と目次の項目」を消す。`toc-<l>` の `font` に見出しの書体の役割を書けば、目次の項目を見出しの書体で組めるからである。
   - 退けた案：消さずに残す。実装した機能が予定に残り、ロードマップが今の振る舞いと食い違う。

## 決めたことの記録

2026-11-09 に、tett23 がすべて推奨のとおりに決めた。

1. 段落スタイルは、推奨のとおり組み込みの名前 `toc-1` から `toc-6` を足し、利用者は同じ名前の表で上書きする。
2. ページ番号には、推奨のとおり組み込みの文字スタイル `toc-page-number` を足す。
3. `toc-<l>` は、推奨のとおり `body` を親にし、`size` と字下げだけを組み込みの定義に書く。
4. 予約の幅は、推奨のとおり `depth` 以下の全階層で一つの W を使う。
5. HTML と EPUB では、推奨のとおり本文の `@toc` と目次のページの項目に `font-family` だけを書き、ナビゲーション文書には書かない。
6. ロードマップの「ページ番号と柱の拡張」からは、推奨のとおり「と目次の項目」を消す。

diagnostic のコードは、採択のときに、docs/diagnostics.md と origin/main のコードで使われていない番号であり、同じ時期の ADR と重ならないことを確かめて、G07117 とした。
草案の仮の番号から振り直した。

## 参考文献

- [2026-10-17 の調査](../audits/2026-10-17-latex-gap-for-v1.md)（10 と「所有者の決定」）
- [ロードマップ](../roadmap.md)
- [仕様書](../specifications.md)
- [ADR 0177](0177-note-mark-style-and-numerals.md)、[ADR 0183](0183-tagged-pdf-and-pdf-a.md)、[ADR 0260](0260-front-matter-folios-and-page-labels.md)、[ADR 0262](0262-table-numbers-captions-column-widths-and-cell-styles.md)、[ADR 0267](0267-pdf-bookmarks-and-links-inside-the-document.md)
- [golem-driver ADR 0009](../golem-driver/adr/0009-pdf-toc-page-numbers.md)、[golem-driver ADR 0027](../golem-driver/adr/0027-paragraph-style-rules.md)、[golem-driver ADR 0043](../golem-driver/adr/0043-caption-sidenote-do-not-inherit-indent.md)
- [golem-epub ADR 0002](../golem-epub/adr/0002-nav-and-toc-depth.md)
- Adobe, InDesign User Guide, Customize table of contents styles, https://helpx.adobe.com/indesign/desktop/indexes-and-references/add-a-table-of-contents/customize-toc-style.html（本文は読めず、調査の抜粋による）
- Adobe, InDesign User Guide, Create multiple tables of contents, https://helpx.adobe.com/be_en/indesign/desktop/indexes-and-references/add-a-table-of-contents/create-multiple-tocs.html（同上）
- tocloft, https://ctan.org/pkg/tocloft
- titletoc, https://ctan.org/pkg/titletoc
- W3C, Requirements for Japanese Text Layout（JLReq）, 2.2、2.6.2, https://www.w3.org/TR/jlreq/
