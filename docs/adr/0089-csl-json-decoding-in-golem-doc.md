# ADR 0089: CSL-JSON の項目の読み取りを golem-doc に移す

ステータス: 採択

## 文脈

参考文献の書誌は、manifest の `bibliography` に挙げた CSL-JSON のファイルから読む。
読む処理は golem-driver の `Golem.Driver` にあり、三つの関数からなる。

- [`loadBibliography`](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-driver/src/Golem/Driver.hs#L546-L569)：manifest のパスをプロジェクトのルートの中に解決し、ファイルを読み、aeson の `eitherDecode` で JSON にし、配列の各要素を `cslEntry` で読む。読めないファイルは G03026 か G03003 にする。
- [`cslEntry`](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-driver/src/Golem/Driver.hs#L571-L640)：aeson の `Value` から golem-doc の `CslEntry` を作る。どの欄をどう読むかは [golem-doc ADR 0004](../golem-doc/adr/0004-bibliography-formatting.md) と [golem-doc ADR 0005](../golem-doc/adr/0005-bibliography-fields.md) が決めている。
- [`cslYear`](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-driver/src/Golem/Driver.hs#L642-L657)：CSL-JSON の数を年の整数にする（[ADR 0035](0035-security-hardening.md)）。

書誌の型 `CslEntry` と書式 `formatEntry` は golem-doc の [`Golem.Doc.Bibliography`](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-doc/src/Golem/Doc/Bibliography.hs) にある。
読み取りだけが golem-driver に残ったのは、[golem-doc ADR 0004](../golem-doc/adr/0004-bibliography-formatting.md) が「golem-doc は aeson に依存しないので、JSON の読み込みは golem-driver に残し、書式だけを golem-doc に移す」と決めたからである（[golem-doc ADR 0004 の 32 行目](../golem-doc/adr/0004-bibliography-formatting.md)）。
[golem-doc ADR 0005](../golem-doc/adr/0005-bibliography-fields.md) も、読み方の節を「CSL-JSON の読み方（golem-driver）」としている。
[2026-10-25 のリファクタリングの調査](../audits/2026-10-25-refactoring-survey.md) の R4 は、この配置を見直す対象に挙げた。

コードを読むと、三つの関数は二種類に分かれる。
`cslEntry` と `cslYear` は、JSON の値から書誌の値への純粋な写像で、golem-doc の型だけを作る。
`loadBibliography` は、manifest（golem-project の `Manifest`）と、プロジェクトのルートの中にパスを解決する golem-project の `resolveInRoot` を使い、ファイルを読む IO を持つ。
golem-project は golem-doc に依存しているので、`loadBibliography` を golem-doc に移すと閉路になる。
移せるのは、純粋な写像のほうだけである。

golem-driver で aeson を使うのは、この三つの関数だけである。
`Data.Aeson`、`Data.Aeson.Key`、`Data.Aeson.KeyMap`、`Data.Scientific` を import するのは `Golem.Driver` だけで（[aeson の import](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-driver/src/Golem/Driver.hs#L46-L48)、[`Data.Scientific` の import](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-driver/src/Golem/Driver.hs#L58)）、`Golem.Driver` の中でそれらを使うのは 546 行目から 657 行目の三つの関数だけである。
`Data.Vector` は `Golem.Driver.Memo` も使う（[Memo.hs](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-driver/src/Golem/Driver/Memo.hs#L23)）。

読み取りの規則は、今は golem-driver の `ReferencesSpec` が、プロジェクトを一時ディレクトリに書いて組む形でしか確かめていない（[ReferencesSpec.hs](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-driver/test/ReferencesSpec.hs#L177-L188)）。

## 実装すること

`cslEntry` と `cslYear` を golem-doc に移し、JSON の文字列から書誌の項目の列を作る純粋な関数を golem-doc に足す。
ファイルを探して読み、diagnostic を作る処理は golem-driver に残す。

### golem-doc の新しいモジュール

`Golem.Doc.Bibliography.Csl` を足し、次を公開する。

- `data CslJsonError = CslNotJson String | CslNotArray`：JSON として読めないこと（aeson の文言を持つ）と、最上位が配列でないこと。
- `decodeCslJson :: BL.ByteString -> Either CslJsonError [CslEntry]`：`eitherDecode` が失敗すれば `CslNotJson` に文言を入れて返す。最上位が配列なら、各要素に `cslEntry` を当て、`Nothing` を除いた列を返す。配列でなければ `CslNotArray` を返す。
- `cslEntry :: Value -> Maybe CslEntry` と `cslYear :: Scientific -> Maybe Integer`：今の本体をそのまま移す。

`Golem.Doc.Bibliography`（書式）は aeson を import しないままにする。
書式のモジュールが JSON のライブラリを知らずに済み、読み取りの規則と書式の規則の変更が別のモジュールに収まるからである。

### golem-driver の変更

- `loadBibliography` は、パスの解決、ファイルの読み込み、diagnostic の作成を今のまま持ち、読んだバイト列を `decodeCslJson` に渡す。
- `CslNotJson err` は今の `Right (Left err)` の枝と同じく `参考文献のファイルを JSON として読めません: <パス>（<err>）` に、`CslNotArray` は `参考文献のファイルは CSL-JSON の配列で書きます: <パス>` にする。文言とコード（G03026）は変えない。
- `cslEntry` と `cslYear` の定義と、aeson、`Data.Scientific`、`Data.Vector` の import を `Golem.Driver` から消す。`loadBibliography` の型と export は変えない。

### build-depends の変更

| パッケージ | 部品 | 変更 |
| --- | --- | --- |
| golem-doc | library | `aeson >=2.1 && <2.3`、`scientific >=0.3 && <0.4`、`vector >=0.13 && <0.14` を足す。`exposed-modules` に `Golem.Doc.Bibliography.Csl` を足す |
| golem-doc | golem-doc-test | `scientific` を足す（`cslYear` のテストのため） |
| golem-driver | library | `aeson` と `scientific` を消す。`vector` は `Golem.Driver.Memo` が使うので残す |
| golem-driver | テストスイート | 変えない |

版の範囲は、今の golem-driver の範囲（[golem-driver.cabal](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-driver/golem-driver.cabal#L43)、[66 行目](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-driver/golem-driver.cabal#L66)、[70 行目](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-driver/golem-driver.cabal#L70)）をそのまま使う。
golem のパッケージのあいだの依存は変わらない。

### 依存のグラフ

golem のパッケージのあいだの辺は変わらないので、閉路は生じない。
変わるのは Hackage のパッケージへの辺である。

```
前：golem-doc     → golem-parser, golem-syntax, base, bytestring, cborg, containers, mtl, text
    golem-driver  → （golem の 16 のパッケージ）, aeson, scientific, vector, ...
後：golem-doc     → golem-parser, golem-syntax, base, bytestring, cborg, containers, mtl, text, aeson, scientific, vector
    golem-driver  → （golem の 16 のパッケージ）, vector, ...
```

golem の実行ファイルの依存の閉包には、aeson、scientific、vector がもともと入っている。
golem-lsp のライブラリが aeson に依存し（[golem-lsp.cabal](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/modules/golem-lsp/golem-lsp.cabal#L22)）、golem-cli の実行ファイルが golem-lsp に依存するからである。
したがって、リンクされる Hackage のパッケージの集合と、`scripts/release/licenses.sh` が集めるライセンスの一覧は変わらない。

### 出力が変わらない理由

- 本体を移すだけで、関数の中身は変えない。
- aeson の版とフラグ（`+ordered-keymap`）は `cabal.project.freeze` がプロジェクト全体で固定している（[cabal.project.freeze](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/cabal.project.freeze#L14-L15)）。依存するパッケージが golem-driver から golem-doc に替わっても、使う aeson は同じである。`eitherDecode` の失敗の文言も同じになる。

### 文書

- [golem-doc ADR 0004](../golem-doc/adr/0004-bibliography-formatting.md) のステータスの行を「採択→CSL-JSON の読み取りの置き場は [ADR 0089](../../adr/0089-csl-json-decoding-in-golem-doc.md)」に、[golem-doc ADR 0005](../golem-doc/adr/0005-bibliography-fields.md) のステータスの行を「採択→CSL-JSON の読み方の置き場（golem-driver）は [ADR 0089](../../adr/0089-csl-json-decoding-in-golem-doc.md)」に改める。
- `manual-dev/part2/07-modules.gm` のモジュールの一覧の golem-doc の行（[22 行目](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/manual-dev/part2/07-modules.gm#L22)）に、「参考文献の CSL-JSON の読み取りと書式」を加える。
- `docs/specifications.md` の参考文献の節は、どのモジュールが読むかを書いていないので変えない。モジュール構成の図も、golem のパッケージのあいだの辺が変わらないので変えない。
- `manual-dev/part2/12-purity.gm` の、IO を持つ関数の列挙は golem-doc を挙げておらず、移した関数は純粋なので、変えない。

## 実装しないこと

- `loadBibliography` を golem-doc に移すこと。golem-project の型と関数を使うので、閉路になる。
- 読み取りの規則（どの欄をどう読むか）と、G03026 の文言の変更。
- CSL-JSON の文字列に含まれる制御文字の検査。ロードマップの rc4 の「CSL-JSON の制御文字」の項目で、どこで拒むかを含めて決める。この ADR の後なら、`decodeCslJson` が候補の一つになる。
- golem-lsp の aeson の使い方の変更。

## テスト設計

### 先に書くテスト

golem-doc のテストに `CslSpec` を足す。
`Golem.Doc.Bibliography.Csl` がないので、コンパイルが失敗する。

- `decodeCslJson "{"` は `Left (CslNotJson _)` で、文言は aeson の `eitherDecode` が同じ入力に返す文言と同じである。
- `decodeCslJson "{}"` と `decodeCslJson "1"` は `Left CslNotArray` である。
- `decodeCslJson "[]"` は `Right []` である。
- `id` が文字列でない要素と、オブジェクトでない要素は除かれ、残りは元の順に並ぶ。
- 欄の読み方は [golem-doc ADR 0005](../golem-doc/adr/0005-bibliography-fields.md) の「CSL-JSON の読み方」のとおりである。`type`、`container-title`、`URL` を文字列のときに読む。`volume`、`issue`、`page` は文字列か整数を読み、整数は十進の文字列にし、`12.5` は読まない。`date-parts` の月がなければ日も読まない。`literal` の日付を読む。空白だけの文字列は欄がないものとして扱う。名前は `literal` を先に読み、`family` も `given` もない名前は除く。
- `cslYear` は、10 の 15 乗以上で `Nothing`、0.1 未満で `Just 0`、`1999.6` で `Just 2000`、`1e1000000000` で `Nothing` を返す。`1e1000000000` は [ADR 0035](0035-security-hardening.md) のテストと同じ値で、桁を展開せずにすぐ返ることを、時間の上限（10 秒）で確かめる。

### 移した後の確かめ

- golem-doc-test と golem-driver-test が通る。golem-driver-test の `ReferencesSpec` は、変更の前と後で `--list-tests` の出力も結果も同じである。
- `rg -n 'Data.Aeson|Data.Scientific' modules/golem-driver/src` が何も返さない。
- `cabal build all` が、golem-driver の build-depends から aeson と scientific を消した状態で通る。

### 出力が変わらないことの確かめ

- golem-driver の `OutputGoldenSpec` が通る。ただし、この四つのダンプの入力（sample と figures）は参考文献を持たないので、読み取りの経路は通らない。
- ベースのコミットと変更後のコミットでそれぞれ golem をビルドし、`GOLEM=<その golem> sh scripts/determinism.sh` の出力の一覧を取って `diff` し、差がない。一覧には二つのマニュアルの出力が入り、どちらも manifest に `bibliography = ["references.json"]` を持つ（[manual](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/manual/manifest.toml#L25)、[manual-dev](https://github.com/tett23/golem/blob/48dd0756f6dc59e84d645130953508f8090b7707/manual-dev/manifest.toml#L24)）。読み取りの経路は、この一覧で確かめられる。
- 計画で、`golem-cli:exe:golem` から辿れる Hackage のパッケージの集合が変わらないことを確かめる。

## トレードオフ

- golem-doc の依存に aeson が入る。golem-doc は golem-project、golem-eval、golem-html、golem-text、golem-epub、golem-layout、golem-plugin などの下にあるので、何もない状態からのビルドでは、これらがすべて aeson のビルドを待つ。今は aeson を golem-doc などと並行にビルドできている。CI は依存のパッケージをキャッシュするので、ふだんのビルドの時間はほとんど変わらないはずだが、キャッシュがないときの時間は延びる可能性がある。
- 読み取りの規則のテストを、プロジェクトを組まずに golem-doc の中で書ける。今は欄を一つ確かめるにも、一時ディレクトリにプロジェクトを書いて組む必要がある。
- 読み取りを golem-driver に残し、`Golem.Driver.Bibliography` のようなモジュールに切り出すだけの案もある。依存は変わらず、[golem-doc ADR 0004](../golem-doc/adr/0004-bibliography-formatting.md) の決定もそのまま保てる。ただし、[golem-doc ADR 0005](../golem-doc/adr/0005-bibliography-fields.md) が決めた読み方の規則が golem-doc の外に残り、`CslEntry` を作る処理とその型が別のパッケージに分かれたままになる。
- [golem-doc ADR 0004](../golem-doc/adr/0004-bibliography-formatting.md) が golem-driver に残した理由は「golem-doc は aeson に依存しない」ことだけで、依存を避けるべき理由は書いていない。この ADR はその前提を変える。

## 参考文献

- [2026-10-25 のリファクタリングの調査](../audits/2026-10-25-refactoring-survey.md) の R4
- [golem-doc ADR 0004](../golem-doc/adr/0004-bibliography-formatting.md)、[golem-doc ADR 0005](../golem-doc/adr/0005-bibliography-fields.md)、[ADR 0035](0035-security-hardening.md)
- aeson：https://hackage.haskell.org/package/aeson
- CSL-JSON の仕様：https://citeproc-js.readthedocs.io/en/latest/csl-json/markup.html
