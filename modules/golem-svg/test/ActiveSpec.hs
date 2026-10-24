-- | The active content that HTML and EPUB refuse in SVG figures (docs/adr ADR 0039).
module ActiveSpec (tests) where

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
tests = testGroup "active" [tests2018, auditTests]

tests2018 :: TestTree
tests2018 =
  testGroup
    "active content (docs/adr ADR 0039)"
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

-- | Candidates of the security audit of 2026-10-24: each is something a browser loads.
auditTests :: TestTree
auditTests =
  testGroup
    "security audit 2026-10-24"
    [ testCase "A-S2: a url() between two CSS strings that hold /* and */ is found" $
        names "<style>a{content:\"/*\"} rect{fill:url(https://evil.example/p.svg#g)} b{content:\"*/\"}</style>" @?= ["url()"],
      testCase "A-S2: the same in a style attribute" $
        names "<rect style=\"--a:'/*';fill:url(https://evil.example/p.svg#g);--b:'*/'\"/>" @?= ["url()"],
      testCase "A-S3: url written with a CSS escape is found" $
        names "<style>rect{fill:\\75 rl(https://evil.example/p.svg#g)}</style>" @?= ["url()"],
      testCase "A-S3: @import written with a CSS escape is found" $
        names "<style>@\\69mport \"https://evil.example/x.css\";</style>" @?= ["@import"],
      testCase "A-S4: image-set with a string is found" $
        names "<style>rect{background:image-set(\"https://evil.example/x.png\" 1x)}</style>" @?= ["image-set"],
      testCase "A-S5: a presentation attribute with an external url() is found" $
        names "<rect fill=\"url(https://evil.example/p.svg#g)\"/>" @?= ["fill"],
      testCase "A-S6: an xml-stylesheet processing instruction is found" $
        case activeContent (TE.encodeUtf8 "<?xml-stylesheet type=\"text/css\" href=\"https://evil.example/x.css\"?><svg xmlns=\"http://www.w3.org/2000/svg\"/>") of
          Right as -> map acName as @?= ["xml-stylesheet"]
          Left why -> assertFailure (show why),
      testCase "A-S7: an XHTML img with an external src is found" $
        names "<h:img xmlns:h=\"http://www.w3.org/1999/xhtml\" src=\"https://evil.example/t.png\"/>" @?= ["src"],
      testCase "A-S8: set that animates style to an external url() is found" $
        names "<rect><set attributeName=\"style\" to=\"fill:url(https://evil.example/p.svg#g)\"/></rect>" @?= ["set"],
      testCase "A-S9: set that animates href through another prefix of the XLink namespace is found" $
        names "<a xmlns:q=\"http://www.w3.org/1999/xlink\"><set attributeName=\"q:href\" to=\"javascript:alert(1)\"/></a>" @?= ["set"]
    ]
