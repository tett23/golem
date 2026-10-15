# ADR 0022: 柱の内容の書式

ステータス: 採択

## 文脈

[golem-driver ADR 0014](0014-running-heads.md) は、柱の内容を固定の語彙に絞った。
マスターページの `running-head` の `content`（または `even` と `odd`）に書けるのは、`heading.<l>.short`、`heading.<l>.numbered`（どちらも末尾に `.last` を付けられる）、`title`、`none` だけである。
書式の文字列にしなかった理由として、[ADR 0014](0014-running-heads.md) は「ノンブルの書式と別の差し込みの言語が増える」ことを挙げ、v1 は InDesign の柱の変数の基本の使い方に絞るとした。

その結果、次の柱が作れない。

- 書名と章の題を一つの柱に並べる柱（「Golem 入門　第 1 章　組版の基礎」）。
- 章の題と節の題を並べる柱。
- 固定の文言だけの柱（「校正刷り」、版の番号など）。
- 書名の行と章の題の行を重ねた、二行の柱。

仕様書の「v1 の実装で次の段階以降に回した項目」の「柱の内容の書式」は、任意の文字列と変数の参照（`meta` のメタデータ、見出しの題と番号、`@set` の変数）と複数の行を書けるようにすること、記法、行送りと揃え、版面との空き、値がないときの扱い、参照の誤りの診断を ADR で決めるとしている。

今の実装をコードで確かめると、次のとおりである。

- `Golem.Project.Style` の `parseRunningContent` が、内容の文字列を `RunningContent`（`RunningHeading l form pick`、`RunningTitle`、`RunningNone`）に読む。`FromValue RunningHeadDef` は、`content` か `even` と `odd` の両方を求め、それ以外を G0314 とする。値は文字列だけを受け付ける。
- `Golem.LayoutSpec.masterGeometry` は、内容を `mgRunningHead :: Maybe (RunningContent, RunningContent, Anchor, Anchor)` で運ぶ。アンカーの y は、天の位置なら天の余白の中央、地の位置なら地の余白の中央である。
- `Golem.Driver.Pdf.runningHeadText` が一ページの柱の文字列（`Maybe Text`）を決め、`runningHeads` がページの番号からの表を作る。`masterMarks` は、その文字列を `textAt` で、本文の役割と版面の文字の大きさで一行だけ描く。行の幅は検査しない。
- `meta` の値は、`Golem.Driver.metadataValues` がマニフェストの `[metadata]` から作る（`id`、`title`、`language`、`date`、`creators`、あれば `title_reading`、`edition`、`publisher`）。`creators` は配列である。
- `@set` の変数はファイルの単位であり、評価の結果の `EvalResult` の `erExports` に、そのファイルで定義した変数が残る。import した変数は `ctxImports` から引く。
- 書式の文字列の差し込みは、すでに `formatNumber`（見出しの番号、図番号、ノンブル）と `[lists]` の `numbers` にある。`[lists]` は、差し込みでない `{` と `}` を `{{` と `}}` で書くと決めている（[golem-driver ADR 0013](0013-list-indents.md)）。

InDesign では、柱の変数（段落スタイルの柱、メタデータのキャプションなど）とテキストを、マスターページのテキストフレームの中に自由に並べる。
固定の文言は、フレームに直接打つ。
二行の柱は、フレームの中で改行するか、フレームを二つ置いて作る。
この ADR は、マスターページのフレームを持たない Golem で、同じことを `style.toml` の書式で書けるようにする。

## 実装すること

### 書式の書き方

`running-head` の `content`、`even`、`odd` の値に、文字列の配列を書けるようにする。
配列の各要素が柱の一行であり、配列の順に天から地へ重ねる。

```toml
[masters.body]
# 書名と章の番号と題を一行に並べる
running-head = { position = "top-outside", content = ["{meta.title}　{heading.1.numbered}"] }

[masters.book]
# 偶数ページに書名、奇数ページに章の題と節の題（節がなければ章の題だけ）
running-head = { position = "top-outside", even = ["{meta.title}"], odd = ["{heading.1.short}　{heading.2.short?}"] }

[masters.twoline]
# 書名の行と章の題の行を重ねる
running-head = { position = "top-outside", content = ["{meta.title}", "{heading.1.short}"] }

[masters.proof]
# 固定の文言と @set の変数
running-head = { position = "top-center", content = ["校正刷り　{set.revision}"] }
```

