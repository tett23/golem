# ADR 0426: 移動し終えたファイルとフォルダの参照の編集を Golem LSP が返す

Status: proposed

## 文脈

Golem LSP は、ファイルとフォルダを移す前に、参照を書き換える編集を返す。
エディタの改名には `workspace/willRenameFiles` で（[root ADR 0338](0338-update-references-on-file-and-folder-renames.md)）、Aleph のツリーでの移動には `golem/planFileMove` で応じる（[root ADR 0399](0399-plan-moves-across-project-boundaries.md)）。
どちらも、移動元にファイルがあり、移動先にまだ無い状態を前提にしている。

ファイルは、エディタの外でも移される。
ターミナルの `git mv` や `mv`、Finder での移動である。
この場合、エディタが気付いたときには移動はもう終わっている。
移動元にはファイルが無いので、今の二つの要求は使えない。
その結果、原稿の import、画像のパス、manifest の章のパス、Wiki リンクなどが、移動前の場所を指したまま残る。

この ADR は、移動し終えた後の状態から、`golem/planFileMove` と同じ計画を返す要求を決める。
移動を見つけて、この要求を送り、編集を当てるのは、エディタ（Aleph）の役目である。
Aleph の側の決まりは、Aleph の ADR で決める。

## 調査した事項

origin/main（[f815a8bed](https://github.com/tett23/golem/commit/f815a8bedb6366412ea8d3b442d32eeff1998420)）で、次のことを確かめた。

- `golem/planFileMove` の要求は、`workspaceUri`、`oldUri`、`newUri`、`projects`、`wikiSheets`、`documents`、`inventoryComplete` を持ち、移動の対を一つだけ受ける（[FileMove.hs#L42-L103](https://github.com/tett23/golem/blob/f815a8bedb6366412ea8d3b442d32eeff1998420/modules/golem-lsp/src/Golem/Lsp/FileMove.hs#L42-L103)）。
  応答は、`complete`、`groups`、`snapshot`、`chapters` を持つ（[root ADR 0399](0399-plan-moves-across-project-boundaries.md)）。
- 計画は、ディスクを走査した移動前の索引から作る。
  入力の検査は、移動元があること、移動先が無いこと、移動先の親があることを求める（[FileMove.hs#L182-L216](https://github.com/tett23/golem/blob/f815a8bedb6366412ea8d3b442d32eeff1998420/modules/golem-lsp/src/Golem/Lsp/FileMove.hs#L182-L216)）。
  参照の書き換えは、移動前のパスが索引にあることを確かめ、移動後のパスを移動の写像で求める（[FileMove.hs#L306-L323](https://github.com/tett23/golem/blob/f815a8bedb6366412ea8d3b442d32eeff1998420/modules/golem-lsp/src/Golem/Lsp/FileMove.hs#L306-L323)）。
  章の登録の移し替えも、移動前の索引で章を読む（[FileMove.hs#L342-L347](https://github.com/tett23/golem/blob/f815a8bedb6366412ea8d3b442d32eeff1998420/modules/golem-lsp/src/Golem/Lsp/FileMove.hs#L342-L347)）。
- 索引の走査は、`listDirectory` が返す名前で比べる（[FileMove.hs#L137-L145](https://github.com/tett23/golem/blob/f815a8bedb6366412ea8d3b442d32eeff1998420/modules/golem-lsp/src/Golem/Lsp/FileMove.hs#L137-L145)）。
- `workspace/didRenameFiles` は、接続のルートの中の対について、旧パスの索引を捨ててプロジェクトを読み直す。
  ルートの外の対は捨てる（[Server.hs#L358-L363](https://github.com/tett23/golem/blob/f815a8bedb6366412ea8d3b442d32eeff1998420/modules/golem-lsp/src/Golem/Lsp/Server.hs#L358-L363)）。
- LSP が `workspace/didChangeWatchedFiles` で見張るのは、`manifest.toml` と評価が読んだ表のファイルだけである（[Server.hs#L487-L498](https://github.com/tett23/golem/blob/f815a8bedb6366412ea8d3b442d32eeff1998420/modules/golem-lsp/src/Golem/Lsp/Server.hs#L487-L498)、[Workspace.hs#L187-L188](https://github.com/tett23/golem/blob/f815a8bedb6366412ea8d3b442d32eeff1998420/modules/golem-lsp/src/Golem/Lsp/Workspace.hs#L187-L188)）。
- 初期化の応答の `capabilities.experimental.golem` は、`planFileMove` の契約の版 `1` を返している（[Server.hs#L131](https://github.com/tett23/golem/blob/f815a8bedb6366412ea8d3b442d32eeff1998420/modules/golem-lsp/src/Golem/Lsp/Server.hs#L131)）。

指示者は 2026-11-23 に、エディタの外での移動にも参照が追従するように求め、この ADR を書くことを認めた。

## 実装すること

### 要求

Golem LSP に、独自の要求 `golem/planMovedReferences` を足す。
初期化の応答の `capabilities.experimental.golem.planMovedReferences` に、契約の版 `1` を返す。
クライアントは、`initializationOptions.golem.fileMove` に `version: 1` と `workspaceUri` を渡したときだけ、この要求を使える。
これは `golem/planFileMove` と同じ条件である。

要求と応答は、`golem/planFileMove` の型を元にする。
違うのは、要求が移動の対の配列 `moves` を持つことと、要求の各欄が移動し終えた後の状態を表すことである。
クライアントが一度に見つけた移動（`git mv a.png b.png img/` や、Finder で複数を選んで移したもの）は、まとめて一つの要求で渡す。
対ごとに分けて計画すると、まだ戻していないほかの対の移動先が、移動前の状態で参照先の無い参照に見え、計画の全体がエラーになるためである。

```ts
type PlanMovedReferencesRequest = {
  workspaceUri: string;
  moves: { oldUri: string; newUri: string }[];           // 移動元は今は何も無く、移動先に今ある
  projects: { uri: string; plotCsv: string | null }[];   // 移動し終えた後の一覧
  wikiSheets: { uri: string; title: string | null }[];  // 移動し終えた後の一覧
  documents: { uri: string; text: string; version: number }[]; // 移動し終えた後の URI
  inventoryComplete: boolean;
};
// 応答は golem/planFileMove と同じ { complete, groups, snapshot, chapters }
```

### 検査

サーバーは、移動し終えた状態であることを確かめてから計画を作る。
存在は、親のディレクトリの一覧の名前で、大文字と小文字を区別して比べる。
そのため、大文字と小文字だけを変えた改名も、移動として扱える。

- `moves` が空でないこと。
- 各対の `oldUri` にファイルもフォルダも無いこと。
- 各対の `newUri` にファイルかフォルダがあること。
- 対どうしが独立していること。
  どの対の移動元と移動先も、ほかの対の移動元か移動先と同じでなく、その下にも上にもないこととする。
  連鎖（a を b に、b を c に）と入れ子（フォルダと、その中のファイル）は、順によって移動前の状態が変わるので扱わない。
- 移動元と移動先が、どちらも `workspaceUri` の登録済みのワークスペースの中にあること。
- 移動先がシンボリックリンクでなく、シンボリックリンクを含まないこと。
- `inventoryComplete` が `true` であること。

検査に一つでも通らなければ、該当する URI と理由を持つエラーを返し、編集を返さない。
これは `golem/planFileMove` のエラーと同じ形にする。

### 計画

サーバーは、移動し終えた後の状態を、すべての対の逆の写像で移動前の状態に戻し、`golem/planFileMove` と同じ検査をして計画する。
対が独立しているので、逆の写像はどの順で合成しても同じになる。
計画も、対の順に一つずつ行うのではなく、合成した写像で一度に行う。
対の順に行うと、まだ移していない対の項目が移動元に残っているとみなされ、一度に移せば成り立つ参照（章の原稿と、それが指す画像を一緒に別のプロジェクトへ移すなど）を拒むためである。

- ディスクの索引は、今の索引の各 `newUri` の下を、その対の `oldUri` の下に移したものとする。
  移動元の親のディレクトリが今は無ければ（移した後に空のフォルダを消した場合）、移動前の状態にそのディレクトリを組み直す。
- `projects`、`wikiSheets`、`documents` の URI も、同じく逆の写像で移動前の URI に戻す。
- 閉じた文書の本文は、今のディスクの、移動後のパスから読む。
- 計画は、`golem/planFileMove` の書き換えの規則を、一つの対の写像の代わりに、すべての対を合成した写像で行う。
- 章の登録の移し替えは、移動元のプロジェクトと移動先のプロジェクトの組ごとに一度行う。
  一つの manifest への変更は、一つの編集にまとめる。
  移動先の chapters の末尾に足す順は、`moves` の順とし、同じ対の中では元の章の順とする。

その計画の編集先の URI、`groups` の `projectUri`、`snapshot` の URI を、移動の写像で移動後の URI に写して返す。
`groups` の編集は `TextDocumentEdit` だけで、`RenameFile`、`CreateFile`、`DeleteFile` を含めない。
`snapshot` の本文は、サーバーが読んだ移動後の本文とする。
`chapters` は、`golem/planFileMove` と同じく、章の登録の変更の要約とする。
LSP は、ディスクを変えない。
書き換える参照が無ければ、空の `groups` を返す。

### 索引

LSP は、`workspace/didRenameFiles` を受けて索引を作り直す今の振る舞いを変えない。
クライアントがいつ、どの接続にこの通知を送るかは、クライアントの ADR で決める。

### 文書

仕様書の「プロジェクトをまたぐ移動の計画」の後に、「移動し終えたファイルの参照の編集」の節を足す。
README の Usage の表の `golem lsp` の行と、開発者向けのマニュアルの LSP の章（manual-dev の part1 の 04-lsp）の改名の段落に、この要求を書き足す。

## 実装しないこと

LSP は、自分でファイルシステムを見張って移動を見つけない。
移動を見つけるのは、クライアントの役目である。
`git mv` をエディタが動いていないときに行った場合など、クライアントが見つけられない移動には追従しない。

移動先に前からあったファイルを上書きした移動は扱わない。
移動し終えた後のディスクからは、上書きされたファイルを指していた参照を見分けられないためである。
この場合も検査は通りうるので、上書きを見分けるのはクライアントの役目とする。

連鎖と入れ子の移動の対を、一つの要求で扱わない。
LSP は、編集を自分で当てない（`workspace/applyEdit` を送らない）。
Aleph 以外のエディタ（Neovim、Helix、VS Code）のための設定や拡張は作らない。
`workspace/willRenameFiles` と `golem/planFileMove` の振る舞いは変えない。

## 不変条件

I1: 対が一つで、移動先に移動の前は何も無い（親のディレクトリの一覧の名前で判断する）移動について、移動の前の状態で `golem/planFileMove` が成功するときだけ `golem/planMovedReferences` も成功し、そのとき返す編集を当てた結果は、移動の前に `golem/planFileMove` が返す編集を当ててから移動した結果と、すべてのファイルのパスと本文で一致する。
I2: I1 の移動について、二つの要求が返す `chapters` は一致し、`groups` の編集先の URI と `projectUri` は、`golem/planFileMove` のものを移動の写像で移動後に写したものと一致する。
I3: 独立した二つ以上の対の要求が成功したとき、返す編集を当てた結果では、移動の前に解決できた各参照が、その参照先を合成した写像で写したパスを指し、参照の値のほかの本文は変わらない。
I4: 検査の節の条件のどれかに通らない要求は、エラーを返し、編集を返さない。
I5: 要求を処理しても、ディスクの内容は変わらない。
I6: 書き換える参照が無いとき、`groups` は空である。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| 誰からも参照されないファイルを移した | 空の `groups` | I1, I6 |
| 画像を一つ別のフォルダへ移した | 画像を指す原稿のパスの編集 | I1, I2 |
| 参照される画像二つを一度に別のフォルダへ移した | 二つの画像を指す参照の編集 | I3 |
| 章の原稿と、それが指す画像を、一度に別のプロジェクトへ移した | 成功し、章の登録と画像のパスの編集 | I3 |
| 二つの章を一度に別のプロジェクトへ移した | 両方の manifest への一つずつの編集で、`moves` の順に末尾へ足す | I3 |
| 章の原稿を同じプロジェクトの別のフォルダへ移した | manifest の章のパスの編集 | I1, I2 |
| import を持つ原稿を移した | 移動先の URI に対する、その原稿の import の編集 | I1, I2 |
| 原稿を含むフォルダを移した | フォルダの下を指す参照の編集 | I1, I2 |
| 章を別のプロジェクトへ移した | 両方の manifest の章の登録の編集と、同じ `chapters` | I1, I2 |
| プロジェクトのフォルダごと移した | プロジェクトの所属を保つ編集と、移動後の `projectUri` | I1, I2 |
| 大文字と小文字だけを変えた改名 | 改名した名前への編集 | I1, I2 |
| 最後のファイルを移した後に、空になった移動元のフォルダを消した | 移動元のフォルダを組み直して計画する | I1, I2 |
| Wiki リンクで指される Markdown のシートを移した | Wiki リンクの編集 | I1, I2 |
| 参照先の無い参照を持つプロジェクトで移した | エラー | I1 |
| `moves` が空 | エラー | I4 |
| 連鎖の対（a を b に、b を c に） | エラー | I4 |
| 入れ子の対（フォルダと、その中のファイル） | エラー | I4 |
| 移動元にファイルが残っている | エラー | I4 |
| 移動先にファイルが無い | エラー | I4 |
| 移動先がシンボリックリンク | エラー | I4 |
| 移動先がワークスペースの外 | エラー | I4 |
| `inventoryComplete` が false | エラー | I4 |
| 開いている文書の本文がディスクと違う | `documents` の本文に対する編集 | I1, I2 |

## 受けいれ条件

A1: Aleph の開発ビルドで、ターミナルの `git mv` で画像と章の原稿を移した後、Aleph が受け取った編集を当てると、`golem build` が参照の誤りなしに通る（Aleph の ADR で手で確かめる）。

## テスト設計

root ADR 0426 I1 から I6 を名前の先頭に置いたテストを、golem-lsp のテストに足す。
I1 と I2 は、一時ディレクトリに小さなプロジェクトを作り、境界の表の各移動について、二つの手順の結果を比べる。
一つは、移動の前に `golem/planFileMove` の編集を当ててから移す手順である。
もう一つは、移してから `golem/planMovedReferences` の編集を当てる手順である。

加えて、ファイル 3 個とフォルダ 2 個までのプロジェクトで、どのファイルがどのファイルを参照するか（参照の有無と向き）と、独立した一つか二つの移動の選び方を、すべて数え上げる。
対が一つの入力では I1 と I2 を、二つの入力で要求が成功したときは I3 を確かめる。
I3 は、移動の前に各参照を解決したパスを記録し、編集を当てた後に同じ参照を解決したパスと比べる。
I4 は、表のエラーの行を要求として送り、エラーの形と、編集が無いことを確かめる。
I5 は、要求の前後でディレクトリの全ファイルの内容とパスが一致することを確かめる。
root ADR 0426 A1 は、Aleph の側の手での確かめに含める。

## トレードオフ

移動を見つける役目をクライアントに置くので、Aleph のほかのエディタは、この要求を使わない限り、エディタの外での移動に追従しない。
その代わりに、LSP はファイルシステムを見張らず、今の作りのまま、要求に応じて計画を返すだけでよい。

移動の前の状態を逆の写像で戻して既存の計画を使うので、規則は `golem/planFileMove` と一つにそろう。
そのため、`golem/planFileMove` と同じく、参照先の無い参照やシンボリックリンクがあれば計画を返さない。
外で移した後にこのエラーが出ると、参照は古いまま残る。
その場合は、エラーの URI と理由を見て、手で直す必要がある。

一度に見つけた独立した移動は一つの要求でまとめて計画するが、連鎖と入れ子の移動は扱わない。
これらは、移動前の状態が順によって変わり、移動し終えた後の状態から一つに決められないためである。
クライアントがこれらを見つけたときは、参照は古いまま残る。

## 参考文献

- [root ADR 0338](0338-update-references-on-file-and-folder-renames.md)
- [root ADR 0399](0399-plan-moves-across-project-boundaries.md)
- Language Server Protocol Specification 3.17, Workspace Edit と File Operations
