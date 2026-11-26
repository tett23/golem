# ADR 0471: 組み込みのコマンドを、組版と Golem の仕組みに要るもののほかは上書きできるようにする

Status: accepted

## 文脈

[root ADR 0453](0453-override-built-in-commands-by-listed-imports-and-plugins.md) は、名前を並べた取り込みとプラグインで上書きできる組み込みのコマンドを、インラインの十二と、出力の中身を作るブロックの五つ（`toc`、`index`、`bibliography`、`printings`、`separator`）に限った。
ほかのコマンドは、評価、ページ分割、参照、チャネルの仕組みがその意味を前提にするとして、上書きできないものにした。

メンテナーは、2026-11-26 に、次のことを決めた。

- 書き手は、`@note` という名前が書きやすいので、注の仕組みのためでなく、その名前で `.emet` の関数を呼びたい。
  注のチャネルとの関係は考えなくてよい。
- 上書きすると基礎的なことができなくなる命令のほかは、ブロックでもインラインでも上書きできてよい。
  上書きできないのは、`@frame` のように無いと組版そのものができないものと、`@import` のように Golem の仕組みそのものを変えてしまうものである。
- 名前を見て特別に扱っている箇所は、直せるなら直す。
- どの命令を基礎的とするかは、v1.0.0 で用語と基準を決める。
  v1.x か、間に合えば v1.0.0 で、基礎の IR を定め、組み込みの命令のほとんどを Emet に移す予定である。
  `@import` も、driver にそのためのインターフェースがあれば、Emet で実装できる見込みがある（driver にはエフェクトの仕組みがすでにある）。

この ADR は、v1.0.0 の基準を決めるまでの、上書きできないコマンドの一覧を決める。

## 調査した事項

