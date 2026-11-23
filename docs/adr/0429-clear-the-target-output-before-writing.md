# ADR 0429: ターゲットの出力のフォルダーを、書く前に消す

Status: proposed

## 文脈

仕様書は、`golem build` の出力について「プロジェクトルートの `build` の下のターゲットごとのディレクトリ（`build/html` など）に、前の出力を消してから書く」と書いている。
この文には ADR へのリンクが無く、この決まりを決めた ADR は見つからなかった。
実装はこの決まりのとおりに動いているが、決まりの範囲（どのターゲットを、いつ、どこまで消すか）は書かれておらず、それを確かめるテストも無い。

失敗したときの片付けは、いくつかの ADR が個別に決めている。

- PDF は、[root ADR 0326](0326-discard-stale-pdf-after-build-errors.md) が、prod のビルドでエラーのために今回の PDF を書けなかったときに片付けると決めている。
- PDF は、prod で G08100、G08103、G07127、G07128 が出たときにも、前の PDF を消す（[root ADR 0081](0081-missing-glyphs-warn-in-build.md)、[root ADR 0268](0268-opentype-features-on-character-styles.md)、[root ADR 0389](0389-diagnose-caption-and-sidenote-indents-that-leave-no-width.md)）。
- 図版の色を変換できないとき（G08113）は、[root ADR 0403](0403-include-grayscale-tones-in-single-color-figures.md)、[root ADR 0406](0406-limit-jpeg-figure-color-decoding.md)、[root ADR 0407](0407-reject-svg-figures-that-cannot-be-recolored.md)、[root ADR 0425](0425-classify-colors-of-imported-pdf-figures.md) が、その媒体の古い出力を残さないと決めている。

EPUB の固定ページ対応表（page-map）を読めないときに `build/epub` を消すことは、実装にはあるが、[root ADR 0386](0386-page-list-and-page-colors.md) は決めていない。
0386 が決めているのは、古い原稿を指す対応表をエラーにすることだけである。

この ADR は、書くときの決まりを、今の振る舞いのとおりに決めて記録し、テストで確かめる。
あわせて、page-map を読めないときに `build/epub` を消すことを、0386 の補足として決める。
ほかの失敗したときの片付けは、今の ADR の決まりを変えない。

## 調査した事項

