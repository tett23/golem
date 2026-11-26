-- | The built-in inline commands as a sum type (docs/adr ADR 0027).
module BuiltinSpec (tests) where

import Data.List (sort)
import Data.Maybe (isJust)
import Golem.Eval.Builtin
import Golem.Eval.File (builtinInlineCommands)
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "built-in inline commands (docs/adr ADR 0027)"
    [ testCase "root ADR 0380 I1: warichu and upright are built-in prose commands" $
        assertBool "both commands are built in" (all (isJust . parseBuiltin) ["warichu", "upright"]),
      testCase "parseBuiltin is the inverse of builtinName" $
        [(b, parseBuiltin (builtinName b)) | b <- allBuiltins] @?= [(b, Just b) | b <- allBuiltins],
      testCase "allBuiltins holds every constructor once" $ do
        sort allBuiltins @?= [minBound .. maxBound]
        length allBuiltins @?= length [minBound .. maxBound :: BuiltinInline],
      testCase "parseBuiltin rejects names that are not built in" $
        map parseBuiltin ["nope", "", "Strong", "greet", "strong "] @?= replicate 5 Nothing,
      testCase "builtinInlineCommands keeps its names and order" $
        builtinInlineCommands @?= ["strong", "bold", "italic", "code", "ruby", "kenten", "color", "style", "warichu", "upright", "tcy", "number-text", "ref-number", "ref-title", "ref-page", "note", "sidenote", "endnote", "index", "cite", "aki", "link", "lang", "shy"],
      -- docs/adr ADR 0031, root ADR 0471: a plugin may override every built-in inline command
      testCase "root ADR 0471 I2: every built-in inline command is one a plugin may override" $
        map builtinName allBuiltins @?= builtinInlineCommands,
      testCase "takesNoSlot marks the commands without a prose slot" $
        [builtinName b | b <- allBuiltins, takesNoSlot b] @?= ["number-text", "ref-number", "ref-title", "ref-page", "cite", "shy"],
      testCase "pluginCommandName refuses every built-in name" $ do
        map pluginCommandName builtinInlineCommands @?= map (const Nothing) builtinInlineCommands
        fmap unPluginCommandName (pluginCommandName "greet") @?= Just "greet"
        assertBool "a non-built-in name" (isJust (pluginCommandName "nope"))
    ]
