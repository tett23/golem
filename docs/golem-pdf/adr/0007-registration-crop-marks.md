# ADR 0007: トンボをレジストレーションの色で描く

ステータス: 採択

## 文脈

[ADR 0004](0004-crop-marks-and-bleed.md) は、トンボを DeviceCMYK の C、M、Y、K の各 100% の塗りで描くと決めた。
[ADR 0002](0002-pdf-x-4.md) が v1 をプロセスカラーだけとし、スポットカラー（Separation と DeviceN の色空間）を v2 以降に回したので、レジストレーションの色（Separation の `All`）を使えなかったためである。
CMYK の各 100% は、四つのプロセスの版のすべてに線を出す点ではレジストレーションの色と同じだが、インキの総量が 400% になる。
[仕様書](../../specifications.md)の「未決事項」は、プリフライトの設定によっては総量の警告が出ると考えられること、警告が出る場合にレジストレーションの色を使うかが決まっていないことを挙げている。

ユーザーは、トンボに限ってレジストレーションの色を許すと決めた。
本文、図版、罫線、柱、ノンブルの色は、v1 の範囲（プロセスカラーだけ）のまま変えない。

### 今の実装

- `Golem.Pdf.Marks.framePage` は、トンボを `Saved (SetColor (Swatch 100 100 100 100) : map Rule (markRules ...))` としてページの内容の後に描く。
- `Golem.Pdf.Writer.contentStream` は、`SetColor` を `1 1 1 1 k 1 1 1 1 K` と書き、`Rule` を `re f` と書く。
- ページの `Resources` は、全ページに共通の一つの辞書で、`Font` と `XObject` だけを持つ。`ColorSpace` はない。
- `Swatch` は CMYK の四つの百分率だけを持つ型であり、`style.toml` の色（`stSwatches`）もこの形に限られる。原稿と `style.toml` から特色を書く手段はない。
- `Golem.Pdf.X4.checkPdfX` は、ページの箱の包含だけを検査する。色空間は検査しない。

### レジストレーションの色と PDF/X-4

以下は記憶によるもので、規格の本文と照合していない。

- PDF の仕様（ISO 32000）は、Separation の色材の名前 `All` を、すべての版（プロセスとスポットの両方）に出る特別な色材と定め、見当合わせのトンボなどに使うものとしている。`All` の色は代替の色空間を使わずにすべての版に出力され、代替の色空間（tint transform）は画面の表示と合成の出力にだけ使われる。
- PDF/X-4 は Separation の色空間を許す。PDF/X-4 の要件で `All` の使用を禁じるものはないと理解している。PDF/X の系列の規格に、`All` の使用を仕上がりの外（トンボの領域）に限るような要件があったかどうかは確かめていない。

InDesign のトンボはレジストレーションのスウォッチ（`[レジストレーション]`）で描かれる。
これは記憶と、Adobe のコミュニティの回答（トンボはレジストレーションのスウォッチで作るべきだという回答）によるもので、Adobe の公式のヘルプでは確かめられなかった。

Golem のトンボは、[ADR 0004](0004-crop-marks-and-bleed.md) の計算で、どの線も BleedBox の内部と重ならず、MediaBox の内側に収まる（golem-pdf のテストで確かめている）。
したがって、`All` の使用を仕上がりの外に限る要件があったとしても、トンボに限って `All` を使う限り満たされる。

## 実装すること

### 色空間の書き方

トンボの色を、次の Separation の色空間の濃度 1.0 の塗りにする。

```
[/Separation /All /DeviceCMYK
  << /C0 [0 0 0 0] /C1 [1 1 1 1] /Domain [0 1] /FunctionType 2 /N 1 >>]
```

- 代替の色空間は DeviceCMYK とする。出力インテントが CMYK（Japan Color 2001 Coated）なので、代替の色空間を出力インテントと同じ CMYK の色空間にそろえる。
- tint transform は Type 2（指数補間）の関数とし、濃度 0 を CMYK の 0%、濃度 1 を各 100% に写す。画面の表示と合成の出力では、今と同じ CMYK の各 100% の黒に見える。
- 関数と色空間の配列は、間接オブジェクトにせず、ページの `Resources` の `ColorSpace` の辞書に直接の値として書く。オブジェクトの番号の振り方（[ADR 0001](0001-deterministic-pdf-writer.md)）を変えずに済むためである。
- 色空間の資源の名前は `/Reg` とする。
- 内容のストリームでは、`/Reg cs 1 scn` で塗りの色を設定する。トンボは塗り（`re f`）だけで描くので、線の色（`CS` と `SCN`）は設定しない。

### Writer の変更（`Golem.Pdf.Writer`）

