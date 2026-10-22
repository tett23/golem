-- | Contributors, printings and the publisher person of [metadata] (docs/adr ADR 0033).
module ColophonSpec (tests) where

import Data.ByteString qualified as BS
import Data.List (nub)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time.Calendar (fromGregorian)
import Golem.Project
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

-- | A manifest with lines in [metadata] and tables after it.
manifestOf :: Text -> Text -> Text
manifestOf metaLines tables =
  T.unlines
    [ "chapters = [\"a.gm\"]",
      "",
      "[metadata]",
      "id = \"urn:uuid:00000000-0000-4000-8000-000000000000\"",
      "title = \"テスト\"",
      "language = \"ja\"",
      "date = 2026-10-11",
      metaLines,
      "[targets.html]",
      "",
      tables
    ]

parsed :: Text -> Text -> Either [Diagnostic] Metadata
parsed m t = manifestMetadata <$> parseManifest (FileId 0) (manifestOf m t)

-- | The one G03001 of a manifest: its message and its offset.
oneError :: Text -> Text -> IO (Text, Int)
oneError m t = case parseManifest (FileId 0) (manifestOf m t) of
  Left [d] | diagCode d == DiagnosticCode "G03001" -> pure (diagMessage d, spanStart (diagSpan d))
  other -> assertFailure (show (either (map diagMessage) (const []) other))

-- | The byte offset of the first occurrence of a text in a manifest.
offsetOf :: Text -> Text -> Text -> Int
offsetOf needle m t = BS.length (TE.encodeUtf8 (fst (T.breakOn needle (manifestOf m t))))

-- | An array of tables of contributors with one role.
contributor :: Text -> Text
contributor r = "[[metadata.contributors]]\nname = \"鈴木 花子\"\nrole = \"" <> r <> "\"\n"

printing :: Int -> Int -> Text -> Text
printing e p d = "[[metadata.printings]]\nedition = " <> T.pack (show e) <> "\nprinting = " <> T.pack (show p) <> "\ndate = " <> d <> "\n"

{- | The byte offset of the second item of printings in a manifest whose
tables are @t@: the key @printings@ of its header @[[metadata.printings]]@.
-}
secondPrinting :: Text -> Int
secondPrinting t =
  let whole = manifestOf "" t
      second = snd (T.breakOn "[[metadata.printings]]" (T.drop 1 (snd (T.breakOn "[[metadata.printings]]" whole))))
   in BS.length (TE.encodeUtf8 whole) - BS.length (TE.encodeUtf8 second) + T.length "[[metadata."

