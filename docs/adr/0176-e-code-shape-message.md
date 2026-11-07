# ADR 0176: コードの形の誤りのメッセージに、Emet の `E` のコードを含める

ステータス: 採択（未実装）

## 文脈

v0.1.0-rc4 のロードマップは、「`E` のコードの形の誤りのメッセージ」の項目を持つ（[docs/roadmap.md](../roadmap.md)）。
`golem explain` と `silence-notices` は Emet の `E` のコードを受け付けるが、コードの形の誤りのメッセージは「G と 5 桁の数字」のままである。

### コードの形の判定

コードの形は、golem-syntax の `isCodeShape` の一か所で判定する（[`Diagnostic.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-syntax/src/Golem/Syntax/Diagnostic.hs#L85-L89)）。
[ADR 0160](0160-emet-function-language-core.md) の実装は、この判定に `E` を足した。
六文字で、先頭が大文字の `G` か `E`、残りの五文字が数字のものを、コードの形とする。

この判定を使う誤りのメッセージは二つある。

| 使う所 | メッセージ | diagnostic のコード |
| --- | --- | --- |
| `golem explain` の引数（[`Main.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-cli/app/Main.hs#L149-L156)） | `診断のコードは G と 5 桁の数字です: <値>` | なし（使い方の誤り、終了コード 2） |
| `manifest.toml` の `silence-notices` と `silence-info` の要素（[`Manifest.hs`](https://github.com/tett23/golem/blob/50b9fca8a0744f6f9d92808db231e6c04ac35d2c/modules/golem-project/src/Golem/Project/Manifest.hs#L307-L313)） | `診断のコードは G と 5 桁の数字で書きます: <文字列>` | G03024 |

`golem explain` は、引数を大文字に直してから形を調べる。
`silence-notices` と `silence-info` は、大文字に直さずに調べる。

### 再現

`~/.local/bin/golem`（`golem 0.1.0-rc3` と名乗るが、`E` のコードを受け付けるので、rc3 より後の main から作ったもの）で確かめた（2026-11-06）。

`golem explain` に `E0101`（`E` と 4 桁の数字）を渡すと、`診断のコードは G と 5 桁の数字です: E0101` が出る。
`E01100` と `e01100` を渡すと、どちらも E01100 の節を表示する。

`sample` の fixture を写し、`manifest.toml` に `silence-notices = ["E0210", "E02109", "nope", "e02109", 3]` を足して `golem check` を実行すると、次の四つの G03024 が出た。
`E02109` は notice のコードなので、誤りにならない。

```text
manifest.toml:21:20: error[G03024]: 診断のコードは G と 5 桁の数字で書きます: E0210 (diagnostics.silence-notices[0])
manifest.toml:21:39: error[G03024]: 診断のコードは G と 5 桁の数字で書きます: nope (diagnostics.silence-notices[2])
manifest.toml:21:47: error[G03024]: 診断のコードは G と 5 桁の数字で書きます: e02109 (diagnostics.silence-notices[3])
manifest.toml:21:57: error[G03024]: 診断のコードは文字列で書きます (diagnostics.silence-notices[4])
```

`E0210` の書き手は Emet のコードを書くつもりだったのに、メッセージは `G` のコードしか示さない。
`e02109` は小文字だけが誤りだが、メッセージは大文字で書くことを示さない。
`silence-info` も同じメッセージを出す（`E05108` は info のコードで、`silence-info` に書ける）。

### 文書に残る「G と 5 桁の数字」

`rg` で探した（main の `50b9fca8`）。

| 文書 | 場所 | 中身 |
| --- | --- | --- |
| [docs/diagnostics.md](../diagnostics.md) | G03024 の「意味」のメッセージと「直し方」 | `診断のコードは G と 5 桁の数字で書きます: <文字列>`、「コードは大文字の `G` と 5 桁の数字で書く」 |
| [docs/specifications.md](../specifications.md) | 「構文木と diagnostics」の節 | 「コードは `G`、diagnostic を出す段階の 2 桁、番号の 3 桁からなる 5 桁である」 |
| README.md | diagnostics の段落 | 「コードは `G` と、段階の 2 桁と番号の 3 桁からなる 5 桁の数字である」 |
| 使い手のマニュアル | 付録 E の冒頭（`manual/appendices/e-errors.gm` の 10 行め） | 「コードは G と 5 桁の数字です」 |
| 使い手のマニュアル | 付録 E の G03024（同 517 行め） | 「コードは大文字の G と 5 桁の数字で書きます」 |
| 開発者のマニュアル | 「diagnostic のコード」の節（`manual-dev/part1/02-diagnostics.gm` の 116 行め） | 「diagnostic のコードは、G と 5 桁の数字である」 |
| 開発者のマニュアル | 「diagnostic のコードの説明」の節（同 169 行めと 177 行め） | 形の誤りの説明と、`golem explain` の出力の例 |

[docs/diagnostics.md](../diagnostics.md) の「番号の区分」の節は、`E` のコードと段階の表をすでに持つ。
仕様書の Emet の節も、「誤りのコードは `E` と 5 桁の数字である」と書く。
使い手のマニュアルの付録 E は、E02109 の項目を持つのに、冒頭では、コードを G と 5 桁の数字だとしている。

[golem-cli ADR 0009](../golem-cli/adr/0009-explain-several-codes.md) は、`golem explain` の形の誤りのメッセージを `診断のコードは G と 5 桁の数字です: <値>` と定めた。
コミットした ADR は変えられないので、この ADR で改める。

## 実装すること

### メッセージ

二つのメッセージを次のように変える（「メンテナーが決めること」の 1 と 2）。

| 使う所 | 今 | 新しいメッセージ |
| --- | --- | --- |
| `golem explain` | `診断のコードは G と 5 桁の数字です: <値>` | `診断のコードは G か E の後に 5 桁の数字を続けたものです: <値>` |
| `silence-notices` と `silence-info` | `診断のコードは G と 5 桁の数字で書きます: <文字列>` | `診断のコードは大文字の G か E の後に 5 桁の数字を続けて書きます: <文字列>` |

`golem explain` は大文字と小文字を区別しないので、「大文字の」を付けない。
`silence-notices` と `silence-info` は区別するので、「大文字の」を付け、小文字で書いた誤りを直せるようにする。

終了コード、diagnostic のコード（G03024）、位置、メッセージの後ろの経路（`(diagnostics.silence-notices[0])`）は変えない。
形の判定（`isCodeShape`）も変えない。

### 形の言い方を一か所に置く

形の言い方「G か E の後に 5 桁の数字」は、golem-syntax の `isCodeShape` の隣に一つの値として置き、二つのメッセージはそこから作る（「メンテナーが決めること」の 3）。
コードの接頭辞を足したときに、判定と言い方の片方だけが変わることを防ぐためである。
golem-cli と golem-project は、すでに golem-syntax から `isCodeShape` を取り込んでいるので、パッケージの依存は変わらない。

### 文書

- [docs/diagnostics.md](../diagnostics.md) の G03024 の「意味」のメッセージを新しい文言にし、「直し方」を「コードは大文字の `G` か `E` の後に 5 桁の数字を続けて書く」にする。
- [docs/specifications.md](../specifications.md) の「構文木と diagnostics」の節に、Emet のコードは `E` で始まることと、`golem explain`、`silence-notices`、`silence-info` が `E` のコードも受け付けることを書く。
- README.md の diagnostics の段落に、Emet のコードは `E` で始まることを書く。
- 使い手のマニュアルの付録 E の冒頭と G03024 の項目を、新しい形の言い方に直す。冒頭には、`E` で始まるコードが関数を書くファイル（`.emet`）の誤りであることを一文で足す。
- 開発者のマニュアルの「diagnostic のコード」の節に、`E` のコードが Emet のものであり、段階の表は docs/diagnostics.md にあることを一文で足す（「メンテナーが決めること」の 4）。「diagnostic のコードの説明」の節の形の誤りの説明と、`golem explain` の出力の例を、新しい文言に直す。
- [golem-cli ADR 0009](../golem-cli/adr/0009-explain-several-codes.md) のステータスの行に、形の誤りの文はこの ADR で改めたことを書く。

二つのマニュアルの文章が変わるので、直した位置より後ろのページの見た目が変わりうる。
同じプルリクエストで `scripts/visual/run.sh --accept` を実行し、`scripts/visual/pages/manual.txt` と `manual-dev.txt` を書き直す（[ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md)）。

## 実装しないこと

- コードの形の判定を変えること（小文字を `silence-notices` で受け付けるなど）。
- `golem explain` のほかのメッセージ（`未知の診断のコードです: <値>。…`、プラグインのコードの形の誤りの文）。
- G03024 を原因ごとのコードに分けること。G03024 は、形の誤り、notice でないコード、もう一方の一覧のコードをまとめて持つが、この ADR はメッセージの文言だけを扱う。
- メッセージの「診断」を diagnostic に変えること。メッセージは使い手が読むもので、使い手のマニュアルは「診断」のまま書く（[docs/manual-policy.md](../manual-policy.md)）。
- 開発者のマニュアルに `E` のコードの段階の表を写すこと。
- コミットした ADR（[golem-cli ADR 0005](../golem-cli/adr/0005-explain-diagnostic-codes.md)、[golem-cli ADR 0009](../golem-cli/adr/0009-explain-several-codes.md)）と監査の記録の本文を直すこと。

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから、実装を変える。

golem-cli のテストでは、次のことを確かめる。

- `golem explain E0101` が終了コード 2 で終わり、標準出力が空で、標準エラー出力が `診断のコードは G か E の後に 5 桁の数字を続けたものです: E0101` の一行であること。
- `golem explain G0258`、`nope`、`G01017 G0101 nope G0101` の既存のテストの期待値を、新しい文言に変えること。ゴールデンの `explain-bad-code.stderr.txt` も書き直す。
- `golem explain e01100` が、今のとおり E01100 の節を表示すること。

golem-project のテストでは、次のことを確かめる。

- `silence-notices = ["E0210"]` が G03024 で、メッセージが `診断のコードは大文字の G か E の後に 5 桁の数字を続けて書きます: E0210` を含むこと。
- `silence-notices = ["e02109"]` と `silence-info = ["e05108"]` が、同じ形のメッセージの G03024 になること。
- 既存の `G0262` のテストの期待値を、新しい文言に変えること。
- `silence-notices = ["E02109"]` と `silence-info = ["E05108"]` が、今のとおり誤りにならないこと。

golem-syntax のテストで、形の言い方の値が `G` と `E` の両方を含むことを確かめる。
`isCodeShape` が受け付ける接頭辞を足したときに、このテストを直す必要が生じ、言い方の直し忘れに気付けるようにするためである。

マニュアルの変更は、`scripts/manual/build.sh` で二つのマニュアルが diagnostic なしで組めることと、見た目の回帰テストの参照を書き直した後に `scripts/visual/check.sh` が通ることで確かめる。

## トレードオフ

メッセージが長くなる。
`golem explain` の新しいメッセージは、今より 12 字長い（空白を含めて数えた）。
形の誤りは一度に数個しか出ないので、端末の幅を超えることは少ないと見込む。

`silence-notices` と `silence-info` のメッセージに「大文字の」を足すので、ロードマップの項目（`E` を足すこと）より範囲が広がる。
同じ文言を変えるので、二度に分けて直すと、テストとマニュアルの書き直しが二度になる。

二つのマニュアルを直すので、見た目の回帰テストの参照が変わり、レビューでは変わったページの前後の画像（[ADR 0096](0096-before-and-after-images-of-changed-pages.md)）を見ることになる。
文言だけの変更でも、付録 E と開発者のマニュアルの前半より後ろのページが組み直されうる。

## 決めたことの記録

- **メッセージを直すこと**（ロードマップ、v0.1.0-rc4）：`golem explain` と `silence-notices` は `E` のコードを受け付けるのに、形の誤りのメッセージが「G と 5 桁の数字」のままなので直す。
- **すべての項目**（2026-11-07、メンテナー）：「問題なし」。「メンテナーが決めること」の 1 から 4 を、すべて推奨のとおりとした。

## メンテナーが決めること

すべて決めた（「決めたことの記録」）。

1. **形の言い方**：決めた。推奨のとおり「G か E の後に 5 桁の数字を続けたもの」とし、`silence-notices` と `silence-info` では「続けて書く」の形にする（「決めたことの記録」）。
   - 退けた案（「G か E と 5 桁の数字」）：今の文言に「か E」を足すだけで済むが、「G か、E と 5 桁の数字」とも読める。
   - 退けた案（「Golem のコードは G、Emet のコードは E と 5 桁の数字」）：コードの出どころまで示せるが、形を直すのに出どころは要らず、メッセージが倍ほどに長くなる。
   - 退けた案（「診断のコードの形ではありません」）：接頭辞を足しても文言を変えずに済むが、どう直せばよいかを示さない。
2. **`silence-notices` と `silence-info` に「大文字の」を付けるか**：決めた。推奨のとおり付ける（「決めたことの記録」）。`e02109` の誤りを、メッセージだけで直せるようにする。docs/diagnostics.md の G03024 の「主な原因」は、小文字で書くことを挙げている。
   - 退けた案（付けない）：ロードマップの範囲に収まるが、小文字の誤りの書き手は、docs/diagnostics.md の「直し方」まで読まないと原因が分からない。
3. **形の言い方をどこに置くか**：決めた。推奨のとおり golem-syntax の `isCodeShape` の隣に一つの値として置く（「決めたことの記録」）。
   - 退けた案（二つのメッセージにそれぞれ書く、今の形）：変更は小さいが、今回の不整合（判定に `E` を足し、メッセージを直し忘れた）がまた起きうる。
4. **開発者のマニュアルにどこまで書くか**：決めた。推奨のとおり「diagnostic のコード」の節に、`E` が Emet のコードであることと、段階の表の場所を一文で書く（「決めたことの記録」）。
   - 退けた案（`E` の段階の表も写す）：開発者のマニュアルだけで完結するが、docs/diagnostics.md と同じ表を二か所で保つことになる。
   - 退けた案（形の誤りの例だけを直す）：「diagnostic のコードは、G と 5 桁の数字である」という誤った記述が残る。

## 参考文献

- [docs/roadmap.md](../roadmap.md) の v0.1.0-rc4 の「`E` のコードの形の誤りのメッセージ」
- [ADR 0160](0160-emet-function-language-core.md)、[docs/adr/0061](0061-five-digit-diagnostic-codes.md)、[docs/adr/0104](0104-info-severity.md)、[ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md)、[ADR 0096](0096-before-and-after-images-of-changed-pages.md)
- [golem-cli ADR 0005](../golem-cli/adr/0005-explain-diagnostic-codes.md)、[golem-cli ADR 0009](../golem-cli/adr/0009-explain-several-codes.md)、[golem-syntax ADR 0002](../golem-syntax/adr/0002-notice-severity.md)
- [docs/diagnostics.md](../diagnostics.md) の G03024
- [docs/manual-policy.md](../manual-policy.md)
