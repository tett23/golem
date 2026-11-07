# ADR 0198: 機能を組み合わせた二冊の fixture で、G07030 と G07046 だけを止める

ステータス: 採択

## 文脈

[ADR 0175](0175-complex-typesetting-fixture.md) は、機能を組み合わせた二冊の fixture（`complex-vertical` と `complex-horizontal`）を作り、出力のゴールデン、決定性の検査、見た目の回帰テストで、機能のあいだの相互作用を固定すると決めた。
同じ ADR は、二冊が「どのターゲットでも diagnostic を一つも出さない」とも決めた（[ADR 0175](0175-complex-typesetting-fixture.md) の「diagnostics」と、「メンテナーが決めること」の 4）。
相互作用が notice を出す組み合わせは、原稿で避けるという決まりである。

ところが、[ADR 0175](0175-complex-typesetting-fixture.md) が二冊に求める機能のうち、二つは、使えば必ず notice を出す。

- **コードブロックの折り返す行**：[ADR 0175](0175-complex-typesetting-fixture.md) は、コードブロックに「折り返す行」を含めると決めた。PDF の組版は、コードの行を一行でも折り返すと、そのコードブロックの位置に notice の G07030 を出す（[`Flow.hs`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L2262)、[golem-driver ADR 0017](../golem-driver/adr/0017-pdf-code-blocks.md)）。条件は折り返した行の数が 1 以上であることだけである。
- **ページか段の境で分かれる、罫線を持つ段落**：[ADR 0175](0175-complex-typesetting-fixture.md) は、段落スタイルの罫線を持つ段落に、ページ（横組みの本では段）の境で分かれるものを一つ以上含めると決めた（[golem-driver ADR 0035](../golem-driver/adr/0035-paragraph-rules-split-and-space-units.md)）。PDF の組版は、罫線を持つ段落の行が二つ以上の段に置かれると、notice の G07046 を出す（[`Flow.hs`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L520-L538)、[golem-driver ADR 0027](../golem-driver/adr/0027-paragraph-style-rules.md)）。`ruledNotices` の条件は `columns > 1 || lost` であり、分かれた段落は `columns > 1` で必ず notice になる。

[ADR 0175](0175-complex-typesetting-fixture.md) の二つの決まりは、両立しない。
機能を使えば notice が出て、notice を出さなければ機能を使えない。

### 実装がしたこと

[ADR 0175](0175-complex-typesetting-fixture.md) の実装（#597）は、二つの機能を残し、二冊の `manifest.toml` に次の行を置いた（[`complex-vertical/manifest.toml`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-driver/test/fixtures/complex-vertical/manifest.toml#L35-L39)、[`complex-horizontal/manifest.toml`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-driver/test/fixtures/complex-horizontal/manifest.toml#L35-L39)）。

```toml
[diagnostics]
silence-notices = ["G07030", "G07046"]
```

