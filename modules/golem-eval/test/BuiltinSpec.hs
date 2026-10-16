-- | The built-in inline commands as a sum type (docs/adr ADR 0027).
module BuiltinSpec (tests) where

import Data.List (sort)
import Data.Maybe (isJust)
import Golem.Eval.Builtin
import Golem.Eval.File (builtinInlineCommands, overridableCommands)
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "built-in inline commands (docs/adr ADR 0027)"
    [ testCase "parseBuiltin is the inverse of builtinName" $
        [(b, parseBuiltin (builtinName b)) | b <- allBuiltins] @?= [(b, Just b) | b <- allBuiltins],
      testCase "allBuiltins holds every constructor once" $ do
        sort allBuiltins @?= sort (map Overridable [minBound .. maxBound] <> map Fixed [minBound .. maxBound])
        length allBuiltins @?= length (map Overridable [minBound .. maxBound :: OverridableBuiltin]) + length [minBound .. maxBound :: FixedBuiltin],
      testCase "parseBuiltin rejects names that are not built in" $
        map parseBuiltin ["nope", "", "Strong", "greet", "strong "] @?= replicate 5 Nothing,
      testCase "builtinInlineCommands keeps its names and order" $
        builtinInlineCommands @?= ["strong", "bold", "italic", "code", "ruby", "kenten", "color", "style", "tcy", "number-text", "ref-number", "ref-title", "ref-page", "note", "sidenote", "index", "cite", "aki"],
      testCase "overridableCommands keeps its names and order" $
        overridableCommands @?= ["strong", "bold", "italic", "code", "ruby", "kenten", "color", "style", "tcy", "number-text"],
      testCase "takesNoSlot marks the commands without a prose slot" $
        [builtinName b | b <- allBuiltins, takesNoSlot b] @?= ["number-text", "ref-number", "ref-title", "ref-page", "cite"],
      testCase "pluginCommandName refuses every built-in name" $ do
        map pluginCommandName builtinInlineCommands @?= map (const Nothing) builtinInlineCommands
        fmap unPluginCommandName (pluginCommandName "greet") @?= Just "greet"
        assertBool "a non-built-in name" (isJust (pluginCommandName "nope"))
    ]
