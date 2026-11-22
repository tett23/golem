# ADR 0390: CFF の random を決定的に読み、とりうる値すべてで参照を確かめる

Status: superseded [{"part":"G08108 と G08109 の並べ方","by":["docs/adr/0394-order-cff-glyph-diagnostics-like-the-others.md"]}]

## 文脈

Type 2 の CharString には、擬似乱数を積む演算子 `random`（12 23）がある。
同梱の FreeType は、この乱数のシード値をメモリのアドレスから作る。
そのため、`random` を含む CFF のフォントでは、同じ入力から組んだ PDF のバイト列が実行ごとに変わる。
これは、出力を入力だけで決める決定性（[ADR 0002](0002-determinism.md)）に反する。

一方、[ADR 0357](0357-validate-embedded-cff.md) の参照の確かめ（`Golem.Font.Cff`）は、`random` に出会うとそのグリフを壊れたものとして扱い、それ以上たどらない。
そのため、`random` の後にある参照は、表の外を指していても G08107 にならない。

tett23 は、2026-11-17 と 2026-11-18 に次のとおり決めた。

- シード値を固定して決定性を保ち、v1 で対応する。
- OpenType と CFF の仕様には厳密に従う。
- CFF のフォントのグリフの寸法は、すべてグリフごとに開き直した face で読む。読む時間が延びるのは、入稿のための組版では問題にしない。
- 参照の確かめは、`random` がとりうる値すべてで行う。
- FreeType が寸法を読めないグリフは、新しいコードのエラーにする。
- 演算子の数の上限に達して確かめきれないグリフは、`random` によらず G08108 にする。

## 調査した事項

