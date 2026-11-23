# ADR 0411: 書記素と語の分割を Haskell で実装し、依存のないパッケージに置く

Status: accepted

## 文脈

原稿の統計（[ADR 0355](0355-manuscript-statistics.md)）は、書記素の数と語の数を数える。
今は、libgrapheme 3.0.0 の C のソースを golem-cli に同梱し、`golem` の実行ファイルの C のコードから呼んでいる。

拡張した和文組版（[ADR 0380](0380-extended-japanese-composition.md)）も、割注の境界と縦組みの正立の欧文で、書記素の分割を使う。
Codex の PR #1062 は、libgrapheme を golem-syntax に移し、Haskell から `unsafePerformIO` で呼ぶ関数を足した。
この関数は [ADR 0034](0034-fewer-unsafe-perform-io.md) の許可の一覧になく、CI の検査で落ちる。
Codex はこの関数を許す案を出したが、tett23 は採択しなかった。

tett23 は 2026-11-23 に、次のことを決めた。

- 書記素と語の分割を、libgrapheme の実装とテストを参考に、Haskell で再実装する（libgrapheme は ISC ライセンス）。
- golem-html は golem-layout に依存しない形にする。
- 必要なら、新しいパッケージを作ってよい。

## 調査した事項

`origin/main`（`b540aa68a`）と PR #1062 の `bae0cbf8f` で確かめた。
上流のリポジトリは `ghq` で取得して読んだ。

- 同梱の版は libgrapheme 3.0.0 である（`modules/golem-cli/cbits/libgrapheme/SOURCE`）。
  上流のタグ 3.0.0 の 7 つのファイルと、同梱のファイルは同じ内容である（`diff -q`）。
  上流の Makefile の `UNICODE_VERSION` は 17.0.0 である。
- golem-cli の `stats.c` が使う関数は、次の三つである。
  - `grapheme_next_word_break_utf8`：語の区間を取る。区間に一般カテゴリ L か N の字が一つでもあれば、一語と数える。L と N の判定は、UnicodeData.txt（Unicode 17.0.0）から作った表の二分探索である。
  - `grapheme_decode_utf8`：上の判定のために、UTF-8 を解く。
  - `grapheme_next_character_break_utf8`：書記素の数を数える。
- 上流のテストは、二種類である。
  - 適合テスト：Unicode の `GraphemeBreakTest.txt`（データ行 766）と `WordBreakTest.txt`（データ行 1944）から生成する。
  - 手で書いた単体テスト：書記素と語で、それぞれ 12 件ある（空の入力、NUL 終端、断片など）。
  上流のテストを手元で走らせて通るかは、確かめていない（未確認）。
- PR #1062 で書記素の分割を呼ぶのは、次の箇所である。
  - golem-layout：割注を二行に分ける位置、縦組みの正立の欧文を書記素ごとの箱にすること、割注の幅を書記素ごとに測ること。
  - golem-typeset：PDF で割注の各行の書記素を置くこと。
  - golem-html：字送りを指定したときに欧文でない書記素を包むこと、割注を書記素の数で半分に分けること。
- PR #1062 は、golem-html の build-depends に golem-layout を足す。
  golem-html が使うのは `Golem.Layout.CharClass` の `charClass` と `CharClass` だけで、欧文かどうかの判定に使う。
  `Golem.Layout.CharClass` は、golem の他のパッケージに依存しない（import は `Data.Char`、`Data.IntSet`、`Data.Text` だけ）。
  golem-layout は golem-project に依存するので、この依存を足すと、golem-html が golem-project も引き込む。
  [ADR 0090](0090-html-settings-conversion-stays-in-driver.md) は、golem-html が golem-project に依存しないと決めている。
- main の Haskell には、書記素と語の分割がない。
  代わりに、「基底の字と、その後に続く結合文字（Mn、Mc、Me）」という近似が、golem-eval、golem-layout、golem-preflight、golem-regex の 4 か所にある。
- 依存のないパッケージを下の層に作った前例は、[ADR 0114](0114-sp-in-a-length-package.md) の golem-length である。
- Unicode の表を生成する前例は `scripts/gen-vertical-orientation.sh` である。
  データのファイルはパスで受け取り、何もダウンロードしない。
  生成したモジュールの先頭に、生成したスクリプトと Unicode の版を書く。
  このスクリプトの表は Unicode 18.0.0 のデータから作っている。

## 実装すること

### パッケージ

依存のない新しいパッケージ golem-unicode を作る。
library の依存は base、containers、text だけにする。
wasm でも組めるパッケージとする（[ADR 0202](0202-packages-that-do-not-build-for-wasm.md) の除外に入れない）。

