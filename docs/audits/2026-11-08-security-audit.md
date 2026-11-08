# 脆弱性診断（2026-11-08）

## 結論

前回（[2026-11-06](2026-11-06-security-audit.md)）の Emet の 2 件は直っていない。今回新しく再現したのは、表の上限の中に収まる 5 MB の CSV で PDF のビルドが 2.9 GB の常駐メモリを使う問題（T-01）と、wasm の入力フレームの読み込みがファイル数の二乗の時間になる問題（W-01）である。[ADR 0182](../adr/0182-external-links.md) のリンク、[ADR 0199](../adr/0199-pdf-typesetting-as-wasm-reactor.md) のパスの正規化、[ADR 0187](../adr/0187-inline-language-switch.md) の言語タグ、取得スクリプトの SHA-256 固定、ワークフローの権限は、再現入力と静的確認のどちらでも問題を見つけなかった。

| ID | 重大度 | 問題 | 確認結果 |
| --- | --- | --- | --- |
| E-01 | 中（前回から継続） | `List.range` の長さが `Int` に収まらず、手数制限を迂回する | 前回の再現コードを今回のコミットで再コンパイルして同じ結果。コードに変更なし |
| E-02 | 中（前回から継続） | `String.replace` が手数を確認する前に巨大な結果を確保する | 同上。256 MiB のヒープ上限で終了 |
| T-01 | 中 | [ADR 0043](../adr/0043-table-file-size-limits.md) の上限（10,000 行、256 セル）に収まる表で、PDF のビルドが数 GB を割り当てる | 5 MB の CSV で常駐 2.87 GB、割り当て 96 GB、57 秒。1 GiB の上限では 5,000 行で停止 |
| W-01 | 低 | wasm の入力フレームの重複検査がファイル数の二乗 | 40,000 ファイル（0.6 MB）で 16 秒、80,000 で 60 秒超 |
| W-02 | 情報 | 入力フレームは空のパス `""` を正規化済みとして受け付ける | `readFiles` で確認 |
| L-01 | 情報（前回から継続） | 取得設定は Wasmtime 49.0.5 だが、手元の取得済み依存は 49.0.2 のまま | `third_party/wasmtime/VERSION` を照合 |
| CI-01 | 情報 | `ci.yml` の determinism ジョブの checkout に `persist-credentials: false` がない | 前回の監査の後に足された checkout。秘密を持たず、信頼できないコードを動かさないジョブ |
| I-01 | 情報 | 言語サーバーは semantic tokens の要求ごとにスレッドを立てて構文解析する。aarch64 の GHC の不具合（[ADR 0207](../adr/0207-run-golem-emet-test-one-test-at-a-time-under-the-watchdog.md) 草稿）に当たる経路 | コードを読んだ。LSP への DoS は実証していない |
| I-02 | 情報 | `manifest.toml` と `style.toml` がルート外へのシンボリックリンクでも読む（[ADR 0199](../adr/0199-pdf-typesetting-as-wasm-reactor.md) が「従来どおり」と明記） | CLI で再現。診断にしか影響しない |
| I-03 | 情報 | `scripts/wasm/run.mjs` はディレクトリの下のシンボリックリンクをたどって読む | コードを読んだ。CI の fixture にしか使わない |

製品コードの修正は行っていない。前回レポートを上書きせず、現在の状態をこの記録に残す。

## 対象・脅威モデル・方法

