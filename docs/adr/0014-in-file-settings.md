# ADR 0014: .gm の中に、そのファイルにだけ効く設定とスタイルを書く

ステータス: 採択→正規表現スタイルの意味と G0254 の廃止は [docs/adr/0015](0015-regex-styles.md)

## 文脈

[docs/adr/0013](0013-paragraph-separator.md) は、段落の区切り方（`paragraph-separator`）をマニフェストの `[source]` の節と章の項目で選べるようにした。
和文の章と欧文の章が混ざる本では、章の項目に書けばファイルごとに様式を変えられる。

それでも、設定をファイルの中に書きたい場面が残る。

- 原稿の読み方は、原稿のテキストの性質である。一行一段落で書いたファイルを別のプロジェクトに移すと、マニフェストの章の項目を書き写さない限り、段落が一つにつながる。
- `@import` でだけ参照されるファイルと、プロジェクトの外のファイル（LSP が S0 だけを評価するファイル）には、章の項目がない。
- ファイルを開いた人が、そのファイルの改行の意味を、マニフェストを見ずに知れない。

スタイルにも同じ事情がある。
文字スタイルと段落スタイルは、`style.toml` の `[character-styles.*]` と `[paragraph-styles.*]` にだけ定義できる（[docs/adr/0005](0005-character-and-paragraph-styles.md)）。
一つの章でだけ使う見た目（章の中に引いた手紙の段落、付録の用語の文字など）も、本の全体に効く `style.toml` に名前を足すことになる。
`style.toml` には一度しか使わない名前が増え、その章を別の本に移すと定義が付いてこない。
InDesign でも、スタイルは文書ごとに持ち、ある文書のスタイルを別の文書に読み込んで使う。

段落スタイルの中で、正規表現に一致した文字に文字スタイルを当てる機能（InDesign の正規表現スタイル、英語版の GREP スタイル）は、まだ Golem にない。
[仕様書](../specifications.md)は、「v2 以降に回した事項」の「段落スタイルの拡張」に「先頭文字スタイルと正規表現スタイル」を挙げていた。
この ADR で、正規表現スタイルを v1 の項目に移す。
正規表現スタイルも、特定の章の固有名や数字にだけ当てたいことが多く、ファイルの中で定義できる必要がある。

そこで、ファイルの中で、マニフェストの設定の一部の上書きと、そのファイルにだけ効くスタイルの定義を書けるようにする。

### 上書きできるマニフェストの範囲

仕様書は、初期の設計にあった `--- ... ---` によるファイル先頭のメタデータを廃止し、メタデータをマニフェストに一元化すると決めている（[仕様書](../specifications.md)の「意図的に採用しなかったもの」の「ソースファイルのプリアンブル」）。
書名、著者、`id`、出力ターゲットは本の全体で一つの値であり、ファイルごとに変わると、どのファイルの値を成果物に書くかが決まらないためである。

この決定は保つ。
上書きできるのは、[docs/adr/0013](0013-paragraph-separator.md) で設けた `[source]` の節のキーに限る。
`[source]` は、一つのファイルの読み方を決める設定だけを置く節であり、章の項目で上書きできるキーと同じ集合である。
今のキーは `paragraph-separator` だけである。

ほかの候補は次の理由で外した。

- `language`：`[metadata]` の値であり、PDF の XMP と EPUB のパッケージ文書に一つだけ書く本の属性である。章ごとの言語（HTML の `lang` 属性など）は意味論 IR と各媒体の出力に新しい欄が要り、上書きの仕組みとは別に設計する。
- 組み方向（`writing-mode`）：マニフェストではなく `style.toml` の `[page]` の値であり、レイアウト IR が版面ごとに持つ。一冊の中で組み方向を変えるには、マスターページと版面の側の設計が要る。
- `id`、書名、著者、日付、出力ターゲット、プラグインとフィルタの宣言：本の全体で一つの値である。フィルタはマニフェストでファイルごとに宣言できるが、ファイルの中で宣言できると、プラグインを宣言した場合だけ原稿の意味が変わるという規則（[仕様書](../specifications.md)の「プラグイン」）の検査が、マニフェストだけでは済まなくなる。

### ファイルの中で定義できるスタイルの範囲

ファイルの中で定義できるのは、文字スタイル、段落スタイル、正規表現スタイルの三つに限る。
`style.toml` のほかの節は、本の全体で一つの資源か、版面の設計である。

- `[fonts]`：PDF に埋め込むフォントは本の全体で一度だけ読み込み、HTML と EPUB ではフォントのファイルを成果物に写す。ファイルの中で役割を足すと、どのファイルを評価したかで読み込むフォントが変わる。ファイルの中のスタイルの `font` は、`[fonts]` にある役割だけを指せる。
- `[color.swatches]`：スウォッチは出力インテントに束縛した色である。ファイルの中のスタイルの `color` は、`[color.swatches]` にあるスウォッチだけを指せる。
- `[page]`、`[headings.*]`、`[composition]`、`[masters.*]` など：版面と見出しの番号、行分割の設定であり、本の全体で一つの値である。

### 記法の候補

マニフェストの上書きは、次の三つを比べた。

- ファイルの先頭のフロントマター（`---` で囲んだ TOML）：マニフェストと同じ書き方で書けるが、仕様書が廃止したプリアンブルの記法を戻すことになる。文法に新しい規則が要り、今は段落の地の文である `---` の行の解釈が変わる。CST の中に TOML を持つので、整形と LSP の位置の扱いも二重になる。
- `@set` と同じ形の専用の文法（`@manifest paragraph-separator = "line"`）：`@set` は `SetIdent` の専用の規則で解析している（`Golem.peg` の `BlockCommand`）。同じ形を別の名前で許すには文法を変える必要がある。
- キーワード引数を取るブロックコマンド（`@manifest paragraph-separator=line`）：今のブロックコマンドの文法で解析できる。キーワード引数の規則（[golem-parser ADR 0004](../golem-parser/adr/0004-inline-grammar.md)）、整形の規則、LSP の位置の扱いをそのまま使える。

ブロックコマンドの形を採る。
文法を変えないので、構文解釈の安定（コマンドの定義によらず解析が決まること）にも触れない。

スタイルの定義は、次の四つを比べた。

- `@manifest` を広げる（`@manifest paragraph-styles.letter.indent=1zw`）：`manifest.toml` の上書きと `style.toml` の定義が一つの名前に混ざる。キーが節の名前、スタイルの名前、欄の名前を点でつないだ形になり、一つのスタイルの欄が複数の引数に散る。
- 本体に TOML を書く（`@style-def` の下に 2 つ深くインデントした `[paragraph-styles.letter]` の表）：ブロックコマンドの本体は Golem のブロックとして解析するので、`[` で始まる行はインラインの要素になる。本体を TOML として読むには文法を変える必要がある。
- 種類ごとのブロックコマンド（`@paragraph-style letter indent=1zw`、`@character-style term font=gothic`）：[docs/adr/0005](0005-character-and-paragraph-styles.md) は、段落スタイルを付けるコマンドの候補として `@paragraph-style 名前` を検討して外した。同じ綴りで定義を書くと、段落スタイルを付けるコマンドと読み違える。
- 一つのブロックコマンドで種類を位置引数にする（`@style-def paragraph letter indent=1zw`）：今の文法で解析できる。`@style`（スタイルを付ける）と `@style-def`（スタイルを定義する）は綴りで区別がつく。種類の語 `character` と `paragraph` は、`style.toml` の節の名前（`character-styles`、`paragraph-styles`）に対応する。

`@style-def` を採る。

### `@manifest` と `@style-def` を分ける

