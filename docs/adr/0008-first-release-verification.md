# ADR 0008: 最初のプレリリース v0.1.0-rc1 でリリースのワークフローを確かめる

ステータス: 採択

## 文脈

[ADR 0004](0004-binary-distribution-and-release.md) で、リリースのワークフロー（`.github/workflows/release.yml`）と `scripts/release/` のスクリプトを足した。
スクリプトのうち、`check-version.sh`、`notes.sh`、`check-notes.sh`、`licenses.sh` は `scripts/release/test.sh` で CI が検査している。
一方で、次のものはまだ一度も動かしていない。

- `release.yml` そのもの。`ci` の再利用、`version`、`build`、`smoke`、`determinism`、`release` の各ジョブ。
- Alpine のコンテナの中での musl に対する静的なビルド（`scripts/release/build-linux.sh`）。ghcup による GHC 9.10.3 の Alpine 向けの配布物の導入と、musl 向けの wasmtime の C API のリンクを含む。
- `alpine` と `debian:stable-slim` のコンテナの中での配布物の検査（`scripts/release/smoke.sh`）。
- `actions/attest-build-provenance` による来歴の証明。
- Claude Code によるリリースノート（`scripts/release/write-notes.sh`）。リポジトリの秘密情報 `ANTHROPIC_API_KEY` は設定済みである。
- `gh release create` による下書きのリリースと、プレリリースの印。

[ADR 0004](0004-binary-distribution-and-release.md) のテスト設計の「ワークフローをタグなしで試す」は、`workflow_dispatch` での試しと、`v0.1.0-rc1` のタグでの確かめを求めているが、手順の細部と、失敗したときのタグの扱いを決めていない。
リポジトリにはまだタグが一つもなく、`VERSION` は `0.1.0` である。

タグの扱いについて、[CONTRIBUTING.md](../../CONTRIBUTING.md) は `main` の rebase と force push を禁じているが、タグの削除と付け直しについては何も書いていない。
リリースのワークフローは、タグの名前と結び付いた次の状態を作る。

- 来歴の証明は、アーカイブの SHA-256 と、ワークフローを起動したコミットとを結び付ける。
- `notes.sh` と `write-notes.sh` は、前のタグを `git describe --tags --abbrev=0 --match 'v*' <タグ>^` で求める。リリースを作れなかったタグが残っていると、次のタグのリリースノートの範囲がそのタグから始まり、利用者に届いていない変更がノートから抜ける。

監査の記録の置き場所について、[CONTRIBUTING.md](../../CONTRIBUTING.md) は「監査の記録や性能計測のスナップショットは、`docs/` の下に用途ごとのディレクトリを作って置く。これらもコミットしたあとは変更しない。」と定めているが、まだそのようなディレクトリはない。

## 実装すること

### 前提

- [ADR 0007](0007-third-party-licenses.md) の実装を `main` にマージしてから、`v0.1.0-rc1` のタグを付ける。`THIRD_PARTY_LICENSES/` が musl、libffi、libgcc、libstdc++、wasmtime のクレートの文書を欠いたまま、配布物をプレリリースとして公開しないためである。
- `workflow_dispatch` での試し（後述の手順 2）は、[ADR 0007](0007-third-party-licenses.md) の実装の前に行ってよい。配布物を公開しないためである。試しで得たリンクマップは、[ADR 0007](0007-third-party-licenses.md) の対応表を作る材料になる。

### 手順

