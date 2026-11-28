-- | Explicit number styles preserve the complete semantic IR (golem-parser ADR 0014).
module NumberStyleShorthandSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Ratio ((%))
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
      Tcy _ content -> Tcy zero content
      Text _ t -> Text zero t
      other -> other

observed :: EvalContext -> Text -> (Document, [Diagnostic])
observed ctx source = let (ds, result) = evalSource ctx source in (normalDocument (erDocument result), map normalizeDiagnostic ds)
  where
    zero = mkSpan (FileId 0) 0 0
    locations = map (\(_, text) -> (zero, text))
    normalizeDiagnostic d = d {diagSpan = zero, diagRelated = locations (diagRelated d), diagFixes = [f {fixEdits = locations (fixEdits f)} | f <- diagFixes d]}

pair :: EvalContext -> Text -> Text -> Assertion
pair ctx n style = observed ctx ("##" <> n <> ":" <> style <> "##\n") @?= observed ctx ("[number-text " <> n <> " style=" <> style <> "]\n")

tests :: TestTree
tests =
  testGroup
    "golem-parser ADR 0014"
    [ unifiedTcyTests,
      rationalNumberTests,
      testGroup
        "explicit number shorthand styles"
        [ testCase ("golem-parser ADR 0014 I2: complete Number IR in " <> T.unpack direction <> " for " <> T.unpack style) $ do
            let parsed = either (error . show) id (parseStyle (FileId 9) ("[page]\nsize = \"A5\"\nwriting-mode = \"" <> direction <> "\"\n"))
                ctx = baseCtx {ctxStyle = parsed}
            mapM_ (\n -> pair ctx n style) ["0", "1", "17", "2027", "9223372036854775807"]
            let (_, ds) = evalSource ctx ("##17:" <> style <> "##\n")
            case resultBodies ds of
              [Paragraph Nothing [Number _ 17 (Just _)]] | style /= "tcy" -> pure ()
              [Paragraph Nothing [Tcy _ (TcyNumber 17)]] | style == "tcy" -> pure ()
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

rationalNumberTests :: TestTree
rationalNumberTests =
  testGroup
    "root ADR 0478"
    [ testGroup
        "I1 I2 exact rational values"
        [ testCase (T.unpack source) $ do
            let (ds, r) = evalSource baseCtx (source <> "\n")
            map diagCodeText ds @?= []
            case resultBodies r of
              [Paragraph Nothing [Number _ n _]] -> toRational n @?= expected
              [Paragraph Nothing [Tcy _ (TcyNumber n)]] -> n @?= expected
              other -> assertFailure (show other)
        | (source, expected) <- [("##0.1##", 1 % 10), ("##0.10:tcy##", 1 % 10), ("##1.0##", 1), ("##0.00##", 0), ("[number-text -0.25]", (-1) % 4), ("[number-text [= 1/3]]", 1 % 3), ("[number-text 1e-1]", 1 % 10), ("[number-text [= 1/1]]", 1), ("[number-text [= 1/9223372036854775807]]", 1 % 9223372036854775807), ("[number-text [= 2/(2 ** 64 - 2)]]", 1 % 9223372036854775807), ("[number-text -9223372036854775808]", -9223372036854775808), ("[number-text 9223372036854775807]", 9223372036854775807)]
        ],
      testCase "root ADR 0478 I1: complete IR and style equality" $
        mapM_ (\n -> mapM_ (pair baseCtx n) ["kanji", "kanji-digits", "tcy", "unknown"]) ["0.1", "0.10", "1.0", "0.00"],
      testCase "root ADR 0478 I2: equivalent decimals normalize before IR" $
        observed baseCtx "##0.10##\n" @?= observed baseCtx "##0.1##\n",
      testCase "root ADR 0478 I1: overriding plugin receives the same original numeric type" $ do
        let output = PluginCommand (\args _ sp -> Right ([Text sp (T.pack (show args))], []))
            ctx = baseCtx {ctxPlugins = noPlugins {phOverrides = Map.singleton BNumberText output}}
        mapM_ (\n -> pair ctx n "custom") ["0.1", "1.0", "12"],
      testCase "root ADR 0478 I5: rejected values preserve diagnostic priority" $
        mapM_
          (\(source, code) -> map diagCodeText (fst (evalSource baseCtx (source <> "\n"))) @?= [code])
          [("[number-text \"0.1\"]", "G02019"), ("[number-text [= 1...3]]", "G02113"), ("[number-text 1e1301]", "G02086"), ("[number-text [= 1/(2 ** 63)]]", "G02091"), ("[number-text 9223372036854775808]", "G02091"), ("##1.2.3##", "G02078"), ("##1.##", "G02078"), ("##00.1##", "G02078")],
      testCase "root ADR 0478 I7: decimal shorthand stays literal in code" $ do
        let ctx = baseCtx {ctxCharStyles = Set.singleton "code"}
        case resultBodies (evalResult ctx "[code: ##0.10:tcy##]\n") of
          [Paragraph Nothing [CharStyle _ "code" [Text _ t]]] -> t @?= "##0.10:tcy##"
          other -> assertFailure (show other)
    ]

unifiedTcyTests :: TestTree
unifiedTcyTests =
  testGroup
    "root ADR 0479"
    [ testCase "root ADR 0479 I3: explicit numeric TCY uses the common Tcy node" $
        mapM_
          ( \source -> case resultBodies (evalResult baseCtx (source <> "\n")) of
              [Paragraph Nothing [Tcy {}]] -> pure ()
              other -> assertFailure (show other)
          )
          ["[number-text 1 style=tcy]", "##1:tcy##", "##0.10:tcy##"],
      testCase "root ADR 0479 I3: an implicit number remains Number until output" $
        case resultBodies (evalResult baseCtx "##1##\n") of
          [Paragraph Nothing [Number _ 1 Nothing]] -> pure ()
          other -> assertFailure (show other)
    ]
