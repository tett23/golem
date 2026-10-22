# ADR 0015: 段落スタイルの正規表現スタイル

ステータス: 採択

## 文脈

段落スタイルの中で、正規表現に一致した文字に文字スタイルを当てる機能（InDesign の正規表現スタイル、英語版の GREP スタイル）を v1 で実装する（[仕様書](../specifications.md)の「v1 の実装で次の段階以降に回した項目」の「正規表現スタイル」）。
数字だけを欧文の書体にする、「第 N 章」の N を太字にする、特定の固有名に色を付ける、といった指定を、原稿の該当箇所にいちいち `[style 名前: ...]` を書かずに済ませるためのものである。

[docs/adr/0014](0014-in-file-settings.md) は、ファイルの中の記法 `@style-def regex 段落スタイル key=value` と効く範囲を決め、意味をこの ADR に送った。
それまでの暫定として、`@style-def regex` は G02054（`正規表現スタイルはまだ実装していません`）になる。
[docs/adr/0014](0014-in-file-settings.md) がこの ADR に求めたのは次の三つである。

- 段落スタイルのどの欄に置くか、`based-on` で組の並びを引き継ぐか。
- 正規表現の方言と、ルビ、圏点、縦中横、散文スロットをまたぐ一致の扱い。
- 一致の重なりの解決の順（決定性）と、エンジンを再実装するか依存に入れるか（性能）。

文字スタイルと段落スタイルの仕組みは [docs/adr/0005](0005-character-and-paragraph-styles.md) にある。
段落スタイルの定義は `based-on` をたどり、子のキーが親のキーを上書きして決まる。
意味論 IR の文字スタイルは `CharStyle !SrcSpan !Text [Inline]` であり、PDF は `restyle` で外側の見た目に重ね、HTML は `<span class="cs-名前">`（組み込みの `strong`、`bold`、`italic` は `<strong>`、`<b>`、`<i>`）にする。
入れ子の `CharStyle` は、内側の定義が外側に勝つ。

### InDesign の正規表現スタイル

確かめた資料のあるものと、記憶によるものを分けて書く。

資料で確かめたもの（いずれも Adobe の公式のヘルプではなく、Adobe のコミュニティのフォーラムと CreativePro の記事である。公式のヘルプのページは取得できなかった）：

