{- | HTML, XHTML and CSS output (golem-html ADR 0001): one tree of each page,
written in the HTML syntax for the HTML target and in the XHTML syntax for
EPUB (root ADR 0432).
-}
module Golem.Html
  ( HtmlConfig (..),
    HtmlLists (..),
    HtmlCharStyle (..),
    HtmlParaStyle (..),
    HtmlHeadingStyle (..),
    HtmlPhysicalParagraph (..),
    HtmlIndent (..),
    HtmlBox (..),
    defaultAlignDecls,
    HtmlRule (..),
    HtmlFeatures (..),
    noFeatures,
    HtmlLocalStyles (..),
    anonymousStyleNumbers,
    Face (..),
    noFace,
    HtmlCode (..),
    codeTokens,
    XhtmlSite (..),
    renderXhtml,
    renderXhtmlWithPageBreaks,
    renderHtml,
    pageTrees,
    pagePathIn,
    Syntax (..),
    allFigures,
    webSource,
    pagePath,
    escapeXml,
    cmykToRgb,
    indexPage,
    langAttrs,
    titleWithLanguages,
  )
where

import Control.Applicative ((<|>))
import Data.Char (isAsciiUpper)
import Data.List (find, intercalate, mapAccumL, sortOn, zip4)
import Data.List.NonEmpty (NonEmpty)
import Data.List.NonEmpty qualified as NE
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, isNothing)
import Data.Ratio (denominator, numerator)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Assemble
import Golem.Assemble.ListMarkers
import Golem.Assemble.Numbering (formatSeparator, formatTitle, titleSeparator)
import Golem.Bibliography (EntryPart (..))
import Golem.Color qualified as Color
import Golem.Doc.Citation (CitePiece (..), citationPieces)
import Golem.Doc.FigureWidth (FigureWidth (..), parseFigureWidth)
import Golem.Doc.IR
import Golem.Html.Markup (AttrValue (..), Node (..), Syntax (..), plainAttr)
import Golem.Html.Markup qualified as M
import Golem.Length qualified as L
import Golem.Length.Decimal (showRationalDigits)
import Golem.Numerals
import Golem.Numerals.Notation (Notation, notationName, writeNumber)
import Golem.Numerals.Number (renderIRNumber)
import Golem.Syntax.Span
import Golem.Syntax.Text (escapeXml, tshow)
import Golem.Unicode.CharClass (CharClass (..), charClass, charClassIn)
import Golem.Unicode.Grapheme (graphemeClusters)
import Numeric (showHex)
import Skylighting qualified as S
import System.FilePath (dropExtension, makeRelative, splitDirectories, takeDirectory, takeFileName, (<.>), (</>))

data HtmlConfig = HtmlConfig
  { hcTitle :: !Text,
    hcLanguage :: !Text,
    hcVertical :: !Bool,
    -- | The physical base pitch of free composition, independent of paragraph overrides (root ADR 0398).
    hcSeparatorPitch :: !(Maybe L.Sp),
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
    -- | the font and size of the cells of tables by the paragraph style of the cells, table and those the book gives to tables (docs/adr/0262)
    hcTableFaces :: !(Map Text Face),
    -- | whether the captions of tables are below them, [tables] caption-position (docs/adr/0262)
    hcTableCaptionBelow :: !Bool,
    -- | whether the index has its section headings, [index] section-headings (docs/adr/0265)
    hcIndexSectionHeadings :: !Bool,
    hcBibliography :: !(Map Text [EntryPart]), -- key -> formatted entry (golem-doc ADR 0005)
    hcDev :: !Bool,
    -- | [composition.ruby] as CSS ruby-align values (golem-layout ADR 0009)
    hcRubyMonoAlign :: !Text,
    hcRubyGroupAlign :: !Text,
    hcRubyBaseSpacing :: !Text,
    hcRubyReadingStyle :: !(Maybe Text),
    -- | the kinds of forced break the book uses (docs/adr ADR 0017)
    hcBreakKinds :: !(Set BreakKind),
    -- | whether the book uses @no-page-break (docs/adr ADR 0030)
    hcNoBreak :: !Bool,
    -- | the markers of [lists], when the book has it (golem-driver ADR 0013)
    hcLists :: !(Maybe HtmlLists),
    -- | the paragraph style code: pre (golem-driver ADR 0017)
    hcCode :: !HtmlCode,
    -- | the rules before and after the headings of each level (golem-driver ADR 0027)
    hcHeadingRules :: !(Map Int (Maybe HtmlRule, Maybe HtmlRule)),
    -- | the notation of [notes] mark-format: the text of the links of notes (docs/adr/0177)
    hcNoteNotation :: !Notation,
    -- | the notation of [endnotes] mark-format: the text of the links of endnotes (root ADR 0412)
    hcEndnoteNotation :: !Notation,
    {- | whether the site embeds the fonts of hcFonts with @font-face
    (fonts = "embed") or names only generic families (docs/adr/0423)
    -} hcEmbedFonts :: !Bool,
    {- | the license documents of the fonts of hcFonts, which a site that
    embeds the fonts copies to fonts/ beside them (root ADR 0433)
    -} hcFontLicenses :: ![FilePath],
    -- | the generic-family of each role that has one, as CSS writes it (docs/adr/0423)
    hcGenericFamilies :: !(Map Text Text),
    -- | full-width character cells in em, without changing glyph size (root ADR 0380)
    hcCharacterAdvance :: !(Maybe Text),
    {- | the paragraph styles without a name of the book, with the keys of
    @style over a style (root ADR 0467), resolved with style.toml
    -} hcAnonymousStyles :: !(Map StyleRef HtmlParaStyle),
    -- | those of each file with styles of its own, resolved with its styles (root ADR 0467)
    hcLocalAnonymousStyles :: !(Map FileId (Map StyleRef HtmlParaStyle)),
    -- | the font and size of the cells of the tables in a paragraph style without a name (root ADR 0467)
    hcAnonymousTableFaces :: !(Map StyleRef Face),
    -- | Allowed heading paragraph keys (root ADR 0468), global and per file.
    hcHeadingStyles :: !(Map Int HtmlHeadingStyle),
    hcLocalHeadingStyles :: !(Map FileId (Map Int HtmlHeadingStyle))
  }

{- | A rule before or after a paragraph or a heading as CSS (golem-driver
ADR 0027, 0028): the width (none lets the block fill the rest of the
line), the indents at the start and the end, the border (weight, style
and colour) and the spaces before and after it as CSS lengths.
-}
data HtmlRule = HtmlRule
  { hrWidth :: !(Maybe Text),
    hrStartIndent :: !(Maybe Text),
    hrEndIndent :: !(Maybe Text),
    hrBorder :: !Text,
    hrOuter :: !Text,
    hrInner :: !Text
  }
  deriving stock (Eq)

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
    hlGap :: !(Maybe Bool),
    hlMarkerStyle :: !(Maybe Text)
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
    hcsPadding :: !(Maybe Text),
    -- | the element of the position (docs/adr/0269): sup, sub, or Nothing for span
    hcsElement :: !(Maybe Text),
    -- | the declarations of the underline and the strikethrough (docs/adr/0270)
    hcsTextDecoration :: ![Text],
    -- | the characters do not break between them (docs/adr ADR 0272)
    hcsNoBreak :: !Bool,
    hcsSize :: !(Maybe Text)
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
    hfBaselineShift :: !(Maybe Text),
    -- | the OpenType features through based-on, the last value of each tag (docs/adr/0268)
    hfOpenType :: ![(Text, Int)]
  }
  deriving stock (Eq)

noFeatures :: HtmlFeatures
noFeatures = HtmlFeatures Nothing Nothing Nothing Nothing []

-- | Only the paragraph properties applicable to a heading (root ADR 0468).
data HtmlHeadingStyle = HtmlHeadingStyle
  { hhsName :: !Text,
    hhsPitch :: !(Maybe Text),
    hhsAlign :: ![Text],
    hhsFeatures :: !HtmlFeatures,
    hhsFitCharacters :: !(Maybe Int)
  }
  deriving stock (Eq)

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
    hpsFeatures :: !HtmlFeatures,
    -- | the rules before and after (golem-driver ADR 0027)
    hpsRuleBefore :: !(Maybe HtmlRule),
    hpsRuleAfter :: !(Maybe HtmlRule),
    -- | the declarations of the alignment, as 'defaultAlignDecls' for left-justified (docs/adr/0189)
    hpsAlign :: ![Text],
    -- | the grid lines before and after (docs/adr/0189)
    hpsSpaceBefore :: !Int,
    hpsSpaceAfter :: !Int,
    -- | a CSS length (docs/adr/0189)
    hpsEndIndent :: !Text,
    {- | the declarations of the keep options not of their defaults:
    break-after, break-inside, orphans, widows, break-before (docs/adr/0261)
    -} hpsBreaks :: ![Text],
    -- | the box of the style (docs/adr/0271)
    hpsBox :: !(Maybe HtmlBox),
    -- | Resolved absolute lengths in free placement (root ADR 0397).
    hpsPhysical :: !(Maybe HtmlPhysicalParagraph),
    {- | the first-line indent of a style with opening-indent = "half", Nothing
    for any other (root ADR 0469)
    -} hpsOpeningHalf :: !(Maybe HtmlIndent),
    -- | fit-characters, none with drop-lines too (root ADR 0466)
    hpsFitCharacters :: !(Maybe Int)
  }
  deriving stock (Eq)

-- | A first-line indent as style.toml gives it: in em, or absolute in sp (root ADR 0469).
data HtmlIndent = IndentEm !Rational | IndentAbs !L.Sp
  deriving stock (Eq, Show)

{- | Absolute pitch and additional boundary gaps. Legacy styles retain their
integer em spacing, so grid output remains byte-for-byte unchanged.
-}
data HtmlPhysicalParagraph = HtmlPhysicalParagraph
  { hppPitch :: !L.Sp,
    hppBefore :: !L.Sp,
    hppAfter :: !L.Sp,
    hppBetween :: !L.Sp
  }
  deriving stock (Eq)

spaceBefore :: HtmlParaStyle -> L.Sp
spaceBefore ps = maybe (fromIntegral (hpsSpaceBefore ps)) hppBefore (hpsPhysical ps)

spaceAfter :: HtmlParaStyle -> L.Sp
spaceAfter ps = maybe (fromIntegral (hpsSpaceAfter ps)) hppAfter (hpsPhysical ps)

spaceBetween :: HtmlParaStyle -> L.Sp
spaceBetween ps = maybe (fromIntegral (hpsSpaceBetween ps)) hppBetween (hpsPhysical ps)

spaceText :: HtmlParaStyle -> L.Sp -> Text
spaceText ps n = case hpsPhysical ps of
  Nothing -> T.pack (show (L.unSp n)) <> "em"
  Just _ -> L.ptText n <> "pt"

{- | The box of a paragraph style (docs/adr/0271): paragraphs of equal keys
one after the other are in one div.box, of the class of the first; the
declarations of div.box-<name>.
-}
data HtmlBox = HtmlBox
  { hbKey :: !Text,
    hbDecls :: ![Text]
  }
  deriving stock (Eq)

-- | The declarations of left-justified, the default of body (docs/adr/0189).
defaultAlignDecls :: [Text]
defaultAlignDecls = ["text-align: justify", "text-align-last: start"]

{- | The styles a file defines, resolved, where they differ from those of
style.toml (docs/adr ADR 0014): character and paragraph styles by name,
and the faces of figcaption and sidenotes.
-}
data HtmlLocalStyles = HtmlLocalStyles
  { hlCharStyles :: !(Map Text HtmlCharStyle),
    hlParaStyles :: !(Map Text HtmlParaStyle),
    hlCaptionFace :: !(Maybe Face),
    hlSidenoteFace :: !(Maybe Face),
    -- | the faces of the cells of tables that differ from hcTableFaces (docs/adr/0262)
    hlTableFaces :: !(Map Text Face)
  }

data XhtmlSite = XhtmlSite
  { sitePages :: ![(FilePath, Text)],
    siteCss :: !Text,
    siteAssets :: ![(FilePath, FilePath)], -- output path, source path

    -- | the output paths of siteAssets that are license documents of fonts, in order (root ADR 0433)
    siteLicenses :: ![FilePath]
  }

-- | The path of the page of a file without its extension (root ADR 0432).
pageBase :: FileTable -> FileId -> FilePath
pageBase ft fid = dropExtension (fromMaybe "unknown" (lookupPath fid ft))

-- | The path of the page of a file in EPUB, .xhtml.
pagePath :: FileTable -> FileId -> FilePath
pagePath = pagePathIn XhtmlSyntax

-- | The path of the page of a file in a syntax: .html or .xhtml (root ADR 0432).
pagePathIn :: Syntax -> FileTable -> FileId -> FilePath
pagePathIn syntax ft fid = pageBase ft fid <.> T.unpack (M.extensionOf syntax)

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

-- | The existing screen approximation, shared with screen PDF.
cmykToRgb :: (Int, Int, Int, Int) -> (Int, Int, Int)
cmykToRgb = Color.cmykPercentToRgb8