二つを一つのコマンドにはしない。

- 上書きする先が違う。`@manifest` は `manifest.toml` の `[source]` の値を上書きし、`@style-def` は `style.toml` のスタイルを足すか上書きする。
- 値の検査が違うモジュールにある。`[source]` のキーの表は golem-parser の `Golem.Parser.SourceSettings`（[docs/adr/0013](0013-paragraph-separator.md)）に、スタイルの欄の検査は golem-project の `Golem.Project.Style` にある。
- 一つのコマンドが一つの設定ファイルに対応すれば、診断のメッセージから直す先のファイルを示せる。

置き場所の規則は共有する。
どちらもファイルの先頭に置く「ファイルの設定」のコマンドとし、先頭の並びの中では順序を問わない。

### 同じ名前の扱い

ファイルの中では、新しい名前のスタイルを定義でき、`style.toml` と組み込みのスタイルと同じ名前の定義を上書きできる。
上書きは、そのファイルの中でだけ効く。

上書きを禁じ、新しい名前だけを許す案も比べた。
`@style quote` の意味がファイルによって変わらず、`style.toml` を読めばどの章の `quote` の見た目も分かる。
一方で、一つの章だけ本文（`body`）の字下げを変えるような用途では、その章のすべての段落に新しい名前の `@style` を付けることになる。
後から `style.toml` に同じ名前を足すと、その名前を定義していたファイルがすべてエラーになる。
InDesign でも、文書ごとに同じ名前のスタイルが別の定義を持つ。
上書きを許す。

上書きの意味は、[docs/adr/0005](0005-character-and-paragraph-styles.md) の、`style.toml` の定義が組み込みの定義を上書きする規則と同じにする。
ファイルの中の定義に書いたキーだけが、`style.toml` の同じ名前の定義（組み込みの定義に `style.toml` を重ねたもの）の同じキーを上書きする。
書かなかったキーは、`style.toml` の定義の値を保つ。
たとえば `@style-def paragraph body indent=1zw` は、そのファイルの `body` の字下げだけを変え、書体と `line-breaks` は `style.toml` の `body` のままにする。

同じ名前の定義は、三つの層で一つに決まる。

| 層 | 同じ名前の定義が二つあるとき |
|---|---|
| 組み込みと `style.toml` | `style.toml` の定義が上書きする（[docs/adr/0005](0005-character-and-paragraph-styles.md)） |
| `style.toml` の中 | TOML の誤り。`[paragraph-styles.quote]` の表を二度書くと、TOML の解析器（toml-parser 2.0.2.0 の `Toml.Semantics`）が `ClosedTable` か `AlreadyAssigned` の誤りを返し、今の `decodeStrict` が G0306（`TOML の誤りです`）とする。新しい検査は要らない |
| `style.toml` とファイルの中 | ファイルの中の定義が、そのファイルの中でだけ上書きする |
| 同じファイルの中 | G0253。後勝ちにしない |

`based-on` の名前は、そのファイルから見た定義で解決する。
そのファイルの `Style` は、`style.toml` の定義にファイルの中の定義を重ねたものであり、`based-on` をたどる鎖のどの名前も、上書きがあれば上書きした後の定義を指す。

- `style.toml` の `quote` が `based-on = "body"` で、ファイルの中で `body` を上書きすると、そのファイルの `quote` は上書きした `body` を引き継ぐ。`style.toml` の `quote` は書き直さなくてよい。
- 上書きした定義の `based-on` に、自分の名前は書けない。上書きしたキーのほかは `style.toml` の同じ名前の定義の値を保つので、自分を基準にして `style.toml` の定義を引き継ぐ必要がない。自分の名前を書くと、ほかの循環と同じく G0313 とする。
- `based-on` を書かない上書きは、`style.toml` の同じ名前の定義の `based-on` を保つ。
- 循環は、そのファイルから見た定義の全体で検査する。`style.toml` の `a` が `based-on = "b"` のとき、ファイルの中で `b` を `based-on=a` で上書きすると、そのファイルで循環になり G0313 とする。
- `body` の上書きにも、`based-on` は書けない（G0313）。`style.toml` の `body` と同じ規則である。

`based-on` には、`style.toml` のスタイルと、同じファイルの中で定義したスタイルのどちらも書ける。
文字スタイルと段落スタイルは別の名前の空間であり、`style.toml` と同じく、同じ名前の文字スタイルと段落スタイルを定義してよい。

正規表現スタイルは名前を持たない。
InDesign の正規表現スタイルは、段落スタイルの中の、正規表現と文字スタイルの組の並びである。
ファイルの中の正規表現スタイルは、段落スタイル（`style.toml` のものでもよい）に組を足すものであり、上の名前の規則は当てはまらない。

### 正規表現スタイルの範囲

正規表現スタイルは v1 で実装する。
この ADR で決めるのは、ファイルの中の正規表現スタイルの記法と効く範囲だけである。
正規表現スタイルそのものの意味は、v1 の別の ADR で決める。
その ADR では次のことを決める。

- 段落スタイルのどの欄に置くか、`based-on` で組の並びを引き継ぐか。
- 正規表現の方言（Unicode の文字クラスの扱い、和文の文字の範囲の書き方）と、ルビ、圏点、縦中横、散文スロットをまたぐ一致の扱い。
- 決定性（一致の重なりの解決の順）と性能（正規表現のエンジンを再実装するか、依存に入れるか）。

その ADR を実装するまでの暫定の扱いとして、`@style-def regex` はエラーにする（[仕様書](../specifications.md)の「雑誌級のレイアウトエンジン」と同じく、未実装の機能に出会ったら黙って無視しない）。
記法の形を先に決めておくのは、ファイルの設定の並びの規則と LSP の補完を、正規表現スタイルを加えるときに作り直さないためである。

### 構文解析との順序

上書きと定義は、構文解析の後、評価のときに読めばよい。
[docs/adr/0013](0013-paragraph-separator.md) は、段落の区切り方を構文の層ではなく評価の層で扱うと決めた。
スタイルの名前と定義も、今の評価が `ctxCharStyles` と `ctxParaStyles` で検査している（[docs/adr/0005](0005-character-and-paragraph-styles.md)）。
構文の層で様式を切り替える設計なら、ファイルの先頭の上書きを構文解析の前に読む段階が必要になり、上書きの行を解析するための別の小さな解析器を持つことになっていた。

## 実装すること

### 記法

```
@manifest paragraph-separator=line
@style-def paragraph letter based-on=body indent=2zw first-line-indent=0zw
@style-def character sender font=gothic
%% 正規表現スタイル（別の ADR で実装するまではエラー） %%
%% @style-def regex letter pattern="[0-9]+" style=sender %%

「おい地獄さ[ruby: 行 | え]ぐんだで！」
@style letter
拝啓[style sender: 浅川]殿
```

`@manifest`：

- 引数は、キーワード引数だけである。キーは `[source]` のキーであり、値は語（`line`）か文字列（`"line"`）で書く。

`@style-def`：

- 最初の位置引数は種類であり、`character`（文字スタイル）、`paragraph`（段落スタイル）、`regex`（正規表現スタイル）のどれかである。
- `character` と `paragraph` の二つ目の位置引数は、定義するスタイルの名前である。名前の規則は `style.toml` と同じく `[a-z][a-z0-9-]*` である。
- `regex` の二つ目の位置引数は、組を足す段落スタイルの名前である。
- 位置引数の後に、キーワード引数でスタイルの欄を書く。キーは `style.toml` の `[character-styles.<名前>]`、`[paragraph-styles.<名前>]` と同じである。正規表現スタイルのキーは、正規表現スタイルの ADR が `style.toml` に設ける一つの組のキーと同じにする。
- 一つのスタイルは一行で定義する。同じ名前を二つの `@style-def` に分けて書くことはできない。

