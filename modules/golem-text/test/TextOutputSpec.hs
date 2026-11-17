{- | Small tests of the plain-text output over hand-built books
(golem-text ADR 0001): page references, citations, footnotes, sidenotes,
ruby, numbers and the block forms.
-}
module TextOutputSpec (textOutputTests) where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Assemble (Book (..), ChannelEntry (..), HeadingInfo (..), LabelTarget (..), TocEntry (..))
import Golem.Doc.IR
import Golem.Syntax.Span
import Golem.Text
import Hedgehog (forAll, property, (===))
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testProperty)

fid :: FileId
ft :: FileTable
(fid, ft) = registerFile "chapters/a.gm" emptyFileTable

-- | A span in a.gm; distinct starts keep the blocks apart.
at :: Int -> SrcSpan
at n = mkSpan fid n (n + 1)

-- | A book of one document, a.gm, with nothing assembled.
bookOf :: [Block] -> Book
bookOf bs =
  Book
    { bookDocs = [Document fid bs],
      bookHeadings = Map.empty,
      bookFigures = Map.empty,
      bookListings = Map.empty,
      bookTables = Map.empty,
      bookToc = [],
      bookTocDepth = Nothing,
      bookIndexes = [],
      bookBibliographies = [],
      bookCiteMarks = Map.empty,
      bookLabels = Map.empty,
      bookReferenced = Set.empty,
      bookChapterOf = [],
      bookChannels = [],
      bookChannelDecls = Map.empty,
      bookTitleSeparators = Map.empty,
      bookImages = Map.empty
    }

para :: Int -> [Inline] -> Block
para n = Block (at n) Nothing Nothing . Paragraph Nothing

txt :: Text -> Inline
txt = Text (at 0)

-- | The one text file of a book, as the given variant and profile.
renderWith :: Bool -> TextVariant -> Book -> [(FilePath, Text)]
renderWith dev variant = renderText "ja" "kanji" dev (const (const (0, 0))) (TextLists (pure "・") Nothing Nothing) False Map.empty variant ft

horizontal, vertical :: Book -> [(FilePath, Text)]
horizontal = renderWith False Horizontal
vertical = renderWith False Vertical

-- | The text of the only file.
only :: [(FilePath, Text)] -> Text
only = T.concat . map snd

fidB :: FileId
ft2 :: FileTable
(fidB, ft2) = registerFile "chapters/b.gm" ft

-- | a.gm and b.gm with one note each, in the chapters given.
twoFiles :: Text -> Int -> Int -> [Int] -> [(FilePath, Text)]
twoFiles lang na nb chapters =
  renderText lang "kanji" False (const (const (0, 0))) (TextLists (pure "・") Nothing Nothing) False Map.empty Horizontal ft2 $
    (bookOf [])
      { bookDocs =
          [ Document fid [para 0 [txt "甲", Note (at 1) na (noteBody (at 1) [txt "注甲。"])]],
            Document fidB [Block (mkSpan fidB 0 1) Nothing Nothing (Paragraph Nothing [txt "乙", Note (mkSpan fidB 1 2) nb (noteBody (mkSpan fidB 1 2) [txt "注乙。"])])]
          ],
        bookChapterOf = chapters
      }

