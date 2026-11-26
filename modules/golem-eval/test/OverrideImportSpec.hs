{- | The built-in commands that names listed by @import and plugins may
override (root ADR 0453): the overridable and the fixed commands of each
space of use, the order the evaluation looks a name up in, and the
shorthand ##N##.
-}
module OverrideImportSpec (tests) where

import Data.List (intersect, sort)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR
import Golem.Eval.Builtin (BuiltinInline (..), OverridableBlock (..), OverridableBuiltin (..), allBuiltins, builtinBlockCommands, builtinName, fixedBlockCommands, overridableBlockCommands)
import Golem.Eval.File
import Golem.Eval.Functions
import Golem.Eval.Value
import Golem.Syntax
import Support
import Test.Tasty
import Test.Tasty.HUnit

-- | The overridable inline commands, then the fixed ones.
overridableInline, fixedInline :: [Text]
overridableInline = [builtinName b | b@(Overridable _) <- allBuiltins]
fixedInline = [builtinName b | b@(Fixed _) <- allBuiltins]

{- | functions/over.emet: an inline command of each built-in inline name,
and a block command of each built-in block name. Each puts out a text
F:<name>, its numbers and its slot.
-}
over :: FunctionNamespace
over =
  FunctionNamespace
    { fnInline = Map.fromList [(n, inline n) | n <- overridableInline <> fixedInline],
      fnBlock = Map.fromList [(n, block n) | n <- builtinBlockCommands],
      fnExpr = Map.empty,
      fnOthers = Map.empty
    }
  where
    inline n = InlineFunction (Params [] (Just ArgNat) []) (if n == "number-text" then 0 else 1) "" $ \vs slots sp ->
      Right [Text sp ("F:" <> n <> T.concat [T.pack (show k) | VArray xs <- vs, VNat k <- xs] <> T.concat [t | s <- slots, Text _ t <- s])]
    block n = BlockFunction noParams True "" (\_ body sp -> Right (Block sp Nothing Nothing (Paragraph Nothing [Text sp ("F:" <> n)]) : body))

ctx :: EvalContext
ctx =
  baseCtx
    { ctxFunctions = FunctionTable (Map.fromList [("functions/over.emet", over), ("functions/other.emet", over)]) False Set.empty
    }

-- | over.emet with its inline commands alone, or its block commands alone.
inlineOnly, blockOnly :: EvalContext
inlineOnly = ctx {ctxFunctions = FunctionTable (Map.fromList [("functions/over.emet", over {fnBlock = Map.empty})]) False Set.empty}
blockOnly = ctx {ctxFunctions = FunctionTable (Map.fromList [("functions/over.emet", over {fnInline = Map.empty})]) False Set.empty}

-- | The plugin hook of the tests: ruby over its inline command, separator over its block command.
overriding :: PluginHook
overriding =
  noPlugins
    { phOverrides = Map.fromList [(BRuby, PluginCommand (\_ _ sp -> Right ([Text sp "PLUGIN"], [])))],
      phBlockOverrides = Map.fromList [(BlockSeparator, PluginBlockCommand (\_ _ sp -> Right ([Block sp Nothing Nothing (Paragraph Nothing [Text sp "PLUGIN"])], Map.empty, [])))]
    }

texts :: EvalContext -> Text -> [Text]
texts c src = [T.concat [t | Text _ t <- is] | Paragraph _ is <- resultBodies (evalResult c src)]

codes :: EvalContext -> Text -> [Text]
codes c src = map diagCodeText (fst (evalSource c src))

-- | The code, the message and the text of the source each diagnostic covers.
sites :: EvalContext -> Text -> [(Text, Text, Text)]
sites c src = [(diagCodeText d, diagMessage d, covered d) | d <- fst (evalSource c src)]
  where
    covered d = T.take (spanEnd (diagSpan d) - spanStart (diagSpan d)) (T.drop (spanStart (diagSpan d)) src)

