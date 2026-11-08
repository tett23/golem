# ADR 0245: CI の warning を 0 に保つ

ステータス: 採択（未実装）

## 文脈

### 2026-11-09 に CI が出していた warning

`main` の 40eb98ce の CI（ci.yml）と、docs.yml、browser.yml、models.yml、enum.yml、release.yml、race.yml、advisories.yml の最新の実行の、すべてのジョブのログを読んだ。
release.yml は v0.1.0-rc4 のタグの実行が走っている途中だったので、その前の `workflow_dispatch` の実行（71d5b0fd）を読んだ。

GHC の warning は、ci.yml の一回の実行で 98 行あった。
GitHub の problem matcher は、それを `##[warning]` の注釈にする。
注釈は一つのジョブに 10 までしか載らないので、プルリクエストの画面では、warning の数がわからない。

手元で、空の dist-newstyle から `cabal build all --enable-tests --enable-benchmarks` を走らせると、golem のパッケージに 42 か所の warning があった。

| 種類 | か所 |
| --- | --- |
| `-Wname-shadowing` | 31 |
| `-Wunused-imports` | 6 |
| `-Wtype-defaults` | 3 |
| `-Wunused-matches` | 1 |
| `-Wincomplete-uni-patterns` | 1 |

CI のビルドのジョブは、復元した dist-newstyle から増分でビルドする（[ADR 0045](0045-split-x86-build-and-pull-request-cache.md)）。
コンパイルし直したモジュールの warning だけが出るので、ジョブによって出る warning が違う。
ライブラリの warning は、キャッシュのない release.yml と wasm のジョブにだけ出ていた。
プルリクエストの CI に出ない warning は、誰にも見られないまま残る。

