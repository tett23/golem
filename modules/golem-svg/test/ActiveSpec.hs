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
