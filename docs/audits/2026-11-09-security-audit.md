# 脆弱性診断（2026-11-09）

## 結論

v0.1.0-rc4 のタグ付けの前の監査である（[CONTRIBUTING.md](../../CONTRIBUTING.md) のリリース手順 1、[docs/adr/0035](../adr/0035-security-hardening.md)）。前回（[2026-11-08](2026-11-08-security-audit.md)、対象 `bcbe71402204b777d8631c56e90b5f44b3662574`）で挙げた中・低の問題（E-01、E-02、T-01、W-01、W-02）は、[ADR 0223](../adr/0223-emet-sizes-before-building-values.md)、[0224](../adr/0224-limit-the-cells-of-a-table-set-in-pdf.md)、[0225](../adr/0225-refuse-the-empty-path-in-the-input-frame-of-golem-wasm.md) で直っていた。再現入力を今回のコミットで作り直して、いずれも直ったことを確認した。

今回新しく重点を置いたのは、rc4 で入った preflight の内容ストリームの色の解析（G09019〜G09021、golem-pdf の `Paint`／`Import.contentOperations`）、行分割・アキ・縦中横の組版、`golem.wasm` の例外処理つきビルドと wasmtime の C ホスト（`scripts/wasm/run-wasmtime.c`）、新しいブラウザー検査（`scripts/browser` の CDP／WebDriver クライアントと HTTP サーバー `serve.mjs`）、そして供給網と CI（Neovim・Helix・Chrome for Testing・Deno・wasmtime の C API・Alloy・Poppler・`browser_wasi_shim` の取得、ワークフローの権限）である。これらに中・高の問題は見つからなかった。原稿から呼べる関数だけで起きる可用性の問題（旧 E-01、E-02）は解消しており、rc4 のタグを止める指摘はない。

| ID | 重大度 | 問題 | 確認結果 |
| --- | --- | --- | --- |
| E-01 | 修正済み | `List.range` の長さが `Int` に収まらず手数制限を迂回する（旧・中） | [ADR 0223](../adr/0223-emet-sizes-before-building-values.md)。2^63／2^64 の範囲が `PrimOverLimit`。前回の再現が通らない |
| E-02 | 修正済み | `String.replace` が手数を確認する前に巨大な結果を確保する（旧・中） | 同 ADR。40,000 文字の引数が E04100、256 MiB のヒープで落ちない。`String.join`・`List.concat`・`++` も同様に E04100 |
| T-01 | 修正済み | 上限内の表で PDF のビルドが数 GB を割り当てる（旧・中） | [ADR 0224](../adr/0224-limit-the-cells-of-a-table-set-in-pdf.md)、G07108（上限 100,000 セル）。2,560,000 セルの表が常駐 521 MB・5 秒で拒否（前回は 2.87 GB・57 秒） |
| W-01 | 修正済み | wasm の入力フレームの重複検査がファイル数の二乗（旧・低） | [ADR 0225](../adr/0225-refuse-the-empty-path-in-the-input-frame-of-golem-wasm.md) で `sortOn`＋`groupBy`。160,000 ファイルを 0.19 秒で読む（前回は 40,000 で 16 秒） |
| W-02 | 修正済み | 入力フレームが空のパス `""` を受け付ける（旧・情報） | 同 ADR。空のパスは `Left EmptyPath` |
| T-02 | 情報 | セルの上限（100,000）内でも、PDF の表はセルごとに `composeInlines` を呼ぶため、常駐がセル数に比例する | 100,000 セルの表で常駐 402 MB・割り当て 23.9 GB・9 秒。上限で頭打ちになるが、1 セルあたりの費用は残る |
| L-01 | 情報（前回から継続） | 取得設定は Wasmtime 49.0.5 だが、手元の取得済み依存は 49.0.2 のまま | `third_party/wasmtime/VERSION` と `wasmtime.h` を照合 |
| CI-01 | 情報 | `release.yml` の `ci` 呼び出しが reusable workflow に `actions: write` を与える。実際にそのトークンを受け取るジョブは今はない | `release.yml`・`ci.yml`・`scripts/ci/test.sh` を読んだ。[ADR 0228](../adr/0228-keep-the-ci-caches-under-the-10-gb-limit.md) に記録がない拡大 |
| CI-02 | 情報 | 取得スクリプトの一部は、キャッシュから戻した実行ファイルを `VERSION` の一致だけで信用し、中身を再ハッシュしない | `fetch-nvim.sh`・`fetch-chromium.sh`・`fetch-deno.sh` ほか。キャッシュは main スコープのみ復元されるので低い |
| CI-03 | 情報（前回 H-02 から継続） | 外部 action はすべてタグ参照で、SHA 固定がない | 36 の checkout ほか、全 `uses:` を確認 |
| B-01 | 情報 | `serve.mjs` は root 内のシンボリックリンクをたどり、root 外のファイルを配る | 関数レベルで再現。root は CI が組む fixture のみ、127.0.0.1 の短命ポート |
| B-02 | 情報 | CDP のブラウザーを `--no-sandbox` で起動する | `cdp.mjs`。開く URL は自分の 127.0.0.1 のページだけ |
| WT-01 | 情報 | wasmtime の C ホストは fuel・epoch・store limiter・最大メモリを設定しない | `run-wasmtime.c`。golem.wasm はリポジトリ自身のビルド。読み越しは境界検査で防ぐ |
| I-01〜I-03 | 情報（前回から継続） | LSP の semantic tokens の同時構文解析、ルート外リンクの manifest/style.toml、`run.mjs` のシンボリックリンク | いずれもコード不変。I-01 は [ADR 0207](../adr/0207-run-golem-emet-test-one-test-at-a-time-under-the-watchdog.md)（採択）と roadmap に記録 |

