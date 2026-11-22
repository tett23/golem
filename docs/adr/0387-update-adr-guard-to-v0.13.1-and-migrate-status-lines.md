# ADR 0387: adr-guard を v0.13.1 に上げ、ADR のステータスの行を新しい形に移す

Status: accepted

## 文脈

このリポジトリは、コミット済みの ADR と記録の変更を [adr-guard](https://github.com/tett23/adr-guard) で拒否している。
検査は `.githooks/pre-commit` と、CI の `docs.yml` の `adr` ジョブで行う。
[ADR 0194](0194-update-adr-guard-to-v0.10.0.md) で `adr` ジョブの action を v0.10.0 にし、[ADR 0296](0296-pin-every-github-action-by-commit-sha.md) で action をコミットの SHA と版の注釈で指定する形にした。
いまの指定は `tett23/adr-guard@624df60fe8956ef52b3a275198ee938175324496 # v0.10.0` である。

その後、tett23/adr-guard は [v0.11.0](https://github.com/tett23/adr-guard/releases/tag/v0.11.0)、[v0.12.0](https://github.com/tett23/adr-guard/releases/tag/v0.12.0)、[v0.13.0](https://github.com/tett23/adr-guard/releases/tag/v0.13.0)、[v0.13.1](https://github.com/tett23/adr-guard/releases/tag/v0.13.1) を出した。
変更は次のとおりである。

- v0.11.0 は、Codex の PreToolUse の hook の `adr-guard codex-hook` を加えた（[tett23/adr-guard ADR 0021](https://github.com/tett23/adr-guard/blob/v0.13.1/docs/adr/0021-codex-hook.md)）。
- v0.12.0 は、ステータスの行の新しい形と、状態遷移の検査を加えた（[tett23/adr-guard ADR 0022](https://github.com/tett23/adr-guard/blob/v0.13.1/docs/adr/0022-status-transitions.md)）。
  新しい形は `Status: <トークン>` である。
  トークンは `proposed`、`accepted`、`accepted-pending`、`rejected`、`discarded`、`deprecated`、または `superseded [<変更の JSON 配列>]` のいずれかである。
  変更は `{"part":<部分名か null>,"by":[<リポジトリのルートからのパス>]}` の形のオブジェクトである。
  新しい ADR は、最初に `Status: proposed` でコミットする。
  追加した ADR と、ステータスの行を変えた ADR には、新しい形が要る。
  pre-commit と `check-range` は状態遷移を検査し、この検査は `--allow-status` でも `ADR_GUARD_ALLOW` でも免除されない（[tett23/adr-guard ADR 0022](https://github.com/tett23/adr-guard/blob/v0.13.1/docs/adr/0022-status-transitions.md) の 129 行め）。
  これまでの形（`ステータス: 採択` など。以下「旧形式」）の行は、そのまま読める。
  あわせて、旧形式の行を新しい形に移すスクリプト `scripts/migrate-adr-status`（以下「移行のスクリプト」）と、修正の連なりをたどる `adr-guard trace`（[tett23/adr-guard ADR 0023](https://github.com/tett23/adr-guard/blob/v0.13.1/docs/adr/0023-trace-amendments.md)）を加えた。
  移行のスクリプトは adr-guard のソースにあり、リリースのアーカイブには入らない。
- v0.13.0 は、移行のスクリプトに `--dry-run` を加え、移せない ADR を全件数えるようにした（[tett23/adr-guard ADR 0024](https://github.com/tett23/adr-guard/blob/v0.13.1/docs/adr/0024-migration-dry-run-and-error-count.md)）。
  一件でも移せない ADR があると、`--write` は何も書かない。
  あわせて、`superseded-pending`、変更の `kind`（`replace`、`supplement`、`note`）と `note`、`https://` の修正先を加えた（[tett23/adr-guard ADR 0025](https://github.com/tett23/adr-guard/blob/v0.13.1/docs/adr/0025-extend-canonical-status-amendments.md)）。
  `trace --list` は 6 列を出し、`unimplemented` は `superseded-pending` の ADR も出す。
  旧形式の参照の読み方も広げた（[tett23/adr-guard ADR 0026](https://github.com/tett23/adr-guard/blob/v0.13.1/docs/adr/0026-read-more-legacy-references.md)、[tett23/adr-guard ADR 0027](https://github.com/tett23/adr-guard/blob/v0.13.1/docs/adr/0027-read-legacy-replaced-status.md)）。
- v0.13.1 は、移行のスクリプトが作る部分名を直した（[tett23/adr-guard ADR 0028](https://github.com/tett23/adr-guard/blob/v0.13.1/docs/adr/0028-fix-legacy-part-names.md)）。
  旧形式の部分名から、`ADR NNNN` の直前の修飾子、先頭の `。`、末尾の `→` を除く。
  参照の後ろに部分名の続きがある行と、括弧が部分名をまたぐ行は、`<パス>:<行>: 部分名を決められません: …` と報告し、移せない ADR として数える。
  この不具合は、このリポジトリで v0.13.0 の移行のスクリプトを試したときに見つかった（「調査した事項」の「v0.13.0 の移行のスクリプトの出力の誤り」）。

手元の adr-guard は、すでに v0.13.1 である。
手元の pre-commit は新しい ADR に新しい形を求めるので、この ADR も `Status: proposed` で書く。
一方、CI の action は v0.10.0 のままなので、CI は状態遷移を検査しない。
手元と CI で検査が食い違わないよう、CI を v0.13.1 に上げる。

ステータスの行を新しい形に移す理由は二つある。
一つめに、旧形式の行は「採択→○○は [ADR NNNN](...)」のように文で書くので、どの部分がどの ADR で変わったかをプログラムで読み取りにくい。
実際、v0.13.0 の移行のスクリプトは、このリポジトリの旧形式の行の一部を読み違えた。
二つめに、旧形式のままの ADR のステータスを変えるコミットは、そのたびに行を新しい形で書き直す必要がある。
一度にすべてを移せば、以後の ADR のステータスの変更は、どれも新しい形の中での遷移になる。

## 調査した事項

この節のコマンドは、特に断らない限り、`origin/main`（`9a9d5da2`）から作ったこのブランチの worktree のルートで実行した。

### 手元の adr-guard と、いまの状態

- `adr-guard -V` は `adr-guard 0.13.1` を出した。
- `adr-guard check-status`、`adr-guard check-numbers`、`adr-guard links` は、この ADR を書く前に、いずれも終了コード 0 で終わった（このときの手元の adr-guard は 0.13.0）。
- `ls docs/adr/*.md docs/*/adr/*.md | wc -l` は 572 を出した（この ADR を除く）。
- `adr-guard unimplemented | wc -l` は 39 を出した。
- `rg -n 'adr-guard' .github/` は、`.github/workflows/docs.yml:35` の `uses: tett23/adr-guard@624df60fe8956ef52b3a275198ee938175324496 # v0.10.0` の 1 か所だけを出した。
  入力は `allow-status: true`、`allow-links: true`、`base`、`head` である。
- adr-guard のリポジトリで `git rev-parse v0.13.1^{commit} v0.10.0^{commit}` は、`ab55769152ed0f8a3465ee3435a2df43ab9d067f` と `624df60fe8956ef52b3a275198ee938175324496` を出した。
- `git show v0.13.1:action.yml` の入力は、`base`、`head`、`version`、`allow-status`、`allow-links`、`links`、`check-status`、`check-numbers`、`allow-renumber` だった。
  いまの `docs.yml` が使う入力は、どれも v0.13.1 にある。
- v0.10.0 の `src/status.rs` は、`const LABELS: [&str; 2] = ["ステータス:", "Status:"];` で、行頭が `Status:` の行もステータスの行として数える。
  そのため、`Status: proposed` のこの ADR は、v0.10.0 の CI の `check-status` も通る。

### 版を書いている場所

`rg -n 'v?0\.10\.0|624df60' --hidden -g '!.git' -g '!docs/adr/**' -g '!docs/*/adr/**' .` のうち、adr-guard の版を指すものは次のとおりだった。
ほかの一致は、Rust と Haskell と npm の依存の版である。

- `.github/workflows/docs.yml:35`（action の SHA と注釈）
- `README.md:343`、`README.md:344`、`README.md:372`
- `CONTRIBUTING.md:21`、`CONTRIBUTING.en.md:21`
- `manual-dev/part2/08-build-test.gm:22`、`manual-dev/part2/08-build-test.gm:27`
- `manual-dev/part2/09-adr.gm:107`、`manual-dev/part2/09-adr.gm:125`
- `manual-dev/part2/11-ci-jobs.gm:357`
- `docs/ci-timings/2026-11-09-ci-critical-path-and-download-failures.md:308`（計測の記録なので変えない）

`.githooks/pre-commit` は版を書かず、コメントに ADR の参照を並べている。
`.claude/` と `.codex/` の下に、リポジトリが管理するファイルはない（`git ls-files .claude .codex` は何も出さなかった）。

### 旧形式の行を前提にしている場所

`rg -n 'ステータス' --hidden -g '!docs/adr/**' -g '!docs/*/adr/**' .` で、行頭の `ステータス:` を前提にする記述とコードを探した。
主なものは次のとおりである。

- `CLAUDE.md:15`、`README.md:350`、`README.md:355`、`CONTRIBUTING.md:58`、`CONTRIBUTING.md:71`、`CONTRIBUTING.md:74`、`CONTRIBUTING.md:82`、`CONTRIBUTING.en.md:58`、`CONTRIBUTING.en.md:71`、`CONTRIBUTING.en.md:81`、`docs/specifications.md:20`、`manual-dev/part2/09-adr.gm:58`、`manual-dev/part2/09-adr.gm:80`、`manual-dev/part2/09-adr.gm:86`
- `scripts/release/notes.sh:82` の `awk '/^ステータス:/ { print; exit }'` と、`scripts/release/notes.sh:85` の `sed 's/^ステータス://; ...'`
- `scripts/release/write-notes.sh:61` の `/^ステータス:/ && !s { print; s = 1 }`
- `docs/specifications.md:8599` と `docs/specifications.md:8602`（変更の一覧の `## ADRs whose status changed` の定義）
- `tools/textlint/config/adr.js:8` のコメント

リリースノートのスクリプトは、行頭が `ステータス:` の行しか読まない。
そのため、移行の後は `## ADRs whose status changed` の後のステータスが空になり、プロンプトからステータスの行が落ちる。

### v0.13.1 の移行のスクリプトの試し

移行のスクリプトは、adr-guard の v0.13.1 のコミット（`ab55769`）で `examples/migrate_adr_status` をビルドした実行ファイルを使った。
adr-guard のソースの `scripts/migrate-adr-status` は、この example を `cargo run` で動かすラッパーである。

`migrate_adr_status --dry-run` は終了コード 1 で終わり、最後に `移行できる: 553件、移行済み: 1件、移行できない: 19件` を出した。
移行済みの 1 件は、新しい形で書いたこの ADR である。
`--dry-run` は何も書かなかった（実行の後の `git status --short` は、この ADR のほかに何も出さなかった）。

移せない 19 件と、理由は次のとおりだった。

| ADR | 理由 |
|---|---|
| `docs/adr/0037-ci-build-job-speedup.md` | 注記または未知のステータス |
| `docs/adr/0139-plugin-diagnostic-code-starts-with-letter.md` | 注記または未知のステータス |
| `docs/adr/0141-smaller-ghc-and-hackage-index-caches.md` | 注記または未知のステータス |
| `docs/adr/0151-explain-uses-plugin-code-rule.md` | 注記または未知のステータス |
| `docs/golem-cli/adr/0009-explain-several-codes.md` | 注記または未知のステータス |
| `docs/golem-fmt/adr/0003-lone-cr-to-lf.md` | 注記または未知のステータス |
| `docs/golem-pdf/adr/0003-pdf-x-4-validator.md` | 注記または未知のステータス |
| `docs/golem-pdf/adr/0011-cff-fontfile3-subtype.md` | 注記または未知のステータス |
| `docs/golem-layout/adr/0034-line-breaks-between-japanese-characters-in-inline-code.md` | 注記または未知のステータス |
| `docs/adr/0351-prove-parser-formatter-round-trips.md` | 注記または未知のステータス |
| `docs/adr/0044-release-workflow-hardening.md` | 参照の後ろに部分名の続きがある |
| `docs/adr/0182-external-links.md` | 参照の後ろに部分名の続きがある |
| `docs/adr/0183-tagged-pdf-and-pdf-a.md` | 参照の後ろに部分名の続きがある |
| `docs/adr/0209-line-breaking-invariants-by-exhaustive-small-inputs.md` | 参照の後ろに部分名の続きがある |
| `docs/adr/0221-check-iso-15930-7-for-link-annotations-before-rc4.md` | 参照の後ろに部分名の続きがある |
| `docs/golem-fmt/adr/0001-formatter.md` | 参照の後ろに部分名の続きがある |
| `docs/golem-pdf/adr/0004-crop-marks-and-bleed.md` | 参照の後ろに部分名の続きがある |
| `docs/golem-pdf/adr/0006-cid-system-info.md` | 参照の後ろに部分名の続きがある |
| `docs/golem-font/adr/0002-subsetting-and-embedding.md` | 括弧が部分名をまたぐ |

表の上から 8 件は、「採択」の後に読点で修正を続ける形である（`採択、… は [ADR 0062](…)` など）。
`docs/golem-layout/adr/0034` は括弧の中に注記を持ち、`docs/adr/0351` は句点の後に修正を書いている。
「参照の後ろに部分名の続きがある」8 件は、参照の後に `→` で次の修正を続けるか（`docs/adr/0182`、`docs/adr/0221`）、参照の後に「で実装」「で加えた」のような語か括弧の中の参照（`docs/golem-pdf/adr/0004`）を続けるか、部分名の中に修正先でない ADR へのリンクを持つ（`docs/adr/0209`）。

### 手で書く行と移行の試し

一時ディレクトリに、この worktree の `docs/` を写した Git のリポジトリを作り、手順を通しで試した。

1. 19 件のステータスの行を、「実装すること」の行に書き換えた。
   `adr-guard pre-commit --allow-status --allow-links`、コミットの後の `adr-guard check-range HEAD~1 HEAD --allow-status --allow-links`、`adr-guard links` は、どれも終了コード 0 で終わった。
2. `--dry-run` は `移行できる: 553件、移行済み: 20件、移行できない: 0件` を出して終了コード 0 で終わった。
3. `--write` は 553 件を書いた。
   その後、`rg -l '^ステータス:' docs | wc -l` は 0 を出した。
4. pre-commit、`check-range HEAD~2 HEAD --allow-status --allow-links`、`check-status`、`links`、`check-numbers` は、どれも終了コード 0 で終わった。
   `adr-guard unimplemented | wc -l` は、移行の前と同じ 39 を出した。
5. 「テスト設計」の部分名の検査の 2 つのコマンドと、末尾が空白か `→` の部分名を探す `rg -o '"part":"[^"]*"' docs | rg ' "$|→"$'` は、どれも何も出さなかった。

同じ一時リポジトリにこの ADR をコミットした後で、[ADR 0194](0194-update-adr-guard-to-v0.10.0.md) の行を「前の更新の ADR のステータス」の節の行に書き換えると、pre-commit と `check-range HEAD~1 HEAD --allow-status --allow-links` は終了コード 0 で終わった。

v0.13.0 の手元の adr-guard で、`docs/golem-layout/adr/0034` の新しい行に `adr-guard trace` を実行すると、`wrap-mark` の既定の注記を `note` の辺として、ほかの四つを `replace` の辺として出した。

この ADR の草稿では、ステータスの行の例をコードブロックの中に行頭から書くと、`adr-guard check-status` が `ステータスの行が2つ以上あります` を報告した。
adr-guard は、ADR のコードブロックの中の行も、行頭が `Status:` ならステータスの行に数える。
そのため、この ADR は例を箇条書きと表の中のインラインのコードに置いている。

### v0.13.0 の移行のスクリプトの出力の誤り

v0.13.1 の前に、v0.13.0 のコミット（`0096636`）でビルドした移行のスクリプトを同じ worktree で試した。
`--dry-run` は `移行できる: 562件、移行済み: 0件、移行できない: 10件` を出し、移せない 10 件は上の表の上から 10 件だった。
その出力の部分名 433 個には、元の行と意味の違うものがあった。
以下で修飾子は、[ADR 0194](0194-update-adr-guard-to-v0.10.0.md) のとおり、`golem-driver ADR 0026` の `golem-driver` のように ADR の参照の直前に置くモジュールの名前かディレクトリを指す。

- 109 個の部分名が、末尾に「は」と修飾子を含んだ（`注の本文をまとめる場所と一覧の見出しは golem-driver` など）。
- 句点の後に続く修正は、部分名が `。` で始まった（`。パーサーと fmt の往復の予算` など 3 個）。
- 部分名の中にある ADR のリンクを、修正として読んだ（`docs/adr/0209` の [golem-layout ADR 0016](../golem-layout/adr/0016-ellipsis-before-full-stop.md) への参照）。
- 括弧の中の参照で、部分名が括弧の途中で切れた（`docs/golem-font/adr/0002`）。

この誤りは、adr-guard の pre-commit、`check-range`、`check-status` では見つからなかった。
v0.13.1 は、上の四つの誤りを、部分名の作り方の修正か、移せない ADR としての報告で扱う（[tett23/adr-guard ADR 0028](https://github.com/tett23/adr-guard/blob/v0.13.1/docs/adr/0028-fix-legacy-part-names.md)）。

## 実装すること

### CI の action

- `.github/workflows/docs.yml` の `adr` ジョブの action を、`uses: tett23/adr-guard@ab55769152ed0f8a3465ee3435a2df43ab9d067f # v0.13.1` にする。
  コミットの SHA と版の注釈の形は、[ADR 0296](0296-pin-every-github-action-by-commit-sha.md) のとおりに保つ。
  入力 `allow-status: true`、`allow-links: true`、`base`、`head` はそのまま保つ。
  `version` の入力は付けず、action と同じ版の adr-guard を使う。
- 同じステップのコメントに、状態遷移の検査を加え、ADR の参照にこの ADR を加える。

### ステータスの行の移行

移行には、adr-guard の v0.13.1 のソースの `scripts/migrate-adr-status` を使い、このリポジトリのルートで動かす。
次の順に行う。
`--write` は一件でも移せない ADR があると何も書かないので、手で書く 19 件を先にする。

1. 下の表の 19 件のステータスの行を、表の新しい行に書き換える。
2. `scripts/migrate-adr-status --dry-run` を動かし、`移行できない: 0件` を確かめる。
3. `scripts/migrate-adr-status --write` を動かし、残りの ADR を移す。
4. `rg -l '^ステータス:' docs` が何も出さないことを確かめる。

手で書く行は、元の行の部分名、修正先、参照の後ろの語を、次の決まりで写したものである。

- 修正先は、リンク先をリポジトリのルートからのパスにしたものとする。
- 参照の後ろの語（「で実装」「で加えた」「golem-driver に移した」「の J3 と J5」）は、その変更の `note` にする（[tett23/adr-guard ADR 0026](https://github.com/tett23/adr-guard/blob/v0.13.1/docs/adr/0026-read-more-legacy-references.md) の `で消した` の例と同じ扱い）。
- 修正先を持たない注記は、`kind` が `note` で `by` が空の変更にする。
- 部分名の中の、修正先でない ADR へのリンクは、リポジトリのルートからのパスの文字列にする。
- 一つの部分名を二つの ADR が変えた行（`docs/golem-fmt/adr/0001` の「移行の段階」）は、同じ部分名の変更を二つ並べる。
- 括弧の中の参照（`docs/golem-pdf/adr/0004` の「`golem check` が四つのターゲットを検査すること」）は、独立した変更にする。
- `採択（未実装）` の行に修正を書いたもの（`docs/adr/0221`、`docs/adr/0351`）は `superseded-pending` にする。

| ADR | 新しい行 |
|---|---|
| `docs/adr/0037-ci-build-job-speedup.md` | `Status: superseded [{"by":["docs/adr/0062-epubcheck-from-release-with-cache.md"],"part":"epubcheck の入れ方と apt の時間切れの再試行"}]` |
| `docs/adr/0139-plugin-diagnostic-code-starts-with-letter.md` | ``Status: superseded [{"by":["docs/adr/0151-explain-uses-plugin-code-rule.md"],"part":"`golem explain` の判定"}]`` |
| `docs/adr/0141-smaller-ghc-and-hackage-index-caches.md` | ``Status: superseded [{"by":["docs/adr/0152-remove-hackage-index-tar-gz-before-cache.md"],"part":"`01-index.tar.gz` の除き方"}]`` |
| `docs/adr/0151-explain-uses-plugin-code-rule.md` | `Status: superseded [{"by":["docs/adr/0164-explain-dedup-and-plugin-code-messages.md"],"part":"重複の除き方と形の誤りの文"}]` |
| `docs/golem-cli/adr/0009-explain-several-codes.md` | `Status: superseded [{"by":["docs/adr/0151-explain-uses-plugin-code-rule.md"],"part":"プラグインのコードの形の誤りの文"},{"by":["docs/adr/0164-explain-dedup-and-plugin-code-messages.md"],"part":"プラグインのコードの重複の除き方"},{"by":["docs/adr/0176-e-code-shape-message.md"],"part":"形の誤りの文"}]` |
| `docs/golem-fmt/adr/0003-lone-cr-to-lf.md` | ``Status: superseded [{"by":["docs/golem-fmt/adr/0004-fmt-without-arguments-fixes-cr.md"],"part":"引数なしの `golem fmt` が CR を含む原稿を読む手順"}]`` |
| `docs/golem-pdf/adr/0003-pdf-x-4-validator.md` | `Status: superseded [{"by":["docs/golem-pdf/adr/0012-x4-forbidden-names-in-found-order.md"],"part":"禁止の名前の並び"}]` |
| `docs/golem-pdf/adr/0011-cff-fontfile3-subtype.md` | `Status: superseded [{"by":["docs/golem-pdf/adr/0013-renamed-cff-table-is-g08003.md"],"part":"テスト設計の二つめの項目と、輪郭の表のないフォントの扱い"}]` |
| `docs/golem-layout/adr/0034-line-breaks-between-japanese-characters-in-inline-code.md` | 表の後に示す |
| `docs/adr/0351-prove-parser-formatter-round-trips.md` | `Status: superseded-pending [{"by":["docs/adr/0354-remove-leading-boms-from-table-files.md"],"part":"不変条件 9 の先頭の連続 BOM"}]` |
| `docs/adr/0044-release-workflow-hardening.md` | ``Status: superseded [{"by":[],"kind":"note","note":"docs/adr/0021 ではなく docs/adr/0004-binary-distribution-and-release.md にある","part":"「実装しないこと」の、ノートを人間が書く案を退けた根拠の決定"},{"by":["docs/adr/0058-run-skipped-checks-in-ci.md"],"part":"CI で `claude --help` を確かめること"},{"by":["docs/adr/0085-pin-mise-version-in-workflows.md"],"part":"mise の版と SHA-256 の固定"},{"by":["docs/adr/0296-pin-every-github-action-by-commit-sha.md"],"part":"action を SHA で固定しないこと"}]`` |
| `docs/adr/0182-external-links.md` | ``Status: superseded [{"by":["docs/adr/0211-record-what-implementations-decided-found-by-the-review-of-2026-11-08.md"],"part":"散文スロットが二つ以上の `[link]` の G02038"},{"by":["docs/adr/0350-omit-page-link-annotations-from-pdf-x-4.md"],"part":"PDF/X-4 の本文リンク注釈"}]`` |
| `docs/adr/0183-tagged-pdf-and-pdf-a.md` | ``Status: superseded [{"by":["docs/adr/0216-drawn-content-missing-from-the-structure-tree-is-an-error.md"],"part":"構造の木にない内容の扱い"},{"by":["docs/adr/0211-record-what-implementations-decided-found-by-the-review-of-2026-11-08.md"],"part":"CI の ICC プロファイル、最初の見出しの G07103 のメッセージ、校正のコメントの行"},{"by":["docs/adr/0215-ref-number-and-ref-title-as-reference.md"],"note":"で実装","part":"`[ref-number]` と `[ref-title]` の `Reference`"},{"by":["docs/adr/0227-draw-the-glyphs-of-a-box-in-the-order-of-its-text.md"],"part":"一つの葉の中の字形の順"},{"by":["docs/adr/0244-take-verapdf-off-the-critical-path-of-ci.md"],"part":"CI の `verapdf` の待ち方"}]`` |
| `docs/adr/0209-line-breaking-invariants-by-exhaustive-small-inputs.md` | `Status: superseded [{"by":["docs/golem-layout/adr/0028-kinsoku-across-spaces-and-explicit-hyphens.md"],"part":"（L4 の読み方）"},{"by":["docs/adr/0211-record-what-implementations-decided-found-by-the-review-of-2026-11-08.md"],"part":"正規形と縦組みのテストの段、上限の変数、正規形の比べ方、docs/golem-layout/adr/0016-ellipsis-before-full-stop.md の回帰の述語、L7 の 3 行の段落"},{"by":["docs/adr/0222-line-breaking-points-the-invariants-did-not-decide.md"],"part":"（不変条件の L5、L6、L9、L11、L13 の読み方）"},{"by":["docs/golem-layout/adr/0032-drop-word-spaces-before-the-end-of-a-paragraph.md"],"part":"（空の最後の行を判定する不変条件 T1）"},{"by":["docs/adr/0272-discretionary-hyphens-hyphenation-exceptions-and-no-break.md"],"part":"（L8 と L9 の広げ方）"}]` |
| `docs/adr/0221-check-iso-15930-7-for-link-annotations-before-rc4.md` | `Status: superseded-pending [{"by":["docs/adr/0226-move-the-iso-15930-7-check-to-before-v1.md"],"part":"照合の期限"},{"by":["docs/adr/0350-omit-page-link-annotations-from-pdf-x-4.md"],"part":"PDF/X-4 の本文リンク注釈"}]` |
| `docs/golem-fmt/adr/0001-formatter.md` | ``Status: superseded [{"by":["docs/adr/0005-character-and-paragraph-styles.md"],"note":"で加えた","part":"移行の段階"},{"by":["docs/golem-fmt/adr/0002-remove-verse-migration.md"],"note":"で外した","part":"移行の段階"},{"by":["docs/golem-parser/adr/0010-ruby-slash-escape-and-table-cell-breaks.md"],"part":"エスケープの規則の出力の不変の確かめ方"},{"by":["docs/golem-fmt/adr/0003-lone-cr-to-lf.md"],"part":"単独の CR の扱い"},{"by":["docs/golem-fmt/adr/0004-fmt-without-arguments-fixes-cr.md"],"part":"引数なしの `golem fmt` が CR を含む原稿を読む手順"}]`` |
| `docs/golem-pdf/adr/0004-crop-marks-and-bleed.md` | ``Status: superseded [{"by":["docs/golem-pdf/adr/0007-registration-crop-marks.md"],"part":"トンボの色"},{"by":["docs/golem-pdf/adr/0010-golem-check-g0702-and-template-bleed.md"],"part":"`golem check` が G07002 を出す条件"},{"by":["docs/golem-project/adr/0004-font-file-check-per-target.md"],"part":"`golem check` が四つのターゲットを検査すること"}]`` |
| `docs/golem-pdf/adr/0006-cid-system-info.md` | ``Status: superseded [{"by":["docs/golem-driver/adr/0030-ligature-text-layer.md"],"note":"で加えた","part":"ToUnicode で表せないクラスタに ActualText を使うこと"},{"by":["docs/golem-driver/adr/0036-combining-characters.md"],"part":"異体字セレクタを前の字に付ける処理を結合文字に広げたこと"},{"by":["docs/golem-pdf/adr/0011-cff-fontfile3-subtype.md"],"part":"CFF のフォントの `FontFile3` の形"}]`` |
| `docs/golem-font/adr/0002-subsetting-and-embedding.md` | ``Status: superseded [{"by":["docs/golem-pdf/adr/0006-cid-system-info.md"],"part":"`CIDSystemInfo` と異体字セレクタの ToUnicode"},{"by":["docs/golem-driver/adr/0030-ligature-text-layer.md"],"note":"golem-driver に移した","part":"ToUnicode を作る処理"},{"by":["docs/golem-pdf/adr/0011-cff-fontfile3-subtype.md"],"part":"`FontFile3` の `Subtype`"}]`` |

`docs/golem-layout/adr/0034` の新しい行は、次の 1 行である。
括弧の中の注記は `kind` が `note` の変更にし、`の J3 と J5` は置換の変更の `note` にする。

- ``Status: superseded [{"by":[],"kind":"note","note":"`\"⏎\"`（U+23CE）とした。二つのマニュアルのコードの書体の Noto Sans JP と Source Code Pro が U+21A9 の字形を持たず、Noto Sans JP が U+23CE を持つため。`↩` は和文の字のクラスに入り、Noto Sans JP で描くので、その書体が字形を持ち、同じく改行を表す記号の U+23CE を選んだ","part":"`wrap-mark` の既定"},{"by":["docs/golem-layout/adr/0036-record-what-the-implementation-of-0034-decided.md"],"part":"改行の印の幅で行があふれる候補の活きている節点、トレードオフの節の印の文、C2 の a_あ の文"},{"by":["docs/golem-layout/adr/0042-draw-the-wrap-mark-of-inline-code-small-and-light.md"],"part":"印の描き方、大きさ、位置、色"},{"by":["docs/golem-layout/adr/0045-break-inline-code-after-hyphens-and-full-stops-to-avoid-loose-lines.md"],"note":"の J3 と J5","part":"不変条件の C3 と C4"},{"by":["docs/adr/0257-record-what-the-audit-of-the-layout-adrs-of-2026-11-09-found.md"],"part":"golem-typeset のテストの置き場所と書体"}]``

移行は、ほかの変更と別のコミットにする。
移行のコミットのメッセージには、使った adr-guard のコミットの SHA を書く。

### 前の更新の ADR のステータス

[ADR 0194](0194-update-adr-guard-to-v0.10.0.md) のステータスを、CI の action の版についてこの ADR に修正されたことを示す行にする。
部分名は、[ADR 0048](0048-update-adr-guard-to-v0.8.3.md) が [ADR 0194](0194-update-adr-guard-to-v0.10.0.md) に修正されたときの「CI の action の版」に倣う。

- `Status: superseded [{"by":["docs/adr/0387-update-adr-guard-to-v0.13.1-and-migrate-status-lines.md"],"part":"CI の action の版"}]`

### リリースノートのスクリプト

- `scripts/release/notes.sh` の `status_line` は、行頭が `ステータス:` または `Status:` の最初の行を返す。
  `status_of` は、その行から `ステータス:` または `Status:` を除き、前後の空白を除いた文字列を返す。
- `scripts/release/write-notes.sh` の `adrs` は、題名の行と、行頭が `ステータス:` または `Status:` の最初の行をプロンプトに入れる。
- 新しい形の修正先はリポジトリのルートからのパスで、Markdown のリンクではないので、`scripts/release/absolute-links.sh` は変えない。
- `scripts/release/test.sh` に、下の「テスト設計」のテストを足す。

### 文書

- `.githooks/pre-commit` は `exec adr-guard pre-commit --allow-status --allow-links` のまま保ち、コメントの ADR の参照にこの ADR を加える。
- `README.md` の「Git フックの有効化」の節で、必要な adr-guard を v0.13.1 以降にし、`cargo install` の `--tag` を `v0.13.1` にする。
  ステータスの行の説明を、行頭が `Status:` の新しい形と、pre-commit と CI の `adr` ジョブが状態遷移を検査することに書き換える。
  CI の `adr` ジョブの action の版を v0.13.1 にし、「CI のジョブ」の節の `adr` の説明に状態遷移の検査を加える。
- `CONTRIBUTING.md` と `CONTRIBUTING.en.md` の開発環境の節の版を v0.13.1 にする。
  ADR の雛形のステータスを `Status: proposed` にし、ステータスのトークンの一覧、`superseded` の変更の書き方、状態遷移の検査、`adr-guard trace` を書く。
- `CLAUDE.md` のステータスの行の項目を、行頭が `Status:` の新しい形と、状態遷移の検査に書き換える。
- `docs/specifications.md` の ADR の規則（20 行め）を新しい形に書き換え、新しい ADR は `Status: proposed` で始めることと、状態遷移の検査を加える。
  変更の一覧の `## ADRs whose status changed` の定義（8599 行めと 8602 行め）を、行頭が `ステータス:` または `Status:` の行に書き換える。
- `manual-dev/` の adr-guard の版（第二部の「ビルドとテスト」「ADR」「CI のジョブ」の章）を v0.13.1 にする。
  第二部の「ADR」の章の雛形、「ステータス」の節、adr-guard の命令の一覧を、`CONTRIBUTING.md` と同じ内容に合わせる。
  「CI のジョブ」の章の `adr` の説明（表と本文）に、状態遷移の検査を加える。
- `tools/textlint/config/adr.js` のコメントのステータスの行の例を `Status: proposed` にする。
- `adr-guard links --fix` を実行する。

## 実装しないこと

- `.githooks/pre-commit` のコマンドの変更。
- Codex の hook（v0.11.0 の `adr-guard codex-hook`）の追加。
  このリポジトリは Codex の設定を管理しない。
- Claude Code の hook の変更。
  Claude Code の hook は全体の設定（`~/.claude/settings.json`）にあり、このリポジトリでは管理しない。
- action の指定の形の変更。
  [ADR 0296](0296-pin-every-github-action-by-commit-sha.md) のとおり、コミットの SHA と版の注釈で指定する。
- adr-guard 以外の action の版の更新。
- 移行のスクリプトの、このリポジトリへの取り込み。
  移行は一度だけ行うので、adr-guard のソースのものを使う。
- 部分名の言い回しの統一や書き直し。
  手で書く 19 件のほかは、移行のスクリプトの出力をそのまま書く。
- リリースノートで、移行だけで変わったステータスの行を `## ADRs whose status changed` から除くこと（「トレードオフ」の節を参照）。
- 計測の記録（`docs/ci-timings/` など）の版の記述の変更。

## 不変条件

この ADR が振る舞いを決めるのは、リリースノートのスクリプトのステータスの行の読み方だけである。
CI の action の版、移行の手順、文書の更新は設定と手順なので、不変条件ではなく「テスト設計」の確かめ方で扱う。

1. `notes.sh` の `status_line REV PATH` は、`REV` の `PATH` のうち、行頭が `ステータス:` または `Status:` の最初の行をそのまま返す。そのような行がなければ空を返す。
2. `notes.sh` の `status_of LINE` は、`LINE` の先頭の `ステータス:` または `Status:` を一つだけ除き、前後の空白を除いた文字列を返す。
3. `notes.sh` は、範囲で変更された ADR のうち、前のタグとタグで `status_line` が異なるものだけを `## ADRs whose status changed` に並べる（行頭の語が違うだけでも異なるとみなす）。
4. `write-notes.sh` のプロンプトの各 ADR には、題名の行と、行頭が `ステータス:` または `Status:` の最初の行が入り、ほかの行は入らない。

境界の入力は次のとおりである。

| 入力（ADR のステータスの行） | `status_line` | `status_of` |
|---|---|---|
| `ステータス: 採択` | `ステータス: 採択` | `採択` |
| `Status: accepted` | `Status: accepted` | `accepted` |
| `Status:accepted`（コロンの後に空白がない） | `Status:accepted` | `accepted` |
| `Status:  accepted-pending `（前後に空白） | そのまま | `accepted-pending` |
| `Status:`（値が空） | `Status:` | 空 |
| ステータスの行がない | 空 | 空 |
| `Status: superseded [{"by":["docs/adr/0010-status.md"],"part":"x"}]` | そのまま | `superseded [{"by":["docs/adr/0010-status.md"],"part":"x"}]` |
| 前のタグで `ステータス: 採択`、タグで `Status: accepted` | 二つは異なる | `採択` と `accepted` |
| 前のタグとタグで同じ `Status: accepted` | 同じ | 並ばない |
| 本文に `Status: accepted` を含む引用があり、ステータスの行が先にある | 先の行 | 先の行の値 |

## テスト設計

### リリースノートのスクリプト

`scripts/release/test.sh` に、次のテストを先に足し、いまのスクリプトで失敗することを確かめてから実装する。
テストの名前には、不変条件の番号を `S1` から `S4` の形で入れる（[ADR 0246](0246-bound-the-prompt-of-the-release-notes.md) の `I4` から `I6` と区別するため）。

- S1、S2：一時リポジトリに、上の境界の表の各行を持つ ADR を置き、前のタグとタグで行を変え、`notes.sh` の `## ADRs whose status changed` の各行の前後のステータスが表の `status_of` と一致する。
- S3：前のタグで `ステータス: 採択`、タグで `Status: accepted` の ADR は並び、前のタグとタグで同じ `Status: accepted` の ADR は並ばない。
- S4：`write-notes.sh` のプロンプトに、`Status:` の行を持つ ADR の題名とステータスの行が入り、本文の目印の行が入らない。

### 移行

- 移行の後に、`rg -l '^ステータス:' docs` が何も出さず、`rg -c '^Status:' -g '*.md' docs/adr docs/*/adr` の合計が ADR の数と一致する。
- 移行の後に、`adr-guard unimplemented` の ADR の集合が、移行の前の集合と一致する（`superseded-pending` になる `docs/adr/0221` と `docs/adr/0351` を含む）。
- 移行の後の部分名に、v0.13.0 の移行のスクリプトの出力の誤りが残らない。
  次のコマンドが、どれも何も出さないことを確かめる。
  - `rg -o '"part":"[^"]*は ?(Golem|docs/adr|golem-[a-z0-9-]+)"' docs`
  - `rg -o '"part":"[、。）]' docs`
- 移行の差分（`git diff` の `-ステータス:` と `+Status:` の組）を、本人がレビューする。

### adr-guard と CI

- 手元の adr-guard（v0.13.1）で、次を確かめる。
  - 変更をステージして `.githooks/pre-commit` が終了コード 0 で終わる（各コミットで hook が通る）。
  - `adr-guard links`、`adr-guard check-status`、`adr-guard check-numbers` が終了コード 0 で終わる。
  - コミットの後、`adr-guard check-range origin/main HEAD --allow-status --allow-links` が終了コード 0 で終わる。
- `sh scripts/ci/actions-pins.sh check` と `sh scripts/ci/actions-pins.sh verify` が終了コード 0 で終わる。
- `.github/workflows/docs.yml` が YAML として読めることを確かめる。
- マニュアルと文書の検査（`scripts/manual/test.sh`、`scripts/manual/check-updated.sh origin/main HEAD`、`scripts/ci/docs-refs.sh`、`scripts/ci/textlint.sh origin/main`）が通ることを確かめる。
- 変更のプルリクエストの CI で、`adr` ジョブが v0.13.1 の action で実行され、成功することを確かめる。

## トレードオフ

- 移行は、572 件の ADR のステータスの行を一度に変える。
  このため、ステータスの行を変える別のブランチは、移行のマージの後に衝突する。
  衝突した行は、新しい形で書き直す。
  少しずつ移す方法もあるが、旧形式と新しい形が長く混ざり、文書とリリースノートのスクリプトが両方を説明し続けることになる。
- CI を v0.13.1 に上げた後は、旧形式のステータスの行で ADR を足す別のブランチが、CI の `adr` ジョブで失敗する。
  そのブランチは、足す ADR の行を `Status: proposed` などの新しい形に書き直す。
- 移行の後の最初のリリースでは、`## ADRs whose status changed` に、前のタグにあった ADR がすべて並ぶ。
  移行で、どの ADR もステータスの行の文字列が変わるからである。
  リリースノートを書くプロンプトも、その分だけ大きくなる。
  旧形式と新しい形の値が同じ状態かを比べれば除けるが、そのためにはリリースノートのスクリプトが adr-guard と同じ旧形式の読み方を持つ必要がある。
  一度だけのことなので、比べる処理は作らない。
- 手で書く 19 件は、元の文を人が読んで部分名と修正先に分けたものである。
  参照の後ろの語を `note` に入れる決まりは [tett23/adr-guard ADR 0026](https://github.com/tett23/adr-guard/blob/v0.13.1/docs/adr/0026-read-more-legacy-references.md) の例に倣ったが、「で加えた」を `kind` が `supplement` の変更と読むこともできる。
  元の文を落とさないことを優先し、`kind` は注記のほかは既定のままにする。
- 新しい形は JSON の配列なので、旧形式の文に比べて人が読みにくい。
  `adr-guard trace` で、修正の連なりを読める形で出せる。
- 手元の adr-guard が v0.13.1 より古いと、pre-commit が状態遷移を検査せず、CI で初めて失敗する。
  README と CONTRIBUTING に必要な版を書いて補う。

## 参考文献

- [tett23/adr-guard ADR 0021](https://github.com/tett23/adr-guard/blob/v0.13.1/docs/adr/0021-codex-hook.md)
- [tett23/adr-guard ADR 0022](https://github.com/tett23/adr-guard/blob/v0.13.1/docs/adr/0022-status-transitions.md)
- [tett23/adr-guard ADR 0023](https://github.com/tett23/adr-guard/blob/v0.13.1/docs/adr/0023-trace-amendments.md)
- [tett23/adr-guard ADR 0024](https://github.com/tett23/adr-guard/blob/v0.13.1/docs/adr/0024-migration-dry-run-and-error-count.md)
- [tett23/adr-guard ADR 0025](https://github.com/tett23/adr-guard/blob/v0.13.1/docs/adr/0025-extend-canonical-status-amendments.md)
- [tett23/adr-guard ADR 0026](https://github.com/tett23/adr-guard/blob/v0.13.1/docs/adr/0026-read-more-legacy-references.md)
- [tett23/adr-guard ADR 0027](https://github.com/tett23/adr-guard/blob/v0.13.1/docs/adr/0027-read-legacy-replaced-status.md)
- [tett23/adr-guard ADR 0028](https://github.com/tett23/adr-guard/blob/v0.13.1/docs/adr/0028-fix-legacy-part-names.md)
- tett23/adr-guard の [v0.11.0 のリリース](https://github.com/tett23/adr-guard/releases/tag/v0.11.0)、[v0.12.0 のリリース](https://github.com/tett23/adr-guard/releases/tag/v0.12.0)、[v0.13.0 のリリース](https://github.com/tett23/adr-guard/releases/tag/v0.13.0)、[v0.13.1 のリリース](https://github.com/tett23/adr-guard/releases/tag/v0.13.1)
