# ADR 0442: wait-pdfs.sh で待った成果物を、digest で確かめて取り直しつきで取り寄せる

Status: superseded [{"part":"実装することの、取り寄せる成果物の選び方と、名前の一致する成果物が二つ以上あるときの扱い（未確認の注記を含む）、I5、境界の表の「同じ名前の成果物が二つある」の行","by":["docs/adr/0446-pick-the-newest-artifact-of-a-name-across-attempts.md"],"kind":"replace"}]

## 文脈

[root ADR 0099](0099-visual-job-waits-only-for-visual-pdfs.md) は、`visual` を `build` と同時に始め、`scripts/visual/wait-pdfs.sh` で成果物 `visual-pdfs` を待たせた。
その前提は、upload-artifact の v4 以降では、上げた成果物を同じ実行の中ですぐに API で取れる、ということだった。
同じ形は、`wasm`（`wasm-native-list`、[root ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md)）、`editors-lsp`（`golem-linux-x86_64`、[root ADR 0231](0231-run-the-lsp-and-the-editor-grammars-in-headless-neovim-and-helix.md)）、`verapdf`（`conformance-pdfs`、[root ADR 0244](0244-take-verapdf-off-the-critical-path-of-ci.md)）にも広がった。
どのジョブも、`wait-pdfs.sh` が終了コード 0 で終わった直後に、`actions/download-artifact` で成果物を取り寄せる。

しかし、この前提は成り立たないことがある。
`wait-pdfs.sh` が成果物を一覧の API で見つけた 1 秒以内に、`actions/download-artifact` が同じ成果物を見つけられずに失敗した例が、2026-11-23 に 2 回あった（「調査した事項」）。
どちらも、失敗したジョブを再実行すると通った。
CI の失敗の理由が変更と関係しないので、メンテナーは毎回ログを読んで再実行するしかない。
この ADR は、待った成果物の取り寄せを、成果物が取れるようになるまで取り直す形に変える。

## 調査した事項

次のログと API の応答を、2026-11-24 に `gh run view`、`gh api .../actions/jobs/<ID>/logs`、`gh api .../actions/runs/<RUN>/artifacts` で取得して確かめた。
時刻はログの行の時刻（UTC）である。

1 回目は、PR #1095 の実行 45099523314 の試行 1 の `editors-lsp`（ジョブ 137447276110）である。

| 時刻 | ジョブ | ログの行 |
| --- | --- | --- |
| 02:22:41.9376 | `build (ubuntu-24.04, outputs)`（137447276174） | `Artifact golem-linux-x86_64 successfully finalized. Artifact ID 14785445098` |
| 02:22:42.4693 | `editors-lsp` | `wait-pdfs: golem-linux-x86_64 is uploaded` |
| 02:22:42.7444 | `editors-lsp` | `##[error]Unable to download artifact(s): Artifact not found for name: golem-linux-x86_64` |

2 回目は、PR #1128 の実行 45237425490 の試行 1 の `verapdf`（ジョブ 137912965976）である。

| 時刻 | ジョブ | ログの行 |
| --- | --- | --- |
| 18:23:32.4460 | `build (ubuntu-24.04, outputs)`（137912966281） | `Uploading artifact: conformance-pdfs.zip` |
| 18:23:33.5715 | 同上 | `Finalizing artifact upload` |
| 18:23:34.0856 | `verapdf` | `wait-pdfs: conformance-pdfs is uploaded` |
| 18:23:34.1245 | `build (ubuntu-24.04, outputs)` | `Artifact conformance-pdfs successfully finalized. Artifact ID 14850482527` |
| 18:23:34.5938 | `verapdf` | `##[error]Unable to download artifact(s): Artifact not found for name: conformance-pdfs` |

