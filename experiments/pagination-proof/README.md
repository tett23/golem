# [root ADR 0352](../../docs/adr/0352-prove-pagination-in-lean.md) の Lean 証明

このディレクトリは、[root ADR 0352](../../docs/adr/0352-prove-pagination-in-lean.md) の改ページ証明を作る場所である。
`check.sh` は Alloy の 42 コマンドと期待値の一覧が一致することを確かめ、各コマンドに対応する `theorem` を要求する。
対応する定理の名前は、[root ADR 0352](../../docs/adr/0352-prove-pagination-in-lean.md) のテスト設計に従って不変条件の番号を頭に付け、`I3_someFits` のように書く。
`check.sh` は、名前から `I` と番号と `_` の接頭辞を除いた残りがコマンド名と一致する定理を対応とみなす。
`tallFigure` は縮小前の図版の反例を示すので不変条件 2 の `I2_tallFigure` とし、ほかの 41 件は一段の配置の規則を扱うので不変条件 3 の `I3_` を付ける。
接頭辞のない定理や、同名の計算用関数だけではこの検査に通らない。
42 コマンドすべてについて、Alloy のモデルを Lean へ書き写した述語（「元の述語の書き写し」の節）の上で述べた、名前空間 `Alloy` の中の対応する定理も要求する。
改ページの規則のモデルは、Alloy のモデルを書き写した Lean の定義であり、Alloy のモデルではない（2026-11-23 のメンテナーの決定）。
移行はまだ完了していない。
未完の項目は「未完の項目」の節に挙げる。

この文書では、Alloy のモデルの項目を次の語で呼ぶ。
`Text` は本文、`Figure` は図版、`Space` はスペース、`Blank` は行アキ、`Need` は `need-lines` である。
P1 は Alloy の `needMet` で、`need-lines` の次のブロックを段の先頭でない位置に置くなら、段の容量からそのブロックより前に置いた行（スペースと行アキを除く）を引いた残りが、要求の行数以上であることを求める。
P7 は Alloy の `spaceKeeps` で、`need-lines` が記述位置で満たされ、次のブロックの最初の部分がスペースの後に収まるなら、そのブロックを段に置くことを求める。

名前空間の外の宣言は、それぞれ独自の抽象化の上で述べた命題である。
`blankFigureOrder` は、本文を置かない境界の配置を構成し、図版が 0〜2 枚で行アキが 0〜1 個の入力について、図版規則、行アキ規則、段容量を同時に満たすことを証明する。
`blankRules25` は、空段の先頭内容を本文、図版、内容なしに分け、旧行アキ規則と段容量、本文と図版の順序、空段から先頭内容を送らない規則を同時に満たす配置を証明する。
`figureEmpty` と `figureOrder` は行アキのない入力をこの証明から導く。
`keep21` はこの配置に、段落境界の orphan、widow、見出しの規則を接続する。
`keepHeadingEmpty`、`keepHeadingFigure`、`keepHeadingOrphan`、`keepHeadingWidow`、`orphanEmpty`、`widowEmpty`、`orphanWidow`、`noneMeetsAllButGreedy` は、この同じ配置から対象の規則を取り出す。
`waitingBlankNone` と `waitingBlankAllButGreedy` は、待機中の図版を飛ばす現在の行アキ規則について同様の配置を構成する。
段容量と図版寸法に有限の上限はない。
これらの宣言は補助の命題であり、モデルとしては扱わない。

`greedyFigure` は、本文を詰める規則と図版を収まる位置に置く規則が両立することを示す。
図版が原稿位置で収まる場合はその行数を確保し、残りの行に本文を詰める。
図版がその位置で収まらない場合は本文だけを詰める。
元の Alloy コマンドをスコープ 5、配置 14 で検査しても反例は 0 件だった。

`needFigure` では、容量 5 行の段を 4 行使い、2 行を求める `need-lines` の直後に高さ 1 行の図版を置く。
旧図版規則と図版順を満たす配置は図版を置き、P1 を満たす配置は図版を送る。
どちらも段容量を満たすが、同じ配置では両規則を満たせない。
同じ原稿の全 2 配置を元の Alloy 述語で調べてもこの衝突を再現した。
Haskell の `paginate 1 5` に本文 4 行と高さ 1 行の図版を渡すと、本文と図版を同じページに置いた。
本文と図版の間に `FNeedLines` で 2 行を求めると、本文 4 行は 1 ページ目に残り、図版だけが 2 ページ目に移った。

`decidedSome` は、容量 3 行の空段に改丁見出し 1 行と 1 行段落を続け、両方を置く配置を証人とする。
手元の Alloy CLI で同じ容量、使用済み行数 0、本文の位置 0、1、区切り位置 2 を固定して実行し、解を確認した。
`keepAllSome` は、容量 3 行、使用済み 1 行、本文 1 行の配置を証人とする。
同じ入力を Alloy CLI で固定して解を確認した。

`relaxedAfterHeadings` の代表入力では、空段の先頭に見出し 1 行と 3 行段落を続ける。
Lean は任意の段落行数と容量 2 行以上について、見出しと最初の本文行を置く区切りが緩めた孤立行、寡婦行規則と見出し後の 1 行規則を満たすことを示す。
Alloy でも容量 3 行、段落 3 行、区切り 2 を固定して解を確認した。

Alloy の容量下限 3 行を外し、容量 1 行の空段に見出し 1 行と本文 1 行を続けると、段頭の見出しを置く規則、収まり、見出し後の本文 1 行を同時に満たす区切りはない。
Lean はこの 2 項目入力の区切り 0〜2 をすべて排除する。
Golem は見出しだけを最初の段に置き、本文を次の段に置いた。
したがって、この出力は Alloy の見出し後 1 行規則を満たさない。
容量 2 行以上では両方を置く区切りがある。

同じ入力を Golem に渡すと、最初の段には見出しと本文 2 行が置かれ、残る本文 1 行は次の段に置かれる。
Alloy の区切り 2 も実装の区切り 3 も緩めた規則を満たす。
モデルは配置の存在を調べるもので、規則を満たす配置が複数ある場合の選択順はこの証明では扱っていない。

見出しと最初の本文行の間または後ろに図版が一つある場合も、任意の容量 2 行以上で、図版の寸法に応じて本文 1 行と図版のどちらを置くかを算術モデルで証明した。
容量 3 行で見出しの後に高さ 2 行の図版が収まる入力と、高さ 3 行の図版が待機する入力は、Alloy の固定入力と Golem の回帰テストの双方で配置を確認した。
任意の原稿列における図版の位置と算術モデルの対応は未証明である。

区切り 2 で本文 2 行を置く場合も、図版と行アキが第 2 本文より後ろにある一図版または二図版と一行アキの入力について、同じ配置が図版規則、行アキ規則、容量、緩めた孤立行、寡婦行規則を同時に満たすことを証明した。
見出し、二行段落、行アキ、一図版の順の固定入力では、段落行を Alloy の原稿条件どおり連続させ、区切り 2 で図版と行アキが待機する解を確認した。
Golem は同じ入力で二行段落を最初のページに置き、図版を次のページへ送った。
二図版に増やした実装の回帰テストでも順序と既存の配置不変条件が保たれた。
どちらも各規則を満たすが、選んだ区切りは異なる。
この二図版と行アキを含む入力は、図版を高々一つに限り行アキを除く `relaxedAfterHeadings` の範囲を超える。

図版がなく、見出し列の後に段落が続く形では、容量 2 行以上の任意の段、見出し 1 行以上、本文 1 行以上に対し、最初の見出しの後か最初の本文行の後で区切れることを示した。
見出し 2 行と本文 1 行、区切り 1 の入力は Alloy でも確認した。
見出し列の長さと段落構造を原稿列から取り出す一般的な対応は未証明である。

さらに、任意長の見出し、本文行の列から最初の区切りを選ぶと、容量 2 行以上で収まり、先頭内容を置き、見出し後の本文 1 行規則を満たすことを証明した。
この区切りで置かれる見出しは必ず最初の行にあり、置かれる本文行より前には見出ししかない。
したがって、この本文行が段落の最初の行であれば、緩めた孤立行、寡婦行規則の前提に必要な位置関係が成り立つ。

Alloy の `tpos[t]` は位置が小さい `Text` の件数、`here[p,t]` はその件数と区切りの比較である。
Lean では、図版、行アキ、`need-lines` を含む任意の位置順の原稿列から `Text` の位置を抜き出し、各 `Text` より前の `Text` の件数がその順位に等しいことを証明した。
各 `Text` の役割も、その順位から取り出せる。
見出し、本文行、`Space` の三役割の列については、最初の区切りが `Text` の件数だけの収まり、先頭の `Text` を送らない規則、Alloy の `lineAfterHeadings` を満たし、原稿列の `here` 判定と役割の順位が一致する。
配置済みの本文行より前の `Text` が見出しだけであることも、原稿列上の位置関係として証明した。
見出しと本文行だけの列については、さらに配置済みの見出しが段頭にある。
図版、行アキ、`need-lines` 自体の配置、Alloy の `para` 関係、実装の分類と計測値への対応はこれらの定理には含まれない。

改丁見出しを本文の位置列として与えた場合は、本文を置かない区切りと、空段の最初の本文だけを置く区切りで、置いた改丁見出しが段頭になることを証明した。
これは図版と行アキの現在の規則が構成する配置にも接続した。

