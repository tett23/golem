# ADR 0007: Knuth と Plass の論文の段落による行分割の参照テスト

ステータス: 採択→明示のハイフンの扱いと、罰点が等しい場合の不一致の扱いは [ADR 0008](0008-explicit-hyphens.md)

## 文脈

[ADR 0001](0001-knuth-plass-line-breaking.md) のテスト設計は、Knuth と Plass の論文（"Breaking Paragraphs into Lines", Software: Practice and Experience 11, 1981）の例の段落で、論文と同じ分割が得られることを確かめると定めた。
このテストはまだない。
仕様書の「今後の実装項目」（[specifications.md](../../specifications.md)）は、論文の文字幅のデータがないためと記している。
代わりに今あるのは、短い語の並びで、総当たりと比べて罰点の合計が最小になることを確かめるプロパティテストである（`modules/golem-layout/test/Main.hs`）。

総当たりとの比較は、動的計画法が最小の経路を見落とさないことを確かめる。
一方で、不良度、罰点、適合度の分類、許容度による段階の切り替えが TeX と同じ式になっているかは確かめない。
総当たりの側も同じ `lineDemerits` と `badness` を使うので、式そのものの誤りは両方に同じように入り、差として現れないためである。
実際の段落の長さと、TeX の sp の大きさの数値で TeX と同じ結果になることを確かめるテストが要る。

### 字幅のデータの検討

論文の例の段落は、グリム童話の「蛙の王さま」の冒頭である。
論文の図は、各行の分割と、行の右に調整比を示している。
この段落で論文の図と同じ分割を再現するには、各語の幅が要る。
次の三つの入手の方法を比べた。

| 方法 | 内容 | 判断 |
|---|---|---|
| 論文の情報から再構成する | 図の各行の調整比と空きの伸縮から、各行の箱の幅の合計を逆算する | 採らない。行ごとの合計は決まるが、語ごとの幅は決まらない。語の幅を合計に合うように割り振ると、作った幅で作った答えを確かめることになる |
| cmr10 の TFM から語の幅を計算する | TFM の文字幅と、合字とカーニングの表から、テストの中で語の幅を計算する | 採らない。合字とカーニングの表を読む処理をテストのために再実装することになり、その誤りと行分割の誤りが区別できない |
| TeX に語の幅を測らせ、TeX の分割を期待値にする | 論文の段落を plain TeX と cmr10 で組み、各語の幅と、TeX が選んだ分割と罰点を記録する | 採る |

三つ目を採る。
TeX（tex.web）は論文のアルゴリズムの作者による実装であり、[ADR 0001](0001-knuth-plass-line-breaking.md) が不良度と罰点の式を TeX と同じにすると定めている。
語の幅を TeX が測るので、合字とカーニングは幅に含まれた状態で記録され、テストは行分割だけを確かめる。

論文の図そのものとの一致は、自動テストにしない。
論文の図が、どの書体の字幅と、どの行長と、どの段落のパラメーターで組まれたかは、論文を確かめないと決められない。
これらが cmr10 と一致しなければ、同じアルゴリズムでも分割は変わる。
実装の手順で論文を確かめ、行長などが論文に書かれていればそれを TeX の生成に使う。
そのうえで TeX の分割と論文の図の分割が一致したかを、データのディレクトリの README に記録する。

### cmr10 のライセンス

cmr10 は Knuth の Computer Modern のフォントであり、CTAN では `cm` のパッケージとして Knuth のライセンスで配布されている。
このライセンスは、変更しないファイルの再配布を認め、変更したファイルには別の名前を付けることを求める。
このテストではフォントのファイルをリポジトリに置かず、TeX が測った語の幅（整数）と、TeX のログを置く。
出所として、TeX の版と cmr10.tfm の SHA-256 を README に記録する。
ライセンスの条文は、取得の手順で CTAN のパッケージのページ（https://ctan.org/pkg/cm ）を確かめ、README に要旨を写す。

## 実装すること

### TeX との対応

テストの段落の並びと TeX の段落を、次のように一致させる。
TeX の側の設定は、生成に使う `frog-king.tex` に書く。

