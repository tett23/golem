# ADR 0145: 目次と `[ref-title]` に写す題から、索引の印とチャネルの項目を除く

ステータス: 採択

## 文脈

見出しの題のインラインは、本の二か所に写される。

- 目次（`@toc`）の項目。文書構造（S1）の `TocEntry` の題である（[Assemble.hs の 370 行め](https://github.com/tett23/golem/blob/97be81e8de344a22a15079b2e56bf0e5ce20ea62/modules/golem-doc/src/Golem/Doc/Assemble.hs#L370)）。
- `[ref-title ラベル]` の参照。S1 がラベルの題（`ltTitle`）を参照の位置に写す（[同 617 行めから 621 行め](https://github.com/tett23/golem/blob/97be81e8de344a22a15079b2e56bf0e5ce20ea62/modules/golem-doc/src/Golem/Doc/Assemble.hs#L617-L621)）。キャプションのあるコードブロックのキャプションも、同じく写される。

写すとき、`relocate` はテキストと数の位置だけを参照の位置に移し、ほかのインラインはそのまま残す（[同 680 行めから 684 行め](https://github.com/tett23/golem/blob/97be81e8de344a22a15079b2e56bf0e5ce20ea62/modules/golem-doc/src/Golem/Doc/Assemble.hs#L680-L684)）。
題の中の索引の印（`IndexMark`）とチャネルの項目（`ChannelItem`）も、見出しと同じ位置のまま写る。

この二つは、本文の位置を一覧（索引、プラグインのチャネル）に知らせる印である。
PDF は、印の位置ごとに置かれたページを記録する（[Paginate.hs の 415 行めから 416 行め](https://github.com/tett23/golem/blob/97be81e8de344a22a15079b2e56bf0e5ce20ea62/modules/golem-layout/src/Golem/Layout/Paginate.hs#L415-L416)）。
位置をキーにした表で、後のページが前のページを上書きする。
写しが見出しより後のページにあれば、一覧のページは写しのページになる。
HTML は、印ごとに `id` を書き、一覧からその `id` へリンクする。

これまでの対策は、写す先ごとに最上位の印だけを除くものだった。

- PDF の目次は `IndexMark` だけを除く（[Flow.hs の 1301 行め](https://github.com/tett23/golem/blob/97be81e8de344a22a15079b2e56bf0e5ce20ea62/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L1301)、[同 1345 行めから 1347 行め](https://github.com/tett23/golem/blob/97be81e8de344a22a15079b2e56bf0e5ce20ea62/modules/golem-driver/src/Golem/Driver/Pdf/Flow.hs#L1345-L1347)）。
- HTML の目次は、[docs/adr/0126](0126-glossary-plugin.md) で `IndexMark` と `ChannelItem` を除くようにした（[Html.hs の 516 行めから 527 行め](https://github.com/tett23/golem/blob/97be81e8de344a22a15079b2e56bf0e5ce20ea62/modules/golem-html/src/Golem/Html.hs#L516-L527)）。[docs/adr/0126](0126-glossary-plugin.md) は、これを「PDF の目次と同じ扱い」と書いた。
- `[ref-title]` は、どの出力でも除かない。
- どの対策も、文字スタイルなどの中に入れ子になった印を除かない。

### 確かめたこと

2026-11-04 の監査（[docs/audits/2026-11-04-rc4-plugin-adr-conformance.md](../audits/2026-11-04-rc4-plugin-adr-conformance.md) の F-31）は、PDF の目次がチャネルの項目を残すことをコードの読みから指摘し、実機では確かめていなかった。
この ADR を書くために、`golem new` で作った横組みのプロジェクトに見本の `glossary` を `path` で置いて組み、PDF のテキストを取り出して確かめた（`golem` は 5db37cb9 から組んだもので、`modules/` は [97be81e8](https://github.com/tett23/golem/tree/97be81e8de344a22a15079b2e56bf0e5ce20ea62) と同じ）。
各行の数字は、一覧に出たページ番号である。

| 原稿 | 写し | 一覧の PDF のページ | 一覧の HTML のリンク |
| --- | --- | --- | --- |
| 1 ページに `# [term: 組版]の章`、2 ページに `@toc` | PDF の目次 | 用語集 `2`（誤り） | （確かめていない） |
| 1 ページに `@toc`、2 ページに同じ見出し | PDF の目次 | 用語集 `2`（正しい） | （確かめていない） |
| 1 ページに `# [term: 組版]と[index reading=くみ: 組]の章`、2 ページに `[ref-title]` | `[ref-title]` | 用語集 `2`、索引 `2`（誤り） | 用語集 `1, 2`（2 は写しへのリンク） |
| 1 ページに `# [strong: [index reading=くみ: 組]と]の章`、2 ページに `@toc` | PDF と HTML の目次 | 索引 `2`（誤り） | 目次の側にも `id="i-1-11"` |

誤りの行では、一覧は見出しのページ（1）を示すべきである。
[golem-doc ADR 0007](../golem-doc/adr/0007-plugin-channel-lists.md) は、チャネルの項目のページを「索引の印と同じ規則」で決めると定めており、索引の印は、本文に書いた位置のページを示すものである。
写しのページを示すのは、この規則に反するバグである。
索引の印の `[ref-title]` と入れ子の場合は、プラグインより前からあった。

PDF の一覧のページは一つだけになる（混じるのではなく、置き換わる）。
HTML の一覧は、写しへのリンクを足す。
出力の媒体で一覧の結果が違うので、どちらも直す。

## 実装すること

### 規則

本文のほかの場所に写す題からは、索引の印とチャネルの項目を除く。
入れ子の中（文字スタイル、色、圏点、ルビの親文字など）にあるものも除く。
印は、書いた場所の一か所にだけあるものとする。

除く場所は S1 の一か所とする。

- 見出しの情報の題（`hiTitle`）を作るとき、印を除いたインラインにする。目次の項目（`TocEntry`）と、見出しのラベルの題（`ltTitle`）は、これを使う。
- コードブロックのキャプションをラベルの題にするときも、同じく除く。
- 本文の見出しとキャプションそのものは変えない。印は、そこにだけ残る。

除く関数は golem-doc に一つ置き、印の種類（今は `IndexMark` と `ChannelItem`）をそこで決める。
印の種類を足すときに、写す先ごとの直しを要らなくするためである。
PDF の目次と HTML の目次の今のフィルタは、S1 が除いた後は何もしないので、取り除く。

### 出力

- PDF：見出しの題を写した目次と `[ref-title]` の後のページにあっても、索引と一覧のページは見出しのページになる。
- HTML と EPUB：目次と `[ref-title]` の写しに、印の `id` を書かない。一覧のリンクは見出しの一つだけになる。
- プレーンテキスト：印は何も書かないので、変わらない。

新しいコードは作らない。
diagnostic は変わらない。

### 文書

- docs/specifications.md の「目次と文書構造の参照」の節（今の 717 行め）を、HTML の目次だけでなく、PDF の目次と `[ref-title]` の写しから、入れ子の印も含めて除くと書き改め、この ADR へのリンクを足す。
- docs/markup.md の「索引」と「相互参照」の節に、見出しの中の索引の印は見出しの位置だけを数え、目次と `[ref-title]` の写しを数えないことを書く。
- [docs/adr/0126](0126-glossary-plugin.md) のステータスの行に、「目次の写しから印を除く範囲（PDF、`[ref-title]`、入れ子）は [ADR 0145](0145-title-copies-drop-anchor-inlines.md)」を足す。
- [golem-doc ADR 0007](../golem-doc/adr/0007-plugin-channel-lists.md) は変えない。この ADR は、その規則に実装を合わせる。

## 実装しないこと

- 写しの脚注と傍注。見出しに脚注を書いて目次や `[ref-title]` に写したときの扱いは、この ADR を書く時点で確かめていない。印と同じ問題があるかを調べ、あれば別に決める。
- 柱（ランニングヘッド）と PDF のしおり、HTML の `<title>`、EPUB のナビゲーション文書。どれも題の文字列だけを使い、印を組まないので、変わらない。
- 写しの印を、写しの位置の出現として一覧に数えること。目次や参照の中の語は、本文に書いた語の出現ではない。

## テスト設計

先に次のテストを書き、今の main で失敗することを確かめてから実装する。

golem-doc のテストで、次のことを確かめる。

- 見出し `[strong: [index ...]]` と `[term ...]` に当たる `ChannelItem` を持つ文書で、`TocEntry` の題と、見出しのラベルの題に、`IndexMark` と `ChannelItem` がどの深さにもない。今の main では残って失敗する。
- キャプションに索引の印を持つコードブロックのラベルの題にも、印がない。
- 本文の見出しのインラインは、印を含んだまま変わらない。

golem-driver の `ReferencesSpec` で、PDF について次のことを確かめる。

- 1 ページの見出しに索引の印とチャネルの項目を書き、2 ページに `@toc` を置いた本で、索引の印とチャネルの項目のページが 1 である。今の main では 2 で失敗する。
- 同じ見出しを 2 ページの `[ref-title]` で参照した本でも 1 である。今の main では 2 で失敗する。
- 入れ子の索引の印でも 1 である。

golem-driver の `PluginsSpec`（見本の `glossary`）と golem-html のテストで、次のことを確かめる。

- 見出しの `[term]` を `[ref-title]` で参照した本の HTML の用語集が、見出しへのリンクを一つだけ持つ。今の main では二つで失敗する。
- 入れ子の索引の印を持つ見出しの HTML の目次に、印の `id` がない。今の main では `id` があって失敗する。

決定性の検査、ゴールデン、見た目の回帰テストの参照が変わらないことを確かめる。
リポジトリの原稿とマニュアルに、索引の印かチャネルの項目を持つ見出しはない（`rg '^#+ .*\[(index|term)' -g '*.gm'` で確かめた。当たる一行はコードの中の字である）。

## トレードオフ

S1 で除くので、出力の段階で写しの印を使いたくなっても使えない。
写しの印には、上の誤りのほかの用途がない。
写す先ごとに除く今の作りは、写す先が増えるたびに直しが要り、実際に `[ref-title]` と入れ子を漏らした。
一か所で除くほうが、漏れが起きにくい。

S1 が印を除くことは、プラグインには見えない。
プラグインが受け取る文書は評価の後の S0 であり、S1 の題を受け取らないからである。

## 決めたことの記録

- **採択**：メンテナーが、この ADR の案のとおり採択した（2026-11-04）。

## 参考文献

- [docs/audits/2026-11-04-rc4-plugin-adr-conformance.md](../audits/2026-11-04-rc4-plugin-adr-conformance.md)（F-31）
