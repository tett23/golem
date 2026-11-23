# ADR 0427: warning の検査で、ログの無いジョブと、変更と関係の無いキャッシュの知らせを扱う

Status: proposed

## 文脈

CI の `ci` ジョブは、同じ実行のほかのジョブのログを読み、許可の一覧にない warning があれば失敗する（[root ADR 0245](0245-keep-the-warnings-of-ci-at-zero.md)）。
main の保護は `ci` を求めるので、`ci` が失敗すると、プルリクエストをマージできない。

2026-11-22 から 2026-11-23 にかけて、この検査の step が 10 回失敗し、その後の main の実行でも 1 回失敗した。
原因は四つに分かれ、どれもプルリクエストの変更とは関係が無かった。

- 8 回は、ジョブのログを取る API が 404 を返し、検査のループがそこで止まった。
  これらの実行は、取り消されたジョブのために、`ci` の前の step でもう失敗していたので、マージを止めたのはこの 404 ではない。
  害は、ループが止まり、残りのジョブのログを読まずに終わったことである。
- 1 回は、actions/cache がキャッシュの復元に失敗したことを知らせる warning で、マージを止めた。
- 1 回は、wasm のジョブが出した、キャッシュが追い出されたことを知らせる warning で、マージを止めた。
- main の 1 回は、ランナーが action を取りに行ってタイムアウトし、取り直したことを知らせる warning だった。

この ADR は、四つのそれぞれについて、検査がどう扱うかを決める。

## 調査した事項

