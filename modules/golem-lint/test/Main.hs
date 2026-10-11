module Main (main) where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Golem.Eval.File (Usage (..))
import Golem.Lint
import Golem.Parser (parse)
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

main :: IO ()
main = defaultMain tests

newlineCodes :: Text -> [Text]
newlineCodes src = [c | d <- latinJoinedByNewline (FileId 0) (fst (parse (FileId 0) src)), let DiagnosticCode c = diagCode d]

usage :: Usage
usage = Usage [] Set.empty Map.empty []

codes :: [Diagnostic] -> [Text]
codes = map (\d -> let DiagnosticCode c = diagCode d in c)

sp :: SrcSpan
sp = mkSpan (FileId 0) 0 1

tests :: TestTree
tests =
  testGroup
    "golem-lint (ADR 0001)"
    [ testCase "G0501 only between Latin characters" $ do
        newlineCodes "This is\nEnglish\n" @?= ["G0501"]
        newlineCodes "日本語の\n文章\n" @?= []
        newlineCodes "Golem は\n日本語\n" @?= []
        newlineCodes "日本語\nGolem\n" @?= []
        newlineCodes "Ελληνικά\nκείμενο\n" @?= ["G0501"],
      testCase "G0501 sees through indentation of continuation lines but not commands" $ do
        newlineCodes "- word\n  word\n" @?= ["G0501"]
        newlineCodes "[strong: a]\n[strong: b]\n" @?= [],
      testCase "G0502 unused variable, unless an importer uses it" $ do
        let defining = FileLint (FileId 1) "common.gm" (fst (parse (FileId 1) "")) usage {usageDefined = [("x", sp), ("y", sp)]}
            importing = FileLint (FileId 2) "ch.gm" (fst (parse (FileId 2) "")) usage {usageImports = [("c", "common.gm", sp)], usageNamespaceRefs = Map.fromList [("c", Set.fromList ["x"])]}
        codes (lint (LintInput [defining, importing] Map.empty Set.empty)) @?= ["G0502"],
      testCase "G0503 unused import" $ do
        let f = FileLint (FileId 1) "a.gm" (fst (parse (FileId 1) "")) usage {usageImports = [("v", "v.gm", sp)]}
        codes (lint (LintInput [f] Map.empty Set.empty)) @?= ["G0503"],
      testCase "G0504 unreferenced labels are warnings, errors in prod" $ do
        let ds = lint (LintInput [] (Map.fromList [("a", sp), ("b", sp)]) (Set.fromList ["a"]))
        map diagSeverity ds @?= [Warning]
        map (diagSeverity . adjustForProfile Prod) ds @?= [Error]
    ]