`silence-notices` に並べたコードの notice は、`golem build`、`golem check`、`golem lint`、LSP のどれにも出ない（[docs/specifications.md](../specifications.md) の `[diagnostics]` の節）。
出力のゴールデンのテストは、二冊を `buildOne tmp target []` で組み、diagnostics が空であることを断言する（[`OutputGoldenSpec.hs`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-driver/test/OutputGoldenSpec.hs#L124-L141)）。
二つの notice を止めたうえで、ほかの diagnostic が一つでも出れば落ちる。
fixtures の README も、二つのコードだけを止めることを書いている（[`README.md`](https://github.com/tett23/golem/blob/e491d7898e702296e6d373b524c6455ec2a5e0e6/modules/golem-driver/test/fixtures/README.md#L70-L73)）。

#597 は、この扱いをメンテナーに確かめるよう、説明に書いた。

### 止めた notice が実際に出ること

二冊の `manifest.toml` から `silence-notices` の行を除き、PDF を組んで確かめた（2026-11-07）。
使った `golem` は、`.claude/worktrees/impl-0177` のブランチ（`cd66f272`、[ADR 0175](0175-complex-typesetting-fixture.md) の後の main をマージしたもの）でビルドしたものである。
フォントは、`OutputGoldenSpec` の `copyFonts` と同じく、Noto Serif JP と Source Sans Pro を `fonts/ja.otf` と `fonts/latin.otf` に写した。

| 本 | G07030 | G07046 | ほかの diagnostic |
| --- | --- | --- | --- |
| `complex-vertical` | 1 | 1 | なし |
| `complex-horizontal` | 2 | 1 | なし |

二冊とも、止めているのはこの二つのコードだけであり、ほかの diagnostic は出なかった。

### 止める範囲

`silence-notices` は、コードの単位で、本の全体の notice を止める。
二冊が G07030 を出すコードブロックが、変更で一つから三つに増えても、テストは落ちない。
止めた二つのコードについては、[ADR 0175](0175-complex-typesetting-fixture.md) の「変更が新しい notice を出すようになれば、テストが落ちて気付ける」が成り立たない。
ほかのコードについては成り立つ。
一方、`silence-notices` に三つめのコードを足すと、そのコードの notice も黙って止まる。
今のテストは、`manifest.toml` の `[diagnostics]` の中身を確かめないので、これに気付けない。

## 実装すること

### diagnostics の条件

[ADR 0175](0175-complex-typesetting-fixture.md) の「二冊は、どのターゲットでも diagnostic を一つも出さない」を、次のように改める（「決めたことの記録」）。

> 二冊は、どのターゲットでも、G07030 と G07046 のほかの diagnostic を出さない。二冊の `manifest.toml` は、`[diagnostics]` の `silence-notices` に G07030 と G07046 の二つだけを並べ、ほかの diagnostic を止める手段を使わない。

- 二つの機能（折り返すコードの行と、分かれる罫線を持つ段落）は、[ADR 0175](0175-complex-typesetting-fixture.md) のとおり二冊に残す。
- 止める二つのコードは、どちらも notice である。error と warning は、`silence-notices` で止められない。
- 「ほかの diagnostic を止める手段」は、`silence-notices` のほかのコード、`silence-info`、`golem build` の `--no-notices` である。二冊の `manifest.toml` はほかの二つを書かず、`OutputGoldenSpec` と決定性の検査は `--no-notices` を付けない。

### テストで強いること

条件は、二つのテストで強いる。

- **出力のゴールデン**：今のとおり、`OutputGoldenSpec` の `complexOutput` は、`buildOne tmp target []` で diagnostics が空であることを断言する。止めた二つのほかの diagnostic が一つでも出れば落ちる。テストは変えず、`complexOutput` のコメントの「Neither gives a diagnostic on any target」を、二つの notice を止めたうえでのことと分かるように直す。
- **止めるコードの一覧**：`ComplexFixtureSpec` に、二冊のそれぞれで、`manifest.toml` の `[diagnostics]` の表がちょうど `silence-notices = ["G07030", "G07046"]` の一つのキーだけを持つことを確かめるテストを足す。表は、`ComplexFixtureSpec` が `style.toml` に使う `tables` で切り出し、空の行とコメントの行を除いて比べる。コードを足しても、`silence-info` を書いても、`[diagnostics]` を消しても落ちる。

二つめは、原稿の記法を読む `ComplexFixtureSpec` の今のテストと同じく、出力ではなく入力を読む。
`[diagnostics]` を消すと、一つめのテストも G07030 と G07046 で落ちる。

### 文書とステータスの行

- fixtures の README は、すでに二つのコードだけを止めることを書いているので、直さない。`ComplexFixtureSpec` がそれを確かめることを一文足す。
- 二冊の `manifest.toml` のコメントは、今のままにする。
- この ADR を実装するプルリクエストで、この ADR のステータスの行を「採択」にし、[ADR 0175](0175-complex-typesetting-fixture.md) のステータスの行を「採択」から「採択→diagnostics の条件（G07030 と G07046 を止めること）は [ADR 0198](0198-silenced-notices-of-complex-fixtures.md)」にする。

## 実装しないこと

- **二つの機能を二冊から除くこと**：メンテナーが退けた（「決めたことの記録」）。折り返すコードの行と、段の境で分かれる罫線を持つ段落は、ほかのどの入力も組み合わせていない相互作用である（[ADR 0175](0175-complex-typesetting-fixture.md) の「文脈」）。除けば、[ADR 0175](0175-complex-typesetting-fixture.md) が固定しようとしたものが減る。
- **止めた notice の数を固定すること**：`silence-notices` を外して組み、G07030 と G07046 の数と位置を断言するテストは作らない。二冊を PDF でもう一度ずつ組むことになり、golem-driver のテストの時間が増える。notice の条件は、`ParagraphRuleSpec` と `DiagnosticsSpec` の単体のテストが受け持つ。二冊が二つの機能を使い続けることは、`ComplexFixtureSpec` が原稿の記法で確かめる。
- **一つのコードブロックや段落だけで notice を止めること**：notice の抑制は、`silence-notices` と `--no-notices` による本の全体の単位であり、箇所ごとに止める手段はない（[docs/specifications.md](../specifications.md) の G07039 の段落）。この fixture のために足すことはしない。
- **G07030 と G07046 の出し方を変えること**：notice の条件を変えれば、すべての本の diagnostics が変わる。この ADR は fixture の条件だけを改める。

## テスト設計

テストを先に書き、失敗することを確かめてから実装する。

- `ComplexFixtureSpec` の止めるコードの一覧のテスト：今の二冊の `manifest.toml` では通る。手元で、一方の `silence-notices` に G07039 を足したとき、`silence-info = []` を足したとき、`[diagnostics]` を消したときに、それぞれ落ちることを確かめ、プルリクエストの説明に書く。
- `OutputGoldenSpec` の四つのゴールデンのテスト：変えず、そのまま通ること。
- `scripts/determinism/hashes.txt`、`scripts/visual/pages/` の参照、`test/golden/` のファイルは変わらない。この ADR は二冊の原稿も `manifest.toml` も変えないからである。

## トレードオフ

二冊は、[ADR 0175](0175-complex-typesetting-fixture.md) が意図した「よい原稿」の例から、二つの notice を止めた原稿になる。
[ADR 0175](0175-complex-typesetting-fixture.md) は、notice を原稿の側で取り除くものとしたが、この二つは原稿の側で取り除けない。
コードの行を折り返さず、罫線を持つ段落を分けない原稿にすれば、相互作用そのものがなくなるからである。

止めた二つのコードの notice は、増えても減っても、どのテストも気付かない。
たとえば、変更が二冊の別のコードブロックまで折り返すようになっても、G07030 では気付けない。
ただし、そうした変更はページの配置を変えるので、出力のゴールデンと見た目の回帰テストの参照の差分として現れる。
差分を読むレビュー（[ADR 0175](0175-complex-typesetting-fixture.md) の「ゴールデンの更新のレビュー」）が、その代わりになる。

二つのマニュアルの方針（[docs/manual-policy.md](../manual-policy.md)）は、マニュアルの `manifest.toml` に `silence-notices` を書くことを禁じ、`scripts/manual/build.sh` が組む前に止める。
折り返したコードの行のような notice の原因は、原稿の側で取り除くとする。
二冊の fixture は、マニュアルと違う扱いになる。
マニュアルは読み手に見せる本であり、コードの行を折り返さないように原稿を直せる。
fixture は機能の相互作用を固定するための入力であり、notice を出す機能そのものを固定する。

## 決めたことの記録

- **二つの notice を止めること**（2026-11-07、メンテナー）：#597 の扱い（二冊の `manifest.toml` の `silence-notices = ["G07030", "G07046"]`）を認める。[ADR 0175](0175-complex-typesetting-fixture.md) の diagnostics の条件は「止めた二つの notice のほかの diagnostic を出さない」とし、テストは、ゴールデンのテストの diagnostics が空であることと、`silence-notices` がこの二つだけを並べることで強いる。
- **退けた案**（2026-11-07、メンテナー）：二つの機能を二冊から除くことは退けた。

## 参考文献

- [ADR 0175](0175-complex-typesetting-fixture.md)
- [golem-driver ADR 0017](../golem-driver/adr/0017-pdf-code-blocks.md)、[golem-driver ADR 0027](../golem-driver/adr/0027-paragraph-style-rules.md)、[golem-driver ADR 0035](../golem-driver/adr/0035-paragraph-rules-split-and-space-units.md)
- [golem-syntax ADR 0002](../golem-syntax/adr/0002-notice-severity.md)（`silence-notices`）
- プルリクエスト #597（[ADR 0175](0175-complex-typesetting-fixture.md) の実装）の説明
