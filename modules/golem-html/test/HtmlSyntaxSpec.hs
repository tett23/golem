{- | The HTML target in the HTML syntax and EPUB in the XHTML syntax, from
one tree of the pages (root ADR 0432), over hand-built books.
-}
module HtmlSyntaxSpec (htmlSyntaxTests) where

import Control.Monad (forM_, when)
import Data.Char (isAlphaNum)
import Data.List (isPrefixOf)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (isNothing)
import Data.Ratio ((%))
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Golem.Assemble (Book (..), LabelTarget (..), SeparatorAppearance (..), SeparatorStroke (..), TocEntry (..))
import Golem.Assemble.Formats (arabic)
import Golem.Doc.IR
import Golem.Html
import Golem.Html.Markup (AttrValue (..), Node (..), writeDocument)
import Golem.Syntax.Span
import Hedgehog (Gen, forAll, property, (===))
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import System.Environment (lookupEnv)
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testProperty)

fidA, fidB :: FileId
ft :: FileTable
(fidA, fidB, ft) =
  let (a, t1) = registerFile "a.gm" emptyFileTable
      (b, t2) = registerFile "chapters/b.gm" t1
   in (a, b, t2)

at :: Int -> SrcSpan
at n = mkSpan fidA n (n + 1)

atB :: Int -> SrcSpan
atB n = mkSpan fidB n (n + 1)

cfg0 :: HtmlConfig
cfg0 =
  HtmlConfig
    { hcTitle = "本",
      hcLanguage = "ja",
      hcVertical = False,
      hcSeparatorPitch = Nothing,
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
      hcRubyReadingStyle = Nothing,
      hcBreakKinds = Set.empty,
      hcNoBreak = False,
      hcLists = Nothing,
      hcCode = HtmlCode Nothing Nothing Nothing "0.5em" Nothing "0.25pt" False Nothing Nothing Nothing Nothing Map.empty,
      hcHeadingRules = Map.empty,
      hcHeadingStyles = Map.empty,
      hcLocalHeadingStyles = Map.empty,
      hcNoteNotation = arabic,
      hcEndnoteNotation = arabic,
      hcEmbedFonts = True,
      hcFontLicenses = [],
      hcGenericFamilies = Map.empty,
      hcCharacterAdvance = Nothing,
      hcAnonymousStyles = Map.empty,
      hcLocalAnonymousStyles = Map.empty,
      hcAnonymousTableFaces = Map.empty
    }

-- | A book of the documents given, with nothing assembled.
bookOfDocs :: [Document] -> Book
bookOfDocs docs =
  Book
    { bookDocs = docs,
      bookHeadings = Map.empty,
      bookFigures = Map.empty,
      bookListings = Map.empty,
      bookTables = Map.empty,
      bookToc = [],
      bookTocDepth = Nothing,
      bookIndexes = [],
      bookBibliographies = [],
      bookBibliographyEntries = Map.empty,
      bookBibliographyLabels = Map.empty,
      bookBibliographyHangingIndent = Nothing,
      bookCitationPieces = Map.empty,
      bookNoteCitationPieces = Map.empty,
      bookCiteMarks = Map.empty,
      bookLabels = Map.empty,
      bookReferenced = Set.empty,
      bookChapterOf = [],
      bookChannels = [],
      bookChannelDecls = Map.empty,
      bookTitleSeparators = Map.empty,
      bookTitleFormats = Map.empty,
      bookImages = Map.empty,
      bookSeparators = Map.empty
    }

bookOf :: [Block] -> Book
bookOf bs = bookOfDocs [Document fidA bs]

para :: Int -> [Inline] -> Block
para n = Block (at n) Nothing Nothing . Paragraph Nothing

txt :: Text -> Inline
txt = Text (at 0)

-- | A sample of the table of boundaries: its name, its book and the page breaks EPUB gets.
data Sample = Sample
  { sName :: String,
    sBook :: Book,
    sBreaks :: Map SrcSpan [(Int, Text, Text)]
  }

sample :: String -> Book -> Sample
sample n b = Sample n b Map.empty

