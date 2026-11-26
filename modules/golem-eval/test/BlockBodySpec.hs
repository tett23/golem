{- | The body of a block command written without indentation (root ADR
0459): the block commands written in a row read as one command, the next
block and the blocks between ::: lines as the body; and the body of
@style holding any blocks (root ADR 0460).
-}
module BlockBodySpec (tests) where

import Data.List (isInfixOf)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR
import Golem.Eval.File
import Golem.Eval.Functions
import Golem.Eval.Value
import Golem.Parser.SourceSettings (ParagraphSeparator (..), SourceSettings (..))
import Golem.Project.Style (LineBreaks (..))
import Golem.Syntax
import Support
import Test.Tasty
import Test.Tasty.HUnit

{- | functions/s.emet: stage-direction takes a body and puts out a
paragraph SD before it; stamp takes none and puts out a paragraph ST.
-}
stage :: FunctionNamespace
stage =
  FunctionNamespace
    { fnInline = Map.empty,
      fnBlock =
        Map.fromList
          [ ("stage-direction", BlockFunction noParams True "" (\_ body sp -> Right (Block sp Nothing Nothing (Paragraph Nothing [Text sp "SD"]) : body))),
            ("stamp", BlockFunction noParams False "" (\_ _ sp -> Right [Block sp Nothing Nothing (Paragraph Nothing [Text sp "ST"])])),
            -- an override of @toc that takes a body (root ADR 0453)
            ("toc", BlockFunction noParams True "" (\_ body sp -> Right (Block sp Nothing Nothing (Paragraph Nothing [Text sp "TOC"]) : body)))
          ],
      fnExpr = Map.empty,
      fnOthers = Map.empty
    }

-- | A plugin block command box, which puts out a paragraph BOX before its body.
boxPlugin :: PluginHook
boxPlugin = noPlugins {phBlocks = Map.fromList [("box", PluginBlockCommand (\_ body sp -> Right (Block sp Nothing Nothing (Paragraph Nothing [Text sp "BOX"]) : body, Map.empty, [])))]}

ctx :: EvalContext
ctx =
  baseCtx
    { ctxFunctions = FunctionTable (Map.fromList [("functions/s.emet", stage)]) False Set.empty,
      ctxParaStyles = Map.fromList [("body", JoinLines), ("quote", JoinLines), ("aside", JoinLines), ("v", KeepLines), ("t", JoinLines), ("table", JoinLines)],
      ctxPlugins = boxPlugin,
      ctxAssets = Map.fromList [("data.csv", AssetText (FileId 7) "a,b\n1,2\n"), ("x.png", AssetPresent)]
    }

-- | The same with the paragraphs separated by lines.
lineCtx :: EvalContext
lineCtx = ctx {ctxSource = SourceSettings LineSeparated}

-- | A .emet that could not be loaded.
unloadedCtx :: EvalContext
unloadedCtx = ctx {ctxFunctions = FunctionTable Map.empty True Set.empty}

-- | The source with the functions listed and namespaced.
src :: Text -> Text
src body = "@import functions/s.emet { stage-direction, stamp }\n@import functions/s.emet * as s\n\n" <> body

-- | The output without the source positions.
ir :: EvalContext -> Text -> String
ir c s = eraseSpans (show (resultBodies (evalResult c (src s))))

codes :: EvalContext -> Text -> [Text]
codes c s = map diagCodeText (fst (evalSource c (src s)))

-- | The output and the diagnostic codes.
both :: EvalContext -> Text -> (String, [Text])
both c s = (ir c s, codes c s)

eraseSpans :: String -> String
eraseSpans input = case input of
  _ | Just rest <- dropPrefix "SrcSpan {" input -> eraseSpans (drop 1 (dropWhile (/= '}') rest))
  (c : rest) -> c : eraseSpans rest
  [] -> []
  where
    dropPrefix p s = if take (length p) s == p then Just (drop (length p) s) else Nothing

