# ADR と仕様の矛盾のレビュー（Fable 5.1、2026-10-20）

Fable 5.1 による読み取りだけのレビュー二本（横断的な ADR、モジュールの ADR）の結果を、直し方の種類で分けてまとめた。
対象は origin/main（1ff7d3e6 から 45d228a3）であり、#282（[ADR 0047](../adr/0047-blank-line-limit.md) の実装）はまだ入っていない。
各項目の引用は、レビュアーが本文とコードで確かめたもの。
「コード」は、実装がどちらの側に従っているかを示す。
何も直していない。採るかどうかは tett23 が決める。

## A. 新しい ADR が要るもの（振る舞いの決定）

1. **プレーンテキストで、強制改行の後の行の字下げ**：docs/adr/0016 は `join` の段落の強制改行の後の行に一行目の字下げを掛けないと決め、テキストは「今のまま（最初の行だけ）」と書いた。テキストの実装（`Golem.Text` 117–120 行）は改行で分けた各行に字下げを付け、仕様書（1281 行）もそれに合わせて「各行」と書く。PDF と HTML は [ADR 0016](../adr/0016-hard-line-breaks.md) のとおり。テキストを [ADR 0016](../adr/0016-hard-line-breaks.md) にそろえるか、今の振る舞いを決め直すか。
2. **`golem` の `-N`（すべてのプロセッサで動かす）**：docs/adr/0029（225 行）は「`-N` を有効にするときは、環境の変化の検査に capability の数の変化を足す ADR を書く」とした。仕様書（2715 行）は `-N` で動くと書き、実行ファイルも `-with-rtsopts=-N` でリンクしているが、その ADR がない。
3. **PDF の図版の `Contents` をつないだ大きさの上限**：docs/adr/0040（63 行）は「別の上限は設けない」とし、テストも 8 MiB のストリームを 40 回名指しした `Contents` が読めることを求める。コード（`Golem.Pdf.Import` 1060–1070 行）と golem-pdf の仕様書は、つないだ内容に 256 MiB の上限を設ける。
4. **ABI のバージョンを上げる規則**：docs/adr/0030 は「ABI の版を一つ上げる（今は 6）」としたが、仕様書は「同じリリースで先に上げた 7 のまま」とする。「未リリースの ABI は上げない」は [golem-doc ADR 0006](../golem-doc/adr/0006-integer-range-in-ir.md) と [0007](../golem-doc/adr/0007-plugin-channel-lists.md)、docs/adr/0046 に個別に書かれているだけで、0030 を改める ADR がない。
5. **プロポーショナルメトリクスを約物に当てない規則**：仕様書（1089 行）とコード（`Pdf.hs` 541 行）にあるが、docs/adr/0020 は和文の全体に `palt`／`vpal` を足すとだけ書く。
6. **回した図版の改段と白ページ**：仕様書（1816–1817 行）の「回した図版が待っているあいだの改段は改ページとして扱う」「回した図版のページの直後の改ページで白ページを足さない」は、[golem-driver ADR 0034](../golem-driver/adr/0034-fit-figures-to-column.md) にも、docs/adr/0017 と 0018 にもない。いずれも tett23 が「その挙動でよい」とし、仕様書に書いたもの。記録として ADR に残すか。
7. **`golem check` が G0702 を出す条件**：[golem-pdf ADR 0004](../golem-pdf/adr/0004-crop-marks-and-bleed.md)（167 行）は「マニフェストのターゲットに PDF があれば」とし、[golem-project ADR 0004](../golem-project/adr/0004-font-file-check-per-target.md)（125 行）は「`golem check` は常に四つのターゲットを検査する」とする。仕様書（2734 行）は前者を写すが、コードは後者（マニフェストに PDF がなくても G0702 を出す）。仕様書を直すだけで済むが、二つの採択 ADR が衝突している。
8. **`keep-in-column = false` の罫線を版面の外に出す範囲**：[golem-driver ADR 0027](../golem-driver/adr/0027-paragraph-style-rules.md)（147 行）は段組みの段間に入る場合を書くが、仕様書（1477 行）とコード（`Paginate.hs` 683 行）は版面の上端に接する段の始まりに限る。
9. **G0750 の検査に使う列の幅**：[golem-driver ADR 0021](../golem-driver/adr/0021-hidden-folios.md) は「字の送りの半分」、仕様書、diagnostics.md、コードは「`size` の半分」。
10. **SVG の `marker` の循環の判定**：docs/adr/0041 は描いている id の列で判定するとし、golem-svg の仕様書とコードは参照のグラフで判定する（G0811 の件数が変わる）。
11. **コードブロックのキャプションの区切り**：[golem-html ADR 0002](../golem-html/adr/0002-heading-number-spacing.md) は番号と題の区切りを本の言語で一つに決めるとし、[golem-driver ADR 0023](../golem-driver/adr/0023-code-block-book-features.md) と仕様書とコードはリスト番号の後を全角の空白に固定する。英語の本では、図は半角、リストは全角になる。
12. **G0904 をまとめる単位**：[golem-cli ADR 0006](../golem-cli/adr/0006-preflight.md) は「段落スタイルか文字スタイルと色の組」、diagnostics.md とコードは「文字の役割と大きさと色の組」。
13. **CFF の `FontFile3` の `Subtype`**：[golem-pdf ADR 0006](../golem-pdf/adr/0006-cid-system-info.md) は `/OpenType`、コード（`Writer.hs` 586 行）は `CIDFontType0C`（PDFium のため）。決めた ADR がない。
14. **`[sidenotes]` の `side`**：[golem-driver ADR 0011](../golem-driver/adr/0011-sidenote-font.md) は `width`、`gap`、`marker` だけを残すとし、[golem-project ADR 0002](../golem-project/adr/0002-style-toml.md) と仕様書の例は `side` を持つ。コードは `side = "outside"` を受け付けて読み捨てる。残すなら仕様書に書き、なくすなら ADR が要る。
15. **小さな ADR で記録すれば足りるもの**：`@no-page-break` で送る行（docs/adr/0030 は「2 行の段落では全体」、仕様書とコードは「3 行以下の段落では全体」）。`@printings` の引数の誤りのコード（docs/adr/0033 はほかのブロックコマンドと同じ誤り、仕様書とコードは G0276）。G0814 の文言（docs/adr/0039 は「動く中身」、実装は「動的なコンテンツ」）。

