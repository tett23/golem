# ADR 0109: プロジェクトの中のプラグインを path で宣言する

ステータス: 採択

## 文脈

プラグインは、`manifest.toml` に配布物の HTTPS の URL を書いて宣言する（[golem-plugin ADR 0002](../golem-plugin/adr/0002-distribution-and-lock.md)）。
ビルドはキャッシュからだけ読み、キャッシュには `golem plugin fetch` か `golem plugin lock` が HTTPS で取ったものだけが入る。

見本のプラグイン（[docs/adr/0106](0106-sample-plugins-in-rust.md)）を作って、手元のプロジェクトで動かそうとすると、この経路しかないことが障害になった。
作ったばかりの `.wasm` を試すには、次の手順を手で行うしかなかった。

1. `.wasm` の SHA-256 を計算する。
2. キャッシュのディレクトリ（XDG の規則で決まる。[`defaultCacheDir`](https://github.com/tett23/golem/blob/668ed3acc8df131ed53fdafe49200b4a8ed05d2d/modules/golem-plugin/src/Golem/Plugin/Lock.hs#L146-L147)）に `<SHA-256>.wasm` として写す。
3. `plugins.lock` に、まだ存在しない URL と、そのハッシュを手で書く。

`plugins.lock` は「処理系だけが書き、手で編集しない」ファイルなので、この手順は [golem-plugin ADR 0002](../golem-plugin/adr/0002-distribution-and-lock.md) の取り決めに反する。
golem-driver のテストも、HTTPS の取得の偽物を使って同じことをしている。
プラグインを作る人が、作るたびにこの手順を踏むことになる。
社内でだけ使うプラグインを、配布せずにリポジトリに置きたい利用者も同じである。

## 実装すること

- `[plugins.<名前>]` に、`url` の代わりに `path` を書けるようにする。`path` はプロジェクトのルートを基準にした `.wasm` のパスで、`url` と `path` の両方か、どちらもないときは G03001 とする。
- `path` の検査は、データのファイル（[docs/adr/0105](0105-plugin-data.md)）と同じく `resolveInRoot` で行う。形の誤りは G03003、ファイルがなければ新しいエラー G06104 とする。
- `path` のプラグインは、`plugins.lock` にもキャッシュにも入れない。データと同じく、プロジェクトの入力としてリポジトリの版管理で固定される。`golem plugin lock` と `golem plugin fetch` は `path` のプラグインを飛ばす。
- LSP は、`path` のファイルを `@table` のファイルと同じく監視し、変われば読み込み直す。

## 実装しないこと

- プロジェクトの外の `.wasm` を指すこと。
- `path` のプラグインのソースを指して、Golem がビルドすること。

## テスト設計

- `path` のプラグインのコマンドが呼べること。`plugins.lock` がなくてもよいこと。
- `url` と `path` の両方、どちらもないときの G03001、ルートの外の G03003、ファイルがないときの G06104。
- `golem plugin lock` が `path` のプラグインを `plugins.lock` に書かないこと。

## トレードオフ

`path` を許すと、配布物のハッシュの固定（[golem-plugin ADR 0002](../golem-plugin/adr/0002-distribution-and-lock.md)）を通らないプラグインが動く。
ただし、`path` のファイルはプロジェクトの中にあり、原稿と同じくリポジトリで差分が見える。
外から取ってくるものを固定するという [golem-plugin ADR 0002](../golem-plugin/adr/0002-distribution-and-lock.md) の目的は損なわれない。

## 参考文献

なし
