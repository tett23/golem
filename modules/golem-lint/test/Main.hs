module Main (main) where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Golem.Eval.File (Usage (..))
import Golem.Lint
import Golem.Parser (parse)
import Golem.Parser.SourceSettings
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

main :: IO ()
main = defaultMain tests

newlineCodes :: Text -> [Text]
newlineCodes = newlineCodesWith (Set.fromList ["verse"])

newlineCodesWith :: Set.Set Text -> Text -> [Text]
newlineCodesWith = newlineCodesIn defaultSourceSettings

newlineCodesIn :: SourceSettings -> Set.Set Text -> Text -> [Text]
newlineCodesIn source keep src = [c | d <- latinJoinedByNewline source keep (FileId 0) (fst (parse (FileId 0) src)), let DiagnosticCode c = diagCode d]

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
      testCase "G0501 does not apply to the line breaks of keep styles (docs/adr ADR 0003, 0005)" $ do
        newlineCodes "@style verse\n  Full fathom five\n  Of his bones\n" @?= []
        newlineCodes "@style verse\nFull fathom five\nOf his bones\n" @?= []
        newlineCodes "@label song\n@style verse\nFull fathom five\nOf his bones\n" @?= []
        newlineCodes "Full fathom five\nOf his bones\n" @?= ["G0501"]
        newlineCodes "@style verse\n  [note: a\n  b] x\n" @?= ["G0501"]
        newlineCodes "@style quote\n  Full fathom five\n  Of his bones\n" @?= ["G0501"]
        newlineCodes "@style quote\nFull fathom five\nOf his bones\n" @?= ["G0501"]
        newlineCodesWith (Set.fromList ["verse", "quote"]) "@style quote\n  Full fathom five\n  Of his bones\n" @?= []
        -- a style a file defines (docs/adr ADR 0014)
        newlineCodesWith (Set.fromList ["verse", "letter"]) "@style letter\n  Full fathom five\n  Of his bones\n" @?= []
        newlineCodes "@figure a.png alt=x\n  Full fathom\n  five\n" @?= ["G0501"],
      testCase "G0501 does not apply to hard line breaks (docs/adr ADR 0016)" $ do
        newlineCodes "Full fathom\\\nfive\n" @?= []
        newlineCodes "Full fathom\nfive\n" @?= ["G0501"],
      testCase "G0501 does not apply to the newlines that separate paragraphs (docs/adr ADR 0013)" $ do
        let lineCodes = newlineCodesIn (SourceSettings LineSeparated) (Set.fromList ["verse"])
        lineCodes "Full fathom\nfive\n" @?= []
        newlineCodes "Full fathom\nfive\n" @?= ["G0501"]
        lineCodes "- Full fathom\n  five\n" @?= []
        lineCodes "@style quote\n  Full fathom\n  five\n" @?= []
        lineCodes "[note: a\nb] x\n" @?= ["G0501"],
      testCase "G0502 unused variable, unless an importer uses it" $ do
        let defining = FileLint (FileId 1) "common.gm" (fst (parse (FileId 1) "")) defaultSourceSettings usage {usageDefined = [("x", sp), ("y", sp)]}
            importing = FileLint (FileId 2) "ch.gm" (fst (parse (FileId 2) "")) defaultSourceSettings usage {usageImports = [("c", "common.gm", sp)], usageNamespaceRefs = Map.fromList [("c", Set.fromList ["x"])]}
        codes (lint (LintInput [defining, importing] Map.empty Set.empty (Set.fromList ["verse"]))) @?= ["G0502"],
      testCase "G0503 unused import" $ do
        let f = FileLint (FileId 1) "a.gm" (fst (parse (FileId 1) "")) defaultSourceSettings usage {usageImports = [("v", "v.gm", sp)]}
        codes (lint (LintInput [f] Map.empty Set.empty (Set.fromList ["verse"]))) @?= ["G0503"],
      testCase "G0504 unreferenced labels are warnings, errors in prod" $ do
        let ds = lint (LintInput [] (Map.fromList [("a", sp), ("b", sp)]) (Set.fromList ["a"]) (Set.fromList ["verse"]))
        map diagSeverity ds @?= [Warning]
        map (diagSeverity . adjustForProfile Prod) ds @?= [Error]
    ]
