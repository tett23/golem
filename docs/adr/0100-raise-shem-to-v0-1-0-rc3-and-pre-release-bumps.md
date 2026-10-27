# ADR 0100: shem を v0.1.0-rc3 に上げ、pre-release の識別子を変える版の上げ方を決める

ステータス: 採択

## 文脈

見た目の回帰テストは、PDF のページを shem で画像にする（[ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md)）。
Golem は shem の版と、三つのアーカイブの SHA-256 を [`scripts/visual/fetch-shem.sh`](https://github.com/tett23/golem/blob/22f6975623903baf42236964a8d29ae244b06a83/scripts/visual/fetch-shem.sh#L29-L34) に固定している（[ADR 0093](0093-fetch-shem-pinned-by-version-and-sha256.md)）。
今の版は v0.1.0-rc2 である。

### shem v0.1.0-rc3

shem は 2026-10-27 に v0.1.0-rc3 を出した（pre-release）。
リリースノートによれば、rc3 は、Linux の二つのアーカイブ（musl で静的にリンクしたもの）が `--jobs` を増やすと遅くなる不具合を直した版である。
musl のメモリの確保は一回ごとにロックを取り、rc2 は一ページに約 27 万回確保していた。
rc3 は確保を一ページあたり数百回に減らした（[shem ADR 0013](https://github.com/tett23/shem/blob/6c93aa9702e713e5d1af963d04e9a1b453bb3975/docs/adr/0013-fewer-allocations-for-musl-threads.md)）。
リリースノートは、同じ入力に対して rc2 と同じ画素と、同じ PNG と PPM のバイトを出すと書いている。
shem のテストは、Golem の『蟹工船』の 516 枚の画像（72 dpi と 150 dpi、PNG と PPM）が rc2 のバイトと一致することを確かめている。

[ADR 0095](0095-visual-job-in-ci.md) の `visual` ジョブは、PDF を一つずつ描く。
rc3 に上げても、この描き方（一度に一つの PDF、shem の既定の `--jobs`）は変えない。
rc2 のスレッドの遅さを避けるために PDF を並べて描く案（下書きの ADR 0098）は、rc3 で要らなくなったので取り下げた。

### [ADR 0093](0093-fetch-shem-pinned-by-version-and-sha256.md) が決めていないこと

[ADR 0093](0093-fetch-shem-pinned-by-version-and-sha256.md) の「版を上げるとき」は、shem の取り決め（[shem ADR 0001](https://github.com/tett23/shem/blob/152858295b7949514e05d0ae009e858a1262dfa0/docs/adr/0001-scope-golem-contract-and-determinism.md#L42-L48)）に合わせて、二つの場合を決めている。

- マイナーバージョンを上げるときは、画素が変わりうるので、同じプルリクエストで参照を作り直す。
- パッチバージョンを上げるときは、参照を変えない。CI でページのハッシュが変われば、shem の側で直す。

rc2 から rc3 への変更では、`0.1.0` の部分が同じで、pre-release の識別子だけが変わる。
shem の取り決めは、画素を変える変更でマイナーを、変えない変更でパッチを上げると定めるが、pre-release の識別子の進め方は定めていない。
rc3 のリリースノートは画素を変えないと書いているものの、識別子だけの変更が画素を変えないという約束は、取り決めの中にない。
`0.1.0-rc3` から `0.1.0` への変更も、識別子だけの変更である。
[ADR 0093](0093-fetch-shem-pinned-by-version-and-sha256.md) は、こうした版上げで参照をどう扱うかを決めていない。

[ADR 0093](0093-fetch-shem-pinned-by-version-and-sha256.md) の規則には、shem の画素と関係なく参照が変わる場合も抜けている。
開発者のマニュアルの「ラスタライザ shem を取得する」の節は、固定した版の名前を本文に書いている（[08-build-test.gm](https://github.com/tett23/golem/blob/22f6975623903baf42236964a8d29ae244b06a83/manual-dev/part2/08-build-test.gm#L219)）。
開発者のマニュアルは見た目の回帰テストの入力の一つなので、版を上げると、その段落のあるページの参照が変わる。
これは Golem の入力が変わったためで、shem の画素が変わったためではない。
[ADR 0093](0093-fetch-shem-pinned-by-version-and-sha256.md) のパッチの規則を文字どおりに読むと、パッチの版上げでは、このページの参照も変えられない。

### 下書きのプルリクエストでの確かめ

下書きのプルリクエスト [#439](https://github.com/tett23/golem/pull/439) で、rc3 への版上げを試した。

rc3 の release から三つのアーカイブと `SHA256SUMS` だけを取り、各アーカイブの SHA-256 を計算して、`SHA256SUMS` と release のアセットの digest に一致することを確かめた。

| アーカイブ | 大きさ | SHA-256 |
| --- | --- | --- |
| `shem-v0.1.0-rc3-x86_64-unknown-linux-musl.tar.gz` | 520,204 バイト | `9a49e705b1ab31cb28f34838561b85627181d743a2f3f68b887374a217b85c1b` |
| `shem-v0.1.0-rc3-aarch64-unknown-linux-musl.tar.gz` | 501,288 バイト | `c49dfe7452d5e8c11100ebdbc7be8a6aecb94dfdcea1122e3266b896b3b1efc1` |
| `shem-v0.1.0-rc3-aarch64-apple-darwin.tar.gz` | 416,038 バイト | `2097571f5a1ea13e5442e1f2a7907bffe94090564499ce23b20abea078ebae6f` |

`SHA256SUMS`（341 バイト）の、release のアセットの digest は `aad0beb51f8ffcd69cda4a4ffeb2abfff4b82c239deb5903ca4bab012660cbc4` である。

参照への影響は次のとおりだった。

- `scripts/visual/check.sh` は、rc3 で、macOS の aarch64 の手元で、CI が組んだ PDF に対して通った。
- #439 の `visual` ジョブ（x86-64 の Linux、実行 [40502975549](https://github.com/tett23/golem/actions/runs/40502975549)）で参照と違ったのは、`manual-dev` の 92 ページだけだった。このページは、上の段落（固定した版の名前）を含む。
- 新しい PDF の 92 ページを rc2 と rc3 で描くと、同じ SHA-256 になった。違いは、マニュアルの本文の `v0.1.0-rc2` を `v0.1.0-rc3` に変えたことだけから来る。
- #439 は、`scripts/visual/pages/manual-dev.txt` の 92 ページの行を、成果物 `visual-diff` の一覧から写して直した（[ADR 0096](0096-before-and-after-images-of-changed-pages.md)）。その後の実行で、`visual` を含むすべての検査が通った。

rc3 への版上げで、shem の描くページの画素は一つも変わらなかった。

## 実装すること

### rc3 への版上げ

- `scripts/visual/fetch-shem.sh` の版を `0.1.0-rc3` にし、三つの SHA-256 を上の表の値にする。実装のプルリクエストでも、取ったアーカイブから計算した値と照らしてから書く。
- `docs/specifications.md` の「識別子」の節と、開発者のマニュアル（`manual-dev/part2/08-build-test.gm`）の、固定した版の名前を `v0.1.0-rc3` にする。
- `scripts/visual/pages/manual-dev.txt` のうち、版の名前を含むページの行を、CI の成果物 `visual-diff` の一覧から写して直す。ほかの行は変えない。
- `visual` ジョブの描き方は変えない。PDF を一つずつ描き、`--jobs` を渡さず、shem の既定に任せる。

### pre-release の識別子を変える版上げ

- 古い版と新しい版のどちらかが pre-release の識別子（`-rc3` など）を持つとき、その版上げはマイナーバージョンを上げるときと同じに扱い、参照を作り直してよい。`0.1.0-rc2` から `0.1.0-rc3`、`0.1.0-rc3` から `0.1.0`、`0.1.0-rc3` から `0.1.1` がこれに当たる。
- そのプルリクエストは、shem が画素を変えたかどうかを説明に示す。プルリクエストの PDF を古い版と新しい版の両方で描き、ページの SHA-256 が違うページを入力ごとに挙げる。違うページがなければ「なし」と書く。CI の `visual` は新しい版だけで描くので、この比べ方は手元で行う。
- 古い版と新しい版で SHA-256 が違うページがあれば、shem のリリースノートの「変更」を説明に引き、そのページの前後の画像（`visual-diff`）を見てから参照を受け入れる。

### 版の名前を含むページ

- 版上げのプルリクエストが Golem の入力（マニュアルの本文など）を変えたために変わったページの参照は、版上げの種類（マイナー、パッチ、pre-release）によらず直してよい。直してよいのは、古い版と新しい版で同じ SHA-256 になるページに限る。
- [ADR 0093](0093-fetch-shem-pinned-by-version-and-sha256.md) のパッチの規則（参照を変えない）は、shem の画素のために変わる参照に限ると読む。

### 文書

- CONTRIBUTING.md と、開発者のマニュアルの「ラスタライザ shem を取得する」の節に、pre-release の識別子を変える版上げの扱い、古い版と新しい版で描いて比べる手順、版の名前を含むページの扱いを書く。
- [ADR 0093](0093-fetch-shem-pinned-by-version-and-sha256.md) のステータスの行を「採択→版を上げるときの pre-release と、Golem の入力が変わるページの扱いは ADR 0100」に変える。

## 実装しないこと

- 古い版と新しい版で描いて比べるスクリプトと、CI で古い版を取ること。版上げは数か月に数回のプルリクエストで、そのために古い版の固定値も `fetch-shem.sh` に持つことになる。手順は、古いコミットの `fetch-shem.sh` で取った shem を `SHEM` に渡せば手元で足りる。
- pre-release の版を固定しないこと。[ADR 0093](0093-fetch-shem-pinned-by-version-and-sha256.md) は、shem が 0.x の間は pre-release も固定してよいとしている。
- 開発者のマニュアルの本文から版の名前を消すこと。消せば版上げで変わるページはなくなるが、読み手は固定した版を知るために `fetch-shem.sh` を開くことになる。
- `visual` の描き方を変えること（取り下げた下書きの ADR 0098）。

## テスト設計

版上げは、スクリプトの定数を変えるだけで、振る舞いは変わらない。
`fetch-shem.sh` の振る舞いは、今の `scripts/visual/test.sh` が、スクリプトの中の SHA-256 をテストのアーカイブの値に置き換えた写しで確かめている。
三つの SHA-256 をテストにも写すと、写しと写しを比べるだけになるので、自動のテストは足さない。

実装のプルリクエストで、次を確かめて記録する。

- 手元の macOS の aarch64 で `scripts/visual/fetch-shem.sh` が rc3 のアーカイブを取り、`third_party/shem/shem --version` が `shem 0.1.0-rc3` を出すこと。
- CI の x86-64 の Linux の `visual` ジョブで、同じく rc3 が入り、参照と比べて通ること。aarch64 の Linux のアーカイブは、取ったものの SHA-256 が `SHA256SUMS` と一致することだけを確かめる。
- プルリクエストの PDF を rc2 と rc3 で描き、SHA-256 の違うページがないこと。参照の差分が、版の名前を含む `manual-dev` のページだけであること。
- `scripts/visual/test.sh` と `scripts/ci/test.sh` が通ること。
- 文書を変えた後に、`sh scripts/manual/build.sh manual-dev` が diagnostic を出さずに通ること。

## トレードオフ

- pre-release の版上げをマイナーと同じに扱うのは、パッチと同じに扱うより緩い。shem が識別子だけの変更で画素を変えても、参照を受け入れられる。その代わりに、古い版と新しい版で描いて比べた結果を説明に書かせ、画素の変化を黙って受け入れないようにする。
- パッチと同じに扱えば厳しいが、shem の取り決めにない約束を shem に負わせることになる。shem の rc は v0.1.0 に向けた候補で、候補のあいだに画素を変える修正が入りうる。
- 古い版と新しい版で描いて比べる手順は手作業で、説明に書かれた結果を CI は確かめない。レビューでは、参照の差分と、説明に挙げたページが合っているかを見る。
- 版の名前を本文に書いたマニュアルのページは、版上げのたびに参照が変わる。

## 参考文献

- [ADR 0093](0093-fetch-shem-pinned-by-version-and-sha256.md)
- [ADR 0094](0094-visual-regression-page-hashes-at-72-dpi.md)
- [ADR 0095](0095-visual-job-in-ci.md)
- [ADR 0096](0096-before-and-after-images-of-changed-pages.md)
- shem v0.1.0-rc3 の release https://github.com/tett23/shem/releases/tag/v0.1.0-rc3
- [shem ADR 0013](https://github.com/tett23/shem/blob/6c93aa9702e713e5d1af963d04e9a1b453bb3975/docs/adr/0013-fewer-allocations-for-musl-threads.md)
- [shem ADR 0001「目的と版ごとの範囲、Golem との取り決め、決定性の約束」](https://github.com/tett23/shem/blob/152858295b7949514e05d0ae009e858a1262dfa0/docs/adr/0001-scope-golem-contract-and-determinism.md)
- [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html)（pre-release の識別子）
- 下書きのプルリクエスト [#439](https://github.com/tett23/golem/pull/439) と CI の実行 [40502975549](https://github.com/tett23/golem/actions/runs/40502975549)
