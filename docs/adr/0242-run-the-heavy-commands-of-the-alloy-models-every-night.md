# ADR 0242: Alloy のモデルの重いコマンドを毎晩走らせる

ステータス: 採択

## 文脈

### 走らせていない 14 のコマンド

[ADR 0235](0235-check-the-manual-wat-example-the-diagnostic-anchors-and-the-alloy-models-in-ci.md) の 3 は、改ページの Alloy のモデル `docs/golem-layout/models/pagination.als` を CI で走らせることにした。
`scripts/models/check.sh` が、同じディレクトリの `expected.txt` に挙げたコマンドを走らせ、解の有無を比べる（[`check.sh`](https://github.com/tett23/golem/blob/c4202bb6754a95d425c4fe5627463ccaf8273558/scripts/models/check.sh)）。
`.github/workflows/models.yml` は、モデルを変えたプルリクエストと `main` への push と週に一度、上限 30 分で走る（[`models.yml`](https://github.com/tett23/golem/blob/c4202bb6754a95d425c4fe5627463ccaf8273558/.github/workflows/models.yml)）。

モデルのコマンドは 37 あり、`expected.txt` にあるのは 23 である。
残りの 14 は、`check.sh` が「not in expected.txt, not run」と書くだけで、走らない。

- [golem-layout ADR 0026](../golem-layout/adr/0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) の 6：`waitingBlankSome`、`waitingBlankNone`、`waitingBlankAllButGreedy`、`blankFigureOrder`、`blankBeforeWaiting25`、`blankRules25`
- [golem-layout ADR 0027](../golem-layout/adr/0027-need-lines-judged-again-after-spaces.md) の 5：`needSpaceSome`、`needSpaceNone`、`needSpaceAllButGreedy`、`needFigure`、`needGreedy`
- [golem-layout ADR 0035](../golem-layout/adr/0035-a-larger-need-lines-after-a-judged-one-is-judged-again.md) の 3：`needMoreSome`、`needMore27`、`needMoreNone`

モデルの README は、これらの結果をスコープ 3 か 4 までしか書いていない（[docs/golem-layout/models/README.md](../golem-layout/models/README.md)）。
README の書いた時間は、スコープ 4 の解のないコマンドで 2 分から 20 分、`needSpaceNone` のスコープ 3 で 33 分、`blankFigureOrder` のスコープ 4 で 1 時間を超えて打ち切り、である。
そのため [ADR 0235](0235-check-the-manual-wat-example-the-diagnostic-anchors-and-the-alloy-models-in-ci.md) は、スコープ 5 では 30 分に収まらない見込みが高いとして、14 を `expected.txt` に入れなかった。

### スコープ 5 で測った

2026-11-09 に、14 のコマンドをモデルに書いたスコープ（5）のまま、二か所で走らせた。

- **ランナー**：GitHub Actions の `ubuntu-24.04`（4 コア、16 GB）で、一つのジョブに一つのコマンドを走らせた。Alloy は `check.sh` と同じ 6.2.0 の jar（SHA-256 で検査）、Java はランナーの 17、ソルバーは既定の SAT4J である。測るための一時的なブランチ `measure-alloy-nightly` のワークフローで走らせ、ブランチは消した。
- **手元**：Apple Silicon の 10 コアの macOS で、Alloy 6.2.0（同じ jar）と Zulu の JDK 21 で、6 つずつ同時に走らせた。同じマシンで、ほかの作業とソルバーの比べ（下）も動いていた。

| コマンド | 結果 | ランナー | 手元 |
| --- | --- | --- | --- |
| `waitingBlankSome` | found | 7 秒 | 17 秒 |
| `waitingBlankNone` | none | 1,893 秒 | 2,365 秒 |
| `waitingBlankAllButGreedy` | none | 3,694 秒 | 4,063 秒 |
| `blankFigureOrder` | none | 648 秒 | 1,891 秒 |
| `blankBeforeWaiting25` | found | 8 秒 | 17 秒 |
| `blankRules25` | none | 436 秒 | 1,270 秒 |
| `needSpaceSome` | found | 7 秒 | 10 秒 |
| `needSpaceNone` | none | 13,138 秒 | 8,845 秒 |
| `needSpaceAllButGreedy` | found | 127 秒 | 227 秒 |
| `needFigure` | found | 14 秒 | 26 秒 |
| `needGreedy` | found | 10 秒 | 17 秒 |
| `needMoreSome` | found | 13 秒 | 18 秒 |
| `needMore27` | found | 48 秒 | 87 秒 |
| `needMoreNone` | 終わらず | 4 時間 10 分を過ぎても終わらず | 4 時間 30 分を過ぎても終わらず |

ランナーの時間は、Java を起こしてから終わるまでの実時間である（`/usr/bin/time -v`）。
ランナーの最大の常駐は、どのコマンドも 760 MB 以下だった。

多くは README の時間より短い。
README の時間は、手元でほかの走らせ方と重ねたときのもので、SAT4J の探索の時間は問題の大きさだけでは決まらない。
たとえば `blankFigureOrder` は、README ではスコープ 4 で 1 時間を超えたが、ランナーではスコープ 5 で 11 分に収まった。
`needSpaceNone` は、手元のほうがランナーより速かった。
同じ問題でも、時間はマシンと探索の順で 1.5 倍ほど揺れる。

`needMoreNone` だけは、スコープ 5 が、ランナーでも手元でも 4 時間を過ぎて終わらなかった。
スコープ 4 では、ランナーで 822 秒で終わり、解はない。

### `needSpaceAllButGreedy` に解がある

`needSpaceAllButGreedy` は、README ではスコープ 3 まで「なし」だが、スコープ 4 で解がある（手元で 180 秒）。
最も小さい例は、段の行の数が 4 で 2 行を使った段に、`@need-lines 2`、見出し、改丁の見出し、改丁の見出しが来るものである。
空きはない。

- `@need-lines` は書いた位置で守られ（残りは 2 行）、次のブロック（一つめの見出し）の最初の部分（`firstPart`、見出しなら 1 行）が入るので、`spaceKeeps`（P7）は一つめの見出しをこの段に置くことを求める。
- 一つめの見出しは段の最初ではないので、`keepHeading21` は続く二つの見出しも同じ段に求める。3 行は残りの 2 行に入らない。
- 三つとも次の段に送れば、P7 を破る。

モデルの `firstPart` は、見出しの最初の部分を見出しの 1 行とし、`keepHeading21` が一緒に置くことを求める見出しの並びを数えない。
これがモデルの書き方の誤りか、P7 と見出しの規則が実際に両立しない組かは、この ADR では決めない。
改ページの規則を決める ADR の範囲であり、実装が同じ入力で何をするかも確かめていない。

### ソルバーを替えても一様には速くならない

Alloy 6.2.0 の jar は、SAT4J のほかに、MiniSat と Glucose のネイティブのライブラリを linux/amd64 と darwin/arm64 などの分だけ持つ（jar の `native/`、`alloy6 solvers` の `minisat`、`glucose`）。
`exec` の `-s` で選べ、新しく取ってくるものはない。
ライセンスは、jar の `LICENSES/MiniSat.txt` と `LICENSES/Glucose.txt` で MIT の形である。

比べた結果は次のとおりである。
Glucose は、ランナーの `needMoreNone` のスコープ 4 で SAT4J より 3 割速かったが、手元の `needSpaceNone` のスコープ 3 では 2.5 倍遅かった。
MiniSat は、どれでも SAT4J より遅かった。

| コマンドとスコープ | 場所 | SAT4J | MiniSat | Glucose |
| --- | --- | --- | --- | --- |
| `needMoreNone`、3 | 手元 | 22 秒 | 29 秒 | 24 秒 |
| `needSpaceNone`、3 | 手元 | 711 秒 | 1,767 秒で打ち切り | 1,750 秒 |
| `needMoreNone`、4 | ランナー | 822 秒 | 1,012 秒 | 580 秒 |

### メンテナーの決めたこと

2026-11-09 に、メンテナーは、上限を緩めて 14 のコマンドを毎晩走らせると決めた（「決めたことの記録」）。
この ADR は、その走らせ方を決める。

## 実装すること

### 1. 二つめの一覧 `nightly.txt`

`docs/golem-layout/models/nightly.txt` を足し、14 のコマンドとその解の有無を書く。
書き方は `expected.txt` と同じ（一行に一つのコマンドの名前と `found` か `none`、`#` で始まる行は注）である。
それに、三つめの欄として、走らせるスコープを書けるようにする。
書かないコマンドは、モデルに書いたスコープ（5）で走る。

スコープは、ランナーでの時間が上限（3 の 5.5 時間）の 1.5 分の 1（3 時間 40 分）以内なら 5 とし、そうでないコマンドだけを、それに収まる最も大きいスコープにする。
1.5 は、文脈の時間の揺れの幅である。
`needMoreNone` だけが 4 で、ほかの 13 は 5 である。
値は、文脈のランナーの測定の結果である。

```
waitingBlankSome found
waitingBlankNone none
waitingBlankAllButGreedy none
blankFigureOrder none
blankBeforeWaiting25 found
blankRules25 none
needSpaceSome found
needSpaceNone none
needSpaceAllButGreedy found
needFigure found
needGreedy found
needMoreSome found
needMore27 found
needMoreNone none 4
```

`expected.txt` は変えない。
`models.yml` は、今のとおり `expected.txt` の 23 のコマンドだけを、上限 30 分で走らせる。

### 2. `check.sh` の引数と時間切れ

`check.sh` を次の形にする。

```
check.sh [-f LIST] [COMMAND ...]
```

- `-f LIST` は、各モデルのディレクトリで読む一覧のファイルの名前である。既定は `expected.txt` である。モデルのディレクトリに `LIST` がなければ、今の `expected.txt` がないときと同じく、失敗として書く。
- `COMMAND` を挙げたときは、一覧のコマンドのうち、挙げたものだけを走らせる。どのモデルの一覧にもない `COMMAND` は、使い方の誤りとして終了コード 2 で終わる。挙げないときは、一覧のすべてを走らせる（今と同じ）。
- 環境変数 `TIMEOUT` は、一つのコマンドの実時間の上限（秒）である。空か 0 なら上限はない（今と同じ）。上限を超えたコマンドは、その Java を止め、`check: time-out after <秒> s, not decided: <モデル> <コマンド>` を標準出力に書く。時間切れのコマンドを `found` とも `none` とも数えない。
- 終了コードは次のとおりである。結果が一覧と違うコマンド、Alloy の失敗、一覧の誤りが一つでもあれば 1。それがなく、時間切れが一つでもあれば 3。どちらもなければ 0。使い方の誤りは 2（今と同じ）。
- 一覧の三つめの欄にスコープがあるコマンドは、モデルの写しの `for <数> but` の数をすべてそのスコープに替えて走らせる。モデルに `for <数> but` がなければ、一覧の誤りとする。スコープは 1 から 99 の整数とする。
- 時間を測って止めることは、`timeout` のコマンドに頼らず、シェルで書く。macOS の BSD の道具にも `timeout` はない。

### 3. 毎晩のワークフロー `models-nightly.yml`

`.github/workflows/models-nightly.yml` を足す。

- 毎日一度の `schedule` と `workflow_dispatch` で走る。プルリクエストと push では走らない。
- 最初のジョブ `prepare` が、`scripts/ci/race-needed.sh "$GITHUB_SHA" models-nightly.yml` で、前に成功した実行から `main` が変わったかを見る（enum.yml と browser.yml と同じ。`workflow_dispatch` ではいつも走る）。変わっていなければ、後のジョブを飛ばす。
- `prepare` は、`docs/*/models/nightly.txt` のコマンドの名前を JSON の配列にして出力する。
- 後のジョブ `nightly` は、その配列の matrix で、一つのジョブに一つのコマンドを走らせる。`fail-fast: false` とし、14 のジョブを同時に走らせる。
- 各ジョブは `TIMEOUT=19800 JAVA="$JAVA_HOME_17_X64/bin/java" sh scripts/models/check.sh -f nightly.txt "$COMMAND"` を走らせる。
- 一つのコマンドの上限は 5.5 時間（19,800 秒）、ジョブの `timeout-minutes` は 345 分とする。ジョブの上限は、`check.sh` の時間切れが働かなかったときの止めである。
- 終了コード 3（時間切れだけ）は、`::warning::` の注釈とジョブの要約に、時間切れのコマンドと上限を書き、ジョブを成功とする。終了コード 1 と 2 は、ジョブを失敗させる。
- 権限は `contents: read` と `actions: read`（`race-needed.sh` の `gh run list` のため）だけとする。

5.5 時間は、次のように決めた。

- 一覧のスコープで、ランナーで最も長かったコマンドは `needSpaceNone` の 13,138 秒（3 時間 39 分）だった。5.5 時間はその 1.5 倍で、文脈の揺れの幅にあたる。
- GitHub のジョブの上限は 6 時間である。チェックアウトと jar の取得の時間と、`check.sh` が止めてから終わるまでの時間を残すと、5.5 時間がその中で取れる最も長い上限である。
- 一つのコマンドに一つのジョブを割り当てるので、コマンドの時間は足し合わさらない。実行の全体の時間は、最も長いコマンドで決まる。

### 4. 時間切れを失敗にしない

時間切れは、ジョブを失敗させずに、注釈で知らせる。
結果の誤り（一覧と違う解の有無）と Alloy の失敗だけを、失敗にする。

Golem は、組版について、速さより正しさを先に置く。
この検査で正しさにあたるのは、モデルが一覧と同じ答えを出すことであり、時間切れは答えを出さなかったことである。
時間切れを失敗にすると、ランナーの速さと SAT4J の探索の運で毎晩の結果が赤と緑に揺れる。
揺れる検査は、本当の失敗を見落とさせる。
そこで、時間切れは、答えがないことを注釈で毎回はっきり書き、答えが違うことだけを赤にする。
時間切れが続くコマンドは、上限を見直すか、モデルを小さくする ADR で扱う。

### 5. ソルバー

SAT4J のままとする。
文脈の比べのとおり、jar に入った MiniSat はどれでも遅く、Glucose は一つで速く一つで遅かった。
最も長い `needSpaceNone` を速くする見込みはなく、`models.yml` と同じソルバーにしておけば、二つの検査の結果の違いをソルバーの違いに帰さずに済む。

### 6. 測った時間の記録と文書

- 実装のプルリクエストで、`models-nightly.yml` を一度走らせ、各コマンドの時間を `docs/ci-timings/` に記録する。ワークフローは `main` に入るまで `schedule` でも `workflow_dispatch` でも走らないので、ブランチでは一時的に push で走らせ、マージの前にその設定を外す。
- その実行の結果が 1 の値と違えば、`nightly.txt` を走らせた結果に合わせず、プルリクエストで止めて報告する。
- `docs/golem-layout/models/README.md` の「CI の検査と expected.txt」に、`nightly.txt` と毎晩の検査を書き、14 のコマンドの結果の表を、スコープ 5 の結果に書き直す。`needSpaceAllButGreedy` の解の例と、それをこの ADR では決めないことを書く。
- `docs/roadmap.md` の「未決事項」に、`needSpaceAllButGreedy` の組（P7 と見出しの規則、またはモデルの `firstPart`）を足す。
- README.md の CI のワークフローの表に、`models-nightly.yml` の行を足す。
- `CONTRIBUTING.md` と `CONTRIBUTING.en.md` の「規則の Alloy のモデル」に、コマンドの解の有無を変えたときに直す一覧として `nightly.txt` を足す。GitHub Actions の節に、`models-nightly.yml` が毎晩走り、5 分の方針に関わらないことを書く。
- [ADR 0235](0235-check-the-manual-wat-example-the-diagnostic-anchors-and-the-alloy-models-in-ci.md) のステータスの行を「採択→重いコマンドの毎晩の検査は [ADR 0242](0242-run-the-heavy-commands-of-the-alloy-models-every-night.md)」に改める。

## 実装しないこと

- `models.yml` を変えること。プルリクエストと週に一度の検査は、今の 23 のコマンドと 30 分のままとする。
- モデルを変えるプルリクエストで、14 のコマンドを走らせること。走らせると、そのプルリクエストは時間を待つことになる。モデルを変えた後の最初の夜に、毎晩の検査が確かめる。
- `needSpaceAllButGreedy` の組を解くこと。モデルを直すか、規則を決めるかは、改ページの規則の ADR で決める。
- モデルの最も小さい例を CI で探し直すこと（[ADR 0235](0235-check-the-manual-wat-example-the-diagnostic-anchors-and-the-alloy-models-in-ci.md) のとおり）。
- スコープを 5 より上げること。`needMoreNone` のスコープ 5 を、ほかの方法（ソルバーを替える、モデルを分ける）で走らせること。
- ソルバーを替えること。jar の外のソルバーを取ってくること。
- 毎晩の検査の失敗を、issue やメールなど、GitHub の実行の結果のほかの方法で知らせること。

## 不変条件

- **I1**：`main` の `nightly.txt` の各コマンドを、一覧のスコープ（書いていなければモデルのスコープ）で走らせると、時間切れでない限り、解の有無は `nightly.txt` のとおりである。
- **I2**：各モデルのコマンド（`run` と `check`）は、`expected.txt` と `nightly.txt` のちょうど一方に挙がっている。
- **I3**：`check.sh` は、時間切れのコマンドを `found` とも `none` とも書かない。
- **I4**：`check.sh` の終了コードは、結果の誤りか Alloy の失敗か一覧の誤りがあれば 1、それがなく時間切れがあれば 3、どちらもなければ 0 である。時間切れは、結果の誤りを隠さない。
- **I5**：`check.sh` に `COMMAND` を挙げたときは、一覧のうち挙げたコマンドだけが走る。一覧にない `COMMAND` があれば、何も走らせずに終了コード 2 で終わる。
- **I6**：`models.yml` が走らせるのは `expected.txt` のコマンドだけであり、`models-nightly.yml` が走らせるのは `nightly.txt` のコマンドだけである。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| 一つのコマンドの時間 | 上限なし（`TIMEOUT` が空か 0）、上限より短い、上限を超える |
| 時間切れと誤り | 時間切れだけ、誤りだけ、両方 |
| `COMMAND` | なし、一つ、二つ、一覧にないもの |
| 一覧 | `-f` なし（`expected.txt`）、`-f nightly.txt`、モデルのディレクトリにない一覧 |
| 一覧のスコープ | なし、モデルと違う数、数でないもの、四つめの欄がある |
| モデルのコマンド | 二つの一覧のどちらにもない、両方にある、ちょうど一方にある |

## テスト設計

`scripts/ci/test.sh` の `check.sh` の節に、次のテストを先に足し、今の `check.sh` で失敗することを確かめてから実装する。
偽の `java` は、今のテストのものに、`FAKE_SLOW` に挙げたコマンドでは止められるまで眠ることを足す。

- I3、I4：`TIMEOUT=1` で、`FAKE_SLOW` の一つのコマンドが時間切れの行を書き、ほかのコマンドの結果を書き、終了コード 3 で終わること。時間切れのコマンドの名前の行に `found` も `none` もないこと。
- I4：時間切れと結果の誤りが両方あるとき、終了コード 1 で終わること。
- `TIMEOUT` が空のときと 0 のとき、眠らない偽の `java` で、今と同じ結果になること。
- I5：`COMMAND` を一つ挙げると、そのコマンドの結果だけを書くこと。二つ挙げると二つだけを書くこと。一覧にない名前を挙げると、終了コード 2 で終わり、偽の `java` が一度も呼ばれないこと。
- `-f other.txt` で、そのファイルの一覧を読むこと。モデルのディレクトリに `other.txt` がないとき、終了コード 1 で終わること。
- `-f` に値がないとき、終了コード 2 で終わること。
- 一覧にスコープを書いたコマンドだけが、そのスコープに替えたモデルで走ること（偽の `java` が受け取ったモデルの `for <数> but` を書く）。スコープが数でないときと、四つめの欄があるときは、終了コード 1 で終わること。
- 今のテスト（`-f` も `COMMAND` もない形）は、そのまま通ること。

リポジトリのファイルの検査を、同じ `scripts/ci/test.sh` に足す。

- I2：`docs/*/models/*.als` の各モデルの `run` と `check` のコマンドが、同じディレクトリの `expected.txt` と `nightly.txt` のちょうど一方にあること。
- I6：`models.yml` が `check.sh` を `-f` なしで呼び、`models-nightly.yml` が `-f nightly.txt` で呼ぶこと。`models-nightly.yml` が `schedule` と `workflow_dispatch` だけで走り、`pull_request` と `push` を持たないこと（一時的な push は、マージの前に外すので、この検査がそれを確かめる）。権限が `contents: read` と `actions: read` だけであること。

I1 は、実装のプルリクエストで `models-nightly.yml` を一度走らせて確かめ、結果をプルリクエストの説明と `docs/ci-timings/` に書く。
`nightly.txt` の一つのコマンドの `found` を `none` に変えた写しで、そのジョブが失敗することも、同じプルリクエストで一度確かめる（[ADR 0235](0235-check-the-manual-wat-example-the-diagnostic-anchors-and-the-alloy-models-in-ci.md) の 3 と同じ確かめ方）。

## トレードオフ

- 14 のコマンドは、モデルを変えたプルリクエストでは走らない。結果を変えるモデルの変更は、マージした次の夜に赤になってわかる。モデルを変えるプルリクエストは少なく、変える人は手元で走らせて README と一覧を書き直すので、その夜までに気づく見込みが高い。
- `main` が変わった日には、モデルが変わっていなくても毎晩走る。モデルの結果はモデルと Alloy の版だけで決まるので、多くの夜は同じことを確かめ直す。変わったファイルでしぼる道具を新しく書くより、enum.yml と browser.yml と同じ `race-needed.sh` を使うほうが単純である。公開のリポジトリの GitHub のランナーは、時間で課金されない。
- 時間切れを失敗にしないので、時間切れが続いても実行は緑である。注釈を読まなければ、そのコマンドを確かめていないことに気づかない。
- 一つのコマンドに一つのジョブを割り当てるので、ジョブごとに jar を取ってくる（14 回）。キャッシュを足すほどの時間はかからない。
- SAT4J の時間は、同じ問題でも揺れる。5.5 時間の上限は `needSpaceNone` の 1.5 倍しかなく、ランナーの遅い夜に足りなくなることはありうる。そのときは時間切れの注釈が出る。

## 決めたことの記録

- **14 のコマンドの走らせ方**（2026-11-09、メンテナー）：上限を緩め、毎晩走らせる。この ADR の 1 から 6 は、その決定を具体にしたものである。

## 参考文献

- [ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md)、[ADR 0208](0208-widen-lightweight-formal-methods.md)、[ADR 0235](0235-check-the-manual-wat-example-the-diagnostic-anchors-and-the-alloy-models-in-ci.md)
- [golem-layout ADR 0026](../golem-layout/adr/0026-need-lines-and-blank-lines-pass-over-waiting-figures.md)、[golem-layout ADR 0027](../golem-layout/adr/0027-need-lines-judged-again-after-spaces.md)、[golem-layout ADR 0035](../golem-layout/adr/0035-a-larger-need-lines-after-a-judged-one-is-judged-again.md)
- Alloy 6, https://alloytools.org/
- AlloyTools/org.alloytools.alloy の 6.2.0 のリリース, https://github.com/AlloyTools/org.alloytools.alloy/releases/tag/v6.2.0
- GitHub Docs, Usage limits for GitHub Actions（ジョブの実行時間の上限 6 時間）, https://docs.github.com/en/actions/reference/limits
