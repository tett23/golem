# セキュリティ監査（2026-10-17）

この記録は、2026-10-17 の main（dcc1e54）の Golem を、信頼できない入力を処理する道具として監査した結果である。
見つかった問題の修正は、[docs/adr/0035](../adr/0035-security-hardening.md)（提案）とそのプルリクエストで行う。
修正のない項目は、確かめた範囲と残る危険を書く。

## 脅威のモデル

攻撃者は、Golem でビルドされる原稿のリポジトリを用意できるものとする。
原稿、`manifest.toml`、`style.toml`、`plugins.lock`、画像（PNG と JPEG）、フォント、CSL-JSON、取り込むコードと表、シンボリックリンクは、すべて攻撃者が書ける。
被害者は、そのリポジトリを clone して `golem build`、`golem check`、`golem preflight` を実行するか、エディタで開いて LSP を動かす人である。
Golem が書いた HTML と EPUB を読む人も、被害者になりうる。
プラグインは URL から取得し、`plugins.lock` の SHA-256 で照合する。
プラグインの作者は信頼しないが、どのプラグインを使うかは原稿の作者が決める。
LSP の相手（エディタ）と、コマンドの引数と環境変数は信頼する。

## 重大度の決め方

- **高**：ビルドするだけで、プロジェクトの外のファイルが消えるか書き換わる。
- **中**：ビルドするだけで、Golem が止まらなくなるか落ちる、出力を読む人の環境でスクリプトが動く、またはサンドボックスの上限を越えられる。
- **低**：悪用に別の条件が要るか、被害が小さい。
- **情報**：今は問題にならないが、前提が変わると問題になる。

## 見つかった問題

| 番号 | 重大度 | 問題 | 修正 | テスト |
| --- | --- | --- | --- | --- |
| S1 | 高 | `build` のシンボリックリンクで、プロジェクトの外のディレクトリを消して書く | G0813 で止める | golem-driver の SecuritySpec |
| S2 | 中 | HTML と EPUB の属性と CSS の文字列にパスと名前をエスケープせずに書く | エスケープする | golem-driver の SecuritySpec |
| S3 | 中 | PNG と JPEG の読み込みが止まらない、落ちる、際限なく展開する | 全域で有界な読み込みにする | golem-pdf の ImageSpec |
| S4 | 中 | 式の整数、`round` と `fixed` の桁数、`highlight` の範囲に上限がない | G0286 と範囲の絞り込み | golem-eval の ExprSpec と FileSpec |
| S5 | 中 | CSL-JSON の年の大きな指数で止まらない | 係数と指数で判定する | golem-driver の SecuritySpec |
| S6 | 中 | wasm のテーブルの要素の数に上限がない | 100 万を上限にする | golem-plugin の Main |
| S7 | 低 | プラグインの戻り値の型を確かめず、初期化していない値を読む | 型を確かめる | golem-plugin の Main |
| S8 | 低 | `plugins.lock` の `sha256` をキャッシュのパスにそのまま使う | 64 文字の小文字の 16 進数に限る | golem-plugin の Main |
| S9 | 低 | C の側で `malloc` と `calloc` の失敗を確かめない | 確かめる | なし（メモリ不足を再現できない） |
| S10 | 低 | CI の `GITHUB_TOKEN` の権限が既定のまま、リリースのノートを書く AI がトークンを持つ | 権限を絞り、トークンを外す | なし（設定） |
| S11 | 低 | GitHub Actions の action をタグで指定している | 推奨のみ | なし |
| S12 | 低 | パスの `\` を区切りとして扱う EPUB の読み手がある | 記録のみ | なし |
| S13 | 情報 | FreeType の顔を複数のスレッドで同時に使いうる | 記録のみ | なし |

### S1：出力先のシンボリックリンク（高）

`golem build` は、ターゲットごとに `build/html` などのディレクトリを `removeDirectoryRecursive` で消してから書く。
パスは `root </> "build" </> "html"` と組み立てるだけで、途中のシンボリックリンクを確かめていなかった。
原稿のリポジトリに `build` という名前でホームディレクトリへのシンボリックリンクを置くと、`golem build` は `~/html`、`~/epub`、`~/text`、`~/pdf` を中身ごと消し、そこへ出力を書く。
`git clone` はシンボリックリンクをそのまま作るので、clone してビルドするだけで起きる。
2026-10-17 の main の `golem` で、`build` を外のディレクトリへのリンクにした fixture をビルドし、リンク先の `html/precious.txt` と `text/precious.txt` が消えることを確かめた。
`removeDirectoryRecursive` は、消すディレクトリの中のシンボリックリンクはたどらないが、パスの途中のリンクはたどる。

修正では、`writeTargets` が何かを消す前に、`build` と各ターゲットのディレクトリがシンボリックリンクでもディレクトリ以外のファイルでもないことを確かめる。
一つでも当てはまれば G0813 を出し、どのターゲットも消さず、書かない。
`build/html` だけがリンクの場合も同じである。
確かめてから消すまでのあいだにリンクを差し替える競合は、同じマシンで同時に動く攻撃者を要するので、脅威のモデルの外とした。

### S2：HTML と EPUB のエスケープ（中）

golem-html は、図版の `<img src="...">` とページへのリンクの `href` に、`relLink` が作ったパスをエスケープせずに書いていた。
パスは `resolveInRoot` でプロジェクトの中の実在のファイルに限られるが、ファイルの名前に `"` を含めることはできる。
`q" onerror="alert(1).jpg` という名前の画像を置いて `@figure` で参照すると、`<img src="q" onerror="alert(1).jpg" .../>` が出力され、ブラウザで開くとスクリプトが動く。
2026-10-17 の main の `golem` で、この出力を確かめた。
EPUB の XHTML も同じページを使うので、同じ問題を持つ。
章のファイルの名前に `"` を含めると、目次と参照のリンクにも同じことが起きる。

