# ADR 0076: ADR のテスト設計より弱いテストを、テスト設計のとおりに強める

ステータス: 採択（未実装）

## 文脈

ADR のテスト設計は、採択のときに「これが通れば実装したとみなす」条件として読まれる。
テストがそれより弱いと、ADR のステータスが採択になっていても、条件の一部は確かめられていない。
2026-10-23 のテストの品質の点検は、ADR を 17 本抜き出して、テストと比べた。
コードと照らし合わせ、次の四つはテストがテスト設計より弱いことを確かめた。

- [ADR 0035](0035-security-hardening.md) の 123 行めは、`highlight=1-1000000000000` のコードで「強調される行が今と同じである」ことを求める。[modules/golem-eval/test/FileSpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-eval/test/FileSpec.hs#L1243-L1249) は `highlight=2-1000000000000` を使い、G02069 と評価が終わることだけを断言する。大きな範囲で強調される行は断言していない。
- [ADR 0035](0035-security-hardening.md) の 28-29 行めは、`build` と、出力するターゲットのディレクトリ（`build/html`、`build/epub`、`build/text`、`build/pdf`）のどれかがシンボリックリンクか、ディレクトリ以外のファイルなら G08013 を出すと定める。[modules/golem-driver/test/SecuritySpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/SecuritySpec.hs#L48-L68) は、`build` と `build/html` のシンボリックリンクだけを試す。テスト設計（110-111 行め）もこの二つだけを挙げているが、実装すること（[`unsafeOutputDirs`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/src/Golem/Driver.hs#L896-L911)）の残りの経路を確かめるテストがない。出力しないターゲットのディレクトリは調べない（[`targets` に限る](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/src/Golem/Driver.hs#L901)）ことも、確かめていない。
- [ADR 0051](0051-reuse-repeated-pdf-content-streams.md) の 151 行めは、組んだ PDF の「図版の Form XObject の `Resources` に内側の Form があること」を求める。[modules/golem-driver/test/FigureSpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/FigureSpec.hs#L125-L132) は `/Subtype /Form` の数と `/GolemC4 ` の出現の数だけを断言し、どの辞書の中にあるかは見ていない。golem-pdf の単体テスト（[modules/golem-pdf/test/ImportSpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-pdf/test/ImportSpec.hs#L341-L360)）は取り込みの結果の値で入れ子を確かめているので、欠けているのは組んだ PDF の側だけである。
- [ADR 0015](0015-regex-styles.md) の 415 行めは、縦組みで「ルビが親文字の上に置かれること」を求める。縦組みの「上」は行の右である（docs/specifications.md:1237）。[modules/golem-driver/test/StylesSpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/StylesSpec.hs#L76-L80) は字の大きさだけを断言し、位置は見ていない。

[ADR 0035](0035-security-hardening.md) の CSL-JSON の年のテスト（[modules/golem-driver/test/SecuritySpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/SecuritySpec.hs#L86)）が、テスト設計の 10 秒ではなく 20 秒の時間切れを使うことも、点検は挙げた。
時間切れの値の扱いは [ADR 0073](0073-time-bounds-in-tests.md) で決めるので、この ADR では扱わない。

点検が挙げた残りの項目は、テストの不足ではなかった。

- [ADR 0041](0041-svg-marker-and-number-limits.md) の 57 行めの「深さ 9 の入れ子の `marker` は描かれ」は、各段で四つに分かれることを求めていない。一本の鎖で試すテスト（[modules/golem-svg/test/SecuritySpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-svg/test/SecuritySpec.hs#L237-L250)）は、テスト設計に合っている。
- [golem-eval ADR 0006](../golem-eval/adr/0006-exact-power-limit-before-range.md) の 149 行めが挙げる `15e-1` は、Golem の式の言語に指数の書き方がない（[golem-parser の `number`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-parser/src/Golem/Parser/Lower.hs#L363-L367) は整数と小数だけを読む）ので、今はテストに書けない。指数の書き方は v0.1.0-rc4 で式の言語に加える（[docs/roadmap.md](../roadmap.md) の v0.1.0-rc4 の「式の言語の指数の書き方」）。そのときにこの項目のテストを書けるようになる。
- [golem-layout ADR 0018](../golem-layout/adr/0018-url-line-breaks.md) の 111 行めの「本文の文字の大きさの四分の一」と、[modules/golem-driver/test/ReferencesSpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/ReferencesSpec.hs#L764) が比べる「注の印の大きさの四分の一」は、同じ値である。注の印は脚注の本文と同じ大きさの文字として置かれる（[golem-driver の `withNoteMark`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/src/Golem/Driver/Pdf.hs#L1602-L1609)）。

## 実装すること

- highlight：`highlight=1-1000000000000` の三行のコードで、三行とも強調され、G02069 が行 4 について一つ出ることを断言する。今の `2-…` のテストは残す。
- G08013：次のテストを足す。
  - `build/epub`、`build/text`、`build/pdf` のそれぞれがシンボリックリンクのとき、そのターゲットを出力すると G08013 になり、リンク先のファイルが残る。
  - `build/html` がディレクトリではなく通常のファイルのとき G08013 になる。
  - プロジェクトの中のディレクトリを指すシンボリックリンクも G08013 になる（[ADR 0035](0035-security-hardening.md) の 29 行めは、リンク先を問わない）。
  - 受け入れ側として、`build/pdf` がシンボリックリンクでも、HTML だけを出力するビルドは G08013 にならず、`build/html` に書く。
- [ADR 0051](0051-reuse-repeated-pdf-content-streams.md)：組んだ PDF を `qpdf --qdf --object-streams=disable` で展開した形にし、オブジェクトの番号で辞書をたどって、図版の Form XObject の `Resources` の `XObject` に `GolemC4` があり、その値の Form の `Resources` には `GolemC4` がないことを断言する。qpdf はこのテストですでに使っている（[FigureSpec.hs の `qpdfCheck` の呼び出し](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/FigureSpec.hs#L132)、[modules/golem-driver/test/Support.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/Support.hs#L512-L513)）。たどる処理は [Support.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/Support.hs) に書き、JSON を読むための依存（aeson）は足さない。
- [ADR 0015](0015-regex-styles.md)：縦組みのルビの読みの字（と）の x 座標が、親文字（東）の x 座標より大きく、y 座標の範囲が親文字の範囲と重なることを断言する。

## 実装しないこと

- [golem-eval ADR 0006](../golem-eval/adr/0006-exact-power-limit-before-range.md) の `15e-1` のテストを書くこと。v0.1.0-rc4 で式の言語に指数の書き方を加えた後に書く。指数の書き方が入れば項目はそのまま書けるので、今は書けないことを記録する ADR は作らない。
- 点検がサンプルしなかった ADR のテスト設計を、すべて照らし合わせること。

## テスト設計

この ADR はテストを足すだけなので、足したテストが、それぞれ次の変異で落ちることを確かめる。

- highlight：大きな範囲を空の集合として扱う変異（強調なしになる）。
- G08013：`unsafeOutputDirs` の対象を `build` と `build/html` に限る変異。受け入れ側は、出力しないターゲットのディレクトリも調べる変異。
- [ADR 0051](0051-reuse-repeated-pdf-content-streams.md)：内側の Form を外側の `Resources` ではなくページの `Resources` に足す変異。
- [ADR 0015](0015-regex-styles.md)：縦組みのルビを親文字の左に置く変異。

## トレードオフ

- [ADR 0051](0051-reuse-repeated-pdf-content-streams.md) のテストは、qpdf の QDF の形をテストの中で読む。辞書を正規表現でたどる簡単な読み取りなので、qpdf の出力の書式が変われば直す必要がある。

## 参考文献

- [ADR 0015](0015-regex-styles.md)
- [ADR 0035](0035-security-hardening.md)
- [ADR 0041](0041-svg-marker-and-number-limits.md)
- [ADR 0051](0051-reuse-repeated-pdf-content-streams.md)
- [ADR 0073](0073-time-bounds-in-tests.md)
- [golem-eval ADR 0006](../golem-eval/adr/0006-exact-power-limit-before-range.md)
- [golem-layout ADR 0018](../golem-layout/adr/0018-url-line-breaks.md)
