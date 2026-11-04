# ADR 0140: build のテストを四つのランナーに分け、visual-pdfs を決定性の検査の出力より先に組む

ステータス: 採択（未実装）

## 文脈

`ci.yml` の一回の実行は、プルリクエストで 3 分半から 4 分ほどかかる。
[ADR 0097](0097-ci-same-path-before-build-and-env-check-runner.md) と [ADR 0099](0099-visual-job-waits-only-for-visual-pdfs.md) の後、臨界経路は一本のジョブではなくなった。
`build` の行列の各ランナーと `visual` が、ほぼ同じ時刻に終わる。

### 計測

2026-11-04 のプルリクエストの 10 回の実行を、`gh run view <id> --json jobs` で取った。
次の表は、実行の最初のジョブの始まりから、各ジョブが終わるまでの秒数である。

| 実行 | `x-tests` | `arm-all` | `visual` | `x-outputs` | `x-env` |
|---|---|---|---|---|---|
| [41785790404](https://github.com/tett23/golem/actions/runs/41785790404) | 208 | 190 | 190 | 178 | 87 |
| [41785477761](https://github.com/tett23/golem/actions/runs/41785477761) | 224 | 207 | 147 | 139 | 99 |
| [41784899059](https://github.com/tett23/golem/actions/runs/41784899059) | 158 | 199 | 198 | 191 | 90 |
| [41783846229](https://github.com/tett23/golem/actions/runs/41783846229) | 210 | 184 | 146 | 141 | 85 |
| [41782495838](https://github.com/tett23/golem/actions/runs/41782495838) | 213 | 196 | 156 | 143 | 88 |
| [41781230608](https://github.com/tett23/golem/actions/runs/41781230608) | 210 | 222 | 238 | 227 | 125 |
| [41780771663](https://github.com/tett23/golem/actions/runs/41780771663) | 239 | 225 | 223 | 215 | 134 |
| [41777232052](https://github.com/tett23/golem/actions/runs/41777232052) | 296 | 289 | 233 | 229 | 167 |
| [41775715478](https://github.com/tett23/golem/actions/runs/41775715478) | 365 | 339 | 304 | 296 | 218 |
| [41773489912](https://github.com/tett23/golem/actions/runs/41773489912) | 293 | 291 | 234 | 230 | 194 |

`x-` は x86-64 の `build`、`arm-all` は aarch64 の `build` である。
後の三つの実行は、プルリクエストが下のほうのパッケージを変え、`cabal build` が 86 秒から 192 秒かかった。
ほかの七つの `cabal build` は 13 秒から 72 秒である。
最後に終わるのは、10 回のうち 7 回が `x-tests`、2 回が `visual`、1 回が `arm-all` だった。
`determinism` と `ci` は、`build` の行列のすべてが終わった後に、合わせて 15 秒ほどかかる。

各ランナーは、仕事の前に同じ準備を払う。
チェックアウトと五つのキャッシュの復元、GHC と cabal の用意で、x86-64 で約 30 秒、aarch64 で約 40 秒かかる。
その後の `cabal build` は、モジュールを変えないプルリクエストで 15 秒から 30 秒である。
ランナーごとの違いは、その後の仕事の量にある。

| ランナー | 準備とビルドの後の仕事 | 秒 |
|---|---|---|
| `x-tests` | `cabal test all` | 75〜131 |
| `arm-all` | `cabal test all`、決定性の検査の出力 | 80〜87、23〜24 |
| `x-outputs` | epubcheck の二回、決定性の検査の出力、`visual-pdfs`、成果物の上げ | 8〜13、14〜24、32〜54、約 7 |
| `x-env` | 環境を変える検査（プルリクエストは `--quick`） | 10〜14 |

### cabal test all の中身

`x-tests` の `cabal test all` は、x86-64 のランナーによって 75 秒前後と 125 秒前後に分かれる。
遅い実行では、すべてのスイートがほぼ同じ比で遅い（`golem-svg-test` が 12 秒と 22 秒、`golem-pdf-test` が 43 秒と 84 秒）。
同じ実行の `x-outputs` の `visual-pdfs` も 33 秒前後と 50 秒前後に分かれるので、ランナーに割り当てられたマシンの違いと見られる。
aarch64 の `cabal test all` は 80 秒から 87 秒で、揺れが小さい。

遅い実行（ジョブ [126429019179](https://github.com/tett23/golem/actions/runs/41786252402/job/126429019179)）の、各スイートが終わった時刻は次のとおりである。
`cabal test all` の手順は 06:34:08 に始まった。

| スイート | 始まり | 終わり | tasty の報告 |
|---|---|---|---|
| `golem-driver-test` | 06:34:12 | 06:36:14 | 121.77 秒 |
| `golem-pdf-test` | 06:34:43 | 06:36:07 | 84.18 秒 |
| `golem-parser-test` | 06:34:43 | 06:35:49 | 66.09 秒 |
| `golem-driver-parallel-test` | 06:34:11 | 06:34:40 | 28.96 秒 |
| `golem-svg-test` | 06:35:10 | 06:35:26 | 22.20 秒 |

`golem-driver-test` は最初に始まり、最後に終わる。
その 122 秒のあいだ、4 コアのランナーで `golem-parser-test`（`-N`）、`golem-pdf-test`、`golem-svg-test` などが同時に走る。
`golem-pdf-test` と `golem-svg-test` は `-threaded` を持たず、テストを一つずつ実行する。
`cabal test` はすでにスイートをコアの数だけ並べている（[ADR 0037](0037-ci-build-job-speedup.md)）。
そのため、一つのランナーの中では、これ以上縮める余地がない。

### 前の ADR が退けたこと

この ADR が変える形は、前の ADR が退けている。
退けた理由は、その時点の臨界経路にあった。

- [ADR 0045](0045-split-x86-build-and-pull-request-cache.md) は、aarch64 の `build` を二つに分けることを退けた。aarch64 は x86-64 より短く終わり、臨界経路になかったからである。今の `arm-all` は、最後に終わる `x-tests` の 10 秒から 25 秒後ろにいる。
- [ADR 0097](0097-ci-same-path-before-build-and-env-check-runner.md) は、テストのスイートを複数のランナーに分けることを退けた。分けても、`build` の行列のすべてを待つ `visual`（約 210 秒）が残るからである。[ADR 0099](0099-visual-job-waits-only-for-visual-pdfs.md) の後、`visual` は `x-outputs` の 10 秒ほど後に終わる。
- [ADR 0095](0095-visual-job-in-ci.md) は、`visual-pdfs` を `scripts/determinism.sh` の後に組むと決めた。組む場所としてそろっているものを挙げた決定で、順序が要る理由は書いていない。`scripts/visual/build.sh` は入力を一時ディレクトリに写して組み、マニュアルのフォントも自分で取る（[build.sh](https://github.com/tett23/golem/blob/2511d517ac2b2d09b352f6d3ca0a429275ab31d1/scripts/visual/build.sh#L1-L20)）。決定性の検査の出力にも、epubcheck の結果にも依らない。

## 実装すること

テストを先に書き、今の `ci.yml` で失敗することを確かめる。

### x86-64 のテストを二つのランナーに分ける

- `scripts/ci/test-suites.sh PART` を足す。`modules/*/*.cabal` の `test-suite` を読み、`cabal test` に渡すターゲット（`パッケージ:test:スイート`）を一行に一つ書く。`PART` が `driver` なら golem-driver のスイートを、`rest` ならそれ以外のすべてのスイートを書く。どのスイートも、ちょうど一方に入る。新しいスイートは `rest` に入るので、一覧を手で保つ必要はない。
- `build` の行列の x86-64 の `tests` を、`tests-driver` と `tests-rest` の二つにする。どちらも `tests: true` とし、行列に `suites`（`driver` か `rest`）を足す。
- `cabal test all` の手順を、`cabal test $(sh scripts/ci/test-suites.sh "$SUITES")` にする。環境変数（`GOLEM_REQUIRE_EXTERNAL_TOOLS`、`GOLEM_PD_BOOKS`、`TASTY_NO_CREATE`）と時間の上限は変えない。
- どちらのランナーも、今と同じく `cabal build all peg-cli:exe:peg-hs` を実行する。ビルドの計画と `PATH` は、ほかのランナーと同じになる（[ADR 0097](0097-ci-same-path-before-build-and-env-check-runner.md)）。
- qpdf と cddl の CLI は、`tests: true` の二つのランナーが入れる。生成したパーサーの検査は `tests-rest` だけが行う。

### aarch64 をテストと出力の二つのランナーに分ける

- 行列の `ubuntu-24.04-arm` の `all` を、`tests`（`tests: true`、`outputs: false`、`suites: all`）と `outputs`（`tests: false`、`outputs: true`）の二つにする。
- aarch64 の `tests` は、今と同じくすべてのスイートを実行する。`suites` が `all` のときは `cabal test all` とする。
- 成果物 `determinism-ubuntu-24.04-arm` は aarch64 の `outputs` が上げる。名前は変えないので、`determinism` ジョブは変えない。

### dist-newstyle を保存するランナー

- 行列に `save`（真偽値）を足し、x86-64 の `tests-driver` と aarch64 の `tests` だけを `true` にする。
- `main` への push の保存と、プルリクエストの保存（[ADR 0045](0045-split-x86-build-and-pull-request-cache.md)）の条件の `matrix.tests` を `matrix.save` に替える。テストを実行するランナーが二つになっても、一つのアーキテクチャで保存するのは一つのランナーである。

### visual-pdfs を先に組む

- x86-64 の `outputs` で、「The PDFs of the visual regression test」と「Upload the PDFs of the visual regression test」を、「Cache the fonts of the manuals」の直後、epubcheck の二つの手順より前に移す（今は決定性の検査の出力の後にある、[ci.yml](https://github.com/tett23/golem/blob/2511d517ac2b2d09b352f6d3ca0a429275ab31d1/.github/workflows/ci.yml#L289-L335)）。
- 手順の中身、`visual` ジョブ、`wait-pdfs.sh` は変えない。

### 判定と文書

- `ci` の `needs` と `scripts/ci/gate.sh` は変えない。行列のランナーが増えても、`build` は一つのジョブである。
- `scripts/visual/wait-pdfs.sh` が待つジョブの名前（`build (ubuntu-24.04, outputs)`）は変えない。
- README の CI の表の `build` の行と、開発者のマニュアルの「CI のジョブ」の章を直す。
- 計測の結果を `docs/ci-timings/` に記録する。

## 実装しないこと

- **テストのスイートの中身を分けること。** `golem-driver-test` を二つのスイートにすれば、もっと細かく釣り合わせられる。モジュールのテストの変更であり、golem-driver の ADR で扱う。
- **テストの RTS の設定（並列 GC など）を変えること。** 同時に走るスイートの GC の取り合いが遅さの一因である可能性はあるが、計測していない。`.cabal` の `ghc-options` を変える変更になり、[ADR 0050](0050-run-golem-on-every-processor.md) の capability の扱いにも関わる。
- **プルリクエストでだけ、テストの一部を `env` のランナーに載せること。** `env` はプルリクエストでは 90 秒ほどで終わり、余っている。しかし `main` への push では最も長いランナーの一つであり、イベントによって受け持ちを変えると、[ADR 0097](0097-ci-same-path-before-build-and-env-check-runner.md) が退けたとおり条件が複雑になる。
- **`main` への push の環境を変える検査（約 130 秒）を分けること。** `main` への push では `x-env` が最後に終わることが多く、この ADR の後も残る。プルリクエストの時間を縮めないので、ここでは扱わない。
- **`determinism` を `visual` と同じく成果物を待つ形にすること。** `build` の後の約 15 秒のうち 7 秒ほどを縮められるが、別の ADR で扱う。

## テスト設計

### 先に書いて失敗させるテスト

`scripts/ci/test.sh` に次の項目を足す。

- `test-suites.sh` が、偽の `modules/` の木で、`driver` に golem-driver のスイートだけを、`rest` にそれ以外のすべてを書くこと。二つの出力に重なりがなく、合わせると `test-suite` のすべてになること。
- `test-suites.sh` が、実際の `modules/` で同じ性質を満たすこと。
- `test-suites.sh` が、引数がないか未知の `PART` で終了コード 2 で終わること。
- `build` の行列が、`ubuntu-24.04` の `tests-driver`、`tests-rest`、`outputs`、`env` と、`ubuntu-24.04-arm` の `tests`、`outputs` を持ち、各行の `tests`、`outputs`、`env`、`suites`、`save` が上のとおりであること。
- 二つの `Save dist-newstyle` の条件が `matrix.save` を含み、`matrix.tests` を含まないこと。
- 「Generated parser matches the grammar」の条件が、`tests-rest` と aarch64 の `tests` で真になること。
- x86-64 の `outputs` で、`visual-pdfs` を組む手順と上げる手順が、epubcheck と決定性の検査の出力の手順より前にあること。

### 自動テストにできないものの確かめ方

下書きのプルリクエストで、次を確かめて記録する。

- 各テストのランナーのログで、`cabal test` が実行したスイートの和が、今の `cabal test all` のスイートと一致すること。
- `determinism` と `visual` が通ること。
- 実行全体と各ジョブの時間を、変更の前後で 3 回ずつ取る。

## トレードオフ

- 一回の実行で使うランナーが二つ増え、`build` の行列は六つになる。同時に動くジョブは、`ci.yml` の一回で最大 12 になる。GitHub の無料のプランの同時実行の枠（20）を、二つのプルリクエストが同時に走ると超え、待ちが出る。
- キャッシュの復元が二回分増える。一回の実行で、x86-64 で約 960 MB、aarch64 で約 1.2 GB を余分に取り寄せる。
- 準備とビルドに 50 秒から 70 秒を払って、テストを 40 秒から 60 秒縮める。モジュールを変えて `cabal build` が長いときも、縮む秒数はほぼ同じである。ビルドの時間はどのランナーにも同じだけかかり、分けても縮まないからである。
- 見積もりは次のとおりである。`tests-driver` は `golem-driver-test` だけが CPU を使えるので、今の 75 秒から 125 秒より短くなる見込みである。`tests-rest` は、一つずつ実行する `golem-pdf-test`（43 秒から 84 秒）より短くはならない。aarch64 の `tests` は今の `arm-all` から決定性の検査の出力（約 24 秒）と成果物の上げが抜ける。`visual` は epubcheck と決定性の検査の出力（25 秒から 37 秒）の分だけ早く終わる。モジュールを変えないプルリクエストで、最後のランナーの終わりが今の約 210 秒から 170 秒前後になると見込む。この数字は下書きのプルリクエストで確かめる。
- `main` への push では、`x-env` が残るので、縮む秒数はプルリクエストより小さい。

## 決めたことの記録

- **ランナーを二つ増やすこと**：メンテナーが認めた（2026-11-04）。
- **[docs/adr/0045](0045-split-x86-build-and-pull-request-cache.md)、[docs/adr/0097](0097-ci-same-path-before-build-and-env-check-runner.md)、[docs/adr/0095](0095-visual-job-in-ci.md) の判断を覆すこと**：メンテナーが、三つとも覆してよいと決めた（2026-11-04）。
- **main への push の環境の検査**：この ADR の範囲から外すことを、メンテナーが認めた（2026-11-04）。

## 参考文献

- [ci.yml（今の build と visual）](https://github.com/tett23/golem/blob/2511d517ac2b2d09b352f6d3ca0a429275ab31d1/.github/workflows/ci.yml#L105-L404)
- [scripts/visual/build.sh](https://github.com/tett23/golem/blob/2511d517ac2b2d09b352f6d3ca0a429275ab31d1/scripts/visual/build.sh)
- [scripts/determinism.sh](https://github.com/tett23/golem/blob/2511d517ac2b2d09b352f6d3ca0a429275ab31d1/scripts/determinism.sh)
- GitHub Docs, "Usage limits, billing, and administration"（同時に動くジョブの数の上限）. https://docs.github.com/en/actions/administering-github-actions/usage-limits-billing-and-administration
- [ADR 0037](0037-ci-build-job-speedup.md)、[ADR 0045](0045-split-x86-build-and-pull-request-cache.md)、[ADR 0050](0050-run-golem-on-every-processor.md)、[ADR 0095](0095-visual-job-in-ci.md)、[ADR 0097](0097-ci-same-path-before-build-and-env-check-runner.md)、[ADR 0099](0099-visual-job-waits-only-for-visual-pdfs.md)
- 計測のデータ：上の表の 10 回の実行（2026-11-04）
