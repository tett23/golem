# 文法から生成する認識モデルの証明

この実験は、[root ADR 0351](../../../docs/adr/0351-prove-parser-formatter-round-trips.md) に従って、Golem の文法と Lean の認識モデルを照合する。
`generate.mjs` は Cabal の plan が選んだ `peg-grammar` で `Golem.hpeg` を読み、PEG の抽象構文木（AST）から `Generated.lean` を生成する。
実際のルールと選択肢の順序をモデルへ渡す。

## 実行方法

リポジトリのルートで、Lean 4.7.0 と Node.js、GHC、Cabal、`peg-hs` を使う。
Cabal の plan とパッケージデータベースには `peg-grammar` と `aeson` が必要である。
`peg-hs parse` は PATH の `ghc` を使うため、先に `ghc --numeric-version` が `9.10.3` となる環境を用意する。
次の版の検査が失敗した場合は、PATH を直してから続ける。
既存の CI が使う準備と、ローカルでの検証コマンドは次のとおりである。

```sh
test "$(ghc --numeric-version)" = 9.10.3
cabal build peg-cli:exe:peg-hs
cabal build --only-dependencies lib:golem-bibliography
export PEG_HS="$(cabal list-bin peg-cli:exe:peg-hs)"
node experiments/parser-fmt-proof/grammar/test.mjs
```

ビルド先を分けている場合は、`CABAL_PLAN` にそのビルド先の `cache/plan.json` を指定する。
`LEAN` で Lean の実行ファイルを指定できる。
`PEG_HS` は上のようにプロジェクトが固定する実行ファイルを指定し、システムに別途入れた `peg-hs` に任せない。
生成器が呼ぶ `runghc` の版とパッケージ ID は plan から求める。
`test.mjs` は一時ディレクトリでモデルを生成し、Lean の証明、文法を変えた反例、`peg-hs` の実際の解析結果を確かめる。

未証明の選択肢との一致だけを調べる場合は、次を実行する。
最後の引数は生成先である。

```sh
node experiments/parser-fmt-proof/grammar/check-deferred.mjs \
  modules/golem-parser/grammar/Golem.hpeg \
  experiments/parser-fmt-proof/grammar/deferred-choices.txt \
  /tmp/Golem-Generated.lean
```

## ReservedRange の任意入力の証明

`ReservedRangeTotal.lean` は、任意の入力について、`ReservedRange` の認識結果を証明する。
先頭が `...` なら通常の不一致となり、先頭が `..` で `...` でなければ `reserved` のラベルエラーとなる。
それ以外も通常の不一致となる。
認識モデルは、再帰の深さと繰り返しの回数の上限に fuel を使う。
この定理は、任意の自然数に 7 を足した fuel で成り立ち、入力の長さの上限は置かない。

このルールでは、二つの先読みが通っても、直後の偽の述語でラベルエラーとなる。
そのため後続の省略可能な式と繰り返しには到達しない。
証明は、生成されたルールの後続部分をそのまま保持し、任意の後続部分について停止結果が変わらないことを示す。
後続の解析が成功するという仮定や、再帰呼出しが正しいという仮定は置かない。
生成器は後続部分も含むルール全体を照合し、一部でも変われば未証明の一覧に戻す。

回帰テストは、否定の先読み、肯定の先読み、偽の述語、ラベル、後続の量指定子、入れ子の選択順を変え、未証明として検出する。
さらに、生成済みモデルのラベルだけを変えると Lean の定理が通らないことを確かめる。
`peg-hs` の CST（具象構文木）の出力では、偽の述語を真に変えると、元は拒否した `[= 1..2]` を受けいれることも確かめる。

## 保証の範囲と残件

認識モデルの結果は、残りの入力を返す成功、通常の不一致、ラベルエラーなどのエラーである。
文法の Haskell アクションの戻り値、CST から作る AST の値や、ラベルエラー後の復旧結果は、この結果に含まれない。
認識の合成は全選択肢について証明し、`deferred-choices.txt` は空になった。
以下の各増分の選択肢の個数は、その増分を終えた時点の記録である。
復旧後の AST や `golem fmt` の往復を証明したことにはならない。

未証明の選択肢は `deferred-choices.txt` に列挙する。
`check-deferred.mjs` は実際の未証明の一覧との差分で失敗し、一覧に無い追加と、証明できたのに残った行の両方を検出する。
子の再帰全体、Haskell の戻り値、AST、整形、評価の一般的な往復の照合は残っている。
語と引用値のキーワード引数のモデルは、限った構文領域で値の往復も示すが、Golem の AST 全体との一般的な対応ではない。
全範囲が終わるまで [root ADR 0351](../../../docs/adr/0351-prove-parser-formatter-round-trips.md) の未実装のステータスを保つ。

## 予約括弧内のコメントの証明

