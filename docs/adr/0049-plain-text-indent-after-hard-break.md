# ADR 0049: プレーンテキストで、強制改行の後の行に一行目の字下げを掛けない

ステータス: 採択（未実装）

## 文脈

[ADR 0016](0016-hard-line-breaks.md) は、`line-breaks = "join"` の段落の強制改行の後の行に、一行目の字下げを掛けないと決めた。
`keep` の段落（韻文）の行は、行ごとに一行目の字下げを掛ける。
同じ ADR は、プレーンテキストについて「変えない」とし、段落の一行目の字下げ（`textFirstLine`）は最初の行にだけ掛かると書いた。

この記述は、当時のコードと合っていなかった。
`Golem.Text.block` の `Paragraph` は、段落を `LineBreak` で行に分け、分けた各行の先頭に同じ数の全角の空白を置く（`modules/golem-text/src/Golem/Text.hs` の 117 行から 120 行）。
これは [ADR 0006](0006-paragraph-indent.md) の「`LineBreak` で区切った各部分の先頭にも置く」に従ったものである。
[ADR 0006](0006-paragraph-indent.md) を書いた時点では、`LineBreak` を生むのは `keep` の段落だけだった。
[ADR 0016](0016-hard-line-breaks.md) が `join` の段落にも `LineBreak` を置くようにした後も、プレーンテキストは段落スタイルの `line-breaks` を見ずに、すべての行に字下げを掛けている。

仕様書（[docs/specifications.md](../specifications.md) の 1292 行）は、コードに合わせて「段落の各行の先頭に置く」と書く。
一方、仕様書の「段落内の改行」の節（2023 行）、[markup.md](../markup.md) の 116 行、[docs/glossary.md](../glossary.md)、利用者のマニュアル（`manual/chapters/03-markup.gm` の 49 行）は、媒体を限らずに「強制改行の後の行には一行目の字下げを掛けない」と書く。

