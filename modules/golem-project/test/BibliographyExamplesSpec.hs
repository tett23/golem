{- | The primary-source bibliography examples transcribed in
docs/research/bibliography-styles.md, through explicit declarations.
-}
module BibliographyExamplesSpec (tests) where

import Control.Applicative ((<|>))
import Control.Monad (forM_)
import Data.ByteString.Lazy qualified as BL
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Text.Read qualified as TR
import Golem.Assemble.BibliographyFormats
import Golem.Assemble.BibliographyNames qualified as Names
import Golem.Assemble.BibliographyRanges
import Golem.Assemble.BibliographyRecords (formatBibliographyRecord)
import Golem.Assemble.BibliographyStyle qualified as Decl
import Golem.Bibliography qualified as Csl
import Golem.Bibliography.Csl qualified as Json
import Golem.Project.Bibliography.Builtin (bundledBibliographyDeclaration, bundledBibliographySource)
import Golem.Project.Style (parseStyle, stBibliography)
import Golem.Syntax (FileId (..))
import Numeric.Natural (Natural)
import Test.Tasty
import Test.Tasty.HUnit

-- These fixtures are only the transcribed examples. Their explicit
-- bounds are the example author counts, not publication-wide name rules.
tests :: TestTree
tests =
  testGroup
    "primary bibliography examples"
    ( [example name | name <- ["ieee", "vancouver", "sist02", "unified-linguistics"]]
        <> [ testCase "root ADR 0470 I2, I6: bundled IEEE is its source file and equals a writer copy" $ do
               source <- TIO.readFile "data/bibliography/ieee.toml"
               bundledBibliographySource "ieee" @?= Just source
               declaration <- either (failure . show) pure (bundledBibliographyDeclaration (FileId 0) "ieee") >>= require "bundled IEEE declaration"
               let copy = T.replace "[bibliography.styles.ieee" "[bibliography.styles.writer-copy" (T.replace "style = 'ieee'" "style = 'writer-copy'" source)
               copied <- either (failure . show) pure (parseStyle (FileId 0) copy)
               Map.lookup "writer-copy" (Decl.bibStyles (stBibliography copied)) @?= Just declaration
               forM_ ["ieee", "ieee-book", "ieee-chapter"] $ \exampleName -> do
                 let fixture extension = "test/fixtures/bibliography/" <> exampleName <> extension
                 records <- BL.readFile (fixture ".json") >>= either (failure . show) pure . Json.decodeCslRecords
                 case records of
                   [record] -> do
                     parts <- either (failure . T.unpack) pure (formatBibliographyRecord declaration 1 record)
                     expected <- T.stripEnd <$> TIO.readFile (fixture ".txt")
                     Csl.entryText parts @?= expected
                   _ -> failure "exactly one primary IEEE example required",
             testCase "root ADR 0470: bundled IEEE lists six names and abbreviates seven to the first" $ do
               declaration <- either (failure . show) pure (bundledBibliographyDeclaration (FileId 0) "ieee") >>= require "bundled IEEE declaration"
               options <- require "IEEE author options" (Map.lookup "author" (Decl.bsNames declaration))
               (format, extras) <- either (failure . T.unpack) pure (Names.resolveBibliographyNames options)
               let people n = [Names.PersonalName (Just ("N" <> T.pack (show i))) (Just "A") | i <- [1 :: Int .. n]]
               Names.formatBibliographyNamesWith extras format (people 6) @?= "A. N1, A. N2, A. N3, A. N4, A. N5, and A. N6"
               Names.formatBibliographyNamesWith extras format (people 7) @?= "A. N1 et al.",
             testCase "root ADR 0470 I8: an explicit numeric month overrides the declared month label" $
               verifyExample "ieee" (T.replace "{month?}" "{month?:kanji} ") (T.replace "Oct. " "十 "),
             testCase "root ADR 0470 I6: an unlisted type uses the explicit default without changing its example" $
               verifyExample "vancouver" (T.replace ".types.article-journal]" ".types.default]") id
           ]
    )

example :: String -> TestTree
example name = testCase ("root ADR 0470 I6: explicit " <> name <> " declaration matches its primary-source example") (verifyExample name id id)

