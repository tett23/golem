# 脆弱性診断（2026-11-05）

## 結論

最優先で Wasmtime を更新する必要がある。Golem が固定する 49.0.2 は、aarch64 でサンドボックスを逸脱できる CVE-2026-115893 の対象である。公式アドバイザリの影響条件と、Golem の版・コンパイラー設定・呼び出し経路が一致する。攻撃コードによる逸脱の実証はしていない。

このほか、前回から残る SVG の検査漏れと CSL-JSON の制御文字を調べた。今回の診断は静的レビューと限定した再現試験であり、全コード・全依存関係の安全性を保証するものではない。

## 対象と方法

- 対象コミット：`89ae4b4142c58cb8937e10c18c0e664280397547`。
- 環境：macOS / aarch64、GHC 9.10.3。追跡済みファイルに開始時の変更はなかった。既存の未追跡 `.claude/` は対象外。
- 想定する攻撃者：原稿・設定・図版・参考文献・Wasm を提供できる第三者。利用者がそのプロジェクトをビルドする、または成果物を閲覧することを前提とする。
- 主な確認箇所：プロジェクトのパス解決、出力先の削除と書き込み、HTML/EPUB の生成、SVG の検査、プラグインの取得・ハッシュ照合・Wasm ホスト、LSP、PDF 取り込みの上限、CI/release の権限と外部 action。
- 既存の [2026-10-24 の監査](../audits/2026-10-24-security-audit.md) と [roadmap](../roadmap.md) を照合した。既知の項目を新規発見とは扱っていない。
- 公開情報は 2026-11-05 に Wasmtime の公式 GitHub Security Advisories を確認した。検索結果の重大度だけで判定せず、個々の影響版と必要機能を照合した。
- アプリケーションのコードは修正していない。再現用の入力と実行記録を、このレポートに添付する。

## 所見一覧

| ID | 重大度 | 内容 | 確認の程度 |
| --- | --- | --- | --- |
| V-01 | 高（上流評価 Critical / CVSS 3.1 9.9） | Wasmtime 49.0.2 の aarch64 向け既知サンドボックス逸脱 | 公式情報・版・使用経路を照合。逸脱の実証なし |
| V-02 | 低 | SVG の外部参照が能動コンテンツ検査を通る | 検査関数と CLI で再現。既知 C9 の再確認 |
| V-03 | 低 | CSL-JSON の制御文字が XHTML に残る | CLI で HTML/EPUB の出力を再現。既知 C10 の再確認 |
| H-01 | 情報 | ダウンロードと Wasm コンパイルの資源上限が不足 | 静的確認。資源枯渇の負荷試験なし |
| H-02 | 情報 | CI の外部 action が可変タグ参照 | 静的確認。侵害の証拠なし |

「高」は実行ユーザーの環境に影響し得るもの、「低」は閲覧などの追加条件が必要か、成果物の可用性への影響にとどまるものとする。上流の CVSS はそのまま併記し、Golem 専用のスコアを計算したとは扱わない。

## V-01：aarch64 の Wasmtime に既知のサンドボックス逸脱

### 根拠と到達経路

[`scripts/fetch-wasmtime.sh:20`](../../scripts/fetch-wasmtime.sh) は `VERSION=49.0.2` を指定する。手元の `third_party/wasmtime/include/wasmtime.h` も `WASMTIME_VERSION "49.0.2"` である。

[`golem_plugin.c:41–56`](../../modules/golem-plugin/cbits/golem_plugin.c) は既定のコンパイラーを使い、Cranelift の NaN 正規化を設定した engine で `wasmtime_module_new` を呼ぶ。aarch64 は macOS と Linux の正式な配布対象である。

