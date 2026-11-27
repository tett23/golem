module BibliographyFormatsSpec (tests) where

import Data.Either (isLeft)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Assemble.BibliographyFormats
import Golem.Assemble.Formats (Notation)
import Golem.Bibliography (EntryPart (..))
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup "bibliography declaration pieces" $
    [ testCase "root ADR 0480 I5: DOI and URL absence conditions cover all presence combinations" $
        mapM_
          ( \(doi, url) -> do
              let values = [("DOI", "10/example") | doi] <> [("URL", "https://example.org") | url]
              render ["DOI", "URL"] values ["https://doi.org/{DOI}", "{!DOI}{URL}"]
                @?= Right (if doi then "https://doi.org/10/example" else if url then "https://example.org" else "")
              render ["DOI", "URL"] values ["{!DOI}{!URL}."] @?= Right (if not doi && not url then "." else "")
          )
          [(doi, url) | doi <- [False, True], url <- [False, True]],
      testCase "root ADR 0480 I5: empty values and absent values have the same guard availability" $ do
        render ["DOI", "URL"] [("DOI", ""), ("URL", "fallback")] ["{!DOI}{URL}"] @?= Right "fallback"
        render ["DOI"] [("DOI", " ")] ["{!DOI}."] @?= Right "",
      testCase "root ADR 0480 I5: guards preserve ordinary required and optional omission" $ do
        render ["DOI", "URL"] [] ["{!DOI}({URL})"] @?= Right ""
        render ["DOI", "URL"] [] ["{!DOI}({URL?})"] @?= Right "()"
        render ["DOI", "URL"] [("DOI", "x")] ["{!DOI}({URL?})"] @?= Right "",
      testCase "root ADR 0480 I5: guards produce no field fragments and preserve literal escapes" $ do
        parsed <- either (assertFailure . T.unpack) pure (parseBibliographyPiece ["DOI", "URL"] "{!DOI}\\{{URL}\\}")
        renderBibliographyFragments (\name -> if name == "URL" then Just "literal {!DOI}" else Nothing) [parsed]
          @?= Right [BibliographyLiteral "{", BibliographyField "URL" "literal {!DOI}", BibliographyLiteral "}"]
        bibliographyPieceFields parsed @?= ["DOI", "URL"],
      testCase "root ADR 0480 I5: every guard uses the plain field availability context" $
        contextual (\case Nothing -> Just "Oct."; Just _ -> Nothing) ["{!month}missing"] @?= Right [],
      testCase "root ADR 0480 I5, I6: an omitted guarded piece never evaluates an unwritable ordinal" $
        render ["DOI", "edition"] [("DOI", "x"), ("edition", "0")] ["{edition:ordinal-en}{!DOI}"] @?= Right "",
      testCase "root ADR 0480 I6: English ordinal suffix boundaries and decimal canonicalization" $
        mapM_
          (\(value, expected) -> render ["edition"] [("edition", value)] ["{edition:ordinal-en} ed."] @?= Right (expected <> " ed."))
          [("1", "1st"), ("2", "2nd"), ("3", "3rd"), ("4", "4th"), ("11", "11th"), ("12", "12th"), ("13", "13th"), ("21", "21st"), ("22", "22nd"), ("23", "23rd"), ("111", "111th"), ("112", "112th"), ("113", "113th"), ("121", "121st"), ("+0002", "2nd"), ("0003", "3rd")],
      testCase "root ADR 0480 I6: arbitrarily large integer ordinals do not narrow or round" $ do
        let value = T.pack (show (10 ^ (100 :: Int) + 23 :: Integer))
        render ["edition"] [("edition", value)] ["{edition:ordinal-en}"] @?= Right (value <> "rd"),
      testCase "root ADR 0480 I6: ordinal formatting retains its field identity and punctuation" $
        fragments [("volume", "2")] ["({volume:ordinal-en})"]
          @?= Right [BibliographyLiteral "(", BibliographyField "volume" "2nd", BibliographyLiteral ")"],
      testCase "root ADR 0480 I6: zero and negative integers are range errors" $
        mapM_ (\value -> assertBool (T.unpack value) (isLeft (render ["edition"] [("edition", value)] ["{edition:ordinal-en}"]))) ["0", "+0", "000", "-0", "-1", "-12"],
      testCase "root ADR 0480 I6: non-integers and already formatted strings retain their spelling" $
        mapM_ (\value -> render ["edition"] [("edition", value)] ["{edition:ordinal-en}"] @?= Right value) ["1.5", "2.0", "1/2", "2nd", "1e2", "１２", " 2", "2 ", "+", "--2", "-1.5"],
      testCase "root ADR 0480 I6: absent and optional ordinals retain ordinary omission semantics" $ do
        render ["edition"] [] ["({edition:ordinal-en})"] @?= Right ""
        render ["edition"] [] ["({edition?:ordinal-en})"] @?= Right "()"
        render ["edition"] [("edition", "")] ["({edition:ordinal-en})"] @?= Right "",
      testCase "root ADR 0480 I6, I7: an unannotated edition and existing kanji notation stay unchanged" $ do
        render ["edition"] [("edition", "0002")] ["{edition}"] @?= Right "0002"
        render ["edition"] [("edition", "2")] ["{edition:kanji}"] @?= Right "二",
      testCase "root ADR 0470 I8: a month label and numeric month use their own contexts" $
        contextual (Just . maybe "Oct." (const "10")) ["{month}", "/", "{month:kanji}"]
          @?= Right [BibliographyField "month" "Oct.", BibliographyLiteral "/", BibliographyField "month" "十"],
      testCase "root ADR 0470 I3: required presence is checked in the requested notation context" $
        contextual (\case Nothing -> Nothing; Just _ -> Just "10") ["({month})", "{month:kanji}"]
          @?= Right [BibliographyField "month" "十"],
      testCase "root ADR 0470 I3: a missing numeric context suppresses its whole required piece" $
        contextual (\case Nothing -> Just "Oct."; Just _ -> Nothing) ["{month} {month:kanji}"] @?= Right [],
      testCase "root ADR 0470 I3: an optional missing numeric context keeps literal punctuation" $
        contextual (\case Nothing -> Just "Oct."; Just _ -> Nothing) ["{month}({month?:kanji})"]
          @?= Right [BibliographyField "month" "Oct.", BibliographyLiteral "(", BibliographyLiteral ")"],
      testCase "root ADR 0470 I8: contextual numeric values retain notation range errors" $
        assertBool "Roman 4000 is not hidden by the plain month label" (isLeft (contextual (Just . maybe "Oct." (const "4000")) ["{month:upper-roman}"])),
      testCase "root ADR 0470 I2: character styles affect fields and preserve URL parts" $
        bibliographyEntryParts (Map.fromList [("title", "italic"), ("URL", "strong")]) [BibliographyField "title" "Title", BibliographyLiteral ". ", BibliographyField "URL" "https://example.org"]
          @?= [EntryStyled "italic" [EntryText "Title"], EntryText ". ", EntryStyled "strong" [EntryUrl "https://example.org"]],
      testCase "root ADR 0470 I2: an unstyled field retains ordinary text" $
        bibliographyEntryParts Map.empty [BibliographyField "title" "Title", BibliographyField "URL" "https://example.org"] @?= [EntryText "Title", EntryUrl "https://example.org"],
      testCase "root ADR 0470 I8: fragment rendering preserves notation errors" $
        assertBool "Roman 4000 must report the same error" (isLeft (fragments [("volume", "4000")] ["{volume:upper-roman}"])),
      testCase "root ADR 0470 I3: fragment values remain literal text" $
        fragments [("title", "{URL}")] ["{title}"] @?= Right [BibliographyField "title" "{URL}"],
      testCase "root ADR 0470 I3: fragments retain fields separately from punctuation" $
        fragments [("title", "題"), ("URL", "https://example.org")] ["{title}. ", "{URL}"]
          @?= Right [BibliographyField "title" "題", BibliographyLiteral ". ", BibliographyField "URL" "https://example.org"],
      testCase "root ADR 0470 I3: omitted fragment pieces retain no punctuation" $
        fragments [("title", "題")] ["{title}", " ({volume})"] @?= Right [BibliographyField "title" "題"],
      testCase "root ADR 0470 I8: numeric fragments keep their original field name" $
        fragments [("volume", "12")] ["第{volume:kanji}巻"] @?= Right [BibliographyLiteral "第", BibliographyField "volume" "十二", BibliographyLiteral "巻"],
      testCase "root ADR 0470 I3: optional absent fragment fields do not produce empty nodes" $
        fragments [] ["a{title?}b"] @?= Right [BibliographyLiteral "a", BibliographyLiteral "b"],
      testCase "root ADR 0470 I3: empty fragments have no output nodes" $
        fragments [] [""] @?= Right [],
      testCase "root ADR 0470 I3: all required and optional presence combinations" $
        mapM_
          ( \(a, b) -> do
              let values = [("title", "T") | a] <> [("volume", "2") | b]
              render ["title", "volume"] values ["({title}{volume})"] @?= Right (if a && b then "(T2)" else "")
              render ["title", "volume"] values ["({title?}{volume?})"] @?= Right ("(" <> (if a then "T" else "") <> (if b then "2" else "") <> ")")
              render ["title", "volume"] values ["({title}{volume?})"] @?= Right (if a then "(T" <> (if b then "2" else "") <> ")" else "")
          )
          [(a, b) | a <- [False, True], b <- [False, True]],
      testCase "root ADR 0470 I8: non-integers and non-ASCII digits retain their value" $
        mapM_ (\value -> render ["volume"] [("volume", value)] ["{volume:kanji}"] @?= Right value) ["1.2", "1e2", "１２", " 2", "2 ", "second"],
      testCase "root ADR 0470 I8: a number outside the notation range reports an error" $
        assertBool "Roman 4000 must not disappear" (isLeft (render ["volume"] [("volume", "4000")] ["{volume:upper-roman}"])),
      testCase "root ADR 0470 I3: a missing required field removes its punctuation" $
        render ["title", "volume"] [("title", "題")] ["{title}", "、{volume:kanji}号"] @?= Right "題",
      testCase "root ADR 0470 I3: one absent field suppresses a whole multi-field piece" $
        render ["volume", "issue"] [("volume", "2")] ["第{volume:kanji}巻（{issue}）"] @?= Right "",
      testCase "root ADR 0470 I3: optional fields keep the rest of a piece" $
        render ["title", "volume"] [("title", "題")] ["{title}{volume?}"] @?= Right "題",
      testCase "root ADR 0470 I3: empty required values are missing" $
        render ["title", "volume"] [("title", "題"), ("volume", "")] ["{title}", "、{volume}号"] @?= Right "題",
      testCase "root ADR 0470 I3: literal pieces survive without fields" $
        render [] [] ["", "。"] @?= Right "。",
      testCase "root ADR 0470 I8: numeric fields use existing number notations" $
        render ["volume"] [("volume", "12")] ["第{volume:kanji}巻"] @?= Right "第十二巻",
      testCase "root ADR 0470 I8: ranges remain exactly as written" $
        render ["issue"] [("issue", "2–3")] ["{issue:kanji}"] @?= Right "2–3",
      testCase "root ADR 0470 I8: non-numbers retain suffixes and leading text" $
        render ["issue"] [("issue", "8(2–3)")] ["第{issue:kanji}号"] @?= Right "第8(2–3)号",
      testCase "root ADR 0470 I8: zero and leading zeros are numeric" $ do
        render ["volume"] [("volume", "0")] ["{volume:kanji}"] @?= Right "〇"
        render ["volume"] [("volume", "0012")] ["{volume:kanji}"] @?= Right "十二",
      testCase "root ADR 0470 I8: optional numeric slots permit absent values" $
        render ["volume"] [] ["第{volume?:kanji}巻"] @?= Right "第巻",
      testCase "root ADR 0470 I3: literal braces and backslashes use common escapes" $
        render ["title"] [("title", "題")] ["\\{{title}\\}\\\\"] @?= Right "{題}\\",
      testCase "root ADR 0470 I3: substituted values are not parsed as formats" $
        render ["title"] [("title", "{volume}")] ["{title}"] @?= Right "{volume}",
      testCase "root ADR 0470 I3: an absent later field suppresses a piece before rendering numerals" $
        render ["volume", "title"] [("volume", "0")] ["{volume:upper-roman}{title}"] @?= Right ""
    ]
      <> [ testCase ("root ADR 0480 I5: malformed absence condition " <> show value) $
             assertBool (T.unpack value) (isLeft (parseBibliographyPiece ["DOI", "URL"] value))
         | value <- ["{!unknown}", "{!}", "{!!DOI}", "{!DOI?}", "{!DOI:kanji}", "{!DOI?:kanji}", "{!DOI:ordinal-en}", "{!DOI"]
         ]
      <> [ testCase ("root ADR 0470 I7: malformed format " <> show value) $ case parseBibliographyPiece ["title", "volume"] value of
             Left _ -> pure ()
             Right result -> assertFailure ("accepted malformed format: " <> show result)
         | value <- ["{missing}", "{title", "title}", "{}", "{volume:unknown}", "{title??}", "\\q", "\\", "{{title}}", "{volume:kanji?}"]
         ]

render :: [Text] -> [(Text, Text)] -> [Text] -> Either Text Text
render names values pieces = do
  parsed <- traverse (parseBibliographyPiece names) pieces
  renderBibliographyPieces (`lookup` values) parsed

fragments :: [(Text, Text)] -> [Text] -> Either Text [BibliographyFragment]
fragments values source = traverse (parseBibliographyPiece ["title", "URL", "volume"]) source >>= renderBibliographyFragments (`lookup` values)

contextual :: (Maybe Notation -> Maybe Text) -> [Text] -> Either Text [BibliographyFragment]
contextual value source = traverse (parseBibliographyPiece ["month"]) source >>= renderBibliographyFragmentsWith (\_ notation -> value notation)
