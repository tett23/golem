## Added

## Changed

## Removed

## Fixed

## Unsorted

- old ([#2](https://github.com/tett23/golem/pull/2))
- a ([#3](https://github.com/tett23/golem/pull/3))
- b ([#4](https://github.com/tett23/golem/pull/4))
- not an ADR ([#5](https://github.com/tett23/golem/pull/5))

## ADRs

- [docs/adr/0000-old.md](https://github.com/tett23/golem/blob/v0.1.0/docs/adr/0000-old.md)
- [docs/adr/0001-x.md](https://github.com/tett23/golem/blob/v0.1.0/docs/adr/0001-x.md)
- [docs/golem-cli/adr/0002-y.md](https://github.com/tett23/golem/blob/v0.1.0/docs/golem-cli/adr/0002-y.md)

## ADRs whose status changed

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
gh attestation verify golem-v0.1.0-x86_64-linux.tar.gz --repo tett23/golem
```
