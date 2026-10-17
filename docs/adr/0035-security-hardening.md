# ADR 0035: 信頼できない入力に対する防御を固める

ステータス: 提案

## 文脈

Golem は、他人の書いた原稿、フォント、画像、TOML、CSL-JSON を読み、URL から取得した WebAssembly のプラグインを動かす。
原稿のリポジトリを clone して `golem build` するだけで、これらの入力はすべて Golem に届く。
2026-10-17 のセキュリティ監査（[docs/audits/2026-10-17-security-audit.md](../audits/2026-10-17-security-audit.md)）で、次の問題が見つかった。

1. `build` がプロジェクトの外を指すシンボリックリンクだと、`golem build` は、その先の `html/`、`epub/`、`text/`、`pdf/` を消し（`removeDirectoryRecursive`）、出力をそこへ書く。原稿のリポジトリにシンボリックリンクを一つ置くだけで、ビルドする人のファイルを消せる。
2. HTML と EPUB の XHTML で、図版の `src` とページへのリンクの `href` を、エスケープせずに属性に書いている。名前に `"` を含む画像のファイルを置くと、`onerror` などの属性を差し込める（スクリプトの実行）。HTML の CSS の `@font-face` でも、フォントのファイル名と役割の名前をエスケープせずに文字列に書いている。
3. PNG の読み込みが、悪意のある画像で止まらない、または落ちる。
   - 色の種類 4 と 6（アルファつき）でビット深度が 8 未満だと、標本の区切りの幅が 0 になり、無限のリストを作って止まらない。
   - IDAT と iCCP を上限なしに展開する。小さなファイルが数 GB に膨らむ（解凍爆弾）。
   - 幅と高さの積が `Int` を溢れると、大きさの検査をすり抜けて範囲の外を読み、例外で落ちる。
   - 短い IHDR、壊れた zlib のデータ、短い JPEG の SOF と APP2 で、純粋なはずの関数が例外を投げる。
4. 式の評価で、整数が際限なく大きくなる。`[= 10 ** 100000000]` は数百 MB の整数を作り、文字列にするまで終わらない。`round` と `fixed` の桁数、コードの `highlight` の行の範囲（`1-1000000000000`）も、上限なしに計算と集合を作る。
5. CSL-JSON の `date-parts` の年に `1e1000000000` と書くと、`round` が 10 の 10 億乗の整数を作ろうとして止まらない。
6. プラグインのホストが、wasm のテーブルの要素の数に上限を付けていない（`wasmtime_store_limiter` の `table_elements` が `-1`）。メモリの上限（既定 256 MiB）の外で、ホストのメモリを使い切れる。また、`golem_abi_version`、`golem_describe`、`golem_alloc`、`golem_invoke` の戻り値の型を確かめずに共用体を読むので、型の違う関数を公開したプラグインでは、初期化していないバイトを読む（結果が決定的でなくなる）。
7. `plugins.lock` の `sha256` を検査せずにキャッシュのパスに使う。`../` を含む値で、キャッシュの外の `.wasm` のファイルを読みにいく（ハッシュは一致しないので使われはしない）。
8. CI の `ci.yml` が `permissions` を書いておらず、`GITHUB_TOKEN` の権限がリポジトリの既定に従う。リリースのノートを書く Claude Code が、`GH_TOKEN`（`contents: write`）と OIDC のトークンを要求する環境変数を持ったまま、プルリクエストの本文を読む。

## 実装すること

### 出力先のディレクトリ（G0813）

- golem-driver の `writeTargets` は、何かを消すか書く前に、`build` と、出力するターゲットのディレクトリ（`build/html`、`build/epub`、`build/text`、`build/pdf`）を調べる。
- そのどれかが、シンボリックリンクであるか、ディレクトリ以外のファイルであれば、新しいエラー G0813 を出し、どのターゲットも消さず、書かない。
  - メッセージは `出力先がシンボリックリンクかディレクトリではないので、消すことも書くこともしません: <パス>`。
  - 位置は、ほかの出力の診断と同じく `style.toml` の先頭（ないときは `manifest.toml` の先頭）である。
- `golem preflight`（出力を書かない）では調べない。

### HTML と EPUB のエスケープ

- golem-html の図版の `src` と、ページへのリンク（目次、索引、参照）の `href` を、ほかの属性と同じく `escapeXml` でエスケープする。
- CSS の `@font-face` の `font-family` と `src: url("...")` の文字列、および `font-family` の並びの中の名前を、CSS の文字列としてエスケープする（`"` と `\` の前に `\` を置き、改行などの制御文字を `\` と 16 進の番号にする）。
- `"`、`&`、`<`、`>`、`\`、制御文字を含まない名前の出力は変わらない。

