module CslRecordSpec (tests) where

import Control.Monad (forM_)
import Data.Aeson qualified as J
import Data.ByteString.Lazy.Char8 qualified as BL
import Data.Text.Encoding qualified as TE
import Golem.Bibliography
import Golem.Bibliography.Csl
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "declared bibliography metadata"
    [ testCase "root ADR 0470 I2: previously discarded declaration fields survive CSL decoding" $ do
        records <- either (assertFailure . show) pure $ decodeCslRecords "[{\"id\":\"a\",\"DOI\":\"10.1000/a\",\"ISBN\":\"123\",\"publisher-place\":\"Tokyo\",\"collection-title\":\"Series\",\"collection-number\":3,\"edition\":2}]"
        case records of
          [record] -> do
            map (`recordText` record) ["DOI", "ISBN", "publisher-place", "collection-title", "collection-number", "edition"] @?= map Just ["10.1000/a", "123", "Tokyo", "Series", "3", "2"]
            ceId (recordEntry record) @?= "a"
          _ -> assertFailure "expected one record",
      testCase "root ADR 0480 I6, I7: the unscaled integer view keeps the legacy scalar and entry views unchanged" $ do
        records <- either (assertFailure . show) pure $ decodeCslRecords "[{\"id\":\"a\",\"edition\":123456789012345678901,\"volume\":-123456789012345678901,\"small\":1e0,\"decimal\":1.0,\"string\":\"123456789012345678901\",\"fraction\":1.25,\"huge\":1e1000000000,\"tiny\":1e-1000000000,\"object\":{}}]"
        case records of
          [record] -> do
            map (`recordUnscaledIntegerText` record) ["edition", "volume", "small"] @?= map Just ["123456789012345678901", "-123456789012345678901", "1"]
            map (`recordUnscaledIntegerText` record) ["decimal", "string", "fraction", "huge", "tiny", "object", "missing"] @?= replicate 7 Nothing
            recordText "edition" record @?= Nothing
            ceVolume (recordEntry record) @?= Nothing
          _ -> assertFailure "expected one record",
      testCase "root ADR 0470 I9: sort keys stay with their corresponding valid author" $ do
        records <- either (assertFailure . show) pure $ decodeCslRecords "[{\"id\":\"a\",\"author\":[{}, {\"family\":\"Kadar\",\"given\":\"Daniel\",\"golem-sort-key\":\"kadar\"}, {\"literal\":\"Team\",\"golem-sort-key\":\"team\"}]}]"
        case records of
          [record] -> recordNames "author" record @?= [CslPerson (PersonalName (Just "Kadar") (Just "Daniel")) (Just "kadar"), CslPerson (LiteralName "Team") (Just "team")]
          _ -> assertFailure "expected one record",
      testCase "root ADR 0470 I2: editors retain personal and literal names" $ do
        records <- either (assertFailure . show) pure $ decodeCslRecords "[{\"id\":\"a\",\"editor\":[{\"family\":\"Smith\",\"given\":\"Ann\"},{\"literal\":\"Board\"}]}]"
        case records of
          [record] -> recordNames "editor" record @?= [CslPerson (PersonalName (Just "Smith") (Just "Ann")) Nothing, CslPerson (LiteralName "Board") Nothing]
          _ -> assertFailure "expected one record",
      testCase "root ADR 0470 I2: dates retain month and day" $ do
        records <- either (assertFailure . show) pure $ decodeCslRecords "[{\"id\":\"a\",\"issued\":{\"date-parts\":[[2011,10,25]]}}]"
        case records of
          [record] -> recordDate "issued" record @?= Just (DateParts 2011 (Just 10) (Just 25))
          _ -> assertFailure "expected one record",
      testCase "root ADR 0470 I8: calendar literals and missing years are not guessed or converted" $
        forM_ [("", Nothing), (",\"issued\":{\"date-parts\":[[null]]}", Nothing), (",\"issued\":{\"literal\":\"寛永某年\"}", Just (DateLiteral "寛永某年")), (",\"issued\":{\"date-parts\":[[null]],\"literal\":\"ヒジュラ暦1445年\"}", Just (DateLiteral "ヒジュラ暦1445年")), (",\"issued\":{\"date-parts\":[[1445]],\"calendar\":\"islamic\"}", Just (DateParts 1445 Nothing Nothing))] $ \(fields, expected) -> do
          records <- either (assertFailure . show) pure (decodeCslRecords (BL.fromStrict (TE.encodeUtf8 ("[{\"id\":\"a\"" <> fields <> "}]"))))
          case records of
            [record] -> recordDate "issued" record @?= expected
            _ -> assertFailure "expected one record",
      testCase "root ADR 0470 I3: missing, blank and structured fields are absent" $ do
        records <- either (assertFailure . show) pure $ decodeCslRecords "[{\"id\":\"a\",\"title\":\"  \",\"DOI\":null,\"edition\":{}}]"
        case records of
          [record] -> map (`recordText` record) ["title", "DOI", "edition", "ISBN"] @?= replicate 4 Nothing
          _ -> assertFailure "expected one record",
      testCase "root ADR 0470 I9: Japanese names retain explicit readings and blank keys are absent" $ do
        records <- either (assertFailure . show) pure $ decodeCslRecords "[{\"id\":\"a\",\"author\":[{\"family\":\"\\u5c71\\u7530\",\"golem-sort-key\":\"yamada\"},{\"family\":\"Smith\",\"golem-sort-key\":\"  \"}]}]"
        case records of
          [record] -> recordNames "author" record @?= [CslPerson (PersonalName (Just "山田") Nothing) (Just "yamada"), CslPerson (PersonalName (Just "Smith") Nothing) Nothing]
          _ -> assertFailure "expected one record",
      testCase "root ADR 0470 I2: records retain raw values beyond legacy scalar limits" $ do
        records <- either (assertFailure . show) pure $ decodeCslRecords "[{\"id\":\"a\",\"edition\":1.25,\"volume\":12345678901234567890,\"custom\":[\"value\"]}]"
        case records of
          [record] -> do
            fmap J.encode (recordValue "edition" record) @?= Just "1.25"
            fmap J.encode (recordValue "volume" record) @?= Just "12345678901234567890"
            fmap J.encode (recordValue "custom" record) @?= Just "[\"value\"]"
          _ -> assertFailure "expected one record",
      testCase "root ADR 0470 I3: unsupported scalar shapes do not become citation text" $ do
        records <- either (assertFailure . show) pure $ decodeCslRecords "[{\"id\":\"a\",\"DOI\":true,\"edition\":[],\"volume\":1.25,\"author\":null,\"issued\":[]}]"
        case records of
          [record] -> do
            map (`recordText` record) ["DOI", "edition", "volume"] @?= replicate 3 Nothing
            recordNames "author" record @?= []
            recordDate "issued" record @?= Nothing
          _ -> assertFailure "expected one record",
      testCase "root ADR 0470 I1: legacy entries and their order are unchanged" $ do
        let input = "[{\"id\":\"a\",\"title\":\"Title\",\"author\":[{\"family\":\"Knuth\",\"given\":\"Donald\"}],\"issued\":{\"date-parts\":[[1981]]}},{\"title\":\"no id\"},null,{\"id\":\"b\"}]"
        fmap (map recordEntry) (decodeCslRecords input) @?= decodeCslJson input
        fmap (map (entryText . formatEntry . recordEntry)) (decodeCslRecords input) @?= Right ["Knuth Donald. Title. 1981.", ""],
      testCase "root ADR 0470 I1: unknown fields still participate in unwritable character validation" $
        decodeCslRecords (BL.pack "[{\"id\":\"a\",\"unread\":\"\\u0000\"}]") @?= Left (CslUnwritable '\0' "/0/unread" 0),
      testCase "root ADR 0470 I1: malformed and non-array JSON are still refused" $ do
        decodeCslRecords "{}" @?= Left CslNotArray
        case decodeCslRecords "[" of
          Left CslNotJson {} -> pure ()
          other -> assertFailure (show other)
    ]
