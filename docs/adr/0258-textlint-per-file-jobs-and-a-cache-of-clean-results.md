# ADR 0258: textlint をファイルごとのジョブで並べ、何も報告しなかったジョブを覚える

ステータス: 採択

## 文脈

[ADR 0036](0036-textlint-for-documents.md) は、文書の表記の検査を textlint で行い、五つのプロファイルを並行して走らせると決めた。
そのトレードオフの節は、手元の計測で五つのプロファイルを約 10 秒と見積もっている。
今の CI の `textlint` の手順は、その数倍かかる。
`docs.yml` の 2026-11-09 の 10 の実行（04:28Z から 04:46Z）では、`textlint` の手順が 39 秒から 70 秒（中央値 55 秒）、規則のテストの手順が 4 秒から 8 秒、ジョブの全体が 58 秒から 97 秒だった。
`node_modules` のキャッシュはどの実行でも当たり、`npm ci` は 0 秒である。

[ADR 0036](0036-textlint-for-documents.md) は、textlint の結果のキャッシュ（`--cache`）を「CI では毎回まっさらなので効かない」として実装しないことにした。
メンテナーは、パッケージを最新に上げることと、キャッシュで速くできるかを試すことを求めた。
この ADR は、その試した結果と、採る変更を決める。

### 時間はどこに使われているか

