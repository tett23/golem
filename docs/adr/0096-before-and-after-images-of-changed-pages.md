# ADR 0096: 見た目の回帰テストで変わったページの前後の画像と差分の画像を、CI の成果物と要約にする

ステータス: 採択

## 文脈

[ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md) は、ページの SHA-256 の一覧をコミットして参照にすると決めた。
一覧は、どのページの画素が変わったかを示すが、どう変わったかは示さない。
意図して見た目を変えるプルリクエストでも、意図せず崩したプルリクエストでも、レビューする人は変わったページの前と後を並べて見る必要がある。

shem v0.1.0-rc2 は、二つの画像の差分を描く `shem diff` を持つ（[shem ADR 0010](https://github.com/tett23/shem/blob/152858295b7949514e05d0ae009e858a1262dfa0/docs/adr/0010-diff-images.md)、[shem の仕様書の「差分の画像」](https://github.com/tett23/shem/blob/152858295b7949514e05d0ae009e858a1262dfa0/docs/specifications.md#L44-L54)）。
二つのディレクトリの画像を名前で対応させて比べ、違う組ごとに、違う画素に色を付けた画像を書く。
標準出力には `differ: <名前>: <違う画素の数> pixels in <x0> <y0> <x1> <y1>`（違う画素を囲む矩形）、`added: <名前>`、`removed: <名前>` を名前の順に書く。
終了コードは、違いがなければ 0、あれば 1、読めなければ 2 である。
Golem は [ADR 0093](0093-fetch-shem-pinned-by-version-and-sha256.md) で rc2 を固定するので、この機能をそのまま使える。

違う画素の数は、変化が目に見えるかどうかを示さない。
[ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md) の測定で、『テンペスト』の本文を 0.001mm ずらすと、72 dpi で違う画素がページごとに 3,221 以上あった。
人の目で見分けられないずれでも、字の縁のアンチエイリアスの画素がまとめて変わるからである。

### 前の画像をどこから得るか

「前」は、プルリクエストのベースのコミット（`main` への push では push の前のコミット）の出力である。
参照の一覧はハッシュだけなので、前の画像を描くには、ベースのコミットの PDF が要る。
ベースの golem をビルドして組み直すのは、[ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md) で退けた。

[ADR 0095](0095-visual-job-in-ci.md) で、どの実行も成果物 `visual-pdfs` を上げることにした。
成果物は実行に属するので、ベースのコミットの `ci.yml` の実行を `gh run list --commit` で探せば、そのコミットの PDF が得られる。
成果物は、リポジトリの設定の日数（既定は 90 日）残る。
`actions/cache` はキーで引くもので、あるコミットの PDF を引くにはコミットをキーに入れて別に保存する必要がある。
すでに上げている成果物を使うほうが、仕組みが一つ少ない。

別の実行の成果物を取り寄せるには、トークンに `actions: read` の権限が要る。
`ci.yml` の権限は、ワークフロー全体で `contents: read` だけにしている（[ADR 0035](0035-security-hardening.md)）。
`race.yml` は `actions: read` を持つ（[race.yml](https://github.com/tett23/golem/blob/ee7cf504744c48390908701277ae9fcfcdc85d2b/.github/workflows/race.yml#L15-L17)）。

ベースのコミットに成果物がないこともある。
文書だけを変えたコミットでは `build` が省かれるので（[ADR 0009](0009-ci-speed.md)）、`visual-pdfs` が上がらない。
成果物の日数を過ぎたコミットも同じである。

## 実装すること

### 報告を作る条件

- [ADR 0095](0095-visual-job-in-ci.md) の `visual` ジョブで、比べる手順が失敗したときだけ、`scripts/visual/report.sh` を動かす。比べる手順が通れば、報告は作らない。
- 前の画像のベースは、プルリクエストでは `github.event.pull_request.base.sha`、`main` への push では `github.event.before` とする。`changes` ジョブがビルドの要否を決めるときと同じ値である。`release.yml` から呼ばれたときはベースがないので、前の画像を探さず、後の画像と変わったページの一覧だけを報告する。

### 前の PDF を探す

- `visual` ジョブの権限に `actions: read` を足す。ワークフロー全体の権限は `contents: read` のままとし、ほかのジョブには足さない。
- ベースのコミットから first-parent の祖先を 20 個までたどり、`ci.yml` の `push` の実行で `visual-pdfs` を持つ最初のコミットの成果物を、`gh run list` と `gh run download` で取り寄せる。チェックアウトは `fetch-depth: 0` とする。
- 取り寄せた PDF のページは、ベースのコミットの参照（`git show <ベース>:scripts/visual/pages/<入力>.txt`）と照らしてから使う。変わったページを 72 dpi の PPM に描き、その SHA-256 がベースの参照の行と一致したときだけ、そのページの前の画像とする。祖先の PDF でも、ベースと同じ画素のページなら前の画像として正しい。一致しないページと、見つからなかったページは、「前の画像なし」と報告する。
- `gh` の失敗、成果物の取り寄せの失敗、20 個の祖先に成果物がないことは、報告に書くだけで、ジョブの結果を変えない。ジョブは比べる手順の失敗で、すでに失敗している。

### 要約

- 前の画像のあるページについて、前と後の 72 dpi の PPM を入力ごとのディレクトリに置き、`shem diff --format ppm` で比べる。違う画素の数と矩形は、その標準出力から取る。比べるのは参照と同じ 72 dpi の画素である。
- `GITHUB_STEP_SUMMARY` に、次の表を書く。行の順は入力の名前とページの順とする。
  - `unreadable` の入力と shem のエラー（[ADR 0095](0095-visual-job-in-ci.md)）。
  - 変わったページ：入力、ページ、種類（`changed`、`added`、`removed`）、違う画素の数、違う画素を囲む矩形。前の画像がないページは、数の欄に「前の画像なし」と書く。
  - `unlisted` と `stale` の入力。
- 要約の表は、変わったページが 500 を超えたら、入力ごとの変わったページの数と、違う画素の数の最大だけにする。要約の大きさの上限（一つの手順に 1 MiB）に収めるためである。

### 成果物

- 成果物 `visual-diff` を上げる。中身は次のとおりとする。
  - `after/<入力>/page-<番号>.png`：後の画像。
  - `before/<入力>/page-<番号>.png`：前の画像。前の画像のあるページだけ。
  - `diff/<入力>/page-<番号>.png`：`shem diff` で `before` と `after` を比べた差分の画像。違う画素に色を付け、違う範囲を枠で囲んだもの。
  - `pages/<入力>.txt`：このコミットの PDF から作った参照の一覧。`check.sh --accept` が書くものと同じである。
  - `summary.md`：要約と同じ表。
- 画像は shem の `--format png --dpi 150` で、変わったページだけを `--pages` で描く。72 dpi は比べるための解像度で、和文の本文を目で読むには粗いからである。差分の画像も、この 150 dpi の二枚から作る。
- 画像を描くのは、入力の名前とページの順で最初の 100 ページまでとする。rc1 の 150 dpi の PNG は一ページ平均 182.1 KB だったので（[ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md) の測定）、前と後で約 37 MB になり、差分の画像がこれに加わる。100 を超えた分は、要約に数だけを書く。
- `pages/` の一覧を写せば、手元で `--accept` したのと同じ参照になる。ただし、受け入れは画像を見てから行う。開発者のマニュアルにそう書く。

### 文書

- 開発者のマニュアルの「CI のジョブ」の章の `visual` の節（[ADR 0095](0095-visual-job-in-ci.md)）に、要約の表、成果物の中身、前の画像を探す手順、前の画像がない場合を書く。
- 開発者のマニュアルの「決定性を守る」の章の「見た目の回帰テスト」の節に、変わったページの見方として、差分の画像と前後の画像を書く。違う画素の数は、目に見えない 0.001mm のずれでも数千になるので、見えるかどうかの判断には使えず、差分の画像の色の付き方と前後の画像を見て決めることも書く。
- README の CI の表の `visual` の行に、失敗したときに要約と成果物 `visual-diff` を作ることを書く。

## 実装しないこと

- Golem の側で差分の画像を作ること。shem の `shem diff` を使う。ImageMagick などの道具を CI に足すこともしない。
- 比べる手順が通ったときの報告。変わったページがないので、見るものがない。
- ベースのコミットの golem をビルドして前の PDF を作ること（[ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md)）。
- `actions/cache` に PDF や画像を置くこと。
- 成果物の日数を変えること。90 日を過ぎたベースでは、前の画像がないと報告する。
- プルリクエストへのコメント。トークンに書き込みの権限が要る。
- 差の量で合否を決めること。合否は [ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md) の完全な一致で決め、差の量は人が見るための手がかりにとどめる。

## テスト設計

テストを先に書き、今の実装で失敗することを確かめる。

`scripts/visual/test.sh` に、次を置く。
`gh` と shem は、`PATH` の先頭に置いた偽物で動かす。
偽の `gh` は、テストが決めたコミットに成果物があるように振る舞い、呼ばれた引数を記録する。
偽の shem は、`render` では決まった画像を書き、`diff` ではテストが決めた `differ:` の行を出して終了コード 1 で終わる。

- ベースのコミットに成果物があれば、そのコミットの成果物を取り寄せること。
- ベースになく、二つ前の祖先にあれば、その祖先の成果物を取り寄せること。20 個の祖先のどれにもなければ、要約に「前の画像なし」が書かれ、`report.sh` が終了コード 0 で終わること。
- 取り寄せたページの SHA-256 がベースの参照と違えば、そのページを前の画像に使わず、`diff` を呼ばないこと。
- 偽の shem の `diff` が出した違う画素の数と矩形が、要約の表に写されること。偽の shem の `diff` が終了コード 2 で終われば、そのページの欄にエラーが書かれ、`report.sh` が終了コード 0 で終わること。
- 変わったページが 101 あれば、画像が 100 ページ分だけ描かれ、要約に残りの数が書かれること。
- 変わったページが 501 あれば、要約が入力ごとの表になること。
- `pages/` の一覧が、同じ PDF に `check.sh --accept` を当てた結果と同じであること。
- ベースがない（`release.yml` から呼ばれた）とき、`gh` が呼ばれないこと。

`scripts/ci/test.sh` に、次を確かめる項目を足す。

- `visual` ジョブだけが `actions: read` を持ち、ワークフロー全体の `permissions` は `contents: read` のままであること。
- `scripts/visual/report.sh` の手順が、比べる手順の失敗のときだけ動き、`visual-diff` を上げること。

実装のプルリクエストで、『テンペスト』の `top` を 0.001mm 変えた捨てるコミットを push し、要約の表と `visual-diff` の前後の画像と差分の画像を確かめて、結果をプルリクエストに書く。
確かめた後にそのコミットを消す。

## トレードオフ

- `visual` ジョブのトークンが `actions: read` を持つ。読めるのは、公開されたリポジトリの実行の記録と成果物で、ほかの人も読めるものである。プルリクエストのコードがこのジョブで動くので、権限はこのジョブだけに足す。
- 前の画像は、ベースか、その 20 個までの祖先の成果物があるときにしか得られない。照らし合わせで正しさは保てるが、得られる範囲は成果物の残り方に左右される。
- 失敗したプルリクエストのたびに、約 17 MB の PDF を取り寄せ、変わったページを二回描く（照らし合わせの 72 dpi と、画像の 150 dpi）。比べる手順が通ったときにはかからない。
- 違う画素の数は、変化が目に見えるかを決めない。目に見えないずれでも数千になる。数は、どのページから見るかを決める手がかりにとどまる。
- 画像を 100 ページで打ち切るので、すべてのページが変わる変更（丸めの変更、shem の版の上げ）では、101 ページめ以降を手元で描いて見る必要がある。
- 差分の画像の形（色、枠）は shem が決める。shem の版を上げると変わりうるが、合否には関わらない。

## 参考文献

- [ADR 0009](0009-ci-speed.md)
- [ADR 0035](0035-security-hardening.md)
- [ADR 0093](0093-fetch-shem-pinned-by-version-and-sha256.md)
- [ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md)
- [ADR 0095](0095-visual-job-in-ci.md)
- [shem ADR 0010「画像の差分の画像を出す（ファイルどうしとディレクトリどうし）」](https://github.com/tett23/shem/blob/152858295b7949514e05d0ae009e858a1262dfa0/docs/adr/0010-diff-images.md)
- shem の仕様書 https://github.com/tett23/shem/blob/152858295b7949514e05d0ae009e858a1262dfa0/docs/specifications.md
- GitHub Docs「Store and share data with workflow artifacts」https://docs.github.com/en/actions/tutorials/store-and-share-data
- GitHub Docs「Workflow commands for GitHub Actions」の Adding a job summary https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands#adding-a-job-summary
