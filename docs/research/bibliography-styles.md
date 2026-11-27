# 参考文献の書式の調査

この文書は、[Golem ADR 0385](../adr/0385-bibliography-and-citation-styles.md) の文献スタイルを決めるために、広く使われる参考文献の書式と、組版の見本の論文の投稿先の書式を調べたものである。
最初の調査は 2026-11-26 で、エージェントがウェブの資料を読んだ。
一次資料を読めなかったところは、その旨と、代わりに読んだ資料を書く。

## 調べ方

一次資料のうち、apastyle.apa.org（ボットの検査）、chicagomanualofstyle.org（ログインへの転送）、ncbi.nlm.nih.gov（ブラウザーの検査）、iso.org と Elsevier の投稿規定（HTTP 403）は読めなかった。
これらは、大学の図書館の案内などの二次資料で代えた。
見本の論文の参考文献は、CiNii Research（cir.nii.ac.jp）か Crossref（api.crossref.org）で、書誌の情報が合うことを確かめた。

## 広く使われる書式

### Chicago

*The Chicago Manual of Style* 18th ed.（2024、University of Chicago Press）が定める。
13 章が引用の方式、14 章が資料の種類ごとの例である（`https://www.chicagomanualofstyle.org/tools_citationguide.html`）。
方式は二つあり、注と書誌（notes-bibliography）は脚注か後注と書誌を、著者と年（author-date）は本文の (Author Year, page) と参考文献の一覧を使う。

例は、公式の案内を読めなかったので、Widener University の 18 版の案内（`https://widener.libguides.com/Chicago18/examples`）から採った。

- 書籍（書誌）：`Hopkins, Richard S. *Planning the Greenspaces of Nineteenth-Century Paris*. Louisiana State University Press, 2015.`
- 書籍（著者と年）：`Hopkins, Richard S. 2015. *Planning the Greenspaces …*. Louisiana State University Press.`
- 論文（書誌）：`Huckstein, Erika. "The Politics of Peace and Reproduction in the Anti-Fascist Campaigns of British Women's Organisations." *Contemporary European History* 33, no. 1 (2024): 53–69. https://doi.org/10.1017/S0960777322000157.`
- 章（書誌）：`Smith, Jordan. "'For How Could We Do Without Sugar and Rum?' …" In *Global Commerce and Economic Conscience in Europe, 1700–1900*, edited by Felix Brahm and Eve Rosenhaft. Oxford University Press, 2022.`

著者と年の方式の論文の巻号を、この案内は「33, (1): 53-69」と書くが、誤植と見える。
通例の形は `33 (1): 53–69` であるが、CMOS で確かめていない（未確認）。

18 版の変更は、University of Queensland の案内（`https://guides.library.uq.edu.au/referencing/chicago-18th-edition-notes-and-bibliography`）によれば次のとおりである。

- 出版地を書かない。
- 書誌で、章のページの範囲を求めない。
- 著者は六人まで書き、七人以上なら最初の三人を書く。
- 同じ著者を、3 エムダッシュでなく、名前で書き直す。
- 項目をぶら下げ字下げにする。

日本語の資料については、11.93（日本語のローマ字表記）と 11.94（修正ヘボン式）の節があるが、本文を読めなかった。
題の訳を角括弧で添える規則は未確認である。

### APA

*Publication Manual of the American Psychological Association* 7th ed.（2020）が定める（`https://apastyle.apa.org/`）。
引用は著者と年の (Author, Year) である。
次の例は公式の例のページを読めなかったので、エージェントが覚えていた形を Crossref の DOI と書誌で確かめたものである。

- 書籍：`Jackson, L. M. (2019). *The psychology of prejudice: From attitudes to social action* (2nd ed.). American Psychological Association. https://doi.org/10.1037/0000168-000`
- 論文：`Grady, J. S., Her, M., Moreno, G., Perez, C., & Yelinek, J. (2019). Emotions in storybooks: A comparison of storybooks that represent ethnic and racial groups in the United States. *Psychology of Popular Media Culture, 8*(3), 207–217. https://doi.org/10.1037/ppm0000185`
- 章：`Aron, L., Botella, M., & Lubart, T. (2019). Culinary arts: Talent and their development. In R. F. Subotnik, P. Olszewski-Kubilius, & F. C. Worrell (Eds.), *The psychology of high performance …* (pp. 345–359). American Psychological Association. https://doi.org/10.1037/0000120-016`

