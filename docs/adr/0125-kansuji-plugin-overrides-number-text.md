# ADR 0125: 数を漢数字で組む見本のプラグイン kansuji

ステータス: 採択

## 文脈

rc4 では、プラグインの仕組みを実際のプラグインで通すために、見本のプラグインを六つ作る（[docs/roadmap.md](../roadmap.md) の v0.1.0-rc4、[docs/adr/0106](0106-sample-plugins-in-rust.md)）。
その一つが、組み込みの `number-text` を上書きして、縦組みの数を漢数字で組むプラグインである。
ルビの二つのプラグインは、インラインの文字列を受け取ってルビを付けて返すだけなので、プラグインの仕組みの同じ部分しか通らない。
このプラグインは、次の二つを通すために作る。

- 組み込みのコマンドの上書き（[docs/adr/0031](0031-adr-code-mismatches.md)）。`number-text` は上書きできる十のコマンドの一つである。
- 自然数、整数、有理数を CBOR で受け取る経路（[ADR 0101](0101-rational-numbers-in-expressions.md)、[ADR 0102](0102-natural-number-type.md)）。

組み込みの `[number-text ...]` は、すでに整数を三つの表記（`kanji` の「百二十三」、`kanji-digits` の「一二三」、`tcy` の縦中横）で組める（[docs/markup.md](../markup.md) の「数の表記」）。
組み込みは IR の数のノード（tag 9）を作り、表記はレイアウトが書字方向と `style.toml` の `[numbers]` の `vertical` を見て決める（[`numberPieces`](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-layout/src/Golem/Layout/Japanese.hs#L378-L385)）。
組み込みが受け取るのは整数だけで、小数と分数は G02019 になる（[`builtinWith` の `BNumberText`](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-eval/src/Golem/Eval/File.hs#L1747-L1760)）。
このプラグインは、組み込みにない小数と分数の表記を足し、整数の表記はプラグインの中で組み直す。

### 決めること

1. 小数、分数、負の数、大きな数の表記。
2. 表記の選び方（引数か、データか、本の文脈か）。
3. プラグインが返す diagnostic。
4. 組み込みと同じ整数の表記を、プラグインがどこまで自分で組むか。

### 試しに実装して分かったこと

この ADR は、採択の前に実装を試した（ブランチ `plugins-number-tcy`、`plugins-foundation` から分岐）。
`plugins/kansuji` を作り、golem-driver のテストと、縦組みの小さなプロジェクトの `golem build`（PDF）で動かした。
試してわかったことは次のとおりである。

- **キーワード引数が名前を失っていた**：CDDL の `argument` は `[0, value] / [1, key, value]` だが、ホストはすべての引数を `[0, value]` で送り、キーワードの名前を捨てていた（[`evalCommand`](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-eval/src/Golem/Eval/File.hs#L1689-L1692)、[`commandRequest`](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-plugin/src/Golem/Plugin.hs#L250-L253)）。`[number-text 123 style=kanji-digits]` は、プラグインには位置引数が二つの呼び出しとして届き、`kansuji-arity` になった。CDDL のとおりに送るよう、この試しのブランチで直した。修正の草稿は [docs/adr/0110](0110-keyword-arguments-to-plugins.md) である。
- **書字方向が分からない**：コマンドの要求は、名前、引数、散文スロット、位置、データだけを持ち（[golem-plugin ADR 0001](../golem-plugin/adr/0001-wasm-host-and-abi.md)、[docs/adr/0105](0105-plugin-data.md)）、書字方向を持たなかった。最初の試しでは、プラグインが返した「百二十三」の文字列が、横組みでもそのまま「百二十三」になった。組み込みの「横組みでは算用数字」という規則（[docs/markup.md](../markup.md) の「数の表記」）を、上書きしたプラグインは守れなかった。
- **本の既定の表記が分からない**：`style` 引数のない `[number-text ...]` と `##N##` の表記は、組み込みでは `[numbers]` の `vertical` で決まる。最初の試しでは、プラグインに `style.toml` が渡らないので、既定をプラグインのデータ `config` で別に指定させた。同じ本で、ページ番号とリストの番号（組み込みのまま）と本文の数（プラグイン）が、別々の設定に従うことになった。
- **本の文脈で解いた**：上の二つは、プラグインが本の文脈を宣言して受け取る仕組み（[docs/adr/0121](0121-host-context-in-plugin-requests.md)）で解いた。`kansuji` は `writing-mode` と `vertical-numbers` を宣言し、データの `config` をやめた。横組みの PDF とプレーンテキストに漢数字が出ないことを確かめた。
- **上書きが届く範囲**：上書きで変わるのは、原稿の `[number-text ...]` と `##N##` だけである（`##N##` は評価で `[number-text N]` になる。[`evalInline`](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-eval/src/Golem/Eval/File.hs#L1617-L1619)）。ページ番号、リストの `{n}`、見出しの番号は、レイアウトが数のノードから組むので、プラグインを通らない。
- **語で書いた数の型**：引数の語は、数字だけの語（`12`）が自然数になり、`-3` と `3.14` は文字列になる（[`argValueRaw`](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-eval/src/Golem/Eval/File.hs#L1903-L1909)）。組み込みの `[number-text -3]` は G02019 になり、プラグインには文字列の `"-3"` が届く。負の数と小数は `[number-text [= -3]]` のように式で書くしかない。[docs/markup.md](../markup.md) は `[number-text ...]` の負の数に意味があるとするが、語では書けない。語を数のリテラルとして読む修正は、別の草稿（[docs/adr/0111](0111-argument-words-as-number-literals.md)）で扱う。
- **自然数と整数の区別**：CBOR の `value` は自然数も整数も `int64` で書く（[docs/specifications.md](../specifications.md) の「シリアライズ形式」）。プラグインは二つを区別できない。数の表記には区別が要らないので困らなかったが、ロードマップの「自然数、整数、有理数を CBOR で受け取る経路」のうち、実際にある経路は整数（`int64`）と有理数（タグ 30）の二つである。
- **有理数**：`[= 3.14]` はタグ 30 の `[157, 50]` で届き、`[= 3.0]` は分母 1 の `[3, 1]` で届いた。値が整数の有理数を整数として扱うのはプラグインの側の決まりになる。小数のリテラルの末尾の 0 は値に残らないので、`[= 3.10]` を `三・一〇` と組むことはできない。
- **大きな数**：絶対値が 2 の 63 乗以上の整数と、分子か分母がその範囲の外の有理数は、ホストが G02091 にしてプラグインを呼ばない（[`evalCommand`](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-eval/src/Golem/Eval/File.hs#L1697)、[golem-doc ADR 0006](../golem-doc/adr/0006-integer-range-in-ir.md)）。`int64` の最大値は「九百二十二京……」で、単位は京までで足りる。垓より上の単位を組む機会はない。
- **diagnostic のコード**：ホストはプラグインのコードをそのまま表示する。`lookup` に倣い、`kansuji-not-number` のようにプラグインの名前を前に付けた。`golem explain` では引けない（[docs/adr/0108](0108-plugin-diagnostic-codes-and-spans.md)）。
- **データの誤りの位置**：最初の試しの `config` の誤りは、データに位置がないので、コマンドを呼んだ箇所に出すしかなかった。同じ誤りが、本文の `[number-text ...]` の数だけ繰り返し報告された。`config` をやめたので、この問題は `kansuji` からは消えた。
- **プラグインを読み込めないとき**：キャッシュにプラグインがない（G06003）と、`number-text` は組み込みに戻り、`[number-text [= 3.14]]` が組み込みの G02019 になった。プラグインのコマンドでは、読み込みの誤りのあとに未知のコマンド（G02022）を出さない（[golem-plugin ADR 0003](../golem-plugin/adr/0003-plugin-diagnostic-codes.md)）が、上書きしたコマンドには同じ抑えがない。G06003 でビルドは止まるので出力が黙って変わることはないが、原因でない diagnostic が混じる。
- **縦組みと横組みで組んだ結果**：`[numbers]` の `vertical = "auto"` の縦組みの PDF では、`一億二千三百四十五万六千七百八十九`、`三・一四`、`三分の二`、`二〇二六`、`マイナス三` が漢字で、`##10##` が縦中横で組まれた。同じ原稿を横組みにすると、`123456789`、`3.14`、`2/3`、`2026`、`-3`、`10` になった。二回のビルドで、PDF のバイト列と JSON の diagnostic は同じだった。
- **大きさ**：`kansuji.wasm` は 88818 バイトだった（`lookup` は 76116 バイト）。

## 実装すること

### 置き場所と宣言

`plugins/kansuji` に、[docs/adr/0106](0106-sample-plugins-in-rust.md) の手順で置く。
利用者は次のように宣言する。

```toml
[plugins.kansuji]
url = "https://github.com/tett23/golem/releases/download/v0.1.0-rc4/kansuji.wasm"
overrides = ["number-text"]
```

プラグインはコマンド `number-text` と、本の文脈 `writing-mode` と `vertical-numbers` を `golem_describe` で宣言する（[docs/adr/0121](0121-host-context-in-plugin-requests.md)）。
データは受け取らない。
`overrides` に `number-text` を書かなければ、組み込みと衝突して G06007 になる。

### 引数

```
[number-text 123]
[number-text 123 style=kanji-digits]
[number-text [= 2 / 3]]
[number-text [= 0.5] form=fraction]
```

- 位置引数は一つで、整数か有理数である。
- `style` は `kanji`、`kanji-digits`、`tcy` のいずれかである。組み込みと同じ名前にし、組み込みと同じく `auto` と `auto-digits` は書けない。
- `form` は `decimal`（既定）か `fraction` である。整数でない有理数の書き方を選ぶ。
- 散文スロットは取らない。

### 表記

縦組みの本では、次のとおりに書く。

| 値 | `kanji` | `kanji-digits` | `tcy` |
| --- | --- | --- | --- |
| `123` | 百二十三 | 一二三 | 数のノード（縦中横） |
| `10000` | `一万` | `一〇〇〇〇` | 数のノード |
| `-3` | マイナス三 | マイナス三 | 数のノード |
| `3.14` | `三・一四` | `三・一四` | エラー |
| `123.45` | `百二十三・四五` | `一二三・四五` | エラー |
| `2/3` | 三分の二 | 三分の二 | エラー |
| `13/10`、`form=fraction` | 十分の十三 | 一〇分の一三 | エラー |

横組みの本では、`style` によらず、次のとおりに書く。

| 値 | 出力 |
| --- | --- |
| 整数（`123`、`-3`） | 表記のない数のノード（ホストが算用数字で組む） |
| 十進で有限に書ける有理数（`3.14`、`-1/8`） | `3.14`、`-0.125` |
| ほかの有理数と `form=fraction` | `2/3`、`-7/3`、`1/2` |

整数でない数の `tcy` は、横組みでも縦組みと同じくエラーにする。
同じ原稿の誤りが、書字方向で変わらないようにするためである。

- 位取りは、組み込みの `kanji`（[`Golem.Doc.Numerals.kanji`](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-doc/src/Golem/Doc/Numerals.hs#L34-L54)）と同じにする。十、百、千の前の「一」は書かず、万、億、兆、京の前の「一」は書く。0 は「〇」である。
- 負の数は、前に「マイナス」を付ける。組み込みと同じである。
- 小数は、十進で有限に書ける有理数（既約の分母が 2 と 5 の積）に使う。整数の部分は `style` の表記で、小数点を「・」、小数の部分を一字ずつの漢数字で書く。小数の部分の桁は、値が決める最短の桁数である。
- 十進で有限に書けない有理数と、`form=fraction` の有理数は「（分母）分の（分子）」と書く。分母と分子は `style` の表記で書く。帯分数にはしない。
- 値が整数の有理数（`[= 3.0]` など）は整数として書く。
- `tcy` は、組み込みと同じく IR の数のノード（tag 9、`number-style` は 2）を返す。縦中横にするかどうかと横組みの表記は、ホストのレイアウトに任せる。整数でない数の `tcy` はエラーにする。

`tcy` だけ数のノードを返すのは、縦中横が文字列では書けず、IR に縦中横の数を表すノードがすでにあるからである。
`kanji` と `kanji-digits` を数のノードで返さないのは、このプラグインの目的が、表記をプラグインの中で決めることにあるからである。
数のノードで返すと、プラグインは組み込みと同じことしかしない。

### 既定の表記

`style` のない `[number-text ...]` と `##N##` の表記は、本の文脈の `vertical-numbers`（`style.toml` の `[numbers]` の `vertical`）で決める。
`auto` と `auto-digits` は組み込みと同じ意味である（0 以上 99 以下は縦中横）。
組み込みと同じ設定に従うので、ページ番号やリストの番号と本文の数が、別々の設定に従うことはない。

### diagnostic

プラグインの diagnostic は、どれもエラーで、出力は空のインラインの列である。
一つの原因に一つのコードを当てる。

| コード | 原因 | メッセージ |
| --- | --- | --- |
| `kansuji-arity` | 位置引数がない、または二つ以上 | `number-text には数を一つ渡します`、`number-text に渡せる数は一つです（<数> 個）` |
| `kansuji-not-number` | 位置引数が数でない | `number-text には数を渡します。負の数と小数は [= -3] や [= 3.14] のように式で書きます: <文字列>`、`number-text には数を渡します` |
| `kansuji-style` | `style` の値が三つのいずれでもない | `style は kanji、kanji-digits、tcy のいずれかです: <値>` |
| `kansuji-form` | `form` の値が二つのいずれでもない | `form は decimal か fraction です` |
| `kansuji-key` | 知らないキーワード引数 | `number-text の知らないキーワード引数です: <キー>` |
| `kansuji-tcy-not-integer` | 整数でない数の `tcy` | `縦中横にできるのは整数だけです` |
| `kansuji-slot` | 散文スロットがある | `number-text は散文スロットを取りません` |

位置は、どれもコマンドを呼んだ箇所である。
コードは、ホストがプラグインの宣言の名前を前に付ける（[docs/adr/0108](0108-plugin-diagnostic-codes-and-spans.md)）。
プラグインは `kansuji-` を除いた後ろの部分（`arity`、`not-number` など）を返し、利用者には `kansuji/arity` のように見える。
試しの実装は、その草稿の実装の前なので、`kansuji-arity` を返している。

`kansuji-not-number` のメッセージの「式で書きます」は、語を数のリテラルとして読む修正（[docs/adr/0111](0111-argument-words-as-number-literals.md)）が入ると当てはまらなくなる。
その修正の後は、`-3` と `3.14` の語は数として届くので、文字列が届くのは数でない語だけになり、メッセージは `number-text には数を渡します: <文字列>` にする。

### モジュールとドキュメント

- golem-* のパッケージのあいだの build-depends は変えない。Haskell のコードは golem-driver のテストだけを変える（キーワード引数の修正は [docs/adr/0110](0110-keyword-arguments-to-plugins.md) の実装である）。
- 使い手のマニュアルのプラグインの章に、見本のプラグインとして `kansuji` の宣言を載せ、既定の表記が `[numbers]` の `vertical` に従うこと、横組みでは算用数字になることを書く。
- 採択の後、`docs/roadmap.md` の v0.1.0-rc4 から「数の表記を変えるプラグイン」を除く。

## 実装しないこと

- 横組みの数の表記を選ぶこと（全角の数字、桁区切り）。横組みでは組み込みと同じく算用数字にする。
- 大字（壱、弐、参）、「零」、「〇」と「零」の選択、「一千」のように千の前の一を書く表記。
- 小数の桁を指定すること（`3.10` を `三・一〇` と組む）。値に桁の情報がないので、引数で桁を受け取る必要がある。
- 帯分数（「一と三分の一」）と、分数を縦中横や割注で組むこと。
- 「マイナス」以外の負の記号（「△」「負の」）。
- 単位の付いた数（「三万円」の円）や、桁区切り。
- 2 の 63 乗以上の数。ホストが G02091 にする。

## テスト設計

テストは、Rust の単体テスト（`cargo test -p kansuji`）と、golem-driver の `PluginsSpec` で行う。
Rust の単体テストは実装と同時に書いた。
golem-driver のテストは、`plugins/wasm/kansuji.wasm` を除いた状態で失敗することを確かめた。
wasm を置くと、キーワード引数のテストが `kansuji-arity` で失敗し、上のキーワード引数の問題が見つかった。

Rust の単体テスト（`plugins/kansuji/src/lib.rs`）では、次のことを確かめる。

- 位取り：0、1、10、11、20、100、123、1000、1001、2026、10000、11000、100000000、100010001、-3。
- `int64` の最大値と最小値（最小値は符号を反転すると `i64` を溢れるので、`i128` で計算する）。
- 一字ずつ：123、2026、0、-10。
- 三つの表記と `auto`、`auto-digits` の整数。99 と 100、-1 の境。
- 小数と分数：157/50、24691/200、1/2、-1/8、2/3、-7/3、`form=fraction`、`tcy` の分数のエラー。
- 1/2^62 の小数の部分が 62 桁になること。
- 記述が `writing-mode` と `vertical-numbers` を宣言し、データを受け取らないこと。
- 文脈の `vertical-numbers` が既定の表記になり、`style=` がそれより先に立つこと。
- 横組みの文脈で、整数が表記のない数のノード、有理数が `3.14`、`-0.125`、`2/3`、`-7/3`、`1/2` になること。横組みでも `tcy` の分数がエラーになること。
- コマンドの要求に対する応答と、表の七つのコード。

golem-driver のテスト（`modules/golem-driver/test/PluginsSpec.hs` の `kansujiTests`）では、次のことを確かめる。

- `[number-text 123]`、`##12##`、`style=kanji-digits`、`[= 3.14]`、`[= 2 / 3]`、`[= -3]` の S0 のインライン。
- `style=tcy` が数のノードになり、`form=fraction` が分数になること。
- `[numbers]` の `vertical = "auto"` の本で、`##12##` が数のノードに、`##120##` が「百二十」になること。
- 横組みの本で、`[number-text 123]` と `[number-text 12 style=kanji]` が表記のない数のノードに、`[= 3.14]` と `[= 2 / 3]` が `3.14` と `2/3` になること。
- `kansuji` を読み込むと、LSP の監視するファイルに `style.toml` が入ること。
- `*[[123]]` と `**[{style: "tcy"}]` の展開、展開の型の誤り、展開したキーの重なり（[docs/adr/0110](0110-keyword-arguments-to-plugins.md)）。
- `[number-text -3]` が `kansuji-not-number` になること。
- 2 の 63 乗の整数と、分母が 2 の 63 乗の有理数が G02091 になり、プラグインを呼ばないこと。
- `int64` の最大値の漢数字。

手で確かめたこと：縦組みと横組みの小さなプロジェクトで `golem build` が PDF とプレーンテキストを書き、縦組みでは本文の数が漢数字と縦中横で、横組みでは算用数字で組まれること。

## トレードオフ

整数の表記を組み込みと同じ規則でプラグインの中に書き直したので、`Golem.Doc.Numerals` と同じ規則が Rust にもう一つある。
規則を変えるときは両方を直す必要がある。
見本のプラグインとして、組み込みに頼らずに数を組む例を示すことを優先した。

書字方向と `[numbers]` の `vertical` を本の文脈として受け取るので、`style.toml` を変えると、このプラグインを使うファイルの S0 の結果が変わる。
LSP は `style.toml` の変更でプロジェクトの全体を評価し直す（[docs/adr/0121](0121-host-context-in-plugin-requests.md)）。

## 決めたことの記録

- **書字方向と既定の表記**：メンテナーが、書字方向を要求に入れ、プラグインが要る本の文脈を宣言する一般の仕組みにすると決めた（2026-10-29）。`kansuji` はそれを使い、横組みでは漢数字を出さない。データの `config` はやめた。
- **diagnostic のコード**：メンテナーが、ホストがプラグインの宣言の名前をコードの前に付ける形でよいと決めた。この ADR のコードは [docs/adr/0108](0108-plugin-diagnostic-codes-and-spans.md) に従う。ブリーフで割り当てられた G06016 から G06019 はプラグインのコードには使わなかった。本の文脈の知らない名前のコードは、[docs/adr/0121](0121-host-context-in-plugin-requests.md) で G06105 とした。
- **整数の表記をプラグインの中で組むか**：メンテナーが、`kansuji` が整数の表記を自分で組むことでよいと決めた。

## 参考文献

- 日本語組版処理の要件（JLReq）、W3C Working Group Note。https://www.w3.org/TR/jlreq/
- 文化庁、公用文作成の考え方（2022）。https://www.bunka.go.jp/seisaku/bunkashingikai/kokugo/hokoku/93651301.html
