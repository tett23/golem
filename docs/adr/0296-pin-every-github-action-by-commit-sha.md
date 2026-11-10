# ADR 0296: GitHub Actions の action を、コミットの SHA と版の注釈で指定する

ステータス: 採択

## 文脈

[docs/adr/0035](0035-security-hardening.md) は、action を Node 24 以降で動く最新のメジャー版のタグで指定し、コミットの SHA では固定しないと決めた。
SHA で固定すればタグの付け替えによる乗っ取りは防げるが、メジャー版の更新から取り残される、というのが理由である。
[ADR 0044](0044-release-workflow-hardening.md) と [ADR 0085](0085-pin-mise-version-in-workflows.md) は、この判断を変えないと書いた。

2026-11-05 以降の監査は、この点を毎回挙げている。
2026-11-05 の監査（[docs/audits/2026-11-05-security-audit.md](../audits/2026-11-05-security-audit.md)）の H-02 が最初で、2026-11-06、2026-11-08 の監査が継続と記録し、2026-11-09 の監査（[docs/audits/2026-11-09-security-audit.md](../audits/2026-11-09-security-audit.md)）は CI-03 として残した。
ロードマップの v1.0.0 の「テストと CI」も、2026-11-09 の監査の所見の一つとしてこれを挙げている。

docs/adr/0035 の理由は、取り残されることを人が気付けない、という前提に立つ。
この前提は、固定した版を上流と毎日照合する仕組み（[ADR 0157](0157-check-wasmtime-pin-against-advisories.md) が wasmtime で作ったもの）があれば成り立たない。

### 今の参照

`main`（9acc137aeab273aec90561d5a8bfa4055fb6fc53）の `.github/workflows/*.yml` の 9 個のファイルに、`uses:` の行は 129 ある。
`.github/` の下に、ほかの action の定義（`action.yml`）と Dependabot の設定はない。
`docker://` の参照もない。
2026-11-10 に、各タグを `git ls-remote --tags` で引き、`^{}` で注釈つきのタグをコミットまでたどった。
同じコミットを指す版のタグも、同じ出力から探した。

| 参照 | 行の数 | 種類 | 指すコミット | 同じコミットの版のタグ | 動く環境 |
| --- | --- | --- | --- | --- | --- |
| `actions/checkout@v7` | 35 | GitHub | 3d3c42e5aac5ba805825da76410c181273ba90b1 | v7.0.1 | node24 |
| `actions/cache/restore@v6` | 22 | GitHub | 55cc8345863c7cc4c66a329aec7e433d2d1c52a9 | v6.1.0 | node24 |
| `actions/cache/save@v6` | 13 | GitHub | 同上 | 同上 | node24 |
| `actions/cache@v6` | 10 | GitHub | 同上 | 同上 | node24 |
| `actions/upload-artifact@v7` | 15 | GitHub | cf430e030ddbb5b0abf93d22962f4752f3646cd9 | v7.0.2 | node24 |
| `actions/download-artifact@v8` | 13 | GitHub | 9000827ccba6bdab643e8b6fd33ac0654aef8333 | v8.0.2 | node24 |
| `actions/setup-node@v7` | 8 | GitHub | 949feb2413d6458794dcd2491c4babbbce0c15c1 | v7.1.0 | node24 |
| `actions/attest-build-provenance@v4` | 1 | GitHub | 4d101475d8b20a2381f78447822ac1eab6504dd8 | v4.2.2 | composite |
| `haskell-actions/setup@v2` | 6 | 第三者 | 0f8e8c99d88aeb3fbfd523f1ef2c6f762d10d64d | v2.12.1 | node24 |
| `haskell-actions/run-fourmolu@v13` | 1 | 第三者 | 1b9df64b784203126500372730b9725c97e4040b | なし（メジャー版のタグだけ） | node24 |
| `jdx/mise-action@v5` | 2 | 第三者 | b44d12e7d0d8ee7461bb893e1b1993500433185b | v5.2.7 | node24 |
| `cachix/install-nix-action@v31` | 1 | 第三者 | 75c75c31ebece974e48ebc36b4ad125bd97bd97b | v31.11.3 | composite |
| `tett23/adr-guard@v0.10.0` | 1 | メンテナー自身 | 624df60fe8956ef52b3a275198ee938175324496 | v0.10.0 | composite |
| `./.github/workflows/ci.yml` | 1 | このリポジトリ | （リポジトリの同じコミット） | | reusable workflow |

