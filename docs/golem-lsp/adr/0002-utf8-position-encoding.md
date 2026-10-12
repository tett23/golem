# ADR 0002: LSP の位置の単位に UTF-8 を交渉する

ステータス: 採択

## 文脈

[ADR 0001](0001-language-server.md) は、クライアントが対応していれば位置の単位に UTF-8 を、そうでなければ UTF-16 を交渉で選ぶと決めた。
実装は UTF-16 だけを使っており、仕様書の「今後の実装項目」（[specifications.md](../../specifications.md)）に残っている。
理由は、使っている `lsp` パッケージ 2.8.0.0 が、初期化の応答のサーバーの能力（`ServerCapabilities`）を自分で組み立て、その `positionEncoding` を `utf-16` に固定しているためである（`Language.LSP.Server.Processing` の `inferServerCapabilities`）。
`ServerDefinition` の `options` にも `doInitialize` にも、この値を変える手段はない。

Golem の内部の位置は UTF-8 のバイト数である（[golem-syntax ADR 0001](../../golem-syntax/adr/0001-source-spans-and-diagnostics.md)）。
UTF-8 の列と行の変換の関数（`offsetToUtf8LineCol`、`utf8LineColToOffset`）と、単位を選ぶ型（`Golem.Lsp.Features` の `Encoding`、`toLineCol`、`fromLineCol`）はすでにある。
足りないのは、交渉の結果を応答に載せることと、サーバーの各所で単位を固定している呼び出しを交渉の結果に従わせることである。

### 調べたこと

ネットワークには接続せず、cabal が取得済みの Hackage の索引（`~/.cabal/packages/hackage.haskell.org/01-index.tar`、2026-10-12 時点）と、取得済みのソースの tarball を読んだ。

- 索引にある `lsp` の最新版は 2.8.0.0（2026-02-14）である。2.8.0.0 の ChangeLog に位置の単位に関する変更はなく、`_positionEncoding = Just PositionEncodingKind_UTF16` のままである。
- `lsp` の VFS は UTF-16 の rope（`Data.Text.Utf16.Rope.Mixed`）で差分を適用する。全文の同期では変更のたびに全文を置き換えるので、位置の単位は VFS の内容に影響しない。Golem は全文の同期を使い、VFS からは `virtualFileText` で全文を読むだけである。
- `lsp-types` 2.4.0.0 は `PositionEncodingKind_UTF8` と、クライアントの能力の `general.positionEncodings` を持つ。型を新たに定義する必要はない。
- `lsp` は `runServerWithConfig` と `ServerConfig` を公開している。`ServerConfig` の `outwards` は、サーバーが送るメッセージを JSON に符号化した後のバイト列を受け取る関数である。初期化の応答もここを通る。
- `lsp-test` 0.18.0.0 の `fullLatestClientCaps` は `positionEncodings` に `utf-16` だけを入れている。テストでは能力を書き換えて渡す必要がある。
- `lsp`、`lsp-types`、`lsp-test` のライセンスはいずれも MIT である。

### 比較した方法

| 方法 | 内容 | 変更の量 | 危うさ |
|---|---|---|---|
| A. 新しい版の `lsp` を使う | 交渉に対応した版へ上げる | 小さい | 索引にそのような版がない。採れない |
| B. `lsp` を使ったまま初期化の応答を差し替える | `runServerWithConfig` の `outwards` で、初期化の応答の JSON の `capabilities.positionEncoding` だけを書き換える | 小さい（Server.hs の数十行） | `lsp` が将来、送る位置を自分で変換するようになると食い違う |
| C. `lsp` をやめて自前で実装する | JSON-RPC のヘッダーと本体の読み書き、要求と応答の対応付け、初期化と終了の手順、VFS の代わりの全文の保持を実装する | 大きい（数百行と、そのテスト） | 取り消しや進捗の通知など、`lsp` が扱っている手順を自分で保つ必要がある |

B を採る。
A は採れない。
C は再実装の方針には合うが、ここで必要なのは初期化の応答の一つの値だけであり、`lsp` の残りの機能（メッセージの振り分け、型付きのハンドラー、VFS、`lsp-test` との接続）は使い続ける。
B の危うさは、`lsp` が位置を扱う箇所に依存する。
2.8.0.0 で位置を解釈するのは VFS の差分の適用だけであり、全文の同期では通らない。
そこで、`lsp` の版の上限を 2.9 未満に固定し、版を上げるときにこの前提を確かめ直す。

