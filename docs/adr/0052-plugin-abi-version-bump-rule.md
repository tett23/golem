# ADR 0052: プラグインの ABI のバージョンは、リリースしたバージョンからだけ上げる

ステータス: 採択

## 文脈

プラグインとの ABI のバージョンは、`Golem.Doc.IR.abiVersion` と `Golem.Plugin.abiVersion` の値である。
プラグインは `golem_abi_version` でバージョンを返し、処理系の値と違えば読み込みを止める（[golem-plugin ADR 0001](../golem-plugin/adr/0001-wasm-host-and-abi.md)）。
`Golem.Doc.IR` のコメントは「IR を変えるたびに上げる」と書く。

ABI を変える ADR は、これまで個別に「ABI の版を一つ上げる」と書いてきた（[ADR 0003](0003-verse-line-breaks.md)、[ADR 0005](0005-character-and-paragraph-styles.md)、[ADR 0017](0017-forced-page-breaks.md)、[ADR 0019](0019-aki-settings.md) など）。
[ADR 0030](0030-manual-page-break-control.md) も、`PageControl` のブロックを足すときに、次のように書いた。

> CDDL（`modules/golem-doc/schema/golem-doc.cddl`）に次のブロックを加え、ABI の版を一つ上げる。
> 今の版は 6 であり、この ADR より前に別の ADR が版を上げていれば、その次の版にする。

実際には、次のように進んだ。

- v0.1.0-rc2 の ABI のバージョンは 6 である。
- rc2 の後、[golem-pdf ADR 0008](../golem-pdf/adr/0008-pdf-figures.md) の実装（コミット 9106b162）が 7 に上げた。
- [ADR 0030](0030-manual-page-break-control.md) の実装は、7 のまま `PageControl` を足した。[ADR 0030](0030-manual-page-break-control.md) の文のとおりなら 8 になるはずだった。
- 仕様書（[docs/specifications.md](../specifications.md)）は、`PageControl`、行アキ、回した図版の三か所で「ABI のバージョンは、同じリリースで先に上げた 7 のままとする」と書く（1819 行、2046 行、2132 行）。

「まだリリースしていない ABI のバージョンは上げない」という規則は、[ADR 0030](0030-manual-page-break-control.md) より後の個別の ADR にだけ書かれている。

- [golem-doc ADR 0006](../golem-doc/adr/0006-integer-range-in-ir.md)：7 はまだリリースしておらず、同じリリースの中の変更なので、7 のままとする。
- [golem-doc ADR 0007](../golem-doc/adr/0007-plugin-channel-lists.md)：7 はまだリリースしていないので、バージョンを変えずに ABI を広げられる。
- [ADR 0046](0046-blank-line-command.md)：7 のままとし、この ADR の実装より前に ABI 7 を含むバージョンをリリースした場合は一つ上げる。
- [golem-driver ADR 0036](../golem-driver/adr/0036-combining-characters.md)：7 のままとする。

この規則は、一般の規則としてどこにも採択されていない。
[ADR 0030](0030-manual-page-break-control.md) は、実装と食い違ったまま採択の状態にある。
`Golem.Doc.IR` のコメントも、この規則と食い違う。

ABI のバージョンは、配布したプラグインとの互換を判定するためのものである。
リリースしていないバージョンの ABI で作られたプラグインは、開発中のものに限られる。
同じリリースの中で ABI を何度変えても、利用者が手にするのはリリースの時点の ABI だけである。
変更のたびに上げると、リリースのあいだにバージョンが跳び、跳んだバージョンに当たる ABI はどのリリースにも存在しない。

## 実装すること

### 規則

プラグインの ABI のバージョンを、次の規則で決める。

1. リリースとは、`v` で始まるタグを打つことである。`v0.1.0-rc3` のようなプレリリースも含む。
2. ABI を変えるとき、今のバージョンがすでにリリースに含まれていれば、バージョンを一つ上げる。
3. 今のバージョンがまだどのリリースにも含まれていなければ（直前のリリースの後に上げたものなら）、バージョンを変えない。
4. したがって、二つのリリースのあいだで、バージョンは高々一つしか上がらない。
5. リリースに含まれたバージョンの ABI は、後から変えない。

ABI の変更には、次のものを含める。

