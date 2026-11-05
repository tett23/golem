# ADR 0168: 見た目の回帰テストで、PDF を並べて描き、shem に `--jobs 1` を渡す

ステータス: 採択（未実装）

## 文脈

見た目の回帰テストの `scripts/visual/check.sh` は、17 の入力の PDF を一つずつ `shem render --dpi 72 --format ppm` で描き、ページごとの PPM の SHA-256 を参照と比べる（[ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md)、[check.sh](https://github.com/tett23/golem/blob/3693218a8990fdea1f090faa8ec8f91e6d02ebf1/scripts/visual/check.sh#L70-L98)）。
一つの PDF のページを並べて描くのは shem の `--jobs` に任せ、`check.sh` は `--jobs` を渡さない。
[ADR 0100](0100-raise-shem-to-v0-1-0-rc3-and-pre-release-bumps.md) は、shem を v0.1.0-rc3 に上げるときも、この描き方（一度に一つの PDF、shem の既定の `--jobs`）を変えないと決めた。
`scripts/visual/test.sh` は、`check.sh` が `--jobs` を渡さないことを確かめている（[test.sh](https://github.com/tett23/golem/blob/3693218a8990fdea1f090faa8ec8f91e6d02ebf1/scripts/visual/test.sh#L233)）。

shem は 2026-11-04 に v0.1.0-rc4 を出し、Golem は [#552](https://github.com/tett23/golem/pull/552) でこれに上げた。
rc4 は、rc3 と同じ画素と PPM のバイトを出したまま、一つのスレッドでも複数のスレッドでも速くなった（[shem ADR 0014](https://github.com/tett23/shem/blob/f113cbf16f6695ea8ae5c343fed3d83aaa107b50/docs/adr/0014-thread-workspaces-and-faster-check-and-fill.md)、[shem ADR 0015](https://github.com/tett23/shem/blob/f113cbf16f6695ea8ae5c343fed3d83aaa107b50/docs/adr/0015-faster-png-render-and-decoding.md)）。
この ADR は、rc4 で `--jobs` の渡し方と PDF の並べ方を測り直し、`check.sh` の描き方を決め直す。

### 0098 番の下書きとの関係

コミットしていない 0098 番の下書きの ADR「見た目の回帰テストで、PDF を shem の `--jobs 1` で描き、PDF を並べる」は、この ADR と同じ形（PDF ごとに `--jobs 1` の shem を起こし、`xargs -P` で並べる）を提案していた。
その理由は、shem v0.1.0-rc2 の Linux の配布物（musl で静的にリンクしたもの）が、スレッドを増やすと遅くなることだった。
rc3 がこの遅さを直したので、[ADR 0100](0100-raise-shem-to-v0-1-0-rc3-and-pre-release-bumps.md) は下書きの 0098 を取り下げた。

この ADR は、同じ形をもう一度提案するが、理由が違う。
rc4 では、一つの shem のスレッドを増やすと速くなる。
それでも、PDF を並べて描くほうが、PDF を一つずつ既定の `--jobs` で描くより速い（次の節）。
下書きの 0098 はコミットされておらず、この ADR が置き換える。
下書きのファイルは、メンテナーが消すか残すかを決める。

### 測ったこと

17 の PDF（1,813 ページ）を 72 dpi の PPM に描き、ページの SHA-256 を取って PPM を消すまでの実時間を、描き方を変えて測った。
`check.sh` の参照との比べは含めない。
測るためのスクリプトは、PDF を一つ描いてハッシュを取る `one.sh` と、描き方ごとに時間を取る `bench.sh` で、コミットしていない。

描き方は次のとおりである。

- **seq-J**：PDF を一つずつ、`--jobs J` で描く。`seq-default` は `--jobs` を渡さない今の `check.sh` の形である。
- **parP-jJ**：PDF を大きい順（バイト数）に `xargs -n 1 -P P` で並べ、それぞれを `--jobs J` で描く。

CI は、捨てる draft のプルリクエスト [#554](https://github.com/tett23/golem/pull/554)（閉じた）の `visual` ジョブで、成果物 `visual-pdfs` に対して測った（実行 [41936584731](https://github.com/tett23/golem/actions/runs/41936584731)、2026-11-05）。
ランナーは `ubuntu-24.04` で、`nproc` が 4、CPU は AMD EPYC 9V45（2 コア、1 コアに 2 スレッド）だった。
shem は x86_64-unknown-linux-musl の配布物である。

| 描き方 | rc4（3 回、秒） | rc3（1 回、秒） |
|---|---|---|
| seq-default（今の形） | 2.98、2.92、2.96 | 6.37 |
| seq-1 | 5.69、5.50、5.50 | 13.89 |
| seq-2 | 3.53、3.59、3.49 | 8.13 |
| seq-4 | 2.89、2.94、2.90 | 6.39 |
| seq-8 | 2.94、3.00、2.96 | 6.66 |
| par2-j1 | 2.92、2.90、2.90 | 7.29 |
| par2-j2 | 2.27、2.34、2.31 | 5.34 |
| par4-j1 | 2.01、1.98、1.97 | 5.10 |
| par4-j2 | 2.03、2.03、2.10 | 5.15 |
| par4-jdefault | 2.06、2.13、2.08 | 5.13 |

手元は、10 コアの Apple silicon の macOS（`getconf _NPROCESSORS_ONLN` が 10）で、shem は aarch64-apple-darwin の配布物である。
PDF は [#552](https://github.com/tett23/golem/pull/552) のコミットで `scripts/visual/build.sh` が組んだものである。

| 描き方 | rc4（3 回、秒） | rc3（1 回、秒） |
|---|---|---|
| seq-default（今の形） | 2.30、2.31、2.41 | 3.65 |
| seq-1 | 5.37、5.34、5.61 | 15.09 |
| seq-10 | 2.28、2.31、2.38 | 3.74 |
| par2-j2 | 1.92、2.14、2.11 | 4.59 |
| par10-j1 | 1.17、1.30、1.18 | 3.19 |
| par10-j2 | 1.00、1.19、1.12 | 2.67 |
| par10-jdefault | 0.93、1.07、1.03 | 2.27 |

読み取れることは次のとおりである。

- `--jobs` の既定は、ランナーのコアの数（CI で 4、手元で 10）を明示したときと同じ時間だった。`--jobs` を明示するだけでは速くならない。
- PDF をコアの数だけ並べると、CI で約 2.95 秒から約 2.0 秒に、手元で約 2.3 秒から約 1.2 秒に縮んだ。
- 並べたときの `--jobs` は、CI では 1、2、既定でほとんど変わらず、`--jobs 1` がわずかに速かった。手元では既定が `--jobs 1` より 0.1〜0.2 秒速かった。
- 一つずつ描くと遅い理由は確かめていない。17 の入力のうち 11 は 90 ページ未満で（`sample` は 3 ページ、`figures` は 8 ページ）、shem はページを描く前に、描くページをすべて読んで検査する。この部分と、ページの少ない PDF が、一つの PDF の中のスレッドで縮みにくいと考えられる。

`check.sh` の手順としての CI の時間は、rc3 の main の 15 回で 6〜10 秒（中央値 8 秒）、rc4 の #552 の 3 回で 4、4、5 秒だった（[docs/ci-timings/2026-11-05-shem-rc4.md](../ci-timings/2026-11-05-shem-rc4.md)）。
上の表の差（約 1 秒）がそのまま縮めば、比べる手順は 3〜4 秒になる。

### 出力の一致

ページの SHA-256 は、描き方によらず一致した。

- CI の rc4 の 30 回と rc3 の 10 回で、すべてのページの行をまとめた SHA-256 は一つだった。
- 手元の rc4 と rc3 でも、すべての描き方で一つだった。
- 同じ PDF に対して、CI（x86-64 の Linux）と手元（aarch64 の macOS）の値が一致した。CI の `visual-pdfs` は手元で組んだ PDF とバイト単位で一致した。

shem は、出力のバイト列が `--jobs` によらないと約束している（[shem ADR 0009](https://github.com/tett23/shem/blob/f113cbf16f6695ea8ae5c343fed3d83aaa107b50/docs/adr/0009-render-pages-in-parallel.md)）。
PDF を並べることは、別々のプロセスが別々のディレクトリに書くだけなので、ページのバイト列に影響しない。

### 見込める短縮

縮むのは比べる手順の約 1 秒で、`visual` ジョブの終わりもその分だけ早くなる。
`visual` は `outputs` が PDF を上げるのを待つので、PDF が上がってから `visual` が終わるまで（rc4 で 14〜15 秒）のうちの約 1 秒である。
手元で `scripts/visual/run.sh` を動かす開発者には、描く部分の約 2.3 秒が約 1.2 秒になる。
`build.sh` の 17〜20 秒に比べると、どちらも小さい。

## 実装すること

テストを先に書き、今の実装で失敗することを確かめる。

- `check.sh` は、PDF のある入力を、ランナーのプロセッサの数（`getconf _NPROCESSORS_ONLN`、取れなければ 1）を上限に同時に描く。上限の決め方は `build.sh` と同じにする（[ADR 0163](0163-build-visual-pdfs-in-parallel.md)）。上限を変える環境変数は設けない。
- 各 shem には `--jobs 1` を渡す。同時に動くスレッドの数を、上限と同じにするためである。既定の `--jobs` を渡さずに並べると、プロセスの数とコアの数の積のスレッドが動く。CI では `--jobs 1` が既定と同じか速く、手元で既定が速い差は 0.2 秒以内だった。
- 描き始める順は、PDF の大きさ（バイト数）の大きい順、同じ大きさなら入力の名前の順とする。大きな PDF が最後に始まって一つだけ残るのを避けるためである。順は結果に影響しない。
- 一つの入力を描いてハッシュを取る処理は、入力ごとの一時的なディレクトリと、入力ごとの結果のファイル（ページの SHA-256 の一覧、shem の標準エラー出力、shem の終了コード）に書く。入力によらない同じファイルを使わない（[ADR 0163](0163-build-visual-pdfs-in-parallel.md) が `build.sh` で見つけた取り違えと同じ理由）。
- すべての入力を描き終えてから、入力の一覧の順に結果を読み、今と同じ行（`changed`、`added`、`removed`、`unlisted`、`stale`、`unreadable`、`missing`）を、今と同じ順に標準出力に書く。`--accept` と `--lists` の振る舞いも変えない。
- 入力の名前（`check: rendering <入力>`）は、描き始めるときに標準エラー出力に書く。並べて描くので、名前の順は入力の一覧の順と変わりうる。止まった実行では、名前が出ていて結果のファイルがない入力のどれかが止まっている（[ADR 0095](0095-visual-job-in-ci.md) の、どこで止まったかを示す目的）。
- `ci.yml` は変えない。比べる手順の上限（600 秒）も変えない。
- `scripts/visual/report.sh` の `shem render` と `shem diff` は変えない。報告は比べる手順が失敗したときだけ動き、変わったページだけを描く。
- `docs/specifications.md` の見た目の回帰テストの節に、PDF を並べて `--jobs 1` で描くことを書く。
- 開発者のマニュアルの「決定性」の章（`manual-dev/part2/12-determinism.gm`）の、PDF を一つずつ描き、ページを並べるのを shem の `--jobs` に任せるという段落を直す。同じ章の、CI の比べる手順が約 216 秒で予算を超えているという段落は、rc2 の時の値で、今は 4〜5 秒なので、測った値に直す。マニュアルを直すと `manual-dev` の PDF が変わるので、同じプルリクエストで `scripts/visual/pages/manual-dev.txt` の変わったページの行を、CI の成果物 `visual-diff` の一覧から写して直す。
- 実装のプルリクエストの 2 回の実行で、比べる手順の秒数を記録し、`docs/ci-timings/` に置く。
- [ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md) のステータスの行を「採択→PDF の描き方（PDF を並べ、`--jobs 1` を渡すこと）は ADR 0168」に変える。
- [ADR 0095](0095-visual-job-in-ci.md) のステータスの行の末尾に「、shem のコアの使い方は ADR 0168」を足す。
- [ADR 0100](0100-raise-shem-to-v0-1-0-rc3-and-pre-release-bumps.md) のステータスの行を「採択→`visual` の描き方（`--jobs` を渡さないこと）は ADR 0168」に変える。

## 実装しないこと

- **`--jobs` を明示して PDF を一つずつ描くこと。** 既定の `--jobs` はコアの数で、明示しても時間は変わらなかった。
- **上限を変える環境変数。** 手元でもコアの数が上限としてよく、`build.sh` も環境変数を持たない。必要になれば別の ADR で足す。
- **`report.sh` の描き方を変えること。** 失敗したときだけ動き、時間は比べる手順の予算に入らない。
- **shem を変えること。** 一つの PDF の中で、描く前の読み込みと検査を並べるのは shem の側の変更で、shem のリポジトリで扱う。shem がそれを並べれば、この ADR の短縮は小さくなりうる。そのときは測り直して、この ADR を改める ADR を出す。
- **PPM をファイルに書かずにハッシュを取ること。** shem に標準出力へ書く機能はなく、[ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md) の範囲の外である。

## テスト設計

### 先に書いて失敗させるテスト（`scripts/visual/test.sh`）

今の偽の shem（引数を `shem.log` に書き、PDF の行ごとに一ページの PPM を書くもの）を、次のように使う。

- shem の `render` の呼び出しがすべて `--jobs 1` を持つこと。今の「`--jobs` を渡さない」の項目（[test.sh](https://github.com/tett23/golem/blob/3693218a8990fdea1f090faa8ec8f91e6d02ebf1/scripts/visual/test.sh#L233)）を置き換える。一つの呼び出しの引数の数は 7 から 9 になる。今の実装では `--jobs` を渡さないので失敗する。
- 偽の shem が、始まりと終わりに印のファイルを書き、入力の名前ごとに決まった時間だけ待つ。二つの入力を同時に描いたこと（同時に動いた数の最大が 2 以上）と、同時に動いた数が `getconf _NPROCESSORS_ONLN` の値を超えないことを確かめる。今の実装では最大が 1 なので失敗する。`getconf` が 1 を返すランナーでは、前者の項目を飛ばしたことを出力に書く。
- 偽の shem が、入力の一覧で先にある入力ほど長く待つようにして、二つの入力のページを変え、一つの PDF を消し、一つを shem が読めないものにする。標準出力が、今の実装の出力（このテストを先に書いたときに今の実装で取り、テストに書く）と一致すること。描き終える順が入力の一覧の順と逆でも、出力の順が変わらないことを確かめる。
- `--accept` が書く参照と、`--lists` が書く一覧が、今の実装と同じであること。
- `check: rendering <入力>` が、17 の入力のそれぞれについて標準エラー出力に一度ずつ出ること。

今の項目（`unreadable` と shem の一行、`stale`、`missing`、`--accept` が書かない場合など）は、そのまま通ること。
テストは `changes` と `scripts-macos` の両方で動く（[ADR 0079](0079-shell-tests-on-macos.md)）。

### 自動テストにできないものの確かめ方

- 実装のプルリクエストで、`scripts/visual/pages/` のうち `manual-dev.txt` の、マニュアルを直したページの行のほかを変えずに `visual` が通ること。
- 同じプルリクエストの 2 回の実行で、比べる手順の秒数を記録し、この ADR の見込み（3〜4 秒）と比べる。

## トレードオフ

- 縮むのは CI で約 1 秒、手元で約 1 秒である。`check.sh` には、背景のプロセスを数えて待つ処理と、入力ごとの結果のファイルと、描き終えてから順に読む処理が加わる。`build.sh` が [ADR 0163](0163-build-visual-pdfs-in-parallel.md) で同じ形を持つので、書き方はそれに合わせられるが、[ADR 0163](0163-build-visual-pdfs-in-parallel.md) の 15〜25 秒に比べて、得るものは一桁小さい。
- `--jobs 1` は、手元の 10 コアでは既定より 0.1〜0.2 秒遅い。スレッドの数を上限と同じにする予測のしやすさを取る。
- 止まった shem がどれかは、名前の出た入力のうち結果のないものとしてしかわからない。今は、最後に名前の出た入力が止まっている。
- 同時に描く PDF の数だけ、一時的な PPM がディスクにある。最も大きい `manual.pdf` の PPM は約 223 MB（下書きの 0098 の CI の測定）で、ランナーのディスクの空きに比べて小さい。
- shem が一つの PDF の中の読み込みと検査を並べるようになれば、短縮は小さくなりうる。そのとき、並べる処理は残っても害はないが、得るものがなくなる。

## 決めてほしい点

- **この ADR を採るか。** 縮むのは CI と手元でそれぞれ約 1 秒で、`check.sh` の複雑さが増える。採らずに却下とし、`--jobs` を渡さない今の形を続けるのも妥当な選択である。却下するなら、この ADR の測定は、`--jobs` を明示しても速くならない記録として残る。
- **`--jobs 1` か、既定の `--jobs` か。** 推奨は `--jobs 1`（CI で同じか速い、スレッドの数が上限と一致する）。
- **上限をコアの数にするか、固定の数にするか。** 推奨はコアの数（`build.sh` と同じ規則。固定の数にすると、手元の 10 コアで縮まない）。

## 決めたことの記録

- **採択**：メンテナーが「rc4 に上がったので --jobs を増やして。上限はコア数で」として採択した（2026-11-05）。並べて描く数の上限はコア数（`getconf _NPROCESSORS_ONLN`）とする。この ADR が決めてほしい点として挙げたほかの項目は、どれも ADR の推奨のとおりとする。

## 参考文献

- [ADR 0079](0079-shell-tests-on-macos.md)、[ADR 0093](0093-fetch-shem-pinned-by-version-and-sha256.md)、[ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md)、[ADR 0095](0095-visual-job-in-ci.md)、[ADR 0099](0099-visual-job-waits-only-for-visual-pdfs.md)、[ADR 0100](0100-raise-shem-to-v0-1-0-rc3-and-pre-release-bumps.md)、[ADR 0163](0163-build-visual-pdfs-in-parallel.md)
- 0098 番の下書きの ADR「見た目の回帰テストで、PDF を shem の `--jobs 1` で描き、PDF を並べる」（コミットしていない）
- [scripts/visual/check.sh](https://github.com/tett23/golem/blob/3693218a8990fdea1f090faa8ec8f91e6d02ebf1/scripts/visual/check.sh)、[scripts/visual/test.sh](https://github.com/tett23/golem/blob/3693218a8990fdea1f090faa8ec8f91e6d02ebf1/scripts/visual/test.sh)
- shem v0.1.0-rc4 の release https://github.com/tett23/shem/releases/tag/v0.1.0-rc4
- [shem ADR 0009「ページを並列に描く」](https://github.com/tett23/shem/blob/f113cbf16f6695ea8ae5c343fed3d83aaa107b50/docs/adr/0009-render-pages-in-parallel.md)、[shem ADR 0014](https://github.com/tett23/shem/blob/f113cbf16f6695ea8ae5c343fed3d83aaa107b50/docs/adr/0014-thread-workspaces-and-faster-check-and-fill.md)、[shem ADR 0015](https://github.com/tett23/shem/blob/f113cbf16f6695ea8ae5c343fed3d83aaa107b50/docs/adr/0015-faster-png-render-and-decoding.md)
- 計測のデータ：CI の実行 41936584731（#554、2026-11-05）、手元の計測（2026-11-05）、[docs/ci-timings/2026-11-05-shem-rc4.md](../ci-timings/2026-11-05-shem-rc4.md)
