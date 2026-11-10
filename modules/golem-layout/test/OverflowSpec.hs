{- | How far a line sticks out past its target (docs/adr ADR 0210):
'lineOverflow' against the condition of the line breaking (O1, O2), and,
on every small paragraph, against the widest run of boxes the paragraph
cannot break inside (O3, O4).
-}
module OverflowSpec (overflowTests) where

import Control.Monad (replicateM)
import Data.List (find)
import Data.Text qualified as T
import Fixtures (look0)
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (noBoxSource)
import Test.Tasty
import Test.Tasty.HUnit

overflowTests :: TestTree
overflowTests =
  testGroup
    "how far a line sticks out (docs/adr ADR 0210)"
    [ testCase "O1, O2: one box of W - 1, W, W + 1 and 2W in a line of W" $
        [overflows (breakParagraph defaultParams (const 30) (box 0 w : finish)) | w <- [29, 30, 31, 60]]
          @?= [[0], [0], [1], [30]],
      testCase "O1, O2: a glue of shrink 1 inside the run takes 1sp of a natural width of 31, not of 32" $ do
        let run w = [box 0 w, Penalty 0 infPenalty NoHyphen, glue 1 0 1, box 1 15] <> finish
        overflows (breakParagraph defaultParams (const 30) (run 15)) @?= [0]
        overflows (breakParagraph defaultParams (const 30) (run 16)) @?= [1],
      testCase "O1, O2: a full stop hung past the target is not overflow" $ do
        let stop = Box 10 (content 1) {bcProtrudeEnd = 5}
            r = breakParagraph defaultParams {pProtrusion = True} (const 30) ([box 0 25, stop] <> finish)
        overflows r @?= [0]
        map lineProtrusion (brLines r) @?= [(0, 5)],
      testCase "O1, O2: lineOverfull is lineOverflow > 0" $
        mapM_
          (\l -> lineOverfull l @?= (lineOverflow l > 0))
          (concatMap (brLines . breakParagraph defaultParams (const width) . itemsOf) (paragraphs 2)),
      testCase "O1: on every small paragraph, max 0 (N - Z - L) of every line, in sp" $
        mapM_
          (\p -> map lineOverflow (lines' p) @?= map expected (lines' p))
          (paragraphs 3),
      testCase "O3: when every run fits fully shrunk, no line overflows" $
        mapM_
          (\p -> assertEqual (show p) [] [l | l <- lines' p, lineOverflow l > 0])
          [p | p <- paragraphs 3, all ((<= width) . shrunk) p],
      testCase "O4: the line of a run longer than the line fully shrunk overflows" $
        mapM_
          ( \p ->
              let ls = lines' p
               in mapM_
                    ( \r -> case find (elem (firstTag r) . tags) ls of
                        Just l -> assertBool (show p) (lineOverflow l > 0)
                        Nothing -> assertFailure ("no line holds " <> show r)
                    )
                    [r | r <- numbered p, shrunk (snd r) > width]
          )
          [p | p <- paragraphs 3, any ((> width) . shrunk) p]
    ]
  where
    overflows = map lineOverflow . brLines
    lines' = brLines . breakParagraph defaultParams (const width) . itemsOf
    expected l =
      let n = sum [w | Box w _ <- lineItems l] + sum [w | Glue w _ _ _ _ <- lineItems l]
          z = sum [s | Glue _ _ s _ _ <- lineItems l]
       in max 0 (n - z - lineTarget l)
    tags l = [read (T.unpack (bcText c)) | Box _ c <- lineItems l] :: [Int]

-- | The width of a line.
width :: Sp
width = 10

{- | A run the paragraph cannot break inside: its boxes, and the glue
between each two of them (its width and shrink), behind a penalty that
forbids the break.
-}
data Run = Run [Sp] [(Sp, Sp)]
  deriving stock (Show)

-- | Every run of one or two boxes of 4, 10 and 11, with the glue of 1 and a shrink of 0 or 1.
runs :: [Run]
runs = [Run [w] [] | w <- ws] <> [Run [a, b] [g] | a <- ws, b <- ws, g <- [(1, 0), (1, 1)]]
  where
    ws = [4, 10, 11]

-- | The paragraphs of one to n runs, separated by glue of 2 that shrinks by 1.
paragraphs :: Int -> [[Run]]
paragraphs n = concat [replicateM k runs | k <- [1 .. n]]

-- | The width of a run fully shrunk.
shrunk :: Run -> Sp
shrunk (Run bs gs) = sum bs + sum [w - z | (w, z) <- gs]

-- | The runs with the tag of the first box of each.
numbered :: [Run] -> [(Int, Run)]
numbered p = zip (scanl (+) 0 [length bs | Run bs _ <- p]) p

firstTag :: (Int, Run) -> Int
firstTag = fst

itemsOf :: [Run] -> [Item]
itemsOf p = concat (zipWith runItems [0 ..] (numbered p)) <> finish
  where
    runItems i (t, Run bs gs) =
      [glue 2 1 1 | i > (0 :: Int)]
        <> concat (zipWith3 (\k w g -> box k w : maybe [] (\(gw, gz) -> [Penalty 0 infPenalty NoHyphen, glue gw 0 gz]) g) [t ..] bs (map Just gs <> [Nothing]))

finish :: [Item]
finish = [Penalty 0 infPenalty NoHyphen, glue 0 filStretch 0, Penalty 0 (negate infPenalty) NoHyphen]

-- | A box of a width; its text is its tag.
box :: Int -> Sp -> Item
box t w = Box w (content t)

content :: Int -> BoxContent
content t = BoxContent (T.pack (show t)) False 0 0 0 look0 0 0 [] 0 0 noBoxSource Nothing noLeaf 0
