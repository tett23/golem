# ADR 0053: `palt` と `vpal` を、JLReq が空きを決める約物に当てない

ステータス: 採択

## 文脈

[ADR 0020](0020-indesign-character-features.md) は、文字スタイルと段落スタイルのキー `proportional-metrics` を定めた。
真なら、和文に OpenType の `palt`（縦組みでは `vpal`）を当てる。
「シェイピング」の節は、和文に足す機能を次のように書く。

> `metrics` なら、`proportional-metrics` が真のとき横組みで `["palt"]`、縦組みで `["vpal"]`、偽のとき `[]`。

和文のどの字に当てるかは限っていない。

実装（コミット 69dcedd9）は、約物の一部を除く。
`Golem.Driver.Pdf.shapingOf`（`modules/golem-driver/src/Golem/Driver/Pdf.hs` の 530 行から 547 行）は、字の分類の前後の空き（`Golem.Layout.Japanese.punctSpace`）が `(0, 0)` の字にだけ `palt` と `vpal` を足す。
`punctSpace` が空きを持つのは、始め括弧類、終わり括弧類、句点類、読点類、中点類の五つである。
仕様書（[docs/specifications.md](../specifications.md) の 1100 行）は、これを次のように書く。

> プロポーショナルメトリクスは、JLReq の規則で前後の空きを決める約物（括弧類、句読点、中点類）には適用しない。

利用者のマニュアル（`manual/chapters/05-style.gm` の 279 行）も、括弧類と句読点を全角のまま組むと書く。
一方、仕様書の「フォント」の節の 1703 行は、[ADR 0020](0020-indesign-character-features.md) のとおり、`proportional-metrics` が真なら `palt` か `vpal` を足すとだけ書く。

一方、フォントの役割の `features` に書いた `palt` と `vpal` は、約物にも当たる。
`shapingOf` は、役割の `features` の後ろに機能を足すだけで、役割の `palt` を約物から外さない。
golem-driver の `test/PdfSpec.hs` の「PDF: a glyph is drawn at its box moved by its offset; other glyphs stay」は、役割の `palt` で始め括弧が動くことを前提にしている。
同じ「字面に合わせた送り」を、文字スタイルで指定すると約物は全角のまま組まれ、役割で指定すると約物も縮む。

この規則を決めた ADR はない。

### 除く理由

Golem の和文の組版（[golem-layout ADR 0002](../golem-layout/adr/0002-japanese-composition.md)）は、JLReq の約物の扱いに従う。
JLReq は、括弧類、句読点、中点類の字形が全角の字幅の一部（括弧類と句読点は半分、中点類は中央の半分）を占め、残りを空きとみなして、約物が続く場合や行頭と行末の空きを決める。
Golem はこれを次のように実装している。

- `Golem.Layout.Japanese.itemsFor` は、約物の送り（フォントから測った全角）から `punctSpace` の空き（括弧類と句読点は半角、中点類は前後に四分）を引き、残りを字の箱の幅にする。
- 引いた空きは、隣の字の分類に応じて、グルーとして足し直すか、詰める（JLReq の 3.1.4 の、約物が続く場合の規則）。

`palt` は、約物の送りを字面に合わせて縮める。
始め括弧 `「` の送りは、全角から字面の幅（おおよそ半角）に縮む。
これに `itemsFor` の引き算を重ねると、送りから半角がもう一度引かれ、箱の幅が 0 に近くなる。
字は隣の字に重なり、JLReq の空きの規則も意味を失う。
したがって、`proportional-metrics` が真でも、JLReq が空きを決める約物には `palt` と `vpal` を当てず、全角の送りのまま JLReq の規則に任せる。
仮名と漢字（約物でない和文）には、今のとおり当てる。


縮める指定の経路によって、約物が隣の字に重なったり重ならなかったりするのは、書き手から見て予測できない振る舞いである。
この理由は、`palt` をどの経路で当てても変わらない。
したがって、役割の `features` の `palt` と `vpal` も、JLReq が空きを決める約物には当てない。

## 実装すること

### 規則

- 和文の字のうち、JLReq の規則で前後の空きを決める約物には、`palt` と `vpal` を当てない。`proportional-metrics` で指定した場合も、フォントの役割の `features` に書いた場合も同じである。
- 除く約物は、`Golem.Layout.Japanese.punctSpace` が空きを持つ分類（始め括弧類、終わり括弧類、句点類、読点類、中点類）の字である。分類は `Golem.Layout.CharClass.charClass` で決め、中点類には `・` のほかに `：` と `；` が入る。
- 区切り約物（`？`、`！`）、ハイフン類（`〜` など）、分離禁止文字（`—`、`…` など）、長音記号は除かない。JLReq の規則で前後の空きを決めない字だからである。
- 仮名と漢字には、今と同じく、`proportional-metrics` と役割の `features` のどちらでも当てる。
- `kerning = "japanese-equal-width"` は、今と同じく、すべての和文で `palt` と `vpal` を止める。

