# ADR 0289: wasmtime の C ホストの入力の長さとメモリの上限を決める

ステータス: 採択

## 文脈

[ADR 0238](0238-build-golem-wasm-with-the-standard-exception-handling-and-run-it-under-wasmtime.md) は、`golem.wasm` を wasmtime の C API で動かすホスト `scripts/wasm/run-wasmtime.c` を入れた。
夜ごとの `browser.yml` の `chromium` のジョブが、このホストで `golem.wasm` の PDF と diagnostics をネイティブの `golem` と比べる（[`browser.yml#L190-L212`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/.github/workflows/browser.yml#L190-L212)）。
[2026-11-09 の監査](../audits/2026-11-09-security-audit.md) は、このホストについて二つの所見（情報）を挙げた。
監査の本文と要約の表とで番号の振り方が違うので、ここでは本文の番号で呼ぶ。

- **WT-01**：入力の長さを `int32_t` に変えて `golem_alloc` に渡す（[`run-wasmtime.c#L143-L147`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/scripts/wasm/run-wasmtime.c#L143-L147)）。
- **WT-02**：fuel、epoch、store の limiter、メモリの上限のどれも設定しない（[`run-wasmtime.c#L120`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/scripts/wasm/run-wasmtime.c#L120)）。

二つは同じ量を相手にしているので、この ADR で一緒に決める。
入力の長さの上限は、`golem.wasm` の線形メモリがどこまで伸びうるかで決まり、メモリの上限をどう置くかを決めないと値が決まらない。

### 入力の長さ

`golem_alloc` の引数は `Word32` である（[`Main.hs#L26`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/modules/golem-wasm/app/Main.hs#L26)）。
ホストの `(int32_t)len` は、2^31 以上 2^32 未満の長さでもビットを保つので、`Word32` として読めば値は戻る。
値が壊れるのは 2^32 バイト以上で、長さは 2^32 を法として丸められる。
`golem_alloc` は丸めた長さだけを確保し、`memory_at` の境界の検査（[`run-wasmtime.c#L111-L116`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/scripts/wasm/run-wasmtime.c#L111-L116)）が、線形メモリを越える書き込みを「a buffer beyond the memory」で止める。
メモリの安全は保たれるが、利用者が読むのは、入力が大きすぎることではなく、境界の検査の文である。
`golem_alloc` が確保に失敗して 0 を返したときも、ホストは 0 番地に書こうとして同じ文で止まる。

### メモリと時間

`golem.wasm` は wasm32 のモジュールなので、線形メモリは 2^16 ページ（4 GiB）を超えて伸びない。
ホストが動かすのはリポジトリ自身のビルドした `golem.wasm` だけで、利用者の書いた wasm ではない。
時間は、`chromium` のジョブの `timeout-minutes: 11` と、`compare.sh` の入力ごとの `COMPARE_TIMEOUT`（60 秒）が縛る（[`browser.yml#L105-L114`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/.github/workflows/browser.yml#L105-L114)）。
4 GiB の上限は wasm32 の性質から来るが、ホストは memory64 を明示して切っていない。
wasmtime 49.0.5 の既定で memory64 が有効かどうかは、この ADR を書く時点で確かめていない。

## 実装すること

1. **入力の長さの上限**：`slurp` を、読んだ長さが `UINT32_MAX`（2^32 − 1）を超えた時点で読むのをやめる形にする。超えたら、`golem_alloc` を呼ぶ前に、標準エラーに `run-wasmtime: the input frame is larger than 4294967295 bytes` と書いて終了コード 3 で終わる。標準出力には何も書かない。上限の値は、テストのためにコンパイルのときのマクロ `RUN_WASMTIME_MAX_INPUT` で小さくできるようにし、既定を `UINT32_MAX` とする。
2. **長さの渡し方**：`golem_alloc` と `golem_build_pdf` の長さは、`uint32_t` に変えたうえで `wasmtime_val_t` の `i32` に入れる。ビットの並びは今と同じである。
3. **確保の失敗**：`golem_alloc` が 0 を返し、長さが 0 でないなら、`run-wasmtime: golem_alloc could not allocate <長さ> bytes` と書いて終了コード 3 で終わる。
4. **memory64 を切る**：`engine()` で `wasmtime_config_wasm_memory64_set(config, false)` を呼ぶ。線形メモリの上限 4 GiB を、wasmtime の既定によらずホストの設定で保つ。
5. **fuel、epoch、store の limiter は入れない**（「メンテナーが決めること」の 2）。
6. 仕様書の wasmtime のホストの段落に、1 から 4 と、ホストがリポジトリ自身の `golem.wasm` だけを動かす前提で時間はジョブと `compare.sh` の時間切れで縛ることを書く。
7. [docs/roadmap.md](../roadmap.md) の「2026-11-09 の監査の情報の所見」の項目から、WT-01 と WT-02 を外す。

## 実装しないこと

- `scripts/wasm/run.mjs` の上限。Node の `Buffer` の上限が先に働き、利用者のホストの例として別に扱う。[ADR 0238](0238-build-golem-wasm-with-the-standard-exception-handling-and-run-it-under-wasmtime.md) の I5（同じ入力の枠に同じ結果の枠）は、上限の内側の入力についてだけ成り立つ。
- 利用者の書いた wasm を動かすための防護。このホストはテストの道具で、配布物ではない。

## 不変条件

上限を M（既定は 2^32 − 1）、入力の枠の長さを n とする。

- **H1 上限の内側は今のとおり**：n ≤ M で `golem_alloc` が確保できれば、標準出力の結果の枠は、今のホストと同じバイト列である。
- **H2 上限の外は呼ばない**：n > M なら、終了コードは 3、標準出力は空で、`golem_alloc` も `golem_build_pdf` も呼ばない。
- **H3 確保の失敗を言う**：`golem_alloc` が 0 を返し n > 0 なら、終了コードは 3 で、標準エラーの文は境界の検査の文ではなく確保の失敗の文である。
- **H4 memory64 を切る**：`engine()` は memory64 を偽にして engine を作る。

境界の入力：

| n | 期待 |
| --- | --- |
| 0（空の入力の枠） | 今のとおり（H1。`browser.yml` の `empty`） |
| 1 | H1 |
| M | H1 |
| M + 1 | H2 |
| 2^32（M が既定のとき） | H2 |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
テストの名前（`browser.yml` の手順の名前と `echo` の文）には、H1 から H4 の番号を入れる。

- **H1、H2**：`browser.yml` の `chromium` のジョブの、`run-wasmtime.c` の手順に、`-DRUN_WASMTIME_MAX_INPUT=64` でビルドしたホストを足す。長さ 64 の入力の枠（kanikosen の枠の先頭を切ったもの）で終了コードが 3 でないこと、長さ 65 の入力で終了コードが 3、標準出力が空、標準エラーが上限の文であることを確かめる。`golem_alloc` を呼ばないことは、標準エラーに `golem_alloc` の文が出ないことで代える。今の実装では、65 の入力で上限の文が出ない。
- **H3**：`golem_alloc` を 0 にさせる入力を作れないので、自動のテストにしない。実装のプルリクエストで、`golem_alloc` の呼び出しを一時的に 0 を返す偽物に替えて走らせ、文を確かめる。
- **H4**：`scripts/ci/test.sh` で、`run-wasmtime.c` に `wasmtime_config_wasm_memory64_set(config, false)` があることを確かめる。
- 既定の M での 2^32 バイトの入力は、ランナーで 4 GiB を読むので、自動のテストにしない。

## トレードオフ

上限の外の入力では、ホストは読んだ 4 GiB のバッファーを持ったまま終わる。
上限の検査を読む前に置くには、入力の長さを先に知る必要があり、標準入力のパイプでは知れない。

fuel と epoch を入れないので、`golem.wasm` が止まらなくなったときは、`compare.sh` の 60 秒とジョブの 11 分で止まる。
どこで止まったかはわからない。

## メンテナーが決めること

1. **入力の上限の値**：推奨は 2^32 − 1 である。`golem_alloc` の `Word32` で表せる最大の長さで、それより小さい値に根拠がない。
   - 退けた案は、2^31 − 1 にすることである。`int32_t` の正の範囲に合うが、`Word32` を受け取る `golem_alloc` には意味のない境目である。
2. **fuel、epoch、store の limiter**：推奨は入れないことである。メモリは wasm32 と H4 で 4 GiB に縛られ、時間は `compare.sh` とジョブの時間切れで縛られている。動かすのはリポジトリ自身のビルドだけである。
   - 退けた案の一つは、fuel を入れることである。命令ごとに数えるので遅くなり、上限の値が wasmtime の版で変わる。
   - もう一つは、epoch を入れることである。時間で割り込むためのスレッドがホストに要り、`compare.sh` の時間切れと役割が重なる。
   - もう一つは、store の limiter で 4 GiB より小さいメモリの上限を置くことである。上限の値を決める測定がなく、大きな fixture で正しい入力を拒みうる。

## 決めたことの記録

2026-11-10 に、tett23 が「メンテナーが決めること」のすべてを推奨のとおりに決めた。

1. 入力の上限は、`golem_alloc` の `Word32` で表せる最大の長さ 2^32 − 1 とする。
2. fuel、epoch、store の limiter は入れない。メモリは wasm32 と H4 で 4 GiB に縛られ、時間は `compare.sh` とジョブの時間切れで縛られている。

採択にあたり、ソースコードへのリンクを `main` の `9acc137a`（[ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md) の実装のマージ）に合わせた。

## 参考文献

- [2026-11-09 の監査](../audits/2026-11-09-security-audit.md)（WT-01、WT-02）
- [ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md)、[ADR 0238](0238-build-golem-wasm-with-the-standard-exception-handling-and-run-it-under-wasmtime.md)、[ADR 0247](0247-keep-the-values-of-golem-wasm-independent-of-the-width-of-int.md)
- [`scripts/wasm/run-wasmtime.c`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/scripts/wasm/run-wasmtime.c)、[`modules/golem-wasm/app/Main.hs`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/modules/golem-wasm/app/Main.hs#L26-L30)
- wasmtime の C API の `wasmtime_config_wasm_memory64_set` の文書、WebAssembly Core Specification 2.0 の memory の上限（32 ビットの番地で 2^16 ページ）
