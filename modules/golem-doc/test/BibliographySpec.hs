-- | The format of one entry of the bibliography (golem-doc ADR 0004, 0005).
module BibliographySpec (tests) where

import Data.Text (Text)
import Golem.Doc.Bibliography
import Test.Tasty
import Test.Tasty.HUnit

entry :: CslEntry
entry = CslEntry "k" Nothing Nothing [] Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing

titled :: Text -> CslEntry
titled t = entry {ceTitle = Just t}

year :: Integer -> CslDate
year y = DateParts y Nothing Nothing

fmt :: CslEntry -> Text
fmt = entryText . formatEntry

tests :: TestTree
tests = testGroup "bibliography" [adr0004, adr0005]

adr0004 :: TestTree
adr0004 =
  testGroup
    "bibliography (golem-doc ADR 0004)"
    [ testCase "the two entries of manual/references.json" $ do
        fmt (titled "日本語組版処理の要件") {cePublisher = Just "W3C", ceIssued = Just (year 2020)}
          @?= "日本語組版処理の要件、W3C、2020。"
        fmt (titled "JIS X 4061:1996 日本語文字列照合順番") {cePublisher = Just "日本規格協会", ceIssued = Just (year 1996)}
          @?= "JIS X 4061:1996 日本語文字列照合順番、日本規格協会、1996。",
      testCase "a Latin entry is as before" $
        fmt (titled "Breaking Paragraphs into Lines") {ceAuthors = [PersonalName (Just "Knuth") (Just "Donald")], ceIssued = Just (year 1981)}
          @?= "Knuth Donald. Breaking Paragraphs into Lines. 1981.",
      testCase "a literal author" $
        fmt (titled "日本語文字列照合順番") {ceAuthors = [LiteralName "日本規格協会"], ceIssued = Just (year 1996)}
          @?= "日本規格協会、日本語文字列照合順番、1996。",
      testCase "personal names: Japanese without a space, one part alone" $ do
        fmt entry {ceAuthors = [PersonalName (Just "山田") (Just "太郎")]} @?= "山田太郎。"
        fmt entry {ceAuthors = [PersonalName (Just "Knuth") Nothing]} @?= "Knuth."
        fmt entry {ceAuthors = [PersonalName Nothing (Just "Donald")]} @?= "Donald.",
      testCase "two authors: 、 between Japanese, , between Latin" $ do
        fmt (titled "組版") {ceAuthors = [PersonalName (Just "山田") (Just "太郎"), PersonalName (Just "佐藤") (Just "花子")]}
          @?= "山田太郎、佐藤花子、組版。"
        fmt (titled "Lines") {ceAuthors = [PersonalName (Just "Knuth") (Just "Donald"), PersonalName (Just "Plass") (Just "Michael")]}
          @?= "Knuth Donald, Plass Michael. Lines.",
      testCase "language decides before the title" $ do
        fmt (titled "Typesetting") {ceLanguage = Just "ja-JP", ceIssued = Just (year 2020)} @?= "Typesetting、2020。"
        fmt (titled "組版") {ceLanguage = Just "en", ceIssued = Just (year 2020)} @?= "組版. 2020."
        fmt (titled "Typesetting") {ceLanguage = Just "JA", ceIssued = Just (year 2020)} @?= "Typesetting、2020。"
        fmt (titled "排版") {ceLanguage = Just "zh-CN", ceIssued = Just (year 2020)} @?= "排版. 2020.",
      testCase "without language or title, the publisher decides" $
        fmt entry {cePublisher = Just "日本規格協会", ceIssued = Just (year 1996)} @?= "日本規格協会、1996。",
      testCase "without language, a Latin title decides before a Japanese publisher" $
        fmt (titled "Typesetting") {cePublisher = Just "日本規格協会"} @?= "Typesetting. 日本規格協会.",
      testCase "Latin fields that end in . ? ! take no period after them" $ do
        fmt (titled "What Is Typesetting?") {ceIssued = Just (year 2001)} @?= "What Is Typesetting? 2001."
        fmt (titled "Breaking Paragraphs into Lines.") @?= "Breaking Paragraphs into Lines."
        fmt (titled "Wow!") {cePublisher = Just "ACME Inc."} @?= "Wow! ACME Inc.",
      testCase "a Japanese last field that ends in 。 takes no 。" $ do
        fmt (titled "組版とは何か。") @?= "組版とは何か。"
        fmt (titled "組版とは何か？") @?= "組版とは何か？"
        fmt (titled "組版とは何か。") {ceIssued = Just (year 2001)} @?= "組版とは何か。、2001。",
      testCase "a literal date is the year field" $
        fmt (titled "日本語文字列照合順番") {ceIssued = Just (DateLiteral "1996年3月")} @?= "日本語文字列照合順番、1996年3月。",
      testCase "an entry with nothing is empty" $
        fmt entry @?= ""
    ]