手元（Apple Silicon の 10 コア、Node 26.11.1）で、プロファイルを一つずつ走らせた（2026-11-09、`origin/main` の [3a93bf6d](https://github.com/tett23/golem/tree/3a93bf6d5530cad30c056c26b81efcd36a65bfce)）。

| プロファイル | ファイル | バイト | 秒（実時間） |
| --- | --- | --- | --- |
| `docs` | 15 | 1,253,589 | 37.1 |
| `diagnostics` | 1 | 504,503 | 25.2 |
| `manual` | 24 | 632,854 | 0.3 |
| `manual-dev` | 22 | 487,388 | 0.3 |

スクリプトの全体は 38.7 秒から 43.3 秒（3 回）で、`docs` のプロファイルの時間とほぼ等しい。
並行に走るのはプロファイルの単位なので、全体の時間は最も重いプロファイルで決まる。
`docs` の 37 秒のうち、`docs/specifications.md`（651,458 バイト）の一つだけで 26.8 秒を使う。

`docs/specifications.md` だけを `node --cpu-prof` で測ると、26.8 秒の内訳は次のとおりだった。

- sentence-splitter（5.0.1、npm の最新）が 10.1 秒（38%）。そのうち 9.2 秒は `SourceCode` のコンストラクターである。段落ごとに、ファイルの先頭からその段落までの長さの配列を作り直す（[`SourceCode.js`](https://github.com/textlint-rule/sentence-splitter/blob/v5.0.1/src/parser/SourceCode.ts) の `firstOffset`）ので、時間はファイルの長さと段落の数の積に比例する。大きなファイルほど、バイトあたりで遅い。
- kuromoji の形態素解析が 5.9 秒、その辞書の doublearray が 1.8 秒。
- textlint-rule-helper の `IgnoreNodeManager` が 3.9 秒。

規則で分けると、sentence-splitter と kuromoji を呼ぶ `no-doubled-conjunctive-particle-ga`、`max-ten`、`no-doubled-conjunction` がそれぞれ 3 秒前後を使う。
kuromoji の辞書の読み込みは、プロセスごとに 0.5 秒ほどである（小さなファイル一つの検査が 0.52 秒）。
マニュアルの `.gm` は平文として読み、Golem の規則と prh しか当てないので、二つのプロファイルを合わせても 1 秒に満たない。

時間を使っているのは、上流の規則の中の、ファイルの大きさに対して線形でない処理である。
これを Golem の側で直すには、上流のパッケージを書き換えることになる。
一方で、ファイルを分けて並べれば、全体の時間は最も重いファイル一つの時間まで縮む。

### パッケージを最新に上げた結果

npm の公式のレジストリで、直接の依存の最新を調べた（2026-11-09）。

| パッケージ | 今 | 最新 |
| --- | --- | --- |
| textlint | 15.8.0 | 15.8.0 |
| textlint-rule-preset-ja-technical-writing | 12.0.2 | 12.0.2 |
| textlint-rule-preset-ja-spacing | 3.0.3 | 3.0.4 |
| @textlint-ja/textlint-rule-preset-ai-writing | 1.7.0 | 1.7.0 |
| textlint-rule-prh | 6.1.1 | 6.1.1 |

`package.json` で textlint-rule-preset-ja-spacing を 3.0.4 にし、`npm update` で `package-lock.json` を作り直すと、範囲の中で上がる推移的な依存も上がった。
上がったのは、ja-spacing の 11 の規則（3.0.3 から 3.0.4）、textlint-rule-ja-no-successive-word（2.0.1 から 2.1.0）、@babel/parser と @babel/types と @babel/helper-string-parser、@modelcontextprotocol/core と同 server（2.3.1 から 2.4.0）、glob、table、semver、fast-uri で、lodash.truncate が外れた。
`package-lock.json` の 397 のパッケージは、どれも `https://registry.npmjs.org/` から取り、`sha512-` の integrity を持つ（残る一つは `file:rules` の Golem の規則）。
範囲の外の版（textlint-rule-no-hankaku-kana が依存に持つ textlint-tester 13.4.1、textlint-rule-ja-no-abusage が持つ textlint-rule-prh 5.3.0 など）は、上流のプリセットが範囲を上げない限り上がらない。

上流の変更は二つである。

- textlint-rule-ja-no-successive-word 2.1.0 は、記号や空白の連続を許すオプションを足した（[#36](https://github.com/textlint-ja/textlint-rule-ja-no-successive-word/pull/36)）。既定は変わらない。
- ja-spacing 3.0.4 は、`ja-no-space-around-parentheses` が続きの行の字下げを報告しないように直した（[#141](https://github.com/textlint-ja/textlint-rule-preset-ja-spacing/pull/141)）。

報告が変わるかは、CI の対象より広い範囲で確かめた。
`docs` のプロファイルで `docs/` の全 Markdown（ADR と記録を含む）、README.md、CONTRIBUTING.md、functions/README.md を、`adr` のプロファイルでコミット済みの全 ADR を、ほかの三つのプロファイルで CI と同じ対象を、上げる前と後のそれぞれで `--format json` で検査した。
報告は上げる前が 3,387 件（`docs` で 1,879 件、`adr` で 1,508 件）で、ファイル、行、桁、規則、重大度、メッセージ、直しの組がすべて一致した。
報告が増えた規則も減った規則もない。
CI の対象では、上げる前も後も報告は 0 件である。
`node --test tools/textlint/test/*.test.js` の 46 のテストは、上げた後も通る。

上げても速さは変わらない。
変わった規則は、時間を使っている sentence-splitter、kuromoji、textlint-rule-helper のどれでもないからである。

### textlint の `--cache` が使えない理由

textlint 15.8.0 の `--cache` は、ファイルの中身ではなく、更新の時刻と大きさで変更を判定する（[`cache-backer.js`](https://github.com/textlint/textlint/blob/v15.8.0/packages/textlint/src/engine/execute-file-backers/cache-backer.ts) が `file-entry-cache` をチェックサムなしで作る。上流のコメントも、CI で使うには中身のキャッシュが要ると書いている）。
設定の変更は、textlint の版と設定の記述の JSON の MD5 で判定する（[`createLinter.ts`](https://github.com/textlint/textlint/blob/v15.8.0/packages/textlint/src/createLinter.ts) の `createHashForDescriptor`）。
手元の小さなリポジトリで、二つの誤りを再現した。

- prh の辞書に規則を足しても、設定の記述（辞書のパス）は変わらないので、キャッシュは当たる。`--cache` の実行は何も報告せず、キャッシュなしの実行は prh の報告を出した。規則のパッケージの版を上げたときと、Golem の規則のコードを変えたときも、同じ理由で当たる。
- 中身を変えたファイルの大きさを変えずに、更新の時刻を元に戻す（`touch -r`）と、キャッシュは当たる。`--cache` の実行は何も報告せず、キャッシュなしの実行は報告を出した。

CI では、`actions/checkout` がすべてのファイルの更新の時刻を今の時刻にするので、戻したキャッシュは一度も当たらない。
[ADR 0036](0036-textlint-for-documents.md) の判断は、textlint の `--cache` については今も正しい。

### 報告の順序は決まっていない

textlint は、一つのプロセスに渡した複数のファイルの報告を、glob が返した順に出す（[`find-util.ts`](https://github.com/textlint/textlint/blob/v15.8.0/packages/textlint/src/util/find-util.ts) が非同期の `glob` で探す）。
手元で、六つのファイル（三つが報告を出す）を一つのプロセスで検査する今のスクリプトを 24 回同時に走らせると、23 回は名前の順、1 回は順が入れ替わった。
報告の中身は同じでも、出力のバイト列は実行ごとに変わりうる。

## 実装すること

### ファイルごとのジョブ

`scripts/ci/textlint.sh` は、Markdown のファイル（`docs`、`diagnostics`、`adr` の各プロファイルの対象）を一つずつ別のジョブにする。
二つのマニュアルは、プロファイルごとに一つのジョブのままとする。
マニュアルのジョブは 1 秒に満たず、ファイルごとにすると kuromoji を読まないプロセスの起動の時間がファイルの数だけ増えるからである。

ジョブは、大きいもの（ファイルのバイトの和）から順に、`TEXTLINT_JOBS` 個ずつ並べて走らせる（`xargs -P`）。
`TEXTLINT_JOBS` を省くと、`getconf _NPROCESSORS_ONLN` のプロセッサの数を使う。
大きい順に始めるのは、最も重い二つ（`docs/diagnostics.md` と `docs/specifications.md`、それぞれ 26 秒ほど）を後で始めると、その分だけ全体が延びるからである。

報告は、ジョブを数えた順（今のプロファイルの順、その中は `git ls-files` の順）に出す。
走った順に依らないので、並べる数を変えても出力は同じになり、上の textlint の順序の揺れもなくなる。
報告の書式は、ファイルごとに textlint の既定（stylish）の一つの塊になり、末尾の「✖ N problems」の行もファイルごとに出る。
今はプロファイルごとに一つの塊である。
報告の中身（ファイル、行、桁、規則、メッセージ）は変わらない。

ジョブの textlint が 0 でない終了コードで終われば、スクリプトはそのファイルの名前を標準エラーに書き、終了コード 1 で終わる。
今の「the docs profile failed」はプロファイルを名指すが、新しいスクリプトはファイルまで名指す。
`docs/diagnostics.md` は、ほかのプロファイルと同じく `git ls-files` で探し、ないときはジョブを作らない。

### 何も報告しなかったジョブを覚えるキャッシュ

ジョブには、キーを付ける。
キーは、次のすべてを並べたものの Git のハッシュ（`git hash-object --stdin`）である。

- プロファイルの名前
- ジョブのファイルのパスと、そのバイト列のハッシュ（`git hash-object --no-filters`。改行の変換をしない生のバイト列）
- `tools/textlint/` の下のすべてのファイル（`node_modules` を含み、キャッシュの置き場所 `tools/textlint/.cache` を除く）の名前とバイト列のハッシュ
- `scripts/ci/textlint.sh` のバイト列のハッシュ
- `node --version`

`tools/textlint/` の下には、設定、Golem の規則、prh の辞書、`package-lock.json`、入れたパッケージのすべてがある。
textlint のジョブが読むものは、このほかに文書とスクリプトと Node だけである。
ジョブの結果を変えうる入力が変われば、キーが変わる。

ジョブが終了コード 0 で終わり、何も出力しなかったとき、スクリプトはそのキーをキャッシュのファイルに覚える。
次の実行で同じキーのジョブは、textlint を走らせず、何も出力しない。
報告を出したジョブは覚えないので、毎回走る。
キャッシュが返すのは「何も報告しない」という結果だけで、その結果は同じ入力で textlint を走らせた結果と同じである。

キャッシュのファイルは `TEXTLINT_CACHE`（既定は `tools/textlint/.cache/clean`）で、一行に一つのキーを持つ。
`TEXTLINT_CACHE=`（空）でキャッシュを止める。
`TEXTLINT_ARGS` を渡した実行（`--fix` など）は、キャッシュを読まず、書かない。
実行の後、ファイルはその実行で何も報告しなかったジョブのキーだけを持つ（古いキーは消える）。
ファイルは隣の一時ファイルに書いてから名前を変えるので、途中で止まっても半端な中身にならない。
ジョブが一つもない実行は、ファイルに触れない。
`.gitignore` に `/tools/textlint/.cache/` を足す。

手元では既定でキャッシュを使う。
キャッシュが正しさを変えない限り、既定で速いほうがよいからである。

### CI

`docs.yml` の `textlint` のジョブで、キャッシュのファイルを `actions/cache/restore@v6` と `actions/cache/save@v6` で保つ。

- 戻すキーは `textlint-clean-<OS>-<実行の ID>` で、これは常に外れる。`restore-keys` の `textlint-clean-<OS>-` が、最も新しいものを戻す（プルリクエストでは、そのプルリクエストの範囲、なければ `main` の範囲）。
- 戻した直後に `hashFiles` でファイルのハッシュを取っておき、textlint の後で、ファイルがあり、ハッシュが変わったときだけ保存する。保存のキーは `textlint-clean-<OS>-<実行の ID>-<試行の番号>` で、同じキーを二度保存しない。
- 保存は、textlint が報告を出して失敗した実行でも行う（`!cancelled()`）。キーが入力のすべてを含むので、どの実行のファイルも、どの実行にとって正しいからである。

キャッシュの正しさは、`actions/cache` のキーに頼らない。
どの古いファイルを戻しても、キーの一致しないジョブは走る。
戻すのに失敗すれば、すべてのジョブが走る（[ADR 0167](0167-leave-cache-restore-failures-as-misses.md) と同じく、外れとして扱う）。
ファイルは数 KB で、[ADR 0228](0228-keep-the-ci-caches-under-the-10-gb-limit.md) のキャッシュの上限にはほとんど響かない。

規則のテストの手順の名前を「The tests of the Golem rules, the dictionaries and the script」にする。
Node は今のまま `lts/*`（2026-11-09 に 26.13.0）、アクションは `actions/checkout@v7`、`actions/setup-node@v7`、`actions/cache@v6`（いずれも最新のメジャー版で、Node 24 で動く）のままとする。

### パッケージ

textlint-rule-preset-ja-spacing を 3.0.4 に上げ、`package-lock.json` を `npm update` で作り直す。
`tools/textlint/README.md` の版の表を直す。

### 文書

`tools/textlint/README.md` に、ジョブとキャッシュ、`TEXTLINT_JOBS` と `TEXTLINT_CACHE` の使い方を書く。
README.md の textlint の段落に、キャッシュの一文を足す。

## 実装しないこと

- **textlint の `--cache`**：文脈の節のとおり、辞書や規則の変更でも当たり、CI では当たらない。
- **上流のパッケージを書き換えて速くすること**（`patch-package` や fork）：sentence-splitter の段落ごとの配列の作り直しを直せば `docs/specifications.md` が大きく速くなる見込みはあるが、上流と違うコードを保守することになる。上流への報告は、メンテナーの判断に残す（「メンテナーが決めること」の 3）。
- **大きな文書を分けること**：`docs/specifications.md` を分ければジョブが短くなるが、文書の構成を検査の速さで決めることになる。
- **一つの Node のプロセスで全ジョブを走らせること**（textlint の API を直接呼ぶ JavaScript の実行器）：kuromoji の辞書の読み込み（プロセスごとに 0.5 秒ほど）を一度にできるが、Node の中で並べる仕組みが要り、シェルのスクリプトより複雑になる。
- **マニュアルのジョブのファイルごとの分割**：上のとおり、合わせて 1 秒に満たない。
- **規則のテストの並べ方の変更**：今も `concurrency: true` で並べている。
- **開発者のマニュアルの変更**：実行の方法（`sh scripts/ci/textlint.sh`、`TEXTLINT_ARGS=--fix`）は変わらない。

## 不変条件

- **I1 キャッシュは報告を変えない**：どの文書の集まりと、どのキャッシュのファイル（ない、空、ほかの実行のもの、キーでない行を含む）についても、スクリプトの標準出力と終了コードは、`TEXTLINT_CACHE=` で走らせた実行のものと一致する。
- **I2 キャッシュは何も報告しなかったジョブだけを持つ**：キャッシュを使った実行の後、ファイルの行は、その実行で終了コード 0 で終わり何も出力しなかったジョブ（キーが当たったジョブを含む）のキーの集まりにちょうど等しい。
- **I3 入力が変わればキーが変わる**：ジョブの文書のバイト列、文書のパス、プロファイル、`tools/textlint/` の下のどれかのファイル（名前かバイト列）、`scripts/ci/textlint.sh`、`node --version` のどれかが変われば、ジョブのキーは変わる。
- **I4 キーは同じ入力で同じ**：同じ入力のジョブのキーは、実行、作業ツリーの場所、マシンに依らない。
- **I5 報告は並べる数に依らない**：どの `TEXTLINT_JOBS`（1 以上）でも、標準出力と終了コードは同じである。
- **I6 `TEXTLINT_ARGS` はキャッシュを使わない**：`TEXTLINT_ARGS` が空でない実行は、キャッシュのファイルを読まず、書かない。
- **I7 ジョブのないプロファイル**：対象のファイルがないプロファイルはジョブを作らない。ジョブが一つもない実行は、何も出力せず、終了コード 0 で終わり、キャッシュのファイルに触れない。

I1 は、I2 から I4 と textlint の決定性から導ける。
キャッシュが返すのは「出力が空で終了コード 0」だけで、I2 によりそれはキーの入力で実際に得た結果であり、I3 と I4 により同じキーなら同じ入力である。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| キャッシュのファイル | ない、空、空行だけ、ほかのキーと「キーでない行」、`- docs` のような書式に似た行、ほかの実行のもの |
| キャッシュの当たり | すべて外れる（初回）、すべて当たる（二回目）、一つだけ外れる（一つの文書を変えた） |
| ジョブの結果 | 報告なし、報告あり、報告ありから報告なしに変わる、報告なしから報告ありに変わる |
| 変える入力 | 文書の中身、文書の名前、`tools/textlint/` の下の辞書 |
| ジョブの数 | 0、1、プロファイルに一つ、プロファイルに四つ |
| `TEXTLINT_JOBS` | 1、3、8（ジョブより多い） |
| `TEXTLINT_ARGS` | 空、空でない |

## テスト設計

`tools/textlint/test/script.test.js` を足し、規則のテストと同じ `node --test tools/textlint/test/*.test.js` で走らせる。
各テストは一時ディレクトリに Git のリポジトリを作り、`tools/textlint/` の写し（`node_modules` はリンク）と `scripts/ci/textlint.sh` の写しを置き、文書を `git add` してからスクリプトを走らせる。
プロファイルの設定は、規則のテストの設定（`test/config.js`、Golem の規則と prh だけ）に差し替える。
スクリプトの振る舞いは規則に依らず、公開のプリセットはプロセスごとに 1 秒ほどかかるからである。
テストの名前に不変条件の番号を入れる。

- I1、I2：報告を出す文書と出さない文書で、キャッシュなし、初回、二回目の出力と終了コードが一致し、キャッシュが報告を出さなかった二つのジョブのキーだけを持つ。
- I1、I2、I3：報告を出さなかった文書を、報告を出す中身に変えると、キャッシュなしと同じ報告が出て、そのキーが消える。
- I1、I3：`tools/textlint/prh/dev.yml` に規則を足すと、前の実行で報告を出さなかった文書が prh の報告を出す。
- I1、I3：文書の名前を変えると、キーが変わる。
- I1：キャッシュのファイルが空のとき、空行とほかのキーとキーでない行を持つとき、書式に似た行を持つとき、出力はキャッシュなしと一致する。
- I5：四つの文書（二つが報告を出す）で、`TEXTLINT_JOBS` が 1、8、3（キャッシュあり）の出力が一致する。
- I6：`TEXTLINT_ARGS` を渡すと、置いておいたキャッシュのファイルが変わらない。
- I7：文書がないと、出力が空、終了コード 0 で、キャッシュのファイルが変わらない。

I4 は、キーの入力にパスの絶対の形、時刻、マシンの名前を含めないことで成り立つ。
自動のテストでは、別の一時ディレクトリの二つのリポジトリで同じキーになることを確かめる。

今のスクリプトで走らせると、九つのテストのうち七つが落ちた。
キャッシュを持たないので I1 から I4 のテストが落ち、`docs/diagnostics.md` のないリポジトリでもそのファイルを検査しようとするので I6 と I7 のテストが落ちる。
キャッシュのファイルの中身を変えるテスト（I1）と I5 のテストは通った。
I5 のテストは、報告の順が揺れたときにだけ落ちる（文脈の節の 24 回に 1 回）。

自動のテストを書かない部分は、次のように動かして確かめる。

- このリポジトリの全体で、新しいスクリプトの報告がキャッシュなし、初回、二回目で一致し、今のスクリプトと同じく 0 件で終わる。
- 文脈の節の広い範囲（全 ADR と記録を含む）を、ファイルごとに分けて検査した報告が、一つのプロセスで検査した報告と一致する。
- プルリクエストの `docs.yml` の `textlint` のジョブで、初回はキャッシュが外れてすべて走り、二回目の push でキャッシュが当たり、手順の秒が減る。報告を出す文書を含む実行でも保存が走る。

## 計測

手元（上と同じマシン）で、作業ツリーに上の変更を当てて測った（2026-11-09）。
このマシンでは同時にほかの作業が走っており、ロードアベレージが 5 から 66 のあいだで動いた。
ロードアベレージが 10 前後に下がってから、今のスクリプトと新しいスクリプトを交互に 2 回ずつ走らせた結果を表に載せる。
パッケージは、どちらも上げた後のものである。

| 実行 | 秒（実時間、2 回） |
| --- | --- |
| 今のスクリプト | 37.7、38.9 |
| 新しいスクリプト、キャッシュなし（`TEXTLINT_CACHE=`） | 29.2、31.0 |
| 新しいスクリプト、空のキャッシュから（初回） | 30.6、30.0 |
| 新しいスクリプト、すべて当たる（二回目） | 1.3、1.4 |
| 新しいスクリプト、`docs/glossary.md` だけを変えた | 2.4 |
| 新しいスクリプト、`docs/specifications.md` だけを変えた | 27.4 |

負荷の高いあいだ（ロードアベレージ 15 から 66）に交互に 3 回ずつ走らせたときは、今のスクリプトが 52.8 秒から 118.8 秒、新しいスクリプトのキャッシュなしが 31.2 秒から 59.6 秒だった。
二回目の一つ（72.1 秒）は、間に `tools/textlint/README.md` を書き換えたのですべてのキーが変わり、すべて走った。
キーが `tools/textlint/` の下のすべてのファイルを含むことの、意図した結果である。

ジョブを一つずつ走らせると、`docs/specifications.md` が 26.3 秒（CPU 28.6 秒）、`docs/diagnostics.md` が 28.7 秒（CPU 30.2 秒）で、ほかの 14 の Markdown は 0.6 秒から 2.7 秒、二つのマニュアルは 0.3 秒ずつだった。
CPU の時間の和は、今のスクリプトの約 66 秒から、新しいスクリプトの約 84 秒に増える。
増えた分は、Markdown のジョブごとのプロセスの起動と辞書の読み込みで、一つあたり 1 秒ほどである。
パッケージを上げる前と後で、どのジョブの時間も測りの揺れの範囲で変わらなかった。

CI のランナー（4 コア）では、CPU の時間の和を 4 で割った 21 秒より、最も重いジョブのほうが長い。
全体の時間は、`docs/diagnostics.md` か `docs/specifications.md` の一つの時間に近づく見込みである。
今の CI の `textlint` の手順（中央値 55 秒）が手元の今のスクリプト（約 38 秒）の 1.4 倍ほどなので、キャッシュが外れたときで 40 秒前後、すべて当たれば数秒と見積もる。
CI での実際の秒は、実装のプルリクエストで測る。

ファイルを分けても報告は変わらない。
文脈の節の広い範囲（`docs` で 507、`adr` で 437 のファイル）を一つずつ別のプロセスで検査し、まとめた報告は、一つのプロセスで検査した 3,387 件と、ファイル、行、桁、規則、重大度、メッセージ、直しの組がすべて一致した。
このリポジトリの全体では、新しいスクリプトの報告は、キャッシュなし、初回、二回目のどれも 0 件で、終了コードは 0 だった。

## トレードオフ

- ファイルごとのジョブは、プロセスの起動と kuromoji の辞書の読み込み（0.5 秒ほど）をファイルの数だけ繰り返す。Markdown のジョブは今 16（ADR を足せばその数だけ増える）で、CPU の時間は合わせて数秒増える。全体の実時間は、最も重いファイル一つと、CPU の時間の和をプロセッサの数で割ったもののうち、大きいほうに近づく。
- キャッシュが当たるのは、文書も道具も変わらなかったジョブだけである。`docs/specifications.md` を変えるプルリクエスト（ADR の実装の多く）では、最も重いジョブが毎回走り、短くなるのは残りのジョブの分だけである。
- キーは `tools/textlint/` の下のすべてのファイル（約 1 万 2 千、133 MB）を読んで作るので、すべて当たる実行でも 1 秒ほどかかる。`package-lock.json` だけを読めば速いが、手で `node_modules` を変えたときにキャッシュが古くなる。正しさを選んだ。
- 報告の書式が、プロファイルごとの塊からファイルごとの塊に変わる。「✖ N problems」の行がファイルごとに出る。
- テストに、スクリプトの 20 回ほどの実行が加わる。手元の `node --test tools/textlint/test/*.test.js` は、規則のテストだけの 2.4 秒から 5.3 秒（CPU 34.8 秒）になった。4 コアの CI では、規則のテストの手順（今は 4 秒から 8 秒）が数秒延びる見込みである。

## メンテナーが決めること

1. **キャッシュを手元の既定にするか**：推奨は既定にすることである。I1 によりキャッシュは報告を変えないので、手元で何度も走らせる開発者が速さを得る。退けた案は、CI だけで `TEXTLINT_CACHE` を渡すことである。
2. **報告の書式の変化を受け入れるか**：推奨は受け入れることである。中身は変わらず、順序が決まる。退けた案は、ジョブを `--format json` で走らせ、最後に textlint の stylish の書式で一つにまとめる Node のスクリプトを足すことである。書式は保てるが、textlint の内部の API（`@textlint/linter-formatter`）に依る。
3. **sentence-splitter の線形でない処理を上流に報告するか**：手元のプロファイルで確かめた事実（`docs/specifications.md` の 26.8 秒のうち 9.2 秒が `SourceCode` のコンストラクター）はある。上流に送る前に、最小の再現と、直した版の計測を用意する必要がある。

## 決めたことの記録

2026-11-09 に、tett23 が推奨のとおりに決めた。

1. キャッシュを手元でも既定で使う。
2. 報告の書式の変化を受け入れる。
3. sentence-splitter の処理を上流に報告するかは決めていない。tett23 は、textlint に代わるものを再設計して実装することもありうると述べた。

## 参考文献

- [ADR 0036](0036-textlint-for-documents.md)、[ADR 0167](0167-leave-cache-restore-failures-as-misses.md)、[ADR 0228](0228-keep-the-ci-caches-under-the-10-gb-limit.md)
- 今のスクリプト：[scripts/ci/textlint.sh](https://github.com/tett23/golem/blob/3a93bf6d5530cad30c056c26b81efcd36a65bfce/scripts/ci/textlint.sh#L39-L95)
- 今の CI のジョブ：[.github/workflows/docs.yml](https://github.com/tett23/golem/blob/3a93bf6d5530cad30c056c26b81efcd36a65bfce/.github/workflows/docs.yml#L66-L91)
- textlint 15.8.0 のキャッシュ：https://github.com/textlint/textlint/blob/v15.8.0/packages/textlint/src/engine/execute-file-backers/cache-backer.ts
- textlint 15.8.0 の設定のハッシュ：https://github.com/textlint/textlint/blob/v15.8.0/packages/textlint/src/createLinter.ts
- file-entry-cache：https://github.com/jaredwray/cacheable/tree/main/packages/file-entry-cache
- sentence-splitter 5.0.1：https://github.com/textlint-rule/sentence-splitter/blob/v5.0.1/src/parser/SourceCode.ts
- textlint-rule-ja-no-successive-word 2.1.0：https://github.com/textlint-ja/textlint-rule-ja-no-successive-word/releases/tag/v2.1.0
- textlint-rule-preset-ja-spacing 3.0.4：https://github.com/textlint-ja/textlint-rule-preset-ja-spacing/releases/tag/v3.0.4
- `actions/cache` の restore と save：https://github.com/actions/cache