`ReservedCommentTotal.lean` は、`ReservedBracketBody` の中の `'%%' (!'%%' ![\n] .)* '%%'` を、任意の入力について証明する。
先頭の `%%` があり、その同じ行に閉じる `%%` があれば、閉じ区切りまでを消費して残りを返す。
先頭の区切りがない場合と、改行か入力末までに閉じ区切りがない場合は、この選択肢は通常の不一致になる。
コメントの中の `]` は、予約括弧の終わりにはしない。

一般形では、任意の文法、環境、区切り文字列に対し、入力の長さに 6 と任意の自然数を足した fuel で結果が一致する。
入力の長さには上限を置かない。
実文法の定理は、生成した `ReservedBracketBody` の選択肢を取り出した値を直接使い、手書きの代用ルールだけを証明する形にはしていない。
前提と公理の詳しい記録は [証明の依存関係](../../../docs/research/0351-reserved-comment-proof-dependencies.md) にある。

テストは、開きと閉じ区切り、区切りの先読み、改行の先読み、繰り返し、本文の一文字を変え、未証明として検出する。
生成した AST の先読みを変えると、実文法の定理も失敗する。
実パーサーとの照合では、既存の `ReservedBracketBody` を `%entry` で公開しただけの文法を使う。
この入口で空のコメント、`]` を含むコメント、和文を含むコメントを最後まで読み、区切りの先読みを逆にした文法では対照を拒むことを確かめる。
これらは復旧用のルールの CST の照合であり、正しい原稿の往復例には数えない。

予約括弧の本体全体、入れ子の括弧、復旧後の AST の一般的な証明は残っている。

## 箇条書きと番号付きリストの合成

`ListCompositionTotal.lean` は、実文法の `BulletList` と `OrderedList` を、最初の `ListItem` と、空行を省略できる後続の繰り返しへ分解する。
任意の入力、自然数の字下げ量、fuel で、生成したルールの結果と、この分解による走査の結果が一致する。
最初の項目の成功、不一致、エラーをすべて扱い、繰り返しで入力が進まない場合のエラーも保つ。
項目の解析が成功するという仮定は置かない。

この証明は認識処理の合成を扱う。
子である `ListItem` と `ItemTail` の再帰全体、CST から Haskell が作る AST、整形の往復の証明は残る。
前提と公理、直接参照と間接参照の区別は [依存関係の記録](../../../docs/research/0351-list-composition-proof-dependencies.md) にある。

回帰では、各ルールの繰り返しの下限、空行の省略、最初と後続の項目種別を変え、未証明の一覧へ戻ることを確かめる。
生成済み AST の最初の項目種別を変えた対照では、同じ Lean 定理が失敗する。
実パーサーでは、項目一つと三つ、途中の空行、和文と補助平面の文字、タイ語を含む原稿を読み切る。
繰り返しを一回以上に変えた文法は項目一つの対照を拒否し、空行を必須にした文法は隣り合う二つの項目を別々のリストへ分ける。

## 定義リストの合成

`DefinitionCompositionTotal.lean` は、実文法の `DefList`、`DefGroup`、`DefBody` の認識を合成する。
最初のグループ、用語の一回以上の繰り返し、本文の先読み、後続のグループや本文の走査を、実際の生成ルールから取り出す。
各定理は任意の入力、自然数の字下げ量と fuel を扱い、入口へ `fuel + 3` を渡す。
子が成功するという前提は置かず、通常の不一致、子のエラー、打ち切りと入力が進まない反復のエラーを保つ。
前提、公理と定理間の依存は [依存関係の記録](../../../docs/research/0351-definition-composition-proof-dependencies.md) にまとめる。

回帰では、三つの規則の繰り返しの下限、空行の省略、先読み、最初と後続のルール参照、字下げ引数を変える。
これらの文法変異を未証明として検出し、生成済みの PEG の AST を変えた三つの対照では Lean の定理が通らないことを確かめる。
実パーサーでは、グループや本文が複数ある例、空行の有無、リスト内へ入れ子にした定義リストを読み切る。
反復の下限、空行の省略、本文参照や先読みを変えた四つの native parser とも照合する。

この増分は、子の解析結果を保持した認識処理の合成である。
子である `Block` などを含む再帰全体、CST から Haskell が作る AST の値、復旧、コメントを含む CST、整形と評価の一般的な往復は証明していない。
全範囲が終わるまで [root ADR 0351](../../../docs/adr/0351-prove-parser-formatter-round-trips.md) の未実装の状態を保つ。

## ブロック列の合成

`BlockSequenceTotal.lean` は、`Blocks`、`ItemTail`、`DivBlocks` の認識を反復の走査へ分解する。
`Blocks` は最初の `Block` の後に、空行と先読みを含む後続のブロックを走査する。
`ItemTail` と `DivBlocks` は、ゼロ回からの反復を扱う。
`DivBlocks` の閉じ行を調べる否定の先読みも、反復の一部として保持する。
子の成功は仮定せず、任意の入力、自然数の字下げ量と fuel について、不一致、子のエラー、打ち切り、入力が進まない反復のエラーを保つ。
入口の fuel は `Blocks` が `fuel + 3`、残りの二つが `fuel + 2` である。
詳しい命題と依存関係は [証明の記録](../../../docs/research/0351-block-sequence-proof-dependencies.md) にある。

