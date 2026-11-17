# Golem [ADR 0335](../../docs/adr/0335-emet-expression-repl.md) の対話試験

Ruby 4.0.7 と IRB 1.16.0 の [入力と出力](irb-session.txt) は、次の手順で再現できる。

```sh
printf '1 +\n2\n1 / 0\n6\n_ + 1\nexit\n' | irb -f --noreadline --simple-prompt
```

Golem の [実装差分](review-implementation.patch) は [基準コミット](BASE) から作った。
別の作業ディレクトリでそのコミットに差分を適用し、次のコマンドを実行する。
最後の引数はレビュー用 worktree にある試験のパスに合わせる。

```sh
cabal build --offline -j2 golem-cli:exe:golem
node /path/to/proposed-review/experiments/repl/check.mjs "$(cabal list-bin golem-cli:exe:golem)"
```

旧コマンドを持つ実行ファイルでは、新しい入口の [最初の 34 試験](review-red.jsonl) のうち引数エラーの 1 件だけが通った。
入口と継続入力を変更した後、疑似端末で Ctrl-C を送ると [35 件中 1 件](cancel-red.jsonl) が失敗した。
未完の入力の取り消しを実装した macOS arm64 の [最終結果](review-green.jsonl) は 35 件すべて成功した。
端末を長時間開いた際のヒープ、Windows、WASM での実行は未確認である。