golem-unicode には、次のモジュールを置く。

- `Golem.Unicode.Grapheme`：拡張書記素クラスタの分割（UAX #29 の GB 規則）。
- `Golem.Unicode.Word`：語の境界（UAX #29 の WB 規則）。
- `Golem.Unicode.Category`：一般カテゴリが L か N かの判定。
- `Golem.Unicode.CharClass`：今の `Golem.Layout.CharClass` を移したもの。

golem-layout は `Golem.Unicode.CharClass` を使い、`Golem.Layout.CharClass` は消す。
golem-html は golem-unicode に依存し、golem-layout には依存しない。
今 `Golem.Layout.CharClass` を使う golem-typeset のライブラリと golem-driver のテストは、`Golem.Unicode.CharClass` に替える。
`Golem.Layout.CharClass` は消し、golem-layout から再び export しない。
golem-unicode に依存させるのは、golem-layout、golem-typeset、golem-html、golem-cli のライブラリ（golem-cli は実行ファイル）と、golem-driver のテストである。

### 分割の関数

- 書記素の分割と語の分割は、`Text` を受け取って `[Text]` を返す純粋な関数とする。
  FFI と `unsafePerformIO` は使わない。
- 規則は、libgrapheme 3.0.0 の `src/character.c` と `src/word.c` の書き方を参考にし、UAX #29 の規則の番号ごとに書く。
- 字の性質の表（Grapheme_Cluster_Break、Word_Break、Extended_Pictographic、Indic_Conjunct_Break、一般カテゴリ）は、Unicode 17.0.0 のデータファイルから生成する。
  版は、今の libgrapheme と同じ 17.0.0 にそろえる。
  統計の結果を変えないためである。

### 表の生成

- 生成のスクリプトは `scripts/gen-unicode-segmentation.sh` とし、`scripts/gen-vertical-orientation.sh` と同じく POSIX の sh と awk で書く。
  データのファイルはパスで受け取り、ダウンロードしない。
- 生成したモジュールの先頭に、生成したスクリプト、Unicode の版、Unicode License v3 の表記を書く。
- データのファイルの取り方（URL と SHA-256）は、スクリプトの冒頭の注釈に書く。
- 適合テストのデータ（`GraphemeBreakTest-17.0.0.txt` と `WordBreakTest-17.0.0.txt`）は、golem-unicode のテストのディレクトリにコミットする。
  Unicode License を同じディレクトリに置く。

### 呼ぶ側

- golem-cli の統計を、golem-unicode の関数で数える Haskell の実装に替える。
  `stats.c` と、同梱の libgrapheme の C のソースとヘッダーを消す。
- 配布物のライセンスの一覧（`scripts/release/licenses.sh`）から libgrapheme を消し、golem-unicode が参考にした libgrapheme の ISC ライセンスの表記と、Unicode のデータの Unicode License を残す。
  libgrapheme の実装を参考にしたことは、golem-unicode のモジュールの冒頭にも書く。
- PR #1062 の書記素の分割の呼び出しは、golem-unicode の `Golem.Unicode.Grapheme` に替える。
  PR #1062 が golem-syntax に移した libgrapheme の C と、`Golem.Syntax.Grapheme` は入れない。

### 仕様書

- 仕様書のモジュール構成の図と一覧に golem-unicode を足し、golem-html と golem-layout の依存の矢印を直す。
- 仕様書の原稿の統計の節に、書記素と語の数え方が golem-unicode（UAX #29、Unicode 17.0.0）によることを書く。

## 実装しないこと

- `Golem.Unicode.CharClass` の一般カテゴリの判定は、移した後も今と同じく `Data.Char.generalCategory`（GHC の base が持つ Unicode の版）を使う。
  `Golem.Unicode.Category` の表（17.0.0）にそろえると行分割の結果が変わりうるので、そろえるときは別の ADR で決める。

- golem-eval、golem-layout、golem-preflight、golem-regex にある「基底の字と結合文字」の近似は、この ADR では書記素の分割に替えない。
  それぞれ結果が変わりうるので、替えるときは別の ADR で決める。
- 行分割（UAX #14）と文の境界は実装しない。
- Unicode の版を、縦書きの向きの表（18.0.0）とそろえることは、この ADR では扱わない。
  そろえるときは別の ADR で決める。

## 不変条件

