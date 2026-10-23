# ADR 0080: リリースの smoke の検査で、ビルドが diagnostics を出さないことも確かめる

ステータス: 採択

## 文脈

[scripts/release/smoke.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/release/smoke.sh) は、配布物を、それを作ったのとは別のランナーと、alpine と debian:stable-slim のコンテナで展開して動かす（[ADR 0004](0004-binary-distribution-and-release.md)）。
2026-10-23 のテストの品質の点検で、smoke.sh の検査が次のとおりであることを確かめた。

- `golem new --no-fonts` は、終了コードだけを見る（[`golem new --no-fonts` の手順](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/release/smoke.sh#L100-L102)）。標準エラー出力は `2>/dev/null` で捨てる。
- sample の fixture のビルドは、終了コードと、出力のディレクトリが空でないことだけを見る（[sample のビルドの手順](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/release/smoke.sh#L103-L109)）。警告と notice の有無は見ない。
- フォントを取る `golem new` と四つのターゲットのビルドも、終了コードと、出力のディレクトリが空でないことだけを見る（[`with_fonts`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/release/smoke.sh#L111-L122)）。
- `.sha256` は、パッケージのときに同じ手順が書いたファイルなので、輸送の途中の破損しか見つけない（[SHA-256 の検査](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/release/smoke.sh#L52-L57)）。

一方で、点検の報告より守られている部分もある。
[release.yml の `determinism` ジョブ](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/.github/workflows/release.yml#L167-L179) は、smoke.sh が `--determinism` で書いた [scripts/determinism.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/determinism.sh) の出力を三つの配布物と CI のビルドの間で比べる。
配布物が組んだ出力のバイト列は、CI で検査した出力と一致することが確かめられている。
欠けているのは、`golem new` の雛形が、配布物の golem で警告なしに組めることの確認である。
雛形を組んで警告が出るなら、利用者が最初に見る出力が警告になる。

コンテナには POSIX の sh、tar、gzip、sha256sum しかない（[smoke.sh の冒頭の注釈](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/release/smoke.sh#L16-L17)）ので、epubcheck や qpdf で出力の妥当性を確かめることはできない。

## 実装すること

- `golem new --no-fonts` の標準エラー出力を捨てずに受け取り、空であることを確かめる。
- フォントを取る `golem new` の雛形のビルド（`with_fonts`）を `--format json` で走らせ、標準エラー出力が diagnostics の空の一覧であることを確かめる。notice も出ないことを求める。雛形が notice を出す設計なら、その notice のコードだけを許す一覧を smoke.sh に書く。
- sample の fixture のビルドは、意図して diagnostics を出す入力ではないことを確かめたうえで、同じく diagnostics がないことを求める。出すなら、今の出力の一覧を smoke.sh に固定する。
- README.md の release の表の `smoke` の行（351 行め）に、雛形のビルドが diagnostics を出さないことを確かめると書く。

## 実装しないこと

- コンテナの中で EPUB と PDF の妥当性を検査すること。道具がない。妥当性は CI の `build` ジョブが検査し、出力のバイト列が同じであることを `determinism` ジョブが確かめる。
- `.sha256` の検査を強めること。輸送の破損を見つけるためのものであり、それで足りる。

## テスト設計

- [ADR 0078](0078-tests-for-release-and-hand-run-scripts.md) で足す smoke.sh のテストに、偽の golem の `build` が標準エラー出力に警告の JSON を一つ書くとき smoke.sh が失敗することを足す。今の smoke.sh は終了コードしか見ないので、このテストは落ちる。
- 偽の golem の `new --no-fonts` が標準エラー出力に一行書くとき失敗することを足す。

## トレードオフ

- 雛形に警告が出る変更（例えば、新しい lint の規則）は、リリースの smoke で初めて止まる。CI の golem-driver のテストに、雛形を組んで diagnostics がないことを確かめるテストがあれば、それより早く止まる。そのテストの有無は実装のときに確かめ、なければ足す。

## 参考文献

- [ADR 0004](0004-binary-distribution-and-release.md)
- [ADR 0078](0078-tests-for-release-and-hand-run-scripts.md)
