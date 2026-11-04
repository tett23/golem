-- | The active content that HTML and EPUB refuse in SVG figures (docs/adr ADR 0039).
module ActiveSpec (tests) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.Either (isLeft)
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Golem.Svg.Active
import Test.Tasty
import Test.Tasty.HUnit

-- | An SVG whose root is on the first line, the body after a newline (so it starts at line 2, column 1).
svg :: Text -> BS.ByteString
svg body = TE.encodeUtf8 ("<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" width=\"10\" height=\"10\">\n" <> body <> "\n</svg>")

found :: Text -> [(Text, Int, Int)]
found body = case activeContent (svg body) of
  Right as -> [(acName a, acLine a, acColumn a) | a <- as]
  Left why -> error (show why)

names :: Text -> [Text]
names body = [n | (n, _, _) <- found body]

tests :: TestTree
tests =
  testGroup "active content (docs/adr ADR 0039)" $
    [ testCase "an empty script element is returned with its name and place" $
        found "  <script/>" @?= [("script", 2, 3)],
      testCase "a script in another namespace is returned too" $
        names "<h:script xmlns:h=\"http://www.w3.org/1999/xhtml\"/>" @?= ["script"],
      testCase "an onload attribute is returned, in any case" $ do
        found "<rect onload=\"\"/>" @?= [("onload", 2, 7)]
        names "<rect ONLOAD=\"\"/>" @?= ["ONLOAD"],
      testCase "href to #a passes, href to another file is returned; xlink:href too" $ do
        names "<use href=\"#a\"/>" @?= []
        names "<use href=\"other.svg\"/>" @?= ["href"]
        names "<use xlink:href=\"#a\"/>" @?= []
        names "<use xlink:href=\"other.svg#a\"/>" @?= ["xlink:href"],
      testCase "an empty foreignObject is returned, and the other embedding elements" $ do
        names "<foreignObject/>" @?= ["foreignObject"]
        names "<iframe/><embed/><object/><handler/><listener/>" @?= ["iframe", "embed", "object", "handler", "listener"],
      testCase "set and animate of href or an event are returned; of other attributes they pass" $ do
        names "<set attributeName=\"href\" to=\"#a\"/>" @?= ["set"]
        names "<animate attributeName=\"xlink:href\"/>" @?= ["animate"]
        names "<set attributeName=\"onclick\"/>" @?= ["set"]
        names "<animate attributeName=\"x\"/>" @?= [],
      testCase "@import and url() outside the document are returned from style elements and attributes; url(#g) passes" $ do
        found "<style>@import \"a.css\";\nrect { fill: url(x.svg#a) }</style>" @?= [("@import", 2, 8), ("url()", 3, 14)]
        names "<style>rect { fill: url(#g) }</style>" @?= []
        names "<rect style=\"fill: url(x.svg#a)\"/>" @?= ["url()"]
        names "<rect style=\"fill: url( '#g' )\"/>" @?= []
        names "<style>/* url(x.svg) */ rect { fill: URL(y.svg) }</style>" @?= ["url()"],
      testCase "text that is not outlined and @font-face pass (unlike the subset of the PDF)" $
        names "<style>@font-face { font-family: a; src: local(a) }</style><text>a</text>" @?= [],
      testCase "what is found is in the order of the document" $
        names "<rect onclick=\"\" href=\"a.svg\"/><script/><foreignObject onload=\"\"/>" @?= ["onclick", "href", "script", "foreignObject", "onload"],
      testCase "an SVG that is not XML, not UTF-8 or with an internal subset cannot be checked" $ do
        assertBool "broken" (isLeft (activeContent "<svg"))
        assertBool "latin-1" (isLeft (activeContent "<svg xmlns=\"http://www.w3.org/2000/svg\">\xE9</svg>"))
        assertBool "subset" (isLeft (activeContent "<!DOCTYPE svg [<!ENTITY a \"b\">]><svg xmlns=\"http://www.w3.org/2000/svg\"/>"))
    ]
      <> cssTokenTests
      <> [testGroup "external references beyond href (docs/adr/0158)" beyondHrefTests]

{- | CSS read as its tokenizer reads it: what a browser loads is found, and
nothing hides it (security audit 2026-10-24).
-}
cssTokenTests :: [TestTree]
cssTokenTests =
  [ testCase "a url() between two strings that hold /* and */ is found, at its place" $
      found "<style>a{content:\"/*\"} rect{fill:url(https://evil.example/p.svg#g)} b{content:\"*/\"}</style>" @?= [("url()", 2, 34)],
    testCase "the same in a style attribute" $
      names "<rect style=\"--a:'/*';fill:url(https://evil.example/p.svg#g);--b:'*/'\"/>" @?= ["url()"],
    testCase "an escaped quote does not end a string" $
      names "<style>a{content:\"\\\" /*\"} rect{fill:url(x.svg)} b{content:\"*/\"}</style>" @?= ["url()"],
    testCase "url written with a CSS escape is found, at the backslash" $
      found "<style>rect{fill:\\75 rl(https://evil.example/p.svg#g)}</style>" @?= [("url()", 2, 18)],
    testCase "@import written with a CSS escape is found" $
      names "<style>@\\69mport \"https://evil.example/x.css\";</style>" @?= ["@import"],
    testCase "an escape of a letter that is not hexadecimal is the letter" $
      names "<style>rect{fill:\\u\\r\\l(x.svg)}</style>" @?= ["url()"],
    testCase "url(#g) written with escapes passes" $
      names "<style>rect{fill:\\75 rl(\\23 g)}</style>" @?= [],
    testCase "a url() in a comment is not found, with or without strings before it" $ do
      names "<style>/* url(x.svg) */</style>" @?= []
      names "<style>a{content:\"x\"} /* url(x.svg) \" */</style>" @?= []
  ]