- 後読みは固定の長さに限る。長さの異なる候補を並べるには、後読みを候補ごとに分けて並べる（[Adobe Community: GREP for multiple spaces not preceded by two particular words](https://community.adobe.com/t5/indesign-discussions/grep-for-multiple-spaces-not-preceded-by-two-particular-words/m-p/10558410)）。
- CS6 から `\K`（そこまでの一致を一致の範囲から外す）を使える（[CreativePro: GREP of the Month: Keep Out](https://creativepro.com/grep-of-the-month-keep-out/)）。
- `\p{Punctuation}` は使えるが、`\p{Han}` のような文字体系の指定は使えない（[Adobe Community: InDesign GREP style for composite fonts](https://community.adobe.com/t5/indesign-discussions/indesign-grep-style-for-composite-fonts/m-p/13863815)）。和文の文字は `[\x{4E00}-\x{9FBF}]` のように符号位置の範囲で書く（[CreativePro: Search for foreign language characters in text](https://creativepro.com/search-for-foreign-language-characters-in-text/)）。
- 本文に手で当てた文字スタイルは、正規表現スタイルより優先されるという報告がある（[Adobe Community: Character style question](https://community.adobe.com/t5/indesign-discussions/character-style-question/m-p/13385221)）。報告者自身も網羅的には確かめていないと書いている。

記憶によるもの：

- 正規表現の方言は Boost の Perl 互換の方言に、InDesign 独自の `~` で始まるメタ文字（`~m` の全角スペース、`~=` の二分ダッシュ、`~#` のページ番号など）を加えたものである。
- 正規表現スタイルは段落スタイルの一つの属性であり、正規表現と文字スタイルの組の並びである。並びの後の組が、前の組と重なる文字では前の組に勝つ。
- `^` と `$` は段落の先頭と末尾に一致する。
- `\d` は全角の数字にも一致する。POSIX の文字クラス（`[[:punct:]]` など）を使える。大文字と小文字を区別しない `(?i)` を使える。
- 基準（Based On）の段落スタイルの正規表現スタイルは、子のスタイルが自分の正規表現スタイルを持たなければ引き継がれる。

### 当てる層の比較

正規表現スタイルを当てる層として、次の二つを比べた。

- 各媒体の出力で当てる：PDF は行を組む前に、HTML は書き出すときに、それぞれ一致を求める。InDesign が組版のたびに動的に当てるのに近い。ただし、一致を求める処理と、重なりの解決が媒体ごとに一つずつ必要になり、媒体のあいだで結果がずれる余地が生じる。
- 評価で意味論 IR に展開する：評価の最後に、一致した文字を `CharStyle` で包んだ意味論 IR を作る。媒体はすべて今の `CharStyle` の扱いのまま、同じ結果を得る。HTML と EPUB は静的な `<span>` になり、読書環境のスクリプトや CSS の機能に頼らない。

評価で展開する層を採る。
媒体契約（意味内容は全媒体で同一）を、一つの実装で保てるためである。
意味論 IR の型も ABI も変えずに済む。

代わりに、S1 と S2 で決まる値（`doc` を参照する式、ページ番号への参照）と、組み方向で表記の決まる数（`[number-text ...]`）の文字列は、評価の時点では分からない。
これらは一致の対象の中で一字の置き換え文字として扱う（「照合の対象」）。

### エンジンの比較

正規表現のエンジンを依存に入れる場合の候補と、再実装を比べた。
ライセンスと方言は記憶による（導入しないので、配布物で確かめていない）。

| 候補 | 方言 | ライセンス | 判断 |
|---|---|---|---|
| regex-tdfa（Haskell） | POSIX の拡張正規表現。最左最長の一致で、先読み、後読み、怠惰な量指定子がない | BSD-3-Clause | Perl 互換の最左優先の一致と結果が異なる。後読みを書けない |
| pcre2 か regex-pcre-builtin（Haskell のバインディングと C の PCRE2 か PCRE） | Perl 互換 | PCRE2 は BSD-3-Clause（例外条項付き） | C のライブラリを同梱することになり、ビルド、musl の静的リンク、ライセンスの一覧（[docs/adr/0007](0007-third-party-licenses.md)）に構成要素が増える |
| text-icu（Haskell のバインディングと ICU） | ICU の正規表現。Perl に近く、Unicode の性質を広く持つ | BSD-2-Clause と Unicode License | ICU のデータが数十 MB あり、配布物が大きくなる。ICU の版で Unicode のデータが変わる |
| Boost.Regex（C++、FFI） | InDesign と同じ系統 | BSL-1.0 | C++ のビルドを持ち込む |
| 再実装（Haskell） | 下の「方言」の部分集合 | なし | 採る |

再実装を採る。

- 必要な部分集合（文字、文字クラス、量指定子、選択、群、先読み、固定長の後読み、`\K`）は、後方参照を除けば、バックトラックの照合器と失敗の記憶（後述）で実装できる。規模は構文解析と照合を合わせて千行程度と見込む（見込みであり、確かめていない）。
- 一致の範囲だけが要り、捕獲した群の位置は要らない。正規表現スタイルは一致の全体に文字スタイルを当てるので、置換のための捕獲は使わない。
- C のライブラリを足さずに済み、決定性（[docs/adr/0002](0002-determinism.md)）を、Haskell の純粋な関数として保てる。Unicode の文字の分類は GHC の base の `Data.Char` に従い、base の版は freeze ファイルで固定されている。
- 依存に入れる候補は、方言が合わないか、C か C++ の大きな構成要素を持ち込む。

## 実装すること

### style.toml の欄

`[paragraph-styles.<名前>]` に `regex-styles` のキーを加える。
値は表の配列であり、各表が正規表現と文字スタイルの組である。

```toml
[character-styles.latin-digits]
font = "latin"

[paragraph-styles.body]
regex-styles = [
  { pattern = '[0-9０-９]+', style = "latin-digits" },
  { pattern = '(?<=第)[0-9]+(?=章)', style = "strong" },
]
```

| キー | 型 | 意味 |
|---|---|---|
| `pattern` | 文字列 | 正規表現（「方言」の節） |
| `style` | 文字スタイルの名前 | 一致した文字に当てる文字スタイル |

- 配列の順は意味を持つ。後の組が前の組に重なる文字では、後の組の文字スタイルが勝つ（「一致の重なりと当てる順序」）。
- 正規表現は TOML のリテラル文字列（`'...'`）で書くと、`\` をそのまま書ける。基本の文字列（`"..."`）では `\` を `\\` と書く。
- `regex-styles` は一つのキーとして `based-on` で引き継ぐ。子のスタイルが `regex-styles` を書かなければ親の並びを引き継ぎ、書けば親の並びを置き換える。`regex-styles = []` は、親の並びを引き継がないことを表す。ほかのキーと同じ規則（[docs/adr/0005](0005-character-and-paragraph-styles.md) の「based-on の解決」）であり、InDesign の振る舞いの記憶とも合う。
- 組み込みの段落スタイルは `regex-styles` を持たない。

### 正規表現の方言

InDesign の方言（Boost の Perl 互換）の部分集合とする。
部分集合の外の構文は、黙って別の意味に読まず、G03015 とする。

| 構文 | 意味 |
|---|---|
| 文字 | その文字に一致する |
| `\` と英数字でない文字 | その文字に一致する（`\.`、`\\`、`\[`、`\~` など） |
| `\t`、`\n` | タブ、行の区切り（強制改行と `keep` の段落の行の区切り。「照合の対象」） |
| `\xHH`、`\x{H...}` | 符号位置で書いた文字 |
| `.` | `\n` を除く任意の一字 |
| `[...]`、`[^...]` | 文字クラス。範囲（`a-z`、`\x{3041}-\x{3096}`）、下の文字クラスのエスケープ、POSIX の文字クラスを含められる |
| `[:alpha:]`、`[:digit:]`、`[:alnum:]`、`[:upper:]`、`[:lower:]`、`[:space:]`、`[:punct:]` | 文字クラスの中の POSIX の文字クラス。Unicode の一般カテゴリーで決める（L、Nd、L か Nd、Lu、Ll、White_Space、P） |
| `\d`、`\D` | Unicode の一般カテゴリー Nd の文字（全角の数字を含む）とその補集合 |
| `\w`、`\W` | 一般カテゴリー L、M、Nd、Pc の文字（漢字、仮名を含む）とその補集合 |
| `\s`、`\S` | Unicode の White_Space の文字（全角の空白を含む）とその補集合 |
| `\l`、`\u` | 一般カテゴリー Ll、Lu の文字 |
| `\p{名前}`、`\P{名前}` | 一般カテゴリー。一字の大分類（`L`、`M`、`N`、`P`、`S`、`Z`、`C`）、二字の分類（`Lu`、`Nd` など）、大分類の英語の名前（`Letter`、`Mark`、`Number`、`Punctuation`、`Symbol`、`Separator`、`Other`） |
| `*`、`+`、`?`、`{n}`、`{n,}`、`{n,m}` | 量指定子（欲張り） |
| `*?`、`+?`、`??`、`{n,}?`、`{n,m}?` | 量指定子（怠惰） |
| `\|`、`(...)`、`(?:...)` | 選択と群 |
| `^`、`$` | 段落の先頭と末尾 |
| `\b`、`\B` | `\w` による語の境界とその否定 |
| `(?=...)`、`(?!...)` | 先読み |
| `(?<=...)`、`(?<!...)` | 後読み。中身は固定の長さ（どの経路でも同じ字数）に限る |
| `\K` | そこまでの一致を一致の範囲から外す |
| `(?i)` | 正規表現の先頭にだけ書ける。大文字と小文字を区別しない（`Data.Char` の `toLower` と `toUpper` による単純な対応） |

G03015 とする構文：

- 後方参照（`\1` から `\9`、`\k<...>`）、名前付きの群（`(?<名前>...)`、`(?P<...>...)`）、アトミックな群（`(?>...)`）、所有的な量指定子（`*+`、`++`、`?+`）、条件（`(?(...)...)`）、コメント（`(?#...)`）。
- 先頭でない位置の `(?i)` と、ほかのフラグ（`(?s)`、`(?m)`、`(?x)`、`(?-i)`）。
- `\Q...\E`、`\X`、`\h`、`\v`、`\R`、`\A`、`\z`、`\Z`、`\G`、上の表にない英字のエスケープ。
- 文字体系の名前の `\p{...}`（`\p{Han}` など）と、表にない名前。InDesign でも使えないためである（資料は「InDesign の正規表現スタイル」）。
- 長さが一つに決まらない後読み。
- エスケープしない `~`。InDesign の `~` のメタ文字を含む正規表現を写したとき、黙って `~` という文字として読むのを防ぐためである。文字の `~` は `\~` と書く。
- 空の正規表現、閉じていない括弧、範囲の両端の逆転（`[z-a]`）、`{n,m}` の `n > m`。
- 量指定子の展開を含めた照合のプログラムの大きさが 10000 の命令を超える正規表現（`(a{1000}){1000}` など）。

### 照合の対象

一つの段落ごとに、意味論 IR の段落のインラインの列から、一致を求める対象の文字列（以下、対象）を作る。
対象は段落を越えない。
一つの段落の中だけで一致を求めるので、段落をまたぐ一致は起こらない。

| インライン | 対象の中での扱い | 文字スタイルを当てるか |
|---|---|---|
| `Text` | その文字の並び | 当てる。一致の境界で `Text` を分ける |
| `CharStyle`、`Color`、`Kenten` | 透過する。中のインラインの対象を並べる | 中の文字に当てる |
| `Ruby` | 各セグメントの親文字の対象を並べる。読みは対象に入れない | 親文字に当てる |
| `Tcy`、`Number`、`Ref`、`Deferred`、`Cite` | 置き換え文字（U+FFFC）一字 | 一字が一致に含まれれば、要素の全体に当てる |
| `Note`、`Sidenote` | 置き換え文字（U+FFFC）一字。本文は対象に入れない | 当てない |
| `IndexMark`、`ProofComment` | 何も入れない（幅を持たない） | 当てない |
| `LineBreak` | `\n` 一字 | 当てない |

- `Tcy` と `Number` を一字として扱うのは、縦中横の文字の並びと、数の表記（組み方向で「十」「一〇」「10」のどれになるか）が、要素の途中で分けられないか、評価の時点で決まらないためである。
- 脚注の本文には、どの段落スタイルの正規表現スタイルも当てない。注の本文は段落ではなく、段落スタイルを持たないためである。
- 傍注の本文には、組み込みの段落スタイル `sidenote` の `regex-styles` を当てる。図版のキャプションの段落には、`caption` の `regex-styles` を当てる。どちらも、書体と大きさをその段落スタイルで決めている（[golem-driver ADR 0010](../golem-driver/adr/0010-caption-style.md)、[golem-driver ADR 0011](../golem-driver/adr/0011-sidenote-font.md)）のに合わせる。
- 見出し、定義リストの用語、表のセル、目次、索引、参考文献には当てない。段落スタイルを持たないためである。リストの項目と定義リストの説明の段落は、その段落の段落スタイル（指定がなければ `body`）の並びを当てる。

### 一致の重なりと当てる順序

1. 並びの各組について、対象の先頭から、最左優先（Perl と同じく、左の位置で最初に成功した選択肢を採る）で重ならない一致を求める。一致の終わりから次の照合を始める。空の一致は文字スタイルを当てず、次の照合を一字先から始める。`\K` があれば、一致の範囲の始まりを `\K` の位置にする。
2. 対象の各文字について、その文字を含む一致を持つ組の集合を求める。
3. 集合が同じ文字の連続（以下、区間）ごとに、組の文字スタイルを並びの順に包む。並びの最初の組の `CharStyle` を最も外側に、最後の組を最も内側に置く。入れ子の `CharStyle` は内側が勝つので、後の組が前の組に勝つ。
4. 区間は、段落の最上位で包む。原稿で手で当てた `[style 名前: ...]`、`[color ...: ...]`、`[kenten: ...]` が区間の途中で始まるか終わる場合は、それらを区間の境界で分けて複製し、正規表現スタイルの `CharStyle` の内側に置く。手で当てた文字スタイルが、正規表現スタイルに勝つ。InDesign の振る舞いの報告（「InDesign の正規表現スタイル」）に合わせる。
5. ルビは分けられないので、区間の境界がルビの親文字の途中にある場合は、そのルビを段落の最上位では包まず、各セグメントの親文字の中で 3 と 4 を行う。ルビの親文字の全体が一つの区間に入る場合は、ルビの全体を包む。
6. `LineBreak`、`Note`、`Sidenote`、`IndexMark`、`ProofComment` は包まない。区間はこれらの位置で切れる。意味論 IR の `LineBreak` は段落の最上位にしか置けない（`Golem.Doc.Validate`）ためでもある。

分けた `Text` は、元の `Text` の位置（`SrcSpan`）をそのまま持つ。
包んだ `CharStyle` の位置は、区間の最初の要素の始まりから最後の要素の終わりまでとする。

結果は、段落の内容、並びの順、正規表現だけで決まる。
組の評価の順、ファイルの評価の順、ハッシュの表の順には依存しない。

### エンジン（golem-regex）

新しいパッケージ `modules/golem-regex` を作り、`Golem.Regex` を置く。
依存は `base`、`text`、`containers`、`array` だけとする。
仕様書 `docs/golem-regex/specifications.md` を、実装と同時に作る。

```haskell
-- | コンパイルした正規表現。Eq と Show は元の文字列で比べる。
data Regex

data RegexError = RegexError
  { reOffset :: !Int, -- 正規表現の中の位置（文字の数）
    reMessage :: !Text
  }
  deriving stock (Eq, Show)

compile :: Text -> Either RegexError Regex

-- | 重ならない一致の範囲 [始まり, 終わり)。位置は対象の文字の数で数える。
-- 最左優先で、空の一致は含めない。
matches :: Regex -> Text -> [(Int, Int)]

-- | テスト用。matches と同じ結果と、照合の手順の数。
matchesCounting :: Regex -> Text -> ([(Int, Int)], Int)
```

#### アルゴリズム

- 構文解析：正規表現を抽象構文木にし、「方言」の検査（G03015 の条件）をここで行う。
- コンパイル：抽象構文木を、命令の配列（一字の述語、分岐（欲張りと怠惰で順序を変える）、移動、表明（`^`、`$`、`\b`、`\B`）、先読みと後読みの部分プログラム、`\K`、成功）に写す。`{n,m}` は展開する。後読みの部分プログラムには、固定の長さを持たせる。
- 照合：対象を `UArray Int Char` に写し、各開始位置から、命令の番号と位置の組（pc, pos）を状態とするバックトラックで探す。一度失敗した（pc, pos）を集合に記録し、再び訪れたら直ちに失敗とする。捕獲と後方参照がないので、（pc, pos）から成功に至るかは、そこまでの経路によらない。失敗の記録は開始位置をまたいで使い回せる。探している最中の（pc, pos）を再び訪れた場合（空の繰り返しの輪）も失敗とする。
- 先読みと後読みの結果は、（部分プログラム、位置）ごとに記録して使い回す。後読みは、今の位置から固定の長さだけ戻った位置で部分プログラムを照合し、ちょうど今の位置で成功するかを調べる。
- `\K` は、成功した経路の上で最後に通った `\K` の位置を一致の始まりにする。成功するかどうかには影響しないので、失敗の記録はそのまま正しい。

失敗の記録により、一つの組の一つの段落の照合の手順の数は、命令の数 P、対象の長さ N に対して O(P × N) に収まる。
バックトラックの指数的な爆発（`(a*)*b` のような正規表現）は起こらない。
この方法は、Davis らの選択的な記憶によるバックトラックの考え方（Davis, Servant, Lee, "Using Selective Memoization to Defeat Regular Expression Denial of Service (ReDoS)", IEEE S&P 2021）と同じであり、捕獲を持たない分だけ単純になる（記憶による）。

#### テストの出典

照合器のテストは、PCRE2 の `testdata/testinput1` と `testoutput1`（BSD-3-Clause）と Boost.Regex のテスト（BSL-1.0）から、部分集合の構文だけを含む例を選んで写す。
写した例には出典のファイル名と行を注記する。
ライセンスの表示は、テストのファイルの先頭に書く。

### style.toml の読み込みと検査（golem-project）

`Golem.Project.Style` を次のように変える。

```haskell
data RegexStyleDef = RegexStyleDef
  { rdPattern :: !Text,
    rdStyle :: !Text
  }
  deriving stock (Eq, Show)

-- ParaStyleDef に加える欄
psRegexStyles :: !(Maybe [RegexStyleDef])
```

- `FromValue ParaStyleDef` は `regex-styles` を、`pattern` と `style` の二つのキーを持つ表の配列として読む。キーの欠け、未知のキー、型の誤りは、今の型の誤りと同じく G03006 とする。
- `overPara` は `psRegexStyles` を、ほかのキーと同じく `<|>` で重ねる（並びの全体を置き換える）。
- [docs/adr/0014](0014-in-file-settings.md) の `styleChecks` に `regexChecks` を加える。各組の `pattern` を `Golem.Regex.compile` にかけ、誤りを G03015 とする。`style` が文字スタイル（組み込みと `style.toml`）にない場合は G03013 とする。
- golem-project は golem-regex に依存する。

| 診断コード | 重大度 | メッセージ |
|---|---|---|
| G03015 | エラー | `正規表現を解釈できません: <理由>（<段落スタイル> の <n> 番目の正規表現の <位置> 字目）` |
| G03013 | エラー | 今の `style.toml のスタイルの参照が不正です: <理由>`。理由は `正規表現スタイルの文字スタイルがありません: <名前>` |

G03015 は未使用である（golem-project は G03013 まで使い、G03014 は作業中の [golem-driver ADR 0014](../golem-driver/adr/0014-running-heads.md) が使う。origin/main のコードと docs の ADR、作業中の ADR に記載はない）。
`<理由>` の例：`後方参照は使えません`、`後読みの長さが一つに決まりません`、`InDesign の ~ のメタ文字は使えません。文字の ~ は \~ と書きます`、`文字体系の \p{Han} は使えません。\x{4E00}-\x{9FFF} のように範囲で書きます`。

### ファイルの中の正規表現スタイル（[docs/adr/0014](0014-in-file-settings.md) の `@style-def regex`）

```
@style-def regex body pattern="[0-9]+" style=latin-digits
@style-def regex letter pattern="(?<=拝)啓" style=strong
```

- 二つ目の位置引数は、組を足す段落スタイルの名前である。組み込み、`style.toml`、同じファイルの `@style-def paragraph` のどれかの名前でなければならない（G03013）。
- キーワード引数は `pattern` と `style` の二つで、どちらも必須である。欠け、未知のキーは G03006 とする。値の読み方は [docs/adr/0014](0014-in-file-settings.md) の「値の読み方」の表のとおりであり、`pattern` は文字列として読む。
- Golem の文字列の中では、`\` の後の文字はその文字になる（`"\d"` は `d`）。正規表現の `\` は `\\` と書く（`pattern="\\d+"`）。
- 一行が一つの組である。同じ段落スタイルに何行でも書け、書いた順に並びに加わる。[docs/adr/0014](0014-in-file-settings.md) の G02053（同じ名前を二度定義した）は、正規表現スタイルには当てない。
- そのファイルの段落スタイル `P` の並びは、`style.toml` から見た `P` の並び（`based-on` で引き継いだものを含む）の後に、ファイルの中の組を書いた順に並べたものとする。そのファイルでは、`P` の `regex-styles` のキーをこの並びで上書きしたのと同じであり、`regex-styles` を書かずに `P` を `based-on` で引き継ぐ段落スタイルにも及ぶ。
- `@style-def paragraph` のキーワード引数に `regex-styles` は書けない。値が配列なので、[docs/adr/0014](0014-in-file-settings.md) の値の読み方では表せず、型の誤り（G03006）になる。

`Golem.Project.Style` を次のように変える。

- `LocalStyles` に `lsRegexStyles :: !(Map Text [RegexStyleDef])`（段落スタイルの名前から、書いた順の組）を加える。
- `withLocalStyles` は、文字スタイルと段落スタイルを重ねた後に、`lsRegexStyles` の各名前について、重ねた後の `Style` で解決した並びの後に組を足した値を、その名前の `psRegexStyles` にする。
- `checkLocalStyles` は、`regexChecks` の G03015 と G03013 を、組を書いた `@style-def` の行の位置で返す。誤りのある組は捨て、ほかの組は効かせる。

G02054 は使わなくなる。
番号は再利用しない。
`fileStyles`（[docs/adr/0014](0014-in-file-settings.md)）の手順 1 から G02054 の分岐を削り、`regex` の種類の引数を上の規則で検査する（形の誤りは G02052）。

### 評価（golem-eval）

新しいモジュール `Golem.Eval.RegexStyle` を置く。

```haskell
-- | 段落スタイルの名前（body を含む）から、コンパイルした組の並び。
type RegexRules = Map Text [(Regex, Text)]

regexRules :: Style -> RegexRules

-- | 文書のすべての段落に正規表現スタイルを当てる。
applyRegexStyles :: RegexRules -> Document -> Document
```

- `regexRules` は、そのファイルから見た `Style`（[docs/adr/0014](0014-in-file-settings.md) の `withLocalStyles` の結果）のすべての段落スタイルを `paraStyle` で解決し、`psRegexStyles` の各組をコンパイルする。検査を通った正規表現なので、コンパイルは失敗しない。並びが空の段落スタイルは表に入れない。
- `applyRegexStyles` は、ブロックの木を走査し、`Paragraph st is` に `st`（`Nothing` は `body`）の並びを、図版のキャプションの段落に `caption` の並びを、段落の中の `Sidenote` の本文に `sidenote` の並びを、「照合の対象」と「一致の重なりと当てる順序」の規則で当てる。
- `evalFile` は、フィルタのプラグインを適用し、段落スタイルの検査（`unknownParaStyles`）をした後の文書に `applyRegexStyles` をかけ、`erDocument` にする。フィルタのプラグインが返した文字も、正規表現スタイルの対象になる。InDesign の正規表現スタイルが、最後の本文の文字に当たるのと同じ考え方である。
- `EvalContext` には新しい欄を加えない。[docs/adr/0014](0014-in-file-settings.md) の `ctxStyle` とファイルの中の定義から、`evalFile` の中で `regexRules` を作る。

意味論 IR に展開した `CharStyle` は、原稿で手で書いた `[style 名前: ...]` と区別しない。
フィルタのプラグインから正規表現スタイルの結果は見えない（フィルタの後に当てるため）。

### 各媒体

- PDF、HTML、EPUB、プレーンテキストは、コードを変えない。意味論 IR の `CharStyle` を今のとおりに扱う。
- HTML と EPUB では、正規表現スタイルは静的な `<span class="cs-名前">`（組み込みの文字スタイルなら `<strong>`、`<b>`、`<i>`）になる。[docs/adr/0014](0014-in-file-settings.md) の文書ごとの CSS の規則も、そのまま効く。
- 組み込みの `strong` を正規表現スタイルに使うと、HTML では意味の強調の `<strong>` になる。見た目だけを変えたい場合は `bold` か利用者の文字スタイルを使う、と markup.md に書く。

### 性能

- 一つの組の一つの段落の照合は O(P × N) に収まる（「アルゴリズム」）。
- 正規表現のコンパイルは、ファイルの評価ごとに一度行う。
- 実装の後、『蟹工船』の fixture（`modules/golem-driver/test/fixtures/kanikosen`）の `body` に `{ pattern = '[0-9０-９]+', style = "bold" }` と `{ pattern = '(?<=「)[^」]{1,10}(?=」)', style = "italic" }` を足して PDF を作り、足す前とのビルドの時間を比べる。手元の計測の結果は、計測の環境と合わせて `docs/benchmarks/` の下に記録として残す。比べた結果が 10% を超えて遅くなる場合は、照合器の改良を別の ADR で検討する。

### 決定性

- 照合器は純粋な Haskell の関数であり、時計、乱数、環境に依存しない。
- 文字の分類（`\d`、`\w`、`\s`、`\p{...}`、`(?i)`）は、GHC の base の `Data.Char`（`generalCategory`、`isSpace` ではなく White_Space の表、`toLower`、`toUpper`）に従う。base の版は `cabal.project.freeze` で固定されているので、同じ Golem の版の中では結果が変わらない。White_Space は 25 字の固定の表として `Golem.Regex` に持つ。
- 一致の重なりの解決は、並びの順と対象の位置だけで決まる。

### lint（golem-lint）

規則は加えない。
一度も一致しない正規表現を報告することは、原稿によって一致したりしなかったりするので行わない。

### fmt（golem-fmt）

コードは変えない。
`@style-def regex` の行は、ほかのブロックコマンドと同じく整形する。

### LSP（golem-lsp）

[docs/adr/0014](0014-in-file-settings.md) の補完を次のように広げる。

- 行頭の `@style-def ` の後で、種類 `regex` も出す。
- `@style-def regex ` の後で、段落スタイルの名前（組み込み、`style.toml`、同じファイルの `@style-def paragraph`）を出す。
- `@style-def regex 名前 ` の後で、`pattern=` と `style=` を出す。`style=` の直後では、文字スタイルの名前を出す。

定義へのジャンプ：

- `@style-def regex` の二つ目の位置引数を `OccStyleRef ParagraphKind`、`style=` の値を `OccStyleRef CharacterKind` として集める。

### ドキュメント

- markup.md：「ファイルの設定」の節の `@style-def regex` の説明を、上の記法に改める。「段落スタイル」の節に「正規表現スタイル」の項を設け、`regex-styles` の書き方、方言の表、当てる範囲（段落、キャプション、傍注。脚注、見出し、表は対象外）、手で当てた文字スタイルが勝つこと、`\` の書き方（TOML のリテラル文字列、Golem の文字列の `\\`）を書く。
- 仕様書：「style.toml」の例の `[paragraph-styles.body]` に `regex-styles` を加え、説明を書く。「v1 の実装で次の段階以降に回した項目」から「正規表現スタイル」を削る。
- docs/glossary.md の「組版」に「正規表現スタイル」の項目（段落スタイルの中の、正規表現と文字スタイルの組の並び。一致した文字に文字スタイルを当てる）を加える。
- `docs/golem-regex/specifications.md` を作り、方言、照合の規則、アルゴリズム、性能の上限を書く。
- [docs/adr/0014](0014-in-file-settings.md) のステータスの行を「採択→正規表現スタイルの意味と G02054 の廃止は docs/adr/0015」に変え、この ADR へのリンクを付ける。

## データ構造の変更

- golem-regex（新設）：`Regex`、`RegexError`、`compile`、`matches`、`matchesCounting`。
- golem-project：`RegexStyleDef` を新設し、`ParaStyleDef` に `psRegexStyles` を、`LocalStyles` に `lsRegexStyles` を加える。`styleChecks` に `regexChecks` を加える。
- golem-eval：`Golem.Eval.RegexStyle`（`RegexRules`、`regexRules`、`applyRegexStyles`）を新設する。
- golem-lsp：補完と出現位置の収集に `regex` の種類を加える。
- 意味論 IR と ABI は変えない。

## 実装しないこと

- InDesign の `~` で始まるメタ文字、後方参照、名前付きの群、アトミックな群、所有的な量指定子、条件、先頭以外のフラグ、文字体系の `\p{...}`、可変長の後読み。
- 群ごとに別の文字スタイルを当てること。一致の全体に一つの文字スタイルを当てる。
- 段落をまたぐ一致。
- 脚注の本文、見出し、定義リストの用語、表のセル、目次、索引、参考文献への正規表現スタイル。
- 正規表現スタイルで、文字スタイル以外のもの（ルビ、圏点、縦中横、色の直接の指定）を当てること。
- 縦中横の中の文字、数の表記、S1 と S2 で決まる文字列の中身への一致。
- InDesign の先頭文字スタイル（段落の先頭から区切りの文字までに文字スタイルを当てる機能）。
- HTML と EPUB の CSS やスクリプトで、読書環境の側で一致を求めること。
- 正規表現スタイルが当たった箇所を LSP で示すこと（ホバーやインレイの表示）。

## テスト設計

先に書き、失敗させてから実装する。

### golem-regex（`test/Main.hs`）

- 方言の表の各行について、一致する例と一致しない例を一つ以上置く。`matches (compile "[0-9]+") "a12b345"` が `[(1,3),(4,7)]`、`\d+` が `"１２"` に一致すること、`\w+` が `"漢字かな"` の全体に一致すること、`\s` が U+3000 に一致すること、`[[:punct:]]` が `"、"` に一致すること、`\p{P}` と `\p{Punctuation}` が同じ結果になること。
- 最左優先：`a|ab` が `"ab"` で `(0,1)` に、`ab|a` が `(0,2)` に一致すること。`a*?b` が `"aab"` で `(0,3)` に、`<.+?>` が `"<a><b>"` で `(0,3)` と `(3,6)` に一致すること。
- 空の一致：`a*` が `"baa"` で `[(1,3)]` だけを返すこと。
- 先読みと後読み：`(?<=第)[0-9]+(?=章)` が `"第12章と第3節"` で `[(1,3)]` を返すこと。`(?<!\d)\d{2}(?!\d)` が `"1 22 333"` で `[(2,4)]` を返すこと。
- `\K`：`第\K[0-9]+` が `"第12章"` で `[(1,3)]` を返すこと。
- `(?i)abc` が `"ABC"` に一致すること。`a(?i)bc` が G03015 の誤り（`compile` の `Left`）になること。
- `^` と `$`：`^a` が `"aa"` で `[(0,1)]`、`a$` が `[(1,2)]` を返すこと。`^b` が `"a\nb"` に一致しないこと。`.` が `\n` に一致せず、`\n` が一致すること。
- 誤り：`\1`、`(?<n>a)`、`(?>a)`、`a*+`、`(?(1)a)`、`(?#c)`、`(?s)a`、`\Q`、`\h`、`\p{Han}`、`\p{Nope}`、`(?<=a+)b`、`(?<=a|bc)d`、`~m`、`[z-a]`、`a{3,2}`、`(a`、空の文字列、`(a{1000}){1000}` が `Left` になり、`reOffset` が誤りの位置を指すこと。`\~` と `(?<=ab|cd)e` は `Right` になること。
- 性能：`matchesCounting (compile "(a*)*b")` を `'a'` 10000 字に当てた手順の数が、命令の数 × 10001 × 4 以下であること。`(a|aa)*c` と `(?=(a+))*b` でも同じ上限を確かめる。
- PCRE2 と Boost.Regex のテストから写した例（部分集合の構文だけを含むもの）が通ること。

### golem-project（`test/Main.hs`）

- `[paragraph-styles.body] regex-styles = [{ pattern = '[0-9]+', style = "bold" }]` を読み、`paraStyle s Nothing` の `psRegexStyles` が一つの組を持つこと。
- `[paragraph-styles.quote]`（`regex-styles` なし）の `psRegexStyles` が `body` の並びを引き継ぎ、`regex-styles = []` の `quote` が空の並びを持つこと。`quote` が自分の並びを持てば、`body` の並びと合わさらず置き換わること。
- `pattern` の欠け、`style` の欠け、未知のキー `colour`、`pattern = 1` が G03006 になること。
- `pattern = '\1'` が G03015、`style = "nope"` が G03013 になること。
- `checkLocalStyles` で、`lsRegexStyles` の `body` の組が `style.toml` の `body` の並びの後に足され、`based-on` で `body` を引き継ぐ `quote` にも及ぶこと。ファイルの中の組の誤り（G03015、G03013）がその組の位置で返り、ほかの組は残ること。

### golem-eval（`test/RegexStyleSpec.hs` と `test/FileSpec.hs`）

`applyRegexStyles` は意味論 IR を直接作って確かめる。
文字スタイル `n`、`m` と、組の並び `body = [("[0-9]+", "n")]` を使う。

- `Paragraph Nothing [Text "第12章"]` が `[Text "第", CharStyle "n" [Text "12"], Text "章"]` になること。
- 並び `[("[0-9]+", "n"), ("2", "m")]` で、`"12"` が `[CharStyle "n" [Text "1"], CharStyle "n" [CharStyle "m" [Text "2"]]]` になること（後の組が内側）。
- `[Text "a1", CharStyle "x" [Text "2b"]]` で、`1` と `2` が一つの区間になり、`[Text "a", CharStyle "n" [Text "1", CharStyle "x" [Text "2"]], CharStyle "x" [Text "b"]]` になること（手で当てたスタイルが内側）。
- `Kenten` と `Color` が区間の境界で分けて複製されること。
- ルビ `[ruby: 東京12|とうきょう]` 相当の `Ruby` で、親文字の一部 `12` だけが一致すると、ルビは段落の最上位で包まれず、親文字の中で `CharStyle "n"` に包まれること。親文字の全体が一致すると、`Ruby` の全体が包まれること。読みの `12` には一致しないこと。
- `Tcy "12"` は一字の置き換え文字として扱われ、`[0-9]+` に一致しないこと。`.` には一致し、`Tcy` の全体が包まれること。
- `Note` の本文の `"12"` に、段落の並びが当たらないこと。`Sidenote` の本文には `sidenote` の並びが当たること。図版のキャプションの段落に `caption` の並びが当たり、`body` の並びが当たらないこと。
- `[Text "a1", LineBreak, Text "2b"]` に `[0-9\n]+` を当てても、`LineBreak` が包まれず、`1` と `2` が別の `CharStyle` になること。結果が `Golem.Doc.Validate` を通ること。
- 見出し、表のセル、定義リストの用語の文字に当たらないこと。リストの項目の段落には `body` の並びが当たること。
- `evalFile` で、`"@style-def regex body pattern=\"\\\\d+\" style=bold\n\na1\n"` が `CharStyle "bold" [Text "1"]` を含み、G02054 が出ないこと。
- `"@style-def regex nope pattern=x style=bold\n"` が G03013、`"@style-def regex body style=bold\n"` が G03006、`"@style-def regex body pattern=\"\\\\1\" style=bold\n"` が G03015、`"@style-def regex body\n"` が G03006 になること。
- 同じファイルに `@style-def regex body` を二行書くと、二つの組が書いた順に並ぶこと（G02053 にならないこと）。
- フィルタのプラグインが返した `Text` にも正規表現スタイルが当たること。

### golem-driver（`test/Main.hs`）

- `style.toml` に `[character-styles.n] synthetic-bold = true` と `[paragraph-styles.body] regex-styles = [{ pattern = '[0-9]+', style = "n" }]` を書いたプロジェクトで、HTML の段落 `第12章` が `第<span class="cs-n">12</span>章` になること。プレーンテキストが `第12章` のままであること。
- 同じプロジェクトの PDF で、`12` のグリフが合成の太字で描かれ、`第` と `章` が描かれないこと（描画の命令の線の幅の有無で確かめる）。
- [docs/adr/0014](0014-in-file-settings.md) のファイルの中の正規表現スタイルを書いた章だけで、HTML の `<span>` が付くこと。
- 縦組みのプロジェクトで、ルビの親文字の中の一致が PDF で組めること（エラーにならず、ルビが親文字の上に置かれること）。
- 既存の golden と、`scripts/determinism.sh` の sample の各ファイルのハッシュが、この ADR の前と変わらないこと。

### golem-lsp（`test/Main.hs`）

- `"@style-def "` の行末での補完が `regex` を含むこと。`"@style-def regex "` の行末での補完が `body` を含むこと。`"@style-def regex body "` の行末での補完が `pattern=` と `style=` を返すこと。`"@style-def regex body pattern=x style="` の行末での補完が文字スタイルの名前を返すこと。

## トレードオフ

評価の時点で意味論 IR に展開するので、S1 と S2 で決まる文字列（`doc` を参照する式、章番号とページ番号の参照）と、組み方向で決まる数の表記には、正規表現が一致しない。
InDesign では、ページ番号のような自動の文字にも正規表現スタイルが当たる（記憶による）。
これらを対象にするには、S1 の後か媒体ごとに当てる層が要り、媒体のあいだの結果の一致を別に保つことになる。
数字の書体を変える用途では、`[number-text ...]` の数が対象から外れることに注意が要る。

縦中横（`[tcy: ...]`）の中の文字を一字の置き換え文字として扱うので、`[0-9]+` は縦中横の数字に一致しない。
縦中横の数字の書体を変えたい場合は、縦中横の全体に一致する正規表現（`.` など）では足りず、原稿で文字スタイルを当てる。
縦中横の中を文字として扱い、途中で分けられない要素を包むかどうかを決める規則は作れるが、規則が一つ増える。

手で当てた文字スタイルを正規表現スタイルより内側に置くので、手で当てた文字スタイルが勝つ。
InDesign の振る舞いは公式の資料で確かめておらず、フォーラムの報告に拠っている。
逆の振る舞いが正しいと分かった場合は、包む順を入れ替える ADR を作る。
包む順は意味論 IR の形として出力に現れるので、入れ替えると HTML の `<span>` の入れ子の順が変わる。

正規表現の照合器を再実装するので、PCRE2 や Boost.Regex と結果が食い違う不具合が起こりうる。
テストの例を両者のテストから写して、食い違いを減らす。
方言を部分集合に絞ったので、InDesign の正規表現スタイルをそのまま写すと G03015 になることがある。
黙って別の意味に読むよりは、移すときに直す箇所が分かるほうを取った。
`\p{Han}` を使えないのは不便だが、InDesign でも使えず、使えるようにすると Unicode の文字体系の表（Scripts.txt）を Golem に持つことになる。

Golem の文字列の中では `\` がエスケープになるので、ファイルの中の正規表現では `\d` を `\\d` と書く必要がある。
`"\d"` と書くと、黙って `d` になる。
文字列の段階で `\` の後の英字を誤りにすれば防げるが、文字列の規則は式の言語と共有しているので、ここでは変えず、markup.md の説明と例で補う。
`style.toml` では TOML のリテラル文字列を使えば、この問題は起こらない。

意味論 IR に展開した `CharStyle` は、手で書いた `[style 名前: ...]` と区別できない。
フィルタのプラグインは正規表現スタイルの後の文書を見ないので、区別の要る場面は当面ない。
HTML でも同じ `<span class="cs-名前">` になるので、正規表現スタイルの箇所だけを CSS で選ぶことはできない。

失敗の記録は、照合の最中に（命令、位置）の組の集合を持つので、長い段落と大きい正規表現の組では、照合の間のメモリが P × N に比例して増えうる。
一つの段落の長さは数千字程度であり、命令の数を 10000 で抑えているので、上限は一つの照合あたり数千万の組になる。
実際には訪れた組だけを記録するので、これより小さいと見込む（確かめていない）。
