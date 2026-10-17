# ADR 0014: 欧文の突き出しの量を字の幅から求める

ステータス: 採択

## 文脈

仕様書の「既知の不具合」の「ぶら下げの量」は、欧文の約物の突き出しの量を、字の幅ではなく語の箱全体の幅に対する割合で求めている不具合である。
[golem-layout ADR 0005](0005-microtypography.md) は、突き出しの量を「文字の幅に対する割合」の表で持つと定めている。
[docs/roadmap.md](../../roadmap.md) の「既知の不具合の修正」は、これを v0.1.0-rc3 の項目にし、行の端の字の送りに比を掛ける直し方を案として挙げている。

項目の名前は「ぶら下げ」だが、対象は和文の句読点のぶら下げ組（[golem-layout ADR 0002](0002-japanese-composition.md)）ではなく、`[composition]` の `protrusion` による欧文の突き出しである。
ぶら下げ組の量は、句読点の一字だけの箱の幅で決まるので、この不具合はない。
利用者のマニュアルの付録I も「ぶら下げ組で行末の外に出す句読点の量」と書いており、説明が実際の不具合と合っていない。

### 今の振る舞い

`Golem.Layout.Japanese` の `wordItems` は、欧文の語を、明示したハイフンとパターンの分綴の位置で箱に分ける。
各箱の突き出しの量は、次の式で決まる。

```haskell
w = round (ceWordAdvance env lk t * toRational (lkSize lk))   -- 箱の全体の送り
prot r = if ceProtrusion env then min w (w * r `div` 1000) else 0
```

`r` は、箱の最初の字と最後の字の `protrusionRatio`（千分率）である。
掛ける相手が字の送りではなく箱の全体の送り `w` なので、語が長いほど突き出しが大きくなる。

`defaultComposeEnv` の 10pt（655360sp）で、`protrusion` を有効にして確かめた（origin/main の e16ab1e、`cabal repl golem-layout`）。
欧文の字の送りは、既定の環境では 0.5em（327680sp）である。

| 語 | 箱の送り | 今の行末の突き出し | 字の幅による値 |
| --- | --- | --- | --- |
| `a.` | 655360 | 458752（7pt） | 229376（3.5pt） |
| `end.` | 1310720 | 917504（14pt） | 229376（3.5pt） |
| `well-`（`well-known` の前の部分） | 1638400 | 1146880（17.5pt） | 229376（3.5pt） |

`end.` のピリオドは、版面の外に 1.4 字分出ることになり、ピリオドの幅の 2.8 倍である。
上限の `min w` があるので語の幅を超えては出ないが、語の大部分が版面の外に出うる。

既存のテスト（`modules/golem-layout/test/Main.hs` の「protrusion of hyphens and full stops follows the table」）は、`bcProtrudeEnd c @?= w * 700 \`div\` 1000` と、語の箱の幅を基準にした値を期待している。
テストが実装を写しているので、ADR との食い違いを検出できなかった。

### 出力への影響

`protrusion = true` を書いた `style.toml` は、リポジトリの中にない。
golem-driver の fixture（`modules/golem-driver/test/fixtures/` の十三のプロジェクト）、決定性の検査の入力（`scripts/determinism/`）、二つのマニュアルは、どれも突き出しを使わない。
`[composition]` の `hanging-punctuation` は行分割の `pProtrusion` を有効にするが、欧文の箱の量を決める `ceProtrusion` は `protrusion` だけで有効になる。
足したハイフンの量も `ceProtrusion` が無効なら 0 なので、`hanging-punctuation` だけを有効にした本でも、足したハイフンは今のとおり突き出さない。
したがって、この ADR の変更で、fixture、決定性の検査、マニュアルの出力は変わらない。
CI の `determinism` ジョブは二つのアーキテクチャの出力を比べるだけで、過去の出力のハッシュを持たないので、基準の値を直す作業もない。
ロードマップの案の「fixture の出力の変化を決定性の検査の基準に反映する」は、要らない。

変わるのは、利用者が `protrusion = true` を書いた本の PDF である。
欧文の行の端の約物が版面の外に出る量が小さくなり、パターンの分綴で足したハイフンが突き出すようになり、行分割の結果も変わりうる。

### パターンの分綴のハイフン

パターンの分綴で行末に足すハイフンも、突き出していない。
行分割の `protrusionOf` は、行の最後の箱の `bcProtrudeEnd` だけを見る。
パターンの位置で分けた行の最後の箱は語の前の部分（`hy` など）で、終わりの字は文字なので、足したハイフン（ペナルティの幅）は突き出さない。
原稿に書いたハイフン（`well-`）は箱の最後の字なので突き出す。
同じハイフンが、原稿に書いたかどうかで突き出したりしなかったりする。

