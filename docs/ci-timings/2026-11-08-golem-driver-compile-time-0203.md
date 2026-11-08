# golem-driver のライブラリのコンパイルの時間（2026-11-08、[ADR 0203](../adr/0203-generated-modules-instead-of-template-haskell-in-golem-driver.md)）

[ADR 0203](../adr/0203-generated-modules-instead-of-template-haskell-in-golem-driver.md) は、golem-driver の Template Haskell を生成したモジュールに替えたときのコンパイルの時間を、実装のときに測ると決めた。
その測定は、実装のプルリクエスト [#635](https://github.com/tett23/golem/pull/635) の説明にだけ書かれていた。
この記録は、その説明の数を写したものである。
2026-11-08 に作り、コミットした後は変更しない。

## 条件

- 測ったのは #635 の実装者で、手元の macOS（arm64）、GHC 9.10.3、`-O1` で測った。
- 一回ごとに `dist-newstyle/build/.../golem-driver-0.1.0` を消し、`cabal build golem-driver:lib:golem-driver` を実行した。
- 前は Template Haskell で埋め込む `b7acd268`、後は生成したモジュールで埋め込む #635 の版である。#635 は `c53026fd` でマージした。
- 前と後を二回ずつ測った。

## 結果

| | real（秒） | user（秒） |
| --- | --- | --- |
| 前（Template Haskell、`b7acd268`） | 18.26、19.39 | 16.75、17.31 |
| 後（生成したモジュール） | 31.98、34.89 | 31.04、31.94 |

ライブラリのコンパイルは約 14 秒延び、約 75% 増えた。
延びた時間は、`Golem.Driver.Explain.Embedded` の 9,916 個の `Text` のリテラルのリストに掛かる。
生成したモジュールは 573,127 バイトである。

生成したモジュールに `{-# OPTIONS_GHC -O0 #-}` を付けると、63.8 秒に延びた。
`text` のリテラルの書き換えの規則が働かなくなるためと見られる。
そのため、生成したモジュールは ADR のとおりの形のままとした。

wasm の GHC での `Golem.Driver.Explain.Embedded` と golem-driver のライブラリのコンパイルの時間は、[CI のジョブ wasm の記録](2026-11-08-wasm-job.md)にある。
