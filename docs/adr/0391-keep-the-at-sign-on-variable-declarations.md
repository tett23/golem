# ADR 0391: 原稿の変数の宣言を @set に戻す

Status: accepted

## 文脈

[ADR 0336](0336-unprefixed-variable-declarations.md) は、原稿のファイル内の変数を、行頭の `set 名前 = 式` で宣言するようにした。
旧記法の `@set 名前 = 式` も同じ値を定義するが、先頭の `@` に廃止予定の notice G02155 を出している。

しかし、`@` の無い `set 名前 = 式` は、原稿の本文と区別がつかない。
行頭の `set x = 3` は、宣言のつもりで書いた行とも、その文字列を本文として書いた行とも読める。
[ADR 0336](0336-unprefixed-variable-declarations.md) 自身も、トレードオフに「旧版で行頭に `set x = 3` と書いた本文は、更新後は宣言として読まれる」と書いている。

tett23 は、2026-11-18 に次のとおり決めた。

- 宣言は `@set 名前 = 式` に戻す。`@` は、その行がブロックコマンドの行であることを表す。
- 変数を参照するときは `@` を付けない（`[= 名前]`）。ブロックコマンドと式の中では、名前が現れる位置と型から、それが変数だと決まるので、変数の名前に `@` を付ける必要はない。PHP の `$var` のように、変数の名前に記号を付けることは、今の設計では要らない。

## 調査した事項