### ファイルの設定の並び

- `@manifest` と `@style-def` は、ファイルの最初のブロックとして置く。二つは任意の順に並べてよく、どちらも複数の行に分けて書いてよい。ファイルの先頭から続く `@manifest` と `@style-def` の行の並びを、ファイルの設定とする。コメントと空行は、ファイルの設定の前と途中に置いてよい。
- ファイルの設定の直後には、空行を挟まずにほかのブロックを書いてよい。今の文法では、空行を挟まないブロックコマンドの行と直後のブロックが一つの属性のまとまり（`NAttributed`）になるが、評価が先頭のファイルの設定をまとまりから外す（「評価」の節）。改行の様式の原稿で、空行を求めないためである。
- `@import` と `@set` は、ファイルの設定の後に書く。

### 値の読み方

`@manifest` の値は、語と文字列のどちらも文字列として `sourceKeys` に渡す。

`@style-def` の値は、`style.toml` の TOML の値として読む。
引用符で囲む TOML の書き方に合わせ、次の規則で TOML の値に写す。

| 原稿の値 | TOML の値 | 例 |
|---|---|---|
| 文字列（`"..."`） | 文字列 | `font="gothic"`、`synthetic-bold="true"`（文字列なので型の誤り） |
| 語 `true`、`false` | 真偽値 | `synthetic-bold=true` |
| `-?[0-9]+` に合う語 | 整数 | `space-between=1` |
| ほかの語 | 文字列 | `indent=2zw`、`first-line-indent=-1zw`、`line-breaks=keep` |

写した値の表を、`style.toml` と同じ `FromValue` のインスタンスで読む。
欄の型、未知のキー、値の範囲（`space-between` が負でないこと、`line-breaks` が `join` か `keep` であることなど）の検査は、`style.toml` と共有する。

### 効く範囲

- 上書きと定義は、そのファイルにだけ効く。`@import` したファイルにも、そのファイルを `@import` するファイルにも及ばない。`@import` で取り込むのは変数だけであり、取り込んだファイルの段落は出力に現れない。各ソースファイルを単独で検査できる単位に保つ（[仕様書](../specifications.md)の「プロジェクトの構成と import」）ためでもある。
- 一つのファイルに効く `[source]` の値は、ファイルの中の上書き、章の項目、`[source]`、既定の順で最初に見つかったものとする（[docs/adr/0013](0013-paragraph-separator.md)）。
- 一つのファイルで使えるスタイルは、組み込みのスタイル、`style.toml` のスタイル、そのファイルの `@style-def` のスタイルである。同じ名前があれば、そのファイルの `@style-def` の定義を上に重ねる（「同じ名前の扱い」）。
- ファイルの中のスタイルは、ファイルの中のどの位置からも使える。`@style-def` の行より前に書いたブロックはないので、定義と使用の順は問題にならない。

docs/markup.md の v1 のブロックコマンドの一覧に `@manifest` と `@style-def` を加え、「ファイルの設定」の節を設けて上の規則を書く。

### スタイルの定義の検査（golem-project）

`Golem.Project.Style` に、ファイルの中の定義の型と関数を加える。

```haskell
-- | ファイルの中で定義したスタイル。style.toml と組み込みのスタイルと同じ名前は、
-- 書いたキーだけを持ち、withLocalStyles で同じ名前の定義に重ねる。
data LocalStyles = LocalStyles
  { lsCharStyles :: !(Map Text CharStyleDef),
    lsParaStyles :: !(Map Text ParaStyleDef)
  }
  deriving stock (Eq, Show)

noLocalStyles :: LocalStyles

data StyleKind = CharacterKind | ParagraphKind
  deriving stock (Eq, Show)

-- | 原稿の値。語か文字列。
data LocalValue = LocalWord Text | LocalString Text
  deriving stock (Eq, Show)

-- | 一つの @style-def の欄を「値の読み方」の表で TOML の表に写し、
-- style.toml と同じ FromValue で読む。誤りは G0306 のメッセージとして返す。
localStyleDef :: StyleKind -> [(Text, LocalValue)] -> Either [Text] (Either CharStyleDef ParaStyleDef)

-- | ファイルの中の定義を style.toml の定義に重ねた Style。
-- 同じ名前は overChar と overPara で重ね（書いたキーが勝つ）、新しい名前は加える。
withLocalStyles :: Style -> LocalStyles -> Style

-- | withLocalStyles した Style に style.toml と同じ検査をかけ、
-- style.toml だけの Style でも出る誤りを除いたもの。
-- 返す組は（診断コード、スタイルの名前、メッセージ）。
checkLocalStyles :: Style -> LocalStyles -> [(Text, Text, Text)]

-- | @style-def のキーの一覧（LSP の補完に使う）。
charStyleKeys, paraStyleKeys :: [Text]
```

`parseStyle` の `checks`、`roleChecks`、`referenceChecks`、`sizeChecks`、`indentChecks` を、`Style` を受け取り（診断コード、スタイルの名前、メッセージ）の組を返す関数 `styleChecks` に切り出す。
`parseStyle` は読んだ `Style` に、`checkLocalStyles` は `withLocalStyles` した `Style` にかける。
`checkLocalStyles` は、`style.toml` だけの `Style` にかけた結果にもある組を除く。
`style.toml` の誤りを、ファイルごとに重ねて報告しないためである。

ファイルの中で定義した名前だけでなく、`style.toml` の名前も検査の対象に残す。
上書きは、`based-on` でその名前を引き継ぐ `style.toml` のスタイルの解決も変える。
ファイルの中で `body` の字下げを上書きすると、`style.toml` の `quote` の `indent` と `first-line-indent` の和が負になりうる（G0312）。
検査は `withLocalStyles` した `Style` の上で行うので、`based-on` が `style.toml` のスタイルを指す場合も、上書きで循環が生じる場合も検査できる。

| 検査 | 診断コード |
|---|---|
| 名前が `[a-z][a-z0-9-]*` に合わない、未知のキー、値の型や範囲の誤り | G0306 |
| `font` が `[fonts]` にない役割を指す | G0308 |
| 段落スタイルの解決した `size` が版面の文字の大きさを超える | G0311 |
| `indent` と `first-line-indent` の和が負 | G0312 |
| `based-on` が存在しない、`based-on` が循環する、`color` が `[color.swatches]` にない | G0313 |

コードは `style.toml` と同じものを使う。
位置は、名前をファイルの中で定義していればその `@style-def` の行とし、`style.toml` の名前なら、その `based-on` の鎖の中で最初にファイルの中で定義した名前の `@style-def` の行とする。
メッセージの先頭の「style.toml の」は、ファイルの中の定義では「@style-def の」にする。
一つの規則に一つのコードを当て、どこに書いた定義かは位置で示す。

### 評価（golem-eval）

`EvalContext` に `ctxStyle :: !Style`（`style.toml` を読んだ値）を加える。
golem-driver の `reeval` は `projectStyle` の値を渡す。
`ctxCharStyles` と `ctxParaStyles` は、今と同じく `style.toml` から作った値を渡す。
`EvalResult` に `erStyles :: !LocalStyles` を加え、そのファイルで定義したスタイルを返す。

`evalFile` の最初に、次の関数でファイルの設定を取り出す。

