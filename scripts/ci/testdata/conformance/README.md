# The output intent of the conformance PDFs

`golem-test-cmyk.icc` is the CMYK profile that `scripts/ci/conformance-pdfs.sh`
gives the books that the CI job verapdf checks against PDF/A-2a and
PDF/UA-1 ([docs/adr/0183](../../../../docs/adr/0183-tagged-pdf-and-pdf-a.md)).
It was made for Golem and is under the license of the repository (MIT,
`LICENSE`); it holds no data of another work.

It is an ICC version 2.1 profile of the output class (`prtr`), of the CMYK
colour space with the PCS Lab, and has the tags `desc`, `cprt`, `wtpt`,
`A2B0`, `B2A0` and `gamt`, each table of 8-bit entries with two grid
points: the lightness falls with the ink, and the colour stays neutral.
It describes no real press. It is only for the checks of the structure of
the PDF, where veraPDF needs an output intent with a valid profile of a
printer; a book to print takes the profile of its press (Japan Color 2001
Coated and so on).

Its SHA-256 is `8776f9b40c18292c2f33673a5c7d327f240301b6ed1e42ef4fd03a288ac39708` (5208 bytes).