回帰は、三つの規則の下限、空行、先読み、ルール参照と字下げ引数の変異を検出する。
生成した PEG の AST を変えた対照では、同じ Lean の定理が失敗する。
実パーサーでは、三つの段落、末尾にブロックを持たないリスト、末尾の見出しや複数の段落、空と複数ブロックの囲みを読み切る。
一回以上に変えた反復と、閉じ行の先読みを外した native parser とも照合する。

`Blocks` と `ItemTail` は `%inline` により通常の CST では省略される。
これら二つの表示指定だけを外した文法でも同じ六つの原稿を解析し、補助ノードを確認する。
追加された補助ノードを取り除いた CST は、子の順序と入力の範囲を含め、元の文法の CST と一致する。
この対照は表示指定を変えた有限の例であり、認識規則を手書きの代用品へ置き換えるものではない。

この増分も認識処理の合成に限る。
子ルールを含む再帰全体、CST から Haskell が作る AST、復旧、コメントの保存、整形と評価の一般的な往復は未完了である。
[root ADR 0351](../../../docs/adr/0351-prove-parser-formatter-round-trips.md) の未実装の状態を保つ。

## ファイル入口の合成

`FileCompositionTotal.lean` は、実際の `File` を、先頭の空行、空でない本文、末尾の空行の処理へ分解する。
任意の入力、呼出し元の環境と自然数の fuel を扱い、子の成功や結果の一致は仮定しない。
入口へ `fuel + 6` を渡し、三つの子の解析へ順に `fuel + 3`、`fuel + 2`、`fuel + 1` を渡す。
省略可能な式が不一致なら、その式の開始位置を返す。
子のエラーはそのまま保ち、本文の肯定の先読みは入力を消費せずに空かどうかを調べる。

一般の文法を扱う補助定理は、`File` の検索結果と構造の一致を前提にする。
主定理は、実際の生成文法でこの一致を証明してから使う。
前提と公理、生成された補助定理を含む依存関係は [証明の記録](../../../docs/research/0351-file-composition-proof-dependencies.md) にある。

回帰は、前後の空行や本文を必須にする変更、先読みの反転、本文の字下げ引数の変更を検出する。
生成した PEG の AST を変えた三つの対照でも Lean の証明が失敗する。
実パーサーの六つの原稿は、空の入力と空行だけの入力、前後の空行、複数の段落と Unicode の文字を含む。
四つの native parser の変異は、境界の対照を拒否する。

モデルの `File` の式には EOF がなく、成功時の残りも結果に含む。
入口での読み切りの有限の照合を、任意の原稿を読み切る証明とは数えない。
子ルールを含む再帰全体、AST、復旧、コメントの保存、整形と評価の一般的な往復は未完了である。
[root ADR 0351](../../../docs/adr/0351-prove-parser-formatter-round-trips.md) の未実装の状態を保つ。

## コマンドの本体を選ぶ合成

`BodyDispatchTotal.lean` は、`CommandBody` と `GroupBody` の認識を合成する。
任意の入力、自然数の字下げ量と fuel を扱い、入口へ `fuel + 3`、子へ `fuel + 1` を渡す。
子の成功や結果の一致は仮定しない。
`CommandBody` は字下げした本文の先読みの後にブロック列を読む。
`GroupBody` は囲みを先に試し、通常の不一致の場合だけ、同じ入力で直後の本体を試す。
子の成功とエラーはそのまま保ち、エラーの場合に後続の選択肢へ進まない。

字下げ本体の先読みは、定義リストが使う既存の `DefinitionCompositionTotal.bodyGuard` を共有する。
共有先の定義リストの定理を仮定するのではなく、この認識式を実際の生成ルールと照合する。
前提と公理、生成された補助宣言を含む依存関係は [証明の記録](../../../docs/research/0351-body-dispatch-proof-dependencies.md) にある。

回帰は、先読み、字下げ引数、子の参照と選択順の変異を検出する。
生成した PEG の AST を変える五つの対照でも Lean の証明が失敗する。
通常の八つの原稿では、直後の段落、見出し、リスト、空と複数ブロックの囲み、続けたコマンド、囲みの開始印に似た本文、一段落の字下げ本体を読み切る。
二段落の字下げ本体は、G02290 のための認識経路だけを別に確かめ、正常な CLI 原稿の照合には数えない。
六つの native parser の変異は、入力の拒否と、本体や囲みの CST の違いで検出する。

子ルールを含む再帰全体、コマンドの返す値、AST、復旧、コメントの保存、整形と評価の一般的な往復は未完了である。
[root ADR 0351](../../../docs/adr/0351-prove-parser-formatter-round-trips.md) の未実装の状態を保つ。

## リスト項目と囲みの合成

