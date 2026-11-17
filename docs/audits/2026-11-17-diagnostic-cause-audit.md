# 診断コードの原因の監査

[Golem ADR 0356](../adr/0356-diagnostic-cause-audit.md) に従い、diagnostics の一覧で状態が使用中の 423 件のコードについて、発生箇所、失敗した入力条件、書き手が直す箇所を照合した。
廃止の 7 件は、[廃止した診断コードの照合](2026-11-13-retired-diagnostic-codes.md) で照合を済ませている。
対象のソースは、コミット `41b5510dfe26754a6bce3da39ab5c74ccbb8d498` である。
再現に使った CLI は、同じソースから `cabal build exe:golem` でビルドしたものであり、`golem --version` は `golem 0.1.0-rc4` を返した。

## 手順

まず、各コードについて、modules の test の外にある発生箇所を探し、そのコードが出る入力条件と、書き手が直す箇所を読み取った。
異なる条件を独立して再現でき、修正方法の種類も異なるコードを、分割候補とした。
条件の違いがキー、値、名前、欄の違いだけで、同じ種類の修正で直るコードは、単一とした。
同じ検査を複数の箇所から出しているだけのコードも、単一とした。

次に、各候補について、`modules/golem-driver/test/fixtures/tempest` の写しを条件ごとに作り、その条件の入力だけを加えて CLI を実行した。
同じ写しに条件ごとの修正を加えて実行し直し、そのコードが消えることを確かめた。
`--format json` の diagnostics は標準エラーに出るので、標準エラーからコードを数えた。
プラグインの候補では、wat2wasm が手元にないので、modules/golem-plugin/test/plugins の .wat と同じ形のモジュールを手で wasm に符号化して使った。

## 結果の概要

使用中の 423 件のうち、分割候補は 62 件、単一は 359 件、未調査は 2 件である。
どの候補でも、二つ以上の条件が同じコードを出し、条件ごとに異なる修正でそのコードが消えた。
2026-11-13 の記録が挙げた G03001、G03006、G03013、G03026、G09102 も候補であり、上のコミットの CLI で再現し直した。

候補のうち、次のものは分け方の判断が要る。
G01100 は、[root ADR 0115](../adr/0115-reserved-syntax-code.md) が記法ごとにコードを分けないと明示して決めたコードであり、分けるにはその決定を置き換える ADR が要る。
G06005 と G07033 は、条件ごとに再現できるが、同じ一つの修正（プラグインの差し替え、傍注の領域の拡大）でも両方が消えるので、候補としては弱い。
E02106、G02133、G02135 は、修正の種類の差が小さい境界の例である。
G03256 の宣言の中の未定義の名前と種類の違う参照、G07027 の図版の脇のリストは、新しい番号ではなく既存のコード（G03257、G03258、G07028）に移す提案である。

この監査ではコードを改番しない。
各候補の修正提案は、旧コードに残す条件と、新しい番号か既存のコードに移す条件を示す。
新しい番号は、分割を決める ADR で、各段階の 100 から 999 の空きから割り当てる。
コードを分けると、旧コードで diagnostics を引く CI と、`silence-notices` と `silence-info` の設定の移行が要る。

## 候補

候補ごとに、条件、再現の入力、修正、旧コードを期待する試験、修正提案を示す。
表の変更は、どれも tempest の写しに一つだけ加えたものである。

再現はどれも、tempest の写しに `functions/ex.emet` を置き、`tempest.gm` の先頭に `@import functions/ex.emet as ex` と空行を足して行った。
表の変更の列には、`functions/ex.emet` の中身を書く（`\n` は改行である）。
`golem check --format json` は診断を標準エラーに出す。
修正は、同じ写しの `functions/ex.emet` を書き換えて行った。

### E01100

E01100 は、`.emet` の構文の誤り、文字列の `\u{...}` が Unicode のスカラー値でないこと、REPL の入力が式一つでないことの三つをまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 構文の誤り | `pub f :: Nat;\nf = 1\n` | `golem check --format json` | 1 | `E01100` 一件（functions/ex.emet 1:13、構文の誤りです） | `;` を消す | 終了コード 0、診断なし |
| `\u{...}` がスカラー値でない | `pub f :: String\nf = "\u{D800}"\n` | `golem check --format json` | 1 | `E01100` 一件（functions/ex.emet 2:6、`\u{D800}` は Unicode のスカラー値ではありません） | `\u{41}` にする | 終了コード 0、診断なし |
| REPL の入力が式一つでない | 写しは使わず、標準入力に `x where { x = 2 }` を与える | `golem repl emet` | 1 | `E01100` 一件（入力の 0 から 0、REPL には Emet の式を一つ入力してください） | 入力を式一つ（`2`）にする | 終了コード 0、出力 `2` |

旧コードを期待する試験は modules/golem-emet/test/LanguageSpec.hs:135-139、modules/golem-emet/test/LanguageSpec.hs:154-156、modules/golem-emet/test/LanguageSpec.hs:162、modules/golem-emet/test/LanguageSpec.hs:225-226、modules/golem-emet/test/ExportSpec.hs:175、modules/golem-cli/test/CommandsSpec.hs:163 と、manual/examples/emet/e01100-*.emet を読む modules/golem-driver/test/ManualEmetSpec.hs:44-50 である。
`\u{...}` の値の誤りを期待するのは LanguageSpec.hs:154-156 であり、REPL の入力の形を期待する試験は見つからない。
修正提案：構文の誤りは E01100 に残し、`\u{...}` の値の誤り（modules/golem-emet/src/Golem/Emet/Parse.hs:161）に新しい番号を付ける。
REPL の入力が式一つでないこと（modules/golem-emet/src/Golem/Emet.hs:180）にも、新しい番号を付ける。

### E02100

E02100 は、未定義の名前の参照と、シグネチャだけがあって等式のない関数と束縛をまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 未定義の名前 | `pub f :: Nat\nf = y\n` | `golem check --format json` | 1 | `E02100` 一件（functions/ex.emet 2:5、未定義の名前 y です） | 右辺を定義された値（`1`）にする | 終了コード 0、診断なし |
| 等式のないシグネチャ | `pub f :: Nat\npub g :: Nat\ng = 1\n` | `golem check --format json` | 1 | `E02100` 一件（functions/ex.emet 1:5、関数 f の等式がありません） | 等式 `f = 1` を足す | 終了コード 0、診断なし |

旧コードを期待する試験は modules/golem-emet/test/LanguageSpec.hs:182-183、modules/golem-emet/test/LanguageSpec.hs:246-247、modules/golem-emet/test/LanguageSpec.hs:424-427 と、manual/examples/emet/e02100-where.emet である。
どれも未定義の名前の試験であり、等式のないシグネチャの試験は見つからない。
修正提案：未定義の名前は E02100 に残し、等式のないシグネチャ（modules/golem-emet/src/Golem/Emet/Check.hs:629、Check.hs:1318）に新しい番号を付ける。

### E02101

E02101 は、式の型の不一致に加えて、型とコンストラクタの引数の数、レコードの構文、要求の列の形、型の別名の循環をまとめている。
別名の循環は、下の入力では再現しなかった。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 式の型の不一致 | `pub f :: Nat\nf = "a"\n` | `golem check --format json` | 1 | `E02101` 一件（functions/ex.emet 2:5、型が合いません: Nat を求める位置に String があります） | 右辺を `1` にする | 終了コード 0、診断なし |
| 型の引数の数 | `pub f :: List\nf = []\n` | `golem check --format json` | 1 | `E02101` 一件（functions/ex.emet 1:10、型 List の引数の数が合いません（1 個を取ります）） | `List Nat` にする | 終了コード 0、診断なし |
| コンストラクタのパターンの引数の数 | `data T = A Nat\npub f :: T -> Nat\nf (A x y) = x\n` | `golem check --format json` | 1 | `E02101` 一件（functions/ex.emet 3:4、コンストラクタ A は 1 個の引数を取ります） | パターンを `(A x)` にする | 終了コード 0、診断なし |
| レコードでないコンストラクタにレコードの構文 | `pub data P = P Nat\npub f :: P\nf = P { x = 1 }\n` | `golem check --format json` | 1 | `E02101` 一件（functions/ex.emet 3:5、コンストラクタ P はレコードではありません） | `P 1` と書く | 終了コード 0、診断なし |
| レコードの構築の欄の欠け | `pub data P = P { x :: Nat, y :: Nat }\npub f :: P\nf = P { x = 1 }\n` | `golem check --format json` | 1 | `E02101` 一件（functions/ex.emet 3:5、欄 y がありません） | `y = 2` を足す | 終了コード 0、診断なし |
| `file` の引数が一つでない | `pub f :: Nat -> <file> Nat\nf x = x\n` | `golem check --format json` | 1 | `E02101` 一件（functions/ex.emet 1:18、file には読むファイルのパスを一つだけ書きます） | 要求の列を消す | 終了コード 0、診断なし |
| 型の変数と要求の変数に同じ名前 | `pub f :: (a -> a a) -> a -> a\nf g x = g x\n` | `golem check --format json` | 1 | `E02101` 一件（functions/ex.emet 1:16、変数 a を型の変数と要求の変数の両方に使っています） | 要求の変数を `e` にする（`(a -> e a) -> a -> e a`） | 終了コード 0、診断なし |
| 型の別名の循環（未再現） | `type A = B\ntype B = A\npub f :: A\nf = 1\n` | `golem check --format json` | 1 | `E02101` 一件（functions/ex.emet 4:5、型が合いません: A を求める位置に Nat があります）であり、循環のメッセージは出ない | `type A = Nat` にする | 終了コード 0、診断なし |

旧コードを期待する試験は modules/golem-emet/test/LanguageSpec.hs:248-249、LanguageSpec.hs:274-277、LanguageSpec.hs:284、LanguageSpec.hs:288-291、LanguageSpec.hs:297-298、modules/golem-emet/test/RequirementSpec.hs:65-68、RequirementSpec.hs:105、RequirementSpec.hs:183-184、modules/golem-driver/test/CallsSpec.hs:204、CallsSpec.hs:275 と、manual/examples/emet/e02101-*.emet である。
要求の列の形を期待するのは RequirementSpec.hs:65-68 で、残りは式の型の不一致の試験である。
引数の数とレコードの構文の試験は見つからない。
修正提案：式の型の不一致（演算子が使えない型と数の狭めを含む）は E02101 に残す。
型とコンストラクタの引数の数（modules/golem-emet/src/Golem/Emet/Check.hs:448、Check.hs:1161）、レコードの構文（Check.hs:1058、Check.hs:1062、Check.hs:1191）、要求の列の形（Check.hs:440、Check.hs:528、Check.hs:658）には、それぞれ新しい番号を付ける。
要求の列の形は、E05 の範囲に置いてもよい。

### E02106

E02106 は、等式どうしの引数の数の食い違いと、等式とシグネチャの食い違いをまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 等式の引数がシグネチャの矢印より多い | `pub f :: Nat -> Nat\nf x y = x\n` | `golem check --format json` | 1 | `E02106` 一件（functions/ex.emet 2:1、等式の引数がシグネチャの矢印の数より多くあります） | シグネチャを `Nat -> Nat -> Nat` にする | 終了コード 0、診断なし |
| 等式どうしで引数の数が違う | `pub f :: Nat -> Nat -> Nat\nf 0 y = y\nf x = g\n  where {\n    g y = y\n  }\n` | `golem check --format json` | 1 | `E02106` 一件（functions/ex.emet 3:1、等式どうしで引数の数が違います） | 二つ目の等式を `f x y = y` にする | 終了コード 0、診断なし |

旧コードを期待する試験は modules/golem-emet/test/LanguageSpec.hs:184-185（シグネチャとの食い違い）と modules/golem-emet/test/LanguageSpec.hs:186-187（等式どうしの食い違い）である。
修正提案：等式どうしの食い違い（modules/golem-emet/src/Golem/Emet/Check.hs:725）は E02106 に残し、シグネチャの矢印を超える引数（Check.hs:727）に新しい番号を付ける。

### E06100

E06100 は、`.gm` に出す名前の規則違反と、`pub fn` に名前の文字列を書いたことをまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 名前が規則に反する | `pub inline "Tax" tax :: Nat -> Inlines\ntax n = []\n` | `golem check --format json` | 1 | `E06100` 一件（functions/ex.emet 1:12、コマンドとフィルタの名前は、英小文字で始まり…） | 名前を `"tax"` にする | 終了コード 0、診断なし |
| pub fn に名前の文字列がある | `pub fn "tax" tax :: Nat -> Nat\ntax n = n\n` | `golem check --format json` | 1 | `E06100` 一件（functions/ex.emet 1:8、pub fn は .emet の名前のまま式から呼ぶので、名前の文字列を書けません） | 文字列を消す（`pub fn tax :: Nat -> Nat`） | 終了コード 0、診断なし |

旧コードを期待する試験は modules/golem-emet/test/ExportSpec.hs:52-55 と modules/golem-emet/test/ExportSpec.hs:123-124 である。
どれも規則違反の試験であり、pub fn の名前の文字列の試験は見つからない。
修正提案：規則違反（modules/golem-emet/src/Golem/Emet/Check.hs:1598、Check.hs:1601、Check.hs:1644）は E06100 に残し、pub fn の名前の文字列（Check.hs:1594）に新しい番号を付ける。

### E06102

E06102 は、`.gm` から渡せない引数の型、引数の並びの誤り、種類に合わない `Inlines` と `Blocks` の三つをまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 渡せない型 | `pub inline f :: Maybe Nat -> Inlines\nf _ = []\n` | `golem check --format json` | 1 | `E06102` 一件（functions/ex.emet 1:17、.gm から渡せない型の引数です） | 引数の型を `Nat` にする | 終了コード 0、診断なし |
| 並びの誤り | `pub inline f :: Inlines -> Nat -> Inlines\nf xs _ = xs\n` | `golem check --format json` | 1 | `E06102` 一件（functions/ex.emet 1:28、Inlines と Blocks の引数は、ほかの型の引数の後ろに置きます） | `Nat -> Inlines -> Inlines` に並べ替える | 終了コード 0、診断なし |
| 種類に合わない Inlines | `pub block f :: Inlines -> Blocks\nf _ = []\n` | `golem check --format json` | 1 | `E06102` 一件（functions/ex.emet 1:16、Inlines を受け取れるのはインラインのコマンドの散文スロットだけです） | 種類を inline にする（`pub inline f :: Inlines -> Inlines`） | 終了コード 0、診断なし |

旧コードを期待する試験は modules/golem-emet/test/ExportSpec.hs:82-83（並び）、ExportSpec.hs:84-85（型）、ExportSpec.hs:86-88（並び）、ExportSpec.hs:162-163（型）である。
種類に合わない `Inlines` と `Blocks` の試験は見つからない。
修正提案：渡せない型（modules/golem-emet/src/Golem/Emet/Check.hs:1633、Check.hs:1639、Check.hs:1646）は E06102 に残す。
並びの誤り（Check.hs:1631、Check.hs:1656）と、種類に合わない `Inlines` と `Blocks`（Check.hs:1652、Check.hs:1655）には、それぞれ新しい番号を付ける。

### E06103

E06103 は、キーワード引数の既定の値の欠けと誤り、位置の誤り、キーワード引数を持てない関数にあることをまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 既定の値がない | `pub inline f :: (tax :: Bool) -> Inlines\nf _ = []\n` | `golem check --format json` | 1 | `E06103` 一件（functions/ex.emet 1:17、キーワード引数には既定の値を書きます） | `= True` を足す | 終了コード 0、診断なし |
| 既定の値がその型のリテラルでない | `pub inline f :: (tax :: Bool = 1) -> Inlines\nf _ = []\n` | `golem check --format json` | 1 | `E06103` 一件（functions/ex.emet 1:32、キーワード引数の既定の値は Bool のリテラルに限ります） | 既定の値を `True` にする | 終了コード 0、診断なし |
| 位置の誤り | `pub inline f :: Inlines -> (tax :: Bool = True) -> Inlines\nf xs _ = xs\n` | `golem check --format json` | 1 | `E06103` 一件（functions/ex.emet 1:28、キーワード引数は散文スロットと本体の前に置きます） | キーワード引数を散文スロットの前に移す | 終了コード 0、診断なし |
| 持てない関数にある | `pub fn f :: (tax :: Bool = True) -> Nat\nf _ = 1\n` | `golem check --format json` | 1 | `E06103` 一件（functions/ex.emet 1:13、キーワード引数は、インラインのコマンドとブロックコマンドだけが持てます） | キーワード引数を消す（`pub fn f :: Nat`） | 終了コード 0、診断なし |

旧コードを期待する試験は modules/golem-emet/test/ExportSpec.hs:113-114（既定の値がない）、ExportSpec.hs:115-116（位置）、ExportSpec.hs:117-120（持てない関数）、ExportSpec.hs:121-122（リテラルでない）である。
修正提案：持てない関数にあること（modules/golem-emet/src/Golem/Emet/Check.hs:1490、Check.hs:1555、Check.hs:1577、Check.hs:1642）は E06103 に残す。
既定の値の欠けと誤り（Check.hs:1647、Check.hs:1649）と位置の誤り（Check.hs:1630、Check.hs:1643）には、それぞれ新しい番号を付ける。
既定の値の欠けと、リテラルでないことをさらに分けるかは、判断が要る。

### E06105

E06105 は、可変長引数が二つあること、位置の誤り、可変長引数を置けない場所にあることをまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 二つある | `pub inline f :: Varargs Nat -> Varargs Nat -> Inlines\nf _ _ = []\n` | `golem check --format json` | 1 | `E06105` 一件（functions/ex.emet 1:32、可変長引数は一つの関数に一つだけです） | 一つ消す | 終了コード 0、診断なし |
| 位置の誤り | `pub inline f :: Varargs Nat -> Nat -> Inlines\nf _ _ = []\n` | `golem check --format json` | 1 | `E06105` 一件（functions/ex.emet 1:32、可変長引数の後ろに位置引数は置けません） | `Nat -> Varargs Nat -> Inlines` に並べ替える | 終了コード 0、診断なし |
| 置けない場所 | `pub f :: Varargs Nat -> Nat\nf _ = 1\n` | `golem check --format json` | 1 | `E06105` 一件（functions/ex.emet 1:10、Varargs は、pub inline、pub block、pub fn の引数にだけ書けます） | `List Nat` にする | 終了コード 0、診断なし |

旧コードを期待する試験は modules/golem-emet/test/ExportSpec.hs:131-132（二つ）、ExportSpec.hs:133-134（位置）、ExportSpec.hs:135-138（置けない場所）である。
修正提案：置けない場所（modules/golem-emet/src/Golem/Emet/Check.hs:1491、Check.hs:1556、Check.hs:1575、Check.hs:1578）は E06105 に残す。
二つあること（Check.hs:1636）と位置の誤り（Check.hs:1629、Check.hs:1637）には、それぞれ新しい番号を付ける。
引数の並びの誤りは、E06102（Check.hs:1631、Check.hs:1656）、E06103（Check.hs:1630、Check.hs:1643）、E06105（Check.hs:1629、Check.hs:1637）に散っているので、並べ替えで直す一つの新しい番号にまとめてもよい。

### G01100
G01100 は、マクロのために予約した `[!` と `@!` を書いた誤りと、範囲の `..` を書いた誤りをまとめている。
root [ADR 0115](../adr/0115-reserved-syntax-code.md) は、記法ごとにコードを分けないと明示して決めた。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| `[!` を書いた | tempest.gm の末尾に段落 `a [!x] b` を足した | `golem check --format json` | 1 | `G01100 一件（tempest.gm 3228:3）` | `a \[!x] b` とエスケープした | 終了コード 0、診断なし |
| `@!` を書いた | tempest.gm の末尾に行 `@!foo` を足した | `golem check --format json` | 1 | `G01100 一件（tempest.gm 3228:1）` | `\@!foo` とエスケープした | 終了コード 0、診断なし |
| 範囲を `..` で書いた | tempest.gm の末尾に段落 `[= len([1..3])]` を足した | `golem check --format json` | 1 | `G01100 一件（tempest.gm 3228:10）` | `[= len([1...3])]` と `...` に替えた | 終了コード 0、診断なし |

旧コードを期待する試験は modules/golem-parser/test/ParserSpec.hs:318-323、modules/golem-parser/test/ParserSpec.hs:356-358、modules/golem-parser/test/ParserSpec.hs:392-405、modules/golem-parser/test/ParserSpec.hs:436-438、modules/golem-cli/test/CommandsSpec.hs:718-722、modules/golem-eval/test/RangeSpec.hs:153-155、modules/golem-eval/test/RangeSpec.hs:174-175 である。
修正提案：`[!` と `@!` は G01100 に残し、`..` は構文の段階の新しい番号にする。
評価の段階で語と文字列の中の `..` を報告する modules/golem-eval/src/Golem/Eval/File.hs:3028 も、同じ新しい番号にする。
root [ADR 0115](../adr/0115-reserved-syntax-code.md) の決定を変えるので、新しい ADR が要る。

