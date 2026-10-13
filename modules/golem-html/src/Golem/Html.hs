{- | XHTML and CSS output (golem-html ADR 0001). Pages are polyglot XHTML
so that EPUB can use them unchanged.
-}
module Golem.Html
  ( HtmlConfig (..),
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
import Data.Maybe (fromMaybe, mapMaybe)
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
    hcStrongAs :: !Text, -- bold or italic
    hcSwatches :: !(Map Text (Int, Int, Int, Int)),
    hcCharStyles :: !(Map Text (Maybe Text)), -- style -> font role
    hcFonts :: !(Map Text (Maybe FilePath, Maybe FilePath)), -- role -> (ja, latin)
    hcBoldFont :: !(Maybe Text), -- the font role of b (golem-driver ADR 0004)
    hcItalicFont :: !(Maybe Text), -- the font role of i
    hcBibliography :: !(Map Text Text), -- key -> formatted entry
    hcDev :: !Bool,
    -- | [verse] of style.toml as CSS lengths, and the stanza gap in lines (docs/adr ADR 0003)
    hcVerseIndent :: !Text,
    hcVerseHang :: !Text,
    hcStanzaGap :: !Int,
    -- | [composition.ruby] as CSS ruby-align values (golem-layout ADR 0009)
    hcRubyMonoAlign :: !Text,
    hcRubyGroupAlign :: !Text,
    hcRubyBaseSpacing :: !Text
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
      body = T.concat (map (block c) bs) <> notesSection c d
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

block :: Ctx -> Block -> Text
block c (Block sp lbl body) = case body of
  Paragraph is -> "<p" <> idAttr lbl <> ">" <> inlines c is <> "</p>\n" <> sidenotes c is
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
        cap = T.concat [inlines c is | Block _ _ (Paragraph is) <- figCaption f]
     in "<figure" <> idAttr lbl <> ">\n<img src=\"" <> relLink (cHere c) (T.unpack (webSource f)) <> "\" alt=\"" <> escapeXml (figAlt f) <> "\"/>\n<figcaption>" <> num <> cap <> "</figcaption>\n</figure>\n"
  VerseBlock stanzas ->
    "<div class=\"verse\""
      <> idAttr lbl
      <> ">\n"
      <> T.concat ["<p>" <> T.intercalate "<br/>\n" ["<span>" <> inlines c l <> "</span>" | l <- st] <> "</p>\n" | st <- stanzas]
      <> "</div>\n"
      <> sidenotes c (concat (concat stanzas))
  ChannelOutput (TocOutput d) -> toc c (Just d)
  ChannelOutput IndexOutput -> index c
  ChannelOutput BibliographyOutput ->
    "<ol class=\"bibliography\">\n"
      <> T.concat
        [ "<li id=\"cite-" <> escapeXml k <> "\">" <> escapeXml (fromMaybe k (Map.lookup k (hcBibliography (cCfg c)))) <> "</li>\n"
        | (k, _) <- bookCitations (cBook c)
        ]
      <> "</ol>\n"

item :: Ctx -> Maybe Integer -> ListItem -> Text
item c value (ListItem _ bs) =
  "<li" <> maybe "" (\n -> " value=\"" <> T.pack (show n) <> "\"") value <> ">" <> case bs of
    [Block _ _ (Paragraph is)] -> inlines c is <> "</li>\n"
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
  Strong _ xs -> "<strong>" <> inlines c xs <> "</strong>"
  Bold _ xs -> "<b>" <> inlines c xs <> "</b>"
  Italic _ xs -> "<i>" <> inlines c xs <> "</i>"
  Ruby _ _ segs ->
    -- several segments, or one base character, are mono ruby (golem-layout ADR 0009)
    (if length segs >= 2 || T.length (T.concat [foldMap inlineText b | RubySegment b _ <- segs]) == 1 then "<ruby class=\"mono\">" else "<ruby>")
      <> T.concat [inlines c b <> "<rp>（</rp><rt>" <> maybe "" escapeXml r <> "</rt><rp>）</rp>" | RubySegment b r <- segs]
      <> "</ruby>"
  Kenten _ sh xs -> "<span class=\"kenten kenten-" <> escapeXml (fromMaybe "default" sh) <> "\">" <> inlines c xs <> "</span>"
  Color _ s xs -> "<span class=\"swatch-" <> escapeXml s <> "\">" <> inlines c xs <> "</span>"
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
  where
    styleOf = \case
      "kanji-digits" -> StyleKanjiDigits
      "tcy" -> StyleTcy
      _ -> StyleKanji

tshow :: (Show a) => a -> Text
tshow = T.pack . show

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
  Paragraph is -> deep is
  Heading _ _ is -> deep is
  BulletList items -> concatMap (concatMap blockNotes . itemBlocks) items
  OrderedList items -> concatMap (concatMap blockNotes . itemBlocks) items
  DefList gs -> concatMap (\(DefGroup ts ds) -> concatMap deep ts <> concatMap (concatMap blockNotes) ds) gs
  Table _ h rows -> concatMap deep h <> concatMap (concatMap deep) rows
  FigureBlock f -> concatMap blockNotes (figCaption f)
  VerseBlock stanzas -> concatMap (concatMap deep) stanzas
  _ -> []
  where
    deep = concatMap (\i -> i : nested i)
    nested = \case
      Strong _ xs -> deep xs
      Bold _ xs -> deep xs
      Italic _ xs -> deep xs
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
    [ "@font-face { font-family: \"" <> family role kind <> "\"; src: url(\"" <> T.pack (fontOut p) <> "\");" <> (if Just role == hcItalicFont cfg then " font-style: italic;" else "") <> " }"
    | (role, (ja, la)) <- Map.toAscList (hcFonts cfg),
      (kind, Just p) <- [("latin" :: Text, la), ("ja", ja)]
    ]
      <> [ "body { font-family: " <> fontStack "body" <> "; }",
           "body.vertical { writing-mode: vertical-rl; -epub-writing-mode: vertical-rl; }",
           "strong { font-weight: " <> (if hcStrongAs cfg == "italic" then "normal; font-style: italic" else "bold") <> "; }",
           ".tcy { text-combine-upright: all; -epub-text-combine: horizontal; }",
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
           T.strip (T.pack (S.styleToCss S.pygments)),
           ".sidenote { font-size: 0.85em; }",
           "@media (min-width: 60em) { .sidenote { float: right; clear: right; width: 14em; margin-right: -16em; } }",
           -- verse (docs/adr ADR 0003): lines hang; br is for readers without CSS
           ".verse { margin-inline-start: " <> hcVerseIndent cfg <> "; }",
           ".verse p { margin: 0; text-indent: 0; }"
         ]
      <> [".verse p + p { margin-block-start: 1em; }" | hcStanzaGap cfg > 0]
      <> [ ".verse span { display: block; padding-inline-start: " <> hcVerseHang cfg <> "; text-indent: -" <> hcVerseHang cfg <> "; }",
           ".verse br { display: none; }"
         ]
      <> [ ".swatch-" <> name <> " { color: rgb(" <> tshow r <> ", " <> tshow g <> ", " <> tshow b <> "); }"
         | (name, cmyk) <- Map.toAscList (hcSwatches cfg),
           let (r, g, b) = cmykToRgb cmyk
         ]
      <> [ ".cs-" <> name <> " { font-family: " <> fontStack role <> "; }"
         | (name, Just role) <- Map.toAscList (hcCharStyles cfg)
         ]
      -- the bold and italic roles: the role's font is already bold or italic,
      -- so the browser does not synthesise it again (golem-driver ADR 0004)
      <> [ sel <> " { font-family: " <> fontStack role <> "; font-weight: normal; }"
         | Just role <- [hcBoldFont cfg],
           sel <- ["b"] <> ["strong" | hcStrongAs cfg == "bold"]
         ]
      <> [ sel <> " { font-family: " <> T.intercalate ", " (families role <> [fontStack "body"]) <> "; font-style: italic; }"
         | Just role <- [hcItalicFont cfg],
           sel <- ["i"] <> ["strong" | hcStrongAs cfg == "italic"]
         ]
  where
    families role = case Map.lookup role (hcFonts cfg) of
      Just (ja, la) -> ["\"" <> family role "latin" <> "\"" | Just _ <- [la]] <> ["\"" <> family role "ja" <> "\"" | Just _ <- [ja]]
      Nothing -> []
    family role kind = "golem-" <> role <> "-" <> kind
    fontStack role = T.intercalate ", " (families role <> ["serif"])
