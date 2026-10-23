# ADR 0066: 空の結果や Nothing で通ってしまう断言を、中身を確かめる断言にする

ステータス: 採択

## 文脈

「悪いものが含まれていない」という形の断言は、結果が空でも通る。
何もしない実装、すべてを捨てる実装、常に `Nothing` を返す実装が、この形の断言をすり抜ける。
2026-10-23 のテストの品質の点検と、その確認で、次の四つがこの形であることを確かめた。

- [modules/golem-lsp/test/TableWatchSpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-lsp/test/TableWatchSpec.hs#L108-L113)（[ADR 0042](0042-control-characters-and-glob-metacharacters.md) の C14）は `not (any hasBareGlob regs)` を断言する。`regs` が空なら通るので、監視を一つも登録しない実装でも緑になる。[ADR 0042](0042-control-characters-and-glob-metacharacters.md) の 89 行めのテスト設計は、`a[*]b[?].tsv` の glob で登録されることを求めている。
- [modules/golem-lsp/test/Main.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-lsp/test/Main.hs#L341-L352) の「a converted position lies within its line」は、`fromLineCol` が `Nothing` を返せば `success` とする。常に `Nothing` を返す実装でも通る。
- [modules/golem-html/test/XhtmlSpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-html/test/XhtmlSpec.hs#L460-L462) の「escapeXml leaves no markup characters」は、出力に `<`、`>`、`"` が残らないことだけを見る。文字を削る実装でも通る。生成器は `&` を出すが、`&` の扱いは見ていない。具体的な値は [同じファイルの単体テスト](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-html/test/XhtmlSpec.hs#L329-L330) が確かめているので、穴はプロパティの側だけである。
- [modules/golem-fmt/test/Main.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-fmt/test/Main.hs#L95-L103) の二つのプロパティは、整形できない文書（`Unformattable`）では、AST の保存を `discard` し、冪等性は入力をそのまま返す経路で通る。生成した文書のうち何割が整形できたかは、`cover` も `classify` も使っておらず、誰も見ていない。リポジトリのテストで `cover` と `classify` を使う箇所はない。

## 実装すること

- C14：登録されたパターンそのものを断言する。`regs @?= ["data/x[*]y[?].tsv"]` の形にする。点検の報告は `["data/x*y?.tsv"]` を勧めたが、これは [ADR 0042](0042-control-characters-and-glob-metacharacters.md) のテスト設計と逆であり、採らない。
- LSP の位置：`Nothing` になる入力を、行の範囲の外（`l < 0` か `l >= lineCount`）と、文字の途中の列（UTF-8 の多バイトの途中、UTF-16 のサロゲートの対の途中。[LSP の位置の単体テスト](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-lsp/test/Main.hs#L337-L339) の `LineCol 0 1` がこれに当たる）に限ると断言する。文字の境目の列の集合は、テストの中で行の文字列から数えて求める。それ以外で `Nothing` が返れば失敗にする。
- escapeXml：プロパティを、エスケープを戻す関数（テストの中に書く）との往復にする。`unescape (escapeXml t) === t` と、出力に `<>"'` と、実体参照の始まりでない `&` がないことを断言する。生成器に `'` を足す。`'` をエスケープするかどうかは今の実装に合わせ、実装のときに確かめる。
- golem-fmt：二つのプロパティに `cover` を付け、生成した文書のうち整形できたものが 80% 以上であることを求める。満たさなければ、生成器を整形できる文書に寄せる。

## 実装しないこと

- 「含まれていない」形の断言をリポジトリ全体からスクリプトで自動的に探すこと。今回は見つかったものだけを直す。
- `cover` の割合を他のプロパティに広げること。整形できない入力を捨てる形のプロパティは、今は golem-fmt だけである。

## テスト設計

先に断言を変え、次の変異で落ちることを確かめる。
今の断言はどの変異でも落ちない。

- C14：golem-lsp で表のファイルの監視の登録をすべて省く変異。
- LSP の位置：`fromLineCol` が常に `Nothing` を返す変異。
- escapeXml：`<` を空の文字列に置き換える変異。
- golem-fmt：`format` が常に `Unformattable` を返す変異で、`cover` が満たされずに落ちる。80% という値は、今の生成器での割合を一度測ってから決める。測った値が 80% に届かなければ、先に生成器を直す。

## トレードオフ

- 往復の断言は、テストの中に `unescape` を書くぶん長くなる。削る実装と書き換える実装を区別できる。
- `cover` は割合を満たすまで生成を続けるので、golem-fmt のテストの時間が延びることがある。

## 参考文献

- [ADR 0042](0042-control-characters-and-glob-metacharacters.md)
- hedgehog の `cover` と `classify`
