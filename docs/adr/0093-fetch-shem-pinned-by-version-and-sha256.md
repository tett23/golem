# ADR 0093: 見た目の回帰テストのラスタライザ shem を、版と SHA-256 を固定して配布元の release から取る

ステータス: 採択（未実装）

## 文脈

v0.1.0-rc4 の「見た目の回帰テスト」は、Golem の PDF の出力をページごとの画像にして、前のコミットの出力と比べる（[roadmap の rc4 の項目](https://github.com/tett23/golem/blob/ee7cf504744c48390908701277ae9fcfcdc85d2b/docs/roadmap.md#L23)）。
PDF を画像にするのは、別のリポジトリで Rust で作るラスタライザ shem（[tett23/shem](https://github.com/tett23/shem)）である。
Golem はテストと CI から shem をコマンドとして呼び、golem の実行ファイルにはリンクしない。
比べ方は [ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md) で、CI のジョブは [ADR 0095](0095-visual-job-in-ci.md) で決める。
この ADR は、shem をどこから、どの版で取るかを決める。

### shem の配布と取り決め

shem は 2026-10-26 に v0.1.0-rc1 を、同じ日に v0.1.0-rc2 を GitHub の Releases に出した（どちらも pre-release）。
rc2 は、ページを並べて描く `--jobs`（[shem ADR 0009](https://github.com/tett23/shem/blob/152858295b7949514e05d0ae009e858a1262dfa0/docs/adr/0009-render-pages-in-parallel.md)）と、画像の差分を描く `shem diff`（[shem ADR 0010](https://github.com/tett23/shem/blob/152858295b7949514e05d0ae009e858a1262dfa0/docs/adr/0010-diff-images.md)）を加えた。
rc2 のアーカイブは次の三つと `SHA256SUMS` で、どれも `shem`、`LICENSE`、`README.md` を入れている（[shem の仕様書の「配布」](https://github.com/tett23/shem/blob/152858295b7949514e05d0ae009e858a1262dfa0/docs/specifications.md#L143-L146)）。

| アーカイブ | 大きさ | SHA-256 |
| --- | --- | --- |
| `shem-v0.1.0-rc2-x86_64-unknown-linux-musl.tar.gz` | 515,604 バイト | `42f59599abb744056d32e23c80738c4423b3a1ffe6e518e2a63e8dbfc1396c34` |
| `shem-v0.1.0-rc2-aarch64-unknown-linux-musl.tar.gz` | 496,168 バイト | `65de44c251bf9ec6b6b33243159040483785d9c6d3a0c8e68c943767685eda10` |
| `shem-v0.1.0-rc2-aarch64-apple-darwin.tar.gz` | 410,619 バイト | `d69c660e59bb75d5778416d62bac7246f57255fa79fb0e54a9d34c095dd4ffdf` |

SHA-256 は、rc2 の release の `SHA256SUMS` に書かれた値を写したものである。
手元で取った macOS の aarch64 のアーカイブの SHA-256 は、この値と一致した。
実装では、取ったアーカイブから計算した値と照らしてから書く。
Linux の二つは musl で静的にリンクしているので、ディストリビューションを問わない。
x86-64 の macOS と Windows のアーカイブはなく、shem はこれらを作らないと決めている（[shem ADR 0001 の「実装しないこと」](https://github.com/tett23/shem/blob/152858295b7949514e05d0ae009e858a1262dfa0/docs/adr/0001-scope-golem-contract-and-determinism.md#L87)）。

[shem ADR 0001](https://github.com/tett23/shem/blob/152858295b7949514e05d0ae009e858a1262dfa0/docs/adr/0001-scope-golem-contract-and-determinism.md) は、Golem との取り決めとして次を定めている（[「Golem との取り決め」](https://github.com/tett23/shem/blob/152858295b7949514e05d0ae009e858a1262dfa0/docs/adr/0001-scope-golem-contract-and-determinism.md#L42-L48)）。

- Golem は、shem のリリースのタグとアーカイブの SHA-256 を固定して取得する。
- Golem の Writer が新しい演算子や資源を書くようになるときは、先に shem を直してリリースし、その後で Golem が固定している版を上げる。
- 同じ入力に対する画素を変える変更は、マイナーバージョンを上げる。リリースノートの「変更」に、画素が変わることと、変わる入力の種類を書く。
- 画素を変えない変更は、パッチバージョンを上げる。

shem は、読む部分集合の外の入力に出会うと、ファイルを一つも書かずに終了コード 1 で終わる（[shem の仕様書の「コマンド」](https://github.com/tett23/shem/blob/152858295b7949514e05d0ae009e858a1262dfa0/docs/specifications.md#L32-L35)）。
Golem の Writer が shem の知らない演算子を書けば、見た目の回帰テストはそこで止まる。

### Golem がほかの道具を取る形

Golem には、外部の道具を版と SHA-256 で固定して取るスクリプトがすでにある。
shem に近いのは次の三つである。

- [`scripts/fetch-wasmtime.sh`](https://github.com/tett23/golem/blob/ee7cf504744c48390908701277ae9fcfcdc85d2b/scripts/fetch-wasmtime.sh) は、版と、OS とアーキテクチャごとの SHA-256 をスクリプトの中に書き、`third_party/wasmtime/VERSION` に取ったアーカイブの名前と SHA-256 を残す。二つが一致すれば取り直さない（[ADR 0044](0044-release-workflow-hardening.md)）。手元と CI が同じスクリプトを使う。
- [`scripts/ci/epubcheck-install.sh`](https://github.com/tett23/golem/blob/ee7cf504744c48390908701277ae9fcfcdc85d2b/scripts/ci/epubcheck-install.sh) は、版と SHA-256 を `ci.yml` から受け取り、zip を `actions/cache` に置く（[ADR 0062](0062-epubcheck-from-release-with-cache.md)）。apt のミラーの停止で CI の 18% が落ちていたことが、配布元から取ってキャッシュする理由だった。
- [`scripts/ci/fetch-hlint.sh`](https://github.com/tett23/golem/blob/ee7cf504744c48390908701277ae9fcfcdc85d2b/scripts/ci/fetch-hlint.sh) は、x86-64 の Linux だけを扱い、CI でだけ使う。

shem は、CI だけでなく手元でも要る。
意図して見た目を変えたとき、開発者は手元で参照を作り直すからである（[ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md)）。
このため、版と SHA-256 を `ci.yml` に置く epubcheck の形ではなく、スクリプトに置く wasmtime の形が合う。

## 実装すること

### 取得のスクリプト

- `scripts/visual/fetch-shem.sh` を新しく置く。shem を `third_party/shem/` に入れる。
- 版（`0.1.0-rc2`）と、三つのアーカイブの SHA-256 をスクリプトの中に書く。SHA-256 は上の表の値とする。
- `uname -s` と `uname -m` から、取るアーカイブを決める。

  | `uname -s`-`uname -m` | ターゲット |
  | --- | --- |
  | `Darwin-arm64` | `aarch64-apple-darwin` |
  | `Linux-x86_64` | `x86_64-unknown-linux-musl` |
  | `Linux-aarch64` | `aarch64-unknown-linux-musl` |

- ほかの組み合わせでは、取らずに終了コード 1 で終わる。標準エラーには、配布物がないことと、下の `SHEM` で自分でビルドした shem を使えることを書く。
- 取る URL は `https://github.com/tett23/shem/releases/download/v<版>/shem-v<版>-<ターゲット>.tar.gz` とする。`curl -fsSL --connect-timeout 30 --retry 3` で一時的な名前に取り、SHA-256 がスクリプトの値と一致したときだけ展開する。一致しなければ、何も入れずに終了コード 1 で終わる。release の `SHA256SUMS` は取らない。同じ release から取った一覧は、アーカイブの差し替えに対して何も保証しないからである。
- 展開した `shem` を `third_party/shem/shem` に置き、`third_party/shem/VERSION` にアーカイブの名前と SHA-256 を一行で書く。`VERSION` がスクリプトの値と一致すれば、ネットワークに接続せずに終わる。
- 入れた後に `third_party/shem/shem --version` を実行し、`shem <版>` が出ることを確かめる。出なければ終了コード 1 で終わる。
- `fetch-shem.sh --expected` は、`VERSION` に書くはずの行を出して終わる（`fetch-wasmtime.sh` と同じ）。
- 使う道具は `uname`、`curl`、`tar`、`sha256sum` か `shasum -a 256`、`cut` だけとし、BSD 版と GNU 版のどちらでも動くように書く。Python は使わない。

### 見つからない環境と、自分でビルドした shem

- 環境変数 `SHEM` に実行ファイルのパスがあれば、見た目の回帰テストのスクリプトは `fetch-shem.sh` を呼ばず、そのパスの shem を使う。
- そのときも、`$SHEM --version` が `shem <固定した版>` でなければ失敗にする。版の違う shem で作った参照は、画素が違いうるからである（shem の取り決めの、画素を変える変更）。
- `SHEM` は、x86-64 の macOS のように配布物のない環境の開発者が、shem の固定した版のタグを `cargo build --release` でビルドして使うためのものである。shem の決定性の約束（x86-64 と aarch64、Linux と macOS で同じ画素）により、どの環境でビルドしても同じ画素を出す（[shem の仕様書の「決定性」](https://github.com/tett23/shem/blob/152858295b7949514e05d0ae009e858a1262dfa0/docs/specifications.md#L131-L139)）。
- CI は `SHEM` を使わない。

### CI での取得

- [ADR 0095](0095-visual-job-in-ci.md) の `visual` ジョブは、`third_party/shem` を `actions/cache` に置く。キーは `shem-${{ hashFiles('scripts/visual/fetch-shem.sh') }}` とする。版か SHA-256 を変えればスクリプトが変わり、キーも変わる。
- キャッシュを戻した後に `timeout -k 10 300 sh scripts/visual/fetch-shem.sh` を実行する。キャッシュがあれば `VERSION` の一致で何も取らず、なければ取る。止まった接続で 5 分を使い切れば、終了コード 124 でジョブが失敗する（[ADR 0062](0062-epubcheck-from-release-with-cache.md) と同じ上限）。

### 版を上げるとき

- 版を上げるときは、`fetch-shem.sh` の版と三つの SHA-256 を変えるプルリクエストを出す。SHA-256 は、取ったアーカイブから自分で計算し、release の `SHA256SUMS` と一致することを確かめてから書く。
- マイナーバージョンを上げるとき（0.x の間は `0.x` の x）は、shem の取り決めにより画素が変わりうる。同じプルリクエストで、[ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md) の参照を作り直す。プルリクエストの説明には、shem のリリースノートの「変更」を引く。
- パッチバージョンを上げるときは、参照を変えない。CI でページのハッシュが変われば、shem が取り決めに反しているので、参照を受け入れずに shem の側で直す。
- Golem の Writer が新しい演算子や資源を書く変更は、shem がそれを読める版をリリースしてから入れる。版を上げる変更は、Writer の変更と同じプルリクエストか、その前のプルリクエストに入れる。shem が読めない PDF を Golem が書けば、`visual` ジョブが shem のエラーで失敗する（[ADR 0095](0095-visual-job-in-ci.md)）。
- shem の pre-release（`-rc` の付いた版）も固定してよい。shem が 0.x の間は、Golem の rc4 に合わせて出る版がどれも pre-release になりうるからである。

### 文書

- README の Development の節に、見た目の回帰テストを手元で動かすには shem が要ることと、`scripts/visual/fetch-shem.sh` が取ること、配布物のない環境では `SHEM` を使うことを書く。
- CONTRIBUTING.md と開発者のマニュアルの「ビルドとテスト」の章（`manual-dev/part2/08-build-test.gm`）に、版を上げる手順と、Writer の変更より先に shem を直す規則を書く。
- `docs/specifications.md` の「識別子」の節で、HarfBuzz、FreeType、wasmtime、zlib の版の固定を書いた段落の後に、テストにだけ使う道具として shem の版を固定することを書き、この ADR へリンクする。

## 実装しないこと

- CI で shem をソースからビルドすること。Rust の環境を CI に足すことになり、ビルドの時間もかかる。
- shem を Git のサブモジュールや、ソースの写しとして Golem のリポジトリに置くこと。
- x86-64 の macOS と Windows のアーカイブを Golem の側で作ること。配布物は shem が決める。
- Homebrew などのパッケージの管理の道具から shem を入れること。版を固定できないからである。
- アーカイブの署名や GitHub の attestation を確かめること。SHA-256 の固定で、取ったものが固定した版と同じであることは確かめられる。
- golem の実行ファイルや配布物に shem を含めること。shem はテストにだけ使う。

## テスト設計

テストを先に書き、今の実装で失敗することを確かめる。

- `scripts/visual/test.sh` を新しく置き、`fetch-shem.sh` の次の振る舞いを確かめる。ネットワークは使わず、`PATH` の先頭に置いた偽の `curl` と `uname` で動かす。偽の `curl` は、テストが作った小さなアーカイブ（`shem --version` に答える偽の `shem` を入れたもの）を書く。
  - SHA-256 が一致すれば、`third_party/shem/shem` と `VERSION` ができること。テストは、スクリプトの中の SHA-256 を、テストのアーカイブの値に置き換えた写しで動かす。
  - SHA-256 が一致しなければ、終了コード 1 で、`third_party/shem` に何も残らないこと。
  - `VERSION` が一致していれば、`curl` が呼ばれないこと。
  - `uname` が `Darwin-x86_64` を返せば、終了コード 1 で、標準エラーに `SHEM` が現れること。
  - 入れた `shem --version` が別の版を出せば、終了コード 1 で終わること。
  - `--expected` が、`<アーカイブの名前> <SHA-256>` の一行を出すこと。
- `SHEM` に別の版を答える偽の shem を置くと、[ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md) の比べるスクリプトが失敗することを、同じ `test.sh` で確かめる。
- `scripts/ci/test.sh` に、`ci.yml` の `visual` ジョブが `third_party/shem` を `fetch-shem.sh` のハッシュをキーにキャッシュし、`fetch-shem.sh` を `timeout` の下で動かすことを確かめる項目を足す（今の `step_if` と同じ形）。
- 実装のプルリクエストで、手元の macOS の aarch64 と CI の x86-64 の Linux で、本物のアーカイブを取って `shem --version` が `shem 0.1.0-rc2` を出すことを確かめる。aarch64 の Linux のアーカイブは、取ったものの SHA-256 が `SHA256SUMS` と一致することだけを確かめる。

## トレードオフ

- Golem の CI と手元のテストが、shem の GitHub の release に依存する。CI はキャッシュがあれば取りに行かない。アーカイブは 0.52 MB に満たない。
- Writer が新しい演算子を書く変更は、shem のリリースを待つ。shem も同じメンテナーが作るので待ちは短いが、二つのリポジトリにまたがる手順になる。黙って読み飛ばす shem なら待たずに済むが、新しい描画が画像に現れず、変化を見逃す（[shem ADR 0001](https://github.com/tett23/shem/blob/152858295b7949514e05d0ae009e858a1262dfa0/docs/adr/0001-scope-golem-contract-and-determinism.md) のトレードオフ）。
- `SHEM` で渡した shem は、SHA-256 を確かめない。確かめるのは版の文字列だけである。CI は `SHEM` を使わないので、手元の参照が誤った shem で作られても、CI の比較で見つかる。
- 版と SHA-256 をスクリプトに書くので、`ci.yml` の値を見ても版がわからない。`fetch-wasmtime.sh` と同じ置き方で、手元と CI が同じ値を読む。

## 参考文献

- [ADR 0044](0044-release-workflow-hardening.md)
- [ADR 0062](0062-epubcheck-from-release-with-cache.md)
- [ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md)
- [ADR 0095](0095-visual-job-in-ci.md)
- Golem の roadmap の rc4「見た目の回帰テスト」https://github.com/tett23/golem/blob/ee7cf504744c48390908701277ae9fcfcdc85d2b/docs/roadmap.md#L23
- [shem ADR 0001「目的と版ごとの範囲、Golem との取り決め、決定性の約束」](https://github.com/tett23/shem/blob/152858295b7949514e05d0ae009e858a1262dfa0/docs/adr/0001-scope-golem-contract-and-determinism.md)
- shem の仕様書 https://github.com/tett23/shem/blob/152858295b7949514e05d0ae009e858a1262dfa0/docs/specifications.md
- shem v0.1.0-rc2 の release https://github.com/tett23/shem/releases/tag/v0.1.0-rc2
