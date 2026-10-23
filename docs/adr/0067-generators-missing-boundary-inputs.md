# ADR 0067: プロパティテストの生成器に、境界の入力を出させる

ステータス: 採択

## 文脈

プロパティテストは、生成器が出す入力の範囲でしか検査にならない。
2026-10-23 のテストの品質の点検は、生成器が危ない入力を出さない箇所を五つ挙げた。
コードと照らし合わせ、次の三つは穴であることを確かめた。

- genText（[golem-syntax のテスト](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-syntax/test/Main.hs#L26-L31) と [golem-lsp のテスト](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-lsp/test/Main.hs#L55-L60)）は `"ab 漢字かな\n😀𠮷x"` の 11 文字から作る。`\r` が出ない。Golem のソースの CRLF は G01003 のエラーだが（[modules/golem-lsp/test/Main.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-lsp/test/Main.hs#L197-L199)）、エラーの位置を示すために、CR を含む行でも行と列の変換は正しくなければならない。単体テストは CRLF の一例だけを持つ（[modules/golem-syntax/test/RenderSpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-syntax/test/RenderSpec.hs#L139-L141)）。
- [modules/golem-layout/test/LineBreakingSpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-layout/test/LineBreakingSpec.hs#L24-L29) の genFitting は、すべての語が版面に収まる段落だけを作る。「[すべての語を一度ずつ順に置く](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-layout/test/LineBreakingSpec.hs#L43-L46)」は、版面より広い語があっても成り立つべき性質だが、その入力では試していない。版面より広い語の単体テストはある（[modules/golem-layout/test/Main.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-layout/test/Main.hs#L398-L402)）。
- [modules/golem-layout/test/PaginateSpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-layout/test/PaginateSpec.hs#L503-L528) の五つのプロパティは、容量（1 ページの行の数）を 2 から 9 で生成し、ブロックの列を 1 個以上で生成する。容量 1 は [単体テスト](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-layout/test/PaginateSpec.hs#L163-L164) が一例だけ持つ。

残る二つは、穴ではないか、穴が小さい。

- golem-doc の [genFloat](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-doc/test/Gen.hs#L119-L142) に NaN、無限大、-0.0 がない。golem-eval は NaN と無限大を値として持たず、-0.0 を 0 にする（[modules/golem-eval/src/Golem/Eval/Number.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-eval/src/Golem/Eval/Number.hs#L25-L30)）。これらは評価の結果として IR に入らない。
- [modules/golem-parser/test/ParserSpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-parser/test/ParserSpec.hs#L95-L101) のプロパティは `render (parse s) == s` だけを見る。これは無損失のための性質であり、木の形は単体テストの役目である。点検の報告が挙げた「木の形を見ない」は、このプロパティの目的の外にある。

点検の報告が挙げた結合文字、異体字セレクタ、BOM は、行と列の変換では他の BMP の文字と同じ扱いになり、新しい境界を作らない。
サロゲートの対はすでに `😀` と `𠮷` が出す。

## 実装すること

- genText に `\r` を足す。CR だけの行末と CRLF の両方が出る。行と列の変換のプロパティ（[golem-syntax のテスト](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-syntax/test/Main.hs) と [golem-lsp のテスト](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-lsp/test/Main.hs)）が、CR を行の中の一文字として扱うことを、今の実装の振る舞いに合わせて確かめる。CR を行末として扱うべきかは、[golem-syntax ADR 0001](../golem-syntax/adr/0001-source-spans-and-diagnostics.md) の行の定義に従う。
- LineBreakingSpec に、版面より広い語を含む段落の生成器を足し、「すべての語を一度ずつ順に置く」をその入力でも断言する。「行が版面からはみ出さない」の二つは、収まる段落に限る今の生成器のままとする。
- PaginateSpec の容量の範囲を 1 から 9 にする。見出しの規則（見出しと後の二行を離さない）が容量 1 で満たせない場合の振る舞いは、今の実装を先に確かめ、プロパティが断言する性質（すべての行を一度ずつ順に置く、ページの番号に抜けがない）がそれでも成り立つことを求める。成り立たなければ、実装の誤りとして別に扱う。
- PaginateSpec のブロックの列を 0 個からにし、空の流れでページが一つもないこと（または一ページだけであること。今の実装に合わせる）を断言する。

## 実装しないこと

- genFloat に NaN、無限大、-0.0 を足すこと（上の理由による）。
- ParserSpec のプロパティに木の形の断言を足すこと。

## テスト設計

- genText の変更の後、行と列の変換のプロパティが通ることを確かめる。落ちれば、そのとき出た反例を単体テストとして残し、実装の誤りか仕様の未決かを分けて扱う。
- 版面より広い語：語を一つ捨てる変異（overfull の行の最後の語を落とす）で、新しいプロパティが落ちる。
- 容量 1：容量 1 のとき見出しの行を落とす変異で、新しいプロパティが落ちる。

## トレードオフ

- 生成器が広がるので、反例が見つかり、この ADR の実装のプルリクエストが実装の修正を含むことになりうる。反例と修正は別のプルリクエストに分ける。
- 容量 1 の扱いを先に決めずに今の実装を確かめるので、仕様の未決が見つかる可能性がある。見つかれば roadmap に載せる。

## 参考文献

- [golem-syntax ADR 0001](../golem-syntax/adr/0001-source-spans-and-diagnostics.md)
