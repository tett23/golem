# ADR 0157: 固定した wasmtime の版を、上流のアドバイザリと毎日照合する

ステータス: 採択→範囲、修正版、パッケージの読み方は [ADR 0166](0166-read-wasmtime-advisory-ranges-as-written.md)

## 文脈

wasmtime の GHSA-mghf-wjfp-p5xm（CVE-2026-115893）は 2026-10-19 に公開された。
Golem がこれを知ったのは、2026-11-05 の [セキュリティ監査](../audits/2026-11-05-security-audit.md) の V-01 である。
その間の 2026-10-24 に、49.0.2 とリンクした v0.1.0-rc3 を公開した。
固定した版が既知の脆弱性の範囲に入ったことを、Golem は人が調べるまで知る手段を持っていない。
[ADR 0156](0156-wasmtime-49-0-5.md) は版を上げるが、次のアドバイザリにも同じ遅れが起きる。

### アドバイザリの取り方

GitHub の Advisory Database の全体の API（`GET /advisories?ecosystem=rust&affects=wasmtime@49.0.2`）は、版の範囲の判定をサーバーの側で行う。
2026-11-05 に試すと、49.0.2 に当たるものとして二件だけを返した。
同じ日に、bytecodealliance/wasmtime のリポジトリのアドバイザリの API（`GET /repos/bytecodealliance/wasmtime/security-advisories`）は、49.0.2 を範囲に含むものを 25 件返した。
全体のデータベースへの反映は遅れるので、リポジトリのアドバイザリを読む。

リポジトリのアドバイザリの `vulnerabilities[].vulnerable_version_range` は、次のような形で書かれている。

- `<36.0.19, >=37.0.0, <48.0.7, >=49.0.0, <49.0.4`（範囲の和をカンマで並べたもの）
- `>= 49.0.0, < 49.0.5`、`<= 36.0.17`、`50.0.0`（一つの版）、`>=49.0.0, <=49.0.2`

カンマで区切った比較を「かつ」で読むと、最初の例は空の範囲になる。
上流は、下限（`>=`）で区間を始め、上限（`<` か `<=`）で区間を閉じる並びとして書いている。
パッケージの名前は `wasmtime`、`wasmtime-wasi`、`wasmtime-wasi-http` などで、版は wasmtime の版と同じ番号を使う。

## 実装すること

### 照合のスクリプト

`scripts/wasmtime-advisories.sh [ADVISORIES_JSON]` を足す。
POSIX のシェルと `jq` で書く。

- 固定した版は、`scripts/fetch-wasmtime.sh --expected` の出力の名前から取り出す。
- 引数があれば、そのファイルをアドバイザリの一覧（API の応答の JSON の配列）として読む。なければ `gh api --paginate '/repos/bytecodealliance/wasmtime/security-advisories?per_page=100&state=published'` で取得する。
- アドバイザリごと、`vulnerabilities` の要素ごとに、範囲を次の規則で区間の並びに読む。
  - カンマで区切り、各項目の前後の空白を除く。比較の記号と版のあいだの空白も除く。
  - `>=` か `>` の項目は区間を始める。開いた区間があれば誤りとする。
  - `<` か `<=` の項目は区間を閉じる。開いた区間がなければ、下限のない区間として閉じる。
  - 記号のない版か `=` の項目は、その版だけの区間とする。
  - 最後に開いた区間が残れば、上限のない区間とする。
  - 版は `<数>.<数>.<数>` に限り、数として比べる。読めない項目は誤りとする。
- パッケージの名前が `wasmtime` か `wasmtime-` で始まるものだけを照合する。ほかの名前（`cranelift-codegen` など、版の番号が違うもの）があれば、照合できないアドバイザリとして誤りとする。
- 固定した版がどれかの区間に入るアドバイザリを、`GHSA の ID<TAB>重大度<TAB>パッケージ<TAB>範囲<TAB>概要` の行で標準出力に書く。
- 当たるものがなく、誤りもなければ終了コード 0、当たるものがあれば 1、誤りがあれば 2 で終える。

当たったアドバイザリが Golem のホストに届くかは判定しない。
届かないと判断して照合から外す一覧も持たない。
当たったときは版を上げる（[CONTRIBUTING.md](../../CONTRIBUTING.md) のとおり ADR を書く）。

### ワークフロー

`.github/workflows/advisories.yml` を足す。

- `schedule`（一日に一度）と `workflow_dispatch` で動く。
- `permissions` は `contents: read` だけとし、`gh` には `GITHUB_TOKEN` を渡す。公開されたアドバイザリは読み取りの権限で読める。
- ジョブは checkout と `sh scripts/wasmtime-advisories.sh` だけを行う。
- 失敗すると、スケジュールの実行の通知が GitHub からメンテナーに届く。

