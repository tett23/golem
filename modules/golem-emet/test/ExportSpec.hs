{- | The functions .gm uses (docs/adr/0162): the kinds of pub, the names of
commands, the arguments, the keyword and the variable arguments, and the
errors of their declarations (E06100 to E06106).
-}
module ExportSpec (exportTests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Emet
import Golem.Syntax
import Support
import Test.Tasty
import Test.Tasty.HUnit

exportTests :: TestTree
exportTests =
  testGroup
    "the functions .gm uses (docs/adr/0162)"
    [ nameTests,
      resultTests,
      argumentTests,
      keywordTests,
      varargsTests,
      fnTests,
      kindTests
    ]

-- | The kinds and the names of commands main.emet exports.
exported :: Text -> IO [(Kind, Text, Text)]
exported src = case load src of
  (ds, Just p) | not (any isError ds) -> pure [(exKind e, exName e, exFunction e) | e <- Map.findWithDefault [] "main.emet" (programExports p)]
  (ds, _) -> assertFailure (show ds) >> fail "unreachable"

nameTests :: TestTree
nameTests =
  testGroup
    "the names of commands"
    [ testCase "a string names the command; .emet calls the function by its own name" $ do
        let src =
              T.unlines
                [ "pub inline \"tax-included\" taxIncluded :: Nat -> Inlines",
                  "taxIncluded n = Inline.text (String.fromNat n)",
                  "",
                  "twice :: Nat -> Inlines",
                  "twice n = taxIncluded n ++ taxIncluded n",
                  "",
                  "pub inline price :: Nat -> Inlines",
                  "price n = twice n"
                ]
        exported src >>= (@?= [(KindInline, "tax-included", "taxIncluded"), (KindInline, "price", "price")]),
      testCase "a name against the rule of .gm is E06100" $ do
        codes "pub inline \"Tax\" tax :: Nat -> Inlines\ntax n = []\n" @?= ["E06100"]
        codes "pub inline \"tax_included\" tax :: Nat -> Inlines\ntax n = []\n" @?= ["E06100"]
        codes "pub inline taxIncluded :: Nat -> Inlines\ntaxIncluded n = []\n" @?= ["E06100"],
      testCase "the message of a function name against the rule shows the string" $
        assertBool "a hint" (any ("pub inline \"" `T.isInfixOf`) (messages "pub inline taxIncluded :: Nat -> Inlines\ntaxIncluded n = []\n")),
      testCase "two commands of one name are E06106; an inline and a block one are not" $ do
        codes "pub inline \"a\" f :: Inlines\nf = []\n\npub inline \"a\" g :: Inlines\ng = []\n" @?= ["E06106"]
        codes "pub inline \"a\" f :: Inlines\nf = []\n\npub block \"a\" g :: Blocks\ng = []\n" @?= []
    ]

resultTests :: TestTree
resultTests =
  testGroup
    "the types of the results"
    [ testCase "pub inline that returns String is E06101" $
        codes "pub inline f :: String\nf = \"x\"\n" @?= ["E06101"],
      testCase "pub filter that is Blocks -> Inlines is E06101" $
        codes "pub filter f :: Blocks -> Inlines\nf _ = []\n" @?= ["E06101"],
      testCase "pub filter of Blocks -> Blocks, with requirements or not" $ do
        codes "pub filter f :: Blocks -> Blocks\nf bs = bs\n" @?= []
        codes "pub filter f :: Blocks -> <file \"a.tsv\"> Blocks\nf bs = bs ++ Block.paragraph (Inline.text (File.read \"a.tsv\"))\n" @?= [],
      testCase "pub block returns Blocks" $
        codes "pub block f :: Inlines\nf = []\n" @?= ["E06101"]
    ]

argumentTests :: TestTree
argumentTests =
  testGroup
    "the arguments"
    [ testCase "Inlines before Nat is E06102" $
        codes "pub inline f :: Inlines -> Nat -> Inlines\nf xs _ = xs\n" @?= ["E06102"],
      testCase "an argument of a type .gm cannot pass is E06102" $
        codes "pub inline f :: Maybe Nat -> Inlines\nf _ = []\n" @?= ["E06102"],
      testCase "a block command takes the body as its last Blocks" $ do
        codes "pub block f :: String -> Blocks -> Blocks\nf _ bs = bs\n" @?= []
        codes "pub block f :: Blocks -> String -> Blocks\nf bs _ = bs\n" @?= ["E06102"],
      testCase "prose slots of an inline command" $
        codes "pub inline f :: Nat -> Inlines -> Inlines -> Inlines\nf _ a b = a ++ b\n" @?= []
    ]

priceSrc :: Text
priceSrc =
  T.unlines
    [ "pub inline price :: Nat -> (tax :: Bool = True) -> (\"unit-name\" :: String = \"円\") -> Inlines",
      "price n tax unit = Inline.text (String.fromNat n ++ unit ++ (tax ? \"（税込）\" : \"\"))",
      "",
      "pub fromInside :: Inlines",
      "fromInside = price 1000 True \"円\""
    ]

keywordTests :: TestTree
keywordTests =
  testGroup
    "keyword arguments"
    [ testCase "keyword arguments with defaults; .emet passes them by place" $ do
        codes priceSrc @?= []
        r <- call priceSrc "fromInside" [] >>= ok
        case r of
          RList [RCon "Text" (RPrim _ : _)] -> pure ()
          other -> assertFailure (show other),
      testCase "a keyword argument without a default is E06103" $
        codes "pub inline f :: (tax :: Bool) -> Inlines\nf _ = []\n" @?= ["E06103"],
      testCase "a keyword argument after a prose slot is E06103" $
        codes "pub inline f :: Inlines -> (tax :: Bool = True) -> Inlines\nf xs _ = xs\n" @?= ["E06103"],
      testCase "a keyword argument of pub fn is E06103" $
        codes "pub fn f :: (tax :: Bool = True) -> Nat\nf _ = 1\n" @?= ["E06103"],
      testCase "a keyword argument of a function .gm does not call is E06103" $
        codes "pub f :: (tax :: Bool = True) -> Nat\nf _ = 1\n" @?= ["E06103"],
      testCase "a default of another type is E06103" $
        codes "pub inline f :: (tax :: Bool = 1) -> Inlines\nf _ = []\n" @?= ["E06103"],
      testCase "a name of a keyword argument against the rule is E06100" $
        codes "pub inline f :: (\"Tax\" :: Bool = True) -> Inlines\nf _ = []\n" @?= ["E06100"]
    ]

varargsTests :: TestTree
varargsTests =
  testGroup
    "variable arguments"
    [ testCase "Varargs twice is E06105" $
        codes "pub inline f :: Varargs Nat -> Varargs Nat -> Inlines\nf _ _ = []\n" @?= ["E06105"],
      testCase "a positional argument after Varargs is E06105" $
        codes "pub inline f :: Varargs Nat -> Nat -> Inlines\nf _ _ = []\n" @?= ["E06105"],
      testCase "Varargs of a bare pub is E06105" $
        codes "pub f :: Varargs Nat -> Nat\nf _ = 1\n" @?= ["E06105"],
      testCase "Varargs in a field of a data type is E06105" $
        codes "data T = T (Varargs Nat)\n" @?= ["E06105"],
      testCase "Varargs a is List a" $ do
        let src =
              T.unlines
                [ "pub fn sum :: Varargs Nat -> Nat",
                  "sum [] = 0",
                  "sum (x : xs) = x + sum xs",
                  "",
                  "total :: List Nat -> Nat",
                  "total xs = sum xs",
                  "",
                  "pub six :: Nat",
                  "six = total [1, 2, 3]"
                ]
        codes src @?= []
        call src "six" [] >>= ok >>= (@?= nat 6),
      testCase "Varargs before keyword arguments and prose slots" $
        codes "pub inline tags :: String -> Varargs String -> (sep :: String = \"、\") -> Inlines -> Inlines\ntags _ _ _ xs = xs\n" @?= []
    ]

fnTests :: TestTree
fnTests =
  testGroup
    "pub fn"
    [ testCase "an argument of Maybe Nat is E06102" $
        codes "pub fn f :: Maybe Nat -> Nat\nf _ = 1\n" @?= ["E06102"],
      testCase "a result of Inlines is E06101" $
        codes "pub fn f :: Nat -> Inlines\nf _ = []\n" @?= ["E06101"],
      testCase "a result of a list of numbers" $
        codes "pub fn f :: Nat -> List Nat\nf n = [n]\n" @?= []
    ]

kindTests :: TestTree
kindTests =
  testGroup
    "the kinds"
    [ testCase "two kinds are a syntax error" $
        codes "pub inline fn f :: Inlines\nf = []\n" @?= ["E01100"],
      testCase "a bare pub function is not exported" $
        exported "pub f :: Inlines\nf = []\n" >>= (@?= []),
      testCase "every kind" $ do
        let src =
              T.unlines
                [ "pub inline i :: Inlines",
                  "i = []",
                  "",
                  "pub block b :: Blocks",
                  "b = []",
                  "",
                  "pub filter \"keep\" k :: Blocks -> Blocks",
                  "k bs = bs",
                  "",
                  "pub fn total :: List Nat -> Nat",
                  "total xs = List.foldl add 0 xs",
                  "  where {",
                  "    add a b = a + b",
                  "  }"
                ]
        exported src >>= (@?= [(KindInline, "i", "i"), (KindBlock, "b", "b"), (KindFilter, "keep", "k"), (KindFn, "total", "total")])
    ]
