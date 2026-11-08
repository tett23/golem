# ADR 0214: `mark-size` と注の印の文字スタイルの `size` がぶつかるときのメッセージ

ステータス: 採択

## 文脈

[ADR 0177](0177-note-mark-style-and-numerals.md) は、`[notes]` の `mark-size` を廃止予定とし、注の印の大きさを組み込みの文字スタイル `note-mark` の `size` で決めることにした。
廃止までのあいだ、`mark-size` は本文の印の文字スタイルの `size` の省略形として読む。
大きさを決める値が二つあると、どちらかを黙って捨てることになるので、0177 は次の組み合わせを G03006 のエラーとした。

> `mark-size` と、`size` を持つ（`based-on` の先を含む）文字スタイルを指す `mark-style` を一緒に書くと、G03006 とする。

メッセージは `[notes] の mark-size と、size を持つ mark-style <名前> は一緒に書けません` である。
0177 が決めたのは、書き手が `mark-style` を書いた場合だけである。

### 実装が足した場合

実装（[`markSizeConflict`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-project/src/Golem/Project/Style.hs#L484-L494)）は、`mark-style` を書かない本でも、書き手の `[character-styles.note-mark]`（とその `based-on` の先）が `size` を持てば、同じエラーにする。
`mark-style` を書かない本は `note-mark` で印を組むので、この場合も大きさを決める値が二つある。
エラーにすること自体は 0177 の理由に合う。

ただし、メッセージは `mark-style` を書いた場合と同じ文言を使い、名前に `note-mark` を入れる（[`Style.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-project/src/Golem/Project/Style.hs#L2001-L2006)）。
仕様書（[`specifications.md`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/docs/specifications.md#L3495)）は、この場合を書いていない。

### 組んで確かめたこと

`golem 0.1.0-rc3`（`bcbe7140` のビルド。`4c808d07` まで golem-project の `Style.hs` に変更はない）で `golem check` を走らせた（2026-11-08）。

| `style.toml` | 出たもの |
| --- | --- |
| `[character-styles.note-mark]` に `size = "0.6zw"`、`[notes]` に `mark-size = "0.65zw"` | `[notes] の mark-size と、size を持つ mark-style note-mark は一緒に書けません (notes.mark-size)` |
| `[character-styles.big]` に `size`、`[character-styles.mine]` に `based-on = "big"`、`[notes]` に `mark-size` と `mark-style = "mine"` | `[notes] の mark-size と、size を持つ mark-style mine は一緒に書けません (notes.mark-size)` |
| `[character-styles.mine]` に `based-on = "note-mark"`、`[notes]` に `mark-size` と `mark-style = "mine"` | エラーなし（組み込みの `note-mark` の `size` は数えない） |

一つめの本の書き手は、`mark-style` を書いていない。
メッセージは書いていないキーの名前を示し、直す場所（`mark-size` を消すこと）を示さない。
この本は、G03117 の「`[character-styles.note-mark]` の `size` に書きます」に従って `size` を書き、`mark-size` を消し忘れたときにできる形である。
二つめのメッセージも、`size` を書いた定義（`big`）を示さない。

## 実装すること

### 規則

0177 の規則を、`mark-style` を書かない場合に広げる（「メンテナーが決めること」の 1）。
本文の印の文字スタイルを、`mark-style` を書けばその名前、書かなければ `note-mark` とする。
`mark-size` と、`size` を持つ定義に `based-on` で行き着く本文の印の文字スタイルを一緒に書くと、G03006 とする。
組み込みの `note-mark` の `size` は、`mark-size` がその代わりなので数えない。
今の実装の振る舞いと同じであり、判定は変えない。

### メッセージ

メッセージを、`size` を書いた定義と、それにたどり着いた道筋を示す形に改める（「メンテナーが決めること」の 2）。

```text
mark-style を書いたとき:
[notes] の mark-size と、mark-style <名前> の size（[character-styles.<定義>] に書いたもの）は一緒に書けません。mark-size を消します
mark-style を書かないとき:
[notes] の mark-size と、注の印の文字スタイル note-mark の size（[character-styles.<定義>] に書いたもの）は一緒に書けません。mark-size を消します
```

- `<定義>` は、`based-on` の鎖を本文の印の文字スタイルからたどって、最初に `size` を書いた定義の名前である。本文の印の文字スタイルそのものが `size` を書いていれば、`<名前>` と同じになる。
- コードは今のとおり G03006 とする。原因（大きさを決める値が二つある）は一つで、二つのメッセージは、その原因に書き手がどの道でたどり着いたかだけが違う。
- 位置は今のとおり `mark-size` の値とする。`mark-size` は廃止予定であり、消すのはこちらである。

### 文書

- docs/specifications.md の「脚注」の節の `mark-size` の段落に、`mark-style` を書かない本の規則を足す。
- docs/diagnostics.md の G03006 のメッセージの一覧の `[notes] の mark-size と、size を持つ mark-style <名前> は一緒に書けません` を、二つの文言に替える。golem-driver の `golem explain` の埋め込みの文書も同じく替える。
- [ADR 0177](0177-note-mark-style-and-numerals.md) のステータスの行に、「`mark-size` と文字スタイルの `size` のエラーの範囲とメッセージは ADR 0214」と足す。

## 実装しないこと

- **`mark-size` の廃止の時期**：0177 のとおり、notice を出す minor のバージョンの後の ADR で決める。
- **`@style-def` で定義した文字スタイル**：ファイルの中の定義と `[notes]` の組み合わせは、この ADR では調べていない。
- **G03006 と G03117 の並び**：確かめた一つめの本では、G03006 だけが出て、`mark-size` の G03117 は出なかった。`[notes]` の表がエラーで捨てられるためと見られるが、原因はまだ調べていない。この ADR では扱わない。

## 不変条件

本文の印の文字スタイルを m（`mark-style` の値、なければ `note-mark`）、m から `based-on` をたどる鎖で最初に `size` を書いた書き手の定義を d とする（組み込みの `note-mark` の `size` は除く）。

- **M1**：`mark-size` を書き、d があるときに限り、G03006 がちょうど一つ出る。位置は `mark-size` の値である。
- **M2**：M1 のメッセージは、`mark-style` を書いたかどうかで二つの文言のどちらかになり、`<定義>` は d の名前である。書き手が書いていないキーの名前（書いていない `mark-style`）を示さない。
- **M3**：`mark-size` を書かない本、d のない本では、この検査の diagnostic は出ない。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| `mark-style` | 書かない、`note-mark`、ほかの名前 |
| `size` を書いた定義 | なし、m そのもの、`based-on` の一つ先、二つ先、組み込みの `note-mark` だけ |
| `mark-size` | 書かない、書く |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
golem-project のテスト（`modules/golem-project/test/Main.hs`）で、境界の入力の組み合わせごとに次を確かめる。

- 「組んで確かめたこと」の一つめの本が、`mark-style を書かないとき` の文言で、`<定義>` が `note-mark` の G03006 になること（M1、M2）。今の実装では文言が違うので失敗する。
- 二つめの本が、`<定義>` が `big` の文言になること（M2）。
- `mark-style = "note-mark"` を書いた本は、`mark-style を書いたとき` の文言になること（M2）。
- 三つめの本と、`mark-size` を書かない本が、何も報告しないこと（M3）。

## トレードオフ

メッセージは長くなる。
ただし、書き手が直すのは `mark-size` を消すことだけであり、それを文言の終わりに書く。
`<定義>` を示すために、`based-on` の鎖をたどって最初の `size` を探す処理が要るが、今の `markSizeConflict` がすでに同じ鎖をたどっている。

## メンテナーが決めること

1. **`mark-style` を書かない本の規則**：推奨は、今の実装のとおり、書き手の `note-mark` が `size` を持てば G03006 とすることである。`mark-style` を書かない本は `note-mark` で印を組むので、大きさを決める値が二つになる。0177 の理由がそのまま当てはまる。
   - 退けた案の一つは、`mark-style` を書いたときだけエラーにし、書かないときは `note-mark` の `size` を勝たせることである。書いた `mark-size` が黙って使われない。0177 は、文字スタイルの `size` が `mark-size` に勝つ案を同じ理由で退けている。
   - 二つめは、書かないときは `mark-size` を勝たせることである。書き手が G03117 に従って書いた `size` が黙って使われない。
2. **メッセージ**：推奨は、`mark-style` を書いたかどうかで文言を分け、`size` を書いた定義を示し、`mark-size` を消すよう求めることである。書いていないキーを示さず、直す場所が文言から決まる。
   - 退けた案の一つは、今の文言のままにすることである。`mark-style` を書いていない書き手に、書いていないキーを示す。
   - 二つめは、`mark-style` を書かない場合に別のコードを足すことである。原因（大きさを決める値が二つある）は同じで、直すことも同じ（`mark-size` を消す）である。G03006 のほかのメッセージも、原因は一つで道筋だけが違うものを一つのコードにしている。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-08、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [ADR 0177](0177-note-mark-style-and-numerals.md)
- [golem-driver ADR 0025](../golem-driver/adr/0025-note-mark-size-and-format.md)
- [golem-project ADR 0006](../golem-project/adr/0006-project-diagnostic-codes.md)（G03006）