| 項目 | TeX の設定 | Golem の並び |
|---|---|---|
| 書体 | `\tenrm`（cmr10） | 語ごとの `Box`。幅は TeX が測った sp の値 |
| 語間 | `\frenchspacing`。空きは `\fontdimen2` から `\fontdimen4` | `Glue`。値は TeX が書き出した sp の値 |
| 字下げ | `\parindent` | 段落の先頭の `Box`。幅は `\parindent` の sp の値 |
| 段落の終わり | `\parfillskip=0pt plus 1fil` | 既存の `finish`（`Penalty 10000`、`filStretch` の `Glue`、`Penalty -10000`） |
| ハイフネーション | `\hyphenpenalty=10000`、`\exhyphenpenalty=10000` | 罰則を置かない。`lime-tree` は一つの `Box` |
| パラメーター | `\pretolerance=100`、`\tolerance=200`、`\emergencystretch=0pt`、`\linepenalty=10`、`\adjdemerits=10000`、`\doublehyphendemerits=10000`、`\finalhyphendemerits=0`、`\looseness=0` | `defaultParams` |
| 行長 | `\hsize`（後述の複数の値） | `const hsize` |

`\frenchspacing` にするのは、句読点の後の空きを TeX のスペースファクターで変えないためである。
Golem の欧文の組版はスペースファクターを持たず、テストの並びも語間の空きを一つの値にする。

ハイフネーションを止めるのは、TeX のパターン（`hyphen.tex`）と Golem が同梱するパターン（hyph-utf8 の `hyph-en-us`）が異なり、分割の候補が一致しないためである。
明示のハイフン（`\exhyphenpenalty`）も止める。
TeX は明示のハイフンの後を一回目の段階から分割の候補にするが、Golem の `breakParagraph` は一回目の段階でフラグの付いた罰則をすべて除くので、ここで差が出る。

### 行長

`\hsize` は複数の値で生成する。
候補は 180pt、240pt、300pt と、論文に行長が書かれていればその値とする。
次の条件を満たす値だけを採る。

- ログに `Overfull \hbox` がない。Golem の 4 番目の段階（はみ出す行を許す分割）と TeX の最後の段階は、はみ出す行の扱いが異なるためである。
- 採った値の中に、一回目の段階（`@firstpass`）で決まるものと、二回目の段階（`@secondpass`）まで進むものが、少なくとも一つずつある。足りなければ候補を 20pt 刻みで足す。

### データのファイル

`modules/golem-layout/test/data/knuth-plass/` に次のファイルを置く。

| ファイル | 内容 | 作り方 |
|---|---|---|
| `README.md` | 段落の出典、TeX の版、cmr10.tfm の SHA-256、cmr10 のライセンスの要旨、再生成の手順、論文の図との照合の結果 | 手で書く |
| `frog-king.tex` | 生成に使う plain TeX のファイル。段落の本文、パラメーター、各 `\hsize` での組版、幅の書き出し | 手で書く |
| `frog-king.words` | TeX が測った値 | `frog-king.tex` が `\immediate\write` で書く |
| `frog-king.log` | TeX のログ | TeX の実行で作られる |

段落の本文は、論文の例の段落を一字ずつ写す。
英語の訳文（Margaret Hunt による 1884 年の訳と考えられる）はパブリックドメインであり、論文の本文から写すのは例の段落だけとする。

`frog-king.words` は一行に一つの記録を持つ、空白区切りのテキストとする。

```text
space 218453 109226 72818
parindent 1310720
whole 123456789
box 491524 In
box 1231234 olden
...
```

- `space` は `\fontdimen2` から `\fontdimen4` の sp の値である。
- `parindent` は `\parindent` の sp の値である。
- `whole` は、段落の全文を一つの `\hbox` に組んだ幅である。語の幅の合計と語間の数から計算した幅とこれが一致することを、テストでデータの欠けの検査に使う。
- `box` は語の順に並べ、句読点は直前の語に含める。値は TeX が `\number\wd0` で書いた整数である。
- 上の数値は形式の例であり、実際の値は TeX の出力で決まる。

`frog-king.log` は、行の折り返しを止めて生成する（`max_print_line=10000`）。
各 `\hsize` の組版の前に `\message{GOLEM-HSIZE=<sp の値>}` を出し、テストはこの印でログを区切る。
各 `\hsize` で、`\tracingparagraphs=1` で分割の候補と罰点を出し、段落を `\vbox` に組んで `\showbox` で各行のグルーの設定（`glue set`）を出す。

### テストのコード

`modules/golem-layout/test/KnuthPlassReference.hs` を足し、テストスイートの `other-modules` に加える。
`golem-layout.cabal` の `extra-source-files` に `test/data/knuth-plass/*` を加える。

