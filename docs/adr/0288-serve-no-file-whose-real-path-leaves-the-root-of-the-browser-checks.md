# ADR 0288: ブラウザーの検査のサーバーは、実のパスが root の外に出るファイルを返さない

ステータス: 採択（未実装）

## 文脈

[ADR 0234](0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md) のブラウザーの検査は、`scripts/browser/serve.mjs` のサーバーで、検査するファイルを 127.0.0.1 の短命のポートから配る。
ヘッダーの注釈は「root を出るパスは 404」と約束する（[`serve.mjs#L10-L11`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/scripts/browser/serve.mjs#L10-L11)）。

`fileOf` は、URL のパスを `decodeURIComponent` し、`normalize` し、先頭の区切りを除き、`..` で始まれば `null` を返す（[`serve.mjs#L40-L51`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/scripts/browser/serve.mjs#L40-L51)）。
文字列としてのパスは、これで root の中に収まる。
ただ、ファイルを開く前に実のパスを求めないので、root の下に外を指すシンボリックリンクがあれば、`stat` と `readFile` はリンクをたどり、外のファイルを 200 で返す（[`serve.mjs#L64-L65`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/scripts/browser/serve.mjs#L64-L65)）。
[2026-11-09 の監査](../audits/2026-11-09-security-audit.md) の B-01（情報）は、これを関数の水準で再現し、注釈の約束と実装がずれていると記録した。

今の危険は小さい。
root は、CI が `cp -R` で組む fixture、マニュアルの HTML、`mkdtemp` の一時ディレクトリで、リンクを置けるのはリポジトリのコミットだけである。
リポジトリが追跡するシンボリックリンクは、`modules/golem-driver/VERSION` と `modules/golem-driver/diagnostics.md` の二つで、どちらも root の材料にならない（2026-11-10 に `git ls-tree -r` のモード 120000 で確かめた）。
それでも、サーバーが約束を守るかどうかは、置かれるファイルの性質ではなくサーバー自身で決まるほうがよい。
将来 fixture にリンクが入ったとき、検査がリポジトリの外のファイルを読んで通ることはありうる。

## 実装すること

1. `serve.mjs` に、ファイルの実のパスを求める段を足す。`fileOf` が返したパスを `fs.promises.realpath` で解決し、root の実のパス（サーバーの起動のときに一度だけ求める）と同じか、その下にあるときだけ返す。それ以外は 404 とする。root の中を指すリンクは、今のとおり返す。
2. 実のパスを求められないとき（リンクの先がない、権限がない）は 404 とする。
3. ヘッダーの注釈の「root を出るパス」を「実のパスが root を出るファイル」に改め、この ADR へのリンクを書く。
4. 仕様書のブラウザーの検査の節に、サーバーが実のパスで root の外のファイルを返さないことを書く。
5. [docs/roadmap.md](../roadmap.md) の「2026-11-09 の監査の情報の所見」の項目から、B-01 を外す。

## 実装しないこと

- 監査の I-03（`scripts/wasm/run.mjs` がシンボリックリンクをたどること）。roadmap の項目に入っておらず、`run.mjs` は利用者のホストの例でもあるので、扱いを別に決める。
- B-02（CDP のブラウザーを `--no-sandbox` で起動すること）。roadmap の項目に入っていない。
- `fileOf` の文字列の検査を外すこと。実のパスの検査の前の、ファイルシステムに触れない一段目として残す。

## 不変条件

root の実のパスを R、URL のパス u に対して `fileOf` が返すパスを f(u)、その実のパスを real(f(u)) とする。

- **S1 外を返さない**：応答が 200 なら、real(f(u)) は R か、R の下にある。
- **S2 中は今のとおり**：u が `pages` にない、リンクを含まない root の下の通常のファイルを指すなら、応答は 200 で、本文はそのファイルのバイト列である。
- **S3 中を指すリンクは返す**：root の下のリンクが root の下の通常のファイルを指すなら、応答は 200 である。
- **S4 `pages` が先**：u が `pages` にあれば、ファイルシステムによらず、その内容を返す。

境界の入力：

| 入力 | 期待 |
| --- | --- |
| root の下の通常のファイル | 200（S2） |
| root の下の、root の下のファイルへのリンク | 200（S3） |
| root の下の、root の外のファイルへのリンク | 404（S1） |
| root の下の、root の外のディレクトリへのリンクの中のファイル | 404（S1） |
| 先のないリンク | 404 |
| root そのものがリンクで、その先の下のファイル | 200（R は root の実のパス） |
| root と同じ名前で始まる隣のディレクトリ（`/tmp/r` に対する `/tmp/r2`） | 404（S1。名前の前方一致で判定しない） |
| `pages` にあるパスと同じ名前の、外へのリンク | `pages` の内容（S4） |

## テスト設計

テストを先に書き、今の実装で失敗することを確かめてから実装する。
テストの名前には、S1 から S4 の番号を入れる。

- `scripts/browser/test/unit.test.mjs` に、`mkdtemp` で root と外のディレクトリを作り、境界の入力の表の各行のリンクを置いて確かめるテストを足す。サーバーの bind の要らない形にするため、実のパスを求めてファイルを返すかを決める関数（たとえば `servedFile(root, urlPath)`）を `serve.mjs` から公開し、その関数で確かめる。
- bind の要るテストとして、`browser.test.mjs` の既存の `serve` の起動に、外へのリンクを一つ足し、404 であることを確かめる。
- 今の実装では、外へのリンクの行（S1）が落ちる。

## トレードオフ

ファイルを返すたびに `realpath` を一度呼ぶ。
検査が配るファイルは数百で、時間は増えないと見込む。

## メンテナーが決めること

1. **外へのリンクの扱い**：推奨は 404 とすることである。ほかの「root を出るパス」と同じ扱いになる。
   - 退けた案の一つは、シンボリックリンクをすべて拒むことである。root の中を指すリンクまで拒むと、将来 fixture が中のリンクを使ったときに検査が壊れる。
   - もう一つは、注釈を実装に合わせて「リンクはたどる」と改めることである。サーバーが外のファイルを返しうるという性質を、置かれるファイルの側で保つことになる。

## 決めたことの記録

2026-11-10 に、tett23 が「メンテナーが決めること」のすべてを推奨のとおりに決めた。

1. 実のパスが root の外を指すリンクは、ほかの「root を出るパス」と同じく 404 とする。

採択にあたり、ソースコードへのリンクを `main` の `9acc137a`（[ADR 0281](0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md) の実装のマージ）に合わせた。

## 参考文献

- [2026-11-09 の監査](../audits/2026-11-09-security-audit.md)（B-01）
- [ADR 0234](0234-check-html-and-golem-wasm-in-a-pinned-headless-chromium.md)
- [`scripts/browser/serve.mjs`](https://github.com/tett23/golem/blob/9acc137aeab273aec90561d5a8bfa4055fb6fc53/scripts/browser/serve.mjs)
- Node.js の `fs.promises.realpath` の文書
