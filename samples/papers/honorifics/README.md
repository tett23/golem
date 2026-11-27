# 待遇表現を考える欧文の見本

“Honorifics in interaction” は、欧文の横組み、二段組みの見本である。
本文は待遇表現を比較して読むための独自の提案であり、引用した文献の精読や実証研究の報告ではない。
二つの依頼文は筆者が作った例であり、実際の会話や文献からの引用ではないことを本文に明記している。
参考文献十一件の出典は[文献スタイルの調査](../../../docs/research/bibliography-styles.md#見本の論文の参考文献)にあり、Haugh 二〇〇七年の未確認のページは補っていない。
本文の引用にも、確認していない位置の指定は加えていない。

リポジトリのルートで次を実行する。
`golem` には、このチェックアウトからビルドした実行ファイルを使う。
フォントは既存の CI と同じ取得先と SHA-256 を検査して準備し、Git には含めない。

```sh
sh samples/papers/prepare-fonts.sh
cd samples/papers/honorifics
golem check
golem build
```

PDF は `build/pdf/`、HTML は `build/html/`、EPUB は `build/epub/`、二種類のテキストは `build/text/` に出る。
文献スタイルは同梱の `unified-linguistics` を名前で選ぶ。
本文に全十一件の参照を含め、Okamoto 一九九九年と Haugh 二〇〇七年を再引用する。
書籍、論文、編者のある章を含む一覧で、著者、年、題、掲載先、DOI の出力を確認できる。

この見本は[採択した root ADR 0470](../../../docs/adr/0470-bibliography-styles-by-name-and-by-declaration.md)の Journal of Politeness Research 向けの条件を確かめるための原稿であり、投稿品質の確認済み原稿ではない。
現在の同梱宣言では、Watts の名前の末尾と区切りのピリオドが重なり、PDF の DOI の直前などでは行の両端揃えで空白が広がる。
見本の側で書誌データを変えたり、句読点を自動で削ったりはしていない。
同梱宣言との統合後の再確認、投稿規定との細部の照合、A1 のメンテナーによる目視は残っている。
著者と年による引用から一覧へ移る HTML と EPUB のリンクも、現時点では接続されていない。
CI の追加と時間予算の判断も、このプロジェクトには含めていない。
