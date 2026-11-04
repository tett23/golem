# ADR 0137: 原稿の図版の出力のパスがプラグインの画像のフォルダーと重なるときの G08102

ステータス: 採択

## 文脈

[docs/adr/0123](0123-figures-from-plugins.md) は、プラグインが作った画像を、HTML と EPUB では `images/golem-plugin/<SHA-256>.<拡張子>` に書くと決めた。
原稿の `@figure` の画像は、HTML と EPUB ではプロジェクトの中のパスのまま写す。
原稿の画像を `images/golem-plugin/` に置くと、二つが同じフォルダーに並び、名前によっては一方が他方を上書きする。

[docs/adr/0123](0123-figures-from-plugins.md) は、これを「実装しないこと」の節に次のように書いたまま採択された。

> 原稿の図版の出力のパスが `images/golem-plugin/` と重なるときのエラー。試しの実装には入れていない。採択の前に、コード G08102（出力の段階として割り当てた）と一緒に足す。

「採択の前に足す」は、本文の「実装すること」に移すつもりの覚え書きだった。
移さないまま採択されたので、ADR の字面では実装しないことになり、エラーの文言、重大度、出す条件はどこにも決まっていない。
実装（PR #491）は G08102 を入れ、文言と条件を実装側で決めた（[`pluginImagePathDiagnostics`](https://github.com/tett23/golem/blob/97be81e8de344a22a15079b2e56bf0e5ce20ea62/modules/golem-driver/src/Golem/Driver.hs#L679-L692)、呼び出しは [Driver.hs の 657 行めから 662 行め](https://github.com/tett23/golem/blob/97be81e8de344a22a15079b2e56bf0e5ce20ea62/modules/golem-driver/src/Golem/Driver.hs#L657-L662)）。
docs/diagnostics.md、仕様書、両マニュアル、テスト（[PluginsSpec.hs の 352 行めから 357 行め](https://github.com/tett23/golem/blob/97be81e8de344a22a15079b2e56bf0e5ce20ea62/modules/golem-driver/test/PluginsSpec.hs#L352-L357)）もそろっている。
実装者はこれを申告した。

2026-11-04 の監査（[docs/audits/2026-11-04-rc4-plugin-adr-conformance.md](../audits/2026-11-04-rc4-plugin-adr-conformance.md) の F-25）は、`@figure images/golem-plugin/a.svg alt=x` を HTML を含む本で組むと G08102 が出て、`build/` に PDF とテキストだけが書かれ、`--target pdf` では出ないことを確かめた。
プラグインを使わない本にも出る新しいエラーなので、ADR の「実装しないこと」との矛盾を、短い ADR で記録に残すよう求めた。

この ADR は、今の G08102 の振る舞いを決定として記録する。

## 実装すること

### G08102

| 項目 | 決めること |
| --- | --- |
| 重大度 | エラー |
| 条件 | 原稿の `@figure` で、HTML と EPUB に写す画像（`web` があれば `web`、なければ図版そのもの）のパスが、`./` と `..` を正規化した後で `images/golem-plugin/` で始まる |
| 本にプラグインがあるか | 問わない。プラグインを宣言していない本でも出す |
| 出す時 | `golem build` で、HTML か EPUB を書くとき。`golem check` と、HTML も EPUB も書かないビルド（`--target pdf` など）では出さない |
| 効果 | HTML と EPUB を書かない。PDF とプレーンテキストは書く |
| 数と位置 | `@figure` ごとに一つ、その `@figure` のブロックの位置 |
| メッセージ | `図版の画像の出力のパスが、プラグインの画像を置くフォルダー images/golem-plugin と重なります: <パス>` |
| 段階 | 出力（golem-driver の `Golem.Driver`） |

今の main は、この表のとおりに振る舞う。
コードは変えない。

### 理由

- **プラグインの有無を問わない**：プラグインを足したとたんに、それまで通っていた本が止まるのを避ける。フォルダーの名前は Golem が予約した名前として扱い、本の構成によらず同じ規則を当てる。規則が本の構成に依らないので、結果も予測しやすい。
- **重なる名前だけでなく、フォルダーの全体を拒む**：プラグインの画像の名前は画像のバイト列の SHA-256 で決まる。実際に同じ名前になるかどうかは、プラグインの出力とそのデータで変わる。フォルダーの全体を拒めば、原稿だけを見て判定できる。
- **警告でなくエラー**：重なれば一方のファイルが他方を黙って上書きし、出力が変わる。「出力を黙って変えない」の原則から、書かずに止める。
- **HTML と EPUB だけを止める**：PDF は画像のバイト列をファイルに写さず、プレーンテキストは画像を書かない。重なりの害はこの二つの媒体にない。HTML と EPUB の SVG を止める G08014（[docs/adr/0039](0039-svg-active-content-in-html-and-epub.md)）と同じ扱いである。
- **`golem check` で出さない**：出力の段階のコードであり、同じ段階の G08014 も `golem build` でだけ出す。

### 文書

- [docs/adr/0123](0123-figures-from-plugins.md) のステータスの行に、「`images/golem-plugin/` と重なる原稿の図版のエラー（G08102）は [ADR 0137](0137-plugin-image-folder-collision-g08102.md)」を足す。
- docs/diagnostics.md の G08102 の節の ADR の欄に、この ADR を足す。仕様書の G08102 の段落にも、この ADR へのリンクを足す。ほかの記述は、すでにこの ADR の表のとおりである。

## 実装しないこと

- プラグインの画像のフォルダーの名前を変えること。どんな名前にしても、原稿の画像のパスと重なりうる。
- 実際に同じファイルの名前になったときだけ拒むこと。上の「理由」を参照。
- G08102 を `golem check` と LSP で出すこと。出力の段階のコードを `golem check` で出すかどうかは、G08014 と合わせて別に決める。
- [docs/adr/0123](0123-figures-from-plugins.md) の「実装しないこと」の節を書き換えること。コミット済みの ADR は書き換えない。この ADR が訂正の記録である。

## テスト設計

コードを変えないので、新しいテストは書かない。
今のテストが、この ADR の表を固定している。

- golem-driver の `PluginsSpec` の `G08102: a figure of the source where HTML and EPUB put the images of plugins`（[PluginsSpec.hs の 352 行めから 357 行め](https://github.com/tett23/golem/blob/97be81e8de344a22a15079b2e56bf0e5ce20ea62/modules/golem-driver/test/PluginsSpec.hs#L352-L357)）。プラグインのない本で、`./images/golem-plugin/x.svg` の図版が G08102 になり、メッセージが表のとおりである。

ステータスの行と文書を直した後、`adr-guard links` と `adr-guard check-status` が通ることを確かめる。

## トレードオフ

プラグインを使わない本でも、`images/golem-plugin/` という名前のフォルダーに画像を置けなくなる。
このフォルダーの名前を偶然使う本は少ないと見込むが、使っていた本は、画像を移してパスを直す手間を負う。
rc3 にはこのフォルダーの意味がなかったので、rc3 で通っていた本が rc4 で止まる場合がある。

`golem check` で出さないので、LSP とエディタでは気づけず、`golem build` で初めて見える。
G08014 と同じ制約である。

ADR の「実装しないこと」に置いた項目を、実装が ADR なしに入れた。
今回は文言、重大度、条件のどれも原則に沿っていたが、採択の前に覚え書きを本文に移す手順が抜けていた。

## 決めたことの記録

- **採択**：メンテナーが、この ADR の案のとおり採択した（2026-11-04）。

## 参考文献

- [docs/audits/2026-11-04-rc4-plugin-adr-conformance.md](../audits/2026-11-04-rc4-plugin-adr-conformance.md)（F-25）
