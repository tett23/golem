{- | The paths of the boxes of paragraph styles, of the line styles of a
rule and of the wrap mark of code are drawn as before root ADR 0437 put
them on the paths of golem-geometry (I6): the bytes of their content
streams, over an enumeration of boxes, corners, sides and line styles,
hash to the value of the commit before the change.
-}
module PathMarksSpec (pathMarksTests) where

import Data.ByteString qualified as BS
import Data.ByteString.Builder qualified as B
import Data.ByteString.Lazy qualified as BL
import Golem.LayoutSpec (Rect (..))
import Golem.Pdf qualified as P
import Golem.Pdf.Sha256 (sha256)
import Golem.Project.Style (BoxSide (..), RuleStyle (..))
import Golem.Typeset.Box (BoxPaint (..), boxMarks)
import Golem.Typeset.RuleShape (ruleMarks, ruleShapes)
import Golem.Typeset.WrapMark (wrapMarkFills, wrapMarkPolygons)
import Test.Tasty
import Test.Tasty.HUnit

pathMarksTests :: [TestTree]
pathMarksTests =
  [ testCase "root ADR 0437 I6: the boxes of paragraph styles with round and square corners draw the bytes of before" $
      hex (stream boxes) @?= boxesBefore,
    testCase "root ADR 0437 I6: the line styles of rules draw the bytes of before" $
      hex (stream rules) @?= rulesBefore,
    testCase "root ADR 0437 I6: the wrap marks of code draw the bytes of before" $
      hex (stream wraps) @?= wrapsBefore
  ]

-- | The hashes of the streams, by the code of 2635598c5 (before the change).
boxesBefore, rulesBefore, wrapsBefore :: String
boxesBefore = "68d2298de018a76fcaaf0f659ecbdb8d1d05a06d1eaead12dfded51c3ad02b2a"
rulesBefore = "4f048d6064f9d01066a4f648f2c960674455f8e49332b79a28402c78bf26c78e"
wrapsBefore = "9f1ab1de6aa0fde04db6145bf9c92b156db5d8a89d359d8e9ecccba631ce52bc"

stream :: [P.Mark] -> BS.ByteString
stream = P.contentStream mempty mempty

hex :: BS.ByteString -> String
hex = map (toEnum . fromEnum) . BL.unpack . B.toLazyByteString . B.byteStringHex . sha256

sw :: P.Swatch
sw = P.Swatch 10 20 30 40

styles :: [RuleStyle]
styles = [RuleSolid, RuleMulti [2, 1, 1], RuleDashed 196611 131075, RuleDotted 98307, RuleJapaneseDots 65539, RuleWavy]

-- | Boxes of odd sizes, every radius up to beyond half the box, every set of sides, first or last or both.
boxes :: [P.Mark]
boxes =
  concat
    [ map snd background <> map snd border
    | vertical <- [False, True],
      rect <- [Rect 655361 1310723 6553607 3276809, Rect (-3) 7 1966087 655363],
      radius <- [0, 1, 98307, 655363, 9999991],
      sides <- subsets [SideBefore, SideAfter, SideStart, SideEnd],
      paint <- [Just sw, Nothing],
      line <- Nothing : [Just (sw, t, style) | t <- [65537, 131075], style <- styles],
      (isFirst, isLast) <- [(True, True), (True, False), (False, True), (False, False)],
      let (background, border) = boxMarks vertical rect (BoxPaint paint line sides radius) isFirst isLast
    ]
  where
    subsets = \case
      [] -> [[]]
      x : xs -> let rest = subsets xs in map (x :) rest <> rest

-- | Bands of the line styles along and across, of odd lengths and weights.
rules :: [P.Mark]
rules =
  concat
    [ ruleMarks swatch (ruleShapes along (Rect 131073 196613 len weight) style)
    | along <- [False, True],
      len <- [655363, 6553609, 13107211],
      weight <- [65537, 196611, 327685],
      style <- styles,
      swatch <- [Nothing, Just sw]
    ]

-- | The wrap marks of sizes that 5 and 20 do not divide, at odd origins, in both directions.
wraps :: [P.Mark]
wraps = concat [wrapMarkFills (wrapMarkPolygons vertical (x, y) size) | vertical <- [False, True], (x, y) <- [(0, 0), (131071, -65537)], size <- [655360, 655363, 917507]]
