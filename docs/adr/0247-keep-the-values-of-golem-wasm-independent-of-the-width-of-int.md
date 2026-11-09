# ADR 0247: golem.wasm の値を `Int` の幅に依らせない

ステータス: 採択→7 の `int-width-icc` で見るもの、I3 のストリームの番号の上限（2^31 以上を G08020 で拒む）は [ADR 0259](0259-record-what-the-audit-of-the-ci-release-and-tooling-adrs-found-on-2026-11-09.md)

## 文脈

### [ADR 0245](0245-keep-the-warnings-of-ci-at-zero.md) が残したもの

[ADR 0245](0245-keep-the-warnings-of-ci-at-zero.md) は、golem のパッケージを `-Werror` でビルドする。
wasm のビルドにだけ出る `-Woverflowed-literals` が 3 か所あり、それを直すまで、[ADR 0245](0245-keep-the-warnings-of-ci-at-zero.md) の 1 は wasm のビルドを壊す。
[ADR 0245](0245-keep-the-warnings-of-ci-at-zero.md) は、この 3 か所を別の ADR で直すと決めた（「メンテナーが決めること」の 2）。
この ADR は、その別の ADR である。

### wasm32 の `Int`

[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md) の `golem.wasm` は、wasm32 の GHC でビルドする。
wasm32 の GHC の `Int` は 32 ビットである（[ADR 0202](0202-packages-that-do-not-build-for-wasm.md)、[ADR 0223](0223-emet-sizes-before-building-values.md)）。
ネイティブのビルド（x86-64、aarch64）の `Int` は 64 ビットである。
[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md) は、wasm で組んだ PDF と diagnostics が、ネイティブのものと一致することを保証する。
`Int` の幅で値が変わるコードは、この保証を破る。

32 ビットの `Int` は、`Int32` と同じく、2 の補数で折り返す。
整数のリテラルは `fromInteger` で 2^32 を法として丸められ、`shiftL` は 32 以上のずらしで 0 になる。
この ADR の再現は、この性質を使い、`Int` を `Int32` に置き換えた写しのコードをネイティブで動かして得た。
wasm のツールチェーン（`scripts/fetch-ghc-wasm.sh`）は x86-64 の Linux の向けだけなので、手元の macOS では `golem.wasm` を組めなかった。
CI の wasm のジョブでの確認は、実装のプルリクエストで行う（「テスト設計」）。

### 調べた範囲

`cabal.project.wasm` の `packages:` にある 24 の golem のパッケージの `src/` を、次の形で探した（`main` の 0cd8798d）。

- `maxBound :: Int` と `minBound :: Int`
- 8 桁以上の 16 進のリテラルと、10 桁以上の 10 進のリテラル
- 2 の 31 乗以上の冪と、31 以上のずらし
- `Int64`、`Word64`、`finiteBitSize`
- golem-pdf の `Import.hs` と `Image.hs` の、`Integer` から `Int` への `fromInteger`（外から来るバイト列を読むモジュールなので、一つずつ読んだ）

ほかのモジュールの `fromIntegral` と `fromInteger`（あわせて約 200 か所）は、一つずつは読んでいない。

### 値が変わる箇所

