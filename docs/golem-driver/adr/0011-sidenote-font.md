# ADR 0011: 傍注を段落スタイル sidenote の書体と大きさで組む

ステータス: 採択→（`[sidenotes]` に残すキーへの `side` の追加）は [golem-project ADR 0009](../../golem-project/adr/0009-sidenotes-side-key.md)、キャプションと傍注が引き継ぐキーは [ADR 0043](0043-caption-sidenote-do-not-inherit-indent.md)

## 文脈

`style.toml` の `[sidenotes]` は、傍注欄の幅（`width`）と版面との間隔（`gap`）に加え、傍注のフォントの役割（`font`）と文字の大きさ（`size`）を持つ（[golem-project ADR 0002](../../golem-project/adr/0002-style-toml.md)）。
[golem-layout ADR 0006](../../golem-layout/adr/0006-sidenotes.md) は、傍注の本文を `[sidenotes]` のフォントと文字の大きさで組むと定めた。
[ADR 0006](0006-pdf-sidenotes.md) は、役割ごとのフォントの仕組みが PDF のパイプラインになかったので、`font` を使わず、傍注を本文の書体と `size` の大きさで組むと決めた。
その仕組みは [ADR 0003](0003-pdf-heading-styles.md) で入り、見出し、太字と斜体、文字スタイルが使っている（[ADR 0004](0004-pdf-emphasis-and-character-styles.md)）。

現状をコードで確かめると、次のとおりである。

- `Golem.Driver.Pdf` の `buildFlow` は、傍注の本文を `snEnv = envFor body snSize'` で組む。`body` は本文の役割、`snSize'` は `sidenoteMetrics` が `[sidenotes]` の `size` から求めた大きさである。本文の先頭の印（番号か「※」）も同じ環境で組む。
- `usedRoles` は `[sidenotes]` の `font` を含まないので、その役割のフォントは読み込まれない。
- `Golem.Project.Style.parseStyle` の `roleChecks` は `[sidenotes]` の `font` を検査しない。`[fonts]` にない役割を書いても、黙って本文の書体で組まれる。
- HTML と EPUB の CSS は、傍注に `.sidenote { font-size: 0.85em; }` を固定で出し、`font` と `size` を使わない。
- `[sidenotes]` の `size` を書いているのは、golem-driver のテストの `sidenoteStyle`（`modules/golem-driver/test/Main.hs`）と仕様書の例である。`font` を書いているものは、リポジトリの中にない。

[docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md) は、段落の見た目を `[paragraph-styles.<名前>]` の段落スタイルにまとめ、組み込みの段落スタイルとして `body`、`verse`、`caption`、`sidenote` を置く。
段落スタイルの `font` はフォントの役割、`size` は文字の大きさで、`zw` は版面の文字の大きさを一字とする。
書かない欄は `based-on` をたどって引き継ぎ、最後は `body` の値になる。
`font` が `[fonts]` にない役割を指すと G03008、`size` が版面の文字の大きさを超えると G03011 になり、`usedRoles` はすべての段落スタイルの `font` を集める。
`sidenote` は `based-on = "body"` だけを持ち、その ADR では傍注の組み方に使われない。
キャプションの書体と大きさは、[ADR 0010](0010-caption-style.md) で段落スタイル `caption` に置いた。

この ADR は [docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md) と [docs/adr/0006](../../adr/0006-paragraph-indent.md) の後に、[ADR 0010](0010-caption-style.md) に続けて実装する。
`sidenote` の段落スタイル、`usedRoles` の集め方、`restyle` の文字スタイルの扱いを、その二つの ADR に頼るためである。

### [sidenotes] の font と size の扱い

`[sidenotes]` の `font` と `size` について、次の二つを比べた。

- 残し、段落スタイル `sidenote` の `font` と `size` への写像として扱う。両方に書いた場合の優先を決める必要がある。
- 廃止し、`[paragraph-styles.sidenote]` に移す。`[sidenotes]` には傍注欄の幾何（`width`、`gap`）と印（`marker`）だけを残す。

