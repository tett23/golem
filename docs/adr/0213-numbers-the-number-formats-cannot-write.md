# ADR 0213: 見出し、図版、コードブロック、ノンブルの番号を書式の表記で表せないときにエラーにする

ステータス: 採択（未実装）

## 文脈

[ADR 0177](0177-note-mark-style-and-numerals.md) は、数の表記を一つの登録表にまとめ、見出し、図版、コードブロック、ノンブルの番号の書式でも `{n:circled}` や `{chapter:upper-roman}` を書けるようにした。
登録表の表記には、表せる範囲がある。
丸数字は 1 から 50 まで、ローマ数字は 1 から 3999 まで、イロハ順は 47 まで、アイウエオ順は 46 まで、`note-symbols` は 7 まで、ラテン文字とローマ数字と丸数字は 0 を表せない。

範囲の外の番号の扱いを、[ADR 0177](0177-note-mark-style-and-numerals.md) は二つの書式についてだけ決めた。
注の印は G07102、リストの印は今のとおり G07029 のエラーとし、どのターゲットも書かない。
見出し、図版、コードブロック、ノンブルの番号の書式については、何も書いていない。

### 今の振る舞い

実装（[`formatNumber`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-numerals/src/Golem/Numerals/Format.hs#L205-L230)）は、表記で表せない番号を算用数字で書く。
`writeNumber` が `Nothing` を返すと、`fromMaybe (T.pack (show k))` で算用数字に替える（[同じファイルの 230 行](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-numerals/src/Golem/Numerals/Format.hs#L230)）。
diagnostic は出さない。
仕様書の「style.toml」の節も、実装に合わせて「表記で表せない番号（`circled` の 51 番など）は、算用数字で書く」と書いている（[`specifications.md`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/docs/specifications.md#L1261)）。
利用者のマニュアルの付録 C も「表記で表せない番号は、算用数字で書きます」と書く（[`c-style.gm`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/manual/appendices/c-style.gm#L37)）。

`formatNumber` を呼ぶのは次の四か所である。

| 番号 | 書式のキー | 呼ぶところ |
| --- | --- | --- |
| 見出し | `[headings.<階層>]` の `number` | [`Assemble.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-assemble/src/Golem/Assemble.hs#L297) |
| 図版 | `[figures]` の `number` | [`Assemble.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-assemble/src/Golem/Assemble.hs#L345-L347) |
| コードブロック（リスト番号） | `[code]` の `number` | [`Assemble.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-assemble/src/Golem/Assemble.hs#L348-L350) |
| ノンブル | `[masters.<名前>]` の `folio` の `format` | [`Draw.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L1235) |

見出しの番号の文字は、本文の見出しのほかに、目次、柱、`[ref-number]` にも写る。
図版とコードブロックの番号の文字は、キャプションに写る。
どれも同じ文字を写すので、見出しの番号が算用数字に替わると、写した先もすべて算用数字になる。

### 組んで確かめたこと

`golem 0.1.0-rc3`（`bcbe7140` のビルド。`4c808d07` まで golem-numerals、golem-assemble、golem-typeset に変更はない）で、次の本を HTML とプレーンテキストに組んだ（2026-11-08）。

```toml
[headings.1]
number = "{n:circled}"
[headings.2]
number = "{1}-{n:note-symbols}"
```

```text
@number 50
# 五十
# 五十一
## 一
…（「## 八」まで八つ）
@number 0
# 零
```

`golem build --target text --target html` は終了コード 0 で終わり、diagnostic は一つも出なかった。
プレーンテキストの見出しは、`㊿　五十`、`51　五十一`、`51-*　一` から `51-#　七`、`51-8　八`、`0　零` になった。
丸数字の本で 51 番めの章だけが `51` になり、記号の本で 8 番めの節だけが `8` になる。
書き手は、組んだものを読むまで、それに気づかない。

### 何が原則に反するか

仕様書の設計原則は、Golem が出力を黙って変えることを許さない。
書き手は `{n:circled}` と書き、算用数字とは書いていない。
算用数字で書くのは、書き手の書式を Golem が書き換えることである。

同じ原因は、リストと注ではすでにエラーである。
三つの書式だけが、同じ範囲の外の番号を黙って許すので、書式によって厳しさが違う。

CSS Counter Styles Level 3 は、範囲の外の番号を `fallback`（既定は `decimal`）の表記で書く。
実装の振る舞いは、これと同じである。
ただし、CSS は書き手が `fallback` を選べ、ブラウザは組んだ結果を誰にも報告しない。
Golem には `fallback` の欄がなく、組んだ結果の誤りは diagnostic で知らせる、という前提が違う。

## 実装すること

### 範囲の外の番号をエラーにする

見出し、図版、コードブロック、ノンブルの番号の書式で、差し込みの番号をその表記で表せないときは、エラーとする（「メンテナーが決めること」の 1）。
コードは書式のキーごとに分ける（「メンテナーが決めること」の 2）。

| コード | 番号 | 段階 | 位置 | 書かないもの |
| --- | --- | --- | --- | --- |
| G04012 | 見出し | 文書の組み立て（golem-assemble） | その見出しのブロック | どのターゲットも |
| G04013 | 図版 | 文書の組み立て（golem-assemble） | その図版のブロック | どのターゲットも |
| G04014 | コードブロック | 文書の組み立て（golem-assemble） | そのコードブロックのブロック | どのターゲットも |
| G07106 | ノンブル | PDF の組版（golem-typeset） | `[masters.<名前>]` の `folio` の `format` の値 | PDF |

- 重大度は、dev でも prod でもエラーとする。
- 見出し、図版、コードブロックの番号の文字は、すべてのターゲットに写るので、ターゲットによらず報告し、どれも書かない。同じ入力から同じ diagnostics を出すためである。
- ノンブルは PDF だけが描くので、PDF をターゲットに含むときだけ報告し、PDF を書かない。
- 一つのブロックの書式に表せない差し込みが二つあるときは、書式の左から最初の差し込みについて一つだけ出す。
- ノンブルは、マスターページごとに一つだけ出す。番号は、そのマスターページを使うページのうち、表せない最初のページのノンブルとする。ページごとに出すと、丸数字のノンブルの 200 ページの本で 150 の diagnostic が並ぶ。

メッセージは次のとおりとする。

```text
G04012: [headings.<階層>] の number <書式> の {<差し込み>} では、<番号> を表せません
G04013: [figures] の number <書式> の {<差し込み>} では、<番号> を表せません
G04014: [code] の number <書式> の {<差し込み>} では、<番号> を表せません
G07106: [masters.<名前>] の folio の format <書式> の {<差し込み>} では、ノンブル <番号> を表せません
```

`<書式>` は `style.toml` に書いた形、`<差し込み>` は `n:circled` のように差し込みの中身である。

### `formatNumber` の型

`formatNumber` を、表せない差し込みを返す形に改める。

```haskell
formatNumber :: Text -> [Integer] -> Maybe Integer -> Either Unwritable Text

data Unwritable = Unwritable
  { uwSlot :: Text, -- the slot as written, n:circled
    uwNumber :: Integer
  }
```

- 表せない差し込みがなければ `Right`、あれば最初の差し込みの `Left` を返す。算用数字で書く枝を消す。
- 書式が読めないとき（`Left _ -> fmt`）は、今のとおり書式の文字を返す。`style.toml` を読むときに G03006 で止まるので、組み立てには届かない。
- golem-assemble は、`Left` を受けたブロックに G04012 から G04014 を出し、番号の文字を持たないものとして組み立てを続ける。組み立ての後の段階には進まない（エラーがあるため）。
- golem-typeset は、ページを決めた後、マスターページごとに G07106 を調べ、ノンブルを描く前に報告する。

### 文書

- docs/specifications.md の「style.toml」の節の「表記で表せない番号（`circled` の 51 番など）は、算用数字で書く」を、四つのコードでエラーにする文に改める。この ADR へのリンクを付ける。
- docs/diagnostics.md に G04012、G04013、G04014、G07106 の節を足す。golem-driver の `golem explain` の埋め込みの文書も同じく足す。
- 利用者のマニュアルの付録 C（`manual/appendices/c-style.gm`）の「表記で表せない番号は、算用数字で書きます」を、エラーになる文に改める。付録 E（`manual/appendices/e-errors.gm`）の G07029 と G07102 の項目の近くに、四つのコードの項目を足す（[docs/manual-policy.md](../manual-policy.md) に従い、同じプルリクエストで直す）。
- [ADR 0177](0177-note-mark-style-and-numerals.md) のステータスの行に、「見出し、図版、コードブロック、ノンブルの表せない番号は ADR 0213」と足す。

## 実装しないこと

- **`fallback` の欄**：表記ごとに、範囲の外で使う表記を書き手が選ぶ欄（CSS の `fallback`）は足さない。足すかどうかは、使う本が出てから決める。
- **リストと注の番号**：G07029 と G07102 は今のとおりとする。
- **golem-layout と golem-html の注の印の算用数字の枝**：[`Japanese.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-layout/src/Golem/Layout/Japanese.hs#L535) と [`Html.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-html/src/Golem/Html.hs#L727) にも `fromMaybe` で算用数字に替える枝があるが、G07102 がすべてのターゲットで先に止める（[`Driver.hs`](https://github.com/tett23/golem/blob/4c808d072df6918bf20ab57fd97eb7e75005f38c/modules/golem-driver/src/Golem/Driver.hs#L822)）ので、組んだものには現れない。この ADR では変えない。
- **`[ref-number]` の図番号とリスト番号の書式**：仕様書の「既知の不具合」にある、`[ref-number]` が `[figures]` と `[code]` の書式に従わない件は、別に扱う。
- **隠しノンブル**：書式を使わず算用数字で描くので、範囲の外がない。

## 不変条件

書式 f の差し込みの並びを s₁, …, sₖ、差し込み sᵢ の表記を tᵢ（書いていなければ `arabic`）、その番号を vᵢ（値がない差し込みは除く）とする。
表記 t が番号 v を表せることを W(t, v) と書く。

- **N1**：見出し、図版、コードブロックのどれかで ¬W(tᵢ, vᵢ) となる i があれば、そのブロックの位置に、そのキーのコード（G04012、G04013、G04014）がちょうど一つ出る。どのターゲットも書かない。
- **N2**：すべての i で W(tᵢ, vᵢ) なら、四つのコードはどれも出ず、番号の文字はこの ADR の前と同じである。
- **N3**：N1 の diagnostic のメッセージの差し込みと番号は、¬W となる最小の i のものである。
- **N4**：PDF をターゲットに含む本で、あるマスターページを使うページのノンブル n が ¬W なら、そのマスターページについて G07106 がちょうど一つ出て、PDF を書かない。番号はそのようなページのうち最初のもののノンブルである。PDF をターゲットに含まない本では、G07106 は出ない。
- **N5**：同じ入力からは、ターゲットの組み合わせによらず（N4 の PDF の有無を除き）同じ diagnostics を同じ順に出す。
- **N6**：どの書式も、表記で表せない番号を算用数字やほかの表記で書かない。

境界の入力：

| 量 | 調べる値 |
| --- | --- |
| `circled` の番号 | 0、1、50、51 |
| `iroha` の番号 | 47、48 |
| `aiueo` の番号 | 46、47 |
| `note-symbols` の番号 | 7、8 |
| `upper-roman`、`lower-roman` の番号 | 0、1、3999、4000 |
| `lower-alpha` の番号 | 0、1、26、27（`aa`） |
| `arabic`、`kanji`、`kanji-digits` の番号 | 0（どれも表せる） |
| 差し込みの種類 | `{n}`、上の階層の `{1}`、`{chapter}` |
| 上の階層の番号 | 番号を持つ、飛ばした階層（値 0） |
| 表せない差し込みの数 | 0、1、一つの書式に 2 |
| `@number` | なし、0、51 |
| 番号を持たない見出しと図版 | `@nonumber`（番号がないので報告しない） |
| ノンブル | 50 ページと 51 ページの本（`{n:circled}`）、二つのマスターページの片方だけが表せない |
| ターゲット | PDF だけ、HTML とプレーンテキストだけ、すべて |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。

golem-numerals のテスト（`modules/golem-numerals/test/Main.hs`）には、次のものを足す。

- `formatNumber` が、境界の入力の表の各表記の端で `Right` を、端の外で `Left` を返すこと。`Left` の差し込みと番号が、最初の表せない差し込みのものであること（N3、N6）。

golem-assemble のテスト：

- `{n:circled}` の見出しの 51 番め、`@number 0` の見出し、`{1:upper-roman}` の階層 2 の見出しで階層 1 を飛ばしたもの、`{n:note-symbols}` の図版の 8 番め、`{chapter:iroha}` のコードブロックの 48 章めが、それぞれ G04012、G04013、G04014 になり、位置がそのブロックであること（N1）。
- 50 番めの丸数字の見出しと `@nonumber` の見出しが、何も報告しないこと（N2）。

golem-driver のテスト：

- 上の本を、PDF だけ、HTML とプレーンテキストだけ、すべてのターゲットで組み、同じ diagnostics が同じ順に出て、どのターゲットも書かないこと（N1、N5）。
- `{n:circled}` のノンブルの 51 ページの本が G07106 を一つだけ出し、PDF を書かないこと。50 ページの本は何も出さないこと。PDF をターゲットに含まない同じ本は G07106 を出さないこと（N4）。

今のゴールデンとハッシュは変わらない見込みである。
今の fixture に範囲の外の番号はない（`scripts/visual` の PDF も含め、変わらないことを CI で確かめる）。

## トレードオフ

今まで算用数字で組めていた本が、組めなくなる。
丸数字のノンブルや記号の節番号のように、範囲が小さい表記を選んだ本では、原稿を足しただけでエラーになる。
ただし、組めていた本は、書き手の書式と違う番号を含んでいた。
リストと注は最初からエラーにしており、同じ範囲の外の番号を書式によって許したり許さなかったりする理由はない。

コードを四つ足す。
一つのコードにまとめれば数は減るが、直すキーが四つに分かれる。
[ADR 0177](0177-note-mark-style-and-numerals.md) は、同じ理由で G07029 と G07102 を分けた。

## メンテナーが決めること

1. **範囲の外の番号の扱い**：推奨は、エラーとし、そのターゲットを書かないことである。書き手の書式と違う番号を、黙って組まない。リストの G07029 と注の G07102 とも揃う。
   - 退けた案の一つは、今のとおり算用数字で書き、仕様書に書いておくことである。出力を黙って変えることになり、書き手は組んだものを読むまで気づかない。
   - 二つめは、算用数字で書いたうえで警告を出すことである。警告を読まない CI では、書式と違う番号のまま入稿される。範囲の外の番号は、書き手が書式か原稿を直すまで正しくならない。
   - 三つめは、CSS の `fallback` に倣い、範囲の外で使う表記を選ぶ欄を足すことである。表記ごとに欄を一つ増やし、範囲の外を書き手に選ばせる。選ぶ本が出てから決めても遅くない。
2. **コードの分け方**：推奨は、書式のキーごとに四つ（G04012、G04013、G04014、G07106）に分けることである。[ADR 0177](0177-note-mark-style-and-numerals.md) は、直すキーが違うことを理由に G07029 と G07102 を分けた。
   - 退けた案の一つは、四つを一つのコードにまとめることである。G04004 は図版とコードブロックを一つのコードにしているが、0177 より前の決定であり、どのキーを直すかをコードから引けない。
   - 二つめは、G07029 か G07102 を使い回すことである。直すキーが違い、一つのコードに二つの原因を持たせる。
3. **見出し、図版、コードブロックを報告する段階**：推奨は、番号の文字を作る文書の組み立て（golem-assemble、G04 の範囲）である。番号の文字を作る関数がそこにあり、`golem check` でも報告できる。
   - 退けた案は、G07029 と G07102 と同じく出力の段階（G07 の範囲）で報告することである。リストと注の印は出力の段階で文字にするので、そこで報告している。見出しの番号は組み立てで文字になり、目次や柱に写るので、組み立てで止めるほうが後の段階に誤った文字を渡さない。
4. **ノンブルの報告の数**：推奨は、マスターページごとに一つとし、表せない最初のページのノンブルを示すことである。原因は書式一つなので、ページの数だけ出しても、直すことは一つである。
   - 退けた案は、ページごとに一つ出すことである。丸数字のノンブルの長い本で、同じ diagnostic が百以上並ぶ。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-08、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- [ADR 0177](0177-note-mark-style-and-numerals.md)、[ADR 0188](0188-headings-beyond-level-3.md)、[ADR 0200](0200-figures-and-listings-without-numbers.md)
- [golem-driver ADR 0013](../golem-driver/adr/0013-list-indents.md)（G07029）、[golem-driver ADR 0014](../golem-driver/adr/0014-running-heads.md)、[golem-driver ADR 0023](../golem-driver/adr/0023-code-block-book-features.md)
- [golem-doc ADR 0003](../golem-doc/adr/0003-document-diagnostic-codes.md)（G04 の範囲）
- W3C, CSS Counter Styles Level 3, `fallback` と `range` の記述 <https://www.w3.org/TR/css-counter-styles-3/>