origin/main（[00da89db1](https://github.com/tett23/golem/commit/00da89db13a46a2be441c0e9235a1ff46236710a)）で、次のことを確かめた。

- 検査の step は、同じ実行の試行のジョブの一覧を取り、`status` が `completed` で `conclusion` が `skipped` でないジョブに絞る。
  そのジョブごとに `curl -fsSL --retry 5 --retry-all-errors` でログを取り、`log-warnings.sh` に渡す（[ci.yml#L1481-L1497](https://github.com/tett23/golem/blob/00da89db13a46a2be441c0e9235a1ff46236710a/.github/workflows/ci.yml#L1481-L1497)）。
  step は既定の `bash -e` で動くので、curl が一つ失敗すると、ループがそこで止まる。
  `ci` 自身は、まだ `completed` でないので、この絞り込みで外れる。
- `log-warnings.sh` は、行頭が `##[warning]` の行を warning と数え、出どころを区別しない。
  `##[notice]` の行は数えない（[log-warnings.sh#L70-L80](https://github.com/tett23/golem/blob/00da89db13a46a2be441c0e9235a1ff46236710a/scripts/ci/log-warnings.sh#L70-L80)）。
- ログの無いジョブの扱いは、[root ADR 0245](0245-keep-the-warnings-of-ci-at-zero.md) にも [root ADR 0349](0349-retry-ci-job-list-on-rate-limit.md) にも書かれていない。

404 の 8 回は、次のとおりである。

- 404 を返したのは、どれも、step を一つも走らせずに `cancelled` になったジョブのログだった（ジョブの `steps` が空で、多くはランナーも付いていない）。
  GitHub の logs API は、このジョブに `404 The specified blob does not exist.` を返し、後から取り直しても同じだった。
- step を一つ以上走らせてから `cancelled` になったジョブのログは、どれも 200 で取れた。
  たとえば、run 45095101386 では、`cancelled` のジョブ 25 件のうち、step が 0 の 6 件だけが 404 だった。
- 取り消しは、プルリクエストの新しい実行が古い実行を止める `cancel-in-progress` で起きたと考えられる。
  macOS のランナーを長く待つ `scripts-macos` が、step を走らせる前に取り消されやすかった。
  すべてが `cancel-in-progress` によるかは、1 件しか確かめていない。
- `cancelled` 以外で step が 0 の `completed` のジョブがあるかは、確かめていない。

キャッシュの 2 回は、次のとおりである。

- run 45102453312 の `build (ubuntu-24.04-arm, tests-driver)` で、dist-newstyle の復元の途中に `##[warning]Failed to restore: The specified blob does not exist.` が出た。
  このジョブは、キャッシュの無い状態で組み直して `success` で終わった。
- この warning は、actions/cache が使う @actions/cache の復元の処理が出す。
  そこには「キャッシュの復元の失敗は warning にして、組み立てを続ける」とあり、5xx のほかの失敗は外れとして扱われる（cache service v1 の [cache.ts#L290-L302](https://github.com/actions/toolkit/blob/ffdc20ef9208b774c9a99db718b9b02c64d84e70/packages/cache/src/cache.ts#L290-L302)、v2 の [cache.ts#L436-L448](https://github.com/actions/toolkit/blob/ffdc20ef9208b774c9a99db718b9b02c64d84e70/packages/cache/src/cache.ts#L436-L448)）。
  ffdc20e は、この処理を最後に変えた toolkit のコミットである。
  ci.yml が固定する actions/cache が、この版を束ねているかは確かめていない。
- 同じ処理は、展開の途中で失敗したときにも同じ接頭辞の warning を出す。
  展開の途中で失敗したときに、半分だけ戻ったファイルで組み立てが正しく進むかは確かめていない。
- run 45104175901 の wasm のジョブは、`scripts/ci/wasm-cache.sh` の `::warning::wasm-cache: missed, though the toolchain, the project and its freeze are those of main: the cache was evicted (docs/adr/0219)` を出した（[wasm-cache.sh#L39](https://github.com/tett23/golem/blob/00da89db13a46a2be441c0e9235a1ff46236710a/scripts/ci/wasm-cache.sh#L39)）。
- [root ADR 0219](0219-frequency-of-the-wasm-job-and-its-uncached-runs.md) は、追い出されたときに `::warning::` の注釈を出し、ジョブを失敗させないと決めている。
  理由は、プルリクエストの変更と関係の無い原因で、マージを止めないためである。
  ところが、0245 の検査がこの注釈を warning と数えるので、`ci` が落ち、マージが止まった。
  二つの ADR は、効果の上で食い違っている。
- run 45119055017（main の 47f29fff1）の `ci` で、ランナーが `jdx/mise-action` を取りに行ったとき、`##[warning]Failed to download action 'https://codeload.github.com/jdx/mise-action/tar.gz/236a21c3b91f5db6d4e174b348674a0f0caac06d'. Error: The request was canceled due to the configured HttpClient.Timeout of 100 seconds elapsing.` と `##[warning]Back off 25.872 seconds before retry.` が二回ずつ出た。
  このほかのジョブは、すべて通った。
  この warning は、action のリポジトリの中ではなく、GitHub Actions のランナーが、ジョブを始める前に action を取るときに出す（[ActionManager.cs#L1747-L1760](https://github.com/actions/runner/blob/f732921e664ced59792e405454a8235ed9b2d755/src/Runner.Worker/ActionManager.cs#L1747-L1760)）。
  取り直しても取れなければ、ジョブは失敗する。
- 2026-11-23 のキャッシュの使用量は約 6.64 GiB（38 個）で、リポジトリの上限の 10 GB に届いていなかった。
  追い出しが起きた時刻に上限を超えていたかは確かめていない。

## 実装すること

### ログの無いジョブ

検査の step は、ジョブの一覧を絞るとき、`conclusion` が `cancelled` で step を一つも持たないジョブも除く。
このジョブは何も走らせていないので、warning を出しようがなく、GitHub にもログが無い。
除いたジョブの ID と名前は、step のログに一覧として書く。
`cancelled` 以外の conclusion で step が 0 のジョブは除かない。
確かめていない形のジョブのログを、黙って読み飛ばさないためである。

選んだジョブのログが取れないときは、そのジョブの ID と名前を書き、残りのジョブのログを取り続ける。
すべてのジョブを読み終えた後で、取れないログが一つでもあれば、検査を失敗にする。
こうすれば、一つのジョブのログが取れなくても、ほかのジョブの warning は報告される。

ジョブの一覧を絞る処理と、ログを取るループは、テストできるように `scripts/ci/` のスクリプトに切り出す。

### キャッシュの復元の失敗

許可の一覧 `scripts/ci/warnings-allowed.tsv` に、正規表現 `^##\[warning\]Failed to restore: The specified blob does not exist\.$` の行を足す。
理由の欄には「actions/cache が、キャッシュの保管所に中身の無いキャッシュを読もうとしたときに出す。ジョブはキャッシュの外れとして組み直す。golem は action を変えられない」と書く。
上流の欄には、@actions/cache の v2 の復元の処理の URL を書く。

許すのは、確かめたこの一つのメッセージだけとする。
同じ接頭辞のほかのメッセージ（展開の途中の失敗など）は、組み立ての正しさに関わりうるので、許さない。
これは、0245 が上流の action の warning を許可の一覧で扱うと決めたことに当たる。
0245 の許可の一覧の表には、actions/download-artifact、actions/checkout、haskell-actions/setup の warning がある。

### wasm のキャッシュの追い出し

`scripts/ci/wasm-cache.sh` は、キャッシュが追い出されたときに、`::warning::` の代わりに `::notice::` の注釈を出す。
`log-warnings.sh` は `##[notice]` の行を数えないので、`ci` は落ちない。
注釈は今までどおり実行の画面に出るので、追い出しが起きたことは見える。

これは、[root ADR 0219](0219-frequency-of-the-wasm-job-and-its-uncached-runs.md) の「`::warning::` の注釈を出す」を変える。
0219 の理由である「マージを止めない」を、0245 の検査の下でも保つためである。

### ランナーの action の取り直し

許可の一覧に、正規表現 `^##\[warning\]Failed to download action 'https://codeload\.github\.com/[^']+'\. Error: ` と `^##\[warning\]Back off [0-9.]+ seconds before retry\.$` の行を足す。
理由の欄には「GitHub Actions のランナーが、ジョブを始める前に action を取るときに、一時的な失敗を取り直したことを知らせる。取り直しても取れなければジョブが失敗するので、通ったジョブでは結果に影響しない。golem はランナーを変えられない」と書く。
上流の欄には、ランナーの [ActionManager.cs](https://github.com/actions/runner/blob/f732921e664ced59792e405454a8235ed9b2d755/src/Runner.Worker/ActionManager.cs#L1747-L1760) の URL を書く。

### 直す文書とコード

- docs/specifications.md の `ci` ジョブの検査の文を、「省かれたもの、step を一つも走らせずに取り消されたもの、`ci` 自身を除く」に直し、取れないログがあっても残りを読むことを書く。
- README.md の wasm のキャッシュの三つめの場合の `::warning::` を `::notice::` に直し、`ci` のログを読む文を仕様書に合わせる。
- `wasm-cache.sh` の冒頭の注釈と、ci.yml の wasm のジョブの注釈の説明を、notice に直す。
- `scripts/ci/test.sh` の wasm-cache の evicted のテストの期待を `::notice::` に直し、名前に `root ADR 0427 I6:` を付ける。

### ステータスの行

採択したら、次のステータスを書き足す。

- [root ADR 0219](0219-frequency-of-the-wasm-job-and-its-uncached-runs.md): 今の `superseded [...]` の配列に、`{"part":"キャッシュのない実行と、不変条件の表の追い出しの行","by":["docs/adr/0427-warning-gate-and-jobs-without-logs.md"],"kind":"replace"}` を足す。
- [root ADR 0245](0245-keep-the-warnings-of-ci-at-zero.md): `superseded [{"part":"6. ci.yml の最後のジョブで検査する","by":["docs/adr/0427-warning-gate-and-jobs-without-logs.md"],"kind":"supplement"}]` にする。
- [root ADR 0349](0349-retry-ci-job-list-on-rate-limit.md): 読むジョブが変わることを、`{"part":null,"by":[],"kind":"note","note":"root ADR 0427 で、step を走らせずに取り消されたジョブを読むジョブから除いた"}` の注記で記録する。

許可の一覧に行を足すことは、0245 の決まりの中なので、そのためのステータスの変更はしない。

## 実装しないこと

`cancel-in-progress` を変えない。
許可の一覧に、ほかのキャッシュの知らせや、5xx で出る `core.error` の行を足さない。
warning の検査そのものの規則（行頭の形、許可の一覧の形）は変えない。
404 を返したジョブのログを、時間をおいて取り直す仕組みを作らない。

## 不変条件

I1: ジョブの一覧から検査するジョブを選ぶとき、`status` が `completed` で、`conclusion` が `skipped` でなく、`conclusion` が `cancelled` で step が 0 のものでないジョブだけを選ぶ。
I2: 選んだジョブのログのうち一つでも取れなければ、ほかのすべてのジョブのログを取って検査した後に、検査は失敗する。
I3: 選んだジョブが一つも無いときは、検査は失敗する。
I4: 行の全体が `##[warning]Failed to restore: The specified blob does not exist.` の行は、許可の一覧に当たり、検査を失敗させない。
I5: 許可の一覧に当たらないほかの `##[warning]` の行は、今までどおり検査を失敗させる。
I6: キャッシュが追い出されたとき、`wasm-cache.sh` は `::notice::` を一行出し、`::warning::` を出さない。
I7: `##[warning]Failed to download action 'https://codeload.github.com/...'. Error: ` で始まる行と、`##[warning]Back off <数> seconds before retry.` の行は、許可の一覧に当たり、検査を失敗させない。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| step が 0 の `cancelled` のジョブを一つ含む一覧 | そのジョブを選ばず、ID と名前をログに書く | I1 |
| step が 1 以上の `cancelled` のジョブ | 選ぶ | I1 |
| step が 0 の `failure` のジョブ | 選ぶ | I1 |
| `skipped` のジョブ | 選ばない | I1 |
| `in_progress` のジョブ（`ci` 自身） | 選ばない | I1 |
| 三つのジョブの二つめのログが 404 | 三つめのログも読み、最後に失敗する | I2 |
| 三つめのジョブのログに許可されない warning があり、二つめのログが 404 | 三つめの warning も報告し、失敗する | I2, I5 |
| 選んだジョブが一つも無い | 失敗する | I3 |
| すべてのジョブが step 0 の `cancelled` | 選んだジョブが無いので失敗する | I1, I3 |
| `##[warning]Failed to restore: The specified blob does not exist.` | 許可される | I4 |
| `##[warning]Failed to restore: Unexpected end of file` | 許可されない | I5 |
| `##[warning]Failed to save: ...` | 許可されない | I5 |
| ほかの `##[warning]` の行 | 失敗する | I5 |
| wasm のキャッシュが追い出された | `::notice::` が一行出る | I6 |
| ツールチェーンが main と違って外れた | 注釈を出さない（今と同じ） | I6 |
| `##[warning]Failed to download action 'https://codeload.github.com/jdx/mise-action/tar.gz/236a21c'. Error: The request was canceled ...` | 許可される | I7 |
| `##[warning]Back off 25.872 seconds before retry.` | 許可される | I7 |
| `##[warning]Failed to download action 'https://example.com/x'. Error: ...` | 許可されない | I5 |

## 受けいれ条件

A1: この ADR を実装した後の 20 回の CI の実行で、上の四つの原因で `ci` の検査の step が失敗しない。
20 回のうちに四つの原因が起きなかった場合は、起きなかったことを記録する。

## テスト設計

root ADR 0427 I1 から I7 を名前の先頭に置いたテストを、`scripts/ci/` のテストに足す。
I1 から I3 は、切り出したスクリプトに、`status`、`conclusion`、`steps` を持つジョブの一覧の JSON と、ジョブごとのログの応答（200、404）を与えて確かめる。
今の `scripts/ci/test-warning-job-list.sh` のモックは `--jq` を読まず、絞った後の一覧を返すので、I1 には使えない。
I4、I5、I7 は、`log-warnings.sh` に許可の一覧と、表の行を持つログを与えて、出力と終了コードを確かめる。
I6 は、`scripts/ci/test.sh` の今の evicted のテストを書き換えて確かめる。
root ADR 0427 A1 は、実装の後の 20 回の実行の `ci` の結果を数え、記録する。

## トレードオフ

step を走らせずに取り消されたジョブを除くので、そのジョブが本来出したはずの warning は、その実行では検査されない。
ただし、そのジョブは何も走らせていないので、見逃す warning は無い。
ジョブが `ci` の needs にあれば、取り消しはその実行の `ci` を `gate.sh` で失敗させ、次の実行でジョブが走れば、そこで検査される。

キャッシュの復元の失敗のうち、中身の無いキャッシュを読もうとした場合だけを許すので、キャッシュの保管所のほかの不調は、今までどおり `ci` を落とす。
許した場合は組み直しで CI の時間が延びるが、時間の予算は直近 20 回の中央値で判定するので、たまの組み直しは予算に表れない。
不調が続けば、中央値に表れる。

wasm のキャッシュの追い出しを notice にするので、warning の一覧には出なくなる。
追い出しの回数を数えたいときは、notice の注釈を数える必要がある。

## 参考文献

- [root ADR 0219](0219-frequency-of-the-wasm-job-and-its-uncached-runs.md)
- [root ADR 0245](0245-keep-the-warnings-of-ci-at-zero.md)
- [root ADR 0349](0349-retry-ci-job-list-on-rate-limit.md)
- GitHub Docs, Workflow commands for GitHub Actions（`::warning::` と `::notice::`）
- [actions/toolkit packages/cache/src/cache.ts](https://github.com/actions/toolkit/blob/ffdc20ef9208b774c9a99db718b9b02c64d84e70/packages/cache/src/cache.ts)