媒体ごとの今の振る舞いは次のとおりである。
`[paragraph-styles.body] first-line-indent = "1zw"` の本で、`東京都\` と `千代田区` の二行の段落を組んだ場合である。

| 媒体 | 一行目 | 強制改行の後の行 |
|---|---|---|
| PDF | 1 字下げる | `indent` の位置から始める（字下げしない） |
| HTML と EPUB | `text-indent` で 1 字下げる | `<br/>` の後なので `padding-inline-start`（`indent`）の位置から始める |
| プレーンテキスト | 全角の空白を一つ置く | 全角の空白を一つ置く |

プレーンテキストだけが、ほかの媒体と文書の両方に食い違う。
住所や署名のように強制改行で組む段落は、二行目以降が字下げされると、行の頭がそろわない。

## 実装すること

### 規則

プレーンテキストの段落の行の先頭に置く全角の空白の数を、次のように決める。
空白を置くのは、今と同じく、解決した `indent` と `first-line-indent` がどちらも `zw` で書かれている場合に限る。
どちらかが絶対の単位なら、どの行にも置かない。

| 段落 | 段落の最初の行 | `LineBreak` の後の行 |
|---|---|---|
| `keep` の段落 | `indent` と `first-line-indent` の和の整数部 | 最初の行と同じ |
| `join` の段落 | `indent` と `first-line-indent` の和の整数部 | `indent` の整数部 |

- 数が負なら 0 とする。`indent` と `first-line-indent` の和は G0312 で 0 以上に限られるが、`indent` だけなら負になりうる。
- `keep` の段落は今と変えない。原稿の一行が InDesign の一段落にあたるので、行ごとに一行目の字下げを掛ける（[ADR 0006](0006-paragraph-indent.md)）。
- `join` の段落の強制改行の後の行は、PDF と HTML と同じく、`indent` の位置から始める。プレーンテキストには行長がないので、折り返した行はない。
- リストの項目の中の段落には、今と同じく、どの行にも置かない。入れ子の字下げ（`indentBy ind`）は、今と同じく、すべての行の前に置く。
- 組み込みの `body` の段落スタイルは `indent` も `first-line-indent` も 0 なので、字下げを指定していない本の出力は変わらない。

### golem-driver

- `textFirstLine :: Style -> Maybe Text -> Int` を、`textIndents :: Style -> Maybe Text -> (Int, Int)` に改める。組の一つめは段落の最初の行の空白の数、二つめは `LineBreak` の後の行の空白の数である。
- 二つめは、解決した段落スタイルの `line-breaks` が `keep` なら一つめと同じ値、そうでなければ `max 0 (truncate indent)` とする。
- `line-breaks` を見るのは golem-driver の側だけにする。golem-text は二つの数を受け取るだけで、段落スタイルの `line-breaks` を知らない。

### golem-text

- `renderText` の引数 `firstLine :: FileId -> Maybe Text -> Int` を `FileId -> Maybe Text -> (Int, Int)` に改める。
- `Ctx` の `cFirstLine` も同じ型にする。
- `block` の `Paragraph` は、最初の行の前に一つめの数の空白を、`LineBreak` の後の各行の前に二つめの数の空白を置く。
- コメント（`each line starts with the first-line indent`）を、この ADR の規則に合わせて書き直す。

### ドキュメント

- 仕様書の「style.toml」の節の字下げの段落（1292 行）を、上の規則に書き直す。「各行の先頭に置く」を、`keep` の段落の各行と、`join` の段落の強制改行の後の行に分けて書き、この ADR へのリンクを付ける。
- 仕様書の「段落内の改行」の節の「HTML と EPUB では `<br/>` にし、プレーンテキストでは改行にする。」に、プレーンテキストでは強制改行の後の行の頭に `indent` の整数部の全角の空白を置くことを足す。
- markup.md、docs/glossary.md、利用者のマニュアルは、媒体を限らずに「強制改行の後の行には一行目の字下げを掛けない」と書いており、この ADR で正しくなる。変えない。
- [ADR 0016](0016-hard-line-breaks.md) のステータスの行を「採択→プレーンテキストの強制改行の後の行の字下げは [ADR 0049](0049-plain-text-indent-after-hard-break.md)」に改める。
- [ADR 0006](0006-paragraph-indent.md) のステータスの行を「採択→プレーンテキストで join の段落の LineBreak の後の行に置く空白は [ADR 0049](0049-plain-text-indent-after-hard-break.md)」に改める。

## 実装しないこと

- `keep` の段落の振る舞いを変えること。韻文の行ごとの字下げは、三つの媒体で今と同じである。
- `zw` 以外の単位で書いた字下げを、プレーンテキストで空白に換算すること。[ADR 0006](0006-paragraph-indent.md) のとおり、文字の大きさが決まらない媒体では字数に換算しない。
- 強制改行の後の行に、段落の一行目と別の字下げを指定する設定。[ADR 0016](0016-hard-line-breaks.md) の「実装しないこと」のとおりである。
- `indent` の小数部を、半角の空白などで表すこと。今の一行目の字下げと同じく、整数部だけを全角の空白で表す。

## テスト設計

先に書き、失敗させてから実装する。

### golem-driver（`test/ParagraphSpec.hs` のプレーンテキストの `text`）

- `[paragraph-styles.body] first-line-indent = "1zw"` の本で、`"東京都\\\n千代田区\n"` が `"　東京都\n千代田区\n"` になること。今は `"　東京都\n　千代田区\n"` になるので失敗する。
- `indent = "2zw"` と `first-line-indent = "1zw"` の本で、同じ原稿が `"　　　東京都\n　　千代田区\n"` になること。
- `indent = "-1zw"` と `first-line-indent = "2zw"` の本で、同じ原稿が `"　東京都\n千代田区\n"` になること（負の `indent` を 0 とする）。
- `indent = "2zw"` と `first-line-indent = "3mm"` の本で、同じ原稿の二行のどちらにも空白が付かないこと。
- `[paragraph-styles.verse] indent = "3zw"`、`first-line-indent = "-1zw"` の本で、`"@style verse\n  あ\n  い\n"` が `"　　あ\n　　い\n"` になること（`keep` の段落は今と同じ）。この項目は実装の前にも通る。
- `first-line-indent = "1zw"` の本の `"- 東京都\\\n  千代田区\n"` の項目に、どの行にも段落の字下げが付かないこと。この項目も実装の前に通る。

### golem-text（`test/TextOutputSpec.hs`）

- `renderText` に `(1, 0)` を返す関数を渡し、`[txt "一行目", LineBreak, txt "二行目"]` の段落が `"　一行目\n二行目\n"` になること。
- `(1, 1)` を渡すと `"　一行目\n　二行目\n"` になること。
- 既存のテスト（`const (const 0)` を渡すもの）は、`const (const (0, 0))` に書き換えて、出力が変わらないこと。

### 出力の一致

- `scripts/determinism.sh` の出力と、`tempest`、`kanikosen`、パブリックドメインの本、二つのマニュアルのプレーンテキストが、この ADR の前と変わらないこと。`join` の段落で強制改行と字下げを併用する原稿がないためである。変わった場合は、その原稿の段落を確かめてから golden を更新する。

## トレードオフ

プレーンテキストの出力が、[ADR 0016](0016-hard-line-breaks.md) と仕様書の「強制改行」の節、markup.md、利用者のマニュアルの記述に合う。
代わりに、仕様書の 1292 行の「各行」は書き直しになり、[ADR 0006](0006-paragraph-indent.md) の文の一部は `keep` の段落に限られる。

逆に、今のプレーンテキストの振る舞いを正として、[ADR 0016](0016-hard-line-breaks.md) の側を改める案も考えた。
プレーンテキストを読み物として読むとき、強制改行の後の行も字下げされていたほうが段落の切れ目がわかりやすい、という理由は立ちうる。
しかし、この案では、同じ原稿の同じ段落が、PDF と HTML では行の頭がそろい、プレーンテキストだけで二行目も下がる。
強制改行を使う段落（住所、署名、手紙の結び）は行の頭をそろえる用途が多く、プレーンテキストだけ違う見た目にする理由は弱い。
プレーンテキストでは段落のあいだに空行を一つ置くので、段落の切れ目は字下げに頼らなくてもわかる。
媒体のあいだの一致を優先し、プレーンテキストを [ADR 0016](0016-hard-line-breaks.md) にそろえる。

`line-breaks` を golem-driver の側で解決して二つの数にするので、golem-text の型は少し広がるが、段落スタイルの表を golem-text に渡さずに済む。
golem-text は段落スタイルを知らないという今の分け方を保てる。

## 参考文献

- [ADR 0006](0006-paragraph-indent.md)
- [ADR 0016](0016-hard-line-breaks.md)
