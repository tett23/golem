# ADR 0036: 文書の表記を textlint で検査する

ステータス: 採択

## 文脈

Golem の文書（`docs/` の仕様書、README、CONTRIBUTING、ADR、二つのマニュアル）は日本語で書き、表記の規則を CONTRIBUTING.md と [docs/manual-policy.md](../manual-policy.md) に置いている。
規則のうち、一文ごとの改行、ダッシュと中黒の禁止、全角と半角のあいだの空白、用語の使い分けは、文字と行を見れば判定できる。
今は、これらをレビューだけで守っている。
レビューの時間は、事実の確認や論理の矛盾のように人にしか見つけられない誤りに使いたい。

仕様書の「lint」の節は、表記の検査を Golem の処理系に持たせず、外部の校正ツールの役割としている（[golem-lint ADR 0001](../golem-lint/adr/0001-lint-rules.md)）。
Golem 自身の文書にも、その外部のツールを使えばよい。

調べた候補は次のとおりである（2026-10-17 時点）。

- textlint（MIT）と、日本語の技術文書の規則のプリセット textlint-rule-preset-ja-technical-writing（MIT）、全角と半角の空白の規則の textlint-rule-preset-ja-spacing（MIT）、LLM が書きがちな表現を拾う @textlint-ja/textlint-rule-preset-ai-writing（MIT）、表記の辞書の textlint-rule-prh（MIT）。どれもオフラインで動き、規則を npm のパッケージとして固定できる。
- textlint-rule-preset-jtf-style は、全角と半角のあいだに空白を入れない規則を持ち、Golem の表記（`Golem の`）と衝突する。
- Vale は日本語の分かち書きを持たず、RedPen は 2020 年から更新がなく、LanguageTool は日本語の規則が少ない。

メンテナーは、上の五つのパッケージを `tools/` の下に開発の依存として入れることを認めた。
あわせて、次の表記の規則を決めた。

- 日本語の文は一文ごとに改行する。ただし、箇条書きの項目と表のセルは、複数の文を含んでよい。
- 地の文ではダッシュを使わない。中黒は並列を表すことにだけ禁じ、外来語の区切りのようなほかの使い方は認める。
- docs/manual-policy.md の用語の規則（書体とフォント、マシンと計算機、diagnostic、アセット、バージョンと版、パブリックドメインなど）は、これからは仕様書と新しい ADR にも当てはめる。コミット済みの ADR は変更できないので、書き換えない。

## 実装すること

### 置き場所と固定

`tools/textlint/` に、文書の検査のための開発の道具を置く。
Golem の配布物には入らない。

- `package.json` と `package-lock.json`：上の五つのパッケージを、正確なバージョン（textlint 15.8.0、textlint-rule-preset-ja-technical-writing 12.0.2、textlint-rule-preset-ja-spacing 3.0.3、@textlint-ja/textlint-rule-preset-ai-writing 1.7.0、textlint-rule-prh 6.1.1）で固定する。リポジトリの根には `package.json` を置かない。
- `rules/`：公開の規則にない Golem の規則を、ローカルのプリセット `textlint-rule-preset-golem` として置く。`package.json` からは `file:rules` で参照する。
- `prh/`：用語の辞書。`common.yml`（全文書）、`dev.yml`（開発者が読む文書）、`user.yml`（使い手のマニュアル）に分ける。prh には規則をパスごとに分ける機能がないので、辞書を分け、プロファイルごとに選ぶ。
- `config/`：プロファイルごとの textlint の設定（JavaScript）。共通の部分は `config/common.js` に置き、各プロファイルが組み立てる。公開の規則を変える、または止める理由は、その設定の隣のコメントと `tools/textlint/README.md` に書く。
- `test/`：Golem の規則と辞書のテスト。

### Golem の規則

