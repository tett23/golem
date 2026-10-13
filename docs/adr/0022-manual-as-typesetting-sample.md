# ADR 0022: 組版のサンプルを兼ねるマニュアル

ステータス: 採択

## 文脈

Golem には、使い手のためのマニュアルがない。
記法は docs/markup.md に、設定と挙動は docs/specifications.md と各モジュールの仕様書に、決定の経緯は ADR に散らばっている。
これらは開発者が仕様を確かめるための文書であり、「プロジェクトを作って一冊の本を組む」順には並んでいない。
しかも、まだ実装していない採択の ADR や、v2 以降に回した事項も同じ文書に混ざっている。

Golem で組んだ実物のサンプルも、リポジトリにない。
テストのフィクスチャ（`modules/golem-driver/test/fixtures/sample` など）は機能を一つずつ確かめる小さな原稿であり、本の体裁をしていない。
決定性の検査（`scripts/determinism.sh`）が組むのもこのフィクスチャである。

マニュアルを Golem 自身で組めば、この二つが一度に埋まる。
Golem のマニュアルを読む人は、手元の PDF が Golem の出力そのものであることから、組版の品質を確かめられる。
開発の側から見ると、一冊の本の分量の原稿を毎回組むことが、テストのフィクスチャより現実に近い回帰の検査になる。

ただし、マニュアルは仕様が変わるたびに古くなる。
ADR を採択して実装するたびに、マニュアルも同じプルリクエストで直す決まりと、それを忘れたときに気づく仕組みが要る。

## 実装すること

### 二つの原稿

マニュアルの原稿を二つ置く。

