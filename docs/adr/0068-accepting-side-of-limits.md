# ADR 0068: 上限ちょうどの入力が通ることを、拒む側と対にして確かめる

ステータス: 採択

## 文脈

上限のテストが拒む側だけだと、上限を 0 にした実装でも、上限の比較を一つずらした実装でも通る。
上限の値とその境界（「以下」か「未満」か）を固定するには、上限ちょうどが通り、一つ超えると拒まれる対が要る。
2026-10-23 のテストの品質の点検と、その確認で、次の六つに受け入れ側か境界の対がないことを確かめた。

| 上限 | 定める場所 | 今のテスト | 欠けているもの |
|---|---|---|---|
| プラグインのテーブルの要素 100 万 | [ADR 0035](0035-security-hardening.md) の 65 行め、[golem_plugin.c の `GOLEM_TABLE_ELEMENTS`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-plugin/cbits/golem_plugin.c#L15-L16) | 2000 万で `InstantiateFailed`（[modules/golem-plugin/test/Main.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-plugin/test/Main.hs#L199-L203)） | 100 万で起動でき、100 万 1 で起動できない対 |
| PNG の ICC プロファイル 32 MiB | docs/specifications.md:1791 は「32 MiB 以下」 | 64 MiB で拒む（[modules/golem-pdf/test/ImageSpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-pdf/test/ImageSpec.hs#L299-L301)） | ちょうど 32 MiB で読め、32 MiB + 1 で拒む対 |
| PNG のフィルタの前の画素のデータ 512 MiB | docs/specifications.md:1791 は「512 MiB 以下」 | 30000×30000 の 16 ビット RGBA で拒む（[modules/golem-pdf/test/ImageSpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-pdf/test/ImageSpec.hs#L289-L290)） | ちょうど 512 MiB で「大きすぎ」にならず、1 バイト超えると拒む対 |
| PDF の取り込みで展開する合計 256 MiB | docs/specifications.md:1801、[golem-pdf の `maxDecodedBytes`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-pdf/src/Golem/Pdf/Import.hs#L165-L166) | 合計 256 MiB + 1 で拒み、256 MiB − 1 で読む（[modules/golem-pdf/test/SecuritySpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-pdf/test/SecuritySpec.hs#L229-L238)） | 合計ちょうど 256 MiB |
| 正規表現の繰り返しの回数 65535 | [modules/golem-regex/src/Golem/Regex.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-regex/src/Golem/Regex.hs#L206) | `a{70000}` が位置 1 のエラー（[modules/golem-regex/test/Main.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-regex/test/Main.hs#L214)） | 65535 と 65536 の対。今のテストは位置しか見ず、命令の数の上限（[全体の検査](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-regex/src/Golem/Regex.hs#L137) と [群ごとの検査](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-regex/src/Golem/Regex.hs#L219)）とどちらで拒まれたかを区別しない |
| diagnostic の抜粋 200 文字 | docs/specifications.md:1996 | 100、300 文字と、長い行の中ほど（[modules/golem-syntax/test/RenderSpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-syntax/test/RenderSpec.hs#L112-L127)） | ちょうど 200 文字の行がそのまま書かれ、201 文字の行が切られる対 |

点検の報告は SVG の大きさの数 1e9 も挙げたが、受け入れ側はすでにある。
数の読み取りで `1e9` と `1000000000` が読め、`1e10` と `1.000000001e9` が読めないことを [modules/golem-svg/test/NumberSpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-svg/test/NumberSpec.hs#L62-L65) が確かめ、半径 `1e9` が読めることを [modules/golem-svg/test/SecuritySpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-svg/test/SecuritySpec.hs#L272-L274) が確かめている。

## 実装すること

上の六つに、境界の対のテストを足す。
上限の値は変えない。
実装で変えるのは、正規表現の繰り返しの回数のエラーのメッセージだけである（下の「正規表現の繰り返しの回数の上限」）。
テストが今の実装で落ちれば、仕様（「以下」）に合わせて実装を直す。

- プラグイン：要素 1000000 と 1000001 のテーブルを持つ二つの wat を [modules/golem-plugin/test/plugins/](https://github.com/tett23/golem/tree/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-plugin/test/plugins) に置く。前者は起動でき、後者は `InstantiateFailed` になる。対で原因を特定できるので、wasmtime の言い回しに依存するメッセージは断言しない。今の 2000 万のテストは残す。
- ICC：iCCP をちょうど 32 MiB と 32 MiB + 1 に展開する PNG。前者は ICC の大きさの理由で拒まれない。
- PNG の画素：IHDR の幅、高さ、ビット深度、色の種類から計算した画素のデータがちょうど 2^29 バイトになる IHDR と、それを 1 行だけ増やした IHDR。前者は `PNG の画像が大きすぎます` にならない（IDAT が足りないので別の理由で `Left` になってよい）。後者は `PNG の画像が大きすぎます` になる。
- PDF の取り込み：`Contents` の二つのストリームの展開の合計がちょうど 256 MiB になる PDF が読める。
- 正規表現：`(?:){65535}` と `(?:){65536}` のように命令の数の上限にかからない形で、回数の上限の境界を確かめる。前者がエラーにならなければ通り、後者は `繰り返しの回数が上限の 65535 回を超えています` のメッセージで拒まれる。空の群の繰り返しが命令の数に数えられる場合は、実装のときに命令の数にかからない別の形を選ぶ。`a{70000}` のテストにメッセージの断言を足す。
- 抜粋：ちょうど 200 文字の行はそのまま、201 文字の行は 200 文字と `…` で書かれる。

### 正規表現の繰り返しの回数の上限

繰り返しの回数の上限 65535 を仕様書に書き、エラーのメッセージがその上限を述べるようにする。

- docs/specifications.md の正規表現の節の、G03015 の条件を書いた段落に、繰り返しの回数の上限を足す。「量指定子の展開を含めて 10000 命令を超える正規表現」と並べて、「繰り返しの回数に 65535 を超える数を書いた正規表現」をエラー（G03015）とする。
- golem-regex の繰り返しの回数のエラーのメッセージを `繰り返しの回数が上限の 65535 回を超えています` にする。今のメッセージ `繰り返しの回数は 65535 までです`（[modules/golem-regex/src/Golem/Regex.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-regex/src/Golem/Regex.hs#L206)）は、比較の値とは別に数を文字列へ直接書いている。命令の数の上限のメッセージ（[`tooLarge`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-regex/src/Golem/Regex.hs#L142-L143)）と同じく、上限を定数にし、比較とメッセージの両方をその定数から作る。G03015 のメッセージは `正規表現を解釈できません: 繰り返しの回数が上限の 65535 回を超えています（<段落スタイル> の <n> 番目の正規表現の <位置> 字目）` になる。
- docs/diagnostics.md の G03015 の節の「主な原因」で、繰り返しの回数の項にこのメッセージの文言を添える。
- マニュアルの付録 E（manual/appendices/e-errors.gm）の G03015 の項は、メッセージを `正規表現を解釈できません: …` とだけ載せており、理由の文言を載せていない。理由の文言が載っていれば合わせて直すが、今は載っていないので変えない。
- golem-regex の仕様書の「繰り返しの回数は 65535 までとする」は、今のまま残す。

## 実装しないこと

- 上限の値を変えること。

## テスト設計

先に対のテストを書き、次の変異で落ちることを確かめる。
今のテストはどれもこの変異で落ちない。

- 上限の比較の `>` を `>=` に変えた変異（ICC、画素、取り込みの合計、抜粋）。
- プラグインの上限を 0 にした変異。今の 2000 万のテストはこれで落ちない。
- 正規表現の 65535 の比較を 1000 にした変異。今の `a{70000}` のテストは、70000 が 1000 も超えるので同じ位置で拒まれ、落ちない。

メッセージのテストは、メッセージを変える前に書いて落ちることを確かめる。

- golem-regex：`compile "a{70000}"` と `compile "(?:){65536}"` の `Left` のメッセージが `繰り返しの回数が上限の 65535 回を超えています` に一致する。今の実装では落ちる。
- golem-regex：`(?:){65535}` が通り `(?:){65536}` が拒まれる対と、メッセージが上限の数 `65535` を含むことを、両方断言する。比較の値だけを変えた変異では対のテストが落ち、メッセージの数だけを変えた変異ではメッセージのテストが落ちる。
- golem-project：`regex-styles = [{ pattern = "a{65536}", style = "bold" }]` の G03015 のメッセージが、`正規表現を解釈できません: 繰り返しの回数が上限の 65535 回を超えています` で始まる。

## トレードオフ

- 512 MiB と 256 MiB の境界のテストは、大きな入力を作る。画素の境界は IHDR だけで試し、データを展開しないので軽い。取り込みの合計は、今の 256 MiB − 1 のテストと同じく 256 MiB を展開するので、時間と割り当てが今のテストと同じだけ増える。今のテストの 120 秒の時間切れの中に収まることを、実装のときに確かめる。
- プラグインの 100 万の要素のテーブルは、起動に時間とメモリを使う。funcref の 100 万の要素は 8 MB 程度と見込むが、実装のときに測る。
- 繰り返しの回数のメッセージが変わる。前のメッセージを固定したテストやゴールデンはなく、利用者の目に触れる文言が、上限を超えたことと上限の値を述べる形になるだけである。

## 参考文献

- [ADR 0035](0035-security-hardening.md)
- [ADR 0040](0040-pdf-import-resource-limits.md)
