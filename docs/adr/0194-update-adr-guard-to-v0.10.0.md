# ADR 0194: adr-guard を v0.10.0 に上げ、ADR の番号の重複と修飾子付きの参照を検査する

ステータス: 採択

## 文脈

このリポジトリは、コミット済みの ADR と記録の変更を [adr-guard](https://github.com/tett23/adr-guard) で拒否している。
検査は `.githooks/pre-commit` と、CI の `docs.yml` の `adr` ジョブで行う。
[ADR 0048](0048-update-adr-guard-to-v0.8.3.md) で、`adr` ジョブの action を `tett23/adr-guard@v0.8.3`（`allow-status: true`、`allow-links: true`）にした。

その後、tett23/adr-guard は [v0.9.0](https://github.com/tett23/adr-guard/releases/tag/v0.9.0)、[v0.9.1](https://github.com/tett23/adr-guard/releases/tag/v0.9.1)、[v0.10.0](https://github.com/tett23/adr-guard/releases/tag/v0.10.0) を出した。

- v0.9.0 は、同じディレクトリで番号が重複した ADR を報告する `adr-guard check-numbers` と、重複を直す `adr-guard renumber [--dry-run]` を加えた。
  action は既定で `check-numbers` を実行し、重複があると CI が失敗する。
  振りなおしのコミットは `--allow-renumber`（action の入力 `allow-renumber`、既定は false）で許す。
  根拠は tett23/adr-guard の ADR「[重複したADRの番号の修復](https://github.com/tett23/adr-guard/blob/main/docs/adr/0018-repair-duplicate-adr-numbers.md)」。
- v0.9.1 は、`renumber` の誤報を直した。
- v0.10.0 は、修飾子付きの ADR の参照を解釈する。
  `ADR NNNN` の直前の語（空白一つで区切る）が修飾子になる。
  `/` を含む語はディレクトリ（`docs/adr ADR 0003`）、`-` を含む語はモジュール（`golem-driver ADR 0015` は `docs/golem-driver/adr/` の番号 0015 の ADR）を表す。
  それ以外の語は、その名前のモジュールの ADR のディレクトリがあるときだけ修飾子になる。
  修飾子はリンクのテキストに含める（`[golem-driver ADR 0015](../golem-driver/adr/0015-vertical-dashes.md)`）。
  `links` と pre-commit は、ディレクトリか ADR が無い修飾子付きの参照、リンク先が修飾子の ADR と異なるリンク、リンクの外に出た修飾子（`golem-driver [ADR 0015](...)`）を報告し、`links --fix` は直せるものを直す。
  シンボリックリンクの `.md` は検査しない。
  根拠は tett23/adr-guard の ADR「[モジュールで修飾したADRの参照](https://github.com/tett23/adr-guard/blob/main/docs/adr/0019-module-qualified-adr-references.md)」と「[シンボリックリンクの文書を飛ばす](https://github.com/tett23/adr-guard/blob/main/docs/adr/0020-skip-symlinked-documents.md)」。

このリポジトリは `docs/adr/` のほかに `docs/<モジュール>/adr/` を多く持ち、`golem-driver ADR 0015` の形の参照が多い。
v0.10.0 の `adr-guard links` を main で実行すると、8 つのファイルの 21 か所で、修飾子がリンクの外にある参照、リンク先が修飾子の ADR と異なるリンク、修飾子付きのリンクのない参照、対象の無い修飾子付きの参照を報告する。
たとえば `docs/adr/0172-continuous-double-dashes.md` の `golem-driver [ADR 0015](0015-regex-styles.md)` は、[golem-driver ADR 0015](../golem-driver/adr/0015-vertical-dashes.md) ではなく [docs/adr ADR 0015](0015-regex-styles.md) を指している。
また、`docs/adr/0039-svg-active-content-in-html-and-epub.md` の「[peg-hs ADR 0039](https://github.com/tett23/peg-hs/blob/main/docs/adr/0039-faster-ci.md)」への参照は、ほかのリポジトリの ADR を指すので、このリポジトリに対象が無い。

手元の adr-guard はすでに v0.10.0 に更新されている。
`adr-guard check-numbers` は main で重複を報告しない。

## 実装すること

- `.github/workflows/docs.yml` の `adr` ジョブの action を `uses: tett23/adr-guard@v0.10.0` にする。
  入力 `allow-status: true`、`allow-links: true`、`base`、`head` はそのまま保つ。
  `check-numbers` の入力は付けず、既定のとおり番号の重複も検査する。
  コメントの ADR の参照にこの ADR を加える。
- `.githooks/pre-commit` は `exec adr-guard pre-commit --allow-status --allow-links` のまま保ち、コメントの ADR の参照にこの ADR を加える。
- `README.md` の「Git フックの有効化」の節で、必要な adr-guard を v0.10.0 以降にし、`cargo install` の `--tag` を `v0.10.0` にする。
  修飾子付きの参照の規則と、CI の `adr` ジョブが番号の重複も検査することを書き、action の版を v0.10.0 にする。
- `CONTRIBUTING.md` と `CONTRIBUTING.en.md` の開発環境の節の版を v0.10.0 にする。
  ADR の書き方の節に、修飾子付きの参照の規則と、番号の重複を `adr-guard check-numbers` で確かめ、`adr-guard renumber` で直せることを書く。
- `manual-dev/` の adr-guard の版（第二部の「ビルドとテスト」「ADR」「CI のジョブ」の章）を v0.10.0 にする。
  第二部の「ADR」の章の参照の規則と adr-guard の命令の一覧を、`CONTRIBUTING.md` と同じ内容に合わせる。
- [ADR 0048](0048-update-adr-guard-to-v0.8.3.md) のステータスを、action の版についてこの ADR に置き換えられたことを示す `採択→…は [ADR 0194](...)` の形にする。
- `adr-guard links --fix --include-committed` を実行し、直らない参照は手でリンクを付ける。
  ほかのリポジトリの ADR への修飾子付きの参照は、リンクのテキストごとそのリポジトリの ADR への絶対リンクにする。
  リンクの修正は、実装とは別のコミットにする。
- `adr-guard links`、`adr-guard check-status`、`adr-guard check-numbers` が終了コード 0 で終わる状態にする。

## 実装しないこと

- `.githooks/pre-commit` のコマンドと、action の `allow-renumber` の入力の追加。
  番号の重複を直すときだけ、一時的に `--allow-renumber` を付ける。
- 番号の重複を防ぐ仕組み（番号の予約など）。重複は CI の `check-numbers` で見つけ、`adr-guard renumber` で直す。
- 修飾子の無い参照の書き換え。既存の文書の書き方は、v0.10.0 が報告するものだけを直す。
- 記録の保護の変更。
- Claude Code の hook の変更。Claude Code の hook は全体の設定（`~/.claude/settings.json`）にあり、このリポジトリでは管理しない。
- 手元の adr-guard の更新の自動化。
- action の指定方法の変更。これまでどおりバージョンのタグで指定する。

## テスト設計

- 手元の adr-guard（v0.10.0）で、次を確かめる。
  - 変更をステージして `.githooks/pre-commit` が終了コード 0 で終わる（各コミットで hook が通る）。
  - `adr-guard links`、`adr-guard check-status`、`adr-guard check-numbers` が終了コード 0 で終わる。
  - コミットの後、`adr-guard check-range origin/main HEAD --allow-status --allow-links` が終了コード 0 で終わる。
- `.github/workflows/docs.yml` が YAML として読めることを確かめる。
- マニュアルと文書の検査（`scripts/manual/test.sh`、`scripts/manual/check-updated.sh origin/main HEAD`、`scripts/ci/docs-refs.sh`、`scripts/ci/textlint.sh origin/main`）が通ることを確かめる。
- 変更のプルリクエストの CI で、`adr` ジョブが v0.10.0 の action で実行され、成功することを確かめる。

## トレードオフ

- 修飾子をリンクのテキストに含める規則が加わり、ADR を書く人が守ることが一つ増える。
  その代わり、モジュールの ADR を指すつもりで別のディレクトリの ADR にリンクする誤りを、adr-guard が見つける。
- `links --fix --include-committed` は、コミット済みの ADR のリンクのテキストとリンク先を書きかえる。
  ステータスの行以外の変更だが、リンクだけの変更なので `--allow-links` で許される。
- 別々のブランチで同じ番号の ADR を作ると、後からマージした側で CI が失敗する。
  このリポジトリは並行して多くのブランチで ADR を書くので、失敗は起こりうる。
  見落としたまま番号が重複するよりよいと判断した。
- 手元の adr-guard が v0.10.0 より古いと、pre-commit が修飾子付きの参照を検査せず、CI で初めて失敗する。README と CONTRIBUTING に必要なバージョンを書いて補う。

## 参考文献

- tett23/adr-guard の ADR「[重複したADRの番号の修復](https://github.com/tett23/adr-guard/blob/main/docs/adr/0018-repair-duplicate-adr-numbers.md)」
- tett23/adr-guard の ADR「[モジュールで修飾したADRの参照](https://github.com/tett23/adr-guard/blob/main/docs/adr/0019-module-qualified-adr-references.md)」
- tett23/adr-guard の ADR「[シンボリックリンクの文書を飛ばす](https://github.com/tett23/adr-guard/blob/main/docs/adr/0020-skip-symlinked-documents.md)」
- tett23/adr-guard の [v0.9.0 のリリース](https://github.com/tett23/adr-guard/releases/tag/v0.9.0)、[v0.9.1 のリリース](https://github.com/tett23/adr-guard/releases/tag/v0.9.1)、[v0.10.0 のリリース](https://github.com/tett23/adr-guard/releases/tag/v0.10.0)