1. `VERSION` を `0.1.0-rc1` に書き換えるブランチ（`release/v0.1.0-rc1`）を `main` から切り、プルリクエストを作る。全パッケージの cabal ファイルの `version` はすでに `0.1.0` なので、変えるのは `VERSION` だけである。CI の `release-scripts` ジョブが二つの一致を検査する。
2. 同じブランチで `gh workflow run release.yml --ref release/v0.1.0-rc1` を実行する。`ci`、`version`、`build`、`smoke`、`determinism` が通り、`release` が実行されず（`if` で除かれる）、GitHub Releases に何も作られないことを確かめる。`version` の出力が `version=0.1.0-rc1` と `tag=dev-<コミットの先頭 12 桁>` であることも確かめる。三つの `archive-<プラットフォーム>` の成果物を `gh run download` で取得し、後述の確かめる項目のうち配布物に関するものを手元で行う。
3. 2 が失敗したら、原因を直す変更を別のプルリクエストで `main` に入れ、`release/v0.1.0-rc1` を `main` の上に rebase して 2 をやり直す。マージ前のブランチの rebase は [CONTRIBUTING.md](../../CONTRIBUTING.md) で許されている。仕様を変える修正には ADR を書く。
4. `main` に含まれないコミットのタグでリリースが作られないことを確かめる。使い捨てのブランチ（`release-test/off-main`）を切り、`VERSION` だけを `0.1.0-test1` にしたコミットを作り、そのコミットに `v0.1.0-test1` のタグを付けて push する。`VERSION` とタグは一致するので `check-version.sh` は通り、`git merge-base --is-ancestor` の検査で `version` ジョブが失敗し、`build` 以降と `release` が実行されないことを確かめる。確かめたら、ワークフローの残りのジョブ（`ci`）を取り消し、タグとブランチを削除する。
5. 1 のプルリクエストを `main` に no-ff でマージする。
6. マージのコミットに軽量のタグを付けて push する。

   ```sh
   git fetch origin
   git tag v0.1.0-rc1 <マージのコミット>
   git merge-base --is-ancestor v0.1.0-rc1 origin/main
   git push origin v0.1.0-rc1
   ```

   注釈付きのタグにしないのは、ワークフローの `GITHUB_SHA` と `gh release create --verify-tag` がタグの指すコミットだけを使い、タグのオブジェクトの持つ情報を使わないためである。
7. ワークフローの終了を待つ。すべてのジョブが通れば、プレリリースの印の付いた下書きのリリースができている。
8. 後述の確かめる項目をすべて行い、結果を記録に書く。
9. 下書きのリリースノートを読み、分類やまとめ方を手で直す。
10. 確かめる項目がすべて通ったら、GitHub の Releases の画面で下書きを公開する。公開したものはプレリリースとして残す。
11. 記録をプルリクエストで `main` に入れる。

### 確かめる項目

配布物に関する項目は、`gh release download v0.1.0-rc1 --dir <空のディレクトリ>` で下書きから取得したもので確かめる。
`aarch64-macos` は手元の Mac で、Linux の二つは手元の Docker の `alpine` と `debian:stable-slim` のコンテナで確かめる。
Docker で `x86_64-linux` を動かせない場合は、`smoke` ジョブのログで代え、その旨を記録に書く。

| 番号 | 項目 | 確かめ方 | 期待 |
|---|---|---|---|
| 1 | 添付のファイル | `gh release view v0.1.0-rc1 --json assets` | `golem-v0.1.0-rc1-{x86_64-linux,aarch64-linux,aarch64-macos}.tar.gz`、`SHA256SUMS`、`gmp-<版>.tar.xz` の五つだけがある |
| 2 | SHA256SUMS | `sha256sum -c SHA256SUMS`（macOS では `shasum -a 256 -c`） | 三つとも `OK` |
| 3 | 来歴の証明 | 三つのアーカイブそれぞれに `gh attestation verify <アーカイブ> --repo tett23/golem` | 通り、証明の示すコミットがタグのコミットと一致する |
| 4 | アーカイブの中身 | `tar -tzf` | `golem-v0.1.0-rc1-<プラットフォーム>/` の下に `golem`、`LICENSE`、`THIRD_PARTY_LICENSES/`、`BUILDINFO` だけがある |
| 5 | `golem --version` | 展開した `golem --version` | 標準出力が `golem 0.1.0-rc1` の一行で、終了コードが 0 |
| 6 | `golem new` | 空のディレクトリで `golem new book` と `golem new --language en book-en` | 終了コードが 0 で、フォントを取得して雛形ができる |
| 7 | `golem build` | 6 の二つのプロジェクトで `golem build` | 終了コードが 0 で、PDF、HTML、EPUB、テキストの四つのターゲットができる |
| 8 | 出力の決定性 | `determinism` ジョブのログ | 三つの配布物と CI の出力が一致している |
| 9 | 依存 | Linux では `file golem` と `ldd golem`、macOS では `otool -L golem` と `codesign --verify golem` | Linux は静的、macOS は `/usr/lib/` と `/System/Library/` の下だけに依存し、署名の検証が通る |
| 10 | macOS の隔離の属性 | ブラウザで取得したアーカイブを展開し、README の Installation の手順（`xattr -d com.apple.quarantine golem`）に従う | 手順のとおりに起動できる |
| 11 | THIRD_PARTY_LICENSES | `THIRD_PARTY_LICENSES/README` と、`build` ジョブが上げたリンクマップ | リンクマップに現れた構成要素の文書がすべてある（[ADR 0007](0007-third-party-licenses.md)） |
| 12 | BUILDINFO | 三つの `BUILDINFO` | コミットがタグのコミットと一致し、GHC が 9.10.3、wasmtime が musl 向けまたは macOS 向けの 49.0.2 の配布物の名前である |
| 13 | GMP のソース | `gmp-<版>.tar.xz` の版と、`BUILDINFO` の `gmp:` | 一致する |
| 14 | リリースノートの作り手 | `release` ジョブの要約 | `Claude Code (claude-opus-5-5) wrote the notes, and they passed check-notes.sh.` があり、`notes.sh` の一覧への切り替えが起きていない |
| 15 | リリースノートの中身 | 下書きの本文を読む | 英語で、`## Added` などの見出しに分かれ、`## Unsorted` がなく、リポジトリの最初のコミットからの全プルリクエストが絶対リンクで現れ、追加した ADR がタグの版への絶対リンクで現れ、末尾に `## Verifying the downloads` がある |
| 16 | プレリリースの印 | `gh release view v0.1.0-rc1 --json isDraft,isPrerelease` | 公開の前は `isDraft` と `isPrerelease` がともに `true`。公開の後は `isPrerelease` が `true` |
| 17 | 公開の操作 | ワークフローのログ | ワークフローが公開していない |

