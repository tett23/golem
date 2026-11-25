{- | The figures a block command of .emet returns (root ADR 0439): a
figure of its own at the top of the output, without a web image, whose
source is an SVG in a data: source; any other figure is E06104.
-}
module GmFigureSpec (gmFigureTests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Golem.Doc.IR (Block (..), BlockBody (..), Figure (..))
import Golem.Emet
import Golem.Emet.Gm (functionNamespaces)
import Golem.Eval.Functions (BlockFunction (..), FunctionNamespace (..))
import Golem.Syntax
import Support
import Test.Tasty
import Test.Tasty.HUnit

svg :: Text
svg = "data:image/svg+xml,<svg xmlns=\\\"http://www.w3.org/2000/svg\\\"></svg>"

figure :: Text -> Text -> Text
figure src web = "Block.FigureBlock (Block.Figure \"" <> src <> "\" " <> web <> " \"x\" Nothing Nothing [] Nothing False True)"

-- | Calls the block command fig of main.emet without arguments or a body.
callFig :: Text -> IO (Either [Diagnostic] [Block])
callFig src = case load ("pub block fig :: Blocks\nfig = " <> src <> "\n") of
  (ds, Just p) | not (any isError ds) -> case Map.lookup "main.emet" (functionNamespaces noHandlers p) >>= Map.lookup "fig" . fnBlock of
    Just f -> pure (bfCall f [] [] callSpan)
    Nothing -> assertFailure "no block command fig" >> fail "unreachable"
  (ds, _) -> assertFailure (show ds) >> fail "unreachable"

codesOfCall :: Either [Diagnostic] [Block] -> [Text]
codesOfCall = either (\ds -> [c | DiagnosticCode c <- map diagCode ds]) (const [])

gmFigureTests :: TestTree
gmFigureTests =
  testGroup
    "the figures of block commands (root ADR 0439)"
    [ testCase "root ADR 0439 I7: a figure of an SVG in a data: source passes as it is" $ do
        r <- callFig ("[" <> figure svg "Nothing" <> "]")
        fmap (map (\(Block _ _ _ b) -> case b of FigureBlock f -> figSource f; _ -> "")) r @?= Right ["data:image/svg+xml,<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>"],
      testCase "root ADR 0439 I7: a figure of a file of the project is E06104" $
        callFig ("[" <> figure "images/a.svg" "Nothing" <> "]") >>= (@?= ["E06104"]) . codesOfCall,
      testCase "root ADR 0439 I7: a figure of PNG in a data: source is E06104" $
        callFig ("[" <> figure "data:image/png,x" "Nothing" <> "]") >>= (@?= ["E06104"]) . codesOfCall,
      testCase "root ADR 0439 I7: a figure with a web image is E06104" $
        callFig ("[" <> figure svg "(Just \"images/a.png\")" <> "]") >>= (@?= ["E06104"]) . codesOfCall,
      testCase "root ADR 0439 I7: a figure in a bulleted list is E06104" $
        callFig ("[Block.BulletList [Block.ListItem Nothing [" <> figure svg "Nothing" <> "]]]") >>= (@?= ["E06104"]) . codesOfCall
    ]
