{- | The values of the project that the outputs and the evaluation share
(docs/adr/0192): the FileId of style.toml, the metadata a running head can
show, and the bullets of [lists].
-}
module SharedValuesSpec (tests) where

import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict qualified as Map
import Data.Text.IO qualified as TIO
import Data.Time.Calendar (fromGregorian)
import Golem.Project
import Golem.Project.Style
import Golem.Syntax
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

metadata :: Metadata
metadata =
  Metadata
    { mdId = "urn:uuid:00000000-0000-4000-8000-000000000000",
      mdTitle = "テスト",
      mdTitleReading = Nothing,
      mdLanguage = "ja",
      mdDate = fromGregorian 2026 10 11,
      mdEdition = Nothing,
      mdPublisher = Nothing,
      mdCreators = [Creator "著者" Nothing Author],
      mdPublisherPerson = Nothing,
      mdContributors = [],
      mdPrintings = []
    }

tests :: TestTree
tests =
  testGroup
    "values the outputs share (docs/adr/0192)"
    [ testCase "styleFileId is the FileId after the files of the project" $
        withSystemTempDirectory "golem" $ \root -> do
          TIO.writeFile (root </> "manifest.toml") "chapters = [\"a.gm\", \"b.gm\"]\n\n[metadata]\nid = \"urn:uuid:00000000-0000-4000-8000-000000000000\"\ntitle = \"テスト\"\nlanguage = \"ja\"\ndate = 2026-10-11\n\n[targets.html]\n"
          TIO.writeFile (root </> "a.gm") ""
          TIO.writeFile (root </> "b.gm") ""
          loadProject root >>= \case
            Right p -> do
              length (fileTableEntries (projectFiles p)) @?= 3
              styleFileId p @?= FileId 3
            Left f -> assertFailure (show (map diagMessage (pfDiagnostics f))),
      testCase "runningMetadata has id, title, language and date, the optional keys with values, and no creators" $ do
        runningMetadata metadata
          @?= Map.fromList [("id", "urn:uuid:00000000-0000-4000-8000-000000000000"), ("title", "テスト"), ("language", "ja"), ("date", "2026-10-11")]
        runningMetadata metadata {mdTitleReading = Just "てすと", mdEdition = Just "第2版", mdPublisher = Just "出版社"}
          @?= Map.fromList
            [ ("id", "urn:uuid:00000000-0000-4000-8000-000000000000"),
              ("title", "テスト"),
              ("language", "ja"),
              ("date", "2026-10-11"),
              ("title_reading", "てすと"),
              ("edition", "第2版"),
              ("publisher", "出版社")
            ],
      testCase "without bullets, listBullets is • and textBullets is ・; with bullets, both are those written" $ do
        listBullets defaultListStyle @?= pure "•"
        textBullets defaultListStyle @?= pure "・"
        let written = defaultListStyle {lsBullets = Just ("■" :| ["□"])}
        listBullets written @?= "■" :| ["□"]
        textBullets written @?= "■" :| ["□"]
    ]
