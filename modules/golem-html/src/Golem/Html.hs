{- | XHTML and CSS output (golem-html ADR 0001). Pages are polyglot XHTML
so that EPUB can use them unchanged.
-}
module Golem.Html
  ( HtmlConfig (..),
    HtmlCharStyle (..),
    HtmlParaStyle (..),
    Face (..),
    noFace,
    XhtmlSite (..),
    renderXhtml,
    pagePath,
    escapeXml,
    cmykToRgb,
  )
where

import Data.List (sortOn)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, mapMaybe)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.Assemble
import Golem.Doc.IR
import Golem.Doc.Numerals
import Golem.Syntax.Span
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
    -- | the font and size of figcaption (golem-driver ADR 0010)
    hcCaptionFace :: !Face,
    -- | the font and size of sidenotes (golem-driver ADR 0011)
    hcSidenoteFace :: !Face,
    hcBibliography :: !(Map Text Text), -- key -> formatted entry
    hcDev :: !Bool,
    -- | [composition.ruby] as CSS ruby-align values (golem-layout ADR 0009)
    hcRubyMonoAlign :: !Text,
    hcRubyGroupAlign :: !Text,
    hcRubyBaseSpacing :: !Text,
    -- | the kinds of forced break the book uses (docs/adr ADR 0017)
    hcBreakKinds :: !(Set BreakKind)
  }

-- | A font role and a CSS font-size for an element (golem-driver ADR 0010).
data Face = Face
  { faFont :: !(Maybe Text),
    faSize :: !(Maybe Text)
  }

noFace :: Face
noFace = Face Nothing Nothing

-- | A resolved character style for CSS (docs/adr ADR 0005).
data HtmlCharStyle = HtmlCharStyle
  { hcsFont :: !(Maybe Text),
    -- | the resolved synthetic-bold
    hcsBold :: !Bool,
    -- | the resolved synthetic-italic
    hcsItalic :: !Bool,
    hcsColor :: !(Maybe Text)
  }

