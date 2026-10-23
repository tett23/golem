{- | The characters that cannot be written to the output, in the strings
of manifest.toml (docs/adr ADR 0042, G03028). These tests replace those
of the security audit of 2026-10-18, C15, in golem-pdf and golem-epub:
the title is refused when it is read, so it never reaches XMP or OPF.
-}
module OutputCharsSpec (tests) where

import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Project
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

-- | A manifest whose [metadata] has the lines given after the title.
manifestOf :: Text -> Text -> Text
manifestOf title extra =
  T.unlines
    [ "chapters = [\"a.gm\"]",
      "",
      "[metadata]",
      "id = \"urn:uuid:00000000-0000-4000-8000-000000000000\"",
      "title = " <> title,
      "language = \"ja\"",
      "date = 2026-10-11",
      extra,
      "",
      "[targets.html]"
    ]

-- | The byte offset of the first occurrence of a needle.
offsetOf :: Text -> Text -> Int
offsetOf needle src = BS.length (TE.encodeUtf8 (fst (T.breakOn needle src)))

-- | The code, the start and the message of each diagnostic of a failed parse.
failures :: Text -> [(DiagnosticCode, Int, Text)]
failures src = case parseManifest (FileId 0) src of
  Left ds -> [(diagCode d, spanStart (diagSpan d), diagMessage d) | d <- ds]
  Right _ -> []

tests :: TestTree
tests =
  testGroup
    "characters that cannot be written to the output (docs/adr ADR 0042)"
    [ testCase "C15: a title with \\u0001 is G03028 at the value of title" $ do
        let src = manifestOf "\"t\\u0001t\"" ""
        case failures src of
          [(c, at, msg)] -> do
            (c, at) @?= (DiagnosticCode "G03028", offsetOf "\"t\\u0001t\"" src)
            assertBool (T.unpack msg) ("title" `T.isInfixOf` msg && "U+0001" `T.isInfixOf` msg)
          other -> assertFailure (show other),
      testCase "C15: \\u0000 in an element of creators is G03028" $ do
        let src = manifestOf "\"t\"" "\n[[metadata.creators]]\nname = \"a\\u0000b\"\nrole = \"author\"\n"
        case failures src of
          [(c, at, msg)] -> do
            (c, at) @?= (DiagnosticCode "G03028", offsetOf "\"a\\u0000b\"" src)
            assertBool (T.unpack msg) ("name" `T.isInfixOf` msg && "U+0000" `T.isInfixOf` msg)
          other -> assertFailure (show other),
      testCase "U+FFFE in publisher is G03028" $ do
        let src = manifestOf "\"t\"" "publisher = \"p\\uFFFEq\""
        map (\(c, _, m) -> (c, "U+FFFE" `T.isInfixOf` m)) (failures src) @?= [(DiagnosticCode "G03028", True)],
      testCase "a string of another table is checked too" $ do
        let src = manifestOf "\"t\"" "" <> "\n[targets.epub]\nisbn = \"978\\u001F\"\n"
        map (\(c, _, _) -> c) (failures src) @?= [DiagnosticCode "G03028"],
      testCase "a title with a tab and a newline passes" $
        case parseManifest (FileId 0) (manifestOf "\"a\\tb\\nc\\rd\"" "") of
          Left ds -> assertFailure (show ds)
          Right m -> mdTitle (manifestMetadata m) @?= "a\tb\nc\rd",
      testCase "U+007F and U+0085 pass" $
        case parseManifest (FileId 0) (manifestOf "\"a\\u007Fb\\u0085c\"" "") of
          Left ds -> assertFailure (show ds)
          Right _ -> pure ()
    ]