`BlockRemainderTotal.lean` は、`ListItem` と `Div` の子の認識を順に合成する。
任意の入力、自然数の引数と fuel を対象にし、入口へ `fuel + 3`、直接の子へ `fuel + 1` を渡す。
項目本文の一回以上の反復は、`PlusComposition.scanPlus` に移す。
子の成功や結果の一致は仮定せず、不一致、エラー、fuel の打ち切りと、入力が進まない反復のエラーを保つ。
囲みの `fenced ind` と、閉じ行の前の空行を含む省略可能な式も、そのまま残す。

行番号と `()` を返す action の空白は、認識する式の構造と区別して照合する。
十二の文法変異と八つの生成済み AST の変異は証明を無効にし、行番号と空白だけの二つの AST の変更では証明が通る。
前提と公理、生成された補助宣言を含む依存関係は [証明の記録](../../../docs/research/0351-list-item-and-div-proof-dependencies.md) にある。

通常の十六の原稿では、`-` と `+` の項目、空白、改行の有無、後続のブロック、空の囲みと入れ子、Unicode の文字を読み切る。
本文が空の二つの項目は拒否する。
閉じ印がない囲みの一例は、G01030 のための認識経路だけを別に確かめ、正常な CLI 原稿の照合には数えない。
八つの native parser の変異は、受理と拒否、本体や閉じ印の CST の違いで検出する。

子ルールを含む再帰全体、コマンドの返す値、AST、復旧、コメントの保存、整形と評価の一般的な往復は未完了である。
[root ADR 0351](../../../docs/adr/0351-prove-parser-formatter-round-trips.md) の未実装の状態を保つ。

## 予約構文を読み飛ばす処理の合成

`RecoveryDispatchTotal.lean` は、`SkippedReserved` の四つの選択肢を、実文法と同じ順に合成する。
`ReservedBodyCompositionTotal.lean` は、`ReservedBracketBody` の反復と、その内部にある角括弧の入れ子を合成する。
任意の入力、環境と fuel について、子の成功を仮定せず、不一致とエラーを保つ。
本体の反復は、入力の残りかエラーを返し、通常の不一致は返さないことも証明する。
これは入口が入力の末尾まで受理するという意味ではない。
前提と公理、依存関係と残件は [証明の記録](../../../docs/research/0351-reserved-recovery-proof-dependencies.md) にある。

`UnboundSequenceTotal.lean` は、名前付きの束縛が外側の要素にない列を、子の認識を順に呼ぶ処理へ移す。
この構文上の条件の下では、環境は列の途中で変わらない。
名前付きの本体や表のセル数を束縛する列には、この補題を適用しない。

回帰は、十六の文法変異と八つの生成済み AST の変異を拒否し、束縛のない列の補題を壊す一つの変異も検出する。
行番号と unit action の空白だけを変えた二つの AST は、証明を保つ。
実パーサーでは十八例を入力の末尾まで読み、七例の入口を拒否する。
二十五の例で、モデルの入力の残りと、実パーサーの入口の受理と拒否を照合する。
閉じていない `[!abc` は、モデルが短い `[!` の選択肢へ戻って `abc` を残すが、実パーサーのエラー位置は先行の選択肢が失敗した位置になる。
エラー位置を残りの入力の長さから求める性質は証明していない。

この増分で未証明の選択肢は九個から六個になる。
再帰全体、コマンドの値、AST、復旧後の文書、コメントの保存、整形と評価の一般的な往復は未完了である。
[root ADR 0351](../../../docs/adr/0351-prove-parser-formatter-round-trips.md) の未実装の状態を保つ。

## 表の行とコマンドの認識の合成

`TableRowCompositionTotal.lean` と `CommandRecognitionTotal.lean` は、`TableRow` と `BlockCommand` の三つの選択肢を合成する。
任意の入力、自然数の字下げ量と fuel に対して、子の成功を仮定せず、不一致とエラーを保つ。
入口へ `fuel + 2`、子へ `fuel` を渡す。
`BlockCommand` の設定と通常の呼び出しの順も保つ。

両方のルールに名前付きの束縛があるが、その場の認識には値を使わない。
`InertCaptureSequenceTotal.lean` は、モデルの値取得関数が列のすべての要素で値を返さないとき、環境が変わらないことを示す。
この条件は、実際の二つのルールについて構文とモデルの実装を照合して満たす。
本体の有無やセル数という Haskell の戻り値を一般に復元する証明ではない。
公理と前提、依存関係とこの区別は [証明の記録](../../../docs/research/0351-inert-capture-proof-dependencies.md) にある。

実パーサーでは、セル数の七例とコマンドの Bool の七例を読み切り、入口が七例を拒否する。
名前付きの束縛の環境を壊す一つの変異、十五の文法変異、十一の生成済み AST の変異を検出する。
行番号だけを変えた二つの AST は、証明を保つ。
二十一例で、モデルの接尾辞やエラーと、実パーサーの入口の受理と拒否を照合する。
戻り値の一般的な対応、子の再帰全体、復旧、AST、コメントの保存、整形と評価の往復は未完了である。
[root ADR 0351](../../../docs/adr/0351-prove-parser-formatter-round-trips.md) の未実装の状態を保つ。