```haskell
-- | ファイルの先頭の @manifest と @style-def の並びと、残りのブロックの列。
fileHeader :: [A.Located A.Block] -> ([A.Located A.Block], [A.Located A.Block])

-- | @manifest を書いた順に ctxSource に適用した設定と、上書きの診断。
fileSettings :: SourceSettings -> [A.Located A.Block] -> (SourceSettings, [Diagnostic])

-- | @style-def を読み、検査した定義と診断。
fileStyles :: Style -> [A.Located A.Block] -> (LocalStyles, [Diagnostic])
```

`fileHeader` は次のように取り出す。

1. ファイルの先頭から、名前が `manifest` か `style-def` の `A.BlockCommand` を取り出す。
2. 次のブロックが `A.Attributed cmds t` で、`cmds` の先頭が `@manifest` と `@style-def` の並びなら、その並びを取り出す。残りの `cmds` が空なら `t` を独立したブロックとして残し、空でなければ `A.Attributed` の残りとして残す。
3. 2 で `cmds` の残りがあるか、`@manifest` と `@style-def` のほかのブロックに当たったら、そこで止める。

`fileSettings` は、`@manifest` の引数を書いた順に `sourceKeys`（[docs/adr/0013](0013-paragraph-separator.md) の `Golem.Parser.SourceSettings`）で解釈し、`ctxSource` に適用する。
返した設定を、[docs/adr/0013](0013-paragraph-separator.md) の `splitLines` に渡し、`EvalResult` の `erSource` に入れる。

`fileStyles` は次のように読む。

1. 各 `@style-def` の引数の形を検査する（G0252）。種類が `regex` なら G0254 とし、定義として扱わない。
2. 同じファイルの同じ種類で同じ名前を二度定義していれば G0253 とし、二つ目以降の定義を捨てる。`style.toml` と組み込みのスタイルと同じ名前は、上書きとして受け付ける。
3. 欄を `localStyleDef` で読み、誤りを G0306 とする。誤りのある定義は捨てる。
4. 残った定義を `LocalStyles` にまとめ、`checkLocalStyles` の結果を診断にする。参照の検査で誤った組の名前をファイルの中で定義していれば、その定義も捨てる。捨てた新しい名前を使った箇所は、G0218 か G0247 になる。捨てた上書きの名前は、`style.toml` の定義のまま使える。

評価の文脈を、ファイルの中の定義を重ねた値に替えてから、残りのブロックを評価する。

- `ctxCharStyles` に `lsCharStyles` の名前を加える。
- `ctxParaStyles` を、`withLocalStyles` した `Style` のすべての段落スタイルについて、`paraStyle` で解決した `line-breaks` の表に替える（golem-driver の `paraLineBreaks` を golem-project に移して共有する）。上書きは、その名前と、`based-on` でその名前を引き継ぐ段落スタイルの `line-breaks` を変えうる。たとえば `@style-def paragraph verse line-breaks=join` のファイルでは、`@style verse` の段落の改行が文字を生まない。
- [docs/adr/0013](0013-paragraph-separator.md) の `splitLines` と、フィルタのプラグインの後の段落スタイルの検査（`unknownParaStyles`）も、替えた後の `ctxParaStyles` を使う。

先頭でない位置の `@manifest` と `@style-def` は、`standalone` の `"manifest"` と `"style-def"` で G0249 とし、上書きと定義としては扱わない。
属性のまとまりの途中の `@manifest` と `@style-def` も、`attributed` を通って同じく G0249 とする。

G0218 と G0247 のメッセージの「style.toml にない」を「定義されていない」に改める。
ファイルの中で定義できるので、`style.toml` だけを直す先として示すと誤りになる。

| 診断コード | 重大度 | 条件 | メッセージ |
|---|---|---|---|
| G0249 | エラー | ファイルの設定の並びの外にある `@manifest` か `@style-def` | `@manifest と @style-def はファイルの最初に置きます` |
| G0250 | エラー | `@manifest` のキーが `[source]` のキーでない | `ファイルの中で上書きできない設定です: <キー>。上書きできるのは paragraph-separator です` |
| G0251 | エラー | `@manifest` の値が不正 | `paragraph-separator の値は blank-line か line です: <値>`（`sourceKeys` の返すメッセージ） |
| G0252 | エラー | 引数の形の誤り | `@manifest には key=value だけを書きます`、`@style-def には種類（character、paragraph、regex）と名前を書きます`、`値は語か文字列で書きます`、`同じキーを二度書いています: <キー>` |
| G0253 | エラー | 同じファイルの中で、同じ種類の同じ名前のスタイルを二度定義した | `同じ名前のスタイルを二度定義しています: <名前>` |
| G0254 | エラー | `@style-def regex`（正規表現スタイルの ADR を実装するまでの暫定） | `正規表現スタイルはまだ実装していません` |

G0252 の条件は、位置引数の数の誤り（`@manifest` の位置引数、`@style-def` の種類か名前の欠け、三つ目の位置引数）、未知の種類、展開する引数（`*[...]`、`**[...]`）、本体がある、`@manifest` に引数がない、同じキーを二度書いた、値が語と文字列のほか（`[= ...]`、命令文脈）、である。
誤りのある `@manifest` の引数は、その引数だけを無視し、ほかの引数の上書きは効かせる。
誤りのある `@style-def` は、その定義の全体を捨てる。
欄の一部だけを効かせた段落スタイルは、書いた人が意図しない見た目で組まれるためである。

G0249 から G0254 は未使用である（golem-eval は G0248 まで使う。G0247 と G0248 は [docs/adr/0005](0005-character-and-paragraph-styles.md) が使う。origin/main のコードと docs の ADR に G0249 から G0254 の記載はない）。

未知のキーと、マニフェストにはあるが上書きできないキー（`title` など）は、どちらも G0250 とする。
マニフェストのスキーマは `FromValue` のインスタンスとして書かれており、キーの一覧を持たない。
二つを分けるには、インスタンスと一致させ続けるキーの一覧を golem-project に別に持つことになる。
どちらの場合も、利用者が要る情報は上書きできるキーの一覧であり、メッセージに並べる。

### マニフェストとの関係（golem-project と golem-driver）

golem-project のマニフェストの読み込みは変えない。
`projectSourceSettings` は、マニフェストだけから決まる値（[docs/adr/0013](0013-paragraph-separator.md)）のままとし、ファイルの中の上書きは評価が適用する。
ファイルに実際に効いた設定は、`EvalResult` の `erSource` で知る。

golem-driver の lint（`Golem.Driver.Lint`）は、[docs/adr/0013](0013-paragraph-separator.md) のとおり `erSource` を `FileLint` に渡すので、上書きはそのまま G0501 の判定に反映される。

### 出力（golem-driver、golem-html）

golem-driver は、各ファイルの `erStyles` を集め、文書（意味論 IR の `Document` の `FileId`）ごとに `withLocalStyles style (erStyles r)` した `Style` を使う。
意味論 IR は変えない。
段落スタイルと文字スタイルの名前は今と同じく名前だけを持ち、同じ名前がどのファイルの定義を指すかは、その名前を含む `Document` の `FileId` で決まる。
ABI の版も変えない。
フィルタのプラグインから見ると、ファイルの中のスタイルの名前も `style.toml` の名前と同じ文字列である。

PDF：

- `unitsOf` は、文書ごとの `Style` で段落の書体、大きさ、字下げ、`space-between` を決める（`paraFace`、`unitsOf` の中の `paraStyle`）。
- `Unit` に `uStyle :: !Style` を加え、行を組むときの `ceRestyle` は単位の `uStyle` で `restyle` を呼ぶ。文字スタイルの解決が文書ごとになる。
- 図版のキャプション（`paraFace style geom "caption"`）と傍注（`paraFace style geom "sidenote"`）の書体と大きさも、その図版と傍注を含む文書の `Style` で決める。ファイルの中で `caption` と `sidenote` を上書きすると、そのファイルのキャプションと傍注だけが変わる。
- `usedRoles` に `[LocalStyles]` の引数を加え、すべてのファイルの中のスタイルの `font` も集める。読み込む役割は、`style.toml` のスタイルが使わない役割の分だけ増えうる。どの役割も `[fonts]` にある（G0308）ので、`[fonts]` にないフォントのファイルを探すことはない。

