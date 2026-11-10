# ADR 0300: golem-driver と golem-pdf のテストのスイートを wasm32 で組めるようにする

ステータス: 採択

## 文脈

[ADR 0293](0293-run-the-test-suites-of-the-packages-of-golem-wasm-on-wasm32-every-night.md) は、`golem.wasm` のパッケージのすべてのテストのスイートを、夜ごとの `wasm-tests.yml` で wasm32 に向けて組んで走らせると決めた（不変条件 A1）。
実装のプルリクエスト（#849）の `workflow_dispatch` の実行で、27 のスイートのうち 3 つが wasm32 で組めなかった。

- **golem-driver-test と golem-driver-global-test**：二つは golem-plugin に依る。golem-plugin は `http-client-tls` を通して `network` に、`crypton-x509-store` を通して `basement` に依り、どちらも wasm32-wasi で組めない（`network` は `getaddrinfo` がなく、`basement` は「Unknown compiler」で止まる）。さらに、二つのスイートの `BuildSpec`、`CliSpec`、`LocaleSpec`、`PdfSpec`、`NewPlanSpec` は `Golem.Driver.New` を使う。`cabal.project.wasm` は golem-driver のフラグ `plugins` を外すので、ライブラリに `Golem.Driver.New` がない。
- **golem-pdf-test**：テストのコードが、`Int` に収まらないリテラルを `Int` として書く。`HexSpec` の `maxOffset = 9999999999`、`ImportSpec` の `RawObj = (Int, ByteString)` の番号 2147483648、4294967297、123456789012345678 である。wasm32 では `-Werror=overflowed-literals` で止まる。`RawObj` の番号を `Int64` にすると、`SecuritySpec` の `RawObj` を使う箇所にも型の変更が広がる。

[ADR 0293](0293-run-the-test-suites-of-the-packages-of-golem-wasm-on-wasm32-every-night.md) の「実装すること」の 1 は、wasm32 で組めない依存とオプションを `if arch(wasm32)` で外すと言い、同じ節で、golem のパッケージのあいだの `build-depends` は golem-test-support のほかに変えないと言う。
golem-plugin を wasm32 で外すことは、前の文に当たり、後の文に反する。
実装のプルリクエストは、どちらにも寄せず、二つのスイートを組めないまま残した。
golem-pdf のテストのリテラルは、[ADR 0293](0293-run-the-test-suites-of-the-packages-of-golem-wasm-on-wasm32-every-night.md) の「テストの問題」に当たるが、スイートが組めないので、落ちるテストの一覧（`scripts/wasm/test-failures.tsv`）に載せられない。

## 実装すること

1. **golem-driver の二つのスイート**：`if flag(plugins)` の条件で、`golem-plugin` への `build-depends` と、golem-plugin と `Golem.Driver.New` を使う `other-modules` と、`Main` の中のそれらのテストを、ライブラリと同じく `plugins` のときだけ組む。`cabal.project.wasm-tests` は `cabal.project.wasm` から `-plugins` を受け継ぐので、wasm32 ではそれらを組まない。ネイティブの `cabal.project` は `plugins` を外さないので、ネイティブのスイートは今と同じテストを持つ。
2. **golem-pdf のテスト**：`ImportSpec` の `RawObj` の番号を `Int64` にし、使う箇所の型を合わせる。`HexSpec` の `maxOffset` を `min 9999999999 (maxBound :: Int)` にする。製品のコードは変えない。
3. 組めるようになった三つのスイートを wasm32 で走らせ、落ちたテストを `scripts/wasm/test-failures.tsv` に、[ADR 0293](0293-run-the-test-suites-of-the-packages-of-golem-wasm-on-wasm32-every-night.md) の扱いで載せる。

## 実装しないこと

- golem-plugin を wasm32 で組めるようにすること。
- golem-driver の `plugins` のフラグの意味を変えること。

## 不変条件

- **B1 ネイティブは変わらない**：ネイティブ（`plugins` を外さない）の golem-driver の二つのスイートと golem-pdf-test のテストの名前の集合は、この ADR の前と同じである。
- **B2 wasm32 で組める**：`cabal.project.wasm-tests` で、`scripts/ci/test-suites.sh wasm` のすべてのスイートが組める。
- **B3 plugins の外のテストだけを外す**：`plugins` を外したときに組まないテストは、golem-plugin か `Golem.Driver.New` を使うテストだけである。

境界の入力：

| 入力 | 期待 |
| --- | --- |
| ネイティブ、`plugins` あり | B1 |
| wasm32、`plugins` なし | B2、B3 |
| `RawObj` の番号 2^31 − 1、2^31、2^32 + 1 | wasm32 でも同じ PDF のバイト列を作る |

## テスト設計

- **B1**：実装の前と後で、ネイティブのスイートの `--list-tests` を比べる。
- **B2**：`wasm-tests.yml` の要約に「not built」がないことを、`workflow_dispatch` の実行で確かめる。
- **B3**：`plugins` を外して組んだ golem-driver のスイートの `--list-tests` と、ネイティブのものの差が、golem-plugin か `Golem.Driver.New` を使う spec のテストだけであることを、実装のプルリクエストに書く。

## トレードオフ

`plugins` の外では、`golem new` とプラグインのテストが wasm32 で走らない。
`golem.wasm` はそもそもプラグインと `golem new` を持たないので、失うものはない。
CPP の条件で組むテストが増え、テストのコードが読みにくくなる。

## メンテナーが決めること

1. **golem-driver の二つのスイートの扱い**：推奨は 1 の、`plugins` のフラグで golem-plugin と `Golem.Driver.New` を使うテストを外すことである。ライブラリの `plugins` と同じ線で分かれる。
   - 退けた案の一つは、二つのスイートを [ADR 0293](0293-run-the-test-suites-of-the-packages-of-golem-wasm-on-wasm32-every-night.md) の W から外すことである。golem-driver のテストの大半（組版の経路のテスト）が wasm32 で走らなくなる。
   - もう一つは、プラグインのテストを別のスイートに移すことである。A1 で新しいスイートも W に入るので、組めない問題は残る。
2. **golem-pdf のテストの直し方**：推奨は 2 の、テストの型を `Int64` にすることである。

## 決めたことの記録

2026-11-10 に、tett23 が「メンテナーが決めること」のすべてを推奨のとおりに決めた。

1. golem-driver の二つのスイートは、ライブラリと同じく `plugins` のフラグで、golem-plugin と `Golem.Driver.New` を使うテストを外して組む。
2. golem-pdf のテストは、`ImportSpec` の `RawObj` の番号を `Int64` にし、`HexSpec` の `maxOffset` を `Int` に収めて直す。製品のコードは変えない。

## 参考文献

- [ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md)、[ADR 0247](0247-keep-the-values-of-golem-wasm-independent-of-the-width-of-int.md)、[ADR 0293](0293-run-the-test-suites-of-the-packages-of-golem-wasm-on-wasm32-every-night.md)
- [#849](https://github.com/tett23/golem/pull/849)（[ADR 0293](0293-run-the-test-suites-of-the-packages-of-golem-wasm-on-wasm32-every-night.md) の実装）の `wasm-tests.yml` の実行 42766458584 と 42769900004 のビルドの記録
