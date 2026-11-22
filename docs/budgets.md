# 予算の一覧

この文書は、Golem の ADR が決めた予算を一か所に並べる。
予算とは、変更を重ねても守りつづける数値の上限である（テストの時間、キャッシュの量など）。
予算を決めるのは ADR で、この一覧はその写しである。
一覧と ADR が食い違うときは ADR が正であり、一覧を ADR に合わせる。
予算を変えるときは ADR を書き、同じ変更でこの一覧も直す。

この一覧には、一回きりの受けいれ条件を載せない。
受けいれ条件は、ある変更の前と後を比べる条件で、変更が入った後は確かめなおさないからである。
製品の振る舞いの上限（表のセルの数の上限など）も、CI で測る予算ではないので載せない。

## 計測のコマンドで確かめる予算

次の表の予算は、計測のコマンドで確かめる。
計測のコマンドは、リポジトリのルートで動かすと、標準出力の最後の行に一つの数を出す。
表の形は、グローバルの `conformance-audit` スキルの決まりに従う。

| 名前 | 指標と単位 | 比較 | 値 | 計測のコマンド | ADR |
| --- | --- | --- | --- | --- | --- |
| 列挙の範囲ごとの時間 | 範囲ごとの壁時計の秒の、4 回の中央値のうち最大のもの | `<=` | 10 | `cabal build -v0 golem-layout-test && d=$(mktemp -d) && for i in 1 2 3 4; do sh scripts/ci/enum-timings.sh > "$d/$i"; done; awk -F'\174' '$4+0>0 && $2 !~ /和/ {k=$2; c[k]++; v[k,c[k]]=$4+0} END{m=0; for(k in c){n=c[k]; for(i=2;i<=n;i++){x=v[k,i]; for(j=i-1;j>0&&v[k,j]>x;j--)v[k,j+1]=v[k,j]; v[k,j+1]=x} md=(n%2 ? v[k,(n+1)/2] : (v[k,n/2]+v[k,n/2+1])/2); if(md>m)m=md} print m}' "$d"/*` | [ADR 0281](adr/0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md) 2、[ADR 0286](adr/0286-leave-the-start-of-cabal-out-of-the-time-of-an-enumeration-area.md) 3 |
| 列挙の範囲の和の時間 | すべての範囲の壁時計の秒の和の、4 回の中央値 | `<=` | 30 | `cabal build -v0 golem-layout-test && d=$(mktemp -d) && for i in 1 2 3 4; do sh scripts/ci/enum-timings.sh > "$d/$i"; done; awk -F'\174' '$2 ~ /和/ {v[++n]=$4+0} END{for(i=2;i<=n;i++){x=v[i]; for(j=i-1;j>0&&v[j]>x;j--)v[j+1]=v[j]; v[j+1]=x} print (n%2 ? v[(n+1)/2] : (v[n/2]+v[n/2+1])/2)}' "$d"/*` | [ADR 0281](adr/0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md) 2、[ADR 0286](adr/0286-leave-the-start-of-cabal-out-of-the-time-of-an-enumeration-area.md) 3 |
| Actions のキャッシュの合計 | GB（10^9 バイト） | `<=` | 10 | `gh api repos/tett23/golem/actions/cache/usage --jq '.active_caches_size_in_bytes / 1000000000'` | [ADR 0228](adr/0228-keep-the-ci-caches-under-the-10-gb-limit.md) I5 |
| プルリクエストの CI の時間 | `build` を省かなかった直近 20 回の `ci.yml` の、依存をたどった最も長い道の秒の中央値 | `<=` | 300 | `sh scripts/ci/ci-critical-path.sh` | [ADR 0392](adr/0392-budget-the-pull-request-ci-at-five-minutes.md) |