- `Mark` に `RegistrationRules ![Rect]` を加える。`contentStream` は `q`、改行、`/Reg cs 1 scn`、改行、各矩形の `<x> <y> <w> <h> re f`、改行、`Q`、改行を書く。
- `writePdf` は、どれかのページの内容（`Saved` と `Translated` の内側を含む）に `RegistrationRules` があるときに限り、ページの `Resources` に `ColorSpace << /Reg [...] >>` を加える。ないときは今と同じ `Resources` を書く。`fontsOf` と `imagesOf` と同じく、内容を辿る関数 `usesRegistration :: Mark -> Bool` を置く。
- `Swatch` と `SetColor` は変えない。`SetColor` は今のとおり DeviceCMYK のプロセスカラーだけを書く。

### トンボの描き方（`Golem.Pdf.Marks`）

`framePage` のトンボを次のように変える。

```haskell
drawn = [RegistrationRules (markRules st bleed size) | Just st <- [marks]]
```

`Saved` と `SetColor` で囲まない。
`RegistrationRules` が自身で `q` と `Q` を書き、色の設定をその内側に閉じ込めるためである。

### スポットカラーをトンボの外に出さない保証

レジストレーションの色を、型と公開の範囲でトンボに閉じ込める。

- `RegistrationRules` は Separation を書く唯一の `Mark` であり、色材の名前は `All` に固定する。色材の名前を引数に取る構成子は作らない。
- `Golem.Pdf` は、`Golem.Pdf.Writer` を `hiding (RegistrationRules)` で取り込んで再び公開する。golem-driver は `Golem.Pdf` だけを取り込んでいるので、`RegistrationRules` を作れない。`RegistrationRules` を作れるのは、`Golem.Pdf.Writer` を直接取り込む golem-pdf の中のモジュール（`Golem.Pdf.Marks`）とテストだけになる。
- `Golem.Pdf.Marks` に、ページの内容の中の `RegistrationRules` の矩形を、`Translated` の移動を足したページの座標で返す `registrationRects :: [Mark] -> [Rect]` を置く。
- `Golem.Pdf.Marks` に `checkRegistration :: [Page] -> [Int]` を置き、`RegistrationRules` の矩形がそのページの BleedBox の内部と重なるページの番号（1 から）を返す。`checkPdfX` と同じく、守られていれば空のリストを返す。`Golem.Pdf.X4` は `Golem.Pdf.Writer` に取り込まれる側なので、`Mark` を扱う検査は `Golem.Pdf.Marks` に置く。
- `Swatch` に色材の名前を加えない。`style.toml` の色は今のとおり CMYK の値だけであり、本文、図版、罫線の色が Separation になる道はない。

[ADR 0003](0003-pdf-x-4-validator.md) は、CI での PDF/X-4 の検証を、[ADR 0002](0002-pdf-x-4.md) の要件ごとの検査と `qpdf --check` で行うと決めた。
この ADR は、その要件ごとの検査に、「Separation の色空間は `All` だけであり、トンボの矩形だけに使い、トンボは BleedBox の内部と重ならない」を加える。
外部の検証器を使わない方針は変えない。

### 決定性

- 色空間と関数の値は定数であり、辞書のキーは今のとおり整列して書く。
- `ColorSpace` の有無は、ページの内容（`--marks` の値）だけで決まる。`--marks` はインスタンス ID の入力に入っている（[ADR 0004](0004-crop-marks-and-bleed.md)）。
- `--marks none` の PDF は、この変更の前とバイト列が変わらない。

### ドキュメント

- 仕様書の CLI の節の「トンボの線は太さ 0.25pt、長さ 10mm で、CMYK の各 100% で描く。」を「トンボの線は太さ 0.25pt、長さ 10mm で、レジストレーションの色（Separation の `All`）で描く。」に改め、この ADR へのリンクを付ける。
- 仕様書の「意図的に採用しなかったもの」の「スポットカラー」の項目に、トンボのレジストレーションの色だけは例外とすることを書き、この ADR へのリンクを付ける。
- 仕様書の「v2 以降に回した事項」の「スポットカラー」の項目から、「トンボをレジストレーションの色（Separation の `All`）で描くかも、このときに決める」の文と、その後の [ADR 0004](0004-crop-marks-and-bleed.md) へのリンクを除く。
- 仕様書の「未決事項」から「トンボのインキの総量」の項目を除く。
- 仕様書の「色」の節に、PDF の色はプロセスカラーだけで、例外はトンボのレジストレーションの色だけであることを書く。
- 用語集に、レジストレーションの色を加える。
- [ADR 0002](0002-pdf-x-4.md) のステータスの行を「採択→検証ツールの選定は [ADR 0003](0003-pdf-x-4-validator.md)、トンボのレジストレーションの色（Separation の `All`）は [ADR 0007](0007-registration-crop-marks.md)」に変える。
- [ADR 0004](0004-crop-marks-and-bleed.md) のステータスの行を「採択→トンボの色は [ADR 0007](0007-registration-crop-marks.md)」に変える。

### 診断

新しい診断は加えない。
レジストレーションの色の使い道は型と公開の範囲で閉じており、利用者の入力から誤った使い方が生じないためである。

## 実装しないこと