14 で切り替えが起きていた場合は、要約に書かれた理由を記録に書き、ノートを手で分類して書く。
この場合もリリースそのものは失敗としない。
[ADR 0004](0004-binary-distribution-and-release.md) が、AI の失敗でリリースを止めないと決めているためである。

### 失敗したときのタグと下書きの扱い

タグの名前は、一度 push したら別のコミットに付け直さない。
付け直すと、同じ名前が二つのコミットを指すことになり、先に取得した人の手元のタグと食い違い、最初の実行で作った来歴の証明が別のコミットを指したまま残るためである。

失敗の種類ごとに、次のとおり扱う。

- コードを変えずに直る失敗（ランナーの不調、ネットワークの一時的な失敗、API の制限）は、`gh run rerun <実行の ID> --failed` で失敗したジョブだけをやり直す。タグはそのままにする。前の実行で下書きのリリースがすでにできていて `gh release create` が失敗した場合は、下書きを `gh release delete v0.1.0-rc1 --yes` で削除してからやり直す。`--cleanup-tag` は付けない。
- コードの変更を要する失敗は、下書きのリリースがあれば削除し、タグを `git push origin :refs/tags/v0.1.0-rc1` と `git tag -d v0.1.0-rc1` で削除する。直す変更をプルリクエストで `main` に入れ、`VERSION` を `0.1.0-rc2` にするプルリクエストから手順をやり直す。`v0.1.0-rc1` の名前は二度と使わない。
- 確かめる項目が通らなかった場合も、コードの変更を要する失敗として扱う。
- タグを削除するのは、そのタグのリリースを一度も公開していない場合に限る。公開したリリースのタグは削除しない。

リリースを作れなかったタグを削除するのは、残すと次のタグのリリースノートの範囲がそのタグから始まるためである。
削除したタグの名前を使わないことで、名前と来歴の証明の対応は一意に保たれる。

[CONTRIBUTING.md](../../CONTRIBUTING.md) と `CONTRIBUTING.en.md` の「タグとリリース」に、次の約束を加える。

- push したタグを別のコミットに付け直さない。
- 公開していないリリースのタグは、ワークフローが失敗したとき、または配布物の確かめが通らなかったときに限り削除してよい。削除したタグの名前は再び使わず、プレリリースの識別子を進める（`rc1` の次は `rc2`）。
- 公開したリリースのタグは削除しない。
- コードを変えずに直る失敗は、タグを変えずにワークフローをやり直す。

### 記録