-- | The paragraphs at any depth with their styles and texts.
paragraphs :: EvalContext -> Text -> [(Maybe StyleRef, Text)]
paragraphs c s = concatMap go (resultBodies (evalResult c (src s)))
  where
    go = \case
      Paragraph st is -> [(st, T.concat [t | Text _ t <- is])]
      BulletList items -> concatMap (concatMap (go . blockBody) . itemBlocks) items
      OrderedList items -> concatMap (concatMap (go . blockBody) . itemBlocks) items
      DefList gs -> concatMap (concatMap (concatMap (go . blockBody)) . dgDefs) gs
      _ -> []

-- | Whether some paragraph at any depth holds a line break.
keepsLines :: EvalContext -> Text -> Bool
keepsLines c s = "LineBreak" `isInfixOf` ir c s

tests :: TestTree
tests = testGroup "block bodies (root ADR 0459, root ADR 0460, root ADR 0462)" [bodyTests, styleTests, breakTests]

bodyTests :: TestTree
bodyTests =
  testGroup
    "the body without indentation (root ADR 0459)"
    [ testCase "root ADR 0459 I1: a listed @stage-direction takes the next paragraph as its body" $ do
        both ctx "@stage-direction\n段落\n" @?= both ctx "@stage-direction\n  段落\n"
        assertBool "no G02011" ("G02011" `notElem` codes ctx "@stage-direction\n段落\n")
        paragraphs ctx "@stage-direction\n段落\n" @?= [(Nothing, "SD"), (Nothing, "段落")],
      testCase "root ADR 0459 I1: a namespaced @s.stage-direction takes the next paragraph" $
        both ctx "@s.stage-direction\n段落\n" @?= both ctx "@s.stage-direction\n  段落\n",
      testCase "root ADR 0459 I1: a block command of a plugin takes the next paragraph" $ do
        both ctx "@box\n段落\n" @?= both ctx "@box\n  段落\n"
        paragraphs ctx "@box\n段落\n" @?= [(Nothing, "BOX"), (Nothing, "段落")],
      testCase "root ADR 0459 I1: @note takes the next paragraph as the text of the note" $ do
        both ctx "本文[note n]\n\n@note n\n注の本文\n" @?= both ctx "本文[note n]\n\n@note n\n  注の本文\n"
        codes ctx "本文[note n]\n\n@note n\n注の本文\n" @?= [],
      testCase "root ADR 0459 I1: a bullet list and a heading are bodies" $ do
        both ctx "@stage-direction\n- 一\n- 二\n" @?= both ctx "@stage-direction\n  - 一\n  - 二\n"
        both ctx "@stage-direction\n# 見出し\n" @?= both ctx "@stage-direction\n  # 見出し\n",
      testCase "root ADR 0459 I1: one paragraph between ::: lines is the body, with G01031" $ do
        ir ctx "@stage-direction\n:::\n段落\n:::\n" @?= ir ctx "@stage-direction\n  段落\n"
        codes ctx "@stage-direction\n:::\n段落\n:::\n" @?= ["G01031"],
      testCase "root ADR 0459 I1: @page-break goes before the command that takes the paragraph" $ do
        both ctx "@stage-direction\n@page-break\n段落\n" @?= both ctx "@page-break\n\n@stage-direction\n  段落\n",
      testCase "root ADR 0459 I1: an @toc listed over the built-in one takes the paragraph" $ do
        let s = "@import functions/s.emet { toc }\n\n@toc\n段落\n"
        both ctx s @?= both ctx "@import functions/s.emet { toc }\n\n@toc\n  段落\n"
        paragraphs ctx s @?= [(Nothing, "TOC"), (Nothing, "段落")],
      testCase "root ADR 0459 I1: a paragraph right after an indented body is a block of its own" $ do
        both ctx "@stage-direction\n  一\n二\n" @?= both ctx "@stage-direction\n  一\n\n二\n",
      testCase "root ADR 0459 I1: @style quote and a paragraph of two lines in the line style" $ do
        both lineCtx "@style quote\n一行目\n二行目\n" @?= both lineCtx "@style quote\n  一行目\n  二行目\n"
        paragraphs lineCtx "@style quote\n一行目\n二行目\n" @?= [(Just "quote", "一行目"), (Just "quote", "二行目")],
      testCase "root ADR 0459 I2: @style and @lang in either order both apply" $ do
        let one s = [(blockLang b, blockBody b) | b <- resultBlocks (evalResult ctx (src s))]
        map fst (one "@style quote\n@lang en\n段落\n") @?= [Just "en"]
        paragraphs ctx "@style quote\n@lang en\n段落\n" @?= [(Just "quote", "段落")]
        map fst (one "@lang en\n@style quote\n段落\n") @?= [Just "en"]
        paragraphs ctx "@lang en\n@style quote\n段落\n" @?= [(Just "quote", "段落")]
        codes ctx "@style quote\n@lang en\n段落\n" @?= [],
      testCase "root ADR 0459 I2: commands in a row are the commands nested in their bodies" $ do
        both ctx "@style quote\n@stage-direction\n段落\n" @?= both ctx "@style quote\n  @stage-direction\n    段落\n"
        paragraphs ctx "@style quote\n@stage-direction\n段落\n" @?= [(Just "quote", "SD"), (Just "quote", "段落")]
        both ctx "@stage-direction\n@box\n段落\n" @?= both ctx "@stage-direction\n  @box\n    段落\n",
      testCase "root ADR 0459 I2: an attribute goes to the first block of the result" $ do
        let lbls s = map blockLabel (resultBlocks (evalResult ctx (src s)))
        lbls "@label x\n@stage-direction\n段落\n" @?= [Just "x", Nothing]
        codes ctx "@label x\n@stage-direction\n段落\n" @?= [],
      testCase "root ADR 0459 I2: an attribute or @style outside @note is G02013" $ do
        codes ctx "本文[note n]\n\n@label x\n@note n\n段落\n" @?= ["G02013"]
        codes ctx "本文[note n]\n\n@style quote\n@note n\n段落\n" @?= ["G02013"]
        both ctx "本文[note n]\n\n@label x\n@note n\n段落\n" @?= (ir ctx "本文[note n]\n\n@note n\n  段落\n", ["G02013"]),
      testCase "root ADR 0459 I3: blocks between ::: lines read as an indented body" $ do
        let fenced = "@stage-direction\n:::\n一\n\n二\n\n# 見出し\n:::\n\n後\n"
            indented = "@stage-direction\n  一\n\n  二\n\n  # 見出し\n\n後\n"
        both ctx fenced @?= both ctx indented,
      testCase "root ADR 0459 I3: ::: right after a paragraph closes it" $
        both ctx "@stage-direction\n:::\n一\n\n二\n:::\n後\n" @?= both ctx "@stage-direction\n  一\n\n  二\n\n後\n",
      testCase "root ADR 0459 I3: ::: in a code block is code" $ do
        let fenced = "@stage-direction\n:::\n```\n:::\n```\n\n二\n:::\n"
        both ctx fenced @?= both ctx "@stage-direction\n  ```\n  :::\n  ```\n\n  二\n",
      testCase "root ADR 0459 I3: a blank line before ::: after @figure closes the body" $
        both ctx "@stage-direction\n:::\n一\n\n@figure x.png\n\n:::\n" @?= both ctx "@stage-direction\n  一\n\n  @figure x.png\n",
      testCase "root ADR 0459 I3: a nested @note between ::: lines ends at its own close" $ do
        let fenced = "本文[note n]\n\n@stage-direction\n:::\n@note n\n:::\n注一\n\n注二\n:::\n\n一\n:::\n"
            indented = "本文[note n]\n\n@stage-direction\n  @note n\n    注一\n\n    注二\n\n  一\n"
        both ctx fenced @?= both ctx indented,
      testCase "root ADR 0459 I4: an unclosed ::: is G01030 and the body runs to the end" $ do
        codes ctx "@stage-direction\n:::\n一\n\n二\n" @?= ["G01030"]
        ir ctx "@stage-direction\n:::\n一\n\n二\n" @?= ir ctx "@stage-direction\n  一\n\n  二\n",
      testCase "root ADR 0459 I4: ::: right after @figure opens a nested body" $ do
        let cs = codes ctx "@stage-direction\n:::\n一\n\n@figure x.png\n:::\n"
        (length (filter (== "G01030") cs), length (filter (== "G02123") cs)) @?= (2, 1),
      testCase "root ADR 0459 I5: the outputs of the attribute form stay" $ do
        -- a table takes the paragraph style for its cells
        [tableStyle t | TableBlock t <- resultBodies (evalResult ctx (src "@style quote\n| a | b |\n| - | - |\n| 1 | 2 |\n"))] @?= [Just "quote"]
        -- @toc and a heading take the language
        [blockLang b | b <- resultBlocks (evalResult ctx (src "@lang en\n@toc\n"))] @?= [Just "en"]
        [blockLang b | b <- resultBlocks (evalResult ctx (src "@lang en\n# 見出し\n"))] @?= [Just "en"]
        codes ctx "@lang en\n@toc\n" @?= []
        codes ctx "@style quote\n@style aside\n段落\n" @?= ["G02012"]
        -- the source starts with two @import lines in a row
        codes ctx "@set a = 1\n@set b = 2\n" @?= []
        codes ctx "@set a = 1\n@toc\n" @?= []
        codes ctx "@label x\n段落\n" @?= []
        [blockLabel b | b <- resultBlocks (evalResult ctx (src "@label x\n段落\n"))] @?= [Just "x"],
      testCase "root ADR 0459 I5: a style that keeps its lines keeps them with @lang and @label" $ do
        assertBool "@lang" (keepsLines ctx "@style v\n@lang en\n一\n二\n")
        assertBool "@label" (keepsLines ctx "@style v\n@label x\n一\n二\n")
        paragraphs ctx "@style v\n@label x\n一\n二\n" @?= [(Just "v", "一二")]
        [blockLabel b | b <- resultBlocks (evalResult ctx (src "@style v\n@label x\n一\n二\n"))] @?= [Just "x"],
      testCase "root ADR 0459 I5: a block function that takes no body keeps G02011" $ do
        assertBool "G02011" ("G02011" `elem` codes ctx "@stamp\n段落\n")
        paragraphs ctx "@stamp\n段落\n" @?= [(Nothing, "ST"), (Nothing, "段落")],
      testCase "root ADR 0459 I5: ::: in the text of a paragraph stays text" $ do
        paragraphs ctx "本文\n:::\n続き\n" @?= [(Nothing, "本文:::続き")]
        paragraphs ctx "@label x\n本文\n:::\n" @?= [(Nothing, "本文:::")]
        paragraphs ctx "@label x\n\\:::\n" @?= [(Nothing, ":::")],
      testCase "root ADR 0459 I5, root ADR 0461 I5: a function of a .emet that could not be loaded puts out nothing, the paragraph stays, and G02011 as after @index" $ do
        let s = "@import functions/s.emet { stage-direction }\n\n@stage-direction\n段落\n"
            (ds, r) = evalSource unloadedCtx s
        map diagCodeText ds @?= ["G02011", "G02279"]
        filter (== "G02011") (codes ctx "@index\n段落\n") @?= ["G02011"]
        [T.concat [t | Text _ t <- is] | Paragraph _ is <- resultBodies r] @?= ["段落"],
      testCase "root ADR 0459 I6: @set before a command that takes the body is no G02011" $ do
        codes ctx "@set a = 1\n@stage-direction\n段落\n" @?= []
        paragraphs ctx "@set a = 1\n@stage-direction\n段落\n" @?= [(Nothing, "SD"), (Nothing, "段落")],
      testCase "root ADR 0459 I6: ::: after a command that takes no body is G02123" $ do
        codes ctx "@page-break\n:::\n一\n\n二\n:::\n" @?= ["G02123"]
        paragraphs ctx "@page-break\n:::\n一\n\n二\n:::\n" @?= [(Nothing, "一"), (Nothing, "二")]
        codes ctx "@toc\n:::\n一\n\n二\n:::\n" @?= ["G02123"],
      testCase "root ADR 0459 I6: an attribute outside @toc that is not innermost is G02011 once" $ do
        codes ctx "@label x\n@toc\n@stage-direction\n段落\n" @?= ["G02011"]
        case resultBodies (evalResult ctx (src "@label x\n@toc\n@stage-direction\n段落\n")) of
          (ChannelOutput (TocOutput _) : _) -> pure ()
          other -> assertFailure (show other)
    ]

