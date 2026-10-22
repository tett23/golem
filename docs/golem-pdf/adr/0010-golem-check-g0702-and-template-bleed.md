# ADR 0010: `golem check` の G0702 の条件と、雛形の塗り足し

ステータス: 採択

## 文脈

[ADR 0004](0004-crop-marks-and-bleed.md) は、日本式のトンボと塗り足しが 0 の組み合わせを G0702 とした。
`golem check` が G0702 を出す条件は、次のように書いた。

> `golem check` は、マニフェストのターゲット（`targetsOf`）に PDF があれば出す。

同じ日に採択した [golem-project ADR 0004](../../golem-project/adr/0004-font-file-check-per-target.md) は、「実装しないこと」に次のように書いた。

> `golem check --target`。`golem check` は常に四つのターゲットを検査する。

[golem-cli ADR 0002](../../golem-cli/adr/0002-build-all-targets-by-default.md) も、`golem build` が `--target` を省くとマニフェストの `[targets.*]` を見ずに四つのターゲットを作ると決めた。

実装は [golem-project ADR 0004](../../golem-project/adr/0004-font-file-check-per-target.md) の側に従う。

- golem-cli の `run` は、`golem check` に `optTargets = Just allTargets` を渡す。
- golem-driver の `buildCore` は、`optTargets` が `Nothing` のときだけ `targetsOf` でマニフェストのターゲットを使う。CLI からは `Nothing` が渡らない。
- `cropMarkDiagnostics` は、ターゲットに PDF があり、`--marks japanese` で、`bleed` が 0 なら G0702 を出す。

したがって、マニフェストに `[targets.pdf]` がなくても、`golem check --marks japanese` は塗り足しのないプロジェクトで G0702 を出す。
docs/specifications.md の CLI の節は、[ADR 0004](0004-crop-marks-and-bleed.md) の文言を写して「`golem check` も、マニフェストのターゲットに PDF があれば G0702 を検査する」と書いており、コードと合わない。

二つの採択済みの ADR が衝突しているので、どちらを正とするかを決める。

### 雛形の塗り足し

`golem new` の雛形の `style.toml` は、`[page]` に `bleed` を書かない（[golem-cli ADR 0006](../../golem-cli/adr/0006-preflight.md) の「雛形の `style.toml` は変えない」）。
そのため、雛形のプロジェクトで `--marks japanese` を付けると G0702 で PDF を組めない。
使い手のマニュアルも、入稿の手順の最初で `bleed` を書かせ、`golem preflight` の最初の実行では G0910（塗り足しの幅の不足）が出ると説明している。

塗り足しは、日本の印刷所の入稿の案内では 3mm がふつうである（[golem-cli ADR 0006](../../golem-cli/adr/0006-preflight.md) の `bleed-size` の既定も 3mm 以上）。
英語の雛形は、英語圏の印刷所の慣行に合わせて 0.125in とする。
メンテナーは、日本語の雛形に 3mm、英語の雛形に 0.125in の塗り足しを書くと決めた。

## 実装すること

`golem check` は、マニフェストの `[targets.*]` によらず、四つのターゲットをすべて検査すると決める。
G0702 も、`--marks japanese` で `style.toml` の `[page]` の `bleed` が 0 なら、マニフェストに PDF のターゲットがなくても報告する。
コードの振る舞いは変えない。

`golem check` は「`golem build` が通るか」を先に知るための命令であり（[golem-project ADR 0004](../../golem-project/adr/0004-font-file-check-per-target.md)）、`golem build` の既定は四つのターゲットである（[golem-cli ADR 0002](../../golem-cli/adr/0002-build-all-targets-by-default.md)）。
`golem check` だけがマニフェストのターゲットを見ると、`golem check` が通っても、同じオプションの `golem build` が G0702 で止まる。