{- | The forms of external references beyond the table of docs/adr/0039 that
the security audits of 2026-10-24 (C9) and 2026-11-05 (V-02) found
(docs/adr/0158).
-}
beyondHrefTests :: [TestTree]
beyondHrefTests =
  [ testCase "url() outside the document in a presentation attribute is returned; fill, filter, clip-path, mask, marker-start, cursor" $
      forM_ ["fill", "filter", "clip-path", "mask", "marker-start", "cursor"] $ \a ->
        found ("<rect " <> a <> "=\"url(https://example.invalid/a#g)\"/>") @?= [("url()", 2, 7)],
    testCase "url(#g) in a presentation attribute passes, in any case and with spaces and quotes" $ do
      names "<rect fill=\"url(#g)\"/>" @?= []
      names "<rect fill=\"URL( '#g' )\"/>" @?= [],
    testCase "url written with a CSS escape in an attribute is returned" $
      names "<rect fill=\"u\\72l(https://example.invalid/a)\"/>" @?= ["url()"],
    testCase "image-set() and -webkit-image-set() are returned" $ do
      names "<rect style=\"background: image-set('https://example.invalid/a.png' 1x)\"/>" @?= ["image-set()"]
      names "<rect style=\"background: -webkit-image-set('https://example.invalid/a.png' 1x)\"/>" @?= ["image-set()"]
      names "<style>rect { background: image-set('a.png' 1x) }</style>" @?= ["image-set()"],
    testCase "an xml-stylesheet instruction before the root is returned at its place" $
      found' "<?xml version=\"1.0\"?>\n<?xml-stylesheet type=\"text/css\" href=\"https://example.invalid/a.css\"?>\n<svg xmlns=\"http://www.w3.org/2000/svg\"/>"
        @?= [("xml-stylesheet", 2, 1)],
    testCase "an xml-stylesheet instruction in an element, or in upper case, is returned" $ do
      found "<g><?xml-stylesheet href=\"https://example.invalid/a.css\"?></g>" @?= [("xml-stylesheet", 2, 4)]
      names "<?XML-STYLESHEET href=\"a.css\"?>" @?= ["xml-stylesheet"]
      found' "<svg xmlns=\"http://www.w3.org/2000/svg\"/>\n<?xml-stylesheet href=\"a.css\"?>" @?= [("xml-stylesheet", 2, 1)],
    testCase "other instructions and the XML declaration pass" $ do
      names "<?xpacket begin=\"\"?>" @?= []
      found' "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<?xpacket begin=\"\"?><svg xmlns=\"http://www.w3.org/2000/svg\"/>" @?= [],
    testCase "set of style to a url() outside the document is returned by its to" $ do
      names "<set attributeName=\"style\" to=\"fill:url(https://example.invalid/a#g)\"/>" @?= ["url()"]
      names "<animate attributeName=\"fill\" values=\"url(#a);url(https://example.invalid/a#g)\"/>" @?= ["url()"]
      names "<set attributeName=\"style\" to=\"fill:red\"/>" @?= [],
    testCase "set of href under another prefix of XLink is returned, in any case" $ do
      names "<set xmlns:q=\"http://www.w3.org/1999/xlink\" attributeName=\"q:href\" to=\"javascript:void(0)\"/>" @?= ["set"]
      names "<set xmlns:q=\"http://www.w3.org/1999/xlink\" attributeName=\"Q:HREF\" to=\"javascript:void(0)\"/>" @?= ["set"]
      names "<animate attributeName=\"z:onclick\"/>" @?= ["animate"],
    testCase "an element of XHTML is returned, outside foreignObject too" $
      found "<h:img xmlns:h=\"http://www.w3.org/1999/xhtml\" src=\"https://example.invalid/a.png\"/>" @?= [("img", 2, 1)],
    testCase "Inkscape's sodipodi:namedview and RDF in metadata pass" $
      names
        "<sodipodi:namedview xmlns:sodipodi=\"http://sodipodi.sourceforge.net/DTD/sodipodi-0.dtd\" pagecolor=\"#ffffff\"/><metadata><rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\" xmlns:cc=\"http://creativecommons.org/ns#\"><cc:Work rdf:about=\"\"/></rdf:RDF></metadata>"
        @?= [],
    testCase "what is found, instructions included, is in the order of the document" $
      names "<rect fill=\"url(a.svg#g)\"/><?xml-stylesheet href=\"a.css\"?><h:p xmlns:h=\"http://www.w3.org/1999/xhtml\"/><rect onclick=\"\"/>"
        @?= ["url()", "xml-stylesheet", "p", "onclick"]
  ]
  where
    found' b = case activeContent (TE.encodeUtf8 b) of
      Right as -> [(acName a, acLine a, acColumn a) | a <- as]
      Left why -> error (show why)
