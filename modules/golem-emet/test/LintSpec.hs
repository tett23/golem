-- | The lint of .emet (docs/adr/0162): E07100 to E07102.
module LintSpec (lintTests) where

import Data.Text (Text)
import Data.Text qualified as T
import Golem.Emet.Lint (lintProgram)
import Golem.Syntax
import Support
import Test.Tasty
import Test.Tasty.HUnit

-- | The codes of the lint of main.emet and the files it imports.
lintCodes :: [(FilePath, Text)] -> IO [Text]
lintCodes files = case loadMany files of
  (ds, Just p) | not (any isError ds) -> pure [c | DiagnosticCode c <- map diagCode (lintProgram p)]
  (ds, _) -> assertFailure (show ds) >> fail "unreachable"

lintOf :: Text -> IO [Text]
lintOf src = lintCodes [("main.emet", src)]

lintTests :: TestTree
lintTests =
  testGroup
    "the lint of .emet (docs/adr/0162)"
    [ testCase "an unused top-level function without pub is E07100" $
        lintOf (T.unlines ["helper :: Nat", "helper = 1", "", "pub f :: Nat", "f = 2"]) >>= (@?= ["E07100"]),
      testCase "a function used only by itself is unused" $
        lintOf (T.unlines ["go :: Int -> Int", "go k", "  | k <= 0 = 0", "  | otherwise = go (k - 1)"]) >>= (@?= ["E07100"]),
      testCase "a recursive function used by another is used" $
        lintOf (T.unlines ["count :: List Nat -> Nat", "count [] = 0", "count (_ : xs) = 1 + count xs", "", "pub f :: Nat", "f = count [1]"]) >>= (@?= []),
      testCase "an unused data type without pub is E07100; a used one is not" $ do
        lintOf (T.unlines ["data T = A | B", "", "pub f :: Nat", "f = 1"]) >>= (@?= ["E07100"])
        lintOf (T.unlines ["data T = A | B", "", "pub f :: Bool", "f = isA A", "", "isA :: T -> Bool", "isA A = True", "isA B = False"]) >>= (@?= []),
      testCase "an unused function with pub is no error" $
        lintOf (T.unlines ["pub f :: Nat", "f = 1", "", "pub inline g :: Inlines", "g = []"]) >>= (@?= []),
      testCase "an unused import is E07101" $ do
        lintCodes [("main.emet", "import \"lib.emet\"\n\npub f :: Nat\nf = 1\n"), ("lib.emet", "pub g :: Nat\ng = 2\n")] >>= (@?= ["E07101"])
        lintCodes [("main.emet", "import \"lib.emet\"\n\npub f :: Nat\nf = g\n"), ("lib.emet", "pub g :: Nat\ng = 2\n")] >>= (@?= []),
      testCase "an unused variable of a pattern is E07102, but one that starts with _" $ do
        lintOf (T.unlines ["pub f :: Nat -> Nat -> Nat", "f x y = x"]) >>= (@?= ["E07102"])
        lintOf (T.unlines ["pub f :: Nat -> Nat -> Nat", "f x _y = x"]) >>= (@?= [])
        lintOf (T.unlines ["pub f :: Maybe Nat -> Nat", "f m = case m of {", "  Just n -> 1", "  Nothing -> 0", "}"]) >>= (@?= ["E07102"]),
      testCase "an unused binding of where is the notice E02109, no error of lint" $ do
        let src = T.unlines ["pub f :: Nat", "f = 1", "  where {", "    unused = 2", "  }"]
        codes src @?= ["E02109"]
        lintOf src >>= (@?= [])
    ]
