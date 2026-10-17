{- | Small tests of the XHTML and CSS output over hand-built books
(golem-html ADR 0001): colours, notes, ruby, headings, cross references,
the index and citations.
-}
module XhtmlSpec (xhtmlTests) where

import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.Assemble (Book (..), HeadingInfo (..), IndexGroup (..), LabelTarget (..), TocEntry (..))
import Golem.Doc.IR
import Golem.Html
import Golem.Syntax.Span
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
      hcBibliography = Map.empty,
      hcDev = False,
      hcRubyMonoAlign = "center",
      hcRubyGroupAlign = "space-between",
      hcRubyBaseSpacing = "center",
      hcBreakKinds = Set.empty,
      hcLists = Nothing,
      hcCode = HtmlCode Nothing Nothing Nothing "0.5em" Nothing "0.25pt" False Nothing Nothing Nothing Nothing Map.empty
    }

-- | A book of one document, a.gm, with nothing assembled.
bookOf :: [Block] -> Book
bookOf bs =
  Book
    { bookDocs = [Document fidA bs],
      bookHeadings = Map.empty,
      bookFigures = Map.empty,
      bookListings = Map.empty,
      bookToc = [],
      bookTocDepth = Nothing,
      bookIndex = [],
      bookCitations = [],
      bookLabels = Map.empty,
      bookReferenced = Set.empty
    }

para :: Int -> [Inline] -> Block
para n = Block (at n) Nothing . Paragraph Nothing

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

