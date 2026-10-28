{- | Spaces inside inline code (golem-layout ADR 0017): glue of the
advance of a space, with no stretch and no shrink, still a break.
-}
module CodeSpaceSpec (codeSpaceTests) where

import Data.Text (Text)
import Fixtures (fs, look0, sp)
import Golem.Doc.IR qualified as IR
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (Look (..))
import Test.Tasty
import Test.Tasty.HUnit

-- | The advance of a space in 'defaultComposeEnv': a quarter em.
sw :: Sp
sw = Sp (unSp fs `div` 4)

-- | Text in the look of the environment, and in the character style code.
env :: ComposeEnv
env = (defaultComposeEnv fs) {ceRestyle = \lk -> \case IR.CharStyle _ "code" _ -> lk {lkCode = True}; _ -> lk}

txt :: Text -> IR.Inline
txt = IR.Text sp

code :: Text -> IR.Inline
code t = IR.CharStyle sp "code" [txt t]

-- | The glue of the items, without the paragraph end.
glues :: [Item] -> [(Sp, Sp, Sp)]
glues items = [(w, y, z) | Glue w y z <- items, y < filStretch]

-- | The items of the inlines, ended by a forced break with no fill: the line is justified.
justified :: [IR.Inline] -> [Item]
justified is = take (length items - 3) items <> [Penalty 0 (negate infPenalty) NoHyphen]
  where
    items = fst (composeInlines env is)

-- | The set width of each glue that follows a box of the text, in a placed line.
glueAfter :: Text -> Line -> [Sp]
glueAfter t l =
  [ next - at
  | ((Box _ c, _), (Glue {}, at), (_, next)) <- zip3 placed (drop 1 placed) (drop 2 placed),
    bcText c == t
  ]
  where
    placed = placeLine l

codeSpaceTests :: TestTree
codeSpaceTests =
  testGroup
    "spaces inside inline code (golem-layout ADR 0017)"
    [ testCase "a space of code is glue of its advance and tracking, with no stretch or shrink" $ do
        let lk = look0 {lkCode = True, lkTracking = 50}
            t = Sp (round (toRational (unSp (50 * lkSize lk)) / 1000))
        glues (fst (composeInlines (defaultComposeEnv fs) {ceLook = lk} [txt "golem new DIR"])) @?= [(sw + t, 0, 0), (sw + t, 0, 0)],
      testCase "a space between words stretches by half its advance and shrinks by a third" $
        glues (fst (composeInlines (defaultComposeEnv fs) [txt "a b"])) @?= [(sw, Sp (unSp sw `div` 2), Sp (unSp sw `div` 3))],
      testCase "a space of a URL stretches and shrinks as one between words" $
        glues (fst (composeInlines (defaultComposeEnv fs) {ceLook = look0 {lkUrl = True}} [txt "a b"])) @?= [(sw, Sp (unSp sw `div` 2), Sp (unSp sw `div` 3))],
      testCase "in a justified line the space of code keeps its width; the Japanese glue takes up the rest" $ do
        let items = justified [txt "あいうえおかきくけこ", code "x y", txt "さしすせそたちつてと"]
            natural = sum [itemWidth it | it <- items, case it of Penalty {} -> False; _ -> True]
            ls = brLines (breakParagraph defaultParams (const (natural + Sp (unSp fs `div` 2))) items)
        length ls @?= 1
        case ls of
          [l] -> do
            glueAfter "x" l @?= [sw]
            assertBool "the Japanese glue stretches" (any (> 0) (glueAfter "あ" l))
          _ -> pure (),
      testCase "a line of code alone is set at its natural width, at the line start" $ do
        let items = fst (composeInlines env [code "a b c d"])
            ls = brLines (breakParagraph defaultParams (const (20 * fs)) items)
        length ls @?= 1
        case ls of
          [l] -> do
            concatMap (`glueAfter` l) ["a", "b", "c"] @?= [sw, sw, sw]
            take 1 (map snd (placeLine l)) @?= [0]
          _ -> pure (),
      testCase "long code breaks at its spaces; a line keeps no space at its end" $ do
        let items = fst (composeInlines env [code "a b c d e f g h"])
            ls = brLines (breakParagraph defaultParams (const (2 * fs)) items)
        assertBool (show (length ls)) (length ls > 1)
        mapM_ (assertBool "no glue at the end" . not . endsWithGlue . lineItems) ls
    ]
  where
    endsWithGlue its = case reverse [it | it <- its, case it of Penalty {} -> False; _ -> True] of
      Glue _ y _ : _ -> y < filStretch
      _ -> False
