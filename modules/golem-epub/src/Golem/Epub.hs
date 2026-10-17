{- | EPUB 3.3 packaging over the XHTML output (golem-epub ADR 0001).
Determinism of the zip container is deferred to v2.
-}
module Golem.Epub
  ( EpubConfig (..),
    EpubCreator (..),
    packageDocument,
    navDocument,
    containerXml,
    writeEpub,
  )
where

import Codec.Archive.Zip
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Char (toLower)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time.Calendar (Day, showGregorian)
import Golem.Doc.Assemble
import Golem.Doc.Numbering (numberSeparator)
import Golem.Html
import Golem.Syntax.Span
import System.FilePath (takeExtension, (</>))

data EpubCreator = EpubCreator
  { ecName :: !Text,
    ecReading :: !(Maybe Text),
    ecRole :: !Text
  }

data EpubConfig = EpubConfig
  { epIdentifier :: !Text, -- urn:isbn:... or the manifest id
    epTitle :: !Text,
    epTitleReading :: !(Maybe Text),
    epLanguage :: !Text,
    epDate :: !Day,
    epPublisher :: !(Maybe Text),
    epCreators :: ![EpubCreator],
    -- | dc:contributor, with the role as a MARC relator code (docs/adr ADR 0033)
    epContributors :: ![EpubCreator],
    epVertical :: !Bool
  }

containerXml :: Text
containerXml =
  T.unlines
    [ "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
      "<container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\">",
      "<rootfiles><rootfile full-path=\"OEBPS/package.opf\" media-type=\"application/oebps-package+xml\"/></rootfiles>",
      "</container>"
    ]

mediaType :: FilePath -> Text
mediaType p = case map toLower (takeExtension p) of
  ".xhtml" -> "application/xhtml+xml"
  ".css" -> "text/css"
  ".png" -> "image/png"
  ".jpg" -> "image/jpeg"
  ".jpeg" -> "image/jpeg"
  ".svg" -> "image/svg+xml"
  ".otf" -> "font/otf"
  ".ttf" -> "font/ttf"
  ".woff2" -> "font/woff2"
  _ -> "application/octet-stream"

itemId :: Int -> Text
itemId i = "item" <> T.pack (show i)

-- | The package document. Pages keep the order of the book (spine).
packageDocument :: EpubConfig -> [FilePath] -> [FilePath] -> Text
packageDocument cfg pages others =
  let items = zip [1 :: Int ..] (pages <> others)
      -- dc:creator or dc:contributor, its role and its reading (docs/adr ADR 0033)
      person element prefix (i, c) =
        let ident = prefix <> T.pack (show i)
         in [ "<dc:" <> element <> " id=\"" <> ident <> "\">" <> escapeXml (ecName c) <> "</dc:" <> element <> ">",
              "<meta refines=\"#" <> ident <> "\" property=\"role\" scheme=\"marc:relators\">" <> escapeXml (ecRole c) <> "</meta>"
            ]
              <> ["<meta refines=\"#" <> ident <> "\" property=\"file-as\">" <> escapeXml r <> "</meta>" | Just r <- [ecReading c]]
   in T.unlines $
        [ "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
          "<package xmlns=\"http://www.idpf.org/2007/opf\" version=\"3.0\" unique-identifier=\"bookid\" xml:lang=\"" <> escapeXml (epLanguage cfg) <> "\">",
          "<metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">",
          "<dc:identifier id=\"bookid\">" <> escapeXml (epIdentifier cfg) <> "</dc:identifier>",
          "<dc:title id=\"title\">" <> escapeXml (epTitle cfg) <> "</dc:title>"
        ]
          <> ["<meta refines=\"#title\" property=\"file-as\">" <> escapeXml r <> "</meta>" | Just r <- [epTitleReading cfg]]
          <> ["<dc:language>" <> escapeXml (epLanguage cfg) <> "</dc:language>"]
          <> concatMap (person "creator" "creator") (zip [1 :: Int ..] (epCreators cfg))
          <> concatMap (person "contributor" "contributor") (zip [1 :: Int ..] (epContributors cfg))
          <> ["<dc:publisher>" <> escapeXml p <> "</dc:publisher>" | Just p <- [epPublisher cfg]]
          <> [ "<meta property=\"dcterms:modified\">" <> T.pack (showGregorian (epDate cfg)) <> "T00:00:00Z</meta>",
               "</metadata>",
               "<manifest>",
               "<item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>"
             ]
          <> ["<item id=\"" <> itemId i <> "\" href=\"" <> escapeXml (T.pack p) <> "\" media-type=\"" <> mediaType p <> "\"/>" | (i, p) <- items]
          <> ["</manifest>", "<spine" <> (if epVertical cfg then " page-progression-direction=\"rtl\"" else "") <> ">"]
          <> ["<itemref idref=\"" <> itemId i <> "\"/>" | (i, p) <- items, p `elem` pages]
          <> ["</spine>", "</package>"]

