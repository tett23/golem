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
        mixed [Color sp "red" [ruby], tcy] @?= 2200
    ]
  where
    trackings = [-100, 0, 100, 250]
    tcy = Tcy sp "12"
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