どの action も、各リポジトリの最新のリリースと同じメジャー版を使っている。
今の参照は、グローバルの方針（Node 24 以降で動く最新のメジャー版）を満たす。

`actions/attest-build-provenance` の v4.2.2 は composite で、中で `actions/attest@508db95dd578ae2727ebd6217d5ba78e4fbda05d # v4.2.1` を SHA で呼ぶ。
`tett23/adr-guard` は composite で、action と同じ版の実行ファイルを GitHub の release から取り、同じ release の `SHA256SUMS` で確かめる。
`cachix/install-nix-action` は、Nix のインストーラーを releases.nixos.org から取る。
外側の action を SHA で固定しても、これらが取るものは固定されない。

### メジャー版のタグは動く

メジャー版のタグは、上流が新しい版を出すたびに付け替える。
[ADR 0085](0085-pin-mise-version-in-workflows.md) は、`jdx/mise-action` の `v5` がコミット 82a612c5ab8bcda7cc5db6b7e81a8e7584c3dc6e を指すと書いた。
このコミットは v5.2.3 である。
2026-11-10 の `v5` は b44d12e7d0d8ee7461bb893e1b1993500433185b（v5.2.7）を指す。
その間に上流は v5.2.4 から v5.2.7 までの四つの版を出し、`ANTHROPIC_API_KEY` を持つ `notes` ジョブで動く mise-action のコードは、このリポジトリのプルリクエストを経ずに変わった。
上流の正当な更新であっても、レビューの外で変わるという性質は、乗っ取られた更新と同じである。

### このリポジトリの脅威モデル

乗っ取られた action ができることは、その action が動くジョブの権限と秘密で決まる。

