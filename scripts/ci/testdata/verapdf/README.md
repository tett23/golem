# An untagged PDF

`untagged.pdf` is a page of one line, "An untagged page.", in Source Sans
Pro, set by golem 0.1.0-rc3, before the structure tree of
[docs/adr/0183](../../../../docs/adr/0183-tagged-pdf-and-pdf-a.md): it has no
`StructTreeRoot`, no `MarkInfo` and no `Lang`. `scripts/ci/verapdf.sh` checks
first that veraPDF finds it not to conform to PDF/UA-1, so that a wrong call
of veraPDF does not pass every PDF.