-- | Knuth and Plass, the first entry of the examples of golem-doc ADR 0005.
knuthPlass :: CslEntry
knuthPlass =
  (titled "Breaking Paragraphs into Lines")
    { ceType = Just "article-journal",
      ceAuthors = [PersonalName (Just "Knuth") (Just "Donald"), PersonalName (Just "Plass") (Just "Michael")],
      ceContainerTitle = Just "Software: Practice and Experience",
      ceVolume = Just "11",
      ceIssue = Just "11",
      cePage = Just "1119-1184",
      ceIssued = Just (year 1981)
    }

jlreq :: CslEntry
jlreq = (titled "日本語組版処理の要件") {ceType = Just "webpage", cePublisher = Just "W3C", ceIssued = Just (year 2020), ceUrl = Just "https://www.w3.org/TR/jlreq/"}

cssText :: CslEntry
cssText = (titled "CSS Text Module Level 3") {ceType = Just "webpage", cePublisher = Just "W3C", ceUrl = Just "https://www.w3.org/TR/css-text-3/"}

oct16 :: CslDate
oct16 = DateParts 2026 (Just 10) (Just 16)

-- | A Japanese entry of a type with a title and a container.
jaTyped :: Text -> CslEntry
jaTyped t = (titled "題") {ceType = Just t, ceContainerTitle = Just "誌"}

-- | A Latin entry with a container and the fields of the container.
latinIn :: CslEntry
latinIn = (titled "Title") {ceContainerTitle = Just "Journal", ceIssued = Just (year 1981)}

