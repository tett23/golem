# ADR 0034: unsafePerformIO を減らし、残すものを検査で固定する

ステータス: 提案

## 文脈

Golem は、IO を処理の両端に寄せ、そのあいだを純粋な関数でつなぐ（[docs/adr/0002](0002-determinism.md)、開発者向けマニュアルの「決定性と純粋性」の章）。
カーネルの中には、C のライブラリの呼び出しとメモ化のために `unsafePerformIO` が置いてある。
[golem-font ADR 0001](../golem-font/adr/0001-shaping-and-metrics.md) は、FFI の呼び出しを純粋な関数として見えるように包むと決めた。
[golem-plugin ADR 0001](../golem-plugin/adr/0001-wasm-host-and-abi.md) の `Golem.Plugin` も同じ形で wasmtime を包んでいる。

2026-10-17 の時点で、`unsafePerformIO` は次の 12 か所にある（`unsafeDupablePerformIO`、`unsafeInterleaveIO`、`inlinePerformIO` は使っていない）。

| モジュール | 関数 | 呼び出す側 |
| --- | --- | --- |
| `Golem.Font` | `loadFont` | `Golem.Driver.Fonts` の IO（フォントのファイルを読んだ直後） |
| `Golem.Font` | `fontEmBoxCentral` | 組版（純粋） |
| `Golem.Font` | `shapeUnits` | 組版（純粋） |
| `Golem.Font` | `glyphVerticalOrigin` | 組版（純粋） |
| `Golem.Font` | `glyphMetrics` | 組版と PDF の書体の記述（純粋） |
| `Golem.Font` | `glyphCid` | 組版と PDF の書体の記述（純粋） |
| `Golem.Font` | `subsetFont` | PDF の書体の記述（純粋） |
| `Golem.Plugin` | `watToWasm` | テストだけ |
| `Golem.Plugin` | `loadPluginWith` | `Golem.Driver.Plugins` の IO（キャッシュを読んだ直後） |
| `Golem.Plugin` | `callMode` | `loadPluginWith`、`invokeRaw`（評価器から呼ぶプラグインのコマンドとフィルタ） |
| `Golem.Driver.Fonts` | `memo`（二か所） | 字の送りと二字のカーニングのメモ化 |

`unsafePerformIO` は型の検査を黙らせるだけで、純粋性を作りはしない。
包んだ関数を純粋と呼べるかどうかは、レビューで三つの条件（結果が引数だけで決まる、作用が観察できない、境界の値が環境に依存しない）を確かめるしかない。
このうち、呼び出す側がもともと IO の中にあるもの（`loadFont`、`loadPluginWith`、`watToWasm`）と、値がフォントを開いた時点で決まるもの（`fontEmBoxCentral`、`glyphCid`）は、包む理由がない。
PDF の書体の記述（`subsetFont`）は、組版の後に一度だけ呼ぶので、書く側の IO のエッジに移せる。
メモ化（`memo`）は、`IORef` の表を `unsafePerformIO` で作って書き換えている。
遅延評価の木（いわゆる memo trie）を使えば、同じことを状態なしで書ける。

残りのもの（`shapeUnits`、`glyphVerticalOrigin`、`glyphMetrics`、プラグインの呼び出し）は、純粋な組版と評価器の内側から、組版の進み具合に応じて呼ぶ。
何を問い合わせるかは組版が進むまでわからないので、IO のエッジで先に計算しておくことはできない。
組版と評価器を IO にすれば外せるが、それは純粋なカーネルという構成そのものを捨てることになる。

## 実装すること

### IO のエッジに移すもの

- golem-font の `loadFont` を `ByteString -> IO (Either FontError Font)` にする。
  - フォントを開く処理（`golem_font_open` と、upem、fsType、範囲、PostScript 名、ROS の読み取り）は今と同じである。
  - `fontEmBoxCentral` は、`loadFont` の中で一度だけ求め、`Font` のフィールドとして持つ。型は `Font -> Int` のまま変えない。
  - CID-keyed CFF のフォントでは、`loadFont` の中ですべてのグリフの CID を読み、表として持つ。`glyphCid` は表を引く純粋な関数になる。それ以外のフォントでは、今と同じくグリフ ID をそのまま返す（表を作らない）。範囲の外のグリフ ID も、今の C の関数と同じくグリフ ID をそのまま返す。