- `release.yml` の `release` ジョブは `contents: write`、`id-token: write`、`attestations: write` を持ち（[release.yml の 441 行から 455 行](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/.github/workflows/release.yml#L441-L455)）、`actions/checkout`、`actions/download-artifact`、`actions/attest-build-provenance` を動かす（[507 行](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/.github/workflows/release.yml#L507)）。ここで動く action は、リリースを書き換え、OIDC のトークンで偽の来歴に署名できる。
- `notes` ジョブは `contents: read` だけだが、`ANTHROPIC_API_KEY` を環境に持つ（[410 行から 431 行](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/.github/workflows/release.yml#L410-L431)）。同じジョブの `jdx/mise-action` は、`GITHUB_ENV` や `GITHUB_PATH` を書いて後のステップを変えられる（[ADR 0085](0085-pin-mise-version-in-workflows.md) の文脈）。
- `ci.yml` の `caches` ジョブは `actions: write` を持ち（[ci.yml の 1197 行から 1204 行](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/.github/workflows/ci.yml#L1197-L1204)）、`release.yml` は `ci.yml` を呼ぶときに `actions: write` を渡す（[release.yml の 33 行から 37 行](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/.github/workflows/release.yml#L33-L37)）。
- ほかのジョブは `contents: read` か、それに `actions: read` を足した権限で動き、秘密を持たない。

権限を持つジョブだけを守れば足りるように見えるが、そうはならない。
`release` ジョブが来歴に署名する配布物は、`build` や `wasm` のジョブが作って artifact として渡したものである。
これらのジョブは `haskell-actions/setup` と `actions/cache` を動かす。
ここで乗っ取られた action が配布物を書き換えれば、`release` ジョブは書き換えられた配布物に正しい来歴を付ける。
`main` への push で動くジョブは、キャッシュも書く。
配布物とキャッシュを通して、権限のないジョブの action も、リリースの完全性に関わる。

### リポジトリの設定

GitHub は、リポジトリの Actions の設定に、action を完全な長さの SHA でしか指定させない項目を持つ。
2026-11-10 に `gh api repos/tett23/golem/actions/permissions` で読むと、`"allowed_actions":"all","sha_pinning_required":false` だった。
GitHub Docs によれば、これを有効にすると、タグで指定した action は実行の時点で拒まれる。
reusable workflow は、この設定の下でもタグで呼べる。
リポジトリの設定を変えるのはメンテナーであり、ワークフローの変更とは別の操作である。

### 固定の置き場所

SHA を書く場所には二つの候補がある。
一つは、ワークフローの `uses:` の行に SHA を書くことである。
もう一つは、GitHub の **ワークフローの依存のロックファイル**（`.github/workflows/actions.lock`）である。
GitHub Docs によれば、ロックファイルは GitHub CLI の拡張 `gh actions-lock`（github/gh-actions-lock、Go、MIT）が作り、手では書かない。
ワークフローを取り込むと、実行の時点でロックファイルのコミットが動き、composite の action が中で呼ぶ action（推移的な依存）も固定される。
依存ごとに、リポジトリの数値の ID も記録し、名前の後ろのリポジトリが入れ替わっていないことを実行の時点で確かめる。
`sha_pinning_required` の設定も満たす。
GitHub Docs は、ロックファイルを使うリポジトリではワークフローに SHA を書く必要はないとし、ロックファイルのほうを勧める。

ロックファイルの利点のうち、このリポジトリで役に立つものは限られる。
推移的な `uses:` は、`actions/attest-build-provenance` の中の `actions/attest` だけであり、上流がすでに SHA で呼んでいる。
`tett23/adr-guard` と `cachix/install-nix-action` の中身は `curl` での取得であり、ロックファイルでも固定されない。
一方で、拡張は 2026-04-22 に作られたリポジトリで、2026-11-10 の最新は v0.4.1（2026-11-02）である。
実行の時点の強制は GitHub の側の振る舞いであり、このリポジトリの手元のテストでは確かめられない。
この ADR を書くにあたって、拡張を入れて動かしてはいない。

### 更新の方法の候補

SHA で固定した参照を新しい版へ上げる方法には、次のものがある。

- **Dependabot の github-actions のエコシステム**：GitHub の機能で、`.github/dependabot.yml` を置くと、新しい版のプルリクエストを開く。ロックファイルを使うときは、同じプルリクエストでロックファイルも作り直す（GitHub Docs）。このリポジトリでは使っていない（Dependabot のアラートも無効で、`vulnerability-alerts` の API は 404 を返した）。
- **Renovate**：第三者の GitHub App である。リポジトリに新しいサービスを足すことになる。
- **このリポジトリのスクリプト**：タグを SHA に引き直し、ワークフローを書き換えるシェルスクリプトを置く。上流を照合する仕事は、wasmtime のアドバイザリと同じく、毎日の `advisories.yml` で動かせる。

[ADR 0085](0085-pin-mise-version-in-workflows.md) は「このリポジトリは依存の更新を手のプルリクエストで行う」と書いた。
wasmtime、mise、epubcheck、Claude Code の版も、この形で上げている。

## 実装すること

### 固定する範囲

- `.github/workflows/*.yml` のすべての `uses:` を、コミットの SHA で指定する。GitHub の `actions/*`、第三者の action、メンテナー自身の `tett23/adr-guard` を区別しない。
- 形は次のとおりとする。SHA は 40 桁の小文字の 16 進数で、`^{}` でたどったコミットの SHA である（注釈つきのタグのオブジェクトの SHA ではない）。注釈は、そのコミットを指す版のタグである。

  ```yaml
  - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
  ```

- 注釈のタグは、そのコミットを指すタグのうち、いちばん細かいもの（`v7.0.1` と `v7` があれば `v7.0.1`）とする。`haskell-actions/run-fourmolu` のようにメジャー版のタグしかなければ `v13` とする。
- 同じリポジトリの action（`actions/cache`、`actions/cache/restore`、`actions/cache/save` など）は、どのファイルでも同じ SHA と同じ注釈で指定する。
- このリポジトリの reusable workflow（`./.github/workflows/ci.yml`）は、リポジトリの同じコミットを指すので、今のまま `./` で書く。
- `docker://` の参照は使わない。使うときは、イメージの digest での固定を別の ADR で決める。

### スクリプト

`scripts/ci/actions-pins.sh` を足す。
POSIX の sh と、macOS の BSD の道具で動く `grep`、`sed`、`awk`、`sort` で書く。
三つの操作を持つ。

- **`check`**：ネットワークを使わない。`.github/workflows/*.yml` のすべての `uses:` の行が上の形であることと、同じリポジトリの SHA と注釈がそろっていることを確かめる。外れた行は `ファイル:行` と理由を出し、一つでもあれば終了コード 1 で終わる。調べた行の数を出し、0 なら失敗する（[ADR 0077](0077-shell-test-assertions-that-pass-vacuously.md)）。
- **`verify`**：ネットワークを使う。リポジトリと SHA と注釈の組ごとに、`git ls-remote --tags https://github.com/<owner>/<repo>.git` で注釈のタグを引き、`^{}` でたどったコミットが SHA と一致することを確かめる。タグがないか、違うコミットを指せば失敗する。
- **`latest`**：ネットワークを使う。リポジトリごとに、`v` と数字とドットだけからなるタグ（`v8.0.0-beta.1` のような前置きつきの版は除く）を数の大小で並べ、いちばん大きな版のコミットが固定した SHA と一致することを確かめる。一致しなければ、新しい版の名前を出して失敗する。あわせて、固定したコミットの `action.yml`（なければ `action.yaml`）を `gh api` で読み、`runs.using` が `node24` 以上の Node か `composite` であることを確かめる。`docker` も失敗とする。
- **`update`**：手で動かす。`latest` が選ぶ版へ、すべてのファイルの SHA と注釈を書き換える。いちばん大きな版の `runs.using` が条件を満たさなければ、古い版に下がらずに失敗し、どの action が条件を満たさないかを出す。書き換えたあとの内容は、`check` を通る。

### CI と毎日の照合

- `ci.yml` の `scripts-linux` ジョブに、`sh scripts/ci/actions-pins.sh check` の手順を足す。`scripts-macos` ジョブは `scripts/ci/test.sh` を動かすので、テストを通して BSD の道具でも確かめる。
- `advisories.yml` に、`actions` ジョブを足す。`permissions` は `contents: read` で、`GH_TOKEN: ${{ github.token }}` を渡し、`verify` と `latest` を動かす。`timeout-minutes` は 10 とする。毎日一回と手での起動で動き、失敗した実行がメンテナーへの知らせになる（[ADR 0157](0157-check-wasmtime-pin-against-advisories.md) と同じ）。プルリクエストでは動かさない。結果がコミットではなく日付で変わるからである。

### 版の上げ方

- `advisories.yml` の `actions` ジョブが失敗したら、手元で `sh scripts/ci/actions-pins.sh update` を動かし、書き換えたワークフローのプルリクエストを出す。プルリクエストには、スクリプトの出力（どの action をどの版からどの版へ上げたか）を書く。
- メジャー版が上がるときは、上流のリリースノートを読み、入力の変わった action の `with:` をそのプルリクエストで直す。プルリクエストの CI が、新しい版で動くことを確かめる。
- `tett23/adr-guard` の版も同じ手順で上げる。

### 今のテストの書き換え

`scripts/ci/test.sh` には、タグの名前まで含めて `uses:` の行を探す検査がある。

- `uses: haskell-actions/setup@v2` を数える検査と、その手順の条件を比べる検査（[test.sh の 2006 行から 2023 行](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/scripts/ci/test.sh#L2006-L2023)）。
- `notes` ジョブに `jdx/mise-action@v` があることの検査（[test.sh の 1981 行](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/scripts/ci/test.sh#L1981)）。

これらを、`@` までの前置き（`uses: haskell-actions/setup@`、`jdx/mise-action@`）で探す形に変える。
ほかの検査は、すでに `@` までの前置きで探している。

### リポジトリの設定

- 固定のプルリクエストがマージされたあと、メンテナーがリポジトリの Actions の設定で、SHA での指定を求める項目（`sha_pinning_required`）を有効にする。`check` がプルリクエストで形を確かめ、設定が実行の時点で拒む。二つは別の時点で働く。
- 有効にした直後に `main` の CI と `workflow_dispatch` の `release.yml` を一度ずつ動かし、`./.github/workflows/ci.yml` の呼び出しを含めて拒まれないことを確かめる。拒まれれば、設定を戻し、この ADR を直す ADR を書く。

### ADR のステータス

- [docs/adr/0035](0035-security-hardening.md) のステータスの行の末尾に、「、action をタグで指定し SHA で固定しないことは [ADR 0296](0296-pin-every-github-action-by-commit-sha.md)」を足す。
- [ADR 0044](0044-release-workflow-hardening.md) のステータスの行の末尾に、「、action を SHA で固定しないことは [ADR 0296](0296-pin-every-github-action-by-commit-sha.md)」を足す。
- [ADR 0085](0085-pin-mise-version-in-workflows.md) のステータスを、「採択→action を SHA で固定しないことは [ADR 0296](0296-pin-every-github-action-by-commit-sha.md)」にする。

### ドキュメント

- `CONTRIBUTING.md` と `CONTRIBUTING.en.md` の「GitHub Actions」の節の「アクションは、Node 24 以降で動く最新のメジャーバージョンを使う」に、SHA と版の注釈で指定すること、`advisories.yml` の照合、`update` での上げ方を足す。
- 開発者向けマニュアルの「CI のジョブ」の章（`manual-dev/part2/11-ci-jobs.gm`）の「Actions のバージョン」の節と、ビルドとテストの章（`manual-dev/part2/08-build-test.gm`）の `advisories.yml` の段落に、同じことを書く。
- 仕様書の、`advisories.yml` が wasmtime の版を照合する段落の後ろに、action の固定の照合を書き、この ADR へのリンクを付ける。
- `docs/roadmap.md` の「テストと CI」の「2026-11-09 の監査の情報の所見」から「外部 action のタグ参照（CI-03）、」を外し、同じ項目の末尾に「外部 action のタグ参照（CI-03）は [docs/adr/0296](adr/0296-pin-every-github-action-by-commit-sha.md) で扱った。」を足す。同じ項目を外す ADR がほかにもあるので、マージの順に合わせて文を直す。

## 実装しないこと

- 第三者の action だけを固定すること。`release` ジョブは GitHub の action だけで来歴に署名するので、第三者だけを固定してもいちばん強い権限のジョブが守られない。持ち主で分けると、どれを固定するかの一覧が要り、一覧の誤りが穴になる。
- ワークフローの依存のロックファイル（`gh actions-lock`）で固定すること。このリポジトリで役に立つ利点（推移的な依存の固定）が小さく、拡張は v0.x で、実行の時点の強制を手元のテストで確かめられない。ワークフローに書いた SHA は、拡張が取り込むときにもそのまま使える。拡張が 1.0 に達したとき、または上流が SHA で固定していない推移的な `uses:` が現れたときに、別の ADR で選び直す。
- タグのまま残すこと（docs/adr/0035 の判断）。取り残される危険は、`latest` の毎日の照合で知らせられる。タグのままでは、`notes` ジョブの mise-action のように、レビューの外でコードが変わる。
- Dependabot で版を上げること。新しいサービスではないが、プルリクエストを開く bot を足し、[ADR 0085](0085-pin-mise-version-in-workflows.md) の「依存の更新を手のプルリクエストで行う」と違う運用になる。Node 24 以降で動くかの判定は、Dependabot に頼らず `latest` で行う必要がある。`update` の手間が重くなったら、別の ADR で選び直す。
- Renovate で版を上げること。第三者の GitHub App を足すことになる。
- スクリプトなしに手で SHA を書くこと。129 行を手で書き換えると、同じ action の SHA がファイルごとにずれやすい。
- composite の action が中で取るもの（`actions/attest` の呼び出し、adr-guard の実行ファイル、Nix のインストーラー）を固定すること。上流の action の中身であり、このリポジトリのワークフローからは書けない。`actions/attest-build-provenance` の v4.2.2 は、すでに SHA で呼んでいる。
- action の中身のレビューを、版を上げるたびに義務にすること。上げるプルリクエストで差分を読むかどうかは、メンテナーが決める。
- `docker://` の参照の固定の規則。今は使っていない。
- GitHub の Advisory Database の `actions` のエコシステムとの照合。`latest` が最新の版を求めるので、古い版に残る脆弱性は版の更新で外れる。

## 不変条件

`scripts/ci/actions-pins.sh` の性質を、テストの述語として書く。
ここで、ワークフローの **`uses:` の行** とは、`.github/workflows/*.yml` の行で、行頭の空白の後に `uses: ` か `- uses: ` が来るものをいう。

- **I1**：`check` が終了コード 0 で終われば、すべての `uses:` の行は、`./` で始まる参照か、`<owner>/<repo>` に `/<パス>` が続いてもよい名前、`@`、40 桁の小文字の 16 進数、空白、`# v`、`数(.数){0,2}` の順で、その後に何もない。
- **I2**：`uses:` の行のどれか一つでも I1 の形でなければ、`check` は終了コード 1 で終わり、その行の `ファイル:行` を出す。タグ、ブランチ、短い SHA、大文字の SHA、注釈のない SHA、`docker://` はすべてこれに当たる。
- **I3**：`check` が終了コード 0 で終われば、`<owner>/<repo>` が同じ二つの行は、パスが違っても、同じ SHA と同じ注釈を持つ。
- **I4**：`check` が出す調べた行の数は、`uses:` の行の数に等しい。その数が 0 なら、`check` は終了コード 1 で終わる。
- **I5**：`verify` が終了コード 0 で終われば、リポジトリと SHA と注釈の組のどれでも、上流の注釈のタグを `^{}` でたどったコミットは SHA に等しい。
- **I6**：`latest` が終了コード 0 で終われば、どのリポジトリでも、固定した SHA は、前置きのない版のタグのうち数でいちばん大きなものが指すコミットに等しく、そのコミットの `runs.using` は 24 以上の `node` か `composite` である。
- **I7**：上流が変わらなければ、`update` の後の内容は `check`、`verify`、`latest` を通り、もう一度 `update` を動かしても内容は変わらない。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 参照の形 | `actions/checkout@v7`、`@main`、7 桁の SHA、39 桁と 41 桁の 16 進数、大文字の 40 桁、注釈のない 40 桁、`# v7.0.1`、`# v7`、`# 7.0.1`、`# v7.0.1.2`、注釈の後の空白、`./.github/workflows/ci.yml`、`docker://alpine:3` |
| 行の書き方 | `- uses:`、`name:` の下の `uses:`、引用符で囲んだ値 |
| `uses:` の行の数 | 0、1、2 以上 |
| 同じリポジトリの行 | 同じ SHA と注釈、SHA が違う、SHA が同じで注釈が違う、パス（`/restore`、`/save`）だけが違う、別のファイルにある |
| 上流のタグ（`verify`） | 軽量のタグ、注釈つきのタグ、タグがない、別のコミットへ付け替えられた |
| 上流の版（`latest`） | 固定した版がいちばん新しい、新しいパッチの版がある、新しいメジャー版がある、新しい版が `-beta` などの前置きつきだけ、メジャー版のタグしかない、`v9` と `v10` の大小 |
| `runs.using` | `node24`、`node26`、`node20`、`composite`、`docker`、`action.yaml` しかない |

## テスト設計

`scripts/ci/test.sh` に `actions-pins.sh` の節を足し、先に書いて失敗することを確かめてから、スクリプトとワークフローを変える。
テストの名前には、不変条件の番号（I1 から I7）を入れる。
`scripts-linux` と `scripts-macos` の両方で動く（[ADR 0079](0079-shell-tests-on-macos.md)）。

- **`check`**：境界の表の参照の形と行の書き方を一つずつ書いた YAML を作業用のディレクトリに置き、通るものと失敗するもの、失敗の `ファイル:行` を確かめる（I1、I2）。同じリポジトリの行の組を二つのファイルに分けて置き、そろわない組が失敗することを確かめる（I3）。`uses:` の行のないファイルだけのディレクトリで失敗し、行の数が出力と一致することを確かめる（I4）。
- **`verify` と `latest`**：`git` と `gh` を、記録した出力を返すスタブに置き換えて `PATH` の前に置く。`ls-remote` の出力は、2026-11-10 に記録した実物（`actions/checkout`、`haskell-actions/setup` の注釈つきのタグ、`haskell-actions/run-fourmolu` のメジャー版のタグだけのもの）を `scripts/ci/testdata/` に置き、境界の表の上流の場合はそれを書き換えて作る（I5、I6）。
- **`update`**：同じスタブで、古い SHA のワークフローを書き換え、`check` と、スタブでの `verify`、`latest` が通り、二度目の `update` で差分がないことを確かめる（I7）。最新の版の `runs.using` が `node20` のとき、ファイルを変えずに失敗することを確かめる。
- **ワークフロー**：`main` のワークフローに `check` を動かす検査を足す。今の `main` ではタグの参照が 128 行あるので失敗する。`update` で書き換えたあとに通ることを確かめる。`advisories.yml` の `actions` ジョブの `permissions` が `contents: read` だけで、`verify` と `latest` を動かすことを、YAML を読んで確かめる。
- 今のテストのうち、タグの名前まで含めて探す二つの検査が、書き換えたワークフローで通ることを確かめる。

自動テストで確かめられないことは、実装の後に次の手順で確かめる。

- `workflow_dispatch` で `advisories.yml` を動かし、`actions` ジョブが通ることを見る。
- 一時的なコミットで、一つの action の SHA を一つ前の版の SHA に変え、注釈も合わせたうえで `advisories.yml` を手で動かし、`latest` が新しい版の名前を出して失敗することを見る。このコミットはマージしない。
- `sha_pinning_required` を有効にしたあと、「リポジトリの設定」に書いた二つの実行が通ることを見る。

## トレードオフ

- ワークフローの行が長くなり、読む人は版を注釈で読む。注釈と SHA のずれは `verify` が毎日見つけるが、見つかるまでの最長一日は、注釈が誤っていることがある。
- 上流の新しい版は、`update` のプルリクエストを通るまで入らない。セキュリティの修正を含む版も、最長一日と、プルリクエストを出してマージするまでの時間だけ遅れる。タグのままなら、上流が付け替えた時点で入っていた。
- GitHub のログの手順の名前が `Run actions/checkout@<SHA>` になり、版を上げるたびに変わる。`scripts/ci/timings.sh --median` は手順の名前で行をまとめるので、版を上げた前後の実行は別の行になる。
- `advisories.yml` の失敗は、wasmtime のアドバイザリと action の版の二つの理由で起きる。ジョブを分けるので、どちらが失敗したかは実行の画面で見分けられる。
- 上流が古い版のタグを消せば、`verify` が失敗する。そのときは `update` で上げる。
- `latest` は、最新の版がメジャー版を上げたものでも失敗する。メジャー版を上げるかの判断を毎回プルリクエストで行うことになるが、グローバルの方針は最新のメジャー版を使うことなので、上げないという判断は方針から外れる。

## 決めたことの記録

2026-11-10 に、tett23 がこの ADR の判断のすべてを推奨のとおりに決めた。

1. SHA は、ワークフローの `uses:` の行に書く。ワークフローの依存のロックファイル（`gh actions-lock`）は使わない。
2. GitHub の `actions/*`、第三者の action、`tett23/adr-guard` を区別せず、すべての action を固定する。
3. 版は `scripts/ci/actions-pins.sh` の `update` で上げ、手のプルリクエストで入れる。Dependabot と Renovate は使わない。
4. 上流との照合（`verify` と `latest`）は、`advisories.yml` の `actions` ジョブで毎日動かす。プルリクエストでは `check` だけを動かす。
5. 固定のプルリクエストがマージされたあとに、tett23 がリポジトリの設定の `sha_pinning_required` を有効にする。

採択にあたり、`main` の aa95669d1f723958c925c4d8aac3966798c14ae3 で `uses:` の行を数え直し、2026-11-10 に各タグを `git ls-remote --tags` で引き直した。
行の数、指すコミット、同じコミットの版のタグは、「今の参照」の表と変わらなかった。
9acc137aeab273aec90561d5a8bfa4055fb6fc53 から aa95669d までに、`.github/` と `scripts/ci/test.sh` は変わっていないので、ソースコードへのリンクは 9acc137a のままとした。

## 参考文献

- GitHub Docs, "Security hardening for GitHub Actions"（action を完全な長さの SHA で固定すること）。https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions
- GitHub Docs, "Managing GitHub Actions settings for a repository"（許可する action と SHA での指定を求める設定）。https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository
- GitHub REST API, "Get GitHub Actions permissions for a repository"（`sha_pinning_required`、2026-11-10 に読んだ）。https://docs.github.com/en/rest/actions/permissions
- GitHub Docs, "Workflow dependency lockfiles"。https://docs.github.com/en/actions/concepts/security/workflow-dependency-lockfiles
- GitHub Docs, "Locking action dependencies in a repository's workflows"。https://docs.github.com/en/actions/how-tos/secure-your-work/lock-workflow-dependencies
- github/gh-actions-lock（README と release、2026-11-10 に読んだ）。https://github.com/github/gh-actions-lock
- GitHub Docs, "Keeping your actions up to date with Dependabot"。https://docs.github.com/en/code-security/dependabot/working-with-dependabot/keeping-your-actions-up-to-date-with-dependabot
- GitHub Docs, "Metadata syntax for GitHub Actions"（`runs.using`）。https://docs.github.com/en/actions/reference/workflows-and-actions/metadata-syntax
- Git, `git-ls-remote`（`^{}` でたどったタグ）。https://git-scm.com/docs/git-ls-remote
- actions/attest-build-provenance, `action.yml`、コミット 4d101475d8b20a2381f78447822ac1eab6504dd8（v4.2.2）。https://github.com/actions/attest-build-provenance/blob/4d101475d8b20a2381f78447822ac1eab6504dd8/action.yml
- tett23/adr-guard, `action.yml`、コミット 624df60fe8956ef52b3a275198ee938175324496（v0.10.0）。https://github.com/tett23/adr-guard/blob/624df60fe8956ef52b3a275198ee938175324496/action.yml
- jdx/mise-action のタグ（v5.2.3 は 82a612c5ab8bcda7cc5db6b7e81a8e7584c3dc6e、v5.2.7 は b44d12e7d0d8ee7461bb893e1b1993500433185b）。https://github.com/jdx/mise-action/tags
- [docs/adr/0035](0035-security-hardening.md)
- [ADR 0044](0044-release-workflow-hardening.md)
- [ADR 0085](0085-pin-mise-version-in-workflows.md)
- [ADR 0157](0157-check-wasmtime-pin-against-advisories.md)
- [docs/audits/2026-11-05-security-audit.md](../audits/2026-11-05-security-audit.md)
- [docs/audits/2026-11-09-security-audit.md](../audits/2026-11-09-security-audit.md)
