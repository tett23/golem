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
`Text` は本文で、段落の行の `Line`、見出しの `Heading`、スペースの `Space` からなる。
`Recto` は改丁見出しで、`Heading` の一種である。
`Figure` は図版、`Blank` は行アキ、`Need` は `need-lines` である。
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

`relaxedAfterHeadings` の代表入力（容量 3 行、見出し 1 行と 3 行段落）を Golem に渡すと、最初の段には見出しと本文 2 行が置かれ、残る本文 1 行は次の段に置かれる。
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

`keepNone` は、行アキがなく容量 1 行以上で図版が段に収まる入力で、段落の最初の行を含む任意の行位置列と任意の keep 指定について、`blankRules25` の配置が keep 指定を満たすことを示す。
Lean では、本文を置かない場合に分割を生じさせず、空段に最初の本文行を置く場合に分割された段落が段頭で始まることを証明する。
段落に属する行の選択と順位の対応は、上の二つの定理が示す。

`needSpaceAllButGreedy` は、容量 4 行の段を 2 行使ったところに `@need-lines 2` と見出し 3 個が続き、後ろの 2 個が改丁見出しである入力で、規則が両立しないことを示す。
P7 は最初の見出しをこの段に求める。
段はすでに使っているため、旧 `keepHeading21` は続く改丁見出しも同じ段に求める。
残り 2 行に見出し 3 個は収まらない。
Lean で本文の区切り 4 通りのすべてについてこの衝突を証明し、元の Alloy 述語に同じ原稿と 4 配置を固定して反例を確認した。
固定を外した元のコマンドでも、SAT4J は容量 4 行、使用済み 2 行、見出し 3 個の反例を返した。
Golem は改丁見出しの手前で見出し列を切り、三つの見出しを 1、3、5 ページ目に置いた。

`needMore27` は、容量 3 行、使用済み 1 行、`need-lines` 1 行、スペース 1 行、`need-lines` 3 行、段落 1 行の入力で旧 P7 と P1 を同時に満たす配置がないことを示す。
Alloy でも同じ入力と配置 3 通りを固定して解を確認した。

`needMoreSome` は、`needMore27` と同じ原稿を容量 4 行の段に置き、新 P7 が両方の `need-lines` を満たす証人を示す。
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
`need-lines` と次の本文との間のスペースが区切りをまたいでも、使用済み行数、先に置いたスペース以外の本文、置いた図版の高さを数える `placedBefore` の値は変わらない。

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

`needMoreSome` と `needSpaceSome` の入力は、実装との照合のため [PaginateSpec](../../modules/golem-layout/test/PaginateSpec.hs) に追加した。
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
`I4_flush_figures` は、待機図版がなくなった時点で改段を止め、出した図版が元の待機図版の列に一致することを示す。
待機図版がなければ状態を変えず、残る脚注を次の本文の配置に渡すことは、`I5_flush_figures_keeps_pending_notes` が示す。

