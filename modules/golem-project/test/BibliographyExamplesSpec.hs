{- | The bibliography examples transcribed in
docs/research/bibliography-styles.md, through explicit declarations.
-}
module BibliographyExamplesSpec (tests) where

import Control.Applicative ((<|>))
import Control.Monad (forM_)
import Data.ByteString.Lazy qualified as BL
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
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

-- The legacy fixtures retain their example author counts. APA also checks
-- the separately sourced publication-wide boundary of 20 and 21 authors.
tests :: TestTree
tests =
  testGroup
    "primary bibliography examples"
    ( [example name | name <- ["ieee", "vancouver", "sist02", "unified-linguistics"]]
        <> [bundledExample name | name <- ["ieee", "vancouver", "sist02", "unified-linguistics"]]
        <> apaTests
        <> [ testCase "root ADR 0470: bundled IEEE lists six names and abbreviates seven to the first" $ do
               declaration <- either (failure . show) pure (bundledBibliographyDeclaration (FileId 0) "ieee") >>= require "bundled IEEE declaration"
               options <- require "IEEE author options" (Map.lookup "author" (Decl.bsNames declaration))
               (format, extras) <- either (failure . T.unpack) pure (Names.resolveBibliographyNames options)
               let people n = [Names.PersonalName (Just ("N" <> T.pack (show i))) (Just "A") | i <- [1 :: Int .. n]]
               Names.formatBibliographyNamesWith extras format (people 6) @?= "A. N1, A. N2, A. N3, A. N4, A. N5, and A. N6"
               Names.formatBibliographyNamesWith extras format (people 7) @?= "A. N1 et al.",
             testCase "root ADR 0470 I8: literal issued dates survive the selected record formatter" $ do
               let declaration = Decl.emptyBibliographyStyle {Decl.bsTypes = Map.singleton "default" (Decl.BibliographyType (Just ["{year:kanji}", " ({month})", " ({day})"]) Map.empty)}
               forM_ ["n.d.", "circa 2020", "2020/21", "寛永某年", "ヒジュラ暦1445年"] $ \literal -> do
                 let source = "[{\"id\":\"a\",\"issued\":{\"literal\":\"" <> literal <> "\"}}]"
                 records <- either (failure . show) pure (Json.decodeCslRecords (BL.fromStrict (TE.encodeUtf8 source)))
                 case records of
                   [record] -> do
                     parts <- either (failure . T.unpack) pure (formatBibliographyRecord declaration 1 record)
                     Csl.entryText parts @?= literal
                   _ -> failure "one literal-date record required",
             testCase "root ADR 0470 I8: an explicit numeric month overrides the declared month label" $
               verifyExample "ieee" (T.replace "{month?}" "{month?:kanji} ") (T.replace "Oct. " "十 "),
             testCase "root ADR 0470 I6: an unlisted type uses the explicit default without changing its example" $
               verifyExample "vancouver" (T.replace ".types.article-journal]" ".types.default]") id
           ]
    )

-- APA examples retain the secondary transcriptions in the research note.
apaTests :: [TestTree]
apaTests =
  [ testCase "root ADR 0470 I2, I6: secondary-source APA examples match named and copied declarations" $ do
      declaration <- either (failure . show) pure (bundledBibliographyDeclaration (FileId 0) "apa") >>= require "bundled APA declaration"
      source <- TIO.readFile "data/bibliography/apa.toml"
      bundledBibliographySource "apa" @?= Just source
      let copy = T.replace "[bibliography.styles.apa" "[bibliography.styles.writer-copy" (T.replace "style = 'apa'" "style = 'writer-copy'" source)
      copied <- either (failure . show) pure (parseStyle (FileId 0) copy)
      Map.lookup "writer-copy" (Decl.bibStyles (stBibliography copied)) @?= Just declaration
      forM_ apaExamples $ \(json, expected, styles) -> do
        records <- either (failure . show) pure (Json.decodeCslRecords (BL.fromStrict (TE.encodeUtf8 json)))
        record <- case records of [one] -> pure one; _ -> failure "one APA record required"
        parts <- either (failure . T.unpack) pure (formatBibliographyRecord declaration 1 record)
        Csl.entryText parts @?= expected
        [(name, Csl.entryText body) | Csl.EntryStyled name body <- parts] @?= styles,
    testCase "root ADR 0470 I2, I6: APA lists twenty names and retains nineteen plus the last of twenty-one" $ do
      declaration <- either (failure . show) pure (bundledBibliographyDeclaration (FileId 0) "apa") >>= require "bundled APA declaration"
      options <- require "APA author options" (Map.lookup "author" (Decl.bsNames declaration))
      (format, extras) <- either (failure . T.unpack) pure (Names.resolveBibliographyNames options)
      let people n = [Names.PersonalName (Just ("N" <> T.pack (show i))) (Just "A") | i <- [1 :: Int .. n]]
          written :: Int -> Text
          written i = "N" <> T.pack (show i) <> ", A."
      Names.formatBibliographyNamesWith extras format (people 20) @?= T.intercalate ", " (map written [1 .. 19]) <> ", & " <> written 20
      Names.formatBibliographyNamesWith extras format (people 21) @?= T.intercalate ", " (map written [1 .. 19]) <> ", . . . " <> written 21
  ]

