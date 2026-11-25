-- | The text frames of style.toml (root ADR 0438).
module FramesSpec (tests) where

import Control.Monad (forM_)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Golem.Project.PathData (Path (..), Segment (..), SubPath (..))
import Golem.Project.Style
import Golem.Syntax
import Support (offsetOf)
import Test.Tasty
import Test.Tasty.HUnit

page :: Text -> Text
page layout = "[page]\nsize = \"A4\"\n" <> layout <> "[page.grid]\nfont-size = \"10pt\"\ncharacters = 30\nlines = 30\nline-pitch = \"16pt\"\nposition = { top = \"20mm\", " <> (if layout == "" then "gutter" else "left") <> " = \"25mm\" }\n"

facing :: Text -> Text
facing = (page "" <>)

single :: Text -> Text
single = (page "layout = \"single\"\n" <>)

errors :: Text -> [(DiagnosticCode, Int)]
errors src = either (map (\d -> (diagCode d, spanStart (diagSpan d)))) (const []) (parseStyle (FileId 0) src)

codes :: Text -> [DiagnosticCode]
codes = map fst . errors

framesOf :: Text -> Map.Map Text FrameDef
framesOf src = either (error . show) stFrames (parseStyle (FileId 0) src)

rect :: Text
rect = "x = \"0mm\"\ny = \"0mm\"\nwidth = \"10mm\"\nheight = \"10mm\"\n"

tests :: TestTree
tests =
  testGroup
    "the text frames of style.toml (root ADR 0438)"
    [ testCase "root ADR 0438 I1: a frame of a rectangle reads its keys, x from the left and no wrap by default" $ do
        let fs = framesOf (facing "[frames.title]\nx = \"20pt\"\ny = \"30pt\"\nwidth = \"100pt\"\nheight = \"40pt\"\nparagraph-style = \"body\"\ntext = \"扉の文\"\n")
        fmap frameShape (Map.lookup "title" fs) @?= Just (Just (FrameRect (Abs (Sp 1310720)) (Abs (Sp 1966080)) (Abs (Sp 6553600)) (Abs (Sp 2621440))))
        fmap frXFrom (Map.lookup "title" fs) @?= Just FromLeft
        fmap frWrap (Map.lookup "title" fs) @?= Just FrameWrapNone
        fmap frText (Map.lookup "title" fs) @?= Just (Just "扉の文"),
      testCase "root ADR 0438 I2: a frame of a path reads it in its unit" $ do
        let fs = framesOf (facing "[frames.round]\npath = \"M 0 0 L 10 0 L 10 10 Z\"\nunit = \"pt\"\nx-from = \"inside\"\nwrap = \"around\"\n")
        fmap frameShape (Map.lookup "round" fs) @?= Just (Just (FramePath (Path [SubPath (0, 0) [LineTo (655360, 0), LineTo (655360, 655360)] True])))
        fmap frXFrom (Map.lookup "round" fs) @?= Just FromInside
        fmap frWrap (Map.lookup "round" fs) @?= Just FrameWrapAround,
      testCase "root ADR 0438 I10: the keys of the rectangle and a path both is G03285 alone" $ do
        let src = facing ("[frames.a]\n" <> rect <> "path = \"M 0 0 L 1 0 L 1 1 Z\"\n")
        errors src @?= [(DiagnosticCode "G03285", offsetOf src "\"M 0 0")],
      testCase "root ADR 0438 I10: neither the keys of the rectangle nor a path is G03285 alone" $
        codes (facing "[frames.a]\ntext = \"文\"\n") @?= [DiagnosticCode "G03285"],
      testCase "root ADR 0438 I10: only some of the keys of the rectangle is G03286 alone" $
        forM_ ["x = \"0mm\"\n", "x = \"0mm\"\ny = \"0mm\"\nwidth = \"1mm\"\n", "height = \"1mm\"\n"] $ \keys ->
          codes (facing ("[frames.a]\n" <> keys)) @?= [DiagnosticCode "G03286"],
      testCase "root ADR 0438 I10: a path with a subpath that is not closed is G03287 alone" $ do
        let src = facing "[frames.a]\npath = \"M 0 0 L 10 0 L 10 10 Z M 20 20 L 30 20\"\n"
        errors src @?= [(DiagnosticCode "G03287", offsetOf src "\"M 0 0")],
      testCase "root ADR 0438 I10: x-from inside or outside in the single-page mode is G03288 alone" $
        forM_ ["inside", "outside"] $ \side -> do
          let src = single ("[frames.a]\n" <> rect <> "x-from = \"" <> side <> "\"\n")
          errors src @?= [(DiagnosticCode "G03288", offsetOf src ("\"" <> side <> "\""))],
      testCase "root ADR 0438 I10: x-from left in the single-page mode is no error" $
        codes (single ("[frames.a]\n" <> rect <> "x-from = \"left\"\n")) @?= [],
      testCase "root ADR 0438 I10: a name in the frames of a master page that [frames] does not have is G03289 alone" $ do
        let src = facing ("[frames.a]\n" <> rect <> "[masters.body]\nframes = [\"a\", \"missing\"]\n")
        errors src @?= [(DiagnosticCode "G03289", offsetOf src "[\"a\"")],
      testCase "root ADR 0438: a master page keeps the names of its frames in order" $ do
        let src = facing ("[frames.a]\n" <> rect <> "[frames.b]\npath = \"M 0 0 L 1 0 L 1 1 Z\"\n[masters.body]\nframes = [\"b\", \"a\"]\n")
        either (error . show) (fmap mdFrames . Map.lookup "body" . stMasters) (parseStyle (FileId 0) src) @?= Just ["b", "a"],
      testCase "root ADR 0438: a width of 0, an unknown x-from, wrap and unit, path data that does not read and an unknown key are G03006"
        $ forM_
          [ "x = \"0mm\"\ny = \"0mm\"\nwidth = \"0mm\"\nheight = \"10mm\"\n",
            rect <> "x-from = \"right\"\n",
            rect <> "wrap = \"both\"\n",
            "path = \"M 0 0 L 1 0 L 1 1 Z\"\nunit = \"in\"\n",
            "path = \"M 0 0 Q 1 1 2 2 Z\"\n",
            rect <> "columns = 2\n"
          ]
        $ \keys -> codes (facing ("[frames.a]\n" <> keys)) @?= [DiagnosticCode "G03006"],
      testCase "root ADR 0438: the name of a frame is a style name, and its paragraph style must be there" $ do
        codes (facing ("[frames.Bad]\n" <> rect)) @?= [DiagnosticCode "G03006"]
        length (codes (facing ("[frames.a]\n" <> rect <> "paragraph-style = \"none-such\"\n"))) @?= 1
    ]