-- | The navigation document: the TOC channel, nested by level.
navDocument :: EpubConfig -> FileTable -> Book -> Text
navDocument cfg ft book =
  T.unlines
    [ "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
      "<!DOCTYPE html>",
      "<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"http://www.idpf.org/2007/ops\" lang=\"" <> escapeXml (epLanguage cfg) <> "\" xml:lang=\"" <> escapeXml (epLanguage cfg) <> "\">",
      "<head><meta charset=\"UTF-8\"/><title>" <> escapeXml (epTitle cfg) <> "</title></head>",
      "<body>",
      "<nav epub:type=\"toc\" id=\"toc\">",
      "<h1>" <> escapeXml (epTitle cfg) <> "</h1>",
      nested (bookToc book),
      "</nav>",
      "</body>",
      "</html>"
    ]
  where
    entry e =
      "<a href=\""
        <> escapeXml (T.pack (pagePath ft (teFile e)))
        <> "#"
        <> escapeXml (teAnchor e)
        <> "\">"
        <> maybe "" (\n -> escapeXml (n <> numberSeparator (epLanguage cfg) n)) (teNumber e)
        <> escapeXml (T.concat (map inlineText (teTitle e)))
        <> "</a>"
    nested [] = "<ol><li><a href=\"#toc\">" <> escapeXml (epTitle cfg) <> "</a></li></ol>"
    nested es = "<ol>" <> go es <> "</ol>"
    go [] = ""
    go (e : rest) =
      let (children, after) = span ((> teLevel e) . teLevel) rest
       in "<li>" <> entry e <> (if null children then "" else "<ol>" <> go children <> "</ol>") <> "</li>" <> go after

-- | Writes the EPUB. Assets are read from the project root.
writeEpub :: FilePath -> FilePath -> EpubConfig -> FileTable -> Book -> XhtmlSite -> IO ()
writeEpub root out cfg ft book site = do
  assets <- mapM (\(o, src) -> (o,) <$> BS.readFile (root </> src)) (siteAssets site)
  let pages = map fst (sitePages site)
      others = "style.css" : map fst assets
      text p t = toEntry ("OEBPS" </> p) 0 (BL.fromStrict (TE.encodeUtf8 t))
      mimetype = (toEntry "mimetype" 0 "application/epub+zip") {eCompressionMethod = NoCompression}
      entries =
        [ mimetype,
          toEntry "META-INF/container.xml" 0 (BL.fromStrict (TE.encodeUtf8 containerXml)),
          text "package.opf" (packageDocument cfg pages others),
          text "nav.xhtml" (navDocument cfg ft book),
          text "style.css" (siteCss site)
        ]
          <> [text p t | (p, t) <- sitePages site]
          <> [toEntry ("OEBPS" </> p) 0 (BL.fromStrict b) | (p, b) <- assets]
      archive = emptyArchive {zEntries = entries}
  BL.writeFile out (fromArchive archive)
