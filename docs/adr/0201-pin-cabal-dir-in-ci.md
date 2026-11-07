# ADR 0201: CI の cabal に `CABAL_DIR` を与え、`~/.cabal` の配置に固定する

ステータス: 採択（未実装）

## 文脈

2026-11-07 に、`ci.yml` の `build` ジョブが、ときどき cabal の依存の解決で失敗するようになった。
失敗したジョブは、同じ実行のほかのランナーと同じイメージ、同じキャッシュ、同じ cabal で動いており、ログにだけ違いがある。
このプロジェクトは、ときどき落ちるテストやジョブを再実行で済ませず、原因を調べて直すと決めている。
落ちたジョブを再実行すれば今回の実行は緑になるが、同じ確率で次の実行が落ち、そのたびに人が原因を見直すことになる。

### 失敗したジョブ

2026-11-07 の三つのジョブが、同じ形で失敗した。

| 実行 | ブランチ | ジョブ | ランナー |
|---|---|---|---|
| [42341110073](https://github.com/tett23/golem/actions/runs/42341110073/job/128308802479) | impl-0182 | `build (ubuntu-24.04, tests-rest)` | x86-64 |
| [42342959506](https://github.com/tett23/golem/actions/runs/42342959506/job/128314543327) | impl-0183 | `build (ubuntu-24.04, tests-driver)` | x86-64 |
| [42346732450](https://github.com/tett23/golem/actions/runs/42346732450/job/128326054560) | impl-0192-typeset（PR #612） | `build (ubuntu-24.04-arm, tests-driver)` | aarch64 |

どのジョブでも、`cabal build all peg-cli:exe:peg-hs` の手順の最初の出力は次のとおりである（42346732450 のもの）。

```
Warning: Both /home/runner/.cabal and /home/runner/.config/cabal/config exist
- ignoring the former.
It is advisable to remove one of them. In that case, we will use the remaining
one by default (unless '$CABAL_DIR' is explicitly set).
Warning: The package list for 'hackage.haskell.org' does not exist. Run 'cabal
update' to download it.
Warning: There is no index-state for 'hackage.haskell.org' exactly at the
requested timestamp (2026-10-11T15:10:52Z). Also, there are no index-states
before the one requested, so the repository 'hackage.haskell.org' will be
empty.
Resolving dependencies...
Error: [Cabal-7107]
Could not resolve dependencies:
[__0] trying: golem-bibliography-0.1.0 (user goal)
[__1] unknown package: vector (dependency of golem-bibliography)
```

その前の「Cache the Hackage index」の手順は、`hackage-index-no-gz-608d9616…` のキーで当たり、`~/.cabal/packages/hackage.haskell.org` に索引を戻している。
索引は戻っているのに、cabal は索引がないと言っている。

同じ実行の、通ったジョブと比べた。
42346732450 の `build (ubuntu-24.04-arm, tests-rest)` と、42342959506 の `build (ubuntu-24.04, tests-rest)` である。
ランナーのイメージのバージョン（x86-64 は 20261101.360.1、aarch64 は 20261101.172.1）、ghcup（0.2.6.2）、cabal-install（3.16.1.0）、GHC、Hackage の索引、cabal の store のキャッシュのキーは、どれも失敗したジョブと同じだった。
通ったジョブの `cabal build` は、一行めの警告を出さず、「Resolving dependencies...」から計画に進んでいる。
ログに出ている違いは、この警告、つまり `~/.config/cabal/config` があるかどうかだけである。

### どれほど起きているか

`ci.yml` の新しい 200 の実行（2026-11-04 の 23:28 から 2026-11-07 の 06:22 まで）のうち、失敗した 52 の実行の失敗したジョブのログ（`gh run view --log-failed`）を取り、一行めの警告を数えた。
警告があったのは上の三つのジョブだけで、どれも 2026-11-07 のものだった。
2026-11-07 の 116 の実行では、`build` の行列のジョブが 701 回、成功か失敗で終わっており、そのうちの三回である。
通ったジョブは警告を出していないと見てよい。
後で述べるとおり、警告が出た `build` のジョブは、索引のキャッシュが当たれば依存の解決で、外れれば `cabal update` の後の `ls` で、必ず落ちるからである。
調べた範囲で 2026-11-07 より前に起きていない理由は、分かっていない。

### cabal が使うディレクトリの決め方

cabal-install は、設定ファイル、Hackage の索引（remote-repo-cache）、store などのディレクトリを、次の順で決める（cabal 3.16 の文書の「Configuration file discovery」と「Directories」、cabal-install 3.16.1.0 の `maybeGetCabalDir`）。

1. 環境変数 `CABAL_DIR` があれば、すべてをその下に置く。
2. なければ、`~/.cabal` がディレクトリとしてあり、かつ `~/.config/cabal/config` がないときに限り、`CABAL_DIR=~/.cabal` と同じに振る舞う。
3. それ以外は、XDG Base Directory の配置を使う。設定は `~/.config/cabal/config`、索引は `~/.cache/cabal/packages`、store は `~/.local/state/cabal/store` である。

`~/.cabal` と `~/.config/cabal/config` の両方があると、3 に当たり、`~/.cabal` は読まれない。
一行めの警告は、この場合に `loadConfig` が出すものである。
CI は索引を `~/.cabal/packages/hackage.haskell.org` に戻しているので（[ci.yml#L254-L266](https://github.com/tett23/golem/blob/804e7fa509d9808f60b0551bd553e8dda6d26b7e/.github/workflows/ci.yml#L254-L266)）、XDG の配置の cabal は空の `~/.cache/cabal/packages` を見て、パッケージが一つもないと判断する。

cabal の store は、この失敗に巻き込まれていない。
`haskell-actions/setup` が、見つけた設定ファイルの末尾に `store-dir` として `$HOME/.cabal/store` の絶対パスを書き足すからである（後述）。
失敗したジョブでも、store のキャッシュの `path` は `/home/runner/.cabal/store` で、キーで当たっている。

手元の cabal-install 3.18.1.0（macOS）で、一時的な `HOME` を使って `cabal path --config-file --remote-repo-cache --store-dir` を確かめた。

| `HOME` の中身 | `CABAL_DIR` | 設定ファイル | 索引 |
|---|---|---|---|
| `~/.cabal/` だけ | なし | `~/.cabal/config` | `~/.cabal/packages` |
| `~/.cabal/` と `~/.config/cabal/config` | なし | `~/.config/cabal/config`（警告あり） | `~/.cache/cabal/packages` |
| `~/.cabal/` と `~/.config/cabal/config` | `$HOME/.cabal` | `~/.cabal/config`（警告なし） | `~/.cabal/packages` |
| 空 | `$HOME/.cabal` | `cabal user-config init` が `~/.cabal/config` を書く | |
| 空 | なし | `cabal user-config init` が `~/.config/cabal/config` を書く | |

CI の cabal-install 3.16.1.0 では動かしていない。
3.16.1.0 の `maybeGetCabalDir` は、上の 1 から 3 と同じ判定である。

### `~/.config/cabal/config` を作るもの

ランナーのイメージは同じなので、`~/.config/cabal/config` はジョブの中で作られたと見られる。
索引のキャッシュが当たったジョブで、`cabal build` より前に cabal を呼ぶのは `haskell-actions/setup` だけである。

`haskell-actions/setup@v2`（v2.12.1、コミット 0f8e8c9）の「Setting up cabal」は、次の順に動く。

1. `~/.cabal/bin` を `io.mkdirP` で作る。cabal を XDG の配置にさせないための回避策である（upstream の issue haskell/actions#210）。
2. `cabal user-config init` を実行する。設定ファイルがなければ作る。
3. `cabal --help` の最後の行から設定ファイルのパスを読み、その末尾に `store-dir: $HOME/.cabal/store`（展開した絶対パス）を書き足し、同じパスを出力 `cabal-store` にする。
4. `~/.cabal/bin` を `PATH` に足す。

1 の `io.mkdirP` は Promise を返すが、`await` されていない（`src/setup-haskell.ts` の 84 行め、`dist/index.js` の 35744 行め）。
ディレクトリを作り終える前に 2 の cabal が `~/.cabal` を調べれば、cabal は XDG の配置を選び、`~/.config/cabal/config` を書く。
その後で `~/.cabal/bin` ができ、キャッシュの復元が `~/.cabal/packages` と `~/.cabal/store` を置くので、`cabal build` の時点で両方がそろう。
ソースから読んだこの順序の競合で、ときどきだけ起きることと、x86-64 と aarch64 の両方で起きることを説明できる。
ただし、`cabal user-config init` は出力を出さずに実行されるので、ログからこの競合を直接は確かめていない。

同じ症状は、upstream に issue として報告されている（haskell-actions/setup#108、2025-01-05 から未解決）。
報告者の CI でも、警告が出たときだけ「unknown package」で落ちている。

### ワークフローが `~/.cabal` を前提にしている箇所

- `ci.yml` の `build`：`haskell-actions/setup` を `cabal-update: false` で呼び（[ci.yml#L227-L232](https://github.com/tett23/golem/blob/804e7fa509d9808f60b0551bd553e8dda6d26b7e/.github/workflows/ci.yml#L227-L232)）、索引を `~/.cabal/packages/hackage.haskell.org` にキャッシュし、外れたときは `cabal update` の後に同じディレクトリの `01-index.tar.gz` を消す（[ci.yml#L254-L266](https://github.com/tett23/golem/blob/804e7fa509d9808f60b0551bd553e8dda6d26b7e/.github/workflows/ci.yml#L254-L266)、[ADR 0141](0141-smaller-ghc-and-hackage-index-caches.md)、[ADR 0152](0152-remove-hackage-index-tar-gz-before-cache.md)）。store は `steps.setup.outputs.cabal-store` を使う（[ci.yml#L267-L272](https://github.com/tett23/golem/blob/804e7fa509d9808f60b0551bd553e8dda6d26b7e/.github/workflows/ci.yml#L267-L272)）。
- `race.yml` の `race`：同じく `cabal-update: false` で呼び、索引を `~/.cabal/packages/hackage.haskell.org` に戻す（[race.yml#L57-L80](https://github.com/tett23/golem/blob/804e7fa509d9808f60b0551bd553e8dda6d26b7e/.github/workflows/race.yml#L57-L80)）。
- `release.yml` の `build` の macOS：`haskell-actions/setup` を既定の `cabal-update: true` で呼び、キャッシュを使わない（[release.yml#L106-L111](https://github.com/tett23/golem/blob/804e7fa509d9808f60b0551bd553e8dda6d26b7e/.github/workflows/release.yml#L106-L111)）。`cabal update` もビルドも同じ設定を読むので、配置がどちらになっても動く。
- `scripts/release/licenses.sh`：索引の場所を `cabal path --remote-repo-cache` で尋ね、答えがなければ `~/.cabal/packages` と XDG の配置の順に探す（[licenses.sh#L72-L81](https://github.com/tett23/golem/blob/804e7fa509d9808f60b0551bd553e8dda6d26b7e/scripts/release/licenses.sh#L72-L81)）。

CI のキャッシュの ADR（[ADR 0009](0009-ci-speed.md)、[ADR 0141](0141-smaller-ghc-and-hackage-index-caches.md)、[ADR 0152](0152-remove-hackage-index-tar-gz-before-cache.md)）は、cabal が `~/.cabal` を使うことを前提にしている。
`cabal-update: false` にしたのは、[ADR 0009](0009-ci-speed.md) を実装した 2026-10-13 のコミット 6bc251c7「Speed up CI」である。
それより前は `haskell-actions/setup` の中で `cabal update` が走り、配置がどちらでも索引はその配置に入っていた。

## 実装すること

`haskell-actions/setup` を呼ぶすべてのジョブで、cabal が使うディレクトリを `$HOME/.cabal` に固定する。

### `CABAL_DIR` を与える手順

`ci.yml` の `build`、`race.yml` の `race`、`release.yml` の `build` の三つのジョブで、`haskell-actions/setup` より前に、次の手順を置く。

```yaml
      # cabal reads and writes everything under ~/.cabal, whatever the
      # image and haskell-actions/setup leave in ~/.config/cabal
      # (docs/adr/0201)
      - name: cabal's directory (docs/adr/0201)
        run: echo "CABAL_DIR=$HOME/.cabal" >> "$GITHUB_ENV"
```

`race.yml` と `release.yml` では、同じジョブの `haskell-actions/setup` の手順と同じ `if:` を付ける。
`$GITHUB_ENV` に書くのは、ワークフローの `env:` では `$HOME` を展開できず、cabal も `CABAL_DIR` の `~` を展開しないからである。
`/home/runner/.cabal` と書けば、`HOME` が `/Users/runner` の macOS のランナーでは、ないディレクトリを指す。

`haskell-actions/setup` は `$GITHUB_ENV` の値を環境として受け取る。
`cabal user-config init` は `$CABAL_DIR/config` を書き、`cabal --help` の最後の行も `$CABAL_DIR/config` を指すので、`store-dir` の書き足しも同じファイルに入る（手元の 3.18.1.0 で確かめた。上の表の四行め）。

### cabal のディレクトリを確かめる手順

同じ三つのジョブで、`haskell-actions/setup` の直後（`ci.yml` と `race.yml` では索引のキャッシュより前）に、cabal が実際に使うディレクトリを確かめる手順を置く。

```yaml
      - name: cabal uses ~/.cabal (docs/adr/0201)
        run: |
          test "$(cabal path -z --config-file)" = "$HOME/.cabal/config"
          test "$(cabal path -z --remote-repo-cache)" = "$HOME/.cabal/packages"
          test "$(cabal path -z --store-dir)" = "$HOME/.cabal/store"
```

`cabal path` は、キーを一つだけ尋ねると値だけを出す（cabal-install 3.16.1.0 の `showAsKeyValuePair`）。
`-z`（`--ignore-project`）を付けるのは、プロジェクトの文脈で `cabal path` を実行すると、cabal が `cabal.project` の `source-repository-package` を `dist-newstyle/src` に取得するからである。
手元の 3.18.1.0 で、`-z` なしの `cabal path` が peg-hs を clone しようとすることを確かめた。
この手順は `dist-newstyle` の復元より前にあるので、ここで取得させるわけにはいかない。
`cabal.project` は `store-dir` などのディレクトリを指定していないので、`-z` でも `cabal build` と同じディレクトリが返る。
cabal の配置が変われば、`cabal build` の依存の解決ではなく、この手順が何が違うのかを名指しして落ちる。

### 変えないもの

キャッシュの `path` は `~/.cabal/packages/hackage.haskell.org` のまま変えない。
actions/cache のキャッシュのバージョンは `path` の文字列から作られるので、`${{ env.CABAL_DIR }}/packages/…` に書き換えると、すべてのキャッシュが一度外れる。
`path` と cabal の実際のディレクトリが一致することは、上の確かめる手順が保証する。

### 文書

開発者のマニュアルの第 2 部「CI のジョブ」（`manual-dev/part2/11-ci-jobs.gm`）の `build` の手順の一覧に、cabal が `~/.cabal` を使うよう `CABAL_DIR` を与え、それを確かめることを足す。
`docs/specifications.md` と README は CI のキャッシュの配置を書いていないので、変えない。

## 実装しないこと

### キャッシュを XDG の配置へ移すこと

キャッシュの `path` を `~/.cache/cabal/packages` などに移しても、直らない。
配置を決めるのは、`haskell-actions/setup` の中の競合のままだからである。
競合に勝てば `~/.cabal` の配置になり、XDG に移したキャッシュは読まれない。
XDG の配置に固定するには `~/.cabal` があってはならないが、`haskell-actions/setup` は必ず `~/.cabal/bin` を作る。

### `~/.config/cabal/config` を消すこと

`haskell-actions/setup` の後に `rm -f ~/.config/cabal/config` を置けば、cabal は `~/.cabal` の配置に戻る。
しかし、そのファイルには `haskell-actions/setup` が書き足した `store-dir` が入っており、消すと次の cabal が既定の設定を新しく書く。
既定の store は `~/.cabal/store` なので今は結果が同じだが、`haskell-actions/setup` が書き足す中身が変わったときに黙って失われる。
cabal が知っている指定（`CABAL_DIR`）で決めるほうが、ファイルを消して判定の条件を作るより単純である。

### `haskell-actions/setup` を直す、または固定すること

upstream の `await` の欠けを直すのは、このリポジトリの仕事ではない。
直ったとしても、cabal の配置はランナーのイメージにある `~/.config/cabal` に左右され続ける。
`CABAL_DIR` があれば、upstream が直しても直さなくても同じに動く。
フォークや別のアクションへの乗り換えもしない。

### release.yml の Linux のビルド

Linux のアーカイブは Alpine のコンテナの中で `scripts/release/build-linux.sh` がビルドする。
コンテナは自分の `HOME` を持ち、キャッシュを使わず、`cabal update` もビルドも同じ設定を読むので、この ADR の失敗は起きない。
コンテナの中の cabal には `CABAL_DIR` を与えない。

### race.yml のキャッシュのキー

`race.yml` は GHC を `…-${{ env.ImageOS }}` の、索引を `hackage-index-…` のキーで戻すが、`ci.yml` が保存するのは `…-slim` と `hackage-index-no-gz-…` である（[ADR 0141](0141-smaller-ghc-and-hackage-index-caches.md) で変わった）。
2026-11-07 のキャッシュの一覧（`gh cache list`）には、`race.yml` のキーのキャッシュがない。
`race.yml` の復元は外れ、`cabal update` が走るので、今は配置の違いで落ちない。
キーのずれは別の問題なので、この ADR では直さない。

### 再実行

落ちたジョブを再実行して済ませることはしない（文脈を参照）。

## テスト設計

### scripts/ci/test.sh

先に書き、今のワークフローで失敗することを確かめる。

- `ci.yml`、`race.yml`、`release.yml` のそれぞれで、`uses: haskell-actions/setup@v2` の手順の数と、`echo "CABAL_DIR=$HOME/.cabal" >> "$GITHUB_ENV"` を実行する手順の数が等しいこと。
- 各ジョブで、`CABAL_DIR` を与える手順が `haskell-actions/setup` より前にあること。
- 各ジョブで、`haskell-actions/setup` の後に、`cabal path -z --config-file`、`cabal path -z --remote-repo-cache`、`cabal path -z --store-dir` を `$HOME/.cabal` の下と比べる手順があること。
- `ci.yml` の `build` と `race.yml` の `race` で、確かめる手順が索引のキャッシュの手順より前にあること。
- `race.yml` と `release.yml` で、二つの手順の `if:` が、同じジョブの `haskell-actions/setup` の `if:` と同じであること。

`job_of` と `step_has` など、`test.sh` にある補助の関数を使う。

### CI での確かめ

この ADR の失敗は、確率が低く（2026-11-07 の 701 回のジョブで三回）、狙って起こせない。
そのため、競合が起きたかどうかではなく、cabal が使うディレクトリそのものを各ジョブで確かめる（実装することの「cabal のディレクトリを確かめる手順」）。
実装のプルリクエストでは、次を確かめる。

1. `ci.yml` の `build` の行列のすべてのジョブで、確かめる手順が通ること。
2. どのジョブの `cabal build` のログにも「ignoring the former」がないこと（`gh run view <id> --log` で数える）。
3. `race.yml` を workflow_dispatch で、`release.yml` を workflow_dispatch（アーカイブのビルドと検査だけで、リリースを作らない）で一度ずつ動かし、確かめる手順が通ること。

### 手元での確かめ

文脈の表の五つの場合を、一時的な `HOME` で `cabal path` と `cabal user-config init` を実行して確かめた（cabal-install 3.18.1.0、macOS）。
CI の 3.16.1.0 での振る舞いは、上の 1 と 3 で確かめる。

## トレードオフ

- `CABAL_DIR` があると、cabal は XDG の配置を読まない。ランナーのイメージが将来 `~/.config/cabal/config` に設定を置いても、CI の cabal はそれを読まない。CI はイメージの cabal の設定に頼っていないので、失うものはない。
- 三つのジョブに二つずつ手順が増える。確かめる手順は `cabal path -z` を三回実行する。手元では三回で 0.13 秒だった。CI では計っていない。
- `haskell-actions/setup` が `cabal --help` の最後の行から設定ファイルを読む作り（upstream が brittle と書いている）には、引き続き頼る。`CABAL_DIR` があれば、その行は `$CABAL_DIR/config` を指す。
- upstream の競合が直っても、この手順は残る。そのときは無害な重複になる。

## メンテナーが決めること

### 1. 直し方（推奨：`CABAL_DIR=$HOME/.cabal`）

- **`CABAL_DIR=$HOME/.cabal` を与える（推奨）**：cabal がディレクトリを決めるときに最初に見る指定で、`~/.cabal` と `~/.config/cabal/config` のどちらがあっても配置が一つに決まる。キャッシュの `path` も、[ADR 0141](0141-smaller-ghc-and-hackage-index-caches.md) と [ADR 0152](0152-remove-hackage-index-tar-gz-before-cache.md) の手順も変えずに済む。
- **キャッシュを XDG の配置へ移す**：配置を決めるのが競合のままなので直らない（実装しないことを参照）。採らない。
- **`~/.config/cabal/config` を消す**：今は動くが、`haskell-actions/setup` が書き足した設定を黙って捨て、判定の条件をファイルの有無で作ることになる。採らない。
- **再実行で済ませる**：プロジェクトの方針に反する。採らない。

### 2. `CABAL_DIR` の与え方（推奨：`$GITHUB_ENV` に書く手順）

- **`$GITHUB_ENV` に書く手順（推奨）**：`$HOME` をランナーごとに展開でき、macOS のランナーでも同じ一行で済む。
- **ワークフローの `env:` に `/home/runner/.cabal` と書く**：一行で済むが、macOS のランナー（`release.yml`）では `HOME` の外を指し、ランナーの `HOME` が変われば、確かめる手順がなければ気づけない。採らない。
- **`ci.yml` の既存の「Image and GHC directory for the cache keys」の手順に一行足す**：手順は増えないが、その手順の名前と役目（キャッシュのキー）に合わず、`release.yml` にはその手順がない。採らない。

### 3. 確かめる手順を置くジョブ（推奨：三つのジョブすべて）

- **三つのジョブすべて（推奨）**：「`haskell-actions/setup` を呼ぶジョブには、前に `CABAL_DIR` の手順、後に確かめる手順」という一つの規則で `test.sh` が検査できる。
- **キャッシュを使う `ci.yml` と `race.yml` だけ**：`release.yml` の macOS は配置がどちらでも動くので、確かめなくても落ちない。規則に例外が一つ増える。

### 4. upstream への報告（推奨：しない）

haskell-actions/setup#108 に、`await` の欠けを原因として書き込むこともできる。
しかし、競合はソースから読んだもので、実機で確かめていない。
確かめていないことを upstream に書くと、upstream のメンテナーの手間を増やすだけになる。
報告するなら、競合を再現する手順を実機で確かめてからにする。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-07、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- cabal 3.16 の文書「4.1.2. Environment variables」「4.1.2.1. Configuration file discovery」「4.1.3. Directories」：https://cabal.readthedocs.io/en/3.16/config.html#environment-variables
- cabal 3.16 の文書「cabal path」：https://cabal.readthedocs.io/en/3.16/cabal-commands.html#cabal-path
- cabal-install 3.16.1.0 の `warnOnTwoConfigs` と `maybeGetCabalDir`：https://github.com/haskell/cabal/blob/8d1f5a33662be0db0654061fb53fb00e3f4417e0/cabal-install/src/Distribution/Client/Config.hs#L748-L787
- cabal-install 3.16.1.0 の `cabal path`：https://github.com/haskell/cabal/blob/8d1f5a33662be0db0654061fb53fb00e3f4417e0/cabal-install/src/Distribution/Client/CmdPath.hs#L226-L297
- haskell-actions/setup v2.12.1 の「Setting up cabal」：https://github.com/haskell-actions/setup/blob/0f8e8c99d88aeb3fbfd523f1ef2c6f762d10d64d/src/setup-haskell.ts#L78-L128
- haskell-actions/setup#108（`~/.cabal` と `~/.config/cabal/config` が両方ある CI がときどき落ちるという報告）：https://github.com/haskell-actions/setup/issues/108
- haskell/actions#210（`~/.cabal/bin` を作る回避策の元の issue）：https://github.com/haskell/actions/issues/210