origin/main（[e4807fb22](https://github.com/tett23/golem/commit/e4807fb22a982139ffb7b7790332d760fa0a2422)）で、次のことを確かめた。

- `cleanDir` は、フォルダーがあれば中身ごと消すだけの関数である（[Driver.hs#L1696-L1699](https://github.com/tett23/golem/blob/e4807fb22a982139ffb7b7790332d760fa0a2422/modules/golem-driver/src/Golem/Driver.hs#L1696-L1699)）。
- 書くターゲットは、選んだターゲットのうち、ターゲットごとのエラー（G07001 系、G08014 など）で外れなかったものである。
  `writeTargets` は、何かを消すか書く前に、`build` と書くターゲットのフォルダーがシンボリックリンクか通常のファイルでないかを調べる。
  一つでも当たれば、どのターゲットも消さず書かずに、問題のフォルダーごとに G08013 か G08104 を返す（[Driver.hs#L1254-L1260](https://github.com/tett23/golem/blob/e4807fb22a982139ffb7b7790332d760fa0a2422/modules/golem-driver/src/Golem/Driver.hs#L1254-L1260)、[root ADR 0035](0035-security-hardening.md)、[root ADR 0329](0329-output-path-file-diagnostic.md)）。
  選んでも書かないターゲットのフォルダーは調べない。
- 書くときは、ターゲットごとに、そのフォルダーを `cleanDir` で消してから書き、書いたファイルをすべて返す。
  - HTML: `build/html` を消してから、ページ、`style.css`、`index.xhtml`、写した素材を書く（[Driver.hs#L1432-L1443](https://github.com/tett23/golem/blob/e4807fb22a982139ffb7b7790332d760fa0a2422/modules/golem-driver/src/Golem/Driver.hs#L1432-L1443)）。
  - EPUB: `build/epub` を消してから `book.epub` を書く（[Driver.hs#L1530-L1533](https://github.com/tett23/golem/blob/e4807fb22a982139ffb7b7790332d760fa0a2422/modules/golem-driver/src/Golem/Driver.hs#L1530-L1533)）。
    page-map を読めないときも、`build/epub` を消して page-map の diagnostic（G03272 から G03277 のどれか）を返す（[Driver.hs#L1517-L1527](https://github.com/tett23/golem/blob/e4807fb22a982139ffb7b7790332d760fa0a2422/modules/golem-driver/src/Golem/Driver.hs#L1517-L1527)）。
  - プレーンテキスト: `build/text` を消してから、縦書きと横書きのうち生成するものを書く（[Driver.hs#L1554-L1563](https://github.com/tett23/golem/blob/e4807fb22a982139ffb7b7790332d760fa0a2422/modules/golem-driver/src/Golem/Driver.hs#L1554-L1563)）。
    生成しない側の古いサブフォルダーも消える。
  - PDF: `build/pdf` を消してから、PDF と `pages.json` を書く（[Driver.hs#L1594-L1600](https://github.com/tett23/golem/blob/e4807fb22a982139ffb7b7790332d760fa0a2422/modules/golem-driver/src/Golem/Driver.hs#L1594-L1600)）。
- 書き込みの後、`build` は、プロジェクトのルート、`build`、選んだターゲットのフォルダーの通常の `.DS_Store` を取り除く（[root ADR 0329](0329-output-path-file-diagnostic.md)）。
  出力先の検査に落ちたときも、この片付けは行う。
  prod では、PDF を選び、エラーで今回の PDF を書けなかったとき、`build/pdf` だけを調べ直して片付ける（[Driver.hs#L905-L909](https://github.com/tett23/golem/blob/e4807fb22a982139ffb7b7790332d760fa0a2422/modules/golem-driver/src/Golem/Driver.hs#L905-L909)、[root ADR 0326](0326-discard-stale-pdf-after-build-errors.md)）。
  そのため、兄弟の `build/html` がリンクでも、安全な `build/pdf` は片付ける。
- 選んでいないターゲットのフォルダーは、調べず、消さず、書かない。
- 今あるテストは、PDF の失敗の片付け（0326 の B1 から B4）、出力先のリンクとファイル（0329 の O1 と O2）、色の変換の失敗の片付け（0403、0406、0407 の不変条件）、HTML を書いても `build/pdf` の別のファイルが残ることを確かめる。
  成功したときに、前の出力のうち今回書かないファイルが消えることを確かめるテストは、どのターゲットにも見つからなかった。
  page-map を読めないときに `build/epub` が消えることのテストも見つからなかった。
- 原稿や評価のエラーで書き込みに入らないときは、PDF の prod のほかは、前の出力が残る。

指示者は 2026-11-23 に、この決まりの ADR が無ければ書くよう求めた。

## 実装すること

### 言葉

この ADR では、次の言葉を使う。

- **書くターゲット**：選んだターゲットのうち、ターゲットごとのエラーで外れなかったもの。
- **書き込みに入ったビルド**：`writeTargets` の出力先の検査を通ったビルド。
- **書き込みに成功したターゲット**：今回書いたファイルをビルドの結果の書いたファイルの一覧（`brWritten`）に返したターゲット。

### 書くときの決まり

`golem build` がターゲットを書くときは、次の順で行う。

1. `build` と、すべての書くターゲットのフォルダーを調べる。
   一つでもシンボリックリンクか通常のファイルなら、どのターゲットも消さず書かずに、問題のフォルダーごとに G08013 か G08104 を返す（[root ADR 0035](0035-security-hardening.md)、[root ADR 0329](0329-output-path-file-diagnostic.md)）。
2. 書くターゲットごとに、そのフォルダー（`build/html`、`build/epub`、`build/text`、`build/pdf`）を中身ごと消す。
3. そのフォルダーを作り、今回の出力を書く。

こうすれば、書き込みに成功したターゲットのフォルダーには、今回のビルドが書いたファイルだけが残る。
前のビルドが書いた別の名前のファイル（消した章のページ、生成をやめた縦書きのテキストなど）が、古いまま残らない。

書き込みのときに消すのは、書くターゲットのフォルダーだけとする。
選んでいないターゲットのフォルダーと、選んでも書かないターゲットのフォルダーは、書き込みのときには調べず、消さず、書かない。
失敗したときに消すフォルダーは、次の節に従う。
`build` の直下とプロジェクトのルートのファイルには、[root ADR 0329](0329-output-path-file-diagnostic.md) の `.DS_Store` の片付けのほかは触れない。

### 失敗したときの決まり

失敗したときの片付けは、今の ADR の決まりのままとする。

- PDF は、[root ADR 0326](0326-discard-stale-pdf-after-build-errors.md)、[root ADR 0081](0081-missing-glyphs-warn-in-build.md)、[root ADR 0268](0268-opentype-features-on-character-styles.md)、[root ADR 0389](0389-diagnose-caption-and-sidenote-indents-that-leave-no-width.md) のとおりに片付ける。
- 図版の色を変換できないときは、[root ADR 0403](0403-include-grayscale-tones-in-single-color-figures.md)、[root ADR 0406](0406-limit-jpeg-figure-color-decoding.md)、[root ADR 0407](0407-reject-svg-figures-that-cannot-be-recolored.md)、[root ADR 0425](0425-classify-colors-of-imported-pdf-figures.md) のとおり、その媒体のフォルダーを片付ける。

この ADR は、次の片付けを足す。

- EPUB の page-map を読めないときは、`build/epub` を片付け、page-map の diagnostic を返す。
  前のビルドの EPUB が、古い対応表のまま成功した成果物として残らないためである。
  これは [root ADR 0386](0386-page-list-and-page-colors.md) の補足である。

これらのほかの失敗（原稿や評価のエラーで書き込みに入らないときなど）で、HTML、EPUB、プレーンテキストの前の出力を片付けるかは、この ADR では決めない。

### 文書

仕様書の「前の出力を消してから書く」の文に、この ADR へのリンクを付け、消すのは書くターゲットのフォルダーだけであることを書き足す。
同じ段落の「選んだターゲットの出力フォルダーがシンボリックリンクなら」を、「書くターゲットの出力フォルダーがシンボリックリンクなら」に直す。
仕様書の固定ページ対応表の節に、page-map を読めないときに `build/epub` を片付けることを書き足す。

### ステータスの行

採択したら、[root ADR 0386](0386-page-list-and-page-colors.md) のステータスを、`superseded-pending [{"part":"page-map を読めないときの EPUB の出力","by":["docs/adr/0429-clear-the-target-output-before-writing.md"],"kind":"supplement"}]` にする。
ほかの ADR の決まりは変えないので、ステータスの行を変えない。

## 実装しないこと

失敗したときの片付けの範囲を、page-map のほかには広げない。
`build` の直下のターゲットのフォルダーではないファイルやフォルダーを、`.DS_Store` のほかは消さない。
`check`、`preflight`、メモリ上のビルドの振る舞いを変えない。

## 不変条件

- I1: 書き込みに成功したターゲットのフォルダーにある、`.DS_Store` のほかのファイルの集合は、そのターゲットが `brWritten` に返したファイルの集合と等しい。
- I2: 書き込みに入ったビルドは、選んでいないターゲットのフォルダーの中身を変えない。
- I3: `build` か書くターゲットのフォルダーのどれかがシンボリックリンクか通常のファイルなら、どのターゲットのフォルダーにも書かず、[root ADR 0326](0326-discard-stale-pdf-after-build-errors.md) の prod の片付けと、[root ADR 0329](0329-output-path-file-diagnostic.md) の `.DS_Store` の片付けのほかは消さない。
- I4: EPUB の page-map を読めないとき、`build/epub` は残らず、page-map の diagnostic（G03272 から G03277 のどれか）が返る。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| 前の `build/html` に今回書かない `old.html` がある状態で HTML を書く | `old.html` が消え、`brWritten` のファイルだけが残る | I1 |
| 前の `build/epub` に今回書かない `old.txt` がある状態で EPUB を書く | `book.epub` だけが残る | I1 |
| 前に縦書きと横書きを書き、今回は横書きだけを書く | 縦書きのサブフォルダーが消える | I1 |
| 前の `build/pdf` に今回書かない `old.pdf` がある状態で PDF を書く | PDF と `pages.json` だけが残る | I1 |
| 前の出力が無い状態で書く | `brWritten` のファイルだけがある | I1 |
| `--target html` で書き、`build/pdf` と `build/epub` に前の出力がある | `build/pdf` と `build/epub` は変わらない | I2 |
| dev で、`build/epub` がシンボリックリンクで、`--target html,epub` で書く | どのフォルダーも、`.DS_Store` のほかは変わらず G08013 | I3 |
| dev で、`build/text` が通常のファイルで、`--target html,text` で書く | どのフォルダーも、`.DS_Store` のほかは変わらず G08104 | I3 |
| prod で、`build/html` がシンボリックリンクで、四つのターゲットを書く | G08013 が返り、`build/pdf` は片付けられ、ほかは変わらない | I3 |
| `build` そのものがシンボリックリンク | どのフォルダーも変わらず G08013 | I3 |
| 前の `build/epub` があり、page-map の参照先のファイルが無い | `build/epub` が無く、G03272 が返る | I4 |

## 受けいれ条件

なし。
不変条件のテストで足りるためである。

## テスト設計

root ADR 0429 I1 から I4 を名前の先頭に置いたテストを、golem-driver のテストに足す。
I1 は、ターゲットごとに、前のビルドの出力に今回書かないファイルを置いてからビルドし、ビルドの後のフォルダーのファイルの集合が、`brWritten` のそのターゲットのファイルの集合と等しいことを確かめる。
`brWritten` が書いたファイルを返し漏らしても見つかるように、ターゲットごとに期待するファイル名を固定した行（EPUB なら `book.epub` だけ、PDF なら PDF と `pages.json`）も確かめる。
I2 は、`--target` で一つのターゲットを選び、選んでいないターゲットのフォルダーの、ビルドの前と後のファイルの名前と中身が等しいことを確かめる。
I3 は、[root ADR 0329](0329-output-path-file-diagnostic.md) の今のテストに、ビルドの前と後のすべてのターゲットのフォルダーが、`.DS_Store` を除いて等しいことの確かめを足し、prod で PDF を含む行を足す。
I4 は、前の EPUB のビルドを残してから、page-map の参照先を消してビルドし、`build/epub` が無いことと G03272 を確かめる。
どれも今の振る舞いを確かめるテストなので、実装の前にも通ることがある。
通らなければ、仕様書と食い違う不具合として直す。

## トレードオフ

書くたびにターゲットのフォルダーを丸ごと消すので、利用者がそのフォルダーに置いたファイルも消える。
その代わりに、出力のフォルダーには今回のビルドの成果物だけが残り、消した章の古いページなどが混ざらない。
利用者のファイルは、`build` の外に置く必要がある。

失敗したときの片付けをターゲットごとの ADR に任せたままにするので、原稿のエラーで止まったときに、HTML、EPUB、プレーンテキストの前の出力が残る。
これを片付けるかどうかは、別の ADR で決める。

## 参考文献

- [root ADR 0035](0035-security-hardening.md)
- [root ADR 0081](0081-missing-glyphs-warn-in-build.md)
- [root ADR 0268](0268-opentype-features-on-character-styles.md)
- [root ADR 0326](0326-discard-stale-pdf-after-build-errors.md)
- [root ADR 0329](0329-output-path-file-diagnostic.md)
- [root ADR 0386](0386-page-list-and-page-colors.md)
- [root ADR 0389](0389-diagnose-caption-and-sidenote-indents-that-leave-no-width.md)
- [root ADR 0403](0403-include-grayscale-tones-in-single-color-figures.md)
- [root ADR 0406](0406-limit-jpeg-figure-color-decoding.md)
- [root ADR 0407](0407-reject-svg-figures-that-cannot-be-recolored.md)
- [root ADR 0425](0425-classify-colors-of-imported-pdf-figures.md)
- [golem-cli ADR 0002](../golem-cli/adr/0002-build-all-targets-by-default.md)
