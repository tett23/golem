# ADR 0243: CI の取得を一つの補助スクリプトで再試行し、取得物のアーカイブを SHA-256 で照合してキャッシュする

ステータス: 採択

## 文脈

### 取得の失敗で実行が落ちる

[docs/ci-timings/2026-11-09-ci-critical-path-and-download-failures.md](../ci-timings/2026-11-09-ci-critical-path-and-download-failures.md)（以下「記録」）の表 8 のとおり、2026-11-08T10:37Z から 12:16Z までの約 100 分に、`build` の wasmtime の C API の取得が 32 のジョブで失敗した。
GitHub の release の配信が、2 分で 504 を返すか、すぐに 502 か 503 を返した。
10 回の実行が落ち、6 回は手で再実行して通し（最大 4 回の試行）、4 回は失敗のまま終わった。
`outputs` のランナーが落ちた実行では、その成果物を待つ `visual` と `wasm` も連鎖して落ちた（6 回ずつ）。

`scripts/fetch-wasmtime.sh` の `curl` には `--retry` がない（[`fetch-wasmtime.sh`](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/scripts/fetch-wasmtime.sh#L47)）。
`build` の 7 つのランナーが毎回取るので、この手順は 40 時間に 2,219 回走った（記録の表 6）。
`release.yml` は同じアーカイブを `actions/cache` に置いているが（[`release.yml`](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/.github/workflows/release.yml#L105-L110)）、`ci.yml` の `build` は置いていない（[`ci.yml`](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/.github/workflows/ci.yml#L309-L310)）。

同じ 40 時間に、ほかの取得も一度ずつ失敗した。

- `format` の hlint の release（`scripts/ci/fetch-hlint.sh`、`--retry` なし、キャッシュなし）が 503 で落ちた。
- `verapdf` の `nix build github:NixOS/nixpkgs/...` が、`api.github.com` の nixpkgs の tarball を認証なしで取り、429（rate limit）で 4 回試して落ちた。
- `visual` の `actions/download-artifact@v8` が、成果物の一覧の API の名前解決で `ENOTFOUND` になった。
- `docs.yml` の `tett23/adr-guard@v0.10.0` が、自分の実行ファイルを取るときに 504 で落ちた（300 回に 1 回）。
- `release.yml` の `scripts/release/fetch-gmp.sh` は、`gmplib.org` への接続が 20 秒で時間切れになり、ミラーに移って通った（19 回に 2 回）。

### 取得のスクリプトは同じ形を 13 通り持つ

SHA-256 で固定した取得のスクリプトは、どれも「`curl` で取る、SHA-256 を比べる、展開する、`VERSION` に名前と SHA-256 を書く」の形で、`curl` の再試行の有無と回数がばらばらである。

| スクリプト | `--retry` | `--connect-timeout` | CI のキャッシュ |
| --- | --- | --- | --- |
| [`scripts/fetch-wasmtime.sh`](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/scripts/fetch-wasmtime.sh#L47) | なし | なし | `ci.yml` はなし、`release.yml` は展開した木 |
| [`scripts/ci/fetch-hlint.sh`](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/scripts/ci/fetch-hlint.sh#L21) | なし | なし | なし |
| [`scripts/visual/fetch-shem.sh`](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/scripts/visual/fetch-shem.sh#L49) | 3 | 30 | 展開した木 |
| [`tools/editors/fetch-nvim.sh`](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/tools/editors/fetch-nvim.sh#L47) | 3 | 30 | 展開した木 |
| [`tools/editors/helix/test.sh`](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/tools/editors/helix/test.sh#L57) | 3 | 30 | 展開した木 |
| [`scripts/browser/fetch-chromium.sh`](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/scripts/browser/fetch-chromium.sh#L45) | 3 | 30 | 展開した木 |
| [`scripts/wasm/fetch-deno.sh`](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/scripts/wasm/fetch-deno.sh#L39) | 3 | 30 | 展開した木 |
| [`scripts/ci/epubcheck-install.sh`](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/scripts/ci/epubcheck-install.sh#L39) | 3 | 30 | zip（戻すたびに SHA-256 を照合） |
| [`scripts/models/check.sh`](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/scripts/models/check.sh#L46) | 3 | なし | なし |
| [`scripts/release/fetch-gmp.sh`](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/scripts/release/fetch-gmp.sh#L30-L38) | 2、ミラー 3 つ | 20 | なし |
| [`scripts/manual/fetch-fonts.sh`](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/scripts/manual/fetch-fonts.sh#L58) | 3 | なし | 取ったファイル（`manual-fonts-…`） |
| [`scripts/fetch-ghc-wasm.sh`](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/scripts/fetch-ghc-wasm.sh#L67) | 5 | なし | 展開した木と cabal の store |
| [`scripts/fetch-wasm-packages.sh`](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/scripts/fetch-wasm-packages.sh#L29) | 5 | なし | なし（展開先は `ghc-wasm-…` の外） |

`curl` の `--retry` は、時間切れと HTTP の 408、429、500、502、503、504 だけを再試行する。
今回の 504、503、502 は `--retry` があれば再試行の対象だったが、`curl: (56) Connection died`（受信の途中で切れた）は対象でなく、`--retry-all-errors` が要る。

### キャッシュから戻した実行ファイルを再ハッシュしない

2026-11-09 の監査（[2026-11-09-security-audit.md](../audits/2026-11-09-security-audit.md)）の CI-02 は、取得のスクリプトの一部がキャッシュから戻した実行ファイルを `VERSION` の一致だけで信用し、中身を再ハッシュしないことを情報として挙げた。
`fetch-shem.sh`、`fetch-nvim.sh`、`helix/test.sh`、`fetch-chromium.sh`、`fetch-deno.sh` と、`release.yml` の `fetch-wasmtime.sh` がこれにあたる。
`actions/cache` は展開した木をそのまま戻すので、`VERSION` が一致すればスクリプトは何も照合せずに終わる。
`epubcheck-install.sh` だけは zip をキャッシュし、戻すたびに SHA-256 を照合してから展開している（[ADR 0062](0062-epubcheck-from-release-with-cache.md)）。

### 時間への効果はない

取得の手順は、取れたときは 1 秒から 3 秒で終わる（記録の表 5）。
この ADR は実行の時間を縮めず、取得で落ちる実行と、落ちた実行を手で再実行する手間をなくす。
時間は [ADR 0244](0244-take-verapdf-off-the-critical-path-of-ci.md) が扱う。

## 実装すること

### 1. 補助スクリプト `scripts/ci/fetch-url.sh`

```
fetch-url.sh FILE SHA256 URL [URL...]
```

- `FILE` があり、その SHA-256 が `SHA256` なら、何も取らずに終了コード 0 で終わる。
- そうでなければ、`URL` を順に `curl` で `FILE.part` に取る。一つの `URL` で取れたら残りの `URL` は試さない。`curl` の引数は `--proto '=https' --tlsv1.2 -fsSL --connect-timeout 30 --max-time $FETCH_MAX_TIME` とする。
- すべての `URL` で失敗した試行を一回と数え、`FETCH_ATTEMPTS` 回（既定 3）まで試す。試行のあいだは `FETCH_WAITS`（既定 `10 30`、秒を空白で区切る）の順に待つ。待つ秒の数が足りないときは最後の値を使う。失敗した試行ごとに、`URL`、`curl` の終了コード、次に待つ秒を標準エラーに一行で書く。
- `FETCH_MAX_TIME` の既定は 120 とする。記録の表 10 の最も大きい取得物（Chromium、122 MB）でも、ランナーの帯域なら 30 秒以内に収まる。GitHub の release の配信が 504 を返すのは接続から 120 秒後なので、これより長くしても得るものがない。
- 取れた `FILE.part` の SHA-256 が `SHA256` と違えば、再試行せず、`FILE.part` を消し、SHA-256 の実際の値と期待した値を書いて終了コード 1 で終わる。配信元のファイルが替わったことは一時的な誤りではない。
- `FETCH_ATTEMPTS` 回失敗したら、`FILE.part` を消して終了コード 1 で終わる。`FILE` は作らない。
- SHA-256 が合えば `FILE.part` を `FILE` に `mv` する。`FILE` のディレクトリは作る。
- 再試行の判断は `curl` の `--retry` に任せず、シェルで回す。再試行する誤りを `curl` の一覧に限らず（`curl: (56)` も再試行する）、テストで偽の `curl` に失敗の回数を指定できるようにするためである。
- POSIX sh で書き、macOS の BSD の道具でも動くようにする。`sha256sum` がなければ `shasum -a 256` を使う（今のスクリプトと同じ）。`sleep` の秒は整数とする。

### 2. 取得のスクリプトは補助スクリプトでアーカイブを取り、アーカイブを `third_party/downloads/` に置く

文脈の表の 13 のスクリプトを、次の形にそろえる。

- アーカイブは `$GOLEM_DOWNLOADS`（既定はリポジトリの `third_party/downloads`）の下に、配信元の名前で置く。`fetch-url.sh` でそこに取る。アーカイブがあって SHA-256 が合えば `fetch-url.sh` が取らないので、キャッシュから戻したアーカイブは使う前に必ず照合される。
- 展開先（`third_party/wasmtime`、`third_party/shem` など）と `VERSION` の書き方は変えない。`VERSION` が合えば今までどおり何もしない。CI は展開した木をキャッシュしなくなるので、CI では毎回アーカイブを照合して展開する。
- `fetch-fonts.sh` は、取ったファイルそのものが成果物で、今もファイルごとに SHA-256 を照合してから使っている。`curl` を `fetch-url.sh` に替えるだけとし、置き場所は変えない。
- `epubcheck-install.sh` は、zip の置き場所（`EPUBCHECK_HOME/zip`）を変えず、`curl` を `fetch-url.sh` に替える。
- `fetch-gmp.sh` は、3 つの URL を `fetch-url.sh` にそのまま渡す。
- `fetch-ghc-wasm.sh` は、5 つのアーカイブと `cabal.th.config` を `fetch-url.sh` で取る。アーカイブは `third_party/downloads` に置くが、CI はこれをキャッシュしない（4 を見よ）。
- `fetch-wasm-packages.sh` は、Hackage の 2 つの tarball を `fetch-url.sh` で取る。

### 3. ワークフローはアーカイブだけをキャッシュし、`main` だけが保存する

- `ci.yml` の `build` に、`third_party/downloads` を `downloads-build-${{ runner.os }}-${{ runner.arch }}-${{ hashFiles('scripts/fetch-wasmtime.sh') }}` のキーで戻す `actions/cache/restore` を、`wasmtime C API` の手順の前に足す。`main` への push の `tests-driver`（`matrix.save` のランナー）だけが `actions/cache/save` で保存する。wasmtime の版を上げたプルリクエストは、7 つのランナーが取る（再試行つき）。
- `format` の hlint、`visual` の shem、`editors-lsp` の Neovim、`editors` の Helix、`browser.yml` の Chromium と Deno と wasmtime、`models.yml` の Alloy の jar、`release.yml` の GMP と wasmtime も同じ形にする。キーは `downloads-<ジョブ>-<OS>-<アーキテクチャ>-<取得のスクリプトの hashFiles>` とし、今ある展開した木のキャッシュ（`shem-…`、`nvim-…`、`helix-…`、`chromium-…`、`deno-…`、`wasmtime-…-musl-…`）は使わなくなる。`epubcheck-5.4.0-…` と `manual-fonts-…` はそのまま使う。
- 保存は `github.ref == 'refs/heads/main'` のときだけとする（[ADR 0228](0228-keep-the-ci-caches-under-the-10-gb-limit.md) の方針。`browser.yml` が今そうしている）。プルリクエストの範囲に保存しても、ほかのプルリクエストから戻せず、7 日で消えるだけである。
- `ci.yml` の取得の手順には `timeout-minutes: 10` を置く。再試行の最悪の時間（3 回の 120 秒と待ちの 40 秒で約 7 分）がこの中に収まる。今ある `timeout -k 10 300` の包みは外し、`timeout-minutes` にそろえる。
- 復元のキーは `restore-keys` を持たない。アーカイブは版で決まり、古い版のアーカイブは役に立たない。

### 4. 手を入れない取得

- `third_party/ghc-wasm` のキャッシュ（`ghc-wasm-…`、1.1 GB）は、ツールチェーンの展開した木と、wasm の cabal の store を一つに持つ。store はビルドした結果でアーカイブではなく、ツールチェーンのアーカイブ（約 500 MB）を毎回展開し直すと 100 秒前後かかる（[docs/ci-timings/2026-11-08-wasm-job.md](../ci-timings/2026-11-08-wasm-job.md)）。今の形のままとする。
- `third_party/hosttools`（ネイティブの `alex` と `happy`）も、ビルドした結果なので今のままとする。
- `haskell-actions/setup`（GHC は `ghc-…` のキャッシュから戻す）、`actions/setup-node`、`cachix/install-nix-action`、`haskell-actions/run-fourmolu`、`jdx/mise-action` は、外部の action が自分で取る。この 40 時間に失敗していないので、変えない。
- `actions/download-artifact` の `ENOTFOUND`（1,179 回に 1 回）は、GitHub の API の名前解決の失敗で、この ADR では扱わない。

### 5. `verapdf` の nix に GitHub のトークンを渡す

`verapdf` の `nix build` の手順に、環境変数 `NIX_CONFIG` で `access-tokens = github.com=${{ github.token }}` を渡す。
nixpkgs の tarball を `api.github.com` から認証つきで取るので、429 の上限（認証なしの 60 回/時）にかからない。
ジョブの権限は変えない（`contents: read` のトークンで足りる）。

### 6. 文書と記録

- `CONTRIBUTING.md` と `CONTRIBUTING.en.md` の GitHub Actions の節に、取得は `scripts/ci/fetch-url.sh` で行い、アーカイブを `third_party/downloads` に置いてキャッシュし、戻したアーカイブを使う前に SHA-256 を照合すること、再試行の回数と待ちの既定を書く。epubcheck の段落の「zip は版と SHA-256 をキーにキャッシュする」はそのままとする。
- README.md の CI の表に、取得のキャッシュの列があればそれに合わせる。
- `docs/roadmap.md` の 2026-11-09 の監査の項から CI-02 を外し、この ADR で扱ったと書く。
- `docs/specifications.md` は変えない（Golem の振る舞いは変わらない）。
- 実装のプルリクエストで、wasmtime の版を上げずに 1 回、`gh cache delete` で `downloads-build-…` を消して 1 回走らせ、取得の手順の秒をプルリクエストの説明に書く。
- 2026-11-09 の監査（[2026-11-09-security-audit.md](../audits/2026-11-09-security-audit.md)）は変更不可なので、CI-02 の対応はこの ADR と roadmap に書く。

## 実装しないこと

- **配信元のミラーを立てること、アーカイブをリポジトリに入れること（vendoring）**。取得物は合わせて約 280 MB で、リポジトリに入れると clone が重くなる。ミラー（GitHub のリリースに置き直すなど）は、配信元が GitHub のときは同じ配信の経路に乗り、効果がない。`main` の範囲のキャッシュが、リポジトリの中のミラーの役を果たす。
- **再試行の回数や待ちをスクリプトごとに変えること**。すべて既定（3 回、10 秒と 30 秒）で始め、記録に失敗が残れば ADR で変える。
- **外部の action の SHA 固定（監査の CI-03）**。取得の失敗と別の問題であり、別の ADR で扱う。
- **`tett23/adr-guard` の action の再試行**。action は別のリポジトリにあり、このリポジトリからは変えられない（「メンテナーが決めること」の 4）。
- **`scripts/plugin-licenses.sh`、`scripts/wasmtime-licenses.sh`、`scripts/release/build-linux.sh` の `curl`**。手で走らせる保守のスクリプトか、Alpine のコンテナの中の bootstrap で、CI のプルリクエストの実行では走らない。
- **キャッシュの復元の失敗の再試行**。[ADR 0167](0167-leave-cache-restore-failures-as-misses.md) のとおり、外れとして扱う。記録の 400 回の実行に復元の失敗はなかった。
- **`actions/cache` の `enableCrossOsArchive` や、アーキテクチャをまたぐキーの共有**。アーカイブはアーキテクチャごとに違う。

## 不変条件

`fetch-url.sh` の性質を、テストの述語として書く。

- **I1**：終了コードが 0 なら、`FILE` がありその SHA-256 は `SHA256` である。
- **I2**：呼ぶ前に `FILE` がありその SHA-256 が `SHA256` なら、`curl` は一度も呼ばれない。
- **I3**：`curl` が失敗した試行の回数が `FETCH_ATTEMPTS` に達するまで試行を繰り返し、達したら終了コード 1 で終わる。終わったとき `FILE` も `FILE.part` もない。試行のあいだの待ちの秒は `FETCH_WAITS` の順で、足りなければ最後の値である。
- **I4**：取れたファイルの SHA-256 が `SHA256` と違えば、それ以上 `curl` を呼ばずに終了コード 1 で終わり、`FILE` も `FILE.part` もない。
- **I5**：一回の試行の中で `URL` は与えた順に試され、ある `URL` で取れたら残りの `URL` は呼ばれない。
- **I6**：ワークフローの `actions/cache`、`actions/cache/restore`、`actions/cache/save` の `path` に、`third_party/` の下で `third_party/downloads` と `third_party/ghc-wasm` と `third_party/hosttools` 以外のものがない。展開した木は戻さないので、戻したものはすべて使う前に照合される。
- **I7**：`.github/workflows/*.yml` の `actions/cache/save` で `third_party/downloads` を保存する手順の `if` は、`github.ref == 'refs/heads/main'` を含む。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| `FETCH_ATTEMPTS` | 1、2、3（既定） |
| 失敗する試行の数 | 0、`FETCH_ATTEMPTS - 1`、`FETCH_ATTEMPTS` |
| `FETCH_WAITS` | 空、一つ、試行の数より少ない、同じ |
| `URL` の数 | 1、2（一つめが失敗して二つめが成功、両方が失敗） |
| 呼ぶ前の `FILE` | ない、SHA-256 が合う、合わない、`FILE.part` だけが残っている |
| 取れたファイル | 0 バイト、SHA-256 が合う、合わない |
| `curl` の終了コード | 22（HTTP の誤り）、56（受信の途中で切れた）、28（時間切れ）、6（名前解決） |

## テスト設計

`scripts/ci/test.sh` に `fetch-url.sh` の節を足し、今はスクリプトがないので失敗することを確かめてから実装する。
偽の `curl` を PATH に置く（`scripts/visual/test.sh` の `fetch-shem.sh` の節と同じ方法）。
偽の `curl` は、呼ばれた引数を記録し、環境変数 `FAKE_FAILS` の回数だけ `FAKE_CODE` の終了コードで失敗し、その後は `FAKE_FILE` を `-o` のファイルに書く。
偽の `sleep` は、受け取った秒を記録して眠らない。

- I1、I2：SHA-256 の合う `FILE` を置いて呼び、`curl` が呼ばれず終了コード 0 で終わること。
- I3：`FETCH_ATTEMPTS=3 FETCH_WAITS="1 2"` で `FAKE_FAILS=2` のとき、`curl` が 3 回呼ばれ、`sleep` が 1 と 2 で呼ばれ、終了コード 0 で `FILE` の SHA-256 が合うこと。`FAKE_FAILS=3` のとき、`curl` が 3 回、`sleep` が 1 と 2 で呼ばれ、終了コード 1 で `FILE` も `FILE.part` もないこと。`FETCH_WAITS=5` で `FAKE_FAILS=2` のとき、`sleep` が 5 と 5 で呼ばれること。`FETCH_ATTEMPTS=1` で `FAKE_FAILS=1` のとき、`sleep` が呼ばれず終了コード 1 で終わること。
- I3：`FAKE_CODE` が 22、56、28、6 のどれでも再試行すること。
- I4：SHA-256 の合わないファイルを書く偽の `curl` で、`curl` が 1 回だけ呼ばれ、終了コード 1 で `FILE` も `FILE.part` もないこと。標準エラーに実際の SHA-256 と期待した SHA-256 があること。0 バイトのファイルでも同じこと。
- I5：二つの `URL` で、一つめが失敗して二つめが成功するとき、`curl` が 2 回呼ばれ、順がそのとおりで、終了コード 0 で終わること。両方が失敗する試行が `FETCH_ATTEMPTS` 回続くとき、`curl` が `2 × FETCH_ATTEMPTS` 回呼ばれること。
- `FILE.part` だけが残っているとき、取り直して上書きし、終了コード 0 で終わること。
- `FILE` のディレクトリがないとき、作ること。
- 引数が 2 つ以下のとき、使い方を書いて終了コード 2 で終わること。
- `curl` の引数に `--proto '=https'`、`--tlsv1.2`、`--connect-timeout 30`、`--max-time 120` があること。

既存の取得のスクリプトのテスト（`scripts/visual/test.sh` の `fetch-shem.sh`、`tools/editors/test.sh`、`scripts/test.sh` の `fetch-wasmtime.sh`、`scripts/ci/test.sh` の `epubcheck-install.sh` と `fetch-gmp.sh`）は、偽の `curl` が `fetch-url.sh` 経由で呼ばれる形に直し、次を足す。

- アーカイブが `third_party/downloads`（`GOLEM_DOWNLOADS` で変えた場所）に残ること。
- SHA-256 の合うアーカイブがそこにあるとき、`curl` が呼ばれずに展開されること。
- SHA-256 の合わないアーカイブがそこにあるとき、取り直すこと。

ワークフローの構造の検査を `scripts/ci/test.sh` に足す。

- I6：`.github/workflows/*.yml` のキャッシュの手順の `path` を列挙し、`third_party/` の下は `third_party/downloads`、`third_party/ghc-wasm`、`third_party/hosttools` だけであること。
- I7：`third_party/downloads` を保存する手順の `if` が `refs/heads/main` を含むこと。
- `ci.yml` の `build` で、`third_party/downloads` を戻す手順が `wasmtime C API` の手順より前にあること。
- 取得の手順に `timeout-minutes` があること。
- `verapdf` の `nix build` の手順の `env` に `NIX_CONFIG` があり、`access-tokens = github.com=` を含むこと。

CI を走らせて確かめること（実装のプルリクエストの説明に書く）。

- 実装のプルリクエストの実行で、`build` の 7 つのランナーの `wasmtime C API` の手順が、アーカイブの照合と展開だけで終わること（ログに `fetch-url.sh` の取得の行がないこと）。最初の実行は `main` にキャッシュがないので取る。
- マージの後の `main` への push で、`downloads-build-…` が二つのアーキテクチャで保存されること（`gh cache list --key downloads-`）。
- `gh cache delete` で `downloads-build-…` を一つ消した後の実行で、取り直して通ること。

## トレードオフ

- 取得の失敗で落ちる実行は、配信元が 7 分を超えて止まったときと、版を上げた直後の最初の取得だけになる。その代わり、配信元が止まっているときの失敗は、今の 2 分ではなく最大 7 分かかって失敗する。
- 展開した木をキャッシュしないので、CI は毎回アーカイブを照合して展開する。wasmtime（15 MB の tar.xz）で 1 秒から 2 秒、Chromium（122 MB の zip）で 3 秒前後で、取っていた時間と同じ程度である。
- キャッシュの数は増えない。展開した木のキャッシュ（`shem-…`、`nvim-…`、`helix-…`、`chromium-…`、`deno-…`、`wasmtime-…-musl-…`）がアーカイブのキャッシュに替わり、量は同じ程度（合わせて約 300 MB）である。`build` の `downloads-build-…` は二つのアーキテクチャで約 30 MB 増える。
- 補助スクリプトが一つ増え、13 のスクリプトがそれに依存する。重複していた `curl` と SHA-256 の照合が一か所になる。
- `--retry` を `curl` に任せないので、`curl` の再試行の細かい挙動（`Retry-After` の尊重など）は使わない。配信元の `Retry-After` は 10 秒と 30 秒の待ちより短いことが多く、失うものは小さい。
- 版を上げるプルリクエストは、`main` のキャッシュが新しい版を持たないので、7 つのランナーが取る。今と同じである。

## メンテナーが決めること

1. **再試行の回数と待ち**：推奨は、3 回、待ちは 10 秒と 30 秒、一回の `--max-time` は 120 秒である。記録の 504 は接続から 120 秒で返り、約 100 分の障害のあいだも、落ちた 10 回の実行の 14 の試行では、7 つのランナーの 98 回の取得のうち 66 回は取れていた（失敗は 32 回）。3 回で通る見込みが高く、最悪でも 7 分で失敗する。
   - 退けた案の一つは、5 回で待ちを 10、30、60、120 秒にすることである。最悪で 14 分かかり、CONTRIBUTING の 5 分の方針から遠い。配信元が 100 分止まる障害は何回試しても通らない。
   - 二つめは、`curl --retry 3 --retry-all-errors` に任せることである。再試行の待ちが `curl` の既定（1、2、4 秒）になり短すぎる。偽の `curl` で失敗の回数を指定するテストも書けない。
2. **キャッシュするもの**：推奨は、アーカイブだけをキャッシュし、展開した木はキャッシュしないことである。戻したものを使う前に必ず照合でき（CI-02）、展開の時間は 1 秒から 3 秒である。
   - 退けた案の一つは、今のまま展開した木をキャッシュし、`VERSION` のほかに展開したファイルごとの SHA-256 の一覧を書いて照合することである。スクリプトごとに一覧の形と照合を書くことになり、アーカイブの照合より複雑である。
   - 二つめは、展開した木をキャッシュし、再ハッシュしないままにすることである。監査の CI-02 はリスクを低いとしたが、キャッシュは `main` の範囲でも書き換えられうる（`actions: write` のトークンを持つジョブ、`release.yml` の `ci` の呼び出し）。
3. **保存の範囲**：推奨は、`main` への push だけが保存することである。[ADR 0228](0228-keep-the-ci-caches-under-the-10-gb-limit.md) と `browser.yml` に合わせる。
   - 退けた案は、プルリクエストも保存することである。ほかのプルリクエストから戻せず、7 日で消え、量だけが増える。
4. **`tett23/adr-guard` の action**：推奨は、`tett23/adr-guard` のリポジトリで、action が実行ファイルを取るときに再試行を入れ、取ったファイルを SHA-256 で照合することである。300 回に 1 回の 504 で `docs.yml` が落ちる。このリポジトリでは `uses: tett23/adr-guard@v0.10.0` のままとし、その版が出たら上げる。
   - 退けた案は、このリポジトリで adr-guard の実行ファイルを `fetch-url.sh` で取り、action を使わないことである。adr-guard を使うほかのリポジトリでは役に立たず、action の更新に追随する手間が増える。
5. **`verapdf` の nix**：推奨は、`NIX_CONFIG` でトークンを渡すことである。一行の変更で 429 を避けられる。
   - 退けた案の一つは、veraPDF の closure を `nix copy` でキャッシュに置くことである。Nix の store のキャッシュの出し入れを書くことになり、今の 25 秒を縮める効果も [ADR 0244](0244-take-verapdf-off-the-critical-path-of-ci.md) の後では臨界経路にない。
   - 二つめは、`nix build` の前に `nixpkgs` の tarball を `fetch-url.sh` で取り、`path:` で与えることである。`VERAPDF_NIXPKGS_REV` と tarball の SHA-256 の二つを管理することになる。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-09、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [ADR 0009](0009-ci-speed.md)、[ADR 0062](0062-epubcheck-from-release-with-cache.md)、[ADR 0093](0093-fetch-shem-pinned-by-version-and-sha256.md)、[ADR 0167](0167-leave-cache-restore-failures-as-misses.md)、[ADR 0183](0183-tagged-pdf-and-pdf-a.md)、[ADR 0228](0228-keep-the-ci-caches-under-the-10-gb-limit.md)、[ADR 0231](0231-run-the-lsp-and-the-editor-grammars-in-headless-neovim-and-helix.md)、[ADR 0234](0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md)、[ADR 0244](0244-take-verapdf-off-the-critical-path-of-ci.md)
- [docs/ci-timings/2026-11-09-ci-critical-path-and-download-failures.md](../ci-timings/2026-11-09-ci-critical-path-and-download-failures.md)
- 2026-11-09 の監査（[2026-11-09-security-audit.md](../audits/2026-11-09-security-audit.md)）の CI-02
- [`.github/workflows/ci.yml` の wasmtime の取得](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/.github/workflows/ci.yml#L309-L310)、[同 `verapdf`](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/.github/workflows/ci.yml#L1069-L1090)、[`browser.yml` のキャッシュ](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/.github/workflows/browser.yml#L124-L139)、[`docs.yml` の adr-guard](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/.github/workflows/docs.yml#L35)
- curl のマニュアル（`--retry`、`--retry-all-errors`、`--retry-connrefused`、`--max-time`）, https://curl.se/docs/manpage.html
- GitHub Docs, "Dependency caching reference"（「Restrictions for accessing a cache」）, https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching
- GitHub Docs, "Rate limits for the REST API"（認証なしの 60 回/時）, https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api
- Nix Reference Manual, `access-tokens`, https://nix.dev/manual/nix/stable/command-ref/conf-file#conf-access-tokens