### PDF（golem-driver）

- `Golem.Driver.Pdf.shapingOf` は、除く約物に、カーニングの方式によらず `-palt` と `-vpal` を足す。役割の `features` の後ろに足すので、HarfBuzz の規則（後ろの機能が前の同じ機能を上書きする）により、役割の `palt` と `vpal` より優先される。
- `proportional-metrics` で足す `palt` と `vpal` は、今と同じく、除く約物には足さない。
- 除く約物の `Shaping` は、カーニングの方式ごとに次のとおりになる（横組みと縦組みで同じ）。
  - `metrics`：`["-palt", "-vpal"]`
  - `none`：`["-kern", "-vkrn", "-palt", "-vpal"]`
  - `japanese-equal-width`：今と同じ `["-kern", "-vkrn", "-palt", "-vpal"]`
- `Shaping` は字の測り方のキャッシュのキーでもあるので、約物のキーが変わる。キャッシュの正しさは変わらない。

役割の `features` に `palt` を書いた本では、約物の送りと位置が変わる。
今の fixture と二つのマニュアルの `style.toml` は、役割の `features` に `palt` を書いていないので、出力は変わらない。
仕様書の `style.toml` の例（671 行）は `features = ["palt"]` を書いている。
この例の本では、約物が全角の送りに戻る。

### HTML と EPUB

変えない。
`proportional-metrics = true` は、`cs-名前` と `ps-名前` の規則の `font-feature-settings: "palt" 1`（縦組みの本では `"vpal" 1`）になり、約物にも当たる。
CSS の `font-feature-settings` は字の種類で当て分けられないので、約物を除くには約物ごとに要素で囲む必要がある。
HTML と EPUB は、もともと JLReq の約物の空きの規則を処理系の側で組まず、閲覧する環境に任せている。
`palt` を約物から外しても、約物の空きが PDF と同じになるわけではない。
この差は受け入れる。

### ドキュメント

- [ADR 0020](0020-indesign-character-features.md) のステータスの行は、今「採択→和文のペアカーニングから除く一覧への分離禁止文字の追加は [golem-driver ADR 0020](../golem-driver/adr/0020-glyph-positioning-and-dash-kerning.md)」である。これを「採択→和文のペアカーニングから除く一覧への分離禁止文字の追加は [golem-driver ADR 0020](../golem-driver/adr/0020-glyph-positioning-and-dash-kerning.md)、`palt` と `vpal` を約物に当てないことは [ADR 0053](0053-no-palt-on-jlreq-punctuation.md)」に改める。
- 仕様書の「style.toml」の節の 1100 行の項目に、この ADR へのリンクを付け、除く分類に「始め括弧類、終わり括弧類、句点類、読点類、中点類」と JLReq の名前を書く。区切り約物を除かないこと、役割の `features` の `palt` と `vpal` も除く約物には当たらないことも書く。
- 仕様書の「フォント」の節の 1703 行の段落に、除く約物には、カーニングの方式によらず `-palt` と `-vpal` を足すことを書く。役割の `features` の説明（`features` の例の近く）にも、同じことを一文で書く。
- 仕様書の HTML の CSS の表の後に、HTML と EPUB では `palt` が約物にも当たり、PDF と違うことを一文で足す。
- 利用者のマニュアルの、括弧類と句読点を全角のまま組むという文に、中点類（`・`、`：`、`；`）も全角のまま組むこと、フォントの役割の `features` に `palt` を書いても同じであること、HTML と EPUB ではこれらにも字面に合わせた送りが当たることを足す。役割の `features` を説明する箇所にも、約物には `palt` と `vpal` が当たらないことを書く。

## 実装しないこと

- 約物に `palt` を当て、`itemsFor` で引く空きを `palt` の後の送りから計算し直すこと。約物の字面の幅はフォントごとに違い、JLReq の規則は全角の字幅を前提に空きを決めるので、規則の全体を作り直すことになる。
- 約物にも `palt` と `vpal` を当てたい本のための逃げ道。v1.0.0 か v1.x で設ける（[docs/roadmap.md](../roadmap.md) の「約物のプロポーショナルメトリクスの逃げ道」）。この ADR では、どの経路でも当てない。
- HTML と EPUB で、約物を要素で囲んで `font-feature-settings: "palt" 0` を当てること。出力が約物の数だけ膨らむ。
- 役割の `features` に約物を縮めるほかの機能（`halt`、`vhal`、`chws` など）を書いた場合を除くこと。この ADR は `palt` と `vpal` に限る。
- InDesign の振る舞いに合わせること。InDesign で、プロポーショナルメトリクスと文字組みアキ量設定がどう組み合わさるかは、確かめていない。