プレーンテキスト：

- `textFirstLine` は、文書ごとの `Style` で段落スタイルの字下げを解決する。

HTML と EPUB：

ファイルの中のスタイルは、ファイルごとに名前が衝突しうる。
章 A と章 B が、それぞれ別の定義で `letter` を定義でき、章 C が `style.toml` の `quote` を上書きできる。
CSS の選択子を、文書ごとの class で区切る。

- ファイルの中のスタイルを持つ文書の `<body>` に、class `file-<n>` を加える。`n` は、`bookDocs` の中のその文書の位置（1 から数える）である。縦組みの `vertical` と並べて `class="vertical file-3"` とする。ファイルの中のスタイルを持たない文書の `<body>` は今のままとする。既存の golden を変えないためである。
- `HtmlConfig` に `hcLocalStyles :: !(Map FileId (Map Text HtmlCharStyle, Map Text HtmlParaStyle))` を加える。golem-driver が、文書ごとの `Style` で解決した定義のうち、`style.toml` だけの `Style` で解決した定義と異なるもの（新しい名前、上書きした名前、`based-on` で上書きした名前を引き継ぐ名前）を入れる。
- `style.css` の最後に、文書の順、各文書の中では名前の順に、`hcLocalStyles` の規則を書く。
- 段落の行を保つかどうか（`block` の `keep`）は、その文書の `hcLocalStyles` を `hcParaStyles` に重ねた表で引く。
- キャプションと傍注の書体と大きさ（`hcCaptionFace`、`hcSidenoteFace`）が文書で異なれば、`body.file-<n> figcaption` と `body.file-<n> .sidenote` の規則を書く。

文書ごとの規則は、`style.toml` の規則（全体の規則）の上に重なる。
全体の規則が書いた性質が、文書ごとの規則に書かれなければ、上書きした後も全体の値が残る。
今の規則は、要素の既定と同じ性質を書かない（`charRuleMaybe`、`indentRule`）ので、全体の規則と同じ作り方では、上書きで消した性質が残る。
`style.toml` の `term` が `synthetic-bold = true` で、ファイルの中で `synthetic-bold=false` に上書きすると、全体の `.cs-term { font-weight: bold; }` が残る。
そこで、文書ごとの規則は、扱う性質をすべて書く。

| スタイル | 選択子 | 書く性質 |
|---|---|---|
| 文字スタイル `strong`、`bold`、`italic` | `body.file-<n> strong`、`body.file-<n> b`、`body.file-<n> i` | `font-family`（役割がなければ `inherit`）、`font-weight`（`bold` か `normal`）、`font-style`（`italic` か `normal`）、`color`（スウォッチがなければ `inherit`） |
| ほかの文字スタイル | `body.file-<n> .cs-名前` | 同上 |
| 段落スタイル `body` | `body.file-<n> p:not([class])` | `font-family`、`margin-block`、`padding-inline-start`、`text-indent` |
| ほかの段落スタイル | `body.file-<n> p.ps-名前` | 同上 |
| 段落スタイルの `space-between` | `S + S`（S は上の選択子） | `margin-block-start` |

- `font-family` は、役割があれば今の `fontStack` の並び、なければ `inherit` とする。
- `margin-block` は、`keep` なら `0`、`join` なら `1em`（ブラウザーの `p` の既定）とする。
- `padding-inline-start` と `text-indent` は、字下げが 0 でも書く。
- `S + S` の `margin-block-start` は、`space-between` が 1 以上なら `<n>em`、0 なら `margin-block` と同じ値とする。

`body` の選択子を `body.file-<n> p` にしないのは、詳細度のためである。
`body.file-<n> p`（class 一つ、要素二つ）は、全体の `p.ps-verse`（class 一つ、要素一つ）より詳細度が高く、その文書の `verse` の段落の字下げまで `body` の値にしてしまう。
`:not([class])` を付けると、class を持たない段落、つまり `body` の段落にだけ当たる。
`body` を上書きしても解決が変わらない段落スタイル（`verse` のように字下げを自分で持つもの）には、文書ごとの規則を書かず、全体の規則がそのまま効く。
`body` から字下げを引き継ぐ段落スタイルは解決が変わるので、上の規則で `hcLocalStyles` に入り、文書ごとの規則が書かれる。

リストの項目の中の字下げを消す全体の規則（`li p, li p[class]`）は、文書ごとの規則より詳細度が低い。
文書ごとの段落スタイルの規則を書いた文書では、`body.file-<n> li p:not([class]), body.file-<n> li p[class] { padding-inline-start: 0; text-indent: 0; }` を、その文書の規則の後に書く。

`font-weight: bold` か `font-style: italic` の文字スタイルの役割を `@font-face` で太字か斜体として宣言する規則（`boldRoles`、`italicRoles`）は、すべての文書の `hcLocalStyles` の文字スタイルも含めて集める。
`@font-face` は `style.css` に一度だけ書くので、文書ごとには分けない。

ファイルごとの `<style>` 要素で規則を書く案は外した。
HTML を Content Security Policy の `style-src 'self'` の下で配信すると、ページの中の `<style>` が効かない。
`style.css` の一つに規則を集めれば、配信の設定によらず同じ見た目になる。

### 決定性

出力は、マニフェスト、`style.toml`、各ファイルの内容だけで決まる。

- 上書きと定義は、そのファイルのテキストの中にある。ほかのファイルの評価の結果にも、評価の順序にも依存しない。
- インスタンス ID の入力（全ソースファイルとマニフェスト）は変わらない。上書きと定義はソースファイルに含まれる。
- CSS の class の番号 `n` と規則の順は、マニフェストの章の順と名前の順で決まる。
- 同じキーを二度書いた場合と、同じ名前を二度定義した場合は、後勝ちにせず G0252 と G0253 とする。書いた順に依存する規則を一つでも減らすためである。

### fmt（golem-fmt）

コードは変えない。
`@manifest` と `@style-def` の行は、ほかのブロックコマンドと同じく、名前と引数のあいだの空白を一つにそろえる。
どちらも AST の `BlockCommand` として残るので、整形の前後で AST が一致するという不変条件はそのまま成り立つ。
長い `@style-def` の行は折り返さない。

### lint（golem-lint）

規則は加えない。
マニフェストと同じ値の上書き（効果のない上書き）も、誤りとは言えないので報告しない。
G0501 の例外にする `keep` の段落スタイル（`liKeepStyles`）は、`Golem.Driver.Lint` が、文書ごとの `Style` から作る。
評価が止まった場合は、今と同じく組み込みの `keep` のスタイルだけを集合にする。

### LSP（golem-lsp）

補完（`completions`。`@import ` のパスの補完と同じく最初の分岐に加える）：

