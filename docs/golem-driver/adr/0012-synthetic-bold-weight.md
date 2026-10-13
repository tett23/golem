# ADR 0012: 合成の太字の線の幅を和文と欧文で分けて細くする

ステータス: 採択

## 文脈

この ADR は [docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md) の後に実装する。
合成の太字を和文と欧文の側ごとに表す仕組みを、その ADR に頼るためである。
以下の現状は、その ADR を実装した後の状態として書く。

[docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md) は、合成の太字と斜体を文字スタイルの欄（`synthetic-bold`、`synthetic-italic`）にし、組み込みの文字スタイル `bold` を `synthetic-bold = true`、`strong` を `based-on = "bold"` とする。
`synthetic-bold` が真の文字スタイルは、`font` の役割が持たない側の文字を合成の太字にし、`font` がなければ両側を合成の太字にする。
PDF の見た目（`Golem.Layout.Look.Look`）は、合成の太字と斜体を和文の側（`lkSynthetic`）と欧文の側（`lkLatinSynthetic`）の組で持つ。
`writeDocument` の `runsOf` は、二つの側の役割か合成の指定が異なれば、文字の並びを欧文の連続とそれ以外の連続に分け、`drawLine` は欧文の連続には `lkLatinSynthetic`、それ以外には `lkSynthetic` を使う。
したがって、`[bold: ...]` と `[strong: ...]` は、`[character-styles.bold]` に `font` を書かない限り、両側とも合成の太字で組まれる。

合成の太字は、字形を塗ったうえで輪郭を線でなぞる（`2 Tr` と `w`）。
線は輪郭の両側に半分ずつ広がるので、字形の各辺は線の幅の半分だけ外へ太り、縦画や横画の太さは線の幅の分だけ増える。
線の幅は、`Golem.Driver.Pdf.syntheticStroke` が文字の大きさの 1/40 を `div` で整数の sp にした値であり、和文の側と欧文の側で同じである。

この値は、目で見ると太すぎる（[仕様書の「v1 の実装で次の段階以降に回した項目」](../../specifications.md)）。
値を決め直すために、テストの fixture（`modules/golem-driver/test/fixtures/` の `tempest` と `kanikosen`）に太字の段落を足し、線の幅を変えて PDF を作り、画像にして見比べた。
手順は「テスト設計」の「目で確かめる手順」と同じである。

### 見比べた結果

和文は `kanikosen`（Noto Serif JP Regular、13Q、縦組み）、欧文は `tempest`（Source Serif の既定のインスタンス、10pt、横組み）で、線の幅を文字の大きさの 1/40、1/60、1/80、1/100、1/140 にした。
画像はおよそ 580dpi に相当する大きさで作った。

- 和文の 1/40 では、「鬱」「靈」「薔」のような画の多い字のふところが埋まり、字の形が読み取りにくい。
- 和文の 1/60 では、「鬱」と「靈」のふところがまだ一部埋まる。
- 和文の 1/80 では、ふところが開いたまま、隣の通常の字面との太さの違いがはっきり分かる。
- 和文の 1/100 では太さの違いが弱く、1/140 では通常の字面とほとんど区別できない。
- 欧文の 1/40 では、ふところは埋まらず、セミボールドに近い見え方になる。
- 欧文の 1/60 でも太字として十分に区別でき、1/80 では区別できるが弱く、1/100 では区別しにくい。

太すぎると感じる原因は、和文にある。
和文の字は一字の中に欧文よりはるかに多くの画を持ち、画と画の間のすきまが狭いので、同じ線の幅でも先にすきまが埋まる。
欧文だけを見れば 1/40 は破綻していない。

### ほかの実装の値

次の値は、各実装のソースの記憶にもとづくもので、この ADR を書く時点では確かめていない。
いずれも、線の幅に換算すると今の Golem の 1/40 と同じか、それより太い。