CSS の `@font-face` は、`font-family: "golem-<役割>-<種類>"` と `src: url("fonts/<ファイル名>")` を、エスケープせずに書いていた。
フォントの役割の名前は `style.toml` のキーで、スタイルの名前（G0306 で検査する）と違って文字を限っていない。
`"` を含む名前で文字列を閉じ、任意の CSS の規則を足せる。
CSS からスクリプトは動かないが、`url()` で外部に読み込みを起こし、読者の閲覧を知らせることはできる。

修正では、属性の値を `escapeXml` でエスケープし、CSS の文字列を `"`、`\`、制御文字についてエスケープする。
パスのパーセントエンコードはしない。
日本語の名前の出力が変わり、既存の出力のバイト列が変わるためである。

### S3：画像の読み込み（中）

golem-pdf の `readImage` は純粋な関数だが、次の入力で止まらないか、例外で落ちていた。

- 色の種類 4 と 6 でビット深度が 8 未満の PNG：一つの画素のバイト数が 0 になり、`[0, 0 .. n]` が終わらないリストになる。CPU とメモリを使い続ける。
- IDAT と iCCP：`Codec.Compression.Zlib.decompress` で全部を展開していた。zlib は約 1000 倍に縮むので、数 MB の画像が数 GB に膨らむ。画素のデータは、画像に要る分より後ろを使っていなかったのに、展開はしていた。
- 幅と高さ：32 ビットの値を `Int` の掛け算に使い、`高さ × (行のバイト数 + 1)` が溢れると、足りなさの検査を通り抜け、範囲の外の `BS.index` で例外になる。
- 短い IHDR（13 バイト未満）、壊れた zlib のデータ、6 バイト未満の JPEG の SOF、14 バイト未満の APP2 の ICC：`BS.index` と zlib が例外を投げる。

例外は `golem build` を落とし、`golem preflight` の G0905 の判定（`unplaceableFigures`）も落とす。
LSP は画像を読まないので影響しない。

修正では、IHDR の長さ、幅と高さの範囲（1 以上 2^31 - 1 以下）、色の種類ごとのビット深度を検査し、大きさを `Integer` で計算して 512 MiB を上限にする。
zlib のデータは、必要なバイト数までだけ展開する関数（`inflateUpTo`）で読み、壊れたデータは例外ではなく `Left` にする。
ICC プロファイルは 32 MiB までとする。
テストでは、64 MiB に展開される 1×1 の画像の読み込みが割り当てるメモリを `GHC.Stats` で測り、16 MiB 未満であることを確かめた（修正の前は 64 MiB を超えた）。

### S4：式の評価の上限（中）

式の整数は任意精度で、`**` は `a ^ k` をそのまま計算していた。
`[= 10 ** 100000000]` は 4 億ビットを超える整数を作り、本文に埋め込むために十進に直すところで終わらなくなる。
`@set` で値を受け渡せば、掛け算を重ねるだけでも大きさは指数的に増える。
`round(x, n)` と `fixed(x, n)` は `10 ^ n` を計算し、`n` に上限がなかった。
コードの `highlight=1-1000000000000` は、範囲のすべての番号から集合を作っていた（G0269 を出した後も、評価の結果を作るために集合を作る）。
LSP も同じ評価を行うので、原稿を開いただけでエディタの LSP が止まる。

修正では、整数の演算の結果の絶対値を 2^4096 未満に限り、`**` は計算する前に判定する。
桁数は 1000 までとし、超えれば G0286 とする。
`highlight` の集合は、コードにある行の番号から範囲に入るものを選んで作る。

### S5：CSL-JSON の年（中）

`date-parts` の最初の数を、aeson の `Scientific` から `round` で整数にしていた。
`1e1000000000` は 13 バイトの JSON だが、`round` は 10 の 10 億乗の整数を作ろうとして終わらない。
`Scientific` の比較（`<` など）も内部で有理数に直すので、値の範囲の判定に使えない。
修正では、係数の桁数と指数から大きさを見積もり、10^15 以上は年として使わない。

### S6：wasm のテーブル（中）

`wasmtime_store_limiter` で、メモリは 256 MiB、インスタンス、テーブル、メモリの数は各 1 に限っていたが、テーブルの要素の数は `-1`（無制限）だった。
`(table 20000000 funcref)` を持つモジュールは、読み込みもインスタンスの作成も通った。
`table.grow` で要素を足していけば、メモリの上限の外でホストのメモリを使える。
fuel は命令の数を数えるので、一つの `table.grow` で大きく増やす操作は止められない。
修正では、要素の数を 100 万に限る。

### S7：プラグインの戻り値の型（低）

`golem_plugin_call` は、`golem_abi_version` と `golem_alloc` の結果を `res.of.i32`、`golem_describe` と `golem_invoke` の結果を `res.of.i64` として、型を確かめずに共用体から読んでいた。
`golem_describe` が i32 を返すモジュールでは、i64 の上位 32 ビットに初期化していないスタックの値が入る。
読む範囲は線形メモリの大きさで検査しているので、メモリの外は読まないが、結果は決定的でなくなる。
試したモジュールでは `CBOR の後ろに余分なバイトがあります` のエラーになったが、スタックの中身次第で別の結果になりうる。
修正では、戻り値の型を ABI の型と比べ、違えば `<関数名> の戻り値の型が不正です` の `BadOutput` にする。

### S8：plugins.lock のハッシュ（低）

`readCached` は `plugins.lock` の `sha256` を、検査せずに `<キャッシュ>/<sha256>.wasm` のパスに使っていた。
`sha256 = "../../../../tmp/x"` と書けば、キャッシュの外の `.wasm` のファイルを読みにいく。
読んだバイト列のハッシュは `sha256` の値と一致しえないので、そのファイルが使われることはなく、存在の有無で G0603 と G0604 が変わるだけである。
キャッシュに書くパスは取得したバイト列のハッシュから作るので、書き込みには使えない。
修正では、`sha256` を 64 文字の小文字の 16 進数に限り、違えば G0611 にする。

### S9：C の側のメモリの確保（低）

`golem_plugin.c` の `golem_plugin_load` の `calloc`、`golem_plugin_import_name`、`read_result`、`golem_wat2wasm` の `malloc` は、失敗を確かめずに書き込んでいた。
メモリが尽きたときに NULL に書き込んで落ちる。
修正では、失敗をエラーとして返す。
`golem_font.c` は確保の失敗を確かめている。

### S10：CI のトークン（低）

`ci.yml` は `permissions` を書いておらず、`push` で動くときの `GITHUB_TOKEN` の権限はリポジトリの設定に従う。
フォークからのプルリクエストのトークンは読み取りだけなので、外部からの悪用は難しいが、最小の権限を明示していなかった。
リリースの `write-notes.sh` は、プルリクエストの本文を入れたプロンプトで Claude Code を動かす。
そのジョブは `contents: write` と `id-token: write` を持ち、環境に `GH_TOKEN` と OIDC のトークンを要求する変数がある。
`claude -p` は、許可のない道具（Bash など）を使わないので、プロンプトへの注入でトークンを使われる道は今は見つからないが、トークンを渡す理由もない。
修正では、`ci.yml` に `permissions: contents: read` を書き、Claude Code をトークンを外した環境で動かす。

ワークフローの `run:` で `${{ github.event.* }}` を直接展開している箇所はなかった。
コミットの SHA は `env:` を通して渡している。
`pull_request_target` は使っていない。

### S11：action の指定（低）

action は `actions/checkout@v7` のようにメジャー版のタグで指定している。
タグは付け替えられるので、action のリポジトリが乗っ取られると、リリースのジョブ（`contents: write`）で任意のコードが動く。
コミットの SHA で固定すれば防げるが、最新のメジャー版を使うという方針と、Dependabot などの更新の手段を合わせて決める必要がある。
この監査では変更せず、メンテナーの判断に委ねる。
リリースのコンテナのイメージは、すでにダイジェストで固定している。

### S12：EPUB の中のパスの `\`（低）

`normalizeRelative` は `/` だけを区切りとして扱うので、`..\..\x.png` という名前のファイルはプロジェクトの中の一つのファイルとして受け付ける。
EPUB の ZIP の項目の名前は `OEBPS/..\..\x.png` になる。
`\` を区切りとして扱う展開の道具で EPUB を展開すると、展開先の外に書かれうる。
EPUB の読み手は ZIP を展開せずに読むものが多く、Golem の側の被害はないので、記録にとどめる。
直すなら、`normalizeRelative` で `\` を含むパスを拒むか、ZIP の項目の名前を検査する。

### S13：FreeType の顔と並列の組版（情報）

golem-font の `glyphMetrics` は `FT_Load_Glyph` で顔の共有のグリフスロットに書く。
FreeType の顔は、複数のスレッドから同時に使ってはならない。
PDF の組版は `mapConcurrently` で段落を並列に組むが、`golem` は `-threaded` で capability を一つしか使わず（`-N` を付けず、既定の `-rtsopts=some` で RTS のオプションのほとんどを受け付けない）、`unsafe` の FFI の呼び出しは capability を手放さないので、同時には走らない。
`-N` を有効にするときは、顔ごとの排他か、スレッドごとの顔が要る。

## 問題のなかった項目

- **原稿と取り込むファイルのパス**：章、`@import`、`@figure`、`@listing`、`@table`、フォント、出力インテント、書誌は、すべて `resolveInRoot` で字句の正規化、存在、シンボリックリンクを解決した後のルートの内側を確かめている。プロジェクトの外を指すリンクの画像は G0260 になることを、実際のビルドで確かめた。
- **`@import` の循環**：G0305 で止まる。二つのファイルの循環で確かめた。
- **深い入れ子**：インラインのコマンドを 10 万段、式の括弧を 10 万段入れ子にした原稿は、それぞれ約 4 秒で診断を出して終わった。落ちることも止まらなくなることもない。
- **正規表現のスタイル**：照合器はバックトラックしない方式で、`(a*)*b` を 1 万字に当てるテストがある（[docs/adr/0015](../adr/0015-regex-styles.md)）。
- **プラグインの隔離**：import を渡さず（WASI もない）、呼び出しごとに新しいストアとインスタンスを作り、fuel とメモリを限っている。出力の CBOR は、余分なバイト、形、ソースの位置と DeferredExpr の出所、IR の不変条件を検査している。出力の範囲は線形メモリの大きさで検査している（`pos + len` は 64 ビットで計算し、溢れない）。
- **ネットワーク**：プラグインの取得は HTTPS に限り、リダイレクトも一回ずつ HTTPS に限る。証明書は OS のストアで検証する。`golem plugin fetch` は、ハッシュを照合してからキャッシュに書き、ビルドはキャッシュから読んだバイト列のハッシュを照合してから同じバイト列を使うので、照合と使用のあいだの差し替えは効かない。`golem new` のフォントは、コードに書いた URL とハッシュで照合してから書く。取得の大きさに上限はないが、URL は利用者が選ぶ。
- **LSP**：`lsp` ライブラリが Content-Length の枠と JSON を解釈する。不正な JSON の `initialize` を送ると、診断を出して終了し、落ちることはなかった。
- **EPUB の書き出し**：ZIP の項目の名前は、ページと画像のパス（ルートの中に正規化済み）と固定の名前だけで、`..` を含まない。EPUB を読み込む処理はない。
- **golem-font の C の層**：フォントのバイト列は複製して FreeType と HarfBuzz に渡し、`ForeignPtr` のファイナライザで一度だけ解放する。シェイピングの出力の配列は、HarfBuzz が返した数が足りないときに大きさを返させてから取り直す。サブセットのバッファは `bracket` で解放する。
- **スクリプト**：`scripts/` の中に `eval` はなく、外部の入力をコマンドとして解釈する箇所はなかった。

## 調べ方

- コードを読み、ファイルを読み書きする箇所（`readFile`、`writeFile`、`removeDirectoryRecursive`、`createDirectoryIfMissing`）、FFI、ネットワーク、JSON と CBOR の数の変換、ワークフローの `run:` と `permissions` をすべて洗った。
- 問題らしいものは、2026-10-17 の main の `golem` で実際に再現するか、失敗するテストを書いてから直した。
- 修正の後、`cabal test all`、二つのマニュアルのビルド、`scripts/determinism.sh` を実行した。

## 参考文献

- PNG Specification (Third Edition), W3C, 2025. https://www.w3.org/TR/png-3/
- FreeType Tutorial, "Thread safety". https://freetype.org/freetype2/docs/design/design-4.html
- Wasmtime C API, `wasmtime_store_limiter`. https://docs.wasmtime.dev/c-api/store_8h.html
- GitHub Docs, "Security hardening for GitHub Actions". https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions
- OWASP, "Cross Site Scripting Prevention Cheat Sheet". https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html
- directory, `System.Directory.removeDirectoryRecursive` のドキュメント。https://hackage.haskell.org/package/directory/docs/System-Directory.html