`style.toml` だけで決まる G0701、G0725、G0807 などを `golem check` で報告する条件（PDF をターゲットに含むとき）も、同じく常に満たされる。
これらは [golem-driver ADR 0016](../../golem-driver/adr/0016-output-and-layout-diagnostic-codes.md) の範囲であり、決定は変えない。

### 雛形の `style.toml`

`golem new` の雛形の `style.toml` の `[page]` に、塗り足しを書く（golem-driver の `Golem.Driver.New`）。

- 日本語の雛形（`--language ja`）：`bleed = "3mm"`
- 英語の雛形（`--language en`）：`bleed = "0.125in"`

今の `style.toml` の寸法は `in` の単位を受け付けないので、`in` を加える [golem-project ADR 0010](../../golem-project/adr/0010-inch-unit.md) を先に実装する。
`--no-fonts` を付けても同じである。

これで、雛形のプロジェクトは `--marks japanese` でそのまま PDF を組め、`golem preflight` の `print` で G0910 が出なくなる。
出力インテントがないことの G0914 は残る。

### ADR のステータス

- [ADR 0004](0004-crop-marks-and-bleed.md) のステータスの行を次のようにする。

  ```
  ステータス: 採択→トンボの色は [ADR 0007](0007-registration-crop-marks.md)、`golem check` が G0702 を出す条件は [ADR 0010](0010-golem-check-g0702-and-template-bleed.md)
  ```

- [golem-cli ADR 0006](../../golem-cli/adr/0006-preflight.md) のステータスの行を次のようにする。

  ```
  ステータス: 採択→G0905 の廃止と、図版の検査の PDF の図版への拡張は [golem-pdf ADR 0008](../../golem-pdf/adr/0008-pdf-figures.md)、雛形の `style.toml` の塗り足しは [golem-pdf ADR 0010](../../golem-pdf/adr/0010-golem-check-g0702-and-template-bleed.md)
  ```

### ドキュメント

- docs/specifications.md の CLI の節の「`golem check` も、マニフェストのターゲットに PDF があれば G0702 を検査する」を、「`golem check` は四つのターゲットを検査するので、マニフェストのターゲットによらず G0702 を検査する」に改め、この ADR へのリンクを付ける。
- 「PDF をターゲットに含む `golem check`」と書いた箇所は、`golem check` に PDF を含まない場合があると読めるので、すべて「`golem check`（四つのターゲットを検査するので、つねに PDF を含む）」の意味に改める。対象は次のとおりである。
  - docs/specifications.md の「style.toml」の節の、索引の段の行長（G0744）、コードブロックの行長（G0743）、段落スタイルの字下げ（G0725）。
  - docs/specifications.md の、マスターページの柱の `set` の変数（G0267、G0268）。
  - docs/specifications.md の「CLI」の節の、版面、字下げ、本文のフォント（G0701、G0725、G0807）と、隠しノンブルの重なり（G0750）。
  - `docs/diagnostics.md` の G0267 と G0268 の節の「PDF をターゲットに含むビルドと `golem check`」。
- docs/specifications.md の `golem new` の雛形の説明と `style.toml` の `[page]` の `bleed` の説明に、日本語の雛形が `bleed = "3mm"`、英語の雛形が `bleed = "0.125in"` を書くことを足す。
- 使い手のマニュアルの第 1 章（`golem preflight` の最初の実行で出るエラー）と第 6 章（塗り足しとトンボ、プリフライト）を、雛形が塗り足しを持つことに合わせて改める。第 6 章の「雛形に `bleed` と `intent` が書かれていない」理由と、最初の実行に `--marks japanese` を付けなかった理由の段落を書き直す。第 6 章の塗り足しの説明に、英語の雛形は 0.125in であることを足す。
- `docs/diagnostics.md` の G0702 の節の「PDF をターゲットに含まないビルドと LSP では出さない」に、`golem check` はマニフェストのターゲットによらず出すことを足し、ADR の欄にこの ADR を足す。

## 実装しないこと

