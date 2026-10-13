# Contributing to Golem

[日本語](./CONTRIBUTING.md)

The Japanese version of this document is canonical.
This English version is a translation; where the two differ, the Japanese version prevails.

Every change to Golem starts with an ADR (Architecture Decision Record).
Contributors are expected to keep this order: decide the specification, write the tests, see them fail, then implement.
This document describes that order and the conventions of the repository.

## Development environment

The build and test instructions are in the Development section of [README.md](./README.md).
After cloning, enable the Git hooks first.

```bash
git config core.hooksPath .githooks
```

The hook calls [adr-guard](https://github.com/tett23/adr-guard) v0.5.0 or later, so install it beforehand.
This setting is not stored in the repository, so run it in every clone.

## How a change proceeds

1. Write an ADR and get it reviewed.
2. Write the tests listed in the ADR's test design and confirm that they fail.
3. Implement until the tests pass.
4. Update the specification and the README.
5. Push a branch and open a pull request.
6. Once CI passes, merge it into `main` with no-ff.

Fixing typos, or documentation that does not affect the specification, needs no ADR.
When in doubt, write an ADR.

## ADRs

### Location and naming

ADRs that belong to one module go in `docs/<module>/adr/`.
ADRs that span modules go in `docs/adr/`.

File names start with a four-digit sequence number, as in `0001-feature-details.md`.
After the number comes a kebab-case name that says what the ADR is about.

### Structure

Write ADRs in the following form.
If the ADR changes a data structure or an algorithm, add a section for it.
Add other sections for anything from the discussion worth keeping.
ADRs are written in Japanese.

```markdown
# ADR 0001: タイトル

ステータス: 提案

## 文脈

## 実装すること

## 実装しないこと

## テスト設計

## トレードオフ
```

The status (ステータス) is one of 提案 (proposed), 採択 (accepted), 却下 (rejected), or 破棄 (abandoned).
When a later ADR replaces part of one, the status names it, as in "採択→○○（変更部分）は [ADR NNNN](...)", with a link.

### ADRs are immutable

Once committed, an ADR cannot be changed except for its status line.
`.githooks/pre-commit` and the `adr` job in CI reject edits, deletions, and renames.
Changes to the status line (`--allow-status`) and changes that only add, remove, or retarget links of ADR references (`--allow-links`) are allowed ([docs/adr/0010](./docs/adr/0010-update-adr-guard-to-v0.5.0.md)).
ADR references in documents must link to the ADR file; the `adr` job in CI rejects unlinked ones, and `adr-guard links --fix` fixes them.

To change the specification, do not rewrite the old ADR; write a new one with the next number.
To abandon an ADR, set its status to 破棄 and record the reason in [docs/specifications.md](./docs/specifications.md).

Do not commit an ADR until it has been reviewed.
A proposal can only be revised until it is committed.

## Tests and implementation

Write the tests from the ADR's test design first, confirm that they fail, and then implement.
For changes that cannot be tested automatically, such as configuration values, the test design says how to check them, and they are checked by running them after implementation.

Golem always produces the same bytes from the same input.
Changes that affect output are checked by the `determinism` job in CI, which compares x86-64 and aarch64.
Keep anything that depends on the environment out of the output: time, random numbers, hash-table iteration order, locale.

If something has no license problem and is easy to reimplement, reimplement it instead of adding a dependency.
In that case, write thorough tests, using the original project's tests as a reference.
If only a few features are needed, implementing only those is fine.

Raising the version of any pinned native library listed in [README.md](./README.md) (HarfBuzz, FreeType, wasmtime, zlib, hyph-utf8) requires an ADR.
When changing dependency versions pinned in `cabal.project.freeze`, explain why in the pull request.

## Formatting and linting

Format Haskell code with fourmolu 0.21.0.0 and resolve every hlint 3.10 hint.
The `format` job in CI checks both.
The generated parser (`modules/golem-parser/src/Golem/Parser/Generated.hs`) and the grammar without its labels (`modules/golem-parser/test/StrippedGrammar.hs`) are excluded.

After changing the grammar (`modules/golem-parser/grammar/Golem.peg`), regenerate the parser with `scripts/gen-parser.sh` and commit the generated files.
The script also generates the grammar without its labels; the golem-parser tests check that both grammars accept the same inputs.
When adding a label to the grammar, make sure that removing it does not change the accepted language, and declare it with `%safe` and a comment giving the reason.
`scripts/gen-parser.sh` treats peg-hs warnings as errors, so a label without `%safe` makes the generation fail ([golem-parser ADR 0007](./docs/golem-parser/adr/0007-grammar-label-safety.md)).

## Documentation

When an ADR changes the specification, update [docs/specifications.md](./docs/specifications.md) and [README.md](./README.md) in the same pull request.
These two must always be up to date on `main`.
Implementation details of a module go in `docs/<module>/specifications.md`.

References to ADRs from the specification must link to the ADR file.
When introducing a new term, add it to [docs/glossary.md](./docs/glossary.md).

Audit records and performance snapshots go under `docs/`, in a directory for each purpose.
These are also not changed once committed.

Japanese prose puts each sentence on its own line.
It does not use dashes (——) or the middle dot (・) for lists.

## Git

### Commits

Write commit messages in English.
Keep each commit to one coherent change.

### Branches and merging

Do not push to `main` directly; create a branch and open a pull request.
Always merge with no-ff.

Rebasing or force-pushing `main` is forbidden.
The only exception is when a secret such as an API key has been committed by mistake.
Your own branch may be rebased until it is merged.

### Tags and releases

Tags starting with `v` are releases.
Tags with an identifier after the version, such as `v0.0.1-rc`, are pre-releases.
Release notes go in GitHub Releases, written in English.
Group the changes under headings such as Added, Changed, Removed, and Fixed, and where possible add absolute links to the commit or pull request and the ADR for each change.

A release goes as follows ([docs/adr/0004](./docs/adr/0004-binary-distribution-and-release.md)).

1. Open a pull request that raises the version. Write the new version (for example `0.1.0-rc1`) into `VERSION` at the root of the repository, and its `X.Y.Z` without the identifier into the `version` of every package's cabal file. The `release-scripts` job of CI checks that the two agree.
2. Merge the pull request into `main`.
3. Tag the merge commit with `v` followed by the content of `VERSION` (for example `v0.1.0-rc1`) and push the tag. When the tag does not match `VERSION`, or its commit is not on `main`, the `version` job of the workflow fails and no release is made.
4. `.github/workflows/release.yml` builds and checks the archives and makes a draft release. A pre-release tag makes a draft marked as a pre-release.
5. Read the draft release notes. Fix by hand what the AI classified or summarized badly. When the AI or the check failed, the notes are the list of changes with a `## Unsorted` section; classify and rewrite them. The summary of the workflow says why it failed.
6. Publish the draft on the GitHub Releases page. The workflow never publishes.

To try the build and the checks without a release, run `gh workflow run release.yml --ref <branch>`, which starts the workflow through `workflow_dispatch`.
It makes no release.

## Test material

When adding outside text or fonts to fixtures, check the license and include the license text.
Record the source in that fixture's README.
Scripts that download material pin and verify the SHA-256 of each file.

## GitHub Actions

Use the latest LTS of Node.
Use the latest major version of each action that runs on Node 24 or later.

## License

Contributed code and documentation are distributed under the [MIT License](./LICENSE).
