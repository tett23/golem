# ADR 0319: 長さを取る欄で単位のないゼロを受け付ける

ステータス: 採択（未実装）

## 文脈

本の余白をなくすには、長さの欄に `"0pt"` などの単位付きの値を書く。
長さとしてはどの単位でもゼロだが、整数の `0` と文字列の `"0"` は、ともに現在の読み込みでエラーになる。
また、アキ量の規則は `"0pt"` も拒む。
アキ量のゼロに相当する値は `"ベタ"` である。

## 実装すること

長さを読む各入口で、TOML の整数のゼロと、単位なしの文字列 `0` または `-0` を受け付ける。
TOML の整数はパーサーが返す数値で判定するので、TOML が整数のゼロとして読む符号付き表記も含む。
TOML の浮動小数点は既存の型の検査に渡す。
原稿の引数では前述の文字列二つを認める。

長さのゼロは絶対長のゼロ、アキ量のゼロはベタとして保持する。
HTML と EPUB の CSS にこの値を長さとして書く場合は `0` と出力する。
既存の単位付きの長さも内部の値がゼロなら CSS に `0` と書く。
従来の原稿から生成する CSS の字面が変わりうるので、参照出力の差を検査する。

次の欄を実装時の入口の一覧とする。
長さの値を読んだ後は、それぞれの欄の正数条件、利用できるキー、組版の条件を今と同じ順で検査する。

| 入口 | 対象 |
| --- | --- |
| `style.toml` のページ | `[page] bleed`、`[page.grid] column-gap` と `position` の絶対長 |
| 段落、文字スタイル | `indent`、`first-line-indent`、両方の `code` の `padding`、`baseline-shift` |
| 組版と罫線 | `[composition.ruby] overhang`、段落の `rule-before` の `space-before`、`space-after`、`start-indent`、`[notes.rule]` の前後の間隔 |
| 一覧、索引、アキ | `[lists] gap`、`[index] column-gap`、アキ量のセットの規則の量 |
| 原稿 | `@style-def` の寸法、`[aki 0]`、図版の `width` |
| preflight | 単位付きの絶対長を読む欄 |

`@blank-line` は空ける行の数を取る。
ゼロは加算の単位元とし、評価時にブロックを追加しない。
ゼロの指令を除いた場合と行アキ、前後の属性、連続した指令の notice が一致する。
引数なしは一行のままである。

## 実装しないこと

`[notes.rule]` では `start-indent` がキーとして許されていないので、値に単位を付けても G03006 のままとする。

## 不変条件

1. ゼロを許す長さの欄で、単位のないゼロを既存の同じ型のゼロに置き換えても、寸法と diagnostics は一致する。
2. 値の型と欄の制約は表のとおりとし、長さのゼロを読む変更によって負の行数と正でない図版の幅は従来どおりエラーになる。

| 入力 | 結果 |
| --- | --- |
| 空文字、文字列の `1`、文字列の `0.0` | 既存のエラー |
| TOML の整数の `0`、文字列の `0` と `-0` | 長さは絶対長のゼロ、アキ量はベタ |
| 文字列の `+0` や `00` | 既存のエラー |
| 図版の `width=0` | 正の幅を要求する G02133 |
| `@blank-line 0`、`@blank-line 1` | 空きなし、空行一つ |
| HTML または EPUB に出力する長さのゼロ | CSS の `0` |

## テスト設計

[改訂後の評価器の試験](../../experiments/syntax/review/Sources.hs) は、三つの提案を合わせて変更前に 16 件中 6 件、変更後に [16 件すべて](../../experiments/syntax/review/actual-green.log) が通った。
初回の試作と改訂後の結果は [実験の記録](../../experiments/syntax/review/README.md) に分けて記した。

[試作](../../experiments/syntax/proposal.mjs) は入力の型を保ったまま整数と文字列のゼロを正規化する。
`node --test experiments/syntax/test.mjs` の 319 I1 と I2 が型と CSS の境界を検査する。
`node experiments/syntax/cli.mjs /path/to/golem` は実際のプロジェクトを作り、整数、文字列、正規化後の入力を順にコミット `0a8d21a0` の CLI に渡す。
[照合結果](../../experiments/syntax/cli.log) には、style.toml の 18 通りの欄、原稿の 4 通りと preflight の結果がある。
preflight が `"0pt"` に G09001 を出さなくなった後、検査本体は別の G09014 で終了した。

Haskell の `parseDim` と TOML の長さのデコーダーにも同じ変更を入れた。
`sh experiments/syntax/dimensions.sh` は変更前に 12 件中 7 件が失敗し、[変更後の 12 件](../../experiments/syntax/dimensions-green.log) はすべて成功した。

採択後は各入口に直接入力を渡し、正規化前の位置を保つことも検査する。
HTML と EPUB は CSS 生成後の値まで調べる。
試作で調べた CSS は正規化関数の戻り値であり、生成物全体の差は未確認である。

## トレードオフ

型を問わず数値に変換してからゼロか調べると、文字列の空欄や浮動小数点まで受け付ける実装になりうる。
整数と文字列の入口で別々に判定すると、既存の型エラーが残る。
ゼロ行の指令を書ければ、生成側は空きがゼロの場合を特別扱いせずに済む。
[加算の試験](../../experiments/syntax/review/review.test.mjs) は 0 + 0、0 + 3、3 + 0、2 + 3 を含む。

## 参考文献

- [長さの読み込み](https://github.com/tett23/golem/blob/2b7d1dffe359e065bf5e899a2df6cab85704905d/modules/golem-project/src/Golem/Project/Style.hs#L166-L194)
- [図版の幅の仕様](0190-non-wrapping-figure-width.md)