- `readWords :: FilePath -> IO Words`：`frog-king.words` を読む。
- `paragraphItems :: Words -> [Item]`：字下げの `Box`、語の `Box` と語間の `Glue`、`finish` の並びを作る。
- `parseTrace :: Text -> [TexRun]`：ログを `GOLEM-HSIZE` の印で区切り、各区間から次を取り出す。

  ```haskell
  data TexRun = TexRun
    { trHsize :: !Sp,
      trPass :: !Int,              -- 1 なら @firstpass、2 なら @secondpass
      trBreaks :: ![TexBreak],     -- 選ばれた経路の分割。段落の先頭から順に
      trTotalDemerits :: !Integer, -- 最後の分割の t
      trGlueSet :: ![Rational]     -- \showbox の各行の glue set。縮める行は負
    }

  data TexBreak = TexBreak
    { tbWordIndex :: !Int, -- この分割の直前の語の番号（0 始まり）
      tbFitness :: !Int,   -- line n.f の f
      tbDemerits :: !Integer
    }
  ```

  経路は、`@@n: line l.f t=T -> @@m` の行を集め、最後の分割（`\par` の位置）から `-> @@m` をたどって求める。
  各 `@@n` の直前の `@<文字列> via @@m b=B p=P d=D` の行の文字列から、分割の直前の語を求める。
  語の番号は、`frog-king.words` の語の並びの中での位置に写す。
- `glue set` の値は、TeX が `print_scaled` で出した 10 進数を sp の整数に戻して持つ（TeX の `print_scaled` は、読み戻すと元の整数になる桁数で出力する）。

### データの取得と生成の手順

この ADR の実装には TeX の処理系が要り、開発の環境には入っていない。
TeX は期待値を作るときに一度だけ使い、テストの実行と CI には要らない。

1. 論文を確かめる。例の段落の本文と、図の各行の分割と調整比と、行長などの組版の条件が書かれていれば、それを書き写す（本文は `frog-king.tex` に、条件と図の分割は `README.md` に）。
2. TeX Live を入れる。macOS では BasicTeX（TeX Live の最小の構成）の pkg を CTAN の `systems/mac/mactex/` から取得する（https://mirror.ctan.org/systems/mac/mactex/BasicTeX.pkg ）。取得したファイルは、同じディレクトリで公開されている検査値（SHA-512）と照合してから入れる。入れた TeX Live の年版を記録する。
3. `tex --version` の一行目（`TeX 3.141592653 (TeX Live 年版)` の形）を README に記録する。
4. `kpsewhich cmr10.tfm` で使われる cmr10.tfm を特定し、その SHA-256 を記録する。CTAN の `fonts/cm/tfm/cmr10.tfm`（https://mirrors.ctan.org/fonts/cm/tfm/cmr10.tfm ）の SHA-256 と一致することを確かめ、一致しなければ実装を止めて記録する。
5. `max_print_line=10000 tex -interaction=batchmode frog-king.tex` で `frog-king.words` と `frog-king.log` を作る。`\showbox` が対話で止まらないように batchmode で動かし、`frog-king.tex` で `\showboxdepth` と `\showboxbreadth` を十分に大きくする。
6. ログの中のファイルのパスなど、生成した機械に固有の行は、テストが読まない部分だけを `frog-king.log` から除いてよい。除いた行の種類を README に書く。
7. 「行長」の節の条件を満たす `\hsize` の組を決め、`frog-king.tex` を確定して 5 からやり直す。

### 不一致が出た場合

テストは実装の前に書いて、失敗することを確かめる（データを置く前は、ファイルがないことで失敗する）。
データを置いた後に Golem と TeX の結果が異なれば、原因を次のように扱う。

- [ADR 0001](0001-knuth-plass-line-breaking.md) が TeX と同じにすると定めた式（不良度、罰点、適合度の分類、許容度による段階）の誤りであれば、`Golem.Layout.KnuthPlass` を直す。
- 罰点が等しい候補の選び方の差であれば、直さない。[ADR 0001](0001-knuth-plass-line-breaking.md) は前の位置を選ぶと定めており、TeX は活性ノードの並びの順で後から調べた候補を選ぶ（tex.web の `try_break` は `d<=minimal_demerits` で置き換える）。その `\hsize` をデータから除き、理由を README に書く。

### ドキュメント

