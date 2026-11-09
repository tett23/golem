## Added

## Changed

## Removed

## Fixed

## Unsorted

- accept 0010 ([#10](https://github.com/tett23/golem/pull/10))
- a link in 0011 ([#11](https://github.com/tett23/golem/pull/11))
- implement 0012 ([#12](https://github.com/tett23/golem/pull/12))
- add 0013 ([#13](https://github.com/tett23/golem/pull/13))
- implement 0013 ([#14](https://github.com/tett23/golem/pull/14))
- links of 0014 ([#15](https://github.com/tett23/golem/pull/15))

## ADRs

- [docs/adr/0013-new.md](https://github.com/tett23/golem/blob/v1.1.0/docs/adr/0013-new.md)

## ADRs whose status changed

- [docs/adr/0010-status.md](https://github.com/tett23/golem/blob/v1.1.0/docs/adr/0010-status.md): 提案 → 採択
- [docs/golem-cli/adr/0012-module.md](https://github.com/tett23/golem/blob/v1.1.0/docs/golem-cli/adr/0012-module.md): 採択（未実装） → 採択
- [docs/golem-cli/adr/0014-links.md](https://github.com/tett23/golem/blob/v1.1.0/docs/golem-cli/adr/0014-links.md): 採択→x は [ADR 0010](https://github.com/tett23/golem/blob/v1.0.0/docs/adr/0010-status.md) → 採択→x は [ADR 0010](https://github.com/tett23/golem/blob/v1.1.0/docs/adr/0010-status.md)、y は [golem-cli ADR 0012](https://github.com/tett23/golem/blob/v1.1.0/docs/golem-cli/adr/0012-module.md#文脈)、z は [ADR 0013](https://github.com/tett23/golem/blob/v1.1.0/docs/adr/0013-new.md)、w は [下](https://github.com/tett23/golem/blob/v1.1.0/docs/golem-cli/adr/0014-links.md#文脈)

## Verifying the downloads

`SHA256SUMS` lists the SHA-256 of every archive.
Check the archives you downloaded:

```sh
sha256sum --ignore-missing -c SHA256SUMS
```

On macOS, use `shasum -a 256 --ignore-missing -c SHA256SUMS`.

Each `golem-*.tar.gz` archive has a build provenance attestation.
The manuals, the sample plugins (`.wasm`) and the GMP source have none; check them with `SHA256SUMS` only.
Check an archive with the GitHub CLI:

```sh
gh attestation verify golem-v1.1.0-x86_64-linux.tar.gz --repo tett23/golem
```
