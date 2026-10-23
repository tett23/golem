# ADR 0077: スクリプトのテストで、検査の対象が壊れても通る断言を直す

ステータス: 採択

## 文脈

scripts の下の四本のテスト（[scripts/ci/test.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/test.sh)、[scripts/manual/test.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/manual/test.sh)、[scripts/release/test.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/release/test.sh)、[scripts/env-determinism/test.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/env-determinism/test.sh)）は、CI の `changes` と `release-scripts` のジョブで走る。
2026-10-23 のテストの品質の点検と、その確認で、次の断言が、検査の対象のスクリプトが壊れても通ることを確かめた。

- [scripts/ci/test.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/test.sh#L665-L666) の「gate: a job missing from the names is found」は、テストが自分で作った「ci.yml のジョブから format を除いた一覧」と、`gate.sh --names` の出力が違うことを確かめる。`gate.sh` が format を名前に持つ限り必ず通り、`gate.sh` の振る舞いを何も確かめていない。名前の一致そのものは、[直前の断言](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/test.sh#L663-L664) が確かめている。
- [scripts/release/test.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/release/test.sh#L377) は `cmp -s written notes || grep -q '## Unsorted' written` である。`## Unsorted` の見出しさえあれば、ノートの中身が何でも通る。
- [scripts/ci/test.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/test.sh#L361-L372) の suite-timeout.sh の四つの断言は、`timeout` のない環境では黙って飛ばされる。飛ばしたことも、その数も表示しない。macOS の手元では `timeout` がないので、実際に飛ばされる。
- [scripts/ci/test.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/test.sh) の git の fixture（[changed-paths.sh の fixture](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/test.sh#L95-L106)、[`abi_repo`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/test.sh#L135-L144)、[`abi_change`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/test.sh#L150)、[188 行め](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/test.sh#L188)、[199 行め](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/test.sh#L199)、[203 行め](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/test.sh#L203)）は、`commit.gpgsign` と `tag.gpgsign` を切らない。署名が有効な環境ではコミットが失敗し、その失敗は `>/dev/null 2>&1` で捨てられる。fixture が作れていないまま、後の断言が別の理由で通ったり落ちたりする。[scripts/manual/test.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/manual/test.sh#L58-L59) は切っている。
- [scripts/release/test.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/release/test.sh#L426) は、[build-linux.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/release/build-linux.sh) が何もシェルに流し込まないことを `grep -Eq '\| *(ba)?sh'` で確かめる。`| /bin/sh`、`| dash`、`sh -c "$(curl ...)"` はすり抜ける。

点検が挙げた残りの二つは、穴ではなかった。

- 「the repository」のケース（[scripts/ci/test.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/test.sh#L210-L211) など）は実際のリポジトリを入力にするが、これは検査をリポジトリに対して走らせる本来の用途であり、fixture の代わりではない。各スクリプトの振る舞いは、別の fixture のケースが確かめている。
- [scripts/manual/fetch-fonts.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/manual/fetch-fonts.sh) のテスト（[scripts/manual/test.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/manual/test.sh#L333-L345)）は SHA-256 の不一致の側だけだが、正常の側は CI の `build` ジョブがマニュアルを組むときに毎回通る（[scripts/determinism.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/determinism.sh) から [scripts/manual/build.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/manual/build.sh)）。常に失敗する実装は、そこで落ちる。

## 実装すること

- [gate.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/gate.sh)：[この断言](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/test.sh#L665-L666) を削る。代わりに、`NAMES` から一つの名前を除いた gate.sh の写しを一時ディレクトリに作り、[名前の一致の断言](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/test.sh#L663-L664) と同じ比較がその写しで落ちることを確かめる。比較が欠けた名前を見つけられることを、gate.sh の写しで示す。
- write-notes.sh：偽の claude が返すノートと、check が失敗したときに書く一覧（notes.md）を区別できる入力にし、`cmp -s written notes` だけで断言する。`|| grep` の逃げ道を削る。どちらになるべきかがテストの入力で一つに決まらないなら、入力を二つに分けて、それぞれの結果を断言する。
- suite-timeout：`timeout` がないときは、飛ばした断言の数を `SKIP 4 suite-timeout (no timeout command)` の形で標準エラー出力に書く。test.sh の最後の要約にも、飛ばした数を書く。
- git の fixture：[scripts/ci/test.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/test.sh) の fixture のリポジトリを作る関数を一つにし、`commit.gpgsign false`、`tag.gpgsign false`、`user.email`、`user.name` を設定する。fixture を作るコマンドの失敗は捨てずに、テストを止める。
- build-linux.sh：流し込みの検査を、パイプの右側の最初の語がシェル（`sh`、`bash`、`dash`、`ash`、`zsh`、それらの絶対パス）であるか、`sh -c` か `bash -c` に `$(` が続くかで判定する。検査の関数を [scripts/release/test.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/release/test.sh) に置き、fixture の文字列でこれらの形を拒み、`curl ... -o FILE` と `sha256sum -c` の組を通すことを確かめる。

## 実装しないこと

- 四本のテストを別のテストの枠組み（bats など）に書き換えること。
- the repository のケースと fetch-fonts.sh のテスト（上の理由による）。

## テスト設計

それぞれ、先に断言を変え、次の変異で落ちることを確かめる。
今の断言はどれもこの変異で落ちない。

- gate.sh：gate.sh の `NAMES` から format を除く変異で、[名前の一致の断言](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/test.sh#L663-L664) が落ちる（これは今も落ちる）。新しい写しのケースは、比較を常に成功にするテストの変異で落ちる。
- write-notes.sh：write-notes.sh が check の失敗のときに `## Unsorted` だけの空のノートを書く変異。
- suite-timeout：`PATH` から `timeout` を除いて test.sh を走らせ、`SKIP 4` の行が出ることを確かめる。今は何も出ないので落ちる。
- git の fixture：`git config --global commit.gpgsign true` と偽の `gpg`（常に失敗する）を `HOME` と `PATH` で差し込んで test.sh を走らせ、fixture のコミットが成功することを確かめる。今は fixture が黙って壊れる。
- build-linux.sh：`curl ... | /bin/sh` を含む fixture の文字列を、新しい検査の関数が拒む。

## トレードオフ

- fixture の失敗でテストを止めるので、環境の問題（git がない、など）で test.sh が早く止まる。何が原因かは止まったときのメッセージで分かるようにする。

## 参考文献

- [ADR 0021](0021-docs-workflow-and-ci-gate.md)
- [ADR 0004](0004-binary-distribution-and-release.md)