### G02002
G02002 は、未定義の名前と、.emet の関数が pub fn でない誤りと、.gm の変数の取り込みの名前空間で関数を呼んだ誤りをまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 未定義の変数 | tempest.gm の末尾に段落 `[= y]` を足した | `golem check --format json` | 1 | `G02002 一件（tempest.gm 3228:4）` | tempest.gm の先頭に `set y = 1` を足した | 終了コード 0、診断なし |
| pub fn でない関数を式から呼んだ | functions/book.emet に `pub inline greet :: Inlines` と `greet = Inline.text "hi"` を書き、tempest.gm の先頭に `@import functions/book.emet as book`、末尾に `[= book.greet()]` を足した | `golem check --format json` | 1 | `G02002 一件（tempest.gm 3230:4）` | 呼び出しを `[book.greet]` に替えた | 終了コード 0、診断なし |
| .gm の変数の取り込みで関数を呼んだ | vars.gm に `set x = 1` を書き、tempest.gm の先頭に `@import vars.gm as v`、末尾に `[= v.twice(1)] [= v.x]` を足した（functions/book.emet には `pub fn twice :: Nat -> Nat` がある） | `golem check --format json` | 1 | `G02002 一件（tempest.gm 3230:4）` | `@import functions/book.emet as book` を足し、`[= book.twice(1)]` に替えた | 終了コード 0、診断なし |

旧コードを期待する試験は、未定義の名前の条件が modules/golem-eval/test/ExprSpec.hs:87、modules/golem-eval/test/ExprSpec.hs:137-141、modules/golem-eval/test/VarsSpec.hs:68-73、modules/golem-eval/test/FileSpec.hs:365、modules/golem-driver/test/ColophonSpec.hs:121-125、modules/golem-lsp/test/TableWatchSpec.hs:128、modules/golem-lsp/test/TableWatchSpec.hs:137、modules/golem-driver/test/PluginsSpec.hs:1256 である。
pub fn でない条件は modules/golem-eval/test/FunctionSpec.hs:161-164 と modules/golem-driver/test/CallsSpec.hs:186-190 である。
.gm の変数の取り込みの条件には試験がない。
修正提案：未定義の名前は G02002 に残し、pub fn でない関数の呼び出しを新しい番号にする。
.gm の変数の取り込みの名前空間でコマンドか関数を呼ぶ誤りは、G02009 と G02022 の同じ条件と合わせて、一つの新しい番号にする。

### G02009
G02009 は、未知のブロックコマンドと、.gm の変数の取り込みの名前空間でブロックコマンドを呼んだ誤りをまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 未知のブロックコマンド | tempest.gm の末尾に行 `@tocc` を足した | `golem check --format json` | 1 | `G02009 一件（tempest.gm 3228:2）` | `@toc` に綴りを直した | 終了コード 0、診断なし |
| .gm の変数の取り込みでブロックコマンドを呼んだ | vars.gm に `set x = 1` を書き、tempest.gm の先頭に `@import vars.gm as v`、末尾に `@v.rule` と段落 `[= v.x]` を足した（functions/book.emet には `pub block rule :: Blocks` がある） | `golem check --format json` | 1 | `G02009 一件（tempest.gm 3230:2）` | `@import functions/book.emet as book` を足し、`@book.rule` に替えた | 終了コード 0、診断なし |

旧コードを期待する試験は modules/golem-eval/test/FileSpec.hs:163、modules/golem-eval/test/FileSpec.hs:398、modules/golem-eval/test/FileSpec.hs:610、modules/golem-eval/test/FileSpec.hs:1915、modules/golem-eval/test/FunctionSpec.hs:81-83、modules/golem-lsp/test/FunctionsLspSpec.hs:126、modules/golem-driver/test/PluginsSpec.hs:278、modules/golem-driver/test/PluginsSpec.hs:601 である。
.gm の変数の取り込みの条件には試験がない。
修正提案：未知のブロックコマンドは G02009 に残す。
.gm の変数の取り込みの名前空間の誤り（modules/golem-eval/src/Golem/Eval/File.hs:678）は、G02002 と G02022 の同じ条件と合わせて、一つの新しい番号にする。

### G02022
G02022 は、未知のインラインのコマンドと、.gm の変数の取り込みの名前空間でインラインのコマンドを呼んだ誤りをまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 未知のインラインのコマンド | tempest.gm の末尾に段落 `[strongg: x]` を足した | `golem check --format json` | 1 | `G02022 一件（tempest.gm 3228:2）` | `[strong: x]` に綴りを直した | 終了コード 0、診断なし |
| .gm の変数の取り込みでインラインのコマンドを呼んだ | vars.gm に `set x = 1` を書き、tempest.gm の先頭に `@import vars.gm as v`、末尾に段落 `[v.greet] [= v.x]` を足した（functions/book.emet には `pub inline greet :: Inlines` がある） | `golem check --format json` | 1 | `G02022 一件（tempest.gm 3230:2）` | `@import functions/book.emet as book` を足し、`[book.greet]` に替えた | 終了コード 0、診断なし |

旧コードを期待する試験は modules/golem-eval/test/FileSpec.hs:164、modules/golem-eval/test/FileSpec.hs:397、modules/golem-eval/test/FileSpec.hs:546、modules/golem-eval/test/FileSpec.hs:1946、modules/golem-eval/test/FunctionSpec.hs:78-82、modules/golem-driver/test/CallsSpec.hs:152-155、modules/golem-eval/test/DiagnosticSitesSpec.hs:33-35、modules/golem-driver/test/CliSpec.hs:395、modules/golem-driver/test/DiagnosticsSpec.hs:248-250、modules/golem-driver/test/PluginsSpec.hs:278、modules/golem-cli/test/CommandsSpec.hs:586、modules/golem-cli/test/Main.hs:641-644 である。
.gm の変数の取り込みの条件には試験がない。
修正提案：未知のインラインのコマンドは G02022 に残す。
.gm の変数の取り込みの名前空間の誤りは、G02002 と G02009 の同じ条件と合わせて、一つの新しい番号にする。

### G02017
G02017 は、style.toml にないスウォッチの名前と、スウォッチの名前を語で一つ書かない誤りをまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 未定義のスウォッチ | tempest.gm の末尾に段落 `[color red: x]` を足した | `golem check --format json` | 1 | `G02017 一件（tempest.gm 3228:1）` | style.toml に `[color.swatches]` と `red = { cmyk = [0, 100, 100, 0] }` を足した | 終了コード 0、診断なし |
| 名前を語で一つ書かない | style.toml に同じ `red` のスウォッチを足し、tempest.gm の末尾に段落 `[color [= "red"]: a]` を足した | `golem check --format json` | 1 | `G02017 一件（tempest.gm 3228:1）` | `[color red: a]` と名前を語で書いた | 終了コード 0、診断なし |

旧コードを期待する試験は、未定義の条件が modules/golem-eval/test/FileSpec.hs:390 と modules/golem-eval/test/FileSpec.hs:1939、名前を一つ書かない条件が modules/golem-eval/test/FileSpec.hs:1936 である。
修正提案：未定義のスウォッチは G02017 に残す。
名前を一つ書かない誤りは、G02018 と G02047 の同じ条件と合わせて、一つの新しい番号にする。

### G02018
G02018 は、未定義の文字スタイルの名前と、文字スタイルの名前を語で一つ書かない誤りをまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 未定義の文字スタイル | tempest.gm の末尾に段落 `[style term: x]` を足した | `golem check --format json` | 1 | `G02018 一件（tempest.gm 3228:1）` | style.toml に `[character-styles.term]` を足した | 終了コード 0、診断なし |
| 名前を語で一つ書かない | style.toml に `[character-styles.term]` を足し、tempest.gm の末尾に段落 `[style [= "term"]: x]` を足した | `golem check --format json` | 1 | `G02018 一件（tempest.gm 3228:1）` | `[style term: x]` と名前を語で書いた | 終了コード 0、診断なし |

旧コードを期待する試験は、未定義の条件が modules/golem-eval/test/FileSpec.hs:391、modules/golem-eval/test/FileSpec.hs:1131、modules/golem-eval/test/FunctionSpec.hs:153、名前を一つ書かない条件が modules/golem-eval/test/FileSpec.hs:1937 である。
修正提案：未定義の文字スタイルは G02018 に残す。
名前を一つ書かない誤りは、G02017 と G02047 の同じ条件と合わせて、一つの新しい番号にする。

### G02047
G02047 は、未定義の段落スタイルの名前と、`@style` に段落スタイルの名前を一つ書かない誤りをまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 未定義の段落スタイル | tempest.gm の末尾に行 `@style lead` と段落 `x` を足した | `golem check --format json` | 1 | `G02047 一件（tempest.gm 3229:1）` | style.toml に `[paragraph-styles.lead]` を足した | 終了コード 0、診断なし |
| 名前を一つ書かない | style.toml に `[paragraph-styles.lead]` を足し、tempest.gm の末尾に名前のない `@style` と字下げした本体 `  x` を足した | `golem check --format json` | 1 | `G02047 一件（tempest.gm 3228:1）` | `@style lead` と名前を書いた | 終了コード 0、診断なし |

旧コードを期待する試験は、未定義の条件が modules/golem-eval/test/FileSpec.hs:199-201、modules/golem-eval/test/FileSpec.hs:607、modules/golem-eval/test/FileSpec.hs:631、modules/golem-eval/test/FileSpec.hs:704-705、modules/golem-eval/test/FileSpec.hs:1211、modules/golem-eval/test/FileSpec.hs:1278、modules/golem-eval/test/FileSpec.hs:1322、modules/golem-eval/test/FunctionSpec.hs:154、modules/golem-eval/test/TableAttributesSpec.hs:70-71、modules/golem-eval/test/TableAttributesSpec.hs:79、modules/golem-driver/test/CallsSpec.hs:197-200、modules/golem-driver/test/StylesSpec.hs:168 である。
名前を一つ書かない条件は modules/golem-eval/test/FileSpec.hs:609 である。
修正提案：未定義の段落スタイルは G02047 に残す。
名前を一つ書かない誤り（modules/golem-eval/src/Golem/Eval/File.hs:1544）は、G02017 と G02018 の同じ条件と合わせて、一つの新しい番号にする。

### G02019
G02019 は、`style` の値が語彙の外にある誤りと、数の引数が整数一つでない誤りをまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| `style` が語彙の外 | tempest.gm の末尾に段落 `[number-text 1 style=roman]` を足した | `golem check --format json` | 1 | `G02019 一件（tempest.gm 3228:1）` | `style=kanji` に替えた | 終了コード 0、診断なし |
| 整数でない数 | tempest.gm の末尾に段落 `[number-text 1.5]` を足した | `golem check --format json` | 1 | `G02019 一件（tempest.gm 3228:1）` | `[number-text 2]` と整数にした | 終了コード 0、診断なし |
| 数を書かない | tempest.gm の末尾に段落 `[number-text]` を足した | `golem check --format json` | 1 | `G02019 一件（tempest.gm 3228:1）` | `[number-text 2]` と整数を一つ書いた | 終了コード 0、診断なし |

旧コードを期待する試験は、`style` の条件が modules/golem-eval/test/FileSpec.hs:384、数の条件が modules/golem-eval/test/FileSpec.hs:383、modules/golem-eval/test/FileSpec.hs:807、modules/golem-eval/test/FileSpec.hs:841-843、modules/golem-eval/test/FileSpec.hs:1942-1943 である。
修正提案：数の引数の誤りは G02019 に残し、`style` の値が語彙の外にある誤りを新しい番号にする。
整数でない数と数を書かない誤りは、どちらも整数を一つ書けば直るので、分けない。

### G02042
G02042 は、索引の段が 3 段以上ある誤りと、語と読みの段の数が違う誤りと、空の段がある誤りをまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 3 段以上 | tempest.gm の末尾に段落 `[index reading=あ/い/う: a/b/c]` を足した | `golem check --format json` | 1 | `G02042 一件（tempest.gm 3228:1）` | `[index reading=あ/い: a/b]` と 2 段にした | 終了コード 0、診断なし |
| 段の数が違う | tempest.gm の末尾に段落 `[index reading=あ/い: a]` を足した | `golem check --format json` | 1 | `G02042 一件（tempest.gm 3228:1）` | 語を `a/b` にして段の数をそろえた | 終了コード 0、診断なし |
| 空の段 | tempest.gm の末尾に段落 `[index reading=あ/: a/b]` を足した | `golem check --format json` | 1 | `G02042 一件（tempest.gm 3228:1）` | 読みを `あ/い` にして空の段を埋めた | 終了コード 0、診断なし |

旧コードを期待する試験は、3 段以上の条件の modules/golem-eval/test/FileSpec.hs:395 だけである。
段の数が違う条件と空の段の条件には試験がない。
修正提案：段の数が違う誤りは G02042 に残し、ルビの G02015 と対にする。
3 段以上の誤りと空の段の誤りは、それぞれ新しい番号にする。

### G02050
G02050 は、マニフェストにはあるがファイルの中で上書きできないキーと、どこにもないキーをまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 上書きできないマニフェストのキー | tempest.gm の先頭に `@manifest title=x` を足した | `golem check --format json` | 1 | `G02050 一件（tempest.gm 1:11）` | `@manifest` の行を消し、manifest.toml の `[metadata]` の `title` を `"x"` にした | 終了コード 0、診断なし |
| 未知のキー | tempest.gm の先頭に `@manifest paragraph-separater=line` を足した | `golem check --format json` | 1 | `G02050 一件（tempest.gm 1:11）` | `paragraph-separator` に綴りを直した | 終了コード 0、診断なし |

旧コードを期待する試験は、上書きできないキーの条件が modules/golem-eval/test/FileSpec.hs:1217 と modules/golem-eval/test/FileSpec.hs:1300、未知のキーの条件が modules/golem-eval/test/FileSpec.hs:1218 と modules/golem-eval/test/FileSpec.hs:1301 である。
modules/golem-eval/test/FileSpec.hs:1220 と modules/golem-eval/test/FileSpec.hs:1310 も G02050 を期待する。
修正提案：未知のキーは G02050 に残し、上書きできないマニフェストのキーを新しい番号にする。
今の modules/golem-eval/src/Golem/Eval/Settings.hs:124 は `[source]` の表だけを見るので、分けるにはマニフェストのキーの一覧が要る。

再現は、どれも modules/golem-driver/test/fixtures/tempest の写しの tempest.gm の末尾に、空行を挟んで表の行を足して行った。
足した行は tempest.gm の 3228 行めから始まる。
コマンドは、ビルドした golem の CLI を写しのディレクトリで動かしたものである。

### G02055
`[aki]` の引数の数の誤り、量の語の誤り、散文スロットの誤りを一つのコードにまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 量を二つ書いた | `a[aki 四分 二分]b` を足す | `golem check --format json` | 1 | `G02055` 一件（tempest.gm 3228:2、aki には量を一つ書きます） | `a[aki 四分]b` にする | 終了コード 0、診断なし |
| 量の語を読めない | `a[aki 十分]b` を足す | `golem check --format json` | 1 | `G02055` 一件（tempest.gm 3228:2、アキの量を読めません: 十分） | `a[aki 四分]b` にする | 終了コード 0、診断なし |
| 散文スロットを書いた | `a[aki 四分: 語]` を足す | `golem check --format json` | 1 | `G02055` 一件（tempest.gm 3228:2、aki は散文スロットを取りません） | `a[aki 四分]語` にする | 終了コード 0、診断なし |

旧コードを期待する試験は modules/golem-eval/test/FileSpec.hs:1870 から 1880 である。
修正提案：量の語を読めない条件は G02055 に残す。
量の数とキーワード引数の条件には新しい番号を振る。
散文スロットの条件は、散文スロットを取らないコマンドの G02038 に移すか、新しい番号を振る。

### G02058
`@page-break` の引数の数か形の誤りと、引数の語が recto と verso のどちらでもない誤りを一つのコードにまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 引数を二つ書いた | `@page-break recto verso` を足す | `golem check --format json` | 1 | `G02058` 一件（tempest.gm 3228:1） | `@page-break recto` にする | 終了コード 0、`G04008` 一件（お知らせ、本の最後の改ページ） |
| 語彙の外の語 | `@page-break page` を足す | `golem check --format json` | 1 | `G02058` 一件（tempest.gm 3228:1） | `@page-break` にする | 終了コード 0、`G04008` 一件（お知らせ、本の最後の改ページ） |

修正後の `G04008` は、改ページを本の最後に置いたことによるお知らせであり、G02058 とは関係しない。
旧コードを期待する試験は modules/golem-eval/test/FileSpec.hs:1472 から 1477 である。
修正提案：語彙の外の語の条件は G02058 に残す。
引数の数とキーワード引数の条件には新しい番号を振る。
この新しい番号は、G02070 と G02099 の同じ条件と共通にしてよい。

### G02069
コードブロックの引数と中身にまつわる七つの誤りを一つのコードにまとめている。
七つは、書けないキー、開始の行の位置引数、キーの値の誤り、コードにない highlight の行、diff の行頭の誤り、範囲の外の注釈の印、本文のない `@caption` である。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 書けないキー | 開始の行が ```` ``` unknown=1 ````、中身が `a` のコードブロックを足す | `golem check --format json` | 1 | `G02069` 一件（tempest.gm 3228:5） | `unknown=1` を消す | 終了コード 0、診断なし |
| 開始の行の位置引数 | 開始の行が ```` ```haskell foo ````、中身が `a` のコードブロックを足す | `golem check --format json` | 1 | `G02069` 一件（tempest.gm 3228:12） | `foo` を消す | 終了コード 0、診断なし |
| キーの値の誤り | 開始の行が ```` ``` diff=yes ````、中身が `a` のコードブロックを足す | `golem check --format json` | 1 | `G02069` 一件（tempest.gm 3228:5） | `diff=true` にし、中身を ` a` にする | 終了コード 0、診断なし |
| コードにない highlight の行 | 開始の行が ```` ``` highlight=9 ````、中身が `a`、`b`、`c` の三行のコードブロックを足す | `golem check --format json` | 1 | `G02069` 一件（tempest.gm 3228:5） | `highlight=2` にする | 終了コード 0、診断なし |
| diff の行頭の誤り | 開始の行が ```` ``` diff=true ````、中身が `+a` と `xa` のコードブロックを足す | `golem check --format json` | 1 | `G02069` 一件（tempest.gm 3230:1） | 二行めを ` xa` にする | 終了コード 0、診断なし |
| 範囲の外の注釈の印 | 開始の行が ```` ``` callouts=true ````、中身が `foo <51>` のコードブロックを足す | `golem check --format json` | 1 | `G02069` 一件（tempest.gm 3229:1） | 印を `<1>` にする | 終了コード 0、診断なし |
| 本文のない `@caption` | `@caption` の行と、中身が `a` のコードブロックを足す | `golem check --format json` | 1 | `G02069` 一件（tempest.gm 3228:1） | `@caption 例` にし、その前に `@nonumber` の行を足す | 終了コード 0、診断なし |

本文のない `@caption` の修正で `@nonumber` を足したのは、tempest の写しの最後の位置が章の外であり、キャプションのあるコードブロックに番号を振ろうとして G04004 が出るからである。
旧コードを期待する試験は modules/golem-eval/test/FileSpec.hs:1764, 1765, 1770（書けないキーと位置引数）、FileSpec.hs:844, 1767, 1768, 1769, 1774 と modules/golem-eval/test/RangeSpec.hs:184（値の誤り）、FileSpec.hs:1713, 1717, 1726, 1742（highlight の行）、FileSpec.hs:1740（diff の行頭）、FileSpec.hs:1746（注釈の印）、FileSpec.hs:1756 と modules/golem-eval/test/TableAttributesSpec.hs:69（本文のない `@caption`）である。
修正提案：書けないキーの条件は G02069 に残し、ほかの六つの条件にはそれぞれ新しい番号を振る。
書けないキーと開始の行の位置引数は、受け付けない引数として一つの番号にまとめてもよい。

### G02070
`@need-lines` の引数の数か形の誤りと、値が 1 以上 10 の 9 乗未満の整数でない誤りを一つのコードにまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 引数を二つ書いた | `@need-lines 3 4` を足す | `golem check --format json` | 1 | `G02070` 一件（tempest.gm 3228:1） | `@need-lines 3` にする | 終了コード 0、診断なし |
| 値が 0 | `@need-lines 0` を足す | `golem check --format json` | 1 | `G02070` 一件（tempest.gm 3228:1） | `@need-lines 1` にする | 終了コード 0、診断なし |

旧コードを期待する試験は modules/golem-eval/test/FileSpec.hs:1528 から 1530 である。
修正提案：値の条件は G02070 に残す。
引数の数とキーワード引数の条件には新しい番号を振り、G02058 と G02099 の同じ条件と共通にしてよい。

### G02075
PDF の図版の page の値の誤りと、PDF でない図版に page を書いた誤りを一つのコードにまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| page の値が 0 | images/a.pdf（modules/golem-driver/test/fixtures/figures/images/chart.pdf の写し）と images/a.png（同じ所の gray.png の写し）を置き、`@nonumber` と `@figure images/a.pdf page=0 web=images/a.png alt="x"` の二行を足す | `golem check --format json` | 1 | `G02075` 一件（tempest.gm 3229:1） | `page=1` にする | 終了コード 0、診断なし |
| PDF でない図版の page | 同じ画像を置き、`@nonumber` と `@figure images/a.png page=1 alt="x"` の二行を足す | `golem check --format json` | 1 | `G02075` 一件（tempest.gm 3229:1） | `page=1` を消す | 終了コード 0、診断なし |

`@nonumber` は、章の外の図版に番号を振ろうとする G04004 を避けるために足した。
旧コードを期待する試験は modules/golem-eval/test/FileSpec.hs:471, 472（値）、FileSpec.hs:466, 473, 185（PDF でない図版）である。
修正提案：値の条件は G02075 に残し、PDF でない図版に page を書いた条件には新しい番号を振る。

### G02078
数の糖衣構文の中身が算用数字でない誤りと、閉じの `##` がない誤りを一つのコードにまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 中身が算用数字でない | `a##1.5##b` を足す | `golem check --format json` | 1 | `G02078` 一件（tempest.gm 3228:2） | `a##15##b` にする | 終了コード 0、診断なし |
| 閉じの `##` がない | `a##12年` を足す | `golem check --format json` | 1 | `G02078` 一件（tempest.gm 3228:2） | `a##12##年` にする | 終了コード 0、診断なし |

