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

-- | (code, start, end) of each G05001 with the keep style verse.
newlineSpans :: SourceSettings -> Text -> [(Text, Int, Int)]
newlineSpans source src =
  [ (c, spanStart (diagSpan d), spanEnd (diagSpan d))
  | d <- latinJoinedByNewline source (Set.fromList ["verse"]) (FileId 0) (fst (parse (FileId 0) src)),
    let DiagnosticCode c = diagCode d
  ]

-- | (code, message) of each diagnostic.
coded :: [Diagnostic] -> [(Text, Text)]
coded = map (\d -> let DiagnosticCode c = diagCode d in (c, diagMessage d))

tests :: TestTree
tests =
  testGroup
    "golem-lint (ADR 0001)"
    [ testCase "G05001 only between Latin characters" $ do
        newlineCodes "This is\nEnglish\n" @?= ["G05001"]
        newlineCodes "日本語の\n文章\n" @?= []
        newlineCodes "Golem は\n日本語\n" @?= []
        newlineCodes "日本語\nGolem\n" @?= []
        newlineCodes "Ελληνικά\nκείμενο\n" @?= ["G05001"],
      testCase "G05001 sees through indentation of continuation lines but not commands" $ do
        newlineCodes "- word\n  word\n" @?= ["G05001"]
        newlineCodes "[strong: a]\n[strong: b]\n" @?= [],
      testCase "G05001 does not apply to the line breaks of keep styles (docs/adr ADR 0003, 0005)" $ do
        newlineCodes "@style verse\n  Full fathom five\n  Of his bones\n" @?= []
        newlineCodes "@style verse\nFull fathom five\nOf his bones\n" @?= []
        newlineCodes "@label song\n@style verse\nFull fathom five\nOf his bones\n" @?= []
        newlineCodes "Full fathom five\nOf his bones\n" @?= ["G05001"]
        newlineCodes "@style verse\n  [note: a\n  b] x\n" @?= ["G05001"]
        newlineCodes "@style quote\n  Full fathom five\n  Of his bones\n" @?= ["G05001"]
        newlineCodes "@style quote\nFull fathom five\nOf his bones\n" @?= ["G05001"]
        newlineCodesWith (Set.fromList ["verse", "quote"]) "@style quote\n  Full fathom five\n  Of his bones\n" @?= []
        -- a style a file defines (docs/adr ADR 0014)
        newlineCodesWith (Set.fromList ["verse", "letter"]) "@style letter\n  Full fathom five\n  Of his bones\n" @?= []
        newlineCodes "@figure a.png alt=x\n  Full fathom\n  five\n" @?= ["G05001"],
      testCase "G05001 does not apply to hard line breaks (docs/adr ADR 0016)" $ do
        newlineCodes "Full fathom\\\nfive\n" @?= []
        newlineCodes "Full fathom\nfive\n" @?= ["G05001"],
      testCase "G05001 sees through the spaces the language ignores at the end of a line (golem-lint ADR 0002)" $ do
        newlineSpans defaultSourceSettings "word  \nword\n" @?= [("G05001", 6, 7)]
        newlineCodes "word\t\nword\n" @?= ["G05001"]
        newlineCodes "- word  \n   word\n" @?= ["G05001"]
        newlineCodes "word\x3000\nword\n" @?= []
        newlineCodes "word\\ \nword\n" @?= []
        newlineCodes "word  \\\nword\n" @?= []
        newlineCodes "語  \nword\n" @?= [],
      testCase "G05001 does not apply to the newlines that separate paragraphs (docs/adr ADR 0013)" $ do
        let lineCodes = newlineCodesIn (SourceSettings LineSeparated) (Set.fromList ["verse"])
        lineCodes "Full fathom\nfive\n" @?= []
        newlineCodes "Full fathom\nfive\n" @?= ["G05001"]
        lineCodes "- Full fathom\n  five\n" @?= []
        lineCodes "@style quote\n  Full fathom\n  five\n" @?= []
        lineCodes "[note: a\nb] x\n" @?= ["G05001"],
      testCase "G05002 unused variable, unless an importer uses it" $ do
        let defining = FileLint (FileId 1) "common.gm" (fst (parse (FileId 1) "")) defaultSourceSettings usage {usageDefined = [("x", sp), ("y", sp)]}
            importing = FileLint (FileId 2) "ch.gm" (fst (parse (FileId 2) "")) defaultSourceSettings usage {usageImports = [("c", "common.gm", sp)], usageNamespaceRefs = Map.fromList [("c", Set.fromList ["x"])]}
        codes (lint (LintInput [defining, importing] Map.empty Set.empty (Set.fromList ["verse"]))) @?= ["G05002"],
      testCase "G05003 unused import" $ do
        let f = FileLint (FileId 1) "a.gm" (fst (parse (FileId 1) "")) defaultSourceSettings usage {usageImports = [("v", "v.gm", sp)]}
        codes (lint (LintInput [f] Map.empty Set.empty (Set.fromList ["verse"]))) @?= ["G05003"],
      testCase "G05004 unreferenced labels are warnings, errors in prod" $ do
        let ds = lint (LintInput [] (Map.fromList [("a", sp), ("b", sp)]) (Set.fromList ["a"]) (Set.fromList ["verse"]))
        map diagSeverity ds @?= [Warning]
        map (diagSeverity . adjustForProfile Prod) ds @?= [Error]
        coded ds @?= [("G05004", "参照されていないラベルです: b")],
      testGroup
        "exact diagnostics"
        [ testCase "G05001 is the one character of the newline, with its message" $ do
            newlineSpans defaultSourceSettings "This is\nEnglish\n" @?= [("G05001", 7, 8)]
            map diagMessage (latinJoinedByNewline defaultSourceSettings Set.empty (FileId 0) (fst (parse (FileId 0) "a\nb\n")))
              @?= ["改行の前後が欧文なので、単語が空白なしにつながります。一行で書いてください"],
          testCase "G05001 counts the offsets of the blocks and slots before it" $ do
            newlineSpans defaultSourceSettings "日本語。\n\none\ntwo\nthree\n" @?= [("G05001", 17, 18), ("G05001", 21, 22)]
            newlineSpans defaultSourceSettings "- word\n  word\n" @?= [("G05001", 6, 7)]
            newlineSpans defaultSourceSettings "@style verse\n  [note: a\n  b] x\n" @?= [("G05001", 23, 24)]
            newlineSpans (SourceSettings LineSeparated) "x [note: a\nb] y\n" @?= [("G05001", 10, 11)],
          testCase "G05001 stops at commands and expressions" $ do
            newlineSpans defaultSourceSettings "[= 1]word\nword[= 1]\n" @?= [("G05001", 9, 10)]
            newlineSpans defaultSourceSettings "word [= 1]\nword\n" @?= []
            newlineSpans defaultSourceSettings "word\n[= 1] word\n" @?= [],
          testCase "the scripts that count as Latin, at the edges of their blocks" $ do
            let latin = "Az09\x00C0\x00FF\x024F\x1E00\x1EFF\x0370\x03B1\x04FF"
                other = "_ \x00AA\x00BF\x00D7\x0250\x1F00\x0500\x3042漢\xFF10\xFF41"
            filter (not . isLatinScript) latin @?= ""
            filter isLatinScript other @?= "",
          testCase "G05002 names the variable that no one uses" $ do
            let defining = FileLint (FileId 1) "common.gm" (fst (parse (FileId 1) "")) defaultSourceSettings usage {usageDefined = [("x", sp), ("y", sp), ("z", sp)], usageReferenced = Set.fromList ["z"]}
                importing = FileLint (FileId 2) "ch.gm" (fst (parse (FileId 2) "")) defaultSourceSettings usage {usageImports = [("c", "common.gm", sp)], usageNamespaceRefs = Map.fromList [("c", Set.fromList ["x"])]}
            coded (lint (LintInput [defining, importing] Map.empty Set.empty Set.empty)) @?= [("G05002", "使われていない変数です: y")],
          testCase "G05002: a reference through an import of another file does not count" $ do
            let defining = FileLint (FileId 1) "common.gm" (fst (parse (FileId 1) "")) defaultSourceSettings usage {usageDefined = [("x", sp)]}
                importing = FileLint (FileId 2) "ch.gm" (fst (parse (FileId 2) "")) defaultSourceSettings usage {usageImports = [("c", "other.gm", sp)], usageNamespaceRefs = Map.fromList [("c", Set.fromList ["x"])]}
            coded (lint (LintInput [defining, importing] Map.empty Set.empty Set.empty)) @?= [("G05002", "使われていない変数です: x")],
          testCase "G05003 names the import, and a used import is no error" $ do
            let at s = mkSpan (FileId 1) s (s + 1)
                f = FileLint (FileId 1) "a.gm" (fst (parse (FileId 1) "")) defaultSourceSettings usage {usageImports = [("w", "w.gm", at 5), ("v", "v.gm", at 2), ("u", "u.gm", at 8)], usageNamespaceRefs = Map.fromList [("u", Set.fromList ["k"])]}
                ds = lint (LintInput [f] Map.empty Set.empty Set.empty)
            coded ds @?= [("G05003", "使われていない import です: v"), ("G05003", "使われていない import です: w")]
            map (spanStart . diagSpan) ds @?= [2, 5]
        ]
    ]
