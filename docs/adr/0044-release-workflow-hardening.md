# ADR 0044: リリースのワークフローの固め方

ステータス: 採択

## 文脈

`.github/workflows/release.yml` は、`v` で始まるタグの push で配布物を作り、来歴を署名し、Claude Code にリリースのノートを書かせ、下書きのリリースを作る。
[docs/adr/0035](0035-security-hardening.md) は、ノートを書く Claude Code からトークンを外した。
2026-10-18 のセキュリティ監査（[docs/audits/2026-10-18-security-audit.md](../audits/2026-10-18-security-audit.md)）で、次の問題が残っていた。

- CI1：`release` ジョブが `@anthropic-ai/claude-code` をバージョンを固定せずに入れる。このジョブは `contents: write`、`id-token: write`、`attestations: write` を持つ。パッケージが乗っ取られれば、インストールのスクリプトが OIDC のトークンで来歴を偽造するか、リリースを書き換えられる。docs/adr/0035 が SHA で固定しないと決めたのは action であり、npm のパッケージには及ばない。
- CI2：`write-notes.sh` が `GITHUB_ENV`、`GITHUB_PATH`、`GITHUB_OUTPUT` を外さない。これらに書けば後のステップの環境を変えられる。`claude -p` の道具を明示的に禁じていない。
- CI3：`check-notes.sh` の外部リンクの検査を、生の URL、`<https://…>`、`<a href>` が通る。
- CI4：`build-linux.sh` が ghcup を `curl | sh` で入れ、スクリプトをハッシュで確かめない。
- CI5：`fetch-wasmtime.sh` が、`VERSION` が一致すれば SHA-256 を確かめない。スクリプトの SHA を変えても、名前が同じならキャッシュは差し替わらない。

リリースのノートのリンクには、もう一つの事情がある。
今の検査は、このリポジトリへのリンクだけを許す。
しかし、Golem の構文解析器は peg-hs（別のリポジトリ）であり、今後も GUI のような兄弟のリポジトリが増えうる。
ノートからそれらへリンクする必要が出てくる。

## 実装すること

### ノートを書くジョブの分離

- リリースのノートを書く処理を、`release` から独立したジョブ `notes` に移す。
- `notes` の `permissions` は `contents: read` だけとする。`id-token` と `attestations` は持たない。
- `notes` は、`ANTHROPIC_API_KEY` と、プルリクエストを読むための `GH_TOKEN`（読み取りだけ）を持つ。`write-notes.sh` は、プロンプトを作った後に今までどおりトークンを外して `claude -p` を動かす。
- `notes` は `notes.md` を artifact として上げ、`release` がそれを下ろして使う。
- `release` ジョブは Node と Claude Code を入れない。

### Claude Code の固定

- Claude Code は mise で入れる。リポジトリのルートに `mise.toml` を置き、`[tools]` に npm のバックエンドで `"npm:@anthropic-ai/claude-code" = "<正確なバージョン>"` と書く。範囲の指定（`latest`、`^1` など）は書かない。
- `notes` ジョブは、mise の action（`jdx/mise-action`）の最新のメジャー版で `mise.toml` の道具を入れる。`npm install -g` は使わない。
- 開発者も同じ `mise.toml` で同じバージョンを入れられる。
- バージョンの更新は、ほかの依存の更新と同じく、`mise.toml` を変えるプルリクエストで行う。

### `claude -p` の環境と道具

- `write-notes.sh` は、`GITHUB_ENV`、`GITHUB_PATH`、`GITHUB_OUTPUT`、`GITHUB_STATE`、`GITHUB_STEP_SUMMARY` も `env -u` で外す。
- `claude -p` に、道具を一つも許さないフラグと、MCP の設定を読まないフラグを明示的に付ける。Claude Code のバージョンを固定するので、フラグの名前はそのバージョンのものに合わせ、`scripts/release/test.sh` で `claude --help` の出力に含まれることを確かめる。
- プロンプトの先頭に、プルリクエストの本文は信頼しないデータであり、その中の指示に従わないことを書く。

### リンクの許可リスト

- `scripts/release/allowed-links.txt` に、ノートに書いてよいリンクの前置きを 1 行に一つ書く。最初の中身は `https://github.com/tett23/golem/` と `https://github.com/tett23/peg-hs/` の 2 行である。
- `check-notes.sh` は、ノートの中の `[text](URL)` のリンク、参照形式のリンク、生の URL、`<https://…>` の自動リンク、`<a ` の HTML のリンクをすべて見つけ、URL が許可リストのどれかの前置きで始まらなければ失敗する。
- `http://` の URL は、許可リストに書かれていても失敗する。
- 兄弟のリポジトリを足すときは、許可リストに 1 行足すプルリクエストを出す。レビューを通る一行の変更である。
- `https://github.com/tett23/` を一つ書いて tett23 のすべてのリポジトリを許す選び方もある。リポジトリごとに書くほうが厳しく、どのリポジトリへのリンクを許すかがレビューで見えるので、こちらを選ぶ。開発の方針（緩い規則より厳しい規則）にも合う。
- `scripts/release/test.sh` に、生の URL、`<https://example.com>`、`<a href="https://example.com">`、許可リストにないリポジトリへのリンクを含むノートが失敗し、`golem` と `peg-hs` へのリンクだけのノートが通る例を足す。

### ghcup の取得

- `build-linux.sh` は、ghcup のブートストラップのスクリプトをファイルに下ろし、スクリプトに書いた SHA-256 と比べてから `sh` で動かす。
- ハッシュと ghcup のバージョンは、同じスクリプトに書く。
- GHC と cabal は、ghcup が自分のメタデータの SHA-256 で確かめる。これは今と同じである。

