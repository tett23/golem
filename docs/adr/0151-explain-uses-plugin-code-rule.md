# ADR 0151: `golem explain` が受けるプラグインのコードの形を、golem-plugin の規則で判定する

ステータス: 採択、重複の除き方と形の誤りの文は [ADR 0164](0164-explain-dedup-and-plugin-code-messages.md)

## 文脈

[ADR 0139](0139-plugin-diagnostic-code-starts-with-letter.md) は、プラグインの diagnostic のコードを、英小文字で始まり、英小文字、数字、`-` だけからなる列に限った。
判定は golem-plugin の `pluginCode` の一か所で行い、その中で `dataName` を使う（[Plugin.hs#L204-L207](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-plugin/src/Golem/Plugin.hs#L204-L207)、[同#L821-L824](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-plugin/src/Golem/Plugin.hs#L821-L824)）。
0139 は、その理由を「名前の形の規則を一つにし、二つの関数が食い違わないようにする」と書いた。

ところが、同じ形の規則の写しが、golem-cli にもう一つある。
`golem explain` は、`<名前>/<コード>` の形の引数をプラグインのコードとして受け、説明が golem にないことを一行で標準出力に書いて終了コード 0 で終わる（[docs/adr/0108](0108-plugin-diagnostic-codes-and-spans.md)）。
その判定は golem-cli の `pluginCode` が自前で行い、`/` の後を「英小文字、数字、`-` の列」とだけ見て、先頭の文字を見ない（[cli/Main.hs#L156-L166](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-cli/app/Main.hs#L156-L166)）。
0139 はこの写しを直さなかった。
2026-11-04 の二度めの監査（[PR #525](https://github.com/tett23/golem/pull/525) の docs/audits/2026-11-04-rc4-followup-conformance.md の F-12）は、`golem explain x/404`、`x/-`、`x/0` が「プラグインの診断のコードです」を書いて終了コード 0 になることを実機で確かめた。
0139 の後は、どのプラグインもこれらのコードを出せない。
CLI は、存在しえないコードをプラグインのコードとして説明している。

同じ規則の写しが二つあったことが、この食い違いの原因である。
直し方は、規則をどこに一つだけ置くかで決まる。

### 依存の向き

golem-cli の実行ファイル `golem` は、golem-plugin をすでに build-depends に持つ（[golem-cli.cabal#L18-L35](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-cli/golem-cli.cabal#L18-L35)）。
`Golem.Plugin.Lock` を import している。
golem-cli のテストのスイートは golem-plugin に依存しないが、`golem` の実行ファイルを起動して試すので、依存を足す必要はない。
golem-plugin が規則を公開し、golem-cli がそれを使うなら、golem-\* のあいだの build-depends は変わらない。

### 誤った形の扱い

今の `golem explain` は、プラグインのコードの形に合わない引数を、Golem のコードとして `checkCode` に回す（[cli/Main.hs#L147-L153](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-cli/app/Main.hs#L147-L153)）。
そのため、`golem explain lookup/No-key` は `診断のコードは G と 5 桁の数字です: lookup/No-key` を標準エラー出力に書き、終了コード 2 で終わる。
終了コードは [golem-cli ADR 0009](../golem-cli/adr/0009-explain-several-codes.md) のとおりだが、文はプラグインのコードを書こうとした利用者に合わない。
`x/404` を同じ経路に回すと、同じ合わない文が出る。

## 実装すること

### 規則を置く場所

- golem-plugin の `Golem.Plugin` に、プラグインのコードの後ろの部分の形を判定する関数を公開する。

  ```haskell
  -- | 英小文字で始まり、英小文字、数字、- だけからなる（docs/adr/0139）
  pluginCodeForm :: Text -> Bool
  pluginCodeForm = dataName
  ```

- golem-plugin の中の `pluginCode` は `pluginCodeForm` で判定する。振る舞いは変わらない。
- golem-cli の `pluginCode` は、`/` の後の判定を `pluginCodeForm` に置き換え、自前の文字の判定を消す。`/` の前の判定（空でなく、空白を含まない）は今のまま残す。
- golem-\* のあいだの build-depends は変えない。

`dataName` そのものを公開せず、別の名前で公開するのは、呼び手から見た意味（プラグインのコードの形）を名前に出すためである。
データの名前とコードの形が将来分かれても、golem-cli の呼び手は変えずに済む。

### 誤った形のコードの扱い

`golem explain` の引数を、次の順に分ける。

1. `/` をちょうど一つ含み、`/` の前が空でなく空白を含まず、`/` の後が `pluginCodeForm` を満たすもの。今と同じく、プラグインのコードとして一行を標準出力に書く。
2. `/` を含み、1 に当たらないもの。プラグインのコードの形の誤りとして、次の一行を標準エラー出力に書く。

   ```
   プラグインの診断のコードの形が不正です: <引数>。/ の後は英小文字で始まり、英小文字、数字、- だけからなります
   ```

3. `/` を含まないもの。今と同じく `checkCode` で Golem のコードとして判定する。

2 に当たる引数は、[golem-cli ADR 0009](../golem-cli/adr/0009-explain-several-codes.md) の誤ったコードと同じに扱う。
正しいコードの節を書いた後に標準エラー出力に書き、使い方の表示は書かず、終了コードを 2 とする。
大文字に直して同じになる引数を一度だけ扱う今の重複の除き方も変えない。

`lookup/No-key` の文は、`診断のコードは G と 5 桁の数字です` から、2 の文に変わる。
終了コードは 2 のままである。

### 文書

- docs/specifications.md の「プラグイン」の節の `golem explain` の項（今の 3195 行め）に、`/` の後が 0139 の形でない引数は 2 の文を標準エラー出力に書き、使い方の誤り（終了コード 2）とすることを足す。CLI の表の `golem explain [CODE...]` の行の「形の誤り」に、プラグインのコードの形の誤りを含めることを書く。
- 開発者のマニュアルの CLI の章（`manual-dev/part1/01-cli.gm`）の、`golem explain` が 2 で終わる場合の箇条（今の 133 行め）に、プラグインのコードの形の誤りを足す。
- [docs/adr/0139](0139-plugin-diagnostic-code-starts-with-letter.md) のステータスの行に、「`golem explain` の判定は [ADR 0151](0151-explain-uses-plugin-code-rule.md)」を足す。
- [golem-cli ADR 0009](../golem-cli/adr/0009-explain-several-codes.md) のステータスの行に、「プラグインのコードの形の誤りの文は [docs/adr/0151](../../adr/0151-explain-uses-plugin-code-rule.md)」を足す。

## 実装しないこと

- `/` の前の部分（プラグインの宣言の名前）の形を検査すること（2026-11-04 の一度めの監査の F-10）。マニフェストの宣言の名前に形の規則がないので、[ADR 0139](0139-plugin-diagnostic-code-starts-with-letter.md) と同じく扱わない。`golem explain G01017/x` は今と同じく終了コード 0 になる。
- `golem explain` が、プロジェクトの `manifest.toml` を読み、宣言されたプラグインの名前かを確かめること。`golem explain` はプロジェクトの外でも動くコマンドである。
- 規則を golem-syntax や golem-driver に移すこと。規則はプラグインの ABI のもので、golem-plugin が持つ。
- golem-cli のテストのスイートに golem-plugin を足し、関数を直に試すこと。実行ファイルを起動するテストで足りる。

## テスト設計

先に次のテストを golem-cli の `explainTests`（`modules/golem-cli/test/Main.hs`）に書き、今の main で失敗することを確かめてから実装する。

- `golem explain x/404`、`x/-`、`x/0`、`x/2x`、`x/-a` のそれぞれが、終了コード 2 で終わり、標準出力が空で、標準エラー出力が 2 の文の一行だけであること。今の main では、どれも終了コード 0 で失敗する。
- `golem explain lookup/No-key` の標準エラー出力が、2 の文の一行だけであること。今の main では `診断のコードは G と 5 桁の数字です` の文なので失敗する。今の `exitsWith (ExitFailure 2) ["explain", "lookup/No-key"]` はこのテストに置き換える。
- `golem explain x/404 G01017` が終了コード 2 で終わり、標準出力が `golem explain G01017` の標準出力と等しく、標準エラー出力が 2 の文の一行だけであること。今の main では終了コード 0 で失敗する。

次のテストは今も通るが、変えずに通り続けることを確かめる。

- `golem explain x/a`、`x/a-`、`x/no-key-2` が、今と同じ一行を標準出力に書いて終了コード 0 で終わること（`x/a` と `x/a-` と `x/no-key-2` を新たに足し、`lookup/no-key` と `lk/x` の今のテストは変えない）。
- `golem explain nope` と `G99999` の文と終了コードが変わらないこと（golden の `explain-bad-code` と `explain-unknown-code`）。
- golem-plugin の `ResponseSpec` と `CheckDataSpec` が変えずに通ること。

## トレードオフ

- golem-cli の `Main.hs` が `Golem.Plugin` を import する。golem-cli はすでに golem-plugin に依存しているので、ビルドの依存は増えないが、`Golem.Plugin` の公開する名前が一つ増える。
- 新しい依存より小さな複製を選ぶ方針（二度めの監査の F-17 が挙げた、golem-eval の `notInCaption` と golem-plugin の `blockKind` など）とは逆の選び方である。この方針は、依存の向きのために共有できない場合のものである。ここでは依存がすでにあり、複製が食い違いを実際に生んだので、共有を選ぶ。
- `/` を含む引数の文が、Golem のコードの文と分かれる。`G01017/` のように `/` の後が空の引数も、プラグインのコードの形の誤りとして報告する。利用者が Golem のコードを書こうとして `/` を混ぜた場合には、文が合わない。`/` を含む Golem のコードはないので、プラグインのコードを書こうとした場合に合わせる。
- `/` の前を検査しないので、`G01017/x` は今と同じくプラグインのコードとして受ける。

## 決めたことの記録

- **採択**：メンテナーが採択した（2026-11-04）。この ADR が決めてほしい点として挙げた項目は、どれも ADR の推奨のとおりとする。

## 参考文献

- [PR #525](https://github.com/tett23/golem/pull/525) の docs/audits/2026-11-04-rc4-followup-conformance.md（F-12）
- [docs/audits/2026-11-04-rc4-plugin-adr-conformance.md](../audits/2026-11-04-rc4-plugin-adr-conformance.md)（F-10）
- [docs/adr/0108](0108-plugin-diagnostic-codes-and-spans.md)、[docs/adr/0139](0139-plugin-diagnostic-code-starts-with-letter.md)
- [golem-cli ADR 0004](../golem-cli/adr/0004-usage-error-exit-code.md)、[golem-cli ADR 0009](../golem-cli/adr/0009-explain-several-codes.md)
- [cli/Main.hs の `checkCode` と `pluginCode`](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-cli/app/Main.hs#L141-L166)、[`explain`](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/modules/golem-cli/app/Main.hs#L239-L257)