-- | A resolved paragraph style for CSS (docs/adr ADR 0005, 0006).
data HtmlParaStyle = HtmlParaStyle
  { hpsFont :: !(Maybe Text),
    hpsKeepLines :: !Bool,
    hpsSpaceBetween :: !Int,
    -- | a CSS length
    hpsIndent :: !Text,
    -- | a CSS length; may be negative
    hpsFirstLineIndent :: !Text
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

-- | The naive conversion: screen colours are an approximation of print.
cmykToRgb :: (Int, Int, Int, Int) -> (Int, Int, Int)
cmykToRgb (c, m, y, k) =
  let ch v = round (255 * (1 - fromIntegral v / 100 :: Rational) * (1 - fromIntegral k / 100))
   in (ch c, ch m, ch y)

data Ctx = Ctx
  { cCfg :: HtmlConfig,
    cFt :: FileTable,
    cBook :: Book,
    cHere :: FilePath
  }

renderXhtml :: HtmlConfig -> FileTable -> Book -> XhtmlSite
renderXhtml cfg ft book =
  XhtmlSite
    { sitePages = [(pagePath ft fid, page cfg ft book d) | d@(Document fid _) <- bookDocs book],
      siteCss = css cfg,
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

page :: HtmlConfig -> FileTable -> Book -> Document -> Text
page cfg ft book d@(Document fid bs) =
  let here = pagePath ft fid
      c = Ctx cfg ft book here
      body = topBlocks c bs <> notesSection c d
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
          if hcVertical cfg then " class=\"vertical\"" else "",
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
        keep = maybe False hpsKeepLines (Map.lookup (fromMaybe "body" st) (hcParaStyles (cCfg c)))
        -- the lines of a paragraph that keeps them, each a span; br is for readers without CSS (docs/adr ADR 0005)
        content
          | keep || any isLineBreak is = T.intercalate "<br/>\n" ["<span class=\"line\">" <> inlines c l <> "</span>" | l <- splitLines is]
          | otherwise = inlines c is
     in "<p" <> idAttr lbl <> cls <> ">" <> content <> "</p>\n" <> sidenotes c is
  Heading l _ is ->
    let tag = "h" <> T.pack (show l)
        info = Map.lookup sp (bookHeadings (cBook c))
        anchor = maybe (headingAnchor lbl sp) hiAnchor info
        num = maybe "" (\n -> "<span class=\"number\">" <> escapeXml n <> "</span>") (info >>= hiNumberText)
     in "<" <> tag <> " id=\"" <> escapeXml anchor <> "\">" <> num <> inlines c is <> "</" <> tag <> ">\n"
  BulletList items -> "<ul" <> idAttr lbl <> ">\n" <> T.concat (map (item c Nothing) items) <> "</ul>\n"
  OrderedList items ->
    let start = case items of
          (ListItem (Just n) _ : _) -> " start=\"" <> T.pack (show n) <> "\""
          _ -> ""
     in "<ol" <> idAttr lbl <> start <> ">\n" <> T.concat (zipWith (\i it -> item c (if i > (0 :: Int) then itemNumber it else Nothing) it) [0 ..] items) <> "</ol>\n"
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
  CodeBlock lang t ->
    "<pre" <> idAttr lbl <> "><code" <> maybe "" (\l -> " class=\"sourceCode language-" <> escapeXml l <> "\"") lang <> ">" <> highlighted lang t <> "</code></pre>\n"
  FigureBlock f ->
    let num = maybe "" (\n -> "<span class=\"number\">" <> escapeXml n <> "</span>") (Map.lookup sp (bookFigures (cBook c)))
        cap = T.concat [inlines c is | Block _ _ (Paragraph _ is) <- figCaption f]
     in "<figure" <> idAttr lbl <> ">\n<img src=\"" <> relLink (cHere c) (T.unpack (webSource f)) <> "\" alt=\"" <> escapeXml (figAlt f) <> "\"/>\n<figcaption>" <> num <> cap <> "</figcaption>\n</figure>\n"
  ChannelOutput (TocOutput d) -> toc c (Just d)
  ChannelOutput IndexOutput -> index c
  ChannelOutput BibliographyOutput ->
    "<ol class=\"bibliography\">\n"
      <> T.concat
        [ "<li id=\"cite-" <> escapeXml k <> "\">" <> escapeXml (fromMaybe k (Map.lookup k (hcBibliography (cCfg c)))) <> "</li>\n"
        | (k, _) <- bookCitations (cBook c)
        ]
      <> "</ol>\n"
  ForcedBreak _ -> ""

item :: Ctx -> Maybe Integer -> ListItem -> Text
item c value (ListItem _ bs) =
  "<li" <> maybe "" (\n -> " value=\"" <> T.pack (show n) <> "\"") value <> ">" <> case bs of
    [Block _ _ (Paragraph Nothing is)] | not (any isLineBreak is) -> inlines c is <> "</li>\n"
    _ -> "\n" <> T.concat (map (block c) bs) <> "</li>\n"

toc :: Ctx -> Maybe Int -> Text
toc c depth =
  "<nav epub:type=\"toc\" class=\"toc\">\n<ol>\n"
    <> T.concat
      [ "<li class=\"toc-"
          <> T.pack (show (teLevel e))
          <> "\"><a href=\""
          <> linkTo c (teFile e) (teAnchor e)
          <> "\">"
          <> maybe "" (\n -> escapeXml n <> " ") (teNumber e)
          <> inlines c (teTitle e)
          <> "</a></li>\n"
      | e <- bookToc (cBook c),
        maybe True (teLevel e <=) depth
      ]
    <> "</ol>\n</nav>\n"

linkTo :: Ctx -> FileId -> Text -> Text
linkTo c fid anchor =
  let target = pagePath (cFt c) fid
      file = if target == cHere c then "" else relLink (cHere c) target
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
  Kenten _ sh xs -> "<span class=\"kenten kenten-" <> escapeXml (fromMaybe "default" sh) <> "\">" <> inlines c xs <> "</span>"
  Color _ s xs -> "<span class=\"swatch-" <> escapeXml s <> "\">" <> inlines c xs <> "</span>"
  -- the built-in character styles keep their elements (docs/adr ADR 0005)
  CharStyle _ "strong" xs -> "<strong>" <> inlines c xs <> "</strong>"
  CharStyle _ "bold" xs -> "<b>" <> inlines c xs <> "</b>"
  CharStyle _ "italic" xs -> "<i>" <> inlines c xs <> "</i>"
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
  Note _ n _ -> "<a epub:type=\"noteref\" class=\"noteref\" href=\"#note-" <> tshow n <> "\" id=\"noteref-" <> tshow n <> "\">" <> tshow n <> "</a>"
  Sidenote _ n _ -> "<sup class=\"sidenote-ref\">" <> tshow n <> "</sup>"
  IndexMark sp _ -> "<span id=\"" <> spanAnchor sp <> "\"></span>"
  Cite _ k -> case lookup k (bookCitations (cBook c)) of
    Just n -> "<a class=\"cite\" href=\"#cite-" <> escapeXml k <> "\">[" <> tshow n <> "]</a>"
    Nothing -> ""
  ProofComment _ t -> if hcDev (cCfg c) then "<span class=\"proof\">" <> escapeXml t <> "</span>" else ""
  LineBreak _ -> "<br/>"
  where
    styleOf = \case
      "kanji-digits" -> StyleKanjiDigits
      "tcy" -> StyleTcy
      _ -> StyleKanji

tshow :: (Show a) => a -> Text
tshow = T.pack . show

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

notesSection :: Ctx -> Document -> Text
notesSection c (Document _ bs) =
  case concatMap (mapMaybe noteOf . blockNotes) bs of
    [] -> ""
    ns ->
      "<section class=\"notes\">\n"
        <> T.concat
          [ "<aside epub:type=\"footnote\" id=\"note-" <> tshow n <> "\"><a href=\"#noteref-" <> tshow n <> "\">" <> tshow n <> "</a> " <> inlines c xs <> "</aside>\n"
          | (n, xs) <- ns
          ]
        <> "</section>\n"
  where
    noteOf = \case
      Note _ n xs -> Just (n, xs)
      _ -> Nothing

blockNotes :: Block -> [Inline]
blockNotes (Block _ _ body) = case body of
  Paragraph _ is -> deep is
  Heading _ _ is -> deep is
  BulletList items -> concatMap (concatMap blockNotes . itemBlocks) items
  OrderedList items -> concatMap (concatMap blockNotes . itemBlocks) items
  DefList gs -> concatMap (\(DefGroup ts ds) -> concatMap deep ts <> concatMap (concatMap blockNotes) ds) gs
  Table _ h rows -> concatMap deep h <> concatMap (concatMap deep) rows
  FigureBlock f -> concatMap blockNotes (figCaption f)
  _ -> []
  where
    deep = concatMap (\i -> i : nested i)
    nested = \case
      Kenten _ _ xs -> deep xs
      Color _ _ xs -> deep xs
      CharStyle _ _ xs -> deep xs
      _ -> []

{- | Code coloured with skylighting's classes (golem-html ADR 0001). An
unknown language, or text the highlighter rejects, stays plain.
-}
highlighted :: Maybe Text -> Text -> Text
highlighted lang code = case lang >>= \l -> S.lookupSyntax l S.defaultSyntaxMap of
  Nothing -> escapeXml code
  Just syntax -> case S.tokenize (S.TokenizerConfig S.defaultSyntaxMap False) syntax code of
    Left _ -> escapeXml code
    Right ls -> T.intercalate "\n" (map (T.concat . map tok) ls)
  where
    tok (S.NormalTok, t) = escapeXml t
    tok (ty, t) = "<span class=\"" <> shortClass ty <> "\">" <> escapeXml t <> "</span>"

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

css :: HtmlConfig -> Text
css cfg =
  T.unlines $
    [ "@font-face { font-family: \""
        <> family role kind
        <> "\"; src: url(\""
        <> T.pack (fontOut p)
        <> "\");"
        <> (if role `elem` boldRoles then " font-weight: bold;" else "")
        <> (if role `elem` italicRoles then " font-style: italic;" else "")
        <> " }"
    | (role, (ja, la)) <- Map.toAscList (hcFonts cfg),
      (kind, Just p) <- [("latin" :: Text, la), ("ja", ja)]
    ]
      <> [ "body { font-family: " <> fontStack "body" <> "; }",
           "body.vertical { writing-mode: vertical-rl; -epub-writing-mode: vertical-rl; }"
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
           ".align-left { text-align: left; }",
           ".align-center { text-align: center; }",
           ".align-right { text-align: right; }",
           ".proof { background: #ffeb99; }",
           -- ruby: the base, a group reading and a mono reading (golem-layout ADR 0009)
           "ruby { ruby-align: " <> hcRubyBaseSpacing cfg <> "; }",
           "rt { ruby-align: " <> hcRubyGroupAlign cfg <> "; }",
           "ruby.mono rt { ruby-align: " <> hcRubyMonoAlign cfg <> "; }",
           T.strip (T.pack (S.styleToCss S.pygments))
         ]
      -- the caption's font and size (golem-driver ADR 0010)
      <> [faceRule "figcaption" (hcCaptionFace cfg) | isJust (faFont (hcCaptionFace cfg)) || isJust (faSize (hcCaptionFace cfg))]
      -- the sidenote's font and size; smaller than the text when no size is given (golem-driver ADR 0011)
      <> [ faceRule ".sidenote" (hcSidenoteFace cfg) {faSize = Just (fromMaybe "0.85em" (faSize (hcSidenoteFace cfg)))},
           "@media (min-width: 60em) { .sidenote { float: right; clear: right; width: 14em; margin-right: -16em; } }"
         ]
      -- paragraph styles (docs/adr ADR 0005); body is the plain p
      <> concat [paraRules name ps | (name, ps) <- Map.toAscList (hcParaStyles cfg)]
      -- no indent in list items (docs/adr ADR 0006); li p[class] is stronger than p.ps-name
      <> ["li p, li p[class] { padding-inline-start: 0; text-indent: 0; }" | any (uncurry indentRule) (Map.toList (hcParaStyles cfg))]
      -- the lines of a paragraph that keeps them; br is for readers without CSS
      <> [ ".line { display: block; }",
           ".line + br { display: none; }"
         ]
      <> [ ".swatch-" <> name <> " { color: rgb(" <> tshow r <> ", " <> tshow g <> ", " <> tshow b <> "); }"
         | (name, cmyk) <- Map.toAscList (hcSwatches cfg),
           let (r, g, b) = cmykToRgb cmyk
         ]
      <> [r | (name, cs) <- Map.toAscList (hcCharStyles cfg), name /= "strong", Just r <- [charRuleMaybe name cs]]
      -- forced breaks, only the kinds the book uses (docs/adr ADR 0017)
      <> [ "[data-break-before=\"" <> name <> "\"] { page-break-before: always; break-before: " <> name <> "; }"
         | k <- Set.toAscList (hcBreakKinds cfg),
           Just name <- [breakName k]
         ]
  where
    -- a role a bold (italic) character style sets: its font is declared bold (italic)
    boldRoles = [r | HtmlCharStyle {hcsFont = Just r, hcsBold = True} <- Map.elems (hcCharStyles cfg)]
    italicRoles = [r | HtmlCharStyle {hcsFont = Just r, hcsItalic = True} <- Map.elems (hcCharStyles cfg)]
    selectorOf = \case
      "strong" -> "strong"
      "bold" -> "b"
      "italic" -> "i"
      name -> ".cs-" <> name
    -- what the element shows without a rule
    defaults = \case
      "strong" -> ["font-weight: bold"]
      "bold" -> ["font-weight: bold"]
      "italic" -> ["font-style: italic"]
      _ -> []
    declsOf name cs =
      [ "font-family: " <> T.intercalate ", " (families role <> families "body" <> ["serif"])
      | Just role <- [hcsFont cs]
      ]
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
    families role = case Map.lookup role (hcFonts cfg) of
      Just (ja, la) -> ["\"" <> family role "latin" <> "\"" | Just _ <- [la]] <> ["\"" <> family role "ja" <> "\"" | Just _ <- [ja]]
      Nothing -> []
    family role kind = "golem-" <> role <> "-" <> kind
    fontStack role = T.intercalate ", " (families role <> ["serif"])