廃止する。
写像として残すと、同じ指定を二通りに書けるようになり、[ADR 0010](0010-caption-style.md) が `[figures.caption]` を設けなかった理由と食い違う。
`font` は今まで出力に効いておらず、`size` を書いているのはリポジトリの中のテストと仕様書の例だけなので、書き換えの範囲は小さい。
[docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md) が `[emphasis]` と `[verse]` の `stanza-gap` を廃止したのと同じ扱いにする。

## 実装すること

### style.toml の欄（golem-project）

傍注の書体と大きさは、組み込みの段落スタイル `sidenote` の `font` と `size` で指定する。

```toml
[sidenotes]
width = "6zw"
gap = "1zw"

[paragraph-styles.sidenote]
font = "note"   # フォントの役割
size = "8pt"    # 文字の大きさ
```

- `SidenoteStyle` から `snFont` と `snSize` を削る。`snWidth`、`snGap`、`snMarker` は残す。
- `[sidenotes]` の `font` と `size` は未知のキーとして G03006 にし、[docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md) の廃止した欄と同じく、メッセージで書き換え方を示す。

| 旧 | 新 |
|---|---|
| `[sidenotes] font = "r"` | `[paragraph-styles.sidenote] font = "r"` |
| `[sidenotes] size = "8pt"` | `[paragraph-styles.sidenote] size = "8pt"` |

- `[paragraph-styles.sidenote]` の読み込み、`based-on` の解決、G03006、G03008、G03011 の検査は [docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md) のとおりとする。`roleChecks` に傍注のための検査を加える必要はない。
- 傍注に効くのは、解決した `sidenote` の `font` と `size` だけである。`line-breaks`、`space-between`、[docs/adr/0006](../../adr/0006-paragraph-indent.md) の `indent` と `first-line-indent` は、傍注の本文には効かない。傍注の本文は意味論 IR の段落ではなく、インラインの要素の内容だからである。これらの欄は、`@style sidenote` を付けた原稿の段落には効く。

今まで `[sidenotes]` の `font` に `[fonts]` にない役割を書いても黙って本文の書体で組まれていたが、`[paragraph-styles.sidenote]` に移すと G03008 になる。
綴りの誤りが見た目の劣化としてしか現れないことを防ぐという、未知のキーをエラーにする方針（[仕様書](../../specifications.md) の「style.toml」の節）に合う。

### 役割と大きさの決め方（golem-driver）

傍注の役割と大きさを、[ADR 0010](0010-caption-style.md) の `paraFace` で決める。

```haskell
paraFace style geom "sidenote"
```

- 役割：解決した `sidenote` の `font`。なければ本文の役割。
- 大きさ：解決した `sidenote` の `size` を `dimToSp` で sp にしたもの。`zw` は版面の文字の大きさを一字とする。なければ版面の文字の大きさ。

大きさの決め方は今の `sidenoteMetrics` と同じであり、読む欄が `[sidenotes]` の `size` から `sidenote` の `size` に替わるだけである。
`sidenoteMetrics` は、`paraFace` の結果を使って、役割、大きさ、行送りの三つを返す形に変える。

```haskell
sidenoteMetrics :: Style -> PageGeometry -> (Text, Sp, Sp)
-- 役割、文字の大きさ s、行送り p
```

行送りは今と同じく `本文の行送り × s ÷ 本文の文字の大きさ`（整数の除算）とする。
[ADR 0010](0010-caption-style.md) のキャプションは見出しと同じ丸めで行送りを求めるが、傍注の計算を変えると既存の傍注のある PDF の出力が変わるので、ここでは変えない。