### 画像の読み込み

golem-pdf の `readImage` を、どの入力でも例外を投げず、止まる関数にする。

- PNG の IHDR は 13 バイトを要る。幅と高さは 1 以上 2^31 - 1 以下とする（PNG の仕様の範囲）。
- ビット深度は、色の種類ごとに PNG の仕様が許すものに限る（0：1、2、4、8、16、2：8、16、3：1、2、4、8、4：8、16、6：8、16）。外れれば `PNG のビット深度が色の種類に合いません`。
- フィルタの前の画素のデータ（`高さ × (行のバイト数 + 1)`）を `Integer` で計算し、512 MiB（2^29 バイト）を超えれば `PNG の画像が大きすぎます` とする。
- IDAT は、必要なバイト数までしか展開しない。それより後ろのデータは読まない（今も使っていない）。展開できないデータは `PNG の画素のデータを展開できません`。
- iCCP の ICC プロファイルは 32 MiB までしか展開せず、超えれば `PNG の ICC プロファイルが大きすぎます`、展開できなければ `PNG の ICC プロファイルを展開できません` とする。
- JPEG の SOF が 6 バイトに満たなければ `JPEG の SOF が壊れています` とし、APP2 の ICC の断片が 14 バイトに満たなければ無視する。
- これらの理由は、`golem preflight` の G0905 のメッセージの括弧の中に出る。`golem build` は、これまでどおり読めない図版を描かず、診断を出さない。

### 式の評価の上限（G0286）

- 整数の演算（`+`、`-`、`*`、`**`、単項の `-`、`abs`）の結果の絶対値が 2^4096 以上になれば、新しいエラー G0286 を出す。`**` は、計算する前に、結果のビットの数を指数と底のビットの数から見積もって判定する。
  - メッセージは `整数が大きすぎます（絶対値は 2 の 4096 乗未満に限ります）`。
- `round(x, n)` と `fixed(x, n)` の `n` が 1000 を超えれば、G0286 を出す。メッセージは `小数の桁数が多すぎます（1000 桁までです）`。
- コードの `highlight` の範囲は、コードにある行だけを集合にする。範囲が大きくても、コードの行の数を超える計算をしない。強調する行と G0269 の判定は変わらない。

### CSL-JSON の年

- `date-parts` の最初の数の絶対値が 10^15 以上なら、年として使わない（`literal` があればそれを使い、なければ日付なしとする）。絶対値が 10^-1 未満の数は 0 年とする。判定は `Scientific` の係数と指数から行い、大きな整数や有理数を作らない。

### プラグイン

- `wasmtime_store_limiter` のテーブルの要素の数の上限を 100 万にする（今は無制限）。インスタンス、テーブル、メモリの数の上限（各 1）とメモリの上限は変えない。上限を超えるテーブルを持つモジュールは、インスタンスを作るときに `InstantiateFailed` になる。
- 呼んだ関数の戻り値の型を確かめる。`golem_abi_version` と `golem_alloc` は i32、`golem_describe` と `golem_invoke` は i64 とし、違えば `BadOutput` にする（メッセージは `<関数名> の戻り値の型が不正です`）。
- C の側の `malloc` と `calloc` の失敗を確かめ、NULL を使わない。

### plugins.lock

- `sha256` は 64 文字の小文字の 16 進数に限る。違えば G0611 とし、メッセージは `plugins.<名前>.sha256 は 64 文字の小文字の 16 進数で書きます`。

### CI

- `ci.yml` に `permissions: contents: read` を書く。
- `scripts/release/write-notes.sh` は、Claude Code を `GH_TOKEN`、`GITHUB_TOKEN`、`ACTIONS_ID_TOKEN_REQUEST_TOKEN`、`ACTIONS_ID_TOKEN_REQUEST_URL` を外した環境で動かす。プルリクエストの本文は、それより前に `gh pr view` で読んでおく（今と同じ）。

### ドキュメント

- `docs/diagnostics.md` に G0286 と G0813 を足し、G0611 のメッセージを足す。
- 仕様書の、式の評価、画像、出力のディレクトリの節に、上限と G0813 を書く。
- 利用者向けマニュアルの診断の付録と、式と図版の章に、上限を書く。

## 実装しないこと