[公式アドバイザリ GHSA-mghf-wjfp-p5xm](https://github.com/bytecodealliance/wasmtime/security/advisories/GHSA-mghf-wjfp-p5xm) によると、aarch64 の Cranelift は非常に多くの分岐先を持つ `br_table` を誤ってコンパイルし、サンドボックス逸脱につながり得る。49 系の影響範囲は `>=49.0.0, <49.0.4`、修正版は 49.0.4。CVE は CVE-2026-115893 である。

[`loadPluginWith:152–176`](../../modules/golem-plugin/src/Golem/Plugin.hs) はモジュールをコンパイルしてから import を検査し、ABI と説明を取得するためにコードを実行する。import の禁止や WASI の不使用は、生成した機械語の誤りへの対策にならない。fuel とメモリ制限も、正しく生成されたコードを前提とするため、この問題を解消しない。

攻撃には、悪意あるプラグインのバイト列がキャッシュにあり、そのハッシュを含む lock とプロジェクトが読み込まれる必要がある。ハッシュ照合は改ざんを防ぐが、攻撃者が用意したプラグインの無害性を保証しない。通常のビルドが勝手にプラグインをダウンロードするわけではない。

### 影響と修正案

影響を受ける aarch64 環境では、Wasm の隔離を越え、実行ユーザーの権限でファイルやプロセスに影響する可能性がある。x86-64 がこのアドバイザリに該当するとは判断していない。

49 系なら少なくとも 49.0.4 に更新する。別の公開修正も含めるため、49.0.5 以降の適切な保守版を評価する。取得用の SHA-256、ライセンス記録、キャッシュ識別、配布物をそろえて更新し、両 aarch64 配布物を再ビルドする。更新まで信頼できない Wasm の実行を避ける。

更新後はプラグインの ABI・import 拒否・fuel・メモリ上限の既存テストを実行し、実際にリンクした版も確かめる。今回は悪用コードを実行しておらず、上流の情報と到達経路に基づく判定である。

## V-02：SVG の外部参照が検査を通る

[`Active.hs:45–68`](../../modules/golem-svg/src/Golem/Svg/Active.hs) は `href`、イベント属性、`style` の CSS などを検査するが、`fill` の `url()` と、`style` を書き換える `set` を検査しない。[`Xml.hs:133–141`](../../modules/golem-svg/src/Golem/Svg/Xml.hs) は処理命令を捨てるため、`xml-stylesheet` も検査されない。

[再現プログラム](2026-11-05-evidence/svg-probe.hs) を現在のソースで動かした。[結果](2026-11-05-evidence/svg-probe.txt) は次のとおりである。

| 入力 | `activeContent` の結果 |
| --- | --- |
| `script` 要素（対照） | 検出 |
| `image href="https://example.invalid/a"`（対照） | 検出 |
| `rect fill="url(https://example.invalid/a#g)"` | `Right []` |
| `xml-stylesheet` 処理命令 | `Right []` |
| `set attributeName="style" to="fill:url(...)"` | `Right []` |

CLI でも `xml-stylesheet` と `fill` の外部参照を含む SVG が終了コード 0・diagnostic なしで HTML にコピーされ、元のバイト列と一致した。

`Right []` は検出項目なしを意味する。これは前回 C9 と同じ既知の検査範囲の不足である。SVG を文書として開くなどの追加条件で、外部参照が閲覧者の通信や表示へ影響する可能性が残る。今回ブラウザーの通信、JavaScript の実行、情報流出は実証していない。`img` として表示するだけでスクリプトが動くとは報告しない。

検査対象を表現属性・処理命令・アニメーションの変更先に広げるか、HTML/EPUB へ渡す SVG を許可リスト方式で再生成する。正常な内部参照 `url(#id)` を維持するテストと、直接開く場合のブラウザー試験を追加する。現在の仕様に列挙されていないため、対応時は拒否対象を仕様に明記する。

## V-03：参考文献の制御文字が XHTML に残る

[`Driver.hs:544–562`](../../modules/golem-driver/src/Golem/Driver.hs) の `loadBibliography` は CSL-JSON をデコードするが、XML 1.0 が許さない文字を検査しない。[`Html.hs:471–476`](../../modules/golem-html/src/Golem/Html.hs) の `EntryText` は XML の特殊文字をエスケープするだけである。

fixture の `refs.json` の引用される項目の `title` に JSON の `\u0001` を入れて CLI を実行した。ビルドは終了コード 0・diagnostic なしで完了した。HTML の 2 ページと EPUB 内の 2 ページに U+0001 が残り、Python の XML パーサーは HTML の両ページを `not well-formed (invalid token)` で拒否した。XML として正しく読めない XHTML となり、HTML/EPUB の閲覧・検証を妨げる。スクリプト実行を意味するものではない。前回 C10 と同じ既知事項である。

参考文献を読む段階で、出力へ使う文字列に共通の文字検査を適用する。対象キーと診断コードを定義し、U+0001 と ESC を拒否するテスト、通常の改行・タブ・日本語を壊さないテストを追加する。

## 追加の強化事項

### H-01：取得・コンパイルの資源上限

[`Lock.hs:123–143`](../../modules/golem-plugin/src/Golem/Plugin/Lock.hs) の HTTPS 取得は `httpLbs` で本文全体を読み、`BL.toStrict` へ変換する。アプリケーションのサイズ上限は見当たらない。さらに Wasm コンパイルは store の fuel・メモリ制限を設定する前に行われる。従って、実行時の 256 MiB 制限が取得やコンパイルにも効くとはいえない。

利用者が取得先を選ぶこと、今回は負荷試験をしていないことから、確認済みの DoS とは数えない。ストリーム読み込み中のバイト数上限、展開後サイズの上限、コンパイル用プロセスの時間・メモリ制限を検討する。過去の 2026-10-17 の監査にも取得サイズ上限なしの記載がある。

### H-02：CI の action 参照

`.github/workflows/` は `actions/checkout@v7`、`jdx/mise-action@v5` など、複数の外部 action をタグで参照する。タグが移動すると、同じ workflow でも別のコードが実行され得る。特に release ジョブには書き込み権限がある。

上流侵害や認証情報の漏えいは確認していないため、強化事項とする。外部 action を完全なコミット SHA に固定し、更新時に差分をレビューする。mise 本体の版・ハッシュ固定と action 自体の固定は別に扱う。

## 誤検出を避けるために確認した点

- 入力パスは `normalizeRelative` と `resolveInRoot` で絶対パス・ルート外参照を拒否し、シンボリックリンクを canonicalize する。
- 出力は `unsafeOutputDirs` が `build` と対象サブディレクトリを検査する。単に `removeDirectoryRecursive` があることだけで任意削除とは判定しない。同時に別プロセスがファイルを置換する競合は今回未検証。
- プラグインは HTTPS とハッシュ照合を使い、build はキャッシュだけを読む。Wasm の import、WASI、threads を許可せず、実行時には fuel・メモリ・テーブルの制限がある。
- PDF 取り込みにはストリーム・累計展開量・参照深さなどの上限がある。今回はそれらすべての迂回を試す fuzzing は実施していない。
- [GHSA-897f-g5gm-fmxm](https://github.com/bytecodealliance/wasmtime/security/advisories/GHSA-897f-g5gm-fmxm) は 49.0.2 が影響範囲外であり、V-01 とは別件。
- [GHSA-r8xh-cgf7-392j](https://github.com/bytecodealliance/wasmtime/security/advisories/GHSA-r8xh-cgf7-392j) は wasi-http が必要。Golem のホストはこの機能を提供しないので、版だけを見て脆弱としない。
- [GHSA-qw58-7h65-crq2](https://github.com/bytecodealliance/wasmtime/security/advisories/GHSA-qw58-7h65-crq2) はホストが engine をまたいだ struct 型を作る条件が必要。確認した C ホストにはその経路がない。

## 再現手順と限界

リポジトリのルートで実行する。CLI の試験は OS の一時ディレクトリに fixture を複製し、そこだけを変更する。外部サービスへのリクエストは送らない。`.invalid` の URL は検査入力としてのみ使う。

```sh
cabal build golem --offline
runghc -XGHC2021 -XLambdaCase -XOverloadedStrings -XDerivingStrategies -imodules/golem-svg/src docs/audits/2026-11-05-evidence/svg-probe.hs
sh docs/audits/2026-11-05-evidence/cli-probe.sh "$(cabal list-bin golem --offline)"
```

### 実行結果

- `cabal build golem --offline`：コンパイルとリンクを実施。初回はホーム配下のビルドログ書き込みが sandbox に拒否されたため、権限承認後に再実行し、終了コード 0（`Up to date`）を確認した。
- SVG の関数単位の試験：5 件実行。対照 2 件を検出し、外部参照の 3 件は検出されなかった。
- [CLI の実行記録](2026-11-05-evidence/cli-probe.txt)（監査のときは同じ手順を Python で書いた probe で取った。コミットの前に、リポジトリの方針に合わせてシェルスクリプトの [cli-probe.sh](2026-11-05-evidence/cli-probe.sh) に書き直し、同じ観測になることを確かめた）：CSL-JSON と SVG の問題を再現した。`build` を一時ディレクトリ外の検査用フォルダーへのリンクにした試験は G08013・終了コード 1 となり、リンク先の sentinel は `unchanged` のままだった。リンク先も同じ試験用一時領域内にある。
- 全モジュールのテストスイートは実行していない。監査記録は `scripts/ci/textlint.sh` の対象から除外されているため、textlint は実行していない。

同梱の probe は監査の観測用であり、脆弱性が直ると観測結果が変わる。製品の回帰テストの代わりではない。

今回の対象外は、全 Haskell/npm/C 依存パッケージの網羅的 CVE 照合、ネイティブフォント処理の fuzzing、実際の CI/GitHub 権限設定、全ブラウザー・EPUB リーダーでの攻撃実証である。公開情報の照合は上記の Wasmtime アドバイザリに限定した。