## 値の束縛を保つ列と表の合成

`CapturedSequenceTotal.lean` は、名前付きの束縛で環境が変わる列も合成する。
認識器と値取得関数は任意で、子が成功するという前提や、環境が変わらないという前提は置かない。
値取得関数が返すエラーも、そのまま保つ。

`TableCompositionTotal.lean` は、この一般補題を実際の `Table` と `TableBodyRow` に適用する。
ヘッダーのセル数を `h` に束縛し、本文行のセル数 `r` と比べる環境を保つ。
任意の入力、自然数の字下げ量と幅、fuel に対して、入口へ `fuel + 2`、子へ `fuel` を渡す。
値取得の式を記述した `CapturedValueTotal.lean` は、現行モデルの同じ処理との一致を、主定理の型検査で照合する。
Haskell の `length cs` との一般的な対応を別に仮定するものではなく、その対応の証明は残件として保つ。
公理、前提、定理の直接参照と間接参照は [証明の記録](../../../docs/research/0351-captured-table-proof-dependencies.md) にある。

回帰は七つの文法変異、十の生成済み AST の変異、環境を更新しない変異、セル数を数えない変異を検出する。
行番号と unit action の空白だけを変えた二つの AST は、証明を保つ。
実パーサーの入口は、ヘッダーだけ、複数列、Unicode の文字を含む五例を読み切り、幅の不一致などの五例を拒否する。
同じ十例をモデルでも実行し、全入力の受理、不一致とラベルのエラーを照合する。
この照合を、一般の戻り値や診断位置の対応を示す証明とは区別する。

この表の増分の時点では、認識の合成が未証明の選択肢は `BlockGroup` の一つだった。
戻り値の一般的な対応、子の再帰全体、AST、復旧、コメントの保存、整形と評価の往復は未完了である。
[root ADR 0351](../../../docs/adr/0351-prove-parser-formatter-round-trips.md) の未実装の状態を保つ。

## Bool の束縛とコマンド群の合成

`BlockGroupCompositionTotal.lean` は、連続するコマンドから本体の有無の Bool を集め、最後の値が false のときだけ後続の本体を試す認識を示す。
入力、自然数の字下げ量と fuel は任意で、入口へ `fuel + 5` を渡す。
直接のコマンド群には `fuel + 3`、後続の本体には `fuel + 1` を渡す。
残りの fuel が 0 から 4 の場合も、五つの補題が入力によらず fuel のエラーになることを示す。
子の成功や、後で示す結果の一致を前提に置かない。

値を持つ補助モデルは、設定を false、通常の呼び出しを本体の有無に応じた Bool にし、反復の順で集める。
このモデルから値を除くと、現在の公開の認識器を同じ fuel で呼んだ結果と一致する。
コアの実装との一致も、`CorePayloadCoherence.lean` と `CachedPayloadCoherence.lean` が示す。
値を再計算するときは、より小さい fuel の認識器を保持した表から読む。
`StructuralCoherence.lean` は、この表の各認識器が公開の認識器と一致することを、fuel についての帰納法で示す。

モデルが扱う意味は、実際の `BlockCommand` の二つの action と、最後の Bool を検査する固定の述語に限る。
ほかの Haskell の式を解釈するものではない。
認識の合成に未証明の選択肢はなくなるが、戻り値の一般的な対応、子の再帰全体、AST、復旧、コメントの保存、整形と評価の往復は未完了である。
[root ADR 0351](../../../docs/adr/0351-prove-parser-formatter-round-trips.md) の未実装の状態を保つ。
公理と前提、依存関係と検査の範囲は [証明の記録](../../../docs/research/0351-boolean-command-group-proof-dependencies.md) にある。

## 引用値を持つキーワード引数の列

`QuotedKeywords.lean` は、語の名前と引用値の組を任意個書き出して読み戻すと、名前、StringLit の種類と復号値がすべて入力順に戻ることを示す。
名前には既存の Word の条件と、`%%` で始まらないという条件を使う。
値は任意長の Part の列で、空の値、引用符、バックスラッシュ、空白、Unicode の文字と `%%` も表せる。
語の値との混在や式、コメントを含む引数全体の一般証明ではない。

`QuotedCanonical.lean` は、この列を実際の `Generated.pegGrammar` の `Arguments` が読み、改行と任意の接尾辞を残すことを示す。
キーワードを位置引数として取らないこと、省略可能なコメント、繰り返しと引数順の検査も導く。
入口に子の成功や結果の一致を仮定しない。
`QuotedArgumentRules.lean` が実際の規則の形を照合し、行番号と unit action の空白だけの変更では証明が変わらない。

