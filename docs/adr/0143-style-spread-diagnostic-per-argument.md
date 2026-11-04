# ADR 0143: `@style` の展開の G02114 を展開の引数ごとに出す

ステータス: 採択（未実装）

## 文脈

[docs/adr/0112](0112-spread-arguments.md) は、評価の前に引数を読む `@manifest`、`@style-def`、`@style` に展開（`*[式]`、`**[式]`）を書くと G02114 にすると決め、位置を「どれも展開の引数」とした。
展開の引数ごとに位置があるので、展開を二つ書けば二つの diagnostic になる、と読める。

`@manifest` と `@style-def` は、展開の引数ごとに G02114 を出す。
`@style` は、最初の展開の引数にだけ出す。
本体の形も属性の形も、`spreadsOf` の結果の先頭だけを取っている（[File.hs の 484 行め](https://github.com/tett23/golem/blob/97be81e8de344a22a15079b2e56bf0e5ce20ea62/modules/golem-eval/src/Golem/Eval/File.hs#L484)、[同 2063 行め](https://github.com/tett23/golem/blob/97be81e8de344a22a15079b2e56bf0e5ce20ea62/modules/golem-eval/src/Golem/Eval/File.hs#L2063)）。

2026-11-04 の監査（[docs/audits/2026-11-04-rc4-plugin-adr-conformance.md](../audits/2026-11-04-rc4-plugin-adr-conformance.md) の F-18）の指摘を、この ADR を書くために確かめ直した。
`golem new` で作ったプロジェクトで、次の原稿を `golem check` にかけた（`golem` は 5db37cb9 から組んだもので、`modules/` は [97be81e8](https://github.com/tett23/golem/tree/97be81e8de344a22a15079b2e56bf0e5ce20ea62) と同じ）。

```text
@manifest *[["a"]] **[{b: 1}]
@style-def paragraph x *[["a"]] **[{b: 1}]

# 章

@style *[["a"]] **[{b: 1}]
  本体。

@style *[["a"]] **[{b: 1}]
本文。
```

| 行 | コマンド | G02114 の数 | 位置 |
| --- | --- | --- | --- |
| 1 | `@manifest` | 2 | 1:11、1:20 |
| 2 | `@style-def` | 2 | 2:24、2:33 |
| 6 | `@style`（本体の形） | 1 | 6:8 |
| 9 | `@style`（属性の形） | 1 | 9:8 |

三つのコマンドで、同じ規則の数え方が揃っていない。
決定性は保たれているが、書き手は一つめの展開を直した後に、二つめの G02114 を初めて見る。

## 実装すること

`@style` も、展開の引数ごとに G02114 を出す。
本体の形と属性の形の両方に当てる。
位置は、それぞれの展開の引数とする。
メッセージは今と同じ `@style は評価の前に読むので、*[式] と **[式] を書けません` である。

誤りの後の扱いは変えない。
本体の形の `@style` はそのコマンドを捨て、属性の形ではその属性がないものとする。
diagnostic の数が増えるだけで、出力は変わらない。

`@manifest`、`@style-def`、`@style` の三つで、G02114 の数は書いた展開の引数の数に等しくなる。
G02114 の並びは、引数を書いた順である。

### 文書

- docs/diagnostics.md の G02114 の節に、展開の引数ごとに一つ出すことを書く。
- [docs/adr/0112](0112-spread-arguments.md) のステータスの行に、「`@style` の G02114 の数は [ADR 0143](0143-style-spread-diagnostic-per-argument.md)」を足す。

## 実装しないこと

- 展開の引数をまとめて一つの diagnostic にすること。下の「トレードオフ」を参照。
- `@style` に展開を許すこと。`@style` は評価の前に名前で本体の行の扱いを決めるので、展開を受け付けない（[docs/adr/0112](0112-spread-arguments.md) の判断を変えない）。

## テスト設計

golem-eval の `FileSpec` の `spreadTests` に、次のテストを先に書き、今の main で失敗することを確かめてから実装する。

- 本体の形の `@style *[["a"]] **[{b: 1}]` が、二つの G02114 を、それぞれの展開の引数の位置に、書いた順に出す。今の main では一つで失敗する。
- 属性の形の `@style *[["a"]] **[{b: 1}]` も同じく二つである。今の main では一つで失敗する。
- 展開が一つの `@style` は、今と同じく一つである。
- 二つの展開を書いた `@style` の後の段落が、今と同じく `@style` のないものとして出力される。

## トレードオフ

一つのコマンドに複数の diagnostic が出るので、出力が長くなる。
コマンドごとに一つにまとめる案もある。
しかし `@manifest` と `@style-def` は引数ごとに出しており、[docs/adr/0132](0132-setting-command-codes-by-cause.md) も「G02052 と G02116 と G02077 は、それぞれの引数ごとに出す」と決めている。
引数ごとに出す規則に `@style` を合わせるほうが、変える箇所が少なく、書き手も一度ですべての展開を直せる。

## 決めたことの記録

- **採択**：メンテナーが、この ADR の案のとおり採択した（2026-11-04）。

## 参考文献

- [docs/audits/2026-11-04-rc4-plugin-adr-conformance.md](../audits/2026-11-04-rc4-plugin-adr-conformance.md)（F-18）