`textlint-rule-preset-golem` は、次の四つの規則を持つ。
どれも行を単位に読み、コードブロック、インラインのコード（`` ` ``）、Golem の `[code: ...]` を地の文から除いてから判定する。

- `one-sentence-per-line`：段落の一行に、括弧の外の「。」のあとに続く文があれば報告する。箇条書きの項目（`-`、`1.`、Golem の `=` と `=:`、字下げした続きの行）、表の行、見出し、Markdown の脚注の定義、Golem のブロックコマンドとコメント（`@`、`%` で始まる行）は対象にしない。括弧（`（「『【[(` とその閉じ括弧）の中の「。」は文の終わりとみなさないので、Golem の `[note: ...]` の中の文は数えない。
- `no-dash`：U+2014 と U+2015 を報告する。（——）のように括弧か鉤括弧だけで囲んで文字そのものを指す場合は除く。
- `no-nakaguro-listing`：中黒（U+30FB と半角の U+FF65）のうち、前後のどちらかがカタカナでないものを報告する。カタカナどうしのあいだの中黒は、外来語の区切りと並列を字面から区別できないので、レビューに残す。
- `review-words`：設定した語を、置き換えずに報告する。置き換えの先が意味によって変わる語（「機械」はマシンか計算機か言い換えか、「診断」は diagnostic か diagnostics か）に使う。鉤括弧の中（引いた題や、語そのものを指す場合）は除く。

### 用語の辞書

prh の辞書は、意味によらず一つに決まる置き換えだけを持つ。
鉤括弧の中の語は、題や語そのものを引いた場合とみなし、置き換えない。

| 辞書 | 置き換え |
| --- | --- |
| `common.yml` | 「公有」をパブリックドメインに |
| `dev.yml` | `common.yml` に加えて、「資産」をアセットに |
| `user.yml` | `common.yml` に加えて、「道具」をツールに |

「版」と「バージョン」、「書体」と「フォント」は、どちらも語の意味で選ぶので、辞書にも `review-words` にも入れない。
「版」は組版、版面、奥付の版、印刷の版の中にも現れ、字面ではバージョンの意味を拾えないからである。
この二組は CONTRIBUTING.md に規則として書き、レビューで守る。

### プロファイルと対象

| プロファイル | 対象 | 規則 |
| --- | --- | --- |
| `docs` | `docs/` の下の Markdown のうち、ADR、`docs/diagnostics.md`、記録（`docs/audit/`、`docs/audits/`、`docs/benchmark/`、`docs/benchmarks/`、`docs/ci-timings/`）を除いたもの。README.md と CONTRIBUTING.md | 公開の三つのプリセット（調整済み）、Golem の規則（`review-words` は「機械」）、`dev.yml` |
| `diagnostics` | `docs/diagnostics.md` | `docs` から、文末の句点、文体の混在、括弧の対応と括弧の前後の空白の検査を除いたもの |
| `adr` | ブランチが加えた ADR | `docs` から文末の句点の検査を除き、`review-words` に「診断」を加えたもの |
| `manual` | `manual/` の `.gm` | Golem の規則（`review-words` は「機械」と「シェル」）、`user.yml` |
| `manual-dev` | `manual-dev/` の `.gm` | Golem の規則（`review-words` は「機械」「診断」「お知らせ」）、`dev.yml` |

`docs/diagnostics.md` を分けるのは、各節の題と引いたメッセージが、Golem が使い手に見せるメッセージそのもの（敬体で、句点がなく、Golem の括弧を含む）だからである。
ADR の文末の句点の検査を止めるのは、adr-guard が求めるステータスの行（`ステータス: 提案`）と、参考文献の「なし」が句点で終わらないからである。

ブランチが加えた ADR は、分岐点（`git merge-base BASE HEAD`）から作業ツリーまでの差分で加わった ADR と、Git が追跡していない ADR とする。
コミット済みの ADR は、ステータスの行のほかは変えられないので、検査しない。
CONTRIBUTING.en.md は英語の翻訳なので、対象にしない。

マニュアルは、原稿の `.gm` を textlint の平文のプラグインで読み、文字と行を見る規則（Golem の規則と prh）だけを当てる。
公開のプリセットは当てない。
`[code: ...]`、`[note: ...]`、`[index ...]` のようなインラインのコマンドが文に混ざり、括弧の前後の空白、文の長さ、全角と半角の空白の規則が数千件の誤検知を出すからである。
`golem build --target text` の平文の出力を検査する方法は採らない。
`golem` の実行ファイルのビルドが要り、`docs.yml` の検査が Haskell のビルドを待つことになるうえ、平文の出力は段落を一行にまとめるので、一文ごとの改行を検査できない。

### 公開のプリセットの調整

全角と半角のあいだ、インラインのコードの前後、リンクの前後には空白を入れる（Golem の表記）。
文体は常体（である）とする。
次の規則は止めるか、緩める。

| 規則 | 扱い | 理由 |
| --- | --- | --- |
| `arabic-kanji-numbers` | 止める | Golem は数を数える語を漢数字で書く（二つ、一文）。 |
| `sentence-length` | 止める | 100 字を超える文が 251 あり、多くは仕様の項目をコードとともに並べた文である。単純な手直しでは短くできないので、レビューに残す。 |
| `no-doubled-joshi` | 止める | 123 件の報告のほぼすべてが、「A も B も」「A と B と」と、連体修飾の中の「が」（〜が指すファイルがない）だった。 |
| `max-comma` | 止める | 日本語の文は読点で区切る。半角のカンマは `(八分, 四分, 二分)` のような組の表記にしか現れない。 |
| `max-ten` | 6 以上で報告 | 仕様書は、項目を読点で並べる文が多い。 |
| `ja-no-successive-word` | ○、一つ、… を許す | 伏せ字の ○○、「一つ一つ」、三点リーダーの二連は誤りではない。 |
| `max-kanji-continuous-len` | 団体、規格、書名を許す | 日本産業標準調査会、日本語文字列照合順番のような固有名詞である。 |
| `no-ai-list-formatting` | 止める | `- **語**：説明` は用語集、ロードマップ、仕様書の定義の並べ方である。 |
| `no-ai-hype-expressions` | 「完全に静的」「完全に同じ」を許す | 静的リンクの種類と、見た目の一致の度合いを言う事実である。 |

### 実行

`scripts/ci/textlint.sh [BASE]` が、上の五つのプロファイルを並行して走らせ、報告をプロファイルの順に出す。
一つでも報告があれば終了コード 1 で終わる。
BASE を省くと `origin/main` との分岐点を使い、コミットでない BASE（ブランチを作った push の 0 の列）では ADR を検査しない。
初めて実行するときは `npm ci` でパッケージを入れる。
`TEXTLINT_ARGS=--fix` を付けると、prh と空白の規則の直しを当てる。
開発者と CI は同じスクリプトを使う。

### CI

`docs.yml` に `textlint` のジョブを足す。

- `actions/setup-node` の v7 で、Node の最新の LTS（`lts/*`）を使う。
- `tools/textlint/node_modules` を、`package-lock.json` のハッシュを鍵にして `actions/cache` の v6 で保存する。当たれば `npm ci` を省く。
- Golem の規則と辞書のテスト（`node --test`）のあと、`scripts/ci/textlint.sh` にプルリクエストのベース（`main` への push では push の前のコミット）を渡して走らせる。
- `adr` と同じく、変更のパスにかかわらず常に走る。

`main` の保護の規則が必須とする検査（`ci`、`adr`、`manual`）に、このジョブを加える。

`scripts/ci/needs-build.sh` は、`tools/textlint/` の下だけの変更をビルドの要らない変更として扱う（[docs/adr/0009](0009-ci-speed.md) の、ビルドの要らない変更を `docs/` と根の Markdown に限る規則を広げる）。
ビルドもテストも `tools/textlint/` を読まないからである。
`scripts/ci/textlint.sh` は `scripts/` の下にあるので、その変更は今までどおりビルドする。

### 規則の記録

CONTRIBUTING.md（と CONTRIBUTING.en.md）の日本語の文章の節に、上の三つの決定と、textlint の実行の方法を書く。
docs/manual-policy.md には、用語の規則が仕様書と新しい ADR にも及ぶことを書く。
開発者のマニュアルの文書の章とマニュアルの章を、同じ内容に直す。

### 今の文書を直す

この ADR を入れる変更で、今の `main` の文書の違反を直し、検査が通る状態にする。
直すのは、文を行に分ける、リンクとコードの前後の空白、パスと式をコードにする、「機械」「資産」「公有」の置き換えのような、意味を変えない小さな直しに限る。

## 実装しないこと

- **既存の文書の「診断」の置き換え**：仕様書、ロードマップ、用語集、README には「診断」が 70 ほどある。diagnostic と diagnostics の使い分けは一つずつ判断が要るので、この変更では置き換えず、`docs` のプロファイルの `review-words` にも入れない。新しい ADR と開発者のマニュアルだけを検査する。仕様書の置き換えは、別のプルリクエストで行う。
- **文の長さの検査**：上の表のとおり止める。
- **「版」と「書体」の自動の検査**：辞書の節のとおり、レビューで守る。
- **CONTRIBUTING.en.md と英語の文**：日本語の規則を当てない。英語の文の検査は持たない。
- **コミット済みの ADR の検査**：変えられないので検査しない。
- **プレーンテキストの出力の検査**：対象の節のとおり採らない。
- **textlint の結果のキャッシュ（`--cache`）**：CI では毎回まっさらなので効かない。
- **ほかのエディタとの統合（LSP など）**：開発者が各自で設定する。

## テスト設計

### Golem の規則と辞書

`tools/textlint/test/rules.test.js` を `node --test` で実行する。
各ケースは、テキストを textlint のコマンドに標準入力で渡し、報告した規則と行の組を比べる。
テスト用の設定（`test/config.js`）は、Golem の規則と辞書だけを読み、公開のプリセットを読まない。

- 一文ごとの改行：一行に二文の段落は報告し、一行に一文、箇条書きの項目、字下げした続きの行、表のセル、脚注の定義、括弧の中の文、鉤括弧の中の文、インラインのコード、コードブロック、見出しは報告しない。文の終わりのあとにリンクが続けば報告する。`.gm` では、文の終わりのあとの `[note: ...]` を報告せず、二文目を報告し、`=:` の説明と `@` のブロックコマンドを報告しない。
- ダッシュ：U+2014 と U+2015 を報告し、（——）、インラインのコード、`.gm` の `[code: —]` は報告しない。箇条書きの項目の中のダッシュも報告する。
- 中黒：漢字のあいだの中黒を報告し、カタカナのあいだ、（・）、コードの中は報告しない。
- `review-words`：設定した語を報告し、パターンが除く語（機械語）と鉤括弧の中は報告しない。
- prh：「公有」を報告し、鉤括弧で引いた ADR の題の中は報告しない。`dev.yml` は「資産」を報告し、「」の中は報告しない。`user.yml` は「資産」を報告せず、「道具」を報告する。
- 辞書の `specs`（置き換えの前後の例）は、prh が辞書を読むときに確かめ、外れれば textlint が失敗する。

### ビルドの要否

`scripts/ci/test.sh` の `needs-build.sh` のケースに次を足す。

- `tools/textlint/` の下だけの変更は `false`。
- `tools/textlint/` の下と `docs/` の下の変更は `false`。
- `tools/textlint/` の下とモジュールの変更は `true`。
- `scripts/ci/textlint.sh` の変更は `true`。
- `tools/textlintx/` のように名前が前方で一致するだけのディレクトリは `true`。

### スクリプトと CI

自動のテストを書かない部分は、次のように動かして確かめる。

- 今の `main` に直しを当てた作業ツリーで `sh scripts/ci/textlint.sh` が何も報告せず、終了コード 0 で終わる。
- 違反を含む ADR を追跡しないファイルとして置くと、`adr` のプロファイルが報告し、終了コード 1 で終わる。
- プルリクエストの `docs.yml` の `textlint` のジョブが通り、キャッシュが当たった二回目の実行で `npm ci` が省かれる。

## トレードオフ

- Node と npm のパッケージがリポジトリの開発の道具に加わる。Golem のビルドとテストは Node を使わないので、文書を直す人だけが Node を要る。依存は `package-lock.json` で固定し、Golem の配布物には入らない。
- Golem の規則は行を単位に字面で判定するので、誤検知と見逃しがある。カタカナどうしの中黒は並列か外来語の区切りかを判定できず、見逃す。括弧の中の文は数えないので、括弧の中で二文を続けても報告しない。
- マニュアルには公開のプリセットを当てないので、マニュアルの全角と半角の空白や文体の混在は、今までどおりレビューで守る。
- 文の長さと助詞の重複を止めたので、読みにくい長い文はレビューで見つける必要がある。
- 公開のプリセットの規則は、バージョンを上げると増えたり変わったりする。バージョンを上げるときは、今の文書で検査を走らせ、増えた報告を直すか設定で止めてから入れる。
- CI のジョブが一つ増える。手元の計測では、五つのプロファイルを並行して約 10 秒、テストが約 2 秒である。キャッシュが外れたときは `npm ci` の時間が加わる。

## 参考文献

- textlint：https://github.com/textlint/textlint
- textlint-rule-preset-ja-technical-writing：https://github.com/textlint-ja/textlint-rule-preset-ja-technical-writing
- textlint-rule-preset-ja-spacing：https://github.com/textlint-ja/textlint-rule-spacing
- @textlint-ja/textlint-rule-preset-ai-writing：https://github.com/textlint-ja/textlint-rule-preset-ai-writing
- textlint-rule-prh：https://github.com/textlint-rule/textlint-rule-prh
- prh：https://github.com/prh/prh
- textlint-rule-preset-jtf-style：https://github.com/textlint-ja/textlint-rule-preset-JTF-style
- JTF 日本語標準スタイルガイド（翻訳用）：https://www.jtf.jp/tips/styleguide
