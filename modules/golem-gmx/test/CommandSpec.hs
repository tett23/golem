-- | pub inline and pub block: commands of .gm (docs/adr/0150).
module CommandSpec (commandTests) where

import Golem.Doc.IR
import Golem.Eval.File (FunctionParam (..))
import Golem.Eval.Value (Value (..))
import Golem.Gmx
import Golem.Syntax
import Support
import Test.Tasty
import Test.Tasty.HUnit

commandTests :: TestTree
commandTests =
  testGroup
    "pub inline and pub block (docs/adr/0150)"
    [ testCase "taxIncluded is tax-included" $ do
        commandName "taxIncluded" @?= Just "tax-included"
        commandName "wordTable" @?= Just "word-table"
        commandName "ruby" @?= Just "ruby",
      testCase "toHTML and to_html are G10600" $ do
        codes "pub inline toHTML :: Inlines;\ntoHTML = Inline.text \"\";\n" @?= ["G10600"]
        codes "pub inline to_html :: Inlines;\nto_html = Inline.text \"\";\n" @?= ["G10600"]
        commandName "toHTML" @?= Nothing
        commandName "to_html" @?= Nothing,
      testCase "pub inline that returns a String is G10601" $
        codes "pub inline f :: String;\nf = \"\";\n" @?= ["G10601"],
      testCase "pub block that returns Inlines is G10601" $
        codes "pub block f :: Inlines;\nf = Inline.text \"\";\n" @?= ["G10601"],
      testCase "an Inlines argument before a Nat argument is G10602" $
        codes "pub inline f :: Inlines -> Nat -> Inlines;\nf s n = s;\n" @?= ["G10602"],
      testCase "a Maybe Nat argument of pub inline is G10602" $
        codes "pub inline f :: Maybe Nat -> Inlines;\nf _ = Inline.text \"\";\n" @?= ["G10602"],
      testCase "pub inline block is G10100" $
        codes "pub inline block f :: Inlines;\nf = Inline.text \"\";\n" @?= ["G10100"],
      testCase "the commands of a program: names, arguments, slots and body" $ case load "pub inline taxIncluded :: Nat -> Inlines;\ntaxIncluded n = Inline.text (String.fromNat n);\npub block wordTable :: String -> Blocks -> Blocks;\nwordTable _ b = b;\npub inline emphTwice :: Inlines -> Inlines;\nemphTwice s = s ++ s;\n" of
        ([], Just p) ->
          [(cmdName c, cmdKind c, cmdParams c, cmdSlots c, cmdBody c) | c <- programCommands p]
            @?= [ ("tax-included", InlineCommand, [FPNat], 0, False),
                  ("word-table", BlockCommand, [FPString], 0, True),
                  ("emph-twice", InlineCommand, [], 1, False)
                ]
        (ds, _) -> assertFailure (show ds),
      testCase "a command builds inlines at the call" $ case load "pub inline taxIncluded :: Nat -> Inlines;\ntaxIncluded n = Inline.text (String.fromRat (n * 11 / 10)) ++ Inline.ruby \"円\" \"えん\";\n" of
        ([], Just p) -> case programCommands p of
          [c] -> do
            let at = mkSpan (FileId 1) 3 9
            callCommand noHandlers p at c [VNat 1000] (Left [])
              @?= Right (Left [Text at "1100", Ruby at () [RubySegment [Text at "円"] (Just "えん")]])
          cs -> assertFailure (show (length cs))
        (ds, _) -> assertFailure (show ds)
    ]
