-- | The requirements of functions and the handler of file (docs/adr/0161).
module RequirementSpec (requirementTests) where

import Data.Either (isRight)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Emet
import Golem.Syntax
import Support
import Test.Tasty
import Test.Tasty.HUnit

requirementTests :: TestTree
requirementTests =
  testGroup
    "requirements (docs/adr/0161)"
    [ notationTests,
      arrowTests,
      fileReadTests,
      flowTests,
      compositionTests,
      inferenceTests,
      unusedTests,
      handlerTests,
      fmtTests
    ]

-- | The codes of a source, and whether it gave a program.
loads :: Text -> Assertion
loads src = case load src of
  (ds, Just _) | not (any isError ds) -> pure ()
  (ds, _) -> assertFailure (T.unpack (T.unlines [c <> " " <> diagMessage d | d <- ds, let DiagnosticCode c = diagCode d]))

errorCodes :: Text -> [Text]
errorCodes src = [c | d <- fst (load src), isError d, let DiagnosticCode c = diagCode d]

notationTests :: TestTree
notationTests =
  testGroup
    "notation"
    [ testCase "a row after an arrow, a variable alone, and an open row are read" $ do
        loads "f :: String -> <file \"data/words.tsv\"> String\nf s = File.read \"data/words.tsv\" ++ s\n"
        loads "m :: (a -> e b) -> List a -> e (List b)\nm f xs = List.map f xs\n"
        loads "g :: (String -> e String) -> <file \"a.tsv\", file \"b.tsv\"|e> String\ng f = f (File.read \"a.tsv\" ++ File.read \"b.tsv\")\n",
      testCase "the same requirement twice is E05102" $
        codes "f :: Nat -> <file \"a.tsv\", file \"a.tsv\"> Nat\nf x = x\n" @?= ["E05102"],
      testCase "data/./a.tsv and data/a.tsv are the same requirement: E05102" $
        codes "f :: Nat -> <file \"data/./a.tsv\", file \"data/a.tsv\"> Nat\nf x = x\n" @?= ["E05102"],
      testCase "an unknown kind is E05100, with the kinds there are" $ do
        let src = "f :: Nat -> <net, db> Nat\nf x = x\n"
        codes src @?= ["E05100"]
        case messages src of
          [m] -> do
            assertBool (T.unpack m) ("file" `T.isInfixOf` m)
            assertBool (T.unpack m) ("net" `T.isInfixOf` m && "db" `T.isInfixOf` m)
          ms -> assertFailure (show ms),
      testCase "a path outside the root, absolute or a URL is G03003" $ do
        codes "f :: Nat -> <file \"../a.tsv\"> Nat\nf x = x\n" @?= ["G03003"]
        codes "f :: Nat -> <file \"/a.tsv\"> Nat\nf x = x\n" @?= ["G03003"]
        codes "f :: Nat -> <file \"https://example.com/a.tsv\"> Nat\nf x = x\n" @?= ["G03003"],
      testCase "two paths that differ only in case are G03004" $
        codes "f :: Nat -> <file \"a.tsv\", file \"A.tsv\"> Nat\nf x = x\n" @?= ["G03004"],
      testCase "file without one path is E02101" $
        codes "f :: Nat -> <file> Nat\nf x = x\n" @?= ["E02101"],
      testCase "a variable used as a type and as a requirement is E02101" $
        codes "f :: (a -> a a) -> a -> a\nf g x = g x\n" @?= ["E02101"]
    ]

