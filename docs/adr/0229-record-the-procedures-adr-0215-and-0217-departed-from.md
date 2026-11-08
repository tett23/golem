# ADR 0229: [ADR 0215](0215-ref-number-and-ref-title-as-reference.md) と 0217 の実装が手順から外れた点を記録する

ステータス: 採択（未実装）

## 文脈

[ADR 0215](0215-ref-number-and-ref-title-as-reference.md) と [ADR 0217](0217-html-spaces-of-paragraph-styles-redefined-in-files.md) の実装（[#683](https://github.com/tett23/golem/pull/683)、[#677](https://github.com/tett23/golem/pull/677)）は、プロジェクトの手順の決まりから三つの点で外れた。
どれもマージ済みで、PR の説明にも書かれている。
メンテナーは、三つを記録に入れると決めた（2026-11-08）。
この ADR は、その記録である。

### テストを先に書いていない（[ADR 0215](0215-ref-number-and-ref-title-as-reference.md)）

プロジェクトの決まり（`CLAUDE.md`）は、ADR のテスト設計に書いたテストを先に書き、失敗させてから実装するとする。
#683 は、テストを実装と並べて書き、先に失敗させることを確かめていない。
テスト設計の項目のテストはあり、CI は通っている。
縦組み、行の途中で分かれる参照、ルビの親文字の中の参照は、テストしていない。
ルビの親文字の中の参照は、`Reference` にならない。

### ADR にない規則（[ADR 0215](0215-ref-number-and-ref-title-as-reference.md)）

#683 は、[ADR 0215](0215-ref-number-and-ref-title-as-reference.md) が書いていない規則を一つ足した。
プラグインの出力に、解決済みの参照のインラインの要素（`Resolved`、CBOR のタグ 22）があれば、G06009 で退ける（[`Validate.hs`](https://github.com/tett23/golem/blob/683744442737c02e86e700e26b6f1b9b95277aef/modules/golem-doc/src/Golem/Doc/Validate.hs#L164)）。
メッセージは「解決した参照は文書の組み立てだけが作ります」である。
`Resolved` は文書の組み立ての段階が作る要素で、プラグインが作るものではないので、出力に現れれば ABI の誤りとして扱う。
`withoutAnchors` が `Resolved` を中身へ溶かさずに残すことも、ADR に書かれていない判断である。

### パッケージをまたいでテストのコードを読む（[ADR 0217](0217-html-spaces-of-paragraph-styles-redefined-in-files.md)）

#677 は、golem-driver のテストのスイートの `hs-source-dirs` に `../golem-html/test` を足し、golem-html のテストの CSS の評価器（`CssCascade`）を golem-driver のテストから使えるようにした（[`golem-driver.cabal`](https://github.com/tett23/golem/blob/683744442737c02e86e700e26b6f1b9b95277aef/modules/golem-driver/golem-driver.cabal#L80-L85)）。
`build-depends` は変えていない。
プロジェクトの決まりは、golem のパッケージのあいだの `build-depends` の変更に ADR を求める。
ソースのディレクトリを共有するのは `build-depends` の変更ではないが、二つのパッケージのテストのあいだに、同じつながりを作る。

## 実装すること

- [ADR 0215](0215-ref-number-and-ref-title-as-reference.md) と [ADR 0217](0217-html-spaces-of-paragraph-styles-redefined-in-files.md) のステータスの行に、この ADR が記録したことを書く。
- `Golem.Doc.Validate` の G06009 の `Resolved` の枝と、`golem-driver.cabal` の `hs-source-dirs` の注釈に、この ADR を足す。
- docs/roadmap.md に、ルビの親文字の中の `[ref-number]` と `[ref-title]` が `Reference` にならないことを足す。

## 実装しないこと

- **テストを書き直すこと**：テスト設計の項目のテストはあり、通っている。
- **G06009 の規則を外すこと**：「メンテナーが決めること」の 1。
- **`CssCascade` を新しいパッケージに出すこと**：「メンテナーが決めること」の 2。

## 不変条件

なし。
すでに入った振る舞いと構成を記録する ADR であり、振る舞いを変えない。

## テスト設計

自動のテストは足さない。
実装のプルリクエストで、ステータスの行と注釈とロードマップの項目が書かれていることを確かめる。

## トレードオフ

テストを先に書かなかったことは、記録しても戻らない。
今のテストが実装に合わせて書かれ、実装の誤りを見逃している可能性は残る。
テストしていない三つの入力のうち、ルビの親文字の中の参照は、実際に `Reference` にならないことが分かっている。

ソースのディレクトリを共有すると、golem-html のテストの `CssCascade` を変えたときに、golem-driver のテストが壊れうる。
`build-depends` の検査（`scripts/ci/doc-deps.sh` と `test-only-deps.sh`）は、このつながりを見ない。

## メンテナーが決めること

1. **G06009 の `Resolved` の規則**：推奨は、このまま採ることである。プラグインが組み立ての段階の要素を作れば、組み立ての前提が崩れるので、出力の誤りとして退けるのがよい。
   - 退けた案は、規則を外して `Resolved` を通すことである。プラグインが偽の参照を作れる。
2. **パッケージをまたぐソースのディレクトリ**：推奨は、このまま認めることである。共有するのはテストのコードだけで、配布物には入らない。
   - 退けた案の一つは、`CssCascade` を golem-test-support に移すことである。golem-test-support は golem のパッケージに依存しないので移せるが、golem-html の内部の型を使うなら移せない。
   - もう一つは、golem-driver のテストに写すことである。同じコードを二か所に持つことになる。
   - 同じ形の共有が増えたら、検査のスクリプトに見させる ADR を作る。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-08、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [ADR 0215](0215-ref-number-and-ref-title-as-reference.md)、[ADR 0217](0217-html-spaces-of-paragraph-styles-redefined-in-files.md)、[ADR 0211](0211-record-what-implementations-decided-found-by-the-review-of-2026-11-08.md)、[ADR 0205](0205-rules-added-by-the-implementation-of-adr-0180.md)
- [#683](https://github.com/tett23/golem/pull/683)、[#677](https://github.com/tett23/golem/pull/677) の説明
