# ADR 0152: Hackage の索引のキャッシュから `01-index.tar.gz` を `rm` で除く

ステータス: 採択

## 文脈

[ADR 0141](0141-smaller-ghc-and-hackage-index-caches.md) は、Hackage の索引のキャッシュから、cabal がビルドの計画に使わない `01-index.tar.gz` を除くと決めた。
実装は、キャッシュの `path` に除外の行を足した（[ci.yml#L239-L251](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/.github/workflows/ci.yml#L239-L251)）。

```yaml
path: |
  ~/.cabal/packages/hackage.haskell.org
  !~/.cabal/packages/hackage.haskell.org/01-index.tar.gz
```

この除外は働いていない。
2026-11-04 の二度めの監査（[PR #525](https://github.com/tett23/golem/pull/525) の docs/audits/2026-11-04-rc4-followup-conformance.md の F-16）が、actions/cache の作りと実測から示した。

### actions/cache の `path` の扱い

actions/cache（3edfce9、v6）の保存は、次のように動く。
行番号は `dist/save/index.js` のものである。

1. `resolvePaths` が、`path` の行を `@actions/glob` に `implicitDescendants: false` で渡し、当たったパスを並べる（43319 行めから 43326 行め）。
2. `@actions/glob` の `matchDirectories` は既定で真である（42267 行め）。ディレクトリの行に当たると、そのディレクトリ自身を一件として返す（43007 行め）。
3. tar は、並べたパスを `--files-from` で受け、`--no-recursion` を付けない（94112 行め）。ディレクトリを一件として受けると、その中身をすべて書く。

`!` の行は、glob が当てたパスの一覧から、そのパスを除くだけである。
`~/.cabal/packages/hackage.haskell.org` の行はディレクトリ一件に当たり、`01-index.tar.gz` はそもそも一覧にない。
tar がディレクトリの中身を書くときに、`01-index.tar.gz` も書く。

監査は、`…/hackage.haskell.org/**` と `!` の組なら除外が働くとした。
これも働かないと見られる。
`@actions/glob` は、末尾が `**` の型を、その直前のディレクトリ自身にも当てる（42710 行めから 42720 行めの `match` は、`/foo/**` を `/foo` に当てるために末尾に区切りを足す）。
`hackage.haskell.org` 自身が一件として tar に渡り、中身がすべて入る。
`…/hackage.haskell.org/*` と `!` の組なら、ディレクトリ自身には当たらず、直下のファイルを一件ずつ並べるので、除外は働くはずである。
どちらも、手元で `@actions/glob` を動かして確かめてはいない。

### 実測

| | x86-64 | aarch64 |
|---|---|---|
| 0141 の前（[41786252402](https://github.com/tett23/golem/actions/runs/41786252402)） | 259 MB | 259 MB |
| 0141 の後の二回目（[41817232702](https://github.com/tett23/golem/actions/runs/41817232702)） | 242 MB | 242 MB |

手元の索引（index-state 2026-10-11）では、`01-index.tar.gz` が 139 MB だった。
圧縮済みのファイルはキャッシュの zstd でも縮まないので、除外が働けば 100 MB 前後になるはずである。
17 MB の差の原因は分かっていない。

### 誤った説明の記録

計測の記録 [docs/ci-timings/2026-11-04-smaller-ghc-and-index-caches.md](../ci-timings/2026-11-04-smaller-ghc-and-index-caches.md) は、縮まなかった理由を「ランナーの上の `01-index.tar.gz` はずっと小さいと見られる」と推測した。
原因の取り違えである。
`docs/ci-timings/` の記録は、コミットした後は変えない約束である（CLAUDE.md）。
この記録は直さず、新しい記録で訂正する。

### CI で確かめていないこと

0141 は、`01-index.tar.gz` のない索引で cabal が計画を立てられることを、手元の cabal-install 3.18.1.0 で確かめ、CI の 3.16.1.0 では確かめていないとした。
除外が働いていないので、0141 の後の CI の実行は、いつも `01-index.tar.gz` のそろった索引で動いている。
この点は CI でまだ確かめられていない。

## 実装すること

### 除き方

`cabal update` の後に、`01-index.tar.gz` を `rm` で消す。

```yaml
- id: index
  name: Cache the Hackage index (docs/adr/0009, docs/adr/0141, docs/adr/0152)
  uses: actions/cache@v6
  with:
    path: ~/.cabal/packages/hackage.haskell.org
    key: hackage-index-no-gz-${{ hashFiles('cabal.project.freeze') }}
- if: steps.index.outputs.cache-hit != 'true'
  run: |
    cabal update
    ls -l ~/.cabal/packages/hackage.haskell.org/01-index.tar.gz
    rm ~/.cabal/packages/hackage.haskell.org/01-index.tar.gz
    du -sh ~/.cabal/packages/hackage.haskell.org
```

- `path` から `!` の行を消し、ディレクトリの一行だけにする。
- `cabal update` の手順で、`01-index.tar.gz` の大きさを `ls -l` で書いてから、`rm` で消す。`-f` は付けない。cabal がファイルの名前を変えたら、手順が失敗して気づける。
- キーを `hackage-index-no-gz-` で始まる名前に変える。今のキー `hackage-index-tar-…` のままでは、`01-index.tar.gz` を含む今のキャッシュが当たり続け、保存し直されない。
- キャッシュはジョブの終わりに保存されるので、消した後の中身が入る。キャッシュが当たった実行では `cabal update` を飛ばし、`01-index.tar.gz` のない索引で `cabal build` が動く。
- 計測の結果を、新しい記録 `docs/ci-timings/<日付>-hackage-index-without-tar-gz.md` に書く。記録には、2026-11-04 の記録の「ランナーの上の `01-index.tar.gz` はずっと小さい」が誤りで、原因は actions/cache の `path` の扱いだったことを書く。2026-11-04 の記録は変えない。

### 文書

- manual-dev の CI の章（`manual-dev/part2/11-ci-jobs.gm` の 115 行め）の「Hackage の索引のキャッシュには、…（`01-index.tar.gz`）を入れない」を、「`cabal update` の後に消してから保存する」に改め、この ADR の注を足す。
- `ci.yml` のキャッシュの手順の上の注（今の 239 行めから 241 行め）を、`rm` で消す理由に改める。
- [docs/adr/0141](0141-smaller-ghc-and-hackage-index-caches.md) のステータスの行に、「`01-index.tar.gz` の除き方は [ADR 0152](0152-remove-hackage-index-tar-gz-before-cache.md)」を足す。

## 実装しないこと

- **`…/hackage.haskell.org/*` と `!` の組。** 働くはずだが、`@actions/glob` の型の当て方と tar の再帰の両方に頼る。`rm` は、何が入るかを手順の中で見て確かめられる。
- **`…/hackage.haskell.org/**` と `!` の組。** 上のとおり、ディレクトリ自身が tar に渡るので働かないと見られる。
- **race.yml の索引のキャッシュ（`hackage-index-…`）を変えること。** 別のワークフローで、0141 の対象でもなかった。
- **ほかのキャッシュの `path` を見直すこと。** ci.yml の actions/cache の `path` で `!` を使っているのは、この一か所だけである。`format` の `pattern` の `!` は fourmolu の型で、actions/cache ではない。

## テスト設計

### 先に書いて失敗させるテスト（`scripts/ci/test.sh`）

0141 が足した「`path` が `01-index.tar.gz` を除き、キーが `hackage-index-tar-` で始まる」の検査を、次に置き換える。

- Hackage の索引のキャッシュの `path` が `~/.cabal/packages/hackage.haskell.org` の一行だけで、`!` の行がないこと。
- そのキーが `hackage-index-no-gz-${{ hashFiles('cabal.project.freeze') }}` であること。
- `steps.index.outputs.cache-hit != 'true'` の手順が、`cabal update` の後に `rm ~/.cabal/packages/hackage.haskell.org/01-index.tar.gz` を走らせること。
- `ci.yml` の actions/cache の手順の `path` に、`!` で始まる行がないこと。actions/cache の `!` は、ファイルを一件ずつ並べる型と組まないと働かず、この誤りは `path` の字面の検査では捉えられないためである。

今の main では、`path` に `!` の行があり、キーは `hackage-index-tar-` で、`rm` はないので、四つとも失敗する。

### 自動テストにできないものの確かめ方

実装のプルリクエストで、次を確かめて新しい記録に書く。

- キャッシュが外れた一回目の実行で、`ls -l` が書いたランナーの上の `01-index.tar.gz` の大きさ。2026-11-04 の記録の推測を、実測で確かめる。
- 同じ一回目の実行で、`01-index.tar.gz` を消した後の `cabal build` と `cabal test` が、x86-64 と aarch64 の両方で通ること。消した後に同じジョブで `cabal build` が動くので、0141 が CI で確かめていなかった「`.tar.gz` なしで cabal-install 3.16.1.0 が計画を立てられる」ことを、この一回目で確かめられる。
- 二回目の実行で、キャッシュの `Cache Size` と `gh api repos/tett23/golem/actions/caches` の `hackage-index-no-gz-…` の大きさが、242 MB から `01-index.tar.gz` の大きさほど小さいこと。手順の秒数も記録する。
- 二回目の実行の `cabal build` が、`Up to date` か、変えたモジュールだけをコンパイルすること。`cabal update` を求める誤りや警告がログにないこと。

一回目で `cabal build` が `01-index.tar.gz` なしで失敗したときは、`rm` をやめ、`path` をディレクトリの一行に戻し（`!` の行は働かないので消す）、0141 の一つめの項目をあきらめたことを記録に書く。
その場合は、この ADR のステータスを却下にし、0141 のステータスの行にそのことを書く。

## トレードオフ

- 見込める短縮は、索引のキャッシュの復元で 1 秒から 2 秒と小さい（0141 の見積もり）。
- キーを変えた最初の実行で、すべてのランナーで `cabal update`（15 秒から 18 秒）が走る。
- cabal がビルドの計画に `01-index.tar.gz` を読まないことに頼る。cabal-install を上げたときに、この前提が崩れれば `cabal build` が失敗するか、索引を取り直す。失敗すれば CI で気づけるが、黙って取り直す場合は、手順の秒数でしか気づけない。
- `rm` に `-f` を付けないので、cabal-install がファイルの名前を変えると、キャッシュが外れた実行で CI が失敗する。黙って大きなキャッシュに戻るより、気づけるほうを選ぶ。

## 決めたことの記録

- **採択**：メンテナーが採択した（2026-11-04）。この ADR が決めてほしい点として挙げた項目は、どれも ADR の推奨のとおりとする。

## 参考文献

- [PR #525](https://github.com/tett23/golem/pull/525) の docs/audits/2026-11-04-rc4-followup-conformance.md（F-16）
- [docs/adr/0009](0009-ci-speed.md)、[docs/adr/0141](0141-smaller-ghc-and-hackage-index-caches.md)
- [docs/ci-timings/2026-11-04-smaller-ghc-and-index-caches.md](../ci-timings/2026-11-04-smaller-ghc-and-index-caches.md)
- [ci.yml（今の索引のキャッシュ）](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/.github/workflows/ci.yml#L239-L251)、[scripts/ci/test.sh（0141 の検査）](https://github.com/tett23/golem/blob/4f86b945b6e60913fc63e22c0bf4ec14e5114bed/scripts/ci/test.sh#L979-L988)
- actions/cache 3edfce9 の `dist/save/index.js`（`resolvePaths`、`@actions/glob` の `Pattern.match` と `globGenerator`、`getTarArgs`）. https://github.com/actions/cache/blob/3edfce9056124e459a23f683a21433670d47daca/dist/save/index.js
- actions/cache, "Inputs"（`path` の `!` による除外）. https://github.com/actions/cache#inputs
