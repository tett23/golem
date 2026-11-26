# ADR 0467: @style の名前付き引数で、段落ごとに段落スタイルのキーを上書きする

Status: accepted-pending

## 文脈

[root ADR 0374](0374-paragraph-style-controls.md) は、`@style` の名前付き引数を、明示した段落スタイルと次スタイルの後に最後に重ねると決めた（0374 の 16 行）。
例は `@style body line-height="16pt"` である（0374 の 22 行）。
行送りのキーの名前は、後に [root ADR 0397](0397-paragraph-line-pitch-and-dimensional-spacing.md) が `line-pitch` に改めた。
0374 は、名前付き引数にどのキーを書けるかと、意味論 IR での持ち方を書いていない（ロードマップの「段落ごとの上書きのキー」）。

メンテナーは、2026-11-26 に、0374 の残りを機能ごとの ADR に分けると決めた。
この ADR は、`@style` の名前付き引数を決める。

## 調査した事項

origin/main（[c034510](https://github.com/tett23/golem/commit/c034510e33476f4af68ba22636f5ab6ef8463f0a)）で、次のことを確かめた。
根拠の行は、調べを受け持ったエージェントが `git show` と `git grep` で返したものと、メインが `git show` で読んだものである。

- `@style` は、位置引数の名前を一つだけ受け付け、ほかの引数の形は G02047 `@style には段落スタイルの名前を一つ書きます` にする（[File.hs#L2140-L2144](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-eval/src/Golem/Eval/File.hs#L2140-L2144)）。
  そのため、`@style body line-pitch="16pt"` は、評価で G02047 になる（コードから読んだもので、実行していない）。
- `@style-def` は、段落スタイルのキーを `localStyleDefWithValues` で読み、`style.toml` と同じ `FromValue ParaStyleDef` を使う（[Settings.hs#L304-L306](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-eval/src/Golem/Eval/Settings.hs#L304-L306)、[Style.hs#L4140-L4157](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-project/src/Golem/Project/Style.hs#L4140-L4157)）。
- `@style` の本体の形は、本体のブロックに段落スタイルの名前を渡す（[File.hs#L2151-L2162](https://github.com/tett23/golem/blob/c034510e33476f4af68ba22636f5ab6ef8463f0a/modules/golem-eval/src/Golem/Eval/File.hs#L2151-L2162)）。

## 実装すること

### 書けるキー

`@style` の名前の位置引数の後に、名前付き引数を書けるようにする。
名前付き引数のキーは、`@style-def paragraph` に書ける段落スタイルのキーから、`based-on` を除いたものである。
値の書き方と検査は、`@style-def` に同じ値を書いたときと同じで、誤りのコードも同じである。

`based-on` と、段落スタイルのキーでない名前は、エラーの G02288 `@style の名前付き引数に書けない名前です: <名前>` とする。
`@style-def` の未知のキーは G03006 だが、G03 は `style.toml` と同じ形の定義の誤りのコードであり、原稿のコマンドの引数の誤りは G02 のコードで報告するので、別のコードにする。
同じキーを二度書いた名前付き引数は、今の名前付き引数の重なりと同じく扱う。
名前の無い `@style line-pitch="16pt"` は、今と同じく G02047 である。

### 重ね方

名前付き引数を書いた `@style` の段落は、名前の段落スタイルを `based-on` に持ち、名前付き引数のキーを持つ、名前の無い段落スタイルで組む。
次スタイル（`next-style`）は、名前付き引数より前に決まる。
名前付き引数の `next-style` は、次の段落の段落スタイルを決める。

本体の形の `@style` の名前付き引数は、本体の段落と表のすべてに当たる。
表には、[root ADR 0460](0460-let-style-take-any-blocks-as-its-body.md) が段落スタイルを当てるのと同じく当てる。

名前の無い段落スタイルは、名前と、名前付き引数のキーと値の表が等しければ、同じ段落スタイルとする。
同じ段落スタイルの段落が続くときの空き（`space-between`）は、この同じさで決める。
名前付き引数の無い `@style body` の段落と、`@style body line-pitch="16pt"` の段落は、別の段落スタイルである。

### 意味論 IR

意味論 IR の段落の段落スタイルの参照に、名前付き引数のキーと値の表を持たせる。
キーの無い参照は、今の参照と同じ形で表す。
プラグインと Emet のフィルタは、この表を読める。
意味論 IR の型が変わるので、プラグインの ABI の IR のスキーマの版を上げる。

### 出力

PDF は、名前の無い段落スタイルのキーで段落を組む。
HTML と EPUB は、名前の無い段落スタイルごとに、文書の中で最初に出た順に 1 から番号を振り、段落に class `ps-<名前>` と `pso-<番号>` を付ける。
CSS には、`p.ps-<名前>.pso-<番号>` の規則として、名前付き引数のキーの CSS を書く。
番号は文書の順だけで決まるので、同じ入力からは同じ出力になる。
プレーンテキストの出力は変えない。

### 文書

仕様書の `@style` の節と、意味論 IR の段落の節に、名前付き引数を書く。
`docs/diagnostics.md` に G02288 を足し、G02047 の説明を直す。
ロードマップの「段落ごとの上書きのキー」を消す。
採択したら、0374 のステータスに `{"part":"段落ごとの上書き","by":["docs/adr/0467-override-paragraph-style-keys-with-style-arguments.md"],"kind":"replace"}` を足す。

## 実装しないこと

見出しとリストへの上書きは、[root ADR 0468](0468-paragraph-styles-for-headings-and-lists.md) で決める。
文字スタイルの上書きは扱わない。

## 不変条件

- I1: 名前付き引数の無い `@style` の段落は、この ADR の前と同じに組む。
- I2: `@style s k=v` の段落の出力は、`@style-def paragraph t based-on=s k=v` を定義して `@style t` と書いた段落の出力と等しい。
- I3: 名前付き引数の誤りのある `@style` の段落は、誤りの無いキーだけを上書きして組む。
- I4: `based-on` か段落スタイルのキーでない名前の名前付き引数の数を k とすると、G02288 はちょうど k 個出る。
- I5: 名前と名前付き引数の表が等しい二つの段落は、同じ段落スタイルとして空きと HTML の class が決まり、等しくない二つは別の段落スタイルとして決まる。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| `@style body` | 今と同じ | I1 |
| `@style body line-pitch="16pt"` | 行送り 16pt の body | I2 |
| 本体の形の `@style body space-before="1lh"` と段落二つ | 二つとも上書き | I2 |
| `@style body based-on=caption` | G02288 | I4 |
| `@style body colour="red"` と `line-pitch="16pt"` | G02288 が一つ。行送りは 16pt | I3, I4 |
| `@style body line-pitch="-1pt"` | `@style-def` と同じ誤り | I3 |
| `@style line-pitch="16pt"` | G02047（今と同じ） | I1 |
| `@style body line-pitch="16pt"` の段落が二つ続く | あいだは `space-between` | I5 |
| `@style body` と `@style body line-pitch="16pt"` の段落が続く | あいだは別のスタイルの空き | I5 |
| 表を本体に持つ `@style s line-pitch="16pt"` | 表のセルの段落も 16pt | I2 |

## 受けいれ条件

なし。
不変条件のテストで足りるためである。

## テスト設計

root ADR 0467 I1 から I5 を名前の先頭に置いたテストを、golem-eval（引数の読み込みと診断）、golem-typeset（組んだ段落）、golem-html（class と CSS）に足す。
I2 は、キーと値の組を並べて、二つの原稿の出力を比べる。
テストは、実装の前に書いて落ちることを確かめる。

## トレードオフ

`@style-def` と同じキーを受け付けるので、書き手は一つのキーの一覧を覚えれば足りる。
0374 が挙げた六つのキーに限ると、ほかのキーを段落ごとに変えたいときに `@style-def` を書く手間が残る。

## 参考文献

- [root ADR 0374](0374-paragraph-style-controls.md)
- [root ADR 0397](0397-paragraph-line-pitch-and-dimensional-spacing.md)
- [root ADR 0460](0460-let-style-take-any-blocks-as-its-body.md)
