# ADR 0154: `scripts-macos` の六本のテストを同時に走らせ、期限を過ぎたテストを止めて出力を残す

ステータス: 採択（未実装）

## 文脈

`ci.yml` の `scripts-macos` ジョブは、macOS 15 のランナーで、`PATH` をシステムの道具だけにして、`scripts/` の下の六本のテストを走らせる（[docs/adr/0079](0079-shell-tests-on-macos.md)、[docs/adr/0095](0095-visual-job-in-ci.md)）。
2026-11-04 まで、六本は六つの手順で一本ずつ走った。

PR [#522](https://github.com/tett23/golem/pull/522)（マージのコミット a023cbe3）は、六本を同時に走らせるように変えた。
[ADR 0140](0140-ci-split-test-runners-and-visual-pdfs-first.md) の後、`build` のランナーは実行の始まりから 150 秒から 175 秒で終わり、`scripts-macos` は 109 秒から 167 秒で終わっていた（2026-11-04 の 12 回の実行）。
`scripts-macos` が `ci` の前の最後のジョブになりかけていた。

### 今の作り

- `scripts/ci/run-all.sh SCRIPT...` は、各スクリプトを `sh SCRIPT </dev/null` で背景に走らせ、標準出力と標準エラー出力を `mktemp -d` の作業ディレクトリのファイルに書く（[run-all.sh#L15-L26](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/scripts/ci/run-all.sh#L15-L26)）。
- `wait` ですべての終わりを待ってから、引数の順に `==> SCRIPT: exit CODE, SECONDS s` の行と出力を書く。失敗したスクリプトごとに標準エラー出力に一行を書き、終了コードを 1 とする。引数がなければ 2 である（[同#L27-L40](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/scripts/ci/run-all.sh#L27-L40)）。
- `scripts-macos` は、同じ六本をこのスクリプトで一つの手順として走らせる（[ci.yml#L569-L584](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/.github/workflows/ci.yml#L569-L584)）。ジョブの `timeout-minutes` は 15 である。
- `scripts/ci/test.sh` に、出力の順、見出しの行、同時に走ること、失敗の報告、標準入力を渡さないこと、使い方、`scripts-macos` の手順の七つの検査がある。

PR #522 の実行 41831996929 で、`scripts-macos` は 78 秒で終わった。

### ADR がなかったこと

PR #522 は、ランナー、`PATH`、テストが同じで検査が変わらないので ADR は要らないとした。
同じ日の [ADR 0140](0140-ci-split-test-runners-and-visual-pdfs-first.md)（ランナーの分割）と [ADR 0141](0141-smaller-ghc-and-hackage-index-caches.md)（キャッシュの中身）は、検査を変えない CI だけの変更に ADR を書いた。
#522 だけが例外である。
2026-11-04 の二度めの監査（[PR #525](https://github.com/tett23/golem/pull/525) の docs/audits/2026-11-04-rc4-followup-conformance.md の F-26）は、新しいスクリプトの仕様とトレードオフがどこにも記録されていないとした。
この ADR は、その決定を後から記録する。

### 記録されていないトレードオフ

一本ずつ走らせていたとき、各手順の出力は、走っているあいだにログに流れた。
一本がハングしても、どの手順が止まったか、そこまでに何を書いたかは、ログに残った。

今の作りでは、出力は作業ディレクトリのファイルにだけあり、六本すべてが終わるまで書かれない。
一本がハングすると、ジョブは 15 分の時間切れで止められ、どのテストの出力もログに残らない。
ランナーは捨てられるので、作業ディレクトリも残らない。
どのテストがハングしたかも分からない。

ハングはまだ起きていない。
しかし、起きたときの代価は大きい。
15 分を待った後に、調べる手がかりがない。
不安定なテストは調べて直す、というプロジェクトの方針にとって、手がかりのない失敗は直せない失敗である。

逆に、良くなった点もある。
一本ずつのときは、最初に失敗した手順の後の手順は飛ばされた。
今は六本すべてが走り、すべての失敗を一度に報告する。

### 期限の置き方

macOS 15 の `/usr/bin` には `timeout` がない（manual-dev の CI の章は、`timeout` を使う検査を `scripts-macos` で飛ばすと書く）。
期限は、POSIX の `sh`、`sleep`、`kill` だけで作る必要がある。

## 実装すること

### 後から記録する決定

- `scripts-macos` の六本を、`scripts/ci/run-all.sh` で同時に走らせる。PR #522 の作りを保つ。
- `scripts-linux` は変えない。`ci` の前の最後のジョブになっていないためである。

### 期限

`run-all.sh` に、期限のオプションを足す。

```
run-all.sh [-t SECONDS] SCRIPT...
```

- `-t` がなければ、今と同じく、すべての終わりを待つ。
- `-t SECONDS` があれば、始めてから `SECONDS` 秒たっても終わっていないスクリプトを `kill` で止める。止めたスクリプトの見出しの行は `==> SCRIPT: timed out after SECONDS s` とし、その後に、そこまでに書いた出力を書く。標準エラー出力には `run-all: SCRIPT timed out (SECONDS s)` の一行を書き、終了コードを 1 とする。
- 期限の内に終わったスクリプトの見出しの行と出力は、今と同じである。順は引数の順のままである。
- `SECONDS` が正の整数でなければ、使い方の誤りとして終了コード 2 とする。
- 止めるのは、`run-all.sh` が起動した `sh SCRIPT` のプロセスである。その子のプロセスは残ることがあるが、標準出力と標準エラー出力はファイルに向いているので、`run-all.sh` の出力を塞がない。期限を見張る背景のプロセスも、`run-all.sh` の標準出力と標準エラー出力を持たないようにする。残ったプロセスは、ジョブの終わりにランナーが片づける。
- POSIX の `sh` と、macOS と Linux の両方にある道具だけを使う（[docs/adr/0079](0079-shell-tests-on-macos.md)）。

`scripts-macos` は `-t 600` を渡す。

- 今の 78 秒、一本ずつのときの 95 秒から 130 秒に対し、十分に大きい。
- ジョブの 15 分の時間切れより 5 分早いので、止めた後に出力を書く時間が残る。

### 文書

- 開発者のマニュアルの CI の章（`manual-dev/part2/11-ci-jobs.gm` の `scripts-macos` の段落）に、六本を同時に走らせ、すべてが終わってから引数の順に出力を書くこと、600 秒の期限を過ぎたテストを止めて、そこまでの出力を書くことを足し、この ADR の注を置く。
- README の CI の表の `scripts-macos` の行に、同時に走らせることを足す。
- `run-all.sh` の冒頭のコメントに、`-t` を書く。

## 実装しないこと

- **一本ずつに戻すこと。** `scripts-macos` が再び `ci` の前の最後のジョブになる。
- **六本の出力を、名前を前に付けて流すこと。** 走っているあいだに出力が見えるが、六本の行が交ざり、一本のテストの出力を続けて読めなくなる。
- **手順の `timeout-minutes` と、`if: failure()` で作業ディレクトリを書く手順の組。** 作業ディレクトリを決まった場所に置く必要があり、二つの手順と `run-all.sh` が結びつく。手順の時間切れのときの後の手順の振る舞いにも頼る。
- **作業ディレクトリを成果物として上げること。** 失敗のたびに成果物を取りにいく手間が増え、ログで足りる情報である。
- **六本の中の個々の検査に期限を置くこと。** どの検査がハングしうるかは分からず、六本の単位で止めれば、どのテストのどこまでが動いたかは出力から分かる。
- **`scripts-linux` に `run-all.sh` を使うこと。**

## テスト設計

### 先に書いて失敗させるテスト（`scripts/ci/test.sh`）

`run-all.sh` の今の七つの検査の後に、次を足す。
今の `run-all.sh` は `-t` を知らないので、どれも失敗する。

- 「`before` を書いてから `sleep 30` する」偽のスクリプトと、すぐに終わる偽のスクリプトを `run-all.sh -t 2` に渡すと、10 秒以内に終わり、終了コードが 1 で、標準出力に `==> <偽のスクリプト>: timed out after 2 s` の行とその次の `before` の行があり、すぐに終わるスクリプトの見出しは `exit 0` であること。`run-all.sh` の標準出力は `| cat` のパイプで受ける。背景のプロセスが出力を持ったままなら、パイプが閉じずに 30 秒かかり、時間の検査で落ちる。
- 同じ実行の標準エラー出力が、`run-all: <偽のスクリプト> timed out (2 s)` の一行だけであること。
- `run-all.sh -t 0 a.sh` と `run-all.sh -t x a.sh` が終了コード 2 で終わること。
- `ci.yml` の `scripts-macos` の手順が `sh scripts/ci/run-all.sh -t 600` で始まり、`600` がジョブの `timeout-minutes` の秒数より小さいこと。今の手順の字面の検査は、この形に改める。

`-t` のない今の七つの検査は、変えずに通ること。
`scripts/ci/test.sh` は `scripts-linux`（GNU の道具）と `scripts-macos`（BSD の道具）の両方で走るので、二つの環境で確かめられる。

### 自動テストにできないものの確かめ方

- 実装のプルリクエストの `scripts-macos` の時間が、今の 78 秒前後から変わらないこと。期限を見張るプロセスが、テストの時間を延ばさないことを確かめる。
- 下書きのコミットで、六本の一本に `sleep 900` を足し、`scripts-macos` が 600 秒の後に止めたテストの見出しと出力をログに書いて失敗することを確かめる。確かめた後、そのコミットは戻す。

## トレードオフ

- 期限の 600 秒より長くかかる正しいテストも止める。今の六本の最も長いものは 78 秒の実行の中に収まっており、余裕は 7 倍以上ある。テストが育って期限に近づいたら、値を上げる。
- 止めたスクリプトの子のプロセスは、ジョブの終わりまで残りうる。出力を塞がないようにするので、`run-all.sh` の終わりは遅れない。
- 期限を置いても、出力が見えるのは、すべてが終わるか止められた後である。走っているあいだの進み具合はログに出ない。
- 六本が三つのコアを分け合うので、時間に頼る検査があれば、一本ずつのときより不安定になりうる。今の六本にそのような検査は見つかっていない。
- `run-all.sh` の作りが少し大きくなる（今の 40 行に、期限の見張りと止める処理が加わる）。

## 決めたことの記録

- **採択**：メンテナーが採択した（2026-11-04）。この ADR が決めてほしい点として挙げた項目は、どれも ADR の推奨のとおりとする。

## 参考文献

- [PR #525](https://github.com/tett23/golem/pull/525) の docs/audits/2026-11-04-rc4-followup-conformance.md（F-26）
- PR [#522](https://github.com/tett23/golem/pull/522)（マージのコミット a023cbe3）
- [scripts/ci/run-all.sh](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/scripts/ci/run-all.sh)、[ci.yml の `scripts-macos`](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/.github/workflows/ci.yml#L569-L584)
- [ci.yml の PR #522 の前の `scripts-macos`](https://github.com/tett23/golem/blob/371b94b88f10a7d7cf8dc66a63c5e89bea64917c/.github/workflows/ci.yml#L569-L591)（一本ずつの六つの手順）
- [docs/adr/0079](0079-shell-tests-on-macos.md)、[docs/adr/0095](0095-visual-job-in-ci.md)、[docs/adr/0140](0140-ci-split-test-runners-and-visual-pdfs-first.md)、[docs/adr/0141](0141-smaller-ghc-and-hackage-index-caches.md)