`relaxedAfterHeadings`、`rectoKept`、`rectoEnds` では、容量 2 行以上の段について、元の各規則を同時に満たす配置を構成した。
Alloy の入力に合わせ、本文を見出しと段落の行とし、図版は高々一つとする。
図版の前にある本文の件数を図版の位置とし、段落の各行の位置も本文の順位で表す。
段の使用済み行数が正なら、本文を置かず、先行する本文がない図版だけを収まりに応じて置く。
空段の先頭が図版ならその図版を置く。
先頭が本文なら本文を 1 行置く。
ただし、その 1 行が見出しで、次の本文が段落の行であり、区切り 1 で図版を置かない場合は、本文を 2 行置く。
この構成で置く見出しはすべて段頭にあるため、改丁見出しを見出し列に含める規則と改丁見出しの前で列を切る規則の両方を満たす。
元の 3 コマンドを Alloy CLI の SAT4J で実行したところ、いずれも指定した範囲（スコープ 5、整数 5 ビット、配置 14）で反例は 0 件だった。

```sh
for command in relaxedAfterHeadings rectoKept rectoEnds; do
  alloy6 exec -q -n -t text -c "$command" -o - docs/golem-layout/models/pagination.als || exit 1
done
```

旧 `keepHeading21` と改丁見出しで見出し列を切る `keepHeadingR` の差は、通常見出し 2 行と改丁見出し 1 行を続け、区切り 2 を選ぶ固定入力で示した。
この配置は `keepHeadingR` と改丁規則を満たすが、旧 `keepHeading21` を満たさない。
Alloy でも同じ述語差を確認した。
Golem に同じ原稿を渡す回帰テストは、通常見出し 2 行を最初のページに置き、空白の 2 ページ目の後で改丁見出しを 3 ページ目に置く結果で通過した。

`keepDefaultDiffers` は、段落の分割前後の行数に関する orphan、widow 規則と、先頭、最後の位置による境界規則が一致することを示す。
さらに、Lean の段落行位置列を配置済み行と次段の行に分けると、両者の行数の和が元の行数と一致し、分割の存在と両方の行数が正であることも同値である。
原稿順の行から段落に属する行を選んでも順序を保つことを `I3_paragraph_projection_sorted` が示す。
`I3_alloy_paragraph_endpoints` は、この列の各行について、Alloy の `first`、`second`、`beforeLast`、`last` が数える前後の行数を列における順位に対応付ける。

`keepNone` は、段落の最初の行を含む任意の行位置列と任意の keep 指定について、旧図版規則の配置と keep 指定を同時に満たす証人を構成する。
Lean では、本文を置かない場合に分割を生じさせず、空段に最初の本文行を置く場合に分割された段落が段頭で始まることを証明する。
段落に属する行の選択と順位の対応は上の二つの定理で検査する。

`needSpaceAllButGreedy` は、容量 4 行の段を 2 行使ったところに `@need-lines 2` と見出し 3 個が続き、後ろの 2 個が改丁見出しである入力で、規則が両立しないことを示す。
P7 は最初の見出しをこの段に求める。
段はすでに使っているため、旧 `keepHeading21` は続く改丁見出しも同じ段に求める。
残り 2 行に見出し 3 個は収まらない。
Lean で本文の区切り 4 通りのすべてについてこの衝突を証明し、元の Alloy 述語に同じ原稿と 4 配置を固定して反例を確認した。
固定を外した元のコマンドでも、SAT4J は容量 4 行、使用済み 2 行、見出し 3 個の反例を返した。
Golem は改丁見出しの手前で見出し列を切り、三つの見出しを 1、3、5 ページ目に置いた。

`needMore27` は、容量 3 行、使用済み 1 行、`need-lines` 1 行、スペース 1 行、`need-lines` 3 行、段落 1 行の入力で旧 P7 と P1 を同時に満たす配置がないことを示す。
Alloy でも同じ入力と配置 3 通りを固定して解を確認した。

`needMoreSome` は、容量 4 行で同じ配置の新 P7 が両方の `need-lines` を満たす証人を示す。
`needSpaceSome` は、容量 3 行、使用済み 1 行、`need-lines` 2 行、スペース 1 行、段落 1 行の証人を示す。
両方の入力は Alloy でも固定して解を確認した。

さらに、`need-lines`、スペース、`need-lines`、本文 1 行という形では、任意の段容量と使用済み行数について、二つの `need-lines` の大きい値を判定すれば P1 と P7 を同時に満たす区切りがあることを証明した。
区切り 0、1、2 でスペースと本文が置かれる位置は Lean の原稿列から計算して照合した。
後続ブロックの先頭部分を任意の正の行数に広げ、空段では先頭のスペースを送らない規則も加えた場合に、同じ形の区切りが存在することを証明した。

図版を除いた場合には、任意長の本文、スペース列と任意の位置にある行アキ一つに対して配置を構成した。
各本文にかかる `need-lines` は原稿順にまとめ、容量と P1 を満たす最長の本文の接頭部を選ぶ。
その次がスペースなら、収まる限りそのスペースを含む接頭部がさらに長いはずである。
次が本文で必要な高さと最初の部分が収まる場合も同じ理由で、その本文を接頭部に含む。
このため同じ区切りが P7 を満たす。
行アキは次の本文を置いた場合に限って加え、段頭では捨てる。
次の部分が収まるかを調べるときには、そこまでの行アキを段頭のものを除いて数える。
`need-lines` と次の本文との間のスペースが区切りをまたいでも、先に置いた本文の行数を数える `placedBefore` の値は変わらない。

図版を判定する段階では、その図版と先行する図版を原稿順に調べれば、`figures27` の `need-lines` 判定と図版の順序を同時に満たす図版の集合を構成できる。
先にある図版をすべて置いた場合は、判定中の図版より前に待機中の図版はない。
このとき `needNext` の対象は、図版の配置を決める前に定まり、`placedBefore` が数える図版の高さは先行する全図版の高さの和に等しい。
本文の区切りを固定し、行アキより前に置いた本文があるかを与えると、段頭の行アキ判定と配置する図版の集合も同時に決まる。
行アキを段頭と仮定して先行図版を調べても、その先行図版の配置は行アキを置くかどうかに依存しない。
名前空間の外の `needSpaceNone` と `needMoreNone` では、段容量と P1 を満たし、もう 1 行延ばせない本文の区切りを選ぶ。
この区切りで P7 の条件を満たす本文や図版を段の外に置くと、さらに 1 行延ばせるか、その図版を図版規則が段の中に置くことになり、矛盾する。
図版 0〜2 枚と行アキ 0〜1 個の各入力について、同じ配置が段容量、段頭の規則、図版の順序、P1、P7 を同時に満たす。
`needSpaceNone` は 2 行を要求する `need-lines` が 0 個か 1 個のときに適用する。
`needMoreNone` は原稿順に並ぶ 2 個のうち、同じ対象への先行要求より大きいものだけを記述位置で再判定する。
元の `needMoreNone` を夜間検査と同じスコープ 4、整数 5 ビット、配置 24、図版 2、行アキ 1 で SAT4J に渡すと、反例は 0 件だった。

待機中の図版の後にある本文に `need-lines` がかかる入力も、Lean、Alloy、Golem で照合した。
容量 4 行の空段に本文 2 行、高さ 3 行の図版、`@need-lines 2`、高さ 1 行の図版、本文 1 行を並べる。
最初の図版は収まらず、続く図版は待機するため、`needNext` の対象は最後の本文行となる。
Lean はこの対象と必要な残り 2 行を確認した。
Alloy は本文 3 行を置く区切りで `base27`、`needMet`、`spaceKeeps` を同時に満たす配置を返した。
Golem の回帰テストでは最初の段に本文 3 行を置き、次の段に 2 枚の図版を原稿順に置いた。

実装との照合には、二つの入力を [PaginateSpec](../../modules/golem-layout/test/PaginateSpec.hs) に追加した。
先頭の 1 行段落で使用済み 1 行を作り、後続の `need-lines`、スペース、段落の配置を検査する。
手元の実装では二つの回帰テストがそれぞれ 1 件ずつ通過した。

図版寸法の証明では、`tallFigure` の旧規則が段より高い図版と衝突することを任意の自然数の高さについて示す。
縮小後はこの衝突が解消する。
キャプション付き図版については、入力の行数から占有できる高さの上限を証明する。
キャプションのない図版についても、本文の文字サイズが行送り以下であるという版面の条件から、画像の高さを行送りで切り上げた行数が段に収まることを示す。