tests :: [TestTree]
tests =
  [ testCase "a chapter of two files: its notes at the end of the second, after a title (golem-driver ADR 0026)" $
      twoFiles "ja" 1 2 [0, 0] @?= [("chapters/a.txt", "甲*1\n"), ("chapters/b.txt", "乙*2\n\n注\n*1 注甲。\n*2 注乙。\n")],
    testCase "two chapters each have their notes; Notes in English (golem-driver ADR 0026)" $
      twoFiles "en" 1 1 [0, 1] @?= [("chapters/a.txt", "甲*1\n\nNotes\n*1 注甲。\n"), ("chapters/b.txt", "乙*1\n\nNotes\n*1 注乙。\n")],
    testCase "files after the chapters the manifest gives are each a chapter of their own" $
      let (fidC, ft3) = registerFile "chapters/c.gm" ft2
          noted f n t = Document f [Block (mkSpan f 0 1) Nothing Nothing (Paragraph Nothing [txt t, Note (mkSpan f 1 2) n (noteBody (mkSpan f 1 2) [txt ("注" <> t)])])]
       in renderText "ja" "kanji" False (const (const (0, 0))) (TextLists (pure "・") Nothing Nothing) False Map.empty Horizontal ft3 ((bookOf []) {bookDocs = [noted fid 1 "甲", noted fidB 2 "乙", noted fidC 3 "丙"], bookChapterOf = [0]})
            @?= [("chapters/a.txt", "甲*1\n\n注\n*1 注甲\n"), ("chapters/b.txt", "乙*2\n\n注\n*2 注乙\n"), ("chapters/c.txt", "丙*3\n\n注\n*3 注丙\n")],
    testCase "the title of the notes is 注 for any language that starts with ja, in any case" $
      [lookup "chapters/b.txt" (twoFiles lang 1 1 [0, 1]) | lang <- ["JA", "ja-JP"]]
        @?= replicate 2 (Just "乙*1\n\n注\n*1 注乙。\n"),
    testCase "the last file of a chapter with no text of its own has the title and the notes only" $
      renderText "ja" "kanji" False (const (const (0, 0))) (TextLists (pure "・") Nothing Nothing) False Map.empty Horizontal ft2 ((bookOf []) {bookDocs = [Document fid [para 0 [txt "甲", Note (at 1) 1 (noteBody (at 1) [txt "注甲。"])]], Document fidB []], bookChapterOf = [0, 0]})
        @?= [("chapters/a.txt", "甲*1\n"), ("chapters/b.txt", "注\n*1 注甲。\n")],
    testCase "the file is named after the source with .txt and ends with one newline" $
      horizontal (bookOf [para 0 [txt "本文。"]]) @?= [("chapters/a.txt", "本文。\n")],
    testCase "the first line and the lines after a line break have their own indents (docs/adr ADR 0049)" $ do
      let indented ns = only (renderText "ja" "kanji" False (const (const ns)) (TextLists (pure "・") Nothing Nothing) False Map.empty Horizontal ft (bookOf [para 0 [txt "一行目", LineBreak (at 1), txt "二行目"]]))
      indented (1, 0) @?= "　一行目\n二行目\n"
      indented (1, 1) @?= "　一行目\n　二行目\n",
    testCase "a link: the text and the URL in full-width parentheses; the URL alone when the text is the URL (docs/adr ADR 0182)" $ do
      only (horizontal (bookOf [para 0 [Link (at 1) "https://example.com/" [txt "例"]]])) @?= "例（https://example.com/）\n"
      only (horizontal (bookOf [para 0 [Link (at 1) "https://example.com/" [CharStyle (at 1) "url" [txt "https://example.com/"]]]])) @?= "https://example.com/\n"
      only (horizontal (bookOf [para 0 [Link (at 1) "https://example.com/" [txt "https://example.com/"]]])) @?= "https://example.com/\n",
    testCase "a language span: its characters as they are (docs/adr ADR 0187)" $
      only (horizontal (bookOf [para 0 [txt "英語では", Lang (at 1) "en" [txt "“Tokyo”", Lang (at 2) "fr" [txt " « oui »"]], txt "と書く。"]])) @?= "英語では“Tokyo” « oui »と書く。\n",
    testCase "blocks are separated by one blank line" $
      only (horizontal (bookOf [para 0 [txt "一つ目。"], para 5 [txt "二つ目。"]])) @?= "一つ目。\n\n二つ目。\n",
    testCase "a page reference is the title of the target in corner brackets" $
      let book =
            (bookOf [para 0 [txt "詳しくは", Ref (at 1) RefPage "intro", txt "を見よ。"]])
              { bookLabels = Map.fromList [("intro", LabelTarget (at 9) Nothing [txt "はじめに"] "intro" fid)]
              }
       in only (horizontal book) @?= "詳しくは「はじめに」を見よ。\n",
    testCase "the list of a channel of a plugin: the body of each entry on a line; the item shows nothing (golem-doc ADR 0007)" $
      let item n t = ChannelItem (at n) (ChannelItemData "people" (Just t) Nothing [Text (at n) t])
          entry t n = ChannelEntry (Just t) [Text (at n) t] [(fid, at n)]
          book =
            (bookOf [para 0 [txt "本文", item 1 "甲", item 2 "乙"], Block (at 5) Nothing Nothing (ChannelOutput (CustomOutput "people" Nothing))])
              { bookChannels = [((fid, at 5), "people", [entry "甲" 1, entry "乙" 2])]
              }
       in only (horizontal book) @?= "本文\n\n甲\n乙\n",
    testCase "a citation is its number in square brackets" $
      let book = (bookOf [para 0 [txt "文献", Cite (at 1) [citeItem "knuth1981"], txt "による。"]]) {bookBibliographies = [(Nothing, [("tex", 1), ("knuth1981", 2)])], bookCiteMarks = Map.fromList [((fid, at 1), (Nothing, 2))]}
       in only (horizontal book) @?= "文献[2]による。\n",
    testCase "the marks of several keys and of a page (docs/adr/0266)" $ do
      let marks = [Cite (at 1) (map citeItem ["c", "a", "b"]), Cite (at 2) (map citeItem ["d", "a"]), Cite (at 3) [CiteItem "a" (Just (Locator LocatorPage (LocRange 5 7))) [] []]]
          book = (bookOf [para 0 marks]) {bookBibliographies = [(Nothing, [("a", 1), ("b", 2), ("c", 3), ("d", 5)])], bookCiteMarks = Map.fromList [((fid, at i), (Nothing, 1)) | i <- [1, 2, 3]]}
      only (horizontal book) @?= "[1\x2013\&3][1, 5][1, pp. 5\x2013\&7]\n"
      -- a key without a number: nothing, as a mark of one key
      only (horizontal ((bookOf [para 0 [Cite (at 1) (map citeItem ["a", "x"])]]) {bookBibliographies = [(Nothing, [("a", 1)])], bookCiteMarks = Map.fromList [((fid, at 1), (Nothing, 1))]})) @?= "",
    testCase "C4 (docs/adr/0277): the label of a page and its value stay apart by U+0020, not U+00A0" $ do
      let mark i v = Cite (at i) [CiteItem "a" (Just (Locator LocatorPage v)) [] []]
          book = (bookOf [para 0 [mark 1 (LocNumber 5), mark 2 (LocRange 5 7), mark 3 (LocText "xii")]]) {bookBibliographies = [(Nothing, [("a", 1)])], bookCiteMarks = Map.fromList [((fid, at i), (Nothing, 1)) | i <- [1, 2, 3]]}
          out = only (horizontal book)
      out @?= "[1, p. 5][1, pp. 5\x2013\&7][1, p. xii]\n"
      assertBool "no U+00A0" (not (T.any (== '\xA0') out)),
    testCase "a footnote is *n in horizontal text, its body at the end of the file" $
      let book = bookOf [para 0 [txt "本文", Note (at 1) 1 (noteBody (at 1) [txt "注の本文。"]), txt "。"], para 5 [txt "次の段落。"]]
       in only (horizontal book) @?= "本文*1。\n\n次の段落。\n\n注\n*1 注の本文。\n",
    testCase "I5: a footnote of three paragraphs: the first after its mark, each other on a line of its own, without a mark or an indent (docs/adr/0263)" $
      let body = [Block (at 1) Nothing Nothing (Paragraph Nothing [txt p]) | p <- ["一。", "二。", "三。"]]
       in only (horizontal (bookOf [para 0 [txt "本文", Note (at 1) 1 body]])) @?= "本文*1\n\n注\n*1 一。\n二。\n三。\n",
    testCase "a footnote is ※n in vertical text" $
      only (vertical (bookOf [para 0 [txt "本文", Note (at 1) 1 (noteBody (at 1) [txt "注の本文。"])]])) @?= "本文※1\n\n注\n※1 注の本文。\n",
    testCase "the footnotes of several paragraphs are gathered in order at the end" $
      let book = bookOf [para 0 [txt "甲", Note (at 1) 1 (noteBody (at 1) [txt "一"])], para 5 [txt "乙", Note (at 6) 2 (noteBody (at 6) [txt "二"])]]
       in only (horizontal book) @?= "甲*1\n\n乙*2\n\n注\n*1 一\n*2 二\n",
    testCase "a footnote inside emphasis is still gathered at the end" $
      let book = bookOf [para 0 [CharStyle (at 1) "strong" [txt "強", Note (at 2) 1 (noteBody (at 2) [txt "注"])]]]
       in only (horizontal book) @?= "強*1\n\n注\n*1 注\n",
    testCase "a sidenote is marked ※n and its body follows the paragraph" $
      let book = bookOf [para 0 [txt "本文", Sidenote (at 1) 1 (noteBody (at 1) [txt "補足。"]), txt "。"], para 5 [txt "次。"]]
       in only (horizontal book) @?= "本文※1。\n※1 補足。\n\n次。\n",
    testGroup
      "ruby is base（reading）"
      [ testCase "group ruby" $
          only (horizontal (bookOf [para 0 [Ruby (at 1) () [RubySegment [Text (at 1) "漢字"] (Just "かんじ")]]])) @?= "漢字（かんじ）\n",
        testCase "mono ruby joins the readings of consecutive segments" $
          only (horizontal (bookOf [para 0 [Ruby (at 1) () [RubySegment [Text (at 1) "漢"] (Just "かん"), RubySegment [Text (at 2) "字"] (Just "じ")]]])) @?= "漢字（かんじ）\n",
        testCase "partial ruby writes the segments without a reading as they are" $
          only (horizontal (bookOf [para 0 [Ruby (at 1) () [RubySegment [Text (at 1) "お"] Nothing, RubySegment [Text (at 2) "父"] (Just "とう"), RubySegment [Text (at 3) "さん"] Nothing]]])) @?= "お父（とう）さん\n"
      ],
    testCase "kenten, colour and character styles write only their content" $
      let book = bookOf [para 0 [Kenten (at 1) Nothing [txt "傍点"], Color (at 2) "accent" [txt "色"], CharStyle (at 3) "strong" [txt "強調"]]]
       in only (horizontal book) @?= "傍点色強調\n",
    testGroup
      "numbers"
      [ testCase "a number is arabic in horizontal text" $
          only (horizontal (bookOf [para 0 [Number (at 1) 12 Nothing, txt "章"]])) @?= "12章\n",
        testCase "a number is kanji in vertical text" $
          only (vertical (bookOf [para 0 [Number (at 1) 12 Nothing, txt "章"]])) @?= "十二章\n",
        testCase "a tate-chu-yoko number is kanji in vertical text" $
          only (vertical (bookOf [para 0 [Number (at 1) 12 (Just StyleTcy)]])) @?= "十二\n",
        testCase "kanji-digits is kept in vertical text" $
          only (vertical (bookOf [para 0 [Number (at 1) 2026 (Just StyleKanjiDigits)]])) @?= "二〇二六\n",
        -- golem-parser ADR 0011
        testCase "vertical = auto: kanji, as plain text has no tate-chu-yoko" $ do
          let num def variant n = only (renderText "ja" def False (const (const (0, 0))) (TextLists (pure "・") Nothing Nothing) False Map.empty variant ft (bookOf [para 0 [Number (at 1) n Nothing]]))
          num "auto" Vertical 9 @?= "九\n"
          num "auto" Vertical 99 @?= "九十九\n"
          num "auto" Vertical 100 @?= "百\n"
          num "auto-digits" Vertical 100 @?= "一〇〇\n"
          num "auto" Horizontal 100 @?= "100\n"
      ],
    testCase "a proof comment is written in the dev profile" $
      only (renderWith True Horizontal (bookOf [para 0 [txt "本文", ProofComment (at 1) "要確認"]])) @?= "本文【校正：要確認】\n",
    testCase "a proof comment is dropped in the prod profile" $
      only (renderWith False Horizontal (bookOf [para 0 [txt "本文", ProofComment (at 1) "要確認"]])) @?= "本文\n",
    testCase "a line break is a newline" $
      only (horizontal (bookOf [para 0 [txt "一行目", LineBreak (at 1), txt "二行目"]])) @?= "一行目\n二行目\n",
    testCase "a figure is one line of number and caption in corner brackets" $
      let fig = Figure "a.png" Nothing "代替" Nothing Nothing [para 3 [txt "キャプション"]] Nothing False False
          book = (bookOf [Block (at 0) Nothing Nothing (FigureBlock fig)]) {bookFigures = Map.fromList [(at 0, "図1-1")]}
       in only (horizontal book) @?= "［図1-1　キャプション］\n",
    -- docs/adr/0200
    testCase "a figure without a number is its caption in corner brackets; without a caption either, no line" $ do
      let fig cap = Figure "a.png" Nothing "代替" Nothing Nothing cap Nothing False True
      only (horizontal (bookOf [Block (at 0) Nothing Nothing (FigureBlock (fig [para 3 [txt "キャプション"]]))])) @?= "［キャプション］\n"
      only (horizontal (bookOf [para 0 [txt "前"], Block (at 1) Nothing Nothing (FigureBlock (fig [])), para 2 [txt "後"]])) @?= "前\n\n後\n",
    testCase "a bullet list is ・ and the item" $
      let items = [ListItem Nothing [para 1 [txt "りんご"]], ListItem Nothing [para 2 [txt "みかん"]]]
       in only (horizontal (bookOf [Block (at 0) Nothing Nothing (BulletList items)])) @?= "・りんご\n・みかん\n",
    testCase "an ordered list is 1. in horizontal text" $
      let items = [ListItem Nothing [para 1 [txt "一つ目"]], ListItem Nothing [para 2 [txt "二つ目"]]]
       in only (horizontal (bookOf [Block (at 0) Nothing Nothing (OrderedList items)])) @?= "1. 一つ目\n2. 二つ目\n",
    testCase "an ordered list is 一、 in vertical text" $
      let items = [ListItem Nothing [para 1 [txt "一つ目"]], ListItem Nothing [para 2 [txt "二つ目"]]]
       in only (vertical (bookOf [Block (at 0) Nothing Nothing (OrderedList items)])) @?= "一、一つ目\n二、二つ目\n",
    testCase "a definition list indents the definition by one ideographic space" $
      let group = DefGroup [[txt "用語"]] [[para 2 [txt "説明。"]]]
       in only (horizontal (bookOf [Block (at 0) Nothing Nothing (DefList [group])])) @?= "用語\n　説明。\n",
    testCase "a table separates the cells by tabs" $
      let table = TableBlock (plainTable [] [[txt "名前"], [txt "値"]] [[[txt "a"], [txt "1"]]])
       in only (horizontal (bookOf [Block (at 0) Nothing Nothing table])) @?= "名前\t値\na\t1\n",
    testCase "a table with a caption: the number, the separator and the caption a line before the rows, or after them below (docs/adr/0262)" $ do
      let t = (plainTable [] [[txt "名前"], [txt "値"]] [[[txt "a"], [txt "1"]]]) {tableCaption = Just [txt "題目"]}
          book = (bookOf [Block (at 0) Nothing Nothing (TableBlock t)]) {bookTables = Map.fromList [(at 0, "表1-1")]}
          belowCaption = renderText "ja" "kanji" False (const (const (0, 0))) (TextLists (pure "・") Nothing Nothing) True Map.empty Horizontal ft
      only (horizontal book) @?= "表1-1　題目\n名前\t値\na\t1\n"
      only (belowCaption book) @?= "名前\t値\na\t1\n表1-1　題目\n"
      -- without a number, the caption alone
      only (horizontal (bookOf [Block (at 0) Nothing Nothing (TableBlock t {tableNoNumber = True})])) @?= "題目\n名前\t値\na\t1\n",
    testCase "a code block is written as it is" $
      only (horizontal (bookOf [Block (at 0) Nothing Nothing (CodeBlock (Code (Just "haskell") Nothing Nothing Nothing False [CodeLine "main = pure ()" (Just 1) Nothing False [] Nothing] False))])) @?= "main = pure ()\n",
    testCase "a heading is its number, an ideographic space and its title" $
      let attrs = HeadingAttrs Nothing Nothing False False
          info = HeadingInfo 1 (Just [1]) (Just "第一章") [txt "はじめに"] "h-0-0" fid
          book = (bookOf [Block (at 0) Nothing Nothing (Heading 1 attrs [txt "はじめに"])]) {bookHeadings = Map.fromList [(at 0, info)]}
       in only (horizontal book) @?= "第一章　はじめに\n",
    testCase "the table of contents lists number and title" $
      let entry = TocEntry 1 (Just "第一章") [txt "はじめに"] "intro" fid (at 9)
          book = (bookOf [Block (at 0) Nothing Nothing (ChannelOutput (TocOutput 2))]) {bookToc = [entry]}
       in only (horizontal book) @?= "第一章　はじめに\n",
    testCase "the index and forced breaks write nothing" $
      only (horizontal (bookOf [para 0 [txt "前"], Block (at 2) Nothing Nothing (ChannelOutput IndexOutput), Block (at 3) Nothing Nothing (ForcedBreak BreakPage), para 4 [txt "後"]]))
        @?= "前\n\n後\n",
    testProperty "a paragraph of plain words is the words and one newline" $ property $ do
      ws <- forAll (Gen.list (Range.linear 1 5) (Gen.text (Range.linear 1 6) (Gen.element ("あいう漢字abc" :: String))))
      only (horizontal (bookOf [para 0 (map txt ws)])) === T.concat ws <> "\n",
    -- docs/adr ADR 0019
    testCase "an aki in zw is its whole part in ideographic spaces; an absolute aki is nothing" $
      map
        (\a -> only (horizontal (bookOf [para 0 [txt "a", Aki (at 1) a, txt "b"]])))
        [AkiZw 2, AkiZw 1.5, AkiZw 2.99, AkiZw 0.5, AkiZw 0, AkiZw (-1), AkiAbs (10 * 65536)]
        @?= ["a\x3000\x3000\&b\n", "a\x3000\&b\n", "a\x3000\x3000\&b\n", "ab\n", "ab\n", "ab\n", "ab\n"]
  ]

textOutputTests :: TestTree
textOutputTests = testGroup "plain-text output (golem-text ADR 0001)" tests