tests :: TestTree
tests =
  testGroup
    "colophon (docs/adr ADR 0033)"
    [ testCase "contributors and printings are read in the order of the manifest" $ do
        let tables =
              "[[metadata.creators]]\nname = \"山田 太郎\"\nrole = \"author\"\n\n"
                <> "[[metadata.contributors]]\nname = \"鈴木 花子\"\nreading = \"すずき はなこ\"\nrole = \"editor\"\n\n"
                <> contributor "printer"
                <> "\n"
                <> printing 1 1 "2026-10-16"
                <> "\n"
                <> printing 1 2 "2027-04-01"
        case parsed "publisher-person = \"佐藤 一郎\"" tables of
          Left ds -> assertFailure (show ds)
          Right md -> do
            mdCreators md @?= [Creator "山田 太郎" Nothing Author]
            mdContributors md @?= [Creator "鈴木 花子" (Just "すずき はなこ") Editor, Creator "鈴木 花子" Nothing Printer]
            mdPrintings md @?= [Printing 1 1 (fromGregorian 2026 10 16), Printing 1 2 (fromGregorian 2027 4 1)]
            mdPublisherPerson md @?= Just "佐藤 一郎",
      testCase "without them, the lists are empty and there is no publisher person" $
        case parsed "" "" of
          Left ds -> assertFailure (show ds)
          Right md -> (mdContributors md, mdPrintings md, mdPublisherPerson md) @?= ([], [], Nothing),
      testCase "every word of the table is a role" $
        mapM_
          ( \r -> case parsed "" (contributor (roleWord r)) of
              Right md -> map crRole (mdContributors md) @?= [r]
              Left ds -> assertFailure (show ds)
          )
          [minBound .. maxBound],
      testCase "a code of the table is G03001 at the value and names the word" $ do
        (m1, at1) <- oneError "" (contributor "aut")
        at1 @?= offsetOf "\"aut\"" "" (contributor "aut")
        assertBool (T.unpack m1) ("\"author\"" `T.isInfixOf` m1)
        (m2, _) <- oneError "" (contributor "trl")
        assertBool (T.unpack m2) ("\"translator\"" `T.isInfixOf` m2)
        (m3, _) <- oneError "" "[[metadata.creators]]\nname = \"a\"\nrole = \"aut\"\n"
        assertBool (T.unpack m3) ("\"author\"" `T.isInfixOf` m3),
      testCase "a word or code not in the table is G03001 and lists the words" $
        mapM_
          ( \r -> do
              (m, at) <- oneError "" (contributor r)
              at @?= offsetOf ("\"" <> r <> "\"") "" (contributor r)
              assertBool (T.unpack m) (all (`T.isInfixOf` m) ["author", "cover-designer", "binder"])
          )
          ["pbl", "Author", "writer"],
      testCase "role = publisher is G03001 and names publisher and publisher-person" $ do
        (m, _) <- oneError "" (contributor "publisher")
        assertBool (T.unpack m) ("publisher-person" `T.isInfixOf` m && "[metadata] の publisher" `T.isInfixOf` m),
      testCase "an empty publisher-person, or one with a newline, is G03001 at the value" $ do
        (_, at) <- oneError "publisher-person = \"\"" ""
        at @?= offsetOf "\"\"" "publisher-person = \"\"" ""
        _ <- oneError "publisher-person = \"a\\nb\"" ""
        pure (),
      testCase "an empty name is G03001, in creators and in contributors" $ do
        _ <- oneError "" "[[metadata.creators]]\nname = \"\"\nrole = \"author\"\n"
        (_, at) <- oneError "" "[[metadata.contributors]]\nname = \"\"\nrole = \"editor\"\n"
        at @?= offsetOf "\"\"" "" "[[metadata.contributors]]\nname = \"\"\nrole = \"editor\"\n",
      testCase "an edition or a printing below 1 is G03001" $ do
        _ <- oneError "" (printing 0 1 "2026-10-16")
        _ <- oneError "" (printing 1 0 "2026-10-16")
        pure (),
      testCase "printings that do not increase, or go back in date, are G03001 at the item" $ do
        let two a b = a <> "\n" <> b
            cases =
              [ two (printing 1 1 "2026-10-16") (printing 1 1 "2026-10-17"),
                two (printing 1 2 "2026-10-16") (printing 1 1 "2026-10-17"),
                two (printing 2 1 "2026-10-16") (printing 1 3 "2026-10-17"),
                two (printing 1 1 "2026-10-16") (printing 1 2 "2026-10-15")
              ]
        mapM_ (\t -> oneError "" t >>= \(_, at) -> assertBool (show at) (at > offsetOf "[[metadata.printings]]" "" t)) cases,
      testCase "printings out of order: the message names the order, at the second item" $ do
        let t = printing 1 2 "2026-10-16" <> "\n" <> printing 1 1 "2026-10-17"
        (m, at) <- oneError "" t
        (m, at) @?= ("printings は版と刷の順に、同じ版と刷を二度書かずに並べます (metadata.printings)", secondPrinting t),
      testCase "a printing dated before the one before it: the message names the date, at the second item" $ do
        let t = printing 1 1 "2026-10-16" <> "\n" <> printing 1 2 "2026-10-15"
        (m, at) <- oneError "" t
        (m, at) @?= ("printings の date が前の項目の date より前です (metadata.printings)", secondPrinting t),
      testCase "two printings on the same date are not out of order" $
        fmap (map prNumber . mdPrintings) (parsed "" (printing 1 1 "2026-10-16" <> "\n" <> printing 1 2 "2026-10-16")) @?= Right [1, 2],
      testCase "a new edition starts its printings again from 1" $
        fmap (map (\p -> (prEdition p, prNumber p)) . mdPrintings) (parsed "" (printing 1 3 "2026-10-16" <> "\n" <> printing 2 1 "2027-01-01"))
          @?= Right [(1, 3), (2, 1)],
      testCase "a printing number may skip" $
        fmap (map prNumber . mdPrintings) (parsed "" (printing 1 1 "2026-10-16" <> "\n" <> printing 1 3 "2027-01-01")) @?= Right [1, 3],
      testCase "an unknown key of contributors is G03001" $ do
        _ <- oneError "" "[[metadata.contributors]]\nname = \"a\"\nrole = \"editor\"\nnote = \"x\"\n"
        pure (),
      testCase "the words differ, and the codes are three lower-case letters that differ" $ do
        let rs = [minBound .. maxBound] :: [Role]
        length (nub (map roleWord rs)) @?= length rs
        length (nub (map marcRelator rs)) @?= length rs
        assertBool "codes" (all ((\c -> T.length c == 3 && T.all (`elem` ['a' .. 'z']) c) . marcRelator) rs)
        filter (not . inMetadata) rs @?= [Printer, Binder]
    ]
