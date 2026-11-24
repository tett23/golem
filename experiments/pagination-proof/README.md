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
段落が最後の行を保つ相手の行数（`Decide.hs:126` の `keptNeed`）、先の制御が求める最後の行数（`Decide.hs:151` の `keepAhead` の 2 番目の値、制御がなければ 0）、次の部分の最初の行数（`Decide.hs:214` の `nextFirstLines`）の三つである。
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
golem-typeset は、罫線つきのブロックを前の罫線を共有しないもの（`frJoined` が偽）として作る（`modules/golem-typeset/src/Golem/Typeset/Flow.hs:3897`）。
`ruledLinks` は、直前のフローが後の罫線を持つ罫線つきのブロックのときだけ共有を付け、箱の本体の中には入らない（`Flow.hs:4664`）。
golem-typeset は、箱を作ってから `ruledLinks` でブロックをつなぎ、その後で `markBookParts` が本の部を作る（`Flow.hs:4165`、`:4166`、`:4212`）。
`markBookParts` はフローを本の部で包むだけで、並びを変えない（`Flow.hs:4540`）。
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
| `Paginate.hs:259` `needMore` | `needMore` |
| `Paginate.hs:271` `needAfterSpaces` | `needAfterSpaces` |
| `Paginate.hs:283` `needBeforeSpaces` | `needBeforeSpaces` |
| `Paginate.hs:292` `placeSpace` | `placeSpace` |
| `Paginate.hs:302` `needBeforeSpace` | `needBeforeSpace` |
| `Paginate.hs:319` `needBefore` | `needBefore` |
| `Paginate.hs:330` `waitsBehind` | `waitsBehind` |
| `Paginate.hs:337` `waitsFor` | `waitsFor` |
| `Paginate.hs:361` `placeBlank` | `placeBlank` |
| `Paginate.hs:379` `applyNeed` | `applyNeed` |
| `Paginate.hs:389` `adjustLines` | `adjustLines` |
| `Paginate.hs:403` `placeFlow` | `placeFlow`、`previousKeep` |
| `Paginate.hs:427` `placeKept` | `placeKept`、`keptCut` |
| `Paginate.hs:447` `waitFor` | `waitFor` |
| `Paginate.hs:458` `checkNoBreak` | `checkNoBreak`、`linesIn` |
| `Paginate.hs:470` `slotLineCount` | `slotLineCount` |
| `Paginate.hs:476` `applyBreaks`、`:479` `applyBreak` | `applyBreaks`、`applyPending` |
| `Paginate.hs:491` `startBefore` | `startBefore` |
| `Paginate.hs:572` `place` の `FSection` | `place` の `sectionStart` |
| `Paginate.hs:504` `applyBreakKind` | `applyBreakKind` |
| `Paginate.hs:514` `breakPage` | `breakPage` |
| `Paginate.hs:522` `place` | `place`、スペースは `placeSpaceFlow` |
| `Paginate.hs:524` `place` の `FBookPart` | `place` の `bookPart`、`runFlows` |
| `Paginate.hs:597` `place` の `FBoxed` | `place` の `boxed`、`boxEnd` |
| `Paginate.hs:574` `place` の `FSwitchColumns`、`:580` `FRestoreColumns` | `place` の `switchColumns`、`restoreColumns` |
| `Paginate.hs:612` `placeCode` | `placeCode`、`codeCount`、`codeSpanOf` |
| `Paginate.hs:638` `placeLines` | `placeLines`、`placeLinesGo`、`lineCount`、`shortParts` |
| `Paginate.hs:561` `place` の `FWrapped` | `place` の `wrapped` |
| `Paginate.hs:678` `placeStanza` | `placeStanza`、`placeStanzaGo`、`versesFitting`、`stanzaK0`、`stanzaK2`、`putVerses`、`shortVerse` |
| `Paginate.hs:725` `placeRuled` | `placeRuled`、`placeRuledFresh` |
| `Paginate.hs:756` `commitRuled`、`:769` `splitRuled`、`:785` `flushJoin` | `commitRuled`、`putRuledLines`、`splitRuled`、`flushJoin` |
| `Paginate.hs:800` `placeTable` | `placeTable`、`tableRowsGo`、`withCaption`、`putRepeated` |
| `Paginate.hs:825` `placeTableAcross` | `placeTableAcross`、`acrossGo`、`tableGroups`、`mustRepeat`、`retainsTail` |
| `Paginate/BookParts.hs:13` `placeBookPart` | `placeBookPart`、`partTrial`、`fitsPart`、`unitKey`、`emptyUnit`、`nextUnit`、`nextSpread`、`hasNested` |
| `Paginate/BookParts.hs:60` `flattenBookParts` | `flattenParts` |
| `Paginate/BookParts.hs:66` `flowSlotIds`、`:83` `slotIds` | `flowSlotIds`、`flowsSlotIds`、`slotIds` |
| `Paginate/State.hs:139` `initialState` | `initialState` |
| `Paginate/State.hs:149` `cap`、`:157` `free`、`:164` `typeAreaFree`、`:171` `isEmpty` | `cap`、`boxAfter`、`free`、`typeAreaFree`、`isEmpty`、`boxTop` |
| `Paginate/State.hs:183` `atBoxStart`、`:189` `openBox`、`:198` `closeBox` | `atBoxStart`、`openBox`、`boxEnd` |
| `Paginate/State.hs:214` `keep` | `keep` |
| `Paginate/State.hs:222` `parityStart` | `parityStart` |
| `Paginate/State.hs:228` `blankPage` | `blankPage` |
| `Paginate/State.hs:231` `putSlot` | `putSlot` |
| `Paginate/State.hs:238` `putLineKeeping` | `putLineKeeping`、`putLine` |
| `Paginate/State.hs:256` `putBlock` | `putBlock` |
| `Paginate/State.hs:278` `splitNotes` | `splitNotes` |
| `Paginate/State.hs:288` `closePage` | `closePage` |
| `Paginate/State.hs:295` `nextColumn`、`:298` `nextPage` | `nextColumn`、`nextPage` |
| `Paginate/State.hs:301` `advance` | `advance`、`advanceIn`、`advanceFresh`、`advanceTurned`、`openColumn` |
| `Paginate/State.hs:339` `startSet` | `startSet` |
| `Paginate/State.hs:365` `pageFigure` | `pageFigure` |
| `Paginate/State.hs:372` `carryNote` | `carryNote`、`carryRoom`、`carryShown` |
| `Paginate/State.hs:387` `placeDeferred` | `placeDeferred` |
| `Paginate/State.hs:396` `flushDeferred` | `flushDeferred` |
| `Paginate/State.hs:402` `flushFigures` | `flushFigures` |
| `Paginate/Decide.hs:243` `splitAtBreak` | `splitAtBreak` |
| `Paginate/Decide.hs:284` `needIn` | `needIn` |
| `Paginate/Decide.hs:291` `headingNeed` | `headingNeed` |
| `Paginate/Decide.hs:298` `tableHead` | `tableHead` |
| `Paginate/Decide.hs:322` `afterPageFigure` | `afterPageFigure` |
| `Paginate/Decide.hs:328` `startsRecto` | `startsRecto` |
| `Paginate/Decide.hs:350` `bodySize`、`:364` `joinsNext` | `RuledBody.size`、`joinsNext` |
| `Paginate/Decide.hs:374` `planOf`、`:409` `planNeed`、`:413` `planParts` | `planOf`、`Plan`、`planNeed`、`planParts` |

