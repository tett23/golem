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
word = Gen.element ["語", "word", "漢字", "\\a", "\\[", "x", "日本語の文", "##36##", "\\##1##"]

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

-- | Lines joined by newlines, some of them hard breaks (docs/adr ADR 0016).
paragraphLines :: Text -> Gen Text
paragraphLines indent = do
  ls <- Gen.list (Range.linear 1 3) line
  ends <- Gen.list (Range.singleton (length ls - 1)) (Gen.element ["\n", "\\\n", " \\\n"])
  pure (T.concat (zipWith (\l e -> l <> e <> indent) ls ends) <> last ls)

block :: Gen Text
block =
  Gen.choice
    [ paragraphLines "",
      ("- " <>) <$> paragraphLines "  ",
      (\l s -> "# " <> l <> s) <$> line <*> spaces,
      (\items -> T.intercalate "\n" ["- " <> i | i <- items]) <$> Gen.list (Range.linear 1 3) line,
      (\s1 s2 -> "@toc" <> s1 <> "depth=2" <> s2) <$> Gen.element [" ", "   "] <*> spaces,
      (\s -> "@set" <> s <> "v = 1") <$> Gen.element [" ", "    "],
      (\name stanzas -> name <> "\n" <> T.intercalate "\n\n" [T.intercalate "\n" ["  " <> l | l <- ls] | ls <- stanzas]) <$> Gen.element ["@style verse", "@verse"] <*> Gen.list (Range.linear 1 2) (Gen.list (Range.linear 1 3) line),
      pure "```\n  code  \n```",
      (\s1 s2 -> "|" <> s1 <> "a|b" <> s2 <> "|\n|---|---|\n|1" <> s2 <> "|" <> s1 <> "2|") <$> spaces <*> spaces
    ]

-- | The file settings at the top of a file (docs/adr ADR 0014).
settings :: Gen Text
settings = do
  ls <-
    Gen.list
      (Range.linear 0 3)
      ( Gen.choice
          [ (\s1 s2 -> "@manifest" <> s1 <> "paragraph-separator=line" <> s2) <$> Gen.element [" ", "   "] <*> spaces,
            (\s1 s2 s3 -> "@style-def" <> s1 <> "paragraph" <> s2 <> "letter" <> s3 <> "indent=1zw") <$> Gen.element [" ", "   "] <*> Gen.element [" ", "  "] <*> Gen.element [" ", "   "],
            pure "@style-def character term synthetic-bold=true"
          ]
      )
  end <- Gen.element ["\n", "\n\n"]
  pure (if null ls then "" else T.intercalate "\n" ls <> end)

