{- | The manifest.toml that the tests of several packages write
(docs/adr ADR 0087).

'manifestToml' puts a fixed string together for the input of a test; it
is not a writer of TOML, and does not escape @"@ nor @\\@ in the values.
-}
module Golem.TestSupport.Manifest
  ( testBookId,
    TestManifest (..),
    testManifest,
    manifestToml,
  )
where

import Data.Text (Text)
import Data.Text qualified as T

-- | The id of the book of the tests.
testBookId :: Text
testBookId = "urn:uuid:11111111-2222-4333-8444-555555555555"

-- | The parts of a manifest that the tests vary.
data TestManifest = TestManifest
  { -- | The chapters, in order.
    tmChapters :: [Text],
    -- | The title.
    tmTitle :: Text,
    -- | The language.
    tmLanguage :: Text,
    -- | The text put after the line of the date, as it is.
    tmExtra :: Text,
    -- | The targets, each a section of its own.
    tmTargets :: [Text]
  }
  deriving stock (Eq, Show)

-- | The chapter @a.gm@, the title @T@, the language @ja@ and the target @html@.
testManifest :: TestManifest
testManifest =
  TestManifest
    { tmChapters = ["a.gm"],
      tmTitle = "T",
      tmLanguage = "ja",
      tmExtra = "",
      tmTargets = ["html"]
    }

-- | The text of the manifest: chapters, the metadata, the extra text, the targets.
manifestToml :: TestManifest -> Text
manifestToml m =
  "chapters = ["
    <> T.intercalate ", " ["\"" <> c <> "\"" | c <- tmChapters m]
    <> "]\n\n[metadata]\nid = \""
    <> testBookId
    <> "\"\ntitle = \""
    <> tmTitle m
    <> "\"\nlanguage = \""
    <> tmLanguage m
    <> "\"\ndate = 2026-10-11\n"
    <> tmExtra m
    <> T.concat ["\n[targets." <> t <> "]\n" | t <- tmTargets m]