- 仕様書の「今後の実装項目」から「行分割の参照例のテスト」の項目を消す。
- 仕様書の行分割の説明に、TeX が論文の段落を組んだ結果を参照のテストにしていることと、このテストの条件（ハイフネーションなし、`\frenchspacing`）を書く。

## 実装しないこと

- 論文の図の調整比との自動の照合。照合の結果は README に記録するだけとする。
- ハイフネーションを含む参照のテスト。TeX と Golem でパターンが異なるので、分割の候補をそろえる方法を別に決める必要がある。
- 明示のハイフンを一回目の段階から分割の候補にすること。TeX との差としてここに記録し、扱いは別の ADR で決める。
- TeX のスペースファクター、`\finalhyphendemerits`、`\looseness` を Golem に加えること。
- TFM を読む処理。語の幅は TeX が測った値を使う。
- cmr10.tfm と TeX の処理系をリポジトリや CI に置くこと。

## テスト設計

`modules/golem-layout/test/Main.hs` の「Knuth-Plass ([ADR 0001](0001-knuth-plass-line-breaking.md))」の群の隣に、「Knuth-Plass reference (ADR 0007)」の群を加える。

### データを使わない単体テスト

- `parseTrace` が、手で書いた短いログ（二つの `GOLEM-HSIZE` の区間、`@secondpass`、三つの `@@n` と後戻りの `-> @@m`、二行分の `glue set`）から、期待した `TexRun` を二つ返す。経路は最後の分割からたどった順を逆にして、先頭から並ぶ。
- 縮める行の `glue set - 0.5` が負の値になり、伸ばす行の `glue set 0.33333` が sp の整数 21845 に戻る。
- `paragraphItems` が、`space`、`parindent`、二つの `box` の小さな入力から、`[Box parindent, Box w1, Glue sp st sh, Box w2] <> finish` を作る。

### データを使うテスト

各 `TexRun` について、`breakParagraph defaultParams (const trHsize) (paragraphItems ws)` の結果を次のように比べる。

- データの検査：`whole` が、語の幅の合計と、語間の数に `space` の幅を掛けた値の和に等しい。
- 段階：`brPass` が `trPass` に等しい。
- 分割の位置：`brPositions` の各位置の直前の語の番号が、`trBreaks` の `tbWordIndex` の並びに等しい。
- 罰点：`brDemerits` が `trTotalDemerits` に等しい。整数なので誤差を許さない。
- 適合度：各行の適合度が `tbFitness` に等しい。Golem の側は、各行の伸び縮みの量と `badness` と `fitnessOf` から計算する。
- 調整比：最後の行を除く各行で、`lineRatio` に 65536 を掛けて丸めた値と、`trGlueSet` の対応する値に 65536 を掛けた値の差が 1 以下である。TeX は `glue_set` を浮動小数点数で持ち、Golem は有理数で持つので、丸めの境目で 1 だけずれうる。
- はみ出し：どの行も `lineOverfull` でない。

`\hsize` ごとに一つの `testCase` にし、失敗したときに、どの幅で、何行目の何が食い違ったかをメッセージに出す。

### 自動テストにしないもの

論文の図の分割との照合は、取得と生成の手順の 1 で書き写した図の分割と、TeX の分割を見比べ、一致したかを README に記録する。

## トレードオフ

期待値は論文の図ではなく、論文の段落を TeX が組んだ結果である。
論文の図との一致を直接には確かめないが、TeX は論文の著者によるアルゴリズムの実装であり、[ADR 0001](0001-knuth-plass-line-breaking.md) が式を TeX に合わせると定めているので、TeX との一致を確かめることで、論文の方式に従っていることの確かめになる。
論文の図の字幅が手に入らない以上、図と数値で一致させる手段はない。

ハイフネーション、明示のハイフン、スペースファクターを止めるので、テストが確かめるのは語間の空きだけの段落である。
二回目の段階のうち、ハイフネーションの候補を加える部分は確かめない。
ここを確かめるには、TeX と Golem でハイフネーションの候補をそろえる必要があり、パターンの扱いを決める別の ADR が要る。

期待値の生成に TeX の処理系が要る。
生成は一度だけで、生成物をリポジトリに置くので、テストの実行と CI は TeX に依存しない。
TeX 3（1990 年）以降の版の更新は誤りの修正に限られ、行分割の処理は変わっていない。
cmr10.tfm の SHA-256 も照合するので、生成をやり直すときに TeX の版が変わっていても、同じデータが得られるはずである。
得られなければ、README の記録との差から原因を調べられる。