- スポットカラー（`All` 以外の色材の Separation と DeviceN）。v2 以降のまま変えない。
- 本文、図版、罫線、柱、ノンブルをレジストレーションの色で描くこと。`style.toml` にレジストレーションの色の名前を設けることもしない。
- レジストレーションの色の画像。
- カラーバー、レジスターマーク（円と十字の見当合わせの印）、ページの情報の印字。[ADR 0004](0004-crop-marks-and-bleed.md) のとおり実装しない。
- トンボの色を選ぶ設定（CMYK の各 100% に戻すオプションなど）。
- `checkRegistration` を golem-driver のビルドの中で毎回走らせて診断にすること。トンボの座標は `markRules` の定数の計算で決まり、入力によって BleedBox の内部に入ることはないので、テストで確かめれば足りる。

## テスト設計

### golem-pdf（`modules/golem-pdf/test/Main.hs`）

テストは `Golem.Pdf.Writer` を直接取り込んで `RegistrationRules` を使う。

- `contentStream Map.empty Map.empty [RegistrationRules [Rect 0 0 65536 65536]]` が `q\n/Reg cs 1 scn\n0 0 1 1 re f\nQ\n` になること。
- `RegistrationRules` を含むページの PDF の `Resources` に `/ColorSpace << /Reg [/Separation /All /DeviceCMYK << /C0 [0 0 0 0] /C1 [1 1 1 1] /Domain [0 1] /FunctionType 2 /N 1 >>] >>` があること。
- `RegistrationRules` を含まない PDF に `/ColorSpace` も `/Separation` もないこと。既存の golden とバイト列の比較が変わらないことでも確かめる。
- `RegistrationRules` が `Translated` と `Saved` の内側にだけあるページでも、`ColorSpace` の資源が書かれること。
- `framePage (Just Japanese) b (w, h) content` の内容が `[Translated m m (content <> [RegistrationRules (markRules Japanese b (w, h))])]` であること（既存の「CMYK で描く」のテストを置き換える）。
- `framePage Nothing` の内容に `RegistrationRules` がないこと。
- 日本式と欧文のトンボ、塗り足しの 0 と 3mm の各組み合わせで、`framePage` のページの `checkRegistration` が空のリストを返すこと。
- `RegistrationRules [Rect 0 0 65536 65536]` を仕上がりの内側に置いたページで、`checkRegistration` がそのページの番号を返すこと。
- `registrationRects` が `Translated` の移動を足した座標を返すこと。
- 既存のプロパティテスト（任意のページの内容を決定的に書き、相互参照が正しいこと）の生成器に `RegistrationRules` を加える。
- `framePage (Just Japanese)` のページを書いた PDF/X-4 の PDF が `qpdf --check` を通ること（qpdf がある環境で）。

### golem-driver（`modules/golem-driver/test/Main.hs`）

- `bleed = "3mm"` と `optMarks = JapaneseMarks` の PDF の内容のストリームが `/Reg cs 1 scn` を含み、`1 1 1 1 k` を含まないこと（既存のテストの `1 1 1 1 k` の確認を置き換える）。
- 同じ PDF で、`/Separation` が一度だけ（`Resources` の中に）現れ、その色材の名前が `/All` であること。
- `optMarks = NoMarks` の PDF に `/Separation` がないこと。
- スウォッチで色を付けた文字と、トンボを含む PDF で、文字の色が `k` の DeviceCMYK のままであること。
- `Golem.Pdf` から `RegistrationRules` が見えないことは、golem-driver のソースが `Golem.Pdf` だけを取り込むことと、コンパイルが通ることで保たれる。golem-driver のテストのソースに `Golem.Pdf.Writer` の取り込みを加えない。

### 手作業の確認

- 日本式のトンボを付けた PDF を Acrobat の出力プレビューで開き、トンボが C、M、Y、K のすべての版に出ること、色材の一覧に `All` 以外の特色が出ないことを確かめる。
- 同じ PDF を Acrobat のプリフライトの PDF/X-4 の検査と、インキの総量の検査にかけ、指摘を記録する。この ADR の前の版（CMYK の各 100%）の PDF でも同じ検査を行い、総量の警告が消えたかを比べる。
- InDesign で同じ判型と塗り足しに日本式のトンボを付けて書き出した PDF のトンボの色空間と見比べる。

## トレードオフ

v1 の「プロセスカラーだけ」に、トンボに限った例外が一つ入る。
例外は型と公開の範囲で golem-pdf の中に閉じているが、PDF の中には Separation の色空間が現れる。
入稿先のプリフライトが「特色の使用」を一律に警告する設定なら、トンボの `All` が警告の対象になる可能性がある（確かめていない）。
CMYK の各 100% なら特色の警告は出ないが、インキの総量の警告が出る可能性がある。
InDesign のトンボと同じ形にそろえるほうを選ぶ。

代替の色空間を DeviceCMYK の各 100% にしたので、`All` を解釈しない処理（画面の表示、合成の出力、一部の変換の処理）では、トンボは今と同じ各 100% の色として扱われる。
その処理の中でインキの総量を測るものがあれば、総量の警告は残る。