列挙の二つの予算は、[ADR 0286](adr/0286-leave-the-start-of-cabal-out-of-the-time-of-an-enumeration-area.md) では CI の x86-64 の 4 つのジョブの中央値で判定する。
上の計測のコマンドは、同じ計算機で 4 回走らせた中央値を出すので、CI の値とは計算機の分だけ違う。
和の中央値は、回ごとの和の中央値であり、範囲ごとの中央値の和ではない（[ADR 0286](adr/0286-leave-the-start-of-cabal-out-of-the-time-of-an-enumeration-area.md) の M2）。
キャッシュの予算は、[ADR 0228](adr/0228-keep-the-ci-caches-under-the-10-gb-limit.md) では「10 GB の下にある」と書かれており、ちょうど 10 GB は予算を超える。
プルリクエストも `dist-newstyle` を保存するので、`pr-caches.yml` が、キャッシュの合計が 9 GB を超えたときに開いているプルリクエストの `dist-` のキャッシュを古いものから消し、予算との間に 1 GB を残す（[ADR 0395](adr/0395-bring-the-pull-request-ci-under-five-minutes.md) の I3）。
プルリクエストの CI の時間の計測のコマンドは、GitHub の API を `gh` で読むので、ネットワークと `gh` の認証が要る（[ADR 0392](adr/0392-budget-the-pull-request-ci-at-five-minutes.md)）。

## テストと CI の中で強制する上限

次の上限は、テストや CI のスクリプトが、超えたときに止めるか落とすことで強制する。
数を一つ出す計測のコマンドが無いので、上の表には載せない。

| 名前 | 上限 | 強制するもの | ADR |
| --- | --- | --- | --- |
| 毎晩の列挙の和 | 時間を量る段とすべての範囲の段の和が 60 分。ジョブの上限は 90 分 | 60 分は `.github/workflows/enum.yml` の最後の段の `scripts/ci/enum-budget.sh judge`（実行ごとの和、[root ADR 0415](adr/0415-fix-the-medium-findings-of-the-conformance-audit-of-2026-11-18.md) 3）、90 分は `timeout-minutes` | [ADR 0208](adr/0208-widen-lightweight-formal-methods.md) 4、[ADR 0281](adr/0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md) 2、[ADR 0304](adr/0304-check-the-keep-options-up-to-4-elements-and-draw-5-every-night.md) |
| テストスイートごとの時間 | `max(10, ceil(2 × m))` 秒。m は main の直近 20 回の中央値。テストを足して伸びたスイートは、プルリクエストの CI の秒 t から `max(10, ceil(2 × t))` 秒 | `scripts/ci/suite-timeout.sh` と、スイートごとの値の表 `scripts/ci/suite-limits.tsv` | [ADR 0292](adr/0292-limit-the-time-of-each-test-suite-by-the-median-of-main.md)、[ADR 0301](adr/0301-make-the-suite-limits-follow-a-suite-that-grew-by-added-tests.md) 1 |
| テストスイートの止まりの検出 | 600 秒 | `scripts/ci/suite-timeout.sh`（`SUITE_TIMEOUT` の既定） | [ADR 0292](adr/0292-limit-the-time-of-each-test-suite-by-the-median-of-main.md) |
| golem-pdf と golem-svg のテストの時間（ネイティブ） | CPU 60 秒、実時間 300 秒。時間の上限を付けるテストは、単独の CPU 時間で 10 秒以内 | `hangLimits` | [ADR 0091](adr/0091-cpu-time-limits-in-pdf-and-svg-tests.md) |
| golem-pdf と golem-svg のテストの時間（wasm32） | CPU 600 秒、実時間 1200 秒 | `hangLimits` の wasm32 の値 | [ADR 0388](adr/0388-widen-the-time-limits-of-tests-on-wasm32.md) I2 |
| golem-driver-test の止まりの検出 | 300 秒 | `hangTimeout` | [ADR 0237](adr/0237-raise-the-hang-time-outs-of-golem-driver-test-to-300-seconds.md) |
| threaded のテストの見張り | `300 × GOLEM_RACE_TESTS` 秒 | ランタイムの外の見張りのスレッド | [ADR 0117](adr/0117-watchdog-outside-the-runtime-for-threaded-tests.md) |
| Alloy のモデルの CI | `models.yml` は 30 分。毎晩のジョブは 1 コマンド 5.5 時間、ジョブ 345 分 | `check.sh` の `TIMEOUT` | [ADR 0242](adr/0242-run-the-heavy-commands-of-the-alloy-models-every-night.md) |
| CI の warning | 許可の一覧に無い warning が 0 行 | `scripts/ci/log-warnings.sh` と `scripts/ci/warnings-allowed.tsv` | [ADR 0245](adr/0245-keep-the-warnings-of-ci-at-zero.md) |
| 取得の `curl` の時間 | 1 回 120 秒。3 回まで試す | `FETCH_MAX_TIME` | [ADR 0243](adr/0243-retry-every-download-and-cache-the-archives-checked-by-sha-256.md) |
