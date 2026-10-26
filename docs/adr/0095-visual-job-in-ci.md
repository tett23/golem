# ADR 0095: 見た目の回帰テストを、CI の新しいジョブ visual で動かす

ステータス: 採択（未実装）

## 文脈

[ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md) は、17 の入力の PDF を shem で 72 dpi の PPM に描き、ページごとの SHA-256 をコミットした一覧と比べると決めた。
[ADR 0093](0093-fetch-shem-pinned-by-version-and-sha256.md) は、shem を版と SHA-256 で固定して取ると決めた。
この ADR は、これを CI のどこで動かすかと、時間の上限を決める。

### 今の CI の形

`ci.yml` の `build` ジョブは、三つのランナーで動く（[ci.yml](https://github.com/tett23/golem/blob/ee7cf504744c48390908701277ae9fcfcdc85d2b/.github/workflows/ci.yml#L92-L118)、[ADR 0045](0045-split-x86-build-and-pull-request-cache.md)）。
x86-64 の `tests` はテストを受け持つ。
x86-64 の `outputs` は、決定性の検査の出力（`scripts/determinism.sh`、二つのマニュアルを含む）、epubcheck、環境を変える検査、マニュアルの成果物を受け持つ。
aarch64 の `all` は両方を受け持つ。

`build` の後には、`determinism` ジョブが動く。
このジョブはチェックアウトをせず、`build` が上げた成果物（二つのアーキテクチャの `scripts/determinism.sh` の出力）を取り寄せて `diff` で比べる。
出力を `build` で作り、比べるのを後のジョブで行う形は、すでにこのジョブで使っている。

`ci` ジョブは、`ci.yml` のほかのジョブの結果を `scripts/ci/gate.sh` でまとめて判定する。
ジョブを足すときは、`ci` の `needs` と `gate.sh` の `NAMES` の両方に加える（[ADR 0021](0021-docs-workflow-and-ci-gate.md)、[gate.sh](https://github.com/tett23/golem/blob/ee7cf504744c48390908701277ae9fcfcdc85d2b/scripts/ci/gate.sh#L14)）。
`scripts/` の下のスクリプトのテストは、`changes` ジョブと、BSD 版の道具で動かす `scripts-macos` ジョブの両方で走る（[ADR 0079](0079-shell-tests-on-macos.md)）。

直近の `main` の実行（40329004293、2026-10-26）では、`outputs` が `build` の中で最も遅く（6 分 25 秒）、`determinism` は 35 秒だった。
`outputs` の中で `scripts/determinism.sh` は 14 秒だった。

### 時間の上限の考え方

[ADR 0091](0091-cpu-time-limits-in-pdf-and-svg-tests.md) は、時間の上限を止まらないことの検出にだけ使い、正しい処理が負荷だけで届かないように、測った値から十分に離して置くと決めた。
上限に収まったことは、速いことを意味しない。

[ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md) の測定では、17 の PDF（1,779 ページ）を shem v0.1.0-rc2 で 72 dpi の PPM に描いてハッシュを取るのに、`--jobs 1` で約 38.5 秒、`--jobs 4` で約 15.6 秒かかった。
同じマシンで、17 の入力を組むのに約 40 秒（1 秒単位の計で、マニュアルのフォントの取得を含む）かかった。
測ったのは負荷のある Apple silicon の macOS で、CI の x86-64 のランナーでは測っていない。

## 実装すること

### 入力の PDF を組む場所と、描く場所

- x86-64 の `outputs` のランナーで、`scripts/determinism.sh` の後に `scripts/visual/build.sh` を動かし、17 の PDF を成果物 `visual-pdfs` として上げる。`outputs` は、golem をビルドし、マニュアルのフォントのキャッシュを戻し、ほかの出力を作るランナーなので、PDF を組むのに要るものがそろっている。
- 描いて比べるのは、新しい `visual` ジョブとする。`visual` は `visual-pdfs` を取り寄せて比べる。`determinism` ジョブと同じく、`build` が作った出力を後のジョブが受け取る形にする。
- 組むのも描くのも x86-64 で行う。ランナーの組み合わせを最も少なくするためである。
- `visual-pdfs` を組むと、`outputs` の時間が延び、CI の全体の時間もその分だけ延びる。手元では約 40 秒だった。速くする工夫（組む場所を余りのあるランナーに移すなど）は、必要になったときに別の ADR で考える。

### visual ジョブ

- `ci.yml` に `visual` ジョブを足す。`needs: build` とし、`build` と同じく、ビルドの要らない変更（`changes` の判定）では省く。
- ランナーは `ubuntu-24.04`（x86-64）とする。shem はページを `--jobs` で並べて描き、既定でランナーのすべてのコアを使う。
- 手順は次のとおりとする。
  1. チェックアウトする。
  2. shem を [ADR 0093](0093-fetch-shem-pinned-by-version-and-sha256.md) のとおり、キャッシュから戻すか取る。
  3. 成果物 `visual-pdfs` を取り寄せる。
  4. `timeout -k 10 600 sh scripts/visual/check.sh visual-pdfs` で比べる。
  5. 比べる手順が失敗したときだけ、[ADR 0096](0096-before-and-after-images-of-changed-pages.md) の報告を作る。
- ジョブの `timeout-minutes` は 15 とする。
- `gate.sh` の `NAMES` と、`ci` ジョブの `needs` に `visual` を加える。
- `release.yml` は `ci.yml` を呼ぶので、リリースの前にも `visual` が動く。リリースのワークフローには手を加えない。

### determinism ジョブと分ける理由

- `determinism` ジョブには加えない。`determinism` は同じコミットの二つのアーキテクチャの出力を比べ、`visual` はコミットした参照と比べる。比べる相手が違い、失敗したときの直し方も違う（`determinism` の失敗は決定性の誤りで、`visual` の失敗は参照の受け入れか、組版の誤りか、shem の版の問題である）。ジョブを分ければ、`ci` の判定の一覧から、どちらが落ちたかがわかる。
- `determinism` はチェックアウトもしないジョブで、shem の取得もキャッシュも要らない。混ぜると、二つのテキストの比較が shem の取得の失敗で落ちうる。
- `outputs` のランナーの手順として描かない理由は、[ADR 0096](0096-before-and-after-images-of-changed-pages.md) の報告が `actions: read` の権限を要るからである。権限はジョブの単位で付くので、`build` に付けると、テストを動かす三つのランナーすべてに付く。

### 時間の上限

- 比べる手順の上限は、実時間の 600 秒とする（`timeout -k 10 600`）。手元の rc2 の `--jobs 1` の約 38.5 秒の約 15 倍、`--jobs 4` の約 15.6 秒の約 38 倍である。CI のランナーが手元の数倍遅くても、正しい処理は届かない。上限に届くのは、shem が止まらなくなったときである。
- 上限で止まると、`timeout` が終了コード 124 で終わり、手順が失敗する。そのときどの PDF を描いていたかがわかるように、`check.sh` は描き始める PDF の名前を標準エラーに書く。
- 予算は、比べる手順の実時間で 2 分とする。上限ではなく、見直しの目安である。CI の実行でこれを超えるようになったら、入力の数か解像度を見直す。予算を超えてもジョブは失敗させない。
- 実装のプルリクエストで、CI の `visual` ジョブの各手順の時間と、`outputs` のランナーで `build.sh` にかかった時間を記録し、`docs/ci-timings/` に置く。

### shem のエラー

- `check.sh` が `unreadable` を出したら、ジョブは失敗する（[ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md)）。Golem の Writer が shem の読む部分集合の外を書いたことを意味するので、Golem の側で参照を書き直しても通らない。shem を先に直してリリースし、固定した版を上げる（[ADR 0093](0093-fetch-shem-pinned-by-version-and-sha256.md)）。
- ジョブの要約（`GITHUB_STEP_SUMMARY`）の先頭に、`unreadable` の入力と shem のエラーの行を、参照の不一致とは別の表として書く。

### スクリプトのテスト

- `scripts/visual/test.sh` を、`changes` ジョブと `scripts-macos` ジョブの両方で動かす。`scripts-macos` が動かすテストは五本から六本になる。

### 文書

- README の CI の表に `visual` の行を足し、`build` の行に `outputs` のランナーが `visual-pdfs` を上げることを、`changes` と `scripts-macos` の行に `scripts/visual/test.sh` を足す。
- 開発者のマニュアルの「CI のジョブ」の章（`manual-dev/part2/11-ci-jobs.gm`）の、`ci.yml` のジョブの一覧（七つから八つ）と `ci` の節の `needs` の列挙に `visual` を足し、`visual` の節を置く。`scripts-macos` の五本のテストの列挙も直す。
- CONTRIBUTING.md の `scripts-macos` の「五本のテスト」を六本に直す。

## 実装しないこと

- aarch64 でも組んで描くこと。shem の決定性は shem の CI が確かめており、Golem の出力のアーキテクチャによる違いは `determinism` ジョブが受け持つ。参照の一致は一つのアーキテクチャで足りる。
- 組む場所と描く場所を、別のアーキテクチャのランナーに分けること。
- 速くするためにランナーを増やすことや、組む手順を別のランナーに移すこと。必要になるまで行わない。
- 時間の上限を CPU 時間で測ること。[ADR 0091](0091-cpu-time-limits-in-pdf-and-svg-tests.md) が CPU 時間にしたのは、tasty のテストがほかのスイートと CPU を取り合うからである。`visual` のランナーでは、比べる手順のほかに CPU を使うものがない。
- 予算を超えたら失敗させること。予算は見直しの目安であり、負荷で揺れる実時間でジョブを落とさない。
- `release.yml` に `visual` の結果を別に確かめるジョブを足すこと。`ci.yml` の `ci` の判定に含まれる。

## テスト設計

テストを先に書き、今の実装で失敗することを確かめる。

- `scripts/ci/test.sh` に、次を確かめる項目を足す（今の `step_if` と同じ形）。
  - `ci.yml` に `visual` ジョブがあり、`needs` に `build` を持ち、`changes` の判定で省かれること。
  - `visual` が `scripts/visual/check.sh` を `timeout -k 10 600` の下で動かすこと。
  - x86-64 の `outputs` のランナーだけが `scripts/visual/build.sh` を動かし、`visual-pdfs` を上げること。
  - `changes` と `scripts-macos` が `scripts/visual/test.sh` を動かすこと。
- `scripts/ci/test.sh` の `gate.sh` の項目に、`visual` が `NAMES` にあり、`ci` ジョブの `needs` と `gate.sh --names` が一致することを足す。一致の項目がすでにあれば、`visual` を足しても通ることを確かめる。
- 実装のプルリクエストで、次を CI で確かめる。
  - 参照を変えないコミットで `visual` が通ること。
  - 参照の一行を書き換えた捨てるコミットで `visual` が `changed` で落ち、`ci` が失敗すること。確かめた後にそのコミットを消す。
  - 上の時間の記録。

## トレードオフ

- `outputs` で PDF を組む分と、`visual` が `determinism` より長い分だけ、CI の全体の時間が延びる。`visual` は、ランナーの起動、shem の取得、約 17 MB の成果物の取り寄せ、描画の時間がかかる。CI では測っていない。
- PDF を組むジョブと描くジョブが分かれるので、成果物を一つ受け渡す。`determinism` と同じ形なので、仕組みは増えない。
- 600 秒の上限は、shem が止まらなくなったときに失敗までを 10 分待たせる。ジョブの `timeout-minutes` の 15 分より先に働くので、どの手順で止まったかはわかる。
- 実時間の予算は負荷で揺れるので、超えたかどうかは複数の実行で判断する。

## 参考文献

- [ADR 0021](0021-docs-workflow-and-ci-gate.md)
- [ADR 0045](0045-split-x86-build-and-pull-request-cache.md)
- [ADR 0079](0079-shell-tests-on-macos.md)
- [ADR 0091](0091-cpu-time-limits-in-pdf-and-svg-tests.md)
- [ADR 0093](0093-fetch-shem-pinned-by-version-and-sha256.md)
- [ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md)
- [ADR 0096](0096-before-and-after-images-of-changed-pages.md)
- Golem の ci.yml https://github.com/tett23/golem/blob/ee7cf504744c48390908701277ae9fcfcdc85d2b/.github/workflows/ci.yml
- Golem の CI の実行 40329004293 https://github.com/tett23/golem/actions/runs/40329004293
