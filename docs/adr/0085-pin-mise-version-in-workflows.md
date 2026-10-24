# ADR 0085: CI とリリースのワークフローで、mise の版と SHA-256 を固定する

ステータス: 採択

## 文脈

[ADR 0044](0044-release-workflow-hardening.md) は、リリースのノートを書く Claude Code を mise で入れると決めた。
`mise.toml` は Claude Code の版を正確に固定する（2.1.292）。
`release.yml` の `notes` ジョブは、`jdx/mise-action` でこの `mise.toml` の道具を入れ、`ANTHROPIC_API_KEY` を持って `write-notes.sh` を動かす（[release.yml の 197 行から 206 行](https://github.com/tett23/golem/blob/19948d11bb3064fb2950f351ab8b16e1e2744523/.github/workflows/release.yml#L197-L206)）。

Claude Code の版は固定したが、それを入れる mise 自身の版は固定していない。
2026-10-24 のセキュリティ監査（[docs/audits/2026-10-24-security-audit.md](../audits/2026-10-24-security-audit.md)）の CI2 は、この点を挙げた。

### action の振る舞い

`notes` ジョブが使う `jdx/mise-action@v5` の版で、action の定義（`action.yml`）を読んだ。
`v5` のタグは、この ADR を書いた時点でコミット 82a612c5ab8bcda7cc5db6b7e81a8e7584c3dc6e を指す。

- `version`：入れる mise の版。省けば、`minimum_release_age` を満たす最新の安定版を入れる。
- `minimum_release_age`：`version` を省いたときだけ使われる。既定は 24 時間である。
- `sha256`：mise の実行ファイルの SHA-256。与えれば、入れた実行ファイルと比べ、違えば失敗する。

`notes` ジョブは、`with:` に `cache: false` だけを渡す。
`version` を省いているので、ジョブを動かすたびに、24 時間より前に出た最新の mise を入れる。

action のソース（`src/index.ts`、同じコミット）も読んだ。
`version` を省いても、action は配布物を mise の署名つきの一覧（packslip か、minisign の署名を持つ `SHASUMS256.txt`）で確かめる。
`sha256` を与えると、この署名の確かめを飛ばし、展開した実行ファイルを与えた値と比べる。
`version` を与えると、配布物は GitHub の release からだけ取り、mise.jdx.dev の CDN には落ちない。

### 何が守れていないか

署名の確かめは、mise の配布の仕組みが正しく動いていることを前提にする。
mise の release の仕組みが乗っ取られ、署名つきの新しい版が出れば、24 時間の後に `notes` ジョブはその版を入れる。
mise は `notes` ジョブの中で動き、同じジョブの後のステップは `ANTHROPIC_API_KEY` を環境に持つ。
mise の実行ファイルは、`GITHUB_ENV` や `GITHUB_PATH` を書いて後のステップを変えられる。

版を固定すれば、新しい版は、版を上げるプルリクエストを通らない限り入らない。
SHA-256 を固定すれば、固定した版の配布物が差し替えられても、署名の鍵ごと乗っ取られていても、入れずに止まる。

[docs/adr/0035](0035-security-hardening.md) は、action をコミットの SHA ではなくタグで指定すると決めた。
この ADR はその判断を変えない。
action が取得する道具の版は、action の指定とは別の問題である。
[ADR 0062](0062-epubcheck-from-release-with-cache.md) は、epubcheck の配布物を版と SHA-256 で固定した（`ci.yml` の `EPUBCHECK_VERSION` と `EPUBCHECK_SHA256`）。
mise も同じ形で固定する。

### `ci.yml` の `release-scripts` ジョブ

`ci.yml` の `release-scripts` ジョブも、同じ action を同じ形で使う（[ci.yml の 374 行から 378 行](https://github.com/tett23/golem/blob/19948d11bb3064fb2950f351ab8b16e1e2744523/.github/workflows/ci.yml#L374-L378)）。
このジョブは秘密を持たない（[scripts/ci/test.sh の 861 行](https://github.com/tett23/golem/blob/19948d11bb3064fb2950f351ab8b16e1e2744523/scripts/ci/test.sh#L861) が検査する）。
ただし [ADR 0058](0058-run-skipped-checks-in-ci.md) は、このジョブを `notes` ジョブと同じ形で mise を動かすものと決めている（[scripts/ci/test.sh の 859 行](https://github.com/tett23/golem/blob/19948d11bb3064fb2950f351ab8b16e1e2744523/scripts/ci/test.sh#L859)）。
`notes` だけを固定すると、二つのジョブが違う版の mise で Claude Code を入れ、`release-scripts` が確かめた版と `notes` が使う版がずれる。
このジョブも同じ版と SHA-256 で固定する。

## 実装すること

### 固定する値

- mise の版と、その版の Linux の x86-64 の実行ファイルの SHA-256 を、ワークフローの最上位の `env` に書く。`release.yml` と `ci.yml` の両方に、同じ値で書く。

  ```yaml
  env:
    # mise, which installs the pinned Claude Code of mise.toml, at an exact
    # version and the SHA-256 of its linux-x64 binary (docs/adr/0085)
    MISE_VERSION: "<版>"
    MISE_SHA256: "<64 桁の 16 進数>"
  ```

- `release.yml` は `ci.yml` を `workflow_call` で呼ぶが、呼んだ側の `env` は呼ばれた側に渡らない。そのため二つのファイルに書き、テストで一致を確かめる。
- 版は、実装する時点の最新の安定版とする。`mise.toml` の Claude Code の版と同じく、正確な版を書き、範囲は書かない。
- SHA-256 は、action が比べる値、つまり展開した後の `mise` の実行ファイルの値である。配布物の圧縮ファイルの値ではない。実装するときに、その版の `mise-v<版>-linux-x64.tar.zst` を GitHub の release から取り、署名つきの `SHASUMS256.txt` で確かめてから展開し、実行ファイルの SHA-256 を求める。同じ版の圧縮しない配布物（`mise-v<版>-linux-x64`）の `SHASUMS256.txt` の値と一致するかも確かめ、プルリクエストに書く。

### action の入力

- `jdx/mise-action` を使うすべてのステップ（`release.yml` の `notes` と、`ci.yml` の `release-scripts`）の `with:` に、次の二行を足す。`cache: false` は残す。

  ```yaml
  version: ${{ env.MISE_VERSION }}
  sha256: ${{ env.MISE_SHA256 }}
  ```

- SHA-256 は Linux の x86-64 の実行ファイルの値なので、二つのジョブの `runs-on` は今のとおり `ubuntu-24.04` とする。ランナーを変えるときは、SHA-256 も変える。
- action は、これまでどおり最新のメジャー版のタグで指定する（[docs/adr/0035](0035-security-hardening.md)、[ADR 0044](0044-release-workflow-hardening.md)）。

### 版の上げ方

- mise の版は、Claude Code の版と同じく、二つのワークフローの `MISE_VERSION` と `MISE_SHA256` を変えるプルリクエストで上げる。プルリクエストには、SHA-256 を求めた手順を書く。
- 上げたプルリクエストの CI で `release-scripts` が通れば、action が新しい SHA-256 で実行ファイルを確かめたことになる。

### ADR のステータス

- [ADR 0044](0044-release-workflow-hardening.md) のステータスの行の末尾に、「、mise の版と SHA-256 の固定は [ADR 0085](0085-pin-mise-version-in-workflows.md)」を足す。

### ドキュメント

- 仕様書の「リリースの手順」の、ノートを書く Claude Code の段落に、mise の版と SHA-256 を二つのワークフローの `env` で固定することを書き、この ADR へのリンクを付ける。
- 開発者向けマニュアルの「リリースの手順」の章（`manual-dev/part2/13-release.gm`）の mise の段落と、「CI のジョブ」の章（`manual-dev/part2/11-ci-jobs.gm`）の `release-scripts` の段落に、同じことを書く。
- `CONTRIBUTING.md` と `CONTRIBUTING.en.md` の依存の更新の手順に、mise の版と SHA-256 の上げ方を足す。
- 利用者向けマニュアルの付録 E と `docs/diagnostics.md` は、diagnostic が変わらないので変えない。

## 実装しないこと

- action をコミットの SHA で固定すること。[docs/adr/0035](0035-security-hardening.md) の判断を変えない。
- 版だけを固定し、SHA-256 を固定しないこと。版だけでは、固定した版の配布物の差し替えを、署名の仕組みに頼って防ぐことになる。
- `minimum_release_age` を延ばして、版を固定しないこと。待つ期間が延びるだけで、新しい版を自動で入れることは変わらない。
- mise を使わずに Claude Code を入れ直すこと。[ADR 0044](0044-release-workflow-hardening.md) の判断を変えない。
- 版の更新を自動にすること（Renovate など）。このリポジトリは依存の更新を手のプルリクエストで行う。
- 開発者の手元の mise の版を固定すること。手元の mise は API キーを持つジョブで動かない。

## テスト設計

`scripts/ci/test.sh` の「release.yml and mise.toml」の検査（[876 行から](https://github.com/tett23/golem/blob/19948d11bb3064fb2950f351ab8b16e1e2744523/scripts/ci/test.sh#L876-L893)）に次を足す。
19948d11 では、二つのワークフローに `MISE_VERSION` も `version:` もないので、どれも失敗する。
テストを先に書き、失敗することを確かめてから、ワークフローを変える。

- `release.yml` と `ci.yml` の最上位の `env` に、`MISE_VERSION` が正確な版の形（`^  MISE_VERSION: "[0-9]{4}\.[0-9]{1,2}\.[0-9]+"$`）で、`MISE_SHA256` が 64 桁の小文字の 16 進数の形で、それぞれちょうど一つあること。
- 二つのファイルの `MISE_VERSION` と `MISE_SHA256` が、それぞれ同じ値であること。
- 二つのファイルの `uses: jdx/mise-action@` の行の数と、その後に続く `with:` の中の `version: ${{ env.MISE_VERSION }}` と `sha256: ${{ env.MISE_SHA256 }}` の組の数が一致し、0 でないこと。`jdx/mise-action` を使うステップを足して固定を忘れれば、ここで失敗する。
- `release.yml` の `notes` と `ci.yml` の `release-scripts` の `runs-on` が `ubuntu-24.04` であること。

検査の書き方は、[ADR 0069](0069-lint-scripts-bypassed-by-plain-rewrites.md) と [ADR 0077](0077-shell-test-assertions-that-pass-vacuously.md) に従う。
`grep` が何も見つけないときに通る形にせず、数を数えて比べる。
macOS の BSD の道具でも動くように書き、`scripts-macos` ジョブで確かめる（[ADR 0079](0079-shell-tests-on-macos.md)）。

自動テストで確かめられないことは、実装の後に次の手順で確かめる。

- 実装のプルリクエストの CI で、`release-scripts` ジョブのログに、固定した版の mise を GitHub から取り、与えた SHA-256 で確かめた行があること。
- `MISE_SHA256` の一桁を変えたコミットを一時的に作り、`release-scripts` が SHA-256 の不一致で失敗することを見る。このコミットはマージしない。
- 実装の後の最初のリリース（v0.1.0-rc3）で、`notes` ジョブが同じ版の mise で Claude Code を入れ、ノートを書くこと。

## トレードオフ

- mise の版を上げる手間が増える。SHA-256 を求める手順も要る。Claude Code の版と epubcheck の版も同じ手間をかけているので、手順が一つ増えるだけである。
- 固定した版の mise に不具合や脆弱性が見つかっても、自動では上がらない。上げるかどうかはプルリクエストで決める。
- 同じ値を二つのファイルに書く。テストが一致を確かめるので、片方だけを変えれば CI で止まる。
- `sha256` を与えると、action は署名つきの一覧での確かめを飛ばす。固定した値と比べるほうが強いので、守りは弱まらない。ただし、SHA-256 を求めるときに署名つきの一覧で確かめることを、手順として守る必要がある。

## 参考文献

- jdx/mise-action, `action.yml`（`version`、`minimum_release_age`、`sha256`、`fetch_from_github` の入力）、コミット 82a612c5ab8bcda7cc5db6b7e81a8e7584c3dc6e（`v5`）。https://github.com/jdx/mise-action/blob/82a612c5ab8bcda7cc5db6b7e81a8e7584c3dc6e/action.yml
- jdx/mise-action, `src/index.ts`（`sha256` による実行ファイルの確かめと、署名つきの一覧の確かめ）、同じコミット。https://github.com/jdx/mise-action/blob/82a612c5ab8bcda7cc5db6b7e81a8e7584c3dc6e/src/index.ts
- jdx/mise, Releases（配布物と `SHASUMS256.txt`）。https://github.com/jdx/mise/releases
- GitHub Docs, Contexts reference（`env` の文脈を使える場所）。https://docs.github.com/en/actions/reference/workflows-and-actions/contexts
- [docs/adr/0035](0035-security-hardening.md)
- [ADR 0044](0044-release-workflow-hardening.md)
- [ADR 0058](0058-run-skipped-checks-in-ci.md)
- [ADR 0062](0062-epubcheck-from-release-with-cache.md)
- [docs/audits/2026-10-24-security-audit.md](../audits/2026-10-24-security-audit.md)