[ADR 0014](0014-running-heads.md) の文字列の値（`"heading.1.short"`、`"title"`、`"none"` など）は、そのまま同じ意味で読む。
文字列は語彙の名前、配列は書式と、値の型で読み方を分ける。
文字列に書式を書けるようにすると、綴りを誤った語彙の名前（`"heading.1.shrot"`）が固定の文言として黙って柱に出てしまう。
[ADR 0014](0014-running-heads.md) が G0314 で防いだこの誤りを、型の違いで防ぎ続けるためである。
文字列に `{` を含む値を書いた場合の G0314 のメッセージでは、配列で書くよう案内する。

語彙の値と書式は、次のとおり対応する。

| 語彙の値 | 同じ意味の書式 |
| --- | --- |
| `"heading.<l>.short"` など | `["{heading.<l>.short}"]` など |
| `"title"` | `["{meta.title}"]` |
| `"none"` | （書式では書かない） |

この対応のとおり、実装は語彙の値を読み込みの段階で書式に直し、以後は書式だけを扱う。

`even` と `odd` の片方を文字列、もう片方を配列で書いてもよい。
`content` と `even` または `odd` を一緒に書けないこと、`even` と `odd` の片方だけを書けないことは、[ADR 0014](0014-running-heads.md) のとおりである。

### 差し込み

書式の各行は、文字と差し込みからなる。
差し込みは `{` と `}` で囲む。
差し込みでない `{` と `}` は、`[lists]` の番号の書式と同じく `{{` と `}}` で書く。

| 差し込み | 値 |
| --- | --- |
| `{heading.<l>.short}` | 階層 l の見出しの短い題（[ADR 0014](0014-running-heads.md) と同じ） |
| `{heading.<l>.numbered}` | 階層 l の見出しの番号の表記、全角の空白、短い題。番号のない見出しは短い題だけ（[ADR 0014](0014-running-heads.md) と同じ） |
| `{heading.<l>.number}` | 階層 l の見出しの番号の表記だけ（「第一章」など）。番号のない見出しでは値がない |
| 上の三つの末尾に `.last` | ページの中の見出しの選び方を「最後」にする（[ADR 0014](0014-running-heads.md) と同じ） |
| `{meta.<キー>}` | マニフェストの `[metadata]` の値。キーは `title`、`title_reading`、`edition`、`publisher`、`date`、`language`、`id` |
| `{set.<名前>}` | そのページのファイルで `@set` した変数 |
| `{set.<名前空間>.<名前>}` | そのページのファイルが `@import ... as <名前空間>` で取り込んだ変数 |

`heading` の l は 1 以上の整数とする。
`meta` のキーは、式文脈の `meta` と同じ綴り（`title_reading` は下線）とする。
`meta.creators` は配列なので書けない（G0314）。
式文脈でも配列は本文に埋め込めず、型エラーになる規則に合わせる。
著者名を柱に出す場合は、`@set` で文字列の変数を作る。

差し込みの名前の末尾に `?` を付けると（`{heading.2.short?}`）、値がないときに空の文字列として扱う（下の「値がないとき」）。

`set` の変数は、そのページのファイルの変数とする。
ページのファイルは、[ADR 0014](0014-running-heads.md) がマスターページを選ぶのに使う、そのページの最初の行を組んだファイルである。
`@set` の変数がファイルの単位で定義されるという今の規則を変えないためである。
本の全体で同じ値を柱に出したい場合は、変数を一つのファイルに置き、各章のファイルで `@import` して `{set.<名前空間>.<名前>}` で参照する。

### 値の文字列

- 見出しの値は、[ADR 0014](0014-running-heads.md) と同じく `hiTitle` と `hiNumberText` から作る。
- `meta` の値は、`metadataValues` の文字列である。`date` は `2026-10-11` の形になる。
- `set` の変数の値は、文字列はそのまま、整数は十進の算用数字、浮動小数点数は言語仕様の「数の規則」の表記で文字列にする。式文脈 `[= ...]` で本文に埋め込んだときと同じ文字列である。真偽値、`nil`、配列、連想配列は G0268 のエラーとする。

縦組みの本でも、柱は [ADR 0014](0014-running-heads.md) のとおり横書きで描くので、数を `[numbers]` の `vertical` の表記に変えない。

### 値がないとき

差し込みの値は、次の場合に「ない」とする。

- 見出しの差し込みで、[ADR 0014](0014-running-heads.md) の規則による有効な見出しがない場合。`number` で、見出しが番号を持たない場合。
- `meta` の差し込みで、マニフェストにそのキーがない場合（`edition`、`publisher`、`title_reading`）。
- 値が空の文字列の場合（`title = ""` など）。