-- | The inputs of the table of boundaries of root ADR 0432.
samples :: [Sample]
samples =
  [ sample "void-elements" $
      bookOf
        [ para 0 [txt "一行目", LineBreak (at 1), txt "二行目"],
          Block (at 2) Nothing Nothing (TableBlock (Table [AlignLeft, AlignDefault] [ColumnAuto, ColumnZw 3] Nothing False Nothing [[txt "a"], [txt "b"]] [[[txt "1"], [txt "2"]]])),
          Block (at 3) Nothing Nothing (FigureBlock (Figure "images/a.png" Nothing "代替" Nothing Nothing [para 4 [txt "図"]] Nothing False False Nothing))
        ],
    sample "notes" $
      (bookOf [para 0 [txt "本文", Note (at 1) 1 Nothing (noteBody (at 1) [txt "注。"]), Endnote (at 2) 1 Nothing (noteBody (at 2) [txt "後注。"])], Block (at 3) Nothing Nothing (ChannelOutput (TocOutput 2))])
        { bookToc = [TocEntry 1 Nothing [txt "はじめに"] "intro" fidA (at 9)]
        },
    (sample "page-breaks" (bookOf [Block (mkSpan fidA 0 4) Nothing Nothing (Paragraph Nothing [Text (mkSpan fidA 0 4) "日本語句"])]))
      { sBreaks = Map.singleton (mkSpan fidA 0 4) [(2, "GolemFixedPage-1", "1")]
      },
    sample "language" $ bookOf [para 0 [txt "和", Lang (at 1) "fr" [txt "oui"]], (para 2 [txt "en"]) {blockLang = Just "en"}],
    sample "svg" $
      (bookOf [Block (at 1) Nothing Nothing (Separator "scene")])
        { bookSeparators = Map.singleton (at 1, "scene") (SeparatorRuleAppearance 1 1 "center" (Just 655360) 32768 Nothing StrokeWavy)
        },
    sample "escapes" $ bookOf [para 0 [txt "a & b < c > d \"e\""]],
    sample "aki" $ bookOf [para 0 [txt "前", Aki (at 1) (AkiZw 0.5), txt "後"]],
    sample "cross-chapter" $
      (bookOfDocs [Document fidA [para 0 [Ref (at 1) RefTitle "second", txt "を見よ。"]], Document fidB [Block (atB 0) (Just "second") Nothing (Heading 1 noHeadingAttrs [txt "次の章"])]])
        { bookLabels = Map.fromList [("second", LabelTarget (atB 0) Nothing [txt "次の章"] "second" fidB Nothing)],
          bookToc = [TocEntry 1 Nothing [txt "次の章"] "second" fidB (atB 0)]
        }
  ]

htmlPages :: Sample -> [(FilePath, Text)]
htmlPages s = sitePages (renderHtml cfg0 ft (sBook s))

epubPages :: Sample -> [(FilePath, Text)]
epubPages s = sitePages (renderXhtmlWithPageBreaks cfg0 ft (sBook s) (sBreaks s))

sampleNamed :: String -> Sample
sampleNamed n = case [s | s <- samples, sName s == n] of
  (s : _) -> s
  [] -> error n

-- | All the pages of a sample in one text, the index page of HTML last.
allHtml :: Sample -> Text
allHtml s = T.concat (map snd (htmlPages s)) <> indexPage cfg0 ft (sBook s)

allEpub :: Sample -> Text
allEpub s = T.concat (map snd (epubPages s))

-- | A text frame between two paragraphs (root ADR 0438).
frameSample :: Sample
frameSample = sample "frame" $ bookOf [para 0 [txt "前の段落"], Block (at 1) Nothing Nothing (FrameBlock "quote" [para 2 [txt "枠の一"], para 3 [txt "枠の二"]]), para 4 [txt "後の段落"]]

