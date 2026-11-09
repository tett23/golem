-- | The soft hyphen [shy] (docs/adr ADR 0272).
module ShySpec (tests) where

import Data.Maybe (isJust)
import Data.Text (Text)
import Golem.Doc.IR
import Golem.Eval.Builtin (FixedBuiltin (..), BuiltinInline (..), parseBuiltin, pluginCommandName)
import Support
import Test.Tasty
import Test.Tasty.HUnit

-- | The blocks of a source.
blocksOf :: Text -> [Block]
blocksOf = resultBlocks . evalResult baseCtx

-- | The texts of the paragraphs of a source, without their spans.
textsOf :: Text -> [[Text]]
textsOf src = [[t | Text _ t <- is] | Block _ _ _ (Paragraph _ is) <- blocksOf src]

-- | The codes of the diagnostics of a source.
codes :: Text -> [Text]
codes src = [c | (c, _, _, _) <- map diagSite (fst (evalSource baseCtx src))]

tests :: TestTree
tests =
  testGroup
    "[shy] (docs/adr ADR 0272)"
    [ testCase "I10: [shy] is the same IR as U+00AD written in the source" $ do
        textsOf "in[shy]com[shy]pre\n" @?= textsOf "in\xAD\&com\xAD\&pre\n"
        textsOf "in[shy]com\n" @?= [["in\xAD\&com"]]
        textsOf "a [shy]b\n" @?= [["a \xAD\&b"]]
        codes "in[shy]com\n" @?= [],
      testCase "[shy] alone is a text of U+00AD" $
        textsOf "[shy]\n" @?= [["\xAD"]],
      testCase "G02152: [shy] with a positional or a keyword argument, and nothing set" $ do
        codes "a[shy x]b\n" @?= ["G02152"]
        codes "a[shy x=1]b\n" @?= ["G02152"]
        textsOf "a[shy x]b\n" @?= [["ab"]],
      testCase "G02038: [shy] with a prose slot" $
        codes "a[shy: b]c\n" @?= ["G02038"],
      testCase "shy is a built-in command a plugin may not override" $ do
        parseBuiltin "shy" @?= Just (Fixed BShy)
        isJust (pluginCommandName "shy") @?= False
    ]