adr0005 :: TestTree
adr0005 =
  testGroup
    "bibliography fields (golem-doc ADR 0005)"
    [ testCase "the eight examples" $ do
        fmt knuthPlass @?= "Knuth Donald, Plass Michael. Breaking Paragraphs into Lines. Software: Practice and Experience, vol. 11, no. 11, pp. 1119\x2013\&1184. 1981."
        fmt (titled "日本語の行分割") {ceType = Just "article-journal", ceAuthors = [PersonalName (Just "山田") (Just "太郎")], ceContainerTitle = Just "情報処理", ceVolume = Just "45", ceIssue = Just "1", cePage = Just "21-30", ceIssued = Just (year 2004)}
          @?= "山田太郎、「日本語の行分割」、『情報処理』、第45巻第1号、21\x2013\&30頁、2004。"
        fmt (titled "縦組みの約物") {ceType = Just "chapter", ceAuthors = [PersonalName (Just "鈴木") (Just "一郎")], ceContainerTitle = Just "組版論集", cePage = Just "45-60", cePublisher = Just "組版出版", ceIssued = Just (year 2015)}
          @?= "鈴木一郎、「縦組みの約物」、『組版論集』、45\x2013\&60頁、組版出版、2015。"
        fmt (titled "組版の基礎") {ceType = Just "book", ceAuthors = [PersonalName (Just "山田") (Just "花子")], cePublisher = Just "組版出版", ceIssued = Just (year 2010)}
          @?= "山田花子、『組版の基礎』、組版出版、2010。"
        fmt jlreq @?= "「日本語組版処理の要件」、W3C、2020、https://www.w3.org/TR/jlreq/。"
        fmt jlreq {ceAccessed = Just oct16} @?= "「日本語組版処理の要件」、W3C、2020、https://www.w3.org/TR/jlreq/（2026年10月16日閲覧）。"
        fmt cssText @?= "CSS Text Module Level 3. W3C. https://www.w3.org/TR/css-text-3/"
        fmt cssText {ceAccessed = Just oct16} @?= "CSS Text Module Level 3. W3C. https://www.w3.org/TR/css-text-3/ (accessed October 16, 2026).",
      testCase "Japanese brackets by type" $ do
        fmt (jaTyped "article-journal") @?= "「題」、『誌』。"
        fmt (jaTyped "chapter") @?= "「題」、『誌』。"
        fmt (jaTyped "webpage") @?= "「題」、誌。"
        fmt (jaTyped "post-weblog") @?= "「題」、誌。"
        fmt (jaTyped "book") @?= "『題』、誌。"
        fmt (jaTyped "standard") @?= "題、誌。"
        fmt (jaTyped "x") {ceType = Nothing} @?= "題、誌。",
      testCase "a title already in its brackets is not bracketed twice" $ do
        fmt (titled "「既に括った題」") {ceType = Just "article-journal"} @?= "「既に括った題」。"
        fmt (titled "『書名』") {ceType = Just "book"} @?= "『書名』。"
        fmt (titled "『書名』") {ceType = Just "article-journal"} @?= "「『書名』」。",
      testCase "a Latin entry is not bracketed or quoted by its type" $ do
        fmt latinIn {ceType = Just "article-journal"} @?= "Title. Journal. 1981."
        fmt latinIn {ceType = Just "book"} @?= "Title. Journal. 1981.",
      testCase "a bracketed title that ends in 。 is followed by 、" $
        fmt (titled "組版とは何か。") {ceType = Just "book", ceIssued = Just (year 2001)} @?= "『組版とは何か。』、2001。",
      testCase "a Latin container with a volume or an issue" $ do
        fmt latinIn {ceVolume = Just "11"} @?= "Title. Journal, vol. 11. 1981."
        fmt latinIn {ceIssue = Just "3"} @?= "Title. Journal, no. 3. 1981."
        fmt latinIn {ceVolume = Just "Suppl. 2"} @?= "Title. Journal, Suppl. 2. 1981.",
      testCase "a Japanese volume and issue" $ do
        fmt (titled "題") {ceVolume = Just "11"} @?= "題、第11巻。"
        fmt (titled "題") {ceIssue = Just "3"} @?= "題、第3号。"
        fmt (titled "題") {ceVolume = Just "11", ceIssue = Just "3"} @?= "題、第11巻第3号。",
      testCase "pages" $ do
        fmt (titled "Title") {cePage = Just "1119-1184"} @?= "Title. pp. 1119\x2013\&1184."
        fmt (titled "Title") {cePage = Just "1119--1184"} @?= "Title. pp. 1119\x2013\&1184."
        fmt (titled "Title") {cePage = Just "5"} @?= "Title. p. 5."
        fmt (titled "Title") {cePage = Just "A-1"} @?= "Title. p. A-1."
        fmt (titled "Title") {cePage = Just "3, 7"} @?= "Title. pp. 3, 7."
        fmt (titled "題") {cePage = Just "1119-1184"} @?= "題、1119\x2013\&1184頁。"
        fmt (titled "題") {cePage = Just "5"} @?= "題、5頁。",
      testCase "the date of access" $ do
        let at d = fmt cssText {ceAccessed = Just d}
            ja d = fmt jlreq {ceAccessed = Just d}
        at (DateParts 2026 (Just 10) Nothing) @?= "CSS Text Module Level 3. W3C. https://www.w3.org/TR/css-text-3/ (accessed October 2026)."
        at (DateParts 2026 Nothing Nothing) @?= "CSS Text Module Level 3. W3C. https://www.w3.org/TR/css-text-3/ (accessed 2026)."
        at (DateLiteral "autumn 2026") @?= "CSS Text Module Level 3. W3C. https://www.w3.org/TR/css-text-3/ (accessed autumn 2026)."
        at (DateParts 2026 (Just 13) (Just 1)) @?= "CSS Text Module Level 3. W3C. https://www.w3.org/TR/css-text-3/ (accessed 2026)."
        at (DateParts 2026 (Just 10) (Just 32)) @?= "CSS Text Module Level 3. W3C. https://www.w3.org/TR/css-text-3/ (accessed October 2026)."
        ja (DateParts 2026 (Just 10) Nothing) @?= "「日本語組版処理の要件」、W3C、2020、https://www.w3.org/TR/jlreq/（2026年10月閲覧）。"
        ja (DateParts 2026 Nothing Nothing) @?= "「日本語組版処理の要件」、W3C、2020、https://www.w3.org/TR/jlreq/（2026年閲覧）。"
        ja (DateLiteral "2026年秋") @?= "「日本語組版処理の要件」、W3C、2020、https://www.w3.org/TR/jlreq/（2026年秋閲覧）。"
        ja (DateParts 2026 (Just 13) (Just 1)) @?= "「日本語組版処理の要件」、W3C、2020、https://www.w3.org/TR/jlreq/（2026年閲覧）。"
        ja (DateParts 2026 (Just 10) (Just 32)) @?= "「日本語組版処理の要件」、W3C、2020、https://www.w3.org/TR/jlreq/（2026年10月閲覧）。",
      testCase "the date of access at the bounds of month and day" $ do
        let at d = fmt cssText {ceAccessed = Just d}
            ja d = fmt jlreq {ceAccessed = Just d}
        at (DateParts 2026 (Just 1) (Just 1)) @?= "CSS Text Module Level 3. W3C. https://www.w3.org/TR/css-text-3/ (accessed January 1, 2026)."
        at (DateParts 2026 (Just 12) (Just 31)) @?= "CSS Text Module Level 3. W3C. https://www.w3.org/TR/css-text-3/ (accessed December 31, 2026)."
        -- month 0 is not a month: the year alone, the day dropped with it
        at (DateParts 2026 (Just 0) (Just 5)) @?= "CSS Text Module Level 3. W3C. https://www.w3.org/TR/css-text-3/ (accessed 2026)."
        -- day 0 is not a day: the year and the month
        at (DateParts 2026 (Just 10) (Just 0)) @?= "CSS Text Module Level 3. W3C. https://www.w3.org/TR/css-text-3/ (accessed October 2026)."
        ja (DateParts 2026 (Just 12) (Just 31)) @?= "「日本語組版処理の要件」、W3C、2020、https://www.w3.org/TR/jlreq/（2026年12月31日閲覧）。"
        ja (DateParts 2026 (Just 0) (Just 5)) @?= "「日本語組版処理の要件」、W3C、2020、https://www.w3.org/TR/jlreq/（2026年閲覧）。"
        ja (DateParts 2026 (Just 10) (Just 0)) @?= "「日本語組版処理の要件」、W3C、2020、https://www.w3.org/TR/jlreq/（2026年10月閲覧）。",
      testCase "a hyphen between a digit and a letter is kept and is not a range" $ do
        fmt (titled "Title") {cePage = Just "1-A"} @?= "Title. p. 1-A."
        fmt (titled "Title") {cePage = Just "12a-13"} @?= "Title. p. 12a-13.",
      testCase "a Japanese volume that is not digits is as written" $
        fmt (titled "題") {ceVolume = Just "別冊", ceIssue = Just "3"} @?= "題、別冊第3号。",
      testCase "a title in kana alone, or with 々, decides a Japanese entry" $ do
        fmt (titled "カタカナ") {ceIssued = Just (year 2020)} @?= "カタカナ、2020。"
        fmt (titled "ひらがな") {ceIssued = Just (year 2020)} @?= "ひらがな、2020。"
        fmt (titled "々") {ceIssued = Just (year 2020)} @?= "々、2020。",
      testCase "accessed without a URL is not shown" $ do
        fmt (titled "Title") {ceAccessed = Just oct16} @?= "Title."
        fmt (titled "題") {ceAccessed = Just oct16} @?= "題。",
      testCase "the URL is one part, the separators and the date are text" $ do
        formatEntry cssText @?= [EntryText "CSS Text Module Level 3. W3C. ", EntryUrl "https://www.w3.org/TR/css-text-3/"]
        formatEntry cssText {ceAccessed = Just oct16} @?= [EntryText "CSS Text Module Level 3. W3C. ", EntryUrl "https://www.w3.org/TR/css-text-3/", EntryText " (accessed October 16, 2026)."]
        formatEntry jlreq @?= [EntryText "「日本語組版処理の要件」、W3C、2020、", EntryUrl "https://www.w3.org/TR/jlreq/", EntryText "。"]
        formatEntry (titled "Title") @?= [EntryText "Title."]
    ]