- GitHub Actions の action を、メジャー版のタグではなくコミットの SHA で固定すること。グローバルの方針（最新のメジャー版を使う）と衝突するので、監査の記録に推奨として残し、判断はメンテナーに委ねる。
- ネットワークから取得するプラグインとフォントの大きさの上限。URL は利用者が選び、ハッシュで照合している。
- FreeType の `FT_Face` の、スレッドをまたぐ同時の使用の排除。`golem` は capability を一つで動かし（`-N` を付けず、既定の `-rtsopts=some` で RTS のオプションのほとんどを受け付けない）、`unsafe` の FFI の呼び出しは同時に走らない。監査の記録に、`-N` を有効にするときの注意として残す。
- `@figure` のパスの、`\` や `:` を含む名前の禁止。EPUB の読み手の中には `\` を区切りとして扱うものがあるが、パスはプロジェクトルートの中のファイルに限られ、出力の名前は Golem の書く ZIP の中で `..` を含まない。監査の記録に残す。
- LSP の不正なメッセージへの対処。不正な JSON を受けたサーバーは、`lsp` ライブラリが診断を出して終了し、止まり続けたり落ちたりはしない。

## テスト設計

すべて、修正の前に失敗することを確かめてから実装する。

- golem-driver
  - `build` がプロジェクトの外のディレクトリへのシンボリックリンクのとき、`golem build` が G0813 を出し、リンク先のファイルが残っている。
  - `build/html` がシンボリックリンクのときも同じ。
  - `"` を含む名前の画像を `@figure` に置いた HTML で、`src` の値がエスケープされ、`onerror` の属性ができない。
  - 役割の名前に `"` を含むフォントで、`style.css` の `@font-face` の文字列が閉じない。
  - CSL-JSON の年が `1e1000000000` のとき、ビルドが 10 秒以内に終わる。
- golem-pdf
  - 色の種類 6 でビット深度 4 の PNG が、5 秒以内にエラーになる。
  - IHDR が 13 バイトに満たない PNG、壊れた zlib の IDAT、短い SOF の JPEG、14 バイトに満たない APP2 の ICC が、例外ではなく `Left` になる（APP2 は無視される）。
  - 幅と高さが 2^31 - 1 の PNG が、すぐに `PNG の画像が大きすぎます` になる。
  - 1×1 の画像の IDAT が 64 MiB に展開されるとき、読み込みの割り当てが 16 MiB に満たない（`GHC.Stats` で測る）。
  - iCCP が 64 MiB に展開されるとき、`PNG の ICC プロファイルが大きすぎます` になる。
- golem-eval
  - `10 ** 100000000`、`2 ** 4096`、2^4095 の自乗、`round(1.5, 100000000)` が G0286 になり、10 秒以内に終わる。`2 ** 4095` は通る。
  - `highlight=1-1000000000000` のコードが 10 秒以内に評価され、強調される行が今と同じである。
- golem-plugin
  - 2000 万の要素のテーブルを持つプラグインが `InstantiateFailed` になる。
  - `golem_describe` が i32 を返すプラグインが `BadOutput "golem_describe の戻り値の型が不正です"` になる。
  - `sha256` が `../x` の `plugins.lock` が G0611 になる。
- CI は、`ci.yml` を YAML として読めることと、`scripts/release/test.sh` が通ることで確かめる。

## トレードオフ

- 512 MiB を超える PNG は使えなくなる。8 ビットの RGBA で約 1 億 3 千万画素（A3 を 600 dpi で約 7000 × 9900 画素にあたる量の約 2 倍）である。
- 整数の上限（2^4096）と桁数の上限（1000）は、組版の原稿の計算には十分に大きいが、任意の精度の整数という言語の性質に、はじめて上限を設ける。
- 出力先がシンボリックリンクだと、利用者が意図して `build` を別のディスクに向けていた場合もビルドが止まる。その場合は、`build` をリンクにせず、プロジェクトの外でビルドするか、ディレクトリをマウントする。

## 参考文献

- PNG Specification (Third Edition), W3C, 2025. https://www.w3.org/TR/png-3/
- Wasmtime C API, `wasmtime_store_limiter`. https://docs.wasmtime.dev/c-api/store_8h.html
- GitHub Docs, "Security hardening for GitHub Actions". https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions
- scientific, `Data.Scientific` のドキュメント（大きな指数を持つ値の変換の注意）。https://hackage.haskell.org/package/scientific/docs/Data-Scientific.html
- OWASP, "Cross Site Scripting Prevention Cheat Sheet". https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html