八つの共通の原稿の十二のキーワード出現で、モデルの名前、種類と復号値を確かめる。
同じ原稿を Golem.Parser.parseAst と通常の `golem fmt` に渡し、前後の値の一致と二度目のバイト列の不変も確かめる。
この有限の照合は、AST の全体と fmt の一般証明とは区別する。
Golem の入力全体の検査や、引数の宣言の検査までモデルにしたものではない。

Haskell の AST の照合は、既存の arguments の検査で動く。
単独で動かす場合は、プロジェクトが固定する GHC と、選んだ Cabal plan で CLI をビルドしてから、次を実行する。
ビルド先を分けるときは、その `cache/plan.json` を `CABAL_PLAN` に指定する。
検査は plan のコンパイラーとパッケージ ID を使い、`GHC` を指定した場合も版の一致を確かめる。

```sh
cabal build exe:golem
export GOLEM="$(cabal list-bin exe:golem)"
node --test experiments/parser-fmt-proof/arguments/quoted-values.native-test.mjs
```

公理、前提と残る範囲は [依存関係の記録](../../../docs/research/0351-quoted-keyword-proof-dependencies.md) にある。
[root ADR 0351](../../../docs/adr/0351-prove-parser-formatter-round-trips.md) の未実装の状態を保つ。

## 語と引用値を混ぜたキーワード引数の列

`MixedKeywords.lean` は、語と引用値を任意に混ぜた列を印字して読むと、名前、Word または StringLit の種類と値が入力順に戻ることを示す。
名前には Word の条件と、先頭が `%%` でない条件を使う。
語の値には `%%` を含まない条件を加え、引用値は既存の Part の領域を使う。
個数と並び順、名前の繰り返しには上限を置かない。

`MixedCanonical.lean` は、この列を実際の `Generated.pegGrammar` の `Arguments` が読み、改行と任意の接尾辞を残すことを示す。
語と引用値の各一般補題から、省略可能なコメント、位置引数の拒否、反復と引数順の検査を導く。
公開の入口に、子の成功や結果の一致を仮定しない。

共通の五つの原稿の十一の引数出現を、モデルと実際の Haskell の AST、通常の `golem fmt` の前後で照合する。
同じ `0.10` を語と引用値にした例では、値の文字が同じでも種類は区別する。
二度目の整形でバイト列が変わらないことも確かめる。
Haskell の版とパッケージの選択は、引用値の検査と同じ `ast-probe.mjs` で行う。
上の CLI のビルドの後に、次を実行する。

```sh
node --test experiments/parser-fmt-proof/arguments/mixed-values.native-test.mjs
```

このモデルは引数の宣言や評価時の検査、Golem の入力全体の検査を扱わず、式、展開、位置引数やコメントを自由に混ぜた引数全体の一般証明でもない。
公理、前提と残る範囲は [依存関係の記録](../../../docs/research/0351-mixed-keyword-proof-dependencies.md) にある。
[root ADR 0351](../../../docs/adr/0351-prove-parser-formatter-round-trips.md) の未実装の状態を保つ。

## キーワードの CST から AST へ移す段階

`KeywordLowering.lean` は、構築したキーワードの CST から、名前、Word または StringLit の種類と復号値を得る性質を示す。
既存の Word と引用値の前後へ、KWhitespace、KComment と KNewline のトークンを任意個置ける。
そのようなキーワードを任意個並べ、引数に当たらない外側の要素を差しても、値のある出現だけが元の順で残る。
KProofComment は通常のコメントと同じ trivia にしない。

モデルは `Golem.Parser.Lower` の有意な子の選択、キーワードと値の写像、引用値の復号へ対応付ける。
共通の五つの構築した CST の十二の保持される引数を、モデルと実際の公開関数 `Lower.lower` で照合する。
Word と StringLit の種類、空の引用値、エスケープ、Unicode、同名の繰り返しと、除かれる要素も含む。
上の CLI のビルドの後、同じ Cabal plan で次を実行する。

```sh
node --test experiments/parser-fmt-proof/arguments/lowered-cst.native-test.mjs
```

内部へ自由に trivia を差したこの CST のすべてが、実 PEG の像だとは証明しない。
同じ文字列を正しい Golem 原稿として扱う検査とは区別する。
AST に trivia を移さない性質は、fmt が CST のコメントを消してよいという意味ではない。
公理、前提と残る範囲は [依存関係の記録](../../../docs/research/0351-cst-keyword-lowering-proof-dependencies.md) にある。
[root ADR 0351](../../../docs/adr/0351-prove-parser-formatter-round-trips.md) の未実装の状態を保つ。

## 認識区間から CST トークンへ移す段階

`CstWrapperMetadata.lean` は、実際の生成文法の token と inline の属性を検査する。
`CstWrapper.lean` は、CST を出力する場合の inline、token、通常の node の順をモデルにする。
Word、StringLit と Eq が任意の接尾辞の前で読む区間から、原綴りのトークンと残りを得ることを示す。
引用符とエスケープはここで除かない。