### メンテナーが決めたこと

- パターンの分綴で足したハイフンの突き出しを、この ADR で直す。行分割の `protrusionOf` が、足したハイフンを見るようにする。

## 実装すること

### 突き出しの量（golem-layout）

`wordItems` の箱の突き出しの量を、行の端になる字の送りに比を掛けて求める。

```haskell
-- 行の端になる字の送り（トラッキングを含まない）に比を掛ける
protAt pick c =
  if ceProtrusion env
    then min w (advance env lk c * pick (protrusionRatio c) `div` 1000)
    else 0
ps = maybe 0 (protAt fst . fst) (T.uncons t)  -- 箱の最初の字
pe = maybe 0 (protAt snd . snd) (T.unsnoc t)  -- 箱の最後の字
```

- 字の送りは `advance env lk c`（`ceAdvance` に箱の見た目の大きさを掛けた値）とする。PDF の経路では、フォントのその字のグリフの送りである。
- トラッキング（[docs/adr/0020](../../adr/0020-indesign-character-features.md)）は字の送りに含めない。行末のトラッキングは、今と同じく箱の終わりの側の縁（`bcEdgeEnd`）で戻す。
- 語の中のカーニングは、行の端の字の送りに含めない。pdfTeX の突き出しも、字の幅に対する比で量を決める。
- 上限の `min w` は残す。字の送りに 1000 以下の千分率を掛けるので、ふつうは効かない。
- 突き出しの表（`protrusionRatio`）は変えない。
- 二つの値の計算は整数の掛け算と切り捨ての割り算であり、決定性（[docs/adr/0002](../../adr/0002-determinism.md)）は保たれる。

### 足したハイフンの突き出し（golem-layout）

パターンの分綴のペナルティに、足すハイフンの突き出しの量を持たせる。

```haskell
data Hyphen
  = NoHyphen
  | -- | a break found by Liang's patterns; the line ends with a hyphen
    -- drawn, which protrudes by the amount given (golem-layout ADR 0014)
    PatternHyphen !Sp
  | ExplicitHyphen
```

- `wordItems` は、パターンの分綴のペナルティを `Penalty (advance env lk '-') 50 (PatternHyphen q)` とする。`q` は、`ceProtrusion` が有効なら `advance env lk '-'` に `protrusionRatio '-'` の終わりの比（700）を掛けて 1000 で切り捨てて割った値、無効なら 0 とする。箱の突き出しと同じく、ハイフンの送りに比を掛ける。
- `protrusionOf s b` は、行の終わり `b` が `PatternHyphen q` のペナルティなら、行の終わりの突き出しを `q` とする。そのほかは今のとおり、行の最後の箱の `bcProtrudeEnd` とする。パターンの位置で分けた行の最後の箱の終わりの字は、行の端にならないので、その箱の `bcProtrudeEnd` は使わない。
- 行の始まりの突き出しは変えない。
- `pProtrusion` が無効なら、今のとおりどの突き出しも 0 である。
- `PatternHyphen` を引数のない形で照合している箇所（`Golem.Layout.KnuthPlass` の `patternAt`、`Golem.Layout.Table`、`Golem.Driver.Pdf`、テスト）は、`PatternHyphen _` の照合に直す。`Golem.Layout.Table` の `h /= PatternHyphen` は、パターンの分綴かどうかを調べる関数に替える。
- 足したハイフンを描く位置は変えない。行の自然な幅から突き出しの量を引くので、行の終わりの字（足したハイフン）が版面の外に出る。

### ドキュメント

- 仕様書の「既知の不具合」から「ぶら下げの量」の項目を消す。
- 仕様書の `[composition]` の `protrusion` の説明に、突き出しの量は行の端の字の送りに表の比を掛けた値であることを書き足し、この ADR と [golem-layout ADR 0005](0005-microtypography.md) へのリンクを付ける。
- [docs/roadmap.md](../../roadmap.md) の「既知の不具合の修正」から「ぶら下げの量」の項目を消す。
- 利用者のマニュアルの `manual/appendices/i-known-issues.gm` から「ぶら下げの量が少し違う」の項目を消す。`manual/appendices/h-roadmap.gm` に同じ項目があれば消す。
- 仕様書の `[composition]` の `protrusion` の説明に、パターンの分綴で足したハイフンも、原稿に書いたハイフンと同じ量だけ突き出すことを書き足す。
- [golem-layout ADR 0005](0005-microtypography.md) は量の基準を正しく定めているので、ステータスの行は変えない。

