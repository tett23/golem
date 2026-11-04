# ADR 0165: wait-pdfs.sh は、呼び出し元の接頭辞のついたジョブの名前でも待つジョブを見つける

ステータス: 採択

## 文脈

[ADR 0099](0099-visual-job-waits-only-for-visual-pdfs.md) は、`visual` ジョブが `build` の行列の全体ではなく、成果物 `visual-pdfs` だけを待つと決めた。
待つあいだ、`scripts/visual/wait-pdfs.sh` は、`visual-pdfs` を上げるジョブを名前 `build (ubuntu-24.04, outputs)` で探し、そのジョブが成果物なしで終わったら失敗する。
名前は、実行の試行のジョブの一覧から、`.name` が引数と一致するものを選んで探す（[wait-pdfs.sh の該当行](https://github.com/tett23/golem/blob/2a743e8041fbd7c4810cf9352aa5d43db0a5254d/scripts/visual/wait-pdfs.sh#L27)）。

`release.yml` は、ジョブ `ci` で `ci.yml` を `workflow_call` で呼ぶ（[release.yml の ci ジョブ](https://github.com/tett23/golem/blob/2a743e8041fbd7c4810cf9352aa5d43db0a5254d/.github/workflows/release.yml#L27-L28)）。
呼ばれたワークフローのジョブは、API の上で、呼び出し元のジョブの名前と ` / ` を前につけた名前になる。
`release.yml` の中では、待つべきジョブは `ci / build (ubuntu-24.04, outputs)` であり、`build (ubuntu-24.04, outputs)` という名前のジョブはない。

### release.yml が通らないこと

`release.yml` を `workflow_dispatch` で動かした実行 41918079466（2026-11-04、#547 のブランチ）で、これが起きた。
`ci / build (ubuntu-24.04, outputs)` は 8 分 27 秒で成功し、`visual-pdfs` を上げた。
一方 `ci / visual` は、待ち始めて 2 秒で次を書いて失敗した。

```
wait-pdfs: the attempt 1 of the run 41918079466 has no job 'build (ubuntu-24.04, outputs)'
```

`ci / ci` の判定は `visual` の失敗で失敗し、`determinism` と `release` は省かれた。
つまり、今の `main` では、`v` で始まるタグを押しても下書きのリリースは作られない。

[ADR 0095](0095-visual-job-in-ci.md) は「`release.yml` は `ci.yml` を呼ぶので、リリースの前にも `visual` が動く」とし、`release.yml` には手を加えないと決めた。
[ADR 0099](0099-visual-job-waits-only-for-visual-pdfs.md) はジョブを名前で探す形にしたが、呼び出し元の接頭辞を考えなかった。
`scripts/visual/test.sh` の偽の `gh` は、`--jq` の絞り込みを行わず、`FAKE_JOB_STATUS` をそのまま返す。
そのため、名前の照合そのものはテストされておらず、この食い違いは CI で見つからなかった。

同じ実行の `ci / visual` には、成果物の権限（`actions: read`）が呼び出し元で足りないという別の問題もあり、#547 が直す。
この ADR は、ジョブの名前の照合だけを扱う。

### ジョブを見分ける手がかり

ジョブの一覧の API（`GET /repos/{owner}/{repo}/actions/runs/{run_id}/attempts/{attempt}/jobs`）が返すジョブには、数の `id`、表示の `name`、`status` などがあるが、ワークフローの YAML のジョブのキー（`build`）や行列の値は含まれない。
したがって、API から待つジョブを見分ける手がかりは `name` だけである。

## 実装すること

テストを先に書き、今の実装で失敗することを確かめる。

### 名前の照合

`wait-pdfs.sh RUN ATTEMPT JOB` の、ジョブの照合を次のとおりに変える。

- ジョブの一覧は、`gh api --paginate .../attempts/$ATTEMPT/jobs --jq '.jobs[] | [.name, .status] | @tsv'` で、名前と状態をタブで区切った行として受け取る。照合は、`jq` ではなくシェル（`awk`）で行う。偽の `gh` が行を返せば、照合そのものをテストできる。
- 名前が `JOB` と一致するか、` / JOB` で終わるジョブを、待つジョブとする。` / ` は GitHub が呼び出し元の名前とのあいだに置く区切りである。呼び出しが入れ子になって `a / b / JOB` となっても見つかる。
- 当たるジョブが一つもなければ、今と同じく終了コード 1 で、`JOB` の名前を標準エラーに書く。
- 当たるジョブが二つ以上あれば、終了コード 1 で、当たった名前をすべて標準エラーに書く。どちらを待つかを推して選ぶことはしない。
- 当たるジョブが一つなら、その状態で今と同じ判定をする。

`ci.yml` の `visual` の手順の引数（`'build (ubuntu-24.04, outputs)'`）と、`release.yml` は変えない。

### ドキュメント

- 開発者のマニュアルの「CI のジョブ」の章の `visual` の節に、`release.yml` から呼ばれたときは名前に `ci / ` がつき、`wait-pdfs.sh` はそれも見つけることを一文で書く。
- `wait-pdfs.sh` の冒頭の注釈に、照合の規則を書く。

## 実装しないこと

- `ci.yml` に `workflow_call` の入力（呼び出し元の接頭辞）を足し、`release.yml` から `ci / ` を渡すこと。「検討して退けたこと」に理由を書く。
- `release.yml` に `visual` を別に置くこと。[ADR 0095](0095-visual-job-in-ci.md) が退けたとおり、`ci` の判定に含まれる。
- `actions: read` の権限の不足。#547 が扱う。
- `ci.yml` のほかのジョブで、名前に頼る箇所を探すこと。2026-11-05 の `main` で、`gh api` でジョブの名前を引くのは `wait-pdfs.sh` だけである。

## 検討して退けたこと

### 呼び出し元の接頭辞を入力で渡す

`ci.yml` に `inputs.job-prefix` を足し、`release.yml` の `ci` ジョブが `with: job-prefix: "ci / "` を渡す形である。
照合は完全一致のまま保てる。
しかし、`release.yml` のジョブのキー（`ci`）と、渡す文字列の二か所に同じことを書くことになる。
キーを変えれば、また同じ失敗が起きる。
`scripts/ci/test.sh` で二か所の一致を検査できるが、検査を一つ足してまで二重に書く理由がない。

### ジョブの id で見分ける

API のジョブの `id` は実行ごとに振られる数で、YAML のジョブのキーとは結びつかない。
`visual` から `build (ubuntu-24.04, outputs)` の `id` を知る手段がないので、採れない。

### ジョブの状態を見ず、成果物だけを待つ

照合をやめ、`visual-pdfs` が現れるまで待つ上限（60 分）だけに頼る形である。
`outputs` が失敗したとき、`visual` は 60 分待ってから失敗する。
[ADR 0099](0099-visual-job-waits-only-for-visual-pdfs.md) が `outputs` の失敗を早く知らせるために状態を見ると決めた理由を失う。

### 後方の一致だけで照合する

` / ` を区切りとして求めず、名前が `JOB` で終わるものを選ぶ形である。
`xbuild (ubuntu-24.04, outputs)` のような名前にも当たる。
区切りを求めても照合は一行で書けるので、厳しい側を選ぶ。

## テスト設計

`scripts/visual/test.sh` の `wait-pdfs.sh` の項目を直す。
偽の `gh` は、ジョブの問い合わせに、`FAKE_JOBS`（名前と状態をタブで区切った行）を返すようにする。
今の項目は、`FAKE_JOBS` に `build (ubuntu-24.04, outputs)` の一行を置いて同じことを確かめる。

先に書いて、今の実装で失敗させる項目は次のとおりである。

- 実行 41918079466 のジョブの一覧の形（`version`、`build (x86_64-linux, ubuntu-24.04)`、`ci / build (ubuntu-24.04, outputs)`、`ci / build (ubuntu-24.04-arm, outputs)`、`ci / visual` など）で、`ci / build (ubuntu-24.04, outputs)` が `completed` で成果物がないとき、終了コード 1 で「成果物なしで終わった」と書くこと。今の実装は「ジョブがない」と書く。
- 同じ一覧で `ci / build (ubuntu-24.04, outputs)` が `in_progress` のとき、成果物が 2 回目の問い合わせで現れれば、終了コード 0 で終わること。

今の実装でも通るが、規則を固定する項目は次のとおりである。

- `a / b / build (ubuntu-24.04, outputs)` が見つかること。
- `xbuild (ubuntu-24.04, outputs)` と `build (ubuntu-24.04, outputs) / x` だけの一覧では、ジョブがないとして終了コード 1 であること。
- `build (ubuntu-24.04, outputs)` と `ci / build (ubuntu-24.04, outputs)` の両方がある一覧では、終了コード 1 で、二つの名前を標準エラーに書くこと。
- `ci / build (ubuntu-24.04-arm, outputs)` だけの一覧では、ジョブがないとすること。

自動テストにできないものは、次のとおり確かめる。

- #547 と、この ADR の実装がともに `main` に入った後、`release.yml` を `workflow_dispatch` で動かし、`ci / visual` が `ci / build (ubuntu-24.04, outputs)` の成果物を待って通ること。実行の番号をプルリクエストの説明に書く。
- `pull_request` の CI で、`visual` が今までどおり通ること。

## トレードオフ

- 照合が ` / JOB` の後方の一致まで広がる。`ci.yml` の中に、`… / build (ubuntu-24.04, outputs)` という名前のジョブを別に足すと、二つが当たって失敗する。黙ってどちらかを選ぶより、失敗して気付けるほうを選んだ。
- GitHub が呼び出し元の名前とのあいだに置く区切り（` / `）に依存する。区切りが変われば、呼ばれたときだけまた見つからなくなる。そのときは `release.yml` の試しの実行で気付く。
- `release.yml` を試しに動かすまで、呼ばれたときの形は CI で確かめられない。テストの一覧は、実行 41918079466 の実際の名前から作るので、今の区切りでの振る舞いは固定できる。

## 決めたことの記録

- **採択**：メンテナーが採択した（2026-11-05）。この ADR が決めてほしい点として挙げた項目は、どれも ADR の推奨のとおりとする。

## 参考文献

- [ADR 0095](0095-visual-job-in-ci.md)
- [ADR 0096](0096-before-and-after-images-of-changed-pages.md)
- [ADR 0099](0099-visual-job-waits-only-for-visual-pdfs.md)
- [wait-pdfs.sh（今の実装）](https://github.com/tett23/golem/blob/2a743e8041fbd7c4810cf9352aa5d43db0a5254d/scripts/visual/wait-pdfs.sh)
- [ci.yml の visual ジョブの待つ手順](https://github.com/tett23/golem/blob/2a743e8041fbd7c4810cf9352aa5d43db0a5254d/.github/workflows/ci.yml#L529-L535)
- [scripts/visual/test.sh の wait-pdfs.sh の項目（偽の gh）](https://github.com/tett23/golem/blob/2a743e8041fbd7c4810cf9352aa5d43db0a5254d/scripts/visual/test.sh#L323-L355)
- `release.yml` の実行 41918079466（2026-11-04、`workflow_dispatch`、#547 のブランチ）
- GitHub REST API, "List jobs for a workflow run attempt". https://docs.github.com/en/rest/actions/workflow-jobs
- GitHub Docs, "Reusing workflows". https://docs.github.com/en/actions/sharing-automations/reusing-workflows
