module Main (main) where

import Data.ByteString.Lazy qualified as BL
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Fmt
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Test.Tasty
import Test.Tasty.Golden (goldenVsString)
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testProperty)

main :: IO ()
main = defaultMain tests

spaces :: Gen Text
spaces = Gen.element ["", " ", "  ", "   "]

word :: Gen Text
word = Gen.element ["語", "word", "漢字", "\\a", "\\[", "x", "日本語の文"]

inline :: Gen Text
inline =
  Gen.choice
    [ T.unwords <$> Gen.list (Range.linear 1 3) word,
      (\s1 w s2 -> "[strong" <> s1 <> ":" <> s2 <> w <> "]") <$> spaces <*> word <*> spaces,
      (\s1 s2 s3 a b -> "[ruby" <> s1 <> "漢字" <> s2 <> ":" <> s3 <> a <> "|" <> s3 <> b <> "]") <$> Gen.element [" ", "  "] <*> spaces <*> spaces <*> word <*> word,
      (\s -> "[=" <> s <> "1 + 2" <> s <> "]") <$> spaces
    ]

line :: Gen Text
line = ((<>) . T.concat <$> Gen.list (Range.linear 1 3) inline) <*> spaces

block :: Gen Text
block =
  Gen.choice
    [ T.intercalate "\n" <$> Gen.list (Range.linear 1 3) line,
      (\l s -> "# " <> l <> s) <$> line <*> spaces,
      (\items -> T.intercalate "\n" ["- " <> i | i <- items]) <$> Gen.list (Range.linear 1 3) line,
      (\s1 s2 -> "@toc" <> s1 <> "depth=2" <> s2) <$> Gen.element [" ", "   "] <*> spaces,
      (\s -> "@set" <> s <> "v = 1") <$> Gen.element [" ", "    "],
      pure "```\n  code  \n```",
      (\s1 s2 -> "|" <> s1 <> "a|b" <> s2 <> "|\n|---|---|\n|1" <> s2 <> "|" <> s1 <> "2|") <$> spaces <*> spaces
    ]

document :: Gen Text
document = do
  bs <- Gen.list (Range.linear 0 6) block
  seps <- Gen.list (Range.singleton (length bs)) (Gen.element ["\n\n", "\n\n\n", "\n \n\n"])
  lead <- Gen.element ["", "\n", "\n\n"]
  end <- Gen.element ["", "\n", "\n\n\n"]
  pure (lead <> T.concat (zipWith (<>) bs seps) <> end)

formatted :: Text -> Text
formatted t = case format t of
  Formatted r -> r
  Unformattable _ -> t

golden :: String -> Text -> TestTree
golden name src = goldenVsString name ("test/golden/" <> name <> ".gm") (pure (BL.fromStrict (TE.encodeUtf8 (formatted src))))

tests :: TestTree
tests =
  testGroup
    "golem-fmt (ADR 0001)"
    [ testProperty "output is unchanged: the AST is preserved" $ property $ do
        src <- forAll document
        case format src of
          Formatted r -> astFingerprint r === astFingerprint (preprocess src)
          Unformattable _ -> discard,
      testProperty "idempotent" $ property $ do
        src <- forAll document
        let once = formatted src
        formatted once === once,
      testGroup
        "rules"
        [ golden "blank-lines" "\n\n# 見出し\n\n\n\n本文\n\n \n\n次の段落",
          golden "command-spacing" "[strong:   a] と [ruby   漢字  :かん|  じ]。[= 1 ]\n\n@toc    depth=2   \n\n@set   v = 1\n",
          golden "escapes" "\\a\\漢\\[\\]\\\\\\%と\\1\n\n\\1. 番号ではない\n",
          golden "trailing-whitespace" "@toc depth=2   \n\n- a  \n- b\t\n\n本文。  \n続き。 \n",
          golden "table-spacing" "| a|b |\n|---|:-:|\n|1|  2|\n"
        ],
      testCase "BOM, CRLF and tab indentation are fixed" $
        formatted "\xFEFF- a\r\n\t- b\r\n" @?= "- a\n  - b\n",
      testCase "a file with syntax errors is not formatted" $
        case format "[strong: a\n" of
          Unformattable ds -> assertBool "diagnostics" (not (null ds))
          Formatted r -> assertFailure ("formatted: " <> show r),
      testCase "code blocks and comments are untouched" $
        formatted "```\n  a   \n```\n\n本文%%  コメント   %%\n" @?= "```\n  a   \n```\n\n本文%%  コメント   %%\n"
    ]