## 実装しないこと

- 縦組みの行の端のハイフンの突き出しを変えること。縦組みの欧文の語も同じ `wordItems` を通るので、量の求め方は横組みと同じになる。
- 突き出しの量をフォントごとに調整する設定（[golem-layout ADR 0005](0005-microtypography.md) の「実装しないこと」）。
- 和文のぶら下げ組の量。
- 突き出しを決定性の検査の入力に加えること。突き出しを使う本の出力が二つのアーキテクチャで一致するかは、今の検査では確かめていない。

## テスト設計

実装の前に書き、今の実装で失敗することを確かめる。

### 突き出しの量（`modules/golem-layout/test/Main.hs`）

既存の「protrusion of hyphens and full stops follows the table」の期待値を、表の比と字の送りから計算し直す。
`fs` は 10pt（655360sp）、既定の環境の欧文の字の送りは 0.5em（327680sp）である。

- `end.` の箱の `bcProtrudeEnd` が 229376（327680 × 700 / 1000）になる。今の実装は 917504 を返すので失敗する。
- `a.` と `end.` の行末の突き出しが等しい。語の長さに依存しないことを確かめる。
- `a;` の行末の突き出しが 163840（327680 × 500 / 1000）になる。
- `well-known` の前の箱（`well-`）の行末の突き出しが 229376 になる。
- `ceAdvance` を字ごとに変えた環境（ピリオドだけ 0.25em）で、`end.` の行末の突き出しが 655360 × 0.25 × 700 / 1000 = 114688 になる。字の送りが箱の送りでなく行の端の字の送りから来ることを確かめる。
- 行頭の引用符の箱で、`bcProtrudeStart` が引用符の送りに 700 / 1000 を掛けた値になる。
- トラッキングのある見た目で、突き出しの量がトラッキングを含まない。
- `protrusion` が無効なら、どの箱の突き出しも 0 になる（今の実装でも通る）。

### 足したハイフン（`modules/golem-layout/test/Main.hs`）

- `protrusion` が有効な環境で、パターンの分綴を持つ語の `wordItems` の分綴のペナルティが `PatternHyphen 229376`（327680 × 700 / 1000）になる。無効な環境では `PatternHyphen 0` になる。
- パターンの位置で行を分けた段落を `pProtrusion` を有効にして組むと、その行の `Line` の突き出しの終わりの値が `PatternHyphen` の量に等しい。今の実装では最後の箱の文字の量（0）になるので失敗する。
- 同じ行を `placeLine` で置くと、足したハイフンの終わりが、行の幅より突き出しの量だけ外に出る。
- 原稿に書いたハイフンで分けた行（`well-known` の `well-`）の行末の突き出しが、足したハイフンの行末の突き出しと等しい。
- `pProtrusion` が無効なら、パターンの位置で分けた行の突き出しが 0 になる（今の実装でも通る）。

### 表（`modules/golem-layout/test/PunctuationSpec.hs`）

`protrusionRatio` の表のテストは変えない。

### 自動テストにしない確かめ方

- `golem new --language en` の雛形に `protrusion = true` を書いて組み、行末のピリオドと、原稿に書いたハイフンと、パターンの分綴で足したハイフンが、版面の外に字の幅の一部だけ出ることを、PDF を拡大して目で確かめる。

## トレードオフ

字の送りを `ceAdvance` で一字ずつ求めるので、語の中のカーニングや合字は量に反映されない。
行の端の約物が前の字と合字になることは欧文のフォントではまれであり、字の送りを基準にする pdfTeX の方式と同じ扱いにした。

足したハイフンの量を、行分割の型の `PatternHyphen` に持たせた。
`Hyphen` は分け方の種類を表す型であり、量を持たせると種類と量が一つの型に絡む。
ペナルティに突き出しの欄を加える形もあるが、`Penalty` を作るすべての箇所が変わる。
量を持つのはパターンの分綴のペナルティだけなので、その構成子に持たせ、変更の範囲を小さくした。

## 参考文献

- Hàn Thế Thành, Micro-typographic extensions to the TeX typesetting system, PhD thesis, Masaryk University Brno, 2000. 突き出しの量を字の幅に対する比で与える方式。
- [docs/audits/2026-10-16-tex-feature-gap.md](../../audits/2026-10-16-tex-feature-gap.md)。TeX との機能の比較。突き出しの行。