arrowTests :: TestTree
arrowTests =
  testGroup
    "the arrows that take a row"
    [ testCase "a row before the arrow of the body is E05106" $ do
        codes "f :: String -> <file \"a.tsv\"> String -> String\nf x y = x ++ y\n" @?= ["E05106"]
        codes "f :: <file \"a.tsv\"> Nat -> Nat\nf x = x\n" @?= ["E05106"],
      testCase "a row after the arrow of the body is the row of the function returned" $ do
        let src =
              T.unlines
                [ "g :: Nat -> Nat -> <file \"a.tsv\"> String",
                  "g _ _ = File.read \"a.tsv\"",
                  "f :: Nat -> (Nat -> <file \"a.tsv\"> String)",
                  "f x = g x",
                  "keep :: (Nat -> <file \"a.tsv\"> String) -> String",
                  "keep _ = \"\"",
                  "once :: Nat -> String",
                  "once n = keep (f n)",
                  "twice :: Nat -> <file \"a.tsv\"> String",
                  "twice n = f n 2"
                ]
        loads src
        -- f 1 has no requirement; f 1 2 has
        errorCodes (src <> "bad :: Nat -> String\nbad n = f n 2\n") @?= ["E05101"],
      testCase "a function of no arguments takes its row after ::" $
        loads "config :: <file \"data/config.tsv\"> String\nconfig = File.read \"data/config.tsv\"\n"
    ]

fileReadTests :: TestTree
fileReadTests =
  testGroup
    "File.read"
    [ testCase "File.read of a literal has the type <file path> String" $ do
        loads "r :: <file \"data/a.tsv\"> String\nr = File.read \"data/a.tsv\"\n"
        errorCodes "r :: <file \"data/a.tsv\"> Nat\nr = File.read \"data/a.tsv\"\n" @?= ["E02101"]
        errorCodes "r :: String\nr = File.read \"data/a.tsv\"\n" @?= ["E05101"],
      testCase "the path of File.read is normalised" $
        loads "r :: <file \"data/a.tsv\"> String\nr = File.read \"data/./a.tsv\"\n",
      testCase "File.read of a variable is E05107" $
        codes "f :: String -> <file \"a.tsv\"> String\nf path = File.read path\n" @?= ["E05107"],
      testCase "File.read passed as a value is E05107" $
        codes "f :: List String -> <file \"a.tsv\"> List String\nf xs = List.map File.read xs\n" @?= ["E05107"],
      testCase "File.read of a path outside the root is G03003" $
        errorCodes "f :: <file \"a.tsv\"> String\nf = File.read \"../a.tsv\"\n" @?= ["G03003"]
    ]

flowTests :: TestTree
flowTests =
  testGroup
    "how requirements flow"
    [ testCase "a function without a row that calls File.read is E05101 at the call" $ do
        let src = "f :: Nat -> String\nf _ = File.read \"a.tsv\"\n"
        codes src @?= ["E05101"]
        map (spanStart . diagSpan) (fst (load src)) @?= [T.length (fst (T.breakOn "File.read" src))],
      testCase "a call of a function of file \"a.tsv\" from one of <file \"b.tsv\"> is E05101 and names file \"a.tsv\"" $ do
        let src = "a :: Nat -> <file \"a.tsv\"> String\na _ = File.read \"a.tsv\"\nb :: Nat -> <file \"b.tsv\"> String\nb n = a n ++ File.read \"b.tsv\"\n"
        errorCodes src @?= ["E05101"]
        assertBool (show (messages src)) (any ("file \"a.tsv\"" `T.isInfixOf`) (messages src)),
      testCase "naming a function of no arguments with a requirement is a call: E05101" $
        errorCodes "config :: <file \"c.tsv\"> String\nconfig = File.read \"c.tsv\"\nf :: Nat -> String\nf _ = config\n" @?= ["E05101"],
      testCase "a partial application has no requirement" $
        loads "g :: Nat -> Nat -> <file \"a.tsv\"> String\ng _ _ = File.read \"a.tsv\"\nf :: Nat -> Maybe (Nat -> <file \"a.tsv\"> String)\nf n = Just (g n)\n"
    ]

lookupSrc :: Text
lookupSrc =
  T.unlines
    [ "lookupReading :: String -> <file \"data/words.tsv\"> Maybe String",
      "lookupReading w = List.at 0 (List.select (String.startsWith w) (String.lines (File.read \"data/words.tsv\")))"
    ]

