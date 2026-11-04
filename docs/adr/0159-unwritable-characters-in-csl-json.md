# ADR 0159: CSL-JSON の出力に書けない文字を、参考文献のファイルを読むときに G03108 で拒む

ステータス: 採択（未実装）

## 文脈

[ADR 0042](0042-control-characters-and-glob-metacharacters.md) は、XML 1.0 の `Char` に当たらない文字（U+0000 から U+001F のうちタブ、改行、復帰以外と、U+FFFE、U+FFFF、サロゲートの符号位置）を**出力に書けない文字**と呼び、出力の側で置き換えずに読み込みの段階でエラーにすると決めた。
検査するのは、`manifest.toml` の文字列（G03028）と、原稿、表のファイル、取り込んだコードとテキスト（G02089）である。
参考文献の CSL-JSON のファイルは、この一覧にない。

[2026-10-24 の監査](../audits/2026-10-24-security-audit.md) の C10 は、CSL-JSON の `title` の U+0001 と ESC が、diagnostic なしに HTML と EPUB の XHTML に書かれ、`xmllint` がその XHTML を拒むことを示した。
roadmap の「セキュリティ監査の残り」は、参考文献のファイルを読むときに拒むか、引用と参考文献の項目を組むときに拒むか、どのコードを使うかを ADR で決めるとしている。
[2026-11-05 のセキュリティ監査](../audits/2026-11-05-security-audit.md) の V-03 は、今のソースで同じことを CLI で再現した（[cli-probe.txt](../audits/2026-11-05-evidence/cli-probe.txt)）。
ビルドは終了コード 0 で終わり、HTML の 2 ページと EPUB の 2 ページに U+0001 が残った。

### 今の流れ

