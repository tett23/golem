# ADR 0013: 輪郭の表のないフォントは G08003 とし、G08018 は埋め込みの防御として残す

ステータス: 採択

## 文脈

[ADR 0011](0011-cff-fontfile3-subtype.md) は、CFF のフォントの埋め込みで `CFF ` の表を取り出せないとき、G08018 のエラーにすると決めた。
テスト設計は二つの項目を挙げる。

- golem-driver の `Golem.Driver.Fonts` で、`CFF ` の表を持たない OpenType のバイト列（`CFF ` を別の名前に書き換えた Source Sans Pro など）を CFF のフォントとして埋め込もうとすると、G08018 になること。
- そのフォントを `[fonts.body]` に書いたプロジェクトの PDF のビルドが、`style.toml` の先頭に G08018 を一つ出し、PDF を書かないこと。

テストの質の点検（2026-10-23）で、二つめの項目を満たすテストがないことが分かった。
golem-driver の [test/PdfSpec.hs のテスト](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/PdfSpec.hs#L83-L91) は、フォントの読み込みの `lfEmbed` を、常に G08018 を返す関数に差し替えてビルドしている。
差し替えをやめ、`CFF ` の表を `CFX ` に改名した Source Sans Pro を本物の `golemFontProvider` で読むと、ビルドは G08018 ではなく G08003（フォントを読み込めません）を出した。

原因は、フォントの読み込みが埋め込みより先に失敗することにある。

- golem-font の `golem_font_open`（[modules/golem-font/cbits/golem/golem_font.c](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-font/cbits/golem/golem_font.c#L35-L43)）は、FreeType の `FT_New_Memory_Face` が失敗すると NULL を返す。改名したフォントには `CFF ` の表も `glyf` の表もないので、FreeType は開けない。`loadFont` は `Unreadable` になり、`Golem.Driver.Fonts` が G08003 を出す。ビルドは、G08018 を判定する埋め込みまで進まない。
- フォントを CFF とみなすか（`fontIsCff`）は、`CFF ` の表の長さが 0 より大きいかで決まる。CFF とみなされたフォントは、元のファイルに `CFF ` の表を持つ。
- 埋め込みで G08018 になるのは、CFF とみなされたフォントで、サブセット（作れなければ元のフォント）から空でない `CFF ` の表を取り出せない場合だけである。プロジェクトに置いたフォントからこの状態を作る入力は、まだ見つかっていない。

改名したフォントは輪郭を持たず、フォントとして開けない。
これは「CFF の表を取り出せない」より前の原因であり、G08003 の意味（OpenType のフォントとして開けない）に当たる。
G08018 に寄せると、一つのコードに二つの原因（開けない、開けたが埋め込めない）を持たせることになる。
メンテナーは、G08003 が正しいとみなし、G08018 は埋め込みの防御として残すと決めた。

## 実装すること

### G08003 と G08018 の分担

- 輪郭の表（`CFF ` も `glyf` も）がないフォントは、今のとおり G08003 とする。コードの振る舞いは変えない。
- G08018 は、今のとおり埋め込みの段階の防御として残す。CFF とみなしたフォントのサブセットから `CFF ` の表を取り出せないとき、OpenType のまま黙って埋め込まずにエラーにする（[ADR 0011](0011-cff-fontfile3-subtype.md)）。

### テスト

- [ADR 0011](0011-cff-fontfile3-subtype.md) のテスト設計の二つめの項目は、この ADR のテスト設計で置き換える。
- [test/PdfSpec.hs の、`lfEmbed` を差し替えたテスト](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/PdfSpec.hs#L83-L91) は残す。確かめているのは「埋め込みが返したエラーを、ビルドが `style.toml` の先頭のエラーとして出し、PDF を書かない」ことなので、テストの名前と注釈をそのとおりに直す。
- 改名したバイト列を `cffFontProgram` に渡して G08018 になることを確かめる [今のテスト](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/PdfSpec.hs#L76-L79) は、本物の関数を試しているので残す。

### 主な原因の確かめ

docs/diagnostics.md の G08018 の「主な原因」は、確かめていない二つの原因（表の目録が壊れている、フォントのコレクションの `.ttc` を指している）を挙げる。
実装のとき、次の二つのフォントを本物の `golemFontProvider` で読むビルドを実際に試す。

- `CFF ` の表の目録の位置か長さを壊した Source Sans Pro
- CFF のフォントを含む `.ttc`（リポジトリにあるフォントから作れなければ、試せなかったと記録する）

どちらも、出たコード（G08003、G08018、エラーなし）をテストで固定する。
G08018 の「主な原因」には、試して G08018 になった原因だけを書く。
どの入力でも G08018 にならなければ、「主な原因」を「プロジェクトのフォントからは通常は起きない。埋め込みの処理の不具合を防ぐためのエラーである」と書き直す。

### ドキュメント

- docs/diagnostics.md の G08003 の「主な原因」に、「輪郭の表（`CFF ` も `glyf` も）がない」を足す。
- docs/diagnostics.md の G08018 の「意味」と「主な原因」を、上の確かめの結果に合わせて直す。
- 使い手のマニュアルの付録 E の G08018 の説明を、同じく直す。
- docs/specifications.md の「フォント」の節の G08018 の文は、埋め込みの規則としては正しいので変えない。
- [ADR 0011](0011-cff-fontfile3-subtype.md) のステータスの行の末尾に、次を足す。

  ```
  、テスト設計の二つめの項目と、輪郭の表のないフォントの扱いは [ADR 0013](0013-renamed-cff-table-is-g08003.md)
  ```

## 実装しないこと

- 輪郭の表がないことを、G08003 と別のコードにすること。原因は「OpenType のフォントとして開けない」に含まれる。
- G08018 を消すこと。埋め込みの処理（サブセットや表の取り出し）の不具合で `CFF ` の表を失ったとき、OpenType のまま黙って埋め込むのを防ぐ。
- golem-font の読み込みの振る舞いを変えること。モジュールのあいだの依存も変えない。

## テスト設計

今の振る舞いを固定するテストなので、先に書いても失敗しない。
実装のときに、テストの期待値を G08018 に変えると失敗することを一度確かめる（テストが本物の経路を通っていることの確かめ）。

- golem-driver の [test/PdfSpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/PdfSpec.hs)：`CFF ` の表を `CFX ` に改名した Source Sans Pro（golem-font のテストのフォント）を `[fonts.body]` に書いたプロジェクトを、本物の `golemFontProvider` でビルドする。`style.toml` の先頭に G08003 を一つ出し、メッセージが `フォントを読み込めません: fonts/sans.otf` で、PDF を書かないこと。
- golem-driver の [test/PdfSpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/PdfSpec.hs)：`lfEmbed` を差し替えたテストの名前と注釈を、埋め込みのエラーの扱いを確かめるものに直す。断言は変えない。
- golem-driver の [test/PdfSpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/PdfSpec.hs)：「主な原因の確かめ」の二つのフォントで、出たコードを固定する。
- golem-syntax の、docs の diagnostic の一覧とコードの一致の検査が通ること。

## トレードオフ

- G08018 は、プロジェクトの入力からはほぼ届かないコードになる。届く入力が見つかっていないコードを持つのは、テストで確かめられない分岐を残すことである。それでも、届いたときに PDFium で描けない PDF を黙って書くよりは、エラーにするほうがよい。意図しない振る舞いを黙って通すことも、それを知らせずに済ませることも、許容できない。仕様書の [設計原則](../../specifications.md#設計原則) の「緩い規則より厳しい規則」は、入力が仕様に反するときに推測で補って組まず誤りとして止めること、書き手の入力と違う出力を黙って作らないことを定めており、G08018 を残すのはこの原則に従うためである。

## 参考文献

- [ADR 0011](0011-cff-fontfile3-subtype.md)
- テストの質の点検（2026-10-23）。リポジトリの外の記録である。