wasm のビルドにだけ出る warning が 3 か所あった。
golem-pdf の `Import.hs` の `-Woverflowed-literals` である（[932 行め](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/modules/golem-pdf/src/Golem/Pdf/Import.hs#L932)、[939 行め](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/modules/golem-pdf/src/Golem/Pdf/Import.hs#L939)、[1121 行め](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/modules/golem-pdf/src/Golem/Pdf/Import.hs#L1121)）。
wasm32 の `Int` は 32 ビットなので、`0xFFFFFFFF` と `4294967296` があふれる。
ASCII85 の検査と、取りこんだ PDF の内側の Form のキーの計算が、ネイティブのビルドと wasm のビルドで違う値になる。
これは warning の掃除ではなく、振る舞いの違いである。

GHC のほかに、次の warning があった。

| warning | 出どころ | 数 |
| --- | --- | --- |
| gawk の `escape sequence \| treated as plain` など | scripts/ci/test.sh の [`step_has`](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/scripts/ci/test.sh#L1150-L1152) | 3 |
| GNU sed の `couldn't write ... Broken pipe` | scripts/ci/test.sh の [cabal update の検査](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/scripts/ci/test.sh#L1399) | 1 |
| cabal の `[relative-path-outside]` | golem-driver の `hs-source-dirs: ../golem-html/test`（[golem-driver.cabal](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/modules/golem-driver/golem-driver.cabal#L85)） | 6 |
| Node の `[DEP0005] Buffer()` | actions/download-artifact@v8 | 12 |
| git の `init.defaultBranch` の hint | actions/checkout@v7 の中の `git init` | 39 |
| ghcup の `[ Warn ]`（shadowed binaries、setModificationTime、新しい版） | haskell-actions/setup@v2 とランナーのイメージ | 48 |
| GHC の `-Wunused-packages` | wasm のビルドの skylighting のパッケージ | 2 |
| GCC 15 の `-Wstringop-overflow` | 同梱の HarfBuzz（Alpine の release のビルド） | 16 |
| macOS の `ld: warning: -U option is redundant` | GHC のリンクで macOS の ld が出す | 1 |
| Node の WASI の `ExperimentalWarning` | Node の WASI | 2 |
| Nix のインストーラーの `useradd warning` | cachix/install-nix-action@v31 | 8 |

actions は、どれもいまの最新のメジャー版である（download-artifact v8、upload-artifact v7、checkout v7、cache v6、setup-node v7）。
Node 20 の非推奨や `set-output` の注釈は、なかった。

### この ADR の前に直したもの

[#748](https://github.com/tett23/golem/pull/748) が、golem のパッケージの 42 か所と、scripts/ci/test.sh の awk と sed の warning を、振る舞いを変えずに直した。
`Import.hs` の 3 か所と、cabal の `relative-path-outside` は、残した。
前者は wasm の振る舞いを変え、後者は [ADR 0217](0217-html-spaces-of-paragraph-styles-redefined-in-files.md) と [ADR 0229](0229-record-the-procedures-adr-0215-and-0217-departed-from.md) が決めた構成だからである。

### 0 にしても、また増える

warning は、出ても CI が通るかぎり、増える。
42 か所は、どれも誰かのプルリクエストで入り、CI を通った。
すでに、警告の一つを止める仕組みはある。
すべてのコンポーネントが `-Werror=incomplete-patterns` でビルドされることを、[`scripts/ci/incomplete-patterns.sh`](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/scripts/ci/incomplete-patterns.sh) が検査している（[ADR 0027](0027-exhaustive-command-dispatch-by-types.md)、[ADR 0069](0069-lint-scripts-bypassed-by-plain-rewrites.md)、[ci.yml の step](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/.github/workflows/ci.yml#L58)）。
この ADR は、それをすべての GHC の warning と、CI のログの warning に広げる。

## 実装すること

### 1. golem のパッケージを `-Werror` でビルドする

`modules/` のすべてのパッケージの、すべてのコンポーネント（library、executable、test-suite、benchmark）の `ghc-options` に `-Werror` を足す。
`common warnings` を持つパッケージはそこに、持たない golem-cli は各コンポーネントの `ghc-options` に足す。
依存するパッケージ（Hackage のものと、`source-repository-package` の peg-hs）には足さない。
`cabal.project` と `cabal.project.wasm` の `ghc-options` には書かない。
そこに書いたオプションが、依存するパッケージ（とくに `source-repository-package` の peg-hs）に及ぶかを、cabal の版ごとに確かめなければならないからである。

### 2. 検査のスクリプト

`scripts/ci/werror.sh` を足す。
読み方は `scripts/ci/incomplete-patterns.sh` と同じにする（共通の stanza を読んだ後の `ghc-options`、大文字と小文字、字下げ）。
次のどれかがあれば、場所を標準エラー出力に書き、終了コード 1 で終わる。

- `-Werror` を持たないコンポーネント
- `-Werror` の後に、`-Wwarn` か `-Wno-error`（`=` の付いたものも含む）を持つコンポーネント
- `modules/` の Haskell のファイルの `OPTIONS_GHC` の、`-Wwarn`、`-Wno-error`、`-Wno-` で始まる警告の無効化
- `cabal.project`、`cabal.project.wasm`、`cabal.project.local` の `ghc-options` の、`-Wwarn` と `-Wno-error`

ci.yml の `incomplete-patterns.sh` の次の step で走らせる。
`incomplete-patterns.sh` は変えない。
二つの検査は、同じファイルを別のコードで読む（[ADR 0069](0069-lint-scripts-bypassed-by-plain-rewrites.md) と同じく、検査どうしを絡めない）。

### 3. wasm32 のあふれ

1 の前に、`Import.hs` の 3 か所を、wasm32 でもネイティブと同じ値になる型に直す。
これは振る舞いを変えるので、別の ADR で決める（「メンテナーが決めること」の 2）。
その ADR が実装されるまで、この ADR の 1 は wasm のビルドを壊すので、実装できない。

### 4. GHC のほかの warning の許可の一覧

`scripts/ci/warnings-allowed.tsv` を足す。
一行に一つ、次の三つの欄をタブで区切って書く。

1. 拡張正規表現（ログの行の、時刻を除いた部分に `grep -E` で当てる）
2. 直せない理由（日本語）
3. 上流の URL（issue、リリースノート、ソース）

`#` で始まる行は注である。
最初の中身は、文脈の表のうち、golem の外から来る 8 種類である。

### 5. ログの検査

`scripts/ci/log-warnings.sh` を足す。

```
log-warnings.sh ALLOWED LOG ...
```

- 各 LOG の各行から、GitHub Actions の時刻の前置き（`2026-11-09T00:00:00.0000000Z `）を除く。
- 除いた行が、次のどれかに当たれば warning とする。
  - `##[warning]` で始まる
  - `^[^ :]+\.(hs|c|cc|cpp|h):[0-9]+:[0-9]+: warning:` に当たる（GHC と C のコンパイラー）
  - `^(awk|gawk|sed|grep|find|ld): warning` に当たる
  - `^Warning: \[` で始まる（cabal）
  - `DeprecationWarning` か `ExperimentalWarning` を含む
  - `^npm warn` で始まる（大文字と小文字を区別しない）
- warning のうち、ALLOWED のどの行の正規表現にも当たらないものを、`LOG:行番号: 行` の形で標準出力に書く。
- 一つでも書けば終了コード 1、なければ 0 で終わる。ALLOWED の書き方の誤り（欄が三つでない、正規表現が `grep -E` で誤り）は終了コード 2 とする。

golem の diagnostic（`warning[G03010]` など）と、テストの名前の「warning」は、上の形のどれにも当たらない。
当てるのは行の頭の形だけで、行の中の語では探さない。

### 6. ci.yml の最後のジョブで検査する

ci.yml の `ci` のジョブ（[gate.sh を走らせるジョブ](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/.github/workflows/ci.yml#L1148-L1159)）に、`permissions: actions: read` と、次の step を足す。

- `gh api` で、同じ実行のジョブの一覧と、`ci` 自身を除く各ジョブのログを取る。
- `log-warnings.sh scripts/ci/warnings-allowed.tsv` に渡す。
- 失敗したら、`ci` のジョブを失敗にする。gate.sh の結果とは別の step にし、どちらが落ちたかを分ける。

release.yml は ci.yml を呼ぶので、同じ検査が走る。
release.yml 自身のジョブ、docs.yml、browser.yml、models.yml、enum.yml、race.yml、advisories.yml の検査は、この ADR ではしない（「メンテナーが決めること」の 4）。

### 7. 文書

`docs/specifications.md` の CI の節に、1 と 6 を書き、この ADR へのリンクを付ける。
README の開発の節に、手元で warning を見ながら作業するときは、自分の `cabal.project.local` に `-Wwarn` を書けば止まらないことと、その `cabal.project.local` を CI に持ちこめないこと（werror.sh が落とす）を書く。

## 実装しないこと

- 依存するパッケージの warning を直すことも、`-Werror` でビルドすることもしない。
- 上流の warning を `--no-warnings` や `-Wno-` で消すことはしない。許可の一覧に、理由と上流の URL とともに書く。
- 許可の一覧の行が、最近の実行で一度も当たらなかったことを検査しない（「メンテナーが決めること」の 5）。
- GHC の警告の集合（`-Wall` などの組）は変えない。
- cabal の `relative-path-outside` を直すこと（golem-html の `test/CssCascade` の置き場所を変えること）は、この ADR ではしない（「メンテナーが決めること」の 3）。
- hlint と fourmolu の扱いは変えない。どちらも今のまま、指摘があれば format のジョブが落ちる。

## 不変条件

1. **W1**：`modules/` のどのパッケージのどのコンポーネントでも、そのソースが GHC の warning を一つでも出せば、`cabal build` は失敗する。
2. **W2**：依存するパッケージだけが warning を出すとき、`cabal build` は成功する。
3. **W3**：werror.sh は、`-Werror` を持たないか、後で取り消すコンポーネントが一つでもあるとき、そのときに限り、終了コード 1 で終わる。
4. **W4**：log-warnings.sh の出力の行の集合は、warning の形に当たり、許可の一覧のどの正規表現にも当たらない行の集合に等しい。終了コードは、それが空のとき 0、空でないとき 1 である。
5. **W5**：log-warnings.sh の結果は、ログの行の順と、許可の一覧の行の順によらない（出力の行の集合と終了コードが同じ）。
6. **W6**：golem の diagnostic の行（`<file>:<line>:<col>: warning[Gnnnnn]: ...`）と、tasty のテストの名前の行は、warning の形に当たらない。

境界の入力：

| 入力 | W1、W2 | W3 | W4 | W6 |
| --- | --- | --- | --- | --- |
| warning のないパッケージ | 成功 | 0 | | |
| library に一つの warning | 失敗 | | | |
| test-suite に一つの warning | 失敗 | | | |
| 依存するパッケージに一つの warning | 成功 | | | |
| wasm32 だけで出る warning | wasm のビルドが失敗 | | | |
| `-Werror` のないコンポーネントが一つ | | 1 | | |
| `-Werror` の後に `-Wwarn` | | 1 | | |
| `-Werror` の後に `-Wno-error=name-shadowing` | | 1 | | |
| `OPTIONS_GHC -Wno-name-shadowing` | | 1 | | |
| 空のログ | | | 出力なし、0 | |
| warning が一つ、許可なし | | | その行、1 | |
| warning が一つ、それにちょうど当たる許可 | | | 出力なし、0 | |
| warning が二つ、許可は一つにだけ当たる | | | もう一つの行、1 | |
| 許可の一覧が空 | | | すべての warning、1 | |
| 欄が二つの許可の行 | | | 2 | |
| `warning[G03010]` を含むテストの出力 | | | | 当たらない |
| `G05004 unreferenced labels are warnings` というテストの名前 | | | | 当たらない |

## テスト設計

- **W3**：scripts/ci/test.sh に、`testdata/werror/` の小さな `modules/` の木で、境界の表の werror.sh の行をそれぞれ確かめる。今の `incomplete-patterns.sh` のテストと同じ形にする。スクリプトがないので、初めは失敗する。
- **W4、W5、W6**：scripts/ci/test.sh に、`testdata/log-warnings/` のログと許可の一覧で、境界の表の log-warnings.sh の行を確かめる。ログには、40eb98ce の CI のログから取った実際の行（時刻つき）を使う。W5 は、ログの行と許可の一覧の行を逆にした入力で、出力を `sort` したものと終了コードが同じことを確かめる。スクリプトがないので、初めは失敗する。
- **W1、W2**：自動のテストにしない。実装のプルリクエストで、次を一度ずつ手で確かめ、プルリクエストに書く。
  - golem-length の library に使わない import を一つ足すと、`cabal build golem-length` が失敗し、取ると成功する。
  - golem-length の test-suite で同じことをする。
  - `cabal build all` の `dist-newstyle/cache/plan.json` で、`-Werror` が golem のパッケージの `ghc-options` にだけあり、peg-hs と Hackage のパッケージにないこと。
- **6**：実装のプルリクエストの CI で、`ci` のジョブの新しい step が通ること。加えて、一時的なコミットで test.sh に `awk -v x='\|' 'BEGIN{}'` を足し、その step が落ちて、その行を書くことを確かめ、コミットを取り消す。

## トレードオフ

- `-Werror` を .cabal に書くと、手元の作業の途中でも、使わない import 一つでビルドが止まる。CI だけで `-Werror` を足す方法（CI が `cabal.project.local` に書く）は、手元を止めない。その代わり、CI のどのジョブがそれを書き忘れても warning が通り、書いたかを確かめる検査が別に要る。.cabal に書けば、`incomplete-patterns.sh` と同じ仕組みで一か所を検査すればよい。手元で止めたくないときは、自分の `cabal.project.local` に `-Wwarn` を書けばよい。
- GHC を上げると、新しい警告で、コードを変えずにビルドが落ちる。GHC を上げるプルリクエストで、その警告を直すことになる。上げる作業は大きくなるが、上げた後に warning が残ることはない。
- ログの検査は、上流が新しい warning を出すと、golem のコードを変えずに CI を落とす。許可の一覧に足すか、上流の版を戻すまで、プルリクエストが止まる。許可の一覧に理由と URL を書かせるのは、足すことを安易にしないためである。
- ログを `gh api` で取るので、`ci` のジョブが数十秒長くなり、`actions: read` の権限が要る。
- 行の頭の形だけを当てるので、形の違う warning（たとえば上流の道具の独自の書き方）は見逃す。見逃したものに気づいたら、形を足す。行の中の語で探すと、golem の diagnostic とテストの名前に当たり、許可の一覧が golem 自身の出力で埋まる。

## メンテナーが決めること

1. **`-Werror` の置き場所**：案 1 は各 .cabal の `ghc-options`、案 2 は CI が書く `cabal.project.local`、案 3 は `cabal.project` の最上位である。推奨は案 1 である。今の `-Werror=incomplete-patterns` と同じ置き場所と検査で、手元と CI と release のビルドが同じフラグになる。案 3 は、`source-repository-package` の peg-hs に及ぶかを cabal の版ごとに確かめる必要があり、W2 を保証しにくい。
2. **wasm32 のあふれ**：`Import.hs` の 3 か所は、wasm のビルドの振る舞いを変える。推奨は、この ADR の実装の前に、別の ADR で `Int64` に直すことを決めること。ネイティブ（64 ビット）の値は変わらず、wasm がネイティブに揃う。golem-doc の `inInt64` も、`Int` の範囲で判定しているので、wasm32 では 32 ビットの範囲になる（[IR.hs](https://github.com/tett23/golem/blob/40eb98ce0abc39c8b11db3c09389b98e8e2efe05/modules/golem-doc/src/Golem/Doc/IR.hs#L65-L66)）。warning は出ないが、同じ ADR で扱うことを推奨する。
3. **cabal の `relative-path-outside`**：golem-driver の test-suite が golem-html の `test/` を読む構成をやめるか。推奨は、やめる別の ADR を立てること。`sdist` で壊れる構成であり、テスト用の小さな module なら、写しを置けばよい。[ADR 0217](0217-html-spaces-of-paragraph-styles-redefined-in-files.md) の決めた構成を変えるので、ADR が要る。この ADR では許可の一覧に入れない。golem 自身が直せるものだからである。決まるまでの間、ログの検査が落ちるので、この ADR の 6 は、その ADR の後に実装する。
4. **ログの検査の範囲**：案 1 は ci.yml だけ（release.yml は ci.yml を呼ぶので含まれる）、案 2 はすべてのワークフローである。推奨は案 1 である。プルリクエストを止めるのは ci.yml と docs.yml で、毎晩と週に一度のワークフローは、落ちても誰かのプルリクエストを止めない。docs.yml は Haskell をビルドせず、warning もなかったので、問題が出てから足せばよい。
5. **許可の一覧の古い行**：上流が直した後も、許可の行が残る。推奨は、検査しないこと。行が当たったかは実行ごとに違い（キャッシュの当たり外れ、ジョブの飛ばし）、一度当たらなかっただけで落とすと不安定になる。上流の版を上げるプルリクエストで、見直す。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-09、メンテナー）：どれも推奨のとおりとした。wasm32 のあふれと `relative-path-outside` は、それぞれ別の ADR で先に直す。

## 参考文献

- GHC User's Guide, "Warnings and sanity-checking": https://downloads.haskell.org/ghc/9.10.3/docs/users_guide/using-warnings.html
- Cabal User Guide, "cabal.project Reference": https://cabal.readthedocs.io/en/stable/cabal-project-description-file.html
- GitHub Docs, "Workflow commands for GitHub Actions"（`::warning` と注釈）: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands
- GitHub Docs, "Download job logs for a workflow run job"（REST API）: https://docs.github.com/en/rest/actions/workflow-jobs#download-job-logs-for-a-workflow-run-job