`set` の変数がそのページのファイルで定義されていない場合は、値がないのではなく、誤りとして G0267 とする（下の「診断」）。
ただし `?` を付けた差し込みは、定義されていなくても G0267 にせず、空の文字列とする。

各行の柱は、次の順に決める。

1. `?` のない差し込みのうち、一つでも値がなければ、その行を描かない。
2. `?` を付けた差し込みのうち、値のないものは空の文字列にする。
3. できた文字列の先頭と末尾の空白（U+0020 と U+3000）を取り除く。
4. 取り除いた結果が空の文字列なら、その行を描かない。

すべての行を描かない場合は、柱を描かない。
[ADR 0014](0014-running-heads.md) で「有効な見出しがないページには柱を描かない」とした規則は、`["{heading.1.short}"]` の行を描かない規則として、この手順に含まれる。
3 の手順は、`"{heading.1.short}　{heading.2.short?}"` で節の題がないときに、章の題の後に全角の空白が残らないようにするためである。

[ADR 0014](0014-running-heads.md) の「柱を描かないページ」（白ページ、`page-break = "recto"` の見出しを置いたページ、`running-head` のないマスターページのページ）は変えない。
固定の文言だけの柱も、章の始まりのページには描かない。

### 複数の行の置き方

柱の各行は、[ADR 0014](0014-running-heads.md) と同じく本文の役割と版面の文字の大きさで、横書きで描く。
行送りは、本文の行送り（`[page.grid]` の行送り）とする。
各行は、アンカーの揃え（`outside` なら小口の側、`inside` ならノドの側、`center` なら中央）にそろえる。

行を重ねる向きは、版面との空きを変えないように決める。

- 天の位置（`top-outside`、`top-inside`、`top-center`）では、最後の行（版面に最も近い行）のベースラインを今のアンカーの位置に置き、それより前の行を行送りずつ天の側へ置く。
- 地の位置では、最初の行（版面に最も近い行）のベースラインを今のアンカーの位置に置き、それより後の行を行送りずつ地の側へ置く。

描かない行は詰め、残った行を版面の側から順に置く。
一行の柱は、今と同じ位置に描かれる。

行を増やしたときに版面との空きを変える設定は設けない。
空きを変えたい場合は、版面の位置（余白）を変える。

### 診断

この ADR が加えるコードと、意味を広げるコードは次のとおりである。

| コード | 重大度 | 段階 | 出す条件 | メッセージ |
| --- | --- | --- | --- | --- |
| G0314 | エラー | プロジェクト | 書式の誤り（下の一覧） | `柱の書式が正しくありません: <理由>` |
| G0267 | エラー | 評価 | 柱の書式の `{set.<名前>}`（`?` なし）が、そのマスターページを使うファイルで定義されていない | `柱が参照する変数 <名前> が、このファイルにありません（マスターページ <マスターページの名前>）` |
| G0268 | エラー | 評価 | 柱の書式が参照する変数の値が、文字列でも数でもない | `柱に出せるのは文字列と数です: <名前> は <型>` |
| G0751 | 警告 | レイアウト | 描く柱の行の幅が、そのページの版面の幅を超える | `柱の行が版面の幅を超えています（<ページ> ページ）: <行の文字列>` |
| G0752 | エラー | レイアウト | 柱の行がページの仕上がりの線を越える | `柱の行がページからはみ出しています。行の数を減らすか、天（または地）の余白を広げてください` |

G0314 で報告する書式の誤りは次のとおりである。
位置は、誤りのある値（`content`、`even`、`odd` の値）とする。

- 閉じていない `{`、対にならない `}`、空の差し込み `{}`。
- 表にない差し込み（`{heading.0.short}`、`{heading.1.long}`、`{meta.author}`、`{chapter}` など）と、`{meta.creators}`。
- 空の配列、空の文字列の要素、改行（U+000A）を含む要素。行は配列の要素で分けるので、要素の中の改行は書き方の重複になるためである。
- 配列の要素が文字列でない場合。
- 文字列の値に `{` を含む場合。メッセージで、書式は配列で書くことを示す。