data Ctx = Ctx
  { cCfg :: HtmlConfig,
    cFt :: FileTable,
    cBook :: Book,
    -- | the path of the page without its extension (root ADR 0432)
    cHere :: FilePath,
    -- | the paragraph styles of the page: those of its file over those of style.toml (docs/adr ADR 0014)
    cParaStyles :: Map Text HtmlParaStyle,
    {- | the number of each paragraph style without a name in the book and
    the style as the page resolves it (root ADR 0467)
    -} cAnonymous :: Map StyleRef (Int, Maybe HtmlParaStyle),
    -- | the depth of the list around (0 outside lists; golem-driver ADR 0013)
    cListDepth :: Int,
    -- | the notes of the chapter of the page (golem-driver ADR 0026)
    cNotes :: ChapterNotes,
    -- | the endnotes of the chapter of the page, as its notes (root ADR 0412)
    cEndnotes :: ChapterNotes,
    -- | the id of each entry of each @bibliography (golem-doc ADR 0008)
    cCiteIds :: Map (ListAt, Text) Text,
    -- | the character styles of the page: those of its file over those of style.toml (docs/adr/0269)
    cCharStyles :: Map Text HtmlCharStyle,
    {- | the text is inside a link: a resolved reference in it is its text
    alone (docs/adr/0267)
    -} cInLink :: Bool,
    cPageBreaks :: Map SrcSpan [(Int, Text, Text)]
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

{- | The notes (or the endnotes, root ADR 0412) of each document of a chapter (golem-driver ADR 0026): the
id of a note is its number, or the place of its file in the chapter and
its number when the numbers of the chapter meet.
-}
chapterNotes :: (Document -> [(SrcSpan, Int, [[Inline]])]) -> [Document] -> [(Document, ChapterNotes)]
chapterNotes notesOf docs =
  let home = case reverse docs of
        (Document f _ : _) -> f
        [] -> FileId 0
      numbers d = [n | (_, n, _) <- notesOf d]
      allNumbers = concatMap numbers docs
      meet = length allNumbers /= Set.size (Set.fromList allNumbers)
      keyOf k n = if meet then tshow k <> "-" <> tshow n else tshow n
      keyed = [(f, keyOf k, d) | (k, d@(Document f _)) <- zip [1 :: Int ..] docs]
   in [(d, ChapterNotes home key (if f == home then keyed else [])) | (f, key, d) <- keyed]

-- | The site of EPUB: the pages in the XHTML syntax (root ADR 0432).
renderXhtml :: HtmlConfig -> FileTable -> Book -> XhtmlSite
renderXhtml cfg ft book = renderXhtmlWithPageBreaks cfg ft book Map.empty

-- | EPUB page breaks in body text, indexed by its source span and character offset.
renderXhtmlWithPageBreaks :: HtmlConfig -> FileTable -> Book -> Map SrcSpan [(Int, Text, Text)] -> XhtmlSite
renderXhtmlWithPageBreaks = renderSite XhtmlSyntax

-- | The site of the HTML target: the pages in the HTML syntax, without page breaks (root ADR 0432).
renderHtml :: HtmlConfig -> FileTable -> Book -> XhtmlSite
renderHtml cfg ft book = renderSite HtmlSyntax cfg ft book Map.empty

-- | The site of the pages of 'pageTrees' written in a syntax (root ADR 0432).
renderSite :: Syntax -> HtmlConfig -> FileTable -> Book -> Map SrcSpan [(Int, Text, Text)] -> XhtmlSite
renderSite syntax cfg ft book pageBreaks =
  XhtmlSite
    { sitePages = [(pagePathIn syntax ft fid, M.writeDocument syntax tree) | (fid, tree) <- pageTrees cfg ft book pageBreaks],
      siteCss = css cfg book,
      siteAssets =
        sortOn fst
          $ Map.toList
          $ Map.fromList
          $ [(T.unpack (webOutput f), T.unpack (webSource f)) | Document _ bs <- bookDocs book, Block _ _ _ (FigureBlock f) <- allFigures bs]
            -- the fonts only when the site embeds them (docs/adr/0423)
            <> [(fontOut p, p) | hcEmbedFonts cfg, (ja, la) <- Map.elems (hcFonts cfg), Just p <- [ja, la]]
            -- and their license documents beside them (root ADR 0433)
            <> [(fontOut p, p) | hcEmbedFonts cfg, p <- hcFontLicenses cfg],
      siteLicenses = Set.toAscList (Set.fromList [fontOut p | hcEmbedFonts cfg, p <- hcFontLicenses cfg])
    }

{- | The tree of the page of each document, after its doctype: the same
for HTML and EPUB, which write it in their syntaxes (root ADR 0432).
-}
pageTrees :: HtmlConfig -> FileTable -> Book -> Map SrcSpan [(Int, Text, Text)] -> [(FileId, [Node])]
pageTrees cfg ft book pageBreaks =
  [ (fid, page cfg ft book pageBreaks notes endnotes d)
  | chapter <- bookChapters book,
    ((d@(Document fid _), notes), (_, endnotes)) <- zip (chapterNotes documentNotes chapter) (chapterNotes documentEndnotes chapter)
  ]

-- | The file that HTML and EPUB copy for a figure: its @web@ image, or the figure itself.
webSource :: Figure -> Text
webSource f = fromMaybe (figSource f) (figWeb f)

{- | Where HTML and EPUB put that file: its own path, or for an image a
plugin made, images/golem-plugin/<SHA-256>.<extension> (docs/adr/0123).
-}
webOutput :: Figure -> Text
webOutput f = fromMaybe (webSource f) (pluginImageOutput (webSource f))

fontOut :: FilePath -> FilePath
fontOut p = "fonts" </> takeFileName p

-- | The @figure blocks, also those inside lists, in the order of the document.
allFigures :: [Block] -> [Block]
allFigures = concatMap go
  where
    go b@(Block _ _ _ body) = case body of
      FigureBlock _ -> [b]
      BulletList items -> allFigures (concatMap itemBlocks items)
      OrderedList items -> allFigures (concatMap itemBlocks items)
      DefList gs -> allFigures (concat (concatMap dgDefs gs))
      _ -> []

relLink :: FilePath -> FilePath -> Text
relLink from to =
  let depth = length (splitDirectories (takeDirectory from)) - (if takeDirectory from == "." then 1 else 0)
   in T.pack (concat (replicate depth "../") <> makeRelative "." to)

el :: Text -> [(Text, Text)] -> [Node] -> Node
el = M.element

textOf :: Text -> Node
textOf = M.text

nl :: Node
nl = M.newline

-- | The attributes added at the end of the first start tag of nodes.
addAttrs :: [(Text, Text)] -> [Node] -> [Node]
addAttrs extra = \case
  Element n as cs : rest -> Element n (as <> [(k, Plain v) | (k, v) <- extra]) cs : rest
  x : rest -> x : addAttrs extra rest
  [] -> []

-- | The value of an attribute of the first start tag of nodes changed.
mapFirstAttr :: Text -> (Text -> Text) -> [Node] -> [Node]
mapFirstAttr name f = \case
  Element n as cs : rest -> Element n [(k, if k == name then Plain (f (M.attrValue XhtmlSyntax v)) else v) | (k, v) <- as] cs : rest
  x : rest -> x : mapFirstAttr name f rest
  [] -> []

-- | Whether nodes write no text.
writesNothing :: [Node] -> Bool
writesNothing = T.null . M.writeNodes XhtmlSyntax

page :: HtmlConfig -> FileTable -> Book -> Map SrcSpan [(Int, Text, Text)] -> ChapterNotes -> ChapterNotes -> Document -> [Node]
page cfg ft book pageBreaks notes endnotes (Document fid bs) =
  let here = pageBase ft fid
      local = Map.lookup fid (hcLocalStyles cfg)
      anonymous = Map.union (Map.findWithDefault Map.empty fid (hcLocalAnonymousStyles cfg)) (hcAnonymousStyles cfg)
      numbered = Map.fromList [(r, (n, Map.lookup r anonymous)) | (r, n) <- Map.toList (anonymousStyleNumbers book)]
      c = Ctx cfg ft book here (maybe id (Map.union . hlParaStyles) local (hcParaStyles cfg)) numbered 0 notes endnotes (citeIds book) (maybe id (Map.union . hlCharStyles) local (hcCharStyles cfg)) False pageBreaks
      -- a page with styles of its own has the class of its position (docs/adr ADR 0014)
      classes = ["vertical" | hcVertical cfg] <> ["file-" <> tshow n | Just _ <- [local], (n, Document fid' _) <- zip [1 :: Int ..] (bookDocs book), fid' == fid]
      body = topBlocks c bs <> notesSection c <> endnotesSection c
      title = case [hiTitle h | Block sp _ _ (Heading 1 _ _) <- bs, Just h <- [Map.lookup sp (bookHeadings book)]] of
        (t : _) -> T.concat (map plain t)
        [] -> hcTitle cfg
   in [ el
          "html"
          ([("xmlns", "http://www.w3.org/1999/xhtml"), ("xmlns:epub", "http://www.idpf.org/2007/ops")] <> langPairs (hcLanguage cfg))
          [ nl,
            el "head" [] [nl, el "meta" [("charset", "UTF-8")] [], nl, el "title" [] [textOf title], nl, el "link" [("rel", "stylesheet"), ("type", "text/css"), ("href", relLink here "style.css")] [], nl],
            nl,
            el "body" [("class", T.unwords classes) | not (null classes)] (nl : body),
            nl
          ],
        nl
      ]

plain :: InlineF r -> Text
plain = inlineText

idAttr :: Maybe Text -> [(Text, Text)]
idAttr = maybe [] (\l -> [("id", l)])

-- | The attributes of a language in the tree: lang and xml:lang, which HTML leaves out (docs/adr ADR 0187, root ADR 0432).
langPairs :: Text -> [(Text, Text)]
langPairs l = [("lang", l), ("xml:lang", l)]

-- | The attributes of a language as XHTML writes them: lang and xml:lang (docs/adr ADR 0187).
langAttrs :: Text -> Text
langAttrs l = T.concat [" " <> k <> "=\"" <> escapeXml v <> "\"" | (k, v) <- langPairs l]

{- | A title as escaped XHTML text, for the navigation document of EPUB:
the language spans kept as spans with lang and xml:lang, every other
inline its text (docs/adr ADR 0187).
-}
titleWithLanguages :: [InlineF r] -> Text
titleWithLanguages = M.writeNodes XhtmlSyntax . titleNodes

-- | The nodes of 'titleWithLanguages'.
titleNodes :: [InlineF r] -> [Node]
titleNodes = concatMap one
  where
    one :: InlineF r -> [Node]
    one = \case
      Lang _ l xs -> [el "span" (langPairs l) (titleNodes xs)]
      Ruby _ _ segs -> concat [titleNodes b | RubySegment b _ <- segs]
      Kenten _ _ xs -> titleNodes xs
      Color _ _ xs -> titleNodes xs
      CharStyle _ _ xs -> titleNodes xs
      Link _ _ xs -> titleNodes xs
      Resolved _ _ _ xs -> titleNodes xs
      x -> [textOf (inlineText x)]

{- | The blocks at the top of a document: the block after forced breaks
carries the kind of the last of them on its outermost element; a break
at the end writes nothing, and a column break nothing (docs/adr ADR 0017).
The block after a no-break carries avoid; need-lines and page-lines write
nothing (docs/adr ADR 0030). Blank lines are a div of a br for each line
between two blocks, and nothing before the first block, after a break or
after the last block (docs/adr ADR 0046).
-}
topBlocks :: Ctx -> [Block] -> [Node]
topBlocks c = go Nothing Nothing 0 False
  where
    -- These boundaries are semantic, so inline margins take precedence over
    -- global and file-local paragraph rules, including their physical spacing.
    displayed (Block _ _ _ (BlankLines _)) = False
    displayed (Block _ _ _ (PageControl _)) = False
    displayed _ = True
    nextSeparator rest = case filter displayed rest of
      next : _ -> isJust (separatorSpace next)
      _ -> False
    -- blank lines are written before the next block unless a break or the end
    -- comes first; the block before them keeps no margin on their side, so the
    -- default margin of a paragraph is not added to them (root ADR 0398)
    blankFollows rest = case break displayed rest of
      (_, Block _ _ _ (ForcedBreak _) : _) -> False
      (hidden, _ : _) -> sum [toInteger n | Block _ _ _ (BlankLines n) <- hidden] > 0
      _ -> False
    styledBoundary before after html = case ["margin-block-start:0" | before] <> ["margin-block-end:0" | after] of
      [] -> html
      declarations -> addAttrs [("style", T.intercalate ";" declarations)] html
    render before after b@(Block _ _ _ (Paragraph _ _)) = styledBoundary before after (block c b)
    render _ _ b = block c b
    -- the break pending, and the blank lines pending after a block (Nothing before one)
    go _ _ _ _ [] = []
    go _ _ _ _ (Block _ _ _ (ForcedBreak k) : rest) = go (breakName k) Nothing 0 False rest
    go _ blanks after previous (Block _ _ _ (PageControl control) : rest) | keepsPageBreak control = go (Just "avoid") blanks after previous rest
    go pending blanks after previous (Block _ _ _ (PageControl _) : rest) = go pending blanks after previous rest
    go pending blanks after previous (Block _ _ _ (BlankLines n) : rest) = go pending ((+ toInteger n) <$> blanks) after previous rest
    -- the paragraphs of one box in its div (docs/adr/0271)
    go pending blanks after previous (b : rest)
      | Just (name, key) <- boxOf b =
          let (more, rest') = span (\x -> fmap snd (boxOf x) == Just key && not (startsPage x)) rest
              lastIndex = length more
              followingSeparator = nextSeparator rest' || blankFollows rest'
              blanksBefore = max 0 (fromMaybe 0 blanks - after)
              start = previous || blanksBefore > 0
           in blankLines blanksBefore <> withBreak pending (styledBoundary start followingSeparator [el "div" [("class", "box box-" <> name <> anonymousClass b)] (nl : concat [render (start && i == 0) (followingSeparator && i == lastIndex) x | (i, x) <- zip [0 ..] (b : more)]), nl]) <> go Nothing (Just 0) 0 False rest'
      | Just (before, after') <- separatorSpace b =
          let explicit = fromMaybe 0 blanks
              extra = if not previous && explicit > max after before then explicit - after else 0
              marginBefore
                | previous = max explicit (max after before)
                | extra > 0 = 0
                | otherwise = before
              marginAfter = if nextSeparator rest then 0 else after'
              html =
                mapFirstAttr
                  "style"
                  ( T.replace ("margin-block-end:" <> tshow after' <> "lh") ("margin-block-end:" <> tshow marginAfter <> "lh")
                      . T.replace ("margin-block-start:" <> tshow before <> "lh") ("margin-block-start:" <> tshow marginBefore <> "lh")
                  )
                  (block c b)
           in blankLines extra <> withBreak pending html <> go Nothing (Just 0) after' True rest
      | otherwise =
          let blanksBefore = max 0 (fromMaybe 0 blanks - after)
           in blankLines blanksBefore <> withBreak pending (render (previous || blanksBefore > 0) (nextSeparator rest || blankFollows rest) b) <> go Nothing (Just 0) 0 False rest
    separatorSpace (Block sp _ _ (Separator name)) = case Map.lookup (sp, name) (bookSeparators (cBook c)) of
      Just (SeparatorTextAppearance before after _ _ _) -> Just (toInteger before, toInteger after)
      Just (SeparatorRuleAppearance before after _ _ _ _ _) -> Just (toInteger before, toInteger after)
      Nothing -> Nothing
    separatorSpace _ = Nothing
    styleOf = \case
      Block _ _ _ (Paragraph st _) -> (maybe "body" styleRefName st,) <$> paraStyleOf c st
      _ -> Nothing
    -- the class of the number of a style without a name, on its box too (root ADR 0467)
    anonymousClass = \case
      Block _ _ _ (Paragraph (Just r) _) | Just (n, _) <- Map.lookup r (cAnonymous c) -> " pso-" <> tshow n
      _ -> ""
    boxOf x = styleOf x >>= \(name, ps) -> (\hb -> (name, hbKey hb)) <$> hpsBox ps
    -- a paragraph of a style with page-break other than any starts a box of its own
    startsPage x = maybe False (any ("break-before:" `T.isPrefixOf`) . hpsBreaks . snd) (styleOf x)
    blankLines n
      | n > 0 = [el "div" [("class", "blank-line")] (replicate (fromInteger n) (el "br" [] [])), nl]
      | otherwise = []
    -- the attribute goes at the end of the first start tag
    withBreak pending html = case pending of
      Nothing -> html
      Just name -> addAttrs [("data-break-before", name)] html

-- | The value of data-break-before; a column break has none.
breakName :: BreakKind -> Maybe Text
breakName = \case
  BreakPage -> Just "page"
  BreakRecto -> Just "recto"
  BreakVerso -> Just "verso"
  BreakColumn -> Nothing

{- | A block. A block with a language has it on its outermost element
(docs/adr ADR 0187).
-}
block :: Ctx -> Block -> [Node]
block c b@(Block _ _ lang _) = maybe id (addAttrs . langPairs) lang (blockHtml c b)

{- | The first character of a paragraph is an opening bracket (root ADR
0469), in the language of its span or of the block, as the PDF judges it
(root ADR 0374).
-}
opensWithBracket :: Maybe Text -> [Inline] -> Bool
opensWithBracket blang is = case firstCharOf Nothing is of
  Just (spanLang, ch) -> charClassIn (spanLang <|> blang) ch == Opening
  Nothing -> False

{- | The first character of inlines, with the language of the span it is
in: inside styles, links, language spans and the bases of ruby, past the
elements without a character (copied from golem-typeset, root ADR 0469).
-}
firstCharOf :: Maybe Text -> [InlineF r] -> Maybe (Maybe Text, Char)
firstCharOf lang = \case
  [] -> Nothing
  x : xs ->
    let inner l ys = firstCharOf l ys <|> firstCharOf lang xs
     in case x of
          Text _ t -> maybe (firstCharOf lang xs) (\(ch, _) -> Just (lang, ch)) (T.uncons t)
          Kenten _ _ ys -> inner lang ys
          Color _ _ ys -> inner lang ys
          CharStyle _ _ ys -> inner lang ys
          Link _ _ ys -> inner lang ys
          Lang _ l ys -> inner (Just l) ys
          Resolved _ _ _ ys -> inner lang ys
          Ruby _ _ segs -> firstCharOf lang (concatMap rsBase segs) <|> firstCharOf lang xs
          IndexMark {} -> firstCharOf lang xs
          ProofComment {} -> firstCharOf lang xs
          ChannelItem {} -> firstCharOf lang xs
          _ -> Nothing

{- | The text-indent of the first line of a paragraph that starts with an
opening bracket (root ADR 0469): max(min(f, 0), f - 0.5em) of the
first-line indent f, computed for em, written with max() of CSS for an
absolute length.
-}
openingTextIndent :: HtmlIndent -> Text
openingTextIndent = \case
  IndentEm r -> let v = max (min r 0) (r - 1 / 2) in if v == 0 then "0" else L.emText v <> "em"
  IndentAbs 0 -> "0"
  IndentAbs sp -> let f = L.ptText sp <> "pt" in "max(min(" <> f <> ", 0em), " <> f <> " - 0.5em)"

{- | The selector of the paragraphs of a style that start with an opening
bracket (root ADR 0469): the selector of the style with data-opening; the
first line of a style that keeps its lines, each of which is a block.
-}
openingSelector :: Text -> HtmlParaStyle -> Text
openingSelector sel ps = sel <> "[data-opening]" <> (if hpsKeepLines ps then " > .line:first-child" else "")

blockHtml :: Ctx -> Block -> [Node]
blockHtml c (Block sp lbl blang body) = case body of
  Paragraph st is ->
    let cls = maybe [] (\r -> [("class", styleClasses c r)]) st
        -- the lines of a paragraph that keeps them, each a span; br is for readers without CSS (docs/adr ADR 0005).
        -- A hard break elsewhere is a br, so that text-indent stays on the first line (docs/adr ADR 0016)
        content
          | keepsLines c st = intercalate [el "br" [] [], nl] [[el "span" [("class", "line")] (inlines c l)] | l <- splitAtLineBreaks is]
          | otherwise = inlines c is
        -- a paragraph of a style with opening-indent = "half" that starts with an opening bracket, outside lists, which have no indent (root ADR 0469)
        opening = [("data-opening", "") | cListDepth c == 0, isJust (paraStyleOf c st >>= hpsOpeningHalf), opensWithBracket blang is]
     in [el "p" (idAttr lbl <> cls <> opening) content, nl] <> sidenotes c blang is
  Heading l _ is ->
    let tag = "h" <> T.pack (show l)
        info = Map.lookup sp (bookHeadings (cBook c))
        anchor = maybe (headingAnchor lbl sp) hiAnchor info
        headingStyle = Map.lookup l (Map.findWithDefault (hcHeadingStyles (cCfg c)) (spanFile sp) (hcLocalHeadingStyles (cCfg c)))
        cls = [("class", "ps-" <> hhsName h) | Just h <- [headingStyle]]
     in [el tag ([("id", anchor)] <> cls) (titledNodes (hcLanguage (cCfg c)) (cBook c) (spanFile sp) (Just l) True (info >>= hiNumberText) (foldMap inlineText is) (inlines c is)), nl]
  BulletList items -> [el "ul" (idAttr lbl <> listClass (NE.length . hlBullets)) (nl : concatMap (item inList Nothing) items), nl]
  OrderedList items ->
    let start = case items of
          (ListItem (Just n) _ : _) -> [("start", T.pack (show n))]
          _ -> []
     in [el "ol" (idAttr lbl <> listClass (NE.length . hlNumbers) <> start) (nl : concat (zipWith (\i it -> item inList (if i > (0 :: Int) then toInteger <$> itemNumber it else Nothing) it) [0 ..] items)), nl]
  DefList gs ->
    [ el
        "dl"
        (idAttr lbl)
        ( nl
            : concat
              [ concat [[el "dt" [] (inlines c t), nl] | t <- ts] <> concat [[el "dd" [] (nl : concatMap (block c) d), nl] | d <- ds]
              | DefGroup ts ds <- gs
              ]
        ),
      nl
    ]
  TableBlock t ->
    let al = tableAligns t
        cls a = case a of
          AlignLeft -> [("class", "align-left")]
          AlignCenter -> [("class", "align-center")]
          AlignRight -> [("class", "align-right")]
          AlignDefault -> []
        row tag cells = [el "tr" [] (zipWith (\a x -> el tag (cls a) (inlines c x)) (al <> repeat AlignDefault) cells), nl]
        -- the paragraph style of the cells, the built-in table without a class (docs/adr/0262)
        styleClass = maybe [] (\r -> [("class", styleClasses c r)]) (tableStyle t)
        -- the caption, the first child whichever side it is on (docs/adr/0262)
        caption = case tableCaption t of
          Just is -> [el "caption" [] (titledNodes (hcLanguage (cCfg c)) (cBook c) (spanFile sp) Nothing True (Map.lookup sp (bookTables (cBook c))) (foldMap inlineText is) (inlines c is)), nl]
          Nothing -> []
        colgroup
          | null (tableWidths t) = []
          | otherwise = [el "colgroup" [] [el "col" (maybe [] (\w' -> [("style", "width: " <> w')]) (columnWidthCss w)) [] | w <- tableWidths t], nl]
     in [el "table" (idAttr lbl <> styleClass) (nl : caption <> colgroup <> [el "thead" [] (nl : row "th" (tableHeader t)), nl, el "tbody" [] (nl : concatMap (row "td") (tableRows t)), nl]), nl] <> sidenotes c blang (fromMaybe [] (tableCaption t) <> concat (tableHeader t) <> concat (concat (tableRows t)))
  CodeBlock code ->
    let co = hcCode (cCfg c)
        lang = codeLang code
        ls = codeLines code
        -- a caption or a file name: a figure (golem-driver ADR 0023)
        wrapped = isJust (codeCaption code) || isJust (codeFile code)
        caption =
          [ el "figcaption" [] (titledNodes (hcLanguage (cCfg c)) (cBook c) (spanFile sp) Nothing False (Map.lookup sp (bookListings (cBook c))) (foldMap inlineText is) (inlines c is))
          | Just is <- [codeCaption code]
          ]
        file = [el "div" [("class", "code-file")] [textOf f] | Just f <- [codeFile code]]
        numbered = fromMaybe (hcoLineNumbers co) (codeNumbers code)
        -- a block with line numbers, highlights, a diff or callouts: a span per line
        perLine = numbered || codeDiff code || any (\l -> clHighlight l || not (null (clCallouts l))) ls
        texts = highlightedLines lang (codeText code)
        line l h =
          let classes = T.unwords (["line"] <> ["hl" | clHighlight l] <> ["add" | clDiff l == Just DiffAdded] <> ["del" | clDiff l == Just DiffRemoved])
              ln = [el "span" [("class", "ln"), ("aria-hidden", "true")] [textOf (maybe "" tshow (clNumber l))] | numbered]
              dm = [el "span" [("class", "dm"), ("aria-hidden", "true")] [textOf (diffMark (clDiff l))] | codeDiff code]
              callouts = concat [[textOf " ", el "span" [("class", "callout")] [textOf (circled n)]] | n <- clCallouts l]
           in [el "span" [("class", classes)] (ln <> dm <> h <> callouts)]
        content
          | perLine = intercalate [nl] (zipWith line ls (if length texts == length ls then texts else map (\l -> [textOf (clText l)]) ls))
          | otherwise = intercalate [nl] texts
        pre = el "pre" (if wrapped then [] else idAttr lbl) [el "code" (maybe [] (\l -> [("class", "sourceCode language-" <> l)]) lang) content]
     in ( if wrapped
            then [el "figure" ([("class", "listing")] <> idAttr lbl) (caption <> file <> [pre]), nl]
            else [pre, nl]
        )
          <> sidenotes c blang (fromMaybe [] (codeCaption code))
  FigureBlock f ->
    let -- a paragraph of the caption with a language is a span of it (docs/adr ADR 0187)
        cap = concat [maybe id (\l x -> [el "span" (langPairs l) x]) pl (inlines c is) | Block _ _ pl (Paragraph _ is) <- figCaption f]
        captioned = titledNodes (hcLanguage (cCfg c)) (cBook c) (spanFile sp) Nothing True (Map.lookup sp (bookFigures (cBook c))) (T.concat [foldMap inlineText is | Block _ _ _ (Paragraph _ is) <- figCaption f]) cap
        -- no figcaption without a number and a caption (docs/adr/0200)
        figcaption = if writesNothing captioned then [] else [el "figcaption" [] captioned, nl]
     in [el "figure" (idAttr lbl) ([nl, el "img" ([("src", relLink (cHere c) (T.unpack (webOutput f))), ("alt", figAlt f)] <> figureWidthStyle (hcVertical (cCfg c)) (figWidth f)) [], nl] <> figcaption), nl]
  ChannelOutput (TocOutput d) -> toc c (Just d)
  ChannelOutput IndexOutput -> index c sp
  ChannelOutput (CustomOutput name _) -> channelList c sp name
  ChannelOutput BibliographyOutput ->
    [ el
        "ol"
        [("class", "bibliography")]
        ( nl
            : concat
              [ [el "li" [("id", citeId c (Just (spanFile sp, sp)) k)] (maybe [textOf k] (concatMap entryPart) (Map.lookup k (hcBibliography (cCfg c)))), nl]
              | (k, _) <- bibliographyAt (cBook c) sp
              ]
        ),
      nl
    ]
  ForcedBreak _ -> []
  PageControl _ -> []
  -- placed by topBlocks (docs/adr ADR 0046)
  BlankLines _ -> []
  Separator name -> case Map.lookup (sp, name) (bookSeparators (cBook c)) of
    Just (SeparatorTextAppearance before after align content charStyle) ->
      [el "div" [("class", "separator separator-text"), ("style", separatorStyle align before after)] [el "span" (maybe [] (\s -> [("class", "cs-" <> s)]) charStyle) [textOf content]], nl]
    Just (SeparatorRuleAppearance before after align len weight color stroke) ->
      [el "div" [("class", "separator separator-rule"), ("style", separatorStyle align before after)] [separatorRuleSvg c sp name len weight color stroke], nl]
    Nothing -> []
  -- a text frame at the place of the command; its position and shape are for the PDF only (root ADR 0438)
  FrameBlock name bs -> [el "aside" [("class", "frame frame-" <> name)] (nl : concatMap (block c) bs), nl]
  where
    separatorStyle align before after = "text-align:" <> align <> ";margin-block-start:" <> tshow before <> "lh;margin-block-end:" <> tshow after <> "lh"
    -- a URL of http or https is a link; another URL is not (golem-doc ADR 0005)
    entryPart = \case
      EntryText t -> [textOf t]
      EntryUrl u
        | any (`T.isPrefixOf` T.toLower u) ["http:", "https:"] -> [el "a" [("class", "cs-url"), ("href", u)] [textOf u]]
        | otherwise -> [el "span" [("class", "cs-url")] [textOf u]]
    -- the lists inside count one deeper; with [lists], the class of the depth (golem-driver ADR 0013)
    depth = cListDepth c + 1
    inList = c {cListDepth = depth}
    listClass count = case hcLists (cCfg c) of
      Just ls -> [("class", "list-" <> tshow (min depth (count ls)))]
      Nothing -> []

-- | An SVG keeps the rule's physical dash, gap and wave parameters in both writing modes.
separatorRuleSvg :: Ctx -> SrcSpan -> Text -> Maybe Integer -> Integer -> Maybe Text -> SeparatorStroke -> Node
separatorRuleSvg c sp name len weight color stroke =
  let vertical = hcVertical (cCfg c)
      pt n = L.ptText (L.Sp n) <> "pt"
      extent = maybe "100%" pt len
      ink = case color >>= (`Map.lookup` hcSwatches (cCfg c)) of
        Just sw -> let (r, g, b) = cmykToRgb sw in "rgb(" <> tshow r <> ", " <> tshow g <> ", " <> tshow b <> ")"
        Nothing -> "currentColor"
      segment pos thick extra =
        let coords = if vertical then [("x1", pos <> "%"), ("y1", "0"), ("x2", pos <> "%"), ("y2", "100%")] else [("x1", "0"), ("y1", pos <> "%"), ("x2", "100%"), ("y2", pos <> "%")]
         in el "line" (coords <> [("stroke", ink), ("stroke-width", pt thick)] <> extra) []
      base = segment "50" weight []
      svgBody = case stroke of
        StrokeSolid -> [base]
        StrokeDashed dash gap -> [segment "50" weight [("stroke-dasharray", pt dash <> " " <> pt gap)]]
        StrokeDotted gap -> [segment "50" weight [("stroke-linecap", "round"), ("stroke-dasharray", "0pt " <> pt gap)]]
        StrokeJapaneseDots gap -> [segment "50" weight [("stroke-linecap", "square"), ("stroke-dasharray", "0pt " <> pt gap)]]
        StrokeMulti ratios ->
          let total = max 1 (sum ratios)
              edges = scanl (+) 0 ratios
           in [segment (tshow ((100 * (a + b)) `div` (2 * total))) (weight * fromIntegral r `div` fromIntegral total) [] | (i, a, b, r) <- zip4 [0 :: Int ..] edges (drop 1 edges) ratios, even i]
        StrokeWavy ->
          let FileId fileNo = spanFile sp
              waveId = "separator-wave-" <> tshow fileNo <> "-" <> tshow (spanStart sp) <> "-" <> name
              (w, h, view, path) =
                if vertical
                  then (pt weight, pt (4 * weight), "0 0 1 4", "M .5 0 Q 0 1 .5 2 T .5 4")
                  else (pt (4 * weight), pt weight, "0 0 4 1", "M 0 .5 Q 1 0 2 .5 T 4 .5")
           in [ el "defs" [] [el "pattern" [("id", waveId), ("patternUnits", "userSpaceOnUse"), ("width", w), ("height", h), ("viewBox", view)] [el "path" [("d", path), ("fill", "none"), ("stroke", ink), ("stroke-width", "0.3")] []]],
                el "rect" [("width", "100%"), ("height", "100%"), ("fill", "url(#" <> waveId <> ")")] []
              ]
   in el "svg" [("class", "separator-rule-svg"), ("xmlns", "http://www.w3.org/2000/svg"), ("aria-hidden", "true"), ("style", "display:inline-block;inline-size:" <> extent <> ";block-size:" <> pt weight <> ";vertical-align:middle;overflow:visible")] svgBody

{- | A numbered title of a file and a level: the title alone without a
number; with one, the format of the level (root ADR 0463), or the number,
in its span when @spanned@, and the separator (golem-html ADR 0002, Golem
ADR 0372) before the title. From the language of the book, the book, the
file, the level, whether the number has its span, the number, the text
of the title and its nodes.
-}
titledNodes :: Text -> Book -> FileId -> Maybe Int -> Bool -> Maybe Text -> Text -> [Node] -> [Node]
titledNodes lang book fid level spanned num titleText title = case num of
  Nothing -> title
  Just n -> case Map.lookup (fid, level) (bookTitleFormats book) of
    -- the format: the number in its span at each {number}, the title at {title} (root ADR 0463)
    Just format -> formatTitle (\t -> [textOf t]) [numberNode n] title (formatSeparator lang separator) format
    Nothing
      | spanned -> [numberNode n, textOf (titleSeparator lang separator n titleText)] <> title
      | otherwise -> textOf (n <> titleSeparator lang separator n titleText) : title
  where
    separator = Map.lookup (fid, level) (bookTitleSeparators book)
    numberNode n = el "span" [("class", "number")] [textOf n]

item :: Ctx -> Maybe Integer -> ListItem -> [Node]
item c value (ListItem _ bs) =
  [ el "li" (maybe [] (\n -> [("value", T.pack (show n))]) value) $ case bs of
      -- a paragraph of a language of its own keeps its element (docs/adr ADR 0187)
      [Block _ _ Nothing (Paragraph Nothing is)] | not (keepsLines c Nothing) -> inlines c is
      _ -> nl : concatMap (block c) bs,
    nl
  ]

-- | Whether the paragraph style keeps the lines of its paragraphs (docs/adr ADR 0005).
keepsLines :: Ctx -> Maybe StyleRef -> Bool
keepsLines c st = maybe False hpsKeepLines (paraStyleOf c st)

{- | The paragraph style of a paragraph on its page: a style without a name
(root ADR 0467) as the page resolves it, another by its name.
-}
paraStyleOf :: Ctx -> Maybe StyleRef -> Maybe HtmlParaStyle
paraStyleOf c = \case
  Just r | Just (_, Just ps) <- Map.lookup r (cAnonymous c) -> Just ps
  st -> Map.lookup (maybe "body" styleRefName st) (cParaStyles c)

{- | The classes of a paragraph style (root ADR 0467): ps-NAME, and pso-N
of the style without a name numbered N.
-}
styleClasses :: Ctx -> StyleRef -> Text
styleClasses c r = "ps-" <> styleRefName r <> maybe "" (\(n, _) -> " pso-" <> tshow n) (Map.lookup r (cAnonymous c))

{- | The paragraph styles without a name of a book numbered from 1 in the
order they first come in it (root ADR 0467): of its paragraphs and of the
cells of its tables, the documents in their order.
-}
anonymousStyleNumbers :: Book -> Map StyleRef Int
anonymousStyleNumbers book = Map.fromList (zip (keyedStyleRefs (concatMap docBlocks (bookDocs book))) [1 ..])

toc :: Ctx -> Maybe Int -> [Node]
toc c depth =
  [ Element
      "nav"
      [plainAttr "epub:type" "toc", plainAttr "class" "toc"]
      [ nl,
        el
          "ol"
          []
          ( nl
              : concat
                [ [ el
                      "li"
                      [("class", "toc-" <> T.pack (show (teLevel e)))]
                      [ Element
                          "a"
                          [("href", linkTo c (teFile e) (teAnchor e))]
                          (titledNodes (hcLanguage (cCfg c)) (cBook c) (teFile e) (Just (teLevel e)) False (teNumber e) (foldMap inlineText (teTitle e)) (inlines c {cInLink = True, cPageBreaks = Map.empty} (teTitle e)))
                      ],
                    nl
                  ]
                | e <- bookToc (cBook c),
                  maybe True (teLevel e <=) depth
                ]
          ),
        nl
      ],
    nl
  ]

-- | A link to the place of an anchor: the page of the file in the syntax, or the anchor alone on the page itself.
linkTo :: Ctx -> FileId -> Text -> AttrValue
linkTo c fid anchor =
  let target = pageBase (cFt c) fid
   in if target == cHere c then Plain ("#" <> anchor) else PageLink (relLink (cHere c) target) anchor

{- | The index (docs/adr/0265): a heading and a list for each section, or
one list in a book without headings. Each entry links its marks numbered
from 1, a range by the links of its two ends; its references follow, as
in the PDF, not linked.
-}
index :: Ctx -> SrcSpan -> [Node]
index c sp =
  [ el
      "section"
      [("class", "index")]
      ( nl
          : if hcIndexSectionHeadings (cCfg c)
            then concat [[el "p" [("class", "index-heading")] [textOf (isHeading s)], nl] <> list (isGroups s) | s <- sections]
            else list (concatMap isGroups sections)
      ),
    nl
  ]
  where
    sections = indexAt (cBook c) sp
    list gs = [el "ul" [] (nl : concatMap entry gs), nl]
    entry g =
      [ el
          "li"
          []
          ( [textOf (T.intercalate " / " (igTerms g))]
              <> (if null (igLocators g) then [] else textOf " " : intercalate [textOf ", "] (snd (mapAccumL link 1 (igLocators g))))
              <> [textOf (indexReferences (not (null (igLocators g))) (igSee g))]
          ),
        nl
      ]
    anchor i (fid, loc) = [Element "a" [("href", linkTo c fid (spanAnchor loc))] [textOf (T.pack (show (i :: Int)))]]
    link i = \case
      AtMark m -> (i + 1, anchor i m)
      Between a b -> (i + 2, anchor i a <> [textOf "\x2013"] <> anchor (i + 1) b)

{- | The ids of the entries of the bibliographies, unique in the book
(golem-doc ADR 0008): the lists in document order and their entries in
the order of their numbers, each taking the first of cite-<key>,
cite-<key>-2, cite-<key>-3, ... not taken yet.
-}
citeIds :: Book -> Map (ListAt, Text) Text
citeIds book = fst (foldl assign (Map.empty, Set.empty) entries)
  where
    entries = [(at, k) | (Just at, cites) <- bookBibliographies book, (k, _) <- sortOn snd cites]
    assign (ids, used) (at, k) =
      let candidates = ("cite-" <> k) : ["cite-" <> k <> "-" <> tshow i | i <- [2 :: Int ..]]
          chosen = fromMaybe ("cite-" <> k) (find (`Set.notMember` used) candidates)
       in (Map.insert (at, k) chosen ids, Set.insert chosen used)

{- | The file of the bibliography list a cite mark belongs to (golem-html
ADR 0003, golem-doc ADR 0008); nothing when the book has no
@bibliography.
-}
bibliographyHome :: Book -> SrcSpan -> Maybe FileId
bibliographyHome book sp = fst <$> (fst =<< Map.lookup (spanFile sp, sp) (bookCiteMarks book))

-- | The id of the entry of a key in a list; cite-<key> without a list.
citeId :: Ctx -> Maybe ListAt -> Text -> Text
citeId c at k = fromMaybe ("cite-" <> k) (at >>= \a -> Map.lookup (a, k) (cCiteIds c))

{- | The list of a channel of a plugin (golem-doc ADR 0007): its entries
in a ul, each with links to where its items are when the channel shows
them.
-}
channelList :: Ctx -> SrcSpan -> Text -> [Node]
channelList c sp name =
  [ el
      "section"
      [("class", "channel"), ("data-channel", name)]
      [ nl,
        el
          "ul"
          []
          ( nl
              : concat
                [ [ el
                      "li"
                      []
                      ( inlines c (ceBody e)
                          <> ( if locators
                                 then textOf " " : intercalate [textOf ", "] [[Element "a" [("href", linkTo c fid (channelAnchor name lsp))] [textOf (tshow i)]] | (i, (fid, lsp)) <- zip [1 :: Int ..] (ceLocations e)]
                                 else []
                             )
                      ),
                    nl
                  ]
                | e <- channelAt (cBook c) sp
                ]
          ),
        nl
      ],
    nl
  ]
  where
    locators = maybe False channelLocators (Map.lookup name (bookChannelDecls (cBook c)))

-- | The id at an item of a channel: c-<channel>-<file>-<start> (golem-doc ADR 0007).
channelAnchor :: Text -> SrcSpan -> Text
channelAnchor name (SrcSpan (FileId f) s _) = "c-" <> name <> "-" <> T.pack (show f) <> "-" <> T.pack (show s)

-- | The empty span of the label of a note, the place its references go (root ADR 0422).
labelSpan :: Text -> Node
labelSpan l = el "span" [("id", l)] []

spanAnchor :: SrcSpan -> Text
spanAnchor (SrcSpan (FileId f) s _) = "i-" <> T.pack (show f) <> "-" <> T.pack (show s)

inlines :: Ctx -> [InlineF r] -> [Node]
inlines c = concatMap (inline c)

inline :: Ctx -> InlineF r -> [Node]
inline c value = anchor <> inlineBody c value
  where
    anchor = maybe [] (\sp -> pageText (Map.findWithDefault [] sp (cPageBreaks c)) "") atom
    atom = case value of
      Tcy sp _ -> Just sp
      Number sp _ _ -> Just sp
      Ref sp _ _ -> Just sp
      Cite sp _ -> Just sp
      ChannelItem sp _ -> Just sp
      _ -> Nothing

inlineBody :: Ctx -> InlineF r -> [Node]
inlineBody c = \case
  Text sp t -> pageTextWith (textHtml c) (Map.findWithDefault [] sp (cPageBreaks c)) t
  Ruby _ _ segs
    | any (\seg -> rsOptions seg /= defaultRubyOptions || isJust (rsOtherReading seg)) segs ->
        concatMap extendedRuby segs
    where
      extendedRuby seg =
        let options = rsOptions seg
            monoClass = [("class", "mono") | length segs >= 2 || T.length (foldMap inlineText (rsBase seg)) == 1]
            alignment = case roAlign options of
              Just "1-2-1" -> "ruby-align:space-around;"
              Just "0-1-0" -> "ruby-align:space-between;"
              Just value -> "ruby-align:" <> value <> ";"
              Nothing -> ""
            readingSize = case roSize options of
              Just (RubySizeAbsolute size) -> [("style", "font-size:" <> L.ptText size <> "pt;")]
              Just (RubySizeRelative size) -> [("style", "font-size:" <> L.emText size <> "em;")]
              Nothing -> []
            readingHtml side readingText marks = [case mark of Nothing -> textOf (T.singleton ch); Just shape -> el "span" [("style", "text-emphasis-position:" <> (if side == "under" then "under left" else "over right") <> ";"), ("class", "kenten kenten-" <> shape)] [textOf (T.singleton ch)] | (ch, mark) <- zip (T.unpack (fromMaybe "" readingText)) (marks <> repeat Nothing)]
            wrap side baseNodes readingText marks = [el "ruby" (monoClass <> [("style", "ruby-position:" <> side <> ";" <> alignment)]) (baseNodes <> [el "rp" [] [textOf "（"], el "rt" readingSize (readingHtml side readingText marks), el "rp" [] [textOf "）"]])]
            base = inlines c (rsBase seg)
         in case roSide options of
              RubyBefore -> wrap "over" base (rsReading seg) (roReadingKenten options)
              RubyAfter -> wrap "under" base (rsReading seg) (roReadingKenten options)
              RubyBoth -> wrap "under" (wrap "over" base (rsReading seg) (roReadingKenten options)) (rsOtherReading seg) (roOtherKenten options)
  Ruby _ _ segs ->
    -- several segments, or one base character, are mono ruby (golem-layout ADR 0009)
    [ el
        "ruby"
        [("class", "mono") | length segs >= 2 || T.length (T.concat [foldMap inlineText b | RubySegment b _ <- segs]) == 1]
        (concat [inlines c b <> [el "rp" [] [textOf "（"], el "rt" [] (maybe [] (\r' -> [textOf r']) r), el "rp" [] [textOf "）"]] | RubySegment b r <- segs])
    ]
  -- the shape of the IR; none (from a plugin) is sesame (golem-driver ADR 0019)
  Kenten _ sh xs ->
    if any containsRuby xs
      then concatMap emphasized xs
      else [el "span" [("class", "kenten kenten-" <> fromMaybe "sesame" sh)] (inlines c xs)]
    where
      containsRuby = \case
        Ruby {} -> True
        Color _ _ ys -> any containsRuby ys
        CharStyle _ _ ys -> any containsRuby ys
        Link _ _ ys -> any containsRuby ys
        Lang _ _ ys -> any containsRuby ys
        Resolved _ _ _ ys -> any containsRuby ys
        _ -> False
      emphasized (Ruby sp unit segs) = inline c (Ruby sp unit (map markSegment segs))
      emphasized (Color sp name ys) = inline c (Color sp name [Kenten sp sh ys])
      emphasized (CharStyle sp name ys) = inline c (CharStyle sp name [Kenten sp sh ys])
      emphasized (Link sp target ys) = inline c (Link sp target [Kenten sp sh ys])
      emphasized (Lang sp lang ys) = inline c (Lang sp lang [Kenten sp sh ys])
      emphasized (Resolved sp kind label ys) = inline c (Resolved sp kind label [Kenten sp sh ys])
      emphasized x = [el "span" [("class", "kenten kenten-" <> fromMaybe "sesame" sh)] (inline c x)]
      markSegment seg =
        let opts = rsOptions seg
            marks reading previous = take (maybe 0 T.length reading) (map (Just . fromMaybe (fromMaybe "sesame" sh)) (previous <> repeat Nothing))
         in seg {rsOptions = opts {roReadingKenten = marks (rsReading seg) (roReadingKenten opts), roOtherKenten = marks (rsOtherReading seg) (roOtherKenten opts)}}
  Color _ s xs -> [el "span" [("class", "swatch-" <> s)] (inlines c xs)]
  -- the built-in character styles keep their elements (docs/adr ADR 0005)
  CharStyle _ "strong" xs -> [el "strong" [] (inlines (styled "strong") xs)]
  CharStyle _ "bold" xs -> [el "b" [] (inlines (styled "bold") xs)]
  CharStyle _ "italic" xs -> [el "i" [] (inlines (styled "italic") xs)]
  CharStyle _ "code" xs -> [el "code" [] (inlines c {cCfg = (cCfg c) {hcCharacterAdvance = Nothing}} xs)]
  -- superscript and subscript are sup and sub; the built-in ones without a class (docs/adr/0269)
  CharStyle _ s xs
    | Just e <- Map.lookup s (cCharStyles c) >>= hcsElement ->
        [el e [("class", "cs-" <> s) | s `notElem` ["superscript", "subscript"]] (inlines (styled s) xs)]
  CharStyle _ s xs -> [el "span" [("class", "cs-" <> s)] (inlines (styled s) xs)]
  Tcy _ t -> [el "span" [("class", "tcy")] [textOf t]]
  Upright _ t -> [el "span" [("class", "upright")] [textOf t]]
  Warichu _ "" -> []
  Warichu _ t ->
    let units = graphemeClusters t
        (first, second) = splitAt (length units `div` 2) units
        row xs = el "span" [("class", "warichu-line")] [el "span" [("class", "warichu-cell")] [textOf u] | u <- xs]
     in [el "span" [("class", "warichu")] [row first, row second]]
  Number _ q st
    | denominator q /= 1 ->
        let value = renderIRNumber q
         in if hcVertical (cCfg c) && (st == Just StyleTcy || (isNothing st && hcNumberDefault (cCfg c) == "tcy"))
              then [el "span" [("class", "tcy")] [textOf value]]
              else [textOf value]
    | not (hcVertical (cCfg c)) -> [textOf (renderIRNumber q)]
    | otherwise -> case fromMaybe (verticalStyleOf (verticalNumbersNamed (hcNumberDefault (cCfg c))) (numerator q)) st of
        StyleKanji -> [textOf (kanji (numerator q))]
        StyleKanjiDigits -> [textOf (kanjiDigits (numerator q))]
        StyleTcy -> [el "span" [("class", "tcy")] [textOf (renderIRNumber q)]]
  Ref _ _ l -> case Map.lookup l (bookLabels (cBook c)) of
    -- a note has no title: its number, as [ref-number] gives it (root ADR 0422)
    Just t@LabelTarget {ltNote = Just _} -> [Element "a" [("href", linkTo c (ltFile t) (ltAnchor t))] (inlines c {cPageBreaks = Map.empty} (maybe [] pure (ltNumber t)))]
    Just t -> [Element "a" [("href", linkTo c (ltFile t) (ltAnchor t))] (inlines c {cPageBreaks = Map.empty} (ltTitle t))]
    Nothing -> []
  Deferred {} -> []
  -- a labelled note: an empty span with its label as the id before the mark, where its references go (root ADR 0422)
  Note sp n (Just l) b -> labelSpan l : inline c (Note sp n Nothing b)
  Sidenote sp n (Just l) b -> labelSpan l : inline c (Sidenote sp n Nothing b)
  Endnote sp n (Just l) b -> labelSpan l : inline c (Endnote sp n Nothing b)
  Note _ n _ _ ->
    let key = cnKey (cNotes c) n
     in [Element "a" [plainAttr "epub:type" "noteref", plainAttr "class" "noteref", ("href", linkTo c (cnHome (cNotes c)) ("note-" <> key)), plainAttr "id" ("noteref-" <> key)] [textOf (noteText c n)]]
  Sidenote _ n _ _ -> [el "sup" [("class", "sidenote-ref")] [textOf (tshow n)]]
  -- a reference to an endnote in the list at the end of its chapter (root ADR 0412)
  Endnote _ n _ _ ->
    let key = cnKey (cEndnotes c) n
     in [Element "a" [plainAttr "epub:type" "noteref", plainAttr "class" "endnoteref", ("href", linkTo c (cnHome (cEndnotes c)) ("endnote-" <> key)), plainAttr "id" ("endnoteref-" <> key)] [textOf (endnoteText c n)]]
  IndexMark sp _ -> [el "span" [("id", spanAnchor sp)] []]
  -- an empty span with an id when the channel shows where its items are (golem-doc ADR 0007)
  ChannelItem sp ci
    | maybe False channelLocators (Map.lookup (ciChannel ci) (bookChannelDecls (cBook c))) -> [el "span" [("id", channelAnchor (ciChannel ci) sp)] []]
    | otherwise -> []
  -- the mark in a span, each number a link to its entry in the file of its bibliography;
  -- no link without one (golem-html ADR 0003, docs/adr/0266)
  Cite sp is -> case traverse (\i -> (,) i . Just <$> citeNumber (cBook c) sp (citKey i)) is of
    Just ns ->
      let at = fst =<< Map.lookup (spanFile sp, sp) (bookCiteMarks (cBook c))
          piece = \case
            CiteText t -> [textOf t]
            -- U+00A0: the browser does not break between the label of a page and its value (docs/adr/0277)
            CiteLocator l v -> [textOf (l <> "\xA0" <> v)]
            CiteNumber k n -> case bibliographyHome (cBook c) sp of
              Just home -> [Element "a" [("href", linkTo c home (citeId c at k))] [textOf (tshow n)]]
              Nothing -> [textOf (tshow n)]
       in [el "span" [("class", "cite")] (concatMap piece (citationPieces ns))]
    Nothing -> []
  ProofComment _ t -> [el "span" [("class", "proof")] [textOf t] | hcDev (cCfg c)]
  LineBreak _ -> [el "br" [] []]
  -- an empty span with a margin; word joiners keep the line from breaking around it (docs/adr ADR 0019)
  Aki _ a -> [CharRef 0x2060, el "span" [("class", "aki"), ("style", "margin-inline-start: " <> akiLength a)] [], CharRef 0x2060]
  -- the URL as written: an IRI is a valid href (docs/adr ADR 0182)
  Link _ u xs -> [el "a" [("href", u)] (inlines c {cInLink = True} xs)]
  -- the tag as written, even the language of the book (docs/adr ADR 0187)
  Lang _ l xs -> [el "span" (langPairs l) (inlines c xs)]
  {- the text the reference resolved to (docs/adr/0215), a link to the place
  of its label as [ref-page] has; inside a link its text alone (docs/adr/0267) -}
  Resolved _ _ l xs
    | not (cInLink c),
      Just t <- Map.lookup l (bookLabels (cBook c)) ->
        [Element "a" [("href", linkTo c (ltFile t) (ltAnchor t))] (inlines c {cInLink = True} xs)]
  Resolved _ _ _ xs -> inlines c xs
  where
    styled name
      | maybe False hcsCode (Map.lookup name (cCharStyles c)) = c {cCfg = (cCfg c) {hcCharacterAdvance = Nothing}}
      | otherwise = c

{- | The nodes of a run of text: with a character advance, each grapheme
cluster that is not Western is wrapped so that it takes the advance (root ADR
0380).
-}
textHtml :: Ctx -> Text -> [Node]
textHtml c t = case hcCharacterAdvance (cCfg c) of
  Just _ -> [if maybe False (\(ch, _) -> charClass ch /= Western && ch /= ' ' && ch /= '\n' && ch /= '\t') (T.uncons u) then el "span" [("class", "character-advance")] [textOf u] else textOf u | u <- graphemeClusters t]
  Nothing -> [textOf t]

-- | Insert page-break spans without changing the surrounding text or its styles.
pageText :: [(Int, Text, Text)] -> Text -> [Node]
pageText = pageTextWith (pure . textOf)

{- | 'pageText' with the way each run of text between the page breaks becomes
nodes.
-}
pageTextWith :: (Text -> [Node]) -> [(Int, Text, Text)] -> Text -> [Node]
pageTextWith html breaks text = go 0 (sortOn (\(offset, _, _) -> offset) breaks)
  where
    go start [] = html (T.drop start text)
    go start ((offset, ident, label) : rest) =
      html (T.take (offset - start) (T.drop start text))
        <> [Element "span" [plainAttr "epub:type" "pagebreak", plainAttr "role" "doc-pagebreak", plainAttr "id" ident, plainAttr "aria-label" label] []]
        <> go offset rest

{- | The CSS length of an aki: zw in em, an absolute amount in pt, at most
four decimals (docs/adr ADR 0103).
-}
akiLength :: AkiAmount -> Text
akiLength = \case
  AkiZw r -> L.emText r <> "em"
  AkiAbs x -> L.ptText x <> "pt"

{- | The text of the links of a note, its mark and the way back (docs/adr/0177):
its number in the notation of [notes] mark-format, without the text around it.
-}
noteText :: Ctx -> Int -> Text
noteText c n = fromMaybe (tshow n) (writeNumber (hcNoteNotation (cCfg c)) (toInteger n))

-- | The sidenotes of a paragraph after it, in the language of the paragraph (docs/adr ADR 0187).
sidenotes :: Ctx -> Maybe Text -> [Inline] -> [Node]
sidenotes c lang is = concat [[el "aside" ([("class", "sidenote")] <> maybe [] langPairs (at <|> lang)) (el "span" [("class", "number")] [textOf (tshow n)] : concatMap (inlines c) (noteParagraphs body)), nl] | (at, _, n, body) <- inlineSidenotes is]

-- | The text of the links of an endnote, in the notation of [endnotes] mark-format (root ADR 0412).
endnoteText :: Ctx -> Int -> Text
endnoteText c n = fromMaybe (tshow n) (writeNumber (hcEndnoteNotation (cCfg c)) (toInteger n))

{- | The endnotes of the chapter at the end of its last page, after its
notes, as they are written (root ADR 0412).
-}
endnotesSection :: Ctx -> [Node]
endnotesSection c = noteList c "endnotes" (endnotesTitle (hcLanguage (cCfg c))) "endnote" "endnote-" "endnoteref-" endnoteText [(f, key, n, xs) | (f, key, d) <- cnList (cEndnotes c), (_, n, xs) <- documentEndnotes d]

{- | The notes of the chapter at the end of its last page, after a title
(golem-driver ADR 0026); each links back to its mark, on whichever page.
-}
notesSection :: Ctx -> [Node]
notesSection c = noteList c "notes" (notesTitle (hcLanguage (cCfg c))) "footnote" "note-" "noteref-" noteText [(f, key, n, xs) | (f, key, d) <- cnList (cNotes c), (_, n, xs) <- documentNotes d]

{- | A list of notes or endnotes: the section of its class with its title,
an aside of its kind for each, a p for each paragraph, the link back at
the start of the first (docs/adr/0263).
-}
noteList :: Ctx -> Text -> Text -> Text -> Text -> Text -> (Ctx -> Int -> Text) -> [(FileId, Int -> Text, Int, [[Inline]])] -> [Node]
noteList _ _ _ _ _ _ _ [] = []
noteList c cls title kind idPrefix backPrefix mark ns =
  [ el
      "section"
      [("class", cls)]
      ( [nl, el "h2" [] [textOf title], nl]
          <> concat
            [ [ Element
                  "aside"
                  [plainAttr "epub:type" kind, plainAttr "id" (idPrefix <> key n)]
                  [el "p" [] ((if i == (0 :: Int) then [Element "a" [("href", linkTo c f (backPrefix <> key n))] [textOf (mark c n)], textOf " "] else []) <> inlines c is) | (i, is) <- zip [0 ..] ps],
                nl
              ]
            | (f, key, n, ps) <- ns
            ]
      ),
    nl
  ]

{- | Code coloured with skylighting's classes (golem-html ADR 0001), a
list of nodes for each line. An unknown language, or text the highlighter
rejects, stays plain.
-}
highlightedLines :: Maybe Text -> Text -> [[Node]]
highlightedLines lang code = case lang >>= \l -> S.lookupSyntax l S.defaultSyntaxMap of
  Nothing -> escaped
  Just syntax -> case S.tokenize (S.TokenizerConfig S.defaultSyntaxMap False) syntax code of
    Left _ -> escaped
    Right ls -> map (map tok) ls
  where
    escaped = map (pure . textOf) (T.splitOn "\n" code)
    tok (S.NormalTok, t) = textOf t
    tok (ty, t) = el "span" [("class", shortClass ty)] [textOf t]

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
    codesIn (Block _ _ _ body) = case body of
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
        -- auto and auto-digits name the style of the numbers above 99; a counter style cannot change by the number
        | hcVertical cfg -> case verticalNumbersNamed (hcNumberDefault cfg) of
            VerticalFixed StyleKanjiDigits -> extends "cjk-decimal"
            VerticalAuto StyleKanjiDigits -> extends "cjk-decimal"
            VerticalFixed StyleTcy -> extends "decimal"
            _ -> extends "japanese-informal"
        | otherwise -> extends "decimal"
      NsNotation n
        -- the notations of the same rule as a counter style of CSS (docs/adr/0177)
        | Just cssName <- lookup (notationName n) cssStyles -> extends cssName
      _ -> "system: fixed; symbols: " <> T.unwords [str (fromMaybe (tshow n) (formatListNumber st n)) | n <- [1 .. largest k]] <> ";"
    extends s = "system: extends " <> s <> ";"
    cssStyles = [("arabic", "decimal"), ("kanji", "japanese-informal"), ("lower-alpha", "lower-alpha"), ("upper-alpha", "upper-alpha"), ("lower-roman", "lower-roman"), ("upper-roman", "upper-roman")]
    -- the space after a marker: the gap of [lists], or none after punctuation with its own space
    gapAfter m = if fromMaybe (not (endsWithSpacedPunctuation m)) (hlGap ls) then " " else ""
    str t = "\"" <> T.replace "\"" "\\\"" (T.replace "\\" "\\\\" t) <> "\""

-- | Only books using the new inline forms receive their CSS (root ADR 0380).
extendedInlineCss :: Book -> [Text]
extendedInlineCss book
  | any (any hasBlock . docBlocks) (bookDocs book) || or [any hasInline (ceBody e) | (_, _, entries) <- bookChannels book, e <- entries] =
      [ ".upright { text-orientation: upright; }",
        ".warichu { display: inline-flex; flex-direction: column; font-size: 0.5em; line-height: 1; vertical-align: middle; white-space: nowrap; }",
        ".warichu-line { display: block; }",
        ".warichu-cell { display: inline-block; inline-size: 1em; text-align: center; }"
      ]
  | otherwise = []
  where
    hasBlock = hasBody . blockBody
    hasBody = \case
      Paragraph _ xs -> any hasInline xs
      Heading _ attrs xs -> any hasInline xs || maybe False (any hasInline) (haTocTitle attrs)
      BulletList items -> any (any hasBlock . itemBlocks) items
      OrderedList items -> any (any hasBlock . itemBlocks) items
      DefList groups -> any (\g -> any (any hasInline) (dgTerms g) || any (any hasBlock) (dgDefs g)) groups
      FigureBlock f -> any hasBlock (figCaption f)
      TableBlock t -> any (any hasInline) (tableHeader t) || any (any (any hasInline)) (tableRows t) || maybe False (any hasInline) (tableCaption t)
      CodeBlock c -> maybe False (any hasInline) (codeCaption c)
      _ -> False
    hasInline :: InlineF r -> Bool
    hasInline = \case
      Warichu {} -> True
      Upright {} -> True
      Ruby _ _ segments -> any (any hasInline . rsBase) segments
      CharStyle _ _ xs -> any hasInline xs
      Color _ _ xs -> any hasInline xs
      Kenten _ _ xs -> any hasInline xs
      Link _ _ xs -> any hasInline xs
      Lang _ _ xs -> any hasInline xs
      Resolved _ _ _ xs -> any hasInline xs
      Note _ _ _ blocks -> any hasBlock blocks
      Sidenote _ _ _ blocks -> any hasBlock blocks
      ChannelItem _ c -> any hasInline (ciBody c)
      _ -> False

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
    | hcEmbedFonts cfg,
      (role, (ja, la)) <- Map.toAscList (hcFonts cfg),
      (kind, Just p) <- [("latin" :: Text, la), ("ja", ja)]
    ]
      <> [ "body { font-family: " <> fontStack "body" <> "; }",
           "body.vertical { writing-mode: vertical-rl; -epub-writing-mode: vertical-rl; }",
           -- code blocks and code (golem-driver ADR 0017)
           "pre, code { font-family: " <> codeStack <> "; }",
           rule "pre" (["white-space: pre-wrap", "overflow-wrap: anywhere", "tab-size: 2", "hyphens: none", "font-kerning: none"] <> preDecls)
         ]
      <> [".character-advance { display: inline-block; inline-size: " <> advance <> "; }" | Just advance <- [hcCharacterAdvance cfg]]
      <> [ruleText | not (Map.null (bookSeparators book)), ruleText <- [".separator { display: block; block-size: " <> separatorPitch <> "; line-height: " <> separatorPitch <> "; }"]]
      -- strong is always written (docs/adr ADR 0005)
      <> [charRule "strong" cs | Just cs <- [Map.lookup "strong" (hcCharStyles cfg)]]
      <> extendedInlineCss book
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
           -- the paragraphs of a note, as the note was before it had them (docs/adr/0263)
           "section.notes aside p { margin-block: 0; padding-inline-start: 0; text-indent: 0; }",
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
      -- Ordinary paragraph pitch never changes the inside of a note.
      -- the endnotes as the notes, only in a book that has them (root ADR 0412)
      <> ["section.endnotes aside p { margin-block: 0; padding-inline-start: 0; text-indent: 0; }" | hasEndnotes]
      <> ["section.endnotes aside p { line-height: normal; }" | hasEndnotes, any (isJust . hpsPhysical) (Map.elems (hcParaStyles cfg) <> concatMap (Map.elems . hlParaStyles) (Map.elems (hcLocalStyles cfg)))]
      <> ["section.notes aside p { line-height: normal; }" | any (isJust . hpsPhysical) (Map.elems (hcParaStyles cfg) <> concatMap (Map.elems . hlParaStyles) (Map.elems (hcLocalStyles cfg)))]
      -- the captions of tables below them (docs/adr/0262)
      <> ["table > caption { caption-side: bottom; }" | hcTableCaptionBelow cfg]
      -- the font and size of the cells of tables (docs/adr/0262)
      <> [faceRule (tableCellSelector name) f | (name, f) <- Map.toAscList (hcTableFaces cfg), isJust (faFont f) || isJust (faSize f)]
      -- paragraph styles (docs/adr ADR 0005); body is the plain p
      <> concat [paraRules name ps | (name, ps) <- Map.toAscList (hcParaStyles cfg), name /= "code"]
      -- the paragraph styles without a name (root ADR 0467), after those of their names
      <> anonymousRules "" (anonymousOf (hcAnonymousStyles cfg))
      <> [faceRule (tableCellSelector key) f | (r, f) <- Map.toAscList (hcAnonymousTableFaces cfg), isJust (faFont f) || isJust (faSize f), Just key <- [anonymousKey r]]
      -- the spaces before and after (docs/adr/0189)
      <> spaceRules outside True allStyles [(a, b) | a <- allStyles, b <- allStyles]
      -- the boxes of paragraph styles (docs/adr/0271)
      <> boxRules
      -- the rules of paragraph styles and headings as pseudo-elements (golem-driver ADR 0027)
      <> concat [ruleRules (if name == "body" then "p:not([class])" else "p.ps-" <> name) (hpsRuleBefore ps) (hpsRuleAfter ps) | (name, ps) <- Map.toAscList (hcParaStyles cfg), name /= "code"]
      <> concat [ruleRules ("h" <> tshow l) b a | (l, (b, a)) <- Map.toAscList (hcHeadingRules cfg)]
      <> headingStyleRules "" (hcHeadingStyles cfg)
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
      <> readingRules "" (hcCharStyles cfg)
      <> maybe [] (listRules cfg book) (hcLists cfg)
      <> markerRules "" (hcCharStyles cfg)
      -- forced breaks, only the kinds the book uses (docs/adr ADR 0017)
      <> [ "[data-break-before=\"" <> name <> "\"] { page-break-before: always; break-before: " <> name <> "; }"
         | k <- Set.toAscList (hcBreakKinds cfg),
           Just name <- [breakName k]
         ]
      -- avoiding a break, only when the book uses @no-page-break (docs/adr ADR 0030)
      <> ["[data-break-before=\"avoid\"] { page-break-before: avoid; break-before: avoid; }" | hcNoBreak cfg]
      -- the styles of the files, last, under the class of their pages (docs/adr ADR 0014)
      <> concat [localRules n l | (n, fid) <- zip [1 :: Int ..] docs, Just l <- [Map.lookup fid (hcLocalStyles cfg)]]
      -- the styles without a name as the files with styles of their own resolve them (root ADR 0467)
      <> concat [anonymousRules ("body.file-" <> tshow n <> " ") (anonymousOf a) | (n, fid) <- zip [1 :: Int ..] docs, Map.member fid (hcLocalStyles cfg), Just a <- [Map.lookup fid (hcLocalAnonymousStyles cfg)]]
      <> concat [headingStyleRules ("body.file-" <> tshow n <> " ") hs | (n, fid) <- zip [1 :: Int ..] docs, Just hs <- [Map.lookup fid (hcLocalHeadingStyles cfg)]]
  where
    headingStyleRules prefix hs = [rule (prefix <> "h" <> tshow level <> ".ps-" <> hhsName h) (hhsAlign h <> featureDecls (hhsFeatures h) <> ["line-height: " <> p | Just p <- [hhsPitch h]] <> maybe [] fitDecls (hhsFitCharacters h)) | (level, h) <- Map.toAscList hs]
    numbers = anonymousStyleNumbers book
    -- the key of a style without a name: NAME.pso-N, so that p.ps-KEY is p.ps-NAME.pso-N
    anonymousKey r = (\n -> styleRefName r <> ".pso-" <> tshow n) <$> Map.lookup r numbers
    anonymousOf m = [(key, ps) | (r, ps) <- sortOn (\(r, _) -> Map.lookup r numbers) (Map.toList m), Just key <- [anonymousKey r]]
    {- the rules of the styles without a name (root ADR 0467): every property
    the rule of a paragraph style handles, as a property left out would keep
    the value of the rule of its name; the space between two paragraphs of
    the same style; and the spaces of the pairs with the other styles -}
    anonymousRules pre styles =
      concat
        [ [ rule
              (pre <> "p.ps-" <> key)
              ( [ "font-family: " <> maybe "inherit" fontStack (hpsFont ps),
                  "margin-block: " <> marginOf ps
                ]
                  <> ["line-height: " <> L.ptText (hppPitch physical) <> "pt" | Just physical <- [hpsPhysical ps]]
                  <> ["margin-block-start: " <> spaceText ps (spaceBefore ps) | spaceBefore ps > 0]
                  <> [ "padding-inline-start: " <> hpsIndent ps,
                       "text-indent: " <> hpsFirstLineIndent ps,
                       "padding-inline-end: " <> hpsEndIndent ps
                     ]
                  <> hpsAlign ps
                  <> featureDecls (hpsFeatures ps)
                  <> hpsBreaks ps
              ),
            rule (pre <> "p.ps-" <> key <> " + p.ps-" <> key) ["margin-block-start: " <> (if spaceBetween ps > 0 then spaceText ps (spaceBetween ps) else if spaceBefore ps > 0 || spaceAfter ps > 0 then "0" else marginOf ps)]
          ]
            <> [rule (openingSelector (pre <> "p.ps-" <> key) ps) ["text-indent: " <> openingTextIndent f] | Just f <- [hpsOpeningHalf ps]]
            <> ruleRules (pre <> "p.ps-" <> key) (hpsRuleBefore ps) (hpsRuleAfter ps)
            <> [rule (pre <> "div.box-" <> key) (hbDecls hb) | Just hb <- [hpsBox ps]]
        | (key, ps) <- styles
        ]
        <> spaceRules (const (T.dropWhileEnd (== ' ') pre)) False styles [(a, b) | a <- styles <> allStyles, b <- styles <> allStyles, fst a `elem` map fst styles || fst b `elem` map fst styles]
    marginOf ps = if hpsKeepLines ps || isJust (hpsPhysical ps) then "0" else "1em"
    hasEndnotes = not (all (null . documentEndnotes) (bookDocs book))
    separatorPitch = maybe "1lh" ((<> "pt") . L.ptText) (hcSeparatorPitch cfg)
    docs = [fid | Document fid _ <- bookDocs book]
    -- the role of code, then its generic family or monospace (golem-driver ADR 0017, docs/adr/0423)
    codeStack = T.intercalate ", " (maybe [] families (hcoFont (hcCode cfg)) <> [fromMaybe "monospace" (hcoFont (hcCode cfg) >>= genericOf)])
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
      [ "font-family: " <> T.intercalate ", " (stack role)
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
        <> hcsTextDecoration cs
        -- the background and the padding of inline code, along the line only (golem-driver ADR 0029)
        <> ["background-color: " <> rgbOf cmyk | Just sw <- [hcsBackground cs], Just cmyk <- [Map.lookup sw (hcSwatches cfg)]]
        <> ["padding-inline: " <> p | Just p <- [hcsPadding cs]]
        -- a range that does not break; a br breaks inside it, as a forced break does in the PDF (docs/adr ADR 0272)
        <> ["white-space: nowrap" | hcsNoBreak cs]
      where
        fallback = if hcsCode cs then [] else families "body"
        -- the families of the role, then body's for a style not of code, then the generic family (docs/adr/0423)
        stack role = families role <> fallback <> [charGeneric cs]
    {- the keys of the spacing of characters whose values differ from the
    defaults of body (docs/adr/0020): CSS kerns Japanese and Latin alike,
    so japanese-equal-width keeps the Latin kerning -}
    featureDecls f =
      [ "font-kerning: " <> (if k == "none" then "none" else "normal")
      | Just k <- [hfKerning f],
        k /= "metrics"
      ]
        <> ["letter-spacing: " <> thousandths t <> "em" | Just t <- [hfTracking f], t /= 0]
        -- one declaration: the features of the style, then palt (vpal) of proportional-metrics (docs/adr/0268)
        <> [ "font-feature-settings: " <> T.intercalate ", " settings
           | let settings =
                   ["\"" <> t <> "\" " <> tshow v | (t, v) <- hfOpenType f]
                     <> ["\"" <> (if hcVertical cfg then "vpal" else "palt") <> "\" 1" | hfProportional f == Just True],
             not (null settings)
           ]
        <> ["vertical-align: " <> l | Just l <- [hfBaselineShift f], not (isZero l)]
    thousandths n =
      let (q, r) = abs n `divMod` 1000
          frac = T.dropWhileEnd (== '0') (T.justifyRight 3 '0' (tshow r))
       in (if n < 0 then "-" else "") <> tshow q <> (if T.null frac then "" else "." <> frac)
    rgbOf cmyk = let (r, g, b) = cmykToRgb cmyk in "rgb(" <> tshow r <> ", " <> tshow g <> ", " <> tshow b <> ")"
    rule sel ds = sel <> " { " <> T.concat [d <> "; " | d <- ds] <> "}"
    -- the rule before as ::before, after as ::after; space-before above, space-after below (golem-driver ADR 0027)
    ruleRules sel before after =
      [ruleOf (sel <> "::before") r (hrOuter r <> " " <> hrInner r) | Just r <- [before]]
        <> [ruleOf (sel <> "::after") r (hrOuter r <> " " <> hrInner r) | Just r <- [after]]
    ruleOf sel r margins =
      rule
        sel
        ( ["content: \"\"", "display: block"]
            <> ["width: " <> w | Just w <- [hrWidth r]]
            <> ["border-block-start: " <> hrBorder r, "margin-block: " <> margins]
            <> ["margin-inline-start: " <> i | Just i <- [hrStartIndent r]]
            <> ["margin-inline-end: " <> i | Just i <- [hrEndIndent r]]
        )
    faceRule sel f = rule sel (["font-family: " <> fontStack role | Just role <- [faFont f]] <> ["font-size: " <> s | Just s <- [faSize f]])
    markerRules prefix styles =
      [ rule (prefix <> markerSelector) (["all: inherit" | not (T.null prefix)] <> declsOf "" cs <> ["font-size: " <> size | Just size <- [hcsSize cs]])
      | Just name <- [hcLists cfg >>= hlMarkerStyle],
        Just cs <- [Map.lookup name styles]
      ]
    markerSelector = ":is(ol, ul)[class^=\"list-\"] > li::marker"
    charRule name cs = rule (selectorOf name) (declsOf name cs)
    -- a rule that says only what the element shows anyway is not written
    {- the box of each style that has one, its paragraphs without their
    indents, which the box takes, and without their outer margins, the
    spaces before the first and after the last on the box; a pair of a
    paragraph and a box after it as a pair of paragraphs (docs/adr/0271) -}
    boxed = [(n, ps, hb) | (n, ps) <- allStyles, Just hb <- [hpsBox ps]]
    paraSelOf n = if n == "body" then "p:not([class])" else "p.ps-" <> n
    boxRules =
      [rule ("div.box-" <> n) (hbDecls hb) | (n, _, hb) <- boxed]
        <> concat
          [ [ "div.box > p { padding-inline-start: 0; padding-inline-end: 0; }",
              "div.box > p:first-child { margin-block-start: 0; }",
              "div.box > p:last-child { margin-block-end: 0; }"
            ]
          | not (null boxed)
          ]
        <> ["div.box:has(> " <> paraSelOf n <> ":first-child) { margin-block-start: " <> spaceText ps (spaceBefore ps) <> "; }" | (n, ps, _) <- boxed, spaceBefore ps > 0]
        <> ["div.box:has(> " <> paraSelOf n <> ":last-child) { margin-block-end: " <> spaceText ps (spaceAfter ps) <> "; }" | (n, ps, _) <- boxed, spaceAfter ps > 0]
        <> [ paraSelOf a <> " + div.box:has(> " <> paraSelOf b <> ":first-child) { margin-block-start: " <> spaceText pb (max x y) <> "; }"
           | (a, pa) <- allStyles,
             (b, pb, _) <- boxed,
             let x = spaceAfter pa
                 y = spaceBefore pb,
             x > 0,
             y > 0
           ]
    charRuleMaybe name cs =
      let ds = declsOf name cs
       in if null ds || ds == defaults name then Nothing else Just (rule (selectorOf name) ds)
    {- the indent of a style is written when it differs from body's, and
    body's when it is not 0; text-indent is inherited by the lines, so
    each line of a style that keeps them hangs (docs/adr ADR 0006) -}
    bodyIndent = maybe ("0", "0") (\b -> (hpsIndent b, hpsFirstLineIndent b)) (Map.lookup "body" (hcParaStyles cfg))
    isZero l = T.dropWhile (== '-') l `elem` ["0", "0em", "0pt"]
    indentRule name ps
      | name == "body" = not (isZero (hpsIndent ps) && isZero (hpsFirstLineIndent ps))
      | otherwise = (hpsIndent ps, hpsFirstLineIndent ps) /= bodyIndent
    {- the alignment and the end indent, on the same condition as the indent
    (docs/adr/0189): body's when not the default, another's when it differs
    from body's -}
    bodyPara = Map.lookup "body" (hcParaStyles cfg)
    alignRule name ps
      | name == "body" = hpsAlign ps /= defaultAlignDecls
      | otherwise = hpsAlign ps /= maybe defaultAlignDecls hpsAlign bodyPara
    endIndentRule name ps
      | name == "body" = not (isZero (hpsEndIndent ps))
      | otherwise = hpsEndIndent ps /= maybe "0em" hpsEndIndent bodyPara
    paraRules name ps =
      let sel = if name == "body" then "p" else "p.ps-" <> name
          -- the same style in a row: space-between, also 0 against the spaces before and after (docs/adr/0189)
          spaced = spaceBefore ps > 0 || spaceAfter ps > 0
          adjacent = if name == "body" && isJust (hpsPhysical ps) then "p:where(:not([class]))" else sel
       in ["p.ps-" <> name <> " { font-family: " <> fontStack role <> "; }" | name /= "body", Just role <- [hpsFont ps]]
            -- the entries of the table of contents in the font of toc-<l> (docs/adr/0264)
            <> ["nav.toc li." <> name <> " { font-family: " <> fontStack role <> "; }" | "toc-" `T.isPrefixOf` name, Just role <- [hpsFont ps]]
            <> [sel <> " { line-height: " <> L.ptText (hppPitch physical) <> "pt; margin-block: 0; }" | Just physical <- [hpsPhysical ps]]
            <> [sel <> " { margin-block: 0; }" | hpsKeepLines ps, isNothing (hpsPhysical ps)]
            <> [ sel <> " { padding-inline-start: " <> hpsIndent ps <> "; text-indent: " <> hpsFirstLineIndent ps <> "; }"
               | indentRule name ps
               ]
            -- the first line of a paragraph that starts with an opening bracket (root ADR 0469)
            <> [openingSelector sel ps <> " { text-indent: " <> openingTextIndent f <> "; }" | Just f <- [hpsOpeningHalf ps]]
            <> [rule sel (hpsAlign ps) | alignRule name ps]
            -- the width of so many characters, the characters spread over it (root ADR 0466)
            <> [rule sel (fitDecls n) | Just n <- [hpsFitCharacters ps]]
            <> [sel <> " { padding-inline-end: " <> hpsEndIndent ps <> "; }" | endIndentRule name ps]
            <> [ prefixed (outside [name | name /= "body"]) (adjacent <> " + " <> adjacent) <> " { margin-block-start: " <> (if spaceBetween ps > 0 then spaceText ps (spaceBetween ps) else "0") <> "; }"
               | spaceBetween ps > 0 || spaced || isJust (hpsPhysical ps)
               ]
            <> [rule sel ds | let ds = featureDecls (hpsFeatures ps), not (null ds)]
            <> [rule sel (hpsBreaks ps) | not (null (hpsBreaks ps))]
    {- the spaces before and after of the paragraph styles (docs/adr/0189),
    under a prefix and over styles: the space before on the style, the
    space after on the next element of another style that is not a blank
    line, the greater of the two for a pair, after both, and none after a
    blank line. The rule of a pair, p.ps-A + p.ps-B:not(.ps-A), wins over
    the rule of the space after by its specificity, not by its place
    (docs/adr/0211). The rules p and div.blank-line + p of body, like p + p
    of body above, take no prefix: with one, they would win over the
    spaces before of other styles on other pages (docs/adr/0236) -}
    spaceRules preOf withBefore styles pairs =
      let at ns = prefixed (preOf ns)
          -- the rule p of body and the rule after a blank line that goes with it are on every page
          atBefore n = if n == "body" && global then prefixed "" else at [n]
          -- the rules of style.toml, not those of a file
          global = T.null (preOf [])
          -- the class of body is that it has none
          own n = if n == "body" then "p:not([class])" else "p.ps-" <> n
          beforeSel n = if n == "body" && global then "p" else own n
          afterSel n
            | n == "body" = "p:not([class]) + :not(p):not(.blank-line), p:not([class]) + p[class]"
            | otherwise = "p.ps-" <> n <> " + :not(.ps-" <> n <> "):not(.blank-line)"
          -- as strong as the rule of the space after, written after it
          pairSel a b
            | a == "body" = own a <> " + " <> own b
            | otherwise = own a <> " + " <> own b <> ":not(.ps-" <> a <> ")"
       in [atBefore n (beforeSel n) <> " { margin-block-start: " <> spaceText ps b <> "; }" | withBefore, (n, ps) <- styles, let b = spaceBefore ps, b > 0]
            <> [at [n] (afterSel n) <> " { margin-block-start: " <> spaceText ps a <> "; }" | (n, ps) <- styles, let a = spaceAfter ps, a > 0]
            <> [ at [a, b] (pairSel a b) <> " { margin-block-start: " <> spaceText pb (max x y) <> "; }"
               | ((a, pa), (b, pb)) <- pairs,
                 a /= b,
                 let x = spaceAfter pa
                     y = spaceBefore pb,
                 x > 0,
                 y > 0
               ]
            <> [atBefore n ("div.blank-line + " <> beforeSel n) <> " { margin-block-start: 0; }" | (n, ps) <- styles, spaceBefore ps > 0]
    {- a selector list under a prefix: each selector of the list starts
    with it -}
    prefixed pre sel = if T.null pre then sel else T.intercalate ", " [pre <> " " <> x | x <- T.splitOn ", " sel]
    {- the rules of style.toml for the spaces of these paragraph styles are
    not on the pages of the files that define any of them (docs/adr/0217):
    body:not(.file-n1):not(.file-n2)..., or nothing when no file does -}
    outside names = case [k | (k, fid) <- zip [1 :: Int ..] docs, Just l <- [Map.lookup fid (hcLocalStyles cfg)], any (`Map.member` hlParaStyles l) names] of
      [] -> ""
      ks -> "body" <> T.concat [":not(.file-" <> tshow k <> ")" | k <- ks]
    allStyles = [(n, ps) | (n, ps) <- Map.toAscList (hcParaStyles cfg), n /= "code"]
    -- the families of the fonts of a role, none when the site names generic families only (docs/adr/0423)
    families role = case Map.lookup role (hcFonts cfg) of
      Just (ja, la) | hcEmbedFonts cfg -> ["\"" <> cssString (family role "latin") <> "\"" | Just _ <- [la]] <> ["\"" <> cssString (family role "ja") <> "\"" | Just _ <- [ja]]
      _ -> []
    family role kind = "golem-" <> role <> "-" <> kind
    {- the generic family that ends font-family (docs/adr/0423): that of the
    role; for a paragraph, serif without one; for a character style of code,
    monospace; for another character style, that of body, then serif -}
    genericOf role = Map.lookup role (hcGenericFamilies cfg)
    fontStack role = T.intercalate ", " (families role <> [fromMaybe "serif" (genericOf role)])
    charGeneric cs
      | hcsCode cs = fromMaybe "monospace" (hcsFont cs >>= genericOf)
      | otherwise = fromMaybe "serif" ((hcsFont cs >>= genericOf) <|> genericOf "body")
    charStack cs = T.intercalate ", " (maybe [] families (hcsFont cs) <> [charGeneric cs])
    {- the rules of the styles of a file: every property they handle, as a
    property left out would keep the value of the rule of style.toml -}
    readingRules prefix styles =
      [ rule (prefix <> "ruby > rt") (declsOf "" cs <> inherited cs <> ["font-size: " <> fromMaybe "0.5em" (hcsSize cs)])
      | Just name <- [hcRubyReadingStyle cfg],
        Just cs <- [Map.lookup name styles]
      ]
      where
        inherited cs =
          [ property <> ": inherit"
          | not (T.null prefix),
            (property, missing) <- [("font-family", isNothing (hcsFont cs)), ("color", isNothing (hcsColor cs)), ("font-weight", not (hcsBold cs)), ("font-style", not (hcsItalic cs))],
            missing
          ]
    localRules n l =
      let pre = "body.file-" <> tshow n
          stackOr = maybe "inherit" fontStack
          colorOf cs = case hcsColor cs >>= (`Map.lookup` hcSwatches cfg) of
            Just cmyk -> let (r, g, b) = cmykToRgb cmyk in "rgb(" <> tshow r <> ", " <> tshow g <> ", " <> tshow b <> ")"
            Nothing -> "inherit"
          charRules =
            [ rule
                (pre <> " " <> selectorOf name)
                ( [ "font-family: " <> (if isJust (hcsFont cs) then charStack cs else "inherit"),
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
                    -- a range that does not break (docs/adr ADR 0272)
                    <> ["white-space: nowrap" | hcsNoBreak cs]
                )
            | (name, cs) <- Map.toAscList (hlCharStyles l)
            ]
          paraOf name
            | name /= "body" = "p.ps-" <> name
            | maybe False (isJust . hpsPhysical) (Map.lookup name merged) = "p:where(:not([class]))"
            | otherwise = "p:not([class])"
          paraSel name = pre <> " " <> paraOf name
          margin ps = if hpsKeepLines ps || isJust (hpsPhysical ps) then "0" else "1em"
          -- the alignment of the file's body, the default written as the initial values (docs/adr/0189)
          fileBodyAlign = maybe defaultAlignDecls hpsAlign (Map.lookup "body" merged)
          -- the styles of the page: the file's over those of style.toml
          merged = Map.union (hlParaStyles l) (hcParaStyles cfg)
          mergedList = [(m, ps) | (m, ps) <- Map.toAscList merged, m /= "code"]
          alignOf ps
            | hpsAlign ps == defaultAlignDecls && fileBodyAlign == defaultAlignDecls = ["text-align: start", "text-align-last: auto"]
            | otherwise = hpsAlign ps
          spaced ps = spaceBefore ps > 0 || spaceAfter ps > 0
          locals = [(name, ps) | (name, ps) <- Map.toAscList (hlParaStyles l), name /= "code"]
          paraStyleRules =
            concat
              [ [ rule
                    (paraSel name)
                    ( [ "font-family: " <> stackOr (hpsFont ps),
                        "margin-block: " <> margin ps
                      ]
                        <> ["line-height: " <> L.ptText (hppPitch physical) <> "pt" | Just physical <- [hpsPhysical ps]]
                        <> ["margin-block-start: " <> spaceText ps (spaceBefore ps) <> "" | spaceBefore ps > 0]
                        <> [ "padding-inline-start: " <> hpsIndent ps,
                             "text-indent: " <> hpsFirstLineIndent ps,
                             "padding-inline-end: " <> hpsEndIndent ps
                           ]
                        <> alignOf ps
                        <> featureDecls (hpsFeatures ps)
                    ),
                  rule (paraSel name <> " + " <> paraOf name) ["margin-block-start: " <> (if spaceBetween ps > 0 then spaceText ps (spaceBetween ps) else if spaced ps then "0" else margin ps)]
                ]
                  -- the first line of a paragraph that starts with an opening bracket (root ADR 0469)
                  <> [rule (openingSelector (paraSel name) ps) ["text-indent: " <> openingTextIndent f] | Just f <- [hpsOpeningHalf ps]]
                  -- fit-characters (root ADR 0466)
                  <> [rule (paraSel name) (fitDecls k) | Just k <- [hpsFitCharacters ps]]
              | (name, ps) <- locals
              ]
              -- the pairs of a style of the file and another
              <> spaceRules (const pre) False locals [(a, b) | a <- mergedList, b <- mergedList, Map.member (fst a) (hlParaStyles l) || Map.member (fst b) (hlParaStyles l)]
          faceDecls f = ["font-family: " <> stackOr (faFont f), "font-size: " <> fromMaybe "inherit" (faSize f)]
          faceRules =
            [rule (pre <> " figcaption") (faceDecls f) | Just f <- [hlCaptionFace l]]
              -- the cells of tables (docs/adr/0262)
              <> [rule (T.intercalate ", " [pre <> " " <> sel | sel <- T.splitOn ", " (tableCellSelector name)]) (faceDecls f) | (name, f) <- Map.toAscList (hlTableFaces l)]
              <> [rule (pre <> " .sidenote") (faceDecls f {faSize = Just (fromMaybe "0.85em" (faSize f))}) | Just f <- [hlSidenoteFace l]]
          -- no indent in list items, after the rules of the paragraph styles of the page
          listRule = [pre <> " li p:not([class]), " <> pre <> " li p[class] { padding-inline-start: 0; text-indent: 0; }" | not (Map.null (hlParaStyles l))]
          -- the boxes of the styles of the file, and no indent in a box (docs/adr/0271)
          boxLocal =
            [rule (pre <> " div.box-" <> name) (hbDecls hb) | (name, ps) <- locals, Just hb <- [hpsBox ps]]
              <> [pre <> " div.box > p { padding-inline-start: 0; padding-inline-end: 0; }" | not (Map.null (hlParaStyles l)), any (isJust . hpsBox . snd) mergedList]
       in charRules <> markerRules (pre <> " ") (hlCharStyles l) <> readingRules (pre <> " ") (hlCharStyles l) <> paraStyleRules <> faceRules <> boxLocal <> listRule

{- | The declarations of a paragraph style of fit-characters (root ADR
0466): the width of so many characters, the characters spread over it.
-}
fitDecls :: Int -> [Text]
fitDecls n = ["width: " <> T.pack (show n) <> "em", "text-align: justify", "text-align-last: justify", "text-justify: inter-character"]

{- | The table of contents page of the HTML target, index.html, in the HTML
syntax (docs/adr ADR 0090, root ADR 0432).
-}
indexPage :: HtmlConfig -> FileTable -> Book -> Text
indexPage cfg ft book =
  let items =
        concat
          [ [ el
                "li"
                [("class", "toc-" <> T.pack (show (teLevel te)))]
                [ Element
                    "a"
                    [("href", PageLink (T.pack (pageBase ft (teFile te))) (teAnchor te))]
                    (titledNodes (hcLanguage cfg) book (teFile te) (Just (teLevel te)) False (teNumber te) (foldMap inlineText (teTitle te)) (titleNodes (teTitle te)))
                ],
              nl
            ]
          | -- within the depth of @toc (golem-epub ADR 0002)
            te <- tocWithinDepth book
          ]
   in M.writeDocument
        HtmlSyntax
        [ el
            "html"
            ([("xmlns", "http://www.w3.org/1999/xhtml")] <> langPairs (hcLanguage cfg))
            [ nl,
              el "head" [] [nl, el "meta" [("charset", "UTF-8")] [], nl, el "title" [] [textOf (hcTitle cfg)], nl, el "link" [("rel", "stylesheet"), ("type", "text/css"), ("href", "style.css")] [], nl],
              nl,
              el "body" [] [nl, el "h1" [] [textOf (hcTitle cfg)], nl, el "nav" [("class", "toc")] [nl, el "ol" [] (nl : items), nl], nl],
              nl
            ],
          nl
        ]

{- | The cells of the tables of a paragraph style (docs/adr/0262): of a
table without a class for the built-in table, of table.ps-NAME otherwise.
-}
tableCellSelector :: Text -> Text
tableCellSelector = \case
  "table" -> "table:not([class]) th, table:not([class]) td"
  name -> "table.ps-" <> name <> " th, table.ps-" <> name <> " td"

{- | The width of a column as CSS (docs/adr/0262): zw in em, a length as
the width of a figure, a percentage in % (of the width of the table, not
of the width the columns share as in the PDF); none for auto.
-}
columnWidthCss :: ColumnWidth -> Maybe Text
columnWidthCss = \case
  ColumnAuto -> Nothing
  ColumnZw r -> Just (L.emText r <> "em")
  ColumnAbs x -> Just (L.ptText x <> "pt")
  ColumnPercent r -> Just (showRationalDigits 4 r <> "%")

{- | The size of the image of a figure with a width (docs/adr/0190): in a
horizontal book its width, in a vertical one its height, each with the
maximum of 100% of the same direction, so that a width beyond the measure
fits it as in the PDF. A length in pt, zw in em, a percentage in %.
-}
figureWidthStyle :: Bool -> Maybe Text -> [(Text, Text)]
figureWidthStyle vertical width = case width >>= parseFigureWidth of
  Nothing -> []
  Just w ->
    let prop = if vertical then "height" else "width"
        len = case w of
          WidthLength x -> L.ptText x <> "pt"
          WidthZw r -> L.emText r <> "em"
          WidthPercent r -> showRationalDigits 4 r <> "%"
     in [("style", prop <> ": " <> len <> "; max-" <> prop <> ": 100%")]