旧コードを期待する試験は modules/golem-eval/test/FileSpec.hs:657 から 660（閉じのない `##12年` も同じ一覧の 660 行めにある）と modules/golem-cli/test/Main.hs:446 である。
修正提案：中身の条件は G02078 に残し、閉じの `##` がない条件には新しい番号を振る。

### G02081
`@table` の align の値の語が語彙の外にある誤りと、値の数が列の数と違う誤りを一つのコードにまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 語彙の外の値 | 三列二行の t.tsv を置き、`@table t.tsv align=middle` を足す | `golem check --format json` | 1 | `G02081` 一件（tempest.gm 3228:14） | `align=center` にする | 終了コード 0、診断なし |
| 値の数が列と違う | 同じ t.tsv を置き、`@table t.tsv align=left,right` を足す | `golem check --format json` | 1 | `G02081` 一件（tempest.gm 3228:14） | `align=left,right,left` にする | 終了コード 0、診断なし |

旧コードを期待する試験は modules/golem-eval/test/TableSpec.hs:279 から 283（語彙）と TableSpec.hs:277 から 278（値の数）である。
修正提案：語彙の外の値の条件は G02081 に残し、値の数の条件には新しい番号を振る。

### G02086
数の大きさの上限を超えた誤りと、round と fixed の桁数の上限を超えた誤りを一つのコードにまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 数が 2 の 4096 乗以上 | `a[= 2 ** 4096]` を足す | `golem check --format json` | 1 | `G02086` 一件（tempest.gm 3228:5、数が大きすぎます） | `a[= 2 ** 10]` にする | 終了コード 0、診断なし |
| 桁数が 1000 を超える | `a[= round(1.5, 1001)]` を足す | `golem check --format json` | 1 | `G02086` 一件（tempest.gm 3228:5、小数の桁数が多すぎます） | `a[= round(1.5, 1)]` にする | 終了コード 0、診断なし |

旧コードを期待する試験は modules/golem-eval/test/ExprSpec.hs:159 から 170、modules/golem-eval/test/RationalSpec.hs:162 から 173、modules/golem-eval/test/NaturalSpec.hs:124 から 125、modules/golem-eval/test/FileSpec.hs:746 から 763、827 から 831、877 から 879、modules/golem-eval/test/RangeSpec.hs:130（大きさ）と、ExprSpec.hs:171 から 172、NaturalSpec.hs:118（桁数）である。
修正提案：数の大きさの条件は G02086 に残し、桁数の条件には新しい番号を振る。

### G02087
`@figure` の rotate の値の誤りと、rotate=true と wrap を一緒に書いた誤りを一つのコードにまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| rotate の値の誤り | images/a.png（modules/golem-driver/test/fixtures/figures/images/gray.png の写し）を置き、`@nonumber` と `@figure images/a.png alt="x" rotate=yes` の二行を足す | `golem check --format json` | 1 | `G02087` 一件（tempest.gm 3229:1） | `rotate=true` にする | 終了コード 0、診断なし |
| rotate と wrap の組み合わせ | 同じ画像を置き、`@nonumber` と `@figure images/a.png alt="x" rotate=true wrap=end width=4zw` の二行を足す | `golem check --format json` | 1 | `G02087` 一件（tempest.gm 3229:1） | `wrap=end` と `width=4zw` を消す | 終了コード 0、診断なし |

旧コードを期待する試験は modules/golem-eval/test/FileSpec.hs:503（値）と FileSpec.hs:504, 183（組み合わせ）である。
修正提案：値の条件は G02087 に残し、組み合わせの条件には新しい番号を振る。

### G02090
`@channel` の名前をどのプラグインも宣言していない誤りと、名前の数の誤りを一つのコードにまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 宣言のない名前 | plugins/glossary.wasm を plugins/ に写して manifest.toml に `[plugins.glossary]` の `path` と `data = { terms = "data/terms.tsv" }` を書き、一行の data/terms.tsv を置き、`@channel unknown` を足す | `golem check --format json` | 1 | `G02090` 一件（tempest.gm 3228:1、宣言されていないチャネルです: unknown） | `@channel glossary` にする | 終了コード 0、診断なし |
| 名前が二つ | 同じプラグインを置き、`@channel glossary people` を足す | `golem check --format json` | 1 | `G02090` 一件（tempest.gm 3228:1、@channel にはチャネルの名前を一つ書きます） | `@channel glossary` にする | 終了コード 0、診断なし |
| 名前がない | 同じプラグインを置き、`@channel` を足す | `golem check --format json` | 1 | `G02090` 一件（tempest.gm 3228:1、@channel にはチャネルの名前を一つ書きます） | `@channel glossary` にする | 終了コード 0、診断なし |

旧コードを期待する試験は modules/golem-eval/test/FileSpec.hs:697 から 699（宣言のない名前）と FileSpec.hs:700 から 702（名前の数）である。
modules/golem-driver/test/PluginsSpec.hs:144 は、プラグインの読み込みが失敗したときに G02090 を出さないことを確かめている。
修正提案：宣言のない名前の条件は G02090 に残し、名前の数の条件には新しい番号を振る。

### G02092
`@blank-line` の本体の誤り、引数の数か形の誤り、数でない語の誤りを一つのコードにまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 本体を書いた | `@blank-line` の行と、字下げした `あ` の行を足す | `golem check --format json` | 1 | `G02092` 一件（tempest.gm 3228:1、@blank-line は本体を持てません） | `あ` の字下げをやめ、空行を挟んで別の段落にする | 終了コード 0、診断なし |
| 引数を二つ書いた | `@blank-line 1 2` を足す | `golem check --format json` | 1 | `G02092` 一件（tempest.gm 3228:1） | `@blank-line 2` にする | 終了コード 0、`G04009` 一件（お知らせ、本の最後の @blank-line） |
| 数でない語 | `@blank-line x` を足す | `golem check --format json` | 1 | `G02092` 一件（tempest.gm 3228:1） | `@blank-line 1` にする | 終了コード 0、`G04009` 一件（お知らせ、本の最後の @blank-line） |

修正後の `G04009` は、`@blank-line` を本の最後に置いたことによるお知らせであり、G02092 とは関係しない。
旧コードを期待する試験は modules/golem-eval/test/FileSpec.hs:1580 から 1587、FileSpec.hs:1591 から 1593、modules/golem-eval/test/NaturalSpec.hs:104 から 109 である。
修正提案：本体の条件は、ほかの改ページのコマンドと同じく既存の G02097 に移す。
引数の数か形の条件と数でない語の条件は、一方を G02092 に残し、もう一方に新しい番号を振る。

### G02099
`@page-lines` の引数の数か形の誤りと、値が符号を付けた 0 でない整数でない誤りを一つのコードにまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 引数を二つ書いた | `@page-lines +1 +2` を足す | `golem check --format json` | 1 | `G02099` 一件（tempest.gm 3228:1） | `@page-lines +1` にする | 終了コード 0、診断なし |
| 符号がない | `@page-lines 1` を足す | `golem check --format json` | 1 | `G02099` 一件（tempest.gm 3228:1） | `@page-lines +1` にする | 終了コード 0、診断なし |

旧コードを期待する試験は modules/golem-eval/test/FileSpec.hs:1532 から 1534 と FileSpec.hs:1544 である。
modules/golem-driver/test/DiagnosticsSpec.hs:406 から 409 は、このコードが使用中であることだけを確かめている。
修正提案：値の形の条件は G02099 に残す。
引数の数とキーワード引数の条件には新しい番号を振り、G02058 と G02070 の同じ条件と共通にしてよい。

### G02110
範囲の端の欠けや読めない形（構文の誤り）と、端の値が数でないこと（評価の型の誤り）を一つのコードにまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| A 端がない | tempest.gm の末尾に `set r = 5...` を足した | `golem check --format json` | 1 | `G02110 一件（tempest.gm 3228:13）` | 端を書き足して `set r = 5...7` にした | 終了コード 0、診断なし |
| B 端の値が数でない | tempest.gm の末尾に `set r = "a"...3` を足した | `golem check --format json` | 1 | `G02110 一件（tempest.gm 3228:9）` | 端の値を数に替えて `set r = 1...3` にした | 終了コード 0、診断なし |

旧コードを期待する試験は modules/golem-parser/test/ParserSpec.hs:324、modules/golem-eval/test/RangeSpec.hs:97、modules/golem-eval/test/RangeSpec.hs:132、modules/golem-eval/test/RangeSpec.hs:136 である。
修正提案：構文の誤りと語の項目の読めない端（A）は G02110 に残し、評価で端の値が数でないもの（B、modules/golem-eval/src/Golem/Eval/Expr.hs:171、modules/golem-eval/src/Golem/Eval/Analysis.hs:159、modules/golem-eval/src/Golem/Eval/File.hs:3019）に新しい番号を振る。
RangeSpec.hs:132 の一覧にある `lines=[= "a"...3]` は B に移る。

### G02124
`[link]` の引数の数と形の誤りと、URL が文字列でないこと（引用符の書き忘れ）を一つのコードにまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| A URL がない | tempest.gm の末尾に `[link: 例]` を足した | `golem check --format json` | 1 | `G02124 一件（tempest.gm 3228:1）` | URL を書き足して `[link "https://example.com/": 例]` にした | 終了コード 0、診断なし |
| A2 URL が二つある | tempest.gm の末尾に `[link "https://a.example/" "https://b.example/": 例]` を足した | `golem check --format json` | 1 | `G02124 一件（tempest.gm 3228:1）` | 二つめの URL を消した | 終了コード 0、診断なし |
| B URL が文字列でない | tempest.gm の末尾に `[link https://example.com/: 例]` を足した | `golem check --format json` | 1 | `G02124 一件（tempest.gm 3228:1）` | URL を引用符で囲んだ | 終了コード 0、診断なし |

旧コードを期待する試験は modules/golem-eval/test/LinkSpec.hs:49、modules/golem-eval/test/LinkSpec.hs:52 である。
修正提案：引数の数とキーワード引数の誤り（A、A2）は G02124 に残し、URL の値が文字列でない誤り（B）に新しい番号を振る。
今の引用符の手がかりの文言は、B の新しい番号に移す。

### G02131
言語のタグの数の誤りと、タグを式で書いた誤りを一つのコードにまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| A タグが二つある | tempest.gm の末尾に `[lang en fr: x]` を足した | `golem check --format json` | 1 | `G02131 一件（tempest.gm 3228:1）` | タグを一つにして `[lang en: x]` にした | 終了コード 0、診断なし |
| B タグを式で書いた | tempest.gm の末尾に `[lang [= "en"]: x]` を足した | `golem check --format json` | 1 | `G02131 一件（tempest.gm 3228:1）` | 式をやめて語で `[lang en: x]` と書いた | 終了コード 0、診断なし |

旧コードを期待する試験は modules/golem-eval/test/LangSpec.hs:81、modules/golem-eval/test/LangSpec.hs:142 である。
修正提案：タグの数とキーワード引数の誤り（A）は G02131 に残し、式やコマンドで書いたタグ（B）には新しい番号を振るか、評価の前の値を語か文字列で書く誤り（G02116）と同じ原因として扱う。

### G02133
図版の `width` の書き方の誤りと、読める値が 0 であることを一つのコードにまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| A 単位がない | modules/golem-driver/test/fixtures/figures/images/gray.png を images/a.png に写し、tempest.gm の末尾に `@nonumber` と `@figure images/a.png alt=x width=50` の二行を足した | `golem check --format json` | 1 | `G02133 一件（tempest.gm 3229:28）` | 単位を書き足して `width=50%` にした | 終了コード 0、診断なし |
| B 値が 0 | A と同じ画像を置き、tempest.gm の末尾に `@nonumber` と `@figure images/a.png alt=x width=0zw` の二行を足した | `golem check --format json` | 1 | `G02133 一件（tempest.gm 3229:28）` | 0 より大きい値の `width=12zw` にした | 終了コード 0、診断なし |

`@nonumber` を付けないと、章の外の図版の番号の誤り（G04004）が修正後にも残るので、条件の行に `@nonumber` を足した。
旧コードを期待する試験は modules/golem-eval/test/FileSpec.hs:506、modules/golem-eval/test/FileSpec.hs:522、modules/golem-eval/test/FileSpec.hs:524、modules/golem-driver/test/PageElementsSpec.hs:861 である。
修正提案：寸法として読めない値（A）は G02133 に残し、読めるが 0 の値（B）に新しい番号を振る。
G02135 の 0 の幅と同じ原因なので、二つで一つの新しい番号を使ってよい。

### G02135
`@column-widths` の値の書き方の誤り、0 の幅、式で書いた値を一つのコードにまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| A 読めない値 | tempest.gm の末尾に `@column-widths wide auto` と二列の表（見出し、区切り、一行）を足した | `golem check --format json` | 1 | `G02135 一件（tempest.gm 3228:16）` | `wide` を `auto` にした | 終了コード 0、診断なし |
| B 0 の幅 | 同じ表の前に `@column-widths 0zw auto` を足した | `golem check --format json` | 1 | `G02135 一件（tempest.gm 3228:16）` | `0zw` を `12zw` にした | 終了コード 0、診断なし |
| C 式で書いた値 | 同じ表の前に `@column-widths [= 3] auto` を足した | `golem check --format json` | 1 | `G02135 一件（tempest.gm 3228:16）` | 式をやめて語で `3zw` と書いた | 終了コード 0、診断なし |

旧コードを期待する試験は modules/golem-eval/test/TableAttributesSpec.hs:57、modules/golem-eval/test/TableAttributesSpec.hs:59、modules/golem-eval/test/TableAttributesSpec.hs:79 である。
修正提案：読めない値（A）は G02135 に残し、0 の幅（B）には新しい番号を振る（G02133 の B と共に使ってよい）。
式で書いた値（C）には新しい番号を振るか、G02116 と同じ原因として扱う。

### G02142
注の名前の数の誤り、式で書いた名前、名前に使えない字を一つのコードにまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| A 名前が二つある | tempest.gm の末尾に `本文[note a b]。` と、字下げした本文を持つ `@note a` を足した | `golem check --format json` | 1 | `G02142 一件（tempest.gm 3228:3）`、`G02138 一件（tempest.gm 3230:1）` | 名前を一つにして `[note a]` にした | 終了コード 0、診断なし |
| B 名前を式で書いた | tempest.gm の末尾に `本文[note [= 1]]。` と、字下げした本文を持つ `@note a` を足した | `golem check --format json` | 1 | `G02142 一件（tempest.gm 3228:3）`、`G02138 一件（tempest.gm 3230:1）` | 式をやめて語で `[note a]` と書いた | 終了コード 0、診断なし |
| C 名前に大文字がある | tempest.gm の末尾に `本文[note Ab]。` と、字下げした本文を持つ `@note Ab` を足した | `golem check --format json` | 1 | `G02142 二件（tempest.gm 3228:3、3230:1）` | 両方の名前を `ab` にした | 終了コード 0、診断なし |

A と B の G02138 は、誤った `[note]` が `@note a` を指さないために重なって出たものである。
旧コードを期待する試験は modules/golem-eval/test/NoteSpec.hs:68 から modules/golem-eval/test/NoteSpec.hs:73 である。
C を期待する試験はない。
修正提案：名前の数の誤り（A）は G02142 に残し、使えない字を含む名前（C、modules/golem-eval/src/Golem/Eval/File.hs:1531 の validLabel の違反）に新しい番号を振る。
式で書いた名前（B）には新しい番号を振るか、G02116 と同じ原因として扱う。

### G02148
`page` の値の型が頁でないことと、数が頁の範囲の外にあることを一つのコードにまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| A 型が頁でない | manifest.toml の先頭に `bibliography = ["refs.json"]` を足し、キー `a` の項目を一つ持つ refs.json を置き、tempest.gm の末尾に `[cite a page=[= true]]` を足した | `golem check --format json` | 1 | `G02148 一件（tempest.gm 3228:1）` | 頁の数を書いて `page=5` にした | 終了コード 0、診断なし |
| A2 空の文字列 | A と同じ書誌データを置き、tempest.gm の末尾に `[cite a page=""]` を足した | `golem check --format json` | 1 | `G02148 一件（tempest.gm 3228:1）` | 空でない文字列の `page=xii` にした | 終了コード 0、診断なし |
| B 負の数 | A と同じ書誌データを置き、tempest.gm の末尾に `[cite a page=-1]` を足した | `golem check --format json` | 1 | `G02148 一件（tempest.gm 3228:1）` | 0 以上の `page=1` にした | 終了コード 0、診断なし |
| B2 整数でない数 | A と同じ書誌データを置き、tempest.gm の末尾に `[cite a page=[= 1/2]]` を足した | `golem check --format json` | 1 | `G02148 一件（tempest.gm 3228:1）` | 整数の `page=1` にした | 終了コード 0、診断なし |

旧コードを期待する試験は modules/golem-eval/test/CiteSpec.hs:55、modules/golem-eval/test/CiteSpec.hs:69、modules/golem-eval/test/CiteSpec.hs:71 である。
修正提案：頁の型の誤りと空の文字列（A、A2）は G02148 に残し、負の数と整数でない数（B、B2）に新しい番号を振るか、自然数の負の数（G02103）と整数でない数（G02104）に寄せる。

### G03001
manifest.toml の TOML の構文、スキーマ、値の検査、ターゲットの有無、章の重複、printings の順、未定義のフィルタ名という八つの原因を一つのコードにまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 TOML の構文 | manifest.toml の一行目を `chapters = ["tempest.gm"` にした（文言は `TOML の誤りです: ここに'['は書けません`） | `golem check --format json` | 1 | `G03001 一件（manifest.toml 3:1）` | 配列を閉じた | 終了コード 0、診断なし |
| 2 必須のキーの欠け | manifest.toml の `title = "The Tempest"` を消した（文言は `必須のキーがありません: metadata.title`） | `golem check --format json` | 1 | `G03001 一件（manifest.toml 3:2）` | `title` を書き戻した | 終了コード 0、診断なし |
| 3 未知のキー | manifest.toml の二行目に `bogus = 1` を足した（文言は `知らないキーです: bogus`） | `golem check --format json` | 1 | `G03001 一件（manifest.toml 2:1）` | `bogus` を消した | 終了コード 0、診断なし |
| 4 語彙の外の役割 | manifest.toml の `role = "author"` を `role = "writer"` にした（文言は `役割は author、translator、…のどれかです: writer`） | `golem check --format json` | 1 | `G03001 一件（manifest.toml 11:8）` | 表の語の `author` に戻した | 終了コード 0、診断なし |
| 4b 許されない pdfa | manifest.toml の `[targets.pdf]` に `pdfa = "1b"` を足した | `golem check --format json` | 1 | `G03001 一件（manifest.toml 18:8）` | `pdfa` を消した | 終了コード 0、診断なし |
| 5 ターゲットがない | manifest.toml の `[targets.*]` と `variants` の行を消し、空の `[targets]` を足した（文言は `出力ターゲットが一つもありません`） | `golem check --format json` | 1 | `G03001 一件（manifest.toml 1:1）` | ターゲットの表を書き戻した | 終了コード 0、診断なし |
| 6 章の重複 | manifest.toml の一行目を `chapters = ["tempest.gm", { file = "tempest.gm", paragraph-separator = "line" }]` にした | `golem check --format json` | 1 | `G03001 一件（manifest.toml 1:1）` | 章を一つに戻した | 終了コード 0、診断なし |
| 7 printings の順 | `[[metadata.printings]]` を、1 版 2 刷、1 版 1 刷の順に二つ足した | `golem check --format json` | 1 | `G03001 一件（manifest.toml 18:12）` | 1 版 1 刷、1 版 2 刷の順に並べ替えた | 終了コード 0、診断なし |
| 8 未定義のフィルタ | `pub filter k :: Blocks -> Blocks` を持つ f.emet を置き、manifest.toml に `function = "f.emet"`、`filter = "nothing"`、`files = ["tempest.gm"]` の `[[filters]]` を足した（文言は `function の .emet にないフィルタです: f.emet の nothing`） | `golem check --format json` | 1 | `G03001 一件（manifest.toml 1:1）` | `filter = "k"` にした | 終了コード 0、診断なし |

旧コードを期待する試験は modules/golem-project/test/Main.hs:95、modules/golem-project/test/Main.hs:144、modules/golem-project/test/Main.hs:167、modules/golem-project/test/Main.hs:215、modules/golem-project/test/Main.hs:217、modules/golem-project/test/Main.hs:241、modules/golem-project/test/Main.hs:275、modules/golem-project/test/Main.hs:412、modules/golem-project/test/Main.hs:438、modules/golem-project/test/Main.hs:440、modules/golem-project/test/Main.hs:706、modules/golem-project/test/Main.hs:711、modules/golem-project/test/ColophonSpec.hs:92、modules/golem-project/test/ColophonSpec.hs:100、modules/golem-project/test/ColophonSpec.hs:108、modules/golem-project/test/NaturalKeySpec.hs:70、modules/golem-project/test/FunctionsSpec.hs:48、modules/golem-project/test/FunctionsSpec.hs:50、modules/golem-project/test/VarsSpec.hs:78、modules/golem-driver/test/CallsSpec.hs:235、modules/golem-driver/test/CallsSpec.hs:244、modules/golem-cli/test/Main.hs:564 である（試験の中に G03001 を書いた行は 62 行あり、ここに挙げたのはその代表である）。
修正提案：TOML の構文の誤り（1）は G03001 に残し、必須のキーの欠け（2）、未知のキー（3）、値の誤り（4、4b と型の誤り）、ターゲットがないこと（5）、章の重複の設定の食い違い（6）、printings の順（7）、未定義のフィルタ名（8）のそれぞれに新しい番号を振る。
未定義のフィルタ名（8）は未定義の名前の誤りなので、G03007 と並べて番号を決める。