{- | The page of the frame sample has the paragraph before, the aside of
the frame with its two paragraphs, and the paragraph after, in this
order (root ADR 0438 I6).
-}
assertFrameInPlace :: Text -> Assertion
assertFrameInPlace page = do
  let order = ["前の段落", "<aside class=\"frame frame-quote\">", "枠の一", "枠の二", "</aside>", "後の段落"]
      positions = [T.length (fst (T.breakOn t page)) | t <- order]
  assertBool ("every piece is on the page: " <> T.unpack page) (and [t `T.isInfixOf` page | t <- order])
  assertBool ("the pieces are in order: " <> show positions) (and (zipWith (<) positions (drop 1 positions)))

-- | The start tags of the void elements of HTML that end with a slash.
slashedVoids :: Text -> [Text]
slashedVoids page =
  [ tag
  | piece <- drop 1 (T.splitOn "<" page),
    let tag = T.takeWhile (/= '>') piece
        name = T.takeWhile isAlphaNum tag,
    name `elem` ["br", "col", "img", "meta", "link", "hr", "input", "source", "wbr"],
    "/" `T.isSuffixOf` tag
  ]

-- | I1 of a page: what the HTML syntax leaves out.
assertHtmlSyntax :: FilePath -> Text -> Assertion
assertHtmlSyntax p page = do
  assertBool (p <> ": starts with the doctype") ("<!DOCTYPE html>\n<html" `T.isPrefixOf` page)
  forM_ ["<?xml", "xmlns", "xml:lang", "epub:type"] $ \bad ->
    assertBool (p <> ": no " <> T.unpack bad) (not (bad `T.isInfixOf` page))
  slashedVoids page @?= []