`usedRoles` は [docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md) のとおりすべての段落スタイルの `font` を集めるので、`sidenote` の役割はこの ADR で加えなくても読み込まれる。
読み込む役割の決め方、フェイスの番号、同じバイト列のファイルの統合、G08005 の検査は [ADR 0003](0003-pdf-heading-styles.md) のとおりとする。
縦組みの版面には `[sidenotes]` を書けない（G07001）ので、縦組みでは傍注を組まない。
縦組みでも `sidenote` の `font` の役割は `usedRoles` に入って読み込まれるが、PDF に書くフォントは内容のストリームが参照するものだけ（`Golem.Pdf.Writer.writePdf` の `fontOrder`）なので、傍注のない PDF にはその役割のフォントは埋め込まれない。

### 傍注の組版と描画

- `buildFlow` の `snEnv` を `envFor 役割 s` にする。傍注の本文と、その先頭の印（番号か「※」と半角の空白）を、この役割と大きさで組む。
- 本文の側の印（傍注を指す番号か「※」の箱）は、今と同じく本文の見た目（その位置の `Look`）で組む。印は本文の行の一部だからである。
- 傍注の本文の中の文字スタイル（`[strong: ...]` などの組み込みの文字スタイルを含む）と色は、[docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md) の `restyle` で、傍注の見た目から切り替える。文字スタイルの `size` の `zw` は s を一字とする。
- `writeDocument` の傍注の描画は変えない。各箱の `bcLook` の役割で `lfShape` を呼ぶので、傍注の役割のグリフはその役割のフォントで描かれ、そのサブセットに入る。

傍注の配置（`placePageSidenotes`）、G07032 から G07035 の検査、S2 との関係は [ADR 0006](0006-pdf-sidenotes.md) のまま変えない。
傍注の高さは役割によらず `(行数 − 1) × p + s` なので、書体を変えて変わるのは、行分割で決まる行数だけである。

### HTML と EPUB（golem-html、golem-driver）

傍注の書体を PDF だけに効かせると、媒体のあいだで傍注の見た目がずれるので、HTML と EPUB の CSS にも反映する。
キャプション（[ADR 0010](0010-caption-style.md)）と同じ型と関数を使い、キャプションと同じく `size` も反映する。

- `HtmlConfig` に `hcSidenoteFace :: !Face` を加える。`Face` は [ADR 0010](0010-caption-style.md) で `Golem.Html` に加える型である。
- `writeTargets` は、解決した `sidenote` の段落スタイルを `d` として、`Face (d >>= psFont) (cssFontSize style <$> (d >>= psSize))` を渡す。
- `css` の `.sidenote` の規則を、次のように出す。
  - `faFont` があれば `font-family: <役割の並び>;` を出す。役割の並びは既存の `fontStack` で作る。
  - `faSize` があれば `font-size: <値>;` を、なければ今と同じ `font-size: 0.85em;` を出す。
- どちらもない場合の規則は、今の `.sidenote { font-size: 0.85em; }` と同じ文字列にする。
- `.sidenote` の規則は、[docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md) の `p.ps-sidenote` の規則とは別に書く。`p.ps-sidenote` は `@style sidenote` を付けた原稿の段落のためのものである。

`size` がない場合、PDF は版面の文字の大きさで組むが、HTML は今の 0.85em のままとする。
HTML の傍注は、画面が広ければ本文の余白に置かれるので、本文より小さい既定を保つ。
`size` を書けば、PDF と HTML は同じ比の大きさになる。

プレーンテキストは変えない。

### 決定性

- 役割の決定は `Style` だけから決まる純粋な関数で行う。
- 傍注の本文を並列に組んだ結果は、今と同じく文書の順に並べ直した行に付く（[docs/adr/0002](../../adr/0002-determinism.md)）。
- フェイスの番号は [ADR 0003](0003-pdf-heading-styles.md) の規則で、役割の名前とファイルのバイト列だけから決まる。

### ドキュメント

