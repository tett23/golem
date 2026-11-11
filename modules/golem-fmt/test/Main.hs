module Main (main) where

import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Fmt
import Golem.Parser (parse)
import Golem.Syntax
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Peg.Grammar qualified as Grammar
import Peg.Grammar.Parser (parseGrammar)
import Test.Tasty
import Test.Tasty.Golden (goldenVsString)
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testProperty)

main :: IO ()
main = defaultMain tests

-- The alternatives come from the grammar used by the parser, not a second
-- handwritten list of accepted heading marks (Golem ADR 0310).
grammarHeadings :: IO [Text]
grammarHeadings = do
  source <- TIO.readFile "../golem-parser/grammar/Golem.hpeg"
  grammar <- either (fail . show) pure (parseGrammar source)
  let hashRules = [rule | rule <- Grammar.grammarRules grammar, Grammar.ruleName rule == "HashMark"]
  case hashRules of
    [rule] -> mapM headingLiteral (Grammar.ruleAlts rule)
    _ -> fail ("HashMark: expected one rule, found " <> show (length hashRules))
  where
    headingLiteral alt = case Grammar.altItems alt of
      [item] -> case Grammar.itemExpr item of
        Grammar.ELit literal _ -> pure literal
        expression -> fail ("HashMark: unsupported expression " <> show expression)
      items -> fail ("HashMark: unsupported alternative " <> show items)

grammarRoundTrips :: TestTree
grammarRoundTrips =
  testGroup
    "Golem ADR 0310"
    [ testCase "G1: generated manuscripts retain syntax" $ do
        marks <- grammarHeadings
        let letters = ["a", "漢", "😀"]
            manuscripts =
              ""
                : [mark <> " " <> letter <> "\n" | mark <- marks, letter <- letters]
                ++ [a <> "\n\n" <> b | a <- letters, b <- letters]
        mapM_
          ( \source -> case format source of
              Formatted result -> do
                assertEqual ("source: " <> show source) [] (snd (parse (FileId 0) source))
                assertEqual ("source: " <> show source) (astFingerprint source) (astFingerprint result)
              Unformattable diagnostics -> assertFailure ("source: " <> show source <> ": " <> show diagnostics)
          )
          manuscripts,
      testCase "G2: generated manuscripts format idempotently" $ do
        marks <- grammarHeadings
        let letters = ["a", "漢", "😀"]
            manuscripts =
              ""
                : [mark <> " " <> letter <> "\n" | mark <- marks, letter <- letters]
                ++ [a <> "\n\n" <> b | a <- letters, b <- letters]
        mapM_
          ( \source -> case format source of
              Formatted once -> case format once of
                Formatted twice -> assertEqual ("source: " <> show source) once twice
                Unformattable diagnostics -> assertFailure ("source: " <> show source <> ": " <> show diagnostics)
              Unformattable diagnostics -> assertFailure ("source: " <> show source <> ": " <> show diagnostics)
          )
          manuscripts,
      testCase "G3: a seventh hash starts G01012 at its generated UTF-8 offset" $ do
        let prefixes = ["", "a\n\n", "漢\n\n", "😀\n\n"]
        mapM_
          ( \prefix -> do
              let source = prefix <> "####### a\n"
                  offset = BS.length (TE.encodeUtf8 prefix) + 6
                  positions = [spanStart (diagSpan issue) | issue <- snd (parse (FileId 0) source), diagCode issue == DiagnosticCode "G01012"]
              assertEqual ("source: " <> show source) [offset] positions
          )
          prefixes
    ]

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

{- | Whether the formatter formatted the document; the properties pass
trivially on the others, so they must be few (docs/adr/0066).
-}
isFormatted :: FormatResult -> Bool
isFormatted = \case
  Formatted _ -> True
  Unformattable _ -> False

golden :: String -> Text -> TestTree
golden name src = goldenVsString name ("test/golden/" <> name <> ".gm") (pure (BL.fromStrict (TE.encodeUtf8 (formatted src))))