- どちらの失敗も、`wait-pdfs.sh` が成果物を見つけてから `actions/download-artifact` が失敗するまで、0.3〜0.5 秒である。
- 2 回目では、`wait-pdfs.sh` が成果物を見つけたと書いた行が、上げる側の `successfully finalized` の行より 39 ミリ秒早い。
  一覧の API（`GET /repos/{owner}/{repo}/actions/runs/{run}/artifacts?name=…`）の `conformance-pdfs` の `created_at` は `2026-11-23T18:23:33Z` で、確定（finalize）を終えた時刻より前である。
- どちらの実行も、試行 2 で同じジョブが通った。
- 一覧の API の応答は、成果物ごとに `digest`（`sha256:` で始まる、上げた zip の SHA-256）と `archive_download_url` を持つ。
  実行 45237425490 の `conformance-pdfs` の `digest` は、上げる側のログの `SHA256 digest of uploaded artifact is a8e71b94…` と一致した。

待つ手順と取り寄せる手順は、origin/main（[b9eb4f236](https://github.com/tett23/golem/commit/b9eb4f236c9f4b3c5bb9668e903d8a52f4068652)）で次のとおりである。

- `wait-pdfs.sh` は、一覧の API で、期限切れでない成果物が一つでもあれば終了コード 0 で終わる（[wait-pdfs.sh#L33-L40](https://github.com/tett23/golem/blob/b9eb4f236c9f4b3c5bb9668e903d8a52f4068652/scripts/visual/wait-pdfs.sh#L33-L40)）。
  成果物の確定を終えたかは見ない。
- 待った後に `actions/download-artifact` を使うジョブは、`wasm`（[ci.yml#L1017-L1018](https://github.com/tett23/golem/blob/b9eb4f236c9f4b3c5bb9668e903d8a52f4068652/.github/workflows/ci.yml#L1017-L1018)）、`visual`（[ci.yml#L1115-L1116](https://github.com/tett23/golem/blob/b9eb4f236c9f4b3c5bb9668e903d8a52f4068652/.github/workflows/ci.yml#L1115-L1116)）、`editors-lsp`（[ci.yml#L1348-L1349](https://github.com/tett23/golem/blob/b9eb4f236c9f4b3c5bb9668e903d8a52f4068652/.github/workflows/ci.yml#L1348-L1349)）、`verapdf`（[ci.yml#L1396-L1397](https://github.com/tett23/golem/blob/b9eb4f236c9f4b3c5bb9668e903d8a52f4068652/.github/workflows/ci.yml#L1396-L1397)）の 4 つである。
  `actions/download-artifact` には、取り直しの設定がない。

### 推測

次は、上の時刻からの推測で、確かめていない。

- 一覧の API は、上げ始めた成果物を、確定を終える前から返す。
  `actions/download-artifact` は、別の経路（Actions の結果のサービスの一覧）で、確定を終えた成果物だけを探す。
  そのため、`wait-pdfs.sh` が確定の前か直後に成果物を見つけると、`actions/download-artifact` はまだその成果物を見つけられない。
- 1 回目は、確定の 0.5 秒後に成果物を見つけ、0.8 秒後に取り寄せに失敗しているので、確定を終えた後にも、取り寄せの経路に現れるまでの遅れがある。
  確定を待つだけでは、この競合はなくならない。

## 実装すること

テストを先に書き、今の実装で失敗することを確かめる。

- `scripts/ci/download-artifact.sh RUN NAME DIR` を足す。
  一覧の API で、実行 `RUN` の名前 `NAME` の期限切れでない成果物を問い合わせ、`digest` があるものの `archive_download_url` から zip を取り寄せる。
  zip の SHA-256 が `digest` と一致したら、`DIR` に展開して終了コード 0 で終わる。
- 一回の試行は、一覧の問い合わせと、zip の取り寄せの一組とする。
  一覧の問い合わせは、`wait-pdfs.sh` と同じく `scripts/ci/github-api-read.sh` を通す（利用上限の 429 と 403 を待って取り直す、[root ADR 0349](0349-retry-ci-job-list-on-rate-limit.md)）。
  利用上限の待ちは、試行の数に数えない。
  zip は `gh api` で取り寄せ、`gh` が 302 の転送を追う。
  SHA-256 は、`sha256sum` があればそれで、なければ `shasum -a 256` で求める（scripts-macos でも走るため）。
- 成果物がない、`digest` がない、取り寄せが 404 で失敗した、のどれかのときは、`DOWNLOAD_INTERVAL` 秒（既定 5）待って取り直す。
  `DOWNLOAD_ATTEMPTS` 回（既定 12、待ちの合計は約 1 分）で取れなければ、最後の理由を標準エラーに書いて終了コード 1 で終わる。
- SHA-256 が `digest` と一致しないとき、取り寄せが 401 か 403（利用上限でない）で失敗したときは、取り直さずに終了コード 1 で終わる。
  一致しないことは、[root ADR 0243](0243-retry-every-download-and-cache-the-archives-checked-by-sha-256.md) と同じく、取り直しで直る失敗ではないと見る。
  権限の不足も、取り直しで直らない。
- 名前 `NAME` の期限切れでない成果物が二つ以上あるときは、取り寄せずに終了コード 1 で終わる。
  実行の全体を再実行したときに、前の試行の同じ名前の成果物が一覧に残るかは確かめていない（未確認）。
  残るなら、この決まりで再実行が毎回失敗するので、採択の前に再実行の一覧を確かめ、残る場合は試行の番号で絞る形にこの ADR を直す。
- 引数が 3 つでなければ、終了コード 2 で終わる。
- `ci.yml` の `wasm`、`visual`、`editors-lsp`、`verapdf` で、`wait-pdfs.sh` の後の `actions/download-artifact` を、`timeout-minutes: 5` の `sh scripts/ci/download-artifact.sh "$GITHUB_RUN_ID" <成果物> <置き場所>` の手順に替える。
  置き場所は、今の `path` と同じにし、`path` の無い `wasm` では作業ディレクトリ（`.`）とする。
  トークンは、`wait-pdfs.sh` の手順と同じ `GH_TOKEN` と `GH_REPO` を渡す。
- 成果物の zip を REST で取り寄せるには、トークンに `actions: read` の権限が要る。
  今 `actions: read` を持つのは `visual` と `ci` だけなので、`wasm`、`editors-lsp`、`verapdf` に `actions: read` を足す。
  これは、[root ADR 0096](0096-before-and-after-images-of-changed-pages.md) の「ほかのジョブには足さない」と、[root ADR 0244](0244-take-verapdf-off-the-critical-path-of-ci.md) の「`wasm` と `editors-lsp` は `contents: read` だけで、権限は変えない」を変える。
  `scripts/ci/test.sh` の、`actions: read` を持つジョブが `ci` と `visual` だけであることの検査も直す。
  `release.yml` は `ci` を `actions: write` で呼ぶので、呼ばれたときも足りる。
- `wait-pdfs.sh` は変えない。待つことと取り寄せることを、別のスクリプトに分けたままにする。
- 待った成果物ではない `actions/download-artifact`（`determinism` など、`needs` で上げる側のジョブの終わりを待つもの）は変えない。
- [root ADR 0244](0244-take-verapdf-off-the-critical-path-of-ci.md) の手順の並びのうち、`actions/download-artifact` は `download-artifact.sh` の手順に替わる。
  ほかの並び（Nix と veraPDF の取得が待つ前、検査が取り寄せの後）は変えない。
- README の `visual`、`wasm`、`editors-lsp`、`verapdf` の節と、開発者のマニュアルの `manual-dev/part2/11-ci-jobs.gm` の `visual` の節で、`wait-pdfs.sh` の後の取り寄せを書いたところに、`download-artifact.sh` で取り寄せることを書く。

### ステータスの行

採択したら、次の ADR のステータスに、この ADR の変更を記録する。

- [root ADR 0099](0099-visual-job-waits-only-for-visual-pdfs.md)、[root ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md)、[root ADR 0231](0231-run-the-lsp-and-the-editor-grammars-in-headless-neovim-and-helix.md)、[root ADR 0244](0244-take-verapdf-off-the-critical-path-of-ci.md): 待った後の取り寄せの手順を置き換えた（`replace`）。
- [root ADR 0096](0096-before-and-after-images-of-changed-pages.md) と 0244: `wasm`、`editors-lsp`、`verapdf` の権限を置き換えた（`replace`）。

## 実装しないこと

- 取り寄せる側のジョブを `needs: build` にすること。
  `build` は行列のジョブで、`needs` は一つのランナーだけを指せない（[root ADR 0099](0099-visual-job-waits-only-for-visual-pdfs.md)）。
  行列のすべてのランナーを待つと、[root ADR 0099](0099-visual-job-waits-only-for-visual-pdfs.md) と [root ADR 0244](0244-take-verapdf-off-the-critical-path-of-ci.md) が縮めた時間が戻る。
- `wait-pdfs.sh` に、確定を待つ条件だけを足すこと。
  1 回目は、確定の 0.5 秒後に見つけてから取り寄せに失敗したので、確定を待っても防げなかった（推測）。
  確定の前に `digest` が空になるかも確かめていない（REST の文書の型は文字列か null で、いつ null かは書いていない）。
- `actions/download-artifact` の手順を `continue-on-error` にして、もう一度同じ手順を置くこと。
  1 回目の失敗が、成功した実行にもエラーの注釈として残る。
- `release.yml`、`browser.yml`、`wasm-tests.yml`、`enum.yml` の `actions/download-artifact`。
  どれも `needs` で上げる側のジョブの終わりを待っていて、待った直後の取り寄せではない。

## 不変条件

`download-artifact.sh` を、偽の `gh` で確かめる。

- I1: 終了コード 0 で終わったとき、`DIR` の中身は、`digest` と SHA-256 が一致した zip を展開したものである。
- I2: `digest` と SHA-256 が一致しない zip を、`DIR` に展開せず、取り直さずに終了コード 1 で終わる。
- I3: 成果物が取れるまでの試行（一覧の問い合わせと取り寄せの一組）が `DOWNLOAD_ATTEMPTS` 回以内なら、終了コード 0 で終わる。
- I4: 取り直す失敗が続いて `DOWNLOAD_ATTEMPTS` 回の試行で取れなければ、`DOWNLOAD_ATTEMPTS` 回だけ試行して、終了コード 1 で終わり、最後の理由を標準エラーに書く。
- I5: 名前の一致する成果物が二つ以上あれば、取り寄せずに終了コード 1 で終わる。
- I6: 問い合わせる一覧のパスは、`RUN` と `NAME` を含む。
- I7: 取り寄せが 401 か 403（利用上限でない）で失敗したとき、取り直さずに終了コード 1 で終わる。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| 1 回目の問い合わせで、成果物が一つあり、`digest` が一致する | 1 回で終了コード 0、展開する | I1, I3, I6 |
| 1 回目は成果物がなく、2 回目にある | 2 回で終了コード 0 | I3 |
| 1 回目は `digest` がなく、2 回目にある | 2 回で終了コード 0 | I3 |
| 期限切れの成果物だけがある | 成果物がないものとして取り直し、`DOWNLOAD_ATTEMPTS` 回で終了コード 1 | I4 |
| 1 回目は取り寄せが 404 で、2 回目に取れる | 2 回で終了コード 0 | I3 |
| ちょうど `DOWNLOAD_ATTEMPTS` 回目に取れる | 終了コード 0 | I3 |
| `DOWNLOAD_ATTEMPTS` 回とも成果物がない | `DOWNLOAD_ATTEMPTS` 回で終了コード 1 | I4 |
| 1 回目の zip の SHA-256 が `digest` と一致しない | 1 回で展開せず、終了コード 1 | I2 |
| 取り寄せが 403（利用上限でない） | 1 回で終了コード 1 | I7 |
| 同じ名前の成果物が二つある | 取り寄せず、終了コード 1 | I5 |
| 引数が 2 つ | 終了コード 2 | なし |

## 受けいれ条件

- A1: `ci.yml` で、`wait-pdfs.sh` の手順を持つジョブは、どれも `actions/download-artifact` を使わず、`wait-pdfs.sh` の手順の後に、同じ成果物の名前で `download-artifact.sh` の手順を持つ。
- A2: 実装のプルリクエストの CI で、4 つのジョブが成果物を取り寄せて通る。

## テスト設計

- `scripts/ci/test.sh` に、偽の `gh` で、不変条件の表の各行を確かめる項目を足す。
  テストの名前は `root ADR 0442 I<番号>: …` とする。
  待ちは `DOWNLOAD_INTERVAL=0` で縮める。
- `scripts/ci/test.sh` の、`visual` と `verapdf` の手順の並びの項目（[root ADR 0099](0099-visual-job-waits-only-for-visual-pdfs.md)、[root ADR 0244](0244-take-verapdf-off-the-critical-path-of-ci.md) I4）と、`visual` が `visual-pdfs` を取り寄せることの項目を、`actions/download-artifact` の代わりに `download-artifact.sh` の手順を探すように直す。
- A1 を、`ci.yml` を読む項目として `scripts/ci/test.sh` に足す。
- A2 は、実装のプルリクエストの CI の結果で確かめる。

## トレードオフ

- `wasm`、`editors-lsp`、`verapdf` に `actions: read` を足すので、三つのジョブのトークンが、同じリポジトリの Actions の実行と成果物を読めるようになる。
  書き込みの権限は足さない。
- 取り寄せを自前のスクリプトで行うので、`actions/download-artifact` の更新（速さ、展開の扱い）を受けられない。
  一方で、取り寄せた zip を `digest` で確かめ、一致しなければ取り直さずに止めるので、[root ADR 0243](0243-retry-every-download-and-cache-the-archives-checked-by-sha-256.md) の取得と同じ扱いになる。
  0243 の `scripts/ci/fetch-url.sh` は使わない。成果物の取り寄せは GitHub のトークンと 302 の転送が要り、`gh api` で行うためである。
- 成果物が本当に上がらなかったときに、失敗が最大で約 1 分遅れる。
  上がらずに上げる側のジョブが終わったときは、`wait-pdfs.sh` が先に終了コード 1 で終わる。
  遅れが出るのは、待った後に成果物が消えたときと、`digest` がいつまでも空のときである。
  権限の不足と SHA-256 の不一致では、取り直さずにすぐ止める。
- 一覧の API と取り寄せの経路の遅れが 1 分を超えると、まだ失敗する。
  2 回の失敗の遅れは 1 秒以内だったので、1 分あれば足りると見ている（推測）。

## 参考文献

- [root ADR 0099](0099-visual-job-waits-only-for-visual-pdfs.md)、[root ADR 0165](0165-wait-pdfs-finds-the-job-under-a-caller-prefix.md)、[root ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md)、[root ADR 0231](0231-run-the-lsp-and-the-editor-grammars-in-headless-neovim-and-helix.md)、[root ADR 0243](0243-retry-every-download-and-cache-the-archives-checked-by-sha-256.md)、[root ADR 0244](0244-take-verapdf-off-the-critical-path-of-ci.md)
- [GitHub REST API: List workflow run artifacts](https://docs.github.com/en/rest/actions/artifacts#list-workflow-run-artifacts)
- CI の実行 45099523314（PR #1095、2026-11-23）と 45237425490（PR #1128、2026-11-23）の試行 1
