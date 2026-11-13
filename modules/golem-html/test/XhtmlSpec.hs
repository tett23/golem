{- | Small tests of the XHTML and CSS output over hand-built books
(golem-html ADR 0001): colours, notes, ruby, headings, cross references,
the index and citations.
-}
module XhtmlSpec (xhtmlTests) where

import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Assemble (AssembleConfig (..), Book (..), HeadingInfo (..), IndexGroup (..), IndexLocator (..), IndexSection (..), LabelTarget (..), NoteNumbering (..), TocEntry (..), assemble)
import Golem.Assemble.Formats (arabic, kanjiNotation)
import Golem.Assemble.ListMarkers (defaultNumberFormat)
import Golem.Bibliography (EntryPart (..))
import Golem.Doc.IR
import Golem.Html
import Golem.Syntax.Span
import Golem.TestSupport.CssCascade (Elem (..), Page (..), Winner (..), winningMarginStarts)
import Hedgehog (forAll, property, (===))
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testProperty)

-- | a.gm and b.gm, in that order.
fidA, fidB :: FileId
ft :: FileTable
(fidA, fidB, ft) =
  let (a, t1) = registerFile "a.gm" emptyFileTable
      (b, t2) = registerFile "b.gm" t1
   in (a, b, t2)

-- | A span in a.gm; distinct starts keep the blocks apart.
at :: Int -> SrcSpan
at n = mkSpan fidA n (n + 1)

-- | A horizontal Japanese book with no styles.
cfg0 :: HtmlConfig
cfg0 =
  HtmlConfig
    { hcTitle = "本",
      hcLanguage = "ja",
      hcVertical = False,
      hcNumberDefault = "kanji",
      hcSwatches = Map.empty,
      hcFonts = Map.empty,
      hcCharStyles = Map.empty,
      hcParaStyles = Map.empty,
      hcLocalStyles = Map.empty,
      hcCaptionFace = noFace,
      hcSidenoteFace = noFace,
      hcTableFaces = Map.empty,
      hcTableCaptionBelow = False,
      hcIndexSectionHeadings = True,
      hcBibliography = Map.empty,
      hcDev = False,
      hcRubyMonoAlign = "center",
      hcRubyGroupAlign = "space-between",
      hcRubyBaseSpacing = "center",
      hcBreakKinds = Set.empty,
      hcNoBreak = False,
      hcLists = Nothing,
      hcCode = HtmlCode Nothing Nothing Nothing "0.5em" Nothing "0.25pt" False Nothing Nothing Nothing Nothing Map.empty,
      hcHeadingRules = Map.empty,
      hcNoteNotation = arabic
    }

