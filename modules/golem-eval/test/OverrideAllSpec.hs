{- | The built-in commands that names listed by @import may override (root
ADR 0471): every block and inline command but those of the mechanisms of
Golem and @frame, and the handling by name only where the built-in
command is called.
-}
module OverrideAllSpec (tests) where

import Data.List (sort, (\\))
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR
import Golem.Eval.Builtin (BuiltinInline (..), OverridableBlock (..), builtinBlockCommands)
import Golem.Eval.File
import Golem.Eval.Functions
import Golem.Parser (parseAst)
import Golem.Project.Style (LineBreaks (..), paraLineBreaks, parseStyle)
import Golem.Syntax
import Support
import Test.Tasty
import Test.Tasty.HUnit

{- | The names that stay the built-in ones (root ADR 0471): the mechanisms
of Golem, then @frame. Written out here, apart from the implementation.
-}
fixedBlock :: [Text]
fixedBlock =
  ["import", "set", "channel", "manifest", "style-def", "hyphenation-exceptions", "label", "toc-title", "number", "nonumber", "notoc", "caption", "column-widths", "frame"]

{- | functions/all.emet: an inline command and a block command of each
built-in name, and extra. Each takes any strings; the inline one puts
out F:<name> and its slot, the block one a paragraph F:<name> and then
its body.
-}
allNs :: FunctionNamespace
allNs =
  FunctionNamespace
    { fnInline = Map.fromList [(n, inline n) | n <- "extra" : builtinInlineCommands],
      fnBlock = Map.fromList [(n, block n) | n <- "extra" : builtinBlockCommands],
      fnExpr = Map.empty,
      fnOthers = Map.empty
    }
  where
    any' = Params [] (Just ArgString) []
    inline n = InlineFunction any' 1 "" $ \_ slots sp -> Right [Text sp ("F:" <> n <> T.concat [t | s <- slots, Text _ t <- s])]
    block n = BlockFunction any' True "" (\_ body sp -> Right (Block sp Nothing Nothing (Paragraph Nothing [Text sp ("F:" <> n)]) : body))

withNs :: FunctionNamespace -> EvalContext
withNs ns =
  baseCtx
    { ctxFunctions = FunctionTable (Map.fromList [("functions/all.emet", ns)]) False Set.empty,
      ctxParaStyles = Map.fromList [("s", JoinLines)]
    }

-- | all.emet whole, with its block commands alone, and with its inline commands alone.
ctxAll, blockOnly, inlineOnly :: EvalContext
ctxAll = withNs allNs
blockOnly = withNs allNs {fnInline = Map.empty}
inlineOnly = withNs allNs {fnBlock = Map.empty}

listed :: Text -> Text -> Text
listed n body = "@import functions/all.emet { " <> n <> " }\n\n" <> body

texts :: EvalContext -> Text -> [Text]
texts c src = [T.concat [t | Text _ t <- is] | Paragraph _ is <- resultBodies (evalResult c src)]

codes :: EvalContext -> Text -> [Text]
codes c src = map diagCodeText (fst (evalSource c src))

sites :: EvalContext -> Text -> [(Text, Text, Text)]
sites c src = [(diagCodeText d, diagMessage d, covered d) | d <- fst (evalSource c src)]
  where
    covered d = T.take (spanEnd (diagSpan d) - spanStart (diagSpan d)) (T.drop (spanStart (diagSpan d)) src)

called :: EvalContext -> Text -> Bool
called c src = any ("F:" `T.isPrefixOf`) (texts c src)

g02270 :: Text -> (Text, Text, Text)
g02270 n = ("G02270", "上書きできない組み込みのコマンドと同じ名前は取り込めません: " <> n, n)

-- | A plugin over cite and over the block note, each putting out PLUGIN.
overriding :: PluginHook
overriding =
  noPlugins
    { phOverrides = Map.fromList [(BCite, PluginCommand (\_ _ sp -> Right ([Text sp "PLUGIN"], [])))],
      phBlockOverrides = Map.fromList [(BlockNote, PluginBlockCommand (\_ body sp -> Right (Block sp Nothing Nothing (Paragraph Nothing [Text sp "PLUGIN"]) : body, Map.empty, [])))]
    }

-- | The overrides the tools read of a source ('fileOverrides').
overridesOf :: EvalContext -> Text -> Overrides
overridesOf c src = let (file, _, _) = parseAst (FileId 1) src in fileOverrides (ctxFunctions c) (ctxPlugins c) file

-- | The overridable block names: every built-in block name but the fixed ones.
overridableBlock :: [Text]
overridableBlock = builtinBlockCommands \\ fixedBlock

