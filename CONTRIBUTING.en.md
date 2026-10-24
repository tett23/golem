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

The hook calls [adr-guard](https://github.com/tett23/adr-guard) v0.8.3 or later, so install it beforehand (`cargo install --git https://github.com/tett23/adr-guard --tag v0.8.3`).
This setting is not stored in the repository, so run it in every clone.
`.githooks/pre-push` stops the push of a branch that changes the specification without updating the manual (see Documentation).

## How a change proceeds

1. Write an ADR and get it reviewed.
2. Write the tests listed in the ADR's test design and confirm that they fail.
3. Implement until the tests pass.
4. Update the specification and the README.
5. Push a branch and open a pull request.
6. Once CI passes, merge it into `main` with no-ff.

Fixing typos, or documentation that does not affect the specification, needs no ADR.
Changes to the two manuals and to [docs/manual-policy.md](./docs/manual-policy.md) are decided in pull requests and need no ADR unless the maintainer asks for one.
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

The status (ステータス) is one of 提案 (proposed), 採択 (accepted), 採択（未実装） (accepted, not implemented), 却下 (rejected), or 破棄 (abandoned).
Use 採択（未実装） for an ADR that is accepted but not implemented yet, and change it to 採択 when the implementation is done.
`adr-guard unimplemented` lists the ADRs with 採択（未実装） ([docs/adr/0048](./docs/adr/0048-update-adr-guard-to-v0.8.3.md)).
When a later ADR replaces part of one, the status names it, as in "採択→○○（変更部分）は [ADR NNNN](...)", with a link.

### ADRs are immutable

Once committed, an ADR cannot be changed except for its status line.
`.githooks/pre-commit` and the `adr` job in CI reject edits, deletions, and renames.
Changes to the status line (`--allow-status`) and changes that only add, remove, or retarget links (`--allow-links`) are allowed ([docs/adr/0010](./docs/adr/0010-update-adr-guard-to-v0.5.0.md), [docs/adr/0032](./docs/adr/0032-update-adr-guard-to-v0.8.2.md)); changes to link text are not.
Every ADR must have exactly one status line starting with `ステータス:`; the hook and the `adr` job in CI reject ADRs with none or more than one, and `adr-guard check-status` lists them ([docs/adr/0011](./docs/adr/0011-update-adr-guard-to-v0.8.0.md)).
ADR references in documents must link to the ADR file; the `adr` job in CI rejects unlinked ones, and `adr-guard links --fix` fixes them.

To change the specification, do not rewrite the old ADR; write a new one with the next number.
To abandon an ADR, set its status to 破棄 and record the reason in [docs/specifications.md](./docs/specifications.md).

Do not commit an ADR until it has been reviewed.
A proposal can only be revised until it is committed.

## Tests and implementation

Write the tests from the ADR's test design first, confirm that they fail, and then implement.
For changes that cannot be tested automatically, such as configuration values, the test design says how to check them, and they are checked by running them after implementation.

Write a test that uses an external tool (such as `cddl`, `qpdf` or `openssl`) with `needsTool` or `optionalTool` of `Golem.TestSupport.ExternalTool` in `modules/golem-test-support` ([docs/adr/0028](./docs/adr/0028-shared-test-support-package.md)).
Where the tool is missing, the test is reported as `SKIP`, and with `GOLEM_REQUIRE_EXTERNAL_TOOLS=1` it fails.
Only test suites may depend on golem-test-support; if a library or an executable does, `scripts/ci/test-only-deps.sh` in the `build` job of CI fails.

Do not write golden files by hand; write them with `--accept` (see the Development section of [README.md](./README.md)).
Read the diff of the written files and confirm that the output is the intended one before committing.
CI runs the tests with `TASTY_NO_CREATE=true`, so a deleted or misnamed golden file fails.

Golem always produces the same bytes from the same input.
Changes that affect output are checked by the `determinism` job in CI, which compares x86-64 and aarch64.
Keep anything that depends on the environment out of the output: time, random numbers, hash-table iteration order, locale.

Write the scripts under `scripts/` in POSIX `sh`, and make them run with the BSD `awk`, `sed`, `find` and `grep` of macOS too.
Avoid forms that GNU and BSD write differently, such as the argument of `sed -i`.
The `scripts-macos` job of CI runs the five tests under `scripts/` on macOS with only the tools of the system on `PATH` ([docs/adr/0079](./docs/adr/0079-shell-tests-on-macos.md)).

If something has no license problem and is easy to reimplement, reimplement it instead of adding a dependency.
In that case, write thorough tests, using the original project's tests as a reference.
If only a few features are needed, implementing only those is fine.

Raising the version of any pinned native library listed in [README.md](./README.md) (HarfBuzz, FreeType, wasmtime, zlib, hyph-utf8) requires an ADR.
When raising the version of wasmtime, regenerate `licenses/wasmtime-v<version>/` (the license documents of the Rust crates and others in `libwasmtime.a`) with `scripts/wasmtime-licenses.sh` and commit the output ([docs/adr/0007](./docs/adr/0007-third-party-licenses.md)).
The script connects to the network and needs `cargo` and `rustup`.
It does not fill in the component column of `c-objects.tsv`; fill it in by hand.
When changing dependency versions pinned in `cabal.project.freeze`, explain why in the pull request.
The version of Claude Code, which writes the release notes, is pinned to an exact value at `"npm:@anthropic-ai/claude-code"` in `mise.toml` ([docs/adr/0044](./docs/adr/0044-release-workflow-hardening.md)).
To raise it, open a pull request that changes `mise.toml`, and check that `claude --help` of the new version still has `--tools` and `--strict-mcp-config` (`scripts/release/test.sh` checks this when that version of `claude` is installed; the `release-scripts` job of CI installs that version with mise and always checks it, [docs/adr/0058](./docs/adr/0058-run-skipped-checks-in-ci.md)).
To link from the release notes to a sibling repository, open a pull request that adds the line `https://github.com/tett23/<repository>/` to `scripts/release/allowed-links.txt`.
When raising ghcup, change the ghcup version, the commit of the bootstrap script and its SHA-256 in `scripts/release/build-linux.sh` together.

## Formatting and linting

Format Haskell code with fourmolu 0.21.0.0 and resolve every hlint 3.10 hint.
The `format` job in CI checks both.
The generated parser (`modules/golem-parser/src/Golem/Parser/Generated.hs`) and the grammar without its labels (`modules/golem-parser/test/StrippedGrammar.hs`) are excluded.

After changing the grammar (`modules/golem-parser/grammar/Golem.hpeg`), regenerate the parser with `scripts/gen-parser.sh` and commit the generated files.
The script also generates the grammar without its labels; the golem-parser tests check that both grammars accept the same inputs.
When adding a label to the grammar, make sure that removing it does not change the accepted language, and declare it with `%safe` and a comment giving the reason.
`scripts/gen-parser.sh` treats peg-hs warnings as errors, so a label without `%safe` makes the generation fail ([golem-parser ADR 0007](./docs/golem-parser/adr/0007-grammar-label-safety.md)).

## Documentation

When an ADR changes the specification, update [docs/specifications.md](./docs/specifications.md) and [README.md](./README.md) in the same pull request.
These two must always be up to date on `main`.
Implementation details of a module go in `docs/<module>/specifications.md`.
Which version handles what, items not implemented yet, items awaiting a check by hand, open questions, and matters not taken up go in [docs/roadmap.md](./docs/roadmap.md), not in the specification.
When an item is implemented, remove it from roadmap.md and describe the behavior in the specification.

References to ADRs from the specification must link to the ADR file.
When introducing a new term, add it to [docs/glossary.md](./docs/glossary.md).

There are two manuals, the user manual `manual/` and the developer manual `manual-dev/`; both are written as Golem projects and typeset with Golem ([docs/adr/0024](./docs/adr/0024-manual-audiences-and-policy.md)).
Their readers, style, depth of explanation, grounds and footnotes, structure and code display follow the policy [docs/manual-policy.md](./docs/manual-policy.md).
When implementing an ADR changes what users see, update `manual/` in the same pull request; when it changes how Golem is developed or built upon, update `manual-dev/`.
The manuals describe only the specification that is accepted and implemented.
Before editing a manual, run `sh scripts/manual/build-info.sh manual` (and `manual-dev`) once, so that `common/build-info.gm`, which the colophon imports, exists.
Both manuals must build with `scripts/manual/build.sh` without a single error, warning or notice (the `build` job of CI runs it).
Do not hide notices with `silence-notices` or `--no-notices`.
`.githooks/pre-push` and the `manual` job of CI (`docs.yml`) stop these branches:

- a branch that changes docs/markup.md or docs/specifications.md without changing `manual/` or `manual-dev/`;
- a branch that changes CONTRIBUTING.md or CONTRIBUTING.en.md without changing `manual-dev/`.

When a change does not change what the manuals describe, such as adding a known bug to the specification, end the message of one of the commits of the branch with the trailer line `Manual: unchanged`.
The hook checks from the merge base with your local `origin/main`; if it stops a push because of changes already on `main`, run `git fetch` and push again.

When the build or the tests start to read a document under `docs/`, add it to the list in `scripts/ci/needs-build.sh`.
A document not in the list counts as documentation only, and changing it does not run the build.
In the code, write the path of the document as one string (like `"../../docs/diagnostics.md"`).
The `changes` job of CI picks up such strings and checks them against the list ([docs/adr/0021](./docs/adr/0021-docs-workflow-and-ci-gate.md)).
When you build the path from parts, like `"docs" </> "diagnostics.md"`, name the document on that line with the comment `-- docs-refs: docs/diagnostics.md`.
A line with the string `"docs"` and without the comment fails the same job (`scripts/ci/docs-refs.sh`, [docs/adr/0069](./docs/adr/0069-lint-scripts-bypassed-by-plain-rewrites.md)).

Every package turns an incomplete `case` or function definition into an error with `-Werror=incomplete-patterns` ([docs/adr/0027](./docs/adr/0027-exhaustive-command-dispatch-by-types.md)).
When you add a package under `modules/`, put the flag in the `ghc-options` of the `common warnings` stanza of its cabal file, and write `import: warnings` in each component.
Without it, the `changes` job of CI (`scripts/ci/incomplete-patterns.sh`) fails.

`unsafePerformIO` and its kin (`unsafeDupablePerformIO`, `unsafeInterleaveIO` and others) are used only in the definitions listed in `scripts/ci/unsafe-io-allowed.txt` ([docs/adr/0034](./docs/adr/0034-fewer-unsafe-perform-io.md)).
Work that can be written in IO goes to the IO edges; only when a pure function must call a C library from inside, add the definition and the reason it is kept to the list.
When the list and the sources differ, the `changes` job of CI (`scripts/ci/unsafe-io.sh`) fails.

An executable or a test suite built with `-threaded` is also linked with `-with-rtsopts=-N`, so that it has one capability per processor from the start.
The code does not call `setNumCapabilities`.
Two calls that raise the number of capabilities at the same time stop the runtime of GHC 9.10.3.
tasty 1.5.4 also calls it at start when there are fewer capabilities than processors, and `-N` keeps it from doing so.
If either rule is broken, the `changes` job of CI (`scripts/ci/rts-capabilities.sh`) fails.

Audit records and performance snapshots go under `docs/`, in a directory for each purpose.
These are also not changed once committed.
Records under `docs/audit/`, `docs/audits/`, `docs/benchmarks/`, and `docs/benchmark/` are enforced: the hook and the `adr` job in CI reject changes, deletions, and moves of committed ones ([docs/adr/0011](./docs/adr/0011-update-adr-guard-to-v0.8.0.md), [docs/adr/0012](./docs/adr/0012-update-adr-guard-to-v0.8.1.md)).
Records in directories with other names, such as `docs/ci-timings/`, are not checked and are kept by convention and review.

### Japanese prose

Japanese prose puts each sentence on its own line.
A list item or a table cell may hold several sentences.
Prose does not use dashes (——).
The middle dot (・) is not used to list things in parallel; join them with 、 or と instead.
Other uses of the middle dot, such as separating the words of a loanword, are allowed.

Terms follow the rules of [docs/manual-policy.md](./docs/manual-policy.md).
The rules of the developer manual (diagnostic, not 診断; アセット, not 資産; マシン or 計算機, not 機械; notice and info, not お知らせ) and the rules common to the two manuals (書体 and フォント kept apart; バージョン, not 版, for a version; パブリックドメイン, not 公有) also apply to the specifications under `docs/`, README, CONTRIBUTING, and new ADRs.
Committed ADRs cannot change and keep their old terms.

textlint checks the rules that can be decided from the characters and the lines ([docs/adr/0036](./docs/adr/0036-textlint-for-documents.md)).
The rules, the term dictionaries, and the pinned npm packages are in `tools/textlint/` ([tools/textlint/README.md](./tools/textlint/README.md)).
Install Node and run `sh scripts/ci/textlint.sh`.
The first run installs the packages.
With `TEXTLINT_ARGS=--fix`, it fixes what can be fixed.
It checks the Markdown under `docs/` (but the ADRs and records such as `docs/audits/`), README.md, CONTRIBUTING.md, the ADRs that the branch adds, and the sources of the two manuals.
The `textlint` job of CI (`docs.yml`) runs the same script.
Words chosen by meaning (版 and バージョン, 書体 and フォント) and the length of sentences are not checked; review them.

## Git

### Commits

Write commit messages in English.
Keep each commit to one coherent change.

### Branches and merging

Do not push to `main` directly; create a branch and open a pull request.
Always merge with no-ff.
`main` is protected: it rejects pushes that do not go through a pull request, and merges other than merge commits (squash and rebase).
A merge needs four checks of CI to pass: `ci` (`ci.yml`), and `adr`, `manual`, and `textlint` (`docs.yml`) ([docs/adr/0021](./docs/adr/0021-docs-workflow-and-ci-gate.md), [docs/adr/0022](./docs/adr/0022-manual-as-typesetting-sample.md), [docs/adr/0036](./docs/adr/0036-textlint-for-documents.md)).

Rebasing or force-pushing `main` is forbidden.
The only exception is when a secret such as an API key has been committed by mistake.
Your own branch may be rebased until it is merged.

### Tags and releases

Tags starting with `v` are releases.
Tags with an identifier after the version, such as `v0.0.1-rc`, are pre-releases.
Release notes go in GitHub Releases, written in English.
Group the changes under headings such as Added, Changed, Removed, and Fixed, and where possible add absolute links to the commit or pull request and the ADR for each change.

A release goes as follows ([docs/adr/0004](./docs/adr/0004-binary-distribution-and-release.md)).

1. Run a security audit ([docs/adr/0035](./docs/adr/0035-security-hardening.md)). It is done for every release of a tag starting with `v`, pre-releases (tags with an identifier such as `rc`) included. Look at untrusted input (sources, TOML, images, fonts, CSL-JSON, plugins, symbolic links) and the CI workflows, mainly what changed since the previous audit. Record the results in `docs/audits/<date>-security-audit.md`, in Japanese, and merge it into `main` through a pull request; the record is not changed once committed. Fix each problem found with a failing test first; a fix that changes the specification needs an ADR. Do not tag before the record and the fixes are on `main`.
2. Open a pull request that raises the version. Write the new version (for example `0.1.0-rc1`) into `VERSION` at the root of the repository, and its `X.Y.Z` without the identifier into the `version` of every package's cabal file. The `release-scripts` job of CI checks that the two agree.
3. Merge the pull request into `main`.
4. Tag the merge commit with `v` followed by the content of `VERSION` (for example `v0.1.0-rc1`) and push the tag. When the tag does not match `VERSION`, or its commit is not on `main`, the `version` job of the workflow fails and no release is made.
5. `.github/workflows/release.yml` builds and checks the archives and makes a draft release. A pre-release tag makes a draft marked as a pre-release.
6. Read the draft release notes. Fix by hand what the AI classified or summarized badly. When the AI or the check failed, the notes are the list of changes with a `## Unsorted` section; classify and rewrite them. The summary of the workflow says why it failed.
7. Publish the draft on the GitHub Releases page. The workflow never publishes.

To try the build and the checks without a release, run `gh workflow run release.yml --ref <branch>`, which starts the workflow through `workflow_dispatch`.
It makes no release.

Tags are handled as follows ([docs/adr/0008](./docs/adr/0008-first-release-verification.md)).

- Never move a pushed tag to another commit.
- The tag of a release that has not been published may be deleted only when the workflow failed or the checks of the archives did not pass. A deleted tag name is never used again; advance the pre-release identifier instead (`rc2` after `rc1`).
- Never delete the tag of a published release.
- A failure that goes away without a code change (a runner problem, a transient network failure, an API limit) is fixed by running the workflow again with the tag unchanged (`gh run rerun <run ID> --failed`).

Record the results of the checks of the archives in `docs/audits/releases/<tag>.md`, in Japanese, and merge it into `main` through a pull request.
When a tag is deleted and the release retried, the record of the deleted tag stays with the failure written in it, and the next tag gets a record of its own.
Records are not changed once committed.

## Test material

When adding outside text or fonts to fixtures, check the license and include the license text.
Record the source in that fixture's README.
Scripts that download material pin and verify the SHA-256 of each file.
Do not write the conversion of the downloaded texts into Golem source in Python.
It is written in Haskell, in the `golem-fixtures` executable of `modules/golem-fixtures`, which `scripts/fixtures/fetch-public-domain.sh` runs with `cabal run` ([docs/adr/0023](docs/adr/0023-fixture-converters-without-python.md)).
This package is not part of the release archives.

## GitHub Actions

Use the latest LTS of Node.
Use the latest major version of each action that runs on Node 24 or later.

Keep CI within 5 minutes.
Every change waits for CI, so slow CI slows down development itself.
This project values the speed of development above all, so slow CI is never postponed.
When CI on a pull request exceeds 5 minutes, stop other work and improve CI first (split jobs, cache, skip checks of unchanged modules, and so on).
Record the times before and after the optimization in `docs/ci-timings/`.

## License

Contributions to the two manuals (`manual/` and `manual-dev/`, except `fonts/`) are distributed under [CC0 1.0](./manual/LICENSE) ([docs/adr/0082](./docs/adr/0082-manuals-under-cc0.md)).
Other contributed code and documentation are distributed under the [MIT License](./LICENSE).
