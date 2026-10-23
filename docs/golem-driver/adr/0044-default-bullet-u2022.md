# ADR 0044: 箇条書きの既定の印を、PDF と CSS では「•」にする

ステータス: 採択

## 文脈

`style.toml` に `[lists]` を書かない本の箇条書きの印は、本の言語によらず「・」（U+30FB）である（[ADR 0013](0013-list-indents.md)、golem-project の `defaultListStyle`）。
`[lists]` を書いても `bullets` を書かなければ、同じく「・」になる。
「・」は和文の中点であり、欧文の書体の多くはこの字形を持たない。
欧文の書体だけで組む英語の本では、箇条書きの印が豆腐（.notdef の箱）になる。

### 確かめたこと

2026-10-23 に `~/.local/bin/golem`（0.1.0-rc2）で確かめた。

tempest の fixture（`language = "en"`、`[fonts.body]` は `latin` の Source Serif の可変フォントだけ）の `golem preflight` は、G09002 を一つ出した。
字は U+30FB「・」で、位置は最初の箇条書きの項目（[tempest.gm の 4 行め](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/fixtures/tempest/tempest.gm#L4)）である。
原稿に「・」はない。
草稿の [docs/adr/0081](../../adr/0081-missing-glyphs-warn-in-build.md) によれば、merry-wives も同じ字で G09002 を出す。

同じ fixture の `style.toml` に `[lists] bullets = [...]` を足し、印の候補ごとに `golem preflight` を走らせた。

| 印 | G09002 |
| --- | --- |
| U+2022「•」 | 出ない |
| U+00B7「·」 | 出ない |
| U+2013「–」 | 出ない |
| U+25E6「◦」 | 出る |
| U+25AA「▪」 | 出る |

ほかのターゲットの既定の印は次のとおりだった（`golem new --language en` の雛形に箇条書きを二項目足して組んだ）。

- プレーンテキストは、項目を `・one` のように「・」で始める。golem-driver の `textLists` が、PDF と同じ `lsBullets` を golem-text に渡すためである。
- HTML と EPUB は、`ul` に class も `list-style-type` も付けない。印は読書環境の既定であり、Golem は字を選ばない。`[lists]` を書いた本でだけ、`@counter-style` に印の文字列を書く（golem-driver の `hcLists`）。
- tempest に `[lists] numbers = ["{n}."]` だけを足すと、HTML の CSS に `@counter-style golem-ul-1 { system: cyclic; symbols: "・"; ... }` が出た。番号の書式を変えただけで、HTML の箇条書きの印も「・」に変わる。

### 印の書体の役割

PDF は、印を項目の一行目の先頭の文字として組む（[`Golem.Driver.Pdf` の `listMarker`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/src/Golem/Driver/Pdf.hs#L1723-L1730)）。
字を欧文の書体と和文の書体のどちらで組むかは、golem-layout の `charClass` が `Western` を返すかで決まる。
`Western` は ASCII、U+00A0 から U+024F、ギリシア文字とキリル文字（U+0370 から U+04FF）である。
U+2022 はこの範囲の外にあり、和文の書体と欧文の書体を持つ役割では和文の書体で組む。

これを、tempest の `[fonts.body]` に `ja` を足して確かめた。
`ja` を golem-font のテストの Source Han Sans のサブセット（U+2022 を持たない）にして `bullets = ["•"]` を書くと、G09002 は U+2022 をそのサブセットのフォントのファイルについて出した。
`ja` を Noto Serif JP（蟹工船の fixture のフォント）にすると出なかった。
和文の書体を持たない tempest の役割では、上の表のとおり U+2022 は豆腐にならなかった。

テストと CI で使うフォントの cmap も読んだ。
U+2022 を持たないのは、Source Han Sans のサブセット（[modules/golem-font/test/fonts/SourceHanSans-Regular_subset.otf](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-font/test/fonts/SourceHanSans-Regular_subset.otf)）だけだった。
Noto Serif JP、Source Serif の可変フォント、Source Serif 4、Source Sans Pro は U+2022 を持つ。
Noto Serif JP の U+2022 の送りは 336/1000 で、全角ではない。

### 印の字の選び方

メンテナーは、InDesign の箇条書きの既定の印を、U+2022 か、それに見える字だと考えている。
今の版の InDesign が手元になく、これは確かめていない。
U+2022 は Unicode の名前が BULLET の字であり、箇条書きの印として符号化された字である。
PDF と CSS の印を U+2022 にそろえれば、日本語の本と英語の本で既定を分ける必要はなく、本の言語を判定せずに済む。

プレーンテキストには、U+2022 を箇条書きの印に使う慣習がない。
プレーンテキストは書体を使わないので、今の「・」が豆腐になることもない。
プレーンテキストの既定は「・」のまま残す。

### 印を変える手段

U+2022 を持たない書体はある（上の Source Han Sans のサブセット）。
その書体で組む書き手は、印を別の字に変えられなければならない。

`[lists]` の `bullets` は、今すでに三つの経路の印を決める。

- PDF は [`listMarker`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/src/Golem/Driver/Pdf.hs#L1730) で `lsBullets` を読む。
- HTML と EPUB は、`[lists]` を書いた本で [`hcLists`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/src/Golem/Driver.hs#L979-L981) が `lsBullets` を `@counter-style` に書く。ただし、`[lists]` の値が既定と等しい本（`bullets = ["・"]` だけを書いた本）では、CSS を書かない（`stLists style == defaultListStyle` の判定）。
- プレーンテキストは [`textLists`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/src/Golem/Driver.hs#L1063-L1068) が `lsBullets` を golem-text に渡す。

仕様書の `[lists]` の節（[docs/specifications.md](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/docs/specifications.md?plain=1#L1352-L1396)）も、`bullets` を経路を問わない印として書いている。
新しいキーを足さなくても、印は `style.toml` で変えられる。
ただし `bullets` は一つで、プレーンテキストの印だけを PDF と別に変える手段はない。

## 実装すること

### 既定の印

`bullets` を書かない本の箇条書きの印を、経路で決める。
本の言語は見ない。

- PDF は `["•"]`（U+2022）とする。
- HTML と EPUB は、`[lists]` を書いて `bullets` を書かない本で、`@counter-style golem-ul-<深さ>` の `symbols` に `"•"` を書く。`[lists]` を書かない本では、今と同じく `ul` に `list-style-type` を当てず、印は読書環境の既定のままとする。
- プレーンテキストは、今と同じく `["・"]` とする。

`bullets` を書いた本は、どの経路でも書いた印を使う。
プレーンテキストだけの印のキーは足さない。
既定が経路で分かれるのは書き手が何も書かないときだけであり、書き手が字を選んだなら、どの経路でも同じ字で組むのが自然である。

### 型と値の決め方

- golem-project の `ListStyle` の `lsBullets` を `Maybe (NonEmpty Text)` にする。`[lists]` がない本と、`[lists]` に `bullets` がない本では `Nothing` とする。`lsNumbers` が組み方向で決まる既定を `Nothing` で表すのと同じ形である。`bullets` を書いた本は `Just` になって `defaultListStyle` と等しくならないので、`hcLists` は書いた値を必ず CSS に書く。
- golem-driver に、`ListStyle` から深さごとの印を求める関数を、PDF と CSS の既定（`"•"`）とプレーンテキストの既定（`"・"`）の二つの値で置く。PDF（`listMarker` と、印の幅 M を求める `listWidths`）と HTML と EPUB（`hcLists`）は前者を、プレーンテキスト（`textLists`）は後者を使う。
- 空き G の規則は変えない。「•」は全角の字面の外に空きを持つ約物ではないので、`gap` を書かなければ G は `fs / 2` になる。

### ドキュメント

- 仕様書（docs/specifications.md）の `[lists]` の節の `bullets` の既定を「PDF と、`[lists]` を書いた本の HTML と EPUB の `@counter-style` では `["•"]`、プレーンテキストでは `["・"]`」に改め、この ADR へのリンクを付ける。`bullets` を書けばすべての経路がその値を使うことと、U+2022 を持たない書体では `bullets` で印を変えることを書く。同じ節の「`[lists]` を書かない本の HTML、EPUB、プレーンテキストの出力は変わらない」は、今も成り立つので残す。
- 記法の仕様（docs/markup.md）の箇条書きの節の「項目の印（既定は `・`）」を `•` に改める。
- 利用者のマニュアルの付録 C（`manual/appendices/c-style.gm`）の `[lists]` の表の `bullets` の既定を、仕様書と同じく経路ごとに書く。
- 次のコミット済みの ADR のステータスの行に、この ADR へのリンクを書き足す。
  - [ADR 0013](0013-list-indents.md)：「採択→`bullets` の既定は [ADR 0044](0044-default-bullet-u2022.md)」。
- docs/diagnostics.md は変えない。新しいコードを足さないからである。

## 実装しないこと

- 本の言語で既定を変えること。言語の判定の関数も公開しない。
- `charClass` で U+2022 を `Western` にすること。和文の書体と欧文の書体を持つ役割で U+2022 を和文の書体から組むのは今の振る舞いであり、印に限らず原稿の U+2022 にも当たる。変えれば日本語の本の本文の組みも変わるので、別の ADR で扱う。
- 二段目より深いリストの既定の印を変えること。既定は一つの要素の配列のままとし、入れ子でも同じ印を使う。上の表のとおり、Source Serif は「◦」と「▪」を持たない。
- プレーンテキストだけの印を `style.toml` に書けるようにすること。
- HTML と EPUB の `[lists]` を書かない本の出力を変えること。

## テスト設計

実装の前に次のテストを書き、今の実装で失敗することを確かめる。

- golem-project の [test/Main.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-project/test/Main.hs)：`[lists]` がない `style.toml` と、`[lists] numbers = ["{n}."]` だけの `style.toml` で、`lsBullets` が `Nothing` であること。`bullets = ["・", "◦"]` では `Just ("・" :| ["◦"])` であること。今は型が違うのでコンパイルが通らない（[972 行め](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-project/test/Main.hs#L972) と [979 行め](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-project/test/Main.hs#L979) のテストを書き換える）。
- golem-driver の [test/ParagraphSpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/ParagraphSpec.hs)：`[lists]` のない版面に `- い` を組むと、`language = "ja"` の本でも `language = "en"` の本でも、印の箱の文字が `["•", ""]` であること。今は `["・", ""]` なので失敗する。`bullets = ["・"]` を書いた本では `["・", ""]` であること。
- 同じ本で、`fakeFonts`（U+2000 以上の字は一字）の印の幅 M が 2 字であること（w が 1 字、G が `fs / 2`）。今は 1 字なので失敗する。
- golem-driver の [test/BuildSpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/BuildSpec.hs)：`language = "en"` の本と `language = "ja"` の本を横組みのプレーンテキストに組むと、箇条書きの項目が今と同じ `・one` で始まること（今の実装でも通る）。`bullets = ["-"]` を書いた本では `- one` で始まること（今の実装でも通る）。
- 同じ [test/BuildSpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/BuildSpec.hs)：`[lists] numbers = ["{n}."]` だけの本の HTML の CSS に、`language = "ja"` でも `"en"` でも `symbols: "•"` があること。今は `"・"` なので失敗する。`bullets = ["・"]` だけを書いた本の CSS に `symbols: "・"` があること。今は CSS を書かないので失敗する。`[lists]` のない本の CSS に `@counter-style` がないこと（今の実装でも通る）。
- 出力のゴールデン：[modules/golem-driver/test/golden/pdf-sample.txt](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/golden/pdf-sample.txt) は、sample の fixture（`language = "ja"`、縦組み）の [chapters/01.gm の箇条書き](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/fixtures/sample/chapters/01.gm#L15-L16) を Noto Serif JP で組むので、印のグリフが変わる。G が 0 から `fs / 2` に変わるので、M と項目の本文の位置も変わりうる。実装のプルリクエストでゴールデンを作り直し、変わったのが箇条書きの印と項目の位置だけであることを差分で確かめる。sample と figures の fixture は `[lists]` を書かないので、epub-sample.txt、epub-figures.txt、html-style.css、プレーンテキストのゴールデンは変わらない。pdf-figures.txt は、figures の fixture に箇条書きがないので変わらない。
- 自動のテストにしないもの：実装のプルリクエストで、tempest の fixture の `golem preflight` が U+30FB の G09002 を出さないことを確かめる。[docs/adr/0081](../../adr/0081-missing-glyphs-warn-in-build.md) を先に実装していれば、`golem build --target pdf` が U+30FB の G08100 を出さないことも確かめる。

## トレードオフ

日本語の本の PDF の箇条書きの印も、「・」から「•」に変わる。
CI の入力では、sample の fixture、二冊のマニュアル、箇条書きを持つパブリックドメインの本の PDF が変わる。
[scripts/determinism.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/determinism.sh) と [scripts/env-determinism/check.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/env-determinism/check.sh) は同じコミットの出力を比べるので、この変更で失敗しない。

「•」は全角の字面の外に空きを持つ約物ではないので、`gap` を書かない本の G は 0 から `fs / 2` になる。
M は w と G の和を全角の字の単位に切り上げるので、書体と組み方向によっては、今の 1 字から 2 字に広がる。
日本語の本の箇条書きの字下げが深くなる場合がある。

U+2022 は、和文の書体と欧文の書体を持つ役割では和文の書体から組まれる。
和文の書体が U+2022 を持たなければ、日本語の本でも印が豆腐になる。
テストのフォントでは Source Han Sans のサブセットがこれにあたる。
[scripts/determinism.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/determinism.sh) の PDF の入力は、sample の fixture をこのサブセットで組むので、印が豆腐になる。
[docs/adr/0081](../../adr/0081-missing-glyphs-warn-in-build.md) は、この入力の和文のフォントを Noto Serif JP に替える。
この ADR を先に実装する場合も、同じ替え方をこの ADR のプルリクエストで行う。
0081 を実装した後は、U+2022 を持たないフォントで組むと、`golem build` が G08100 を出す（dev では warning、prod ではエラー）。
golem-driver のテストのうち、このサブセットで箇条書きを組み、diagnostics を一つずつ断言するテストは、G08100 が加わって落ちる。
そのテストは、U+2022 を持つフォントに替えるか、`bullets` を書いて直す。
書き手も同じく、G08100 を見て `bullets` に書体が持つ字を書けば直せる。

プレーンテキストの既定だけが「・」なので、`bullets` を書かない本では、PDF と HTML の印とプレーンテキストの印が食い違う。
プレーンテキストに U+2022 の慣習がないことを、経路のあいだの一致より優先した。

## 参考文献

- [ADR 0013](0013-list-indents.md)
- [golem-text ADR 0001](../../golem-text/adr/0001-plain-text-output.md)
- [docs/adr/0081](../../adr/0081-missing-glyphs-warn-in-build.md)（草稿）
- Unicode Character Database、U+2022 BULLET、U+30FB KATAKANA MIDDLE DOT