## 実装すること

### 単位の選択

`Golem.Lsp.Features` に、クライアントの能力から単位を選ぶ純粋な関数を足す。

```haskell
chooseEncoding :: Maybe [PositionEncodingKind] -> Encoding
```

- 一覧に `utf-8` があれば `Utf8` を返す。クライアントが並べた順は見ない（[ADR 0001](0001-language-server.md) が UTF-8 を優先すると決めているため）。
- 一覧がない場合、空の場合、`utf-8` を含まない場合は `Utf16` を返す。LSP 3.17 は、`utf-16` を常に使える単位と定めている。
- `utf-32` は選ばない。
- `Encoding` から LSP の値への変換 `encodingKind :: Encoding -> PositionEncodingKind` も足す。

### 初期化の応答の差し替え

`Golem.Lsp.Server` を次のように変える。

- 交渉の結果を `TVar Encoding` に持つ。初期値は `Utf16` とする。
- `doInitialize` で、要求の `params.capabilities.general.positionEncodings` に `chooseEncoding` を適用し、結果を書き込む。あわせて、初期化の要求の `id` を `TVar (Maybe (LspId Method_Initialize))` に書き込む。`doInitialize` は `lsp` が応答を送る前に呼ばれるので、応答を送る時点で値は決まっている。
- 応答を書き換える純粋な関数を足し、テストのために公開する。

  ```haskell
  rewriteInitializeResponse :: LspId Method_Initialize -> Encoding -> BSL.ByteString -> Maybe BSL.ByteString
  ```

  引数のバイト列が、`id` が一致し `result.capabilities` を持つ JSON の応答であれば、`capabilities.positionEncoding` を `encodingKind` の値に置き換えたバイト列を返す。
  それ以外は `Nothing` を返す。
  JSON の解析と再符号化には `aeson` を使う。`aeson` は `lsp-types` が依存しているのですでにビルドに含まれており、golem-lsp の `build-depends` に直接の依存として足すだけである。
- `runGolemLsp` を `runServer` から `runServerWithConfig` に変える。
  - `prepareOutwards` は `id` とし、`outwards` で書き換えとヘッダーの付加を行う。書き換えでバイト数が変わるので、`Content-Length` は書き換えた後に `prependHeader` で付ける。
  - `outwards` は、書き換えが済んだかを `TVar Bool` で持ち、済むまでは送る各メッセージに `rewriteInitializeResponse` を試す。済んだ後は JSON を解析しない。
  - `inwards` と `parseInwards` は、`runServerWithHandles` と同じく、標準入力からの読み込みと `parseHeaders` にする。標準入出力のバッファリングと符号化の設定も `runServerWithHandles` と同じにする。
- テストが同じ経路を通れるように、ハンドルを受け取る `runGolemLspWithHandles :: Handle -> Handle -> IO Int` を公開し、`runGolemLsp` はこれに標準入出力を渡す。

### 位置の変換を交渉の結果に従わせる

`Golem.Lsp.Server` で UTF-16 を固定している次の箇所を、`TVar Encoding` の値を使うように変える。
変換は `Features.toLineCol` と `Features.fromLineCol` を通す。

| 箇所 | 今の呼び出し |
|---|---|
| 要求の位置からバイト位置への変換（`atPosition`） | `F.fromLineCol F.Utf16` |
| 範囲への変換（`rangeIn`） | `S.offsetToUtf16LineCol` |
| 診断の範囲（`toDiagnostic`） | `S.offsetToUtf16LineCol` |
| アウトラインの範囲（`symbol`） | `S.offsetToUtf16LineCol` |
| 整形の編集の終端（`TextDocumentFormatting` のハンドラー） | `S.offsetToUtf16LineCol` |

`rangeIn`、`toDiagnostic`、`symbol` は `Encoding` を引数に取る形にする。
モジュールの先頭のコメントにある「UTF-16 に固定する」という記述は、交渉の説明に書き換える。

### 行の索引

位置の変換の費用は、行の索引の作り方と引き方で決まる。
今の `Golem.Syntax.Position.LineIndex` には次の問題がある。

