# Hyphenation patterns

`hyph-en-us.pat.txt` and `hyph-en-us.hyp.txt` are the US English patterns
and exceptions of hyph-utf8, taken from
https://github.com/hyphenation/tex-hyphen at commit
`5684c0f51c0b81133db2efbe60a408b4155a3ff5` (golem-layout ADR 0001).
Their copyright and licence are in `LICENSE-hyph-en-us.txt`, the header
of `hyph-en-us.tex` from the same commit.

Changing these files changes line breaks; update them only through an ADR.
