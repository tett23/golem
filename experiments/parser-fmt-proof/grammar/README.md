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
文法に書かれた Haskell の式（アクション）が作る AST の値や、ラベルエラー後の復旧結果は、この結果に含まれない。
`ReservedRange` の証明により、未証明の選択肢は 27 個から 24 個に減るが、復旧後の AST や `golem fmt` の往復を証明したことにはならない。

未証明の選択肢は `deferred-choices.txt` に列挙する。
`check-deferred.mjs` は実際の未証明の一覧との差分で失敗し、一覧に無い追加と、証明できたのに残った行の両方を検出する。
ブロックの入れ子やコマンドの返す値、予約された括弧の本体を含む選択肢と、AST、整形、評価の一般的な往復の照合は残っている。
全範囲が終わるまで [root ADR 0351](../../../docs/adr/0351-prove-parser-formatter-round-trips.md) の未実装のステータスを保つ。
