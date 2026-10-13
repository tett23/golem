# ADR 0005: PDF の Producer に Golem の版を書く

ステータス: 採択

## 文脈

[仕様書](../../specifications.md)の「メタデータ」の節は、PDF の Producer に Golem の版を書くと定め、Golem を更新すると出力のバイト列が変わっても、処理系は入力の一部なので決定性に反しないとしている。
`Golem.Pdf.Writer.writePdf` は Producer を書いていない。
文書情報辞書（Info）に書くのは `Title`、`CreationDate`、`ModDate` と、出力インテントがあるときの `Trapped` と `GTS_PDFXVersion` だけである。
XMP（`Golem.Pdf.X4.xmpPacket`）も `pdf:Producer` を持たない。

[docs/adr/0004](../../adr/0004-binary-distribution-and-release.md) は、版の正本をリポジトリの根の `VERSION` とし、golem-driver の `Golem.Driver.Version.golemVersion` にコンパイルの時点で埋め込むと決めた。
値は `0.1.0` や `0.1.0-rc1` の形で、`scripts/release/check-version.sh` が `^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$` に合うことを CI で検査する。
同じ ADR は、Producer への版の書き込みを、PDF の出力を変える変更として範囲から外した。

インスタンス ID は、すでに Golem の版を入力に含んでいる。
`Golem.Driver.Pdf.instanceIdInputs` は、入力の末尾に `"golem-" <> golemVersion` を加える。
したがって、版が変われば、今でも PDF のバイト列（トレーラーの `/ID` と XMP の `xmpMM:InstanceID`）は変わる。

[ADR 0002](0002-pdf-x-4.md) は、XMP のメタデータを規格の要求に従って書くことを求める。
PDF/X-4 は、文書情報辞書と XMP の両方にある項目の値を一致させることを求めると一般に知られている。
[ADR 0002](0002-pdf-x-4.md) と同じく、規格の本文ではこの要件を確かめていない。

golem-pdf は golem-driver に依存しない。
`golemVersion` は golem-driver にあるので、golem-pdf は版を自分で読めない。

## 実装すること

### Producer の文字列

- Producer は `"Golem " <> golemVersion` とする（例：`Golem 0.1.0-rc1`）。
- 文字列は `VERSION` の内容だけから作り、Git のコミットやビルドの環境を含めない。版の文字列がソースだけで決まるという [docs/adr/0004](../../adr/0004-binary-distribution-and-release.md) の方針を保つためである。

### golem-pdf

- `Golem.Pdf.Writer.Document` に `docProducer :: !Text` を加える。golem-pdf は渡された文字列をそのまま書き、版の意味を知らない。
- `writePdf` は、文書情報辞書に `Producer` を加える。出力インテントの有無にかかわらず書く。
- 値は PDF の文字列として書く。`pdfTextString :: Text -> Obj` を Writer に加え、すべての文字が印字可能な ASCII（0x20 から 0x7E）なら `OStr`（括弧の文字列）、そうでなければ `Title` と同じ UTF-16BE の `OHex` を返す。`VERSION` の形は ASCII に限られるので、Golem の出力では括弧の文字列になる。
- `xmpPacket` に Producer の引数を加え、`<pdf:Producer>` に `escapeXml` した値を書く。位置は `xmpMM:RenditionClass` の行の後、`pdf:Trapped` の行の前とし、順序を固定する。`pdf` の名前空間はすでに宣言している。
- Info のキーは `serialize` が名前の順に並べるので、`Producer` の位置は自動で決まる。

### golem-driver

- `Golem.Driver.Pdf.writeDocument` の `P.Document` に `P.docProducer = producer` を加える。
- `producer :: Text` を `Golem.Driver.Pdf` に置いて公開し、`"Golem " <> golemVersion` とする。テストがこの関数を参照する。

### インスタンス ID との関係

インスタンス ID の計算は変えない。
Producer は `golemVersion` だけから作り、`golemVersion` はすでにインスタンス ID の入力の末尾にある。
このため、Producer が異なる二つの PDF は、必ずインスタンス ID も異なる。

文書 ID（マニフェストの `id` から導く）も変えない。
文書 ID は同じ文書の版をまたいで変わらない値であり、Golem の版を含めない。

### 決定性

Producer は時計も環境も読まないので、同じ版の Golem と同じ入力からは同じバイト列になる。
版が変われば Producer は変わるが、[docs/adr/0002](../../adr/0002-determinism.md) が「異なる版の Golem の間での出力の一致」を求めないとしたとおり、決定性には反しない。
CI の `determinism` ジョブは同じビルドの実行ファイルどうしを比べ、リリースの `determinism` ジョブも同じ版の配布物どうしを比べるので、どちらも影響を受けない。

