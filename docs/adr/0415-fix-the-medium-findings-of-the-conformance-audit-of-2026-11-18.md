# ADR 0415: 2026-11-18 の監査の、重大度が中の指摘を直す

Status: accepted-pending

## 文脈

2026-11-18 の ADR 違反と予算違反の監査（[docs/audits/2026-11-18-conformance-audit.md](../audits/2026-11-18-conformance-audit.md)）は、重大度が高の指摘を一つ、中の指摘をいくつか挙げた。
tett23 は 2026-11-23 に、高と中のどちらも直すことを決めた。
高の指摘（プルリクエストの CI の時間が予算の 300 秒を超える）は、[ADR 0416](0416-shorten-the-build-of-the-pull-request-ci.md) で扱う。
この ADR は、中の指摘を扱う。

## 調査した事項

`origin/main`（`b540aa68a`）で確かめた。
CI の値は、`gh` で取った実行の記録から数えた。

1. **[ADR 0395](0395-bring-the-pull-request-ci-under-five-minutes.md) の測り直しの記録がない**。
   [ADR 0395](0395-bring-the-pull-request-ci-under-five-minutes.md) の項目 7 と A2 は、実装のマージの後の、成功したプルリクエストの `ci.yml` 20 回の、`scripts/ci/ci-critical-path.sh` の中央値を、`docs/ci-timings/` に記録すると決めた。
   `docs/ci-timings/` の最新は 2026-11-10 の記録で、0395 の後の記録はない。
   実装（PR #1049、2026-11-18T03:09:56Z のマージ）より後に作られた、成功したプルリクエストの実行は 41 回あり、build を省かなかったのは 25 回である。
   その中央値は 389 秒である。
2. **[ADR 0388](0388-widen-the-time-limits-of-tests-on-wasm32.md) の I2 のテストが、どの CI でも動かない**。
   `scripts/ci/test-suites.sh` は、wasm のとき `cabal.project.wasm` のパッケージだけを読む。
   I2 のテストを持つ golem-test-support は、`cabal.project.wasm-tests` にだけある。
   `scripts/ci/test.sh` は、wasm のスイートが `cabal.project.wasm` のパッケージのスイートと等しいことを検査する（[ADR 0293](0293-run-the-test-suites-of-the-packages-of-golem-wasm-on-wasm32-every-night.md) の A1）。
   golem-test-support には、`golem-test-support-test` と、`-threaded` で組む `golem-test-support-par-test` がある。
   後者が wasm32 で組めるかは確かめていない（未確認）。
   `golem-test-support-test` が wasm32 で組めるかも、確かめていない（未確認）。
3. **毎晩の列挙の和の 60 分を、何も判定しない**。
   [ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md) と [ADR 0304](0304-check-the-keep-options-up-to-4-elements-and-draw-5-every-night.md) は、範囲ごとの時間の和を 60 分以下とするが、何回の値をどう判定するかを書いていない。
   予算の一覧は、この予算を「テストと CI の中で強制する上限」の表に置き、「60 分は、ジョブが自分では落ちない」と書く。
   README は中央値で収まったとしている。
   走った直近の 7 回のうち、60 分を超えたのは 2026-11-12 の 1 回（61 分 26 秒）で、11-13 より後はすべて 45 分以下である。
4. **自動で動かないテストがある**。
   - [ADR 0341](0341-revise-retire-listing-src.md) から [ADR 0344](0344-revise-retire-legacy-style-formats.md) の I3 と I4（rc4 の CLI と今の CLI の結果を比べる）は、`experiments/syntax/*-release.mjs` にだけあり、ワークフローもテストのスイートも呼ばない。
     v0.1.0-rc4 のリリースには、`golem-v0.1.0-rc4-x86_64-linux.tar.gz` と `SHA256SUMS` がある。
     CI でこれを取って動かせるかは確かめていない（未確認）。
   - [ADR 0348](0348-revise-emet-expression-repl.md) の端末の振る舞い（R4 の端末の部分と R7）は、`modules/golem-cli/test/repl/terminal.rb` を手で動かすだけである。
     ワークフローに ruby と PTY を使うジョブはない。