tests :: TestTree
tests =
  testGroup
    "golem-fmt (ADR 0001)"
    [ -- the escapes the formatter may remove are made text first (golem-parser ADR 0010)
      testProperty "output is unchanged: the AST is preserved" $ property $ do
        src <- forAll document
        cover 80 "formattable" (isFormatted (format src))
        case format src of
          Formatted r -> astFingerprintWith removableEscape r === astFingerprintWith removableEscape (preprocess src)
          Unformattable _ -> discard,
      testCase "Golem ADR 0339 I2: comment boundaries and order format idempotently" $ do
        let source = "[cmd%%注%%]\n\n[cmd x %%注%% : 本文]\n\n[cmd \"x\"%%甲%%%%乙%%key=y]\n\n[= 1+%%注%%2]\n"
            expected = "[cmd %%注%%]\n\n[cmd x %%注%%: 本文]\n\n[cmd \"x\" %%甲%% %%乙%% key=y]\n\n[= 1+ %%注%% 2]\n"
        formatted source @?= expected
        formatted expected @?= expected,
      testCase "Golem ADR 0339 I5: missing quotes prevent rewriting" $
        case format "[cmd key=x%%注%%]\n" of
          Unformattable ds -> map diagCode ds @?= [DiagnosticCode "G01102"]
          Formatted r -> assertFailure ("rewritten: " <> show r),
      testCase "Golem ADR 0339 I2: expression delimiters touch boundary comments" $ do
        formatted "[= ( %%前%% 1 %%後%% )]\n" @?= "[= (%%前%% 1 %%後%%)]\n"
        formatted "[= %%前%% 1 %%後%% ]\n" @?= "[=%%前%% 1 %%後%%]\n",
      testCase "Golem ADR 0339 I2: call and member comments keep their order" $ do
        formatted "[= f%%注%%(1)]\n" @?= "[= f %%注%% (1)]\n"
        formatted "[= values%%注%%.price]\n" @?= "[= values %%注%% .price]\n",
      testProperty "idempotent" $ property $ do
        src <- forAll document
        cover 80 "formattable" (isFormatted (format src))
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
        formatted "```\n  a   \n```\n\n本文%%  コメント   %%\n" @?= "```\n  a   \n```\n\n本文%%  コメント   %%\n",
      tableTests,
      grammarRoundTrips
    ]

-- | The preprocessing of the table files (docs/adr/0186).
tableTests :: TestTree
tableTests =
  testGroup
    "the table files (docs/adr/0186)"
    [ testCase "the BOM is removed and CRLF becomes LF" $
        formatTable "\xFEFF\&a,b\r\n1,2\r\n" @?= "a,b\n1,2\n",
      testCase "a lone CR becomes LF; CRLF stays one line break" $ do
        formatTable "a,b\r1,2\r" @?= "a,b\n1,2\n"
        formatTable "a\r\r\nb" @?= "a\n\nb",
      testCase "tabs, spaces, blank lines and quotes are kept" $ do
        formatTable "a\tb\n\tz  \n" @?= "a\tb\n\tz  \n"
        formatTable "a,b\n\"x\n\n\ny  \",1\n\n\n  c ,\"d\"\"\"\n" @?= "a,b\n\"x\n\n\ny  \",1\n\n\n  c ,\"d\"\"\"\n",
      -- A4 of docs/adr/0211: 0, 1 and 2 BOMs at the start lose 0, 1 and 1
      testCase "A4: of 0, 1 and 2 BOMs at the start, formatTable removes 0, 1 and 1" $ do
        formatTable "a,b\n" @?= "a,b\n"
        formatTable "\xFEFF\&a,b\n" @?= "a,b\n"
        formatTable "\xFEFF\xFEFF\&a,b\n" @?= "\xFEFF\&a,b\n"
        formatTable (formatTable "\xFEFF\&a,b\n") @?= formatTable "\xFEFF\&a,b\n",
      testCase "only the BOM at the start, and only one, is removed" $ do
        formatTable "a\xFEFF\&b\n" @?= "a\xFEFF\&b\n"
        formatTable "\xFEFF\xFEFF\&a\n" @?= "\xFEFF\&a\n",
      -- a second BOM right after the first is a character of the first cell,
      -- which the reader keeps; it is left out here, as the reader leaves it
      testProperty "idempotent" $ property $ do
        src <- forAll tableText
        formatTable (formatTable src) === formatTable src
    ]

{- | The text of a table file: a BOM at the start or none, then cells,
separators, quotes and line breaks of every kind.
-}
tableText :: Gen Text
tableText = do
  bom <- Gen.element ["", "\xFEFF"]
  body <- T.concat <$> Gen.list (Range.linear 0 30) (Gen.element ["a", "x y", " ", ",", "\t", "\"", "\n", "\r\n", "\r", "\xFEFF", "語"])
  pure (bom <> (if "\xFEFF" `T.isPrefixOf` body then "a" <> body else body))
