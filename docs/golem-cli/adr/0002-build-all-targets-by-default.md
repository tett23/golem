# ADR 0002: --target を省いた golem build はすべてのターゲットを作る

ステータス: 採択

## 文脈

`golem build` は、`--target` を省くと、マニフェストの `[targets.*]` に書いたターゲットだけを出力している。
この既定は [golem-driver ADR 0001](../../golem-driver/adr/0001-build-pipeline.md) の「マニフェストと `--target` で指定されたターゲットごとに出力を作る」に従ったもので、仕様書のコマンドの表にも「ターゲットの既定はマニフェスト」と書いてある。

この既定では、何が出力されるかを知るためにマニフェストを読まなければならない。
`golem build` と打てば、Golem が作れる出力（HTML、EPUB、プレーンテキスト、PDF）がすべてそろうほうが、コマンドの意味が単純になる。

一方で、ターゲットによっては、マニフェストの設定がないと出力が決まらない。

- プレーンテキストは、`[targets.text]` の `variants` で縦書きと横書きのどちらを作るかを決める。`variants` を省くと両方を作るが、`[targets.text]` そのものがなければ、今は一つもファイルを作らない。
- PDF は、`style.toml` の `[fonts.body]` にフォントがなければエラーになる。

## 実装すること

### 既定のターゲット

- `golem build` で `--target` を一つも指定しなかった場合は、HTML、EPUB、プレーンテキスト、PDF の四つをこの順で作る。マニフェストの `[targets.*]` の有無は見ない。
- `--target` を指定した場合は、これまでどおり指定したターゲットだけを作る。
- 四つのターゲットの一覧は golem-driver の `allTargets` として公開し、golem-cli はそれを使う。golem-driver の `build` に `optTargets = Nothing` を渡したときの挙動（マニフェストのターゲット）は変えない。

### 設定のないターゲット

- `[targets.text]` がないときは、`variants` を省いた `[targets.text]` と同じく、縦書きと横書きの両方を作る。
- `[targets.epub]` がないときは、これまでどおり、本の識別子にマニフェストの `id` を使う。
- PDF のフォントがないときは、これまでどおりエラーの診断を出す。ほかのターゲットの出力は書き、終了コードは 1 になる。

### ドキュメントとスクリプト

- 仕様書のコマンドの表と README の `golem build` の説明を、既定がすべてのターゲットであることに直す。
- `scripts/determinism.sh` は、フォントを置いていないプロジェクトを `--target` なしでビルドしている。PDF のエラーで止まらないよう、`--target html --target epub --target text` を明示する。

## 実装しないこと

- `--target all` のような、すべてを表す値。`--target` を省けば同じになるので加えない。
- `[targets.*]` の意味の変更。ISBN とプレーンテキストの `variants` の設定の置き場所として残す。ターゲットが一つもないマニフェストを拒む検査（G0301）も変えない。
- フォントのない PDF を警告にして飛ばすこと。設定の不足を、終了コード 0 のまま見逃させないためである。
- `golem new` の雛形の変更。雛形はフォントを含まないので、雛形のまま `golem build` すると PDF のエラーで終了コードが 1 になる。

## テスト設計

golem-driver のテストに加える。

- `allTargets` が HTML、EPUB、プレーンテキスト、PDF の順の四つであること。
- `[targets.*]` に HTML しか書いていないプロジェクトを `optTargets = Just allTargets` でビルドすると、`build/html`、`build/epub`、`build/text/vertical`、`build/text/horizontal` に出力が書かれること。フォントのない PDF はエラーの診断になり、それ以外の出力は書かれていること。
- `[targets.text]` のないプロジェクトでプレーンテキストを作ると、`build/text/vertical` と `build/text/horizontal` が作られること。
- `[targets.text]` に `variants = ["vertical"]` があるときは、これまでどおり `build/text/vertical` だけが作られること。
- `optTargets = Nothing` の挙動が変わらないことは、既存のテストで確かめる。

golem-cli はテストを持たないので、`--target` を省いたときに `allTargets` を渡すことは、実装の後に `golem build` を実行して確かめる。

## トレードオフ

`golem build` の既定がフォントの設定に依存するようになる。
フォントを設定していないプロジェクトでは、`--target` なしのビルドが常に終了コード 1 になり、CI で使うには `--target` を明示する必要がある。
その代わり、既定の出力をマニフェストを読まずに言い当てられる。

`[targets.*]` は、出力するかどうかを決めなくなり、ターゲットごとの設定だけを持つ。
節の名前と役割が少しずれるが、名前を変えるとすべてのマニフェストの書き換えが必要になるので、名前は残す。