キャプションの改行候補から終端を選ぶとき、Haskell はデメリットの最小値を求め、その値を持つ終端だけを最終行の fitness と先行する改行履歴で比較する。
`I1_caption_two_stage` は、候補を順に比較する Lean の選択が、同じ最小値と履歴を使うこの二段階の選択に一致することを示す。
`I1_caption_discard_prefix` は、各改行後に次のボックスか強制改行まで読み飛ばす項目が一致することを示す。
`I1_caption_assemble_span` は、選んだ改行履歴から行の開始位置、終了位置を組み立てたとき、得られた行数で計算するキャプションの占有行数が改行履歴の長さからの計算と一致することを示す。
`I1_caption_assembled_natural` は、行の前後で幅の累積値を引く実装の式が、行内のボックスとグルーの幅に、改行位置のペナルティの幅と行端の補正を加えた値に等しいことを示す。
`I1_caption_checked_payload_exact` は、原稿項目の全データを残したまま、絶対位置の改行列から `[start, break)` の範囲を切り出し、改行後の空きと任意のペナルティを読み飛ばす処理について、各ボックスが原稿順に一度ずつ残ることを示す。
`captionAssembleAt` は実際の項目列と位置から、改行位置がボックスでないこと、範囲に重なりがないこと、原稿を最後まで消費することを検査する。
読み飛ばしは最初のボックスと強制改行の前で止まり、描画用に改行位置のペナルティを加えても原稿のボックスは増えない。
これは検査を通る、範囲が重ならない改行列についての証明である。
`I1_caption_whole_payload_exact` は、原稿全体も保持する検査を使い、読み飛ばしたペナルティの位置を選んで空の表示行を作る場合も扱う。
この場合、原稿に対して計算した次の開始位置が、すでに読み飛ばした先の位置と同じことを検査する。
`I1_caption_whole_grid_span` は、この空の表示行も数えた行数で、キャプションの占有行数を計算することを示す。
`I1_caption_next_start_monotone` は、任意の項目列で、後ろの位置から読み飛ばしを始めても次の行の開始位置が後戻りしないことを示す。
`I1_caption_next_start_bounds` は、開始位置が原稿内なら、読み飛ばし後の位置も原稿内にあることを示す。
どちらも項目の幅や行長の上限を仮定しない。
Haskell の各パスが作る active な候補と選ばれた履歴がこの検査を満たすことは、下の `I1_caption_chosen_history_assembles` で証明する。
`I1_caption_active_step_progress` は、実装と同じ行数と fitness のキーで候補をまとめる一段階について、候補の原稿位置の上下限と、履歴の改行数が保存されることを示す。
先行候補の位置と履歴が正しいことは、この定理の前提である。
評価に使う整数の値と生存判定は、文脈全体に依存してよい。
`I1_caption_active_equal_cost_keeps_later` は、同じキーでデメリットが等しい場合、後から調べた先行候補の履歴を残すことを示す。
`I1_caption_ordinary_pass_from_start` は、初期候補から通常のパスの候補列を最後まで処理することを示す。
候補列が原稿順に並ぶという前提のもとで、各履歴は実際の改行候補だけからなり、先行する位置が厳密に小さく、行数は履歴の長さと一致する。
候補の数や評価値の上限は置かず、候補列を一つずつ消費する再帰で終了する。
逆順の候補列ではこの不変条件が壊れる反例も検査する。
これは追い出しを使わない通常のパスの履歴についての証明である。
`I1_caption_push_out_advances` は、第 4 パスで行末を手前へ戻す追い出しについて、次の開始位置より後ろの、はみ出さない改行候補を探し、原稿位置、デメリット、先行位置の順で選ぶ処理を扱う。
選ばれた候補の原稿位置は、先行候補すべてに共通の位置の下限より厳密に大きくなる。
`I1_caption_restart_scan_rank` は、原稿位置の下限と原稿長、未処理候補数から作る自然数が、この位置の前進で減ることを示す。
再開時には元の全候補を調べ直してもよく、再試行数の上限を追加しない。
`I1_caption_rescue_minimum` は、救済で選ぶ先行候補が、文脈から求めたはみ出し量の最小値を持つことを示す。
値が等しければ最初の候補を残す。
`I1_caption_rescue_history` は、この先行候補へ fitness 3 の行を一つ加え、改行位置の順序と履歴を保つことを示す。
救済で現在の改行位置まで進む場合も、再開の自然数は減る。
`I1_caption_generated_scan_terminates` は、項目から作る候補列で、通常の更新、追い出しによる候補列の再開、はみ出す行の救済を通る走査に無限列がないことを示す。
候補列の原稿順と範囲は、パターンによるハイフンの除外とグルーの直前のボックスを調べる候補生成から導く。
各分岐で原稿位置の下限と候補列の不変条件が保たれ、同じ自然数が厳密に減る。
これらは状態遷移のモデルについての証明である。
評価値を求める文脈依存の関数や順位付けを Haskell の処理と照合することは、まだ証明していない。

走査が選ぶ履歴は、原稿全体の組立検査を通る。
`I1_caption_ordered_breaks_assemble` は、ボックスでない改行位置が原稿順に厳密に増え、最後が原稿の最終項目であれば、組立検査が成功することを示す。
直前の改行の読み飛ばし範囲に入る改行も、`I1_caption_discard_inside_same_start` により同じ開始位置へ戻るので、空の表示行として通る。
`I1_caption_scan_history_step` は、通常の更新と追い出しによる再開と救済のどの分岐でも、各 active の履歴についての不変条件が保たれることを示す。
履歴は実際の候補だけからなり、原稿位置が厳密に減る順に並ぶ。
履歴の長さは行数と一致し、候補の原稿位置は最後の改行の次の位置に一致する。
`I1_caption_scan_reaches_final` と `I1_caption_generated_scan_completes` は、項目から作る候補列の走査が燃料や再試行の上限なしに最終状態へ達することを示す。
`I1_caption_chosen_history_assembles` は、その最終状態で最終項目に達した候補のどれを選んでも、履歴から作る改行列が組立検査を通り、表示行の数が候補の行数と一致し、原稿のボックスが原稿順に一度ずつ出ることを示す。
この定理は最終の選択規則を仮定しない。
Haskell は最小デメリットと fitness、履歴のキーで最終項目の候補から一つを選ぶので、どの選択でもこの結論が成り立つ。
評価関数は任意の文脈依存の関数のままであり、評価値と幅の計算を Haskell と照合する義務は残る。
`CheckCaptionAssembly.hs` はボックスの幅、グルー、任意のペナルティ、幅のあるペナルティ、強制改行を組み合わせ、3 種の行長と 2 種の行末の伸びについて、実際の改行器を呼ぶ。
負の任意のペナルティを含め、実装が返す改行位置とボックス番号列を Lean の具体例として出力する。
16,806 例について、改行列の検査を通り、実装の出力と原稿のボックス番号列が一致することを Lean でも確認した。
これは有限の対応試験であり、上の未証明の一般的な対応を置き換えない。

実フォントの対応試験は、横組み 12 字幅の段で、同じ図番号と「M」12 字を組む。
Source Sans Pro のキャプションは 1 行、Source Serif のキャプションは 2 行になる。
段の容量がキャプションの行数以下なら、ドライバーは G07038 を返す。
1 行余るときは、どちらのフォントでも幅 5 pt、高さ 15 pt の画像を置く。
`I2_real_fonts_at_capacity` は、この 5 通りの行数と寸法を sp 単位で照合する。

表の本文行を段ごとに置く `placeTable.rowsFrom` では、行全体が収まらず、直前に見出し行だけを置いた段でもないとき、次の段で同じ行を再試行する。
見出しを繰り返した直後の使用行数は、表の開始位置と見出しの行数の和に等しい。
そのため、再試行では背の高い行でも 1 行分の表データを消費する。
Lean では残る表データの行数の 2 倍に、見出しの直後でない場合は 1 を足した値が、どちらの分岐でも減ることを証明した。
行が収まるかを調べる関数と次の段の開始位置は任意でよく、本文行を元の順で過不足なく出力する。

Haskell の `paginate 1 4` に見出し 1 行、本文 1 行、5 行の高さの本文、本文 1 行からなる表を渡すと、3 ページすべてで見出しを繰り返し、本文を各ページに順に置いた。
見出しがなく、空の本文行、5 行の高さの本文、空の本文行が続く入力では、本文の 5 行を 1 ページに出力して終了した。

脚注の `splitNotes` は脚注 1 件が収まれば残りのリストを処理し、収まらなければ脚注を分割するか、後続を含めて次の段に送る。
Lean は、段の残りの行数が負の場合を含め、表示分と繰り越し分を順に並べると元の全脚注の各行が 1 回ずつ現れることを証明する。
`carryNote` が 0 行以上の残りの行に置く部分と次に残す部分も、脚注番号と行位置を保存する。
1 行以上の残りの行がある段でさらに繰り越すなら、残りの行数は減る。

Haskell の `paginate 1 5` で本文 1 行に 1 行、5 行、2 行の脚注を順につけた。
1 ページ目は最初の脚注と 2 個目の先頭 2 行を、2 ページ目は 2 個目の残り 3 行を置いた。
この時点で 3 個目を開始位置 0、長さ 0 として記録し、3 ページ目で開始位置 0 から 2 行を置いた。

本文と脚注を合わせたモデルでは、本文 1 行を消費する、脚注の一部を置く、脚注を置けない段から次段に送る、という遷移を扱う。
「残る本文の行数」「繰り越す脚注の件数と行数の和」「次に脚注を置けるまでに通過する段数」の辞書式順序で、それぞれの遷移の後に値が減る。
本文の残りと繰り越し分がともに尽きたとき、本文の行番号列と脚注の各行の番号列が元の入力と一致する。
上の 3 ページの入力でも同じ行番号列を構成した。
同じページで次の段に進むと、ページ末までに残る段数が一つ減る。
予約、図版、ほかの脚注のない新しいページでは、最初の繰り越し脚注を 1 行以上置くか、段容量不足を診断する。
`flushDeferred` の証明は、現在の段番号、ページの段数、脚注の予約行数、転置図版を含む待ち行列から終了までの進み具合を求める。
ページをまたぐと予約行数を 0 に戻し、先頭に並ぶ転置図版を 1 枚ずつ独立したページに置いてから、脚注を前から繰り越す。
脚注の後で収まる通常図版を並べると、出力した図版と残った図版をつないだ列は元の図版列と一致する。
「待つ図版の枚数」「繰り越す脚注の件数とその行数の和」「ページ末までの残り段数」の辞書式順序で、図版か脚注を繰り越す段階ごとに値が減る。
脚注が段容量に入らず診断される場合は、その脚注を待ち行列から除いた時点で値が減る。
脚注も予約もない新ページで図版を置くときに段が空であることを仮定する。
Haskell の `advance` は出力スロットと脚注を空にしてから `placeDeferred` を呼び、段頭のボックスをその後で開く。
下の回帰例では、同じ 2 段構成と予約行数を Lean に渡し、2 段目を経て転置図版の次の 3 ページ目で脚注と図版の待ち行列が空になることを確かめた。

