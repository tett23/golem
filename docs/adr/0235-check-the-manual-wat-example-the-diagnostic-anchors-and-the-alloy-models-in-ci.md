# ADR 0235: マニュアルの wat の例、diagnostic の説明への節のリンク、Alloy のモデルを CI で確かめる

ステータス: 採択（未実装）

## 文脈

[docs/roadmap.md](../roadmap.md) の「手で確かめる項目」のうち、次の三つは文書の中のものを確かめる。

- **開発者向けのマニュアルの例**（[ADR 0024](0024-manual-audiences-and-policy.md)）：プラグインの wat の例を、実際に組んで動かしていない。
- **diagnostic の説明へのリンク**（[golem-cli ADR 0005](../golem-cli/adr/0005-explain-diagnostic-codes.md)）：GitHub の上で `docs/diagnostics.md#g01017` を開き、G01017 の節に移ることを確かめていない。
- **規則の Alloy のモデル**（[ADR 0204](0204-pagination-invariants-by-exhaustive-small-inputs.md)、[ADR 0208](0208-widen-lightweight-formal-methods.md) の 5）：モデルは CI で走らせないので、規則を変える ADR で、手で直して走らせ直す。

三つとも、確かめる手段がすでにリポジトリか GitHub にある。

### wat の例は、golem-plugin がそのまま読める

