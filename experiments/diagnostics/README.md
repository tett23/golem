# diagnostics とビルドの結果の試作

基準は Golem [ADR 0308](../../docs/adr/0308-tell-a-japanese-book-by-the-primary-subtag-of-its-language.md) の実装を含む `0a8d21a091d830573fb6229111ed744f74162afd`。
この記録は最初の試作の結果である。
Golem [ADR 0321](../../docs/adr/0321-preflight-rule-error-causes.md)、[0324](../../docs/adr/0324-manifest-language-form.md)、[0325](../../docs/adr/0325-preflight-glyph-severity.md)、[0326](../../docs/adr/0326-discard-stale-pdf-after-build-errors.md)、[0329](../../docs/adr/0329-output-path-file-diagnostic.md) の再検証は [レビュー後の実験](../diagnostics-review/README.md) にある。
とくに Golem [ADR 0326](../../docs/adr/0326-discard-stale-pdf-after-build-errors.md) の最新の方針は dev で前回出力を保持し、prod で削除する。
通常の CLI をコンパイルして、同一スクリプトで基準版と試作版に一時プロジェクトを渡した。
入力を作るスクリプト、CLI の実出力、期待値の比較を別のファイルに置いた。

| ロードマップの項目 | 提案 | 確かめたこと |
| --- | --- | --- |
| 一つのコードに一つの原因 | [Golem ADR 0321](../../docs/adr/0321-preflight-rule-error-causes.md) | G09001 の六原因と複合入力での位置を検査した。 |
| 同上、CSV と TSV | [Golem ADR 0328](../../docs/adr/0328-table-file-shape-diagnostics.md) | 空、列数不一致、同じ列数の二行を両形式で試した。 |
| 同上、出力先 | [Golem ADR 0329](../../docs/adr/0329-output-path-file-diagnostic.md) | リンクと通常ファイルを実際の出力先に置き、別コードと内容の保存を確かめた。 |
| 同上、プラグイン | [Golem ADR 0330](../../docs/adr/0330-undeclared-plugin-and-missing-filter.md) | 同梱 wasm をロックし、未宣言のプラグインと存在しないフィルタを比較した。 |
| 同上、PDF の図版 | [Golem ADR 0331](../../docs/adr/0331-encrypted-figure-and-missing-page.md) | 暗号化辞書への参照と範囲外のページを試し、原稿の三行目に別コードが出た。 |
| 数に関する判定 | [Golem ADR 0322](../../docs/adr/0322-check-numeric-diagnostic-boundaries.md) | 実際に配置した JPEG の 1 ppi を境に、三つのしきい値で各三回実行した。ライブラリの A2 は native で一件成功。 |
| G01012 の重複 | [Golem ADR 0323](../../docs/adr/0323-heading-level-diagnostic-occurrences.md) | 章六構成の check と HTML ビルドで一致。歴史的な重複の条件は未再現。 |
| manifest の language | [Golem ADR 0324](../../docs/adr/0324-manifest-language-form.md) | HTML でも不正な形を拒否した。他のスキーマエラーがある場合を含む。 |
| glyph-missing の終了値 | [Golem ADR 0325](../../docs/adr/0325-preflight-glyph-severity.md) | 欠けた字だけの場合に off、warning、error が順に終了 0、0、1。別のエラーも報告された。 |
| 古い PDF の片付け | [Golem ADR 0326](../../docs/adr/0326-discard-stale-pdf-after-build-errors.md) | G08010、マニフェストエラー、check、HTML の明示指定、親の下のリンクを比較した。 |
| 入稿しない原稿 | [Golem ADR 0327](../../docs/adr/0327-screen-preflight-and-template.md) | screen の検査、明示的な上書きとトンボ、日英の new --screen を試した。 |

## 再現

次のコマンドはこの worktree のルートで実行する。
`GOLEM_BIN` にはビルドした実行ファイルの絶対パスを渡す。
各実行は一時フォルダーを作り、プラグインのキャッシュもその中だけに置く。
`expected.mjs` は一つでも期待値に合わなければ終了コード 1 を返す。

```sh
node experiments/diagnostics/survey.mjs
cabal build golem-cli:exe:golem --offline -j2
GOLEM_BIN="$(cabal list-bin golem-cli:exe:golem)" node experiments/diagnostics/baseline.mjs > /tmp/golem-diagnostic-prototype.json
node experiments/diagnostics/expected.mjs /tmp/golem-diagnostic-prototype.json
cabal test golem-preflight:test:golem-preflight-test --offline -j2 --test-options='-p A2' --test-show-details=direct
```

[基準版の結果](baseline.json) を [期待値](expected.mjs) と照合すると 26 件中 20 件が不一致で終了 1。
[試作版の結果](prototype.json) は同じ 26 件すべてが一致して終了 0。
[基準版の照合記録](red.log)、[試作版の照合記録](green.log)、[A2 の native での結果](native-a2.log) を保存した。
A2 の wasm32 での実行は未確認である。
公開 WASM のコマンドに preflight はないため、受け入れには [共通テストのジョブ](../../.github/workflows/wasm-tests.yml) で golem-preflight-test を実行する。

## 調査の範囲

[全コードの台帳](catalog.tsv) は文書の 409 節すべてを収録した。
[調査スクリプト](survey.mjs) は Haskell の src、src-plugins、src-no-plugins の 195 ファイルを調べ、生成済みの説明文を除いた。
文書の語の組み合わせで候補となった 47 件には、入力元が複数でも原因が変わらないコードを含む。
候補に入らなかった G02085 や G06010 も、タイトルや原因の説明を読んで試作に加えた。
全コードについて一つの原因しかないことを検証したものではない。

ほかにコードを見直す候補として、G03001 と G03006 は TOML とスキーマ、G03013 はスタイルの参照先と循環、G03026 は参考文献ファイルの不在と JSON の誤り、G06005 は wasm の読み込みと ABI、G06009 は実行の上限と出力、G06012 はチャネル名の重複と予約語、G09014 は PDF/X の個別の要件を一つにまとめている。
前後の仕様と発行箇所は台帳の該当行を参照する。
これらの発行条件をすべて CLI の最小入力にしたわけではなく、採番していない。

[浮動小数点の候補](floating.tsv) は 7 行、[丸めと平方根などの候補](rounding.tsv) は 144 行である。
型の名前の検索は、型推論や FFI、同梱のネイティブライブラリまでの全経路を保証しない。
試作は仕様書、既存の説明のカタログ、既存のテストの期待値を採択後のものに一括で書き換えていない。
決定と実装 PR で更新する範囲は各 ADR に記した。