予約済みの脚注がある段では、段の残りの行数を 0 行で下限にする必要がある。
5 行のページを一時的に 8 行増やし、5 行の脚注を置いてから 2 段組みに切り替えると、後の段で 6 行が予約されたまま容量が 5 行に戻る。
8 行の次の脚注はこの段までに 5 行を表示済みである。
修正前の Haskell 実装は、続きの開始位置 5 で長さ−2 を記録し、転置図版の次のページに開始位置 3 から 3 行を置いた。
このため脚注の行 3 と 4 を二度出力した。
修正後は開始位置 5、長さ 0 として次ページに繰り越し、転置図版の後に開始位置 5 から残る 3 行を置く。
Lean は任意の整数の段容量、予約行数、区切り行数で、繰り越す脚注の開始位置が後戻りせず、すべての行を順に保つことを証明する。

原稿の終端では、保留した行アキと待機図版が両方あるときに一度だけ先に改段し、その後で脚注と図版を最後まで置く。
`I5_measured_flow_eof` は、この手順で箱の内外の図版を原稿順に一度ずつ出すことを、段の容量、段の先頭位置、脚注区切りの行数から求めた残りの行数で確かめる。
`I4_flush_figures` は、回り込み図版の前では待機図版がなくなった時点で改段を止め、残る脚注は次の本文の配置に渡せることを示す。

