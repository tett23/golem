# Hyphenation patterns

The patterns and exceptions of hyph-utf8, taken from
https://github.com/hyphenation/tex-hyphen at commit
`5684c0f51c0b81133db2efbe60a408b4155a3ff5`: US English since
[golem-layout ADR 0001](../../../../docs/golem-layout/adr/0001-knuth-plass-line-breaking.md),
and the other languages since
[ADR 0276](../../../../docs/adr/0276-hyphenate-words-by-the-patterns-of-their-language.md).
`hyph-<tag>.pat.txt` and `hyph-<tag>.hyp.txt` are the files of
`hyph-utf8/tex/generic/hyph-utf8/patterns/txt/` of that commit, as they
are. `LICENSE-hyph-<tag>.txt` holds the copyright and licence of a
language: the comment lines at the head of
`hyph-utf8/tex/generic/hyph-utf8/patterns/tex/hyph-<tag>.tex` of the same
commit, up to the first line that does not start with `%`
(`awk '!/^%/{exit} {print}' hyph-<tag>.tex`).

| Tag | Language | Licence | Letters kept before, after a break | Files |
| --- | --- | --- | --- | --- |
| `en-us` | English (US) | as in `LICENSE-hyph-en-us.txt` | 2, 3 | `.pat.txt`, `.hyp.txt` |
| `en-gb` | English (UK) | MIT | 2, 3 | `.pat.txt`, `.hyp.txt` |
| `fr` | French | MIT | 2, 2 | `.pat.txt` |
| `de-1996` | German (reformed orthography) | MIT | 2, 2 | `.pat.txt` |
| `es` | Spanish | MIT/X11 | 2, 2 | `.pat.txt` |
| `it` | Italian | MIT (chosen of LPPL 1.3 and MIT) | 2, 2 | `.pat.txt` |
| `pt` | Portuguese | BSD 3-clause | 2, 3 | `.pat.txt`, `.hyp.txt` |
| `nl` | Dutch | MIT | 2, 2 | `.pat.txt`, `.hyp.txt` |

The letters kept before and after a break are those of `hyphenmins:
typesetting:` in the head of each `hyph-<tag>.tex`.

The SHA-256 of each file (the test "F6" of golem-layout checks them):

| File | SHA-256 |
| --- | --- |
| `hyph-de-1996.pat.txt` | `0570839683e4843a6210b188e2a586fe06f2b6b73952ec8106a634209d735adb` |
| `hyph-en-gb.hyp.txt` | `947b7b8e76f6a0d8ebe296178ff92ad624e4912ffbaaf59b26f81a395124e366` |
| `hyph-en-gb.pat.txt` | `651b89b4a0d4051995db8586e81ab109a4c7395d7706c06483893ebab5af013b` |
| `hyph-en-us.hyp.txt` | `5e785c27e151f878c312991d937b5582615b77737ab30bac413d5967d6aa21da` |
| `hyph-en-us.pat.txt` | `0f57318b878b132547ae92db39a6e1d1cf2a05d9008874955d6ecb910007a463` |
| `hyph-es.pat.txt` | `7ae8fa8d6a61ea4111c4a0412d019b62e7c07a62673121d0b711c5bc08d8e00c` |
| `hyph-fr.pat.txt` | `fd40a89e9e8eb0784a0919e50378814843e44afa41c5beaf0a85f6562820f6c2` |
| `hyph-it.pat.txt` | `ce650cffad4e81ecaf04591f3274a8ed909e82c587698c55e33b00e2aa7746de` |
| `hyph-nl.hyp.txt` | `5902ba4d760815a51a972b6d05f514dde1842c16fa2859b907e2d299edbb3299` |
| `hyph-nl.pat.txt` | `ac5795c1d6cd7027e6ec3a9e58e173789f999669e40ffd81755a4db7d3214165` |
| `hyph-pt.hyp.txt` | `5c093a9e48dc8f87624693f31b8da7d090ed1e6eeb07fce7bcfd5689d7f941a8` |
| `hyph-pt.pat.txt` | `37cab85eee09030843f74d7e34453422b69404491abb0d8fa61ad42539b22ee8` |
| `LICENSE-hyph-de-1996.txt` | `18e08f782f3d7a7772cc201a9e7286e4f8fffd686508e2af8bef952f17e87987` |
| `LICENSE-hyph-en-gb.txt` | `8a9d78cb8e3aa30383acc91fb05962035eed59877016263bd97be63c63341977` |
| `LICENSE-hyph-en-us.txt` | `1011c22144f360184ed86200fa2d2ca9df9ac19dd2ab4a31c0b4c94d998bb6f1` |
| `LICENSE-hyph-es.txt` | `467d968bbc9b32cd89c7f7d351f7391001a5416131d82ea37f82d7121430c22b` |
| `LICENSE-hyph-fr.txt` | `80092fcb79cf83748597f346355fd2e1c3aceb104240fb774999c62d5b1c1365` |
| `LICENSE-hyph-it.txt` | `a0b140b91a8599bdeffc4af2dea64c6d95baf19c8b2528fec7541e2772f23c24` |
| `LICENSE-hyph-nl.txt` | `351d2b98f7cef12b15b92a3aa2d74d05dcf358cee50443effed66bb80fb3a0ed` |
| `LICENSE-hyph-pt.txt` | `b97287be8d51f6de6c1f007f18741d574ea1adce4c4084ff7c4fc4917312bcb4` |

Changing these files changes line breaks; update them only through an ADR.
