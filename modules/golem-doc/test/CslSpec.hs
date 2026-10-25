-- | Reading CSL-JSON into the entries of the bibliography (docs/adr ADR 0089, golem-doc ADR 0005).
module CslSpec (tests) where

import Control.Exception (evaluate)
import Data.ByteString.Lazy qualified as BL
import Data.Scientific (scientific)
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Golem.Doc.Bibliography
import Golem.Doc.Bibliography.Csl
import Test.Tasty
import Test.Tasty.HUnit

entry :: CslEntry
entry = CslEntry "k" Nothing Nothing [] Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing

-- | JSON text as UTF-8 (a literal of a lazy ByteString keeps only the low byte of each character).
utf8 :: Text -> BL.ByteString
utf8 = BL.fromStrict . TE.encodeUtf8

-- | The entries of a JSON array, or a failure that names the error.
entries :: Text -> IO [CslEntry]
entries s = case decodeCslJson (utf8 s) of
  Right es -> pure es
  Left e -> assertFailure ("not read: " <> showError e) >> pure []

showError :: CslJsonError -> String
showError = \case
  CslNotJson m -> "CslNotJson " <> m
  CslNotArray -> "CslNotArray"

-- | The one entry of an array with one item, whose fields follow the id k.
one :: Text -> IO CslEntry
one fields = do
  es <- entries ("[{\"id\": \"k\"" <> fields <> "}]")
  case es of
    [e] -> pure e
    _ -> assertFailure ("not one entry: " <> show es) >> pure entry

tests :: TestTree
tests =
  testGroup
    "CSL-JSON (docs/adr ADR 0089)"
    [ testCase "text that is not JSON is CslNotJson with the message of aeson's eitherDecode" $
        -- the message of eitherDecode for "{" with the aeson of cabal.project.freeze
        case decodeCslJson "{" of
          Left (CslNotJson m) -> m @?= "Unexpected end-of-input, expecting record key literal or }"
          r -> assertFailure (either showError show r),
      testCase "JSON other than an array is CslNotArray" $ do
        mapM_
          ( \s -> case decodeCslJson s of
              Left CslNotArray -> pure ()
              r -> assertFailure (either showError show r)
          )
          ["{}", "1"],
      testCase "an empty array has no entries" $
        entries "[]" >>= (@?= []),
      testCase "items without a string id and items that are not objects are left out, the others kept in order" $ do
        es <- entries "[{\"id\": \"b\"}, 1, {\"id\": 2}, {\"title\": \"T\"}, \"a\", {\"id\": \"a\"}]"
        map ceId es @?= ["b", "a"],
      testCase "type, container-title and URL are read when they are strings" $ do
        e <- one ", \"type\": \"book\", \"container-title\": \"C\", \"URL\": \"https://example.com\""
        (ceType e, ceContainerTitle e, ceUrl e) @?= (Just "book", Just "C", Just "https://example.com")
        e' <- one ", \"type\": 1, \"container-title\": [\"C\"], \"URL\": null"
        (ceType e', ceContainerTitle e', ceUrl e') @?= (Nothing, Nothing, Nothing),
      testCase "volume, issue and page: a string, or an integer as its decimal digits; 12.5 is not read" $ do
        e <- one ", \"volume\": \"3\", \"issue\": 12, \"page\": \"10-20\""
        (ceVolume e, ceIssue e, cePage e) @?= (Just "3", Just "12", Just "10-20")
        e' <- one ", \"volume\": 12.5, \"issue\": 7, \"page\": 120"
        (ceVolume e', ceIssue e', cePage e') @?= (Nothing, Just "7", Just "120"),
      testCase "date-parts: without a month the day is not read" $ do
        e <- one ", \"issued\": {\"date-parts\": [[2020, 4, 5]]}, \"accessed\": {\"date-parts\": [[\"2021\"]]}"
        (ceIssued e, ceAccessed e) @?= (Just (DateParts 2020 (Just 4) (Just 5)), Just (DateParts 2021 Nothing Nothing))
        e' <- one ", \"issued\": {\"date-parts\": [[2020, \"x\", 5]]}"
        ceIssued e' @?= Just (DateParts 2020 Nothing Nothing),
      testCase "a literal date is read" $ do
        e <- one ", \"issued\": {\"literal\": \"2020年春\"}"
        ceIssued e @?= Just (DateLiteral "2020年春"),
      testCase "a string of spaces only is a field that is not there" $ do
        e <- one ", \"title\": \"  \", \"publisher\": \"\", \"volume\": \" \", \"issued\": {\"literal\": \" \"}"
        (ceTitle e, cePublisher e, ceVolume e, ceIssued e) @?= (Nothing, Nothing, Nothing, Nothing),
      testCase "names: literal first, and a name with neither family nor given is left out" $ do
        e <- one ", \"author\": [{\"literal\": \"日本規格協会\", \"family\": \"F\"}, {\"family\": \"山田\", \"given\": \"太郎\"}, {\"given\": \"G\"}, {\"suffix\": \"Jr.\"}, \"x\"]"
        ceAuthors e @?= [LiteralName "日本規格協会", PersonalName (Just "山田") (Just "太郎"), PersonalName Nothing (Just "G")],
      testCase "an entry with every field read" $ do
        e <- one ", \"title\": \"T\", \"language\": \"ja\", \"publisher\": \"P\""
        e @?= entry {ceTitle = Just "T", ceLanguage = Just "ja", cePublisher = Just "P"},
      localOption (mkTimeout 10000000) $ testCase "cslYear: Nothing from 10^15, 0 below 0.1, rounded otherwise; 1e1000000000 returns at once (docs/adr ADR 0035)" $ do
        cslYear (scientific 1 15) @?= Nothing
        cslYear (scientific 999999999999999 0) @?= Just 999999999999999
        cslYear (scientific 9 (-2)) @?= Just 0
        cslYear (scientific 19996 (-1)) @?= Just 2000
        r <- evaluate (cslYear (scientific 1 1000000000))
        r @?= Nothing
    ]