開発者のマニュアルの「プラグイン」の章（`manual-dev/part1/05-plugins.gm` の 310 行から）は、受け取った文書をそのまま返すフィルタ `same` だけを持つプラグインを、wat のコードブロックで示している。
本文は、golem-plugin のテストの `identity.wat` から、コマンドの部分を除いて整形し直したものだと書いている。
golem-plugin は、wasmtime の `wasmtime_wat2wasm` を `watToWasm` として持ち、テストは `identity.wat` を読み込んで `applyFilter p "same" doc` が文書を変えないことを確かめている（[`modules/golem-plugin/test/Main.hs` の 163 行から 166 行](https://github.com/tett23/golem/blob/683744442737c02e86e700e26b6f1b9b95277aef/modules/golem-plugin/test/Main.hs#L163-L166)）。
マニュアルのコードブロックを切り出して同じテストに渡せば、例が動くことを、新しい道具なしに毎回確かめられる。

### GitHub の節のリンクは、GitHub の API で描いた HTML に出る

`golem explain` は、説明の URL を `https://github.com/tett23/golem/blob/main/docs/diagnostics.md#` にコードの小文字を続けて作る（[`modules/golem-driver/src/Golem/Driver/Explain.hs` の 53 行](https://github.com/tett23/golem/blob/683744442737c02e86e700e26b6f1b9b95277aef/modules/golem-driver/src/Golem/Driver/Explain.hs#L53)）。
この URL で節に移るかは、GitHub が Markdown を描いた HTML に、その見出しの `id` があるかで決まる。
GitHub は見出しの `id` に `user-content-` を前に付け、ページのスクリプトが `#g01017` を `user-content-g01017` に結び付ける。

2026-11-08 に、`gh api repos/tett23/golem/contents/docs/diagnostics.md -H 'Accept: application/vnd.github.html'` で、`main` の `docs/diagnostics.md` を GitHub が描いた HTML を取った。
`id="user-content-g01017"` があり、`user-content-g` で始まる `id` は 310 個あった。
`docs/diagnostics.md` の `## G` で始まる見出しも 310 個である。

この確かめ方は、ブラウザで開いて押すことと同じではない。
ページのスクリプトが `#g01017` から `user-content-g01017` に移る部分は、GitHub のすべての Markdown のページに共通の振る舞いであり、Golem の変更で壊れることはない。
Golem の変更で壊れうるのは、見出しの書き方と、ファイルの大きさである。
`docs/diagnostics.md` は 2026-11-08 に 498,077 バイトあり、diagnostic のコードを足すたびに大きくなる。
GitHub が描く Markdown のファイルの大きさには上限があり、超えると、ファイルは描かれず、節のリンクはどれも働かなくなる。
上限の正確な値は確かめていないが、API で描いた HTML に `id` があるかを毎回見れば、超えたときにわかる。

### Alloy のモデルは、CI で走らせられるが重い

改ページのモデル（`docs/golem-layout/models/pagination.als`）の README は、Alloy 6.2.0 の CLI で走らせ、各コマンドの解の有無を表にしている（[docs/golem-layout/models/README.md](../golem-layout/models/README.md)）。
2026-11-08 に、この ADR を書いた手元の macOS（Apple Silicon）で、`alloy6 exec -q -n -t text -c '*'` ですべてのコマンドを一度に走らせると、7 分 26 秒かかった。
解が出たのは 8 個のコマンドで、README の表で「なし」でない 8 個（`someFits`、`noneMeetsAll`、`greedyOrphan`、`greedyWidow`、`greedyKeepHeading`、`tallFigure`、`strictAfterHeadings`、`decidedSome`）と同じだった。
一つのプロセスがほぼ一つのコアで走っていた（CPU の利用は 83%）ので、コマンドごとにプロセスを分ければ、ランナーの四つのコアに分けられる。
それでも、プルリクエストの 5 分の中には収まらない見込みが高い。

Alloy の配布物のライセンスは、確かめきれていない。
GitHub の AlloyTools/org.alloytools.alloy の `LICENSE` は、先頭に「まだ有効でない、今のコードは MIT のもとにある」という趣旨の注を置き、その後に Apache License 2.0 の本文を続けている。
MIT と Apache 2.0 のどちらであっても CI で走らせることに妨げはないが、実装の前に配布物の jar のライセンスの文書を読む。

ロードマップのこの項目には、もう一つ、手で確かめることではない部分がある。
「規則を足すか変える ADR は、モデルを直して走らせ直す」と「三つ以上のほかの規則と端で重なる ADR は、新しくモデルを書く」は、ADR を書く人の決まりであり、確かめる項目ではない。

## 実装すること

### 1. wat の例のテスト

golem-plugin のテストに、`manual-dev/part1/05-plugins.gm` の ```` ```wat ```` のコードブロックを切り出すテストを足す。

- コードブロックが一つだけあること（二つ以上か、ないときは、テストを直すように失敗する）。
- 切り出した文字列が `watToWasm` で変換でき、`loadPlugin` で読めること。
- `same` のフィルタが、`identity.wat` のテストと同じ文書を変えずに返すこと。

ファイルの位置は、テストのパッケージのディレクトリからの相対のパスで書き、golem-plugin の `extra-source-files` には加えない。
パッケージの依存は変えない。

### 2. GitHub の節のリンクの検査

`scripts/ci/github-anchors.sh` を足す。

- `gh api repos/{owner}/{repo}/contents/docs/diagnostics.md?ref=<コミット> -H 'Accept: application/vnd.github.html'` で描いた HTML を取る。
- `docs/diagnostics.md` の `## G` で始まる見出しのコードのそれぞれについて、`id="user-content-<小文字のコード>"` が HTML にあることを確かめる。
- ないコードを書いて、終了コード 1 で終わる。

`docs.yml` に、`docs/diagnostics.md` か `Explain.hs` を変えたプルリクエストと、`main` への push で走るジョブを足す。
`GITHUB_TOKEN` は `contents: read` のまま使う。
フォークからのプルリクエストで、そのコミットが API から引けないときは、飛ばしたことを書いて通し、`main` への push で確かめる。

`scripts/ci/test.sh` には、手で作った小さな HTML と見出しの一覧を与えるテストを足し、ネットワークを使わない部分を確かめる。

### 3. Alloy のモデルの検査

`scripts/models/check.sh` を足す。

- `docs/*/models/*.als` のそれぞれについて、同じディレクトリの `expected.txt`（コマンドの名前と、`found` か `none` の組）を読む。
- コマンドごとに `java -jar <Alloy の jar> exec -q -n -t text -c <コマンド> -o - <モデル>` を、コアの数まで並べて走らせ、`---Trace---` の有無を `found` と `none` に直して `expected.txt` と比べる。
- 違うコマンドを書いて、終了コード 1 で終わる。

`expected.txt` は、README の「結果」の表の、スコープ 5 での解の有無から作る。
README の表の最も小さいスコープは、この検査の範囲に入れない（スコープを 2 から上げて走らせると、時間が数倍になる）。

Alloy の jar は、GitHub の AlloyTools のリリースから、版（6.2.0）と SHA-256 をスクリプトに書いて取り、検査してから使う。

`.github/workflows/models.yml` を足す。

- `docs/*/models/` を変えたプルリクエストと、`main` への push と、`schedule` の週に一度で走る。
- `timeout-minutes` は 30 にする。

### 4. ロードマップと文書

- 「開発者向けのマニュアルの例」を外す。
- 「diagnostic の説明へのリンク」を外す。
- 「規則の Alloy のモデル」を、手で確かめる項目から外す。モデルを走らせることは 3 が行う。モデルを直す決まりと、新しくモデルを書く決まりは、CONTRIBUTING.md の ADR の節に移す。
- `docs/golem-layout/models/README.md` の「CI では走らせない」を、3 の検査を書く文に改め、`expected.txt` の作り方を書く。
- CONTRIBUTING.md の GitHub Actions の節に、`models.yml` が 5 分の方針の例外であることを書く（「メンテナーが決めること」の 3）。

## 実装しないこと

- ブラウザで GitHub のページを開いて、節に移ることを確かめること。移る仕組みは GitHub のページに共通で、Golem の変更が届かない。
- `docs/diagnostics.md` を分けること。上限に近づいたことが 2 の検査でわかってから、別の ADR で決める。
- Alloy のモデルの最も小さい例を CI で探し直すこと。
- モデルのない範囲に新しくモデルを書くこと。

## 不変条件

| 番号 | 不変条件 |
| --- | --- |
| I1 | 開発者のマニュアルの wat の例は、golem-plugin が読み込めるプラグインであり、`same` は文書を変えない。 |
| I2 | `docs/diagnostics.md` のすべての diagnostic のコードの見出しは、GitHub が描いた HTML に `user-content-<小文字のコード>` の `id` を持つ。 |
| I3 | `main` の Alloy のモデルの各コマンドの解の有無は、`expected.txt` のとおりである。 |

## テスト設計

1 のテストは、先に書いて失敗させる。
失敗させる方法は、マニュアルの wat の例の `golem_describe` の CBOR の長さを一バイト変えた写しをテストの中で作り、`loadPlugin` が失敗することを確かめることである。
写しで失敗しないなら、テストはマニュアルの例を読んでいない。

2 は、`scripts/ci/test.sh` のテストを先に書いて失敗させる。
見出しが三つあり、そのうち一つの `id` を除いた HTML で、除いたコードを書いて失敗すること。
見出しの書き方が `## G01017` でない行（`### G01017` や `## G01017（説明）`）を、コードの見出しとして数えないこと。

3 は、`expected.txt` の一つのコマンドの `found` を `none` に変えた写しで、そのコマンドを書いて失敗することを、実装のプルリクエストで一度走らせて確かめ、結果をプルリクエストの説明に書く。
Alloy を要るので、`scripts/ci/test.sh` には入れない。
`scripts/ci/test.sh` には、Alloy の代わりに決まった出力を書く偽の `java` で、`---Trace---` の有無を数える部分のテストを足す。

## トレードオフ

2 は、GitHub の API の描き方に頼る。
API の描き方が、ブラウザで見る `blob` のページの描き方と違えば、2 は通ってもリンクが働かないことがありうる。
どちらも同じ Markdown の処理系で描かれているはずだが、確かめたのは API の側だけである。

3 は、週に一度とモデルを変えたときにしか走らない。
golem-layout の実装を変えても、モデルは実装を読まないので、走らせる理由がない。
モデルを変えるプルリクエストは、5 分を超えて待つ。
そうしたプルリクエストは、ADR とモデルを一緒に変えるもので、数は少ない。

## メンテナーが決めること

1. **wat の例を確かめる場所**：推奨は、golem-plugin のテストでマニュアルのファイルを読むことである。プラグインの規約を変えたときに、テストと同じプルリクエストで例の誤りがわかる。
   - 退けた案は、`scripts/manual/` のスクリプトで、golem の実行ファイルにプラグインとして読ませることである。golem のプロジェクトを一つ作る手間がかかり、確かめることは同じである。
2. **節のリンクの確かめ方**：推奨は、GitHub の API で描いた HTML を見ることである。GitHub の描き方そのものを確かめられ、上限を超えたこともわかる。
   - 退けた案の一つは、GitHub の見出しの `id` の作り方（小文字にし、記号を除き、空白を `-` にする）をスクリプトで真似ることである。真似が GitHub と同じかは確かめられず、ファイルの大きさの上限もわからない。
   - 二つめは、ヘッドレスのブラウザで `blob` のページを開くことである。GitHub のページは利用の条件と取得の制限があり、CI から開くのに向かない。
3. **Alloy のモデルの頻度**：推奨は、モデルを変えたプルリクエストと週に一度にし、そのプルリクエストを 5 分の方針の例外とすることである。モデルは実装から独立しており、変えたときにだけ結果が変わる。
   - 退けた案の一つは、すべてのプルリクエストで走らせることである。5 分に収まらない。
   - 二つめは、手で走らせることを続けることである。Alloy の版を上げたときや、README の表を書き直したときに、表と実際の結果がずれても気づかない。
4. **Alloy の決まりの置き場所**：推奨は、モデルを直す決まりと新しく書く決まりを CONTRIBUTING.md に移すことである。手で確かめる項目は、確かめたら消す一覧であり、ずっと続く決まりを置くと、消せない項目になる。

## 決めたことの記録

- **「メンテナーが決めること」のすべて**（2026-11-08、メンテナー）：どれも推奨のとおりとした。

## 参考文献

- GitHub Docs, REST API endpoints for repository contents（`application/vnd.github.html`）, https://docs.github.com/en/rest/repos/contents
- Alloy 6, https://alloytools.org/
- AlloyTools/org.alloytools.alloy, https://github.com/AlloyTools/org.alloytools.alloy
