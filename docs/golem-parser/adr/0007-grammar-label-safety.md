# ADR 0007: 文法のラベルを安全にする

ステータス: 採択

## 文脈

peg-hs をコミット 35915bc に上げたところ、生成器がラベルの安全性を検査するようになった（[peg-hs ADR 0028](https://github.com/tett23/peg-hs/blob/35915bc3b1586cc8c69ddbdf41a183be4dcdff8b/docs/adr/0028-label-safety-check.md)）。
`CABAL=cabal-3.16.1.0 scripts/gen-parser.sh` を実行すると、`modules/golem-parser/grammar/Golem.peg` の 15 か所のラベルに「正しい入力を拒むかもしれない」という警告が出る。
生成物は変わらず、警告は生成を止めない。

peg-hs の言う安全は、[peg-hs ADR 0029](https://github.com/tett23/peg-hs/blob/35915bc3b1586cc8c69ddbdf41a183be4dcdff8b/docs/adr/0029-label-safety-implementation-deviations.md) で次のように定まっている。
ラベル `e ^l` が安全であるとは、ほかのラベルをすべて外した文法で、`e` が失敗する入力のどれについても解析全体が失敗することをいう。
すべてのラベルが安全なら、ラベルを付けた文法とすべて外した文法は同じ言語を受理する。
検査は入力の次の一文字による近似であり、安全と判定したものは安全だが、安全なものに警告することがある。
作者が確かめたラベルは `%safe label` で警告を止める。

Golem の文法は、ラベルを二つの目的で使っている。
一つは回復の位置を決めること（[ADR 0002](0002-parser-on-peg-hs.md)）、もう一つは仕様が誤りとする入力を拒むことである。
後者の典型は `BadIndent <- Ind(ind) [ \t] (&{ False })^indent` のような、必ず失敗する式に付けたラベルである。
ラベルを外すとこの規則は単に失敗し、次の選択肢が試される。
次の選択肢がその入力を受理すれば、拒むはずの入力が受理される。
つまり、ラベルが言語を定めている。
[ADR 0002](0002-parser-on-peg-hs.md) は「ラベルは、その位置で失敗したらどの選択肢でも成功しえない場所にだけ付ける」と定めており、この使い方はその定めに反する。

### 警告の一覧と判定

ラベルを外した文法を `peg-hs --strip-labels` で生成し、現在の生成物と並べて、小さな入力での受理と拒否を比べた（入力と結果は後の節に記す）。
判定はその結果と、文法を読んで確かめた失敗の伝わり方による。

| 位置 | ラベル | 規則 | 判定 | 根拠 |
|---|---|---|---|---|
| 112:10 | `block` | `Block` の選択の全体 | 文法を直す | 空のファイルと空行だけのファイルで、`Blocks(0)` がファイルの終わりで `Block` を試して送出する。`""`、`"\n"` が G0110 になる |
| 125:29 | `indent` | `BadIndent` | 文法を直す | ラベルを外すと `Paragraph` が行頭の空白を地の文として受理する（`" foo\n"` を受理する）。また、改行のない末尾の空白だけの行（`"a\n\n  "`）を空行とみなさず、G0111 にしている |
| 128:28 | `def_orphan` | `OrphanDef` | 安全 | `=:` で始まる行は、`DefNew` 以外のどの規則も読めない。`Paragraph` は `BlockStart` の `'=' [ \t:]` で拒む |
| 169:16 | `heading_level` | `TooDeep` | 安全 | `####` の後は `Ws` が失敗し、`#` で始まる行は `Paragraph` が拒む |
| 208:37 | `comment_close` | `Comment` | 安全 | `%%` はどの地の文の規則（`Text`、`SlotText`、`CellText`）も読めない |
| 211:43 | `comment_close` | `ProofComment` | 安全 | 同上。続く `Comment` も同じ位置で閉じずに失敗する |
| 216:55 | `close` | `InlineCommand` | 安全 | `[` は地の文の規則が読めず、`BadBracket` はラベルを外すと必ず失敗する |
| 222:19 | `bracket` | `BadBracket` | 安全 | 同上 |
| 231:49 | `arg_order` | `Arguments` | 安全 | `Arguments` が失敗すると、命令文脈とブロックコマンドの行が失敗し、`[` と `@` で始まる行はほかの規則が読めない |
| 244:33 | `close` | `SplatArgument` | 文法を直す | 裸の語（`Word`）が `*` を読めるので、`*[` の展開に失敗すると `*` を位置引数として読み直す。`"[f *[x y]]"` は `*` と入れ子の命令文脈 `[x y]` として受理される |
| 292:30 | `close` | `ExprCtx` | 安全 | `[=` は命令文脈（識別子が要る）も地の文も読めない |
| 298:16 | `expr` | `ExprBody` | 文法を直す | 244:33 と同じ理由で、`"[f *[= 1]]"` が `*` と式文脈 `[= 1]` として受理される。式文脈と `@set` の中では安全である |
| 492:29 | `table_delimiter` | `Table` | 安全 | `\|` で始まる行は表しか読めない |
| 496:36 | `table_cells` | `TableBodyRow` | 文法を直す | ラベルを外すと、セルの数の合わない行の手前で表が終わり、その行から次の表が始まりうる。`"\| a \| b \|\n\|---\|---\|\n\| 1 \|\n\|---\|\n"` が二つの表として受理される |
| 529:14 | `code_close` | `CodeBlock` | 安全 | ```` ``` ```` で始まる行は `Paragraph` が拒み、ほかの規則も読めない |

「安全」と判定した 9 か所が警告を受ける原因は、どれも検査の近似にある。

- `Ind(n)` は `&{ n == 0 }` の意味述語と引数で書いた規則であり、検査は意味述語を「どの文字でも成功しうる」とみなす。ブロックの選択肢はどれも `Ind(ind)` で始まるので、行頭の空白の後に記号が要ることを検査は使えない（`indent`、`def_orphan`、`heading_level`、`bracket`、`table_delimiter`、`code_close`）。
- `BadBracket` の `&{ False }` も意味述語なので、成功しうるものとみなされる（`close` の 216:55、`arg_order`）。
- `%%` と `[=` の区別には二文字目が要る（`comment_close`、`close` の 292:30）。

文法を直す 5 か所も、直した後に警告は消えない。
同じ近似のためである。
直した後は 9 か所と同じく安全であり、`%safe` を付ける。

## 実装すること

### 文法の変更

`modules/golem-parser/grammar/Golem.peg` を次のように変える。

1. 空のファイルを受理する。

   ```
   File <- BlankLines? (&. Blocks(0) BlankLines?)? { () }
   ```

   ファイルの終わりで `Blocks(0)` を試さないので、`block` が送出しない。

2. 改行で終わらない末尾の空白だけの行を空行とする。

   ```
   BlankLine <- Ws? Nl { () }
              / Ws !. { () }
   ```

   [ADR 0003](0003-block-grammar.md) の「空白だけの行も空行とみなす」「末尾の改行の有無は問わない」を、末尾の行にも適用する。
   これまでは `"# h\n  "` が G0111 になっていた。

3. 段落の行頭の空白を拒む。

   ```
   Paragraph <- Ind(ind) ![ \t] !BlockStart Inline(ind)+ (Nl / !.) { () }
   ```

   ラベルを付けた文法では、行頭の空白は先に `BadIndent` が送出するので、受理する言語は変わらない。
   ラベルを外した文法でも、インデントの誤りを拒むようになる。

4. 位置引数の裸の語を、展開の記号で始めない。

   ```
   PosArg <- !(Word Eq) SplatArgument { () }
           / !(Word Eq) !Splat Argument { () }
   ```

   `*[` と `**[` は常に展開の始まりとして読む（docs/markup.md）。
   `*` だけの裸の語（後ろに `[` が続かないもの）は、これまでどおり書ける。

5. 表の直後の行が `|` で始まるなら、表の行として読めなかったことを誤りにする。

   ```
   Table <- h:TableRow(ind) Nl (TableDelimiter(ind))^table_delimiter
            TableBodyRow(ind, h)* (!(Nl Ind(ind) Pipe))^table_row (Nl / !.) { () }
   ```

   ```
   %recover table_row SkipBlock
   ```

   [ADR 0003](0003-block-grammar.md) は「行頭が `|` で始まる連続した行が一つの表である」と定めている。
   ラベルを外した文法でも表が途中で終わらないようにするためである。
   新しいラベル `table_row` は、表の行として読めない行（`|abc` のように閉じる `|` のない行）で送出する。
   これまでこの行は、表が終わった後の `block`（G0110）になっていた。

### `%safe` と理由

すべてのラベルに、理由のコメントを付けて `%safe` を書く。
ラベルの宣言（`%recover`）の直後に置く。

```
# The checker treats the predicate of Ind(n) as succeeding on any character;
# every alternative of Block starts with Ind(ind), and after it each needs a
# mark that the failing input does not have (golem-parser ADR 0007).
%safe block
%safe indent
%safe def_orphan
%safe heading_level
%safe table_delimiter
%safe table_row
%safe code_close
# BadBracket's &{ False } looks like it may succeed to the checker.
%safe bracket
%safe arg_order
# Telling %% from %, [= from [ and *[ from * needs the second character.
%safe close
%safe comment_close
%safe expr
# A row whose cell count differs is followed by the !(Nl Ind Pipe) check,
# which fails on that very row.
%safe table_cells
```

`%safe` はラベルの名前で効くので、`close` の三か所（216:55、244:33、292:30）と `comment_close` の二か所は一行でまとめて止まる。
三か所すべてが安全になってから付ける。

### 再生成のスクリプトと CI

- `scripts/gen-parser.sh` の生成に `--Werror` を付ける。今後、理由を書かずにラベルを足すと再生成が失敗する。
- 同じスクリプトで、ラベルを外した文法を `modules/golem-parser/test/StrippedGrammar.hs`（モジュール名 `StrippedGrammar`）に生成する。

  ```sh
  "$PEG" modules/golem-parser/grammar/Golem.peg --strip-labels StrippedGrammar \
    -o modules/golem-parser/test/StrippedGrammar.hs
  ```

- CI の「Generated parser matches the grammar」の段で、`StrippedGrammar.hs` も `git diff --exit-code` の対象に加える。fourmolu と hlint の対象からも、`Generated.hs` と同じく外す。
- `golem-parser.cabal` のテストスイートの `other-modules` に `StrippedGrammar` を加え、生成物の警告を抑える `ghc-options`（ライブラリの `Generated` と同じもの）をテストスイートにも付ける。

### peg-hs の版

peg-hs 35915bc の `--strip-labels` は、Golem の文法からはコンパイルできないモジュールを生成する。
この ADR を書いた時点の最新の main（437bcd8）でも同じであることを、`parseSkipBlock` の型の宣言が 5 回現れることで確かめた。
複数のラベルが同じ回復の規則を使うと（`SkipBlock` は 5 つ、`SkipParagraph` は 3 つのラベルが使う）、回復の規則の入口（`parseSkipBlock` など）を同じ名前で重複して定義するためである。
peg-hs でこれを直し（入口を規則ごとに一つにする）、`cabal.project` の peg-hs のコミットを上げる。
版を上げるには ADR が要るので（[ADR 0002](0002-parser-on-peg-hs.md)）、この ADR で上げることを決めておく。
peg-hs の修正は peg-hs の ADR として行い、そのコミットに固定する。

### 診断

`Golem.Parser.labelCode` に `table_row` を加える。

| ラベル | 診断コード | メッセージ |
|---|---|---|
| `table_row` | G0123 | 表の行は `\|` で始まり `\|` で終わります |

G0123 は未使用である（G0110 から G0122 までと、既定の G0129 が使われている）。

### 仕様書の更新

- `docs/specifications.md` の「v1 の実装で次の段階以降に回した項目」から、文法のラベルの安全性の項目を外す。
- [ADR 0003](0003-block-grammar.md) の回復のラベルの表に `table_row` がないことは、この ADR で補う。[ADR 0003](0003-block-grammar.md) のステータスの行を「採択→回復のラベルの追加（table_row）は ADR 0007」に変える。

## 実装しないこと

- peg-hs の検査の改良（二文字の先読み、意味述語で判定する文字の範囲の宣言）。[peg-hs ADR 0029](https://github.com/tett23/peg-hs/blob/35915bc3b1586cc8c69ddbdf41a183be4dcdff8b/docs/adr/0029-label-safety-implementation-deviations.md) が別の ADR に回している。
- ラベルを使わずに書ける誤りの検出への書き換え。誤りの文言と回復の位置を保つため、ラベルは残す。
- `*` を含む裸の語のほかの不整合（`a*[x]` が `a*` と `[x]` の二つの引数として読まれることなど）。安全性とは別の問題であり、受理する言語はこの ADR の前後で変わらない。

## テスト設計

`modules/golem-parser/test` に加える。
文法の変更の前に書き、失敗させる。

### 言語の一致

`StrippedGrammar.parse` が `Right` を返すことと、`Golem.Parser.parse` の診断が空であることが一致するかを確かめる。

- 断片の組み合わせ：`ParserSpec` の `fragment` の断片に `"*"`、`"[= "`、`"x"`、`"|"`、`"| 1 |"`、`"|abc"`、`"\n  "`、`"**[= 1]"` を加え、三つまでのすべての連結（約 4.8 万通り）で一致すること。
- 無作為な原稿：既存の hedgehog の生成器（`fragment` を 30 個まで連結したもの）で 500 件、一致すること。
- 変異：`modules/golem-driver/test/fixtures` の `sample` の各ファイルと `tempest.gm`、`kanikosen.gm` について、等間隔に選んだ 100 の位置（大きいファイルは 20）で一文字の削除と重複を作り、すべてで一致すること。

### 新しく受理する入力

- `""`、`"\n"`、`"\n\n"`、`"  \n"` が診断なしで解析されること。
- `"a\n\n  "`、`"# h\n  "`、`"a\n\n\t"` が診断なしで解析され、AST が `"a\n"`、`"# h\n"`、`"a\n"` と一致すること。

### 拒む入力と診断

- `"[f *[x y]]\n"` が G0117、`"[f *[= 1]]\n"` と `"[f **[= 1]]\n"` が G0120 であること（今も同じ診断であり、変わらないことを確かめる）。
- `"| a |\n|---|\n|abc\n"` が G0123 であり、続く段落が正しく解析されること。
- `"- \n  "` が `"- \n"` と同じく診断になること。これまでは末尾の空白を項目の続きとして受理しており、改行で終わる場合とで結果が違った。

### 既存のテスト

ParserSpec、CSTSpec、LowerSpec の既存のテストは、期待値を変えずに通ること。
`labelCode` の対応表の検査（文法のラベルと表の一致）に `table_row` が含まれること。
golem-fmt、golem-lsp、golem-driver のテストが通り、二冊の fixture のビルドの出力がバイト単位で変わらないこと。
文法の変更が変えるのは、これまで拒んでいた入力の扱いと `|abc` の診断だけだからである。

### 再生成

- `scripts/gen-parser.sh` が警告なしで終わること（`--Werror` で失敗しないこと）。
- `%safe` の行を一つ消すと、`scripts/gen-parser.sh` が失敗すること。手で一度確かめる。

## 文法の変更を試した結果

この ADR を書く前に、上の 5 つの変更を加えた文法を作業用のディレクトリで生成し、ラベルを外した変種と比べた。

| 比べたもの | 入力 | 一致しない入力 |
|---|---|---|
| 現在の文法とラベルを外した変種 | 断片の三つまでの連結 47,989 件 | 3,279 件 |
| 変更後の文法とラベルを外した変種 | 同上 | 0 件 |
| 変更後の文法とラベルを外した変種 | fixture の 4 ファイルと各ファイルの変異 544 件 | 0 件 |

現在の文法と変更後の文法とで受理が変わった 322 件は、すべて空白に関わる入力だった。
306 件は今は拒み変更後は受理する入力（空のファイル、空行だけのファイル、末尾の空白だけの行）である。
16 件は今は受理し変更後は拒む入力であり、どれも中身のない項目の後に末尾の空白だけの行が続く形（`"- \n  "` など）だった。
`"- \n"` は今も拒んでいるので、この 16 件は末尾の空白が項目の中身として数えられていたことによる。

ラベルを外した変種のコンパイルには、重複した入口の定義を手で取り除いた。
peg-hs の修正が要る理由である。

## トレードオフ

すべてのラベルに `%safe` を付けるので、検査は新しいラベルの見落としを防ぐ役にしか立たない。
既存のラベルの安全性は、作者の主張と、ラベルを外した変種との比較のテストに頼る。
比較のテストは有限の入力でしか確かめられず、証明ではない。

ラベルを外した変種をテストのために生成してコミットするので、生成物が一つ増え、文法を変えるたびに二つのファイルが変わる。

`*[` を常に展開として読むので、`*` の後に入れ子の命令文脈や式文脈を空白なしで続ける書き方はできない。
今もラベルが拒んでいる書き方であり、原稿に書けることは減らない。
