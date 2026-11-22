-- | Physical page anchors independent of parity (root ADR 0400).
module SinglePageSpec (tests) where

import Control.Monad (forM_)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.LayoutSpec
import Golem.Project.Style
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

src :: Text -> Text -> Text -> Text -> Text
src mode side size extra = "[page]\nsize = " <> size <> "\nlayout = \"single\"\nwriting-mode = \"" <> mode <> "\"\n[page.grid]\nfont-size = \"10pt\"\ncharacters = 10\nlines = 10\nline-pitch = \"16pt\"\nposition = { top = \"20pt\", " <> side <> " = \"30pt\" }\n" <> extra

withGeom :: Text -> (PageGeometry -> Assertion) -> Assertion
withGeom text use = case parseStyle (FileId 0) text >>= pageGeometry (FileId 0) True of
  Left ds -> assertFailure (show ds)
  Right g -> use g

pt :: Integer -> Sp
pt = Sp . (* 65536)

tests :: TestTree
tests =
  testGroup
    "root ADR 0400"
    [ testCase "I2/I3: horizontal and vertical physical anchors never mirror" $
        forM_ ["horizontal", "vertical"] $ \mode -> forM_ ["left", "right"] $ \side ->
          withGeom (src mode side "\"A4\"" "") $ \g -> do
            let r = typeAreaFor g 1
                (pw, ph) = pgPageSize g
            forM_ [1 .. 4] $ \n -> do
              typeAreaFor g n @?= r
              columnsFor g n @?= columnsFor g 1
            (if side == "left" then rectX r else pw - rectX r - rectW r) @?= pt 30
            ph - rectY r - rectH r @?= pt 20,
      testCase "I2: horizontal and vertical multicolumn reading order is stable" $
        forM_ ["horizontal", "vertical"] $ \mode ->
          withGeom (T.replace "position =" "columns = 2\ncolumn-gap = \"10pt\"\nposition =" (src mode "left" "\"A4\"" "")) $ \g -> do
            length (columnsFor g 1) @?= 2
            forM_ [2 .. 4] $ \n -> columnsFor g n @?= columnsFor g 1,
      testCase "I2: left and right sidenote rectangles are stable and outside the body" $
        forM_ ["left", "right"] $ \side ->
          withGeom (src "horizontal" "left" "\"A4\"" ("[sidenotes]\nside = \"" <> side <> "\"\nwidth = \"10pt\"\ngap = \"5pt\"\n")) $ \g -> do
            let r = typeAreaFor g 1
            case sidenoteAreaFor g 1 of
              Nothing -> assertFailure "no sidenote rectangle"
              Just sn -> do
                forM_ [1 .. 4] $ \n -> sidenoteAreaFor g n @?= Just sn
                if side == "left" then rectX sn + rectW sn + pt 5 @?= rectX r else rectX sn @?= rectX r + rectW r + pt 5,
      testCase "I2/A5: either master element accepts either central anchor" $
        forM_ ["top", "bottom"] $ \vertical ->
          withGeom (src "horizontal" "left" "\"A4\"" ("[masters.default]\nrunning-head = { position = \"" <> vertical <> "-center\", odd = \"title\", even = \"none\" }\nfolio = { position = \"" <> vertical <> "-center\", format = \"{n}\" }\n")) $ \g -> do
            let r = typeAreaFor g 1
                middle = rectX r + Sp (unSp (rectW r) `div` 2)
            case Map.lookup "default" (pgMasters g) of
              Just (MasterGeometry (Just (_, _, ho, he)) (Just (_, fo, fe)) _ _) -> do
                ho @?= he
                fo @?= fe
                ho @?= fo
                (anX ho, anAlign ho) @?= (middle, AlignCenter)
              other -> assertFailure (show other),
      testCase "I2: physical master positions align at the same physical edge" $
        forM_ ["top", "bottom"] $ \vertical -> forM_ ["left", "right"] $ \side ->
          withGeom (src "horizontal" "left" "\"A4\"" ("[masters.default]\nfolio = { position = \"" <> vertical <> "-" <> side <> "\", format = \"{n}\" }\n")) $ \g -> do
            let r = typeAreaFor g 1
            case Map.lookup "default" (pgMasters g) >>= mgFolio of
              Just (_, a, b) -> do
                a @?= b
                (anX a, anAlign a) @?= if side == "left" then (rectX r, AlignStart) else (rectX r + rectW r, AlignEnd)
              Nothing -> assertFailure "no folio anchor",
      testCase "I3: exact trim boundary is allowed" $
        withGeom (src "horizontal" "left" "{ width = \"130pt\", height = \"174pt\" }" "") $
          \g -> rectY (typeAreaFor g 1) @?= 0,
      testCase "I3: one sp overflow is rejected as G07001" $ do
        let text = src "horizontal" "left" "{ width = \"129.9999847412109375pt\", height = \"174pt\" }" ""
        case parseStyle (FileId 0) text >>= pageGeometry (FileId 0) False of
          Left [d] -> diagCode d @?= DiagnosticCode "G07001"
          other -> assertFailure (show other),
      testCase "I3: negative physical margins are geometric errors" $
        forM_ ["left", "right"] $ \side -> do
          let text = T.replace (side <> " = \"30pt\"") (side <> " = \"-1pt\"") (src "horizontal" side "\"A4\"" "")
          case parseStyle (FileId 0) text >>= pageGeometry (FileId 0) False of
            Left [d] -> diagCode d @?= DiagnosticCode "G07001"
            other -> assertFailure (show other),
      testCase "I7: crop marks do not enable default hidden folios" $
        withGeom (src "horizontal" "left" "\"A4\"" "") $
          \g -> pgHiddenFolio g @?= Nothing
    ]
