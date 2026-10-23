# ADR 0003: `golem fmt` は単独の CR も LF に直す

ステータス: 採択、引数なしの `golem fmt` が CR を含む原稿を読む手順は [ADR 0004](0004-fmt-without-arguments-fixes-cr.md)

## 文脈

原稿のファイルに CR があると、構文の段階で G01003（改行に CR が含まれている）のエラーになる。
G01003 は、CRLF の改行の CR も、単独の CR も対象にし、原稿のファイルの diagnostic には修正案「golem fmt で LF に直す」を付ける（docs/diagnostics.md、[golem-parser ADR 0009](../../golem-parser/adr/0009-syntax-diagnostic-codes.md)）。

ところが、`golem fmt` の前処理（`Golem.Fmt.preprocess`）が直すのは CRLF だけである。
[ADR 0001](0001-formatter.md) が「CRLF を LF に直す」とだけ決め、単独の CR を扱わなかったためである。
テストの質を上げる作業（2026-10-23）で、`format "a\rb\n"` が `Formatted "a\rb\n"` を返すことが分かった。

そのため、単独の CR を含む原稿は、G01003 の修正案のとおりに `golem fmt` を実行しても直らず、同じエラーが出続ける。
diagnostic の案内と、案内された道具の振る舞いが食い違っている。

## 実装すること

- `golem fmt` の前処理で、CRLF を LF に直した後に、残った単独の CR も LF に直す。単独の CR は、古い Mac の改行の名残であり、改行として扱うのが書き手の意図に近い。
- 順は、CRLF を先に一つの LF に直してから単独の CR を直す。逆にすると、CRLF が二つの改行になる。
- 整形の後の AST が整形の前と同じであることを確かめる今の安全網は変えない。前処理は構文の解析より前に行う（`Golem.Fmt.format`）ので、CR を直した後の原稿に、今の安全網がそのまま働く。
- G01003 のメッセージと修正案は変えない。

### ドキュメント

- 仕様書の fmt の節の、前処理の一覧に「単独の CR を LF に直す」を足す。
- 使い手のマニュアルの `golem fmt` の説明に、単独の CR も直すことを足す。
- [ADR 0001](0001-formatter.md) のステータスの行に「、単独の CR の扱いは [ADR 0003](0003-lone-cr-to-lf.md)」を足す。

## 実装しないこと

- `style.toml` を整形すること。今のとおり `golem fmt` は `style.toml` を扱わず、G01003 の修正案も付けない。
- ほかの改行の文字（U+2028、U+0085 など）を直すこと。

## テスト設計

テストを先に書き、今の実装で失敗することを確かめる。

- golem-fmt：`format "a\rb\n"` が `"a\nb\n"` を返すこと。今は `"a\rb\n"` を返すので失敗する。
- golem-fmt：`format "a\r\nb\n"` が `"a\nb\n"`（二つの改行にならない）、`format "a\r\r\nb\n"` が `"a\n\nb\n"` を返すこと。
- golem-fmt：末尾の単独の CR（`"a\r"`）が `"a\n"` になること。
- golem-cli：単独の CR を含む章を `golem fmt` で直した後、`golem check` が G01003 を出さないこと。

## トレードオフ

- 単独の CR を本文の文字として残したい書き手は、`golem fmt` で失う。G01003 が CR をエラーにするので、そうした原稿は今も組めず、失うものはない。

## 参考文献

- [ADR 0001](0001-formatter.md)
- [golem-parser ADR 0009](../../golem-parser/adr/0009-syntax-diagnostic-codes.md)