- [仕様書](../../specifications.md) の「v1 の実装で次の段階以降に回した項目」から「傍注の書体」を削る。
- [仕様書](../../specifications.md) の「傍注」の節の「傍注の文字の大きさは `[sidenotes]` の `size`」の文を、傍注の書体と大きさが段落スタイル `sidenote` の `font` と `size` になること、省略時は本文の役割と版面の文字の大きさになることに改め、この ADR へのリンクを付ける。
- [仕様書](../../specifications.md) の「style.toml」の例の `[sidenotes]` から `size` を削り、`[paragraph-styles.sidenote]` の例を加える。`[sidenotes]` の説明を `width`、`gap`、`marker` だけにする。
- [仕様書](../../specifications.md) の「フォント」の節の、PDF が読み込む役割の列挙に、段落スタイルの `font`（`caption` と `sidenote` を含む）を加える。
- README の `style.toml` の説明を改める。
- [golem-layout ADR 0006](../../golem-layout/adr/0006-sidenotes.md) のステータスの行を「採択→傍注の書体と大きさの欄は golem-driver ADR 0011」に変え、この ADR へのリンクを付ける。
- [golem-project ADR 0002](../../golem-project/adr/0002-style-toml.md) のステータスの行に「`[sidenotes]` の `font` と `size` の廃止は golem-driver ADR 0011」を加え、この ADR へのリンクを付ける。
- ステータスの行のリンクは、書き込む先のファイルからの相対パスにする。

## 実装しないこと

- `[sidenotes]` の `font` と `size` を互換の別名として残すこと。
- 傍注の番号（傍注の本文の先頭の印）と本文で書体や大きさを変えること。
- 本文の側の印の書体と大きさの設定。
- 傍注の行送りを `style.toml` で指定すること。
- 傍注の行送りの計算を、見出しとキャプションと同じ丸めに変えること。
- 傍注に `sidenote` の `line-breaks`、`space-between`、字下げを効かせること。
- 縦組みの傍注、段組みの版面での傍注欄（[仕様書](../../specifications.md) の「v2 以降に回した事項」）。
- HTML と EPUB で、傍注の置き方（余白に置く幅と位置）を `[sidenotes]` の `width` と `gap` から決めること。

## テスト設計

先に書いて失敗させるテストを並べる。

### golem-project（modules/golem-project/test/Main.hs）

- `[sidenotes]\nwidth = "6zw"\ngap = "1zw"\nsize = "8pt"\n` が G03006 になり、メッセージに `[paragraph-styles.sidenote]` が含まれること。`font = "note"` も同じであること。
- `[fonts.note]` と `[paragraph-styles.sidenote]\nfont = "note"\nsize = "8pt"\n` を含む `style.toml` が診断なしで読め、`paraStyle s (Just "sidenote")` の `psFont` が `Just "note"`、`psSize` が `Just (Abs (8 × 65536))` になること。
- `[paragraph-styles.sidenote]\nfont = "nope"\n` を含み `[fonts.nope]` がない `style.toml` が G03008 になること。

### golem-driver（modules/golem-driver/test/Main.hs）

フォントは `fakeFonts` を使う。
既存の `sidenoteStyle` を、`horizontalStyle` に `[sidenotes]` の `width = "6zw"`、`gap = "1zw"` と `[paragraph-styles.sidenote]` の `size = "8pt"` を足したものに書き換える。