verifyExample :: String -> (Text -> Text) -> (Text -> Text) -> Assertion
verifyExample name changeDeclaration changeExpected = do
  let path extension = "test/fixtures/bibliography/" <> name <> extension
  source <- changeDeclaration <$> TIO.readFile (path ".toml")
  style <- either (failure . show) pure (parseStyle (FileId 0) source)
  Decl.bibSelected (stBibliography style) @?= "example"
  declaration <- require "example declaration" (Map.lookup "example" (Decl.bibStyles (stBibliography style)))
  records <- BL.readFile (path ".json") >>= either (failure . show) pure . Json.decodeCslRecords
  record <- case records of
    [one] -> pure one
    _ -> failure "the primary example must contain exactly one record"
  author <- require "explicit author options" (Map.lookup "author" (Decl.bsNames declaration))
  initial <- either (failure . T.unpack) pure (Names.parseInitialFormat "{i}!")
  let base = Names.NameFormat Names.FirstFamilyGiven "::" True initial "/" (Names.NameListFormat "|" "~" (Just 0) 0 "unused")
  format <- either (failure . T.unpack) pure (Names.applyBibliographyNames id base author)
  editorFields <- case Json.recordNames "editor" record of
    [] -> pure []
    editors -> do
      options <- require "explicit editor options" (Map.lookup "editor" (Decl.bsNames declaration))
      editorFormat <- either (failure . T.unpack) pure (Names.applyBibliographyNames id base options)
      labels <- require "explicit editor labels" (Decl.bnLabel options)
      let people = map person editors
      label <- require "editor label" (Names.bibliographyEditorLabel labels people)
      pure [("editor", Names.formatBibliographyNames editorFormat people), ("editor-label", label)]
  mode <- case Decl.bsPageRange declaration of
    Just "full" -> pure FullPageRange
    Just "minimal" -> pure MinimalPageRange
    _ -> failure "explicit page-range required"
  delimiter <- require "explicit range-delimiter" (Decl.bsRangeDelimiter declaration)
  page <- require "page field" (Json.recordText "page" record)
  endpoints <- case T.splitOn "-" page of
    [a, b] -> (,) <$> natural a <*> natural b
    _ -> failure "example must have two full decimal page endpoints"
  date <- case Json.recordDate "issued" record of
    Just (Csl.DateParts year month day) -> do
      monthField <- case month of
        Nothing -> pure []
        Just number -> do
          labels <- require "explicit months" (Decl.bsMonths declaration)
          label <- require "valid month in example" (lookup number (zip [1 ..] labels))
          pure [("month", label)]
      pure ([("year", T.pack (show year))] <> monthField <> [("day", T.pack (show number)) | Just number <- [day]])
    _ -> failure "example must have an issued date-parts value"
  entryType <- require "entry type" (Json.recordText "type" record)
  entry <- require "explicit entry type declaration" (Decl.bibliographyTypeFor entryType declaration)
  pieces <- require "explicit pieces" (Decl.btPieces entry)
  let authorField = Names.formatBibliographyNames format (map person (Json.recordNames "author" record))
      fields = Map.fromList ([("author", authorField), ("page", uncurry (formatBibliographyRange mode delimiter) endpoints)] <> date <> editorFields)
      field key notation
        | key == "month",
          Just _ <- notation = case Json.recordDate "issued" record of
            Just (Csl.DateParts _ (Just number) _) -> Just (T.pack (show number))
            _ -> Nothing
        | otherwise = Map.lookup key fields <|> Json.recordText key record
  parsed <- either (failure . T.unpack) pure (traverse (parseBibliographyPiece Decl.bibliographyFields) pieces)
  fragments <- either (failure . T.unpack) pure (renderBibliographyFragmentsWith field parsed)
  let parts = bibliographyEntryParts (Decl.btCharStyles entry) fragments
  expected <- TIO.readFile (path ".txt") >>= require "expected example ends with newline" . T.stripSuffix "\n"
  Csl.entryText parts @?= changeExpected expected
  selectedParts <- either (failure . T.unpack) pure (formatBibliographyRecord declaration 1 record)
  selectedParts @?= parts
  [(styleName, Csl.entryText body) | Csl.EntryStyled styleName body <- parts]
    @?= case name of
      "ieee" -> [("italic", "IEEE Trans. Biomed. Eng.")]
      "unified-linguistics" -> [("italic", "Multilingualism, second language learning, and gender")]
      _ -> []

person :: Json.CslPerson -> Names.BibliographyName
person (Json.CslPerson value _) = case value of
  Csl.PersonalName family given -> Names.PersonalName family given
  Csl.LiteralName literal -> Names.LiteralName literal

natural :: Text -> IO Natural
natural source = case TR.decimal source of
  Right (value, rest) | T.null rest -> pure value
  _ -> failure "page endpoint is not a natural number"

require :: String -> Maybe a -> IO a
require message = maybe (failure message) pure

failure :: String -> IO a
failure message = assertFailure message >> fail message