共通の八つの原稿の二十四のトークンを、モデルと実際の Haskell の CST の構成子から取り出して照合する。
文法の属性を四通り変えると、生成し直した metadata の証明が失敗し、実パーサーが返す CST の形も変わることを確かめる。
上の CLI のビルドの後、同じ Cabal plan で次を実行する。

```sh
node --test experiments/parser-fmt-proof/arguments/raw-cst.native-test.mjs
```

文字単位のモデルと UTF-8 の byte offset の一般的な対応、通常の node の隙間に補う Text token、原稿全体の CST の生成は未証明である。
公理、前提と残る範囲は [依存関係の記録](../../../docs/research/0351-cst-wrapper-proof-dependencies.md) にある。
[root ADR 0351](../../../docs/adr/0351-prove-parser-formatter-round-trips.md) の未実装の状態を保つ。

## CST の種類を変換してキーワードの値へ接続する段階

TokenLowering.lean は、認識と CST wrapper が返す Word と StringLit から、種類を保った Lean のモデルの値を得ることを示す。
実際の Golem.Parser.AST との一致は下の九例で照合し、一般的な対応は未証明である。
Word は原綴りを保ち、StringLit は引用符とエスケープを除く。
等号を認識しても値にはしない。
子の認識の成功や結果の一致を仮定せず、既存の認識と復号の一般定理から導く。

構築したキーワードの node から名前、種類と値が戻ること、任意個並べても同名の繰り返しと順を保つことも示す。
この部分は、原稿を解析してすべての node を生成する一般証明とは区別する。
モデルの arguments はキーワードだけの射影であり、位置引数や展開を混ぜた入力の lowering 全体ではない。

九つの共通の原稿の十六の引数出現を、実際の parseAst と通常の golem fmt の前後で照合する。
八つの個別の値に加え、それらすべてを同じ原稿に並べた例を含む。
二回目の整形でバイト列が変わらないことも確かめる。
上の CLI のビルドの後、同じ Cabal plan で次を実行する。

```sh
node --test experiments/parser-fmt-proof/arguments/token-values.native-test.mjs
```

公理、前提と残る範囲は [依存関係の記録](../../../docs/research/0351-token-ast-proof-dependencies.md) にある。
[root ADR 0351](../../../docs/adr/0351-prove-parser-formatter-round-trips.md) の未実装の状態を保つ。

## 生成規則から子の CST を作る段階

KeywordTrace.lean は、実際の生成文法の KeywordArgument と ArgValue の選択肢を読み、参照を順に実行して子の CST を作る。
子の列を引数で与えず、Word、Eq と StringLit の token と KeywordArgument の node を構築する。
任意の語と引用値について、残りの入力、モデルの名前、値と種類が一致することを示す。
Word は先頭が %% でないことと区切りの条件を使い、引用値は任意長の Part の列を使う。

モデルの展開はこの二段階に限る。
認識に成功した未対応の非 token を空の子として扱わず、未対応のエラーを返す。
実際の parser が受理する式の対照も置き、モデルの未対応と parser の拒否を区別する。
文字の位置、GreenNode の間隙と UTF-8 の対応、文法全体の再帰や Haskell の AST への一般的な対応は未証明である。

引用符なしの値に %% があるかを調べる G01102 の射影もモデルに含める。
名前の内部と引用値の %% は、この射影の対象にしない。
コードだけの射影であり、commentDiagnostics 全体や位置の一般証明とは数えない。
十二例を実際の CST、parseAst と通常の整形の前後で照合する。
別の三例で、G01102 のコード、重大度、UTF-8 の byte span と fix、および失敗した整形が元の原稿を書き換えないことを照合する。

上の CLI と Cabal plan を選択した後、次を実行する。

```sh
node --test experiments/parser-fmt-proof/arguments/trace-values.native-test.mjs \
  experiments/parser-fmt-proof/arguments/trace-diagnostics.native-test.mjs
```

公理、前提と残る範囲は [依存関係の記録](../../../docs/research/0351-keyword-capture-proof-dependencies.md) にある。
[root ADR 0351](../../../docs/adr/0351-prove-parser-formatter-round-trips.md) の未実装の状態を保つ。

## KwArg の通常のキーワード経路をつなぐ段階

KwArgTrace.lean は、実際の KwArg が先頭の KeywordArgument の経路で成功する場合を扱う。
任意の語と引用値のキーワードについて、子の capture、同じ fuel の生成規則の認識、モデルの名前、種類と値を接続する。
KwArg 自体は inline なので、外側に KwArg の node を追加しない。
主定理では、子の成功や結果の一致を未証明の前提にしない。

KwArgMetadata.lean は、引数がないこと、先頭の参照と inline の指定を検査する。
残りの選択肢は生成文法から取り出し、別の固定した規則で代用しない。
SplatArgument の経路では capture モデルが明示的な未対応となり、実際の parser が受理する対照を置く。
この対照を、parser の拒否する反例には数えない。