- 行頭の `@manifest ` の後で、`sourceKeys` のキーを `paragraph-separator=` の形で出す。`paragraph-separator=` の直後では、値 `blank-line` と `line` を出す。
- 行頭の `@style-def ` の後で、種類 `character` と `paragraph` を出す。`regex` は、正規表現スタイルを実装するまで出さない。
- `@style-def paragraph 名前 ` と `@style-def character 名前 ` の後で、`paraStyleKeys` と `charStyleKeys` のキーを `based-on=` の形で出す。`based-on=` の直後では同じ種類のスタイルの名前（組み込み、`style.toml`、同じファイルの `@style-def`）を、`font=` の直後では `[fonts]` の役割を、`color=` の直後ではスウォッチを、`line-breaks=` の直後では `join` と `keep` を出す。
- `@style ` と `[style ` の後の補完に、そのファイルの評価の結果の `erStyles` の名前を加える。
- `CompletionKind` に `CkSettingKey`、`CkSettingValue`、`CkStyleKind` を加え、`Golem.Lsp.Server` で `CompletionItemKind_Property`、`CompletionItemKind_EnumMember`、`CompletionItemKind_Keyword` に写す。

定義へのジャンプ：

- `Occurrence` に `OccStyleDef StyleKind Text`（`@style-def` の名前の位置引数）と `OccStyleRef StyleKind Text`（`@style 名前` と `[style 名前: ...]` の名前、`@style-def` の `based-on` の値）を加える。
- `definition` は、`OccStyleRef` の名前が同じファイルの `@style-def` で定義されていれば、その名前の位置を返す。`style.toml` の名前をファイルの中で上書きしていれば、上書きした `@style-def` の位置を返す。上書きしていない `style.toml` のスタイルと組み込みのスタイルは位置を返さない。`style.toml` の表の位置を今の読み込みは保持していないためである。

診断：

- G0249 から G0254 と、ファイルの中の定義の G0306、G0308、G0311、G0312、G0313 は、評価の診断として既存の経路で表示される。

編集：

- `@manifest` と `@style-def` の行の編集は、そのファイルの評価だけをやり直す今の経路（`updateFile`）で反映される。上書きと定義はほかのファイルに及ばないので、ほかのファイルを評価し直す必要はない。構文解析の結果も上書きと定義によらない。
- プロジェクトの外のファイルでも、`@manifest` と `@style-def` は効く。`style.toml` は既定の値とする。章の項目と `style.toml` を持たないファイルで、様式とスタイルを選ぶ唯一の方法になる。

### ドキュメント

- markup.md：「ファイルの設定」の節を設け、`@manifest` と `@style-def` の記法、置き場所、値の読み方、効く範囲、同じ名前の規則を書く。ブロックコマンドの一覧に二つを加える。「段落スタイル」と「文字スタイル」の節の「`style.toml` にない名前はエラーになる」を、「`style.toml` にも `@style-def` にもない名前」に改める。
- 仕様書：[docs/adr/0013](0013-paragraph-separator.md) で加える `[source]` の説明に、ファイルの中の上書きと値の優先の順を書く。「style.toml」の節に、文字スタイルと段落スタイルをファイルの中で定義できること、名前の規則、`style.toml` と組み込みの同じ名前の定義をそのファイルの中でだけ上書きできることを書く。「意図的に採用しなかったもの」の「ソースファイルのプリアンブル」に、`[source]` のキーの上書きとスタイルの定義に限ってファイルの中に書けることを一文で加える。
- docs/glossary.md の「原稿の記法」に「ファイルの設定」の項目（ファイルの先頭の `@manifest` と `@style-def` の並び。そのファイルにだけ効く）を加え、「文字スタイル」と「段落スタイル」の項目に `@style-def` でも定義できることを加える。

## データ構造の変更

- golem-project：`LocalStyles`、`StyleKind`、`LocalValue` を新設する。`localStyleDef`、`withLocalStyles`、`checkLocalStyles`、`charStyleKeys`、`paraStyleKeys` を新設し、`parseStyle` の検査を `styleChecks` に切り出す。golem-driver の `paraLineBreaks` を `Golem.Project.Style` に移す。
- golem-eval：`EvalContext` に `ctxStyle` を、`EvalResult` に `erStyles` を加える。
- golem-driver：`Unit` に `uStyle` を加える。`usedRoles` に `[LocalStyles]` の引数を加える。
- golem-html：`HtmlConfig` に `hcLocalStyles` を加える。
- golem-lsp：`CompletionKind` に `CkSettingKey`、`CkSettingValue`、`CkStyleKind` を、`Occurrence` に `OccStyleDef` と `OccStyleRef` を加える。

## 実装しないこと

- `[source]` のほかのキー（`language`、組み方向、書誌情報、`id`、出力ターゲット、プラグインとフィルタ）の上書き。
- `style.toml` の文字スタイルと段落スタイルのほかの節（`[fonts]`、`[color.swatches]`、`[page]`、`[headings.*]`、`[composition]`、`[masters.*]` など）のファイルの中での定義と上書き。
- 上書きで、`style.toml` の定義のキーを消すこと（値を持たない状態に戻すこと）。書いたキーが勝つ規則では、書かなかったキーは `style.toml` の値を保つ。
- 組み込みのスタイルを、ファイルの中で消すこと。
- 正規表現スタイルの意味と実装。段落スタイルの欄、`style.toml` の書き方、正規表現の方言、一致の重なりと決定性、エンジンは、v1 の別の ADR で決める。その ADR を実装するまで、`@style-def regex` は G0254 とする。
- ファイルより細かい範囲（節、ブロック）での上書きと定義。
- `@import` したファイルへの上書きと定義の伝播。ほかのファイルのスタイルを取り込む記法。
- フロントマター（`---` で囲んだ TOML）。
- 式（`[= ...]`）による値の指定。変数や `meta` から設定とスタイルの欄を導く用途が見当たらない。
- 未知のキーと上書きできないキーの診断コードを分けること。
- `@manifest` と `@style-def` を `golem fmt` でファイルの先頭に移すこと。fmt はブロックの順を変えない。
- 使っていないファイルの中のスタイルを lint で報告すること。
- 上書きしていない `style.toml` のスタイルへの定義へのジャンプと、スタイルの名前の一括の名前の変更。

## テスト設計

先に書き、失敗させてから実装する。

### golem-project（`test/Main.hs`）

- `localStyleDef ParagraphKind [("based-on", LocalWord "body"), ("indent", LocalWord "2zw"), ("line-breaks", LocalWord "keep"), ("space-between", LocalWord "1")]` が、`psBasedOn = Just "body"`、`psIndent = Just (Zw 2)`、`psLineBreaks = Just KeepLines`、`psSpaceBetween = Just 1` の段落スタイルになること。
- `localStyleDef CharacterKind [("synthetic-bold", LocalWord "true")]` が `csSyntheticBold = Just True` になり、`[("synthetic-bold", LocalString "true")]`、`[("space-between", LocalString "1")]`（段落スタイル）、`[("colour", LocalWord "x")]`、`[("line-breaks", LocalWord "x")]`、`[("space-between", LocalWord "-1")]` が誤りになること。
- `charStyleKeys` と `paraStyleKeys` の各キーが、`localStyleDef` で未知のキーの誤りにならないこと。
- 空の `style.toml` に `quote` を足した `Style` で、`based-on = "quote"` のファイルの中の段落スタイル `letter` を `withLocalStyles` した `paraStyle s (Just "letter")` が、`quote` の欄を引き継ぐこと。
- `checkLocalStyles` が、`Letter` という名前に G0306、`based-on = "nope"` に G0313、ファイルの中の `a` と `b` の循環に G0313、`[fonts]` にない `font` に G0308、`[color.swatches]` にない `color` に G0313、`[page.grid] font-size = "13Q"` での `size = "2zw"` に G0311、`indent = "1zw"` と `first-line-indent = "-2zw"` に G0312 を返すこと。
- `style.toml` に `based-on` の誤りがあっても、`checkLocalStyles` がその誤りを返さないこと。
- `[paragraph-styles.quote] font = "heading"` の `style.toml` に、ファイルの中の `quote`（`indent = "1zw"`）を `withLocalStyles` した `paraStyle s (Just "quote")` が、`psFont = Just "heading"` と `psIndent = Just (Zw 1)` を持つこと。`withLocalStyles` の前の `Style` の `quote` は変わらないこと。
- ファイルの中で `body` を `indent = "1zw"` で上書きすると、`based-on` を書かない `style.toml` の `quote` の `psIndent` が `Just (Zw 1)` になること。
- ファイルの中の `quote` を `based-on = "quote"` で上書きすると G0313 になること。`style.toml` の `a` が `based-on = "b"` のとき、ファイルの中の `b` を `based-on = "a"` で上書きすると G0313 になり、その位置の名前が `b` であること。ファイルの中の `body` に `based-on` を書くと G0313 になること。
- ファイルの中で `body` を `first-line-indent = "-1zw"` で上書きし、`style.toml` の `quote` が字下げを持たないとき、G0312 が `quote` の名前で返ること。
- `[paragraph-styles.quote]` の表を二度書いた `style.toml` の `parseStyle` が G0306 になること（TOML の重複の誤りであり、新しい検査を加えずに通ることを確かめる）。

