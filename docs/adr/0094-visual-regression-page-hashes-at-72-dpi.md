# ADR 0094: 見た目の回帰テストで、PDF のページを 72 dpi の PPM に描き、ページごとの SHA-256 をコミットした一覧と比べる

ステータス: 採択

## 文脈

### 今の検査が見ていないもの

今の Golem の検査は、PDF の見た目の変化を見ていない。
CI の `determinism` ジョブは、同じコミットを x86-64 と aarch64 で組んだ出力のハッシュを比べる（[ADR 0002](0002-determinism.md)、[ADR 0071](0071-determinism-check-compares-diagnostics.md)）。
異なるコミットの出力は比べないので、組版を崩す変更でも、二つのアーキテクチャで同じように崩れれば通る。

異なるコミットの出力を比べているのは、golem-driver の出力のゴールデン（[OutputGoldenSpec](https://github.com/tett23/golem/blob/ee7cf504744c48390908701277ae9fcfcdc85d2b/modules/golem-driver/test/OutputGoldenSpec.hs#L1-L37)、[ADR 0064](0064-goldens-that-fix-less-than-the-output.md)）である。
PDF のゴールデンは、`sample` と `figures` の二つの fixture のストリームを伸長したテキストを固定する。
ほかの fixture（『蟹工船』、『テンペスト』、パブリックドメインの十冊）と二つのマニュアルの PDF には、ゴールデンがない。
また、ゴールデンが変わったことは、見た目が変わったことを意味しない。
`VERSION` を上げれば、Producer とインスタンス ID が変わり、すべての PDF のバイト列が変わる（ゴールデンは、この二つを正規化して避けている）。
ToUnicode の誤りのように、バイト列が変わっても画面に現れない変更もある（開発者のマニュアルの「決定性を守る」の章、[見た目の回帰テストの節](https://github.com/tett23/golem/blob/ee7cf504744c48390908701277ae9fcfcdc85d2b/manual-dev/part2/12-determinism.gm#L132-L227)）。
ゴールデンの差分から、どのページの見た目が変わったかは読み取れない。

v0.1.0-rc4 では、出力を変えないリファクタリングと、単位の変換を一か所にまとめる変更（丸めが揃うので出力が変わりうる）を入れる（[roadmap の rc4](https://github.com/tett23/golem/blob/ee7cf504744c48390908701277ae9fcfcdc85d2b/docs/roadmap.md#L18-L23)）。
見た目の回帰テストは、そのときの安全網になる。

### shem の性質

PDF を画像にするのは、shem v0.1.0-rc2 である（[ADR 0093](0093-fetch-shem-pinned-by-version-and-sha256.md)）。
比べ方に関わる性質は次の五つである（[shem の仕様書](https://github.com/tett23/shem/blob/152858295b7949514e05d0ae009e858a1262dfa0/docs/specifications.md)）。

- 同じ入力と同じオプションから、x86-64 と aarch64、Linux と macOS で、バイト単位で同じ出力を出す。画素までの計算に浮動小数点数を使わない。
- PNG のバイト列は、同じ版の shem で同じ画素なら同じになるが、版が違えば画素が同じでも変わりうる（圧縮の手順を変える版はパッチバージョンを上げる）。PPM のバイト列は画素だけで決まる。
- 画像と図版（Form XObject）は、中身を読まずに灰色の箱とバツ印で描く。
- 読む部分集合の外の入力では、ファイルを一つも書かずに終了コード 1 で終わる。
- `--jobs` でページを並べて描く。既定は使えるコアの数で、出力のバイト列は `--jobs` によらない。

### 測った量

2026-10-27 に、origin/main の ee7cf504 から作った golem と、shem の release の macOS の aarch64 のアーカイブ（v0.1.0-rc1 と v0.1.0-rc2）で測った。
マシンは Apple silicon の 10 コアの macOS で、ほかの作業のセッションも動いていた（負荷の平均は 8 から 30）。
`--dpi 72 --format ppm` で、17 の PDF をすべて描けた。
shem がエラーで止まった PDF はない。
rc1 と rc2 で、1,779 ページの PPM の SHA-256 はすべて一致した。

| 入力 | ページ | PDF の大きさ |
| --- | --- | --- |
| 使い手のマニュアル | 310 | 2,656,823 バイト |
| 開発者のマニュアル | 173 | 2,815,300 バイト |
| 『蟹工船』 | 129 | 1,244,995 バイト |
| 『蟹工船』の日本式のトンボ | 129 | 1,292,213 バイト |
| 『テンペスト』 | 79 | 560,505 バイト |
| パブリックドメインの十冊 | 948 | 7,739,752 バイト |
| `figures` | 8 | 117,916 バイト |
| `sample`（`determinism.sh` と同じ B6 の縦組み） | 3 | 112,635 バイト |
| 計 | 1,779 | 16,540,139 バイト |

トンボは、`kanikosen` の `style.toml` の `[page]` に `bleed = "3mm"` を足し、`--marks japanese` で組んだ。
マニュアルは、`GOLEM_MANUAL_COMMIT` と `GOLEM_MANUAL_TAG` に決まった値を与えて組んだ。
奥付のコミットのハッシュが、コミットごとに変わらないようにするためである（[docs/specifications.md の「本文からの参照」](https://github.com/tett23/golem/blob/ee7cf504744c48390908701277ae9fcfcdc85d2b/docs/specifications.md#L531-L545)）。

描く時間と画像の大きさは次のとおりだった。
時間は 17 の PDF を一つずつ順に描いた計で、PPM の行はページの SHA-256 を取ってファイルを消すまでを含む。
rc2 は、各 PDF を `--jobs` で描いた。
rc1 は `--jobs` を持たないので、PDF を `xargs -P` で並べた。
時間は二回ずつ測り、二回の値を書いた。

| 版と形式 | 並べ方 | 時間 | ファイルの計 | 一ページの平均 |
| --- | --- | --- | --- | --- |
| rc2、72 dpi の PPM | `--jobs 1` | 38.49 秒、38.47 秒 | 測っていない | 測っていない |
| rc2、72 dpi の PPM | `--jobs 4` | 15.59 秒、15.63 秒 | 測っていない | 測っていない |
| rc2、150 dpi の PPM | `--jobs 4` | 34.18 秒（一回） | 測っていない | 測っていない |
| rc1、72 dpi の PPM | 一つずつ | 81.22 秒、81.20 秒 | 1,267.6 MB | 712.5 KB |
| rc1、72 dpi の PPM | PDF を 4 つ並べて | 21.11 秒、23.11 秒 | 同上 | 同上 |
| rc1、72 dpi の PNG | 一つずつ | 106.28 秒 | 115.4 MB | 64.9 KB |
| rc1、150 dpi の PNG | 一つずつ | 209.14 秒 | 324.0 MB | 182.1 KB |

rc2 の `--jobs 1` が rc1 の一つずつの半分に満たないのは、rc2 が出力を変えずに描画を速くしたからである（[shem ADR 0011](https://github.com/tett23/shem/blob/152858295b7949514e05d0ae009e858a1262dfa0/docs/adr/0011-speed-up-without-changing-bytes.md)）。
`--jobs 1` と `--jobs 4` で、ページの SHA-256 の一覧は一致した。

72 dpi で見つかる変化の細かさも確かめた。
『テンペスト』の `style.toml` の `[page.grid]` の `top` を、18mm から 18.001mm、18.002mm、18.005mm、18.01mm、18.1mm に変えて組み、最初の 10 ページを rc2 で描いて、`shem diff` で 18mm のものと比べた。
どの値でも、72 dpi と 150 dpi のどちらでも、10 ページすべてが変わった。
18.001mm のとき、72 dpi で違う画素の数はページごとに 3,221 以上だった。
0.001mm は約 0.0028 ポイントで、72 dpi では約 0.0028 画素にあたる。
shem はパスの点を画素の 1/256 に丸め、覆いからアンチエイリアスの濃さを求めるので、画素より小さいずれも境界の画素の値に現れる（[shem の仕様書の「描画」](https://github.com/tett23/shem/blob/152858295b7949514e05d0ae009e858a1262dfa0/docs/specifications.md#L87-L97)）。

### 参照をどこに置くか

比べる相手は、プルリクエストのベース（`main` への push では push の前）のコミットの出力である。
置き方には三つの候補があり、測った量で比べた。

- **ベースのコミットを CI で組み直す**：参照を置かずに済む。しかし、ベースのコミットの golem をもう一度ビルドする必要がある。直近の `main` の実行（40329004293）では、キャッシュを戻した後の `cabal build` が 3 分 41 秒かかった。二つのコミットの golem を CI の中で扱う手順も増える。手元でも、二つのコミットを組み直さなければ比べられない。
- **画像をコミットする**：rc1 の 72 dpi の PNG で 115.4 MB、150 dpi の PNG で 324.0 MB になる。使い手のマニュアルの前のほうを一行直すと、後ろの 300 ページほどが組み直されるので、そのたびに 72 dpi でも 20 MB ほどが履歴に積まれる。shem の版を上げれば、画素が同じでも PNG のバイト列が変わりうる。
- **ページの SHA-256 をコミットする**：PPM の SHA-256 の一覧は、1,779 ページで 164,815 バイトである。shem の決定性により、どの環境で作っても同じ一覧になる。Typst も、一部のテストでは画像の代わりにハッシュだけをコミットしている（[Typst の tests/README.md](https://github.com/typst/typst/blob/main/tests/README.md)）。

ハッシュの一覧は、変わったページがどれかを示すが、どう変わったかは示さない。
変わったページの前と後の画像を人が見る手段は、[ADR 0096](0096-before-and-after-images-of-changed-pages.md) で決める。

## 実装すること

### 入力

- 入力は次の 17 とする。どれも PDF だけを組む。
  - `sample`：`scripts/determinism.sh` と OutputGoldenSpec と同じく、`scripts/determinism/pdf-style.toml` と、`kanikosen` の Noto Serif JP と golem-font の Source Sans Pro で組む。
  - `figures`：OutputGoldenSpec と同じフォントで組む。
  - `kanikosen`、`tempest`、`pd/` の十冊：fixture のまま組む。十冊のフォントは `scripts/fixtures/copy-fonts.sh` で写す。
  - `kanikosen-marks-japanese`：`kanikosen` の `[page]` に `bleed = "3mm"` を足し、`--marks japanese` で組む。トンボの Separation の色と塗り足しの付いた `MediaBox` は、ほかの入力にない。西洋式のトンボは入れない。トンボの形が違うだけで、通る経路は日本式と同じだからである。
  - `manual` と `manual-dev`：`scripts/manual/build.sh` で組む。`GOLEM_MANUAL_COMMIT` を 0 が 40 個の文字列に、`GOLEM_MANUAL_TAG` を `v0.0.0-visual` にする。
- roadmap の rc4 の「複雑な組版の fixture」ができたら、同じプルリクエストで入力に加える。
- 入力の組み方は `scripts/visual/build.sh <出力のディレクトリ>` に置く。環境変数 `GOLEM` の golem で組み、`<入力>.pdf` を書く。各プロジェクトを一時的なディレクトリに写してから組み、リポジトリの中の `build/` を変えない。どの入力も、組むのに失敗すれば終了コード 1 で終わる。
- 入力の一覧は `build.sh` の中の一か所にだけ書き、ほかのスクリプトはそれを読む（`build.sh --list`）。

### 描き方

- 入力を一つずつ、`shem render --dpi 72 --format ppm <入力>.pdf <一時的なディレクトリ>` で全ページを描き、各ページの PPM の SHA-256 を取って、PPM を消す。
- 解像度は 72 dpi とする。文脈の測定のとおり、0.001mm のずれでも 72 dpi の画素が変わるので、解像度を上げても見つかる変化は増えない。rc2 の 150 dpi の PPM は、`--jobs 4` で時間が約 2.2 倍（15.6 秒と 34.18 秒）、ファイルが約 4.3 倍（画素の数の比）になる。
- 形式は PPM とする。PNG は shem の版で画素が同じでもバイト列が変わりうるので、比べる対象にしない。
- 並べて描くのは shem の `--jobs` に任せ、`--jobs` は渡さない（既定は使えるコアの数）。スクリプトの側では PDF を並べない。出力のバイト列は `--jobs` によらないので（[shem ADR 0009](https://github.com/tett23/shem/blob/152858295b7949514e05d0ae009e858a1262dfa0/docs/adr/0009-render-pages-in-parallel.md)）、参照はコアの数によらない。

### 参照と比べ方

- 参照は `scripts/visual/pages/<入力>.txt` に置き、Git で管理する。一行が一ページで、形は `<SHA-256>  page-<番号>`、番号は shem のファイルの名前のとおり（`page-0001`）とする。行は `LC_ALL=C` で並べる。
- `scripts/visual/check.sh <PDF のディレクトリ>` が、`build.sh --list` のすべての入力を描き、参照と比べる。比べるのはバイト列の一致だけで、閾値は設けない。Golem の出力も shem の出力も決定的なので、同じ PDF からは同じ一覧ができるからである。
- 次のどれか一つでもあれば、標準出力に一行ずつ書き、終了コード 1 で終わる。
  - `changed <入力> page-<番号>`：ページの SHA-256 が違う。
  - `added <入力> page-<番号>`：参照にないページがある。
  - `removed <入力> page-<番号>`：参照にあるページがない。
  - `unlisted <入力>`：入力に参照のファイルがない。
  - `stale <入力>`：参照のファイルに対応する入力がない。
  - `unreadable <入力>`：shem が終了コード 0 以外で終わった。shem の標準エラーの一行も書く。
- `unreadable` は、Golem が shem の読む部分集合の外を書いたことを意味する。直し方は、shem を先に直してリリースし、固定した版を上げることである（[ADR 0093](0093-fetch-shem-pinned-by-version-and-sha256.md)）。画像の比較の失敗とは原因が違うので、行の形を分ける。
- shem は、`SHEM` があればそれを、なければ `scripts/visual/fetch-shem.sh` で入れた `third_party/shem/shem` を使う。どちらも、固定した版でなければ比べずに失敗する（[ADR 0093](0093-fetch-shem-pinned-by-version-and-sha256.md)）。

### 意図して見た目を変えるとき

- `check.sh --accept <PDF のディレクトリ>` は、描いた結果で参照を書き直し、`stale` の参照を消す。出力のゴールデンの `--accept` と同じく、見た目を変えるプルリクエストは、書き直した参照を同じプルリクエストに入れる。参照の差分が、どのページの見た目が変わったかの記録になる。
- `--accept` は、組めなかった入力、ページが一つもない入力、`unreadable` の入力があれば、どの参照も書かずに失敗する。空の参照が黙ってできることを避けるためである（[ADR 0064](0064-goldens-that-fix-less-than-the-output.md) の、`--accept` が空のゴールデンを作った件）。
- 手元では、`scripts/visual/run.sh [--accept]` が、`build.sh` で組み、`fetch-shem.sh` で shem を入れ、`check.sh` で比べるまでを続けて行う。`GOLEM` が要るのは、`scripts/determinism.sh` と同じである。マニュアルのフォントは `scripts/manual/build.sh` が取る。
- プルリクエストのラベルやコミットのトレーラーで受け入れを示す仕組みは作らない。参照のファイルの差分がレビューの対象になるので、受け入れの記録はそれで足りる。

### 文書

- `docs/specifications.md` の「識別子」の節の決定性の検査の段落の後に、見た目の回帰テストの段落を足す。入力、72 dpi の PPM、ページの SHA-256 の一覧との完全な一致、`--accept` を書き、この ADR へリンクする。「Golem が強いるワークフロー」の節の、利用者のためのページ画像の差分を外部のツールに任せるという記述は変えない。このテストは Golem 自身の開発のためのものだからである。
- 開発者のマニュアルの「決定性を守る」の章の「見た目の回帰テスト」の節を書き直す。道具の候補とほかのプロジェクトの調査は残し、「外部のラスタライザを使うことになる」の一文と「考えられる進め方」の小節を、shem を別のリポジトリに作ったことと、この ADR の比べ方に置き換える。節の冒頭の「今の Golem には、…テストがない」と「着手するときに ADR を作成する」も、今の振る舞いに直す。
- README の Development の節と CONTRIBUTING.md の、`--accept` でゴールデンを書き直す手順の後に、`scripts/visual/run.sh --accept` で参照を書き直す手順を足す。開発者のマニュアルの「ビルドとテスト」の章の `--accept` の段落にも同じことを書く。
- roadmap の rc4 の「見た目の回帰テスト」の項目を、実装の後に消す。

## 実装しないこと

- 閾値や、色の差を許す比較。決定的な出力の比較で閾値を置くと、閾値より小さい変化を黙って通す。
- HTML と EPUB の見た目の比較（roadmap の「HTML の見た目の回帰テスト」）。
- 画像と図版の中身の比較。shem v0.1 は箱で描くので、図版の中身の変化は見つからない。`figures` の fixture の図版の中身は、出力のゴールデンのハッシュが固定している。マニュアルの図版の中身は、どちらの検査も固定していない。
- テキスト層（ToUnicode）、メタデータ、しおりなど、画像に現れないものの比較。出力のゴールデンと、PDF の各テストが受け持つ。
- 画像のファイルを参照としてコミットすること。文脈の測定のとおり、rc1 の 72 dpi の PNG でも 115.4 MB になる。
- CI でベースのコミットを組み直して比べること。参照の一覧を置けば、ベースの golem をビルドせずに済む。
- Haskell のテストのスイートにすること。shem は外部のコマンドで、手元と CI で同じシェルのスクリプトから呼べば足りる。golem-* のパッケージの依存も変えない。
- 解像度を入力ごとに変えること。

## テスト設計

テストを先に書き、今の実装で失敗することを確かめる。

`scripts/visual/test.sh`（[ADR 0093](0093-fetch-shem-pinned-by-version-and-sha256.md) と同じファイル）に、次を置く。
本物の golem と shem は使わない。
偽の shem は、入力の PDF の中身（テストが書いた小さなテキスト）から、ページの数と各ページの PPM を決まった形で書く。
偽の golem は、`build.sh` が渡す引数を記録し、決まった PDF を書く。

- 描いた一覧が参照と一致すれば、終了コード 0 で、標準出力が空であること。
- 一ページの中身を変えると、終了コード 1 で、`changed <入力> page-0002` の一行だけが出ること。
- ページを増やすと `added`、減らすと `removed`、参照のファイルを消すと `unlisted`、入力にない参照のファイルを置くと `stale` が出ること。
- 偽の shem が終了コード 1 で終わると、`unreadable` の行と shem の標準エラーの一行が出ること。
- `--accept` の後に `check.sh` を動かすと、終了コード 0 になること。`--accept` が書いた参照の行が `LC_ALL=C` の順であること。`stale` の参照が消えること。
- 入力が一つ組めないとき、ページが一つもないとき、`unreadable` のときに、`--accept` が失敗し、どの参照も変わらないこと。
- `check.sh` が shem に `--jobs` を渡さず、入力を一つずつ描くこと（偽の shem が引数を記録する）。
- `build.sh` が、マニュアルを `GOLEM_MANUAL_COMMIT` と `GOLEM_MANUAL_TAG` の決まった値で組むこと、トンボの入力に `--marks japanese` を渡すこと、リポジトリの中の `build/` に何も書かないこと。

実際の入力では、自動のテストにできない次のことを、実装のプルリクエストで確かめて記録する。

- 手元の macOS の aarch64 で作った参照と、CI の x86-64 の Linux で描いた一覧が一致すること。
- `VERSION` だけを変えて組んだ PDF で、参照が変わらないこと。Producer とインスタンス ID は画像に現れないからである。
- 『テンペスト』の `top` を 0.001mm 変えると、`check.sh` が失敗すること（文脈の測定の再現）。

## トレードオフ

- 完全な一致で比べるので、人の目で見分けられないずれでもテストが失敗する。0.001mm のずれで全ページが変わったので、単位の変換を一か所にまとめる変更のように丸めが変わる変更では、大半のページで参照を書き直すことになる。この費用は受け入れる。見分けられない変化を受け入れるかどうかは、前と後の画像と差分の画像（[ADR 0096](0096-before-and-after-images-of-changed-pages.md)）を見て人が決める。黙って通す閾値より、人に見せるほうを選ぶ。
- マニュアルを入力にしたので、マニュアルの文章を直すプルリクエストでも、直した位置より後ろのページの参照が変わり、`--accept` が要る。マニュアルは最も大きな組版の例なので、入力に含める。
- 参照を書き直すには、手元で golem をビルドし、shem とマニュアルのフォントを取る必要がある。文脈と同じマシンで、17 の入力を組むのに約 40 秒（1 秒単位の計で、マニュアルのフォントの取得を含む）、rc2 の `--jobs 4` で描くのに約 16 秒かかった。
- 参照の一覧は、どのページが変わったかしか示さない。どう変わったかは、CI の成果物（[ADR 0096](0096-before-and-after-images-of-changed-pages.md)）か、手元で描いた画像で見る。
- 出力のゴールデンと同じく、別々に参照を書き直した二つのプルリクエストを続けてマージすると、組み合わせた出力がどちらの参照とも違い、`main` の CI が落ちうる。
- shem v0.1 は画像と図版を箱で描くので、図版の中身の崩れは見つからない。shem が中身を描くようになれば（shem の roadmap の v0.x）、版を上げるときに参照を書き直す。

## 参考文献

- [ADR 0002](0002-determinism.md)
- [ADR 0064](0064-goldens-that-fix-less-than-the-output.md)
- [ADR 0071](0071-determinism-check-compares-diagnostics.md)
- [ADR 0093](0093-fetch-shem-pinned-by-version-and-sha256.md)
- [ADR 0095](0095-visual-job-in-ci.md)
- [ADR 0096](0096-before-and-after-images-of-changed-pages.md)
- Golem の開発者のマニュアルの「決定性を守る」の章の「見た目の回帰テスト」の節 https://github.com/tett23/golem/blob/ee7cf504744c48390908701277ae9fcfcdc85d2b/manual-dev/part2/12-determinism.gm#L132-L227
- Golem の OutputGoldenSpec https://github.com/tett23/golem/blob/ee7cf504744c48390908701277ae9fcfcdc85d2b/modules/golem-driver/test/OutputGoldenSpec.hs
- shem の仕様書 https://github.com/tett23/shem/blob/152858295b7949514e05d0ae009e858a1262dfa0/docs/specifications.md
- [shem ADR 0009「ページを並列に描く」](https://github.com/tett23/shem/blob/152858295b7949514e05d0ae009e858a1262dfa0/docs/adr/0009-render-pages-in-parallel.md)
- [shem ADR 0011「出力のバイト列を変えない高速化（フォントの使い回しなど）」](https://github.com/tett23/shem/blob/152858295b7949514e05d0ae009e858a1262dfa0/docs/adr/0011-speed-up-without-changing-bytes.md)
- [shem ADR 0007「PNG の書き出し、解像度、CLI の形」](https://github.com/tett23/shem/blob/152858295b7949514e05d0ae009e858a1262dfa0/docs/adr/0007-png-output-resolution-and-cli.md)
- Typst の tests/README.md https://github.com/typst/typst/blob/main/tests/README.md