{- | The differences of the table of root ADR 0432 applied in turn to an
XHTML text: the XML declaration, the namespaces and xml:lang removed, the
slash of the void elements of HTML removed, epub:type as role, and the
links to .xhtml pages to .html pages.
-}
toHtmlText :: Text -> Text
toHtmlText =
  T.replace ".xhtml#" ".html#"
    . T.replace "epub:type=\"" "role=\"doc-"
    . unslashVoids
    . removeAttr "xml:lang"
    . removeAttr "xmlns:epub"
    . removeAttr "xmlns"
    . T.replace "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" ""
  where
    removeAttr name t = case T.breakOn (" " <> name <> "=\"") t of
      (before, rest)
        | T.null rest -> before
        | otherwise -> before <> removeAttr name (T.drop 1 (T.dropWhile (/= '"') (T.drop (T.length name + 3) rest)))
    unslashVoids t = case T.breakOn "<" t of
      (before, rest)
        | T.null rest -> before
        | otherwise ->
            let (tag, rest') = T.breakOn ">" rest
                name = T.takeWhile isAlphaNum (T.drop 1 tag)
                tag' = if name `elem` ["br", "col", "img", "meta", "link"] then maybe tag fst (T.unsnoc tag) else tag
             in before <> tag' <> T.take 1 rest' <> unslashVoids (T.drop 1 rest')

goldenDir :: FilePath
goldenDir = "test/golden/"

-- | The EPUB pages of a sample against the XHTML before root ADR 0432.
epubGolden :: Sample -> Assertion
epubGolden s = do
  accept <- lookupEnv "GOLEM_ACCEPT_GOLDEN"
  forM_ (epubPages s) $ \(p, page) -> do
    let file = goldenDir <> "adr-0432-" <> sName s <> "-" <> map (\ch -> if ch == '/' then '-' else ch) p
    when (accept == Just "1") (TIO.writeFile file page)
    expected <- TIO.readFile file
    page @?= expected

-- | A small check that a text is well-formed XML: tags balance and attributes are quoted.
wellFormed :: Text -> Either String ()
wellFormed = go [] . T.unpack
  where
    go stack s = case break (== '<') s of
      (_, []) -> if null stack then Right () else Left ("unclosed " <> show stack)
      (_, _ : rest)
        | "?" `isPrefixOf` rest || "!" `isPrefixOf` rest -> go stack (drop 1 (dropWhile (/= '>') rest))
        | "/" `isPrefixOf` rest ->
            let (name, rest') = break (== '>') (drop 1 rest)
             in case stack of
                  (top : more) | top == name -> go more (drop 1 rest')
                  _ -> Left ("unexpected </" <> name <> ">")
        | otherwise ->
            let (tag, rest') = break (== '>') rest
                name = takeWhile (\ch -> ch /= ' ' && ch /= '/') tag
             in if not (quoted (drop (length name) tag))
                  then Left ("attributes of <" <> name <> ">")
                  else
                    if "/" `isPrefixOf` reverse tag
                      then go stack (drop 1 rest')
                      else go (name : stack) (drop 1 rest')
    quoted a = even (length (filter (== '"') a))

{- | A tree of a page: elements with the attributes the pages have (a
language, epub:type, links to pages), void elements, text with the
characters that are escaped, word joiners and an inline SVG.
-}
genTree :: Gen Node
genTree = Gen.recursive Gen.choice leaves [element, svg]
  where
    leaves =
      [ TextNode <$> genText,
        pure (CharRef 0x2060),
        (\n as -> Element n as []) <$> Gen.element ["br", "col", "img"] <*> genAttrs
      ]
    element = Element <$> Gen.element ["p", "span", "a", "aside", "nav", "div", "rt"] <*> genAttrs <*> Gen.list (Range.linear 0 3) genTree
    svg = Element "svg" [("class", Plain "s"), ("xmlns", Plain "http://www.w3.org/2000/svg")] <$> Gen.list (Range.linear 0 3) genSvg
    genSvg = Gen.recursive Gen.choice [(\n -> Element n [("d", Plain "M 0 0")] []) <$> Gen.element ["path", "rect", "line"]] [Element "g" [] <$> Gen.list (Range.linear 0 2) genSvg]
    genText = Gen.text (Range.linear 0 5) (Gen.element ("ab &<>\"和" :: String))
    genAttrs =
      concat
        <$> sequence
          [ Gen.element [[], [("id", Plain "n-1")]],
            Gen.element [[], [("class", Plain "c")]],
            Gen.element [[], [("lang", Plain "en"), ("xml:lang", Plain "en")]],
            Gen.element [[], [("epub:type", Plain "noteref")], [("epub:type", Plain "footnote")]],
            Gen.element [[], [("href", Plain "#x")], [("href", PageLink "../b" "x")]]
          ]

htmlSyntaxTests :: TestTree
htmlSyntaxTests =
  testGroup
    "the HTML target in the HTML syntax (root ADR 0432)"
    [ testCase "root ADR 0478 I2, I4: decimal HTML and XHTML use one normalized TCY span" $ do
        let body = bookOf [Block (at 0) Nothing Nothing (Paragraph Nothing [Tcy (at 0) (TcyNumber (1 % 10))])]
        mapM_
          (\site -> assertBool "one normalized whole TCY" ("<span class=\"tcy\">0.1</span>" `T.isInfixOf` T.concat (map snd (sitePages site))))
          [renderHtml (cfg0 {hcVertical = True}) ft body, renderXhtmlWithPageBreaks (cfg0 {hcVertical = True}) ft body Map.empty],
      testCase "root ADR 0478 I4: fractional HTML and XHTML honor fixed TCY defaults and explicit overrides" $
        forM_ [False, True] $ \vertical ->
          forM_ ["tcy", "auto", "auto-digits", "kanji"] $ \def ->
            forM_ [Nothing, Just StyleKanji, Just StyleKanjiDigits, Just StyleTcy] $ \style -> do
              let cfg = cfg0 {hcVertical = vertical, hcNumberDefault = def}
                  body = bookOf [Block (at 0) Nothing Nothing (Paragraph Nothing [Number (at 0) (1 % 10) style])]
                  expected = vertical && (style == Just StyleTcy || (isNothing style && def == "tcy"))
              forM_ [renderHtml cfg ft body, renderXhtmlWithPageBreaks cfg ft body Map.empty] $ \site ->
                ("<span class=\"tcy\">0.1</span>" `T.isInfixOf` T.concat (map snd (sitePages site))) @?= expected,
      testCase "root ADR 0438 I6: the paragraphs of @frame are in an aside at the place of the command in HTML" $
        do
          forM_ (htmlPages frameSample) (uncurry assertHtmlSyntax)
          assertFrameInPlace (T.concat (map snd (htmlPages frameSample))),
      testCase "root ADR 0438 I6: the paragraphs of @frame are in an aside at the place of the command in EPUB" $
        assertFrameInPlace (allEpub frameSample),
      testCase "root ADR 0432 I1: a book without documents has the index page alone, which starts with the doctype" $ do
        let book = bookOfDocs []
        map fst (sitePages (renderHtml cfg0 ft book)) @?= []
        assertHtmlSyntax "index.html" (indexPage cfg0 ft book),
      testCase "root ADR 0432 I1: every page of HTML of every sample is in the HTML syntax" $
        forM_ samples $ \s -> do
          forM_ (htmlPages s) (uncurry assertHtmlSyntax)
          assertHtmlSyntax "index.html" (indexPage cfg0 ft (sBook s)),
      testCase "root ADR 0432 I1: the pages of HTML are .html and those of EPUB .xhtml" $ do
        map fst (htmlPages (sampleNamed "cross-chapter")) @?= ["a.html", "chapters/b.html"]
        map fst (epubPages (sampleNamed "cross-chapter")) @?= ["a.xhtml", "chapters/b.xhtml"],
      testCase "root ADR 0432 I1: br, col and img without a slash in HTML, with one in EPUB" $ do
        let s = sampleNamed "void-elements"
        forM_ ["<br>", "<col>", "<col style=\"width: 3em\">", "<img src=\"images/a.png\" alt=\"代替\">", "<meta charset=\"UTF-8\">"] $ \x ->
          assertBool (T.unpack x) (x `T.isInfixOf` allHtml s)
        forM_ ["<br/>", "<col/>", "<col style=\"width: 3em\"/>", "<img src=\"images/a.png\" alt=\"代替\"/>", "<meta charset=\"UTF-8\"/>"] $ \x ->
          assertBool (T.unpack x) (x `T.isInfixOf` allEpub s),
      testCase "root ADR 0432 I1: notes, endnotes and the table of contents carry the roles of DPUB-ARIA in HTML and epub:type in EPUB" $ do
        let s = sampleNamed "notes"
        forM_ ["role=\"doc-noteref\"", "role=\"doc-footnote\"", "role=\"doc-endnote\"", "role=\"doc-toc\""] $ \x ->
          assertBool (T.unpack x) (x `T.isInfixOf` allHtml s)
        forM_ ["epub:type=\"noteref\"", "epub:type=\"footnote\"", "epub:type=\"endnote\"", "epub:type=\"toc\""] $ \x ->
          assertBool (T.unpack x) (x `T.isInfixOf` allEpub s)
        assertBool "no role in EPUB" (not ("role=" `T.isInfixOf` allEpub s)),
      testCase "root ADR 0432 I1, I2: page breaks only in EPUB" $ do
        let s = sampleNamed "page-breaks"
        assertBool "HTML" (not ("pagebreak" `T.isInfixOf` allHtml s))
        assertBool "EPUB" ("<span epub:type=\"pagebreak\" role=\"doc-pagebreak\" id=\"GolemFixedPage-1\" aria-label=\"1\"></span>" `T.isInfixOf` allEpub s),
      testCase "root ADR 0432 I1: a language has lang alone in HTML, lang and xml:lang in EPUB" $ do
        let s = sampleNamed "language"
        assertBool "span" ("<span lang=\"fr\">oui</span>" `T.isInfixOf` allHtml s)
        assertBool "block" ("<p lang=\"en\">en</p>" `T.isInfixOf` allHtml s)
        assertBool "root" ("<html lang=\"ja\">" `T.isInfixOf` allHtml s)
        assertBool "EPUB span" ("<span lang=\"fr\" xml:lang=\"fr\">oui</span>" `T.isInfixOf` allEpub s)
        assertBool "EPUB block" ("<p lang=\"en\" xml:lang=\"en\">en</p>" `T.isInfixOf` allEpub s),
      testCase "root ADR 0432 I6: the inline SVG has no xmlns in HTML and its empty elements close themselves" $ do
        let s = sampleNamed "svg"
            html = allHtml s
        assertBool "svg" ("<svg class=\"separator-rule-svg\" aria-hidden=\"true\"" `T.isInfixOf` html)
        assertBool "path" ("<path d=\"M 0 .5 Q 1 0 2 .5 T 4 .5\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"0.3\"/>" `T.isInfixOf` html)
        assertBool "rect" ("<rect width=\"100%\" height=\"100%\" fill=\"url(#separator-wave-0-1-scene)\"/>" `T.isInfixOf` html)
        assertBool "EPUB" ("<svg class=\"separator-rule-svg\" xmlns=\"http://www.w3.org/2000/svg\" aria-hidden=\"true\"" `T.isInfixOf` allEpub s),
      testCase "root ADR 0432 I3: & and < as &amp; and &lt; in both" $ do
        let s = sampleNamed "escapes"
        forM_ [allHtml s, allEpub s] $ \page -> assertBool (T.unpack page) ("a &amp; b &lt; c &gt; d &quot;e&quot;" `T.isInfixOf` page),
      testCase "root ADR 0432 I3: the word joiners around an aki as &#x2060; in both" $ do
        let s = sampleNamed "aki"
        forM_ [allHtml s, allEpub s] $ \page -> assertBool (T.unpack page) ("前&#x2060;<span class=\"aki\" style=\"margin-inline-start: 0.5em\"></span>&#x2060;後" `T.isInfixOf` page),
      testCase "root ADR 0432 I4: a reference across chapters links .html in HTML and .xhtml in EPUB" $ do
        let s = sampleNamed "cross-chapter"
        assertBool "HTML" (maybe False ("<a href=\"chapters/b.html#second\">" `T.isInfixOf`) (lookup "a.html" (htmlPages s)))
        assertBool "EPUB" (maybe False ("<a href=\"chapters/b.xhtml#second\">" `T.isInfixOf`) (lookup "a.xhtml" (epubPages s)))
        assertBool "index" ("<a href=\"chapters/b.html#second\">" `T.isInfixOf` indexPage cfg0 ft (sBook s)),
      testCase "root ADR 0432 I3: each XHTML page with the differences applied is its HTML page" $
        forM_ [s | s <- samples, Map.null (sBreaks s)] $ \s ->
          [(T.unpack (T.replace ".xhtml" ".html" (T.pack p)), toHtmlText x) | (p, x) <- epubPages s] @?= htmlPages s,
      testProperty "root ADR 0432 I3: a tree written in XHTML with the differences applied is the tree written in HTML" $ property $ do
        tree <- forAll genTree
        toHtmlText (writeDocument XhtmlSyntax [tree]) === writeDocument HtmlSyntax [tree],
      testCase "root ADR 0432 I2: the EPUB pages are the trees written in XHTML, whatever writes HTML" $
        forM_ samples $ \s -> do
          let trees = pageTrees cfg0 ft (sBook s) (sBreaks s)
              -- another writer of HTML in the place of the HTML syntax
              otherHtml = [(pagePathIn HtmlSyntax ft fid, T.pack (show t)) | (fid, t) <- trees]
          epubPages s @?= [(pagePathIn XhtmlSyntax ft fid, writeDocument XhtmlSyntax t) | (fid, t) <- trees]
          assertBool "the other writer differs" (map snd otherHtml /= map snd (htmlPages s)),
      testCase "root ADR 0432 I2: the EPUB pages of every sample are those before root ADR 0432" $
        mapM_ epubGolden samples,
      testCase "root ADR 0432 I2: the EPUB pages of every sample are well-formed XML" $
        forM_ samples $
          \s -> forM_ (epubPages s) $ \(p, page) -> (p, wellFormed page) @?= (p, Right ()),
      testCase "root ADR 0432 I5: the same book gives the same bytes twice" $
        forM_ samples $
          \s -> (htmlPages s, indexPage cfg0 ft (sBook s)) @?= (htmlPages (sampleNamed (sName s)), indexPage cfg0 ft (sBook (sampleNamed (sName s))))
    ]