- Chrome が使う Skia は、合成の太字の輪郭を、文字の大きさの 1/24（9pt 以下）から 1/32（36pt 以上）を幅とする線で塗りと同時になぞる。間の大きさでは補間する。
- FreeType の `FT_GlyphSlot_Embolden` は、文字の大きさの 1/24 だけ字形を太らせる。
- macOS の WebKit は、字形を 1 ピクセルずらして二度描く。太りは文字の大きさに比例せず、画面の画素に固定される。
- InDesign は、フォントにない太さを合成する機能を持たない（記憶による）。和文で太字が要る場合に文字に線を付ける運用はあるが、標準の線の幅は決まっていない。

ブラウザーの値は、画面の低い解像度で、アンチエイリアスに細く見える字形を太らせるためのものだと考えられる（推測）。
印刷の解像度では字形の幾何がそのまま出るので、同じ比率でも画面より太く見える。
また、ブラウザーの値は欧文を基準にしていると考えられ、和文の画の密度を考えていない（推測）。
したがって、ほかの実装の値をそのまま使わず、上の見比べの結果から値を決める。

### 決めること

- 線の幅の値。
- 文字の大きさに比例させるか、固定の幅にするか。
- 和文と欧文で値を変えるか。
- `style.toml` で値を変える設定を持つか。[ADR 0004](0004-pdf-emphasis-and-character-styles.md) は持たないとし、[docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md) も文字スタイルの欄に線の幅を加えていない。

## 実装すること

### 値

合成の太字の線の幅を、文字の大きさに比例させ、和文と欧文で分ける。

| 文字 | 線の幅 | 各辺の太り | 10pt での線の幅 |
|---|---|---|---|
| 和文（欧文以外のすべて） | 文字の大きさの 1/80 | 1/160 | 0.125pt |
| 欧文（`charClass` が `Western`） | 文字の大きさの 1/60 | 1/120 | 約 0.1667pt |

- 比例させるのは、ふところが埋まるかどうかが、線の幅と画のすきまの比で決まるためである。画のすきまは文字の大きさに比例するので、比例させれば大きさによらず同じ見え方になる。画素に固定する方式は画面のためのもので、解像度を持たない PDF には当てはまらない。
- 和文と欧文の区別は、[docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md) の合成の側の区別と同じにする。欧文の値は `lkLatinSynthetic` の `synBold` で太らせる文字に、和文の値は `lkSynthetic` の `synBold` で太らせる文字に使う。側の判定は、行分割と描画が書体の切り替えに使っている判定（`charClass` が `Western` かどうか）である。和文のフォントの欧文の字形（`[fonts.body]` が `ja` だけを持つ場合の `ABC` など）も、欧文の側なので欧文の値で太らせる。
- 和文の値は、見比べで画の多い字のふところが開いていた最も太い値である。欧文の値は、太字としてはっきり区別できた最も細い値であり、和文と並んだときの太さの差を小さくする。

### 定数と関数（golem-driver）

`Golem.Driver.Pdf` の `syntheticStroke` を次のように変える。

```haskell
-- | The outline stroke of synthetic bold for Japanese: 1/80 of the size (golem-driver ADR 0012).
syntheticStrokeJa :: Rational
syntheticStrokeJa = 1 / 80

-- | The outline stroke of synthetic bold for Latin: 1/60 of the size.
syntheticStrokeLatin :: Rational
syntheticStrokeLatin = 1 / 60

-- | The stroke of a size, rounded down to whole sp.
syntheticStroke :: Rational -> Sp -> Sp
syntheticStroke r size = floor (toRational size * r)
```

- 有理数と `floor` で整数の sp にし、浮動小数点数を使わない（[docs/adr/0002](../../adr/0002-determinism.md)）。
- `syntheticStroke` と二つの定数をモジュールの外に公開し、テストから値を確かめられるようにする。

### 描画（golem-driver）

`writeDocument` の中の `runsOf` と `runAt` を変える。
[docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md) の後の `runsOf` は、各要素に役割、文字の並び、欧文の連続かどうかを持つ。