apaExamples :: [(Text, Text, [(Text, Text)])]
apaExamples =
  [ ("[{\"issued\": {\"date-parts\": [[2019]]}, \"publisher\": \"American Psychological Association\", \"id\": \"jackson2019\", \"type\": \"book\", \"author\": [{\"family\": \"Jackson\", \"given\": \"L. M.\"}], \"title\": \"The psychology of prejudice: From attitudes to social action\", \"edition\": 2, \"DOI\": \"10.1037/0000168-000\"}]", "Jackson, L. M. (2019). The psychology of prejudice: From attitudes to social action (2nd ed.). American Psychological Association. https://doi.org/10.1037/0000168-000", [("italic", "The psychology of prejudice: From attitudes to social action")]),
    ("[{\"issued\": {\"date-parts\": [[2019]]}, \"id\": \"grady2019\", \"type\": \"article-journal\", \"author\": [{\"family\": \"Grady\", \"given\": \"J. S.\"}, {\"family\": \"Her\", \"given\": \"M.\"}, {\"family\": \"Moreno\", \"given\": \"G.\"}, {\"family\": \"Perez\", \"given\": \"C.\"}, {\"family\": \"Yelinek\", \"given\": \"J.\"}], \"title\": \"Emotions in storybooks: A comparison of storybooks that represent ethnic and racial groups in the United States\", \"volume\": \"8\", \"issue\": \"3\", \"page\": \"207-217\", \"DOI\": \"10.1037/ppm0000185\", \"container-title\": \"Psychology of Popular Media Culture\"}]", "Grady, J. S., Her, M., Moreno, G., Perez, C., & Yelinek, J. (2019). Emotions in storybooks: A comparison of storybooks that represent ethnic and racial groups in the United States. Psychology of Popular Media Culture, 8(3), 207–217. https://doi.org/10.1037/ppm0000185", [("italic", "Psychology of Popular Media Culture"), ("italic", "8")]),
    ("[{\"issued\": {\"date-parts\": [[2019]]}, \"publisher\": \"American Psychological Association\", \"id\": \"aron2019\", \"type\": \"chapter\", \"author\": [{\"family\": \"Aron\", \"given\": \"L.\"}, {\"family\": \"Botella\", \"given\": \"M.\"}, {\"family\": \"Lubart\", \"given\": \"T.\"}], \"editor\": [{\"family\": \"Subotnik\", \"given\": \"R. F.\"}, {\"family\": \"Olszewski-Kubilius\", \"given\": \"P.\"}, {\"family\": \"Worrell\", \"given\": \"F. C.\"}], \"title\": \"Culinary arts: Talent and their development\", \"page\": \"345-359\", \"DOI\": \"10.1037/0000120-016\", \"container-title\": \"The psychology of high performance …\"}]", "Aron, L., Botella, M., & Lubart, T. (2019). Culinary arts: Talent and their development. In R. F. Subotnik, P. Olszewski-Kubilius, & F. C. Worrell (Eds.), The psychology of high performance … (pp. 345–359). American Psychological Association. https://doi.org/10.1037/0000120-016", [("italic", "The psychology of high performance …")])
  ]

example :: String -> TestTree
example name = testCase ("root ADR 0470 I6: explicit " <> name <> " declaration matches its primary-source example") (verifyExample name id id)

bundledExample :: String -> TestTree
bundledExample name = testCase ("root ADR 0470 I2, I6: bundled " <> name <> " equals its file, writer copy and primary examples") $ do
  source <- TIO.readFile ("data/bibliography/" <> name <> ".toml")
  let styleName = T.pack name
  bundledBibliographySource styleName @?= Just source
  declaration <- either (failure . show) pure (bundledBibliographyDeclaration (FileId 0) styleName) >>= require "bundled declaration"
  let copy = T.replace ("[bibliography.styles." <> styleName) "[bibliography.styles.writer-copy" (T.replace ("style = '" <> styleName <> "'") "style = 'writer-copy'" source)
  copied <- either (failure . show) pure (parseStyle (FileId 0) copy)
  Map.lookup "writer-copy" (Decl.bibStyles (stBibliography copied)) @?= Just declaration
  forM_ (if name == "ieee" then [name, "ieee-book", "ieee-chapter"] else [name]) $ \exampleName -> do
    let fixture extension = "test/fixtures/bibliography/" <> exampleName <> extension
    records <- BL.readFile (fixture ".json") >>= either (failure . show) pure . Json.decodeCslRecords
    case records of
      [record] -> do
        parts <- either (failure . T.unpack) pure (formatBibliographyRecord declaration 1 record)
        expected <- T.stripEnd <$> TIO.readFile (fixture ".txt")
        Csl.entryText parts @?= expected
      _ -> failure "exactly one primary example required"

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