この節の事実は、origin/main の [`33a39d02`](https://github.com/tett23/golem/tree/33a39d0267c440bc32e47b24897f368ed7602d0c) と、手元の `golem 0.1.0-rc4` で確かめた。

### [ADR 0336](0336-unprefixed-variable-declarations.md) の実装とリリース

- [ADR 0336](0336-unprefixed-variable-declarations.md) の実装は、PR #947 で 2026-11-12 に main にマージした（マージコミット `5baad12c`）。
- 最後のリリース `v0.1.0-rc4` は 2026-11-09 のタグで、`git tag --contains 5baad12c` は何も返さない。そのため、`set 名前 = 式` の宣言を含むリリースは無い。
- PR #947 が変えたファイルは、`git diff --stat 5baad12c^1 5baad12c` で次のとおりである。
  - 文法と生成物：`modules/golem-parser/grammar/Golem.hpeg`（`SetDeclarationStart`）、`modules/golem-parser/src` の 3 ファイル（AST の `SetVar` の `@` の位置の欄、Lower、生成したパーサー）
  - 評価と diagnostic：`modules/golem-eval/src`（G02155）、`modules/golem-syntax/src`（`noticeCodes`）、`modules/golem-driver/src`（`golem explain` の埋め込み）
  - LSP：`modules/golem-lsp/src` の 1 ファイル（`SetVar` の形に合わせた）
  - テスト：golem-parser 5、golem-eval 6、golem-driver 6、golem-lsp 4、golem-project 1、golem-syntax 1、golem-fmt 1 のファイル。原稿の文字列の `@set` を `set` に書き換えたものを含む。
  - スクリプト：`scripts/manual` の 2 ファイル（`build-info.sh` が書く宣言と `test.sh` の期待）、`scripts/visual` の 3 ファイル、`scripts/determinism` の 1 ファイル（ハッシュの記録）
  - 原稿と文書：`manual/` の 9 ファイル、`manual-dev/` の 2 ファイル、`docs/specifications.md`、`docs/markup.md`、`docs/compatibility.md`、`docs/diagnostics.md`、README
- エディタの文法は PR #947 で変わっておらず、`@set` だけを宣言として読む（`tools/editors/textmate/golem.tmLanguage.json` の `^(\\s*)(@)(set)`、`tools/editors/tree-sitter-golem/grammar.js` の `@set`）。golem-fmt の実装も PR #947 で変わっていない。

### rc4 の振る舞い

`golem 0.1.0-rc4` は `SetDeclarationStart` を持たない。
rc4 で次を確かめた。

- `@set x = "abc"` の後の `[= x]` は、diagnostic を出さずに `abc` を返す。
- 行頭の `set x = "abc"` は、AST が `Paragraph [Text "set x = \"abc\""]` になる。その後の `[= x]` は G02002（未定義の名前）になる。`set up is easy` も `Paragraph` になる。
- 行頭の `set xs = [1, 2]` は、本文の記法の誤り G01021 になる。行頭の `set x = [= 1 + 2]` は、本文の中の式として評価する。
- コードブロックの中の `@set x = 3` は変数を定義せず、その後の `[= x]` は G02002 になる。
- `@set x =` は G01020 になる。`[= @x]` は G01020 になる。
- `silence-notices = ["G02155"]` は G03024 になる（G02155 が `noticeCodes` に無いため）。

### 今のコードと文書

- G02155 は、評価で旧記法の先頭の `@` に出す（[`File.hs`](https://github.com/tett23/golem/blob/33a39d0267c440bc32e47b24897f368ed7602d0c/modules/golem-eval/src/Golem/Eval/File.hs#L511)）。`noticeCodes` に入っている（[`Diagnostic.hs`](https://github.com/tett23/golem/blob/33a39d0267c440bc32e47b24897f368ed7602d0c/modules/golem-syntax/src/Golem/Syntax/Diagnostic.hs#L120)）。
- `noticeCodes` に無いコードを `silence-notices` に書くと G03024 になる（[`Manifest.hs`](https://github.com/tett23/golem/blob/33a39d0267c440bc32e47b24897f368ed7602d0c/modules/golem-project/src/Golem/Project/Manifest.hs#L523-L536)）。廃止した notice の前例は G02065 と G02129 である。
- `docs/compatibility.md` の廃止予定の一覧と `docs/markup.md` は、`@set` の notice のコードを G02154 と誤って書いている。G02154 は表の行のセルの数のエラーである。
- リポジトリで追跡している `.gm` のファイルには、行頭の `set 名前 = ` が 16 行ある（`git grep -n -E '^set [A-Za-z_][A-Za-z0-9_-]* = ' -- '*.gm'`）。このほかに、`scripts/manual/build-info.sh` が、追跡しない `common/build-info.gm` に `set edition = ...` などの三行を書く。

## 実装すること

### 宣言

- 原稿のファイル内の変数は、コードブロックの外の行頭の `@set 名前 = 式` で宣言する。
- `@set` の読み方（名前、右辺、有効範囲、予約名、二度の定義、ファイル間の取り込み、エラーの位置）は、PR #947 の前（[`03e37f02`](https://github.com/tett23/golem/blob/03e37f02db7794e9dec3a8a3319bcd4f6d6c69b9/docs/markup.md) の `docs/markup.md` と `docs/specifications.md`）の規則に戻す。
- 行頭の `set 名前 = 式` は、宣言として読まず、`set` で始まらないほかの段落の行と同じ規則で本文として読む。
- 参照は、今のとおり `[= 名前]` と書く。
- 文法から `SetDeclarationStart` を消し、パーサーを生成し直す。AST の `SetVar` は、PR #947 の前の形（`@` の位置を持たない形）に戻す。LSP は、その形に合わせる。
- エディタの文法と golem-fmt の実装は、`@set` だけを扱っているので変えない。

### G02155

- G02155 を出さない。`@set` は廃止予定ではなくなる。
- G02155 を `noticeCodes` から外し、`docs/diagnostics.md` の状態を「廃止」にする。`silence-notices` に G02155 を書いたプロジェクトは、G02065 と G02129 と同じく G03024 になる。
- 新しいコードは設けない。

### 原稿、スクリプト、テスト

- リポジトリの `.gm` のファイルの `set 名前 = 式` の宣言を、すべて `@set 名前 = 式` に書き換える。
- `scripts/manual/build-info.sh` が書く宣言と、`scripts/manual/test.sh` と `scripts/visual/test.sh` の期待を `@set` に戻す。
- PR #947 が `set` に書き換えたテストの原稿（Haskell の文字列を含む）を `@set` に戻す。G02155 を期待するテストは、消すか、I3 の期待に直す。
- `scripts/determinism` と `scripts/visual/pages` のハッシュは、組み直した結果で更新する。

### 文書

- 仕様書、`docs/markup.md`、README、`docs/diagnostics.md` とその埋め込み（`golem explain`）、マニュアルと開発者のマニュアルを、この ADR に合わせて直す。
- `docs/compatibility.md` の廃止予定の一覧から `@set` の行を除き、一覧の前の数を直す。`docs/markup.md` の G02154 の誤りも直す。
- [ADR 0336](0336-unprefixed-variable-declarations.md) のステータスの行を、この ADR で置き換えたことを示す `superseded` にする。

## 実装しないこと

- 行頭の `set 名前 = 式` の本文に、宣言の書き誤りの疑いを知らせる diagnostic を設けること。その行は、正しい本文でありうるためである。
- 参照に `@` を付けること。
- `@import` などほかのブロックコマンドと、Emet の構文を変えること。
- `experiments/syntax/review/` の [ADR 0336](0336-unprefixed-variable-declarations.md) の記録を消すこと。[ADR 0336](0336-unprefixed-variable-declarations.md) がリンクしている記録である。

## 不変条件

- I1: コードブロックの外の行頭の `@set 名前 = 式` は、名前が予約名でも定義済みでもなく、式に誤りが無ければ、変数を宣言し、後の `[= 名前]` はその値を返す。
- I2: 行頭が `set` で始まる行とコードブロックの中の行は、変数を宣言しない。
- I3: どの原稿の評価も、G02155 を出さない。
- I4: `silence-notices` に G02155 を書いたプロジェクトは、G03024 になる。
- I5: 参照に `@` を付けた `[= @名前]` は、G01020 になる。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| `@set x = "abc"` の後の `[= x]` | 本文に abc を出し、diagnostic を出さない | I1, I3 |
| `@set x =` | G01020 | I1 |
| `set x = "abc"` の後の `[= x]` | `set x = "abc"` を本文に出し、`[= x]` は G02002 | I2 |
| `set up is easy` | 本文 | I2 |
| `set xs = [1, 2]` | 本文として読み、G01021 | I2 |
| コードブロックの `@set x = 3` の後の `[= x]` | コードブロックはそのまま掲載し、`[= x]` は G02002 | I2 |
| `[= @x]` | G01020 | I5 |
| `silence-notices = ["G02155"]` | G03024 | I4 |

## 受けいれ条件

- A1: 実装のコミットで、`git grep -n -E '^set [A-Za-z_][A-Za-z0-9_-]* = ' -- '*.gm'` が、コードブロックの外の宣言のつもりの行を返さない。`scripts/manual/build-info.sh` が書く宣言も `@set` である。実装の PR で一度だけ確かめ、CI には置かない。行頭の `set` で始まる本文は正しい原稿でありうるためである。

## テスト設計

テストの名前は `ADR 0391 I<n>: ` で始める。

- I1、I2、I5 は、golem-parser と golem-eval のテストで、境界の表の行をそれぞれ一つのケースとして書く。
- [ADR 0336](0336-unprefixed-variable-declarations.md) の名前を持つ五つのテスト（golem-eval、golem-parser、golem-fmt、golem-lsp の 2 つ）は、この ADR の不変条件に合わせて期待を直し、名前を `ADR 0391` に付け直す。golem-fmt の `set   x = 3` は本文なので、整形の前後で変わらないことを確かめる。
- I3 は、旧記法を使う golem-eval のテストで、G02155 が出ないことを確かめる。
- I4 は、G02065 と G02129 の前例と同じく、golem-driver のテストで確かめる。
- A1 は、実装の PR の本文に、`git grep` の出力を書いて確かめる。

## トレードオフ

- [ADR 0336](0336-unprefixed-variable-declarations.md) の後に `set 名前 = 式` で書いた原稿は、宣言でなく本文になる。リリースに含まれていないので、影響を受けるのは main を使っていた原稿だけである。
- 行頭の `@` を書き忘れた宣言は、宣言の書き誤りを知らせる diagnostic を出さずに本文になる。右辺に `[` があれば、本文の記法の誤り（G01021 など）になる。後で `[= 名前]` と参照すれば G02002 になるので、そこで気づける。参照しない変数では気づけない。

## 参考文献

- [ADR 0336](0336-unprefixed-variable-declarations.md)
- [互換性と廃止の手順（ADR 0174）](0174-compatibility-promises-for-1-0.md)
- [Golem 言語仕様](../markup.md)
