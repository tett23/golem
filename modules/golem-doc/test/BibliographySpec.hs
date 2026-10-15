-- | The format of one entry of the bibliography (golem-doc ADR 0004).
module BibliographySpec (tests) where

import Data.Text (Text)
import Golem.Doc.Bibliography
import Test.Tasty
import Test.Tasty.HUnit

entry :: CslEntry
entry = CslEntry "k" Nothing [] Nothing Nothing Nothing

titled :: Text -> CslEntry
titled t = entry {ceTitle = Just t}

tests :: TestTree
tests =
  testGroup
    "bibliography (golem-doc ADR 0004)"
    [ testCase "the two entries of manual/references.json" $ do
        formatEntry (titled "日本語組版処理の要件") {cePublisher = Just "W3C", ceIssued = Just (DateYear 2020)}
          @?= "日本語組版処理の要件、W3C、2020。"
        formatEntry (titled "JIS X 4061:1996 日本語文字列照合順番") {cePublisher = Just "日本規格協会", ceIssued = Just (DateYear 1996)}
          @?= "JIS X 4061:1996 日本語文字列照合順番、日本規格協会、1996。",
      testCase "a Latin entry is as before" $
        formatEntry (titled "Breaking Paragraphs into Lines") {ceAuthors = [PersonalName (Just "Knuth") (Just "Donald")], ceIssued = Just (DateYear 1981)}
          @?= "Knuth Donald. Breaking Paragraphs into Lines. 1981.",
      testCase "a literal author" $
        formatEntry (titled "日本語文字列照合順番") {ceAuthors = [LiteralName "日本規格協会"], ceIssued = Just (DateYear 1996)}
          @?= "日本規格協会、日本語文字列照合順番、1996。",
      testCase "personal names: Japanese without a space, one part alone" $ do
        formatEntry entry {ceAuthors = [PersonalName (Just "山田") (Just "太郎")]} @?= "山田太郎。"
        formatEntry entry {ceAuthors = [PersonalName (Just "Knuth") Nothing]} @?= "Knuth."
        formatEntry entry {ceAuthors = [PersonalName Nothing (Just "Donald")]} @?= "Donald.",
      testCase "two authors: 、 between Japanese, , between Latin" $ do
        formatEntry (titled "組版") {ceAuthors = [PersonalName (Just "山田") (Just "太郎"), PersonalName (Just "佐藤") (Just "花子")]}
          @?= "山田太郎、佐藤花子、組版。"
        formatEntry (titled "Lines") {ceAuthors = [PersonalName (Just "Knuth") (Just "Donald"), PersonalName (Just "Plass") (Just "Michael")]}
          @?= "Knuth Donald, Plass Michael. Lines.",
      testCase "language decides before the title" $ do
        formatEntry (titled "Typesetting") {ceLanguage = Just "ja-JP", ceIssued = Just (DateYear 2020)} @?= "Typesetting、2020。"
        formatEntry (titled "組版") {ceLanguage = Just "en", ceIssued = Just (DateYear 2020)} @?= "組版. 2020."
        formatEntry (titled "Typesetting") {ceLanguage = Just "JA", ceIssued = Just (DateYear 2020)} @?= "Typesetting、2020。"
        formatEntry (titled "排版") {ceLanguage = Just "zh-CN", ceIssued = Just (DateYear 2020)} @?= "排版. 2020.",
      testCase "without language or title, the publisher decides" $
        formatEntry entry {cePublisher = Just "日本規格協会", ceIssued = Just (DateYear 1996)} @?= "日本規格協会、1996。",
      testCase "without language, a Latin title decides before a Japanese publisher" $
        formatEntry (titled "Typesetting") {cePublisher = Just "日本規格協会"} @?= "Typesetting. 日本規格協会.",
      testCase "Latin fields that end in . ? ! take no period after them" $ do
        formatEntry (titled "What Is Typesetting?") {ceIssued = Just (DateYear 2001)} @?= "What Is Typesetting? 2001."
        formatEntry (titled "Breaking Paragraphs into Lines.") @?= "Breaking Paragraphs into Lines."
        formatEntry (titled "Wow!") {cePublisher = Just "ACME Inc."} @?= "Wow! ACME Inc.",
      testCase "a Japanese last field that ends in 。 takes no 。" $ do
        formatEntry (titled "組版とは何か。") @?= "組版とは何か。"
        formatEntry (titled "組版とは何か？") @?= "組版とは何か？"
        formatEntry (titled "組版とは何か。") {ceIssued = Just (DateYear 2001)} @?= "組版とは何か。、2001。",
      testCase "a literal date is the year field" $
        formatEntry (titled "日本語文字列照合順番") {ceIssued = Just (DateLiteral "1996年3月")} @?= "日本語文字列照合順番、1996年3月。",
      testCase "an entry with nothing is empty" $
        formatEntry entry @?= ""
    ]
