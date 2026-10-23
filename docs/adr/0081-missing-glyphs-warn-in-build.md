# ADR 0081: フォントにない字を、golem build の dev では warning、prod ではエラーにする

ステータス: 採択

## 文脈

`golem build` は、フォントにグリフのない字を、グリフ番号 0（.notdef）で PDF に書く。
ビルドは diagnostic を出さず、終了コードは 0 である。
フォントにない字を報告するのは `golem preflight` の G09002 だけであり（[golem-cli ADR 0006](../golem-cli/adr/0006-preflight.md)）、`golem preflight` を走らせない限り、書き手は PDF を開くまで気付けない。
[docs/roadmap.md](../roadmap.md) の v0.1.0-rc4 の「書体にない字」も、この振る舞いを課題に挙げている。

メンテナーは、豆腐（.notdef の箱）は許容できないので、ビルドで報告すると決めた。
重大度は、dev のプロファイルでは warning、prod のプロファイルではエラーとする。
書きかけの原稿を組むときは、フォントにない字をそのたびに直さずに組んだ結果を見たい。
フォントにない字が問題になるのは印刷所に入稿するときなので、入稿のために組む prod だけをエラーにする。

### 確かめたこと

golem-driver の sample の fixture を、[scripts/determinism.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/determinism.sh) と同じ設定（[scripts/determinism/pdf-style.toml](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/determinism/pdf-style.toml) の版面、和文に golem-font のテストの Source Han Sans のサブセット、欧文に Source Sans Pro）で組んだ（`~/.local/bin/golem`、2026-10-23 のビルド）。