- `golem check --target`。[golem-project ADR 0004](../../golem-project/adr/0004-font-file-check-per-target.md) のとおり加えない。
- golem-driver の `build` に `optTargets = Nothing` を渡したときの振る舞い（マニフェストのターゲットを使う）の変更。[golem-cli ADR 0002](../../golem-cli/adr/0002-build-all-targets-by-default.md) が残すと決めたライブラリの振る舞いであり、CLI からは使われない。
- LSP で G0702 を出すこと。

## テスト設計

`golem check` の G0702 の条件はコードを変えないので、CLI の振る舞いを固定するテストを足す。
golem-driver の `test/PdfSpec.hs` の「golem check with Japanese marks and no bleed is G0702 and writes nothing」は `optTargets = Nothing`（マニフェストのターゲット）で検査しており、CLI が渡す `Just allTargets` の経路を確かめていない。

- golem-cli の `test/Main.hs` の `--marks` のテストに、`[targets.html]` だけを持ち `[targets.pdf]` を持たないマニフェストで `golem check --marks japanese` を実行し、標準エラー出力に G0702 が出ることを確かめるテストを足す。
- 同じマニフェストで `golem check --marks western` を実行し、標準エラー出力に G0702 が出ないことを確かめる。G0702 が `--marks japanese` だけに依ることを固定するためである。このプロジェクトは `style.toml` を持たないので、`golem check` は PDF の本文のフォントの欠け（G0807）でも失敗する。終了コードではなく、G0702 の有無で確かめる。

雛形の塗り足しは、次のテストを先に書き、失敗させてから実装する。

- golem-cli の `test/CommandsSpec.hs`：`golem new` で作った日本語のプロジェクトの `style.toml` の `[page]` の `bleed` が `"3mm"` で、英語のプロジェクトでは `"0.125in"` であること。
- golem-project の `Style` の読み込みで、英語の雛形の `style.toml` の塗り足しが 0.125in（9pt と同じ sp）になること。
- 同じファイルの「the summary of a new project names its preflight.toml ...」を、エラーが 1（G0914 だけ）になり、G0910 が出ない形に改める。
- golem-cli：`golem new` で作ったプロジェクトで、`golem build --target pdf --marks japanese` が G0702 を出さないこと（フォントを置いた状態で、PDF が書かれること）。

## トレードオフ

- PDF を作らない利用者も、`--marks japanese` を付けて `golem check` を実行すれば G0702 で失敗する。`--marks` は PDF でだけ有効なオプションなので、PDF を作らない利用者が付ける理由は少ない。付けた場合は、`golem build` も四つのターゲットで同じ G0702 で止まるので、二つの命令の結果はそろう。
- マニフェストのターゲットを `golem check` の範囲に使う道は閉じる。範囲を絞りたい利用者のための `golem check --target` は、必要になったときに別の ADR で扱う。

- 雛形で組んだ PDF は、トンボを付けなくても、仕上がりの外側に塗り足しの分（3mm か 0.125in）だけ大きくなる。今の Golem は塗り足しの領域に何も描かないので、画面で読む PDF の周りに白い余白が付く。[golem-cli ADR 0006](../../golem-cli/adr/0006-preflight.md) が雛形に塗り足しを入れなかった理由の一つである。入稿する本を作る道具として、入稿の手順の一つを最初から満たすほうを選んだ。画面用の PDF が要る利用者は `bleed` を消す。

## 参考文献

- [ADR 0004](0004-crop-marks-and-bleed.md)
- [golem-project ADR 0004](../../golem-project/adr/0004-font-file-check-per-target.md)
- [golem-cli ADR 0002](../../golem-cli/adr/0002-build-all-targets-by-default.md)
- [golem-driver ADR 0016](../../golem-driver/adr/0016-output-and-layout-diagnostic-codes.md)
- [golem-cli ADR 0006](../../golem-cli/adr/0006-preflight.md)