`{set.<名前>}` は、どのファイルにどの変数があるかが評価の後でないと分からないので、`style.toml` を読む段階では名前の形だけを検査する。
G0267 と G0268 は、golem-driver が S0 の評価の後に、マニフェストの章の各ファイルについて検査する。
ファイルのマスターページは、[ADR 0014](0014-running-heads.md) の規則（章の項目の `master`、なければ `body`、なければ名前の順で最初のもの）で決める。
行のないページが前のページのファイルを使う規則はページ割りの後でないと決まらないが、ページのファイルはどれかの章のファイルなので、章のファイルの単位の検査で足りる。
位置は、そのファイルの先頭とし、関連する位置として `style.toml` の先頭を添える。
同じファイルと同じ変数の組には、一つだけ出す。
評価の段階の検査なので、`golem check` でも出る。
PDF をターゲットに含まないビルド（`--target html` など）では、柱を使わないので検査しない。

G0751 は、柱を描く処理（`masterMarks`）で、シェイピングした行の幅を版面の幅（横組みでも縦組みでも、そのページの版面の矩形の幅）と比べて出す。
柱を版面の幅で折り返さないので、版面の外へ伸びて小口やノドの余白に入るが、PDF は組める。
同じ行の文字列には一つだけ出し、位置は `style.toml` の先頭とする。

G0752 は、`Golem.LayoutSpec.pageGeometry` で、書式の行の数の最大と行送りから、最も外側の行の字の外枠（ベースラインから、天の側へ文字の大きさ × `baselineRatio`、地の側へ残り）が仕上がりの判型の外に出るかで決める。
行の数は `style.toml` だけで決まるので、`golem check` でも出る。
位置は `style.toml` の先頭とする。

G0267、G0268、G0751、G0752 は未使用である。
G0751 は警告なので、[golem-syntax ADR 0002](../../golem-syntax/adr/0002-notice-severity.md) の `noticeCodes` には加えない。

### HTML、EPUB、プレーンテキスト

[ADR 0014](0014-running-heads.md) のとおり、柱を出さない。
G0267 と G0268 も、これらだけのビルドでは出さない。

### 決定性

柱の各行は、収束した最終回の `PageOut` の列、S1 の `bookHeadings`、マニフェストの `[metadata]`、各ファイルの S0 の変数、`style.toml` だけから決まる純粋な関数で求める。
柱は行の格子の外に描き、改ページに影響しない。

### ドキュメント

- docs/specifications.md の「v1 の実装で次の段階以降に回した項目」から「柱の内容の書式」を削る。
- 同じく「style.toml」の柱の節に、配列の書式、差し込みの表、`?`、`{{` と `}}`、値がないときの手順、複数の行の置き方、四つの診断を書き、この ADR へリンクする。[ADR 0014](0014-running-heads.md) の内容の値の表は残し、書式と同じ意味であることを書く。
- docs/diagnostics.md の G0314 の節に書式の誤りを足し、G0267、G0268、G0751、G0752 の節を足す。
- 利用者のマニュアル（`manual/`）に、書式の例（書名と章の題を並べる柱、二行の柱）を書く（[docs/adr/0024](../../adr/0024-manual-audiences-and-policy.md)）。例は `manual/chapters/05-style.gm` の「柱とノンブル」の節に、キーと値の一覧は `manual/appendices/c-style.gm` の「`[masters.名前]`」の節に書く。`manual/appendices/f-indesign.gm`（今の `e-indesign.gm`、[golem-cli ADR 0006](../../golem-cli/adr/0006-preflight.md) で付録F に繰り下がる）の「マスターページと親ページ」の節の「柱に出す内容も、見出しの題、番号と題、書名のどれかから選びます」を、書式で組み合わせられることに合わせて直す。
- [golem-driver ADR 0014](0014-running-heads.md) のステータスの行を `ステータス: 採択→内容の書式は [golem-driver ADR 0022](0022-running-head-formats.md)` に変える。

## データ構造の変更

golem-project の型を次のようにする。
[ADR 0014](0014-running-heads.md) の `RunningHeading`、`RunningTitle` は、読み込みで書式に直すので削る。

```haskell
data HeadForm = HeadShort | HeadNumbered | HeadNumber -- HeadNumber を加える
data HeadPick = PickFirst | PickLast                    -- 変えない

data RunningRef
  = RefHeading !Int !HeadForm !HeadPick
  | RefMeta !Text      -- title、title_reading など
  | RefVar ![Text]     -- set の後の名前（名前空間を含む）

data RunningPart
  = PartText !Text
  | PartRef !RunningRef !Bool -- True なら ? 付き

data RunningContent
  = RunningLines !(NonEmpty [RunningPart]) -- 行の列
  | RunningNone
```

