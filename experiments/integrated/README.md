# 複数の提案 ADR を同じ CLI で試す

基準は Golem [ADR 0308](../../docs/adr/0308-tell-a-japanese-book-by-the-primary-subtag-of-its-language.md) の実装を含む `0a8d21a091d830573fb6229111ed744f74162afd` である。
この worktree の `modules/` には、記法と設定の試作と diagnostics の試作の両方を適用した。
適用時の差分を [記法と設定](syntax.patch) と [diagnostics](diagnostics.patch) に保存した。
両方が変更するファイルは `Golem.Eval.File` である。
片方が表のパスの数を調べ、もう片方が表の行ごとのセル数を調べるため、それぞれの変更を残した。
Cabal の通常のビルドでは初回に三つの未使用引数がエラーになったので、この worktree で使わない引数をワイルドカードに変えた。

## 再現

macOS arm64、GHC 9.10.3 の環境で、リポジトリの通常の CLI をビルドする。
登録済みの Cabal ストアと Wasmtime を使い、依存関係のダウンロードは行わなかった。

```sh
cabal build golem-cli:exe:golem --offline -j2
node experiments/integrated/check.mjs "$(cabal list-bin golem-cli:exe:golem)"
```

[試験](check.mjs) は一時ディレクトリに日本語の画面向けプロジェクトを生成する。
`--no-fonts` を選び、リポジトリの小さなフォントをコピーする。
テンプレートの本に `bleed = 0` とフォントにない U+E000 を入れ、同じ本を順に書き換えて preflight と HTML ビルドを試す。
基準版が `new --screen` を拒む場合だけ、従来のテンプレートで後続の検査も続ける。
最後の三件は旧記法と列数の優先順位だけを測るため、`bleed = "0pt"` に戻す。
テストに `unitful` を第 2 引数として渡すと、最初の明示的な塗り足しにも `"0pt"` を使う。

| 組み合わせ | 入力 | 観測する結果 |
| --- | --- | --- |
| Golem [ADR 0319](../../docs/adr/0319-unitless-zero-in-length-fields.md)、[0325](../../docs/adr/0325-preflight-glyph-severity.md)、[0327](../../docs/adr/0327-screen-preflight-and-template.md) | screen の本にゼロの塗り足しと欠字 | glyph-missing の off、warning、error に従い終了コードは 0、0、1 |
| 同上 | 欠字を warning、bleed-size を error とし正の塗り足しを要求 | G09002 と G09010 が同時に出て終了 1 |
| Golem [ADR 0319](../../docs/adr/0319-unitless-zero-in-length-fields.md)、[0327](../../docs/adr/0327-screen-preflight-and-template.md) | 日本式トンボを指定し、塗り足しを 0 から 3mm に変更 | G07002 が出て終了 1、修正後は終了 0 |
| Golem [ADR 0308](../../docs/adr/0308-tell-a-japanese-book-by-the-primary-subtag-of-its-language.md)、0324 | 同じ原稿に発行履歴を入れ、JA-jp、ja_JP、en-US で HTML をビルド | 日本語の発行履歴、G03119、G02076 |
| Golem [ADR 0317](../../docs/adr/0317-retire-table-src.md)、[0328](../../docs/adr/0328-table-file-shape-diagnostics.md) | 列数がそろわない CSV のパスを旧記法、両方、位置引数の順に指定 | 順に G02252、G02130、G02154 を一つずつ |

## 統合で見つけた G07002 の案内

`bleed = 0` をすでに書いた人に、G07002 は「bleed を書いてください」と案内する。
正の塗り足しを明示するよう案内すると、設定の何を直せばよいかが分かる。
[発行箇所](../../modules/golem-driver/src/Golem/Driver.hs) の `cropMarkDiagnostics` は従来と同じ条件で G07002 を出す。
そのメッセージを「style.toml の [page] の bleed に 0 より大きい長さを書いてください」とし、[diagnostics の G07002](../../docs/diagnostics.md#g07002) と CLI の `explain` もそろえる。
[golem-pdf ADR 0004](../../docs/golem-pdf/adr/0004-crop-marks-and-bleed.md) の「診断」は以前の文言を指定している。
[Golem ADR 0332 の草案](../../docs/adr/0332-positive-bleed-in-japanese-crop-mark-message.md) は、同じエラーコードでこの文言だけを変更する。

## 実行結果

| CLI と入力 | 一致した件数 | テストの終了コード |
| --- | ---: | ---: |
| [基準版](base.jsonl) | 0/20 | 1 |
| [diagnostics の試作](red.jsonl) | 6/20 | 1 |
| [同じ試作で塗り足しを単位付きゼロにした対照](unitful-control.jsonl) | 15/20 | 1 |
| [二つの試作をビルドした直後](merged-red.jsonl) | 17/20 | 1 |
| [G07002 の案内を直した CLI](green.jsonl) | 20/20 | 0 |
| [修正後、単位付きゼロの対照](unitful-green.jsonl) | 20/20 | 0 |

統合直後に残った三件は、ゼロを明示した場合、省略した場合、CLI の説明文の三つである。
[統合後のコンパイル](build-merged.log) と [文言の変更後のコンパイル](build-fixed.log) はどちらも成功した。
[発行処理の行](../../modules/golem-driver/src/Golem/Driver.hs) は 1005 行、説明の正本は `docs/diagnostics.md:8978` である。
単位なしゼロを整数として読む処理は `modules/golem-project/src/Golem/Project/Style.hs:1752` にある。
欠字の集計は `modules/golem-driver/src/Golem/Driver.hs:961`、screen の規則は `modules/golem-preflight/src/Golem/Preflight/Rules.hs:175` にある。
言語タグの検査は `modules/golem-project/src/Golem/Project/Manifest.hs:810`、日本語の発行履歴の検査は `modules/golem-eval/src/Golem/Eval/File.hs:1012` にある。
表の旧記法の検査は同ファイルの 1773 行、列数の検査は 2012 行である。

ここで組み合わせた未コミットの原案は、[画面向けの雛形](../../../road-diag/docs/adr/0327-screen-preflight-and-template.md)、[欠字](../../../road-diag/docs/adr/0325-preflight-glyph-severity.md)、[単位なしゼロ](../../../road-syntax/docs/adr/0319-unitless-zero-in-length-fields.md)、[言語タグ](../../../road-diag/docs/adr/0324-manifest-language-form.md)、[表の旧記法](../../../road-syntax/docs/adr/0317-retire-table-src.md)、[表の構造](../../../road-diag/docs/adr/0328-table-file-shape-diagnostics.md) にある。

## 測定範囲

実 CLI の終了コードと JSON の diagnostics、書き出した XHTML の発行履歴、`golem explain G07002` を検査した。
表については、無効な `src=` を書くとセル数を報告せず、位置引数へ移したらセル数の誤りを報告するところまでを検査する。
OS のファイル読み出し回数、ほかのターゲットのバイト列、すべての診断の組み合わせ、LSP と WASM はこの試験の範囲外である。
