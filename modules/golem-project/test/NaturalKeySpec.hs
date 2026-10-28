{- | The keys of style.toml and manifest.toml that take a natural number
(docs/adr ADR 0102): a negative number is G02103 at its value, with the
message of the key; 0, a float and the other errors keep their codes.
-}
module NaturalKeySpec (tests) where

import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Project
import Golem.Project.Style
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

-- | The byte offset of the first occurrence of a needle.
offsetOf :: Text -> Text -> Int
offsetOf src needle = BS.length (TE.encodeUtf8 (fst (T.breakOn needle src)))

grid :: Text
grid = "[page]\nsize = \"A5\"\n[page.grid]\nfont-size = \"10pt\"\ncharacters = 40\nlines = 30\nline-pitch = \"16pt\"\nposition = { top = \"14mm\", gutter = \"14mm\" }\n"

-- | A grid whose key has another value.
gridWith :: Text -> Text -> Text
gridWith key value = T.unlines [if (key <> " = ") `T.isPrefixOf` l then key <> " = " <> value else l | l <- T.lines grid]

-- | The code, the message and the offset of each diagnostic of style.toml.
styleErrors :: Text -> [(Text, Text, Int)]
styleErrors src = case parseStyle (FileId 0) src of
  Right _ -> []
  Left ds -> [(c, diagMessage d, spanStart (diagSpan d)) | d <- ds, let DiagnosticCode c = diagCode d]

manifestOf :: Text -> Text
manifestOf extra =
  T.unlines
    [ "chapters = [\"a.gm\"]",
      "",
      "[metadata]",
      "id = \"urn:uuid:00000000-0000-4000-8000-000000000000\"",
      "title = \"テスト\"",
      "language = \"ja\"",
      "date = 2026-10-11",
      "",
      extra,
      "[targets.html]"
    ]

manifestErrors :: Text -> [(Text, Text, Int)]
manifestErrors src = case parseManifest (FileId 0) src of
  Right _ -> []
  Left ds -> [(c, diagMessage d, spanStart (diagSpan d)) | d <- ds, let DiagnosticCode c = diagCode d]

tests :: TestTree
tests =
  testGroup
    "keys of natural numbers (docs/adr ADR 0102)"
    [ testCase "lines = -1 of [page.grid] is G02103 at its value" $ do
        let src = gridWith "lines" "-1"
        styleErrors src @?= [("G02103", "page.grid.lines には 0 以上の整数を書きます", offsetOf src "-1")],
      testCase "characters and columns of [page.grid] too" $ do
        map (\(c, _, _) -> c) (styleErrors (gridWith "characters" "-1")) @?= ["G02103"]
        map (\(c, _, _) -> c) (styleErrors (grid <> "columns = -2\ncolumn-gap = \"1zw\"\n")) @?= ["G02103"],
      testCase "lines of a heading and columns of [index]" $ do
        map (\(c, m, _) -> (c, m)) (styleErrors "[headings.1]\nlines = -1\n") @?= [("G02103", "headings.1.lines には 0 以上の整数を書きます")]
        map (\(c, m, _) -> (c, m)) (styleErrors "[index]\ncolumns = -1\n") @?= [("G02103", "index.columns には 0 以上の整数を書きます")],
      testCase "0 and a float keep their codes" $ do
        map (\(c, _, _) -> c) (styleErrors "[headings.1]\nlines = 0\n") @?= ["G03006"]
        map (\(c, _, _) -> c) (styleErrors "[headings.1]\nlines = 1.5\n") @?= ["G03006"]
        map (\(c, _, _) -> c) (styleErrors "[index]\ncolumns = 0\n") @?= ["G03025"],
      testCase "edition = -1 of a printing is G02103 at its value" $ do
        let src = manifestOf "[[metadata.printings]]\nedition = -1\nprinting = 1\ndate = 2026-10-11\n"
        manifestErrors src @?= [("G02103", "metadata.printings[0].edition には 0 以上の整数を書きます", offsetOf src "= -1" + 2)],
      testCase "printing = 0 keeps G03001" $
        map (\(c, _, _) -> c) (manifestErrors (manifestOf "[[metadata.printings]]\nedition = 1\nprinting = 0\ndate = 2026-10-11\n")) @?= ["G03001"]
    ]
