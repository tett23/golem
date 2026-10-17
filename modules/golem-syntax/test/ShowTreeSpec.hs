-- | The tree of a derived Show (golem-cli ADR 0007).
module ShowTreeSpec (tests) where

import Data.Ratio ((%))
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Syntax
import Golem.Syntax.ShowTree (showTree)
import Test.Tasty
import Test.Tasty.HUnit

data R = R {rInt :: Int, rList :: [Maybe Double], rPair :: (Int, String), rRatio :: Rational, rChar :: Char}
  deriving stock (Show)

newtype W = W String
  deriving stock (Show)

data A = A Int (Maybe Int) [Int]
  deriving stock (Show)

-- | The shape of golem-parser's Located.
data L a = Located {locSpan :: SrcSpan, locValue :: a}
  deriving stock (Show)

tree :: (Show a) => a -> Text
tree = showTree (FileId 0) . show

tests :: TestTree
tests =
  testGroup
    "ShowTree (golem-cli ADR 0007)"
    [ testCase "records, lists, tuples, negative numbers, ratios and characters are read" $
        tree (R (-3) [Just 1.5e-3, Nothing] (4, "x") (1 % 2) 'y')
          @?= "R {rInt = -3, rList = [Just 1.5e-3, Nothing], rPair = (4, \"x\"), rRatio = 1 % 2, rChar = 'y'}",
      testCase "a negative argument and a constructor argument keep their parentheses" $
        tree (A (-1) (Just 2) []) @?= "A (-1) (Just 2) []",
      testCase "one line up to 100 columns, a tree beyond" $ do
        let fits = W (replicate (100 - length ("W \"\"" :: String)) 'a')
            over = W (replicate (101 - length ("W \"\"" :: String)) 'a')
        T.length (tree fits) @?= 100
        T.lines (tree over) @?= ["W", "  \"" <> T.replicate 97 "a" <> "\""],
      testCase "a record that does not fit has a field per line, a long list an item per line" $
        T.lines (tree (R 1 (replicate 20 (Just 1)) (2, "z") 3 'c'))
          @?= [ "R",
                "  rInt = 1",
                "  rList =",
                "    - Just 1.0",
                "    - Just 1.0",
                "    - Just 1.0",
                "    - Just 1.0",
                "    - Just 1.0",
                "    - Just 1.0",
                "    - Just 1.0",
                "    - Just 1.0",
                "    - Just 1.0",
                "    - Just 1.0",
                "    - Just 1.0",
                "    - Just 1.0",
                "    - Just 1.0",
                "    - Just 1.0",
                "    - Just 1.0",
                "    - Just 1.0",
                "    - Just 1.0",
                "    - Just 1.0",
                "    - Just 1.0",
                "    - Just 1.0",
                "  rPair = (2, \"z\")",
                "  rRatio = 3 % 1",
                "  rChar = 'c'"
              ],
      testCase "the empty list" $ tree ([] :: [Int]) @?= "[]",
      testCase "Japanese is written as it is; quotes, backslashes and newlines are escaped" $ do
        tree (W "本文\"\\\n1") @?= "W \"本文\\\"\\\\\\n1\""
        tree 'あ' @?= "'あ'",
      testCase "spans of the file, of other files, and located values" $ do
        tree (SrcSpan (FileId 0) 3 9) @?= "@3..9"
        tree (SrcSpan (FileId 2) 1 2) @?= "@2:1..2"
        tree (Located (SrcSpan (FileId 0) 0 9) (W "x")) @?= "W \"x\" @0..9"
        tree [Located (SrcSpan (FileId 0) 0 9) (Just (1 :: Int))] @?= "[Just 1 @0..9]",
      testCase "a string it cannot read is returned as it is" $ do
        showTree (FileId 0) "Foo {a = 1" @?= "Foo {a = 1"
        showTree (FileId 0) "<function>" @?= "<function>"
    ]
