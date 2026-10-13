# ADR 0023: fixture の変換を Python から移す

ステータス: 採択

## 文脈

テストの fixture の『テンペスト』（`modules/golem-driver/test/fixtures/tempest/tempest.gm`）と『蟹工船』（`kanikosen/kanikosen.gm`）は、`scripts/fixtures/fetch-public-domain.sh` が作る。
このスクリプトは、配布元から原文を取得して SHA-256 を検査し、次の二つの Python のスクリプトで Golem の原稿に変換し、`golem fmt` で整形する。

- `scripts/fixtures/gutenberg_play_to_gm.py`（225 行）：Project Gutenberg のケンブリッジ版の戯曲を変換する。韻文を行の形から推し量って `@style verse` にし、`_…_` を斜体に、話者の名前を `[strong: …]` にする。
- `scripts/fixtures/aozora_to_gm.py`（169 行）：青空文庫のルビ付きの本文を変換する。ルビ（`《》` と `｜`）、傍点、縦中横、見出し、外字の注記を Golem の記法にする。[docs/adr/0013](0013-paragraph-separator.md) の実装で、段落を改行ひとつでつなぐように変わった。

リポジトリの持ち主は Python を使わないので、Python のスクリプトはコミットせず、できる限りシェルスクリプトで書く、という方針がある。
シェルスクリプトで書けない場合は相談する、とも決めている。
この二つは、その方針より前にコミットされたものである。
CI はこの二つを動かさない。
fixture を作り直すときに手で動かすだけである。

### シェルスクリプトで書く場合の難しさ

『テンペスト』の変換は、行の字下げ、行頭の文字、正規表現による行の分類で決まり、扱う文字は ASCII と少数の記号（`—`、`æ`、引用符）である。
POSIX の `sh` と `awk` で書ける。

『蟹工船』の変換は、ルビの親文字を決めるときに、`《` の直前の文字の並びを一字ずつさかのぼり、漢字、片仮名、平仮名、英数字の種類が変わるところで止める。
文字を一字として数える `awk` が要る。
手元の macOS の `/usr/bin/awk`（version 20200816）は、UTF-8 のロケールでも `length("あい")` を 6 と数える。
文字を数えられるのは GNU awk などの一部の実装だけで、POSIX の範囲ではバイトと文字の扱いが実装によって違う。
`sed` と `iconv` を組み合わせても、文字の種類を判定して一字ずつさかのぼる処理は、読めない長さになる。

### 比べた案

- **A：POSIX の sh と awk**：『テンペスト』は書けるが、『蟹工船』のルビの親文字の判定を、どの `awk` でも同じに動くように書くのは難しい。
- **B：sh と GNU awk**：GNU awk を必須にすれば、二つとも `awk` で書ける。macOS には標準で入っていないので、fixture を作り直す人は GNU awk を入れる必要がある。
- **C：Haskell の小さな実行ファイル**：リポジトリの言語で書き、テストと同じ `cabal` で動かす。文字の扱いは `Data.Text` で確かであり、ほかの道具は要らない。リリースの配布物には入れない。

## 実装すること

上の案から **C** を採る。
A は『蟹工船』の変換を確実に書けず、B は fixture を作り直す人に GNU awk という新しい道具を求める。
C はシェルスクリプトで書くという方針から外れるが、方針の「書けない場合は相談する」に従い、リポジトリの持ち主と相談して決めた。

### 変換の実行ファイル

新しいパッケージ `modules/golem-fixtures` を設け、実行ファイル `golem-fixtures` を置く。

```
golem-fixtures gutenberg-play INPUT.txt OUTPUT.gm
golem-fixtures aozora INPUT.txt OUTPUT.gm
```

- 二つの Python のスクリプトの処理を、そのまま Haskell に移す。同じ入力から同じバイト列を出すことを、移す際の基準にする。
- 依存は `base`、`text`、`containers`、`bytestring` だけにする。正規表現は使わず、Python の正規表現が表す行の分類を、文字列の関数で書く。
- `cabal.project` の `packages` に加える。`release.yml` と `scripts/release/` は、このパッケージを配布物に入れない（`golem` の実行ファイルだけを作る今の形のまま）。
- `fetch-public-domain.sh` は、`python3 -I …` の二行を `cabal run -v0 golem-fixtures -- …` に置き換える。
- 二つの `.py` のファイルを削除する。

### ドキュメント

- `modules/golem-driver/test/fixtures/README.md` と、`fetch-public-domain.sh` の先頭のコメントを、新しい変換に合わせて直す。
- CONTRIBUTING.md と CONTRIBUTING.en.md の「テスト用の素材」に、fixture の変換は Python で書かないことを書く。

## 実装しないこと

- 変換の規則の変更。韻文の推し量り方、ルビ、傍点などの扱いは、今の Python のスクリプトのとおりにする。
- 変換を CI で動かすこと。原文の取得にネットワークを使うので、今と同じく手で動かす。
- 原文をリポジトリにコミットすること。

## テスト設計

### 先に書いて失敗させるテスト

- 変換の単体のテストを、小さな入力と期待する出力の組で書く（`modules/golem-fixtures/test/Main.hs`）。
  - 『テンペスト』：話者の名前と斜体、二行以上の韻文の台詞と散文の台詞、字下げした歌、行番号の除去、`--` からダッシュへの置き換え、行頭の特別な文字のエスケープ、ト書き、幕と場の見出し。
  - 『蟹工船』：漢字の親文字のルビ、`｜` で範囲を示したルビ、平仮名に続く漢字の親文字、傍点、縦中横、見出しの三つの大きさ、外字の注記（名前で引くものと `U+` で書いたもの、どちらでもないもの）、レイアウトの注記の除去、底本の情報の節、段落を改行ひとつでつなぐこと。
- 期待する出力は、今の Python のスクリプトを同じ入力に適用して作る。Python は、この期待値を作るときにだけ手元で使い、リポジトリには残さない。

### 自動テストにしない確かめ方

- 二つの原文を `fetch-public-domain.sh` と同じ URL と SHA-256 で取得し、Python のスクリプトと新しい変換の出力が、整形の前と後のどちらでもバイト単位で一致することを確かめる。
- 新しい `fetch-public-domain.sh` で作り直した `tempest.gm` と `kanikosen.gm` が、コミット済みの fixture と一致することを確かめる。一致しない場合は、[docs/adr/0013](0013-paragraph-separator.md) で手でつなぎ直した部分との差を調べ、変換の誤りか fixture の側の誤りかを記録する。

## トレードオフ

- シェルスクリプトで書くという方針から外れる。代わりに、リポジトリがすでに使っている言語と道具だけで済み、文字の扱いが環境によって変わらない。パッケージが一つ増え、`cabal build all` の対象も増える。
- B（sh と GNU awk）は方針に近いが、GNU awk という新しい道具を、fixture を作り直す人に求めるので採らない。
- 規則は今の Python のスクリプトの写しなので、韻文の推し量りの誤り（第一幕第一場の短い散文の台詞を韻文と見なすことなど）も、そのまま残る。

## 参考文献

- POSIX の awk の文字とバイトの扱い：IEEE Std 1003.1-2017 の awk の節（`length` は文字の数を返すと定めるが、実装の対応はまちまちである）。
- GNU Awk User's Guide, "Bytes vs. Characters". https://www.gnu.org/software/gawk/manual/html_node/Bytes-vs-Characters.html
