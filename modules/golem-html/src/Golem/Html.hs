{- | XHTML and CSS output (golem-html ADR 0001). Pages are polyglot XHTML
so that EPUB can use them unchanged.
-}
module Golem.Html
  ( HtmlConfig (..),
    HtmlLists (..),
    HtmlCharStyle (..),
    HtmlParaStyle (..),
    HtmlFeatures (..),
    noFeatures,
    HtmlLocalStyles (..),
    Face (..),
    noFace,
    HtmlCode (..),
    tokenKind,
    codeTokens,
    XhtmlSite (..),
    renderXhtml,
    pagePath,
    escapeXml,
    cmykToRgb,
  )
where

import Data.Char (isAsciiUpper)
import Data.List (sortOn)
import Data.List.NonEmpty (NonEmpty)
import Data.List.NonEmpty qualified as NE
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.Assemble
import Golem.Doc.Bibliography (EntryPart (..))
import Golem.Doc.IR
import Golem.Doc.ListMarkers
import Golem.Doc.Numbering (numberSeparator)
import Golem.Doc.Numerals
import Golem.Syntax.Span
import Numeric (showHex)
import Skylighting qualified as S
import System.FilePath (makeRelative, replaceExtension, splitDirectories, takeDirectory, takeFileName, (</>))

data HtmlConfig = HtmlConfig
  { hcTitle :: !Text,
    hcLanguage :: !Text,
    hcVertical :: !Bool,
    hcNumberDefault :: !Text, -- kanji, kanji-digits, tcy
    hcSwatches :: !(Map Text (Int, Int, Int, Int)),
    hcFonts :: !(Map Text (Maybe FilePath, Maybe FilePath)), -- role -> (ja, latin)

    -- | the character styles, built-in ones included (docs/adr ADR 0005)
    hcCharStyles :: !(Map Text HtmlCharStyle),
    -- | the paragraph styles, body included (docs/adr ADR 0005)
    hcParaStyles :: !(Map Text HtmlParaStyle),
    -- | the styles of each file that differ from hcCharStyles and hcParaStyles (docs/adr ADR 0014)
    hcLocalStyles :: !(Map FileId HtmlLocalStyles),
    -- | the font and size of figcaption (golem-driver ADR 0010)
    hcCaptionFace :: !Face,
    -- | the font and size of sidenotes (golem-driver ADR 0011)
    hcSidenoteFace :: !Face,
    hcBibliography :: !(Map Text [EntryPart]), -- key -> formatted entry (golem-doc ADR 0005)
    hcDev :: !Bool,
    -- | [composition.ruby] as CSS ruby-align values (golem-layout ADR 0009)
    hcRubyMonoAlign :: !Text,
    hcRubyGroupAlign :: !Text,
    hcRubyBaseSpacing :: !Text,
    -- | the kinds of forced break the book uses (docs/adr ADR 0017)
    hcBreakKinds :: !(Set BreakKind),
    -- | the markers of [lists], when the book has it (golem-driver ADR 0013)
    hcLists :: !(Maybe HtmlLists),
    -- | the paragraph style code: pre (golem-driver ADR 0017)
    hcCode :: !HtmlCode
  }

{- | The paragraph style code for pre (golem-driver ADR 0017): its font
role, its size and its padding as CSS lengths, and the swatch of its
background; its border and [code] (golem-driver ADR 0023).
-}
data HtmlCode = HtmlCode
  { hcoFont :: !(Maybe Text),
    hcoSize :: !(Maybe Text),
    hcoBackground :: !(Maybe Text),
    hcoPadding :: !Text,
    -- | the swatch and the CSS width of the border
    hcoBorder :: !(Maybe Text),
    hcoBorderWidth :: !Text,
    -- | [code] line-numbers
    hcoLineNumbers :: !Bool,
    -- | the swatches of [code]
    hcoLineNumberColor :: !(Maybe Text),
    hcoHighlight :: !(Maybe Text),
    hcoAdded :: !(Maybe Text),
    hcoRemoved :: !(Maybe Text),
    -- | [code.colors]: token kind to swatch
    hcoColors :: !(Map Text Text)
  }
  deriving stock (Eq)

{- | The markers of [lists] (golem-driver ADR 0013): the bullets and the
number formats by depth, and whether a gap is written (Nothing: by the last
character of the marker).
-}
data HtmlLists = HtmlLists
  { hlBullets :: !(NonEmpty Text),
    hlNumbers :: !(NonEmpty NumberFormat),
    hlGap :: !(Maybe Bool)
  }

-- | A font role and a CSS font-size for an element (golem-driver ADR 0010).
data Face = Face
  { faFont :: !(Maybe Text),
    faSize :: !(Maybe Text)
  }
  deriving stock (Eq)

noFace :: Face
noFace = Face Nothing Nothing

-- | A resolved character style for CSS (docs/adr ADR 0005).
data HtmlCharStyle = HtmlCharStyle
  { hcsFont :: !(Maybe Text),
    -- | the resolved synthetic-bold
    hcsBold :: !Bool,
    -- | the resolved synthetic-italic
    hcsItalic :: !Bool,
    hcsColor :: !(Maybe Text),
    -- | kerning, tracking, proportional metrics and baseline shift (docs/adr/0020)
    hcsFeatures :: !HtmlFeatures,
    -- | code or based on it (golem-driver ADR 0017)
    hcsCode :: !Bool,
    {- | the swatch of the background and the padding along the line as a
    CSS length, of code only (golem-driver ADR 0029)
    -} hcsBackground :: !(Maybe Text),
    hcsPadding :: !(Maybe Text)
  }
  deriving stock (Eq)

{- | The keys of a style for the spacing of characters (docs/adr/0020),
as written or resolved; Nothing is not written.
-}
data HtmlFeatures = HtmlFeatures
  { -- | metrics, japanese-equal-width or none
    hfKerning :: !(Maybe Text),
    -- | in 1/1000 em
    hfTracking :: !(Maybe Int),
    hfProportional :: !(Maybe Bool),
    -- | a CSS length
    hfBaselineShift :: !(Maybe Text)
  }
  deriving stock (Eq)

noFeatures :: HtmlFeatures
noFeatures = HtmlFeatures Nothing Nothing Nothing Nothing

-- | A resolved paragraph style for CSS (docs/adr ADR 0005, 0006).
data HtmlParaStyle = HtmlParaStyle
  { hpsFont :: !(Maybe Text),
    hpsKeepLines :: !Bool,
    hpsSpaceBetween :: !Int,
    -- | a CSS length
    hpsIndent :: !Text,
    -- | a CSS length; may be negative
    hpsFirstLineIndent :: !Text,
    -- | kerning, tracking, proportional metrics and baseline shift (docs/adr/0020)
    hpsFeatures :: !HtmlFeatures
  }
  deriving stock (Eq)

{- | The styles a file defines, resolved, where they differ from those of
style.toml (docs/adr ADR 0014): character and paragraph styles by name,
and the faces of figcaption and sidenotes.
-}
data HtmlLocalStyles = HtmlLocalStyles
  { hlCharStyles :: !(Map Text HtmlCharStyle),
    hlParaStyles :: !(Map Text HtmlParaStyle),
    hlCaptionFace :: !(Maybe Face),
    hlSidenoteFace :: !(Maybe Face)
  }

