# ADR 0021: ドキュメントの検査の分離と CI の判定ジョブ

ステータス: 採択

## 文脈

[ADR 0009](0009-ci-speed.md) の「9. 変更のないジョブを省く」で、docs だけの変更では `build`、`determinism`、`format`、`release-scripts` を省くことにした。
`changes` ジョブが変更のパスを `scripts/ci/needs-build.sh` に渡し、ビルドが要るかを決める。
ところが、docs だけを変えたプルリクエストでも全部のジョブが走ることがある。

### 差分の取り方の誤り

`changes` ジョブは、プルリクエストのとき `git diff --name-only "$PR_BASE" "$PR_HEAD"` で変更のパスを集めている。
`PR_BASE` はプルリクエストの base の今の先端であり、ブランチの分岐点ではない。
プルリクエストを作ったあとにほかのプルリクエストが `main` に入ると、base の先端はその分だけ進む。
二点の差分は、ほかのプルリクエストの変更を逆向きに含んでしまう。

[#49](https://github.com/tett23/golem/pull/49) がその例である。
変更は `docs/specifications.md` の一行だけだが、作った直後に [#48](https://github.com/tett23/golem/pull/48)（peg-hs の更新）が入った。
二点の差分には #48 の `cabal.project` と生成したパーサーが入り、`needs-build.sh` は `true` を返した。
分岐点からの差分（`git diff --name-only "$PR_BASE...$PR_HEAD"`）なら `docs/specifications.md` だけになり、`false` を返す。
手元でこの二つを比べて確かめた。

### docs を読むビルドとテスト

[ADR 0009](0009-ci-speed.md) は、docs だけの変更を省いてよい根拠を「どのテストも `docs/` の下のファイルを読まない」ことに置いた。
この前提は崩れつつある。
`docs/diagnostics.md`（診断のコードの一覧）を作ったブランチでは、golem-cli のテストがこのファイルを読み、ソースの診断のコードがすべて載っているかを確かめる。
提案中の `golem explain` の ADR（golem-cli の 5 番）は、このファイルを実行ファイルに埋め込む。
`docs/diagnostics.md` だけを変えたプルリクエストでビルドを省くと、このテストが走らないまま `main` に入る。

### 保護の規則と必須の検査

2026-10-13 に、`main` に保護の規則（ルールセット）を設けた。
`changes`、`adr`、`format`、`release-scripts`、`build (ubuntu-24.04)`、`build (ubuntu-24.04-arm)`、`determinism` の七つが必須の検査である。
GitHub は、`if` で skip されたジョブを通過として扱うので、docs だけのプルリクエストもマージできる。

peg-hs は、ADR の検査を別のワークフロー（`adr.yml`）に分け、`ci.yml` には `paths-ignore` を付けて、docs だけの変更ではワークフローそのものを起動しない。
これを Golem にそのまま持ち込むと、起動しなかったワークフローの必須の検査が「待ち」のまま残り、docs だけのプルリクエストはマージできなくなる。
必須の検査を `adr` だけに減らせば両立するが、自動マージを付けたコードのプルリクエストが、ビルドの結果を待たずにマージされてしまう。

もう一つ、必須の検査をジョブの名前で七つ並べていることにも手間がある。
ジョブを足す、名前を変える、マトリクスを変えるたびに、ルールセットも直さなければならない。
直し忘れると、存在しない検査を待ち続けてマージできなくなるか、新しいジョブが必須から漏れる。

## 実装すること

### 1. 分岐点からの差分を取る

`scripts/ci/changed-paths.sh` を加え、`changes` ジョブの差分の取り方をここに移す。

```
changed-paths.sh EVENT [BASE HEAD]
```

- `EVENT` が `pull_request` のときは、`git diff --name-only BASE...HEAD`（分岐点からの差分）のパスを、一行に一つ標準出力に書く。
- `EVENT` が `push` のときは、`git diff --name-only BASE..HEAD` のパスを書く。`BASE` が空か、`0` だけからなる（ブランチを作った push）ときは何も書かず、終了コード 3 で終わる。
- それ以外の `EVENT`（`release.yml` から呼ばれたときの `workflow_dispatch` やタグの push）は、終了コード 3 で終わる。
- 終了コード 3 は「差分が決まらない」を表し、`changes` ジョブはビルドする側（`build=true`）に倒す。git が失敗したときも、同じくビルドする側に倒す。
- パスは `git -c core.quotePath=false` で、エスケープせずに書く。

`changes` ジョブは、今の差分の計算の代わりにこのスクリプトを呼び、出力を `needs-build.sh` に渡す。

### 2. ビルドが読む docs を一覧にする

`needs-build.sh` に、ビルドとテストが読む `docs/` の下のファイルの一覧を持たせる。
一覧のファイルを一つでも変えた変更は、docs の下でもビルドする側にする。
今の一覧は `docs/diagnostics.md` だけである。

一覧の漏れは、`scripts/ci/test.sh` の検査で見つける。
`modules/` の下の `*.hs` と `*.cabal`、`scripts/` の下のスクリプトから、`docs/` の下のファイルを指す文字列を grep で拾い、すべてが一覧にあることを確かめる。
一覧にないファイルを指していれば、`changes` ジョブが失敗する。
拾い方は、`docs/[A-Za-z0-9_./-]*\.(md|toml|txt|json)` に当たる文字列とする。
テストの名前のように、ファイルを読まない文字列が当たった場合は、一覧とは別の除外の一覧に、理由のコメントを添えて書く。

### 3. ドキュメントの検査を別のワークフローにする

`.github/workflows/docs.yml` を加え、`ci.yml` の `adr` ジョブをここに移す。

- `docs.yml` は、`main` への push とすべてのプルリクエストで起動する。パスで起動を絞らない。ADR とドキュメントの検査は、docs だけの変更こそが対象だからである。
- ジョブの名前は `adr` のまま変えない。
- `ci.yml` からは `adr` ジョブを消す。`release.yml` が `ci.yml` を呼ぶときに `adr` を skip させていた `if` も要らなくなる。
- `concurrency` は `ci.yml` と同じ形にし、グループの名前の先頭だけを `docs-` にする。

これで、コードの検査とドキュメントの検査が、ワークフローの単位で分かれる。
`ci.yml` の古い実行が取り消されても、`adr` の結果は残る。

### 4. 判定のジョブを一つ置く

`ci.yml` の最後に、`ci` という名前のジョブを置く。

```yaml
ci:
  needs: [changes, build, determinism, release-scripts, format]
  if: always()
  runs-on: ubuntu-24.04
  steps:
    - uses: actions/checkout@v7
      with:
        persist-credentials: false
    - name: Results of the jobs
      env:
        NEEDS: ${{ toJSON(needs) }}
      run: printf '%s\n' "$NEEDS" | sh scripts/ci/gate.sh
```

`scripts/ci/gate.sh` は、標準入力から `needs` の JSON を読む。
すべてのジョブの `result` が `success` か `skipped` なら終了コード 0、一つでも `failure` か `cancelled` があれば、そのジョブの名前と結果を標準エラー出力に書いて終了コード 1 で終わる。
`needs` に含まれるべきジョブの名前（`changes`、`build`、`determinism`、`release-scripts`、`format`）が JSON にないときも、終了コード 1 にする。
`ci.yml` にジョブを足すときは、`needs` とこの名前の一覧の両方に足す。
`scripts/ci/test.sh` は、`ci.yml` のジョブの名前（`ci` を除く）と `gate.sh` の名前の一覧が一致することを確かめる。

`changes` が `build=false` を出した変更では、`build` などが skipped になり、`ci` は通過する。
`changes` が失敗したときは、`build` なども skipped になるが、`changes` の `failure` で `ci` は失敗する。

### 5. 必須の検査を二つにする

実装をマージしたあと、ルールセット（ID 24998069）の必須の検査を、`ci`（`ci.yml`）と `adr`（`docs.yml`）の二つに改める。
ルールセットはリポジトリの設定であり、コードとしては管理しない。
変えるときは、変える前と後の必須の検査の一覧をプルリクエストのコメントに残す。

順序は次のとおりとする。

1. この ADR の実装のプルリクエストを、今の必須の検査（七つ）で通してマージする。`adr` のジョブの名前は変わらず、`ci` は増えるだけなので、今の規則のままマージできる。
2. マージの後、ルールセットの必須の検査を `ci` と `adr` に改める。
3. docs だけのプルリクエストと、コードのプルリクエストを一つずつ出して、下の「確かめ方」を行う。

### ドキュメント

- README の CI の節の表に、`docs.yml` の `adr` と `ci.yml` の `ci` を加え、`adr` が別のワークフローになったこと、必須の検査が `ci` と `adr` であることを書く。
- CONTRIBUTING.md と CONTRIBUTING.en.md の「ブランチとマージ」に、`main` の保護の規則（プルリクエストが必須、マージコミットだけ、必須の検査は `ci` と `adr`）を書く。
- `docs/` の下にビルドが読むファイルを足したときは、`scripts/ci/needs-build.sh` の一覧に加えることを、CONTRIBUTING.md の「ドキュメント」に書く。

## 実装しないこと

- `paths-ignore` で `ci.yml` を起動しないこと。必須の検査が待ちのまま残るためである（文脈の「保護の規則と必須の検査」）。判定のジョブを置いたあとも、`ci` が起動しなければ同じことになる。
- マージキュー。プルリクエストの数が少なく、待ちが問題になっていない。
- `changes` ジョブを GitHub の API（プルリクエストの変更ファイルの一覧）に置き換えること。API の一覧は 3000 ファイルで打ち切られ、`push` には使えない。git の差分なら両方を同じ規則で扱える。
- ルールセットをリポジトリの中のファイルから設定すること。GitHub にその仕組みがない。
- ドキュメントのリンク切れや文体の検査を `docs.yml` に足すこと。必要になったら別の ADR で決める。

## テスト設計

### 先に書いて失敗させるテスト（`scripts/ci/test.sh`）

`changed-paths.sh` について、一時ディレクトリに git のリポジトリを作って確かめる。

- `main` で `a.hs` を作ってコミットし、そこからブランチを切って `docs/x.md` を足してコミットする。そのあと `main` で `b.hs` を足してコミットする。`pull_request`、`BASE` に `main` の先端、`HEAD` にブランチの先端を渡すと、出力が `docs/x.md` だけになること。
- 同じリポジトリで、`push`、`BASE` に `main` の一つ前、`HEAD` に `main` の先端を渡すと、出力が `b.hs` だけになること。
- `push` で `BASE` が `0000000000000000000000000000000000000000` のとき、終了コード 3 で何も書かないこと。
- `workflow_dispatch` のとき、終了コード 3 で終わること。
- 存在しないコミットを渡したとき、0 と 3 以外の終了コードで終わること。
- 空白と日本語を含むパス（`docs/a b.md`、`docs/日本語.md`）が、エスケープされずにそのまま書かれること。

`needs-build.sh` について、今の表に次を加える。

- `docs/diagnostics.md` だけの変更で `true` を出すこと。
- `docs/diagnostics.md` と `docs/specifications.md` の変更で `true` を出すこと。
- `docs/specifications.md` だけの変更で、今と同じく `false` を出すこと。

docs の一覧の漏れの検査について、次を確かめる。

- 今のリポジトリで検査が通ること。
- 一時ディレクトリに `modules/x/test/Main.hs` を作り、`"../../docs/new.md"` を書いて検査に渡すと、`docs/new.md` を挙げて失敗すること。

`gate.sh` について、標準入力と終了コードを並べる。

- 五つのジョブがすべて `success` で 0。
- `build`、`determinism`、`release-scripts`、`format` が `skipped`、`changes` が `success` で 0。
- `build` が `failure` で 1、標準エラー出力に `build` と `failure` が出ること。
- `determinism` が `cancelled` で 1。
- `format` がない JSON で 1、標準エラー出力に `format` が出ること。
- JSON でない入力で 1。

`ci.yml` のジョブの名前と `gate.sh` の一覧が一致することの検査について、今の `ci.yml` で通ること、一覧から一つ消したときに失敗することを確かめる。

### 自動テストにできないものの確かめ方

マージとルールセットの変更の後に、次を確かめ、結果をこの ADR の実装のプルリクエストのコメントに書く。

- docs だけを変えたプルリクエスト（`docs/specifications.md` の一行）を、ほかのプルリクエストを `main` に入れたあとで出し直したときにも、`build`、`determinism`、`format`、`release-scripts` が skipped になり、`ci` と `adr` が通ってマージできること。
- `docs/diagnostics.md` だけを変えたプルリクエストで、`build` が走ること。
- コードを変えたプルリクエストで、`ci` が `build` の終わりを待ってから通ること。わざとテストを一つ落としたコミットを push して、`ci` が失敗し、マージのボタンが押せないことも確かめる（確かめたら、そのコミットは取り消す）。
- `release.yml` を `workflow_dispatch` で走らせたときに、`ci / ci` が通り、`adr` が呼ばれないこと。

## トレードオフ

- 判定のジョブ `ci` は、どのジョブよりも後に終わるので、結果が出るまでの時間は変わらない。ランナーの時間は、チェックアウトと JSON の検査の 10 秒ほど増える。代わりに、必須の検査をジョブの名前で並べる手間と、直し忘れの危険がなくなる。
- `gate.sh` の名前の一覧は、`needs` と二重に書くことになる。`needs` だけに頼ると、`needs` からジョブを消し忘れたとき（あるいは足し忘れたとき）に、そのジョブの失敗が判定に入らない。二重に書いて検査で一致させるほうを選んだ。
- docs の一覧を grep で作ると、パスを組み立てて読むコード（`"docs" </> name` のような書き方）を拾えない。今はそうしたコードがない。書くときは、パスを一つの文字列で書く約束を CONTRIBUTING.md に置く。
- `docs.yml` を分けても、docs だけの変更で節約できるランナーの時間は増えない。今でも docs だけの変更で走るのは `changes` と `adr` だけだからである。分ける理由は、ドキュメントの検査をコードの CI の取り消しや `release.yml` の呼び出しから切り離すことにある。
- peg-hs のようにワークフローを起動しない方式に比べると、docs だけの変更で `changes` と `ci` の分（合わせて 20 秒ほど）のランナーの時間を余分に使う。必須の検査でマージを守ることを優先した。

## 参考文献

- GitHub Docs, "Troubleshooting required status checks"（パスで起動しなかったワークフローの必須の検査が待ちのまま残ること）. https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/collaborating-on-repositories-with-code-quality-features/troubleshooting-required-status-checks
- GitHub Docs, "Using conditions to control job execution"（`if` で skip したジョブは成功として報告されること）. https://docs.github.com/en/actions/writing-workflows/choosing-when-your-workflow-runs/using-conditions-to-control-job-execution
- Git Documentation, git-diff（`A...B` が共通の祖先から `B` への差分であること）. https://git-scm.com/docs/git-diff
- peg-hs の `.github/workflows/adr.yml` と `.github/workflows/ci.yml`（[peg-hs ADR 0039](https://github.com/tett23/peg-hs/blob/main/docs/adr/0039-faster-ci.md)）. https://github.com/tett23/peg-hs
