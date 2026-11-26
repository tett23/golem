-- | The outlines of figures in style.toml (root ADR 0464).
module OutlinesSpec (tests) where

import Control.Monad (void)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Golem.Project.PathData (Path (..), Segment (..), SubPath (..))
import Golem.Project.Style
import Golem.Syntax
import Support (offsetOf)
import Test.Tasty
import Test.Tasty.HUnit

style :: Text -> Text
style = ("[page]\nsize = \"A4\"\n[page.grid]\nfont-size = \"10pt\"\ncharacters = 30\nlines = 30\nline-pitch = \"16pt\"\nposition = { top = \"20mm\", gutter = \"25mm\" }\n" <>)

errors :: Text -> [(DiagnosticCode, Int)]
errors src = either (map (\d -> (diagCode d, spanStart (diagSpan d)))) (const []) (parseStyle (FileId 0) src)

outlinesOf :: Text -> Map.Map Text OutlineDef
outlinesOf src = either (error . show) stOutlines (parseStyle (FileId 0) src)

tests :: TestTree
tests =
  testGroup
    "the outlines of figures in style.toml (root ADR 0464)"
    [ testCase "root ADR 0464: an outline keeps its coordinates of no unit, each 65536 times its value" $
        fmap outlinePath (Map.lookup "round" (outlinesOf (style "[outlines.round]\npath = \"M 0 0 L 10.5 0 L 10 20 Z\"\n")))
          @?= Just (Just (Path [SubPath (0, 0) [LineTo (688128, 0), LineTo (655360, 1310720)] True])),
      testCase "root ADR 0464 I6: a style without outlines has none and no error" $ do
        Map.keys (outlinesOf (style "")) @?= []
        errors (style "") @?= [],
      testCase "root ADR 0464 I6: a path that is not closed is G03300 alone, at the path" $ do
        let src = style "[outlines.a]\npath = \"M 0 0 L 10 0\"\n"
        errors src @?= [(DiagnosticCode "G03300", offsetOf src "\"M 0 0")],
      testCase "root ADR 0464 I6: a path that cannot be read is G03300 alone, at the path" $ do
        let src = style "[outlines.a]\npath = \"M 0 0 Q 1 1 2 2 Z\"\n"
        errors src @?= [(DiagnosticCode "G03300", offsetOf src "\"M 0 0")],
      testCase "root ADR 0464 I6: an outline with a subpath not closed after a closed one is G03300" $ do
        let src = style "[outlines.a]\npath = \"M 0 0 L 10 0 L 10 10 Z M 20 20 L 30 20\"\n"
        map fst (errors src) @?= [DiagnosticCode "G03300"],
      testCase "root ADR 0464 I6: each outline that cannot be read is one G03300" $ do
        let src = style "[outlines.a]\npath = \"M 0 0 L 10 0\"\n[outlines.b]\npath = \"\"\n[outlines.c]\npath = \"M 0 0 L 1 0 L 1 1 Z\"\n"
        map fst (errors src) @?= [DiagnosticCode "G03300", DiagnosticCode "G03300"],
      testCase "root ADR 0464 I6: a closed outline is no error and is read" $ do
        let src = style "[outlines.c]\npath = \"M 0 0 L 1 0 L 1 1 Z\"\n"
        errors src @?= []
        fmap (void . outlinePath) (Map.lookup "c" (outlinesOf src)) @?= Just (Just ())
    ]
