-- | Paragraph boundaries and body binding are independent of styles (root ADR 0473).
module ParagraphBlocksSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR
import Golem.Eval.File
import Golem.Eval.Functions
import Golem.Parser (parseAst)
import Golem.Parser.AST qualified as A
import Golem.Parser.SourceSettings
import Golem.Project.Style (LineBreaks (..), noLocalStyles, paraLineBreaks, parseStyle)
import Golem.Syntax
import Support
import Test.Tasty
import Test.Tasty.HUnit

ctx :: EvalContext
ctx = baseCtx {ctxSource = SourceSettings LineSeparated, ctxParaStyles = Map.singleton "body" JoinLines}

blocks :: EvalContext -> Text -> [Block]
blocks c = resultBlocks . evalResult c

codes :: EvalContext -> Text -> [Text]
codes c = map diagCodeText . fst . evalSource c

styles :: EvalContext -> Text -> [Maybe StyleRef]
styles c source = [st | b <- blocks c source, Paragraph st _ <- [blockBody b]]

texts :: [Block] -> [Text]
texts bs = [T.concat [t | Text _ t <- is] | Block _ _ _ (Paragraph _ is) <- bs]

-- A body-preserving command records the number of distinct blocks received.
capture :: [Block] -> [Block]
capture bs = [b {blockLabel = Just (T.pack (show (length bs)))} | b <- bs]

functions :: FunctionTable
functions = FunctionTable (Map.singleton "functions/sample.emet" namespace) False Set.empty
  where
    namespace =
      FunctionNamespace
        Map.empty
        ( Map.fromList
            [ ("capture", BlockFunction noParams True "" (\_ bs _ -> Right (capture bs))),
              ("pair", BlockFunction noParams False "" (\_ _ sp -> Right [Block sp Nothing Nothing (Paragraph Nothing [Text sp t]) | t <- ["Generated alpha", "Generated beta"]])),
              ("empty", BlockFunction noParams False "" (\_ _ _ -> Right [])),
              ("heading", BlockFunction noParams False "" (\_ _ site -> Right [Block site Nothing Nothing (Heading 1 noHeadingAttrs [Text site "Generated heading"])])),
              ("lead", BlockFunction noParams False "" (\_ _ site -> Right [Block site Nothing Nothing (Paragraph (Just "lead") [Text site "Generated lead"])]))
            ]
        )
        Map.empty
        Map.empty

withFunctions :: Text -> Text
withFunctions = ("@import functions/sample.emet * as sample\n\n" <>)