- 書き換えた `sidenoteStyle` で、[ADR 0006](0006-pdf-sidenotes.md) の既存の傍注のテストが同じ値で通り、PDF のバイト列がこの ADR の前の `sidenoteStyle` の出力と一致すること。
- `usedRoles` が、`[fonts.body]`、`[fonts.heading]`、`[paragraph-styles.sidenote] font = "heading"` を持つスタイルで `["body", "heading"]` を返すこと。
- `sidenoteStyle` の `[paragraph-styles.sidenote]` に `font = "heading"` を足して「本文[sidenote: 注]。」を組むと、傍注の文字「注」と番号のグリフが `heading` の役割のフェイス（`fakeFonts` の 4）のフォントのリソースで大きさ 8 の `Tf` で描かれ、本文の文字と本文の側の番号のグリフが本文のフォントのリソースで描かれること。
- `font = "wide"`（`fakeFonts` で全角も半角も 1 em になる役割）で、半角の文字の多い傍注の行数が、`font` なしのときより多くなること。行の幅が役割のメトリクスで測られることの確認である。
- `font = "body"` を書いた `sidenoteStyle` の PDF が、書かない `sidenoteStyle` の PDF とバイト列で一致すること。
- `[paragraph-styles.sidenote] first-line-indent = "1zw"` を書いても、傍注の 1 行目の位置が書かない場合と同じであること。
- 傍注に `[bold: 語]` を含め、`[character-styles.bold] font = "wide"` を指定すると、その語のグリフが `wide` の役割で描かれ、ほかの傍注の文字が傍注の役割で描かれること。
- 傍注の役割を指定した原稿を並列と逐次でビルドし、PDF のバイト列が一致すること。二回のビルドでも一致し、qpdf の検査を通ること。
- 実際のフォントで、本文の欧文を `SourceSansPro-Regular.otf`、`[fonts.note]` の欧文を `SourceSerifVariable-Roman.ttf` とし、`[paragraph-styles.sidenote] font = "note"` で欧文の傍注を組むと、二つのフォントが埋め込まれ、傍注のフォントのサブセットに傍注の文字（と番号）のグリフだけが入ること。
- HTML：`[paragraph-styles.sidenote]` に `font = "note"` と `size = "8pt"` を書き、`[page.grid]` の `font-size` が 10pt の `style.toml` の CSS に、`.sidenote { font-family: "golem-note-latin", serif; font-size: 0.8em; }` が出ること。`size` だけを書いた場合は `font-family` がなく、`font` だけを書いた場合は `font-size: 0.85em` になること。`[paragraph-styles.sidenote]` がない場合の CSS が今の golden（`test/golden/html-style.css`）と一致すること。

自動テストにしない確かめ方として、実装の後に横組みの雛形（`golem new` の英文の雛形）に `[sidenotes]` と、本文と別の役割の `[paragraph-styles.sidenote] font` を足してビルドし、傍注欄の文字がその書体で組まれることを PDF のビューアーで確かめる。
HTML でも、傍注がその書体で表示されることを確かめる。

## トレードオフ

`[sidenotes]` の `font` と `size` を廃止するので、それを書いた `style.toml` は G03006 になり、`[paragraph-styles.sidenote]` への書き換えが要る。
Golem はまだ配布しておらず、書き換えの対象はリポジトリの中のテストと仕様書の例だけである。
書体と大きさの書き方を段落スタイルの一通りにする利点を取る。

傍注の書体と大きさを段落スタイルに置くので、`sidenote` の欄のうち `font` と `size` だけが傍注に効き、ほかの欄は `@style sidenote` の段落にだけ効く。
[ADR 0010](0010-caption-style.md) のキャプションと同じ扱いである。

`size` が版面の文字の大きさを超えると G03011 になるので、本文より大きい傍注は組めなくなる。
今の `[sidenotes]` の `size` には上限がない。
傍注を本文より大きく組む本は考えにくく、段落スタイルの検査を場所によって変えないことを選ぶ。

`size` がない場合の大きさが、PDF（版面の文字の大きさ）と HTML（0.85em）で異なる。
HTML の既定を版面の文字の大きさに合わせると、`size` を書いていない既存のプロジェクトの HTML の見た目が変わる。
PDF の傍注欄は版面の外にあり、利用者は幅と大きさを合わせて決めるので、PDF では `size` を書くことが前提になる。
既定のずれは、`size` を書けば解消する。

傍注の行送りの計算を、キャプションと見出しの丸めにそろえない。
そろえると傍注の出力が変わるうえ、差は 1sp で見た目に現れないので、出力を保つほうを選ぶ。
