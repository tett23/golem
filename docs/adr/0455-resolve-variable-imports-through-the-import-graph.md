# ADR 0455: 変数のファイルの取り込みを取り込みのグラフで引き、マニフェストの無いファイルの評価では読み込めなかった `.emet` と同じく扱う

Status: proposed

## 文脈

[root ADR 0451](0451-import-listed-names-without-a-namespace.md) は、`@import パス { 名前, … }` で並べた名前が取り込む先に公開されていなければ、G02276 にすると決めた。
また、`.emet` のどれかを読み込めないときは、`.emet` から並べた名前の検査をせず、その呼び出しの誤りも報告しないと決めた（0451 の I8）。
誤りの元を `.emet` の側で一度だけ報告し、取り込む側で同じ原因から誤りを重ねないためである。

0451 の実装の後、変数のファイルについて、この扱いが無いことが分かった。
評価が変数のファイルの公開する変数の表を引けないとき、評価はそのファイルが変数を一つも公開していないと読み、並べたすべての名前を G02276 にする。
この場合の扱いを、0451 は決めていない。
メンテナーは、2026-11-26 に、この扱いを ADR で決めるよう求めた。

表を引けない場合を調べると、二つあった。
一つは、マニフェストの無いファイルの評価で、取り込みを解かない場合である。
もう一つは、プロジェクトの評価で、`@import` に書いたパスが正規化した形と違う場合である（`./common/v.gm` など）。
二つ目は、ファイルを読めているのに変数を失う誤りなので、表を取り込みのグラフで引くように直す。

## 調査した事項

