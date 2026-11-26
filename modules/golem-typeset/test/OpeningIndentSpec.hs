-- | The indent of a paragraph that starts with an opening bracket in the PDF (root ADR 0374, 0469).
module OpeningIndentSpec (openingIndentTests) where

import Data.Text (Text)
import Golem.Doc.IR
import Golem.Layout.Look (plainLook)
import Golem.Project.Style (OpeningIndent (..), ParaAlign (..), Sp (..))
import Golem.Syntax.Span (FileId (..), SrcSpan, mkSpan)
import Golem.Typeset.Internal (Indent (..), openingIndent)
import Test.Tasty
import Test.Tasty.HUnit

-- | The size of the paragraph, 10pt.
fs :: Sp
fs = 655360

sp0 :: SrcSpan
sp0 = mkSpan (FileId 0) 0 0

txt :: Text -> Inline
txt = Text sp0

{- | The table of root ADR 0469 I2, the same as in the tests of golem-html:
a paragraph, the language of its block, and whether its first character
is an opening bracket. A paragraph that keeps its lines is judged by its
first line, which these paragraphs start.
-}
openingTable :: [(String, [Inline], Maybe Text, Bool)]
openingTable =
  [ ("「 first", [txt "「あ」"], Nothing, True),
    ("あ first", [txt "あ「い」"], Nothing, False),
    ("( first in a [lang en] span", [Lang sp0 "en" [txt "(a)"]], Nothing, False),
    ("“ first in a [lang en] span", [Lang sp0 "en" [txt "“a”"]], Nothing, False),
    ("“ first in a block of ja", [txt "“あ”"], Just "ja", True),
    ("“ first in a block of en", [txt "“a”"], Just "en", False),
    ("an empty paragraph", [], Nothing, False),
    ("「 first in a character style after an empty text", [txt "", CharStyle sp0 "em" [txt "「あ」"]], Nothing, True),
    ("「 first in the base of ruby", [Ruby sp0 () [RubySegment [Text sp0 "「漢"] (Just "かん")]], Nothing, True),
    ("a line break first", [LineBreak sp0, txt "「あ」"], Nothing, False)
  ]

-- | The first-line indent with opening-indent = "half", the indent 2em and the first-line indent f.
firstWith :: Sp -> Maybe Text -> [Inline] -> Sp
firstWith f blang = inFirst . openingIndent (Just OpeningHalf) (plainLook "body" fs) blang (Indent (2 * fs) f 0 ParaLeftJustified)

openingIndentTests :: TestTree
openingIndentTests =
  testGroup
    "the indent of a paragraph that starts with an opening bracket (root ADR 0374, 0469)"
    ( [ testCase ("root ADR 0469 I2: " <> name) $ (firstWith fs blang is /= fs) @?= opens
      | (name, is, blang, opens) <- openingTable
      ]
        <> [ testCase "root ADR 0469 I1: a style without opening-indent keeps its indent" $
               inFirst (openingIndent Nothing (plainLook "body" fs) Nothing (Indent (2 * fs) fs 0 ParaLeftJustified) [txt "「あ」"]) @?= fs,
             testCase "root ADR 0469 I4: a first-line indent of 1em becomes 0.5em" $ firstWith fs Nothing [txt "「あ」"] @?= Sp (unSp fs `div` 2),
             testCase "root ADR 0469 I4: a first-line indent of 0.25em becomes 0" $ firstWith (Sp (unSp fs `div` 4)) Nothing [txt "「あ」"] @?= 0,
             testCase "root ADR 0469 I4: a first-line indent of -1em stays -1em" $ firstWith (negate fs) Nothing [txt "「あ」"] @?= negate fs
           ]
    )
