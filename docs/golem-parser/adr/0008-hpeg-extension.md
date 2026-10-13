# ADR 0008: 文法ファイルの拡張子を .hpeg にする

ステータス: 採択

## 文脈

Golem の構文は、peg-hs の文法 `modules/golem-parser/grammar/Golem.peg` から生成している（[ADR 0002](0002-parser-on-peg-hs.md)）。
`scripts/gen-parser.sh` がこの文法から `Golem.Parser.Generated` と、ラベルを外した `StrippedGrammar` を作る（[ADR 0007](0007-grammar-label-safety.md)）。

拡張子 `.peg` は、C の peg/leg や Go の pointlander/peg など、ほかの PEG の道具も使っている。
記法はどれも別物で、互換はない。
拡張子が重なると、エディタと GitHub の言語の判定が別の道具の文法と取り違える。
peg-hs の `fmt` と `lint` も、探索で見つけたほかの道具の `.peg` を peg-hs の文法として読んでしまう。

peg-hs は、この重なりを避けるため、文法ファイルの拡張子を `.hpeg` に改めた（[peg-hs ADR 0050](https://github.com/tett23/peg-hs/blob/7fc4bcb372d0/docs/adr/0050-hpeg-extension.md)）。
同じ ADR で、`peg-hs fmt` と `peg-hs lint` が引数なしやディレクトリの指定で探すのは `.hpeg` だけになった。
直接渡したファイルは拡張子を見ないので、`peg-hs gen Golem.peg` は今後も動く。
それでも、エディタの言語の判定と peg-hs の道具の探索から外れないように、Golem の文法も `.hpeg` に改める。

生成したモジュールは、文法のパスを行の番号の指示（`{-# LINE ... "modules/golem-parser/grammar/Golem.peg" #-}`）として記録する。
`Generated.hs` には 612 か所、`StrippedGrammar.hs` には 617 か所ある。
パスを変えると、この二つの生成物も変わる。

## 実装すること

### 文法ファイル

- `modules/golem-parser/grammar/Golem.peg` を `modules/golem-parser/grammar/Golem.hpeg` に改める（`git mv`）。中身は変えない。
- `scripts/gen-parser.sh` の二つの `peg-hs gen` が読むパスを `Golem.hpeg` に改め、`Generated.hs` と `StrippedGrammar.hs` を生成し直してコミットする。変わるのは行の番号の指示のパスだけである。
- `modules/golem-parser/test/ParserSpec.hs` が文法を読むパス（`grammar/Golem.peg`）を `grammar/Golem.hpeg` に改める。

### peg-hs の版

peg-hs の版は上げない。
今の固定のコミット（`cabal.project` の 7114641）の `peg-hs gen` は、ファイルを直接渡せば拡張子を見ないので、`.hpeg` の文法を読める。
peg-hs の版を上げるときは、[ADR 0002](0002-parser-on-peg-hs.md) と [ADR 0007](0007-grammar-label-safety.md) のとおり、別の変更として行う。

### 文書

- README の「ビルドとテスト」の節と、CONTRIBUTING.md と CONTRIBUTING.en.md の「整形と検査」の節の、文法のパスを `Golem.hpeg` に改める。
- 仕様書（docs/specifications.md）に文法のパスを書いた箇所があれば改める。
- コミット済みの ADR は変えない。[ADR 0002](0002-parser-on-peg-hs.md)、[ADR 0007](0007-grammar-label-safety.md)、[docs/adr/0005](../../adr/0005-character-and-paragraph-styles.md) などが書いている `Golem.peg` は、それぞれの ADR を採択した時点のパスとして残す。

## 実装しないこと

- 文法の中身の変更。
- peg-hs の版を上げること。
- エディタの設定（VS Code、Neovim）をこのリポジトリに置くこと。
- `.peg` のファイルを探索から外すための仕組みを Golem の側に持つこと。Golem のリポジトリには、ほかの道具の `.peg` はない。

## テスト設計

- 文法のパスを変えた後で、`CABAL=cabal-3.16.1.0 scripts/gen-parser.sh` が警告なしで終わり、生成し直した `Generated.hs` と `StrippedGrammar.hs` の差分が、行の番号の指示のパスだけであることを確かめる（`git diff` で `Golem.peg` が `Golem.hpeg` に替わった行のほかに差分がないこと）。
- `cabal-3.16.1.0 test all` が通ること。とくに、文法を読む golem-parser のテスト（`labelCode` の対応表の検査）と、ラベルを外した文法との比較のテストが通ること。
- CI の「Generated parser matches the grammar」の段で、生成物が文法と一致すること。
- リポジトリに `.peg` の拡張子のファイルが残っていないことを、`git ls-files '*.peg'` が空であることで確かめる。

## トレードオフ

生成物の 1,229 か所の行が、パスの文字列の分だけ変わる。
差分は大きいが機械的であり、文法の中身が変わらないことは、差分がパスだけであることで確かめる。

コミット済みの ADR に古いパスが残る。
ADR はコミットした時点の決定の記録であり、書き換えない規約なので、古いパスのまま読む。
今のパスは README、CONTRIBUTING、この ADR で分かる。
