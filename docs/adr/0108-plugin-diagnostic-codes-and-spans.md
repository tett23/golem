# ADR 0108: プラグインが返す diagnostic のコードと位置を検査する

ステータス: 採択→コードの先頭の文字は [ADR 0139](0139-plugin-diagnostic-code-starts-with-letter.md)

## 文脈

プラグインの応答は、出力と diagnostic の列を持つ（[golem-plugin ADR 0001](../golem-plugin/adr/0001-wasm-host-and-abi.md)）。
CDDL では `plugin-diagnostic = [code: tstr, severity: 0 / 1, span, message: tstr]` である。
ホストは、出力のノードについては、ソース位置が呼び出しの位置か要求に含まれていたノードの位置であることを検査する。
しかし、diagnostic の列は検査しない。

見本のプラグイン `lookup`（[docs/adr/0106](0106-sample-plugins-in-rust.md)）を書いて動かしたところ、次の二つが分かった。

**コード**：ホストは diagnostic のコードの文字列をそのまま diagnostic のコードにする（[`response`](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-plugin/src/Golem/Plugin.hs#L291-L306)）。
`lookup` が返した `lookup-no-key` は、`golem build` で `error[lookup-no-key]` と表示された。
このコードは `golem explain` で引けず、`docs/diagnostics.md` の「G、段階の二桁、三桁」の形（[docs/adr/0061](0061-five-digit-diagnostic-codes.md)）にも合わない。
プラグインが `G02022` のような Golem 自身のコードを返すこともでき、そのときは Golem の diagnostic と見分けられない。
[golem-plugin ADR 0003](../golem-plugin/adr/0003-plugin-diagnostic-codes.md) は、プラグインが返す diagnostic のコードを「実装しないこと」に置いたまま、どこでも決めていない。

**位置**：diagnostic の `span` は、CBOR として位置の形であることだけを確かめ、どのファイルのどの範囲かは確かめない。
出力のノードに課している「呼び出しの位置か、要求に含まれていたノードの位置」という制約が、diagnostic にはない。
プラグインは、要求に含まれないファイルや、ファイルの長さを超える範囲を指す diagnostic を返せる。

**重大度**：`severity` はエラーと警告の二つだけで、notice と info（[docs/adr/0104](0104-info-severity.md)）を返せない。

## 実装すること

- プラグインが返す diagnostic のコードは、`<プラグインの宣言の名前>/<英小文字、数字、- の列>` の形にホストが組み立てる。プラグインは後ろの部分だけを返し、形の誤りは不正な出力（G06009）とする。これで Golem のコードとも、ほかのプラグインのコードとも重ならない。
- diagnostic の `span` は、出力のノードと同じく、呼び出しの位置か、要求に含まれていたノードの位置に限る。違反は不正な出力（G06009）とする。
- `golem explain` は、プラグインのコードには説明がないことを、使い方の誤りではなく一行で伝える。

### フィルタの diagnostic の位置

上の `span` の制約では、フィルタが報告できない誤りがある。
二つのルビのプラグイン（[docs/adr/0130](0130-sou-ruby-plugin.md)、[docs/adr/0131](0131-first-occurrence-ruby-plugin.md)）を書いて分かった。

- フィルタには呼び出しの位置がない。要求は文書とデータだけである。
- データ（[docs/adr/0105](0105-plugin-data.md)）の誤り（TSV の行の誤り、辞書のファイルの欠け）は、文書のどのノードにも属さない。データのファイルの中の位置は、要求に含まれない。
- 誤りのある文書が空のファイル（ブロックのない文書）なら、指せるノードが一つもない。

二つのプラグインは、このような誤りを、フィルタを当てたファイルの先頭（`[file, 0, 0]`）で報告している。
ホストも、フィルタの実行の失敗（G06009）を同じ位置で報告する（[`applyFilters`](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-driver/src/Golem/Driver/Plugins.hs#L97-L111)）。
ところが、ファイルの先頭は要求に含まれたノードの位置ではないので、上の制約のままでは、ホストがこれらの diagnostic を G06009 として拒む。

そこで、`span` の制約に、フィルタについて次の一つを足す。

- フィルタの応答の diagnostic は、要求に含まれていたノードの位置に加えて、要求の文書のファイルの先頭（`[file, 0, 0]`、`file` は文書の `file`）を指してよい。

ほかのファイルの先頭、ファイルの長さを超える位置は、上の制約のとおり G06009 とする。
コマンドの応答には、この例外を設けない。
コマンドには呼び出しの位置があり、データの誤りもそこで報告できるからである。

## 実装しないこと

- プラグインが diagnostic の説明を `golem_describe` で宣言し、`golem explain` が表示すること。
- notice と info の重大度。必要になったら ABI のバージョンを上げて足す。
- `manifest.toml` の `silence-notices` でプラグインの警告を抑えること。
- フィルタの diagnostic が、データのファイルの中の位置を指すこと。データに位置を与える形を決める必要があり、「トレードオフ」のとおり別に決める。
- 同じデータの誤りが、フィルタを当てたファイルの数だけ重なることを、ホストで一つにまとめること（[docs/adr/0131](0131-first-occurrence-ruby-plugin.md) の「トレードオフ」）。

## テスト設計

下のテストのうち、見本のプラグイン first-ruby（[docs/adr/0131](0131-first-occurrence-ruby-plugin.md)）を使うものは、この ADR の実装では書かない。
この ADR の実装では、同じことを wat のテスト用のプラグイン（`modules/golem-plugin/test/` と golem-driver のテストの wat）で確かめるテストを先に書く。
見本のプラグインを使うテストは、結合のテストとして、その見本のプラグインの ADR を実装するときに足す。
見本のプラグインの ADR が、この ADR より後に実装されるからである。

- `lookup` の `no-key` が `lookup/no-key` として表示され、JSON の diagnostics のコードも同じであること。
- `G02022` や `Lookup/x` を返す fixed.wat のプラグインが G06009 になること。
- 要求にない位置（別のファイル、ファイルの外）を指す diagnostic を返すプラグインが G06009 になること。
- `first-ruby` に誤った TSV を渡すと、`first-ruby-tsv` の diagnostic が、フィルタを当てたファイルの先頭の位置で報告され、G06009 にならないこと（golem-driver の `PluginsSpec` の既存のテストを、この ADR の実装の後も通す）。
- 空のファイルに当てた `first-ruby` が、データの誤りをファイルの先頭で報告できること。
- fixed.wat のフィルタが、別のファイルの先頭（`[file + 1, 0, 0]`）を指す diagnostic を返すと G06009 になること。
- fixed.wat のコマンドが、ファイルの先頭を指す diagnostic を返すと G06009 になること。

## トレードオフ

コードにプラグインの宣言の名前を前置するので、同じプラグインでもプロジェクトでの名前によってコードが変わる。
プラグインの配布物の名前は宣言の外にないので、ホストが前置できる名前はこれしかない。

位置を制約すると、プラグインが「設定のファイル」のような要求の外の位置を指せなくなる。
データのファイル（[docs/adr/0105](0105-plugin-data.md)）の中の位置を指せるようにするかは、データに位置を与える形と合わせて別に決める。

フィルタにファイルの先頭を許すと、フィルタは、誤りの場所が分かっていても先頭で報告できてしまう。
位置の正確さはプラグインの作者に任せることになるが、データの誤りを報告できないよりはよい。

## 決めたことの記録

- 2026-10-29、メンテナー：フィルタの diagnostic にファイルの先頭を許す修正を、ルビのレーン（[docs/adr/0130](0130-sou-ruby-plugin.md)、[docs/adr/0131](0131-first-occurrence-ruby-plugin.md)）が短い提案として書き、この ADR に後でまとめると決めた。「フィルタの diagnostic の位置」の節は、その提案をまとめたものである。
- **テストのプラグイン**：メンテナーが、土台の ADR は wat のテスト用のプラグインで試し、見本のプラグインを使う結合のテストは見本のプラグインの実装のときに足す運用にすると決めた（2026-11-04）。

## 参考文献

なし