- I1：`GraphemeBreakTest-17.0.0.txt` のどのデータ行でも、`Golem.Unicode.Grapheme` の分割は、その行が示す境界と一致する。
- I2：`WordBreakTest-17.0.0.txt` のどのデータ行でも、`Golem.Unicode.Word` の分割は、その行が示す境界と一致する。
- I3：どの入力でも、書記素の分割と語の分割の結果をつなぐと、入力に等しく、結果のどの要素も空でない。
- I4：どの入力でも、golem-unicode で数えた書記素の数と語の数は、置き換える前の libgrapheme 3.0.0 の C の実装で数えた数と等しい。
- I5：golem-html と golem-unicode の library の build-depends は、golem-layout と golem-project を含まない。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| 空の文字列 | 書記素も語も空の列 | I3, I4 |
| 一字（`a`、`あ`） | 一つの書記素、一つの区間 | I3, I4 |
| 結合文字の続く字（`か` と U+3099、`e` と U+0301） | 一つの書記素 | I3 |
| 家族の絵文字（ZWJ でつないだ列） | 一つの書記素 | I3, I4 |
| 国旗の地域指示記号の対が二つ | 二つの書記素 | I3 |
| CR と LF | 一つの書記素 | I3 |
| 英語の文（`can't stop.`） | WB の規則どおりの区間 | I3, I4 |
| 和文と欧文の混在 | WB の規則どおりの区間 | I3, I4 |
| 不正な並び（孤立したサロゲートは `Text` に入らないので、U+FFFD を含む列） | 規則どおりに分ける | I3 |

## 受けいれ条件

なし。
この ADR の振る舞いは、不変条件のテストで確かめる。

## テスト設計

- golem-unicode にテストのスイートを作る。
  名前は `root ADR 0411 I<番号>: ...` とする。
- I1 と I2 は、コミットした適合テストのデータの全行を読んで確かめる。
  テストを先に書き、分割の関数が空の実装のときに失敗することを確かめる。
- I3 は、Hedgehog の性質テストで、任意の Unicode の字の列について確かめる。
- I4 は、C の実装を消す前の段で、C の実装がある golem-cli のテストのスイートで確かめる。
  比べる字の集合は、`a`、`'`、空白、`あ`、`ア`、`漢`、U+0301、U+200D、U+1F468、U+1F1EF、U+1F1F5、CR、LF、`1`、`.` の 15 字とする。
  その長さ 0 から 4 のすべての並びについて、golem-unicode と libgrapheme の C の数が等しいことを確かめ、結果を実装のプルリクエストに書く。
  C を消した後は、この比較の結果を golden（`modules/golem-unicode/test/data/libgrapheme-3.0.0-counts.tsv`）として残し、golem-unicode のテストのスイートが、golem-unicode の数がそれと等しいことを確かめる。
- 境界の表の行は、I3 と I4 のテストに、行ごとの期待する分割を書いた単体のテストとして置く。
- I5 は、`scripts/ci/test.sh` に、二つの .cabal の library の build-depends を読む検査を足す。
- 上流の手で書いた単体テスト（書記素と語で各 12 件）のうち、`Text` の入力に意味のあるもの（空の入力、断片など）を写す。
- [ADR 0355](0355-manuscript-statistics.md) と [ADR 0380](0380-extended-japanese-composition.md) の今のテストが、置き換えた後も通ることを確かめる。

## トレードオフ

C の libgrapheme を使い続ければ、実装は要らない。
しかし、Haskell から呼ぶには FFI と `unsafePerformIO` が要り、wasm の配布物にも C を持ち込む。
Haskell で書けば、純粋な関数として扱え、wasm でもそのまま組める。
代償は、UAX #29 の規則と表を自分で保つことであり、Unicode の版を上げるたびに表を作り直す。
適合テストのデータを版ごとに差し替えれば、規則の誤りは検出できる。

`Golem.Layout.CharClass` を新しいパッケージに移すと、golem-layout の利用者は import を書き換える必要がある。
golem-html に欧文の判定だけを写す方法もあるが、二つの判定が食い違うおそれがあるので採らない。

## 参考文献

- [ADR 0355](0355-manuscript-statistics.md)
- [ADR 0380](0380-extended-japanese-composition.md)
- [ADR 0034](0034-fewer-unsafe-perform-io.md)
- [ADR 0090](0090-html-settings-conversion-stays-in-driver.md)
- [ADR 0114](0114-sp-in-a-length-package.md)
- [ADR 0202](0202-packages-that-do-not-build-for-wasm.md)
- [ADR 0007](0007-third-party-licenses.md)
- Unicode Standard Annex #29, Unicode Text Segmentation：<https://www.unicode.org/reports/tr29/>
- libgrapheme 3.0.0：<https://libs.suckless.org/libgrapheme/>