data XhtmlSite = XhtmlSite
  { sitePages :: ![(FilePath, Text)],
    siteCss :: !Text,
    siteAssets :: ![(FilePath, FilePath)] -- output path, source path
  }

pagePath :: FileTable -> FileId -> FilePath
pagePath ft fid = replaceExtension (fromMaybe "unknown" (lookupPath fid ft)) "xhtml"

escapeXml :: Text -> Text
escapeXml = T.concatMap $ \case
  '&' -> "&amp;"
  '<' -> "&lt;"
  '>' -> "&gt;"
  '"' -> "&quot;"
  c -> T.singleton c

{- | The inside of a CSS string in double quotes (docs/adr ADR 0035): a
quote or a backslash after a backslash, a control character as a
backslash, its hexadecimal code and a space. Other characters stay.
-}
cssString :: Text -> Text
cssString = T.concatMap $ \case
  '"' -> "\\\""
  '\\' -> "\\\\"
  c | c < ' ' || c == '\DEL' -> "\\" <> T.pack (showHex (fromEnum c) "") <> " "
  c -> T.singleton c

-- | The naive conversion: screen colours are an approximation of print.
cmykToRgb :: (Int, Int, Int, Int) -> (Int, Int, Int)
cmykToRgb (c, m, y, k) =
  let ch v = round (255 * (1 - fromIntegral v / 100 :: Rational) * (1 - fromIntegral k / 100))
   in (ch c, ch m, ch y)

data Ctx = Ctx
  { cCfg :: HtmlConfig,
    cFt :: FileTable,
    cBook :: Book,
    cHere :: FilePath,
    -- | the paragraph styles of the page: those of its file over those of style.toml (docs/adr ADR 0014)
    cParaStyles :: Map Text HtmlParaStyle,
    -- | the depth of the list around (0 outside lists; golem-driver ADR 0013)
    cListDepth :: Int,
    -- | the notes of the chapter of the page (golem-driver ADR 0026)
    cNotes :: ChapterNotes
  }

{- | Where the notes of a page go (golem-driver ADR 0026): the file whose
page ends the chapter, the id of a note of the page by its number, and
the chapter's documents with the ids of their notes when the page ends
the chapter.
-}
data ChapterNotes = ChapterNotes
  { cnHome :: FileId,
    cnKey :: Int -> Text,
    cnList :: [(FileId, Int -> Text, Document)]
  }

{- | The notes of each document of a chapter (golem-driver ADR 0026): the
id of a note is its number, or the place of its file in the chapter and
its number when the numbers of the chapter meet.
-}
chapterNotes :: [Document] -> [(Document, ChapterNotes)]
chapterNotes docs =
  let home = case reverse docs of
        (Document f _ : _) -> f
        [] -> FileId 0
      numbers d = [n | (_, n, _) <- documentNotes d]
      allNumbers = concatMap numbers docs
      meet = length allNumbers /= Set.size (Set.fromList allNumbers)
      keyOf k n = if meet then tshow k <> "-" <> tshow n else tshow n
      keyed = [(f, keyOf k, d) | (k, d@(Document f _)) <- zip [1 :: Int ..] docs]
   in [(d, ChapterNotes home key (if f == home then keyed else [])) | (f, key, d) <- keyed]

renderXhtml :: HtmlConfig -> FileTable -> Book -> XhtmlSite
renderXhtml cfg ft book =
  XhtmlSite
    { sitePages = [(pagePath ft fid, page cfg ft book notes d) | chapter <- bookChapters book, (d@(Document fid _), notes) <- chapterNotes chapter],
      siteCss = css cfg book,
      siteAssets =
        sortOn fst
          $ Map.toList
          $ Map.fromList
          $ [(T.unpack (webSource f), T.unpack (webSource f)) | Document _ bs <- bookDocs book, Block _ _ (FigureBlock f) <- allFigures bs]
            <> [(fontOut p, p) | (ja, la) <- Map.elems (hcFonts cfg), Just p <- [ja, la]]
    }

webSource :: Figure -> Text
webSource f = fromMaybe (figSource f) (figWeb f)

fontOut :: FilePath -> FilePath
fontOut p = "fonts" </> takeFileName p

allFigures :: [Block] -> [Block]
allFigures = concatMap go
  where
    go b@(Block _ _ body) = case body of
      FigureBlock _ -> [b]
      BulletList items -> allFigures (concatMap itemBlocks items)
      OrderedList items -> allFigures (concatMap itemBlocks items)
      DefList gs -> allFigures (concat (concatMap dgDefs gs))
      _ -> []

relLink :: FilePath -> FilePath -> Text
relLink from to =
  let depth = length (splitDirectories (takeDirectory from)) - (if takeDirectory from == "." then 1 else 0)
   in T.pack (concat (replicate depth "../") <> makeRelative "." to)