tests :: TestTree
tests =
  testGroup
    "built-in commands overridden but the mechanisms and @frame (root ADR 0471)"
    [ testCase "root ADR 0471 I1: a file that overrides no built-in name evaluates as before, for every block and inline name" $ do
        let same body = (texts ctxAll (listed "extra" body), codes ctxAll (listed "extra" body)) @?= (texts ctxAll body, codes ctxAll body)
        -- the file settings are read at the top of a file alone, before the @import line (docs/adr ADR 0014)
        mapM_ (\n -> same ("@" <> n <> "\n")) (filter (`notElem` ["import", "set", "manifest", "style-def", "hyphenation-exceptions"]) builtinBlockCommands)
        mapM_ (\n -> same ("[" <> n <> ": a]\n")) builtinInlineCommands,
      testCase "root ADR 0471 I1: { note } of a .emet that could not be loaded: @note puts out nothing, G02279 once, and the paragraph is set" $ do
        let unloaded = ctxAll {ctxFunctions = (ctxFunctions ctxAll) {ftUnloaded = True}}
        texts unloaded (listed "note" "@note\n段落\n") @?= ["段落"]
        -- the paragraph after a name the evaluation cannot call is G02011, as root ADR 0461 decides
        filter (== "G02279") (codes unloaded (listed "note" "@note\n段落\n")) @?= ["G02279"]
        codes unloaded (listed "note" "@note\n\n段落\n") @?= ["G02279"],
      testCase "root ADR 0471 I2: each overridable block name listed is the function's, with no G02270 and no diagnostics of the built-in one" $
        mapM_ (\n -> (n, texts blockOnly (listed n ("@" <> n <> "\n")), codes blockOnly (listed n ("@" <> n <> "\n"))) @?= (n, ["F:" <> n], [])) overridableBlock,
      testCase "root ADR 0471 I2: each inline name listed is the function's, with no G02270 and no diagnostics of the built-in one" $
        mapM_ (\n -> (n, texts inlineOnly (listed n ("[" <> n <> ": a]\n")), codes inlineOnly (listed n ("[" <> n <> ": a]\n"))) @?= (n, ["F:" <> n <> "a"], [])) builtinInlineCommands,
      testCase "root ADR 0471 I2: the overridable block names are the page breaks, blank-line, figure, table, listing, style, lang, note, endnote and the five of root ADR 0453" $
        sort overridableBlock
          @?= sort ["toc", "index", "bibliography", "printings", "separator", "page-break", "column-break", "no-page-break", "need-lines", "page-lines", "blank-line", "figure", "table", "listing", "style", "lang", "note", "endnote"],
      testCase "root ADR 0471 I2: { note } and @note with a paragraph: the function's output, no G02270 nor G02142" $ do
        texts blockOnly (listed "note" "@note\n段落\n") @?= ["F:note", "段落"]
        codes blockOnly (listed "note" "@note\n段落\n") @?= [],
      testCase "root ADR 0471 I2: { note } with @label x, @note and a paragraph: the label on the function's output, no G02013" $ do
        let r = evalResult blockOnly (listed "note" "@label x\n@note\n段落\n")
        map blockLabel (resultBlocks r) @?= [Just "x", Nothing]
        codes blockOnly (listed "note" "@label x\n@note\n段落\n") @?= [],
      testCase "root ADR 0471 I2: { note } inside the body of @style s: s on the paragraphs of the function's output" $ do
        [st | Paragraph st _ <- resultBodies (evalResult blockOnly (listed "note" "@style s\n@note\n段落\n"))] @?= [Just "s", Just "s"]
        codes blockOnly (listed "note" "@style s\n@note\n段落\n") @?= [],
      testCase "root ADR 0471 I2: { note } of an inline command and [note 本文]: the function's output, no G02270" $ do
        texts inlineOnly (listed "note" "[note: 本文]\n") @?= ["F:note本文"]
        codes inlineOnly (listed "note" "[note: 本文]\n") @?= [],
      testCase "root ADR 0471 I2: { page-break } of Blocks -> Blocks and @page-break with a paragraph: the paragraph is the body" $ do
        texts blockOnly (listed "page-break" "@page-break\n段落\n") @?= ["F:page-break", "段落"]
        [() | ForcedBreak _ <- resultBodies (evalResult blockOnly (listed "page-break" "@page-break\n段落\n"))] @?= []
        codes blockOnly (listed "page-break" "@page-break\n段落\n") @?= [],
      testCase "root ADR 0471 I2: { figure } and @figure a.png without a.png: the function's output, no error of the file" $ do
        texts blockOnly (listed "figure" "@figure a.png\n") @?= ["F:figure"]
        codes blockOnly (listed "figure" "@figure a.png\n") @?= [],
      -- G02077 of the repeated key is that of every command (golem-parser ADR 0013); the call is not stopped as that of @listing is
      testCase "root ADR 0471 I2: { listing } and src twice: the call reaches the function, whose signature has no src" $
        codes blockOnly (listed "listing" "@listing src=a src=b\n") @?= ["G02077", "G02119", "G02119"],
      testCase "root ADR 0471 I2: { lang } and @lang twice: the functions, no G02012" $ do
        texts blockOnly (listed "lang" "@lang en\n@lang ja\n段落\n") @?= ["F:lang", "F:lang", "段落"]
        codes blockOnly (listed "lang" "@lang en\n@lang ja\n段落\n") @?= [],
      testCase "root ADR 0471 I2: { toc as note } and @note with a paragraph: the output of toc" $ do
        texts blockOnly ("@import functions/all.emet { toc as note }\n\n@note\n段落\n") @?= ["F:toc", "段落"]
        codes blockOnly ("@import functions/all.emet { toc as note }\n\n@note\n段落\n") @?= [],
      testCase "root ADR 0471 I3: { note as n } and @note with a paragraph: the built-in note, G02142" $ do
        assertBool "not called" (not (called blockOnly ("@import functions/all.emet { note as n }\n\n@note\n段落\n")))
        codes blockOnly ("@import functions/all.emet { note as n }\n\n@note\n段落\n") @?= ["G02142"],
      testCase "root ADR 0471 I3: @note before the @import line of { note }: the built-in note, G02142 and no G02270" $ do
        assertBool "not called" (not (called blockOnly ("@note\n段落\n\n" <> listed "note" "")))
        codes blockOnly ("@note\n段落\n\n" <> listed "note" "") @?= ["G02142"],
      testCase "root ADR 0471 I4: each fixed block name listed is G02270 once, and its call is the built-in one" $
        mapM_
          ( \n -> do
              (n, sites blockOnly (listed n "")) @?= (n, [g02270 n])
              assertBool (T.unpack n) (not (called blockOnly (listed n ("@" <> n <> "\n"))))
          )
          fixedBlock,
      testCase "root ADR 0471 I4: G02270 is for the fixed names alone, of every built-in block and inline name" $ do
        [n | n <- builtinBlockCommands, "G02270" `elem` codes blockOnly (listed n "")] @?= filter (`elem` fixedBlock) builtinBlockCommands
        [n | n <- builtinInlineCommands, "G02270" `elem` codes inlineOnly (listed n "")] @?= [],
      testCase "root ADR 0471 I4: { import }, { set }, { frame } and { label } are G02270 each" $
        mapM_ (\n -> sites blockOnly (listed n "") @?= [g02270 n]) ["import", "set", "frame", "label"],
      testCase "root ADR 0471 I5: a plugin's override of cite and of the block note is called" $ do
        let c = baseCtx {ctxPlugins = overriding}
        texts c "本文[cite k]。\n" @?= ["本文PLUGIN。"]
        texts c "@note\n段落\n" @?= ["PLUGIN", "段落"]
        codes c "@note\n段落\n" @?= []
        -- the inline note and the block cite stay the built-in ones
        codes c "本文[note x]。\n" @?= ["G02137"],
      testCase "root ADR 0471: the overrides the tools read agree with the evaluation, for every built-in name" $ do
        let at n src = T.length (fst (T.breakOn ("@" <> n <> "\n") src))
        mapM_
          ( \n -> do
              let src = "@" <> n <> "\n\n" <> listed n ("@" <> n <> "\n")
                  ov = overridesOf blockOnly src
                  later = T.length src - T.length n - 2
              (n, callsBuiltin ov BlockSpace n (at n src), callsBuiltin ov BlockSpace n later) @?= (n, True, n `elem` fixedBlock)
          )
          builtinBlockCommands
        mapM_ (\n -> (n, callsBuiltin (overridesOf inlineOnly (listed n "")) InlineSpace n 1000) @?= (n, False)) builtinInlineCommands
        -- a .emet that could not be loaded overrides every space; a plugin every file
        callsBuiltin (overridesOf ctxAll {ctxFunctions = (ctxFunctions ctxAll) {ftUnloaded = True}} (listed "note" "")) InlineSpace "note" 1000 @?= False
        callsBuiltin (overridesOf baseCtx {ctxPlugins = overriding} "") BlockSpace "note" 0 @?= False
        callsBuiltin (overridesOf blockOnly (listed "note" "")) InlineSpace "note" 1000 @?= True,
      testCase "root ADR 0471 I6: [note x] in a file that overrides the block note is G02137, a @note x after it included" $ do
        codes blockOnly (listed "note" "本文[note x]。\n") @?= ["G02137"]
        codes blockOnly (listed "note" "本文[note x]。\n\n@note x\n  注。\n") @?= ["G02137"],
      testCase "root ADR 0471 I8: { style } leaves the next-style to the built-in paragraph style" $ do
        let style = either (error . show) id (parseStyle (FileId 9) "[paragraph-styles.body]\nnext-style = \"after\"\n\n[paragraph-styles.after]\n")
            c = blockOnly {ctxStyle = style, ctxParaStyles = paraLineBreaks style}
        [(st, T.concat [t | Text _ t <- is]) | Paragraph st is <- resultBodies (evalResult c (listed "style" "一\n\n二\n"))] @?= [(Nothing, "一"), (Just "after", "二")]
        codes c (listed "style" "一\n\n二\n") @?= []
    ]