### XMP と文書情報辞書の一致

両方に現れる項目は、次の対応で同じ値にする。

| 文書情報辞書 | XMP |
|---|---|
| `Title` | `dc:title` の `x-default` |
| `CreationDate` | `xmp:CreateDate` |
| `ModDate` | `xmp:ModifyDate` |
| `Producer` | `pdf:Producer` |
| `Trapped` | `pdf:Trapped` |

日時は書式が異なる（`D:20261011000000Z` と `2026-10-11T00:00:00Z`）が、どちらもマニフェストの `metadata.date` の同じ日の 0 時（UTC）を表す。
XMP の `dc:creator` に当たる `Author` は文書情報辞書に書いていないので、対応の外にある。

### ドキュメント

- 仕様書の「v1 の実装で次の段階以降に回した項目」から PDF の Producer を除く。
- 仕様書の「メタデータ」の節に、Producer の形（`Golem ` に版を続けたもの）と、文書情報辞書と XMP の両方に書くことを加える。

## 実装しないこと

- XMP の `xmp:CreatorTool` と文書情報辞書の `Creator`。原稿を書いた道具は Golem ではなくエディタであり、Golem は PDF を作る側（Producer）だけを名乗る。
- 文書情報辞書の `Author`。XMP の `dc:creator` との対応は別に扱う。
- Producer へのコミットのハッシュ、ビルドの日時、プラットフォームの書き込み。ビルドの環境は `BUILDINFO`（[docs/adr/0004](../../adr/0004-binary-distribution-and-release.md)）に記録する。
- Producer の文字列を利用者が変える設定。
- HTML、EPUB、プレーンテキストへの Golem の版の書き込み。

## テスト設計

### golem-pdf（`modules/golem-pdf/test/Main.hs`）

テストの `Document` には、`golemVersion` に依存しない固定の文字列（`"Golem 0.0.0-test"`）を渡す。
golem-pdf の golden が、版を上げるたびに変わらないようにするためである。

- 出力インテントのない `sample` を書いた PDF の文書情報辞書に `/Producer (Golem 0.0.0-test)` があること。
- 出力インテントのある PDF で、文書情報辞書の `/Producer (Golem 0.0.0-test)` と、XMP の `<pdf:Producer>Golem 0.0.0-test</pdf:Producer>` が両方あること。
- `pdfTextString "Golem 0.1.0-rc1"` が `OStr "Golem 0.1.0-rc1"` で、`pdfTextString "ゴーレム"` が `FE FF` で始まる `OHex` であること。
- Producer に `<` と `&` を含む文字列を渡したとき、XMP では `&lt;` と `&amp;` に置き換わること。
- `test/golden/xmp.xml` の golden に `<pdf:Producer>Golem 0.0.0-test</pdf:Producer>` の行を加え、golden を先に書き換えて失敗させてから実装する。
- 文書情報辞書と XMP の一致を検査するテストを加える。出力インテントのある PDF から、文書情報辞書の `Title`（UTF-16BE を復号したもの）、`CreationDate`、`ModDate`、`Producer`、`Trapped` と、XMP の対応する項目を取り出し、前の節の表のとおりに一致すること。

### golem-driver（`modules/golem-driver/test/Main.hs`）

- `producer` が `"Golem " <> golemVersion` と一致すること。
- `buildMini` で作った PDF の文書情報辞書に `"/Producer (" <> producer <> ")"` があり、出力インテントのある設定では XMP に `<pdf:Producer>` と `producer` があること。
- 既存の「`instanceIdInputs` の末尾が `"golem-" <> golemVersion` である」テストを変えずに通すこと。
- `golemVersion` が `check-version.sh` の正規表現に合うこと。Producer が括弧の文字列として書かれることの前提になる。

## トレードオフ

Producer が版を含むので、PDF のバイト列を丸ごと固定する golden テストは、版を上げるたびに書き直しになる。
今の Golem には PDF のバイト列の golden はなく、PDF のテストは部分の検査と同じビルドの二回の比較で書かれている。
インスタンス ID がすでに版を含んでいるので、Producer を足しても、版をまたいだバイト列の比較ができないという状況は変わらない。
ページの見た目の回帰を版をまたいで調べるには、バイト列ではなく、ページの画像やページの記述（`Golem.Pdf.Writer.Page`）を比べる必要がある。

golem-pdf のテストは固定の Producer を使うので、golem-pdf の golden は版の変化に影響されない。
その代わり、実際の版の文字列が書かれることは、golem-driver のテストだけが確かめる。

プレリリースの識別子（`-rc1`）が Producer に入るので、rc と正式のリリースでは同じ入力の PDF の Producer が異なる。
入稿の後で、どの版の Golem で作った PDF かを Producer で区別できることを優先する。
