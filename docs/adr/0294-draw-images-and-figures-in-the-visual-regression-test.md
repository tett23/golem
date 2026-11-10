# ADR 0294: 見た目の回帰テストで、画像と図版の中身を描く

ステータス: 採択（未実装）

## 文脈

見た目の回帰テストは、Golem の PDF を shem（[tett23/shem](https://github.com/tett23/shem)）で 72 dpi の画像に描き、ページごとの SHA-256 を参照と比べる（[ADR 0093](0093-fetch-shem-pinned-by-version-and-sha256.md)、[ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md)）。
shem は、画像と図版（Form XObject）の中身を読まず、灰色の箱とバツ印で描く（[shem ADR 0006](https://github.com/tett23/shem/blob/33c6bec0c82fdf9e659c40938132d64ea0e338b8/docs/adr/0006-placeholder-boxes-for-images-and-forms.md)）。
仕様書もそう書き、画像と図版の中身の変化はこのテストでは見つからないとしている。

このテストが見る入力（`scripts/visual/build.sh` の一覧）のうち、`figures`、`complex-vertical`、`complex-horizontal`、`specimens-horizontal`、`specimens-vertical` は、画像と図版を含む（[`build.sh#L27-L32`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/scripts/visual/build.sh#L27-L32)）。
箱は位置と大きさを保つので、図版がずれたことは見つかる。
画像の色の空間、透過、向き、図版の線と塗りと切り抜きの変化は見つからない。

[docs/roadmap.md](../roadmap.md) は、v2 で図版をフレームに合わせて拡大縮小するとき、画像を描けない描画系は致命的になるので、それより前に shem に描く処理を入れるとしている。
shem の側も、ロードマップの v0.x に「画像の復号（JPEG、PNG の標本、`SMask`）と、図版の描画（SVG の図版の Form、取り込んだ PDF の図版の Form）」を置いている。
shem は今、線の描画を広げる作業（[shem ADR 0025](https://github.com/tett23/shem/blob/33c6bec0c82fdf9e659c40938132d64ea0e338b8/docs/adr/0025-strokes-of-paths-with-round-caps-and-dashes.md)、[0026](https://github.com/tett23/shem/blob/33c6bec0c82fdf9e659c40938132d64ea0e338b8/docs/adr/0026-corrections-to-round-caps-and-dashes.md)）の途中にある。

この ADR は Golem の側だけを決める。
shem の振る舞いは shem の ADR で決め、ここでは Golem が shem に何を求めるかを書く。

### Golem の Writer が画像と図版について書くもの

`origin/main` の `8828fc5d` のコードから読んだ。

- **画像**（[`Writer.hs#L1209-L1256`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L1209-L1251)）：`Subtype /Image` の XObject である。JPEG は受け取ったバイト列のまま `DCTDecode` で、PNG は標本を取り出して `FlateDecode` で書き、どちらも `DecodeParms` を持たない。`BitsPerComponent` は PNG の深さ（1、2、4、8、16）のままである。色の空間は `DeviceGray`、`DeviceCMYK`、成分の数が 1、3、4 の `ICCBased`、`ICCBased` を基にした `Indexed` である。Adobe の反転した CMYK の JPEG には `Decode [1 0 1 0 1 0 1 0]` を付ける。透過は `SMask`（`DeviceGray`、`FlateDecode`）で表す。
- **SVG の図版**（[`Drawing.hs`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/modules/golem-pdf/src/Golem/Pdf/Drawing.hs)）：Form XObject の内容を Golem が書く。演算子は `q Q cm cs CS sc SC m l c h re W n f f* S B B* w J j M d` で、色は `ICCBased` の sRGB（`GolemSRGB`）である。文字、透明、パターン、シェーディングはない。
- **PDF の図版**（[`Import.hs`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/modules/golem-pdf/src/Golem/Pdf/Import.hs)）：取り込んだ PDF のページを Form XObject にする。`DeviceRGB` を sRGB の `ICCBased` に替え、特色、レイヤー、埋め込んでいないフォント、RGB のインライン画像を拒むほかは、元の PDF の内容をそのまま持つ。どの演算子と資源が現れるかは、元の PDF を書いた道具で決まる。

shem が今読む部分集合は、`ICCBased`、`f*`、`B`、`W n`、`j`、`M`、`2 J`、`sc` と `SC` を読まない（[shem の仕様書の「ページの内容の演算子」と「色」](https://github.com/tett23/shem/blob/33c6bec0c82fdf9e659c40938132d64ea0e338b8/docs/specifications.md#L111-L186)）。
今、それで落ちないのは、Form の内容を読まないからである。

## 実装すること

### 1. shem に求めるもの

Golem は、次を描く shem のリリースを待って、固定した版を上げる。

1. 上の「画像」のすべての組み合わせの復号と描画。`DCTDecode` は、ベースラインとプログレッシブ、成分の数が 1、3、4 の JPEG とする。`ICCBased` は、プロファイルを使わず、成分の数で `DeviceGray`、RGB、`DeviceCMYK` として扱う（shem の「ICC のプロファイルは使わない」方針のまま）。`SMask` で合成する。
2. 上の「SVG の図版」の演算子のすべての描画。`W n` の切り抜きを含む。
3. 見た目の回帰テストの入力にある PDF の図版（今は `figures` の `images/chart.pdf`）の内容の描画。
4. 1 から 3 の外の入力では、今のとおりファイルを書かずに終了コード 1 で終わること。箱で代わりに描かないこと。
5. 同じ版で同じ入力なら、x86-64 と aarch64 で同じ画素を出すこと（[shem ADR 0001](https://github.com/tett23/shem/blob/33c6bec0c82fdf9e659c40938132d64ea0e338b8/docs/adr/0001-scope-golem-contract-and-determinism.md) の決定性のまま）。画像の拡大縮小の標本の取り方も、整数の計算で決めること。

### 2. Writer が書くものの一覧を検査する

見た目の回帰テストの入力の PDF に現れる、内容の演算子、ストリームのフィルタ、色の空間の種類、XObject の `Subtype`、フォントの `Subtype` を、`scripts/visual/pdf-subset.txt` に一行ずつ書く。
golem-driver のテストに、見た目の回帰テストの入力を組み、PDF から同じ種類を数えて、この一覧と比べるテストを足す（内容の解析は golem-pdf の `Import.contentOperations` を使う）。
一覧にないものが現れたら、テストは落ちる。
これで、Writer が shem の読まないものを書き始めたことが、shem で描く前の golem-driver のテストで見つかる。
一覧を足す変更は、shem がそれを読む版を固定したプルリクエストでだけ行う（仕様書の「先に shem を直してリリースし、固定した版を上げる」の手順を、検査で保つ）。

### 3. 固定した版を上げる

1 を満たす shem のリリースが出たら、`scripts/visual/fetch-shem.sh` の版と SHA-256 を上げ、[ADR 0100](0100-raise-shem-to-v0-1-0-rc3-and-pre-release-bumps.md) の手順で参照（`scripts/visual/pages/`）を作り直す。
画像と図版のあるページの参照が変わる。
変わったページを、`scripts/visual/report.sh` の前と後の画像で見てから受け入れる。

### 4. 文書

- 仕様書の見た目の回帰テストの節の「画像と図版は shem が中身を読まずに箱で描く」を改め、中身を描くことと、2 の一覧の検査を書く。
- [docs/roadmap.md](../roadmap.md) の「画像と図版を描く処理」の項目を外す。3 が済むまでは「（未実装）」としてこの ADR へリンクする。
- 「手で確かめる項目」に、画像と図版のある入力を shem と pdftoppm で描いて並べ、色、透過、向き、切り抜きが合うことを目で確かめる項目を足す。shem の描いた結果が正しいことは、shem 自身のテストでも見た目の回帰テストでも示せない。

## 実装しないこと

- shem の実装。shem のリポジトリの ADR とプルリクエストで行う。
- `figures-external`（Skia、cairo、LibreOffice、LuaTeX、matplotlib、pdfTeX の書いた PDF）を見た目の回帰テストの入力に足すこと（「メンテナーが決めること」の 2）。
- 画像の色の管理（ICC のプロファイルでの変換）。PDF の画素を比べる目的には要らない。
- v2 の図版の拡大縮小そのもの。

## 不変条件

見た目の回帰テストの入力の集合を I、その PDF に現れる種類（演算子、フィルタ、色の空間、XObject とフォントの `Subtype`）の集合を K(I)、`pdf-subset.txt` の集合を S とする。

- **V1 一覧の外を書かない**：K(I) ⊆ S である。
- **V2 一覧は使われている**：S のどの要素も K(I) に現れる。使われなくなった種類は一覧から消す。
- **V3 描けない入力はない**：固定した shem は、I のすべての PDF を `unreadable` なしで描く（今の `check.sh` の検査）。
- **V4 箱で描かない**：固定した shem の版は、1 の 1 から 3 を満たすと shem のリリースノートが書く版である。

境界の入力：

| 入力 | 期待 |
| --- | --- |
| 画像も図版もない入力（`kanikosen`） | V1 から V3。参照は版を上げても変わらない |
| JPEG だけの入力（`complex-horizontal` の `photo.jpg`） | `DCTDecode` が S にある |
| 16 ビットの RGB と透過の PNG（`figures` の `trns-rgb16.png`） | `BitsPerComponent` 16 と `SMask` を描く |
| パレットと透過の PNG（`figures` の `trns-palette.png`） | `Indexed` を描く |
| `W n` を含む SVG の図版 | `W` と `n` が S にある |
| 手で書いた PDF の図版（`figures` の `chart.pdf`） | その演算子が S にある |
| S にない演算子を書く Writer の変更 | V1 で落ちる |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
テストの名前には、V1 から V4 の番号を入れる。

- **V1、V2**：golem-driver のテストに 2 の検査を足す。一覧を空にして走らせ、今のすべての種類で落ちることを確かめてから、一覧を埋める。
- **V3**：今の `visual` のジョブがそのまま確かめる。今の shem では、Form の内容を読まないので通っている。版を上げたときに通ることを確かめる。
- **V4**：自動のテストにしない。版を上げるプルリクエストで、shem のリリースノートの該当の行を引く。
- 実装の前に、今の shem で画像と図版のあるページのハッシュが箱のものであることを、`check.sh` の一覧で確かめておく。版を上げた後に、それらのページだけが変わることを確かめる。

## トレードオフ

`pdf-subset.txt` を足す変更は、shem のリリースを待つ。
Writer に新しい演算子を足す ADR は、shem の ADR とリリースを先に要る。
今もこの順は仕様書の決まりだが、検査がないので、見た目の回帰テストで shem が落ちて初めて気付く。
検査があれば、golem-driver のテストで先に気付く。

PDF の図版は、元の PDF を書いた道具で中身が変わる。
見た目の回帰テストの入力の PDF の図版を `chart.pdf` だけにしておくと、shem が読むものは小さく保てるが、利用者が実際に入れる図版の描画は確かめられない。

## メンテナーが決めること

1. **ICCBased の扱い**：推奨は、shem にプロファイルを使わず成分の数で扱ってもらうことである。shem は ICC を使わないと決めており、画素の比較にはプロファイルの変換は要らない。
   - 退けた案は、Golem の Writer が見た目の回帰テストのときだけ `ICCBased` を書かないことである。テストのときだけ出力が変わり、テストが製品の出力を見なくなる。
2. **`figures-external` を入れるか**：推奨は、この ADR では入れず、shem の v1 の範囲が決まってから別の ADR で入れることである。pdfTeX と LuaTeX の PDF は透明のグループを使い、ほかの道具の PDF も、shem の v1 の候補（透明、Type 1 のフォント、シェーディングなど）の多くを要る。
   - 退けた案は、今入れることである。shem の v1 の範囲のかなりを、v0.x のうちに求めることになり、画像と SVG の図版の描画まで遅れる。
3. **一覧を検査する場所**：推奨は golem-driver のテストである。見た目の回帰テストの入力を組む部品と、PDF の内容を読む golem-pdf の部品が、どちらもすでにそこから使える。
   - 退けた案は、`scripts/visual/check.sh` で qpdf を使って数えることである。`visual` のジョブに qpdf を入れることになり、`visual-pdfs` を待つ後でしか落ちない。

## 決めたことの記録

2026-11-10 に、tett23 が「メンテナーが決めること」のすべてを推奨のとおりに決めた。

1. `ICCBased` は、shem にプロファイルを使わず成分の数で扱ってもらう。
2. `figures-external` はこの ADR では入れず、shem の v1 の範囲が決まってから別の ADR で入れる。
3. 一覧の検査は golem-driver のテストに置く。

この ADR の実装は、「実装すること」の 1 を満たす shem のリリースを待つ。
2026-11-10 の shem の最新のリリースは v0.1.0-rc7 で、そのリリースノートに画像と図版の描画はない（Golem が固定している版は v0.1.0-rc4 である）。
そのリリースが出るまで、この ADR は実装に入らない。

採択にあたり、ソースコードへのリンクを `main` の `9acc137a`（[ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md) の実装のマージ）に合わせた。

## 参考文献

- [ADR 0093](0093-fetch-shem-pinned-by-version-and-sha256.md)、[ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md)、[ADR 0095](0095-visual-job-in-ci.md)、[ADR 0100](0100-raise-shem-to-v0-1-0-rc3-and-pre-release-bumps.md)、[ADR 0168](0168-render-visual-pdfs-side-by-side-with-shem-jobs-1.md)、[ADR 0232](0232-check-inks-fonts-figures-links-and-epubs-structurally-in-ci.md)
- [golem-pdf ADR 0008](../golem-pdf/adr/0008-pdf-figures.md)、[golem-pdf ADR 0009](../golem-pdf/adr/0009-svg-figures.md)、[golem-pdf ADR 0014](../golem-pdf/adr/0014-png-trns-transparency.md)
- shem（`33c6bec0` で読んだ）：[仕様書](https://github.com/tett23/shem/blob/33c6bec0c82fdf9e659c40938132d64ea0e338b8/docs/specifications.md)、[ロードマップ](https://github.com/tett23/shem/blob/33c6bec0c82fdf9e659c40938132d64ea0e338b8/docs/roadmap.md)、[shem ADR 0001](https://github.com/tett23/shem/blob/33c6bec0c82fdf9e659c40938132d64ea0e338b8/docs/adr/0001-scope-golem-contract-and-determinism.md)、[shem ADR 0006](https://github.com/tett23/shem/blob/33c6bec0c82fdf9e659c40938132d64ea0e338b8/docs/adr/0006-placeholder-boxes-for-images-and-forms.md)、[shem ADR 0025](https://github.com/tett23/shem/blob/33c6bec0c82fdf9e659c40938132d64ea0e338b8/docs/adr/0025-strokes-of-paths-with-round-caps-and-dashes.md)
- [`scripts/visual/build.sh`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/scripts/visual/build.sh)、[`scripts/visual/fetch-shem.sh`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/scripts/visual/fetch-shem.sh)
- ISO 32000-1 の 8.9（画像）、8.10（Form XObject）、11.6.5.3（ソフトマスクの画像）