styleTests :: TestTree
styleTests =
  testGroup
    "the blocks of the body of @style (root ADR 0460)"
    [ testCase "root ADR 0460 I1: a body of two paragraphs" $ do
        paragraphs ctx "@style quote\n  一\n\n  二\n" @?= [(Just "quote", "一"), (Just "quote", "二")]
        codes ctx "@style quote\n  一\n\n  二\n" @?= [],
      testCase "root ADR 0460 I2: the paragraphs of a bullet list, nested too, and of a definition list" $ do
        paragraphs ctx "@style quote\n  - 一\n    - 二\n" @?= [(Just "quote", "一"), (Just "quote", "二")]
        unstyled (ir ctx "@style quote\n  - 一\n    - 二\n") @?= ir ctx "- 一\n  - 二\n"
        paragraphs ctx "@style quote\n  = 語\n    定義\n" @?= [(Just "quote", "定義")]
        unstyled (ir ctx "@style quote\n  = 語\n    定義\n") @?= ir ctx "= 語\n  定義\n"
        codes ctx "@style quote\n  - 一\n" @?= [],
      testCase "root ADR 0460 I2, I3: a paragraph and a code block" $ do
        paragraphs ctx "@style quote\n  一\n\n  ```\n  x\n  ```\n" @?= [(Just "quote", "一")]
        unstyled (ir ctx "@style quote\n  一\n\n  ```\n  x\n  ```\n") @?= ir ctx "一\n\n```\nx\n```\n",
      testCase "root ADR 0460 I2: the paragraphs of a block function in the body" $
        paragraphs ctx "@style quote\n  @stage-direction\n    段落\n" @?= [(Just "quote", "SD"), (Just "quote", "段落")],
      testCase "root ADR 0460 I3, I5: a body of a code block only is G02046" $ do
        codes ctx "@style quote\n  ```\n  x\n  ```\n" @?= ["G02046"]
        ir ctx "@style quote\n  ```\n  x\n  ```\n" @?= ir ctx "```\nx\n```\n",
      testCase "root ADR 0460 I3: a heading is put out as it is" $
        ir ctx "@style quote\n  # 見出し\n\n  一\n" @?= unstyledHeading,
      testCase "root ADR 0460 I4: G02045 is not reported" $
        mapM_
          (\s -> assertBool (T.unpack s) ("G02045" `notElem` codes ctx s))
          ["@style quote\n  - 一\n", "@style quote\n  ```\n  x\n  ```\n", "@style quote\n  | a |\n  | - |\n", "@style quote\n  ---\n"],
      testCase "root ADR 0460 I6: a paragraph of an inner @style keeps its style" $ do
        paragraphs ctx "@style quote\n  @style t\n    一\n\n  二\n" @?= [(Just "t", "一"), (Just "quote", "二")]
        codes ctx "@style quote\n  @style t\n    一\n" @?= []
        paragraphs ctx "@style quote\n  @style t\n    一\n" @?= [(Just "t", "一")],
      testCase "root ADR 0460 I7: a table, @table and @printings as with the attribute" $ do
        [tableStyle t | TableBlock t <- resultBodies (evalResult ctx (src "@style quote\n  | a |\n  | - |\n  | 1 |\n"))] @?= [Just "quote"]
        [tableStyle t | TableBlock t <- resultBodies (evalResult ctx (src "@style quote\n  @table data.csv\n"))] @?= [Just "quote"]
        [tableStyle t | TableBlock t <- resultBodies (evalResult ctx (src "@style quote\n@table data.csv\n"))] @?= [Just "quote"]
        let pc = ctx {ctxMeta = Map.fromList [("language", VString "ja"), ("printings", VArray [VHash (Map.fromList [("edition", VInt 1), ("number", VInt 1), ("year", VInt 2026), ("month", VInt 10), ("day", VInt 16), ("date", VString "2026-10-16")])])]}
        map fst (paragraphs pc "@style quote\n  @printings\n") @?= [Just "quote"]
        codes pc "@style quote\n  @printings\n" @?= [],
      testCase "root ADR 0460 I8: a style that keeps its lines keeps those of a bullet list and of @lang" $ do
        assertBool "a bullet list" (keepsLines ctx "@style v\n  - 一\n    二\n")
        assertBool "@lang" (keepsLines ctx "@style v\n  @lang en\n  一\n  二\n"),
      testCase "root ADR 0460 I9: the paragraphs of @frame and @note are not styled" $ do
        unstyled (ir ctx "@style quote\n  @frame side\n    一\n\n  二\n") @?= ir ctx "@frame side\n  一\n\n二\n"
        paragraphs ctx "@style quote\n  @frame side\n    一\n\n  二\n" @?= [(Just "quote", "二")]
        ir ctx "本文[note n]\n\n@style quote\n  @note n\n    注\n\n  二\n" @?= ir ctx "本文[note n]\n\n@note n\n  注\n\n@style quote\n  二\n"
    ]
  where
    unstyled = replace "Paragraph (Just \"quote\")" "Paragraph Nothing"
    unstyledHeading = ir ctx "# 見出し\n\n@style quote\n  一\n"
    replace from to s = T.unpack (T.replace from to (T.pack s))