### G03006
style.toml の TOML の構文、未知のキー、型、値の範囲、二つのキーの組み合わせ、廃止した欄、スタイルの名前の形という七つの原因を一つのコードにまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 TOML の構文 | style.toml の末尾に、二つめの `[page]` を `bleed = "3mm"` とともに足した（文言は `TOML の誤りです: 閉じた表にキーを足しています: page`） | `golem check --format json` | 1 | `G03006 一件（style.toml 21:2）` | 二つめの `[page]` を消した | 終了コード 0、診断なし |
| 2 未知のキー | style.toml の `[page]` に `unknown = 1` を足した（文言は `知らないキーです: page.unknown`） | `golem check --format json` | 1 | `G03006 一件（style.toml 4:1）` | `unknown` を消した | 終了コード 0、診断なし |
| 3 型の誤り | style.toml の `binding = "left"` を `binding = 1` にした（文言は `page.binding には文字列を書きます（整数が書かれています）`） | `golem check --format json` | 1 | `G03006 一件（style.toml 3:11）` | 文字列の `"left"` に戻した | 終了コード 0、診断なし |
| 4 値の範囲の外 | style.toml の末尾に `[color.swatches]` と `a = { cmyk = [0, 0, 0, 101] }` を足した（文言は `cmyk は 0 から 100 までの整数四つです`） | `golem check --format json` | 1 | `G03006 一件（style.toml 22:14）` | 101 を 100 にした | 終了コード 0、診断なし |
| 5 二つのキーの組み合わせ | style.toml の `[page.grid]` を `columns = 2`、`characters = 14` にした（文言は `columns が 2 以上のときは column-gap が要ります`） | `golem check --format json` | 1 | `G03006 一件（style.toml 11:11）` | `column-gap = "2zw"` を足した | 終了コード 0、診断なし |
| 6 廃止した欄 | style.toml の末尾に `[emphasis]` と `style = "sesame"` を足した（文言は `[emphasis] は廃止しました。` で始まる） | `golem check --format json` | 1 | `G03006 一件（style.toml 21:2）` | `[emphasis]` を消した | 終了コード 0、診断なし |
| 7 スタイルの名前の形 | style.toml の末尾に `[paragraph-styles.Body]` と `size = "10pt"` を足した（文言は `スタイルの名前は英小文字で始まり、英小文字、数字、- だけからなります: Body`） | `golem check --format json` | 1 | `G03006 一件（style.toml 21:19）` | 名前を `body2` にした | 終了コード 0、診断なし |

条件 5 で `characters = 30` のまま段を二つにすると、`column-gap` を足した後に版面のはみ出し（G07001）が残るので、字数も条件の側で減らした。
旧コードを期待する試験は modules/golem-project/test/Main.hs:645、modules/golem-project/test/Main.hs:748、modules/golem-project/test/Main.hs:753、modules/golem-project/test/Main.hs:983、modules/golem-project/test/StyleSchemaSpec.hs:180、modules/golem-project/test/StyleSchemaSpec.hs:182、modules/golem-project/test/StyleSchemaSpec.hs:187、modules/golem-project/test/StyleSchemaSpec.hs:191、modules/golem-project/test/StyleSchemaSpec.hs:195 である（試験の中に G03006 を書いた行は 265 行あり、ここに挙げたのはその代表である）。
修正提案：TOML の構文の誤り（1）は G03006 に残し、未知のキーと表（2）、型の誤り（3）、値の範囲の外（4）、二つのキーの組み合わせ（5）、廃止した欄（6）、スタイルの名前の形（7）のそれぞれに新しい番号を振る。
値の検査の文言は四十を超えるので、文言ごとに 3 から 7 のどれに寄せるかを決める必要がある。

### G03010
G03010 は、HTML と EPUB に同梱するフォントのファイルがない場合と、フォントのパスがプロジェクトルートの外を指す場合をまとめている。
どちらも modules/golem-driver/src/Golem/Driver.hs:1067 が出し、文言は Driver.hs:1072 の `report` が選ぶ。
この二つは G08002 の二つの条件と同じ混ざり方であり、G08002 の再現の際に見つけた。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| ファイルがない | style.toml の `latin` を `"fonts/none.ttf"` にした | `golem build --target html --format json` | 0 | G03010 一件（警告、フォントのファイルがない） | fonts/none.ttf にフォントのファイルを置いた | 終了コード 0、診断なし |
| ルートの外を指す | style.toml の `latin` を `"../x.ttf"` にした | `golem build --target html --format json` | 0 | G03010 一件（警告、プロジェクトルートの外を指す） | `latin` をルートの中の `"fonts/SourceSerifVariable-Roman.ttf"` に戻した | 終了コード 0、診断なし |

ルートの外の `../x.ttf` にフォントのファイルを置いても、G03010 は消えなかった。
したがって、ファイルを置くという修正はルートの外の条件には効かない。
旧コードを期待する試験は、modules/golem-driver/test/BuildSpec.hs:258、279、290 と modules/golem-cli/test/Main.hs:287、291 である。
どれもファイルがない条件を見ており、ルートの外の条件を見る試験はない。
修正提案：ファイルがない条件は G03010 に残す。
ルートの外を指す条件は、G08002 と G08006 のパスの形の条件と同じ扱いにし、G03003 に寄せるか、共通の新しい番号にする。

### G03013
G03013 は、参照先のない名前、based-on の循環、禁じられた based-on の三つの原因をまとめている。
どれも modules/golem-project/src/Golem/Project/Style.hs:3142 の `styleReferenceChecks` が出す。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 参照先がない | style.toml の末尾に `[character-styles.a]` と `based-on = "nope"` を足した | `golem check --format json` | 1 | G03013 一件（style.toml 22:12） | based-on を `"bold"` にした | 終了コード 0、診断なし |
| based-on の循環 | style.toml の末尾に `[character-styles.a]` の `based-on = "b"` と `[character-styles.b]` の `based-on = "a"` を足した | `golem check --format json` | 1 | G03013 一件（style.toml 22:12） | b の based-on を消して循環を断った | 終了コード 0、診断なし |
| based-on に code を書いた | style.toml の末尾に `[paragraph-styles.x]` と `based-on = "code"` を足した | `golem check --format json` | 1 | G03013 一件（style.toml 22:12） | based-on を `"body"` にした | 終了コード 0、診断なし |
| body に based-on を書いた | style.toml の末尾に `[paragraph-styles.body]` と `based-on = "verse"` を足した | `golem check --format json` | 1 | G03013 一件（style.toml 22:12） | based-on の行を消した | 終了コード 0、診断なし |

旧コードを期待する試験は、modules/golem-project/test/Main.hs:1151、1185、1186、1444、1445、1446、1447、1448、1513、1514、1898、1900、1978、2030、2031、2039、2097、2098、2264、2265、2266、2271、2313、2323、2342、2428、2429、2431、2451 と modules/golem-eval/test/FileSpec.hs:1242 である。
このうち循環を見るのは Main.hs:1445、1446、2266、2429、2451 であり、禁じられた based-on を見るのは Main.hs:1447 と 1898 である。
修正提案：参照先がない誤りは G03013 に残す。
based-on の循環は、文字スタイル、段落スタイル、アキ量のセットに共通の新しい番号にする。
body の based-on と based-on の code は、もう一つの新しい番号にする。

### G03014
G03014 は、柱の内容の値の誤りと、content、even、odd の組み合わせの誤りをまとめている。
値の誤りは modules/golem-project/src/Golem/Project/Style.hs:2256、2257、2261、2263、2266、2267 が出し、組み合わせの誤りは Style.hs:2281 の `wrong` が出す。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 内容の値が語彙にない | style.toml の末尾に `[masters.body.running-head]` を足し、`position = "top-outside"` と `content = "chapter"` を書いた | `golem check --format json` | 1 | G03014 一件（style.toml 23:11） | content を `"heading.1.short"` にした | 終了コード 0、診断なし |
| even だけを書いた | style.toml の末尾に `[masters.body.running-head]` を足し、`position = "top-outside"` と `even = "title"` を書いた | `golem check --format json` | 1 | G03014 一件（style.toml 21:15） | `odd = "heading.1.short"` を足した | 終了コード 0、診断なし |

旧コードを期待する試験は、modules/golem-project/test/Main.hs:511 から 514、516 から 520、522 から 525、556 から 576 と modules/golem-project/test/StylePositionSpec.hs:69 である。
このうち組み合わせの誤りを見るのは Main.hs:522 から 525 と StylePositionSpec.hs:69 である。
修正提案：値の語彙と書式の誤りは G03014 に残す。
content、even、odd の組み合わせの誤りは、新しい番号にする。

### G03015
G03015 は、方言の外の構文、正規表現としての誤り、照合の上限の超過をまとめている。
どれも modules/golem-project/src/Golem/Project/Style.hs:3442 が、golem-regex の `RegexError` の文言を添えて出す。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 方言の外の構文 | style.toml の末尾に `[paragraph-styles.body]` と `regex-styles = [{ pattern = '\1', style = "bold" }]` を足した | `golem check --format json` | 1 | G03015 一件（style.toml 22:29） | 後方参照を使わない `'(a)a'` に書き換えた | 終了コード 0、診断なし |
| 括弧が閉じていない | 同じ行の pattern を `'(a'` にした | `golem check --format json` | 1 | G03015 一件（style.toml 22:29） | 括弧を閉じて `'(a)'` にした | 終了コード 0、診断なし |
| 繰り返しの回数が上限を超える | 同じ行の pattern を `'a{70000}'` にした | `golem check --format json` | 1 | G03015 一件（style.toml 22:29） | 回数を減らして `'a{7}'` にした | 終了コード 0、診断なし |

旧コードを期待する試験は、modules/golem-project/test/Main.hs:2312、2317、2319、2342、modules/golem-project/test/StylePositionSpec.hs:121、modules/golem-eval/test/FileSpec.hs:1234、1242 である。
括弧の閉じない正規表現を G03015 として見る試験は見当たらない。
修正提案：方言の外の構文は G03015 に残す。
正規表現としての誤りと、上限の超過は、それぞれ新しい番号にする。
`RegexError` は位置と文言しか持たないので、分けるには modules/golem-regex に誤りの種類を足す必要がある。

### G03017
G03017 は、判型の名前の誤り、width か height の欠け、寸法の範囲の誤り、`[page.size]` の未知のキーをまとめている。
名前と寸法の誤りは modules/golem-project/src/Golem/Project/Style.hs:1746、1751、1757、1759 が出し、未知のキーと型の誤りは Style.hs:2833 の codeAt が G03017 にする。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 判型の名前が表にない | style.toml の `size = "A5"` を `size = "A3"` にした | `golem check --format json` | 1 | G03017 一件（style.toml 2:8） | `"A5"` に戻した | 終了コード 0、診断なし |
| height がない | style.toml の size を `{ width = "148mm" }` にした | `golem check --format json` | 1 | G03017 一件（style.toml 2:8） | `height = "210mm"` を足した | 終了コード 0、診断なし |
| 幅が 0 である | style.toml の size を `{ width = "0mm", height = "210mm" }` にした | `golem check --format json` | 1 | G03017 一件（style.toml 2:8） | width を `"148mm"` にした | 終了コード 0、診断なし |
| 未知のキーがある | style.toml の size を `{ width = "148mm", height = "210mm", depth = "1mm" }` にした | `golem check --format json` | 1 | G03017 一件（style.toml 2:45） | depth を消した | 終了コード 0、診断なし |

旧コードを期待する試験は、modules/golem-project/test/Main.hs:763、2505 から 2515、2516 から 2520、2531、modules/golem-project/test/StylePositionSpec.hs:53、modules/golem-project/test/StyleSchemaSpec.hs:183 と 184、modules/golem-driver/test/PdfSpec.hs:702 である。
修正提案：判型の名前の誤りと値の型の誤りは G03017 に残す。
width か height の欠けと、寸法の範囲の誤りは、それぞれ新しい番号にする。
`[page.size]` の未知のキーは codeAt から外し、ほかの未知のキーと同じコードにする。

### G03020
G03020 は、アキの量の値、量の順序、クラス、組み込みのセットの名前、寸法の欄のアキの名前、`[aki-sets]` の未知のキーをまとめている。
アキの誤りは modules/golem-project/src/Golem/Project/Style.hs:1769、1806、1807、1815、1827、2522 の `akiError` の文言を Style.hs:2829 が G03020 にし、`[aki-sets]` の下の誤りは Style.hs:2837 の codeAt が G03020 にする。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 量が読めない | style.toml の末尾に `[aki-sets.mine]` と `rules = [{ before = "kana", after = "kana", optimum = "十分" }]` を足した | `golem check --format json` | 1 | G03020 一件（style.toml 22:55） | optimum を `"四分"` にした | 終了コード 0、診断なし |
| 量の順序の誤り | 同じ規則を `optimum = "四分", minimum = "二分"` にした | `golem check --format json` | 1 | G03020 一件（style.toml 22:71） | `optimum = "二分", minimum = "四分"` にした | 終了コード 0、診断なし |
| 未知のクラス | 同じ規則の before を `"kanji"` にし、optimum を `"四分"` にした | `golem check --format json` | 1 | G03020 一件（style.toml 22:21） | before を `"ideograph"` にした | 終了コード 0、診断なし |
| 組み込みのセットと同じ名前 | style.toml の末尾に `[aki-sets.gyomatsu-yakumono-zenkaku]` を足した | `golem check --format json` | 1 | G03020 一件（style.toml 21:11） | `[aki-sets.mine]` に改め、`based-on = "gyomatsu-yakumono-zenkaku"` を書いた | 終了コード 0、診断なし |
| 寸法の欄のアキの名前 | style.toml の末尾に `[paragraph-styles.body]` と `indent = "二分"` を足した | `golem check --format json` | 1 | G03020 一件（style.toml 22:10） | indent を `"0.5zw"` にした | 終了コード 0、診断なし |
| `[aki-sets]` の未知のキー | style.toml の末尾に `[aki-sets.mine]` と `base = "x"` を足した | `golem check --format json` | 1 | G03020 一件（style.toml 22:1） | base の行を消した | 終了コード 0、診断なし |

旧コードを期待する試験は、modules/golem-project/test/Main.hs:2249 から 2257、2261、modules/golem-project/test/StylePositionSpec.hs:56、57、76、modules/golem-eval/test/DiagnosticSitesSpec.hs:45 から 47 である。
このうち量の順序を見るのは Main.hs:2249 と 2250 であり、クラスを見るのは Main.hs:2251 から 2254 と StylePositionSpec.hs:56 であり、組み込みの名前を見るのは Main.hs:2256、2257 と StylePositionSpec.hs:57 であり、寸法の欄を見るのは Main.hs:2261、StylePositionSpec.hs:76、DiagnosticSitesSpec.hs:47 である。
`[aki-sets]` の未知のキーを見る試験は見当たらない。
修正提案：読めない量と負の量は G03020 に残す。
量の順序、クラスの誤り、組み込みのセットと同じ名前、寸法の欄のアキの名前は、それぞれ新しい番号にする。
`[aki-sets]` の未知のキーは codeAt から外し、ほかの未知のキーと同じコードにする。

### G03022
G03022 は、`[lists]` の値の誤りと、`[lists]` の未知のキーをまとめている。
値の誤りは modules/golem-project/src/Golem/Project/Style.hs:2426 の `bad` が出し、未知のキーは Style.hs:2835 の codeAt が G03022 にする。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 番号の差し込みがない | style.toml の末尾に `[lists]` と `numbers = ["x"]` を足した | `golem check --format json` | 1 | G03022 一件（style.toml 22:11） | numbers を `["{n}."]` にした | 終了コード 0、診断なし |
| 未知のキー | style.toml の末尾に `[lists]` と `bullet = ["・"]` を足した | `golem check --format json` | 1 | G03022 一件（style.toml 22:1） | キーを `bullets` に直した | 終了コード 0、診断なし |

旧コードを期待する試験は、modules/golem-project/test/Main.hs:1577 から 1589 と modules/golem-project/test/StylePositionSpec.hs:73、74 である。
`[lists]` の未知のキーを見る試験は見当たらない。
修正提案：bullets、numbers、gap の値の誤りは G03022 に残す。
`[lists]` の未知のキーは codeAt から外し、ほかの未知のキーと同じコードにする。

### G03024
G03024 は、コードの形でない要素、抑制できないコード、もう一方の一覧に書くコードをまとめている。
形の誤りは modules/golem-project/src/Golem/Project/Manifest.hs:523 と 527 が出し、抑制できないコードともう一方の一覧のコードは Manifest.hs:525 が出す。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| コードの形でない | manifest.toml の末尾に `[diagnostics]` と `silence-notices = ["g02062"]` を足した | `golem check --format json` | 1 | G03024 一件（manifest.toml 23:20） | 大文字の `"G02062"` に書き直した | 終了コード 0、診断なし |
| 抑制できないコード | manifest.toml の末尾に `[diagnostics]` と `silence-notices = ["G01001"]` を足した | `golem check --format json` | 1 | G03024 一件（manifest.toml 23:20） | 要素を消して `[]` にした | 終了コード 0、診断なし |
| もう一方の一覧のコード | manifest.toml の末尾に `[diagnostics]` と `silence-notices = ["G07047"]` を足した | `golem check --format json` | 1 | G03024 一件（manifest.toml 23:20） | `silence-info = ["G07047"]` に移した | 終了コード 0、診断なし |

旧コードを期待する試験は、modules/golem-project/test/Main.hs:186 から 196、197 から 201、203 から 209、219 から 222、463 から 467、469 から 478、486、487、modules/golem-driver/test/DiagnosticsSpec.hs:233 から 236、modules/golem-lsp/test/TomlSpec.hs:119 である。
修正提案：抑制できないコードは G03024 に残す。
コードの形でない要素と文字列でない要素は、新しい番号にする。
もう一方の一覧に書くコードも、新しい番号にする。

### G03026
G03026 は、参考文献のファイルがないこと、JSON として読めないこと、最上位が配列でないことをまとめている。
modules/golem-driver/src/Golem/Driver.hs:732 と 737 がファイルのない誤りを、Driver.hs:738 が JSON の誤りを、Driver.hs:739 が配列でない誤りを出す。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| ファイルがない | manifest.toml の chapters の次の行に `bibliography = ["refs.json"]` を足し、refs.json を置かなかった | `golem check --format json` | 1 | G03026 一件（manifest.toml 1:1） | 中身が `[]` の refs.json を置いた | 終了コード 0、診断なし |
| JSON として読めない | 同じ行を足し、中身が `{` の refs.json を置いた | `golem check --format json` | 1 | G03026 一件（manifest.toml 1:1） | refs.json の中身を `[]` にした | 終了コード 0、診断なし |
| 最上位が配列でない | 同じ行を足し、中身が `{}` の refs.json を置いた | `golem check --format json` | 1 | G03026 一件（manifest.toml 1:1） | refs.json の中身を `[]` にした | 終了コード 0、診断なし |

旧コードを期待する試験は、modules/golem-driver/test/ReferencesSpec.hs:256 から 258、260 から 265、270 から 274 である。
修正提案：ファイルがない誤りは G03026 に残す。
JSON として読めない誤りと、最上位が配列でない誤りは、それぞれ新しい番号にする。

### G03256
G03256 は、組版用の値の宣言についての五つの誤りを一つのコードに束ねている。
束ねているのは、表の形の誤り、宣言値の種類や範囲の誤り、宣言の循環、宣言の中の未定義の名前、宣言の中の種類の違う参照である。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| A 表の形の誤り | style.toml の末尾に `[values.size]` と `a = "1zw"` を足す | `golem check --format json` | 1 | `G03256` 一件（style.toml 21:9、`values.size は length、aki、count の表にします`） | 表の名前を `[values.length]` に直す | 終了コード 0、診断なし |
| B 宣言値が種類に合わない | style.toml の末尾に `[values.count]` と `rows = -1` を足す | `golem check --format json` | 1 | `G03256` 一件（style.toml 22:8、`宣言の値が種類に合いません`） | `rows = 1` にする | 終了コード 0、診断なし |
| B2 行数の加算が上限を超える | style.toml の末尾に `[values.count]` と `rows = 2147483647` と `more = "rows + 1"` を足す | `golem check --format json` | 1 | `G03256` 一件（style.toml 23:8、`行数が上限を超えています`） | `rows = 2147483646` にする | 終了コード 0、診断なし |
| C 宣言の循環 | style.toml の末尾に `[values.length]` と `a = "b"` と `b = "a"` を足す | `golem check --format json` | 1 | `G03256` 一件（style.toml 22:5、`値の宣言が循環しています: a → b → a`） | `a = "1zw"` にする | 終了コード 0、診断なし |
| D 宣言の中の未定義の名前 | style.toml の末尾に `[values.length]` と `a = "b"` を足す | `golem check --format json` | 1 | `G03256` 一件（style.toml 22:5、`値の名前がありません: b`） | `b = "1zw"` を宣言に足す | 終了コード 0、診断なし |
| E 宣言の中の種類の違う参照 | style.toml の末尾に `[values.aki]` と `half = "二分"`、`[values.length]` と `w = "half"` を足す | `golem check --format json` | 1 | `G03256` 一件（style.toml 24:5、`値 half の種類が違います: 要求 length、実際 aki`） | `w = "1zw"` にする | 終了コード 0、診断なし |