英語以外の資料は、原語で書き、題の英訳を角括弧で添える。
角括弧の訳は斜体にしない。
日本語はローマ字にし、文頭だけを大文字にし、年は西暦にする。
根拠は University of Melbourne の案内（`https://library.unimelb.edu.au/recite/referencing-styles/apa7/referencing-non-english-sources`）と UBC の資料（`https://wiki.ubc.ca/images/8/80/Japanese_APA.pdf`）である。
APA の公式のブログの記事（`https://apastyle.apa.org/blog/transliterated-titles-references`、`https://apastyle.apa.org/blog/citing-works-written-another-language`）は読めなかった。

### MLA

*MLA Handbook* 9th ed.（2021、Modern Language Association）が定める（`https://style.mla.org/`）。
引用は著者とページの (Author page) で、著者と年ではない。
項目は、九つの基本の要素と、入れ物（container）で組み立てる。
例は二次資料（`https://libguides.bgsu.edu/MLA/books`、`https://www.pcc.edu/library/html_handouts/mla-9-citation-samples/`）から採った。

- 書籍：`Davis, Michael. *Street Gang: The Complete History of Sesame Street*. Viking, 2008.`
- 論文の形：`Last, First. "Title." *Journal*, vol. #, no. #, Year, pp. x–y. https://doi.org/…`
- 章の形：`Last, First. "Chapter." *Book*, edited by First Last, Publisher, Year, pp. x–y.`

日本語の資料は、原語の文字か、ローマ字か、その両方を、一貫して書いてよい。
読み手が言語を知らないときは、英訳を角括弧で添える（`https://uwcchina.libguides.com/cite/languages`）。
ただし、University of Pennsylvania の図書館は、Handbook 自体はローマ字以外の文字の題の書き方を定めていないと書く（`https://faq.library.upenn.edu/lkcajs/faq/45830`）。

### Harvard

Harvard は、著者と年の方式の書式の一群で、管理する団体を持たない。
英国でよく使われる拠りどころは、Pears and Shields, *Cite Them Right* 13th ed.（Bloomsbury、2025）である（`https://www.sussex.ac.uk/skills-hub/referencing-and-academic-integrity/harvard`）。
例は University of Sussex の案内から採った。

- 書籍：`Walsh, A.W. (2012) *The treatment of children*. Collins Books.`
- 論文：`Gomes, A. (2012) 'Alter-native 'development': indigenous forms of social ecology', *Third World Quarterly*, 33(6), pp. …`
- 章：`Loizos, P. (1996) 'A broken mirror: masculine sexuality in Greek ethnography', in A. Cornwall and N. Lindisfarne (eds), …`

日本語の資料の扱いは調べていない。

### IEEE

