-- | Requirements and their handlers in golem-gmx (docs/adr/0149).
module RequirementSpec (requirementTests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Gmx
import Golem.Syntax
import Support
import Test.Tasty
import Test.Tasty.HUnit

requirementTests :: TestTree
requirementTests =
  testGroup
    "requirements (docs/adr/0149)"
    [ testCase "a function with => file calls File.read" $ do
        r <- callWith (fileHandler (Map.fromList [("words", TE.encodeUtf8 "a\tあ\n")])) "f :: String => file;\nf = File.read \"words\";\n" "f" [] >>= ok
        r @?= str "a\tあ\n",
      testCase "File.read from a function without => is G10501" $
        codes "f :: String;\nf = File.read \"words\";\n" @?= ["G10501"],
      testCase "a call of a function that requires file, from one without, is G10501" $
        codes "g :: String => file;\ng = File.read \"words\";\nf :: String;\nf = g;\n" @?= ["G10501"],
      testCase "the message of G10501 names the requirement" $
        assertBool "file" (any ("file" `T.isInfixOf`) (messages "f :: String;\nf = File.read \"words\";\n")),
      testCase "a local function of where inherits the requirements" $
        noDiagnostics "f :: String => file;\nf = g \"words\" where { g n = File.read n; };\n",
      testCase "=> net is G10500 and names file" $ do
        let src = "f :: String => net;\nf = \"\";\n"
        codes src @?= ["G10500"]
        assertBool (show (messages src)) (any ("file" `T.isInfixOf`) (messages src)),
      testCase "unknown requirements are one G10500" $
        codes "f :: String => net, time;\nf = \"\";\n" @?= ["G10500"],
      testCase "=> file, file is G10502" $
        codes "f :: String => file, file;\nf = \"\";\n" @?= ["G10502"],
      testCase "a function with requirements passed to List.map is G10501" $
        codes "g :: String -> String => file;\ng n = File.read n;\nf :: List String => file;\nf = List.map g [\"a\"];\n" @?= ["G10501"],
      testCase "an unused => file is no error" $
        noDiagnostics "f :: String => file;\nf = \"\";\n",
      testCase "File.read of a name the handler does not have is G10503 at the call" $ do
        let src = "f :: String => file;\nf = File.read \"missing\";\n"
        r <- callWith (fileHandler Map.empty) src "f" []
        case r of
          Left d -> do
            diagCode d @?= DiagnosticCode "G10503"
            spanStart (diagSpan d) @?= T.length (fst (T.breakOn "File.read" src))
          Right v -> assertFailure (show v),
      testCase "the requirements of a program are listed with their signatures" $ case load "f :: String => file;\nf = \"\";\ng :: Nat;\ng = 1;\n" of
        ([], Just p) -> map fst (programRequirements p) @?= ["file"]
        (ds, _) -> assertFailure (show ds)
    ]
