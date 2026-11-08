# ADR 0230: リリースのワークフローと CI の履歴の確かめを、スクリプトとジョブに移す

ステータス: 採択

## 文脈

[docs/roadmap.md](../roadmap.md) の「手で確かめる項目」には、リリースのワークフローと CI の実行の履歴を確かめる項目が三つある。

- **リリースのワークフローの固め方**（[ADR 0044](0044-release-workflow-hardening.md)）：`workflow_dispatch` の `notes` ジョブが mise で Claude Code を入れて `notes.md` を上げること、タグの push で `release` ジョブがそれを使うこと、`build-linux.sh` が Alpine のコンテナで ghcup のブートストラップのスクリプトのハッシュを確かめて進むこと、ハッシュを一文字変えると止まること。
- **wasm の版のリリース**（[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md)）：`release.yml` のジョブ `wasm` を実際のタグで動かし、`golem-<タグ>-wasm32-wasi.tar.gz` の `THIRD_PARTY_LICENSES/` が [ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md) の 8 の挙げるものを持ち、`SHA256SUMS` と `gh attestation verify` が通ること。
- **epubcheck と apt の時間切れ**（[ADR 0062](0062-epubcheck-from-release-with-cache.md)）：epubcheck を配布元の release から取るようにした後の 30 回の `ci.yml` の実行で、apt と epubcheck の時間切れが一度も起きないこと。

三つとも、人の目や判断を要しない。
確かめる対象は、GitHub の実行の記録、アーカイブの中身、スクリプトの終了コードであり、どれもスクリプトで読める。
手で確かめる項目に残っているのは、確かめる手順がまだ書かれていないからである。

### 一つめの項目のうち、すでに起きたこと

2026-11-08 に `gh run view` で `release.yml` の実行を読んだ。
`v0.1.0-rc3` のタグの push の実行（run 40107403473）では、`notes` ジョブが成功している。
そのログには、mise が `npm:@anthropic-ai/claude-code` の 2.1.292 を入れた行がある。
`release` ジョブのログには、成果物 `notes` を取ってきた行と、`gh release create` に `--notes-file notes.md` を渡した行がある。
同じ実行の `build (x86_64-linux, ubuntu-24.04)` は、`ALPINE_IMAGE` のコンテナで `build-linux.sh` を動かして成功しており、ghcup のブートストラップのスクリプトのハッシュの検査を通っている。
`main` の `workflow_dispatch` の実行（run 41934030359、2026-11-04）でも `notes` は成功し、`release` は飛ばされている。

つまり、一つめの項目のうち、ハッシュを変えると止まること以外は、rc3 のリリースのときにもう起きていた。
記録がないので、手で確かめる項目から外れていないだけである。