- 対象コミット：`bcbe71402204b777d8631c56e90b5f44b3662574`（origin/main）。ソースへのリンクはこのコミットに固定した。
- 環境：macOS / aarch64、GHC 9.10.3（`cabal build golem golem-emet golem-lsp --offline`）、64 ビットの `Int`。cabal は Hackage の索引のキャッシュを `~/.cabal` に書き直す必要があり、サンドボックスの中では失敗したので、ビルドと再現コードのコンパイルだけサンドボックスの外で行った。負荷試験はすべてサンドボックスの中で行った。
- 作業はブランチ `audit-1108` の worktree で行い、追跡済みファイルを変えていない。push、pull-req、issue は作っていない。
- 攻撃者が `.gm`、`.emet`、`manifest.toml`、`style.toml`、図版、表のファイル、参考文献、フォント、プラグインを提供し、利用者が `golem build`／`check`／`fmt`／`preflight` を実行する、LSP で開く、またはホストのページが `golem.wasm` にメモリ上のファイルを渡す状況を想定した。供給網と CI（ワークフロー、取得スクリプト、cabal の固定）も対象にした。
- 前回（`50b9fca8`）からの差分は 327 コミット、582 ファイルである。rc4 以降の変更、とくに [ADR 0182](../adr/0182-external-links.md)、[0183](../adr/0183-tagged-pdf-and-pdf-a.md)、[0185](../adr/0185-project-wide-variables.md)、[0186](../adr/0186-fmt-table-files.md)、[0187](../adr/0187-inline-language-switch.md)、[0195](../adr/0195-page-start-positions-of-pdf.md)、[0199](../adr/0199-pdf-typesetting-as-wasm-reactor.md)、[0202](../adr/0202-packages-that-do-not-build-for-wasm.md)、[0203](../adr/0203-generated-modules-instead-of-template-haskell-in-golem-driver.md) と、Emet の評価器、LSP、資源の上限を中心に読んだ。
- 負荷試験の各プロセスには GHC RTS のヒープ上限（`+RTS -M256m` から `-M4g`）と、[`run-limited.sh`](2026-11-08-evidence/run-limited.sh) による外部からの時間制限（子プロセスを `kill` する。`timeout` は入っていない）を付けた。自分で起動した子プロセス以外は停止させていない。
- 配布される `golem` は `-rtsopts` なしでリンクされ、`+RTS -M` を受け付けない。そこで、同じ `modules/golem-cli/app/Main.hs` を同じパッケージに対して `-threaded -rtsopts -with-rtsopts=-N` でリンクし直した `golem-rtsopts` を CLI の試験に使った。製品のビルド設定は変えていない。
- Python はツールの一時実行にも使わなかった。成果物にシェルスクリプトと Haskell の再現コードだけを含める。

この診断は重点レビューであり、差分全体、全依存ライブラリ、全ターゲットの網羅的な安全性検証ではない。

## E-01、E-02：Emet の手数制限（前回から継続）

