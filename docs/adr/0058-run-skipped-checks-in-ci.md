# ADR 0058: CI で動いていなかった二つの検査を CI で動かす

ステータス: 採択

## 文脈

v0.1.0-rc3 の作業で、スキップされているテストを調べた。
無効にしたテストはなかった。
外部の道具（qpdf、cddl、openssl）が要るテストは、手元では道具がなければスキップし、CI では `GOLEM_REQUIRE_EXTERNAL_TOOLS` で道具を必須にしている。

ただ、CI で一度も動いていない検査が二つあった。

1. **パブリックドメインの十冊をすべてのターゲットに組む検査**（[ADR 0026](0026-ten-public-domain-fixtures.md)）。golem-driver のテストは、十冊を出力を書かずに検査し、環境変数 `GOLEM_PD_BOOKS` があるときだけ、すべてのターゲットに組む。CI はこの変数を付けていない。[ADR 0026](0026-ten-public-domain-fixtures.md) はトレードオフの節で、組版の段階で生じる誤り（G07xxx など）が CI では見つからないことを認めていた。
2. **固定した版の Claude Code が、リリースのスクリプトの使うフラグを持つかの検査**（[ADR 0044](0044-release-workflow-hardening.md)）。`scripts/release/test.sh` は、`mise.toml` に固定した版の `claude` が `PATH` にあるときだけ、`claude --help` に `--tools` と `--strict-mcp-config` があることを確かめ、なければ `skip:` と書いて飛ばす。CI の `release-scripts` ジョブは Claude Code を入れないので、いつも飛ばしている。固定の版を上げたときにフラグが変わっていても、リリースの `notes` ジョブを動かすまで分からない。

手元で動かすと、どちらも通った。
十冊は、qpdf のない手元で qpdf の検査を飛ばして、27 件がすべて通った（約 19 秒）。
`claude --help` の検査は、mise で固定の 2.1.292 を入れて、161 件がすべて通った。

メンテナーは、両方を CI で動かすと決めた。

## 実装すること

### 十冊を組む検査

- `ci.yml` の `build` ジョブの `cabal test all` のステップの `env` に、`GOLEM_PD_BOOKS: "1"` を足す。テストを走らせる二つのランナー（x86-64 の `tests` と aarch64 の `all`）の両方で動く。
- このステップは `GOLEM_REQUIRE_EXTERNAL_TOOLS` を付けており、qpdf が入っているので、十冊の PDF の qpdf の検査も必須になる。
- README と開発者のマニュアルの、十冊の検査の説明（「CI では検査だけを行う」の旨）を、CI ではすべてのターゲットに組むと改める。手元では今のとおり、変数を付けたときだけ組む。
- [ADR 0026](0026-ten-public-domain-fixtures.md) のステータスの行を「採択→CI で十冊をすべてのターゲットに組むことは [ADR 0058](0058-run-skipped-checks-in-ci.md)」とする。

### `claude --help` の検査

- `ci.yml` の `release-scripts` ジョブで、`scripts/release/test.sh` の前に、リリースの `notes` ジョブと同じく `jdx/mise-action` で `mise.toml` の固定の版の Claude Code を入れる（`MISE_TRUSTED_CONFIG_PATHS` と `cache: false` も同じにする）。API キーは渡さない。`claude --help` は認証なしで動く。
- `scripts/release/test.sh` に、環境変数 `GOLEM_REQUIRE_CLAUDE=1` のとき、固定の版の `claude` がなければ飛ばさずに失敗にする分岐を足す。CI のステップはこの変数を付ける。手元では今のとおり、なければ飛ばす。
- [ADR 0044](0044-release-workflow-hardening.md) のステータスの行に「、CI で `claude --help` を確かめることは [ADR 0058](0058-run-skipped-checks-in-ci.md)」を足す。

## 実装しないこと

- 十冊を組んだ出力のハッシュを、決定性の検査（`scripts/determinism.sh`）に加えること。十冊の検査は誤りがないことを確かめるためのもので、出力の一致は今の決定性の検査が扱う。
- 手元の既定で十冊を組むこと。手元のテストの時間を延ばさないため、今のとおり変数を付けたときだけ組む。
- Claude Code でリリースノートを実際に書かせること。API キーを CI のふだんのジョブに渡さない。

## テスト設計

- `scripts/release/test.sh` に、偽の `PATH`（固定の版の `claude` がない）と `GOLEM_REQUIRE_CLAUDE=1` で走らせると失敗し、変数がなければ `skip:` と書いて通ることを確かめる項目を足す。先に書いて、今のスクリプトで失敗することを確かめる。
- `scripts/ci/test.sh` に、`ci.yml` の `cabal test all` のステップが `GOLEM_PD_BOOKS` を付けていることと、`release-scripts` ジョブが `test.sh` の前に mise で Claude Code を入れ、`GOLEM_REQUIRE_CLAUDE` を付けていることを確かめる項目を足す（今の `step_if` と同じ形）。
- CI の時間：十冊を組むと、手元では約 19 秒増えた。実装のプルリクエストで、`build` ジョブの時間の増え方を、`docs/ci-timings/` の記録と比べて確かめる。

## トレードオフ

- `build` ジョブがおよそ 20 秒から 1 分延びる。組版の段階の誤りを CI で見つけられることのほうが重い。
- `release-scripts` ジョブで npm から Claude Code を取ってくるので、ジョブが延び、npm のレジストリの障害で失敗しうる。リリースの `notes` ジョブも同じ取り方をしているので、取り方を一つにそろえられる。
- 固定の版を上げるプルリクエストは `mise.toml` を変え、docs だけの変更にはならないので、`release-scripts` が走り、新しい版のフラグを確かめられる（[ADR 0021](0021-docs-workflow-and-ci-gate.md)）。

## 参考文献

- [ADR 0026](0026-ten-public-domain-fixtures.md)
- [ADR 0044](0044-release-workflow-hardening.md)