tests :: TestTree
tests =
  testGroup
    "root ADR 0473 paragraphs"
    [ testCase "root ADR 0473 I1, I2: pre-binding normalization preserves four paragraph spans" $ do
        let source = "@style body align=center\nAlpha\nBeta\n@style body align=center\nGamma\nDelta\n"
            (A.File _ raw, _, _) = parseAst (FileId 1) source
            normalized = paragraphBlocks (SourceSettings LineSeparated) raw
            paragraphOf (A.Located _ (A.Attributed _ (Just target))) = paragraphOf target
            paragraphOf (A.Located sp (A.Paragraph is)) = Just (sp, is)
            paragraphOf _ = Nothing
            actual = [sp | Just (sp, _) <- map paragraphOf normalized]
            at word = let start = T.length (fst (T.breakOn word source)) in mkSpan (FileId 1) start (start + T.length word)
        actual @?= map at ["Alpha", "Beta", "Gamma", "Delta"]
        length normalized @?= 4,
      testCase "root ADR 0473 I3: pre-binding normalization keeps the fence and splits its paragraphs" $ do
        let (A.File _ raw, _, _) = parseAst (FileId 1) "@style body\n:::\nAlpha\nBeta\n:::\n"
        case paragraphBlocks (SourceSettings LineSeparated) raw of
          [A.Located _ (A.Attributed _ (Just (A.Located _ (A.Fenced True [A.Located _ A.Paragraph {}, A.Located _ A.Paragraph {}]))))] -> pure ()
          other -> assertFailure (show other),
      testCase "root ADR 0473 I5: a fence count never evaluates its plugin twice" $ do
        let hook = noPlugins {phBlocks = Map.singleton "once" (PluginBlockCommand (\_ _ sp -> Right ([Block sp Nothing Nothing (Paragraph Nothing [Text sp "Generated"])], Map.empty, [notice "G02062" sp "callback probe"])))}
            c = ctx {ctxPlugins = hook}
            (ds, r) = evalSource c "@style body\n:::\n@once\n\n:::\n"
        length [() | d <- ds, diagMessage d == "callback probe"] @?= 1
        map diagCodeText ds @?= ["G02062", "G01031"]
        texts (resultBlocks r) @?= ["Generated"],
      testCase "root ADR 0473 I1, I2: four source paragraphs bind only the first and third to style" $ do
        let source = "@style body align=center\nAlpha.\nBeta.\n@style body align=center\nGamma.\nDelta.\n"
            ss = styles ctx source
        length ss @?= 4
        map (fmap styleRefName) ss @?= [Just "body", Nothing, Just "body", Nothing]
        texts (blocks ctx source) @?= ["Alpha.", "Beta.", "Gamma.", "Delta."],
      testCase "root ADR 0473 I1, I2: keep does not merge separate line-mode paragraphs" $ do
        let bs = blocks ctx "@style body line-breaks=keep\nAlpha.\nBeta.\nGamma.\n"
        texts bs @?= ["Alpha.", "Beta.", "Gamma."]
        length bs @?= 3,
      testCase "root ADR 0473 I1: a hard break stays inside one paragraph with its source positions" $ do
        let bs = blocks ctx "Alpha\\\nBeta\nGamma\n"
        case bs of
          [Block a _ _ (Paragraph _ [Text _ "Alpha", LineBreak _, Text _ "Beta"]), Block b _ _ (Paragraph _ [Text _ "Gamma"])] -> do
            (spanStart a, spanEnd a) @?= (0, 11)
            (spanStart b, spanEnd b) @?= (12, 17)
          other -> assertFailure (show other),
      testCase "root ADR 0473 I2: blank-line keep retains the internal ordinary newline" $ do
        let blank = ctx {ctxSource = SourceSettings BlankLineSeparated}
        case map blockBody (blocks blank "@style body line-breaks=keep\nAlpha\nBeta\n") of
          [Paragraph _ [Text _ "Alpha", LineBreak _, Text _ "Beta"]] -> pure ()
          other -> assertFailure (show other),
      testCase "root ADR 0473 I3, I5: a fenced pair contains two blocks and no redundant-fence info" $ do
        let source = "@style body align=center\n:::\nAlpha\nBeta\n:::\n"
        texts (blocks ctx source) @?= ["Alpha", "Beta"]
        codes ctx source @?= [],
      testCase "root ADR 0473 I4: an indented pair is one G02290 and puts out no styled blocks" $ do
        let source = "@style body align=center\n  Alpha\n  Beta\n"
        codes ctx source @?= ["G02290"]
        blocks ctx source @?= [],
      testCase "root ADR 0473 I4: blank-separated indented paragraphs also require a fence" $ do
        let blank = ctx {ctxSource = SourceSettings BlankLineSeparated}
        codes blank "@style body\n  Alpha\n\n  Beta\n" @?= ["G02290"],
      testCase "root ADR 0473 I4: one indented paragraph remains accepted" $
        codes ctx "@style body align=center\n  Alpha\n" @?= [],
      testCase "root ADR 0473 I4: a generated pair cannot become an implicit body" $ do
        let c = ctx {ctxFunctions = functions}
        codes c (withFunctions "@style body\n@sample.pair\n") @?= ["G02290"],
      testCase "root ADR 0473 I3, I5: a generated pair in a fence remains two blocks without G01031" $ do
        let c = ctx {ctxFunctions = functions}
            source = withFunctions "@style body\n:::\n@sample.pair\n\n:::\n"
        texts (blocks c source) @?= ["Generated alpha", "Generated beta"]
        codes c source @?= [],
      testCase "root ADR 0473 I4: an empty generated body preserves the existing empty-style error" $ do
        let c = ctx {ctxFunctions = functions}
        codes c (withFunctions "@style body\n@sample.empty\n") @?= ["G02046"],
      testCase "root ADR 0473 I5: unknown and bodyless commands never get G01031" $ do
        assertBool "unknown has no G01031" ("G01031" `notElem` codes ctx "@not-a-command\n:::\nAlpha\n:::\n")
        codes ctx "@toc\n:::\nAlpha\n:::\n" @?= ["G02123"],
      testCase "root ADR 0473 I5: an unclosed single-block fence gets G01030 alone" $
        mapM_ (\ending -> codes ctx ("@style body\n:::\nAlpha" <> ending) @?= ["G01030"]) ["\n", "\n\n\n", "\n  \n\n"],
      testCase "root ADR 0473 I5: a rejected style never gets redundant-fence info" $
        codes ctx "@style missing\n:::\nAlpha\n:::\n" @?= ["G02047"],
      testCase "root ADR 0473 I5: a single accepted paragraph gets G01031 once" $
        codes ctx "@style body\n:::\nAlpha\n:::\n" @?= ["G01031"],
      testCase "root ADR 0473 I1: an Emet body contains only its next normalized paragraph" $ do
        let c = ctx {ctxFunctions = functions}
            bs = blocks c (withFunctions "@sample.capture\nAlpha\nBeta\n")
        map blockLabel bs @?= [Just "1", Nothing]
        texts bs @?= ["Alpha", "Beta"],
      testCase "root ADR 0473 I1: a plugin body contains only its next normalized paragraph" $ do
        let hook = noPlugins {phBlocks = Map.singleton "capture" (PluginBlockCommand (\_ received _ -> Right (capture received, Map.empty, [])))}
            bs = blocks ctx {ctxPlugins = hook} "@capture\nAlpha\nBeta\n"
        map blockLabel bs @?= [Just "1", Nothing]
        texts bs @?= ["Alpha", "Beta"],
      testCase "root ADR 0473 I6: a generated non-paragraph resets next-style before the next source paragraph" $ do
        let style = either (error . show) id (parseStyle (FileId 9) "[paragraph-styles.lead]\nnext-style=\"after\"\n[paragraph-styles.after]\n")
            c = ctx {ctxStyle = style, ctxFunctions = functions, ctxParaStyles = Map.fromList [("body", JoinLines), ("lead", JoinLines), ("after", JoinLines)]}
        map (fmap styleRefName) (styles c (withFunctions "@style lead\nAlpha\n@sample.heading\nBeta\n")) @?= [Just "lead", Nothing],
      testCase "root ADR 0473 I6: a generated paragraph supplies next-style to the next source paragraph" $ do
        let style = either (error . show) id (parseStyle (FileId 9) "[paragraph-styles.lead]\nnext-style=\"after\"\n[paragraph-styles.after]\n")
            c = ctx {ctxStyle = style, ctxFunctions = functions, ctxParaStyles = Map.fromList [("body", JoinLines), ("lead", JoinLines), ("after", JoinLines)]}
        map (fmap styleRefName) (styles c (withFunctions "@sample.lead\nBeta\nGamma\n")) @?= [Just "lead", Just "after", Nothing],
      testCase "root ADR 0473 I3, I5: a figure accepts a fenced caption of several paragraphs" $ do
        let c = ctx {ctxAssets = Map.singleton "sample.png" AssetPresent}
            source = "@figure sample.png alt=\"Sample\"\n:::\nCaption alpha\nCaption beta\n:::\n"
        codes c source @?= []
        case map blockBody (blocks c source) of
          [FigureBlock figure] -> texts (figCaption figure) @?= ["Caption alpha", "Caption beta"]
          other -> assertFailure (show other),
      testCase "root ADR 0473 I5: a figure's single fenced caption requires its fence" $ do
        let c = ctx {ctxAssets = Map.singleton "sample.png" AssetPresent}
        codes c "@figure sample.png alt=\"Sample\"\n:::\nCaption alpha\n:::\n" @?= [],
      testCase "root ADR 0473 I3: a figure's empty fenced caption remains empty without G01031" $ do
        let c = ctx {ctxAssets = Map.singleton "sample.png" AssetPresent}
            source = "@figure sample.png alt=\"Sample\"\n:::\n:::\n"
        codes c source @?= []
        case map blockBody (blocks c source) of
          [FigureBlock figure] -> figCaption figure @?= []
          other -> assertFailure (show other),
      testCase "root ADR 0473 I2: a figure still does not consume the implicit following paragraph" $ do
        let c = ctx {ctxAssets = Map.singleton "sample.png" AssetPresent}
            source = "@figure sample.png alt=\"Sample\"\nOrdinary paragraph\n"
        codes c source @?= ["G02011"]
        case map blockBody (blocks c source) of
          [FigureBlock figure, Paragraph Nothing [Text _ "Ordinary paragraph"]] -> figCaption figure @?= []
          other -> assertFailure (show other),
      testCase "root ADR 0468 I2, root ADR 0473 I1 I6: a heading advances styles across normalized line paragraphs" $
        headingNext "# Sample heading\n\nAlpha\nBeta\nGamma\n",
      testCase "root ADR 0468 I2, root ADR 0473 I1 I6: a generated heading supplies the next style to normalized following paragraphs" $
        headingNext (withFunctions "@sample.heading\n\nAlpha\nBeta\nGamma\n"),
      testCase "root ADR 0468 I2, root ADR 0473 I1 I6: an empty generated command preserves a heading's pending style" $
        headingNext (withFunctions "# Sample heading\n\n@sample.empty\n\nAlpha\nBeta\nGamma\n"),
      testCase "root ADR 0473 I6: next-style advances once per separate paragraph" $ do
        let style = either (error . show) id (parseStyle (FileId 9) "[paragraph-styles.lead]\nnext-style=\"after\"\n[paragraph-styles.after]\n")
            c = ctx {ctxStyle = style, ctxLocalStyles = noLocalStyles, ctxParaStyles = Map.fromList [("body", JoinLines), ("lead", JoinLines), ("after", JoinLines)]}
        map (fmap styleRefName) (styles c "@style lead\nAlpha\nBeta\nGamma\n") @?= [Just "lead", Just "after", Nothing]
    ]

-- Heading next-style and paragraph normalization share the same state transition.
headingNext :: Text -> Assertion
headingNext source = do
  let style = either (error . show) id (parseStyle (FileId 9) "[paragraph-styles.h]\nnext-style=\"first\"\n[paragraph-styles.first]\nline-breaks=\"keep\"\nnext-style=\"after\"\n[paragraph-styles.after]\n[headings.1]\nparagraph-style=\"h\"\n")
      c = ctx {ctxStyle = style, ctxFunctions = functions, ctxParaStyles = paraLineBreaks style}
      result = blocks c source
  codes c source @?= []
  map (fmap styleRefName) (styles c source) @?= [Just "first", Just "after", Nothing]
  texts result @?= ["Alpha", "Beta", "Gamma"]
