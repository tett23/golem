# ADR 0433: HTML と EPUB に写したフォントに、そのライセンスの文書を添える

Status: proposed

## 文脈

`fonts = "embed"` を書いた HTML と EPUB の出力は、`style.toml` が指すフォントのファイルを `fonts/` に写す（[root ADR 0423](0423-generic-font-families-for-html-and-epub.md)）。
写すのはフォントのファイルだけで、そのライセンスの文書は写さない。

[root ADR 0082](0082-manuals-under-cc0.md) は、マニュアルの HTML について、`@font-face` で読ませるために丸ごと渡すフォントのファイルは文書への埋め込みではなく配布であり、OFL の FAQ が強く勧める全文を添えるべきだと読んだ。
そして、マニュアルを組むスクリプトが組んだ後にライセンスの文書を写すことで、マニュアルの分だけを直した。
Golem 本体の扱いは、HTML の書き方を変える予定とあわせて決めるとした。

同じことは、Golem で `fonts = "embed"` を使うすべての本に起きる。
この ADR は、HTML の書き方を決める [root ADR 0432](0432-write-the-html-target-in-the-html-syntax.md) とあわせて、本体の扱いを決める。
OFL の条文の解釈の細部に頼らず、Golem の方針として「写したフォントには、必ずそのライセンスの文書を添える」と決める。
解釈が割れうるとき（EPUB の中のフォントを埋め込みとみなせるか、など）も、添える側に倒しておけば条件を欠かないためである。

## 調査した事項

