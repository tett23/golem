# Knuth と Plass の論文の段落による参照データ

このディレクトリは、行分割の参照テスト（[golem-layout ADR 0007](../../../../../docs/golem-layout/adr/0007-knuth-plass-reference-test.md)）の期待値を置く。
Knuth と Plass の論文（"Breaking Paragraphs into Lines", Software: Practice and Experience 11, 1981）の例の段落を plain TeX と cmr10 で組み、TeX が測った語の幅と、TeX が選んだ分割を記録した。
テストは `../../KnuthPlassReference.hs` がこれらを読み、`breakParagraph` の結果と比べる。

| ファイル | 内容 |
|---|---|
| `frog-king.tex` | 生成に使う plain TeX のファイル |
| `frog-king.words` | TeX が測った語間の空き、字下げ、段落全体の幅、語ごとの幅（sp） |
| `frog-king.log` | TeX のログ。`\tracingparagraphs` の分割の候補と、`\showbox` の各行のグルーの設定 |

## 段落の出典

段落は、グリム童話の「蛙の王さま」の英訳の冒頭である。
論文そのものは手元になく、本文を論文から直接は写していない。
本文は TeX Live 2026 の `context` パッケージ（リビジョン 80243）の文書 `doc/context/sources/general/manuals/beyond/beyond-twins.tex` から写した。
この文書は、Didier Verna の論文（Similarity Problems in Paragraph Justification, 2024）が Knuth と Plass の例として使った引用と同じ段落を、例に使っている。
写したファイルの SHA-256 は `2c0e81f1283f859b050f285ae216353fae91a8838978f865ed3376de78ca1c4c` である。
写すときに、アポストロフィ（U+2019）を ASCII の `'` に置き換えた。
cmr10 では `'` が右の引用符の字形になるので、字形は変わらない。

英訳（Margaret Hunt による 1884 年の訳と考えられる）はパブリックドメインである。

## TeX と cmr10

- TeX：`tex --version` の一行目は `TeX 3.141592653 (TeX Live 2026)` である。
  TeX Live 2026 の `install-tl` で `scheme-minimal` をホームディレクトリの下に入れた。
- cmr10.tfm：`kpsewhich cmr10.tfm` が示したファイルの SHA-256 は `87f2d8981927644cbecaf3d639e96e348ea4e7be49d8804468bd8ba9ff3f5244` である。
  CTAN の `fonts/cm/tfm/cmr10.tfm`（https://mirrors.ctan.org/fonts/cm/tfm/cmr10.tfm ）の SHA-256 と一致した。

### cmr10 のライセンス

cmr10 は Knuth の Computer Modern のフォントであり、CTAN では `cm` のパッケージとして配布されている。
TeX Live のパッケージの目録（`texlive.tlpdb` の `catalogue-license`）は、このパッケージのライセンスを `knuth` としている。
このライセンスは、ファイルを変更せずに使い、複製し、再配布することを認め、変更したファイルには別の名前を付けることを求める。
Computer Modern の METAFONT のソースの冒頭にも、名前を変えずに変更してはならないと書かれている。
CTAN のパッケージのページ（https://ctan.org/pkg/cm ）は確かめていない。

このディレクトリにはフォントのファイルを置かない。
置くのは、TeX が測った幅の整数と、TeX のログだけである。

## 組版の条件

`frog-king.tex` は golem-layout [ADR 0007](../../../../../docs/golem-layout/adr/0007-knuth-plass-reference-test.md) の「TeX との対応」の表のとおりに設定する。
ハイフネーションと明示のハイフンでの分割は罰則 10000 で止め、`\frenchspacing` で語間の空きを一つの値にする。

`\hsize` は 160pt、200pt、240pt、300pt の四つである。

| `\hsize` | TeX の段階 |
|---|---|
| 160pt | `@secondpass` |
| 200pt | `@secondpass` |
| 240pt | `@firstpass` |
| 300pt | `@firstpass` |

最初の候補のうち 180pt は、`Overfull \hbox` が出たので除いた。
この幅では二回目の段階で活性の候補がなくなり、TeX は不良度が許容度を超える行を作った（ログの `b=*`、`d=*`）。
ADR の候補（180pt、240pt、300pt）だけでは二回目の段階の例がなくなるので、20pt 刻みで 160pt と 200pt を足した。
240pt と 300pt は一回目の段階で決まる。

罰点の等しい候補の選び方の差で除いた `\hsize` はない。

## 論文の図との照合

論文が手元にないので、論文の図の分割と調整比、論文の行長などの組版の条件は書き写していない。
TeX の分割と論文の図の分割の照合も、まだしていない。
論文を確かめたら、ここに結果を記録する。

## 再生成の手順

1. TeX Live を入れる（上の「TeX と cmr10」の版）。
2. `kpsewhich cmr10.tfm` のファイルの SHA-256 が上の値と一致することを確かめる。
3. このディレクトリで `max_print_line=10000 tex -interaction=batchmode frog-king.tex` を実行する。
   `\showbox` が止まらないように batchmode で動かすので、終了コードは 0 にならない。
4. `frog-king.log` の一行目を除く。
   一行目は TeX の版と、フォーマットを作った日付と実行の日時を含み、テストは読まない。

ほかの行は除いていない。
ログの中のファイルのパスは `./frog-king.tex` だけで、機械に固有の部分を含まない。