- 行の先頭の位置をリストで持つので、行を探す `lineOf` と行の範囲を求める `lineStartAndEnd` が、どちらも行数に比例する。
- `advance` が、列を一つ進めるたびに行頭からの単位の数を数え直すので、一行の変換が行の長さの二乗に比例する。
- `Golem.Lsp.Server` の `rangeIn` が、範囲を一つ作るたびに `mkLineIndex` でファイル全体の索引を作り直す。参照の検索や名前の変更では、結果の数だけファイル全体を走査する。

これを次のように変える。
公開している関数の名前と型は変えない。`LineIndex` の構成子は公開していないので、利用者（golem-cli、golem-driver、golem-project、golem-lsp）の変更は要らない。

- `liStarts` を `UArray Int Int` にする（golem-syntax はすでに `array` に依存している）。`lineOf` は二分探索、`lineStartAndEnd` は添字で引く。
- `utf8LineColToOffset` は走査せずに求める。列が行のバイト数以下で、その位置が行末か UTF-8 の後続バイトでなければ、行頭に列を足した値を返し、そうでなければ `Nothing` を返す。
- `lineColToOffset` と `utf16LineColToOffset` は、行を一度だけ先頭から走査し、単位の数を累積しながら列に達した位置を返す。列が文字の途中（UTF-16 のサロゲートペアの間）に当たる場合と、行の長さを超える場合は、今と同じく `Nothing` を返す。
- 改行は LF だけを数える。原稿の改行は LF に限ると決めている（[markup.md](../../markup.md)）ので、CR を行の区切りに数える必要はない。

golem-lsp の `Workspace` に、ファイルごとの行の索引を持たせる。

- `Workspace` に `wsLines :: Map FilePath LineIndex` を足す。`fullEvaluate` でプロジェクトのソースと編集中のファイルのすべてについて作り、`updateFile` で変更したファイルの分だけ作り直す。
- `lineIndexOf :: Workspace -> FilePath -> LineIndex` を公開する。表にないファイルには空のテキストの索引を返す。
- `Golem.Lsp.Server` の `mkLineIndex` の呼び出しを、すべて `lineIndexOf` に置き換える。

### ドキュメント

- 仕様書の「今後の実装項目」から「LSP の位置の単位」の項目を消す。
- 仕様書の LSP の節に、位置の単位は UTF-8 を優先して交渉し、クライアントが対応しなければ UTF-16 を使うことを書く。

## 実装しないこと

- `utf-32` の交渉。変換の関数（符号位置の数え方）はあるが、LSP 3.17 では UTF-16 を常に使えるので、`utf-32` だけを申し出るクライアントにも UTF-16 で応えられる。
- `lsp` パッケージを使わない自前の実装（比較の C）。`lsp` の版を上げるときに前提が崩れていれば、新たな ADR で扱う。
- 差分の同期。全文の同期を続ける（[ADR 0001](0001-language-server.md)）。差分の同期では `lsp` の VFS が UTF-16 で位置を解釈するので、UTF-8 と組み合わせられない。
- 行の長さを超える列を行末に丸める扱い。LSP 3.17 は行末に丸めると定めているが、今の実装は `Nothing` を返して結果を空にしており、この ADR では変えない。
- 診断コードの追加。位置の交渉は利用者に診断を出す場面を持たない。

## テスト設計

### golem-syntax（`modules/golem-syntax/test/Main.hs`）

- プロパティ：既存の `genText` と `boundaries` で、`utf8LineColToOffset li (offsetToUtf8LineCol li off) === Just off`。
- プロパティ：リストで行の先頭を持つ素朴な索引をテストの中に書き、任意のテキストと境界の位置で、`offsetToLineCol`、`offsetToUtf16LineCol`、`offsetToUtf8LineCol` の結果が素朴な索引の結果と一致する。
- 単体：`mkLineIndex "漢字\nab"` で、`utf8LineColToOffset li (LineCol 0 1)` と `(LineCol 0 2)` が `Nothing`（文字の途中）、`(LineCol 0 3)` が `Just 3`、`(LineCol 0 6)` が `Just 6`（行末）、`(LineCol 0 7)` が `Nothing`、`(LineCol 1 2)` が `Just 9`、`(LineCol 2 0)` が `Nothing` になる。
- 単体：10 万行のテキストで最後の行の位置を往復させるテストを、tasty の `localOption (mkTimeout 2000000)` を付けて置く。行数に比例する探索に戻ったときに気付けるようにするためである。

