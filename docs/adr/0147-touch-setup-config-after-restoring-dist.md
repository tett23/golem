# ADR 0147: 戻した dist-newstyle の setup-config の更新時刻を新しくし、cabal test がテストのスイートを設定し直さないようにする

ステータス: 採択

## 文脈

[ADR 0140](0140-ci-split-test-runners-and-visual-pdfs-first.md) の後、`ci.yml` の `build` の x86-64 の `tests-rest` は、golem-driver のほかの 24 のスイートを一つの `cabal test` で実行する。
その手順は、2026-11-04 のモジュールを変えないプルリクエストでも 58 秒から 106 秒かかり、`build` で最も遅いランナーの一つになっている。
手順の終わりを決めるのは golem-pdf-test で、threaded でない RTS で一つずつテストを走らせ、40 秒から 75 秒かかる（[ADR 0091](0091-cpu-time-limits-in-pdf-and-svg-tests.md)）。

### スイートの始まりが遅れる

golem-pdf-test は、手順が始まってから 18 秒から 31 秒たって始まる。
そのあいだ、cabal は 24 のスイートを順に「ビルド」してから走らせる。
ログには、スイートごとに次の行が出る。

```
golem-doc.cabal has been changed. Re-configuring with most recently used
Configuring test suite 'golem-doc-test' for golem-doc-0.1.0...
```