製品コードの修正は行っていない。前回レポートを上書きせず、現在の状態をこの記録に残す。

## 対象・脅威モデル・方法

- 対象コミット：`94b976e1fb59b59867e66195f2c8ca55a8f60b11`（origin/main、`git fetch https://github.com/tett23/golem.git`）。ソースへのリンクはこのコミットに固定した。
- 環境：macOS / aarch64、GHC 9.10.3（`cabal build golem golem-emet golem-lsp golem-wasm golem-pdf golem-preflight`）、64 ビットの `Int`。cabal は Hackage の索引のキャッシュと peg-hs の clone のためにサンドボックスの外でビルドした。負荷試験はサンドボックスの中で行った。
- 作業はブランチ `audit-rc4` の worktree（`.claude/worktrees/audit-rc4`）で行い、追跡済みファイルを変えていない。push、pull-req、issue は作っていない。
- 攻撃者が `.gm`、`.emet`、`manifest.toml`、`style.toml`、`preflight.toml`、図版（SVG・PDF）、表のファイル、参考文献、フォント、プラグインを提供し、利用者が `golem build`／`check`／`fmt`／`preflight` を実行する、LSP で開く、ホストのページが `golem.wasm` にメモリ上のファイルを渡す状況を想定した。供給網と CI（ワークフロー、取得スクリプト、ブラウザー検査、wasmtime ホスト）も対象にした。
- 前回（`bcbe7140`）からの差分は 355 コミット、495 ファイル（+40,009／−6,201）である。新規 [ADR 0207](../adr/0207-run-golem-emet-test-one-test-at-a-time-under-the-watchdog.md)〜0242 と、Emet の評価器、golem-wasm のフレーム、golem-typeset の表・縦中横・行分割、golem-pdf の `Paint`／`Import`、golem-preflight の G09019〜G09021、`scripts/browser`・`scripts/wasm`・`tools/editors` の新しいスクリプト、`.github/workflows` を中心に読んだ。
- 負荷試験の各プロセスには GHC RTS のヒープ上限（`+RTS -M256m` から `-M2g`）と、[`run-limited.sh`](2026-11-09-evidence/run-limited.sh) による外部からの時間制限（子プロセスを `kill` する）を付けた。自分で起動した子プロセス以外は停止させていない。
- 配布される `golem` は `-rtsopts` なしでリンクされるので、表の試験には、同じ `modules/golem-cli/app/Main.hs` を `-threaded -rtsopts` でリンクし直した `golem-rtsopts` を使った。製品のビルド設定は変えていない。
- CI とスクリプトの読みは、二つの補助エージェントに分けて行った（ワークフローと供給網、ブラウザーと wasmtime ホスト）。上流のチェックサムの照合を含む。Python は使っていない。成果物にシェルスクリプトと Haskell の再現コードだけを含める。

この診断は重点レビューであり、差分全体、全依存ライブラリ、全ターゲットの網羅的な安全性検証ではない。

## E-01、E-02：Emet の手数制限（修正済み）

[ADR 0223](../adr/0223-emet-sizes-before-building-values.md) が、プリミティブと二項演算の作る値の長さを、値を作る前に `Integer` で求め、残りの手数を超えるなら作らないようにした。手数は全ターゲットで `Int64` になった。