- **docs/manual.md**：マニュアルの本文の元のテキスト。Markdown で書く。GitHub の上でそのまま読め、差分のレビューもしやすい。マニュアルの内容はこちらを正とする。
- **manual/**：docs/manual.md を Golem の記法に書き直した Golem のプロジェクト。`manifest.toml`、`style.toml`、章ごとの `.gm` のファイルを置く。

docs/manual.md から manual/ への変換は、手で行う。
変換のスクリプトは作らない（「実装しないこと」）。
Golem の記法は Markdown にない機能（ルビ、圏点、傍注、段落スタイル、相互参照）を持ち、サンプルとしてはそれらを使いたいからである。
docs/manual.md では、そうした機能を Markdown で書ける範囲で表す（ルビは `親文字（よみ）` とする、など）。

二つの原稿のずれは、見出しで検出する。
`scripts/manual/check-headings.sh` は、docs/manual.md の見出し（`#` から `###` まで）と、manual/ の各 `.gm` の見出しを、ファイルの並び（`manifest.toml` の章の順）のとおりにつなげて比べる。
見出しの階層と文字列が一つでも違えば、違う最初の見出しを挙げて失敗する。
見出しの文字列は、Golem の記法（ルビやインラインのコマンド）を外したテキストで比べる。

### 内容の範囲

マニュアルに書くのは、確定していて、しかも実装済みの仕様だけとする。

- 採択した ADR のうち、実装を終えたもの。docs/specifications.md の「今後の実装項目」に残っている事項と、「v2 以降に回した事項」「v3 以降に回した事項」は書かない。
- 提案の ADR と、未決事項は書かない。
- 書くのは使い手から見える振る舞い（インストール、`golem new`、記法、`manifest.toml` と `style.toml`、`golem build` と `golem check`、診断、LSP、プラグイン）である。

### 読み手と書き方

マニュアルの読み手は、Golem で本を作る人（著者、編集者、組版の担当者）であり、Golem を開発する人ではない。
docs/ の下のほかの文書とは読み手が違うので、書き方も変える。

- やりたいこと（「本文の字下げを変える」「章ごとにファイルを分ける」）から引ける構成にし、各節は手順と例を先に、規則の細部を後に置く。
- ADR の番号、モジュールの名前（golem-layout など）、意味論 IR、評価の段階（S0、S1、S2）、内部の型の名前を本文に出さない。決めた理由を書くときも、使い手にとっての理由（「縦組みの本で読みやすくするため」）にとどめ、実装の都合は書かない。
- 用語は、組版の慣用の語（版面、字下げ、行送り、ノンブル、柱）と、`style.toml` のキーの名前を使う。docs/glossary.md の開発の用語のうち、使い手が設定や診断で目にしない語は使わない。
- 診断は、コードとメッセージ、直し方を使い手の言葉で書く。診断を出す処理の段階やモジュールは書かない。
- 例は、そのままコピーして `golem new` で作ったプロジェクトに貼れば動くものにする。
- 文体は敬体（です、ます）とする。docs/ の下のほかの文書は常体（である）で書いているが、マニュアルは使い手に向けた案内なので、読み手に語りかける敬体を使う。一文ごとに改行する、ダッシュと並列の中黒を使わない、といったリポジトリの文章の決まりは、マニュアルにも同じく当てはめる。

docs/manual.md と manual/ の両方に、この書き方を適用する。
レビューでは、上の語が本文に出ていないかを確かめる。

マニュアルは、マニュアル自身が使う機能を説明する。
たとえばルビの節ではルビを、傍注の節では傍注を、表の節では表を、その節の中で実際に組んで見せる。
ここで使う機能はどれも実装済みなので、manual/ を組めること自体が、書いた内容が今の Golem で動く証拠になる。

章立ては次のとおりとする。
実装のときに分量を見て節を分けてよいが、章の順は変えない。

1. はじめに（Golem とは何か、このマニュアル自体が Golem で組まれていること）
2. インストールと最初の一冊（配布物、`golem new`、`golem build`）
3. 原稿の記法（docs/markup.md の実装済みの範囲）
4. プロジェクトの設定（`manifest.toml`）
5. スタイルの設定（`style.toml`）
6. 出力（PDF、HTML、EPUB、プレーンテキスト、トンボと塗り足し、決定性）
7. 検査と診断（`golem check`、`golem fmt`、lint、診断の読み方）
8. エディタと LSP
9. プラグイン

### 体裁

- 言語は日本語とする。欧文の版は作らない（「実装しないこと」）。
- 横組みとする。
- PDF は A5 の判型とする。
- 出力は PDF と HTML の二つとし、`manifest.toml` の出力のターゲットにこの二つだけを書く。EPUB とプレーンテキストは組まない。
- 版面は、本文 13Q、行送り 22H、一行 35 字、一ページ 29 行を出発点とする。実装のときに組み見て変えてよく、変えた値は `style.toml` のコメントに理由とともに書く。
- 書体は、本文を Noto Serif JP（和文）と Source Serif 4（欧文）、見出しを Noto Sans JP の Bold（和文）と Source Sans 3 の Bold（欧文）とする。どれも SIL Open Font License 1.1 である。

### フォントの取得

フォントはリポジトリにコミットしない。
`scripts/manual/fetch-fonts.sh` が、上流の版を固定した URL から取得し、SHA-256 を検査して `manual/fonts/` に置く。
書き方は `scripts/fetch-wasmtime.sh` と `golem new` のフォントの取得（[golem-cli ADR 0003](../golem-cli/adr/0003-new-project-page-and-fonts.md)）に合わせ、取得するファイルにはライセンスの文書も含める。
`manual/fonts/` は `.gitignore` に加える。

### 組み方

`scripts/manual/build.sh` を置く。
フォントを取得し（すでにあれば検査だけ）、`golem build --target pdf --target html` で manual/ を組む。
`GOLEM` の環境変数で使う `golem` を選べる（`scripts/determinism.sh` と同じ）。
出力は manual/build/ に入り、`.gitignore` に加える。

### CI

`ci.yml` の `build` ジョブ（x86-64 と aarch64 の両方）で、テストの後に次を行う。

1. `scripts/manual/check-headings.sh` で、二つの原稿の見出しが一致することを確かめる。
2. `scripts/manual/build.sh` で、manual/ を組む。診断が一つでも出れば失敗とする（`golem build` の終了コードと、警告の有無の両方で判定する）。
3. 組んだ PDF と HTML のハッシュを、決定性の検査の一覧（`scripts/determinism.sh` の出力）に加える。これで、マニュアルも x86-64 と aarch64 で同じバイト列になることを `determinism` ジョブが確かめる。
4. x86-64 のジョブだけ、組んだ PDF と HTML を成果物（`manual`）としてアップロードする。

フォントは `actions/cache@v6` でキャッシュする。
鍵は `scripts/manual/fetch-fonts.sh` のハッシュとする。

`scripts/ci/needs-build.sh` の判定では、docs/manual.md を「ビルドが読む文書」の一覧に加える（[docs/adr/0021](0021-docs-workflow-and-ci-gate.md)）。
docs/manual.md だけを変えたプルリクエストでも、見出しの照合とマニュアルの組版が走る。
manual/ は docs/ の外にあるので、今の判定のままビルドする側になる。

### 仕様の変更とマニュアルの更新

ADR を実装して使い手から見える振る舞いが変わるプルリクエストでは、同じプルリクエストで docs/manual.md と manual/ も直す。
CONTRIBUTING.md と CONTRIBUTING.en.md の「ドキュメント」の節に、この決まりを書く。

更新の漏れは、Git のフックと CI の両方で、同じスクリプトを使って止める。

- `scripts/manual/check-updated.sh` を置く。

  ```
  check-updated.sh BASE HEAD
  ```

  `BASE...HEAD`（分岐点から `HEAD` まで）の変更のパスと、そのあいだのコミットのメッセージを読む。
  docs/markup.md か docs/specifications.md を変えているのに docs/manual.md を変えていなければ、終了コード 1 で失敗し、どのファイルを変えたかと、直し方を標準エラー出力に書く。
- ただし、範囲のコミットのどれかのメッセージに、`Manual: unchanged` というトレーラーの行があれば通す。v2 以降の課題の追加のように、仕様書を変えても実装済みの振る舞いが変わらない変更があるからである。迂回の印をコミットに置くことで、フックと CI が同じ情報で判定でき、迂回したこともリポジトリの履歴に残る。
- **Git のフック**：`.githooks/pre-push` を加え、push するブランチについて、`origin/main` との分岐点から push する先端までを `check-updated.sh` で検査する。`main` への push と、ブランチの削除は検査しない。フックは `git config core.hooksPath .githooks`（README と CONTRIBUTING の手順のとおり）で有効になる。
- **CI**：`docs.yml` に `manual` ジョブを置き、プルリクエストのときに `check-updated.sh "$PR_BASE" "$PR_HEAD"` を走らせる。`main` への push では、ジョブを skip する。
- **必須の検査**：実装をマージしたあと、`main` のルールセットの必須の検査に `manual` を加え、`ci`、`adr`、`manual` の三つにする。変える前と後の一覧は、[docs/adr/0021](0021-docs-workflow-and-ci-gate.md) と同じく、実装のプルリクエストのコメントに残す。フックは手元で早く気づくためのもので、守る役は必須の検査が担う。フックは `--no-verify` で飛ばせるが、必須の検査は飛ばせないからである。

### 配布

v0.1.0-rc1 の次のリリースから、リリースのワークフロー（`release.yml`）は、manual/ を組んだ PDF と HTML をリリースの資産に加える。

- `golem-manual-<タグ>.pdf`
- `golem-manual-<タグ>-html.tar.gz`（HTML とその画像やスタイルシートをまとめたもの）

SHA256SUMS にも二つのハッシュを加える。
組むのに使う `golem` は、そのリリースの x86-64 の Linux の配布物とする。
リリースの配布物でマニュアルが組めることが、配布物の検査の一つにもなる。

### ドキュメント

- README の冒頭近くに、マニュアル（docs/manual.md と、リリースの資産の PDF と HTML）への案内を書く。
- README の開発の節に、`scripts/manual/build.sh` でマニュアルを組めることと、フォントを取得することを書く。
- docs/specifications.md に「マニュアル」の節を設け、二つの原稿の関係、内容の範囲、更新の決まりを書く。

## 実装しないこと

- docs/manual.md から manual/ への自動の変換。Golem の記法の機能をサンプルとして使うには、手で書き直すほうがよい。見出しの照合で大きなずれは検出できる。
- 欧文の版と、縦組みの版。組版のサンプルとしては縦組みの版も価値があるが、今回の要求は横組みだけである。
- EPUB とプレーンテキストの出力。
- GitHub Pages での HTML の公開。リリースの資産で足りる。必要になったら別の ADR で決める。
- 本文の段落の単位での二つの原稿の照合。見出しの照合だけにとどめる。
- 実装していない機能の説明。実装したときに、その ADR のプルリクエストで足す。

## テスト設計

### 先に書いて失敗させるテスト（`scripts/manual/test.sh`）

`check-headings.sh` について、一時ディレクトリに小さな docs/manual.md と manual/ を作って確かめる。

- 見出しが同じ順に同じ階層で並ぶとき、終了コード 0。
- manual/ の章の一つで見出しの文字列が違うとき、終了コード 1 で、違う見出しの両方の文字列が標準エラー出力に出る。
- 見出しの階層が違う（`##` と `###`）とき、終了コード 1。
- manual/ の見出しにルビ（`[ruby: 組版|くみはん]` の形）や強調があっても、外したテキストが同じなら終了コード 0。
- `manifest.toml` の章の順と、ファイル名の順が違うとき、章の順でつなげて比べること。
- docs/manual.md のコードブロックの中の `#` で始まる行を、見出しとして数えないこと。

`check-updated.sh` について、一時ディレクトリに git のリポジトリを作り、`main` から切ったブランチにコミットを積んで確かめる。

- ブランチで `docs/markup.md` を変え、`docs/manual.md` を変えていないとき、終了コード 1 で、標準エラー出力に `docs/markup.md` が出る。
- `docs/markup.md` と `docs/manual.md` を別々のコミットで変えたとき、終了コード 0。
- `docs/specifications.md` を変え、範囲のコミットのどれかのメッセージに `Manual: unchanged` のトレーラーがあるとき、終了コード 0。
- `Manual: unchanged` が本文の途中（トレーラーでない位置）にあるだけのとき、終了コード 1。
- `modules/` の下だけを変えたとき、終了コード 0。
- ブランチを切ったあとに `main` で `docs/markup.md` が変わっても、ブランチの変更に数えないこと（分岐点からの差分であること）。

`.githooks/pre-push` について、同じ一時リポジトリで、フックに pre-push の標準入力（`<local ref> <local sha> <remote ref> <remote sha>`）を渡して確かめる。

- 漏れのあるブランチの push で、終了コード 1。
- `main` への push と、ブランチの削除（local sha が `0` だけ）では、終了コード 0。

`fetch-fonts.sh` について、SHA-256 が合わないファイルを置いた状態で実行すると、そのファイルを消して失敗することを確かめる。
取得そのものはネットワークを使うので、`scripts/manual/test.sh` では行わない。

`scripts/ci/test.sh` の `needs-build.sh` の表に、`docs/manual.md` だけの変更で `true` を出すことを加える。

### 自動テストにできないものの確かめ方

- manual/ を組んだ PDF を開き、A5 の横組みで、本文と見出しの書体が上の指定どおりであることを目で確かめる。各章で、その章が説明する機能が実際に組まれていることも確かめる。
- HTML をブラウザで開き、同じく確かめる。
- CI の `determinism` ジョブで、マニュアルのハッシュが x86-64 と aarch64 で一致することを確かめる。
- 最初のリリースで、資産にマニュアルの PDF と HTML が載り、SHA256SUMS のハッシュと一致することを確かめる。

確かめた結果は、実装のプルリクエストのコメントに書く。

## トレードオフ

- 原稿を二つ持つので、書き直しの手間と、ずれの危険が増える。docs/manual.md だけにすれば手間は減るが、Golem で組んだサンプルにならない。manual/ だけにすれば、GitHub の上で読めず、差分のレビューも Golem の記法を読める人に限られる。見出しの照合で大きなずれを捕まえ、細かい表現のずれはレビューで直す。
- CI の `build` ジョブが、フォントの取得（初回だけ）とマニュアルの組版の分だけ長くなる。組版は本一冊の分量で、手元の計測では数秒から十数秒の見込みである。実装の後に `docs/ci-timings/` に記録する。
- docs/manual.md を「ビルドが読む文書」に入れるので、docs/manual.md だけの変更でもビルドが走る。マニュアルの文章の修正で組版が崩れないことを確かめるには、ビルドが要る。
- 更新の漏れの検査は、仕様書を変えたかどうかで判定するので、粗い。仕様書を変えずにコードだけで振る舞いが変わる変更は捕まえられない。この場合はレビューで気づくしかない。
- `Manual: unchanged` のトレーラーで迂回できるので、必須の検査にしても漏れを完全には防げない。迂回の判断は書いた人に任せ、トレーラーが履歴に残ることで、レビューで迂回の妥当さを確かめられるようにする。
- pre-push のフックは `origin/main` を基準にするので、手元の `origin/main` が古いと、すでに `main` に入った変更を自分の変更と見なすことがある。フックは検査の前に `git fetch origin main` をしない（push のたびに通信を増やさない）。誤って止まったときは、`git fetch` をしてから push し直す。

## 参考文献

- Noto CJK（Noto Serif JP、Noto Sans JP）. https://github.com/notofonts/noto-cjk
- Source Serif 4. https://github.com/adobe-fonts/source-serif
- Source Sans 3. https://github.com/adobe-fonts/source-sans
- SIL Open Font License 1.1. https://openfontlicense.org/