確かめた結果を `docs/audits/releases/v0.1.0-rc1.md` に書く。
`docs/audits/` は監査の記録を置くディレクトリとし、リリースの確かめの記録はその下の `releases/` に、タグの名前をファイル名にして置く。
記録はコミットしたあとは変更しない。
`v0.1.0-rc1` を削除して `rc2` でやり直した場合も、`v0.1.0-rc1.md` には失敗の記録を書いて残し、`v0.1.0-rc2.md` を別に作る。

記録には次のことを書く。

- 対象のタグ、タグのコミット、ワークフローの実行の URL（`workflow_dispatch` の試しと、手順 4 の試しを含む）。
- 三つの `BUILDINFO` の内容。
- 確かめる項目の表に、結果（通った、通らなかった、代わりの方法で確かめた）と、通らなかったものの原因を加えたもの。
- 手で直したリリースノートの差分の要約。
- 公開した日時、または削除した日時と理由。
- 見つけた問題と、それを扱うプルリクエストか ADR へのリンク。

記録のファイルは日本語で書き、ほかのドキュメントと同じ規範に従う。

### ドキュメント

- [CONTRIBUTING.md](../../CONTRIBUTING.md) と `CONTRIBUTING.en.md` の「タグとリリース」に、上の約束と、確かめた結果を `docs/audits/releases/` に記録することを書く。
- [仕様書](../specifications.md)の「リリースの手順」の節に、最初のプレリリースで確かめた記録へのリンクを、記録をコミットしたプルリクエストで加える。

## 実装しないこと

- 確かめる項目の自動化。`gh release download` と `gh attestation verify` を使う確かめのスクリプトは書けるが、一度確かめるための手順にスクリプトを足すより、次のリリースで同じ項目を繰り返す必要が見えてから足す。
- `v0.1.0-rc1` の公開の自動化。[ADR 0004](0004-binary-distribution-and-release.md) のとおり、公開は人が行う。
- `release.yml` の変更。確かめの中で不具合が見つかれば、その修正は別のプルリクエストで行い、仕様を変えるものには別の ADR を書く。
- 正式のリリース `v0.1.0` の時期の決定。
- 監査の記録を adr-guard のような仕組みで変更できなくすること。今は約束とレビューで守る。

## テスト設計

この ADR は手順を決めるもので、自動テストを足さない。
次の確かめで、手順と約束が実際に機能することを示す。

- 手順 2 の `workflow_dispatch` の実行で、`release` 以外のすべてのジョブが通り、GitHub Releases に何も作られないこと（`gh release list` が空のまま）。
- 手順 4 の `v0.1.0-test1` で、`version` ジョブが「the tag v0.1.0-test1 is not on main」の誤りで失敗し、`release` ジョブが実行されないこと。
- 手順 6 から 10 で、確かめる項目の 1 から 17 がすべて通ること。
- 記録の `docs/audits/releases/v0.1.0-rc1.md` が、上の「記録」の節の項目をすべて持つこと。プルリクエストのレビューで確かめる。
- CONTRIBUTING.md の日本語版と英語版の「タグとリリース」に、同じ約束が書かれていること。プルリクエストのレビューで確かめる。

## トレードオフ

タグの名前を使い捨てにするので、失敗するたびにプレリリースの識別子が進み、`rc1` が存在しないまま `rc2` が出ることがある。
名前の連続よりも、名前と来歴の証明が一対一に対応することを優先する。

公開していないタグの削除を許すので、push したタグを取得した人の手元に、削除したタグが残りうる。
最初のタグが付く時点で利用者はいないので、実害は小さいと判断する。

`workflow_dispatch` の試し、`main` に含まれないタグの試し、本番のタグの三回ワークフローを動かすので、`ci` を含むビルドが三回走り、時間と Actions の利用枠を使う。
最初のリリースで一度だけの費用である。

確かめる項目を手で行うので、確かめる人によって手順がぶれうる。
記録に確かめ方を書き残すことで、次のリリースで同じ手順を繰り返せるようにし、繰り返しが重くなった時点で自動化を検討する。

[ADR 0007](0007-third-party-licenses.md) の実装を待ってからタグを付けるので、最初のプレリリースはその分遅れる。
ライセンスの文書を欠いた配布物を公開するよりよい。