この証明の基にした Haskell の `Flow` 22 種は、通常図版、転置図版、箱と、それ以外の 19 種に分けられる。
`MeasuredFlow.events` は、図版の前後と箱の出入りで実行した本文の操作を受け取り、操作ごとに更新した状態で次の図版の配置条件を計る。
図版の前の改ページを実行してから、待機中の図版の有無、段番号、本文と脚注の使用行数で `waitsBehind` を判定する。
待機する図版は直前の指定行数や行アキを消費しない。
`I5_all_measured_flows_eof` はその実行列について、入れ子の箱と原稿末尾の処理を含めて図版が原稿順に一度ずつ出ることを示す。
本文の操作列を各コンストラクターの引数と先読みから生成する処理は、なお Haskell の `step` と照合する必要がある。
現在の main の `FlowAt` には、さらに `FNoBreakLines` があり、その行数を含む制御もこの照合に含める。
[root ADR 0398](https://github.com/tett23/golem/blob/0d20d3e2e445d69aa576ec97615a51c31114ceec/docs/adr/0398-styled-separators-in-manuscripts.md) で加わった `USeparator` からのフロー生成と、区切りを後続行と保持できなければ G07134 を返す後処理も、現在の未証明の範囲に含む。

段落と詩節の通常の分割では、`splitAtBreak` が先頭と末尾に必要な行数を満たす最大の部分を選ぶことを `I3_kept_break_is_largest` が示す。
空段で強制的に行を置く分岐は、この最大性の前提から外れる。
詩節では、詩行が占める行数の累積値と段に残った行数を比べ、丸ごと置ける詩行を数える。
`I3_fitting_verses_maximal` は、次の詩行まで含めると収まらないことを示す。
`placeKept` が複数の配置を試す場合は、それぞれの候補で本文を正しく置ければ、選ばれた状態に本文が一度ずつ残る。
改段後に行アキを置き直す場合は、元の要求行数を使い、移動先の段で実際に消費した行数を記録する。
`I3_replayed_space_charges` は要求の順序と実際の消費行数の合計を、`I3_replay_on_column_top` は段頭で消費する行数がゼロであることを示す。

## 元の述語の書き写し

Alloy のモデルを Lean へ書き写し、この書き写しを改ページの規則のモデルとする。
規則を変えるときは、まずこの定義を変える。
`docs/golem-layout/models/pagination.als` と Alloy の定期実行は、[root ADR 0352](../../docs/adr/0352-prove-pagination-in-lean.md) が定めるとおり、移行の完了まで残す。
書き写した述語は、元にした ADR ごとに第 1 群から第 5 群に分ける。
[docs/adr/0204](../../docs/adr/0204-pagination-invariants-by-exhaustive-small-inputs.md) の述語を第 1 群とする。
`AlloyInput` は段の容量と使用済み行数、原稿順の項目を持ち、項目の位置を列の番号とする。
`alloyInputFact` は `fact input` の残りの条件を、容量の 3〜6 行も含めて検査する。
`alloyPlacements` は `fact allPlacements` のとおり、区切り位置、置く図版の部分集合、置く行アキの部分集合のすべての組を列挙するので、`some p: Placement` と `no p: Placement` はこの列の上の量化になる。
`alloyFits` から `alloyAll7` までは、[docs/adr/0204](../../docs/adr/0204-pagination-invariants-by-exhaustive-small-inputs.md) の述語を一つずつ写す。
整数は上限のない自然数とし、Alloy の 5 ビット整数の折り返しは写さない。
Alloy が図版の集合の位置を整数として比べる `p.kept.pos > i.pos` は、Alloy と同じく位置の和で比べる。
`alloy_someFits`、`alloy_noneMeetsAll`、`alloy_greedyOrphan`、`alloy_greedyWidow`、`alloy_greedyKeepHeading`、`alloy_tallFigure` は、解のある 6 コマンドの本体を、書き写した述語の上で具体的な入力により示す。
`check-alloy-witnesses.sh` は同じ入力を Alloy に固定して、どれにも解があることを確かめる。
書き写しが元の述語と一致することは、次の有限の突き合わせで一度確かめた記録として残す。
Lean の定義がモデルなので、両者の同値は証明の対象にしない。
`DiffAlloy.lean` と `check-alloy-diff.sh` は、書き写した述語を元の述語と入力ごとに突き合わせる。
項目 2 個以下のすべての入力と、項目 3〜4 個の入力の 97 個に 1 個を、容量 3〜4 行、使用済み行数 0、1、容量 −1、容量で選ぶ。
各入力について、Lean が各述語を満たす配置の集合を計算し、Alloy のコマンドがその入力を固定して、元の述語がちょうどその集合で成り立つことを述べる。
固定した入力のインスタンスは同型を除いて一つなので、コマンドに解があることは、`fact input` がその入力を許し、すべての述語が一致することと同じである。
2026-11-23 に間隔 97 で生成した 2,719 個のコマンド（`diff0`〜`diff2718`）は、すべてに解があった。
`diff0`〜`diff1677` と `diff1678`〜`diff2718` の 2 回に分けて Alloy 6 で走らせた。
これは有限の照合であり、証明ではない。

同じ群で解のない 11 コマンドは、書き写した述語の上で、項目の数と容量の上限なしに証明した。
`alloy_noneMeetsAllButGreedy` は、図版が高々一つで行アキとスペースと `need-lines` のない任意の入力で、容量が 1 行以上かつ使用済み行数が容量以下なら、詰める規則のほかの 7 規則を同時に満たす配置があることを示す。
その配置は、空の段の先頭が本文なら先頭の本文だけを置き、それ以外は本文を置かず、図版は図版規則が求めるとおりに置く。
`alloy_orphanEmpty`、`alloy_widowEmpty`、`alloy_keepHeadingEmpty`、`alloy_orphanWidow`、`alloy_keepHeadingOrphan`、`alloy_keepHeadingWidow`、`alloy_keepHeadingFigure`、`alloy_figureOrder`、`alloy_figureEmpty` は、この配置が二つの規則を同時に満たすので、規則の対に衝突がないことを示す。
`alloy_greedyFigure` は、使用済み行数が容量以下なら、収まる区切りを一つずつ進めて詰める規則と図版規則を同時に満たす配置があることを示す。
区切りを一つ進めて図版が新たに置かれる場合も、図版規則の和がそのまま新しい使用行数の上限になる。
容量 1 行以上と使用済み行数の条件は `fact input` から導かれ、`alloy_input_fact_bounds` が示す。
容量の 6 行以下という条件と項目の数の上限は使わない。
容量 0 行の空の段に本文 1 行を置く入力では 7 規則を同時に満たす配置がないことを、具体例で検査した。
この入力は容量 3 行以上という `fact input` の条件を満たさないので、Alloy のコマンドの反例ではない。

第 2 群として、[docs/adr/0206](../../docs/adr/0206-pagination-points-the-invariants-did-not-decide.md) の述語も書き写した。
`alloyAfterHeadingsOnly`、`alloyLineAfterHeadingsRule`、`alloyOrphanH`、`alloyWidowH`、`alloyKeptLines`、`alloyKeepHeading21`、`alloyKeepHeadingR`、`alloyRecto`、`alloyBase` が、元の述語に一つずつ対応する。
既存の `alloyLineAfterHeadings` は見出しの役割の列だけを見る別の宣言なので、書き写しには `Rule` を付けた名前を使う。
`keepHeading21` と `keepHeadingR` は、見出しの連なりを始め、続ける項目の種類だけが異なるので、`alloyKeepRun` を共有する。
解のある `alloy_strictAfterHeadings` と `alloy_decidedSome` は具体的な入力で示し、同じ入力を Alloy に固定して解を確かめた。
解のない `alloy_keep21` は、第 1 群の配置が置く見出しがいつも段の先頭にあることから、上限なしに示す。
見出しの後に行を一行置く規則があるので、残る 3 コマンドには第 1 群の配置では足りない。
`alloyHeadingPlacement` は、空の段の先頭が見出しで、次の本文が行で、その間に置く図版がなければ、見出しとその行を置く。
それ以外は第 1 群と同じく、空の段の先頭の本文だけを置くか、本文を置かない。
`alloy_heading_placement_meets` は、図版が高々一つで行アキとスペースと `need-lines` のない任意の入力で、容量が 2 行以上かつ使用済み行数が容量以下なら、この配置が第 2 群のすべての規則を満たすことを示す。
`alloy_relaxedAfterHeadings`、`alloy_rectoKept`、`alloy_rectoEnds` はこの定理から導く。
容量 2 行以上の条件は `fact input` から導かれ、`alloy_input_fact_cap_two` が示す。
容量 1 行の空の段に見出しと行を続ける入力では、緩めた規則を同時に満たす配置がないことを具体例で検査した。
この入力は `fact input` の条件を満たさないので、Alloy のコマンドの反例ではない。
`EnumerateSmall.lean` は、項目 4 個以下、容量 3〜4 行の入力 18,099 個で、この 4 コマンドに解がないことを書き写した述語の上で確かめる。
これは書き写しの有限の照合であり、証明ではない。

各群のコマンドは、名前空間 `Alloy` の対応する定理で、書き写した述語の上のコマンドの本体として述べる。
解のあるコマンドは、`fact input` と本体を満たす入力があることを述べる。
解のないコマンドは、`fact input` を満たすどの入力でも本体が成り立たないことを、項目の数の上限なしに述べる。
`check.sh` は、第 1 群から第 5 群までの 42 コマンドすべてについて `Alloy` の中の対応する定理を要求する。
名前空間の外にある対応する既存の宣言は、それぞれ独自の抽象化の上の補助の命題として残し、書き写しとの同値は求めない。

第 3 群として、[golem-layout ADR 0026](../../docs/golem-layout/adr/0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) の待機図版と行アキの述語も書き写した。
`alloyWaiting`、`alloyNextOf`、`alloyNextOf25`、`alloyInColumn`、`alloyBlankAtTop`、`alloyFigures`、`alloyFigureOrder`、`alloyBlankWithNext`、`alloyBlankWithNext25`、`alloyBase26` が、元の述語に一つずつ対応する。
解のある `alloy_waitingBlankSome` と `alloy_blankBeforeWaiting25` は具体的な入力で示し、同じ入力を Alloy に固定して解を確かめた。
解のない 4 コマンドには `alloyPlacement26` を使う。
空の段の最初の項目が本文ならその本文だけを置き、そうでなければ本文を置かない。
行アキと `need-lines` のほかの最初の項目を、最初の項目として扱う。
図版は原稿順に、それまでに置いた図版で図版規則を読んで置き、行アキは与えた次のブロックの規則で置く。
`alloy_placement26_meets` は、図版が高々二つでスペースと `need-lines` のない任意の入力で、容量が 1 行以上かつ使用済み行数が容量以下なら、この配置が `base26`、行アキの規則、孤立行、寡婦行、見出しの規則を満たすことを示す。
次のブロックの規則は、[golem-layout ADR 0026](../../docs/golem-layout/adr/0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) の `nextOf` でも、それ以前の `nextOf25` でもよい。
`alloy_waitingBlankAllButGreedy`、`alloy_blankRules25`、`alloy_blankFigureOrder` はこの定理から導き、`waitingBlankNone` は最初のものから導く。
図版が二つ以下という条件は `fact input` から導かれ、`alloy_input_fact_two_figures` が示す。

第 4 群と第 5 群として、`need-lines` とスペースの述語（[golem-layout ADR 0027](../../docs/golem-layout/adr/0027-need-lines-judged-again-after-spaces.md)、[golem-layout ADR 0035](../../docs/golem-layout/adr/0035-a-larger-need-lines-after-a-judged-one-is-judged-again.md)、[golem-layout ADR 0046](../../docs/golem-layout/adr/0046-the-alloy-model-judges-a-larger-need-lines-without-the-spaces-before-it.md)）と、段落の保持の述語（[docs/adr/0261](../../docs/adr/0261-keep-options-of-paragraph-styles.md)）を書き写した。
第 4 群は `need` で始まる 10 コマンド、第 5 群は `keep` で始まる 3 コマンドである。
Alloy の `minus[Col.cap, x] >= l` は、引き算を使わずに `x + l ≤ cap` と書く。
`Kept` と `AllLines` は段落の番号で `AlloyKeeps` に持ち、`alloyKeepsFact` が `fact keeps` を検査する。
解のある 8 コマンドは具体的な入力で示した。
`needMoreSpace46Here` のほかの 7 コマンドは、`check-alloy-witnesses.sh` で同じ入力を Alloy に固定して解を確かめた。
`needMoreSpace46Here` は元のコマンドが入力を固定しており、通常の期待値でも解があると記録されている。
`alloy_needMoreSpace46` は、コマンドの条件から入力が段落の番号を除いて一つに決まることを示し、その入力で段落が段に入ることを段落の番号によらず示す。
`alloy_keepNone` は、第 1 群の配置が段落を段の先頭でしか分けないことから導く。
`alloy_keep_default` は、保持行数が 2 と 2 のとき、どの配置でも孤立行と寡婦行の規則が K1 と K2 と段落ごとに一致することを示し、`keepDefaultDiffers` を導く。
段に置いた行が段落の先頭の行の並びになることを、`alloy_here_prefix` が示す。

`needSpaceNone` と `needMoreNone` は、名前空間の外の宣言とは別に、書き写した述語の上で、項目の数の上限なしに証明した。
`need-lines` の次のブロックを段に残す規則（P7）があるので、`need-lines` の後のブロックまで置く配置を作る。
`alloyPlacement27` は区切りを受け取り、図版を `figures27` の規則で原稿順に置き、行アキを `blankWithNext` で置く。
`alloyBreak27` は、この配置が段容量と P1 を満たす区切りのうち、最大のものを選ぶ。
区切り 0 はいつもこの条件を満たし、空の段の先頭が本文なら区切り 1 も満たすので、空の段から先頭の内容を送らない規則も成り立つ。
この区切りで、P7 が段に置くよう求めるブロックが段の外にあるとする。
`alloy_keeps27_step` は、そのとき区切りを本文一つ分進めた配置も段容量と P1 を満たすか、そのブロックである図版を図版規則が段に置くことを示し、最大の区切りを選んだことと矛盾させる。
区切りの本文より前で二つの配置が一致することを `alloy_agree27_step` が示し、図版規則がその図版より前の本文と図版だけを読むことを `alloy_cond27_congr` が示す。
`needMoreNone` では、同じブロックに先行し、行数が同じか大きい `need-lines` に余地があれば、後の `need-lines` にも余地がある。
`EnumerateSmall.lean` は、項目 4 個以下、容量 3〜4 行の入力 66,744 個で、2 コマンドに解がないことを書き写した述語の上でも照合する。

## 格子モードの改ページ全体のモデル

`Whole.lean` は、格子モードの `placeAll` と `step` を、Haskell の関数ごとに一つの Lean の定義へ写した状態遷移のモデルである。
`Pagination.lean` の部分ごとのモデルとは独立し、一つの状態 `St` の上で原稿の全体を処理する。
Haskell の `placeAll` は原稿の列についての構造的な再帰なので、全体の終了は、`step` の中で次の段へ進むループの終了に帰着する。
このモデルでは、そのループをすべて整礎な再帰で定義した。
Lean はループごとに減少する尺度の証明を求めるので、定義が受理されれば、どの入力でも各ループは有限回で止まる。
`check.sh` は `Whole.lean` に `partial`、`sorry`、`axiom` などがないことを確かめ、ファイルを検査する。

尺度は、待つ内容、段の行数の縮み、段の使用、ページの残りの段数の 4 つ組の辞書式順序である。
待つ内容は、待機中の図版の枚数と、繰り越す脚注ごとの行数に 1 を足した値の和である。
`I4_nextColumn_rank` は、何かを置いた段か `FAdjustLines` で縮んだ段から次の段へ進むと、この 4 つ組が減ることを証明する。
次のページへ進むときは、待つ内容があれば必ず減る。
先頭の転置図版にページを与えるか、最初の繰り越し脚注を 1 行以上置くか、その脚注を置けないと診断して除くか、待機中の最初の図版を空の段に置くからである。
待つ内容がなければ、新しいページの段は空になり、行数の縮みも 0 に戻る。
同じページの次の段へ進むときは、待つ内容が増えず、行数の縮みが 0 に戻り、残りの段数が一つ減る。
`I4_nextColumn_flush_rank` は、待つ内容がある間は、待つ内容とページの残りの段数の組が減ることを証明する。
`flushDeferred` と `flushFigures` は、この組で止まる。
ページの残りの段数は、状態が持つ段組みの段数から求める。
段組みを切り替えるのは `place` の中だけで、次の段へ進む操作は段組みを変えないので、ループの中では段数は変わらない。
`keep` は空でない段からだけ次の段へ進むので、4 つ組で止まる。
`placeLines` の段のループは、残りの行数、`keep-all-lines` の有無、4 つ組の辞書式順序で止まる。
行を一つも置かずに次の段へ進むのは、行数が縮んだ空の段か、何かを置いた段からだけである。
`placeStanza` のループは、残りの詩行の数、`keep-all-lines` の有無、4 つ組の辞書式順序で止まる。
詩行を一つも置かずに次の段へ進むのは、空でも見出しだけでもない段からだけである。
`placeCode` のループは、残りの行数と 4 つ組の辞書式順序で止まる。
空の段には少なくとも 1 行を置くので、行を置かずに次の段へ進むのは、何かを置いた段からだけである。
`KeepColumn` の表の `rowsFrom` は、残りの行数と、見出し行の直後かどうかの辞書式順序で止まる。
行が収まらなければ次の段で見出し行を繰り返し、繰り返した見出し行の直後では行を必ず置くからである。
それ以外の表の `placeTableAcross` は、残りの組の数、見出し行を繰り返したか、4 つ組の辞書式順序で止まる。
組を置かずに次の段へ進むのは空でない段からだけで、見出し行を繰り返すのは組ごとに一度だけである。
本の部と箱は、その中のフローを `step` で一つずつ置くので、`step`、`place`、`placeFlow` と、フローの列を置く `runFlows` は相互に再帰する。
この再帰は、フローの重み（`flowWeight`）と関数の順位の組の辞書式順序で止まる。
本の部と箱の重みはその中のフローの重みの和より大きく、`flattenParts`（`flattenBookParts`）で平らにした列の重みは元の列の重みを超えない（`flattenParts_weight`）。
`placeAll` は原稿の列について構造的に再帰する。
`I4_paginate_ends` は、この全体が任意の有限の原稿で値を持つことを述べる。

`I5_paginate_text` は、出力のページに、段落、詩の行、回り込み図版の横の行、定義の項、表の行、見出し、コードの行が原稿の順に一度ずつ並ぶことを証明する。
この定理は `nextNeed`、`fitting`、`roomForLine` のどの値でも、段の容量と脚注区切りの行数のどの値でも成り立つ。
本文の行を置くのは `putLine`、`putBlock` と、`placeCode` がコードの行の部分を置く `putSlot` だけで、表の見出し行を繰り返す `putRepeated` は本文に数えないスロットを置く。
ほかの操作は出力済みのページと現在の段のスロットから本文を消さず、増やさない。
`advance` は、現在の段を閉じてからスロットを空にするので、行は一度だけ出力に移る。
表の行は、キャプションが上なら、キャプション、見出し行、本体の行の順に、キャプションが下なら、見出し行、本体の行、キャプションの順に数える。
次の段で繰り返す見出し行は、注などを除いた同じ行なので、本文の行とは別のスロットに置き、本文には数えない。
`no-break` か `keep-with-next` の前の段落では、`placeKept` が、段落の全体をそのまま置くか、最後の行を残りから分けて置くかを選ぶ。
分けるときも、前の部分を置いた状態に続けて後ろの部分を置くので、行は原稿の順に一度ずつ置かれる。
`waitFor` と `checkNoBreak` は待つ制御と満たせなかった制御だけを変えるので、本文と図版を変えない。
本の部の `placeBookPart` は、中のフローをそのまま置いた結果、平らにして置いた結果、次の単位から置いた結果のどれかを選ぶ。
どの結果も、選ぶ前の状態に中のフローの行を原稿の順に足したものなので（`text_placeBookPart`）、どれを選んでも行は一度ずつ置かれる。
本の部と箱の行は、中のフローの行を原稿の順につないだ列として数える。
箱は、段ごとの部分の前の行（`openBox`）と、最後の部分の後の行（`boxEnd`）を使用行数に足すだけで、本文と図版を変えない。

図版の順序には、図版の高さが 1 行以上という前提が要る。
高さ 0 行の図版の直後に転置図版があると、Haskell の実装は図版の順序を原稿と逆にする。
`paginate 1 5 [FFigure 1 0 [] [], FPageFigure 2 [] []]` を `runghc` で実行すると、1 ページ目に転置図版 2 を、2 ページ目に図版 1 を置いた。
図版 1 を置いても段の使用行数が 0 のままなので、転置図版をすぐに置く条件（待機中の図版がなく、ページの最初の段で、使用行数と脚注が 0）が成り立つ。
このとき `pageFigure` は、図版 1 のある段を閉じる前に、転置図版のページを出力する。

`I5_paginate_figures` は、この前提の下で、出力のページに図版と転置図版が原稿の順に一度ずつ並ぶことを証明する。
前提は四つで、原稿のどの図版も、本の部と箱の中の図版も高さが 1 行以上であること、本の部と箱の中を含めて箱の直後のブロックが待っている後の罫線と領域を共有しないこと（`BoxesOk`）、段の容量が 1 行以上であること、脚注区切りの行数が 0 行以上であることである。
段の容量の前提は、[root ADR 0352](../../docs/adr/0352-prove-pagination-in-lean.md) が入力とする段と同じである。
定理は、出力済みのページの図版、現在の段の図版、待機中の図版をこの順につないだ列が、それまでに読んだ原稿の図版の列に等しいという不変条件から導く。
転置図版をすぐに置くのは段の使用行数と脚注の行数がともに 0 のときだけなので、この不変条件には、図版のある段では使用行数か脚注の行数が 1 以上であるという性質が要る。
この性質は、使用行数が 0 以上か脚注の行数が 1 以上であること、組の先頭行が 0 以上か組が各段の下に脚注の行を確保していること、待機中の図版の高さが 1 行以上であることと合わせて、すべての操作で保たれる。
組の先頭行についての性質は、同じページの次の段の使用行数が組の先頭行に、脚注の行数が確保した行数に戻るので要る。
`startSet` は、切り替える前の段の使用行数を新しい組の先頭行に、脚注の行数を確保する行数にするので、使用行数についての性質からこの性質が出る。
脚注の行数は段の中で減らないので、脚注の行数についての部分は段の中の操作で保たれる。
脚注の行数が減らないことには、脚注区切りの行数の前提が要る。
golem-layout の `paginateWithin` は区切りの行数を 1 以上にするので、この前提は実装で成り立つ。
`needBeforeSpaces` だけは、使用行数からスペースの分を一時的に引くので、この性質を一時的に崩す。
そこで、ページと段の組が前へしか進まないことを示し、段が変わらなければ使用行数、脚注の行数、スロットがもとに戻ることと、段が進めば新しい段で性質が成り立つことを使う。

使用行数を増やす操作は、どれも 0 行以上を足す。
`KeepColumn` の表の前のアキは `max 0 (min sp (free st))` を足すので、脚注の行数が段の行数を超えて残りの行数が負の段でも、使用行数は段の先頭より下がらない。
段の容量の前提は、行アキの行数が 0 以上で、行アキを足しても使用行数が減らないことに使う。
行数の変更（`FAdjustLines`）は段の行数を負にもするが、図版の順序の不変条件はどの値でも保たれる。
`adjustLines` は使用行数、脚注の行数、スロットを変えず、次の段へ進むと行数の変更は 0 に戻るからである。

段組みを切り替える `FSwitchColumns` は、`FAdjustLines` が足した行を数えず、版面の行（`typeAreaFree`）が残るときだけ同じページで新しい組を始める。
新しい組の段は行数の変更を 0 に戻し、版面の行数を持つ。
そのため、組の先頭行は段の行数より小さい。
`paginate 1 5 [FAdjustLines mk 3, FParagraph defaultKeep (ls 0 7), FSwitchColumns (ColumnSet 2 0 0 0), FParagraph defaultKeep (ls 10 1), FBreak BreakColumn, FTable 50 0 (ls 20 1) [ls 30 1] [] False]` を `runghc` で実行した（`ls b n` は id が b から n 個の注のない行）。
1 ページ目は段落の 7 行だけを持ち、2 段組みは 2 ページ目の 0 行目から始まった。
表の見出し行と本体の行は、2 ページ目の 2 段目の 0 行目と 1 行目に置かれた。

回り込み図版の横の行が次の段へ送られると、Haskell の実装は送った先の段の使用行数を、`placeLines` の後の状態の値のままにする（PR #1129）。
`place` の `FWrapped` は、図版を置いた段と `placeLines` の後の段が同じときだけ、使用行数を `max (sUsed st1 + size) (sUsed placed)` とし、図版の除外領域の終わりまでを空ける。
このモデルの `place` の `wrapped` も、ページと段が変わらないときだけ使用行数を `max` で広げる。

モデルは次の点で Haskell の実装を抽象化する。
`nextNeed`、`fitting`、`roomForLine` の値は `Env` の引数とし、定理はそのどの値でも成り立つ。
コードの行の部分の行数を決める `Code.hs:150` の `codeSpan` も `Env` の引数とし、コードの組み方は自然数で区別する。
罫線の領域の行数（`RuleArea.hs` の `ruleBefore`、`ruleBeforeAtStart`、`rulesJoined`、`ruleAfter`、`ruleAfterAtEnd`）も、ブロックの id ごとの `Env` の引数とし、罫線の位置（`sRules`）は出力の付帯情報なのでモデルには持たない。
`keepAhead` の 3 番目の値（`keep-with-next` が求める最初の行数）も `Env` の `keepNextLines` とする。
部分を段の中で保つか（`envKeepParts` が `KeepColumn` か）も `Env` の引数とし、定義の項の置き方はその両方の値で扱う。
`no-break` と `keep-with-next` が先の原稿から求める値も `Env` の引数とする。
段落が最後の行を保つ相手の行数（`Decide.hs:125` の `keptNeed`）、先の制御が求める最後の行数（`Decide.hs:133` の `keepAhead` の 2 番目の値、制御がなければ 0）、次の部分の最初の行数（`Decide.hs:186` の `nextFirstLines`）の三つである。
フローは、段落、続きの段落、見出し、図版、転置図版、改段と改ページ、スペース、行アキ、`need-lines`、コード、定義の項、表、`no-break`、`keep-with-next`、段組みの切り替えと戻し、段の行数の変更（`FAdjustLines`）を扱う。
本の部、箱、詩、回り込み図版、節と改ページつきの段落の開始（`FSection`）も扱う。
罫線つきのブロック（`FRuled`）も扱う。
節の開始は、改段や改ページと同じく待つ改ページ（`Pending`）に加え、次のフローの前に `startBefore` で始める。
節が始まったページの記録 `sSections` は、状態の `sections` に持つ。
回り込み図版（`SWrapped`）は、`I5_paginate_figures` の図版に数えない。

罫線つきのブロックは、図版の順序の不変条件を、後の罫線が共有を待つ状態とそうでない状態に分ける。
罫線つきのブロックの `flushJoin` は、後の罫線の領域を次のブロックと共有しなかったとき、使用行数に `min k (free st)` を足すので、残りの行数が負なら使用行数を減らす。
図版の順序の不変条件をこの操作で保つには、共有を待つ状態（`sJoin`）では残りの行数が 0 以上か脚注の行数が 1 以上であることが要る。
そこで不変条件 `Inv` には共有を待たないこと（`join`）を足し、共有を待つ状態は別の述語 `Win` で表す。
`Win` は、共有を待つこと（`join`）を除けば `Inv` が成り立ち、残りの行数が 0 以上か脚注の行数が 1 以上で、待っている改ページ、`need-lines`、行アキがないことである。
後の罫線が待つのは、`planOf` が `joinsNext` で、平らにした次のフローが前の罫線を共有するブロックだと判定したときだけなので、待つ状態の次の `step` は、そのブロックか、そのブロックで始まる本の部に限られる（`JoinAhead`）。
このとき改ページ、`need-lines`、行アキの処理は状態を変えないので（`prelude_win`）、ブロックの `placeRuled` が `Win` の状態から共有するか、`flushJoin` で領域を閉じる。
収まると判定して置いたブロックの行は、脚注を置いても残りの行数を負にしないか脚注の行数を 1 以上にするので（`putRuledLines_room`、`putBlock_room`）、ブロックの後の状態は `Win` になる（`commitRuled_good`）。
`Win` の状態の `flushJoin` は、残りの行数が負なら脚注の行数が 1 以上なので、使用行数を減らしても `Inv` を保つ（`flushJoin_inv`）。

`I5_paginate_figures` の前提 `BoxesOk` は、golem-typeset が作るフローの列では常に成り立つ。
golem-typeset は、罫線つきのブロックを前の罫線を共有しないもの（`frJoined` が偽）として作る（`modules/golem-typeset/src/Golem/Typeset/Flow.hs:3845`）。
`ruledLinks` は、直前のフローが後の罫線を持つ罫線つきのブロックのときだけ共有を付け、箱の本体の中には入らない（`Flow.hs:4612`）。
golem-typeset は、箱を作ってから `ruledLinks` でブロックをつなぎ、その後で `markBookParts` が本の部を作る（`Flow.hs:4113`、`:4114`、`:4160`）。
`markBookParts` はフローを本の部で包むだけで、並びを変えない（`Flow.hs:4488`）。
そのため、共有は本の部の境をまたいでも起こるが、箱の中のブロックと箱の直後のブロックは共有しない。
定理にこの前提が要るのは、箱の終わりが使用行数を `boxEnd` まで広げるので、箱の終わりで後の罫線が待つと `Win` の残りの行数が保てないからである。
`I5_paginate_figures` は、平らにした列で箱の直後のブロックが共有しないことを前提 `BoxesOk` とし、本の部と箱の中でも同じことを求める。
`BoxesOk_shared` は、共有する二つのブロックの列がこの前提を満たすことを示す。

段組みは段数と先頭行だけを状態に持ち、段の幅と段間は持たない。
`Env` の段数は基本の段組み（`envBase`）の段数で、段組みを戻すとこの段数になる。
表は、`envKeepParts` が `KeepColumn` のときの `placeTable` と、それ以外のときの `placeTableAcross` の両方を扱う。
`placeTableAcross` は、本の部の中で末尾の行とキャプションを一つの単位に保つ分岐（`envBookPartSpan` が `Just` のとき）も扱う。
`Env` の `keepParts` は `envKeepParts` を、`inBookPart` は `envBookPartSpan` が `Just` であることを表す。
本の部の種類は自然数で表し、満たせなかった保持は `Unmet.splitBookPart` で表す。
`placeBookPart` が試した配置を選ぶ `fits` は、出力のページのスロットの id から実装のとおりに求める。
`fits` の値は定理の証明に使わないので、定理はどの選び方でも成り立つ。
表の部分の記録 `sTables` は出力の付帯情報なので、モデルには持たない。
満たせなかった制御は、出典の位置を持たない `Unmet.noBreak` と `Unmet.keepNext` で表す。
`FAdjustLines` の行数の上限（`envMaxLines`）は `Env` の `maxLines` とし、満たせなかった変更は `Unmet.adjust` で表す。
箱は、状態の `box`（`sBox`）に、id、部分の前と後の行数、段の中の部分の先頭行、部分が空の段の先頭から始まったかを持つ。
`cap` は箱の部分の後の行数を引き、`isEmpty` は空の段の先頭から始まった部分の前の行だけの段も空とみなす。
`advance` は次の段を開いた後に `openBox` で箱の部分の前の行を置く。
箱の部分の記録 `sBoxes` は出力の付帯情報なのでモデルには持たず、`closeBox` は最後の部分の後の行の位置（`boxEnd`）だけを求める。
出力の `PageOut` には、ページ番号、段番号、空白ページか、スロット、脚注、満たせなかった制御だけを持つ。
脚注と図版の行数は自然数とし、負の行数は扱わない。

次の表は、Haskell の関数と Lean の定義の対応である。
Haskell の位置は `modules/golem-layout/src/Golem/Layout/` からの相対パスと行番号で示す。

| Haskell | Lean |
| --- | --- |
| `Paginate.hs:175` `placeAll` | `placeAll` |
| `Paginate.hs:191` `step` | `step` |
| `Paginate.hs:193` `step` の `FBookPart` | `step` の `bookPart`、`runFlows` |
| `Paginate.hs:249` `needMore` | `needMore` |
| `Paginate.hs:261` `needAfterSpaces` | `needAfterSpaces` |
| `Paginate.hs:273` `needBeforeSpaces` | `needBeforeSpaces` |
| `Paginate.hs:282` `placeSpace` | `placeSpace` |
| `Paginate.hs:292` `needBeforeSpace` | `needBeforeSpace` |
| `Paginate.hs:309` `needBefore` | `needBefore` |
| `Paginate.hs:320` `waitsBehind` | `waitsBehind` |
| `Paginate.hs:327` `waitsFor` | `waitsFor` |
| `Paginate.hs:351` `placeBlank` | `placeBlank` |
| `Paginate.hs:369` `applyNeed` | `applyNeed` |
| `Paginate.hs:379` `adjustLines` | `adjustLines` |
| `Paginate.hs:393` `placeFlow` | `placeFlow`、`previousKeep` |
| `Paginate.hs:417` `placeKept` | `placeKept`、`keptCut` |
| `Paginate.hs:437` `waitFor` | `waitFor` |
| `Paginate.hs:448` `checkNoBreak` | `checkNoBreak`、`linesIn` |
| `Paginate.hs:460` `slotLineCount` | `slotLineCount` |
| `Paginate.hs:466` `applyBreaks`、`:469` `applyBreak` | `applyBreaks`、`applyPending` |
| `Paginate.hs:481` `startBefore` | `startBefore` |
| `Paginate.hs:562` `place` の `FSection` | `place` の `sectionStart` |
| `Paginate.hs:494` `applyBreakKind` | `applyBreakKind` |
| `Paginate.hs:504` `breakPage` | `breakPage` |
| `Paginate.hs:512` `place` | `place`、スペースは `placeSpaceFlow` |
| `Paginate.hs:514` `place` の `FBookPart` | `place` の `bookPart`、`runFlows` |
| `Paginate.hs:587` `place` の `FBoxed` | `place` の `boxed`、`boxEnd` |
| `Paginate.hs:564` `place` の `FSwitchColumns`、`:570` `FRestoreColumns` | `place` の `switchColumns`、`restoreColumns` |
| `Paginate.hs:602` `placeCode` | `placeCode`、`codeCount`、`codeSpanOf` |
| `Paginate.hs:628` `placeLines` | `placeLines`、`placeLinesGo`、`lineCount`、`shortParts` |
| `Paginate.hs:551` `place` の `FWrapped` | `place` の `wrapped` |
| `Paginate.hs:668` `placeStanza` | `placeStanza`、`placeStanzaGo`、`versesFitting`、`stanzaK0`、`stanzaK2`、`putVerses`、`shortVerse` |
| `Paginate.hs:715` `placeRuled` | `placeRuled`、`placeRuledFresh` |
| `Paginate.hs:746` `commitRuled`、`:759` `splitRuled`、`:775` `flushJoin` | `commitRuled`、`putRuledLines`、`splitRuled`、`flushJoin` |
| `Paginate.hs:790` `placeTable` | `placeTable`、`tableRowsGo`、`withCaption`、`putRepeated` |
| `Paginate.hs:815` `placeTableAcross` | `placeTableAcross`、`acrossGo`、`tableGroups`、`mustRepeat`、`retainsTail` |
| `Paginate/BookParts.hs:13` `placeBookPart` | `placeBookPart`、`partTrial`、`fitsPart`、`unitKey`、`emptyUnit`、`nextUnit`、`nextSpread`、`hasNested` |
| `Paginate/BookParts.hs:60` `flattenBookParts` | `flattenParts` |
| `Paginate/BookParts.hs:66` `flowSlotIds`、`:83` `slotIds` | `flowSlotIds`、`flowsSlotIds`、`slotIds` |
| `Paginate/State.hs:131` `initialState` | `initialState` |
| `Paginate/State.hs:142` `cap`、`:150` `free`、`:157` `typeAreaFree`、`:164` `isEmpty` | `cap`、`boxAfter`、`free`、`typeAreaFree`、`isEmpty`、`boxTop` |
| `Paginate/State.hs:168` `atBoxStart`、`:174` `openBox`、`:183` `closeBox` | `atBoxStart`、`openBox`、`boxEnd` |
| `Paginate/State.hs:199` `keep` | `keep` |
| `Paginate/State.hs:207` `parityStart` | `parityStart` |
| `Paginate/State.hs:213` `blankPage` | `blankPage` |
| `Paginate/State.hs:216` `putSlot` | `putSlot` |
| `Paginate/State.hs:223` `putLineKeeping` | `putLineKeeping`、`putLine` |
| `Paginate/State.hs:241` `putBlock` | `putBlock` |
| `Paginate/State.hs:263` `splitNotes` | `splitNotes` |
| `Paginate/State.hs:273` `closePage` | `closePage` |
| `Paginate/State.hs:280` `nextColumn`、`:283` `nextPage` | `nextColumn`、`nextPage` |
| `Paginate/State.hs:286` `advance` | `advance`、`advanceIn`、`advanceFresh`、`advanceTurned`、`openColumn` |
| `Paginate/State.hs:324` `startSet` | `startSet` |
| `Paginate/State.hs:350` `pageFigure` | `pageFigure` |
| `Paginate/State.hs:357` `carryNote` | `carryNote`、`carryRoom`、`carryShown` |
| `Paginate/State.hs:372` `placeDeferred` | `placeDeferred` |
| `Paginate/State.hs:381` `flushDeferred` | `flushDeferred` |
| `Paginate/State.hs:387` `flushFigures` | `flushFigures` |
| `Paginate/Decide.hs:215` `splitAtBreak` | `splitAtBreak` |
| `Paginate/Decide.hs:256` `needIn` | `needIn` |
| `Paginate/Decide.hs:263` `headingNeed` | `headingNeed` |
| `Paginate/Decide.hs:270` `tableHead` | `tableHead` |
| `Paginate/Decide.hs:294` `afterPageFigure` | `afterPageFigure` |
| `Paginate/Decide.hs:300` `startsRecto` | `startsRecto` |
| `Paginate/Decide.hs:322` `bodySize`、`:336` `joinsNext` | `RuledBody.size`、`joinsNext` |
| `Paginate/Decide.hs:346` `planOf`、`:381` `planNeed`、`:385` `planParts` | `planOf`、`Plan`、`planNeed`、`planParts` |

## 未完の項目

格子モードの改ページ全体は `Whole.lean` が扱う。
格子モードのすべてのフローについて、改ページ全体の終了と、段落、詩の行、回り込み図版の横の行、定義の項、表の行、見出し、コードの行、罫線つきのブロックの行の過不足と順序を証明した。
図版と転置図版の過不足と順序は、図版の高さと段の容量を 1 行以上、脚注区切りの行数を 0 行以上とし、箱の直後のブロックが罫線の領域を共有しない（`BoxesOk`）前提の下で証明した。
[root ADR 0352](../../docs/adr/0352-prove-pagination-in-lean.md) の完了の条件のうち、残るのは次の四つである。

一つ目は、境界入力の表のうち、キャプションの行の Lean の側の照合である。
`modules/golem-layout/test/PaginateSpec.hs` の `boundaryTableTests` は、空の原稿と一行の原稿、容量 1〜3 行の段の段落、空の段にちょうど収まる図版と一行高い図版、図版を一〜三つ含む原稿について、Haskell の実装の終了、行と図版を原稿順に一度ずつ置くこと、空の段を残さないことを確かめる。
同じ表は、見出し、`need-lines`、`no-break`、行数を指定した `no-break`、`keep-with-next` を段落の間に置いた原稿についても、終了と、段落と見出しの行を原稿順に一度ずつ置くことを確かめる。
この原稿は、1〜5 行の段落、一行の見出し、2 行か 3 行の `need-lines`、`no-break`、3 行の `no-break`、1 行か 2 行の `keep-with-next` から一〜三つを並べ、最後に 1〜3 行の段落を置いたもので、段の容量は 2〜4 行である。
`Boundary.lean` は、これらの 20806 個の入力を `Whole.lean` の `paginate` で評価し、ページ、段、スロットとその格子の行、満たせなかった指定を `#eval` で書き出す。
`Env` は `paginate 1` の容量ごとの `Env` で、その引数は `Decide.hs` の `nextNeed`、`keptNeed`、`keepAhead`、`nextFirstLines`、`fitting`、`roomForLine` を写した関数である（`boundaryEnv`）。
`check.sh` は、`Whole.lean` を `.olean` にして `Boundary.lean` を評価し、`Boundary.hs` が golem-layout の `paginate` に同じ入力を渡した出力と `diff` で比べる。
二つの出力は一致した。
`keep` などは整礎再帰で定義しているので、カーネルの簡約による `decide` ではなく、コンパイルした評価で比べ、`native_decide` は使わない。
`Boundary.lean` は証明ではなく評価のためのファイルなので、`Decide.hs` を写した関数に `partial` を使う。

この照合は、`boundaryEnv` の引数の写しの誤りを検出する。
`boundaryEnv` の引数を一つずつ替えると、食い違う入力の数は次のとおりだった。
`nextNeed` を何も求めない関数にすると 888 個、`keptNeed` を常に `none` にすると 802 個、`nextFirst` を常に 1 行にすると 148 個、`keepLast` を常に 0 行にすると 276 個、`fitting` を常に 1 行にすると 19701 個、`roomForLine` を常に偽にすると 1109 個である。
`keepNextLines` は罫線つきのブロックの配置にだけ使うので、罫線つきのブロックを含まないこの表では替えても出力は変わらない。

境界入力の照合には、二つのことが残る。
表のキャプションの行（改行位置の前後に一文字足す、画像に残る行が一行かゼロ行、キャプションが一行超過）は、golem-driver の `FigureSpec.hs` がキャプションを改行して図版を縮小して確かめるので、Lean の側の照合は二つ目の条件の評価関数を待つ。
また、箱、表、コード、罫線つきのブロック、詩、回り込み図版、脚注を含む入力は、まだ照合していない。

二つ目は、キャプションの評価値と幅の計算の Haskell との対応である。
`Pagination.lean` は、改行候補の選択、改行列からの行の組み立て、占有行数の計算を、評価値と幅を引数として証明する（`I1_caption_*`）。
評価値（デメリット、fitness）と、累積した幅の計算そのものが Haskell の改行器と同じであることは、まだ示していない。
計画は、`CheckCaptionAssembly.hs` が改行器を呼ぶ入力ごとに、候補の評価値と累積の幅を書き出し、Lean に写した評価関数が同じ値を返すことを `CaptionExamples.lean` で確かめることである。
評価関数の整数の丸めは golem-layout の `Golem.Layout.KnuthPlass` の式をそのまま Lean に写し、実フォントの送りは golem-driver の `FigureSpec.hs` が使う計測値を記録して渡す。
そのうえで、写した評価関数を `I1_caption_*` の引数に入れ、不変条件 1 と 2 を具体的な評価関数について結ぶ。

三つ目は、[root ADR 0397](https://github.com/tett23/golem/blob/7fc360ff641d7eea6e8ee3ace30eca26e545334b/docs/adr/0397-paragraph-line-pitch-and-dimensional-spacing.md) の自由な配置の状態遷移である。
自由な配置は `Paginate/Physical.hs` が `Sp` の寸法で行い、図版の回り込みを実際の段の位置で改行し直す経路も持つ。
整数行の `Whole.lean` を、この経路の証明とは扱わない。
計画は、`Physical.lean` に `Physical.hs` の状態（`PhysicalState`）と、その `placeRuled`、`placeRuledKeeping`、`flushPendingRule` を含む各フローの配置を、寸法を整数として写すことである。
終了は、残りのフローの重さと、段を進めるたびに減る尺度で示し、内容の過不足と順序は `Whole.lean` と同じく、出力済み、段の中、待機中をつないだ列の不変条件で示す。
回り込みの改行し直しは、改行器を引数とし、改行した行の id が原稿の行の id と同じ列であることを前提に置く。

四つ目は、[root ADR 0398](https://github.com/tett23/golem/blob/0d20d3e2e445d69aa576ec97615a51c31114ceec/docs/adr/0398-styled-separators-in-manuscripts.md) の区切りである。
`USeparator` からのフロー生成と、区切りを後続行と保持できなければ G07134 を返す後処理は、まだ証明していない。
計画は、フロー生成を区切りの行を段落のフローに変える関数として `Whole.lean` の `Flow` の上に写し、生成したフローに I4 と I5 の定理をそのまま当てることである。
後処理は出力のページを変えず診断だけを足す関数として写し、区切りの行とその後続行が別の段に分かれるときに限って G07134 を返すことと、ページの内容を変えないことを証明する。

これらを終えるまで Alloy の定期実行と既存の参照を維持する。

## 検査の手順

手元では次のコマンドで Lean 4.7.0 の証明を検査する。

```sh
lean experiments/pagination-proof/Pagination.lean
lean experiments/pagination-proof/Whole.lean
cabal build golem-layout
sh experiments/pagination-proof/check.sh
```

`check.sh` は境界入力の照合で `cabal exec` から `runghc` を呼ぶので、先に golem-layout をビルドしておく。

書き写しの有限の照合は、`Pagination.olean` を作ってから `LEAN_PATH` に置いて `EnumerateSmall.lean` を実行する。

```sh
work=$(mktemp -d)
lean -o "$work/Pagination.olean" experiments/pagination-proof/Pagination.lean
LEAN_PATH="$work" lean experiments/pagination-proof/EnumerateSmall.lean
rm -rf "$work"
```

入力の数を出す 2 行（18099 と 66744）を除く 6 個の一覧がすべて空なら、照合は通る。

ライブラリをビルドした後、実装の改行結果を Lean に渡して照合する。
次のコマンドでは、現在の `golem-layout` のローカルのパッケージを明示し、別にインストール済みの同名パッケージとの混同を避ける。

```sh
work=$(mktemp -d)
lean -o "$work/Pagination.olean" experiments/pagination-proof/Pagination.lean
cabal exec -- runghc -hide-all-packages -package=base -package=text \
  -package-id=golem-layout-0.1.0-inplace \
  experiments/pagination-proof/CheckCaptionAssembly.hs --lean > "$work/CaptionExamples.lean"
LEAN_PATH="$work" lean "$work/CaptionExamples.lean"
rm -rf "$work"
```

`check-alloy-witnesses.sh` は、この文書で Alloy に固定して確かめた 25 の具体例をすべて実行する。
Alloy CLI を用意して次のコマンドで照合する。

```sh
sh experiments/pagination-proof/check-alloy-witnesses.sh
```

書き写しと元の述語の突き合わせは、Alloy CLI を用意して次のコマンドで行う。
引数は項目 3〜4 個の入力を選ぶ間隔で、既定は 97 である。

```sh
sh experiments/pagination-proof/check-alloy-diff.sh 97
```