この証明の基にした Haskell の `Flow` 22 種は、通常図版、転置図版、箱と、それ以外の 19 種に分けられる。
`MeasuredFlow.events` は、図版の前後と箱の出入りで実行した本文の操作を受け取り、操作ごとに更新した状態で次の図版の配置条件を計る。
図版の前の改ページを実行してから、待機中の図版の有無、段番号、本文と脚注の使用行数で `waitsBehind` を判定する。
待機する図版は直前の指定行数や行アキを消費しない。
`I5_all_measured_flows_eof` はその実行列について、入れ子の箱と原稿末尾の処理を含めて図版が原稿順に一度ずつ出ることを示す。
`MeasuredFlow` は本文の操作列を引数として受け取り、操作列を Haskell の `step` から作るモデルは「格子モードの改ページ全体のモデル」の節の `Whole.lean` にある。
今の `FlowAt` には、この 22 種のほかに `FNoBreakLines` と `FBookPart` があり、この 2 種は `MeasuredFlow` に含めず、`Whole.lean` の `Flow` で扱う。
[root ADR 0398](https://github.com/tett23/golem/blob/0d20d3e2e445d69aa576ec97615a51c31114ceec/docs/adr/0398-styled-separators-in-manuscripts.md) で加わった `USeparator` からのフロー生成と G07134 を返す後処理は、「区切りのモデル」の節で扱う。

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
`alloy_noneMeetsAllButGreedy` は、図版が高々一つでどの図版も段の容量以下の高さを持ち、行アキとスペースと `need-lines` のない任意の入力で、容量が 1 行以上かつ使用済み行数が容量以下なら、詰める規則のほかの 7 規則を同時に満たす配置があることを示す。
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
`alloy_heading_placement_meets` は、図版が高々一つでどの図版も段の容量以下の高さを持ち、行アキとスペースと `need-lines` のない任意の入力で、容量が 2 行以上かつ使用済み行数が容量以下なら、この配置が第 2 群のすべての規則を満たすことを示す。
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
`alloy_placement26_meets` は、図版が高々二つでどの図版も段の容量以下の高さを持ち、スペースと `need-lines` のない任意の入力で、容量が 1 行以上かつ使用済み行数が容量以下なら、この配置が `base26`、行アキの規則、孤立行、寡婦行、見出しの規則を満たすことを示す。
次のブロックの規則は、[golem-layout ADR 0026](../../docs/golem-layout/adr/0026-need-lines-and-blank-lines-pass-over-waiting-figures.md) の `nextOf` でも、それ以前の `nextOf25` でもよい。
`alloy_waitingBlankAllButGreedy`、`alloy_blankRules25`、`alloy_blankFigureOrder` はこの定理から導き、`Alloy.I3_waitingBlankNone` は最初のものから導く。
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
同じページの次の段へ進むときは、待つ内容が増えず、残りの段数が一つ減る。
行数の縮みの項（`adjustRank`）は、組の段がそろって縮むとき（`setAdjust` が負）は残りの段数に 2 を足した値、その段だけが縮むときは 1、縮まないときは 0 である。
[root ADR 0441](https://github.com/tett23/golem/blob/7e332092be2f3b7523faaa09d73a7e657f2ca27d/docs/adr/0441-index-columns-on-a-page-with-adjusted-lines.md) の後は、同じページの次の段は組の縮み（`sSetAdjust`）を受け継ぐので、組の段がそろって縮むときは次の段も縮むが、この項が残りの段数の分だけ減る。
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
前提は四つで、原稿のどの図版も、本の部と箱の中の図版も高さが 1 行以上であること、本の部と箱の中を含めて箱の直後のブロックが待っている後の罫線と領域を共有せず、罫線つきの見出しが 1 行以上を持つこと（`BoxesOk`）、段の容量が 1 行以上であること、脚注区切りの行数が 0 行以上であることである。
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
`adjustLines` は使用行数、脚注の行数、スロットを変えないからである。
`adjustLines` の後の `drainPendingNotes` は、繰り越す脚注を段に移して脚注の行数を増やすだけで、スロットと使用行数を変えない（`drainPendingNotes_eq`）。

段組みを切り替える `FSwitchColumns` は、版面の終わりと前の段の脚注の上のどちらか早いほうまでの行（`typeAreaFree`）が残るときだけ、同じページで新しい組を始める。
新しい組の段は、前の段の行数の変更と脚注の行数の小さいほうを行数の変更とし（`startSet` の `adjust` と `setAdjust`）、同じページの後の段もそれを受け継ぐ。
この終わりは [root ADR 0441](https://github.com/tett23/golem/blob/7e332092be2f3b7523faaa09d73a7e657f2ca27d/docs/adr/0441-index-columns-on-a-page-with-adjusted-lines.md) が決めたもので、`FAdjustLines` が足した行は数えず、引いた行は数える。
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
段落が最後の行を保つ相手の行数（`Decide.hs:127` の `keptNeed`）、先の制御が求める最後の行数（`Decide.hs:152` の `keepAhead` の 2 番目の値、制御がなければ 0）、次の部分の最初の行数（`Decide.hs:215` の `nextFirstLines`）の三つである。
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
golem-typeset は、罫線つきのブロックを前の罫線を共有しないもの（`frJoined` が偽）として作る（`modules/golem-typeset/src/Golem/Typeset/Flow.hs:3944`）。
`ruledLinks` は、直前のフローが後の罫線を持つ罫線つきのブロックのときだけ共有を付け、箱の本体の中には入らない（`Flow.hs:4712`）。
golem-typeset は、箱を作ってから `ruledLinks` でブロックをつなぎ、その後で `markBookParts` が本の部を作る（`Flow.hs:4213`、`:4214`、`:4260`）。
`markBookParts` はフローを本の部で包むだけで、並びを変えない（`Flow.hs:4588`）。
そのため、共有は本の部の境をまたいでも起こるが、箱の中のブロックと箱の直後のブロックは共有しない。
定理にこの前提が要るのは、箱の終わりが使用行数を `boxEnd` まで広げるので、箱の終わりで後の罫線が待つと `Win` の残りの行数が保てないからである。
`I5_paginate_figures` は、平らにした列で箱の直後のブロックが共有しないことを前提 `BoxesOk` とし、本の部と箱の中でも同じことを求める。
`BoxesOk` は、罫線つきの見出しが 1 行以上を持つことも求める（「置いた罫線の位置」の節の `I3_waiting_used`）。
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
満たせなかった `no-break` は出典の位置を持たない `Unmet.noBreak` で表し、満たせなかった `keep-with-next` は位置の id を持つ `Unmet.keepNext` で表す。
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
| `Paginate.hs:185` `placeAll` | `placeAll` |
| `Paginate.hs:201` `step` | `step` |
| `Paginate.hs:203` `step` の `FBookPart` | `step` の `bookPart`、`runFlows` |
| `Paginate.hs:260` `needMore` | `needMore` |
| `Paginate.hs:272` `needAfterSpaces` | `needAfterSpaces` |
| `Paginate.hs:284` `needBeforeSpaces` | `needBeforeSpaces` |
| `Paginate.hs:293` `placeSpace` | `placeSpace` |
| `Paginate.hs:303` `needBeforeSpace` | `needBeforeSpace` |
| `Paginate.hs:320` `needBefore` | `needBefore` |
| `Paginate.hs:331` `waitsBehind` | `waitsBehind` |
| `Paginate.hs:338` `waitsFor` | `waitsFor` |
| `Paginate.hs:362` `placeBlank` | `placeBlank` |
| `Paginate.hs:380` `applyNeed` | `applyNeed` |
| `Paginate.hs:390` `adjustLines` | `adjustLines` |
| `Paginate.hs:404` `placeFlow` | `placeFlow`、`previousKeep` |
| `Paginate.hs:428` `placeKept` | `placeKept`、`keptCut` |
| `Paginate.hs:448` `waitFor` | `waitFor` |
| `Paginate.hs:459` `checkNoBreak` | `checkNoBreak`、`linesIn` |
| `Paginate.hs:471` `slotLineCount` | `slotLineCount` |
| `Paginate.hs:477` `applyBreaks`、`:480` `applyBreak` | `applyBreaks`、`applyPending` |
| `Paginate.hs:492` `startBefore` | `startBefore` |
| `Paginate.hs:574` `place` の `FSection` | `place` の `sectionStart` |
| `Paginate.hs:505` `applyBreakKind` | `applyBreakKind` |
| `Paginate.hs:515` `breakPage` | `breakPage` |
| `Paginate.hs:523` `place` | `place`、スペースは `placeSpaceFlow` |
| `Paginate.hs:525` `place` の `FBookPart` | `place` の `bookPart`、`runFlows` |
| `Paginate.hs:601` `place` の `FBoxed` | `place` の `boxed`、`boxEnd` |
| `Paginate.hs:576` `place` の `FSwitchColumns`、`:582` `FRestoreColumns` | `place` の `switchColumns`、`restoreColumns` |
| `Paginate.hs:616` `placeCode` | `placeCode`、`codeCount`、`codeSpanOf` |
| `Paginate.hs:642` `placeLines` | `placeLines`、`placeLinesGo`、`lineCount`、`shortParts` |
| `Paginate.hs:562` `place` の `FWrapped` | `place` の `wrapped` |
| `Paginate.hs:682` `placeStanza` | `placeStanza`、`placeStanzaGo`、`versesFitting`、`stanzaK0`、`stanzaK2`、`putVerses`、`shortVerse` |
| `Paginate.hs:729` `placeRuled`、`:768` `settleRuled`、`:781` `settlesAfter` | `placeRuled`、`placeRuledFresh`、`settleJoined`、`unjoined`、`settleRuled`、`settlesOn`、`settlesAfter` |
| `Paginate.hs:791` `commitRuled`、`:804` `splitRuled`、`:820` `flushJoin`、`:826` `ownAfter` | `commitRuled`、`putRuledLines`、`splitRuled`、`flushJoin`、`ownArea`、`ownFits` |
| `Paginate.hs:841` `placeTable` | `placeTable`、`tableRowsGo`、`withCaption`、`putRepeated` |
| `Paginate.hs:866` `placeTableAcross` | `placeTableAcross`、`acrossGo`、`tableGroups`、`mustRepeat`、`retainsTail` |
| `Paginate/BookParts.hs:13` `placeBookPart` | `placeBookPart`、`partTrial`、`fitsPart`、`unitKey`、`emptyUnit`、`nextUnit`、`nextSpread`、`hasNested` |
| `Paginate/BookParts.hs:60` `flattenBookParts` | `flattenParts` |
| `Paginate/BookParts.hs:66` `flowSlotIds`、`:83` `slotIds` | `flowSlotIds`、`flowsSlotIds`、`slotIds` |
| `Paginate/State.hs:142` `initialState` | `initialState` |
| `Paginate/State.hs:152` `cap`、`:160` `free`、`:168` `typeAreaFree`、`:175` `isEmpty` | `cap`、`boxAfter`、`free`、`typeAreaFree`、`isEmpty`、`boxTop` |
| `Paginate/State.hs:187` `atBoxStart`、`:193` `openBox`、`:202` `closeBox` | `atBoxStart`、`openBox`、`boxEnd` |
| `Paginate/State.hs:218` `keep` | `keep` |
| `Paginate/State.hs:226` `parityStart` | `parityStart` |
| `Paginate/State.hs:232` `blankPage` | `blankPage` |
| `Paginate/State.hs:235` `putSlot` | `putSlot` |
| `Paginate/State.hs:242` `putLineKeeping` | `putLineKeeping`、`putLine` |
| `Paginate/State.hs:260` `putBlock` | `putBlock` |
| `Paginate/State.hs:282` `splitNotes` | `splitNotes` |
| `Paginate/State.hs:292` `closePage` | `closePage` |
| `Paginate/State.hs:299` `nextColumn`、`:302` `nextPage` | `nextColumn`、`nextPage` |
| `Paginate/State.hs:305` `advance` | `advance`、`advanceIn`、`advanceFresh`、`advanceTurned`、`openColumn` |
| `Paginate/State.hs:347` `startSet` | `startSet` |
| `Paginate/State.hs:375` `pageFigure` | `pageFigure` |
| `Paginate/State.hs:382` `carryNote` | `carryNote`、`carryRoom`、`carryShown` |
| `Paginate/State.hs:431` `placeDeferred` | `placeDeferred` |
| `Paginate/State.hs:440` `flushDeferred` | `flushDeferred` |
| `Paginate/State.hs:446` `flushFigures` | `flushFigures` |
| `Paginate/Decide.hs:244` `splitAtBreak` | `splitAtBreak` |
| `Paginate/Decide.hs:285` `needIn` | `needIn` |
| `Paginate/Decide.hs:292` `headingNeed` | `headingNeed` |
| `Paginate/Decide.hs:299` `tableHead` | `tableHead` |
| `Paginate/Decide.hs:323` `afterPageFigure` | `afterPageFigure` |
| `Paginate/Decide.hs:329` `startsRecto` | `startsRecto` |
| `Paginate/Decide.hs:351` `bodySize`、`:365` `joinsNext` | `RuledBody.size`、`joinsNext` |
| `Paginate/Decide.hs:375` `planOf`、`:410` `planNeed`、`:414` `planParts` | `planOf`、`Plan`、`planNeed`、`planParts` |

## 区切りのモデル

`Separator.lean` は、[root ADR 0398](https://github.com/tett23/golem/blob/0d20d3e2e445d69aa576ec97615a51c31114ceec/docs/adr/0398-styled-separators-in-manuscripts.md) の区切りを扱う golem-typeset の四つの関数と、`round'` が診断を足す処理を、`Whole.lean` の `Flow` の上に写したものである。
`space` は、`blocks` の局所関数 `spaceSeparators`（`modules/golem-typeset/src/Golem/Typeset/Flow.hs:2515`）の `go` を写す。
この関数は、可視の区切りの後に 1 行の `keep-with-next` を足し、区切りとの境界の行アキを一つのアキに置き換える。
足す `keep-with-next` は区切りの位置を持つ（`Flow.hs:2547`）。
`holdNeeds` は、`space` の後に働く `holdSeparatorNeeds`（`Flow.hs:2477`）を写す。
区切りの保持は、可視の区切りから、区切り、アキ、行アキ、`keep-with-next`、`UPageControl` が続くあいだの単位の列である（`inHold`）。
この関数は、区切りの保持に `@need-lines` があると、保持の最初の区切りの前に `@need-lines` を一つ足す。
足す `@need-lines` の行数は、保持の中の各 `@need-lines` について、保持の前の行アキと保持の中でそれより前の行数に、その行数を足したものの最大で、段の行数を超えない。
PR #1141 の後、この関数は、保持の中でそれより前の行数と合わせると段の行数を超える `@need-lines` を `UHeldNeedLines` に変え、フローを作らずに G07037 で報告する。
`settleHolds` はこの置き換えを写し、足す `@need-lines` を決めた後の単位の列で、そのような保持の中の `@need-lines` をフローのない単位に変える。
保持の前の行アキは、この判定では数えない。
`reported` は、`unmetWarnings`（`Flow.hs:1027`）が区切りの位置の満たせなかった `@need-lines` と `keep-with-next` を報告しない処理（`Flow.hs:1038`、`Flow.hs:1041`）を写す。
`Whole.lean` の `Unmet` のうち `needLines` は位置を持たないので、`reported` は位置を `Unmet` と組にして受け取る。
`holdErrors` は、`separatorHoldErrors`（`Flow.hs:795`）を写す。
この関数は、組んだページを読み、区切りの連続と後続ブロックの最初の行が一つの段にない連続ごとに G07134 を返す。
`postProcess` は、`round'`（`Flow.hs:751`）がこの診断を足す処理を写し、ページをそのまま返して、受け取った診断の後に G07134 を足す。

単位（`Unit`）は、可視の区切り、行アキ、改ページ、アキ、`keep-with-next` と、それ以外の単位からなる。
可視の区切りは、前後の格子の行数と 1 行の行を持ち、段落のフロー（`Flow.hs:3954`）になる。
種類が `blank` の区切りは、単位を作る前に行アキへ解決される（`modules/golem-driver/src/Golem/Driver.hs:404`）ので、行アキとして表す。
アキ（`UGap`）は `FSpace` になり、格子の行へは `paginateBuilt` の `gridUnits`（`Flow.hs:841`）が行送りで割って渡す。
それ以外の単位は、フロー、区切りの連続を終えるか通すか切るか（`Role`）、最初の行の id を引数として持つ。
`separatorHoldErrors` は、`UBreak`、`USection`、`UColumns` で連続を切り、`UGap`、`UBlank`、`UKeepNext`、`UPageControl` を通し、ほかの単位では最初の行を持つときだけ連続を終える（`Flow.hs:812`〜`:826`）。
モデルでは、`USection` と `UColumns` を `reset`、`UPageControl` を `pass`、ほかを `block` の役とする。
定理はこれらの引数のどの選び方でも成り立つ。

区切りの保持の位置は、格子モードの `Whole.lean` と自由な配置の `Physical.lean`（「自由な配置のモデル」の節）の二つの改ページのモデルに `Env` の引数 `held` として渡す。
golem-typeset は可視の区切りの位置の集合（`separatorSpans`、`Flow.hs:829`）を golem-layout の `paginateHeld` と `PhysicalSettings` の `physicalHeld` に渡す（`Flow.hs:835`、`:862`）。
モデルでは、位置を行の id で表す。
`Whole.lean` と `Physical.lean` の `keepNext` のフローと満たせなかった `keepNext` は位置の id を持ち、`space` は区切りの後の `keep-with-next` に区切りの行の id を付ける（`keepOf`、`holdOf`）。
`heldHere`（`modules/golem-layout/src/Golem/Layout/Paginate/State.hs:183` と `Paginate/Physical.hs:935`）は、`held` に入る位置の `keep-with-next` が今の段で待っているかを返す。
格子モードの `placeKept`（`Paginate.hs:442`）と自由な配置の `placeWithNext` と `placeStanzaWithNext`（`Paginate/Physical.hs:912`、`:926`）は、保持が待つ段から後続のブロックを自分の指定のために送らず、空の段からと同じに置く。
格子モードでは、`Boundary.lean` の `holds` と `chained` が `Decide.hs` の `holds`（`Decide.hs:135`）と `chainedHeld`（`Decide.hs:197`）を写す。
保持の後のブロックの全体の後に `@no-page-break` が続くと、`keptNeed` はその `@no-page-break` が保つ後の最初の部分も区切りに求める。
`held` は `Env` の引数なので、`Whole.lean`、`Physical.lean`、`Separator.lean` の定理は `held` のどの値でも成り立つ。
`Boundary.lean` と `PhysicalBoundary.lean` は `held` を空にし、`SeparatorBoundary.lean` は単位の可視の区切りの行の id を渡す。

不変条件 4 と 5 は、`Whole.lean` の定理をそのまま当てて導いた。
`separatorFlows` は段の行数を引数に取り、定理では `env.capacity` を渡す。
`I4_separator_paginate_ends` は、`separatorFlows` が作るフローの改ページが終わることを `I4_paginate_ends` から示す。
`I5_separator_text` は、ページの行と見出しが、可視の区切りの行とほかの単位の行を原稿順に一度ずつ並べた列（`unitsText`）に等しいことを `I5_paginate_text` から示す。
`space` が足す `keep-with-next`、アキ、行アキと、除く行アキは行を持たないので、`space_text` がこの列を保つ。
`holdNeeds` が足す `@need-lines` も行を持たないので、`holdNeeds_text` がこの列を保つ。
`I5_separator_figures` は、図版と転置図版が原稿順に一度ずつ出ることを `I5_paginate_figures` から示す。
その前提は、区切り、行アキ、改ページ、アキ、`keep-with-next` を除いたほかの単位のフロー（`otherFlows`）についての `figureOk` と、そのフローから `need-lines` を除いた列（`dropNeeds`）についての `BoxesOk` である。
`settleHolds` が `need-lines` を除くと箱と罫線つきのブロックが隣り合うことがあるので、`BoxesOk` は `need-lines` を除いた列に置く。
`space` と `holdNeeds` と `settleHolds` が作るフローは、`need-lines` を除いたこのフローの間に、段落、行アキ、スペース、`keep-with-next`、改ページ、`need-lines` のフロー（`plainFlow`）を挟んだものである（`holdFlows_ins`、`Del`、`Ins.dropNeeds`、`separatorFlows_ins`）。
`boxesOk_ins` と `figureOk_ins` は、そのようなフローを挟んでも二つの前提が保たれることを示す。
実際のフローでは、`ruledLinks`（`Flow.hs:4712`）が直前のフローが罫線つきのブロックのときだけ共有を付けるので、共有するブロックの直前には `otherFlows` でも罫線つきのブロックがあり、箱は来ない。
golem-typeset が単位のフローの後に行う `joinBoxes`（`Flow.hs:4007`）、`ruledLinks`（`Flow.hs:4712`）、`markBookParts`（`Flow.hs:4588`）は、`SeparatorBlocks.lean` に写した。
ここまでの定理は、この三つを通さないフローについて述べる。
`SeparatorBoundary.lean` は、格子モードでもこの三つを通したフローを評価する。
段落だけの原稿では、三つを通しても出力は変わらなかった。

三つを通したフローにも、不変条件 4 と 5 を当てた。
`Nested` は、フローの列を足し合わせて読み、箱と本の部はその中のフローで読み、罫線つきのブロックは領域を共有するかによらず同じに読む関数の性質である。
`Nested.blockFlows_eq` は、そのような関数が三つを通したフローと単位のフローに同じ値を返すことを示す。
三つは、箱の中身をつなぎ、罫線の共有の印を付け替え、項目のフローを本の部に包むだけで、行も図版も足さず、除かず、並べ替えないからである。
`I4_blocks_paginate_ends` と `I5_blocks_text` は、三つを通したフローの改ページが終わり、ページの行が `unitsText` に等しいことを、`I4_paginate_ends` と `I5_paginate_text` から示す。
`I5_blocks_figures` は、図版と転置図版が原稿順に一度ずつ出ることを `I5_paginate_figures` から示し、その前提の `figureOk` と `BoxesOk` は三つを通したフローについて置く。

自由な配置の区切りは、`SeparatorPhysical.lean` に写した。
このファイルは、`Separator.lean` が作る `Whole.lean` のフローを、`Physical.lean` の sp のフローに写す。
アキと箱の前後の行数には行送りを掛け（`Flow.hs:2541`、`Flow.hs:3781`、`Flow.hs:3964`）、罫線には `ruleSide`（`Flow.hs:3620`）の寸法を持たせる。
G07134 は、`Physical.lean` のページの上で同じ規則（`Flow.hs:795`）で判定する。
`textOf` と `figsOf` は、格子モードのフローを sp のフローに写し、その行と図版を `Physical.lean` の `sourceText` と `sourceFigs` で読む。
どちらも `Nested` を満たす（`textOf_nested`、`figsOf_nested`）ので、`Separator.lean` の生成と三つの変換は、写したフローの行と図版を変えない。
`I4_free_paginate_ends` は、写したフローの `paginatePhysical` が終わることを示す。
`I5_free_text` と `I5_free_figures` は、`paginatePhysical` がページを返すとき、ページの行と図版が単位のフローを写したものの行と図版に等しく、原稿順に一度ずつ並ぶことを、`Physical.lean` の `I5_paginate_text` と `I5_paginate_figures` から示す。
三つを通したフローについても、`I4_free_blocks_paginate_ends`、`I5_free_blocks_text`、`I5_free_blocks_figures` が同じことを示す。
`flow` は照合の原稿に現れないフローを写さないので、これらの定理の行と図版は、写したフローが運ぶものに限る。

区切りの保持は、生成と後処理の二つの性質として示した。
`I3_separator_keeps` は、可視の区切りの後に行アキと、行アキでも改ページでもない単位が続くと、`space` が区切りの行、1 行の `keep-with-next`、アキ、その単位をこの順に置くことを示す。
`I5_separator_post_keeps_pages` は、後処理がページを変えず、受け取った診断の後に診断を足すだけであることを示す。
`I3_separator_error_iff` は、ある連続で G07134 を返すのは、連続の区切りの行と後続ブロックの最初の行のうち、置いた二つが異なる段にあるときに限ることを示す。
`I3_separator_error_single` は、区切り一つと、連続を通す単位と、ブロック一つの原稿について、区切りの行と最初の行をどちらも置いたとき、二つの段が異なるときに限って G07134 を返すことを示す。
`hoisted_need` は、保持に `@need-lines` があるときに限って `holdNeeds` が `@need-lines` を足し、その行数が段の行数以下で、保持の中の各 `@need-lines` について、その行数に保持の前の行アキと保持の中でそれより前の行数を足した値か段の行数の小さいほう以上であることを示す（`wants`）。
`reported_iff` は、区切りの位置の満たせなかった `@need-lines` と `keep-with-next` を報告せず、ほかの満たせなかった指定をすべて報告に回すことを示す。

境界入力の照合は、`SeparatorBoundary.hs` と `SeparatorBoundary.lean` で行う。
`SeparatorBoundary.hs` は、golem-driver のテストの偽のフォント（`modules/golem-driver/test/Support.hs`）で原稿を golem-typeset の `layoutPdf` に渡し、ページか、診断の一覧を書き出す。
原稿は、なしか 1 行の段落の後に、`---`、`@separator scene`、種類が `blank` の `@separator gap`、`@blank-line 1`、`@page-break`、`@need-lines 2`、1 行の段落から一つ〜三つを並べ、最後になしか 1 行か 2 行の段落を置いたもので、可視の区切りを一つ以上含む。
`default` と `scene` の前後の行数は、0 と 0 と 1 と 2、または 1 と 1 と 2 と 0 の二組で、段の容量は 1〜3 行である。
`SeparatorBoundary.lean` は、同じ 8784 個の原稿を単位にし、`separatorFlows` に `joinBoxes`、`ruledLinks`、`markBookParts` を通したフロー（`flowsOf`）を `paginate` に渡す。
環境は、`Boundary.lean` の `boundaryEnv` に罫線の領域と可視の区切りの位置（`held`）を足した `blockEnv` である。
`holdErrors` が空ならページを、空でなければ各連続の最初の区切りの行の id を書き出す。
原稿から単位を作る前に、golem-eval の `collapseBlankLines`、golem-assemble の `ineffectiveBlankLines` と `blankLinesOverPage` が行アキをまとめたり除いたりするので、`SeparatorBoundary.lean` はこの三つを `collapse`、`effective`、`overPage` として写した。
出力のない段で満たせなかった指定は、`paginateWithin`（`Paginate.hs:145`）と同じく最後のページに付ける。
`check.sh` は二つの出力を `diff` で比べ、すべて一致した。

照合の感度は、写した処理を一つずつ替えて確かめた。
区切りの後に `keep-with-next` を足さないと 1272 個、区切りの後のアキを行アキにすると 698 個、前の区切りの後の行数を見ないと 1076 個、明示した行アキを見ないと 272 個、区切りの前の行数を見ないと 2746 個、区切りの前の行数があっても境界を可視としないと 2696 個、`beforeOf` を常に 0 にすると 2782 個の入力で出力が食い違った。
後処理では、`@need-lines` で連続を切ると 689 個、連続の id から後続ブロックの最初の行を除くと 2977 個の入力で出力が食い違った。
`holdNeeds` では、保持の中の `@need-lines` を見ないで何も足さないと 33 個、足す行数を段の行数で抑えないと 482 個の入力で出力が食い違った。
見ないときに食い違う 33 個のうち 7 個は、golem-typeset がページを返す入力で、Lean の側だけが G07134 を返した。
保持の前の行アキを数えない変更は、この入力では出力が変わらない。
原稿の末尾で区切りの後の行アキを残す変更と、改ページの前の行アキを除く変更は、この入力では出力が変わらない。
golem-assemble の `ineffectiveBlankLines` が、その位置の行アキを単位を作る前に除くからである。
`keep-with-next` の行数を 2 にする変更も、この組の入力では照合できていない。
本文の段落スタイルは段落の先頭に 2 行を求め、1 行の段落は分けられないので、1 行と 2 行の `keep-with-next` が後続の段落に同じ行数を求めるからである。
この変更を区別する入力は、後の「区切り」の節の `split` と `split-free` に追加した。
段が一つなので、段の番号だけが異なる分割も照合していない。

[仕様](../../docs/specifications.md)は、空の段へ送っても区切りの連続、後ろのアキ、後続ブロックの最初の部分を同じ段に置けない場合に G07134 で PDF の生成を止める（1876 行）と定める。
`holdNeeds` を写す前は、容量 3 行の段で 1 行の段落、`---`、`@need-lines 2`、1 行の段落を並べた原稿などの 7 個の入力で、空の段に収まる保持に golem-typeset と Lean の両方が G07134 を返していた。
PR #1131 が golem-typeset に `holdSeparatorNeeds` を加えたので、この 7 個は区切りの保持を次の段へ送ったページを返し、Lean の側も同じページを返す。
ただし、保持の中の `@need-lines` が段の容量から区切りの行を引いた行数を超えると、両方が G07134 を返す。
容量 2 行の段で、前後の行数が 0 の `---`、`@need-lines 2`、1 行の段落を並べた原稿では、区切りの行と段落の 1 行は空の段に収まる。
`holdSeparatorNeeds` が足す `@need-lines` は段の行数で抑えた 2 行なので、区切りの行は段の先頭に置かれ、その後の `@need-lines 2` は残りの 1 行で満たせず、段落を次の段へ送る。
`---` と 1 行の段落だけの原稿は、両方が一つの段に置いたページを返す。
仕様は保持の中の `@need-lines` をどう扱うかを定めていないので、この README は食い違いとは扱わず、`@need-lines` と G07134 のどちらを優先するかをメンテナーの判断に残す。
格子モードでは、区切り一つと後続の段落について、空の段に収まる保持の二つの行が一つの段に入ることを定理で示した。
`I3_separator_hold_together` は、何も待っていない状態（`Clear`）から、区切りの行、1 行の `keep-with-next`、区切りの後ろのアキ、段落のフローを `step` で進めると、区切りの行と段落の最初の行が一つの段に入ることを示す。
後ろのアキは、ないか、`FSpace` のフローが一つである（`gapFlows`）。
一つの段とは、最後の状態の今の段か、閉じた段の一つである（`Together`）。
`separatorFlows_hold` は、前後の行数が 0 の区切りと段落の単位から、`separatorFlows` が後ろのアキのないこのフローを作ることを示す。
`separatorFlows_hold_gap` は、後ろの行数が 1 以上の区切りから、`separatorFlows` がその行数のアキを持つこのフローを作ることを示す。

定理の前提は次のとおりで、保持が空の段に収まることと段落についての最後の二つの条件のほかは、段組みを切り替えない実際の入力で成り立つ。
`Clear` は、改ページ、`@need-lines`、行アキ、送った図版、繰り越す脚注が待っておらず、箱の中でも `FAdjustLines` の後でもなく、段組みの始めの行と段組みの上に残す脚注の行（`firstLine` と `reserved`）が 0 で、脚注のない段に脚注の行がないことである。
区切りの前の状態の段では、ほかの区切りの保持が待っていない（`heldHere` が `false`）。
区切りの後の `keep-with-next` は可視の区切りの位置を持つ（`env.held sp`）。
段組みを切り替えない本文では、`firstLine` と `reserved` は 0 のままである。
行は脚注を持たず、`fitting` は段に残る行の数だけ行を数える（`PlainFitting`）。
脚注区切りの行数は 0 行以上である。
`SeparatorBoundary.lean` の `boundary_plainFitting` は、照合に使う `boundaryEnv` の `fitting` がこの前提を満たすことを示し、`blockEnv` は `fitting` を変えない。
区切りの段落は最後の 1 行以上を送る段落スタイルを持つ（`keep-last-lines` は 1 以上である、[仕様](../../docs/specifications.md)の 3103 行）。
`keptNeed`（`modules/golem-layout/src/Golem/Layout/Paginate/Decide.hs:127`）が区切りの後に求める行数を n とし、1 + n が段の容量以下であることを、保持が空の段に収まることとする。
p は段落の最初の部分の行数で、1 行以上であり、段落の全体か、`splitAtBreak` がそのまま返す行数である（`firstPart`、`Decide.hs:258`）。
p と後ろのアキの行数の和は、n 行以下である。
段落の後に `@no-page-break` も `keep-with-next` も続かない（段落の後の `keptNeed` が `none`）か、p が `placeKept` の前の部分の最初の部分でもある。
前の部分は、`placeKept` が後の指定のために送る段落の最後の行（`keptCut`）より前の行である。
p がその行数以上であるか、`splitAtBreak` が前の部分について p をそのまま返すことを、p が前の部分の最初の部分であることとする。
`placeKept` が段落の全体を送るときは前の部分が 0 行なので、この条件はいつも成り立つ。

証明は、まず `placeKept` が区切りの行を置いた段に n 行以上が残ることを示す（`separator_place`）。
今の段に区切りの行を置いて n 行が残らず、今の段が空でなければ、区切りの行は次の段の先頭に送られ、その段には容量から 1 を引いた行が残る。
今の段が空なら、同じく容量から 1 を引いた行が残るので、n 行が残る。
続く `keep-with-next` は段を変えない（`view_keepNext`）。
後ろのアキは、段も待っている指定も変えず、アキの行数以下の行だけを使う（`gap_step`）。
そのため段には p 行以上が残り、段落はそこに p 行以上の最初の部分を置く（`placeLinesGo_first`、`split_pos`）。
段落が段に収まらないときは、最初の部分を置いた段を閉じてから次の段へ進むので、二つの行は閉じた段の一つに入る。
段落の後に `@no-page-break` か `keep-with-next` が続くときは、段落は `placeKept` で置かれる。
`placeKept` が段落の全体を送る行数にするときは、区切りの `keep-with-next` が区切りの段で待っているので、`heldHere` が成り立ち、`placeKept` は段落の全体を今の段から置く（`placeKept_held`）。
そのため、段落は `keptNeed` が `none` のときと同じに置かれる。
`placeKept` が段落を分けるときは、段落の全体を今の段から置くか、前の部分を今の段から置いた後に残りを同じ段か次の段へ置く（`placeKept_cases`）。
前者は `keptNeed` が `none` のときと同じである。
後者では、前の部分の最初の部分が区切りの行と一つの段に入り（`together_lines`）、残りを置く処理と次の段へ進む処理は閉じた段と今の段の行を変えない（`keeps_lines`、`keeps_nextColumn`）。

後のフローは、閉じた段と今の段の行を変えない。
`WholeNotes.lean` の `Keeps` は、出力済みのページと段がそのまま残り、今の段の行が段の先頭に残るか、後に続く行と一緒に閉じた段に入ることである。
`Keeps` は、`WholeNotes.lean` が脚注の行を注ごとに数える関係 `Rel` の一部（`Grows`）なので、`Rel` と同じく改ページのすべての関数で示される。
`keeps_placeAll` は、読む脚注が新しいとき（`Fresh`）に、`placeAll` がこの性質を保つことを示す。
`I3_separator_hold_one_column` は、`I3_separator_hold_together` の前提に、後のフローの脚注が新しいことを加えて、区切りの行と段落の最初の行が出力の段の一つに入ることを示す。
`hold_no_error_of_once` は、さらに二つの行がそれぞれ出力の一つの段にだけあるとき、区切りと段落の連続に G07134 を返さない（`holdErrors` に区切りの番号がない）ことを示す。
`I3_separator_hold_no_error` は、この最後の前提を、出力の行の列についての `text_placeAll` から導く。
`once_of_uniq` は、前の状態に置いた行と原稿のフローの行の id が重ならないとき（`Uniq`）、id は出力の一つの段にだけあることを示す。
出力の行の列は前の状態の行と原稿の行を一度ずつ並べたものなので、二つの段にある id は、この列に二度現れるからである。
golem-typeset は、行、図版、コードの行の id を一つの番号（`nuNext`、`Flow.hs:3863`、`Flow.hs:3873`）から振るので、実際の入力は `Uniq` を満たす。
`textSlots` が読まない図版、転置図版、回り込み図版、表の繰り返す見出しの行のスロット（`unlisted`）の id は、`WholeSlots.lean` が原稿の id に結びつける。
`WholeSlots.lean` の `P S` は、出力済みの段と今の段の `unlisted` のスロットと待機中の図版が `S` の id だけを持つことである。
`U` は、`WholeNotes.lean` の `Rel` と同じ形で、読んだフローが足す id（`flowUnl`）が `S` にあるとき、関数の前後で `P S` が保たれることを表し、改ページのすべての関数で示される。
フローが足す id は、図版、転置図版、回り込み図版の id と、表の見出しの行の id である。
表の見出しの行を後の段で繰り返すのは `putRepeated` だけで、その行は表の見出しの行である（`u_putRepeateds`）。
`hn_of` は、前の状態の `unlisted` のスロットが持たず（`T`）、フローも足さない id について、`I3_separator_hold_no_error` の前提 `hn` を導く。
表の見出しの行は後に続くフローの本文の行なので、`Uniq` から区切りの行と段落の最初の行の id と異なる（`not_unl`）。
`I3_separator_hold_no_error_ids` と `I3_separator_chain_no_error_ids` は、前提 `hn` の代わりに、前の状態の `unlisted` のスロットが二つの行の id を持たないことと、後に続くフローの図版の id（`sourceFigIds`）が二つの行の id でないことを置く。
golem-typeset は行と図版の id を一つの番号から振るので、実際の入力はこの二つも満たす。
区切りの連続も、格子モードで定理にした。
`Link` は連続の一つの区切りを、その段落スタイル、行、`keep-with-next` の位置、後ろのアキで表し、`chainFlows` はその列のフローである。
`I3_separator_chain_together` は、最初の区切りと後に続く区切りの列と段落のフローを進めると、すべての区切りの行と段落の最初の行が一つの段に入ることを示す（`TogetherAll`）。
前提は `I3_separator_hold_together` の前提を連続の各区切りについて置いたもので、p、最初の区切りの後ろのアキ、後の区切りの行とアキの行数（`chainLines`）の和が n 行以下であることを求める。
後の区切りは前の区切りの `keep-with-next` が待つ段で `placeKept` に置かれるので、`heldHere` が成り立ち、その行は今の段に置かれる（`held_line`）。
`chain_held` は、後の区切りの列が段から `chainLines` 以下の行だけを使い、行を今の段に足すことを、列についての帰納法で示す。
`I3_separator_chain_one_column` は、すべての行が出力の段の一つに入ることを示す。
`I3_separator_chain_no_error` は、連続に G07134 を返さないことを、`I3_separator_hold_no_error` と同じ前提で示す。
そのとき、連続の単位（`sepUnits`）が区切りの行を持ち、区切りの間の単位が連続を通せば、`holdGroups` は連続を一つの組にする（`holdGroups_chain`）。
`separatorFlows_chain` は、前後の行数が 0 の区切り二つと段落の単位から、`separatorFlows` がこの連続のフローを作ることを示す。
保持の中の `@need-lines` と区切りの前の行アキは、まだ定理の範囲にない。
自由な配置（`SeparatorPhysical.lean`）の同じ性質も、まだ示していない。

段落の後に `@no-page-break` が続く保持では、PR #1132 より前の golem-typeset が仕様と食い違っていた。
容量 4 行の段で、1 行の段落、`---`、1 行の段落、`@no-page-break`、3 行の段落を並べた原稿（区切りの前後の行数は 0）では、区切りの行が 1 ページ目に残り、続く 1 行の段落が 2 ページ目に送られて、G07134 になった。
区切りの行、1 行の段落、3 行の段落の最初の 2 行は合わせて 4 行で、空の段に収まる。
PR #1132 は、区切りの `keptNeed` に `@no-page-break` が保つ後の最初の部分を足し、保持の後のブロックを保持の段から送らないようにした。
その後は、golem-typeset と Lean の両方が、区切りの行と 1 行の段落を 2 ページ目に置き、3 行の段落を 3 ページ目に置いて、満たせなかった `@no-page-break` を付けたページを返す。
この原稿は、「実装との照合と全体の証明」の節で述べる照合の組 `holds`（`SeparatorBoundary.hs` の `holdInputs`）に含まれる。
容量 3 行の段で `---` と 3 行の段落を並べた原稿も、照合の組には含まれないが、両方が G07134 を返す。
3 行の段落は、最初と最後の 2 行を同じ段に置く規則（`keep-first-lines` と `keep-last-lines` の既定値）で分けられず、全体で一つの段に置かれる。
区切りの行と段落の最初の 1 行だけなら空の段に収まるが、分け方の規則を守ると区切りの行と合わせて 4 行になり、収まらない。
PR #1133 は、後続ブロックの最初の部分をそのブロック自身の分け方で前の段に残せる最小の部分と定め（1872 行）、この原稿を G07134 の例に挙げた（1877 行）。
そのため、この原稿の G07134 は仕様のとおりである。

## 自由な配置のモデル

`Physical.lean` は、[root ADR 0397](https://github.com/tett23/golem/blob/7fc360ff641d7eea6e8ee3ace30eca26e545334b/docs/adr/0397-paragraph-line-pitch-and-dimensional-spacing.md) の自由な配置（`Paginate/Physical.hs` の `paginatePhysical`）を、Haskell の関数ごとに一つの Lean の定義へ写した状態遷移のモデルである。
寸法は sp の整数（`Int`）のまま写し、格子の行に丸めない。
状態 `St` は `PhysicalState` から、ラベル、索引の印、表の部分、置いた罫線、節の記録を除いたものである。
除いた項目は出力の付帯情報で、どの段に何を置くかの判断には使わない。
`check.sh` は `Physical.lean` に `partial`、`sorry`、`axiom` などがないことを確かめ、ファイルを検査する。

モデルが扱うフローは、段落、続きの段落、図版、回した図版、スペース、行アキ、改段と改ページ（奇数ページと偶数ページの改ページを含む）、`need-lines`、`page-lines`（`FAdjustLines`）、`no-break`、行数を指定した `no-break`、`keep-with-next`、本文の行を持つ罫線つきのブロック（`RuledLines`）、見出しの罫線つきのブロック（`RuledHeading`）、回り込み図版（`FWrapped`）、表（`FTable`）、箱（`FBoxed`）、本の部（`FBookPart`）、節の開始（`FSection`）、段組みの切り替えと戻し（`FSwitchColumns`、`FRestoreColumns`）、見出し（`FHeading`）、定義の項（`FDefTerm`）、詩（`FStanza`）、コード（`FCode`）である。
コードの部分のスロット（`SCode`）は、Haskell の最初の行と行の数の代わりに行の id の列を持つ。
コードの行の数ごとの格子の行数は、`Code.hs` の `codeSpan` が返す値の列として `Flow.code` の引数（`spans`）に取る。
見出しは一つのスロット（`SHeading`）に置き、`I5_paginate_text` では見出しの最初の行の id を一つだけ数える。
脚注は、行ごとの脚注の分割（`splitNotes`）、次の段への繰り越し（`carryInto` と `splitCarried`）、区切りの長さを含めて写した。
罫線つきのブロックは、前のブロックと罫線の領域を共有する配置（`psJoin`）、共有をやめて次の段へ送る配置（`placeRuledKeeping` と `flushPendingRule`）を含めて写した。
待つ罫線は、`Paginate/Physical.hs` の `PendingRule` と同じく、ブロックの id、罫線の寸法、段の終わりで罫線が使う箱の始まりと送りと字面で持つ（`Pending`）。
[root ADR 0449](../../docs/adr/0449-share-rule-areas-with-ruled-headings-in-both-placements.md) の後、見出しの罫線つきのブロックも、前の罫線を待つ罫線と共有し（`headingBeforeShared`）、後の罫線を次のブロックのために待たせる（`headingWaiting`、`ruledHeadingHere`）。
`ruledHeadingHere`（`Paginate/Physical.hs:1569`）は、`placeRuled` の `RuledHeading` の枝から分かれた関数で、`Physical.lean` でも同じ名前で写した。
段の終わりの後の罫線で次の段へ送った見出しは、`Paginate/Physical.hs` では `placeRuled` で置き直すが、`Physical.lean` では `ruledHeadingHere` で置き直す。
新しい段には待つ罫線も後の罫線もないので、`placeRuled` はそのまま `ruledHeadingHere` を呼び、二つは同じ配置を返す。
こう写すと、`placeRuled` と `ruledHeadingHere` の相互再帰の尺度を、罫線の数の 2 倍（`placeRuled` ではそれに 1 を足す）と段の順位で取れる。
共有できないブロックが次の段から始まる規則（`startsAfterOwnRule`）も写した。
見出しの罫線つきのブロックは、`keepFollowing` で後続を判定した段から、罫線の領域を足した長さで見出しを置く。
罫線の領域と見出しと脚注の長さの和が段の容量を超えるときは、後の罫線を外し、次に前の罫線を外して置き直し、どちらもなければ罫線のない見出しとして置く。
見出しの罫線の領域は、`physicalHeadingBounds` に見出しの字面の位置があればその位置から求めた仮想の送りで求める（`Env.headingBounds`）。
罫線の領域の長さは、`FreeGeometry.hs` の `faceOffset`、`ruleBeforeGap`、`ruleAfterGap`、`rulesSharedGap`、`ruleBeforeEdge`、`ruleAfterEdge` のうち、使用長に足す長さ（extra）だけを写した。
罫線つきの段落の後の罫線の位置だけは、段に置けるかの判定（`ruleAfterInColumn`）が読むので、`ruleAfterGap` と `ruleAfterEdge` が返す位置も写した（`ruleAfterPos`）。
段に置いた後の罫線の位置は、見出しの前の罫線の置き方が読むので、段ごとに `St.afterRules` に記録する（`ruledAfterRules`、`flushPendingRule`、`putRuledHeading`）。
見出しの罫線は、領域の長さと位置をともに写した（`headingBeforeGeom`、`headingAfterGeom`）。
先のフローが求める長さ（`firstNeed`）は `Env` の引数とし、定理はそのどの値でも成り立つ。

罫線つきの段落は、`ruledHere`（`Paginate/Physical.hs:1384`）が置く段を決める（[golem-driver ADR 0027](../../docs/golem-driver/adr/0027-paragraph-style-rules.md)）。
`ruledHere` は、後続を読んだ配置で段落が段に収まり、後の罫線が段にとどまるときに、その配置で置く。
後の罫線がとどまるのは、後続が罫線の領域を共有する段落か見出しで始まり、そのブロックが同じ段で領域を共有して置けて後続のために次の段へ送られないとき（`settlesHere`）か、後続が共有しないときに後の罫線が段の脚注より上で終わるとき（`ruleAfterInColumn`）である。
とどまらなければ、後続を読まず、後の罫線を段の終わりの長さで数えた配置で置き直す。
罫線を省く見出し（G07046、`headingDrops`）と、奇数ページから始める見出しは、前の罫線を共有しない（`joinsNext`、`settlesHere`）。
`Physical.lean` は、`ruleAfterInColumn` が読む `psRules` を写さず、ブロックの後の罫線を一つだけ読む（`ruleAfterFits`、見出しでは `headingRuleFits`）。
罫線つきのブロックの id は互いに異なるので、`psRules` の中でその id を持つ後の罫線はこの一つである。

`I3_ruledHere_rule_after` は、`ruledHere` が置いた段落の後の罫線が、次の段落との共有を待つか、段の中で段の脚注より上で終わることを示す。
段の終わりの長さで置いた後の罫線も、段落が使った長さの中で終わり（`I3_ruleAfter_edge`）、その長さは段の脚注より上にある。
段落の各行は、段落の残りの行と後の罫線の領域を、その行の脚注に使わせないからである（`Paginate/Physical.hs:1436` の `ruledLinesPlan` の `putKeeping`、`Physical.lean` の `putLinesKeeping`）。
各行を置いた後で、使用長と脚注の長さと残りの行と後の罫線の領域の和が段の長さを超えないことが、行ごとに保たれる（`putLinesKeeping_room`）。
定理の前提は、ページの行送りが正であることと、段落の行の脚注がどれも 1 行以上であることである。
脚注が 0 行なら、脚注の区切りだけが余りを越えて数えられうる。

この性質は、PR #1149 が golem-layout を直す前には成り立たなかった。
容量 40 sp、脚注の区切り 2 sp の段に、3 行の脚注を持つ行と脚注のない行からなる段落を、後の罫線（内側 2 sp、外側 2 sp、太さ 1 sp）とともに置き、1 行の段落を続けた入力で、直す前の `paginatePhysical` は脚注を 2 行置き、後の罫線を脚注の領域の中の 21 sp に置いた。
直した後は、1 ページ目に脚注を 1 行だけ置いて脚注の領域を 28 sp から始め、後の罫線を 22 sp に置く。
`PhysicalBoundary.hs` は、この形の入力（後の罫線を持ち、1 行目か 2 行目に脚注を持つ 2 行または 3 行の段落）を照合に含む。

この性質は、PR #1150 が golem-layout を直す前には、空の段の余りが段落より短いときに成り立たなかった。
`fit` は空の段を次の段へ送らないので、段落はその段の余りを越えて置かれ、後の罫線も脚注の領域や段の外に出えた。
容量 40 sp の 1 段組みで、2 行の段落の後に 2 段組みに切り替え、2 行の段落と、後の罫線を持つ 3 行の罫線つきの段落を続けた入力で、直す前の `paginatePhysical` は、2 段目を 20 sp から始め、罫線つきの段落の 3 行目を 40 sp に、後の罫線を 51 sp に置いた。
どちらも容量の 40 sp を越える。
直した後の `ruledLinesHere` は、`fit` が残した段の余りより段落が長いときにも段落を置かず、`placeRuled` は格子の `splitRuled` と同じく段落を罫線なしで分ける（G07046、[root ADR 0397](../../docs/adr/0397-paragraph-line-pitch-and-dimensional-spacing.md) の境界の行「罫線付き段落が空段の長さを超える」）。
同じ入力で、2 段目の 20 sp と 30 sp に 2 行を置き、3 行目を次のページの 0 sp へ送り、罫線は置かない。
`Physical.lean` の `ruledLinesHere` にもこの条件を写したので、`I3_ruledHere_rule_after` は例外なく成り立つ。
`I3_ruledHere_in_column` は、`ruledHere` が置いた段落の使用長と脚注の長さの和が段の長さを超えないこと、つまり段落の各行が段の中にあることを示す。
`PhysicalBoundary.hs` はこの入力（2 行と 3 行の段落、後の罫線の各形）を照合に含み、`Physical.lean` の `paginate` は直した後の位置を返す。

罫線つきの段落の後に、領域を共有しないブロック（前の罫線がない、共有の印がない、奇数ページから始める見出し）が続くときは、段落の後の罫線は待たず、次の行の字面との間のアキか段の終わりに置かれる（`ruledLinesPlan` の `endRule`、`Physical.lean` の `ruleAfterPos`）。
`I3_ruledHere_unshared_rule_after` は、このとき `ruledHere` が置いた段落の後の罫線が、段の中で段の脚注より上で終わることを示す。

PR #1151 の後、見出しの前の罫線は、罫線つきの段落の前の罫線と同じく置かれる（`placeRuled` の `RuledHeading` の `beforeGeometry`、`Physical.lean` の `headingBeforeGeom`）。
直前のスロットが行で、待っているスペースがなく、その行の始まりより後に後の罫線がないときは、行の字面と見出しの字面の間のアキに `ruleBeforeGap` で置かれる。
そうでないときは、見出しの領域の始めから `ruleBeforeEdge` で置かれ、版面の外に出るのは、使用長 0 の空の段の始めだけである。
空の段に罫線とともに収まるかの判定には、これまでと同じく版面の外を持つ寸法の領域（`headingBeforeExtra`）を使う。
`I3_ruledHeading_rule_before` は、待つ罫線と領域を共有しないときに（`headingBeforeSharedAt_own`）、この前の罫線が三つの性質を持つことを示す。
一つ目に、見出しの最初の行の字面の始まりからはみ出しを引いた位置より前で終わる。
二つ目に、段の脚注より上で終わる。
三つ目に、直前の行の字面の終わり以降から始まるか、見出しの領域の始め以降から始まるか、使用長 0 の空の段の始めより前に収まる。
前提は、ページの行送りが正であること、見出しの脚注がどれも 1 行以上であること、`putRuledHeading` を呼ぶ状態の余りが前の罫線の領域と見出しの長さと後の罫線の領域を収めること、見出しの最初の行の字面の前のアキからはみ出しを引いた長さが見出しの長さを越えないこと、罫線の内側と外側のアキが 0 以上であること、`putRuledHeading` を呼ぶ状態が `placeRuled` と同じく `headingReady` で作られ、段を変えないことである。
待っているスペースがなければ、段を変えない `headingReady` は使用長を変えない（`headingReady_here_used`）。
`fit` は、空の段の始めではスペースを捨て、そうでなければ待っているスペースを置くので、段を変えなければ使用長は待っているスペースの分だけ増え、それは 0 である（`fit_here_used`）。
縮めた段に見出しを置く `tallAt` も使用長を変えない。
これまでの前提にあった、罫線が版面の外を持たないことは除いた。
`placeRuled` は、`fit` が段を変えず、置く長さが余りに収まるときにだけ、余りの前提を満たして `putRuledHeading` を呼ぶ（`fit_here_room`）。
空の段の余りより見出しが長くても `fit` が段を残す場合と、縮めた段に見出しを置く `TallHeadingExtent` の場合は、この前提を満たさない。

PR #1151 の前は、版面の外に出してよい（`keep-in-column = false`）見出しの前の罫線が、段の途中で見出しの字面に重なりえた。
`placeRuled` は、前の罫線の領域を版面の外を持つ寸法で求めたが、罫線の位置は版面の外を除いた寸法で求めたからである。
行送り 20 sp、字面 10 sp、容量 200 sp の 1 段組みで、1 行の段落の後に、前の罫線（内側 0 sp、外側 0 sp、太さ 12 sp、アキの指定なし、版面の外に 20 sp）を持つ長さ 20 sp の見出しの罫線つきのブロックを続けた入力で、直す前の `paginatePhysical` は見出しと前の罫線をともに 20 sp に置き、罫線は 25 sp から始まる見出しの字面に重なった。
直した後の `paginatePhysical` は、見出しを 22 sp に、前の罫線を 15 sp に置く。
罫線は段落の行の字面が終わる 15 sp から始まり、見出しの字面が始まる 27 sp で終わる。
`ruledHeading_outside_rule_off_face` は、この入力で `headingBeforeGeom` が領域 2 sp と位置 -5 sp（見出しの領域の始めから）を与え、罫線が二つの字面のどちらにも重ならないことを示す。

PR #1152 の後、見出しの後の罫線は、段の途中では次の行の字面との間のアキに `ruleAfterGap` で置かれ、外側のアキと次の行のはみ出しを数える（`afterGeometry` の `interior`、`Physical.lean` の `headingAfterGeom`）。
次のブロックが自身の前の罫線を持つとき、次のブロックに行がないとき、その配置で罫線が段の脚注より上で終わらないとき（`ruleAfterInColumn`、`headingRuleFits`）、置く長さが段に収まらないときは、段の終わりの寸法（`ruleAfterEdge`、外側のアキなし）で置き直す。
`I3_ruledHeading_rule_after` は、見出しの後の罫線が、見出しの最後の行の字面の終わり以降から始まり、段の脚注より上で終わることを示す。
段の途中の配置では、罫線は次の行の字面の始まりから次の行のはみ出しを引いた位置より前で終わり、段の終わりの配置では、見出しの領域の中で終わる。
前提は、`I3_ruledHeading_rule_before` の余りと脚注と内側と外側のアキの前提と、段の途中の配置では `headingRuleFits` が真であることである。
`placeRuled` は、段の途中の配置を `headingRuleFits` が真のときにだけ返す。
この位置は、段に置いた後の罫線の位置の記録（`St.afterRules`）の最後に入る。

段落の後の罫線と見出しの前の罫線は、PR #1151 と #1152 の後も、段の中にあって重なりえた。
後の罫線を待たせるのは次のブロックが段落のときだけで、見出しの前の罫線は見出しの領域の始めから置かれ、二つの罫線が見出しの字面の前のアキを取り合ったからである。
行送り 20 sp、字面 10 sp、容量 200 sp の 1 段組みで、後の罫線（内側 0 sp、外側 0 sp、太さ 4 sp、アキの指定なし）を持つ 1 行の罫線つきの段落と、同じ寸法の前の罫線を持つ長さ 20 sp の見出しの罫線つきのブロックを続けると、PR #1152 の後の `paginatePhysical` は段落の後の罫線を 18 sp に、見出しの前の罫線を 21 sp に置き、21 sp から 22 sp までが重なった。

[root ADR 0449](../../docs/adr/0449-share-rule-areas-with-ruled-headings-in-both-placements.md) の後、段落と見出しの四つの組で、後の罫線と前の罫線は一つの領域を共有する。
同じ入力で見出しに共有の印（`frJoined`）を付けると、PR #1159 の後の `paginatePhysical` は段落の後の罫線を 15 sp に、見出しの前の罫線を 21 sp に置き、二つは重ならない。
`ruledHeading_rules_shared` は、この入力で段落の後の罫線が待ち、見出しが共有の領域から 0 sp の長さと二つの罫線の位置 15 sp と 21 sp を与えることを示す。
golem-typeset の `ruledLinks` は、後の罫線を持つブロックの直後の前の罫線を持つブロックに必ず共有の印を付けるので、実際のフローで重なりが起きる組は残らない。
共有の印のない同じ入力では、`paginatePhysical` は今も 18 sp と 21 sp に置く。

[root ADR 0449](../../docs/adr/0449-share-rule-areas-with-ruled-headings-in-both-placements.md) の不変条件 2（罫線が重ならないこと）は、自由な配置では五つの定理で示す。
`I2_sharedGap_disjoint` は、共有の領域（`rulesSharedGap`）で、前のブロックの後の罫線が前の字面の終わり以降から始まり、後のブロックの前の罫線がその罫線の終わり以降から始まり、後の字面の始まりからはみ出しを引いた位置より前で終わることを示す。
前提は、二つの罫線の内側のアキと、前のブロックの後の罫線の外側のアキが 0 以上であることである。
`I2_ruledLines_shared` と `I2_ruledHeading_shared` は、待つ罫線を共有する段落と見出しの配置が、この共有の領域を前の罫線の領域とし、前のブロックの後の罫線をその中に置くことを示す。
`I2_placeRuled_joined` は、待つ罫線を共有する印を持つブロックが同じ段で共有しないとき、待つ罫線を段の終わりに置き、ブロックを次の段から置くことを示す。
`I2_startsAfterOwnRule` は、前のブロックの後の罫線が段の最後のスロット以降に自身の領域で置かれた段では、共有の印を持つブロックが次の段から始まることを示す。
`PhysicalBoundary.hs` は、四つの組を、あいだにスペースを置くか置かないか、段の容量（36、44、60 sp）、後のブロックの長さ（1 行か 2 行の段落、長さ 10 sp か 24 sp の見出し）を変えて照合に含む。

[root ADR 0450](../../docs/adr/0450-put-free-placement-rules-after-outside-the-column-end.md) の後、段の外に出てよい後の罫線（`RuleSide.outside` が `some`）は、段の終わりで最後の行の直後に置かれ、段を閉じる。
条件は、最後の行の直後の位置（`ruleAfterOutside`）が段の終わり以降にあり、段の外へのはみ出しが外の余白に収まり、段とブロックの行に脚注がないことである。
Lean は、この判定を段落の後の罫線（`ruledOutsideAt`、`ruledAfterExtraAt`、`ruledAfterRules`、`ruledCloses`、`ruledPlaceAt`）、見出しの後の罫線（`headingOutsideAt`、`headingAfterHere`、`headingEndsAt`、`headingClosesAt`、`putRuledHeading`）、待つ罫線を段の終わりに置く処理（`flushPendingRule`）、空の段で見出しが罫線を捨てるかの判定（`headingDropsAfter`）に写した。
`ruleAfterInColumn` は、罫線が段の中で脚注より前に終わるか、この条件で段の外にあることを求める（`ruleAfterInColumnAt`）。
`placeRuled` は、次の段に送るかと罫線を捨てるかを、この段と次の段の長さの小さいほう（`ruledLeast`）で決める。
`I3_ruled_rule_after_outside` と `I3_ruledHeading_rule_after_outside` は、段の外に出た罫線が段の終わり以降にあり、はみ出しが外の余白以下で、段に脚注がないことを示す。
`ruledPlaceAt_room` と `I3_ruledHere_in_column` は、罫線が段を閉じる場合も、行と脚注が段に収まることを示す。
段の中に置く罫線についての定理（`I3_ruledHere_rule_after`、`I3_ruledHere_unshared_rule_after`、`I3_ruledHeading_rule_after`）は、`RuleSide.outside` が `none` の罫線について述べる。
`PhysicalBoundary.hs` の 156520 個の境界入力は、段の外に出てよい後の罫線を持つブロックを含み、すべて golem-layout の `paginatePhysical` と一致した。
その罫線は、字面からのアキを指定しないもの（外の余白 5 sp と 20 sp）と、指定するもの（内側 2 sp で外の余白 10 sp、内側 6 sp で外の余白 4 sp）である。
後者の 160 個は、1〜3 行の罫線つきの段落か 1 行の見出しを、なしか 1〜3 行の段落の後に容量 30〜60 sp の段に置く。
`ruleAfterOutside` の `spaced` の場合を、内側のアキを足さない位置か `spaced` でない場合と同じ位置に替えると、どちらも 18 個の入力で出力が食い違ったので、この照合はその場合を区別する。

回り込み図版は、長さのないスロット（`SWrapped`）として段に置き、横に収まる行（`fittingWrapped`）を図版の終わりまでの長さを予約して置き、残りの行を次の段から置く（`placeWrappedOverflow`）。
横の行と残りの行の前のアキは `physicalWrappedBefore` の値で、`Env.wrappedBefore` に写した。

表は、本の部の外で使う `placeTable` を写した。
最初の部分が収まる段を `seek` で探し（`tableReady`）、キャプション、見出しの行、本体の行を、後に置く行の長さを予約しながら置く（`putReserved`）。
本体の行が収まらなければ次の段へ進み、見出しの行が収まる段でその行を繰り返す。
繰り返す見出しの行は、Physical.hs では同じ id の `SLine` である。
モデルでは本文に数えないスロット（`Slot.repeated`）に置き、照合では同じ `L` の記号で書き出す。
ページか見開きの本の部の中では、`placeTableAcross` を写した。
キャプション、見出しの行、本体の行をそれぞれ収まる段か段の先頭に置き、行が新しいページで始まるときだけ見出しの行を繰り返す（`acrossGo`）。
下のキャプションは、最後の行とともに本の部と同じく保持する（`acrossTail` と `retain`）。

箱は、`placeFlow` の `FBoxed` の四つの場合を中身の形ごとに写した（`placeBox`）。
中身が一つの段落なら `placeBoxedParagraph` で、一つの詩なら `placeBoxedStanza` で置く。
中身が段落、詩、スペース、`keep-with-next` だけなら、`collectMixedBoxUnits`（`collectMixed`）が段落の各行と詩の各行を単位に分け、`placeBoxedStanzaWith` がその単位を置く。
このとき、スペースは次の単位の前のアキ（`BoxMaps.gaps`）になり、`keep-with-next` はその前の最後の行と求める行数の組（`boxLinks`）になり、段落と詩の保持は単位ごとの保持（`unitKeepsOf`）になる。
モデルの `placeBoxedStanza` はこれらの表を引数（`BoxMaps`）に取り、一つの詩の箱には空の表（`noMaps`）を渡す。
そのほかの中身の箱は、余白の内側に中身のフローを一つずつ `placeFlow` で置く（`placeGeneric`）。
箱の中にも箱を置けるので、`Flow` は自身の列を持つ入れ子の帰納型である。
`placeFlow` は一段内側のフローを置く `placeFlow` を引数（`Inner`）に取り、`level n` は箱を `n` 段まで入れ子にした `placeFlow` である。
`paginate` は、原稿の入れ子の深さ（`flowsDepth`）の段数の `level` を使う。

本の部は、`retainPhysicalPart` を写した（`retain`）。
本の部の中身は、一段内側の `placeAll`（`Inner.all`）で置く。
単位が段でなければ、中身を置く `Env` に単位を与える（`Env.retention`、Physical.hs の `physicalRetention`）。
単位を与えた `Env` では、定義の項を `keepFollowing` を通さずに置き、表を `placeTableAcross` で置く。
`retain` は、中身を今の段から置き、本の部の図版が待機している間は段を進める（`settle`）。
置いた後、本の部の id がすべて、置き始めた段の単位に最初に現れるかを確かめる（`partFits`）。
単位は、段なら段、ページならページ、見開きなら見開きの番号である（`unitKey`）。
確かめが通らなければ、次の単位の最初の段（`nextUnit`）から置き直し、それでも通らなければ `SplitBookPart`（`Unmet.splitPart`）を記録する。
単位が段のときは、置き直した結果は確かめにだけ使い、今の段から置いた配置を残す。
箱の部分は、`physicalBoxPadding` があればその余白（`Env.boxPadding`）、なければフローの前後の長さを最初と最後の行の外に取る。
ただし、そのほかの中身の箱は、余白がなければ 0 の余白で長さを求め、中身に行がないときだけフローの前後の長さを使う（`genericExtra`）。
詩の行が空の段にも収まらないときは、その詩の行を箱の段落として置き、段の終わりで閉じた箱の部分を開き直して後の詩の行を続ける（`reopen` と `seal`）。
このため、状態 `St` に段の箱の部分（`psBoxes`）を加えた。

回り込み図版の横の段落は、golem-typeset が `trialParagraphPartLimit` に回り込みの領域と行数の上限を渡して一部分ずつ置き、段を進めるたびに残りの原稿を改行し直す。
モデルは、回り込みの領域と行数の上限を持つ `trialParagraphPartLimit` を `trialWrap` として、`movePhysicalCursor` を `moveCursor` として、`beginPhysicalWrap` を `beginWrap` として写した。
回り込みの領域（`Region`）は図版のページ、段、終わりの位置で、その段では行の終わりを図版の終わりと比べて収まる行を数え（`fittingHere`）、図版の横の行を `putWrappedLine` で置く（`putHere`）。
改行し直すループは、golem-typeset の `causalFreeFlow` の `paragraph` の `parts` を `parts` として写した。
`parts` は改行器を引数（`breaker`）に取り、改行器は、カーソル、置いた行の数、原稿の項目の位置から、残りの原稿の行と、それぞれの行の改行の後の項目の位置を返す。
後に続くものが収まるかの判定（`probeNext`）と、最後の部分の後の `keepPhysicalNext` も引数（`follows` と `hold`）である。
golem-typeset が小さくならない上限で試し直すとき、または後でない項目の位置から続けるとき、`parts` は `noProgress` を返す。

モデルは次の点で Haskell の実装と異なる。
`paginatePhysical` の中の `trialParagraphPartLimit` は回り込みの領域と行数の上限を持たない場合（`trial`）として写し、そこでの `movePhysicalCursor` は `nextColumn` として写した。
`movePhysicalCursor` が閉じる段の使用長を広げる処理は、閉じた段の出力に現れないからである。
`trialParagraphPartLimit` が呼ぶたびに行う `checkPhysicalNotes` は、`trial` も呼ぶたびに行う（`checkRows`）。
`paginatePhysical` の最初の検査は本の部の中の行を見ないので（`flowLines` の `FBookPart` は空）、本の部の中の段落にはこの検査が働く。
`slotIds` は、コードのスロットの id を、Physical.hs の最初の行から続く番号でなく、モデルのスロットが持つ行の id の列とする。
golem-typeset はコードの行に、行と図版と同じ番号から続く番号を振る（`numberCode`、`Flow.hs:3866`）。
`SeparatorBoundary.hs` のコードブロックを含む組（`code` と `code-free`）は、golem-typeset のコードのスロットの最初の行と行数から行の番号を並べ、モデルのスロットの id の列と照合し、すべて一致した。
これは有限個の原稿の照合であり、定理ではない。
モデルのコードの行の id を一つずらすと、格子モードで 2620 個、自由な配置で 2300 個の原稿で出力が食い違った。
`drainCarry` は、次のページが最初の待機中の図版と最初の繰り越し脚注の 1 行を受け取れる間だけ進む（`drainOk`）。
この条件が成り立たない状態では、Physical.hs の `drainCarry` は止まらないか、送りが 0 のときに `div` の例外になる。
繰り越す脚注の 1 行が新しいページに収まらなければ、どのページでも脚注は減らないからである。
そのため、`paginate` は、最後の `drainCarry` の後に待機中の図版か繰り越す脚注が残れば `noProgress` を返す。
`PhysicalDrain.lean` は、本の部を含まずに `checkNotes` を通り、行送りが正の原稿では、`paginate` がこの `noProgress` を返さないことを証明する（`I4_paginate_checked`）。
その不変条件 `Inv` は、待機中の図版がどれも段の容量以下であり、繰り越す脚注は、区切りと 1 行の和が段の容量以下で行送りが正のときにだけ残ることである。
図版を待機させるのは `placeFlow` の `FFigure` と `FPageFigure` だけで、`FFigure` は段の容量を超える図版を `figureTooTall` にしてから待機させる（`dk_send`）。
脚注を繰り越すのは脚注を持つ行を置く `putLineWithReserve` だけなので、原稿が脚注を持たなければ繰り越す脚注は空のままである（`dr_putLine`）。
`R` は、`PhysicalNotes.lean` の `Rel` と同じ形で、読んだ脚注が空か脚注の 1 行が空の段に収まるとき、関数の前後で `Inv` が保たれることを表す。
`dr_placeAll` は、`paginate` が呼ぶ `placeAll` が箱と本の部の入れ子のどの深さでも `Inv` を保つことを示し、`Inv` は `drainOk` を導き（`inv_drainOk`）、`nextColumn` で保たれる。
そのため、最後の `drainCarry` は待機中の図版と繰り越す脚注をすべて置く（`I4_paginate_drained`）。
`checkNotes` は本の部の中の行を見ないので、本の部を含む原稿は、脚注を持たないか、区切りと 1 行の和が段の容量以下の場合だけを `I4_paginate_drained` が扱う。

終了は、各ループが整礎な再帰で定義されていることで示す。
`I4_nextColumn_rank` は、何かを置いた段か `FAdjustLines` で縮んだ段から次の段へ進むと、尺度 `rank` が減ることを証明する。
`rank` は、待機中の図版の数と繰り越す脚注ごとの行数に 1 を足した値の和（`waiting`）に、組の段の数の 4 倍に 8 を足した重み（`unitWeight`）を掛け、段の縮みの重み（`adjustWeight`）と、段が空でなければ 1 を足した値である。
段の縮みの重みは、組の段がそろって縮むとき（`psSetAdjustment` を写した `setAdjust` が負）はページの残りの段数の 4 倍に 4 を足した値、その段だけが縮むときは 2、縮まないときは 0 である。
組の段がそろって縮むときは次の段も縮むので、`fresh_weight` は、次の段の重みが前の段より小さいか 0 であることを示す。
`placeLines` は残りの行数、`keep-all-lines` の有無、この尺度の辞書式順序で止まる（`I4_trial_moved`、`I4_trial_placed`）。
`placeStanza` も、残りの詩の行の数、`keep-all-lines` の有無、この尺度の辞書式順序で止まる。
`placeCode` が収まる段まで進むループは `seek` に写し、`drainCarry` と同じく `waiting` とページの残りの段数の辞書式順序で止まる。
ただし、`seek` は、待つものがなくページの最後の段まで進んでも収まらないとき、次のページの最初の段で止まる。
そこから先の段はどれも同じ状態なので、Haskell の実装はこのとき止まらない。
`placeCode` はこの段で収まる行がなければ `noProgress` を返すので、`paginate` が成功した入力では Haskell と同じ配置になる。

回り込み図版の横の行を置く `putBeside` と残りの行を置く `placeWrappedOverflow` は、行の列についての構造的な再帰である。
箱の段落は、残りの行の数、`keep-all-lines` の有無、`rank` の辞書式順序で止まり、箱の詩は、残りの詩の行の数、`keep-all-lines` の有無、`rank` の辞書式順序で止まる。
開いた箱の部分を閉じてから次の段へ進んでも `rank` は減る（`rank_seal_lt`）。
単位ごとの保持を持つ箱では、`keep-all-lines` の有無と `rank` の間に、`keep-all-lines` をまだ緩めていない段落の単位の数（`unrelaxed`）を入れる。
空の段でも収まらない単位がその段落の `keep-all-lines` を緩めると、この数が減る（`unrelaxed_lt`）。
表の本体の行を置くループ（`tableRowsGo`）は、見出しの行を繰り返す前の `tableReady` のループを含めて、一つの整礎な再帰で定義した。
尺度は、残りの行の数、最後に行を置いてから待つもののないページの最後の段を通ったか、`waiting`、ページの残りの段数、`tableReady` の途中かの辞書式順序である。
見出しの行を繰り返した直後の行は、収まらなくても、使用長が見出しの行の数と行の送りの積だけ進んでいれば置く（Physical.hs の `firstRow`）。
見出しの行の送りが行の送りと異なると、この判定が偽になり、Physical.hs は収まらない行の前で見出しの行を繰り返し続ける。
モデルは、最後に行を置いてから二度目に、待つもののないページの最後の段から進むとき、`noProgress` を返す。
一度目にそこを通った後の段は、ページの番号のほかはどれも同じ状態なので、Haskell の実装はそこから止まらないからである。
容量 30 sp、送り 10 sp の 1 段で、2 行の段落の後に、送り 14 sp の行 905 だけの見出しの行と本体の行 `[810]`、`[820, 821]` を持つ表を置くと、`paginatePhysical` は 2 秒で 2.8 GB を割り当てても終わらなかった。
golem-typeset が `physicalPitches` に送りを与えるのは段落の単位の行だけで（`modules/golem-typeset/src/Golem/Typeset/Flow.hs:4222`）、表の行には与えないので、原稿から作る表では見出しの行の送りは行の送りに等しい。

`judgeNeed`（`FNeedLines` の段のループ）も、空でない段か縮んだ段からだけ次の段へ進むので、`rank` で止まる。

本の部の次の単位まで段を進めるループ（`advanceUnit`）は、次の段がページの番号か残りの段数を必ず進める（`nextColumn_moves`）ので、単位の番号から決まるページの上限との差と残りの段数の辞書式順序で止まる。
本の部の図版が待つ間に段を進めるループ（`settle`）は、待機中の図版があるので `waiting` とページの残りの段数の辞書式順序で止まる（`I4_settle_rank`）。
`placeTableAcross` のループ（`acrossGo`）は、残りの部分の数と `rank` の辞書式順序で止まる。
`parts` は、原稿の残りの項目の数、`keep-all-lines` の有無、`rank`、行数の上限の辞書式順序で止まる。
段を進めると `rank` が減り（`I4_trialWrap_moved` と `I4_moveCursor_rank`）、試し直すと上限が減り、続けると残りの項目が減る。

回り込み図版の横のほかのループも、`parts` と同じく、組んだ行と後続の判定を引数（`Beside`、`Probe`、`StanzaArgs`、`Jobs`）に取って写し、明示した尺度で止まることを証明した。
詩の行を一つずつ試すループ（`tryVerses`）は、詩の行の列で構造的に止まる。
後続を試すループ（`probeNext` と `probeChain`）は、相互再帰で定義し、残りの段落の数と関数（`probeChain` が 1、`probeNext` が 0）の辞書式順序で止まる。
`probeNext` は、試す段落か連（`verseSpan`）を先頭から外した残りを `probeChain` に渡し、`probeChain` は同じ残りを `probeNext` に渡すからである。
連を置くループ（`stanza` とその `accept`）も相互再帰で定義し、残りの詩の行の数、`keepRank`、`rank`、関数（`stanza` が 1、`accept` が 0）、`accept` の行数の辞書式順序で止まる。
`stanza` を呼び直すのは、1 行以上を置いたとき、空の段に収まらない詩の行を表示の行で置いたとき、`keep-all-lines` を外したとき、空でない段から次の段へ進んだとき（`I4_moveCursor_rank`）だけであり、`accept` は行数を減らして自身を呼ぶ。
golem-typeset が `trials !! (count - 1)` で読む行数は 1 以上で試しの数以下なので（`splitAtBreak` は受け取った数を越えない）、その外の行数では `noProgress` を返す。
図版ごとの仕事を進めるループ（`jobsFrom`）は、図版の数で止まる。
リスト項目の中の図版では、`itemJobs` が返す残りの図版の数が受け取った数を越えないことを型（部分型）で持たせたので、`retainPhysicalPart` が試しを何度呼んでも、`jobsFrom` に戻る図版は減る。
回り込み図版の横の段落と連を順に置くループ（`paragraphs`）は、段落を `paragraph` に、連を `stanza` に渡し、残りの段落の数で止まる。
連のときは、同じ連の詩の行（`verseSpan`）をまとめて先頭から外すので、残りは `verseSpan_after` により 1 以上減る。
段落の前の制御と始まりの改段（`stepPhysicalCursor` と `stepPhysicalPrefix`）、試さなかった詩の行の組み直す前の行、`paragraph` は、`Paras` の引数として受け取る。
`paragraphs` が段落と詩の行を過不足なく順に渡すことも証明した。
`groups` は、入力の列を `paragraphs` が一度に扱う組（段落一つか、一つの連の詩の行）に分ける。
`I5_groups_join` は、組をつなげると入力の列に戻ることを示すので、どの段落と詩の行もちょうど一つの組に、入力の順で入る。
`I5_paragraphs_groups` は、`paragraphs` が、組を順に一つずつ `paragraph` か `stanza` に渡す `byGroups` と等しいことを示す。

`fitsFollowing` は罫線つきのブロックを試しに置き、見出しの罫線つきのブロックは `keepFollowing` を通して `fitsFollowing` を呼ぶので、`fitsFollowingGo` と `placeRuled` は相互再帰で定義した。
尺度は三つ組の辞書式順序である。
`fitsFollowingGo` の尺度は、読む後続のフローの数、5、0 の組である。
`placeRuled` の尺度は、後に続くフローの数に 1 を足した値、罫線の数と共有の有無の和（`ruledRank`）に 1 を足した値、この `rank` の組である。
`fitsFollowingGo` が `placeRuled` を呼ぶときは後続のフローの数が等しく、`ruledRank` は 3 以下なので、二つ目が減る。
`placeRuled` が `fitsFollowingGo` を呼ぶときは、`keepAhead` が返す列が元の列より長くならないので（`keepWanted_length`）、一つ目が減る。
`placeRuled` が自身を呼ぶときは、罫線を外すか共有をやめれば `ruledRank` が減り、`fit` が段を進めれば `rank` が減る（`I4_fit_moved`、見出しでは `headingReady_moved`）。
罫線つきの段落を置く段を決める `ruledHere`、`settlesHere`、`movesForFollowing` も、同じ相互再帰に入る。
`ruledHere` と `movesForFollowing` の尺度は後に続くフローの数に 1 を足した値、0、0 の組で、`settlesHere` の尺度は後に続くフローの数、1、0 の組である。
`placeRuled` は同じ後続で `ruledHere` を呼ぶので二つ目が減り、`ruledHere` は同じ後続で `settlesHere` を呼ぶので一つ目が減る。
`settlesHere` は後続の先頭を除いた列で `ruledHere` と `movesForFollowing` を呼ぶので二つ目が減り、`movesForFollowing` が `fitsFollowingGo` に渡す列は後続より長くならないので一つ目が減る。
見出しを置く前の `keepFollowing` と奇数ページへの改ページは `rank` を増やさない（`rank_headingState_le`）。

`drainCarry` は、`waiting` とページの残りの段数の辞書式順序で止まる（`I4_drain_rank`）。
ページの終わりで次のページへ進むと、`drainOk` の下で最初の図版か最初の脚注の 1 行が新しいページに置かれ、`waiting` が減る。
`I4_paginate_ends` は、この全体が任意の有限の原稿で値を持つことを述べる。

内容の過不足と順序は、`Whole.lean` と同じく、出力済みの段と現在の段をつないだ列の不変条件で示す。
`I5_paginate_text` は、`paginate` が成功すれば、段落、続きの段落、定義の項、詩、コード、罫線つきのブロックの行と見出しが原稿の順に一度ずつ出力のページに並ぶことを証明する。
見出しの罫線つきのブロックは、見出しと同じく最初の行の id を一つだけ数える（`ruledText`）。
回り込み図版の id は、図版の列ではなく本文の列に、横の行の前に数える。
回り込み図版は待機中の図版があってもその場に置かれるので、図版の列に入れると原稿の順にならないからである。
箱と本の部の行と図版は、中身のフローの列として数える（`flowText` と `flowFigs`）。
この定理に、`paginate` の成功のほかの前提はない。
`I5_paginate_figures` は、図版と回した図版が原稿の順に一度ずつ並ぶことを証明し、この定理にも `paginate` の成功のほかの前提はない。
この定理は、出力済みの段、現在の段、待機中の図版をつないだ図版の列が、それまでに読んだ原稿の図版の列に等しいという不変条件から導く。
`paginate` が成功すれば、最後に待機中の図版は残らない。
各操作の補題（`step_placeNext` など）は、操作の前後で行と図版の列にどれだけ足されるかを `Step` の形で述べる。
`I5_parts_lines` は、`parts` が成功すれば、段落の `before` 番目からの行が一度ずつ順に置かれることを証明する。
この定理は二つの前提を置く。
一つ目に、改行器が、置いた行の数 `c` の後の行に、段落の最初の行の id に `c` を足した id から続く番号を振ること（`hb`）である。
golem-typeset は、行に `bUnitFirsts updated Map.! index + countBefore` から続く番号を振る（`modules/golem-typeset/src/Golem/Typeset/Flow.hs:4523` と `:3601`）。
段落の最初の行の id が改行し直すたびに変わらないことは、未確認である。
二つ目に、`hold` が行と図版を足さないこと（`hh`）であり、`keepPhysicalNext` の写しの `waitForPrior` はこれを満たす（`step_waitForPrior`）。
箱の中身を置く補題は、一段内側の `placeFlow` について同じことが成り立つこと（`InnerOk`）を前提とし、`level_ok` がすべての段数でこの前提を導く。

回した図版は、`Physical.hs` の `Waiting` と同じく、待機中の図版の列に図版と区別して入れる（`Waiting.turned`）。
新しいページを開くとき、`placeTurned` が列の先頭の回した図版にそれぞれ一ページを与え、続けて `placeDeferred` が先頭の図版を置く。
`placeDeferred` は回した図版で止まるので、図版と回した図版は列の順のままページに出る。
`placeTurned` は現在の段が空のときにだけ呼ばれ、閉じたページは出力済みのページの後ろに並ぶ（`ptg_step`）。
`I4_drain_rank` のページの終わりの場合は、先頭の回した図版を置けば列が短くなり、置かなければ先頭が図版か列が空であることから導く。

`PhysicalBoundary.hs` は、境界の入力を作って golem-layout の `paginatePhysical` に渡し、入力を `in` の行に、出力のページを `out` の行に書き出す。
入力は、段の容量 12〜80 sp の 1 段か 2 段の組で、1〜3 個の段落の組み合わせ、段落と図版と回した図版の 1〜4 個の並び、段落の間の制御、脚注つきの段落、単独と共有の罫線つきのブロック、縮めた段、`keep-with-next` と `no-break` の連鎖、節の開始と段組みの切り替えと戻し、見出しと定義の項とその後続、縮めた段の見出し、回した図版の前後の改段と改ページと図版、段落か見出しの後の詩とその後続、コードとその前後の保持と行アキ、見出しの罫線つきのブロックとその前後の見出しと保持と縮めた段、回り込み図版とその前後、見出しの行と本体の行とキャプションと脚注の組み合わせを変えた表とその前後、一つの段落か一つの詩の箱とその前後、段落と詩とスペースと保持を混ぜた箱とそのほかの中身の箱とその前後、段とページと見開きの本の部とその前後、ページか見開きの本の部の中の表、失敗する入力からなる。
さらに、脚注を繰り越す段の行数の変更とその後の段落か段組みの切り替え、行数の変更の後の段組みの切り替えと組の段に続く段落の入力を足した（[root ADR 0441](https://github.com/tett23/golem/blob/7e332092be2f3b7523faaa09d73a7e657f2ca27d/docs/adr/0441-index-columns-on-a-page-with-adjusted-lines.md) と [root ADR 0444](https://github.com/tett23/golem/blob/87b1cf391e1995235f957bb0c530640792b8a704/docs/adr/0444-keep-footnotes-in-order-while-one-continues.md)）。
さらに、待機中の図版の後に、横に収まらない最後の行が脚注を持つ回り込み図版と、スペースに続く表を置く入力を足した。
さらに、図版の前のフロー、図版の高さ、行数の上限、保持、段落の始めかを変えて、回り込み図版の横の段落の一部分を `trialParagraphPartLimit` で試す入力を `tw` の行に書き出す。
次の段へ送った部分は、送った先の段でもう一度試す。
id が 900 以上の行は、送り 14 sp、字面 12 sp とした。
最初の行の id が 385 の見出しには、`physicalHeadingBounds` として字面の始まり 4 sp と終わり 16 sp を与えた。
id が 702 と 705 の行には 3 sp、712 の行には 5 sp の `physicalWrappedBefore` を与え、箱 170 には 3 sp の `physicalBoxPadding` を与えた。
`PhysicalBoundary.lean` は `in` の行を読み、`Physical.lean` の `paginate` で評価して同じ形式で書き出す。
`PhysicalBoundary.hs` は、`paginatePhysical` が 100 MB を割り当てても終わらない入力を `out fail loop` と書き出し、`PhysicalBoundary.lean` は `noProgress` を同じく書き出す。
止まらないかどうかの判定には、壁時計の時間でなく、GHC の割り当ての上限（`enableAllocationLimit`）を使う。
初めは 2 秒で終わらない入力を `loop` としていたが、機械が混んでいたときに、終わる入力 `in 40 4 1 p:2,2,0:0,1,2 X:171:5:5:3,2,0:400,401,402 p:2,2,0:20,21` を一度 `loop` と書き出した。
割り当てたバイト数は、同じ入力と同じ GHC では機械の負荷によらないので、この判定は負荷で変わらない。
runghc で数えると、終わる 152126 個の入力が割り当てるのは多くて約 240 KB で、上の入力は約 109 KB だった。
`loop` になる 4 個の入力は、2 秒で 0.8〜8.1 GB を割り当てていたので、100 MB の上限には 1 秒以内に達する。
上限は終わる入力の最大の 400 倍を超えるので、終わる入力を `loop` とすることはない。
`loop` の判定は、`diff` で `Physical.lean` の `noProgress` と照らし合わされるので、Haskell の判定だけで決まることはない。
割り当てずに回るループに備えて、120 秒の壁時計の見張りも残すが、そこで止めた入力は `out fail hang` と書き出す。
`PhysicalBoundary.lean` は `hang` を書き出さないので、見張りが働けば `check.sh` は必ず失敗し、`loop` と取り違えることはない。
見出しの行の送りが 14 sp の表の 8 個の入力では、4 個が両方で `loop` になった。
`check.sh` は二つの出力を `diff` で比べ、156520 個の入力と 10368 個の試しですべて一致した。
写した計算を一つずつ替えると、`drainCarried` を外すと 308 個、組の段に組の縮みを渡さないと 474 個、組の段に脚注の行を確保しないと 356 個の入力で出力が食い違った。
`PhysicalBoundary.lean` の `firstNeed` は `Physical.hs` の `firstNeed` の写しで、評価のためのファイルなので `partial` を使う。

この照合の感度は、写した計算を一つずつ替えて確かめた。
食い違う入力の数は次のとおりだった。
見出しの罫線つきのブロックの数は 105552 個の入力で、回り込み図版の数は 110832 個の入力で、表の数は 120266 個の入力で、一つの段落か一つの詩の箱の数は 133642 個の入力で、混ぜた箱とそのほかの中身の箱の数はそれらの 12240 個の入力で、ほかの数はそれらを写す前の 80012 個の入力で数えた。
脚注では、行の脚注の区切りを除くと 4812 個、繰り越しの区切りを除くと 1152 個、`splitCarried` が分けた脚注の行を一つ減らすと 1152 個、`splitNotes` が脚注を途中で分けないと 6696 個、`fitting` から脚注の長さを除くと 11001 個である。
段落では、`fit` が待っているスペースを足さないと 281 個、強制した分割の `ShortPart` を除くと 9628 個、縮めた空の段で行が収まらないときに次の段へ進まないと 2 個である。
罫線つきのブロックでは、共有をやめて次の段へ送る分岐を除くと 179 個、`placeRuledKeeping` が後続を見ないと 116 個、共有する領域の長さを共有しない長さにすると 345 個、後の罫線を常に段の端の長さにすると 1510 個、段の外の余白を見ないと 1193 個である。
後続の保持では、`fitsFollowing` を常に真にすると 1446 個、`checkWaits` を除くと 2346 個、空の段でも待つ保持を記録すると 244 個、`firstNeed` から脚注の区切りを除くと 10 個、`firstNeed` が後の保持を見ないと 297 個である。
その他では、`need-lines` が縮めた空の段から進まないと 11 個、`page-lines` の下限を除くと 42 個、奇数ページの改ページが空白のページを入れないと 368 個、行アキの後の段送りを除くと 14 個、回した図版の前で改ページしないと 4520 個である。
節の開始では、空の段でも改段すると 48 個、空のページの判定で段を見ないと 6 個、前に `drainCarry` を呼ばないと 18 個である。
段組みでは、同じページで切り替える分岐を除くと 356 個、切り替えた段の先頭を 0 にすると 144 個、切り替えで脚注の長さを 0 に戻すと 69 個、次のページで切り替えるときに段の数を変えないと 142 個、戻しで段の数を戻さないと 90 個、戻しで次のページでなく次の段へ進むと 348 個である。
PR #1151 と #1152 を写した後に、見出しの罫線の置き方を変えると、前の罫線を常に見出しの領域の始めから置くと 97 個、前の罫線が直前の後の罫線の位置を見ないと 69 個、後の罫線を常に段の終わりの寸法で置くと 1331 個の入力で出力が食い違った。
見出しの罫線つきのブロックでは、前の罫線の領域を 0 にすると 11274 個、後の罫線の領域を 0 にすると 3280 個、前の罫線で `physicalHeadingBounds` を見ないと 2880 個、後の罫線で見ないと 864 個、後の罫線より先に前の罫線を外すと 1744 個、脚注の長さを 0 にすると 5181 個である。
さらに、`TallHeadingExtent` の分岐を除くと 422 個、`keepFollowing` を呼ばないと 410 個、`placeRuledKeeping` が後続の制御のないときに後続を見ないと 651 個、`fitsFollowing` が奇数ページの見出しの罫線つきのブロックを収まらないとすると 12 個、置く長さに `headingNeed` でなく見出しの長さを使うと 197 個、脚注を分けるときに後の罫線の領域を予約しないと 48 個、後の罫線の領域を使用長に足さないと 3260 個である。
回り込み図版では、横に収まる行の判定で図版の終わりを見ないと 130 個、脚注の 1 行を求めないと 448 個、表示した脚注の長さを足さないと 160 個、行の前のアキを足さないと 833 個、置くときに行の前のアキを足さないと 968 個、図版の終わりまでの長さを予約しないと 32 個、図版の後で使用長を図版の終わりまで進めないと 887 個、残りの行の前のアキを除くと 446 個、残りの行が収まらないときに次の段へ進まないと 192 個、図版の長さで `fit` を呼ばないと 1046 個である。
残りの行を置く前に次の段へ進まないと、4 個の入力で出力が食い違った。
図版の横に収まらなかった行は図版の下にも収まらないので、この写しでも `placeWrappedOverflow` が次の段へ進むが、進んだ段に行と脚注が収まるかを確かめない。
食い違うのは、待機中の図版の後の回り込み図版で、横に収まらない最後の行が脚注を持つ入力である。
待機中の図版が次の段の先頭に置かれ、その段には行が収まるが脚注は収まらない。
元の写しはその行をさらに次の段へ送り、変えた写しは行をその段に置いて脚注を繰り越す。
表では、見出しの行を繰り返さないと 2740 個、繰り返した直後の行を必ず置く判定を除くと 942 個、行の判定で脚注のすべてでなく 1 行を求めると 4 個、`tableNeed` の部分で脚注の 1 行でなくすべてを求めると 1062 個、`checkTableNotes` を除くと 736 個である。
さらに、行の後の予約を除くと 389 個、見出しの行の後の最初の行の予約を除くと 369 個、最後の行と下のキャプションを一つにしないと 571 個、表の前のアキを使用長に足さないと 865 個、下のキャプションと最後の行が空の段に収まるかの検査を除くと 192 個である。
`fit` に渡す長さから表の前のアキを除いても、出力は変わらなかった。
`tableFits` が成り立つ段では、どちらの長さでも `fit` は段を進めないからである（`tableAt_fields`）。
`tableReady` の条件から待っているスペースを除くと、2 個の入力で出力が食い違った。
食い違うのは、待機中の図版の後のスペースに続く表で、最初の部分がスペースを除けば段に収まり、スペースを含めると収まらず、待機中の図版を先頭に置く次の段にも収まらない入力である。
変えた写しでは、`tableReady` が今の段で止まり、`fit` が次の段へ進んで、収まらない段に最初の部分を置く。
元の写しは、最初の部分が収まる段まで進む。
箱では、`physicalBoxPadding` を見ないと 6688 個、余白のない箱でフローの前後の長さを 0 にすると 6166 個、部分の長さに脚注を含めないと 972 個、選んだ行数でなく収まる行数を置くと 176 個、部分の後の長さを使用長に足さないと 6354 個、脚注を分けるときに後の長さを予約しないと 208 個である。
詩の箱では、詩の行を箱の段落として置いた後に部分を開き直さないと 384 個、開き直した部分にも前の長さを足すと 288 個、開き直した部分の長さに前の長さを含めると 96 個、開いた部分を閉じないと 400 個、詩の行を箱の段落として置くときに既定の保持を使うと 800 個、`fitsFollowing` が箱を常に収まるとすると 704 個である。
箱の段落で、空の段でも `keep-all-lines` を緩めないと、評価が 300 秒で終わらなかった。
混ぜた箱では、単位の長さに前のアキを含めないと 1424 個、置くときに前のアキを足さないと 736 個、開き直した部分の最初の単位の前のアキを足さないと 48 個、`collectMixedBoxUnits` がアキを記録しないと 2080 個である。
さらに、区切りの判定で `keep-with-next` を見ないと 2400 個、段落の `keep-all-lines` を見ないと 352 個、段落の最初の部分の行数を見ないと 1656 個、最後の部分の行数を見ないと 1448 個、単位の段落の `keep-all-lines` を緩める分岐を除くと 984 個、箱の段落として置く単位に段落の保持でなく既定の保持を使うと 240 個である。
短い部分の `ShortPart` を除くと 1416 個、切った `keep-with-next` の `UnmetKeepNext` を除くと 1728 個、単位ごとの保持を見ずに箱の保持で区切ると 5072 個、`boxKeepLinks` が前の行を更新しないと 2400 個である。
そのほかの中身の箱では、余白を見ないと 1762 個、最初の行の長さ（`minimumSize`）を 0 にすると 224 個、`fit` を呼ばないと 224 個、前の長さを使用長に足さないと 936 個、後の長さを使用長に足さないと 440 個である。

本の部と本の部の中の表の数は、それらの 4224 個の入力で数えた。
本の部では、保持せずに中身を置くと 1347 個、次の単位で置き直さないと 1641 個、`SplitBookPart` を記録しないと 706 個、待機中の図版を待たないと 192 個、`nextUnit` が単位の境目まで進まないと 235 個である。
さらに、ページの単位を段で数えると 382 個、見開きの組を 1 と 2 のページから始めると 357 個、単位の先頭の空の段を見ないと 124 個、段の単位で置き直した結果でなく今の結果を確かめると 240 個、中身の `Env` に単位を与えないと 1156 個、単位を与えた定義の項を `keepFollowing` で置くと 32 個である。
`partFits` が置き始めたページより前の段も見るようにしても、出力は変わらなかった。
本の部の id は置き始めた段より後にしか現れないからである。
本の部の中の表では、行の前で見出しの行を繰り返さないと 752 個、部分の判定で脚注のすべてでなく 1 行を求めると 81 個、最後の行と下のキャプションを保持しないと 159 個、表の前のアキを使用長に足さないと 307 個、行の検査で段の数を掛けないと 96 個、最後の行の前で見出しの行を繰り返さないと 244 個、繰り返した見出しの行の後に行が収まらないときに次の段へ進まないと 321 個である。
`trial` が呼ぶたびに行う脚注の検査は、この照合の入力では確かめていない。
脚注を持つ入力は、どれも区切りと 1 行の和が段の容量以下だからである。

回り込み図版の横の段落の数は、10368 個の試しで数えた。
回り込みの領域を見ずに `fitting` で数えると 320 個、図版の終わりと比べずに行の終わりだけで数えると 320 個、行数の上限を見ないと 2824 個、領域の段を見ずにページだけで比べると 417 個、図版を置く前に `fit` を呼ばないと 3072 個である。
次の三つの写しは、変えても出力が変わらなかった。
`moveCursor` が使用長を図版の終わりまで広げる処理は、閉じた段の使用長が出力に現れないからである。
`fittingHere` が待っているスペースを足す処理は、`beginWrap` の `fit` が待っているスペースを使用長に移した後に試すからである。
図版の横の行を `putWrappedLine` でなく `putLine` で置いても出力が変わらないことは、`trialWrapRest_putLine` が示す。
`fittingHere` は、行の脚注のすべての行が図版の終わりの下に収まる行だけを数える。
そのとき、図版の残りを予約しても脚注のすべての行を段に表示するので、`putWrappedLine` は `putLine` と同じに行を置く（`putWrappedLine_eq`、`putHereLines_fitting`）。
`trialWrapRest_putLine` は、`trialWrapRest` が、行をすべて `putLine` で置く写し（`trialWrapRestLine`）と等しいことを示す。
前提は三つで、送りが正であること、回り込みの段が空でないこと、次の段が回り込みの段でないことである。
回り込みの段には `beginWrap` が図版を置き、`parts` はそこから後の段へだけ進むが、`parts` が引数に取る改行器と後続の判定についてこの二つは示していない。
`parts` は、この入力では照合せず、「実装との照合と全体の証明」の節で述べる `CausalBoundary.hs` の原稿で golem-typeset と照合する。
見出しでは、`headingOnly` を常に偽にすると 1444 個、`TallHeadingExtent` の分岐を除くと 29 個、`headingNeed` が脚注の全体を常に求めると 23 個、`headingNeed` から脚注の区切りを除くと 2 個、`putHeading` が見出しの長さを行の送りにしないと 3414 個である。
`keepFollowing` では、次の段へ送らないと 1292 個、仮の配置に脚注の長さを足さないと 8 個、待っているスペースを足さないと 30 個、後続の保持の行数を 1 行にすると 18 個、定義の項の長さを 0 にすると 324 個、定義の項の仮のスロットを見出しにすると 6 個である。
回した図版では、段の終わりでページを開くときに `placeTurned` を呼ばないと、回した図版を一度も置かないと、どちらも評価が 300 秒で終わらなかった。
待機中の回した図版があっても改段すると 46 個、回した図版の直後のページで改ページを省かないと 32 個、回した図版を空のページの先頭でなく空の段に置くと 72 個である。
回した図版をすぐに置く条件から待機中の図版がないことを除いても、出力は変わらなかった。
空のページの先頭で待機中の図版が残るのは、段に収まらない図版が待つときだけで、`FFigure` の検査がそれを除くからである。
詩では、収まる詩の行の数を行の数で数えると 2190 個、空の段か見出しだけの段で `keep-all-lines` を緩めないと 144 個、見出しだけの段を空の段と扱わないと 452 個、短い部分の `ShortPart` を除くと 1432 個、`placeStanzaWithNext` が送る詩の行を常に全体にすると 222 個、前の部分が空の段になったかを見ないと 382 個、`followingRows` が詩の行の数を表示の行の数でなく詩の行の数で返すと 1 個である。
選んだ詩の行を `Keep 1 1 False` でなく詩の保持で置いても、出力は変わらなかった。
選んだ行は保持の規則に合う区切りで、その行はすべて段に収まるからである。
コードでは、続きの行を数えないと 488 個、最初の部分でなくてもキャプションを足すと 380 個、最初の部分の最小の行数を 1 行にすると 278 個、空の段でも待っているスペースを足すと 7 個、スロットの格子の行数から続きの行を除くと 296 個、`fit` を呼ばないと 30 個である。
`fitsFollowing` では、見出しを常に収まるとすると 72 個、見出しの後を見ないと 18 個である。
`checkWaits` が見出しの行数を数える処理は、保持の求める行数が 2 行以上になるのは段落と詩が続くときだけなので、この照合では確かめていない。
待機中の図版を容量に等しい空きに置かないようにした場合と、`keep-all-lines` の段落を空の段でも緩めない場合は、評価が 120 秒で終わらなかった。
変えたモデルでは段を進めるループが止まらなくなるためと考えられるが、未確認である。
`flushPendingRule` が使用長を広げる処理を除いても、出力は変わらなかった。
この処理の後には必ず `nextColumn` が段を閉じ、閉じた段の使用長は出力に現れないからである。
同じ処理が置く罫線の位置はモデルに持たないので、この照合では確かめていない。

次の表は、Haskell の関数と Lean の定義の対応である。
Haskell の位置は `modules/golem-layout/src/Golem/Layout/` からの相対パスと行番号で示し、golem-typeset の位置だけはリポジトリからのパスで示す。

| Haskell | Lean |
| --- | --- |
| `Paginate/Physical.hs:303` `initial`、`:306` `limit`、`:309` `room`、`:312` `empty` | `initial`、`limit`、`room`、`empty` |
| `Paginate/Physical.hs:327` `close` | `close` |
| `Paginate/Physical.hs:334` `nextColumn`、`:364` `nextPage` | `fresh`、`nextColumn`、`nextPage` |
| `Paginate/Physical.hs:134` `Waiting`、`:371` `placeDeferred`、`:381` `placeTurned`、`:389` `afterTurned` | `Waiting`、`placeDeferred`、`placeDeferredGo`、`placeTurned`、`placeTurnedGo`、`opened`、`afterTurned`、`breakPage` |
| `Paginate/Physical.hs:394` `carryInto`、`:427` `splitCarried` | `carryInto`、`splitCarried` |
| `Paginate/Physical.hs:437` `fit` | `fit`、`dropAtTop` |
| `Paginate/Physical.hs:447` `putSlot` | `putSlot` |
| `Paginate/Physical.hs:457` `putLineWithReserve`、`:484` `splitNotes` | `putLineWithReserve`、`lineSep`、`lineNotes`、`lineNotesUsed`、`putLines`、`splitNotes` |
| `Paginate/Physical.hs:494` `fitting` | `fitting`、`fittingGo` |
| `Paginate/Physical.hs:506` `fittingWrapped`、`:520` `putWrappedLine`、`:527` `placeWrappedOverflow`、`:967` `placeFlow` の `FWrapped` | `fittingWrapped`、`fittingWrappedGo`、`putWrappedLine`、`putBeside`、`placeWrappedOverflow`、`overflowMove`、`overflowReady`、`placeWrapped` |
| `Paginate/Physical.hs:538` `splitAtBreak`、`Paginate/Decide.hs:258` `firstPart` | `splitAtBreak`、`firstPart` |
| `Paginate/Physical.hs:599` `trialParagraphPartLimit` | `trial`、`trialFrom`、`trialRest`、`checkRows`、`Part`、`trialWrap`、`trialWrapFrom`、`trialWrapRest`、`fittingHere`、`fittingWrapGo`、`putHere`、`putHereLines`、`limited` |
| `Paginate/Physical.hs:210` `PhysicalWrap`、`:240` `activeWrapEnd`、`:245` `endPhysicalWrap`、`:248` `movePhysicalCursor`、`:273` `beginPhysicalWrap` | `Region`、`wrapEnd`、`endWrap`、`moveCursor`、`beginWrap` |
| `modules/golem-typeset/src/Golem/Typeset/Flow.hs:4512` `paragraph`（`parts`） | `parts`、`nextItem`、`minimumFront`、`limitRank` |
| `modules/golem-typeset/src/Golem/Typeset/Flow.hs:4451` `tryVerses`、`:4464` `stanza` | `Beside`、`tryVerses`、`StanzaArgs`、`stanza`、`accept` |
| `modules/golem-typeset/src/Golem/Typeset/Flow.hs:4399` `probeNext`、`:4442` `probeChain` | `Probe`、`verseSpan`、`probeNext`、`probeChain` |
| `modules/golem-typeset/src/Golem/Typeset/Flow.hs:4307` `jobsFrom`、`:4331` `itemJobs` | `Jobs`、`jobsFrom`、`itemJobs`、`itemEnd` |
| `modules/golem-typeset/src/Golem/Typeset/Flow.hs:4360` `paragraphs` | `Paras`、`verseRows`、`paragraphs`、`groups`、`placeGroup`、`byGroups` |
| `Paginate/Physical.hs:646` `placeLines` | `placeLines` |
| `Paginate/Physical.hs:659` `checkPhysicalNotes`、`:667` `paginatePhysical` | `checkNotes`、`paginate` |
| `Paginate/Physical.hs:681` `drainCarry` | `drainCarry`、`drainOk` |
| `Paginate/Physical.hs:686` `placeAll`、`:692` `placeNext`、`:720` `occupies` | `placeAll`、`placeNext`、`beforeOf`、`placeBody`、`occupies` |
| `Paginate/Physical.hs:736` `checkWaits` | `checkWaits`、`checkWait`、`waitMet`、`markUnmet`、`addedSlots` |
| `Paginate/Physical.hs:751` `followingRows`、`:764` `keepAhead` | `followingRows`、`keepAhead`、`keepAheadGo`、`collect`、`soft`、`counts` |
| `Paginate/Physical.hs:784` `firstNeed` | `Env.firstNeed`（照合では `PhysicalBoundary.firstNeed`） |
| `Paginate/Physical.hs:839` `fitsFollowing` | `fitsFollowing`、`fitsFollowingGo`、`keepWanted_length` |
| `Paginate/Physical.hs:897` `placeWithNext` | `placeWithNext`、`keptBack`、`afterFront` |
| `Paginate/Physical.hs:938` `placeFlow` | `placeFlow`、`judgeNeed`、`adjustLines`、`ceilDiv` |
| `Paginate/Physical.hs:1048` `placeFlow` の `FBoxed`、`:1139` `placeBoxedParagraph`、`:1206` `placeBoxedStanza` | `Flow.boxed`、`placeBox`、`paddingExtra`、`boxExtra`、`boxNotes`、`fragmentSize`、`boxAvailable`、`boxCount`、`putBoxPart`、`placeBoxedParagraph`、`stanzaBoxSize`、`stanzaBoxCount`、`seal`、`reopen`、`placeBoxedStanza`、`nonemptyVerses` |
| `Paginate/Physical.hs:1050` `placeFlow` の混ぜた `FBoxed`、`:1083` `boxKeepLinks`、`:1094` `boxKeepMarks`、`:1098` `boxKeepCounts`、`:1102` `BoxUnitKeep`、`:1109` `boxUnitKeeps`、`:1124` `collectMixedBoxUnits`、`:1210` `placeBoxedStanzaWith` | `collectMixed`、`boxLinks`、`unitKeepsOf`、`unitEntries`、`mapsOf`、`BoxMaps`、`UnitKeep`、`unitGaps`、`linkBreaks`、`unitBoundary`、`atGroupStart`、`paragraphBreak`、`legalBreak`、`boundaryWarnings`、`relaxFor`、`fallbackKeep`、`unrelaxed`、`boxSelected`、`boxShort`、`putUnits`、`putStanzaPart`、`placeBoxedStanza` |
| `Paginate/Physical.hs:1051` `placeFlow` のそのほかの `FBoxed`、`:1068` `flowLines` | `placeGeneric`、`genericExtra`、`genericMinimum`、`placeFlows`、`Inner`、`level`、`flowDepth`、`flowsDepth`、`flowLines`、`bodyLines` |
| `Paginate/Physical.hs:861` `fitsFollowing` の `FBoxed` | `boxFits` |
| `Paginate/Physical.hs:121` `PendingRule`、`:1336` `placeRuledKeeping`、`:1345` `movesForFollowing`、`:1360` `joinsNext`、`:1370` `startsAfterOwnRule`、`:1384` `ruledHere`、`:1395` `ruledBefore`、`:1401` `ruleAfterInColumn`、`:1406` `settlesHere`、`:1423` `ruledLinesHere`、`:1436` `ruledLinesPlan`、`:1487` `placeRuled`、`:1690` `flushPendingRule` | `Pending`、`Pending.faceEnd`、`placeRuledKeeping`、`movesForFollowing`、`joiningNext`、`startsAfterOwnRule`、`ruledHere`、`hereOr`、`ruleAfterFits`、`ruleAfterFitsLast`、`ruleAfterPos`、`settlesHere`、`ruledLinesHere`、`ruledPlaceAt`、`placeRuled`、`ruledBefore`、`ruledAfter`、`ruledBeforeExtra`、`ruledAfterExtra`、`ruledJoin`、`ruledExtent`、`flushPendingRule`、`ruledRank`、`ruledAfterRules`、`sharedPriorPos`、`sharedCurrentPos`、`ruleAfterEdgePos`、`ruledBeforeFlow` |
| `Paginate/Physical.hs:880` `keepFollowingWaiting`、`:1487` `placeRuled` の `RuledHeading`、`:1524` `headingBeforeEdge`、`:1540` `headingEndBox`、`:1549` `headingDropsRules`、`:1569` `ruledHeadingHere` | `placeRuled`、`ruledHeadingHere`、`headingStateOf`、`keepFrom`、`headingBeforeExtra`、`headingBeforeAt`、`headingBeforeGeom`、`headingBeforeShared`、`headingBeforeSharedAt`、`headingSharedRules`、`headingWaiting`、`headingEndBox`、`headingDropsAt`、`headingDrops`、`lastLineSlot`、`ruleBeforeGapPos`、`headingAfterExtra`、`headingAfterAt`、`headingAfterGeom`、`headingAfterRule`、`headingLastFace`、`headingNextGap`、`headingRuleFits`、`headingReady`、`headingNotesExtent`、`putRuledHeading`、`ruledText`、`headingFirstPitch`、`headingBeforePos` |
| `Paginate/Physical.hs:1697` `waitFor`、`:1704` `waitForPrior` | `waitFor`、`waitForPrior` |
| `Paginate/Physical.hs:1940` `breakAt`、`:1956` `parityStart` | `breakAt`、`parityStart` |
| `Paginate/Physical.hs:320` `headingOnly`、`:873` `keepFollowing`、`:1715` `putHeading`、`:1722` `headingNeed`、`:1731` `placeHeading` | `headingOnly`、`keepFollowing`、`keepFrom`、`keepVirtual`、`keepWanted`、`putHeading`、`headingEnv`、`headingNeed`、`tallAt`、`placeHeading` |
| `Paginate/Physical.hs:549` `placeStanza`、`:915` `placeStanzaWithNext` | `placeStanza`、`wholeVerses`、`stanzaShort`、`placeStanzaWithNext`、`stanzaBack` |
| `Paginate/Physical.hs:1741` `placeCode` | `placeCode`、`codeExtent`、`codeMinimum`、`codeFit`、`codeFitting`、`codeCount`、`seek` |
| `Paginate/Physical.hs:1771` `tableNeed`、`:1778` `checkTableNotes`、`:1784` `tableReady`、`:1792` `placeTable` | `tableNeed`、`checkTableNotes`、`tableFits`、`tableAt`、`seek`、`tableCheck`、`tableFirstPart`、`placeTableFrom`、`tableCaption`、`placeTable` |
| `Paginate/Physical.hs:1903` `placeTableLinesReserved`、`:1913` `placeTableRows` | `putReserved`、`putRepeated`、`repeatedOf`、`tableRowsGo`、`tableTail`、`tableText` |
| `Paginate/Physical.hs:154` `retainPhysicalPart`、`:940` `placeFlow` の `FBookPart`、`Paginate/BookParts.hs:83` `slotIds` | `Flow.bookPart`、`PartUnit`、`retain`、`retainTry`、`settle`、`figureOk`、`partFits`、`minKey`、`lexMin`、`slotIds`、`unitKey`、`emptyUnit`、`nextUnit`、`advanceUnit`、`Env.retention` |
| `Paginate/Physical.hs:706` `placeNext` の `FDefTerm`、`:1043` `placeFlow` の `FTable`、`:1827` `placeTableAcross` | `placeBody`、`placeFlow`、`placeTableAcross`、`acrossGo`、`acrossTail`、`splitLast` |
| `Paginate/Physical.hs:985` `FSection`、`:1027` `FRestoreColumns`、`:1028` `FSwitchColumns` | `sectionStart`、`restoreColumns`、`switchColumns` |
| `FreeGeometry.hs:29` `faceOffset`、`:56` `ruleBeforeExtra`、`:59` `ruleAfterExtra` | `faceOffset`、`ruleBeforeExtra`、`ruleAfterExtra` |
| `FreeGeometry.hs:68` `ruleBeforeGap`、`:76` `ruleAfterGap`、`:83` `rulesSharedGap` | `ruleGapExtra`、`rulesSharedExtra` |
| `FreeGeometry.hs:97` `ruleBeforeEdge`、`:109` `ruleAfterEdge` | `ruleBeforeEdgeExtra`、`ruleAfterEdgeExtra` |

## 実装との照合と全体の証明

[root ADR 0352](../../docs/adr/0352-prove-pagination-in-lean.md) の完了の判定のうち、一般化できる性質の証明と実装との境界例の照合について、この節は済ませたことを述べる。
まだ済んでいないことは「未完の項目」の節に挙げる。

格子モードの改ページ全体は `Whole.lean` が扱う。
格子モードのすべてのフローについて、改ページ全体の終了と、段落、詩の行、回り込み図版の横の行、定義の項、表の行、見出し、コードの行、罫線つきのブロックの行の過不足と順序を証明した。
図版と転置図版の過不足と順序は、図版の高さと段の容量を 1 行以上、脚注区切りの行数を 0 行以上とし、箱の直後のブロックが罫線の領域を共有しない（`BoxesOk`）前提の下で証明した。
図版の高さの前提は、[root ADR 0440](https://github.com/tett23/golem/blob/0c204cb98782e325a9e04357176962419310d182/docs/adr/0440-reject-figures-of-zero-extent-across-the-lines.md) の後は golem-typeset が受け持つ。
行の方向の長さが 0 sp の図版は G07135 になり、行のない図版とともにページに置かれない（`Flow.hs` の `numberFigure`）。
`Whole.lean` の `admitFigures` はこの除外を写し、`I5_paginate_figures_admitted` は、除外を通したフローについて、図版の高さの前提なしに図版と転置図版の過不足と順序を示す。

### 境界入力の表

`modules/golem-layout/test/PaginateSpec.hs` の `boundaryTableTests` は、空の原稿と一行の原稿、容量 1〜3 行の段の段落、空の段にちょうど収まる図版と一行高い図版、図版を一〜三つ含む原稿について、Haskell の実装の終了、行と図版を原稿順に一度ずつ置くこと、空の段を残さないことを確かめる。
同じ表は、見出し、`need-lines`、`no-break`、行数を指定した `no-break`、`keep-with-next` を段落の間に置いた原稿についても、終了と、段落と見出しの行を原稿順に一度ずつ置くことを確かめる。
この原稿は、1〜5 行の段落、一行の見出し、2 行か 3 行の `need-lines`、`no-break`、3 行の `no-break`、1 行か 2 行の `keep-with-next` から一〜三つを並べ、最後に 1〜3 行の段落を置いたもので、段の容量は 2〜4 行である。
さらに同じ表は、箱、表、コード、罫線つきのブロック、詩、回り込み図版、脚注つきの段落を含む原稿についても、終了と、行を原稿順に一度ずつ置くことと、脚注の行を過不足なく置くか置けない脚注を診断することを確かめる。
この原稿は三組ある。
一組目は、0〜2 行の段落の後に一つの種類を置き、最後に 1〜3 行の段落を置いたもので、段の容量は 2〜5 行である。
二組目は、各種類の数例と `keep-with-next`、`no-break`、`need-lines` から二つを並べ、最後に 1 行か 2 行の段落を置いたもので、段の容量は 2〜4 行である。
三組目は、1 行か 2 行の段落の後に、一つの種類と、見出し、`keep-with-next`、`no-break`、`need-lines` のどれかを両方の順に並べ、最後に 1 行か 3 行の段落を置いたもので、段の容量は 3〜5 行である。
罫線は、段の中では 1 行、段の始めと終わりでは 2 行、前後の罫線が領域を共有すると 3 行を取る寸法にした。
コードは、一行が格子の 1 行を取る寸法と、上下に半行のアキを足した寸法の二つを使う。
さらに、`adjustInputs` の三組 3696 個の入力を足した。
一組目は、2〜6 行の脚注を持つ 1 行の段落、行数の変更、なしか 1 行の脚注を持つ段落か横の行に 1 行の脚注を持つ回り込み図版か 2 段組みへの切り替えと段落、1 行か 3 行の段落を並べたもので、段の容量は 3〜5 行である（[root ADR 0444](https://github.com/tett23/golem/blob/87b1cf391e1995235f957bb0c530640792b8a704/docs/adr/0444-keep-footnotes-in-order-while-one-continues.md)）。
二組目は、脚注のない段落か脚注つきの段落、行数の変更、2 段か 3 段への切り替え、1〜6 行の段落、1 行の段落を並べたものである（[root ADR 0441](https://github.com/tett23/golem/blob/7e332092be2f3b7523faaa09d73a7e657f2ca27d/docs/adr/0441-index-columns-on-a-page-with-adjusted-lines.md)）。
三組目は、横の行に脚注を持つ回り込み図版を段落の後か見出しなどの指定の後に置いたものである（[root ADR 0443](https://github.com/tett23/golem/blob/8873337addc24163574d69d33c20d4f95b67ac9b/docs/adr/0443-count-side-line-notes-when-a-wrapped-figure-fits.md)）。
さらに、`boxInputs` の 864 個の入力を足した。
この入力は、1〜4 行の脚注を持つ 1 行の段落と、行のない最後の部分を作るコードか横の行のない回り込み図版を箱に入れ、箱の後に 1 行の脚注を持つ 1 行の段落と 1 行か 2 行の段落を置いたもので、箱の前のアキは 0 行か 1 行、後のアキは 1〜3 行、段の容量は 3〜5 行である（[root ADR 0444](https://github.com/tett23/golem/blob/87b1cf391e1995235f957bb0c530640792b8a704/docs/adr/0444-keep-footnotes-in-order-while-one-continues.md)）。
さらに、`ruleInputs` の四組 2884 個の入力を足した。
一組目の 1080 個は、なしか 1〜2 行の段落の後に、後の罫線と、なしか前の罫線を持つ 1〜3 行の段落のブロックと、その後の罫線と領域を共有するブロック（1 行か 2 行の段落か 1 行の見出し）を置き、最後に 1 行か 2 行の段落を置いたもので、段の容量は 2〜6 行である。
二組目の 1260 個は、一組目と同じ組を版面の外に出してよい罫線（`keep-in-column = false`、余白 20 sp）で作り、前になしか 1 行の段落か 1 行の脚注を持つ段落を置き、共有するブロックの代わりに 1 行の段落も選べるようにしたものである。
三組目の 64 個は、罫線つきのブロックの後に段組みの切り替えと領域を共有しないブロックを置いたものである。
四組目の 480 個は、なしか 1〜2 行の段落の後に、後の罫線と、なしか前の罫線を持つ 1 行か 2 行の見出しのブロックと、その後の罫線と領域を共有するブロック（1 行か 2 行の段落か、1 行か 2 行の見出し）を置き、最後に 1 行の段落を置いたもので、段の容量は 2〜6 行である（[root ADR 0449](../../docs/adr/0449-share-rule-areas-with-ruled-headings-in-both-placements.md)）。
`Boundary.lean` は、これらの 55838 個の入力を `Whole.lean` の `paginate` で評価し、ページ、段、スロットとその格子の行、置いた罫線の位置、満たせなかった指定を書き出す。
`Env` は `paginate 1` の容量ごとの `Env` で、その引数は `Decide.hs` の `nextNeed`、`keptNeed`、`keepAhead`、`nextFirstLines`、`fitting`、`roomForLine` を写した関数と、`Code.hs` の `codeSpan` と `RuleArea.hs` の罫線の領域をこの寸法で求めた値である（`boundaryEnv`）。
`check.sh` は、`Whole.lean` を `.olean` にして `Boundary.lean` を四つに分けて並べて評価し、`Boundary.hs` が golem-layout の `paginate` に同じ入力を渡した出力と `diff` で比べる。
二つの出力は一致した。
`keep` などは整礎再帰で定義しているので、カーネルの簡約による `decide` ではなく、コンパイルした評価で比べ、`native_decide` は使わない。
`Boundary.lean` は証明ではなく評価のためのファイルなので、`Decide.hs` を写した関数に `partial` を使う。

この照合は、`boundaryEnv` の引数の写しの誤りを検出する。
段落、図版、見出しと指定だけの 20806 個の入力で `boundaryEnv` の引数を一つずつ替えると、食い違う入力の数は次のとおりだった。
`nextNeed` を何も求めない関数にすると 888 個、`keptNeed` を常に `none` にすると 802 個、`nextFirst` を常に 1 行にすると 148 個、`keepLast` を常に 0 行にすると 276 個、`fitting` を常に 1 行にすると 19701 個、`roomForLine` を常に偽にすると 1109 個である。

ほかの種類を含む 27588 個の入力でも、種類ごとに写した計算を一つずつ替えて、照合が誤りを検出することを確かめた。
食い違う入力の数は次のとおりだった。
箱では、`nextNeed` から箱の前の格子の行を除くと 28 個、箱の後の格子の行を除くと 6 個である。
表では、`nextNeed` から表の前のアキを除くと 78 個である。
コードでは、`codeSpan` からアキの 1 行を除くと 3267 個である。
罫線つきのブロックでは、段の中の罫線の領域を 0 行にすると 1120 個、段の始めの領域を 1 行にすると 1096 個、段の終わりの領域を 1 行にすると 437 個、共有する領域を 1 行にすると 2 個、`keepNextLines` を常に 0 行にすると 37 個である。
詩では、`nextNeed` の最初の部分を 1 行にすると 66 個である。
回り込み図版では、`nextNeed` から横の行の数を除くと 16 個である。
脚注では、`fitting` から脚注の行を除くと 2295 個、`roomForLine` から脚注の行を除くと 40 個、`nextNeed` の求める行から脚注の行を除くと 82 個である。
足した 3696 個の入力では、`drainPendingNotes` を外すと 336 個、組の後の段に組の縮みを渡さないと 192 個、`startSet` の縮みを 0 にすると 312 個、`typeAreaFree` を版面だけで測ると 184 個、回り込み図版を収める判定から横の行の脚注を除くと 769 個、`nextNeed` の回り込み図版から脚注を除くと 41 個である。
`boxInputs` の 864 個の入力では、箱を閉じた後の `drainPendingNotes` を外すと 40 個が食い違う。
置いた罫線の位置の照合の感度も、`Whole.lean` の罫線の計算を一つずつ替えて確かめた。
55358 個の入力で、段の中の前の罫線の起点を前の行でなく今の行にすると 667 個、段の始めの前の罫線を段の中の罫線として置くと 2398 個、共有する二つの罫線の起点の種類を入れ替えると 82 個、後の罫線の起点から前の罫線の領域を除くと 378 個、前の罫線と後の罫線を足す順を逆にすると 930 個の入力で出力が食い違った。
`flushJoin` の罫線を置かないと 1778 個、その罫線を常に段の中の罫線にすると 644 個、脚注のある段でも版面の外に出してよいとすると 96 個、段の始めの罫線を段組みの始まりの行によらず版面の外に出してよいとすると 6 個の入力で食い違った。
次の段で罫線を空にしないと 3073 個、段組みを始めるときに空にしないと 40 個の入力で食い違った。
`commitRuled` が置く後の罫線を常に段の中の罫線にする変更と、脚注のある段でも版面の外に出してよいとする変更は、出力を変えなかった。
この寸法では、段の端の後の罫線の領域（2 行）が段の中の領域（1 行）より大きく、段の中に収める段の終わりの後の罫線を `commitRuled` が置くことがないからである。
版面の外に出す段の終わりの後の罫線は、段の中の罫線と同じ sp の位置に置かれる。

境界入力の表のキャプションの行（改行位置の前後に一文字足す、画像に残る行が一行かゼロ行、キャプションが一行超過）は、実フォントの送りで Lean の側とも照合する。
golem-driver の `FigureSpec.hs` は、縦横比 1 対 3 の画像の図版に、図番号「F1」と全角空白の後に M を続けたキャプションを付け、Source Sans Pro と Source Serif で改行して図版を縮小して確かめる。
`CaptionFonts.hs` は、同じ設定（10pt、行送り 15pt、一行 12 字の行長 120pt）で、M を 10〜14 字続けたキャプションの図版を、容量 1〜4 行の段で golem-typeset に組ませる。
二つのフォントと五つの字数と四つの容量の 40 個の入力について、`CaptionFonts.hs` は、キャプションの項目、改行器の引数、段と画像の寸法を書き出し、golem-typeset が置いた改行位置、総デメリット、キャプションの格子の行数、画像の行数と寸法か G07038 を書き出す。
`CaptionValues.lean` は、同じ項目を `captionCompared` で改行し、`captionGridSpan` と `fitCaptionedFigure` で図版を求め、`check.sh` は二つの出力を `diff` で比べる。
二つの出力は一致した。

Lean に渡した計測結果は、`CaptionFonts.hs` の出力の `in fig` の行に残る。
M の送りは、Source Sans Pro で 476447 sp、Source Serif で 591135 sp である。
M の間の改行候補は幅を持つハイフンのペナルティ（ペナルティ 50）で、その幅は Source Sans Pro で 203817 sp、Source Serif で 203162 sp である。
改行位置の前後に一文字足す行は、Source Serif の 11 字（1 行）と 12 字（2 行）、Source Sans Pro の 13 字（1 行）と 14 字（2 行）である。
2 行のキャプションは改行器の pass 4 で改行され、総デメリットは 100022600 になる。
画像に残る行が一行の行は、1 行のキャプションの容量 2 行の段と、2 行のキャプションの容量 3 行の段である。
キャプションが段を埋める行は、1 行のキャプションの容量 1 行の段と、2 行のキャプションの容量 1 行と 2 行の段で、どれも G07038 になる。

`CaptionFonts.hs` は、項目を golem-typeset が置いたキャプションの行から作る。
行は、その行の項目と、幅を持つペナルティで終わればそのペナルティを持つので、行の項目をつなぎ、最後に強制改行を足すと原稿の項目になる。
ただし、行の間で項目が落ちないことが要るので、`CaptionFonts.hs` は、どの改行も幅を持つペナルティで、次の行がボックスで始まることを確かめる。
さらに、golem-layout の `breakParagraph` がその項目と引数から置いた行と同じ行を組み直すことと、字形を伸縮しないことと、`headingBlock` の行数が置いたキャプションの行数と一致することを確かめ、どれかが成り立たなければ止まる。
改行器の引数は、golem-typeset の `kpParams` と、`adjustedParams` の `pPullInFirst` を、段落スタイル `caption` について組版の設定から求め直したものである。
`adjustedParams` のほかの引数（`pStretchLimit` と `pAdjustOrder`）は、golem-layout の `breakParagraph` が行に写すだけで（`KnuthPlass.hs` の `mkLine`）、改行位置と調整比の計算には使わない。

照合の感度は、写した計算を一つずつ替えて確かめた。
`captionGridSpan` に行数より 1 多い行数を渡すと 40 個、ペナルティの幅を 0 にすると 4 個、`fitCaptionedFigure` の容量を 1 行増やすと 10 個、行長を 1pt 縮めると 4 個の入力で出力が食い違った。

### キャプションの評価値と改行器

`Pagination.lean` は、改行候補の選択、改行列からの行の組み立て、占有行数の計算を、評価値と幅を引数として証明する（`I1_caption_*`）。
評価値と幅の計算は、有限の入力で Haskell の改行器と照合した。
`CheckCaptionAssembly.hs --values` は、golem-layout の `badness`、`fitnessOf`、`lineDemerits` を境界の値で評価し、改行器が改行した 34586 個の入力について、項目、引数、各行の行長、字形の伸縮の引数、選んだ改行位置と、その総デメリット、各行の調整比、超過幅、字形の伸縮率、行長を書き出す。
入力のうち 24186 個はキャプションで、既存の 16806 例の入力に、突出と端のあるボックス、ソフトハイフン、突出、`pull-in-first`、緊急の伸びを使う引数を足したものである。
キャプションは行長が一つで、字形を伸縮しない。
残る 10400 個は、ほかの段落のための入力である。
2400 個は行ごとに行長が変わり（10 と 60、60 と 10、30 と 10 と 60、最後の行長がその後の行にも続く）、8000 個は伸縮するボックスを含み、`pExpansion` に上限まで刻める値、刻みが上限に届かない値、刻みが上限より大きい値、突出と `pull-in-first` と緊急の伸びとの組を与える。
`CaptionValues.lean` は、その入力を読み、`captionBadness`、`captionFitness`、`captionLineDemerits` の値と、`captionLineRanges` の行ごとに累積の幅（`captionSum`）の差から `captionLineEvaluationFrom` と `captionPathCost` で求めた総デメリットと、調整比、超過幅、`captionExpansionStep` の伸縮率、行長を書き出す。
`check.sh` は二つの出力を `diff` で比べ、すべて一致した。
直前の改行の読み飛ばし範囲に入る改行では、行の開始位置が改行位置より後になり、Haskell の伸びと縮みの和は負になる。
Lean の側も、伸びと縮みを項目の和ではなく累積の和の差として求めて、この値に合わせた。

照合の感度は、写した計算を一つずつ替えて確かめた。
24186 個のキャプションの入力では、行末の伸びを除くと 4384 個、緊急の伸びを除くと 155 個、隣接する fitness のデメリットを除くと 181 個、行頭の突出を除くと 529 個、ハイフンの突出を除くと 72 個、行末の端を除くと 1590 個、改行位置のペナルティの幅を除くと 1306 個、調整比の下限を除くと 850 個、`pull-in-first` を除くと 2 個、`cappedCubicBadness` の上限を 1291 にすると 1 個の入力で出力が食い違った。
行長と字形の伸縮の写しも、34586 個の入力で同じく替えて確かめた。
前の節点の行数でなく常に最初の行の行長を使うと 994 個、超過を測る行長だけを最初の行の行長にすると 6 個の入力で出力が食い違った。
伸縮による伸びを除くと 192 個、縮みを除くと 836 個、節点の生存の判定から縮みを除くと 655 個、上限を刻みの倍数に丸めないと 1410 個、`expansionOf` を正の無限大の向きに丸めると 2150 個、`expansionStep` の負の値を 0 の向きに丸めると 829 個の入力で出力が食い違った。
`expansionOf` の負の値を 0 の向きに丸める変更は、出力を変えなかった。
次の段落に書くとおり、`expansionOf` には負の幅が渡らない。

評価値は、改行器の走査にも渡した。
`Pagination.lean` の `captionEvaluate` は、`breakParagraph` の `evaluate` を写したもので、行の評価値に `captionLineSums`、`captionWidthEvaluation`、`captionPathCost` を使う。
行の目標の長さは、前の節点の行数（`nLine`）を `CaptionParams` の `lineWidth` に渡して求める。
字形の伸縮は、行の伸縮するボックスの幅に `captionReachedLimit` の上限を掛けた値（`captionExpansionOf`）を、伸びと縮みに加える。
Haskell の `div` は負の無限大の向きに丸めるので、Lean は `Int.fdiv` を使う。
読み飛ばす項目はボックスを含まないので、直前の改行の読み飛ばし範囲に入る改行でも、伸縮するボックスの幅の差は 0 であり、負にならない。
したがって、負の値の丸めの向きは照合では区別されない。
`mkLine` の伸縮率（`expansionStep`）は、調整比に上限を掛けた値を上限の範囲に収め、刻みの倍数へ負の無限大の向きに丸める（`captionExpansionStep`）。
Haskell は負の値を `floor` で、非負の値を `truncate` で丸めるが、非負の値では二つは一致する。
`captionContext` はこの評価を `I1_caption_*` の走査の引数（`CaptionScanContext`）に入れ、`captionCompared` は `breakParagraph` と同じ順に pass を試し、総デメリットの最も小さい経路を選ぶ。
`CaptionValues.lean` は、同じ 34586 個の入力を `captionCompared` で改行し、成功した pass、改行位置、総デメリットを書き出す。
`check.sh` はこれを golem-layout の `breakParagraph` の pass、改行位置、総デメリットと比べ、すべて一致した。
この照合は pass 4 で改行した 16833 個も含むので、救済した行と追い出した行の総デメリットも Haskell と一致する。

この照合の感度も、写した計算を一つずつ替えて確かめた。
24186 個のキャプションの入力では、許容度を見ないと 8991 個、節点の生存の判定から改行位置のペナルティの幅を除くと 790 個、緊急の伸びを除くと 1151 個、pass 3 を試さないと 155 個の入力で出力が食い違った。
超過を測る行の開始位置で読み飛ばしを数えないと 89 個、pass 4 の許容度を通常の許容度にすると 744 個、fitness を常に 2 にすると 518 個、強制改行を強制としないと 11993 個、最後の経路を総デメリットで選ばないと 2321 個の入力で出力が食い違った。
総デメリットの等しい経路から、最後の行の fitness と前の改行の列で選ぶ規則は、替えても出力が変わらなかったので、この入力では照合できていない。

不変条件 1 と 2 は、この評価について定理にした。
`I1_caption_compared_scan_ends` は、どの pass でも走査が終わることを示す。
`I1_caption_compared_lines` は、`captionCompared` が選んだ改行位置がキャプションを行に組み立て、行の数が節点の行数と等しく、行のボックスが原稿のボックスと順に一致することを示す。
`I1_caption_compared_deterministic` は、同じ項目と引数が同じ pass と改行位置を与えることを示す。
`I1_caption_overfull_pass_some` は、項目が強制改行（ペナルティ -10000 以下）で終われば、pass 4 が最後の項目までの経路を持つ節点を返すことを示す。
pass 4 の走査は能動節点を失わない。
進む節点がなければ、押し出した改行から走査し直すか、超過の最も小さい行で救済するからである（`CaptionOverfullHolds` と `captionOverfull_step`）。
最後の強制改行では前の節点がすべて終わるので、走査の終わりには最後の項目に節点がある。
`I1_caption_compared_some` は、この前提で `captionCompared` が `none` を返さないことを示す。
golem-layout と照合する入力（`CheckCaptionAssembly.hs` の `finish`）は、どれもこの強制改行で終わる。
`I2_caption_compared_diagnostic` は、組み立てた行の格子の行数が改行位置の数から決まり、その行数が段の空きを超えるのは行の高さが空きを超えるときに限ることを示す。
`I2_caption_compared_figure` は、その行数が段を埋めれば図版を返さず（G07038）、行が残れば縮小した図版の高さが残りの行に収まることを示す。

この対応に残ることは、「未完の項目」の節の一つ目に挙げる。

### `causalFreeFlow` のループ

[root ADR 0397](https://github.com/tett23/golem/blob/7fc360ff641d7eea6e8ee3ace30eca26e545334b/docs/adr/0397-paragraph-line-pitch-and-dimensional-spacing.md) の自由な配置の状態遷移のうち、`Physical.lean` の `paginate` が扱わない処理は、golem-typeset の `causalFreeFlow` のループである。
`Physical.lean` は、「自由な配置のモデル」の節に挙げたフローについて、終了、行の過不足と順序、図版と回した図版の過不足と順序を証明し、境界の入力で `paginatePhysical` と照合した。
整数行の `Whole.lean` は、自由な配置の証明とは扱わない。
golem-typeset の `causalFreeFlow` のうち、回り込み図版の横の段落を改行し直すループ（`parts`）、段落と連を順に置くループ（`paragraphs`）、詩を置くループ（`stanza` と `tryVerses`）、後続を試すループ（`probeNext` と `probeChain`）、図版ごとの仕事を進めるループ（`jobsFrom` と `itemJobs`）は、組んだ行と後続の判定を引数として写し、止まることを証明した。
`paragraphs` が段落と詩の行を過不足なく順に渡すことは証明した（`I5_paragraphs_groups`）。
`tryVerses` の試しは、それぞれ一つ前の試しが残したカーソルで組んだその詩の行の行を、ちょうど置く（`I5_tryVerses_lines`）。
`stanza` は、連の詩の行をそれぞれ一度ずつ、順に置く（`I5_stanza_lines`）。
一つの詩の行が置く行は、あるカーソルで組んだその詩の行の行か、段に入らない詩の行を表示の行で置く `paragraph`（`fallback`）が置く行である。
この定理は、`fallback` がその詩の行の行を置くことと、後続を待つ `hold` が行を置かないことを仮定する。
`stanza` が `fallback` の後に詩の行を一つ飛ばす写しでは、この証明が通らないことを確かめた。
`itemJobs` は、残りの図版のうち先頭から続く同じ項目の図版を一つずつ順に組み、その後の図版を残す（`I5_itemJobs_figures`）。
`jobsFrom` が一度の呼び出しで組む図版の群（`jobGroups`）は、図版を過不足なく順に分ける（`I5_jobGroups_join`）。
`retain` が試しのどれかの値を返すとき（`RetainOk`）、項目の図版の試しはその群の図版を組み、`jobsFrom` はその群の後の図版から続ける（`I5_jobsFrom_after_group`）。
`probeNext` と `probeChain` は後続が収まるかを返すだけでカーソルを返さないので、行を置かない。
`jobsFrom` と `itemJobs` は自分では行を置かず、行はすべて `outside`、`run`、`itemRest`、`finish` の呼び出し（`JobPiece`）が置く。
一度の `jobsFrom` が通る呼び出しの列（`jobPieces`）は図版の列だけから決まり、その列の `run` の図版は、図版の列と過不足なく同じ順に並ぶ（`I5_jobPieces_runs`）。
`I5_itemJobs_lines` と `I5_jobsFrom_lines` は、前提（`JobsLines`）のもとで、`itemJobs` と `jobsFrom` が置く行が、その列の呼び出しが置く行を一度ずつ順に並べたものであることを示す（`PieceChain`）。
前提は二つある。
一つは、`outside`、`run`、`itemRest`、`finish` が、それぞれ呼び出しごとの述語を満たす行を置き、図版を置かないことである。
もう一つは、`retain` が、行を置かずに進めたカーソルで試しを走らせ、その試しの値と、その試しのカーソルから行を置かずに進めたカーソルを返すことである。
`CausalBoundary.lean` では、`outside`、`itemRest`、`finish` がその位置の段落の行をちょうど置くこと（`stepAt_lines`）と、`retainPart` が後者の前提を満たすこと（`retainPart_retains`）を証明した（`jobs_lines`）。
`runJob` が、図版の前のフローの行、図版、図版に続く番号の行をこの順に置くこと（`runLines`）も証明した（`runJob_lines`）。
組む行の番号はカーソルの前に置いたテキストの長さから始まるので、`parts`、`stanza`、`paragraphs` が足す行は、どの段へ移っても、それぞれのカーソルのテキストに続く番号になる（`Counts`、`I5_paragraphs_counts`）。
`check.sh` は、4864 個の原稿で `runJob` を呼ぶたびにこれを確かめる検査（`premiseFailures`）を、写しの守りとして残す。
`I5_causal_jobsFrom_lines` は、前提を仮定せずに、これらの原稿の `jobsFrom` が置く行の過不足と順序を与える。

このうち `jobsFrom`、`itemJobs`、`paragraphs`、`parts`、`probeNext`、`probeChain`、`stanza`、`tryVerses`、`accept` は、`CausalBoundary.hs` と `CausalBoundary.lean` で golem-typeset の出力と照合する。
`CausalBoundary.hs` は、回り込み図版（2 × 3 画素の画像を幅 2zw か 3zw で行の始めに回り込ませたもの）の後に段落か連を置いた原稿と、回り込み図版をリスト項目の中に置いた原稿を、golem-driver のテストの偽のフォントと `alignment = "free"` の設定で golem-typeset の `layoutPdf` に渡し、ページか診断の一覧を書き出す。
段落は 5、12、25 字のいずれかで、段は 3〜6 行である。
段落だけの原稿は 1〜3 個の段落からなり、2 個か 3 個の段落の原稿には、段落の後に `@no-page-break` を挟んだものも含める。
連は、`line-breaks = "keep"` の段落スタイル `poem` の段落で、詩の行ごとに一つの単位になる。
連の原稿は、1〜4 行の連だけのもの、2 行か 3 行の連の前か後に段落を置いたもの（間に `@no-page-break` を挟んだものも含める）、2 行の連を二つ続けたものである。
後続と組む原稿は、後の 3 行と組む（`keep-with-next = 3`）段落スタイルの連（`poemk`）か段落（`held`）の後に、4 行の連か段落を置く。
後続と組む段落と連の後では、`keepPhysicalNext` が後続の行を待つ。
リスト項目の原稿は、回り込み図版をリスト項目の中に置き、`[composition]` の `keep-parts` を `"column"`、`"page"`、`"spread"` とした三つの設定でそれぞれ組む。
`"page"` と `"spread"` では、golem-typeset は項目を `itemJobs` と `retainPhysicalPart` で一つのページか見開きに保つ。
`"column"` では項目を保たず、図版の横の段落は項目の境を越えて続く（`composeBeside` の `sameItem`）。
リスト項目は 3 字か 15 字の段落で始まり、その後に図版と、図版の後の項目の段落が続く。
原稿は、図版の後に 1 個か 2 個の段落を置いた項目、図版を二つ持つ項目、図版を持つ項目を二つ続けたもの、項目の前か後に段落を置いたものである。
入れ子の項目の原稿は、図版とその後の段落を持つ項目の終わりに、5、12、25 字の段落一つからなる入れ子の項目を置き、その項目だけか、その後に段落か図版を持つ項目を置く。
`CausalBoundary.lean` は、同じ原稿で `Physical.lean` の `jobsFrom` を評価し、同じ形式で書き出す。
写したループの引数は、これらの原稿について golem-typeset が計算するとおりに与える。
改行器（`composeAt`）は偽のフォントに合わせて、行の幅に収まる字数を前から詰める関数とし、行の幅は、行の領域（`rowExtent`）が図版の除外領域と交わるときに除外の幅を引いた値とした。
除外領域の長さと幅は、図版の長さと幅にそれぞれ 1zw の `wrap-gap` を足した値である。

連の `ShortPart` と `SplitKept` が持つ行の番号は、golem-typeset では、`stanza` を呼んだときの `Built` の `bUnitFirsts`、つまりその時点の組みでその詩の行より前にある行の数で決まる。
そこで `Physical.lean` の `Beside` の `ident` は、詩の行の番号だけでなくカーソルも受け取る。
`CausalBoundary.lean` は、カーソルより前に置いた行と図版の数を与える。
同じく `Probe` の `verseRequired` は、最初の詩の行を試したカーソルも受け取り、試した詩の行はそのカーソルから組み直した行数、試していない詩の行は先に組んだ行数（`composeBeside` が図版の除外領域に合わせて組んだ行数）で数える。

リスト項目の段落は 2zw 字下げされ、一行に 10 字が入る。
入れ子の項目の段落は 4zw 字下げされ、一行に 8 字が入る。
行と図版の番号は、golem-typeset の `bUnitFirsts` と同じく、前に置いた行と図版の数である。
`CausalBoundary.lean` では、この数を置いたテキスト（`text`）の長さ（`slotCount`）とした。
見出しもコードも置かないこれらの原稿では、テキストは置いた行と回り込み図版の番号だけからなる。
図版の横に置かない段落（項目の始めの段落と、項目の外の段落）は、その幅で組んだ行の `FParagraph` として置く。
`retainPhysicalPart` が項目のものとして調べる番号（`flowSlotIds`）は、試しで新たに置いた行と図版の番号として与えた。
golem-typeset は、図版を組む段階で、除外領域が段より長い図版を一つずつ報告し（G07023）、`causalFreeFlow` に進まない。
`CausalBoundary.lean` も、そのような図版があれば、その数だけ G07023 を書き出す。

`check.sh` は二つの出力を `diff` で比べ、4864 個の原稿（段落だけの 1032 個、連を含む 1336 個、後続と組む 912 個、リスト項目の 1584 個）ですべて一致した。
照合が写しの誤りを見つけることは、写しを変えて確かめた。
以下の食い違いの数は、4864 個の原稿で数えた。
段落と連の後続の判定（`probeNext`）を常に収まるとすると 943 個（段落の後続だけなら 666 個）、`parts` が最後の部分の行数を見ずに続けると 383 個の原稿で出力が食い違った。
連については、`ident` を常に 0 とすると 1146 個、`stanza` が `splitAtBreak` を使わずに収まった詩の行をすべて置くと 1452 個、収まった詩の行の数で `accept` を呼ぶと 152 個、最後の部分が短いことを `total - whole ≤ keep.last` で判定すると 224 個、`accept` の `front` を `count - 1` とすると 23 個の原稿で食い違った。
`tryVerses` が置いた段がカーソルの段と同じかを見ない写しは、これらの原稿では出力が変わらない。
この確かめは、どの入力でも `tryVerses` の結果を変えないからである。
`trialWrap_placed_column` は、`trialParagraphPartLimit` の試しが行を置いたとき、置いた後のカーソルが試しの前と同じページと段にあることを示す。
試しが置く行は、`fittingHere` が段に収まると数えた行か、空の段に押し込む一行であり、`fit` が次の段へ送るのはそのどちらでもないときに限る。
この定理は、区切りの長さ（`separator`）とページの行送り（`pagePitch`）が負でないことを前提に置く。
`tryVerses_column_check_unobservable` は、これを使って、段の確かめを除いた写し（`tryVersesAnyColumn`）が `tryVerses` と等しいことを示す。
`CausalBoundary.lean` の `tryVerses_column_check_here` は、これらの原稿の設定がこの前提を満たすことを示す。
まだ試していない詩の行の行数（`orig`、`composeBeside` が組んだ行数）を 0 とする写しは、92 個の原稿で食い違った。
`orig` の行数は、後続の連の詩の行のうち `tryVerses` が試さなかったものの行数として、`probeNext` が求める後続の行数（`verseRequired`）に入る。
食い違った原稿では、後続と組む段落か連の後に `keepPhysicalNext` が置く待ちの行数が変わる。
たとえば 4 行の連のうち 2 行だけが段に収まると、3 行目を数えるかどうかで、待つ行数が段に置いた行数を超えるかが変わる。

`orig` の行は、連の前の改ページの禁止が待つ行数にも入るが、こちらは出力を変えない。
`paragraphs` は、連の前の制御を、連の詩の行の行を後続として置く（`verseRows`）。
後続の行は、`tryVerses` が置いた詩の行ならそのカーソルで組んだ行、置かなかった詩の行なら `orig` の行である。
改ページの禁止は、このうち連の最初の部分の行数を待つ（`followingRows`）。
この行数が `orig` を読むのは、`tryVerses` が置いた詩の行が最初の部分より少ないときに限る（`I5_noBreak_rows_orig`）。
一方、`stanza` が空でない段で `splitAtBreak` によって取る詩の行は、ないか、最初の部分以上である（`I5_splitAtBreak_firstPart`）。
したがって `orig` を読むとき、空でない段では、連はその段に詩の行を置かずに次の段へ進む（`I5_stanza_moves`）。
空の段では、改ページの禁止は待たずに満たされない印を付けるので、待つ行数を読まない。
次の段へ進んだ後の改ページの禁止の待ちは、その段が待ちの後に何も受け取らずに閉じたので、行数によらず満たされない（`Dead`、`waitMet` は少なくとも 1 行を求める）。
待ちを確かめるまでの `trialWrap`、`tryVerses`、`moveCursor` は待ちを読まずに運び（`setW`）、前の段へ戻らない（`Adv`）ので、`checkWaits` はどの行数でも同じ状態を返す（`checkWaits_sim`）。
そのため `parts` と `stanza` は、満たされない待ちの行数だけが違う二つのカーソルから、同じ結果を返す（`parts_sim`、`stanza_accept_sim`）。
`CausalBoundary.lean` の `I5_output_orig` は、これらをまとめ、`orig` の代わりにどの行を与えても、これらの原稿のページと診断が変わらないことを示す。
この証明は、閉じたページがカーソルの段より前にあること（`WO`）と、`paragraphs` の各段落の前で待ちがカーソルの段にあること（`Fresh`）を、`jobsFrom` の各部分が保つことを使う（`jobsFrom_congr`、`I5_paragraphs_orig`）。
改ページの禁止に渡す `orig` の行を、空にする写し、二倍にする写し、100 行にする写しは、4864 個の原稿のどれでも出力を変えなかった。
これらの原稿のうち、`orig` の行が改ページの禁止の待つ行数に入る呼び出しは 140 回ある。
リスト項目については、`itemJobs` が同じ項目の次の図版に進まないと 56 個、`jobsFrom` が `retainPhysicalPart` を通さずに試しを一度だけ置くと 745 個、`jobsFrom` が `itemJobs` の残した図版でなく自分の受け取った残りの図版で続けると 56 個の原稿で食い違った。
`jobsFrom` が終えた項目（`done`）を忘れる写しは、入れ子の項目を持たない原稿では出力を変えない。
それらの原稿では項目の段落がすべて最後の図版の横に置かれ、`outside` と `finish` が数え始める前の図版の横の段落の後には、終えた項目の段落が残らないためである。
入れ子の項目の段落は、外の項目の図版の横に置かれず（`composeBeside` の `sameItem`）、`itemJobs` が項目の残りとして置く。
`done` を忘れる写しはこの段落をもう一度置き、`"page"` と `"spread"` の入れ子の項目の原稿それぞれ 176 個のうち 154 個、計 308 個で食い違った。

### 置いた罫線の位置

置いた罫線の位置は、格子の上で `WholeRules.lean` が扱う（不変条件 3）。
`Whole.lean` の `St` と `PageOut` は、golem-layout の `sRules` と `poRules` を写した `rules` を持つ。
置いた罫線（`PlacedRule`）は、ブロックの id、前の罫線かどうか、位置を測る起点の格子の行、起点の種類（`RuleEdge`）、領域の行数を持つ。
起点の種類は、段の始め（`ruleBeforeAtStart`）、段の中（`ruleBefore` と `ruleAfter`）、段の終わり（`ruleAfterAtEnd`）、共有する領域の二つの罫線（`rulesJoined`）の五つで、段の始めと段の終わりは版面の外に出してよいかを持つ。
`planOf`、`commitRuled`、`flushJoin` は Haskell と同じ順に罫線を足し、`advanceFresh` と `startSet` は新しい段の罫線を空にする。
`Boundary.lean` は、起点の行と種類から `Boundary.hs` の罫線の寸法で sp の位置を求めて（`ruleAt`）、golem-layout の `prAt` と照合する。

`I3_commitRuled_column` は、`commitRuled` がページと段を変えず、前の罫線と後の罫線をその段の罫線に足し、ブロックの行を前の罫線の領域の後に置くことを示す。
`I3_planOf_before_in_column` と `I3_planOf_after_in_column` は、ブロックが二つの領域とともに段の空きに収まれば、`planOf` の罫線の領域が、ブロックの前に使った行から始まり、段の脚注の行の前で終わることを示す。
領域を共有する二つの罫線については、待つ罫線の起点の次の行が使った行であることを前提に置く。
`I3_placeRuledFresh_rules` と `I3_placeRuled_rules` は、`placeRuled` の結果が、この性質を満たす罫線とともにブロックを置いた `commitRuled` か、罫線を外して分けたブロック（`placeLines` か `putBlock`）であることを示す（[golem-driver ADR 0027](../../docs/golem-driver/adr/0027-paragraph-style-rules.md)）。
`I3_placeRuled_joined` は、領域を共有するブロックを罫線が待つ状態の段にそのまま置き、前のブロックの後の罫線と自身の前の罫線を、前のブロックの最後の行を起点に置くことを示す。
`I3_commitRuled_waiting` は、後の罫線を待たせたブロックが使った行を、待つ罫線の起点の次の行にすることを示す。
`I3_commitRuled_waiting_line` は、段落のブロックならその最後の行を同じ段の起点の行に置くことを示し、段落のブロックが 1 行以上を持つことを前提に置く。
`I3_advance_clears` と `I3_startSet_clears` は、次の段に進むか段組みを始めると、待つ罫線がなくなり、罫線が空になることを示す。
したがって、領域を共有する二つの罫線と、二つのブロックの行は一つの段に置かれる。
待つ罫線を置いてから次のブロックを置くまで使った行が変わらないことは、`Whole.lean` の `I3_waiting_used` が全体の不変条件として示す。
その間に `step` が通る処理は、`applyBreaks`、`needBefore`、`placeBlank` と、本の部の `placeBookPart` である。
図版の証明の不変条件 `Win` に、使った行が待つ罫線の起点の次の行であること（`used`）を足し、`commitRuled_used` が後の罫線を待たせたブロックの後でこれを示す。
`Win` を保つ処理はどれも使った行と待つ罫線を変えないので、`step` の列の途中のどの状態でも、罫線が待てば使った行はその起点の次の行である（`stepsOf_good`、`good_waiting_used`）。
本の部の中の `step` も同じく `Win` を保つ（`runFlows_figs`）。
そのため、`I3_waiting_rule_in_column` と `I3_placeRuled_joined` の前提 `hu` は、`I5_paginate_figures` の前提の下で、改ページのどの段階でも成り立つ。
この定理は、`BoxesOk` に、罫線つきの見出しが 1 行以上を持つことを足した。
行のない見出しは、格子の行を使わずに、見出しの格子の行の数だけ先の行から罫線を待たせるので、この性質を満たさない。
golem-typeset は、文字のない見出し（`# `）も 1 行の見出しとして組む（`Support.hs` の `layoutMini` で `headings.1` に `rule-after` を付けて確かめた）。

`I3_flushJoin_rule` は、`flushJoin` が置く後の罫線が段の中にあるのは、その領域が段の空きに収まるときに限ることを示す。
golem-layout は、後の罫線を待たせる前に、その罫線が段にとどまるかを確かめる（`Paginate.hs:768` の `settleRuled`、`:781` の `settlesAfter`）。
`Whole.lean` の `settleRuled` は、後続を渡した `planOf` の計画でブロックが収まり、後続がその罫線を段にとどめるときに限ってその計画で置き、そうでなければ後続を空にした `planOf` の計画、つまり後の罫線の領域をブロック自身のものとして数えた計画で置く。
後続が罫線を段にとどめるのは、本の部を開いた後続が領域を共有するブロックで始まり、そのブロックが同じ状態から `settleRuled` で置けるときか、待つ罫線を自身の領域に置いても段の空きに収まるとき（`ownFits`）である（`settlesOn`）。
`settleRuled` と `settlesOn` は互いを呼ぶので、後続の重さ（`flowsWeight`）と 1 か 0 の組を尺度とした。
`settleRuled` は本の部を開いた後続を渡すので重さが増えず、`settlesOn` は先頭のブロックを除いた後続を渡すので重さが減る（`flattenParts_weight`）。

`I3_settleRuled_rules` は、`settleRuled` の二つの計画のどちらでも、ブロックの罫線が段の中にあることを示す。
`I3_settleRuled_waiting` は、`settleRuled` が後の罫線を待たせたなら、後続がその罫線を段にとどめることを示し、`I3_settleRuled_used` は、そのときブロックが使った行が待つ罫線の起点の次の行であることを示す。
`I3_settlesAfter_rule` は、後続が罫線をとどめるなら、次のブロックが同じ段で領域を共有して置けるか、`flushJoin` の罫線が段の中にあることを示す。
`I3_waiting_rule_in_column` は、待つ罫線の直後のフローが領域を共有するブロックなら、`placeRuled` がそのブロックを二つの罫線とともに段の中に置くか、`flushJoin` の罫線が段の中にあることを示す。
前の版の golem-layout は、容量 3 行の段に、前後に罫線を持つ 1 行の段落と、その後の罫線と領域を共有する 1 行の段落を置くと、最初の段落の後の罫線を段の外に置いた。
今の版は、同じ入力（`Boundary.hs` の記法で `3 [R100:110:L1:10 R101:111:L1:20 P30:1]`）で、最初の段落が二つの罫線とともに空の段に収まらないので、罫線を外して 1 ページ目に置き（[golem-driver ADR 0035](../../docs/golem-driver/adr/0035-paragraph-rules-split-and-space-units.md)）、次の段落を 2 ページ目に置く。
`Whole.lean` も同じページと罫線を返す。

[root ADR 0449](../../docs/adr/0449-share-rule-areas-with-ruled-headings-in-both-placements.md) の後、格子の `placeRuled`（`Paginate.hs:729`）は、待つ罫線と領域を共有する印を持つブロックが同じ段で共有できないとき、待つ罫線を前のブロックの段に置いてから、ブロックを次の段から置く。
`Whole.lean` は、この分かれ目を `unjoined` に写した。
`I2_placeRuled_next_column`（`WholeRules.lean`）は、この場合に、待つ罫線が前のブロックの段に置かれ（`flushJoin`）、ブロックがその段より後の段から、待つ罫線も罫線もない状態で置かれることを示す。
そのため、ブロックの罫線は前のブロックの後の罫線と同じ段に入らず、重ならない（[root ADR 0449](../../docs/adr/0449-share-rule-areas-with-ruled-headings-in-both-placements.md) の不変条件 2）。
`Boundary.hs` は、罫線つきの見出しの後の罫線と、それを共有する罫線つきの段落または見出しの組を、段の容量と見出しの格子の行数を変えて照合に含む。

本の部の最初のブロックが前のブロックと領域を共有すると、`placeBookPart` の `nextUnit` が待つ罫線を置かずに次の段へ進み、前のブロックの後の罫線が失われる。
容量 7 行の段で、前後に罫線を持つ 1 行の段落の後に、領域を共有する 1 行の段落と 2 行の段落を `keep-parts = "page"` の本の部に入れると、golem-layout の `paginate` は罫線 100 の後の罫線を置かなかった。
golem-typeset は、リストの項目と定義の段落に罫線を付けず（`Flow.hs:2596`）、表は罫線つきのブロックでないので、本の部の最初のフローは罫線つきのブロックにならず、この入力は golem-typeset からは来ない。

### 脚注の順

脚注の行の原稿の注の順は、[root ADR 0444](https://github.com/tett23/golem/blob/87b1cf391e1995235f957bb0c530640792b8a704/docs/adr/0444-keep-footnotes-in-order-while-one-continues.md) の I1 が定めた。
この ADR の前は、容量 40 sp、送り 10 sp、区切り 0 sp の 1 段で、`[FParagraph (Keep 1 1 False) (5 行の脚注 500 を持つ 1 行), FAdjustLines 2, FParagraph (Keep 1 1 False) (1 行の脚注 510 を持つ 1 行), 1 行の段落]` を `paginatePhysical` に渡すと、脚注 510 が脚注 500 の続きより前に置かれた。
今の実装では、`@page-lines` が足した行を繰り越す脚注が先に取る（`drainCarried`、`drainPendingNotes`）ので、同じ入力で 1 ページ目に脚注 500 の全体が並び、2 ページ目に脚注 510 が置かれた。
`WholeNotes.lean` の `nm_drainPendingNotes` と `PhysicalNotes.lean` の `nm_drainCarried` は、出力済みの段の脚注、現在の段の脚注、繰り越す脚注をつないだ列を行に展開したものを、この移し替えが注ごとでなく列全体で保つことを示す。
`drain_room` は、格子モードで移し替えの後に繰り越す脚注が残れば、段の空きが、使わなかった区切りの行と、本文の行のない段に残す 1 行の和以下であることを示す（[root ADR 0444](https://github.com/tett23/golem/blob/87b1cf391e1995235f957bb0c530640792b8a704/docs/adr/0444-keep-footnotes-in-order-while-one-continues.md) の I2）。
注の id ごとの証明は、注の id ごとに出力の行を並べた列が、その注の 0 行目から最後の行までの列に等しいことを述べる。
不変条件は、出力済みの段の脚注、現在の段の脚注、繰り越す脚注をつないだ列を、注ごとに行の番号へ展開したものが、読んだ行の脚注を展開したものに注ごとに等しいことである（`WholeNotes.lean` と `PhysicalNotes.lean` の `Rel`）。
新しい行の脚注は、繰り越す脚注の前に今の段へ置かれることがあるので、この等しさは列全体ではなく注ごとに成り立つ。
この入れ替わりが同じ注の中で起きないために、原稿の注の id が互いに異なること（`Distinct`）を前提に置く。
golem-typeset は注の id を注の原稿上の範囲と番号から作る（golem-layout の `Look.hs:250` の `NoteId`、golem-typeset の `Structure.hs:114`）ので、実際の入力はこの前提を満たす。

原稿の注の順の全体（I1）は、格子モードで、箱と段組みの切り替えを含むフローについて証明した（`WholeOrder.lean` の `I1_paginate_order`）。
この定理は、原稿で注 a の印が注 b の印より前にあれば、ページの脚注の行の列が、a の行をすべて含む前半と、b の行をすべて含む後半に分かれることを示す。
ただし、a か b を置けない脚注として報告した場合は除く。
不変条件は、出力済みの段の脚注、現在の段の脚注、繰り越す脚注をつないだ列を行に展開し、置けない注の行を除いたものが、読んだ注の行を原稿の順に並べ、同じ注を除いたものに、列全体で等しいことである（`OR`）。
この等しさは、繰り越す脚注が残る段に、新しい注の行を置かないことに依る。
そこで、繰り越す脚注が残る段は何かを置いていて、区切りの行を除いた空きが 1 行以下であるという性質（`Ok`）を、すべての操作が保つことを示した。
段を進めると、`carryNote` が段の 1 行を残して繰り越す脚注を置くので、この性質が成り立つ。
`@page-lines` の後は、`drainPendingNotes` が空きを繰り越す脚注に渡すので、この性質が成り立つ。
罫線つきのブロックの行は後の行と罫線の行を取っておくので、その行数だけ空きが多いことを許し、ブロックの終わりで元の性質に戻ることを示した（`q_putRuledLines`、`q_commitRuled`）。

箱を閉じた後に繰り越す脚注を移す処理は、PR #1146 の前の golem-layout になかった。
そのころは、容量 5 行の 1 段で、前のアキ 0 行と後のアキ 2 行の箱に、3 行の脚注 500 を持つ 1 行の段落と 1 行のコードを入れ、箱の後に、1 行の脚注 520 を持つ 1 行の段落と 2 行の段落を置くと（`Boundary.hs` の記法で `[X100:0:2(Q0:1:0:3 C10:0:0:1:0:1) Q20:1:0:1 P30:2]`）、I1 が破れた。
`paginate 1 5` は、1 ページ目に脚注 500 の 0 行目を、2 ページ目にコードと段落 20 と脚注 500 の 1 行目と脚注 520 を、3 ページ目に脚注 500 の 2 行目を置いた。
箱の 2 ページ目の部分には行がないので、`closeBox` は部分を記録せず、箱の後のアキ 2 行を、使った行を進めないまま段に返し、後の注 520 がその空きに入ったからである。
今の golem-layout は、箱を閉じた後に `drainPendingNotes` を呼び、返した空きを繰り越す脚注に先に渡す（`Paginate.hs:606`）。
`Whole.lean` の `place` の `boxed` もこれを写す。
同じ入力で、2 ページ目にはコードと脚注 500 の 1 行目と 2 行目が並び、段落 20 と脚注 520 は 3 ページ目に置かれる。
箱、段組みの切り替え、行数の変更を含む 200000 個の無作為の原稿を今の golem-layout で調べると、反例はなかった。
箱の中に罫線つきのブロックを入れ、箱の後のアキを 0〜5 行、段の容量を 1〜4 行、求める脚注区切りを 0〜3 行に広げた 400000 個の無作為の原稿でも、反例はなかった。

`I1_paginate_order` は箱を含むフローも扱う。
前の版の不変条件 `Ok` は段の行数 `cap` が 1 行以上であることを含み、`flushJoin` があふれた段の使用行数を戻すときに、使用行数が負にならないか脚注の行があることを、これで示していた（`q_flushUsed`）。
箱の中の段では `cap` が箱の後のアキの分だけ減るので、後のアキが段の行数以上の箱では、この性質が成り立たない。
今の証明は、`cap` の条件を `Ok` から外し、`Whole.lean` の図版の証明と同じ二つの性質で、この場面を扱う。
一つは、後の罫線が待つ状態では、残りの行数が負でないか脚注の行があり、改ページ、`need-lines`、行アキが待っていないことである（`W`）。
もう一つは、後の罫線が待つのは、次のフローが罫線の領域を共有するブロックのときだけであることである（`JoinAhead`）。
罫線を待たない状態を `Base` が、待つ状態を `BJ` が表し、各フローの一歩は `BJ` と `Ok` と `JoinAhead` を保つ（`QS`）。
収まると判定して置いたブロックの後の状態は `W` を満たし（`qb_commit`、`commit_room`）、`flushJoin` はこの `W` から使用行数を戻す（`q_flushUsed`）。
`Base` は箱の中かどうかを引数に持ち、箱を開く段で箱の中にいないことを使う。
箱の中で箱を開くと、前の箱の後のアキが段に戻って空きが増え、`Ok` が保てないからである。

段組みの切り替えの証明は、フローの間の状態で使用行数が 0 以上であることに依る。
`startSet` は切り替える前の段の使用行数を新しい組の先頭の行（`firstLine`）にし、`carryRoom` はこの行を見ないからである。
先頭の行が負であれば、組の後の段は、繰り越す脚注を置いた後にも区切りの行を除いて 1 行より多い空きを持ちうるので、後の注の行がそこに入りうる。
そこで、使用行数が 0 以上であることを `Ok` に含め、すべての操作がこれを保つことを示した。
使用行数を減らして次のフローへ渡しうる操作は、後の罫線を独立した領域に置く `flushJoin` だけである。
段の空きが負のとき、`flushJoin` は使用行数を、段の行数から脚注の行数を引いた値に戻すので、脚注の行数が段の行数を超えると使用行数は負になる。
このとき段の空きは 0 行で、段は空でないので、1 行以上を取る後のブロックは次の段へ進む（`qb_placeRuledLow`）。
段が空でないことには、箱の始めの行が 0 以上であること（`Base` の `boxStart`）を使う。
`startSet` を通るのは、繰り越す脚注が残らない状態からである（`flushDeferred` の後、`q_startSet`）。
組の段が確保する脚注の行（`reserved`）と組の行数の変更（`setAdjust`）は 0 でなくてよく、`Base` は `reserved` が 0 以上であることだけを求める。
`advanceFresh` は組の次の段の使用行数を先頭の行に、脚注の行数を `reserved` に、行数の変更を `setAdjust` に戻すので、`carryNote` の後の段は、先頭の行が 0 以上であれば元の性質を満たす。
罫線つきのブロック、段組みの切り替え、行数の変更、行のない罫線つきのブロックを含む 1000000 個の無作為の原稿を今の golem-layout で調べると、I1 の反例も、負の先頭の行も、負の位置の行もなかった。

定理の前提は次のとおりである。
フローは箱の中に箱を含まず、見出しと罫線つきの見出しは格子の 1 行以上を取り、本文の行を持つ罫線つきのブロックは 1 行以上を持つ（`plainFlows false`）。
golem-typeset は、箱を持つ段落のフローだけを箱で包み（`modules/golem-typeset/src/Golem/Typeset/Flow.hs:3963`）、`joinBoxes` は箱の中身をつなぐだけなので（`Flow.hs:4021`〜`:4024`）、箱の中に箱はない。
箱の直後のブロックは、待っている後の罫線と領域を共有しない（`BoxesOk`）。
この前提は `I5_paginate_figures` と同じで、golem-typeset が作るフローの列では常に成り立つ（「格子モードの改ページ全体のモデル」の節）。
罫線つきのブロックの行は、golem-typeset が段落の行から作る（`modules/golem-typeset/src/Golem/Typeset/Flow.hs:3948` の `RuledLines kp boxes`）。
この前提は、`flushJoin` が使用行数を負にした段に後のブロックが置かれないことに使う。
golem-typeset は行のない段落を作らないので、実際の入力はこの前提を満たす。
`RuledLines` を作るのは `numberText` だけで（`Flow.hs:3948` と `:3950`）、その行は `composeUnit` が組んだ段落の行（`cuSingles`）である。
golem-layout の `composeInlinesTree` は段落の項目の列の最後に `lineEnd` を足し（`modules/golem-layout/src/Golem/Layout/Japanese.hs:458`）、`lineEnd` は強制改行のペナルティで終わる（`Japanese.hs:806`）。
`breakParagraph` の最後の pass は必ず成功し、強制改行の位置では必ず行を切るので、組んだ段落は 1 行以上を持つ。
回り込み図版の横で段落を組み直す `rebreakComposed` は図版の横の段落（`cuBesides`）だけを扱い、罫線つきのブロックを作らない。
罫線を持つ段落スタイルで、コメントだけの段落、脚注の印だけの段落、空の文字列の式だけの段落、エスケープした空白だけの段落、全角空白だけの段落を golem-typeset の `flowLines` に渡すと、どれも 1 行の `RuledLines` になり、`layoutPdf` はその行をページに置いた。
後にブロックのない `@style` は G02010 になり、語のない索引の印だけの段落は語と読みの段の数の誤り（G02042）になって、どちらもフローを作らない。
見出しの行数は、golem-layout の `headingBlock` が `max 1 least` 以上にする（`Paginate.hs:96`）ので、実際の入力はこの前提を満たす。
脚注区切りは 0 行以上で、段は 1 行以上である（`Hyp`）。
golem-layout は区切りを 1 行以上にする（`Paginate.hs:155`）。
段の行数は golem-typeset の版面の行の数で（`Flow.hs:736`）、実装はそれが 1 以上であることを確かめていない。
原稿の注の id は互いに異なる（`Distinct`）。

格子モードでは、`WholeNotes.lean` の `I5_paginate_each_note` が、原稿のどの注についても、ページに並ぶその注の行が 0 行目から最後の行まで一度ずつ順に並ぶことを示す。
ただし、置けない脚注として `unplaceableFootnote` を報告した注は除く。
`carryNote` は、空の段に脚注の行が入らないとき、その注の残りを捨てて報告するからである。
証明は、脚注区切りの行数を 0 行以上とする前提も置く。
繰り越す注の一つが途中までしか入らなかった後は段の残りが 0 行になり、続く注が先に置かれないことに、この前提を使う。
`I5_paginate_notes` は、原稿にない注の行がページに現れないことも示す。

自由な配置では、`PhysicalNotes.lean` の `I5_paginate_each_note` が同じことを、`Physical.lean` の `paginate` が成功し、注の id が互いに異なる（`Distinct`）入力について示す。
自由な配置では、入らない脚注は `footnoteTooTall` の失敗になり（`Physical.lean:386` と `:3053`）、`drainCarry` の後に繰り越す脚注が残れば `noProgress` の失敗になる（`Physical.lean:3068`）ので、除く注はない。
この注のモデルでは、コード行の脚注を配置対象として数えていない（`PhysicalNotes.lean:1085`）。
[root ADR 0482](../../docs/adr/0482-fix-note-loss-as-a-default-output-compatibility-exception.md) 後の本体は、コードのキャプションの脚注を先頭行へ付け、配置と分割の後も保持する。
この実装経路と注モデルの一般的な一致は未完了である。

### 区切り

[root ADR 0398](https://github.com/tett23/golem/blob/0d20d3e2e445d69aa576ec97615a51c31114ceec/docs/adr/0398-styled-separators-in-manuscripts.md) の区切りは、「区切りのモデル」の節の後に、次のところまで扱った。
格子モードのフロー生成と G07134 の後処理は、「区切りのモデル」の節のとおり `Whole.lean` の `Flow` の上に写し、不変条件 4 と 5 を当て、golem-typeset と照合した。
不変条件 4 と 5 は、`joinBoxes`、`ruledLinks`、`markBookParts` を通したフローと、自由な配置に写したフローにも当てた。
空の段に収まる保持に G07134 を返さないことは、格子モードの区切り一つと後続の段落について定理で示した（`I3_separator_hold_no_error`）。
`placeKept` が段落を分けて送る場合、区切りの後ろのアキ、区切りの連続も、定理の範囲に入る（`I3_separator_chain_no_error`）。
保持の中の `@need-lines`、区切りの前の行アキ、自由な配置は、まだ照合だけで確かめている。
段の行数を超える保持の中の `@need-lines`（G07037）を `settleHolds` が除かないと、格子モードで 140 個、自由な配置で 152 個、箱などを含む格子モードの組で 2 個の原稿で出力が食い違った。
`check.sh` は、区切りの原稿を十の組で golem-typeset と照合する。
格子モードと自由な配置の 8784 個ずつの原稿は、「区切りのモデル」の節で述べた項目の組み合わせである。
もう二組の 8640 個ずつの原稿は、項目に箱、前後に罫線のある段落、1 行のリスト項目を足し、段の容量を 3 行か 4 行にしたもので、格子モードと自由な配置で照合した。
保持の二組の 1440 個ずつの原稿（`holds` と `holds-free`）は、保持の後の段落に `@no-page-break` を続けたもので、格子モードと自由な配置で照合した。
この原稿は、なしか 1 行の段落の後に、`---` か `@separator scene`、なしか `---` か `@blank-line 1`、1〜3 行の段落、`@no-page-break` を置き、最後に 1〜3 行の段落か、1 行か 2 行の段落と `@no-page-break` と同じ行数の段落を置いたもので、段の容量は 2〜5 行である。
コードブロックを含む二組の 3136 個ずつの原稿（`code` と `code-free`）は、なしか 1 行の段落の後に、`---`、`@separator scene`、1 行か 3 行のコードブロック、1 行の段落から 1〜3 個を区切りを含めて並べ、最後に、なしか 1 行の段落か 1 行か 3 行のコードブロックを置き、コードブロックを一つ以上含むもので、段の容量は 3 行か 4 行である。
この二組では、コードのスロットを行の id の列で書き出す。
自由な配置では、`SeparatorPhysical.lean` の `flows` が写さないコードブロックを、`SeparatorBoundary.lean` の `freeFlows` が `FCode` に写す。
自由な配置は、`SeparatorBoundary.hs` が `alignment = "free"` の組版の設定で選ぶ。

最初と最後の部分を 1 行以上とする段落スタイルの二組（`split` と `split-free`）は、それぞれ 288 個の原稿を照合し、すべて一致した。
段の容量は 1〜6 行で、なしか 1〜2 行の段落の後に、可視の区切りと 2〜5 行の段落を置く。
区切り前後のアキは、既存の二通りの設定を使う。
この入力では、区切りの後の `keep-with-next` を 1 行から 2 行へ変える誤変更を検出する。
容量 3 行の段に本文 1 行、アキのない区切り、2 行の段落を置くと、正しい配置は最初の段に本文、区切り、段落の最初の行を置く。
誤変更では、区切りを次の段へ送る。
`root_adr0352_i3_separator_keep_sensitivity` は、この例の配置が誤変更の前後で異なることを、診断を除いて確かめる。

照合の感度は、写した計算を一つずつ替えて確かめた。
自由な配置では、アキを sp にせず行数のまま渡すと 696 個（箱などを含む組で 2709 個）、アキを捨てると 696 個（2658 個）、段の高さを行数と行送りの積にすると 4802 個（3403 個）、G07134 の判定を外すと 3404 個（5585 個）の入力で出力が食い違った。
箱の padding を渡さないと 3164 個、罫線を外すと 2020 個、前の罫線の外側のアキを 0 にすると 1124 個の入力で食い違った。
箱などを含む組では、`joinBoxes` を外すと格子モードで 49 個と自由な配置で 34 個、`ruledLinks` を外すと 86 個と 53 個、`markBookParts` を外すと自由な配置で 167 個の入力で食い違った。
罫線の共有の領域を 0 行にすると 36 個、段の始めの領域を 0 行にすると 1183 個、段の終わりの領域を 2 行にすると 1149 個、箱の前後を 0 行にすると 2870 個の入力で食い違った。
区切りの保持の位置の照合の感度も、同じく確かめた。
格子モードで `heldHere` を常に `false` にすると、`holds` で 420 個、これまでの格子モードの組で 24 個、箱などを含む格子モードの組で 2 個の入力で食い違った。
`keptNeed` の `holds` を常に `false` にすると 22 個、`chainedHeld` が `@no-page-break` の最初の部分を足さないと 40 個、`chainedHeld` の中の `holds` を常に `false` にすると 18 個の入力で、`holds` の出力が食い違った。
自由な配置で `heldHere` を常に `false` にすると、`holds-free` で 260 個、これまでの自由な配置の組で 4 個の入力で食い違った。
区切りの位置を一つも渡さないと、`holds` で 442 個、`holds-free` で 260 個、これまでの組で格子モードの 24 個、自由な配置の 4 個、箱などを含む格子モードの 2 個の入力で食い違った。
`keptNeed` と `chainedHeld` へのこの三つの変更は、`holds` の組を足す前の原稿では出力を変えなかった。
格子モードで `markBookParts` を外す変更、`joinBoxes` で何も結ばない変更、罫線の共有の領域を 1 行にする変更、`firstNeed` がアキを数えない変更は、出力を変えなかったので、この入力では照合できていない。
`markBookParts` の定義の項と表、入れ子のリスト、段組みが二つ以上の段、本文と行送りの違う段落スタイル、脚注を区切りと並べた原稿は、まだ照合していない。

## 未完の項目

[root ADR 0352](../../docs/adr/0352-prove-pagination-in-lean.md) は、42 件の対応、一般化できる性質の証明、実装との境界例の照合で移行の完了を判定し、未証明の項目や未説明の反例がある間は完了としない。
42 件の対応は `check.sh` が検査し、残っていない。
残るのは、次の項目である。
各項目には、完了の判定に欠けている根拠を書く。

1. `captionCompared` と golem-layout の `breakParagraph` の一致の証明。
   今は 34586 個の入力で照合しただけで、どの入力でも一致するという定理はない。
   総デメリットの等しい経路から最後の行の fitness と前の改行の列で選ぶ規則は、照合の入力でも区別されていない。
2. `causalFreeFlow` のループの、任意の入力についての行の過不足と順序。
   `I5_itemJobs_lines` と `I5_jobsFrom_lines` は前提 `JobsLines` を置き、前提なしの `I5_causal_jobsFrom_lines` は `CausalBoundary.lean` の 4864 個の原稿についての定理である。
   `I5_stanza_lines` は `fallback` と `hold` についての仮定を置き、`I5_parts_lines` の前提 `hb`（改行し直しても段落の最初の行の id が変わらないこと）は未確認である。
   欠けているのは、golem-typeset の改行器と後続の判定について、これらの前提を導く定理か、前提を確かめる照合である。
   `CausalFirstIds.lean` の四つの補題は、原稿順の採番を数の列の走査として表し、先行する単位の加算量が変わらなければ、現在の単位の行数を変えても先頭の id が変わらないことを証明する。
   この算術部分と `numberComposedFlow`、`besideFirsts`、`parts` の写しとの接続はまだなく、補題だけで `hb` を解消したとは扱わない。
3. 区切りの残り。
   保持の中の `@need-lines`、区切りの前の行アキ、自由な配置（`SeparatorPhysical.lean`）の保持の性質は、照合だけで確かめ、定理がない。
   `markBookParts` の定義の項と表、入れ子のリスト、段組みが二つ以上の段、本文と行送りの違う段落スタイル、脚注を区切りと並べた原稿は、照合していない。
   格子モードで `markBookParts` を外す変更、`joinBoxes` で何も結ばない変更、罫線の共有の領域を 1 行にする変更、`firstNeed` がアキを数えない変更は、出力を変えなかったので、照合の入力が足りない。
4. Alloy のコマンドの算術モデルと原稿の対応。
   見出しと最初の本文行の間か後ろに図版が一つある場合の算術モデルについて、任意の原稿列の図版の位置との対応は未証明である。
   見出し列の長さと段落構造を原稿列から取り出す一般的な対応も未証明である。
5. 照合できていない変更と、`putWrappedLine` の写しの前提。
   段の番号だけが異なる分割は、照合できていない。
   `trialWrapRest_putLine` の前提のうち、回り込みの段が空でないことは、`parts` の呼び出しについて示していない。
   `WrapPosition.lean` は、除外領域が現在位置より後にないことを `RegionPast` として表し、次の段が除外領域の外にあることを導く。
   `beginWrap` が返す状態は `RegionPast` を満たし、後続を保持する処理が位置を戻さなければ、成功した `parts` の結果も満たす。
   実装の `keepPhysicalNext` に対応する `waitForPrior` の保持では、要求の行数と判定が状態に依存しても、位置を戻さないことを導く。
   `root_adr0352_i3_trial_wrap_rest_put_line` は、この不変条件から次の段の前提を導く。
   `beginWrap` が返す状態には図版のスロットがあるため空でなく、`root_adr0352_i3_initial_trial_wrap_rest_put_line` は最初の試しについて両方の前提を導く。
   `WrapCalls.lean` は、除外領域内の段に局所のテキストがあることも `WrapReady` で表す。
   ここでのテキストは `textSlots` が数えるもので、回り込み図版のスロットも含む。
   `beginWrap` が返す状態は `WrapReady` を満たす。
   `partsEntrySafe` は `parts` と同じ分岐と減少尺度で再帰し、各再帰呼び出しの入力が `WrapReady` を満たすことを表す。
   `root_adr0352_i3_parts_entry_safe` は、改行器や保持の関数を問わず、この入力条件からすべての再帰入力の安全性を導く。
   各入力では `root_adr0352_i3_safe_parts_entry_trial` が `trialWrapRest_putLine` の両方の前提を導く。
   保持が実装と同じ `waitForPrior` の形なら、成功した `parts` の出力も `WrapReady` を満たす。
   `check-wrap-call-shape.sh` は、終端の戻り値を真に置き換えた `parts` の分岐が、この述語の分岐と一致することを確かめる。
   ただし、`causalFreeFlow` のすべての呼び出し元が `parts` に渡す状態について、この初期条件を導く接続は残る。
   `WrapVerses.lean` は、最初のカーソルが `WrapReady` を満たせば、詩の行を試す `tryVerses` の全再帰入力について同じ条件を保つことを示す。
   エラーで終わる試しの入力も含め、改行器と詩の長さを制限しない。
   `beginWrap` の返り値を直接使う入力では初期条件も導き、成功した詩の試しが返すカーソルでも `trialWrapRest_putLine` の前提を導く。
   写しの再帰分岐と定理の入力条件の分岐は `check-wrap-verse-shape.sh` で照合する。
   ただし、本体のすべての制御フローや詩の退避先を通る初期状態への接続は残る。
   公理と定理の依存、有限の実装照合との区別は [詩の試し置きの依存調査](../../docs/research/0352-wrap-verse-entry-dependencies.md) に記録する。
   `CausalStanza.lean` は、対応モデル `CausalBoundary` の任意の `Ms` について、成功した `stanza` と `accept` の出力のカーソルを扱う。
   その保持処理を `waitForPrior`、一つの詩の行の退避先を `parts` から導くので、カーソルを保つことを退避先の前提として置かない。
   `beginWrap` の返り値を直接使う `stanza` の入力では、成功結果の `WrapReady` も導く。
   証明は 4864 個の列挙入力には限らないが、対応モデルの `Ms` の範囲にとどまり、全実装の原稿や行の内容と順序の一般証明には広げない。
   前提と残りは [詩の配置と退避先の依存調査](../../docs/research/0352-causal-stanza-dependencies.md) に記録する。
   `CausalParagraphs.lean` は、このモデルの任意の `Ms` について、段落間の `noBreak`、`paragraphAt`、`paragraphs` の成功結果へ同じカーソルの条件を伝える。
   `beginWrap` の返り値から始める `paragraphs` では、成功した出力の `WrapReady` を、入力の `WrapReady` を別途仮定せずに導く。
   `CAUSAL_MODE=controls` の 216 ケースで、繰り返した制御の前後、空の本文、容量 1〜6 行の成功と失敗を実装と照合する。
   対応モデル以外の制御と、途中状態すべての接続は残す。
   公理と前提は [段落間の受け渡しの依存調査](../../docs/research/0352-causal-paragraphs-dependencies.md) に記録する。
   `CausalCalls.lean` は、処理全体の成功を前提にせず、モデルの `paragraphs` が試みる各入口の `WrapReady` を導く。
   前処理の結果、詩の試しの全再帰入力、通常の段落と詩の配置の入力、次の段落の入力を扱う。
   述語の分岐と再帰先は `check-causal-call-shape.sh` で写しと比べる。
   その時点の前提と残りは [各入口の依存調査](../../docs/research/0352-causal-call-entry-dependencies.md) に記録する。
   `CausalStanzaEntries.lean` は、モデルの `stanza` と `accept` の全再帰入力、詩の試しの全再帰入力、後続のプローブへの入力、保持の結果を検査する。
   警告の追加、移動、採用する詩の行数を減らす再試行、一行の退避先が、次の入力の `WrapReady` を保つことを導く。
   試し置きが返す各状態の条件は `tryVerses` から導き、処理全体の成功は前提にしない。
   相互再帰の分岐と引数は `check-causal-stanza-shape.sh` で写しと比べる。
   その時点の前提と残りは [詩の再帰入口の依存調査](../../docs/research/0352-causal-stanza-entry-dependencies.md) に記録する。
   `CausalProbeEntries.lean` は、モデルの `probeNext` と `probeChain` の各再帰入力、前処理後の入力、詩の試しの全再帰入力、通常の段落の試し後の入力を検査する。
   後続の行を調べる際に渡す `endWrap` 後のカーソルも扱う。
   処理の成功や、前処理がカーソルの条件を保つことを別途仮定しない。
   分岐と引数は `check-causal-probe-shape.sh` で写しと比べる。
   本体の全制御や組み直す状態全体の対応は残し、[プローブの入口の依存調査](../../docs/research/0352-causal-probe-entry-dependencies.md) に記録する。
   `PartsOffsetEntries.lean` は、段落の分割の各再帰入口で、テキスト数が最初の数 `base` と採用済み行数 `before` の和に等しいことを導く。
   この入口の条件があれば、対応モデルの改行器の採番を `base + before` から表せる。
   任意の状態がこの条件を持つと仮定せず、部分採用と再試行に沿って証明する。
   [採用済み行数の依存調査](../../docs/research/0352-parts-offset-dependencies.md) に、組み直す `Built` の採番表との接続が残ることも記録する。
   `PartsNumberedEntries.lean` は、この入口の条件と対応モデルの改行器を接続し、全再帰入口で行 ID が `base + before` から連続することを導く。
   任意の状態で `I5_parts_lines` の前提を仮定せず、到達する入口について証明する。
   配置結果全体の過不足と順序と、本体の `Built` の採番表との一致は残し、[入口の行 ID の依存調査](../../docs/research/0352-parts-numbered-entry-dependencies.md) に記録する。
   `PartsNumberedOutput.lean` は、この入口の条件を `parts` の成功結果へ接続し、以前の ID 列を残して新たな連続 ID 列だけを加えることを導く。
   具体的な対応モデルの `paragraphAt` では、採番と `hold` の条件も導く。
   これはモデルの ID 列についての導出であり、実装の文字列の全量と `Built` の対応は残る。
   [成功結果の依存調査](../../docs/research/0352-parts-numbered-output-dependencies.md) に、前提、24 境界、残件を記録する。
   `BuiltFirstIds.lean` は、所有する図版の採番量も変わることを含めた二段階の走査から、現在の段落の先頭 ID の不変を導く。
   export list だけを変更した一時コピーによる採番表の観測 12 件と、全原稿への射影が残ることを [二段階の採番の依存調査](../../docs/research/0352-built-first-id-dependencies.md) に記録する。
   `NumberedPayload.lean` は、既成行の列に採番するとき、内容と順序を保ち、その ID が既存の `PhysicalPagination.ids` の列と等しいことを導く。
   採用する先頭の行を分けた場合の一致と実装の行内容の観測は、[既成行の内容の依存調査](../../docs/research/0352-numbered-row-payload-dependencies.md) に記録する。
   異なる行列に再組版する文字列の全量の保存と、その後の配置への接続は残る。
   `ChosenSourceProgress.lean` は、選択された改行位置を走査履歴から導き、接尾部を一部採用するモデルのソース前進の条件を導く。
   実装の組み直し 36 接尾部と次の位置の照合 85 件、未接続の範囲を [ソースの前進の依存調査](../../docs/research/0352-chosen-source-progress-dependencies.md) に記録する。
   `RetryPrefix.lean` は、全行の配置後に末尾を減らす再試行の上限を導き、未指定から到達するモデルの各入口で未指定か正数の上限を保つ。
   実装 1344 入力と、上限 0 について条件が必要な例、未完のほかの再試行の条件を [再試行の上限の依存調査](../../docs/research/0352-retry-prefix-dependencies.md) に記録する。
   `RetryLastCounter.lean` は、末尾の保持四行の場合に再試行の上限が減らず、モデルの `noProgress` に到達する閉じた反例を kernel で確認する。
   実装の試し置き三件との一致と、修正が未実装であることを [末尾の再試行の反例](../../docs/research/0352-last-retry-counter-dependencies.md) に記録する。
   `BesideOwnership.lean` は、本文を選ぶキーの範囲、順序、重複のなさと、両判定が偽の単位での区切りを導く。
   五種類の判定の 781 通りと実装の走査 8203 件の照合、任意の生成表との対応が残ることを [所有区間の依存調査](../../docs/research/0352-beside-ownership-dependencies.md) に記録する。
   `BesideCoverage.lean` は、各キーを選ぶ必要十分条件と、区切りのない区間を連結した場合の一致を導く。
   2930 位置の所属判定との比較と、全内容の保存までの未接続部分を [選択条件の依存調査](../../docs/research/0352-beside-coverage-dependencies.md) に記録する。
   `BesideAdjustment.lean` は、組み直す本文の値の更新から、キーの有無と選択結果の保存を導く。
   実装の Map の 4492 更新と、全配置への接続が残ることを [更新前後の所有キーの依存調査](../../docs/research/0352-beside-adjustment-dependencies.md) に記録する。
   `SelectedCountPrefix.lean` は、選択キーの重複のなさと一つの値の更新から、内側の先行する本文の採番量が変わらないことを導き、二段階の先頭 ID の証明へ渡す。
   外側の全単位の寄与は別の条件として残し、[選択キーと先行する採番量の依存調査](../../docs/research/0352-selected-count-prefix-dependencies.md) に記録する。
   `BesideProducer.lean` は、新しく組む本文が段落だけを含むことから、図版のキーを含まないことと、図版を区切りとする判定を導く。
   実装 2540 ジョブの照合と、このモデルでは前のラウンドの再利用を扱わないことを [本文の生成と図版の区切りの依存調査](../../docs/research/0352-beside-producer-dependencies.md) に記録する。
   `BesideProducerRange.lean` は、一つのジョブのキーの範囲と順序、後の図版を越えないことを導き、前後のジョブの出力を分離する。
   532 個の実装の出力キーの比較と未接続の範囲を [新しい本文の生成範囲の依存調査](../../docs/research/0352-beside-producer-range-dependencies.md) に記録する。
   `BesideReuse.lean` は、前の本文の型の条件と再利用する区間の検査から、再利用と新規生成のどちらも現在の段落だけを選ぶことを導く。
   前後五件の実装の比較と、内容の一致と全ラウンドの接続が残ることを [本文の再利用条件の依存調査](../../docs/research/0352-beside-reuse-dependencies.md) に記録する。
   `BesideReuseRounds.lean` は、前の結果がない状態から任意のモデルのラウンド列へ型の条件を渡し、入力の有限な範囲から出力のキーの範囲を導く。
   実装の六回の計算との比較と、本体の全呼び出しとの接続が残ることを [複数ラウンドの本文の型の依存調査](../../docs/research/0352-beside-reuse-rounds-dependencies.md) に記録する。
   `BesideReuseOrder.lean` は、再利用を含む一つのジョブの順序と、後の図版による二つのジョブの分離を導く。
   実装の十三ジョブの比較と、Map との一般の接続が残ることを [再利用を含むジョブの順序の依存調査](../../docs/research/0352-beside-reuse-order-dependencies.md) に記録する。
   `PriorUnitCounts.lean` は、先行する図版の区切りと値の更新から、寄与の射影の外側の採番量を導き、二段階の先頭 ID の保存へ接続する。
   実装の十二件の再採番の比較と、単位の全分岐との一般の接続が残ることを [先行する単位の採番量の依存調査](../../docs/research/0352-prior-unit-counts-dependencies.md) に記録する。
   `MixedRoundOrder.lean` は、前後の所有者の条件から全ジョブの連結の狭義順序と重複のなさを導き、任意のモデルのラウンド列へ渡す。
   実装の六回の系列との比較と、本体の Map との一般の接続が残ることを [全ジョブのキーの順序の依存調査](../../docs/research/0352-mixed-round-order-dependencies.md) に記録する。
   `RoundPayloadStore.lean` は、重複しないキーから、生成済みの組の値を格納して同じキー順に読み戻す接続を導く。
   実装の Map の有限比較と、本体との一般の接続が残ることを [格納時の本文の値の保存の依存調査](../../docs/research/0352-round-payload-store-dependencies.md) に記録する。
   `ProducedPayloadKeys.lean` は、値を持つ新規生成と再利用からキー列の対応を導き、格納後の値の保存へ渡す。
   実装の組んだ行数と offset の比較と、整形と IO の一般の接続が残ることを [生成する値とキーの対応の依存調査](../../docs/research/0352-produced-payload-keys-dependencies.md) に記録する。

これらを終えるまで Alloy の定期実行と既存の参照を維持する。
終えたときは、Alloy の定期実行を終え、規則やモデルを変えたときにローカルの Lean で検証し直す手順を CONTRIBUTING に書く。

## 検査の手順

手元では次のコマンドで Lean 4.7.0 の証明を検査する。

```sh
lean experiments/pagination-proof/Pagination.lean
lean experiments/pagination-proof/Whole.lean
lean experiments/pagination-proof/Physical.lean
cabal build golem-layout golem-driver:tests
sh experiments/pagination-proof/check.sh
```

`check.sh` は、境界入力、自由な配置の境界入力、区切り、キャプションの評価値と実フォントの照合で `cabal exec` から `runghc` を呼ぶので、先に golem-layout をビルドしておく。
区切りとキャプションの実フォントの照合は golem-driver のテストの `Support.hs` を読み込むので、golem-driver のテストもビルドしておく。
照合に使う GHC は、`dist-newstyle/cache/plan.json` の `compiler-id` から選ぶ。
`check.sh` は `jq` でこの値を読み、対応する `runghc-<版>` に GHC のパスを渡すため、システムの既定の GHC が違う版でもよい。
コンパイラの版を別の plan から読む場合は `CABAL_PLAN` にパスを、別の `runghc` を使う場合は `RUNGHC` にパスを指定する。
`CABAL_PLAN` は、`cabal exec` が使うビルド成果物を切り替えない。
ドライバーを使う照合もローカルの package-id を明示し、同名のインストール済みライブラリと区別する。
`check.sh` は、`Whole.olean` と `WholeNotes.olean` を作ってから、それを読み込む `Separator.lean` を検査する。
`SeparatorBoundary.lean` は、`Boundary.olean`、`Physical.olean`、`SeparatorPhysical.olean`、`SeparatorBlocks.olean` を作った後に評価する。
`WholeNotes.lean` と `PhysicalNotes.lean` も、`Whole.olean` と `Physical.olean` を読み込んで検査する。
`PhysicalDrain.lean` は、`PhysicalNotes.olean` を作ってから、それを読み込んで検査する。
`WrapPosition.lean` は、`Physical.olean` を読み込み、除外領域と段の位置について証明を検査する。
`WrapCalls.lean` は、`WrapPosition.olean` を読み込み、各再帰入力の除外領域と非空性を検査する。
`check-wrap-call-shape.sh` は、`Physical.lean` の `parts` と入口の述語の分岐を比較する。
`WrapVerses.lean` は `WrapCalls.olean` を読み込み、詩の全再帰入力と成功結果のカーソルの条件を検査する。
`check-wrap-verse-shape.sh` は、`Physical.lean` の `tryVerses` とその入口の述語の再帰分岐を比較する。
`CausalStanza.lean` は `CausalBoundary.olean` と `WrapCalls.olean` を読み込み、詩の保持と退避先を具体化して成功結果のカーソルを検査する。
`CausalParagraphs.lean` は `CausalStanza.olean` を読み込み、前処理と段落間の成功結果のカーソルを検査する。
`CausalCalls.lean` は `CausalParagraphs.olean` と `WrapVerses.olean` を読み込み、失敗する試みも含む各入口の条件を検査する。
`CausalStanzaEntries.lean` は `CausalCalls.olean` を読み込み、詩の配置と採用の相互再帰の入口を検査する。
`CausalProbeEntries.lean` も `CausalCalls.olean` を読み込み、後続のプローブの相互再帰の入口を検査する。
`PartsOffsetEntries.lean` も同じファイルを読み込み、段落の分割の各入口のテキスト数と採用済み行数を検査する。
`PartsNumberedEntries.lean` は `PartsOffsetEntries.olean` を読み込み、到達する各入口の行 ID の条件を検査する。
`check-parts-numbered-shape.sh` は、その述語と元の `parts` の分岐と引数を比較する。
`PartsNumberedOutput.lean` は `PartsNumberedEntries.olean` を読み込み、到達入口から成功結果の行 ID の条件を検査する。
24 入力の有限検査は、Lean の実行結果を `check.sh` で `true` と比較する。
`CausalFirstIds.lean` は、採番の算術部分だけをほかのモデルを読み込まずに検査する。
`BuiltFirstIds.lean` はその出力を読み込み、二段階の走査と 648 入力、対照の 2 件を検査する。
`NumberedPayload.lean` は `Physical.olean` を読み込み、既成行の採番と ID の射影、分割する先頭の行の内容を検査する。
`ChosenSourceProgress.lean` は `Pagination.olean` と `Physical.olean` を読み込み、選択された接尾部の改行位置と部分採用からソースの前進を検査する。
`RetryPrefix.lean` は `Physical.olean` を読み込み、各再帰入口の上限と全行後の再試行の減少を検査する。
`RetryLastCounter.lean` も同じモジュールを読み込み、別の再試行が減少しない閉じた入力を検査する。
`RetryLastCounter.hs` は同じ行数と保持を実装の試し置きへ渡す。
`BesideOwnership.lean` は、有限のキーの走査の順序と重複のなさ、区切りでの分離を検査する。
`BesideCoverage.lean` は `BesideOwnership.olean` を読み込み、対象のキーを選ぶ必要十分条件と区間の連結を検査する。
`BesideAdjustment.lean` も同じモジュールを読み込み、値を更新した前後のキーの有無と選択結果を検査する。
`SelectedCountPrefix.lean` は `BesideAdjustment.olean` と `BuiltFirstIds.olean` を読み込み、選択キーから内側の先行する採番量の保存を検査する。
`BesideProducer.lean` は `BesideOwnership.olean` を読み込み、新しい本文の生成から図版の区切りの条件を検査する。
`BesideProducerRange.lean` は `BesideProducer.olean` を読み込み、新しい本文のキーの範囲と順序を検査する。
`BesideReuse.lean` は `BesideAdjustment.olean` と `BesideProducer.olean` を読み込み、再利用する区間の検査と新規生成から本文の型の条件を検査する。
`BesideReuseBoundary.lean` は `BesideReuse.olean` を読み込み、再利用の可否の具体例を検査する。
`BesideReuseRounds.lean` は同じモジュールを読み込み、複数ラウンドの型と有限範囲の条件を検査する。
`BesideReuseRoundsBoundary.lean` は `BesideReuseRounds.olean` を読み込み、ラウンド間の変更の具体例を検査する。
`BesideReuseOrder.lean` は `BesideReuse.olean` と `BesideProducerRange.olean` を読み込み、再利用と新規生成が混在するジョブの範囲と順序を検査する。
`BesideReuseOrderBoundary.lean` は `BesideReuseOrder.olean` を読み込み、再利用の組み合わせの具体例を検査する。
`PriorUnitCounts.lean` は `BesideReuseOrder.olean` と `SelectedCountPrefix.olean` を読み込み、先行する単位の寄与と二段階の先頭 ID の保存を検査する。
`PriorUnitCountsBoundary.lean` は `PriorUnitCounts.olean` を読み込み、寄与の更新と先頭 ID の具体例を検査する。
`MixedRoundOrder.lean` は `BesideReuseOrder.olean` と `BesideReuseRounds.olean` を読み込み、全ジョブのキーとラウンド列の順序を検査する。
`MixedRoundOrderBoundary.lean` は `MixedRoundOrder.olean` を読み込み、所有者の重複と逆順の対照を含む具体例を検査する。
`RoundPayloadStore.lean` は `MixedRoundOrder.olean` を読み込み、重複しないキーから格納する値の保存を検査する。
`RoundPayloadStoreBoundary.lean` と `check-side-store-shape.sh` は、格納の具体例と本体の格納呼び出しの形を検査する。
`ProducedPayloadKeys.lean` は `RoundPayloadStore.olean` を読み込み、生成する値とキー列の対応を検査する。
`ProducedPayloadKeysBoundary.lean` と `check-side-payload-shape.sh` は、経路ごとの値の受け渡しと本体の構築箇所の形を検査する。
`check-parts-retry-shape.sh` はその入口の述語と `parts` の分岐と引数を比べる。
`RetryPrefixChecks.hs` はネイティブの試し置きの採用数と、同じ再試行の上限を検査する。
`check-built-first-ids.sh` は、依存する package 環境を渡したローカルの `RUNGHC` で、export list だけを開いた一時ソースから本体の採番表を観測する。
`WholeOrder.lean` は `WholeNotes.olean` を読み込み、ほかの検査と並んで検査し、最後にその結果を待つ。
`WholeRules.lean` は `Whole.olean` を読み込み、同じくほかの検査と並んで検査する。
`WholeSlots.lean` は `Separator.olean` を読み込んで検査する。
`SeparatorPhysical.lean` と `SeparatorBlocks.lean` も同じく読み込み、`SeparatorBoundary.lean` は環境変数 `SEPARATOR_MODE` で十の組を一つずつ評価する。

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

`ForcedPrefix.lean` は [root ADR 0483](../../docs/adr/0483-finish-forced-paragraph-placement-without-repeating-the-retry.md)  の強制配置を採用する呼出し元の具体例を検査する。
公開の試し置きの採用数を保ち、以前の h6 の入力で行IDを一度ずつ配置することを確かめる。
任意本文の終了証明とは区別し、[検証範囲と公理依存](../../docs/research/0483-forced-prefix-placement.md)に記録する。

`PayloadRounds.lean` は、前の round の `(key, value)` の列から得た表を、次の round の再利用判定と読み出しへ渡す。
空の cache から始めた任意の列について、格納したキーの段落型を帰納で導き、順に並んだ図版 job の条件の下で同順の payload 読み出しを証明する。
`PayloadRounds.hs` は、実フォントの六つの変更で観測した行数と offset を渡し、cache の再利用と新規生成を通した列を照合する。
前の payload が新たな整形結果と一致する条件や、実装の IO とモデルとの一般的な対応は証明していない。
根拠と残件は [payload cache の帰納の依存関係](../../docs/research/0352-payload-rounds-dependencies.md) にまとめた。

`DerivedJobs.lean` は、現在の単位の添字を順に走査し、選ばれた図版だけから job を作る。
この生成から所有者の順序と図版の条件を導き、前の payload cache の帰納へ渡す。
`DerivedJobs.hs` は、実フォントの六つの変更で、生成した job が本体の所有者と単位数に対応すること、その job を使った cache の値を照合する。
本体の Map の列挙と添字の全入力での対応は残る。
根拠と残件は [図版 job の生成の依存関係](../../docs/research/0352-derived-jobs-dependencies.md) にまとめた。

`FigureTable.lean` は、現在の図版の組から格納表のキーの型を導き、表だけを選択する走査と図版を検査する走査の一致を証明する。
これにより、生成した表からの job の順序と図版の条件を接続する。
`FigureTable.hs` は containers の有限な表を、`FigureTableFonts.hs` は実フォントの六つの変更を比較する。
配置の計算や Map の列挙の全入力での対応は残る。
根拠と残件は [現在の図版の表の依存関係](../../docs/research/0352-figure-table-dependencies.md) にまとめた。

`FigureWindow.lean` は、格納した現在の図版を添字の範囲で読み戻すと、元の値と昇順を保つことを証明する。
その列からの job の選択が添字の走査と一致することも示す。
`FigureWindow.hs` と `FigureWindowFonts.hs` は、containers の有限な表と実フォントの六つの変更で、列挙と job と cache の出力を比較する。
本体の Map の実装、Int の添字、配置の計算との一般的一致は残る。
根拠と残件は [図版の表の昇順読み取りの依存関係](../../docs/research/0352-figure-window-dependencies.md) にまとめた。

`FigureJobValues.lean` は、選んだ図版の値を job の初期状態を作る callback へ渡す。
その値が元の組と格納表の同じキーの値であること、job の順序と図版の条件を保つことを証明する。
`FigureJobValues.hs` は異なる値を持つ有限な表を、`FigureJobValuesFonts.hs` は実フォントの図版の実際のソース位置を job の状態へ渡して比較する。
配置の全フィールドと IO、Map の実装との一般的な対応は残る。
根拠と残件は [図版値と job 状態の依存関係](../../docs/research/0352-job-values-dependencies.md) にまとめた。

`ClassifiedPrefix.lean` は、表を先に扱い、残りの単位は既存の skip と脇の本文の存在から分類する。
固定の採番増分か回り込み図版の増分を選び、対象より前の添字の列から、先行する所有者の範囲を導く。
到達した payload cache の型も使い、対象の本文の変更で先行する採番増分が変わらないことを示す。
`ClassifiedPrefix.hs` は、表、コード、改段の制御、回り込みの制御を含む実フォントの入力で比較する。
固定件数の計算と本体の全分岐との一般的な対応は残る。
根拠と残件は [単位の分類と採番 prefix の依存関係](../../docs/research/0352-classified-prefix-dependencies.md) にまとめた。

`OwnedFirst.lean` は、到達した cache と現在の図版の表から生成した job を使い、所有段落の先頭 ID の一致を導く。
対象より前の本文の分割、所有者の図版の型と先行する所有者の範囲を、最終定理の自由な前提として渡さない。
対象がその図版の選択に含まれなければ、所有段落だけの照会として `none` を返す。
この `none` を本体の全単位の ID が存在しないという意味には使わない。
`OwnedFirstFonts.hs` は、実フォントで配置した本文の行列を変え、本体の採番の前後と最後の公開定理を比較する。
全 `Built` からモデルの到達と job の所属を導く一般的な接続は残る。
根拠と残件は [到達した本文と所有段落の先頭 ID](../../docs/research/0352-owned-first-dependencies.md) にまとめた。
