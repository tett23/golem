# GHC が同梱する libffi のライセンスの文書

Linux の GHC の配布物は、RTS の一部として libffi を `libCffi.a` という名前で同梱している。
Linux の `golem` を静的にリンクすると、このアーカイブが実行ファイルに入る。
Alpine の `libffi.a` ではないので、`licenses/alpine/` からは文書を取れない。
そこで、`scripts/release/link-components.sh` は GHC の libdir の下の `libCffi.a` を構成要素 `ghc-libffi` とし、`scripts/release/licenses.sh` はこのディレクトリの `LICENSE` を `THIRD_PARTY_LICENSES/ghc-libffi/` に写す（[ADR 0007](../../docs/adr/0007-third-party-licenses.md)）。

## 出どころ

- **GHC**：9.10.3（`GHC_VERSION`）。
- **libffi**：3.4.6（MIT）。
- **取得元**：GHC の `ghc-9.10.3-release` のタグが指すサブモジュール [ghc/libffi-tarballs](https://gitlab.haskell.org/ghc/libffi-tarballs) のコミット `89a9b01c5647c8f0d3899435b99df690f582e9f1` の `LICENSE`。
- **SHA-256**：`67894089811f93fca47a76f85e017da6f8582d4ba0905963c6e0f1ad6df7a195`。

GHC の版を上げたら、その版が同梱する libffi を確かめ、`LICENSE` と `GHC_VERSION` を更新する。
`GHC_VERSION` が使っている GHC の版と食い違うと、`licenses.sh` は失敗する。