プルリクエストの CI では、この照合を走らせない。
ネットワークの状態と、上流がアドバイザリを公開した時刻によって、同じコミットの結果が変わるためである。
ただし、`scripts/fetch-wasmtime.sh` を変えたプルリクエストでは、作者が手元で照合し、出力をプルリクエストの説明に貼る。
この手順を CONTRIBUTING.md と CONTRIBUTING.en.md の wasmtime の版を上げる段落に書く。

### ドキュメント

- 仕様書の、固定したライブラリの版を書いた節に、wasmtime の版をアドバイザリと毎日照合することを書く。
- 開発者向けマニュアルの、wasmtime の取得を説明する章（`manual-dev/part2/08-build-test.gm`）に、スクリプトとワークフローを書く。

## 実装しないこと

- プルリクエストの CI で照合して、マージを止めること。理由は「ワークフロー」の節にある。
- 届かないアドバイザリを照合から外す一覧。外す判断を誤ると黙って脆弱な版が残る。一覧がなければ、届かないアドバイザリでも版を上げることになるが、厳しい側に倒す。
- wasmtime の版のサポートの終わりの検査。上流は終わりの日付を API で返さず、規則から計算することになる。版を追う方針は別の ADR で決める。
- HarfBuzz、FreeType、zlib、GHC、Haskell のパッケージのアドバイザリの照合。wasmtime は信頼できない入力（プラグイン）を実行するので、先に扱う。ほかのものは必要になったときに ADR を書く。
- イシューを自動で作ること。ワークフローの失敗の通知で足りる。
- GitHub の Dependabot。Golem は wasmtime を Cargo の依存としてではなく、スクリプトの版と SHA-256 で固定しているので、Dependabot はこれを見ない。

## テスト設計

`scripts/test.sh`（[ADR 0078](0078-tests-for-release-and-hand-run-scripts.md)）に足す。
ネットワークを使わず、アドバイザリの一覧は fixture の JSON で渡す。
fixture は、2026-11-05 に API で取得した実際のアドバイザリから、ID、重大度、`vulnerabilities`、概要だけを残して作る。
固定した版は、`fetch-wasmtime.sh --expected` の代わりに環境変数 `WASMTIME_VERSION` で渡せるようにし、テストではそれを使う。

- GHSA-mghf-wjfp-p5xm の範囲 `<36.0.19, >=37.0.0, <48.0.7, >=49.0.0, <49.0.4` で、49.0.2、49.0.3、36.0.18、37.0.0、48.0.6 が当たり、49.0.4、49.0.5、36.0.19、48.0.7、50.0.0 が当たらない。
- `>= 49.0.0, < 49.0.5`（空白を含む形）で 49.0.4 が当たり、49.0.5 が当たらない。
- `<= 36.0.17` で 36.0.17 が当たり、36.0.18 が当たらない。
- 一つの版の `50.0.0` で、50.0.0 だけが当たる。
- `vulnerabilities` が複数の要素を持つアドバイザリ（GHSA-h4wp-g4x3-7398 の形）で、どの要素に当たっても一行だけ書く。
- 49.0.2 で、fixture の全体に対して当たるアドバイザリの ID の一覧が、手で数えた一覧と一致し、終了コードが 1 である。
- 49.0.5 で何も当たらず、終了コードが 0 である。
- パッケージの名前が `cranelift-codegen` のアドバイザリで、終了コードが 2 である。
- 読めない範囲（`>=49.0.0, >=50.0.0`、`~49.0`）で、終了コードが 2 である。

テストは、照合の誤りの方向（当たるべきものが当たらない）を確かめるものを先に書き、失敗させてから実装する。
ワークフローは、`workflow_dispatch` で一度動かし、49.0.5 で成功することを確かめる。

## トレードオフ

- 照合は毎日なので、アドバイザリの公開から最大で一日遅れて知る。プルリクエストの CI で走らせれば遅れは減るが、上流の公開によって無関係なプルリクエストが落ちる。
- 範囲の書き方の読み方は、上流の今の書き方から推した規則である。上流が書き方を変えて読めなくなれば、スクリプトは誤り（終了コード 2）で止まり、黙って通さない。
- 届かないアドバイザリでも失敗するので、wasi-http だけのアドバイザリでも版を上げることになる。サポートの終わった系列では、メジャー版を上げることになりうる。
- `gh` と `jq` に依存する。どちらも GitHub のランナーに入っている。

## 決めたことの記録

- **採択**：メンテナーが採択した（2026-11-05）。この ADR が決めてほしい点として挙げた項目は、どれも ADR の推奨のとおりとする。

## 参考文献

- [2026-11-05 のセキュリティ監査](../audits/2026-11-05-security-audit.md)
- GitHub REST API, "Repository security advisories". https://docs.github.com/en/rest/security-advisories/repository-advisories
- GitHub REST API, "Global security advisories". https://docs.github.com/en/rest/security-advisories/global-advisories
- bytecodealliance/wasmtime の Security Advisories の一覧（2026-11-05 に API で取得）。https://github.com/bytecodealliance/wasmtime/security/advisories
