# ADR 0001: ソース位置と診断

ステータス: 採択→コードの一覧は [golem-cli ADR 0005](../../golem-cli/adr/0005-explain-diagnostic-codes.md)、重大度と並び順は [ADR 0002](0002-notice-severity.md)、診断の事実の欄とプリフライトの区分 09 は [golem-cli ADR 0006](../../golem-cli/adr/0006-preflight.md)、コードの形は [docs/adr 0061](../../adr/0061-five-digit-diagnostic-codes.md)、並び順は [ADR 0003](0003-diagnostic-order.md)

## 文脈

golem-syntax は全モジュールが依存する最下層であり、ソースの位置と診断を表す型を持つ。
コンパイルエラー、lint の警告、LSP の診断、プラグインが返す診断は、すべて同じ形式で表すと決めている。
この型が後から変わると全モジュールに波及するので、ほかのどのインターフェースよりも先に固める。

位置の単位には選択がある。
原稿は UTF-8 で書かれ、LSP は既定では UTF-16 の単位で位置を数え、人間は行と文字で位置を読む。
このどれを内部の表現にするかで、変換が必要になる場所が変わる。

## 実装すること

### データ構造

```haskell
newtype FileId = FileId Int

data SrcSpan = SrcSpan
  { spanFile  :: !FileId
  , spanStart :: !Int   -- ファイル先頭からの UTF-8 のバイト数
  , spanEnd   :: !Int   -- 終端（この位置を含まない）
  }

data Severity = Error | Warning

newtype DiagnosticCode = DiagnosticCode Text   -- 例: "G01001"

data Diagnostic = Diagnostic
  { diagCode     :: !DiagnosticCode
  , diagSeverity :: !Severity
  , diagSpan     :: !SrcSpan
  , diagMessage  :: !Text
  , diagRelated  :: ![(SrcSpan, Text)]   -- 関連する位置（循環の経路など）
  , diagFixes    :: ![Fix]
  }

data Fix = Fix
  { fixTitle :: !Text
  , fixEdits :: ![(SrcSpan, Text)]      -- 置き換える範囲と新しいテキスト
  }
```

- 位置はファイル先頭からの UTF-8 のバイト数で持つ。行と列は、ファイルの内容から必要なときに計算する。
- `FileId` とプロジェクトルートからの正規化パスの対応は、ファイルの表（`FileTable`）が持つ。`FileId` はマニフェストの章の順とファイルを初めて読んだ順で決まり、実行ごとに変わらない。
- 行と列への変換、UTF-16 の単位への変換の関数を用意する。UTF-16 への変換は LSP の境界でだけ使う。

### 診断コード

- 診断コードは `G` と 4 桁の数字とし、一度割り当てたコードは別の意味に再利用しない。
- 上 2 桁で発生源を分ける（`G01xxx` 構文、`G02xxx` 評価、`G03xxx` プロジェクトと import、`G04xxx` 文書構造、`G05xxx` lint、`G06xxx` プラグイン、`G07xxx` レイアウト、`G08xxx` 出力）。
- コードの一覧は golem-syntax の中に一箇所で定義する。

### 重大度とプロファイル

一部の診断は、ビルドのプロファイルによって重大度が変わる（参照されていないラベルは dev で警告、prod でエラー）。
診断を作る側は既定の重大度を付け、プロファイルによる変更は `adjustForProfile :: Profile -> Diagnostic -> Diagnostic` の一箇所で行う。

### 出力の形式

- 人が読む形式：ファイルのパス、行、列、重大度、コード、メッセージ、該当行の抜粋。
- JSON 形式：上記のすべてのフィールドを持つ。`--format json` で使う。
- 診断はファイルの順、位置の順、コードの順で並べてから出力する。

## 実装しないこと

- 診断メッセージの多言語化。v1 のメッセージは日本語だけとする。
- 色付きの端末出力の細かい設定。
- 位置を UTF-16 や文字数で持つ表現。

## テスト設計

- バイト位置と行、列の相互変換を、ASCII、日本語、絵文字（4 バイトの文字）、サロゲートペアになる文字を含むテキストでプロパティテストする。
- UTF-16 への変換が、LSP の仕様の例と一致することを確かめる。
- 同じ診断の集合を異なる順序で与えても、出力が同じになることを確かめる。
- `adjustForProfile` が、対象の診断だけの重大度を変えることを確かめる。
- JSON 形式の出力を golden テストで固定する。

## トレードオフ

位置を UTF-8 のバイト数で持つと、LSP との境界で UTF-16 への変換が必要になる。
その代わり、パーサーと原稿のバイト列が同じ単位で扱え、変換は LSP の一箇所に閉じ込められる。
LSP 3.17 では UTF-8 の位置を交渉できるので、対応するエディタでは変換も不要になる。

診断コードを再利用しない規則は、コードの数を増やし続けることになる。
その代わり、CI のログや外部の資料に残ったコードが別の意味に変わることがない。