*IEEE Reference Guide*（V 3.28.2025、IEEE Publication Operations）が定める（`https://journals.ieeeauthorcenter.ieee.org/wp-content/uploads/sites/7/IEEE_Reference_Guide.pdf`）。
引用は、引用した順に番号を振る `[1]` の形である。
2026-11-27 に、[同じ案内の PDF](https://journals.ieeeauthorcenter.ieee.org/wp-content/uploads/sites/7/IEEE_Reference_Guide.pdf?WT.ac=journals) で、著者名は六人まで全員を書き、七人以上は第一著者の後を `et al.` にする規則を確認した。
本文の複数の番号も、範囲に略さず `[1], [2], [3]` のように一つずつ書く。
次の例は、この案内のとおりである。

- 書籍：`B. Klaus and P. Horn, *Robot Vision*. Cambridge, MA, USA: MIT Press, 1986.`
- 論文：`M. M. Chiampi and L. L. Zilberti, "Induction of electric field in human bodies moving near MRI: An efficient BEM computational procedure," *IEEE Trans. Biomed. Eng.*, vol. 58, no. 10, pp. 2787–2793, Oct. 2011, doi: 10.1109/TBME.2011.2158315.`
- 章：`L. Stein, "Random patterns," in *Computers and You*, J. S. Brake, Ed., New York, NY, USA: Wiley, 1994, pp. 55–70.`

外国の資料には「(in Language)」を添える形がある。
案内の例は K. Ichiro, *Thai Economy and Railway 1885–1935*, Tokyo: Nihon Keizai Hyoronsha (in Japanese), 2000. で、題を訳すかローマ字にし、原語の文字では書かない。

### Vancouver

ICMJE の推奨と、NLM の *Citing Medicine* 2nd ed. が定める。
NLM の案内（`https://www.nlm.nih.gov/bsd/uniform_requirements.html`、2026-06-02 に見直し）は、NISO Z39.29-2005 (R2010) を NLM が改めたものに基づくと書く。
*Citing Medicine*（`https://www.ncbi.nlm.nih.gov/books/NBK7256/`）は読めなかった。
引用は、引用した順の番号である。
次の例は、NLM の見本のページのとおりである。

- 書籍：`Murray PR, Rosenthal KS, Kobayashi GS, Pfaller MA. Medical microbiology. 4th ed. St. Louis: Mosby; 2002.`
- 論文：`Halpern SD, Ubel PA, Caplan AL. Solid-organ transplantation in HIV-infected patients. N Engl J Med. 2002 Jul 25;347(4):284-7.`
- 章：`Meltzer PS, Kallioniemi A, Trent JM. Chromosome alterations in human solid tumors. In: Vogelstein B, Kinzler KW, editors. The genetic basis of human cancer. New York: McGraw-Hill; 2002. p. 93-113.`

ページの範囲の終わりは、284-7 のように、始めと同じ上の桁を省く。
英語以外の論文の題は、英訳を角括弧で書き、日本人の名前は ALA-LC の表でローマ字にする。
これは *Citing Medicine* の Box 21（`https://ncbi.nlm.nih.gov/books/NBK7282`）の検索の要約によるもので、Box 21 自体は読めなかった。
中国語、日本語、韓国語の題の例外の有無は未確認である。

### ISO 690

ISO 690:2021（第 4 版、2021 年 6 月、ISO/TC 46）が定める（`https://www.iso.org/standard/72642.html`）。
ページを読めなかったので、次は検索の要約による。
原則と要件を定め、番号の方式と名前と年の方式の両方を扱う。
区切りの記号は定めず、法令の引用とプログラムが読むデータの形は扱わない。
例と、日本語の資料の扱いは未確認である。

### SIST 02

科学技術情報流通技術基準の SIST 02「参照文献の書き方」（2007 年の改訂、JST）が定める。
SIST の事業は 2011 年度の末に終わり、サイトは更新されていない（JST のサイトの検索の要約による）。
手引きは国立国会図書館の WARP に残る（`https://warp.ndl.go.jp/20220119/20220113214833/jipsti.jst.go.jp/sist/handbook/sist02_2007/main.htm`）。
引用は、番号の方式と著者と年の方式のどちらでもよい。

5 節が定める欄の順は次のとおりである。

- 論文：`著者名．論文名．誌名．出版年，巻数，号数，はじめのページ−おわりのページ`
- 書籍：`著者名．書名．版表示，出版地，出版者，出版年，総ページ数，（シリーズ名，シリーズ番号）`
- 章：`著者名．"章の見出し"．書名．編者名．…，出版年，はじめのページ−おわりのページ`

手引きの例は次のとおりである。

- 論文（日本語）：`西潔, 石原和弘. 火山地域における震源計算についての提案. 火山. 2003, vol. 48, no. 5, p. 407-413.`
- 同じ論文の短い形：…火山. 2003, 48(5), p. 407-413.
- 論文（英語）：`Pisciella, Paola; Pelino, Mario. FTIR spectroscopy …. Journal of the European Ceramic Society. 2005, vol. 25, no. 11, p. 1855-1861.`
- 書籍：`井尻憲一. 宇宙の生物学. 朝倉書店, 2001, 148p., (シリーズ応用動物科学／バイオサイエンス, 5).`
- 章：`鵜飼保雄. "遺伝率の相対性". 量的形質の遺伝解析. 医学出版, 2002, p. 109-110.`

日本語と英語の項目は同じ区切りを使い、ピリオドで欄を区切り、『』と「」を使わない。
著者の区切りは、欧米の共著者が「;」、日本の共著者が「,」である。

## 見本の論文の投稿先

### 室町期の朝廷（和文、縦書き、2 段組み）

候補の三誌は、どれも参考文献の書式を定めていない。

- **史学雑誌**（公益財団法人史学会、`https://www.shigakukai.or.jp/journal/regulations/`）：会員に限り、縦書きで、本文、注、図表を合わせて 400 字詰め 89 枚までである。和文の要旨（800 字以内）と英文の要旨（約 400 語）が要る。
- **日本歴史**（日本歴史学会の編、吉川弘文館、`https://www.yoshikawa-k.co.jp/news/n2359.html`）：注は全体の通し番号にし、末尾にまとめる。縦書きで、40 字×30 行である。
- **古文書研究**（日本古文書学会、`http://komonjo.net/content/posts.html`）：和文の縦書きで、40 字×30 行である。注は本文と同じ大きさで、ワープロの注の機能を使わない。

慣行の形は、論文の末尾の注に漢数字で書く次の形と見られるが、規定で確かめていない（未確認）。

- 論文：`著者「論文名」（『誌名』巻号、年）`
- 書籍：`著者『書名』（出版社、年）`

この形の例である `栗原伸一郎「…」（『日本歴史』第七一八号、二○一二年）` は、雑誌の規定でなく、三重県の文書（`https://www.bunka.pref.mie.lg.jp/common/content/000787024.pdf`）にあったものである。
文書に基づく論文なら古文書研究、そうでなければ史学雑誌が投稿先になる。

この論文は、一覧でなく注で文献を書く。
縦書きで、巻号と年を漢数字にし、題を『』と「」で囲む書式が要る。

### 宇佐美のディスコース・ポライトネス理論の展望（和文、横書き、2 段組み）

投稿先は、展望論文を 16 ページまで受け付ける『社会言語科学』（社会言語科学会）である。
規定は `https://www.jass.ne.jp/journal/rule/`、執筆の手引きは `https://www.jass.ne.jp/journal/submission-guidelines/` にある。
ただし、この誌の雛形は 1 段組み（53 字×40 行）なので、見本の 2 段組みはこの誌の規定と合わない。

本文の引用は著者と年で、`柴田 (1978)`、`(安田・海野, 1977:35)` と書く。
複数の文献は古い順に並べ、翻訳は `(トラッドギル, 1972/1975)`、再刊は `(時枝, 2008 [1941])` と書き、同じ著者の同じ年は `1997a`、`1997b` とする。
参考文献は、第一著者の名前の順の一つの一覧で、日本語と欧文を混ぜ、日本語の項目に『』と「」を使わない。

- 柴田武 (1978). 社会言語学の課題. 三省堂.
- 渋谷勝己 (2000). 徳川学の流れ－方言学から社会言語学へ－. 社会言語科学, 2(2), 2-10.
- 欧文は名を略さない：Sacks, Harvey, Schegloff, Emanuel, & Jefferson, Gail (1974). … Language, 50(4), 696-735.

ほかの候補の二誌は、書式が違う。

- **日本語教育**（日本語教育学会、`https://www.nkg.or.jp/gakkaishi/.assets/toko_tebiki.pdf`）：一覧の見出しは「引用文献」で、項目に `(1)`、`(2)` の番号を振る。日本語の文献を五十音順に先に、外国語の文献をアルファベット順に後に置く。論文の題を「」で、書名と誌名を『』で囲む（`宇佐美 洋, 森 篤嗣, …（2009）「…」『日本語教育』140，48-58.`）。外国語の文献は APA に近い。
- **語用論研究**（日本語用論学会、`https://pragmatics.gr.jp/journal/contribution_rule.html`、2025-03-21 改訂）：一つの一覧で、年の後にピリオドを置く（`Horn, L. R. 1985. "Metalinguistic Negation and Pragmatic Ambiguity." Language 61(1), 121-174.` と `小泉 保. 1990. 『言外の言語学―日本語用論―』東京：三省堂.`）。

三誌の違いは四つある。
一覧が一つか二つか、『』と「」を使うか、項目に番号を振るか、年の区切り（`(1978).`、`（2008）`、`1990.`）である。

### 待遇表現（欧文、2 段組み）

投稿先は Journal of Politeness Research（De Gruyter Brill、Mouton）である。
執筆の手引き（2025-06-02、`https://www.degruyterbrill.com/publication/journal_key/JPLR/downloadAsset/JPLR_JPLR_Instruction%20for%20Authors.pdf`）は、De Gruyter Mouton Journal Style Sheet v1.3（`https://www.degruyterbrill.com/publication/journal_key/JPLR/downloadAsset/JPLR_Mouton_journal_stylesheet.pdf`）に従うとする。
この書式は、Unified Style Sheet for Linguistics（`https://www.linguisticsociety.org/sites/default/files/style-sheet_0.pdf`）に基づく。

本文の引用は (Bouissac 1985)、(Smith and Jones 1995)、(Hockett 1964: 140–145) の形である。
ページの範囲を略さず、ibid. を使わず、本文で & を使わない。
参考文献は、名を略さず、著者をすべて書き（一覧で et al. を使わない）、誌名と出版社を略さず、出版地と出版社の両方を書く。
題は文頭だけを大文字にし、書名と誌名を斜体にする。
次の例は、この書式のとおりである。

- 書籍：`Chomsky, Noam. 1986. *Knowledge of language: Its nature, origin, and use*. New York: Praeger.`
- 論文：`Neuman, Yair, Yotam Lurie & Michele Rosenthal. 2001. A watermelon without seeds: A case study in rhetorical rationality. *Text* 21(4). 543–565.`
- 章：`Heller, Monica. 2001. Gender and public space in a bilingual school. In Aneta Pavlenko, Adrian Blackledge, Ingrid Piller & Marya Teutsch-Dwyer (eds.), *Multilingualism, second language learning, and gender* (Language, Power and Social Process 6), 257–282. Berlin & New York: Mouton de Gruyter.`
- 日本語の題：`Haga, Yasushi. 1998. *Nihongo no Shakai Shinri* [Social psychology in the Japanese language]. Tokyo: Ningen no Kagaku Sha.`

2026-11-27 に Mouton Journal Style Sheet v1.3 の 8 ページで、Heller の章の編者を再確認した。
編者は Aneta Pavlenko、Adrian Blackledge、Ingrid Piller、Marya Teutsch-Dwyer の 4 人であり、上の例の省略記号を名前に置き換えた。

ほかの候補の Journal of Pragmatics（Elsevier、`https://www.sciencedirect.com/journal/journal-of-pragmatics/publish/guide-for-authors`）は、ページを読めなかった。
検索の要約によれば、著者と年の引用で、投稿の時点ではどの書式でも一貫していればよく、校正で出版社の書式に直す。
区切りの詳細は未確認である。

## 見本の論文の参考文献

次の文献は、CiNii Research か Crossref で書誌を確かめた。

### 室町期の朝廷

```text
1. 今谷明 1990『室町の王権：足利義満の王権簒奪計画』中央公論社（中公新書）. ISBN 9784121009784. https://cir.nii.ac.jp/crid/1971149384770302872 （叢書の番号 978 は未確認）
2. 富田正弘 1989「室町殿と天皇」『日本史研究』319, pp. 4–48. https://cir.nii.ac.jp/crid/1520572359386553984
3. 富田正弘 2012『中世公家政治文書論』吉川弘文館. ISBN 9784642029094. https://cir.nii.ac.jp/crid/1971993809729667507
4. 松永和浩 2013『室町期公武関係と南北朝内乱』吉川弘文館. ISBN 9784642029117. https://cir.nii.ac.jp/crid/1970867909765746346
5. 水野智之 2005『室町時代公武関係の研究』吉川弘文館. ISBN 4642028471. https://cir.nii.ac.jp/crid/1970586434861559226
6. 水野智之 2008「南北朝・室町期の公武関係論と国家像の展望」『歴史評論』700, pp. 2–15. https://cir.nii.ac.jp/crid/1520853832915931136
7. 久水俊和 2011『室町期の朝廷公事と公武関係』岩田書院（中世史研究叢書 20）. ISBN 9784872947052. https://cir.nii.ac.jp/crid/1971149384754600495
8. 石原比伊呂 2015『室町時代の将軍家と天皇家』勉誠出版. ISBN 9784585221296. https://cir.nii.ac.jp/crid/1971430859869162512
9. 石原比伊呂 2011「室町殿行幸にみる足利義教の位置づけ」『青山史学』29, pp. 1–19. https://cir.nii.ac.jp/crid/1574231876773404544
10. 髙鳥廉 2021「足利将軍家子弟・室町殿猶子の門寺院入室とその意義」『史学雑誌』130 編 9 号, pp. 41–67. DOI 10.24471/shigaku.130.9_41. https://cir.nii.ac.jp/crid/1390574953711185280
```

### ディスコース・ポライトネス理論

```text
1. 宇佐美まゆみ 2001「「ディスコース・ポライトネス」という観点から見た敬語使用の機能：敬語使用の新しい捉え方がポライトネスの談話理論に示唆すること」『語学研究所論集』6, pp. 1–29, 東京外国語大学. DOI 10.15026/21937. https://cir.nii.ac.jp/crid/1390014183332890752
2. 宇佐美まゆみ 2001「談話のポライトネス：ポライトネスの談話理論構想」国立国語研究所『談話のポライトネス』（第 7 回国立国語研究所国際シンポジウム第 4 専門部会）, pp. 9–58. DOI 10.15084/00003587. https://cir.nii.ac.jp/crid/1390855965512482816
3. 宇佐美まゆみ 2002「ポライトネス理論の展開(10) ディスコース・ポライトネス理論構想(4) DP理論の骨格」『言語』31(11), pp. 98–103, 大修館書店. https://cir.nii.ac.jp/crid/1520010379869814144
4. Usami, Mayumi 2002. *Discourse Politeness in Japanese Conversation: Some Implications for a Universal Theory of Politeness*. Hituzi Syobo. https://cir.nii.ac.jp/crid/1971712334836707329 （総ページ数は未確認）
5. 宇佐美まゆみ 2008「相互作用と学習：ディスコース・ポライトネス理論の観点から」西原鈴子・西郡仁朗（編）『講座社会言語科学 第 4 巻 教育・学習』, pp. 150–181, ひつじ書房. https://cir.nii.ac.jp/crid/1010282257009750788
6. 宇佐美まゆみ 2015「『総合的会話分析』の趣旨と方法」『日本語教育』162, pp. 34–49. DOI 10.20721/nihongokyoiku.162.0_34. https://cir.nii.ac.jp/crid/1390282680138738816
7. Brown, Penelope & Stephen C. Levinson 1987. *Politeness: Some Universals in Language Usage*. Cambridge University Press. https://doi.org/10.1017/CBO9780511813085 （Crossref は題を「Politeness」だけにし、Gumperz を著者に誤って含める）
8. Ide, Sachiko 1989. Formal forms and discernment: Two neglected aspects of universals of linguistic politeness. *Multilingua* 8(2–3), 223–248. https://doi.org/10.1515/mult.1989.8.2-3.223
9. Matsumoto, Yoshiko 1988. Reexamination of the universality of face: Politeness phenomena in Japanese. *Journal of Pragmatics* 12(4), 403–426. https://doi.org/10.1016/0378-2166(88)90003-3
10. 滝浦真人 2008『ポライトネス入門』研究社. https://cir.nii.ac.jp/crid/1970586434891254668
11. 井出祥子 2006『わきまえの語用論』大修館書店. https://cir.nii.ac.jp/crid/1971993809775993474
```

### 待遇表現

```text
1. Brown, Penelope & Stephen C. Levinson. 1987. *Politeness: Some universals in language usage*. Cambridge: Cambridge University Press. https://doi.org/10.1017/CBO9780511813085
2. Ide, Sachiko. 1989. 上の 8 と同じ論文。
3. Matsumoto, Yoshiko. 1988. 上の 9 と同じ論文。
4. Agha, Asif. 1994. Honorification. *Annual Review of Anthropology* 23. 277–302. https://doi.org/10.1146/annurev.an.23.100194.001425
5. Okamoto, Shigeko. 1999. Situated politeness: Manipulating honorific and non-honorific expressions in Japanese conversations. *Pragmatics* 9(1). 51–74. https://doi.org/10.1075/prag.9.1.05oka （年は https://benjamins.com/online/prag/list/issue/prag.9.1 による）
6. Pizziconi, Barbara. 2003. Re-examining politeness, face and the Japanese language. *Journal of Pragmatics* 35(10–11). 1471–1506. https://doi.org/10.1016/S0378-2166(02)00200-X
7. Fukada, Atsushi & Noriko Asato. 2004. Universal politeness theory: Application to the use of Japanese honorifics. *Journal of Pragmatics* 36(11). 1991–2002. https://doi.org/10.1016/j.pragma.2003.11.006
8. Haugh, Michael. 2007. The discursive challenge to politeness research: An interactional alternative. *Journal of Politeness Research* 3(2). 295–317. https://doi.org/10.1515/PR.2007.013 （Crossref にページが無く、295–317 は検索の要約による。未確認）
9. Watts, Richard J. 2003. *Politeness*. Cambridge: Cambridge University Press. https://doi.org/10.1017/CBO9780511615184
10. Kádár, Dániel Z. & Michael Haugh. 2013. *Understanding politeness*. Cambridge: Cambridge University Press. https://doi.org/10.1017/CBO9781139382717
11. Pizziconi, Barbara. 2011. Honorifics: The cultural specificity of a universal mechanism in Japanese. In Dániel Z. Kádár & Sara Mills (eds.), *Politeness in East Asia*, 45–70. Cambridge: Cambridge University Press. https://doi.org/10.1017/CBO9780511977886.005 （編者は https://pure.hud.ac.uk/en/publications/politeness-in-east-asia/ による）
```

## 見本で使う著者名の並べ替えのキー

2026-11-27 に、日本語と欧文を混ぜる見本の第一著者のローマ字表記を確認した。
この表記を使い、姓と名をコンマと空白でつないだ `golem-sort-key` を明示する。
漢字から読みを推し量る処理は使わない。

| 著者 | キー | 確認した資料 |
| --- | --- | --- |
| 宇佐美まゆみ | `Usami, Mayumi` | [CiNii Books の著者情報 DA10762367](https://ci.nii.ac.jp/author/DA10762367) |
| 井出祥子 | `Ide, Sachiko` | [CiNii Books の著者情報 DA0072655X](https://ci.nii.ac.jp/author/DA0072655X) |
| 滝浦真人 | `Takiura, Masato` | [国立国語研究所の著者紹介](https://kotoba.ninjal.ac.jp/kokugoken-author/takiura-masato/) |

## 文献スタイルの設計への示唆

調べた書式は、欄の順、区切り、括弧と斜体、著者名の順と略し方、ページの範囲の略し方、一覧の分け方と並べ方、番号の有無で違う。
そのため、文献スタイルは、決まった書式の名前で選べるだけでなく、これらを一つずつ書けなければならない。

室町期の朝廷の論文の投稿先は、一覧でなく、論文の末尾の注に文献を書く。
[ADR 0385](../adr/0385-bibliography-and-citation-styles.md) は一覧（番号の方式か著者と年の方式）を前提にするので、注の形の引用は、そのままでは書けない。