tests :: [TestTree]
tests =
  [ testGroup
      "colours: R = 255 × (1 − C) × (1 − K), rounded"
      [ testCase "white for no ink" $ cmykToRgb (0, 0, 0, 0) @?= (255, 255, 255),
        testCase "black for full K" $ cmykToRgb (0, 0, 0, 100) @?= (0, 0, 0),
        -- 255 × 0.8 × 0.9 = 183.6, 255 × 0.6 × 0.9 = 137.7, 255 × 0.4 × 0.9 = 91.8
        testCase "K scales every channel" $ cmykToRgb (20, 40, 60, 10) @?= (184, 138, 92),
        testCase "a swatch is a CSS rule with rgb()" $
          -- 255 × 0.2 = 51
          cssLines ".swatch-" cfg0 {hcSwatches = Map.fromList [("accent", (0, 80, 100, 0))]} @?= [".swatch-accent { color: rgb(255, 51, 0); }"],
        testCase "a character style with a swatch has its rgb() colour" $
          let term = HtmlCharStyle Nothing False False (Just "accent") noFeatures False
              cfg = cfg0 {hcSwatches = Map.fromList [("accent", (0, 80, 100, 0))], hcCharStyles = Map.fromList [("term", term)]}
           in cssLines ".cs-term" cfg @?= [".cs-term { color: rgb(255, 51, 0); }"],
        testCase "coloured text is a span with the class of its swatch" $
          bodyA cfg0 (bookOf [para 0 [Color (at 1) "accent" [txt "赤"]]]) @?= "<p><span class=\"swatch-accent\">赤</span></p>\n"
      ],
    testCase "the page is polyglot XHTML in the language of the book" $
      let page = fromMaybe "" (lookup "a.xhtml" (sitePages (renderXhtml cfg0 ft (bookOf [para 0 [txt "本文"]]))))
       in T.takeWhile (/= '>') (snd (T.breakOn "<html" page)) @?= "<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"http://www.idpf.org/2007/ops\" lang=\"ja\" xml:lang=\"ja\"",
    testCase "text is escaped for XML" $
      bodyA cfg0 (bookOf [para 0 [txt "a < b & \"c\" > d"]]) @?= "<p>a &lt; b &amp; &quot;c&quot; &gt; d</p>\n",
    testCase "a sidenote is a numbered mark and an aside after the paragraph" $
      bodyA cfg0 (bookOf [para 0 [txt "本文", Sidenote (at 1) 1 [txt "補足。"], txt "。"]])
        @?= "<p>本文<sup class=\"sidenote-ref\">1</sup>。</p>\n<aside class=\"sidenote\"><span class=\"number\">1</span>補足。</aside>\n",
    testCase "sidenotes are smaller than the text when no size is given (golem-driver ADR 0011)" $
      cssLines ".sidenote" cfg0 @?= [".sidenote { font-size: 0.85em; }"],
    testCase "a footnote links to its note at the end of the file, which links back" $
      bodyA cfg0 (bookOf [para 0 [txt "本文", Note (at 1) 1 [txt "注の本文。"]], para 5 [txt "次。"]])
        @?= T.concat
          [ "<p>本文<a epub:type=\"noteref\" class=\"noteref\" href=\"#note-1\" id=\"noteref-1\">1</a></p>\n",
            "<p>次。</p>\n",
            "<section class=\"notes\">\n",
            "<aside epub:type=\"footnote\" id=\"note-1\"><a href=\"#noteref-1\">1</a> 注の本文。</aside>\n",
            "</section>\n"
          ],
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
    testCase "a heading is h1 with the anchor of the heading as id" $
      let info = HeadingInfo 1 Nothing Nothing [txt "はじめに"] "intro" fidA
          book = (bookOf [Block (at 0) (Just "intro") (Heading 1 (HeadingAttrs Nothing Nothing True False) [txt "はじめに"])]) {bookHeadings = Map.fromList [(at 0, info)]}
       in bodyA cfg0 book @?= "<h1 id=\"intro\">はじめに</h1>\n",
    testCase "the first h1 is the title of the page" $
      let info = HeadingInfo 1 Nothing Nothing [txt "はじめに"] "intro" fidA
          book = (bookOf [Block (at 0) Nothing (Heading 1 (HeadingAttrs Nothing Nothing True False) [txt "はじめに"])]) {bookHeadings = Map.fromList [(at 0, info)]}
          page = fromMaybe "" (lookup "a.xhtml" (sitePages (renderXhtml cfg0 ft book)))
       in fst (T.breakOn "</title>" (T.drop 7 (snd (T.breakOn "<title>" page)))) @?= "はじめに",
    testGroup
      "the separator after a number (golem-html ADR 0002)"
      [ testCase "an ideographic space after the number of a heading in a Japanese book" $
          let info = HeadingInfo 1 (Just [1]) (Just "第一章") [txt "はじめに"] "intro" fidA
              book = (bookOf [Block (at 0) (Just "intro") (Heading 1 noHeadingAttrs [txt "はじめに"])]) {bookHeadings = Map.fromList [(at 0, info)]}
           in bodyA cfg0 book @?= "<h1 id=\"intro\"><span class=\"number\">第一章</span>\x3000はじめに</h1>\n",
        testCase "a space after the number of a heading in an English book" $
          let info = HeadingInfo 1 (Just [1]) (Just "1") [txt "Introduction"] "intro" fidA
              book = (bookOf [Block (at 0) (Just "intro") (Heading 1 noHeadingAttrs [txt "Introduction"])]) {bookHeadings = Map.fromList [(at 0, info)]}
           in bodyA cfg0 {hcLanguage = "en"} book @?= "<h1 id=\"intro\"><span class=\"number\">1</span> Introduction</h1>\n",
        testCase "nothing more after a number that ends with a space" $
          let info = HeadingInfo 1 (Just [1]) (Just "Chapter 1: ") [txt "Introduction"] "intro" fidA
              book = (bookOf [Block (at 0) (Just "intro") (Heading 1 noHeadingAttrs [txt "Introduction"])]) {bookHeadings = Map.fromList [(at 0, info)]}
           in bodyA cfg0 {hcLanguage = "en"} book @?= "<h1 id=\"intro\"><span class=\"number\">Chapter 1: </span>Introduction</h1>\n",
        testCase "an ideographic space after the number of a caption, outside the span" $
          let fig = Figure "images/a.png" Nothing "代替" Nothing Nothing [para 3 [txt "キャプション"]] Nothing
              book = (bookOf [Block (at 0) Nothing (FigureBlock fig)]) {bookFigures = Map.fromList [(at 0, "図1-1")]}
           in bodyA cfg0 book @?= "<figure>\n<img src=\"images/a.png\" alt=\"代替\"/>\n<figcaption><span class=\"number\">図1-1</span>\x3000キャプション</figcaption>\n</figure>\n",
        testCase "the table of contents" $
          let entry = TocEntry 1 (Just "第一章") [txt "はじめに"] "intro" fidA (at 9)
              book = (bookOf [Block (at 0) Nothing (ChannelOutput (TocOutput 2))]) {bookToc = [entry]}
           in bodyA cfg0 book @?= "<nav epub:type=\"toc\" class=\"toc\">\n<ol>\n<li class=\"toc-1\"><a href=\"#intro\">第一章\x3000はじめに</a></li>\n</ol>\n</nav>\n"
      ],
    testCase "a labelled paragraph has the label as id" $
      bodyA cfg0 (bookOf [Block (at 0) (Just "quote-1") (Paragraph Nothing [txt "引用"])]) @?= "<p id=\"quote-1\">引用</p>\n",
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
           in bodyA cfg0 book @?= "<p><a href=\"b.xhtml#second\">次の章</a></p>\n"
      ],
    testCase "an index mark is an empty span with an id from its position" $
      bodyA cfg0 (bookOf [para 0 [txt "組版", IndexMark (at 7) (IndexEntry ["組版"] ["くみはん"])]]) @?= "<p>組版<span id=\"i-0-7\"></span></p>\n",
    testCase "the index links each location by its order" $
      let book = (bookOf [Block (at 0) Nothing (ChannelOutput IndexOutput)]) {bookIndex = [IndexGroup ["組版", "和文組版"] ["くみはん", "わぶんくみはん"] [(fidA, at 7), (fidA, at 20)]]}
       in bodyA cfg0 book @?= "<section class=\"index\">\n<ul>\n<li>組版 / 和文組版 <a href=\"#i-0-7\">1</a>, <a href=\"#i-0-20\">2</a></li>\n</ul>\n</section>\n",
    testCase "a citation links to its numbered entry in the bibliography" $
      let book =
            (bookOf [para 0 [txt "文献", Cite (at 1) "knuth1981"], Block (at 5) Nothing (ChannelOutput BibliographyOutput)])
              { bookCitations = [("knuth1981", 1)]
              }
          cfg = cfg0 {hcBibliography = Map.fromList [("knuth1981", "Knuth, Breaking Paragraphs into Lines.")]}
       in bodyA cfg book
            @?= "<p>文献<a class=\"cite\" href=\"#cite-knuth1981\">[1]</a></p>\n<ol class=\"bibliography\">\n<li id=\"cite-knuth1981\">Knuth, Breaking Paragraphs into Lines.</li>\n</ol>\n",
    testCase "a figure uses its web image and copies it as an asset" $
      let fig = Figure "images/a.pdf" (Just "images/a.png") "代替" Nothing Nothing [para 3 [txt "キャプション"]] Nothing
          site = renderXhtml cfg0 ft (bookOf [Block (at 0) Nothing (FigureBlock fig)])
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
    testProperty "escapeXml leaves no markup characters" $ property $ do
      t <- forAll (Gen.text (Range.linear 0 20) (Gen.element ("a<>&\"漢" :: String)))
      T.filter (`elem` ("<>\"" :: String)) (escapeXml t) === ""
  ]

xhtmlTests :: TestTree
xhtmlTests = testGroup "XHTML and CSS (golem-html ADR 0001)" tests
