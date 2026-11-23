# ADR 0420: 埋め込む CFF の seac の部品のグリフも確かめる

Status: accepted

## 文脈

[ADR 0357](0357-validate-embedded-cff.md) は、PDF に埋め込む CFF のフォントについて、使うグリフの CharString とサブルーチンを確かめると決めた。
CharString には、`endchar` の引数で別の二つのグリフ（基底の字とアクセント）を合成する形（seac）がある。
今の確かめは、seac の部品のグリフをたどらない。

一方、サブセットを作る HarfBuzz は、seac の部品のグリフをサブセットに入れる。
そのため、確かめていない部品のグリフの CharString が PDF に入る。
tett23 は 2026-11-18 に、seac の部品もたどって確かめることを決めた。

## 調査した事項

`origin/main`（`2ac7fb273`）と、HarfBuzz と FreeType のソースで確かめた。

- CharString を走らせる確かめは、`endchar`（演算子 14）で [`Went c`](https://github.com/tett23/golem/blob/2ac7fb273d6e26d3b42d57eef76f8f1ddd0634e2/modules/golem-font/src/Golem/Font/Cff.hs#L533) を返して終わり、スタックの引数（seac の `adx ady bchar achar`）を読まない。
- 仕様書は「endchar の引数で別のグリフを合成する形（seac）の部品のグリフは、たどらない」と書く（[docs/specifications.md](../specifications.md) の 4669 行）。
- ロードマップの未決事項は、「部品のグリフは StandardEncoding の文字のコードと charset から求める」と書く。
- [ADR 0390](0390-deterministic-and-exhaustive-cff-random.md) は seac を明示して扱いの外に残した。
  同じ ADR は、seac の部品で `random` を走らせると FreeType の外接矩形が揺れたことを記録している。
- サブセットは HarfBuzz の hb-subset で作る（`HB_SUBSET_FLAGS_RETAIN_GIDS`）。
  hb-subset は、`_add_cff_seac_components` で seac の部品を残すグリフに足す（`hb-subset-plan.cc`）。
- FreeType は、部品の中の seac（入れ子）を拒む（`cffdecode.c`）。

## 実装すること

- 確かめで `endchar` を読むとき、幅の引数を除いたスタックの引数の数で形を決める（FreeType の `psintrp.c` と同じ読み方）。
  - 0 個：ふつうの `endchar` である。
  - 4 個：seac である。スタックの上から `achar`、`bchar`、`ady`、`adx` とする。
  - それ以外：seac の引数の誤り（G08114）とする。
- seac の `bchar` と `achar` を StandardEncoding の文字のコードとして読み、その字の名前の SID を charset で引いてグリフの番号を得る。
- 引いた二つのグリフの CharString とサブルーチンを、使うグリフと同じ規則（G08107、G08108）で確かめる。
- seac の引数が `random` の結果に依るときは、[ADR 0390](0390-deterministic-and-exhaustive-cff-random.md) と同じく、とりうる値すべての部品をたどる。
  たどりきれないときは、G08108 とする。
- 次の場合は、新しいエラーのコードで PDF を出さない。

| コード | 原因 |
| --- | --- |
| G08114 | seac の引数の誤り（幅を除いた引数が 0 個でも 4 個でもない、`bchar` か `achar` が 0〜255 の整数でない） |
| G08115 | seac の `bchar` か `achar` の StandardEncoding の字がない（`.notdef` に当たる）か、その字がフォントの charset にない |
| G08116 | seac の部品のグリフが、また seac を含む（入れ子） |
| G08117 | CID を keyed にした CFF で seac を使う（charset が CID を並べるので、字の名前で部品を引けない） |

- G08117 は、FreeType が CID を keyed にしたフォントの seac を誤りにすることに合わせる。
  HarfBuzz は SID を CID として引くので、別のグリフを部品にしうる。
- 新しいコードの位置、出す単位、並べ方、プリフライトでの扱いは、G08107 と同じ規則（位置は `style.toml` の先頭、フォントとグリフの番号の組ごとに一度、[ADR 0394](0394-order-cff-glyph-diagnostics-like-the-others.md) の並べ方、プリフライトでも出す）にする。
- サブセットの作り方は変えない（すでに部品を含む）。
- 仕様書の 4669 行を、部品をたどる振る舞いに直し、ロードマップの未決事項の項目を消す。
- 新しいコードを `docs/diagnostics.md` に足し、組み込みの写しを作り直す。
- 採択したら、[ADR 0357](0357-validate-embedded-cff.md) のステータスの行に、部分「確かめる対象のグリフ」をこの ADR による補足として足す。

## 実装しないこと

- 使わないグリフ（seac の部品でもないもの）は、今と同じく確かめない。
- CFF2 は変えない（CFF2 には seac がない）。
- Type 1 のフォントは扱わない。

## 不変条件

「部品」は、使うグリフの seac が指す二つのグリフとする。

- I1：使うグリフの部品の CharString かサブルーチンが、G08107 か G08108 の条件に当たるどの入力からも、PDF を発行しない。
- I2：seac の引数が上の表の原因に当たるどの入力でも、diagnostic はその行のコードをちょうど一つ含み、PDF を発行しない。
- I3：seac を含まないフォントの diagnostic と PDF は、この ADR の前と同じである。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| 部品がどちらも正しい seac | PDF を出す | I1, I3 |
| 基底の字の部品の CharString が表長を超える | G08107、PDF なし | I1 |
| アクセントの部品のサブルーチンが壊れている | G08108、PDF なし | I1 |
| `bchar` が 256 | G08114 | I2 |
| `achar` の字が charset にない | G08115 | I2 |
| 部品が seac を含む | G08116 | I2 |
| 幅を除いた引数が 2 個 | G08114 | I2 |
| `bchar` が 0（StandardEncoding で字がない） | G08115 | I2 |
| CID を keyed にした CFF の seac | G08117 | I2 |
| `bchar` が `random` の結果で、とりうる部品がどれも正しい | PDF を出す | I1 |
| seac を含まないフォント | 前と同じ | I3 |

## 受けいれ条件

なし。
この ADR の振る舞いは、不変条件のテストで確かめる。

## テスト設計

- golem-font の `CffSpec.hs` と golem-driver の `PdfSpec.hs` に、境界の表の行ごとのテストを置く。
  名前は `root ADR 0420 I<番号>: ...` とする。
- 入力のフォントは、Source Sans Pro の CharString をその場で書き換えて作る（[ADR 0390](0390-deterministic-and-exhaustive-cff-random.md) の `RandomFontSpec.hs` と同じ方法）。
- I1 は、基底とアクセントのそれぞれで、表長の境界（ちょうど収まる、一つあふれる）の入力を作って確かめる。
- I3 は、今の [ADR 0357](0357-validate-embedded-cff.md) と [ADR 0390](0390-deterministic-and-exhaustive-cff-random.md) のテストが変わらずに通ることで確かめる。
- テストは、実装の前に失敗することを確かめてから実装する。

## トレードオフ

seac を使う古いフォントで、今まで PDF を出せていたものが、部品の誤りで出せなくなることがある。
確かめていない CharString を PDF に入れるより、止めるほうが厳しい側に倒す方針に合う。

## 参考文献

- [ADR 0357](0357-validate-embedded-cff.md)
- [ADR 0390](0390-deterministic-and-exhaustive-cff-random.md)
- [ADR 0394](0394-order-cff-glyph-diagnostics-like-the-others.md)
- Adobe Technical Note #5177, The Type 2 Charstring Format（endchar の seac の形）