D と同じ誤りを欄に書くと、別のコードになる。
tempest の写しに `[paragraph-styles.quote]` と `indent = "missing"` を足すと、G03257 が一件出る（style.toml 22:10）。
E と同じ誤りを欄に書くと、G03258 が一件出る（style.toml 24:10）。
つまり、同じ原因が、宣言の中か欄の中かによって二つのコードに分かれている。

旧コードを期待する試験は modules/golem-project/test/Main.hs:920（C）、modules/golem-project/test/Main.hs:945（B）、modules/golem-project/test/Main.hs:950（B2）である。
A、D、E を確かめる試験はない。

修正提案：G03256 は B と B2（宣言値が種類か範囲に合わない）に残し、C の循環と A の表の形には、それぞれ新しい番号を振る。
D と E には新しい番号を作らない。
modules/golem-project/src/Golem/Project/Style.hs:2691 と modules/golem-project/src/Golem/Project/Style.hs:2694 の `if null stack` の分岐を消し、既存の G03257 と G03258 を出す。

### G07001
G07001 は、PDF の版面を計算できない理由のすべてを一つのコードに束ねている。
束ねている理由は、版面の節がないこと、grid の値の誤り、判型からのはみ出し、傍注を置けない組み方、脚注の区切り線の長さ、段落スタイルと見出しの罫線のはみ出しである。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| A 版面の節がない | style.toml から `[page.grid]` の節を消す | `golem check --format json` | 1 | `G07001` 一件（style.toml 1:1、`style.toml に [page.grid] がないため、版面を計算できません`） | `[page.grid]` の節を書き戻す | 終了コード 0、診断なし |
| B grid の文字の大きさが絶対的な寸法でない | style.toml の `font-size = "10pt"` を `"1zw"` にする | `golem check --format json` | 1 | `G07001` 一件（style.toml 1:1、`文字の大きさは絶対的な寸法で書いてください`） | `"10pt"` に戻す | 終了コード 0、診断なし |
| B2 字数が 0 | style.toml の `characters = 30` を `0` にする | `golem check --format json` | 1 | `G07001` 一件（style.toml 1:1、`字数、行数、段数は 1 以上、行送りは文字の大きさ以上にしてください`） | `30` に戻す | 終了コード 0、診断なし |
| C 版面が判型からはみ出す | style.toml の `characters = 30` を `40` にする | `golem check --format json` | 1 | `G07001` 一件（style.toml 1:1、`版面がページからはみ出しています`） | `30` に戻す | 終了コード 0、診断なし |
| D 段組みの版面に傍注がある | style.toml を `characters = 14`、`columns = 2`、`column-gap = "2zw"` にし、末尾に `[sidenotes]` と `width = "10mm"` と `gap = "2mm"` を足す | `golem check --format json` | 1 | `G07001` 一件（style.toml 1:1、`段組みの版面には傍注の領域を設けられません`） | `[sidenotes]` の節を消す | 終了コード 0、診断なし |
| E 脚注の区切り線が行長を超える | style.toml の末尾に `[notes.rule]` と `length = "31zw"` を足す | `golem check --format json` | 1 | `G07001` 一件（style.toml 1:1、`脚注の区切り線の length が行長を超えます`） | `length = "30zw"` にする | 終了コード 0、診断なし |
| F 段落スタイルの罫線が仕上がりの線を超える | style.toml の末尾に `[paragraph-styles.sec]` と `rule-before = { length = "40zw" }` を足す | `golem check --format json` | 1 | `G07001` 一件（style.toml 1:1、`段落スタイル sec の罫線が仕上がりの線を超えます`） | `length = "30zw"` にする | 終了コード 0、診断なし |

旧コードを期待する試験は modules/golem-layout-spec/test/Main.hs:86（A、B、C、縦組みの D）、modules/golem-layout-spec/test/Main.hs:109（段組みの D）、modules/golem-layout-spec/test/Main.hs:144（E）、modules/golem-layout-spec/test/Main.hs:154 と modules/golem-layout-spec/test/Main.hs:212 から modules/golem-layout-spec/test/Main.hs:234 まで（F）、modules/golem-layout-spec/test/GeometrySpec.hs:68、modules/golem-layout-spec/test/GeometrySpec.hs:70、modules/golem-layout-spec/test/GeometrySpec.hs:75（C と B）、modules/golem-driver/test/DiagnosticsSpec.hs:594 と modules/golem-driver/test/DiagnosticsSpec.hs:602（A）、modules/golem-driver/test/PageElementsSpec.hs:259（E）である。

修正提案：G07001 は A（`[page]` か `[page.grid]` がない）に残し、B、C、D、E、F には、それぞれ新しい番号を振る。
最初に当てはまった一つだけを報告する今の順は、分けた後も保てる。

### G06005
G06005 は、プラグインを読み込めない理由のすべてを一つのコードに束ねている。
束ねている理由には、作者が直すしかない壊れたモジュールと、版を合わせれば書き手が直せる ABI の違いの両方が含まれる。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| A import を求めるモジュール | import `env.now` を一つ持つ ABI 9 の wasm を p.wasm に置き、manifest.toml に `[plugins.p]` と `path = "p.wasm"` を足す | `golem check --format json` | 1 | `G06005` 一件（manifest.toml 1:1、`p: プラグインが import を要求しています: env.now`） | 作者が import を外した版の p.wasm に替える | 終了コード 0、診断なし |
| A2 wasm でないファイル | modules/golem-plugin/test/plugins/override-ruby.wat をそのまま p.wasm として置き、A と同じ宣言を足す | `golem check --format json` | 1 | `G06005` 一件（manifest.toml 1:1、`p: プラグインを読み込めません: failed to parse WebAssembly module`） | wasm のバイナリの p.wasm に替える | 終了コード 0、診断なし |
| B ABI のバージョンが違う | `golem_abi_version` が 8 を返す wasm を p.wasm に置き、A と同じ宣言を足す | `golem check --format json` | 1 | `G06005` 一件（manifest.toml 1:1、`p: プラグインの ABI のバージョンが異なります: 8`） | この Golem の ABI 9 に合う版の p.wasm を使う | 終了コード 0、診断なし |

試験に使った wasm は、modules/golem-plugin/test/plugins/override-ruby.wat と同じ形のモジュールを手で符号化して作った。
wat2wasm がなく、.wat のテキストを読み込ませると A2 の G06005 になるからである。
A と B は、どちらも p.wasm を替えて消える。
ただし、A は作者が直すしかなく、B は書き手が Golem とプラグインの版を合わせれば直る。
この違いは、G06105 を分けたときと同じ構図である。

旧コードを期待する試験は modules/golem-driver/test/PluginsSpec.hs:1200（A）である。
B を G06005 として確かめる試験はなく、modules/golem-plugin/test/Main.hs:206、modules/golem-plugin/test/Main.hs:209、modules/golem-plugin/test/Main.hs:213 が読み込みの段階の `AbiMismatch` を確かめ、modules/golem-plugin/test/ResponseSpec.hs:262 がその文言を確かめている。

修正提案：G06005 は A と A2（壊れたモジュール）に残し、B の ABI の違いには新しい番号を振る。
新しいコードは、modules/golem-driver/src-plugins/Golem/Driver/Plugins.hs:140 の G06105 と同じく、`AbiMismatch` を先に取り出して出す。

### G06007
G06007 は、プラグインのコマンドが組み込みのコマンドと衝突する場合を、上書きできるかどうかによらず一つのコードに束ねている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| A 上書きできる組み込みのコマンドと衝突し、宣言していない | コマンド ruby と greet を提供する ABI 9 の wasm（override-ruby.wat と同じ形）を ruby.wasm に置き、manifest.toml に `[plugins.r]` と `path = "ruby.wasm"` を足す | `golem check --format json` | 1 | `G06007` 一件（manifest.toml 1:1、`組み込みのコマンドと衝突しています（overrides で宣言してください）: r.ruby`） | `[plugins.r]` に `overrides = ["ruby"]` を足す | 終了コード 0、診断なし |
| B 上書きできない組み込みのコマンドと衝突する | コマンド ruby、note、link を提供する ABI 9 の wasm（builtin-names.wat と同じ形）を names.wasm に置き、manifest.toml に `[plugins.names]`、`path = "names.wasm"`、`overrides = ["ruby"]` を足す | `golem check --format json` | 1 | `G06007` 二件（manifest.toml 1:1、`上書きできない組み込みのコマンドと衝突しています: names.link` と `names.note`） | `[plugins.names]` の宣言を消す | 終了コード 0、診断なし |

旧コードを期待する試験は modules/golem-driver/test/PluginsSpec.hs:1210 である。
この試験は、A と B を一つの入力で確かめている。

修正提案：G06007 は A（宣言していない上書き）に残し、B（上書きできない組み込みのコマンドとの衝突）には新しい番号を振る。

### G06012
G06012 は、二つのプラグインのチャネルの衝突と、一つのプラグインが使えない名前のチャネルを宣言することを、一つのコードに束ねている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| A 二つのプラグインが同じチャネルを宣言する | チャネル glossary を宣言する ABI 9 の wasm を c.wasm に置き、manifest.toml に `[plugins.a]` と `[plugins.b]` を足し、どちらも `path = "c.wasm"` にする | `golem check --format json` | 1 | `G06012` 一件（manifest.toml 1:1、`複数のプラグインが同じチャネルを宣言しています: glossary（a、b）`） | `[plugins.b]` の宣言を消す | 終了コード 0、診断なし |
| B 使えない名前のチャネル | チャネル index と Glossary を宣言する ABI 9 の wasm（channels-bad.wat と同じ形）を bad.wasm に置き、manifest.toml に `[plugins.bad]` と `path = "bad.wasm"` を足す | `golem check --format json` | 1 | `G06012` 二件（manifest.toml 1:1、`bad: このチャネルの名前は使えません: Glossary` と `index`） | 作者がチャネルの名前を glossary に直した版の bad.wasm に替える | 終了コード 0、診断なし |

旧コードを期待する試験は modules/golem-driver/test/PluginsSpec.hs:127（B）と modules/golem-driver/test/PluginsSpec.hs:136（A）である。

修正提案：G06012 は A（衝突）に残し、B（使えない名前のチャネル）には新しい番号を振る。
A は、コマンドの衝突の G06006 と同じ種類の誤りである。

### G07027
G07027 は、リストの入れ子が深く行長が 8 字分に満たない誤りと、回り込む図版の脇でリストの字下げを引くと行が残らない誤りを、一つのコードにまとめている。
後者は、リストでない段落なら G07028 で報告する原因であるのに、メッセージは「リストの入れ子が深く」のままである。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| A 入れ子が深い | `style.toml` の `characters = 30` を `characters = 12` にし、`tempest.gm` の末尾に六段の入れ子のリスト（`- one` から `- six item.` まで、一段に空白二つ）を足した | `golem build --target pdf --format json` | 1 | `G07027` 二件（tempest.gm 3233:1、3234:1） | 六つの項目をすべて一段のリストにした | 終了コード 0、診断なし |
| B 回り込む図版の脇のリスト | `figures` の fixture の `photo.jpg` を `images/fig.jpg` に写し、`tempest.gm` の末尾に `@nonumber` と `@figure images/fig.jpg alt="t" wrap=start width=21zw` と十段の入れ子のリスト（`- l0` から `- l9` まで）を足した | `golem build --target pdf --format json` | 1 | `G07027` 二件（tempest.gm 3240:1、3241:1） | 図版の `width` を `18zw` にした | 終了コード 0、診断なし |

条件 B の対照として、同じ写しから図版だけを除くと、終了コード 0、診断なしであった。
したがって、条件 B の `G07027` は入れ子の深さによるものではなく、図版の脇の行の長さによるものである。
図版の幅が `22zw` のときは、脇の行が 8 字分に満たないので `G07022` が先に出た。
旧コードを期待する試験は modules/golem-driver/test/ParagraphSpec.hs:340、modules/golem-driver/test/ParagraphSpec.hs:347、modules/golem-driver/test/ParallelSpec.hs:140 から modules/golem-driver/test/ParallelSpec.hs:142 であり、どれも条件 A である。
条件 B を期待する試験はない。
修正提案：条件 A は G07027 のままにする。
条件 B は、modules/golem-typeset/src/Golem/Typeset/Flow.hs:2963 から 2966 の分岐をなくして G07028 に寄せるか、レイアウトの段階の新しい番号にする。

### G07033
G07033 は、一つの傍注が傍注の領域より高い誤りと、一ページの傍注を合わせると領域に入らない誤りを、一つのコードにまとめている。
メッセージは二つに分かれているが、コードは同じである。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| A 傍注一つが高すぎる | `style.toml` の `characters` を `24` にし、`[paragraph-styles.sidenote]`（`size = "8pt"`）と `[sidenotes]`（`width = "6zw"`、`gap = "1zw"`）を足し、`tempest.gm` の末尾に 700 語の傍注を持つ段落を一つ足した | `golem build --target pdf --format json` | 1 | `G07033` 一件（tempest.gm 3228:5） | その傍注を 40 語に短くした | 終了コード 0、診断なし |
| B 一ページの傍注が多すぎる | A と同じ `style.toml` にし、`tempest.gm` の末尾に 40 語の傍注を持つ段落を 30 個続けて足した | `golem build --target pdf --format json` | 1 | `G07033` 二件（tempest.gm 3232:5、3240:5） | 傍注は変えず、傍注の段落のあいだに 200 語の傍注のない段落を挟んで、傍注を多くのページに散らした | 終了コード 0、診断なし |

条件 A は傍注が一つしかないので、ほかのページへ散らす修正では消えない。
`characters` が `30` のままでは、版面と傍注の領域を合わせた幅がページを超え、`G07001` が先に出たので、両方の条件で `24` に下げた。
旧コードを期待する試験は modules/golem-driver/test/PageElementsSpec.hs:1102 から modules/golem-driver/test/PageElementsSpec.hs:1112 である。
この試験は、1107 と 1108 で条件 B を、1112 で条件 A を確かめている。
修正提案：条件 B は G07033 のままにし、条件 A にはレイアウトの段階の新しい番号を与える。
ただし、傍注の領域を広げればどちらも消えるので、候補としては弱い。

### G07037
G07037 は、`@no-page-break`、`@need-lines`、`@page-lines` の三つのコマンドを守れなかったことを、一つのコードにまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| A `@no-page-break` | `tempest.gm` の先頭に `@no-page-break` を足した | `golem build --target pdf --format json` | 0 | `G07037` 一件（tempest.gm 1:1） | `@no-page-break` を消した | 終了コード 0、診断なし |
| B `@need-lines` | `tempest.gm` の末尾に `@need-lines 40` と段落を足した | `golem build --target pdf --format json` | 0 | `G07037` 一件（tempest.gm 3228:1） | `@need-lines 10` にした | 終了コード 0、診断なし |
| C `@page-lines` | `tempest.gm` の末尾に `@page-lines +40` と段落を足した | `golem build --target pdf --format json` | 0 | `G07037` 一件（tempest.gm 3228:1） | `@page-lines +2` にした | 終了コード 0、診断なし |

三つとも警告なので、終了コードは 0 である。
メッセージは、それぞれ「ここで改ページを止められませんでした」、「@need-lines 40 は段の行数 33 を超えます」、「段に余りがないため、@page-lines の増減を 6 行に切り詰めました」であった。
旧コードを期待する試験は modules/golem-driver/test/ParagraphSpec.hs:422 から modules/golem-driver/test/ParagraphSpec.hs:427（条件 C）と、modules/golem-driver/test/ParagraphSpec.hs:428 から modules/golem-driver/test/ParagraphSpec.hs:431（条件 A と B）である。
修正提案：条件 A は G07037 のままにし、条件 B と条件 C には、レイアウトの段階の新しい番号を一つずつ与える。
条件 C の三つの理由（`AdjustNoRoom`、`AdjustLinesPlaced`、`AdjustOneLine`）は、どれも増減の値を直せば消えるので、一つの番号にまとめる。

### G07043
G07043 は、コードブロックの行長が 8 字分に満たない誤りと、コードの一行と上下の `padding` が一ページに入らない誤りを、一つのコードにまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| A 行長の不足 | `style.toml` に `[paragraph-styles.code]` と `padding = "12zw"` を足し、`tempest.gm` の末尾にコードブロックを足した | `golem build --target pdf --format json` | 1 | `G07043` 一件（style.toml 1:1） | `padding` を `"2zw"` にした | 終了コード 0、`G08008` 一件（style.toml 1:1） |
| B 高さの不足 | `style.toml` の `lines = 33` を `lines = 1` にし、`tempest.gm` の中身を一つの段落と一つのコードブロックだけにした | `golem build --target pdf --format json` | 1 | `G07043` 一件（tempest.gm 3:1）、`G08008` 一件（style.toml 1:1） | `lines = 33` に戻した | 終了コード 0、`G08008` 一件（style.toml 1:1） |

修正後に残る `G08008` は、コードの書体の役割がないことのお知らせであり、この誤りとは関係がない。
条件 B で `tempest.gm` の中身を入れ替えたのは、`lines = 1` では元の見出しが `G07024` になるためである。
条件 A の位置は `style.toml` の先頭で、条件 B の位置はコードブロックである。
旧コードを期待する試験は次のとおりである。
条件 A：modules/golem-driver/test/PdfSpec.hs:1186、modules/golem-driver/test/PdfSpec.hs:1194、modules/golem-driver/test/PdfSpec.hs:1202、modules/golem-driver/test/PdfSpec.hs:1418。
条件 B：modules/golem-driver/test/PdfSpec.hs:1198、modules/golem-driver/test/PdfSpec.hs:1209。
修正提案：条件 A は G07043 のままにし、条件 B（modules/golem-typeset/src/Golem/Typeset/Flow.hs:3535）にはレイアウトの段階の新しい番号を与える。

### G08002
G08002 は、フォントのファイルがない誤りと、フォントのパスが絶対パス、URL、プロジェクトルートの外のどれかである誤りを、一つのコードにまとめている。
後者は、章などのパスなら G03003 で報告する原因である。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| A ファイルがない | `style.toml` の `latin` を `"fonts/none.ttf"` にした | `golem check --format json` | 1 | `G08002` 一件（style.toml 1:1）、`G03010` 一件（style.toml 1:1） | フォントのファイルを `fonts/none.ttf` に置いた | 終了コード 0、診断なし |
| B パスがルートの外 | `style.toml` の `latin` を `"../x.ttf"` にした | `golem check --format json` | 1 | `G08002` 一件（style.toml 1:1）、`G03010` 一件（style.toml 1:1） | `latin` を、プロジェクトの中の `"fonts/SourceSerifVariable-Roman.ttf"` に書き直した | 終了コード 0、診断なし |

条件 B のメッセージは「プロジェクトルートの外を指しています: ../x.ttf」で、条件 A は「フォントのファイルがありません: fonts/none.ttf」であった。
条件 B で、写しの外の `../x.ttf` に本物のフォントを置いても、`G08002` と `G03010` が一件ずつ残り、終了コードは 1 であった。
したがって、ファイルを置く修正は条件 B には効かない。
旧コードを期待する試験は次のとおりであり、どれも条件 A である。
modules/golem-driver/test/DiagnosticSitesSpec.hs:49、modules/golem-driver/test/BuildSpec.hs:268、modules/golem-driver/test/BuildSpec.hs:304、modules/golem-driver/test/BuildSpec.hs:467、modules/golem-driver/test/InMemorySpec.hs:137、modules/golem-cli/test/Main.hs:287、modules/golem-cli/test/CommandsSpec.hs:802。
条件 B を期待する試験はない。
修正提案：条件 A は G08002 のままにする。
条件 B は、ほかのパスと同じ G03003 に寄せるか、出力の段階の新しい番号にする。

### G08006
G08006 は、ICC プロファイルのファイルがない誤りと、`intent` のパスがプロジェクトの中を指さない誤りを、一つのコードにまとめている。
G08002 と同じ形である。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| A ファイルがない | `style.toml` に `[color]` と `intent = "icc/none.icc"` を足した | `golem build --target pdf --format json` | 1 | `G08006` 一件（style.toml 1:1） | scripts/ci/testdata/conformance/golem-test-cmyk.icc を `icc/none.icc` に置いた | 終了コード 0、診断なし |
| B パスがルートの外 | `style.toml` に `[color]` と `intent = "../x.icc"` を足した | `golem build --target pdf --format json` | 1 | `G08006` 一件（style.toml 1:1） | 同じプロファイルを `icc/cmyk.icc` に置き、`intent = "icc/cmyk.icc"` に書き直した | 終了コード 0、診断なし |

条件 B のメッセージは「プロジェクトルートの外を指しています: ../x.icc」であった。
写しの外の `../x.icc` にプロファイルを置いても `G08006` は残り、終了コードは 1 であった。
旧コードを期待する試験は modules/golem-driver/test/BuildSpec.hs:294 と modules/golem-driver/test/DiagnosticSitesSpec.hs:61 であり、どちらも条件 A である。
条件 B を期待する試験はない。
修正提案：条件 A は G08006 のままにし、条件 B は G08002 の条件 B と同じ扱いにする。

