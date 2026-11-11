# ADR 0337: check と HTML ビルドの diagnostics を一つのテストプロセスで調べる

ステータス: 採択

## 文脈

[Golem ADR 0323](0323-heading-level-diagnostic-occurrences.md) は、章の入れ子や import の共有を含む六つの構成で、上限超過の見出しを一度ずつ報告できるかを調べる。
各入力で `golem check` と `golem build --target html` を起動すると、六構成に対して十二回の子プロセス起動が要る。
パーサーの後で diagnostics を組み合わせる処理は、どちらのコマンドも golem-driver の `build` を使う。

## 実装すること

CLI の内部に、プロジェクトのルート、check または出力先を指定する build、プロファイル、トンボ、notice の抑制、詳細表示を受け取り、`BuildResult` を返す関数を置く。
check は従来どおり全ターゲットを指定し、`optCheckOnly` を有効にする。
build は指定されたターゲット、指定がなければ全ターゲットを渡す。
テストと CLI はこの関数と、diagnostics を JSON にして終了コードを決める関数を共有する。
各ケースは一時ディレクトリを明示して渡す。

## 実装しないこと

利用者向けのコマンド、引数、公開ライブラリは増やさない。
ヘルプ、引数の解析、標準エラー出力の割り当てを検査する既存の CLI テストは引き続き実行ファイルを起動する。

## 不変条件

1. C1。六構成の各モードについて、テストが起動する golem 子プロセスは 0 個である。
2. H1。各モードで G01012 のファイルと位置の列が原稿から定めた期待値と一致する。diagnostics を並べ替えたり、重複を取り除いたりして比較しない。
3. H2。六構成のいずれでも、check と HTML ビルドで G01012 の件数、位置、順序が一致する。

| 入力 | 各モードの G01012 の件数 | golem 子プロセスの起動 |
| --- | ---: | ---: |
| 同じ 2 箇所を持つ単独の章、入れ子にした章、二度指定した章 | 各 2 | 0 |
| 2 箇所を持つ章と 1 箇所を持つ章 | 3 | 0 |
| 二章から共通の原稿を import | 1 | 0 |
| 同じ原稿を章と import 先の両方で読む | 1 | 0 |

## テスト設計

各ケースを golem-cli の Cabal テストに置く。
JSON をデコードし、G01012 ごとにファイル、開始と終了のバイト位置、行、列を独立した期待値と照合する。
たとえば絵文字を含む試料の最初の不正な見出しについて、7 個目の `#` からのバイト区間はバイト 23 から 29 の直前までとする。
PATH の先頭に、呼ばれたら記録を残す golem を置き、テスト実行ファイルを起動して C1 を確かめる。

試作の `cabal test --offline -j4 golem-cli:test:golem-cli-test --test-options='-p heading-limit' --test-show-details=direct` で 12 件が通った。
PATH を差し替えた検査でも同じ 12 件が通り、golem の呼び出しは 0 回だった。
再現手順と差分は `experiments/heading-in-process/README.md` にある。

## トレードオフ

テストから二度とも driver を直接呼ぶだけでは、CLI のターゲット選択の変更とテストの設定が別々に変わりうる。
内部関数を共有する案なら、CLI が使う設定、diagnostics の収集、JSON への変換を通せる。
引数パーサー、標準出力と標準エラー出力の書き分け、プロセスの終了は別の検査が受け持つ。

## 参考文献

- [試作前の check と build の実装](https://github.com/tett23/golem/blob/706e5888fb1d63a53da68a0e7223b76f8441d2f9/modules/golem-cli/app/Main.hs#L244-L249)
- [試作前の JSON の出力と終了コード](https://github.com/tett23/golem/blob/706e5888fb1d63a53da68a0e7223b76f8441d2f9/modules/golem-cli/app/Main.hs#L290-L297)