origin/main（[3d8d5a9](https://github.com/tett23/golem/commit/3d8d5a9caf94abafc7b58980bc6aa656e4a2084b)）で、次のことを確かめた。

- 評価は、変数のファイルの公開する変数を、評価の文脈の `ctxImports` から、`@import` に書いたままのパスで引く。
  名前を並べた取り込みは、引けなかったとき空の表を使う（[File.hs#L716-L723](https://github.com/tett23/golem/blob/3d8d5a9caf94abafc7b58980bc6aa656e4a2084b/modules/golem-eval/src/Golem/Eval/File.hs#L716-L723)）。
  空の表には名前が無いので、並べた名前はどれも G02276 になる（[File.hs#L758-L768](https://github.com/tett23/golem/blob/3d8d5a9caf94abafc7b58980bc6aa656e4a2084b/modules/golem-eval/src/Golem/Eval/File.hs#L758-L768)）。
- 名前空間つきの取り込み（`* as ns`）も、書いたままのパスで引き、引けなかったとき空の表を名前空間に入れる（[File.hs#L643-L644](https://github.com/tett23/golem/blob/3d8d5a9caf94abafc7b58980bc6aa656e4a2084b/modules/golem-eval/src/Golem/Eval/File.hs#L643-L644)）。
- `.emet` の取り込みは、書いたパスを `normalizeRelative` で正規化してから引く（[File.hs#L716-L721](https://github.com/tett23/golem/blob/3d8d5a9caf94abafc7b58980bc6aa656e4a2084b/modules/golem-eval/src/Golem/Eval/File.hs#L716-L721)）。
- 取り込みのグラフは、ファイルごとに、取り込む先のファイルと、その `@import` の行（`ImportSite`）の組を持つ（[Imports.hs#L60](https://github.com/tett23/golem/blob/3d8d5a9caf94abafc7b58980bc6aa656e4a2084b/modules/golem-project/src/Golem/Project/Imports.hs#L60)）。
  プロジェクトの読み込みのパスの解決は、パスを正規化し、シンボリックリンクを解く（[Paths.hs#L36-L51](https://github.com/tett23/golem/blob/3d8d5a9caf94abafc7b58980bc6aa656e4a2084b/modules/golem-project/src/Golem/Project/Paths.hs#L36-L51)）。
  `normalizeRelative` は `.` と `..` を畳むだけで、シンボリックリンクを解かない。
- `ctxImports` を作るのは、プロジェクトの評価だけである。
  プロジェクトの評価は、取り込みのグラフにあるファイルの公開する変数を、プロジェクトが正規化したパスをキーにして入れる（[Evaluate.hs#L381-L395](https://github.com/tett23/golem/blob/3d8d5a9caf94abafc7b58980bc6aa656e4a2084b/modules/golem-evaluate/src/Golem/Evaluate.hs#L381-L395)）。
  マニフェストの無いファイルの評価（`evaluateLoose`）は、`ctxImports` を空にする（[Evaluate.hs#L416-L424](https://github.com/tett23/golem/blob/3d8d5a9caf94abafc7b58980bc6aa656e4a2084b/modules/golem-evaluate/src/Golem/Evaluate.hs#L416-L424)）。
  `evaluateLoose` は、言語サーバーがマニフェストの届かないファイルを開いたときと、`golem inspect --as ir` をマニフェストなしで動かしたときに使う。
- プロジェクトの中で `@import` の指すファイルが無いか、取り込みが循環するときは、プロジェクトの読み込みが G03002 か G03005 で止まり、評価に届かない（[Project.hs#L240-L242](https://github.com/tett23/golem/blob/3d8d5a9caf94abafc7b58980bc6aa656e4a2084b/modules/golem-project/src/Golem/Project.hs#L240-L242)）。
- 2026-11-26 にビルドした `golem`（`golem 0.1.0-rc4`、main の cad722820）で、`golem new` で作ったプロジェクトに `common/v.gm`（`@set price = 100`）を置き、`chapters/01.gm` を変えて `golem check` を動かした。
  フォントの無いことの G08002 のほかの diagnostic は、次のとおりだった。

  ```text
  @import common/v.gm { price } と [= price]            → なし
  @import ./common/v.gm { price } と [= price]          → G02002（未定義の名前 price です）、G02276（./common/v.gm が公開していない名前です: price）
  @import common/../common/v.gm * as v と [= v.price]   → G02002（未定義の名前 price です）
  ```

- 読み込めなかったか検査できなかった `.emet` は、`ftUnloaded` で表す。
  その `.emet` から並べた名前は、検査せず、呼び出しは何も報告しない（[File.hs#L758-L767](https://github.com/tett23/golem/blob/3d8d5a9caf94abafc7b58980bc6aa656e4a2084b/modules/golem-eval/src/Golem/Eval/File.hs#L758-L767)）。
  `evaluateLoose` には `.emet` の表も無いので、マニフェストの無いファイルの `.emet` の取り込みは、この扱いになる。
  同じ `golem` で、マニフェストの無いディレクトリで `golem inspect --as ir` を動かした結果は、次のとおりだった。
  取り込んだ名前を使う `@set` は変数を定義せず、その変数の参照は G02002 になる。
  変数のファイルの取り込みは、並べた名前が G02276 になる。

  ```text
  @import f.emet { total }、@set y = total(1)、[= y]、[= total(2)]  → G02002（未定義の名前 y です）
  @import v.gm { price } と [= price]                               → G02002（未定義の名前 price です）、G02276（v.gm が公開していない名前です: price）
  ```

## 実装すること

### 取り込みのグラフで引く

変数のファイルの公開する変数の表を、パスの文字列ではなく、取り込みのグラフで引く。
プロジェクトの読み込みは、`@import` の行ごとに、その行が指すファイルを決めている（パスの正規化とシンボリックリンクの解決を含む）。
プロジェクトの評価は、評価するファイルの `@import` の行ごとに、その行が指すファイルの公開する変数の表を、評価の文脈に渡す。
評価は、`@import` の行の表を、その行から引く。
名前を並べた取り込みと名前空間つきの取り込みの両方に当てはめる。

そのため、プロジェクトの評価では、取り込みのグラフにある変数のファイルの表は、`./`、`..`、シンボリックリンクを含む書き方によらず引ける。
仕様書の「ファイルはプロジェクトルートからの正規化パスで同一性を判定する」に、評価の引き方を合わせる。

### マニフェストの無いファイルの評価

マニフェストの無いファイルの評価は、変数のファイルの取り込みを解かない。
評価の文脈に、取り込みを解かないことを表す値を持たせ、`evaluateLoose` だけがその値を立てる。
表が無いことからは判断しない。

取り込みを解かない評価で変数のファイルを指す `@import` は、読み込めなかった `.emet` を指す `@import` と同じく扱う。

- 名前を並べた取り込みでは、予約語の検査（G02275）だけを行い、G02276 と 0451 の重なりの表のコードを出さない。
- 並べた名前の名前空間なしの式での参照（`[= price]`）と、名前空間つきの取り込みの式での参照（`[= v.price]`）は、何も報告しない。
  その参照を含む式は評価せず、その式のインラインは何も出力しない。
- その参照を含む式で `@set` した変数は定義されず、その変数の参照は、今の `.emet` の場合と同じく G02002 になる。
- コマンドの形の呼び出し（`[price …]`、`@v.price`）は、今と同じ diagnostic にする。

取り込みの理由で取り込む側に誤りを重ねないのは、マニフェストの無いファイルの評価が本を組む評価ではなく、言語サーバーと `golem inspect` の補助の表示に使うだけだからである。

プロジェクトの評価で、表を引けて、その表に名前が無いときは、今と同じく G02276 とする。

### 文書

仕様書の「定義の取り込み」の節で、`.emet` を読み込めないときの扱いの文に、マニフェストの無いファイルの評価での変数のファイルを足す。
マニフェストの無いファイルの評価の記述に、変数のファイルと `.emet` の取り込みを解かないことを書く。
`docs/diagnostics.md` の G02276 と G02002 の説明に、マニフェストの無いファイルの評価での例外を足す。

採択したら、0451 のステータスに `{"part":"名前が重なったとき","by":["docs/adr/0455-resolve-variable-imports-through-the-import-graph.md"],"kind":"supplement"}` を記録する。

## 実装しないこと

マニフェストの無いファイルの評価で、変数のファイルを読みに行くことはしない。
マニフェストの無いファイルの評価で、取り込みを解かないことを知らせる diagnostic は足さない（トレードオフ）。
取り込んだ名前を使って `@set` した変数の参照の G02002 は、`.emet` と変数のファイルのどちらでも変えない。
読んだが評価に誤りのあった変数のファイルの扱いは変えない（評価を終えた変数を公開する）。

## 不変条件

- I1: プロジェクトの評価で、同じ変数のファイルを、正規化した形と、`./`、`..`、シンボリックリンクを含む別の書き方で取り込んだ二つの原稿の diagnostics のコードの集合と出力は等しい。
- I2: 取り込みを解かない評価で、変数のファイルから並べた名前について、G02275 のほかの評価の diagnostic は、その `@import` の行に出ない。
- I3: 取り込みを解かない評価で、変数のファイルから取り込んだ名前の式での参照（名前空間なしと名前空間つき）は、diagnostic を出さない。
- I4: プロジェクトの評価で、正規化した形で書いた `@import` の diagnostics と出力は、この ADR の前と同じである。
- I5: 取り込みを解かない評価で、変数のファイルを指す `@import` の行と、その名前の式での参照の diagnostics のコードの集合は、同じ形で `.emet` を指す原稿のコードの集合と等しい。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| プロジェクトで `@import ./common/v.gm { price }` と `[= price]` | `common/v.gm` と書いたときと同じ。G02276 なし | I1 |
| プロジェクトで `@import common/../common/v.gm * as v` と `[= v.price]` | `common/v.gm` と書いたときと同じ | I1 |
| プロジェクトで、`common/v.gm` へのシンボリックリンク `link.gm` から `{ price }` | `common/v.gm` と書いたときと同じ | I1 |
| プロジェクトで、`price` を公開しない `common/v.gm` から `{ price }` | G02276（今と同じ） | I4 |
| マニフェストの無いファイルの `@import v.gm { price }` と `[= price]` | diagnostic なし | I2, I3 |
| マニフェストの無いファイルの `@import v.gm * as v` と `[= v.price]` | diagnostic なし | I3 |
| マニフェストの無いファイルの `@import v.gm { meta }` | G02275 だけ | I2 |
| マニフェストの無いファイルの `@import v.gm { price }`、`@set y = price`、`[= y]` | `[= y]` に G02002（`.emet` と同じ） | I5 |
| マニフェストの無いファイルの `@import f.emet { total }` と `[= total(1)]`、同じ形の変数のファイル | 同じコードの集合 | I5 |

プロジェクトで無いファイルを指す `@import` は、今と同じく G03002 で止まり、この ADR の扱いの外にある。

## 受けいれ条件

なし。
不変条件のテストで足りるためである。

## テスト設計

root ADR 0455 I1 から I5 を名前の先頭に置いたテストを足す。
golem-evaluate のテストで、`./`、`..`、シンボリックリンクを含む書き方と正規化した書き方のプロジェクトを評価し、I1 と I4 を確かめる。
golem-evaluate のテストで、`evaluateLoose` に表の入力を与え、I2、I3、I5 を確かめる。
I5 は、同じ原稿の `.emet` の取り込みと変数のファイルの取り込みの diagnostics のコードを比べて確かめる。
テストは、実装の前に書いて落ちることを確かめる。

## トレードオフ

マニフェストの無いファイルの評価では、取り込んだ変数の参照が黙って何も出力しない。
書き手は、取り込みが解かれていないことを diagnostic から知れない。
ただし、マニフェストの無いファイルの評価は、`.emet` の取り込みも同じく解かず、補助の表示に使うだけである。
本を組む評価はマニフェストを要するので、そこで取り込みは解かれる。
知らせる diagnostic を足すなら、`.emet` と変数のファイルの両方に、別の ADR で足す。

## 参考文献

- [root ADR 0451](0451-import-listed-names-without-a-namespace.md)
- [docs/adr/0162](0162-calling-emet-functions-from-gm.md)
- [docs/adr/0185](0185-project-wide-variables.md)
