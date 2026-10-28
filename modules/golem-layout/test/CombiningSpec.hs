{- | Combining characters (golem-driver ADR 0036): a base character and
the combining characters after it (general category Mn, Mc or Me) are one
box, whose character class is that of the base.
-}
module CombiningSpec (combiningTests) where

import Data.Text (Text)
import Data.Text qualified as T
import Fixtures (compose, fs, sp)
import Golem.Doc.IR qualified as IR
import Golem.Layout.Hyphenation.EnUs (englishUS)
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass
import Test.Tasty
import Test.Tasty.HUnit

-- | Advances that ignore combining characters, so that boxes with and without them compare equal.
markless :: ComposeEnv
markless = (defaultComposeEnv fs) {ceWordAdvance = \lk t -> ceWordAdvance (defaultComposeEnv fs) lk (T.filter (not . isExtending) t)}

-- | The items with the combining characters removed from the box texts.
stripMarks :: Item -> Item
stripMarks = \case
  Box w c -> Box w c {bcText = T.filter (not . isExtending) (bcText c)}
  it -> it

boxTexts :: [Item] -> [Text]
boxTexts items = [bcText c | Box _ c <- items]

combiningTests :: TestTree
combiningTests =
  testGroup
    "combining characters (golem-driver ADR 0036)"
    [ testCase "isExtending: Mn, Mc and Me, variation selectors included" $ do
        map isExtending "\x301\x308\x3099\xFE00\xE0100" @?= replicate 5 True
        map isExtending "eか\x309B\x200D" @?= replicate 4 False,
      testCase "cafe◌́ au lait: the first box is cafe◌́, with nothing inside it" $ do
        let items = compose (defaultComposeEnv fs) "cafe\x301 au lait"
        case items of
          Box _ c : Glue {} : _ -> bcText c @?= "cafe\x301"
          other -> assertFailure (show (take 3 other)),
      testCase "か◌゙が: two boxes, the first as wide as its whole shaped" $ do
        let env = (defaultComposeEnv fs) {ceWordAdvance = \_ t -> if t == "か\x3099" then 9 / 8 else 1}
            items = compose env "か\x3099が"
        boxTexts items @?= ["か\x3099", "が"]
        take 1 [w | Box w _ <- items] @?= [fs + Sp (unSp fs `div` 8)],
      testCase "か◌゙。: the spacing and the kinsoku of か。" $
        map stripMarks (compose markless "か\x3099。") @?= compose markless "か。",
      testCase "a combining character at the paragraph start is a box of its own" $
        take 1 (boxTexts (compose (defaultComposeEnv fs) "\x301\&a")) @?= ["\x301"],
      testCase "re◌́sume◌́s: hyphenated as resumes, no box starts with a combining character" $ do
        let env = (defaultComposeEnv fs) {cePatterns = Just englishUS}
            breaks is = length [() | Penalty _ _ (PatternHyphen _) <- is]
            items = compose env "re\x301sume\x301s"
        assertBool (show (boxTexts items)) (not (any (maybe False (isExtending . fst) . T.uncons) (boxTexts items)))
        breaks items @?= breaks (compose env "resumes")
        T.concat (boxTexts items) @?= "re\x301sume\x301s",
      testCase "a ruby base of one base and its combining character is mono ruby" $ do
        let ruby segs = [boxKind c | Box _ c <- fst (composeInlines (defaultComposeEnv fs) [IR.Ruby sp () [IR.RubySegment [IR.Text sp b] (Just r) | (b, r) <- segs]])]
        ruby [("e\x301", "x")] @?= [KindRuby]
        ruby [("e\x301", "x"), ("a", "y")] @?= [KindRuby, KindRuby]
    ]