- CDDL（`modules/golem-doc/schema/golem-doc.cddl`）の変更。意味論 IR の形と、`golem_describe` の応答の形の両方を含む。
- `Golem.Doc.Validate` の不変条件の変更。プラグインが返してよい文書の範囲が変わるためである。
- プラグインが export する関数と、その引数と戻り値の取り決め（[golem-plugin ADR 0001](../golem-plugin/adr/0001-wasm-host-and-abi.md)）の変更。
- 形は同じで、欄の値の意味を変えるもの。

ABI を変える新しい ADR は、上げるかどうかをこの規則で決め、「ABI のバージョンは [ADR 0052](0052-plugin-abi-version-bump-rule.md) の規則による」と書けばよい。
個別の ADR に、上げる数を書かない。
ADR を書いた時点と実装する時点のあいだにリリースがあると、上げるかどうかが変わるためである。

### CI の検査

`scripts/ci/abi-version.sh` を足し、`changes` ジョブで実行する。

- HEAD から辿れる最新の `v` で始まるタグ（`git describe --tags --abbrev=0 --match 'v*'`）を、直前のリリースとする。
- ABI を表すファイルとして、次の二つを、直前のリリースと HEAD で比べる。
  - `modules/golem-doc/schema/golem-doc.cddl`。`;` から行末までのコメントと空白を取り除いて比べる。
  - `modules/golem-doc/src/Golem/Doc/Validate.hs`。`--` から行末までのコメント、`{-` と `-}` で囲んだコメント、空白を取り除いて比べる。
- 直前のリリースと HEAD の `Golem.Doc.IR.abiVersion` の値を、`abiVersion = ` の行から読む。
- 二つのファイルがどちらも同じなら、HEAD の値はリリースの値と同じでなければならない。
- どちらかが違えば、HEAD の値はリリースの値に一つ足したものでなければならない。
- どちらにも合わなければ、両方の値と、違いのあったファイルの名前を標準エラー出力に書き、終了コード 1 で終わる。
- 直前のリリースに比べるファイルがなければ（ファイルを移した場合）、その旨を書いて終了コード 1 で終わる。移したときは、このスクリプトの比べるパスを同じ変更で直す。
- `changes` ジョブは `fetch-depth: 0` で取得しているので、タグを読める。

`Validate.hs` は、プラグインが返した文書の不変条件を検査するモジュールである。
不変条件を変えれば、プラグインが返してよい文書の範囲が変わるので、ABI の変更として扱う。
検査は、意味の変わらない書き換え（関数の名前の変更、並べ替え）も ABI の変更とみなす。
その場合も、リリースのあいだで一つ上がるだけであり、上げすぎて害になることはない。

プラグインが export する関数の取り決めと、欄の値の意味の変更は、ファイルの差から判定できない。
これらは ADR のレビューで規則を当てる。

### 今のバージョン

今のバージョン 7 は、どのリリースにも含まれていない（v0.1.0-rc2 は 6）。
この ADR は、7 を変えない。
次のリリース（v0.1.0-rc3）に 7 が含まれた後に ABI を変える ADR は、8 に上げる。

### コードのコメント

`Golem.Doc.IR.abiVersion` と `Golem.Plugin.abiVersion` のコメントを、「この ADR の規則で上げる」という趣旨に書き直す。

### ドキュメント

- [ADR 0030](0030-manual-page-break-control.md) のステータスの行を「採択→ABI のバージョンを上げるかどうかは [ADR 0052](0052-plugin-abi-version-bump-rule.md)」に改める。
- 仕様書の「プラグイン」の「シリアライズ形式」の節に、この規則と今のバージョン（7）を書き、この ADR へのリンクを付ける。
- 仕様書の三か所の「ABI のバージョンは、同じリリースで先に上げた 7 のままとする。」は、規則と重なるので消す。仕様書は今の振る舞いだけを書くためである。
- 開発者のマニュアルのリリースの章（`manual-dev/part2/13-release.gm`）に、リリースの前に ABI のバージョンを確かめる必要はなく、`scripts/ci/abi-version.sh` が検査することを一文で書く。
- 開発者のマニュアルの CI のジョブの章（`manual-dev/part2/11-ci-jobs.gm`）の `changes` の手順と、README の CI の表の `changes` の説明に、この検査を足す。
- [golem-doc ADR 0006](../golem-doc/adr/0006-integer-range-in-ir.md) と [golem-doc ADR 0007](../golem-doc/adr/0007-plugin-channel-lists.md)、[ADR 0046](0046-blank-line-command.md)、[golem-driver ADR 0036](../golem-driver/adr/0036-combining-characters.md) は、この規則と一致しているので、ステータスを変えない。

## 実装しないこと