origin/main（[9d18b90](https://github.com/tett23/golem/commit/9d18b9041033d3a7bd35b5a26a6ea46b1926c3b7)）で、次のことを確かめた。

- 上書きできるインラインのコマンドは `OverridableBuiltin` の十二で、上書きできないものは `FixedBuiltin` の十二（`ref-number`、`ref-title`、`ref-page`、`note`、`sidenote`、`endnote`、`index`、`cite`、`aki`、`link`、`lang`、`shy`）である（[Builtin.hs#L36-L68](https://github.com/tett23/golem/blob/9d18b9041033d3a7bd35b5a26a6ea46b1926c3b7/modules/golem-eval/src/Golem/Eval/Builtin.hs#L36-L68)）。
- 上書きできるブロックのコマンドは `OverridableBlock` の五つで、上書きできない名前は `fixedBlockCommands` である（[Builtin.hs#L162-L184](https://github.com/tett23/golem/blob/9d18b9041033d3a7bd35b5a26a6ea46b1926c3b7/modules/golem-eval/src/Golem/Eval/Builtin.hs#L162-L184)、[Builtin.hs#L200-L233](https://github.com/tett23/golem/blob/9d18b9041033d3a7bd35b5a26a6ea46b1926c3b7/modules/golem-eval/src/Golem/Eval/Builtin.hs#L200-L233)）。
  `fixedBlockCommands` は、`import`、`set`、`channel`、改ページの仲間と `blank-line`、`figure`、`table`、`listing`、`style`、`manifest`、`style-def`、属性（`label`、`toc-title`、`number`、`nonumber`、`notoc`、`caption`、`column-widths`）、`lang`、`hyphenation-exceptions`、`note`、`endnote`、`frame` である。
- 評価は、呼ぶ先でなく名前で決める扱いを持つ。
  - まとまりの中で `@note` の外側に置いた属性、`@style`、`@lang` を G02013 にして捨てる（[File.hs#L1367](https://github.com/tett23/golem/blob/9d18b9041033d3a7bd35b5a26a6ea46b1926c3b7/modules/golem-eval/src/Golem/Eval/File.hs#L1367)、[File.hs#L1413](https://github.com/tett23/golem/blob/9d18b9041033d3a7bd35b5a26a6ea46b1926c3b7/modules/golem-eval/src/Golem/Eval/File.hs#L1413)）。
  - `@style` の本体の中の `@style`、`@frame`、`@note`、`@endnote` の結果には、段落スタイルを当てない（[File.hs#L1512](https://github.com/tett23/golem/blob/9d18b9041033d3a7bd35b5a26a6ea46b1926c3b7/modules/golem-eval/src/Golem/Eval/File.hs#L1512)）。
  - 入れ物の本体の中の `@style` を名前で見分ける（[File.hs#L547](https://github.com/tett23/golem/blob/9d18b9041033d3a7bd35b5a26a6ea46b1926c3b7/modules/golem-eval/src/Golem/Eval/File.hs#L547)）。
  ほかに名前で見分ける箇所は、精読を受け持ったエージェントが `git show` と検索で挙げた。
  次スタイルのための `@style` の生成（[File.hs#L367-L376](https://github.com/tett23/golem/blob/9d18b9041033d3a7bd35b5a26a6ea46b1926c3b7/modules/golem-eval/src/Golem/Eval/File.hs#L367-L376)）、改ページの仲間をまとまりから抜く扱い（[File.hs#L1581-L1584](https://github.com/tett23/golem/blob/9d18b9041033d3a7bd35b5a26a6ea46b1926c3b7/modules/golem-eval/src/Golem/Eval/File.hs#L1581-L1584)）、評価の前の正規化（[File.hs#L508-L545](https://github.com/tett23/golem/blob/9d18b9041033d3a7bd35b5a26a6ea46b1926c3b7/modules/golem-eval/src/Golem/Eval/File.hs#L508-L545)）、読むファイルの収集（[Evaluate.hs#L700-L724](https://github.com/tett23/golem/blob/9d18b9041033d3a7bd35b5a26a6ea46b1926c3b7/modules/golem-evaluate/src/Golem/Evaluate.hs#L700-L724)）、言語サーバーのラベルとスタイルの出現の収集と補完（[Features.hs#L143-L198](https://github.com/tett23/golem/blob/9d18b9041033d3a7bd35b5a26a6ea46b1926c3b7/modules/golem-lsp/src/Golem/Lsp/Features.hs#L143-L198)）、golem-lint の行を保つスタイルの判定（[Lint.hs#L79-L83](https://github.com/tett23/golem/blob/9d18b9041033d3a7bd35b5a26a6ea46b1926c3b7/modules/golem-lint/src/Golem/Lint.hs#L79-L83)）である。
  散文スロットの短縮記法と `##N##` は、0453 と 0458 が、上書きした呼び出しにも名前で当てると決めた。
- プラグインの上書きは、ファイルによらず、本のすべてのファイルに当たる（[File.hs#L687](https://github.com/tett23/golem/blob/9d18b9041033d3a7bd35b5a26a6ea46b1926c3b7/modules/golem-eval/src/Golem/Eval/File.hs#L687)）。
- `pub block "note" note :: Blocks -> Blocks` を公開する `.emet` から `{ note }` を並べて取り込み、`@note` と段落を書いた原稿を、71be497 のビルドの `golem check` で組んだ。
  `@import` の行に G02270 が出て、`@note` は組み込みの注として読まれ、G02142 が出た。

## 実装すること

### 上書きできないコマンド

上書きできないコマンドを、次の二つの種類だけにする。

- **Golem の仕組みを決めるもの**：`import`、`set`、`channel`、`manifest`、`style-def`、`hyphenation-exceptions` と、属性（`label`、`toc-title`、`number`、`nonumber`、`notoc`、`caption`、`column-widths`）。
  取り込み、変数、チャネルの宣言、ファイルの設定、スタイルの定義、まとまりの属性は、評価がほかのすべてのコマンドを読む前提である。
- **無いと組版そのものができないもの**：`frame`。
  メンテナーが、この種類の例として挙げた。

この二つのほかの組み込みのコマンドは、ブロックでもインラインでも、名前を並べた取り込みと、プラグインの `overrides` と `block-overrides` で上書きできる。
インラインでは、`FixedBuiltin` の十二もすべて上書きできるようになる。
ブロックでは、改ページの仲間と `blank-line`、`figure`、`table`、`listing`、`style`、`lang`、`note`、`endnote` が、上書きできるようになる。

上書きの決まりは、0453 と [root ADR 0458](0458-rename-listed-imports-with-as.md) のとおりである。

- 名前を並べた `@import` で取り込んだファイルでは、その行より後の呼び出しが、取り込んだ関数を呼ぶ。
  別名がその名前の項目（`{ f as note }`）も同じで、`{ note as n }` は上書きしない。
- プラグインの上書きは本のすべてのファイルに当たる。
- 上書きが重なったときの扱い、名前を探す順、読み込めない `.emet` の扱い（[root ADR 0461](0461-report-the-diagnostics-that-follow-from-another-error.md)）は、0453 と 0461 のとおりである。

上書きできないコマンドの名前を取り込めば、今と同じく G02270 とする。
プラグインが上書きできないコマンドの名前を提供すれば、今と同じく G06007 とする。

### 名前で決まる扱い

評価とツールが、コマンドの名前で特別に扱う箇所は、呼ぶ先が組み込みのコマンドのときだけ当てる。
上書きした名前の呼び出しは、ほかの取り込んだ関数とプラグインのコマンドと同じく、関数の型で扱いが決まる。
評価の前の段（正規化と読むファイルの収集）と、言語サーバーと golem-lint も、この規則を当てる。
そのために、そのファイルの名前を並べた `@import` の行と、本のプラグインの上書きの宣言から、位置ごとに上書きした名前を求める。

箇所ごとの扱いは次のとおりである。

- 評価が次スタイルのために作る `@style` は、名前を引かず、組み込みの `@style` を直に呼ぶ。
  そのため、`style` を上書きしたファイルでも、次スタイルは今と同じく当たる。
- 改ページの仲間、`blank-line`、`separator` をまとまりから先に抜く扱いは、呼ぶ先が組み込みのときだけである。
  上書きした関数は、[root ADR 0459](0459-take-the-next-block-as-the-body-without-indentation.md) のとおり、型で本体を取るかが決まる。
- 評価の前の正規化（`@style` と `@lang` の本体の改行を残す扱い、`@figure` の本体をキャプションとする扱い）は、呼ぶ先が組み込みのときだけである。
- 読むファイルの収集（`figure`、`table`、`listing` の引数）は、呼ぶ先が組み込みのときだけである。
- G02012、G02013、G02114、G02077 などの、名前で決まるまとまりと引数の検査は、呼ぶ先が組み込みのときだけである。
- 散文スロットの短縮記法と `##N##` は、0453 と 0458 のとおり、上書きした呼び出しにも名前で当てる。

- `@note`（と `@endnote`）の外側の属性、`@style`、`@lang` を G02013 にする扱いは、呼ぶ先が組み込みの注のときだけである。
  上書きした `@note` は属性を受け取る。
- `@style` の本体の中で段落スタイルを当てない扱いは、呼ぶ先が組み込みの `@style`、`@frame`、`@note`、`@endnote` のときだけである。
  上書きした名前の結果には、[root ADR 0460](0460-let-style-take-any-blocks-as-its-body.md) のとおり段落スタイルが当たる。
- 改ページの仲間と区切りの検査（[root ADR 0462](0462-breaks-in-command-bodies-and-repeated-commands.md)）は、コマンドの名前でなく、結果の意味論 IR のブロックで決める。
- 言語サーバーの補完、ホバー、定義への移動は、上書きしたファイルでは、取り込んだ関数を示す。
  ラベルとスタイルの出現の収集、スタイルの名前の補完と、golem-lint の判定は、呼ぶ先が組み込みのときだけ当てる。

### 上書きしたファイルの組み込みの仕組み

上書きしたファイルでは、上書きした名前の組み込みのコマンドを使えない。
たとえば、ブロックの `note` を上書きしたファイルでは、ブロックの `@note` で注の本文を定義できないので、名前で引く `[note x]` はいつも G02137 になる。
上書きした名前のほかのコマンドは、今と同じく組み込みのものである。

### 文書

仕様書の「プラグイン」の節の上書きできるコマンドの表と、その後の定義の文、「定義の取り込み」の節の G02270 の説明を、この ADR の二つの種類で書き改める。
`docs/diagnostics.md` の G02270、G06007、G06008 の説明と、`Golem.Eval.Builtin` のコメントを直す。
マニュアルの、上書きできるコマンドの一覧を直す。
ロードマップに、次の二つの項目を足す。

- v1.0.0：「上書きできない基礎的な命令の用語と基準」。この ADR の二つの種類を出発点にする。
- v1.x（間に合えば v1.0.0）：「基礎の IR と、組み込みの命令の Emet への移行」。`@import` を、driver のエフェクトのインターフェースで Emet に実装できるかを調べることを含める。

採択したら、0453 のステータスに次の記録を足す。
どの記録も `"by":["docs/adr/0471-override-built-in-commands-except-mechanisms-and-frames.md"]` を持つ。

- `{"part":"上書きできるコマンド","kind":"replace"}`
- `{"part":"不変条件の I6","kind":"replace"}`
- `{"part":"テスト設計","kind":"supplement"}`
- `{"part":"名前を探す順","kind":"supplement"}`
- `{"part":"トレードオフ","kind":"supplement"}`

## 実装しないこと

上書きしたファイルの、注のチャネル、番号、参照の扱いは変えない。
上書きできない二つの種類のほかに、基礎的な命令の基準を決めることはしない（v1.0.0 で決める）。
組み込みの命令を Emet に移すことはしない。

## 不変条件

- I1: 組み込みのコマンドの名前を取り込まず、プラグインが組み込みのコマンドの名前を上書きしない本は、どの出力も diagnostics も、この ADR の前と同じである。
- I2: 上書きできるコマンドの名前 n（ブロックかインライン）を名前を並べた `@import` で取り込んだファイルの、その行より後の n の呼び出しの出力は、取り込んだ関数の出力に等しく、G02270 も、n の組み込みの扱いの diagnostics も出ない。
- I3: `@import` の行より前の呼び出しと、上書きしないファイルの呼び出しは、組み込みのコマンドである。
- I4: 上書きできない二つの種類の名前を並べた項目ごとに G02270 がちょうど一つ出て、その名前の呼び出しは組み込みのままである。
- I5: プラグインが `overrides` か `block-overrides` で上書きした名前の呼び出しは、本のどのファイルでも、プラグインのコマンドを呼ぶ。
- I6: 上書きした名前の組み込みのコマンドが作る意味論 IR は、上書きした位置より後のそのファイル（プラグインの上書きでは本の全体）に、一つも現れない。たとえば、ブロックの `note` を上書きしたファイルで名前で引く `[note x]` は、どれも G02137 になる。
- I7: 上書きできない名前について、0453 の I7（G06007 と G06008）が成り立つ。
- I8: `style` を上書きしたファイルでも、次スタイルを持つ段落スタイルの次の段落には、組み込みの段落スタイルが当たる。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| 上書きの無い本 | 今と同じ | I1 |
| `pub block "note" note :: Blocks -> Blocks` から `{ note }`、`@note`、段落 | 関数の出力。G02270 と G02142 は出ない | I2 |
| 同じ取り込みと、`@label x`、`@note`、段落 | 関数の出力にラベル。G02013 は出ない | I2 |
| 同じ取り込みと、`@style s` の本体の中の `@note`、段落 | 関数の出力の段落に s が当たる | I2 |
| `pub inline "note"` から `{ note }` と `[note 本文]` | 関数の出力。G02270 は出ない | I2 |
| `{ page-break }`（`Blocks -> Blocks`）と `@page-break`、段落 | 関数の出力。段落が本体になる | I2 |
| `{ figure }` と `@figure a.png`、`a.png` が無い | 関数の出力。ファイルの誤りは出ない | I2 |
| `{ style }` と、`next-style` を持つ段落スタイルの段落、次の段落 | 次の段落に組み込みの段落スタイル | I8 |
| `{ ref-number }` を取り込んだファイルのラベルの改名 | 関数の引数は書き換えない | I2 |
| `{ f as note }` と `@note`、段落 | f の出力 | I2 |
| `{ note as n }` と `@note`、段落 | 組み込みの注。G02142 | I3 |
| `@note`、段落、`@import fn.emet { note }`（`@import` が後） | 組み込みの注。G02142 が出て、G02270 は出ない | I3 |
| `{ import }`、`{ set }`、`{ frame }`、`{ label }` | それぞれ G02270 | I4 |
| `{ note }` を取り込んだファイルの `[note x]` | G02137 | I6 |
| 読み込めない `.emet` から `{ note }` と `@note`、段落 | `@note` は何も出力せず、G02279 が一つ。段落はふつうに組む | I1 |
| `block-overrides = ["note"]` のプラグインと、二つのファイルの `@note` | どちらもプラグインのコマンド | I5 |
| `overrides = ["cite"]` のプラグインと `[cite k]` | プラグインのコマンド | I5 |
| `frame` を提供するプラグイン | G06007 | I7 |
| `block-overrides = ["frame"]` のプラグイン | G06008 | I7 |

## 受けいれ条件

なし。
不変条件のテストで足りるためである。

## テスト設計

root ADR 0471 I1 から I4、I6、I8 を名前の先頭に置いたテストを golem-eval に足す。
I2 と I4 は、組み込みのブロックとインラインのコマンドの名前の一覧のすべてについて、上書きできるかできないかを総当たりで確かめる。
I5 と I7、読むファイルの収集は、golem-evaluate のテストで確かめる。
言語サーバーの補完、ホバー、改名、出現の収集は golem-lsp の、行を保つスタイルの判定は golem-lint のテストで確かめる。
テストは、実装の前に書いて落ちることを確かめる。

## トレードオフ

上書きした名前の組み込みのコマンドは、そのファイルで使えない。
注や参照の仕組みに結び付くコマンドを上書きすると、そのファイルでは、その仕組みを使えない。
書き手は、そのファイルでその仕組みを使わないと決めて上書きするので、この制限は困らない。
仕組みを使いたくなったら、取り込みに別名を付けて、組み込みに戻せる。
プラグインで上書きすると、本のすべてのファイルで使えなくなる。

上書きできないものを二つの種類に限るのは、v1.0.0 の基準を決めるまでのあいだ、書き手の自由を広く取るためである。
基準を決めたら、この一覧を、その基準で決め直す。

## 参考文献

- [root ADR 0453](0453-override-built-in-commands-by-listed-imports-and-plugins.md)
- [root ADR 0458](0458-rename-listed-imports-with-as.md)
- [root ADR 0460](0460-let-style-take-any-blocks-as-its-body.md)
- [root ADR 0461](0461-report-the-diagnostics-that-follow-from-another-error.md)
- [root ADR 0462](0462-breaks-in-command-bodies-and-repeated-commands.md)
- [docs/adr/0263](0263-notes-with-more-than-one-paragraph.md)
