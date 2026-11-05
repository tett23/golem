-- | The table [functions.requires] of manifest.toml (docs/adr/0161).
module FunctionsSpec (tests) where

import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Project
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

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
      "[targets.html]",
      "",
      extra
    ]

parsed :: Text -> Either [(Text, Int)] Manifest
parsed src = case parseManifest (FileId 0) src of
  Right m -> Right m
  Left ds -> Left [(c, spanStart (diagSpan d)) | d <- ds, let DiagnosticCode c = diagCode d]

codesOf :: Text -> [Text]
codesOf = either (map fst) (const []) . parsed

offsetOf :: Text -> Text -> Int
offsetOf src needle = BS.length (TE.encodeUtf8 (fst (T.breakOn needle src)))

tests :: TestTree
tests =
  testGroup
    "[functions.requires] (docs/adr/0161)"
    [ testCase "without it, functions may read no file" $
        fmap manifestRequiredFiles (parsed (manifestOf "")) @?= Right Nothing,
      testCase "file is the paths from the root, as written" $
        fmap manifestRequiredFiles (parsed (manifestOf "[functions.requires]\nfile = [\"data/words.tsv\", \"data/terms.tsv\"]\n"))
          @?= Right (Just ["data/words.tsv", "data/terms.tsv"]),
      testCase "an unknown kind is G03101 at its key" $ do
        let src = manifestOf "[functions.requires]\nfile = []\nnet = [\"x\"]\n"
        parsed src @?= Left [("G03101", offsetOf src "net")],
      testCase "a file that is no array is G03001" $
        codesOf (manifestOf "[functions.requires]\nfile = \"a.tsv\"\n") @?= ["G03001"],
      testCase "an unknown key of [functions] is G03001" $
        codesOf (manifestOf "[functions]\nfiles = []\n") @?= ["G03001"]
    ]