-- | A book of one document, a.gm, with nothing assembled.
bookOf :: [Block] -> Book
bookOf bs =
  Book
    { bookDocs = [Document fidA bs],
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

-- | What is inside the body of a page.
bodyOf :: Text -> Text
bodyOf page =
  let afterOpen = T.drop 2 (snd (T.breakOn ">\n" (snd (T.breakOn "<body" page))))
   in fst (T.breakOn "</body>" afterOpen)

-- | The body of the page of a.gm.
bodyA :: HtmlConfig -> Book -> Text
bodyA cfg book = maybe "" bodyOf (lookup "a.xhtml" (sitePages (renderXhtml cfg ft book)))

-- | The lines of the style sheet that start with a prefix.
cssLines :: Text -> HtmlConfig -> [Text]
cssLines prefix cfg = filter (T.isPrefixOf prefix) (T.lines (siteCss (renderXhtml cfg ft (bookOf []))))

-- | Several @bibliography in a book (golem-doc ADR 0008), over assembled books of a.gm and b.gm.
multipleBibliographyTests :: TestTree
multipleBibliographyTests =
  testGroup
    "the ids of the entries of several @bibliography (golem-doc ADR 0008)"
    [ testCase "a bibliography per chapter: the second B is cite-B-2 and its mark links to it" $ do
        let book =
              assembled
                [ [citing fidA 0 ["A", "B"], bib fidA 5],
                  [citing fidB 0 ["B", "C"], bib fidB 5]
                ]
            pages = sitePages (renderXhtml cfg0 ft book)
            bodyB = maybe "" bodyOf (lookup "b.xhtml" pages)
        ids (bodyA cfg0 book) @?= ["cite-A", "cite-B"]
        ids bodyB @?= ["cite-B-2", "cite-C"]
        assertBool (T.unpack bodyB) ("<span class=\"cite\">[<a href=\"#cite-B-2\">1</a>]</span>" `T.isInfixOf` bodyB),
      testCase "two bibliographies in one file have no id twice" $ do
        let book = assembled [[citing fidA 0 ["x"], bib fidA 5, citing fidA 6 ["x"], bib fidA 10]]
            body = bodyA cfg0 book
        ids body @?= ["cite-x", "cite-x-2"]
        assertBool (T.unpack body) ("href=\"#cite-x-2\"" `T.isInfixOf` body),
      testCase "a candidate taken by another key is skipped: knuth in the second list is cite-knuth-3" $ do
        let book = assembled [[citing fidA 0 ["knuth-2", "knuth"], bib fidA 5, citing fidA 6 ["knuth"], bib fidA 10]]
        ids (bodyA cfg0 book) @?= ["cite-knuth-2", "cite-knuth", "cite-knuth-3"]
    ]
  where
    ids body = [T.takeWhile (/= '"') rest | piece <- drop 1 (T.splitOn "<li id=\"" body), let rest = piece]

-- | A book of a.gm and b.gm with these blocks, assembled (golem-doc ADR 0002).
assembled :: [[Block]] -> Book
assembled bss = fst (assemble acfg (\_ _ _ -> Right "") [Document f bs | (f, bs) <- zip [fidA, fidB] bss])
  where
    acfg = AssembleConfig Map.empty "" Map.empty NumberPerFile [] "" "" Map.empty 40

-- | A paragraph at offset s that cites the keys, one byte apart.
citing :: FileId -> Int -> [Text] -> Block
citing f s ks = Block (mkSpan f s (s + 1)) Nothing Nothing (Paragraph Nothing [Cite (mkSpan f (s + i) (s + i + 1)) [citeItem k] | (i, k) <- zip [0 ..] ks])

-- | A @bibliography at offset s.
bib :: FileId -> Int -> Block
bib f s = Block (mkSpan f s (s + 1)) Nothing Nothing (ChannelOutput BibliographyOutput)

-- | The lists of the channels of plugins (golem-doc ADR 0007).
channelTests :: TestTree
channelTests =
  testGroup
    "the channels of plugins (golem-doc ADR 0007)"
    [ testCase "a channel with locators: an id at each item, links from the list to another file" $ do
        let book = withChannels [[para 0 [txt "人", item fidA 1 "people" "甲"], para 5 [item fidA 6 "people" "甲"]], [list fidB 0 "people"]]
            pages = sitePages (renderXhtml cfg0 ft book)
            bodyB = maybe "" bodyOf (lookup "b.xhtml" pages)
        bodyA cfg0 book @?= "<p>人<span id=\"c-people-0-1\"></span></p>\n<p><span id=\"c-people-0-6\"></span></p>\n"
        bodyB @?= "<section class=\"channel\" data-channel=\"people\">\n<ul>\n<li>甲 <a href=\"a.xhtml#c-people-0-1\">1</a>, <a href=\"a.xhtml#c-people-0-6\">2</a></li>\n</ul>\n</section>\n",
      testCase "a channel without locators: nothing at the item, the bodies in the list" $ do
        let book = withChannels [[para 0 [item fidA 1 "glossary" "語"], list fidA 5 "glossary"]]
        bodyA cfg0 book @?= "<p></p>\n<section class=\"channel\" data-channel=\"glossary\">\n<ul>\n<li>語</li>\n</ul>\n</section>\n",
      testCase "a list without entries is an empty ul" $
        bodyA cfg0 (withChannels [[list fidA 0 "people"]]) @?= "<section class=\"channel\" data-channel=\"people\">\n<ul>\n</ul>\n</section>\n",
      testCase "channels a-1 and a: no id twice" $ do
        let body = bodyA cfg0 (withChannels [[para 0 [item fidA 1 "a-1" "x", item fidA 2 "a" "y"]]])
            ids = [T.takeWhile (/= '"') p | p <- drop 1 (T.splitOn "id=\"" body)]
        ids @?= ["c-a-1-0-1", "c-a-0-2"]
    ]
  where
    decls = [ChannelDecl "people" OrderDocument True, ChannelDecl "glossary" OrderReading False, ChannelDecl "a-1" OrderDocument True, ChannelDecl "a" OrderDocument True]
    withChannels bss = fst (assemble (AssembleConfig Map.empty "" Map.empty NumberPerFile [] "" "" (Map.fromList [(channelName d, d) | d <- decls]) 40) (\_ _ _ -> Right "") [Document f bs | (f, bs) <- zip [fidA, fidB] bss])
    item f s c t = ChannelItem (mkSpan f s (s + 1)) (ChannelItemData c (Just t) (Just t) [Text (mkSpan f s (s + 1)) t])
    list f s c = Block (mkSpan f s (s + 1)) Nothing Nothing (ChannelOutput (CustomOutput c Nothing))

-- | Links from a cite mark to the file of its bibliography (golem-html ADR 0003).
citeLinkTests :: TestTree
citeLinkTests =
  testGroup
    "a cite mark links to the file of its bibliography (golem-html ADR 0003)"
    [ testCase "a bibliography in another file: a relative link to it" $
        bodyA cfg0 (assembled [[citing fidA 0 ["k"]], [bib fidB 0]])
          @?= "<p><span class=\"cite\">[<a href=\"b.xhtml#cite-k\">1</a>]</span></p>\n",
      testCase "without any bibliography: a span, no link" $ do
        let body = bodyA cfg0 (assembled [[citing fidA 0 ["k"]], []])
        body @?= "<p><span class=\"cite\">[1]</span></p>\n"
        assertBool (T.unpack body) (not ("href" `T.isInfixOf` body)),
      testCase "two bibliographies: each mark links to the file of the list it belongs to" $ do
        let book = assembled [[citing fidA 0 ["k"]], [bib fidB 0, citing fidB 5 ["k"], bib fidB 10]]
            bodyB = maybe "" bodyOf (lookup "b.xhtml" (sitePages (renderXhtml cfg0 ft book)))
        bodyA cfg0 book @?= "<p><span class=\"cite\">[<a href=\"b.xhtml#cite-k\">1</a>]</span></p>\n"
        assertBool (T.unpack bodyB) ("<span class=\"cite\">[<a href=\"#cite-k-2\">1</a>]</span>" `T.isInfixOf` bodyB),
      testCase "a mark of several keys: a link for each number shown, none for the middle of a range (docs/adr/0266)" $ do
        let mark ks = Block (mkSpan fidA 0 1) Nothing Nothing (Paragraph Nothing [Cite (mkSpan fidA 0 1) (map citeItem ks)])
        bodyA cfg0 (assembled [[mark ["c", "a", "b"]], [bib fidB 0]])
          @?= "<p><span class=\"cite\">[<a href=\"b.xhtml#cite-c\">1</a>\x2013<a href=\"b.xhtml#cite-b\">3</a>]</span></p>\n"
        bodyA cfg0 (assembled [[mark ["b", "a"]], [bib fidB 0]])
          @?= "<p><span class=\"cite\">[<a href=\"b.xhtml#cite-b\">1</a>, <a href=\"b.xhtml#cite-a\">2</a>]</span></p>\n"
        bodyA cfg0 (assembled [[mark ["b", "a"]], []])
          @?= "<p><span class=\"cite\">[1, 2]</span></p>\n",
      testCase "a mark with a page: the page after the link (docs/adr/0266)" $ do
        let mark = Block (mkSpan fidA 0 1) Nothing Nothing (Paragraph Nothing [Cite (mkSpan fidA 0 1) [CiteItem "k" (Just (Locator LocatorPage (LocRange 5 7))) [] []]])
        bodyA cfg0 (assembled [[mark], [bib fidB 0]])
          @?= "<p><span class=\"cite\">[<a href=\"b.xhtml#cite-k\">1</a>, pp.\xA0\&5\x2013\&7]</span></p>\n",
      testCase "C5 (docs/adr/0277): the label of a page and its value are apart by U+00A0, the rest as before" $ do
        let mark v = Block (mkSpan fidA 0 1) Nothing Nothing (Paragraph Nothing [Cite (mkSpan fidA 0 1) [CiteItem "k" (Just (Locator LocatorPage v)) [] []]])
            html v = bodyA cfg0 (assembled [[mark v], [bib fidB 0]])
            before v = "<p><span class=\"cite\">[<a href=\"b.xhtml#cite-k\">1</a>, " <> v <> "]</span></p>\n"
        html (LocNumber 5) @?= before "p.\xA0\&5"
        html (LocRange 5 7) @?= before "pp.\xA0\&5\x2013\&7"
        html (LocText "xii") @?= before "p.\xA0xii"
        -- a space in the value stays
        html (LocText "5 f.") @?= before "p.\xA0\&5 f."
        -- the U+00A0 is the only change: with U+0020 in its place, the HTML before the ADR
        T.replace "\xA0" " " (html (LocRange 5 7)) @?= "<p><span class=\"cite\">[<a href=\"b.xhtml#cite-k\">1</a>, pp. 5\x2013\&7]</span></p>\n",
      testCase "C5 (docs/adr/0277): a mark without a locator is the HTML before the ADR, byte for byte" $ do
        let mark ks = Block (mkSpan fidA 0 1) Nothing Nothing (Paragraph Nothing [Cite (mkSpan fidA 0 1) (map citeItem ks)])
        bodyA cfg0 (assembled [[mark ["c", "a", "b"]], [bib fidB 0]])
          @?= "<p><span class=\"cite\">[<a href=\"b.xhtml#cite-c\">1</a>\x2013<a href=\"b.xhtml#cite-b\">3</a>]</span></p>\n"
        bodyA cfg0 (assembled [[mark ["b", "a"]], [bib fidB 0]])
          @?= "<p><span class=\"cite\">[<a href=\"b.xhtml#cite-b\">1</a>, <a href=\"b.xhtml#cite-a\">2</a>]</span></p>\n"
        assertBool "no U+00A0" (not (T.any (== '\xA0') (bodyA cfg0 (assembled [[mark ["b", "a"]], [bib fidB 0]])))),
      testCase "a bibliography inside a list item of another file" $ do
        let inList = Block (mkSpan fidB 0 1) Nothing Nothing (BulletList [ListItem Nothing [bib fidB 2]])
        bodyA cfg0 (assembled [[citing fidA 0 ["k"]], [inList]])
          @?= "<p><span class=\"cite\">[<a href=\"b.xhtml#cite-k\">1</a>]</span></p>\n"
    ]

-- | A span in b.gm.
atB :: Int -> SrcSpan
atB n = mkSpan fidB n (n + 1)

-- | a.gm and b.gm with one note each, in the chapters given.
twoFileBook :: Int -> Int -> [Int] -> Book
twoFileBook na nb chapters =
  (bookOf [])
    { bookDocs =
        [ Document fidA [para 0 [txt "甲", Note (at 1) na (noteBody (at 1) [txt "注甲。"])]],
          Document fidB [Block (atB 0) Nothing Nothing (Paragraph Nothing [txt "乙", Note (atB 1) nb (noteBody (atB 1) [txt "注乙。"])])]
        ],
      bookChapterOf = chapters
    }

pageOf :: FilePath -> HtmlConfig -> Book -> Text
pageOf p cfg book = maybe "" bodyOf (lookup p (sitePages (renderXhtml cfg ft book)))

chapterNoteTests :: [TestTree]
chapterNoteTests =
  [ testCase "the links of notes in the notation of mark-format, without the text around it (docs/adr/0177)" $ do
      let book = twoFileBook 3 3 [0, 1]
          kanjiCfg = cfg0 {hcNoteNotation = kanjiNotation}
      assertBool "noteref" ("id=\"noteref-3\">三</a>" `T.isInfixOf` pageOf "a.xhtml" kanjiCfg book)
      assertBool "the way back" ("<a href=\"#noteref-3\">三</a> 注甲。" `T.isInfixOf` pageOf "a.xhtml" kanjiCfg book),
    testCase "the links of notes of the default format are Arabic, as before (docs/adr/0177)" $ do
      let book = twoFileBook 3 3 [0, 1]
      assertBool "noteref" ("id=\"noteref-3\">3</a>" `T.isInfixOf` pageOf "a.xhtml" cfg0 book)
      assertBool "the way back" ("<a href=\"#noteref-3\">3</a> 注甲。" `T.isInfixOf` pageOf "a.xhtml" cfg0 book),
    testCase "a chapter of two files: the notes of both at the end of the second, linked across" $ do
      let book = twoFileBook 1 2 [0, 0]
      pageOf "a.xhtml" cfg0 book @?= "<p>甲<a epub:type=\"noteref\" class=\"noteref\" href=\"b.xhtml#note-1\" id=\"noteref-1\">1</a></p>\n"
      pageOf "b.xhtml" cfg0 book
        @?= T.concat
          [ "<p>乙<a epub:type=\"noteref\" class=\"noteref\" href=\"#note-2\" id=\"noteref-2\">2</a></p>\n",
            "<section class=\"notes\">\n<h2>注</h2>\n",
            "<aside epub:type=\"footnote\" id=\"note-1\"><p><a href=\"a.xhtml#noteref-1\">1</a> 注甲。</p></aside>\n",
            "<aside epub:type=\"footnote\" id=\"note-2\"><p><a href=\"#noteref-2\">2</a> 注乙。</p></aside>\n",
            "</section>\n"
          ],
    testCase "two chapters of a file each keep their notes" $ do
      let book = twoFileBook 1 1 [0, 1]
      assertBool "a has its notes" ("id=\"note-1\"><p><a href=\"#noteref-1\">" `T.isInfixOf` pageOf "a.xhtml" cfg0 book)
      assertBool "b has its notes" ("id=\"note-1\"><p><a href=\"#noteref-1\">" `T.isInfixOf` pageOf "b.xhtml" cfg0 book),
    testCase "numbers that meet in a chapter take the place of the file in their ids" $ do
      let book = twoFileBook 1 1 [0, 0]
      assertBool "a" ("href=\"b.xhtml#note-1-1\" id=\"noteref-1-1\"" `T.isInfixOf` pageOf "a.xhtml" cfg0 book)
      let b = pageOf "b.xhtml" cfg0 book
      assertBool "b ref" ("href=\"#note-2-1\" id=\"noteref-2-1\"" `T.isInfixOf` b)
      assertBool "b note 1" ("id=\"note-1-1\"><p><a href=\"a.xhtml#noteref-1-1\">1</a>" `T.isInfixOf` b)
      assertBool "b note 2" ("id=\"note-2-1\"><p><a href=\"#noteref-2-1\">1</a>" `T.isInfixOf` b),
    testCase "the title of the notes is Notes in an English book" $
      assertBool "Notes" ("<h2>Notes</h2>" `T.isInfixOf` pageOf "b.xhtml" cfg0 {hcLanguage = "en"} (twoFileBook 1 2 [0, 0])),
    testCase "the title is not in the navigation of the page" $
      assertBool "no nav" (not ("注" `T.isInfixOf` T.concat [t | (_, t) <- sitePages (renderXhtml cfg0 ft (twoFileBook 1 2 [0, 0])), "<nav" `T.isInfixOf` t]))
  ]

-- | A paragraph style that sets nothing but its rules.
ruled :: Maybe HtmlRule -> Maybe HtmlRule -> HtmlParaStyle
ruled b a = HtmlParaStyle Nothing False 0 "0" "0" noFeatures b a defaultAlignDecls 0 0 "0em" [] Nothing

-- | A paragraph style of the defaults of body (docs/adr/0189).
plainPara :: HtmlParaStyle
plainPara = HtmlParaStyle Nothing False 0 "0em" "0em" noFeatures Nothing Nothing defaultAlignDecls 0 0 "0em" [] Nothing

-- | The rules of the CSS that have a declaration of the keys of docs/adr/0189, but those of the cells of tables.
alignSpaceLines :: HtmlConfig -> [Text]
alignSpaceLines cfg = [l | l <- cssLines "" cfg, not (".align-" `T.isPrefixOf` l), any (`T.isInfixOf` l) ["text-align: justify", "text-align: start", "text-align: end", "text-align: center", "text-align: left", "text-align: right", "padding-inline-end", "margin-block-start"]]

alignSpaceTests :: [TestTree]
alignSpaceTests =
  [ testCase "the defaults write no rule" $
      alignSpaceLines cfg0 {hcParaStyles = Map.fromList [("body", plainPara), ("quote", plainPara)]} @?= [],
    testCase "the alignment of body when it is not the default, of another style when it is not that of body" $ do
      let centre = plainPara {hpsAlign = ["text-align: center"]}
      alignSpaceLines cfg0 {hcParaStyles = Map.fromList [("body", centre), ("quote", centre), ("letter", plainPara)]}
        @?= ["p { text-align: center; }", "p.ps-letter { text-align: justify; text-align-last: start; }"]
      alignSpaceLines cfg0 {hcParaStyles = Map.fromList [("body", plainPara), ("quote", centre)]}
        @?= ["p.ps-quote { text-align: center; }"],
    testCase "end-indent is padding-inline-end" $
      alignSpaceLines cfg0 {hcParaStyles = Map.fromList [("body", plainPara), ("quote", plainPara {hpsEndIndent = "2em"})]}
        @?= ["p.ps-quote { padding-inline-end: 2em; }"],
    testCase "the space before and after, the pairs after them, the same style and after a blank line" $
      alignSpaceLines cfg0 {hcParaStyles = Map.fromList [("body", plainPara), ("a", plainPara {hpsSpaceAfter = 2}), ("b", plainPara {hpsSpaceBefore = 1, hpsSpaceBetween = 1})]}
        @?= [ "p.ps-a + p.ps-a { margin-block-start: 0; }",
              "p.ps-b + p.ps-b { margin-block-start: 1em; }",
              "p.ps-b { margin-block-start: 1em; }",
              "p.ps-a + :not(.ps-a):not(.blank-line) { margin-block-start: 2em; }",
              "p.ps-a + p.ps-b:not(.ps-a) { margin-block-start: 2em; }",
              "div.blank-line + p.ps-b { margin-block-start: 0; }"
            ],
    testCase "the space after body: the next element without the class of body, not a blank line" $
      alignSpaceLines cfg0 {hcParaStyles = Map.fromList [("body", plainPara {hpsSpaceAfter = 1}), ("quote", plainPara {hpsSpaceBefore = 2})]}
        @?= [ "p + p { margin-block-start: 0; }",
              "p.ps-quote + p.ps-quote { margin-block-start: 0; }",
              "p.ps-quote { margin-block-start: 2em; }",
              "p:not([class]) + :not(p):not(.blank-line), p:not([class]) + p[class] { margin-block-start: 1em; }",
              "p:not([class]) + p.ps-quote { margin-block-start: 2em; }",
              "div.blank-line + p.ps-quote { margin-block-start: 0; }"
            ],
    testCase "a file's styles write the alignment, the end indent and the spaces again" $ do
      let local = HtmlLocalStyles Map.empty (Map.fromList [("quote", plainPara {hpsAlign = ["text-align: end"], hpsEndIndent = "1em", hpsSpaceBefore = 1})]) Nothing Nothing Map.empty
          cfg = cfg0 {hcParaStyles = Map.fromList [("body", plainPara), ("quote", plainPara)], hcLocalStyles = Map.fromList [(fidA, local)]}
      cssLines "body.file-1 p.ps-quote {" cfg
        @?= ["body.file-1 p.ps-quote { font-family: inherit; margin-block: 1em; margin-block-start: 1em; padding-inline-start: 0em; text-indent: 0em; padding-inline-end: 1em; text-align: end; }"]
      cssLines "body.file-1 p.ps-quote + p.ps-quote" cfg @?= ["body.file-1 p.ps-quote + p.ps-quote { margin-block-start: 0; }"]
      cssLines "body.file-1 div.blank-line" cfg @?= ["body.file-1 div.blank-line + p.ps-quote { margin-block-start: 0; }"]
      let reset = HtmlLocalStyles Map.empty (Map.fromList [("quote", plainPara {hpsEndIndent = "1em"})]) Nothing Nothing Map.empty
      cssLines "body.file-1 p.ps-quote {" cfg {hcLocalStyles = Map.fromList [(fidA, reset)]}
        @?= ["body.file-1 p.ps-quote { font-family: inherit; margin-block: 1em; padding-inline-start: 0em; text-indent: 0em; padding-inline-end: 1em; text-align: start; text-align-last: auto; }"]
  ]

-- | The winning margin-block-start of each element of a page of the site's CSS (docs/adr/0217).
winners :: HtmlConfig -> Page -> [Maybe Text]
winners cfg page = either error (map (fmap wValue)) (winningMarginStarts (siteCss (renderXhtml cfg ft (bookOf []))) page)

fileSpaceTests :: [TestTree]
fileSpaceTests =
  [ testCase "H2: a space after put back to 0 in the file leaves no rule of style.toml on its pages" $ do
      let cfg = cfg0 {hcParaStyles = Map.fromList [("body", plainPara), ("note", plainPara {hpsSpaceAfter = 2})], hcLocalStyles = Map.fromList [(fidA, local [("note", plainPara)])]}
      winners cfg (Page ["file-1"] [Elem "p" ["ps-note"], Elem "p" []]) @?= [Just "1em", Nothing]
      -- the pages of the other files keep the rule of style.toml
      winners cfg (Page [] [Elem "p" ["ps-note"], Elem "p" []]) @?= [Nothing, Just "2em"],
    testCase "H1: a pair whose space before is put back to 0 in the file is the space after" $ do
      let cfg = cfg0 {hcParaStyles = Map.fromList [("body", plainPara), ("a", plainPara {hpsSpaceAfter = 1}), ("b", plainPara {hpsSpaceBefore = 3})], hcLocalStyles = Map.fromList [(fidA, local [("b", plainPara)])]}
      winners cfg (Page ["file-1"] [Elem "p" ["ps-a"], Elem "p" ["ps-b"]]) @?= [Nothing, Just "1em"]
      winners cfg (Page [] [Elem "p" ["ps-a"], Elem "p" ["ps-b"]]) @?= [Nothing, Just "3em"],
    testCase "H1: body put back to 0 in the file, the space before of another style is kept on the other pages" $ do
      let cfg = cfg0 {hcParaStyles = Map.fromList [("body", plainPara {hpsSpaceBefore = 1}), ("b", plainPara {hpsSpaceBefore = 3})], hcLocalStyles = Map.fromList [(fidA, local [("body", plainPara)])]}
      winners cfg (Page [] [Elem "h2" [], Elem "p" ["ps-b"]]) @?= [Nothing, Just "3em"]
      winners cfg (Page ["file-1"] [Elem "h2" [], Elem "p" ["ps-b"]]) @?= [Nothing, Just "3em"],
    testCase "H4: no file defines a paragraph style, no :not() of the files" $ do
      let cfg = cfg0 {hcParaStyles = Map.fromList [("body", plainPara {hpsSpaceAfter = 1}), ("b", plainPara {hpsSpaceBefore = 3})]}
      filter (".file-" `T.isInfixOf`) (cssLines "" cfg) @?= []
  ]
  where
    local ps = HtmlLocalStyles Map.empty (Map.fromList ps) Nothing Nothing Map.empty

-- | A paragraph style of a box of a key with its declarations (docs/adr/0271).
boxed :: Text -> HtmlParaStyle
boxed key = plainPara {hpsBox = Just (HtmlBox key ["background-color: rgb(230, 230, 230)", "padding: 0.5em"])}

-- | A paragraph of a style.
styled :: Int -> Text -> Block
styled n st = Block (at n) Nothing Nothing (Paragraph (Just st) [txt "x"])

boxTests :: [TestTree]
boxTests =
  [ testCase "paragraphs of equal boxes in a row are one div of the class of the first; another box or none is not in it" $ do
      let cfg = cfg0 {hcParaStyles = Map.fromList [("body", plainPara), ("col", boxed "a"), ("title", boxed "a"), ("note", boxed "b")]}
          body = bodyA cfg (bookOf [styled 0 "title", styled 1 "col", para 2 [txt "y"], styled 3 "col", styled 4 "note"])
      body
        @?= T.concat
          [ "<div class=\"box box-title\">\n<p class=\"ps-title\">x</p>\n<p class=\"ps-col\">x</p>\n</div>\n",
            "<p>y</p>\n",
            "<div class=\"box box-col\">\n<p class=\"ps-col\">x</p>\n</div>\n",
            "<div class=\"box box-note\">\n<p class=\"ps-note\">x</p>\n</div>\n"
          ],
    testCase "a break before goes on the div; a paragraph that starts a page starts another box; a blank line ends one" $ do
      let cfg = cfg0 {hcParaStyles = Map.fromList [("body", plainPara), ("col", boxed "a"), ("top", (boxed "a") {hpsBreaks = ["break-before: page"]})]}
          body = bodyA cfg (bookOf [Block (at 0) Nothing Nothing (ForcedBreak BreakPage), styled 1 "col", styled 2 "top", Block (at 3) Nothing Nothing (BlankLines 1), styled 4 "col"])
      body
        @?= T.concat
          [ "<div class=\"box box-col\" data-break-before=\"page\">\n<p class=\"ps-col\">x</p>\n</div>\n",
            "<div class=\"box box-top\">\n<p class=\"ps-top\">x</p>\n</div>\n",
            "<div class=\"blank-line\"><br/></div>\n",
            "<div class=\"box box-col\">\n<p class=\"ps-col\">x</p>\n</div>\n"
          ],
    testCase "the rule of the box; no indent and no outer margin of the paragraphs in a box; the spaces before and after on the box" $ do
      let cfg = cfg0 {hcParaStyles = Map.fromList [("body", plainPara {hpsSpaceAfter = 2}), ("col", (boxed "a") {hpsSpaceBefore = 1, hpsSpaceAfter = 3})]}
      cssLines "div.box" cfg
        @?= [ "div.box-col { background-color: rgb(230, 230, 230); padding: 0.5em; }",
              "div.box > p { padding-inline-start: 0; padding-inline-end: 0; }",
              "div.box > p:first-child { margin-block-start: 0; }",
              "div.box > p:last-child { margin-block-end: 0; }",
              "div.box:has(> p.ps-col:first-child) { margin-block-start: 1em; }",
              "div.box:has(> p.ps-col:last-child) { margin-block-end: 3em; }"
            ]
      cssLines "p:not([class]) + div.box" cfg @?= ["p:not([class]) + div.box:has(> p.ps-col:first-child) { margin-block-start: 2em; }"],
    testCase "a book without boxes writes no rule of a box, and the rule of pre is as it was" $ do
      let cfg = cfg0 {hcParaStyles = Map.fromList [("body", plainPara), ("col", boxed "a")]}
      cssLines "div.box" cfg0 {hcParaStyles = Map.fromList [("body", plainPara)]} @?= []
      cssLines "pre" cfg @?= cssLines "pre" cfg0
  ]

-- | A solid rule of 0.5pt as wide as the line, 1em above and nothing below.
solid :: HtmlRule
solid = HtmlRule (Just "100%") Nothing Nothing "0.5pt solid" "1em" "0"

ruleTests :: [TestTree]
ruleTests =
  [ testCase "the rule before a paragraph style is its ::before, a block with a border, space-before above and space-after below" $
      cssLines "p.ps-sec::" cfg0 {hcParaStyles = Map.fromList [("sec", ruled (Just solid) Nothing)]}
        @?= ["p.ps-sec::before { content: \"\"; display: block; width: 100%; border-block-start: 0.5pt solid; margin-block: 1em 0; }"],
    testCase "the rule after is ::after with the same order of spaces" $
      cssLines "p.ps-sec::" cfg0 {hcParaStyles = Map.fromList [("sec", ruled Nothing (Just solid {hrOuter = "2pt", hrInner = "3pt"}))]}
        @?= ["p.ps-sec::after { content: \"\"; display: block; width: 100%; border-block-start: 0.5pt solid; margin-block: 2pt 3pt; }"],
    testCase "indents without a width are margin-inline-start and margin-inline-end, and no width" $
      cssLines "p.ps-sec::" cfg0 {hcParaStyles = Map.fromList [("sec", ruled (Just (HtmlRule Nothing (Just "-2em") (Just "1em") "1pt dashed rgb(255, 0, 0)" "0" "0")) Nothing)]}
        @?= ["p.ps-sec::before { content: \"\"; display: block; border-block-start: 1pt dashed rgb(255, 0, 0); margin-block: 0 0; margin-inline-start: -2em; margin-inline-end: 1em; }"],
    testCase "the rules of the body style go to the paragraphs without a class" $
      map (T.takeWhile (/= ' ')) (cssLines "p:not([class])::" cfg0 {hcParaStyles = Map.fromList [("body", ruled (Just solid) (Just solid))]})
        @?= ["p:not([class])::before", "p:not([class])::after"],
    testCase "the code style writes no rules" $
      filter ("::" `T.isInfixOf`) (cssLines "p" cfg0 {hcParaStyles = Map.fromList [("code", ruled (Just solid) (Just solid))]}) @?= [],
    testCase "the rules of a heading level are h<level>::before and ::after; a level without rules writes none" $
      map (T.takeWhile (/= ' ')) (cssLines "h" cfg0 {hcHeadingRules = Map.fromList [(1, (Nothing, Nothing)), (3, (Just solid, Just solid))]})
        @?= ["h3::before", "h3::after"]
  ]

tests :: [TestTree]
tests =
  [ testGroup "the rules of paragraph styles and headings (golem-driver ADR 0027)" ruleTests,
    testGroup "the boxes of paragraph styles (docs/adr/0271)" boxTests,
    testGroup "the alignment, spaces and end indent of paragraph styles (docs/adr/0189)" alignSpaceTests,
    testGroup "the spaces of paragraph styles redefined in files (docs/adr/0217)" fileSpaceTests,
    testGroup "blocks" blockTests,
    testGroup
      "colours: R = 255 × (1 − C) × (1 − K), rounded"
      [ testCase "white for no ink" $ cmykToRgb (0, 0, 0, 0) @?= (255, 255, 255),
        testCase "black for full K" $ cmykToRgb (0, 0, 0, 100) @?= (0, 0, 0),
        -- 255 × 0.8 × 0.9 = 183.6, 255 × 0.6 × 0.9 = 137.7, 255 × 0.4 × 0.9 = 91.8
        testCase "K scales every channel" $ cmykToRgb (20, 40, 60, 10) @?= (184, 138, 92),
        testCase "a swatch is a CSS rule with rgb()" $
          -- 255 × 0.2 = 51
          cssLines ".swatch-" cfg0 {hcSwatches = Map.fromList [("accent", (0, 80, 100, 0))]} @?= [".swatch-accent { color: rgb(255, 51, 0); }"],
        testCase "a character style with a swatch has its rgb() colour" $
          let term = HtmlCharStyle Nothing False False (Just "accent") noFeatures False Nothing Nothing Nothing [] False
              cfg = cfg0 {hcSwatches = Map.fromList [("accent", (0, 80, 100, 0))], hcCharStyles = Map.fromList [("term", term)]}
           in cssLines ".cs-term" cfg @?= [".cs-term { color: rgb(255, 51, 0); }"],
        -- the background and the padding of inline code (golem-driver ADR 0029)
        testCase "code with a background: background-color and padding-inline" $
          let code = HtmlCharStyle Nothing False False Nothing noFeatures True (Just "code-bg") (Just "0.25em") Nothing [] False
              cfg = cfg0 {hcSwatches = Map.fromList [("code-bg", (0, 0, 0, 8))], hcCharStyles = Map.fromList [("code", code)]}
           in cssLines "code {" cfg @?= ["code { background-color: rgb(235, 235, 235); padding-inline: 0.25em; }"],
        testCase "a style based on code with a background: the same two in its cs- rule" $
          let path = HtmlCharStyle Nothing False False Nothing noFeatures True (Just "code-bg") (Just "0.25em") Nothing [] False
              cfg = cfg0 {hcSwatches = Map.fromList [("code-bg", (0, 0, 0, 8))], hcCharStyles = Map.fromList [("path", path)]}
           in cssLines ".cs-path" cfg @?= [".cs-path { hyphens: none; background-color: rgb(235, 235, 235); padding-inline: 0.25em; }"],
        testCase "a file's code style without a background resets them: transparent and 0" $
          let code = HtmlCharStyle Nothing False False Nothing noFeatures True Nothing Nothing Nothing [] False
              cfg = cfg0 {hcLocalStyles = Map.fromList [(fidA, HtmlLocalStyles (Map.fromList [("code", code)]) Map.empty Nothing Nothing Map.empty)]}
           in cssLines "body.file-1 code" cfg
                @?= ["body.file-1 code { font-family: inherit; font-weight: normal; font-style: normal; color: inherit; background-color: transparent; padding-inline: 0; }"],
        testCase "a file's code style with a background has its rgb() and padding" $
          let code = HtmlCharStyle Nothing False False Nothing noFeatures True (Just "code-bg") (Just "0.25em") Nothing [] False
              cfg = cfg0 {hcSwatches = Map.fromList [("code-bg", (0, 0, 0, 8))], hcLocalStyles = Map.fromList [(fidA, HtmlLocalStyles (Map.fromList [("code", code)]) Map.empty Nothing Nothing Map.empty)]}
           in cssLines "body.file-1 code" cfg
                @?= ["body.file-1 code { font-family: inherit; font-weight: normal; font-style: normal; color: inherit; background-color: rgb(235, 235, 235); padding-inline: 0.25em; }"],
        testCase "a file's character style that is not code has no background" $
          let term = HtmlCharStyle Nothing False False Nothing noFeatures False (Just "code-bg") (Just "0.25em") Nothing [] False
              cfg = cfg0 {hcSwatches = Map.fromList [("code-bg", (0, 0, 0, 8))], hcLocalStyles = Map.fromList [(fidA, HtmlLocalStyles (Map.fromList [("term", term)]) Map.empty Nothing Nothing Map.empty)]}
           in cssLines "body.file-1 .cs-term" cfg
                @?= ["body.file-1 .cs-term { font-family: inherit; font-weight: normal; font-style: normal; color: inherit; }"],
        testCase "a background swatch that is not defined writes no background-color" $
          let code = HtmlCharStyle Nothing False False Nothing noFeatures True (Just "nowhere") (Just "0.25em") Nothing [] False
              cfg = cfg0 {hcCharStyles = Map.fromList [("code", code)]}
           in cssLines "code {" cfg @?= ["code { padding-inline: 0.25em; }"],
        -- a range that does not break (docs/adr ADR 0272)
        testCase "a character style that does not break: white-space: nowrap in its cs- rule" $
          let nb = HtmlCharStyle Nothing False False Nothing noFeatures False Nothing Nothing Nothing [] True
              cfg = cfg0 {hcCharStyles = Map.fromList [("no-break", nb)]}
           in cssLines ".cs-no-break" cfg @?= [".cs-no-break { white-space: nowrap; }"],
        testCase "a soft hyphen stays as it is in the HTML (docs/adr ADR 0272)" $
          bodyA cfg0 (bookOf [para 0 [txt "in\xAD\&com"]]) @?= "<p>in\xAD\&com</p>\n",
        testCase "code without a background: padding-inline only" $
          let code = HtmlCharStyle Nothing False False Nothing noFeatures True Nothing (Just "0.25em") Nothing [] False
              cfg = cfg0 {hcCharStyles = Map.fromList [("code", code)]}
           in cssLines "code {" cfg @?= ["code { padding-inline: 0.25em; }"],
        -- the OpenType features of a style (docs/adr/0268)
        testCase "features are one font-feature-settings" $
          let sc = HtmlCharStyle Nothing False False Nothing noFeatures {hfOpenType = [("smcp", 1), ("liga", 0)]} False Nothing Nothing Nothing [] False
              cfg = cfg0 {hcCharStyles = Map.fromList [("sc", sc)]}
           in cssLines ".cs-sc" cfg @?= [".cs-sc { font-feature-settings: \"smcp\" 1, \"liga\" 0; }"],
        testCase "proportional-metrics adds palt to the end of the same declaration" $
          let sc = HtmlCharStyle Nothing False False Nothing noFeatures {hfOpenType = [("smcp", 1), ("liga", 0), ("salt", 2)], hfProportional = Just True} False Nothing Nothing Nothing [] False
              cfg = cfg0 {hcCharStyles = Map.fromList [("sc", sc)]}
           in cssLines ".cs-sc" cfg @?= [".cs-sc { font-feature-settings: \"smcp\" 1, \"liga\" 0, \"salt\" 2, \"palt\" 1; }"],
        testCase "a paragraph style's features are in its rule" $
          let ps = plainPara {hpsFeatures = noFeatures {hfOpenType = [("tnum", 1)]}}
              cfg = cfg0 {hcParaStyles = Map.fromList [("table-cell", ps)]}
           in assertBool (show (cssLines "p.ps-table-cell" cfg)) (any ("font-feature-settings: \"tnum\" 1;" `T.isInfixOf`) (cssLines "p.ps-table-cell" cfg)),
        testCase "a style without features has the CSS of before" $
          let tight = HtmlCharStyle Nothing False False Nothing noFeatures {hfProportional = Just True} False Nothing Nothing Nothing [] False
              cfg = cfg0 {hcCharStyles = Map.fromList [("tight", tight)]}
           in cssLines ".cs-tight" cfg @?= [".cs-tight { font-feature-settings: \"palt\" 1; }"],
        -- superscript and subscript (docs/adr/0269)
        testCase "the built-in superscript and subscript are sup and sub without a class" $
          let pos e = HtmlCharStyle Nothing False False Nothing noFeatures False Nothing Nothing (Just e) [] False
              cfg = cfg0 {hcCharStyles = Map.fromList [("superscript", pos "sup"), ("subscript", pos "sub")]}
           in bodyA cfg (bookOf [para 0 [txt "m", CharStyle (at 1) "superscript" [txt "2"], txt "H", CharStyle (at 2) "subscript" [txt "2"], txt "O"]])
                @?= "<p>m<sup>2</sup>H<sub>2</sub>O</p>\n",
        testCase "another style of a position is sup or sub with its class" $
          let x = HtmlCharStyle Nothing False False Nothing noFeatures False Nothing Nothing (Just "sup") [] False
              cfg = cfg0 {hcCharStyles = Map.fromList [("x", x)]}
           in bodyA cfg (bookOf [para 0 [CharStyle (at 1) "x" [txt "2"]]]) @?= "<p><sup class=\"cs-x\">2</sup></p>\n",
        testCase "coloured text is a span with the class of its swatch" $
          bodyA cfg0 (bookOf [para 0 [Color (at 1) "accent" [txt "赤"]]]) @?= "<p><span class=\"swatch-accent\">赤</span></p>\n"
      ],
    testCase "the page is polyglot XHTML in the language of the book" $
      let page = fromMaybe "" (lookup "a.xhtml" (sitePages (renderXhtml cfg0 ft (bookOf [para 0 [txt "本文"]]))))
       in T.takeWhile (/= '>') (snd (T.breakOn "<html" page)) @?= "<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"http://www.idpf.org/2007/ops\" lang=\"ja\" xml:lang=\"ja\"",
    testCase "text is escaped for XML" $
      bodyA cfg0 (bookOf [para 0 [txt "a < b & \"c\" > d"]]) @?= "<p>a &lt; b &amp; &quot;c&quot; &gt; d</p>\n",
    testCase "a sidenote is a numbered mark and an aside after the paragraph" $
      bodyA cfg0 (bookOf [para 0 [txt "本文", Sidenote (at 1) 1 (noteBody (at 1) [txt "補足。"]), txt "。"]])
        @?= "<p>本文<sup class=\"sidenote-ref\">1</sup>。</p>\n<aside class=\"sidenote\"><span class=\"number\">1</span>補足。</aside>\n",
    testCase "sidenotes are smaller than the text when no size is given (golem-driver ADR 0011)" $
      cssLines ".sidenote" cfg0 @?= [".sidenote { font-size: 0.85em; }"],
    testCase "I5: a note of two paragraphs is a p for each, the link back at the start of the first (docs/adr/0263)" $
      bodyA cfg0 (bookOf [para 0 [txt "本文", Note (at 1) 1 [Block (at 1) Nothing Nothing (Paragraph Nothing [txt p]) | p <- ["一。", "二。"]]]])
        @?= T.concat
          [ "<p>本文<a epub:type=\"noteref\" class=\"noteref\" href=\"#note-1\" id=\"noteref-1\">1</a></p>\n",
            "<section class=\"notes\">\n<h2>注</h2>\n",
            "<aside epub:type=\"footnote\" id=\"note-1\"><p><a href=\"#noteref-1\">1</a> 一。</p><p>二。</p></aside>\n",
            "</section>\n"
          ],
    testCase "style.css takes the margins and the indents off the paragraphs of notes (docs/adr/0263)" $
      cssLines "section.notes" cfg0 @?= ["section.notes aside p { margin-block: 0; padding-inline-start: 0; text-indent: 0; }"],
    testCase "a footnote links to its note at the end of the file, which links back" $
      bodyA cfg0 (bookOf [para 0 [txt "本文", Note (at 1) 1 (noteBody (at 1) [txt "注の本文。"])], para 5 [txt "次。"]])
        @?= T.concat
          [ "<p>本文<a epub:type=\"noteref\" class=\"noteref\" href=\"#note-1\" id=\"noteref-1\">1</a></p>\n",
            "<p>次。</p>\n",
            "<section class=\"notes\">\n<h2>注</h2>\n",
            "<aside epub:type=\"footnote\" id=\"note-1\"><p><a href=\"#noteref-1\">1</a> 注の本文。</p></aside>\n",
            "</section>\n"
          ],
    testGroup "notes at the end of the chapter (golem-driver ADR 0026)" chapterNoteTests,
    testGroup
      "ruby"
      [ testCase "group ruby is one rt between rp" $
          bodyA cfg0 (bookOf [para 0 [Ruby (at 1) () [RubySegment [Text (at 1) "漢字"] (Just "かんじ")]]])
            @?= "<p><ruby>漢字<rp>（</rp><rt>かんじ</rt><rp>）</rp></ruby></p>\n",
        testCase "mono ruby has one rt per segment" $
          bodyA cfg0 (bookOf [para 0 [Ruby (at 1) () [RubySegment [Text (at 1) "漢"] (Just "かん"), RubySegment [Text (at 2) "字"] (Just "じ")]]])
            @?= "<p><ruby class=\"mono\">漢<rp>（</rp><rt>かん</rt><rp>）</rp>字<rp>（</rp><rt>じ</rt><rp>）</rp></ruby></p>\n"
      ],
    testCase "kenten is a span with the class of its shape" $
      bodyA cfg0 (bookOf [para 0 [Kenten (at 1) (Just "dot") [txt "傍点"]]]) @?= "<p><span class=\"kenten kenten-dot\">傍点</span></p>\n",
    testCase "tate-chu-yoko is a span of class tcy" $
      bodyA cfg0 (bookOf [para 0 [Tcy (at 1) "12"]]) @?= "<p><span class=\"tcy\">12</span></p>\n",
    testCase "a number is kanji in a vertical book" $
      bodyA cfg0 {hcVertical = True} (bookOf [para 0 [Number (at 1) 12 Nothing]]) @?= "<p>十二</p>\n",
    testCase "a number is arabic in a horizontal book" $
      bodyA cfg0 (bookOf [para 0 [Number (at 1) 12 Nothing]]) @?= "<p>12</p>\n",
    -- golem-parser ADR 0011
    testCase "vertical = auto: two digits or fewer in tate-chu-yoko, the others in kanji" $ do
      let num cfg n = bodyA cfg (bookOf [para 0 [Number (at 1) n Nothing]])
          auto = cfg0 {hcVertical = True, hcNumberDefault = "auto"}
      num auto 9 @?= "<p><span class=\"tcy\">9</span></p>\n"
      num auto 99 @?= "<p><span class=\"tcy\">99</span></p>\n"
      num auto 100 @?= "<p>百</p>\n"
      num auto {hcNumberDefault = "auto-digits"} 100 @?= "<p>一〇〇</p>\n"
      num auto {hcVertical = False} 100 @?= "<p>100</p>\n",
    testCase "a heading is h1 with the anchor of the heading as id" $
      let info = HeadingInfo 1 Nothing Nothing [txt "はじめに"] "intro" fidA
          book = (bookOf [Block (at 0) (Just "intro") Nothing (Heading 1 (HeadingAttrs Nothing Nothing True False) [txt "はじめに"])]) {bookHeadings = Map.fromList [(at 0, info)]}
       in bodyA cfg0 book @?= "<h1 id=\"intro\">はじめに</h1>\n",
    testCase "the first h1 is the title of the page" $
      let info = HeadingInfo 1 Nothing Nothing [txt "はじめに"] "intro" fidA
          book = (bookOf [Block (at 0) Nothing Nothing (Heading 1 (HeadingAttrs Nothing Nothing True False) [txt "はじめに"])]) {bookHeadings = Map.fromList [(at 0, info)]}
          page = fromMaybe "" (lookup "a.xhtml" (sitePages (renderXhtml cfg0 ft book)))
       in fst (T.breakOn "</title>" (T.drop 7 (snd (T.breakOn "<title>" page)))) @?= "はじめに",
    testGroup
      "the separator after a number (golem-html ADR 0002)"
      [ testCase "an ideographic space after the number of a heading in a Japanese book" $
          let info = HeadingInfo 1 (Just [1]) (Just "第一章") [txt "はじめに"] "intro" fidA
              book = (bookOf [Block (at 0) (Just "intro") Nothing (Heading 1 noHeadingAttrs [txt "はじめに"])]) {bookHeadings = Map.fromList [(at 0, info)]}
           in bodyA cfg0 book @?= "<h1 id=\"intro\"><span class=\"number\">第一章</span>\x3000はじめに</h1>\n",
        testCase "a space after the number of a heading in an English book" $
          let info = HeadingInfo 1 (Just [1]) (Just "1") [txt "Introduction"] "intro" fidA
              book = (bookOf [Block (at 0) (Just "intro") Nothing (Heading 1 noHeadingAttrs [txt "Introduction"])]) {bookHeadings = Map.fromList [(at 0, info)]}
           in bodyA cfg0 {hcLanguage = "en"} book @?= "<h1 id=\"intro\"><span class=\"number\">1</span> Introduction</h1>\n",
        testCase "nothing more after a number that ends with a space" $
          let info = HeadingInfo 1 (Just [1]) (Just "Chapter 1: ") [txt "Introduction"] "intro" fidA
              book = (bookOf [Block (at 0) (Just "intro") Nothing (Heading 1 noHeadingAttrs [txt "Introduction"])]) {bookHeadings = Map.fromList [(at 0, info)]}
           in bodyA cfg0 {hcLanguage = "en"} book @?= "<h1 id=\"intro\"><span class=\"number\">Chapter 1: </span>Introduction</h1>\n",
        testCase "an ideographic space after the number of a caption, outside the span" $
          let fig = Figure "images/a.png" Nothing "代替" Nothing Nothing [para 3 [txt "キャプション"]] Nothing False False
              book = (bookOf [Block (at 0) Nothing Nothing (FigureBlock fig)]) {bookFigures = Map.fromList [(at 0, "図1-1")]}
           in bodyA cfg0 book @?= "<figure>\n<img src=\"images/a.png\" alt=\"代替\"/>\n<figcaption><span class=\"number\">図1-1</span>\x3000キャプション</figcaption>\n</figure>\n",
        -- docs/adr/0200
        testCase "a figure without a number: no number span; without a caption either: no figcaption" $ do
          let fig cap = Figure "images/a.png" Nothing "代替" Nothing Nothing cap Nothing False True
          bodyA cfg0 (bookOf [Block (at 0) Nothing Nothing (FigureBlock (fig [para 3 [txt "キャプション"]]))])
            @?= "<figure>\n<img src=\"images/a.png\" alt=\"代替\"/>\n<figcaption>キャプション</figcaption>\n</figure>\n"
          bodyA cfg0 (bookOf [Block (at 0) Nothing Nothing (FigureBlock (fig []))])
            @?= "<figure>\n<img src=\"images/a.png\" alt=\"代替\"/>\n</figure>\n",
        -- docs/adr/0190
        testCase "the width of a figure: width and max-width in a horizontal book, height and max-height in a vertical one, in pt, em and %" $ do
          let imgOf cfg w wr =
                let fig = Figure "images/a.png" Nothing "代替" wr w [] Nothing False False
                 in T.takeWhile (/= '\n') (T.drop 1 (T.dropWhile (/= '\n') (bodyA cfg (bookOf [Block (at 0) Nothing Nothing (FigureBlock fig)]))))
          imgOf cfg0 (Just "10zw") Nothing @?= "<img src=\"images/a.png\" alt=\"代替\" style=\"width: 10em; max-width: 100%\"/>"
          imgOf cfg0 (Just "50%") Nothing @?= "<img src=\"images/a.png\" alt=\"代替\" style=\"width: 50%; max-width: 100%\"/>"
          imgOf cfg0 (Just "12.5%") Nothing @?= "<img src=\"images/a.png\" alt=\"代替\" style=\"width: 12.5%; max-width: 100%\"/>"
          imgOf cfg0 (Just "25.4mm") Nothing @?= "<img src=\"images/a.png\" alt=\"代替\" style=\"width: 72pt; max-width: 100%\"/>"
          imgOf cfg0 (Just "40Q") Nothing @?= "<img src=\"images/a.png\" alt=\"代替\" style=\"width: 28.3465pt; max-width: 100%\"/>"
          imgOf cfg0 (Just "1in") Nothing @?= "<img src=\"images/a.png\" alt=\"代替\" style=\"width: 72pt; max-width: 100%\"/>"
          imgOf cfg0 (Just "10.5pt") Nothing @?= "<img src=\"images/a.png\" alt=\"代替\" style=\"width: 10.5pt; max-width: 100%\"/>"
          imgOf cfg0 {hcVertical = True} (Just "1.5zw") Nothing @?= "<img src=\"images/a.png\" alt=\"代替\" style=\"height: 1.5em; max-height: 100%\"/>"
          imgOf cfg0 {hcVertical = True} (Just "40mm") Nothing @?= "<img src=\"images/a.png\" alt=\"代替\" style=\"height: 113.3858pt; max-height: 100%\"/>"
          -- a wrapped figure is placed as any other, with its width
          imgOf cfg0 (Just "8zw") (Just WrapEnd) @?= "<img src=\"images/a.png\" alt=\"代替\" style=\"width: 8em; max-width: 100%\"/>"
          -- no width, no style
          imgOf cfg0 Nothing Nothing @?= "<img src=\"images/a.png\" alt=\"代替\"/>"
          imgOf cfg0 {hcVertical = True} Nothing Nothing @?= "<img src=\"images/a.png\" alt=\"代替\"/>",
        testCase "the table of contents" $
          let entry = TocEntry 1 (Just "第一章") [txt "はじめに"] "intro" fidA (at 9)
              book = (bookOf [Block (at 0) Nothing Nothing (ChannelOutput (TocOutput 2))]) {bookToc = [entry]}
           in bodyA cfg0 book @?= "<nav epub:type=\"toc\" class=\"toc\">\n<ol>\n<li class=\"toc-1\"><a href=\"#intro\">第一章\x3000はじめに</a></li>\n</ol>\n</nav>\n"
      ],
    testCase "a labelled paragraph has the label as id" $
      bodyA cfg0 (bookOf [Block (at 0) (Just "quote-1") Nothing (Paragraph Nothing [txt "引用"])]) @?= "<p id=\"quote-1\">引用</p>\n",
    testGroup
      "cross references"
      [ testCase "a page reference in the same file links to the anchor with the title of the target" $
          let book = (bookOf [para 0 [Ref (at 1) RefPage "intro", txt "を見よ。"]]) {bookLabels = Map.fromList [("intro", LabelTarget (at 9) Nothing [txt "はじめに"] "intro" fidA)]}
           in bodyA cfg0 book @?= "<p><a href=\"#intro\">はじめに</a>を見よ。</p>\n",
        testCase "a page reference to another file links to its page" $
          let book =
                (bookOf [para 0 [Ref (at 1) RefPage "second"]])
                  { bookDocs = [Document fidA [para 0 [Ref (at 1) RefPage "second"]], Document fidB []],
                    bookLabels = Map.fromList [("second", LabelTarget (mkSpan fidB 0 1) Nothing [txt "次の章"] "second" fidB)]
                  }
           in bodyA cfg0 book @?= "<p><a href=\"b.xhtml#second\">次の章</a></p>\n",
        -- docs/adr/0267
        testCase "I11 a resolved [ref-number] and [ref-title] link to the place of their label" $
          let book =
                (bookOf [para 0 [Resolved (at 1) RefNumber "intro" [txt "1"], txt "と", Resolved (at 2) RefTitle "second" [txt "次の章"]]])
                  { bookDocs = [Document fidA [para 0 [Resolved (at 1) RefNumber "intro" [txt "1"], txt "と", Resolved (at 2) RefTitle "second" [txt "次の章"]]], Document fidB []],
                    bookLabels =
                      Map.fromList
                        [ ("intro", LabelTarget (at 9) Nothing [txt "はじめに"] "intro" fidA),
                          ("second", LabelTarget (mkSpan fidB 0 1) Nothing [txt "次の章"] "second" fidB)
                        ]
                  }
           in bodyA cfg0 book @?= "<p><a href=\"#intro\">1</a>と<a href=\"b.xhtml#second\">次の章</a></p>\n",
        testCase "I11 a resolved reference copied into the table of contents is its text alone" $
          let entry = TocEntry 1 (Just "第一章") [txt "見出し", Resolved (at 3) RefNumber "intro" [txt "2"]] "intro" fidA (at 9)
              book = (bookOf [Block (at 0) Nothing Nothing (ChannelOutput (TocOutput 2))]) {bookToc = [entry], bookLabels = Map.fromList [("intro", LabelTarget (at 9) Nothing [txt "見出し"] "intro" fidA)]}
           in bodyA cfg0 book @?= "<nav epub:type=\"toc\" class=\"toc\">\n<ol>\n<li class=\"toc-1\"><a href=\"#intro\">第一章\x3000見出し2</a></li>\n</ol>\n</nav>\n",
        testCase "I11 a resolved reference inside another is the text of the outer link" $
          let book = (bookOf [para 0 [Resolved (at 1) RefTitle "intro" [txt "題", Resolved (at 2) RefNumber "other" [txt "3"]]]]) {bookLabels = Map.fromList [("intro", LabelTarget (at 9) Nothing [txt "題"] "intro" fidA), ("other", LabelTarget (at 8) Nothing [txt "他"] "other" fidA)]}
           in bodyA cfg0 book @?= "<p><a href=\"#intro\">題3</a></p>\n",
        testCase "I11 a resolved reference whose label the book does not have is its text" $
          bodyA cfg0 (bookOf [para 0 [Resolved (at 1) RefNumber "missing" [txt "1"]]]) @?= "<p>1</p>\n"
      ],
    testCase "an index mark is an empty span with an id from its position" $
      bodyA cfg0 (bookOf [para 0 [txt "組版", IndexMark (at 7) (IndexEntry ["組版"] ["くみはん"] IndexPoint)]]) @?= "<p>組版<span id=\"i-0-7\"></span></p>\n",
    testCase "I7: the index links each location by its order; without headings as before" $
      let book = (bookOf [Block (at 0) Nothing Nothing (ChannelOutput IndexOutput)]) {bookIndexes = [((fidA, at 0), [IndexSection "か" [IndexGroup ["組版", "和文組版"] ["くみはん", "わぶんくみはん"] [AtMark (fidA, at 7), AtMark (fidA, at 20)] []]])]}
       in bodyA cfg0 {hcIndexSectionHeadings = False} book @?= "<section class=\"index\">\n<ul>\n<li>組版 / 和文組版 <a href=\"#i-0-7\">1</a>, <a href=\"#i-0-20\">2</a></li>\n</ul>\n</section>\n",
    testCase "the index: a heading and a list for each section, a range of two links, a reference not linked (docs/adr/0265)" $ do
      let g1 = IndexGroup ["組版"] ["くみはん"] [Between (fidA, at 7) (fidA, at 20), AtMark (fidA, at 30)] [(SeeAuto, ["印刷"])]
          g2 = IndexGroup ["タイプセッティング"] ["たいぷせってぃんぐ"] [] [(SeeAuto, ["組版"])]
          book = (bookOf [Block (at 0) Nothing Nothing (ChannelOutput IndexOutput)]) {bookIndexes = [((fidA, at 0), [IndexSection "か" [g1], IndexSection "た" [g2]])]}
          e1 = "<li>組版 <a href=\"#i-0-7\">1</a>–<a href=\"#i-0-20\">2</a>, <a href=\"#i-0-30\">3</a>（印刷をも見よ）</li>\n"
          e2 = "<li>タイプセッティング（組版を見よ）</li>\n"
      bodyA cfg0 book @?= "<section class=\"index\">\n<p class=\"index-heading\">か</p>\n<ul>\n" <> e1 <> "</ul>\n<p class=\"index-heading\">た</p>\n<ul>\n" <> e2 <> "</ul>\n</section>\n"
      bodyA cfg0 {hcIndexSectionHeadings = False} book @?= "<section class=\"index\">\n<ul>\n" <> e1 <> e2 <> "</ul>\n</section>\n",
    testCase "a citation links to its numbered entry in the bibliography" $
      let book =
            (bookOf [para 0 [txt "文献", Cite (at 1) [citeItem "knuth1981"]], Block (at 5) Nothing Nothing (ChannelOutput BibliographyOutput)])
              { bookBibliographies = [(Just (fidA, at 5), [("knuth1981", 1)])],
                bookCiteMarks = Map.fromList [((fidA, at 1), (Just (fidA, at 5), 1))]
              }
          cfg = cfg0 {hcBibliography = Map.fromList [("knuth1981", [EntryText "Knuth, Breaking Paragraphs into Lines."])]}
       in bodyA cfg book
            @?= "<p>文献<span class=\"cite\">[<a href=\"#cite-knuth1981\">1</a>]</span></p>\n<ol class=\"bibliography\">\n<li id=\"cite-knuth1981\">Knuth, Breaking Paragraphs into Lines.</li>\n</ol>\n",
    multipleBibliographyTests,
    citeLinkTests,
    channelTests,
    -- docs/adr ADR 0182
    testCase "a link is an a element with the URL as written, & as &amp;" $
      bodyA cfg0 (bookOf [para 0 [Link (at 1) "https://example.com/?a=1&b=組" [txt "例"], Link (at 2) "https://example.com/" [CharStyle (at 2) "url" [txt "https://example.com/"]]]])
        @?= "<p><a href=\"https://example.com/?a=1&amp;b=組\">例</a><a href=\"https://example.com/\"><span class=\"cs-url\">https://example.com/</span></a></p>\n",
    testCase "a heading with a link: the link stays in the heading, and the copy in a table of contents has its text alone" $
      let h = Block (at 0) (Just "intro") Nothing (Heading 1 noHeadingAttrs [txt "見出し", Link (at 1) "https://example.com/" [txt "例"]])
          site = renderXhtml cfg0 ft (assembled [[h, Block (at 5) Nothing Nothing (ChannelOutput (TocOutput 2))]])
          page = maybe "" bodyOf (lookup "a.xhtml" (sitePages site))
       in (T.count "<a href=\"https://example.com/\">" page, T.isInfixOf "<a href=\"https://example.com/\">例</a></h1>" page) @?= (1, True),
    -- golem-doc ADR 0005
    testCase "a URL of http or https in the bibliography is a link of class cs-url; another is a span" $
      let book =
            (bookOf [para 0 [Cite (at 1) [citeItem "a"], Cite (at 2) [citeItem "b"]], Block (at 5) Nothing Nothing (ChannelOutput BibliographyOutput)])
              { bookBibliographies = [(Just (fidA, at 5), [("a", 1), ("b", 2)])],
                bookCiteMarks = Map.fromList [((fidA, at 1), (Just (fidA, at 5), 1)), ((fidA, at 2), (Just (fidA, at 5), 2))]
              }
          cfg = cfg0 {hcBibliography = Map.fromList [("a", [EntryText "A. ", EntryUrl "HTTPS://example.com/?a=1&b=2"]), ("b", [EntryText "B. ", EntryUrl "javascript:alert(1)"])]}
       in bodyA cfg book
            @?= "<p><span class=\"cite\">[<a href=\"#cite-a\">1</a>]</span><span class=\"cite\">[<a href=\"#cite-b\">2</a>]</span></p>\n<ol class=\"bibliography\">\n<li id=\"cite-a\">A. <a class=\"cs-url\" href=\"HTTPS://example.com/?a=1&amp;b=2\">HTTPS://example.com/?a=1&amp;b=2</a></li>\n<li id=\"cite-b\">B. <span class=\"cs-url\">javascript:alert(1)</span></li>\n</ol>\n",
    testCase "a figure uses its web image and copies it as an asset" $
      let fig = Figure "images/a.pdf" (Just "images/a.png") "代替" Nothing Nothing [para 3 [txt "キャプション"]] Nothing False False
          site = renderXhtml cfg0 ft (bookOf [Block (at 0) Nothing Nothing (FigureBlock fig)])
       in (maybe "" bodyOf (lookup "a.xhtml" (sitePages site)), siteAssets site)
            @?= ("<figure>\n<img src=\"images/a.png\" alt=\"代替\"/>\n<figcaption>キャプション</figcaption>\n</figure>\n", [("images/a.png", "images/a.png")]),
    testCase "a line break is br" $
      bodyA cfg0 (bookOf [para 0 [txt "一行目", LineBreak (at 1), txt "二行目"]]) @?= "<p>一行目<br/>二行目</p>\n",
    testCase "a proof comment is written only in the dev profile" $
      ( bodyA cfg0 {hcDev = True} (bookOf [para 0 [ProofComment (at 1) "要確認"]]),
        bodyA cfg0 (bookOf [para 0 [ProofComment (at 1) "要確認"]])
      )
        @?= ("<p><span class=\"proof\">要確認</span></p>\n", "<p></p>\n"),
    testCase "one page per source file, named .xhtml" $
      map fst (sitePages (renderXhtml cfg0 ft (bookOf []) {bookDocs = [Document fidA [], Document fidB []]})) @?= ["a.xhtml", "b.xhtml"],
    -- a round trip: an escape that drops or rewrites characters fails too (docs/adr/0066)
    testProperty "escapeXml leaves no markup characters, and unescaping gives the text back" $ property $ do
      t <- forAll (Gen.text (Range.linear 0 20) (Gen.element ("a<>&\"'漢" :: String)))
      let e = escapeXml t
      unescapeXml e === t
      T.filter (`elem` ("<>\"" :: String)) e === ""
      -- every & starts one of the four references
      filter (\rest -> not (any (`T.isPrefixOf` rest) xmlReferences)) (drop 1 (T.splitOn "&" e)) === []
  ]

-- | The references escapeXml writes, without their &.
xmlReferences :: [Text]
xmlReferences = ["amp;", "lt;", "gt;", "quot;"]

-- | The inverse of escapeXml, written from the four references it writes.
unescapeXml :: Text -> Text
unescapeXml t = case T.uncons t of
  Nothing -> ""
  Just ('&', rest)
    | Just r <- T.stripPrefix "amp;" rest -> "&" <> unescapeXml r
    | Just r <- T.stripPrefix "lt;" rest -> "<" <> unescapeXml r
    | Just r <- T.stripPrefix "gt;" rest -> ">" <> unescapeXml r
    | Just r <- T.stripPrefix "quot;" rest -> "\"" <> unescapeXml r
  Just (c, rest) -> T.cons c (unescapeXml rest)

-- | Tables, lists, definition lists, the depth of the contents and code lines.
blockTests :: [TestTree]
blockTests =
  [ testCase "a table: th in the head, td in the body, the class of each column's alignment" $
      bodyA cfg0 (bookOf [Block (at 0) Nothing Nothing (TableBlock (plainTable [AlignRight, AlignCenter, AlignLeft, AlignDefault] [[txt "a"], [txt "b"], [txt "c"], [txt "d"]] [[[txt "1"], [txt "2"], [txt "3"], [txt "4"]]]))])
        @?= T.concat
          [ "<table>\n<thead>\n",
            "<tr><th class=\"align-right\">a</th><th class=\"align-center\">b</th><th class=\"align-left\">c</th><th>d</th></tr>\n",
            "</thead>\n<tbody>\n",
            "<tr><td class=\"align-right\">1</td><td class=\"align-center\">2</td><td class=\"align-left\">3</td><td>4</td></tr>\n",
            "</tbody>\n</table>\n"
          ],
    testCase "the cells after the last alignment are not dropped" $
      bodyA cfg0 (bookOf [Block (at 0) (Just "t") Nothing (TableBlock (plainTable [AlignLeft] [[txt "a"], [txt "b"]] [[[txt "1"], [txt "2"]], [[txt "3"], [txt "4"]]]))])
        @?= "<table id=\"t\">\n<thead>\n<tr><th class=\"align-left\">a</th><th>b</th></tr>\n</thead>\n<tbody>\n<tr><td class=\"align-left\">1</td><td>2</td></tr>\n<tr><td class=\"align-left\">3</td><td>4</td></tr>\n</tbody>\n</table>\n",
    testCase "I4: a table without a caption, widths or style is written as before docs/adr/0262" $
      bodyA cfg0 (bookOf [Block (at 0) Nothing Nothing (TableBlock (plainTable [AlignDefault] [[txt "a"]] [[[txt "1"]]]))])
        @?= "<table>\n<thead>\n<tr><th>a</th></tr>\n</thead>\n<tbody>\n<tr><td>1</td></tr>\n</tbody>\n</table>\n",
    testCase "a table with a caption: the caption first, the table number in its span and the separator (docs/adr/0262)" $ do
      let t = (plainTable [AlignDefault] [[txt "a"]] [[[txt "1"]]]) {tableCaption = Just [txt "題目"]}
          book = (bookOf [Block (at 0) Nothing Nothing (TableBlock t)]) {bookTables = Map.fromList [(at 0, "表1-1")]}
      bodyA cfg0 book @?= "<table>\n<caption><span class=\"number\">表1-1</span>\x3000題目</caption>\n<thead>\n<tr><th>a</th></tr>\n</thead>\n<tbody>\n<tr><td>1</td></tr>\n</tbody>\n</table>\n"
      -- the caption is the first child below too; style.css puts it at the bottom
      bodyA cfg0 {hcTableCaptionBelow = True} book @?= bodyA cfg0 book
      -- without a number, the caption alone
      bodyA cfg0 (bookOf [Block (at 0) Nothing Nothing (TableBlock t {tableNoNumber = True})]) @?= "<table>\n<caption>題目</caption>\n<thead>\n<tr><th>a</th></tr>\n</thead>\n<tbody>\n<tr><td>1</td></tr>\n</tbody>\n</table>\n",
    testCase "caption-position below writes caption-side: bottom in style.css, above writes nothing (docs/adr/0262)" $ do
      cssLines "table > caption" cfg0 {hcTableCaptionBelow = True} @?= ["table > caption { caption-side: bottom; }"]
      cssLines "table > caption" cfg0 @?= [],
    testCase "a table with widths has a colgroup: zw in em, a length in pt, % as %, auto without a width (docs/adr/0262)" $ do
      let t = (plainTable [AlignDefault, AlignDefault, AlignDefault, AlignDefault] [[txt "a"], [txt "b"], [txt "c"], [txt "d"]] []) {tableWidths = [ColumnZw 8, columnAbsolute 655360, ColumnPercent 25, ColumnAuto]}
      bodyA cfg0 (bookOf [Block (at 0) Nothing Nothing (TableBlock t)])
        @?= "<table>\n<colgroup><col style=\"width: 8em\"/><col style=\"width: 10pt\"/><col style=\"width: 25%\"/><col/></colgroup>\n<thead>\n<tr><th>a</th><th>b</th><th>c</th><th>d</th></tr>\n</thead>\n<tbody>\n</tbody>\n</table>\n",
    testCase "a table of a paragraph style has its ps- class; style.css writes the font and size of table and of it (docs/adr/0262)" $ do
      let t = (plainTable [AlignDefault] [[txt "a"]] []) {tableStyle = Just "small"}
      take 1 (T.lines (bodyA cfg0 (bookOf [Block (at 0) Nothing Nothing (TableBlock t)]))) @?= ["<table class=\"ps-small\">"]
      let cfg = cfg0 {hcTableFaces = Map.fromList [("table", Face Nothing (Just "0.8em")), ("small", Face Nothing (Just "0.7em"))]}
      cssLines "table" cfg @?= ["table.ps-small th, table.ps-small td { font-size: 0.7em; }", "table:not([class]) th, table:not([class]) td { font-size: 0.8em; }"]
      cssLines "table" cfg0 {hcTableFaces = Map.fromList [("table", noFace)]} @?= [],
    testCase "a numbered list starts at the number of its first item; a later number is the value of its item" $
      bodyA cfg0 (bookOf [Block (at 0) Nothing Nothing (OrderedList [ListItem (Just 3) [para 1 [txt "三"]], ListItem Nothing [para 2 [txt "四"]], ListItem (Just 7) [para 3 [txt "七"]]])])
        @?= "<ol start=\"3\">\n<li>三</li>\n<li>四</li>\n<li value=\"7\">七</li>\n</ol>\n",
    testCase "a numbered list without numbers has neither start nor value" $
      bodyA cfg0 (bookOf [Block (at 0) Nothing Nothing (OrderedList [ListItem Nothing [para 1 [txt "一"]], ListItem Nothing [para 2 [txt "二"]]])])
        @?= "<ol>\n<li>一</li>\n<li>二</li>\n</ol>\n",
    testCase "an item of more than one block has its blocks inside; lists inside take the class of their depth, up to the last marker" $
      let lists = Just (HtmlLists ("・" :| ["◦"]) (defaultNumberFormat False :| []) Nothing)
          ul n bs = Block (at n) Nothing Nothing (BulletList [ListItem Nothing bs])
          book = bookOf [ul 0 [para 1 [txt "a"], ul 2 [para 3 [txt "b"], ul 4 [para 5 [txt "c"]]]]]
       in bodyA cfg0 {hcLists = lists} book
            @?= T.concat
              [ "<ul class=\"list-1\">\n<li>\n<p>a</p>\n",
                "<ul class=\"list-2\">\n<li>\n<p>b</p>\n",
                "<ul class=\"list-2\">\n<li>c</li>\n</ul>\n",
                "</li>\n</ul>\n",
                "</li>\n</ul>\n"
              ],
    testCase "a definition list: every term, then every definition, of each group" $
      bodyA cfg0 (bookOf [Block (at 0) Nothing Nothing (DefList [DefGroup [[txt "HTTP"], [txt "HyperText"]] [[para 1 [txt "共有"]], [para 2 [txt "転送"]]], DefGroup [[txt "決定性"]] [[para 3 [txt "同じ出力"]]]])])
        @?= "<dl>\n<dt>HTTP</dt>\n<dt>HyperText</dt>\n<dd>\n<p>共有</p>\n</dd>\n<dd>\n<p>転送</p>\n</dd>\n<dt>決定性</dt>\n<dd>\n<p>同じ出力</p>\n</dd>\n</dl>\n",
    testCase "the table of contents takes the headings up to its depth, the depth itself included" $
      let entry l a = TocEntry l Nothing [txt a] a fidA (at 9)
          book = (bookOf [Block (at 0) Nothing Nothing (ChannelOutput (TocOutput 2))]) {bookToc = [entry 1 "h1", entry 2 "h2", entry 3 "h3", entry 2 "h2b"]}
       in bodyA cfg0 book
            @?= "<nav epub:type=\"toc\" class=\"toc\">\n<ol>\n<li class=\"toc-1\"><a href=\"#h1\">h1</a></li>\n<li class=\"toc-2\"><a href=\"#h2\">h2</a></li>\n<li class=\"toc-2\"><a href=\"#h2b\">h2b</a></li>\n</ol>\n</nav>\n",
    testCase "code lines: the number, the diff mark, the classes of a highlight and of the diff, and the callouts" $
      let code =
            Code
              { codeLang = Nothing,
                codeNumbers = Just True,
                codeFile = Nothing,
                codeCaption = Nothing,
                codeDiff = True,
                codeLines =
                  [ CodeLine "a" (Just 1) (Just DiffContext) False [] Nothing,
                    CodeLine "b" Nothing (Just DiffRemoved) False [] Nothing,
                    CodeLine "c<" (Just 2) (Just DiffAdded) True [1, 2] Nothing
                  ],
                codeNoNumber = False
              }
       in bodyA cfg0 (bookOf [Block (at 0) Nothing Nothing (CodeBlock code)])
            @?= T.concat
              [ "<pre><code>",
                "<span class=\"line\"><span class=\"ln\" aria-hidden=\"true\">1</span><span class=\"dm\" aria-hidden=\"true\"> </span>a</span>\n",
                "<span class=\"line del\"><span class=\"ln\" aria-hidden=\"true\"></span><span class=\"dm\" aria-hidden=\"true\">-</span>b</span>\n",
                "<span class=\"line hl add\"><span class=\"ln\" aria-hidden=\"true\">2</span><span class=\"dm\" aria-hidden=\"true\">+</span>c&lt; <span class=\"callout\">①</span> <span class=\"callout\">②</span></span>",
                "</code></pre>\n"
              ],
    testCase "code without numbers, a diff or marks is its escaped text" $
      bodyA cfg0 (bookOf [Block (at 0) (Just "c") Nothing (CodeBlock (Code Nothing Nothing Nothing Nothing False [CodeLine "a & b" (Just 1) Nothing False [] Nothing, CodeLine "c" (Just 2) Nothing False [] Nothing] False))])
        @?= "<pre id=\"c\"><code>a &amp; b\nc</code></pre>\n"
  ]

-- | The table of contents page of the HTML target, moved from golem-driver (docs/adr ADR 0090).
indexPageTests :: TestTree
indexPageTests =
  testGroup
    "indexPage (docs/adr ADR 0090)"
    [ testCase "a book of two files with a numbered heading of level 1 and a heading of level 2" $
        indexPage cfg0 ft twoHeadings
          @?= T.concat
            [ "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE html>\n<html xmlns=\"http://www.w3.org/1999/xhtml\" lang=\"ja\" xml:lang=\"ja\">\n",
              "<head>\n<meta charset=\"UTF-8\"/>\n<title>本</title>\n<link rel=\"stylesheet\" type=\"text/css\" href=\"style.css\"/>\n</head>\n",
              "<body>\n<h1>本</h1>\n<nav class=\"toc\">\n<ol>\n",
              "<li class=\"toc-1\"><a href=\"a.xhtml#intro\">第一章\x3000はじめに</a></li>\n",
              "<li class=\"toc-2\"><a href=\"b.xhtml#detail\">細部</a></li>\n",
              "</ol>\n</nav>\n</body>\n</html>\n"
            ],
      testCase "the title and the language are escaped in title, h1, lang and xml:lang" $ do
        let page = indexPage cfg0 {hcTitle = "<A & B>", hcLanguage = "ja&<"} ft twoHeadings
        assertBool (T.unpack page) ("<title>&lt;A &amp; B&gt;</title>" `T.isInfixOf` page)
        assertBool (T.unpack page) ("<h1>&lt;A &amp; B&gt;</h1>" `T.isInfixOf` page)
        assertBool (T.unpack page) ("lang=\"ja&amp;&lt;\" xml:lang=\"ja&amp;&lt;\"" `T.isInfixOf` page),
      testCase "with @toc of depth 1, the heading of level 2 is not listed (golem-epub ADR 0002)" $ do
        let page = indexPage cfg0 ft twoHeadings {bookTocDepth = Just 1}
        assertBool (T.unpack page) ("a.xhtml#intro" `T.isInfixOf` page)
        assertBool (T.unpack page) (not ("b.xhtml#detail" `T.isInfixOf` page))
    ]
  where
    twoHeadings =
      (bookOf [])
        { bookToc =
            [ TocEntry 1 (Just "第一章") [txt "はじめに"] "intro" fidA (at 0),
              TocEntry 2 Nothing [txt "細部"] "detail" fidB (mkSpan fidB 0 1)
            ]
        }

-- | Language spans and the language of blocks (docs/adr ADR 0187).
langTests :: TestTree
langTests =
  testGroup
    "the language of spans and blocks (docs/adr ADR 0187)"
    [ testCase "a language span is a span with lang and xml:lang, even in the language of the book" $
        bodyA cfg0 (bookOf [para 0 [Lang (at 1) "fr" [txt "x"], Lang (at 2) "ja" [txt "和"]]])
          @?= "<p><span lang=\"fr\" xml:lang=\"fr\">x</span><span lang=\"ja\" xml:lang=\"ja\">和</span></p>\n",
      testCase "the tag is escaped" $
        bodyA cfg0 (bookOf [para 0 [Lang (at 1) "x-a&b" [txt "x"]]]) @?= "<p><span lang=\"x-a&amp;b\" xml:lang=\"x-a&amp;b\">x</span></p>\n",
      testCase "the outermost element of a block with a language has lang and xml:lang" $ do
        let withLang l b = b {blockLang = Just l}
        bodyA cfg0 (bookOf [withLang "en" (para 0 [txt "a"])]) @?= "<p lang=\"en\" xml:lang=\"en\">a</p>\n"
        bodyA cfg0 (bookOf [withLang "en" (Block (at 0) (Just "h") Nothing (Heading 1 noHeadingAttrs [txt "a"]))]) @?= "<h1 id=\"h\" lang=\"en\" xml:lang=\"en\">a</h1>\n"
        bodyA cfg0 (bookOf [withLang "en" (Block (at 0) Nothing Nothing (BulletList [ListItem Nothing [para 1 [txt "a"]]]))]) @?= "<ul lang=\"en\" xml:lang=\"en\">\n<li>a</li>\n</ul>\n"
        bodyA cfg0 (bookOf [withLang "en" (Block (at 0) Nothing Nothing (OrderedList [ListItem Nothing [para 1 [txt "a"]]]))]) @?= "<ol lang=\"en\" xml:lang=\"en\">\n<li>a</li>\n</ol>\n"
        bodyA cfg0 (bookOf [withLang "en" (Block (at 0) Nothing Nothing (DefList [DefGroup [[txt "t"]] [[para 1 [txt "d"]]]]))]) @?= "<dl lang=\"en\" xml:lang=\"en\">\n<dt>t</dt>\n<dd>\n<p>d</p>\n</dd>\n</dl>\n"
        assertBool "table" ("<table lang=\"en\" xml:lang=\"en\">" `T.isPrefixOf` bodyA cfg0 (bookOf [withLang "en" (Block (at 0) Nothing Nothing (TableBlock (plainTable [AlignDefault] [[txt "a"]] [[[txt "b"]]])))]))
        bodyA cfg0 (bookOf [withLang "en" (Block (at 0) Nothing Nothing (CodeBlock (Code Nothing Nothing Nothing Nothing False [CodeLine "a" (Just 1) Nothing False [] Nothing] False)))]) @?= "<pre lang=\"en\" xml:lang=\"en\"><code>a</code></pre>\n",
      testCase "the blocks of the body of @lang: each with its own attributes, nothing around them" $
        bodyA cfg0 (bookOf [(para 0 [txt "a"]) {blockLang = Just "en"}, (para 1 [txt "b"]) {blockLang = Just "en"}])
          @?= "<p lang=\"en\" xml:lang=\"en\">a</p>\n<p lang=\"en\" xml:lang=\"en\">b</p>\n",
      testCase "a paragraph of its own language in an item keeps its element" $
        bodyA cfg0 (bookOf [Block (at 0) Nothing Nothing (BulletList [ListItem Nothing [(para 1 [txt "a"]) {blockLang = Just "de"}]])])
          @?= "<ul>\n<li>\n<p lang=\"de\" xml:lang=\"de\">a</p>\n</li>\n</ul>\n",
      testCase "the sidenotes of a paragraph with a language have it too" $
        bodyA cfg0 (bookOf [(para 0 [txt "a", Sidenote (at 1) 1 (noteBody (at 1) [txt "s"])]) {blockLang = Just "en"}])
          @?= "<p lang=\"en\" xml:lang=\"en\">a<sup class=\"sidenote-ref\">1</sup></p>\n<aside class=\"sidenote\" lang=\"en\" xml:lang=\"en\"><span class=\"number\">1</span>s</aside>\n",
      testCase "the spans stay in the items of @toc, the toc page and the copies; character styles drop out of the toc page" $ do
        let title = [txt "見出し", Lang (at 1) "en" [CharStyle (at 1) "strong" [txt "Tokyo"]]]
            h = Block (at 0) (Just "intro") Nothing (Heading 1 noHeadingAttrs title)
            book = assembled [[h, Block (at 5) Nothing Nothing (ChannelOutput (TocOutput 2))]]
            body = bodyA cfg0 book
        assertBool (T.unpack body) ("<span lang=\"en\" xml:lang=\"en\"><strong>Tokyo</strong></span></a>" `T.isInfixOf` body)
        let page = indexPage cfg0 ft book
        assertBool (T.unpack page) ("見出し<span lang=\"en\" xml:lang=\"en\">Tokyo</span></a></li>" `T.isInfixOf` page),
      testCase "the toc page writes the language of a heading around its title" $ do
        let h = Block (at 0) (Just "intro") (Just "en") (Heading 1 noHeadingAttrs [txt "Tokyo"])
            page = indexPage cfg0 ft (assembled [[h]])
        assertBool (T.unpack page) ("<a href=\"a.xhtml#intro\">1\x3000<span lang=\"en\" xml:lang=\"en\">Tokyo</span></a>" `T.isInfixOf` page),
      testCase "the body of a note is in the language of its mark" $ do
        let book = assembled [[para 0 [txt "本文", Lang (at 1) "en" [txt "text", Note (at 2) 1 (noteBody (at 2) [txt "a note"])]]]]
            body = bodyA cfg0 book
        assertBool (T.unpack body) ("</a> <span lang=\"en\" xml:lang=\"en\">a note</span></p></aside>" `T.isInfixOf` body)
    ]

xhtmlTests :: TestTree
xhtmlTests = testGroup "XHTML and CSS (golem-html ADR 0001)" (tests <> [indexPageTests, langTests])
