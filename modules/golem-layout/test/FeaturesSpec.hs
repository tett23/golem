{- | The OpenType features of a look (docs/adr/0268): characters of
different features are in different boxes, so that each box is shaped with
one list of features.
-}
module FeaturesSpec (featuresTests) where

import Data.List (nub)
import Data.Text (Text)
import Fixtures (fs, sp)
import Golem.Doc.IR qualified as IR
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (Look (..))
import Test.Tasty
import Test.Tasty.HUnit

-- | The character style sc adds smcp, as golem-typeset's restyle does: the tag once.
env :: ComposeEnv
env =
  (defaultComposeEnv fs)
    { ceRestyle = \lk -> \case
        IR.CharStyle _ "sc" _ -> lk {lkFeatures = nub (lkFeatures lk <> ["smcp"])}
        _ -> lk
    }

boxes :: [IR.Inline] -> [(Text, [Text])]
boxes is = [(bcText c, lkFeatures (bcLook c)) | Box _ c <- fst (composeInlines env is)]

featuresTests :: TestTree
featuresTests =
  testGroup
    "OpenType features of a look (docs/adr/0268)"
    [ testCase "I9: the characters of other features are a box of their own" $
        boxes [IR.Text sp "ab", IR.CharStyle sp "sc" [IR.Text sp "cd"], IR.Text sp "ef"]
          @?= [("ab", []), ("cd", ["smcp"]), ("ef", [])],
      {- each text of the source is boxes of its own, whatever its look; the
      same features nested cut nothing more than the texts do, and the boxes
      have one list -}
      testCase "I9: the same features nested add no cut and keep one list" $
        boxes [IR.CharStyle sp "sc" [IR.Text sp "a", IR.CharStyle sp "sc" [IR.Text sp "b"]]]
          @?= boxes [IR.CharStyle sp "sc" [IR.Text sp "a", IR.Text sp "b"]],
      testCase "I9: nested, the features are those of the outer style" $
        map snd (boxes [IR.CharStyle sp "sc" [IR.Text sp "a", IR.CharStyle sp "sc" [IR.Text sp "b"]]]) @?= [["smcp"], ["smcp"]],
      testCase "the plain look has no features" $
        boxes [IR.Text sp "ab"] @?= [("ab", [])]
    ]