### golem-eval（`test/FileSpec.hs`）

マニフェストの上書きは、`ctxSource` を空行の様式にした文脈で確かめる。

- `"@manifest paragraph-separator=line\n\na\nb\n"` が二つの段落 `a` と `b` になり、`erSource` が改行の様式であること。
- `"@manifest paragraph-separator=\"line\"\na\nb\n"`（空行を挟まず、値を文字列で書く）が同じ結果になり、G0211 が出ないこと。
- `"%% 設定 %%\n@manifest paragraph-separator=line\n\na\nb\n"`（先頭のコメント）が同じ結果になること。
- `"@manifest paragraph-separator=line\n@label p\na\nb\n"` で、ラベル `p` が段落 `a` に付くこと。
- `ctxSource` を改行の様式にした文脈で、`"@manifest paragraph-separator=blank-line\n\na\nb\n"` が一つの段落 `ab` になること。
- `"a\n\n@manifest paragraph-separator=line\n"` が G0249 になり、`erSource` が `ctxSource` のままであること。
- `"@manifest title=x\n"` と `"@manifest paragraph-separater=line\n"` が G0250、`"@manifest paragraph-separator=lines\n"` が G0251 になること。
- `"@manifest line\n"`、`"@manifest\n"`、`"@manifest paragraph-separator=line paragraph-separator=line\n"`、`"@manifest paragraph-separator=[= \"line\"]\n"`、本体を持つ `"@manifest paragraph-separator=line\n  a\n"` が G0252 になること。
- `"@manifest title=x paragraph-separator=line\n\na\nb\n"` で、G0250 が出たうえで `paragraph-separator` の上書きが効くこと。

スタイルの定義は、`ctxStyle` に `[color.swatches] accent` と `[paragraph-styles.quote]` を持つ `Style` を入れた文脈で確かめる。

- `"@style-def paragraph letter line-breaks=keep\n\n@style letter\na\nb\n"` が `Paragraph (Just "letter") [Text "a", LineBreak, Text "b"]` になり、`erStyles` の `lsParaStyles` に `letter` があること。
- `"@style-def paragraph letter based-on=verse\n\n@style letter\na\nb\n"` が、`verse` の `keep` を引き継いで同じ結果になること。
- `"@style-def character term color=accent\n\n[style term: x]\n"` が `CharStyle _ "term" [Text _ "x"]` を含む段落になること。`@style-def` のない `"[style term: x]\n"` が G0218 になり、メッセージに「定義されていない」が含まれること。
- `"@manifest paragraph-separator=line\n@style-def paragraph letter\n@style letter\na\nb\n"`（空行なし、改行の様式）で、`a` が `letter` の段落、`b` が `body` の段落になること。
- `"@style-def character note\n@style-def paragraph note\n\nx\n"` が診断を出さないこと（種類ごとの名前の空間）。
- `"@style-def paragraph a\n@style-def paragraph a\n"` と `"@style-def paragraph quote\n@style-def paragraph quote indent=1zw\n"` が G0253 になること。
- `"@style-def paragraph body indent=1zw\n\nx\n"`、`"@style-def character strong synthetic-italic=true\n\n[strong: x]\n"`、`"@style-def paragraph quote indent=1zw\n\n@style quote\nx\n"` が診断を出さず、`erStyles` に上書きした名前があること。
- `"@style-def paragraph verse line-breaks=join\n\n@style verse\na\nb\n"` が `Paragraph (Just "verse") [Text "ab"]` になること。上書きのない文脈では `LineBreak` で二行に分かれること。
- `"@style-def\n"`、`"@style-def table a\n"`、`"@style-def paragraph\n"`、`"@style-def paragraph a b\n"`、`"@style-def paragraph a font=[= \"x\"]\n"`、`"@style-def paragraph a indent=1zw indent=2zw\n"`、本体を持つ `"@style-def paragraph a\n  x\n"` が G0252 になること。
- `"@style-def regex body pattern=\"[0-9]+\" style=strong\n"` が G0254 になること。
- `"@style-def paragraph Letter\n"` と `"@style-def paragraph a line-breaks=x\n"` が G0306、`"@style-def paragraph a based-on=nope\n"` が G0313 になり、位置が `@style-def` の行であること。誤った定義の名前を `@style a` で使うと G0247 になること。
- `"a\n\n@style-def paragraph letter\n"` と `"@label x\n@style-def paragraph letter\na\n"` が G0249 になること。
- フィルタのプラグインが `Paragraph (Just "letter")` を返しても、`letter` を定義したファイルでは G0247 にならないこと。

### golem-lint（`test/Main.hs`）

- `flSource` を改行の様式にした `FileLint` で、欧文の二行に G0501 が出ないこと（[docs/adr/0013](0013-paragraph-separator.md) のテストと共通）。
- `liKeepStyles` に `letter` を入れたとき、`"@style letter\n  Full fathom five\n  Of his bones\n"` に G0501 が出ないこと。

### golem-driver（`test/Main.hs`）

マニフェストの上書き：

- `[source]` を書かないプロジェクトで、`@manifest paragraph-separator=line` を書いた章の三行が HTML の三つの `<p>` になり、書かない章の二行が一つの `<p>` になること。
- 章の項目に `paragraph-separator = "line"` を書き、ファイルに `@manifest paragraph-separator=blank-line` を書いた章で、ファイルの中の上書きが勝つこと。
- `@import` でだけ参照されるファイルの `@manifest` が、取り込む側の章の段落に影響しないこと。
- `golem lint` が、`@manifest paragraph-separator=line` を書いた章の欧文の二行に G0501 を出さないこと。

スタイルの定義：作業用のディレクトリに、`style.toml` に `letter` を持たないプロジェクトを作り、一つ目の章に `@style-def paragraph letter indent=2zw`、二つ目の章に `@style-def paragraph letter indent=4zw`、三つ目の章にファイルの中のスタイルを書かない。