## 区切りのモデル

`Separator.lean` は、[root ADR 0398](https://github.com/tett23/golem/blob/0d20d3e2e445d69aa576ec97615a51c31114ceec/docs/adr/0398-styled-separators-in-manuscripts.md) の区切りを扱う golem-typeset の四つの関数と、`round'` が診断を足す処理を、`Whole.lean` の `Flow` の上に写したものである。
`space` は、`blocks` の局所関数 `spaceSeparators`（`modules/golem-typeset/src/Golem/Typeset/Flow.hs:2491`）の `go` を写す。
この関数は、可視の区切りの後に 1 行の `keep-with-next` を足し、区切りとの境界の行アキを一つのアキに置き換える。
足す `keep-with-next` は区切りの位置を持つ（`Flow.hs:2523`）。
`holdNeeds` は、`space` の後に働く `holdSeparatorNeeds`（`Flow.hs:2458`）を写す。
区切りの保持は、可視の区切りから、区切り、アキ、行アキ、`keep-with-next`、`UPageControl` が続くあいだの単位の列である（`inHold`）。
この関数は、区切りの保持に `@need-lines` があると、保持の最初の区切りの前に `@need-lines` を一つ足す。
足す `@need-lines` の行数は、保持の中の各 `@need-lines` について、保持の前の行アキと保持の中でそれより前の行数に、その行数を足したものの最大で、段の行数を超えない。
`reported` は、`unmetWarnings`（`Flow.hs:1015`）が区切りの位置の満たせなかった `@need-lines` と `keep-with-next` を報告しない処理（`Flow.hs:1026`、`Flow.hs:1029`）を写す。
`Whole.lean` の `Unmet` のうち `needLines` は位置を持たないので、`reported` は位置を `Unmet` と組にして受け取る。
`holdErrors` は、`separatorHoldErrors`（`Flow.hs:793`）を写す。
この関数は、組んだページを読み、区切りの連続と後続ブロックの最初の行が一つの段にない連続ごとに G07134 を返す。
`postProcess` は、`round'`（`Flow.hs:749`）がこの診断を足す処理を写し、ページをそのまま返して、受け取った診断の後に G07134 を足す。

単位（`Unit`）は、可視の区切り、行アキ、改ページ、アキ、`keep-with-next` と、それ以外の単位からなる。
可視の区切りは、前後の格子の行数と 1 行の行を持ち、段落のフロー（`Flow.hs:3907`）になる。
種類が `blank` の区切りは、単位を作る前に行アキへ解決される（`modules/golem-driver/src/Golem/Driver.hs:402`）ので、行アキとして表す。
アキ（`UGap`）は `FSpace` になり、格子の行へは `paginateBuilt` の `gridUnits`（`Flow.hs:838`）が行送りで割って渡す。
それ以外の単位は、フロー、区切りの連続を終えるか通すか切るか（`Role`）、最初の行の id を引数として持つ。
`separatorHoldErrors` は、`UBreak`、`USection`、`UColumns` で連続を切り、`UGap`、`UBlank`、`UKeepNext`、`UPageControl` を通し、ほかの単位では最初の行を持つときだけ連続を終える（`Flow.hs:810`〜`:823`）。
モデルでは、`USection` と `UColumns` を `reset`、`UPageControl` を `pass`、ほかを `block` の役とする。
定理はこれらの引数のどの選び方でも成り立つ。

区切りの保持の位置は、格子モードの `Whole.lean` と自由な配置の `Physical.lean`（「自由な配置のモデル」の節）の二つの改ページのモデルに `Env` の引数 `held` として渡す。
golem-typeset は可視の区切りの位置の集合（`separatorSpans`、`Flow.hs:826`）を golem-layout の `paginateHeld` と `PhysicalSettings` の `physicalHeld` に渡す（`Flow.hs:832`、`:859`）。
モデルでは、位置を行の id で表す。
`Whole.lean` と `Physical.lean` の `keepNext` のフローと満たせなかった `keepNext` は位置の id を持ち、`space` は区切りの後の `keep-with-next` に区切りの行の id を付ける（`keepOf`、`holdOf`）。
`heldHere`（`modules/golem-layout/src/Golem/Layout/Paginate/State.hs:179` と `Paginate/Physical.hs:879`）は、`held` に入る位置の `keep-with-next` が今の段で待っているかを返す。
格子モードの `placeKept`（`Paginate.hs:441`）と自由な配置の `placeWithNext` と `placeStanzaWithNext`（`Paginate/Physical.hs:856`、`:870`）は、保持が待つ段から後続のブロックを自分の指定のために送らず、空の段からと同じに置く。
格子モードでは、`Boundary.lean` の `holds` と `chained` が `Decide.hs` の `holds`（`Decide.hs:134`）と `chainedHeld`（`Decide.hs:196`）を写す。
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
その前提は、区切り、行アキ、改ページ、アキ、`keep-with-next` を除いたほかの単位のフロー（`otherFlows`）についての `figureOk` と `BoxesOk` である。
`space` と `holdNeeds` が作るフローは、このフローの間に、段落、行アキ、スペース、`keep-with-next`、改ページ、`need-lines` のフロー（`plainFlow`）を挟んだものである（`holdNeeds_ins`、`Ins.trans`、`separatorFlows_ins`）。
`boxesOk_ins` と `figureOk_ins` は、そのようなフローを挟んでも二つの前提が保たれることを示す。
実際のフローでは、`ruledLinks`（`Flow.hs:4664`）が直前のフローが罫線つきのブロックのときだけ共有を付けるので、共有するブロックの直前には `otherFlows` でも罫線つきのブロックがあり、箱は来ない。
golem-typeset が単位のフローの後に行う `joinBoxes`（`Flow.hs:3960`）、`ruledLinks`（`Flow.hs:4664`）、`markBookParts`（`Flow.hs:4540`）は、`SeparatorBlocks.lean` に写した。
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
アキと箱の前後の行数には行送りを掛け（`Flow.hs:2517`、`Flow.hs:3739`、`Flow.hs:3917`）、罫線には `ruleSide`（`Flow.hs:3578`）の寸法を持たせる。
G07134 は、`Physical.lean` のページの上で同じ規則（`Flow.hs:793`）で判定する。
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
`keep-with-next` の行数を 2 にする変更も、この入力では照合できていない。
本文の段落スタイルは段落の先頭に 2 行を求め、1 行の段落は分けられないので、1 行と 2 行の `keep-with-next` が後続の段落に同じ行数を求めるからである。
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
`keptNeed`（`modules/golem-layout/src/Golem/Layout/Paginate/Decide.hs:126`）が区切りの後に求める行数を n とし、1 + n が段の容量以下であることを、保持が空の段に収まることとする。
p は段落の最初の部分の行数で、1 行以上であり、段落の全体か、`splitAtBreak` がそのまま返す行数である（`firstPart`、`Decide.hs:257`）。
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
golem-typeset は、行、図版、コードの行の id を一つの番号（`nuNext`、`Flow.hs:3816`、`Flow.hs:3826`）から振るので、実際の入力は `Uniq` を満たす。
ただし、`textSlots` が読まない図版、転置図版、回り込み図版、表の繰り返す見出しの行のスロット（`unlisted`）が二つの行の id を持たないことは、まだ前提に残る。
これらの id が原稿の id から来ることは、まだ示していない。
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
この原稿は、「未完の項目」の節で述べる照合の組 `holds`（`SeparatorBoundary.hs` の `holdInputs`）に含まれる。
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
見出しの罫線つきのブロックは、`keepFollowing` で後続を判定した段から、罫線の領域を足した長さで見出しを置く。
罫線の領域と見出しと脚注の長さの和が段の容量を超えるときは、後の罫線を外し、次に前の罫線を外して置き直し、どちらもなければ罫線のない見出しとして置く。
見出しの罫線の領域は、`physicalHeadingBounds` に見出しの字面の位置があればその位置から求めた仮想の送りで求める（`Env.headingBounds`）。
罫線の領域の長さは、`FreeGeometry.hs` の `faceOffset`、`ruleBeforeGap`、`ruleAfterGap`、`rulesSharedGap`、`ruleBeforeEdge`、`ruleAfterEdge` のうち、使用長に足す長さ（extra）だけを写した。
先のフローが求める長さ（`firstNeed`）は `Env` の引数とし、定理はそのどの値でも成り立つ。

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
golem-typeset はコードの行に続く番号を振るので、二つは一致すると考えられるが、未確認である。
`drainCarry` は、次のページが最初の待機中の図版と最初の繰り越し脚注の 1 行を受け取れる間だけ進む（`drainOk`）。
この条件が成り立たない状態では、Physical.hs の `drainCarry` は止まらないか、送りが 0 のときに `div` の例外になる。
繰り越す脚注の 1 行が新しいページに収まらなければ、どのページでも脚注は減らないからである。
そのため、`paginate` は、最後の `drainCarry` の後に待機中の図版か繰り越す脚注が残れば `noProgress` を返す。
本の部を含まずに `checkNotes` を通った原稿では、待機中の図版は `FFigure` の検査で段の容量以下であり、繰り越す脚注は区切りと 1 行の和が段の容量以下なので、この条件は成り立つと考えられるが、証明していない。

終了は、各ループが整礎な再帰で定義されていることで示す。
`I4_nextColumn_rank` は、何かを置いた段か `FAdjustLines` で縮んだ段から次の段へ進むと、尺度 `rank` が減ることを証明する。
`rank` は、待機中の図版の数と繰り越す脚注ごとの行数に 1 を足した値の和（`waiting`）を 4 倍し、段が縮んでいれば 2 を、段が空でなければ 1 を足した値である。
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
容量 30 sp、送り 10 sp の 1 段で、2 行の段落の後に、送り 14 sp の行 905 だけの見出しの行と本体の行 `[810]`、`[820, 821]` を持つ表を置くと、`paginatePhysical` は 2 秒で終わらなかった。
golem-typeset が `physicalPitches` に送りを与えるのは段落の単位の行だけで（`modules/golem-typeset/src/Golem/Typeset/Flow.hs:4174`）、表の行には与えないので、原稿から作る表では見出しの行の送りは行の送りに等しい。

`judgeNeed`（`FNeedLines` の段のループ）も、空でない段か縮んだ段からだけ次の段へ進むので、`rank` で止まる。

本の部の次の単位まで段を進めるループ（`advanceUnit`）は、次の段がページの番号か残りの段数を必ず進める（`nextColumn_moves`）ので、単位の番号から決まるページの上限との差と残りの段数の辞書式順序で止まる。
本の部の図版が待つ間に段を進めるループ（`settle`）は、待機中の図版があるので `waiting` とページの残りの段数の辞書式順序で止まる（`I4_settle_rank`）。
`placeTableAcross` のループ（`acrossGo`）は、残りの部分の数と `rank` の辞書式順序で止まる。
`parts` は、原稿の残りの項目の数、`keep-all-lines` の有無、`rank`、行数の上限の辞書式順序で止まる。
段を進めると `rank` が減り（`I4_trialWrap_moved` と `I4_moveCursor_rank`）、試し直すと上限が減り、続けると残りの項目が減る。

`fitsFollowing` は罫線つきのブロックを試しに置き、見出しの罫線つきのブロックは `keepFollowing` を通して `fitsFollowing` を呼ぶので、`fitsFollowingGo` と `placeRuled` は相互再帰で定義した。
尺度は三つ組の辞書式順序である。
`fitsFollowingGo` の尺度は、読む後続のフローの数、5、0 の組である。
`placeRuled` の尺度は、後に続くフローの数に 1 を足した値、罫線の数と共有の有無の和（`ruledRank`）に 1 を足した値、この `rank` の組である。
`fitsFollowingGo` が `placeRuled` を呼ぶときは後続のフローの数が等しく、`ruledRank` は 3 以下なので、二つ目が減る。
`placeRuled` が `fitsFollowingGo` を呼ぶときは、`keepAhead` が返す列が元の列より長くならないので（`keepWanted_length`）、一つ目が減る。
`placeRuled` が自身を呼ぶときは、罫線を外すか共有をやめれば `ruledRank` が減り、`fit` が段を進めれば `rank` が減る（`I4_fit_moved`）。
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
golem-typeset は、行に `bUnitFirsts updated Map.! index + countBefore` から続く番号を振る（`modules/golem-typeset/src/Golem/Typeset/Flow.hs:4475` と `:3559`）。
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
さらに、図版の前のフロー、図版の高さ、行数の上限、保持、段落の始めかを変えて、回り込み図版の横の段落の一部分を `trialParagraphPartLimit` で試す入力を `tw` の行に書き出す。
次の段へ送った部分は、送った先の段でもう一度試す。
id が 900 以上の行は、送り 14 sp、字面 12 sp とした。
最初の行の id が 385 の見出しには、`physicalHeadingBounds` として字面の始まり 4 sp と終わり 16 sp を与えた。
id が 702 と 705 の行には 3 sp、712 の行には 5 sp の `physicalWrappedBefore` を与え、箱 170 には 3 sp の `physicalBoxPadding` を与えた。
`PhysicalBoundary.lean` は `in` の行を読み、`Physical.lean` の `paginate` で評価して同じ形式で書き出す。
`PhysicalBoundary.hs` は、2 秒で終わらない入力を `out fail loop` と書き出し、`PhysicalBoundary.lean` は `noProgress` を同じく書き出す。
見出しの行の送りが 14 sp の表の 8 個の入力では、4 個が両方で `loop` になった。
`check.sh` は二つの出力を `diff` で比べ、150106 個の入力と 10368 個の試しですべて一致した。
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
見出しの罫線つきのブロックでは、前の罫線の領域を 0 にすると 11274 個、後の罫線の領域を 0 にすると 3280 個、前の罫線で `physicalHeadingBounds` を見ないと 2880 個、後の罫線で見ないと 864 個、後の罫線より先に前の罫線を外すと 1744 個、脚注の長さを 0 にすると 5181 個である。
さらに、`TallHeadingExtent` の分岐を除くと 422 個、`keepFollowing` を呼ばないと 410 個、`placeRuledKeeping` が後続の制御のないときに後続を見ないと 651 個、`fitsFollowing` が奇数ページの見出しの罫線つきのブロックを収まらないとすると 12 個、置く長さに `headingNeed` でなく見出しの長さを使うと 197 個、脚注を分けるときに後の罫線の領域を予約しないと 48 個、後の罫線の領域を使用長に足さないと 3260 個である。
回り込み図版では、横に収まる行の判定で図版の終わりを見ないと 130 個、脚注の 1 行を求めないと 448 個、表示した脚注の長さを足さないと 160 個、行の前のアキを足さないと 833 個、置くときに行の前のアキを足さないと 968 個、図版の終わりまでの長さを予約しないと 32 個、図版の後で使用長を図版の終わりまで進めないと 887 個、残りの行の前のアキを除くと 446 個、残りの行が収まらないときに次の段へ進まないと 192 個、図版の長さで `fit` を呼ばないと 1046 個である。
残りの行を置く前に次の段へ進まなくても、出力は変わらなかった。
横に収まらなかった行は同じ段の図版の下にも収まらず、`placeWrappedOverflow` が次の段へ進むからと考えられるが、未確認である。
表では、見出しの行を繰り返さないと 2740 個、繰り返した直後の行を必ず置く判定を除くと 942 個、行の判定で脚注のすべてでなく 1 行を求めると 4 個、`tableNeed` の部分で脚注の 1 行でなくすべてを求めると 1062 個、`checkTableNotes` を除くと 736 個である。
さらに、行の後の予約を除くと 389 個、見出しの行の後の最初の行の予約を除くと 369 個、最後の行と下のキャプションを一つにしないと 571 個、表の前のアキを使用長に足さないと 865 個、下のキャプションと最後の行が空の段に収まるかの検査を除くと 192 個である。
`fit` に渡す長さから表の前のアキを除いても、出力は変わらなかった。
`tableFits` が成り立つ段では、どちらの長さでも `fit` は段を進めないからである（`tableAt_fields`）。
`tableReady` の条件から待っているスペースを除いても、出力は変わらなかった。
収まらない段では `fit` が次の段へ進むからと考えられるが、未確認である。
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
図版の横の行を `putWrappedLine` でなく `putLine` で置いても出力が変わらないのは、`fittingHere` が図版の終わりの下に脚注が収まる行だけを選ぶので、予約しても表示する脚注の行が変わらないためと考えられるが、未確認である。
`parts` の照合はしていない。
golem-typeset の改行器と `probeNext` を入力から作るには、組版の全体を動かす必要があるからである。
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
| `Paginate/Physical.hs:281` `initial`、`:284` `limit`、`:287` `room`、`:290` `empty` | `initial`、`limit`、`room`、`empty` |
| `Paginate/Physical.hs:305` `close` | `close` |
| `Paginate/Physical.hs:312` `nextColumn`、`:338` `nextPage` | `fresh`、`nextColumn`、`nextPage` |
| `Paginate/Physical.hs:112` `Waiting`、`:345` `placeDeferred`、`:355` `placeTurned`、`:363` `afterTurned` | `Waiting`、`placeDeferred`、`placeDeferredGo`、`placeTurned`、`placeTurnedGo`、`opened`、`afterTurned`、`breakPage` |
| `Paginate/Physical.hs:368` `carryInto`、`:378` `splitCarried` | `carryInto`、`splitCarried` |
| `Paginate/Physical.hs:388` `fit` | `fit`、`dropAtTop` |
| `Paginate/Physical.hs:398` `putSlot` | `putSlot` |
| `Paginate/Physical.hs:408` `putLineWithReserve`、`:435` `splitNotes` | `putLineWithReserve`、`lineSep`、`lineNotes`、`lineNotesUsed`、`putLines`、`splitNotes` |
| `Paginate/Physical.hs:445` `fitting` | `fitting`、`fittingGo` |
| `Paginate/Physical.hs:457` `fittingWrapped`、`:471` `putWrappedLine`、`:478` `placeWrappedOverflow`、`:911` `placeFlow` の `FWrapped` | `fittingWrapped`、`fittingWrappedGo`、`putWrappedLine`、`putBeside`、`placeWrappedOverflow`、`overflowMove`、`overflowReady`、`placeWrapped` |
| `Paginate/Physical.hs:489` `splitAtBreak`、`Paginate/Decide.hs:257` `firstPart` | `splitAtBreak`、`firstPart` |
| `Paginate/Physical.hs:550` `trialParagraphPartLimit` | `trial`、`trialFrom`、`trialRest`、`checkRows`、`Part`、`trialWrap`、`trialWrapFrom`、`trialWrapRest`、`fittingHere`、`fittingWrapGo`、`putHere`、`putHereLines`、`limited` |
| `Paginate/Physical.hs:188` `PhysicalWrap`、`:218` `activeWrapEnd`、`:223` `endPhysicalWrap`、`:226` `movePhysicalCursor`、`:251` `beginPhysicalWrap` | `Region`、`wrapEnd`、`endWrap`、`moveCursor`、`beginWrap` |
| `modules/golem-typeset/src/Golem/Typeset/Flow.hs:4464` `paragraph`（`parts`） | `parts`、`nextItem`、`minimumFront`、`limitRank` |
| `Paginate/Physical.hs:597` `placeLines` | `placeLines` |
| `Paginate/Physical.hs:610` `checkPhysicalNotes`、`:618` `paginatePhysical` | `checkNotes`、`paginate` |
| `Paginate/Physical.hs:632` `drainCarry` | `drainCarry`、`drainOk` |
| `Paginate/Physical.hs:637` `placeAll`、`:643` `placeNext`、`:671` `occupies` | `placeAll`、`placeNext`、`beforeOf`、`placeBody`、`occupies` |
| `Paginate/Physical.hs:687` `checkWaits` | `checkWaits`、`checkWait`、`waitMet`、`markUnmet`、`addedSlots` |
| `Paginate/Physical.hs:702` `followingRows`、`:715` `keepAhead` | `followingRows`、`keepAhead`、`keepAheadGo`、`collect`、`soft`、`counts` |
| `Paginate/Physical.hs:735` `firstNeed` | `Env.firstNeed`（照合では `PhysicalBoundary.firstNeed`） |
| `Paginate/Physical.hs:790` `fitsFollowing` | `fitsFollowing`、`fitsFollowingGo`、`keepWanted_length` |
| `Paginate/Physical.hs:841` `placeWithNext` | `placeWithNext`、`keptBack`、`afterFront` |
| `Paginate/Physical.hs:882` `placeFlow` | `placeFlow`、`judgeNeed`、`adjustLines`、`ceilDiv` |
| `Paginate/Physical.hs:988` `placeFlow` の `FBoxed`、`:1079` `placeBoxedParagraph`、`:1146` `placeBoxedStanza` | `Flow.boxed`、`placeBox`、`paddingExtra`、`boxExtra`、`boxNotes`、`fragmentSize`、`boxAvailable`、`boxCount`、`putBoxPart`、`placeBoxedParagraph`、`stanzaBoxSize`、`stanzaBoxCount`、`seal`、`reopen`、`placeBoxedStanza`、`nonemptyVerses` |
| `Paginate/Physical.hs:990` `placeFlow` の混ぜた `FBoxed`、`:1023` `boxKeepLinks`、`:1034` `boxKeepMarks`、`:1038` `boxKeepCounts`、`:1042` `BoxUnitKeep`、`:1049` `boxUnitKeeps`、`:1064` `collectMixedBoxUnits`、`:1150` `placeBoxedStanzaWith` | `collectMixed`、`boxLinks`、`unitKeepsOf`、`unitEntries`、`mapsOf`、`BoxMaps`、`UnitKeep`、`unitGaps`、`linkBreaks`、`unitBoundary`、`atGroupStart`、`paragraphBreak`、`legalBreak`、`boundaryWarnings`、`relaxFor`、`fallbackKeep`、`unrelaxed`、`boxSelected`、`boxShort`、`putUnits`、`putStanzaPart`、`placeBoxedStanza` |
| `Paginate/Physical.hs:991` `placeFlow` のそのほかの `FBoxed`、`:1008` `flowLines` | `placeGeneric`、`genericExtra`、`genericMinimum`、`placeFlows`、`Inner`、`level`、`flowDepth`、`flowsDepth`、`flowLines`、`bodyLines` |
| `Paginate/Physical.hs:812` `fitsFollowing` の `FBoxed` | `boxFits` |
| `Paginate/Physical.hs:1276` `placeRuledKeeping`、`:1292` `placeRuled`、`:1406` `flushPendingRule` | `placeRuledKeeping`、`placeRuled`、`ruledBefore`、`ruledAfter`、`ruledBeforeExtra`、`ruledAfterExtra`、`ruledJoin`、`ruledExtent`、`joiningNext`、`flushPendingRule`、`ruledRank` |
| `Paginate/Physical.hs:1352` `placeRuled` の `RuledHeading` | `placeRuled`、`headingStateOf`、`keepFrom`、`headingBeforeExtra`、`headingAfterExtra`、`headingNotesExtent`、`putRuledHeading`、`ruledText` |
| `Paginate/Physical.hs:1416` `waitFor`、`:1423` `waitForPrior` | `waitFor`、`waitForPrior` |
| `Paginate/Physical.hs:1659` `breakAt`、`:1675` `parityStart` | `breakAt`、`parityStart` |
| `Paginate/Physical.hs:298` `headingOnly`、`:824` `keepFollowing`、`:1434` `putHeading`、`:1441` `headingNeed`、`:1450` `placeHeading` | `headingOnly`、`keepFollowing`、`keepFrom`、`keepVirtual`、`keepWanted`、`putHeading`、`headingEnv`、`headingNeed`、`tallAt`、`placeHeading` |
| `Paginate/Physical.hs:500` `placeStanza`、`:859` `placeStanzaWithNext` | `placeStanza`、`wholeVerses`、`stanzaShort`、`placeStanzaWithNext`、`stanzaBack` |
| `Paginate/Physical.hs:1460` `placeCode` | `placeCode`、`codeExtent`、`codeMinimum`、`codeFit`、`codeFitting`、`codeCount`、`seek` |
| `Paginate/Physical.hs:1490` `tableNeed`、`:1497` `checkTableNotes`、`:1503` `tableReady`、`:1511` `placeTable` | `tableNeed`、`checkTableNotes`、`tableFits`、`tableAt`、`seek`、`tableCheck`、`tableFirstPart`、`placeTableFrom`、`tableCaption`、`placeTable` |
| `Paginate/Physical.hs:1622` `placeTableLinesReserved`、`:1632` `placeTableRows` | `putReserved`、`putRepeated`、`repeatedOf`、`tableRowsGo`、`tableTail`、`tableText` |
| `Paginate/Physical.hs:132` `retainPhysicalPart`、`:884` `placeFlow` の `FBookPart`、`Paginate/BookParts.hs:83` `slotIds` | `Flow.bookPart`、`PartUnit`、`retain`、`retainTry`、`settle`、`figureOk`、`partFits`、`minKey`、`lexMin`、`slotIds`、`unitKey`、`emptyUnit`、`nextUnit`、`advanceUnit`、`Env.retention` |
| `Paginate/Physical.hs:657` `placeNext` の `FDefTerm`、`:983` `placeFlow` の `FTable`、`:1546` `placeTableAcross` | `placeBody`、`placeFlow`、`placeTableAcross`、`acrossGo`、`acrossTail`、`splitLast` |
| `Paginate/Physical.hs:929` `FSection`、`:970` `FRestoreColumns`、`:971` `FSwitchColumns` | `sectionStart`、`restoreColumns`、`switchColumns` |
| `FreeGeometry.hs:29` `faceOffset`、`:56` `ruleBeforeExtra`、`:59` `ruleAfterExtra` | `faceOffset`、`ruleBeforeExtra`、`ruleAfterExtra` |
| `FreeGeometry.hs:68` `ruleBeforeGap`、`:76` `ruleAfterGap`、`:83` `rulesSharedGap` | `ruleGapExtra`、`rulesSharedExtra` |
| `FreeGeometry.hs:97` `ruleBeforeEdge`、`:109` `ruleAfterEdge` | `ruleBeforeEdgeExtra`、`ruleAfterEdgeExtra` |

## 未完の項目

格子モードの改ページ全体は `Whole.lean` が扱う。
格子モードのすべてのフローについて、改ページ全体の終了と、段落、詩の行、回り込み図版の横の行、定義の項、表の行、見出し、コードの行、罫線つきのブロックの行の過不足と順序を証明した。
図版と転置図版の過不足と順序は、図版の高さと段の容量を 1 行以上、脚注区切りの行数を 0 行以上とし、箱の直後のブロックが罫線の領域を共有しない（`BoxesOk`）前提の下で証明した。
[root ADR 0352](../../docs/adr/0352-prove-pagination-in-lean.md) の完了の判定のうち、一般化できる性質の証明と実装との境界例の照合について、残るのは次の四つである。

一つ目は、境界入力の表のうち、キャプションの行の Lean の側の照合である。
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
`Boundary.lean` は、これらの 48394 個の入力を `Whole.lean` の `paginate` で評価し、ページ、段、スロットとその格子の行、満たせなかった指定を書き出す。
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

境界入力の照合には、一つのことが残る。
表のキャプションの行（改行位置の前後に一文字足す、画像に残る行が一行かゼロ行、キャプションが一行超過）は、golem-driver の `FigureSpec.hs` がキャプションを改行して図版を縮小して確かめるので、Lean の側の照合は、二つ目の項目に残る、実フォントの送りを `FigureSpec.hs` の計測値で渡す照合を待つ。

二つ目は、キャプションの評価値と幅の計算の Haskell との対応である。
`Pagination.lean` は、改行候補の選択、改行列からの行の組み立て、占有行数の計算を、評価値と幅を引数として証明する（`I1_caption_*`）。
評価値と幅の計算は、有限の入力で Haskell の改行器と照合した。
`CheckCaptionAssembly.hs --values` は、golem-layout の `badness`、`fitnessOf`、`lineDemerits` を境界の値で評価し、改行器が改行した 24186 個のキャプションについて、項目、引数、行長、選んだ改行位置と、その総デメリット、各行の調整比と超過幅を書き出す。
キャプションは、既存の 16806 例の入力に、突出と端のあるボックス、ソフトハイフン、突出、`pull-in-first`、緊急の伸びを使う引数を足したものである。
`CaptionValues.lean` は、その入力を読み、`captionBadness`、`captionFitness`、`captionLineDemerits` の値と、`captionLineRanges` の行ごとに累積の幅（`captionSum`）の差から `captionWidthEvaluation` と `captionPathCost` で求めた総デメリットと、調整比と超過幅を書き出す。
`check.sh` は二つの出力を `diff` で比べ、すべて一致した。
直前の改行の読み飛ばし範囲に入る改行では、行の開始位置が改行位置より後になり、Haskell の伸びと縮みの和は負になる。
Lean の側も、伸びと縮みを項目の和ではなく累積の和の差として求めて、この値に合わせた。

照合の感度は、写した計算を一つずつ替えて確かめた。
行末の伸びを除くと 4384 個、緊急の伸びを除くと 155 個、隣接する fitness のデメリットを除くと 181 個、行頭の突出を除くと 529 個、ハイフンの突出を除くと 72 個、行末の端を除くと 1590 個、改行位置のペナルティの幅を除くと 1306 個、調整比の下限を除くと 850 個、`pull-in-first` を除くと 2 個、`cappedCubicBadness` の上限を 1291 にすると 1 個の入力で出力が食い違った。

評価値は、改行器の走査にも渡した。
`Pagination.lean` の `captionEvaluate` は、`breakParagraph` の `evaluate` を、行長が行ごとに変わらず字形を伸縮しない場合について写したもので、行の評価値に `captionLineSums`、`captionWidthEvaluation`、`captionPathCost` を使う。
`captionContext` はこの評価を `I1_caption_*` の走査の引数（`CaptionScanContext`）に入れ、`captionCompared` は `breakParagraph` と同じ順に pass を試し、総デメリットの最も小さい経路を選ぶ。
`CaptionValues.lean` は、同じ 24186 個のキャプションを `captionCompared` で改行し、成功した pass、改行位置、総デメリットを書き出す。
`check.sh` はこれを golem-layout の `breakParagraph` の pass、改行位置、総デメリットと比べ、すべて一致した。
この照合は pass 4 で改行した 12518 個も含むので、救済した行と追い出した行の総デメリットも Haskell と一致する。

この照合の感度も、写した計算を一つずつ替えて確かめた。
許容度を見ないと 8991 個、節点の生存の判定から改行位置のペナルティの幅を除くと 790 個、緊急の伸びを除くと 1151 個、pass 3 を試さないと 155 個の入力で出力が食い違った。
超過を測る行の開始位置で読み飛ばしを数えないと 89 個、pass 4 の許容度を通常の許容度にすると 744 個、fitness を常に 2 にすると 518 個、強制改行を強制としないと 11993 個、最後の経路を総デメリットで選ばないと 2321 個の入力で出力が食い違った。
総デメリットの等しい経路から、最後の行の fitness と前の改行の列で選ぶ規則は、替えても出力が変わらなかったので、この入力では照合できていない。

不変条件 1 と 2 は、この評価について定理にした。
`I1_caption_compared_scan_ends` は、どの pass でも走査が終わることを示す。
`I1_caption_compared_lines` は、`captionCompared` が選んだ改行位置がキャプションを行に組み立て、行の数が節点の行数と等しく、行のボックスが原稿のボックスと順に一致することを示す。
`I1_caption_compared_deterministic` は、同じ項目と引数が同じ pass と改行位置を与えることを示す。
`I2_caption_compared_diagnostic` は、組み立てた行の格子の行数が改行位置の数から決まり、その行数が段の空きを超えるのは行の高さが空きを超えるときに限ることを示す。
`I2_caption_compared_figure` は、その行数が段を埋めれば図版を返さず（G07038）、行が残れば縮小した図版の高さが残りの行に収まることを示す。

対応には、次の三点が残る。
第一に、`captionCompared` と `breakParagraph` の一致は有限の入力で照合しただけで、証明ではない。
pass 4 が常に成功し、`captionCompared` が `none` を返さないことも、まだ証明していない。
第二に、行ごとに変わる行長と、字形の伸縮（`pExpansion`）は写していない。
第三に、実フォントの送りを golem-driver の `FigureSpec.hs` の計測値で渡す照合も、まだしていない。

三つ目は、[root ADR 0397](https://github.com/tett23/golem/blob/7fc360ff641d7eea6e8ee3ace30eca26e545334b/docs/adr/0397-paragraph-line-pitch-and-dimensional-spacing.md) の自由な配置の状態遷移のうち、`Physical.lean` が扱わない処理である。
`Physical.lean` は、「自由な配置のモデル」の節に挙げたフローについて、終了、行の過不足と順序、図版と回した図版の過不足と順序を証明し、境界の入力で `paginatePhysical` と照合した。
整数行の `Whole.lean` は、自由な配置の証明とは扱わない。
回り込み図版の横の段落を改行し直すループ（`parts`）は写したが、改行器と後続の判定を引数とし、golem-typeset の出力とは照合していない。
golem-typeset の `causalFreeFlow` のうち、回り込み図版の横の詩を置くループ（`stanza` と `tryVerses`）、後続を試すループ（`probeNext` と `probeChain`）、図版ごとの仕事を進めるループ（`jobsFrom` と `itemJobs`）は、まだ写していない。

置いた罫線の位置は、まだ証明していない。

脚注の行は、注ごとに見れば最初の行から順に並ぶが、原稿の注の順には並ばないことがある。
容量 40 sp、送り 10 sp、区切り 0 sp の 1 段で、`[FParagraph (Keep 1 1 False) (5 行の脚注 500 を持つ 1 行), FAdjustLines 2, FParagraph (Keep 1 1 False) (1 行の脚注 510 を持つ 1 行), 1 行の段落]` を `paginatePhysical` に渡すと、1 ページ目に脚注 500 の 0〜2 行目と脚注 510 の全体が並び、脚注 500 の 3〜4 行目は 2 ページ目に置かれた。
`FAdjustLines` がない同じ入力では、脚注 510 を持つ行は 2 ページ目に送られ、脚注 500 の続きの後に置かれた。
`putLineWithReserve`（`Paginate/Physical.hs:408`）は、繰り越す脚注が残っていても、段の残りが増えれば新しい行の脚注を今の段に置くからである。
[仕様](../../docs/specifications.md)は、前のページから続く脚注を次の本文のページに続ける（5327 行）と定めるが、後の注との順は定めていない。
このため、この README は食い違いとは扱わず、注の順を定めるかをメンテナーの判断に残す。
そこで、脚注の証明は、注の id ごとに出力の行を並べた列が、その注の 0 行目から最後の行までの列に等しいことを述べる。
不変条件は、出力済みの段の脚注、現在の段の脚注、繰り越す脚注をつないだ列を、注ごとに行の番号へ展開したものが、読んだ行の脚注を展開したものに注ごとに等しいことである（`WholeNotes.lean` と `PhysicalNotes.lean` の `Rel`）。
新しい行の脚注は、繰り越す脚注の前に今の段へ置かれることがあるので、この等しさは列全体ではなく注ごとに成り立つ。
この入れ替わりが同じ注の中で起きないために、原稿の注の id が互いに異なること（`Distinct`）を前提に置く。
golem-typeset は注の id を注の原稿上の範囲と番号から作る（golem-layout の `Look.hs:250` の `NoteId`、golem-typeset の `Structure.hs:114`）ので、実際の入力はこの前提を満たす。

格子モードでは、`WholeNotes.lean` の `I5_paginate_each_note` が、原稿のどの注についても、ページに並ぶその注の行が 0 行目から最後の行まで一度ずつ順に並ぶことを示す。
ただし、置けない脚注として `unplaceableFootnote` を報告した注は除く。
`carryNote` は、空の段に脚注の行が入らないとき、その注の残りを捨てて報告するからである。
証明は、脚注区切りの行数を 0 行以上とする前提も置く。
繰り越す注の一つが途中までしか入らなかった後は段の残りが 0 行になり、続く注が先に置かれないことに、この前提を使う。
`I5_paginate_notes` は、原稿にない注の行がページに現れないことも示す。

自由な配置では、`PhysicalNotes.lean` の `I5_paginate_each_note` が同じことを、`Physical.lean` の `paginate` が成功し、注の id が互いに異なる（`Distinct`）入力について示す。
自由な配置では、入らない脚注は `footnoteTooTall` の失敗になり（`Physical.lean:386` と `:3053`）、`drainCarry` の後に繰り越す脚注が残れば `noProgress` の失敗になる（`Physical.lean:3068`）ので、除く注はない。
コードの行は脚注を持たない。
golem-typeset はコードの行を脚注なしで作り（`Flow.hs:3823`）、golem-layout の `placeCode` は行の脚注を読まないからである。

四つ目は、[root ADR 0398](https://github.com/tett23/golem/blob/0d20d3e2e445d69aa576ec97615a51c31114ceec/docs/adr/0398-styled-separators-in-manuscripts.md) の区切りの残りである。
格子モードのフロー生成と G07134 の後処理は、「区切りのモデル」の節のとおり `Whole.lean` の `Flow` の上に写し、不変条件 4 と 5 を当て、golem-typeset と照合した。
不変条件 4 と 5 は、`joinBoxes`、`ruledLinks`、`markBookParts` を通したフローと、自由な配置に写したフローにも当てた。
空の段に収まる保持に G07134 を返さないことは、格子モードの区切り一つと後続の段落について定理で示した（`I3_separator_hold_no_error`）。
`placeKept` が段落を分けて送る場合、区切りの後ろのアキ、区切りの連続も、定理の範囲に入る（`I3_separator_chain_no_error`）。
保持の中の `@need-lines`、区切りの前の行アキ、自由な配置は、まだ照合だけで確かめている。
`check.sh` は、区切りの原稿を六つの組で golem-typeset と照合し、すべて一致した。
格子モードと自由な配置の 8784 個ずつの原稿は、「区切りのモデル」の節で述べた項目の組み合わせである。
もう二組の 8640 個ずつの原稿は、項目に箱、前後に罫線のある段落、1 行のリスト項目を足し、段の容量を 3 行か 4 行にしたもので、格子モードと自由な配置で照合した。
残る二組の 1440 個ずつの原稿（`holds` と `holds-free`）は、保持の後の段落に `@no-page-break` を続けたもので、格子モードと自由な配置で照合した。
この原稿は、なしか 1 行の段落の後に、`---` か `@separator scene`、なしか `---` か `@blank-line 1`、1〜3 行の段落、`@no-page-break` を置き、最後に 1〜3 行の段落か、1 行か 2 行の段落と `@no-page-break` と同じ行数の段落を置いたもので、段の容量は 2〜5 行である。
自由な配置は、`SeparatorBoundary.hs` が `alignment = "free"` の組版の設定で選ぶ。

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

これらを終えるまで Alloy の定期実行と既存の参照を維持する。

## 検査の手順

手元では次のコマンドで Lean 4.7.0 の証明を検査する。

```sh
lean experiments/pagination-proof/Pagination.lean
lean experiments/pagination-proof/Whole.lean
lean experiments/pagination-proof/Physical.lean
cabal build golem-layout golem-driver:tests
sh experiments/pagination-proof/check.sh
```

`check.sh` は、境界入力、自由な配置の境界入力、区切り、キャプションの評価値の照合で `cabal exec` から `runghc` を呼ぶので、先に golem-layout をビルドしておく。
区切りの照合は golem-driver のテストの `Support.hs` を読み込むので、golem-driver のテストもビルドしておく。
`check.sh` は、`Whole.olean` と `WholeNotes.olean` を作ってから、それを読み込む `Separator.lean` を検査する。
`SeparatorBoundary.lean` は、`Boundary.olean`、`Physical.olean`、`SeparatorPhysical.olean`、`SeparatorBlocks.olean` を作った後に評価する。
`WholeNotes.lean` と `PhysicalNotes.lean` も、`Whole.olean` と `Physical.olean` を読み込んで検査する。
`SeparatorPhysical.lean` と `SeparatorBlocks.lean` も同じく読み込み、`SeparatorBoundary.lean` は環境変数 `SEPARATOR_MODE` で六つの組を一つずつ評価する。

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