### golem-lsp（`modules/golem-lsp/test/Main.hs`）

- 単体：`chooseEncoding` が、`Nothing`、`Just []`、`Just [utf-16]`、`Just [utf-32]` で `Utf16`、`Just [utf-8]` と `Just [utf-16, utf-8]` で `Utf8` を返す。
- 単体：`rewriteInitializeResponse` が、`id` の一致する初期化の応答で `capabilities.positionEncoding` を `"utf-8"` にし、ほかの能力の値を変えない。`id` が異なる応答、通知、`result` のない応答では `Nothing` を返す。
- golden：既存の `protocol` のセッションを `runGolemLspWithHandles` で動かすように変え、`test/golden/protocol.txt` が変わらないことを確かめる（`fullLatestClientCaps` は `utf-16` だけを申し出るので、UTF-16 が選ばれる）。初期化の応答の `positionEncoding` が `utf-16` であることを一行加える。
- golden：`general.positionEncodings` を `[utf-8, utf-16]` に書き換えた能力で二つ目のセッションを動かし、`test/golden/protocol-utf8.txt` に固定する。内容は次のとおり。
  - 初期化の応答の `positionEncoding` が `utf-8` である。
  - `a.gm` の 0 始まりで 5 の行の UTF-8 の列 22 でのホバーが、UTF-16 のセッションの列 18 と同じ `"1.0"` を返す。
  - 同じ行の UTF-8 の列 97 での定義への移動が、UTF-16 のセッションの列 75 と同じく `b.gm` の 0 始まりで 0 の行の列 7 から 13 を返す。行の途中に絵文字と日本語があるので、二つの単位で列が異なる。
  - `a.gm` の `@label intro` の上での参照の検索で、`b.gm` の 0 始まりで 3 の行の二つ目の `intro` の範囲が列 30 から 35 になる（UTF-16 では 28 から 33。間の「と」が UTF-8 で 3 バイト、UTF-16 で 1 単位のため）。
  - 文書を `😀[ref-title nosuch]\n` に変えたときの G0403 の診断の範囲の開始の列が、UTF-16 のセッションの同じ操作での列より 2 大きい（絵文字が UTF-8 で 4 バイト、UTF-16 で 2 単位のため）。
- 単体：UTF-8 のセッションで、`a.gm` の 0 始まりで 5 の行の UTF-8 の列 1（「版」の 2 バイト目）でのホバーが `null` を返す。

自動テストにしないもの：実装の後、UTF-8 を申し出るエディタ（Neovim 0.10 以降の組み込みのクライアント）で日本語と絵文字を含む原稿を開き、定義への移動、名前の変更、診断の下線の位置がずれないことを確かめる。

## トレードオフ

初期化の応答を JSON のバイト列の段階で書き換えるのは、`lsp` の型付きの経路の外側での操作である。
`lsp` が組み立てる能力の型は変わらないので、`lsp` の中では UTF-16 を交渉したことになっている。
2.8.0.0 で `lsp` が位置を解釈するのは差分の同期の VFS だけなので、全文の同期を使う限り食い違いは表に出ない。
`lsp` が将来、送受信する位置を自分で変換するようになると、この前提が崩れる。
版の上限を 2.9 未満に固定し、上げるときに `positionEncoding` の扱いを読み直すことで、この危うさを版の更新の時点に閉じ込める。

自前の実装（比較の C）を採らないので、JSON-RPC の層を `lsp` に任せ続ける。
再実装すれば依存と書き換えの細工はなくなるが、初期化と終了の手順、取り消し、要求と応答の対応付けを自分で保ち、`lsp-test` との接続も確かめ直すことになる。
一つの値のためにその費用を払うより、細工を一か所に閉じ込めるほうを選ぶ。

行の索引を `Workspace` に持たせると、ファイルの数だけ索引をメモリーに置くことになる。
索引は行の数の整数の配列であり、章ファイル単位の原稿では原稿のテキストより小さい。
