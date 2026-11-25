# ADR 0452: パッケージのファイルの一覧を CI の `cabal sdist all` で確かめる

Status: proposed

## 文脈

README の「CLI のビルド」のコマンド `cabal install exe:golem --installdir="$HOME/.local/bin" --install-method=copy --overwrite-policy=always` は、`main` のきれいなチェックアウトで失敗する。
cabal は `Error: [Cabal-6661] filepath wildcard 'test/data/hyphenation/*.log' does not match any files.` を出して止まる。

原因は、golem-layout の `extra-source-files` の `test/data/hyphenation/*.log`（[golem-layout.cabal の 17 行目](https://github.com/tett23/golem/blob/3d8d5a9caf94abafc7b58980bc6aa656e4a2084b/modules/golem-layout/golem-layout.cabal#L17)）が、リポジトリのどのファイルにも当たらないことである。
このワイルドカードは、[root ADR 0276](0276-hyphenate-words-by-the-patterns-of-their-language.md) の実装のコミット `cee516e74` が加えた。
ディレクトリの README.md は、TeX のログ `showhyphens.log` をこのディレクトリのファイルの一つに挙げている。
しかし、そのコミットはログをコミットしなかった。
作者の環境の git の全体の除外の設定が `*.log` を無視するので、`git add` がログを飛ばしたためである。

CI はこの食い違いを見つけなかった。
cabal は `extra-source-files` などのワイルドカードを、パッケージのソースの tarball を作るとき（`cabal sdist`、`cabal install` の中の同じ手順）にだけ展開し、`cabal build` と `cabal test` では展開しない。
CI のワークフローには `cabal sdist` も `cabal install` も無い。
そのため、当たらないワイルドカードは、README の手順でインストールする人が初めて踏む。

この ADR は、ログを戻して今の失敗を直し、同じ食い違いが CI を落とすようにする。

## 調査した事項

次は、2026-11-26 に macOS（cabal-install 3.18.2.0）で確かめた。
`main` は `3d8d5a9ca` である。

- `git ls-files modules/golem-layout/test/data/hyphenation` は、`README.md`、`showhyphens.lua`、`showhyphens.tex`、`showhyphens.txt` の四つを出す。
- `git check-ignore -v modules/golem-layout/test/data/hyphenation/showhyphens.log` は、作者の環境の git の全体の除外の設定の `*.log` の行を出す。リポジトリの `.gitignore` は、このファイルを無視しない。
- 行分割の参照テストのログ（`test/data/knuth-plass/frog-king.log` と `ties.log`）は、コミットされている。
- `main` の新しい `git worktree` に、元のチェックアウトの `cabal.project.local` と `dist-newstyle/src` を写して README のインストールのコマンドを動かすと、上の Cabal-6661 で終了コード 1 になる。
- 同じ worktree の `cabal sdist all` も、同じエラーで終了コード 1 になる。
- `modules/*/*.cabal` の `extra-source-files`、`extra-doc-files`、`data-files` のすべてのパターンを `git ls-files` に当てると、一つも当たらないのは golem-layout の `test/data/hyphenation/*.log` だけである。
- ディレクトリの README.md の手順を、README.md が記録した Docker のイメージ（`texlive/texlive@sha256:07e8062637249c4f780ca59f42cc2ed592bc2dc1db4320769406aee3f98aa70e`、LuaHBTeX 1.24.0、TeX Live 2026）で動かすと、154 行の `showhyphens.log` ができる。そのログから README.md の `awk` で抜き出した一覧は、コミットされた `showhyphens.txt` とバイト単位で等しい（`cmp` が差を出さない）。
- ログを戻したチェックアウトでは、`cabal sdist all` は終了コード 0 で、39 の tarball（golem の 34 のパッケージと、`source-repository-package` の peg-hs の 5 つ）を書き、壁時計で 4.4 秒かかった。
- golem-layout の `cabal check` は、当たらないワイルドカードを `[no-glob-match]` の警告として出す。同時に、`-Werror` を `[werror]` のエラーとして出し、`Hackage would reject this package.` で終わる。
- `main` の `3d8d5a9ca` の `ci.yml` の実行は成功している（`gh run list --branch main --workflow ci.yml`）。当たらないワイルドカードは、`cabal build` と `cabal test` を落とさない。
- `.github/` と `scripts/` に `cabal sdist` を動かす箇所は無い（`grep -rn sdist .github/ scripts/` は、`pr-caches.sh` のキャッシュの名前の `isdist` だけを出す）。
- `scripts/ci/ci-critical-path.sh` が出したプルリクエストの CI の時間の中央値は 330 秒で、[root ADR 0392](0392-budget-the-pull-request-ci-at-five-minutes.md) の予算の 300 秒を、この ADR の前から超えている。
- 成功したプルリクエストの `ci.yml` の直近 15 回で、`build (ubuntu-24.04, outputs)` の時間は、`build` のランナーの最も長いものより 67 秒から 156 秒短い。

## 実装すること

### 1. ログを戻す

`modules/golem-layout/test/data/hyphenation/showhyphens.log` を、上の手順で作り直してコミットする。
全体の除外の設定に当たるので、`git add -f` で加える。
ディレクトリの README.md と golem-layout.cabal は変えない。
README.md は、このログをディレクトリのファイルに挙げており、ログがあることが README.md と [root ADR 0276](0276-hyphenate-words-by-the-patterns-of-their-language.md) の期待値の作り方に合うからである。

### 2. CI で `cabal sdist all` を動かす

`ci.yml` の `build` ジョブに、`cabal sdist all` を動かす手順を一つ加える。
手順は `matrix.artifacts` の行（`build (ubuntu-24.04, outputs)`）でだけ動かし、`editors-lsp` の golem を上げる手順（[ci.yml の 431 行目から 436 行目](https://github.com/tett23/golem/blob/3d8d5a9caf94abafc7b58980bc6aa656e4a2084b/.github/workflows/ci.yml#L431-L436)）の直後に置く。
tarball は `$RUNNER_TEMP` の下に書き、成果物として上げない。

`cabal sdist all` は、`cabal.project` のパッケージ（`modules/` の下の golem のパッケージと、`source-repository-package` の peg-hs のパッケージ）のすべてについて、`cabal install` と同じ手順で tarball を作る。
そのため、当たらないワイルドカードのほかに、tarball を作れない構成も同じ手順で見つかる。
CI のチェックアウトは `git` が追うファイルだけを持つので、手元で無視されたファイルに当たっているワイルドカードも、CI では当たらずに失敗する。

### 3. [root ADR 0395](0395-bring-the-pull-request-ci-under-five-minutes.md) の A1 のテストを合わせる

[root ADR 0395](0395-bring-the-pull-request-ci-under-five-minutes.md) の A1 のテスト（[scripts/ci/test.sh の 5240 行目から 5261 行目](https://github.com/tett23/golem/blob/3d8d5a9caf94abafc7b58980bc6aa656e4a2084b/scripts/ci/test.sh#L5240-L5261)）は、`cabal build` の後の手順の一覧を、0395 の前のコミットの一覧と比べる。
2 の手順はその一覧に一行を足すので、テストは、計画の検査（`same-plan.sh`）を除くのと同じく、`cabal sdist all` の手順を除いて比べる。
除く理由として、この ADR をテストの注釈に書く。

### 4. 文書

README の `build` ジョブの節に、x86-64 の `outputs` が `cabal sdist all` でパッケージのファイルの一覧を確かめることを書く。

## 実装しないこと

- `git ls-files` にワイルドカードを当てるスクリプトを書くこと。cabal のワイルドカードの規則（拡張子の扱い、`**`）を写すことになり、写しと cabal が食い違えば検査が外れる。cabal 自身に展開させるほうが、README の手順と同じ判定になる。
- `cabal check` を使うこと。`-Werror` をエラーにするので、Golem のパッケージはどれも通らない。
- CI で `cabal install exe:golem` を動かすこと。インストールの手順はパッケージを tarball から組み直すので、ビルドをもう一度行うことになる。失敗の原因になった tarball の作成は、`cabal sdist all` で確かめられる。
- aarch64 と macOS で動かすこと。ワイルドカードの展開は、チェックアウトのファイルにだけよる。
- 手元の pre-commit で確かめること。手元のチェックアウトには無視されたファイルが残るので、今回の食い違いを見つけられない。
- プルリクエストの CI の時間の予算の超過（330 秒）を直すこと。この ADR の前からの超過であり、別に扱う。

## 不変条件

ここでの「当たらない」は、CI のチェックアウトの中で、ワイルドカードに当たるファイルが一つも無いことをいう。

- `I1`: `cabal.project` のパッケージ（golem と peg-hs のもの）のどれかの `extra-source-files`、`extra-doc-files`、`data-files` に当たらないワイルドカードがあれば、`build (ubuntu-24.04, outputs)` は失敗する。
- `I2`: すべてのワイルドカードが一つ以上のファイルに当たり、ほかに tarball を作れない原因が無ければ、2 の手順は成功する。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| 当たるファイルが 0 個のワイルドカードが一つある | 失敗する | I1 |
| すべてのワイルドカードに当たるファイルがちょうど 1 個以上ある | 成功する | I2 |
| ワイルドカードに当たるファイルが手元にだけあり、`git` が追っていない | CI では当たらず、失敗する | I1 |
| ログを戻す前の `main`（`3d8d5a9ca`） | 失敗する | I1 |
| ログを戻した後 | 成功する | I2 |

## 受けいれ条件

- `A1`: ログを戻す前の `main` の `git worktree` で、`cabal sdist all` が Cabal-6661 で終了コード 1 になる。
- `A2`: この ADR を実装したプルリクエストの CI で、2 の手順が成功する。
- `A3`: この ADR をマージした後の `main` の新しい `git worktree`（`cabal.project.local` と `dist-newstyle/src` を写したもの）で、README のインストールのコマンドが終了コード 0 で終わり、`golem` を置く。
- `A4`: `scripts/ci/test.sh` の [root ADR 0395](0395-bring-the-pull-request-ci-under-five-minutes.md) A1 のテストが通る。

## テスト設計

2 の手順は cabal の振る舞いを確かめるもので、golem のスクリプトを持たないので、自動のテストは書かない。
I1 と I2 は、次の手で確かめる。

- I1 と A1: ログを戻す前の `main` の worktree で、`cabal sdist all` を動かし、終了コードとエラーを見る（「調査した事項」で確かめた）。
- I2 と A2: プルリクエストの CI の `build (ubuntu-24.04, outputs)` のログで、2 の手順が 39 の tarball を書いて成功したことを見る。
- A3: マージの後に、`main` の新しい worktree でインストールのコマンドを動かす。

A4 は、今ある `scripts/ci/test.sh` のテストを、3 の変更を入れる前に 2 の手順だけを加えて動かし、失敗することを見てから、3 の変更で通す。

## トレードオフ

- 検査は x86-64 の一つのランナーでだけ動く。ワイルドカードの展開はアーキテクチャによらないので、ほかのランナーで動かしても見つかるものは増えない。
- `build (ubuntu-24.04, outputs)` が数秒長くなる。直近 15 回では、このランナーは最も長い `build` のランナーより 67 秒以上短く、プルリクエストの CI の時間の道には乗らない。
- `cabal sdist all` は peg-hs のパッケージの tarball も作る。peg-hs はコミットで固定しているので、peg-hs の側の変更で検査が落ちることはない。peg-hs の固定を上げたときに、その tarball を作れなければ落ちる。
- 手元では無視されたファイルがワイルドカードに当たるので、手元の `cabal sdist all` は CI と違って成功することがある。

## 参考文献

- [Cabal の package description の `extra-source-files`](https://cabal.readthedocs.io/en/stable/cabal-package-description-file.html#pkg-field-extra-source-files)
