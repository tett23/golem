# ADR 0050: `golem` をすべてのプロセッサの上で動かし、環境を変える検査で capability の数を変える

ステータス: 採択

## 文脈

[ADR 0029](0029-environment-variation-determinism-test.md) は、実行の環境を変えて `golem build` の出力の一致を確かめる検査（`scripts/env-determinism/check.sh`）を定めた。
「実装しないこと」には、capability の数（`+RTS -N`）を変えることを挙げ、次のように書いた。

> `-N` を有効にするときは、この検査に capability の数の変化を足す ADR を書く。

当時の `golem` の実行ファイルは `-threaded` だが `-N` を指定しておらず、capability は常に一つだった。

その後、[PR #170](https://github.com/tett23/golem/pull/170) が FreeType の `FT_Face` にフォントごとのロックを足し、`golem` を `-N` で動かすようにした（[ADR 0035](0035-security-hardening.md) の「実装しないこと」に記録がある）。
今は次のとおりである。

- `modules/golem-cli/golem-cli.cabal` の `executable golem` は、`-threaded "-with-rtsopts=-N"` でリンクする。golem-cli のテストのスイートも同じである。
- [CONTRIBUTING.md](../../CONTRIBUTING.md) は、`-threaded` でビルドする実行ファイルとテストのスイートを `-with-rtsopts=-N` でリンクし、コードの中で `setNumCapabilities` を呼ばないと定める。GHC 9.10.3 のランタイムは、二つの `setNumCapabilities` が同時に capability を増やすと止まるためである。CI の `changes` ジョブの `scripts/ci/rts-capabilities.sh` がこれを検査する。
- golem-cli の `test/RtsSpec.hs` は、`golem +RTS --info -RTS` の出力に `rts_thr` と `-with-rtsopts` の `-N` があることを確かめる。
- 仕様書（[docs/specifications.md](../specifications.md) の「CLI」の節、2749 行）は、`golem` がすべてのプロセッサの上で動き、出力のバイト列はプロセッサの数によらないと書く。

[ADR 0029](0029-environment-variation-determinism-test.md) が求めた ADR は書かれていない。
環境を変える検査は、今も capability の数を変えていない。

### capability の数を外から変えられるか

[ADR 0029](0029-environment-variation-determinism-test.md) は「`-rtsopts` を持たず」と書き、capability の数を外から変えられないことを、変えない理由の一つにした。
しかし、`-rtsopts` を付けずにリンクした実行ファイルも、GHC の既定（`-rtsopts=some`）で、安全とされる一部の RTS のオプションを受け付ける。
`-N` はその一つである。
GHC 9.10.3 で、`-threaded "-with-rtsopts=-N"` だけでリンクした小さなプログラム（`getNumCapabilities` を表示するもの）を、10 個のプロセッサの macOS で動かして確かめた。

| 起動のしかた | capability の数 |
|---|---|
| そのまま | 10 |
| `+RTS -N1 -RTS` | 1 |
| 環境変数 `GHCRTS=-N1` | 1 |
| 環境変数 `GHCRTS=-N2` | 2 |
| `GHCRTS=-N1` と `+RTS -N3 -RTS` | 3 |
| `+RTS -A64m -RTS`、`GHCRTS=-A64m` | 起動せず、`Most RTS options are disabled. Link with -rtsopts to enable them.` を出す |

ランタイムは、`-with-rtsopts` の後に `GHCRTS` を、その後にコマンド行の `+RTS` を読み、後のものが前のものを上書きする。
したがって、`golem` をリンクし直さずに、`GHCRTS` で capability の数を変えられる。
`GHCRTS` は環境変数なので、`check.sh` の他の変化（`TZ`、`LANG` など）と同じ形で足せる。

## 実装すること

### `-N` の追認

- `golem` の実行ファイルを `-threaded "-with-rtsopts=-N"` でリンクし、起動のときから capability を計算機のプロセッサの数だけ持たせることを、この ADR で採択する。
- コードの中で `setNumCapabilities` を呼ばない規則と、`scripts/ci/rts-capabilities.sh` の検査は、今のまま保つ。
- 出力のバイト列と diagnostics は、capability の数によらない。[ADR 0002](0002-determinism.md) の決定性の範囲に、capability の数を含める。
- 利用者が `GHCRTS=-N<n>` か `+RTS -N<n> -RTS` で capability の数を変えても、出力は変わらない。仕様書にこれを書く。`-rtsopts` は足さない。

### 環境を変える検査

`scripts/env-determinism/check.sh` に、二つの変化を足す。

| 名前 | 変えるもの |
|---|---|
| `caps-one` | `GHCRTS=-N1`。capability を一つにして、段落の組版を交互に動くスレッドの上で逐次に進める |
| `caps-two` | `GHCRTS=-N2`。capability を二つにして、段落の組版を本当に同時に、ただし基準と違う度合いで進める |

- 基準の環境は `GHCRTS` を与えない。`-with-rtsopts=-N` のとおり、利用者の計算機と同じく、すべてのプロセッサの capability で動く。capability の数を固定の値にはしない。
- 二つの変化は、他の一つずつの変化と同じく、小さな入力（`exprs`、`sample`、`sample-pdf`、`diagnostics`）に当てる。
- `combined` には `GHCRTS=-N2` を足す。逐次（`-N1`）にすると、大きな入力で並列の組版の誤りを見つけるのが遅れるためである。`-N2` なら、大きな入力も並列に組んだまま、基準と違う capability の数で確かめられる。
- 1 と 2 の組を選んだのは、次の理由による。1 は並列のない場合であり、並列にしたことで出力が変わる誤りを、基準との比較で直接に示す。2 は並列のある最小の数であり、基準（すべてのプロセッサ）と仕事の分かれ方が変わる。どちらもプロセッサの数によらない値なので、どの計算機でも同じ意味の変化になる。プロセッサが二つの計算機では `caps-two` が基準と同じになるが、検査が誤って失敗することはない。
- `check.sh` の先頭のコメントと `CHANGES` の一覧に、二つの名前を足す。
- `GHCRTS` は `env -i` に渡す変数の一つとして足す。他の変化と同じく、外の環境の `GHCRTS` は `golem` に届かない。

### ドキュメント

- [ADR 0029](0029-environment-variation-determinism-test.md) のステータスの行を「採択→CI で `--quick` を付けるかどうかは [ADR 0038](0038-env-determinism-quick-on-pull-requests.md)、capability の数を変えることは [ADR 0050](0050-run-golem-on-every-processor.md)」に改める。
- 仕様書の「CLI」の節の `-N` の段落に、`GHCRTS=-N<n>` と `+RTS -N<n> -RTS` で capability の数を変えられ、出力は変わらないことを書き、この ADR へのリンクを付ける。
- 仕様書の決定性の節（505 行の `check.sh` の文）に、capability の数も変えることを足す。
- 開発者のマニュアルの第 12 章「決定性を守る」の変化の一覧に、`caps-one` と `caps-two` を足し、`combined` が `-N2` で組むことを書く。
- 開発者のマニュアルの「純粋性」の章の「並列の組版」の節の最後の文（`golem` の実行ファイルも `-with-rtsopts=-N` でリンクする）に、環境を変える検査が capability の数を変えて確かめることを足す。
- 利用者のマニュアルは変えない。`GHCRTS` は利用者が知る必要のない設定である。

## 実装しないこと

- `-rtsopts` でリンクし、すべての RTS のオプションを受け付けること。`-A` や `-M` のような GC の設定は出力に影響しないはずだが、利用者に開く理由がない。
- capability の数を、これより多くの値で網羅すること。基準（すべてのプロセッサ）、1、2 の三点で、逐次と、度合いの違う二つの並列を作れる。
- プロセッサの数より多い capability を与える変化。固定の大きな値は、計算機によって意味が変わる。
- 一つの変化を何度も繰り返して、スケジューリングの揺らぎを拾うこと。検査の時間が繰り返しの数に比例して延びる。並列と逐次の一致は、golem-driver の `golem-driver-parallel-test` がプロセスの中で、複数の入力について確かめている。
- `GHCRTS` に `-N` 以外の安全なオプション（`-s` など）を与える変化。出力のファイルと標準出力には影響せず、`-s` は標準エラー出力に統計を書くので、比べる意味がない。
- `golem` 以外のプログラム（LSP、`golem fmt`）の capability の数。[ADR 0029](0029-environment-variation-determinism-test.md) と同じく、`golem build` の出力に限る。

## テスト設計

### check.sh が変化を当てること（`scripts/env-determinism/test.sh`）

先に書き、失敗させてから `check.sh` を改める。

- `GHCRTS` を書く偽の `golem`（`printf "%s" "${GHCRTS-unset}" >build/out.txt`）で、`check.sh` が `FAIL caps-one`、`FAIL caps-two`、`FAIL combined` を出して失敗すること。今は二つの変化がなく、`combined` も `GHCRTS` を与えないので失敗する。
- 決まった文字列を書く偽の `golem` で、`ok   caps-one exprs` と `ok   caps-two exprs` が出ること。
- `--only caps-one` と `--only caps-two` が未知の変化として拒まれないこと。

### golem が GHCRTS の -N を受け付けること（golem-cli の `test/RtsSpec.hs`）

- `GHCRTS=-N1` を与えて `golem +RTS -s -RTS` を（引数の誤りで終わるコマンドでよい）動かし、標準エラー出力の統計に `using -N1` があること。`-with-rtsopts=-N` の後に `GHCRTS` が適用されることを、実際の `golem` で確かめる。
- `GHCRTS=-N2` で同じく `using -N2` があること。
- この二つは、今のリンクのままで通る。リンクの設定を変えて `GHCRTS` が無視されるようになったとき（`-rtsopts=none` など）に失敗する。

### 実際の検査

- 実装の後、手元で `sh scripts/env-determinism/check.sh --only caps-one` と `--only caps-two` を実行し、すべての小さな入力が `ok` になることを確かめる。
- CI の `build` ジョブの環境を変える検査が、`main` への push で `combined` を含めて通ることを確かめる。

## トレードオフ

`caps-one` と `caps-two` は、それぞれ小さな入力を一度ずつ組む。
小さな入力は数秒で組めるので、検査の時間の増え方は小さい。
`combined` は大きな入力を `-N2` で組むので、プロセッサの多いランナーでは基準より遅くなるが、逐次で組むよりは速い。
プルリクエストの検査は [ADR 0038](0038-env-determinism-quick-on-pull-requests.md) のとおり `--quick` なので、大きな入力には影響しない。

一度の実行で一致しても、スケジューリングによる非決定性がないことの証明にはならない。
この検査が拾うのは、capability の数そのものに出力が依存する誤り（スレッドの数で仕事を分け、分け方が結果に出るなど）と、並列の度合いが変わったときに起きやすい誤り（終わった順に diagnostics を並べるなど）である。
後者は確率的にしか拾えない。
`golem-driver-parallel-test` と、`mapConcurrently` が結果を入力の順に返す構造が、主な守りである。

`GHCRTS` を使うので、`golem` を `-rtsopts=none` でリンクし直すと、この変化は黙って何も変えなくなる。
RtsSpec のテストが `using -N1` を確かめるので、その場合はテストが失敗する。

## 参考文献

- [ADR 0002](0002-determinism.md)
- [ADR 0029](0029-environment-variation-determinism-test.md)
- [ADR 0035](0035-security-hardening.md)
- [ADR 0038](0038-env-determinism-quick-on-pull-requests.md)
- [golem-driver ADR 0002](../golem-driver/adr/0002-pdf-pipeline.md)
- GHC User's Guide, Options affecting linking, `-rtsopts`。https://downloads.haskell.org/ghc/9.10.3/docs/users_guide/phases.html#ghc-flag-rtsopts
- GHC User's Guide, Running a compiled program, Setting RTS options with the `GHCRTS` environment variable。https://downloads.haskell.org/ghc/9.10.3/docs/users_guide/runtime_control.html