listed, qualified :: Text -> Text -> Text
listed n body = "@import functions/over.emet { " <> n <> " }\n\n" <> body
qualified _ body = "@import functions/over.emet * as ns\n\n" <> body

-- | A call of an inline command of a name, as it is written without and with the namespace.
inlineCall :: Text -> (Text, Text)
inlineCall n
  | n == "number-text" = ("[number-text 3]\n", "[ns.number-text 3]\n")
  | otherwise = ("[" <> n <> ": a]\n", "[ns." <> n <> ": a]\n")

-- | Whether a function of over.emet made a text of the output.
called :: EvalContext -> Text -> Bool
called c src = any ("F:" `T.isPrefixOf`) (texts c src)

g02270 :: Text -> (Text, Text, Text)
g02270 n = ("G02270", "上書きできない組み込みのコマンドと同じ名前は取り込めません: " <> n, n)

tests :: TestTree
tests =
  testGroup
    "built-in commands overridden by listed imports and plugins (root ADR 0453)"
    [ testCase "root ADR 0453 I1: a listed overridable inline command is the namespace's, with no G02270" $
        mapM_
          ( \n -> do
              let (plain, ns) = inlineCall n
              (n, texts inlineOnly (listed n plain), codes inlineOnly (listed n plain)) @?= (n, texts inlineOnly (qualified n ns), [])
              assertBool (T.unpack n) (called inlineOnly (listed n plain))
          )
          overridableInline,
      testCase "root ADR 0453 I1: a listed overridable block command is the namespace's, with no G02270" $
        mapM_
          ( \n -> do
              (n, texts blockOnly (listed n ("@" <> n <> "\n")), codes blockOnly (listed n ("@" <> n <> "\n"))) @?= (n, texts blockOnly (qualified n ("@ns." <> n <> "\n")), [])
              texts blockOnly (listed n ("@" <> n <> "\n")) @?= ["F:" <> n]
          )
          overridableBlockCommands,
      testCase "root ADR 0453 I1: there are seventeen overridable commands" $
        length overridableInline + length overridableBlockCommands @?= 17,
      testCase "root ADR 0453 I2: a listed fixed inline command is G02270 once, and the built-in one is called" $
        mapM_
          ( \n -> do
              sites ctx (listed n "") @?= [g02270 n]
              assertBool (T.unpack n) (not (called ctx (listed n ("[" <> n <> ": a]\n"))))
          )
          [n | n <- fixedInline, n `notElem` overridableBlockCommands],
      testCase "root ADR 0453 I2: a listed fixed block command is G02270 once, and the built-in one is called" $
        mapM_
          ( \n -> do
              sites ctx (listed n "") @?= [g02270 n]
              assertBool (T.unpack n) (not (called ctx (listed n ("@" <> n <> "\n"))))
          )
          [n | n <- fixedBlockCommands, n `notElem` overridableInline],
      testCase "root ADR 0453 I1, I2: { index } overrides @index and keeps [index]" $ do
        sites ctx (listed "index" "") @?= [g02270 "index"]
        texts ctx (listed "index" "@index\n") @?= ["F:index"]
        [e | Paragraph _ is <- resultBodies (evalResult ctx (listed "index" "[index reading=くみはん: 組版]\n")), IndexMark _ e <- is] @?= [IndexEntry ["組版"] ["くみはん"] IndexPoint],
      testCase "root ADR 0453 I1, I2: { style } overrides [style] and keeps @style" $ do
        sites ctx (listed "style" "") @?= [g02270 "style"]
        texts ctx (listed "style" "[style: a]\n") @?= ["F:stylea"]
        assertBool "@style" (not (called ctx (listed "style" "@style\n  本文\n"))),
      testCase "root ADR 0453 I3: before the @import line, the built-in command" $ do
        case resultBodies (evalResult ctx ("@toc\n\n" <> listed "toc" "@toc\n")) of
          [ChannelOutput (TocOutput 2), Paragraph Nothing [Text _ "F:toc"]] -> pure ()
          other -> assertFailure (show other)
        [t | Paragraph _ is <- resultBodies (evalResult ctx ("[strong: a]\n\n" <> listed "strong" "[strong: b]\n")), CharStyle _ "strong" xs <- is, Text _ t <- xs] @?= ["a"],
      testCase "root ADR 0453 I3: another file calls the built-in command" $
        resultBodies (evalResult ctx "@toc\n") @?= [ChannelOutput (TocOutput 2)],
      testCase "root ADR 0453 I4: @separator calls the plugin of block-overrides" $ do
        let c = ctx {ctxPlugins = overriding}
        texts c "@separator\n" @?= ["PLUGIN"]
        codes c "@separator\n" @?= []
        texts c "@toc\n" @?= [],
      testCase "root ADR 0453 I5: a plugin's override and a listed name: G02271 once, and the plugin is called" $ do
        let c = ctx {ctxPlugins = overriding}
            g02271 n = ("G02271", "プラグインのコマンドと同じ名前は取り込めません: " <> n, n)
        sites c (listed "ruby" "") @?= [g02271 "ruby"]
        texts c (listed "ruby" "[ruby: a]\n") @?= ["PLUGIN"]
        sites c (listed "separator" "") @?= [g02271 "separator"]
        texts c (listed "separator" "@separator\n") @?= ["PLUGIN"],
      testCase "root ADR 0453 I6: each built-in block command is no G02009, another name is" $ do
        -- set is the name of @set name = 式, which the parser reads apart; @set alone is G02009 as before (FileSpec)
        mapM_ (\n -> assertBool (T.unpack n) ("G02009" `notElem` codes baseCtx ("@" <> n <> "\n"))) (filter (/= "set") builtinBlockCommands)
        codes baseCtx "@nonexistent\n" @?= ["G02009"],
      testCase "root ADR 0453 I6: the list is the overridable five and the names of G02270, apart" $ do
        sort builtinBlockCommands @?= sort (overridableBlockCommands <> fixedBlockCommands)
        overridableBlockCommands `intersect` fixedBlockCommands @?= []
        sort overridableBlockCommands @?= sort ["toc", "index", "bibliography", "printings", "separator"]
        -- the block names G02270 counts: each of a .emet of block commands alone
        [n | n <- builtinBlockCommands, (c, _, _) <- sites blockOnly (listed n ""), c == "G02270"] @?= fixedBlockCommands,
      testCase "root ADR 0453 I8: a name of a .emet that could not be loaded puts out nothing" $ do
        let unloaded = ctx {ctxFunctions = (ctxFunctions ctx) {ftUnloaded = True}}
        resultBodies (evalResult unloaded (listed "toc" "@toc\n")) @?= []
        texts unloaded (listed "strong" "[strong: a]\n") @?= [""]
        codes unloaded (listed "toc" "@toc\n") @?= [],
      testCase "root ADR 0453 I8: a name of G02272 puts out nothing" $ do
        let twice body = "@import functions/over.emet { toc, strong }\n@import functions/other.emet { toc, strong }\n\n" <> body
        sort (codes ctx (twice "@toc\n")) @?= replicate 4 "G02272"
        resultBodies (evalResult ctx (twice "@toc\n")) @?= []
        texts ctx (twice "[strong: a]\n") @?= [""],
      testCase "root ADR 0453 I9: ##N## after { number-text } is [number-text N]" $ do
        texts ctx (listed "number-text" "##3##\n") @?= texts ctx (listed "number-text" "[number-text 3]\n")
        texts ctx (listed "number-text" "##3##\n") @?= ["F:number-text3"],
      testCase "root ADR 0453: the lint counts an overridden name as used" $ do
        usageListedRefs (erUsage (evalResult ctx (listed "toc" "@toc\n"))) @?= Set.fromList ["toc"]
        usageListedRefs (erUsage (evalResult ctx (listed "strong" "[strong: a]\n"))) @?= Set.fromList ["strong"]
    ]
