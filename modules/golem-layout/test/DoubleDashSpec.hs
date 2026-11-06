{- | A run of full-width dashes in Japanese text is one box, as many em
long as it has dashes (docs/adr ADR 0172).
-}
module DoubleDashSpec (doubleDashTests) where

import Data.Text (Text)
import Fixtures (compose, fs, sp, sp0)
import Golem.Doc.IR
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (Look (..))
import Golem.Syntax (FileId (..), SrcSpan, mkSpan, spanStart)
import Test.Tasty
import Test.Tasty.HUnit

{- | The environment of a font whose U+2014 is narrower than an em, as
Noto Serif JP's (0.89 em), horizontal or vertical.
-}
narrowDash :: Bool -> ComposeEnv
narrowDash v = (defaultComposeEnv fs) {ceAdvance = \_ c -> if c == '\x2014' then 89 / 100 else 1, ceVertical = v}

-- | The boxes of the items: their text, width and kind.
boxesOf :: [Item] -> [(Text, Sp, BoxKind)]
boxesOf items = [(bcText c, w, boxKind c) | Box w c <- items]

-- | The items between the first box and the second.
between1 :: [Item] -> [Item]
between1 items = case break isBox (drop 1 (dropWhile (not . isBox) items)) of
  (xs, _) -> xs
  where
    isBox = \case Box {} -> True; _ -> False

-- | The edges of the boxes.
edges :: [Item] -> [(Sp, Sp)]
edges items = [(bcEdgeStart c, bcEdgeEnd c) | Box _ c <- items]

-- | The items without the boxes' text, width and kind: what comes around them.
around :: [Item] -> [Item]
around = map (\case Box _ c -> Box 0 c {bcText = "", bcTag = 0}; x -> x)

doubleDashTests :: TestTree
doubleDashTests =
  testGroup
    "double dashes (docs/adr ADR 0172)"
    [ testCase "two dashes, U+2014, U+2015 or mixed, are one box 2em long, horizontal and vertical" $
        sequence_
          [ boxesOf (compose (narrowDash v) ("あ" <> d <> "い")) @?= [("あ", fs, KindText), (d, 2 * fs, KindDashes), ("い", fs, KindText)]
          | v <- [False, True],
            d <- ["\x2014\x2014", "\x2015\x2015", "\x2014\x2015", "\x2015\x2014"]
          ],
      testCase "three dashes are one box 3em long" $
        sequence_
          [ boxesOf (compose (narrowDash v) "あ\x2014\x2014\x2014い") @?= [("あ", fs, KindText), ("\x2014\x2014\x2014", 3 * fs, KindDashes), ("い", fs, KindText)]
          | v <- [False, True]
          ],
      testCase "a single dash is a box of one character, as wide as the font has it" $
        sequence_
          [ boxesOf (compose (narrowDash v) "あ\x2014い\x2015う") @?= [("あ", fs, KindText), ("\x2014", Sp (round (toRational (unSp fs) * 89 / 100)), KindText), ("い", fs, KindText), ("\x2015", fs, KindText), ("う", fs, KindText)]
          | v <- [False, True]
          ],
      testCase "the run is cut at ruby, kenten, character style and colour" $ do
        let dash = "\x2014"
            env = narrowDash False
            texts inls = [t | (t, _, _) <- boxesOf (fst (composeInlines env inls))]
        texts [sp0 ("あ" <> dash), Kenten sp Nothing [sp0 dash], sp0 "い"] @?= ["あ", dash, dash, "い"]
        texts [sp0 ("あ" <> dash), CharStyle sp "s" [sp0 dash], sp0 "い"] @?= ["あ", dash, dash, "い"]
        texts [sp0 ("あ" <> dash), Color sp "red" [sp0 (dash <> dash)], sp0 "い"] @?= ["あ", dash, dash <> dash, "い"]
        texts [sp0 ("あ" <> dash), Ruby sp () [RubySegment [Text sp dash] (Just "だ")], sp0 "い"] @?= ["あ", dash, dash <> "|だ", "い"]
        -- inside one of them, the run is one box
        texts [sp0 "あ", Kenten sp Nothing [sp0 (dash <> dash)], sp0 "い"] @?= ["あ", dash <> dash, "い"],
      testCase "dashes in a Latin word stay in the word" $ do
        let env = narrowDash False
        [t | (t, _, _) <- boxesOf (compose env "word\x2014\x2014word")] @?= ["word\x2014\x2014", "word"]
        [t | (t, _, _) <- boxesOf (compose env "word\x2014word")] @?= ["word\x2014", "word"]
        [(t, k) | (t, _, k) <- boxesOf (compose env "あword\x2014\x2014い")] @?= [("あ", KindText), ("word\x2014\x2014", KindText), ("い", KindText)],
      testCase "no break inside the run; the spacing and the breaks around it are those of a single dash" $
        sequence_
          [ do
              let one = compose env "あ\x2014い"
                  two = compose env "あ\x2014\x2014い"
              -- the same items around the boxes, and the same edges
              around two @?= around one
              edges two @?= edges one
              between1 two @?= between1 one
          | strict <- [True, False],
            v <- [False, True],
            let env = (narrowDash v) {ceKinsokuStrict = strict}
          ],
      testCase "a run at the start and the end of a paragraph" $
        boxesOf (compose (narrowDash False) "\x2015\x2015") @?= [("\x2015\x2015", 2 * fs, KindDashes)],
      testCase "with tracking, the run takes the tracking once, after it, given back at the line end" $ do
        let env = narrowDash False
            tracked = env {ceLook = (ceLook env) {lkTracking = 100}}
            t = Sp (unSp fs `div` 10)
        [(w, bcEdgeEnd c) | Box w c <- compose tracked "\x2014\x2014"] @?= [(2 * fs + t, negate t)],
      testCase "the box of a run comes from the run itself in the source (G07101)" $ do
        let src = "あい\x2014\x2014う"
            at = mkSpan (FileId 0) 10 25
        -- the text at bytes 10 to 25: the run starts 6 bytes in
        [spanStart (snd (bcSource c)) | Box _ c <- fst (composeInlines (narrowDash False) [Text at src]), boxKind c == KindDashes] @?= [16]
        -- a text that is not the source byte for byte keeps the span of the text
        [snd (bcSource c) | Box _ c <- fst (composeInlines (narrowDash False) [Text (wider at) src]), boxKind c == KindDashes] @?= [wider at]
    ]
  where
    wider :: SrcSpan -> SrcSpan
    wider s = mkSpan (FileId 0) (spanStart s) (spanStart s + 40)
