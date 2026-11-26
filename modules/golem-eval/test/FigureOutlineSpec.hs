-- | The outline of a wrapped figure on @figure (root ADR 0464).
module FigureOutlineSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Golem.Doc.IR
import Golem.Eval.File
import Golem.Project.PathData (Path (..))
import Golem.Project.Style (OutlineDef (..), Style (..))
import Golem.Syntax
import Support
import Test.Tasty
import Test.Tasty.HUnit

-- a context with images/a.png and the outlines round (readable) and broken (not readable)
octx :: EvalContext
octx =
  baseCtx
    { ctxAssets = Map.fromList [("images/a.png", AssetPresent)],
      ctxStyle = (ctxStyle baseCtx) {stOutlines = Map.fromList [("round", OutlineDef (Right (Path []))), ("broken", OutlineDef (Left "閉じていない部分パスがあります"))]}
    }

run :: Text -> ([BlockBody], [(Text, Severity, Text)])
run src = let (ds, r) = evalSource octx src in (resultBodies r, [(diagCodeText d, diagSeverity d, diagMessage d) | d <- ds])

outlines :: Text -> [Maybe Text]
outlines src = [figOutline f | FigureBlock f <- fst (run src)]

tests :: TestTree
tests =
  testGroup
    "the outline of @figure (root ADR 0464)"
    [ testCase "root ADR 0464 I1: a figure without outline has none" $ do
        outlines "@figure images/a.png alt=x wrap=start width=10zw\n" @?= [Nothing]
        snd (run "@figure images/a.png alt=x wrap=start width=10zw\n") @?= [],
      testCase "root ADR 0464: a wrapped figure keeps the name of its outline" $ do
        outlines "@figure images/a.png alt=x wrap=end width=10zw outline=round\n" @?= [Just "round"]
        snd (run "@figure images/a.png alt=x wrap=end width=10zw outline=round\n") @?= [],
      testCase "root ADR 0464 I6: an outline style.toml has, though it cannot be read, is no error of the figure (G03300 is at the style)" $
        snd (run "@figure images/a.png alt=x wrap=end width=10zw outline=broken\n") @?= [],
      testCase "root ADR 0464 I1, I6: outline=missing is G02285, and the figure is set by its rectangle" $ do
        let (bs, ds) = run "@figure images/a.png alt=x wrap=start width=10zw outline=missing\n"
        ds @?= [("G02285", Error, "輪郭 missing がありません")]
        [(figWrap f, figOutline f) | FigureBlock f <- bs] @?= [(Just WrapStart, Nothing)],
      testCase "root ADR 0464 I6: outline on a figure without wrap is the warning G02286, and the outline is not used" $ do
        let (bs, ds) = run "@figure images/a.png alt=x outline=round\n"
        ds @?= [("G02286", Warning, "outline は wrap のある図版にだけ使います")]
        [figOutline f | FigureBlock f <- bs] @?= [Nothing],
      testCase "root ADR 0464 I6: outline=missing without wrap is G02286 alone" $
        [c | (c, _, _) <- snd (run "@figure images/a.png alt=x outline=missing\n")] @?= ["G02286"],
      testCase "root ADR 0464 I6: each @figure with an outline that is missing is one G02285, each without wrap one G02286" $
        [c | (c, _, _) <- snd (run "@figure images/a.png alt=x wrap=start width=10zw outline=missing\n\n@figure images/a.png alt=x wrap=start width=10zw outline=missing\n\n@figure images/a.png alt=y outline=round\n\n@figure images/a.png alt=z outline=round\n")]
          @?= ["G02285", "G02285", "G02286", "G02286"]
    ]
