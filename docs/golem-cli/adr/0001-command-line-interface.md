# ADR 0001: コマンドラインのインターフェース

ステータス: 採択→`golem build` と `golem check` の `--marks` は[golem-pdf ADR 0004](../../golem-pdf/adr/0004-crop-marks-and-bleed.md)、`golem preflight` は[ADR 0006](0006-preflight.md)、`golem inspect` の診断、対象、表示の形は [ADR 0007](0007-inspect-output.md)

## 文脈

Golem の操作はすべて CLI で行う。
コマンドの一覧、診断の出力の形式、終了コードは specifications.md で決めている。
golem-cli は実行ファイルを持つ唯一のモジュールであり、引数を解釈して各モジュールを呼ぶだけの薄い層とする。
処理の本体を CLI に書くと、LSP のようにほかの入口から同じ処理を使えなくなるためである。

## 実装すること

### コマンド

| コマンド | 呼ぶもの |
|---|---|
| `golem new <dir>` | プロジェクトの雛形を作る |
| `golem build [--target T ...] [--profile dev\|prod]` | golem-driver の `build` |
| `golem check [--profile dev\|prod]` | golem-driver の `build`（出力を作らない） |
| `golem plugin fetch` | golem-plugin の取得 |
| `golem plugin lock` | golem-plugin のロックファイルの更新 |
| `golem inspect <file> [--cst\|--ast\|--ir]` | 構文木、AST、意味論 IR（CBOR を人が読める形にしたもの）を表示する |

`golem lint`、`golem fmt`、`golem lsp` は、それぞれのモジュールの ADR で加える。

### golem new

- `manifest.toml`、`style.toml`、章のファイルを一つ、`.gitignore`（`build/` を除外する）を作る。
- マニフェストの `id` を、UUID の v4 で生成する。これが Golem が乱数を使う唯一の箇所である。
- 指定したディレクトリが空でない場合はエラーとし、既存のファイルを上書きしない。

### 診断の出力

- 既定は人が読む形とし、`--format json` で機械が読む形にする（[golem-syntax ADR 0001](../../golem-syntax/adr/0001-source-spans-and-diagnostics.md)）。
- 診断は標準エラー出力に、それ以外の出力は標準出力に書く。

### 終了コード

| コード | 意味 |
|---|---|
| 0 | 成功。警告があっても 0 とする |
| 1 | 診断によるエラーがある |
| 2 | コマンドの使い方の誤り（未知のオプションなど） |

### 引数の解釈

optparse-applicative を使う。

## 実装しないこと

- lint、fmt、LSP のコマンド。それぞれのモジュールの ADR で加える。
- 対話的な入力。CI で使うので、すべての操作は引数だけで完結させる。
- 設定ファイルによる既定のオプションの変更。

## テスト設計

- 各コマンドの成功と失敗の終了コードを、テスト用のプロジェクトで確かめる。
- `golem new` が作るファイルの内容を、`id` を除いて golden テストで固定する。`id` は UUID の形式であることだけを確かめる。
- 空でないディレクトリへの `golem new` がエラーになり、ファイルを変更しないことを確かめる。
- 未知のオプションで終了コードが 2 になることを確かめる。
- `--format json` の出力が JSON として正しいことを確かめる。

## トレードオフ

`golem new` の `id` だけは乱数で作るので、`golem new` の出力は決定的ではない。
`id` は一度作れば変えない値であり、作った後のビルドの決定性には影響しない。