`RunningHeadDef`、`MasterDef`、`MasterGeometry` の形は変えない（中の `RunningContent` の定義が変わる）。
書式の文字列を読む関数 `parseRunningFormat :: Text -> Either Text [RunningPart]`（`Left` は G0314 の理由）を golem-project に置く。

golem-driver の型と関数を次のようにする。

```haskell
-- PdfInput に加える。章のファイルごとの、柱で使う変数の文字列（名前空間を含む名前から）
piRunningVars :: !(Map FileId (Map [Text] Text))

-- runningHeadText を置き換える。行ごとに、描くなら Just
runningHeadLines
  :: Map Text Text               -- meta の文字列
  -> Map [Text] Text             -- そのページのファイルの変数
  -> RunningContent
  -> Map Int (Maybe HeadingInfo) -- ページの始まりの時点の有効な見出し
  -> [HeadingInfo]               -- そのページで始まった見出し
  -> [Text]                      -- 描く行（描かない行を除いたもの）

-- runningHeads の値を、行の列にする
runningHeads :: PdfInput -> PageGeometry -> PdfLayout -> Map Int [Text]
```

`piRunningVars` は `Golem.Driver` が、各ファイルの `erExports` と import した変数から、柱の書式が参照する名前だけを文字列にして作る。
G0267 と G0268 は、このときに出す。

意味論 IR とプラグインの ABI は変えない。

## 実装しないこと

- 柱にノンブルを差し込むこと（`{page}`）。ノンブルは `folio` で描き、柱と並べたい場合は同じ位置を指定する。柱とノンブルを一つの文字列にすると、ノンブルを描かないページの規則と柱を描かないページの規則が食い違う。
- 柱の行ごとに書体、大きさ、色、揃えを変えること。仕様書の「ページ番号と柱の拡張」に含める。
- 書式の中での条件の分岐、文字列の加工（大文字への変換、末尾の句読点の削除、長い題の省略）。
- 柱の行を版面の幅で折り返すこと。G0751 で知らせる。
- 行を重ねたときの版面との空きを指定するキー。
- 本の全体で共有する変数の置き場（`style.toml` や `manifest.toml` に変数を書くこと）。`@import` で足りるので設けない。
- `meta.creators` を柱に出す書き方（区切りの文字を決めて配列をつなぐこと）。
- HTML、EPUB、プレーンテキストの柱。

## テスト設計

先に書き、失敗させてから実装する。

### golem-project（`modules/golem-project/test/Main.hs`）

- `content = ["{meta.title}　{heading.1.numbered}"]` が、`RunningLines` の一行（`PartRef (RefMeta "title") False`、`PartText "　"`、`PartRef (RefHeading 1 HeadNumbered PickFirst) False`）として読めること。
- `content = ["{meta.title}", "{heading.1.short}"]` が二行になること。
- `{heading.2.short.last?}` が `PartRef (RefHeading 2 HeadShort PickLast) True` になること。`{heading.1.number}` が `HeadNumber` になること。
- `{set.revision}` が `RefVar ["revision"]`、`{set.values.price}` が `RefVar ["values", "price"]` になること。
- `["{{書名}}"]` が `PartText "{書名}"` になること。
- 語彙の値 `"heading.1.short"` が `RunningLines (([PartRef (RefHeading 1 HeadShort PickFirst) False]) :| [])` に、`"title"` が `{meta.title}` の一行に、`"none"` が `RunningNone` になること。
- `even = "title"`、`odd = ["{heading.1.short}"]` の組み合わせが読めること。
- 次のそれぞれが G0314 になり、位置が値の位置であること：`["{heading.1.short"]`、`["a}b"]`、`["{}"]`、`["{heading.0.short}"]`、`["{heading.1.long}"]`、`["{meta.author}"]`、`["{meta.creators}"]`、`["{chapter}"]`、`[]`、`[""]`、`["a\nb"]`、`[1]`、`"{meta.title}　{heading.1.short}"`（文字列の値。メッセージに「配列」を含むこと）。

### golem-layout-spec（`modules/golem-layout-spec/test/Main.hs`）

- 天の余白が行送りの 1.5 倍しかない版面で、三行の柱の書式が G0752 になり、一行の柱は G0752 にならないこと。地の位置でも同じであること。

### golem-driver の単体のテスト（`modules/golem-driver/test/Main.hs`）

[ADR 0014](0014-running-heads.md) のテストの見出し（「第一章 海」、「一 朝」、「二 昼」、「第二章 山」）で、`runningHeadLines` を確かめる。

