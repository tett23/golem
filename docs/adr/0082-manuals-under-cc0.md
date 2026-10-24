# ADR 0082: 二つのマニュアルの原稿と、組んだ PDF と HTML を CC0 1.0 にする

ステータス: 採択

## 文脈

Golem のリポジトリは、根の [LICENSE](https://github.com/tett23/golem/blob/d974a9fd4226e623775c7f929e45db5b6db03903/LICENSE) の MIT License で配布している。
著作権の行は「Copyright (c) 2026 tett23」である。
二つのマニュアル（使い手のマニュアルの `manual/` と、開発者のマニュアルの `manual-dev/`）も、今はこの MIT の下にある。
[CONTRIBUTING.md の「ライセンス」](https://github.com/tett23/golem/blob/d974a9fd4226e623775c7f929e45db5b6db03903/CONTRIBUTING.md#L295-L297) と、開発者のマニュアルの [「Golem 自身のライセンス」](https://github.com/tett23/golem/blob/d974a9fd4226e623775c7f929e45db5b6db03903/manual-dev/part2/14-fixtures.gm#L126-L129) は、貢献したコードとドキュメントが MIT で配布されると書く。

MIT は、複製物に著作権とライセンスの表示を残すことを条件にする。
ソフトウェアの条件としては軽いが、本の一節を写して社内の手引きに載せる人や、組版の見本として PDF のページを配る人にも、この表示が付いて回る。
マニュアルは、Golem の使い方を広めることと、組版の見本になることのために書いている（[ADR 0022](0022-manual-as-typesetting-sample.md)、[ADR 0024](0024-manual-audiences-and-policy.md)）。
どちらの目的にも、表示の条件はないほうが合う。
[docs/roadmap.md](../roadmap.md) の v0.1.0-rc3 の「マニュアルのライセンス」は、二つのマニュアルの原稿と組んだ PDF と HTML を CC0 にし、ほかの部分は MIT のままにすると決め、表示の置き場所をこの ADR に残した。

難しいのはフォントである。
マニュアルの PDF にはフォントが埋め込まれ、HTML には後で見るとおりフォントのファイルがそのまま入る。
フォントは SIL Open Font License 1.1（以下 OFL）で配布されており、Golem のメンテナーが権利を持つものではないので、CC0 で放棄できない。
OFL の条件 5 は、フォントを OFL のほかのライセンスで配ることを禁じる。
「マニュアルは CC0」とだけ書くと、HTML の中のフォントまで CC0 に読める表示になる。

### 確かめたこと

2026-10-24 に、origin/main の d974a9fd で次のことを確かめた。

フォントは、[scripts/manual/fetch-fonts.sh](https://github.com/tett23/golem/blob/d974a9fd4226e623775c7f929e45db5b6db03903/scripts/manual/fetch-fonts.sh#L14-L33) がタグで固定した配布元の URL から取得し、`manual/fonts/` と `manual-dev/fonts/` に置く。
どちらのディレクトリも `.gitignore` にあり、リポジトリには入らない。
取得するのは、Noto Serif JP の Regular、Noto Sans JP の Regular と Bold、Source Serif 4 の Regular、Source Sans 3 の Bold、Source Code Pro の Regular の六つのフォントと、配布元のライセンスの文書五つ（`LICENSE-NotoSerifJP.txt`、`LICENSE-NotoSansJP.txt`、`LICENSE-SourceSerif4.md`、`LICENSE-SourceSans3.md`、`LICENSE-SourceCodePro.md`）である。
スクリプトを手元で走らせて取得し、次のことを確かめた。

- 五つの文書は、どれも OFL 1.1 の全文を含む。Noto の二つは同じ内容（SHA-256 が一致）で、Source の三つは冒頭に Adobe の著作権の行と予約フォント名「Source」を書く。
- 六つのフォントの `name` テーブルの ID 13（ライセンスの説明）は、OFL 1.1 で配布するという一文と免責の文で、OFL の全文は入っていない。ID 14（ライセンスの URL）は `http://scripts.sil.org/OFL` である。ID 0（著作権）は、Noto が「© 2014-2021 Adobe」または「© 2017-2024 Adobe」、Source が Adobe の著作権と予約フォント名「Source」である。

HTML の出力は、フォントのファイルを丸ごと写す。
[golem-html の `renderXhtml`](https://github.com/tett23/golem/blob/d974a9fd4226e623775c7f929e45db5b6db03903/modules/golem-html/src/Golem/Html.hs#L285-L303) は、`style.toml` のフォントの役割が指す各ファイルを `fonts/<ファイル名>` に写すアセットに加え、CSS の `@font-face` がそれを指す。
ライセンスの文書は写さない。
リリースのワークフローは、[`build/html` をそのまま tar に固める](https://github.com/tett23/golem/blob/d974a9fd4226e623775c7f929e45db5b6db03903/.github/workflows/release.yml#L234-L245) ので、`golem-manual-<タグ>-html.tar.gz` と `golem-dev-manual-<タグ>-html.tar.gz` には、OFL の全文のないフォントのファイルが入っていることになる。
golem-epub も同じアセットの一覧を EPUB に入れる（[`Golem.Epub` の 142 行](https://github.com/tett23/golem/blob/d974a9fd4226e623775c7f929e45db5b6db03903/modules/golem-epub/src/Golem/Epub.hs#L142)）が、マニュアルは EPUB を組まない。

図版は二種類ある。
`manual/images/` の三つの PNG（`crop-marks.png`、`koya-hijiri.png`、`new-project.png`）は、Golem で組んだ PDF のページを画像にしたもので、ビューアーの画面は写っていない。
`git log` では、三つともメンテナーのコミットで加わった。
`koya-hijiri.png` の本文は泉鏡花の『高野聖』で、マニュアル自身が著作権の保護期間の満了を [第 1 章](https://github.com/tett23/golem/blob/d974a9fd4226e623775c7f929e45db5b6db03903/manual/chapters/01-first-book.gm#L278-L279) で述べている。
`manual-dev/images/` の六つの SVG は、`manual-dev/images/src/` の原稿の SVG から、[scripts/manual/outline-figures.sh](https://github.com/tett23/golem/blob/d974a9fd4226e623775c7f929e45db5b6db03903/scripts/manual/outline-figures.sh#L12-L30) が Inkscape で文字を輪郭にしたものである。
このスクリプトは、手元のフォントを使わず、原稿の書体名「Fig Sans」を `manual-dev/fonts/` の Noto Sans JP に割り当てる。
輪郭の SVG は、Noto Sans JP のグリフの輪郭を含む。

OFL の本文と FAQ（2026-10-24 に取得。FAQ は版 1.1-update7）は、これらの扱いを次のように定める。

- OFL の本文の末尾の条件は、フォントが OFL に留まるという要件は、フォントを使って作った文書には及ばないと定める。
- FAQ 1.1 と 1.1.1 は、フォントの輪郭をもとにしたロゴや図を作ってよく、作った図の著作者と著作権者は作った人のままだと答える。輪郭の SVG と PNG は、この「作った文書と図」にあたる。
- FAQ 1.10 は、OFL の全文を添えずにフォントを配れるのは、文書に埋め込むときとプログラムに組み込むときだけだと答える。メタデータの中の全文への URL は法的には足りるが、全文を入れることを強く勧める。
- FAQ 1.11 は、取り出しにくい形で文書に入れることを埋め込みと呼び、それ以外の渡し方は配布であって、著作権の表示とライセンスの情報を添えなければならないと答える。
- FAQ 1.12 と 1.13 は、全体でもサブセットでも文書に埋め込んでよく、埋め込みは文書のライセンスを変えないと答える。
- FAQ 2.1 は、CSS の `@font-face` でウェブフォントとして使うことを配布として扱う。

これに従うと、PDF に埋め込んだフォントは文書への埋め込みであり、OFL の全文を添えなくてよい。
HTML の tar に入るフォントのファイルは、`@font-face` で読ませるために丸ごと渡すものなので配布である。
FAQ 1.10 によれば `name` テーブルの URL で法的には足りるが、FAQ が強く勧める全文は今は添えていない。

マニュアルが写す外部の文章は、『高野聖』の冒頭（第 1 章のコードブロックと `koya-hijiri.png`）だけで、保護期間の満了した作品である。
青空文庫の「収録ファイルの取り扱い規準」は、著作権の消滅した作品のファイルを自由に複製し、改変し、配ってよいとし、底本や入力者と校正者の情報を残すことを希望する（条件ではない）。
マニュアルはその情報を第 1 章の脚注に載せている。
参考文献の一覧（`references.json`）は書誌の情報であり、本文を写していない。

`manual/` と `manual-dev/` を変えたコミットの作者は、`git log` ではすべてメンテナー（tett23 と、同じメールアドレスの別名）であり、多くのコミットに Claude の `Co-Authored-By` が付く。
外部の貢献者はいないので、今の原稿を CC0 にするのに、メンテナーのほかの同意は要らない。

### 検討で決めたこと

- CC0 の範囲は、`.gm` だけでなく、`manual/` と `manual-dev/` の下で Git が管理するすべてのファイル（`fonts/` を除く）とする。`.gm` だけにすると、組むのに要る `style.toml` や図版が MIT に残り、PDF と HTML を CC0 にしても、それを作った入力の一部に表示の条件が残る。
- 宣言者は、根の LICENSE の著作権者 tett23 とする。マニフェストの `publisher` と著者の「Golem プロジェクト」は法人でも団体でもないので、権利を放棄する主体にしない。
- LICENSE には、CC0 を知らない読み手のために、条文の前に CC0 1.0 の説明のページの URL を置く。
- 日本法では著作者人格権を放棄できないので、奥付に、著作者人格権を行使しないことを書く。

## 実装すること

### CC0 の範囲

CC0 1.0 を宣言するのは次のものとする。
宣言者（Affirmer）は、根の LICENSE の著作権者と同じ tett23 とする。

- `manual/` と `manual-dev/` の下で Git が管理するすべてのファイル。原稿の `.gm`、`manifest.toml`、`style.toml`、`preflight.toml`、`references.json`、`manual/data/`、`manual/examples/`、`manual/images/`、`manual-dev/images/`（`src/` の原稿と輪郭の SVG の両方）を含む。
- 二つのマニュアルを組んだ出力（今は PDF と HTML）。生成物の `common/build-info.gm` も含む。

範囲の外は次のとおりである。

- `manual/fonts/` と `manual-dev/fonts/` のフォントと、それを写した出力の中のフォント。OFL 1.1 のままである。
- 根の LICENSE が覆う、ほかのすべてのファイル。マニュアルを組むスクリプト（`scripts/manual/`）と、書き方の方針（`docs/manual-policy.md`）も MIT のままである。
- 『高野聖』のように、もとから保護期間の満了した文章。宣言者の権利でないので CC0 の対象にならないが、パブリックドメインなので、使う人の条件は変わらない。

### LICENSE のファイル

`manual/LICENSE` と `manual-dev/LICENSE` は、1 行目に CC0 1.0 の説明のページの URL（`https://creativecommons.org/publicdomain/zero/1.0/`）を置き、空行を一つ挟んで、Creative Commons の CC0 1.0 の条文の平文（`https://creativecommons.org/publicdomain/zero/1.0/legalcode.txt`）を一字も変えずに置く。
2026-10-24 に取得した平文の SHA-256 は `a2010f343487d3f7618affe54f789f5487602331c0a8d03f49e9a7c547cf0499` である。
URL のほかの説明や範囲の注記は、このファイルに書かない。
範囲とフォントの例外は、奥付、README、CONTRIBUTING に書く。

根の LICENSE は変えない。
MIT の全文と著作権の行だけを置き、マニュアルの例外は README に書く。

### 奥付

二つのマニュアルの奥付（`manual/back.gm` と `manual-dev/back.gm`）の、フォントの段落の後に、ライセンスの段落を足す。
使い手のマニュアルは次の文とする。
開発者のマニュアルは同じ内容を常体で書き、条文の場所を `manual-dev/LICENSE` にする。

```
この本の原稿と、原稿から組んだ PDF と HTML は、CC0 1.0 で公開しています。
著作者は、法が許す限り、この本の著作権とそれに関わる権利を放棄しています。
放棄できない著作者人格権は、行使しません。
誰でも、断りなく複製し、改変し、配れます。
条文は、リポジトリの [code: manual/LICENSE] にあります（[code: https://github.com/tett23/golem/blob/main/manual/LICENSE]）。

ただし、PDF に埋め込んだフォントと、HTML と一緒に配るフォントは、SIL Open Font License 1.1 で配布されているもので、CC0 の対象ではありません。
フォントのライセンスの全文は、HTML の [code: fonts/] に、フォントと並べて置いています。
```

フォントが OFL 1.1 だと述べる既存の一文は残す。

### 組んだ HTML に入れるライセンスの文書

[scripts/manual/build.sh](https://github.com/tett23/golem/blob/d974a9fd4226e623775c7f929e45db5b6db03903/scripts/manual/build.sh) は、`golem build` が diagnostic を出さずに終わった後、プロジェクトごとに次の二つを写す。

- プロジェクトの `LICENSE` を `build/html/LICENSE` に写す。プロジェクトに `LICENSE` がなければ、終了コード 1 で失敗する。
- `build/html/fonts/` があれば、プロジェクトの `fonts/LICENSE-*` をすべて `build/html/fonts/` に写す。

リリースのワークフローは `build/html` をそのまま固めるので、変えない。
二つの HTML の tar に、CC0 の条文と OFL の全文が入る。
CI の成果物 `manual` と `manual-dev` にも入る。
`scripts/determinism.sh` は `build/` の下のすべてのファイルのハッシュを書くので、写したファイルも二つのアーキテクチャで比べることになる。

PDF には何も足さない。
埋め込んだフォントに OFL の全文は要らず（FAQ 1.10）、奥付がフォントと OFL を名指す。

### README、CONTRIBUTING、仕様、マニュアルの記述

- README の「License」を、MIT と書いたうえで、`manual/` と `manual-dev/`（`fonts/` を除く）と組んだ PDF と HTML は CC0 1.0（`manual/LICENSE`）、フォントは OFL 1.1 と書く。README の「マニュアル」の節にも、組んだ HTML にライセンスの文書を写すことを書く。
- CONTRIBUTING.md と CONTRIBUTING.en.md の「ライセンス」を、`manual/` と `manual-dev/` への貢献は CC0 1.0 で、ほかは MIT で配布されると書き分ける。
- 開発者のマニュアルの「Golem 自身のライセンス」（第二部のフィクスチャの章）を、CONTRIBUTING と同じに書き分ける。「二つに共通する体裁」の「奥付は版とコミットの二行を載せる」に、ライセンスの段落を足す。
- docs/specifications.md のマニュアルの節に、`build.sh` がライセンスの文書を写すことと、リリースの HTML の tar の中身を書く。
- docs/manual-policy.md の後付けの記述に、奥付にライセンスの段落を置くことを足す。
- docs/roadmap.md から「マニュアルのライセンス」を除き、v1.0.0 に「HTML の出力のフォントのライセンスの文書」（Golem の本体が HTML と EPUB の出力にフォントのライセンスの文書を写すことを、HTML Living Standard への変更とあわせて決める）を足す。

## 実装しないこと

- Golem の本体が、HTML と EPUB の出力にフォントのライセンスの文書を写すこと。`golem build` の HTML がフォントを OFL の全文なしで配るのは、マニュアルに限らず、Golem を使うすべての本に起きる。ただ、どのファイルがライセンスの文書かを Golem が知る手段（`style.toml` に書くのか、名前で探すのか）と、EPUB の中のフォントを埋め込みとみなすかを決める必要がある。この ADR では、マニュアルを組むスクリプトで足りる分だけを直す。本体の扱いは、HTML の出力を XHTML から HTML Living Standard に変える予定とあわせて、v1.0.0 のころに決める（docs/roadmap.md の v1.0.0 に足す）。
- 原稿や出力のメタデータ（PDF の XMP や EPUB の `dc:rights`）にライセンスを書くこと。マニフェストにはライセンスを書く項目がない。
- 二冊の「はじめに」でマニュアルのライセンスを説明すること。「はじめに」が説明するのは Golem のライセンス（MIT）であり、本のライセンスは奥付に置く。
- 貢献に DCO や CLA を求めること。貢献の受け取りと配布を同じライセンスにし（inbound=outbound）、CONTRIBUTING に書くだけにする。外部の貢献が実際に始まるのは v1 より後と見込むので、DCO と CLA はそのときに検討する。
- MIT から CC0 に変える前に配ったマニュアル（v0.1.0-rc2 までのリリースのアセット）の扱いを変えること。配ったものは MIT のままで、CC0 は v0.1.0-rc3 から組んだものに付く。

## テスト設計

テストは `scripts/manual/test.sh` に足し、実装の前に書いて失敗させる。
このテストは偽の `golem` で `build.sh` を走らせるので、偽の `golem` が `build/html/` と `build/html/fonts/` を作る場合を足す。

- 偽の `golem` が `build/html/fonts/` を作り、プロジェクトの `fonts/` に `LICENSE-A.txt` と `LICENSE-B.md` がある。`build.sh` の後、`build/html/LICENSE` がプロジェクトの `LICENSE` と同じバイト列であり、`build/html/fonts/` に二つの文書が同じバイト列で入っている。
- 偽の `golem` が `build/html/` だけを作り、`fonts/` を作らない。`build.sh` は成功し、`build/html/fonts/` を作らない。
- プロジェクトに `LICENSE` がない。`build.sh` は終了コード 1 で終わり、標準エラー出力が `LICENSE` を名指す。
- 偽の `golem` が notice を出す。`build.sh` は今までどおり失敗し、`build/html/LICENSE` を写さない。
- リポジトリの `manual/LICENSE` と `manual-dev/LICENSE` が、どちらも 1 行目が `https://creativecommons.org/publicdomain/zero/1.0/`、2 行目が空で、3 行目からの SHA-256 が `a2010f343487d3f7618affe54f789f5487602331c0a8d03f49e9a7c547cf0499` である。
- リポジトリの `manual/back.gm` と `manual-dev/back.gm` が、どちらも「CC0 1.0」と「SIL Open Font License 1.1」を含む。原稿の文字列を見るだけの検査であり、組んだ奥付にその段落が載ることは次の手で確かめる。

自動のテストにしないものは、実装の後に手で確かめる。

- 二冊を `scripts/manual/build.sh` で組み、PDF と HTML の奥付にライセンスの段落が載ることを目で確かめる。
- v0.1.0-rc3 の下書きのリリースで、二つの HTML の tar を `tar -tzf` で一覧し、`<名前>-html/LICENSE` と、`<名前>-html/fonts/` の五つの `LICENSE-*` があることを確かめる。

## トレードオフ

CC0 にすると、写した人にマニュアルの出典を示す義務がなくなる。
CC BY 4.0 なら出典の表示を求められるが、それは今の MIT と同じく、一節を写す人と見本のページを配る人に表示の条件を課すことになる。
ロードマップが CC0 と決めたので、出典が失われることは受け入れる。

LICENSE には URL と条文だけを置き、範囲とフォントの例外を書かないので、`manual/` の下だけを見た人は、HTML の中のフォントの扱いを奥付まで読まないと知れない。
注記を長くすると条文との境目が曖昧になるので、条文の前には URL の一行だけを置き、条文の部分は SHA-256 で一字も変えていないことを確かめる。
組んだ HTML では `fonts/` の中に OFL の全文が並ぶので、フォントの扱いはファイルの配置からも読める。

開発者のマニュアルは、リポジトリのコード（MIT）を引用している。
同じ著作権者が同じコードを、リポジトリでは MIT、マニュアルの中では CC0 で配ることになる。
著作権者が一人のあいだは矛盾しないが、外部の貢献者のコードをマニュアルに引くときは、その貢献者の CC0 の同意が要る。
貢献の受け取りを CONTRIBUTING の記述だけに頼るのは、この同意をプルリクエストを出したことに読み込むことである。
DCO のような明示の署名に比べると弱い。

`build.sh` でフォントのライセンスの文書を写しても、直るのはマニュアルの HTML だけである。
Golem を使うほかの本の HTML は、今のまま OFL の全文なしでフォントを配る。
本体で直すには、ライセンスの文書の見つけ方と EPUB の扱いを決める必要があるので、マニュアルを先に直し、本体は HTML Living Standard への変更とあわせて v1.0.0 のころに決める。

## 参考文献

- Creative Commons, "CC0 1.0 Universal" (Legal Code). https://creativecommons.org/publicdomain/zero/1.0/legalcode（平文: https://creativecommons.org/publicdomain/zero/1.0/legalcode.txt 。2026-10-24 に取得）
- SIL International, "SIL Open Font License, Version 1.1". https://openfontlicense.org/open-font-license-official-text/（2026-10-24 に取得）
- SIL International, "OFL-FAQ", version 1.1-update7. https://openfontlicense.org/ofl-faq/（2026-10-24 に取得。1.1、1.1.1、1.10、1.11、1.12、1.13、2.1 を参照）
- 青空文庫「青空文庫収録ファイルの取り扱い規準」. https://www.aozora.gr.jp/guide/kijyunn.html（2026-10-24 に取得）
- [docs/roadmap.md](../roadmap.md) の v0.1.0-rc3 の「マニュアルのライセンス」
- [ADR 0022](0022-manual-as-typesetting-sample.md)、[ADR 0024](0024-manual-audiences-and-policy.md)