5. **[ADR 0345](0345-revise-unitless-zero-in-length-fields.md) の I2 を名前に持つテストがない**。
   置き換えられた [ADR 0319](0319-unitless-zero-in-length-fields.md) の名前のテストが三つ残っている（golem-project のテストの 902 行と 910 行、golem-preflight のテストの 311 行）。
   I2（負の行数と正でない図版の幅を、今までどおり拒む）を確かめるテストは、名前に 0345 を持たずにある（`NaturalSpec.hs` の 98 行、`FileSpec.hs` の 573 行）。
6. **仕様書に、[ADR 0348](0348-revise-emet-expression-repl.md) の REPL の振る舞いがほとんどない**。
   仕様書の REPL の記述は 9 文で、プロンプト、`=> `、終了コード 0 と 2、エラーのバイト範囲、値の表記、要求の集合が空であること（E05101）、E04100 と E04101、BOM と CR と不正な UTF-8 の扱いがない。
   仕様書と README のコマンドの表に、`golem repl emet` の行がない（README には `golem stats` の行もない）。

## 実装すること

1. **測り直しの記録**：`docs/ci-timings/2026-11-23-pull-request-ci-after-adr-0395.md` に、[ADR 0395](0395-bring-the-pull-request-ci-under-five-minutes.md) の項目 7 のとおり、実装の後の直近 20 回の値と中央値を、今までの記録と同じ形（条件、実行ごとの秒、まとめ、読み方）で書く。
   中央値が 300 秒を超えるので、[ADR 0395](0395-bring-the-pull-request-ci-under-five-minutes.md) の項目 8 により、[ADR 0416](0416-shorten-the-build-of-the-pull-request-ci.md) でコンパイルの時間を縮める。
2. **wasm32 の時間の上限のテスト**：毎晩の wasm のテストに、`golem-test-support:test:golem-test-support-test` を足す。
   `scripts/ci/test-suites.sh` の wasm の一覧に、このスイートだけを足す。
   `-threaded` の `golem-test-support-par-test` は足さない。
   `scripts/ci/test.sh` の [ADR 0293](0293-run-the-test-suites-of-the-packages-of-golem-wasm-on-wasm32-every-night.md) の A1 の検査を、「`cabal.project.wasm` のパッケージのスイートと、この一つのスイート」に直す。
3. **毎晩の列挙の 60 分**：毎回の実行の和で判定する。
   範囲ごとの時間を量る段とテストの段は、それぞれの始めと終わりの時刻（`date +%s`）を `$RUNNER_TEMP` のファイルに書き残す。
   毎晩のジョブの最後に判定の段を置き、書き残した時刻から和を数え、60 分を超えたらジョブを失敗にする。
   判定の段は、テストの段と同じく `if: ${{ !cancelled() }}` で動かす。
   GitHub の API は使わない（`actions: read` の権限を足さないため）。
   予算の一覧の「強制するもの」の欄に、この段を書き、「60 分は、ジョブが自分では落ちない」の注記を消す。
   README の「中央値で収まった」の文を、毎回の和で判定することに直す。
4. **rc4 と比べるテスト**：毎晩のワークフローに、rc4 の x86-64 の Linux の配布物を `gh release download` で取り、`SHA256SUMS` と、ワークフローに固定した SHA-256 の両方で照合してから、`experiments/syntax/*-release.mjs` を動かす段を足す。
   比べるのは、rc4 と、そのコミットの `golem` である。
   比べるのは [ADR 0341](0341-revise-retire-listing-src.md)〜0343 の I3 と I4、[ADR 0344](0344-revise-retire-legacy-style-formats.md) の I3〜I5 の rc4 の側である。
   テストの名前を `root ADR NNNN I3, I4: ...` の形にそろえる。
   v1.0.0 のリリースの後は、この段を消してよい（rc4 との比較は、廃止の移行の確認のためのものである）。
5. **端末のテスト**：毎晩のワークフローに、Linux のランナーで `terminal.rb` を動かす段を足す。
   ruby は、ランナーにあるものを使い、無ければ段を失敗にする（黙って飛ばさない）。
   `terminal.rb` は一本のスクリプトなので、段の名前と失敗のメッセージを `root ADR 0348 I4, I7: ...` とする。
6. **0345 の名前**：[ADR 0319](0319-unitless-zero-in-length-fields.md) の名前の三つのテストを、[ADR 0345](0345-revise-unitless-zero-in-length-fields.md) の対応する番号の名前に付け直す。
   I2 を確かめる二つのテストの名前に、`root ADR 0345 I2: ` を付ける。