- 今のバージョン 7 を 8 に上げること。7 はまだリリースしていない。
- ABI のバージョンを、処理系のバージョン（`0.1.0` など）と結び付けること。処理系のバージョンは ABI を変えないリリースでも上がる。
- 同じ ABI のバージョンの中で互換を保つ変更（欄の追加など）を許し、小さな番号を足すこと。今のホストは、バージョンが一致しないプラグインをすべて拒む。互換の判定を細かくする必要が出たら、別の ADR で決める。
- プラグインが export する関数の取り決めと、欄の値の意味の変更を、CI で自動で見つけること。ファイルの差から判定する規則を書けない。
- [ADR 0030](0030-manual-page-break-control.md) より前に「一つ上げる」と書いた ADR（0003、0005、0017、0019 など）のステータスを改めること。どれも実装済みで、上げた結果はリリースした 6 までのバージョンに含まれており、今後のバージョンの決め方に影響しない。

## テスト設計

### abi-version.sh 自身（`scripts/ci/test.sh` に足す）

先に書き、失敗させてから `abi-version.sh` を書く。
一時的なリポジトリを作り、`v0.0.1` のタグを打った後にコミットを足して、次を確かめる。

- CDDL もバージョンも変えないと、終了コード 0 になること。
- CDDL のコメントだけを変えてバージョンを変えないと、終了コード 0 になること。
- CDDL の規則を変えてバージョンを一つ上げると、終了コード 0 になること。
- CDDL の規則を変えてバージョンを変えないと、終了コード 1 になり、二つの値が標準エラー出力にあること。
- CDDL の規則を変えてバージョンを二つ上げると、終了コード 1 になること。
- CDDL も `Validate.hs` も変えずにバージョンを上げると、終了コード 1 になること。
- `Validate.hs` の検査の式を変えてバージョンを変えないと、終了コード 1 になり、`Validate.hs` の名前が標準エラー出力にあること。
- `Validate.hs` のコメントだけを変えてバージョンを変えないと、終了コード 0 になること。
- CDDL と `Validate.hs` の両方を変えてバージョンを一つ上げると、終了コード 0 になること。
- 直前のリリースに `Validate.hs` がなければ、終了コード 1 になること。
- `v` で始まるタグがないリポジトリでは、検査を飛ばす旨を書いて終了コード 0 になること。

### 今のリポジトリ

- `sh scripts/ci/abi-version.sh` が今の main で終了コード 0 になること。v0.1.0-rc2 から CDDL が変わり、バージョンが 6 から 7 へ一つ上がっているためである。この項目が通らなければ、比べ方を直すか、今のバージョンの決め方を見直す。

### 既存のテスト

- golem-doc の `test/Main.hs` の `abiVersion @?= 7` と、golem-plugin の `test/Main.hs` の、二つの `abiVersion` が等しいことのテストは、今のまま残す。

## トレードオフ

リリースのあいだに何度 ABI を変えても、バージョンは一つしか上がらない。
開発中のプラグインは、同じバージョンのまま ABI が変わったホストで読み込めてしまい、復号の誤り（G0609 など）で初めて違いに気づく。
開発中のプラグインを使うのは Golem の開発者とプラグインの作者に限られ、ホストはプラグインの出力を毎回検査するので、壊れた出力が黙って組まれることはない。
配布したプラグインとの互換の判定という目的には、リリースの単位で十分である。

CI の検査は、直前のリリースのタグを基準にする。
7 を含むリリースの後に、ABI を変えるプルリクエストが二つ並んだ場合を考える。
どちらのプルリクエストも、直前のリリースから ABI を表すファイルが変わるので、自分で 8 に上げなければ検査を通らない。
二つをマージした後の main も、ファイルが変わってバージョンが 8 なので通る。
並んだプルリクエストが、それぞれ一つずつ上げて 9 にしてしまうことは、検査が防ぐ。
二つのプルリクエストは `abiVersion` の同じ行を同じ値に変えるので、その行は git のマージで競合しない。

## 参考文献

- [ADR 0030](0030-manual-page-break-control.md)
- [ADR 0046](0046-blank-line-command.md)
- [golem-doc ADR 0006](../golem-doc/adr/0006-integer-range-in-ir.md)
- [golem-doc ADR 0007](../golem-doc/adr/0007-plugin-channel-lists.md)
- [golem-plugin ADR 0001](../golem-plugin/adr/0001-wasm-host-and-abi.md)
- [golem-pdf ADR 0008](../golem-pdf/adr/0008-pdf-figures.md)