- `runsOf look txt` は、[docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md) の分け方の条件（役割か合成の指定が二つの側で異なる）に加え、どちらかの側の `synBold` が真の場合にも、文字の並びを欧文の連続とそれ以外の連続に分ける。二つの側がどちらも合成の太字で、役割も同じ場合に、線の幅を側ごとに変えるためである。どちらの側も太らせない場合は分けない。分けると境界をまたぐシェイピング（カーニングなど）が変わるので、合成の太字のときだけに限る。
- `runAt` は、各連続の側の `Synthetic` の `synBold` が真なら、線の幅を欧文の連続では `syntheticStroke syntheticStrokeLatin size`、それ以外では `syntheticStroke syntheticStrokeJa size` とし、偽なら 0 とする。
- `runAt` がグリフを命令にまとめる鍵（今の `(ix, sl)`）に線の幅を加え、`(ix, sl, 線の幅)` にする。同じフォントでも線の幅の違うグリフは別の `StyledGlyphRun` になる。
- `P.RunStyle` の `rsEmbolden` に、その鍵の線の幅を渡す。
- グリフの位置（送り）は変えない。

golem-pdf の `RunStyle` と `StyledGlyphRun` の直列化は変えない。

### ドキュメント

- 仕様書の「v1 の実装で次の段階以降に回した項目」から「合成の太字の太さ」を削る。
- 仕様書の `style.toml` の節の、合成の太字の説明（「輪郭を線で太らせる」）に、線の幅を和文で文字の大きさの 1/80、欧文で 1/60 とすることと、この ADR へのリンクを足す。

## 実装しないこと

- 線の幅を `style.toml` で変える設定。[ADR 0004](0004-pdf-emphasis-and-character-styles.md) の判断を保つ。合成の太字の見え方に不満がある文書は、`[character-styles.bold]` の `font` で太字の書体を指定する（[docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md)）。
- 合成の斜体の傾きを側ごとに変えること。
- 文字の大きさによって比率を変えること（Skia のような、大きい文字ほど比率を下げる補間）。見比べたのは本文の大きさだけであり、見出しの大きさで比率を変える根拠がまだない。
- フォントごとに値を変えること。フォントの画の太さ（OS/2 テーブルの太さの値など）から線の幅を決める方法は考えられるが、値の根拠を作る手間に見合わない。
- 合成の太字で太った分だけ送りを広げること（[ADR 0004](0004-pdf-emphasis-and-character-styles.md) のとおり）。
- ルビの読みと圏点の点の扱いの変更。
- HTML と EPUB の合成の太字。ブラウザーが合成するので、Golem は値を決めない。

## テスト設計

先に書いて失敗させるテストを並べる。

### golem-driver（modules/golem-driver/test/Main.hs）

`emphasisTests` に加える。
文字の大きさは `horizontalStyle` の 10pt（655360sp）とし、偽のフォント（`fakeProvider`）を使う。
内容のストリームから `2 Tr <幅> w` の幅を読み出す補助の関数を足す。

- `syntheticStroke syntheticStrokeJa 655360` が 8192、`syntheticStroke syntheticStrokeLatin 655360` が 10922 であること。
- `前の[bold: 本文]後` の内容のストリームの線の幅がすべて `0.125` であること。今の 1/40（`0.25`）では失敗する。
- `[bold: Golem]` の線の幅が、10922sp を `num` で書いた値であること。
- 本文の役割が `ja` だけを持つ `style.toml` で `[bold: 本Golem]` を組むと、`StyledGlyphRun` が二つに分かれ、`本` のグリフは `0.125` の幅、`Golem` のグリフは 10922sp の幅の命令の中にあること。
- 上と同じ原稿で、各グリフの `Tm` の位置の並びが、`[bold: ...]` を外した原稿の PDF と一致すること。
- `[character-styles.big] size = "2zw"` で `[style big: [bold: 本]]` を組むと、線の幅が `0.25`（大きさに比例して 2 倍）になること。
- 合成の太字を使わない原稿の PDF が、この変更の前と同じバイト列であること（太字でない段落だけの原稿の PDF を、変更の前後で比べる golden テスト、または既存の golden テストが変わらないこと）。
- `[fonts.gothic]` に `ja` だけを持たせ、`[character-styles.bold] font = "gothic"` で `[bold: 本Golem]` を組むと、`本` のグリフは `gothic` の役割の、`2 Tr` を持たない命令に、`Golem` のグリフは外側の欧文の役割で 10922sp の幅の命令に入ること。[docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md) の、役割が持つ側を太らせない規則との組み合わせの確認である。