ハッシュを変えると止まることは、今の自動のテストでは確かめられていない。
[`scripts/release/test.sh`](https://github.com/tett23/golem/blob/683744442737c02e86e700e26b6f1b9b95277aef/scripts/release/test.sh#L1432-L1441) は、`build-linux.sh` が `/etc/alpine-release` を読むので、偽のコマンドでは代われないとして、引数と Alpine の外での拒否だけを確かめている。
ただ、`release-scripts` ジョブの Ubuntu のランナーには Docker がある。
`release.yml` が使う `ALPINE_IMAGE`（ダイジェストで固定した `alpine:3.24`）のコンテナの中なら、`/etc/alpine-release` は本物であり、`apk` と `curl` だけを偽のコマンドにすれば、ハッシュの検査（[`build-linux.sh` の 42 行から 57 行](https://github.com/tett23/golem/blob/683744442737c02e86e700e26b6f1b9b95277aef/scripts/release/build-linux.sh#L42-L57)）まで進められる。

### 二つめの項目

ジョブ `wasm` は、`workflow_dispatch` でも走る（[`release.yml` の 214 行から](https://github.com/tett23/golem/blob/683744442737c02e86e700e26b6f1b9b95277aef/.github/workflows/release.yml#L214)）。
アーカイブを作るのは `package-wasm.sh` で、`workflow_dispatch` では、ジョブ `version` がタグの代わりに書く `dev-<コミットの先頭の 12 字>` の名前でアーカイブを作る。
`THIRD_PARTY_LICENSES/` の中身を [ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md) の 8 と照らすことは、アーカイブを作った直後のステップでできる。
タグが要るのは、`SHA256SUMS` を下書きのリリースに上げることと、`attest-build-provenance` の証明だけである。
この二つも、`release` ジョブの中で `gh release create` の後に `gh attestation verify` を走らせれば、タグのたびに確かめられる。

### 三つめの項目

epubcheck の取り方を変えたのは 2026-10-23 である（`scripts/ci/epubcheck-install.sh` の最初のコミット）。
それから後の `ci.yml` の実行は、30 回を大きく超えている。
時間切れは、ステップ「qpdf is installed」と「epubcheck is installed」の `timeout-minutes: 5` で起きる。
GitHub の API（`GET /repos/{owner}/{repo}/actions/runs/{run_id}/jobs`）は、ジョブごとにステップの名前と `conclusion` を返す。
ログを取らなくても、この二つのステップが失敗した実行を数えられる。

## 実装すること

### 1. ghcup のハッシュが合わないと止まることのテスト

`scripts/release/test.sh` に、Docker があるときだけ走るテストを足す。

- `ALPINE_IMAGE` を `release.yml` から読む。ダイジェストで固定した値をそのまま使い、ほかの像を取らない。
- コンテナに、リポジトリの写しを読み取りだけで渡し、`PATH` の先頭に偽の `apk`（何もしない）と偽の `curl`（`-o` の先に決まった中身を書く）を置く。
- `GHCUP_BOOTSTRAP_SHA256` を一文字変えた `build-linux.sh` の写しを動かし、終了コードが 1 で、標準エラーに `SHA-256 mismatch for the bootstrap script of ghcup` があることを確かめる。
- ハッシュを偽の `curl` の書く中身のものに変え、`ghver=` の行がない中身では、`does not install ghcup` で止まることを確かめる。
- Docker がない環境（`scripts-macos` と手元の macOS）では、飛ばしたことを一行書いて続ける。

`build-linux.sh` は変えない。
写しの書き換えは `sed` の一つの置換であり、テストが確かめるのは今のスクリプトの検査の部分そのものである。

### 2. wasm のアーカイブの中身の検査

`scripts/release/check-wasm-archive.sh` を足す。
アーカイブを一つ受け取り、次を確かめる。

- 最上位のディレクトリに `golem.wasm`、`LICENSE`、`README`、`THIRD_PARTY_LICENSES/` がある。
- `THIRD_PARTY_LICENSES/` に、[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md) の 8 の挙げるもの（wasm の GHC の RTS と boot のパッケージ、HarfBuzz、FreeType、hyph-utf8、zlib、wasi-libc、libc++、GMP）の文書がある。名前の一覧は、`licenses.sh --wasm` の書く名前に合わせてスクリプトの中に書く。
- アーカイブの `.sha256` が、アーカイブの SHA-256 と一致する。

`release.yml` のジョブ `wasm` の、アーカイブを作るステップの直後にこれを走らせる。
`workflow_dispatch` でも走るので、タグを打つ前に確かめられる。
`scripts/release/test.sh` に、偽のアーカイブで、足りない文書ごとに失敗することのテストを足す。

### 3. リリースの後の `gh attestation verify`

`release.yml` の `release` ジョブの最後に、`gh release create` で上げたアーカイブのそれぞれに `gh attestation verify <ファイル> -R tett23/golem` を走らせるステップを足す。
下書きのリリースから取り直すのではなく、同じジョブの `dist/` のファイルを使う。
上げたものと `dist/` のものが同じであることは、同じステップで `gh release download` した `SHA256SUMS` を `sha256sum -c` で確かめる。

### 4. 時間切れの数え方

`scripts/ci/step-timeouts.sh` を足す。
引数に日時と回数を取り、その日時より後の `ci.yml` の実行を新しい順に読み、二つのステップの `conclusion` を数えて表にする。

```text
run  created  qpdf is installed  epubcheck is installed
```

実装のプルリクエストで、2026-10-23 より後の実行について走らせ、結果を `docs/ci-timings/` に記録する。
これは一度だけの計測であり、定期のジョブにはしない。
時間切れが一度でもあれば、[ADR 0062](0062-epubcheck-from-release-with-cache.md) の続きを別の ADR にする。

### 5. ロードマップと仕様

- 「リリースのワークフローの固め方」を外す。run 40107403473 の記録（上の「一つめの項目のうち、すでに起きたこと」）と、1 のテストで足りる。
- 「wasm の版のリリース」を外す。2 と 3 が、rc4 のタグからは毎回確かめる。最初のタグの結果は、[CONTRIBUTING.md](../../CONTRIBUTING.md) の `docs/audits/releases/<タグ>.md` に書く。
- 「epubcheck と apt の時間切れ」を外す。4 の記録で足りる。
- CONTRIBUTING.md のリリースの節に、2 と 3 が走ることを一文ずつ足す。

## 実装しないこと

- `notes` ジョブを CI で毎回走らせること。Claude Code の API キーを使い、プルリクエストの実行に秘密を渡すことになる。`workflow_dispatch` とタグで足りる。
- `build-linux.sh` を、偽のコマンドで最後まで動かせるように分けること。`test.sh` の注にあるとおり、読む順が崩れる。ハッシュの検査はコンテナの中で本物の `/etc/alpine-release` を使って確かめられる。
- 時間切れを数える定期のジョブ。数えたい期間は一度で終わる。

## 不変条件

| 番号 | 不変条件 |
| --- | --- |
| I1 | `GHCUP_BOOTSTRAP_SHA256` が取ってきたスクリプトの SHA-256 と違えば、`build-linux.sh` は ghcup のスクリプトを走らせる前に終了コード 1 で止まる。 |
| I2 | `release.yml` が上げる wasm のアーカイブは、[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md) の 8 の挙げる文書をすべて `THIRD_PARTY_LICENSES/` に持つ。持たなければ、ジョブ `wasm` が失敗し、`release` は走らない。 |
| I3 | タグの `release` ジョブが成功したとき、上げたアーカイブのそれぞれに、このリポジトリの `release.yml` の証明がある。 |

## テスト設計

先に書いて失敗させるテストは次のとおりである。

- `scripts/release/test.sh`：1 のテスト。ハッシュを一文字変えた写しが I1 のとおり止まること。`ghver=` のない中身で止まること。Docker がなければ飛ばすこと。
- `scripts/release/test.sh`：2 のテスト。足りる偽のアーカイブで成功し、`THIRD_PARTY_LICENSES/` の文書を一つずつ除いたアーカイブで、除いた名前を書いて失敗すること。`.sha256` が合わないアーカイブで失敗すること。
- `scripts/ci/test.sh`：4 のスクリプトに、API の応答の写し（`scripts/ci/testdata/` に置く）を渡し、失敗したステップを数えること。ステップがない実行（文書だけの変更で `build` が飛ばされた実行）を数えないこと。
- `scripts/ci/test.sh` の `release.yml` の構造の検査：ジョブ `wasm` で `check-wasm-archive.sh` が `package-wasm.sh` の後にあること。`release` ジョブで `gh attestation verify` が `gh release create` の後にあること。

CI を走らせて確かめることは次のとおりである。

- 実装のプルリクエストの後に、`main` で `release.yml` を `workflow_dispatch` で動かし、ジョブ `wasm` の 2 が通ること。
- rc4 のタグの実行で、3 が通ること。結果を `docs/audits/releases/v0.1.0-rc4.md` に書く。

## トレードオフ

1 のテストは、`release-scripts` ジョブで Alpine の像を取る。
像は数 MB で、ランナーの Docker のキャッシュにはないので毎回取る。
`release-scripts` ジョブは今 20 秒ほどで終わり（2026-11-08 の `main` の run 42444096822）、臨界経路の `build` より十分に早いので、実行全体の時間は延びない。

3 は、タグのたびに GitHub の API を呼ぶ。
証明は直前のステップで作ったものなので、失敗は GitHub の障害か、証明のステップの設定の誤りである。
どちらもリリースを止める理由になる。

## メンテナーが決めること

1. **一つめの項目を記録で外すこと**：推奨は、run 40107403473 のログを根拠に外すことである。`notes` と `release` と Alpine の `build-linux.sh` は、rc3 で起きたことを実行のログが示しており、同じことをもう一度起こしても増える情報がない。
   - 退けた案は、rc4 のタグで改めて確かめることである。rc3 との違いは、その後に入った変更がワークフローを壊していないかであり、それは手で確かめる項目ではなく、rc4 のリリースそのものが確かめる。
2. **wasm のアーカイブの検査を置く場所**：推奨は、`release.yml` のジョブ `wasm` に置くことである。`workflow_dispatch` で走るので、タグの前に誤りがわかる。
   - 退けた案は、`ci.yml` のジョブ `wasm` に置くことである。`ci.yml` はアーカイブを作らず、作るには GMP のソースを取る手順をプルリクエストのたびに足すことになる。
3. **時間切れの数え方**：推奨は、一度だけのスクリプトで数えることである。
   - 退けた案は、手で GitHub の画面を 30 回開くことである。数え落としの有無を後から確かめられない。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-08、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- GitHub Docs, REST API endpoints for workflow jobs, https://docs.github.com/en/rest/actions/workflow-jobs
- GitHub CLI manual, gh attestation verify, https://cli.github.com/manual/gh_attestation_verify
