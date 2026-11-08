-- | The glyph runs of a box in the order of its text (docs/adr ADR 0227).
module GlyphRunsSpec (glyphRunsTests) where

import Golem.Typeset.GlyphRuns (glyphRuns)
import Test.Tasty
import Test.Tasty.HUnit

-- | The key of the Japanese face and that of the Latin face, as runAt keys them: the face, synthetic slant and stroke, turned.
ja, latin, bold :: (Int, (Bool, Int), Bool)
ja = (0, (False, 0), False)
latin = (2, (False, 0), False)
bold = (2, (False, 12), False)

glyphRunsTests :: [TestTree]
glyphRunsTests =
  [ testCase "R2: “Hello”, its quotation marks in the Japanese face, is three runs in the order of its text" $
      glyphRuns (zip [ja, latin, latin, latin, latin, latin, ja] "“Hello”") @?= [(ja, "“"), (latin, "Hello"), (ja, "”")],
    testCase "R2: “a—b” is a run for each change of face, the same key apart is two runs" $
      glyphRuns (zip [ja, latin, ja, latin, ja] "“a—b”") @?= [(ja, "“"), (latin, "a"), (ja, "—"), (latin, "b"), (ja, "”")],
    testCase "R2: a glyph of synthetic bold in a word is a run of its own" $
      glyphRuns (zip [latin, bold, latin] "xyz") @?= [(latin, "x"), (bold, "y"), (latin, "z")],
    testCase "R4: a box of one face (Hello) is one run" $
      glyphRuns (map (latin,) "Hello") @?= [(latin, "Hello")],
    testCase "R4: a box without glyphs has no run" $
      glyphRuns ([] :: [((Int, (Bool, Int), Bool), Char)]) @?= []
  ]
