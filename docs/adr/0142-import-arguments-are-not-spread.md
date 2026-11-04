# ADR 0142: `@import` の引数を評価器で展開しない

ステータス: 採択

## 文脈

[docs/adr/0112](0112-spread-arguments.md) は、`*[式]` と `**[式]` をすべてのコマンドの引数に展開すると決め、例外として次のように書いた。

> `@import` は変えない。
> `@import` はプロジェクトの段階で `パス as 名前空間` の構文として読み、引数の値を読むのではないからである。
> 展開を書いた `@import` は、今のとおり形の誤り（G03009）である。

実装では、`@import` の引数にも展開が走る。
評価器のブロックコマンドの枝は、`@manifest` と `@style-def` だけを展開の前に分け、ほかのコマンドは `prepareArgs` で展開してから `standalone` に渡す（[File.hs の 480 行めから 485 行め](https://github.com/tett23/golem/blob/97be81e8de344a22a15079b2e56bf0e5ce20ea62/modules/golem-eval/src/Golem/Eval/File.hs#L480-L485)、[`prepareArgs`](https://github.com/tett23/golem/blob/97be81e8de344a22a15079b2e56bf0e5ce20ea62/modules/golem-eval/src/Golem/Eval/File.hs#L2022-L2043)）。
`@import` は `standalone` の中で `importSite` に読まれる（[File.hs の 503 行めから 516 行め](https://github.com/tett23/golem/blob/97be81e8de344a22a15079b2e56bf0e5ce20ea62/modules/golem-eval/src/Golem/Eval/File.hs#L503-L516)）が、そのときには展開が終わっている。

プロジェクトの中では、この食い違いは見えない。
プロジェクトは評価の前に `importsOf` で `@import` を読み、展開を書いた `@import` を G03009 にして評価に進まない（[Imports.hs の 40 行めから 56 行め](https://github.com/tett23/golem/blob/97be81e8de344a22a15079b2e56bf0e5ce20ea62/modules/golem-project/src/Golem/Project/Imports.hs#L40-L56)）。
プロジェクトの外の一つのファイル（`golem inspect` など）は、`importsOf` を通らずに評価されるので、展開の結果を `importSite` が読む。

2026-11-04 の監査（[docs/audits/2026-11-04-rc4-plugin-adr-conformance.md](../audits/2026-11-04-rc4-plugin-adr-conformance.md) の F-17）は、これをコードの読みから指摘し、実機では確かめていなかった。
この ADR を書くために、同じ原稿をプロジェクトの中と外で評価した。
`golem` は 5db37cb9 から組んだもの（`modules/` は [97be81e8](https://github.com/tett23/golem/tree/97be81e8de344a22a15079b2e56bf0e5ce20ea62) と同じ）で、外は `golem inspect single.gm --as ir`、中は `golem new` で作ったプロジェクトの `golem check` である。

| 原稿 | プロジェクトの中 | プロジェクトの外 |
| --- | --- | --- |
| `@import *[["x.gm"]] as n` | G03009 | 誤りなし。`importSite` が `"x.gm" as n` として受け付ける |
| `@import *[1]` | G03009 | G02111（`*[式] の値は配列でなければなりません: 自然数`） |
| `@import *[y]`（`y` は未定義） | G03009 | G02002（`未定義の名前 y です`） |

同じ原稿の `@import` が、評価の経路によって受け付けられたり、三つの違うコードになったりする。
「決定性の対象に diagnostic も含む」と、[docs/adr/0112](0112-spread-arguments.md) の明示の規則のどちらにも反する。
一つめの行は、プロジェクトの中で拒む書き方を外では受け付けるので、「緩い規則より厳しい規則」にも反する。

## 実装すること

評価器は、`@import` の引数を展開しない。
`@manifest` と `@style-def` と同じく、`prepareArgs` の前に分け、書かれた引数のまま `standalone` に渡す。
展開の引数を含む `@import` は、`importSite` が今の規則で G03009 にする。
プロジェクトの中と外で、コード、メッセージ、位置（`@import` のブロック）が同じになる。

| 原稿 | プロジェクトの中 | プロジェクトの外（この ADR） |
| --- | --- | --- |
| `@import *[["x.gm"]] as n` | G03009 | G03009 |
| `@import *[1]` | G03009 | G03009 |
| `@import *[y]` | G03009 | G03009 |

新しいコードは作らない。
展開の式は評価しないので、式の中の誤り（G02002 など）も出さない。
プロジェクトの中で `importsOf` が式を評価しないのと同じである。

### 文書

- docs/diagnostics.md の G02114 の節の「`@import` の展開は、このコードではなく形の誤り（G03009）である」と、docs/markup.md の 1157 行めは、この ADR の後にどの経路でも正しくなる。G02114 の ADR の欄にこの ADR を足す。
- docs/diagnostics.md の G03009 の節に、展開を書いた `@import` がプロジェクトの外の評価でも G03009 になることを足す。
- [docs/adr/0112](0112-spread-arguments.md) のステータスの行に、「`@import` を展開しないことの実装は [ADR 0142](0142-import-arguments-are-not-spread.md)」を足す。

## 実装しないこと

- `@import` に展開を許すこと。`@import` はプロジェクトの段階で依存の図を作るために読むので、評価の前に引数が決まっていなければならない（[docs/adr/0112](0112-spread-arguments.md) の判断を変えない）。
- 展開を書いた `@import` に、G02114（評価の前に引数を読むコマンドに展開を書いた）を当てること。下の「トレードオフ」を参照。
- プロジェクトの外の評価で `@import` を読む経路の、展開と関係のない振る舞い（名前空間の値を読み込まないことなど）。

## テスト設計

golem-eval の `FileSpec` の `spreadTests` に、次のテストを先に書き、今の main で失敗することを確かめてから実装する。
どれも、プロジェクトを通さずに一つのファイルを評価する。

- `@import *[["x.gm"]] as n` が G03009 になり、名前空間 `n` を作らない。今の main では誤りにならずに失敗する。
- `@import *[1]` が G03009 だけになる。今の main では G02111 になって失敗する。
- `@import *[y]`（`y` は未定義）が G03009 だけになる。今の main では G02002 になって失敗する。
- `@import **[{a: 1}]` が G03009 になる。今の main でも G03009 で、変わらないことを固定する。
- それぞれのメッセージと位置が、golem-project の `importsOf` が同じ原稿に出すものと同じである。

## トレードオフ

`@manifest`、`@style-def`、`@style` は、展開を書くと G02114 になる。
`@import` は G03009 のままなので、「評価の前に引数を読むコマンドに展開を書いた」という見方では、同じ原因に二つのコードがあるように見える。
それでも G03009 を保つ。

- [docs/adr/0112](0112-spread-arguments.md) が `@import` を G03009 と明示しており、プロジェクトの中では今もそう振る舞う。G02114 に変えると、プロジェクトの中のコードも変えることになる。
- `@import` の規則は「`パス as 名前空間` の形でなければ G03009」であり、展開は形の誤りの一つとして読める。`@import a b c d` も同じコードである。

G02114 に揃える案は、利用者の見るコードを変えるので、別の ADR で決める。

## 決めたことの記録

- **採択**：メンテナーが、この ADR の案のとおり採択した（2026-11-04）。

## 参考文献

- [docs/audits/2026-11-04-rc4-plugin-adr-conformance.md](../audits/2026-11-04-rc4-plugin-adr-conformance.md)（F-17）