compositionTests :: TestTree
compositionTests =
  testGroup
    "composition"
    [ testCase "List.map of a function with file requires it" $ do
        loads (lookupSrc <> "readings :: List String -> <file \"data/words.tsv\"> List (Maybe String)\nreadings ws = List.map lookupReading ws\n")
        errorCodes (lookupSrc <> "readings :: List String -> List (Maybe String)\nreadings ws = List.map lookupReading ws\n") @?= ["E05101"],
      testCase "List.map of a pure function requires nothing" $
        loads "double :: Nat -> Nat\ndouble n = n * 2\nf :: List Nat -> List Nat\nf xs = List.map double xs\n",
      testCase "List.foldl, List.select, List.any and String.map pass the requirements on" $ do
        let src =
              T.unlines
                [ "has :: String -> <file \"w.tsv\"> Bool",
                  "has w = String.contains w (File.read \"w.tsv\")",
                  "count :: Nat -> String -> <file \"w.tsv\"> Nat",
                  "count n w = has w ? n + 1 : n",
                  "up :: Char -> <file \"w.tsv\"> Char",
                  "up c = String.contains (String.fromChar c) (File.read \"w.tsv\") ? 'x' : c",
                  "f :: List String -> <file \"w.tsv\"> (Nat, List String, Bool, String)",
                  "f ws = (List.foldl count 0 ws, List.select has ws, List.any has ws, String.map up \"ab\")"
                ]
        loads src
        errorCodes (T.replace "f :: List String -> <file \"w.tsv\"> (" "f :: List String -> (" src) @?= ["E05101"],
      testCase "a higher-order function of the user with an open row takes functions with and without requirements" $ do
        let src =
              T.unlines
                [ "twice :: (String -> e String) -> String -> e String",
                  "twice f s = f (f s)",
                  "plain :: String -> String",
                  "plain s = s ++ s",
                  "withFile :: String -> <file \"a.tsv\"> String",
                  "withFile s = s ++ File.read \"a.tsv\"",
                  "p :: String -> String",
                  "p s = twice plain s",
                  "q :: String -> <file \"a.tsv\"> String",
                  "q s = twice withFile s"
                ]
        loads src
        errorCodes (src <> "r :: String -> String\nr s = twice withFile s\n") @?= ["E05101"],
      testCase "an open row with more requirements" $
        loads "g :: (String -> e String) -> <file \"a.tsv\"|e> String\ng f = f (File.read \"a.tsv\")\nsame :: String -> String\nsame s = s\nh :: <file \"a.tsv\"> String\nh = g same\n",
      testCase "a function with a requirement passed where a pure one is wanted is E02101" $
        errorCodes (lookupSrc <> "apply :: (String -> Maybe String) -> String -> Maybe String\napply f s = f s\nh :: String -> <file \"data/words.tsv\"> Maybe String\nh s = apply lookupReading s\n") @?= ["E02101"]
    ]

inferenceTests :: TestTree
inferenceTests =
  testGroup
    "inference"
    [ testCase "the requirements of a function of where without a signature are inferred and checked against the signature outside" $ do
        loads "f :: String -> <file \"a.tsv\"> String\nf s = g s\n  where {\n    g x = x ++ File.read \"a.tsv\"\n  }\n"
        errorCodes "f :: String -> String\nf s = g s\n  where {\n    g x = x ++ File.read \"a.tsv\"\n  }\n" @?= ["E05101"],
      testCase "a value of where with a requirement" $ do
        loads "f :: Nat -> <file \"a.tsv\"> List String\nf _ = rows\n  where {\n    rows = String.lines (File.read \"a.tsv\")\n  }\n"
        errorCodes "f :: Nat -> List String\nf _ = rows\n  where {\n    rows = String.lines (File.read \"a.tsv\")\n  }\n" @?= ["E05101"],
      testCase "the variable of a row of where is generalised" $ do
        let src =
              T.unlines
                [ "withFile :: String -> <file \"a.tsv\"> String",
                  "withFile s = s ++ File.read \"a.tsv\"",
                  "plain :: String -> String",
                  "plain s = s",
                  "f :: String -> <file \"a.tsv\"> (String, String)",
                  "f s = (app plain s, app withFile s)",
                  "  where {",
                  "    app h x = h x",
                  "  }",
                  "g :: String -> String",
                  "g s = app plain s",
                  "  where {",
                  "    app h x = h x",
                  "  }"
                ]
        loads src,
      testCase "a binding of where with a signature is checked against it" $
        errorCodes "f :: String -> <file \"a.tsv\"> String\nf s = g s\n  where {\n    g :: String -> String\n    g x = x ++ File.read \"a.tsv\"\n  }\n" @?= ["E05101"]
    ]

