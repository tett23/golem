# ADR 0212: patch のリリースの検査を、前のリリースの入力を組み直して行う

ステータス: 採択（未実装）

## 文脈

[ADR 0174](0174-compatibility-promises-for-1-0.md) は、1.0.0 から、patch のバージョンが Golem のバージョンから作る値（PDF の Producer とインスタンス ID）のほかに出力を変えないと約束した。
その実装の [`check-patch.sh`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/scripts/release/check-patch.sh) は、リリースのワークフローの `version` ジョブで動く（[`release.yml`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/.github/workflows/release.yml#L62-L66)）。
作るタグが直前のリリースの patch なら、見た目の回帰テストの参照 `scripts/visual/pages/` と、決定性の検査のハッシュの一覧 `scripts/determinism/hashes.txt`（PDF の行を除く）が、二つのタグで同じであることを確かめる。

Fable の ADR のレビュー（2026-11-08）は、この検査に二つの逸脱を見つけた。
どちらも、メンテナーはすべて直すとした。

### rc から正式の版への移り

直前のリリースは、作るタグから届く最新の `v*` のタグで、プレリリースを含む（[`check-patch.sh`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/scripts/release/check-patch.sh#L40-L43)）。
patch かどうかは、二つのタグの `X.Y` が同じかどうかだけで決める（[`check-patch.sh`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/scripts/release/check-patch.sh#L54-L68)）。
そのため、minor か major のプレリリースから正式の版への移りが、patch として検査される。

作業用の Git のリポジトリで、`scripts/visual/pages/manual.txt` を一行だけ変えて二つのタグを打ち、`GOLEM_ROOT` を渡して `check-patch.sh` を動かした（2026-11-08）。

| 直前のリリース | 作るタグ | 今の結果 | あるべき結果 |
| --- | --- | --- | --- |
| `v1.0.0-rc1` | `v1.0.0` | 比べない（終了コード 0） | 比べない |
| `v1.1.0-rc1` | `v1.1.0` | patch として失敗（1） | 比べない（minor） |
| `v1.1.0-rc1` | `v1.1.0-rc2` | patch として失敗（1） | 比べない（minor のプレリリース） |
| `v2.0.0-rc1` | `v2.0.0` | patch として失敗（1） | 比べない（major） |
| `v1.0.0` | `v1.0.1` | patch として失敗（1） | patch として比べる |
| `v1.0.3` | `v1.1.0-rc1` | 比べない（0） | 比べない |

`v1.0.0-rc1` から `v1.0.0` だけが比べられないのは、`since_1` が 1.0.0 のプレリリースを 1.0.0 より前として扱うからである。
minor の rc を出した後に組版を直すと、正式の版のタグでリリースが止まる。
minor は組版の結果を変えてよいので（[docs/compatibility.md](../compatibility.md) の表）、これは約束より厳しい誤りである。

CI の [`abi-version.sh`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/scripts/ci/abi-version.sh#L119-L146) も、同じ `since_1` と `xy` で、HEAD の `VERSION` が直前のリリースの patch かどうかを決める。
`v1.1.0-rc1` の後の `VERSION` が `1.1.0` なら、ABI を変えない patch として扱う。
予告した ABI の変更を rc の後に入れると、`changes` ジョブが止まる。
原因は `check-patch.sh` と同じ、patch の判定である。

### patch でマニュアルを直すとリリースが止まる

`scripts/visual/pages/` には、二つのマニュアルの参照（`manual.txt` と `manual-dev.txt`）がある（[`build.sh`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/scripts/visual/build.sh#L28-L33)）。
マニュアルの原稿を直すプルリクエストは、参照も直す。
[docs/manual-policy.md](../manual-policy.md) は、マニュアルを ADR なしにプルリクエストで直すと決めているので、誤字の修正は patch の前にも入りうる。
すると、Golem の出力が変わっていなくても、`check-patch.sh` は参照の差を出力の変更と取り違えて失敗する。

同じことは、fixture の原稿（`modules/golem-driver/test/fixtures/` の本）を直したときにも起きる。
約束は「同じ入力からは同じ出力」であり、今の検査は入力の差と出力の差を区別できない。
二つのタグの参照を比べる方法では、入力が同じことを前提にするしかない。

### 今のテスト

[`scripts/release/test.sh`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/scripts/release/test.sh#L106-L180) は、`v1.0.0` の後の `v1.0.1`、`v1.1.0`、`v2.0.0`、`v1.0.1-rc1` と、`v1.0.0-rc1` の後の `v1.0.0` を調べる。
minor か major のプレリリースの後の正式の版と、入力を変えた patch は調べていない。

## 実装すること

### patch の判定

patch の判定を次のように改め、`check-patch.sh` と `abi-version.sh` の両方に同じ規則を書く（二つのスクリプトのあいだで関数を共有するファイルは作らず、同じ関数を写す。注釈でこの ADR を指す）。

- バージョン `X.Y.Z[-PRE]` は、`X` が 1 以上で `Z` が 1 以上のとき、そのときに限り patch である。プレリリースの部分は見ない（`v1.0.1-rc1` も patch）。
- 比べる相手（基準のリリース）は、作るタグ（`abi-version.sh` では HEAD）から届く `v*` のタグのうち、プレリリースでなく、`X.Y` が同じで、作るタグとは別のものの最新とする。`git describe --tags --abbrev=0 --match 'v[0-9]*' --exclude '*-*'` で選び、`X.Y` が違えば基準はない。
- patch でないか、基準がないときは、比べずに成功し、その理由を一行で標準出力に書く（今と同じ）。
- patch なのに基準がない（`v1.0.1` の前に `v1.0.0` のタグがない）ときは、比べられないことを標準エラーに書いて失敗する。今は、届くタグがなければ成功する（[`check-patch.sh`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/scripts/release/check-patch.sh#L40-L43)）が、patch を名乗るのに比べる相手がないのは、タグの誤りである。

### 出力の比べ方

参照どうしを比べる今の方法をやめ、作るタグの `golem` で基準のリリースの入力を組み直し、基準のリリースの参照と比べる（「メンテナーが決めること」の 2）。

- リリースのワークフローに、ジョブ `patch` を足す。`version` ジョブが patch と判定したときだけ走り、x86-64 の Linux の配布物（`build` ジョブの成果物）を待つ。
- ジョブは、基準のリリースのタグを `git worktree` で取り出し、その木の `scripts/visual/build.sh` を、`GOLEM` に作るタグの `golem` を渡して走らせ、その木の `scripts/visual/check.sh` で、その木の `scripts/visual/pages/` と比べる。描画の shem は、その木の `scripts/visual/fetch-shem.sh` で取る。
- 基準のリリースに `scripts/determinism/hashes.txt` があれば、その木の `scripts/determinism.sh` を同じく作るタグの `golem` で走らせ、PDF の行を除いて、その木の `hashes.txt` と比べる。
- どちらかが違えば失敗し、違ったページかハッシュの行を標準エラーに書く。`release` ジョブは `patch` ジョブを待つ。
- `check-patch.sh` は、基準のリリースのタグを一行で書く判定だけのスクリプトにし、`version` ジョブの出力 `patch-base` に渡す。参照どうしを比べる処理は消す。

入力は基準のリリースのものなので、マニュアルと fixture の原稿を patch の前に直しても、検査は変わらない。
検査が見るのは、作るタグの `golem` だけである。

### 文書

- [docs/compatibility.md](../compatibility.md) の「patch のリリース」と「ABI のバージョン」の段落を、新しい判定と比べ方に書き直す。
- [ADR 0174](0174-compatibility-promises-for-1-0.md) のステータスの行に、patch の検査の判定と比べ方はこの ADR が改めたと書く。
- README の CI のジョブの表に、リリースのワークフローの `patch` ジョブを足す。

## 実装しないこと

- **minor のリリースの検査**：minor は組版の結果を変えてよいので、出力を比べない。
- **ABI の CBOR の比べ**：`golem inspect --as cbor` のバイト列は、今のとおり `abi-version.sh` の ABI のバージョンで守る。patch の入力を組み直す検査には加えない。
- **1.0.0 より前の規則**：1.0.0 より前のタグは、今のとおり比べない。
- **マニュアルの方針の変更**：マニュアルを ADR なしに直す [docs/manual-policy.md](../manual-policy.md) の決定はそのままにする。この ADR は、その決定とリリースの検査が食い違わないようにするだけである。

## 不変条件

T を作るタグ（`abi-version.sh` では HEAD の `VERSION`）、B を基準のリリースとする。

- **P1**：T が patch であることと、T の `X` が 1 以上で `Z` が 1 以上であることは同値である。T のプレリリースの部分は判定に影響しない。
- **P2**：T が patch なら、B は T から届く、プレリリースでなく `X.Y` が T と同じで T と別の最新のタグである。そのようなタグがなければ、検査は失敗する。
- **P3**：T が patch でないとき、`check-patch.sh` と `patch` ジョブは何も比べずに成功し、`abi-version.sh` は minor の規則（予告の見出し）を当てる。
- **P4**：T が patch のとき、`patch` ジョブが成功することと、T の `golem` で B の入力を組んだ見た目の回帰テストのページのハッシュが B の参照と一致し、B に `hashes.txt` があれば PDF の行を除いて一致することは同値である。
- **P5**：`patch` ジョブの結果は、B と T のあいだで入力（マニュアル、fixture、参照）を変えたかどうかに依らない。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| T の形 | `v1.0.1`、`v1.0.1-rc1`、`v1.1.0`、`v1.1.0-rc2`、`v2.0.0`、`v0.1.0-rc4` |
| 届くタグ | 基準になる正式の版がある、プレリリースだけがある（`v1.0.1` の前が `v1.0.1-rc1` だけ）、何もない |
| B と T のあいだ | 何も変えない、マニュアルの原稿と参照を変える、組版を変える、PDF の Producer だけが変わる |
| `hashes.txt` | B にある、B にない |

## テスト設計

`scripts/release/test.sh` に、先に次のテストを足し、今のスクリプトで失敗することを確かめてから実装する。

- **P1、P3**：`v1.1.0-rc1` の後の `v1.1.0` と `v1.1.0-rc2`、`v2.0.0-rc1` の後の `v2.0.0` で、参照を変えても成功する（今は失敗する）。
- **P2**：`v1.0.0` と `v1.0.1-rc1` の後の `v1.0.1` は、基準が `v1.0.0` になる。`v1.0.0` を消して `v1.0.1-rc1` だけを残すと失敗する（今は `v1.0.1-rc1` と比べる）。
- **P4**：偽の `golem`（受け取った入力のハッシュを PDF として書くもの）と、偽の `build.sh` と `check.sh` を置いた B の木で、出力が同じなら成功し、偽の `golem` に一ページだけ変えさせると、そのページを名指して失敗する。
- **P5**：B と T のあいだでマニュアルの原稿と `manual.txt` の参照を変え、偽の `golem` の出力は変えないと、成功する（今は失敗する）。

`scripts/ci/test.sh` の `abi-version.sh` のテストに、`v1.1.0-rc1` の後の `VERSION` が `1.1.0` で、予告した ABI の変更があるときに成功するテストを足す（今は patch として失敗する）。

ワークフローの `patch` ジョブは自動のテストにできない。
実装のプルリクエストで、`workflow_dispatch` か作業用のタグで一度動かし、所要時間を `docs/ci-timings/` に記録する。

## トレードオフ

組み直す方法は、参照を比べる方法より、リリースの時間が延びる。
見た目の回帰テストの PDF を組むのと描くのとで、今の CI の `visual` ジョブと同じく数分かかる（2026-11-08 の main の `visual` は 126 秒）。
リリースはまれなので、この延びは受け入れられる。

B の木のスクリプトを T の `golem` で走らせるので、CLI の互換（[docs/compatibility.md](../compatibility.md) の表の CLI の行）にも頼る。
patch は CLI を壊さないので、この依存は約束の中にある。
B のスクリプトが、T にない環境（たとえば、消した外部のコマンド）を要るときは、ジョブが失敗して分かる。

基準をプレリリースでない最新の版にすると、`v1.0.1-rc1` と `v1.0.1` は、どちらも `v1.0.0` と比べる。
rc と正式の版のあいだの差は比べないが、どちらも `v1.0.0` と同じなら互いに同じなので、失うものはない。

## メンテナーが決めること

1. **patch の判定**：推奨は、`Z` が 1 以上のときに限り patch とし、基準をプレリリースでない同じ `X.Y` の最新のタグとすることである。minor と major のプレリリースから正式の版への移りを、patch と取り違えない。
   - 退けた案の一つは、今の規則（届く最新のタグと `X.Y` が同じなら patch）に、「直前のリリースがプレリリースなら比べない」を足すことである。`v1.0.1-rc1` の後の `v1.0.1` を比べなくなり、patch の rc の後に組版を変えても通る。
   - 二つめは、プレリリースのタグを判定から外すだけにすることである。`v1.1.0` の基準が `v1.0.3` になり、`X.Y` が違うので比べないという結果は正しいが、`v1.0.1` の前に `v1.0.0` のタグがないときに黙って成功する。
2. **出力の比べ方**：推奨は、T の `golem` で B の入力を組み直し、B の参照と比べることである。約束の「同じ入力」をそのまま確かめるので、マニュアルと fixture の修正を patch に入れられる。
   - 退けた案の一つは、今の参照どうしの比べを残し、入力（マニュアルや fixture の木）が変わったページを比べから外し、外したページを標準出力に書くことである。ページと入力の対応を `build.sh` のほかにもう一つ持つことになり、組版を変えたうえでマニュアルも直した patch では、マニュアルのページが検査を抜ける。
   - 二つめは、patch ではマニュアルと fixture を変えないと決めることである。[docs/manual-policy.md](../manual-policy.md) の、マニュアルをプルリクエストで直す決定と食い違い、誤字の修正が minor まで待つ。
   - 三つめは、マニュアルの参照だけを比べから外すことである。fixture の原稿の修正で同じことが起き、原因の一部しか直さない。
3. **`abi-version.sh` を同じ ADR で直すか**：推奨は、直すことである。原因は同じ patch の判定であり、二つのスクリプトで判定が違うと、`changes` ジョブとリリースが別の規則で止まる。
   - 退けた案は、`check-patch.sh` だけを直し、`abi-version.sh` は別の ADR にすることである。同じ原因を二つの ADR に分けることになる。
4. **基準のない patch**：推奨は、失敗とすることである。patch を名乗るタグに比べる相手がないのは、タグの打ち方の誤りで、黙って通せば約束を確かめないまま出す。
   - 退けた案は、今のとおり成功とすることである。厳しい側を選ぶ原則に反する。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-08、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [ADR 0174](0174-compatibility-promises-for-1-0.md)、[ADR 0173](0173-rc4-refactoring.md)、[ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md)
- [docs/compatibility.md](../compatibility.md)、[docs/manual-policy.md](../manual-policy.md)
- Semantic Versioning 2.0.0, https://semver.org/（プレリリースの順序の 11）
- Fable による ADR のレビュー（2026-11-08、origin/main `6e5f852f`）の「設計の判断が要る逸脱」の 0174