十二例を共通のデータからモデルに渡し、実際の CST、parseAst と通常の整形の照合にも同じデータを使う。
三つのモデル変異は定理と実行時の回帰の両方が拒否することを確かめる。
二つの source の変異と、行番号だけを変える AST の対照は、fresh な Generated と metadata の証明で確かめる。
上の CLI と Cabal plan の選択の後、共通の実装の観測器は次で実行する。

```sh
node --test experiments/parser-fmt-proof/arguments/trace-values.native-test.mjs
```

公理、前提、再現手順と残る範囲は [依存関係の記録](../../../docs/research/0351-kwarg-capture-proof-dependencies.md) にある。
[root ADR 0351](../../../docs/adr/0351-prove-parser-formatter-round-trips.md) の未実装の状態を保つ。

## 通常引数の語と引用値をつなぐ段階

`ArgumentTrace.lean` は、実際の `Argument` から `ArgValue` を読み、語と引用文字列の token を持つ node を返す。
任意の語と引用値について、同じ fuel の生成規則の認識、子の capture と、モデルの `positional` の種類と値を接続する。
子の成功や結果の一致を未証明の前提にしない。

`ArgumentMetadata.lean` は、実際の参照先、全選択肢と node の分類を検査する。
三つのモデル変異を定理と実行時の回帰が拒否し、二つの文法変異を fresh な生成 AST と native parser で照合する。
式の値は native parser が受理するが、今回の capture モデルは明示的な未対応を返す。

同じ十二例をモデルと実装に渡し、CST、位置を除く AST、通常の整形後の AST と二度目のバイト列を比較する。
上記の CLI と Cabal plan を指定した後、実装との照合は次で実行する。

```sh
node --test experiments/parser-fmt-proof/arguments/positional-values.native-test.mjs
```

`PosArg` の先読み、引数列全体、CST の位置、Haskell の AST と整形の一般的な対応は残る。
公理と定理、実装との有限の照合、再現手順は [通常引数の capture の記録](../../../docs/research/0351-positional-capture-proof-dependencies.md) にある。
[root ADR 0351](../../../docs/adr/0351-prove-parser-formatter-round-trips.md) の未実装の状態を保つ。

## ローカルでの全実行と CI の境界

新しい native observer は `arguments/*.native-test.mjs` の八ファイルである。
語と引用値、混合値、CST の token と node、AST への変換、keyword の capture と diagnostic、通常引数の capture を観測する。
上記の GHC、Cabal plan、PEG_HS、Lean と GOLEM を指定し、次で証明と正負の例、変異、全 native observer、既存の引数テストをまとめて実行する。
失敗しても後続を検査し、最後に失敗を返す。

```sh
sh experiments/parser-fmt-proof/check-local.sh
```

`native-runner.mjs` は八ファイルの一覧とディレクトリを照合し、一つでも欠けた場合や、新しい observer が一覧にない場合は失敗する。
この検査自体にも、各ファイルの欠落と一覧への追加を試す回帰がある。
既存の CI は構成と `*.test.mjs` の検査を保ち、新しい native observer はこのローカルの経路で検証する。
CI の所要時間と成否を、新しい native observer の通過の証拠にはしない。

## 位置引数の先読みと引用値の捕捉

`PosArgTrace` は参照と否定先読みを扱い、入力を消費しない先読みから捕捉を作らない。
`PosArgQuoted` は任意の引用値と接尾辞について、実際の先読みの結果を導いて既存の ArgumentTrace へ渡す。
捕捉した Argument node、モデルの復号した Positional と、同じ fuel の生成規則の認識とを接続する。
子の成功や結果の一致を、未証明の前提として置かない。

共有する十二例と前段の native observer を照合し、三つのモデル変異と三つの文法変異を検査する。
先読みを消す変異は引用値の定理を通るが、対象外の接頭辞の回帰が拒否する。
PosArg の語と展開の一般的な捕捉、引数列全体と、Haskell の AST、整形と評価の一般的な対応は残る。
実行には上のローカルの全実行を使い、CI の計測とローカルの成否を分ける。
公理、生成された実行用の宣言、依存図と残件は [位置引数の先読みの記録](../../../docs/research/0351-posarg-quoted-proof-dependencies.md) にある。

[PosArgWord.lean](PosArgWord.lean) は、空白一文字で区切った語について、PosArg の捕捉、抽象 AST と認識結果の一致を示す。
空でなく各文字が許され、先頭が `%%` でない語と任意の後続入力を対象にし、実文法の先読み結果をこの語彙条件から導く。
`=` や `[` を語の直後へ置く場合、スプラットや引数列全体への一般化は含めない。
共有 12 例をモデルで確認し、明示的なローカル観測器では本体の AST と通常の整形が成功する 11 例と、内部の `%%` により G01102 と整形の拒否を保つ一例を区別する。
公理、論理依存と未完の範囲は [空白で区切った語の位置引数](../../../docs/research/0351-posarg-word-proof-dependencies.md) に記す。
全ローカル実行は `sh experiments/parser-fmt-proof/check-local.sh` で、追加した本体観測を既存 CI の保証へ含めない。