既存のテスト「synthetic bold strokes the outline and keeps every glyph where it was」は変えずに通ること。

### 目で確かめる手順

自動テストでは、太すぎるかどうかを判定できない。
実装の後に、次の手順で確かめる。

1. `modules/golem-driver/test/fixtures/tempest` と `kanikosen` から `manifest.toml`、`style.toml`、`fonts/`、原稿を一時ディレクトリに写す。fixture そのものは変えない（README のとおり手で編集しない）。
2. 写した原稿の先頭に、太字と通常の字面を並べた段落を足す。和文は `[bold: 二人はデッキの手すりに寄りかかって、函館の街を見ていた。]` の直後に同じ文を通常の字面で置き、画の多い字（`[bold: 永東國酬鬱靈薔薇、ABCabc123。]永東國酬鬱靈薔薇、ABCabc123。`）も置く。欧文は文の一部を `[bold: ...]` にした段落と、`[bold: HAMBURGEFONTSIV hamburgefontsiv 0123456789.]` を置く。
3. それぞれのディレクトリで `golem build --target pdf` を実行する。
4. PDF を PNG にする。`sips -s format png` は 72dpi（A5 で 420 × 595 画素）でしか描かないので、`qlmanage -t -s 4800 -o <出力先> <PDF>` で長辺 4800 画素に描く。
5. `sips -c <高さ> <幅> --cropOffset <y> <x>` で太字の段落の部分を切り出し、Read で開いて見る。
6. 次のことを確かめる。和文の「鬱」「靈」のふところが埋まっていないこと。和文と欧文の太字が、隣の通常の字面と区別できること。同じ太字の中の和文と欧文の太さが極端に違って見えないこと。

値を比べ直す場合は、`syntheticStrokeJa` と `syntheticStrokeLatin` を変えて手順 3 から繰り返す。
この ADR の値を決めた見比べでは、一時的に環境変数で比率を変えられるようにした版を作って比べ、その変更はコミットせずに戻した。

## トレードオフ

線を細くしたので、合成の太字は今より弱く見える。
特に和文の 1/80 は、太字の書体（Noto Serif JP Bold など）と比べるとはるかに細い。
合成の太字は「通常の字面と区別できる強調」を保証するもので、太字の書体の代わりにはならない。
太字らしい太さが要る本では、`[character-styles.bold]` の `font` で太字の書体を指定する。

和文と欧文で値を分けるので、合成の太字の中で和文と欧文の太り方がわずかに違う。
一つの値にすると、和文のふところが埋まるか、欧文の太字が弱くなるかのどちらかになる。
欧文の値を和文よりわずかに太くするだけにとどめ、並んだときの違いを小さくする。

和文のフォントの欧文の字形も欧文の値で太らせるので、同じフォントの一つの語の中で線の幅が切り替わる位置ができ、そこで `StyledGlyphRun` が分かれる。
内容のストリームは少し大きくなるが、グリフの位置は変わらない。

値は、二つのフォント（Noto Serif JP と Source Serif）と本文の大きさだけで見比べて決めた。
画の太い書体（ゴシック体など）や、極端に小さい文字では、別の値がよい可能性がある。
その場合は、値を決め直す ADR を作る。