- [`Prim.hs:54-55`](https://github.com/tett23/golem/blob/94b976e1fb59b59867e66195f2c8ca55a8f60b11/modules/golem-emet/src/Golem/Emet/Prim.hs#L54-L55) の `runPrim` は、引数だけから `sizeOf` を求め、`size > room` なら `PrimOverLimit` を返す（値を作らない）。[`Prim.hs:65`](https://github.com/tett23/golem/blob/94b976e1fb59b59867e66195f2c8ca55a8f60b11/modules/golem-emet/src/Golem/Emet/Prim.hs#L65) の `sizeOf` は `List.range`・`String.replace`・`String.join` ほかの長さを、引数の長さから計算する。リストは長さを `PL Integer [..]` に持ち、共有されたリストの `List.concat` を数えるときに要素を変換し直さない（[ADR 0236](../adr/0236-record-what-implementations-decided-found-by-the-second-review-of-2026-11-08.md)）。
- [`Eval.hs:191-192`](https://github.com/tett23/golem/blob/94b976e1fb59b59867e66195f2c8ca55a8f60b11/modules/golem-emet/src/Golem/Emet/Eval.hs#L191-L192) の `roomAt` が残りの手数を渡し、[`Eval.hs:282`](https://github.com/tett23/golem/blob/94b976e1fb59b59867e66195f2c8ca55a8f60b11/modules/golem-emet/src/Golem/Emet/Eval.hs#L282) の `KBinR` と [`Eval.hs:345-349`](https://github.com/tett23/golem/blob/94b976e1fb59b59867e66195f2c8ca55a8f60b11/modules/golem-emet/src/Golem/Emet/Eval.hs#L345-L349) のプリミティブで、超過なら値を作らず `limit + 1` 手で止める。

### 再現結果

前回の [再現コード](2026-11-09-evidence/emet-probe.hs) を、`runPrim` の新しい引数（残りの手数）に合わせて直し、ほかのプリミティブ（`String.join`、`List.concat`、`++`）を呼ぶモードを足した。今回のコミットのパッケージに対してコンパイルし、ヒープ上限 256 MiB、30〜60 秒で走らせた。[実行記録](2026-11-09-evidence/emet-recheck.txt)。

| モード | 前回（bcbe7140） | 今回（94b976e1） |
| --- | --- | --- |
| `cost`（`List.range` 2^63／2^64） | コスト -9,223,372,036,854,775,808／0 | `PrimOverLimit`（値を作らない） |
| `take`（2^64 の範囲から 3 つ） | 7 手で `[1,2,3]` を返す（迂回） | E04100（100,000,001 手） |
| `control`（`List.range 1 100000001`） | E04100 | E04100（変わらず） |
| `length`（2^64 の範囲を数える） | `Heap exhausted` | E04100 |
| `replace`（40,000 文字の引数から 4 億文字） | `Heap exhausted` | E04100 |
| `join`（20,000 要素を 20,000 文字で連結） | （今回追加） | E04100 |
| `concat`（20,000×20,000 の連結） | （今回追加） | E04100 |
| `append`（1,000 文字を 30 回二倍） | （今回追加） | E04100 |

いずれも 256 MiB のヒープに収まり、ヒープ枯渇を起こさずに E04100 を返した。旧 E-01 の整数の折り返しと旧 E-02 の事前確保はどちらも解消している。

## T-01、T-02：表のセルの数

[ADR 0224](../adr/0224-limit-the-cells-of-a-table-set-in-pdf.md) が、PDF に組む表のセルの総数に上限（100,000）を付けた。[`Flow.hs:2021`](https://github.com/tett23/golem/blob/94b976e1fb59b59867e66195f2c8ca55a8f60b11/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L2021) が `cells > maxTableCells` を、セルを組む前に判定し、[`Flow.hs:2208-2209`](https://github.com/tett23/golem/blob/94b976e1fb59b59867e66195f2c8ca55a8f60b11/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L2208-L2209) が G07108 を出す。

### 再現結果

前回の [`make-fixtures.sh`](2026-11-09-evidence/make-fixtures.sh) で作った表の fixture に、同じ寸法の表を足して `golem-rtsopts build --target pdf +RTS -s` で測った。[実行記録](2026-11-09-evidence/table-recheck.txt)。

| 表 | バイト数 | ヒープ上限 | 結果（今回） |
| --- | --- | --- | --- |
| 10,000 行 256 セル（2,560,000 セル） | 5.1 MB | 1 GiB | G07108、常駐 521 MB、割り当て 4.6 GB、5 秒（前回は G07041 の前に 2.87 GB・57 秒） |
| 10,000 行 11 セル（110,000 セル） | 220 KB | 1 GiB | G07108、常駐 25 MB、1 秒 |
| 10,000 行 10 セル（100,000 セル） | 200 KB | 1 GiB | 成功、常駐 402 MB、割り当て 23.9 GB、9 秒 |
| 10,000 行 8 セル（80,000 セル） | 160 KB | 1 GiB | 成功、常駐 330 MB、8 GB、6 秒 |

T-01 は直った。2,560,000 セルの表は、全セルを組む前に G07108 で拒否され、常駐は 2.87 GB から 521 MB に下がった。

T-02（情報）：上限ぎりぎりの 100,000 セルの表は、なお常駐 402 MB・割り当て 23.9 GB を使う。上限は確保の量を頭打ちにするが、1 セルあたりに `composeInlines` を呼ぶ費用（セル数に比例）は残る。[ADR 0224](../adr/0224-limit-the-cells-of-a-table-set-in-pdf.md) はこの上限を「本の表としては十分」と置いたもので、上限内でも数百 MB を使うことは仕様の範囲内である。利用者のマシンのメモリが足りなければビルドは止まる。さらに下げるには列の幅の検査をセルを組む前に移すなどの案があり、仕様を変えるので ADR が要る。重大度は情報とした。

## W-01、W-02：wasm の入力フレーム（修正済み）

[ADR 0225](../adr/0225-refuse-the-empty-path-in-the-input-frame-of-golem-wasm.md) が、重複検査を [`Frame.hs:99-100`](https://github.com/tett23/golem/blob/94b976e1fb59b59867e66195f2c8ca55a8f60b11/modules/golem-wasm/src/Golem/Wasm/Frame.hs#L99-L100) の `firstDuplicate`（`sortOn`＋`groupBy`、n log n）にし、空のパスを [`Frame.hs:79-80`](https://github.com/tett23/golem/blob/94b976e1fb59b59867e66195f2c8ca55a8f60b11/modules/golem-wasm/src/Golem/Wasm/Frame.hs#L79-L80) の `checked` で `EmptyPath` として拒むようにした。

前回の [再現コード](2026-11-09-evidence/frame-probe.hs) を今回のコミットのモジュールに対してコンパイルし、ヒープ上限 256 MiB で走らせた。[実行記録](2026-11-09-evidence/frame-recheck.txt)。

| ファイル数 | 前回（二乗） | 今回（n log n） |
| --- | --- | --- |
| 10,000 | 0.65 秒 | 0.010 秒 |
| 40,000 | 16.0 秒 | 0.041 秒 |
| 80,000 | 60 秒で停止 | 0.084 秒 |
| 160,000 | （未測定） | 0.187 秒 |
| 空のパス | `Right [("","x")]` | `Left EmptyPath` |

W-01、W-02 ともに直った。読み込みの時間はファイル数にほぼ比例し、空のパスは拒否される。

## preflight の内容ストリームの色の解析（G09019〜G09021）

[ADR 0232](../adr/0232-check-inks-fonts-figures-links-and-epubs-structurally-in-ci.md) で、`golem preflight` が書く前の PDF のオブジェクトを読み、埋め込んでいないフォント（G09019）、特色の色空間（G09020）、C・M・Y の版に出る色（G09021）を検出するようになった。G09021 は内容ストリームの演算子を [`Import.contentOperations`](https://github.com/tett23/golem/blob/94b976e1fb59b59867e66195f2c8ca55a8f60b11/modules/golem-pdf/src/Golem/Pdf/Import.hs#L385) で解析し、[`Paint.paintsOf`](https://github.com/tett23/golem/blob/94b976e1fb59b59867e66195f2c8ca55a8f60b11/modules/golem-pdf/src/Golem/Pdf/Paint.hs#L199) が塗りと線の色を取り出す。

この解析器が読むのは Golem 自身が書いた最終 PDF のページだけであり（`contentOperations` の呼び出しは `Paint.paintsOf` の一か所）、外部ツールの図版の PDF ではない。図版の PDF の内容ストリームは `Import.importPage` が別の経路（`rewriteContent`）で扱い、`maxStreamBytes`（256 MiB）で縛られる。それでも、細工した内容ストリームでこの解析器が止まらなくなる・落ちることがないかを [再現コード](2026-11-09-evidence/content-probe.hs) で確かめた（ヒープ上限 512 MiB〜2 GiB、60 秒）。[実行記録](2026-11-09-evidence/content-probe.txt)。

| 入力 | 結果 |
| --- | --- |
| `BI` の後に `ID` がない | `Nothing`（壊れた内容として拒否） |
| `BI ID` の後に `EI` がない（1 MB の後続） | `Nothing` |
| 開いたままの文字列・配列・辞書（200 万個の `[`・`<<`） | `Nothing` |
| 壊れた 16 進文字列（5 MB） | `Nothing` |
| 20 万個の正しいインライン画像 `BI ID xx EI` | 20 万 ops |
| 200 万個の `0 0 0 0 0 rg`（26 MB） | 200 万 ops、常駐 516 MB |

解析器はどの不正入力でも `Nothing` を返して止まり、無限ループに入らない。常駐は入力に比例する（26 MB の内容を 200 万 ops に解析して 516 MB）。最終 PDF の内容ストリームは 256 MiB で縛られ、入力は Golem 自身の出力なので、これ自体は信頼できる入力である。`cmy-plates` の規則は既定で `LevelOff`（[`Rules.hs`](https://github.com/tett23/golem/blob/94b976e1fb59b59867e66195f2c8ca55a8f60b11/modules/golem-preflight/src/Golem/Preflight/Rules.hs)）で、明示して有効にしたときだけ内容ストリームを読む。`G09021` の数の解析（`decimal`）は長さ 40 文字で縛られ、桁数の累乗が暴れない。問題は見つけていない。

## golem-pdf の図版の取り込み（`Import.collect`）

外部の図版 PDF は [`Import.importPage`](https://github.com/tett23/golem/blob/94b976e1fb59b59867e66195f2c8ca55a8f60b11/modules/golem-pdf/src/Golem/Pdf/Import.hs#L1044) が読む。オブジェクトの木を [`collect`](https://github.com/tett23/golem/blob/94b976e1fb59b59867e66195f2c8ca55a8f60b11/modules/golem-pdf/src/Golem/Pdf/Import.hs#L1237) が `Set` で訪問済みを覚えてたどるので循環参照で止まらず、`maxNesting`（256）、`maxRevisions`（256）、`maxStreamBytes`／`maxDecodedBytes`（256 MiB）、`maxXrefEntries`（8,388,607）で縛られる。暗号化 PDF は `Encrypted` で拒む。この取り込みは前回・前々回の監査で読んだ範囲であり、今回の差分（`contentOperations`・`unescapeName` の export の追加）は解析器の抽出だけで、取り込みの経路の上限は変わっていない。

## 縦中横・行分割・アキ

- **縦中横**（[`Tcy.hs`](https://github.com/tett23/golem/blob/94b976e1fb59b59867e66195f2c8ca55a8f60b11/modules/golem-typeset/src/Golem/Typeset/Tcy.hs)、新規）：グリフの数だけの純粋な算術で、`w <= s` の分岐がゼロ除算を防ぐ（アドバンスの和が 0 でも割り算に入らない）。無限ループはない。
- **行分割・アキ**（`Japanese.hs`、`KnuthPlass.hs`、`Aki.hs`）：差分に `replicate`・`iterate`・`cycle`・無限リスト・無制限の再帰は入っていない。Knuth-Plass は既知の下地で、[ADR 0222](../adr/0222-line-breaking-points-the-invariants-did-not-decide.md) の不変条件のテスト（`LineBreakInvariantsSpec`、`PaginateInvariantsSpec`）が付く。新しいフォント取得やファイル入出力はない。重点的な負荷試験はしていない。

## wasmtime の C ホスト（`scripts/wasm/run-wasmtime.c`）

[ADR 0238](../adr/0238-build-golem-wasm-with-the-standard-exception-handling-and-run-it-under-wasmtime.md) で入った、`golem.wasm` を wasmtime の C API で動かすホストである。補助エージェントの読みで、次を確認した。

- モジュールが返すポインタと長さは `memory_at(ptr, len)` が `(size_t)ptr + len > wasmtime_memory_data_size()` で縛るので、細工した戻り値でホストが線形メモリの外を読むことはない（64 ビットのホストで溢れない）。
- WASI は引数 `golem.wasm` だけ、ディレクトリを開かず、環境変数を渡さず、stdin/stdout を継承しない（[ADR 0238](../adr/0238-build-golem-wasm-with-the-standard-exception-handling-and-run-it-under-wasmtime.md) の方針どおり）。
- `cc -fsyntax-only -Wall -Wextra` で警告 0。`-Wconversion` 等を足して出る 3 件はすべて wasmtime のヘッダ側。
- WT-01（情報）：入力長を `int32_t` に切り詰めて `golem_alloc` に渡す。2 GiB 以上の入力でメッセージが分かりにくくなるが、境界検査でメモリ安全は保たれる。入力の枠はリポジトリの fixture（数十 MB）。
- WT-02（情報）：fuel・epoch・store limiter・最大メモリを設定しない。golem.wasm はリポジトリ自身のビルドで、CI の step に `timeout-minutes` がある。「悪意ある .wasm」からホストを守る観点では、読み越しは防ぐが資源の消費は防がない。

`golem.wasm` 自体は今回ビルドしていない（x86-64 Linux の道具立てが要る）。wasm の中での実測はしていない。

## ブラウザー検査（`scripts/browser`）

[ADR 0234](../adr/0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md) の、HTML と golem.wasm を headless Chromium で検査するスクリプト群である。補助エージェントの読み（サンドボックスがポートの bind を拒むため、HTTP 越しの動的検証は `fileOf` の関数レベルの検証とユニットテストに置き換えた。ユニットテストは bind の要らない 19 件が通過）。

- **`serve.mjs`** は `127.0.0.1` の短命ポートにだけ bind する（0.0.0.0 ではない）。パスは `decodeURIComponent`→`normalize`→先頭の区切りを剥ぐ→`..` で始まれば拒否、で解決する。`/../../etc/passwd`、`%2e%2e`、`//etc/passwd`、URL エンコードの NUL、バックスラッシュのいずれも root 内に収まる（404）。ディレクトリ一覧は出さない。
- **B-01（情報）**：ただし `realpath` をしないので、root の下に外を指すシンボリックリンクがあれば、その中身を 200 で返す。root は CI が `cp -R` で組む fixture とマニュアルの HTML と `mkdtemp` の一時ディレクトリで、リンクを置く経路はリポジトリのコミットだけ。ヘッダのコメント「root を出るパスは 404」の約束と実装がずれている点を記録する。
- **`cdp.mjs`／`webdriver.mjs`** は `--remote-debugging-port=0` で起動し、stderr から ws の URL を読む（既定で 127.0.0.1 のみ）。`--disable-web-security`・`--remote-allow-origins=*` はない。`user-data-dir` は `mkdtemp` で作り、`close` と接続失敗で `rm -rf` する。シェルへの文字列結合、`eval`・`new Function` はない。ページに渡す式は定数か `JSON.stringify` で囲む。
- **B-02（情報）**：`cdp.mjs` は Chromium を `--no-sandbox` で起動する（Ubuntu の user namespace の制限のため。開く URL は自分の 127.0.0.1 のページだけ）。ブラウザーの脆弱性に対する最後の防護を外している点を記録する。

## 供給網と CI

補助エージェントが、新しい取得スクリプトと `.github/workflows` を読み、上流のチェックサムと照合した。

- **取得の固定**：Neovim（`fetch-nvim.sh`、0.12.6）、Helix（`helix/test.sh`、25.07.1）、Deno（`fetch-deno.sh`、2.9.8）、wasmtime の C API（`fetch-wasmtime.sh`、49.0.5、5 プラットフォーム）は、版と SHA-256 をスクリプトに固定し、`mktemp -d` の新しいディレクトリに展開する前にハッシュを検査する。固定した SHA-256 は GitHub Releases の API の digest と**一致**した。`browser_wasi_shim`（`package-lock.json`、0.4.2）は `integrity` を持ち、`npm ci --ignore-scripts` で入れる（レジストリの digest と一致）。
- **CI-04（情報）**：Chrome for Testing（`fetch-chromium.sh`、157.0.8103.38）と Alloy（`models/check.sh`、6.2.0）は、上流がチェックサムを公表しない（または古いリリースで API に digest がない）ため照合できなかった。版の存在と公式 URL は確認した。zip は 100 MB 級なので取得していない。
- **CI-05（情報）**：Poppler／qpdf は apt で入れ、版を固定しない。Ubuntu のアーカイブ署名で守られ、版のずれは再現性の問題に留まる。
- **ワークフローの権限**：トップレベルは全ワークフローで `contents: read`。書き込み権限で信頼できないコードを動かすジョブはない。`pull_request_target`・`workflow_run`・`issue_comment` はなく、`workflow_dispatch` の `inputs` もない。`run:` 内の `${{ }}` は matrix の定数 2 か所だけで、`github.event.*` は `env:` を経由する。36 の checkout すべてに `persist-credentials: false` がある（前回 CI-01 の determinism ジョブは修正済み）。
- **CI-01（情報）**：[`release.yml`](https://github.com/tett23/golem/blob/94b976e1fb59b59867e66195f2c8ca55a8f60b11/.github/workflows/release.yml#L33-L37) の `ci` 呼び出しが reusable workflow に `actions: write` を与える。これは `ci.yml` の `caches` ジョブ（`actions: write` を要求）が、呼び出し側の権限不足で run 全体を startup_failure にするのを避けるためである（`scripts/ci/test.sh` が run 42480681991 の実例として固定）。`caches` の `if` は `push && main` なので、タグ push の release.yml 経由では走らず、実際にこのトークンを受け取るジョブは今はない。ただし、[ADR 0228](../adr/0228-keep-the-ci-caches-under-the-10-gb-limit.md) は「`caches` ジョブだけが `actions: write` を持つ」と書くのに対し、release.yml の `ci` にも付いた拡大が ADR に記録されていない。将来 ci.yml のどれかのジョブが `actions: write` を要求すれば、タグ push でも通る。狭くするには `caches` を `workflow_run` の別ワークフローにする案がある（ADR が要る）。
- **CI-02、CI-03（情報）**：キャッシュから戻した実行ファイルの `VERSION` だけの信用（再ハッシュしない取得スクリプト）と、外部 action のタグ参照（前回 H-02 の継続）。キャッシュは main スコープのみ復元されるので CI-02 は低い。

## 前回指摘の再確認

| 前回の項目 | 現在の状態 | 今回の確認 |
| --- | --- | --- |
| E-01：`List.range` の整数オーバーフロー | 修正済み | [ADR 0223](../adr/0223-emet-sizes-before-building-values.md)。再現コードを直して走らせ、`PrimOverLimit`／E04100 |
| E-02：`String.replace` の事前確保 | 修正済み | 同上。256 MiB のヒープで落ちない |
| T-01：上限内の表が数 GB | 修正済み | [ADR 0224](../adr/0224-limit-the-cells-of-a-table-set-in-pdf.md)。G07108、常駐 521 MB |
| W-01：重複検査が二乗 | 修正済み | [ADR 0225](../adr/0225-refuse-the-empty-path-in-the-input-frame-of-golem-wasm.md)。160,000 ファイルを 0.19 秒 |
| W-02：空のパス | 修正済み | 同上。`Left EmptyPath` |
| L-01：手元の Wasmtime 49.0.2 | 継続 | `third_party/wasmtime/VERSION`・`wasmtime.h` を照合。配布物は `check-wasmtime-linked.sh` が守る |
| CI-01：determinism の checkout | 修正済み | 36 の checkout すべてに `persist-credentials: false` |
| I-01：LSP の同時構文解析 | 継続・記録済み | [`Server.hs:207-215`](https://github.com/tett23/golem/blob/94b976e1fb59b59867e66195f2c8ca55a8f60b11/modules/golem-lsp/src/Golem/Lsp/Server.hs#L207-L215) 不変。[ADR 0207](../adr/0207-run-golem-emet-test-one-test-at-a-time-under-the-watchdog.md)（採択）と `docs/roadmap.md` に記録 |
| I-02：ルート外リンクの style.toml | 継続 | [再現](2026-11-09-evidence/symlink-recheck.txt)。外を指す `style.toml` で PDF を書く。診断の文面にしか現れない |
| I-03：`run.mjs` のシンボリックリンク | 継続 | CI の fixture にしか使わない |
| H-01：取得・コンパイルの資源上限 | 継続 | `Lock.hs` の静的確認（前回のまま） |
| H-02：外部 action のタグ参照 | 継続（CI-03） | 全 `uses:` がタグ、SHA 固定なし |

## 検証コマンド

リポジトリのルートで実行する。`$S` は OS の一時領域である。

```sh
cabal build golem golem-emet golem-lsp golem-wasm:lib:golem-wasm golem-pdf golem-preflight
sh docs/audits/2026-11-09-evidence/make-fixtures.sh "$PWD" "$S/fx"
# the Emet probe, adapted to runPrim's new "room" argument (docs/adr/0223)
cabal exec -- ghc -O0 -rtsopts -hide-all-packages \
  -package base -package text -package golem-emet-0.1.0 \
  -package golem-eval-0.1.0 -package golem-syntax-0.1.0 \
  -outputdir "$S/obj/emet" -o "$S/bin/emet-probe" docs/audits/2026-11-09-evidence/emet-probe.hs
# the frame probe, against Golem.Wasm.Frame alone (base and bytestring)
ghc-9.10.3 -O1 -rtsopts -XGHC2021 -XLambdaCase -XOverloadedStrings -XDerivingStrategies -XImportQualifiedPost \
  -imodules/golem-wasm/src -outputdir "$S/obj/frame" -o "$S/bin/frame-probe" docs/audits/2026-11-09-evidence/frame-probe.hs
# the content-stream probe, against Golem.Pdf.Import (golem-pdf)
cabal exec -- ghc -O2 -rtsopts -hide-all-packages -package base -package bytestring \
  -package golem-pdf-0.1.0 -outputdir "$S/obj/content" -o "$S/bin/content-probe" docs/audits/2026-11-09-evidence/content-probe.hs
# the CLI linked with -rtsopts, from the same Main.hs (unit ids from plan.json)
cabal exec -- ghc -O1 -threaded -rtsopts "-with-rtsopts=-N" \
  -XDerivingStrategies -XLambdaCase -XOverloadedStrings -XGHC2021 -hide-all-packages \
  -package base -package bytestring -package containers -package directory -package filepath \
  -package golem-doc-0.1.0 -package golem-driver-0.1.0 -package golem-eval-0.1.0 -package golem-fmt-0.1.0 \
  -package golem-lsp-0.1.0 -package golem-project-0.1.0 -package golem-parser-0.1.0 -package golem-plugin-0.1.0 \
  -package golem-syntax-0.1.0 -package-id ptprs-pplctv-0.19.0.0-5e7c932f -package text -package-id d-1.3.16.1-95c685f7 \
  -outputdir "$S/obj/cli" -o "$S/bin/golem-rtsopts" modules/golem-cli/app/Main.hs
R=docs/audits/2026-11-09-evidence/run-limited.sh
for m in cost control take length replace join concat append; do $R 60 "$S/bin/emet-probe" $m +RTS -M256m -RTS; done
for n in empty 10000 20000 40000 80000 160000; do $R 60 "$S/bin/frame-probe" $n +RTS -M256m -RTS; done
$R 60 "$S/bin/content-probe" +RTS -M2g -RTS
(cd "$S/fx/proj-max" && $R 300 "$S/bin/golem-rtsopts" build --target pdf +RTS -M1g -s -RTS)
```

実行記録は [2026-11-09-evidence/](2026-11-09-evidence/) にある。記録の中の一時領域のパスは `DEST` に置き換えた。`length`・`replace`・内容ストリームの `deep-nums` はヒープを多く使うので、再実行にも時間とヒープの両方の制限を付ける。CI とスクリプトの読みは補助エージェントが行った。

## 限界と優先順位

1. rc4 のタグを止める指摘はない。前回の中・低の問題（E-01、E-02、T-01、W-01、W-02）はすべて直った。
2. T-02（上限内の表のメモリ）、CI-01（release.yml の `actions: write` と [ADR 0228](../adr/0228-keep-the-ci-caches-under-the-10-gb-limit.md) の記述のずれ）は、必要なら ADR で扱う。
3. L-01（手元の Wasmtime を更新して再リンク）、CI-02／CI-03（キャッシュの再ハッシュ、外部 action の SHA 固定）、I-01（LSP の semantic tokens のスレッドの上限）を引き続き検討する。

今回実施していないのは、golem.wasm の実際のビルドと wasm の中での測定、実際の LSP セッションへの DoS 試験と [ADR 0207](../adr/0207-run-golem-emet-test-one-test-at-a-time-under-the-watchdog.md) の不具合の再現、Wasm プラグインの実行、全テストスイート、全依存関係の CVE 照合、フォントと PDF の取り込みの fuzzing、全ブラウザーでの SVG と HTML の検証、`serve.mjs`・`webdriver.mjs` の HTTP 越しの動的検証（サンドボックスがポートの bind を拒む）、[ADR 0204](../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md) のテストだけの列挙の確認である。監査レポートは `scripts/ci/textlint.sh` の対象外であり、textlint は実行していない。