origin/main（[9efdc4f89](https://github.com/tett23/golem/commit/9efdc4f89b3fec75abcd37c11abb3e1d909c6725)）で、次のことを確かめた。

- `[fonts.<role>]` は、フォントのパスの `ja` と `latin` を持つ。
  `fonts = "embed"` のとき、各役割の `ja` と `latin` のファイルを写すアセットに加え（[Html.hs#L399-L400](https://github.com/tett23/golem/blob/9efdc4f89b3fec75abcd37c11abb3e1d909c6725/modules/golem-html/src/Golem/Html.hs#L399-L400)）、出力の名前は `fonts/<ファイル名>` で（[Html.hs#L413-L414](https://github.com/tett23/golem/blob/9efdc4f89b3fec75abcd37c11abb3e1d909c6725/modules/golem-html/src/Golem/Html.hs#L413-L414)）、`@font-face` でそれを指す（[Html.hs#L1375-L1378](https://github.com/tett23/golem/blob/9efdc4f89b3fec75abcd37c11abb3e1d909c6725/modules/golem-html/src/Golem/Html.hs#L1375-L1378)）。
  アセットは出力の名前をキーにした表なので、別のフォルダにある同じ名前のフォントは、同じ出力の名前になり、片方だけが残る。
  EPUB は、それを `OEBPS/` の下に入れ、OPF の manifest に挙げる。
  OPF の型は golem-epub の `mediaType` が拡張子で決め、知らない拡張子（`.txt`、`.md` を含む）は `application/octet-stream` にする（[Epub.hs#L59-L70](https://github.com/tett23/golem/blob/9efdc4f89b3fec75abcd37c11abb3e1d909c6725/modules/golem-epub/src/Golem/Epub.hs#L59-L70)）。
- `fonts` は、`[targets.html]` と `[targets.epub]` で別々に決まり、フォントの検査もターゲットごとに行う（[Driver.hs#L1192-L1193](https://github.com/tett23/golem/blob/9efdc4f89b3fec75abcd37c11abb3e1d909c6725/modules/golem-driver/src/Golem/Driver.hs#L1192-L1193)）。
- `fonts = "embed"` でフォントのファイルが無いと G03010 で、重大度は dev では警告、prod ではエラーである。
  dev ではそのフォントを同梱せずに出力し、prod では HTML と EPUB を書かない。
  LSP は出さない。
- `style.toml` のフォントと出力インテントのパスがプロジェクトの外を指すと、どの出力でも G03279 のエラーになる（[root ADR 0421](0421-epub-determinism-per-version-and-fonts-outside-the-project.md)）。
- マニュアルのスクリプト（`scripts/manual/build.sh`）は、組んだ後に、プロジェクトの `LICENSE`（CC0 1.0）を `build/html/LICENSE` に写し、`build/html/fonts/` があれば `fonts/LICENSE-*` をそこへ写す。
- マニュアルのフォントの `name` の表には、ライセンスの一行の文と URL しかなく、OFL の全文は入っていない（0082）。
- リポジトリのフォントのライセンスの文書の名前は、`LICENSE-NotoSerifJP.txt`、`LICENSE-SourceSerif4.md`、`OFL.txt` などで、フォントのファイルの名前と一致しない。
  名前で探しても、どのライセンスがどのフォントのものかは決められない。
- `golem new` は、フォントとそのライセンスの文書を組で取ってくる（`fonts/NotoSerifJP-Regular.otf` と `fonts/LICENSE-NotoSerifJP.txt` など）。

確かめていないことは次のとおりである。

- OPF の manifest に `text/plain` と `text/markdown` の項目を挙げ、どこからも参照しない EPUB が、epubcheck 5.4.0 を警告なしで通るか。
  EPUB 3.3 は、コアの媒体の型でない資源（外来の資源）を manifest に挙げることを許すが、epubcheck の出力は確かめていない。
  採択の前に、手元で epubcheck にかけて確かめる。

指示者は 2026-11-23 に、この ADR を書くよう求めた。

## 実装すること

### ライセンスの文書の指定

`[fonts.<role>]` に、`ja` と `latin` のそれぞれに対応する `ja-license` と `latin-license` のキーを足す。
値は、そのフォントのライセンスの文書のパスで、`ja` と `latin` と同じく、プロジェクトのルートからの相対パスとする。
プロジェクトの外を指すパスは、0421 と同じく G03279 にし、G03279 の説明の「フォントと出力インテントのパス」に、ライセンスの文書のパスを足す。
名前で探す方法は採らない。
ライセンスの文書の名前は、フォントの名前と一致しないためである。

### 写す場合

ライセンスの文書を写すのは、`fonts = "embed"` の HTML と EPUB で、そのフォントを写すときだけとする。
`fonts = "generic"` の出力はフォントを写さないので、ライセンスの文書も写さない。
PDF は、フォントを文書に埋め込むので、ライセンスの文書を写さない。
G03010 などでフォントを写さないときは、そのライセンスの文書も写さない。

### 置き場所と型

HTML のターゲットでは、ライセンスの文書を `fonts/` に、元のファイルの名前のまま写す。
EPUB では、ライセンスの文書を、コンテナの `OEBPS/fonts/` の下に、元のファイルの名前のまま入れ、OPF の manifest に挙げる。
manifest の型は、拡張子が `.md` なら `text/markdown`、それ以外は `text/plain` とする。
ライセンスの文書の型は、`mediaType` の拡張子の表ではなく、この規則で決める。

### 出力の名前のぶつかり

フォントとライセンスの文書は、どちらも `fonts/<ファイル名>` に写すので、二つのファイルが同じ出力の名前になりうる。
同じ出力の名前になる二つのファイルの中身が同じなら、一つだけ写す。
中身が違うなら、エラーにする。
今、黙って片方だけを残しているフォントどうしのぶつかりも、このエラーにする。
ぶつかった片方を黙って落とすと、別のフォントで組んだ出力ができるためである。

### 止めるターゲット

`fonts` はターゲットごとに決まるので、検査とエラーもターゲットごとに行う。
下の diagnostic でターゲットを書かないのは、`fonts = "embed"` で、その原因を持つターゲットだけである。
たとえば、HTML だけが `embed` で EPUB が `generic` の本では、HTML のライセンスの欠けは HTML だけを止め、EPUB は書く。

### diagnostic

次の三つの原因に、それぞれ新しいコードを一つずつ足す。
コードの番号は、実装のときに空き番号から決める。

| 原因 | 重大度と出力 | LSP |
| --- | --- | --- |
| 写すフォントに、対応する `*-license` のキーが無い | dev では警告で、ライセンスの文書なしで出力する。prod ではエラーで、そのターゲットを書かない | `style.toml` に出す |
| `*-license` のファイルが無い | 同上 | 出さない |
| 出力の名前が同じで中身が違う二つのファイルがある | エラーで、dev でも prod でもそのターゲットを書かない | 出さない |

一つめと二つめの重大度は、フォントのファイルが無いときの G03010 に合わせる。
dev の出力は手元で見るためのもので配らないが、prod の出力は配るので、条件を欠いた出力を作らない。
三つめは、どちらの出力も組み方が変わりうるので、dev でも止める。
ファイルの有無を見る二つめと三つめは、G03010 と同じく LSP では出さない。

### マニュアルと雛形

`scripts/manual/build.sh` の、`fonts/LICENSE-*` を `build/html/fonts/` に写す手順だけを消し、マニュアルの `style.toml` に `*-license` を書く。
プロジェクトの `LICENSE`（CC0 1.0）を `build/html/LICENSE` に写す手順は残す。
`golem new` の雛形の `style.toml` に、取ってくるライセンスの文書の `*-license` を書く。

### 文書

仕様書の HTML と EPUB のフォントの節に、`*-license` のキー、写す場合、置き場所と型、出力の名前のぶつかり、diagnostic を書く。
`docs/diagnostics.md` に三つのコードを足し、G03279 の説明を直す。
マニュアルのスタイルの章と、付録の `style.toml` の表と diagnostic の付録を直す。
ロードマップの「HTML と EPUB へのフォントのライセンスの文書の同梱」の項目を消す。

### ステータスの行

採択したら、[root ADR 0082](0082-manuals-under-cc0.md) のステータスに、「組んだ HTML に入れるライセンスの文書」の `fonts/LICENSE-*` を写す手順をこの ADR が置き換え、「実装しないこと」の、本体の扱いを後で決めるという部分をこの ADR が補ったことを記録する。

```text
superseded [{"part":"組んだ HTML に入れるライセンスの文書の、fonts/LICENSE-* を写す手順","by":["docs/adr/0433-bundle-font-licenses-with-embedded-fonts.md"],"kind":"replace"},{"part":"実装しないこと","by":["docs/adr/0433-bundle-font-licenses-with-embedded-fonts.md"],"kind":"supplement"}]
```

## 実装しないこと

フォントのファイルの中のメタデータ（`name` の表）から、ライセンスを読み取らない。
ライセンスの種類（OFL かどうか）を判定しない。
EPUB のフォントの難読化（obfuscation）を足さない。
フォントの同梱をやめる（`fonts = "generic"` を強いる）ことはしない。
出力の名前のぶつかりを、名前を付け替えて避けることはしない。

## 不変条件

- I1: `fonts = "embed"` の HTML のターゲットの出力は、写したフォントごとに、その `*-license` のファイルを `fonts/` に持つ。
- I2: `fonts = "embed"` の EPUB は、写したフォントごとに、その `*-license` のファイルを `OEBPS/fonts/` に持ち、拡張子で決めた型で OPF の manifest に挙げる。
- I3: prod で、`embed` のターゲットの写すフォントに `*-license` のキーが無いか、そのファイルが無いとき、そのターゲットは書かれず、原因ごとのコードのエラーが出て、ほかのターゲットは書かれる。
- I4: dev で、写すフォントに `*-license` のキーが無いか、そのファイルが無いとき、原因ごとのコードの警告が出て、そのターゲットはライセンスの文書なしで書かれる。
- I5: `fonts = "generic"` の出力と PDF は、ライセンスの文書を持たない。
- I6: 同じ出力の名前で中身が同じ二つのファイルは、出力に一つだけある。
- I7: `embed` のターゲットに、同じ出力の名前で中身が違う二つのファイル（フォントどうし、ライセンスどうし、フォントとライセンス）があるとき、dev でも prod でもそのターゲットは書かれず、ぶつかりのコードのエラーが出る。
- I8: `*-license` のパスがプロジェクトの外を指すとき、0421 と同じく G03279 になる。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| `embed`、本文の `ja` と `ja-license` を書いた本の HTML | `fonts/` にフォントとライセンス | I1 |
| `embed`、`ja` と `latin` と両方の `*-license` を書いた本の EPUB | `OEBPS/fonts/` に二つのライセンスがあり、OPF に挙がる | I2 |
| `embed`、ライセンスの文書が `OFL.md` | OPF の型が `text/markdown` | I2 |
| `embed`、ライセンスの文書が `OFL.txt` と拡張子の無い `LICENSE` | OPF の型が `text/plain` | I2 |
| prod、`embed`、`ja-license` を書かない | HTML と EPUB が無く、キーの欠けのエラー | I3 |
| prod、`embed`、`ja-license` のファイルが無い | HTML と EPUB が無く、ファイルの欠けのエラー | I3 |
| dev、`embed`、`ja-license` を書かない | 警告で、HTML と EPUB はライセンスなしで書かれる | I4 |
| `embed`、`ja-license` がプロジェクトの外 | G03279 | I8 |
| prod、HTML だけ `embed`、EPUB は `generic`、`ja-license` を書かない | HTML が無く、EPUB はある | I3 |
| `embed`、フォントのファイルが無い（G03010） | そのライセンスも写さない | I1 |
| `generic` で `*-license` を書いた本 | ライセンスの文書が無い | I5 |
| PDF | ライセンスの文書が無い | I5 |
| 二つの役割が同じ `LICENSE-NotoSerifJP.txt` を指す | 一つだけ写す | I6 |
| 二つのフォルダの同じ中身の `OFL.txt` | 一つだけ写す | I6 |
| 二つのフォルダの中身の違う `OFL.txt` | HTML と EPUB が無く、ぶつかりのエラー | I7 |
| 二つのフォルダの中身の違う同じ名前のフォント | HTML と EPUB が無く、ぶつかりのエラー | I7 |

## 受けいれ条件

A1: マニュアルを `scripts/manual/build.sh` の `fonts/LICENSE-*` を写す手順なしで組み、HTML の出力の `fonts/` に、マニュアルが使うフォントのライセンスの文書がそろっていることを確かめる。

A2: ライセンスの文書を含む EPUB が epubcheck 5.4.0 を通ることを、CI の epubcheck のジョブで確かめる。

## テスト設計

root ADR 0433 I1 から I8 を名前の先頭に置いたテストを、golem-project、golem-html、golem-epub、golem-driver に足す。
境界の表の各行を、小さなプロジェクトで組んで確かめる。
各テストは、実装の前に落ちることを確かめる。
root ADR 0433 A1 は、マニュアルの CI の組み立てで確かめる。
root ADR 0433 A2 は、CI の epubcheck のジョブに、ライセンスの文書を含む EPUB を足して確かめる。

## トレードオフ

prod では、`*-license` を書かないと `fonts = "embed"` の出力が作れなくなるので、今 `embed` を使っている本は、`style.toml` を直す必要がある。
その代わりに、ライセンスの文書を添えない出力を、気付かずに配ることがない。

EPUB のライセンスの文書を OPF に挙げるので、読書のアプリがその文書を出版物の一部として扱うことがある。
OPF に挙げずに置く方法は、epubcheck が通るかを確かめていないので採らない。

同じ名前で中身の違うフォントのぶつかりをエラーにするので、今は黙って組めていた本が組めなくなることがある。
その本は、今も片方のフォントを落とした出力を作っている。

## 参考文献

- [root ADR 0082](0082-manuals-under-cc0.md)
- [root ADR 0421](0421-epub-determinism-per-version-and-fonts-outside-the-project.md)
- [root ADR 0423](0423-generic-font-families-for-html-and-epub.md)
- [root ADR 0432](0432-write-the-html-target-in-the-html-syntax.md)
- [SIL Open Font License 1.1](https://openfontlicense.org/open-font-license-official-text/)
- [OFL FAQ](https://openfontlicense.org/ofl-faq/)
- W3C, EPUB 3.3