## テスト設計

先に書き、失敗させてから実装する。

### golem-driver（`test/PdfSpec.hs` の「each kerning method and proportional metrics turn on their OpenType features」）

今は和文を `'あ'` だけで確かめている。
次を足す。

- `shapingOf False (lk KernMetrics True) '「'` が `Shaping "body" False ["-palt", "-vpal"]` であること。今は `[]` なので失敗する。
- `shapingOf True (lk KernMetrics True) '「'` が `Shaping "body" True ["-palt", "-vpal"]` であること。
- `shapingOf False (lk KernMetrics False) '「'` も同じく `["-palt", "-vpal"]` であること（役割の `palt` を止めるため、`proportional-metrics` が偽でも足す）。
- `shapingOf False (lk KernMetrics True)` を `'」'`、`'。'`、`'、'`、`'・'`、`'：'` に当てた結果が、いずれも `["-palt", "-vpal"]` であること。
- `shapingOf False (lk KernNone True) '「'` が `Shaping "body" False ["-kern", "-vkrn", "-palt", "-vpal"]` であること。
- `shapingOf False (lk KernMetrics True) '？'` と `'…'` が `Shaping "body" False ["palt"]` であること（除かない字）。この項目は今も通る。

### golem-driver（字の送り）

- 役割 `palt`（`features = ["palt"]`）の `lfAdvance` を、`shapingOf` が返す `Shaping` で測ると、`「` が 1 字、`あ` が今と同じ値になること。fixture の Noto Serif JP を使う（`PdfSpec.hs` の「palt narrows a bracket; -palt after the role's palt undoes it」と同じフォント）。今は `「` が 1 字より小さいので失敗する。
- `palt` を持つフォントで、`proportional-metrics = true` の文字スタイルを当てた `漢「字」` を組み、`「` と `」` の箱の幅が、`proportional-metrics` を当てない場合と同じであること。この項目は今も通る。
- 同じ原稿を、役割の `features = ["palt"]` で組み、`「` と `」` の箱の幅が、`palt` のない役割で組んだ場合と同じであること。今は狭いので失敗する。

### 既存のテストの書き換え

- 「PDF: a glyph is drawn at its box moved by its offset; other glyphs stay」は、役割の `palt` で動く字を `「` から仮名（`あ` など）に変える。グリフの原点をずらしだけ動かすという、このテストが確かめる性質は変わらない。

### 出力の一致

- 既存の fixture、`scripts/determinism.sh` の出力、二つのマニュアルの PDF が、この ADR の前とバイト列で同じであること。どれも役割の `features` に `palt` を書いていないためである。

## トレードオフ

約物は、どの経路で `palt` を指定しても、全角の字幅から JLReq の規則で詰める。
約物の詰め方は、JLReq の規則が決める量（括弧類と句読点は半角まで）に限られ、フォントの字面の幅には従わない。
書き手から見て、約物の組み方は指定の経路によらず一つに決まり、隣の字に重なることがなくなる。

代わりに、役割の `features` に `palt` を書き、約物も字面に合わせて詰めていた本は、約物の送りが変わる。
このような本は、`itemsFor` の引き算と重なって約物が隣の字に重なっていたはずであり、意図どおりに組めていたとは考えにくい。
約物を字面に合わせて詰めたい本のための逃げ道は、ロードマップの項目で、JLReq の空きの規則と矛盾しない形で設ける。

役割の `features` は、OpenType の機能をそのままシェイピングに渡す指定だった（[ADR 0020](0020-indesign-character-features.md)）。
この ADR で、処理系が `palt` と `vpal` に限って中身を解釈し、約物から外す。
`features` の中身を処理系が書き換える最初の例になるので、仕様書の `features` の説明に明記する。

HTML と EPUB では約物にも `palt` が当たり、PDF と送りが違う。
HTML と EPUB の約物の空きは、もともと閲覧する環境に任せており、PDF と一致しない。
媒体のあいだの差は増えるが、新しい種類の差ではない。
## 参考文献

- W3C, Requirements for Japanese Text Layout（JLReq）, 3.1.2 Positioning of Punctuation Marks, 3.1.4 Positioning of Consecutive Opening Brackets, Closing Brackets, Commas, Full Stops and Middle Dots, Appendix A Character Classes。https://www.w3.org/TR/jlreq/
- Microsoft, OpenType Feature Registry, `palt`（Proportional Alternate Widths）と `vpal`（Proportional Alternate Vertical Metrics）。https://learn.microsoft.com/en-us/typography/opentype/spec/features_pt
- [docs/adr/0020](0020-indesign-character-features.md)
- [golem-driver ADR 0020](../golem-driver/adr/0020-glyph-positioning-and-dash-kerning.md)
- [golem-layout ADR 0002](../golem-layout/adr/0002-japanese-composition.md)
