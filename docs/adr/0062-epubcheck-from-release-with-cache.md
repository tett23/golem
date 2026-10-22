# ADR 0062: epubcheck を apt ではなく配布元の release から取り、キャッシュする

ステータス: 採択

## 文脈

CI の `build` ジョブは、x86-64 の `outputs` のランナーで、出力した EPUB を epubcheck で検査する（[golem-epub ADR 0001](../golem-epub/adr/0001-epub-packaging.md)）。
epubcheck は、ほかのランナーの qpdf と同じく、`scripts/ci/apt-install.sh` で apt から入れている。
apt は裏で動かし（`scripts/ci/bg.sh`、[ADR 0037](0037-ci-build-job-speedup.md)）、`timeout -k 10 300` で 5 分に限る。
5 分を超えると、終了コード 124 でジョブが失敗する。

### 調べたこと（2026-10-23）

直近の 60 回の `ci.yml` の実行を調べた。

- 失敗は 15 回で、そのうち 11 回が、x86-64 の `outputs` のランナーの apt の時間切れ（終了コード 124）だった。60 回のうちの 11 回で、およそ 18% の実行がこの理由で落ちている。
- qpdf だけを入れるテストのランナー（x86-64 の `tests` と aarch64 の `all`）では、一度も起きていない。
- epubcheck を apt で入れると、Java の実行環境（`openjdk-21-jre-headless`、46.5 MB）を含めて 80.8 MB を取ってくる。うまくいった回は 1 秒から 10 秒で取り終えている。
- 失敗した回のログでは、Azure の Ubuntu のミラー（`azure.archive.ubuntu.com`）からのダウンロードが途中で止まっていた。`openjdk-21-jre-headless` の途中で止まった回と、`libguava-java` で一度止まって再試行した後に時間切れになった回がある。
- apt が入れる epubcheck は Ubuntu 24.04 の 4.2.6 であり、配布元の最新（5.4.0、2026-09-15）よりかなり古い。

GitHub の ubuntu-24.04 のランナーには、Java（8、11、17、21、25。既定は 17）がもとから入っている（actions/runner-images の Ubuntu2404-Readme）。
epubcheck は Java の jar なので、Java の実行環境を apt で入れ直す必要はない。

## 実装すること

### epubcheck を配布元の release から取る

- epubcheck を、配布元（GitHub の w3c/epubcheck）の release の zip（`epubcheck-<版>.zip`）から取る。版は 5.4.0 に固定し、zip の SHA-256 を `ci.yml` に書いて検査する。
- zip は `actions/cache` でキャッシュする。キーは版と SHA-256 とする。キャッシュがあれば、ネットワークから何も取らない。
- 取り出した jar は、ランナーにもとから入っている Java（`JAVA_HOME_17_X64`）で動かす。`epubcheck` の名前で呼べるよう、jar を動かす小さなシェルのスクリプトを `PATH` に置く。
- 取り出しと検査は、新しいスクリプト `scripts/ci/epubcheck-install.sh <版> <SHA-256>` で行う。apt と同じく `bg.sh` で裏で動かし、時間切れは 5 分のままとする。
- x86-64 の `outputs` のランナーでは、apt を使わない。テストのランナーは、今のとおり apt で qpdf を入れる。

### apt の時間切れを短く再試行する

- `scripts/ci/apt-install.sh` の `apt-get` に、`-o Acquire::http::Timeout=30 -o Acquire::Retries=3` を付ける。止まった接続を 30 秒で切って取り直すので、ミラーの一時的な停止で 5 分を使い切ることが減る。qpdf のランナーでは起きていないが、同じ原因で起きうるので一緒に直す。

### epubcheck の版を上げることの扱い

- 4.2.6 から 5.4.0 に上げると、検査の規則が EPUB 3.3 に沿って変わり、今の EPUB に新しいエラーや警告が出る可能性がある。この ADR の実装で、今の CI が検査している二つの EPUB（`sample` と `bibliographies` の fixture）と、二冊のマニュアルの EPUB を 5.4.0 にかけ、出たものを直す。Golem の出力の誤りなら、直す変更を別のプルリクエストか ADR で入れてから、この ADR を実装する。
- 版を上げるときは、`ci.yml` の版と SHA-256 を変えるプルリクエストを出す。

### ドキュメント

- README の CI の表の `build` ジョブの説明と、CONTRIBUTING と開発者のマニュアルの CI の章に、epubcheck を配布元から取ってキャッシュすることと、その版を書く。
- [ADR 0037](0037-ci-build-job-speedup.md) のステータスの行に「、epubcheck の入れ方と apt の時間切れの再試行は [ADR 0062](0062-epubcheck-from-release-with-cache.md)」を足す。

## 実装しないこと

- qpdf を apt の外から取ること。今の失敗は epubcheck のランナーだけで起きている。
- 手元で開発する人の epubcheck の入れ方を変えること。README の手順は今のままとする。
- Java の版を固定すること。ランナーの既定の Java（17）で動かす。epubcheck 5.x が求めるのは Java 11 以上である。

## テスト設計

テストを先に書き、今の実装で失敗することを確かめる。

- `scripts/ci/test.sh` に、`epubcheck-install.sh` の項目を足す。偽の zip と SHA-256 で、SHA-256 が合えば jar を取り出して `epubcheck` を `PATH` に置くこと、合わなければ失敗すること、キャッシュの zip があればネットワークから取らないこと（`curl` を偽物にして呼ばれないことを確かめる）。
- `scripts/ci/test.sh` に、`ci.yml` の x86-64 の `outputs` のランナーが apt で epubcheck を入れず、`epubcheck-install.sh` と `actions/cache` を使うこと、`apt-install.sh` が `Acquire::http::Timeout` と `Acquire::Retries` を付けることを確かめる項目を足す（今の `step_if` と同じ形）。今の `apt-install.sh` の項目（433 行と 437 行）の期待するコマンドも改める。
- 実装のプルリクエストで、CI の二つの EPUB の検査が 5.4.0 で通ることを確かめる。
- 実装の後の 30 回の CI の実行で、apt と epubcheck の時間切れが一度も起きないことを確かめ、結果を `docs/ci-timings/` に記録する。

## トレードオフ

- epubcheck の版が 4.2.6 から 5.4.0 に変わるので、検査が厳しくなりうる。今の EPUB が 5.4.0 で通らなければ、先に Golem の出力を直す必要がある。新しい規則で検査するほうが、EPUB の読書環境での問題を早く見つけられる。
- 版と SHA-256 を `ci.yml` に書くので、版を上げる手間が増える。Ubuntu の版に任せていた今より、版がはっきりする。
- 配布元の GitHub の release に依存する。キャッシュがあれば取りに行かないので、取りに行くのは版を上げたときとキャッシュが消えたときだけである。

## 参考文献

- [ADR 0037](0037-ci-build-job-speedup.md)
- [golem-epub ADR 0001](../golem-epub/adr/0001-epub-packaging.md)
- actions/runner-images、Ubuntu 24.04 の README（Java の節）
- w3c/epubcheck、v5.4.0 の release