7. **REPL の仕様**：仕様書の「関数の言語 Emet」の REPL の記述に、調査した事項の 6 に挙げた振る舞いを、[ADR 0348](0348-revise-emet-expression-repl.md) から書き写す。
   仕様書と README のコマンドの表に、`golem repl emet` の行を足す。
   README の表に `golem stats` の行も足す。
8. **ロードマップとステータスの行**：ロードマップの「プルリクエストの CI の時間を測り直す」の項目を、1 の記録を書いた変更で消す。
   採択したら、[ADR 0293](0293-run-the-test-suites-of-the-packages-of-golem-wasm-on-wasm32-every-night.md)（A1 の検査の中身）、[ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md) と [ADR 0304](0304-check-the-keep-options-up-to-4-elements-and-draw-5-every-night.md)（60 分の判定のしかた）のステータスの行に、この ADR による補足を足す。

## 実装しないこと

- 重大度が低の指摘は、この ADR では直さない。
- 毎晩の列挙の範囲や深さは変えない。
- rc4 と比べるテストと端末のテストを、プルリクエストの CI には入れない。
  プルリクエストの CI の時間を延ばさないためである。

## 不変条件

- I1：wasm の `test-suites.sh` が返すスイートの集合は、`cabal.project.wasm` のパッケージのスイートと `golem-test-support-test` の和に等しい。
- I2：毎晩の列挙のジョブで、範囲ごとの時間の和が 60 分を超える実行は、失敗で終わる。
  60 分以下の実行は、この判定では失敗しない。
- I3：名前に `ADR 0319` を含むテストは、リポジトリに一つもない。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| 今の `cabal.project.wasm` | 今のスイートと `golem-test-support-test` | I1 |
| 和が 59 分 59 秒 | 失敗しない | I2 |
| 和がちょうど 60 分 | 失敗しない | I2 |
| 和が 60 分 1 秒 | 失敗 | I2 |
| 全段を省いた実行（main が変わらない） | 和は 0 で、失敗しない | I2 |

## 受けいれ条件

なし。
この ADR の振る舞いは、不変条件のテストで確かめる。

## テスト設計

- 名前は `root ADR 0415 I<番号>: ...` とする。
- I1 は、`scripts/ci/test.sh` の検査を直し、直す前に今の一覧で失敗することを確かめる。
- I2 は、和を判定するスクリプトを `scripts/ci/` に置き、`scripts/ci/test.sh` で境界の表の入力（段の秒の一覧）を渡して確かめる。
- I3 は、`git grep` で確かめる検査を `scripts/ci/test.sh` に足す。
- 実装の 4 と 5 は、ワークフローを `workflow_dispatch` で一度動かし、rc4 との比較と端末のテストが通ることを確かめて、実装のプルリクエストに実行の URL を書く。
  rc4 の配布物がランナーで動かないときは、そのことを報告し、この ADR の 4 を直す ADR を書く。
- 実装の 1、6、7 は、文書と名前の変更であり、`sh scripts/ci/textlint.sh origin/main` と `adr-guard links` が通ることで確かめる。

## トレードオフ

毎晩の列挙を毎回の和で判定すると、ランナーの速さの揺れで失敗することがある。
直近の和は 45 分以下で、15 分の余裕があるので、揺れで失敗することはまれと見込む。
失敗したら、揺れか遅くなったのかを調べる。

rc4 と比べるテストは、v1.0.0 の後には要らなくなる。
それまでのあいだ、毎晩の時間が少し延びる。

## 参考文献

- [docs/audits/2026-11-18-conformance-audit.md](../audits/2026-11-18-conformance-audit.md)
- [ADR 0395](0395-bring-the-pull-request-ci-under-five-minutes.md)
- [ADR 0388](0388-widen-the-time-limits-of-tests-on-wasm32.md)
- [ADR 0293](0293-run-the-test-suites-of-the-packages-of-golem-wasm-on-wasm32-every-night.md)
- [ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md)
- [ADR 0304](0304-check-the-keep-options-up-to-4-elements-and-draw-5-every-night.md)
- [ADR 0341](0341-revise-retire-listing-src.md)
- [ADR 0344](0344-revise-retire-legacy-style-formats.md)
- [ADR 0345](0345-revise-unitless-zero-in-length-fields.md)
- [ADR 0319](0319-unitless-zero-in-length-fields.md)
- [ADR 0348](0348-revise-emet-expression-repl.md)
- [ADR 0416](0416-shorten-the-build-of-the-pull-request-ci.md)