-- | The bodies at the top of the output.
bodies :: EvalContext -> Text -> [BlockBody]
bodies c s = resultBodies (evalResult c (src s))

-- | A page break, a page control, blank lines or a separator.
isBreakBody :: BlockBody -> Bool
isBreakBody = \case
  ForcedBreak _ -> True
  PageControl _ -> True
  BlankLines _ -> True
  Separator _ -> True
  _ -> False

-- | The blocks of each frame of the output.
frameBodies :: EvalContext -> Text -> [[BlockBody]]
frameBodies c s = [map blockBody bs | FrameBlock _ bs <- bodies c s]

-- | How many of the codes are the one given.
count :: Text -> [Text] -> Int
count x = length . filter (== x)

breakTests :: TestTree
breakTests =
  testGroup
    "breaks in the bodies of block commands, and commands written twice (root ADR 0462)"
    [ testCase "root ADR 0462 I1: @lang en with @page-break and a paragraph in its body" $ do
        codes ctx "@lang en\n  @page-break\n\n  段落\n" @?= []
        [b | b <- bodies ctx "@lang en\n  @page-break\n\n  段落\n", isBreakBody b] @?= [ForcedBreak BreakPage]
        paragraphs ctx "@lang en\n  @page-break\n\n  段落\n" @?= [(Nothing, "段落")],
      testCase "root ADR 0462 I1: the breaks of the body of @lang stay in the order written" $ do
        let s = "@lang en\n  一\n\n  @need-lines 3\n\n  二\n\n  @blank-line\n\n  ---\n\n  三\n"
        codes ctx s @?= []
        [if isBreakBody b then "break" else "p" | b <- bodies ctx s] @?= ["p" :: String, "break", "p", "break", "break", "p"],
      testCase "root ADR 0462 I1: the body of @lang with a break before a paragraph in its group" $ do
        codes ctx "@lang en\n  @page-break\n  段落\n" @?= []
        [b | b <- bodies ctx "@lang en\n  @page-break\n  段落\n", isBreakBody b] @?= [ForcedBreak BreakPage],
      testCase "root ADR 0462 I1: @style body with @blank-line in its body" $ do
        codes ctx "@style body\n  @blank-line\n\n  段落\n" @?= []
        [b | b <- bodies ctx "@style body\n  @blank-line\n\n  段落\n", isBreakBody b] @?= [BlankLines 1]
        -- a body with no paragraph is G02046 (root ADR 0460), not an error of the break
        codes ctx "@style body\n  @blank-line\n" @?= ["G02046"]
        [b | b <- bodies ctx "@style body\n  @blank-line\n", isBreakBody b] @?= [BlankLines 1],
      testCase "root ADR 0462 I1: a block function and a plugin block command keep a break of their bodies" $ do
        codes ctx "@stage-direction\n  @page-break\n\n  段落\n" @?= []
        [b | b <- bodies ctx "@stage-direction\n  @page-break\n\n  段落\n", isBreakBody b] @?= [ForcedBreak BreakPage]
        codes ctx "@box\n  @page-break\n\n  段落\n" @?= []
        [b | b <- bodies ctx "@box\n  @page-break\n\n  段落\n", isBreakBody b] @?= [ForcedBreak BreakPage],
      testCase "root ADR 0462 I1: @lang en with @page-break in its body inside a list item is G02059" $
        codes ctx "- 項目\n\n  @lang en\n    @page-break\n" @?= ["G02059"],
      testCase "root ADR 0462 I2: @frame f with @page-break and a paragraph on the next line is G02256" $ do
        codes ctx "@frame f\n  @page-break\n  段落\n" @?= ["G02256"]
        map (filter isBreakBody) (frameBodies ctx "@frame f\n  @page-break\n  段落\n") @?= [[]]
        map length (frameBodies ctx "@frame f\n  @page-break\n  段落\n") @?= [1],
      testCase "root ADR 0462 I2: @frame f with two @page-break is G02256 twice" $ do
        codes ctx "@frame f\n  @page-break\n  @page-break\n" @?= ["G02256", "G02256"]
        codes ctx "@frame f\n  @page-break\n\n  @page-break\n" @?= ["G02256", "G02256"]
        codes ctx "@frame f\n  @page-break\n  @blank-line\n  段落\n" @?= ["G02256", "G02256"]
        frameBodies ctx "@frame f\n  @page-break\n  @page-break\n" @?= [[]],
      testCase "root ADR 0462 I2: @frame f with @need-lines 3 is G02256" $
        codes ctx "@frame f\n  @need-lines 3\n" @?= ["G02256"],
      testCase "root ADR 0462 I2: a break inside @style in a frame is G02256" $
        codes ctx "@frame f\n  @style quote\n    @page-break\n\n    段落\n" @?= ["G02013", "G02256"],
      testCase "root ADR 0462 I2: @note n with @separator s is G02141" $ do
        codes ctx "本文[note n]。\n\n@note n\n  @separator s\n\n  段落\n" @?= ["G02141"]
        codes ctx "本文[note n]。\n\n@note n\n  @page-break\n  段落\n" @?= ["G02141"]
        codes ctx "本文[endnote n]。\n\n@endnote n\n  @blank-line\n  @column-break\n  段落\n" @?= ["G02141", "G02141"],
      testCase "root ADR 0462 I2: @blank-line in a caption is G02093" $ do
        codes ctx "@figure x.png alt=x\n  一\n\n  @blank-line\n" @?= ["G02093"]
        codes ctx "@figure x.png alt=x\n  @page-break\n  一\n" @?= ["G02059"]
        [() | FigureBlock f <- bodies ctx "@figure x.png alt=x\n  @page-break\n  一\n", b <- figCaption f, isBreakBody (blockBody b)] @?= [],
      testCase "root ADR 0462 I3, I4: @label a, @label b, @label c and a paragraph" $ do
        count "G02012" (codes ctx "@label a\n@label b\n@label c\n段落\n") @?= 2
        [blockLabel b | b <- resultBlocks (evalResult ctx (src "@label a\n@label b\n@label c\n段落\n"))] @?= [Just "c"],
      testCase "root ADR 0462 I3, I4: @style a, @style b and a paragraph" $ do
        codes ctx "@style quote\n@style aside\n段落\n" @?= ["G02012"]
        paragraphs ctx "@style quote\n@style aside\n段落\n" @?= [(Just "aside", "段落")],
      testCase "root ADR 0462 I3, I4: @lang written three times keeps the last" $ do
        count "G02012" (codes ctx "@lang en\n@lang fr\n@lang de\n段落\n") @?= 2
        [blockLang b | b <- resultBlocks (evalResult ctx (src "@lang en\n@lang fr\n@lang de\n段落\n"))] @?= [Just "de"]
    ]