unusedTests :: TestTree
unusedTests =
  testGroup
    "requirements not used"
    [ testCase "a requirement of a closed row that the body does not use is the info E05108" $ do
        let src = "f :: Nat -> <file \"a.tsv\", file \"b.tsv\"> String\nf _ = File.read \"a.tsv\"\n"
            (ds, p) = load src
        [(c, diagSeverity d) | d <- ds, let { DiagnosticCode c = diagCode d }] @?= [("E05108", Info)]
        assertBool "a program" (isJust p)
        assertBool (show ds) (all (\d -> "f" `T.isInfixOf` diagMessage d && "file \"b.tsv\"" `T.isInfixOf` diagMessage d) ds)
        map (spanStart . diagSpan) ds @?= [T.length (fst (T.breakOn "file \"b.tsv\"" src))],
      testCase "a variable of an open row that is not used is no info" $
        load "f :: (Nat -> e Nat) -> Nat -> <file \"a.tsv\"|e> String\nf _ _ = File.read \"a.tsv\"\n" `hasCodes` []
    ]
  where
    hasCodes l cs = codesOf l @?= cs

handlerTests :: TestTree
handlerTests =
  testGroup
    "the handler of file"
    [ testCase "File.read returns the text the handler gives" $ do
        let src = "f :: Nat -> <file \"data/a.tsv\"> String\nf _ = File.read \"data/./a.tsv\"\n"
            hs = fileHandlers (Map.fromList [("data/a.tsv", "一\t二\n")])
        r <- callWith hs [("main.emet", src)] "f" [nat 0] >>= ok
        r @?= str "一\t二\n",
      testCase "a function with a requirement given to List.map reads through the handler" $ do
        let src = lookupSrc <> "readings :: List String -> <file \"data/words.tsv\"> List (Maybe String)\nreadings ws = List.map lookupReading ws\n"
            hs = fileHandlers (Map.fromList [("data/words.tsv", "かな\tkana\nもじ\tmoji\n")])
        r <- callWith hs [("main.emet", src)] "readings" [RList [str "もじ", str "なし"]] >>= ok
        r @?= RList [RCon "Just" [str "もじ\tmoji"], RCon "Nothing" []],
      testCase "a path the handler does not have is E05104 at the call" $ do
        let src = "f :: Nat -> <file \"data/a.tsv\"> String\nf _ = File.read \"data/a.tsv\"\n"
        d <- callWith noHandlers [("main.emet", src)] "f" [nat 0] >>= failure
        diagCode d @?= DiagnosticCode "E05104"
        diagSpan d @?= callSpan,
      testCase "the requirements of the signatures of a program, at their places" $ do
        let src = "f :: Nat -> <file \"data/./a.tsv\"> String\nf _ = File.read \"data/a.tsv\"\n"
        case load src of
          (_, Just p) -> do
            map fst (programRequirements p) @?= [ReqFile "data/a.tsv"]
            map (spanStart . snd) (programRequirements p) @?= [T.length (fst (T.breakOn "file \"data" src))]
          (ds, Nothing) -> assertFailure (show ds)
    ]

fmtTests :: TestTree
fmtTests =
  testGroup
    "fmt"
    [ testCase "fmt sorts the requirements of a row by their kinds and paths" $
        formatEmet "f :: Nat -> <file \"b.tsv\", file \"a.tsv\"|e> Nat\nf x = x\n"
          @?= Right "f :: Nat -> <file \"a.tsv\", file \"b.tsv\"|e> Nat\nf x = x\n",
      testCase "a row with a comment in it is left as it is" $
        isRight (formatEmet "f :: Nat -> <file \"b.tsv\", -- b\n  file \"a.tsv\"> Nat\nf x = x\n") @?= True
    ]
