module BibliographyFormatsSpec (tests) where

import Data.Either (isLeft)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Golem.Assemble.BibliographyFormats
import Golem.Bibliography (EntryPart (..))
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup "bibliography declaration pieces" $
    [ testCase "root ADR 0470 I2: character styles affect fields and preserve URL parts" $
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