[`Prim.hs:41–43`](https://github.com/tett23/golem/blob/bcbe71402204b777d8631c56e90b5f44b3662574/modules/golem-emet/src/Golem/Emet/Prim.hs#L41-L43) の `List.range`、[`Prim.hs:62–64`](https://github.com/tett23/golem/blob/bcbe71402204b777d8631c56e90b5f44b3662574/modules/golem-emet/src/Golem/Emet/Prim.hs#L62-L64) の `String.replace`、[`Prim.hs:81`](https://github.com/tett23/golem/blob/bcbe71402204b777d8631c56e90b5f44b3662574/modules/golem-emet/src/Golem/Emet/Prim.hs#L81) の `text`、[`Eval.hs:327–328`](https://github.com/tett23/golem/blob/bcbe71402204b777d8631c56e90b5f44b3662574/modules/golem-emet/src/Golem/Emet/Eval.hs#L327-L328) の加算、[`Eval.hs:173–174`](https://github.com/tett23/golem/blob/bcbe71402204b777d8631c56e90b5f44b3662574/modules/golem-emet/src/Golem/Emet/Eval.hs#L173-L174) の判定は、前回と同じである。`git log 50b9fca8..HEAD -- modules/golem-emet` にある変更は [ADR 0182](../adr/0182-external-links.md)、[0187](../adr/0187-inline-language-switch.md)、[0200](../adr/0200-figures-and-listings-without-numbers.md) の追加だけで、コストの計算には触れていない。

前回の [再現コード](2026-11-08-evidence/emet-probe.hs)（2026-11-06 の `emet-probe.hs` の写し）を今回のコミットのパッケージに対してコンパイルし、ヒープ上限 256 MiB、30 秒で走らせた。[実行記録](2026-11-08-evidence/emet-recheck.txt) は前回と同じである。

| モード | 結果 |
| --- | --- |
| `cost` | 2^63 の範囲のコストが -9,223,372,036,854,775,808、2^64 が 0 |
| `control` | `List.range 1 100000001` は E04100（100,000,004 手） |
| `take` | 2^64 の範囲から 3 つ取る関数が 7 手で `[1,2,3]` を返す |
| `length` | `Heap exhausted`、終了コード 251 |
| `replace` | 40,000 文字の引数から `Heap exhausted`、終了コード 251 |

`String.join`（53 行）、`String.fromChars`（51 行）、`List.concat`（44 行）も結果を作ってから長さを数える同じ形だが、今回も個別には再現していない。修正案は前回のとおりである。`docs/roadmap.md` にもこの 2 件の記載はなく、ADR の草稿もない。

## T-01：上限の中の表で PDF のビルドが数 GB を使う

### 根拠

[ADR 0043](../adr/0043-table-file-size-limits.md) は表のファイルを 16 MiB、10,000 行、1 行 256 セルまでとし、[`File.hs:1655–1664`](https://github.com/tett23/golem/blob/bcbe71402204b777d8631c56e90b5f44b3662574/modules/golem-eval/src/Golem/Eval/File.hs#L1655-L1664) がその値を持つ。行の数と 1 行のセルの数は別々に検査され、セルの総数（最大 2,560,000）には上限がない。

PDF では、[`Flow.hs:2374`](https://github.com/tett23/golem/blob/bcbe71402204b777d8631c56e90b5f44b3662574/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L2374) が `composeTable` で表の全体を組み、[`Flow.hs:2000–2020`](https://github.com/tett23/golem/blob/bcbe71402204b777d8631c56e90b5f44b3662574/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L2000-L2020) がセルごとに `composeInlines` を呼んでから `layoutTable` に渡す。列の最小の幅が使える幅に収まらないことの検査（G07041、[`Flow.hs:2166–2170`](https://github.com/tett23/golem/blob/bcbe71402204b777d8631c56e90b5f44b3662574/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L2166-L2170)）は、その後の番号付けの段階にある。

### 再現結果

[`make-fixtures.sh`](2026-11-08-evidence/make-fixtures.sh) で、fixture の kanikosen（B6 判、縦組み）に 1 文字のセルからなる CSV を `@table` で置いた。[実行記録](2026-11-08-evidence/table-scaling.txt) と [上限の確認](2026-11-08-evidence/table-probe.txt) から抜粋する。`golem build --target pdf` に `+RTS -s` を付けて測った。

| 表 | バイト数 | ヒープ上限 | 結果 |
| --- | --- | --- | --- |
| 1 行 4,000,001 セル | 4.0 MB | 1 GiB | G02088（セルの数）、1 秒 |
| 2,000,000 行 2 セル | 8.0 MB | 1 GiB | G02088（行の数）、1 秒 |
| 10,000 行 8 セル | 160 KB | 1 GiB | 成功、常駐 305 MB、割り当て 19 GB、8 秒、PDF 11.8 MB |
| 10,000 行 64 セル | 1.3 MB | 1 GiB | G07041、常駐 726 MB、割り当て 24 GB、13 秒 |
| 2,500 行 256 セル | 1.3 MB | 1 GiB | G07041、15 秒 |
| 5,000 行 256 セル | 2.6 MB | 1 GiB | `Heap exhausted`、終了コード 251、14 秒 |
| 10,000 行 256 セル | 5.1 MB | 4 GiB | G07041、常駐 2.87 GB、割り当て 96 GB、57 秒 |
| 10,000 行 256 セル、`--target html` | 5.1 MB | 1 GiB | 成功、5 秒 |

256 セルの表は B6 判に収まらず最終的に G07041 で拒否されるが、拒否の前に全セルが組まれる。セルあたりの常駐は 1.1〜3.8 KB で、セルの総数に比例する。HTML は同じ表を 5 秒で書く。

### 影響と修正案

[ADR 0043](../adr/0043-table-file-size-limits.md) の上限は「本の表としては十分」と判断して決めたもので、上限の中の入力が PDF のビルドで数 GB を使うことは想定に入っていない。過去の監査の基準（ふつうの原稿より小さい入力で数 GB を割り当てる）で中とした。利用者のマシンでメモリが足りなければ、ビルドは `Heap exhausted` か OS の圧迫で止まる。LSP は PDF を組まないので、この経路には当たらない。

対処は仕様を変えるので ADR が要る。候補は、セルの総数の上限（たとえば 100,000）を G02088 に足すこと、または列の最小の幅の検査をセルを組む前（各列の最も長い語の幅で足りる）に移し、収まらない表に時間と割り当てを使わないことである。両方を入れるのが簡単である。回帰テストは、上限ぎりぎりの表を組む時間と割り当てを [ADR 0073](../adr/0073-time-bounds-in-tests.md) の時間の上限の中に限る。

## W-01：wasm の入力フレームの重複検査が二乗の時間になる

[`Frame.hs:63`](https://github.com/tett23/golem/blob/bcbe71402204b777d8631c56e90b5f44b3662574/modules/golem-wasm/src/Golem/Wasm/Frame.hs#L63) は、読んだパスを `seen` のリストに積み、`path `elem` seen` で重複を調べる。ファイル数 n に対して n^2 / 2 回の文字列比較になる。

[再現コード](2026-11-08-evidence/frame-probe.hs) は、`Golem.Wasm.Frame` を base と bytestring だけに対して GHC 9.10.3 で直接コンパイルし、1 バイトのファイル n 個のフレームを `writeFiles` で作って `readFiles` の時間を測る。[実行記録](2026-11-08-evidence/frame-probe.txt)（ヒープ上限 256 MiB、60 秒）は次のとおりである。

| ファイル数 | フレームの大きさ | `readFiles` の時間 |
| --- | --- | --- |
| 10,000 | 139 KB | 0.65 秒 |
| 20,000 | 289 KB | 3.0 秒 |
| 40,000 | 589 KB | 16.0 秒 |
| 80,000 | 1.2 MB | 60 秒で停止 |

ネイティブの測定であり、wasm の中ではさらに遅い。ホストのページが攻撃者のプロジェクトのファイルをそのまま渡すと、1 MB ほどの入力で `golem_build_pdf` がビルドに入る前に止まる。ホストがファイル数を限れば防げるので低とした。`Data.Set` で重複を調べれば n log n になる。`readFiles` の UTF-8 の厳密さ、長さの検査（`toInteger` で比較するので wasm32 でも折り返さない）、`..` と絶対パスの拒否は確認した。

## W-02：空のパスを受け付ける

[`Frame.hs:115–121`](https://github.com/tett23/golem/blob/bcbe71402204b777d8631c56e90b5f44b3662574/modules/golem-wasm/src/Golem/Wasm/Frame.hs#L115-L121) の `isNormalized` は、空の文字列を区切りで分けて空の区間を捨てた結果が空の文字列なので、`""` を正規化済みと判定する。[同じ再現コード](2026-11-08-evidence/frame-probe.hs) の `empty` は `Right [("","x")]` を返した。golem-project の `normalizeRelative`（[`Paths.hs:32–42`](https://github.com/tett23/golem/blob/bcbe71402204b777d8631c56e90b5f44b3662574/modules/golem-project/src/Golem/Project/Paths.hs#L32-L42)）も同じく `Right ""` を返す。`memoryFiles` の表にキー `""` が入るだけで、どの参照も空のパスを引かないので、影響は見つけていない。フレームの仕様が「パスは `normalizeRelative` の結果に等しい」と書くので、記録にとどめる。

## L-01：手元の Wasmtime の版（前回から継続）

`scripts/fetch-wasmtime.sh` は 49.0.5 を指定するが、この作業環境の `third_party/wasmtime/VERSION` と `include/wasmtime.h` は 49.0.2 のままだった。`cabal.project.local` はそのディレクトリを参照し、`cabal build` は取得スクリプトを呼ばない。前回と同じ注意である。リリースの smoke ジョブは `scripts/check-wasmtime-linked.sh` で配布物の `libwasmtime.a` の版を確かめるので、配布物には及ばない。今回も Wasm は実行していない。

## CI-01：determinism ジョブの checkout

[`ci.yml:702–706`](https://github.com/tett23/golem/blob/bcbe71402204b777d8631c56e90b5f44b3662574/.github/workflows/ci.yml#L702-L706) の determinism ジョブの `actions/checkout@v7` だけに `persist-credentials: false` がない（25 の checkout のうち 24 にはある）。2026-10-24 の監査の時点ではこのジョブに checkout がなく、その後に足された。ジョブの権限は `contents: read` だけで、動かすのは `diff` だけなので情報とした。ほかの checkout にそろえる。

このほか、ワークフローには `pull_request_target` がなく、`run:` の中で `${{ github.event.* }}` を展開する箇所はなく（`env:` を経由する）、`release.yml` の書き込み権限は `release` ジョブだけにある。wasm ジョブのキャッシュ（`third_party/ghc-wasm`、`third_party/hosttools`、`dist-wasm`）は `restore-keys` の前方一致で復元し、復元した alex と happy を実行するが、GitHub のキャッシュは pull-req から main のキャッシュを書けないので、汚染には main への書き込みが要る。外部 action のタグ参照（H-02）は続いている。

## I-01：言語サーバーの同時の構文解析

[`Server.hs:207–215`](https://github.com/tett23/golem/blob/bcbe71402204b777d8631c56e90b5f44b3662574/modules/golem-lsp/src/Golem/Lsp/Server.hs#L207-L215) は、semantic tokens の要求ごとに `forkIO` でスレッドを立て、`.gm` か `.emet` の全文を構文解析する。スレッドの数と同時の要求の数に上限はない。要求を出すのはエディターであり、攻撃者が直接は増やせない。

[ADR 0207](../adr/0207-run-golem-emet-test-one-test-at-a-time-under-the-watchdog.md) の草稿（未コミット。`.claude/worktrees/adr-drafts-1108/docs/adr/0207-run-golem-emet-test-one-test-at-a-time-under-the-watchdog.md`）は、aarch64 の GHC で `.emet` の構文解析を複数のスレッドで同時に走らせると、0.1% ほどの率でヌルのクロージャーを適用して落ちるか止まることを記録し、`golem lsp` で 1,200 回は再現しなかったが起きないとは言えないとしている。安全性の観点では、落ちれば言語サーバーが終わり、エディターが立て直す。止まれば診断が更新されなくなる。どちらもローカルの可用性の問題であり、メモリの破壊が攻撃者の入力で制御できる形には見えない（落ちる場所はランタイムのスケジューラーで、入力の内容に依らない）。[ADR 0207](../adr/0207-run-golem-emet-test-one-test-at-a-time-under-the-watchdog.md) が roadmap に残す「本番の経路」の未決事項に、semantic tokens のスレッドの上限（たとえば一つの文書につき最新の要求だけを処理する）を候補として足すことを勧める。根本原因は調べ直していない。

## I-02：ルート外へのリンクの manifest.toml と style.toml

[`Driver.hs:338–343`](https://github.com/tett23/golem/blob/bcbe71402204b777d8631c56e90b5f44b3662574/modules/golem-driver/src/Golem/Driver.hs#L338-L343) の `readMaybeBytes` は、`manifest.toml` と `style.toml` を `Missing` でなければ読み、ルート外へのリンクでも読む（注釈が「従来どおり」と明記する）。[再現](2026-11-08-evidence/symlink-probe.txt) では、`style.toml` をルート外のファイルへのシンボリックリンクにしたプロジェクトが `golem build --target pdf` で PDF を書いた。章、図版、表、フォントは `resolveInRoot` が正規化して拒むので、読めるのはこの 2 つの固定の名前だけである。読まれた内容は TOML として解釈され、診断の文面にしか現れない。情報とした。

## I-03：run.mjs のシンボリックリンク

[`run.mjs:73–84`](https://github.com/tett23/golem/blob/bcbe71402204b777d8631c56e90b5f44b3662574/scripts/wasm/run.mjs#L73-L84) の `filesOf` は `readdir` の項目のうちディレクトリでないものを `readFile` で読むので、シンボリックリンクの先を読む。CI は fixture のディレクトリにしか使わない。ブラウザーのホストはこのスクリプトを使わないので、情報とした。

## 問題のなかった項目

- **[ADR 0182](../adr/0182-external-links.md) のリンク**：[`Url.hs:36–42`](https://github.com/tett23/golem/blob/bcbe71402204b777d8631c56e90b5f44b3662574/modules/golem-doc/src/Golem/Doc/Url.hs#L36-L42) は http と https だけを許し、空白、制御文字、`"`、`<`、`>`、`\` を含む URL を G02125 で拒む。[再現](2026-11-08-evidence/link-probe.txt) で `javascript:` と `data:` は G02126、`file:///etc/passwd`、`<script>`、`\`、`"` を含むものは G02125 になり、成果物は書かれなかった。通る URL では、PDF の `/URI` は [`asciiUri`](https://github.com/tett23/golem/blob/bcbe71402204b777d8631c56e90b5f44b3662574/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L221-L225) で ASCII に直され、`(` と `)` は [`escape`](https://github.com/tett23/golem/blob/bcbe71402204b777d8631c56e90b5f44b3662574/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L441) が `\(`、`\)` にした。HTML の `href` は `escapeXml` を通り、`&` は `&amp;` になった。関数とプラグインの IR のリンクも同じ `checkUrl` を通る（`Validate.hs:185`）。
- **[ADR 0199](../adr/0199-pdf-typesetting-as-wasm-reactor.md) のパス**：絶対パスの図版は G02060 で拒まれ、PDF は書かれない（[再現](2026-11-08-evidence/fig-probe.txt)）。評価の段階に誤りがあると [`Driver.hs:321`](https://github.com/tett23/golem/blob/bcbe71402204b777d8631c56e90b5f44b3662574/modules/golem-driver/src/Golem/Driver.hs#L321) が本を作らないので、[`Flow.hs:2700`](https://github.com/tett23/golem/blob/bcbe71402204b777d8631c56e90b5f44b3662574/modules/golem-typeset/src/Golem/Typeset/Flow.hs#L2700) の `fromRight path` が正規化できないパスをそのまま読む経路には届かない。ただしこの `fromRight` は、評価と組版の整合に頼る書き方であり、`Left` を失敗にするほうが安全である。`memoryFiles` は表の引きだけで、シンボリックリンクも実ファイルもない。
- **wasm の reactor**：`golem_alloc` は長さを 4 バイト前に置き、`golem_result_len` と `golem_free` はそれを読む（[`Main.hs:41–55`](https://github.com/tett23/golem/blob/bcbe71402204b777d8631c56e90b5f44b3662574/modules/golem-wasm/app/Main.hs#L41-L55)）。長さはホストが渡すので、ホストの誤り以外で越えられない。`buildPdfInMemory` は `optParallel = False` で一つのスレッドで組む。`run.mjs check` は同じ入力を同じインスタンスで二度、新しいインスタンスで一度組んで同じバイト列になることを確かめる。golem.wasm 自体はここでは作っていない（x86-64 Linux の道具立てが要る）。
- **[ADR 0187](../adr/0187-inline-language-switch.md) の言語**：`[lang]` の値は `isLanguageTag`（BCP 47 の形）で検査され、HTML では `escapeXml`、PDF の `/Lang` では `pdfTextString` を通る。
- **[ADR 0183](../adr/0183-tagged-pdf-and-pdf-a.md) のタグ付き PDF**：`/Alt`、`/ActualText`、`/Lang`、`/Contents` は `pdfTextString` で書かれ、印字可能な ASCII 以外は UTF-16 の 16 進になる。構造木の大きさはページの要素の数に比例し、20,000 の注（[記録](2026-11-08-evidence/load-probe.txt)、34 秒）と 2,000 の図版（3 秒）で測定した範囲では問題を見つけなかった。
- **[ADR 0203](../adr/0203-generated-modules-instead-of-template-haskell-in-golem-driver.md) の `gen-embedded.sh`**：`\` と `"` だけをエスケープし、制御文字と NUL を拒む。埋め込むのはリポジトリの `VERSION` と `docs/diagnostics.md` で、攻撃者の入力ではない。
- **[ADR 0202](../adr/0202-packages-that-do-not-build-for-wasm.md) の取得**：`fetch-wasm-packages.sh` は Hackage のアーカイブを SHA-256 で確かめてから展開し、リポジトリのパッチを当てる。`fetch-ghc-wasm.sh` は 5 つのアーカイブを SHA-256 と autogen.json の SRI の両方で確かめ、`cabal.th.config` もコミットと SHA-256 で固定する。`Golem.Pdf.Sha1` は文書 ID の UUID v5 にだけ使い、安全性には関わらない。
- **[ADR 0186](../adr/0186-fmt-table-files.md) の `golem fmt`**：引数なしの表のファイルは `resolveInRoot` で解決し、ルート外へのリンクは整形しない。
- **[ADR 0195](../adr/0195-page-start-positions-of-pdf.md) の pages.json**：位置の JSON を書くだけで、入力の文字列は `jsonString` を通る。
- **前回の SVG と CSL-JSON**：`modules/golem-svg/src` に前回からの変更はなく、2026-11-05 の `svg-probe.hs` は 5 つの入力をすべて検出した。CSL-JSON の G03108 は golem-bibliography の `CslUnwritable` が担い、Driver の呼び出しに変更はない。
- **プラグインの取得（H-01）**：`Lock.hs:132–141` の `httpLbs` による全本文の読み込みは続いている。

## 前回指摘の再確認

| 前回の項目 | 現在の状態 | 今回の確認 |
| --- | --- | --- |
| E-01：`List.range` の整数オーバーフロー | 未修正 | 前回の再現コードを今回のコミットで再コンパイルし、同じ結果 |
| E-02：`String.replace` の事前確認なし | 未修正 | 同上。256 MiB のヒープで終了コード 251 |
| L-01：手元の Wasmtime が 49.0.2 | 継続 | `third_party/wasmtime/VERSION` と `wasmtime.h` を照合 |
| V-01：Wasmtime 49.0.2 の逸脱 | 取得設定は 49.0.5、リリースの smoke が版を検査 | `fetch-wasmtime.sh`、`check-wasmtime-linked.sh`、`release.yml` を読んだ |
| V-02：SVG の検査漏れ | 修正済み | `svg-probe.hs` を再実行 |
| V-03：CSL-JSON の制御文字 | 修正済み | コードに変更がないことを `git diff` で確認 |
| H-01：取得・コンパイルの資源上限 | 継続 | `Lock.hs` を静的確認 |
| H-02：外部 action のタグ参照 | 継続 | 13 種の action がすべてタグ参照 |

## 検証コマンド

リポジトリのルートで実行する。`$S` は OS の一時領域である。

```sh
cabal build golem golem-emet golem-lsp --offline
sh docs/audits/2026-11-08-evidence/make-fixtures.sh "$PWD" "$S"
# the Emet probe of 2026-11-06 against the packages of this commit
cabal exec --offline -- ghc -O0 -rtsopts -hide-all-packages \
  -package base -package text -package golem-emet-0.1.0 \
  -package golem-eval-0.1.0 -package golem-syntax-0.1.0 \
  -outputdir "$S/obj/emet" -o "$S/bin/emet-probe" docs/audits/2026-11-08-evidence/emet-probe.hs
# the frame probe, against Golem.Wasm.Frame alone (base and bytestring)
ghc-9.10.3 -O1 -rtsopts -XGHC2021 -XLambdaCase -XOverloadedStrings -XDerivingStrategies -XImportQualifiedPost \
  -imodules/golem-wasm/src -outputdir "$S/obj/frame" -o "$S/bin/frame-probe" docs/audits/2026-11-08-evidence/frame-probe.hs
# the CLI linked with -rtsopts, from the same Main.hs (the unit ids of uuid and
# optparse-applicative are those of dist-newstyle/cache/plan.json)
cabal exec --offline -- ghc -O1 -threaded -rtsopts "-with-rtsopts=-N" \
  -XDerivingStrategies -XLambdaCase -XOverloadedStrings -XGHC2021 -hide-all-packages \
  -package base -package bytestring -package containers -package directory -package filepath \
  -package golem-doc-0.1.0 -package golem-driver-0.1.0 -package golem-eval-0.1.0 -package golem-fmt-0.1.0 \
  -package golem-lsp-0.1.0 -package golem-project-0.1.0 -package golem-parser-0.1.0 -package golem-plugin-0.1.0 \
  -package golem-syntax-0.1.0 -package-id ptprs-pplctv-0.19.0.0-5e7c932f -package text -package-id d-1.3.16.1-95c685f7 \
  -outputdir "$S/obj/cli" -o "$S/bin/golem-rtsopts" modules/golem-cli/app/Main.hs
R=docs/audits/2026-11-08-evidence/run-limited.sh
for m in cost control take length replace; do $R 30 "$S/bin/emet-probe" $m +RTS -M256m -RTS; done
for n in empty 10000 20000 40000 80000; do $R 60 "$S/bin/frame-probe" $n +RTS -M256m -RTS; done
(cd "$S/proj-max" && $R 300 "$S/bin/golem-rtsopts" build --target pdf +RTS -M4g -s -RTS)
(cd "$S/proj-link" && $R 60 "$S/bin/golem-rtsopts" build --target pdf --target html +RTS -M1g -RTS)
runghc-9.10.3 -XGHC2021 -XLambdaCase -XOverloadedStrings -XDerivingStrategies \
  -imodules/golem-svg/src docs/audits/2026-11-05-evidence/svg-probe.hs
```

実行記録は [2026-11-08-evidence/](2026-11-08-evidence/) にある。記録の中の一時領域のパスは `DEST` に置き換えた。`length`、`replace`、5,000 行の表はヒープ枯渇を観測するモードであり、再実行にも時間とヒープの両方の制限を付ける。同梱の再現コードは監査の観測用であり、製品の回帰テストの代わりではない。

## 限界と優先順位

1. E-01 と E-02 を直す。前回から 2 日の間に修正も ADR の草稿もなく、原稿から呼べる関数だけで起きる。
2. T-01 のセルの総数の上限と、幅の検査の前倒しを ADR で決める。
3. W-01 の重複検査を `Set` にする。仕様は変わらないので ADR は要らない。
4. CI-01 の checkout をそろえる。
5. 手元の Wasmtime を更新し、外部 action の SHA 固定と取得サイズの上限を引き続き検討する。

今回実施していないのは、golem.wasm の実際のビルドと wasm の中での測定、実際の LSP セッションへの DoS 試験と [ADR 0207](../adr/0207-run-golem-emet-test-one-test-at-a-time-under-the-watchdog.md) の不具合の再現、Wasm プラグインの実行、全テストスイート、全依存関係の CVE 照合、フォントと PDF の取り込みの fuzzing、全ブラウザーでの SVG と HTML の検証、Emet のすべてのプリミティブの個別の試験、[ADR 0204](../adr/0204-pagination-invariants-by-exhaustive-small-inputs.md) のテストだけの列挙の確認である。監査レポートは `scripts/ci/textlint.sh` の対象外であり、textlint は実行していない。