- golem-font の `subsetFont` を `Font -> [Int] -> IO (Maybe ByteString)` にする。
  - golem-driver の `LoadedFonts` の `lfEmbed` を `Int -> Bool -> [(Int, Text)] -> IO P.Font` にする。
  - `writeDocumentView` は、書体ごとに使ったグリフの表と、埋め込んだ書体から PDF と写しを作る関数の組を返す純粋な関数にする。`renderPdfView` が、そのあいだで `lfEmbed` を IO として呼ぶ。
- golem-plugin の `loadPluginWith` と `loadPlugin` を `... -> ByteString -> IO (Either PluginError Plugin)` に、`watToWasm` を `Text -> IO (Either Text ByteString)` にする。
  - `loadPluginWith` の中の ABI の版と `golem_describe` の呼び出しも IO のまま行う。
  - golem-driver の `loadPlugins` は、もともと IO なので、型を変えない。

### 状態なしのメモ化

- golem-driver に `Golem.Driver.Memo` を足し、`memoWith :: (k -> [Int]) -> ([Int] -> k) -> (k -> v) -> k -> v` を置く。
  - キーを非負の小さな整数の列に符号化し、その列ごとの結果を、遅延評価の 8 分木（深さ 8）の連なり（trie）の葉に評価していない式として持つ。木は、引いた経路の節点だけが作られる。
  - 同じキーを二度引くと、評価済みの葉が返る。表を書き換える処理がないので、`IORef` も `unsafePerformIO` も要らない。
  - 符号化の値が範囲（0 以上 2^24 未満）を外れるキーは、覚えずにそのまま計算する。
- `Golem.Driver.Fonts` の `memo` を `memoWith` に置き換え、`Shaping` と文字の組を符号化する。

### 残すもの

次の三つと一つは `unsafePerformIO` で包んだまま残す。

- `Golem.Font` の `shapeUnits`、`glyphVerticalOrigin`、`glyphMetrics`：組版の内側から、問い合わせが決まるたびに呼ぶ。C の側は、フォントを開いた後は結果に効く状態を持たない。
- `Golem.Plugin` の `invokeRaw`（`callMode` の IO 版を包む）：評価器の内側から呼ぶ。呼び出しごとに新しいストアとインスタンスを作るので、呼び出しのあいだに状態が残らない。

`callMode` は IO の関数にし、`loadPluginWith` は IO の中からそれを呼ぶ。`invokeRaw` だけがそれを `unsafePerformIO` で包む。

### 検査

- `scripts/ci/unsafe-io.sh` を足す。`modules/*/src` と `modules/*/app` の Haskell のソースから、`unsafePerformIO`、`unsafeDupablePerformIO`、`unsafeInterleaveIO`、`unsafeInterleaveST`、`unsafeIOToST`、`inlinePerformIO`、`accursedUnutterablePerformIO` を使うトップレベルの定義を `ファイル:定義名` の形で列挙し、`scripts/ci/unsafe-io-allowed.txt` と比べる。
  - 違いがあれば、増えたものと減ったものを標準エラーに書き、終了コード 1 で終わる。
  - import の行とコメントの行は数えない。
  - 許す一覧の各行には、残す理由を `#` の後に書く。
- CI の、`incomplete-patterns.sh` を実行するジョブで、同じく実行する。
- `scripts/ci/test.sh` に、この検査のテストを足す。

### ドキュメント

- 開発者向けマニュアルの「決定性と純粋性」の章の「カーネルの中に置いた IO」の節を、上の三つと一つだけを包んでいる形に書き直す。メモ化の節を、遅延評価の trie の説明に書き直す。「変更するときの点検」に、`unsafe-io.sh` の一覧を変えるときの手順を足す。
- 開発者向けマニュアルの「CI のジョブ」の章に、`unsafe-io.sh` を足す。

## 実装しないこと

