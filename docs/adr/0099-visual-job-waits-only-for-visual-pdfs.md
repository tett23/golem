# ADR 0099: visual ジョブを build と同時に始め、成果物 visual-pdfs だけを待つ

ステータス: 採択

## 文脈

[ADR 0095](0095-visual-job-in-ci.md) は、`visual` ジョブを `needs: build` とした。
`build` は行列のジョブなので、`visual` は、`visual-pdfs` を上げる x86-64 の `outputs` だけでなく、行列のすべてのランナーが終わるのを待つ。

shem の v0.1.0-rc3 では、比べる手順が 5〜10 秒で終わる（draft のプルリクエスト #439〜#442 の測定、2026-10-27）。
そうなると、`visual` の時間の大半は、ほかのランナーを待つ時間と、ジョブの起動になる。
[ADR 0097](0097-ci-same-path-before-build-and-env-check-runner.md)（提案、CI の実時間を縮める別の ADR）の draft のプルリクエスト（#435）の実行 40376691227（2026-10-26）では、`outputs` が 2 分 28 秒で終わり、`visual` は、最後に終わった aarch64 の `all`（2 分 52 秒）の後に始まった。
`outputs` が `visual-pdfs` を上げてから `visual` が始まるまでに、約 30 秒の差がある。

GitHub Actions の `needs` は、行列の一つのランナーだけを指せない。
upload-artifact の v4 以降は、上げた成果物を、同じ実行の中でもすぐに API で取れる。

この形を先に試した draft のプルリクエスト（#437、#434 と #435 を合わせたもの）の実行 40380673488（2026-10-26）では、`visual` は `build` と同時に始まり、`outputs` が `visual-pdfs` を上げた 7 秒後に待ち終えた。
`visual` は、aarch64 の `all`（`build` の最後のランナー）より 7 秒早く終わり、実行の全体は 3 分 19 秒だった（#435 だけの実行 40376691227 は 7 分 15 秒で、その差の大半は、shem の v0.1.0-rc2 のスレッドの遅さを、PDF を並べて描いて避けた分である。この回避は、shem の v0.1.0-rc3 で要らなくなった）。

## 実装すること

テストを先に書き、今の実装で失敗することを確かめる。

- `scripts/visual/wait-pdfs.sh RUN ATTEMPT JOB` を足す。`gh api` で実行 `RUN` の成果物 `visual-pdfs` を問い合わせ、あれば終了コード 0 で終わる。なければ、実行の試行 `ATTEMPT` のジョブ `JOB` の状態を問い合わせ、`completed` なら（もう一度成果物を問い合わせてなければ）終了コード 1、`JOB` がなければ終了コード 1 で終わる。どちらでもなければ `WAIT_INTERVAL` 秒（既定 10）待って繰り返す。
- `ci.yml` の `visual` を `needs: [changes]` にし、`if` はそのままとする。shem の取得の後、成果物を取り寄せる前に、`timeout -k 10 3600 sh scripts/visual/wait-pdfs.sh "$GITHUB_RUN_ID" "$GITHUB_RUN_ATTEMPT" 'build (ubuntu-24.04, outputs)'` の手順を置く。トークンには、今の `actions: read` を使う。
- 待つ上限は 60 分とする。キャッシュのない `build` でも届く長さである。`visual` の `timeout-minutes` は 15 から 75 にする。
- `ci` の `needs` と `gate.sh` は変えない。`visual` が `build` を待たなくなっても、`ci` は両方を待つ。
- 開発者のマニュアルの「CI のジョブ」の章の `visual` の節（`visual` は `build` の後に走る、という記述）と、README の `visual` の行を直す。

## 実装しないこと

- `visual-pdfs` を組む手順を別のジョブに分けること。golem のビルドがもう一度要る。
- `outputs` のランナーの中で描いて比べること。[ADR 0095](0095-visual-job-in-ci.md) がジョブを分けた理由（判定の一覧から、どちらが落ちたかがわかる）を失う。

## テスト設計

- `scripts/visual/test.sh` に、偽の `gh` で次を確かめる項目を足す。
  - 成果物が 3 回目の問い合わせで現れると、3 回問い合わせて終了コード 0 で終わること。ジョブの問い合わせが、実行と試行の番号を含むパスであること。
  - 成果物があれば、ジョブの状態によらず終了コード 0 であること。
  - ジョブが `completed` で成果物がなければ、終了コード 1 で、その旨を標準エラーに書くこと。
  - ジョブがなければ、終了コード 1 で、ジョブの名前を標準エラーに書くこと。
  - 引数が足りなければ、終了コード 2 であること。
- `scripts/ci/test.sh` の `visual` の項目を直す。`needs: [changes]`、`timeout-minutes: 75`、`wait-pdfs.sh` の手順が成果物の取り寄せより前にあること、待つジョブの名前が `build` の行列の `name` と `part: outputs` から作られる名前であること。
- CI で、`visual` が `build` と同時に始まり、`visual-pdfs` が上がった後に通ること。

## トレードオフ

- `visual` のランナーが、`build` のあいだ待つだけで動いている。golem のリポジトリは公開なので、GitHub のホストのランナーの時間はかからない。
- `wait-pdfs.sh` は、待つジョブを名前で探す。`build` の行列の `name` か `part` を変えると、`visual` は失敗する。`scripts/ci/test.sh` の項目で、名前の食い違いを CI の前に見つける。
- 10 秒ごとに API を問い合わせる。`build` が 3 分なら、約 40 回である。
- `build` が `visual-pdfs` を上げずに失敗すると、`visual` も失敗する。今は `build` の失敗で `visual` が省かれる（skipped）。`ci` の判定はどちらでも失敗である。

## 参考文献

- [ADR 0095](0095-visual-job-in-ci.md)
- [ci.yml の visual ジョブ（今の実装）](https://github.com/tett23/golem/blob/22f6975623903baf42236964a8d29ae244b06a83/.github/workflows/ci.yml#L384-L390)
- [actions/upload-artifact の README（v4 の、すぐに使える成果物）](https://github.com/actions/upload-artifact/blob/v4.0.0/README.md)
- CI の実行 40376691227（#435、2026-10-26）と 40380673488（#437、2026-10-26）
