{- | The tracking of tate-chu-yoko and ruby boxes (root ADR 0370): each is
one box from outside; between two boxes the tracking is added once, that
of the box before; inside a box nothing of it is spread, and nothing is
added at the end of a line.

The width that a run takes on a line is the sum of the widths of its
boxes and the end edge of its last box, the space the line end gives
back ('bcEdgeEnd'), as the line breaking counts it.
-}
module TrackingBoxesSpec (tests) where

import Control.Monad (forM_, replicateM)
import Fixtures (sp)
import Golem.Doc.IR
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass
import Golem.Layout.Look
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "tracking of tate-chu-yoko and ruby boxes (root ADR 0370)"
    [ testCase "ADR 0370 I1: inv1_tracking_inline_boxes_case_1: a single box adds 0" $
        forM_ [tcy, ruby, groupRuby] $ \box ->
          forM_ trackings $ \t -> added t [box] @?= 0,
      testCase "ADR 0370 I1: inv1_tracking_inline_boxes_case_2: a tate-chu-yoko and a ruby add the tracking once, between them" $ do
        added 100 [tcy, ruby] @?= 100
        added 100 [ruby, tcy] @?= 100
        -- between them: the first box carries it, the last gives its own back at the line end
        let boxes t = [(w, bcEdgeEnd c) | Box w c <- items t [tcy, ruby]]
        [w | (w, _) <- boxes 100] @?= [w + 100 | (w, _) <- boxes 0] -- each box is wider by the tracking after it
        [e | (_, e) <- boxes 100] @?= [e - 100 | (_, e) <- boxes 0], -- and gives it back at a line end
      testCase "ADR 0370 I1: inv1_tracking_inline_boxes_property: n boxes of one tracking t add max(0, n - 1) * t" $
        forM_ [0 .. 5] $ \n -> forM_ (replicateM n [tcy, ruby, groupRuby]) $ \boxes -> forM_ trackings $ \t ->
          added t boxes @?= fromIntegral (max 0 (n - 1) * t),
      testCase "ADR 0370 I1: nothing is spread inside a box: its width less the tracking after it is that without tracking" $
        forM_ [tcy, ruby, groupRuby] $ \box -> forM_ trackings $ \t ->
          [w + bcEdgeEnd c | Box w c <- items t [box]] @?= [w + bcEdgeEnd c | Box w c <- items 0 [box]],
      testCase "ADR 0370: between boxes of different trackings, that of the box before is added" $ do
        -- the tate-chu-yoko in 100, the ruby in 200 (in a red range)
        mixed [tcy, Color sp "red" [ruby]] @?= 2100
        -- the ruby in 200, the tate-chu-yoko in 100
        mixed [Color sp "red" [ruby], tcy] @?= 2200,
      -- root ADR 0414: an ordinary character is one box too, so the tracking
      -- is added once between a tate-chu-yoko or ruby box and the character
      -- next to it, and nothing is added after the last box of a line.
      testCase "root ADR 0414 I1: a tate-chu-yoko followed by an ordinary character adds the tracking between them" $
        forM_ trackings0414 $
          \t -> added t [tcy, char] @?= fromIntegral t,
      testCase "root ADR 0414 I1: an ordinary character followed by a ruby adds the tracking between them" $
        forM_ trackings0414 $ \t -> do
          added t [char, ruby] @?= fromIntegral t
          added t [char, groupRuby] @?= fromIntegral t,
      testCase "root ADR 0414 I1: nothing is added after a tate-chu-yoko at the line end" $
        forM_ trackings0414 $ \t -> do
          added t [tcy] @?= 0
          added t [char, tcy] @?= fromIntegral t,
      testCase "root ADR 0414 I1: a tracking of 0 adds no space" $
        forM_ (sequences0414 3) $
          \xs -> added 0 xs @?= 0,
      testCase "root ADR 0414 I1: every sequence of tate-chu-yoko, mono ruby, group ruby and ordinary characters of length 0 to 3 adds the tracking once between neighbours" $
        forM_ (sequences0414 3) $ \xs -> forM_ trackings0414 $ \t ->
          added t xs @?= fromIntegral (max 0 (length xs - 1) * t)
    ]
  where
    trackings = [-100, 0, 100, 250]
    trackings0414 = [-100, 0, 100]
    char = Text sp "字"
    sequences0414 n = concat [replicateM k [tcy, ruby, groupRuby, char] | k <- [0 .. n]]
    tcy = Tcy sp (TcyLiteral "12")
    ruby = Ruby sp () [RubySegment [Text sp "漢"] (Just "かん")]
    groupRuby = Ruby sp () [RubySegment [Text sp "漢字"] (Just "かんじ")]
    env t = (defaultComposeEnv 1000) {ceLook = (plainLook "body" 1000) {lkTracking = t}}
    items t xs = fst (composeInlines (env t) xs)
    width es =
      sum [w | Box w _ <- es] + case reverse [c | Box _ c <- es] of
        [] -> 0
        c : _ -> bcEdgeEnd c
    added t xs = width (items t xs) - width (items 0 xs)
    mixed xs =
      let e = (env 100) {ceRestyle = \lk i -> case i of Color {} -> lk {lkTracking = 200}; _ -> lk}
       in width (fst (composeInlines e xs))