### G08010
G08010 は、壊れた図版のファイル、Golem が扱わない形の画像、Golem が取り込まない機能を使う PDF、大きさのない SVG を、一つのコードにまとめている。
どの条件も、tempest の写しの tempest.gm の末尾に `@nonumber` と `@figure` の二行を足して再現した。
`@nonumber` を付けないと、章の外の図版として G04004 が先に出る。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 壊れた PNG | `@figure images/x.png alt="x"` を足し、`images/x.png` を PNG のシグネチャの 8 バイトだけにした | `golem build --target pdf --format json` | 1 | `G08010` 一件（tempest.gm 3229:1、理由は「PNG の IHDR がありません」） | `images/x.png` を modules/golem-driver/test/fixtures/figures/images/gray.png に差し替えた | 終了コード 0、診断なし |
| インターレースの PNG | `@figure images/x.png alt="x"` を足し、gray.png の IHDR のインターレースのバイト（先頭から 28 バイト目）を 1 にしたものを `images/x.png` にした | `golem build --target pdf --format json` | 1 | `G08010` 一件（tempest.gm 3229:1、理由は「インターレースの PNG は使えません」） | インターレースのバイトを 0 に戻した（インターレースなしで保存し直すことに当たる） | 終了コード 0、診断なし |
| 特色を使う PDF | `@figure images/x.pdf web=images/w.png alt="x"` を足し、`images/x.pdf` に modules/golem-driver/test/fixtures/figures-external/pdftex-spot-color.pdf を、`images/w.png` に gray.png を置いた | `golem build --target pdf --format json` | 1 | `G08010` 一件（tempest.gm 3229:1、理由は「特色（Separation か DeviceN）があります」） | `images/x.pdf` を、特色のない modules/golem-driver/test/fixtures/figures-external/pdftex.pdf に差し替えた | 終了コード 0、診断なし |
| 大きさのない SVG | `@figure images/x.svg alt="x"` を足し、`images/x.svg` を `<svg xmlns="http://www.w3.org/2000/svg"><rect width="5" height="5"/></svg>` にした | `golem build --target pdf --format json` | 1 | `G08010` 一件（tempest.gm 3229:1、理由は「SVG の大きさがありません」） | ルートの要素に `width="10" height="10"` を書いた | 終了コード 0、診断なし |

最初の版の条件の表では、PDF の図版に web の代替画像がなく、G08010 でなく G02029 が出た。
そこで web の代替画像を足して、取り直した。
壊れた PNG とインターレースの PNG は、どちらも正しい PNG を置き直せば直る。
したがって、この二つの直し方の違いは小さい。
特色の PDF と大きさのない SVG の直し方は、ほかの条件と種類が違う。
旧コードを期待する試験は、modules/golem-driver/test/FigureSpec.hs:208-212、modules/golem-driver/test/FigureSpec.hs:246-248、modules/golem-driver/test/FigureSpec.hs:377-382、modules/golem-driver/test/FigureExternalSpec.hs:97-100、modules/golem-driver/test/CliSpec.hs:367-370 である。
modules/golem-svg/test/SecuritySpec.hs:260-266, 329-333 と modules/golem-pdf/test/ImportSpec.hs:306-312 は、G08010 の理由を内部の型で確かめるが、コードは見ていない。
修正提案：壊れたファイルと扱わない形の画像は、G08010 に残す。
Golem が取り込まない機能を使う PDF（特色、レイヤー、埋め込んでいないフォント、扱わない圧縮、RGB のインライン画像、UserUnit）には新しい番号を与え、大きさのない SVG と大きさの数が範囲の外の SVG にも新しい番号を与える。

### G08014
G08014 は、HTML と EPUB に写す SVG に動的なコンテンツがあることと、その SVG を XML として読めないことを、一つのコードにまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 動的なコンテンツ | `@nonumber` と `@figure images/s.svg alt="x"` を足し、`images/s.svg` を `<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><script/></svg>` にした | `golem build --target html --format json` | 1 | `G08014` 一件（tempest.gm 3229:1、`images/s.svg:1:64（script）`） | `script` の要素を除いた | 終了コード 0、診断なし |
| 読めない SVG | 同じ二行を足し、`images/s.svg` を `<svg` の 4 バイトだけにした | `golem build --target html --format json` | 1 | `G08014` 一件（tempest.gm 3229:1、理由は「開始のタグが壊れています: svg」） | `images/s.svg` を、XML として閉じた `<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"/>` にした | 終了コード 0、診断なし |

旧コードを期待する試験は、modules/golem-driver/test/FigureSpec.hs:453-456、modules/golem-driver/test/FigureSpec.hs:458-460、modules/golem-driver/test/FigureSpec.hs:462-467、modules/golem-driver/test/FigureSpec.hs:469-471、modules/golem-driver/test/FigureSpec.hs:473-475、modules/golem-driver/test/FigureSpec.hs:477-480 である。
読めない SVG の条件を確かめるのは、このうち modules/golem-driver/test/FigureSpec.hs:462-464 である。
修正提案：動的なコンテンツは G08014 に残し、読めない SVG には新しい番号を与える。
同じファイルを PDF に組むと G08010 になるので、読めない SVG の新しい番号を G08010 から分けた壊れたファイルのコードとそろえるかも決める。

### G09102
G09102 は、プリフライトの設定の値について、語彙の外の語、範囲の外の整数、二つの閾値の大小の誤りを、一つのコードにまとめている。

| 条件 | tempest の写しに加えた変更 | コマンド | 終了コード | 出たコード | 修正 | 修正後 |
| --- | --- | --- | --- | --- | --- | --- |
| 語彙の外の語 | ルートに `preflight.toml` を置き、`[pdf-x]` と `severity = "notice"` を書いた | `golem preflight --format json` | 1 | `G09102` 一件（preflight.toml 2:12） | `severity = "warning"` にした | 終了コード 1、`G09010` 一件と `G09014` 一件（style.toml 1:1、tempest の写しがもともと持つもの）、G09102 なし |
| 範囲の外の整数 | `preflight.toml` に `[page-count]` と `multiple-of = 0` を書いた | `golem preflight --format json` | 1 | `G09102` 一件（preflight.toml 2:15） | `multiple-of = 4` にした | 終了コード 1、`G09010` 一件と `G09014` 一件、G09102 なし |
| 閾値の大小の誤り | `preflight.toml` に `[image-resolution]` と `gray = { error-below = 400, warning-below = 300 }` を書いた | `golem preflight --format json` | 1 | `G09102` 一件（preflight.toml 2:8） | `error-below = 300, warning-below = 400` にした | 終了コード 1、`G09010` 一件と `G09014` 一件、G09102 なし |

旧コードを期待する試験は、modules/golem-preflight/test/Main.hs:195-198、modules/golem-preflight/test/Main.hs:206、modules/golem-preflight/test/Main.hs:210、modules/golem-preflight/test/Main.hs:214、modules/golem-preflight/test/RulesSchemaSpec.hs:99、modules/golem-preflight/test/RulesSchemaSpec.hs:103、modules/golem-preflight/test/RulesSchemaSpec.hs:105、modules/golem-preflight/test/RulesSchemaSpec.hs:107、modules/golem-driver/test/CliSpec.hs:407-410 である。
modules/golem-preflight/test/Main.hs:307 は、範囲の外の整数のメッセージだけを見ている。
修正提案：型の違い、語彙の外の語、長さの書き方の誤りは、G09102 に残す。
範囲の外の整数と、error-below と warning-below の大小の誤りには、それぞれ新しい番号を与える。

## 単一

次のコードは、一つの原因だけを表すと判定した。
発生箇所は、modules の test の外で、そのコードを出す箇所である。

