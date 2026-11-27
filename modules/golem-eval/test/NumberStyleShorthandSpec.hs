-- | Explicit number styles preserve the complete semantic IR (golem-parser ADR 0014).
module NumberStyleShorthandSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR
import Golem.Eval.Builtin (BuiltinInline (..))
import Golem.Eval.File
import Golem.Eval.Functions
import Golem.Eval.Value
import Golem.Project.Style (parseStyle)
import Golem.Syntax
import Support
import Test.Tasty
import Test.Tasty.HUnit

-- Only source locations change: all remaining Document/Block/Inline fields
-- are compared by their derived Eq instances, never a text projection.
normalDocument :: Document -> Document
normalDocument d = d {docBlocks = map block (docBlocks d)}
  where
    zero = mkSpan (FileId 0) 0 0
    block b = b {blockSpan = zero, blockBody = case blockBody b of Paragraph st xs -> Paragraph st (map inline xs); other -> other}
    inline = \case
      Number _ n st -> Number zero n st
      Text _ t -> Text zero t
      other -> other

observed :: EvalContext -> Text -> (Document, [(DiagnosticCode, Severity)])
observed ctx source = let (ds, result) = evalSource ctx source in (normalDocument (erDocument result), [(diagCode d, diagSeverity d) | d <- ds])

pair :: EvalContext -> Text -> Text -> Assertion
pair ctx n style = observed ctx ("##" <> n <> ":" <> style <> "##\n") @?= observed ctx ("[number-text " <> n <> " style=" <> style <> "]\n")

tests :: TestTree
tests =
  testGroup
    "golem-parser ADR 0014"
    [ testGroup
        "explicit number shorthand styles"
        [ testCase ("golem-parser ADR 0014 I2: complete Number IR in " <> T.unpack direction <> " for " <> T.unpack style) $ do
            let parsed = either (error . show) id (parseStyle (FileId 9) ("[page]\nsize = \"A5\"\nwriting-mode = \"" <> direction <> "\"\n"))
                ctx = baseCtx {ctxStyle = parsed}
            mapM_ (\n -> pair ctx n style) ["0", "1", "17", "2027", "9223372036854775807"]
            let (_, ds) = evalSource ctx ("##17:" <> style <> "##\n")
            case resultBodies ds of
              [Paragraph Nothing [Number _ 17 (Just _)]] -> pure ()
              other -> assertFailure (show other)
        | direction <- ["horizontal", "vertical"],
          style <- ["tcy", "kanji", "kanji-digits"]
        ],
      testGroup
        "boundaries and dispatch"
        [ testCase "golem-parser ADR 0014 I1: legacy shorthand remains the complete unstyled Number IR" $ mapM_ (\n -> observed baseCtx ("##" <> n <> "##\n") @?= observed baseCtx ("[number-text " <> n <> "]\n")) ["0", "17", "9223372036854775807"],
          testCase "golem-parser ADR 0014 I2: unknown built-in style uses G02019" $ do
            pair baseCtx "17" "unknown"
            map diagCodeText (fst (evalSource baseCtx "##17:unknown##\n")) @?= ["G02019"],
          testCase "golem-parser ADR 0014 I2: the int64 boundary and the next integer match explicit commands" $ do
            mapM_ (pair baseCtx "9223372036854775808") ["tcy", "kanji", "kanji-digits", "unknown"]
            map diagCodeText (fst (evalSource baseCtx "##9223372036854775808:tcy##\n")) @?= ["G02091"],
          testCase "golem-parser ADR 0014 I2, I6: plugin override receives arbitrary style names verbatim" $ do
            let output = PluginCommand (\args _ sp -> Right ([Text sp (T.pack (show args))], []))
                ctx = baseCtx {ctxPlugins = noPlugins {phOverrides = Map.singleton BNumberText output}}
            mapM_
              ( \st -> do
                  pair ctx "17" st
                  let (_, r) = evalSource ctx ("##17:" <> st <> "##\n")
                  case resultBodies r of
                    [Paragraph Nothing [Text _ t]] -> assertBool "exact style keyword" (("PluginKeyword \"style\" (VString \"" <> st <> "\")") `T.isInfixOf` t)
                    other -> assertFailure (show other)
              )
              ["custom", "a1-b9", "unknown", "a", "z9-"],
          testCase "golem-parser ADR 0014 I2, I6: listed function override receives the new style" $ do
            let f = InlineFunction (Params [ArgNat] Nothing [KeywordParam "style" ArgString (VString "")]) 0 "" (\vs _ sp -> Right [Text sp (T.pack (show vs))])
                ns = FunctionNamespace (Map.singleton "number-text" f) Map.empty Map.empty Map.empty
                ctx = baseCtx {ctxFunctions = FunctionTable (Map.singleton "functions/sample.emet" ns) False Set.empty}
                prefix = "@import functions/sample.emet { number-text }\n\n"
            observed ctx (prefix <> "##17:custom##\n") @?= observed ctx (prefix <> "[number-text 17 style=custom]\n")
            map diagCodeText (fst (evalSource ctx (prefix <> "##17:custom##\n"))) @?= [],
          testCase "golem-parser ADR 0014 I4: malformed syntax has one diagnostic and no output" $
            mapM_
              ( \src -> do
                  let (ds, r) = evalSource baseCtx (src <> "\n")
                  map diagCodeText ds @?= ["G02078"]
                  map (\d -> (spanStart (diagSpan d), spanEnd (diagSpan d))) ds @?= [(0, T.length src)]
                  resultBodies r @?= [Paragraph Nothing []]
              )
              ["##01:tcy##", "##1:##", "##1::tcy##", "##1: tcy##", "##1 :tcy##", "##1:TCY##", "##1:-tcy##", "##1:1tcy##", "##1:tcy_##", "##1:tcy"],
          testCase "golem-parser ADR 0014 I3: code and escaped shorthand retain the literal text" $ do
            let ctx = baseCtx {ctxCharStyles = Set.singleton "code"}
            mapM_ (\src -> map diagCodeText (fst (evalSource ctx src)) @?= []) ["[code: ##17:tcy##]\n", "[style code: ##17:unknown##]\n", "\\##17:tcy##\n"]
            mapM_
              ( \(source, expected) -> case resultBodies (evalResult ctx source) of
                  [Paragraph Nothing [CharStyle _ "code" [Text _ actual]]] -> actual @?= expected
                  other -> assertFailure (show other)
              )
              [("[code: ##17:tcy##]\n", "##17:tcy##"), ("[style code: ##17:unknown##]\n", "##17:unknown##")]
            case resultBodies (evalResult ctx "\\##17:tcy##\n") of
              [Paragraph Nothing [Text _ actual]] -> actual @?= "##17:tcy##"
              other -> assertFailure (show other)
        ]
    ]
