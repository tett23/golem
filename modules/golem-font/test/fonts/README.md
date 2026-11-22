# Test fonts

The first three are taken from the test data of HarfBuzz 14.6.0
(`test/subset/data/fonts`) and are licensed under the SIL Open Font
License 1.1 (`OFL.txt`).

`SourceSerif4Variable-Roman.otf` is copied unmodified from
`source-serif-4.005_Desktop.zip` (`VAR/`) of the 4.005R release of
adobe-fonts/source-serif, for
[golem-font ADR 0003](../../../../docs/golem-font/adr/0003-reject-cff2-fonts-in-pdf.md). It is licensed under the SIL
Open Font License 1.1 with the Reserved Font Name "Source"
(`SourceSerif4-OFL.txt`, the `LICENSE.md` of that archive). It is not
subset, so that it stays an Original Version under the licence.

| File | Font | Outlines |
|---|---|---|
| `SourceHanSans-Regular_subset.otf` | Source Han Sans (subset by HarfBuzz) | CFF, CID-keyed |
| `SourceSansPro-Regular.otf` | Source Sans Pro | CFF |
| `SourceSerifVariable-Roman.ttf` | Source Serif (variable) | TrueType |
| `SourceSerif4Variable-Roman.otf` | Source Serif 4 (variable) | CFF2 |
| `RandomSansPro-Regular.otf` | Source Sans Pro with four CharStrings rewritten | CFF |

`RandomSansPro-Regular.otf` is a Modified Version of
`SourceSansPro-Regular.otf`, for
[Golem ADR 0390](../../../../docs/adr/0390-deterministic-and-exhaustive-cff-random.md):
the CharStrings of four glyphs are rewritten in place to run the operator
`random`, and the family and PostScript names are changed to "Random Sans
Pro" and "RandomSansPro" with the same lengths, since a Modified Version may
not use the Reserved Font Name "Source", which the copyright notice in
the font declares. The copyright and trademark notices
are kept. `test/RandomFontSpec.hs` makes it from `SourceSansPro-Regular.otf`
and checks that the committed file is what it makes. It is licensed under
the SIL Open Font License 1.1 (`OFL.txt`).
