{- | The tree of the pages of HTML and EPUB and its two ways of writing
(root ADR 0432): the HTML syntax for the HTML target and the XHTML syntax
for EPUB. Both write the same elements, attributes and text in the same
order; they differ only where the table of root ADR 0432 says.
-}
module Golem.Html.Markup
  ( Node (..),
    Attr,
    AttrValue (..),
    Syntax (..),
    element,
    text,
    newline,
    plainAttr,
    extensionOf,
    voidElements,
    writeNodes,
    writeDocument,
    attrValue,
  )
where

import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Lazy qualified as TL
import Data.Text.Lazy.Builder (Builder)
import Data.Text.Lazy.Builder qualified as B
import Golem.Syntax.Text (escapeXml)
import Numeric (showHex)

-- | A node of a page: an element, text, or a character reference.
data Node
  = Element !Text ![Attr] ![Node]
  | TextNode !Text
  | -- | a numeric character reference, written as @&#x...;@
    CharRef !Int
  deriving stock (Eq, Show)

-- | An attribute: its name and its value.
type Attr = (Text, AttrValue)

{- | The value of an attribute: text, or a link to a page of the book
whose extension is that of the syntax: the path relative to the page
without the extension, and the fragment.
-}
data AttrValue
  = Plain !Text
  | PageLink !Text !Text
  deriving stock (Eq, Show)

-- | The way a tree is written.
data Syntax = HtmlSyntax | XhtmlSyntax
  deriving stock (Eq, Show)

element :: Text -> [(Text, Text)] -> [Node] -> Node
element name attrs = Element name [(k, Plain v) | (k, v) <- attrs]

text :: Text -> Node
text = TextNode

newline :: Node
newline = TextNode "\n"

plainAttr :: Text -> Text -> Attr
plainAttr k v = (k, Plain v)

-- | The extension of the pages of a syntax.
extensionOf :: Syntax -> Text
extensionOf = \case
  HtmlSyntax -> "html"
  XhtmlSyntax -> "xhtml"

-- | The void elements of HTML: they have no end tag.
voidElements :: Set Text
voidElements = Set.fromList ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"]

-- | The text of an attribute value in a syntax, not escaped.
attrValue :: Syntax -> AttrValue -> Text
attrValue syntax = \case
  Plain t -> t
  PageLink base fragment -> base <> "." <> extensionOf syntax <> "#" <> fragment

-- | A page: the XML declaration in XHTML, the doctype, then the nodes.
writeDocument :: Syntax -> [Node] -> Text
writeDocument syntax ns = prolog <> "<!DOCTYPE html>\n" <> writeNodes syntax ns
  where
    prolog = case syntax of
      XhtmlSyntax -> "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
      HtmlSyntax -> ""

writeNodes :: Syntax -> [Node] -> Text
writeNodes syntax = TL.toStrict . B.toLazyText . foldMap (node syntax False)

node :: Syntax -> Bool -> Node -> Builder
node syntax inSvg = \case
  TextNode t -> B.fromText (escapeXml t)
  CharRef n -> "&#x" <> B.fromString (showHex n "") <> ";"
  Element name attrs children
    | not inSvg && Set.member name voidElements -> start <> (if syntax == XhtmlSyntax then "/>" else ">")
    | inSvg && null children -> start <> "/>"
    | otherwise -> start <> ">" <> foldMap (node syntax svg) children <> "</" <> B.fromText name <> ">"
    where
      -- the elements inside svg are foreign: an empty one closes itself in both syntaxes
      svg = inSvg || name == "svg"
      start = "<" <> B.fromText name <> foldMap attr (attributes syntax attrs)
  where
    attr (k, v) = " " <> B.fromText k <> "=\"" <> B.fromText (escapeXml (attrValue syntax v)) <> "\""

{- | The attributes as a syntax writes them: XHTML writes them all; HTML
leaves out the namespaces and xml:lang, and writes the epub:type of EPUB
as the role of DPUB-ARIA of the same meaning (root ADR 0432).
-}
attributes :: Syntax -> [Attr] -> [Attr]
attributes XhtmlSyntax attrs = attrs
attributes HtmlSyntax attrs = concatMap one attrs
  where
    hasRole = any ((== "role") . fst) attrs
    one (k, v)
      | k == "xmlns" || "xmlns:" `T.isPrefixOf` k || k == "xml:lang" = []
      | k == "epub:type" = [("role", Plain (T.unwords (map ("doc-" <>) (T.words (attrValue HtmlSyntax v))))) | not hasRole]
      | otherwise = [(k, v)]