`tests-rest` の一回の手順に、この行が 26 から 32 回、テストの実行ファイルのリンクが 8 から 27 回出た（実行 [41818037051](https://github.com/tett23/golem/actions/runs/41818037051)、[41820029937](https://github.com/tett23/golem/actions/runs/41820029937)、[41819668909](https://github.com/tett23/golem/actions/runs/41819668909)、[41818197481](https://github.com/tett23/golem/actions/runs/41818197481)）。
直前の `cabal build all` は、これらのスイートを変わっていないとして飛ばしている。

この行は、Cabal の Setup が出す。
Setup は、ビルドの前に `.cabal` のファイルが `dist/setup-config` より新しいかを、更新時刻だけで比べ、新しければ設定し直す（Cabal 3.16 の [Configure.hs](https://github.com/haskell/cabal/blob/8d1f5a33662be0db0654061fb53fb00e3f4417e0/Cabal/src/Distribution/Simple/Configure.hs#L392-L402) と [Simple.hs](https://github.com/haskell/cabal/blob/8d1f5a33662be0db0654061fb53fb00e3f4417e0/Cabal/src/Distribution/Simple.hs#L798-L810)）。
チェックアウトした `.cabal` の更新時刻はジョブの時刻で、キャッシュから戻した `setup-config` は前の実行の時刻なので、どのスイートでも設定し直しになる。
cabal-install は、Setup とは別に、`.cabal` の中身のハッシュで変更を見ている（[ADR 0037](0037-ci-build-job-speedup.md) が確かめた、更新時刻だけが新しいモジュールをコンパイルし直さない仕組みと同じである）。

[ADR 0037](0037-ci-build-job-speedup.md) は、ソースの更新時刻をコミットの時刻にそろえることを退けた。
コンパイルの要否は中身のハッシュで決まるので、そろえても縮まないからである。
Setup の設定し直しは、そのとき計測していない。

### 下書きでの計測

計測のための下書きのプルリクエスト [#521](https://github.com/tett23/golem/pull/521) で、二つの方法を試した。
どれもモジュールを変えない実行である。

| 実行 | 方法 | `tests-rest` の手順（秒） | golem-pdf-test の始まり（手順から秒） | 設定し直し | リンク |
|---|---|---|---|---|---|
| 上の四つ（前） | なし | 106、83、85、58 | 31、25、27、18 | 26〜32 | 8〜27 |
| [41830290272](https://github.com/tett23/golem/actions/runs/41830290272) の 1 回目 | `.cabal` を 2000 年の時刻にする | 60 | 19 | 0 | 19 |
| 同じ、2 回目 | 同じ | 62 | 20 | 0 | 不明 |
| [41831485473](https://github.com/tett23/golem/actions/runs/41831485473) の 2 回目 | 戻した `setup-config` の時刻を今にする | 75 | 18 | 0 | 11 |

（41831485473 の 1 回目は、`main` の別の変更で golem-doc のライブラリを組み直したので、表から除いた。）

設定し直しは、どちらの方法でもなくなった。
`tests-rest` の手順は、前の中央値 84 秒に対し、60 秒、62 秒、75 秒だった。
x86-64 のランナーは、同じ手順でも割り当てられたマシンによって 1.7 倍ほど時間が違う（[ADR 0140](0140-ci-split-test-runners-and-visual-pdfs-first.md) の文脈）。
三回の計測では、この揺れと短縮を分けきれない。

### 二つの方法の違い

`.cabal` を古い時刻にする方法は、cabal-install の変更の検出を壊すおそれがある。
cabal-install のファイルの監視は、更新時刻が前と同じなら中身を読まない（[FileMonitor.hs](https://github.com/haskell/cabal/blob/8d1f5a33662be0db0654061fb53fb00e3f4417e0/cabal-install/src/Distribution/Client/FileMonitor.hs#L963-L966)）。
いつも同じ古い時刻にすると、プルリクエストが `.cabal` を変えても、前の実行と時刻が同じで、変更を見落としうる。

`setup-config` の時刻を新しくする方法は、Setup の時刻の比べ方だけを満たし、cabal-install の監視には触れない。
`.cabal` の中身が変われば、cabal-install が中身のハッシュで気づき、自分で設定し直す。

## 実装すること

テストを先に書き、今の実装で失敗することを確かめる。

- `build` の「Restore dist-newstyle」の直後に、`dist-newstyle` の下のすべての `setup-config` の更新時刻を今にする手順を置く（`find dist-newstyle -name setup-config -exec touch {} +`）。`dist-newstyle` が戻らなかったときは、何もしない。
- この手順は `PATH` も設定も変えない。[ADR 0097](0097-ci-same-path-before-build-and-env-check-runner.md) の検査（`cabal build` の前の `GITHUB_PATH` への書き込みは GHC の手順だけ）はそのまま通る。
- 計測の結果を `docs/ci-timings/` に記録する。

## 実装しないこと

- **`.cabal` やソースの更新時刻を、コミットの時刻か決まった時刻にそろえること。** 上のとおり、決まった時刻は cabal-install の変更の検出を壊しうる。コミットの時刻は、`build` のチェックアウトが浅い（`fetch-depth` が 1）ので、ファイルごとには取れない。
- **テストの実行ファイルを cabal を通さずに直に走らせること。** テストのラッパーの決まり（[ADR 0037](0037-ci-build-job-speedup.md)）を作り直すことになる。
- **長いスイートを先に始めるよう、`cabal test` の順を変えること。** cabal はスイートを計画の順に走らせ、コマンド行の順には従わない。

## テスト設計

### 先に書いて失敗させるテスト（`scripts/ci/test.sh`）

- `build` に、`find dist-newstyle -name setup-config -exec touch {} +` を走らせる手順があり、それが「Restore dist-newstyle」の後、`cabal build` の前にあること。

### 自動テストにできないものの確かめ方

- 下書きのプルリクエストで、`.cabal` に `other-modules` を一つ足すコミットを置き、cabal-install がそのパッケージを設定し直してビルドすることを確かめる。確かめた後、そのコミットは戻す。
- 実装のプルリクエストの実行と、その後の `main` への push の実行で、`tests-rest` と aarch64 の `tests` のログに `has been changed. Re-configuring` が出ないことと、手順の時間を記録する。

## トレードオフ

- 見込める短縮は、`tests-rest` で 0 秒から 25 秒前後で、マシンの揺れに埋もれうる。実行全体を縮めるのは、`tests-rest` が最後に終わる実行だけである。aarch64 の `tests` は golem-driver-test が終わりを決めているので、[ADR 0146](0146-threaded-golem-driver-test.md) なしには縮まない。
- cabal の内部の振る舞い（Setup が更新時刻だけで比べること）に頼る。cabal を上げたときに、この手順が要らなくなるか、働かなくなるかを確かめる必要がある。
- 設定し直しても `setup-config` は変わらないはずだが、もし変わる場合を、この手順は隠す。cabal-install の中身の検出がそれを受け持つ。

## 決めたことの記録

- **採択**：メンテナーが採択した（2026-11-04）。この ADR が決めてほしい点として挙げた項目は、どれも ADR の推奨のとおりとする。

## 参考文献

- Cabal 3.16, `Distribution.Simple.Configure.checkPersistBuildConfigOutdated`. https://github.com/haskell/cabal/blob/8d1f5a33662be0db0654061fb53fb00e3f4417e0/Cabal/src/Distribution/Simple/Configure.hs#L392-L402
- Cabal 3.16, `Distribution.Simple`（設定し直しの通知）. https://github.com/haskell/cabal/blob/8d1f5a33662be0db0654061fb53fb00e3f4417e0/Cabal/src/Distribution/Simple.hs#L798-L810
- [ci.yml（今の build）](https://github.com/tett23/golem/blob/3011e026b7b52e5100f52b81eddde068a89e04cb/.github/workflows/ci.yml)
- [ADR 0037](0037-ci-build-job-speedup.md)、[ADR 0091](0091-cpu-time-limits-in-pdf-and-svg-tests.md)、[ADR 0097](0097-ci-same-path-before-build-and-env-check-runner.md)、[ADR 0140](0140-ci-split-test-runners-and-visual-pdfs-first.md)、[ADR 0146](0146-threaded-golem-driver-test.md)
- 計測のデータ：下書きのプルリクエスト [#521](https://github.com/tett23/golem/pull/521) の実行と、上の表の実行（2026-11-04）
