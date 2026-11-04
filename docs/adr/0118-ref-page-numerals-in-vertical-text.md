# ADR 0118: 縦組みの ref-page のページ番号の表記

ステータス: 採択

## 文脈

仕様書は、ページ番号への参照を、表記の決まっていない数（Number）に解決するとしている（[docs/specifications.md](../specifications.md) の「目次と文書構造の参照」）。
ページ番号も数なので、縦組みと横組みの表記の使い分けは、ほかの数と同じ経路で行うとも書いている。
縦組みの数の表記は、`style.toml` の `[numbers]` の `vertical` で決まり、既定は位取りをする漢数字である（[golem-parser ADR 0011](../golem-parser/adr/0011-number-shorthand.md)）。

実装は仕様に合っていない。
PDF のレイアウトは、`[ref-page]` のページ番号を算用数字の文字列にして組む（[`piecesOf`](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-layout/src/Golem/Layout/Japanese.hs#L284-L286)）。
縦組みでは、その算用数字が横に倒れて組まれる。
同じ本の索引、目次、チャネルの一覧のページ番号は、`[numbers]` の `vertical` に従って漢数字になる。
一冊の中で、ページ番号の表記が二通りに分かれている。

用語集のプラグイン（[docs/adr/0126](0126-glossary-plugin.md)）を試したときに、この食い違いが見つかった。
一覧の項目の本文に入れた参照のページは「（→2）」と横に倒れ、同じ項目の出現のページは「一、二」だった。

仕様のとおりに漢数字にすれば、食い違いはなくなる。
ただし、縦組みでも参照のページだけは算用数字にしたい本がある。
技術書や、ページ番号を算用数字のノンブルで振る本では、本文の「12 ページ」を漢数字の「十二ページ」にすると、ノンブルと見た目が合わない。

## 実装すること

### 既定

縦組みの PDF の `[ref-page]` のページ番号は、`[numbers]` の `vertical` の表記で組む。
既定の `vertical` は `kanji` なので、何も書かない本では漢数字になる。
これは仕様の今の文のとおりであり、実装を仕様に合わせる変更である。

### 設定

`style.toml` の `[numbers]` に、キー `ref-page` を足す。

```toml
[numbers]
vertical = "kanji"
ref-page = "sideways"
```

| 値 | 縦組みの `[ref-page]` の表記 |
| --- | --- |
| （省く） | `vertical` と同じ |
| `kanji`、`kanji-digits`、`tcy`、`auto`、`auto-digits` | `vertical` の同じ名前の表記 |
| `sideways` | 算用数字を横に倒して組む（今までの表記） |

置き場所を `[numbers]` にしたのは、縦組みの数の表記を決める設定がすでにそこにあるからである。
値の名前を `vertical` と揃えたので、利用者は新しい名前を覚えずに済む。
算用数字にしたい本には、二つの形を用意した。
縦中横にしたい本は `tcy` を、欧文と同じく横に倒したい本は `sideways` を選ぶ。

### 媒体ごとの振る舞い

| 媒体 | `ref-page` の効果 |
| --- | --- |
| PDF（縦組み） | 上の表のとおり |
| PDF（横組み） | なし。いつも算用数字 |
| HTML と EPUB | なし。`[ref-page]` は参照先の題へのリンクで、数を出さない |
| プレーンテキスト | なし。`[ref-page]` は「」で括った題で、数を出さない |

索引、目次、チャネルの一覧のページ番号は、`ref-page` によらず `vertical` に従う。
`ref-page` は、原稿とプラグインの出力に現れるページ番号への参照（DeferredRef）だけを決める。

### diagnostic

`ref-page` に上の六つでない値を書くと、`vertical` の値の誤りと同じく G03006 とする。
メッセージは `ref-page に使えない値です: <値>（kanji, kanji-digits, tcy, auto, auto-digits, sideways のどれか）` である。
新しいコードは作らない。
G03006 は `style.toml` のキーと値の誤りのコードであり、値の誤りという原因は `vertical` と同じだからである。

### モジュールの変更

golem-* のパッケージのあいだの build-depends は変えない。

- **golem-project**：`Style` に `stNumbersRefPage :: Maybe Text` を足し、`[numbers]` の `ref-page` を読む（[`Numbers`](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-project/src/Golem/Project/Style.hs#L1681-L1684)）。
- **golem-layout**：`ComposeEnv` に `ceRefPageNumbers :: Maybe VerticalNumbers` を足す。`Nothing` は `sideways` である。縦組みでは、ページ番号を `numberPieces` で組む。
- **golem-driver**：PDF の `ComposeEnv` に、`ref-page` か、なければ `vertical` から作った値を渡す（[Flow.hs](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L1020)）。

## 実装しないこと

- 索引、目次、チャネルの一覧のページ番号に、別の表記を選ばせること。今は `vertical` に従っており、分けたい本が現れてから決める。
- `[ref-page]` ごとに表記を選ぶ引数（`[ref-page later style=tcy]`）。本の全体で一つの表記に揃えるのが組版の慣習であり、混ぜる必要が見えていない。
- ノンブル（`{n}`）の表記を `ref-page` に揃えること。ノンブルの書式は `[masters]` の `format` で決まる。
- HTML と EPUB で、参照にページ番号を出すこと。

## テスト設計

先に次のテストを書き、今の実装で失敗することを確かめてから実装した。

golem-driver のテスト（`ReferencesSpec` の `refPageNumeralTests`）で、ラベルを指定したページに置き、参照の行の文字列を確かめる。

- 縦組みで、`vertical = "kanji"` のとき、1 ページめの参照が「一」になる。
- 縦組みで、`ref-page` を省き `vertical = "kanji-digits"` のとき、12 ページめの参照が「一二」になる。
- 縦組みで、`vertical = "kanji-digits"`、`ref-page = "kanji"` のとき、「十二」になる。
- 縦組みで、`ref-page = "sideways"` のとき、「12」になる。
- 横組みで、`ref-page = "kanji"` のとき、「1」のままである。

golem-project のテストで、次を確かめる。

- `ref-page` を省くと `Nothing`、`sideways` と `auto-digits` が読める。
- `arabic` が G03006 になり、メッセージに六つの値が並ぶ。

`tcy` と `sideways` は、行の文字列ではどちらも「12」になるので、このテストでは区別していない。
縦中横の箱になることは、`numberPieces` の既存の経路に任せている。

## トレードオフ

既定を漢数字に変えるので、縦組みで `[ref-page]` を使っている本は、設定を書かなければ出力が変わる。
今までの表記に戻すには `ref-page = "sideways"` を書く。
仕様と食い違ったままの実装に本が依存するより、仕様に合わせて戻す道を一つ用意するほうを選んだ。

漢数字は算用数字より字数が多いので（12 が「十二」、100 が「百」）、参照を含む行の長さが変わり、改ページが動くことがある。
ページ番号の参照は、もともとレイアウトを収束するまで繰り返して決めるので、表記が変わっても決定性は保たれる。

## 決めたことの記録

- 2026-10-29、メンテナー：縦組みの `[ref-page]` は、仕様のとおり既定で漢数字にする。縦組みでも算用数字を選びたい本のために、rc4 で `style.toml` の設定を足す。
- 実装は、プラグインのブランチとは別のローカルのブランチ `ref-page-vertical-numerals`（origin/main から分岐）で試す。

## 参考文献

- [golem-parser ADR 0011](../golem-parser/adr/0011-number-shorthand.md)。
- W3C, Requirements for Japanese Text Layout（JLReq）。https://www.w3.org/TR/jlreq/