- `["{meta.title}　{heading.1.short}"]` が、「海」のページで「書名　海」になること。最初の章より前のページで、行がなくなること（柱を描かない）。
- `["{heading.1.short}　{heading.2.short?}"]` が、「海」だけが始まり節のないページで「海」（末尾の全角の空白がない）になり、「一 朝」のページで「海　朝」になること。
- `["{heading.1.short}　{heading.2.short}"]`（`?` なし）が、節のないページで行がなくなること。
- `["{meta.title}", "{heading.1.short}"]` が、最初の章より前のページで「書名」の一行になり、章のページで二行になること。
- `["{heading.1.number}"]` が「第一章」になり、`@nonumber` の見出しでは行がなくなること。
- `["{meta.edition}版"]` が、`edition` のないマニフェストで行がなくなり、`["{meta.edition?}版"]` で「版」になること。
- `["校正刷り"]` が、どのページでも「校正刷り」になること。
- `["{set.revision}"]` が、変数の文字列、整数 3 の「3」、浮動小数点数 0.5 の「0.5」になること。

### golem-driver の PDF と診断のテスト

- `even = ["{meta.title}"]`、`odd = ["{heading.1.short}"]` の `runningHeads` の表が、[ADR 0014](0014-running-heads.md) の `even = "title"`、`odd = "heading.1.short"` の表と一致すること。
- 二行の柱で、天の位置の最後の行のベースラインが一行の柱のベースラインと同じ y にあり、最初の行がその上の行送りの位置にあること。地の位置では逆になること。`top-outside` で、二行がともに小口の側にそろうこと。
- `page-break = "recto"` の見出しのページで、固定の文言の柱も描かれないこと。
- `{set.revision}` を使うマスターページを、`revision` を定義しないファイルに当てると G0267 が一つ出て、位置がそのファイルの先頭であること。`{set.revision?}` では出ないこと。
- `@set revision = true` が G0268 になること。
- `@import common/values.gm as values` のファイルで `{set.values.price}` が取り込んだ値になること。
- `--target html` だけのビルドで、G0267 が出ないこと。
- 版面の幅を超える長い固定の文言で G0751 が一つ出て、PDF が書かれること。
- 柱の書式だけが違う二つの `style.toml` で、`plPages` が一致すること。
- 柱を含む原稿を並列と逐次で組み、PDF のバイト列が一致すること。
- `scripts/determinism.sh` の出力が変わらないこと（今のサンプルとマニュアルは語彙の値だけを使い、同じ意味で読まれるため）。

### 自動テストにしない確かめ方

実装の後に、`golem new` の和文の雛形に、偶数ページが `["{meta.title}"]`、奇数ページが `["{heading.1.numbered}", "{heading.2.short?}"]` のマスターページを加えて PDF にし、ビューアーで、二行の柱が天の余白の中で版面に近い側に寄り、節のないページでは一行になることを目で確かめる。

## トレードオフ

文字列は語彙、配列は書式と型で分けるので、一行だけの書式でも `["..."]` と括弧を書く必要がある。
文字列に書式を書けるようにすると、語彙の名前の綴りの誤りが固定の文言として通ってしまう。
読みやすさより、[ADR 0014](0014-running-heads.md) が防いだ誤りを防ぎ続けることを優先した。

差し込みの値がない行を丸ごと描かない規則にしたので、`["{meta.title}　{heading.1.short}"]` は最初の章より前のページで書名も出さない。
値のない差し込みだけを空にする規則にすると、「書名　」のように区切りの文字が残る行が既定になる。
書名だけでも出したい場合は、`?` を付けるか、二行に分ける。

`set` の変数をページのファイルから引くので、本の全体で同じ値を出すには、各ファイルで `@import` する手間がかかる。
`style.toml` に変数を書けるようにすると、本文と柱で同じ値を二か所に書く経路が増え、変数の言語が `style.toml` に入る。
今の `@set` と `@import` の規則の内側で済ませた。

行を重ねる向きを版面との空きが変わらない向きに固定したので、行を増やすと柱は天（または地）の端へ伸び、G0752 で止まることがある。
空きを指定するキーを足すと、柱だけの都合で版面の位置の決め方が二通りになる。

## 参考文献

- [golem-driver ADR 0014](0014-running-heads.md)（柱の内容の語彙と、柱を描かないページ）
- [golem-driver ADR 0013](0013-list-indents.md)（`{{` と `}}` による波括弧の書き方）
- TOML v1.0.0（配列と文字列） https://toml.io/en/v1.0.0