`Golem.Driver.loadBibliography` は、manifest の `bibliography` のファイルを読み、`Golem.Doc.Bibliography.Csl.decodeCslJson` で項目にする（[Driver.hs#L584-L603](https://github.com/tett23/golem/blob/709b499ae29a0eb78515d67320f0924f996e4071/modules/golem-driver/src/Golem/Driver.hs#L584-L603)、[Csl.hs#L28-L33](https://github.com/tett23/golem/blob/709b499ae29a0eb78515d67320f0924f996e4071/modules/golem-doc/src/Golem/Doc/Bibliography/Csl.hs#L28-L33)）。
読めないファイルは G03026 で、位置は `manifest.toml` の先頭である。
`Manifest` が値の位置を持たず、CSL-JSON のファイルは diagnostic の位置を持てる原稿ではないためである。
項目の文字列は、HTML では `escapeXml` を通るだけで XHTML に書かれる（[Html.hs#L471-L479](https://github.com/tett23/golem/blob/709b499ae29a0eb78515d67320f0924f996e4071/modules/golem-html/src/Golem/Html.hs#L471-L479)）。

### 読むときか、組むときか

組むときに拒むと、引用されて出力に届いた項目だけを検査することになる。
同じファイルでも、原稿がどの項目を引用するかで、diagnostic が出たり出なかったりする。
読むときにファイル全体を検査すれば、ファイルが同じなら結果は同じである。
[ADR 0042](0042-control-characters-and-glob-metacharacters.md) も、XML の出力だけで拒むとターゲットによって同じ原稿が通ったり止まったりするとして、ターゲットを問わず読み込みで拒むと決めた。
同じ理由で、読むときにファイル全体を拒む。

### コード

G03028 と G02089 は、出力に書けない文字という同じ性質を、書いた場所（`manifest.toml` と原稿）で分けたコードである。
直す人が開くファイルと、位置の示し方が違うためである。
CSL-JSON のファイルは、どちらとも違うファイルで、位置の示し方も違う（`manifest.toml` の先頭に、ファイルのパスと JSON の中の場所を書く）。
G02089 を広げると、`SrcSpan` で原稿の位置を示すコードに、位置を持たない別のファイルの誤りが混ざる。
G03026 を広げると、「ファイルを読めない」と「読めたが中身に書けない文字がある」という別の原因が一つのコードになる。
どちらも「一つのコードに一つの原因」に反するので、新しいコードにする。

プロジェクトの段階の新しい番号は G03101 からだが、G03101 から G03107 は、破棄した [ADR 0149](0149-gmx-requirements-and-driver-handlers.md) と [ADR 0150](0150-calling-gmx-functions-from-gm.md) の草稿が使い、それを出し直す .gmx の草稿も同じ番号を使っている。
どれも実装されていないが、番号が重ならないように飛ばし、G03108 を使う。
`docs/diagnostics.md`、origin の `main`、この ADR を書いた時点の ADR とその草稿のどれも G03108 を使っていないことを確かめた。

## 実装すること

### 検査（G03108）

- 参考文献のファイルを JSON として読めた後、JSON の値の全体をたどり、すべての文字列とオブジェクトのキーを、[ADR 0042](0042-control-characters-and-glob-metacharacters.md) の出力に書けない文字の定義で検査する。引用されているかどうか、Golem が読むフィールドかどうかを問わない。
- 出力に書けない文字が一つでもあれば、そのファイルの項目を一つも使わず、新しいエラー G03108 を出す。G03026 と同じく、ファイルを読めなかった場合と同じ扱いとする。
- たどる順は、配列の添字の小さい順、オブジェクトのキーの符号位置の順とする。aeson の `KeyMap` の並びには依らない。この順で最初に見つかった文字列を報告する。
- 一つのファイルに一つの G03108 を出す。最初のもののほかにも出力に書けない文字を持つ文字列があれば、その数を `ほか <n> 件` で添える。
- メッセージは `参考文献のファイルに出力に書けない文字（<符号位置>）があります: <パス>（<JSON Pointer>）[、ほか <n> 件]` とする。
  - `<符号位置>` は G02089 と同じ `U+0001` の形である（`Golem.Syntax.Chars.codePointText`）。
  - `<JSON Pointer>` は、ファイルの根からの RFC 6901 の形（`/3/title`、`/0/author/1/family`）とする。キーの中の文字なら、そのキーを指す。項目の `id` で示さないのは、`id` がない項目と、`id` そのものに書けない文字がある項目があるためである。
- 位置は、G03026 と同じく `manifest.toml` の先頭である。
- G03108 は dev と prod の両方でエラーであり、ターゲットを問わず出す。LSP も、今の参考文献の diagnostic と同じく出す。

### 置き場所

- 文字列をたどる検査は golem-doc の `Golem.Doc.Bibliography.Csl` に置き、`CslJsonError` に構成子 `CslUnwritable` を足す。値は、最初の文字、JSON Pointer、ほかの件数である。
- `decodeCslJson` は、JSON として読めて配列であったときに検査し、出力に書けない文字があれば `CslUnwritable` を返す。
- `loadBibliography` は、`CslUnwritable` を G03108 にする。
- golem-doc は golem-syntax にすでに依存しているので、`firstUnwritable` と `codePointText` を使っても、パッケージの依存は変わらない。

### ドキュメント

- `docs/diagnostics.md` に G03108 の節を足す。G02089 と G03028 の節から、参考文献のファイルは G03108 であることを相互に示す。
- 仕様書の参考文献の節と、出力に書けない文字を書いた箇所に、CSL-JSON のファイルを加える。
- golem-doc の仕様書の CSL-JSON の読み方に、検査を書く。
- 利用者向けマニュアルの参考文献の章と diagnostic の付録に G03108 を書く。
- `docs/roadmap.md` の「CSL-JSON の制御文字」の項目を消す。

## 実装しないこと

- 引用と参考文献の項目を組むときに拒むこと。理由は「読むときか、組むときか」にある。
- 出力に書けない文字を置き換えるか取り除いて読むこと。[ADR 0042](0042-control-characters-and-glob-metacharacters.md) のとおり、入力と出力を黙って食い違わせない。
- U+007F と C1 制御文字の拒否。[ADR 0042](0042-control-characters-and-glob-metacharacters.md) の定義のとおり、XML が許すので含めない。
- CSL-JSON のファイルの中の位置（行と桁）を diagnostic の位置にすること。CSL-JSON のファイルを原稿と同じ位置を持つファイルとして登録する変更が要る。
- G02089 と G03028 を一つにすること。

## テスト設計

どれも、変更の前に失敗することを確かめてから実装する。

- golem-doc（`decodeCslJson` の単体テスト）
  - `title` に `\u0001` を持つ項目で `CslUnwritable` を返し、文字は U+0001、JSON Pointer は `/0/title` である。
  - `\u001b`（ESC）、`\u0000`、`￾`、`￿` でも返す。
  - 引用されないフィールド（`note`）と、Golem が読まないフィールド（`abstract`）の中でも返す。
  - オブジェクトのキーに `\u0001` があれば、そのキーを指す JSON Pointer を返す。
  - `/` と `~` を含むキーは、RFC 6901 のとおり `~1` と `~0` で書く。
  - 二つの項目に書けない文字があれば、添字の小さいほうを報告し、ほかの件数を 1 とする。一つの項目の中では、キーの符号位置の順で最初のものを報告する（`title` と `author` なら `author` の中）。
  - タブ、改行、復帰、U+007F、U+0085、日本語の文字列、サロゲートの対で書いた U+1F600 は通る。
- golem-driver
  - 2026-11-05 の監査の再現と同じく、fixture の `refs.json` の引用される項目の `title` に `\u0001` を入れたプロジェクトで、`golem build --target html --target epub` が G03108 を出し、終了コード 1 で、HTML と EPUB を書かない。メッセージにパス、`U+0001`、JSON Pointer がある。
  - 同じプロジェクトで、`--target pdf` と `--target text` も G03108 を出す。
  - 引用されない項目にだけ書けない文字があっても G03108 を出す。
  - G03108 が dev と prod の両方でエラーである。
  - 書けない文字のない fixture の出力が、この変更の前とバイト列で同じである。
- golem-lsp
  - 書けない文字を持つ参考文献のファイルのプロジェクトで、`manifest.toml` に G03108 が出る。
- `docs/diagnostics.md` の G03108 の節は、golem-driver の既存のテスト（使っているコードが文書に載っていること）が確かめる。

## トレードオフ

- 引用されない項目の書けない文字でもビルドが止まる。Zotero などから書き出した大きなファイルでは、使わない項目を直す手間が出る。その代わり、どの項目を引用するかで結果が変わらない。
- ファイルの一つの誤りで、そのファイルのすべての項目が使えなくなる。その項目を引用する箇所には、引用の側の diagnostic も出うる。読めないファイル（G03026）と同じ扱いにそろえた。
- 位置が `manifest.toml` の先頭なので、エディタで誤りの場所に飛べない。メッセージの JSON Pointer で場所を示す。

## 決めたことの記録

- **採択**：メンテナーが採択した（2026-11-05）。この ADR が決めてほしい点として挙げた項目は、どれも ADR の推奨のとおりとする。

## 参考文献

- [2026-10-24 のセキュリティ監査](../audits/2026-10-24-security-audit.md) の C10
- [2026-11-05 のセキュリティ監査](../audits/2026-11-05-security-audit.md) の V-03、[cli-probe.sh](../audits/2026-11-05-evidence/cli-probe.sh)、[cli-probe.txt](../audits/2026-11-05-evidence/cli-probe.txt)
- W3C, "Extensible Markup Language (XML) 1.0 (Fifth Edition)", 2.2 Characters. https://www.w3.org/TR/xml/#charsets
- IETF, RFC 6901 "JavaScript Object Notation (JSON) Pointer". https://www.rfc-editor.org/rfc/rfc6901
- Citation Style Language, "CSL-JSON schema". https://github.com/citation-style-language/schema
