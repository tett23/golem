-- | Commands of the functions of .gmx in .gm (docs/adr/0150).
module FunctionSpec (functionTests) where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR
import Golem.Eval.File
import Golem.Eval.Value
import Golem.Project.Style (LineBreaks (..))
import Golem.Syntax
import Support
import Test.Tasty
import Test.Tasty.HUnit

-- | A context with the functions of the tests: tax-included, emph-twice, word-table, bad-style, styled.
fctx :: EvalContext
fctx =
  baseCtx
    { ctxCharStyles = Set.fromList ["strong"],
      ctxParaStyles = Map.fromList [("body", JoinLines)],
      ctxFunctions =
        noFunctions
          { ftInline =
              Map.fromList
                [ ("tax-included", FunctionCommand [FPNat] 0 (\vs _ sp -> Right [Text sp (T.pack (show [n * 11 `div` 10 | VNat n <- vs]))])),
                  ("emph-twice", FunctionCommand [] 1 (\_ slots sp -> Right [CharStyle sp "strong" (concat slots), CharStyle sp "strong" (concat slots)]))
                ],
            ftBlock =
              Map.fromList
                [ ("word-table", FunctionBlockCommand [FPString] True (\vs bs sp -> Right (Block sp Nothing (Paragraph Nothing [Text sp (T.concat [s | VString s <- vs])]) : bs))),
                  ("bad-style", FunctionBlockCommand [] False (\_ _ sp -> Right [Block sp Nothing (Paragraph (Just "nope") [Text sp "x"])])),
                  ("plain", FunctionBlockCommand [] False (\_ _ sp -> Right [Block sp Nothing (Paragraph Nothing [Text sp "x"])]))
                ]
          }
    }

codes :: Text -> [Text]
codes src = map diagCodeText (fst (evalSource fctx src))

paragraphs :: Text -> [[Inline]]
paragraphs src = [is | Paragraph _ is <- resultBodies (evalResult fctx src)]

functionTests :: TestTree
functionTests =
  testGroup
    "commands of functions (docs/adr/0150)"
    [ testCase "[tax-included 1000] is the inline the function returns, at the call" $ do
        codes "[tax-included 1000]\n" @?= []
        paragraphs "[tax-included 1000]\n" @?= [[Text (mkSpan (FileId 1) 0 19) "[1100]"]],
      testCase "the slot reaches the function, and a note in it stays a note" $ do
        codes "[emph-twice: 本文[note: 注]]\n" @?= []
        case paragraphs "[emph-twice: 本文[note: 注]]\n" of
          [[CharStyle _ "strong" [Text _ "本文", Note {}], CharStyle {}]] -> pure ()
          other -> assertFailure (show other),
      testCase "the body of @word-table reaches the function" $
        case resultBodies (evalResult fctx "@word-table words\n  本文\n") of
          [Paragraph Nothing [Text _ "words"], Paragraph Nothing [Text _ "本文"]] -> pure ()
          other -> assertFailure (show other),
      testCase "@label gives the label to the first block the function returns" $
        map blockLabel (resultBlocks (evalResult fctx "@label t\n@word-table words\n")) @?= [Just "t"],
      testCase "a keyword argument is G02119" $
        codes "[tax-included 1000 rate=10]\n" @?= ["G02119"],
      testCase "a wrong number of positional arguments is G02120" $
        codes "[tax-included 1000 2000]\n" @?= ["G02120"],
      testCase "[tax-included abc] is G02121" $
        codes "[tax-included abc]\n" @?= ["G02121"],
      testCase "an integer where Nat is wanted is G02121" $
        codes "[tax-included [= 0 - 1]]\n" @?= ["G02121"],
      testCase "a wrong number of slots is G02122" $
        codes "[emph-twice]\n" @?= ["G02122"],
      testCase "a body to a function that takes none is G02123" $
        codes "@plain\n  本文\n" @?= ["G02123"],
      testCase "none of the errors calls the function" $
        mapM_ (\src -> resultBodies (evalResult fctx src) @?= []) ["@plain\n  本文\n"],
      testCase "a paragraph style the function returns that is not defined is G02047" $
        codes "@bad-style\n" @?= ["G02047"],
      testCase "an unknown command is still G02022, and an unknown block command G02009" $ do
        codes "[nope]\n" @?= ["G02022"]
        codes "@nope\n" @?= ["G02009"]
    ]
