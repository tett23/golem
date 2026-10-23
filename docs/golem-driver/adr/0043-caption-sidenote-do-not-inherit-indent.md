# ADR 0043: キャプションと傍注の段落スタイルは、本文の字下げを引き継がない

ステータス: 採択

## 文脈

組み込みの段落スタイル `caption` と `sidenote` は、`based-on = "body"` で本文の段落スタイル `body` を引き継ぐ（`Golem.Project.Style.builtinParaStyles`、[ADR 0017](0017-pdf-code-blocks.md)）。
キャプションと傍注の組版は、段落スタイルのうち、書体（`font`）、大きさ（`size`）、カーニング、プロポーショナルメトリクス、トラッキング、ベースラインのずれ、アキ量のセットだけを使い、字下げ（`indent`、`first-line-indent`）を掛けない（[ADR 0010](0010-caption-style.md)、[ADR 0011](0011-sidenote-font.md)）。

テストの質を上げる作業（2026-10-23）で、次のことが分かった。

- `body` に `indent = "5zw"` を書くと、G07025（段落スタイルの字下げが大きすぎる）が `body`、`caption`、`sidenote` の三つに出る。G07025 の検査（`Golem.Driver.Pdf.indentDiagnostics`）が、すべての段落スタイルについて、`based-on` で引き継いだ字下げを行長と比べるためである。
- キャプションと傍注は字下げを掛けないので、`caption` と `sidenote` の G07025 は、組版では起きない誤りを報告している。原因は `body` の字下げの一つなのに、三つの diagnostic になる。
- `[paragraph-styles.caption]` に `indent` を書いても、組版は字下げを掛けず、diagnostic も出さない。書き手の入力と違う出力を黙って作っており、仕様書の設計原則（「緩い規則より厳しい規則」）に反する。

メンテナーは、キャプションが本文の字下げを引き継ぐのはおかしいとして、この ADR を起こすと決めた。
コードの段落スタイル `code` が、本文の字下げを持ち込まないよう `body` を根にしない（[ADR 0017](0017-pdf-code-blocks.md)）のと同じ考えである。

## 実装すること

### 字下げを引き継がない

- `caption` と `sidenote` は、`body` から、組版が使うキー（`font`、`size`、`kerning`、`proportional-metrics`、`tracking`、`baseline-shift`、`aki-set` と、文字の見た目を決めるキー）だけを引き継ぐ。字下げ（`indent`、`first-line-indent`）は引き継がない。
- 実装は、組み込みの `caption` と `sidenote` の定義に、字下げの値 0 を明示する形とする（`psIndent = Just 0`、`psFirstLineIndent = Just 0`）。`based-on` の規則（書いた値が引き継いだ値に勝つ）を変えずに済む。

### 使わないキーを書いたら誤りにする

- `[paragraph-styles.caption]` と `[paragraph-styles.sidenote]`（ファイルの `@style-def` を含む）に、組版が使わないキーを書いたら、G03006 のエラーとする。対象は `indent`、`first-line-indent` と、実装のときにコードで確かめて組版が使っていないと分かったキー（`space-between`、`line-breaks` など）である。罫線（`rule-before`、`rule-after`）は今もエラーであり、変えない。
- メッセージは、[ADR 0017](0017-pdf-code-blocks.md) がコードの段落スタイルの使えないキーに出す G03006 の形にそろえる（キーの名前と段落スタイルの名前を示す）。
- 使わないキーの一覧は、仕様書の段落スタイルの節と、docs/diagnostics.md の G03006 の節に書く。

### G07025 の検査

- G07025 は、段落に字下げを掛ける段落スタイルだけを検査する。`caption`、`sidenote`、`code`（コードは G07043 が検査する）を除く。
- 一つの段落スタイルの字下げが大きすぎるとき、そのスタイルを `based-on` で引き継ぐほかのスタイルにも出るのは今のとおりとする。それぞれの段落に実際に字下げが掛かり、直す箇所が段落スタイルごとに違いうるからである。

### ドキュメント

- 仕様書の段落スタイルの節に、`caption` と `sidenote` が `body` から引き継ぐキーと、書けないキーを書く。
- docs/diagnostics.md の G07025 と G03006 の節を直す。
- 使い手のマニュアルの段落スタイルの説明（第 5 章、付録 C）に、キャプションと傍注に字下げを書けないことを足す。
- [ADR 0010](0010-caption-style.md)、[ADR 0011](0011-sidenote-font.md)、[ADR 0017](0017-pdf-code-blocks.md) のステータスの行に、「、キャプションと傍注が引き継ぐキーは [ADR 0043](0043-caption-sidenote-do-not-inherit-indent.md)」を足す。

## 実装しないこと

- キャプションと傍注に字下げを掛けられるようにすること。必要になれば、別の ADR で決める。
- `based-on` の規則そのものを変えること。
- G07025 を、引き継いだスタイルに出さないようにまとめること（「G07025 の検査」の二つめの項目）。

## テスト設計

テストを先に書き、今の実装で失敗することを確かめる。

- golem-driver：`body` に `indent = "5zw"` を書いた 12 字の版面で、G07025 が `body` にだけ出て、`caption` と `sidenote` には出ないこと。今は三つ出るので失敗する。
- golem-project：`[paragraph-styles.caption]` に `indent = "1zw"` を書くと G03006 になること。`sidenote` の `first-line-indent` も同じであること。今は誤りにならないので失敗する。
- golem-project：`caption` に `font` と `size` を書くのは今のとおり誤りにならないこと。
- golem-driver：`body` に字下げがあっても、キャプションと傍注の行の位置が変わらないこと（今の振る舞いを固定する）。
- golem-driver の diagnostics.md とソースの一致の検査が通ること。

## トレードオフ

- 今 `[paragraph-styles.caption]` に `indent` などを書いている原稿は、エラーになる。今もその値は組版に適用されていないので、出力は変わらない。利用者はメンテナーだけであり、黙って無視するより、書けないことを知らせるほうがよい。

## 参考文献

- [ADR 0010](0010-caption-style.md)
- [ADR 0011](0011-sidenote-font.md)
- [ADR 0017](0017-pdf-code-blocks.md)