- HTML の一つ目と二つ目の章の `<body>` が `class="file-1"` と `class="file-2"` を持ち、三つ目の章の `<body>` が class を持たないこと。
- `style.css` に `body.file-1 p.ps-letter` と `body.file-2 p.ps-letter` の規則があり、字下げの値が 2em と 4em であること。接頭辞のない `p.ps-letter` の規則がないこと。
- 縦組みのプロジェクトで、一つ目の章の `<body>` が `class="vertical file-1"` になること。
- PDF で、一つ目の章の `letter` の段落と二つ目の章の `letter` の段落の行の始まりが、2 字と 4 字下がること。
- `style.toml` に `[character-styles.term] synthetic-bold = true` と `[paragraph-styles.quote] indent = "1zw"` を書き、四つ目の章に `@style-def character term synthetic-bold=false` と `@style-def paragraph body indent=2zw` を書く。`style.css` に `body.file-4 .cs-term` の規則があって `font-weight: normal` を含むこと。`body.file-4 p:not([class])` の規則が `padding-inline-start: 2em` を含むこと。`quote` は字下げを自分で持つので `body.file-4 p.ps-quote` の規則がないこと。`body.file-4 li p:not([class]), body.file-4 li p[class]` の規則が、四つ目の章の規則の後にあること。全体の `.cs-term` と `p.ps-quote` の規則が、四つ目の章のない場合と同じであること。
- 同じプロジェクトの PDF で、四つ目の章の `[style term: 語]` が合成の太字にならず、ほかの章では太字になること。四つ目の章の `body` の段落が 2 字下がること。
- 四つ目の章で `@style-def paragraph caption size=0.8zw` を書くと、その章の図版のキャプションだけが小さく組まれること。
- `[fonts.heading]` を持ち、`style.toml` のどのスタイルも `heading` を使わないプロジェクトで、`@style-def paragraph letter font=heading` の段落が `heading` の役割のフォントのリソースで描かれること。
- `@import` でだけ参照されるファイルで定義した `letter` を、取り込む側の章で `@style letter` とすると G0247 になること。
- プレーンテキストの出力で、`@style-def paragraph letter first-line-indent=1zw` の段落の最初の行が全角の空白一つで始まること。
- 既存の golden と、`scripts/determinism.sh` の sample の各ファイルのハッシュが、この ADR の前と変わらないこと。

### golem-fmt（`test/Main.hs`）

- golden に `"@manifest   paragraph-separator=line\n"` と `"@style-def   paragraph  letter   indent=1zw\n"` を加え、空白が一つにそろうこと。整形の前後の AST の一致のプロパティテストの生成器に、ファイルの先頭の `@manifest` と `@style-def` を加えること。

### golem-lsp（`test/Main.hs`）

- `"@manifest "` の行末での補完が `paragraph-separator=` を返し、`"@manifest paragraph-separator="` の行末での補完が `blank-line` と `line` を返すこと。
- `"@style-def "` の行末での補完が `character` と `paragraph` を返し、`regex` を返さないこと。`"@style-def paragraph letter "` の行末での補完が `based-on=` と `indent=` を含むこと。`"@style-def paragraph letter based-on="` の行末での補完が `body`、`verse` と同じファイルの段落スタイルを含むこと。
- `@style-def paragraph letter` を書いたファイルで、`"@style "` の行末での補完が `letter` を含み、別のファイルでは含まないこと。
- `@style letter` の `letter` の上での定義へのジャンプが、同じファイルの `@style-def paragraph letter` の `letter` の位置を返すこと。`@style verse` の上では空の結果を返し、`@style-def paragraph verse line-breaks=join` を書いたファイルではその位置を返すこと。
- `@manifest paragraph-separator=line` を書いたプロジェクトの外のファイルで、欧文の二行に G0501 の診断が出ないこと。
- 開いたファイルの `@manifest` と `@style-def` の行を書き換えた後、プロジェクト全体の評価の回数（`wsFullEvaluations`）が増えないこと。

## トレードオフ

上書きと定義を評価の段階で読むので、ファイルの改行の意味とスタイルの名前は、構文の木を見ただけでは分からない。
エディタの構文の色分けのように CST だけを使う道具は、二つの様式を区別できない。
代わりに、構文解析と整形はファイルのテキストだけで決まり、上書きのための前処理の段階も要らない。

同じ設定を書く場所が、`[source]`、章の項目、ファイルの中の三か所になる。
どこに書いた値が効いているかは、優先の順をたどらないと分からない。
LSP のホバーで効いている値と出所を示すことは、必要になってから加える。
ファイルの中の上書きを章の項目より優先するのは、設定を原稿のテキストと一緒に移せることを重く見たためである。

`@manifest` という名前は、マニフェストのどのキーでも書けるように読める。
実際に書けるのは `[source]` のキーだけであり、ほかのキーは G0250 になる。
利用者の言う「マニフェストの上書き」をそのまま名前にし、範囲の制限は診断のメッセージで伝える。

ファイルの中で `style.toml` の定義を上書きできるので、`@style quote` の見た目はファイルによって変わる。
`style.toml` を読んだだけでは、ある章の `quote` の見た目は分からず、その章のファイルの設定も読む必要がある。
上書きはファイルの先頭の並びにしか書けず、LSP の定義へのジャンプが上書きの行を示すので、探す場所は一つのファイルの先頭に限られる。
後から `style.toml` に同じ名前のスタイルを足すと、そのファイルでは、エラーにならずに `style.toml` の定義の上に重なる。
ファイルの中で新しい名前として書いた定義が、意図せず `style.toml` の定義を引き継ぐことになる。
書いたキーは必ずファイルの中の値になるので、見た目が変わるのは、ファイルの中で書かなかったキーに限られる。

上書きは、`based-on` でその名前を引き継ぐ `style.toml` のスタイルにも及ぶ。
`body` の字下げを上書きすると、字下げを自分で持たないすべての段落スタイルの字下げが、そのファイルの中で変わる。
`style.toml` の `body` の上書きが、`body` を引き継ぐスタイルに及ぶのと同じ規則であり、その規則をファイルの中にも当てはめた結果である。

HTML と EPUB の文書ごとの規則は、扱う性質をすべて書くので、全体の規則より長い。
上書きのない文書には規則を書かないので、`style.toml` だけを使う本の `style.css` は変わらない。
`margin-block` の `1em` は、ブラウザーの `p` の既定を写したものであり、読書環境が別の既定を持つと、上書きした文書と上書きしない文書で段落の間が違って見えうる。
`revert` を使えば既定に戻せるが、EPUB の読書環境の対応がそろっていない。

ファイルの中の定義の誤りに、`style.toml` と同じ G03 の番台のコード（G0306、G0308、G0311、G0312、G0313）を使う。
コードの番台はモジュールに対応しているが、ここでは評価の診断に golem-project の番台が混ざる。
同じ規則を一つのコードで説明できることを取った。

HTML と EPUB の class `file-<n>` の番号は、章の順で決まる。
章を一つ挿入すると、後ろの章の番号がずれ、`style.css` の選択子が変わる。
出力は入力だけで決まるので決定性は保たれるが、出力の差分は大きくなる。
ファイルのパスから名前を作れば番号はずれないが、パスの文字を class 名の文字に写す規則が要り、写した名前が衝突しうる。

`@font-face` の太字と斜体の宣言は `style.css` に一度だけ書くので、ある章の文字スタイルが役割を太字にすると、ほかの章でもその役割の `@font-face` が太字として宣言される。
`style.toml` の文字スタイルでも同じことが起きており、ファイルの中のスタイルで新しく生じる問題ではない。

一つのスタイルを一行で定義するので、欄の多い段落スタイルの行は長くなる。
複数の行に分ける記法は、ブロックコマンドの引数の行の継続を文法に加える必要があり、ここでは扱わない。
欄の多いスタイルや、複数の章で使うスタイルは、`style.toml` に書く。

正規表現スタイルは v1 に入れるが、この ADR では記法だけを決め、`@style-def regex` を暫定のエラーにしておく。
v1 の別の ADR が `style.toml` の書き方を決めるまで、ファイルの中で書けるキーも決まらない。
キーを先に決めると、`style.toml` の側の設計を縛るので、ここでは決めない。
