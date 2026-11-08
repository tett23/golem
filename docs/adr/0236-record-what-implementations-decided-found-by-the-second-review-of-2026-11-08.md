# ADR 0236: 2026-11-08 の二度めの ADR のレビューで見つかった、実装が決めた点を記録する

ステータス: 採択（未実装）

## 文脈

2026-11-08 に、[ADR 0211](0211-record-what-implementations-decided-found-by-the-review-of-2026-11-08.md) から 0229 までと、[golem-layout ADR 0026](../golem-layout/adr/0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) から 0032 の実装を、ADR の文と照らし合わせた（origin/main `ed9aafba`）。
[ADR 0211](0211-record-what-implementations-decided-found-by-the-review-of-2026-11-08.md) と同じく、違反と設計の判断が要る逸脱は、それぞれ別の ADR かプルリクエストで扱う。
[golem-layout ADR 0026](../golem-layout/adr/0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) の待つ図版の定義は [golem-layout ADR 0033](../golem-layout/adr/0033-read-waiting-figures-from-the-placement.md) が扱い、文書の食い違いは [#700](https://github.com/tett23/golem/pull/700) が直す。

残ったのは、実装が ADR の書いていない点を決めたもの、ADR の文が実装の前提を取り違えていたもの、ADR のテスト設計の一部を行わなかったものである。
どれもマージ済みで、多くは仕様書かプルリクエストの説明に書かれているが、決めた ADR がない。
この ADR は、それらを決めたこととして記録する。

一つだけ、記録より重いものがある。
[ADR 0217](0217-html-spaces-of-paragraph-styles-redefined-in-files.md) の実装は、ADR が接頭辞を付けると書いた規則の一部に、接頭辞を付けなかった。
ADR の文と振る舞いが食い違い、仕様書だけが今の振る舞いを書いている。
これは「メンテナーが決めること」の 1 で、記録して認めるか、ADR のとおりに直すかを決める。

以下、元の ADR の番号の順に並べる。
各項目は、ADR の文、実装、そうした理由の順に書く。

### [ADR 0211](0211-record-what-implementations-decided-found-by-the-review-of-2026-11-08.md)：A2 と A3

不変条件 A2 は、改ページの手での制御の直前に段落スタイルの空きを置かないとする。
実装は空きを制御の直前に置かず、制御の後ろへ移す（[`AlignSpaceSpec.hs`](https://github.com/tett23/golem/blob/ed9aafba3e0ffd788f921de86b261339d8f642cd/modules/golem-driver/test/AlignSpaceSpec.hs#L68-L88)）。
`@need-lines` と `@no-page-break` の後ろへ移った空きは、次の段落を前から離す。
A2 は字義どおり成り立つが、ADR の文の「段の末尾に残るだけで何も離さない」は、強制の改ページにしか当てはまらない。

A3 のテスト設計は、2 字の行で組んで分かれる側を見るとした。
実装は、`[lang en]` と `[lang ja]` で分けられるかどうかを直接比べた（[`LangSpec.hs`](https://github.com/tett23/golem/blob/ed9aafba3e0ffd788f921de86b261339d8f642cd/modules/golem-layout/test/LangSpec.hs#L117-L126)）。
表の 6 字を覆うので、A3 の確かめ方として足りる。

### [ADR 0212](0212-patch-release-check-on-the-inputs-of-the-previous-release.md)：三つの点

ADR は「patch でないか、基準がないときは成功」と「patch なのに基準がないときは失敗」の二つを書いており、互いに合わない。
実装は後者を採った（[`check-patch.sh`](https://github.com/tett23/golem/blob/ed9aafba3e0ffd788f921de86b261339d8f642cd/scripts/release/check-patch.sh#L64-L71)）。
不変条件 P2 と `docs/compatibility.md` はこれに合う。

出力の検査は `determinism.sh --no-manuals` を呼ぶ。
コミットした `hashes.txt` はマニュアルの行を持たないので、`--no-manuals` がなければ必ず失敗する。

`SHEM` の環境変数があれば `fetch-shem.sh` を飛ばすことと、標準出力の形（patch なら基準のタグ一行、そうでなければ `check-patch:` で始まる一行）は、ADR が決めていない。

### [ADR 0213](0213-numbers-the-number-formats-cannot-write.md)：`piStyleText` と見た目の参照

ADR は G07106 の位置を `folio` の `format` の値と決めたが、その位置を得る手段を決めていない。
実装は `PdfInput` に `style.toml` の文字列（`piStyleText`）を足した（[`Fonts.hs`](https://github.com/tett23/golem/blob/ed9aafba3e0ffd788f921de86b261339d8f642cd/modules/golem-typeset/src/Golem/Typeset/Fonts.hs#L215-L216)）。

テスト設計は `scripts/visual` の PDF も変わらないことを求めたが、`scripts/visual/pages/manual.txt` は変わった。
同じ ADR が付録 C と E を書き換えさせるので、避けられない。

### [ADR 0216](0216-drawn-content-missing-from-the-structure-tree-is-an-error.md)：テストの置き場所とテスト用の関数

テスト設計は、改竄のテストを golem-typeset のテストに置くとした。
golem-typeset のテストは golem-eval と golem-syntax に依存しないので、テストは golem-driver の `TaggedPdfSpec` に置いた。
依存を足すには ADR が要る（`CLAUDE.md`）ので、依存を足さずに済む場所を選んだ。

テストのために、`renderPdfWithTree`、`renderPdfAllWith`、`pdfWithTree` を製品のモジュールから公開した（[`Driver.hs`](https://github.com/tett23/golem/blob/ed9aafba3e0ffd788f921de86b261339d8f642cd/modules/golem-driver/src/Golem/Driver.hs#L1265-L1272)）。
注釈は、G07107 のテストだけが使うと書いている。

### [ADR 0217](0217-html-spaces-of-paragraph-styles-redefined-in-files.md)：接頭辞を付けない `body` の規則と、H2 の基準

「実装すること」は、`body:not(.file-n)` の接頭辞を付ける規則に、`body` の `p` と `p:not([class])` の規則を含める。
実装は、`body` の前のアキの `p`、`p + p`、`div.blank-line + p` に接頭辞を付けない（[`Html.hs`](https://github.com/tett23/golem/blob/ed9aafba3e0ffd788f921de86b261339d8f642cd/modules/golem-html/src/Golem/Html.hs#L1165-L1180)）。
接頭辞を付けると、詳細度が上がり、ほかのページでほかのスタイルの前のアキに勝つ。
そうなると、不変条件 H1 が成り立たない。
仕様書はこの振る舞いを書いている。

逆に、ADR が名を挙げていない同じスタイルの段落のあいだの規則（`p.ps-S + p.ps-S`）には、接頭辞を付けた。

H2 の基準は、ADR の「空きのキーをすべて除いた本」でなく、「すべて 0 にした本」である（[`FileSpacesSpec.hs`](https://github.com/tett23/golem/blob/ed9aafba3e0ffd788f921de86b261339d8f642cd/modules/golem-driver/test/FileSpacesSpec.hs#L52-L60)）。
`verse` の組み込みの空きを除けないためである。
同じスタイルの A と B で `space-between` が 0 のときは、判定を省く。

### [ADR 0218](0218-page-starts-inside-code-blocks.md)：調べていない入力と見た目の参照

境界の入力の表のうち、縦組み、`@style` の本体の中のブロック、プラグインと Emet の関数が作ったコードは、`PageStartsSpec` で調べていない。

不変条件 C7 は `scripts/visual/pages/` の参照が変わらないことを求めるが、`manual-dev.txt` の 13 ページが変わった。
同じ ADR が求めた開発者のマニュアルの CDDL の改訂のためで、組版の処理は変わっていない。

### [ADR 0219](0219-frequency-of-the-wasm-job-and-its-uncached-runs.md)：比べる基準と、試していない行

ADR は「main と違う」かで判定するとした。
実装は、プルリクエストでは `pull_request.base.sha`、push では `event.before` と比べる（[`ci.yml`](https://github.com/tett23/golem/blob/ed9aafba3e0ffd788f921de86b261339d8f642cd/.github/workflows/ci.yml#L705)）。
ツールチェーンを替えたプルリクエストをマージした直後の main の実行は、プルリクエストのキャッシュを読めないので、キャッシュが消されたと注釈される可能性がある。

テスト設計の表の四行め（`fetch-ghc-wasm.sh` を変えたプルリクエスト）と五行め（キャッシュを消した後の実行）は、試していない。
一行めから三行めは、CI の実行で ADR のとおりだと確かめた（プルリクエストの実行 42436431089、push の実行 42436802218 と 42439969107）。

### [ADR 0220](0220-page-count-range-of-complex-fixtures.md)：N2 の確かめ方と `--accept`

テスト設計は、三章に 3 ページ分を足して 32 を超えさせるとした。
3 ページ分では 32 を超えないので、60 段落（49 ページ）を足して確かめた。

`--accept` を付けたとき、PDF のゴールデンは書き直されないが、EPUB のゴールデンは書き直される。
N2 は成り立つ。

### [ADR 0222](0222-line-breaking-points-the-invariants-did-not-decide.md)：L7 の上限

7 は、L7 の素朴な探索の候補の数の上限に当たる入力の数を数え直すとした。
固定した数がテストになかったので、数え直すものがなかった。
D3 の前提の誤りは [ADR 0227](0227-draw-the-glyphs-of-a-box-in-the-order-of-its-text.md) が記録した。

### [ADR 0223](0223-emet-sizes-before-building-values.md)：四つの点

リストの値は、長さを持つ（[`Prim.hs`](https://github.com/tett23/golem/blob/ed9aafba3e0ffd788f921de86b261339d8f642cd/modules/golem-emet/src/Golem/Emet/Prim.hs#L33)）。
長さを持たないと、共有されたリストの `List.concat` を S3 で数えるとき、ヒープを使い果たす。

S3 の `String.join` と `List.concat` の n = 20,000 の割り当ての上限は、ADR の 64 MiB でなく、「要素が一つのときの割り当て + 64 MiB」である。
入力の `rep` を作るだけで約 50 MB を割り当てるので、ADR の見積もりは誤っていた。

wasm32 では確かめていない（ADR が許し、プルリクエストに書いた）。

手数の上限が Int64 の最大値のとき、S5 の「上限 + 1 手」はあふれる。
ADR は「上限 + 1 が Int64 に収まる限り」と留保しているが、`filterFuel` の頭打ちの値が最大値そのものなので、S5 はこの値で成り立たない。

### [ADR 0224](0224-limit-the-cells-of-a-table-set-in-pdf.md)：割り当ての測り方と、作れない入力

T1 と T2 の割り当ての上限は、ADR の 1 GiB でなく 8 GiB で、スレッドの割り当てのカウンタで測る（[`TableFilesSpec.hs`](https://github.com/tett23/golem/blob/ed9aafba3e0ffd788f921de86b261339d8f642cd/modules/golem-driver/test/TableFilesSpec.hs#L169-L178)）。
並列のテストでは `GHC.Stats` がほかのテストの割り当ても数え、読み込みと評価だけで 1 GiB を超えるためである。

行の長さがそろわない表は、どの出所も作れない（G02085、G01015、E06104 で退ける）ので、テストしていない。
数を数える場所は `composeTable` に渡す前でなく、`composeTable` の先頭である。
振る舞いは同じである。

### [ADR 0228](0228-keep-the-ci-caches-under-the-10-gb-limit.md)：記録の時期

所要時間の記録は、実装のプルリクエスト（#691）でなく、後のプルリクエスト（#699）で書いた。
マージの後の実行が要るからである。
I5 を確かめないまま採択にしたことは、[#700](https://github.com/tett23/golem/pull/700) がロードマップの手で確かめる項目に足す。

### [golem-layout ADR 0026](../golem-layout/adr/0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) と [0027](../golem-layout/adr/0027-need-lines-judged-again-after-spaces.md)：Alloy のスコープと段の決め方

二つの ADR は、Alloy のモデルを走らせるスコープを決めていない。
`blankFigureOrder` と `needSpaceNone` は、スコープ 3 まで走らせた（スコープ 4 は 1 時間を超えて止めた。`docs/golem-layout/models/README.md`）。

[golem-layout ADR 0026](../golem-layout/adr/0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) は、残った行アキを捨てる段を「待ちの列の図版を置く段の先頭」とした。
実装は、図版がすでに改ページで置かれていた場合にも同じ段を選ぶ（[`Paginate.hs`](https://github.com/tett23/golem/blob/ed9aafba3e0ffd788f921de86b261339d8f642cd/modules/golem-layout/src/Golem/Layout/Paginate.hs#L133-L137)）。

### [golem-layout ADR 0031](../golem-layout/adr/0031-line-breaks-after-low-lines-in-identifiers.md)：連なりを数える単位と U3 の行の幅

`code` の「最初と最後の連なり」を、空白で区切った一塊ごとに数える（`a/_b` のように `/` を含む塊も一つとする）。
ADR の「1 と同じく」は、識別子ごととも読める。

U3 は、2 字の行でなく 4 em の行で確かめた。
`THIRD_` が 2 em に入らないためである。

### ステータスの行を書き換えた ADR

[golem-layout ADR 0030](../golem-layout/adr/0030-apostrophes-at-word-starts-are-not-closing-brackets.md) は [golem-layout ADR 0028](../golem-layout/adr/0028-kinsoku-across-spaces-and-explicit-hyphens.md) の、[golem-layout ADR 0031](../golem-layout/adr/0031-line-breaks-after-low-lines-in-identifiers.md) は [ADR 0222](0222-line-breaking-points-the-invariants-did-not-decide.md) と [golem-driver ADR 0017](../golem-driver/adr/0017-pdf-code-blocks.md) の、ステータスの行を書き換えた。
どの ADR もそれを求めていないが、書き換えた先の決めたことを改めているので、ステータスの行から改めた ADR を引ける。

## 実装すること

ここに記録した規則と手順は、どれも main に入っている（`ed9aafba` で確かめた）。
この ADR の実装は、次のことだけである。

- 次の ADR のステータスの行に、この ADR が記録した点を足す。すでに `→` を持つ行には `、` でつないで足す。
  - 0211（A2 の制御の後ろの空き、A3 の確かめ方）、0212（基準がないときの失敗、`--no-manuals`、`SHEM` と標準出力の形）、0213（`piStyleText`、見た目の参照）、0216（テストの置き場所、テスト用の関数）、0217（接頭辞を付けない `body` の規則、同じスタイルの段落のあいだの規則、H2 の基準）、0218（調べていない入力、見た目の参照）、0219（比べる基準、試していない行）、0220（N2 の確かめ方、`--accept`）、0222（L7 の上限）、0223（リストの長さ、割り当ての上限、wasm32、S5 の上限）、0224（割り当ての測り方、作れない入力、数える場所）、0228（記録の時期）
  - golem-layout 0026（Alloy のスコープ、行アキを捨てる段）、0027（Alloy のスコープ）、0031（連なりを数える単位、U3 の行の幅）
- 仕様書の [ADR 0217](0217-html-spaces-of-paragraph-styles-redefined-in-files.md) の接頭辞の文、`Golem.Html` の `spaceRules` の注釈、`Golem.Emet.Prim` の `PL` の注釈、`TableFilesSpec` の割り当ての注釈に、この ADR へのリンクを足す。
- 仕様書の Emet の手数の上限の文に、上限が Int64 の最大値のときは S5 が成り立たないことを足す。

## 実装しないこと

- **[ADR 0217](0217-html-spaces-of-paragraph-styles-redefined-in-files.md) の `body` の規則に接頭辞を付けること**：「メンテナーが決めること」の 1 で、推奨の案を採るなら行わない。
- **調べていない入力のテストを足すこと**（0218 の縦組みと Emet のコード、0219 の四行めと五行め、0224 のそろわない行）：0218 と 0219 の分は、それぞれの入力を変える ADR かプルリクエストで足す。0224 の分は作れないので足さない。
- **[ADR 0212](0212-patch-release-check-on-the-inputs-of-the-previous-release.md) の `patch` ジョブを動かすこと**：タグを打つのはメンテナーの作業で、記録の対象ではない。ADR のテスト設計の残りとして、メンテナーが行う。
- **[ADR 0217](0217-html-spaces-of-paragraph-styles-redefined-in-files.md) のブラウザでの確かめ**：同じく、メンテナーが行う。
- **テスト用の関数を製品のモジュールから外すこと**：テスト用の内部のモジュールに移すには、golem-typeset と golem-driver の公開の形を決める ADR が要る。
- **規則の振る舞いを変えること**：記録だけを行う。
- **[golem-layout ADR 0027](../golem-layout/adr/0027-need-lines-judged-again-after-spaces.md) の範囲の外の形**：同じ段で判定した `@need-lines` の後のより大きい `@need-lines` が判定されないことは、記録でなく不具合として [golem-layout ADR 0035](../golem-layout/adr/0035-a-larger-need-lines-after-a-judged-one-is-judged-again.md) で直す。

## 不変条件

なし。
すでに入った振る舞いと手順を記録する ADR であり、振る舞いを変えない。

## テスト設計

- 自動のテストは足さない。
- ステータスの行と注釈と仕様書の文は、`adr-guard links --fix` と `adr-guard pre-commit --allow-status --allow-links` が通ることで確かめる。

## トレードオフ

実装の後で ADR を書くので、どの点も、決める前に代わりの案を比べていない。
[ADR 0211](0211-record-what-implementations-decided-found-by-the-review-of-2026-11-08.md) と同じく、点ごとに ADR を分けずに一本にまとめ、ステータスの行からその節を引けるようにした。

[ADR 0217](0217-html-spaces-of-paragraph-styles-redefined-in-files.md) の `body` の規則は、記録すると、ADR の「実装すること」の文と違う振る舞いを認めることになる。
ADR のとおりに直すと H1 が成り立たないので、直すなら H1 を改める ADR も要る。

## メンテナーが決めること

1. **[ADR 0217](0217-html-spaces-of-paragraph-styles-redefined-in-files.md) の `body` の規則**：推奨は、今のとおり接頭辞を付けないことを記録することである。接頭辞を付けると詳細度が上がり、ほかのページの前のアキに勝つので、H1 が成り立たない。
   - 退けた案は、ADR の文のとおりに接頭辞を付けることである。H1 を破るので、H1 を改める ADR と合わせて行うことになる。
2. **そのほかの記録をこのまま採るか**：推奨は、このまま採ることである。どれも、ADR の前提の誤りを ADR の目的に合わせて正したか、ADR が書いていない端を近くの規則にそろえたものである。
   - 退けた案は、ADR の文に戻すことである。[ADR 0223](0223-emet-sizes-before-building-values.md) の 64 MiB と [ADR 0224](0224-limit-the-cells-of-a-table-set-in-pdf.md) の 1 GiB は、どちらも今の入力で成り立たないので、テストが通らなくなる。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-08、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [ADR 0211](0211-record-what-implementations-decided-found-by-the-review-of-2026-11-08.md)、[ADR 0212](0212-patch-release-check-on-the-inputs-of-the-previous-release.md)、[ADR 0213](0213-numbers-the-number-formats-cannot-write.md)、[ADR 0216](0216-drawn-content-missing-from-the-structure-tree-is-an-error.md)、[ADR 0217](0217-html-spaces-of-paragraph-styles-redefined-in-files.md)、[ADR 0218](0218-page-starts-inside-code-blocks.md)、[ADR 0219](0219-frequency-of-the-wasm-job-and-its-uncached-runs.md)、[ADR 0220](0220-page-count-range-of-complex-fixtures.md)、[ADR 0222](0222-line-breaking-points-the-invariants-did-not-decide.md)、[ADR 0223](0223-emet-sizes-before-building-values.md)、[ADR 0224](0224-limit-the-cells-of-a-table-set-in-pdf.md)、[ADR 0227](0227-draw-the-glyphs-of-a-box-in-the-order-of-its-text.md)、[ADR 0228](0228-keep-the-ci-caches-under-the-10-gb-limit.md)、[ADR 0229](0229-record-the-procedures-adr-0215-and-0217-departed-from.md)
- [golem-layout ADR 0026](../golem-layout/adr/0026-need-lines-and-blank-lines-pass-over-waiting-figures.md)、[golem-layout ADR 0027](../golem-layout/adr/0027-need-lines-judged-again-after-spaces.md)、[golem-layout ADR 0028](../golem-layout/adr/0028-kinsoku-across-spaces-and-explicit-hyphens.md)、[golem-layout ADR 0030](../golem-layout/adr/0030-apostrophes-at-word-starts-are-not-closing-brackets.md)、[golem-layout ADR 0031](../golem-layout/adr/0031-line-breaks-after-low-lines-in-identifiers.md)、[golem-layout ADR 0033](../golem-layout/adr/0033-read-waiting-figures-from-the-placement.md)、[golem-driver ADR 0017](../golem-driver/adr/0017-pdf-code-blocks.md)
- 実装のプルリクエストの説明：[#666](https://github.com/tett23/golem/pull/666)、[#667](https://github.com/tett23/golem/pull/667)、[#669](https://github.com/tett23/golem/pull/669)、[#671](https://github.com/tett23/golem/pull/671)、[#673](https://github.com/tett23/golem/pull/673)、[#675](https://github.com/tett23/golem/pull/675)、[#677](https://github.com/tett23/golem/pull/677)、[#678](https://github.com/tett23/golem/pull/678)、[#679](https://github.com/tett23/golem/pull/679)、[#680](https://github.com/tett23/golem/pull/680)、[#682](https://github.com/tett23/golem/pull/682)、[#685](https://github.com/tett23/golem/pull/685)、[#688](https://github.com/tett23/golem/pull/688)、[#691](https://github.com/tett23/golem/pull/691)、[#696](https://github.com/tett23/golem/pull/696)、[#697](https://github.com/tett23/golem/pull/697)、[#699](https://github.com/tett23/golem/pull/699)