- `shapeUnits`、`glyphVerticalOrigin`、`glyphMetrics`、プラグインの呼び出しを IO にすること。組版（golem-layout、golem-driver の `buildFlow` の内側）と評価器（golem-eval）を IO にすることになり、純粋なカーネルという構成を変える。
- フォントを開いた時点で全グリフの `glyphMetrics` と `glyphVerticalOrigin` を読んでおくこと。CJK のフォントは 6 万を超えるグリフを持ち、グリフの輪郭を読むので、開く時間とメモリが組版で使う分よりはるかに大きくなる。
- Template Haskell の `runIO` の変更。コンパイルの時点の IO であり、実行の時点の純粋性には関わらない。
- 出力の変更。この ADR の前後で、すべての出力のバイト列は変わらない。

## テスト設計

- `scripts/ci/test.sh` に次を足す。
  - リポジトリそのものに対して `unsafe-io.sh` が終了コード 0 で終わる。
  - 一時ディレクトリに作った小さな `modules/x/src` で、許す一覧にない `unsafePerformIO` を一つ足すと終了コード 1 で終わり、標準エラーにその `ファイル:定義名` を書く。
  - 許す一覧にあるのにソースにない定義があると、終了コード 1 で終わる。
  - import の行とコメントの行の `unsafePerformIO` は数えない。
- golem-driver のテストに `Golem.Driver.Memo` のテストを足す。
  - `memoWith` で包んだ関数は、包む前の関数と同じ値を返す（0 から 5000 までと、範囲の端のキー）。
  - 包んだ関数が評価された回数を数え（テストの中だけで `IORef` を使う）、同じキーを二度引いても一度しか評価されないことを確かめる。範囲の外のキーは、引くたびに評価される。
  - 引かないキーの値は評価されない（評価すると例外になる関数を包んでも、引いたキーの値だけが求まる）。
  - `Shaping` と文字の組の符号化が、復号で元に戻る。
- golem-font の既存のテスト（`loadFont`、`subsetFont`、`glyphCid`、`fontEmBoxCentral`）を IO の型に合わせ、同じ値を確かめる。
- golem-plugin の既存のテストを IO の型に合わせ、同じ値を確かめる。
- 出力が変わらないことを、次で確かめる。
  - 変更の前と後の `golem` で `scripts/determinism.sh` を実行し（`GOLEM_MANUAL_COMMIT` と `GOLEM_MANUAL_TAG` を固定する）、SHA-256 の一覧が一致する。
  - 二つのマニュアルが診断なしで組める。
- 速度が落ちていないことを、開発者向けマニュアルの PDF を組む時間で、変更の前と後を比べて確かめる。

## トレードオフ

- `loadFont` と `loadPlugin` を純粋な文脈から呼べなくなる。今の呼び出し元はすべて IO の中にあるので、困るのはテストだけである。
- `glyphCid` の表は、CID-keyed のフォント一つにつき、グリフの数だけの整数（6 万グリフで約 500 KB）を持つ。開く時間には、グリフの数だけの C の呼び出しが加わる。
- 遅延評価の trie は、`IORef` の `Map` より節点の数が多く、メモリを多く使う。引くたびの比較の回数は、`Map` の比較の回数と同じ程度である。
  開発者向けマニュアルの PDF を組んだ計測では、変更の前に対して、16 分木で最大メモリが約 1 割増え、8 分木でほぼ同じ（ユーザー時間は約 3% 増え）、4 分木でユーザー時間が約 5% 増えた。8 分木を選ぶ。
  メモ化をまったくしないと、ユーザー時間は約 13% 増えた。
- 残す `unsafePerformIO` の正しさは、これまでどおりレビューで確かめる。`unsafe-io.sh` は、増えたことを知らせるだけで、正しさは確かめない。

## 参考文献

- Conal Elliott, "Elegant memoization with functional memo tries", 2008. http://conal.net/blog/posts/elegant-memoization-with-functional-memo-tries
- Ralf Hinze, "Generalizing generalized tries", Journal of Functional Programming 10(4), 2000.
- GHC の `System.IO.Unsafe` のドキュメント。https://hackage.haskell.org/package/base/docs/System-IO-Unsafe.html