| 箇所 | ネイティブ | wasm32 | warning |
| --- | --- | --- | --- |
| ASCII85 の検査（[`Import.hs#L932`](https://github.com/tett23/golem/blob/0cd8798d34137b2ac9fc518bf4b208f310fb9d1f/modules/golem-pdf/src/Golem/Pdf/Import.hs#L932)、[`#L939`](https://github.com/tett23/golem/blob/0cd8798d34137b2ac9fc518bf4b208f310fb9d1f/modules/golem-pdf/src/Golem/Pdf/Import.hs#L939)） | 組の値が 2^32 − 1 以下なら通す | `0xFFFFFFFF` が −1 になり、値が 0 以上 2^31 未満の組を退ける | 出る |
| inner Form のキー（[`Import.hs#L1121`](https://github.com/tett23/golem/blob/0cd8798d34137b2ac9fc518bf4b208f310fb9d1f/modules/golem-pdf/src/Golem/Pdf/Import.hs#L1121)） | −(k × 2^32 + n) | `4294967296` が 0 になり、ページ n のすべての inner Form が −n になる | 出る |
| 内容のストリームの形の状態（[`Import.hs#L1446-L1457`](https://github.com/tett23/golem/blob/0cd8798d34137b2ac9fc518bf4b208f310fb9d1f/modules/golem-pdf/src/Golem/Pdf/Import.hs#L1446-L1457)） | marked content の深さを 34 ビットめから数える | `1 shiftL 34` が 0 になり、深さを数えない。どの `EMC` も対のない `EMC` になる | 出ない |
| 間接参照の番号（[`Import.hs#L365`](https://github.com/tett23/golem/blob/0cd8798d34137b2ac9fc518bf4b208f310fb9d1f/modules/golem-pdf/src/Golem/Pdf/Import.hs#L365)） | 18 桁までの番号をそのまま持つ | 2^32 を法として丸める。`4294967297 0 R` は object 1 を指す | 出ない |
| `ICCBased` の `/N`（[`Import.hs#L1352`](https://github.com/tett23/golem/blob/0cd8798d34137b2ac9fc518bf4b208f310fb9d1f/modules/golem-pdf/src/Golem/Pdf/Import.hs#L1352)） | そのまま持つ | 2^32 を法として丸める。`/N 4294967299` は 3（RGB）になる | 出ない |
| PNG の IHDR の幅と高さ（[`Image.hs#L67-L68`](https://github.com/tett23/golem/blob/0cd8798d34137b2ac9fc518bf4b208f310fb9d1f/modules/golem-pdf/src/Golem/Pdf/Image.hs#L67-L68)、[`#L119`](https://github.com/tett23/golem/blob/0cd8798d34137b2ac9fc518bf4b208f310fb9d1f/modules/golem-pdf/src/Golem/Pdf/Image.hs#L119)） | 2^31 以上を IHDR の誤りとして退ける | 2^31 以上が負の数になり、検査を通る | 出ない |
| PNG のチャンクの長さ（[`Image.hs#L268-L277`](https://github.com/tett23/golem/blob/0cd8798d34137b2ac9fc518bf4b208f310fb9d1f/modules/golem-pdf/src/Golem/Pdf/Image.hs#L268-L277)） | 残りより長ければ「途中で切れています」 | 2^31 以上 2^32 − 13 以下の長さが負の数になり、同じ位置を読み直し続けて止まらない | 出ない |
| `inInt64`（[`IR.hs#L65-L66`](https://github.com/tett23/golem/blob/0cd8798d34137b2ac9fc518bf4b208f310fb9d1f/modules/golem-doc/src/Golem/Doc/IR.hs#L65-L66)） | −2^63 以上 2^63 − 1 以下 | −2^31 以上 2^31 − 1 以下。`@number 2147483648` が G02091 になる | 出ない |
| `naturalIntOf`（[`Manifest.hs#L754-L757`](https://github.com/tett23/golem/blob/0cd8798d34137b2ac9fc518bf4b208f310fb9d1f/modules/golem-project/src/Golem/Project/Manifest.hs#L754-L757)）と `[index]` の `columns`（[`Style.hs#L1976`](https://github.com/tett23/golem/blob/0cd8798d34137b2ac9fc518bf4b208f310fb9d1f/modules/golem-project/src/Golem/Project/Style.hs#L1976)） | 2^63 − 1 まで通す | 2^31 − 1 まで通す | 出ない |

`naturalIntOf` は、`printings` の版と刷、`[page.grid]` の `characters`、`lines`、`columns`、見出しのスタイルの `lines` が使う。

warning が出るのは 3 か所だけである。
[ADR 0245](0245-keep-the-warnings-of-ci-at-zero.md) の `-Werror` は、ほかの 6 か所を見つけない。

### 再現

`Int32` に置き換えた写しの結果は、次のとおりである。
ASCII85 の検査は、`ascii85` の `check` を、`Int` を型の引数にして写した。

| 入力 | `Int64` | `Int32` |
| --- | --- | --- |
| `<~9jqo^~>` | 4 バイト | 退ける |
| `<~!!!!!~>`（値 0） | 4 バイト | 退ける |
| `<~s8W-!~>`（値 2^32 − 1） | 4 バイト | 4 バイト |
| `<~s8W-"~>`（値 2^32） | 退ける | 退ける |
| `<~z~>` | 4 バイト | 4 バイト |
| `<~9jqo~>`（最後の組が 4 文字） | 3 バイト | 退ける |
| `mkUnit` | 17179869184 | 0 |
| ページ 1 の k = 3 と k = 7 の inner Form のキー | −12884901889 と −30064771073 | −1 と −1 |
| IHDR の幅 `80 00 00 00` | 2147483648、退ける | −2147483648、通す |
| チャンクの長さ `80 00 00 00` | 「途中で切れています」 | 2 秒で終わらない |
| `inInt64 2147483648` | 真 | 偽 |

ASCII85 の検査は、文字のある組の多くを退ける。
golem-pdf の今のテスト（`ImportSpec` の「ASCIIHex and ASCII85 decode the content」）の入力 `<~0Hb!80d(*~>` も、`Int32` の写しでは退けられた。
`decode` は、組の値の下の 32 ビットからバイトを取るので、検査を通った組では、ネイティブと同じバイトを書くと読める。

inner Form のキーが重なると、`formObjects`（[`Writer.hs#L846-L857`](https://github.com/tett23/golem/blob/0cd8798d34137b2ac9fc518bf4b208f310fb9d1f/modules/golem-pdf/src/Golem/Pdf/Writer.hs#L846-L857)）は、同じページの inner Form を一つの object にまとめる。
`Contents` が二つのストリームをそれぞれ二度ずつ指すページでは、二つめのストリームの名前も、一つめのストリームの Form を指す。
PDF は、壊れた内容で書かれる。

形の状態で `mkUnit` が 0 になると、`BDC` か `BMC` を持つストリームは、どれも閉じていない形になる（[`Import.hs#L1502-L1503`](https://github.com/tett23/golem/blob/0cd8798d34137b2ac9fc518bf4b208f310fb9d1f/modules/golem-pdf/src/Golem/Pdf/Import.hs#L1502-L1503)）。
`Contents` が同じストリームを二度以上指すページは、ネイティブでは inner Form で一度だけ書き、wasm32 ではつないで書く（[`Import.hs#L1197-L1201`](https://github.com/tett23/golem/blob/0cd8798d34137b2ac9fc518bf4b208f310fb9d1f/modules/golem-pdf/src/Golem/Pdf/Import.hs#L1197-L1201)）。
PDF のバイト列が変わる。

`inInt64` のずれは、マニュアルとも合わない。
マニュアルは、`@number` に渡せる整数を「0 以上、2 の 63 乗未満」とする（`manual/appendices/a-markup.gm` の 471 行め）。

### 値が変わらない箇所

次の箇所は、`Int` の幅に関わるが、値は変わらない。

| 箇所 | 理由 |
| --- | --- |
| golem-emet の `count`（[`Prim.hs#L168`](https://github.com/tett23/golem/blob/0cd8798d34137b2ac9fc518bf4b208f310fb9d1f/modules/golem-emet/src/Golem/Emet/Prim.hs#L168)） | `maxBound :: Int` で頭打ちにする。wasm32 のリストと文字列は 2^31 − 1 より短いので、`take`、`drop`、`at` の結果は同じになる |
| golem-emet の `filterFuel`（[`Gm.hs#L159-L163`](https://github.com/tett23/golem/blob/0cd8798d34137b2ac9fc518bf4b208f310fb9d1f/modules/golem-emet/src/Golem/Emet/Gm.hs#L159-L163)） | [ADR 0223](0223-emet-sizes-before-building-values.md) が `Int64` にした |
| SHA-1 と SHA-256 の定数 | `Word32` である |
| sRGB のプロファイルの `fixed` | `Int32` を経て `Integer` で求める |
| Knuth-Plass の `filStretch`（2^50） | `Sp` は `Integer` である |
| フォントのサブセットの名前のハッシュ | `Word64` である |
| 正規表現の量指定子 | 65535 以下に限ってから `Int` にする |
| `Golem.Wasm.Frame` の長さ | `Word32` である |
| `@blank-line` の行数 | `Int64` である |

## 実装すること

ネイティブ（64 ビット）の PDF と diagnostics を変えずに、wasm32 の値をネイティブに揃える。
ただし 6 は、ネイティブの diagnostics を変える。

### 1. ASCII85

`ascii85` の組の値と、`padded` の値を、`Int64` で求める。
上限の比べ（`> 0xFFFFFFFF`）も `Int64` で行う。
`decode` も同じ型で求め、バイトにするところで `Word8` にする。

### 2. 取りこむ PDF の object の番号

`Import` の中で、取りこむ PDF の object の番号を `Int64` で持つ。
間接参照（`VRef`）、相互参照と object のストリームの表のキー、`ImportedPage` の `ipObjects` のキー、取りこんだ object の参照、inner Form のキー（`innerKey`）が対象である。
`Writer` の `formObjects` は、そのキーを受け取り、書く PDF の番号（今の `Int`）に付け替える。
型の名前と形は、実装に任せる。
書く PDF の番号は、今のまま `Int` とする。

### 3. 内容のストリームの形の状態

`rewriteContentShaped` の状態の整数（`inTextBit` から `mkUnit`、`qDepth`、`mkDepth`）を `Int64` にする。
ビットの配置は変えない。

### 4. `ICCBased` の `/N`

`ColorUse` の `UseIcc` の成分の数を `Integer` にする。
golem-preflight の `UseIcc 1`、`UseIcc 3`、`UseIcc 4` の照合は、リテラルのまま動く。

### 5. PNG

`be32` の結果を `Int64` にする。
IHDR の幅と高さは、その型で 1 以上 2^31 − 1 以下かを確かめてから `Int` にする。
チャンクの長さは、その型で残りのバイト数と比べ、長ければ今と同じメッセージ（チャンクが途中で切れていること）で退ける。

### 6. 範囲の検査

golem-doc の `inInt64` を、`Int64` の `minBound` と `maxBound` で判定する。
注の「It is the range of 'Int' too」を消す。

golem-project の `naturalIntOf` と、`[index]` の `columns` の上限を、どのターゲットでも 2^31 − 1（`maxBound :: Int32`）にする（「メンテナーが決めること」の 2）。
値は `Int` で使うので、wasm32 で収まる範囲に、ネイティブも揃える。
メッセージは今のまま（`integer out of range for Int` と、`[index] の columns は 1 以上の整数です`）とする。

### 7. golem.wasm との比べ

`scripts/wasm/compare.sh` に、次の入力を足す。
fixture の PDF と PNG は、golem-driver の `test/fixtures/` に置く。

| 入力 | 中身 | 見ること |
| --- | --- | --- |
| `int-width` | PDF の図を一つ持つ本。図の PDF は、`/ASCII85Decode` の内容のストリームを持ち、`Contents` が `BDC` と `EMC` を持つストリーム二つを二度ずつ指す。番号付きのリストに `@number 2147483648` を付ける | PDF のバイト列と diagnostics |
| `int-width-reference` | 図の PDF の `Resources` が `4294967297 0 R` を持つ本 | PDF のバイト列と diagnostics |
| `int-width-icc` | 図の PDF が `/N 4294967299` の `ICCBased` を使い、preflight の規則で色を検査する本 | diagnostics |
| `int-width-png` | IHDR の幅が 2^31 の PNG の図を持つ本 | diagnostics と終了の状態 |
| `int-width-png-chunk` | チャンクの長さが 2^31 の PNG の図を持つ本 | diagnostics と終了の状態 |
| `int-width-printing` | `printings` の `edition` が 2147483648 の `manifest.toml` | diagnostics と終了の状態 |

`compare.sh` は、入力ごとに時間の上限を持ち、超えたら終了の状態を `exit timeout` と書く。
上限の値と仕組みは、実装に任せる。
止まらない入力で、CI のジョブが時間切れまで待たないためである。

### 8. 文書

`docs/specifications.md` の golem-wasm の節に、wasm32 の `Int` が 32 ビットであることと、値が `Int` の幅に依らないことを書き、この ADR へのリンクを付ける。
golem-project の仕様に、`naturalIntOf` の上限が 2^31 − 1 であることを書く。
マニュアルの `printings` と `[page.grid]` の説明に上限が書いてあれば、2^31 − 1 に直す。

## 実装しないこと

- 「調べた範囲」の外の `fromIntegral` と `fromInteger` を、一つずつ読むことはしない（「メンテナーが決めること」の 3）。
- golem のパッケージのテストのスイートを、wasm32 でビルドして走らせることはしない（「メンテナーが決めること」の 3）。
- `Int` の幅に依るコードを見つける検査のスクリプトは、作らない。`-Woverflowed-literals` は、[ADR 0245](0245-keep-the-warnings-of-ci-at-zero.md) の `-Werror` で wasm のビルドが見つける。
- 取りこむ PDF の object の番号の上限（ISO 32000 の付録 C の 8,388,607 など）を新しく設けることはしない。今の 18 桁を変えない。
- 書く PDF の object の番号の型は変えない。

## 不変条件

1. **I1**：`compare.sh` のどの入力でも、`golem.wasm` の PDF の SHA-256、diagnostics の SHA-256、終了の状態は、ネイティブの `golem` のものと等しい。
2. **I2**：ASCII85 の検査は、どのターゲットでも、すべての組の値が 2^32 − 1 以下で、最後の組が 1 文字でないとき、そのときに限り通す。通ったときのバイト列は、ターゲットによらない。
3. **I3**：一つのページの inner Form のキーは、どの二つも異なり、どのページの、取りこむ PDF の object の番号とも、ほかのページの inner Form のキーとも異なる。
4. **I4**：内容のストリームの形の `shClosed` は、どのターゲットでも、`q` と `Q`、`BMC` か `BDC` と `EMC` がそれぞれ対になっているとき、そのときに限り真である。
5. **I5**：間接参照 `n g R`（n は 18 桁以下）は、どのターゲットでも object n を指す。
6. **I6**：`ICCBased` の `/N` の値 v について、`UseIcc` の成分の数は v に等しい。
7. **I7**：PNG の IHDR は、幅と高さがともに 1 以上 2^31 − 1 以下のとき、そのときに限り通る。チャンクの長さが残りのバイト数より大きい PNG は、どの長さでも「途中で切れています」で退けられ、読み込みは終わる。
8. **I8**：`inInt64 n` は、どのターゲットでも、−2^63 ≤ n ≤ 2^63 − 1 のとき、そのときに限り真である。
9. **I9**：`naturalIntOf` は、どのターゲットでも、n ≤ 2^31 − 1 のとき、そのときに限り n を通す。

境界の入力：

| 入力 | I2 | I3、I4 | I5、I6 | I7 | I8 | I9 |
| --- | --- | --- | --- | --- | --- | --- |
| ASCII85 の空のストリーム（`<~~>`） | 0 バイト | | | | | |
| 値 0 の組（`!!!!!`） | 4 バイト | | | | | |
| `z` | 4 バイト | | | | | |
| 値 2^31 − 1 の組 | 4 バイト | | | | | |
| 値 2^31 の組 | 4 バイト | | | | | |
| 値 2^32 − 1 の組（`s8W-!`） | 4 バイト | | | | | |
| 値 2^32 の組（`s8W-"`） | 退ける | | | | | |
| 最後の組が 1 文字 | 退ける | | | | | |
| 最後の組が 4 文字 | 3 バイト | | | | | |
| 二度指すストリームが一つ | | inner Form が一つ | | | | |
| 二度指すストリームが二つ | | キーが二つ、異なる | | | | |
| `BDC` と `EMC` が一つずつ | | `shClosed` が真 | | | | |
| 対のない `EMC` | | `shClosed` が偽 | | | | |
| `BDC` が一つ、`EMC` がない | | `shClosed` が偽 | | | | |
| `1 0 R` | | | object 1 | | | |
| `4294967297 0 R` | | | object 4294967297 | | | |
| 18 桁の番号 | | | その番号 | | | |
| `/N 3` | | | 3 | | | |
| `/N 4294967299` | | | 4294967299 | | | |
| IHDR の幅 0 | | | | 退ける | | |
| IHDR の幅 1 | | | | 通す | | |
| IHDR の幅 2^31 − 1 | | | | 通す | | |
| IHDR の幅 2^31 | | | | 退ける | | |
| IHDR の幅 2^32 − 1 | | | | 退ける | | |
| チャンクの長さが残りとちょうど同じ | | | | 読む | | |
| チャンクの長さが残りより 1 大きい | | | | 退ける | | |
| チャンクの長さ 2^31 | | | | 退ける | | |
| チャンクの長さ 2^32 − 13 | | | | 退ける | | |
| チャンクの長さ 2^32 − 1 | | | | 退ける | | |
| n = 2^31 − 1 | | | | | 真 | 通す |
| n = 2^31 | | | | | 真 | 退ける |
| n = 2^63 − 1 | | | | | 真 | 退ける |
| n = 2^63 | | | | | 偽 | 退ける |
| n = −2^63 | | | | | 真 | |
| n = −2^63 − 1 | | | | | 偽 | |

I1 の比べは、7 の入力の全体に当てる。

## テスト設計

ネイティブの `Int` は 64 ビットなので、I2 から I8 のネイティブのテストは、今の実装でも通る。
これらは、型を変えたあとにネイティブの値が変わらないことを確かめる回帰のテストである。
先に失敗させるのは、wasm の比べ（I1）と、ネイティブの値を変える I9 である。

- **I1**：7 の入力を `compare.sh` に足すコミットを、実装より先にプルリクエストに積む。CI の wasm のジョブの比べが落ちることを確かめ、その実行の URL をプルリクエストに書く。`int-width-png-chunk` は、`exit timeout` の行で落ちる見込みである。そのあとに 1 から 6 を実装し、比べが通ることを確かめる。
- **I9**：golem-project のテストに、`printings` の `edition`、`[page.grid]` の `characters`、`lines`、`columns`、`[index]` の `columns` が 2^31 − 1 なら通り、2^31 と 2^63 − 1 なら退けられることを書く。2^31 の行は、今の実装では通るので、先に失敗する。テストの名前に I9 を入れる。
- **I2**：golem-pdf の `ImportSpec` に、境界の表の ASCII85 の行を足す。加えて、hedgehog で任意のバイト列を ASCII85 で書き、`ascii85` で読むと元に戻ることを確かめる。値 2^31 と 2^31 − 1 の組は、wasm32 で落ちる値なので、7 の `int-width` の図にも入れる。
- **I3、I4**：`ImportSpec` に、境界の表の行を足す。二度指すストリームが二つのページで、`ipObjects` の inner Form のキーが二つあり、異なることと、書いた PDF の二つの名前が別の object を指すことを確かめる。
- **I5、I6**：`ImportSpec` に、`4294967297 0 R` が object 1 を指さないことと、`/N 4294967299` の `UseIcc` の成分の数が 4294967299 であることを足す。
- **I7**：golem-pdf の画像のテストに、境界の表の PNG の行を足す。チャンクの長さの行は、`Golem.TestSupport.TimeLimit` の上限の中で終わることも確かめる。
- **I8**：golem-doc のテストに、境界の表の `inInt64` の行を足す。
- 各テストの名前に、不変条件の番号を入れる（[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md)）。
- 実装の後、[ADR 0245](0245-keep-the-warnings-of-ci-at-zero.md) の 1 を先に試し、wasm のビルドが `-Werror` で通ることを確かめる。これは [ADR 0245](0245-keep-the-warnings-of-ci-at-zero.md) の実装のプルリクエストで行う。

## トレードオフ

- `Int64` の演算は、wasm32 では 32 ビットの演算より遅い。ASCII85 の復号と内容のストリームの読み込みは、取りこむ PDF のバイト数に比例して遅くなる。ネイティブの速さは変わらない。
- 取りこむ PDF の object の番号の型を `Int` から変えると、`Import` の多くの型の注釈と、`Writer` の付け替えが変わる。差分は大きいが、ネイティブの値は変わらない。上限を 2^31 − 1 に下げれば型は変えずに済むが、ネイティブで読めていた PDF の一部を退けることになる。
- `naturalIntOf` の上限を下げると、ネイティブで 2^31 以上の版の番号や行の数を書いたプロジェクトが、エラーになる。2^31 行の格子や 2^31 版の本は、組めても意味がないので、実害はないと見込む。代わりに `Int64` で持てば上限を下げずに済むが、値を使うレイアウトの側の型も変わる。
- I1 は、`compare.sh` の入力でしか確かめない。「調べた範囲」の外に、幅に依るコードが残っていても見つけられない。
- I2 から I8 のネイティブのテストは、先に失敗しない。wasm32 での失敗は、CI の wasm のジョブでしか見えない。

## メンテナーが決めること

1. **取りこむ PDF の object の番号の型**：案 1 は `Int64` にすること、案 2 は `Integer` にすること、案 3 は `Int` のまま上限を 2^31 − 1 にすることである。推奨は案 1 である。今の 18 桁の番号がそのまま収まり、ネイティブの値も PDF のバイト列も変わらない。案 2 は、表のキーの比べが遅くなる。案 3 は、ネイティブで読めていた PDF を退ける。
2. **`naturalIntOf` と `[index]` の `columns` の上限**：案 1 はどのターゲットでも 2^31 − 1 にすること、案 2 はフィールドとレイアウトの側を `Int64` にすること、案 3 はこの ADR で扱わず、違いを docs/roadmap.md に書くことである。推奨は案 1 である。変更が小さく、[ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md) の diagnostics の一致が成り立つ。2^31 以上の値は、どれも組版の意味を持たない。
3. **調べていない変換と、wasm32 でのテスト**：推奨は、この ADR では扱わず、docs/roadmap.md に「golem のテストのスイートを wasm32 で走らせる」を足すことである。golem-pdf のテストの多くは純粋なので、wasm32 でビルドして Node の WASI で走らせれば、幅に依るコードを網羅的に見つけられる見込みがある。ただし、外部の道具（qpdf、Poppler など）を使うテストを分ける必要があり、別の ADR の大きさになる。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-09、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [ADR 0199](0199-pdf-typesetting-as-wasm-reactor.md)、[ADR 0202](0202-packages-that-do-not-build-for-wasm.md)、[ADR 0223](0223-emet-sizes-before-building-values.md)、[ADR 0245](0245-keep-the-warnings-of-ci-at-zero.md)
- [golem-doc ADR 0006](../golem-doc/adr/0006-integer-range-in-ir.md)
- GHC User's Guide, "Warnings and sanity-checking"（`-Woverflowed-literals`）: https://downloads.haskell.org/ghc/9.10.3/docs/users_guide/using-warnings.html
- GHC User's Guide, "WebAssembly backend": https://downloads.haskell.org/ghc/9.10.3/docs/users_guide/wasm.html
- base, `Data.Bits`（`shiftL` の、幅以上のずらし）: https://hackage.haskell.org/package/base/docs/Data-Bits.html
- Adobe, "PostScript Language Reference, third edition", 3.13.3 ASCII85Encode Filter
- ISO 32000-1:2008, 7.4.3 ASCII85Decode Filter, Annex C Implementation Limits
- W3C, "Portable Network Graphics (PNG) Specification (Third Edition)", 5.3 Chunk layout, 11.2.1 IHDR: https://www.w3.org/TR/png-3/