コードは、origin/main の [`ce6ae0e3`](https://github.com/tett23/golem/tree/ce6ae0e3cf8c5db4115553521d984d09d7945491) を読んだ。
動かして確かめたのは「実際に動かした結果」の項目で、auditor（Fable 5.2）が 2026-11-18 に、同梱の FreeType を cabal と同じフラグでビルドした小さなプログラムと、`random` を含むように書き換えた試験用のフォントで確かめた。
PDF を組んだ実験だけは、HEAD が `825e4734` の worktree にあったビルドの `golem` で動かした。
`825e4734` と `ce6ae0e3` のあいだで、`modules/golem-font`、`modules/golem-pdf` と `FontProvider.hs` に差分は無い。

### 仕様

- Type 2 の CharString の仕様（Adobe Technical Note #5177）は、`random` を「範囲 `(0, 1]` の擬似乱数を返す」と定める。生成器もシード値も定めていない。
- 同じ仕様は、`callsubr` を「番号に偏りを足した位置の Subrs を呼ぶ」と定め、定義の無いサブルーチンを呼んだ結果は定めていない。
- CFF の仕様（Adobe Technical Note #5176）は、Private DICT の `initialRandomSeed`（演算子 12 19、既定値 0）を定める。値の使い方は定めていない。
- OpenType の CFF2 は、CharString の演算子から `random` を含む算術の演算子を除いている。

### FreeType（同梱の 2.15.0）

- ドライバのシード値は、`FT_Init_FreeType` のたびにメモリのアドレスから作る（[`cffobjs.c`](https://github.com/tett23/golem/blob/ce6ae0e3cf8c5db4115553521d984d09d7945491/modules/golem-font/cbits/freetype/src/cff/cffobjs.c#L1158-L1168)）。
- 各サブフォントの乱数の状態は、face を開く途中に一度だけ決まる（[`cffload.c`](https://github.com/tett23/golem/blob/ce6ae0e3cf8c5db4115553521d984d09d7945491/modules/golem-font/cbits/freetype/src/cff/cffload.c#L2105-L2137)）。
  - ドライバのシード値が 0 でなければ、それを使い、ドライバのシード値を一つ進める。
  - 0 なら、Private DICT の `initialRandomSeed` を使う。`initialRandomSeed` は、負なら符号を反転し、0 なら 987654321 にする（[`cffload.c`](https://github.com/tett23/golem/blob/ce6ae0e3cf8c5db4115553521d984d09d7945491/modules/golem-font/cbits/freetype/src/cff/cffload.c#L1943-L1946)）。
- 乱数の状態は、`random` を実行するたびに進み、グリフごとには戻らない。積む値は、状態の下位 16 ビットに 1 を足して 65536 で割った値で、範囲 `(0, 1]` に入る（[`psintrp.c`](https://github.com/tett23/golem/blob/ce6ae0e3cf8c5db4115553521d984d09d7945491/modules/golem-font/cbits/freetype/src/psaux/psintrp.c#L2249-L2265)）。
- `FT_Property_Set(library, "cff", "random-seed", ...)` を face を開く前に呼ぶと、ドライバのシード値を固定できる。`FT_Face_Properties` と `FT_Open_Face` の引数では、CFF の乱数の状態は変わらない。
- `FT_Init_FreeType` は `FT_Set_Default_Properties` を呼び（[`ftinit.c`](https://github.com/tett23/golem/blob/ce6ae0e3cf8c5db4115553521d984d09d7945491/modules/golem-font/cbits/freetype/src/base/ftinit.c#L230)）、`FT_Set_Default_Properties` は環境変数 `FREETYPE_PROPERTIES` を読んでドライバの性質を設定する（[`ftinit.c`](https://github.com/tett23/golem/blob/ce6ae0e3cf8c5db4115553521d984d09d7945491/modules/golem-font/cbits/freetype/src/base/ftinit.c#L111-L127)）。
- `callsubr`、`get`、`put`、`index`、`roll` は、引数を整数の型で受け取り、算術や `random` や `ifelse` が積んだ固定小数の型の値を受け取ると `Syntax_Error` で止まる（[`psstack.c`](https://github.com/tett23/golem/blob/ce6ae0e3cf8c5db4115553521d984d09d7945491/modules/golem-font/cbits/freetype/src/psaux/psstack.c#L145-L149)）。そのグリフの `FT_Load_Glyph` は失敗する。

### Golem

- Golem はフォントごとに `FT_Library` を一つ作り、`FT_Init_FreeType` で初期化して、face を一つ開く（[`golem_font.c`](https://github.com/tett23/golem/blob/ce6ae0e3cf8c5db4115553521d984d09d7945491/modules/golem-font/cbits/golem/golem_font.c#L42-L43)）。
- グリフの寸法は `FT_Load_Glyph` で読む（[`golem_font.c`](https://github.com/tett23/golem/blob/ce6ae0e3cf8c5db4115553521d984d09d7945491/modules/golem-font/cbits/golem/golem_font.c#L116-L130)）。読んだ値をメモ化せず、`lfInkBox` と埋め込みから同じグリフを何度も読む（[`FontProvider.hs`](https://github.com/tett23/golem/blob/ce6ae0e3cf8c5db4115553521d984d09d7945491/modules/golem-typeset/src/Golem/Typeset/FontProvider.hs#L157)、[`FontProvider.hs`](https://github.com/tett23/golem/blob/ce6ae0e3cf8c5db4115553521d984d09d7945491/modules/golem-typeset/src/Golem/Typeset/FontProvider.hs#L263)）。
- `FT_Load_Glyph` が失敗したグリフは、寸法が無いものとして、`/FontBBox` と幅の表から何も出さずに除かれる（同じ `FontProvider.hs` の 263 行）。
- 送り幅は hmtx と vmtx から来るので、`random` で変わらない。変わるのは輪郭から求める bbox である。コードを読んで確かめた範囲では、bbox は、PDF の `/FontBBox`、圏点の位置、二倍ダッシュ、表の罫、G07101 と G07126 に使う。
- `Golem.Font.Cff` は、`random` を `Malformed` にして、そのグリフをたどるのをやめる（[`Cff.hs`](https://github.com/tett23/golem/blob/ce6ae0e3cf8c5db4115553521d984d09d7945491/modules/golem-font/src/Golem/Font/Cff.hs#L452)）。0 での `div` と負の数の `sqrt` も `Malformed` である。一つのグリフの実行の数（数と演算子を合わせた数）の上限は 100000 で、上限を超えると、今は何も出さずにたどるのをやめる。呼び出しの深さの上限は 10 である。
- 同梱の HarfBuzz 15.1.0 は `random` を実装せず、知らない演算子として引数のスタックを空にする。その結果は決定的である。サブセットは `random` を元のバイトのまま残す。

### 実際に動かした結果

- 縦組みの本文 `山山山、山山山山。` を、「山」に `random` を入れたフォントで、別々のプロセスで 4 回組むと、PDF のバイト列は 4 回とも違った。違ったのは `/FontBBox` で、たとえば `[0 -79 1492 831]` と `[0 -79 1014 1456]` だった。終了コードは 0 で、diagnostic は出なかった。HTML、EPUB、テキスト、`pages.json` は 4 回とも同じだった。
- `FREETYPE_PROPERTIES=cff:random-seed=12345` で組むと、2 回とも同じ PDF になった。`cff:random-seed=777` では別の PDF になった。環境変数が出力を変えるので、[ADR 0002](0002-determinism.md) の環境変数についての決まりにも反する。
- シード値を固定しても、同じ face で同じグリフを 2 回読むと、別の bbox が返った（`(188,455,688,955)` と `(37,561,537,1061)`）。シード値が 0 でなければ、同じライブラリで 2 つめの face を開くと、別の bbox が返った。
- シード値を 0 にすると、同じライブラリで何度 face を開いても、最初の読み取りは同じ bbox を返した。`initialRandomSeed` の無いフォントでは、名前で引くフォントでも CID で引くフォントでも同じだった。
- `random` を座標に使うグリフに加え、`random` の前に 0 で割るグリフ、`random` の前に負の数の `sqrt` を置くグリフ、`random` を実行するグリフを seac の部品に持つグリフでも、同じ face で 2 回読むと別の bbox が返った。Golem の確かめは、これらのグリフで `random` に届かない。
- `random 1 mul callsubr` のように、`random` から作った値を `callsubr`、`get`、`index` の引数にしたグリフは、`FT_Load_Glyph` が失敗した。
- sfnt に包まれていない CFF のファイル（`CFF ` の表だけを取り出したもの）も、Golem の C の層で開け、FreeType の CFF ドライバが `random` を実行して、同じグリフを 2 回読むと別の bbox を返した。

## 実装すること

### FreeType の初期化

FreeType のライブラリを、環境変数を読まずに作る。

- `FT_Init_FreeType` の代わりに、malloc、realloc、free を呼ぶ自前の `FT_MemoryRec_` を渡して `FT_New_Library` で作り、`FT_Add_Default_Modules` でドライバを足す。`FT_Set_Default_Properties` は呼ばない。そのため、`FREETYPE_PROPERTIES` は Golem の出力を変えなくなる。
- 閉じるときは、`FT_Done_FreeType` ではなく `FT_Done_Library` を呼び、自前の `FT_MemoryRec_` を放す。
- face を開く前に、`cff` ドライバの `random-seed` を 0 にする。サブフォントの乱数の状態は、Private DICT の `initialRandomSeed` から決まり、それが 0 なら FreeType の既定の 987654321 から決まる。シード値 0 ではドライバのシード値が進まないので、同じライブラリで何度 face を開いても、同じ状態から始まる。
- 同梱の FreeType のソースは変えない。

### グリフの寸法

FreeType の CFF ドライバで開いたフォントのグリフの寸法は、すべて、そのグリフのために開き直した face で読む。
CFF ドライバで開いたかは、`FT_Get_Font_Format` が `CFF` を返すかで決める。
CFF2 のフォントもこれに入るが、CFF2 のフォントは読み込みで G08019 になるので、寸法を読まれない。
sfnt に包まれた CFF のフォントのほかに、sfnt に包まれていない CFF のファイルも、CFF ドライバで開くので当てる。

- 開き直す face は、そのフォントの `FT_Library` で、フォントのバイト列から開く。開く、読む、閉じるは、フォントごとのロック（`ft_lock`）の中で行う。
- 読んだ寸法は、フォントとグリフの番号ごとに一度だけ読み、フォントごとに持つ。そのため、値はフォントのバイト列とグリフの番号だけで決まり、読む順、読む回数、前に開いた face の数、スレッドによらない。
- TrueType ドライバで開いたフォント（TrueType の輪郭のフォント）は、今のまま読む。乱数を使わないので、何度読んでも同じ値になる。

### 寸法を読めないグリフ（G08109）

組版に使うグリフのうち、FreeType が寸法を読めないもの（`FT_Load_Glyph` が失敗するもの）を G08109 とする。

- フォントの種類によらず、すべてのフォントのグリフに当てる。
- G08109 は、dev でも prod でもエラーで、PDF を書かない。寸法の無いグリフを `/FontBBox` と幅の表から黙って除くと、出力が黙って変わるためである。
- 位置、出す段階、プリフライトで出すかは G08107 と同じとする。フォントとグリフの番号の組ごとに一度出し、フォントのパス、グリフの番号の順に並べる。
- G08107、G08108、G08109 は、互いに独立に出す。G08107 は今のとおりフォントごとに一つだが、G08107 が出ても、同じフォントのほかのグリフの G08108 と G08109 は出す。一つのグリフが G08107 と G08109 の両方に当たれば、両方出す。
- 表の構造の確かめで G08107 になったフォントでは、グリフの参照を確かめないので、G08108 は出ない。

G08109 のメッセージは次のとおりとする。

```text
フォントのグリフの寸法を読めません: <フォントのパス> のグリフ <番号>
```

### 参照の確かめ

`Golem.Font.Cff` は、`random` の値を区間として扱い、とりうる値すべてで参照を確かめる。

- 区間は、下端と上端に、それぞれ端を含むか（閉じているか）を持つ。端は無限大でもよい。`random` は仕様の範囲どおり `(0, 1]`（下端を含まず、上端を含む）を積む。
- `random` に由来しない値は、今のとおり一つの値（両端を含む、幅 0 の区間）である。
- 算術の演算子は、区間の演算で結果の区間と端の開閉を求める。

| 演算子 | 結果 |
| --- | --- |
| `add`、`sub`、`neg`、`abs`、`mul` | 区間の演算の結果 |
| `div` | 除数の区間が 0 を含まなければ、区間の演算の結果（除数の端が 0 に開いていれば、結果の端は無限大になる）。除数の区間が 0 を含むときは、下の決まりに従う |
| `sqrt` | 区間がすべて 0 以上なら各端の平方根。負の部分を含むときは、下の決まりに従う |

- 幅を持つ区間で、区間の中のどれかの値が今の `Malformed` の条件に当たれば、G08108 とする。条件は、0 での `div`、負の数の `sqrt`、スタックの深さを超える `index` の位置、負かスタックの深さを超える `roll` の数である。幅 0 の値は、今のとおり `Malformed` としてたどるのをやめる。
- 無限大の端を持つ区間を `mul` と `div` に使えば、G08108 とする。0 と無限大の積や無限大どうしの商の値を決めずに済ませるためである。
- 幅を持つ区間で G08108 にするのは、その後の参照を黙って確かめずに済ませないためである。仕様は 0 での `div`、負の数の `sqrt`、スタックの深さを超える `index` の結果を定めず、処理系によって続きを実行する。
- 比較と論理の演算子（`eq`、`and`、`or`、`not`）と `ifelse` で、区間によって結果が一つに決まらないときは、とりうる結果ごとに別の枝としてたどる。
- 幅を持つ区間を番号や位置に使う演算子（`callsubr`、`callgsubr`、`index`、`roll`、`get`、`put`）は、区間の下端の床から上端の天井までのすべての整数を、それぞれ別の枝としてたどる。整数への丸めは処理系で違いうるためである。端が無限大の区間を番号に使えば、INDEX の外を含むので G08107 とする。端が無限大の区間を位置に使えば、G08108 とする。幅 0 の値は、今のとおり 0 の方向へ丸める。
- `callsubr` と `callgsubr` では、各番号に偏りを足した位置がすべて INDEX の中にあるかを確かめる。どれか一つでも INDEX の外なら G08107 とする。すべて中にあれば、各番号のサブルーチンを別の枝としてたどる。
- 枝は、スタック、ステムの数、一時の配列、読む位置をそれぞれ持つ。そのため、呼ぶ先によってステムの数が変わり、hintmask の長さが変わる場合も、枝ごとに正しく読む。
- 枝は次の順にたどる。番号や位置は小さい順、`ifelse` は最初の引数を選ぶ枝が先、比較と論理は結果 0 の枝が先、`roll` は数の小さい順で、同じ数では量の小さい順である。最初に見つかった INDEX の外の参照を G08107 とし、それより先に G08108 の場合に当たれば G08108 とする。そのため、同じフォントからは同じ diagnostic が出る。
- 実行の数は、今のとおり、数（オペランド）と演算子をそれぞれ一つと数え、すべての枝を足す。実行の数が上限（100000）を超えた時点で G08108 とする。100001 個めが `endchar` でも同じである。
- `random` を壊れたものとして扱うのをやめる。

### 確かめきれないグリフ（G08108）

参照を確かめきれないグリフを G08108 とする。
確かめきれない場合は、実行の数が上限を超えた場合と、上の「参照の確かめ」が G08108 とする場合である。

- `random` を含むかによらず、実行の数が上限を超えたすべてのグリフに当てる。今は上限を超えたグリフをそのまま埋め込んでいるが、確かめていない参照を持つフォントを黙って埋め込まないためである。
- G08108 は、dev でも prod でもエラーで、PDF を書かない。位置、出す段階、プリフライトで出すか、並べる順は G08109 と同じとする。
- G08107 は表の外を読む参照、G08108 は確かめきれない参照、G08109 は寸法を読めないグリフであり、原因が違うので別のコードにする。

G08108 のメッセージは次のとおりとする。

```text
CFF の参照を確かめきれません: <フォントのパス> のグリフ <番号>
```

### 文書

- 仕様書の「決定性」の節と「固定する依存」の節に、FreeType の乱数のシード値と、環境変数を読まないことを書く。
- 仕様書の、CFF の表の参照の確かめの段落（「CFF の表があるフォントは」で始まる段落）の「random の値で決まる参照は、たどらない」を、この ADR の確かめに書き換え、G08108 と G08109 を書く。同じ文の seac の部品は、今のまま残す。
- README の G08107 の段落に、G08108 と G08109 を書く。
- `docs/diagnostics.md` と、その埋め込み（`golem explain`）に G08108 と G08109 を足す。
- マニュアルの diagnostic の付録に G08108 と G08109 を足す。

## 実装しないこと

- 同梱の FreeType と HarfBuzz のソースを変えること。
- HarfBuzz に `random` を実装させること。HarfBuzz の結果は決定的なので、決定性を損なわない。
- PDF のビューアーが `random` をどう描くかを決めること。ビューアーの生成器は Golem の外にある。
- `random` を含むフォントを、それだけでエラーにすること。`random` は仕様にある演算子である。
- seac の部品のグリフの参照を確かめること。ロードマップの未決事項「CFF の seac の部品のグリフの確かめ」のまま残す。
- `random` に由来しない値の 0 での `div`、負の数の `sqrt`、呼び出しの深さの上限で止まる今の扱い（`Malformed`）を変えること。
- 一時の配列（32 要素）の外の位置に `get` と `put` をする今の扱いを変えること。
- CFF2 の `random`。CFF2 には `random` が無い。
- sfnt に包まれていない CFF のファイルの参照の確かめと埋め込み。今は HarfBuzz の表で CFF かを決めるので、このファイルは参照の確かめを通らない。寸法の読み方だけをこの ADR で決める。

## 不変条件

以下で、`c` を Subrs の項目の数、`b` を偏り（`c` が 1240 より小さければ 107）とする。
CharString に書く番号 `v` は、`0 <= v + b < c` のとき INDEX の中にある。
`n = c - b - 1` を、書ける番号の上限とする。
境界の表の CharString は、`random k mul callsubr` の形（書く番号の区間が `(0, k]` で、確かめる番号が 0 から `k`）とする。

- I1: CFF ドライバで開いたフォントの同じバイト列と同じグリフの番号について、Golem が読むグリフの寸法は、読む順、読む回数、前に開いた face とフォントの数、スレッド、環境変数 `FREETYPE_PROPERTIES` によらず等しい。
- I2: `modules/golem-font/cbits/golem/` の C のソースは、`FT_Init_FreeType` と `FT_Set_Default_Properties` を呼ばない。
- I3: `random` を含むフォントを使う同じ入力から、別々のプロセスで組んだ PDF のバイト列は等しい。
- I4: `random` を実行しないグリフの寸法は、フォントの種類によらず、この ADR の前と等しい。
- I5: 区間でたどって求めたすべての番号の位置が INDEX の中にあり、G08108 の場合に当たらないグリフには、G08107 も G08108 も出ない。
- I6: 区間でたどって求めた番号のどれかの位置が INDEX の外にあり、それを見つける前に G08108 の場合に当たらないグリフには、G08107 が出る。
- I7: 参照を確かめるグリフに G08108 が出ることと、そのグリフが G08107 より先に G08108 の場合に当たることは同値である。
- I8: 組版に使うグリフに G08109 が出ることと、FreeType がそのグリフの寸法を読めないことは同値である。
- I9: G08107、G08108、G08109 のどれかが出たビルドは、dev でも prod でも PDF を書かない。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| `random` を含まず、実行の数が上限を超えず、FreeType が読めるフォント | 寸法も diagnostic もこの ADR の前と同じ | I4, I5 |
| `random` を使うが、番号に届かない | 出ない | I5 |
| `k` が `n` より小さい | 出ない | I5 |
| `k` がちょうど `n` | 出ない | I5 |
| `k` が `n` より 1 大きい | G08107 | I6 |
| `random` で選ぶ `ifelse` の片方の枝だけが INDEX の外を呼ぶ | G08107 | I6 |
| 区間で選ぶ二つのサブルーチンで、ステムの数が違う | 両方の枝の hintmask を正しく読み、出ない | I5 |
| 実行の数の合計がちょうど上限 | 出ない | I5, I7 |
| 実行の数の合計が上限より一つ多い | G08108 | I7, I9 |
| `random` を含まず、実行の数の合計が上限より一つ多い | G08108 | I7, I9 |
| `1 random div callsubr` | G08107 | I6 |
| `random 0.5 sub` で割る | G08108 | I7, I9 |
| `random 0.5 sub sqrt` | G08108 | I7, I9 |
| スタックに 4 つ以上あるとき `random 3 mul index` | 位置 0 から 3 の枝をたどる | I5 |
| Subrs が 109 個以上のフォントで `random 1 mul callsubr` のグリフを組版に使う | G08109 だけ | I8, I9 |
| sfnt に包まれていない CFF のファイルの同じグリフを 2 回読む | 寸法が等しい | I1 |
| `FREETYPE_PROPERTIES=cff:random-seed=777` を与えて読む | 与えないときと寸法が等しい | I1 |
| 同じグリフの寸法を 2 回読む | 等しい | I1 |
| グリフを読む順を入れ替える | 寸法が等しい | I1 |
| ほかのフォントを先に開いてから読む | 寸法が等しい | I1 |
| 2 つのスレッドから同時に読む | 寸法が等しい | I1 |
| 同じ入力を別々のプロセスで 4 回組む | 同じ PDF | I3 |

## 受けいれ条件

- A1: リポジトリにあるすべてのフォント（書き換えた試験用のフォントを除く）のすべてのグリフに、G08108 と G08109 が出ず、`random` を実行するグリフが無い。

## テスト設計

テストの名前は `ADR 0390 I<n>: ` で始める。
テストは、確かめる水準ごとに入力を分ける。

- I5、I6、I7 の参照の確かめは、`modules/golem-font/test/CffSpec.hs` の `synthetic` のように、CharString と Subrs を並べて作る CFF の表で、`checkCffTable` を確かめる。`k` と `n` を小さい整数の範囲で数え尽くし、G08107 が出ることと `k > n` が同値であることを確かめる。境界の表の行を、それぞれ一つのケースとして書く。
- I1、I3、I8 の寸法と組版は、リポジトリにある CFF のフォントのグリフの CharString を、同じ長さのまま書き換えたフォントで確かめる。書き換えの手順はテストのコードの中に書き、生成したフォントもテストのデータとしてコミットする。寸法に使うグリフは、FreeType が読める形（`random` を座標に使う形）にする。
- I1 は、同じグリフの寸法を次の読み方で読み、すべて等しいことを確かめる。同じフォントで 2 回読む。別の順で読む。2 つのスレッドから読む。別々に開いた 2 つのフォントで読む。ほかのフォントを先に開いてから読む。sfnt に包まれていない CFF のファイルで読む。`FREETYPE_PROPERTIES=cff:random-seed=777` を与えた別のプロセスで読む。
- I2 は、`modules/golem-font/cbits/golem/` の下のソースを検索し、二つの名前が無いことを確かめるテストである。同梱の FreeType のソースは検索の対象から除く。
- I3 は、golem-cli のテスト（`golem` の実行ファイルを使える）で、`random` を含むフォントの原稿を、`golem` を 4 つの別々のプロセスで動かして組み、PDF のバイト列が等しいことを確かめる。4 つのうち一つには `FREETYPE_PROPERTIES=cff:random-seed=777` を与える。実装の前は、`/FontBBox` が違って失敗する。
- I4 は、リポジトリにあるすべてのフォント（書き換えた試験用のフォントを除く）のすべてのグリフの寸法が、実装の前のコミットで作った golden と等しいことを確かめる。このテストは実装の前から通るので、先に失敗させる手順の例外とする。
- I7 は、`a b random random ifelse` を並べて枝の数を増やしたグリフ、`random` を含まずに数と演算子を並べたグリフ、幅を持つ区間の `div` と `sqrt` のグリフで確かめる。
- I8 と I9 は、golem-cli のテストで `golem build` を dev と prod で動かし、G08107、G08108、G08109 のそれぞれで PDF を書かないことを確かめる。
- A1 は、リポジトリにあるすべてのフォント（書き換えた試験用のフォントを除く）のすべてのグリフで、参照の確かめと FreeType の読み取りを行い、G08108 と G08109 が出ず、`random` を実行するグリフが無いことを確かめる。

## トレードオフ

- CFF ドライバで開くフォントは、グリフごとに face を開き直すので、そのフォントを読む時間が延びる。同梱の FreeType を `-O2` でビルドした C のプログラムで、Haskell の層を通さずに測ると、Noto Serif JP（6210492 バイト）の 3000 グリフで、共有の face では 61.5 ms、開き直すと 1526.2 ms（1 グリフあたり 0.509 ms）だった。Source Sans Pro の 1900 グリフでは、11.8 ms と 150.0 ms だった。
- 区間でたどる確かめは、整数への丸め方の違いと値どうしの相関の消失を含めて広く確かめるので、ビューアーによっては届かない番号まで INDEX の中にあることを求める。そのぶん、正しく組めるフォントを G08107 にすることがありうる。
- Golem が読む寸法は FreeType の固定のシード値によるもので、ビューアーが描く形とは一致しないことがある。
- 実行の数の上限で確かめを打ち切り、幅を持つ区間の `div` と `sqrt` も G08108 にするので、仕様に合っていても確かめきれないフォントは G08108 になる。今まで通っていた、上限を超えるグリフを持つフォントも G08108 になる。
- 算術で作った番号でサブルーチンを呼ぶグリフは、仕様に合っていても FreeType が読めないので、G08109 になる。

## 参考文献

- Adobe Systems, *The Type 2 Charstring Format*, Technical Note #5177, 16 March 2000. https://adobe-type-tools.github.io/font-tech-notes/pdfs/5177.Type2.pdf
- Adobe Systems, *The Compact Font Format Specification*, Technical Note #5176, 4 December 2003. https://adobe-type-tools.github.io/font-tech-notes/pdfs/5176.CFF.pdf
- Microsoft, *CFF2: Compact Font Format (version 2) table*, OpenType specification. https://learn.microsoft.com/en-us/typography/opentype/spec/cff2
- [ADR 0002](0002-determinism.md)
- [ADR 0357](0357-validate-embedded-cff.md)