document :: Gen Text
document = do
  header <- settings
  bs <- Gen.list (Range.linear 0 6) block
  seps <- Gen.list (Range.singleton (length bs)) (Gen.element ["\n\n", "\n\n\n", "\n \n\n"])
  lead <- Gen.element ["", "\n", "\n\n"]
  end <- Gen.element ["", "\n", "\n\n\n"]
  pure (lead <> header <> T.concat (zipWith (<>) bs seps) <> end)

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
    [ -- the escapes the formatter may remove are made text first (golem-parser ADR 0010)
      testProperty "output is unchanged: the AST is preserved" $ property $ do
        src <- forAll document
        case format src of
          Formatted r -> astFingerprintWith removableEscape r === astFingerprintWith removableEscape (preprocess src)
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
          golden "table-spacing" "| a|b |\n|---|:-:|\n|1|  2|\n",
          golden "file-settings" "@manifest   paragraph-separator=line\n@style-def   paragraph  letter   indent=1zw\n\n本文。\n",
          golden "verse" "@style verse\n\tFull fathom five thy father lies;  \n\tOf his bones are coral made;\t\n\n\n  Nothing of him that doth fade,\n  But doth suffer a sea-change \n",
          -- docs/adr ADR 0016
          golden "hard-breaks" "a\\\nb\n\n- a\\\n  b\n",
          -- docs/adr ADR 0046
          golden "blank-line-command" "あ\n@blank-line\nい\n\n@blank-line  2\n"
        ],
      testCase "@blank-line right after a paragraph is kept as written (docs/adr ADR 0046)" $
        formatted "あ\n@blank-line\nい\n" @?= "あ\n@blank-line\nい\n",
      testCase "BOM, CRLF and tab indentation are fixed" $
        formatted "\xFEFF- a\r\n\t- b\r\n" @?= "- a\n  - b\n",
      -- golem-fmt ADR 0003
      testCase "a lone CR becomes LF; CRLF stays one line break" $ do
        formatted "a\rb\n" @?= "a\nb\n"
        formatted "a\r\nb\n" @?= "a\nb\n"
        formatted "a\r\r\nb\n" @?= "a\n\nb\n"
        formatted "a\r" @?= "a\n",
      testCase "only the BOM at the start and only the tabs of the indentation are fixed" $ do
        formatted "a\xFEFF\&b\n" @?= "a\xFEFF\&b\n"
        formatted "\xFEFF\xFEFF\&a\n" @?= "\xFEFF\&a\n"
        formatted "a\tb\n" @?= "a\tb\n"
        formatted "- a\n\t\t- b\tc\n" @?= "- a\n    - b\tc\n",
      testCase "an empty file stays empty; a file of blank lines becomes empty" $ do
        formatted "" @?= ""
        formatted "\n\n\n" @?= "",
      testCase "the escape of every digit stays" $
        mapM_ (\d -> formatted ("\\" <> T.singleton d <> "\n") @?= "\\" <> T.singleton d <> "\n") ['0' .. '9'],
      testCase "a file with syntax errors is not formatted" $
        case format "[strong: a\n" of
          Unformattable ds -> assertBool "diagnostics" (not (null ds))
          Formatted r -> assertFailure ("formatted: " <> show r),
      -- golem-parser ADR 0011
      testCase "##36## and [number-text 36] are kept; the escape of \\##1## stays" $ do
        formatted "##36##\n" @?= "##36##\n"
        formatted "[number-text 36]\n" @?= "[number-text 36]\n"
        formatted "\\##1##\n" @?= "\\##1##\n",
      -- golem-parser ADR 0013
      testCase "**[...] after a keyword argument is formatted" $
        case format "[f k=v **[h]]\n" of
          Formatted _ -> pure ()
          Unformattable ds -> assertFailure (show ds),
      testGroup
        "@verse is not rewritten (ADR 0002)"
        [ testCase "@verse keeps its name" $
            formatted "@verse\n  a\n" @?= "@verse\n  a\n",
          testCase "only the formatting rules apply to @verse" $
            formatted "@verse   \n  a  \n" @?= "@verse\n  a\n",
          testCase "the AST of the source is kept" $
            let src = "@label song\n@verse\n  Full fathom five\n"
             in case format src of
                  Formatted r -> astFingerprint r @?= astFingerprint src
                  Unformattable ds -> assertFailure (show ds)
        ],
      testGroup
        "escapes in the AST (golem-parser ADR 0010)"
        [ testCase "an escape of a plain character is removed" $
            formatted "\\あ\n" @?= "あ\n",
          testCase "escapes the evaluation reads are kept" $ do
            formatted "[ruby: a\\/b | えー]\n" @?= "[ruby: a\\/b | えー]\n"
            formatted "a\\ \n" @?= "a\\ \n"
            formatted "\\# 見出しではない\n" @?= "\\# 見出しではない\n",
          testCase "the characters the evaluation tells apart by an escape are not removable" $
            mapM_ (\c -> assertBool (show c) (not (removableEscape c))) ['/', ' ', '\t']
        ],
      testCase "code blocks and comments are untouched" $
        formatted "```\n  a   \n```\n\n本文%%  コメント   %%\n" @?= "```\n  a   \n```\n\n本文%%  コメント   %%\n"
    ]