| コード | 発生箇所 | 理由 |
| --- | --- | --- |
| E01101 | modules/golem-emet/src/Golem/Emet/Parse.hs:99-103 | どの括弧か引用符が閉じていないかが違うだけで、どれも閉じる記号を足して直す。 |
| E01102 | modules/golem-emet/src/Golem/Emet/Parse.hs:107 | 予約語を書いたという一つの原因だけである。 |
| E01103 | modules/golem-emet/src/Golem/Emet/Check.hs:857 | どれも where の位置の誤りで、最後の等式の後ろの一つの where にまとめて直す。 |
| E02102 | modules/golem-emet/src/Golem/Emet/Check.hs:628 | シグネチャのない最上位の関数という一つの原因だけである。 |
| E02103 | modules/golem-emet/src/Golem/Emet.hs:260 | import の循環という一つの原因だけである。 |
| E02104 | modules/golem-emet/src/Golem/Emet/Check.hs:413-415, 577-579, 596, 625-626, 1059, 1142, 1192, 1206, 1316 | 重なる相手が違うだけで、どれも名前を変えて直す。 |
| E02105 | modules/golem-emet/src/Golem/Emet/Check.hs:466, 473, 919, 926, 948, 955 | 型、関数、コンストラクタのどれかが違うだけで、どれも pub を付けて直す。 |
| E02107 | modules/golem-emet/src/Golem/Emet/Check.hs:627, 1317 | 最上位か where かが違うだけで、どれも等式を続けて並べて直す。 |
| E02108 | modules/golem-emet/src/Golem/Emet/Check.hs:389-393 | 重なる相手がほかの取り込みかこのファイルの定義かが違うだけで、直し方は同じである。 |
| E02109 | modules/golem-emet/src/Golem/Emet/Check.hs:824 | 使われていない where の束縛という一つの原因だけである。 |
| E03100 | modules/golem-emet/src/Golem/Emet/Check.hs:1280、modules/golem-emet/src/Golem/Emet/Eval.hs:317 | 静的な検査の一つの条件だけであり、評価の側は検査を通った後には届かない。 |
| E03101 | modules/golem-emet/src/Golem/Emet/Check.hs:1259, 1273 | どれも選ばれない枝で、消すか順を直して直す。 |
| E03102 | modules/golem-emet/src/Golem/Emet/Check.hs:1268 | ガードの並びの最後が otherwise でないという一つの原因だけである。 |
| E04100 | modules/golem-emet/src/Golem/Emet/Eval.hs:200 | 評価の手数の上限という一つの原因だけである。 |
| E04101 | modules/golem-emet/src/Golem/Emet/Eval.hs:192 | 末尾でない呼び出しの深さの上限という一つの原因だけである。 |
| E04102 | modules/golem-emet/src/Golem/Emet/Eval.hs:259 | where の束縛の循環という一つの原因だけである。 |
| E05100 | modules/golem-emet/src/Golem/Emet/Check.hs:523 | 知らない要求の種類という一つの原因だけである。 |
| E05101 | modules/golem-emet/src/Golem/Emet/Solve.hs:234 | シグネチャにない要求という一つの原因だけである。 |
| E05102 | modules/golem-emet/src/Golem/Emet/Check.hs:537 | 同じ要求の重複という一つの原因だけである。 |
| E05103 | modules/golem-driver/src/Golem/Driver/Functions.hs:86 | 要求したファイルが UTF-8 でないという一つの原因だけである。 |
| E05104 | modules/golem-driver/src/Golem/Driver/Functions.hs:145、modules/golem-emet/src/Golem/Emet/Eval.hs:356 | 静的な検査と評価の側のどちらも、manifest.toml に足して直す。 |
| E05105 | modules/golem-driver/src/Golem/Driver/Functions.hs:82 | 要求したファイルの大きさの上限という一つの原因だけである。 |
| E05106 | modules/golem-emet/src/Golem/Emet/Check.hs:709 | 本体を評価する前の矢印の要求の列という一つの原因だけである。 |
| E05107 | modules/golem-emet/src/Golem/Emet/Check.hs:909, 998 | リテラルでない引数も値としての受け渡しも、リテラルで直接呼んで直す。 |
| E05108 | modules/golem-emet/src/Golem/Emet/Check.hs:803 | 本体が使わない要求という一つの原因だけである。 |
| E06101 | modules/golem-emet/src/Golem/Emet/Check.hs:1588, 1590, 1605、modules/golem-emet/src/Golem/Emet/Gm.hs:122 | 種類が違うだけで、どれも戻り値の型か種類の語を変えて直し、評価の側は型の検査が保証するので届かない。 |
| E06104 | modules/golem-emet/src/Golem/Emet/Gm.hs:87 | どの不変条件に反したかが違うだけで、どれも関数が返す値を直す。 |
| E06106 | modules/golem-emet/src/Golem/Emet/Check.hs:1461 | 同じ名前を二度出すという一つの原因だけである。 |
| E07100 | modules/golem-emet/src/Golem/Emet/Lint.hs:47, 52, 59 | 関数、データ型、型の別名のどれかが違うだけで、どれも消すか pub を付けて直す。 |
| E07101 | modules/golem-emet/src/Golem/Emet/Lint.hs:66 | 使われていない import という一つの原因だけである。 |
| E07102 | modules/golem-emet/src/Golem/Emet/Lint.hs:79 | 使われていないパターンの変数という一つの原因だけである。 |
| G01001 | modules/golem-syntax/src/Golem/Syntax/Read.hs:32、modules/golem-parser/src/Golem/Parser/Read.hs:48 | 同じ検査をファイルの種類ごとに出しているだけである。 |
| G01002 | modules/golem-syntax/src/Golem/Syntax/Read.hs:55 | 先頭の BOM という一つの原因だけである。 |
| G01003 | modules/golem-syntax/src/Golem/Syntax/Read.hs:48 | CRLF の CR も単独の CR も、LF にして直す。 |
| G01010 | modules/golem-parser/src/Golem/Parser.hs:162 | 文法の受け皿の一つのラベルだけである。 |
| G01011 | modules/golem-parser/src/Golem/Parser.hs:163 | タブも余分な空白も、インデントを直して直す。 |
| G01012 | modules/golem-parser/src/Golem/Parser.hs:164 | 7 階層以上の見出しという一つの原因だけである。 |
| G01013 | modules/golem-parser/src/Golem/Parser.hs:165 | 用語のない `=:` という一つの原因だけである。 |
| G01014 | modules/golem-parser/src/Golem/Parser.hs:166 | 表の区切りの行の欠けという一つの原因だけである。 |
| G01015 | modules/golem-parser/src/Golem/Parser.hs:167 | 表のセルの数の食い違いという一つの原因だけである。 |
| G01016 | modules/golem-parser/src/Golem/Parser.hs:168 | 閉じていないコードブロックという一つの原因だけである。 |
| G01017 | modules/golem-parser/src/Golem/Parser.hs:169 | 同じ構文の期待（ここに `]`）を文法の 3 箇所で出しているだけである。 |
| G01018 | modules/golem-parser/src/Golem/Parser.hs:170, 82, 120 | 段落、引数列、式のどれかが違うだけで、どれもコメントを閉じて直す。 |
| G01019 | modules/golem-parser/src/Golem/Parser.hs:171 | キーワード引数の後の位置引数という一つの原因だけである。 |
| G01020 | modules/golem-parser/src/Golem/Parser.hs:172、modules/golem-eval/src/Golem/Eval/Expr.hs:163 | 式が読めないという一つの原因であり、評価の側は表示されない。 |
| G01021 | modules/golem-parser/src/Golem/Parser.hs:173 | `[` の後にコマンド名も `=` もないという一つの原因だけである。 |
| G01023 | modules/golem-parser/src/Golem/Parser.hs:174 | 表の行の端の `|` が欠けるという一つの条件である。 |
| G01024 | modules/golem-parser/src/Golem/Parser.hs:175 | 文法の一つの規則の誤りが段落、見出し、用語、表の行という置き場所で違うだけで、`\` を消すかエスケープすれば直る。 |
| G01101 | modules/golem-parser/src/Golem/Parser.hs:78, :120 | 引数列と式という置き場所が違うだけの同じ誤りである。 |
| G01102 | modules/golem-parser/src/Golem/Parser.hs:95 | 引用符なしの値の `%%` という一つの条件である。 |
| G02001 | modules/golem-eval/src/Golem/Eval/Expr.hs:75 ほか、modules/golem-emet/src/Golem/Emet/Eval.hs:303, :392 | 演算子と関数が違うだけで、どれも型の不一致である。 |
| G02003 | modules/golem-eval/src/Golem/Eval/Expr.hs:245, :249, :284, :343 | 演算が違うだけの 0 での割り算である。 |
| G02005 | modules/golem-eval/src/Golem/Eval/File.hs:2391 | prod に残った校正コメントという一つの条件である。 |
| G02006 | modules/golem-eval/src/Golem/Eval/Expr.hs:254 | `**` の整数でない指数という一つの条件である。 |
| G02007 | modules/golem-eval/src/Golem/Eval/Expr.hs:352, modules/golem-emet/src/Golem/Emet/Prim.hs:147, :158, modules/golem-emet/src/Golem/Emet/Eval.hs:357 | 関数が違うだけの引数の数か型の誤りである。 |
| G02008 | modules/golem-eval/src/Golem/Eval/Expr.hs:376 | 値の型が違うだけの埋め込めない値である。 |
| G02010 | modules/golem-eval/src/Golem/Eval/File.hs:597, :970, :1552 | 属性の種類が違うだけで、どれも後に対象のブロックがない。 |
| G02011 | modules/golem-eval/src/Golem/Eval/File.hs:969, :974 | 属性のまとまりに混ざったコマンドという一つの条件である。 |
| G02012 | modules/golem-eval/src/Golem/Eval/File.hs:993 | 重複した属性という一つの条件である。 |
| G02013 | modules/golem-eval/src/Golem/Eval/File.hs:626, :986, :1357, :1438, :1443, :1833 | 属性とブロックの組み合わせが違うだけで、どれも付けられない種類のブロックへの属性である。 |
| G02014 | modules/golem-eval/src/Golem/Eval/File.hs:2408, :2474 | doc と相互参照のどちらも、見出しの外へ移せば直る。 |
| G02015 | modules/golem-eval/src/Golem/Eval/File.hs:2666 | ルビの対象と読みのセグメントの数の不一致という一つの条件である。 |
| G02016 | modules/golem-eval/src/Golem/Eval/File.hs:2662 | 入れ子のルビという一つの条件である。 |
| G02020 | modules/golem-eval/src/Golem/Eval/File.hs:2555 | reading のない索引という一つの条件である。 |
| G02021 | modules/golem-eval/src/Golem/Eval/File.hs:821, :2775 | 書誌データにないキーという一つの条件を二つの経路で調べる。 |
| G02023 | modules/golem-eval/src/Golem/Eval/File.hs:513, :555 | 変数と名前空間という置き場所が違うだけの予約語の使用である。 |
| G02024 | modules/golem-eval/src/Golem/Eval/File.hs:516 | 変数の二度の定義という一つの条件である。 |
| G02025 | modules/golem-eval/src/Golem/Eval/File.hs:576 | 数でない値と範囲の外の数のどちらも、1 から 6 の整数を書けば直る。 |
| G02026 | modules/golem-eval/src/Golem/Eval/File.hs:1320, :2577 | 名前がない、多い、使えない字のどれも、使える名前を一つ書けば直る。 |
| G02027 | modules/golem-eval/src/Golem/Eval/File.hs:1369 | `@number` の引数が整数一つでないという一つの条件である。 |
| G02028 | modules/golem-eval/src/Golem/Eval/File.hs:1791 | alt のない図版という一つの条件である。 |
| G02029 | modules/golem-eval/src/Golem/Eval/File.hs:1723 | web の代替画像のない PDF の図版という一つの条件である。 |
| G02030 | modules/golem-eval/src/Golem/Eval/File.hs:1808 | wrap の値の誤りという一つの条件である。 |
| G02031 | modules/golem-eval/src/Golem/Eval/File.hs:1753 | width のない回り込む図版という一つの条件である。 |
| G02032 | modules/golem-eval/src/Golem/Eval/File.hs:1813 | `@figure` の位置引数がパス一つでないという一つの条件である。 |
| G02033 | modules/golem-eval/src/Golem/Eval/File.hs:2141 | コマンドが違うだけの存在しないファイルである。 |
| G02034 | modules/golem-eval/src/Golem/Eval/File.hs:1883 | パスのない `@table` という一つの条件である。 |
| G02036 | modules/golem-eval/src/Golem/Eval/File.hs:2154 | パスのない `@listing` という一つの条件である。 |
| G02037 | modules/golem-eval/src/Golem/Eval/File.hs:2176 | 始めが 0 の範囲も終わりが行数を超える範囲も、ファイルの行の外という同じ誤りである。 |
| G02038 | modules/golem-eval/src/Golem/Eval/File.hs:1264, :2475, :2484, :2537, :2545, :2564, :2612, :2669 | コマンドが違うだけの散文スロットの数の誤りである。 |
| G02039 | modules/golem-eval/src/Golem/Eval/File.hs:820, :2495 | 未知の圏点の形という一つの条件である。 |
| G02040 | modules/golem-eval/src/Golem/Eval/File.hs:2512 | 縦中横の中の地の文でないものという一つの条件である。 |
| G02041 | modules/golem-eval/src/Golem/Eval/File.hs:2556 | 索引の語の地の文でないものという一つの条件である。 |
| G02043 | modules/golem-eval/src/Golem/Eval/File.hs:2663 | ルビの読みの地の文でないものという一つの条件である。 |
| G02045 | modules/golem-eval/src/Golem/Eval/File.hs:1554 | `@style` の本体の段落でないブロックという一つの条件である。 |
| G02046 | modules/golem-eval/src/Golem/Eval/File.hs:1553, :1559 | 本体に段落がないという一つの条件で、段落を書けば直る。 |
| G02049 | modules/golem-eval/src/Golem/Eval/File.hs:940 | ファイルの設定の並びの外にある設定のコマンドという一つの条件である。 |
| G02051 | modules/golem-eval/src/Golem/Eval/Settings.hs:126 | `[source]` のキーの受け付けない値という一つの条件である。 |
| G02052 | modules/golem-eval/src/Golem/Eval/Settings.hs:134, 261, 262, 345 | どのコマンドでも位置引数の数が合わないという同じ誤りであり、直し方も数を合わせることである。 |
| G02053 | modules/golem-eval/src/Golem/Eval/Settings.hs:284 | 同じ名前のスタイルを二度定義したという一つの原因である。 |
| G02056 | modules/golem-eval/src/Golem/Eval/File.hs:2388 | コマンドの中の強制改行という一つの原因である。 |
| G02057 | modules/golem-eval/src/Golem/Eval/File.hs:1633 | 三つの書き方はどれも中身のない行を作るもので、直し方も同じである。 |
| G02059 | modules/golem-eval/src/Golem/Eval/File.hs:1302 | 違いは置いたコマンドだけである。 |
| G02060 | modules/golem-eval/src/Golem/Eval/File.hs:2136 | 絶対パス、URL、ルートの外のどれも、ファイルをプロジェクトに置いて相対パスで書くという同じ直し方になる。 |
| G02061 | modules/golem-eval/src/Golem/Eval/Expr.hs:353 | 未定義の関数という一つの原因である。 |
| G02062 | modules/golem-eval/src/Golem/Eval/Settings.hs:223 | 既存のスタイルの上書きという一つの原因である。 |
| G02063 | modules/golem-eval/src/Golem/Eval/File.hs:2509 | 数字だけの縦中横という一つの原因である。 |
| G02064 | modules/golem-eval/src/Golem/Eval/File.hs:1597 | 行頭のエスケープした空白という一つの原因である。 |
| G02065 | modules/golem-eval/src/Golem/Eval/File.hs:2148 | `@listing` の src= という一つの原因である。 |
| G02066 | modules/golem-eval/src/Golem/Eval/File.hs:1542 | 段落に code を付けたという一つの原因である。 |
| G02067 | modules/golem-driver/src/Golem/Driver.hs:530 | 柱が参照する変数がそのファイルで見えないという一つの原因である。 |
| G02068 | modules/golem-driver/src/Golem/Driver.hs:534 | 柱の値の型という一つの原因である。 |
| G02071 | modules/golem-eval/src/Golem/Eval/File.hs:1303 | 違いは置いたコマンドだけである。 |
| G02072 | modules/golem-eval/src/Golem/Eval/File.hs:1224 | 違いは相手のコマンドだけである。 |
| G02073 | modules/golem-eval/src/Golem/Eval/File.hs:1729 | web の画像の形式という一つの原因である。 |
| G02074 | modules/golem-eval/src/Golem/Eval/File.hs:1728 | 図版の形式という一つの原因である。 |
| G02076 | modules/golem-eval/src/Golem/Eval/File.hs:1062 | 日本語でない本の `@printings` という一つの原因である。 |
| G02077 | modules/golem-eval/src/Golem/Eval/Settings.hs:82, File.hs:2691 | 同じキーの重なりを二つの箇所で調べているだけである。 |
| G02079 | modules/golem-eval/src/Golem/Eval/File.hs:1603 | 行末のエスケープした空白という一つの原因である。 |
| G02080 | modules/golem-eval/src/Golem/Eval/File.hs:1869 | format の値という一つの原因である。 |
| G02082 | modules/golem-parser/src/Golem/Parser/Read.hs:66 | 単独の CR という一つの原因である。 |
| G02083 | modules/golem-eval/src/Golem/Eval/File.hs:2067 | 閉じていない引用符という一つの原因である。 |
| G02084 | modules/golem-eval/src/Golem/Eval/File.hs:1880, 1881 | cells=markup とほかの値は、どちらも cells を消すか text にするという同じ直し方になる。 |
| G02085 | modules/golem-eval/src/Golem/Eval/File.hs:2085 | 違いは CSV か TSV かだけである。 |
| G02088 | modules/golem-eval/src/Golem/Eval/File.hs:1947 | 大きさ、行の数、セルの数はどれも同じ種類の資源の上限であり、ファイルを減らすか分けて直す。 |
| G02089 | modules/golem-eval/src/Golem/Eval/File.hs:299 | 違いは文字列の出どころだけである。 |
| G02091 | modules/golem-eval/src/Golem/Eval/File.hs:1198, 3148 | 違いは IR の欄だけで、int64 の範囲の外という原因は同じである。 |
| G02093 | modules/golem-eval/src/Golem/Eval/File.hs:1304 | `@blank-line` を最上位の外に置いたという一つの原因である。 |
| G02094 | modules/golem-eval/src/Golem/Eval/File.hs:1191 | 続けて書いた `@blank-line` という一つの原因である。 |
| G02096 | modules/golem-eval/src/Golem/Eval/File.hs:1060, 1102, 1112 | 違いはコマンドだけである。 |
| G02097 | modules/golem-eval/src/Golem/Eval/File.hs:1061, 1089, 1136, Settings.hs:100 | 違いはコマンドだけである。 |
| G02098 | modules/golem-eval/src/Golem/Eval/File.hs:1063 | `[[metadata.printings]]` がないという一つの原因である。 |
| G02101 | modules/golem-eval/src/Golem/Eval/Expr.hs:329 | 負の数の平方根という一つの原因である。 |
| G02102 | modules/golem-eval/src/Golem/Eval/Expr.hs:374, modules/golem-emet/src/Golem/Emet/Prim.hs:157 | 同じ原因を二つの箇所で出しているだけである。 |
| G02103 | modules/golem-eval/src/Golem/Eval/Expr.hs:208, modules/golem-project/src/Golem/Project/Style.hs:3385, Manifest.hs:828, 1020 | 箇所は多いが、自然数を求める箇所の負の数という一つの原因として [ADR 0102](../adr/0102-natural-number-type.md) が決めている。 |
| G02104 | modules/golem-eval/src/Golem/Eval/Expr.hs:173, 209 | 整数が要る箇所の整数でない数という一つの原因である。 |
| G02105 | modules/golem-eval/src/Golem/Eval/File.hs:3061 | 空、数でない語、違う型の式のどれも、行の番号か範囲に書き直して直す。 |
| G02106 | modules/golem-eval/src/Golem/Eval/File.hs:3057, Expr.hs:161 | 違いは語か式かだけである。 |
| G02107 | modules/golem-eval/src/Golem/Eval/File.hs:3062 | 範囲を二つ以上書いたという一つの原因である。 |
| G02108 | modules/golem-eval/src/Golem/Eval/File.hs:3034 | `-` で区切った範囲という一つの原因である。 |
| G02111 | modules/golem-eval/src/Golem/Eval/File.hs:2720 | `*[式]` の値が配列でないという一つの原因で、直し方も一つである。 |
| G02112 | modules/golem-eval/src/Golem/Eval/File.hs:2723 | `**[式]` の値が連想配列でないという一つの原因である。 |
| G02113 | modules/golem-eval/src/Golem/Eval/File.hs:2921 | 範囲を受け取らない引数への範囲という同じ検査を、箇所ごとに出している。 |
| G02114 | modules/golem-eval/src/Golem/Eval/Settings.hs:65、modules/golem-eval/src/Golem/Eval/File.hs:2749 | 評価の前に読むコマンドの展開という同じ誤りで、コマンドが違うだけである。 |
| G02115 | modules/golem-eval/src/Golem/Eval/Settings.hs:120 | `@manifest` に引数がないという一つの原因である。 |
| G02116 | modules/golem-eval/src/Golem/Eval/Settings.hs:96 | 値を語と文字列のほかで書いた誤りで、箇所が違うだけである。 |
| G02117 | modules/golem-eval/src/Golem/Eval/Settings.hs:267 | 未知のスタイルの種類という一つの原因である。 |
| G02118 | modules/golem-eval/src/Golem/Eval/File.hs:1817 | キャプションの中の段落でないブロックという一つの原因で、ブロックの種類が違うだけである。 |
| G02119 | modules/golem-eval/src/Golem/Eval/File.hs:696 | シグネチャにないキーワード引数という一つの原因である。 |
| G02120 | modules/golem-eval/src/Golem/Eval/Functions.hs:157 | 位置引数の数の食い違いという一つの原因で、直し方も数を合わせることで同じである。 |
| G02121 | modules/golem-eval/src/Golem/Eval/Functions.hs:159、modules/golem-eval/src/Golem/Eval/File.hs:721 | 同じ型の誤りが、位置引数とキーワード引数で出ているだけである。 |
| G02122 | modules/golem-eval/src/Golem/Eval/File.hs:761 | 散文スロットの数の食い違いという一つの原因である。 |
| G02123 | modules/golem-eval/src/Golem/Eval/File.hs:788 | 本体を受け取らない関数のブロックの本体という一つの原因である。 |
| G02125 | modules/golem-eval/src/Golem/Eval/File.hs:2643 | どれも URL の構文の違反で、URL を正しい形に直すという同じ直し方になる。 |
| G02126 | modules/golem-eval/src/Golem/Eval/File.hs:2644 | scheme が http と https のほかという一つの原因である。 |
| G02127 | modules/golem-eval/src/Golem/Eval/File.hs:2645 | ホストの ASCII でない字という一つの原因である。 |
| G02128 | modules/golem-eval/src/Golem/Eval/File.hs:2633 | リンクの中のリンクになる要素という一つの原因で、要素の種類が違うだけである。 |
| G02129 | modules/golem-eval/src/Golem/Eval/File.hs:1861 | `@table` の `src=` という一つの原因である。 |
| G02130 | modules/golem-eval/src/Golem/Eval/File.hs:1884 | どれも余分なパスを消して直す。 |
| G02132 | modules/golem-eval/src/Golem/Eval/File.hs:1250 | 言語のタグが BCP 47 の形でないという一つの原因である。 |
| G02134 | modules/golem-eval/src/Golem/Eval/File.hs:1019、modules/golem-eval/src/Golem/Eval/File.hs:1025 | 同じ検査を、コードブロックと表のそれぞれで出しているだけである。 |
| G02136 | modules/golem-eval/src/Golem/Eval/File.hs:1390 | 値の数が一つでも列の数でもないという一つの原因である。 |
| G02137 | modules/golem-eval/src/Golem/Eval/File.hs:1469 | 定義されていない注の名前という一つの原因である。 |
| G02138 | modules/golem-eval/src/Golem/Eval/File.hs:1475 | 使われない注の本文という一つの原因である。 |
| G02139 | modules/golem-eval/src/Golem/Eval/File.hs:1471 | 一つの本文を二つ以上の `[note]` が指すという一つの原因である。 |
| G02140 | modules/golem-eval/src/Golem/Eval/File.hs:1428 | 同じ名前の `@note` の重複という一つの原因である。 |
| G02141 | modules/golem-eval/src/Golem/Eval/File.hs:1446 | 注の本体の段落でないブロックという一つの原因である。 |
| G02143 | modules/golem-eval/src/Golem/Eval/File.hs:1429 | `@note` に本体がないという一つの原因である。 |
| G02144 | modules/golem-eval/src/Golem/Eval/File.hs:2826 | `range` が begin でも end でもないという一つの原因である。 |
| G02145 | modules/golem-eval/src/Golem/Eval/File.hs:2823 | `see` と `range` を一緒に書いたという一つの原因である。 |
| G02146 | modules/golem-eval/src/Golem/Eval/File.hs:2832 | 三段以上の参照先と空の段は、どちらも参照先の形の違反で、`語` か `語/語` に書き直すという同じ直し方になる。 |
| G02147 | modules/golem-eval/src/Golem/Eval/File.hs:2774 | 同じキーを二度書いたという一つの原因である。 |
| G02149 | modules/golem-eval/src/Golem/Eval/File.hs:2784 | キーが二つ以上ある cite の `page` という一つの原因である。 |
| G02150 | modules/golem-eval/src/Golem/Eval/File.hs:2772 | キーが名前でも文字列でもないという一つの原因である。 |
| G02151 | modules/golem-eval/src/Golem/Eval/File.hs:2785 | キーがないという一つの原因である。 |
| G02152 | modules/golem-eval/src/Golem/Eval/File.hs:2573 | 位置引数とキーワード引数のどちらも、引数を消して直す。 |
| G02153 | modules/golem-eval/src/Golem/Eval/Settings.hs:343 | `@hyphenation-exceptions` のキーワード引数という一つの原因である。 |
| G02154 | modules/golem-eval/src/Golem/Eval/File.hs:2099 | セルの数が見出しと違うという一つの原因で、CSV と TSV の違いは形式だけである。 |
| G02155 | modules/golem-eval/src/Golem/Eval/File.hs:507 | 旧記法の `@set` という一つの原因である。 |
| G02254 | modules/golem-eval/src/Golem/Eval/File.hs:1195 | 行アキの合計が 0 行という一つの原因である。 |
| G03002 | modules/golem-project/src/Golem/Project.hs:271、modules/golem-emet/src/Golem/Emet.hs:269、modules/golem-driver/src/Golem/Driver.hs:576、modules/golem-cli/app/Main.hs:443 | 指したファイルがないという一つの原因で、箇所が違うだけである。 |
| G03003 | modules/golem-project/src/Golem/Project.hs:272、modules/golem-driver/src/Golem/Driver.hs:577、modules/golem-driver/src/Golem/Driver.hs:733、modules/golem-driver/src/Golem/Driver/Functions.hs:70、modules/golem-driver/src-plugins/Golem/Driver/Plugins.hs:126、modules/golem-emet/src/Golem/Emet/Check.hs:529 ほか | 絶対パス、URL、ルートの外は、どれもルートの中の相対パスにするという同じ直し方になる。 |
| G03004 | modules/golem-project/src/Golem/Project.hs:168、modules/golem-driver/src/Golem/Driver/Functions.hs:73、modules/golem-driver/src/Golem/Driver/Functions.hs:144、modules/golem-emet/src/Golem/Emet/Check.hs:538 | 大文字と小文字だけが違うパスという一つの原因である。 |
| G03005 | modules/golem-project/src/Golem/Project.hs:132 | import の循環という一つの原因である。 |
| G03007 | modules/golem-driver/src/Golem/Driver.hs:308 | style.toml にないマスターページの名前という一つの原因である。 |
| G03008 | modules/golem-project/src/Golem/Project/Style.hs:3130、modules/golem-eval/src/Golem/Eval/Settings.hs:173 | 原因は `[fonts]` にない役割の一つであり、違うのは書いた場所だけである。 |
| G03009 | modules/golem-project/src/Golem/Project/Imports.hs:56 | どの形の誤りも、「パス as 名前空間」の形に書き直せば直る。 |
| G03011 | modules/golem-project/src/Golem/Project/Style.hs:3228 | 条件が一つしかない。 |
| G03012 | modules/golem-project/src/Golem/Project/Style.hs:3245 | 条件が一つしかない。 |
| G03016 | modules/golem-project/src/Golem/Project.hs:97 | 条件が一つしかない。 |
| G03018 | modules/golem-project/src/Golem/Project/Style.hs:2223、2224、2843 | 一つのキーの値の誤りであり、直し方は同じである。 |
| G03019 | modules/golem-project/src/Golem/Project/Style.hs:2137、2844 | 条件が一つしかない。 |
| G03021 | modules/golem-project/src/Golem/Project/Style.hs:2846、3262、3387 | 決まったキーの値の誤りだけであり、直し方はどれも値を書き換えることである。 |
| G03023 | modules/golem-driver/src/Golem/Driver.hs:252 | 条件が一つしかない。 |
| G03025 | modules/golem-project/src/Golem/Project/Style.hs:2839 | 違うのは欄だけであり、どれも値を直す。 |
| G03027 | modules/golem-driver/src/Golem/Driver.hs:956 | 条件が一つしかない。 |
| G03028 | modules/golem-project/src/Golem/Project/Manifest.hs:1008 | 違うのはキーだけである。 |
| G03029 | modules/golem-project/src/Golem/Project/Style.hs:2866 | 一つの関係の違反であり、gutter と size のどちらを直しても解ける。 |
| G03100 | modules/golem-project/src/Golem/Project/Style.hs:766、modules/golem-eval/src/Golem/Eval/Settings.hs:235 | 条件が一つしかない。 |
| G03101 | modules/golem-project/src/Golem/Project/Manifest.hs:535 | 違うのはキーの名前だけである。 |
| G03102 | modules/golem-driver/src/Golem/Driver/Functions.hs:77 | 条件が一つしかない。 |
| G03108 | modules/golem-driver/src/Golem/Driver.hs:742 | 条件が一つしかない。 |
| G03109 | modules/golem-project/src/Golem/Project/Manifest.hs:401 | 書けない型を書いたという同じ種類の誤りであり、違うのは型だけである。 |
| G03110 | modules/golem-project/src/Golem/Project/Manifest.hs:387 | 条件が一つしかない。 |
| G03111 | modules/golem-driver/src/Golem/Driver/ProjectVars.hs:61 | 名前がない場合も、途中が表でない場合も、参照が解決しないという同じ誤りである。 |
| G03112 | modules/golem-driver/src/Golem/Driver/ProjectVars.hs:64 | 条件が一つしかない。 |
| G03113 | modules/golem-typeset/src/Golem/Typeset/Draw.hs:381 | 条件が一つしかない。 |
| G03114 | modules/golem-project/src/Golem/Project/Style.hs:773 | 条件が一つしかない。 |
| G03115 | modules/golem-project/src/Golem/Project/Style.hs:774 | 条件が一つしかない。 |
| G03116 | modules/golem-project/src/Golem/Project/Style.hs:779 | 条件が一つしかない。 |
| G03117 | modules/golem-project/src/Golem/Project/Style.hs:788 | 条件が一つしかない。 |
| G03118 | modules/golem-project/src/Golem/Project/Style.hs:3271、modules/golem-eval/src/Golem/Eval/Settings.hs:197 | 条件が一つしかない。 |
| G03119 | modules/golem-project/src/Golem/Project/Manifest.hs:965 | 条件が一つしかない。 |
| G03120 | modules/golem-driver/src/Golem/Driver.hs:254 | 条件が一つしかない。 |
| G03121 | modules/golem-project/src/Golem/Project/Manifest.hs:441 | 条件が一つしかない。 |
| G03122 | modules/golem-project/src/Golem/Project/Manifest.hs:445 | 条件が一つしかない。 |
| G03123 | modules/golem-project/src/Golem/Project.hs:212 | 条件が一つしかない。 |
| G03124 | modules/golem-project/src/Golem/Project/Style.hs:2848、3389 | 違うのは誤った形だけであり、四つの形のどれかに書き直せば直る。 |
| G03125 | modules/golem-project/src/Golem/Project/Style.hs:2883 | 条件が一つしかない。 |
| G03126 | modules/golem-project/src/Golem/Project/Style.hs:2960、modules/golem-eval/src/Golem/Eval/Settings.hs:353 | 条件が一つしかない。 |
| G03127 | modules/golem-project/src/Golem/Project/Style.hs:2976 | 条件が一つしかない。 |
| G03128 | modules/golem-project/src/Golem/Project/Style.hs:2977 | 条件が一つしかない。 |
| G03129 | modules/golem-project/src/Golem/Project/Style.hs:2978 | 条件が一つしかない。 |
| G03130 | modules/golem-project/src/Golem/Project/Style.hs:2961、modules/golem-eval/src/Golem/Eval/Settings.hs:356 | 条件が一つしかない。 |
| G03131 | modules/golem-cli/app/Main.hs:480 | 条件が一つしかない。 |
| G03132 | modules/golem-cli/app/Main.hs:481 | エントリがある場合も、途中の要素がディレクトリでない場合も、そのエントリを移せば直る。 |
| G03133 | modules/golem-cli/app/Main.hs:479 | 条件が一つしかない。 |
| G03134 | modules/golem-cli/app/Main.hs:470 | 条件が一つしかない。 |
| G03254 | modules/golem-project/src/Golem/Project/Style.hs:2636 | 条件が一つしかない。 |
| G03255 | modules/golem-project/src/Golem/Project/Style.hs:2635 | 形の誤りも予約された名前も、名前を変えれば直り、直し方の種類が同じである。 |
| G03257 | modules/golem-project/src/Golem/Project/Style.hs:2646, 2691, 2715, 3343, 3359 | 欄か @style-def に書いた名前の宣言がないという一つの原因で、名前と場所が違うだけである。 |
| G03258 | modules/golem-project/src/Golem/Project/Style.hs:2694, 2717, 3346, 3358 | 参照した宣言の種類が欄と違うという一つの原因で、欄が違うだけである。 |
| G04001 | modules/golem-assemble/src/Golem/Assemble.hs:650 | ラベルの重複という一つの原因である。 |
| G04002 | modules/golem-assemble/src/Golem/Assemble.hs:422 | @toc が二つ以上あるという一つの原因である。 |
| G04003 | modules/golem-assemble/src/Golem/Assemble.hs:681 | 存在しないラベルへの参照という一つの原因である。 |
| G04004 | modules/golem-assemble/src/Golem/Assemble.hs:410 | 図版、表、コードに同じ検査をしており、直し方も同じである。 |
| G04005 | modules/golem-assemble/src/Golem/Assemble.hs:687 | 番号を持たない要素への番号の参照という一つの原因である。 |
| G04006 | modules/golem-assemble/src/Golem/Assemble.hs:691 | 題を持たない要素への題の参照という一つの原因である。 |
| G04007 | modules/golem-assemble/src/Golem/Assemble.hs:469 | 見出しとブロックかリストの項目かが違うだけで、@number を外せば直る。 |
| G04008 | modules/golem-assemble/src/Golem/Assemble.hs:514 | 本の末尾の改ページと改段は同じ扱いで、外せば直る。 |
| G04009 | modules/golem-assemble/src/Golem/Assemble.hs:581 | 本の末尾の @blank-line という一つの原因である。 |
| G04010 | modules/golem-assemble/src/Golem/Assemble.hs:583 | @blank-line の直後の改ページという一つの原因である。 |
| G04011 | modules/golem-assemble/src/Golem/Assemble.hs:548 | @blank-line の行数がページの行数以上という一つの原因である。 |
| G04012 | modules/golem-assemble/src/Golem/Assemble.hs:346 | 上限超えか 0 かが違うだけで、どれも表記で表せる範囲の外という同じ検査である。 |
| G04013 | modules/golem-assemble/src/Golem/Assemble.hs:405 | 図版について G04012 と同じ検査である。 |
| G04014 | modules/golem-assemble/src/Golem/Assemble.hs:406 | コードについて G04012 と同じ検査である。 |
| G04100 | modules/golem-assemble/src/Golem/Assemble.hs:407 | 表について G04012 と同じ検査である。 |
| G04101 | modules/golem-assemble/src/Golem/Assemble.hs:894 | 索引の「を見よ」の参照先がないという一つの原因である。 |
| G04102 | modules/golem-assemble/src/Golem/Assemble.hs:918 | 「を見よ」の参照の輪という一つの原因である。 |
| G04103 | modules/golem-assemble/src/Golem/Assemble.hs:891 | 索引の範囲の始めに終わりがないという一つの原因である。 |
| G04104 | modules/golem-assemble/src/Golem/Assemble.hs:892 | 索引の範囲の終わりに始めがないという一つの原因である。 |
| G05001 | modules/golem-lint/src/Golem/Lint.hs:120 | 欧文の間の改行という一つの原因である。 |
| G05002 | modules/golem-lint/src/Golem/Lint.hs:149 | 使われていない変数という一つの原因である。 |
| G05003 | modules/golem-lint/src/Golem/Lint.hs:167 | 使われていない import という一つの原因である。 |
| G05004 | modules/golem-lint/src/Golem/Lint.hs:178 | プロファイルで重大度が違うだけで、参照されていないラベルという一つの原因である。 |
| G05100 | modules/golem-parser/src/Golem/Parser.hs:207 | コメントの前か後かが違うだけで、空白を入れれば直る。 |
| G06002 | modules/golem-driver/src-plugins/Golem/Driver/Plugins.hs:135, 136 | lock にない場合も URL が違う場合も、golem plugin lock で直る。 |
| G06003 | modules/golem-driver/src-plugins/Golem/Driver/Plugins.hs:132 | キャッシュにないという一つの原因である。 |
| G06004 | modules/golem-driver/src-plugins/Golem/Driver/Plugins.hs:133 | キャッシュのハッシュの不一致という一つの原因である。 |
| G06006 | modules/golem-driver/src-plugins/Golem/Driver/Plugins.hs:192, 193 | コマンドかブロックコマンドかが違うだけで、片方のプラグインを外せば直る。 |
| G06008 | modules/golem-driver/src-plugins/Golem/Driver/Plugins.hs:195 | 二つの文言のどちらも、overrides からその名前を外せば直る。 |
| G06009 | modules/golem-driver/src-plugins/Golem/Driver/Plugins.hs:320 | 中身は多様だが、書き手の直し方は作者に報告することの一つであり、境界上の判断である。 |
| G06010 | modules/golem-driver/src-plugins/Golem/Driver/Plugins.hs:176 | 宣言されていないプラグインを指すフィルタという一つの原因である。 |
| G06011 | modules/golem-plugin/src/Golem/Plugin/Lock.hs:69, 72 | TOML、スキーマ、sha256 の形の誤りのどれも、lock を作り直せば直る。 |
| G06100 | modules/golem-driver/src-plugins/Golem/Driver/Plugins.hs:319 | 遅延した式の有限でない浮動小数点数という一つの原因である。 |
| G06101 | modules/golem-driver/src-plugins/Golem/Driver/Plugins.hs:281 | データのファイルがないという一つの原因である。 |
| G06102 | modules/golem-driver/src-plugins/Golem/Driver/Plugins.hs:260 | プラグインが受け取らないデータの名前という一つの原因である。 |
| G06103 | modules/golem-driver/src-plugins/Golem/Driver/Plugins.hs:270 | データの大きさの上限超えという一つの原因である。 |
| G06104 | modules/golem-driver/src-plugins/Golem/Driver/Plugins.hs:125 | プラグインのファイルがないという一つの原因である。 |
| G06105 | modules/golem-driver/src-plugins/Golem/Driver/Plugins.hs:140 | 渡せない文脈を求めるという一つの原因である。 |
| G06106 | modules/golem-driver/src-no-plugins/Golem/Driver/Plugins.hs:79 | プラグインの機能のないビルドでプラグインを使うという一つの原因である。 |
| G06107 | modules/golem-driver/src-plugins/Golem/Driver/Plugins.hs:178 | プラグインが提供していないフィルタという一つの原因である。 |
| G07002 | modules/golem-driver/src/Golem/Driver.hs:1086 | 日本式のトンボで塗り足しが 0 という一つの原因である。 |
| G07021 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:1412 | ページ番号の参照が収束しないという一つの原因である。 |
| G07022 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:2555 | width を書かない場合も行長の全幅になるだけで、width を小さくすれば直る。 |
| G07023 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:2556 | 回り込みの除外領域がページの行数を超えるという一つの原因である。 |
| G07024 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:3102 | 見出しが一ページの行数を超えるという一つの原因である。 |
| G07025 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:442 | 段落スタイルの名前が違うだけで、字下げが大きすぎるという一つの原因である。 |
| G07026 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:2552 | 段組みの版面での回り込みという一つの原因である。 |
| G07028 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:2965 | 回り込む図版の脇で字下げを引くと行が残らないことだけを報告する。 |
| G07029 | modules/golem-assemble/src/Golem/Assemble/ListMarkers.hs:161 | 書式ごとに上限が違うだけで、番号を書式で表せないという一つの誤りである。 |
| G07030 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:3564 | コードの行を折り返したという一つの事実を知らせる。 |
| G07032 | modules/golem-layout/src/Golem/Layout/Japanese.hs:2230 | 違うのは傍注を置いた場所だけで、どれも脚注に替えれば消える。 |
| G07034 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:1294 | `[sidenotes]` のない横組みで傍注を使ったという一つの原因である。 |
| G07035 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:1295 | 違うのは脚注の本文かキャプションかだけで、傍注をそこから出せば消える。 |
| G07038 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:2559 | `rotate` のときは比べる枠が違うだけで、キャプションを短くすれば消える。 |
| G07039 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:2542 | 高すぎる場合も広すぎる場合も、段に収めるため縮めたお知らせで、`width` を小さくすれば消える。 |
| G07041 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:2908 | 使える幅の求め方が違うだけで、列の最小の幅の合計が入らないという同じ検査である。 |
| G07042 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:2834 | 違うのはどの行かだけである。 |
| G07044 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:415 | 索引の段の行長が足りないという一つの原因である。 |
| G07045 | modules/golem-typeset/src/Golem/Typeset/Fonts.hs:376 | 入れ子の向きが違うだけで、ルビと圏点の組み合わせをやめれば消える。 |
| G07046 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:724, 725 | 違うのは見出しか段落かだけで、罫線を持つブロックが空の段に入らないという同じ事実である。 |
| G07047 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:702 | 段の先頭の `@blank-line` を捨てたという一つの事実である。 |
| G07050 | modules/golem-layout-spec/src/Golem/LayoutSpec.hs:329 | 隠しノンブルが版面に重なるという一つの原因である。 |
| G07051 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:909 | 柱の行が版面の幅を超えるという一つの原因である。 |
| G07052 | modules/golem-layout-spec/src/Golem/LayoutSpec.hs:291 | 柱の行がページの外に出るという一つの原因である。 |
| G07100 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:704 | 見出しが段の残りに入らないという一つの事実である。 |
| G07101 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:484 | ダッシュの字形に線がないという一つの事実である。 |
| G07102 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:1331 | 表記ごとに上限が違うだけで、注の番号を表せないという一つの誤りである。 |
| G07103 | modules/golem-typeset/src/Golem/Typeset/Draw.hs:385 | 最初の見出しが 1 でない場合も段を飛ばす場合も、見出しの段を直せば消える。 |
| G07104 | modules/golem-typeset/src/Golem/Typeset/Draw.hs:415 | PDF/A-2a に私用領域の字があるという一つの原因である。 |
| G07105 | modules/golem-typeset/src/Golem/Typeset/Draw.hs:370 | 違うのははみ出す内容だけで、行が行長からはみ出すという一つの事実である。 |
| G07106 | modules/golem-typeset/src/Golem/Typeset/Draw.hs:326 | ノンブルを `format` の表記で表せないという一つの原因である。 |
| G07107 | modules/golem-typeset/src/Golem/Typeset/Draw.hs:351 | 原稿からは起こせない内部の不変条件の破れで、原因は一つである。 |
| G07108 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:2827 | 表のセルが上限を超えるという一つの原因である。 |
| G07109 | modules/golem-typeset/src/Golem/Typeset/Draw.hs:263 | 二つの場面は、どちらもセクションにページがないという同じ事実である。 |
| G07110 | modules/golem-typeset/src/Golem/Typeset/Draw.hs:248 | セクションの `style` でノンブルを表せないという一つの原因である。 |
| G07111 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:708 | 違うのは守れなかった場面だけで、`keep-with-next` を守れなかったという一つの事実である。 |
| G07112 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:710 | `keep-all-lines` の段落を分けたという一つの事実である。 |
| G07113 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:712 | 違うのは最初の部分か最後の部分かだけである。 |
| G07114 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:2909 | 指定した列の幅の合計が超えるという一つの原因である。 |
| G07115 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:2910 | 違うのはどの列かだけである。 |
| G07116 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:2891 | `caption-position` で組み合わせが違うだけで、原因は一つである。 |
| G07117 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:1045 | 違うのはどの階層かだけである。 |
| G07118 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:1203 | 索引の範囲が逆向きであるという一つの原因である。 |
| G07119 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:1204 | 索引の範囲がセクションをまたぐという一つの原因である。 |
| G07120 | modules/golem-typeset/src/Golem/Typeset/Draw.hs:576 | 原稿からは起こせない内部の不変条件で、リンクとしおりは同じ照合である。 |
| G07121 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:3164 | 囲みの一行と上下の `padding` が段に入らないという一つの原因である。 |
| G07122 | modules/golem-typeset/src/Golem/Typeset/Draw.hs:370 | 改行しない範囲が行に収まらないという一つの原因である。 |
| G07123 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:1263 | 違うのはソフトハイフンを置いた場所だけで、ソフトハイフンを消せば消える。 |
| G07124 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:1264 | 違うのは改行しない文字の種類だけである。 |
| G07125 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:604 | 脚注の印と本文の一行が段に入らないという一つの原因である。 |
| G07126 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:500 | 約物の字面が隣の字にかかるという一つの事実である。 |
| G08001 | modules/golem-typeset/src/Golem/Typeset/Fonts.hs:181 | 試験だけで使う `noFontProvider` から出るもので、原因は一つである。 |
| G08003 | modules/golem-typeset/src/Golem/Typeset/FontProvider.hs:72 | フォントを OpenType として開けないという一つの原因である。 |
| G08004 | modules/golem-typeset/src/Golem/Typeset/FontProvider.hs:73 | `fsType` のどのビットでも、フォントを替えれば消える。 |
| G08005 | modules/golem-typeset/src/Golem/Typeset/FontProvider.hs:101 | PostScript 名が重なるという一つの原因である。 |
| G08007 | modules/golem-typeset/src/Golem/Typeset/Fonts.hs:245-251 | 役割がないことも、本文の役割にファイルがないことも、本文の役割に `ja` か `latin` を書けば直る。 |
| G08008 | modules/golem-typeset/src/Golem/Typeset/Fonts.hs:340 | コードがあるのに `[fonts.code]` がないという原因が一つだけである。 |
| G08009 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:472 | 違うのは役割と圏点の形だけで、同じ種類の誤りである。 |
| G08011 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:3710 | 違うのは、SVG の範囲の外にあるものがどれかだけである。 |
| G08013 | modules/golem-driver/src/Golem/Driver.hs:1142 | 違うのは、シンボリックリンクになっている出力先のフォルダーがどれかだけである。 |
| G08015 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:3714 | ページの内容をつなぐと 256 MiB を超えるという原因が一つだけである。 |
| G08016 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:3711 | marker が循環するという原因が一つだけである。 |
| G08017 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:3712 | marker の入れ子が深すぎるという原因が一つだけである。 |
| G08018 | modules/golem-typeset/src/Golem/Typeset/FontProvider.hs:293 | CFF のフォントから CFF の表を取り出せないという原因が一つだけである。 |
| G08019 | modules/golem-typeset/src/Golem/Typeset/FontProvider.hs:109、modules/golem-driver/src/Golem/Driver.hs:872 | 同じ CFF2 の検査を、check と build の二つの段で出している。 |
| G08020 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:3715 | ストリームの番号が大きすぎるという原因が一つだけである。 |
| G08100 | modules/golem-driver/src/Golem/Driver.hs:1353 | 違うのは、フォントにない字とフォントがどれかだけである。 |
| G08101 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:3713 | marker が描く線分が多すぎるという原因が一つだけである。 |
| G08102 | modules/golem-driver/src/Golem/Driver.hs:917 | 出力のパスがプラグインの画像のフォルダーと重なるという原因が一つだけである。 |
| G08103 | modules/golem-typeset/src/Golem/Typeset/Draw.hs:741 | 違うのは、フォントにない OpenType の機能とフォントがどれかだけである。 |
| G08104 | modules/golem-driver/src/Golem/Driver.hs:1145 | 出力先に通常のファイルがあるという原因が一つだけである。 |
| G08105 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:3707 | 図版の PDF が暗号化されているという原因が一つだけである。 |
| G08106 | modules/golem-typeset/src/Golem/Typeset/Flow.hs:3708 | 指定したページがないという原因が一つだけである。 |
| G09001 | modules/golem-project/src/Golem/Project/Manifest.hs:821, 859 | TOML の構文の同じ検査を、通常の経路と回復の経路で出している。 |
| G09002 | modules/golem-preflight/src/Golem/Preflight.hs:195 | 違うのは、glyph 0 で描いた字とフォントがどれかだけである。 |
| G09003 | modules/golem-preflight/src/Golem/Preflight.hs:201 | 設定が許さない形式のフォントという原因が一つだけである。 |
| G09004 | modules/golem-preflight/src/Golem/Preflight.hs:224 | 違うのは、本文とルビと圏点のどれかと定義だけで、どれも size を上げれば直る。 |
| G09006 | modules/golem-preflight/src/Golem/Preflight.hs:256 | 違うのは画像の種類と閾値だけで、同じ解像度の検査である。 |
| G09007 | modules/golem-preflight/src/Golem/Preflight.hs:277 | 解像度が上限を超えるという原因が一つだけである。 |
| G09008 | modules/golem-preflight/src/Golem/Preflight.hs:316 | 設定が許さない色空間という原因が一つだけである。 |
| G09009 | modules/golem-preflight/src/Golem/Preflight.hs:335 | ICC プロファイルが出力インテントと違うという原因が一つだけである。 |
| G09010 | modules/golem-preflight/src/Golem/Preflight.hs:357 | 塗り足しが足りないという原因が一つだけである。 |
| G09011 | modules/golem-preflight/src/Golem/Preflight.hs:375 | 違うのは辺だけで、同じ幾何の検査である。 |
| G09012 | modules/golem-preflight/src/Golem/Preflight.hs:394 | 違うのは要素の種類と辺だけで、どれも安全域の内に寄せれば直る。 |
| G09013 | modules/golem-preflight/src/Golem/Preflight.hs:425 | 行が行長からはみ出すという原因が一つだけである。 |
| G09014 | modules/golem-preflight/src/Golem/Preflight.hs:440, 443 | 原稿で起こせるのは出力インテントがないことだけで、ほかの要件は Golem が書く PDF の不変条件である。 |
| G09015 | modules/golem-preflight/src/Golem/Preflight.hs:457 | 違うのはスウォッチだけである。 |
| G09016 | modules/golem-preflight/src/Golem/Preflight.hs:472 | ページ数が倍数でないという原因が一つだけである。 |
| G09017 | modules/golem-preflight/src/Golem/Preflight.hs:479 | 空白のページがあるという原因が一つだけである。 |
| G09018 | modules/golem-preflight/src/Golem/Preflight.hs:485 | 違うのは線の種類だけである。 |
| G09019 | modules/golem-preflight/src/Golem/Preflight.hs:497 | フォントを埋め込んでいないという原因が一つだけである。 |
| G09020 | modules/golem-preflight/src/Golem/Preflight.hs:505 | 違うのは色材の名前だけである。 |
| G09021 | modules/golem-preflight/src/Golem/Preflight.hs:520 | 違うのは色空間と成分だけである。 |
| G09100 | modules/golem-driver/src/Golem/Driver.hs:1002 | `--rules` で指したファイルがないという原因が一つだけである。 |
| G09101 | modules/golem-driver/src/Golem/Driver.hs:1007 | 設定のファイルが UTF-8 でないという原因が一つだけである。 |
| G09103 | modules/golem-project/src/Golem/Project/Manifest.hs:828 | 違うのは、知らないキーがどれかだけである。 |
| G09104 | modules/golem-project/src/Golem/Project/Manifest.hs:822 | TOML の定義が衝突するという原因が一つだけである。 |

## 未調査

G01022 と G01029 は、判定しなかった。
G01022 はラベルのない構文エラーのコードであり（modules/golem-parser/src/Golem/Parser.hs:179）、docs/diagnostics.md が今の文法では起こらないと書くとおり、入力から再現できない。
G01029 はコードを割り当てていない文法のラベルのコードであり（modules/golem-parser/src/Golem/Parser.hs:178）、modules/golem-parser/grammar/Golem.hpeg のラベル 16 種はすべて `labelCode` にあるので、入力から再現できない。

候補の条件のうち、E02101 の型の別名の循環（modules/golem-emet/src/Golem/Emet/Check.hs:421）は再現しなかった。
`type A = B` と `type B = A`、`type A = A`、`type A = List A` のどれを書いても、`golem check` は終了コード 0 で診断を出さなかった。
E02101 は、ほかの条件で候補と判定した。

単一と判定したコードのうち、次の判定はコードを読んで下し、実行では確かめていない。
G09014 は、出力インテントのほかの要件（TrimBox、Trapped、PDF の版、ICC のない RGB、JavaScript と外への参照）が、図版から取り込む PDF の中身で起きるかを確かめていない。
E03100、E05104、E06101 の評価の側の発生箇所（modules/golem-emet/src/Golem/Emet/Eval.hs:317、356、modules/golem-emet/src/Golem/Emet/Gm.hs:122）は、静的な検査を通った後には届かないと見たが、確かめていない。

## 付記

監査の途中で、分割候補のほかに、docs/diagnostics.md と実装の食い違いと、同じ原因が二つのコードに分かれている箇所が見つかった。
この記録では直さず、ここに残す。

docs/diagnostics.md の E02101 は型の別名の循環をこのコードとすると書くが、上の「未調査」のとおり、循環は報告されなかった。
循環する別名をシグネチャで使うと、循環のメッセージではなく「型が合いません: A を求める位置に Nat があります」が出た。

docs/diagnostics.md の G02025 の「主な原因」と「直し方」は depth を 1 から 3 と書くが、メッセージと実装（modules/golem-eval/src/Golem/Eval/File.hs:574）は 1 から 6 である。
docs/diagnostics.md の G02092 は引数を 1 以上の整数と書くが、実装のメッセージは 0 以上の整数であり（modules/golem-eval/src/Golem/Eval/File.hs:1160）、[ADR 0345](../adr/0345-revise-unitless-zero-in-length-fields.md) で 0 を受け付けるようになった後の振る舞いと合う。
docs/diagnostics.md の G02055 のメッセージは量の候補に単位のない 0 を含まないが、CLI が出したメッセージは含んでいた。
docs/diagnostics.md の G02133 と G02135 は 0 の幅もこのコードとするが、メッセージは「読めません」であり、読めるが 0 という値に合わない。

docs/diagnostics.md の G03001 は、主な原因に出力ターゲットを一つも書いていないことを挙げる。
しかし、tempest の写しから `[targets.*]` の表をすべて消しても、終了コード 0 で診断は出なかった。
G03001 が出たのは、空の `[targets]` を書いたときだけである。

docs/diagnostics.md の G03022 は理由に「寸法として読めません」を挙げるが、`[lists]` の `gap = "wide"` は G03257 になり、modules/golem-project/test/Main.hs:1590 も G03257 を期待している。
docs/diagnostics.md は、`[lists]` の未知のキーが G03022 に、`[aki-sets]` の未知のキーが G03020 に、`[page.size]` の未知のキーが G03017 になることを、主な原因に挙げていない。
docs/diagnostics.md の G03256 は、メッセージの行を持たず、意味に表の形の誤りと、宣言の中の未定義の名前と種類の違う参照を書いていない。
modules/golem-project/src/Golem/Project/Style.hs:2646 の G03257 は、宣言の名前の一覧を回るときだけ呼ばれるので、どの入力でも出ない。

docs/diagnostics.md の G07027 の意味は図版の脇の場合を書くが、そのときのメッセージは「リストの入れ子が深く」のままであり、書き手を誤った箇所へ導く。
docs/diagnostics.md の G08014 の見出しは「動的なコンテンツがあります」だが、読めない SVG にも同じ見出しとメッセージで出る。

名前空間のない未定義の関数は G02061（modules/golem-eval/src/Golem/Eval/Expr.hs:353）、名前空間のある未定義の関数は G02002（modules/golem-eval/src/Golem/Eval/Expr.hs:321）であり、同じ原因が二つのコードに分かれている。
G02009 と G02022 は、名前空間にない名前が別の種類のコマンドとしてあるとき、メッセージのヒントで知らせるだけで、コードは同じである（modules/golem-eval/src/Golem/Eval/File.hs:755、782）。
G02142 の名前に使えない字を含む条件と、G03015 の括弧が閉じない正規表現、`[aki-sets]` と `[lists]` の未知のキーには、旧コードを期待する試験がない。