page :: HtmlConfig -> FileTable -> Book -> ChapterNotes -> Document -> Text
page cfg ft book notes (Document fid bs) =
  let here = pagePath ft fid
      local = Map.lookup fid (hcLocalStyles cfg)
      c = Ctx cfg ft book here (maybe id (Map.union . hlParaStyles) local (hcParaStyles cfg)) 0 notes
      -- a page with styles of its own has the class of its position (docs/adr ADR 0014)
      classes = ["vertical" | hcVertical cfg] <> ["file-" <> tshow n | Just _ <- [local], (n, Document fid' _) <- zip [1 :: Int ..] (bookDocs book), fid' == fid]
      body = topBlocks c bs <> notesSection c
      title = case [hiTitle h | Block sp _ (Heading 1 _ _) <- bs, Just h <- [Map.lookup sp (bookHeadings book)]] of
        (t : _) -> T.concat (map plain t)
        [] -> hcTitle cfg
   in T.concat
        [ "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE html>\n",
          "<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"http://www.idpf.org/2007/ops\" lang=\"",
          escapeXml (hcLanguage cfg),
          "\" xml:lang=\"",
          escapeXml (hcLanguage cfg),
          "\">\n<head>\n<meta charset=\"UTF-8\"/>\n<title>",
          escapeXml title,
          "</title>\n<link rel=\"stylesheet\" type=\"text/css\" href=\"",
          relLink here "style.css",
          "\"/>\n</head>\n<body",
          if null classes then "" else " class=\"" <> T.unwords classes <> "\"",
          ">\n",
          body,
          "</body>\n</html>\n"
        ]

plain :: InlineF r -> Text
plain = inlineText

idAttr :: Maybe Text -> Text
idAttr = maybe "" (\l -> " id=\"" <> escapeXml l <> "\"")

{- | The blocks at the top of a document: the block after forced breaks
carries the kind of the last of them on its outermost element; a break
at the end writes nothing, and a column break nothing (docs/adr ADR 0017).
-}
topBlocks :: Ctx -> [Block] -> Text
topBlocks c = go Nothing
  where
    go _ [] = ""
    go _ (Block _ _ (ForcedBreak k) : rest) = go (Just k) rest
    go pending (b : rest) = withBreak pending (block c b) <> go Nothing rest
    -- the attribute goes at the end of the first start tag
    withBreak pending html = case pending >>= breakName of
      Nothing -> html
      Just name ->
        let (open, after) = T.breakOn ">" html
         in if T.null after then html else open <> " data-break-before=\"" <> name <> "\"" <> after

-- | The value of data-break-before; a column break has none.
breakName :: BreakKind -> Maybe Text
breakName = \case
  BreakPage -> Just "page"
  BreakRecto -> Just "recto"
  BreakVerso -> Just "verso"
  BreakColumn -> Nothing

block :: Ctx -> Block -> Text
block c (Block sp lbl body) = case body of
  Paragraph st is ->
    let cls = maybe "" (\n -> " class=\"ps-" <> escapeXml n <> "\"") st
        -- the lines of a paragraph that keeps them, each a span; br is for readers without CSS (docs/adr ADR 0005).
        -- A hard break elsewhere is a br, so that text-indent stays on the first line (docs/adr ADR 0016)
        content
          | keepsLines c st = T.intercalate "<br/>\n" ["<span class=\"line\">" <> inlines c l <> "</span>" | l <- splitLines is]
          | otherwise = inlines c is
     in "<p" <> idAttr lbl <> cls <> ">" <> content <> "</p>\n" <> sidenotes c is
  Heading l _ is ->
    let tag = "h" <> T.pack (show l)
        info = Map.lookup sp (bookHeadings (cBook c))
        anchor = maybe (headingAnchor lbl sp) hiAnchor info
        num = numberSpan c (info >>= hiNumberText)
     in "<" <> tag <> " id=\"" <> escapeXml anchor <> "\">" <> num <> inlines c is <> "</" <> tag <> ">\n"
  BulletList items -> "<ul" <> idAttr lbl <> listClass (NE.length . hlBullets) <> ">\n" <> T.concat (map (item inList Nothing) items) <> "</ul>\n"
  OrderedList items ->
    let start = case items of
          (ListItem (Just n) _ : _) -> " start=\"" <> T.pack (show n) <> "\""
          _ -> ""
     in "<ol" <> idAttr lbl <> listClass (NE.length . hlNumbers) <> start <> ">\n" <> T.concat (zipWith (\i it -> item inList (if i > (0 :: Int) then itemNumber it else Nothing) it) [0 ..] items) <> "</ol>\n"
  DefList gs ->
    "<dl"
      <> idAttr lbl
      <> ">\n"
      <> T.concat
        [ T.concat ["<dt>" <> inlines c t <> "</dt>\n" | t <- ts] <> T.concat ["<dd>\n" <> T.concat (map (block c) d) <> "</dd>\n" | d <- ds]
        | DefGroup ts ds <- gs
        ]
      <> "</dl>\n"
  Table al h rows ->
    let cls a = case a of
          AlignLeft -> " class=\"align-left\""
          AlignCenter -> " class=\"align-center\""
          AlignRight -> " class=\"align-right\""
          AlignDefault -> ""
        row tag cells = "<tr>" <> T.concat (zipWith (\a x -> "<" <> tag <> cls a <> ">" <> inlines c x <> "</" <> tag <> ">") (al <> repeat AlignDefault) cells) <> "</tr>\n"
     in "<table" <> idAttr lbl <> ">\n<thead>\n" <> row "th" h <> "</thead>\n<tbody>\n" <> T.concat (map (row "td") rows) <> "</tbody>\n</table>\n"
  CodeBlock code ->
    let co = hcCode (cCfg c)
        lang = codeLang code
        ls = codeLines code
        -- a caption or a file name: a figure (golem-driver ADR 0023)
        wrapped = isJust (codeCaption code) || isJust (codeFile code)
        caption =
          [ "<figcaption>" <> maybe "" (\n -> escapeXml n <> "　") (Map.lookup sp (bookListings (cBook c))) <> inlines c is <> "</figcaption>"
          | Just is <- [codeCaption code]
          ]
        file = ["<div class=\"code-file\">" <> escapeXml f <> "</div>" | Just f <- [codeFile code]]
        numbered = fromMaybe (hcoLineNumbers co) (codeNumbers code)
        -- a block with line numbers, highlights, a diff or callouts: a span per line
        perLine = numbered || codeDiff code || any (\l -> clHighlight l || not (null (clCallouts l))) ls
        texts = highlightedLines lang (codeText code)
        line l h =
          let classes = T.unwords (["line"] <> ["hl" | clHighlight l] <> ["add" | clDiff l == Just DiffAdded] <> ["del" | clDiff l == Just DiffRemoved])
              ln = ["<span class=\"ln\" aria-hidden=\"true\">" <> maybe "" tshow (clNumber l) <> "</span>" | numbered]
              dm = ["<span class=\"dm\" aria-hidden=\"true\">" <> diffMark (clDiff l) <> "</span>" | codeDiff code]
              callouts = [" <span class=\"callout\">" <> circled n <> "</span>" | n <- clCallouts l]
           in "<span class=\"" <> classes <> "\">" <> T.concat (ln <> dm) <> h <> T.concat callouts <> "</span>"
        content
          | perLine = T.intercalate "\n" (zipWith line ls (if length texts == length ls then texts else map (escapeXml . clText) ls))
          | otherwise = highlighted lang (codeText code)
        pre = "<pre" <> (if wrapped then "" else idAttr lbl) <> "><code" <> maybe "" (\l -> " class=\"sourceCode language-" <> escapeXml l <> "\"") lang <> ">" <> content <> "</code></pre>"
     in if wrapped
          then "<figure class=\"listing\"" <> idAttr lbl <> ">" <> T.concat (caption <> file) <> pre <> "</figure>\n"
          else pre <> "\n"
  FigureBlock f ->
    let num = numberSpan c (Map.lookup sp (bookFigures (cBook c)))
        cap = T.concat [inlines c is | Block _ _ (Paragraph _ is) <- figCaption f]
     in "<figure" <> idAttr lbl <> ">\n<img src=\"" <> escapeXml (relLink (cHere c) (T.unpack (webSource f))) <> "\" alt=\"" <> escapeXml (figAlt f) <> "\"/>\n<figcaption>" <> num <> cap <> "</figcaption>\n</figure>\n"
  ChannelOutput (TocOutput d) -> toc c (Just d)
  ChannelOutput IndexOutput -> index c
  ChannelOutput BibliographyOutput ->
    "<ol class=\"bibliography\">\n"
      <> T.concat
        [ "<li id=\"cite-" <> escapeXml k <> "\">" <> maybe (escapeXml k) (T.concat . map entryPart) (Map.lookup k (hcBibliography (cCfg c))) <> "</li>\n"
        | (k, _) <- bookCitations (cBook c)
        ]
      <> "</ol>\n"
  ForcedBreak _ -> ""
  where
    -- a URL of http or https is a link; another URL is not (golem-doc ADR 0005)
    entryPart = \case
      EntryText t -> escapeXml t
      EntryUrl u
        | any (`T.isPrefixOf` T.toLower u) ["http:", "https:"] -> "<a class=\"cs-url\" href=\"" <> escapeXml u <> "\">" <> escapeXml u <> "</a>"
        | otherwise -> "<span class=\"cs-url\">" <> escapeXml u <> "</span>"
    -- the lists inside count one deeper; with [lists], the class of the depth (golem-driver ADR 0013)
    depth = cListDepth c + 1
    inList = c {cListDepth = depth}
    listClass count = case hcLists (cCfg c) of
      Just ls -> " class=\"list-" <> tshow (min depth (count ls)) <> "\""
      Nothing -> ""

{- | The number of a heading or a caption in its span, and the separator
of the language of the book after it as text (golem-html ADR 0002).
-}
numberSpan :: Ctx -> Maybe Text -> Text
numberSpan c = maybe "" (\n -> "<span class=\"number\">" <> escapeXml n <> "</span>" <> escapeXml (numberSeparator (hcLanguage (cCfg c)) n))

item :: Ctx -> Maybe Integer -> ListItem -> Text
item c value (ListItem _ bs) =
  "<li" <> maybe "" (\n -> " value=\"" <> T.pack (show n) <> "\"") value <> ">" <> case bs of
    [Block _ _ (Paragraph Nothing is)] | not (keepsLines c Nothing) -> inlines c is <> "</li>\n"
    _ -> "\n" <> T.concat (map (block c) bs) <> "</li>\n"

-- | Whether the paragraph style keeps the lines of its paragraphs (docs/adr ADR 0005).
keepsLines :: Ctx -> Maybe Text -> Bool
keepsLines c st = maybe False hpsKeepLines (Map.lookup (fromMaybe "body" st) (cParaStyles c))

toc :: Ctx -> Maybe Int -> Text
toc c depth =
  "<nav epub:type=\"toc\" class=\"toc\">\n<ol>\n"
    <> T.concat
      [ "<li class=\"toc-"
          <> T.pack (show (teLevel e))
          <> "\"><a href=\""
          <> linkTo c (teFile e) (teAnchor e)
          <> "\">"
          <> maybe "" (\n -> escapeXml (n <> numberSeparator (hcLanguage (cCfg c)) n)) (teNumber e)
          <> inlines c (teTitle e)
          <> "</a></li>\n"
      | e <- bookToc (cBook c),
        maybe True (teLevel e <=) depth
      ]
    <> "</ol>\n</nav>\n"

linkTo :: Ctx -> FileId -> Text -> Text
linkTo c fid anchor =
  let target = pagePath (cFt c) fid
      -- a path is escaped like any attribute value (docs/adr ADR 0035)
      file = if target == cHere c then "" else escapeXml (relLink (cHere c) target)
   in file <> "#" <> escapeXml anchor

index :: Ctx -> Text
index c =
  "<section class=\"index\">\n<ul>\n"
    <> T.concat
      [ "<li>"
          <> escapeXml (T.intercalate " / " (igTerms g))
          <> " "
          <> T.intercalate ", " ["<a href=\"" <> linkTo c fid (spanAnchor sp) <> "\">" <> T.pack (show i) <> "</a>" | (i, (fid, sp)) <- zip [1 :: Int ..] (igLocations g)]
          <> "</li>\n"
      | g <- bookIndex (cBook c)
      ]
    <> "</ul>\n</section>\n"

spanAnchor :: SrcSpan -> Text
spanAnchor (SrcSpan (FileId f) s _) = "i-" <> T.pack (show f) <> "-" <> T.pack (show s)

inlines :: Ctx -> [InlineF r] -> Text
inlines c = T.concat . map (inline c)

inline :: Ctx -> InlineF r -> Text
inline c = \case
  Text _ t -> escapeXml t
  Ruby _ _ segs ->
    -- several segments, or one base character, are mono ruby (golem-layout ADR 0009)
    (if length segs >= 2 || T.length (T.concat [foldMap inlineText b | RubySegment b _ <- segs]) == 1 then "<ruby class=\"mono\">" else "<ruby>")
      <> T.concat [inlines c b <> "<rp>（</rp><rt>" <> maybe "" escapeXml r <> "</rt><rp>）</rp>" | RubySegment b r <- segs]
      <> "</ruby>"
  -- the shape of the IR; none (from a plugin) is sesame (golem-driver ADR 0019)
  Kenten _ sh xs -> "<span class=\"kenten kenten-" <> escapeXml (fromMaybe "sesame" sh) <> "\">" <> inlines c xs <> "</span>"
  Color _ s xs -> "<span class=\"swatch-" <> escapeXml s <> "\">" <> inlines c xs <> "</span>"
  -- the built-in character styles keep their elements (docs/adr ADR 0005)
  CharStyle _ "strong" xs -> "<strong>" <> inlines c xs <> "</strong>"
  CharStyle _ "bold" xs -> "<b>" <> inlines c xs <> "</b>"
  CharStyle _ "italic" xs -> "<i>" <> inlines c xs <> "</i>"
  CharStyle _ "code" xs -> "<code>" <> inlines c xs <> "</code>"
  CharStyle _ s xs -> "<span class=\"cs-" <> escapeXml s <> "\">" <> inlines c xs <> "</span>"
  Tcy _ t -> "<span class=\"tcy\">" <> escapeXml t <> "</span>"
  Number _ n st
    | not (hcVertical (cCfg c)) -> T.pack (show n)
    | otherwise -> case fromMaybe (styleOf (hcNumberDefault (cCfg c))) st of
        StyleKanji -> kanji n
        StyleKanjiDigits -> kanjiDigits n
        StyleTcy -> "<span class=\"tcy\">" <> T.pack (show n) <> "</span>"
  Ref _ _ l -> case Map.lookup l (bookLabels (cBook c)) of
    Just t -> "<a href=\"" <> linkTo c (ltFile t) (ltAnchor t) <> "\">" <> inlines c (ltTitle t) <> "</a>"
    Nothing -> ""
  Deferred {} -> ""
  Note _ n _ ->
    let key = cnKey (cNotes c) n
     in "<a epub:type=\"noteref\" class=\"noteref\" href=\"" <> linkTo c (cnHome (cNotes c)) ("note-" <> key) <> "\" id=\"noteref-" <> key <> "\">" <> tshow n <> "</a>"
  Sidenote _ n _ -> "<sup class=\"sidenote-ref\">" <> tshow n <> "</sup>"
  IndexMark sp _ -> "<span id=\"" <> spanAnchor sp <> "\"></span>"
  Cite _ k -> case lookup k (bookCitations (cBook c)) of
    Just n -> "<a class=\"cite\" href=\"#cite-" <> escapeXml k <> "\">[" <> tshow n <> "]</a>"
    Nothing -> ""
  ProofComment _ t -> if hcDev (cCfg c) then "<span class=\"proof\">" <> escapeXml t <> "</span>" else ""
  LineBreak _ -> "<br/>"
  -- an empty span with a margin; word joiners keep the line from breaking around it (docs/adr ADR 0019)
  Aki _ a -> "&#x2060;<span class=\"aki\" style=\"margin-inline-start: " <> akiLength a <> "\"></span>&#x2060;"
  where
    styleOf = \case
      "kanji-digits" -> StyleKanjiDigits
      "tcy" -> StyleTcy
      _ -> StyleKanji

tshow :: (Show a) => a -> Text
tshow = T.pack . show

-- | The CSS length of an aki: zw in em, an absolute amount in pt.
akiLength :: AkiAmount -> Text
akiLength = \case
  AkiZw r -> decimal r <> "em"
  AkiAbs x -> decimal (toRational x / 65536) <> "pt"
  where
    -- at most four decimal places, rounded half to even, without trailing zeros
    decimal r =
      let n = round (r * 10000) :: Integer
          (i, f) = abs n `quotRem` 10000
          frac = T.dropWhileEnd (== '0') (T.justifyRight 4 '0' (tshow f))
       in (if n < 0 then "-" else "") <> tshow i <> (if T.null frac then "" else "." <> frac)

isLineBreak :: InlineF r -> Bool
isLineBreak = \case
  LineBreak _ -> True
  _ -> False

-- | The inlines of a paragraph split at its line breaks.
splitLines :: [InlineF r] -> [[InlineF r]]
splitLines is = case break isLineBreak is of
  (l, []) -> [l]
  (l, _ : rest) -> l : splitLines rest

sidenotes :: Ctx -> [Inline] -> Text
sidenotes c is = T.concat ["<aside class=\"sidenote\"><span class=\"number\">" <> tshow n <> "</span>" <> inlines c xs <> "</aside>\n" | Sidenote _ n xs <- is]

{- | The notes of the chapter at the end of its last page, after a title
(golem-driver ADR 0026); each links back to its mark, on whichever page.
-}
notesSection :: Ctx -> Text
notesSection c =
  case [(f, key, n, xs) | (f, key, d) <- cnList (cNotes c), (_, n, xs) <- documentNotes d] of
    [] -> ""
    ns ->
      "<section class=\"notes\">\n<h2>"
        <> escapeXml (notesTitle (hcLanguage (cCfg c)))
        <> "</h2>\n"
        <> T.concat
          [ "<aside epub:type=\"footnote\" id=\"note-" <> key n <> "\"><a href=\"" <> linkTo c f ("noteref-" <> key n) <> "\">" <> tshow n <> "</a> " <> inlines c xs <> "</aside>\n"
          | (f, key, n, xs) <- ns
          ]
        <> "</section>\n"

{- | Code coloured with skylighting's classes (golem-html ADR 0001). An
unknown language, or text the highlighter rejects, stays plain.
-}
highlighted :: Maybe Text -> Text -> Text
highlighted lang code = T.intercalate "\n" (highlightedLines lang code)

-- | The lines of 'highlighted', each its own.
highlightedLines :: Maybe Text -> Text -> [Text]
highlightedLines lang code = case lang >>= \l -> S.lookupSyntax l S.defaultSyntaxMap of
  Nothing -> escaped
  Just syntax -> case S.tokenize (S.TokenizerConfig S.defaultSyntaxMap False) syntax code of
    Left _ -> escaped
    Right ls -> map (T.concat . map tok) ls
  where
    escaped = map escapeXml (T.splitOn "\n" code)
    tok (S.NormalTok, t) = escapeXml t
    tok (ty, t) = "<span class=\"" <> shortClass ty <> "\">" <> escapeXml t <> "</span>"

{- | The tokens of each line of code as the HTML colours them, with their
token kinds (golem-driver ADR 0023): Nothing for a language skylighting
does not know and for text it rejects. Normal text has no kind.
-}
codeTokens :: Maybe Text -> Text -> Maybe [[(Maybe Text, Text)]]
codeTokens lang code = do
  syntax <- lang >>= \l -> S.lookupSyntax l S.defaultSyntaxMap
  ls <- either (const Nothing) Just (S.tokenize (S.TokenizerConfig S.defaultSyntaxMap False) syntax code)
  pure [[(if ty == S.NormalTok then Nothing else Just (tokenKind ty), t) | (ty, t) <- l] | l <- ls]

-- | The mark of a line of a diff (golem-driver ADR 0023).
diffMark :: Maybe DiffMark -> Text
diffMark = \case
  Just DiffAdded -> "+"
  Just DiffRemoved -> "-"
  _ -> " "

-- | Every token type of skylighting.
tokenTypes :: [S.TokenType]
tokenTypes =
  [ S.KeywordTok,
    S.DataTypeTok,
    S.DecValTok,
    S.BaseNTok,
    S.FloatTok,
    S.CharTok,
    S.StringTok,
    S.CommentTok,
    S.OtherTok,
    S.AlertTok,
    S.FunctionTok,
    S.RegionMarkerTok,
    S.ErrorTok,
    S.ConstantTok,
    S.SpecialCharTok,
    S.VerbatimStringTok,
    S.SpecialStringTok,
    S.ImportTok,
    S.DocumentationTok,
    S.AnnotationTok,
    S.CommentVarTok,
    S.VariableTok,
    S.ControlFlowTok,
    S.OperatorTok,
    S.BuiltInTok,
    S.ExtensionTok,
    S.PreprocessorTok,
    S.AttributeTok,
    S.InformationTok,
    S.WarningTok
  ]

{- | The token kind of [code.colors] (golem-driver ADR 0023): the name of
skylighting's TokenType in kebab-case, without Tok.
-}
tokenKind :: S.TokenType -> Text
tokenKind ty = T.intercalate "-" (map T.toLower (words' (fromMaybe name (T.stripSuffix "Tok" name))))
  where
    name = T.pack (show ty)
    words' t = case T.uncons t of
      Nothing -> []
      Just (h, rest) -> let (w, more) = T.break isAsciiUpper rest in T.cons h w : words' more

-- | skylighting's short class names.
shortClass :: S.TokenType -> Text
shortClass = \case
  S.KeywordTok -> "kw"
  S.DataTypeTok -> "dt"
  S.DecValTok -> "dv"
  S.BaseNTok -> "bn"
  S.FloatTok -> "fl"
  S.CharTok -> "ch"
  S.StringTok -> "st"
  S.CommentTok -> "co"
  S.OtherTok -> "ot"
  S.AlertTok -> "al"
  S.FunctionTok -> "fu"
  S.RegionMarkerTok -> "re"
  S.ErrorTok -> "er"
  S.ConstantTok -> "cn"
  S.SpecialCharTok -> "sc"
  S.VerbatimStringTok -> "vs"
  S.SpecialStringTok -> "ss"
  S.ImportTok -> "im"
  S.DocumentationTok -> "do"
  S.AnnotationTok -> "an"
  S.CommentVarTok -> "cv"
  S.VariableTok -> "va"
  S.ControlFlowTok -> "cf"
  S.OperatorTok -> "op"
  S.BuiltInTok -> "bu"
  S.ExtensionTok -> "ex"
  S.PreprocessorTok -> "pp"
  S.AttributeTok -> "at"
  S.InformationTok -> "in"
  S.WarningTok -> "wa"
  S.NormalTok -> ""

{- | The rules of the lines of code blocks and the colours of tokens
(golem-driver ADR 0023): the line numbers and the diff marks out of a
selection, the line numbers as wide as the most digits of the book, the
backgrounds of the highlight (K 15% by default) and of the diff, written
when the book has a block with lines; the colour of each token kind of
[code.colors].
-}
codeRules :: HtmlConfig -> Book -> [Text]
codeRules cfg book =
  ( if null withLines
      then []
      else
        [ "pre .line { display: inline-block; width: 100%; }",
          ".ln, .dm { user-select: none; -webkit-user-select: none; }",
          ".ln { display: inline-block; width: " <> tshow digits <> "ch; margin-inline-end: 2ch; text-align: right;" <> maybe "" (\col -> " color: " <> col <> ";") (rgbOf =<< hcoLineNumberColor co) <> " }",
          ".dm { display: inline-block; width: 2ch; }"
        ]
          <> ["pre .add { background-color: " <> col <> "; }" | Just col <- [rgbOf =<< hcoAdded co]]
          <> ["pre .del { background-color: " <> col <> "; }" | Just col <- [rgbOf =<< hcoRemoved co]]
          -- the highlight wins over the diff
          <> ["pre .hl { background-color: " <> fromMaybe (rgb (cmykToRgb (0, 0, 0, 15))) (rgbOf =<< hcoHighlight co) <> "; }"]
  )
    <> [ "code span." <> shortClass ty <> " { color: " <> col <> "; }"
       | ty <- tokenTypes,
         Just sw <- [Map.lookup (tokenKind ty) (hcoColors co)],
         Just col <- [rgbOf sw]
       ]
  where
    co = hcCode cfg
    codes = [c | Document _ bs <- bookDocs book, c <- concatMap codesIn bs]
    codesIn (Block _ _ body) = case body of
      CodeBlock c -> [c]
      BulletList items -> concatMap (concatMap codesIn . itemBlocks) items
      OrderedList items -> concatMap (concatMap codesIn . itemBlocks) items
      DefList gs -> concatMap (concatMap (concatMap codesIn) . dgDefs) gs
      FigureBlock f -> concatMap codesIn (figCaption f)
      _ -> []
    numberedCode c = fromMaybe (hcoLineNumbers co) (codeNumbers c)
    withLines = [c | c <- codes, numberedCode c || codeDiff c || any (\l -> clHighlight l || not (null (clCallouts l))) (codeLines c)]
    digits = maximum (1 : [T.length (tshow n) | c <- withLines, numberedCode c, CodeLine {clNumber = Just n} <- codeLines c])
    rgb (r, g, b) = "rgb(" <> tshow r <> ", " <> tshow g <> ", " <> tshow b <> ")"
    rgbOf sw = rgb . cmykToRgb <$> Map.lookup sw (hcSwatches cfg)

{- | A @counter-style for the bullet and the number format of each depth,
and the list-style-type of the lists of that class (golem-driver ADR 0013).
Notations CSS has no system for are fixed symbols, as many as the largest
number of the depth in the book.
-}
listRules :: HtmlConfig -> Book -> HtmlLists -> [Text]
listRules cfg book ls =
  concat
    [ [ "@counter-style golem-ul-" <> tshow k <> " { system: cyclic; symbols: " <> str b <> "; suffix: " <> str (gapAfter b) <> "; }",
        "ul.list-" <> tshow k <> " { list-style-type: golem-ul-" <> tshow k <> "; }"
      ]
    | (k, b) <- zip [1 :: Int ..] (NE.toList (hlBullets ls))
    ]
    <> concat
      [ [ "@counter-style golem-ol-" <> tshow k <> " { " <> system k st <> (if T.null pre then "" else " prefix: " <> str pre <> ";") <> " suffix: " <> str (suf <> gapAfter (pre <> "0" <> suf)) <> "; }",
          "ol.list-" <> tshow k <> " { list-style-type: golem-ol-" <> tshow k <> "; }"
        ]
      | (k, NumberFormat pre st suf) <- zip [1 :: Int ..] (NE.toList (hlNumbers ls))
      ]
  where
    count = NE.length (hlNumbers ls)
    -- the largest number at the depths of a class
    largest k = maximum (1 : [lsiNumber s | s <- listSites (concat [bs | Document _ bs <- bookDocs book]), min (lsiDepth s) count == k])
    system k st = case st of
      NsBook
        | hcVertical cfg -> case hcNumberDefault cfg of
            "kanji-digits" -> extends "cjk-decimal"
            "tcy" -> extends "decimal"
            _ -> extends "japanese-informal"
        | otherwise -> extends "decimal"
      NsArabic -> extends "decimal"
      NsKanji -> extends "japanese-informal"
      NsLowerAlpha -> extends "lower-alpha"
      NsUpperAlpha -> extends "upper-alpha"
      NsLowerRoman -> extends "lower-roman"
      NsUpperRoman -> extends "upper-roman"
      _ -> "system: fixed; symbols: " <> T.unwords [str (fromMaybe (tshow n) (formatListNumber st n)) | n <- [1 .. largest k]] <> ";"
    extends s = "system: extends " <> s <> ";"
    -- the space after a marker: the gap of [lists], or none after punctuation with its own space
    gapAfter m = if fromMaybe (not (endsWithSpacedPunctuation m)) (hlGap ls) then " " else ""
    str t = "\"" <> T.replace "\"" "\\\"" (T.replace "\\" "\\\\" t) <> "\""

{- | The style sheet; the documents of the book in order number the rules
of the styles of their files (docs/adr ADR 0014), and its lists give the
largest numbers of the fixed list markers (golem-driver ADR 0013).
-}
css :: HtmlConfig -> Book -> Text
css cfg book =
  T.unlines $
    [ "@font-face { font-family: \""
        <> cssString (family role kind)
        <> "\"; src: url(\""
        <> cssString (T.pack (fontOut p))
        <> "\");"
        <> (if role `elem` boldRoles then " font-weight: bold;" else "")
        <> (if role `elem` italicRoles then " font-style: italic;" else "")
        <> " }"
    | (role, (ja, la)) <- Map.toAscList (hcFonts cfg),
      (kind, Just p) <- [("latin" :: Text, la), ("ja", ja)]
    ]
      <> [ "body { font-family: " <> fontStack "body" <> "; }",
           "body.vertical { writing-mode: vertical-rl; -epub-writing-mode: vertical-rl; }",
           -- code blocks and code (golem-driver ADR 0017)
           "pre, code { font-family: " <> codeStack <> "; }",
           rule "pre" (["white-space: pre-wrap", "overflow-wrap: anywhere", "tab-size: 2", "hyphens: none", "font-kerning: none"] <> preDecls)
         ]
      -- strong is always written (docs/adr ADR 0005)
      <> [charRule "strong" cs | Just cs <- [Map.lookup "strong" (hcCharStyles cfg)]]
      <> [ ".tcy { text-combine-upright: all; -epub-text-combine: horizontal; }",
           ".kenten { text-emphasis-style: sesame; -epub-text-emphasis-style: sesame; }",
           ".kenten-open-sesame { text-emphasis-style: open sesame; }",
           ".kenten-dot { text-emphasis-style: dot; }",
           ".kenten-open-dot { text-emphasis-style: open dot; }",
           ".kenten-circle { text-emphasis-style: circle; }",
           ".kenten-open-circle { text-emphasis-style: open circle; }",
           -- golem-driver ADR 0019
           ".kenten-sesame { text-emphasis-style: sesame; -epub-text-emphasis-style: sesame; }",
           ".kenten-double-circle { text-emphasis-style: double-circle; }",
           ".kenten-open-double-circle { text-emphasis-style: open double-circle; }",
           ".kenten-triangle { text-emphasis-style: triangle; }",
           ".kenten-open-triangle { text-emphasis-style: open triangle; }",
           ".align-left { text-align: left; }",
           ".align-center { text-align: center; }",
           ".align-right { text-align: right; }",
           ".proof { background: #ffeb99; }",
           -- ruby: the base, a group reading and a mono reading (golem-layout ADR 0009)
           "ruby { ruby-align: " <> hcRubyBaseSpacing cfg <> "; }",
           "rt { ruby-align: " <> hcRubyGroupAlign cfg <> "; }",
           "ruby.mono rt { ruby-align: " <> hcRubyMonoAlign cfg <> "; }"
         ]
      -- the caption's font and size (golem-driver ADR 0010)
      <> [faceRule "figcaption" (hcCaptionFace cfg) | isJust (faFont (hcCaptionFace cfg)) || isJust (faSize (hcCaptionFace cfg))]
      -- the sidenote's font and size; smaller than the text when no size is given (golem-driver ADR 0011)
      <> [ faceRule ".sidenote" (hcSidenoteFace cfg) {faSize = Just (fromMaybe "0.85em" (faSize (hcSidenoteFace cfg)))},
           "@media (min-width: 60em) { .sidenote { float: right; clear: right; width: 14em; margin-right: -16em; } }"
         ]
      -- paragraph styles (docs/adr ADR 0005); body is the plain p
      <> concat [paraRules name ps | (name, ps) <- Map.toAscList (hcParaStyles cfg), name /= "code"]
      -- no indent in list items (docs/adr ADR 0006); li p[class] is stronger than p.ps-name
      <> ["li p, li p[class] { padding-inline-start: 0; text-indent: 0; }" | any (uncurry indentRule) (Map.toList (hcParaStyles cfg))]
      -- the lines of a paragraph that keeps them; br is for readers without CSS
      <> [ ".line { display: block; }",
           ".line + br { display: none; }"
         ]
      -- the lines of code blocks and the colours of code (golem-driver ADR 0023)
      <> codeRules cfg book
      <> [ ".swatch-" <> name <> " { color: rgb(" <> tshow r <> ", " <> tshow g <> ", " <> tshow b <> "); }"
         | (name, cmyk) <- Map.toAscList (hcSwatches cfg),
           let (r, g, b) = cmykToRgb cmyk
         ]
      <> [r | (name, cs) <- Map.toAscList (hcCharStyles cfg), name /= "strong", Just r <- [charRuleMaybe name cs]]
      -- the markers of [lists] by depth (golem-driver ADR 0013)
      <> maybe [] (listRules cfg book) (hcLists cfg)
      -- forced breaks, only the kinds the book uses (docs/adr ADR 0017)
      <> [ "[data-break-before=\"" <> name <> "\"] { page-break-before: always; break-before: " <> name <> "; }"
         | k <- Set.toAscList (hcBreakKinds cfg),
           Just name <- [breakName k]
         ]
      -- the styles of the files, last, under the class of their pages (docs/adr ADR 0014)
      <> concat [localRules n l | (n, fid) <- zip [1 :: Int ..] docs, Just l <- [Map.lookup fid (hcLocalStyles cfg)]]
  where
    docs = [fid | Document fid _ <- bookDocs book]
    -- the role of code, then monospace (golem-driver ADR 0017)
    codeStack = T.intercalate ", " (maybe [] families (hcoFont (hcCode cfg)) <> ["monospace"])
    preDecls =
      let co = hcCode cfg
       in [ d
          | Just sw <- [hcoBackground co],
            Just cmyk <- [Map.lookup sw (hcSwatches cfg)],
            let (r, g, b) = cmykToRgb cmyk,
            d <- ["background-color: rgb(" <> tshow r <> ", " <> tshow g <> ", " <> tshow b <> ")", "padding: " <> hcoPadding co]
          ]
            <> ["font-size: " <> sz | Just sz <- [hcoSize co]]
            <> [ "border: " <> hcoBorderWidth co <> " solid rgb(" <> tshow r <> ", " <> tshow g <> ", " <> tshow b <> ")"
               | Just sw <- [hcoBorder co],
                 Just cmyk <- [Map.lookup sw (hcSwatches cfg)],
                 let (r, g, b) = cmykToRgb cmyk
               ]
    -- a role a bold (italic) character style sets: its font is declared bold (italic)
    allCharStyles = Map.elems (hcCharStyles cfg) <> concatMap (Map.elems . hlCharStyles) (Map.elems (hcLocalStyles cfg))
    boldRoles = [r | HtmlCharStyle {hcsFont = Just r, hcsBold = True} <- allCharStyles]
    italicRoles = [r | HtmlCharStyle {hcsFont = Just r, hcsItalic = True} <- allCharStyles]
    selectorOf = \case
      "strong" -> "strong"
      "bold" -> "b"
      "italic" -> "i"
      "code" -> "code"
      name -> ".cs-" <> name
    -- what the element shows without a rule
    defaults = \case
      "strong" -> ["font-weight: bold"]
      "bold" -> ["font-weight: bold"]
      "italic" -> ["font-style: italic"]
      _ -> []
    declsOf name cs =
      [ "font-family: " <> T.intercalate ", " (families role <> fallback)
      | -- code is in the rule of pre and code when it has the role of pre
        name /= "code" || hcsFont cs /= hcoFont (hcCode cfg),
        Just role <- [hcsFont cs]
      ]
        <> ["hyphens: none" | hcsCode cs, name /= "code"]
        <> ( if hcsBold cs
               then ["font-weight: bold"]
               else ["font-weight: normal" | "font-weight: bold" `elem` defaults name]
           )
        <> ( if hcsItalic cs
               then ["font-style: italic"]
               else ["font-style: normal" | "font-style: italic" `elem` defaults name]
           )
        <> [ "color: rgb(" <> tshow r <> ", " <> tshow g <> ", " <> tshow b <> ")"
           | Just sw <- [hcsColor cs],
             Just cmyk <- [Map.lookup sw (hcSwatches cfg)],
             let (r, g, b) = cmykToRgb cmyk
           ]
        <> featureDecls (hcsFeatures cs)
        -- the background and the padding of inline code, along the line only (golem-driver ADR 0029)
        <> ["background-color: " <> rgbOf cmyk | Just sw <- [hcsBackground cs], Just cmyk <- [Map.lookup sw (hcSwatches cfg)]]
        <> ["padding-inline: " <> p | Just p <- [hcsPadding cs]]
      where
        fallback = if hcsCode cs then ["monospace"] else families "body" <> ["serif"]
    {- the keys of the spacing of characters whose values differ from the
    defaults of body (docs/adr/0020): CSS kerns Japanese and Latin alike,
    so japanese-equal-width keeps the Latin kerning -}
    featureDecls f =
      [ "font-kerning: " <> (if k == "none" then "none" else "normal")
      | Just k <- [hfKerning f],
        k /= "metrics"
      ]
        <> ["letter-spacing: " <> thousandths t <> "em" | Just t <- [hfTracking f], t /= 0]
        <> ["font-feature-settings: \"" <> (if hcVertical cfg then "vpal" else "palt") <> "\" 1" | hfProportional f == Just True]
        <> ["vertical-align: " <> l | Just l <- [hfBaselineShift f], not (isZero l)]
    thousandths n =
      let (q, r) = abs n `divMod` 1000
          frac = T.dropWhileEnd (== '0') (T.justifyRight 3 '0' (tshow r))
       in (if n < 0 then "-" else "") <> tshow q <> (if T.null frac then "" else "." <> frac)
    rgbOf cmyk = let (r, g, b) = cmykToRgb cmyk in "rgb(" <> tshow r <> ", " <> tshow g <> ", " <> tshow b <> ")"
    rule sel ds = sel <> " { " <> T.concat [d <> "; " | d <- ds] <> "}"
    faceRule sel f = rule sel (["font-family: " <> fontStack role | Just role <- [faFont f]] <> ["font-size: " <> s | Just s <- [faSize f]])
    charRule name cs = rule (selectorOf name) (declsOf name cs)
    -- a rule that says only what the element shows anyway is not written
    charRuleMaybe name cs =
      let ds = declsOf name cs
       in if null ds || ds == defaults name then Nothing else Just (rule (selectorOf name) ds)
    {- the indent of a style is written when it differs from body's, and
    body's when it is not 0; text-indent is inherited by the lines, so
    each line of a style that keeps them hangs (docs/adr ADR 0006) -}
    bodyIndent = maybe ("0em", "0em") (\b -> (hpsIndent b, hpsFirstLineIndent b)) (Map.lookup "body" (hcParaStyles cfg))
    isZero l = T.dropWhile (== '-') l `elem` ["0em", "0pt"]
    indentRule name ps
      | name == "body" = not (isZero (hpsIndent ps) && isZero (hpsFirstLineIndent ps))
      | otherwise = (hpsIndent ps, hpsFirstLineIndent ps) /= bodyIndent
    paraRules name ps =
      let sel = if name == "body" then "p" else "p.ps-" <> name
       in ["p.ps-" <> name <> " { font-family: " <> fontStack role <> "; }" | name /= "body", Just role <- [hpsFont ps]]
            <> [sel <> " { margin-block: 0; }" | hpsKeepLines ps]
            <> [ sel <> " { padding-inline-start: " <> hpsIndent ps <> "; text-indent: " <> hpsFirstLineIndent ps <> "; }"
               | indentRule name ps
               ]
            <> [ sel <> " + " <> sel <> " { margin-block-start: " <> tshow (hpsSpaceBetween ps) <> "em; }"
               | hpsSpaceBetween ps > 0
               ]
            <> [rule sel ds | let ds = featureDecls (hpsFeatures ps), not (null ds)]
    families role = case Map.lookup role (hcFonts cfg) of
      Just (ja, la) -> ["\"" <> cssString (family role "latin") <> "\"" | Just _ <- [la]] <> ["\"" <> cssString (family role "ja") <> "\"" | Just _ <- [ja]]
      Nothing -> []
    family role kind = "golem-" <> role <> "-" <> kind
    fontStack role = T.intercalate ", " (families role <> ["serif"])
    {- the rules of the styles of a file: every property they handle, as a
    property left out would keep the value of the rule of style.toml -}
    localRules n l =
      let pre = "body.file-" <> tshow n
          stackOr = maybe "inherit" fontStack
          colorOf cs = case hcsColor cs >>= (`Map.lookup` hcSwatches cfg) of
            Just cmyk -> let (r, g, b) = cmykToRgb cmyk in "rgb(" <> tshow r <> ", " <> tshow g <> ", " <> tshow b <> ")"
            Nothing -> "inherit"
          charRules =
            [ rule
                (pre <> " " <> selectorOf name)
                ( [ "font-family: " <> stackOr (hcsFont cs),
                    "font-weight: " <> (if hcsBold cs then "bold" else "normal"),
                    "font-style: " <> (if hcsItalic cs then "italic" else "normal"),
                    "color: " <> colorOf cs
                  ]
                    <> featureDecls (hcsFeatures cs)
                    -- the background and the padding of inline code (golem-driver ADR 0029)
                    <> ( if hcsCode cs
                           then
                             [ "background-color: " <> maybe "transparent" rgbOf (hcsBackground cs >>= (`Map.lookup` hcSwatches cfg)),
                               "padding-inline: " <> fromMaybe "0" (hcsPadding cs)
                             ]
                           else []
                       )
                )
            | (name, cs) <- Map.toAscList (hlCharStyles l)
            ]
          paraOf name = if name == "body" then "p:not([class])" else "p.ps-" <> name
          paraSel name = pre <> " " <> paraOf name
          margin ps = if hpsKeepLines ps then "0" else "1em"
          paraRules =
            concat
              [ [ rule
                    (paraSel name)
                    ( [ "font-family: " <> stackOr (hpsFont ps),
                        "margin-block: " <> margin ps,
                        "padding-inline-start: " <> hpsIndent ps,
                        "text-indent: " <> hpsFirstLineIndent ps
                      ]
                        <> featureDecls (hpsFeatures ps)
                    ),
                  rule (paraSel name <> " + " <> paraOf name) ["margin-block-start: " <> (if hpsSpaceBetween ps > 0 then tshow (hpsSpaceBetween ps) <> "em" else margin ps)]
                ]
              | (name, ps) <- Map.toAscList (hlParaStyles l),
                name /= "code"
              ]
          faceDecls f = ["font-family: " <> stackOr (faFont f), "font-size: " <> fromMaybe "inherit" (faSize f)]
          faceRules =
            [rule (pre <> " figcaption") (faceDecls f) | Just f <- [hlCaptionFace l]]
              <> [rule (pre <> " .sidenote") (faceDecls f {faSize = Just (fromMaybe "0.85em" (faSize f))}) | Just f <- [hlSidenoteFace l]]
          -- no indent in list items, after the rules of the paragraph styles of the page
          listRule = [pre <> " li p:not([class]), " <> pre <> " li p[class] { padding-inline-start: 0; text-indent: 0; }" | not (Map.null (hlParaStyles l))]
       in charRules <> paraRules <> faceRules <> listRule
