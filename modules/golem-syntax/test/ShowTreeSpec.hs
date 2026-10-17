-- | The tree of a derived Show (golem-cli ADR 0007).
module ShowTreeSpec (tests) where

import Data.Ratio ((%))
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Syntax
import Golem.Syntax.ShowTree (showTree)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog

data R = R {rInt :: Int, rList :: [Maybe Double], rPair :: (Int, String), rRatio :: Rational, rChar :: Char}
  deriving stock (Show)

newtype W = W String
  deriving stock (Show)

data A = A Int (Maybe Int) [Int]
  deriving stock (Show)

-- | A record with one field, for the width of a field line.
newtype F = F {f :: W}
  deriving stock (Show)

-- | A value that derives Read too, so that a one-line tree can be read back.
data B = B Int (Maybe Int) [Int] (Int, Maybe Int)
  deriving stock (Eq, Show, Read)

{- | Characters that a string literal escapes in different ways: ASCII
controls, a digit after a numeric escape, \SO before H, quotes,
backslashes, Japanese, and characters that are not printable.
-}
genChar :: Gen Char
genChar =
  Gen.frequency
    [ (3, Gen.element ("aH1\"\\'\n\t\SO\DEL\200\x200B\xFEFF本" :: String)),
      (1, Gen.enumBounded),
      (1, Gen.ascii)
    ]

genB :: Gen B
genB =
  B
    <$> int
    <*> Gen.maybe int
    <*> Gen.list (Range.linear 0 3) int
    <*> ((,) <$> int <*> Gen.maybe int)
  where
    int = Gen.int (Range.linearFrom 0 (-99) 99)

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
      testCase "a string or a character with a space is an argument without parentheses, as derived Show writes it" $ do
        tree (W "a b") @?= "W \"a b\""
        tree (Just ' ') @?= "Just ' '",
      testCase "spans of the file, of other files, and located values" $ do
        tree (SrcSpan (FileId 0) 3 9) @?= "@3..9"
        tree (SrcSpan (FileId 2) 1 2) @?= "@2:1..2"
        tree (Located (SrcSpan (FileId 0) 0 9) (W "x")) @?= "W \"x\" @0..9"
        tree [Located (SrcSpan (FileId 0) 0 9) (Just (1 :: Int))] @?= "[Just 1 @0..9]",
      testCase "a field line counts its indentation: 100 columns fit, 101 do not" $ do
        -- "  f = W \"" and "\"" are 10 columns around 90 a's
        T.lines (tree (F (W (replicate 90 'a')))) @?= ["F", "  f = W \"" <> T.replicate 90 "a" <> "\""]
        T.lines (tree (F (W (replicate 91 'a')))) @?= ["F", "  f =", "    W \"" <> T.replicate 91 "a" <> "\""],
      testProperty "a string literal reads back as the same string" $ property $ do
        s <- forAll (Gen.string (Range.linear 0 30) genChar)
        read (dropWhile (/= '"') (T.unpack (tree (W s)))) === s,
      testProperty "a character literal reads back as the same character" $ property $ do
        c <- forAll genChar
        read (T.unpack (tree c)) === c,
      testProperty "a tree on one line reads back as the same value" $ property $ do
        b <- forAll genB
        read (T.unpack (tree b)) === b,
      testCase "a string it cannot read is returned as it is" $ do
        showTree (FileId 0) "Foo {a = 1" @?= "Foo {a = 1"
        showTree (FileId 0) "<function>" @?= "<function>"
    ]