## B. 文書を直すだけで足りるもの（ADR は要らない）

- **notice のコードの一覧**：コードの `noticeCodes` は 16 個。diagnostics.md（68 行）の表は 9 個、仕様書（1935 行）の列挙は 12 個で、どちらも足りない。
- **章末注の印の後の空き**：仕様書（2335 行）は「半角の空白」、ページの下の注（2307 行）とコードは四分アキ。
- **G0405 と G0406**：番号と題を持つ要素に、キャプションのあるコードブロックがない（diagnostics.md、markup.md）。
- **行分割のはみ出し**：[golem-layout ADR 0001](../golem-layout/adr/0001-knuth-plass-line-breaking.md) の「警告 G07xx」は存在せず、プリフライトの G0913 になっている。仕様書の行分割の節に一文を足す。
- **G0111 の条件**：markup.md に、タブと奇数の字下げの規則がない。
- **diagnostics.md**：G0261 の関数の一覧に `join` がない。G0233 の条件の変化を書いていない。G0810 の理由の書き方。G0275 の原因に SVG がない。G0908 の色空間に `icc` と `lab` がない。G0729 の位置。使っていない番号の一覧に、廃止の G0905 と、空きの G0748、G0749、G0812 がない。
- **仕様書**：`golem new` の雛形に `.gitignore` がない。LSP の補完にスウォッチと文字スタイルがない。索引の印のページの規則が章末注に合わない。1746 行の引用先（G0814 は docs/adr/0039）。プラグインの節に `[plugins.<名前>]` と `[[filters]]` の形がない。改ページの節に孤立行の規則がない。`[composition]` の `pretolerance` などの説明がない。
- **CONTRIBUTING.md**：必須の検査を「二つ」と書いている（README は `ci`、`adr`、`manual`、`textlint` の四つ）。
- **仕様書と用語集**：ADR のコミット後の変更を「ステータスの行を除いて」としか書かず、docs/adr/0032 が許したリンクだけの変更を書いていない。用語集の「強制改行」は `join` の段落に限ると書き足す。

## C. ステータスの行のリンクを足すもの（adr-guard が許す変更）

置き換えられた ADR のステータスの行が、置き換えた ADR を指していない。

- docs/adr：0001 → 0009、0021、0045（CI のジョブ）。0003 と 0005 → golem-parser 0012（`keep` の行末のエスケープした空白）。0004 → 0044（リリースノートのジョブ）。0006 → 0016（字下げ）。0017 → golem-syntax 0002（G0408）。0019 は傍注のアキ量のセットの二重の記述。0029 → `-N` の ADR（A の 2）。0030 → ABI の規則（A の 4）。0035 → golem-pdf 0008（読めない図版）。
- golem-driver：0004 → 0012。0005 → 0010。0006 → 0011。0018 → 0025、golem-layout 0018。0025、0026 → golem-layout 0018。0003、0009、0014、0022 → golem-html 0002（柱の番号の区切り）。
- golem-layout 0001 → golem-cli 0006（G0913）。golem-layout 0003、golem-text 0001、golem-html 0001 → golem-driver 0026（章末注の置き場所）。
- golem-eval 0001 → 0005、0006。golem-eval 0002 → 0004、golem-doc 0007、golem-syntax 0002、golem-driver 0018、0019。golem-eval 0003 → golem-driver 0019（圏点）、golem-fmt 0002（`@verse`）。
- golem-doc 0001 → docs/adr/0005。golem-doc 0002 → 0003、0008、golem-driver 0018。golem-doc 0003 → golem-driver 0023。
- golem-parser 0003 → 0009（G0111）。golem-syntax 0001 → golem-cli 0006。
- golem-pdf 0004 → golem-project 0004。golem-pdf 0006 → CFF の ADR（A の 13）。golem-pdf 0008 → docs/adr/0040。golem-pdf 0009 → docs/adr/0041。
- golem-project 0001 → 0006。0002 → 0003。0006 → 0005。
- golem-cli 0001 → 0003、0005。0005 → golem-syntax 0002、golem-cli 0006。
- golem-lint 0001 → docs/adr/0016。golem-plugin 0001 → golem-doc 0007。
- golem-html 0003 は本文の「[golem-doc ADR 0008](../golem-doc/adr/0008-multiple-index-and-bibliography.md)」が docs/adr/0008 にリンクしている（41 行だけ正しい）。本文は直せないので、ステータスの行で注記する。

## D. 確かめられなかったこと

- README とマニュアルが ADR に求める記載（zlib、HarfBuzz、wasmtime の版、入稿の手順）。
- G0732 の条件（段落単位の縦組みがあるか）。[golem-lsp ADR 0003](../golem-lsp/adr/0003-position-handling.md) が求める verification の記録の有無。golem-fmt `--check` の終了コード（仕様は「非ゼロ」、ADR は「1」）。
- 同じコミットで入った ADR どうし（golem-layout 0018 と golem-driver 0026 など）のどちらが後の決定か。コードがどちらに従うかで記した。
