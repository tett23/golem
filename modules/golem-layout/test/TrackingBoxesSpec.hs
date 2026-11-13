module TrackingBoxesSpec (tests) where

import Control.Monad (forM_)
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
    "Golem ADR 0370"
    [ testCase "inv1_tracking_inline_boxes_case_1: single box" $
        width 100 [Tcy sp "12"] @?= width 0 [Tcy sp "12"],
      testCase "inv1_tracking_inline_boxes_case_2: tcy and ruby" $
        width 100 [Tcy sp "12", ruby] - width 0 [Tcy sp "12", ruby] @?= 100,
      testCase "inv1: the preceding box decides a mixed tracking gap" $ do
        let env = (defaultComposeEnv 1000) {ceLook = (plainLook "body" 1000) {lkTracking = 100}, ceRestyle = \lk _ -> lk {lkTracking = 200}}
            boxes = [(w, bcEdgeEnd c) | Box w c <- fst (composeInlines env [Tcy sp "12", Color sp "red" [ruby]])]
        sum (map fst boxes) + snd (last boxes) @?= 2100,
      testCase "inv1_tracking_inline_boxes_property: n boxes have n-1 gaps" $
        forM_ [0 .. 8] $ \n -> forM_ [-100, 0, 100] $ \tracking ->
          let boxes = take n (cycle [Tcy sp "12", ruby])
           in width tracking boxes - width 0 boxes @?= fromIntegral (max 0 (n - 1)) * fromIntegral tracking
    ]
  where
    ruby = Ruby sp () [RubySegment [Text sp "漢"] (Just "か")]
    width tracking boxes =
      let env = (defaultComposeEnv 1000) {ceLook = (plainLook "body" 1000) {lkTracking = tracking}}
          measured = [(w, bcEdgeEnd c) | Box w c <- fst (composeInlines env boxes)]
       in sum (map fst measured) + case reverse measured of [] -> 0; (_, edge) : _ -> edge