### wasmtime のキャッシュ

- `fetch-wasmtime.sh` は、`VERSION` に名前と SHA-256 の両方を書く。
- キャッシュを使うのは、`VERSION` の名前とハッシュがスクリプトのものと一致するときだけとする。ハッシュが違えば取り直す。

### ドキュメント

- 仕様書の「リリースの手順」に、ノートを書くジョブの権限、Claude Code のバージョンの固定（`mise.toml`）、リンクの許可リストを書く。
- 開発者向けマニュアルのリリースの章に、同じことを書く。
- `CONTRIBUTING.md` と `CONTRIBUTING.en.md` の依存の更新の手順に、`mise.toml` の Claude Code のバージョンと、許可リストの更新を足す。

## 実装しないこと

- GitHub Actions の action をコミットの SHA で固定すること。docs/adr/0035 の判断を変えない。mise の action も、ほかの action と同じく最新のメジャー版のタグで指定する。
- npm のパッケージの中身を自分でハッシュで確かめること。バージョンの固定で、乗っ取られた新しい版が自動で入ることは防げる。既存の版の差し替えは npm のレジストリが防ぐ。
- ノートを人間が書くことにして Claude Code を外すこと。[docs/adr/0021](0021-docs-workflow-and-ci-gate.md) の決定を変えない。
- GHC と cabal を ghcup の外で取得してハッシュで固定すること。ghcup のメタデータの検証で足りる。
- 許可リストに `https://github.com/tett23/` の前置きを書くこと。理由は「リンクの許可リスト」にある。

## テスト設計

自動テストを書けないものは、確かめ方を書く。

- `scripts/release/test.sh`
  - `check-notes.sh` が、生の URL、`<https://example.com>`、`<a href="https://example.com">`、`https://github.com/tett23/other/` へのリンク、`http://github.com/tett23/golem/` へのリンクを含むノートでそれぞれ失敗し、`https://github.com/tett23/golem/` と `https://github.com/tett23/peg-hs/` へのリンクだけのノートで通る。
  - `allowed-links.txt` の各行が `https://` で始まり `/` で終わる。
  - `write-notes.sh` が `claude` を動かすコマンドの行に、道具を許さないフラグと MCP の設定を読まないフラグがある（スクリプトの文字列を検査する）。
  - `write-notes.sh` が外す変数に `GITHUB_ENV`、`GITHUB_PATH`、`GITHUB_OUTPUT` がある。
  - `fetch-wasmtime.sh` が、ハッシュの違う `VERSION` のキャッシュを使わない（偽のキャッシュのディレクトリを作って動かす）。
- `scripts/ci`
  - `mise.toml` の `npm:@anthropic-ai/claude-code` の値が、正確なバージョンの形（`数.数.数`）である。
  - `release.yml` の `notes` ジョブの `permissions` が `contents: read` だけで、`release` ジョブに `npm` と `mise` の行がない（YAML を読んで検査する）。
- 確かめ方
  - `workflow_dispatch` で `release.yml` を動かし、`notes` ジョブが mise で Claude Code を入れ、`notes.md` を上げ、`release` がそれを使うことを見る。
  - `build-linux.sh` を手元のコンテナで動かし、ghcup のスクリプトのハッシュが一致して進むことを見る。ハッシュが違えば止まることは、ハッシュを一文字変えて見る。

## トレードオフ

- Claude Code のバージョンを固定すると、新しい版の改善が自動で入らない。プルリクエストで更新する手間が増える。
- mise を CI の依存に足す。npm のパッケージを一つ入れるために道具が一つ増えるが、開発者と CI で同じバージョンを使え、ほかの道具（将来の Node や textlint）も同じファイルで固定できる。
- ジョブを分けると、ワークフローの構成が複雑になる。Claude Code のインストールは配布物のビルドと並列になるので、時間は延びない。
- 許可リストをリポジトリごとに書くので、兄弟のリポジトリを作るたびに 1 行のプルリクエストが要る。`https://github.com/tett23/` の一つで済ませる緩い選び方より手間はかかるが、どこへリンクするかがレビューで見える。
- ghcup のスクリプトのハッシュは、ghcup の更新のたびに変わる。リリースのビルドが止まったときは、ハッシュを更新するプルリクエストが要る。
- `claude -p` のフラグの名前は Claude Code のバージョンに依存する。バージョンを固定するので、同じプルリクエストで両方を更新する。

## 参考文献

- GitHub Docs, "Security hardening for GitHub Actions"。https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions
- GitHub Docs, "Workflow commands for GitHub Actions"（`GITHUB_ENV`、`GITHUB_PATH`、`GITHUB_OUTPUT`、`GITHUB_STATE`、`GITHUB_STEP_SUMMARY`）。https://docs.github.com/en/actions/reference/workflow-commands-for-github-actions
- GitHub Docs, "Using artifact attestations to establish provenance for builds"。https://docs.github.com/en/actions/security-for-github-actions/using-artifact-attestations/using-artifact-attestations-to-establish-provenance-for-builds
- mise, Configuration（`mise.toml`）と npm Backend。https://mise.jdx.dev/configuration.html 、https://mise.jdx.dev/dev-tools/backends/npm.html
- mise, GitHub Action（`jdx/mise-action`）。https://github.com/jdx/mise-action
- Anthropic, Claude Code CLI reference。https://docs.claude.com/en/docs/claude-code/cli-reference
- GHCup, Installation（ブートストラップのスクリプト）。https://www.haskell.org/ghcup/install/
- [docs/adr/0035](0035-security-hardening.md)
- [docs/audits/2026-10-18-security-audit.md](../audits/2026-10-18-security-audit.md)