- `golem build --target pdf --format json` は、notice の G08008（コードの書体の役割がない）だけを出し、終了コード 0 で PDF を書いた。
- PDF の内容のストリームを展開すると、グリフ番号 0 が 103 回現れた。
- 同じプロジェクトの `golem preflight` は、G09002 を七つ出した。字は U+2026「…」、U+4E00「一」、U+4E09「三」、U+4E8C「二」、U+4FA1「価」、U+91CD「重」、U+9014「途」で、四つは目次（[front.gm の `@toc` の行](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/fixtures/sample/front.gm#L5)）、三つは本文の段落の位置である。`count` の和は 103 だった。
- 和文のフォントを Noto Serif JP（蟹工船の fixture のフォント）に替えると、`golem preflight` は G09002 を出さなかった。

CI のほかの入力も、`golem preflight` で確かめた。
[scripts/env-determinism/check.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/env-determinism/check.sh) の大きな入力のうち、四冊が G09002 を出す。

| 入力 | フォント | フォントにない字 |
|---|---|---|
| tempest | Source Serif（可変） | U+30FB「・」 |
| merry-wives | Source Serif（可変） | U+30FB「・」 |
| koya-hijiri | Noto Serif JP | U+6F75「潵」 |
| haru-to-shura | Noto Serif JP | U+2985「⦅」、U+2986「⦆」 |

tempest と merry-wives の「・」は原稿にない。
`[lists]` を書かない本の箇条書きの記号は、本の言語によらず「・」である（golem-project の `defaultListStyle`）。
欧文のフォントだけで組む英語の本の箇条書きは、記号が豆腐になる。
草稿の [golem-driver ADR 0044](../golem-driver/adr/0044-default-bullet-u2022.md) は、PDF の既定の印を U+2022「•」に替える。
Source Serif は U+2022 を持つので、0044 の後は二冊の「・」の報告は消える。

kanikosen と、ほかの七冊のパブリックドメインの本（frogs、snark、elements-of-style、nightmare-abbey、ichiaku-no-suna、taira-no-masakado、ushiyama-hotel）は G09002 を出さなかった。
二冊のマニュアルは、フォントを手元に取得していないので確かめていない。

### ビルドとプリフライトの関係

`golem preflight` は、[`buildCore`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/src/Golem/Driver.hs#L667) を `optProfile = Prod`、ターゲットを PDF だけにして呼び、PDF をメモリーの上に作る（[golem-driver の `preflight`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/src/Golem/Driver.hs#L791-L816)）。
出すのは、ビルドの diagnostics（`brDiagnostics`）とプリフライトの検査の diagnostics を合わせて `sortDiagnostics` で並べたものである。
ビルドの diagnostics は、プロファイルで重大度を決め直した（`adjustForProfile`）後のものであり、プリフライトはそれを隠しも書き換えもしない。
仕様書の「プリフライト」の節も、構文から出力までの段階の誤りを `golem build` と同じコードで出すと定める。

プリフライトの検査は、PDF を作れたときにだけ走る。
ビルドの diagnostics にエラーがあっても、PDF を組み終えていれば検査は走る。
PDF を書く処理（golem-driver の `writeTargetsChecked` の PDF の枝）は、メモリーの上に作るときはファイルを書かずに PDF と写し（`View`）を返す。

写しは遅延して作られ、`golem build` はこれを評価しない（[`renderPdfView` の注釈](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/src/Golem/Driver/Pdf.hs#L911-L914)）。
仕様書の「プリフライト」の節も、写しは `golem preflight` のときだけ作ると書く。

## 実装すること

### 新しいコード G08100

- PDF をターゲットに含む `golem build` で、シェイピングの結果のグリフ番号が 0（.notdef）になった字を G08100 で報告する。
- 段階は出力（08）とする。新しいコードなので、番号は 100 から取る（[ADR 0061](0061-five-digit-diagnostic-codes.md)）。
- 対象は今の G09002 と同じく、原稿の文字、番号の文字列、柱、ノンブル、目次と索引の文字列、ルビ、圏点のすべてである。PDF の写し（`View`）の字の一覧から求める。
- 符号位置とフォントのファイルの組ごとに一つにまとめる。
- 位置は、今の G09002 と同じく、その字を含む行のブロックの位置とする（`GlyphView` の `gvLineSpan`）。
- メッセージは、今の G09002 と同じ文言にする。

  ```
  フォントにグリフのない文字です: U+<16 進数>「<文字>」（<フォントのパス>、PDF の <ページ> ページ目）
  ```

  結合文字と制御文字は「」の字を省く。ページは 10 ページまで並べ、残りを「ほか <n> ページ」とする（今の `pagesPhrase`）。
- JSON の `facts` に、今の G09002 と同じ `code-point`、`font`、`pdf-pages`、`count` を書く。
- 並びは、ほかの diagnostics と同じ `sortDiagnostics` に従う。並列で組んでも（`optParallel`）同じ並びになる。

### 重大度と出力

- G08100 を golem-syntax の `profileDependentCodes` に加える。重大度は dev では warning、prod ではエラーになる。プロファイルで重大度を決め直すのは、今の `adjustForProfile` だけである。
- dev では、終了コードを変えず、PDF を書く。
- prod では、エラーなので終了コードは 1 になり、PDF を書かない。ほかのターゲットは書く。エラーのターゲットを書かないのは、G08010（PDF に置けない図版）や prod の G03010（HTML と EPUB のフォントの欠け）と同じ規則である。G08100 は PDF を組んだ後でなければわからないので、PDF の枝は、写しの字の一覧から G08100 を求めてから、ファイルを書くかを決める。
- warning は notice ではないので、`silence-notices` と `--no-notices` では抑制できない。

### 報告しないターゲットとコマンド

- HTML、EPUB、プレーンテキストのターゲットでは報告しない。HTML と EPUB はフォントのファイルをそのまま同梱して `@font-face` で指し（golem-html の `fontOut`）、Golem はシェイピングもグリフの選択もしない。字を描くのは読書環境であり、フォントにない字は読書環境が別のフォントで描く。プレーンテキストはフォントを使わない。
- `golem check` と LSP では報告しない。`golem check` は組版をしない（golem-driver の `optCheckOnly`）ので、グリフの一覧がない。今の G09002 と同じである。

### プリフライトの振る舞い

プリフライトは変えない。
G09002 とプリフライトの設定の `glyph-missing` は今のまま残し、プリフライトはビルドの G08100 を隠しも書き換えもしない。

`golem preflight` はビルドを prod で走らせるので、フォントにない字があれば、この ADR の後は次のように出す。

- ビルドの G08100 を、エラーで出す。`glyph-missing` の値によらない。
- 同じ字を、プリフライトの検査の G09002 でも出す。重大度は今と同じく `glyph-missing` の `severity` で決まる。組み込みの `print` と `basic` では、エラーである。
- G08100 は PDF を組んだ後に出るので、PDF は作られ、プリフライトの検査（G09002 から G09018）は今と同じく走る。要約の行も出し、その件数には G08100 も入る。
- 二つは同じ位置（行のブロックの位置）に、同じメッセージと同じ `facts` で並ぶ。
- 終了コードは、G08100 がエラーなので 1 になる。`glyph-missing` を `warning` か `off` にしても、フォントにない字があれば 1 で終わる。

例えば、私用領域の字 U+E000 を一字持つ本を組み込みの `print` で検査すると、人が読む形式では次の二つの diagnostic が並び、要約はエラー 2 と数える。

```
<ファイル>:<行>:<列>: error[G08100]: フォントにグリフのない文字です: U+E000「<字>」（<フォントのパス>、PDF の 1 ページ目）
<ファイル>:<行>:<列>: error[G09002]: フォントにグリフのない文字です: U+E000「<字>」（<フォントのパス>、PDF の 1 ページ目）
```

二つの並びの順は、`sortDiagnostics` の規則で決まる。

golem-preflight の `check` の G09002 の検査は残す。
符号位置とフォントでまとめる処理とメッセージの組み立ては、golem-preflight から関数として公開し、`check` の G09002 と golem-driver の G08100 の両方がこれを使う。
golem-driver はすでに golem-preflight に依存しているので、モジュールのあいだの依存は変えない。

### 写しの評価

`golem build` は、PDF をターゲットに含むとき、写しの字の一覧を評価する。
写しのうち、図版、フォントの形式、色など、G08100 に要らない部分は今と同じく評価しない。

### CI の入力のフォント

- [scripts/determinism.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/determinism.sh) の PDF の入力の和文のフォントを、Source Han Sans のサブセットから、蟹工船の fixture の Noto Serif JP（[modules/golem-driver/test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf)）に替える。sample の fixture のすべての字を持つことを、上の「確かめたこと」で確かめた。
- [scripts/env-determinism/check.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/env-determinism/check.sh) の入力 `sample-pdf` も、同じく Noto Serif JP に替える。
- CI の入力のビルドは、どれも `--profile` を付けない dev で走る（[scripts/determinism.sh の PDF のビルド](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/determinism.sh#L27)、[scripts/env-determinism/check.sh のビルド](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/env-determinism/check.sh#L210)）。フォントにない字が残る入力も、warning を出して PDF を書く。
- 草稿の [ADR 0071](0071-determinism-check-compares-diagnostics.md) は、[scripts/determinism.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/determinism.sh) で各ビルドの標準エラー出力の SHA-256 も比べる。フォントを替えれば、この入力の PDF のビルドが出すのは notice の G08008 だけになる。二つの ADR はどちらを先に実装してもよい。この ADR を後にすると、一覧の中身は変わるが、二つのランナーの一覧は一致する。
- koya-hijiri と haru-to-shura は、この ADR の実装の後も G08100 の warning を出す。tempest と merry-wives も、[golem-driver ADR 0044](../golem-driver/adr/0044-default-bullet-u2022.md) より先にこの ADR を実装すれば出す。[scripts/env-determinism/check.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/env-determinism/check.sh) は、変えた環境と基準の環境の標準エラー出力を比べるので、どちらにも同じ warning が出て、検査は通る。

### ドキュメント

- docs/diagnostics.md に G08100 の節を足す。重大度は「dev では警告、prod ではエラー」とする。主な原因と直し方は、今の G09002 の節と同じものを書き、`golem preflight` では G09002 とともに出ることを書く。
- docs/diagnostics.md の「番号の区分」の節の、プロファイルで重大度が変わるコードの一覧（「今は G03010 と G05004 の二つである」）に G08100 を加える。
- docs/diagnostics.md の G09002 の節の直し方に、同じ字を `golem build` が G08100 で報告すること、`glyph-missing` を `off` にしても `golem preflight` は G08100 のエラーで終了コード 1 になることを書く。
- 仕様書（docs/specifications.md）の「フォント」の節に、フォントにない字を G08100 で報告すること、その重大度と prod で PDF を書かないこと、報告しないターゲットとコマンドを書き、この ADR へのリンクを付ける。
- 仕様書の「構文木と diagnostics」の節の「今はプリフライトの diagnostics だけが、ページ番号（`pdf-pages`）や測った値（`ppi` など）を持つ」を、G08100 も事実を持つことに合わせて書き改める。
- 仕様書の「golem preflight」の節に、ビルドの G08100 が G09002 とともに出ること、`glyph-missing` は G08100 に当たらないことを書く。写しは `golem preflight` のときだけ作るという文を、`golem build` も字の一覧だけは評価することに合わせて書き改める。
- [docs/roadmap.md](../roadmap.md) の v0.1.0-rc4 の「書体にない字」の項目を消す。v2 の「フォントのフォールバック」の項目の、G09002 と「書体にない字」に触れる文を、G08100 と G09002 とこの ADR に合わせて書き改める。
- 利用者のマニュアルの付録 E（`manual/appendices/e-errors.gm`）に G08100 を足し、プロファイルで重大度が変わるコードの文（18 行め）に G08100 を加える。付録 D（`manual/appendices/d-preflight.gm`）の `glyph-missing` の行に、ビルドの G08100 も出ることを添える。
- 利用者のマニュアルの付録 I（`manual/appendices/i-known-issues.gm`）の「フォントにない字を `golem build` が知らせない」の項目を消す。
- 開発者のマニュアルの `manual-dev/part1/02-diagnostics.gm` の、`facts` を持つのはプリフライトの diagnostic だけという記述（88 行め）と、プロファイルで重大度が変わるコードの記述（142 行め）を、G08100 を含めて書き改める。`manual-dev/part1/01-cli.gm` の同じ記述（145 行め）にも G08100 を加える。
- 次のコミット済みの ADR のステータスの行に、この ADR へのリンクを書き足す。
  - [golem-cli ADR 0006](../golem-cli/adr/0006-preflight.md)：末尾に「、ビルドの G08100 は [docs/adr/0081](../../adr/0081-missing-glyphs-warn-in-build.md)」。
  - [golem-driver ADR 0036](../golem-driver/adr/0036-combining-characters.md)：「採択→グリフのない結合文字の報告は [docs/adr/0081](../../adr/0081-missing-glyphs-warn-in-build.md)」。

## 実装しないこと

- dev でもエラーにすること。書きかけの原稿は、フォントにない字が残っていても組めるようにする。
- G09002 を廃止すること、プリフライトの設定の `glyph-missing` を G08100 に当てること、プリフライトがビルドの G08100 を隠すこと。プリフライトの振る舞いは変えない。
- ほかのフォントで補うこと。v2 の「フォントのフォールバック」で扱う。
- koya-hijiri と haru-to-shura の原稿の字を替えること、フォントを替えること。パブリックドメインの本の本文は原典のまま組む fixture であり、Noto Serif JP にない字を持つ入力として残す。
- HTML、EPUB、プレーンテキストのターゲットで、フォントにない字を調べること。

## テスト設計

実装の前に次のテストを書き、今の実装で失敗することを確かめる。

- golem-driver の [test/PdfSpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/PdfSpec.hs)：sample の fixture を、和文に Source Han Sans のサブセット、欧文に Source Sans Pro、版面に [scripts/determinism/pdf-style.toml](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/determinism/pdf-style.toml) で、`optProfile = Dev` で組むと、warning の G08100 がちょうど七つ出て、字が U+2026、U+4E00、U+4E09、U+4E8C、U+4FA1、U+91CD、U+9014 であり、`count` の和が 103 であること。四つの位置が [front.gm の 5 行め](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/fixtures/sample/front.gm#L5)、ほかの三つが [chapters/01.gm の 6 行め](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/fixtures/sample/chapters/01.gm#L6) と [10 行め](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/fixtures/sample/chapters/01.gm#L10)、[chapters/02.gm の 6 行め](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/fixtures/sample/chapters/02.gm#L6) であること。PDF を書き、エラーがないこと。今はどれも出ないので失敗する。[golem-driver ADR 0044](../golem-driver/adr/0044-default-bullet-u2022.md) を先に実装していれば、このサブセットは U+2022 を持たないので、箇条書きの印の U+2022 の G08100 が加わる。そのときは八つとし、U+2022 を字の一覧に加える。
- 同じプロジェクトを `optProfile = Prod` で組むと、同じ G08100 がエラーで出て、`build/pdf` に PDF を書かないこと。HTML を同時に組めば、HTML は書くこと。今は G08100 が出ず、PDF を書くので失敗する。
- 同じプロジェクトを `optParallel` を真と偽の二通りで組むと、diagnostics の一覧が同じであること。
- 同じプロジェクトを HTML、EPUB、プレーンテキストのターゲットで組むと、G08100 が出ないこと（今の実装でも通る）。
- 同じプロジェクトの和文を Noto Serif JP にすると、G08100 が出ないこと（今の実装でも通る）。
- golem-driver の [test/CliSpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/CliSpec.hs)：私用領域の字（U+E000）を足したプロジェクトの `preflight` で、G08100 のエラーと G09002 のエラーが一つずつ出て、位置とメッセージが等しいこと。プリフライトの設定の `glyph-missing` を `warning` にすると G09002 だけが warning になり、`off` にすると G09002 だけが消え、どちらでも G08100 のエラーは残ること。今は G08100 が出ないので失敗する。
- golem-cli の [test/Main.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-cli/test/Main.hs)：`golem build --target pdf --format json` で、私用領域の字を持つプロジェクトが終了コード 0 で終わり、標準エラー出力の JSON に `"code":"G08100"` と `"severity":"warning"` と `facts` の四つのキーがあること。`--profile prod` では終了コード 1、`"severity":"error"` で、`build/pdf` がないこと。`golem preflight` の「G09002: 1」の項目に、`error[G08100]` もあることを加える。今は失敗する。
- golem-syntax の [test/Main.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-syntax/test/Main.hs)：`profileDependentCodes` の段階が `["05", "03", "08"]` であること（[今の断言](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-syntax/test/Main.hs#L184) を書き換える）。`adjustForProfile` が G08100 を dev で warning、prod でエラーにすること。`preflightCodes` が今と同じ G09002 から G09018（G09005 を除く）であること。
- golem-driver の [test/DiagnosticsSpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/DiagnosticsSpec.hs)：今の [プロファイルで重大度が変わるコードの検査](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/DiagnosticsSpec.hs#L234-L238) が、docs/diagnostics.md の G08100 の「- 重大度: dev では警告、prod ではエラー」と合うことを確かめる。G08100 の節を書くまでは、この検査が落ちる。
- 自動のテストにしないもの：実装のプルリクエストの CI で、[scripts/determinism.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/determinism.sh) の PDF のビルドが G08100 を出さないことと、二冊のマニュアルのビルドが通ること（[scripts/manual/build.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/manual/build.sh) は diagnostic を一つでも出せば失敗にする）を確かめる。マニュアルに G08100 が出たら、同じプルリクエストでフォントか原稿を直す。

## トレードオフ

`golem preflight` は、同じ字を G08100 と G09002 の二つのコードで報告する。
同じ位置に同じメッセージが二行並び、要約のエラーの数も二つ増える。
仕様書の設計原則「一つのコードに一つの原因」は、異なる原因を一つのコードにまとめることを禁じるが、一つの原因に二つのコードを持たせることを文言の上では禁じていない。
それでも、書き手は `golem explain` で二つの節を引くことになる。
プリフライトを変えないことを、この重複をなくすことより優先した。

`glyph-missing` の `off` と `warning` は、`golem preflight` の終了コードを 0 にする手段ではなくなる。
フォントにない字を残したまま入稿の検査を通す手段は、prod のビルドと同じくない。
書き手は、字を持つフォントを `style.toml` に書くか、原稿の字を替える必要がある。
入稿の時点で豆腐を許さないので、これを受け入れる。
字が欠けていても preflight をほかの検査まで完走させ、結果をまとめて見られるようにすることは、v1.0.0 の課題とする（docs/roadmap.md）。

dev の warning は終了コードを変えないので、CI で dev の `golem build` の終了コードだけを見る書き手は、豆腐に気付かないまま進める。
入稿のために prod で組めば、そこで止まる。

prod では PDF を書かないので、フォントにない字が一字あるだけで、入稿用の PDF を作れない。
仕様書の「golem preflight」の節は、検査した PDF の SHA-256 が `golem build --target pdf --profile prod` の PDF と一致すると書く。
G08100 が出る本では、prod のビルドが PDF を書かないので、比べる PDF がない。

ビルドのたびに、PDF の写しの字の一覧を評価し、符号位置とフォントでまとめる処理が加わる。
今の `golem build` は写しを評価しないので、PDF の組版の時間はその分だけ延びる。
フォントにない字を黙って出力しないための費用として、これを受け入れる。

## 参考文献

- [golem-cli ADR 0006](../golem-cli/adr/0006-preflight.md)
- [ADR 0061](0061-five-digit-diagnostic-codes.md)
- [ADR 0071](0071-determinism-check-compares-diagnostics.md)（草稿）
- [golem-driver ADR 0036](../golem-driver/adr/0036-combining-characters.md)
- [golem-driver ADR 0044](../golem-driver/adr/0044-default-bullet-u2022.md)（草稿）
